//! Controller rumble.
//!
//! The SNES pad had no motor, so nothing in the game asks for this. Instead it
//! watches what the game already does once each frame has run: Link losing
//! health, the explosion and moving-object sound effects, the background
//! offsets the game jiggles for screen shakes, Link's arrows landing, and a
//! boss going through its death explosion. It only ever reads game state, so
//! the port still matches the original frame for frame with rumble on.
const std = @import("std");
const c = @import("sdl.zig").c;
const config = @import("config.zig");
const vars = @import("variables.zig");

/// The first sound effect port's id for an explosion: bombs, and each blast
/// of the Bombos medallion. The top two bits of the port are stereo pan.
const kSfx1_Explosion = 0x0c;
/// The grinding of something heavy being shifted: push blocks, pushable
/// statues, gravestones, Somaria blocks, pull switches, the Swamp Palace
/// levers and the Sanctuary's sliding mantle all play it.
const kSfx1_Moving = 0x22;
/// The chest-opening fanfare, which a chest plays along with the door sound.
const kSfx1_Chest = 0x29;
/// The second sound effect port's id for a door sliding open: shutters,
/// including the ones floor switches work, key doors, and the eye and torch
/// doors. Opening a chest plays it too, alongside kSfx1_Chest.
const kSfx2_DoorOpens = 0x15;

/// Link's arrows live in the ancilla slots: type 9 while one flies, turning
/// to 10 on the frame it lands, which is when it thuds. The archers' arrows
/// are sprites, not ancillae, so they never count.
const kAncilla_Arrow = 9;
const kAncilla_ArrowStuck = 10;
const kAncillaSlots = 10;
var g_prev_ancilla_type: [kAncillaSlots]u8 = @splat(0);

const Landing = enum { none, wall, enemy };

/// Whether one of Link's arrows landed this frame, and in what. An arrow that
/// hits an enemy keeps that sprite's index in ancilla_S; a wall leaves 255.
fn arrowLanding() Landing {
    var landing: Landing = .none;
    for (0..kAncillaSlots) |k| {
        if (g_prev_ancilla_type[k] == kAncilla_Arrow and vars.ancilla_type[k] == kAncilla_ArrowStuck) {
            if (vars.ancilla_S[k] != 255) return .enemy;
            landing = .wall;
        }
    }
    return landing;
}

/// Modules where Link is actually out in the world: dungeons, the overworld,
/// and the overworld's special areas. Health changes anywhere else are the
/// file select or game over screens setting it, not damage.
fn inGameplay(module: u8) bool {
    return module == 0x07 or module == 0x09 or module == 0x0b;
}

/// When the countdown last read is at or below this, the boss vanishing next
/// is the natural end of its explosion rather than the room going away.
const kBossVanishes = 40;

/// The frames left on a boss's death explosion, or null if nothing is dying.
/// The boss sits in the explode state (4) with sprite_A clear, counting down
/// from 224 (255 for some) until it vanishes at 32. The puffs of smoke it
/// throws off share the state but set sprite_A to 31.
fn bossDeathCountdown() ?u8 {
    for (0..16) |k| {
        if (vars.sprite_state[k] == 4 and vars.sprite_A[k] == 0)
            return vars.sprite_delay_main[k];
    }
    return null;
}

const Effect = struct {
    low: u16 = 0,
    high: u16 = 0,
    ms: u32 = 0,

    fn max(a: Effect, b: Effect) Effect {
        return .{ .low = @max(a.low, b.low), .high = @max(a.high, b.high), .ms = @max(a.ms, b.ms) };
    }
};

var g_prev_health: u8 = 0;
var g_prev_module: u8 = 0;
/// Frames until a running screen shake gets its rumble topped up.
var g_shake_refresh: u8 = 0;
/// The shake offsets last frame, and how many more frames to count the
/// screen as shaking since they last moved. Every shake flips them each
/// frame; one that sits still is a leftover, like the pixel the Armos
/// Knights leave behind if the last one dies mid ground-pound.
var g_prev_shake: u32 = 0;
var g_shake_hold: u8 = 0;
/// The same refresh for a boss blowing up, and its countdown last frame.
var g_boss_refresh: u8 = 0;
var g_prev_boss: ?u8 = null;
/// When the effect sent last runs out, and how strong it was, so a weak shake
/// refresh does not cut off a bomb that is still going.
var g_busy_until: u64 = 0;
var g_busy_low: u16 = 0;

/// Forgets what the previous frame looked like. Loading a snapshot or
/// resetting drops health in a single frame, and that is not damage.
pub fn reset() void {
    g_prev_module = 0;
    g_shake_refresh = 0;
    g_shake_hold = 0;
    g_boss_refresh = 0;
    g_prev_boss = null;
    g_prev_ancilla_type = @splat(0);
}

/// Called after every frame the game runs. `sfx1` and `sfx2` are the values
/// the frame sent to the two sound effect ports.
pub fn afterFrame(sfx1: u8, sfx2: u8) void {
    const module = vars.main_module_index.*;
    const health = vars.link_health_current.*;
    const shake = @as(u32, vars.bg1_x_offset.*) << 16 | vars.bg1_y_offset.*;
    const boss = bossDeathCountdown();
    defer {
        g_prev_module = module;
        g_prev_health = health;
        g_prev_shake = shake;
        g_prev_boss = boss;
        @memcpy(&g_prev_ancilla_type, vars.ancilla_type[0..kAncillaSlots]);
    }
    const strength = config.g_config.rumble;
    if (strength == 0 or !inGameplay(module)) return;

    var effect: Effect = .{};

    // Health is in eighths of a heart, so a one heart hit is 8.
    if (inGameplay(g_prev_module) and health < g_prev_health) {
        const damage: u32 = g_prev_health - health;
        effect = effect.max(.{
            .low = @intCast(@min(0xffff, 0x7000 + damage * 0x1000)),
            .high = 0x5000,
            .ms = @min(400, 150 + damage * 15),
        });
    }

    switch (sfx1 & 0x3f) {
        kSfx1_Explosion => effect = effect.max(.{ .low = 0xc000, .high = 0x8000, .ms = 250 }),
        kSfx1_Moving => effect = effect.max(.{ .low = 0x6000, .high = 0x1000, .ms = 220 }),
        else => {},
    }

    if (sfx2 & 0x3f == kSfx2_DoorOpens and sfx1 & 0x3f != kSfx1_Chest)
        effect = effect.max(.{ .low = 0x5800, .high = 0x1800, .ms = 300 });

    // A short thud, a little firmer when the arrow finds an enemy.
    switch (arrowLanding()) {
        .none => {},
        .wall => effect = effect.max(.{ .low = 0x5000, .high = 0x2000, .ms = 90 }),
        .enemy => effect = effect.max(.{ .low = 0x7000, .high = 0x3000, .ms = 110 }),
    }

    if (screenShaking(shake)) {
        if (g_shake_refresh == 0) {
            effect = effect.max(.{ .low = 0x5000, .high = 0x2000, .ms = 150 });
            g_shake_refresh = 6;
        }
        g_shake_refresh -= 1;
    } else {
        g_shake_refresh = 0;
    }

    // A boss dying builds from a strong rumble to everything the pad has,
    // then lands one big thump when it disappears. A countdown that isn't
    // moving means the game has frozen sprites, for a message or an item,
    // and that shouldn't rumble on and on either.
    if (boss != null and boss != g_prev_boss) {
        const left = boss.?;
        if (g_boss_refresh == 0) {
            const progress: u32 = 224 - @as(u32, @max(@min(left, 224), 32));
            effect = effect.max(.{
                .low = @intCast(0x9000 + progress * 0x6fff / 192),
                .high = @intCast(0x4000 + progress * 0x8000 / 192),
                .ms = 150,
            });
            g_boss_refresh = 6;
        }
        g_boss_refresh -= 1;
    } else {
        if (boss == null and g_prev_boss != null and g_prev_boss.? <= kBossVanishes)
            effect = effect.max(.{ .low = 0xffff, .high = 0xffff, .ms = 700 });
        g_boss_refresh = 0;
    }

    if (effect.ms == 0) return;
    const now = c.SDL_GetTicks();
    if (now < g_busy_until and effect.low < g_busy_low) return;
    g_busy_until = now + effect.ms;
    g_busy_low = effect.low;
    send(scale(effect.low, strength), scale(effect.high, strength), effect.ms);
}

/// Whether the screen is shaking, given this frame's shake offsets. It counts
/// as shaking for a few frames after the offsets last moved.
fn screenShaking(shake: u32) bool {
    if (shake != g_prev_shake) {
        g_shake_hold = 4;
    } else if (g_shake_hold != 0) {
        g_shake_hold -= 1;
    }
    return g_shake_hold != 0;
}

fn scale(v: u16, percent: u8) u16 {
    return @intCast(@as(u32, v) * @min(percent, 100) / 100);
}

/// Every open pad gets it: there is only one player, and whichever pad they
/// are holding is the one that should shake.
fn send(low: u16, high: u16, ms: u32) void {
    var count: c_int = 0;
    const ids = c.SDL_GetGamepads(&count) orelse return;
    defer c.SDL_free(ids);
    for (ids[0..@intCast(count)]) |id| {
        if (c.SDL_GetGamepadFromID(id)) |pad|
            _ = c.SDL_RumbleGamepad(pad, low, high, ms);
    }
}

test "the rumble strength scales and never overflows" {
    try std.testing.expectEqual(@as(u16, 0), scale(0xffff, 0));
    try std.testing.expectEqual(@as(u16, 0x7fff), scale(0xffff, 50));
    try std.testing.expectEqual(@as(u16, 0xffff), scale(0xffff, 100));
    try std.testing.expectEqual(@as(u16, 0xffff), scale(0xffff, 250));
}

test "a dying boss is told apart from the smoke it throws off" {
    @memset(vars.g_ram[0xD90..0xE30], 0);
    try std.testing.expectEqual(@as(?u8, null), bossDeathCountdown());

    vars.sprite_state[3] = 4;
    vars.sprite_A[3] = 31;
    vars.sprite_delay_main[3] = 20;
    try std.testing.expectEqual(@as(?u8, null), bossDeathCountdown());

    vars.sprite_state[7] = 4;
    vars.sprite_A[7] = 0;
    vars.sprite_delay_main[7] = 150;
    try std.testing.expectEqual(@as(?u8, 150), bossDeathCountdown());
}

test "an arrow thuds once, on the frame it lands" {
    @memset(vars.g_ram[0x3A9..0x3B3], 0);
    @memset(vars.g_ram[0xC4A..0xC54], 0);
    reset();

    // In flight: nothing yet.
    vars.ancilla_type[2] = kAncilla_Arrow;
    try std.testing.expectEqual(Landing.none, arrowLanding());
    g_prev_ancilla_type[2] = kAncilla_Arrow;

    // Into a wall.
    vars.ancilla_type[2] = kAncilla_ArrowStuck;
    vars.ancilla_S[2] = 255;
    try std.testing.expectEqual(Landing.wall, arrowLanding());

    // Stuck the next frame is no longer news.
    g_prev_ancilla_type[2] = kAncilla_ArrowStuck;
    try std.testing.expectEqual(Landing.none, arrowLanding());

    // Into an enemy, which wins over a wall hit in the same frame.
    g_prev_ancilla_type[2] = kAncilla_Arrow;
    g_prev_ancilla_type[5] = kAncilla_Arrow;
    vars.ancilla_type[5] = kAncilla_ArrowStuck;
    vars.ancilla_S[5] = 4;
    try std.testing.expectEqual(Landing.enemy, arrowLanding());
}

test "a shake that stops moving stops rumbling" {
    reset();
    g_prev_shake = 0;

    // A real shake flips every frame and keeps going.
    for (0..20) |n| {
        const shake: u32 = if (n & 1 != 0) 0xffff else 1;
        try std.testing.expect(screenShaking(shake));
        g_prev_shake = shake;
    }

    // The Armos Knights' leftover pixel: stuck at one value, it winds down
    // within a few frames and stays quiet.
    var frames: usize = 0;
    while (screenShaking(1)) : (frames += 1) {
        g_prev_shake = 1;
        try std.testing.expect(frames < 8);
    }
    for (0..100) |_| try std.testing.expect(!screenShaking(1));
}
