//! Controller rumble.
//!
//! The SNES pad had no motor, so nothing in the game asks for this. Instead it
//! watches what the game already does once each frame has run: Link losing
//! health, the explosion sound effect, the background offsets the game
//! jiggles for screen shakes, and a boss going through its death explosion. It only ever reads game state, so the port still
//! matches the original frame for frame with rumble on.
const std = @import("std");
const c = @import("sdl.zig").c;
const config = @import("config.zig");
const vars = @import("variables.zig");

/// The first sound effect port's id for an explosion: bombs, and each blast
/// of the Bombos medallion. The top two bits of the port are stereo pan.
const kSfx1_Explosion = 0x0c;

/// Modules where Link is actually out in the world: dungeons, the overworld,
/// and the overworld's special areas. Health changes anywhere else are the
/// file select or game over screens setting it, not damage.
fn inGameplay(module: u8) bool {
    return module == 0x07 or module == 0x09 or module == 0x0b;
}

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
/// The same for a boss blowing up, and whether one was last frame.
var g_boss_refresh: u8 = 0;
var g_boss_was_dying = false;
/// When the effect sent last runs out, and how strong it was, so a weak shake
/// refresh does not cut off a bomb that is still going.
var g_busy_until: u64 = 0;
var g_busy_low: u16 = 0;

/// Forgets what the previous frame looked like. Loading a snapshot or
/// resetting drops health in a single frame, and that is not damage.
pub fn reset() void {
    g_prev_module = 0;
    g_shake_refresh = 0;
    g_boss_refresh = 0;
    g_boss_was_dying = false;
}

/// Called after every frame the game runs. `sfx1` is the value the frame
/// sent to the first sound effect port.
pub fn afterFrame(sfx1: u8) void {
    const module = vars.main_module_index.*;
    const health = vars.link_health_current.*;
    defer {
        g_prev_module = module;
        g_prev_health = health;
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

    if (sfx1 & 0x3f == kSfx1_Explosion)
        effect = effect.max(.{ .low = 0xc000, .high = 0x8000, .ms = 250 });

    if (vars.bg1_x_offset.* != 0 or vars.bg1_y_offset.* != 0) {
        if (g_shake_refresh == 0) {
            effect = effect.max(.{ .low = 0x5000, .high = 0x2000, .ms = 150 });
            g_shake_refresh = 6;
        }
        g_shake_refresh -= 1;
    } else {
        g_shake_refresh = 0;
    }

    // A boss dying builds from a strong rumble to everything the pad has,
    // then lands one big thump when it disappears.
    if (bossDeathCountdown()) |left| {
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
        g_boss_was_dying = true;
    } else {
        if (g_boss_was_dying)
            effect = effect.max(.{ .low = 0xffff, .high = 0xffff, .ms = 700 });
        g_boss_refresh = 0;
        g_boss_was_dying = false;
    }

    if (effect.ms == 0) return;
    const now = c.SDL_GetTicks();
    if (now < g_busy_until and effect.low < g_busy_low) return;
    g_busy_until = now + effect.ms;
    g_busy_low = effect.low;
    send(scale(effect.low, strength), scale(effect.high, strength), effect.ms);
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
