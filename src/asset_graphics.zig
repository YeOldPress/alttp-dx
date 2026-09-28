//! The game's graphics as PNGs to edit: Link's sprites, the dialogue font and
//! the HUD's icons. The sprite sheets have their own file, asset_sprite_sheets.
//!
//! Each follows the old sprite_sheets.py: the same layout, the same palettes, so the
//! PNGs the old Python wrote read back here and the other way round. Pixels are
//! palette indices, which is what the game stores; editors keep them as long
//! as the image stays in indexed color.
const std = @import("std");
const rom_mod = @import("rom.zig");
const png = @import("png.zig");
const asset_tables = @import("asset_tables.zig");

const Rom = rom_mod.Rom;

/// SNES BGR555 to 8-bit RGB, the way the old Python widens it.
pub fn snesToRgb(c: u16) [3]u8 {
    const r: u8 = @intCast(c & 0x1f);
    const g: u8 = @intCast((c >> 5) & 0x1f);
    const b: u8 = @intCast((c >> 10) & 0x1f);
    return .{ r << 3 | r >> 2, g << 3 | g >> 2, b << 3 | b >> 2 };
}

// ------------------------------------------------------------ Link

const kLinkPalette = [16]u16{ 0, 0x7fff, 0x237e, 0x11b7, 0x369e, 0x14a5, 0x1ff, 0x1078, 0x599d, 0x3647, 0x3b68, 0xa4a, 0x12ef, 0x2a5c, 0x1571, 0x7a18 };
const kLinkTiles = 16 * 448 / 8;

/// linksprite.png: every one of Link's 4bpp tiles, 16 across, indexed.
pub fn exportLink(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    const data = try rom.getBytes(alloc, 0x108000, 0x800 * 448 / 32);
    defer alloc.free(data);
    const pixels = try alloc.alloc(u8, 128 * 448);
    defer alloc.free(pixels);
    for (0..kLinkTiles) |i| {
        const offs = i * 32;
        const toffs = (i % 16) * 8 + (i / 16) * 8 * 128;
        for (0..8) |y| {
            const d = [4]u8{ data[offs + y * 2], data[offs + y * 2 + 1], data[offs + y * 2 + 16], data[offs + y * 2 + 17] };
            for (0..8) |x| {
                const s: u3 = @intCast(x);
                pixels[toffs + y * 128 + (7 - x)] = (d[0] >> s & 1) | (d[1] >> s & 1) << 1 | (d[2] >> s & 1) << 2 | (d[3] >> s & 1) << 3;
            }
        }
    }
    var pal: [16][3]u8 = undefined;
    for (kLinkPalette, 0..) |c, i| pal[i] = snesToRgb(c);
    return png.encode(alloc, 128, 448, .indexed, pixels, &pal);
}

/// kLinkGraphics from linksprite.png: print_link_graphics.
pub fn importLink(alloc: std.mem.Allocator, img: png.Image) ![]u8 {
    if (img.width != 128 or img.height != 448) return error.WrongSize;
    const indices = try indicesOf(alloc, img, &kLinkPalette);
    defer alloc.free(indices);
    const out = try alloc.alloc(u8, kLinkTiles * 32);
    @memset(out, 0);
    for (0..56) |ty| {
        for (0..16) |tx| {
            const b = out[(ty * 16 + tx) * 32 ..][0..32];
            const offset = ty * 128 * 8 + tx * 8;
            for (0..8) |y| {
                for (0..8) |x| {
                    const v = indices[offset + y * 128 + x];
                    const s: u3 = @intCast(7 - x);
                    b[y * 2 + 0] |= (v & 1) << s;
                    b[y * 2 + 1] |= (v >> 1 & 1) << s;
                    b[y * 2 + 16] |= (v >> 2 & 1) << s;
                    b[y * 2 + 17] |= (v >> 3 & 1) << s;
                }
            }
        }
    }
    return out;
}

/// An image's pixels as palette indices. An indexed image already is; one an
/// editor saved as RGB is matched back against the palette it was exported
/// with, color for color.
fn indicesOf(alloc: std.mem.Allocator, img: png.Image, snes_palette: []const u16) ![]u8 {
    if (img.kind == .indexed) return alloc.dupe(u8, img.pixels);
    const out = try alloc.alloc(u8, @as(usize, img.width) * img.height);
    errdefer alloc.free(out);
    for (0..img.height) |y| {
        for (0..img.width) |x| {
            const rgb = img.rgbAt(x, y);
            const i = for (snes_palette, 0..) |c, k| {
                const p = snesToRgb(c);
                if (rgb == @as(u32, p[0]) << 16 | @as(u32, p[1]) << 8 | p[2]) break k;
            } else return error.ColorNotInPalette;
            out[y * img.width + x] = @intCast(i);
        }
    }
    return out;
}

// ------------------------------------------------------------ the font

/// Where each language keeps its font in its ROM, how wide the table of
/// character widths is, and what the exported file is called.
pub const FontType = struct { addr: u32, count: usize, file: []const u8, widths_addr: u32, widths: usize };

pub fn fontType(lang: rom_mod.Language) FontType {
    return switch (lang) {
        .us => .{ .addr = 0x8e8000, .count = 256, .file = "font.png", .widths_addr = 0x8ECADF, .widths = 99 },
        .de => .{ .addr = 0xCC6E8, .count = 256, .file = "font_de.png", .widths_addr = 0x8CDECF, .widths = 112 },
        .fr => .{ .addr = 0xCC6E8, .count = 256, .file = "font_fr.png", .widths_addr = 0x8CDEAF, .widths = 112 },
        .fr_c => .{ .addr = 0xCD078, .count = 256, .file = "font_fr_c.png", .widths_addr = 0x8CE83F, .widths = 112 },
        .en => .{ .addr = 0x8E8000, .count = 256, .file = "font_en.png", .widths_addr = 0x8ECAFF, .widths = 102 },
        .es => .{ .addr = 0x8e8000, .count = 256, .file = "font_es.png", .widths_addr = 0x8ECADF, .widths = 99 },
        .pl => .{ .addr = 0x8e8000, .count = 256, .file = "font_pl.png", .widths_addr = 0x8ECADF, .widths = 99 },
        .pt => .{ .addr = 0x8e8000, .count = 256, .file = "font_pt.png", .widths_addr = 0x8ECADF, .widths = 121 },
        .redux => .{ .addr = 0x8e8000, .count = 256, .file = "font_redux.png", .widths_addr = 0x8ECADF, .widths = 99 },
        .nl => .{ .addr = 0x8e8000, .count = 256, .file = "font_nl.png", .widths_addr = 0x8ECADF, .widths = 99 },
        .sv => .{ .addr = 0x8e8000, .count = 256, .file = "font_sv.png", .widths_addr = 0x8ECADF, .widths = 99 },
    };
}

const kFontW = 128 + 15;

fn hudPalette(rom: Rom) [128][3]u8 {
    var pal: [128][3]u8 = undefined;
    for (0..128) |i| pal[i] = snesToRgb((31 << 10) | 31);
    for (0..8) |i| {
        for (1..4) |j| pal[i * 16 + j] = snesToRgb(rom.getWord(0x9BD660 + @as(u32, @intCast(i * 4 + j)) * 2));
    }
    return pal;
}

/// The Portuguese translation moves some glyphs around; everything else
/// keeps them where they are.
fn ptRemap(rom: Rom, i: usize) usize {
    for (0..121) |k| {
        const ch = (k & 0xf) | ((k << 1) & 0xe0);
        const base: u32 = 0x8EFC09 + @as(u32, @intCast(k)) * 3;
        if (ch == i) return rom.getByte(base);
        if ((ch | 0x10) == i) return rom.getByte(base + 1);
    }
    return i;
}

/// font.png, or font_xx.png for another language: each glyph in its box,
/// with a marker pixel (255) where its width ends.
pub fn exportFont(alloc: std.mem.Allocator, rom: Rom, lang: rom_mod.Language) ![]u8 {
    const ft = fontType(lang);
    const h = ft.count / 32 * 17;
    const data = try rom.getBytes(alloc, ft.addr, ft.count * 16);
    defer alloc.free(data);
    var widths: [128]u8 = undefined;
    const n_widths: usize = if (lang == .pt) 121 else ft.widths;
    for (0..n_widths) |i| {
        widths[i] = if (lang == .pt) rom.getByte(0x8EFC09 + @as(u32, @intCast(i)) * 3 + 2) else rom.getByte(ft.widths_addr + @as(u32, @intCast(i)));
    }
    const pixels = try alloc.alloc(u8, kFontW * h);
    defer alloc.free(pixels);
    @memset(pixels, 0);
    for (0..ft.count) |i| {
        const x = i % 16;
        const y = i / 16;
        const base_offs = x * 9 + (y * 8 + (y >> 1)) * kFontW;
        const src = (if (lang == .pt) ptRemap(rom, i) else i) * 16;
        for (0..8) |row| {
            const d0 = data[src + row * 2];
            const d1 = data[src + row * 2 + 1];
            for (0..8) |col| {
                const s: u3 = @intCast(col);
                pixels[base_offs + kFontW + row * kFontW + (7 - col)] = ((d0 >> s) & 1) + ((d1 >> s) & 1) * 2 + 96;
            }
        }
        if (y & 1 == 0) {
            const j = (y >> 1) * 16 + x;
            if (j < n_widths) pixels[base_offs + widths[j] - 1] = 255;
        }
    }
    var pal: [256][3]u8 = @splat(.{ 0, 0, 0 });
    const hud = hudPalette(rom);
    @memcpy(pal[0..128], &hud);
    pal[0] = .{ 192, 192, 192 };
    pal[255] = .{ 128, 128, 128 };
    return png.encode(alloc, kFontW, @intCast(h), .indexed, pixels, &pal);
}

/// The font's glyph tiles and width table back from its PNG:
/// encode_font_from_png.
pub fn importFont(alloc: std.mem.Allocator, img: png.Image, lang: rom_mod.Language) !struct { tiles: []u8, widths: []u8 } {
    if (img.kind != .indexed) return error.FontNotIndexed;
    if (img.width != kFontW or img.height < 136) return error.WrongSize;
    const d = img.pixels;
    const tiles = try alloc.alloc(u8, 256 * 16);
    errdefer alloc.free(tiles);
    var widths: std.ArrayList(u8) = .empty;
    errdefer widths.deinit(alloc);
    for (0..256) |i| {
        const x = i % 16;
        const y = i / 16;
        const base_offs = x * 9 + (y * 8 + (y >> 1)) * kFontW;
        if (y & 1 == 0) {
            var w: u8 = 8;
            for (0..8) |k| if (d[base_offs + k] == 255) {
                w = @intCast(k + 1);
                break;
            };
            try widths.append(alloc, w);
        }
        for (0..8) |row| {
            var d0: u8 = 0;
            var d1: u8 = 0;
            for (0..8) |col| {
                const pixel = d[base_offs + kFontW + row * kFontW + 7 - col];
                const s: u3 = @intCast(col);
                d0 |= (pixel & 1) << s;
                d1 |= ((pixel >> 1) & 1) << s;
            }
            tiles[i * 16 + row * 2] = d0;
            tiles[i * 16 + row * 2 + 1] = d1;
        }
    }
    const keep = @min(widths.items.len, fontType(lang).widths);
    widths.shrinkRetainingCapacity(keep);
    return .{ .tiles = tiles, .widths = try widths.toOwnedSlice(alloc) };
}

// ------------------------------------------------------------ HUD icons

/// Which HUD palette each icon uses, one bit per palette, from
/// the old assets/palette_usage.bin, whose first 384 bytes were all it ever used.
const kPaletteUsage = [384]u8{
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x20, 0x20, 0x20, 0x00, 0x08, 0x00,
    0x00, 0x00, 0x00, 0x02, 0x02, 0x02, 0x02, 0x04, 0x04, 0x04, 0x04, 0x01, 0x01, 0x01, 0x01, 0x00,
    0x80, 0x80, 0x04, 0x80, 0x02, 0x02, 0x02, 0x02, 0x00, 0x04, 0x04, 0x00, 0x00, 0x00, 0x80, 0x00,
    0x04, 0x04, 0x04, 0x00, 0x04, 0x04, 0x04, 0x08, 0x04, 0x04, 0x08, 0x04, 0x04, 0x04, 0x80, 0x00,
    0x80, 0x80, 0x08, 0x08, 0x08, 0x0e, 0x04, 0x04, 0x88, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x80, 0x04, 0x08, 0x08, 0x8a, 0x08, 0x04, 0x04, 0x88, 0x02, 0x02, 0x02, 0x02, 0x04, 0x04, 0x43,
    0x04, 0x04, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x08, 0x08, 0x0e, 0x04, 0x02, 0x04, 0x04, 0x04,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x08, 0x08, 0x00, 0x08, 0x08, 0x20,
    0x02, 0x02, 0x02, 0x00, 0x00, 0x80, 0x80, 0x01, 0x80, 0x01, 0x00, 0x02, 0x02, 0x02, 0x02, 0x00,
    0x0a, 0x02, 0x08, 0x08, 0x02, 0x02, 0x01, 0x01, 0x0a, 0x0a, 0x04, 0x04, 0x02, 0x02, 0x08, 0x00,
    0x0a, 0x0a, 0x08, 0x00, 0x02, 0x02, 0x01, 0x01, 0x04, 0x0a, 0x02, 0x04, 0x02, 0x02, 0x08, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x08, 0x08, 0x00, 0x04, 0x80, 0x80, 0x04, 0x04, 0x0a, 0x0a, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x08, 0x08, 0x00, 0x00, 0x04, 0x04, 0x04, 0x04, 0x0a, 0x0a, 0x00, 0x00,
    0x82, 0x80, 0x02, 0x04, 0x04, 0x0b, 0x02, 0x04, 0x00, 0x86, 0x04, 0x86, 0x86, 0x08, 0x08, 0x20,
    0x20, 0x20, 0x20, 0x10, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00,
    0x22, 0x22, 0x02, 0x02, 0x02, 0x80, 0x80, 0x08, 0x08, 0x08, 0x00, 0x8a, 0x8a, 0x8a, 0x8a, 0x02,
    0x01, 0x01, 0x00, 0x00, 0x02, 0x02, 0x02, 0x02, 0x00, 0x08, 0x00, 0x10, 0x10, 0x10, 0x10, 0x02,
    0x01, 0x01, 0x00, 0x00, 0x08, 0x08, 0x10, 0x10, 0x08, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x00,
    0x2a, 0x22, 0x22, 0x2a, 0x2a, 0x2a, 0x22, 0x22, 0x2a, 0x20, 0x2a, 0x2a, 0x2a, 0x2a, 0x22, 0x2a,
    0x20, 0x2a, 0x2a, 0x2a, 0x2a, 0x20, 0x2a, 0x20, 0x22, 0x20, 0x20, 0x22, 0x22, 0x20, 0x22, 0x02,
    0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
};

/// hud_icons.png: the HUD's three 2bpp sheets, each icon in its own palette.
/// Export only; the game takes its HUD graphics from the ROM.
pub fn exportHudIcons(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    const pixels = try alloc.alloc(u8, 128 * 64 * 3);
    defer alloc.free(pixels);
    for ([3]usize{ 106, 107, 105 }, 0..) |image_set, slot| {
        const dec = try rom_mod.decomp(alloc, rom, asset_tables.kCompSpritePtrs[image_set], false);
        defer alloc.free(dec.data);
        const data = dec.data;
        if (data.len != 0x800) return error.UnexpectedSheetSize;
        const dst = pixels[slot * 128 * 64 ..][0 .. 128 * 64];
        for (0..16 * 64 / 8) |i| {
            const usage = kPaletteUsage[slot * 128 + i];
            var pal: u8 = 0;
            for (0..8) |j| if (usage & (@as(u8, 1) << @intCast(j)) != 0) {
                pal = @intCast(j);
                break;
            };
            const offs = i * 16;
            const toffs = (i % 16) * 8 + (i / 16) * 8 * 128;
            for (0..8) |y| {
                const d0 = data[offs + y * 2];
                const d1 = data[offs + y * 2 + 1];
                for (0..8) |x| {
                    const s: u3 = @intCast(x);
                    dst[toffs + y * 128 + (7 - x)] = ((d0 >> s) & 1) + ((d1 >> s) & 1) * 2 + pal * 16;
                }
            }
        }
    }
    const pal = hudPalette(rom);
    return png.encode(alloc, 128, 64 * 3, .indexed, pixels, &pal);
}
