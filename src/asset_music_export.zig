//! Writing the music out to look at: the three sound banks as SPC memory
//! images, their songs, phrases and patterns as text, the sound effects as
//! text, the instrument table as YAML and every sample as BRR and as 16-bit
//! PCM. A port of the old extract_music.py, down to the spacing.
//!
//! This is the read-only half. The old Python's music compiler would only accept
//! text that assembled back into exactly the ROM's bytes, so the sound banks
//! are still built straight from the ROM (asset_music.zig) and nothing here
//! has a way back in.
const std = @import("std");
const rom_mod = @import("rom.zig");
const yaml = @import("yaml.zig");

const Rom = rom_mod.Rom;
const Value = yaml.Value;
const Pair = yaml.Pair;

/// The sound RAM as a bank upload leaves it: bytes nothing wrote are
/// undefined, which matters because a reference into undefined memory is to
/// something another bank provides, and isn't printed.
const Memory = struct {
    bytes: [0x10000]u8 = @splat(0),
    defined: std.StaticBitSet(0x10000) = .empty,

    fn load(rom: Rom, bank_ea: u32) Memory {
        var m = Memory{};
        var ea = bank_ea;
        for (0..257) |_| {
            const n = rom.getWord(ea);
            const target = rom.getWord(ea + 2);
            if (n == 0) break;
            ea += 4;
            for (0..n) |i| {
                const a = (target + i) & 0xffff;
                m.bytes[a] = rom.getByte(ea);
                m.defined.set(a);
                ea += 1;
                if (ea & 0xffff < 0x8000) ea += 0x8000;
            }
        }
        return m;
    }

    fn byte(self: *const Memory, a: usize) u8 {
        return self.bytes[a & 0xffff];
    }

    fn word(self: *const Memory, a: usize) u16 {
        return @as(u16, self.byte(a)) | @as(u16, self.byte(a + 1)) << 8;
    }
};

const kEffectByteLength = [_]u8{ 1, 1, 2, 3, 0, 1, 2, 1, 2, 1, 1, 3, 0, 1, 2, 3, 1, 3, 3, 0, 1, 3, 0, 3, 3, 3, 1 };
const kEffectNames = [_][]const u8{
    "Instrument",      "Pan",              "PanFade",         "Vibrato",           "VibratoOff",
    "SongVolume",      "SongVolumeFade",   "Tempo",           "TempoFade",         "Transpose",
    "ChannelTranpose", "Tremolo",          "TremoloOff",      "Volume",            "VolumeFade",
    "Call",            "VibratoFade",      "PitchEnvelopeTo", "PitchEnvelopeFrom", "PitchEnvelopeOff",
    "FineTune",        "EchoEnable",       "EchoOff",         "EchoSetup",         "EchoVolumeFade",
    "PitchSlide",      "PercussionDefine",
};

fn noteName(buf: *[4]u8, note: u8) []const u8 {
    if (note == 72) return "-+-"; // don't key off
    if (note == 73) return "---"; // key off
    const keys = [_]*const [2]u8{ "C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-" };
    return std.fmt.bufPrint(buf, "{s}{d}", .{ keys[note % 12], note / 12 + 1 }) catch unreachable;
}

// ------------------------------------------------------------------ songs

const Kind = enum { song, song_list, phrase, pattern };

const Obj = struct {
    kind: Kind,
    ea: u16,
    imported: bool,
    /// The last slot of the song list that points here.
    index: usize = 0,
    text: std.ArrayList(u8) = .empty,
};

/// The walk through one bank: objects by address, and a queue of the ones
/// still to decode, taken lowest address first.
const Walk = struct {
    a: std.mem.Allocator,
    mem: *const Memory,
    objs: std.AutoArrayHashMapUnmanaged(u16, *Obj) = .empty,
    queue: std.ArrayList(u16) = .empty,

    fn get(self: *Walk, ea: u16, kind: Kind) !?*Obj {
        if (ea == 0) return null;
        if (ea < 256) return error.BadMusic;
        if (self.objs.get(ea)) |o| {
            if (o.kind != kind) return error.BadMusic;
            return o;
        }
        const o = try self.a.create(Obj);
        o.* = .{ .kind = kind, .ea = ea, .imported = !self.mem.defined.isSet(ea) };
        try self.objs.put(self.a, ea, o);
        if (!o.imported) try self.queue.append(self.a, ea);
        return o;
    }

    fn popLowest(self: *Walk) ?u16 {
        if (self.queue.items.len == 0) return null;
        var best: usize = 0;
        for (self.queue.items, 0..) |ea, i| {
            if (ea < self.queue.items[best]) best = i;
        }
        return self.queue.swapRemove(best);
    }

    fn lowest(self: *Walk) ?u16 {
        var best: ?u16 = null;
        for (self.queue.items) |ea| {
            if (best == null or ea < best.?) best = ea;
        }
        return best;
    }

    fn name(buf: []u8, o: ?*Obj) []const u8 {
        const obj = o orelse return "None";
        const prefix = switch (obj.kind) {
            .song => "Song",
            .song_list => "SongList",
            .phrase => "Phrase",
            .pattern => "Pattern",
        };
        return std.fmt.bufPrint(buf, "{s}_0x{x}", .{ prefix, obj.ea }) catch unreachable;
    }

    fn line(self: *Walk, o: *Obj, comptime fmt: []const u8, args: anytype) !void {
        try o.text.print(self.a, fmt ++ "\n", args);
    }

    fn decode(self: *Walk, o: *Obj, next_ea: ?u16) !void {
        const m = self.mem;
        var nb: [32]u8 = undefined;
        switch (o.kind) {
            .song_list => {},
            .phrase => {
                try self.line(o, "[Phrase_0x{x}]", .{o.ea});
                for (0..8) |i| try self.line(o, "{s}", .{name(&nb, try self.get(m.word(o.ea + i * 2), .pattern))});
            },
            .song => {
                var ea: usize = o.ea;
                var starts: std.ArrayList(usize) = .empty;
                var lines: std.ArrayList(u8) = .empty;
                while (true) {
                    try starts.append(self.a, ea);
                    const phrase = m.word(ea);
                    if (phrase == 0) break;
                    if (phrase < 0x100) {
                        const target = m.word(ea + 2);
                        if (std.mem.indexOfScalar(usize, starts.items, target) == null) return error.BadMusic;
                        const jmp = @divFloor(@as(i32, target) - @as(i32, @intCast(ea)), 2);
                        try lines.print(self.a, "PhraseLoop {d} {d}\n", .{ phrase, jmp });
                        ea += 4;
                    } else {
                        try lines.print(self.a, "{s}\n", .{name(&nb, try self.get(phrase, .phrase))});
                        ea += 2;
                    }
                }
                // The header waits for the end: the index isn't final until
                // the whole list has been read, which it has by now.
                o.text = lines;
            },
            .pattern => {
                try self.line(o, "[Pattern_0x{x}]", .{o.ea});
                var ea: usize = o.ea;
                while (true) {
                    if (ea != o.ea and next_ea != null and ea == next_ea.?) {
                        try self.line(o, "Fallthrough ", .{});
                        break;
                    }
                    var note_length: ?u8 = null;
                    var volume: ?u8 = null;
                    var cmd = m.byte(ea);
                    ea += 1;
                    if (cmd == 0) break;
                    if (cmd & 0x80 == 0) {
                        note_length = cmd;
                        cmd = m.byte(ea);
                        ea += 1;
                        if (cmd & 0x80 == 0) {
                            volume = cmd;
                            cmd = m.byte(ea);
                            ea += 1;
                        }
                    }
                    if (cmd == 0xef) {
                        const target = try self.get(m.word(ea), .pattern);
                        try self.line(o, "Call {s} {d}", .{ name(&nb, target), m.byte(ea + 2) });
                        ea += 3;
                    } else if (cmd >= 0xe0) {
                        if (cmd - 0xe0 >= kEffectNames.len or note_length != null or volume != null) return error.BadMusic;
                        try o.text.appendSlice(self.a, kEffectNames[cmd - 0xe0]);
                        try o.text.append(self.a, ' ');
                        for (0..kEffectByteLength[cmd - 0xe0]) |i| {
                            if (i != 0) try o.text.append(self.a, ' ');
                            try o.text.print(self.a, "{d}", .{m.byte(ea + i)});
                        }
                        try o.text.append(self.a, '\n');
                        ea += kEffectByteLength[cmd - 0xe0];
                    } else {
                        var key: [4]u8 = undefined;
                        try o.text.appendSlice(self.a, noteName(&key, cmd & 0x7f));
                        if (note_length) |l| try o.text.print(self.a, " {d: >2}", .{l}) else try o.text.appendSlice(self.a, " --");
                        if (volume) |v| try o.text.print(self.a, " {x: >2}", .{v}) else try o.text.appendSlice(self.a, " --");
                        try o.text.append(self.a, '\n');
                    }
                }
            },
        }
    }
};

const Bank = enum { intro, indoor, ending };

fn bankAddr(bank: Bank) u32 {
    return switch (bank) {
        .intro => 0x998000,
        .indoor => 0x9b8000,
        .ending => 0x9ad380,
    };
}

/// sound_xx.txt for one bank.
fn songText(a: std.mem.Allocator, mem: *const Memory, bank: Bank) ![]u8 {
    var w = Walk{ .a = a, .mem = mem };
    const count: usize = switch (bank) {
        .intro => (mem.word(0xd000) -% 0xd000) / 2,
        .indoor, .ending => (0xd046 - 0xd000) / 2,
    };
    const list = (try w.get(0xd000, .song_list)).?;
    var songs: std.ArrayList(?*Obj) = .empty;
    for (0..count) |i| {
        const s = try w.get(mem.word(0xd000 + i * 2), .song);
        if (s) |song| song.index = i;
        try songs.append(a, s);
    }
    const roots: []const struct { u16, Kind } = switch (bank) {
        .intro => &.{ .{ 0xD878, .phrase }, .{ 0xD8A8, .phrase }, .{ 0xD8B8, .phrase }, .{ 0xDf11, .phrase }, .{ 0xe37c, .phrase } },
        .indoor => &.{ .{ 0xDc5e, .phrase }, .{ 0xDc6e, .phrase }, .{ 0xe905, .pattern }, .{ 0xe94a, .phrase } },
        .ending => &.{.{ 0x2a10, .phrase }},
    };
    for (roots) |r| _ = try w.get(r[0], r[1]);

    while (w.popLowest()) |ea| {
        try w.decode(w.objs.get(ea).?, w.lowest());
    }

    // The song list itself.
    var nb: [32]u8 = undefined;
    try w.line(list, "[SongList_0x{x}]", .{list.ea});
    for (songs.items) |s| try w.line(list, "{s}", .{Walk.name(&nb, s)});

    const eas = try a.dupe(u16, w.objs.keys());
    std.mem.sort(u16, eas, {}, std.sort.asc(u16));
    var out: std.ArrayList(u8) = .empty;
    for (eas) |ea| {
        const o = w.objs.get(ea).?;
        if (o.imported) continue;
        if (o.kind == .song) try out.print(a, "# Song index {d}\n[Song_0x{x}]\n", .{ o.index, o.ea });
        try out.appendSlice(a, o.text.items);
        try out.append(a, '\n');
    }
    return out.toOwnedSlice(a);
}

// -------------------------------------------------------------- samples

/// Decodes a BRR sample to 16-bit PCM, the way the SPC's DSP does: blocks of
/// nine bytes, a header and sixteen 4-bit deltas run through one of four
/// prediction filters, until the block with the end flag.
fn decodeBrr(a: std.mem.Allocator, mem: *const Memory, start: usize) ![]i16 {
    var out: std.ArrayList(i16) = .empty;
    var old: i32 = 0;
    var older: i32 = 0;
    var ea = start;
    while (true) {
        const cmd = mem.byte(ea);
        const shift: u5 = @intCast(cmd >> 4);
        const filter = (cmd >> 2) & 3;
        for (0..16) |i| {
            const t: i32 = (mem.byte(ea + 1 + i / 2) >> (if (i & 1 != 0) 0 else 4)) & 0xf;
            var s: i32 = (t & 7) - (t & 8);
            if (shift <= 12) {
                s = (s << shift) >> 1;
            } else {
                s = (s >> 3) << 12;
            }
            s += switch (filter) {
                0 => 0,
                1 => old + ((-old) >> 4),
                2 => old * 2 + ((-old * 3) >> 5) - older + (older >> 4),
                else => old * 2 + ((-old * 13) >> 6) - older + ((older * 3) >> 4),
            };
            s = std.math.clamp(s, -0x8000, 0x7fff);
            s = (s & 0x3fff) - (s & 0x4000);
            older = old;
            old = s;
            try out.append(a, @intCast(s * 2));
        }
        ea += 9;
        if (cmd & 1 != 0) break;
    }
    return out.toOwnedSlice(a);
}

fn musicInfo(a: std.mem.Allocator, mem: *const Memory) ![]u8 {
    const I = struct {
        fn int(v: anytype) Value {
            return .{ .int = @intCast(v) };
        }
        fn map(al: std.mem.Allocator, pairs: []const Pair) !Value {
            return .{ .map = try al.dupe(Pair, pairs) };
        }
        fn adsr(m: *const Memory, ea: usize) [5]Pair {
            const adsr1 = m.byte(ea);
            const adsr2 = m.byte(ea + 1);
            return .{
                .{ .key = "decay", .value = int((adsr1 >> 4) & 7) },
                .{ .key = "attack", .value = int(adsr1 & 0xf) },
                .{ .key = "sustain_level", .value = int(adsr2 >> 5) },
                .{ .key = "sustain_rate", .value = int(adsr2 & 0x1f) },
                .{ .key = "vxgain", .value = int(m.byte(ea + 2)) },
            };
        }
    };

    var samples: [25]Value = undefined;
    for (&samples, 0..) |*s, i| {
        const start = mem.word(0x3c00 + i * 4);
        const rep = mem.word(0x3c00 + i * 4 + 2);
        // Two samples are copies of the one before and share its file.
        const file_idx: usize = switch (i) {
            10 => 9,
            20 => 19,
            else => i,
        };
        const file: Value = .{ .str = try std.fmt.allocPrint(a, "sound/sound{d}.pcm", .{file_idx}) };
        if (mem.byte(start) & 2 != 0) {
            const repeat = @divFloor(@as(i32, rep) - @as(i32, start), 9) * 16;
            s.* = try I.map(a, &.{ .{ .key = "file", .value = file }, .{ .key = "repeat", .value = I.int(repeat) } });
        } else s.* = try I.map(a, &.{.{ .key = "file", .value = file }});
    }

    var instruments: [25]Value = undefined;
    for (&instruments, 0..) |*v, i| {
        const ea = 0x3d00 + i * 6;
        const e = I.adsr(mem, ea + 1);
        v.* = try I.map(a, &.{ .{ .key = "sample", .value = I.int(mem.byte(ea)) }, e[0], e[1], e[2], e[3], e[4], .{ .key = "pitch_base", .value = I.int(@as(u16, mem.byte(ea + 4)) << 8 | mem.byte(ea + 5)) } });
    }

    var gate: [8]Value = undefined;
    for (&gate, 0..) |*v, i| v.* = I.int(mem.byte(0x3D96 + i));
    var volume: [16]Value = undefined;
    for (&volume, 0..) |*v, i| v.* = I.int(mem.byte(0x3D9E + i));

    var sfx: [25]Value = undefined;
    for (&sfx, 0..) |*v, i| {
        const ea = 0x3e00 + i * 9;
        const e = I.adsr(mem, ea + 5);
        v.* = try I.map(a, &.{
            .{ .key = "voll", .value = I.int(mem.byte(ea)) },
            .{ .key = "volr", .value = I.int(mem.byte(ea + 1)) },
            .{ .key = "pitch", .value = I.int(mem.word(ea + 2)) },
            .{ .key = "sample", .value = I.int(mem.byte(ea + 4)) },
            e[0],
            e[1],
            e[2],
            e[3],
            e[4],
            .{ .key = "pitch_base", .value = I.int(mem.byte(ea + 8)) },
        });
    }

    return yaml.emit(a, try I.map(a, &.{
        .{ .key = "samples", .value = .{ .list = &samples } },
        .{ .key = "instruments", .value = .{ .list = &instruments } },
        .{ .key = "note_gate_off", .value = .{ .list = &gate } },
        .{ .key = "note_volume", .value = .{ .list = &volume } },
        .{ .key = "sfx_instruments", .value = .{ .list = &sfx } },
    }));
}

// ---------------------------------------------------------- sound effects

fn sfxText(a: std.mem.Allocator, mem: *const Memory) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var items: std.ArrayList(u16) = .empty;
    const Port = struct { base: u16, num: usize, name: []const u8 };
    for ([_]Port{ .{ .base = 0x17c0, .num = 32, .name = "SfxPort1" }, .{ .base = 0x1820, .num = 63, .name = "SfxPort2" }, .{ .base = 0x191c, .num = 63, .name = "SfxPort3" } }) |p| {
        try out.print(a, "[{s}_0x{x}]\n", .{ p.name, p.base });
        const next_ea = p.base + p.num * 2;
        const echo_ea = next_ea + p.num;
        for (0..p.num) |i| {
            const ea = mem.word(p.base + i * 2);
            var buf: [16]u8 = undefined;
            const t = if (ea == 0) "None" else std.fmt.bufPrint(&buf, "Sfx_0x{x}", .{ea}) catch unreachable;
            if (ea != 0 and std.mem.indexOfScalar(u16, items.items, ea) == null) try items.append(a, ea);
            if (std.mem.eql(u8, p.name, "SfxPort1")) {
                try out.print(a, "{s},{d}\n", .{ t, mem.byte(next_ea + i) });
            } else {
                try out.print(a, "{s},{d},{d}\n", .{ t, mem.byte(next_ea + i), mem.byte(echo_ea + i) });
            }
        }
        try out.append(a, '\n');
    }
    // Effects nothing in the tables points at, but that are there all the
    // same: reached by falling through, or from code.
    for ([_]u16{ 0x1a5b, 0x1d1c, 0x1ee2, 0x1f13, 0x1f1c, 0x252d, 0x2533, 0x26a2, 0x277e, 0x279d, 0x27c9, 0x27f6, 0x2807, 0x2818, 0x2829, 0x2831, 0x284a }) |ea| {
        if (std.mem.indexOfScalar(u16, items.items, ea) == null) try items.append(a, ea);
    }
    std.mem.sort(u16, items.items, {}, std.sort.asc(u16));

    for (items.items, 0..) |start, k| {
        try out.print(a, "[Sfx_0x{x}]\n", .{start});
        const next: usize = if (k + 1 < items.items.len) items.items[k + 1] else 0;
        var ea: usize = start;
        while (true) {
            if (ea == next) {
                try out.appendSlice(a, "Fallthrough\n");
                break;
            }
            var b = mem.byte(ea);
            ea += 1;
            if (b == 0) break;
            var note_length: ?u8 = null;
            var vol_l: ?u8 = null;
            var vol_r: ?u8 = null;
            if (b & 0x80 == 0) {
                note_length = b;
                b = mem.byte(ea);
                ea += 1;
                if (b & 0x80 == 0) {
                    vol_l = b;
                    b = mem.byte(ea);
                    ea += 1;
                    if (b & 0x80 == 0) {
                        vol_r = b;
                        b = mem.byte(ea);
                        ea += 1;
                    }
                }
            }
            var key: [4]u8 = undefined;
            var slide_buf: [40]u8 = undefined;
            switch (b) {
                0xe0 => {
                    try out.print(a, "SetInstrument {d}\n", .{mem.byte(ea)});
                    ea += 1;
                },
                0xff => {
                    try out.appendSlice(a, "Restart\n");
                    break;
                },
                0xf9, 0xf1 => {
                    var note: ?[]const u8 = null;
                    if (b == 0xf9) {
                        note = noteName(&key, mem.byte(ea) & 0x7f);
                        ea += 1;
                    }
                    const slide = std.fmt.bufPrint(&slide_buf, "PitchSlide {d} {d} {d}", .{ mem.byte(ea), mem.byte(ea + 1), mem.byte(ea + 2) }) catch unreachable;
                    ea += 3;
                    try sfxLine(a, &out, note, note_length, vol_l, vol_r, slide);
                },
                else => try sfxLine(a, &out, noteName(&key, b & 0x7f), note_length, vol_l, vol_r, null),
            }
        }
        try out.append(a, '\n');
    }
    return out.toOwnedSlice(a);
}

fn sfxLine(a: std.mem.Allocator, out: *std.ArrayList(u8), note: ?[]const u8, len: ?u8, l: ?u8, r: ?u8, extra: ?[]const u8) !void {
    try out.appendSlice(a, note orelse ".  ");
    if (len) |v| try out.print(a, " {d: >2}", .{v}) else try out.appendSlice(a, " --");
    if (l) |v| try out.print(a, " {d: >3}", .{v}) else try out.appendSlice(a, " ---");
    if (r) |v| try out.print(a, " {d: >3}", .{v}) else try out.appendSlice(a, " ---");
    if (extra) |e| try out.print(a, " {s}", .{e});
    try out.append(a, '\n');
}

// ------------------------------------------------------------------ all

/// Writes every music file through `write(ctx, name, bytes)`. `a` should be
/// an arena; nothing is freed along the way.
pub fn exportMusic(a: std.mem.Allocator, rom: Rom, ctx: anytype, write: fn (@TypeOf(ctx), []const u8, []const u8) anyerror!void) !void {
    for (std.enums.values(Bank)) |bank| {
        const mem = try a.create(Memory);
        mem.* = Memory.load(rom, bankAddr(bank));
        try write(ctx, try std.fmt.allocPrint(a, "sound/{s}.spc", .{@tagName(bank)}), &mem.bytes);
        try write(ctx, try std.fmt.allocPrint(a, "sound_{s}.txt", .{@tagName(bank)}), try songText(a, mem, bank));
        if (bank != .intro) continue;
        for (0..25) |i| {
            const start = mem.word(0x3c00 + i * 4);
            const pcm = try decodeBrr(a, mem, start);
            const brr = try a.alloc(u8, pcm.len / 16 * 9);
            for (brr, 0..) |*b, k| b.* = mem.byte(start + k);
            try write(ctx, try std.fmt.allocPrint(a, "sound/sound{d}.pcm.brr", .{i}), brr);
            const le = try a.alloc(u8, pcm.len * 2);
            for (pcm, 0..) |s, k| std.mem.writeInt(i16, le[k * 2 ..][0..2], s, .little);
            try write(ctx, try std.fmt.allocPrint(a, "sound/sound{d}.pcm", .{i}), le);
        }
        try write(ctx, "music_info.yaml", try musicInfo(a, mem));
        try write(ctx, "sfx.txt", try sfxText(a, mem));
    }
}
