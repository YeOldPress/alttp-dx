//! Port of snes/snes.c: the bus, the internal CPU registers and the glue that
//! holds the chips together.
const std = @import("std");
const snes_types = @import("snes_types.zig");
const apu_mod = @import("apu.zig");
const dma_mod = @import("dma.zig");
const cart_mod = @import("cart.zig");
const input_mod = @import("input.zig");
const cpu_types = @import("cpu_types.zig");
const ppu_types = @import("ppu_types.zig");

const Snes = snes_types.Snes;
const SaveLoadFunc = snes_types.SaveLoadFunc;
const Cpu = cpu_types.Cpu;
const Ppu = ppu_types.Ppu;
const Apu = apu_mod.Apu;
const Dma = dma_mod.Dma;
const Cart = cart_mod.Cart;
const Input = input_mod.Input;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn printf(fmt: [*:0]const u8, ...) c_int;
extern fn fflush(f: ?*anyopaque) c_int;

// Still in C.
extern fn cpu_init(mem: *Snes, memType: c_int) *Cpu;
extern fn cpu_free(cpu: *Cpu) void;
extern fn cpu_reset(cpu: *Cpu) void;
extern fn cpu_saveload(cpu: *Cpu, func: *const SaveLoadFunc, ctx: ?*anyopaque) void;
// ppu.c defines this with no parameters; snes.c passed it a Snes* anyway,
// relying on the empty parameter list in the header.
extern fn ppu_init() *Ppu;
extern fn ppu_free(ppu: *Ppu) void;
extern fn ppu_reset(ppu: *Ppu) void;
extern fn ppu_read(ppu: *Ppu, adr: u8) u8;
extern fn ppu_write(ppu: *Ppu, adr: u8, val: u8) void;
extern fn ppu_saveload(ppu: *Ppu, func: *const SaveLoadFunc, ctx: ?*anyopaque) void;
extern fn getProcessorStateCpu(snes: *Snes, line: [*]u8) void;
extern fn cpu_runOpcode(cpu: *Cpu) c_int;
extern fn ppu_runLine(ppu: *Ppu, line: c_int) void;

// The Snes struct holds its components as bare pointers so that the C headers
// and these modules can be ported independently; these put the types back on.
fn cpuOf(snes: *Snes) *Cpu {
    return @ptrCast(@alignCast(snes.cpu.?));
}

fn apuOf(snes: *Snes) *Apu {
    return @ptrCast(@alignCast(snes.apu.?));
}

fn ppuOf(snes: *Snes) *Ppu {
    return @ptrCast(@alignCast(snes.ppu.?));
}

fn dmaOf(snes: *Snes) *Dma {
    return @ptrCast(@alignCast(snes.dma.?));
}

fn cartOf(snes: *Snes) *Cart {
    return @ptrCast(@alignCast(snes.cart.?));
}

fn input1Of(snes: *Snes) *Input {
    return @ptrCast(@alignCast(snes.input1.?));
}

fn input2Of(snes: *Snes) *Input {
    return @ptrCast(@alignCast(snes.input2.?));
}

pub export fn snes_init(ram: [*]u8) callconv(.c) *Snes {
    const snes: *Snes = @ptrCast(@alignCast(malloc(@sizeOf(Snes)).?));
    snes.ram = ram;
    snes.cpu = cpu_init(snes, 0);
    snes.apu = apu_mod.apu_init();
    snes.dma = dma_mod.dma_init(snes);
    snes.ppu = ppu_init();
    snes.cart = cart_mod.cart_init(snes);
    snes.input1 = input_mod.input_init(@ptrCast(snes));
    snes.input2 = input_mod.input_init(@ptrCast(snes));
    snes.debug_cycles = false;
    snes.disableHpos = false;
    return snes;
}

pub export fn snes_free(snes: *Snes) callconv(.c) void {
    cpu_free(cpuOf(snes));
    apu_mod.apu_free(apuOf(snes));
    dma_mod.dma_free(dmaOf(snes));
    ppu_free(ppuOf(snes));
    cart_mod.cart_free(cartOf(snes));
    input_mod.input_free(input1Of(snes));
    input_mod.input_free(input2Of(snes));
    free(snes);
}

pub export fn snes_saveload(snes: *Snes, func: *const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    cpu_saveload(cpuOf(snes), func, ctx);
    apu_mod.apu_saveload(apuOf(snes), func, ctx);
    dma_mod.dma_saveload(dmaOf(snes), func, ctx);
    ppu_saveload(ppuOf(snes), func, ctx);
    cart_mod.cart_saveload(cartOf(snes), func, ctx);

    // Everything from hPos through openBus inclusive.
    func(ctx, &snes.hPos, @offsetOf(Snes, "openBus") + 1 - @offsetOf(Snes, "hPos"));
    func(ctx, snes.ram, 0x20000);
    func(ctx, &snes.ramAdr, 4);

    snes.disableHpos = false;
}

pub export fn snes_reset(snes: *Snes, hard: bool) callconv(.c) void {
    cart_mod.cart_reset(cartOf(snes)); // reset cart first, because resetting cpu will read from it (reset vector)
    cpu_reset(cpuOf(snes));
    apu_mod.apu_reset(apuOf(snes));
    dma_mod.dma_reset(dmaOf(snes));
    ppu_reset(ppuOf(snes));
    input_mod.input_reset(input1Of(snes));
    input_mod.input_reset(input2Of(snes));
    if (hard) @memset(snes.ram.?[0..0x20000], 0);
    snes.ramAdr = 0;
    snes.hPos = 0;
    snes.vPos = 0;
    snes.frames = 0;
    snes.cpuCyclesLeft = 52; // 5 reads (8) + 2 IntOp (6)
    snes.cpuMemOps = 0;
    snes.apuCatchupCycles = 0.0;
    snes.hIrqEnabled = false;
    snes.vIrqEnabled = false;
    snes.nmiEnabled = false;
    snes.hTimer = 0x1ff;
    snes.vTimer = 0x1ff;
    snes.inNmi = false;
    snes.inIrq = false;
    snes.inVblank = false;
    @memset(&snes.portAutoRead, 0);
    snes.autoJoyRead = false;
    snes.autoJoyTimer = 0;
    snes.ppuLatch = false;
    snes.multiplyA = 0xff;
    snes.multiplyResult = 0xfe01;
    snes.divideA = 0xffff;
    snes.divideResult = 0x101;
    snes.fastMem = false;
    snes.openBus = 0;
}

/// The C keeps a `static FILE *fout` that is only ever set to stdout, so this
/// writes there directly.
pub export fn snes_printCpuLine(snes: *Snes) callconv(.c) void {
    if (snes.debug_cycles) {
        var line: [80]u8 = undefined;
        getProcessorStateCpu(snes, &line);
        _ = printf("%s", &line);
        _ = printf(" 0x%x", @as(c_uint, ppuOf(snes).vram[0]));
        _ = printf("\n");
        _ = fflush(null);
    }
}

fn snes_catchupApu(snes: *Snes) void {
    const catchupCycles: i32 = @intFromFloat(snes.apuCatchupCycles);
    var i: i32 = 0;
    while (i < catchupCycles) : (i += 1) {
        apu_mod.apu_cycle(apuOf(snes));
    }
    snes.apuCatchupCycles -= @floatFromInt(catchupCycles);
}

pub export fn snes_doAutoJoypad(snes: *Snes) callconv(.c) void {
    // TODO: improve? (now calls input_cycle)
    @memset(&snes.portAutoRead, 0);
    const in1 = input1Of(snes);
    const in2 = input2Of(snes);
    in1.latchLine = true;
    in2.latchLine = true;
    input_mod.input_cycle(in1); // latches the controllers
    input_mod.input_cycle(in2);
    in1.latchLine = false;
    in2.latchLine = false;
    for (0..16) |i| {
        const shift: u4 = @intCast(15 - i);
        var val = input_mod.input_read(in1);
        snes.portAutoRead[0] |= @as(u16, val & 1) << shift;
        snes.portAutoRead[2] |= @as(u16, (val >> 1) & 1) << shift;
        val = input_mod.input_read(in2);
        snes.portAutoRead[1] |= @as(u16, val & 1) << shift;
        snes.portAutoRead[3] |= @as(u16, (val >> 1) & 1) << shift;
    }
}

/// The PPU's h/v counters, latched by reading $2137 (or by $4201), then read
/// a byte at a time from $213c/$213d. Vanilla ALttP's random numbers come
/// from these, so a whole-ROM run needs them to be the real thing.
var g_latched_h: u16 = 0;
var g_latched_v: u16 = 0;
var g_counters_latched: bool = false;
var g_h_high: bool = false;
var g_v_high: bool = false;

fn latchCounters(snes: *Snes) void {
    g_latched_h = snes.hPos / 4;
    g_latched_v = snes.vPos;
    g_counters_latched = true;
}

fn counterRead(snes: *Snes, adr: u8) ?u8 {
    switch (adr) {
        0x37 => {
            latchCounters(snes);
            return snes.openBus;
        },
        0x3c => {
            defer g_h_high = !g_h_high;
            return if (g_h_high) @truncate(g_latched_h >> 8) else @truncate(g_latched_h);
        },
        0x3d => {
            defer g_v_high = !g_v_high;
            return if (g_v_high) @truncate(g_latched_v >> 8) else @truncate(g_latched_v);
        },
        0x3e => return 0x01, // STAT77: ppu1 version 1
        0x3f => { // STAT78: resets the byte flip-flops
            const v: u8 = 0x03 | (@as(u8, @intFromBool(g_counters_latched)) << 6);
            g_counters_latched = false;
            g_h_high = false;
            g_v_high = false;
            return v;
        },
        else => return null,
    }
}

pub export fn snes_readBBus(snes: *Snes, adr: u8) callconv(.c) u8 {
    if (adr < 0x40) {
        if (g_accurate_timing) {
            if (counterRead(snes, adr)) |v| return v;
        }
        return ppu_read(ppuOf(snes), adr);
    }
    if (adr < 0x80) {
        // A running game polls these waiting for the sound cpu, so it has to
        // have caught up. (The verification never runs it, so there's no
        // time owed and this does nothing.)
        snes_catchupApu(snes);
        return apuOf(snes).outPorts[adr & 0x3];
    }
    if (adr == 0x80) {
        const ret = snes.ram.?[snes.ramAdr];
        snes.ramAdr = (snes.ramAdr +% 1) & 0x1ffff;
        return ret;
    }
    return snes.openBus;
}

pub export fn snes_writeBBus(snes: *Snes, adr: u8, val: u8) callconv(.c) void {
    if (adr < 0x40) {
        ppu_write(ppuOf(snes), adr, val);
        return;
    }
    if (adr < 0x80) {
        snes_catchupApu(snes); // catch up the apu before writing
        apuOf(snes).inPorts[adr & 0x3] = val;
        return;
    }
    switch (adr) {
        0x80 => {
            snes.ram.?[snes.ramAdr] = val;
            snes.ramAdr = (snes.ramAdr +% 1) & 0x1ffff;
        },
        0x81 => snes.ramAdr = (snes.ramAdr & 0x1ff00) | val,
        0x82 => snes.ramAdr = (snes.ramAdr & 0x100ff) | (@as(u32, val) << 8),
        0x83 => snes.ramAdr = (snes.ramAdr & 0x0ffff) | (@as(u32, val & 1) << 16),
        else => {},
    }
}

fn snes_readReg(snes: *Snes, adr: u16) u8 {
    switch (adr) {
        0x4210 => {
            var val: u8 = 0x2; // CPU version (4 bit)
            val |= @as(u8, @intFromBool(snes.inNmi)) << 7;
            snes.inNmi = false;
            return val | (snes.openBus & 0x70);
        },
        0x4211 => {
            const val = @as(u8, @intFromBool(snes.inIrq)) << 7;
            snes.inIrq = false;
            cpuOf(snes).irqWanted = false;
            return val | (snes.openBus & 0x7f);
        },
        0x4212 => {
            var val: u8 = @intFromBool(snes.autoJoyTimer > 0);
            val |= @as(u8, @intFromBool(snes.hPos >= 1024)) << 6;
            val |= @as(u8, @intFromBool(snes.inVblank)) << 7;
            return val | (snes.openBus & 0x3e);
        },
        0x4213 => return @as(u8, @intFromBool(snes.ppuLatch)) << 7, // IO-port
        0x4214 => return @truncate(snes.divideResult),
        0x4215 => return @truncate(snes.divideResult >> 8),
        0x4216 => return @truncate(snes.multiplyResult),
        0x4217 => return @truncate(snes.multiplyResult >> 8),
        0x4218, 0x421a, 0x421c, 0x421e => {
            return @truncate(snes.portAutoRead[(adr - 0x4218) / 2]);
        },
        0x4219, 0x421b, 0x421d, 0x421f => {
            return @truncate(snes.portAutoRead[(adr - 0x4219) / 2] >> 8);
        },
        else => return snes.openBus,
    }
}

fn snes_writeReg(snes: *Snes, adr: u16, val: u8) void {
    switch (adr) {
        0x4200 => {
            snes.autoJoyRead = val & 0x1 != 0;
            if (!snes.autoJoyRead) snes.autoJoyTimer = 0;
            snes.hIrqEnabled = val & 0x10 != 0;
            snes.vIrqEnabled = val & 0x20 != 0;
            snes.nmiEnabled = val & 0x80 != 0;
            if (!snes.hIrqEnabled and !snes.vIrqEnabled) {
                snes.inIrq = false;
                cpuOf(snes).irqWanted = false;
            }
            // TODO: enabling nmi during vblank with inNmi still set generates nmi
            //   enabling virq (and not h) on the vPos that vTimer is at generates irq (?)
        },
        0x4201 => {
            if ((val & 0x80) == 0 and snes.ppuLatch) {
                // latch the ppu
                if (g_accurate_timing) latchCounters(snes) else _ = ppu_read(ppuOf(snes), 0x37);
            }
            snes.ppuLatch = val & 0x80 != 0;
        },
        0x4202 => snes.multiplyA = val,
        0x4203 => snes.multiplyResult = @as(u16, snes.multiplyA) * val,
        0x4204 => snes.divideA = (snes.divideA & 0xff00) | val,
        0x4205 => snes.divideA = (snes.divideA & 0x00ff) | (@as(u16, val) << 8),
        0x4206 => {
            if (val == 0) {
                snes.divideResult = 0xffff;
                snes.multiplyResult = snes.divideA;
            } else {
                snes.divideResult = snes.divideA / val;
                snes.multiplyResult = snes.divideA % val;
            }
        },
        0x4207 => snes.hTimer = (snes.hTimer & 0x100) | val,
        0x4208 => snes.hTimer = (snes.hTimer & 0x0ff) | (@as(u16, val & 1) << 8),
        0x4209 => snes.vTimer = (snes.vTimer & 0x100) | val,
        0x420a => snes.vTimer = (snes.vTimer & 0x0ff) | (@as(u16, val & 1) << 8),
        0x420b => dma_mod.dma_startDma(dmaOf(snes), val, false),
        0x420c => dma_mod.dma_startDma(dmaOf(snes), val, true),
        0x420d => snes.fastMem = val & 0x1 != 0,
        else => {},
    }
}

/// wrapped by snes_read, to set open bus
/// Hardware on the cartridge beyond ROM and save ram, mapped at $2000-$20ff
/// in the system banks: MSU-1, for a whole-ROM run. Null otherwise.
pub const IoHooks = struct {
    ctx: *anyopaque,
    read: *const fn (ctx: *anyopaque, adr: u16) ?u8,
    write: *const fn (ctx: *anyopaque, adr: u16, val: u8) bool,
};
pub var g_io_hooks: ?IoHooks = null;

fn snes_rread(snes: *Snes, full_adr: u32) u8 {
    const bank: u8 = @truncate(full_adr >> 16);
    const adr: u16 = @truncate(full_adr);
    if (g_io_hooks) |h| {
        if ((bank & 0x7f) < 0x40 and adr >= 0x2000 and adr < 0x2100) {
            if (h.read(h.ctx, adr)) |v| return v;
        }
    }
    if ((bank & 0x7f) < 0x40 and adr < 0x4380) {
        if (adr < 0x2000) {
            return snes.ram.?[adr]; // ram mirror
        }
        if (adr >= 0x2100 and adr < 0x2200) {
            return snes_readBBus(snes, @truncate(adr)); // B-bus
        }
        if (adr == 0x4016) {
            return input_mod.input_read(input1Of(snes)) | (snes.openBus & 0xfc);
        }
        if (adr == 0x4017) {
            return input_mod.input_read(input2Of(snes)) | (snes.openBus & 0xe0) | 0x1c;
        }
        if (adr >= 0x4200 and adr < 0x4220) {
            return snes_readReg(snes, adr); // internal registers
        }
        if (adr >= 0x4300 and adr < 0x4380) {
            return dma_mod.dma_read(dmaOf(snes), adr); // dma registers
        }
    } else if (bank & ~@as(u8, 1) == 0x7e) {
        return snes.ram.?[(@as(u32, bank & 1) << 16) | adr]; // ram
    }

    // read from cart
    return cart_mod.cart_read(cartOf(snes), bank, adr);
}

pub export var g_bp_addr: c_int = 0;

/// The breakpoint tracing the C does around ram writes, kept behind the same
/// g_bp_addr guard (zero, and so off, unless a debugger sets it).
fn traceRamWrite(snes: *Snes, which: c_int, adr: u16, val: u8) void {
    if (adr == g_bp_addr and g_bp_addr != 0) {
        const cpu = cpuOf(snes);
        const ram = snes.ram.?;
        _ = printf(
            "@0x%x: Writing%d 0x%X to 0x%x (frame %d) %.2x %.2x %.2x\n",
            @as(c_int, cpu.k) * 65536 + cpu.pc,
            which,
            @as(c_uint, val),
            @as(c_uint, adr),
            @as(c_uint, ram[0x1a]),
            @as(c_uint, ram[cpu.sp + 1]),
            @as(c_uint, ram[cpu.sp + 2]),
            @as(c_uint, ram[cpu.sp + 3]),
        );
    }
}

pub export fn snes_write(snes: *Snes, full_adr: u32, val: u8) callconv(.c) void {
    snes.openBus = val;
    const bank: u8 = @truncate(full_adr >> 16);
    const adr: u16 = @truncate(full_adr);
    if (bank == 0x7e or bank == 0x7f) {
        traceRamWrite(snes, 1, adr, val);
        snes.ram.?[(@as(u32, bank & 1) << 16) | adr] = val; // ram
    } else if (bank < 0x40 or (bank >= 0x80 and bank < 0xc0)) {
        if (g_io_hooks) |h| {
            if (adr >= 0x2000 and adr < 0x2100 and h.write(h.ctx, adr, val)) return;
        }
        if (adr < 0x2000) {
            traceRamWrite(snes, 2, adr, val);
            snes.ram.?[adr] = val; // ram mirror
        } else if (adr >= 0x2100 and adr < 0x2200) {
            snes_writeBBus(snes, @truncate(adr), val); // B-bus
        } else if (adr == 0x4016) {
            input1Of(snes).latchLine = val & 1 != 0;
            input2Of(snes).latchLine = val & 1 != 0;
        } else if (adr >= 0x4200 and adr < 0x4220) {
            snes_writeReg(snes, adr, val); // internal registers
        } else if (adr >= 0x4300 and adr < 0x4380) {
            dma_mod.dma_write(dmaOf(snes), adr, val); // dma registers
        }
    }
    // write to cart
    cart_mod.cart_write(cartOf(snes), bank, adr, val);
}

/// Real memory speeds, for running a whole ROM on its own (snes_runFrame).
/// The port's verification counts no time, so it leaves this off and every
/// access costs the same.
pub var g_accurate_timing: bool = false;

fn snes_getAccessTime(snes: *Snes, adr_in: u32) c_int {
    if (!g_accurate_timing) return 6;
    const bank: u8 = @truncate(adr_in >> 16);
    const adr: u16 = @truncate(adr_in);
    if ((bank < 0x40 or (bank >= 0x80 and bank < 0xc0)) and adr < 0x8000) {
        // 00-3f,80-bf:0000-7fff
        if (adr < 0x2000 or adr >= 0x6000) return 8; // ram, and cart space
        if (adr < 0x4000 or adr >= 0x4200) return 6; // the b-bus, and cpu registers
        return 12; // the old style joypad ports
    }
    // Everything else is cart space: fast in banks 80+ when FastROM is on.
    return if (snes.fastMem and bank >= 0x80) 6 else 8;
}

// ------------------------------------------------------ running a frame

/// The APU runs off its own crystal; this is its share of each master cycle.
const kApuCyclesPerMaster: f64 = (32040.0 * 32.0) / (1364.0 * 262.0 * 60.0);

/// Runs the whole machine for one frame, from the top of this one to the top
/// of the next, the way LakeSnes did before the port trimmed it to what
/// verification needed. The ppu renders into whatever PpuBeginDrawing set up.
pub export fn snes_runFrame(snes: *Snes) callconv(.c) void {
    const frame = snes.frames;
    while (snes.frames == frame) snes_runCycle(snes);
}

/// Two master cycles: the cpu or dma, interrupts, and whatever happens at
/// this point of the scanline.
fn snes_runCycle(snes: *Snes) void {
    snes.apuCatchupCycles += kApuCyclesPerMaster * 2.0;
    // Nothing gets the bus during dram refresh.
    if (snes.hPos < 536 or snes.hPos >= 576) {
        if (!dma_mod.dma_cycle(dmaOf(snes))) snes_runCpu(snes);
    }
    // h/v timer irqs
    const at_h = snes.hPos == 4 * snes.hTimer;
    const at_v = snes.vPos == snes.vTimer;
    const irq = if (snes.hIrqEnabled and snes.vIrqEnabled)
        at_v and at_h
    else if (snes.hIrqEnabled)
        at_h
    else if (snes.vIrqEnabled)
        at_v and snes.hPos == 0
    else
        false;
    if (irq) {
        snes.inIrq = true;
        cpuOf(snes).irqWanted = true;
    }
    switch (snes.hPos) {
        0 => {
            if (snes.vPos == 0) {
                snes.inVblank = false;
                snes.inNmi = false;
                dma_mod.dma_initHdma(dmaOf(snes));
            } else if (snes.vPos == 225) {
                snes.inVblank = true;
                snes.inNmi = true;
                if (snes.autoJoyRead) {
                    snes.autoJoyTimer = 4224;
                    snes_doAutoJoypad(snes);
                }
                if (snes.nmiEnabled) cpuOf(snes).nmiWanted = true;
            }
        },
        // Render the line halfway along, which suits most games.
        512 => if (!snes.inVblank and snes.vPos > 0) ppu_runLine(ppuOf(snes), snes.vPos),
        1104 => if (!snes.inVblank) dma_mod.dma_doHdma(dmaOf(snes)),
        else => {},
    }
    if (snes.autoJoyTimer > 0) snes.autoJoyTimer -= 2;
    snes.hPos += 2;
    if (snes.hPos == 1364) {
        snes.hPos = 0;
        snes.vPos += 1;
        if (snes.vPos == 262) {
            snes.vPos = 0;
            snes.frames +%= 1;
            snes_catchupApu(snes);
        }
    }
}

fn snes_runCpu(snes: *Snes) void {
    if (snes.cpuCyclesLeft == 0) {
        snes.cpuMemOps = 0;
        const cycles: c_int = cpu_runOpcode(cpuOf(snes));
        // Memory accesses already charged their own time; the rest are
        // internal operations at 6 master cycles each.
        const internal = cycles - @as(c_int, snes.cpuMemOps);
        snes.cpuCyclesLeft +%= @intCast(@max(internal, 0) * 6);
    }
    snes.cpuCyclesLeft -|= 2;
}

pub export fn snes_read(snes: *Snes, adr: u32) callconv(.c) u8 {
    const val = snes_rread(snes, adr);
    snes.openBus = val;
    return val;
}

pub export fn snes_cpuRead(snes: *Snes, adr: u32) callconv(.c) u8 {
    snes.cpuMemOps +%= 1;
    snes.cpuCyclesLeft +%= @intCast(snes_getAccessTime(snes, adr));
    return snes_read(snes, adr);
}

pub export fn snes_cpuWrite(snes: *Snes, adr: u32, val: u8) callconv(.c) void {
    snes.cpuMemOps +%= 1;
    snes.cpuCyclesLeft +%= @intCast(snes_getAccessTime(snes, adr));
    snes_write(snes, adr, val);
}

const testing = std.testing;

/// A Snes wired up with just the parts these tests touch: ram, the two
/// controllers, a cpu and an unloaded cart. The ppu and apu are left null, so
/// tests must stay off the B-bus below $2180.
const TestSnes = struct {
    snes: *Snes,
    ram: *[0x20000]u8,
    cpu: *Cpu,
    cart: *Cart,
    in1: *Input,
    in2: *Input,

    fn init() !TestSnes {
        const ram = try testing.allocator.create([0x20000]u8);
        @memset(ram, 0);
        const cpu = try testing.allocator.create(Cpu);
        cpu.* = std.mem.zeroes(Cpu);
        const cart = try testing.allocator.create(Cart);
        cart.* = std.mem.zeroes(Cart); // type 0: nothing mapped
        const in1 = try testing.allocator.create(Input);
        in1.* = std.mem.zeroes(Input);
        const in2 = try testing.allocator.create(Input);
        in2.* = std.mem.zeroes(Input);
        const snes = try testing.allocator.create(Snes);
        snes.* = std.mem.zeroes(Snes);
        snes.ram = ram;
        snes.cpu = cpu;
        snes.cart = cart;
        snes.input1 = in1;
        snes.input2 = in2;
        cart.snes = snes;
        return .{ .snes = snes, .ram = ram, .cpu = cpu, .cart = cart, .in1 = in1, .in2 = in2 };
    }

    fn deinit(self: TestSnes) void {
        testing.allocator.destroy(self.snes);
        testing.allocator.destroy(self.ram);
        testing.allocator.destroy(self.cpu);
        testing.allocator.destroy(self.cart);
        testing.allocator.destroy(self.in1);
        testing.allocator.destroy(self.in2);
    }
};

test "the low 8k of every low bank mirrors work ram" {
    const t = try TestSnes.init();
    defer t.deinit();

    snes_write(t.snes, 0x00_0100, 0x42);
    try testing.expectEqual(@as(u8, 0x42), t.ram[0x100]);
    try testing.expectEqual(@as(u8, 0x42), snes_read(t.snes, 0x00_0100));
    // The same byte is visible through bank $80 and through $7e.
    try testing.expectEqual(@as(u8, 0x42), snes_read(t.snes, 0x80_0100));
    try testing.expectEqual(@as(u8, 0x42), snes_read(t.snes, 0x7e_0100));
    // Bank $7f is the upper half of work ram.
    snes_write(t.snes, 0x7f_0000, 0x99);
    try testing.expectEqual(@as(u8, 0x99), t.ram[0x10000]);
}

test "the wram port auto-increments and wraps at 128k" {
    const t = try TestSnes.init();
    defer t.deinit();

    // Point the port at $01fffe via $2181-$2183.
    snes_write(t.snes, 0x00_2181, 0xfe);
    snes_write(t.snes, 0x00_2182, 0xff);
    snes_write(t.snes, 0x00_2183, 0x01);
    try testing.expectEqual(@as(u32, 0x1fffe), t.snes.ramAdr);

    snes_write(t.snes, 0x00_2180, 0xaa);
    snes_write(t.snes, 0x00_2180, 0xbb);
    snes_write(t.snes, 0x00_2180, 0xcc); // wraps back to 0
    try testing.expectEqual(@as(u8, 0xaa), t.ram[0x1fffe]);
    try testing.expectEqual(@as(u8, 0xbb), t.ram[0x1ffff]);
    try testing.expectEqual(@as(u8, 0xcc), t.ram[0]);
    try testing.expectEqual(@as(u32, 1), t.snes.ramAdr);

    t.snes.ramAdr = 0x1fffe;
    try testing.expectEqual(@as(u8, 0xaa), snes_read(t.snes, 0x00_2180));
    try testing.expectEqual(@as(u8, 0xbb), snes_read(t.snes, 0x00_2180));
    try testing.expectEqual(@as(u8, 0xcc), snes_read(t.snes, 0x00_2180));
}

test "the multiplier and divider registers" {
    const t = try TestSnes.init();
    defer t.deinit();

    snes_write(t.snes, 0x00_4202, 0x10); // WRMPYA
    snes_write(t.snes, 0x00_4203, 0x20); // WRMPYB starts the multiply
    try testing.expectEqual(@as(u16, 0x200), t.snes.multiplyResult);
    try testing.expectEqual(@as(u8, 0x00), snes_read(t.snes, 0x00_4216));
    try testing.expectEqual(@as(u8, 0x02), snes_read(t.snes, 0x00_4217));

    snes_write(t.snes, 0x00_4204, 0x64); // WRDIV = 100
    snes_write(t.snes, 0x00_4205, 0x00);
    snes_write(t.snes, 0x00_4206, 7); // divide by 7
    try testing.expectEqual(@as(u16, 14), t.snes.divideResult);
    try testing.expectEqual(@as(u16, 2), t.snes.multiplyResult); // remainder
    try testing.expectEqual(@as(u8, 14), snes_read(t.snes, 0x00_4214));

    // Dividing by zero gives all ones and leaves the dividend in the product.
    snes_write(t.snes, 0x00_4206, 0);
    try testing.expectEqual(@as(u16, 0xffff), t.snes.divideResult);
    try testing.expectEqual(@as(u16, 100), t.snes.multiplyResult);
}

test "NMITIMEN enables interrupts and clears pending irq when disabled" {
    const t = try TestSnes.init();
    defer t.deinit();

    snes_write(t.snes, 0x00_4200, 0x81); // nmi + auto joypad
    try testing.expect(t.snes.nmiEnabled);
    try testing.expect(t.snes.autoJoyRead);
    try testing.expect(!t.snes.hIrqEnabled);

    t.snes.inIrq = true;
    t.cpu.irqWanted = true;
    snes_write(t.snes, 0x00_4200, 0x00); // both irq sources off
    try testing.expect(!t.snes.inIrq);
    try testing.expect(!t.cpu.irqWanted);
    try testing.expect(!t.snes.autoJoyRead);
}

test "RDNMI and TIMEUP report and then clear their flags" {
    const t = try TestSnes.init();
    defer t.deinit();

    t.snes.inNmi = true;
    const rdnmi = snes_read(t.snes, 0x00_4210);
    try testing.expectEqual(@as(u8, 0x82), rdnmi & 0x8f); // flag + version 2
    try testing.expect(!t.snes.inNmi);
    try testing.expectEqual(@as(u8, 0x02), snes_read(t.snes, 0x00_4210) & 0x8f);

    t.snes.inIrq = true;
    t.cpu.irqWanted = true;
    try testing.expectEqual(@as(u8, 0x80), snes_read(t.snes, 0x00_4211) & 0x80);
    try testing.expect(!t.snes.inIrq);
    try testing.expect(!t.cpu.irqWanted);
}

test "HVBJOY reports vblank and the joypad timer" {
    const t = try TestSnes.init();
    defer t.deinit();

    t.snes.inVblank = true;
    t.snes.autoJoyTimer = 3;
    t.snes.hPos = 2000;
    const val = snes_read(t.snes, 0x00_4212);
    try testing.expectEqual(@as(u8, 0xc1), val & 0xc1);

    t.snes.inVblank = false;
    t.snes.autoJoyTimer = 0;
    t.snes.hPos = 0;
    try testing.expectEqual(@as(u8, 0), snes_read(t.snes, 0x00_4212) & 0xc1);
}

test "the h and v timers are nine bits wide" {
    const t = try TestSnes.init();
    defer t.deinit();

    snes_write(t.snes, 0x00_4207, 0xff);
    snes_write(t.snes, 0x00_4208, 0xff); // only bit 0 counts
    try testing.expectEqual(@as(u16, 0x1ff), t.snes.hTimer);
    snes_write(t.snes, 0x00_4209, 0x34);
    snes_write(t.snes, 0x00_420a, 0x00);
    try testing.expectEqual(@as(u16, 0x034), t.snes.vTimer);
}

test "auto joypad read shifts both controllers into the port registers" {
    const t = try TestSnes.init();
    defer t.deinit();

    // The latch is clocked out lowest bit first, while the port register is
    // filled highest bit first, so the bit order comes out reversed.
    t.in1.currentState = 0x9000; // bits 15 and 12
    t.in2.currentState = 0x4000; // bit 14
    snes_doAutoJoypad(t.snes);

    try testing.expectEqual(@as(u16, 0x0009), t.snes.portAutoRead[0]); // bits 0 and 3
    try testing.expectEqual(@as(u16, 0x0002), t.snes.portAutoRead[1]); // bit 1
    // Nothing is wired to the second data line of either port.
    try testing.expectEqual(@as(u16, 0), t.snes.portAutoRead[2]);
    try testing.expectEqual(@as(u16, 0), t.snes.portAutoRead[3]);

    // And the cpu reads them back a byte at a time.
    try testing.expectEqual(@as(u8, 0x09), snes_read(t.snes, 0x00_4218));
    try testing.expectEqual(@as(u8, 0x00), snes_read(t.snes, 0x00_4219));
    try testing.expectEqual(@as(u8, 0x02), snes_read(t.snes, 0x00_421a));
}

test "writing $4016 latches both controllers" {
    const t = try TestSnes.init();
    defer t.deinit();

    t.in1.currentState = 0x00ff;
    snes_write(t.snes, 0x00_4016, 1);
    try testing.expect(t.in1.latchLine);
    try testing.expect(t.in2.latchLine);
    input_mod.input_cycle(t.in1);
    snes_write(t.snes, 0x00_4016, 0);
    try testing.expect(!t.in1.latchLine);
    // Serial reads clock the latched state out, low bit first.
    try testing.expectEqual(@as(u8, 1), snes_read(t.snes, 0x00_4016) & 1);
}

test "unmapped register reads return open bus" {
    const t = try TestSnes.init();
    defer t.deinit();

    snes_write(t.snes, 0x00_0000, 0x5a); // any write sets open bus
    try testing.expectEqual(@as(u8, 0x5a), t.snes.openBus);
    try testing.expectEqual(@as(u8, 0x5a), snes_read(t.snes, 0x00_421f + 1));
}

test "cpu accesses charge cycles" {
    const t = try TestSnes.init();
    defer t.deinit();

    t.snes.cpuCyclesLeft = 0;
    t.snes.cpuMemOps = 0;
    _ = snes_cpuRead(t.snes, 0x00_0100);
    try testing.expectEqual(@as(u8, 6), t.snes.cpuCyclesLeft);
    try testing.expectEqual(@as(u8, 1), t.snes.cpuMemOps);
    snes_cpuWrite(t.snes, 0x00_0100, 1);
    try testing.expectEqual(@as(u8, 12), t.snes.cpuCyclesLeft);
    try testing.expectEqual(@as(u8, 2), t.snes.cpuMemOps);
}

test "snes_saveload hands over the right slice of state" {
    // hPos through openBus inclusive is what the C computes with offsetof.
    try testing.expectEqual(58, @offsetOf(Snes, "openBus") + 1 - @offsetOf(Snes, "hPos"));
}
