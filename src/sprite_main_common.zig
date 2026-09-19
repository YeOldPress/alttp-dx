//! Helpers shared by the sprite_main part modules.
//!
//! These were originally copy-pasted into every part file as it was written;
//! `setOam` in particular carries the extended-OAM index arithmetic, so having
//! ten copies of it meant ten places for the same bug to hide.
//!
//! Note this is deliberately only the *concrete-typed* family. The older
//! modules (sprite_main.zig, sprite_main_extra.zig, and parts 1 and 2) use
//! generic `anytype` variants of sign8/sign16 that truncate their argument,
//! and sprite_main_extra.zig uses align(1) OAM pointers. Those are not
//! interchangeable with these, so they keep their own local definitions.
const v = @import("variables.zig");

pub inline fn ix(k: c_int) usize {
    return @intCast(k);
}

pub inline fn byte(x: anytype) u8 {
    return @truncate(@as(u32, @bitCast(@as(i32, @intCast(x)))));
}

pub inline fn sign8(x: u8) bool {
    return @as(i8, @bitCast(x)) < 0;
}

pub inline fn sign16(x: u16) bool {
    return @as(i16, @bitCast(x)) < 0;
}

/// Sign-extend an i8 table entry into the u16 the coordinate maths wants.
pub inline fn s16(x: i8) u16 {
    return @bitCast(@as(i16, x));
}

pub fn oamPtr() [*]v.OamEnt {
    return @ptrCast(&v.g_ram[v.oam_cur_ptr.*]);
}

pub fn setOam(p: [*]v.OamEnt, x: u16, y: u16, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = @truncate(x), .y = if (y +% 16 < 256) @truncate(y) else 0xf0, .charnum = ch, .flags = flags };
    const n = (@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(v.OamEnt);
    v.bytewise_extended_oam[n] = big | @as(u8, @truncate(x >> 8 & 1));
}

pub fn setOamPlain(p: [*]v.OamEnt, x: u8, y: u8, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = x, .y = y, .charnum = ch, .flags = flags };
    v.bytewise_extended_oam[(@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(v.OamEnt)] = big;
}
