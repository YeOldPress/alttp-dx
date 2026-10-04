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

const std = @import("std");
const vars = @import("variables.zig");
const snes_pkg = @import("snes");
const Ppu = snes_pkg.ppu_types.Ppu;
const ppu_mod = snes_pkg.ppu;

const ForestArea = struct {
    screen: u16,
    /// The tile numbers of the area's canopy and the shadows on it.
    canopy_tiles: []const u16,
    /// The plain canopy that fills the margin past the mirrored run.
    canopy: u16,
};

/// The special areas whose left and right edges are woods all the way down.
const kForestAreas = [_]ForestArea{
    // The Master Sword's grove.
    .{ .screen = 0x80, .canopy_tiles = &.{ 0x115, 0x116, 0x118, 0x127, 0x128 }, .canopy = 0x7d18 },
};

/// How far in from an edge the canopy is looked for, in tiles.
const kMaxRun = 12;

fn currentArea() ?ForestArea {
    if (vars.player_is_indoors.* != 0) return null;
    const screen = vars.overworld_screen_index.*;
    for (kForestAreas) |a| {
        if (a.screen == screen) return a;
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
pub fn sourceLayers() u8 {
    return 0b10;
}

fn isCanopy(area: ForestArea, word: u16) bool {
    return std.mem.indexOfScalar(u16, area.canopy_tiles, word & 0x3ff) != null;
}

/// The PPU's question: which tile is at (x, y) of a layer's scrolled tilemap
/// space. Inside the area that's VRAM's to answer (null); past either edge,
/// it's the canopy along that edge mirrored outward, then plain canopy.
pub fn tileSource(ppu: *const Ppu, layer: u32, x: u32, y: u32) ?u16 {
    if (layer != 1) return null;
    const area = currentArea() orelse return null;
    const bg = &ppu.bgLayer[layer];
    // The PPU's scroll is the game's cut to 10 bits; its x is that plus where
    // on the line it is, so the game's scroll plus the same.
    const wx: i32 = @as(i32, vars.BG2HOFS_copy2.*) + @as(i16, @bitCast(@as(u16, @truncate(x -% bg.hScroll))));
    const left: i32 = vars.ow_scroll_vars0.xstart;
    const right: i32 = @as(i32, vars.ow_scroll_vars0.xend) + 256;
    if (!pastEdges(wx, left, right)) return null;

    const on_left = wx < left;
    // The tile `i` columns in from the edge on this side, on this line.
    const Edge = struct {
        ppu: *const Ppu,
        x: u32,
        y: u32,
        wx: i32,
        first: i32,
        step: i32,
        fn word(e: @This(), i: i32) u16 {
            const at = e.first + i * e.step;
            return ppu_mod.bgTilemapWord(e.ppu, 1, e.x +% @as(u32, @bitCast(at - e.wx)), e.y);
        }
    };
    const edge = Edge{
        .ppu = ppu,
        .x = x,
        .y = y,
        .wx = wx,
        .first = if (on_left) left else right - 8,
        .step = if (on_left) 8 else -8,
    };
    var run: i32 = 0;
    while (run < kMaxRun and isCanopy(area, edge.word(run))) : (run += 1) {}

    const out: i32 = if (on_left) @divFloor(left - 1 - wx, 8) else @divFloor(wx - right, 8);
    if (out >= run) return area.canopy;
    return edge.word(out) ^ 0x4000;
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
