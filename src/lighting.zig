//! Dynamic lighting for dark dungeon rooms.
//!
//! The SNES darkens a dark room with subtractive color math: it takes a
//! fixed color away from the room's layers (all of it with no torches lit,
//! less with each one), and, with the lantern, a picture of a cone of light
//! on the subscreen, scrolled onto Link. Here the PPU skips that math and
//! draws the room at full brightness, marking the pixels it would have
//! darkened (ppu.g_light_mask), and this pass relights just those: first
//! the same darkness the game asked for, taken off the same way, so where no
//! light reaches the room looks just as it always did, then soft round light
//! added back from the lantern, the room's lit torches and anything burning.
//!
//! Rooms that aren't dark get it too, gentler: the room's dimmed a little,
//! by scaling its colors rather than taking a fixed amount off them, so the
//! braziers, torches and anything burning have something to light.
//!
//! None of it touches the game's RAM, so the game plays the same with it on
//! or off; it only changes what's drawn. The HUD and the sprites the game
//! leaves lit in the dark (Link among them) stay as the game draws them.
//!
//! In the window, with SDL's GPU renderer, the light is laid on by shaders
//! instead (light_gpu.zig), at the screen's size, with the flames' glow; the
//! frame is handed over unlit with the mask in its spare byte. Anywhere else
//! (the software renderer, screenshots) it's done here, a pixel at a time.

const std = @import("std");
const vars = @import("variables.zig");
const ancilla = @import("ancilla.zig");
const config = @import("config.zig");
const snes_pkg = @import("snes");
const Ppu = snes_pkg.ppu_types.Ppu;
const ppu_mod = snes_pkg.ppu;
const particles = @import("particles.zig");

const kMaxWidth = 256 + 2 * snes_pkg.ppu_types.kPpuExtraLeftRight;
const kMaxHeight = 240;

var g_mask: [kMaxHeight * kMaxWidth]u8 = undefined;

/// The light added to each pixel, per channel, 256 being all of the pixel
/// as drawn.
var g_light: [kMaxHeight * kMaxWidth][3]u16 = undefined;

/// Whether this frame is being relit: set by `beginFrame`, for `endFrame`.
var g_active = false;

/// Frames relit so far, to time the flames by. Not the game's frame
/// counter, which comes round every 256 frames, so the flames would too.
var g_tick: u32 = 0;

/// A light: where on the frame, how far it reaches, how bright and what
/// color at its middle (1.0 is the pixel as drawn; past that, the light's
/// full strength reaches further out before it starts to fade). A flame
/// also glows, a halo `glow_radius` across, `glow` bright; the GPU draws
/// that.
pub const Light = struct {
    x: f32,
    y: f32,
    radius: f32,
    color: [3]f32,
    glow_radius: f32 = 0,
    glow: f32 = 0,
};

/// What a pixel of the mask says: 1, the room's darkness covers it; 2, it's
/// part of the scene the darkness leaves be (Link, some sprites), which a
/// flame's glow still falls on; 0, neither (the HUD, menus over the game).
pub const kMaskDark = 1;
pub const kMaskScene = 2;

/// Set while the window's frame is being drawn and the GPU's there to light
/// it: the frame is left unlit, for `takeGpuFrame`.
pub var g_gpu = false;

/// A frame left for the GPU to light.
pub const GpuFrame = struct {
    width: usize,
    height: usize,
    dark: [3]u8,
    /// What's left of the room's light after `dark`'s taken off, as a share
    /// of it: 1 in a dark room, less in one that isn't.
    ambient: f32,
    lights: [kMaxGpuLights]Light,
    n: usize,
    /// Where the room's scrolled to, and how far the frame reaches past the
    /// 4:3 screen's left edge, to find each pixel's tile in the room.
    cam_x: i32,
    cam_y: i32,
    left: i32,
    /// A pixel a u32, `width` to a row: the mask's value in red, solid
    /// ground in green, as light_map.frag reads them.
    mask: []const u32,
};
pub const kMaxGpuLights = 48;

var g_gpu_frame: GpuFrame = undefined;
var g_gpu_pending = false;
var g_gpu_mask: [kMaxHeight * kMaxWidth]u32 = undefined;

const kLantern = [3]f32{ 1.0, 0.93, 0.78 };
const kFlame = [3]f32{ 1.0, 0.78, 0.5 };
const kSparkColor = [3]f32{ 0.75, 0.85, 1.0 };

/// How a room's lit: a dark room, with the game's own darkness relit; any
/// other room indoors, dimmed a little for its flames to light; or not at
/// all (outdoors, or dynamic lighting off). `plain` is not at all, but with
/// particles to draw, which want the HUD told apart from the scene.
pub const Mode = enum { off, dark, mood, plain };

/// How much of its light a room that isn't dark keeps, for the flames to
/// make up.
pub const kMoodAmbient: f32 = 0.82;

fn roomMode() Mode {
    const plain: Mode = if (particles.enabled() and particles.count() != 0) .plain else .off;
    if (!config.g_config.dynamic_lighting) return plain;
    if (vars.player_is_indoors.* == 0) return plain;
    // The game's own darkness rules, as the widescreen margins read them in
    // zelda_rtl.zig.
    if (vars.hdr_dungeon_dark_with_lantern.* != 0 or vars.dung_want_lights_out.* != 0) return .dark;
    return .mood;
}

var g_mode: Mode = .off;

/// Before the PPU draws a frame: in a dark room, hands it the mask to mark.
/// Needs the whole-line renderer, the only one that knows about the mask.
pub fn beginFrame(render_flags: u32, height: usize) void {
    g_mode = if (render_flags & snes_pkg.ppu_types.kPpuRenderFlags_NewRenderer != 0) roomMode() else .off;
    g_active = g_mode != .off;
    if (!g_active) {
        ppu_mod.g_light_mask = null;
        return;
    }
    @memset(g_mask[0 .. height * kMaxWidth], 0);
    ppu_mod.g_light_mask = .{ .mask = &g_mask, .pitch = kMaxWidth, .dark = g_mode == .dark };
}

/// After the PPU's drawn the frame into `pixels` (XRGB, `pitch` bytes a
/// row): lays the light over the pixels it marked.
pub fn endFrame(ppu: *const Ppu, pixels: [*]u8, pitch: usize, height: usize) void {
    ppu_mod.g_light_mask = null;
    if (!g_active) return;
    g_active = false;
    const width: usize = 256 + 2 * @as(usize, ppu.extraLeftRight);

    g_tick +%= 1;
    var lights: [64]Light = undefined;
    const n = if (g_mode == .plain) 0 else gatherLights(ppu, &lights);
    const dark: [3]u8 = if (g_mode == .dark) darkness(ppu) else .{ 0, 0, 0 };
    const amb: f32 = switch (g_mode) {
        .mood => kMoodAmbient,
        else => 1,
    };
    if (!g_gpu) {
        if (g_mode != .plain) relight(pixels, pitch, width, height, dark, amb, lights[0..n]);
        particles.drawCpu(pixels, pitch, .{
            .left = ppu.extraLeftRight,
            .cam_x = vars.BG2HOFS_copy2.*,
            .cam_y = vars.BG2VOFS_copy2.*,
            .width = width,
            .height = height,
            .dark = .{ @as(f32, @floatFromInt(dark[0])) / 255, @as(f32, @floatFromInt(dark[1])) / 255, @as(f32, @floatFromInt(dark[2])) / 255 },
            .ambient = amb,
            .lights = lights[0..n],
        }, &g_mask, kMaxWidth);
        return;
    }
    // For the GPU: the mask goes in each pixel's spare top byte, so that
    // whatever's drawn over the frame before it's shown (menus, popups)
    // leaves it zero there and isn't lit.
    for (0..height) |y| {
        const mask = g_mask[y * kMaxWidth ..][0..width];
        const row: [*]align(1) u32 = @ptrCast(pixels + y * pitch);
        for (mask, 0..) |m, x| row[x] = (row[x] & 0xffffff) | @as(u32, m) << 24;
    }
    const k = @min(n, kMaxGpuLights);
    g_gpu_frame = .{
        .width = width,
        .height = height,
        .dark = dark,
        .ambient = amb,
        .lights = undefined,
        .n = k,
        .cam_x = vars.BG2HOFS_copy2.*,
        .cam_y = vars.BG2VOFS_copy2.*,
        .left = ppu.extraLeftRight,
        .mask = &.{},
    };
    @memcpy(g_gpu_frame.lights[0..k], lights[0..k]);
    g_gpu_pending = true;
}

/// How much a room tile with this attribute stops light, 0 to 255: walls
/// and anything else Link can't walk through, as the game's tile detection
/// sorts them indoors, and diagonal walls about half.
pub fn solidness(attr: u8) u8 {
    return switch (attr) {
        0x01, 0x02, 0x03, 0x04, 0x0b, 0x26, 0x27, 0x43, 0x6c...0x6f => 255,
        0x10...0x13, 0x18...0x1b => 128,
        else => 0,
    };
}

/// Lights a frame left for the GPU on the CPU after all, when the GPU
/// turns out not to be able to: the mask's still as the PPU left it.
pub fn relightFrame(pixels: [*]u8, pitch: usize, f: *const GpuFrame) void {
    relight(pixels, pitch, f.width, f.height, f.dark, f.ambient, f.lights[0..f.n]);
}

/// Once everything's drawn over the window's frame: takes the mask back out
/// of its spare bytes for the GPU, and the frame is the GPU's to light.
/// Null if there's nothing to light this frame.
pub fn takeGpuFrame(pixels: [*]u8, pitch: usize) ?*const GpuFrame {
    if (!g_gpu_pending) return null;
    g_gpu_pending = false;
    const f = &g_gpu_frame;
    for (0..f.height) |y| {
        const row: [*]align(1) u32 = @ptrCast(pixels + y * pitch);
        const out = g_gpu_mask[y * f.width ..][0..f.width];
        const ty: usize = @intCast(@mod(@as(i32, @intCast(y)) + f.cam_y, 512) >> 3);
        const attrs = vars.dung_bg2_attr_table[ty * 64 ..][0..64];
        for (out, 0..) |*o, x| {
            const m = row[x] >> 24;
            row[x] &= 0xffffff;
            const tx: usize = @intCast(@mod(@as(i32, @intCast(x)) - f.left + f.cam_x, 512) >> 3);
            o.* = 0xff000000 | m << 16 | @as(u32, solidness(attrs[tx])) << 8;
        }
    }
    f.mask = g_gpu_mask[0 .. f.width * f.height];
    return f;
}

/// How much the game takes off each channel of the room to darken it, on
/// the frame's 0-255 scale: its fixed color, all 31 of it with no torches
/// lit (black), less with each one, eased from one to the next as torches
/// catch or go out. The PPU takes it off the 5-bit color before the
/// screen's brightness scales it, so it's scaled the same way here.
pub fn darkness(ppu: *const Ppu) [3]u8 {
    return .{
        ppu.brightnessMult[@min(ppu.fixedColorR, 31)],
        ppu.brightnessMult[@min(ppu.fixedColorG, 31)],
        ppu.brightnessMult[@min(ppu.fixedColorB, 31)],
    };
}

/// How a kind of flame moves.
pub const Burn = struct {
    /// How far its light wavers either way all the time, as a fraction of it.
    waver: f32,
    /// How quickly: the noise's steps per frame. The flutter on top runs a
    /// few times quicker than the swell underneath.
    speed: f32,
    /// How much of its light a gutter takes, when the flame sinks for a
    /// moment and gathers itself again, and how much of the time it's doing
    /// that (roughly; 0 never).
    gutter: f32,
    gutter_odds: f32,
    /// How far its light sways about its place, in pixels.
    sway: f32,
};

/// Behind glass, out of the draft: steady, with now and then a dip.
pub const kLanternBurn = Burn{ .waver = 0.05, .speed = 0.09, .gutter = 0.12, .gutter_odds = 0.12, .sway = 0.4 };
/// An open flame on a stand: wavers, and gutters every few seconds.
pub const kTorchBurn = Burn{ .waver = 0.12, .speed = 0.16, .gutter = 0.3, .gutter_odds = 0.22, .sway = 1.0 };
/// Fire on the ground or in flight: quick and restless.
pub const kFireBurn = Burn{ .waver = 0.18, .speed = 0.3, .gutter = 0.25, .gutter_odds = 0.4, .sway = 1.5 };
/// Sparks: crackle, never still.
pub const kSparkBurn = Burn{ .waver = 0.35, .speed = 0.9, .gutter = 0.5, .gutter_odds = 0.5, .sway = 0.5 };

/// A flame at one moment.
pub const Flame = struct {
    /// How bright, around 1, and how far its light reaches, around 1.
    level: f32,
    reach: f32,
    /// How far its light has swayed, in pixels.
    dx: f32,
    dy: f32,
};

/// A flame of the kind `b` at frame `tick`. `seed` sets one flame apart
/// from the next, so no two in a room keep time.
pub fn flame(tick: u32, seed: u32, b: Burn) Flame {
    const t: f32 = @floatFromInt(tick % (1 << 20));
    const s = seed *% 0x632be5ab;
    const w = 0.5 * noise(t * b.speed, s) +
        0.3 * noise(t * b.speed * 2.3, s +% 1) +
        0.2 * noise(t * b.speed * 5.1, s +% 2);
    const odds = 1.0 - b.gutter_odds;
    const gut = smoothstep(odds, odds + 0.12, noise(t * b.speed * 0.15, s +% 3) * 0.5 + 0.5);
    return .{
        .level = 1.0 + b.waver * w - b.gutter * gut,
        .reach = 1.0 + 0.4 * b.waver * w - 0.5 * b.gutter * gut,
        .dx = b.sway * noise(t * b.speed * 0.7, s +% 4),
        // A guttering flame shrinks down toward its wick.
        .dy = 0.6 * b.sway * noise(t * b.speed * 0.7, s +% 5) + 1.5 * b.sway * gut,
    };
}

/// A flame's light at `level`: the base color scaled, and redder as it
/// dims, the way a flame is when it sinks.
pub fn flameColor(c: [3]f32, strength: f32, level: f32) [3]f32 {
    const dim = @max(0.0, 1.0 - level);
    return .{
        c[0] * strength * level,
        c[1] * strength * level * (1.0 - 0.6 * dim),
        c[2] * strength * level * (1.0 - 1.2 * dim),
    };
}

/// A random number between -1 and 1 for each whole `i`, the same every time.
fn hash(i: u32, seed: u32) f32 {
    var h: u32 = (i *% 0x9e3779b1) ^ (seed *% 0x85ebca77);
    h ^= h >> 15;
    h *%= 0x2c1b3c6d;
    h ^= h >> 12;
    h *%= 0x297a2d39;
    h ^= h >> 15;
    return @as(f32, @floatFromInt(h >> 8)) / 8388607.5 - 1.0;
}

/// Noise between -1 and 1 that wanders smoothly with `x` (0 and up) and
/// never repeats: random values at the whole numbers, eased between.
pub fn noise(x: f32, seed: u32) f32 {
    const fl = @floor(x);
    const i: u32 = @intFromFloat(fl);
    const f = x - fl;
    const u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    const a = hash(i, seed);
    return a + (hash(i +% 1, seed) - a) * u;
}

fn smoothstep(e0: f32, e1: f32, x: f32) f32 {
    const t = std.math.clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

/// Where on the frame a point in the room's 512 pixel tilemap is, given
/// the scroll: the map wraps, so it's the nearest copy to the screen.
pub fn wrapToScreen(pos: i32, scroll: i32) i32 {
    const d = @mod(pos - scroll, 512);
    // The frame reaches 256 past the scroll and the margins as far again
    // before it, so anything further along is the copy before.
    return if (d >= 512 - 160) d - 512 else d;
}

fn gatherLights(ppu: *const Ppu, out: []Light) usize {
    var n: usize = 0;
    const left: f32 = @floatFromInt(ppu.extraLeftRight);
    const cam_x: i32 = vars.BG2HOFS_copy2.*;
    const cam_y: i32 = vars.BG2VOFS_copy2.*;
    const tick = g_tick;

    // The lantern, carried a little out in front of Link as the game's cone
    // is.
    if (g_mode == .dark and vars.link_item_torch.* != 0) {
        const dir = vars.link_direction_facing.* >> 1;
        const ahead = [4][2]f32{ .{ 0, -14 }, .{ 0, 14 }, .{ -14, 0 }, .{ 14, 0 } };
        const lx: f32 = @floatFromInt(@as(i32, vars.link_x_coord.*) - cam_x + 8);
        const ly: f32 = @floatFromInt(@as(i32, vars.link_y_coord.*) - cam_y + 12);
        const f = flame(tick, 0, kLanternBurn);
        out[n] = .{
            .x = left + lx + ahead[dir & 3][0] + f.dx,
            .y = ly + ahead[dir & 3][1] + f.dy,
            .radius = 84.0 * f.reach,
            .color = flameColor(kLantern, 1.45, f.level),
        };
        n += 1;
    }

    // The room's lit torches, found by their tiles in the room's map: the
    // ones Link lights and the ones that are always lit are drawn alike.
    // Layer 1 holds the lantern's cone, not the room, while it's up.
    var torches: [24]u16 = undefined;
    var nt = findLitTorches(vars.dung_bg2, &torches);
    const bg1_is_room = vars.hdr_dungeon_dark_with_lantern.* == 0;
    if (bg1_is_room) nt += findLitTorches(vars.dung_bg1, torches[nt..]);
    // Braziers on stands (the Sanctuary's, the potion shop's): their flame
    // is in the top half of their tiles.
    const torch_count = nt;
    nt += findTiles2x2(vars.dung_bg2, kBrazierTiles, kIgnorePriority, torches[nt..]);
    if (bg1_is_room) nt += findTiles2x2(vars.dung_bg1, kBrazierTiles, kIgnorePriority, torches[nt..]);
    for (torches[0..nt], 0..) |t, ti| {
        if (n == out.len) break;
        const tx: i32 = @intCast((t & 63) * 8 + 8);
        const ty: i32 = @intCast((t >> 6) * 8 + if (ti < torch_count) @as(usize, 8) else 4);
        const f = flame(tick, @as(u32, t) + 1, kTorchBurn);
        out[n] = .{
            .x = left + @as(f32, @floatFromInt(wrapToScreen(tx, cam_x))) + f.dx,
            .y = @as(f32, @floatFromInt(wrapToScreen(ty, cam_y))) + f.dy,
            .radius = 64.0 * f.reach,
            .color = flameColor(kFlame, 1.3, f.level),
            .glow_radius = 9.0 * f.reach,
            .glow = 0.45 * f.level,
        };
        n += 1;
    }

    var add = Adder{ .out = out, .n = n, .tick = tick, .left = left, .cam_x = cam_x, .cam_y = cam_y };

    // Sconces on the walls, two candles to each.
    for (kSconces) |sc| {
        const tiles = SrcPtr(sc.src)[0 .. sc.w * sc.h];
        var found: [16]u16 = undefined;
        var nf = findBlock(vars.dung_bg2, tiles, sc.w, sc.h, sc.by_rows, kIgnorePriority, &found);
        if (bg1_is_room) nf += findBlock(vars.dung_bg1, tiles, sc.w, sc.h, sc.by_rows, kIgnorePriority, found[nf..]);
        for (found[0..nf]) |t| {
            const lx: i32 = @intCast((t & 63) * 8);
            const ly: i32 = @intCast((t >> 6) * 8);
            const seed: u32 = 0x50000 + @as(u32, t) * 2;
            if (sc.w > sc.h) {
                add.tile(kCandle, lx + 10, ly + 8, seed, 1);
                add.tile(kCandle, lx + 22, ly + 8, seed + 1, 1);
            } else {
                add.tile(kCandle, lx + 8, ly + 10, seed, 1);
                add.tile(kCandle, lx + 8, ly + 22, seed + 1, 1);
            }
        }
    }

    // Link's things: fire, sparks, magic, explosions, spells.
    for (0..10) |k| {
        const ax: i32 = @as(i32, vars.ancilla_x_lo[k]) | @as(i32, vars.ancilla_x_hi[k]) << 8;
        const ay: i32 = @as(i32, vars.ancilla_y_lo[k]) | @as(i32, vars.ancilla_y_hi[k]) << 8;
        const seed: u32 = @as(u32, @intCast(k)) + 0x10000;
        switch (vars.ancilla_type[k]) {
            // Fire rod shots and the fires they start, the lantern's flame,
            // the blast wall's fireballs, Skull Woods' fire.
            0x02, 0x2f, 0x32, 0x34 => add.world(kFire, ax + 8, ay + 8, seed, 1),
            // Byrna, the Cane of Somaria's shots, the sword's beam and what
            // it hits.
            0x30, 0x31, 0x01, 0x0c, 0x04 => add.world(kSpark, ax + 8, ay + 8, seed, 1),
            // Sparkles off the sword, spin attacks, hits on walls.
            0x0d, 0x16, 0x1b, 0x06, 0x26, 0x2a, 0x3b, 0x3c => add.world(kTinySpark, ax + 4, ay + 4, seed, 1),
            // A spin attack's sparks, which circle where it was let go. The
            // game keeps their angles and the circle's size apart from the
            // ancilla's own position, which it doesn't use for them.
            0x2b => if (vars.ancilla_L[k] == 0) {
                const cx: i32 = std.mem.readInt(u16, vars.g_ram[0x1580e..][0..2], .little);
                const cy: i32 = std.mem.readInt(u16, vars.g_ram[0x15810..][0..2], .little);
                const radius = vars.g_ram[0x15808];
                for (0..@min(@as(usize, vars.ancilla_step[k]) + 1, 4)) |spark| {
                    const p = ancilla.Ancilla_GetRadialProjection(vars.g_ram[0x15800 + spark], radius);
                    const dx: i32 = if (p.r6 != 0) -@as(i32, p.r4) else p.r4;
                    const dy: i32 = if (p.r2 != 0) -@as(i32, p.r0) else p.r0;
                    add.world(kSpinSpark, cx + dx, cy + dy, seed + @as(u32, @intCast(spark)) * 16, 1);
                }
            },
            // Magic powder.
            0x1a => add.world(kMagic, ax + 8, ay + 8, seed, 1),
            // The ice rod, cold and faint.
            0x0b, 0x11, 0x13 => add.world(kCold, ax + 8, ay + 8, seed, 1),
            // A bomb, only once it goes off: brightest at the blast, fading
            // over its last frames.
            0x07 => {
                const stage = vars.ancilla_item_to_link[k];
                if (stage != 0) add.world(kBlast, ax + 8, ay + 8, seed, fade(stage, 11));
            },
            // Blown-open walls.
            0x0e, 0x0f, 0x10, 0x12, 0x33 => add.world(kBlast, ax + 8, ay + 8, seed, 0.8),
            0x3a => add.world(kBigBlast, ax + 8, ay + 8, seed, 1),
            // A rising crystal.
            0x3e => add.world(kFairy, ax + 8, ay + 8, seed, 1),
            // Ether and Bombos light up the whole room round Link.
            0x18 => add.link(kEther, seed),
            0x19 => add.link(kBombos, seed),
            else => {},
        }
    }

    // Enemies and the things they throw.
    for (0..16) |k| {
        if (vars.sprite_state[k] == 0) continue;
        const sx: i32 = @as(i32, vars.sprite_x_lo[k]) | @as(i32, vars.sprite_x_hi[k]) << 8;
        const sy: i32 = (@as(i32, vars.sprite_y_lo[k]) | @as(i32, vars.sprite_y_hi[k]) << 8) - vars.sprite_z[k];
        const seed: u32 = @as(u32, @intCast(k)) + 0x20000;
        switch (vars.sprite_type[k]) {
            // A fireball (the Zora's sprite, carrying a fireball's flag), the
            // Helmasaur King's, a Kodongo's fire, a fire snake.
            0x55 => if (vars.sprite_E[k] != 0) add.world(kFire, sx + 8, sy + 8, seed, 0.8),
            0x70, 0x87 => add.world(kFire, sx + 8, sy + 8, seed, 1),
            0x80 => add.world(kFire, sx + 8, sy + 8, seed, 0.9),
            // A fire bar: four fireballs down an arm that turns round its hub.
            0x7e, 0x7f => {
                const angle: u16 = @as(u16, vars.sprite_A[k]) | @as(u16, vars.sprite_B[k]) << 8;
                const sin: i32 = GuruguruBarSin(angle, 0x40);
                const cos: i32 = GuruguruBarSin((angle +% 0x80) & 0x1ff, 0x40);
                for (1..5) |seg| {
                    const n4: i32 = @intCast(seg);
                    add.world(kSmallFire, sx + 8 + @divTrunc(sin * n4, 4), sy + 8 + @divTrunc(cos * n4, 4), seed + @as(u32, @intCast(seg)) * 64, 1);
                }
            },
            // Sparks that run along the walls, Vitreous's lightning, Mothula's
            // beam.
            0x5b, 0x5c, 0xbf => add.world(kElectric, sx + 8, sy + 8, seed, 1),
            0x89 => add.world(kSpark, sx + 8, sy + 8, seed, 1),
            // Baris hum faintly.
            0x23, 0x24 => add.world(kBari, sx + 8, sy + 8, seed, 1),
            // Agahnim's magic, the bunny beam.
            0x7b, 0xd1 => add.world(kMagic, sx + 8, sy + 8, seed, 1.2),
            // Fairies, and the bubbles that pretend to be them.
            0xe3, 0xc8 => add.world(kFairy, sx + 8, sy + 8, seed, 1),
            0x15, 0x77, 0x82 => add.world(kTinySpark, sx + 8, sy + 8, seed, 1),
            // A crystal switch, in whichever color it's showing.
            0x1e => add.worldColored(kCrystal, sx + 8, sy + 8, seed, spriteHue(ppu, vars.sprite_oam_flags[k])),
            else => {},
        }
    }

    // What some of those leave behind: trails and sparkles.
    for (0..30) |k| {
        const gx: i32 = @as(i32, vars.garnish_x_lo[k]) | @as(i32, vars.garnish_x_hi[k]) << 8;
        const gy: i32 = @as(i32, vars.garnish_y_lo[k]) | @as(i32, vars.garnish_y_hi[k]) << 8;
        const seed: u32 = @as(u32, @intCast(k)) + 0x30000;
        switch (vars.garnish_type[k]) {
            // A fire snake's tail, Trinexx's fire breath, Ganon's fire bats.
            0x01, 0x0e, 0x10, 0x11 => add.world(kSmallFire, gx + 4, gy + 4, seed, 0.8),
            // Lasers: the eyes', the Beamos', Blind's.
            0x04, 0x0f => add.world(kLaser, gx + 4, gy + 4, seed, 1),
            // Mothula's beam, lightning, flashes, sparkles.
            0x02, 0x07, 0x09, 0x12 => add.world(kTinySpark, gx + 4, gy + 4, seed, 1),
            else => {},
        }
    }
    return add.n;
}

/// A kind of light: how far it reaches, its color and strength, how it
/// flickers, and its glow.
const Source = struct {
    r: f32,
    c: [3]f32,
    strength: f32,
    burn: Burn,
    glow_r: f32 = 0,
    glow: f32 = 0,
};

const kCandle = Source{ .r = 48, .c = kFlame, .strength = 1.2, .burn = kTorchBurn, .glow_r = 6, .glow = 0.4 };
const kFire = Source{ .r = 44, .c = kFlame, .strength = 1.3, .burn = kFireBurn, .glow_r = 8, .glow = 0.55 };
const kSmallFire = Source{ .r = 30, .c = kFlame, .strength = 1.2, .burn = kFireBurn, .glow_r = 6, .glow = 0.5 };
const kSpark = Source{ .r = 30, .c = kSparkColor, .strength = 1.2, .burn = kSparkBurn, .glow_r = 5, .glow = 0.6 };
const kSpinSpark = Source{ .r = 34, .c = kSparkColor, .strength = 1.3, .burn = kSparkBurn, .glow_r = 5, .glow = 0.7 };
const kTinySpark = Source{ .r = 18, .c = kSparkColor, .strength = 1.0, .burn = kSparkBurn, .glow_r = 3, .glow = 0.5 };
const kElectric = Source{ .r = 40, .c = .{ 0.7, 0.85, 1.0 }, .strength = 1.3, .burn = kSparkBurn, .glow_r = 6, .glow = 0.6 };
const kMagic = Source{ .r = 34, .c = .{ 0.85, 0.55, 1.0 }, .strength = 1.2, .burn = kSparkBurn, .glow_r = 6, .glow = 0.6 };
const kFairy = Source{ .r = 40, .c = .{ 1.0, 0.75, 0.9 }, .strength = 1.1, .burn = kLanternBurn, .glow_r = 6, .glow = 0.5 };
const kCold = Source{ .r = 26, .c = .{ 0.6, 0.8, 1.0 }, .strength = 0.9, .burn = kLanternBurn, .glow_r = 4, .glow = 0.4 };
const kLaser = Source{ .r = 22, .c = .{ 1.0, 0.25, 0.2 }, .strength = 1.3, .burn = kSparkBurn, .glow_r = 4, .glow = 0.7 };
const kBari = Source{ .r = 26, .c = .{ 0.5, 0.9, 1.0 }, .strength = 0.8, .burn = kLanternBurn, .glow_r = 4, .glow = 0.35 };
const kCrystal = Source{ .r = 34, .c = .{ 1, 1, 1 }, .strength = 1.0, .burn = kLanternBurn, .glow_r = 5, .glow = 0.45 };
const kBlast = Source{ .r = 84, .c = .{ 1.0, 0.85, 0.6 }, .strength = 1.7, .burn = kFireBurn, .glow_r = 14, .glow = 0.8 };
const kBigBlast = Source{ .r = 130, .c = .{ 1.0, 0.85, 0.6 }, .strength = 1.8, .burn = kFireBurn, .glow_r = 20, .glow = 0.9 };
const kEther = Source{ .r = 160, .c = .{ 0.75, 0.85, 1.0 }, .strength = 1.6, .burn = kSparkBurn };
const kBombos = Source{ .r = 160, .c = kFlame, .strength = 1.6, .burn = kFireBurn };

/// How much of a light is left at `stage` of something that's over at
/// `last`: all of it at 1, none at `last`.
fn fade(stage: u8, last: u8) f32 {
    if (stage >= last) return 0;
    return 1.0 - @as(f32, @floatFromInt(stage - 1)) / @as(f32, @floatFromInt(last - 1));
}

/// Collects lights into a frame's list, from where they are in the world.
const Adder = struct {
    out: []Light,
    n: usize,
    tick: u32,
    left: f32,
    cam_x: i32,
    cam_y: i32,

    /// A light of kind `s` at world position (x, y), `amount` of it.
    fn world(self: *Adder, s: Source, x: i32, y: i32, seed: u32, amount: f32) void {
        self.lightAt(s, x, y, seed, s.c, amount);
    }

    fn worldColored(self: *Adder, s: Source, x: i32, y: i32, seed: u32, color: [3]f32) void {
        self.lightAt(s, x, y, seed, color, 1);
    }

    fn lightAt(self: *Adder, s: Source, x: i32, y: i32, seed: u32, color: [3]f32, amount: f32) void {
        if (self.n == self.out.len or amount <= 0) return;
        const r = s.r * @sqrt(amount);
        const sx: f32 = self.left + @as(f32, @floatFromInt(x - self.cam_x));
        const sy: f32 = @floatFromInt(y - self.cam_y);
        // Nothing reaches the frame from that far off it.
        if (sx < -r or sy < -r or sx > self.left * 2 + 256 + r or sy > 240 + r) return;
        const f = flame(self.tick, seed, s.burn);
        self.out[self.n] = .{
            .x = sx + f.dx,
            .y = sy + f.dy,
            .radius = r * f.reach,
            .color = flameColor(color, s.strength * amount, f.level),
            .glow_radius = s.glow_r * f.reach,
            .glow = s.glow * amount * f.level,
        };
        self.n += 1;
    }

    /// A light of kind `s` at (x, y) in the room's 512 pixel tile map.
    fn tile(self: *Adder, s: Source, x: i32, y: i32, seed: u32, amount: f32) void {
        self.world(s, wrapToScreen(x, self.cam_x) + self.cam_x, wrapToScreen(y, self.cam_y) + self.cam_y, seed, amount);
    }

    /// A light filling the room, centered on Link.
    fn link(self: *Adder, s: Source, seed: u32) void {
        self.world(s, @as(i32, vars.link_x_coord.*) + 8, @as(i32, vars.link_y_coord.*) + 12, seed, 1);
    }
};

extern fn GuruguruBarSin(av: u16, b: u8) i8;

/// The color of sprite palette `oam_flags` names, from what's in color
/// memory now: its colors averaged, scaled so the brightest channel is at
/// `top`.
pub fn spritePaletteColor(ppu: *const Ppu, oam_flags: u8, top: f32) [3]f32 {
    const h = spriteHue(ppu, oam_flags);
    return .{ h[0] * top, h[1] * top, h[2] * top };
}

/// The color of sprite palette `oam_flags` names, from what's in color
/// memory now: its colors averaged, brightest channel at 1.
fn spriteHue(ppu: *const Ppu, oam_flags: u8) [3]f32 {
    const base: usize = 128 + @as(usize, (oam_flags >> 1) & 7) * 16;
    var sum = [3]f32{ 0, 0, 0 };
    for (ppu.cgram[base + 1 .. base + 16]) |col| {
        sum[0] += @floatFromInt(col & 0x1f);
        sum[1] += @floatFromInt((col >> 5) & 0x1f);
        sum[2] += @floatFromInt((col >> 10) & 0x1f);
    }
    const top = @max(sum[0], @max(sum[1], sum[2]));
    if (top <= 0) return .{ 1, 1, 1 };
    return .{ sum[0] / top, sum[1] / top, sum[2] / top };
}


extern fn SrcPtr(src: u16) [*]align(1) const u16;

/// Where the room's object data keeps a lit torch's four tiles: lighting
/// one draws these, and so does a torch that's always lit.
const kLitTorchTiles = 0xeca;

/// The top-left tile of each lit torch in a room's 64x64 tile map, up to
/// `out.len` of them.
pub fn findLitTorches(map: [*]align(1) const u16, out: []u16) usize {
    return findTiles2x2(map, SrcPtr(kLitTorchTiles)[0..4].*, 0, out);
}

/// A fire that stays put in a room: where in the world, and what kind.
pub const Spot = struct { x: i32, y: i32, kind: enum { torch, brazier, candle } };

/// The room's fixed fires, the lit torches, braziers and sconces' candles,
/// in world coordinates, up to `out.len` of them. Indoors only.
pub fn flameSpots(out: []Spot) usize {
    if (vars.player_is_indoors.* == 0) return 0;
    const cam_x: i32 = vars.BG2HOFS_copy2.*;
    const cam_y: i32 = vars.BG2VOFS_copy2.*;
    const bg1_is_room = vars.hdr_dungeon_dark_with_lantern.* == 0;
    var n: usize = 0;
    const world = struct {
        fn f(local: i32, cam: i32) i32 {
            return wrapToScreen(local, cam) + cam;
        }
    }.f;
    var tiles: [24]u16 = undefined;
    for ([_]bool{ false, true }) |brazier| {
        var nt: usize = 0;
        for ([_][*]align(1) const u16{ vars.dung_bg2, vars.dung_bg1 }, 0..) |map, layer| {
            if (layer == 1 and !bg1_is_room) break;
            nt += if (brazier)
                findTiles2x2(map, kBrazierTiles, kIgnorePriority, tiles[nt..])
            else
                findLitTorches(map, tiles[nt..]);
        }
        for (tiles[0..nt]) |t| {
            if (n == out.len) return n;
            const lx: i32 = @intCast((t & 63) * 8 + 8);
            const ly: i32 = @intCast((t >> 6) * 8 + if (brazier) @as(usize, 4) else 8);
            out[n] = .{ .x = world(lx, cam_x), .y = world(ly, cam_y), .kind = if (brazier) .brazier else .torch };
            n += 1;
        }
    }
    for (kSconces) |sc| {
        const src = SrcPtr(sc.src)[0 .. sc.w * sc.h];
        var nf = findBlock(vars.dung_bg2, src, sc.w, sc.h, sc.by_rows, kIgnorePriority, &tiles);
        if (bg1_is_room) nf += findBlock(vars.dung_bg1, src, sc.w, sc.h, sc.by_rows, kIgnorePriority, tiles[nf..]);
        for (tiles[0..nf]) |t| {
            const lx: i32 = @intCast((t & 63) * 8);
            const ly: i32 = @intCast((t >> 6) * 8);
            for (0..2) |candle| {
                if (n == out.len) return n;
                const along: i32 = if (candle == 0) 10 else 22;
                const cx = if (sc.w > sc.h) lx + along else lx + 8;
                const cy = if (sc.w > sc.h) ly + 8 else ly + along;
                out[n] = .{ .x = world(cx, cam_x), .y = world(cy, cam_y), .kind = .candle };
                n += 1;
            }
        }
    }
    return n;
}

/// The wall sconce objects, as the room's object data draws them: on a
/// north or south wall four tiles across and two down, a row at a time; on a
/// west or east wall two across and four down, a column at a time.
const Sconce = struct { src: u16, w: usize, h: usize, by_rows: bool };
const kSconces = [_]Sconce{
    .{ .src = 0xa14, .w = 4, .h = 2, .by_rows = true },
    .{ .src = 0xa24, .w = 4, .h = 2, .by_rows = true },
    .{ .src = 0xa34, .w = 2, .h = 4, .by_rows = false },
    .{ .src = 0xa44, .w = 2, .h = 4, .by_rows = false },
};

/// Finds a `w` by `h` block of tiles in a 64x64 map, `tiles` listed a row
/// at a time (`by_rows`) or a column at a time, with the bits in `ignore`
/// not counting. Gives the top left tile of each.
pub fn findBlock(map: [*]align(1) const u16, tiles: []align(1) const u16, w: usize, h: usize, by_rows: bool, ignore: u16, out: []u16) usize {
    const keep = ~ignore;
    var n: usize = 0;
    for (0..64 - h + 1) |y| {
        x: for (0..64 - w + 1) |x| {
            for (0..h) |dy| for (0..w) |dx| {
                const want = tiles[if (by_rows) dy * w + dx else dx * h + dy];
                if (map[(y + dy) * 64 + x + dx] & keep != want & keep) continue :x;
            };
            if (n == out.len) return n;
            out[n] = @intCast(y * 64 + x);
            n += 1;
        }
    }
    return n;
}

/// A brazier's four tiles: its bowl of fire on top, its stand below, the
/// right half the left mirrored.
pub const kBrazierTiles = [4]u16{ 0x0dc2, 0x0dc3, 0x4dc2, 0x4dc3 };
/// A tile's priority bit, which the same picture can have either way.
pub const kIgnorePriority: u16 = 0x2000;

/// Finds a 2x2 block of tiles in a 64x64 map, given in the order the game
/// draws them: top left, bottom left, top right, bottom right, with the bits
/// in `ignore` not counting.
pub fn findTiles2x2(map: [*]align(1) const u16, tiles: [4]u16, ignore: u16, out: []u16) usize {
    const keep = ~ignore;
    var n: usize = 0;
    var i: u16 = 0;
    while (i < 63 * 64) : (i += 1) {
        if (i & 63 == 63) continue;
        if (map[i] & keep != tiles[0] & keep or map[i + 64] & keep != tiles[1] & keep or
            map[i + 1] & keep != tiles[2] & keep or map[i + 65] & keep != tiles[3] & keep) continue;
        if (n == out.len) break;
        out[n] = i;
        n += 1;
    }
    return n;
}

/// Darkens each marked pixel as the game would have, then adds back the
/// lights' glow on it.
pub fn relight(pixels: [*]u8, pitch: usize, width: usize, height: usize, dark: [3]u8, amb: f32, lights: []const Light) void {
    const keep: u32 = @intFromFloat(@round(std.math.clamp(amb, 0, 1) * 256));
    for (0..height) |y| @memset(g_light[y * kMaxWidth ..][0..width], .{ 0, 0, 0 });

    for (lights) |l| addLight(width, height, l);

    for (0..height) |y| {
        const mask = g_mask[y * kMaxWidth ..][0..width];
        const light = g_light[y * kMaxWidth ..][0..width];
        const row = pixels + y * pitch;
        for (mask, light, 0..) |m, lc, x| {
            if (m != kMaskDark) continue;
            const px: *align(1) u32 = @ptrCast(row + x * 4);
            const c = px.*;
            const r = lit(c >> 16, dark[0], keep, lc[0]);
            const g = lit(c >> 8, dark[1], keep, lc[1]);
            const b = lit(c, dark[2], keep, lc[2]);
            px.* = r << 16 | g << 8 | b;
        }
    }
}

/// One channel of a pixel: darkened by `dark` as the game does it and
/// scaled by `keep` (256 all of it), then `light` (256 is all of it) of the
/// pixel added back. Never brighter than the pixel as drawn, so the art
/// keeps its colors and the light only tints it.
fn lit(channel: u32, dark: u8, keep: u32, light: u16) u32 {
    const ch = channel & 0xff;
    const base = ((ch -| dark) * keep) >> 8;
    return @min(ch, base + ((ch * @min(light, 256)) >> 8));
}

/// Adds a light's glow to the light map: brightest at its middle and gone
/// at its radius, easing in and out with no hard edge anywhere.
fn addLight(width: usize, height: usize, l: Light) void {
    if (l.radius <= 0) return;
    const x0: i32 = @max(@as(i32, @intFromFloat(@floor(l.x - l.radius))), 0);
    const x1: i32 = @min(@as(i32, @intFromFloat(@ceil(l.x + l.radius))), @as(i32, @intCast(width)) - 1);
    const y0: i32 = @max(@as(i32, @intFromFloat(@floor(l.y - l.radius))), 0);
    const y1: i32 = @min(@as(i32, @intFromFloat(@ceil(l.y + l.radius))), @as(i32, @intCast(height)) - 1);
    if (x0 > x1 or y0 > y1) return;
    const inv_r2 = 1.0 / (l.radius * l.radius);
    const c = [3]f32{ l.color[0] * 256.0, l.color[1] * 256.0, l.color[2] * 256.0 };
    var y = y0;
    while (y <= y1) : (y += 1) {
        const dy = @as(f32, @floatFromInt(y)) + 0.5 - l.y;
        const row = g_light[@as(usize, @intCast(y)) * kMaxWidth ..];
        var x = x0;
        while (x <= x1) : (x += 1) {
            const dx = @as(f32, @floatFromInt(x)) + 0.5 - l.x;
            const d2 = (dx * dx + dy * dy) * inv_r2;
            if (d2 >= 1.0) continue;
            const t = @sqrt(d2);
            const k = 1.0 - t * t * (3.0 - 2.0 * t);
            const p = &row[@intCast(x)];
            inline for (0..3) |i| p[i] +|= @intFromFloat(c[i] * k);
        }
    }
}

const testing = std.testing;

test "the darkness is the fixed color the game takes away, at the screen's brightness" {
    var ppu: Ppu = undefined;
    for (0..32) |i| ppu.brightnessMult[i] = @intCast(i * 255 / 31);
    ppu.fixedColorR = 31;
    ppu.fixedColorG = 8;
    ppu.fixedColorB = 0;
    try testing.expectEqual([3]u8{ 255, 65, 0 }, darkness(&ppu));
}

test "flames never repeat, stay in bounds, and gutter now and then" {
    for ([_]Burn{ kLanternBurn, kTorchBurn, kFireBurn, kSparkBurn }) |b| {
        var guttering: u32 = 0;
        var same_after_256: u32 = 0;
        const frames = 60 * 600;
        for (0..frames) |i| {
            const tick: u32 = @intCast(i);
            const f = flame(tick, 7, b);
            try testing.expect(f.level > 1.0 - b.waver - b.gutter - 0.001 and f.level < 1.0 + b.waver + 0.001);
            try testing.expect(f.reach > 0.5 and f.reach < 1.5);
            try testing.expect(@abs(f.dx) <= b.sway + 0.001);
            if (f.level < 1.0 - b.waver - 0.5 * b.gutter) guttering += 1;
            if (@abs(flame(tick + 256, 7, b).level - f.level) < 0.0001) same_after_256 += 1;
        }
        // Not looping the way the game's frame counter would have made it.
        try testing.expect(same_after_256 < frames / 50);
        // Gutters come, but it's mostly burning.
        const share = @as(f32, @floatFromInt(guttering)) / frames;
        try testing.expect(share > 0.005 and share < 0.5);
    }
}

test "the same flame at the same moment is the same, and two flames differ" {
    const a = flame(1234, 1, kTorchBurn);
    try testing.expectEqual(a, flame(1234, 1, kTorchBurn));
    try testing.expect(a.level != flame(1234, 2, kTorchBurn).level);
}

test "a dimming flame goes redder" {
    const full = flameColor(kFlame, 1.0, 1.0);
    const low = flameColor(kFlame, 1.0, 0.7);
    try testing.expect(low[1] / low[0] < full[1] / full[0]);
    try testing.expect(low[2] / low[0] < full[2] / full[0]);
}

test "tilemap positions land on the nearest copy to the screen" {
    try testing.expectEqual(@as(i32, 40), wrapToScreen(100, 60));
    try testing.expectEqual(@as(i32, 40), wrapToScreen(100, 60 + 512));
    try testing.expectEqual(@as(i32, -20), wrapToScreen(40, 60));
    try testing.expectEqual(@as(i32, 300), wrapToScreen(360, 60));
}

test "with no light, marked pixels darken just as the game's math would" {
    const w = 8;
    const h = 2;
    var px: [w * h]u32 = @splat(0x00ff8040);
    @memset(g_mask[0 .. h * kMaxWidth], 0);
    for (0..w) |x| g_mask[x] = 1;
    relight(@ptrCast(&px), w * 4, w, h, .{ 0x50, 0x50, 0x50 }, 1, &.{});
    try testing.expectEqual(@as(u32, 0x00af3000), px[0]);
    try testing.expectEqual(@as(u32, 0x00ff8040), px[w]);
}

test "light brings a pixel back as far as it was drawn and no further" {
    const w = 8;
    const h = 1;
    var px: [w * h]u32 = @splat(0x00ff8040);
    @memset(g_mask[0 .. h * kMaxWidth], 0);
    for (0..w) |x| g_mask[x] = 1;
    relight(@ptrCast(&px), w * 4, w, h, .{ 255, 255, 255 }, 1, &.{.{ .x = 0, .y = 0, .radius = 10, .color = .{ 4, 4, 4 } }});
    try testing.expectEqual(@as(u32, 0x00ff8040), px[0]);
    @memset(&px, 0x00ff8040);
    relight(@ptrCast(&px), w * 4, w, h, .{ 255, 255, 255 }, 1, &.{.{ .x = 0, .y = 0, .radius = 10, .color = .{ 1, 1, 1 } }});
    // Far out at the edge of the light, only a little comes back.
    try testing.expect(px[7] < 0x00ff8040 and px[7] != 0);
}

test "torches are found by their four tiles, and nothing else is" {
    var map: [64 * 64]u16 = @splat(0x0101);
    const torch = [4]u16{ 0x11, 0x12, 0x13, 0x14 };
    for ([_]usize{ 5 * 64 + 10, 40 * 64 + 62 }) |at| {
        map[at] = torch[0];
        map[at + 64] = torch[1];
        map[at + 1] = torch[2];
        map[at + 65] = torch[3];
    }
    // Three of the four tiles is a different picture.
    map[20 * 64 + 3] = torch[0];
    map[21 * 64 + 3] = torch[1];
    map[20 * 64 + 4] = torch[2];
    var found: [4]u16 = undefined;
    const n = findTiles2x2(&map, torch, 0, &found);
    try testing.expectEqualSlices(u16, &.{ 5 * 64 + 10, 40 * 64 + 62 }, found[0..n]);
}

test "walls stop light, floors and water don't, diagonal walls about half" {
    try testing.expectEqual(@as(u8, 255), solidness(0x01));
    try testing.expectEqual(@as(u8, 255), solidness(0x27));
    try testing.expectEqual(@as(u8, 0), solidness(0x00));
    try testing.expectEqual(@as(u8, 0), solidness(0x09));
    try testing.expectEqual(@as(u8, 0), solidness(0xc3)); // a torch
    try testing.expectEqual(@as(u8, 128), solidness(0x12));
}

test "an explosion's light fades out over its frames" {
    try testing.expectEqual(@as(f32, 1), fade(1, 11));
    try testing.expect(fade(6, 11) > 0.4 and fade(6, 11) < 0.6);
    try testing.expectEqual(@as(f32, 0), fade(11, 11));
}

test "a room that isn't dark is dimmed by scaling, not by taking a fixed amount off" {
    const w = 4;
    var px: [w]u32 = @splat(0x00804020);
    @memset(g_mask[0..kMaxWidth], 0);
    for (0..w) |x| g_mask[x] = 1;
    relight(@ptrCast(&px), w * 4, w, 1, .{ 0, 0, 0 }, 0.5, &.{});
    try testing.expectEqual(@as(u32, 0x00402010), px[0]);
}

test "braziers are found whichever way their priority bit is set" {
    var map: [64 * 64]u16 = @splat(0);
    const at = 10 * 64 + 20;
    map[at] = kBrazierTiles[0] | 0x2000;
    map[at + 64] = kBrazierTiles[1] | 0x2000;
    map[at + 1] = kBrazierTiles[2] | 0x2000;
    map[at + 65] = kBrazierTiles[3] | 0x2000;
    var found: [2]u16 = undefined;
    try testing.expectEqual(@as(usize, 1), findTiles2x2(&map, kBrazierTiles, kIgnorePriority, &found));
    try testing.expectEqual(@as(usize, 0), findTiles2x2(&map, kBrazierTiles, 0, &found));
}

test "blocks are found laid out by rows or by columns" {
    var map: [64 * 64]u16 = @splat(0);
    // A 4x2 block at (10, 5), listed a row at a time.
    const rows = [_]u16{ 1, 2, 3, 4, 5, 6, 7, 8 };
    for (0..2) |dy| for (0..4) |dx| {
        map[(5 + dy) * 64 + 10 + dx] = rows[dy * 4 + dx];
    };
    var found: [4]u16 = undefined;
    try testing.expectEqual(@as(usize, 1), findBlock(&map, &rows, 4, 2, true, 0, &found));
    try testing.expectEqual(@as(u16, 5 * 64 + 10), found[0]);
    // The same tiles read a column at a time are a different picture.
    try testing.expectEqual(@as(usize, 0), findBlock(&map, &rows, 2, 4, false, 0, &found));
}
