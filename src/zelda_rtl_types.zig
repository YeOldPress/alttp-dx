//! Layout mirrors for the runtime environment declared in src/zelda_rtl.h.
//! zelda_rtl.c still owns the actual objects, so these only describe them.
const std = @import("std");

/// types.h
pub const MemBlk = @import("util.zig").MemBlk;

/// Must match `typedef struct ZeldaEnv` in zelda_rtl.h. The sub-objects stay
/// untyped pointers so this file does not have to depend on the snes modules;
/// callers cast them where they are actually used.
pub const ZeldaEnv = extern struct {
    ram: ?[*]u8,
    sram: ?[*]u8,
    vram: ?[*]u16,
    ppu: ?*anyopaque,
    player: ?*anyopaque,
    dma: ?*anyopaque,

    dialogue_blk: MemBlk,
    dialogue_font_blk: MemBlk,
    dialogue_flags: u8,
};

/// Defined in src/zelda_rtl.c while that file is still C.
pub extern var g_zenv: ZeldaEnv;

const testing = std.testing;

test "ZeldaEnv layout matches zelda_rtl.h" {
    // Offsets taken from the C compiler on this target.
    if (@sizeOf(*anyopaque) != 8) return error.SkipZigTest;
    try testing.expectEqual(16, @sizeOf(MemBlk));
    try testing.expectEqual(88, @sizeOf(ZeldaEnv));
    try testing.expectEqual(0, @offsetOf(ZeldaEnv, "ram"));
    try testing.expectEqual(8, @offsetOf(ZeldaEnv, "sram"));
    try testing.expectEqual(16, @offsetOf(ZeldaEnv, "vram"));
    try testing.expectEqual(24, @offsetOf(ZeldaEnv, "ppu"));
    try testing.expectEqual(32, @offsetOf(ZeldaEnv, "player"));
    try testing.expectEqual(40, @offsetOf(ZeldaEnv, "dma"));
    try testing.expectEqual(48, @offsetOf(ZeldaEnv, "dialogue_blk"));
    try testing.expectEqual(64, @offsetOf(ZeldaEnv, "dialogue_font_blk"));
    try testing.expectEqual(80, @offsetOf(ZeldaEnv, "dialogue_flags"));
}
