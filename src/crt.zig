//! Old-TV and handheld looks for the finished frame: what each one is, and
//! the pattern of lines and phosphors it lays over the picture.
//!
//! The work each frame is the GPU's, through SDL's renderer (crt_gpu.zig):
//! this only says what to draw, and builds the pattern, once, whenever the
//! window or the look changes. The picture is drawn `scale` times its SNES
//! size, every SNES pixel an S by S block: each line a beam of light with a
//! darker gap under it, and over that a TV's phosphors, the stripes of an
//! aperture grille, the staggered bricks of a slot mask, or the grid of an
//! LCD, with the corners darkened for a tube. Before that, a composite
//! cable's sideways smear blends the game's dithered patterns into the shades
//! they were drawn to make on a TV, and after it a glow lets bright things
//! bleed a soft halo. A gain puts back the light the gaps and phosphors take
//! away. The scale follows the window, so the lines and phosphors land on the
//! screen's own pixels instead of being smeared by a second resize.
const std = @import("std");

pub const Preset = enum(u8) {
    off,
    /// Scanlines alone.
    scanlines,
    /// Hard lines and a strong grille, like an arcade monitor up close.
    arcade,
    /// Gentle lines and a faint grille.
    soft,
    /// A home TV: soft lines, a slot mask, a glow, a little smear, darker
    /// corners.
    tv,
    /// A composite cable's smear, with light lines.
    composite,
    /// A handheld's screen: a fine grid between the pixels, no lines.
    lcd,

    pub fn fromName(name: []const u8) ?Preset {
        inline for (@typeInfo(Preset).@"enum".field_names) |n| {
            if (std.ascii.eqlIgnoreCase(name, n)) return @field(Preset, n);
        }
        return null;
    }
};

pub const Mask = enum { none, aperture, slot, shadow, lcd };

pub const Look = struct {
    /// The brightness of a SNES line's last row, the gap between beams.
    gap: f32 = 1,
    /// The brightness of its first row, the beam's soft top edge, when a
    /// line's at least four rows tall. The rest is the beam itself, full.
    edge: f32 = 1,
    mask: Mask = .none,
    /// How much light the mask's dark parts let through: for the grille and
    /// the slot mask, a channel through the other colors' stripes; for the
    /// LCD, the gap between pixels.
    mask_through: f32 = 1,
    /// Brightening to make up for the rest, up to twice as bright.
    gain: f32 = 1,
    /// The composite smear: 0 none, 1 slight, 2 full.
    blur: u2 = 0,
    /// How much of the glow is added on.
    glow: f32 = 0,
    /// How much darker the corners are.
    vignette: f32 = 0,
    /// How much of a phosphor's light is left a frame later, so moving
    /// things leave a short fading trail: 0 none.
    afterglow: f32 = 0,
    /// The haze bright light makes inside the glass, wider and redder than
    /// the glow: how much of it.
    halation: f32 = 0,

    // With the GPU shader (crt.frag):
    /// The beam's width, as a share of the line spacing, at black and at full
    /// brightness: dark lines thin, bright ones fat. 0 for no beam, flat
    /// pixels.
    beam_min: f32 = 0,
    beam_max: f32 = 0,
    /// How far the red and blue beams sit off the green, in SNES pixels.
    deconverge: f32 = 0,
    /// The composite signal: brightness into its neighbors, 0 to 1, and
    /// color spread, in SNES pixels. Both 0 for an RGB cable.
    luma_blur: f32 = 0,
    chroma_blur: f32 = 0,
    /// The shader's gain, which works in linear light and needs less.
    shader_gain: f32 = 1,
    /// A composite signal made and decoded (ntsc.frag): its rainbow on fine
    /// detail and dot crawl at color edges, 0 to 1. When it's there it does
    /// the smear, and the two blurs above are only for when it isn't.
    ntsc: f32 = 0,
    /// How the signal's taken apart: how far color spreads past its edges
    /// and how wide brightness is averaged, in SNES pixels (1.5 is one
    /// carrier wave, which leaves no dots on a flat color; less lets dot
    /// crawl through); how much the TV sharpens, leaving halos; the cable's
    /// ghost; the signal's noise.
    ntsc_chroma: f32 = 1.2,
    ntsc_luma: f32 = 1.5,
    ntsc_ring: f32 = 0,
    ntsc_ghost: f32 = 0,
    ntsc_noise: f32 = 0,
};

pub fn look(preset: Preset) Look {
    return switch (preset) {
        .off => .{},
        .scanlines => .{ .gap = 0.2, .edge = 0.85, .gain = 1.25, .beam_min = 0.22, .beam_max = 0.45 },
        .arcade => .{ .gap = 0.15, .edge = 0.8, .mask = .aperture, .mask_through = 0.6, .gain = 1.6, .vignette = 0.25, .afterglow = 0.45, .halation = 0.08, .beam_min = 0.2, .beam_max = 0.42, .deconverge = 0.12, .shader_gain = 1.45 },
        .soft => .{ .gap = 0.45, .edge = 0.9, .mask = .shadow, .mask_through = 0.75, .gain = 1.35, .vignette = 0.2, .afterglow = 0.35, .beam_min = 0.3, .beam_max = 0.55, .shader_gain = 1.3 },
        .tv => .{ .gap = 0.4, .edge = 0.85, .mask = .slot, .mask_through = 0.7, .gain = 1.35, .blur = 1, .glow = 0.3, .vignette = 0.3, .afterglow = 0.55, .halation = 0.12, .beam_min = 0.26, .beam_max = 0.5, .deconverge = 0.25, .luma_blur = 0.35, .chroma_blur = 1.2, .shader_gain = 1.4, .ntsc = 0.6, .ntsc_chroma = 1.6, .ntsc_ring = 0.25, .ntsc_ghost = 0.05, .ntsc_noise = 0.02 },
        // A cheap TV on a composite cable: color everywhere it shouldn't be,
        // halos, a ghost and a little noise, through a light shadow mask.
        .composite => .{ .gap = 0.5, .edge = 0.9, .mask = .shadow, .mask_through = 0.85, .gain = 1.25, .blur = 2, .glow = 0.2, .afterglow = 0.45, .beam_min = 0.3, .beam_max = 0.55, .deconverge = 0.15, .luma_blur = 0.6, .chroma_blur = 2.5, .shader_gain = 1.15, .ntsc = 1, .ntsc_chroma = 2.6, .ntsc_luma = 1.2, .ntsc_ring = 0.6, .ntsc_ghost = 0.12, .ntsc_noise = 0.04 },
        // An LCD's slow pixels ghost a little too.
        .lcd => .{ .gap = 0.6, .mask = .lcd, .mask_through = 0.6, .gain = 1.25, .afterglow = 0.3, .shader_gain = 1.2 },
    };
}

/// What a preset starts out with when it's picked, or reset to: the sliders
/// at 100 percent, and a curve and bezel to suit it, the TVs curved and
/// framed, the monitors a little curved, the plain and the LCD flat.
pub const Defaults = struct { curvature: u8 = 0, bezel: bool = false };

pub fn defaultsFor(preset: Preset) Defaults {
    return switch (preset) {
        .off, .scanlines, .lcd => .{},
        .arcade => .{ .curvature = 25 },
        .soft => .{ .curvature = 30 },
        .tv => .{ .curvature = 50, .bezel = true },
        .composite => .{ .curvature = 40, .bezel = true },
    };
}

/// The player's adjustments to a preset, each a share of the preset's own:
/// 1 as it is, 0 none, up to 2.
pub const Tuning = struct {
    scanlines: f32 = 1,
    mask: f32 = 1,
    glow: f32 = 1,
    afterglow: f32 = 1,
};

/// A preset as adjusted. The gains follow the lines and the mask, which they
/// make up for, so turning those down doesn't wash the picture out.
pub fn tuned(preset: Preset, t: Tuning) Look {
    var l = look(preset);
    const s = t.scanlines;
    const m = t.mask;
    // Each part left exactly as the preset has it at 100 percent.
    if (s != 1) {
        l.gap = std.math.clamp(1 - (1 - l.gap) * s, 0, 1);
        l.edge = std.math.clamp(1 - (1 - l.edge) * s, 0, 1);
    }
    if (m != 1) {
        l.mask_through = std.math.clamp(1 - (1 - l.mask_through) * m, 0, 1);
        l.shader_gain = 1 + (l.shader_gain - 1) * m;
    }
    if (s != 1 or m != 1) l.gain = 1 + (l.gain - 1) * (s + m) / 2;
    // The beam: stronger lines are narrower beams; none at all is flat.
    if (s != 1 and l.beam_max > 0) {
        if (s < 0.05) {
            l.beam_min = 0;
            l.beam_max = 0;
        } else {
            l.beam_min = std.math.clamp(l.beam_min / s, 0.08, 1.5);
            l.beam_max = std.math.clamp(l.beam_max / s, 0.08, 1.5);
        }
    }
    if (t.glow != 1) {
        l.glow *= t.glow;
        l.halation *= t.glow;
    }
    if (t.afterglow != 1) l.afterglow = @min(l.afterglow * t.afterglow, 0.9);
    return l;
}

/// The biggest scale drawn: a 4K screen's, where the phosphors come out
/// finest. Past this the frame's too big to be worth it.
pub const kMaxScale = 10;

/// The scale for a window this many pixels tall: as many screen pixels to a
/// SNES pixel as fit, and at least two, below which a line has no room for a
/// gap.
pub fn scaleFor(output_height: c_int, snes_height: c_int) u8 {
    const fit = @divTrunc(output_height, @max(snes_height, 1));
    return @intCast(std.math.clamp(fit, 2, kMaxScale));
}

/// How much of a channel gets through at screen pixel (x, y), at `scale`
/// screen pixels to a SNES pixel: the line's row and the mask's column,
/// before the corners and the gain.
fn through(l: Look, scale: usize, x: usize, y: usize, ch: usize) f32 {
    const row = y % scale;
    // The last row of every line is the gap, whatever the scale, so a
    // smaller window keeps its lines.
    const line: f32 = if (row == scale - 1) l.gap else if (row == 0 and scale >= 4) l.edge else 1;
    // With fewer than three screen pixels to a SNES pixel the phosphors would
    // be coarser than the picture, so there are none, except the LCD's grid.
    const mask: Mask = if (scale < 3 and l.mask != .lcd) .none else l.mask;
    const m: f32 = switch (mask) {
        .none => 1,
        // The grille's columns go red, green, blue; a channel's own stripe
        // lets it all through, the others some of it.
        .aperture => if (x % 3 == ch) 1 else l.mask_through,
        // Dots: the same three colors, each row of triads a step along.
        .shadow => if ((x + (y % 2) * 2) % 3 == ch) 1 else l.mask_through,
        // The same stripes cut into bricks: every other triad's break falls
        // halfway down the line, the rest at its end with the gap.
        .slot => blk: {
            const stripe: f32 = if (x % 3 == ch) 1 else l.mask_through;
            const odd = (x / 3) % 2 == 1;
            const brk = odd and scale >= 4 and row == (scale - 1) / 2;
            break :blk if (brk) stripe * l.mask_through else stripe;
        },
        // A gap down the right of every pixel; the lines' gap is the one
        // along the bottom.
        .lcd => if (x % scale == scale - 1) l.mask_through else 1,
    };
    return line * m;
}

/// The pattern laid over the picture, `w` by `h` SNES pixels at `scale`, as
/// 0x00RRGGBB pixels the picture's multiplied by: the lines, the mask, and
/// the darker corners.
pub fn pattern(l: Look, w: usize, h: usize, scale: usize, out: []u32) void {
    const pw = w * scale;
    const ph = h * scale;
    // The lines and the mask repeat every two lines (the shadow mask's dots
    // shift every other screen row) and every few columns: the slot mask's
    // two triads, or the LCD's pixel. Worked out once, they're a table; the
    // corners, which don't repeat, are a sum of two squares.
    const period: usize = switch (l.mask) {
        .lcd => scale,
        else => 6,
    };
    var base: [2 * kMaxScale][kMaxScale][3]f32 = undefined;
    for (0..2 * scale) |row| {
        for (0..period) |col| {
            for (0..3) |ch| base[row][col][ch] = through(l, scale, col, row, ch);
        }
    }
    const xs = std.heap.c_allocator.alloc(f32, pw) catch return;
    defer std.heap.c_allocator.free(xs);
    const cx: f32 = @as(f32, @floatFromInt(pw)) / 2;
    const cy: f32 = @as(f32, @floatFromInt(ph)) / 2;
    for (xs, 0..) |*v, x| {
        const dx = (@as(f32, @floatFromInt(x)) + 0.5 - cx) / cx;
        v.* = dx * dx;
    }
    for (0..ph) |y| {
        const dy = (@as(f32, @floatFromInt(y)) + 0.5 - cy) / cy;
        const row = &base[y % (2 * scale)];
        const line = out[y * pw ..][0..pw];
        var col: usize = 0;
        for (line, 0..) |*o, x| {
            // Darker the further out, by the square of the distance from the
            // middle, margins included: a corner, 2 out, loses `vignette`.
            const v = @max(1 - l.vignette * (xs[x] + dy * dy) / 2, 0);
            const k = &row[col];
            const r: u32 = @intFromFloat(@min(k[0] * v, 1) * 255 + 0.5);
            const g: u32 = @intFromFloat(@min(k[1] * v, 1) * 255 + 0.5);
            const b: u32 = @intFromFloat(@min(k[2] * v, 1) * 255 + 0.5);
            o.* = r << 16 | g << 8 | b;
            col += 1;
            if (col == period) col = 0;
        }
    }
}

// ------------------------------------------------------------- the bezel

/// Where the picture sits inside the bezel, as a share of the shown area's
/// height on every side.
pub const kBezelInset: f32 = 0.045;
/// How round the corners are, as a share of the shown area's height.
pub const kCornerRadius: f32 = 0.035;

/// What's laid over the picture's edges, `w` by `h` pixels of 0xAARRGGBB:
/// with `frame`, a TV's dark plastic surround with a rounded opening `inset`
/// pixels in, a lighter lip round the opening where the glass meets it; and
/// without, just the picture's corners rounded off in black. Clear where
/// the picture shows.
pub fn bezel(w: usize, h: usize, inset: f32, radius: f32, frame: bool, out: []u32) void {
    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    // The opening, by its middle and half-size, less the corners' radius.
    const hx = fw / 2 - inset - radius;
    const hy = fh / 2 - inset - radius;
    const lip = @max(inset * 0.18, 1.5);
    for (0..h) |y| {
        const py = @abs(@as(f32, @floatFromInt(y)) + 0.5 - fh / 2);
        for (0..w) |x| {
            const px = @abs(@as(f32, @floatFromInt(x)) + 0.5 - fw / 2);
            // How far outside the rounded opening, negative inside.
            const qx = @max(px - hx, 0);
            const qy = @max(py - hy, 0);
            const d = @sqrt(qx * qx + qy * qy) + @min(@max(px - hx, py - hy), 0) - radius;
            const alpha = std.math.clamp(d + 0.5, 0, 1);
            var color: u32 = 0;
            if (frame) {
                // Plastic, a little lighter toward the top, with a lip that
                // catches the light round the opening, falling off outwards.
                const t = @as(f32, @floatFromInt(y)) / fh;
                var shade: f32 = 30 - 10 * t;
                if (d < lip) shade += 26 * (1 - d / lip);
                const v: u32 = @intFromFloat(std.math.clamp(shade, 0, 255));
                color = v << 16 | v << 8 | (v + 2);
            }
            out[y * w + x] = @as(u32, @intFromFloat(alpha * 255 + 0.5)) << 24 | color;
        }
    }
}

test "the presets read back from their names, whatever the case" {
    try std.testing.expectEqual(Preset.arcade, Preset.fromName("Arcade").?);
    try std.testing.expectEqual(Preset.tv, Preset.fromName("TV").?);
    try std.testing.expectEqual(Preset.off, Preset.fromName("off").?);
    try std.testing.expectEqual(@as(?Preset, null), Preset.fromName("vhs"));
}

test "the scale fits the window, within reason" {
    try std.testing.expectEqual(@as(u8, 2), scaleFor(300, 224));
    try std.testing.expectEqual(@as(u8, 4), scaleFor(900, 224));
    try std.testing.expectEqual(@as(u8, kMaxScale), scaleFor(4000, 224));
}

test "every line keeps its gap at any scale" {
    for (2..kMaxScale + 1) |s| {
        var out: [kMaxScale * kMaxScale]u32 = undefined;
        pattern(look(.scanlines), 1, 1, s, out[0 .. s * s]);
        // The beam, above the gap, lets it all through; the last row not.
        try std.testing.expectEqual(@as(u32, 0xffffff), out[((s - 1) / 2) * s]);
        try std.testing.expect(out[(s - 1) * s] & 0xff < 0x80);
    }
}

test "the grille favors each column's own color" {
    var out: [16]u32 = undefined;
    pattern(look(.arcade), 1, 1, 4, &out);
    // Row 1, the beam, away from the corners: column 0 is the red stripe.
    const red = out[4];
    try std.testing.expect((red >> 16 & 0xff) > (red >> 8 & 0xff));
}

test "the LCD grid darkens each pixel's right and bottom edge" {
    var out: [16]u32 = undefined;
    pattern(look(.lcd), 1, 1, 4, &out);
    try std.testing.expect(out[3] & 0xff < out[0] & 0xff);
    try std.testing.expect(out[12] & 0xff < out[0] & 0xff);
}

test "the bezel is clear in the middle and solid at the edges, round at the corners" {
    var out: [100 * 80]u32 = undefined;
    bezel(100, 80, 8, 6, true, &out);
    try std.testing.expectEqual(@as(u32, 0), out[40 * 100 + 50] >> 24);
    try std.testing.expectEqual(@as(u32, 255), out[40 * 100 + 2] >> 24);
    // Just inside the opening's straight edge is clear, but the same depth
    // in at a corner is the bezel's, rounded.
    try std.testing.expectEqual(@as(u32, 0), out[40 * 100 + 9] >> 24);
    try std.testing.expect(out[9 * 100 + 9] >> 24 > 128);
}

test "tuning to nothing takes the lines and the mask away" {
    const l = tuned(.arcade, .{ .scanlines = 0, .mask = 0 });
    try std.testing.expectEqual(@as(f32, 1), l.gap);
    try std.testing.expectEqual(@as(f32, 1), l.mask_through);
    try std.testing.expectEqual(@as(f32, 0), l.beam_max);
    try std.testing.expectEqual(@as(f32, 1), l.gain);
    // And as it comes is the preset.
    try std.testing.expectEqual(look(.tv), tuned(.tv, .{}));
}
