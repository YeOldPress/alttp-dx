//! Particles: embers off every flame, sparks when the sword hits a wall,
//! leaves when a bush is cut, splashes in the water, and the rain.
//!
//! They're the port's own, kept apart from the game's RAM like the lighting
//! (lighting.zig), so the game plays the same with them on or off: each game
//! frame (`step`) they move, and new ones are made from what the game has
//! going on, the room's fires, a sword striking stone. They live in the
//! world's coordinates, so they stay put as the camera moves.
//!
//! With SDL's GPU renderer they're drawn over the lit frame as soft dots at
//! the screen's size (`drawGpu`), moving smoothly between the SNES's pixels;
//! anywhere else, a pixel each into the frame itself (`drawCpu`). Either
//! way, never over the HUD. Sparks and embers give off their own light and
//! are added on; everything else (leaves, water) is lit by the
//! room's light where it is, so it's dark in the dark and warm by a torch.

const std = @import("std");
const c = @import("sdl.zig").c;
const vars = @import("variables.zig");
const config = @import("config.zig");
const lighting = @import("lighting.zig");
const snes_types = @import("snes").ppu_types;

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
    /// Gives off its own light, added on (sparks, embers), rather than lit
    /// by the room's and laid over (everything else).
    glows: bool = true,
    /// How opaque, or for one that glows how bright, at its strongest.
    alpha: f32 = 1,
    /// A hard-edged fleck its own size (a leaf, a shard, a drop of water),
    /// rather than a soft dot that fades out (a spark's glow, smoke).
    crisp: bool = false,
    /// A raindrop's spot on the ground, in the world: it splashes there.
    land: f32 = std.math.inf(f32),
};

var g_parts: [kMaxParticles]Particle = undefined;
var g_n: usize = 0;
var g_rng = std.Random.DefaultPrng.init(0x5eed_f1a3);

/// What each ancilla slot held last frame, to tell a new one.
var g_prev_ancilla: [10]u8 = @splat(0);
/// What each garnish slot held last frame, to catch something breaking:
/// a bush, a pot, a rock turns into a garnish of its bits as it goes.
var g_prev_garnish: [30]u8 = @splat(0);
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

/// A bush's leaves at (x, y), in its colors, fluttering down slowly.
fn leaves(x: f32, y: f32, color: [3]f32) void {
    for (0..14) |_| {
        const a = range(0, std.math.tau);
        const v = range(0.3, 1.1);
        const shade = range(0.7, 1.15);
        const col = [3]f32{ color[0] * shade, color[1] * shade, color[2] * shade };
        add(.{
            .x = x + range(-4, 4),
            .y = y + range(-4, 2),
            .vx = @cos(a) * v,
            .vy = @sin(a) * v - range(0.6, 1.2),
            .drag = 0.9,
            .gravity = 0.035,
            .wobble = range(0.15, 0.35),
            .age = 0,
            .life = @intFromFloat(range(28, 48)),
            .size = range(1.1, 1.7),
            .hot = col,
            .cool = col,
            .seed = @truncate(g_rng.random().int(u16)),
            .glows = false,
            .crisp = true,
        });
    }
}

const kRain = [3]f32{ 0.76, 0.84, 0.96 };

/// The rain: drops coming in above the view, all the way across it and its
/// widescreen margins, falling at the slant the game's own rain falls at,
/// each to a spot of its own on the ground.
fn rain() void {
    const margin: f32 = @floatFromInt(snes_types.kPpuExtraLeftRight);
    const cam_x: f32 = @floatFromInt(vars.BG2HOFS_copy2.*);
    const cam_y: f32 = @floatFromInt(vars.BG2VOFS_copy2.*);
    for (0..kRainPerFrame) |_| {
        const vy = range(5.0, 6.5);
        add(.{
            .x = cam_x + range(-margin, 256 + margin + 60),
            .y = cam_y - range(8, 40),
            .vx = -vy * 0.3,
            .vy = vy,
            .drag = 1,
            .gravity = 0,
            .wobble = 0,
            .age = 0,
            .life = 120,
            .size = range(0.5, 0.7),
            .hot = kRain,
            .cool = kRain,
            .seed = 0,
            .glows = false,
            .alpha = range(0.42, 0.64),
            .crisp = true,
            .land = cam_y + range(8, 232),
        });
    }
}
const kRainPerFrame = 6;

/// A raindrop hitting the ground: a couple of tiny flecks hop up and drop.
fn splashlet(x: f32, y: f32) void {
    for (0..2) |_| {
        add(.{
            .x = x,
            .y = y,
            .vx = range(-0.5, 0.5),
            .vy = range(-0.9, -0.5),
            .drag = 0.95,
            .gravity = 0.16,
            .wobble = 0,
            .age = 0,
            .life = @intFromFloat(range(6, 10)),
            .size = 0.5,
            .hot = kRain,
            .cool = kRain,
            .seed = 0,
            .glows = false,
            .alpha = 0.55,
            .crisp = true,
        });
    }
}

/// Water thrown up at (x, y): `n` droplets that arc up and fall back.
fn splash(x: f32, y: f32, n: usize, power: f32) void {
    for (0..n) |_| {
        const a = range(-std.math.pi, 0);
        const v = range(0.4, 1.0) * power;
        add(.{
            .x = x + range(-5, 5),
            .y = y + range(-2, 2),
            .vx = @cos(a) * v * 0.8,
            .vy = @sin(a) * v - power * 0.6,
            .drag = 0.97,
            .gravity = 0.12,
            .wobble = 0,
            .age = 0,
            .life = @intFromFloat(range(14, 26)),
            .size = range(0.8, 1.3),
            .hot = kWater,
            .cool = kWater,
            .seed = 0,
            .glows = false,
            .alpha = 0.85,
            .crisp = true,
        });
    }
}

const kWater = [3]f32{ 0.78, 0.9, 1.0 };
const kLeaves = [3]f32{ 0.35, 0.65, 0.22 };

/// The color of a bush's leaves, from the game's kind for something
/// liftable, as it finds it in kLink_Lift_tab from the tile: 2 a bush, 4 an
/// off-color one. Null for anything else (signs, rocks, and indoors, where
/// its 2 is a pot), which breaks without any.
pub fn leafColor(kind: u8, indoors: bool, dark_world: bool) ?[3]f32 {
    if (indoors) return null;
    return switch (kind) {
        2 => if (dark_world) [3]f32{ 0.5, 0.58, 0.26 } else kLeaves,
        4 => .{ 0.62, 0.7, 0.28 },
        else => null,
    };
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
        if (p.y >= p.land) {
            const x = p.x;
            const y = p.land;
            g_n -= 1;
            g_parts[i] = g_parts[g_n];
            splashlet(x, y);
            continue;
        }
        i += 1;
    }
    emit();
    if (lighting.raining()) rain();
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
            // Cutting a bush: a few leaves on top of what breaks.
            0x3f => if (fresh) leaves(x + 8, y + 8, kLeaves),
            // Link jumping into deep water, something dropped in it.
            0x15 => if (fresh) splash(x + 8, y + 8, 14, 1.6),
            0x3d => if (fresh) splash(x + 8, y + 8, 8, 1.1),
            else => {},
        }
    }

    // Swimming throws up a little spray now and then; wading, a drip.
    if (vars.link_is_in_deep_water.* != 0 and rand() < 0.12) {
        splash(@floatFromInt(@as(i32, vars.link_x_coord.*) + 8), @floatFromInt(@as(i32, vars.link_y_coord.*) + 14), 2, 0.8);
    } else if (vars.tiledetect_shallow_water.* != 0 and (vars.link_x_vel.* | vars.link_y_vel.*) != 0 and rand() < 0.15) {
        splash(@floatFromInt(@as(i32, vars.link_x_coord.*) + 8), @floatFromInt(@as(i32, vars.link_y_coord.*) + 20), 1, 0.6);
    }

    // A bush breaking: the game swaps it for a garnish of its bits, which
    // says what it was, and leaves fly in its colors.
    for (0..30) |k| {
        const kind = vars.garnish_type[k];
        const fresh = kind != g_prev_garnish[k];
        g_prev_garnish[k] = kind;
        if (kind != 0x16 or !fresh) continue;
        const gx: i32 = @as(i32, vars.garnish_x_lo[k]) | @as(i32, vars.garnish_x_hi[k]) << 8;
        const gy: i32 = @as(i32, vars.garnish_y_lo[k]) | @as(i32, vars.garnish_y_hi[k]) << 8;
        const color = leafColor(vars.garnish_sprite[k], vars.player_is_indoors.* != 0, vars.savegame_is_darkworld.* != 0) orelse continue;
        leaves(@floatFromInt(gx + 8), @floatFromInt(gy - 8), color);
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
        .alpha = in * out * p.alpha,
    };
}

/// Where the frame is in the world: its left edge's margin past the 4:3
/// screen, and the camera; and the room's light, for what doesn't glow:
/// what the darkness takes off (0 to 1), what's left of the room's light
/// after, and the lights.
pub const View = struct {
    left: i32,
    cam_x: i32,
    cam_y: i32,
    width: usize,
    height: usize,
    dark: [3]f32 = .{ 0, 0, 0 },
    ambient: f32 = 1,
    lights: []const lighting.Light = &.{},
    /// A lightning flash, 0 to 1, which lights everything up with it.
    flash: f32 = 0,
};

/// The light on something that doesn't glow, at (x, y) on the frame: the
/// room's own, with the lights' added (their walls' shadows aside), each
/// channel at most a little past 1.
fn lightAt(v: View, x: f32, y: f32) [3]f32 {
    var l = [3]f32{
        (1 - v.dark[0]) * v.ambient,
        (1 - v.dark[1]) * v.ambient,
        (1 - v.dark[2]) * v.ambient,
    };
    for (v.lights) |li| {
        const dx = x - li.x;
        const dy = y - li.y;
        const t = @sqrt(dx * dx + dy * dy) / li.radius;
        if (t >= 1) continue;
        const k = 1 - t * t * (3 - 2 * t);
        for (&l, 0..) |*ch, i| ch.* += li.color[i] * k;
    }
    for (&l, [3]f32{ 0.85, 0.9, 1.0 }) |*ch, white| ch.* = @min(ch.* + white * v.flash, 1.15);
    return l;
}

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
var g_fleck: ?*c.SDL_Texture = null;
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
    // And the fleck: solid to its edge, with just the edge itself smoothed.
    var fk: [n * n]u32 = undefined;
    for (0..n) |y| for (0..n) |x| {
        const dx = (@as(f32, @floatFromInt(x)) + 0.5) / (n / 2) - 1;
        const dy = (@as(f32, @floatFromInt(y)) + 0.5) / (n / 2) - 1;
        const d = @sqrt(dx * dx + dy * dy);
        const a: u32 = @intFromFloat(std.math.clamp((1 - d) * (n / 2) / 1.5, 0, 1) * 255);
        fk[y * n + x] = a << 24 | 0xffffff;
    };
    if (c.SDL_CreateTexture(r, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STATIC, n, n)) |f| {
        _ = c.SDL_UpdateTexture(f, null, &fk, n * 4);
        _ = c.SDL_SetTextureScaleMode(f, c.SDL_SCALEMODE_LINEAR);
        g_fleck = f;
    }
    return t;
}

pub fn destroyGpu() void {
    if (g_dot) |t| c.SDL_DestroyTexture(t);
    if (g_fleck) |t| c.SDL_DestroyTexture(t);
    g_dot = null;
    g_fleck = null;
    g_dot_renderer = null;
}

/// Draws them onto the current target, which is the frame at `scale`
/// screen pixels to a SNES pixel.
pub fn drawGpu(r: *c.SDL_Renderer, v: View, mask: []const u32, scale: f32) void {
    if (g_n == 0) return;
    const dot = dotTexture(r) orelse return;
    // What doesn't glow (leaves, water, all hard flecks) goes down first,
    // laid over the frame; what does, added on top.
    if (g_fleck) |f| drawGpuPass(r, f, v, mask, scale, false, true);
    drawGpuPass(r, dot, v, mask, scale, true, false);
}

fn drawGpuPass(r: *c.SDL_Renderer, tex: *c.SDL_Texture, v: View, mask: []const u32, scale: f32, glows: bool, crisp: bool) void {
    var verts: [kMaxParticles * 4]c.SDL_Vertex = undefined;
    var idx: [kMaxParticles * 6]c_int = undefined;
    var nq: usize = 0;
    for (g_parts[0..g_n]) |*p| {
        if (p.glows != glows or p.crisp != crisp) continue;
        const sx = p.x - @as(f32, @floatFromInt(v.cam_x - v.left));
        const sy = p.y - @as(f32, @floatFromInt(v.cam_y));
        if (!inScene(mask, v, sx, sy)) continue;
        var l = look(p);
        if (!p.glows) {
            const lit = lightAt(v, sx, sy);
            for (&l.color, 0..) |*ch, i| ch.* *= lit[i];
        }
        // The dot fades out well inside its square, so it's drawn a good
        // deal bigger than the spark it stands for. Something moving fast
        // is stretched along the way it's going, a streak rather than a dot.
        // A fleck is drawn its own size, a pixel of the screen at least, and
        // stretched less.
        const half = if (crisp) @max(p.size * 0.5 * scale, 1) else p.size * 1.6 * scale;
        const speed = @sqrt(p.vx * p.vx + p.vy * p.vy);
        const along = [2]f32{ if (speed > 0.01) p.vx / speed else 1, if (speed > 0.01) p.vy / speed else 0 };
        const across = [2]f32{ -along[1], along[0] };
        const long = half + @max(speed - 0.3, 0) * (if (crisp) @as(f32, 0.8) else 2.5) * scale;
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
    _ = c.SDL_SetTextureBlendMode(tex, if (glows) c.SDL_BLENDMODE_ADD else c.SDL_BLENDMODE_BLEND);
    _ = c.SDL_RenderGeometry(r, tex, &verts, @intCast(nq * 4), &idx, @intCast(nq * 6));
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
        var l = look(p);
        if (!p.glows) {
            const lit = lightAt(v, sx, sy);
            for (&l.color, 0..) |*ch, i| ch.* *= lit[i];
        }
        const px: *align(1) u32 = @ptrCast(pixels + y * pitch + x * 4);
        const old = px.*;
        var out: u32 = 0;
        for (0..3) |ch| {
            const shift: u5 = @intCast(16 - ch * 8);
            const was: f32 = @floatFromInt((old >> shift) & 0xff);
            const col = @min(l.color[ch], 1) * 255;
            const now = if (p.glows) was + col * l.alpha else was + (col - was) * l.alpha;
            out |= @as(u32, @intFromFloat(std.math.clamp(now, 0, 255))) << shift;
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

test "what doesn't glow is lit by the room: dark in the dark, warm by a light" {
    const dark = View{ .left = 0, .cam_x = 0, .cam_y = 0, .width = 100, .height = 100, .dark = .{ 1, 1, 1 } };
    try testing.expectEqual([3]f32{ 0, 0, 0 }, lightAt(dark, 50, 50));
    var lights = [_]lighting.Light{.{ .x = 50, .y = 50, .radius = 20, .color = .{ 1, 0.5, 0.25 } }};
    var lit = dark;
    lit.lights = &lights;
    const l = lightAt(lit, 50, 50);
    try testing.expect(l[0] > l[1] and l[1] > l[2] and l[0] > 0.9);
    try testing.expectEqual([3]f32{ 0, 0, 0 }, lightAt(lit, 90, 90));
}

test "splashes arc up and fall back; leaves flutter down slower than drops" {
    clear();
    splash(0, 0, 6, 1.6);
    for (g_parts[0..g_n]) |p| {
        try testing.expect(p.vy < 0 and p.gravity > 0 and !p.glows);
    }
    const drop = g_parts[0];
    clear();
    leaves(0, 0, kLeaves);
    const leaf = g_parts[0];
    try testing.expect(leaf.gravity < drop.gravity and leaf.wobble > drop.wobble);
    clear();
}

test "only bushes break into leaves" {
    const lw = leafColor(2, false, false).?;
    try testing.expect(lw[1] > lw[0] and lw[1] > lw[2]);
    try testing.expect(leafColor(4, false, true) != null);
    try testing.expectEqual(@as(?[3]f32, null), leafColor(2, true, false)); // a pot, indoors
    try testing.expectEqual(@as(?[3]f32, null), leafColor(1, false, false)); // a rock
    try testing.expectEqual(@as(?[3]f32, null), leafColor(0, false, false)); // a sign
}
