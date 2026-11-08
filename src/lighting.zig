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
//! Rooms that aren't dark get it too, gentler: a room with a fire of its
//! own (a lit torch, brazier or sconce) is dimmed a little, by scaling its
//! colors rather than taking a fixed amount off them, so its flames have
//! something to light. A room without one is left as it's drawn.
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
const features = @import("features.zig");
const sprite_tables = @import("sprite_main_tables.zig");
const dungeon_wide = @import("dungeon_wide.zig");

const kMaxWidth = 256 + 2 * snes_pkg.ppu_types.kPpuExtraLeftRight;
const kMaxHeight = 240;

var g_mask: [kMaxHeight * kMaxWidth]u8 = undefined;
/// Which layer each pixel came from, as the PPU's compositing saw it (see
/// ppu.LightMask), the main screen's in the low four bits and the
/// subscreen's in the high: the water's ripple is for the backgrounds, not
/// what's drawn over them.
var g_layers: [kMaxHeight * kMaxWidth]u8 = undefined;

/// The main screen's layer at a pixel: 0 to 3 a background, 4 a sprite.
fn layerAt(i: usize) u8 {
    return g_layers[i] & 0xf;
}

/// Whether BG1 is under a pixel on the subscreen: blended in, see-through,
/// the way Swamp Palace's water lies over the floor.
fn bg1Underneath(i: usize) bool {
    return g_layers[i] >> 4 == 0;
}

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
    /// Indoors, where the room's tiles say what's solid; outdoors nothing
    /// casts a shadow.
    indoors: bool,
    /// The lightning's flash, 0 to 1.
    flash: f32,
    /// There's water in the frame for HD Water to work on.
    water: bool = false,
    /// Game frames gone by, for the water to move in time with the game
    /// rather than the screen's refresh.
    tick: u32 = 0,
    /// Out in the desert, where the heat shimmers over the picture.
    heat: bool = false,
    /// Lava on the screen, the air above it shimmering: how hot each pixel's
    /// air is goes in the mask's alpha.
    lava: bool = false,
    /// Blasts' shockwaves rippling out over the picture: where each started
    /// in the world, how far it's spread and how hard it still pushes.
    shocks: [kMaxShocks][4]f32 = undefined,
    nshocks: usize = 0,
    /// What's reflected in the water: Link and anything else standing in
    /// or beside it, each as the columns it covers, the row its feet are on
    /// and its top row, on the frame.
    mirrors: [kMaxMirrors][4]f32 = undefined,
    nmirrors: usize = 0,
    /// A pixel a u32, `width` to a row: the mask's value in red, solid
    /// ground in green, as light_map.frag reads them, and the water in blue
    /// (254 deep, 140 shallow, 200 see-through, odd in the water's own
    /// colors) for light_apply.frag; in alpha, 255 less how hot the air is
    /// over lava, and its lowest bit clear for a sprite.
    mask: []const u32,
};
pub const kMaxGpuLights = 48;

/// How many lights a frame gathers before the ones that matter least are
/// let go: a room full of laser eyes firing can make more than the shaders
/// take.
const kMaxGathered = 128;

/// How much a light matters, to choose which to keep when there are too
/// many: how bright, how far it reaches, and its glow.
fn lightWeight(l: Light) f32 {
    const bright = @max(l.color[0], @max(l.color[1], l.color[2]));
    return bright * l.radius + l.glow * l.glow_radius;
}

/// Puts the `limit` lights that matter most first, if there are more than
/// that, and says how many to use. In the order they came otherwise, so a
/// room under the limit lights the same as ever.
pub fn keepBrightest(lights: []Light, limit: usize) usize {
    if (lights.len <= limit) return lights.len;
    std.sort.pdq(Light, lights, {}, struct {
        fn more(_: void, a: Light, b: Light) bool {
            return lightWeight(a) > lightWeight(b);
        }
    }.more);
    return limit;
}

var g_gpu_frame: GpuFrame = undefined;
var g_gpu_pending = false;
var g_gpu_mask: [kMaxHeight * kMaxWidth]u32 = undefined;

const kLantern = [3]f32{ 1.0, 0.93, 0.78 };
const kFlame = [3]f32{ 1.0, 0.78, 0.5 };
const kSparkColor = [3]f32{ 0.75, 0.85, 1.0 };

/// How a room's lit: a dark room, with the game's own darkness relit; any
/// other room indoors, dimmed a little for its flames to light; or not at
/// all (outdoors, or dynamic lighting off). `plain` is not at all, but with
/// particles to draw, which want the HUD told apart from the scene. `storm`
/// is outdoors in the rain: lightning, and Link's lantern in the dark.
/// `glow` is outdoors otherwise, with something there that glows, a warp
/// pad or the mirror's portal: their glow, and the day left as it is.
pub const Mode = enum { off, dark, mood, plain, storm, glow };

/// It's raining outside, by the game's own rule (OverworldOverlay_HandleRain):
/// all over Hyrule until Zelda's rescued, and over the swamp in the Dark
/// World until it's drained.
pub fn raining() bool {
    if (vars.player_is_indoors.* != 0) return false;
    // Only out in the world: not the title screen, the file select or the
    // attract mode, where no save's loaded and the rule would say rain.
    var module = vars.main_module_index.*;
    if (module == 14) module = vars.saved_module_for_menu.*;
    if (module != 9 and module != 11) return false;
    const screen: u8 = @truncate(vars.overworld_screen_index.*);
    if (screen != 0x70 and vars.sram_progress_indicator.* >= 2) return false;
    return vars.save_ow_event_info[0x70] & 0x20 == 0;
}

/// The lightning's flash, up to 1 at a strike, fading over a few frames.
///
/// The game flashes like clockwork, at the same three points in every 256
/// frames (its frame counter going round), with the thunder at frame 36.
/// With dynamic lighting on, that flash is kept off the screen (beginFrame)
/// and the storm strikes on a schedule of its own instead: each time round,
/// one strike a moment before the thunder, the gap different every time, as
/// real thunder lags its lightning by however far off it struck; and now
/// and then a fainter one somewhere in between, too far off to hear. Each
/// strike flickers its own way, once, twice or three times.
var g_flash: f32 = 0;
var g_flash_frame: u8 = 0;

/// The flash as it's shown: much softer with Dim Flashes on, as the game
/// softens its own (a fifth as strong there).
pub fn flash() f32 {
    return if (dimFlashes()) g_flash * kDimFlash else g_flash;
}

/// Dim Flashes, the setting for anyone who'd rather the screen didn't
/// flash: as the game reads it.
pub fn dimFlashes() bool {
    return features.enhanced_features0.* & features.kFeatures0_DimFlashes != 0;
}

/// How much of a lightning flash shows with Dim Flashes on.
const kDimFlash: f32 = 0.25;

/// A flame's flicker with Dim Flashes on: slower and shallower, so a light
/// that fills the room (Ether's, a bolt's) swells and fades rather than
/// strobing.
pub fn steadyBurn(b: Burn) Burn {
    return .{
        .waver = b.waver * 0.35,
        .speed = b.speed * 0.5,
        .gutter = b.gutter * 0.25,
        .gutter_odds = b.gutter_odds,
        .sway = b.sway,
    };
}

/// The frame of the game's 256 that its thunder plays on.
const kThunderFrame = 36;

const Strike = struct { at: u8, power: f32 };
var g_strikes: [3]Strike = undefined;
var g_nstrikes: usize = 0;
/// A strike's flickers still to come: frames to wait, and how bright.
var g_pulses: [2]struct { wait: u8, power: f32 } = .{ .{ .wait = 0, .power = 0 }, .{ .wait = 0, .power = 0 } };
var g_weather_rng = std.Random.DefaultPrng.init(0x7417_5701);

fn weatherRand(lo: f32, hi: f32) f32 {
    return lo + (hi - lo) * g_weather_rng.random().float(f32);
}

/// This time round's strikes.
fn planStrikes() void {
    g_nstrikes = 0;
    const lead: u8 = @intFromFloat(weatherRand(6, 36));
    g_strikes[0] = .{ .at = kThunderFrame - lead, .power = weatherRand(0.8, 1.0) };
    g_nstrikes = 1;
    const far: usize = @intFromFloat(weatherRand(0, 2.99));
    for (0..far) |_| {
        g_strikes[g_nstrikes] = .{ .at = @intFromFloat(weatherRand(60, 250)), .power = weatherRand(0.3, 0.6) };
        g_nstrikes += 1;
    }
}

fn strike(power: f32) void {
    g_flash = @max(g_flash, power);
    // One, two or three flickers.
    const more: usize = @intFromFloat(weatherRand(0, 2.99));
    for (&g_pulses, 0..) |*p, i| {
        p.* = if (i < more)
            .{ .wait = @intFromFloat(weatherRand(2, 4) + @as(f32, @floatFromInt(i)) * 3), .power = power * weatherRand(0.5, 0.95) }
        else
            .{ .wait = 0, .power = 0 };
    }
}

/// Which sprite slots held a bolt of lightning last game frame, to catch a
/// new one.
var g_bolts: u16 = 0;

/// How strong the cold wash is as a bolt comes down: softer than the storm's,
/// since the game strobes the room on top of it.
const kBoltFlash: f32 = 0.3;

/// A bolt of Agahnim's or Vitreous's lightning just come down washes the
/// room cold for a moment, as the storm's does outside.
fn noteBolts() void {
    var now: u16 = 0;
    for (0..16) |k| {
        if (vars.sprite_state[k] != 0 and vars.sprite_type[k] == 0xbf) now |= @as(u16, 1) << @intCast(k);
    }
    if (now & ~g_bolts != 0 and config.g_config.dynamic_lighting) g_flash = @max(g_flash, kBoltFlash);
    g_bolts = now;
}

/// How much of each bolt's light there is: Agahnim brings four down at
/// once, close together, which would be four times as bright, and while the
/// game's flashing the room white for them there's less to add.
fn boltAmount() f32 {
    const n: f32 = @floatFromInt(@max(@popCount(g_bolts), 1));
    const strobe: f32 = if (vars.intro_times_pal_flash.* != 0) 0.8 else 1.0;
    const dim: f32 = if (dimFlashes()) 0.6 else 1.0;
    return strobe * dim / @sqrt(n);
}

/// Each game frame: a strike, a flicker, or the last one fading.
pub fn stepWeather() void {
    const fc = vars.frame_counter.*;
    if (fc == g_flash_frame) return;
    const wrapped = fc < g_flash_frame;
    g_flash_frame = fc;
    g_flash *= 0.72;
    if (g_flash < 0.02) g_flash = 0;
    noteBolts();
    if (!raining()) {
        g_nstrikes = 0;
        return;
    }
    if (wrapped or g_nstrikes == 0) planStrikes();
    for (g_strikes[0..g_nstrikes]) |s| {
        if (s.at == fc) strike(s.power);
    }
    for (&g_pulses) |*p| {
        if (p.wait == 0) continue;
        p.wait -= 1;
        if (p.wait == 0) g_flash = @max(g_flash, p.power);
    }
}

/// How much of its light a room that isn't dark keeps, for the flames to
/// make up: what Room Dimming leaves.
pub fn moodAmbient() f32 {
    const dim: f32 = @floatFromInt(@min(config.g_config.room_dimming, 40));
    return 1 - dim / 100;
}

/// A room that isn't dark is only dimmed if it has a fire of its own, a lit
/// torch, brazier or sconce: one seen burning since Link came in. A room
/// with none is left as the original draws it, the fire rod's shots and the
/// like still glowing in it. Lighting a room's first torch dims it then.
var g_fire_room: ?u16 = null;
var g_room_has_fire = false;

/// The dimming as it is now, easing toward what the room wants rather than
/// snapping: a torch scrolling into view, or lit by the fire rod, dims the
/// room over a third of a second or so.
/// Frames that weren't drawn one after another (a snapshot loaded, a
/// screenshot of a script's last frame) jump straight there.
var g_mood_ambient: f32 = 1;
var g_dim_frame: u8 = 0;
const kDimStep: f32 = 0.012;

fn noteRoomFires() void {
    const room = vars.dungeon_room_index.*;
    if (g_fire_room == null or g_fire_room.? != room) {
        g_fire_room = room;
        g_room_has_fire = false;
    }
    for (g_spots[0..g_nspots]) |spot| {
        // Lava counts: it's what lights the room.
        if (spot.kind != .warp and spot.kind != .waterfall) g_room_has_fire = true;
    }
}

/// The step from the dimming `now` toward `target`, `step` at most.
pub fn easeToward(now: f32, target: f32, step: f32) f32 {
    if (now < target) return @min(now + step, target);
    return @max(now - step, target);
}

fn roomMode() Mode {
    // Particles want the HUD told apart from the scene, and indoors the
    // room's fires checked for their embers; HD Water, the water found.
    const plain: Mode = if (g_water_on or g_heat_on or g_shock_on or (particles.enabled() and (particles.count() != 0 or vars.player_is_indoors.* != 0))) .plain else .off;
    if (!config.g_config.dynamic_lighting) return plain;
    if (vars.player_is_indoors.* == 0) {
        if (raining()) return .storm;
        if (outdoorGlows()) return .glow;
        // A waterfall's mist wants the frame looked at.
        if (particles.enabled() and outdoorWaterfallNear()) return .plain;
        return plain;
    }
    // The game's own darkness rules, as the widescreen margins read them in
    // zelda_rtl.zig.
    if (vars.hdr_dungeon_dark_with_lantern.* != 0 or vars.dung_want_lights_out.* != 0) return .dark;
    return .mood;
}

var g_mode: Mode = .off;

/// The PPU's half-color math as the game set it, while a storm frame's
/// drawn with the game's own flash kept off it.
var g_saved_half_color: ?bool = null;

/// Before the PPU draws a frame: in a dark room, hands it the mask to mark.
/// Needs the whole-line renderer, the only one that knows about the mask.
pub fn beginFrame(ppu: *Ppu, render_flags: u32, height: usize) void {
    const new_renderer = render_flags & snes_pkg.ppu_types.kPpuRenderFlags_NewRenderer != 0;
    g_water_on = new_renderer and scanWater(ppu.extraLeftRight);
    g_heat_on = new_renderer and heatHaze();
    g_shock_on = new_renderer and g_gpu and g_nshocks != 0;
    g_mode = if (new_renderer) roomMode() else .off;
    g_active = g_mode != .off;
    // The game's flash adds the rain layer on at full strength instead of
    // half: drawn at half, the storm's own lightning does the flashing.
    if (g_mode == .storm) {
        g_saved_half_color = ppu.halfColor;
        ppu.halfColor = true;
    }
    if (!g_active) {
        ppu_mod.g_light_mask = null;
        return;
    }
    @memset(g_mask[0 .. height * kMaxWidth], 0);
    @memset(g_layers[0 .. height * kMaxWidth], 0xff);
    ppu_mod.g_light_mask = .{ .mask = &g_mask, .pitch = kMaxWidth, .dark = g_mode == .dark, .layers = &g_layers };
}

/// After the PPU's drawn the frame into `pixels` (XRGB, `pitch` bytes a
/// row): lays the light over the pixels it marked.
pub fn endFrame(ppu: *Ppu, pixels: [*]u8, pitch: usize, height: usize) void {
    ppu_mod.g_light_mask = null;
    if (g_saved_half_color) |h| ppu.halfColor = h;
    g_saved_half_color = null;
    if (!g_active) return;
    g_active = false;
    const width: usize = 256 + 2 * @as(usize, ppu.extraLeftRight);

    g_tick +%= 1;
    refreshSpots(.{ .pixels = pixels, .pitch = pitch, .width = width, .height = height }, ppu.extraLeftRight);
    particles.iceGlints(pixels, pitch, width, height, &g_mask, kMaxWidth, ppu.extraLeftRight);
    if (g_mode == .mood) {
        noteRoomFires();
        const target: f32 = if (g_room_has_fire) moodAmbient() else 1;
        const fc = vars.frame_counter.*;
        const step: f32 = if (fc -% g_dim_frame == 1) kDimStep else 1;
        g_dim_frame = fc;
        g_mood_ambient = easeToward(g_mood_ambient, target, step);
    } else {
        g_mood_ambient = 1;
    }
    var lights: [kMaxGathered]Light = undefined;
    const gathered = switch (g_mode) {
        .plain => 0,
        .storm => stormLights(ppu, &lights),
        .glow => glowLights(ppu, &lights),
        else => gatherLights(ppu, &lights),
    };
    const n = keepBrightest(lights[0..gathered], kMaxGpuLights);
    const dark: [3]u8 = if (g_mode == .dark) darkness(ppu) else .{ 0, 0, 0 };
    const amb: f32 = switch (g_mode) {
        .mood => g_mood_ambient,
        .storm => kStormAmbient,
        else => 1,
    };
    if (!g_gpu) {
        if (g_mode != .plain) relight(pixels, pitch, width, height, dark, amb, lights[0..n]);
        if (flash() > 0) flashCpu(pixels, pitch, width, height, flash());
        particles.drawCpu(pixels, pitch, .{
            .left = ppu.extraLeftRight,
            .cam_x = vars.BG2HOFS_copy2.*,
            .cam_y = vars.BG2VOFS_copy2.*,
            .width = width,
            .height = height,
            .dark = .{ @as(f32, @floatFromInt(dark[0])) / 255, @as(f32, @floatFromInt(dark[1])) / 255, @as(f32, @floatFromInt(dark[2])) / 255 },
            .ambient = amb,
            .lights = lights[0..n],
            .flash = flash(),
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
        .indoors = vars.player_is_indoors.* != 0,
        .flash = flash(),
        .water = g_water_on,
        .heat = g_heat_on,
        .lava = lavaShimmer(),
        .tick = g_tick,
        .mask = &.{},
    };
    @memcpy(g_gpu_frame.lights[0..k], lights[0..k]);
    if (g_shock_on) packShocks(&g_gpu_frame);
    g_gpu_pending = true;
}

/// Outdoors out of the rain: the warp pads refreshSpots saw, glowing in
/// their own color, and the portal the mirror leaves in the Light World,
/// shimmering in whatever color it's cycling through.
fn glowLights(ppu: *const Ppu, out: []Light) usize {
    var add = Adder{
        .out = out,
        .n = 0,
        .tick = g_tick,
        .left = @floatFromInt(ppu.extraLeftRight),
        .cam_x = vars.BG2HOFS_copy2.*,
        .cam_y = vars.BG2VOFS_copy2.*,
    };
    for (g_spots[0..g_nspots]) |spot| {
        if (spot.kind != .warp) continue;
        const seed: u32 = 0x50000 +% (@as(u32, @bitCast(spot.x)) *% 73856093 ^ @as(u32, @bitCast(spot.y)) *% 19349663);
        add.worldColored(kOutdoorWarp, spot.x, spot.y, seed, spot.color);
    }
    for (0..16) |k| {
        if (!mirrorPortalShown(k)) continue;
        const sx: i32 = @as(i32, vars.sprite_x_lo[k]) | @as(i32, vars.sprite_x_hi[k]) << 8;
        const sy: i32 = @as(i32, vars.sprite_y_lo[k]) | @as(i32, vars.sprite_y_hi[k]) << 8;
        add.worldColored(kPortal, sx + 8, sy + 8, @as(u32, @intCast(k)) + 0x20000, spriteHue(ppu, vars.sprite_oam_flags[k]));
    }
    return add.n;
}

/// Whether the mirror's portal in slot `k` is drawn (Sprite_6C_MirrorPortal):
/// in the Light World, out of the way while Link's going through it.
fn mirrorPortalShown(k: usize) bool {
    return vars.sprite_state[k] != 0 and vars.sprite_type[k] == 0x6c and
        vars.savegame_is_darkworld.* == 0 and
        @as(u8, @truncate(vars.overworld_screen_index.*)) < 0x80 and
        vars.submodule_index.* != 0x23 and vars.byte_7E0FC6.* < 3;
}

/// Outdoors, whether there's anything to glow: a warp pad on or near the
/// screen, or the mirror's portal.
fn outdoorGlows() bool {
    const cam_x: i32 = vars.BG2HOFS_copy2.*;
    const cam_y: i32 = vars.BG2VOFS_copy2.*;
    const reach: i32 = snes_pkg.ppu_types.kPpuExtraLeftRight + 32;
    for (0..16) |k| {
        if (!mirrorPortalShown(k)) continue;
        // The game keeps the portal where it was left, which may be well
        // off the screen.
        const sx: i32 = (@as(i32, vars.sprite_x_lo[k]) | @as(i32, vars.sprite_x_hi[k]) << 8) - cam_x;
        const sy: i32 = (@as(i32, vars.sprite_y_lo[k]) | @as(i32, vars.sprite_y_hi[k]) << 8) - cam_y;
        if (sx > -reach and sx < 256 + reach and sy > -48 and sy < 224 + 48) return true;
    }
    var spots: [4]Spot = undefined;
    return findOutdoorWarps(&spots) != 0;
}

extern fn Overworld_GetTileAttributeAtLocation(x: u16, y: u16) u8;

/// The overworld's warp pads on the screen or its margins, in world
/// coordinates: ground the game warps Link on (the same attribute as a
/// dungeon's warp tile), a 16 pixel square at a time, each pad's squares
/// counted as one at their middle. Out in the world only, not the title or
/// file select, which keep their own maps.
fn findOutdoorWarps(out: []Spot) usize {
    var module = vars.main_module_index.*;
    if (module == 14) module = vars.saved_module_for_menu.*;
    if (module != 9) return 0;
    const sv = vars.ow_scroll_vars0.*;
    const cam_x: i32 = vars.BG2HOFS_copy2.*;
    const cam_y: i32 = vars.BG2VOFS_copy2.*;
    const reach = snes_pkg.ppu_types.kPpuExtraLeftRight;
    // The area's bounds: its camera range, and a screen past the far end.
    const x0 = @max(cam_x - reach, @as(i32, sv.xstart)) & ~@as(i32, 15);
    const x1 = @min(cam_x + 256 + reach, @as(i32, sv.xend) + 256);
    const y0 = @max(cam_y, @as(i32, sv.ystart)) & ~@as(i32, 15);
    const y1 = @min(cam_y + 224, @as(i32, sv.yend) + 224);
    const warpAt = struct {
        fn f(x: i32, y: i32) bool {
            // It takes x in 8 pixel steps and y in pixels, as its callers
            // in the game pass them.
            const tx: u16 = @truncate(@as(u32, @bitCast(x + 4)) >> 3);
            return Overworld_GetTileAttributeAtLocation(tx, @truncate(@as(u32, @bitCast(y + 4)))) == kWarpAttr;
        }
    }.f;
    var n: usize = 0;
    var y = y0;
    while (y < y1) : (y += 16) {
        var x = x0;
        while (x < x1) : (x += 16) {
            // A pad's top left square only.
            if (!warpAt(x, y) or warpAt(x - 16, y) or warpAt(x, y - 16)) continue;
            var w: i32 = 1;
            while (w < 4 and warpAt(x + w * 16, y)) w += 1;
            var h: i32 = 1;
            while (h < 4 and warpAt(x, y + h * 16)) h += 1;
            if (n == out.len) return n;
            out[n] = .{ .x = x + w * 8, .y = y + h * 8, .kind = .warp };
            n += 1;
        }
    }
    return n;
}

/// Out in the world, the attribute of the face of falling water (the same
/// as a cliff's), and of the deep water it falls into.
const kFallAttr = 0x02;
const kDeepWaterAttr = 0x08;

fn overworldAttr(x: i32, y: i32) u8 {
    // x in 8 pixel steps, y in pixels, as the game's callers pass them.
    return Overworld_GetTileAttributeAtLocation(@truncate(@as(u32, @bitCast(x)) >> 3), @truncate(@as(u32, @bitCast(y))));
}

/// A room's tile attribute at (x, y) in the world, as far as its water
/// goes, and whether it's steps going down into water. Swamp Palace keeps
/// its water on the upper layer, BG1, over floor on the lower one, and only
/// while BG1's drawn (it isn't till the water's let in, though the tiles
/// say water all along); where the lower one has deep water (and the 0x02
/// either side) under it, those are the steps, drawn over the water.
/// Elsewhere the water's on the lower layer, as anything else is.
pub fn dungeonAttr(lo: u8, hi: u8, bg1_shown: bool) struct { attr: u8, steps: bool = false, upper: bool = false } {
    if (waterDepth(hi) != 0) {
        if (!bg1_shown) return .{ .attr = lo };
        if (waterDepth(lo) != 0 or lo == 0x02) return .{ .attr = 0, .steps = true, .upper = true };
        return .{ .attr = hi, .upper = true };
    }
    return .{ .attr = lo };
}

/// A room's tile as far as its water goes: the water attribute dungeonAttr
/// gives it, whether it's steps going into water, whether its water's on
/// the upper layer, and the depth the lower layer's tiles say.
const RoomTile = struct { attr: u8, steps: bool, upper: bool, lower: u8 };

/// The room being played's tiles, a byte each (packRoomTile), as of the
/// last frame, and the room before it's as they were when it was left:
/// on the way from one room to the next, the one being left has no tiles
/// loaded any more.
var g_room_water: [64 * 64]u8 = @splat(0);
var g_room_water_id: i32 = -1;
var g_left_water: [64 * 64]u8 = @splat(0);
var g_left_water_id: i32 = -1;
/// Whether the room being left had see-through water blended in on BG1.
var g_left_overlay = false;
/// Tiles on the screen that are the room being left's.
var g_water_left: [kWaterRows][kWaterCols]bool = undefined;

fn packRoomTile(t: RoomTile) u8 {
    return waterDepth(t.attr) | @as(u8, @intFromBool(t.steps)) << 2 | @as(u8, @intFromBool(t.upper)) << 3 | t.lower << 4;
}

fn unpackRoomTile(b: u8) RoomTile {
    const depth = b & 3;
    return .{ .attr = if (depth == 2) 0x08 else if (depth == 1) 0x09 else 0, .steps = b & 4 != 0, .upper = b & 8 != 0, .lower = b >> 4 };
}

fn roomTileIndex(x: i32, y: i32) usize {
    return @intCast((@mod(y, 512) >> 3) * 64 + (@mod(x, 512) >> 3));
}

/// Whether (x, y) in the world is in a room's 512 pixel square.
fn inRoom(room: i32, x: i32, y: i32) bool {
    const rx = (room & 15) * 512;
    const ry = (room >> 4) * 512;
    return x >= rx and x < rx + 512 and y >= ry and y < ry + 512;
}

/// Takes in the room's tiles for this frame, keeping the last room's when
/// it's just been left.
fn noteRoomWater(room: i32, bg1_shown: bool) void {
    if (room != g_room_water_id) {
        if (g_room_water_id >= 0) {
            g_left_water = g_room_water;
            g_left_water_id = g_room_water_id;
            g_left_overlay = g_overlay_water;
        }
        g_room_water_id = room;
    }
    for (&g_room_water, 0..) |*out, t| {
        const lo = vars.dung_bg2_attr_table[t];
        const a = dungeonAttr(lo, vars.dung_bg1_attr_table[t], bg1_shown);
        out.* = packRoomTile(.{ .attr = a.attr, .steps = a.steps, .upper = a.upper, .lower = waterDepth(lo) });
    }
}

/// Playing in a dungeon or cave, menus over it included, and while the
/// circle closes or opens on it going out or coming in.
fn inDungeonPlay() bool {
    var module = vars.main_module_index.*;
    if (module == 14) module = vars.saved_module_for_menu.*;
    return module == 7 or ((module == 15 or module == 16) and vars.player_is_indoors.* != 0);
}

/// Playing out in the world, menus over it included, and while the circle
/// closes or opens on it going in a door or coming back out.
fn inOverworldPlay() bool {
    var module = vars.main_module_index.*;
    if (module == 14) module = vars.saved_module_for_menu.*;
    return module == 9 or module == 11 or ((module == 15 or module == 16) and vars.player_is_indoors.* == 0);
}

/// Whether there's any falling water's foot on the screen, by the tiles
/// alone: a face of it right over deep water. A cliff that drops into water
/// looks the same here, which only costs a look at the frame.
fn outdoorWaterfallNear() bool {
    if (!inOverworldPlay()) return false;
    const cam_x: i32 = vars.BG2HOFS_copy2.*;
    const cam_y: i32 = vars.BG2VOFS_copy2.*;
    const reach: i32 = snes_pkg.ppu_types.kPpuExtraLeftRight;
    var y = cam_y & ~@as(i32, 7);
    while (y < cam_y + 224) : (y += 8) {
        var x = (cam_x - reach) & ~@as(i32, 7);
        while (x < cam_x + 256 + reach) : (x += 8) {
            if (overworldAttr(x, y) == kFallAttr and overworldAttr(x, y + 8) == kDeepWaterAttr) return true;
        }
    }
    return false;
}

/// The feet of the waterfalls on the frame just drawn, where the falling
/// water meets the deep water under it: a face of it right over deep water,
/// drawn in water's colors (not a cliff's browns). Along each, a spot every
/// 24 pixels or so for its mist.
fn findOutdoorWaterfalls(frame: Frame, left: i32, cam_x: i32, cam_y: i32) void {
    if (!inOverworldPlay()) return;
    var y = cam_y & ~@as(i32, 7);
    while (y < cam_y + @as(i32, @intCast(frame.height))) : (y += 8) {
        var run: i32 = 0;
        var x = (cam_x - left) & ~@as(i32, 7);
        const x_end = cam_x - left + @as(i32, @intCast(frame.width)) + 8;
        while (x <= x_end) : (x += 8) {
            const foot = x < x_end and overworldAttr(x, y) == kFallAttr and overworldAttr(x, y + 8) == kDeepWaterAttr and
                fallingWaterAt(frame, x + 4 - cam_x + left, y + 4 - cam_y);
            if (foot) {
                run += 1;
                continue;
            }
            if (run > 0) {
                // The run ended at x: spots spread along it.
                const start = x - run * 8;
                const n: i32 = @max(1, @divTrunc(run + 1, 3));
                var i: i32 = 0;
                while (i < n) : (i += 1) {
                    if (g_nspots == g_spots.len) return;
                    g_spots[g_nspots] = .{ .x = start + @divTrunc((2 * i + 1) * run * 8, 2 * n), .y = y + 8, .kind = .waterfall };
                    g_nspots += 1;
                }
                run = 0;
            }
        }
    }
}

/// Whether the frame's falling water at (x, y): bright blues and the white
/// of its foam, not a cliff's browns.
fn fallingWaterAt(frame: Frame, x: i32, y: i32) bool {
    const px = frame.at(x, y) orelse return false;
    const r = (px >> 16) & 0xff;
    const g = (px >> 8) & 0xff;
    const b = px & 0xff;
    const white = r >= 0xc8 and g >= 0xc8 and b >= 0xc8;
    return white or (b >= 0x90 and b >= r + 0x30);
}

/// How much of the night's light the storm leaves, for the lantern's pool to
/// stand out of.
pub const kStormAmbient: f32 = 0.85;

/// Outdoors in the storm: just Link's lantern, if he's got it, a warm pool
/// that lifts the night around him.
fn stormLights(ppu: *const Ppu, out: []Light) usize {
    if (vars.link_item_torch.* == 0 or out.len == 0) return 0;
    const f = flame(g_tick, 0, kLanternBurn);
    out[0] = .{
        .x = @as(f32, @floatFromInt(ppu.extraLeftRight)) + @as(f32, @floatFromInt(@as(i32, vars.link_x_coord.*) - @as(i32, vars.BG2HOFS_copy2.*) + 8)) + f.dx,
        .y = @as(f32, @floatFromInt(@as(i32, vars.link_y_coord.*) - @as(i32, vars.BG2VOFS_copy2.*) + 12)) + f.dy,
        .radius = 84 * f.reach,
        .color = flameColor(kLantern, 2.5, f.level),
        .glow_radius = 13 * f.reach,
        .glow = 0.4 * f.level,
    };
    return 1;
}

/// The lightning's flash on the CPU: the scene (not the HUD) washed toward
/// a cold white, `amount` of the way.
fn flashCpu(pixels: [*]u8, pitch: usize, width: usize, height: usize, amount: f32) void {
    const k: u32 = @intFromFloat(std.math.clamp(amount * kFlashStrength, 0, 1) * 256);
    const to = [3]u32{ 0xd8, 0xe6, 0xff };
    for (0..height) |y| {
        const mask = g_mask[y * kMaxWidth ..][0..width];
        const row: [*]align(1) u32 = @ptrCast(pixels + y * pitch);
        for (mask, 0..) |m, x| {
            if (m == 0) continue;
            const c = row[x];
            var out: u32 = 0;
            for (0..3) |ch| {
                const shift: u5 = @intCast(16 - ch * 8);
                const was = (c >> shift) & 0xff;
                const now = was + (((to[ch] -| was) * k) >> 8);
                out |= @as(u32, @min(now, 255)) << shift;
            }
            row[x] = out;
        }
    }
}

/// How far the flash washes the scene toward white at its brightest. The
/// game's own flash is strong already, and over in two frames; this is
/// mostly the afterglow, the cold light fading over the frames after.
pub const kFlashStrength: f32 = 0.3;

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
    if (f.water) noteWaterColors(pixels, pitch, f);
    // Tiles the game counts as water that are drawn as something else
    // entirely, like the pink clouds the Dark World's Death Mountain
    // floats over: nothing to redraw.
    if (f.water and g_nwater_colors == 0) f.water = false;
    if (f.water and f.indoors) markOutsideWater(pixels, pitch, f);
    if (f.lava) findLavaHeat(pixels, pitch, f);
    for (0..f.height) |y| {
        const row: [*]align(1) u32 = @ptrCast(pixels + y * pitch);
        const out = g_gpu_mask[y * f.width ..][0..f.width];
        const ty: usize = @intCast(@mod(@as(i32, @intCast(y)) + f.cam_y, 512) >> 3);
        const attrs = vars.dung_bg2_attr_table[ty * 64 ..][0..64];
        for (out, 0..) |*o, x| {
            const m = row[x] >> 24;
            row[x] &= 0xffffff;
            const tx: usize = @intCast(@mod(@as(i32, @intCast(x)) - f.left + f.cam_x, 512) >> 3);
            const solid: u32 = if (f.indoors) solidness(attrs[tx]) else 0;
            const water: u32 = if (f.water) waterAt(f, x, y, row[x], m != 0) else 0;
            // Alpha: 255 less the heat over lava (in even steps), and its
            // lowest bit clear for a sprite's pixel, for reflections.
            const cool: u32 = if (f.lava) 255 - (lavaHeatAt(f, x, y) & 0xfe) else 255;
            const sprite: u32 = @intFromBool(layerAt(y * kMaxWidth + x) == 4);
            o.* = (cool - sprite) << 24 | m << 16 | solid << 8 | water;
        }
    }
    f.nmirrors = if (f.water) findMirrors(f, f.mirrors[0..]) else 0;
    f.mask = g_gpu_mask[0 .. f.width * f.height];
    return f;
}

// ------------------------------------------------------------- HD water

/// The water on and around the screen, a tile at a time, as waterDepth
/// gives it, from the tile at (g_water_x0, g_water_y0) in the world, 8
/// pixel steps; and next to it, the deepest water in the tiles around.
const kWaterCols = kMaxWidth / 8 + 2;
const kWaterRows = kMaxHeight / 8 + 2;
var g_water: [kWaterRows][kWaterCols]u8 = undefined;
var g_water_near: [kWaterRows][kWaterCols]u8 = undefined;
/// Tiles past the area's edges, where its tile attributes don't reach: the
/// widescreen margins can show the area next door there, and the water in
/// it is found by its colors alone.
var g_water_outside: [kWaterRows][kWaterCols]bool = undefined;
/// Tiles of a waterfall's face (or a rock in the water, which shares its
/// attribute), where the dark blues are falling water, not the water's
/// shading along a shore.
var g_water_face: [kWaterRows][kWaterCols]bool = undefined;
/// Indoors, the tiles past the room's edges that are mostly drawn in the
/// water's colors (markOutsideWater).
var g_outside_wet: [kWaterRows][kWaterCols]bool = std.mem.zeroes([kWaterRows][kWaterCols]bool);
/// Indoors, tiles whose water is on the upper layer, BG1: water only where
/// BG1's actually blended in (a room can have the tiles without it drawn
/// over every one of them).
var g_water_upper: [kWaterRows][kWaterCols]bool = undefined;
/// Indoors, the depth of the water the lower layer's tiles say there is:
/// what a tile is where BG1 isn't blended in, whatever the upper's say.
var g_water_lower: [kWaterRows][kWaterCols]u8 = undefined;
var g_water_x0: i32 = 0;
var g_water_y0: i32 = 0;
/// There's water on the screen this frame for HD Water to work on.
var g_water_on = false;
/// Indoors, BG1 blended in over the floor is water this frame: wherever it
/// is, but on steps going into it (see scanWater).
var g_overlay_water = false;
/// The room's tiles say there's water on the screen: its colors are found
/// there, not in whatever else BG1 blends in.
var g_water_by_tiles = false;

/// The desert's heat shimmering over the picture this frame
/// (light_apply.frag), in place of anything drifting in its air.
var g_heat_on = false;

/// Whether the heat shimmers here: out in the desert, with particles on
/// and the GPU to draw it.
fn heatHaze() bool {
    return g_gpu and particles.enabled() and particles.ambienceHere() == .heat;
}

// ------------------------------------------------------- shockwaves

/// A blast's shockwave: a ring of bent air spreading out from where it went
/// off, pushing the picture outward as it passes (light_apply.frag), fading
/// as it grows.
const Shock = struct {
    x: i32,
    y: i32,
    /// Game frames since it went off, and how many it lasts.
    age: u16 = 0,
    life: u16,
    /// How far it spreads, in SNES pixels, and how far it pushes the
    /// picture at first.
    reach: f32,
    push: f32,
};

pub const kMaxShocks = 6;
var g_shocks: [kMaxShocks]Shock = undefined;
var g_nshocks: usize = 0;
/// There's a shockwave on its way out this frame.
var g_shock_on = false;
/// What each of Link's things was on the frame before, to see a blast the
/// moment it goes off.
const Seen = struct { kind: u8 = 0, stage: u8 = 0 };
var g_shock_seen: [10]Seen = @splat(.{});
/// What each half of a blown wall's blasts was on the frame before.
var g_wall_seen: [2]u8 = .{ 0, 0 };

const kBombShock = Shock{ .x = 0, .y = 0, .life = 22, .reach = 64, .push = 3.5 };
const kWallShock = Shock{ .x = 0, .y = 0, .life = 24, .reach = 72, .push = 3.2 };
const kBigShock = Shock{ .x = 0, .y = 0, .life = 34, .reach = 120, .push = 5 };
const kVaneShock = Shock{ .x = 0, .y = 0, .life = 30, .reach = 96, .push = 4.5 };
const kQuakeShock = Shock{ .x = 0, .y = 0, .life = 52, .reach = 210, .push = 6 };

/// Whether blasts send out shockwaves: with particles on. (They're drawn
/// only on a GPU, which bends the picture.)
fn shockwaves() bool {
    return particles.enabled();
}

fn addShock(kind: Shock, x: i32, y: i32) void {
    var s = kind;
    s.x = x;
    s.y = y;
    if (g_nshocks == kMaxShocks) {
        // The oldest gives way.
        var oldest: usize = 0;
        for (g_shocks[0..g_nshocks], 0..) |o, i| {
            if (o.age > g_shocks[oldest].age) oldest = i;
        }
        g_shocks[oldest] = s;
        return;
    }
    g_shocks[g_nshocks] = s;
    g_nshocks += 1;
}

/// Once a game frame: ages the shockwaves on their way, and starts new ones
/// for whatever's just gone off: a bomb, a super bomb, the weathervane,
/// each burst of a wall being blown open, the Quake medallion.
pub fn stepShocks() void {
    var n: usize = 0;
    for (g_shocks[0..g_nshocks]) |s| {
        var t = s;
        t.age += 1;
        if (t.age >= t.life) continue;
        g_shocks[n] = t;
        n += 1;
    }
    g_nshocks = n;

    const on = shockwaves();
    for (0..10) |k| {
        const kind = vars.ancilla_type[k];
        // How far along it is: for the weathervane, whether it's blown yet
        // (it waits a long while first); for anything else, its frame.
        const stage = if (kind == 0x37) vars.ancilla_arr3[k] else vars.ancilla_item_to_link[k];
        const was = g_shock_seen[k];
        g_shock_seen[k] = .{ .kind = kind, .stage = stage };
        if (!on) continue;
        const ax: i32 = @as(i32, vars.ancilla_x_lo[k]) | @as(i32, vars.ancilla_x_hi[k]) << 8;
        const ay: i32 = @as(i32, vars.ancilla_y_lo[k]) | @as(i32, vars.ancilla_y_hi[k]) << 8;
        const fresh = was.kind != kind;
        const went_off = stage != 0 and (fresh or was.stage == 0);
        switch (kind) {
            // A bomb, the moment its fuse runs out. Its blast is drawn
            // centered on where it is, as a super bomb's is.
            0x07 => if (went_off) addShock(kBombShock, ax, ay),
            0x3a => if (fresh) addShock(kBigShock, ax, ay),
            // The weathervane, from the middle of the splinters it flies
            // apart into.
            0x37 => if (went_off) {
                var sx: i32 = 0;
                var sy: i32 = 0;
                for (0..12) |i| {
                    sx += @as(i32, vars.weathervane_arr8[i]) | @as(i32, vars.weathervane_arr9[i]) << 8;
                    sy += @as(i32, vars.weathervane_arr6[i]) | @as(i32, vars.weathervane_arr7[i]) << 8;
                }
                addShock(kVaneShock, @divTrunc(sx, 12), @divTrunc(sy, 12));
            },
            // Quake: the ground heaving out from Link.
            0x1c => if (fresh) addShock(kQuakeShock, @as(i32, vars.link_x_coord.*) + 8, @as(i32, vars.link_y_coord.*) + 12),
            else => {},
        }
    }

    // A wall being blown open goes off in bursts of four blasts, two sides
    // taking turns; a ring from the middle of each burst.
    const blowing = vars.ancilla_type[0] == 0x33;
    for (0..2) |u| {
        const stage = if (blowing) vars.blastwall_var5[u] else 0;
        const was = g_wall_seen[u];
        g_wall_seen[u] = stage;
        if (!on or stage == 0 or was != 0) continue;
        var sx: i32 = 0;
        var sy: i32 = 0;
        for (0..4) |i| {
            sx += vars.blastwall_var11[u * 4 + i];
            sy += vars.blastwall_var10[u * 4 + i];
        }
        addShock(kWallShock, @divTrunc(sx, 4), @divTrunc(sy, 4));
    }
    if (!on) g_nshocks = 0;
}

/// The shockwaves as light_apply.frag takes them: where each started in the
/// world, how far its ring's spread, and how hard it still pushes, eased
/// out as it grows (and gentler with Dim Flashes on).
fn packShocks(f: *GpuFrame) void {
    const gentle: f32 = if (dimFlashes()) 0.5 else 1;
    for (g_shocks[0..g_nshocks], 0..) |s, i| {
        const a = @as(f32, @floatFromInt(s.age)) / @as(f32, @floatFromInt(s.life));
        const left = 1 - a;
        f.shocks[i] = .{
            @floatFromInt(s.x),
            @floatFromInt(s.y),
            s.reach * (1 - left * left * left),
            s.push * gentle * left * @sqrt(left),
        };
    }
    f.nshocks = g_nshocks;
}

// ------------------------------------------------------- reflections

pub const kMaxMirrors = 8;

/// Link and the sprites standing in the water or at its edge, to be
/// reflected in it (light_apply.frag): each one's extent on the frame, as
/// its pixels show it, its feet the line it's mirrored about. Up to
/// `out.len` of them.
fn findMirrors(f: *const GpuFrame, out: [][4]f32) usize {
    var n: usize = 0;
    const ox = f.left - f.cam_x;
    const oy = -f.cam_y;
    // Link first: the one most worth seeing.
    n += mirrorAt(f, @as(i32, vars.link_x_coord.*) + ox, @as(i32, vars.link_y_coord.*) + oy, out[n..]);
    for (0..16) |k| {
        if (n == out.len) break;
        if (vars.sprite_state[k] == 0) continue;
        const sx: i32 = @as(i32, vars.sprite_x_lo[k]) | @as(i32, vars.sprite_x_hi[k]) << 8;
        const sy: i32 = (@as(i32, vars.sprite_y_lo[k]) | @as(i32, vars.sprite_y_hi[k]) << 8) - vars.sprite_z[k];
        n += mirrorAt(f, sx + ox, sy + oy, out[n..]);
    }
    return n;
}

/// The sprite drawn round (x, y) on the frame, its 16 pixel square's
/// corner, if its feet are in the water or just above it: 1 if it's put in
/// `out`, 0 otherwise.
fn mirrorAt(f: *const GpuFrame, x: i32, y: i32, out: [][4]f32) usize {
    if (out.len == 0) return 0;
    var x0: i32 = std.math.maxInt(i32);
    var x1: i32 = -1;
    var top: i32 = std.math.maxInt(i32);
    var base: i32 = -1;
    var py = @max(y - 14, 0);
    while (py < @min(y + 26, @as(i32, @intCast(f.height)))) : (py += 1) {
        var px = @max(x - 4, 0);
        while (px < @min(x + 20, @as(i32, @intCast(f.width)))) : (px += 1) {
            if (layerAt(@as(usize, @intCast(py)) * kMaxWidth + @as(usize, @intCast(px))) != 4) continue;
            x0 = @min(x0, px);
            x1 = @max(x1, px);
            top = @min(top, py);
            base = @max(base, py);
        }
    }
    if (base < 0 or base - top < 4) return 0;
    // Feet in the water, or the water just below them.
    const cx: usize = @intCast(@divTrunc(x0 + x1, 2));
    var wet = false;
    var wy = base - 4;
    while (wy <= base + 6) : (wy += 2) {
        if (wy < 0 or wy >= f.height) continue;
        const t = waterTile(f, cx, @intCast(wy));
        if (t.depth != 0) wet = true;
    }
    if (!wet) return 0;
    out[0] = .{ @floatFromInt(x0), @floatFromInt(x1 + 1), @as(f32, @floatFromInt(base)) + 1, @floatFromInt(top) };
    return 1;
}

// ------------------------------------------------------- lava shimmer

/// The air over lava, a tile at a time on and around the screen, from the
/// tile at (g_lava_x0, g_lava_y0) in the room: 255 over the lava itself,
/// cooling with height above it and to its sides.
var g_lava_heat: [kWaterRows][kWaterCols]u8 = undefined;
var g_lava_x0: i32 = 0;
var g_lava_y0: i32 = 0;

/// Whether the air shimmers over lava this frame: indoors, with lava on the
/// screen (refreshSpots found it), particles on and the GPU to draw it.
fn lavaShimmer() bool {
    if (!g_gpu or !particles.enabled() or vars.player_is_indoors.* == 0) return false;
    for (g_spots[0..g_nspots]) |spot| {
        if (spot.kind == .lava) return true;
    }
    return false;
}

/// Finds the lava tiles on the frame, a pit's floor drawn in lava's colors,
/// and how hot the air is in the tiles around them: hot right over it,
/// cooling over the three tiles above and fading to the sides.
fn findLavaHeat(pixels: [*]const u8, pitch: usize, f: *const GpuFrame) void {
    const wx0 = f.cam_x - f.left;
    g_lava_x0 = @divFloor(wx0, 8);
    g_lava_y0 = @divFloor(f.cam_y, 8);
    const cols: usize = @min(kWaterCols, (f.width + 15) / 8);
    const rows: usize = @min(kWaterRows, (f.height + 15) / 8);
    var lava: [kWaterRows][kWaterCols]bool = undefined;
    for (0..rows) |ty| {
        for (0..cols) |tx| {
            lava[ty][tx] = false;
            const wx = (g_lava_x0 + @as(i32, @intCast(tx))) * 8;
            const wy = (g_lava_y0 + @as(i32, @intCast(ty))) * 8;
            const t: usize = @intCast((@mod(wy, 512) >> 3) * 64 + (@mod(wx, 512) >> 3));
            if (vars.dung_bg2_attr_table[t] != kPitAttr and vars.dung_bg1_attr_table[t] != kPitAttr) continue;
            // A few of the tile's pixels, any of them lava colored.
            for ([_][2]i32{ .{ 2, 2 }, .{ 5, 2 }, .{ 2, 5 }, .{ 5, 5 } }) |o| {
                const sx = wx + o[0] - wx0;
                const sy = wy + o[1] - f.cam_y;
                if (sx < 0 or sy < 0 or sx >= f.width or sy >= f.height) continue;
                const row: [*]align(1) const u32 = @ptrCast(pixels + @as(usize, @intCast(sy)) * pitch);
                const px = row[@intCast(sx)];
                if (px >> 24 != 0 and looksLikeLava(px & 0xffffff)) {
                    lava[ty][tx] = true;
                    break;
                }
            }
        }
    }
    for (0..rows) |ty| {
        for (0..cols) |tx| {
            var hot: f32 = 0;
            var dy: usize = 0;
            while (dy <= 3) : (dy += 1) {
                const ly = ty + dy;
                if (ly >= rows) break;
                for ([_]i32{ -1, 0, 1 }) |dx| {
                    const lx = @as(i32, @intCast(tx)) + dx;
                    if (lx < 0 or lx >= cols or !lava[ly][@intCast(lx)]) continue;
                    const h = 1 - 0.22 * @as(f32, @floatFromInt(dy)) - 0.45 * @as(f32, @floatFromInt(@abs(dx)));
                    hot = @max(hot, h);
                }
            }
            g_lava_heat[ty][tx] = @intFromFloat(hot * 255);
        }
    }
}

/// How hot the air is at pixel (x, y) of the frame, 0 to 255, read smoothly
/// between the tiles' middles so the shimmer has no edges.
fn lavaHeatAt(f: *const GpuFrame, x: usize, y: usize) u32 {
    const fx = @as(f32, @floatFromInt(@as(i32, @intCast(x)) + f.cam_x - f.left - g_lava_x0 * 8)) / 8 - 0.5;
    const fy = @as(f32, @floatFromInt(@as(i32, @intCast(y)) + f.cam_y - g_lava_y0 * 8)) / 8 - 0.5;
    const ix0: usize = @intFromFloat(@max(0, @floor(fx)));
    const iy0: usize = @intFromFloat(@max(0, @floor(fy)));
    const ix1 = @min(ix0 + 1, kWaterCols - 1);
    const iy1 = @min(iy0 + 1, kWaterRows - 1);
    const ax = std.math.clamp(fx - @as(f32, @floatFromInt(ix0)), 0, 1);
    const ay = std.math.clamp(fy - @as(f32, @floatFromInt(iy0)), 0, 1);
    const h = std.math.lerp(
        std.math.lerp(@as(f32, @floatFromInt(g_lava_heat[iy0][ix0])), @as(f32, @floatFromInt(g_lava_heat[iy0][ix1])), ax),
        std.math.lerp(@as(f32, @floatFromInt(g_lava_heat[iy1][ix0])), @as(f32, @floatFromInt(g_lava_heat[iy1][ix1])), ax),
        ay,
    );
    return @intFromFloat(h);
}

/// The colors the water's drawn in this frame, found in its full tiles,
/// so its edge can be followed pixel by pixel through the tiles along the
/// shore, which are part water and part land.
var g_water_colors: [16]u32 = undefined;
var g_nwater_colors: usize = 0;
/// Frames since each was last seen filling the water. A color stays a
/// while after, so the water's edge doesn't flicker as the game cycles its
/// colors from frame to frame.
var g_water_color_age: [16]u16 = undefined;
const kWaterColorKeep = 120;

pub fn hdWater() bool {
    return config.g_config.hd_water and g_gpu;
}

/// 2 for deep water, 1 for shallow, 0 for anything else, by a tile's
/// attribute, as the game's tile detection reads them.
pub fn waterDepth(attr: u8) u8 {
    return switch (attr) {
        0x08 => 2,
        0x09 => 1,
        else => 0,
    };
}

/// Looks over the tiles on the screen for water (outdoors, for now),
/// filling in g_water. Whether there's any.
fn scanWater(left: i32) bool {
    if (!hdWater()) return false;    const indoors = vars.player_is_indoors.* != 0;
    if (indoors) {
        if (!inDungeonPlay()) return false;
    } else {
        if (!inOverworldPlay()) return false;
        if (onDeathMountain(@truncate(vars.overworld_screen_index.*))) return false;
    }
    const cam_x: i32 = vars.BG2HOFS_copy2.*;
    const cam_y: i32 = vars.BG2VOFS_copy2.*;
    g_water_x0 = ((cam_x - left) >> 3) - 1;
    g_water_y0 = (cam_y >> 3) - 1;
    const b = vars.ow_scroll_vars0.*;
    // Indoors, the room whose tiles' attributes are loaded, kept for its
    // 512 pixel square; past it (the widescreen margins can show the room
    // next door) they'd wrap round to its far side. That's the room the
    // game's on, which on the way from one room to the next is already the
    // next one, Link not yet in it.
    const room_index: i32 = vars.dungeon_room_index.*;
    // BG1 on either screen: Swamp Palace's water, once it's let in.
    const bg1_shown = (vars.TM_copy.* | vars.TS_copy.*) & 1 != 0;
    var attrs: [kWaterRows][kWaterCols]u8 = undefined;
    var any = false;
    var upper = false;
    var any_outside = false;
    if (indoors) noteRoomWater(room_index, bg1_shown);
    for (0..kWaterRows) |r| for (0..kWaterCols) |col| {
        const wx = (g_water_x0 + @as(i32, @intCast(col))) * 8;
        const wy = (g_water_y0 + @as(i32, @intCast(r))) * 8;
        const in_room = if (indoors) inRoom(room_index, wx, wy) else !(wx < b.xstart or wx >= @as(i32, b.xend) + 256 or wy < b.ystart or wy >= @as(i32, b.yend) + 224);
        // On the way to the next room, the one being left as its tiles
        // last were, so its water doesn't change as the room does.
        const in_left = indoors and !in_room and g_left_water_id >= 0 and inRoom(g_left_water_id, wx, wy);
        const outside = !in_room and !in_left;
        g_water_outside[r][col] = outside;
        g_water_left[r][col] = in_left;
        any_outside = any_outside or outside;
        const room: ?RoomTile = if (!indoors or outside) null else unpackRoomTile((if (in_room) &g_room_water else &g_left_water)[roomTileIndex(wx, wy)]);
        const attr: u8 = if (outside) 0 else if (room) |a| a.attr else overworldAttr(wx, wy);
        attrs[r][col] = attr;
        g_water[r][col] = waterDepth(attr);
        // Indoors 0x02 is something else altogether; there, it's steps
        // going down into the water instead.
        g_water_face[r][col] = if (room) |a| a.steps else !indoors and attr == kFallFace;
        if (room) |a| upper = upper or (a.upper and in_room);
        g_water_upper[r][col] = if (room) |a| a.upper and !a.steps else false;
        g_water_lower[r][col] = if (room) |a| a.lower else 0;
    };
    // Down the middle of a waterfall the game marks a strip as shallow
    // water, between the face's own tiles on either side: it's the falls,
    // drawn as falling water, not a lake to redraw.
    for (0..kWaterRows) |r| for (0..kWaterCols) |col| {
        if (!indoors and attrs[r][col] == 0x09 and fallsBeside(&attrs[r], col)) g_water[r][col] = 0;
        any = any or g_water[r][col] != 0;
    };
    // Swamp Palace's kind of water, on BG1 blended in over the floor: where
    // the upper layer's tiles say there's water, or where some water's just
    // been let in (the dam's lever pulled), which the room's tiles don't
    // say till it's next entered. Plenty of rooms blend BG1 in for other
    // things.
    g_overlay_water = indoors and vars.TS_copy.* & 1 != 0 and
        (upper or vars.dung_savegame_state_bits.* & 0x800 != 0);
    g_water_by_tiles = any;
    if (g_overlay_water) any = true;
    // On the way from one room to the next, the one being left has no
    // tiles to go on any more: its water's found by the colors it was just
    // seen in, while they're still remembered.
    if (indoors and any_outside and g_nwater_colors != 0) any = true;
    if (!any) return false;
    for (0..kWaterRows) |r| for (0..kWaterCols) |col| {
        var near: u8 = 0;
        for (@max(r, 1) - 1..@min(r + 2, kWaterRows)) |rr| for (@max(col, 1) - 1..@min(col + 2, kWaterCols)) |cc| {
            near = @max(near, g_water[rr][cc]);
        };
        g_water_near[r][col] = near;
    };
    return true;
}

/// Death Mountain, Light World and Dark: no water up there, though the game
/// counts the clouds the Dark World's floats over as water, and flashes
/// them cyan with each strike of its lightning, as blue as any lake.
pub fn onDeathMountain(area: u8) bool {
    return switch (area) {
        0x03, 0x05, 0x07, 0x43, 0x45, 0x47 => true,
        else => false,
    };
}

/// The attribute of a waterfall's face.
const kFallFace = 0x02;

/// Whether the tile at `col` in a row of attributes has a waterfall's face
/// within a couple of tiles on both sides of it.
pub fn fallsBeside(row: []const u8, col: usize) bool {
    var left = false;
    var right = false;
    for (1..3) |d| {
        if (col >= d and row[col - d] == kFallFace) left = true;
        if (col + d < row.len and row[col + d] == kFallFace) right = true;
    }
    return left and right;
}

/// The water tile under pixel (x, y) of the frame, and the deepest around
/// it.
fn waterTile(f: *const GpuFrame, x: usize, y: usize) struct { depth: u8, near: u8, outside: bool = false, face: bool = false, upper: bool = false, left: bool = false } {
    const tx = ((@as(i32, @intCast(x)) - f.left + f.cam_x) >> 3) - g_water_x0;
    const ty = ((@as(i32, @intCast(y)) + f.cam_y) >> 3) - g_water_y0;
    if (tx < 0 or ty < 0 or tx >= kWaterCols or ty >= kWaterRows) return .{ .depth = 0, .near = 0 };
    const c: usize = @intCast(tx);
    const r: usize = @intCast(ty);
    // Past the area's edges, any water's as good as deep and near. Past a
    // room's, a tile's water if it's mostly in the water's colors: its
    // walls and floors share some of them.
    if (g_water_outside[r][c]) {
        if (f.indoors) return .{ .depth = if (g_outside_wet[r][c]) 2 else 0, .near = 0, .outside = true };
        return .{ .depth = 0, .near = 2, .outside = true };
    }
    if (f.indoors and g_water[r][c] == 0 and g_outside_wet[r][c]) return .{ .depth = 2, .near = 2 };
    // Upper-layer water, and steps going down into it, only where BG1's
    // blended in: elsewhere what the lower layer's tiles say (on the way
    // into a room the upper's can still be the last room's).
    const upper = g_water_upper[r][c];
    if (f.indoors and (upper or g_water_face[r][c]) and !bg1Underneath(y * kMaxWidth + x)) {
        const lower = g_water_lower[r][c];
        return .{ .depth = lower, .near = @max(lower, g_water_near[r][c]) };
    }
    return .{ .depth = g_water[r][c], .near = g_water_near[r][c], .face = g_water_face[r][c], .upper = upper, .left = g_water_left[r][c] };
}

/// Whether the pixel at (x, y) is a background's: a sprite over the water
/// (Link swimming, a Zora) is left alone.
fn backgroundAt(f: *const GpuFrame, x: usize, y: usize) bool {
    _ = f;
    return layerAt(y * kMaxWidth + x) <= 1;
}

/// Whether a color is cool enough to be water's: bluer or greener than it is
/// red, by a margin. Hyrule's water always is, blue in the Light World and
/// green in the Dark World's swamps; the clouds over the Dark World's Death
/// Mountain, on tiles the game counts as water, are pink.
pub fn coolEnough(px: u32) bool {
    const r = (px >> 16) & 0xff;
    const cool = @max((px >> 8) & 0xff, px & 0xff);
    // And not so dark it's the rim round a pool rather than the water.
    return cool >= r + 0x10 and cool >= 0x50;
}

/// Indoors, which tiles the room's tiles don't call water are water all the
/// same, three quarters of their pixels on the frame in the water's own
/// colors: past the room's edges (the room being left, on the way to the
/// next), and beside the water, where the next room's tiles are still
/// coming in on the way into it. Never steps going into it.
fn markOutsideWater(pixels: [*]const u8, pitch: usize, f: *const GpuFrame) void {
    for (0..kWaterRows) |r| for (0..kWaterCols) |c| {
        g_outside_wet[r][c] = false;
        const beside = g_water[r][c] == 0 and g_water_near[r][c] != 0 and !g_water_face[r][c];
        if (!g_water_outside[r][c] and !beside) continue;
        const x0 = (g_water_x0 + @as(i32, @intCast(c))) * 8 - f.cam_x + f.left;
        const y0 = (g_water_y0 + @as(i32, @intCast(r))) * 8 - f.cam_y;
        var seen: u32 = 0;
        var wet: u32 = 0;
        var y = @max(y0, 0);
        while (y < @min(y0 + 8, @as(i32, @intCast(f.height)))) : (y += 1) {
            const row: [*]align(1) const u32 = @ptrCast(pixels + @as(usize, @intCast(y)) * pitch);
            var x = @max(x0, 0);
            while (x < @min(x0 + 8, @as(i32, @intCast(f.width)))) : (x += 1) {
                seen += 1;
                if (isWaterColor(row[@intCast(x)] & 0xffffff)) wet += 1;
            }
        }
        g_outside_wet[r][c] = seen >= 16 and wet * 4 >= seen * 3;
    };
}

/// Gathers the colors the full water tiles are drawn in: the ones that fill
/// stretches of them, however small a share of the screen, and not the
/// thin crests of the waves drawn over them a pixel tall, which mostly
/// have other colors around them.
fn noteWaterColors(pixels: [*]u8, pitch: usize, f: *const GpuFrame) void {
    var colors: [32]u32 = undefined;
    var counts: [32]u32 = undefined;
    var filled: [32]u32 = undefined;
    var n: usize = 0;
    var total: u32 = 0;
    var y: usize = 0;
    // Every other row and column is plenty to see what they're made of.
    while (y < f.height) : (y += 2) {
        const row: [*]align(1) const u32 = @ptrCast(pixels + y * pitch);
        var x: usize = 0;
        while (x < f.width) : (x += 2) {
            const over = g_overlay_water and !g_water_by_tiles and bg1Underneath(y * kMaxWidth + x) and !waterTile(f, x, y).face;
            const t = waterTile(f, x, y);
            if (row[x] >> 24 == 0 or t.outside or (t.depth == 0 and !over) or !backgroundAt(f, x, y)) continue;
            const px = row[x] & 0xffffff;
            total += 1;
            const k = for (colors[0..n], 0..) |col, i| {
                if (col == px) break i;
            } else blk: {
                if (n == colors.len) break :blk null;
                colors[n] = px;
                counts[n] = 0;
                filled[n] = 0;
                n += 1;
                break :blk n - 1;
            };
            if (k) |i| {
                counts[i] += 1;
                // The same color a pixel below and beside it: a stretch of
                // it, not a line.
                if (y + 1 < f.height and x + 1 < f.width) {
                    const below: [*]align(1) const u32 = @ptrCast(pixels + (y + 1) * pitch);
                    if (below[x] & 0xffffff == px and row[x + 1] & 0xffffff == px) filled[i] += 1;
                }
            }
        }
    }
    for (g_water_color_age[0..g_nwater_colors]) |*age| age.* +|= 1;
    for (colors[0..n], counts[0..n], filled[0..n]) |col, cnt, fill| {
        // Even the water's rarer colors; but only what fills, and only
        // what's cool enough to be water. Indoors the water's a busy,
        // dithered pattern that fills nothing: any blue that's a fair share
        // of it is its own.
        const enough = if (f.indoors) cnt * 40 >= total else cnt * 500 >= total and fill * 2 >= cnt;
        if (!enough or !coolEnough(col)) continue;
        const k = for (g_water_colors[0..g_nwater_colors], 0..) |w, i| {
            if (w == col) break i;
        } else blk: {
            if (g_nwater_colors < g_water_colors.len) {
                g_nwater_colors += 1;
                break :blk g_nwater_colors - 1;
            }
            // Full: the one gone longest makes way.
            break :blk std.mem.indexOfMax(u16, &g_water_color_age);
        };
        g_water_colors[k] = col;
        g_water_color_age[k] = 0;
    }
    // Those not seen in a while go.
    var i: usize = 0;
    while (i < g_nwater_colors) {
        if (g_water_color_age[i] > kWaterColorKeep) {
            g_nwater_colors -= 1;
            g_water_colors[i] = g_water_colors[g_nwater_colors];
            g_water_color_age[i] = g_water_color_age[g_nwater_colors];
        } else i += 1;
    }
}

/// Whether `px` is one of the water's colors, or near enough: a tile with
/// something on it may draw the water around it in a palette of its own.
fn isWaterColor(px: u32) bool {
    for (g_water_colors[0..g_nwater_colors]) |w| {
        if (colorNear(px, w, 20)) return true;
    }
    return false;
}

/// Plainly blue, the way water is drawn: blue well over red, and over green.
pub fn looksLikeWater(px: u32) bool {
    const r = (px >> 16) & 0xff;
    const g = (px >> 8) & 0xff;
    const b = px & 0xff;
    return b >= 0x60 and b >= r + 0x30 and b >= g + 0x10;
}

/// A pale, bright blue, lighter than water: a shore's light outline, the
/// crest of a wave.
fn isPaleBlue(px: u32) bool {
    return (px >> 8) & 0xff >= 0xa0 and px & 0xff >= 0xe0;
}

/// Pale, near white: spray, foam, the light on falling water.
fn isLight(px: u32) bool {
    return (px >> 16) & 0xff >= 0xa0 and (px >> 8) & 0xff >= 0xa0 and px & 0xff >= 0xa0;
}

fn isWaterColorExactly(px: u32) bool {
    for (g_water_colors[0..g_nwater_colors]) |w| {
        if (w == px & 0xffffff) return true;
    }
    return false;
}

fn colorNear(a: u32, b: u32, tolerance: u32) bool {
    inline for (.{ 0, 8, 16 }) |shift| {
        const x = (a >> shift) & 0xff;
        const y = (b >> shift) & 0xff;
        if (@max(x, y) - @min(x, y) > tolerance) return false;
    }
    return true;
}

/// The mask's blue for pixel (x, y), drawn `px`: how deep the water is
/// there, 0 for none, odd where it's in the water's own colors and even
/// where it's some speck on it, which light_apply.frag leaves out of the
/// water's blended color. In a water tile it's all water; in a tile next
/// to one, the pixels in the water's colors are. Something over the water,
/// a sprite or the HUD, is 2: not water itself, but not the shore either.
fn waterAt(f: *const GpuFrame, x: usize, y: usize, px: u32, scene: bool) u32 {
    var t = waterTile(f, x, y);
    // Indoors, BG1 blended in underneath is water lying over the floor,
    // wherever the tiles say (Swamp Palace's canals) or not (the water the
    // dam lets through, below its gate): all but steps going into it.
    const overlay = if (t.left) g_left_overlay else g_overlay_water;
    if (overlay and !t.outside and !t.face and bg1Underneath(y * kMaxWidth + x) and isWaterColor(px)) t.depth = @max(t.depth, 2);
    if (!scene) return if (t.depth != 0) 2 else 0;
    // A sprite drawn with the water's own color behind it (a lily pad) is
    // water there; the rest of it, and every other sprite, is left be.
    if (!backgroundAt(f, x, y)) return if (t.depth == 0) 0 else if (isWaterColorExactly(px)) t.depth * 100 + 1 else 2;
    // Past the area's edges there's nothing to go on but the picture: what's
    // plainly blue is water. Beside it, so is a darker blue, the water's
    // shading along a shore, except on a waterfall's face.
    const clean = isWaterColor(px);
    // Indoors, past the room's edges, only the water's own colors: its
    // floors and walls are bluish enough to pass for water otherwise.
    const watery = clean or (!f.indoors and looksLikeWater(px) and (t.outside or (!t.face and !isPaleBlue(px))));
    // Indoors the water fills its tiles whole, and what's next to it in
    // the same colors (steps going down into it) isn't water: the tiles
    // alone say, but past the room's edges, where there are none.
    const by_tile = f.indoors and !t.outside;
    // And in its tiles, the dark rim round a pool isn't water either; nor
    // in the tiles of the room being left, found by their colors, so the
    // water's edge doesn't jump as the room changes.
    const in_water = t.depth != 0 and (!f.indoors or clean or looksLikeWater(px));
    const depth = if (in_water) t.depth else if (t.near != 0 and watery and !by_tile) t.near else 0;
    // See-through water, BG1 blended in over the floor (Swamp Palace's),
    // is 200: what's under it shows through it. Water drawn in its own
    // tiles is redrawn whole.
    const see_through = f.indoors and bg1Underneath(y * kMaxWidth + x);
    const v: u32 = if (depth != 0 and see_through) 200 else switch (depth) {
        2 => 254,
        1 => 140,
        // Something pale or blue that isn't the water's own colors (a
        // waterfall, the lip it pours over, the shore's light outline) is
        // left as drawn, and is no shore for the foam, which would trace
        // its tiles' straight edges.
        else => return if (looksLikeWater(px) or isLight(px)) 2 else 0,
    };
    // Only the water's own colors, exactly, count toward its blended color;
    // specks on it (the waves' crests, rocks) and the shading along a shore
    // are drawn over by it but don't.
    return v | @intFromBool(isWaterColorExactly(px));
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

    // The light Link carries, a little out in front of him as the game's
    // cone is. The game shows its cone in a dark room whether he's found the
    // lantern or not (the lantern lights torches), so it's lit by the cone.
    if (g_mode == .dark and dungeon_wide.coneUp()) {
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

    var add = Adder{ .out = out, .n = n, .tick = tick, .left = left, .cam_x = cam_x, .cam_y = cam_y };

    // Game over: nothing of the room's is drawn any more but Link, and the
    // slots for everything else hold whatever they last did. A fairy out of
    // a bottle, though, flies round him and brings him back: the first
    // ancilla's place, its height above it (RevivalFairy_Main), until it's
    // flown off the screen.
    if (vars.main_module_index.* == 18) {
        const sub = vars.submodule_index.*;
        if (sub >= 11 and sub <= 14 and vars.ancilla_step[0] < 3) {
            const fx: i32 = @as(i32, vars.ancilla_x_lo[0]) | @as(i32, vars.ancilla_x_hi[0]) << 8;
            const fy: i32 = @as(i32, vars.ancilla_y_lo[0]) | @as(i32, vars.ancilla_y_hi[0]) << 8;
            add.world(kFairy, fx + 8, fy + 8 - @as(i32, vars.ancilla_z[0]), 0x10000, 1);
        }
        return add.n;
    }

    // The room's fixed fires, the torches, braziers and sconces' candles, as
    // refreshSpots found them and saw them burning on this frame, and its
    // warp tiles, glowing in their own color.
    for (g_spots[0..g_nspots]) |spot| {
        const seed: u32 = 0x50000 +% (@as(u32, @bitCast(spot.x)) *% 73856093 ^ @as(u32, @bitCast(spot.y)) *% 19349663);
        switch (spot.kind) {
            .candle => add.world(kCandle, spot.x, spot.y, seed, 1),
            .warp => add.worldColored(kWarp, spot.x, spot.y, seed, spot.color),
            .lava => add.world(kLava, spot.x, spot.y, seed, spot.amount),
            // A waterfall gives off mist (particles.zig), not light.
            .waterfall => {},
            else => add.world(kTorch, spot.x, spot.y, seed, 1),
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
            0x0d, 0x16, 0x1b, 0x06, 0x26, 0x2a, 0x3b => add.world(kTinySpark, ax + 4, ay + 4, seed, 1),
            // The twinkles a charging sword, a silver arrow or a falling
            // crystal sheds: each one stays put for its three frames while
            // what shed it moves on, so faint, and fading as it goes, or
            // their glow trails behind a falling crystal like a smear.
            0x3c => add.world(kTinySpark, ax + 4, ay + 4, seed, 0.5 - 0.15 * @as(f32, @floatFromInt(@min(vars.ancilla_item_to_link[k], 2)))),
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
                if (stage != 0) add.world(kBlast, ax, ay, seed, fade(stage, 11));
            },
            // Blown-open walls.
            0x0e, 0x0f, 0x10, 0x12, 0x33 => add.world(kBlast, ax + 8, ay + 8, seed, 0.8),
            0x3a => add.world(kBigBlast, ax, ay, seed, 1),
            // A rising crystal.
            0x3e => add.world(kFairy, ax + 8, ay + 8, seed, 1),
            // Treasure held up: out of a chest, from someone, from a pond.
            0x22, 0x28 => add.world(kTreasure, ax + 8, ay + 8, seed, 1),
            // A pendant or crystal coming down out of the air once the boss
            // is beaten (drawn its height above where it'll land), and the
            // Master Sword.
            0x29 => if (milestoneShown(k))
                add.world(kMilestone, ax + 8, ay + 8 - @as(i32, vars.ancilla_z[k]), seed, 1),
            0x35 => add.world(kMilestone, ax + 8, ay + 8, seed, 1),
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
            // Sparks that run along the walls, Mothula's beam.
            0x5b, 0x5c => add.world(kElectric, sx + 8, sy + 8, seed, 1),
            // A bolt of Agahnim's or Vitreous's lightning: the room lit
            // from it, hard and cold, the walls throwing their shadows away
            // from where it strikes.
            0xbf => add.world(kBolt, sx + 8, sy + 8, seed, boltAmount()),
            0x89 => add.world(kSpark, sx + 8, sy + 8, seed, 1),
            // Baris hum faintly.
            0x23, 0x24 => add.world(kBari, sx + 8, sy + 8, seed, 1),
            // Agahnim's magic, in the colors it's drawn in.
            0x7b => add.worldColored(kMagic, sx + 8, sy + 8, seed, spriteHue(ppu, vars.sprite_oam_flags[k])),
            // The bunny beam, once it's out: until then it waits unseen
            // inside a statue for Link to come by. (Outdoors the same sprite
            // is a chimney's smoke.)
            0xd1 => if (vars.player_is_indoors.* != 0 and vars.sprite_ai_state[k] != 0)
                add.world(kMagic, sx + 8, sy + 8, seed, 1.2),
            // Fairies, and the bubbles that pretend to be them.
            0xe3 => if (absorbableShown(k)) add.world(kFairy, sx + 8, sy + 8, seed, 1),
            0xc8 => add.world(kFairy, sx + 8, sy + 8, seed, 1),
            0x15, 0x77, 0x82 => add.world(kTinySpark, sx + 8, sy + 8, seed, 1),
            // A crystal switch, in whichever color it's showing.
            0x1e => add.worldColored(kCrystal, sx + 8, sy + 8, seed, spriteHue(ppu, vars.sprite_oam_flags[k])),
            // A Beamos: its eye as it sweeps the room, brighter as it locks
            // on and flashes; its laser, the head and down the beam; the
            // spark where it hits.
            0x61 => switch (vars.sprite_C[k]) {
                0 => {
                    const i: usize = vars.sprite_D[k] >> 1;
                    const ex = sx + @as(i32, sprite_tables.kBeamosEyeball_Draw_X[i]) - 3 + 4;
                    const ey = sy + @as(i32, sprite_tables.kBeamosEyeball_Draw_Y[i]) - 18 + 4;
                    add.world(kEye, ex, ey, seed, if (vars.sprite_ai_state[k] == 3) 1.6 else 0.8);
                },
                1 => if (vars.sprite_delay_aux1[k] == 0) {
                    add.world(kLaser, sx + 4, sy + 4, seed, 1);
                    // Its trail: a ring of 32 places it's been, a few of them.
                    const g: usize = @as(usize, vars.sprite_graphics[k] & 3) * 32;
                    var j: usize = 4;
                    while (j < 32) : (j += 9) {
                        const tx: i32 = @as(i32, vars.beamos_x_lo[g + j]) | @as(i32, vars.beamos_x_hi[g + j]) << 8;
                        const ty: i32 = @as(i32, vars.beamos_y_lo[g + j]) | @as(i32, vars.beamos_y_hi[g + j]) << 8;
                        add.world(kLaser, tx + 4, ty + 4, seed + @as(u32, @intCast(j)) * 16, 0.6);
                    }
                },
                else => add.world(kSpark, sx + 8, sy + 8, seed, 1),
            },
            // A laser eye on the wall: shut, nothing; open, a faint glow;
            // about to fire, bright. Its beam lights as it goes.
            0x95...0x98 => if (vars.sprite_A[k] != 0) {
                add.world(kLaser, sx + 4, sy + 4, seed, 1);
            } else {
                const d = vars.sprite_D[k] & 3;
                const ex: i32 = switch (d) {
                    0 => sx + 12,
                    1 => sx + 4,
                    else => sx + 8,
                };
                const ey: i32 = switch (d) {
                    2 => sy + 12,
                    3 => sy + 4,
                    else => sy + 8,
                };
                const amount: f32 = if (vars.sprite_ai_state[k] == 1) 1.4 else if (vars.sprite_graphics[k] == 1) 0.35 else 0;
                add.world(kEye, ex, ey, seed, amount);
            },
            // A Wizzrobe's beam, and the Wizzrobe while it's casting.
            0x9b => if (vars.sprite_C[k] != 0)
                add.world(kMagic, sx + 4, sy + 4, seed, 1)
            else if (vars.sprite_ai_state[k] == 2)
                add.world(kMagic, sx + 8, sy + 8, seed, 0.45),
            // Trinexx's heads' breath: the red one's fire, the blue one's ice.
            0xcc => if (vars.sprite_E[k] != 0) add.world(kFire, sx + 8, sy + 8, seed, 1),
            0xcd => if (vars.sprite_E[k] != 0) add.world(kCold, sx + 8, sy + 8, seed, 1.6),
            // Things to pick up glint a little in their own color: hearts,
            // rupees, keys. A heart container or piece, more.
            0xd8...0xdb, 0xe4, 0xe5 => if (absorbableShown(k)) {
                // A heart's an 8 pixel square, a rupee or small key 8 wide
                // and 16 tall, a big key 16 square.
                const t = vars.sprite_type[k];
                const cx: i32 = if (t == 0xe5) 8 else 4;
                const cy: i32 = if (t == 0xd8) 4 else 8;
                add.worldColored(kPickup, sx + cx, sy + cy, seed, spriteHue(ppu, vars.sprite_oam_flags[k]));
            },
            0xea, 0xeb => add.worldColored(kHeartContainer, sx + 8, sy + 8, seed, spriteHue(ppu, vars.sprite_oam_flags[k])),
            else => {},
        }
    }

    // What some of those leave behind: trails and sparkles.
    for (0..30) |k| {
        const gx: i32 = @as(i32, vars.garnish_x_lo[k]) | @as(i32, vars.garnish_x_hi[k]) << 8;
        // The game draws a garnish 16 pixels above where it keeps it
        // (Garnish_ReturnIfPrepFails).
        const gy: i32 = (@as(i32, vars.garnish_y_lo[k]) | @as(i32, vars.garnish_y_hi[k]) << 8) - 16;
        const seed: u32 = @as(u32, @intCast(k)) + 0x30000;
        switch (vars.garnish_type[k]) {
            // A fire snake's tail, Trinexx's fire breath, Ganon's fire bats.
            0x01, 0x0e, 0x10, 0x11 => add.world(kSmallFire, gx + 4, gy + 4, seed, 0.8),
            // Trinexx's ice breath.
            0x0c => add.world(kCold, gx + 4, gy + 4, seed, 1),
            // Lasers: the eyes', the Beamos', Blind's.
            0x04, 0x0f => add.world(kLaser, gx + 4, gy + 4, seed, 1),
            // Mothula's beam, flashes, sparkles.
            0x02, 0x07, 0x12 => add.world(kTinySpark, gx + 4, gy + 4, seed, 1),
            // The trail a bolt leaves down the room, fading as it goes.
            0x09 => add.world(kBoltTrail, gx + 8, gy + 8, seed, boltAmount() * @as(f32, @floatFromInt(vars.garnish_countdown[k])) / 32.0),
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

const kTorch = Source{ .r = 64, .c = kFlame, .strength = 1.3, .burn = kTorchBurn, .glow_r = 9, .glow = 0.45 };
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
const kEye = Source{ .r = 22, .c = .{ 1.0, 0.3, 0.25 }, .strength = 1.1, .burn = kLanternBurn, .glow_r = 3, .glow = 0.6 };
/// Lava breathes: a slow swell and ebb, never guttering like a flame.
pub const kLavaBurn = Burn{ .waver = 0.12, .speed = 0.035, .gutter = 0, .gutter_odds = 0, .sway = 0 };
const kLava = Source{ .r = 64, .c = .{ 1.0, 0.42, 0.16 }, .strength = 1.15, .burn = kLavaBurn };
const kBolt = Source{ .r = 84, .c = .{ 0.72, 0.84, 1.0 }, .strength = 2.0, .burn = kSparkBurn, .glow_r = 11, .glow = 0.5 };
/// A bolt's trail lights the floor but has no glow of its own: there are a
/// dozen and more of it at once, and their glows would pile up into white.
const kBoltTrail = Source{ .r = 56, .c = .{ 0.72, 0.84, 1.0 }, .strength = 1.6, .burn = kSparkBurn };
const kOutdoorWarp = Source{ .r = 40, .c = .{ 1, 1, 1 }, .strength = 1.0, .burn = kLanternBurn, .glow_r = 10, .glow = 0.3 };
const kPortal = Source{ .r = 36, .c = .{ 1, 1, 1 }, .strength = 1.0, .burn = kLanternBurn, .glow_r = 9, .glow = 0.4 };
const kWarp = Source{ .r = 44, .c = .{ 1, 1, 1 }, .strength = 1.0, .burn = kLanternBurn, .glow_r = 9, .glow = 0.35 };
const kTreasure = Source{ .r = 44, .c = .{ 1.0, 0.9, 0.62 }, .strength = 1.0, .burn = kLanternBurn, .glow_r = 8, .glow = 0.3 };
const kMilestone = Source{ .r = 76, .c = .{ 1.0, 0.96, 0.88 }, .strength = 1.4, .burn = kLanternBurn, .glow_r = 13, .glow = 0.6 };
const kPickup = Source{ .r = 14, .c = .{ 1, 1, 1 }, .strength = 0.5, .burn = kLanternBurn, .glow_r = 3, .glow = 0.16 };
const kHeartContainer = Source{ .r = 26, .c = .{ 1, 1, 1 }, .strength = 0.8, .burn = kLanternBurn, .glow_r = 5, .glow = 0.28 };
const kEther = Source{ .r = 160, .c = .{ 0.75, 0.85, 1.0 }, .strength = 1.6, .burn = kSparkBurn };
const kBombos = Source{ .r = 160, .c = kFlame, .strength = 1.6, .burn = kFireBurn };

/// Whether a heart, rupee, key or fairy is drawn: not while it's hidden
/// under a pot, rock or bush for Link to find, nor while the game's holding
/// them all back (SpriteDraw_AbsorbableTransient).
fn absorbableShown(k: usize) bool {
    return vars.sprite_E[k] == 0 and vars.byte_7E0FC6.* < 3;
}

/// Whether a dungeon's pendant or crystal is drawn yet: it's there from the
/// start, waiting for the boss to be beaten (Ancilla29_MilestoneItemReceipt).
fn milestoneShown(k: usize) bool {
    const item = vars.ancilla_item_to_link[k];
    if (item == 0x10 or item == 0x0f) return vars.ancilla_G[k] == 0;
    const bits = vars.dung_savegame_state_bits.*;
    return bits & 0x4000 == 0 and bits & 0x8000 != 0 and vars.byte_7E04C2.* == 0;
}

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
        const f = flame(self.tick, seed, if (dimFlashes()) steadyBurn(s.burn) else s.burn);
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

/// A light that stays put in a room, a fire or a warp tile: where in the
/// world, and what kind.
pub const Spot = struct {
    x: i32,
    y: i32,
    kind: enum { torch, brazier, candle, warp, lava, waterfall },
    /// A warp tile's light, the color of the tile as drawn.
    color: [3]f32 = .{ 1, 1, 1 },
    /// How much of a stretch of lava there is, 0 to 1.
    amount: f32 = 1,
    /// Frames in a row it's failed to look like it's burning since it last
    /// did (see refreshSpots).
    misses: u8 = 0,
};

/// The room's fixed fires, as last checked against the frame: what
/// refreshSpots kept.
var g_spots: [48]Spot = undefined;
var g_nspots: usize = 0;

/// The room's fixed fires that were burning on the last frame drawn, for
/// the embers that rise off them.
pub fn flameSpots(out: []Spot) usize {
    const n = @min(out.len, g_nspots);
    @memcpy(out[0..n], g_spots[0..n]);
    return n;
}

/// The frame as the PPU drew it, before any light: to tell a fire from
/// something drawn with the same tiles.
const Frame = struct {
    pixels: [*]const u8,
    pitch: usize,
    width: usize,
    height: usize,

    /// The pixel at (x, y), if it's on the frame and part of the scene: not
    /// the HUD, whose hearts are as red as lava and whose lamp is as yellow
    /// as a flame (the mask the PPU just marked says which is which).
    fn at(self: Frame, x: i32, y: i32) ?u32 {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return null;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (g_mask[uy * kMaxWidth + ux] == 0) return null;
        const row: [*]align(1) const u32 = @ptrCast(self.pixels + uy * self.pitch);
        return row[ux];
    }

    /// The average color within `r` pixels of (x, y) on the frame, its
    /// brightest channel at 1. Null if that's mostly off the frame, or black.
    fn colorAt(self: Frame, x: i32, y: i32, r: i32) ?[3]f32 {
        var sum = [3]f32{ 0, 0, 0 };
        var count: i32 = 0;
        var dy = -r;
        while (dy < r) : (dy += 1) {
            var dx = -r;
            while (dx < r) : (dx += 1) {
                const c = self.at(x + dx, y + dy) orelse continue;
                sum[0] += @floatFromInt((c >> 16) & 0xff);
                sum[1] += @floatFromInt((c >> 8) & 0xff);
                sum[2] += @floatFromInt(c & 0xff);
                count += 1;
            }
        }
        if (count * 2 < (2 * r) * (2 * r)) return null;
        const top = @max(sum[0], @max(sum[1], sum[2]));
        if (top <= 0) return null;
        return .{ sum[0] / top, sum[1] / top, sum[2] / top };
    }

    /// Whether there are flame colors, bright yellows and oranges, within
    /// `r` pixels of (x, y) on the frame.
    fn burnsAt(self: Frame, x: i32, y: i32, r: i32) bool {
        var hits: u32 = 0;
        var dy = -r;
        while (dy <= r) : (dy += 1) {
            var dx = -r;
            while (dx <= r) : (dx += 1) {
                const c = self.at(x + dx, y + dy) orelse continue;
                if (looksLikeFlame(c)) hits += 1;
                if (hits >= 2) return true;
            }
        }
        return false;
    }
};

/// A pixel a flame might be: bright, red over blue by a good way, and not
/// washed out to white.
pub fn looksLikeFlame(px: u32) bool {
    const r = (px >> 16) & 0xff;
    const g = (px >> 8) & 0xff;
    const b = px & 0xff;
    return r >= 0xc0 and g >= 0x60 and b <= 0xa0 and r >= b + 0x60;
}

/// Finds the room's fixed fires by their tiles and keeps the ones that are
/// burning on the frame just drawn. The tiles alone aren't enough: a tile's
/// number means a different picture in a different room's tile set (the
/// castle's statues are made of a sconce's tiles), and between two rooms
/// the next one's tiles arrive before the camera does. A fire off the frame
/// can't be seen to burn, so it waits until it's on. A warp tile has to be
/// one the game would warp Link on, and its light takes the tile's color
/// (gold in one dungeon, something else in the next).
fn refreshSpots(frame: Frame, left: i32) void {
    var found: [48]Spot = undefined;
    const n = candidateSpots(&found);
    const cam_x: i32 = vars.BG2HOFS_copy2.*;
    const cam_y: i32 = vars.BG2VOFS_copy2.*;
    var prev: [48]Spot = undefined;
    const nprev = g_nspots;
    @memcpy(prev[0..nprev], g_spots[0..nprev]);
    g_nspots = 0;
    for (found[0..n]) |spot| {
        const r: i32 = if (spot.kind == .candle) 4 else 6;
        var keep = spot;
        if (spot.kind == .waterfall) {
            // Its tiles are hard to mistake; nothing to check on the frame.
        } else if (spot.kind == .warp) {
            // Outdoors the scan has already checked the ground's warp.
            if (vars.player_is_indoors.* != 0 and !isWarp(spot.x, spot.y)) continue;
            keep.color = frame.colorAt(spot.x - cam_x + left, spot.y - cam_y, 6) orelse continue;
        } else if (!frame.burnsAt(spot.x - cam_x + left, spot.y - cam_y, r)) {
            // A fire seen burning a moment ago, its tiles still a lit
            // torch's: kept through a few frames that don't look it, while
            // the game flashes the room white for lightning, say, and every
            // flame on the screen goes pale with it.
            const was = findSpot(prev[0..nprev], spot) orelse continue;
            if (was.misses >= kSpotMisses) continue;
            keep.misses = was.misses + 1;
        }
        if (g_nspots == g_spots.len) break;
        g_spots[g_nspots] = keep;
        g_nspots += 1;
    }
    if (vars.player_is_indoors.* != 0) findLava(frame, left, cam_x, cam_y) else findOutdoorWaterfalls(frame, left, cam_x, cam_y);
}

/// How many frames in a row a fire that was burning may fail to look it
/// and still be kept.
const kSpotMisses = 40;

fn findSpot(spots: []const Spot, want: Spot) ?Spot {
    for (spots) |s| {
        if (s.x == want.x and s.y == want.y and s.kind == want.kind) return s;
    }
    return null;
}

/// The size of the squares lava's looked for in, pinned to the room so they
/// don't slide about as the camera moves.
const kLavaCell = 64;

/// Lava on the frame just drawn: the floor that's a pit (Turtle Rock's lava
/// is, to the game) and lava colored, bright reds and oranges with next to
/// no blue. In each square of the room on the screen with enough of it, a
/// light where its lava is, as much as there is of it.
fn findLava(frame: Frame, left: i32, cam_x: i32, cam_y: i32) void {
    const x_lo = @divFloor(cam_x - left, kLavaCell);
    const x_hi = @divFloor(cam_x - left + @as(i32, @intCast(frame.width)) - 1, kLavaCell);
    const y_lo = @divFloor(cam_y, kLavaCell);
    const y_hi = @divFloor(cam_y + @as(i32, @intCast(frame.height)) - 1, kLavaCell);
    var cy = y_lo;
    while (cy <= y_hi) : (cy += 1) {
        var cx = x_lo;
        while (cx <= x_hi) : (cx += 1) {
            var count: i32 = 0;
            var sum_x: i32 = 0;
            var sum_y: i32 = 0;
            var sy: i32 = 4;
            while (sy < kLavaCell) : (sy += 8) {
                var sx: i32 = 4;
                while (sx < kLavaCell) : (sx += 8) {
                    const wx = cx * kLavaCell + sx;
                    const wy = cy * kLavaCell + sy;
                    const px = frame.at(wx - cam_x + left, wy - cam_y) orelse continue;
                    if (!looksLikeLava(px)) continue;
                    const t: usize = @intCast((@mod(wy, 512) >> 3) * 64 + (@mod(wx, 512) >> 3));
                    if (vars.dung_bg2_attr_table[t] != kPitAttr and vars.dung_bg1_attr_table[t] != kPitAttr) continue;
                    count += 1;
                    sum_x += wx;
                    sum_y += wy;
                }
            }
            // A few pixels' worth is a sprite's red or a sliver at the
            // edge, not a stretch of lava.
            if (count < 6 or g_nspots == g_spots.len) continue;
            g_spots[g_nspots] = .{
                .x = @divTrunc(sum_x, count),
                .y = @divTrunc(sum_y, count),
                .kind = .lava,
                .amount = @min(1.0, @as(f32, @floatFromInt(count)) / 40.0),
            };
            g_nspots += 1;
        }
    }
}

/// The attribute of floor Link falls through, which Turtle Rock's lava is.
const kPitAttr = 0x20;

/// A pixel lava might be: bright to dark red or orange, and next to no blue.
pub fn looksLikeLava(px: u32) bool {
    const r = (px >> 16) & 0xff;
    const g = (px >> 8) & 0xff;
    const b = px & 0xff;
    return r >= 0x90 and g + 0x60 <= r and b <= 0x30;
}

/// The room's fixed fires, the lit torches, braziers and sconces' candles,
/// and its warp tiles, as their tiles say, in world coordinates, up to `out.len` of them.
/// Indoors only.
fn candidateSpots(out: []Spot) usize {
    if (vars.player_is_indoors.* == 0) return findOutdoorWarps(out);
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
                findBraziers(map, tiles[nt..])
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
    var nw = findTiles2x2(vars.dung_bg2, SrcPtr(kWarpTiles)[0..4].*, kIgnorePriority, &tiles);
    if (bg1_is_room) nw += findTiles2x2(vars.dung_bg1, SrcPtr(kWarpTiles)[0..4].*, kIgnorePriority, tiles[nw..]);
    for (tiles[0..nw]) |t| {
        if (n == out.len) return n;
        const lx: i32 = @intCast((t & 63) * 8 + 8);
        const ly: i32 = @intCast((t >> 6) * 8 + 8);
        out[n] = .{ .x = world(lx, cam_x), .y = world(ly, cam_y), .kind = .warp };
        n += 1;
    }
    // Waterfalls pouring out of the walls' faces (Swamp Palace's), the mist
    // at their feet.
    for (kWaterfalls) |wf| {
        const src = SrcPtr(wf.src)[0 .. 4 * wf.rows];
        var nf = findBlock(vars.dung_bg2, src, 4, wf.rows, true, kIgnorePriority, &tiles);
        if (bg1_is_room) nf += findBlock(vars.dung_bg1, src, 4, wf.rows, true, kIgnorePriority, tiles[nf..]);
        for (tiles[0..nf]) |t| {
            if (n == out.len) return n;
            const lx: i32 = @intCast((t & 63) * 8 + 16);
            const ly: i32 = @intCast(((t >> 6) + wf.rows) * 8 - 2);
            out[n] = .{ .x = world(lx, cam_x), .y = world(ly, cam_y), .kind = .waterfall };
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

/// Where the room's object data keeps a warp tile's four tiles.
const kWarpTiles = 0x1f3a;

/// The tile attribute the game warps Link on.
const kWarpAttr = 0x4b;

/// Whether the warp tile centered on world (x, y) is one the game would
/// warp Link on: its tiles alone could be something else in another tile set.
fn isWarp(x: i32, y: i32) bool {
    const i: usize = @intCast((@mod(y - 4, 512) >> 3) * 64 + (@mod(x - 4, 512) >> 3));
    return vars.dung_bg2_attr_table[i] == kWarpAttr or vars.dung_bg1_attr_table[i] == kWarpAttr;
}

/// The faces in the wall that pour out a waterfall, as the room's object
/// data draws them: four tiles across, a row at a time, the face and the
/// water falling from it down to where it lands.
const Waterfall = struct { src: u16, rows: usize };
const kWaterfalls = [_]Waterfall{
    .{ .src = 0x162c, .rows = 5 },
    .{ .src = 0x1654, .rows = 7 },
};

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

/// A brazier's eight tiles, two across and four down, a row at a time: its
/// bowl of fire on top, its stand below, the right half the left mirrored.
/// All eight, since tile numbers mean different things in different rooms'
/// tile sets, and the bowl's four alone turn up in the castle's statues.
pub const kBrazierTiles = [8]u16{ 0x0dc2, 0x4dc2, 0x0dc3, 0x4dc3, 0x0d2c, 0x4d2c, 0x0d3c, 0x4d3c };

/// Finds the room's braziers in a 64x64 tile map.
pub fn findBraziers(map: [*]align(1) const u16, out: []u16) usize {
    return findBlock(map, &kBrazierTiles, 2, 4, true, kIgnorePriority, out);
}
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

test "braziers are found whole, whichever way their priority bit is set, and not by their bowl alone" {
    var map: [64 * 64]u16 = @splat(0);
    const at = 10 * 64 + 20;
    for (0..4) |dy| for (0..2) |dx| {
        map[at + dy * 64 + dx] = kBrazierTiles[dy * 2 + dx] | 0x2000;
    };
    var found: [2]u16 = undefined;
    try testing.expectEqual(@as(usize, 1), findBraziers(&map, &found));
    try testing.expectEqual(@as(u16, at), found[0]);
    // The bowl without its stand, as the castle's statues have it.
    map[at + 2 * 64] = 0;
    try testing.expectEqual(@as(usize, 0), findBraziers(&map, &found));
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

test "it rains until Zelda's rescued, and over the swamp until it's drained" {
    const saved = .{ vars.player_is_indoors.*, vars.overworld_screen_index.*, vars.sram_progress_indicator.*, vars.save_ow_event_info[0x70] };
    defer {
        vars.player_is_indoors.* = saved[0];
        vars.overworld_screen_index.* = saved[1];
        vars.sram_progress_indicator.* = saved[2];
        vars.save_ow_event_info[0x70] = saved[3];
    }
    const saved_module = vars.main_module_index.*;
    defer vars.main_module_index.* = saved_module;
    vars.main_module_index.* = 2; // the file select
    vars.player_is_indoors.* = 0;
    vars.overworld_screen_index.* = 0x2c;
    vars.sram_progress_indicator.* = 0;
    try testing.expect(!raining());
    vars.main_module_index.* = 9; // out in the world
    vars.save_ow_event_info[0x70] = 0;
    vars.sram_progress_indicator.* = 1;
    try testing.expect(raining());
    vars.sram_progress_indicator.* = 2;
    try testing.expect(!raining());
    vars.overworld_screen_index.* = 0x70;
    try testing.expect(raining());
    vars.save_ow_event_info[0x70] = 0x20;
    try testing.expect(!raining());
    vars.save_ow_event_info[0x70] = 0;
    vars.player_is_indoors.* = 1;
    try testing.expect(!raining());
}

test "the storm strikes before the thunder, a different gap each time" {
    var leads: [8]u8 = undefined;
    for (&leads) |*l| {
        planStrikes();
        try testing.expect(g_strikes[0].at < kThunderFrame and g_strikes[0].at >= kThunderFrame - 36);
        for (g_strikes[1..g_nstrikes]) |s| try testing.expect(s.at >= 60 and s.power < g_strikes[0].power);
        l.* = g_strikes[0].at;
    }
    var all_same = true;
    for (leads[1..]) |l| all_same = all_same and l == leads[0];
    try testing.expect(!all_same);
}

test "flames are bright yellows and oranges, not white, gray or blue" {
    try testing.expect(looksLikeFlame(0xfff060));
    try testing.expect(looksLikeFlame(0xf08020));
    try testing.expect(!looksLikeFlame(0xffffff));
    try testing.expect(!looksLikeFlame(0xa0a0a8));
    try testing.expect(!looksLikeFlame(0x4060f0));
    try testing.expect(!looksLikeFlame(0x806040)); // brown, too dim
}

test "a warp tile's light takes the tile's color, and not off the frame's edge" {
    // All scene, no HUD.
    for (0..16) |y| @memset(g_mask[y * kMaxWidth ..][0..16], kMaskDark);
    var px: [16 * 16]u32 = undefined;
    @memset(&px, 0xad7b52);
    const frame = Frame{ .pixels = @ptrCast(&px), .pitch = 16 * 4, .width = 16, .height = 16 };
    const c = frame.colorAt(8, 8, 6).?;
    try testing.expectApproxEqAbs(@as(f32, 1), c[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0x7b) / 0xad, c[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0x52) / 0xad, c[2], 0.001);
    // Mostly off the frame: no telling.
    try testing.expect(frame.colorAt(-3, -3, 6) == null);
    @memset(&px, 0);
    try testing.expect(frame.colorAt(8, 8, 6) == null);
}

test "a warp tile only counts where the game would warp Link" {
    const saved2 = vars.dung_bg2_attr_table[0..4096].*;
    const saved1 = vars.dung_bg1_attr_table[0..4096].*;
    defer {
        vars.dung_bg2_attr_table[0..4096].* = saved2;
        vars.dung_bg1_attr_table[0..4096].* = saved1;
    }
    @memset(vars.dung_bg2_attr_table[0..4096], 0);
    @memset(vars.dung_bg1_attr_table[0..4096], 0);
    // A warp tile with its top left at tile (10, 20), in some room.
    const x = 3 * 512 + 10 * 8 + 8;
    const y = 2 * 512 + 20 * 8 + 8;
    try testing.expect(!isWarp(x, y));
    vars.dung_bg2_attr_table[20 * 64 + 10] = kWarpAttr;
    try testing.expect(isWarp(x, y));
    vars.dung_bg2_attr_table[20 * 64 + 10] = 0;
    vars.dung_bg1_attr_table[20 * 64 + 10] = kWarpAttr;
    try testing.expect(isWarp(x, y));
}

test "the dimming eases toward where it's going and stops there" {
    try testing.expectApproxEqAbs(@as(f32, 0.99), easeToward(1, 0.8, 0.01), 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.8), easeToward(0.805, 0.8, 0.01), 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.81), easeToward(0.8, 1, 0.01), 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 1), easeToward(1, 1, 0.01), 0.0001);
}

test "too many lights keeps the ones that matter most" {
    var lights: [6]Light = undefined;
    const radii = [_]f32{ 10, 80, 20, 60, 5, 40 };
    for (&lights, radii) |*l, r| l.* = .{ .x = 0, .y = 0, .radius = r, .color = .{ 1, 1, 1 } };
    try testing.expectEqual(@as(usize, 3), keepBrightest(&lights, 3));
    try testing.expectEqual(@as(f32, 80), lights[0].radius);
    try testing.expectEqual(@as(f32, 60), lights[1].radius);
    try testing.expectEqual(@as(f32, 40), lights[2].radius);
    // Under the limit, nothing moves.
    var few = [_]Light{ .{ .x = 0, .y = 0, .radius = 5, .color = .{ 1, 1, 1 } }, .{ .x = 0, .y = 0, .radius = 50, .color = .{ 1, 1, 1 } } };
    try testing.expectEqual(@as(usize, 2), keepBrightest(&few, 3));
    try testing.expectEqual(@as(f32, 5), few[0].radius);
}

test "lava is bright to dark red or orange with no blue, and not a flame's yellow" {
    try testing.expect(looksLikeLava(0xe72121));
    try testing.expect(looksLikeLava(0xff7b21));
    try testing.expect(looksLikeLava(0x941818));
    try testing.expect(!looksLikeLava(0xffd060)); // a flame's yellow
    try testing.expect(!looksLikeLava(0xc6c6a5)); // stone
    try testing.expect(!looksLikeLava(0x701010)); // too dark
    try testing.expect(!looksLikeLava(0xe02080)); // pink
}

test "the HUD's pixels don't count as the scene's" {
    var px: [4 * 4]u32 = undefined;
    @memset(&px, 0xe72121); // as red as lava, and a heart
    const frame = Frame{ .pixels = @ptrCast(&px), .pitch = 4 * 4, .width = 4, .height = 4 };
    for (0..4) |y| @memset(g_mask[y * kMaxWidth ..][0..4], 0);
    try testing.expect(frame.at(1, 1) == null);
    g_mask[1 * kMaxWidth + 1] = kMaskDark;
    try testing.expectEqual(@as(?u32, 0xe72121), frame.at(1, 1));
}

test "Dim Flashes softens the lightning and steadies the flicker" {
    const was = features.enhanced_features0.*;
    defer features.enhanced_features0.* = was;
    const saved = g_flash;
    defer g_flash = saved;
    g_flash = 0.8;
    features.enhanced_features0.* = 0;
    try testing.expectApproxEqAbs(@as(f32, 0.8), flash(), 0.0001);
    features.enhanced_features0.* = features.kFeatures0_DimFlashes;
    try testing.expectApproxEqAbs(@as(f32, 0.8) * kDimFlash, flash(), 0.0001);
    const b = steadyBurn(kSparkBurn);
    try testing.expect(b.waver < kSparkBurn.waver and b.speed < kSparkBurn.speed and b.gutter < kSparkBurn.gutter);
}

test "HD Water takes blue and green for water, not the Dark World's pink clouds" {
    try testing.expect(coolEnough(0x006331)); // the Dark World's swamp
    try testing.expect(coolEnough(0x005229));
    try testing.expect(coolEnough(0x314a7b));
    try testing.expect(coolEnough(0x5a84c6));
    try testing.expect(!coolEnough(0xad7b84));
    try testing.expect(!coolEnough(0xd6a5ad));
    try testing.expect(!coolEnough(0x101010));
    try testing.expect(!coolEnough(0x181829)); // a pool's dark rim
    // But the lightning flashes them cyan: Death Mountain's left out.
    try testing.expect(coolEnough(0x00ffff));
    try testing.expect(onDeathMountain(0x45));
    // Indoors: Swamp Palace's water only once BG1's drawn, and the steps
    // into it aren't water.
    try testing.expectEqual(@as(u8, 0x08), dungeonAttr(0x00, 0x08, true).attr);
    try testing.expectEqual(@as(u8, 0x00), dungeonAttr(0x00, 0x08, false).attr);
    try testing.expect(dungeonAttr(0x08, 0x08, true).steps);
    try testing.expect(dungeonAttr(0x02, 0x08, true).steps);
    try testing.expectEqual(@as(u8, 0x08), dungeonAttr(0x08, 0x00, false).attr);
    try testing.expect(!onDeathMountain(0x35));
}

test "HD Water knows deep from shallow, and follows the shore by the water's colors" {
    try testing.expectEqual(@as(u8, 2), waterDepth(0x08));
    try testing.expectEqual(@as(u8, 1), waterDepth(0x09));
    try testing.expectEqual(@as(u8, 0), waterDepth(0x00));
    g_water_colors[0] = 0x3060c0;
    g_water_colors[1] = 0x4878d8;
    g_nwater_colors = 2;
    defer g_nwater_colors = 0;
    try testing.expect(isWaterColor(0x003060c0));
    try testing.expect(isWaterColor(0x014878d8)); // the mask's byte on top doesn't count
    try testing.expect(!isWaterColor(0x806020)); // the bank
    // The shallow strip down the middle of a waterfall isn't water to redraw.
    try testing.expect(fallsBeside(&.{ 0x02, 0x02, 0x09, 0x09, 0x02, 0x02 }, 2));
    try testing.expect(!fallsBeside(&.{ 0x08, 0x09, 0x09, 0x09, 0x02, 0x02 }, 2));
    try testing.expect(looksLikeWater(0x5a84c6) and looksLikeWater(0x3963ad));
    try testing.expect(!looksLikeWater(0x806020) and !looksLikeWater(0x4a9c4a) and !looksLikeWater(0xf8f8f8));
}
