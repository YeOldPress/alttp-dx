//! Widescreen margins for the special overworld areas that are one screen
//! wide, starting with the Master Sword's grove.
//!
//! The grove is exactly 256 pixels across, so the camera has nowhere to go
//! sideways and a wider frame looks past its edges at whatever the tilemap
//! still holds from the area before, which is blacked out. The grove is a
//! clearing in the middle of the Lost Woods, though, so past its edges the
//! canopy ought to carry on, and that's what the margins get, made of nothing
//! but the grove's own canopy.
//!
//! Along each edge, each row of the grove starts with canopy, its shadows
//! included, before the leaves that rim the clearing. A margin is that run
//! of canopy mirrored out across the edge, row by row, and past it plain
//! canopy to the side of the screen. A mirror always meets its own edge, so
//! there's no seam, and the shadows come out as rounded shapes either side
//! of it. The tiles come straight from the grove's tilemap in VRAM. The
//! woods' fog, on BG1, covers the whole tilemap already and carries on over
//! the margins by itself.
//!
//! The leaves stay inside. Mirrored out with the canopy, they made rims of
//! trees down the sides; mirrored back and forth, stripes.
//!
//! The river under the bridge, which shares the grove's screen, is one screen
//! wide too. There each row's edge tile is carried straight on across the
//! margin instead, so the cliff walls run out flat and the river runs on as
//! plain water. Mirroring a wider strip brought the bridge's supports and the
//! cliffs' slopes out with it, and the posts in the river at its left edge
//! would make a grid, so rows that start with one carry on as plain water,
//! after one mirrored tile that finishes off a post cut in half by the edge.
//! Its BG1 is the bridge overhead and its shadow, not fog, and past the area's
//! edges that layer's tilemap holds the grove next door, so in the margins it
//! shows a blank tile: the shadow belongs under the bridge.

const std = @import("std");
const vars = @import("variables.zig");
const snes_pkg = @import("snes");
const Ppu = snes_pkg.ppu_types.Ppu;
const ppu_mod = snes_pkg.ppu;

/// A tile the mirror style doesn't carry on, and what it carries on instead:
/// a tilemap word, or null for the first tile in from the edge that isn't
/// one of these.
const Swap = struct { tile: u16, with: ?u16 };

/// How an area's margins are made from its own edges.
const Style = enum {
    /// The run of canopy along each edge mirrored out, then plain canopy:
    /// woods past the trees, with the leaves kept inside.
    canopy,
    /// The area's edge carried straight on across the margin, row by row:
    /// walls run flat, water carries on as water. Its BG1 is left empty.
    mirror,
};

const ForestArea = struct {
    style: Style = .canopy,
    /// The special area's screen and the exit it's entered as. The screen
    /// alone isn't enough: the grove shares 0x80 with the river under the
    /// bridge, which has water at its sides, not woods.
    screen: u16,
    exit: u16,
    /// The tile numbers of the area's canopy and the shadows on it.
    canopy_tiles: []const u16,
    /// The plain canopy that fills the margin past the mirrored run.
    canopy: u16,
    /// For the mirror style, tiles that shouldn't be carried on across the
    /// margin, and what goes there instead.
    swaps: []const Swap = &.{},
    /// For the mirror style, whether the left margin carries on the right
    /// edge's rows rather than its own.
    from_right: bool = false,
};

/// The special areas that are one screen wide, and how each one's margins are
/// made.
const kForestAreas = [_]ForestArea{
    // The Master Sword's grove.
    .{ .screen = 0x80, .exit = 0x180, .canopy_tiles = &.{ 0x115, 0x116, 0x118, 0x127, 0x128 }, .canopy = 0x7d18 },
    // Under the bridge, where the river runs on past the sides.
    // The posts in the river along its left edge would make a grid repeated,
    // so those rows are plain river water instead, and the ones standing on
    // the shores give way to the shore beside them.
    .{ .screen = 0x80, .exit = 0x181, .style = .mirror, .from_right = true, .swaps = &.{
        .{ .tile = 0x1cf, .with = 0x1dfe },
        .{ .tile = 0x1e1, .with = 0x1dfe },
        .{ .tile = 0x1f1, .with = 0x1dfe },
        .{ .tile = 0x1e2, .with = null },
        .{ .tile = 0x1f0, .with = null },
    }, .canopy_tiles = &.{}, .canopy = 0 },
};

/// How far in from an edge the canopy is looked for, in tiles.
const kMaxRun = 12;

fn currentArea() ?ForestArea {
    if (vars.player_is_indoors.* != 0) return null;
    return areaFor(vars.overworld_screen_index.*, vars.dungeon_room_index.*);
}

/// The forest area at a special area's screen, entered as `exit`. While Link's
/// in one, dungeon_room_index still holds the exit he came in by.
fn areaFor(screen: u16, exit: u16) ?ForestArea {
    for (kForestAreas) |a| {
        if (a.screen == screen and a.exit == exit) return a;
    }
    return null;
}

/// Whether Link's in one of those areas, outdoors.
pub fn inForestArea() bool {
    return currentArea() != null;
}

/// Whether the margins are drawn from here this frame.
pub fn active(ppu: *const Ppu) bool {
    return ppu.extraLeftRight != 0 and inForestArea();
}

/// Which background layers the PPU should ask `tileSource` for: the map, BG2.
/// A tile of BG1's with nothing in it, for where the mirror style wants that
/// layer empty. Found afresh each frame the margins are drawn.
var g_blank_bg1: ?u16 = null;

fn findBlankTile(ppu: *const Ppu, layer: usize, words_per_tile: usize) ?u16 {
    const base: usize = ppu.bgLayer[layer].tileAdr;
    var tile: usize = 0;
    outer: while (tile < 1024) : (tile += 1) {
        for (0..words_per_tile) |i| {
            if (ppu.vram[(base + tile * words_per_tile + i) & 0x7fff] != 0) continue :outer;
        }
        return @intCast(tile);
    }
    return null;
}

pub fn sourceLayers(ppu: *const Ppu) u8 {
    const area = currentArea() orelse return 0;
    // BG1 is 4 bits a pixel here, so 16 words a tile.
    if (area.style == .mirror) g_blank_bg1 = findBlankTile(ppu, 0, 16);
    return switch (area.style) {
        // BG1 is the woods' fog, whose tilemap covers the whole map already.
        .canopy => 0b10,
        // BG1 is the bridge overhead, and past the area's edges its tilemap
        // holds the next area over, so it's emptied there.
        .mirror => if (g_blank_bg1 != null) 0b11 else 0b10,
    };
}

fn swapFor(area: ForestArea, word: u16) ?Swap {
    for (area.swaps) |swap| {
        if (swap.tile == word & 0x3ff) return swap;
    }
    return null;
}

fn isCanopy(area: ForestArea, word: u16) bool {
    return std.mem.indexOfScalar(u16, area.canopy_tiles, word & 0x3ff) != null;
}

/// The PPU's question: which tile is at (x, y) of a layer's scrolled tilemap
/// space. Inside the area that's VRAM's to answer (null); past either edge,
/// it's the canopy along that edge mirrored outward, then plain canopy.
pub fn tileSource(ppu: *const Ppu, layer: u32, x: u32, y: u32) ?u16 {
    if (layer > 1) return null;
    const area = currentArea() orelse return null;
    if (layer == 0 and area.style != .mirror) return null;
    const bg = &ppu.bgLayer[layer];
    // The PPU's scroll is the game's cut to 10 bits; its x is that plus where
    // on the line it is, so the game's scroll plus the same.
    const scroll: i32 = if (layer == 0) vars.BG1HOFS_copy2.* else vars.BG2HOFS_copy2.*;
    const wx: i32 = scroll + @as(i16, @bitCast(@as(u16, @truncate(x -% bg.hScroll))));
    // The area's edges are where BG2's are on screen, put into this layer's
    // own scroll, which for BG1 can run apart from BG2's.
    const shift: i32 = scroll - @as(i32, vars.BG2HOFS_copy2.*);
    const left: i32 = @as(i32, vars.ow_scroll_vars0.xstart) + shift;
    const right: i32 = @as(i32, vars.ow_scroll_vars0.xend) + 256 + shift;
    if (!pastEdges(wx, left, right)) return null;

    const on_left = wx < left;
    // The tile `i` columns in from the edge on this side, on this line.
    const Edge = struct {
        ppu: *const Ppu,
        layer: u32,
        x: u32,
        y: u32,
        wx: i32,
        first: i32,
        step: i32,
        fn word(e: @This(), i: i32) u16 {
            const at = e.first + i * e.step;
            return ppu_mod.bgTilemapWord(e.ppu, e.layer, e.x +% @as(u32, @bitCast(at - e.wx)), e.y);
        }
    };
    const edge = Edge{
        .ppu = ppu,
        .layer = layer,
        .x = x,
        .y = y,
        .wx = wx,
        .first = if (on_left) left else right - 8,
        .step = if (on_left) 8 else -8,
    };
    const out: i32 = if (on_left) @divFloor(left - 1 - wx, 8) else @divFloor(wx - right, 8);
    switch (area.style) {
        .mirror => {
            // BG1 is the bridge overhead and its shadow, which belongs over
            // the river under it and nowhere past the area.
            if (layer == 0) return g_blank_bg1;
            // Posts are a left half and its mirror image, so the right half
            // of one standing across the edge is finished off by one
            // mirrored tile.
            const own = edge.word(0);
            if (swapFor(area, own) != null and own & 0x4000 != 0 and out == 0) return own ^ 0x4000;
            // Past that, the edge column carried straight on, so walls run
            // flat and water stays water: both sides from the right edge's,
            // when the left one has a different shore.
            const from = if (on_left and area.from_right)
                Edge{ .ppu = ppu, .layer = layer, .x = x, .y = y, .wx = wx, .first = right - 8, .step = -8 }
            else
                edge;
            var w = from.word(0);
            if (swapFor(area, w)) |swap| {
                // A post at the edge would make a row of posts, so the row
                // goes on as what's around it instead.
                if (swap.with) |with| return with;
                var col: i32 = 1;
                while (col < kMaxRun and swapFor(area, from.word(col)) != null) col += 1;
                w = from.word(col);
            }
            // Every other tile mirrored, so each meets its own reflection.
            return if (@mod(out, 2) == 0) w ^ 0x4000 else w;
        },
        .canopy => {
            var run: i32 = 0;
            while (run < kMaxRun and isCanopy(area, edge.word(run))) : (run += 1) {}
            if (out >= run) return area.canopy;
            return edge.word(out) ^ 0x4000;
        },
    }
}

/// Whether `wx` is outside an area spanning `left` up to `right`.
fn pastEdges(wx: i32, left: i32, right: i32) bool {
    return wx < left or wx >= right;
}

test "only the margins are woods" {
    const t = std.testing;
    // A grove whose camera can't move: 0 up to 256.
    try t.expect(pastEdges(-1, 0, 256));
    try t.expect(!pastEdges(0, 0, 256));
    try t.expect(!pastEdges(255, 0, 256));
    try t.expect(pastEdges(256, 0, 256));
}

test "the grove and the river under the bridge share a screen and not a style" {
    const t = std.testing;
    try t.expectEqual(Style.canopy, areaFor(0x80, 0x180).?.style); // the Master Sword's grove
    try t.expectEqual(Style.mirror, areaFor(0x80, 0x181).?.style); // under the bridge
    try t.expect(areaFor(0x81, 0x182) == null); // Zora's river
}

test "the bridge carries its edge on past its posts" {
    const area = areaFor(0x80, 0x181).?;
    try std.testing.expect(swapFor(area, 0x5dcf) != null); // a post, flipped or not
    try std.testing.expect(swapFor(area, 0x1dfe) == null); // the water itself
}

test "the grove's canopy is canopy and its leaves aren't" {
    const t = std.testing;
    const grove = kForestAreas[0];
    try t.expect(isCanopy(grove, 0x7d18)); // plain canopy
    try t.expect(isCanopy(grove, 0x7d28)); // its shadow
    try t.expect(isCanopy(grove, 0xfd18)); // flipped, still canopy
    try t.expect(!isCanopy(grove, 0xfd14)); // leaves
    try t.expect(!isCanopy(grove, 0x08aa)); // the grass
    // The fill is canopy itself, so a run of it carries on into the fill.
    try t.expect(isCanopy(grove, grove.canopy));
}
