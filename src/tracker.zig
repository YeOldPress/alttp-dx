//! The item tracker for randomizer runs. Everything it shows is read from the
//! game's own save data in work ram every frame, so there's nothing to click
//! and nothing to get wrong; everything it draws comes out of the seed ROM,
//! so it looks like the game and ships no art.
//!
//! One layout, drawn at any scale: the items, a table of the dungeons, and
//! the light and dark world maps with every check on them. The panel beside
//! the game, the separate window and the overlay all draw it (the overlay
//! leaves the maps out, since it sits on top of the game).
const std = @import("std");
const data = @import("tracker_data.zig");
const hud = @import("hud_tables.zig");

pub const Mode = enum {
    off,
    panel,
    overlay,
    window,

    pub fn next(self: Mode) Mode {
        return switch (self) {
            .off => .panel,
            .panel => .overlay,
            .overlay => .window,
            .window => .off,
        };
    }

    pub fn label(self: Mode) []const u8 {
        return switch (self) {
            .off => "TRACKER OFF",
            .panel => "TRACKER: PANEL",
            .overlay => "TRACKER: OVERLAY",
            .window => "TRACKER: WINDOW",
        };
    }

    pub fn fromName(name: []const u8) ?Mode {
        inline for (@typeInfo(Mode).@"enum".fields) |f| {
            if (std.ascii.eqlIgnoreCase(name, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }
};

/// The layout's size in its own units; it's drawn at a whole multiple.
pub const kWidth = 192;
pub const kHeight = 224;
/// The part without the maps, for the overlay.
pub const kOverlayHeight = 138;

// ------------------------------------------------------------ graphics

/// What the tracker draws with, decoded from the seed once.
pub const Gfx = struct {
    /// The inventory's 2bpp tiles as pixels 0..3, 64 to a tile; 384 tiles in
    /// the order the game loads them to vram.
    tiles: [384 * 64]u8 = @splat(0),
    /// The HUD's eight four-color palettes, as 0xRRGGBB.
    hud: [8][4]u32 = @splat(@splat(0)),
    have_icons: bool = false,
    /// Both world maps, 256x256: the middle of the mode 7 plane, where the
    /// world is (the rest is clouds).
    map: [2][256 * 256]u32 = @splat(@splat(0)),
    have_maps: bool = false,
    /// The maps shrunk to the size they were last drawn at.
    scaled: [2][256 * 256]u32 = @splat(@splat(0)),
    scaled_n: usize = 0,
};

/// Box-filters both maps to n x n (n <= 256), once per size.
fn scaleMaps(gfx: *Gfx, n: usize) void {
    if (gfx.scaled_n == n) return;
    for (0..2) |w| {
        for (0..n) |py| {
            for (0..n) |px| {
                const sx0 = px * 256 / n;
                const sy0 = py * 256 / n;
                const sx1 = @max(sx0 + 1, (px + 1) * 256 / n);
                const sy1 = @max(sy0 + 1, (py + 1) * 256 / n);
                var r: u32 = 0;
                var g: u32 = 0;
                var b: u32 = 0;
                var cnt: u32 = 0;
                for (sy0..sy1) |sy| {
                    for (sx0..sx1) |sx| {
                        const c = gfx.map[w][sy * 256 + sx];
                        r += c >> 16;
                        g += (c >> 8) & 0xff;
                        b += c & 0xff;
                        cnt += 1;
                    }
                }
                // A little darker, so the markers stand out.
                gfx.scaled[w][py * n + px] = blend((r / cnt) << 16 | (g / cnt) << 8 | (b / cnt), 0, 60);
            }
        }
    }
    gfx.scaled_n = n;
}

fn romByte(rom: []const u8, ea: u32) u8 {
    const off = ((ea >> 16) & 0x7f) * 0x8000 + (ea & 0x7fff);
    return rom[off % rom.len];
}

fn snesColor(c: u16) u32 {
    const r: u32 = c & 31;
    const g: u32 = (c >> 5) & 31;
    const b: u32 = (c >> 10) & 31;
    return (r << 3 | r >> 2) << 16 | (g << 3 | g >> 2) << 8 | (b << 3 | b >> 2);
}

/// The game's LZ-style graphics compression, as rom.zig has it.
fn decomp(out: []u8, rom: []const u8, ea_in: u32) ?usize {
    var ea = ea_in;
    var n: usize = 0;
    const next = struct {
        fn f(r: []const u8, p: *u32) u8 {
            const b = romByte(r, p.*);
            p.* += 1;
            if (p.* & 0xffff == 0) p.* += 0x8000;
            return b;
        }
    }.f;
    for (0..4096) |_| {
        const b = next(rom, &ea);
        if (b == 0xff) return n;
        var cmd: u8 = undefined;
        var len: usize = undefined;
        if (b & 0xe0 != 0xe0) {
            cmd = b & 0xe0;
            len = b & 0x1f;
        } else {
            cmd = (b << 3) & 0xe0;
            len = (@as(usize, b & 3) << 8) | next(rom, &ea);
        }
        len += 1;
        if (n + len > out.len) return null;
        if (cmd == 0) {
            for (0..len) |i| out[n + i] = next(rom, &ea);
        } else if (cmd & 0x80 != 0) {
            var from: usize = next(rom, &ea);
            from |= @as(usize, next(rom, &ea)) << 8;
            for (0..len) |i| {
                if (from + i >= n + i) return null;
                out[n + i] = out[from + i];
            }
        } else if (cmd & 0x40 == 0) {
            @memset(out[n..][0..len], next(rom, &ea));
        } else if (cmd & 0x20 == 0) {
            const b1 = next(rom, &ea);
            const b2 = next(rom, &ea);
            for (0..len) |i| out[n + i] = if (i & 1 == 0) b1 else b2;
        } else {
            var v = next(rom, &ea);
            for (0..len) |i| {
                out[n + i] = v;
                v +%= 1;
            }
        }
        n += len;
    }
    return null;
}

/// Decodes the icons and maps out of a Japanese-based ROM (every
/// randomizer seed is). Anything that doesn't decode is left out and drawn
/// plainly instead, rather than failing the run.
pub fn loadGfx(gfx: *Gfx, rom: []const u8) void {
    gfx.* = .{};
    if (rom.len < 0x100000) return;

    // The inventory's tiles: sheets 106, 107 and 105, found through the
    // game's own pointer table (bank, high and low bytes in three arrays),
    // which the randomizer repoints to its redrawn HUD.
    const kSheetTable = 0x5033;
    icons: {
        for ([3]usize{ 106, 107, 105 }, 0..) |sheet, slot| {
            const ea = @as(u32, rom[kSheetTable + sheet]) << 16 |
                @as(u32, rom[kSheetTable + 0xdf + sheet]) << 8 |
                rom[kSheetTable + 0x1be + sheet];
            var buf: [0x800]u8 = undefined;
            const n = decomp(&buf, rom, ea) orelse break :icons;
            if (n != 0x800) break :icons;
            for (0..128) |t| {
                for (0..8) |y| {
                    const d0 = buf[t * 16 + y * 2];
                    const d1 = buf[t * 16 + y * 2 + 1];
                    for (0..8) |x| {
                        const sh: u3 = @intCast(7 - x);
                        gfx.tiles[(slot * 128 + t) * 64 + y * 8 + x] = ((d0 >> sh) & 1) | ((d1 >> sh) & 1) << 1;
                    }
                }
            }
        }
        for (0..8) |p| {
            for (1..4) |j| gfx.hud[p][j] = snesColor(std.mem.readInt(u16, &.{ romByte(rom, 0x9BD660 + @as(u32, @intCast(p * 4 + j)) * 2), romByte(rom, 0x9BD661 + @as(u32, @intCast(p * 4 + j)) * 2) }, .little));
        }
        gfx.have_icons = true;
    }

    // The world maps: 8bpp mode 7 tiles, the light world's 64x64 tilemap in
    // four quarters, and the dark world's 32x32 middle laid over it with the
    // other half of the palette.
    const kMapTiles = 0x18c000;
    const kLightMap = 0x0ac739;
    const kDarkMap = 0x0ad739;
    const kMapPalette = 0x0adb39;
    var tilemap: [2][64 * 64]u8 = undefined;
    for (0..4) |q| {
        const x0 = (q & 1) * 32;
        const y0 = (q >> 1) * 32;
        for (0..32) |row| {
            for (0..32) |col| tilemap[0][(y0 + row) * 64 + x0 + col] = romByte(rom, kLightMap + @as(u32, @intCast(q * 1024 + row * 32 + col)));
        }
    }
    tilemap[1] = tilemap[0];
    for (0..32) |row| {
        for (0..32) |col| tilemap[1][(16 + row) * 64 + 16 + col] = romByte(rom, kDarkMap + @as(u32, @intCast(row * 32 + col)));
    }
    for (0..2) |w| {
        var pal: [128]u32 = undefined;
        for (&pal, 0..) |*p, i| {
            const a = kMapPalette + @as(u32, @intCast((w * 128 + i) * 2));
            p.* = snesColor(@as(u16, romByte(rom, a)) | @as(u16, romByte(rom, a + 1)) << 8);
        }
        for (0..256) |yy| {
            for (0..256) |xx| {
                const x = xx + 128;
                const y = yy + 128;
                const tile: u32 = tilemap[w][(y / 8) * 64 + x / 8];
                const idx = romByte(rom, kMapTiles + tile * 64 + @as(u32, @intCast((y % 8) * 8 + x % 8)));
                gfx.map[w][yy * 256 + xx] = pal[idx & 0x7f];
            }
        }
    }
    gfx.have_maps = true;
}

// --------------------------------------------------------------- state

/// What the player has, read from the save data ($7EF000 on).
pub const State = struct {
    save: *const [0x500]u8,

    fn at(self: State, off: u16) u8 {
        return self.save[off];
    }

    fn has(self: State, c: data.Check) bool {
        return self.save[c.off] & c.mask != 0;
    }

    fn done(self: State, checks: []const data.Check) usize {
        var n: usize = 0;
        for (checks) |c| {
            if (self.has(c)) n += 1;
        }
        return n;
    }

    fn inWorldDark(self: State) bool {
        return self.at(0x3ca) & 0x40 != 0;
    }
};

pub fn stateFrom(work_ram: *const [0x20000]u8) State {
    return .{ .save = work_ram[0xf000..][0..0x500] };
}

// ------------------------------------------------------------- drawing

/// Where the tracker draws: 0x00RRGGBB pixels, `pitch` pixels a row, and a
/// whole-number scale from layout units to pixels.
pub const Canvas = struct {
    px: [*]u32,
    pitch: usize,
    w: usize,
    h: usize,
    scale: usize,
    /// 0..256: how much of the tracker shows over what's already there.
    alpha: u32 = 256,

    /// A pixel in layout units.
    pub fn put2(self: Canvas, x: usize, y: usize, rgb: u32) void {
        self.rect(x, y, 1, 1, rgb);
    }

    pub fn put(self: Canvas, x: usize, y: usize, rgb: u32) void {
        if (x >= self.w or y >= self.h) return;
        const p = &self.px[y * self.pitch + x];
        if (self.alpha >= 256) {
            p.* = rgb;
        } else {
            p.* = blend(p.*, rgb, self.alpha);
        }
    }

    /// Fills a rectangle given in layout units.
    fn rect(self: Canvas, x: usize, y: usize, w: usize, h: usize, rgb: u32) void {
        for (y * self.scale..(y + h) * self.scale) |py| {
            for (x * self.scale..(x + w) * self.scale) |px| self.put(px, py, rgb);
        }
    }
};

fn blend(a: u32, b: u32, t: u32) u32 {
    var out: u32 = 0;
    inline for (.{ 16, 8, 0 }) |sh| {
        const ca = (a >> sh) & 0xff;
        const cb = (b >> sh) & 0xff;
        out |= ((ca * (256 - t) + cb * t) >> 8) << sh;
    }
    return out;
}

fn dim(rgb: u32) u32 {
    return blend(rgb, 0x101010, 190);
}

const kBackground: u32 = 0x10141c;
const kCell: u32 = 0x1c2230;
const kText: u32 = 0xe8e8ec;
const kDim: u32 = 0x6a7080;
const kGood: u32 = 0x6cc86c;
const kGold: u32 = 0xe8c040;
const kBad: u32 = 0xc84848;

/// Draws a 16x16 inventory icon (four tile words, as the game's tables have
/// them) with its top left at x, y in layout units.
fn icon(cv: Canvas, gfx: *const Gfx, words: [4]u16, x: usize, y: usize, owned: bool) void {
    if (!gfx.have_icons) {
        cv.rect(x + 2, y + 2, 12, 12, if (owned) kText else kCell);
        return;
    }
    for (words, 0..) |w, k| {
        const tile: usize = w & 0x3ff;
        if (tile >= 384) continue;
        const pal: usize = (w >> 10) & 7;
        const hflip = w & 0x4000 != 0;
        const vflip = w & 0x8000 != 0;
        const tx = x + (k & 1) * 8;
        const ty = y + (k >> 1) * 8;
        for (0..8) |py| {
            for (0..8) |px| {
                const sx = if (hflip) 7 - px else px;
                const sy = if (vflip) 7 - py else py;
                const v = gfx.tiles[tile * 64 + sy * 8 + sx];
                if (v == 0) continue;
                var rgb = gfx.hud[pal][v];
                if (!owned) rgb = dim(rgb);
                for (0..cv.scale) |dy| {
                    for (0..cv.scale) |dx| cv.put((tx + px) * cv.scale + dx, (ty + py) * cv.scale + dy, rgb);
                }
            }
        }
    }
}

fn item(table: anytype, i: usize) [4]u16 {
    return table[@min(i, table.len - 1)].v;
}

// A 3x5 font for the labels: each glyph is five rows of three bits.
const kGlyphs = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ/+-:.?'";
const kFont = [_]u15{
    0o00000, // space
    0o75557, 0o26227, 0o71747, 0o71717, 0o55711, 0o74717, 0o74757, 0o71111, 0o75757, 0o75717, // 0-9
    0o25755, 0o65656, 0o34443, 0o65556, 0o74647, 0o74644, 0o34553, 0o55755, 0o72227, 0o11153, // A-J
    0o55655, 0o44447, 0o57755, 0o65555, 0o25552, 0o65644, 0o25563, 0o65655, 0o34216, 0o72222, // K-T
    0o55557, 0o55552, 0o55775, 0o55255, 0o55222, 0o71247, // U-Z
    0o11244, 0o02720, 0o00700, 0o02020, 0o00002, 0o61202, 0o22000, // / + - : . ? '
};

/// Text in layout units at the canvas scale (glyphs are 4 units apart).
pub fn text(cv: Canvas, x: usize, y: usize, s: []const u8, rgb: u32) void {
    for (s, 0..) |ch, i| {
        const g = std.mem.indexOfScalar(u8, kGlyphs, std.ascii.toUpper(ch)) orelse continue;
        const bits = kFont[g];
        for (0..5) |row| {
            for (0..3) |col| {
                const shift: u4 = @intCast((4 - row) * 3 + (2 - col));
                if (bits >> shift & 1 != 0) cv.rect(x + i * 4 + col, y + row, 1, 1, rgb);
            }
        }
    }
}

fn number(cv: Canvas, x: usize, y: usize, n: usize, rgb: u32) void {
    var buf: [8]u8 = undefined;
    text(cv, x, y, std.fmt.bufPrint(&buf, "{d}", .{n}) catch "?", rgb);
}

/// Draws the whole tracker, or the overlay's part of it, onto `cv`.
pub fn draw(cv: Canvas, gfx: *Gfx, st: State, with_maps: bool) void {
    const height: usize = if (with_maps) kHeight else kOverlayHeight;
    cv.rect(0, 0, kWidth, height, kBackground);
    drawItems(cv, gfx, st);
    drawDungeons(cv, st, 84);
    if (with_maps) drawMaps(cv, gfx, st, 138);
}

fn drawItems(cv: Canvas, gfx: *const Gfx, st: State) void {
    const inv = st.at(0x38c); // what's been found of the items that share a slot
    const bows = st.at(0x38e);
    var bottles: usize = 0;
    for (0..4) |i| {
        if (st.at(0x35c + @as(u16, @intCast(i))) != 0) bottles += 1;
    }
    const sword = st.at(0x359);
    const Entry = struct { words: [4]u16, owned: bool, count: usize = 0 };
    const any_bow = bows & 0x80 != 0 or st.at(0x340) != 0;
    const silver = bows & 0x40 != 0 or st.at(0x340) >= 3;
    const entries = [_]Entry{
        .{ .words = item(hud.kHudItemBow, if (silver) 3 else 1), .owned = any_bow },
        .{ .words = item(hud.kHudItemBoomerang, 1), .owned = inv & 0x80 != 0 },
        .{ .words = item(hud.kHudItemBoomerang, 2), .owned = inv & 0x40 != 0 },
        .{ .words = item(hud.kHudItemHookshot, 1), .owned = st.at(0x342) != 0 },
        .{ .words = item(hud.kHudItemBombs, 1), .owned = st.at(0x38d) & 0x02 != 0 or st.at(0x343) != 0 },
        .{ .words = item(hud.kHudItemMushroom, 1), .owned = inv & 0x28 != 0 },
        .{ .words = item(hud.kHudItemMushroom, 2), .owned = inv & 0x10 != 0 },
        .{ .words = item(hud.kHudItemFireRod, 1), .owned = st.at(0x345) != 0 },

        .{ .words = item(hud.kHudItemIceRod, 1), .owned = st.at(0x346) != 0 },
        .{ .words = item(hud.kHudItemBombos, 1), .owned = st.at(0x347) != 0 },
        .{ .words = item(hud.kHudItemEther, 1), .owned = st.at(0x348) != 0 },
        .{ .words = item(hud.kHudItemQuake, 1), .owned = st.at(0x349) != 0 },
        .{ .words = item(hud.kHudItemTorch, 1), .owned = st.at(0x34a) != 0 },
        .{ .words = item(hud.kHudItemHammer, 1), .owned = st.at(0x34b) != 0 },
        .{ .words = item(hud.kHudItemFlute, 1), .owned = inv & 0x04 != 0 },
        .{ .words = item(hud.kHudItemFlute, 2), .owned = inv & 0x03 != 0 },

        .{ .words = item(hud.kHudItemBugNet, 1), .owned = st.at(0x34d) != 0 },
        .{ .words = item(hud.kHudItemBookMudora, 1), .owned = st.at(0x34e) != 0 },
        .{ .words = item(hud.kHudItemBottles, 2), .owned = bottles != 0, .count = bottles },
        .{ .words = item(hud.kHudItemCaneSomaria, 1), .owned = st.at(0x350) != 0 },
        .{ .words = item(hud.kHudItemCaneByrna, 1), .owned = st.at(0x351) != 0 },
        .{ .words = item(hud.kHudItemCape, 1), .owned = st.at(0x352) != 0 },
        .{ .words = item(hud.kHudItemMirror, 2), .owned = st.at(0x353) >= 2 },
        .{ .words = item(hud.kHudItemBoots, 1), .owned = st.at(0x355) != 0 },

        .{ .words = item(hud.kHudItemGloves, @max(st.at(0x354), 1)), .owned = st.at(0x354) != 0 },
        .{ .words = item(hud.kHudItemFlippers, 1), .owned = st.at(0x356) != 0 },
        .{ .words = item(hud.kHudItemMoonPearl, 1), .owned = st.at(0x357) != 0 },
        .{ .words = item(hud.kHudItemSword, if (sword >= 1 and sword <= 4) sword else 1), .owned = sword >= 1 and sword <= 4 },
        .{ .words = item(hud.kHudItemShield, @max(st.at(0x35a), 1)), .owned = st.at(0x35a) != 0 },
        .{ .words = item(hud.kHudItemArmor, st.at(0x35b)), .owned = true },
        .{ .words = item(hud.kHudPendants0, 1), .owned = st.at(0x374) & 0x07 != 0, .count = @popCount(st.at(0x374) & 0x07) },
        .{ .words = .{ 0x2D44, 0x2D45, 0xffff, 0xffff }, .owned = st.at(0x37a) & 0x7f != 0, .count = @popCount(st.at(0x37a) & 0x7f) },
    };
    for (entries, 0..) |e, i| {
        const x = (i % 8) * 24 + 4;
        const y = (i / 8) * 20 + 2;
        cv.rect(x - 2, y - 1, 20, 18, kCell);
        icon(cv, gfx, e.words, x, y, e.owned);
        if (e.count > 1 or (e.count == 1 and i >= 30)) number(cv, x + 13, y + 12, e.count, kText);
    }
    // Half or quarter magic.
    const magic = st.at(0x37b);
    if (magic != 0) text(cv, 4 + 7 * 24 - 2, 2 + 3 * 20 + 14, if (magic == 1) "1/2" else "1/4", kGold);
}

fn drawDungeons(cv: Canvas, st: State, top: usize) void {
    for (data.kDungeons, 0..) |d, i| {
        const x = (i % 3) * 64;
        const y = top + (i / 3) * 10;
        cv.rect(x + 1, y, 62, 9, kCell);
        const total = d.checks.len;
        const left = total - st.done(d.checks);
        text(cv, x + 3, y + 2, d.short, kText);
        // What's left to find, green once it's all been found.
        number(cv, x + 17, y + 2, left, if (left == 0) kGood else kText);
        // Small keys found here so far.
        const keys = st.at(d.keys_found);
        if (keys != 0) {
            text(cv, x + 29, y + 2, "K", kDim);
            number(cv, x + 33, y + 2, keys, kDim);
        }
        // Big key, map, compass, boss.
        if (st.has(d.big_key)) cv.rect(x + 42, y + 3, 3, 3, kGold);
        if (st.has(d.map)) cv.rect(x + 47, y + 3, 3, 3, 0x70a0e0);
        if (st.has(d.compass)) cv.rect(x + 52, y + 3, 3, 3, 0xe08040);
        if (d.boss) |b| cv.rect(x + 57, y + 2, 4, 5, if (st.has(b)) kGood else kBad);
    }
}

fn drawMaps(cv: Canvas, gfx: *Gfx, st: State, top: usize) void {
    const size = 84;
    const n = @min(size * cv.scale, 256);
    if (gfx.have_maps) scaleMaps(gfx, n);
    const dark_now = st.inWorldDark();
    for ([2]data.World{ .light, .dark }, 0..) |world, wi| {
        const x0 = 8 + wi * (size + 8);
        const here = dark_now == (world == .dark);
        cv.rect(x0 - 1, top - 1, size + 2, size + 2, if (here) kGold else kCell);
        const px0 = x0 * cv.scale;
        const py0 = top * cv.scale;
        if (gfx.have_maps) {
            for (0..n) |py| {
                for (0..n) |px| cv.put(px0 + px, py0 + py, gfx.scaled[wi][py * n + px]);
            }
        } else {
            cv.rect(x0, top, size, size, if (world == .light) 0x305830 else 0x403050);
        }
        // Checks: bright until found, grey once they have been.
        for (data.kLocations) |loc| {
            if (loc.world != world) continue;
            const done = st.done(loc.checks);
            const color: u32 = if (done == loc.checks.len) 0x505860 else if (done == 0) 0x60e0ff else 0xf0c040;
            marker(cv, x0, top, size, loc.x, loc.y, 2, color);
        }
        for (data.kDungeons) |d| {
            if (d.world != world) continue;
            const left = d.checks.len - st.done(d.checks);
            const beaten = if (d.boss) |b| st.has(b) else left == 0;
            const color: u32 = if (left == 0 and beaten) 0x505860 else if (beaten) kGood else kBad;
            marker(cv, x0, top, size, d.x, d.y, 3, color);
        }
    }
}

/// A square marker centered on a map position given in percent.
fn marker(cv: Canvas, x0: usize, y0: usize, size: usize, px: f32, py: f32, r: usize, color: u32) void {
    const cx: usize = @intFromFloat(@as(f32, @floatFromInt(size)) * px / 100.0);
    const cy: usize = @intFromFloat(@as(f32, @floatFromInt(size)) * py / 100.0);
    const x = x0 + @min(cx, size - 1);
    const y = y0 + @min(cy, size - 1);
    const lx = x -| r / 2;
    const ly = y -| r / 2;
    cv.rect(lx, ly, r + 1, r + 1, 0x000000);
    cv.rect(lx, ly, r, r, color);
}

test "modes cycle through all four and back" {
    var m = Mode.off;
    for (0..4) |_| m = m.next();
    try std.testing.expectEqual(Mode.off, m);
    try std.testing.expectEqual(Mode.overlay, Mode.fromName("Overlay").?);
}

test "the font has a glyph for every character it claims" {
    try std.testing.expectEqual(kGlyphs.len, kFont.len);
}
