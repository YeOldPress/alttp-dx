//! The sound banks.
//!
//! Each bank is an SPC memory image plus the list of regions to upload into
//! it. The ROM already stores it that way - a chain of [length, address,
//! bytes] blocks - and the asset is the same thing with the blocks recut.
//!
//! The recutting is the whole problem. compile_music assembles the bank from
//! a disassembly and then emits one block per contiguous run of bytes it
//! actually wrote, which is not the same as the ROM's own blocking: adjacent
//! ROM blocks merge, the sound driver at 0x0800 is left out because it is
//! code rather than song data, and a region ends where its last object ends
//! rather than where the ROM's block happens to stop.
//!
//! So the bytes are the ROM's, but which addresses count as written has to be
//! worked out by walking the song structures and recording how far each one
//! reaches. That walk is what this file is.

const std = @import("std");
const rom_mod = @import("rom.zig");

const Rom = rom_mod.Rom;

pub const Song = enum {
    intro,
    indoor,
    ending,

    pub fn assetName(self: Song) []const u8 {
        return switch (self) {
            .intro => "kSoundBank_intro",
            .indoor => "kSoundBank_indoor",
            .ending => "kSoundBank_ending",
        };
    }

    fn bankAddr(self: Song) u32 {
        return switch (self) {
            .intro => 0x998000,
            .indoor => 0x9b8000,
            .ending => 0x9ad380,
        };
    }
};

pub const kSongs = [_]Song{ .intro, .indoor, .ending };

/// The SPC's 64K address space as the bank leaves it.
const Image = struct {
    bytes: [0x10000]u8 = @splat(0),
    defined: [0x10000]bool = @splat(false),

    fn word(self: *const Image, ea: u32) u16 {
        return @as(u16, self.bytes[ea]) | (@as(u16, self.bytes[ea + 1]) << 8);
    }
};

/// Replays the ROM's upload blocks into a memory image. A zero length ends
/// the chain, and its address field is the entry point rather than a target.
fn loadBank(rom: Rom, start: u32) Image {
    var img = Image{};
    var ea = start;
    while (true) {
        const num = rom.getWord(ea);
        const target = rom.getWord(ea + 2);
        if (num == 0) return img;
        ea += 4;
        for (0..num) |i| {
            img.bytes[target + i] = rom.getByte(ea);
            img.defined[target + i] = true;
            ea += 1;
            // These streams run on past the end of a bank into the next.
            if (ea & 0xffff < 0x8000) ea += 0x8000;
        }
    }
}

/// Operand counts for the 0xe0..0xfa effect commands inside a pattern.
const kEffectByteLength = [_]u8{ 1, 1, 2, 3, 0, 1, 2, 1, 2, 1, 1, 3, 0, 1, 2, 3, 1, 3, 3, 0, 1, 3, 0, 3, 3, 3, 1 };

const Kind = enum { song, phrase, pattern };

const Item = struct {
    ea: u16,
    kind: Kind,

    fn less(_: void, a: Item, b: Item) std.math.Order {
        return std.math.order(a.ea, b.ea);
    }
};

const Walker = struct {
    img: *const Image,
    written: *[0x10000]bool,
    seen: std.AutoHashMap(u16, Kind),
    queue: std.PriorityQueue(Item, void, Item.less),
    alloc: std.mem.Allocator,

    fn mark(self: *Walker, from: u32, to: u32) void {
        const end = @min(to, 0x10000);
        for (from..end) |i| self.written[i] = true;
    }

    /// Records a reference. Addresses below 0x100 are the SPC's registers and
    /// zero page, never objects, and anything the bank never uploaded belongs
    /// to a different bank and is left alone.
    fn add(self: *Walker, ea: u16, kind: Kind) !void {
        if (ea == 0 or ea < 256) return;
        if (self.seen.contains(ea)) return;
        try self.seen.put(ea, kind);
        if (self.img.defined[ea]) try self.queue.push(self.alloc, .{ .ea = ea, .kind = kind });
    }

    /// A song is a list of phrase pointers. A value under 0x100 is a loop
    /// counter followed by a target, taking four bytes instead of two; zero
    /// ends the list.
    fn walkSong(self: *Walker, ea: u16) !void {
        var p: u32 = ea;
        while (true) {
            const ph = self.img.word(p);
            if (ph == 0) {
                p += 2;
                break;
            }
            if (ph < 0x100) {
                p += 4;
            } else {
                try self.add(ph, .phrase);
                p += 2;
            }
        }
        self.mark(ea, p);
    }

    /// A phrase is exactly eight pattern pointers, one per channel.
    fn walkPhrase(self: *Walker, ea: u16) !void {
        self.mark(ea, ea + 16);
        for (0..8) |i| try self.add(self.img.word(ea + @as(u32, @intCast(i)) * 2), .pattern);
    }

    /// A pattern is a command stream. It ends at a zero byte, or by running
    /// into whatever object comes next - the assembler treats that as falling
    /// through and stops, so the next object's address bounds this one.
    fn walkPattern(self: *Walker, ea: u16, next_ea: ?u16) !void {
        var p: u32 = ea;
        while (true) {
            if (p != ea and next_ea != null and p == next_ea.?) break;
            var cmd = self.img.bytes[p];
            p += 1;
            if (cmd == 0) break;
            // A note may be preceded by a length byte and then a volume byte.
            if (cmd & 0x80 == 0) {
                cmd = self.img.bytes[p];
                p += 1;
                if (cmd & 0x80 == 0) {
                    cmd = self.img.bytes[p];
                    p += 1;
                }
            }
            if (cmd == 0xef) {
                try self.add(self.img.word(p), .pattern);
                p += 3;
            } else if (cmd >= 0xe0) {
                p += kEffectByteLength[cmd - 0xe0];
            }
        }
        self.mark(ea, p);
    }
};

/// Sound effect scripts, which only the intro bank carries. Three port tables
/// hold pointers plus one or two bytes of per-effect data, and a handful of
/// scripts are reachable only from the driver, so they are listed by address.
const SfxTable = struct { base: u16, count: u16, has_echo: bool };
const kSfxTables = [_]SfxTable{
    .{ .base = 0x17c0, .count = 32, .has_echo = false },
    .{ .base = 0x1820, .count = 63, .has_echo = true },
    .{ .base = 0x191c, .count = 63, .has_echo = true },
};

const kExtraSfx = [_]u16{
    0x1a5b, 0x1d1c, 0x1ee2, 0x1f13, 0x1f1c, 0x252d, 0x2533, 0x26a2, 0x277e,
    0x279d, 0x27c9, 0x27f6, 0x2807, 0x2818, 0x2829, 0x2831, 0x284a,
};

/// Sample and instrument tables the intro bank defines at fixed addresses:
/// 25 sample pointers plus six terminators, 29 instruments followed by the
/// note gate and volume tables, and 25 sound effect instruments.
const kIntroTables = [_][2]u16{
    .{ 0x3c00, 0x3c70 },
    .{ 0x3d00, 0x3dae },
    .{ 0x3e00, 0x3ee1 },
};

fn walkSfx(alloc: std.mem.Allocator, img: *const Image, written: *[0x10000]bool) !void {
    var items: std.ArrayList(u16) = .empty;
    defer items.deinit(alloc);

    for (kSfxTables) |t| {
        const per_entry: u32 = if (t.has_echo) 2 else 1;
        const end = @as(u32, t.base) + @as(u32, t.count) * (2 + per_entry);
        for (t.base..end) |i| written[i] = true;

        for (0..t.count) |i| {
            const ea = img.word(t.base + @as(u32, @intCast(i)) * 2);
            if (ea != 0) try items.append(alloc, ea);
        }
    }
    try items.appendSlice(alloc, &kExtraSfx);

    std.mem.sort(u16, items.items, {}, std.sort.asc(u16));
    // The list is walked in address order and each script is bounded by the
    // next one, so duplicates would cut a script off at its own start.
    var uniq: usize = 0;
    for (items.items) |v| {
        if (uniq == 0 or items.items[uniq - 1] != v) {
            items.items[uniq] = v;
            uniq += 1;
        }
    }
    const list = items.items[0..uniq];

    for (list, 0..) |ea, i| {
        const next: u16 = if (i + 1 < list.len) list[i + 1] else 0;
        var p: u32 = ea;
        while (true) {
            if (p == next) break;
            var b = img.bytes[p];
            p += 1;
            if (b == 0) break;
            // Up to three prefix bytes: length, then left and right volume.
            if (b & 0x80 == 0) {
                b = img.bytes[p];
                p += 1;
                if (b & 0x80 == 0) {
                    b = img.bytes[p];
                    p += 1;
                    if (b & 0x80 == 0) {
                        b = img.bytes[p];
                        p += 1;
                    }
                }
            }
            if (b == 0xe0) {
                p += 1;
            } else if (b == 0xf9) {
                p += 4;
            } else if (b == 0xf1) {
                p += 3;
            } else if (b == 0xff) {
                break;
            }
        }
        for (ea..@min(p, 0x10000)) |k| written[k] = true;
    }
}

/// Emits one block per contiguous written run, ending with a zero length.
fn emit(alloc: std.mem.Allocator, img: *const Image, written: *const [0x10000]bool) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    var start: usize = 0;
    var i: usize = 0;
    while (start < 0x10000) {
        while (i < 0x10000 and written[i]) i += 1;
        const end = i;
        while (i < 0x10000 and !written[i]) i += 1;
        if (end == start) {
            start = i;
            continue;
        }
        const len = end - start;
        try out.appendSlice(alloc, &.{
            @intCast(len & 0xff),   @intCast(len >> 8),
            @intCast(start & 0xff), @intCast(start >> 8),
        });
        try out.appendSlice(alloc, img.bytes[start..end]);
        start = i;
    }
    try out.appendSlice(alloc, &.{ 0, 0 });
    return out.toOwnedSlice(alloc);
}

pub fn build(alloc: std.mem.Allocator, rom: Rom, song: Song) ![]u8 {
    var img = loadBank(rom, song.bankAddr());

    const written = try alloc.create([0x10000]bool);
    defer alloc.destroy(written);
    @memset(written, false);

    var w = Walker{
        .img = &img,
        .written = written,
        .seen = std.AutoHashMap(u16, Kind).init(alloc),
        .queue = std.PriorityQueue(Item, void, Item.less).initContext({}),
        .alloc = alloc,
    };
    defer w.seen.deinit();
    defer w.queue.deinit(alloc);

    // The song list is the root. The intro and light world banks size it from
    // the pointer stored at its head; the other two have a fixed count.
    const song_count: u32 = switch (song) {
        .intro => (@as(u32, img.word(0xd000)) - 0xd000) / 2,
        .indoor, .ending => (0xd046 - 0xd000) / 2,
    };
    w.mark(0xd000, 0xd000 + song_count * 2);
    for (0..song_count) |i| try w.add(img.word(0xd000 + @as(u32, @intCast(i)) * 2), .song);

    // Objects the driver reaches directly, which nothing in the song data
    // points at.
    switch (song) {
        .intro => for ([_]u16{ 0xd878, 0xd8a8, 0xd8b8, 0xdf11, 0xe37c }) |e| try w.add(e, .phrase),
        .indoor => {
            for ([_]u16{ 0xdc5e, 0xdc6e, 0xe94a }) |e| try w.add(e, .phrase);
            try w.add(0xe905, .pattern);
        },
        .ending => try w.add(0x2a10, .phrase),
    }

    while (w.queue.pop()) |item| {
        // Bounded by whatever object starts next, which is what makes a
        // pattern stop instead of running into its neighbor.
        const next_ea: ?u16 = if (w.queue.peek()) |n| n.ea else null;
        switch (item.kind) {
            .song => try w.walkSong(item.ea),
            .phrase => try w.walkPhrase(item.ea),
            .pattern => try w.walkPattern(item.ea, next_ea),
        }
    }

    if (song == .intro) {
        try walkSfx(alloc, &img, written);
        for (kIntroTables) |t| {
            for (t[0]..t[1]) |i| written[i] = true;
        }
        // The sample data is written straight after the tables, running from
        // 0x4000 for as long as the bank supplied bytes.
        var i: usize = 0x4000;
        while (i < 0x10000 and img.defined[i]) : (i += 1) written[i] = true;
    }

    return emit(alloc, &img, written);
}

const testing = std.testing;
const fileio = @import("fileio.zig");
const pack = @import("asset_pack.zig");

test "the sound banks match the reference asset file" {
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc") or !fileio.exists("zig-out/bin/zelda3_assets.dat"))
        return error.SkipZigTest;

    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();
    const dat = try fileio.readWholeFile(alloc, "zig-out/bin/zelda3_assets.dat");
    defer alloc.free(dat);
    var contents = try pack.read(alloc, dat);
    defer contents.deinit(alloc);

    for (kSongs) |song| {
        const got = try build(alloc, rom, song);
        defer alloc.free(got);
        const want = contents.find(song.assetName()).?;
        testing.expectEqualSlices(u8, want, got) catch |err| {
            std.debug.print("{s} differs\n", .{song.assetName()});
            return err;
        };
    }
}
