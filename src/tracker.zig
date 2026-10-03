//! The item tracker for randomizer runs. Everything it shows is read from the
//! game's own save data in work ram every frame, so there's nothing to click
//! and nothing to get wrong; everything it draws comes out of the seed ROM,
//! so it looks like the game and ships no art.
//!
//! Two layouts, drawn at any scale. Large puts the items and a table of the
//! dungeons on the left and both world maps stacked on the right; compact is
//! the narrow one, with the dungeons three across and the maps side by side.
//! Nearly every part can be switched off or changed in [Randomizer]. The
//! panel beside the game, the separate window and the overlay all draw it
//! (the overlay leaves the maps out, since it sits on top of the game).
const std = @import("std");
const data = @import("tracker_data.zig");
const hud = @import("hud_tables.zig");
const seed_info = @import("seed_info.zig");

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
        const info = @typeInfo(Mode).@"enum";
        inline for (info.field_names, info.field_values) |field_name, value| {
            if (std.ascii.eqlIgnoreCase(name, field_name)) return @enumFromInt(value);
        }
        return null;
    }
};

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

// ------------------------------------------------------------- options

/// Everything about the tracker a player can choose, from [Randomizer] in
/// zelda3.ini. The defaults are what a first-time player sees.
pub const Options = struct {
    size: Size = .large,
    /// Which side of the game the panel goes on.
    side: Side = .right,
    items: bool = true,
    dungeons: bool = true,
    maps: Maps = .both,
    names: Names = .full,
    keys: bool = true,
    /// Big key, map and compass.
    dungeon_items: bool = true,
    bosses: bool = true,
    prizes: Prizes = .map,
    /// Which medallion Misery Mire and Turtle Rock want: a spoiler, so off.
    medallions: bool = false,
    counter: bool = true,
    missing: Missing = .dim,
    cleared: Cleared = .grey,
    markers: Markers = .large,
    background: Background = .dark,
    /// The overlay's opacity, in percent.
    opacity: u8 = 80,
    corner: Corner = .bottom_right,
    /// Small draws the overlay a pixel a unit, large at the panel's size.
    overlay_size: OverlaySize = .small,
    legend: bool = true,

    pub const Size = enum { large, compact };
    pub const Side = enum { right, left };
    pub const Maps = enum { both, current, off };
    pub const Names = enum { full, short };
    pub const Prizes = enum { map, always, off };
    pub const Missing = enum { dim, hide };
    pub const Cleared = enum { grey, hide };
    pub const Markers = enum { large, small };
    pub const Background = enum { dark, black, green, magenta };
    pub const Corner = enum { bottom_right, bottom_left, top_right, top_left };
    pub const OverlaySize = enum { small, large };

    /// Sets one option from its zelda3.ini key (TrackerSize and so on) and
    /// value. False when either isn't one of ours.
    pub fn set(self: *Options, key: []const u8, value: []const u8) bool {
        const kPrefix = "Tracker";
        if (key.len <= kPrefix.len or !std.ascii.startsWithIgnoreCase(key, kPrefix)) return false;
        const name = key[kPrefix.len..];
        inline for (.{
            .{ "Size", "size" },                .{ "Side", "side" },
            .{ "Items", "items" },              .{ "Dungeons", "dungeons" },
            .{ "Maps", "maps" },                .{ "Names", "names" },
            .{ "Keys", "keys" },                .{ "DungeonItems", "dungeon_items" },
            .{ "Bosses", "bosses" },            .{ "Prizes", "prizes" },
            .{ "Medallions", "medallions" },    .{ "Counter", "counter" },
            .{ "Missing", "missing" },          .{ "Cleared", "cleared" },
            .{ "Markers", "markers" },          .{ "Background", "background" },
            .{ "Opacity", "opacity" },          .{ "Corner", "corner" },
            .{ "OverlaySize", "overlay_size" },
            .{ "Legend", "legend" },
        }) |entry| {
            if (std.ascii.eqlIgnoreCase(name, entry[0])) {
                const field = &@field(self, entry[1]);
                const T = @TypeOf(field.*);
                const v = std.mem.trim(u8, value, " \t%");
                switch (@typeInfo(T)) {
                    .bool => field.* = parseBool(v) orelse return false,
                    .int => field.* = @intCast(std.math.clamp(std.fmt.parseInt(i32, v, 10) catch return false, 0, 100)),
                    .@"enum" => field.* = enumByName(T, v) orelse return false,
                    else => unreachable,
                }
                return true;
            }
        }
        return false;
    }
};

fn parseBool(v: []const u8) ?bool {
    for ([_][]const u8{ "1", "true", "on", "yes" }) |s| if (std.ascii.eqlIgnoreCase(v, s)) return true;
    for ([_][]const u8{ "0", "false", "off", "no" }) |s| if (std.ascii.eqlIgnoreCase(v, s)) return false;
    return null;
}

/// An enum value by name, with - standing in for _ the way the ini writes it.
fn enumByName(comptime T: type, v: []const u8) ?T {
    const info = @typeInfo(T).@"enum";
    inline for (info.field_names, info.field_values) |name, value| {
        if (name.len == v.len) {
            var same = true;
            for (name, v) |a, b| {
                const bb = if (b == '-') '_' else std.ascii.toLower(b);
                if (a != bb) same = false;
            }
            if (same) return @enumFromInt(value);
        }
    }
    return null;
}

/// What the tracker draws from: the graphics, the save data, the options
/// and, when the seed could be read, what it says about itself.
pub const Context = struct {
    gfx: *Gfx,
    st: State,
    opts: Options = .{},
    info: ?*const seed_info.Info = null,
};

// ------------------------------------------------------------- layout

/// The panel is always as tall as the game.
pub const kHeight = 224;
pub const kCompactWidth = 192;
/// The large layout: items and dungeons on the left, the maps on the right.
pub const kLeftWidth = 180;
pub const kMapsWidth = 110;
pub const kMaxWidth = kLeftWidth + kMapsWidth;

const Size2 = struct { w: usize, h: usize };

/// How big the tracker is drawn with these options, in layout units:
/// the panel and the window with maps, the overlay without.
pub fn size(o: Options, with_maps: bool) Size2 {
    const maps = with_maps and o.maps != .off;
    switch (o.size) {
        .compact => {
            var h: usize = 2;
            if (o.items) h += 82;
            if (o.dungeons or o.counter) h += 52;
            return .{ .w = kCompactWidth, .h = if (maps) kHeight else @max(h, 20) };
        },
        .large => {
            const left = o.items or o.dungeons or o.counter or !maps;
            const w: usize = (if (left) @as(usize, kLeftWidth) else 0) + (if (maps) @as(usize, kMapsWidth) else 0);
            return .{ .w = w, .h = if (maps) kHeight else @max(leftHeight(o), 20) };
        },
    }
}

/// How far down the large layout's left column goes.
fn leftHeight(o: Options) usize {
    var y: usize = 1;
    if (o.counter) y += 10;
    if (o.items) y += 82;
    if (o.dungeons) y += 9 + data.kDungeons.len * 9 + 1;
    return y;
}

// ------------------------------------------------------------- drawing

const Palette = struct { bg: u32, cell: u32, cell_on: u32 };

fn palette(b: Options.Background) Palette {
    return switch (b) {
        .dark => .{ .bg = 0x10141c, .cell = 0x1c2230, .cell_on = 0x2c3850 },
        .black => .{ .bg = 0x000000, .cell = 0x141418, .cell_on = 0x262a34 },
        // Keyed out by streaming software; the cells stay, as dark boxes.
        .green => .{ .bg = 0x00ff00, .cell = 0x1c2230, .cell_on = 0x2c3850 },
        .magenta => .{ .bg = 0xff00ff, .cell = 0x1c2230, .cell_on = 0x2c3850 },
    };
}

const kText: u32 = 0xf0f0f4;
const kDim: u32 = 0x78808e;
const kFaint: u32 = 0x3a4252;
const kGood: u32 = 0x60d860;
const kGold: u32 = 0xf0c840;
const kBad: u32 = 0xe05050;
const kDone: u32 = 0x565e6a;
const kTodo: u32 = 0x60e0ff;
const kHeading: u32 = 0x9ad0ff;
const kMapColor: u32 = 0x78a8f0;
const kCompassColor: u32 = 0xf09050;

/// Draws a 16x16 inventory icon (four tile words, as the game's tables have
/// them) with its top left at x, y in layout units.
fn icon(cv: Canvas, gfx: *const Gfx, words: [4]u16, x: usize, y: usize, owned: bool) void {
    if (!gfx.have_icons) {
        cv.rect(x + 2, y + 2, 12, 12, if (owned) kText else kFaint);
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

/// Text with a black shadow, for putting over icons and maps.
fn shadowText(cv: Canvas, x: usize, y: usize, s: []const u8, rgb: u32) void {
    text(cv, x + 1, y + 1, s, 0x000000);
    text(cv, x, y, s, rgb);
}

fn fmt(buf: []u8, comptime f: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, f, args) catch "?";
}

// Small pictures for the dungeon table, 7x7, a bit a pixel (bit 6 leftmost).
const Glyph = [7]u7;
const kKeyGlyph = Glyph{ 0b0011100, 0b0010100, 0b0011100, 0b0001000, 0b0001100, 0b0001000, 0b0001100 };
const kBigKeyGlyph = Glyph{ 0b0111110, 0b0100010, 0b0111110, 0b0001000, 0b0001110, 0b0001000, 0b0001110 };
const kMapGlyph = Glyph{ 0b1111111, 0b1000001, 0b1011101, 0b1000001, 0b1011001, 0b1000001, 0b1111111 };
const kCompassGlyph = Glyph{ 0b0011100, 0b0100010, 0b1001001, 0b1011101, 0b1001001, 0b0100010, 0b0011100 };
const kSkullGlyph = Glyph{ 0b0111110, 0b1111111, 0b1001001, 0b1111111, 0b0110110, 0b0101010, 0b0000000 };
const kCrystalGlyph = Glyph{ 0b0001000, 0b0011100, 0b0111110, 0b1111111, 0b0111110, 0b0011100, 0b0001000 };
const kPendantGlyph = Glyph{ 0b0011100, 0b0100010, 0b0011100, 0b0111110, 0b0111110, 0b0011100, 0b0001000 };

fn glyph(cv: Canvas, x: usize, y: usize, g: Glyph, rgb: u32) void {
    for (g, 0..) |row, ry| {
        for (0..7) |rx| {
            if (row >> @intCast(6 - rx) & 1 != 0) cv.rect(x + rx, y + ry, 1, 1, rgb);
        }
    }
}

/// A dungeon's prize as the tracker shows it: a glyph and its color, when
/// the options and what the player has found allow it to be known.
fn prizeLook(ctx: Context, di: usize) ?struct { g: Glyph, color: u32 } {
    if (ctx.opts.prizes == .off or di >= seed_info.kPrizeDungeons.len) return null;
    const info = ctx.info orelse return null;
    if (ctx.opts.prizes == .map and !ctx.st.has(data.kDungeons[di].map)) return null;
    return switch (info.prizes[di]) {
        .unknown => null,
        .green_pendant => .{ .g = kPendantGlyph, .color = 0x50d050 },
        .blue_pendant => .{ .g = kPendantGlyph, .color = 0x5890ff },
        .red_pendant => .{ .g = kPendantGlyph, .color = 0xf05050 },
        .crystal5, .crystal6 => .{ .g = kCrystalGlyph, .color = 0xff6070 },
        else => .{ .g = kCrystalGlyph, .color = 0x80c8ff },
    };
}

/// How a dungeon stands: the color for its row and its map marker.
fn dungeonColor(st: State, d: data.Dungeon) u32 {
    const left = d.checks.len - st.done(d.checks);
    const beaten = if (d.boss) |b| st.has(b) else left == 0;
    return if (left == 0 and beaten) kDone else if (beaten) kGood else kBad;
}

/// Draws the whole tracker, or the overlay's part of it (no maps), onto
/// `cv`, whose size should be size(ctx.opts, with_maps) times its scale.
pub fn draw(cv: Canvas, ctx: Context, with_maps: bool) void {
    const o = ctx.opts;
    const pal = palette(o.background);
    const sz = size(o, with_maps);
    cv.rect(0, 0, sz.w, sz.h, pal.bg);
    const maps = with_maps and o.maps != .off;
    switch (o.size) {
        .compact => {
            var y: usize = 2;
            if (o.items) {
                drawItems(cv, ctx, pal, 4, y, 24);
                y += 82;
            }
            if (o.dungeons or o.counter) {
                drawDungeonGrid(cv, ctx, pal, y);
                y += 52;
            }
            if (maps) {
                y = @max(y, 138);
                drawCompactMaps(cv, ctx, pal, y);
            }
        },
        .large => {
            const left = o.items or o.dungeons or o.counter or !maps;
            if (left) {
                var y: usize = 1;
                if (o.counter) {
                    drawCounter(cv, ctx, 3, y);
                    y += 10;
                }
                if (o.items) {
                    drawItems(cv, ctx, pal, 3, y, 22);
                    y += 82;
                }
                if (o.dungeons) drawDungeonTable(cv, ctx, pal, 2, y);
            }
            if (maps) drawLargeMaps(cv, ctx, pal, if (left) kLeftWidth else 0);
        },
    }
}

/// Items found out of the seed's total, hearts, and crystals against what
/// Ganon's Tower and Ganon want.
fn drawCounter(cv: Canvas, ctx: Context, x: usize, y: usize) void {
    const st = ctx.st;
    var buf: [32]u8 = undefined;
    const found = @as(u16, st.at(0x423)) | @as(u16, st.at(0x424)) << 8;
    const total: u16 = if (ctx.info) |i| i.total_items else 0;
    text(cv, x, y + 1, "ITEMS", kHeading);
    text(cv, x + 24, y + 1, if (total != 0) fmt(&buf, "{d}/{d}", .{ found, total }) else fmt(&buf, "{d}", .{found}), kText);
    text(cv, x + 66, y + 1, "HEARTS", kHeading);
    text(cv, x + 94, y + 1, fmt(&buf, "{d}", .{st.at(0x36c) / 8}), kText);
    const crystals = @popCount(st.at(0x37a) & 0x7f);
    if (ctx.info) |i| {
        text(cv, x + 108, y + 1, "GT", kHeading);
        text(cv, x + 118, y + 1, fmt(&buf, "{d}/{d}", .{ crystals, i.tower_crystals }), if (crystals >= i.tower_crystals) kGood else kText);
        text(cv, x + 138, y + 1, "GAN", kHeading);
        text(cv, x + 152, y + 1, fmt(&buf, "{d}/{d}", .{ crystals, i.ganon_crystals }), if (crystals >= i.ganon_crystals) kGood else kText);
    }
}

/// The inventory, 8 across and 4 down, `pitch` units apart.
fn drawItems(cv: Canvas, ctx: Context, pal: Palette, x0: usize, y0: usize, pitch: usize) void {
    const st = ctx.st;
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
    const kPendantsAt = 30;
    for (entries, 0..) |e, i| {
        const x = x0 + (i % 8) * pitch;
        const y = y0 + (i / 8) * 20;
        cv.rect(x, y, 20, 19, if (e.owned) pal.cell_on else pal.cell);
        if (e.owned or ctx.opts.missing == .dim) icon(cv, ctx.gfx, e.words, x + 2, y + 1, e.owned);
        if (e.count > 1 or (e.count == 1 and i >= kPendantsAt)) {
            var buf: [4]u8 = undefined;
            shadowText(cv, x + 15, y + 13, fmt(&buf, "{d}", .{e.count}), kText);
        }
    }
    // Half or quarter magic, in the armor's corner.
    const magic = st.at(0x37b);
    if (magic != 0) shadowText(cv, x0 + 5 * pitch + 1, y0 + 3 * 20 + 13, if (magic == 1) "1/2" else "1/4", kGold);

    // Which medallion each of the two medallion dungeons wants, under it.
    if (ctx.opts.medallions) if (ctx.info) |info| {
        for ([_]seed_info.Medallion{ .bombos, .ether, .quake }, 0..) |m, k| {
            const mm = info.misery_mire == m;
            const tr = info.turtle_rock == m;
            if (!mm and !tr) continue;
            const label: []const u8 = if (mm and tr) "BOTH" else if (mm) "MM" else "TR";
            shadowText(cv, x0 + (1 + k) * pitch + 1, y0 + 20 + 13, label, kGold);
        }
    };
}

/// The dungeons as a table, one to a row, for the large layout.
fn drawDungeonTable(cv: Canvas, ctx: Context, pal: Palette, x0: usize, y0: usize) void {
    const o = ctx.opts;
    const st = ctx.st;
    const name_w: usize = if (o.names == .full) 72 else 16;
    // Column positions, leaving out the ones switched off.
    const left_x = x0 + 4 + name_w + 2;
    var cur = left_x + 14;
    const keys_x = cur;
    if (o.keys) cur += 10;
    const items_x = cur;
    if (o.dungeon_items) cur += 26;
    const boss_x = cur;
    if (o.bosses) cur += 10;
    const prize_x = cur;
    if (o.prizes != .off) cur += 10;
    const right = cur;

    // The headings: words where there's room, pictures where there isn't.
    if (o.names == .full) text(cv, x0 + 4, y0 + 1, "DUNGEON", kHeading);
    text(cv, left_x - 2, y0 + 1, "LEFT", kHeading);
    if (o.keys) glyph(cv, keys_x, y0, kKeyGlyph, kHeading);
    if (o.dungeon_items) {
        glyph(cv, items_x, y0, kBigKeyGlyph, kHeading);
        glyph(cv, items_x + 8, y0, kMapGlyph, kHeading);
        glyph(cv, items_x + 16, y0, kCompassGlyph, kHeading);
    }
    if (o.bosses) glyph(cv, boss_x, y0, kSkullGlyph, kHeading);
    if (o.prizes != .off) glyph(cv, prize_x, y0, kCrystalGlyph, kHeading);

    var buf: [8]u8 = undefined;
    for (data.kDungeons, 0..) |d, i| {
        const y = y0 + 9 + i * 9;
        const status = dungeonColor(st, d);
        cv.rect(x0, y, right - x0, 8, pal.cell);
        // A stripe in the dungeon's state: red with its boss alive, green
        // beaten with checks left, grey when there's nothing left at all.
        cv.rect(x0, y, 2, 8, status);
        text(cv, x0 + 4, y + 2, if (o.names == .full) d.name else d.short, if (status == kDone) kDim else kText);
        const left = d.checks.len - st.done(d.checks);
        const n = fmt(&buf, "{d}", .{left});
        text(cv, left_x + 10 - n.len * 4, y + 2, n, if (left == 0) kGood else kGold);
        if (o.keys) {
            const keys = st.at(d.keys_found);
            text(cv, keys_x + 2, y + 2, if (keys == 0) "-" else fmt(&buf, "{d}", .{keys}), if (keys == 0) kFaint else kText);
        }
        if (o.dungeon_items) {
            glyph(cv, items_x, y, kBigKeyGlyph, if (st.has(d.big_key)) kGold else kFaint);
            glyph(cv, items_x + 8, y, kMapGlyph, if (st.has(d.map)) kMapColor else kFaint);
            glyph(cv, items_x + 16, y, kCompassGlyph, if (st.has(d.compass)) kCompassColor else kFaint);
        }
        if (o.bosses) if (d.boss) |b| glyph(cv, boss_x, y, kSkullGlyph, if (st.has(b)) kGood else kBad);
        if (o.prizes != .off and i < seed_info.kPrizeDungeons.len) {
            if (prizeLook(ctx, i)) |p| glyph(cv, prize_x, y, p.g, p.color) else text(cv, prize_x + 2, y + 2, "?", kFaint);
        }
    }
}

/// The dungeons three across, for the compact layout. The two spare cells
/// at the end hold the item count.
fn drawDungeonGrid(cv: Canvas, ctx: Context, pal: Palette, top: usize) void {
    const o = ctx.opts;
    const st = ctx.st;
    var buf: [16]u8 = undefined;
    if (o.dungeons) for (data.kDungeons, 0..) |d, i| {
        const x = (i % 3) * 64;
        const y = top + (i / 3) * 10;
        cv.rect(x + 1, y, 62, 9, pal.cell);
        const status = dungeonColor(st, d);
        cv.rect(x + 1, y, 1, 9, status);
        // The name takes the prize's color once it's known.
        const name_color = if (prizeLook(ctx, i)) |p| p.color else if (status == kDone) kDim else kText;
        text(cv, x + 3, y + 2, d.short, name_color);
        const left = d.checks.len - st.done(d.checks);
        text(cv, x + 16, y + 2, fmt(&buf, "{d}", .{left}), if (left == 0) kGood else kGold);
        if (o.keys) {
            const keys = st.at(d.keys_found);
            if (keys != 0) text(cv, x + 25, y + 2, fmt(&buf, "{d}", .{keys}), kDim);
        }
        if (o.dungeon_items) {
            glyph(cv, x + 31, y + 1, kBigKeyGlyph, if (st.has(d.big_key)) kGold else kFaint);
            glyph(cv, x + 39, y + 1, kMapGlyph, if (st.has(d.map)) kMapColor else kFaint);
            glyph(cv, x + 47, y + 1, kCompassGlyph, if (st.has(d.compass)) kCompassColor else kFaint);
        }
        if (o.bosses) if (d.boss) |b| glyph(cv, x + 55, y + 1, kSkullGlyph, if (st.has(b)) kGood else kBad);
    };
    if (o.counter) {
        const y = top + 4 * 10 + 2;
        const found = @as(u16, st.at(0x423)) | @as(u16, st.at(0x424)) << 8;
        const total: u16 = if (ctx.info) |i| i.total_items else 0;
        text(cv, 68, y, "ITEMS", kHeading);
        text(cv, 92, y, if (total != 0) fmt(&buf, "{d}/{d}", .{ found, total }) else fmt(&buf, "{d}", .{found}), kText);
        text(cv, 140, y, "HEARTS", kHeading);
        text(cv, 168, y, fmt(&buf, "{d}", .{st.at(0x36c) / 8}), kText);
    }
}

fn drawCompactMaps(cv: Canvas, ctx: Context, pal: Palette, top: usize) void {
    const kSize = 84;
    if (ctx.opts.maps == .current) {
        const world: data.World = if (ctx.st.inWorldDark()) .dark else .light;
        drawMap(cv, ctx, pal, world, (kCompactWidth - kSize) / 2, top, kSize, false);
        return;
    }
    drawMap(cv, ctx, pal, .light, 8, top, kSize, true);
    drawMap(cv, ctx, pal, .dark, 8 + kSize + 8, top, kSize, true);
}

fn drawLargeMaps(cv: Canvas, ctx: Context, pal: Palette, x0: usize) void {
    const o = ctx.opts;
    if (o.maps == .current) {
        const world: data.World = if (ctx.st.inWorldDark()) .dark else .light;
        const s = 104;
        text(cv, x0 + 3, 2, if (world == .light) "LIGHT WORLD" else "DARK WORLD", kHeading);
        drawMap(cv, ctx, pal, world, x0 + 3, 9, s, false);
        if (o.legend) drawLegend(cv, o, x0 + 3, 9 + s + 4);
        return;
    }
    const s: usize = if (o.legend) 98 else 101;
    text(cv, x0 + 6, 1, "LIGHT WORLD", kHeading);
    drawMap(cv, ctx, pal, .light, x0 + 6, 8, s, true);
    text(cv, x0 + 6, 8 + s + 3, "DARK WORLD", kHeading);
    drawMap(cv, ctx, pal, .dark, x0 + 6, 8 + s + 10, s, true);
    if (o.legend) drawLegend(cv, o, x0 + 6, 8 + s + 10 + s + 3);
}

/// What the marker colors mean.
fn drawLegend(cv: Canvas, o: Options, x: usize, y: usize) void {
    cv.rect(x, y, 4, 4, kTodo);
    text(cv, x + 6, y, "NEW", kDim);
    cv.rect(x + 22, y, 4, 4, kGold);
    text(cv, x + 28, y, "SOME", kDim);
    cv.rect(x + 48, y, 4, 4, kBad);
    text(cv, x + 54, y, "BOSS", kDim);
    if (o.cleared == .grey) {
        cv.rect(x + 74, y, 4, 4, kDone);
        text(cv, x + 80, y, "DONE", kDim);
    }
}

fn drawMap(cv: Canvas, ctx: Context, pal: Palette, world: data.World, x0: usize, top: usize, size_u: usize, show_here: bool) void {
    const gfx = ctx.gfx;
    const st = ctx.st;
    const o = ctx.opts;
    const wi: usize = @intFromEnum(world);
    const n = @min(size_u * cv.scale, 256);
    if (gfx.have_maps) scaleMaps(gfx, n);
    const here = st.inWorldDark() == (world == .dark);
    cv.rect(x0 - 1, top - 1, size_u + 2, size_u + 2, if (here and show_here) kGold else pal.cell);
    const px0 = x0 * cv.scale;
    const py0 = top * cv.scale;
    if (gfx.have_maps) {
        // Drawn at the size it was shrunk to, centered in its box.
        const off = (size_u * cv.scale - n) / 2;
        for (0..n) |py| {
            for (0..n) |px| cv.put(px0 + off + px, py0 + off + py, gfx.scaled[wi][py * n + px]);
        }
    } else {
        cv.rect(x0, top, size_u, size_u, if (world == .light) 0x305830 else 0x403050);
    }
    const small: usize = if (o.markers == .large) 3 else 2;
    // Checks: bright until found, gold when some are, grey once all are.
    for (data.kLocations) |loc| {
        if (loc.world != world) continue;
        const done = st.done(loc.checks);
        if (done == loc.checks.len and o.cleared == .hide) continue;
        const color: u32 = if (done == loc.checks.len) kDone else if (done == 0) kTodo else kGold;
        marker(cv, x0, top, size_u, loc.x, loc.y, small, color);
    }
    for (data.kDungeons) |d| {
        if (d.world != world) continue;
        const color = dungeonColor(st, d);
        if (color == kDone and o.cleared == .hide) continue;
        marker(cv, x0, top, size_u, d.x, d.y, small + 2, color);
    }
}

/// A square marker centered on a map position given in percent.
fn marker(cv: Canvas, x0: usize, y0: usize, size_u: usize, px: f32, py: f32, r: usize, color: u32) void {
    const cx: usize = @intFromFloat(@as(f32, @floatFromInt(size_u)) * px / 100.0);
    const cy: usize = @intFromFloat(@as(f32, @floatFromInt(size_u)) * py / 100.0);
    const x = x0 + @min(cx, size_u - 1);
    const y = y0 + @min(cy, size_u - 1);
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

test "options read the way zelda3.ini writes them" {
    var o = Options{};
    try std.testing.expect(o.set("TrackerSize", "compact"));
    try std.testing.expect(o.set("TrackerCorner", "top-left"));
    try std.testing.expect(o.set("TrackerOpacity", "60%"));
    try std.testing.expect(o.set("TrackerLegend", "0"));
    try std.testing.expect(!o.set("TrackerSize", "enormous"));
    try std.testing.expect(!o.set("Tracker", "panel"));
    try std.testing.expectEqual(Options.Size.compact, o.size);
    try std.testing.expectEqual(Options.Corner.top_left, o.corner);
    try std.testing.expectEqual(@as(u8, 60), o.opacity);
    try std.testing.expect(!o.legend);
}

test "every layout fits beside the game" {
    inline for (.{ Options.Size.large, Options.Size.compact }) |sz| {
        for ([_]bool{ false, true }) |legend| {
            const o = Options{ .size = sz, .legend = legend };
            const s = size(o, true);
            try std.testing.expect(s.w <= kMaxWidth and s.h <= kHeight);
            try std.testing.expect(size(o, false).h <= kHeight);
        }
    }
    // The large left column, everything on, fits the game's height.
    try std.testing.expect(leftHeight(.{}) <= kHeight);
}
