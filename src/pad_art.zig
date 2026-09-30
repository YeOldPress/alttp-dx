//! A SNES controller, drawn in code, one pixel at a time, like it's 1991 and
//! I've been handed graph paper and a deadline.
//!
//! It shows up in two places: the Controls tab inside the game and the
//! Controls screen on the start menu. Neither knows how to draw a controller
//! and neither has to. They hand over a "put a pixel here" function and this
//! file does the rest, so the game's menu gets it at SNES size and the start
//! menu gets it three times bigger without either one lying about it.
//!
//! ## Why it has to be drawn like this
//!
//! Short version: there was no other controller to use, and two very
//! different menus both needed one.
//!
//! - **The game doesn't have one.** Everything else in the in-game menus
//!   is borrowed from the game itself: the boxes, the hearts, the item
//!   icons, the font all come out of the asset file built from your ROM, so
//!   they look exactly like Nintendo's. I went looking for a controller in
//!   there. There isn't one. A Link to the Past never once shows you a SNES
//!   pad, presumably because you're holding it.
//! - **This repo ships no art.** The whole deal is that the game's graphics
//!   come from your ROM and nothing of Nintendo's lives here. A PNG of their
//!   controller would be exactly the kind of thing that isn't supposed to
//!   be in here, so it's shapes and arithmetic instead of a picture of one.
//! - **The two menus can't share a picture anyway.** The in-game Controls
//!   tab paints over a finished SNES frame, pixel by pixel, in the game's
//!   256x224. The start menu is an SDL window at 640x480 with a debug font,
//!   and it runs before the game's assets are loaded, sometimes before they
//!   even exist. About the only thing those two have in common is being
//!   able to color a square, so that's the only thing this file asks for.
//! - **One button has to light up.** The point of the drawing is showing
//!   which button you're about to remap. With shapes, that's recoloring one
//!   circle. With an image, it's explaining to a PNG which of its pixels are
//!   the B button, and it doesn't care.
//! - **Shapes, not a hand-drawn pixel grid.** Every part is a circle, a
//!   capsule, a cross or a box with a position and a size, and each pixel is
//!   tested against the shapes' math. That's slower than a lookup table and
//!   nobody will ever notice, since the whole drawing is 110x44. What it
//!   buys: when the capsules touched or the arrows pointed the wrong way,
//!   the fix was changing one number instead of redrawing it all by hand.
//!   And the start menu's 3x version comes out crisp, because it's the same
//!   pixels, just bigger, not a blurry stretch.
//! - **Pixels are tested at their centers** (the + 0.5 below), so circles
//!   come out round instead of lopsided toward the top left, which is what
//!   integer corners do to a 4-pixel-radius button.
//! - **Outlines are free.** A pixel inside a shape with any neighbor outside
//!   it is edge, so every part outlines itself, and nobody had to draw a
//!   line. At this size a proper line-drawing algorithm would be showing
//!   off.
const std = @import("std");

/// Where the pixels go. The caller decides what a pixel even is - one game
/// pixel, or a 3x3 block on the start menu - and this file just keeps
/// calling `put` until a controller appears.
pub const Plot = struct {
    ctx: *const anyopaque,
    putFn: *const fn (ctx: *const anyopaque, x: i32, y: i32, rgb: u32) void,

    fn put(self: Plot, x: i32, y: i32, rgb: u32) void {
        self.putFn(self.ctx, x, y, rgb);
    }
};

// The anatomy, for anyone who hasn't held one since they had to blow into
// cartridges: a dog bone with two round ends and a slight dip along the
// bottom where your fingers go; L and R as thin strips hugging the top
// curves; the cross pad sunk in a ring on the left, with an arrow in each
// arm; the four face buttons in two slanted capsules, sunk in a bigger ring
// on the right; Select and Start as two little slanted pills in the middle,
// forever ignored.
//
// The first version of this got a lot of it wrong. The shoulders were one
// grey plank across the top, like someone glued a ruler to it. Then the
// arrows pointed inward, which is how you draw a controller that's
// frightened of its own buttons. It took an actual reference picture to get
// here, and it still leaves the Super Nintendo logo off: at this size it
// would be four pixels of smudge, and it isn't mine to draw anyway.
//
// Coordinates start at the drawing's top left. Every part is a shape that's
// filled and then outlined a pixel at a time: light lines, dark body, like
// the controller is posing for a blueprint.

/// The drawing's size, in its own pixels. L and R poke four pixels above the
/// top, because shoulder buttons don't respect bounding boxes.
pub const kWidth = 110;
pub const kHeight = 44;
pub const kShoulderRise = 4;

const kArtLine = 0xe0e0ec;
const kArtBody = 0x2c2c40;
const kArtWell = 0x1e1e2c;

const kLeftCx: f32 = 22;
const kRightCx: f32 = 88;
const kMidY: f32 = 22;

const Shape = union(enum) {
    circle: struct { cx: f32, cy: f32, r: f32 },
    /// A fat line with round ends. The face buttons live in two of these, and
    /// Select and Start are two tiny ones. Nintendo loved this shape.
    capsule: struct { x0: f32, y0: f32, x1: f32, y1: f32, r: f32 },
    cross: struct { cx: f32, cy: f32, arm: f32, half: f32 },
    rect: struct { x: f32, y: f32, w: f32, h: f32 },
    /// L or R: a slightly bigger circle than the body's end, cut down to
    /// the strip that peeks out over the top. The body gets drawn on top of
    /// it, which is the whole trick.
    shoulder: struct { right: bool },
    body,

    fn inside(self: Shape, px: i32, py: i32) bool {
        const x = @as(f32, @floatFromInt(px)) + 0.5;
        const y = @as(f32, @floatFromInt(py)) + 0.5;
        return switch (self) {
            .circle => |k| (x - k.cx) * (x - k.cx) + (y - k.cy) * (y - k.cy) <= k.r * k.r,
            .capsule => |k| blk: {
                const dx = k.x1 - k.x0;
                const dy = k.y1 - k.y0;
                const t = std.math.clamp(((x - k.x0) * dx + (y - k.y0) * dy) / (dx * dx + dy * dy), 0, 1);
                const nx = k.x0 + t * dx - x;
                const ny = k.y0 + t * dy - y;
                break :blk nx * nx + ny * ny <= k.r * k.r;
            },
            .cross => |k| blk: {
                const dx = @abs(x - k.cx);
                const dy = @abs(y - k.cy);
                break :blk (dx <= k.half and dy <= k.arm) or (dy <= k.half and dx <= k.arm);
            },
            .rect => |k| x >= k.x and x < k.x + k.w and y >= k.y and y < k.y + k.h,
            .shoulder => |k| blk: {
                const cx = if (k.right) kRightCx else kLeftCx;
                const d = (x - cx) * (x - cx) + (y - kMidY) * (y - kMidY);
                // From a little inside the middle out past the edge, which
                // is about where your index finger has lived since 1991.
                const toward_out = if (k.right) x - cx else cx - x;
                break :blk d <= 25.0 * 25.0 and y < 9 and toward_out > -6 and toward_out < 17;
            },
            .body => blk: {
                const lobe = 22.0;
                const l = (x - kLeftCx) * (x - kLeftCx) + (y - kMidY) * (y - kMidY) <= lobe * lobe;
                const r = (x - kRightCx) * (x - kRightCx) + (y - kMidY) * (y - kMidY) <= lobe * lobe;
                // The bridge between the ends sits a hair higher than they do
                // at the bottom. It's the dip in the real thing, and without
                // it this looked like a hot dog.
                const bridge = x >= kLeftCx and x <= kRightCx and y >= 0 and y <= 41.5;
                break :blk l or r or bridge;
            },
        };
    }

    fn bounds(self: Shape) [4]i32 {
        const b: [4]f32 = switch (self) {
            .circle => |k| .{ k.cx - k.r, k.cy - k.r, k.cx + k.r, k.cy + k.r },
            .capsule => |k| .{ @min(k.x0, k.x1) - k.r, @min(k.y0, k.y1) - k.r, @max(k.x0, k.x1) + k.r, @max(k.y0, k.y1) + k.r },
            .cross => |k| .{ k.cx - k.arm, k.cy - k.arm, k.cx + k.arm, k.cy + k.arm },
            .rect => |k| .{ k.x, k.y, k.x + k.w, k.y + k.h },
            .shoulder => .{ 0, -kShoulderRise, kWidth, 9 },
            .body => .{ 0, 0, kWidth, kHeight },
        };
        return .{ @intFromFloat(@floor(b[0]) - 1), @intFromFloat(@floor(b[1]) - 1), @intFromFloat(@ceil(b[2]) + 1), @intFromFloat(@ceil(b[3]) + 1) };
    }

    fn edge(self: Shape, x: i32, y: i32) bool {
        return !self.inside(x - 1, y) or !self.inside(x + 1, y) or !self.inside(x, y - 1) or !self.inside(x, y + 1);
    }
};

/// Fills a shape and outlines it: any pixel inside with a neighbor outside
/// is an edge. Brute force, but the whole drawing is smaller than a
/// thumbnail. `only` narrows the fill to where it overlaps something else,
/// which is how one arm of the cross lights up without the other three
/// getting jealous.
fn drawShape(plot: Plot, shape: Shape, fill_c: u32, line_c: ?u32, only: ?Shape) void {
    const b = shape.bounds();
    var y = b[1];
    while (y <= b[3]) : (y += 1) {
        var x = b[0];
        while (x <= b[2]) : (x += 1) {
            if (!shape.inside(x, y)) continue;
            const on_edge = shape.edge(x, y);
            if (only) |o| {
                if (on_edge or !o.inside(x, y)) continue;
            }
            const color = if (on_edge) line_c orelse fill_c else fill_c;
            plot.put(x, y, color);
        }
    }
}

/// The face buttons, in Controls order from A: right, bottom, top, left.
/// Yes, that's a weird order. It's zelda3.ini's order, and zelda3.ini was
/// here first.
const kFace = [4][2]f32{ .{ 97, 22 }, .{ 88, 31 }, .{ 88, 13 }, .{ 79, 22 } };

/// A tiny arrow in one arm of the cross, pointing out, the way the real pad
/// points them. It's a three-row triangle, which is as much triangle as the
/// pixels allow.
fn drawArrow(plot: Plot, dir: usize, color: u32) void {
    const cx: i32 = @intFromFloat(kLeftCx);
    const cy: i32 = @intFromFloat(kMidY);
    var row: i32 = 0;
    while (row < 3) : (row += 1) {
        var k: i32 = -row;
        while (k <= row) : (k += 1) {
            // Tip ten pixels out, widening back toward the middle. The first
            // version counted from the wrong end.
            const along = 10 - row;
            const p: [2]i32 = switch (dir) {
                0 => .{ cx + k, cy - along },
                1 => .{ cx + k, cy + along - 1 },
                2 => .{ cx - along, cy + k },
                else => .{ cx + along - 1, cy + k },
            };
            plot.put(p[0], p[1], color);
        }
    }
}

/// Draws the pad through `plot`, a pixel at a time, in the drawing's own
/// coordinates (0 to kWidth across, -kShoulderRise to kHeight down). `lit`
/// is the button you're on, filled in `lit_color` so you can see which one
/// you're about to remap, in Controls order: Up, Down, Left, Right, Select,
/// Start, A, B, X, Y, L, R.
pub fn draw(plot: Plot, lit: ?usize, lit_color: u32) void {
    const kArtLit = lit_color;
    const is = struct {
        fn f(l: ?usize, control: usize) bool {
            return l != null and l.? == control;
        }
    }.f;
    // L and R first, so the body can sit on top and hide everything but the
    // strips along the top. Painter's algorithm, like actual painters.
    for ([2]bool{ false, true }, 0..) |right, i| {
        drawShape(plot, .{ .shoulder = .{ .right = right } }, if (is(lit, 10 + i)) kArtLit else kArtBody, kArtLine, null);
    }
    drawShape(plot, .body, kArtBody, kArtLine, null);

    // The cross pad in its ring, an arrow in each arm, and the little dimple
    // in the middle your thumb has been resting in for thirty years. When
    // one direction is picked, only its arm fills in, and its arrow flips to
    // the body's color so it still shows.
    drawShape(plot, .{ .circle = .{ .cx = kLeftCx, .cy = kMidY, .r = 15.5 } }, kArtWell, kArtLine, null);
    const pad = Shape{ .cross = .{ .cx = kLeftCx, .cy = kMidY, .arm = 11.5, .half = 4 } };
    drawShape(plot, pad, kArtBody, kArtLine, null);
    const arms = [4]Shape{
        .{ .rect = .{ .x = kLeftCx - 4, .y = kMidY - 12, .w = 8, .h = 8 } },
        .{ .rect = .{ .x = kLeftCx - 4, .y = kMidY + 4, .w = 8, .h = 8 } },
        .{ .rect = .{ .x = kLeftCx - 12, .y = kMidY - 4, .w = 8, .h = 8 } },
        .{ .rect = .{ .x = kLeftCx + 4, .y = kMidY - 4, .w = 8, .h = 8 } },
    };
    for (arms, 0..) |arm, i| {
        if (is(lit, i)) drawShape(plot, pad, kArtLit, null, arm);
        drawArrow(plot, i, if (is(lit, i)) kArtBody else kArtLine);
    }
    drawShape(plot, .{ .circle = .{ .cx = kLeftCx, .cy = kMidY, .r = 2.5 } }, kArtBody, kArtLine, null);

    // Select and Start: slanted, identical, and unlabeled here, which is
    // exactly as much attention as anyone has ever paid them.
    const small = [2]Shape{
        .{ .capsule = .{ .x0 = 43, .y0 = 31, .x1 = 50, .y1 = 24, .r = 2.4 } },
        .{ .capsule = .{ .x0 = 56, .y0 = 31, .x1 = 63, .y1 = 24, .r = 2.4 } },
    };
    for (small, 0..) |sh, i| drawShape(plot, sh, if (is(lit, 4 + i)) kArtLit else kArtBody, kArtLine, null);

    // The face buttons: a ring, then two capsules, Y paired with X and B
    // with A, then the buttons in them. The capsules have to be thin enough
    // not to touch. The first time they touched, and the two outlines merged
    // into one confused blob.
    drawShape(plot, .{ .circle = .{ .cx = kRightCx, .cy = kMidY, .r = 19 } }, kArtWell, kArtLine, null);
    const caps = [2]Shape{
        .{ .capsule = .{ .x0 = kFace[3][0], .y0 = kFace[3][1], .x1 = kFace[2][0], .y1 = kFace[2][1], .r = 5.3 } },
        .{ .capsule = .{ .x0 = kFace[1][0], .y0 = kFace[1][1], .x1 = kFace[0][0], .y1 = kFace[0][1], .r = 5.3 } },
    };
    for (caps) |cap| drawShape(plot, cap, kArtBody, kArtLine, null);
    for (kFace, 0..) |f, i| {
        const shape = Shape{ .circle = .{ .cx = f[0], .cy = f[1], .r = 3.8 } };
        drawShape(plot, shape, if (is(lit, 6 + i)) kArtLit else kArtBody, kArtLine, null);
    }
}

test "no face button has escaped the controller" {
    for (kFace) |f| {
        try std.testing.expect(f[0] > 0 and f[0] < kWidth and f[1] > 0 and f[1] < kHeight);
        try std.testing.expect((Shape{ .body = {} }).inside(@intFromFloat(f[0]), @intFromFloat(f[1])));
    }
}
