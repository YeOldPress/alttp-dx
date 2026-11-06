//! Particles: embers off every flame, sparks when the sword hits a wall.
//!
//! They're the port's own, kept apart from the game's RAM like the lighting
//! (lighting.zig), so the game plays the same with them on or off: each game
//! frame (`step`) they move, and new ones are made from what the game has
//! going on, the room's fires, a sword striking stone. They live in the
//! world's coordinates, so they stay put as the camera moves.
//!
//! With SDL's GPU renderer they're drawn over the lit frame as soft glowing
//! dots at the screen's size (`drawGpu`), moving smoothly between the SNES's
//! pixels; anywhere else, a pixel each into the frame itself (`drawCpu`).
//! Either way, never over the HUD.

const std = @import("std");
const c = @import("sdl.zig").c;
const vars = @import("variables.zig");
const config = @import("config.zig");
const lighting = @import("lighting.zig");

pub const kMaxParticles = 512;

const Particle = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    /// Speed kept each frame, and how much is added to vy (down).
    drag: f32,
    gravity: f32,
    /// How far it sways side to side as it goes.
    wobble: f32,
    age: u16,
    life: u16,
    /// Across, in SNES pixels.
    size: f32,
    /// Its color new, and as it dies.
    hot: [3]f32,
    cool: [3]f32,
    seed: u16,
};

var g_parts: [kMaxParticles]Particle = undefined;
var g_n: usize = 0;
var g_rng = std.Random.DefaultPrng.init(0x5eed_f1a3);

/// What each ancilla slot held last frame, to tell a new one.
var g_prev_ancilla: [10]u8 = @splat(0);
/// Where the world was last frame, to clear everything when it changes
/// under the particles: in or out of doors, Light World or Dark.
const World = struct { indoors: u8, dark_world: u8 };
var g_prev_world: ?World = null;

pub fn enabled() bool {
    return config.g_config.particles;
}

/// How many are alive.
pub fn count() usize {
    return g_n;
}

pub fn clear() void {
    g_n = 0;
}

fn rand() f32 {
    return g_rng.random().float(f32);
}

fn range(lo: f32, hi: f32) f32 {
    return lo + (hi - lo) * rand();
}

fn add(p: Particle) void {
    if (g_n == kMaxParticles) return;
    g_parts[g_n] = p;
    g_n += 1;
}

const kEmberHot = [3]f32{ 1.0, 0.85, 0.5 };
const kEmberCool = [3]f32{ 0.9, 0.25, 0.05 };
const kSparkHot = [3]f32{ 1.0, 0.97, 0.8 };
const kSparkCool = [3]f32{ 1.0, 0.5, 0.15 };

/// An ember rising off a flame at (x, y), drifting and fading as it cools.
fn ember(x: f32, y: f32, spread: f32) void {
    add(.{
        .x = x + range(-spread, spread),
        .y = y + range(-2, 1),
        .vx = range(-0.12, 0.12),
        .vy = range(-0.55, -0.25),
        .drag = 0.985,
        .gravity = -0.004,
        .wobble = range(0.03, 0.08),
        .age = 0,
        .life = @intFromFloat(range(35, 75)),
        .size = range(0.8, 1.3),
        .hot = kEmberHot,
        .cool = kEmberCool,
        .seed = @truncate(g_rng.random().int(u16)),
    });
}

/// A burst of `n` sparks flying out from (x, y), falling as they go.
fn sparks(x: f32, y: f32, n: usize, speed: f32) void {
    for (0..n) |_| {
        const a = range(0, std.math.tau);
        const v = range(0.4, 1.0) * speed;
        add(.{
            .x = x,
            .y = y,
            .vx = @cos(a) * v,
            .vy = @sin(a) * v - 0.4,
            .drag = 0.93,
            .gravity = 0.07,
            .wobble = 0,
            .age = 0,
            .life = @intFromFloat(range(12, 26)),
            .size = range(0.7, 1.0),
            .hot = kSparkHot,
            .cool = kSparkCool,
            .seed = 0,
        });
    }
}

/// One game frame: everything moves, the old die, new ones are made.
pub fn step() void {
    if (!enabled()) {
        g_n = 0;
        return;
    }
    const world = World{ .indoors = vars.player_is_indoors.*, .dark_world = vars.savegame_is_darkworld.* };
    if (g_prev_world) |w| {
        if (w.indoors != world.indoors or w.dark_world != world.dark_world) g_n = 0;
    }
    g_prev_world = world;
    // The game stands still under a menu or a text box, and so do they.
    if (vars.main_module_index.* == 14) return;

    var i: usize = 0;
    while (i < g_n) {
        const p = &g_parts[i];
        p.age += 1;
        if (p.age >= p.life) {
            g_n -= 1;
            g_parts[i] = g_parts[g_n];
            continue;
        }
        p.vx *= p.drag;
        p.vy = p.vy * p.drag + p.gravity;
        p.x += p.vx + p.wobble * @sin(@as(f32, @floatFromInt(p.age)) * 0.15 + @as(f32, @floatFromInt(p.seed)));
        p.y += p.vy;
        i += 1;
    }
    emit();
}

fn emit() void {
    // Embers off the room's fires.
    var spots: [48]lighting.Spot = undefined;
    for (spots[0..lighting.flameSpots(&spots)]) |s| {
        const rate: f32 = switch (s.kind) {
            .torch, .brazier => 0.1,
            .candle => 0.04,
        };
        if (rand() < rate) ember(@floatFromInt(s.x), @floatFromInt(s.y - 4), 3);
    }

    for (0..10) |k| {
        const kind = vars.ancilla_type[k];
        const fresh = kind != g_prev_ancilla[k];
        g_prev_ancilla[k] = kind;
        const x: f32 = @floatFromInt(@as(i32, vars.ancilla_x_lo[k]) | @as(i32, vars.ancilla_x_hi[k]) << 8);
        const y: f32 = @floatFromInt(@as(i32, vars.ancilla_y_lo[k]) | @as(i32, vars.ancilla_y_hi[k]) << 8);
        switch (kind) {
            // Fire rod shots, the fires they start, the lamp's flame:
            // embers come off them thick.
            0x02, 0x2f, 0x34 => if (rand() < 0.35) ember(x + 8, y + 6, 4),
            // The sword striking a wall, or something else that bounces off
            // one.
            0x1b => if (fresh) sparks(x + 4, y + 4, 12, 2.2),
            0x06 => if (fresh) sparks(x + 4, y + 4, 6, 1.6),
            else => {},
        }
    }

    // Fireballs and the like shed embers as they fly.
    for (0..16) |k| {
        if (vars.sprite_state[k] == 0) continue;
        const rate: f32 = switch (vars.sprite_type[k]) {
            0x55 => if (vars.sprite_E[k] != 0) 0.2 else 0,
            0x70, 0x87, 0x80 => 0.2,
            else => 0,
        };
        if (rate == 0 or rand() >= rate) continue;
        const x: i32 = @as(i32, vars.sprite_x_lo[k]) | @as(i32, vars.sprite_x_hi[k]) << 8;
        const y: i32 = (@as(i32, vars.sprite_y_lo[k]) | @as(i32, vars.sprite_y_hi[k]) << 8) - vars.sprite_z[k];
        ember(@floatFromInt(x + 8), @floatFromInt(y + 8), 3);
    }
}

/// How a particle looks at its age: its color, and how bright (0 to 1),
/// coming in over its first frames and fading over the last part of its
/// life.
fn look(p: *const Particle) struct { color: [3]f32, alpha: f32 } {
    const t = @as(f32, @floatFromInt(p.age)) / @as(f32, @floatFromInt(p.life));
    const in = @min(@as(f32, @floatFromInt(p.age)) / 3.0, 1.0);
    const out = @min((1.0 - t) / 0.4, 1.0);
    return .{
        .color = .{
            p.hot[0] + (p.cool[0] - p.hot[0]) * t,
            p.hot[1] + (p.cool[1] - p.hot[1]) * t,
            p.hot[2] + (p.cool[2] - p.hot[2]) * t,
        },
        .alpha = in * out,
    };
}

/// Where the frame is in the world: its left edge's margin past the 4:3
/// screen, and the camera.
pub const View = struct { left: i32, cam_x: i32, cam_y: i32, width: usize, height: usize };

/// Whether the mask (one u32 a pixel, its value in the red byte, `width` to
/// a row, as lighting hands the GPU) says (x, y) is the scene, not the HUD.
fn inScene(mask: []const u32, v: View, x: f32, y: f32) bool {
    if (x < 0 or y < 0) return false;
    const ix: usize = @intFromFloat(x);
    const iy: usize = @intFromFloat(y);
    if (ix >= v.width or iy >= v.height) return false;
    return (mask[iy * v.width + ix] >> 16) & 0xff != 0;
}

// ------------------------------------------------------------- on the GPU

var g_dot: ?*c.SDL_Texture = null;
var g_dot_renderer: ?*c.SDL_Renderer = null;

/// A soft round dot, white, bright in the middle and fading to nothing at
/// its edge.
fn dotTexture(r: *c.SDL_Renderer) ?*c.SDL_Texture {
    if (g_dot != null and g_dot_renderer == r) return g_dot;
    destroyGpu();
    const n = 32;
    var px: [n * n]u32 = undefined;
    for (0..n) |y| for (0..n) |x| {
        const dx = (@as(f32, @floatFromInt(x)) + 0.5) / (n / 2) - 1;
        const dy = (@as(f32, @floatFromInt(y)) + 0.5) / (n / 2) - 1;
        const d2 = @min(dx * dx + dy * dy, 1.0);
        const a: u32 = @intFromFloat((1 - d2) * (1 - d2) * 255);
        px[y * n + x] = a << 24 | 0xffffff;
    };
    const t = c.SDL_CreateTexture(r, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STATIC, n, n) orelse return null;
    _ = c.SDL_UpdateTexture(t, null, &px, n * 4);
    _ = c.SDL_SetTextureBlendMode(t, c.SDL_BLENDMODE_ADD);
    _ = c.SDL_SetTextureScaleMode(t, c.SDL_SCALEMODE_LINEAR);
    g_dot = t;
    g_dot_renderer = r;
    return t;
}

pub fn destroyGpu() void {
    if (g_dot) |t| c.SDL_DestroyTexture(t);
    g_dot = null;
    g_dot_renderer = null;
}

/// Draws them onto the current target, which is the frame at `scale`
/// screen pixels to a SNES pixel.
pub fn drawGpu(r: *c.SDL_Renderer, v: View, mask: []const u32, scale: f32) void {
    if (g_n == 0) return;
    const dot = dotTexture(r) orelse return;
    var verts: [kMaxParticles * 4]c.SDL_Vertex = undefined;
    var idx: [kMaxParticles * 6]c_int = undefined;
    var nq: usize = 0;
    for (g_parts[0..g_n]) |*p| {
        const sx = p.x - @as(f32, @floatFromInt(v.cam_x - v.left));
        const sy = p.y - @as(f32, @floatFromInt(v.cam_y));
        if (!inScene(mask, v, sx, sy)) continue;
        const l = look(p);
        // The dot fades out well inside its square, so it's drawn a good
        // deal bigger than the spark it stands for. Something moving fast
        // is stretched along the way it's going, a streak rather than a dot.
        const half = p.size * 1.6 * scale;
        const speed = @sqrt(p.vx * p.vx + p.vy * p.vy);
        const along = [2]f32{ if (speed > 0.01) p.vx / speed else 1, if (speed > 0.01) p.vy / speed else 0 };
        const across = [2]f32{ -along[1], along[0] };
        const long = half + @max(speed - 0.3, 0) * 2.5 * scale;
        const cx = sx * scale;
        const cy = sy * scale;
        const col = c.SDL_FColor{ .r = l.color[0], .g = l.color[1], .b = l.color[2], .a = l.alpha };
        const corners = [4][4]f32{ .{ -1, -1, 0, 0 }, .{ 1, -1, 1, 0 }, .{ 1, 1, 1, 1 }, .{ -1, 1, 0, 1 } };
        for (corners, 0..) |k, j| verts[nq * 4 + j] = .{
            .position = .{
                .x = cx + k[0] * long * along[0] + k[1] * half * across[0],
                .y = cy + k[0] * long * along[1] + k[1] * half * across[1],
            },
            .color = col,
            .tex_coord = .{ .x = k[2], .y = k[3] },
        };
        const b: c_int = @intCast(nq * 4);
        idx[nq * 6 ..][0..6].* = .{ b, b + 1, b + 2, b, b + 2, b + 3 };
        nq += 1;
    }
    if (nq == 0) return;
    _ = c.SDL_RenderGeometry(r, dot, &verts, @intCast(nq * 4), &idx, @intCast(nq * 6));
}

// ------------------------------------------------------------- on the CPU

/// Draws them into the frame itself (XRGB, `pitch` bytes a row), a pixel
/// each, added on. `mask` as lighting's own: a byte a pixel, `pitch_mask`
/// to a row, 0 for the HUD.
pub fn drawCpu(pixels: [*]u8, pitch: usize, v: View, mask: [*]const u8, pitch_mask: usize) void {
    for (g_parts[0..g_n]) |*p| {
        const sx = p.x - @as(f32, @floatFromInt(v.cam_x - v.left));
        const sy = p.y - @as(f32, @floatFromInt(v.cam_y));
        if (sx < 0 or sy < 0) continue;
        const x: usize = @intFromFloat(sx);
        const y: usize = @intFromFloat(sy);
        if (x >= v.width or y >= v.height or mask[y * pitch_mask + x] == 0) continue;
        const l = look(p);
        const px: *align(1) u32 = @ptrCast(pixels + y * pitch + x * 4);
        const old = px.*;
        var out: u32 = 0;
        for (0..3) |ch| {
            const shift: u5 = @intCast(16 - ch * 8);
            const was = (old >> shift) & 0xff;
            const plus: u32 = @intFromFloat(l.color[ch] * l.alpha * 255);
            out |= @as(u32, @min(was + plus, 255)) << shift;
        }
        px.* = out;
    }
}

const testing = std.testing;

test "embers rise and fade out; sparks fall" {
    clear();
    ember(100, 100, 0);
    sparks(50, 50, 1, 2);
    const e = g_parts[0];
    var p = e;
    for (0..20) |_| {
        p.age += 1;
        p.vy = p.vy * p.drag + p.gravity;
        p.y += p.vy;
    }
    try testing.expect(p.y < e.y);
    var s = g_parts[1];
    for (0..30) |_| {
        s.vy = s.vy * s.drag + s.gravity;
        s.y += s.vy;
    }
    try testing.expect(s.vy > 0);
    // Faded in by its third frame, gone by its last.
    p.age = 3;
    try testing.expect(look(&p).alpha > 0.99);
    p.age = p.life;
    try testing.expect(look(&p).alpha < 0.01);
    clear();
}

test "nothing's made past the limit" {
    clear();
    for (0..kMaxParticles + 10) |_| ember(0, 0, 0);
    try testing.expectEqual(@as(usize, kMaxParticles), count());
    clear();
}
