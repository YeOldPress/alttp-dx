//! Port of snes/spc.c: the SPC700 core.
const std = @import("std");
const snes_types = @import("snes_types.zig");
const apu_mod = @import("apu.zig");

const SaveLoadFunc = snes_types.SaveLoadFunc;
const Apu = apu_mod.Apu;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

/// Must match `struct Spc` in spc.h.
pub const Spc = extern struct {
    apu: ?*Apu,
    // registers
    a: u8,
    x: u8,
    y: u8,
    sp: u8,
    pc: u16,
    // flags
    c: bool,
    z: bool,
    v: bool,
    n: bool,
    i: bool,
    h: bool,
    p: bool,
    b: bool,
    // stopping
    stopped: bool,
    // internal use
    cyclesUsed: u8, // indicates how many cycles an opcode used
};

const cyclesPerOpcode = [256]u8{
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 5, 4, 5, 4, 6, 8,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 6, 5, 2, 2, 4, 6,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 5, 4, 5, 4, 5, 4,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 6, 5, 2, 2, 3, 8,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 4, 4, 5, 4, 6, 6,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 4, 5, 2, 2, 4, 3,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 4, 4, 5, 4, 5, 5,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 5, 5, 2, 2, 3, 6,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 5, 4, 5, 2, 4, 5,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 5, 5, 2, 2, 12, 5,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 6, 4, 4, 5, 2, 4, 4,
    2, 8, 4, 5, 4, 5, 5, 6, 5, 5, 5, 5, 2, 2, 3, 4,
    2, 8, 4, 5, 4, 5, 4, 7, 2, 5, 6, 4, 5, 2, 4, 9,
    2, 8, 4, 5, 5, 6, 6, 7, 4, 5, 5, 5, 2, 2, 6, 3,
    2, 8, 4, 5, 3, 4, 3, 6, 2, 4, 5, 3, 4, 3, 4, 3,
    2, 8, 4, 5, 4, 5, 5, 6, 3, 4, 5, 4, 2, 2, 4, 3,
};

fn spc_read(spc: *Spc, adr: u16) u8 {
    return apu_mod.apu_cpuRead(spc.apu.?, adr);
}

fn spc_write(spc: *Spc, adr: u16, val: u8) void {
    apu_mod.apu_cpuWrite(spc.apu.?, adr, val);
}

pub export fn spc_init(apu: *Apu) callconv(.c) *Spc {
    const spc: *Spc = @ptrCast(@alignCast(malloc(@sizeOf(Spc)).?));
    spc.apu = apu;
    return spc;
}

pub export fn spc_free(spc: *Spc) callconv(.c) void {
    free(spc);
}

pub export fn spc_reset(spc: *Spc) callconv(.c) void {
    spc.a = 0;
    spc.x = 0;
    spc.y = 0;
    spc.sp = 0;
    spc.pc = @as(u16, spc_read(spc, 0xfffe)) | (@as(u16, spc_read(spc, 0xffff)) << 8);
    spc.c = false;
    spc.z = false;
    spc.v = false;
    spc.n = false;
    spc.i = false;
    spc.h = false;
    spc.p = false;
    spc.b = false;
    spc.stopped = false;
    spc.cyclesUsed = 0;
}

pub export fn spc_saveload(spc: *Spc, func: *const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    func(ctx, &spc.a, @offsetOf(Spc, "cyclesUsed") - @offsetOf(Spc, "a"));
}

pub export fn spc_runOpcode(spc: *Spc) callconv(.c) c_int {
    spc.cyclesUsed = 0;
    if (spc.stopped) return 1;
    const opcode = spc_readOpcode(spc);
    spc.cyclesUsed = cyclesPerOpcode[opcode];
    spc_doOpcode(spc, opcode);
    return spc.cyclesUsed;
}

fn spc_readOpcode(spc: *Spc) u8 {
    const val = spc_read(spc, spc.pc);
    spc.pc +%= 1;
    return val;
}

fn spc_readOpcodeWord(spc: *Spc) u16 {
    const low = spc_readOpcode(spc);
    return @as(u16, low) | (@as(u16, spc_readOpcode(spc)) << 8);
}

fn spc_getFlags(spc: *Spc) u8 {
    var val: u8 = @as(u8, @intFromBool(spc.n)) << 7;
    val |= @as(u8, @intFromBool(spc.v)) << 6;
    val |= @as(u8, @intFromBool(spc.p)) << 5;
    val |= @as(u8, @intFromBool(spc.b)) << 4;
    val |= @as(u8, @intFromBool(spc.h)) << 3;
    val |= @as(u8, @intFromBool(spc.i)) << 2;
    val |= @as(u8, @intFromBool(spc.z)) << 1;
    val |= @intFromBool(spc.c);
    return val;
}

fn spc_setFlags(spc: *Spc, val: u8) void {
    spc.n = val & 0x80 != 0;
    spc.v = val & 0x40 != 0;
    spc.p = val & 0x20 != 0;
    spc.b = val & 0x10 != 0;
    spc.h = val & 8 != 0;
    spc.i = val & 4 != 0;
    spc.z = val & 2 != 0;
    spc.c = val & 1 != 0;
}

fn spc_setZN(spc: *Spc, value: u8) void {
    spc.z = value == 0;
    spc.n = value & 0x80 != 0;
}

fn spc_doBranch(spc: *Spc, value: u8, check: bool) void {
    if (check) {
        spc.cyclesUsed +%= 2; // taken branch: 2 extra cycles
        spc.pc = addRel(spc.pc, value);
    }
}

/// pc += (int8_t)value, wrapping.
fn addRel(pc: u16, value: u8) u16 {
    const rel: i8 = @bitCast(value);
    return pc +% @as(u16, @bitCast(@as(i16, rel)));
}

fn spc_pullByte(spc: *Spc) u8 {
    spc.sp +%= 1;
    return spc_read(spc, 0x100 | @as(u16, spc.sp));
}

fn spc_pushByte(spc: *Spc, value: u8) void {
    spc_write(spc, 0x100 | @as(u16, spc.sp), value);
    spc.sp -%= 1;
}

fn spc_pullWord(spc: *Spc) u16 {
    const value = spc_pullByte(spc);
    return @as(u16, value) | (@as(u16, spc_pullByte(spc)) << 8);
}

fn spc_pushWord(spc: *Spc, value: u16) void {
    spc_pushByte(spc, @truncate(value >> 8));
    spc_pushByte(spc, @truncate(value));
}

fn spc_readWord(spc: *Spc, adrl: u16, adrh: u16) u16 {
    const value = spc_read(spc, adrl);
    return @as(u16, value) | (@as(u16, spc_read(spc, adrh)) << 8);
}

fn spc_writeWord(spc: *Spc, adrl: u16, adrh: u16, value: u16) void {
    spc_write(spc, adrl, @truncate(value));
    spc_write(spc, adrh, @truncate(value >> 8));
}

/// The direct page selector, as the high byte of an address.
fn dp(spc: *Spc) u16 {
    return @as(u16, @intFromBool(spc.p)) << 8;
}

// adressing modes

fn spc_adrDp(spc: *Spc) u16 {
    return @as(u16, spc_readOpcode(spc)) | dp(spc);
}

fn spc_adrAbs(spc: *Spc) u16 {
    return spc_readOpcodeWord(spc);
}

fn spc_adrInd(spc: *Spc) u16 {
    return @as(u16, spc.x) | dp(spc);
}

fn spc_adrIdx(spc: *Spc) u16 {
    const pointer = spc_readOpcode(spc);
    const lo = @as(u16, pointer +% spc.x) | dp(spc);
    const hi = @as(u16, pointer +% spc.x +% 1) | dp(spc);
    return spc_readWord(spc, lo, hi);
}

fn spc_adrImm(spc: *Spc) u16 {
    const adr = spc.pc;
    spc.pc +%= 1;
    return adr;
}

fn spc_adrDpx(spc: *Spc) u16 {
    return @as(u16, spc_readOpcode(spc) +% spc.x) | dp(spc);
}

fn spc_adrDpy(spc: *Spc) u16 {
    return @as(u16, spc_readOpcode(spc) +% spc.y) | dp(spc);
}

fn spc_adrAbx(spc: *Spc) u16 {
    return spc_readOpcodeWord(spc) +% spc.x;
}

fn spc_adrAby(spc: *Spc) u16 {
    return spc_readOpcodeWord(spc) +% spc.y;
}

fn spc_adrIdy(spc: *Spc) u16 {
    const pointer = spc_readOpcode(spc);
    const adr = spc_readWord(spc, @as(u16, pointer) | dp(spc), @as(u16, pointer +% 1) | dp(spc));
    return adr +% spc.y;
}

fn spc_adrDpDp(spc: *Spc, src: *u16) u16 {
    src.* = @as(u16, spc_readOpcode(spc)) | dp(spc);
    return @as(u16, spc_readOpcode(spc)) | dp(spc);
}

fn spc_adrDpImm(spc: *Spc, src: *u16) u16 {
    src.* = spc.pc;
    spc.pc +%= 1;
    return @as(u16, spc_readOpcode(spc)) | dp(spc);
}

fn spc_adrIndInd(spc: *Spc, src: *u16) u16 {
    src.* = @as(u16, spc.y) | dp(spc);
    return @as(u16, spc.x) | dp(spc);
}

fn spc_adrAbsBit(spc: *Spc, adr: *u16) u3 {
    const adrBit = spc_readOpcodeWord(spc);
    adr.* = adrBit & 0x1fff;
    return @truncate(adrBit >> 13);
}

fn spc_adrDpWord(spc: *Spc, low: *u16) u16 {
    const adr = spc_readOpcode(spc);
    low.* = @as(u16, adr) | dp(spc);
    return @as(u16, adr +% 1) | dp(spc);
}

fn spc_adrIndP(spc: *Spc) u16 {
    const adr = @as(u16, spc.x) | dp(spc);
    spc.x +%= 1;
    return adr;
}

// opcode functions

fn spc_and(spc: *Spc, adr: u16) void {
    spc.a &= spc_read(spc, adr);
    spc_setZN(spc, spc.a);
}

fn spc_andm(spc: *Spc, dst: u16, src: u16) void {
    const value = spc_read(spc, src);
    const result = spc_read(spc, dst) & value;
    spc_write(spc, dst, result);
    spc_setZN(spc, result);
}

fn spc_or(spc: *Spc, adr: u16) void {
    spc.a |= spc_read(spc, adr);
    spc_setZN(spc, spc.a);
}

fn spc_orm(spc: *Spc, dst: u16, src: u16) void {
    const value = spc_read(spc, src);
    const result = spc_read(spc, dst) | value;
    spc_write(spc, dst, result);
    spc_setZN(spc, result);
}

fn spc_eor(spc: *Spc, adr: u16) void {
    spc.a ^= spc_read(spc, adr);
    spc_setZN(spc, spc.a);
}

fn spc_eorm(spc: *Spc, dst: u16, src: u16) void {
    const value = spc_read(spc, src);
    const result = spc_read(spc, dst) ^ value;
    spc_write(spc, dst, result);
    spc_setZN(spc, result);
}

/// The shared body of adc/sbc: sbc feeds in the complemented operand.
fn addWithCarry(spc: *Spc, applyOn: u8, value: u8) u8 {
    const carry: i32 = @intFromBool(spc.c);
    const result: i32 = @as(i32, applyOn) + value + carry;
    spc.v = (applyOn & 0x80) == (value & 0x80) and (value & 0x80) != (result & 0x80);
    spc.h = ((applyOn & 0xf) + (value & 0xf) + carry) > 0xf;
    spc.c = result > 0xff;
    return @truncate(@as(u32, @bitCast(result)));
}

fn spc_adc(spc: *Spc, adr: u16) void {
    const value = spc_read(spc, adr);
    spc.a = addWithCarry(spc, spc.a, value);
    spc_setZN(spc, spc.a);
}

fn spc_adcm(spc: *Spc, dst: u16, src: u16) void {
    const value = spc_read(spc, src);
    const applyOn = spc_read(spc, dst);
    const result = addWithCarry(spc, applyOn, value);
    spc_write(spc, dst, result);
    spc_setZN(spc, result);
}

fn spc_sbc(spc: *Spc, adr: u16) void {
    const value = spc_read(spc, adr) ^ 0xff;
    spc.a = addWithCarry(spc, spc.a, value);
    spc_setZN(spc, spc.a);
}

fn spc_sbcm(spc: *Spc, dst: u16, src: u16) void {
    const value = spc_read(spc, src) ^ 0xff;
    const applyOn = spc_read(spc, dst);
    const result = addWithCarry(spc, applyOn, value);
    spc_write(spc, dst, result);
    spc_setZN(spc, result);
}

/// compare: applyOn + ~value + 1, setting only c, z and n.
fn compare(spc: *Spc, applyOn: u8, value: u8) void {
    const result: i32 = @as(i32, applyOn) + value + 1;
    spc.c = result > 0xff;
    spc_setZN(spc, @truncate(@as(u32, @bitCast(result))));
}

fn spc_cmp(spc: *Spc, adr: u16) void {
    compare(spc, spc.a, spc_read(spc, adr) ^ 0xff);
}

fn spc_cmpx(spc: *Spc, adr: u16) void {
    compare(spc, spc.x, spc_read(spc, adr) ^ 0xff);
}

fn spc_cmpy(spc: *Spc, adr: u16) void {
    compare(spc, spc.y, spc_read(spc, adr) ^ 0xff);
}

fn spc_cmpm(spc: *Spc, dst: u16, src: u16) void {
    const value = spc_read(spc, src) ^ 0xff;
    compare(spc, spc_read(spc, dst), value);
}

fn spc_mov(spc: *Spc, adr: u16) void {
    spc.a = spc_read(spc, adr);
    spc_setZN(spc, spc.a);
}

fn spc_movx(spc: *Spc, adr: u16) void {
    spc.x = spc_read(spc, adr);
    spc_setZN(spc, spc.x);
}

fn spc_movy(spc: *Spc, adr: u16) void {
    spc.y = spc_read(spc, adr);
    spc_setZN(spc, spc.y);
}

fn spc_movs(spc: *Spc, adr: u16) void {
    _ = spc_read(spc, adr);
    spc_write(spc, adr, spc.a);
}

fn spc_movsx(spc: *Spc, adr: u16) void {
    _ = spc_read(spc, adr);
    spc_write(spc, adr, spc.x);
}

fn spc_movsy(spc: *Spc, adr: u16) void {
    _ = spc_read(spc, adr);
    spc_write(spc, adr, spc.y);
}

fn spc_asl(spc: *Spc, adr: u16) void {
    var val = spc_read(spc, adr);
    spc.c = val & 0x80 != 0;
    val <<= 1;
    spc_write(spc, adr, val);
    spc_setZN(spc, val);
}

fn spc_lsr(spc: *Spc, adr: u16) void {
    var val = spc_read(spc, adr);
    spc.c = val & 1 != 0;
    val >>= 1;
    spc_write(spc, adr, val);
    spc_setZN(spc, val);
}

fn spc_rol(spc: *Spc, adr: u16) void {
    var val = spc_read(spc, adr);
    const newC = val & 0x80 != 0;
    val = (val << 1) | @intFromBool(spc.c);
    spc.c = newC;
    spc_write(spc, adr, val);
    spc_setZN(spc, val);
}

fn spc_ror(spc: *Spc, adr: u16) void {
    var val = spc_read(spc, adr);
    const newC = val & 1 != 0;
    val = (val >> 1) | (@as(u8, @intFromBool(spc.c)) << 7);
    spc.c = newC;
    spc_write(spc, adr, val);
    spc_setZN(spc, val);
}

fn spc_inc(spc: *Spc, adr: u16) void {
    const val = spc_read(spc, adr) +% 1;
    spc_write(spc, adr, val);
    spc_setZN(spc, val);
}

fn spc_dec(spc: *Spc, adr: u16) void {
    const val = spc_read(spc, adr) -% 1;
    spc_write(spc, adr, val);
    spc_setZN(spc, val);
}

/// The YA register pair as one 16-bit value.
fn ya(spc: *Spc) u16 {
    return @as(u16, spc.a) | (@as(u16, spc.y) << 8);
}

fn setYa(spc: *Spc, value: u16) void {
    spc.a = @truncate(value);
    spc.y = @truncate(value >> 8);
}

fn spc_doOpcode(spc: *Spc, opcode: u8) void {
    switch (opcode) {
        0x00 => {}, // nop imp
        // tcall imp
        0x01, 0x11, 0x21, 0x31, 0x41, 0x51, 0x61, 0x71, 0x81, 0x91, 0xa1, 0xb1, 0xc1, 0xd1, 0xe1, 0xf1 => {
            spc_pushWord(spc, spc.pc);
            const adr = 0xffde - (2 * @as(u16, opcode >> 4));
            spc.pc = spc_readWord(spc, adr, adr +% 1);
        },
        // set1 dp
        0x02, 0x22, 0x42, 0x62, 0x82, 0xa2, 0xc2, 0xe2 => {
            const adr = spc_adrDp(spc);
            spc_write(spc, adr, spc_read(spc, adr) | (@as(u8, 1) << @truncate(opcode >> 5)));
        },
        // clr1 dp
        0x12, 0x32, 0x52, 0x72, 0x92, 0xb2, 0xd2, 0xf2 => {
            const adr = spc_adrDp(spc);
            spc_write(spc, adr, spc_read(spc, adr) & ~(@as(u8, 1) << @truncate(opcode >> 5)));
        },
        // bbs dp, rel
        0x03, 0x23, 0x43, 0x63, 0x83, 0xa3, 0xc3, 0xe3 => {
            const val = spc_read(spc, spc_adrDp(spc));
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, val & (@as(u8, 1) << @truncate(opcode >> 5)) != 0);
        },
        // bbc dp, rel
        0x13, 0x33, 0x53, 0x73, 0x93, 0xb3, 0xd3, 0xf3 => {
            const val = spc_read(spc, spc_adrDp(spc));
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, (val & (@as(u8, 1) << @truncate(opcode >> 5))) == 0);
        },
        0x04 => spc_or(spc, spc_adrDp(spc)), // or  dp
        0x05 => spc_or(spc, spc_adrAbs(spc)), // or  abs
        0x06 => spc_or(spc, spc_adrInd(spc)), // or  ind
        0x07 => spc_or(spc, spc_adrIdx(spc)), // or  idx
        0x08 => spc_or(spc, spc_adrImm(spc)), // or  imm
        0x09 => { // orm dp, dp
            var src: u16 = 0;
            const dst = spc_adrDpDp(spc, &src);
            spc_orm(spc, dst, src);
        },
        0x0a => { // or1 abs.bit
            var adr: u16 = 0;
            const bit = spc_adrAbsBit(spc, &adr);
            spc.c = spc.c or ((spc_read(spc, adr) >> bit) & 1) != 0;
        },
        0x0b => spc_asl(spc, spc_adrDp(spc)), // asl dp
        0x0c => spc_asl(spc, spc_adrAbs(spc)), // asl abs
        0x0d => spc_pushByte(spc, spc_getFlags(spc)), // pushp imp
        0x0e => { // tset1 abs
            const adr = spc_adrAbs(spc);
            const val = spc_read(spc, adr);
            const result = spc.a +% (val ^ 0xff) +% 1;
            spc_setZN(spc, result);
            spc_write(spc, adr, val | spc.a);
        },
        0x0f => { // brk imp
            spc_pushWord(spc, spc.pc);
            spc_pushByte(spc, spc_getFlags(spc));
            spc.i = false;
            spc.b = true;
            spc.pc = spc_readWord(spc, 0xffde, 0xffdf);
        },
        0x10 => { // bpl rel
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, !spc.n);
        },
        0x14 => spc_or(spc, spc_adrDpx(spc)), // or  dpx
        0x15 => spc_or(spc, spc_adrAbx(spc)), // or  abx
        0x16 => spc_or(spc, spc_adrAby(spc)), // or  aby
        0x17 => spc_or(spc, spc_adrIdy(spc)), // or  idy
        0x18 => { // orm dp, imm
            var src: u16 = 0;
            const dst = spc_adrDpImm(spc, &src);
            spc_orm(spc, dst, src);
        },
        0x19 => { // orm ind, ind
            var src: u16 = 0;
            const dst = spc_adrIndInd(spc, &src);
            spc_orm(spc, dst, src);
        },
        0x1a => { // decw dp
            var low: u16 = 0;
            const high = spc_adrDpWord(spc, &low);
            const value = spc_readWord(spc, low, high) -% 1;
            spc.z = value == 0;
            spc.n = value & 0x8000 != 0;
            spc_writeWord(spc, low, high, value);
        },
        0x1b => spc_asl(spc, spc_adrDpx(spc)), // asl dpx
        0x1c => { // asla imp
            spc.c = spc.a & 0x80 != 0;
            spc.a <<= 1;
            spc_setZN(spc, spc.a);
        },
        0x1d => { // decx imp
            spc.x -%= 1;
            spc_setZN(spc, spc.x);
        },
        0x1e => spc_cmpx(spc, spc_adrAbs(spc)), // cmpx abs
        0x1f => { // jmp iax
            const pointer = spc_readOpcodeWord(spc);
            spc.pc = spc_readWord(spc, pointer +% spc.x, pointer +% spc.x +% 1);
        },
        0x20 => spc.p = false, // clrp imp
        0x24 => spc_and(spc, spc_adrDp(spc)), // and dp
        0x25 => spc_and(spc, spc_adrAbs(spc)), // and abs
        0x26 => spc_and(spc, spc_adrInd(spc)), // and ind
        0x27 => spc_and(spc, spc_adrIdx(spc)), // and idx
        0x28 => spc_and(spc, spc_adrImm(spc)), // and imm
        0x29 => { // andm dp, dp
            var src: u16 = 0;
            const dst = spc_adrDpDp(spc, &src);
            spc_andm(spc, dst, src);
        },
        0x2a => { // or1n abs.bit
            var adr: u16 = 0;
            const bit = spc_adrAbsBit(spc, &adr);
            spc.c = spc.c or (~(spc_read(spc, adr) >> bit) & 1) != 0;
        },
        0x2b => spc_rol(spc, spc_adrDp(spc)), // rol dp
        0x2c => spc_rol(spc, spc_adrAbs(spc)), // rol abs
        0x2d => spc_pushByte(spc, spc.a), // pusha imp
        0x2e => { // cbne dp, rel
            const val = spc_read(spc, spc_adrDp(spc)) ^ 0xff;
            const result = spc.a +% val +% 1;
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, result != 0);
        },
        0x2f => { // bra rel
            // Fetch the operand first: the branch is relative to the byte
            // after it (the same slip as the main cpu's BRA had).
            const rel = spc_readOpcode(spc);
            spc.pc = addRel(spc.pc, rel);
        },
        0x30 => { // bmi rel
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, spc.n);
        },
        0x34 => spc_and(spc, spc_adrDpx(spc)), // and dpx
        0x35 => spc_and(spc, spc_adrAbx(spc)), // and abx
        0x36 => spc_and(spc, spc_adrAby(spc)), // and aby
        0x37 => spc_and(spc, spc_adrIdy(spc)), // and idy
        0x38 => { // andm dp, imm
            var src: u16 = 0;
            const dst = spc_adrDpImm(spc, &src);
            spc_andm(spc, dst, src);
        },
        0x39 => { // andm ind, ind
            var src: u16 = 0;
            const dst = spc_adrIndInd(spc, &src);
            spc_andm(spc, dst, src);
        },
        0x3a => { // incw dp
            var low: u16 = 0;
            const high = spc_adrDpWord(spc, &low);
            const value = spc_readWord(spc, low, high) +% 1;
            spc.z = value == 0;
            spc.n = value & 0x8000 != 0;
            spc_writeWord(spc, low, high, value);
        },
        0x3b => spc_rol(spc, spc_adrDpx(spc)), // rol dpx
        0x3c => { // rola imp
            const newC = spc.a & 0x80 != 0;
            spc.a = (spc.a << 1) | @intFromBool(spc.c);
            spc.c = newC;
            spc_setZN(spc, spc.a);
        },
        0x3d => { // incx imp
            spc.x +%= 1;
            spc_setZN(spc, spc.x);
        },
        0x3e => spc_cmpx(spc, spc_adrDp(spc)), // cmpx dp
        0x3f => { // call abs
            const dst = spc_readOpcodeWord(spc);
            spc_pushWord(spc, spc.pc);
            spc.pc = dst;
        },
        0x40 => spc.p = true, // setp imp
        0x44 => spc_eor(spc, spc_adrDp(spc)), // eor dp
        0x45 => spc_eor(spc, spc_adrAbs(spc)), // eor abs
        0x46 => spc_eor(spc, spc_adrInd(spc)), // eor ind
        0x47 => spc_eor(spc, spc_adrIdx(spc)), // eor idx
        0x48 => spc_eor(spc, spc_adrImm(spc)), // eor imm
        0x49 => { // eorm dp, dp
            var src: u16 = 0;
            const dst = spc_adrDpDp(spc, &src);
            spc_eorm(spc, dst, src);
        },
        0x4a => { // and1 abs.bit
            var adr: u16 = 0;
            const bit = spc_adrAbsBit(spc, &adr);
            spc.c = spc.c and ((spc_read(spc, adr) >> bit) & 1) != 0;
        },
        0x4b => spc_lsr(spc, spc_adrDp(spc)), // lsr dp
        0x4c => spc_lsr(spc, spc_adrAbs(spc)), // lsr abs
        0x4d => spc_pushByte(spc, spc.x), // pushx imp
        0x4e => { // tclr1 abs
            const adr = spc_adrAbs(spc);
            const val = spc_read(spc, adr);
            const result = spc.a +% (val ^ 0xff) +% 1;
            spc_setZN(spc, result);
            spc_write(spc, adr, val & ~spc.a);
        },
        0x4f => { // pcall dp
            const dst = spc_readOpcode(spc);
            spc_pushWord(spc, spc.pc);
            spc.pc = 0xff00 | @as(u16, dst);
        },
        0x50 => { // bvc rel
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, !spc.v);
        },
        0x54 => spc_eor(spc, spc_adrDpx(spc)), // eor dpx
        0x55 => spc_eor(spc, spc_adrAbx(spc)), // eor abx
        0x56 => spc_eor(spc, spc_adrAby(spc)), // eor aby
        0x57 => spc_eor(spc, spc_adrIdy(spc)), // eor idy
        0x58 => { // eorm dp, imm
            var src: u16 = 0;
            const dst = spc_adrDpImm(spc, &src);
            spc_eorm(spc, dst, src);
        },
        0x59 => { // eorm ind, ind
            var src: u16 = 0;
            const dst = spc_adrIndInd(spc, &src);
            spc_eorm(spc, dst, src);
        },
        0x5a => { // cmpw dp
            var low: u16 = 0;
            const high = spc_adrDpWord(spc, &low);
            const value = spc_readWord(spc, low, high) ^ 0xffff;
            const result: i32 = @as(i32, ya(spc)) + value + 1;
            spc.c = result > 0xffff;
            spc.z = (result & 0xffff) == 0;
            spc.n = result & 0x8000 != 0;
        },
        0x5b => spc_lsr(spc, spc_adrDpx(spc)), // lsr dpx
        0x5c => { // lsra imp
            spc.c = spc.a & 1 != 0;
            spc.a >>= 1;
            spc_setZN(spc, spc.a);
        },
        0x5d => { // movxa imp
            spc.x = spc.a;
            spc_setZN(spc, spc.x);
        },
        0x5e => spc_cmpy(spc, spc_adrAbs(spc)), // cmpy abs
        0x5f => spc.pc = spc_readOpcodeWord(spc), // jmp abs
        0x60 => spc.c = false, // clrc imp
        0x64 => spc_cmp(spc, spc_adrDp(spc)), // cmp dp
        0x65 => spc_cmp(spc, spc_adrAbs(spc)), // cmp abs
        0x66 => spc_cmp(spc, spc_adrInd(spc)), // cmp ind
        0x67 => spc_cmp(spc, spc_adrIdx(spc)), // cmp idx
        0x68 => spc_cmp(spc, spc_adrImm(spc)), // cmp imm
        0x69 => { // cmpm dp, dp
            var src: u16 = 0;
            const dst = spc_adrDpDp(spc, &src);
            spc_cmpm(spc, dst, src);
        },
        0x6a => { // and1n abs.bit
            var adr: u16 = 0;
            const bit = spc_adrAbsBit(spc, &adr);
            spc.c = spc.c and (~(spc_read(spc, adr) >> bit) & 1) != 0;
        },
        0x6b => spc_ror(spc, spc_adrDp(spc)), // ror dp
        0x6c => spc_ror(spc, spc_adrAbs(spc)), // ror abs
        0x6d => spc_pushByte(spc, spc.y), // pushy imp
        0x6e => { // dbnz dp, rel
            const adr = spc_adrDp(spc);
            const result = spc_read(spc, adr) -% 1;
            spc_write(spc, adr, result);
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, result != 0);
        },
        0x6f => spc.pc = spc_pullWord(spc), // ret imp
        0x70 => { // bvs rel
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, spc.v);
        },
        0x74 => spc_cmp(spc, spc_adrDpx(spc)), // cmp dpx
        0x75 => spc_cmp(spc, spc_adrAbx(spc)), // cmp abx
        0x76 => spc_cmp(spc, spc_adrAby(spc)), // cmp aby
        0x77 => spc_cmp(spc, spc_adrIdy(spc)), // cmp idy
        0x78 => { // cmpm dp, imm
            var src: u16 = 0;
            const dst = spc_adrDpImm(spc, &src);
            spc_cmpm(spc, dst, src);
        },
        0x79 => { // cmpm ind, ind
            var src: u16 = 0;
            const dst = spc_adrIndInd(spc, &src);
            spc_cmpm(spc, dst, src);
        },
        0x7a => { // addw dp
            var low: u16 = 0;
            const high = spc_adrDpWord(spc, &low);
            const value = spc_readWord(spc, low, high);
            const before = ya(spc);
            const result: i32 = @as(i32, before) + value;
            spc.v = (before & 0x8000) == (value & 0x8000) and (value & 0x8000) != (result & 0x8000);
            spc.h = ((before & 0xfff) + (value & 0xfff) + 1) > 0xfff;
            spc.c = result > 0xffff;
            spc.z = (result & 0xffff) == 0;
            spc.n = result & 0x8000 != 0;
            setYa(spc, @truncate(@as(u32, @bitCast(result))));
        },
        0x7b => spc_ror(spc, spc_adrDpx(spc)), // ror dpx
        0x7c => { // rora imp
            const newC = spc.a & 1 != 0;
            spc.a = (spc.a >> 1) | (@as(u8, @intFromBool(spc.c)) << 7);
            spc.c = newC;
            spc_setZN(spc, spc.a);
        },
        0x7d => { // movax imp
            spc.a = spc.x;
            spc_setZN(spc, spc.a);
        },
        0x7e => spc_cmpy(spc, spc_adrDp(spc)), // cmpy dp
        0x7f => { // reti imp
            spc_setFlags(spc, spc_pullByte(spc));
            spc.pc = spc_pullWord(spc);
        },
        0x80 => spc.c = true, // setc imp
        0x84 => spc_adc(spc, spc_adrDp(spc)), // adc dp
        0x85 => spc_adc(spc, spc_adrAbs(spc)), // adc abs
        0x86 => spc_adc(spc, spc_adrInd(spc)), // adc ind
        0x87 => spc_adc(spc, spc_adrIdx(spc)), // adc idx
        0x88 => spc_adc(spc, spc_adrImm(spc)), // adc imm
        0x89 => { // adcm dp, dp
            var src: u16 = 0;
            const dst = spc_adrDpDp(spc, &src);
            spc_adcm(spc, dst, src);
        },
        0x8a => { // eor1 abs.bit
            var adr: u16 = 0;
            const bit = spc_adrAbsBit(spc, &adr);
            spc.c = (@intFromBool(spc.c) ^ ((spc_read(spc, adr) >> bit) & 1)) != 0;
        },
        0x8b => spc_dec(spc, spc_adrDp(spc)), // dec dp
        0x8c => spc_dec(spc, spc_adrAbs(spc)), // dec abs
        0x8d => spc_movy(spc, spc_adrImm(spc)), // movy imm
        0x8e => spc_setFlags(spc, spc_pullByte(spc)), // popp imp
        0x8f => { // movm dp, imm
            var src: u16 = 0;
            const dst = spc_adrDpImm(spc, &src);
            const val = spc_read(spc, src);
            _ = spc_read(spc, dst);
            spc_write(spc, dst, val);
        },
        0x90 => { // bcc rel
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, !spc.c);
        },
        0x94 => spc_adc(spc, spc_adrDpx(spc)), // adc dpx
        0x95 => spc_adc(spc, spc_adrAbx(spc)), // adc abx
        0x96 => spc_adc(spc, spc_adrAby(spc)), // adc aby
        0x97 => spc_adc(spc, spc_adrIdy(spc)), // adc idy
        0x98 => { // adcm dp, imm
            var src: u16 = 0;
            const dst = spc_adrDpImm(spc, &src);
            spc_adcm(spc, dst, src);
        },
        0x99 => { // adcm ind, ind
            var src: u16 = 0;
            const dst = spc_adrIndInd(spc, &src);
            spc_adcm(spc, dst, src);
        },
        0x9a => { // subw dp
            var low: u16 = 0;
            const high = spc_adrDpWord(spc, &low);
            const value = spc_readWord(spc, low, high) ^ 0xffff;
            const before = ya(spc);
            const result: i32 = @as(i32, before) + value + 1;
            spc.v = (before & 0x8000) == (value & 0x8000) and (value & 0x8000) != (result & 0x8000);
            spc.h = ((before & 0xfff) + (value & 0xfff) + 1) > 0xfff;
            spc.c = result > 0xffff;
            spc.z = (result & 0xffff) == 0;
            spc.n = result & 0x8000 != 0;
            setYa(spc, @truncate(@as(u32, @bitCast(result))));
        },
        0x9b => spc_dec(spc, spc_adrDpx(spc)), // dec dpx
        0x9c => { // deca imp
            spc.a -%= 1;
            spc_setZN(spc, spc.a);
        },
        0x9d => { // movxp imp
            spc.x = spc.sp;
            spc_setZN(spc, spc.x);
        },
        0x9e => { // div imp
            // TODO: proper division algorithm
            const value = ya(spc);
            var result: i32 = 0xffff;
            var mod: i32 = spc.a;
            if (spc.x != 0) {
                result = @divTrunc(@as(i32, value), spc.x);
                mod = @rem(@as(i32, value), spc.x);
            }
            spc.v = result > 0xff;
            spc.h = (spc.x & 0xf) <= (spc.y & 0xf);
            spc.a = @truncate(@as(u32, @bitCast(result)));
            spc.y = @truncate(@as(u32, @bitCast(mod)));
            spc_setZN(spc, spc.a);
        },
        0x9f => { // xcn imp
            spc.a = (spc.a >> 4) | (spc.a << 4);
            spc_setZN(spc, spc.a);
        },
        0xa0 => spc.i = true, // ei  imp
        0xa4 => spc_sbc(spc, spc_adrDp(spc)), // sbc dp
        0xa5 => spc_sbc(spc, spc_adrAbs(spc)), // sbc abs
        0xa6 => spc_sbc(spc, spc_adrInd(spc)), // sbc ind
        0xa7 => spc_sbc(spc, spc_adrIdx(spc)), // sbc idx
        0xa8 => spc_sbc(spc, spc_adrImm(spc)), // sbc imm
        0xa9 => { // sbcm dp, dp
            var src: u16 = 0;
            const dst = spc_adrDpDp(spc, &src);
            spc_sbcm(spc, dst, src);
        },
        0xaa => { // mov1 abs.bit
            var adr: u16 = 0;
            const bit = spc_adrAbsBit(spc, &adr);
            spc.c = ((spc_read(spc, adr) >> bit) & 1) != 0;
        },
        0xab => spc_inc(spc, spc_adrDp(spc)), // inc dp
        0xac => spc_inc(spc, spc_adrAbs(spc)), // inc abs
        0xad => spc_cmpy(spc, spc_adrImm(spc)), // cmpy imm
        0xae => spc.a = spc_pullByte(spc), // popa imp
        0xaf => { // movs ind+
            const adr = spc_adrIndP(spc);
            spc_write(spc, adr, spc.a);
        },
        0xb0 => { // bcs rel
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, spc.c);
        },
        0xb4 => spc_sbc(spc, spc_adrDpx(spc)), // sbc dpx
        0xb5 => spc_sbc(spc, spc_adrAbx(spc)), // sbc abx
        0xb6 => spc_sbc(spc, spc_adrAby(spc)), // sbc aby
        0xb7 => spc_sbc(spc, spc_adrIdy(spc)), // sbc idy
        0xb8 => { // sbcm dp, imm
            var src: u16 = 0;
            const dst = spc_adrDpImm(spc, &src);
            spc_sbcm(spc, dst, src);
        },
        0xb9 => { // sbcm ind, ind
            var src: u16 = 0;
            const dst = spc_adrIndInd(spc, &src);
            spc_sbcm(spc, dst, src);
        },
        0xba => { // movw dp
            var low: u16 = 0;
            const high = spc_adrDpWord(spc, &low);
            const val = spc_readWord(spc, low, high);
            setYa(spc, val);
            spc.z = val == 0;
            spc.n = val & 0x8000 != 0;
        },
        0xbb => spc_inc(spc, spc_adrDpx(spc)), // inc dpx
        0xbc => { // inca imp
            spc.a +%= 1;
            spc_setZN(spc, spc.a);
        },
        0xbd => spc.sp = spc.x, // movpx imp
        0xbe => { // das imp
            if (spc.a > 0x99 or !spc.c) {
                spc.a -%= 0x60;
                spc.c = false;
            }
            if ((spc.a & 0xf) > 9 or !spc.h) {
                spc.a -%= 6;
            }
            spc_setZN(spc, spc.a);
        },
        0xbf => { // mov ind+
            const adr = spc_adrIndP(spc);
            spc.a = spc_read(spc, adr);
            spc_setZN(spc, spc.a);
        },
        0xc0 => spc.i = false, // di  imp
        0xc4 => spc_movs(spc, spc_adrDp(spc)), // movs dp
        0xc5 => spc_movs(spc, spc_adrAbs(spc)), // movs abs
        0xc6 => spc_movs(spc, spc_adrInd(spc)), // movs ind
        0xc7 => spc_movs(spc, spc_adrIdx(spc)), // movs idx
        0xc8 => spc_cmpx(spc, spc_adrImm(spc)), // cmpx imm
        0xc9 => spc_movsx(spc, spc_adrAbs(spc)), // movsx abs
        0xca => { // mov1s abs.bit
            var adr: u16 = 0;
            const bit = spc_adrAbsBit(spc, &adr);
            const result = (spc_read(spc, adr) & ~(@as(u8, 1) << bit)) |
                (@as(u8, @intFromBool(spc.c)) << bit);
            spc_write(spc, adr, result);
        },
        0xcb => spc_movsy(spc, spc_adrDp(spc)), // movsy dp
        0xcc => spc_movsy(spc, spc_adrAbs(spc)), // movsy abs
        0xcd => spc_movx(spc, spc_adrImm(spc)), // movx imm
        0xce => spc.x = spc_pullByte(spc), // popx imp
        0xcf => { // mul imp
            const result = @as(u16, spc.a) *% spc.y;
            setYa(spc, result);
            spc_setZN(spc, spc.y);
        },
        0xd0 => { // bne rel
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, !spc.z);
        },
        0xd4 => spc_movs(spc, spc_adrDpx(spc)), // movs dpx
        0xd5 => spc_movs(spc, spc_adrAbx(spc)), // movs abx
        0xd6 => spc_movs(spc, spc_adrAby(spc)), // movs aby
        0xd7 => spc_movs(spc, spc_adrIdy(spc)), // movs idy
        0xd8 => spc_movsx(spc, spc_adrDp(spc)), // movsx dp
        0xd9 => spc_movsx(spc, spc_adrDpy(spc)), // movsx dpy
        0xda => { // movws dp
            var low: u16 = 0;
            const high = spc_adrDpWord(spc, &low);
            _ = spc_read(spc, low);
            spc_write(spc, low, spc.a);
            spc_write(spc, high, spc.y);
        },
        0xdb => spc_movsy(spc, spc_adrDpx(spc)), // movsy dpx
        0xdc => { // decy imp
            spc.y -%= 1;
            spc_setZN(spc, spc.y);
        },
        0xdd => { // movay imp
            spc.a = spc.y;
            spc_setZN(spc, spc.a);
        },
        0xde => { // cbne dpx, rel
            const val = spc_read(spc, spc_adrDpx(spc)) ^ 0xff;
            const result = spc.a +% val +% 1;
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, result != 0);
        },
        0xdf => { // daa imp
            if (spc.a > 0x99 or spc.c) {
                spc.a +%= 0x60;
                spc.c = true;
            }
            if ((spc.a & 0xf) > 9 or spc.h) {
                spc.a +%= 6;
            }
            spc_setZN(spc, spc.a);
        },
        0xe0 => { // clrv imp
            spc.v = false;
            spc.h = false;
        },
        0xe4 => spc_mov(spc, spc_adrDp(spc)), // mov dp
        0xe5 => spc_mov(spc, spc_adrAbs(spc)), // mov abs
        0xe6 => spc_mov(spc, spc_adrInd(spc)), // mov ind
        0xe7 => spc_mov(spc, spc_adrIdx(spc)), // mov idx
        0xe8 => spc_mov(spc, spc_adrImm(spc)), // mov imm
        0xe9 => spc_movx(spc, spc_adrAbs(spc)), // movx abs
        0xea => { // not1 abs.bit
            var adr: u16 = 0;
            const bit = spc_adrAbsBit(spc, &adr);
            const result = spc_read(spc, adr) ^ (@as(u8, 1) << bit);
            spc_write(spc, adr, result);
        },
        0xeb => spc_movy(spc, spc_adrDp(spc)), // movy dp
        0xec => spc_movy(spc, spc_adrAbs(spc)), // movy abs
        0xed => spc.c = !spc.c, // notc imp
        0xee => spc.y = spc_pullByte(spc), // popy imp
        0xef => spc.stopped = true, // sleep imp: no interrupts, so sleeping stops as well
        0xf0 => { // beq rel
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, spc.z);
        },
        0xf4 => spc_mov(spc, spc_adrDpx(spc)), // mov dpx
        0xf5 => spc_mov(spc, spc_adrAbx(spc)), // mov abx
        0xf6 => spc_mov(spc, spc_adrAby(spc)), // mov aby
        0xf7 => spc_mov(spc, spc_adrIdy(spc)), // mov idy
        0xf8 => spc_movx(spc, spc_adrDp(spc)), // movx dp
        0xf9 => spc_movx(spc, spc_adrDpy(spc)), // movx dpy
        0xfa => { // movm dp, dp
            var src: u16 = 0;
            const dst = spc_adrDpDp(spc, &src);
            const val = spc_read(spc, src);
            spc_write(spc, dst, val);
        },
        0xfb => spc_movy(spc, spc_adrDpx(spc)), // movy dpx
        0xfc => { // incy imp
            spc.y +%= 1;
            spc_setZN(spc, spc.y);
        },
        0xfd => { // movya imp
            spc.y = spc.a;
            spc_setZN(spc, spc.y);
        },
        0xfe => { // dbnzy rel
            spc.y -%= 1;
            const rel = spc_readOpcode(spc);
            spc_doBranch(spc, rel, spc.y != 0);
        },
        0xff => spc.stopped = true, // stop imp
        // Every one of the 256 opcodes is accounted for above; the unused
        // slots fall into the nop-like prongs rather than an else.
    }
}

const testing = std.testing;

/// An Spc wired to a real Apu, so reads and writes go through the actual
/// memory map. Programs are written straight into apu ram.
const TestSpc = struct {
    spc: *Spc,
    apu: *Apu,

    fn init() !TestSpc {
        const apu = try testing.allocator.create(Apu);
        apu.* = std.mem.zeroes(Apu);
        const spc = try testing.allocator.create(Spc);
        spc.* = std.mem.zeroes(Spc);
        spc.apu = apu;
        return .{ .spc = spc, .apu = apu };
    }

    fn deinit(self: TestSpc) void {
        testing.allocator.destroy(self.spc);
        testing.allocator.destroy(self.apu);
    }

    /// Load a program at $0200 and point the pc at it.
    fn load(self: TestSpc, code: []const u8) void {
        @memcpy(self.apu.ram[0x200..][0..code.len], code);
        self.spc.pc = 0x200;
    }

    fn step(self: TestSpc) c_int {
        return spc_runOpcode(self.spc);
    }
};

test "bra is relative to the byte after its operand" {
    const t = try TestSpc.init();
    defer t.deinit();
    t.load(&.{ 0x2f, 0x10 });
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x0212), t.spc.pc);
    t.load(&.{ 0x2f, 0xfe });
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x0200), t.spc.pc);
}

test "reset reads the vector at $fffe through the boot rom" {
    const t = try TestSpc.init();
    defer t.deinit();
    t.apu.romReadable = true;
    spc_reset(t.spc);
    // The last two bytes of the boot rom are $ffc0.
    try testing.expectEqual(@as(u16, 0xffc0), t.spc.pc);
    try testing.expectEqual(@as(u8, 0), t.spc.a);
    try testing.expect(!t.spc.stopped);
}

test "flags pack and unpack in the documented order" {
    const t = try TestSpc.init();
    defer t.deinit();
    spc_setFlags(t.spc, 0xff);
    try testing.expect(t.spc.n and t.spc.v and t.spc.p and t.spc.b);
    try testing.expect(t.spc.h and t.spc.i and t.spc.z and t.spc.c);
    try testing.expectEqual(@as(u8, 0xff), spc_getFlags(t.spc));

    spc_setFlags(t.spc, 0x81); // n + c
    try testing.expectEqual(@as(u8, 0x81), spc_getFlags(t.spc));
    try testing.expect(t.spc.n and t.spc.c and !t.spc.z);
}

test "mov imm loads a and sets z and n" {
    const t = try TestSpc.init();
    defer t.deinit();
    t.load(&.{ 0xe8, 0x00 }); // mov a, #$00
    try testing.expectEqual(@as(c_int, 2), t.step());
    try testing.expectEqual(@as(u8, 0), t.spc.a);
    try testing.expect(t.spc.z and !t.spc.n);

    t.load(&.{ 0xe8, 0x80 }); // mov a, #$80
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x80), t.spc.a);
    try testing.expect(!t.spc.z and t.spc.n);
}

test "adc sets carry, overflow and half carry" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.spc.a = 0xff;
    t.spc.c = false;
    t.load(&.{ 0x88, 0x01 }); // adc a, #$01
    _ = t.step();
    try testing.expectEqual(@as(u8, 0), t.spc.a);
    try testing.expect(t.spc.c and t.spc.z and t.spc.h);
    try testing.expect(!t.spc.v); // 0xff + 1 is not a signed overflow

    // 0x7f + 0x01 overflows from positive to negative.
    t.spc.a = 0x7f;
    t.spc.c = false;
    t.load(&.{ 0x88, 0x01 });
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x80), t.spc.a);
    try testing.expect(t.spc.v and t.spc.n and !t.spc.c);

    // The incoming carry is added in.
    t.spc.a = 0x10;
    t.spc.c = true;
    t.load(&.{ 0x88, 0x01 });
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x12), t.spc.a);
}

test "sbc borrows through the carry flag" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.spc.a = 0x10;
    t.spc.c = true; // no borrow
    t.load(&.{ 0xa8, 0x01 }); // sbc a, #$01
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x0f), t.spc.a);
    try testing.expect(t.spc.c);

    t.spc.a = 0x00;
    t.spc.c = true;
    t.load(&.{ 0xa8, 0x01 });
    _ = t.step();
    try testing.expectEqual(@as(u8, 0xff), t.spc.a);
    try testing.expect(!t.spc.c); // borrow occurred
}

test "cmp sets flags without touching the accumulator" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.spc.a = 0x40;
    t.load(&.{ 0x68, 0x40 }); // cmp a, #$40
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x40), t.spc.a);
    try testing.expect(t.spc.z and t.spc.c);

    t.load(&.{ 0x68, 0x50 }); // cmp a, #$50 -> a < operand
    _ = t.step();
    try testing.expect(!t.spc.z and !t.spc.c);
}

test "direct page addressing follows the p flag" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.apu.ram[0x0012] = 0xaa;
    t.apu.ram[0x0112] = 0xbb;

    t.spc.p = false;
    t.load(&.{ 0xe4, 0x12 }); // mov a, $12
    _ = t.step();
    try testing.expectEqual(@as(u8, 0xaa), t.spc.a);

    t.spc.p = true;
    t.load(&.{ 0xe4, 0x12 });
    _ = t.step();
    try testing.expectEqual(@as(u8, 0xbb), t.spc.a);
}

test "indexed addressing wraps inside the direct page" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.apu.ram[0x0002] = 0x77;
    t.spc.x = 0x04;
    t.load(&.{ 0xf4, 0xfe }); // mov a, $fe+x -> wraps to $02
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x77), t.spc.a);
}

test "branches are relative and cost two extra cycles when taken" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.spc.z = true;
    t.load(&.{ 0xf0, 0x10 }); // beq +16
    try testing.expectEqual(@as(c_int, 4), t.step()); // 2 + 2 taken
    try testing.expectEqual(@as(u16, 0x212), t.spc.pc);

    t.spc.z = false;
    t.load(&.{ 0xf0, 0x10 });
    try testing.expectEqual(@as(c_int, 2), t.step()); // not taken
    try testing.expectEqual(@as(u16, 0x202), t.spc.pc);

    // Backwards branches sign extend.
    t.spc.z = true;
    t.load(&.{ 0xf0, 0xfc }); // beq -4
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x1fe), t.spc.pc);
}

test "call and ret move through the stack page" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.spc.sp = 0xff;
    t.load(&.{ 0x3f, 0x00, 0x03 }); // call $0300
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x0300), t.spc.pc);
    try testing.expectEqual(@as(u8, 0xfd), t.spc.sp);
    // The return address sits at $1fe/$1ff, low byte first from the top.
    try testing.expectEqual(@as(u8, 0x02), t.apu.ram[0x1ff]);
    try testing.expectEqual(@as(u8, 0x03), t.apu.ram[0x1fe]);

    t.apu.ram[0x300] = 0x6f; // ret
    t.spc.pc = 0x300;
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x203), t.spc.pc);
    try testing.expectEqual(@as(u8, 0xff), t.spc.sp);
}

test "tcall jumps through the table at the top of memory" {
    const t = try TestSpc.init();
    defer t.deinit();
    t.spc.sp = 0xff;
    t.apu.romReadable = false;
    // The table runs downwards from $ffde: tcall 0 reads its vector there, and
    // each higher call number steps back another two bytes.
    t.apu.ram[0xffde] = 0x34;
    t.apu.ram[0xffdf] = 0x12;
    t.apu.ram[0xffc0] = 0x78;
    t.apu.ram[0xffc1] = 0x56;

    t.load(&.{0x01}); // tcall 0
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x1234), t.spc.pc);

    t.load(&.{0xf1}); // tcall 15
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x5678), t.spc.pc);
}

test "mul and div use the ya pair" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.spc.a = 0x10;
    t.spc.y = 0x10;
    t.load(&.{0xcf}); // mul ya
    _ = t.step();
    try testing.expectEqual(@as(u16, 0x0100), @as(u16, t.spc.a) | (@as(u16, t.spc.y) << 8));

    t.spc.a = 0x00;
    t.spc.y = 0x01; // ya = 0x0100
    t.spc.x = 0x10;
    t.load(&.{0x9e}); // div ya, x
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x10), t.spc.a); // quotient
    try testing.expectEqual(@as(u8, 0x00), t.spc.y); // remainder

    // Dividing by zero leaves the documented junk rather than trapping.
    t.spc.a = 0x20;
    t.spc.y = 0x00;
    t.spc.x = 0x00;
    t.load(&.{0x9e});
    _ = t.step();
    try testing.expectEqual(@as(u8, 0xff), t.spc.a);
}

test "16-bit word ops on the direct page" {
    const t = try TestSpc.init();
    defer t.deinit();

    // movw ya, $10
    t.apu.ram[0x10] = 0x34;
    t.apu.ram[0x11] = 0x12;
    t.load(&.{ 0xba, 0x10 });
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x34), t.spc.a);
    try testing.expectEqual(@as(u8, 0x12), t.spc.y);

    // incw $10
    t.load(&.{ 0x3a, 0x10 });
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x35), t.apu.ram[0x10]);

    // addw ya, $10
    t.spc.a = 0x01;
    t.spc.y = 0x00;
    t.load(&.{ 0x7a, 0x10 });
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x36), t.spc.a);
    try testing.expectEqual(@as(u8, 0x12), t.spc.y);
}

test "bit set, clear and test instructions" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.apu.ram[0x20] = 0x00;
    t.load(&.{ 0x02, 0x20 }); // set1 $20.0
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x01), t.apu.ram[0x20]);

    t.load(&.{ 0xe2, 0x20 }); // set1 $20.7
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x81), t.apu.ram[0x20]);

    t.load(&.{ 0x12, 0x20 }); // clr1 $20.0
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x80), t.apu.ram[0x20]);

    // mov1 c, $0020.7 pulls bit 7 into the carry.
    t.spc.c = false;
    t.load(&.{ 0xaa, 0x20, 0xe0 }); // adr $20, bit 7
    _ = t.step();
    try testing.expect(t.spc.c);
}

test "dbnz counts down and branches until zero" {
    const t = try TestSpc.init();
    defer t.deinit();

    t.apu.ram[0x30] = 2;
    t.load(&.{ 0x6e, 0x30, 0xfd }); // dbnz $30, -3
    _ = t.step();
    try testing.expectEqual(@as(u8, 1), t.apu.ram[0x30]);
    try testing.expectEqual(@as(u16, 0x200), t.spc.pc); // looped back

    _ = t.step();
    try testing.expectEqual(@as(u8, 0), t.apu.ram[0x30]);
    try testing.expectEqual(@as(u16, 0x203), t.spc.pc); // fell through
}

test "stop and sleep halt the core" {
    const t = try TestSpc.init();
    defer t.deinit();
    t.load(&.{0xff}); // stop
    _ = t.step();
    try testing.expect(t.spc.stopped);
    // A stopped core burns one cycle per call and does not advance.
    const pc = t.spc.pc;
    try testing.expectEqual(@as(c_int, 1), t.step());
    try testing.expectEqual(pc, t.spc.pc);
}

test "xcn swaps the nibbles of a" {
    const t = try TestSpc.init();
    defer t.deinit();
    t.spc.a = 0x12;
    t.load(&.{0x9f});
    _ = t.step();
    try testing.expectEqual(@as(u8, 0x21), t.spc.a);
}

test "the cycle table came over intact" {
    try testing.expectEqual(256, cyclesPerOpcode.len);
    try testing.expectEqual(2, cyclesPerOpcode[0x00]); // nop
    try testing.expectEqual(8, cyclesPerOpcode[0x01]); // tcall
    try testing.expectEqual(12, cyclesPerOpcode[0x9e]); // div
    try testing.expectEqual(9, cyclesPerOpcode[0xcf]); // mul
    try testing.expectEqual(3, cyclesPerOpcode[0xff]); // stop
}

test "Spc layout matches spc.h" {
    // Offsets taken from the C compiler on this target.
    if (@sizeOf(*anyopaque) != 8) return error.SkipZigTest;
    try testing.expectEqual(24, @sizeOf(Spc));
    try testing.expectEqual(8, @offsetOf(Spc, "a"));
    try testing.expectEqual(12, @offsetOf(Spc, "pc"));
    try testing.expectEqual(14, @offsetOf(Spc, "c"));
    try testing.expectEqual(23, @offsetOf(Spc, "cyclesUsed"));
    // The block spc_saveload hands to the save file.
    try testing.expectEqual(15, @offsetOf(Spc, "cyclesUsed") - @offsetOf(Spc, "a"));
}
