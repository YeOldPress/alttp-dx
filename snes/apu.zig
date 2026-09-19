//! Port of snes/apu.c: the SPC700's bus, timers and boot ROM.
const std = @import("std");
const snes_types = @import("snes_types.zig");

const SaveLoadFunc = snes_types.SaveLoadFunc;

/// Still implemented in C; only ever held as a pointer here.
const Spc = opaque {};
const Dsp = opaque {};

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn memset(dst: [*]u8, val: c_int, n: usize) [*]u8;

extern fn spc_init(apu: *Apu) *Spc;
extern fn spc_free(spc: *Spc) void;
extern fn spc_reset(spc: *Spc) void;
extern fn spc_runOpcode(spc: *Spc) c_int;
extern fn spc_saveload(spc: *Spc, func: *const SaveLoadFunc, ctx: ?*anyopaque) void;

extern fn dsp_init(apu_ram: [*]u8) *Dsp;
extern fn dsp_free(dsp: *Dsp) void;
extern fn dsp_reset(dsp: *Dsp) void;
extern fn dsp_cycle(dsp: *Dsp) void;
extern fn dsp_read(dsp: *Dsp, adr: u8) u8;
extern fn dsp_write(dsp: *Dsp, adr: u8, val: u8) void;
extern fn dsp_saveload(dsp: *Dsp, func: *const SaveLoadFunc, ctx: ?*anyopaque) void;

/// Must match `struct Timer` in apu.h.
pub const Timer = extern struct {
    cycles: u8,
    divider: u8,
    target: u8,
    counter: u8,
    enabled: bool,
};

/// Must match `struct DspRegWriteHistory` in dsp.h.
pub const DspRegWriteHistory = extern struct {
    count: u32,
    addr: [256]u8,
    val: [256]u8,
};

/// The C struct ends in an anonymous union that pads the history out to a
/// pointer boundary; naming it here does not change the layout.
pub const HistUnion = extern union {
    hist: DspRegWriteHistory,
    padpad: ?*anyopaque,
};

/// Must match `struct Apu` in apu.h.
pub const Apu = extern struct {
    spc: ?*Spc,
    dsp: ?*Dsp,
    ram: [0x10000]u8,
    romReadable: bool,
    dspAdr: u8,
    cycles: u32,
    inPorts: [6]u8, // includes 2 bytes of ram
    outPorts: [4]u8,
    timer: [3]Timer,
    cpuCyclesLeft: u8,
    u: HistUnion,
};

const bootRom = [0x40]u8{
    0xcd, 0xef, 0xbd, 0xe8, 0x00, 0xc6, 0x1d, 0xd0, 0xfc, 0x8f, 0xaa, 0xf4, 0x8f, 0xbb, 0xf5, 0x78,
    0xcc, 0xf4, 0xd0, 0xfb, 0x2f, 0x19, 0xeb, 0xf4, 0xd0, 0xfc, 0x7e, 0xf4, 0xd0, 0x0b, 0xe4, 0xf5,
    0xcb, 0xf4, 0xd7, 0x00, 0xfc, 0xd0, 0xf3, 0xab, 0x01, 0x10, 0xef, 0x7e, 0xf4, 0x10, 0xeb, 0xba,
    0xf6, 0xda, 0x00, 0xba, 0xf4, 0xc4, 0xf4, 0xdd, 0x5d, 0xd0, 0xdb, 0x1f, 0x00, 0x00, 0xc0, 0xff,
};

pub export fn apu_init() callconv(.c) *Apu {
    const apu: *Apu = @ptrCast(@alignCast(malloc(@sizeOf(Apu)).?));
    apu.spc = spc_init(apu);
    apu.dsp = dsp_init(&apu.ram);
    return apu;
}

pub export fn apu_free(apu: *Apu) callconv(.c) void {
    spc_free(apu.spc.?);
    dsp_free(apu.dsp.?);
    free(apu);
}

pub export fn apu_saveload(apu: *Apu, func: *const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    func(ctx, &apu.ram, @offsetOf(Apu, "u") - @offsetOf(Apu, "ram"));
    dsp_saveload(apu.dsp.?, func, ctx);
    spc_saveload(apu.spc.?, func, ctx);
}

pub export fn apu_reset(apu: *Apu) callconv(.c) void {
    apu.romReadable = true; // before resetting spc, because it reads reset vector from it
    spc_reset(apu.spc.?);
    dsp_reset(apu.dsp.?);
    @memset(&apu.ram, 0);
    apu.dspAdr = 0;
    apu.cycles = 0;
    @memset(&apu.inPorts, 0);
    @memset(&apu.outPorts, 0);
    for (&apu.timer) |*t| {
        t.cycles = 0;
        t.divider = 0;
        t.target = 0;
        t.counter = 0;
        t.enabled = false;
    }
    apu.cpuCyclesLeft = 7;
    apu.u.hist.count = 0;
}

pub export fn apu_cycle(apu: *Apu) callconv(.c) void {
    if (apu.cpuCyclesLeft == 0) {
        apu.cpuCyclesLeft = @truncate(@as(u32, @bitCast(spc_runOpcode(apu.spc.?))));
    }
    apu.cpuCyclesLeft -%= 1;

    if (apu.cycles & 0x1f == 0) {
        // every 32 cycles
        dsp_cycle(apu.dsp.?);
    }

    // handle timers
    for (&apu.timer, 0..) |*t, i| {
        if (t.cycles == 0) {
            t.cycles = if (i == 2) 16 else 128;
            if (t.enabled) {
                t.divider +%= 1;
                if (t.divider == t.target) {
                    t.divider = 0;
                    t.counter +%= 1;
                    t.counter &= 0xf;
                }
            }
        }
        t.cycles -%= 1;
    }

    apu.cycles +%= 1;
}

pub export fn apu_cpuRead(apu: *Apu, adr: u16) callconv(.c) u8 {
    switch (adr) {
        0xf0, 0xf1, 0xfa, 0xfb, 0xfc => return 0,
        0xf2 => return apu.dspAdr,
        0xf3 => return dsp_read(apu.dsp.?, apu.dspAdr & 0x7f),
        0xf4...0xf9 => return apu.inPorts[adr - 0xf4],
        0xfd...0xff => {
            const t = &apu.timer[adr - 0xfd];
            const ret = t.counter;
            t.counter = 0;
            return ret;
        },
        else => {},
    }
    if (apu.romReadable and adr >= 0xffc0) {
        return bootRom[adr - 0xffc0];
    }
    return apu.ram[adr];
}

pub export fn apu_cpuWrite(apu: *Apu, adr: u16, val: u8) callconv(.c) void {
    switch (adr) {
        0xf0 => {}, // test register
        0xf1 => {
            for (&apu.timer, 0..) |*t, i| {
                const bit = val & (@as(u8, 1) << @intCast(i)) != 0;
                if (!t.enabled and bit) {
                    t.divider = 0;
                    t.counter = 0;
                }
                t.enabled = bit;
            }
            if (val & 0x10 != 0) {
                apu.inPorts[0] = 0;
                apu.inPorts[1] = 0;
            }
            if (val & 0x20 != 0) {
                apu.inPorts[2] = 0;
                apu.inPorts[3] = 0;
            }
            apu.romReadable = val & 0x80 != 0;
        },
        0xf2 => apu.dspAdr = val,
        0xf3 => {
            const i = apu.u.hist.count;
            if (i != 256) {
                apu.u.hist.count = i + 1;
                apu.u.hist.addr[i] = apu.dspAdr;
                apu.u.hist.val[i] = val;
            }
            if (apu.dspAdr < 0x80) dsp_write(apu.dsp.?, apu.dspAdr, val);
        },
        0xf4...0xf7 => apu.outPorts[adr - 0xf4] = val,
        0xf8, 0xf9 => apu.inPorts[adr - 0xf4] = val,
        0xfa...0xfc => apu.timer[adr - 0xfa].target = val,
        else => {},
    }
    apu.ram[adr] = val;
}

const testing = std.testing;

/// The Apu is 64k of ram plus change, so keep it off the stack.
fn testApu() !*Apu {
    const apu = try testing.allocator.create(Apu);
    apu.* = std.mem.zeroes(Apu);
    return apu;
}

test "the cpu ports are one-way in each direction" {
    const apu = try testApu();
    defer testing.allocator.destroy(apu);

    // f4-f7 write to the ports the main cpu reads.
    apu_cpuWrite(apu, 0xf5, 0x42);
    try testing.expectEqual(@as(u8, 0x42), apu.outPorts[1]);
    // Reading f4-f9 sees what the main cpu wrote, not what the spc wrote.
    apu.inPorts[1] = 0x99;
    try testing.expectEqual(@as(u8, 0x99), apu_cpuRead(apu, 0xf5));
    // f8/f9 are plain ram from the spc's side.
    apu_cpuWrite(apu, 0xf8, 0x11);
    try testing.expectEqual(@as(u8, 0x11), apu_cpuRead(apu, 0xf8));
}

test "control register f1 resets timers and clears port latches" {
    const apu = try testApu();
    defer testing.allocator.destroy(apu);

    apu.timer[0].divider = 5;
    apu.timer[0].counter = 7;
    apu.inPorts = .{ 1, 2, 3, 4, 5, 6 };

    apu_cpuWrite(apu, 0xf1, 0x01 | 0x10);
    try testing.expect(apu.timer[0].enabled);
    try testing.expectEqual(@as(u8, 0), apu.timer[0].divider);
    try testing.expectEqual(@as(u8, 0), apu.timer[0].counter);
    try testing.expect(!apu.timer[1].enabled);
    // 0x10 clears ports 0/1 only.
    try testing.expectEqualSlices(u8, &.{ 0, 0, 3, 4, 5, 6 }, &apu.inPorts);

    // Re-enabling an already enabled timer must not reset its divider.
    apu.timer[0].divider = 3;
    apu_cpuWrite(apu, 0xf1, 0x01);
    try testing.expectEqual(@as(u8, 3), apu.timer[0].divider);
}

test "timer counters read back once and then clear" {
    const apu = try testApu();
    defer testing.allocator.destroy(apu);

    apu.timer[0].counter = 9;
    try testing.expectEqual(@as(u8, 9), apu_cpuRead(apu, 0xfd));
    try testing.expectEqual(@as(u8, 0), apu_cpuRead(apu, 0xfd));
    // fa-fc set the targets, and read back as zero.
    apu_cpuWrite(apu, 0xfb, 0x20);
    try testing.expectEqual(@as(u8, 0x20), apu.timer[1].target);
    try testing.expectEqual(@as(u8, 0), apu_cpuRead(apu, 0xfb));
}

test "the boot rom shadows the top of ram only while enabled" {
    const apu = try testApu();
    defer testing.allocator.destroy(apu);

    apu.ram[0xffc0] = 0x55;
    apu.romReadable = true;
    try testing.expectEqual(@as(u8, 0xcd), apu_cpuRead(apu, 0xffc0));
    try testing.expectEqual(@as(u8, 0xff), apu_cpuRead(apu, 0xffff));
    // Writes always land in ram underneath the rom.
    apu_cpuWrite(apu, 0xffc0, 0x66);
    try testing.expectEqual(@as(u8, 0xcd), apu_cpuRead(apu, 0xffc0));
    apu.romReadable = false;
    try testing.expectEqual(@as(u8, 0x66), apu_cpuRead(apu, 0xffc0));
    // Clearing bit 7 of f1 turns the rom off.
    apu.romReadable = true;
    apu_cpuWrite(apu, 0xf1, 0x00);
    try testing.expect(!apu.romReadable);
}

test "dsp register writes are recorded until the history fills" {
    const apu = try testApu();
    defer testing.allocator.destroy(apu);

    // dspAdr >= 0x80 is recorded but not forwarded to the dsp.
    apu_cpuWrite(apu, 0xf2, 0x80);
    try testing.expectEqual(@as(u8, 0x80), apu_cpuRead(apu, 0xf2));
    apu_cpuWrite(apu, 0xf3, 0x777 & 0xff);
    try testing.expectEqual(@as(u32, 1), apu.u.hist.count);
    try testing.expectEqual(@as(u8, 0x80), apu.u.hist.addr[0]);

    apu.u.hist.count = 256;
    apu_cpuWrite(apu, 0xf3, 0x12);
    try testing.expectEqual(@as(u32, 256), apu.u.hist.count); // saturates, no overflow
}

test "Apu layout matches apu.h" {
    // Offsets taken from the C compiler on this target. spc.c and dsp.c still
    // reach into this struct, so the layout has to agree exactly.
    if (@sizeOf(*anyopaque) != 8) return error.SkipZigTest;
    try testing.expectEqual(5, @sizeOf(Timer));
    try testing.expectEqual(516, @sizeOf(DspRegWriteHistory));
    try testing.expectEqual(66112, @sizeOf(Apu));
    try testing.expectEqual(16, @offsetOf(Apu, "ram"));
    try testing.expectEqual(65552, @offsetOf(Apu, "romReadable"));
    try testing.expectEqual(65556, @offsetOf(Apu, "cycles"));
    try testing.expectEqual(65560, @offsetOf(Apu, "inPorts"));
    try testing.expectEqual(65566, @offsetOf(Apu, "outPorts"));
    try testing.expectEqual(65570, @offsetOf(Apu, "timer"));
    try testing.expectEqual(65585, @offsetOf(Apu, "cpuCyclesLeft"));
    try testing.expectEqual(65592, @offsetOf(Apu, "u"));
    // The block apu_saveload hands to the save file.
    try testing.expectEqual(65576, @offsetOf(Apu, "u") - @offsetOf(Apu, "ram"));
}
