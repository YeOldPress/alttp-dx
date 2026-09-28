//! The sprite sheets as annotated PNGs, and back.
//!
//! Export draws each sprite's tiles in a labelled box in its own palette,
//! grouped by the first digit of the sprite number into sprites_0.png to
//! sprites_X.png, with a machine-readable tag under each box. Import finds
//! those tags, reads each tile back through the palette it was drawn in, and
//! rebuilds the game's 3bpp sheets. Plus all_sheets.png, every sheet in one
//! image, which is for looking at and is never read back.
//!
//! This is the old sprite_sheets.py's decode_sprite_sheets and load_sprite_sheets,
//! and draws the same pixels. Colors are held the way Pillow packs them,
//! red in the low byte, since that's how the old Python compares them.
const std = @import("std");
const rom_mod = @import("rom.zig");
const png = @import("png.zig");
const asset_tables = @import("asset_tables.zig");
const data = @import("asset_sprite_sheet_data.zig");

const Rom = rom_mod.Rom;

const kBigW = 148;
const kSheetCount = 108;

fn isHigh3bit(tileset: usize) bool {
    return switch (tileset) {
        0x52, 0x53, 0x5a, 0x5b, 0x5c, 0x5e, 0x5f => true,
        else => false,
    };
}

/// A sheet's raw 3bpp bytes: stored as is for the first 12, compressed after.
pub fn unpackedSheet(alloc: std.mem.Allocator, rom: Rom, tileset: usize) ![]u8 {
    if (tileset < 12) return rom.getBytes(alloc, asset_tables.kCompSpritePtrs[tileset], 0x600);
    const d = try rom_mod.decomp(alloc, rom, asset_tables.kCompSpritePtrs[tileset], false);
    return d.data;
}

/// A 128x32 sheet as pixel values: 0 to 7, or 8 to 15 for the sheets that
/// use the high half of a palette.
fn decode3bit(alloc: std.mem.Allocator, rom: Rom, tileset: usize) ![128 * 32]u8 {
    const d = try unpackedSheet(alloc, rom, tileset);
    defer alloc.free(d);
    if (d.len != 0x600) return error.UnexpectedSheetSize;
    const base: u8 = if (isHigh3bit(tileset)) 8 else 0;
    var dst: [128 * 32]u8 = undefined;
    for (0..64) |i| {
        const offs = i * 24;
        const toffs = (i % 16) * 8 + (i / 16) * 8 * 128;
        for (0..8) |y| {
            const d0 = d[offs + y * 2];
            const d1 = d[offs + y * 2 + 1];
            const d2 = d[offs + y + 16];
            for (0..8) |x| {
                const s: u3 = @intCast(x);
                dst[toffs + y * 128 + (7 - x)] = base + ((d0 >> s) & 1) + ((d1 >> s) & 1) * 2 + ((d2 >> s) & 1) * 4;
            }
        }
    }
    return dst;
}

// ------------------------------------------------------------ palettes

/// Python's list[start:stop], negative indices and all: a palette table
/// entry of -1 reads as an empty slice from the end, and the sheets show it.
fn pySlice(words: []const u16, start: i64, stop: i64) []const u16 {
    const n: i64 = @intCast(words.len);
    var a = if (start < 0) start + n else start;
    var b = if (stop < 0) stop + n else stop;
    a = std.math.clamp(a, 0, n);
    b = std.math.clamp(b, 0, n);
    if (b <= a) return words[0..0];
    return words[@intCast(a)..@intCast(b)];
}

const Palettes = struct {
    aux3: []u16,
    misc: []u16,
    dung_bg: []u16,
    main_spr: []u16,
    aux1: []u16,
    armor: []u16,

    fn load(alloc: std.mem.Allocator, rom: Rom) !Palettes {
        return .{
            .aux3 = try rom.getWords(alloc, 0x9BD39E, 84),
            .misc = try rom.getWords(alloc, 0x9BD446, 77),
            .dung_bg = try rom.getWords(alloc, 0x9BD734, 1800),
            .main_spr = try rom.getWords(alloc, 0x9BD218, 120),
            .aux1 = try rom.getWords(alloc, 0x9BD4E0, 168),
            .armor = try rom.getWords(alloc, 0x9BD308, 75),
        };
    }

    /// get_palette_subset: seven colors of a sprite palette.
    fn subset(self: Palettes, pal_idx: usize, j_in: ?i64) []const u16 {
        const j = j_in orelse 0;
        return switch (pal_idx) {
            0 => pySlice(self.aux3, j * 7, j * 7 + 7),
            1 => if (j < 11) pySlice(self.misc, j * 7, j * 7 + 7) else pySlice(self.dung_bg, (j - 11) * 90, (j - 11) * 90 + 7),
            2...9 => blk: {
                const o = j * 60 + @as(i64, @intCast((pal_idx - 2) >> 1)) * 15 + @as(i64, @intCast(pal_idx & 1)) * 8;
                break :blk pySlice(self.main_spr, o, o + 7);
            },
            10, 12 => pySlice(self.aux1, j * 7, j * 7 + 7),
            13 => pySlice(self.misc, j * 7, j * 7 + 7),
            14 => self.armor[1..8],
            15 => self.armor[9..16],
            else => &.{},
        };
    }
};

/// A SNES color the way Pillow packs an RGB int: red low.
fn snesToInt(c: u16) u32 {
    const r: u32 = c & 0x1f;
    const g: u32 = (c >> 5) & 0x1f;
    const b: u32 = (c >> 10) & 0x1f;
    return (r << 3 | r >> 2) | (g << 3 | g >> 2) << 8 | (b << 3 | b >> 2) << 16;
}

/// get_full_palette: the sprite's colors, plus the fixed ones the sheet's
/// frame, labels and empty cells are drawn in.
fn fullPalette(pals: Palettes, pal_idx: usize, pal_subidx: ?i64) [256]u32 {
    var rv: [256]u32 = @splat(0xe000e0);
    var n: usize = 0;
    const lead: usize = if (pal_idx & 1 != 0) 9 else 1;
    for (0..lead) |_| {
        rv[n] = 0x00fe00;
        n += 1;
    }
    for (pals.subset(pal_idx, pal_subidx)) |c| {
        rv[n] = snesToInt(c);
        n += 1;
    }
    var i: usize = 0;
    while (i < 128) : (i += 8) rv[i] = 0x808000;
    rv[251] = 0xe0c0c0; // blueish text
    rv[252] = 0xc0c0c0; // palette text
    rv[253] = 0xf0f0f0; // unallocated
    rv[254] = 0x404040; // lines
    rv[255] = 0xe0e0e0; // bg
    return rv;
}

// ------------------------------------------------------------- entries

/// An entry with its palette worked out: fixup_sprite_set_entry.
const Fixed = struct {
    e: data.Entry,
    tileset: usize,
    high: bool,
    skip_header: bool,
    pal_base: usize,
    pal_idx: usize,
    pal_subidx: ?i64,
    encoded_id: i64,
};

fn paletteSubidx(palset_idx: usize, dungeon_or_ow: u8, which: usize) ?i64 {
    const spmain: i64 = if (dungeon_or_ow == 1) 1 else 0;
    var sp0l: i64 = undefined;
    var sp0r: i64 = undefined;
    var sp5l: i64 = undefined;
    var sp6l: i64 = undefined;
    var sp6r: i64 = undefined;
    if (dungeon_or_ow == 2) {
        const d = data.kDungPalinfos[palset_idx];
        sp0l = d[1];
        sp5l = d[2];
        sp6l = d[3];
        sp0r = @divFloor(@as(i64, d[0]), 2) + 11;
        sp6r = 10;
    } else {
        sp5l = data.kOwSprPalInfo[palset_idx * 2];
        sp6l = data.kOwSprPalInfo[palset_idx * 2 + 1];
        sp0l = if (dungeon_or_ow == 1) 3 else 1;
        sp0r = if (dungeon_or_ow == 1) 9 else 7;
        sp6r = if (dungeon_or_ow == 1) 8 else 6;
    }
    const defs = [16]?i64{ sp0l, sp0r, spmain, null, spmain, null, spmain, null, null, null, sp5l, null, sp6l, sp6r, null, null };
    return defs[which];
}

fn fixEntries(out: []Fixed) void {
    var prev: ?Fixed = null;
    for (data.kEntries, 0..) |e, k| {
        const sprite_index: usize = if (e.name[0] != 'X') std.fmt.parseInt(usize, e.name[0..2], 16) catch 10000 else 10000;
        const tileset: usize = if (e.dungeon_or_ow != 3)
            data.kSpriteTilesets[@as(usize, e.tileset) + (if (e.dungeon_or_ow == 2) @as(usize, 64) else 0)][e.ss_idx]
        else
            e.tileset;
        const high = isHigh3bit(tileset);
        const pal_base: usize = e.pal_base orelse if (sprite_index < data.kSpriteInit_Flags3.len) (data.kSpriteInit_Flags3[sprite_index] >> 1) & 7 else 4;
        const pal_idx = pal_base * 2 + @intFromBool(high);
        const pal_subidx = paletteSubidx(e.palset_idx, e.dungeon_or_ow, pal_idx);
        var f = Fixed{ .e = e, .tileset = tileset, .high = high, .skip_header = false, .pal_base = pal_base, .pal_idx = pal_idx, .pal_subidx = pal_subidx, .encoded_id = 0 };
        if (prev) |p| {
            if (std.mem.eql(u8, p.e.name, e.name) and p.pal_idx == pal_idx and std.meta.eql(p.pal_subidx, pal_subidx)) f.skip_header = true;
        }
        const id: i64 = @as(i64, @intCast(pal_base)) | @as(i64, @intCast(tileset)) << 3 | @as(i64, @intFromBool(f.skip_header)) << 10 | (pal_subidx orelse 0) << 11;
        f.encoded_id = id << 8 | @mod(id + 41, 255);
        out[k] = f;
        prev = f;
    }
}

// ------------------------------------------------------------- drawing

/// A pixel buffer being built, BIGW or 128 wide, of palette indices or
/// colors depending on the stage.
fn drawLetter(dst: []u8, pitch: usize, dx: usize, dy: usize, ch: u8, color: u8) void {
    const col = (ch & 31) * 4;
    const row = (ch / 32) * 6;
    for (0..6) |y| {
        for (0..3) |x| {
            const bits = data.kFont3x5[row + y][(col + x) / 8];
            if (bits & (@as(u8, 0x80) >> @intCast((col + x) % 8)) != 0) {
                const o = (dy + y) * pitch + dx + x;
                if (o < dst.len) dst[o] = color;
            }
        }
    }
}

fn drawString(dst: []u8, pitch: usize, dx_in: usize, dy: usize, s: []const u8, color: u8) void {
    var dx = dx_in;
    for (s) |ch| {
        drawLetter(dst, pitch, dx, dy, ch, color);
        dx += 4;
    }
}

fn drawLetter32(dst: []u32, pitch: usize, dx: usize, dy: usize, ch: u8, color: u32) void {
    const col = (ch & 31) * 4;
    const row = (ch / 32) * 6;
    for (0..6) |y| {
        for (0..3) |x| {
            const bits = data.kFont3x5[row + y][(col + x) / 8];
            if (bits & (@as(u8, 0x80) >> @intCast((col + x) % 8)) != 0) dst[(dy + y) * pitch + dx + x] = color;
        }
    }
}

fn hline(dst: []u8, x1: usize, x2: usize, y: usize, color: u8) void {
    for (x1..x2 + 1) |x| dst[y * kBigW + x] = color;
}

fn vline(dst: []u8, x: usize, y1: usize, y2: usize, color: u8) void {
    for (y1..y2 + 1) |y| dst[y * kBigW + x] = color;
}

const Master = struct {
    /// Colored sheets for all_sheets.png, by tileset; null where unused.
    sheets24: [kSheetCount]?*[128 * 32]u32 = @splat(null),

    fn insert(self: *Master, alloc: std.mem.Allocator, tileset: usize, src: *const [128 * 32]u8, xp: usize, yp: usize, palette: *const [256]u32) !void {
        const sheet = self.sheets24[tileset] orelse blk: {
            const s = try alloc.create([128 * 32]u32);
            @memset(s, 0x00f000);
            self.sheets24[tileset] = s;
            break :blk s;
        };
        for (yp * 8..yp * 8 + 8) |y| {
            for (xp * 8..xp * 8 + 8) |x| {
                const o = y * 128 + x;
                sheet[o] = palette[src[o]];
            }
        }
    }
};

/// Appends one entry's header (if it has one) and box to `out`, as colors.
fn drawEntry(alloc: std.mem.Allocator, out: *std.ArrayList(u32), f: Fixed, rom: Rom, pals: Palettes, master: *Master) !void {
    const palette = fullPalette(pals, f.pal_idx, f.pal_subidx);
    var buf: [64]u8 = undefined;

    if (!f.skip_header) {
        var pal_name_buf: [48]u8 = undefined;
        var pal_name: []const u8 = undefined;
        if (f.high) {
            pal_name = try std.fmt.bufPrint(&pal_name_buf, "{d}R", .{f.pal_base});
        } else {
            pal_name = try std.fmt.bufPrint(&pal_name_buf, "{d}", .{f.pal_base});
        }
        if (f.pal_subidx) |sub| {
            var sub_buf: [16]u8 = undefined;
            const sub_text = if (!f.high and f.pal_base >= 1 and f.pal_base <= 3) (if (sub == 0) "LW" else "DW") else try std.fmt.bufPrint(&sub_buf, "{d}", .{sub});
            var joined_buf: [48]u8 = undefined;
            pal_name = try std.fmt.bufPrint(&joined_buf, "{s}-{s}", .{ pal_name, sub_text });
            @memcpy(pal_name_buf[0..pal_name.len], pal_name);
            pal_name = pal_name_buf[0..pal_name.len];
        }
        var header: [kBigW * 9]u8 = @splat(255);
        drawString(&header, kBigW, 1, 3, f.e.name[0..@min(22, f.e.name.len)], 254);
        for (0..7) |i| {
            const xx = kBigW - 37 + i * 5 - 9;
            for (3..8) |y| {
                for (xx..xx + 5) |x| header[y * kBigW + x] = @intCast(i + @as(usize, if (f.high) 9 else 1));
            }
        }
        drawString(&header, kBigW, kBigW - 9, 3, try std.fmt.bufPrint(&buf, "{d: >2}", .{f.tileset}), 252);
        drawString(&header, kBigW, kBigW - 45 - 1 - pal_name.len * 4, 3, pal_name, 252);
        for (header) |p| try out.append(alloc, palette[p]);
    }

    var big: [kBigW * 36]u8 = @splat(255);
    hline(&big, 1, 137, 0, 254);
    hline(&big, 1, 137, 34, 254);
    vline(&big, 1, 0, 34, 254);
    vline(&big, 137, 0, 34, 254);
    // The tag: the encoded id in pixels, low bit rightmost, ending at x 137.
    var v: u64 = @bitCast(f.encoded_id << 9 | 0x55);
    var x: usize = 137;
    while (v != 0 and x > 0) : (v >>= 1) {
        if (v & 1 != 0) big[35 * kBigW + x] = 253;
        x -= 1;
    }

    const src = try decode3bit(alloc, rom, f.tileset);
    for (0..64) |i| {
        const tx = i % 16;
        const ty = i / 16;
        const dst_offs = (ty * 8 + 1 + (ty >> 1)) * kBigW + tx * 8 + 2 + (tx >> 1);
        if (f.e.matrix[ty][tx] == '.') {
            for (0..8) |y| @memset(big[dst_offs + y * kBigW ..][0..8], 253);
        } else {
            for (0..8) |y| {
                for (0..8) |xx| big[dst_offs + y * kBigW + xx] = src[tx * 8 + ty * 8 * 128 + y * 128 + xx];
            }
            try master.insert(alloc, f.tileset, &src, tx, ty, &palette);
        }
    }
    drawString(&big, kBigW, kBigW - 9, 4, try std.fmt.bufPrint(&buf, "{X}x", .{f.e.ss_idx * 4}), 251);
    drawString(&big, kBigW, kBigW - 9, 4 + 17, try std.fmt.bufPrint(&buf, "{X}x", .{f.e.ss_idx * 4 + 2}), 251);

    // Collapse the half of the box nothing uses.
    var rows: []const u8 = &big;
    var collapsed: [kBigW * 36]u8 = undefined;
    const top_unused = std.mem.allEqual(u8, f.e.matrix[0], '.') and std.mem.allEqual(u8, f.e.matrix[1], '.');
    const bottom_unused = std.mem.allEqual(u8, f.e.matrix[2], '.') and std.mem.allEqual(u8, f.e.matrix[3], '.');
    if (top_unused) {
        @memcpy(collapsed[0..kBigW], big[0..kBigW]);
        @memcpy(collapsed[kBigW .. kBigW * 20], big[17 * kBigW ..]);
        rows = collapsed[0 .. kBigW * 20];
    } else if (bottom_unused) {
        @memcpy(collapsed[0 .. 18 * kBigW], big[0 .. 18 * kBigW]);
        @memcpy(collapsed[18 * kBigW .. 20 * kBigW], big[34 * kBigW ..]);
        rows = collapsed[0 .. kBigW * 20];
    }
    if (f.skip_header) {
        const mut: []u8 = @constCast(rows);
        drawString(mut, kBigW, kBigW - 9, rows.len / kBigW - 6, try std.fmt.bufPrint(&buf, "{d:0>2}", .{f.tileset}), 252);
    }
    for (rows) |p| try out.append(alloc, palette[p]);
}

fn toRgbBytes(alloc: std.mem.Allocator, colors: []const u32) ![]u8 {
    const out = try alloc.alloc(u8, colors.len * 3);
    for (colors, 0..) |c, i| out[i * 3 ..][0..3].* = .{ @truncate(c), @truncate(c >> 8), @truncate(c >> 16) };
    return out;
}

pub const kGroups = "0123456789ABCDEFX";

/// Writes sprites/sprites_0.png to sprites_X.png and sprites/all_sheets.png
/// through `write(name, bytes)`.
pub fn exportSheets(alloc: std.mem.Allocator, rom: Rom, ctx: anytype, write: fn (@TypeOf(ctx), []const u8, []const u8) anyerror!void) !void {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const pals = try Palettes.load(a, rom);
    const fixed = try a.alloc(Fixed, data.kEntries.len);
    fixEntries(fixed);
    var master = Master{};

    for (kGroups) |group| {
        var out: std.ArrayList(u32) = .empty;
        for (fixed) |f| {
            if (std.ascii.toUpper(f.e.name[0]) == group) try drawEntry(a, &out, f, rom, pals, &master);
        }
        if (out.items.len == 0) continue;
        const bytes = try png.encode(a, kBigW, @intCast(out.items.len / kBigW), .rgb, try toRgbBytes(a, out.items), &.{});
        var name_buf: [32]u8 = undefined;
        try write(ctx, try std.fmt.bufPrint(&name_buf, "sprites/sprites_{c}.png", .{group}), bytes);
    }

    // all_sheets.png: a title line, then each sheet under its own label.
    var all: std.ArrayList(u32) = .empty;
    try appendLabel(a, &all, "AUTO GENERATED DO NOT EDIT");
    for (master.sheets24, 0..) |sheet, k| {
        const s = sheet orelse continue;
        var label_buf: [32]u8 = undefined;
        try appendLabel(a, &all, try std.fmt.bufPrint(&label_buf, "Sheet {d}", .{k}));
        try all.appendSlice(a, s);
    }
    try write(ctx, "sprites/all_sheets.png", try png.encode(a, 128, @intCast(all.items.len / 128), .rgb, try toRgbBytes(a, all.items), &.{}));
}

fn appendLabel(a: std.mem.Allocator, out: *std.ArrayList(u32), text: []const u8) !void {
    var header: [128 * 8]u32 = @splat(0xf0f0f0);
    var dx: usize = 1;
    for (text) |ch| {
        drawLetter32(&header, 128, dx, 2, ch, 0x404040);
        dx += 4;
    }
    try out.appendSlice(a, &header);
}

// --------------------------------------------------------------- import

/// The game's 3bpp sheets, rebuilt from the edited PNGs: load_sprite_sheets
/// followed by encode_sheet_in_snes_format. Sheets no PNG covers are null.
pub const Imported = struct {
    sheets: [kSheetCount]?[24 * 16 * 4]u8 = @splat(null),
};

pub const ImportError = error{ BadSheet, OutOfMemory };

pub fn importSheets(alloc: std.mem.Allocator, images: []const ?png.Image, why: *[256]u8, why_len: *usize) ImportError!Imported {
    var sheet8: [kSheetCount]?*[128 * 32]u8 = @splat(null);
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    for (images, 0..) |maybe, gi| {
        const img = maybe orelse continue;
        const pitch: usize = img.width;
        const px = try a.alloc(u32, @as(usize, img.width) * img.height);
        for (0..img.height) |y| for (0..img.width) |x| {
            const c = img.rgbAt(x, y); // 0xRRGGBB
            px[y * pitch + x] = (c >> 16 & 0xff) | (c & 0xff00) | (c & 0xff) << 16;
        };

        var lut: [8]struct { color: u32, value: u8 } = undefined;
        var have_lut = false;
        var tag_pos: usize = 0;
        while (findTag(px, pitch, tag_pos)) |pos| {
            tag_pos = pos;
            const tag = decodeTag(px, pos) orelse return fail(why, why_len, "sprites_{c}.png: a sprite's tag under its box is damaged", .{kGroups[gi]});
            var h: usize = 1;
            while (pos >= pitch * (h + 1) and px[pos - pitch * (h + 1)] == 0x404040) h += 1;
            var rects: [2]struct { idx: usize, pos: usize } = undefined;
            var n_rects: usize = 0;
            if (h == 19) {
                if (px[pos - pitch * 2 - 1] == 0xe0e0e0) {
                    rects[0] = .{ .idx = 0, .pos = pos - 135 - pitch * 18 };
                } else if (px[pos - pitch * 18 - 1] == 0xe0e0e0) {
                    rects[0] = .{ .idx = 1, .pos = pos - 135 - pitch * 17 };
                } else return fail(why, why_len, "sprites_{c}.png: can't make out a half-height box", .{kGroups[gi]});
                n_rects = 1;
            } else if (h == 35) {
                rects[0] = .{ .idx = 0, .pos = pos - 135 - pitch * 34 };
                rects[1] = .{ .idx = 1, .pos = pos - 135 - pitch * 17 };
                n_rects = 2;
            } else return fail(why, why_len, "sprites_{c}.png: a box's frame is the wrong height", .{kGroups[gi]});

            const high = isHigh3bit(tag.tileset);
            if (!tag.headerless) {
                const lut_pos = pos - pitch * (h + 3) - 34;
                for (0..7) |i| lut[i] = .{ .color = px[lut_pos + 5 * i], .value = @intCast(i + @as(usize, if (high) 9 else 1)) };
                lut[7] = .{ .color = 0x808000, .value = 0 };
                have_lut = true;
            }
            if (!have_lut) return fail(why, why_len, "sprites_{c}.png: the first box has no palette above it", .{kGroups[gi]});
            if (tag.tileset >= kSheetCount) return fail(why, why_len, "sprites_{c}.png: tag names sheet {d}", .{ kGroups[gi], tag.tileset });

            for (rects[0..n_rects]) |r| {
                for (0..2) |y| for (0..16) |x| {
                    const src = r.pos + (y * 8 + (y >> 1)) * pitch + (x * 8 + (x >> 1));
                    const dst = (y + r.idx * 2) * 8 * 128 + x * 8;
                    if (isEmpty(px, pitch, src)) continue;
                    const sheet = sheet8[tag.tileset] orelse blk: {
                        const s = try a.create([128 * 32]u8);
                        @memset(s, 248);
                        sheet8[tag.tileset] = s;
                        break :blk s;
                    };
                    for (0..8) |yy| for (0..8) |xx| {
                        const pixel = px[src + yy * pitch + xx];
                        const v = lookup(&lut, pixel) orelse {
                            const rgb = (pixel & 0xff) << 16 | (pixel & 0xff00) | (pixel >> 16);
                            return fail(why, why_len, "sprites_{c}.png: color #{x:0>6} isn't in that sprite's palette", .{ kGroups[gi], rgb });
                        };
                        const o = dst + yy * 128 + xx;
                        if (sheet[o] != 248 and sheet[o] != v) return fail(why, why_len, "sprites_{c}.png: sheet {d} is drawn two different ways", .{ kGroups[gi], tag.tileset });
                        sheet[o] = v;
                    };
                };
            }
        }
    }

    var out = Imported{};
    for (sheet8, 0..) |maybe, t| {
        const s = maybe orelse continue;
        var result: [24 * 16 * 4]u8 = @splat(0);
        for (0..4) |y| for (0..16) |x| {
            const dp = (y * 16 + x) * 24;
            const sp = y * 8 * 128 + x * 8;
            for (0..8) |yy| for (0..8) |xx| {
                const b = s[sp + 128 * yy + 7 - xx];
                const sh: u3 = @intCast(xx);
                result[dp + 2 * yy] |= (b & 1) << sh;
                result[dp + 2 * yy + 1] |= ((b & 2) >> 1) << sh;
                result[dp + yy + 16] |= ((b & 4) >> 2) << sh;
            };
        };
        out.sheets[t] = result;
    }
    return out;
}

/// The old Python builds this as a dict, so a color shared by two swatches means
/// the later one, and the transparent teal always means 0.
fn lookup(lut: anytype, pixel: u32) ?u8 {
    if (pixel == 0x808000) return 0;
    var i: usize = 7;
    while (i > 0) {
        i -= 1;
        if (lut[i].color == pixel) return lut[i].value;
    }
    return null;
}

fn fail(why: *[256]u8, why_len: *usize, comptime fmt: []const u8, args: anytype) error{BadSheet} {
    const written: []const u8 = std.fmt.bufPrint(why, fmt, args) catch why;
    why_len.* = written.len;
    return error.BadSheet;
}

fn isEmpty(px: []const u32, pitch: usize, pos: usize) bool {
    for (0..8) |y| for (0..8) |x| if (px[pos + y * pitch + x] != 0xf0f0f0) return false;
    return true;
}

/// find_next_tag: the first scan goes pixel by pixel; after a tag is found
/// the next is looked for straight down the same column.
fn findTag(px: []const u32, pitch: usize, start: usize) ?usize {
    if (px.len < pitch * 2) return null;
    const step: usize = if (start != 0) pitch else 1;
    var i = start;
    while (i < px.len - pitch * 2) : (i += step) {
        if (i + pitch * 2 < 7) continue;
        const b = i + pitch * 2;
        if (px[i] == 0x404040 and px[i + pitch] == 0x404040 and
            px[b] == 0xf0f0f0 and px[b - 1] == 0xe0e0e0 and px[b - 2] == 0xf0f0f0 and px[b - 3] == 0xe0e0e0 and
            px[b - 4] == 0xf0f0f0 and px[b - 5] == 0xe0e0e0 and px[b - 6] == 0xf0f0f0 and px[b - 7] == 0xe0e0e0)
        {
            return b;
        }
    }
    return null;
}

const Tag = struct { pal_base: u8, tileset: usize, headerless: bool, pal_subidx: u8 };

fn decodeTag(px: []const u32, pos: usize) ?Tag {
    if (pos < 63) return null;
    var r: u64 = 0;
    for (0..64) |i| {
        const v = px[pos - 63 + i];
        if (v != 0xe0e0e0 and v != 0xf0f0f0) return null;
        r = r << 1 | @intFromBool(v == 0xf0f0f0);
    }
    if (r & 0x1ff != 0x55) return null;
    r >>= 9;
    if (((r >> 8) + 41) % 255 != r & 0xff) return null;
    r >>= 8;
    return .{ .pal_base = @intCast(r & 7), .tileset = @intCast((r >> 3) & 127), .headerless = (r >> 10) & 1 != 0, .pal_subidx = @intCast((r >> 11) & 31) };
}
