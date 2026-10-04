//! The DX on the title screen, after "A LINK TO THE PAST".
//!
//! The subtitle is drawn from the game's own tiles, and its font has no D and
//! no X, so the two letters are drawn here, over the finished frame, in the
//! subtitle's style: 13 pixels tall, two-pixel strokes, a one-pixel black
//! outline, and the band of grays across the middle. Their colors aren't
//! fixed, though. Every frame they're read off a stroke of the subtitle's last
//! T, so the DX fades in with the logo, goes red with the sword's flash, and
//! fades out with the rest, all without knowing how any of that is done.

const std = @import("std");
const vars = @import("variables.zig");
const gfx = @import("game_gfx.zig");

/// A stroke of the T at the end of "PAST" that runs the letters' full height,
/// outline to outline: its colors are the ones the DX is drawn in.
const kSampleX = 219;
const kTop = 137;
const kHeight = 13;

/// Where the D's box starts. The subtitle leaves one empty column between
/// words, outline to outline, and none between the letters of a word, so the
/// DX is a word of its own one column past the T, and its two letters touch.
const kLeft = 225;

/// The letters' strokes, 11 tall; the outline goes round them. Drawn the
/// way the subtitle's font draws: uprights two pixels wide, everything
/// across one pixel tall, and serifs where the strokes end, as on its T.
const kGlyphs = [_][11]*const [7:0]u8{
    .{ // D
        "#####..",
        ".##.##.",
        ".##..#.",
        ".##..##",
        ".##..##",
        ".##..##",
        ".##..##",
        ".##..##",
        ".##..#.",
        ".##.##.",
        "#####..",
    },
    .{ // X
        "##..##.",
        ".#..#..",
        ".##.#..",
        "..##...",
        "..##...",
        "..##...",
        "..##...",
        "..##...",
        ".#.##..",
        ".#..#..",
        "##..##.",
    },
};

/// How wide a letter's strokes are, so the next one can start right after
/// its outline, as the subtitle's letters do.
fn glyphWidth(glyph: usize) i32 {
    var w: i32 = 0;
    for (kGlyphs[glyph]) |row| {
        for (row, 0..) |ch, x| {
            if (ch == '#') w = @max(w, @as(i32, @intCast(x)) + 1);
        }
    }
    return w;
}

/// Whether this pixel of a glyph's 9x13 box, outline included, is part of a
/// stroke.
fn inStroke(glyph: usize, x: i32, y: i32) bool {
    const gx = x - 1;
    const gy = y - 1;
    if (gx < 0 or gy < 0 or gx >= 7 or gy >= 11) return false;
    return kGlyphs[glyph][@intCast(gy)][@intCast(gx)] == '#';
}

/// Whether it's outline: not a stroke, but next to one, corners included.
fn inOutline(glyph: usize, x: i32, y: i32) bool {
    if (inStroke(glyph, x, y)) return false;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (inStroke(glyph, x + dx, y + dy)) return true;
        }
    }
    return false;
}

/// Whether the title screen, logo and all, is what's on screen: from the
/// logo fading in, through the sword and the background, to the fade out
/// into the story, or out to the file select when a button skips it.
var g_shown = false;

fn titleShowing() bool {
    const module = vars.main_module_index.*;
    const sub = vars.submodule_index.*;
    if (module == 0) return sub >= 5 and sub <= 8;
    if (module == 20) return vars.attract_state.* == 0;
    // Skipped: the file select fades the title out before it draws itself,
    // and the DX goes with it, but only if it was there to begin with.
    if (module == 1) return sub == 0 and g_shown;
    return false;
}

fn brightness(rgb: u32) u32 {
    return (rgb >> 16 & 0xff) + (rgb >> 8 & 0xff) + (rgb & 0xff);
}

pub fn drawOver(pixels: [*]u8, pitch: usize, width: usize, height: usize, scale: usize) void {
    g_shown = titleShowing();
    if (!g_shown) return;
    const cv = gfx.Canvas{ .pixels = pixels, .pitch = pitch, .width = width, .height = height, .scale = scale };

    // The subtitle's colors this frame, top to bottom.
    var colors: [kHeight]u32 = undefined;
    for (&colors, 0..) |*col, i| col.* = cv.get(kSampleX, kTop + @as(i32, @intCast(i)));
    // Only where the subtitle really is there: an outline darker than the
    // white inside it. Black-on-black, before it's faded in, has nothing to
    // show anyway.
    const outline = colors[0];
    if (brightness(outline) >= brightness(colors[1])) return;

    var left: i32 = kLeft;
    for (0..kGlyphs.len) |g| {
        defer left += glyphWidth(g) + 2;
        var y: i32 = 0;
        while (y < kHeight) : (y += 1) {
            var x: i32 = 0;
            while (x < 9) : (x += 1) {
                if (inStroke(g, x, y)) {
                    cv.fill(left + x, kTop + y, 1, 1, colors[@intCast(y)]);
                } else if (inOutline(g, x, y)) {
                    cv.fill(left + x, kTop + y, 1, 1, outline);
                }
            }
        }
    }
}

test "the letters' strokes leave room for their outline" {
    for (0..kGlyphs.len) |g| {
        // Nothing of a stroke in the outline's own row and column.
        var i: i32 = 0;
        while (i < 13) : (i += 1) {
            try std.testing.expect(!inStroke(g, 0, i) and !inStroke(g, 8, i));
        }
        i = 0;
        while (i < 9) : (i += 1) {
            try std.testing.expect(!inStroke(g, i, 0) and !inStroke(g, i, 12));
        }
        // And the outline does go all the way round: the D's top-left corner.
        try std.testing.expect(inOutline(g, 0, 0) or inOutline(g, 0, 1));
    }
}

test "the DX fits beside the subtitle without leaving the screen" {
    var right: i32 = kLeft;
    for (0..kGlyphs.len) |g| right += glyphWidth(g) + 2;
    try std.testing.expect(kLeft > kSampleX + 2);
    try std.testing.expect(right <= 256);
}
