//! Port of snes/cpu.c: the 65816 core, including the game-specific brk hooks
//! that patch over places where the original ROM relies on uninitialised state.
const std = @import("std");
const snes_types = @import("snes_types.zig");
const snes_mod = @import("snes.zig");
const cpu_types = @import("cpu_types.zig");

const Snes = snes_types.Snes;
const SaveLoadFunc = snes_types.SaveLoadFunc;
const Cpu = cpu_types.Cpu;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn printf(fmt: [*:0]const u8, ...) c_int;

/// Defined in src/zelda_cpu_infra.c, which is still C.
extern fn HookedFunctionRts(is_long: c_int) void;

const cyclesPerOpcode = [256]u8{
    7, 6, 7, 4, 5, 3, 5, 6, 3, 2, 2, 4, 6, 4, 6, 5,
    2, 5, 5, 7, 5, 4, 6, 6, 2, 4, 2, 2, 6, 4, 7, 5,
    6, 6, 8, 4, 3, 3, 5, 6, 4, 2, 2, 5, 4, 4, 6, 5,
    2, 5, 5, 7, 4, 4, 6, 6, 2, 4, 2, 2, 4, 4, 7, 5,
    6, 6, 2, 4, 7, 3, 5, 6, 3, 2, 2, 3, 3, 4, 6, 5,
    2, 5, 5, 7, 7, 4, 6, 6, 2, 4, 3, 2, 4, 4, 7, 5,
    6, 6, 6, 4, 3, 3, 5, 6, 4, 2, 2, 6, 5, 4, 6, 5,
    2, 5, 5, 7, 4, 4, 6, 6, 2, 4, 4, 2, 6, 4, 7, 5,
    3, 6, 4, 4, 3, 3, 3, 6, 2, 2, 2, 3, 4, 4, 4, 5,
    2, 6, 5, 7, 4, 4, 4, 6, 2, 5, 2, 2, 4, 5, 5, 5,
    2, 6, 2, 4, 3, 3, 3, 6, 2, 2, 2, 4, 4, 4, 4, 5,
    2, 5, 5, 7, 4, 4, 4, 6, 2, 4, 2, 2, 4, 4, 4, 5,
    2, 6, 3, 4, 3, 3, 5, 6, 2, 2, 2, 3, 4, 4, 6, 5,
    2, 5, 5, 7, 6, 4, 6, 6, 2, 4, 3, 3, 6, 4, 7, 5,
    2, 6, 3, 4, 3, 3, 5, 6, 2, 2, 2, 3, 4, 4, 6, 5,
    2, 5, 5, 7, 5, 4, 6, 6, 2, 4, 4, 2, 8, 4, 7, 5,
};

/// cpu->mem is always a Snes here; the void* is a leftover from the emulator
/// this core was lifted from.
fn snesOf(cpu: *Cpu) *Snes {
    return @ptrCast(@alignCast(cpu.mem.?));
}

fn cpu_read(cpu: *Cpu, adr: u32) u8 {
    return snes_mod.snes_cpuRead(snesOf(cpu), adr);
}

fn cpu_write(cpu: *Cpu, adr: u32, val: u8) void {
    snes_mod.snes_cpuWrite(snesOf(cpu), adr, val);
}

pub export fn cpu_init(mem: *anyopaque, memType: c_int) callconv(.c) *Cpu {
    const cpu: *Cpu = @ptrCast(@alignCast(malloc(@sizeOf(Cpu)).?));
    cpu.mem = mem;
    cpu.memType = @truncate(@as(c_uint, @bitCast(memType)));
    return cpu;
}

pub export fn cpu_free(cpu: *Cpu) callconv(.c) void {
    free(cpu);
}

pub export fn cpu_reset(cpu: *Cpu) callconv(.c) void {
    cpu.a = 0;
    cpu.x = 0;
    cpu.y = 0;
    cpu.sp = 0x100;
    cpu.pc = @as(u16, cpu_read(cpu, 0xfffc)) | (@as(u16, cpu_read(cpu, 0xfffd)) << 8);
    cpu.dp = 0;
    cpu.k = 0;
    cpu.db = 0;
    cpu.c = false;
    cpu.z = false;
    cpu.v = false;
    cpu.n = false;
    cpu.i = true;
    cpu.d = false;
    cpu.xf = true;
    cpu.mf = true;
    cpu.e = true;
    cpu.irqWanted = false;
    cpu.nmiWanted = false;
    cpu.waiting = false;
    cpu.stopped = false;
    cpu.cyclesUsed = 0;
    cpu.spBreakpoint = 0x0;
    cpu.in_emu = false;
}

pub export fn cpu_saveload(cpu: *Cpu, func: *const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    func(ctx, &cpu.a, @offsetOf(Cpu, "cyclesUsed") - @offsetOf(Cpu, "a"));
    cpu.spBreakpoint = 0x0;
}

pub export fn cpu_runOpcode(cpu: *Cpu) callconv(.c) c_int {
    cpu.cyclesUsed = 0;
    if (cpu.stopped) return 1;
    if (cpu.waiting) {
        if (cpu.irqWanted or cpu.nmiWanted) {
            cpu.waiting = false;
        }
        return 1;
    }
    // not stopped or waiting, execute a opcode or go to interrupt
    if ((!cpu.i and cpu.irqWanted) or cpu.nmiWanted) {
        if (cpu.in_emu) {
            _ = printf("nmi while in emu!\n");
        }

        cpu.cyclesUsed = 7; // interrupt: at least 7 cycles
        if (cpu.nmiWanted) {
            cpu.nmiWanted = false;
            cpu_doInterrupt(cpu, false);
        } else {
            // must be irq
            cpu_doInterrupt(cpu, true);
        }
    } else {
        const opcode = cpu_readOpcode(cpu);
        cpu.cyclesUsed = cyclesPerOpcode[opcode];
        cpu_doOpcode(cpu, opcode);
    }
    return cpu.cyclesUsed;
}

fn cpu_readOpcode(cpu: *Cpu) u8 {
    const adr = (@as(u32, cpu.k) << 16) | cpu.pc;
    cpu.pc +%= 1;
    return cpu_read(cpu, adr);
}

fn cpu_readOpcodeWord(cpu: *Cpu) u16 {
    const low = cpu_readOpcode(cpu);
    return @as(u16, low) | (@as(u16, cpu_readOpcode(cpu)) << 8);
}

pub export fn cpu_getFlags(cpu: *Cpu) callconv(.c) u8 {
    var val: u8 = @as(u8, @intFromBool(cpu.n)) << 7;
    val |= @as(u8, @intFromBool(cpu.v)) << 6;
    val |= @as(u8, @intFromBool(cpu.mf)) << 5;
    val |= @as(u8, @intFromBool(cpu.xf)) << 4;
    val |= @as(u8, @intFromBool(cpu.d)) << 3;
    val |= @as(u8, @intFromBool(cpu.i)) << 2;
    val |= @as(u8, @intFromBool(cpu.z)) << 1;
    val |= @intFromBool(cpu.c);
    return val;
}

pub export fn cpu_setFlags(cpu: *Cpu, val: u8) callconv(.c) void {
    cpu.n = val & 0x80 != 0;
    cpu.v = val & 0x40 != 0;
    cpu.mf = val & 0x20 != 0;
    cpu.xf = val & 0x10 != 0;
    cpu.d = val & 8 != 0;
    cpu.i = val & 4 != 0;
    cpu.z = val & 2 != 0;
    cpu.c = val & 1 != 0;
    if (cpu.e) {
        cpu.mf = true;
        cpu.xf = true;
        cpu.sp = (cpu.sp & 0xff) | 0x100;
    }
    if (cpu.xf) {
        cpu.x &= 0xff;
        cpu.y &= 0xff;
    }
}

fn cpu_setZN(cpu: *Cpu, value: u16, byte: bool) void {
    if (byte) {
        cpu.z = (value & 0xff) == 0;
        cpu.n = value & 0x80 != 0;
    } else {
        cpu.z = value == 0;
        cpu.n = value & 0x8000 != 0;
    }
}

fn cpu_doBranch(cpu: *Cpu, value: u8, check: bool) void {
    if (check) {
        cpu.cyclesUsed +%= 1; // taken branch: 1 extra cycle
        cpu.pc = addRel(cpu.pc, value);
    }
}

/// pc += (int8_t)value, wrapping.
fn addRel(pc: u16, value: u8) u16 {
    const rel: i8 = @bitCast(value);
    return pc +% @as(u16, @bitCast(@as(i16, rel)));
}

fn cpu_pullByte(cpu: *Cpu) u8 {
    cpu.sp +%= 1;
    if (cpu.e) cpu.sp = (cpu.sp & 0xff) | 0x100;
    return cpu_read(cpu, cpu.sp);
}

fn cpu_pushByte(cpu: *Cpu, value: u8) void {
    cpu_write(cpu, cpu.sp, value);
    cpu.sp -%= 1;
    if (cpu.e) cpu.sp = (cpu.sp & 0xff) | 0x100;
}

fn cpu_pullWord(cpu: *Cpu) u16 {
    const value = cpu_pullByte(cpu);
    return @as(u16, value) | (@as(u16, cpu_pullByte(cpu)) << 8);
}

fn cpu_pushWord(cpu: *Cpu, value: u16) void {
    cpu_pushByte(cpu, @truncate(value >> 8));
    cpu_pushByte(cpu, @truncate(value));
}

fn cpu_readWord(cpu: *Cpu, adrl: u32, adrh: u32) u16 {
    const value = cpu_read(cpu, adrl);
    return @as(u16, value) | (@as(u16, cpu_read(cpu, adrh)) << 8);
}

fn cpu_writeWord(cpu: *Cpu, adrl: u32, adrh: u32, value: u16, reversed: bool) void {
    if (reversed) {
        cpu_write(cpu, adrh, @truncate(value >> 8));
        cpu_write(cpu, adrl, @truncate(value));
    } else {
        cpu_write(cpu, adrl, @truncate(value));
        cpu_write(cpu, adrh, @truncate(value >> 8));
    }
}

fn cpu_doInterrupt(cpu: *Cpu, irq: bool) void {
    cpu_pushByte(cpu, cpu.k);
    cpu_pushWord(cpu, cpu.pc);
    cpu_pushByte(cpu, cpu_getFlags(cpu));
    cpu.cyclesUsed +%= 1; // native mode: 1 extra cycle
    cpu.i = true;
    cpu.d = false;
    cpu.k = 0;
    if (irq) {
        cpu.pc = cpu_readWord(cpu, 0xffee, 0xffef);
    } else {
        // nmi
        cpu.pc = cpu_readWord(cpu, 0xffea, 0xffeb);
    }
}

// addressing modes

fn cpu_adrImm(cpu: *Cpu, low: *u32, xFlag: bool) u32 {
    if ((xFlag and cpu.xf) or (!xFlag and cpu.mf)) {
        low.* = (@as(u32, cpu.k) << 16) | cpu.pc;
        cpu.pc +%= 1;
        return 0;
    } else {
        low.* = (@as(u32, cpu.k) << 16) | cpu.pc;
        cpu.pc +%= 1;
        const high = (@as(u32, cpu.k) << 16) | cpu.pc;
        cpu.pc +%= 1;
        return high;
    }
}

fn cpu_adrDp(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcode(cpu);
    if (cpu.dp & 0xff != 0) cpu.cyclesUsed +%= 1; // dpr not 0: 1 extra cycle
    low.* = (@as(u32, cpu.dp) + adr) & 0xffff;
    return (@as(u32, cpu.dp) + adr + 1) & 0xffff;
}

fn cpu_adrDpx(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcode(cpu);
    if (cpu.dp & 0xff != 0) cpu.cyclesUsed +%= 1; // dpr not 0: 1 extra cycle
    low.* = (@as(u32, cpu.dp) + adr + cpu.x) & 0xffff;
    return (@as(u32, cpu.dp) + adr + cpu.x + 1) & 0xffff;
}

fn cpu_adrDpy(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcode(cpu);
    if (cpu.dp & 0xff != 0) cpu.cyclesUsed +%= 1; // dpr not 0: 1 extra cycle
    low.* = (@as(u32, cpu.dp) + adr + cpu.y) & 0xffff;
    return (@as(u32, cpu.dp) + adr + cpu.y + 1) & 0xffff;
}

fn cpu_adrIdp(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcode(cpu);
    if (cpu.dp & 0xff != 0) cpu.cyclesUsed +%= 1; // dpr not 0: 1 extra cycle
    const pointer = cpu_readWord(cpu, (@as(u32, cpu.dp) + adr) & 0xffff, (@as(u32, cpu.dp) + adr + 1) & 0xffff);
    low.* = (@as(u32, cpu.db) << 16) + pointer;
    return ((@as(u32, cpu.db) << 16) + pointer + 1) & 0xffffff;
}

fn cpu_adrIdx(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcode(cpu);
    if (cpu.dp & 0xff != 0) cpu.cyclesUsed +%= 1; // dpr not 0: 1 extra cycle
    const pointer = cpu_readWord(
        cpu,
        (@as(u32, cpu.dp) + adr + cpu.x) & 0xffff,
        (@as(u32, cpu.dp) + adr + cpu.x + 1) & 0xffff,
    );
    low.* = (@as(u32, cpu.db) << 16) + pointer;
    return ((@as(u32, cpu.db) << 16) + pointer + 1) & 0xffffff;
}

fn cpu_adrIdy(cpu: *Cpu, low: *u32, write: bool) u32 {
    const adr = cpu_readOpcode(cpu);
    if (cpu.dp & 0xff != 0) cpu.cyclesUsed +%= 1; // dpr not 0: 1 extra cycle
    const pointer = cpu_readWord(cpu, (@as(u32, cpu.dp) + adr) & 0xffff, (@as(u32, cpu.dp) + adr + 1) & 0xffff);
    // x = 0 or page crossed, with writing opcode: 1 extra cycle
    if (write and (!cpu.xf or ((pointer >> 8) != ((@as(u32, pointer) + cpu.y) >> 8)))) cpu.cyclesUsed +%= 1;
    low.* = ((@as(u32, cpu.db) << 16) + pointer + cpu.y) & 0xffffff;
    return ((@as(u32, cpu.db) << 16) + pointer + cpu.y + 1) & 0xffffff;
}

fn cpu_adrIdl(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcode(cpu);
    if (cpu.dp & 0xff != 0) cpu.cyclesUsed +%= 1; // dpr not 0: 1 extra cycle
    var pointer: u32 = cpu_readWord(cpu, (@as(u32, cpu.dp) + adr) & 0xffff, (@as(u32, cpu.dp) + adr + 1) & 0xffff);
    pointer |= @as(u32, cpu_read(cpu, (@as(u32, cpu.dp) + adr + 2) & 0xffff)) << 16;
    low.* = pointer;
    return (pointer + 1) & 0xffffff;
}

fn cpu_adrIly(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcode(cpu);
    if (cpu.dp & 0xff != 0) cpu.cyclesUsed +%= 1; // dpr not 0: 1 extra cycle
    var pointer: u32 = cpu_readWord(cpu, (@as(u32, cpu.dp) + adr) & 0xffff, (@as(u32, cpu.dp) + adr + 1) & 0xffff);
    pointer |= @as(u32, cpu_read(cpu, (@as(u32, cpu.dp) + adr + 2) & 0xffff)) << 16;
    low.* = (pointer + cpu.y) & 0xffffff;
    return (pointer + cpu.y + 1) & 0xffffff;
}

fn cpu_adrSr(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcode(cpu);
    low.* = (@as(u32, cpu.sp) + adr) & 0xffff;
    return (@as(u32, cpu.sp) + adr + 1) & 0xffff;
}

fn cpu_adrIsy(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcode(cpu);
    const pointer = cpu_readWord(cpu, (@as(u32, cpu.sp) + adr) & 0xffff, (@as(u32, cpu.sp) + adr + 1) & 0xffff);
    low.* = ((@as(u32, cpu.db) << 16) + pointer + cpu.y) & 0xffffff;
    return ((@as(u32, cpu.db) << 16) + pointer + cpu.y + 1) & 0xffffff;
}

fn cpu_adrAbs(cpu: *Cpu, low: *u32) u32 {
    const adr = cpu_readOpcodeWord(cpu);
    low.* = (@as(u32, cpu.db) << 16) + adr;
    return ((@as(u32, cpu.db) << 16) + adr + 1) & 0xffffff;
}

fn cpu_adrAbx(cpu: *Cpu, low: *u32, write: bool) u32 {
    const adr = cpu_readOpcodeWord(cpu);
    // x = 0 or page crossed, with writing opcode: 1 extra cycle
    if (write and (!cpu.xf or ((adr >> 8) != ((@as(u32, adr) + cpu.x) >> 8)))) cpu.cyclesUsed +%= 1;
    low.* = ((@as(u32, cpu.db) << 16) + adr + cpu.x) & 0xffffff;
    return ((@as(u32, cpu.db) << 16) + adr + cpu.x + 1) & 0xffffff;
}

fn cpu_adrAby(cpu: *Cpu, low: *u32, write: bool) u32 {
    const adr = cpu_readOpcodeWord(cpu);
    // x = 0 or page crossed, with writing opcode: 1 extra cycle
    if (write and (!cpu.xf or ((adr >> 8) != ((@as(u32, adr) + cpu.y) >> 8)))) cpu.cyclesUsed +%= 1;
    low.* = ((@as(u32, cpu.db) << 16) + adr + cpu.y) & 0xffffff;
    return ((@as(u32, cpu.db) << 16) + adr + cpu.y + 1) & 0xffffff;
}

fn cpu_adrAbl(cpu: *Cpu, low: *u32) u32 {
    var adr: u32 = cpu_readOpcodeWord(cpu);
    adr |= @as(u32, cpu_readOpcode(cpu)) << 16;
    low.* = adr;
    return (adr + 1) & 0xffffff;
}

fn cpu_adrAlx(cpu: *Cpu, low: *u32) u32 {
    var adr: u32 = cpu_readOpcodeWord(cpu);
    adr |= @as(u32, cpu_readOpcode(cpu)) << 16;
    low.* = (adr + cpu.x) & 0xffffff;
    return (adr + cpu.x + 1) & 0xffffff;
}

fn cpu_adrIax(cpu: *Cpu) u16 {
    const adr = cpu_readOpcodeWord(cpu);
    return cpu_readWord(
        cpu,
        (@as(u32, cpu.k) << 16) | (adr +% cpu.x),
        (@as(u32, cpu.k) << 16) | (adr +% cpu.x +% 1),
    );
}

// opcode functions

fn cpu_and(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.mf) {
        const value = cpu_read(cpu, low);
        cpu.a = (cpu.a & 0xff00) | ((cpu.a & value) & 0xff);
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        const value = cpu_readWord(cpu, low, high);
        cpu.a &= value;
    }
    cpu_setZN(cpu, cpu.a, cpu.mf);
}

fn cpu_ora(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.mf) {
        const value = cpu_read(cpu, low);
        cpu.a = (cpu.a & 0xff00) | ((cpu.a | value) & 0xff);
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        const value = cpu_readWord(cpu, low, high);
        cpu.a |= value;
    }
    cpu_setZN(cpu, cpu.a, cpu.mf);
}

fn cpu_eor(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.mf) {
        const value = cpu_read(cpu, low);
        cpu.a = (cpu.a & 0xff00) | ((cpu.a ^ value) & 0xff);
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        const value = cpu_readWord(cpu, low, high);
        cpu.a ^= value;
    }
    cpu_setZN(cpu, cpu.a, cpu.mf);
}

fn cpu_adc(cpu: *Cpu, low: u32, high: u32) void {
    const a: i32 = cpu.a;
    const carry: i32 = @intFromBool(cpu.c);
    if (cpu.mf) {
        const value: i32 = cpu_read(cpu, low);
        var result: i32 = 0;
        if (cpu.d) {
            result = (a & 0xf) + (value & 0xf) + carry;
            if (result > 0x9) result = ((result + 0x6) & 0xf) + 0x10;
            result = (a & 0xf0) + (value & 0xf0) + result;
        } else {
            result = (a & 0xff) + value + carry;
        }
        cpu.v = (a & 0x80) == (value & 0x80) and (value & 0x80) != (result & 0x80);
        if (cpu.d and result > 0x9f) result += 0x60;
        cpu.c = result > 0xff;
        cpu.a = (cpu.a & 0xff00) | @as(u16, @truncate(@as(u32, @bitCast(result)) & 0xff));
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        const value: i32 = cpu_readWord(cpu, low, high);
        var result: i32 = 0;
        if (cpu.d) {
            result = (a & 0xf) + (value & 0xf) + carry;
            if (result > 0x9) result = ((result + 0x6) & 0xf) + 0x10;
            result = (a & 0xf0) + (value & 0xf0) + result;
            if (result > 0x9f) result = ((result + 0x60) & 0xff) + 0x100;
            result = (a & 0xf00) + (value & 0xf00) + result;
            if (result > 0x9ff) result = ((result + 0x600) & 0xfff) + 0x1000;
            result = (a & 0xf000) + (value & 0xf000) + result;
        } else {
            result = a + value + carry;
        }
        cpu.v = (a & 0x8000) == (value & 0x8000) and (value & 0x8000) != (result & 0x8000);
        if (cpu.d and result > 0x9fff) result += 0x6000;
        cpu.c = result > 0xffff;
        cpu.a = @truncate(@as(u32, @bitCast(result)));
    }
    cpu_setZN(cpu, cpu.a, cpu.mf);
}

fn cpu_sbc(cpu: *Cpu, low: u32, high: u32) void {
    const a: i32 = cpu.a;
    const carry: i32 = @intFromBool(cpu.c);
    if (cpu.mf) {
        const value: i32 = cpu_read(cpu, low) ^ 0xff;
        var result: i32 = 0;
        if (cpu.d) {
            result = (a & 0xf) + (value & 0xf) + carry;
            if (result < 0x10) result = (result - 0x6) & (if (result - 0x6 < 0) @as(i32, 0xf) else 0x1f);
            result = (a & 0xf0) + (value & 0xf0) + result;
        } else {
            result = (a & 0xff) + value + carry;
        }
        cpu.v = (a & 0x80) == (value & 0x80) and (value & 0x80) != (result & 0x80);
        if (cpu.d and result < 0x100) result -= 0x60;
        cpu.c = result > 0xff;
        cpu.a = (cpu.a & 0xff00) | @as(u16, @truncate(@as(u32, @bitCast(result)) & 0xff));
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        const value: i32 = cpu_readWord(cpu, low, high) ^ 0xffff;
        var result: i32 = 0;
        if (cpu.d) {
            result = (a & 0xf) + (value & 0xf) + carry;
            if (result < 0x10) result = (result - 0x6) & (if (result - 0x6 < 0) @as(i32, 0xf) else 0x1f);
            result = (a & 0xf0) + (value & 0xf0) + result;
            if (result < 0x100) result = (result - 0x60) & (if (result - 0x60 < 0) @as(i32, 0xff) else 0x1ff);
            result = (a & 0xf00) + (value & 0xf00) + result;
            if (result < 0x1000) result = (result - 0x600) & (if (result - 0x600 < 0) @as(i32, 0xfff) else 0x1fff);
            result = (a & 0xf000) + (value & 0xf000) + result;
        } else {
            result = a + value + carry;
        }
        cpu.v = (a & 0x8000) == (value & 0x8000) and (value & 0x8000) != (result & 0x8000);
        if (cpu.d and result < 0x10000) result -= 0x6000;
        cpu.c = result > 0xffff;
        cpu.a = @truncate(@as(u32, @bitCast(result)));
    }
    cpu_setZN(cpu, cpu.a, cpu.mf);
}

fn cpu_cmp(cpu: *Cpu, low: u32, high: u32) void {
    var result: i32 = 0;
    if (cpu.mf) {
        const value: i32 = cpu_read(cpu, low) ^ 0xff;
        result = (@as(i32, cpu.a) & 0xff) + value + 1;
        cpu.c = result > 0xff;
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        const value: i32 = cpu_readWord(cpu, low, high) ^ 0xffff;
        result = @as(i32, cpu.a) + value + 1;
        cpu.c = result > 0xffff;
    }
    cpu_setZN(cpu, @truncate(@as(u32, @bitCast(result))), cpu.mf);
}

fn cpu_cpx(cpu: *Cpu, low: u32, high: u32) void {
    var result: i32 = 0;
    if (cpu.xf) {
        const value: i32 = cpu_read(cpu, low) ^ 0xff;
        result = (@as(i32, cpu.x) & 0xff) + value + 1;
        cpu.c = result > 0xff;
    } else {
        cpu.cyclesUsed +%= 1; // x = 0: 1 extra cycle
        const value: i32 = cpu_readWord(cpu, low, high) ^ 0xffff;
        result = @as(i32, cpu.x) + value + 1;
        cpu.c = result > 0xffff;
    }
    cpu_setZN(cpu, @truncate(@as(u32, @bitCast(result))), cpu.xf);
}

fn cpu_cpy(cpu: *Cpu, low: u32, high: u32) void {
    var result: i32 = 0;
    if (cpu.xf) {
        const value: i32 = cpu_read(cpu, low) ^ 0xff;
        result = (@as(i32, cpu.y) & 0xff) + value + 1;
        cpu.c = result > 0xff;
    } else {
        cpu.cyclesUsed +%= 1; // x = 0: 1 extra cycle
        const value: i32 = cpu_readWord(cpu, low, high) ^ 0xffff;
        result = @as(i32, cpu.y) + value + 1;
        cpu.c = result > 0xffff;
    }
    cpu_setZN(cpu, @truncate(@as(u32, @bitCast(result))), cpu.xf);
}

fn cpu_bit(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.mf) {
        const value = cpu_read(cpu, low);
        const result = @as(u8, @truncate(cpu.a)) & value;
        cpu.z = result == 0;
        cpu.n = value & 0x80 != 0;
        cpu.v = value & 0x40 != 0;
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        const value = cpu_readWord(cpu, low, high);
        const result = cpu.a & value;
        cpu.z = result == 0;
        cpu.n = value & 0x8000 != 0;
        cpu.v = value & 0x4000 != 0;
    }
}

fn cpu_lda(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.mf) {
        cpu.a = (cpu.a & 0xff00) | cpu_read(cpu, low);
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        cpu.a = cpu_readWord(cpu, low, high);
    }
    cpu_setZN(cpu, cpu.a, cpu.mf);
}

fn cpu_ldx(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.xf) {
        cpu.x = cpu_read(cpu, low);
    } else {
        cpu.cyclesUsed +%= 1; // x = 0: 1 extra cycle
        cpu.x = cpu_readWord(cpu, low, high);
    }
    cpu_setZN(cpu, cpu.x, cpu.xf);
}

fn cpu_ldy(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.xf) {
        cpu.y = cpu_read(cpu, low);
    } else {
        cpu.cyclesUsed +%= 1; // x = 0: 1 extra cycle
        cpu.y = cpu_readWord(cpu, low, high);
    }
    cpu_setZN(cpu, cpu.y, cpu.xf);
}

fn cpu_sta(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.mf) {
        cpu_write(cpu, low, @truncate(cpu.a));
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        cpu_writeWord(cpu, low, high, cpu.a, false);
    }
}

fn cpu_stx(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.xf) {
        cpu_write(cpu, low, @truncate(cpu.x));
    } else {
        cpu.cyclesUsed +%= 1; // x = 0: 1 extra cycle
        cpu_writeWord(cpu, low, high, cpu.x, false);
    }
}

fn cpu_sty(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.xf) {
        cpu_write(cpu, low, @truncate(cpu.y));
    } else {
        cpu.cyclesUsed +%= 1; // x = 0: 1 extra cycle
        cpu_writeWord(cpu, low, high, cpu.y, false);
    }
}

fn cpu_stz(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.mf) {
        cpu_write(cpu, low, 0);
    } else {
        cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
        cpu_writeWord(cpu, low, high, 0, false);
    }
}

fn cpu_ror(cpu: *Cpu, low: u32, high: u32) void {
    var carry = false;
    var result: u32 = 0;
    if (cpu.mf) {
        const value = cpu_read(cpu, low);
        carry = value & 1 != 0;
        result = (value >> 1) | (@as(u32, @intFromBool(cpu.c)) << 7);
        cpu_write(cpu, low, @truncate(result));
    } else {
        cpu.cyclesUsed +%= 2; // m = 0: 2 extra cycles
        const value = cpu_readWord(cpu, low, high);
        carry = value & 1 != 0;
        result = (value >> 1) | (@as(u32, @intFromBool(cpu.c)) << 15);
        cpu_writeWord(cpu, low, high, @truncate(result), true);
    }
    cpu_setZN(cpu, @truncate(result), cpu.mf);
    cpu.c = carry;
}

fn cpu_rol(cpu: *Cpu, low: u32, high: u32) void {
    var result: u32 = 0;
    if (cpu.mf) {
        result = (@as(u32, cpu_read(cpu, low)) << 1) | @intFromBool(cpu.c);
        cpu.c = result & 0x100 != 0;
        cpu_write(cpu, low, @truncate(result));
    } else {
        cpu.cyclesUsed +%= 2; // m = 0: 2 extra cycles
        result = (@as(u32, cpu_readWord(cpu, low, high)) << 1) | @intFromBool(cpu.c);
        cpu.c = result & 0x10000 != 0;
        cpu_writeWord(cpu, low, high, @truncate(result), true);
    }
    cpu_setZN(cpu, @truncate(result), cpu.mf);
}

fn cpu_lsr(cpu: *Cpu, low: u32, high: u32) void {
    var result: u32 = 0;
    if (cpu.mf) {
        const value = cpu_read(cpu, low);
        cpu.c = value & 1 != 0;
        result = value >> 1;
        cpu_write(cpu, low, @truncate(result));
    } else {
        cpu.cyclesUsed +%= 2; // m = 0: 2 extra cycles
        const value = cpu_readWord(cpu, low, high);
        cpu.c = value & 1 != 0;
        result = value >> 1;
        cpu_writeWord(cpu, low, high, @truncate(result), true);
    }
    cpu_setZN(cpu, @truncate(result), cpu.mf);
}

fn cpu_asl(cpu: *Cpu, low: u32, high: u32) void {
    var result: u32 = 0;
    if (cpu.mf) {
        result = @as(u32, cpu_read(cpu, low)) << 1;
        cpu.c = result & 0x100 != 0;
        cpu_write(cpu, low, @truncate(result));
    } else {
        cpu.cyclesUsed +%= 2; // m = 0: 2 extra cycles
        result = @as(u32, cpu_readWord(cpu, low, high)) << 1;
        cpu.c = result & 0x10000 != 0;
        cpu_writeWord(cpu, low, high, @truncate(result), true);
    }
    cpu_setZN(cpu, @truncate(result), cpu.mf);
}

fn cpu_inc(cpu: *Cpu, low: u32, high: u32) void {
    var result: u32 = 0;
    if (cpu.mf) {
        result = @as(u32, cpu_read(cpu, low)) + 1;
        cpu_write(cpu, low, @truncate(result));
    } else {
        cpu.cyclesUsed +%= 2; // m = 0: 2 extra cycles
        result = @as(u32, cpu_readWord(cpu, low, high)) + 1;
        cpu_writeWord(cpu, low, high, @truncate(result), true);
    }
    cpu_setZN(cpu, @truncate(result), cpu.mf);
}

fn cpu_dec(cpu: *Cpu, low: u32, high: u32) void {
    var result: u32 = 0;
    if (cpu.mf) {
        result = @as(u32, cpu_read(cpu, low)) -% 1;
        cpu_write(cpu, low, @truncate(result));
    } else {
        cpu.cyclesUsed +%= 2; // m = 0: 2 extra cycles
        result = @as(u32, cpu_readWord(cpu, low, high)) -% 1;
        cpu_writeWord(cpu, low, high, @truncate(result), true);
    }
    cpu_setZN(cpu, @truncate(result), cpu.mf);
}

fn cpu_tsb(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.mf) {
        const value = cpu_read(cpu, low);
        cpu.z = (@as(u8, @truncate(cpu.a)) & value) == 0;
        cpu_write(cpu, low, value | @as(u8, @truncate(cpu.a)));
    } else {
        cpu.cyclesUsed +%= 2; // m = 0: 2 extra cycles
        const value = cpu_readWord(cpu, low, high);
        cpu.z = (cpu.a & value) == 0;
        cpu_writeWord(cpu, low, high, value | cpu.a, true);
    }
}

fn cpu_trb(cpu: *Cpu, low: u32, high: u32) void {
    if (cpu.mf) {
        const value = cpu_read(cpu, low);
        cpu.z = (@as(u8, @truncate(cpu.a)) & value) == 0;
        cpu_write(cpu, low, value & ~@as(u8, @truncate(cpu.a)));
    } else {
        cpu.cyclesUsed +%= 2; // m = 0: 2 extra cycles
        const value = cpu_readWord(cpu, low, high);
        cpu.z = (cpu.a & value) == 0;
        cpu_writeWord(cpu, low, high, value & ~cpu.a, true);
    }
}

// These four opcode bodies are also reached from the brk hooks below, which in
// the C jump into the middle of the switch with a goto.

fn opAdcDp(cpu: *Cpu) void {
    var low: u32 = 0;
    const high = cpu_adrDp(cpu, &low);
    cpu_adc(cpu, low, high);
}

fn opAdcImm(cpu: *Cpu) void {
    var low: u32 = 0;
    const high = cpu_adrImm(cpu, &low, false);
    cpu_adc(cpu, low, high);
}

fn opSbcDp(cpu: *Cpu) void {
    var low: u32 = 0;
    const high = cpu_adrDp(cpu, &low);
    cpu_sbc(cpu, low, high);
}

fn opSbcImm(cpu: *Cpu) void {
    var low: u32 = 0;
    const high = cpu_adrImm(cpu, &low, false);
    cpu_sbc(cpu, low, high);
}

fn opIny(cpu: *Cpu) void {
    if (cpu.xf) {
        cpu.y = (cpu.y +% 1) & 0xff;
    } else {
        cpu.y +%= 1;
    }
    cpu_setZN(cpu, cpu.y, cpu.xf);
}

/// Sets only the low byte of A, the way the C does with a cast through
/// `*(uint8_t *)&cpu->a`.
fn setAL(cpu: *Cpu, value: u8) void {
    cpu.a = (cpu.a & 0xff00) | value;
}

/// The brk handler: the ROM is patched with brk at a handful of places where
/// the original game reads uninitialised memory or relies on a junk carry.
/// Returns true if the opcode should be re-dispatched (see `retry`).
fn cpu_doBrk(cpu: *Cpu, retry: *?u8) void {
    const addr = (@as(u32, cpu.k) << 16) | cpu.pc;
    switch (addr -% 1) {
        0x7B269 => { // Link_APress_LiftCarryThrow reads OOB
            if ((cpu.x & 0xff) >= 28)
                cpu.pc = 0xB280; // RTS
            retry.* = 0xE8;
        },
        // Uncle_AtHome case 3 will read random memory.
        0x5DEC7 => {
            setAL(cpu, cpu_read(cpu, 0x5DEB0 + @as(u32, cpu.y & 0xff)));
            if (cpu_read(cpu, 0xD90 + (cpu.x & 0xff)) == 2) {
                cpu.pc = 0xdeea;
                return;
            }
            cpu.pc +%= 2;
        },
        // Overlord_StalfosTrap doesn't initialize the sprite_D memory location
        0x9be5e => {
            setAL(cpu, 224);
            cpu_write(cpu, 0xDE0 + @as(u32, @as(u8, @truncate(cpu.y))), 0);
            cpu.pc +%= 1;
        },
        0x1AF9A4 => { // Lanmola_SpawnShrapnel uses undefined carry value
            setAL(cpu, @as(u8, @truncate(cpu.a)) +% 4);
            cpu.c = false;
            cpu.pc +%= 1;
        },
        // .9E:8A46 sbc BG2HOFS_copy2 / sbc R8 / adc #0xC -- carry junk
        0x1E8A46 => {
            cpu.a = cpu.a -% cpu_read(cpu, 0xe2) -% cpu_read(cpu, 8) +% 12;
            cpu.pc +%= 5;
        },
        // .9E:8A52 sbc BG2VOFS_copy2 / adc #8 / sbc R9 / adc #8 -- carry junk
        0x1E8A52 => {
            cpu.a = cpu.a -% cpu_read(cpu, 0xe8) +% 8 -% cpu_read(cpu, 9) +% 8;
            cpu.pc +%= 7;
        },
        0x9a966 => { // Tagalong_DrawInner doesn't init scratch_0 / scratch_1
            for (0..4) |i| cpu_write(cpu, 0x72 + @as(u32, @intCast(i)), 0);
            cpu.pc +%= 1;
        },
        0x8f708 => {
            cpu_write(cpu, 0x75, 0);
            opIny(cpu);
        },
        0x1de0e5 => { // GreatCatfish_ConversateThenSubmerge - not carry preserving
            if (@as(u8, @truncate(cpu.a)) >= 160) {
                cpu.pc = 0xe164;
            } else {
                cpu.pc +%= 1;
            }
        },
        // Sprite_CommonItemPickup - wrong carry chain
        0x6d0b6, 0x6d0c6 => {
            cpu.c = @as(u8, @truncate(cpu.a)) >= 4;
            cpu.a = cpu.a -% 4;
            cpu.pc +%= 1;
        },
        0x1d8f29, 0x1dc812, 0x1DDBD3, 0x1DF856, 0x6ED0B, 0x9b478, 0x9b46c => {
            cpu.c = false;
            opAdcImm(cpu);
        },
        0x1E88DA => {
            cpu.c = false;
            opAdcDp(cpu);
        },
        0x9B468, 0x9B46A, 0x9B474, 0x9B476 => {
            cpu.c = true;
            opSbcDp(cpu);
        },
        0x9B60C => {
            cpu.c = true;
            opSbcImm(cpu);
        },
        0x1DCDEB => {
            // BC B0 0E   mov.b Y, sprite_head_dir[X]
            cpu.y = cpu_read(cpu, 0x0eb0 + (cpu.x & 0xff));
            cpu.a = cpu.x;
        },
        else => std.debug.panic("unhandled brk at 0x{x}", .{addr -% 1}),
    }
}

fn cpu_doOpcode(cpu: *Cpu, opcode_in: u8) void {
    var opcode = opcode_in;
    restart: while (true) {
        switch (opcode) {
            0x00 => { // brk imp
                var retry: ?u8 = null;
                cpu_doBrk(cpu, &retry);
                if (retry) |next| {
                    opcode = next;
                    continue :restart;
                }
            },
            0x01 => { // ora idx
                var low: u32 = 0;
                const high = cpu_adrIdx(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x02 => { // cop imm(s)
                _ = cpu_readOpcode(cpu);
                cpu_pushByte(cpu, cpu.k);
                cpu_pushWord(cpu, cpu.pc);
                cpu_pushByte(cpu, cpu_getFlags(cpu));
                cpu.cyclesUsed +%= 1; // native mode: 1 extra cycle
                cpu.i = true;
                cpu.d = false;
                cpu.k = 0;
                cpu.pc = cpu_readWord(cpu, 0xffe4, 0xffe5);
            },
            0x03 => { // ora sr
                var low: u32 = 0;
                const high = cpu_adrSr(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x04 => { // tsb dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_tsb(cpu, low, high);
            },
            0x05 => { // ora dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x06 => { // asl dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_asl(cpu, low, high);
            },
            0x07 => { // ora idl
                var low: u32 = 0;
                const high = cpu_adrIdl(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x08 => cpu_pushByte(cpu, cpu_getFlags(cpu)), // php imp
            0x09 => { // ora imm(m)
                var low: u32 = 0;
                const high = cpu_adrImm(cpu, &low, false);
                cpu_ora(cpu, low, high);
            },
            0x0a => { // asla imp
                if (cpu.mf) {
                    cpu.c = cpu.a & 0x80 != 0;
                    cpu.a = (cpu.a & 0xff00) | ((cpu.a << 1) & 0xff);
                } else {
                    cpu.c = cpu.a & 0x8000 != 0;
                    cpu.a <<= 1;
                }
                cpu_setZN(cpu, cpu.a, cpu.mf);
            },
            0x0b => cpu_pushWord(cpu, cpu.dp), // phd imp
            0x0c => { // tsb abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_tsb(cpu, low, high);
            },
            0x0d => { // ora abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x0e => { // asl abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_asl(cpu, low, high);
            },
            0x0f => { // ora abl
                var low: u32 = 0;
                const high = cpu_adrAbl(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x10 => { // bpl rel
                const rel = cpu_readOpcode(cpu);
                cpu_doBranch(cpu, rel, !cpu.n);
            },
            0x11 => { // ora idy(r)
                var low: u32 = 0;
                const high = cpu_adrIdy(cpu, &low, false);
                cpu_ora(cpu, low, high);
            },
            0x12 => { // ora idp
                var low: u32 = 0;
                const high = cpu_adrIdp(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x13 => { // ora isy
                var low: u32 = 0;
                const high = cpu_adrIsy(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x14 => { // trb dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_trb(cpu, low, high);
            },
            0x15 => { // ora dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x16 => { // asl dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_asl(cpu, low, high);
            },
            0x17 => { // ora ily
                var low: u32 = 0;
                const high = cpu_adrIly(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x18 => cpu.c = false, // clc imp
            0x19 => { // ora aby(r)
                var low: u32 = 0;
                const high = cpu_adrAby(cpu, &low, false);
                cpu_ora(cpu, low, high);
            },
            0x1a => { // inca imp
                if (cpu.mf) {
                    cpu.a = (cpu.a & 0xff00) | ((cpu.a +% 1) & 0xff);
                } else {
                    cpu.a +%= 1;
                }
                cpu_setZN(cpu, cpu.a, cpu.mf);
            },
            0x1b => cpu.sp = cpu.a, // tcs imp
            0x1c => { // trb abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_trb(cpu, low, high);
            },
            0x1d => { // ora abx(r)
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, false);
                cpu_ora(cpu, low, high);
            },
            0x1e => { // asl abx
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, true);
                cpu_asl(cpu, low, high);
            },
            0x1f => { // ora alx
                var low: u32 = 0;
                const high = cpu_adrAlx(cpu, &low);
                cpu_ora(cpu, low, high);
            },
            0x20 => { // jsr abs
                const value = cpu_readOpcodeWord(cpu);
                cpu_pushWord(cpu, cpu.pc -% 1);
                cpu.pc = value;
            },
            0x21 => { // and idx
                var low: u32 = 0;
                const high = cpu_adrIdx(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x22 => { // jsl abl
                const value = cpu_readOpcodeWord(cpu);
                const newK = cpu_readOpcode(cpu);
                cpu_pushByte(cpu, cpu.k);
                cpu_pushWord(cpu, cpu.pc -% 1);
                cpu.pc = value;
                cpu.k = newK;
            },
            0x23 => { // and sr
                var low: u32 = 0;
                const high = cpu_adrSr(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x24 => { // bit dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_bit(cpu, low, high);
            },
            0x25 => { // and dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x26 => { // rol dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_rol(cpu, low, high);
            },
            0x27 => { // and idl
                var low: u32 = 0;
                const high = cpu_adrIdl(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x28 => cpu_setFlags(cpu, cpu_pullByte(cpu)), // plp imp
            0x29 => { // and imm(m)
                var low: u32 = 0;
                const high = cpu_adrImm(cpu, &low, false);
                cpu_and(cpu, low, high);
            },
            0x2a => { // rola imp
                const result = (@as(u32, cpu.a) << 1) | @intFromBool(cpu.c);
                if (cpu.mf) {
                    cpu.c = result & 0x100 != 0;
                    cpu.a = (cpu.a & 0xff00) | @as(u16, @truncate(result & 0xff));
                } else {
                    cpu.c = result & 0x10000 != 0;
                    cpu.a = @truncate(result);
                }
                cpu_setZN(cpu, cpu.a, cpu.mf);
            },
            0x2b => { // pld imp
                cpu.dp = cpu_pullWord(cpu);
                cpu_setZN(cpu, cpu.dp, false);
            },
            0x2c => { // bit abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_bit(cpu, low, high);
            },
            0x2d => { // and abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x2e => { // rol abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_rol(cpu, low, high);
            },
            0x2f => { // and abl
                var low: u32 = 0;
                const high = cpu_adrAbl(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x30 => { // bmi rel
                const rel = cpu_readOpcode(cpu);
                cpu_doBranch(cpu, rel, cpu.n);
            },
            0x31 => { // and idy(r)
                var low: u32 = 0;
                const high = cpu_adrIdy(cpu, &low, false);
                cpu_and(cpu, low, high);
            },
            0x32 => { // and idp
                var low: u32 = 0;
                const high = cpu_adrIdp(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x33 => { // and isy
                var low: u32 = 0;
                const high = cpu_adrIsy(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x34 => { // bit dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_bit(cpu, low, high);
            },
            0x35 => { // and dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x36 => { // rol dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_rol(cpu, low, high);
            },
            0x37 => { // and ily
                var low: u32 = 0;
                const high = cpu_adrIly(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x38 => cpu.c = true, // sec imp
            0x39 => { // and aby(r)
                var low: u32 = 0;
                const high = cpu_adrAby(cpu, &low, false);
                cpu_and(cpu, low, high);
            },
            0x3a => { // deca imp
                if (cpu.mf) {
                    cpu.a = (cpu.a & 0xff00) | ((cpu.a -% 1) & 0xff);
                } else {
                    cpu.a -%= 1;
                }
                cpu_setZN(cpu, cpu.a, cpu.mf);
            },
            0x3b => { // tsc imp
                cpu.a = cpu.sp;
                cpu_setZN(cpu, cpu.a, false);
            },
            0x3c => { // bit abx(r)
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, false);
                cpu_bit(cpu, low, high);
            },
            0x3d => { // and abx(r)
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, false);
                cpu_and(cpu, low, high);
            },
            0x3e => { // rol abx
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, true);
                cpu_rol(cpu, low, high);
            },
            0x3f => { // and alx
                var low: u32 = 0;
                const high = cpu_adrAlx(cpu, &low);
                cpu_and(cpu, low, high);
            },
            0x40 => { // rti imp
                cpu_setFlags(cpu, cpu_pullByte(cpu));
                cpu.cyclesUsed +%= 1; // native mode: 1 extra cycle
                cpu.pc = cpu_pullWord(cpu);
                cpu.k = cpu_pullByte(cpu);
            },
            0x41 => { // eor idx
                var low: u32 = 0;
                const high = cpu_adrIdx(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x42 => _ = cpu_readOpcode(cpu), // wdm imm(s)
            0x43 => { // eor sr
                var low: u32 = 0;
                const high = cpu_adrSr(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x44 => { // mvp bm
                const dest = cpu_readOpcode(cpu);
                const src = cpu_readOpcode(cpu);
                cpu.db = dest;
                cpu_write(cpu, (@as(u32, dest) << 16) | cpu.y, cpu_read(cpu, (@as(u32, src) << 16) | cpu.x));
                cpu.a -%= 1;
                cpu.x -%= 1;
                cpu.y -%= 1;
                if (cpu.a != 0xffff) {
                    cpu.pc -%= 3;
                }
                if (cpu.xf) {
                    cpu.x &= 0xff;
                    cpu.y &= 0xff;
                }
            },
            0x45 => { // eor dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x46 => { // lsr dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_lsr(cpu, low, high);
            },
            0x47 => { // eor idl
                var low: u32 = 0;
                const high = cpu_adrIdl(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x48 => { // pha imp
                if (cpu.mf) {
                    cpu_pushByte(cpu, @truncate(cpu.a));
                } else {
                    cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
                    cpu_pushWord(cpu, cpu.a);
                }
            },
            0x49 => { // eor imm(m)
                var low: u32 = 0;
                const high = cpu_adrImm(cpu, &low, false);
                cpu_eor(cpu, low, high);
            },
            0x4a => { // lsra imp
                cpu.c = cpu.a & 1 != 0;
                if (cpu.mf) {
                    cpu.a = (cpu.a & 0xff00) | ((cpu.a >> 1) & 0x7f);
                } else {
                    cpu.a >>= 1;
                }
                cpu_setZN(cpu, cpu.a, cpu.mf);
            },
            0x4b => cpu_pushByte(cpu, cpu.k), // phk imp
            0x4c => cpu.pc = cpu_readOpcodeWord(cpu), // jmp abs
            0x4d => { // eor abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x4e => { // lsr abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_lsr(cpu, low, high);
            },
            0x4f => { // eor abl
                var low: u32 = 0;
                const high = cpu_adrAbl(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x50 => { // bvc rel
                const rel = cpu_readOpcode(cpu);
                cpu_doBranch(cpu, rel, !cpu.v);
            },
            0x51 => { // eor idy(r)
                var low: u32 = 0;
                const high = cpu_adrIdy(cpu, &low, false);
                cpu_eor(cpu, low, high);
            },
            0x52 => { // eor idp
                var low: u32 = 0;
                const high = cpu_adrIdp(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x53 => { // eor isy
                var low: u32 = 0;
                const high = cpu_adrIsy(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x54 => { // mvn bm
                const dest = cpu_readOpcode(cpu);
                const src = cpu_readOpcode(cpu);
                cpu.db = dest;
                cpu_write(cpu, (@as(u32, dest) << 16) | cpu.y, cpu_read(cpu, (@as(u32, src) << 16) | cpu.x));
                cpu.a -%= 1;
                cpu.x +%= 1;
                cpu.y +%= 1;
                if (cpu.a != 0xffff) {
                    cpu.pc -%= 3;
                }
                if (cpu.xf) {
                    cpu.x &= 0xff;
                    cpu.y &= 0xff;
                }
            },
            0x55 => { // eor dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x56 => { // lsr dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_lsr(cpu, low, high);
            },
            0x57 => { // eor ily
                var low: u32 = 0;
                const high = cpu_adrIly(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x58 => cpu.i = false, // cli imp
            0x59 => { // eor aby(r)
                var low: u32 = 0;
                const high = cpu_adrAby(cpu, &low, false);
                cpu_eor(cpu, low, high);
            },
            0x5a => { // phy imp
                if (cpu.xf) {
                    cpu_pushByte(cpu, @truncate(cpu.y));
                } else {
                    cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
                    cpu_pushWord(cpu, cpu.y);
                }
            },
            0x5b => { // tcd imp
                cpu.dp = cpu.a;
                cpu_setZN(cpu, cpu.dp, false);
            },
            0x5c => { // jml abl
                const value = cpu_readOpcodeWord(cpu);
                cpu.k = cpu_readOpcode(cpu);
                cpu.pc = value;
            },
            0x5d => { // eor abx(r)
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, false);
                cpu_eor(cpu, low, high);
            },
            0x5e => { // lsr abx
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, true);
                cpu_lsr(cpu, low, high);
            },
            0x5f => { // eor alx
                var low: u32 = 0;
                const high = cpu_adrAlx(cpu, &low);
                cpu_eor(cpu, low, high);
            },
            0x60 => { // rts imp
                if (cpu.sp >= cpu.spBreakpoint and cpu.spBreakpoint != 0) {
                    std.debug.assert(cpu.sp == cpu.spBreakpoint);
                    cpu.spBreakpoint = 0;
                    HookedFunctionRts(0);
                }
                cpu.pc = cpu_pullWord(cpu) +% 1;
            },
            0x61 => { // adc idx
                var low: u32 = 0;
                const high = cpu_adrIdx(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x62 => { // per rll
                const value = cpu_readOpcodeWord(cpu);
                cpu_pushWord(cpu, cpu.pc +% value);
            },
            0x63 => { // adc sr
                var low: u32 = 0;
                const high = cpu_adrSr(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x64 => { // stz dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_stz(cpu, low, high);
            },
            0x65 => opAdcDp(cpu), // adc dp
            0x66 => { // ror dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_ror(cpu, low, high);
            },
            0x67 => { // adc idl
                var low: u32 = 0;
                const high = cpu_adrIdl(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x68 => { // pla imp
                if (cpu.mf) {
                    cpu.a = (cpu.a & 0xff00) | cpu_pullByte(cpu);
                } else {
                    cpu.cyclesUsed +%= 1; // 16-bit m: 1 extra cycle
                    cpu.a = cpu_pullWord(cpu);
                }
                cpu_setZN(cpu, cpu.a, cpu.mf);
            },
            0x69 => opAdcImm(cpu), // adc imm(m)
            0x6a => { // rora imp
                const carry = cpu.a & 1 != 0;
                if (cpu.mf) {
                    cpu.a = (cpu.a & 0xff00) | ((cpu.a >> 1) & 0x7f) | (@as(u16, @intFromBool(cpu.c)) << 7);
                } else {
                    cpu.a = (cpu.a >> 1) | (@as(u16, @intFromBool(cpu.c)) << 15);
                }
                cpu.c = carry;
                cpu_setZN(cpu, cpu.a, cpu.mf);
            },
            0x6b => { // rtl imp
                if (cpu.sp >= cpu.spBreakpoint and cpu.spBreakpoint != 0) {
                    std.debug.assert(cpu.sp == cpu.spBreakpoint);
                    cpu.spBreakpoint = 0;
                    HookedFunctionRts(1);
                }
                cpu.pc = cpu_pullWord(cpu) +% 1;
                cpu.k = cpu_pullByte(cpu);
            },
            0x6c => { // jmp ind
                const adr = cpu_readOpcodeWord(cpu);
                cpu.pc = cpu_readWord(cpu, adr, (@as(u32, adr) + 1) & 0xffff);
            },
            0x6d => { // adc abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x6e => { // ror abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_ror(cpu, low, high);
            },
            0x6f => { // adc abl
                var low: u32 = 0;
                const high = cpu_adrAbl(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x70 => { // bvs rel
                const rel = cpu_readOpcode(cpu);
                cpu_doBranch(cpu, rel, cpu.v);
            },
            0x71 => { // adc idy(r)
                var low: u32 = 0;
                const high = cpu_adrIdy(cpu, &low, false);
                cpu_adc(cpu, low, high);
            },
            0x72 => { // adc idp
                var low: u32 = 0;
                const high = cpu_adrIdp(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x73 => { // adc isy
                var low: u32 = 0;
                const high = cpu_adrIsy(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x74 => { // stz dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_stz(cpu, low, high);
            },
            0x75 => { // adc dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x76 => { // ror dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_ror(cpu, low, high);
            },
            0x77 => { // adc ily
                var low: u32 = 0;
                const high = cpu_adrIly(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x78 => cpu.i = true, // sei imp
            0x79 => { // adc aby(r)
                var low: u32 = 0;
                const high = cpu_adrAby(cpu, &low, false);
                cpu_adc(cpu, low, high);
            },
            0x7a => { // ply imp
                if (cpu.xf) {
                    cpu.y = cpu_pullByte(cpu);
                } else {
                    cpu.cyclesUsed +%= 1; // 16-bit x: 1 extra cycle
                    cpu.y = cpu_pullWord(cpu);
                }
                cpu_setZN(cpu, cpu.y, cpu.xf);
            },
            0x7b => { // tdc imp
                cpu.a = cpu.dp;
                cpu_setZN(cpu, cpu.a, false);
            },
            0x7c => cpu.pc = cpu_adrIax(cpu), // jmp iax
            0x7d => { // adc abx(r)
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, false);
                cpu_adc(cpu, low, high);
            },
            0x7e => { // ror abx
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, true);
                cpu_ror(cpu, low, high);
            },
            0x7f => { // adc alx
                var low: u32 = 0;
                const high = cpu_adrAlx(cpu, &low);
                cpu_adc(cpu, low, high);
            },
            0x80 => cpu.pc = addRel(cpu.pc, cpu_readOpcode(cpu)), // bra rel
            0x81 => { // sta idx
                var low: u32 = 0;
                const high = cpu_adrIdx(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x82 => { // brl rll
                const value = cpu_readOpcodeWord(cpu);
                cpu.pc +%= value;
            },
            0x83 => { // sta sr
                var low: u32 = 0;
                const high = cpu_adrSr(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x84 => { // sty dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_sty(cpu, low, high);
            },
            0x85 => { // sta dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x86 => { // stx dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_stx(cpu, low, high);
            },
            0x87 => { // sta idl
                var low: u32 = 0;
                const high = cpu_adrIdl(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x88 => { // dey imp
                if (cpu.xf) {
                    cpu.y = (cpu.y -% 1) & 0xff;
                } else {
                    cpu.y -%= 1;
                }
                cpu_setZN(cpu, cpu.y, cpu.xf);
            },
            0x89 => { // biti imm(m)
                if (cpu.mf) {
                    const result = @as(u8, @truncate(cpu.a)) & cpu_readOpcode(cpu);
                    cpu.z = result == 0;
                } else {
                    cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
                    const result = cpu.a & cpu_readOpcodeWord(cpu);
                    cpu.z = result == 0;
                }
            },
            0x8a => { // txa imp
                if (cpu.mf) {
                    cpu.a = (cpu.a & 0xff00) | (cpu.x & 0xff);
                } else {
                    cpu.a = cpu.x;
                }
                cpu_setZN(cpu, cpu.a, cpu.mf);
            },
            0x8b => cpu_pushByte(cpu, cpu.db), // phb imp
            0x8c => { // sty abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_sty(cpu, low, high);
            },
            0x8d => { // sta abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x8e => { // stx abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_stx(cpu, low, high);
            },
            0x8f => { // sta abl
                var low: u32 = 0;
                const high = cpu_adrAbl(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x90 => { // bcc rel
                const rel = cpu_readOpcode(cpu);
                cpu_doBranch(cpu, rel, !cpu.c);
            },
            0x91 => { // sta idy
                var low: u32 = 0;
                const high = cpu_adrIdy(cpu, &low, true);
                cpu_sta(cpu, low, high);
            },
            0x92 => { // sta idp
                var low: u32 = 0;
                const high = cpu_adrIdp(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x93 => { // sta isy
                var low: u32 = 0;
                const high = cpu_adrIsy(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x94 => { // sty dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_sty(cpu, low, high);
            },
            0x95 => { // sta dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x96 => { // stx dpy
                var low: u32 = 0;
                const high = cpu_adrDpy(cpu, &low);
                cpu_stx(cpu, low, high);
            },
            0x97 => { // sta ily
                var low: u32 = 0;
                const high = cpu_adrIly(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0x98 => { // tya imp
                if (cpu.mf) {
                    cpu.a = (cpu.a & 0xff00) | (cpu.y & 0xff);
                } else {
                    cpu.a = cpu.y;
                }
                cpu_setZN(cpu, cpu.a, cpu.mf);
            },
            0x99 => { // sta aby
                var low: u32 = 0;
                const high = cpu_adrAby(cpu, &low, true);
                cpu_sta(cpu, low, high);
            },
            0x9a => cpu.sp = cpu.x, // txs imp
            0x9b => { // txy imp
                if (cpu.xf) {
                    cpu.y = cpu.x & 0xff;
                } else {
                    cpu.y = cpu.x;
                }
                cpu_setZN(cpu, cpu.y, cpu.xf);
            },
            0x9c => { // stz abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_stz(cpu, low, high);
            },
            0x9d => { // sta abx
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, true);
                cpu_sta(cpu, low, high);
            },
            0x9e => { // stz abx
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, true);
                cpu_stz(cpu, low, high);
            },
            0x9f => { // sta alx
                var low: u32 = 0;
                const high = cpu_adrAlx(cpu, &low);
                cpu_sta(cpu, low, high);
            },
            0xa0 => { // ldy imm(x)
                var low: u32 = 0;
                const high = cpu_adrImm(cpu, &low, true);
                cpu_ldy(cpu, low, high);
            },
            0xa1 => { // lda idx
                var low: u32 = 0;
                const high = cpu_adrIdx(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xa2 => { // ldx imm(x)
                var low: u32 = 0;
                const high = cpu_adrImm(cpu, &low, true);
                cpu_ldx(cpu, low, high);
            },
            0xa3 => { // lda sr
                var low: u32 = 0;
                const high = cpu_adrSr(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xa4 => { // ldy dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_ldy(cpu, low, high);
            },
            0xa5 => { // lda dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xa6 => { // ldx dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_ldx(cpu, low, high);
            },
            0xa7 => { // lda idl
                var low: u32 = 0;
                const high = cpu_adrIdl(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xa8 => { // tay imp
                if (cpu.xf) {
                    cpu.y = cpu.a & 0xff;
                } else {
                    cpu.y = cpu.a;
                }
                cpu_setZN(cpu, cpu.y, cpu.xf);
            },
            0xa9 => { // lda imm(m)
                var low: u32 = 0;
                const high = cpu_adrImm(cpu, &low, false);
                cpu_lda(cpu, low, high);
            },
            0xaa => { // tax imp
                if (cpu.xf) {
                    cpu.x = cpu.a & 0xff;
                } else {
                    cpu.x = cpu.a;
                }
                cpu_setZN(cpu, cpu.x, cpu.xf);
            },
            0xab => { // plb imp
                cpu.db = cpu_pullByte(cpu);
                cpu_setZN(cpu, cpu.db, true);
            },
            0xac => { // ldy abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_ldy(cpu, low, high);
            },
            0xad => { // lda abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xae => { // ldx abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_ldx(cpu, low, high);
            },
            0xaf => { // lda abl
                var low: u32 = 0;
                const high = cpu_adrAbl(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xb0 => { // bcs rel
                const rel = cpu_readOpcode(cpu);
                cpu_doBranch(cpu, rel, cpu.c);
            },
            0xb1 => { // lda idy(r)
                var low: u32 = 0;
                const high = cpu_adrIdy(cpu, &low, false);
                cpu_lda(cpu, low, high);
            },
            0xb2 => { // lda idp
                var low: u32 = 0;
                const high = cpu_adrIdp(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xb3 => { // lda isy
                var low: u32 = 0;
                const high = cpu_adrIsy(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xb4 => { // ldy dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_ldy(cpu, low, high);
            },
            0xb5 => { // lda dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xb6 => { // ldx dpy
                var low: u32 = 0;
                const high = cpu_adrDpy(cpu, &low);
                cpu_ldx(cpu, low, high);
            },
            0xb7 => { // lda ily
                var low: u32 = 0;
                const high = cpu_adrIly(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xb8 => cpu.v = false, // clv imp
            0xb9 => { // lda aby(r)
                var low: u32 = 0;
                const high = cpu_adrAby(cpu, &low, false);
                cpu_lda(cpu, low, high);
            },
            0xba => { // tsx imp
                if (cpu.xf) {
                    cpu.x = cpu.sp & 0xff;
                } else {
                    cpu.x = cpu.sp;
                }
                cpu_setZN(cpu, cpu.x, cpu.xf);
            },
            0xbb => { // tyx imp
                if (cpu.xf) {
                    cpu.x = cpu.y & 0xff;
                } else {
                    cpu.x = cpu.y;
                }
                cpu_setZN(cpu, cpu.x, cpu.xf);
            },
            0xbc => { // ldy abx(r)
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, false);
                cpu_ldy(cpu, low, high);
            },
            0xbd => { // lda abx(r)
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, false);
                cpu_lda(cpu, low, high);
            },
            0xbe => { // ldx aby(r)
                var low: u32 = 0;
                const high = cpu_adrAby(cpu, &low, false);
                cpu_ldx(cpu, low, high);
            },
            0xbf => { // lda alx
                var low: u32 = 0;
                const high = cpu_adrAlx(cpu, &low);
                cpu_lda(cpu, low, high);
            },
            0xc0 => { // cpy imm(x)
                var low: u32 = 0;
                const high = cpu_adrImm(cpu, &low, true);
                cpu_cpy(cpu, low, high);
            },
            0xc1 => { // cmp idx
                var low: u32 = 0;
                const high = cpu_adrIdx(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xc2 => cpu_setFlags(cpu, cpu_getFlags(cpu) & ~cpu_readOpcode(cpu)), // rep imm(s)
            0xc3 => { // cmp sr
                var low: u32 = 0;
                const high = cpu_adrSr(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xc4 => { // cpy dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_cpy(cpu, low, high);
            },
            0xc5 => { // cmp dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xc6 => { // dec dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_dec(cpu, low, high);
            },
            0xc7 => { // cmp idl
                var low: u32 = 0;
                const high = cpu_adrIdl(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xc8 => opIny(cpu), // iny imp
            0xc9 => { // cmp imm(m)
                var low: u32 = 0;
                const high = cpu_adrImm(cpu, &low, false);
                cpu_cmp(cpu, low, high);
            },
            0xca => { // dex imp
                if (cpu.xf) {
                    cpu.x = (cpu.x -% 1) & 0xff;
                } else {
                    cpu.x -%= 1;
                }
                cpu_setZN(cpu, cpu.x, cpu.xf);
            },
            0xcb => cpu.waiting = true, // wai imp
            0xcc => { // cpy abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_cpy(cpu, low, high);
            },
            0xcd => { // cmp abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xce => { // dec abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_dec(cpu, low, high);
            },
            0xcf => { // cmp abl
                var low: u32 = 0;
                const high = cpu_adrAbl(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xd0 => { // bne rel
                const rel = cpu_readOpcode(cpu);
                cpu_doBranch(cpu, rel, !cpu.z);
            },
            0xd1 => { // cmp idy(r)
                var low: u32 = 0;
                const high = cpu_adrIdy(cpu, &low, false);
                cpu_cmp(cpu, low, high);
            },
            0xd2 => { // cmp idp
                var low: u32 = 0;
                const high = cpu_adrIdp(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xd3 => { // cmp isy
                var low: u32 = 0;
                const high = cpu_adrIsy(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xd4 => { // pei dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_pushWord(cpu, cpu_readWord(cpu, low, high));
            },
            0xd5 => { // cmp dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xd6 => { // dec dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_dec(cpu, low, high);
            },
            0xd7 => { // cmp ily
                var low: u32 = 0;
                const high = cpu_adrIly(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xd8 => cpu.d = false, // cld imp
            0xd9 => { // cmp aby(r)
                var low: u32 = 0;
                const high = cpu_adrAby(cpu, &low, false);
                cpu_cmp(cpu, low, high);
            },
            0xda => { // phx imp
                if (cpu.xf) {
                    cpu_pushByte(cpu, @truncate(cpu.x));
                } else {
                    cpu.cyclesUsed +%= 1; // m = 0: 1 extra cycle
                    cpu_pushWord(cpu, cpu.x);
                }
            },
            0xdb => cpu.stopped = true, // stp imp
            0xdc => { // jml ial
                const adr = cpu_readOpcodeWord(cpu);
                cpu.pc = cpu_readWord(cpu, adr, (@as(u32, adr) + 1) & 0xffff);
                cpu.k = cpu_read(cpu, (@as(u32, adr) + 2) & 0xffff);
            },
            0xdd => { // cmp abx(r)
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, false);
                cpu_cmp(cpu, low, high);
            },
            0xde => { // dec abx
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, true);
                cpu_dec(cpu, low, high);
            },
            0xdf => { // cmp alx
                var low: u32 = 0;
                const high = cpu_adrAlx(cpu, &low);
                cpu_cmp(cpu, low, high);
            },
            0xe0 => { // cpx imm(x)
                var low: u32 = 0;
                const high = cpu_adrImm(cpu, &low, true);
                cpu_cpx(cpu, low, high);
            },
            0xe1 => { // sbc idx
                var low: u32 = 0;
                const high = cpu_adrIdx(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
            0xe2 => cpu_setFlags(cpu, cpu_getFlags(cpu) | cpu_readOpcode(cpu)), // sep imm(s)
            0xe3 => { // sbc sr
                var low: u32 = 0;
                const high = cpu_adrSr(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
            0xe4 => { // cpx dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_cpx(cpu, low, high);
            },
            0xe5 => opSbcDp(cpu), // sbc dp
            0xe6 => { // inc dp
                var low: u32 = 0;
                const high = cpu_adrDp(cpu, &low);
                cpu_inc(cpu, low, high);
            },
            0xe7 => { // sbc idl
                var low: u32 = 0;
                const high = cpu_adrIdl(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
            0xe8 => { // inx imp
                if (cpu.xf) {
                    cpu.x = (cpu.x +% 1) & 0xff;
                } else {
                    cpu.x +%= 1;
                }
                cpu_setZN(cpu, cpu.x, cpu.xf);
            },
            0xe9 => opSbcImm(cpu), // sbc imm(m)
            0xea => {}, // nop imp
            0xeb => { // xba imp
                const low: u8 = @truncate(cpu.a);
                const high: u8 = @truncate(cpu.a >> 8);
                cpu.a = (@as(u16, low) << 8) | high;
                cpu_setZN(cpu, high, true);
            },
            0xec => { // cpx abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_cpx(cpu, low, high);
            },
            0xed => { // sbc abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
            0xee => { // inc abs
                var low: u32 = 0;
                const high = cpu_adrAbs(cpu, &low);
                cpu_inc(cpu, low, high);
            },
            0xef => { // sbc abl
                var low: u32 = 0;
                const high = cpu_adrAbl(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
            0xf0 => { // beq rel
                const rel = cpu_readOpcode(cpu);
                cpu_doBranch(cpu, rel, cpu.z);
            },
            0xf1 => { // sbc idy(r)
                var low: u32 = 0;
                const high = cpu_adrIdy(cpu, &low, false);
                cpu_sbc(cpu, low, high);
            },
            0xf2 => { // sbc idp
                var low: u32 = 0;
                const high = cpu_adrIdp(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
            0xf3 => { // sbc isy
                var low: u32 = 0;
                const high = cpu_adrIsy(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
            0xf4 => cpu_pushWord(cpu, cpu_readOpcodeWord(cpu)), // pea imm(l)
            0xf5 => { // sbc dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
            0xf6 => { // inc dpx
                var low: u32 = 0;
                const high = cpu_adrDpx(cpu, &low);
                cpu_inc(cpu, low, high);
            },
            0xf7 => { // sbc ily
                var low: u32 = 0;
                const high = cpu_adrIly(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
            0xf8 => cpu.d = true, // sed imp
            0xf9 => { // sbc aby(r)
                var low: u32 = 0;
                const high = cpu_adrAby(cpu, &low, false);
                cpu_sbc(cpu, low, high);
            },
            0xfa => { // plx imp
                if (cpu.xf) {
                    cpu.x = cpu_pullByte(cpu);
                } else {
                    cpu.cyclesUsed +%= 1; // 16-bit x: 1 extra cycle
                    cpu.x = cpu_pullWord(cpu);
                }
                cpu_setZN(cpu, cpu.x, cpu.xf);
            },
            0xfb => { // xce imp
                const temp = cpu.c;
                cpu.c = cpu.e;
                cpu.e = temp;
                // updates x and m flags, clears upper half of x and y if needed
                cpu_setFlags(cpu, cpu_getFlags(cpu));
            },
            0xfc => { // jsr iax
                const value = cpu_adrIax(cpu);
                cpu_pushWord(cpu, cpu.pc -% 1);
                cpu.pc = value;
            },
            0xfd => { // sbc abx(r)
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, false);
                cpu_sbc(cpu, low, high);
            },
            0xfe => { // inc abx
                var low: u32 = 0;
                const high = cpu_adrAbx(cpu, &low, true);
                cpu_inc(cpu, low, high);
            },
            0xff => { // sbc alx
                var low: u32 = 0;
                const high = cpu_adrAlx(cpu, &low);
                cpu_sbc(cpu, low, high);
            },
        }
        break;
    }
}

const testing = std.testing;
const cart_mod = @import("cart.zig");
const input_mod = @import("input.zig");
const Cart = cart_mod.Cart;
const Input = input_mod.Input;

/// A cpu attached to a minimal Snes: work ram plus a LoROM cart, which is
/// enough for code in ram and vectors in rom.
const TestCpu = struct {
    cpu: *Cpu,
    snes: *Snes,
    ram: *[0x20000]u8,
    rom: *[0x8000]u8,
    cart: *Cart,
    in1: *Input,
    in2: *Input,

    fn init() !TestCpu {
        const ram = try testing.allocator.create([0x20000]u8);
        @memset(ram, 0);
        const rom = try testing.allocator.create([0x8000]u8);
        @memset(rom, 0);
        const cart = try testing.allocator.create(Cart);
        cart.* = std.mem.zeroes(Cart);
        const in1 = try testing.allocator.create(Input);
        in1.* = std.mem.zeroes(Input);
        const in2 = try testing.allocator.create(Input);
        in2.* = std.mem.zeroes(Input);
        const snes = try testing.allocator.create(Snes);
        snes.* = std.mem.zeroes(Snes);
        const cpu = try testing.allocator.create(Cpu);
        cpu.* = std.mem.zeroes(Cpu);

        cart.snes = snes;
        cart.@"type" = 1; // LoROM
        cart.rom = rom;
        cart.romSize = rom.len;
        cart.ram = null;
        cart.ramSize = 0;
        snes.ram = ram;
        snes.cart = cart;
        snes.cpu = cpu;
        snes.input1 = in1;
        snes.input2 = in2;
        cpu.mem = snes;
        return .{ .cpu = cpu, .snes = snes, .ram = ram, .rom = rom, .cart = cart, .in1 = in1, .in2 = in2 };
    }

    fn deinit(self: TestCpu) void {
        testing.allocator.destroy(self.cpu);
        testing.allocator.destroy(self.snes);
        testing.allocator.destroy(self.ram);
        testing.allocator.destroy(self.rom);
        testing.allocator.destroy(self.cart);
        testing.allocator.destroy(self.in1);
        testing.allocator.destroy(self.in2);
    }

    /// Load a program at $000100 and point the pc at it.
    fn load(self: TestCpu, code: []const u8) void {
        @memcpy(self.ram[0x100..][0..code.len], code);
        self.cpu.k = 0;
        self.cpu.pc = 0x100;
    }

    fn step(self: TestCpu) c_int {
        return cpu_runOpcode(self.cpu);
    }

    /// Start in native mode with 16-bit A and index registers.
    fn native16(self: TestCpu) void {
        self.cpu.e = false;
        self.cpu.mf = false;
        self.cpu.xf = false;
    }
};

test "reset reads the vector at $fffc and starts in emulation mode" {
    const t = try TestCpu.init();
    defer t.deinit();
    // LoROM maps bank 0 $8000-$ffff to the first 32k of rom.
    t.rom[0x7ffc] = 0x34;
    t.rom[0x7ffd] = 0x12;
    cpu_reset(t.cpu);
    try testing.expectEqual(@as(u16, 0x1234), t.cpu.pc);
    try testing.expectEqual(@as(u16, 0x100), t.cpu.sp);
    try testing.expect(t.cpu.e and t.cpu.mf and t.cpu.xf and t.cpu.i);
}

test "flags pack in the documented order" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    cpu_setFlags(t.cpu, 0xff);
    try testing.expectEqual(@as(u8, 0xff), cpu_getFlags(t.cpu));
    cpu_setFlags(t.cpu, 0x00);
    try testing.expectEqual(@as(u8, 0x00), cpu_getFlags(t.cpu));
    // n and c only.
    cpu_setFlags(t.cpu, 0x81);
    try testing.expect(t.cpu.n and t.cpu.c and !t.cpu.z);
}

test "emulation mode forces the 8-bit flags and the stack page" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = true;
    t.cpu.sp = 0x01f0;
    cpu_setFlags(t.cpu, 0x00); // tries to clear m and x
    try testing.expect(t.cpu.mf and t.cpu.xf);
    try testing.expectEqual(@as(u16, 0x1f0), t.cpu.sp);
}

test "rep and sep change the register widths" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.mf = true;
    t.cpu.xf = true;

    t.load(&.{ 0xc2, 0x30 }); // rep #$30
    _ = t.step();
    try testing.expect(!t.cpu.mf and !t.cpu.xf);

    t.load(&.{ 0xe2, 0x20 }); // sep #$20
    _ = t.step();
    try testing.expect(t.cpu.mf and !t.cpu.xf);
}

test "xce swaps carry and the emulation bit" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = true;
    t.cpu.c = false;
    t.load(&.{0xfb}); // xce -> native mode
    _ = t.step();
    try testing.expect(!t.cpu.e and t.cpu.c);

    t.load(&.{0xfb}); // and back
    _ = t.step();
    try testing.expect(t.cpu.e and !t.cpu.c);
}

test "lda immediate is one or two bytes depending on m" {
    const t = try TestCpu.init();
    defer t.deinit();

    t.cpu.e = false;
    t.cpu.mf = true;
    t.cpu.a = 0xff00;
    t.load(&.{ 0xa9, 0x42 }); // lda #$42
    _ = t.step();
    try testing.expectEqual(@as(u16, 0xff42), t.cpu.a); // high byte preserved
    try testing.expectEqual(@as(u16, 0x102), t.cpu.pc);

    t.native16();
    t.load(&.{ 0xa9, 0x34, 0x12 }); // lda #$1234
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x1234), t.cpu.a);
    try testing.expectEqual(@as(u16, 0x103), t.cpu.pc);
    try testing.expect(!t.cpu.z and !t.cpu.n);
}

test "adc adds with carry and sets overflow" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.mf = true;

    t.cpu.a = 0x7f;
    t.cpu.c = false;
    t.load(&.{ 0x69, 0x01 }); // adc #$01
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x80), t.cpu.a);
    try testing.expect(t.cpu.v and t.cpu.n and !t.cpu.c);

    t.cpu.a = 0xff;
    t.cpu.c = false;
    t.load(&.{ 0x69, 0x01 });
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x00), t.cpu.a);
    try testing.expect(t.cpu.c and t.cpu.z and !t.cpu.v);
}

test "adc in decimal mode carries at nine" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.mf = true;
    t.cpu.d = true;

    t.cpu.a = 0x09;
    t.cpu.c = false;
    t.load(&.{ 0x69, 0x01 }); // adc #$01 -> 0x10 in bcd
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x10), t.cpu.a);

    t.cpu.a = 0x99;
    t.cpu.c = false;
    t.load(&.{ 0x69, 0x01 }); // wraps to 0x00 with carry
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x00), t.cpu.a);
    try testing.expect(t.cpu.c);
}

test "sbc subtracts using the carry as a borrow" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.mf = true;

    t.cpu.a = 0x10;
    t.cpu.c = true; // no borrow
    t.load(&.{ 0xe9, 0x01 }); // sbc #$01
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x0f), t.cpu.a);
    try testing.expect(t.cpu.c);

    t.cpu.a = 0x00;
    t.cpu.c = true;
    t.load(&.{ 0xe9, 0x01 });
    _ = t.step();
    try testing.expectEqual(@as(u16, 0xff), t.cpu.a);
    try testing.expect(!t.cpu.c); // borrowed
}

test "cmp leaves the accumulator alone" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.mf = true;
    t.cpu.a = 0x40;

    t.load(&.{ 0xc9, 0x40 }); // cmp #$40
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x40), t.cpu.a);
    try testing.expect(t.cpu.z and t.cpu.c);

    t.load(&.{ 0xc9, 0x50 });
    _ = t.step();
    try testing.expect(!t.cpu.z and !t.cpu.c);
}

test "direct page addressing adds the dp register" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.mf = true;

    t.ram[0x0012] = 0xaa;
    t.ram[0x0112] = 0xbb;

    t.cpu.dp = 0;
    t.load(&.{ 0xa5, 0x12 }); // lda $12
    _ = t.step();
    try testing.expectEqual(@as(u16, 0xaa), t.cpu.a);

    t.cpu.dp = 0x100;
    t.load(&.{ 0xa5, 0x12 });
    _ = t.step();
    try testing.expectEqual(@as(u16, 0xbb), t.cpu.a);
}

test "a non-zero low byte of dp costs an extra cycle" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.mf = true;

    t.cpu.dp = 0x0100;
    t.load(&.{ 0xa5, 0x12 }); // lda dp
    const aligned = t.step();
    t.cpu.dp = 0x0101;
    t.load(&.{ 0xa5, 0x12 });
    const unaligned = t.step();
    try testing.expectEqual(aligned + 1, unaligned);
}

test "16-bit stores write both bytes" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.native16();
    t.cpu.a = 0x1234;
    t.cpu.db = 0;

    t.load(&.{ 0x8d, 0x00, 0x10 }); // sta $1000
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x34), t.ram[0x1000]);
    try testing.expectEqual(@as(u8, 0x12), t.ram[0x1001]);
}

test "jsr and rts round trip through the stack" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.sp = 0x1ff;

    t.load(&.{ 0x20, 0x00, 0x02 }); // jsr $0200
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x0200), t.cpu.pc);
    try testing.expectEqual(@as(u16, 0x1fd), t.cpu.sp);

    t.ram[0x200] = 0x60; // rts
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x103), t.cpu.pc);
    try testing.expectEqual(@as(u16, 0x1ff), t.cpu.sp);
}

test "jsl and rtl carry the bank too" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.sp = 0x1ff;

    t.load(&.{ 0x22, 0x00, 0x02, 0x00 }); // jsl $000200
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x0200), t.cpu.pc);
    try testing.expectEqual(@as(u8, 0), t.cpu.k);
    try testing.expectEqual(@as(u16, 0x1fc), t.cpu.sp);

    t.ram[0x200] = 0x6b; // rtl
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x104), t.cpu.pc);
    try testing.expectEqual(@as(u16, 0x1ff), t.cpu.sp);
}

test "branches are relative and cost an extra cycle when taken" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;

    t.cpu.z = true;
    t.load(&.{ 0xf0, 0x10 }); // beq +16
    const taken = t.step();
    try testing.expectEqual(@as(u16, 0x112), t.cpu.pc);

    t.cpu.z = false;
    t.load(&.{ 0xf0, 0x10 });
    const not_taken = t.step();
    try testing.expectEqual(@as(u16, 0x102), t.cpu.pc);
    try testing.expectEqual(not_taken + 1, taken);

    // Backwards branches sign extend.
    t.cpu.z = true;
    t.load(&.{ 0xf0, 0xfc }); // beq -4
    _ = t.step();
    try testing.expectEqual(@as(u16, 0xfe), t.cpu.pc);
}

test "xba swaps the halves of the accumulator" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.native16();
    t.cpu.a = 0x1234;
    t.load(&.{0xeb});
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x3412), t.cpu.a);
}

test "index registers stay eight bits wide while x is set" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.xf = true;
    t.cpu.x = 0xff;
    t.load(&.{0xe8}); // inx
    _ = t.step();
    try testing.expectEqual(@as(u16, 0), t.cpu.x);
    try testing.expect(t.cpu.z);

    t.cpu.xf = false;
    t.cpu.x = 0xff;
    t.load(&.{0xe8});
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x100), t.cpu.x);
}

test "an nmi pushes the state and vectors through $ffea" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.sp = 0x1ff;
    t.cpu.pc = 0x100;
    t.cpu.k = 0;
    t.rom[0x7fea] = 0x00;
    t.rom[0x7feb] = 0x80;

    t.cpu.nmiWanted = true;
    const cycles = t.step();
    try testing.expectEqual(@as(u16, 0x8000), t.cpu.pc);
    try testing.expect(t.cpu.i and !t.cpu.d);
    try testing.expect(!t.cpu.nmiWanted);
    try testing.expectEqual(@as(c_int, 8), cycles); // 7 + 1 for native mode
}

test "an irq is ignored while the i flag is set" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.cpu.sp = 0x1ff;
    t.cpu.i = true;
    t.cpu.irqWanted = true;
    t.load(&.{0xea}); // nop
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x101), t.cpu.pc); // ran the nop
    try testing.expect(t.cpu.irqWanted); // still pending
}

test "wai parks the cpu until an interrupt arrives" {
    const t = try TestCpu.init();
    defer t.deinit();
    t.cpu.e = false;
    t.load(&.{0xcb}); // wai
    _ = t.step();
    try testing.expect(t.cpu.waiting);
    try testing.expectEqual(@as(c_int, 1), t.step()); // parked
    try testing.expect(t.cpu.waiting);

    t.cpu.irqWanted = true;
    _ = t.step();
    try testing.expect(!t.cpu.waiting);
}

test "the cycle table came over intact" {
    try testing.expectEqual(256, cyclesPerOpcode.len);
    try testing.expectEqual(7, cyclesPerOpcode[0x00]); // brk
    try testing.expectEqual(2, cyclesPerOpcode[0xea]); // nop
    try testing.expectEqual(6, cyclesPerOpcode[0x20]); // jsr abs
    try testing.expectEqual(8, cyclesPerOpcode[0x22]); // jsl abl
    try testing.expectEqual(6, cyclesPerOpcode[0x60]); // rts
    try testing.expectEqual(8, cyclesPerOpcode[0xfc]); // jsr iax
}
