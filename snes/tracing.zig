//! Port of snes/tracing.c: the debug disassembler and CPU/SPC state lines.
//! The opcode tables live in the generated tracing_tables.zig.
const std = @import("std");
const tables = @import("tracing_tables.zig");
const snes_types = @import("snes_types.zig");
const snes_mod = @import("snes.zig");
const apu_mod = @import("apu.zig");
const spc_mod = @import("spc.zig");
const cpu_types = @import("cpu_types.zig");

const Snes = snes_types.Snes;
const Apu = apu_mod.Apu;
const Cpu = cpu_types.Cpu;
const Spc = spc_mod.Spc;

extern fn sprintf(buf: [*]u8, fmt: [*:0]const u8, ...) c_int;

fn cpuOf(snes: *Snes) *Cpu {
    return @ptrCast(@alignCast(snes.cpu.?));
}

fn spcOf(apu: *Apu) *Spc {
    return @ptrCast(@alignCast(apu.spc.?));
}

fn flagChar(set: bool, upper: u8) c_uint {
    // 'N' when the flag is set, 'n' when it is clear.
    return if (set) upper else upper + 0x20;
}

//        1         2         3         4         5         6         7         8
// 345678901234567890123456789012345678901234567890123456789012345678901234567890
// CPU 12:3456 1234567890123 A:1234 X:1234 Y:1234 SP:1234 DP:1234 DP:12 e nvmxdizc
pub export fn getProcessorStateCpu(snes: *Snes, line: [*]u8) callconv(.c) void {
    var disLine: [14]u8 = @splat(' ');
    disLine[13] = 0;
    getDisassemblyCpu(snes, &disLine);
    const cpu = cpuOf(snes);
    _ = sprintf(
        line,
        "CPU %02x:%04x %s A:%04x X:%04x Y:%04x SP:%04x DP:%04x DB:%02x %c %c%c%c%c%c%c%c%c",
        @as(c_uint, cpu.k),
        @as(c_uint, cpu.pc),
        @as([*:0]const u8, @ptrCast(&disLine)),
        @as(c_uint, cpu.a),
        @as(c_uint, cpu.x),
        @as(c_uint, cpu.y),
        @as(c_uint, cpu.sp),
        @as(c_uint, cpu.dp),
        @as(c_uint, cpu.db),
        flagChar(cpu.e, 'E'),
        flagChar(cpu.n, 'N'),
        flagChar(cpu.v, 'V'),
        flagChar(cpu.mf, 'M'),
        flagChar(cpu.xf, 'X'),
        flagChar(cpu.d, 'D'),
        flagChar(cpu.i, 'I'),
        flagChar(cpu.z, 'Z'),
        flagChar(cpu.c, 'C'),
    );
}

//        1         2         3         4         5         6         7         8
// 345678901234567890123456789012345678901234567890123456789012345678901234567890
// SPC 3456 12345678901234567 A:12 X:12 Y:12 SP:12 nvpbhizc
pub export fn getProcessorStateSpc(apu: *Apu, line: [*]u8) callconv(.c) void {
    var disLine: [18]u8 = @splat(' ');
    disLine[17] = 0;
    getDisassemblySpc(apu, &disLine);
    const spc = spcOf(apu);
    _ = sprintf(
        line,
        "SPC %04x %s A:%02x X:%02x Y:%02x SP:%02x %c%c%c%c%c%c%c%c",
        @as(c_uint, spc.pc),
        @as([*:0]const u8, @ptrCast(&disLine)),
        @as(c_uint, spc.a),
        @as(c_uint, spc.x),
        @as(c_uint, spc.y),
        @as(c_uint, spc.sp),
        flagChar(spc.n, 'N'),
        flagChar(spc.v, 'V'),
        flagChar(spc.p, 'P'),
        flagChar(spc.b, 'B'),
        flagChar(spc.h, 'H'),
        flagChar(spc.i, 'I'),
        flagChar(spc.z, 'Z'),
        flagChar(spc.c, 'C'),
    );
}

fn getDisassemblyCpu(snes: *Snes, line: [*]u8) void {
    const cpu = cpuOf(snes);
    const adr: u32 = @as(u32, cpu.pc) | (@as(u32, cpu.k) << 16);
    // read 4 bytes
    // TODO: this can have side effects, implement and use peaking
    const opcode = snes_mod.snes_read(snes, adr);
    const byte = snes_mod.snes_read(snes, (adr + 1) & 0xffffff);
    const byte2 = snes_mod.snes_read(snes, (adr + 2) & 0xffffff);
    const word: u16 = (@as(u16, byte2) << 8) | byte;
    const longv: u32 = (@as(u32, snes_mod.snes_read(snes, (adr + 3) & 0xffffff)) << 16) | word;
    const rel: u16 = cpu.pc +% 2 +% signExtend8(byte);
    const rell: u16 = cpu.pc +% 3 +% word;
    const fmt = tables.opcodeNames[opcode];
    // switch on type
    switch (tables.opcodeType[opcode]) {
        0 => _ = sprintf(line, "%s", fmt),
        1 => _ = sprintf(line, fmt, @as(c_uint, byte)),
        2 => _ = sprintf(line, fmt, @as(c_uint, word)),
        3 => _ = sprintf(line, fmt, @as(c_uint, longv)),
        4 => {
            if (cpu.mf) {
                _ = sprintf(line, tables.opcodeNamesSp[opcode].?, @as(c_uint, byte));
            } else {
                _ = sprintf(line, fmt, @as(c_uint, word));
            }
        },
        5 => {
            if (cpu.xf) {
                _ = sprintf(line, tables.opcodeNamesSp[opcode].?, @as(c_uint, byte));
            } else {
                _ = sprintf(line, fmt, @as(c_uint, word));
            }
        },
        6 => _ = sprintf(line, fmt, @as(c_uint, rel)),
        7 => _ = sprintf(line, fmt, @as(c_uint, rell)),
        8 => _ = sprintf(line, fmt, @as(c_uint, byte2), @as(c_uint, byte)),
        else => {},
    }
}

pub export fn getDisassemblySpc(apu: *Apu, line: [*]u8) callconv(.c) void {
    const spc = spcOf(apu);
    const adr: u16 = spc.pc;
    // read 3 bytes
    // TODO: this can have side effects, implement and use peaking
    const opcode = apu_mod.apu_cpuRead(apu, adr);
    const byte = apu_mod.apu_cpuRead(apu, adr +% 1);
    const byte2 = apu_mod.apu_cpuRead(apu, adr +% 2);
    const word: u16 = (@as(u16, byte2) << 8) | byte;
    const rel: u16 = spc.pc +% 2 +% signExtend8(byte);
    const rel2: u16 = spc.pc +% 2 +% signExtend8(byte2);
    const wordb: u16 = word & 0x1fff;
    const bit: u8 = @truncate(word >> 13);
    const fmt = tables.opcodeNamesSpc[opcode];
    // switch on type
    switch (tables.opcodeTypeSpc[opcode]) {
        0 => _ = sprintf(line, "%s", fmt),
        1 => _ = sprintf(line, fmt, @as(c_uint, byte)),
        2 => _ = sprintf(line, fmt, @as(c_uint, word)),
        3 => _ = sprintf(line, fmt, @as(c_uint, rel)),
        4 => _ = sprintf(line, fmt, @as(c_uint, byte2), @as(c_uint, byte)),
        5 => _ = sprintf(line, fmt, @as(c_uint, byte), @as(c_uint, rel2)),
        6 => _ = sprintf(line, fmt, @as(c_uint, wordb), @as(c_uint, bit)),
        else => {},
    }
}

fn signExtend8(v: u8) u16 {
    return @bitCast(@as(i16, @as(i8, @bitCast(v))));
}

const testing = std.testing;

/// Cut at the NUL the C formatting wrote, then drop the padding spaces the
/// opcode templates carry.
fn trimmed(line: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, line, 0) orelse line.len;
    var stop = end;
    while (stop > 0 and line[stop - 1] == ' ') stop -= 1;
    return line[0..stop];
}

test "the generated opcode tables are complete" {
    try testing.expectEqual(256, tables.opcodeNames.len);
    try testing.expectEqual(256, tables.opcodeNamesSp.len);
    try testing.expectEqual(256, tables.opcodeType.len);
    try testing.expectEqual(256, tables.opcodeNamesSpc.len);
    try testing.expectEqual(256, tables.opcodeTypeSpc.len);

    try testing.expectEqualStrings("brk          ", std.mem.span(tables.opcodeNames[0x00]));
    try testing.expectEqualStrings("nop          ", std.mem.span(tables.opcodeNames[0xea]));
    try testing.expectEqualStrings("nop              ", std.mem.span(tables.opcodeNamesSpc[0x00]));
    // The "sp" table only carries the 8-bit immediate forms.
    try testing.expect(tables.opcodeNamesSp[0x00] == null);
    try testing.expectEqualStrings("ora #$%02x     ", std.mem.span(tables.opcodeNamesSp[0x09].?));
    // Every type code is one the switch handles.
    for (tables.opcodeType) |t| try testing.expect(t <= 8);
    for (tables.opcodeTypeSpc) |t| try testing.expect(t <= 6);
}

test "an operand-less opcode disassembles to just its name" {
    const apu = try testing.allocator.create(Apu);
    defer testing.allocator.destroy(apu);
    apu.* = std.mem.zeroes(Apu);
    const spc = try testing.allocator.create(Spc);
    defer testing.allocator.destroy(spc);
    spc.* = std.mem.zeroes(Spc);
    apu.spc = @ptrCast(spc);
    spc.apu = apu;

    apu.ram[0x200] = 0x00; // nop
    spc.pc = 0x200;
    var line: [32]u8 = @splat(0);
    getDisassemblySpc(apu, &line);
    try testing.expectEqualStrings("nop", trimmed(&line));
}

test "spc operands are formatted into the opcode template" {
    const apu = try testing.allocator.create(Apu);
    defer testing.allocator.destroy(apu);
    apu.* = std.mem.zeroes(Apu);
    const spc = try testing.allocator.create(Spc);
    defer testing.allocator.destroy(spc);
    spc.* = std.mem.zeroes(Spc);
    apu.spc = @ptrCast(spc);
    spc.apu = apu;

    // mov a, #$42 is opcode 0xe8 with one immediate byte (type 1).
    apu.ram[0x300] = 0xe8;
    apu.ram[0x301] = 0x42;
    spc.pc = 0x300;
    var line: [32]u8 = @splat(0);
    getDisassemblySpc(apu, &line);
    try testing.expectEqualStrings("mov a, #$42", trimmed(&line));

    // A 16-bit absolute operand (type 2): mov a, $1234 is 0xe5.
    apu.ram[0x300] = 0xe5;
    apu.ram[0x301] = 0x34;
    apu.ram[0x302] = 0x12;
    line = @splat(0);
    getDisassemblySpc(apu, &line);
    try testing.expectEqualStrings("mov a, $1234", trimmed(&line));
}

test "a relative branch prints its resolved target" {
    const apu = try testing.allocator.create(Apu);
    defer testing.allocator.destroy(apu);
    apu.* = std.mem.zeroes(Apu);
    const spc = try testing.allocator.create(Spc);
    defer testing.allocator.destroy(spc);
    spc.* = std.mem.zeroes(Spc);
    apu.spc = @ptrCast(spc);
    spc.apu = apu;

    // bra $xx is opcode 0x2f, type 3: target is pc + 2 + signed offset.
    apu.ram[0x400] = 0x2f;
    apu.ram[0x401] = 0x10;
    spc.pc = 0x400;
    var line: [32]u8 = @splat(0);
    getDisassemblySpc(apu, &line);
    try testing.expectEqualStrings("bra $0412", trimmed(&line));

    // A backwards branch sign extends.
    apu.ram[0x401] = 0xfc;
    line = @splat(0);
    getDisassemblySpc(apu, &line);
    try testing.expectEqualStrings("bra $03fe", trimmed(&line));
}

test "the spc state line lays out registers and flags" {
    const apu = try testing.allocator.create(Apu);
    defer testing.allocator.destroy(apu);
    apu.* = std.mem.zeroes(Apu);
    const spc = try testing.allocator.create(Spc);
    defer testing.allocator.destroy(spc);
    spc.* = std.mem.zeroes(Spc);
    apu.spc = @ptrCast(spc);
    spc.apu = apu;

    spc.pc = 0x1234;
    spc.a = 0xab;
    spc.x = 0xcd;
    spc.y = 0xef;
    spc.sp = 0x10;
    spc.n = true;
    spc.c = true;
    apu.ram[0x1234] = 0x00; // nop

    var line: [80]u8 = @splat(0);
    getProcessorStateSpc(apu, &line);
    const text = trimmed(&line);
    try testing.expect(std.mem.startsWith(u8, text, "SPC 1234 nop"));
    try testing.expect(std.mem.indexOf(u8, text, "A:ab X:cd Y:ef SP:10") != null);
    // n and c set, the rest clear.
    try testing.expect(std.mem.endsWith(u8, text, "NvpbhizC"));
}

test "the cpu state line reads its opcode through the bus" {
    const snes = try testing.allocator.create(Snes);
    defer testing.allocator.destroy(snes);
    snes.* = std.mem.zeroes(Snes);
    const cpu = try testing.allocator.create(Cpu);
    defer testing.allocator.destroy(cpu);
    cpu.* = std.mem.zeroes(Cpu);
    const ram = try testing.allocator.create([0x20000]u8);
    defer testing.allocator.destroy(ram);
    @memset(ram, 0);

    snes.cpu = cpu;
    snes.ram = ram;
    // Bank 0 below $2000 is work ram, so no cart is needed.
    ram[0x100] = 0xea; // nop
    cpu.pc = 0x100;
    cpu.k = 0;
    cpu.a = 0x1234;
    cpu.e = true;

    var line: [80]u8 = @splat(0);
    getProcessorStateCpu(snes, &line);
    const text = trimmed(&line);
    try testing.expect(std.mem.startsWith(u8, text, "CPU 00:0100 nop"));
    try testing.expect(std.mem.indexOf(u8, text, "A:1234") != null);
    try testing.expect(std.mem.indexOf(u8, text, " E ") != null);
}
