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
const config = @import("config.zig");
const snes_pkg = @import("snes");
const Ppu = snes_pkg.ppu_types.Ppu;
const ppu_mod = snes_pkg.ppu;

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
pub const kMaxGpuLights = 24;

var g_gpu_frame: GpuFrame = undefined;
var g_gpu_pending = false;
var g_gpu_mask: [kMaxHeight * kMaxWidth]u32 = undefined;

const kLantern = [3]f32{ 1.0, 0.93, 0.78 };
const kFlame = [3]f32{ 1.0, 0.78, 0.5 };
const kSpark = [3]f32{ 0.75, 0.85, 1.0 };

/// A dark room is on screen and dynamic lighting's on: the game's own
/// darkness rules, as the widescreen margins read them in zelda_rtl.zig.
fn darkRoom() bool {
    if (!config.g_config.dynamic_lighting) return false;
    if (vars.player_is_indoors.* == 0) return false;
    return vars.hdr_dungeon_dark_with_lantern.* != 0 or vars.dung_want_lights_out.* != 0;
}

/// Before the PPU draws a frame: in a dark room, hands it the mask to mark.
/// Needs the whole-line renderer, the only one that knows about the mask.
pub fn beginFrame(render_flags: u32, height: usize) void {
    g_active = render_flags & snes_pkg.ppu_types.kPpuRenderFlags_NewRenderer != 0 and darkRoom();
    if (!g_active) {
        ppu_mod.g_light_mask = null;
        return;
    }
    @memset(g_mask[0 .. height * kMaxWidth], 0);
    ppu_mod.g_light_mask = .{ .mask = &g_mask, .pitch = kMaxWidth };
}

/// After the PPU's drawn the frame into `pixels` (XRGB, `pitch` bytes a
/// row): lays the light over the pixels it marked.
pub fn endFrame(ppu: *const Ppu, pixels: [*]u8, pitch: usize, height: usize) void {
    ppu_mod.g_light_mask = null;
    if (!g_active) return;
    g_active = false;
    const width: usize = 256 + 2 * @as(usize, ppu.extraLeftRight);

    g_tick +%= 1;
    var lights: [32]Light = undefined;
    const n = gatherLights(ppu, &lights);
    if (!g_gpu) {
        relight(pixels, pitch, width, height, darkness(ppu), lights[0..n]);
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
        .dark = darkness(ppu),
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
    relight(pixels, pitch, f.width, f.height, f.dark, f.lights[0..f.n]);
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
    if (vars.link_item_torch.* != 0) {
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
    var torches: [16]u16 = undefined;
    var nt = findLitTorches(vars.dung_bg2, &torches);
    if (vars.hdr_dungeon_dark_with_lantern.* == 0) nt += findLitTorches(vars.dung_bg1, torches[nt..]);
    for (torches[0..nt]) |t| {
        if (n == out.len) break;
        const tx: i32 = @intCast((t & 63) * 8 + 8);
        const ty: i32 = @intCast((t >> 6) * 8 + 8);
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

    // Things burning or sparking: fire rod shots and the fires they start,
    // the lantern's flame, Byrna's sparks.
    for (0..10) |k| {
        if (n == out.len) break;
        const kind: struct { r: f32, c: [3]f32, strength: f32, burn: Burn, glow_r: f32, glow: f32 } = switch (vars.ancilla_type[k]) {
            0x02, 0x2f, 0x32, 0x34 => .{ .r = 44, .c = kFlame, .strength = 1.3, .burn = kFireBurn, .glow_r = 8, .glow = 0.55 },
            0x30, 0x31 => .{ .r = 30, .c = kSpark, .strength = 1.2, .burn = kSparkBurn, .glow_r = 5, .glow = 0.6 },
            else => continue,
        };
        const ax: i32 = @as(i32, vars.ancilla_x_lo[k]) | @as(i32, vars.ancilla_x_hi[k]) << 8;
        const ay: i32 = @as(i32, vars.ancilla_y_lo[k]) | @as(i32, vars.ancilla_y_hi[k]) << 8;
        const f = flame(tick, @as(u32, @intCast(k)) + 0x10000, kind.burn);
        out[n] = .{
            .x = left + @as(f32, @floatFromInt(ax - cam_x + 8)) + f.dx,
            .y = @as(f32, @floatFromInt(ay - cam_y + 8)) + f.dy,
            .radius = kind.r * f.reach,
            .color = flameColor(kind.c, kind.strength, f.level),
            .glow_radius = kind.glow_r * f.reach,
            .glow = kind.glow * f.level,
        };
        n += 1;
    }
    return n;
}

extern fn SrcPtr(src: u16) [*]align(1) const u16;

/// Where the room's object data keeps a lit torch's four tiles: lighting
/// one draws these, and so does a torch that's always lit.
const kLitTorchTiles = 0xeca;

/// The top-left tile of each lit torch in a room's 64x64 tile map, up to
/// `out.len` of them.
pub fn findLitTorches(map: [*]align(1) const u16, out: []u16) usize {
    return findTiles2x2(map, SrcPtr(kLitTorchTiles)[0..4].*, out);
}

/// Finds a 2x2 block of tiles in a 64x64 map, given in the order the game
/// draws them: top left, bottom left, top right, bottom right.
pub fn findTiles2x2(map: [*]align(1) const u16, tiles: [4]u16, out: []u16) usize {
    var n: usize = 0;
    var i: u16 = 0;
    while (i < 63 * 64) : (i += 1) {
        if (i & 63 == 63) continue;
        if (map[i] != tiles[0] or map[i + 64] != tiles[1] or map[i + 1] != tiles[2] or map[i + 65] != tiles[3]) continue;
        if (n == out.len) break;
        out[n] = i;
        n += 1;
    }
    return n;
}

/// Darkens each marked pixel as the game would have, then adds back the
/// lights' glow on it.
pub fn relight(pixels: [*]u8, pitch: usize, width: usize, height: usize, dark: [3]u8, lights: []const Light) void {
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
            const r = lit(c >> 16, dark[0], lc[0]);
            const g = lit(c >> 8, dark[1], lc[1]);
            const b = lit(c, dark[2], lc[2]);
            px.* = r << 16 | g << 8 | b;
        }
    }
}

/// One channel of a pixel: darkened by `dark` as the game does it, then
/// `light` (256 is all of it) of the pixel added back. Never brighter than
/// the pixel as drawn, so the art keeps its colors and the light only tints
/// it.
fn lit(channel: u32, dark: u8, light: u16) u32 {
    const ch = channel & 0xff;
    const base = ch -| dark;
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
    relight(@ptrCast(&px), w * 4, w, h, .{ 0x50, 0x50, 0x50 }, &.{});
    try testing.expectEqual(@as(u32, 0x00af3000), px[0]);
    try testing.expectEqual(@as(u32, 0x00ff8040), px[w]);
}

test "light brings a pixel back as far as it was drawn and no further" {
    const w = 8;
    const h = 1;
    var px: [w * h]u32 = @splat(0x00ff8040);
    @memset(g_mask[0 .. h * kMaxWidth], 0);
    for (0..w) |x| g_mask[x] = 1;
    relight(@ptrCast(&px), w * 4, w, h, .{ 255, 255, 255 }, &.{.{ .x = 0, .y = 0, .radius = 10, .color = .{ 4, 4, 4 } }});
    try testing.expectEqual(@as(u32, 0x00ff8040), px[0]);
    @memset(&px, 0x00ff8040);
    relight(@ptrCast(&px), w * 4, w, h, .{ 255, 255, 255 }, &.{.{ .x = 0, .y = 0, .radius = 10, .color = .{ 1, 1, 1 } }});
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
    const n = findTiles2x2(&map, torch, &found);
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
