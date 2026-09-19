//! Port of snes/input.c: the controller shift register.
const std = @import("std");

/// Only ever used as a pointer here; the layout lives on the C side still.
const Snes = opaque {};

/// Must match `struct Input` in input.h.
pub const Input = extern struct {
    snes: ?*Snes,
    @"type": u8,
    latchLine: bool,
    currentState: u16, // actual state
    latchedState: u16,
};

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

pub export fn input_init(snes: ?*Snes) callconv(.c) *Input {
    const input: *Input = @ptrCast(@alignCast(malloc(@sizeOf(Input)).?));
    input.snes = snes;
    // TODO: handle (where?)
    input.@"type" = 1;
    input.currentState = 0;
    return input;
}

pub export fn input_free(input: *Input) callconv(.c) void {
    free(input);
}

pub export fn input_reset(input: *Input) callconv(.c) void {
    input.latchLine = false;
    input.latchedState = 0;
}

pub export fn input_cycle(input: *Input) callconv(.c) void {
    if (input.latchLine) {
        input.latchedState = input.currentState;
    }
}

pub export fn input_read(input: *Input) callconv(.c) u8 {
    const ret: u8 = @intCast(input.latchedState & 1);
    input.latchedState >>= 1;
    input.latchedState |= 0x8000;
    return ret;
}

const testing = std.testing;

test "input_cycle latches only while the latch line is high" {
    var input = Input{ .snes = null, .@"type" = 1, .latchLine = false, .currentState = 0x1234, .latchedState = 0 };
    input_cycle(&input);
    try testing.expectEqual(@as(u16, 0), input.latchedState);
    input.latchLine = true;
    input_cycle(&input);
    try testing.expectEqual(@as(u16, 0x1234), input.latchedState);
}

test "input_read clocks out bits low first and shifts in ones" {
    var input = Input{ .snes = null, .@"type" = 1, .latchLine = true, .currentState = 0b1010, .latchedState = 0 };
    input_cycle(&input);
    for ([_]u8{ 0, 1, 0, 1 }) |expected|
        try testing.expectEqual(expected, input_read(&input));
    // The remaining 12 bits of the latch are zero...
    for (0..12) |_|
        try testing.expectEqual(@as(u8, 0), input_read(&input));
    // ...and past the end of the register the line reads high forever.
    for (0..4) |_|
        try testing.expectEqual(@as(u8, 1), input_read(&input));
}

test "input_reset clears the latch" {
    var input = Input{ .snes = null, .@"type" = 1, .latchLine = true, .currentState = 0xffff, .latchedState = 0xffff };
    input_reset(&input);
    try testing.expect(!input.latchLine);
    try testing.expectEqual(@as(u16, 0), input.latchedState);
}

test "Input layout matches input.h" {
    try testing.expectEqual(0, @offsetOf(Input, "snes"));
    try testing.expectEqual(@sizeOf(*anyopaque), @offsetOf(Input, "type"));
    try testing.expectEqual(@offsetOf(Input, "type") + 1, @offsetOf(Input, "latchLine"));
    try testing.expectEqual(@offsetOf(Input, "type") + 2, @offsetOf(Input, "currentState"));
    try testing.expectEqual(@offsetOf(Input, "type") + 4, @offsetOf(Input, "latchedState"));
}
