//! Test root for the emulation module on its own.
//!
//! snes/cpu.zig calls HookedFunctionRts, which the game defines - it is how
//! the emulated CPU hands control back to the ported code at a hooked return.
//! It is the only symbol that crosses the boundary, and nothing under snes/
//! can supply it, so running these tests without the game needs a stand-in.
//!
//! It panics rather than doing nothing: these tests are not supposed to reach
//! a hooked return, and a silent no-op would let one start doing so without
//! anybody noticing.

const std = @import("std");

pub const root = @import("root.zig");

export fn HookedFunctionRts(is_long: c_int) callconv(.c) void {
    _ = is_long;
    @panic("HookedFunctionRts reached with no game linked in");
}

test {
    _ = root;
}
