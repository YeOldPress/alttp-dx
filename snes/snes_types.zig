//! Shared declarations for the SNES core. The Snes struct itself still lives in
//! C (snes.c), so this mirrors its layout for the modules that have moved over.
const std = @import("std");

/// Must match `struct Snes` in snes.h. Sub-components stay opaque pointers;
/// only the fields the ported modules touch need to be spelled out.
pub const Snes = extern struct {
    cpu: ?*anyopaque,
    apu: ?*anyopaque,
    ppu: ?*anyopaque,
    dma: ?*anyopaque,
    cart: ?*anyopaque,
    // input
    debug_cycles: bool,
    disableHpos: bool,
    input1: ?*anyopaque,
    input2: ?*anyopaque,

    // frame timing
    hPos: u16,
    vPos: u16,
    frames: u32,
    // cpu handling
    cpuCyclesLeft: u8,
    cpuMemOps: u8,
    apuCatchupCycles: f64,
    // nmi / irq
    hIrqEnabled: bool,
    vIrqEnabled: bool,
    nmiEnabled: bool,
    hTimer: u16,
    vTimer: u16,
    inNmi: bool,
    inIrq: bool,
    inVblank: bool,
    // joypad handling
    portAutoRead: [4]u16, // as read by auto-joypad read
    autoJoyRead: bool,
    autoJoyTimer: u16, // times how long until reading is done
    ppuLatch: bool,
    // multiplication/division
    multiplyA: u8,
    multiplyResult: u16,
    divideA: u16,
    divideResult: u16,
    // misc
    fastMem: bool,
    openBus: u8,
    // ram
    ram: ?[*]u8,
    ramAdr: u32,
};

/// typedef void SaveLoadFunc(void *ctx, void *data, size_t data_size);
pub const SaveLoadFunc = fn (ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void;

pub extern fn snes_read(snes: *Snes, adr: u32) u8;
pub extern fn snes_write(snes: *Snes, adr: u32, val: u8) void;
pub extern fn snes_readBBus(snes: *Snes, adr: u8) u8;
pub extern fn snes_writeBBus(snes: *Snes, adr: u8, val: u8) void;

const testing = std.testing;

test "Snes layout matches snes.h" {
    // Offsets taken from the C compiler on this target. The ported modules
    // reach into this struct, so a mismatch here corrupts the emulator state.
    if (@sizeOf(*anyopaque) != 8) return error.SkipZigTest;
    try testing.expectEqual(144, @sizeOf(Snes));
    try testing.expectEqual(80, @offsetOf(Snes, "apuCatchupCycles"));
    try testing.expectEqual(100, @offsetOf(Snes, "portAutoRead"));
    try testing.expectEqual(121, @offsetOf(Snes, "openBus"));
    try testing.expectEqual(128, @offsetOf(Snes, "ram"));
    try testing.expectEqual(136, @offsetOf(Snes, "ramAdr"));
}
