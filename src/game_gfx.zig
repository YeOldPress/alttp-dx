//! Draws with the game's own graphics straight onto a finished frame.
//!
//! The PPU has already turned the SNES state into pixels by the time this
//! runs; this paints on top of them, reading the HUD's tiles, the colours
//! out of CGRAM and the dialogue font out of the asset file, so what it draws
//! looks exactly like the game's menus without touching any of the state the
//! game will want back afterwards. Coordinates are in SNES pixels on a 256x224
//! screen, scaled and centred to whatever the frame really is.
const std = @import("std");
const rtl = @import("zelda_rtl_types.zig");
const util = @import("util.zig");
const ppu_types = @import("snes").ppu_types;
const text_tables = @import("asset_text_tables.zig");

extern fn Decomp_spr(dst: [*]u8, gfx: c_int) c_int;

/// The HUD's 2bpp characters: its boxes, hearts and item icons. The game keeps
/// them at VRAM 0x7000 while it's running, but other screens, the file select
/// among them, put other things there. So a copy is decompressed from the same
/// three packs the game loads them from (see LoadDefaultGraphics), and drawing
/// uses that wherever the game happens to be.
var g_hud_chr: [3 * 1024]u16 = undefined;
var g_hud_chr_loaded = false;

pub fn loadHudTiles() void {
    if (g_hud_chr_loaded) return;
    // Decompression can run past the 2K each pack is cut to, so it gets room.
    var scratch: [0x4000]u8 align(2) = undefined;
    for ([3]c_int{ 0x6a, 0x6b, 0x69 }, 0..) |pack, i| {
        _ = Decomp_spr(&scratch, pack);
        const words: [*]const u16 = @ptrCast(&scratch);
        @memcpy(g_hud_chr[i * 1024 ..][0..1024], words[0..1024]);
    }
    g_hud_chr_loaded = true;
}

pub const Canvas = struct {
    pixels: [*]u8,
    pitch: usize,
    /// The frame's size in SNES pixels. Wider than 256 with widescreen on.
    width: usize,
    height: usize,
    /// 1, or 4 when Mode 7 is being drawn at four times the size.
    scale: usize,

    /// Where x = 0 of the 256 wide screen sits, so that a widescreen frame
    /// keeps the menu in the middle.
    fn originX(self: Canvas) i32 {
        return @intCast((self.width - 256) / 2);
    }

    fn put(self: Canvas, x: i32, y: i32, rgb: u32) void {
        const fx = x + self.originX();
        if (fx < 0 or y < 0 or fx >= self.width or y >= self.height) return;
        const s = self.scale;
        for (0..s) |dy| {
            const row: [*]align(1) u32 = @ptrCast(self.pixels + (@as(usize, @intCast(y)) * s + dy) * self.pitch);
            for (0..s) |dx| row[@as(usize, @intCast(fx)) * s + dx] = rgb;
        }
    }

    /// Darkens the whole frame, game and all, to a quarter of its brightness.
    pub fn dim(self: Canvas) void {
        for (0..self.height * self.scale) |y| {
            const row: [*]align(1) u32 = @ptrCast(self.pixels + y * self.pitch);
            for (0..self.width * self.scale) |x| row[x] = (row[x] >> 2) & 0x3f3f3f;
        }
    }

    /// Paints a band across the whole frame, widescreen margins included, so
    /// text laid over it isn't fighting whatever the dimmed screen has there.
    pub fn band(self: Canvas, y: i32, h: i32, rgb: u32) void {
        const s = self.scale;
        const top: usize = @intCast(@max(0, y));
        const bottom: usize = @min(self.height, @as(usize, @intCast(@max(0, y + h))));
        for (top * s..bottom * s) |py| {
            const row: [*]align(1) u32 = @ptrCast(self.pixels + py * self.pitch);
            for (0..self.width * s) |x| row[x] = rgb;
        }
    }

    pub fn fill(self: Canvas, x: i32, y: i32, w: i32, h: i32, rgb: u32) void {
        var yy = y;
        while (yy < y + h) : (yy += 1) {
            var xx = x;
            while (xx < x + w) : (xx += 1) self.put(xx, yy, rgb);
        }
    }

    /// One 8x8 BG3 tile, given the way a tilemap names it: tile number,
    /// palette and flips all in the one word. Colour 0 is see-through.
    pub fn tile(self: Canvas, x: i32, y: i32, word: u16) void {
        if (!g_hud_chr_loaded) return;
        const num: usize = word & 0x3ff;
        if ((num + 1) * 8 > g_hud_chr.len) return;
        const pal: usize = (word >> 10) & 7;
        const hflip = word & 0x4000 != 0;
        const vflip = word & 0x8000 != 0;
        for (0..8) |r| {
            const row_word = g_hud_chr[num * 8 + (if (vflip) 7 - r else r)];
            for (0..8) |col| {
                const bit: u4 = @intCast(if (hflip) col else 7 - col);
                const ci = (row_word >> bit & 1) | (row_word >> (bit + 8) & 1) << 1;
                if (ci != 0) self.put(x + @as(i32, @intCast(col)), y + @as(i32, @intCast(r)), cgramColor(pal * 4 + ci));
            }
        }
    }

    /// A 2x2 icon, laid out the way the inventory's ItemBoxGfx lists it.
    pub fn icon(self: Canvas, x: i32, y: i32, v: [4]u16) void {
        self.tile(x, y, v[0]);
        self.tile(x + 8, y, v[1]);
        self.tile(x, y + 8, v[2]);
        self.tile(x + 8, y + 8, v[3]);
    }

    /// The inventory's framed box, in whole tiles, with its dark interior.
    /// Mirrors Hud_DrawBox tile for tile.
    pub fn box(self: Canvas, x: i32, y: i32, w_tiles: i32, h_tiles: i32, palette: u16) void {
        const p = palette << 10;
        var ty: i32 = 0;
        while (ty < h_tiles) : (ty += 1) {
            var tx: i32 = 0;
            while (tx < w_tiles) : (tx += 1) {
                const last_x = tx == w_tiles - 1;
                const last_y = ty == h_tiles - 1;
                const edge_x = tx == 0 or last_x;
                const edge_y = ty == 0 or last_y;
                const flips: u16 = (if (last_x) @as(u16, 0x4000) else 0) | (if (last_y) @as(u16, 0x8000) else 0);
                const word: u16 = if (edge_x and edge_y)
                    0x20fb | p | flips
                else if (edge_x)
                    0x20fc | p | flips
                else if (edge_y)
                    0x20f9 | p | flips
                else
                    0x24f5;
                self.tile(x + tx * 8, y + ty * 8, word);
            }
        }
    }

    /// Dialogue-font text. Returns how wide it drew. Pictures such as [A] or
    /// [Up] are spelled in brackets, as in the dialogue dump; anything the
    /// font lacks is skipped.
    pub fn text(self: Canvas, x: i32, y: i32, s: []const u8, colors: [3]u32) i32 {
        const font = Font.get() orelse return 0;
        var cx = x;
        var it = Glyphs{ .s = s };
        while (it.next()) |g| {
            const w = font.widths[g];
            const top: usize = (@as(usize, g) & 0x70) * 2 + (g & 0xf);
            for ([2]usize{ top, top + 16 }, 0..) |t, half| {
                const data = font.data[t * 16 ..][0..16];
                for (0..8) |r| {
                    const lo = data[r * 2];
                    const hi = data[r * 2 + 1];
                    for (0..w) |col| {
                        const bit: u3 = @intCast(7 - col);
                        const ci = (lo >> bit & 1) | (hi >> bit & 1) << 1;
                        if (ci != 0) self.put(cx + @as(i32, @intCast(col)), y + @as(i32, @intCast(half * 8 + r)), colors[ci - 1]);
                    }
                }
            }
            cx += w;
        }
        return cx - x;
    }
};

/// A run of text as dialogue glyph numbers.
const Glyphs = struct {
    s: []const u8,
    i: usize = 0,

    fn next(self: *Glyphs) ?u8 {
        while (self.i < self.s.len) {
            var len: usize = 1;
            if (self.s[self.i] == '[') {
                if (std.mem.indexOfScalarPos(u8, self.s, self.i, ']')) |close| len = close + 1 - self.i;
            }
            const token = self.s[self.i .. self.i + len];
            self.i += len;
            if (glyphIndex(token)) |g| return g;
        }
        return null;
    }
};

pub fn glyphIndex(token: []const u8) ?u8 {
    for (text_tables.kAlphabet, 0..) |a, i| {
        if (std.mem.eql(u8, a, token)) return @intCast(i);
    }
    return null;
}

/// How wide text draws in the dialogue font.
pub fn textWidth(s: []const u8) i32 {
    const font = Font.get() orelse return 0;
    var w: i32 = 0;
    var it = Glyphs{ .s = s };
    while (it.next()) |g| w += font.widths[g];
    return w;
}

const Font = struct {
    data: []const u8,
    widths: []const u8,

    fn get() ?Font {
        const blk: util.MemBlk = @bitCast(rtl.g_zenv.dialogue_font_blk);
        if (blk.ptr == null) return null;
        const data = util.FindIndexInMemblk(blk, 0);
        const widths = util.FindIndexInMemblk(blk, 1);
        return .{ .data = data.ptr.?[0..data.size], .widths = widths.ptr.?[0..widths.size] };
    }
};

/// A palette entry as 0x00RRGGBB, the way the PPU writes pixels.
pub fn cgramColor(i: usize) u32 {
    const ppu: *const ppu_types.Ppu = @ptrCast(@alignCast(rtl.g_zenv.ppu orelse return 0));
    return bgr555(ppu.cgram[i & 0xff]);
}

pub fn bgr555(c: u16) u32 {
    const r: u32 = c & 31;
    const g: u32 = (c >> 5) & 31;
    const b: u32 = (c >> 10) & 31;
    return (r << 3 | r >> 2) << 16 | (g << 3 | g >> 2) << 8 | (b << 3 | b >> 2);
}

test "SNES colours widen to eight bits per channel" {
    try std.testing.expectEqual(@as(u32, 0xffffff), bgr555(0x7fff));
    try std.testing.expectEqual(@as(u32, 0xff0000), bgr555(0x001f));
    try std.testing.expectEqual(@as(u32, 0x0000ff), bgr555(0x7c00));
}
