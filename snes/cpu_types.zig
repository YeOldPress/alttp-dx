//! Layout mirror for `struct Cpu` (cpu.h). cpu.c has not been ported yet, so
//! this only describes the struct for the modules that read it.
const std = @import("std");

/// Must match `struct Cpu` in cpu.h.
pub const Cpu = extern struct {
    // reference to memory handler, for reading//writing
    mem: ?*anyopaque,
    memType: u8, // used to define which type mem is
    // registers
    a: u16,
    x: u16,
    y: u16,
    sp: u16,
    pc: u16,
    dp: u16, // direct page (D)
    k: u8, // program bank (PB)
    db: u8, // data bank (B)
    // flags
    c: bool,
    z: bool,
    v: bool,
    n: bool,
    i: bool,
    d: bool,
    xf: bool,
    mf: bool,
    e: bool,
    // interrupts
    irqWanted: bool,
    nmiWanted: bool,
    // power state (WAI/STP)
    waiting: bool,
    stopped: bool,
    // internal use
    cyclesUsed: u8, // indicates how many cycles an opcode used
    spBreakpoint: u16,
    in_emu: bool,
};

const testing = std.testing;

test "Cpu layout matches cpu.h" {
    // Offsets taken from the C compiler on this target.
    if (@sizeOf(*anyopaque) != 8) return error.SkipZigTest;
    try testing.expectEqual(48, @sizeOf(Cpu));
    try testing.expectEqual(8, @offsetOf(Cpu, "memType"));
    try testing.expectEqual(10, @offsetOf(Cpu, "a"));
    try testing.expectEqual(16, @offsetOf(Cpu, "sp"));
    try testing.expectEqual(18, @offsetOf(Cpu, "pc"));
    try testing.expectEqual(22, @offsetOf(Cpu, "k"));
    try testing.expectEqual(23, @offsetOf(Cpu, "db"));
    try testing.expectEqual(24, @offsetOf(Cpu, "c"));
    try testing.expectEqual(33, @offsetOf(Cpu, "irqWanted"));
    try testing.expectEqual(35, @offsetOf(Cpu, "waiting"));
    try testing.expectEqual(37, @offsetOf(Cpu, "cyclesUsed"));
    try testing.expectEqual(38, @offsetOf(Cpu, "spBreakpoint"));
    try testing.expectEqual(40, @offsetOf(Cpu, "in_emu"));
}
