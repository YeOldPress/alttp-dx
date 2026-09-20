//! Port of src/zelda_cpu_infra.c.
//!
//! This file handles running zelda through the emulated cpu.
//! It defines the runtime environment for the emulated side-by-side state.
//! It should be possible to build and run the game without this file.
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl_types.zig");
const snes_pkg = @import("snes");
const snes_mod = snes_pkg.snes;
const snes_other = snes_pkg.snes_other;
const snes_types = snes_pkg.snes_types;
const cpu_mod = snes_pkg.cpu;
const cpu_types = snes_pkg.cpu_types;
const ppu_types = snes_pkg.ppu_types;
const cart_mod = snes_pkg.cart;
const dma_mod = snes_pkg.dma;
const input_mod = snes_pkg.input;
const tracing = snes_pkg.tracing;

const Snes = snes_types.Snes;
const Cpu = cpu_types.Cpu;
const Ppu = ppu_types.Ppu;
const Cart = cart_mod.Cart;
const Dma = dma_mod.Dma;
const Input = input_mod.Input;

const g_ram = &vars.g_ram;
const g_zenv = &rtl.g_zenv;

// snes/snes_regs.h
const DMAP0 = 0x4300;
const BBAD0 = 0x4301;

extern fn malloc(size: usize) ?*anyopaque;
extern fn puts(s: [*:0]const u8) c_int;

// Still in C: zelda_rtl.c
const ZeldaRunFrameFunc = fn (input: u16, run_what: c_int) callconv(.c) void;
const ZeldaSyncAllFunc = fn () callconv(.c) void;
extern fn ZeldaRunFrameInternal(input: u16, run_what: c_int) void;
extern fn ZeldaSetupEmuCallbacks(
    emu_ram: [*]u8,
    func: *const ZeldaRunFrameFunc,
    sync_all: *const ZeldaSyncAllFunc,
) void;

pub export var g_snes: ?*Snes = null;
pub export var g_cpu: ?*Cpu = null;
pub export var g_emulated_ram: [0x20000]u8 = @splat(0);

fn snes() *Snes {
    return g_snes.?;
}

fn cpu() *Cpu {
    return g_cpu.?;
}

fn snesCart() *Cart {
    return @ptrCast(@alignCast(snes().cart.?));
}

fn snesCpu() *Cpu {
    return @ptrCast(@alignCast(snes().cpu.?));
}

fn snesPpu() *Ppu {
    return @ptrCast(@alignCast(snes().ppu.?));
}

fn snesDma() *Dma {
    return @ptrCast(@alignCast(snes().dma.?));
}

fn snesInput1() *Input {
    return @ptrCast(@alignCast(snes().input1.?));
}

fn zenvPpu() *Ppu {
    return @ptrCast(@alignCast(g_zenv.ppu.?));
}

fn zenvDma() *Dma {
    return @ptrCast(@alignCast(g_zenv.dma.?));
}

/// Folds a 24-bit snes address into the LoROM image.
fn romOffset(addr: u32) u32 {
    return ((addr >> 16) << 15) | (addr & 0x7fff);
}

pub export fn GetPtr(addr: u32) callconv(.c) [*]u8 {
    const cart = snesCart();
    return cart.rom.? + (romOffset(addr) & (cart.romSize - 1));
}

pub export fn GetCartRamPtr(addr: u32) callconv(.c) [*]u8 {
    const cart = snesCart();
    return cart.ram.? + addr;
}

pub export fn RomByte(cart: *Cart, addr: u32) callconv(.c) [*]u8 {
    return cart.rom.? + (romOffset(addr) & (cart.romSize - 1));
}

const Snapshot = extern struct {
    a: u16,
    x: u16,
    y: u16,
    sp: u16,
    dp: u16,
    pc: u16,
    k: u8,
    db: u8,
    flags: u8,
    ram: [0x20000]u8,
    vram: [0x8000]u16,
    sram: [0x2000]u16,
};

var g_snapshot_mine: Snapshot = std.mem.zeroes(Snapshot);
var g_snapshot_theirs: Snapshot = std.mem.zeroes(Snapshot);
var g_snapshot_before: Snapshot = std.mem.zeroes(Snapshot);

fn MakeSnapshot(s: *Snapshot) void {
    const c = cpu();
    s.a = c.a;
    s.x = c.x;
    s.y = c.y;
    s.sp = c.sp;
    s.dp = c.dp;
    s.db = c.db;
    s.pc = c.pc;
    s.k = c.k;
    s.flags = cpu_mod.cpu_getFlags(c);
    @memcpy(&s.ram, snes().ram.?[0..0x20000]);
    const cart = snesCart();
    @memcpy(@as([*]u8, @ptrCast(&s.sram))[0..cart.ramSize], cart.ram.?[0..cart.ramSize]);
    @memcpy(&s.vram, &snesPpu().vram);
    // hdma_table (partial)
    std.mem.copyForwards(u8, s.ram[0x1DBA0..][0 .. 224 * 2], s.ram[0x1B00..][0 .. 224 * 2]);
}

fn MakeMySnapshot(s: *Snapshot) void {
    @memcpy(&s.ram, g_zenv.ram.?[0..0x20000]);
    @memcpy(@as([*]u8, @ptrCast(&s.sram))[0..0x2000], g_zenv.sram.?[0..0x2000]);
    @memcpy(&s.vram, &zenvPpu().vram);
    // hdma_table (partial)
    std.mem.copyForwards(u8, s.ram[0x1B00..][0 .. 224 * 2], s.ram[0x1DBA0..][0 .. 224 * 2]);
}

fn RestoreMySnapshot(s: *Snapshot) void {
    @memcpy(g_zenv.ram.?[0..0x20000], &s.ram);
    @memcpy(g_zenv.sram.?[0..0x2000], @as([*]const u8, @ptrCast(&s.sram))[0..0x2000]);
    @memcpy(&zenvPpu().vram, &s.vram);
}

fn RestoreSnapshot(s: *Snapshot) void {
    const c = cpu();
    c.a = s.a;
    c.x = s.x;
    c.y = s.y;
    c.sp = s.sp;
    c.dp = s.dp;
    c.db = s.db;
    c.pc = s.pc;
    c.k = s.k;
    cpu_mod.cpu_setFlags(c, s.flags);
    @memcpy(snes().ram.?[0..0x20000], &s.ram);
    const cart = snesCart();
    @memcpy(cart.ram.?[0..cart.ramSize], @as([*]const u8, @ptrCast(&s.sram))[0..cart.ramSize]);
    @memcpy(&snesPpu().vram, &s.vram);
}

var g_fail: bool = false;

/// b is mine, a is theirs
fn VerifySnapshotsEq(b: *Snapshot, a: *Snapshot, prev: *Snapshot) void {
    @memcpy(b.ram[0..16], a.ram[0..16]);
    b.ram[0xfa1] = a.ram[0xfa1];
    b.ram[0x72] = a.ram[0x72];
    b.ram[0x73] = a.ram[0x73];
    b.ram[0x74] = a.ram[0x74];
    b.ram[0x75] = a.ram[0x75];
    b.ram[0xb7] = a.ram[0xb7];
    b.ram[0xb8] = a.ram[0xb8];
    b.ram[0xb9] = a.ram[0xb9];
    b.ram[0xba] = a.ram[0xba];
    b.ram[0xbb] = a.ram[0xbb];
    b.ram[0xbd] = a.ram[0xbd];
    b.ram[0xbe] = a.ram[0xbe];
    b.ram[0xc8] = a.ram[0xc8];
    b.ram[0xc9] = a.ram[0xc9];
    b.ram[0xca] = a.ram[0xca];
    b.ram[0xcb] = a.ram[0xcb];
    b.ram[0xcc] = a.ram[0xcc];
    b.ram[0xcd] = a.ram[0xcd];
    b.ram[0xa0] = a.ram[0xa0];
    b.ram[0x128] = a.ram[0x128]; // irq_flag
    b.ram[0x463] = a.ram[0x463]; // which_staircase_index_padding

    // c code is authoritative
    @memcpy(a.ram[0x1f0a..][0..2], b.ram[0x1f0a..][0..2]);

    @memcpy(b.ram[0x1f0d..][0 .. 0x3f - 0xd], a.ram[0x1f0d..][0 .. 0x3f - 0xd]);
    @memcpy(b.ram[0x138..][0 .. 256 - 0x38], a.ram[0x138..][0 .. 256 - 0x38]); // copy the stack over

    @memcpy(a.ram[0x1cc0..][0..2], b.ram[0x1cc0..][0..2]); // some leftover stuff in hdma table
    @memcpy(a.ram[0x1dd60..][0 .. 16 * 2], b.ram[0x1dd60..][0 .. 16 * 2]); // some leftover stuff in hdma table

    @memcpy(a.ram[0x1db20..][0 .. 64 * 2], b.ram[0x1db20..][0 .. 64 * 2]); // msu
    a.ram[0x654] = b.ram[0x654]; // msu_volume

    @memcpy(a.ram[0x1CDD..][0..2], b.ram[0x1CDD..][0..2]); // dialogue_msg_src_offs

    if (!std.mem.eql(u8, &b.ram, &a.ram)) {
        std.debug.print("@{d}: Memory compare failed (mine != theirs, prev):\n", .{vars.frame_counter.*});
        var j: c_int = 0;
        var i: usize = 0;
        while (i < 0x20000) : (i += 1) {
            if (a.ram[i] != b.ram[i]) {
                j += 1;
                if (j < 128) {
                    if ((i & 1) == 0 and a.ram[i + 1] != b.ram[i + 1]) {
                        std.debug.print("0x{X:0>6}: {X:0>4} != {X:0>4} ({X:0>4})\n", .{
                            i, word(&b.ram, i), word(&a.ram, i), word(&prev.ram, i),
                        });
                        i += 1;
                        j += 1;
                    } else {
                        std.debug.print("0x{X:0>6}: {X:0>2} != {X:0>2} ({X:0>2})\n", .{
                            i, b.ram[i], a.ram[i], prev.ram[i],
                        });
                    }
                }
            }
        }
        if (j != 0)
            g_fail = true;
        std.debug.print("  total of {d} failed bytes\n", .{j});
    }

    // The C compares 0x2000 bytes but then indexes the arrays as uint16, so the
    // reporting loop walks twice as far as the comparison did.
    const b_sram_bytes: [*]const u8 = @ptrCast(&b.sram);
    const a_sram_bytes: [*]const u8 = @ptrCast(&a.sram);
    if (!std.mem.eql(u8, b_sram_bytes[0..0x2000], a_sram_bytes[0..0x2000])) {
        std.debug.print("@{d}: SRAM compare failed (mine != theirs, prev):\n", .{vars.frame_counter.*});
        var j: c_int = 0;
        var i: usize = 0;
        while (i < 0x2000) : (i += 1) {
            if (a.sram[i] != b.sram[i]) {
                j += 1;
                if (j < 128) {
                    if ((i & 1) == 0 and a.sram[i + 1] != b.sram[i + 1]) {
                        std.debug.print("0x{X:0>6}: {X:0>4} != {X:0>4} ({X:0>4})\n", .{
                            i, b.sram[i], a.sram[i], prev.sram[i],
                        });
                        i += 1;
                        j += 1;
                    } else {
                        std.debug.print("0x{X:0>6}: {X:0>2} != {X:0>2} ({X:0>2})\n", .{
                            i, b.sram[i], a.sram[i], prev.sram[i],
                        });
                    }
                }
            }
        }
        if (j != 0)
            g_fail = true;
        std.debug.print("  total of {d} failed bytes\n", .{j});
    }

    if (!std.mem.eql(u16, &b.vram, &a.vram)) {
        std.debug.print("@{d}: VRAM compare failed (mine != theirs, prev):\n", .{vars.frame_counter.*});
        var j: usize = 0;
        for (0..0x8000) |i| {
            if (a.vram[i] != b.vram[i]) {
                std.debug.print("0x{X:0>6}: {X:0>4} != {X:0>4} ({X:0>4})\n", .{
                    i, b.vram[i], a.vram[i], prev.vram[i],
                });
                g_fail = true;
                j += 1;
                if (j >= 16)
                    break;
            }
        }
    }
}

fn word(ram: []const u8, i: usize) u16 {
    return std.mem.readInt(u16, ram[i..][0..2], .little);
}

pub export var g_calling_asm_from_c: bool = false;

pub export fn HookedFunctionRts(is_long: c_int) callconv(.c) void {
    _ = is_long;
    if (g_calling_asm_from_c) {
        g_calling_asm_from_c = false;
        return;
    }
    unreachable; // assert(0)
}

pub export fn RunEmulatedFunc(
    pc: u32,
    a: u16,
    x: u16,
    y: u16,
    mf: bool,
    xf: bool,
    b: c_int,
    whatflags: c_int,
) callconv(.c) void {
    snes().debug_cycles = true;
    RunEmulatedFuncSilent(pc, a, x, y, mf, xf, b, whatflags | 2);
    snes().debug_cycles = false;
}

var rambak: ?[*]u8 = null;

pub export fn RunEmulatedFuncSilent(
    pc: u32,
    a: u16,
    x: u16,
    y: u16,
    mf: bool,
    xf: bool,
    b: c_int,
    whatflags: c_int,
) callconv(.c) void {
    const c = cpu();
    const org_sp = c.sp;
    const org_pc = c.pc;
    const org_b = c.db;
    const org_dp = c.dp;
    if (b != -1)
        c.db = if (b >= 0) @truncate(@as(c_uint, @bitCast(b))) else @truncate(pc >> 16);
    if (b == -3)
        c.dp = 0x1f00;

    if (rambak == null)
        rambak = @ptrCast(malloc(0x20000));
    @memcpy(rambak.?[0..0x20000], g_emulated_ram[0..0x20000]);
    @memcpy(g_emulated_ram[0..0x20000], g_ram[0..0x20000]);

    if (whatflags & 2 != 0)
        g_emulated_ram[0x1ffff] = 0x67;

    c.a = a;
    c.x = x;
    c.y = y;
    c.spBreakpoint = c.sp;
    c.k = @truncate(pc >> 16);
    c.pc = @truncate(pc & 0xffff);
    c.mf = mf;
    c.xf = xf;
    g_calling_asm_from_c = true;
    while (g_calling_asm_from_c) {
        if (snes().debug_cycles) {
            var line: [80]u8 = undefined;
            tracing.getProcessorStateCpu(snes(), &line);
            _ = puts(@ptrCast(&line));
        }
        _ = cpu_mod.cpu_runOpcode(c);
        while (snesDma().dmaBusy)
            dma_mod.dma_doDma(snesDma());

        // The C's `whatflags & 1` branch is entirely commented out upstream.
    }
    c.dp = org_dp;
    c.sp = org_sp;
    c.db = org_b;
    c.pc = org_pc;

    @memcpy(g_ram[0..0x20000], g_emulated_ram[0..0x20000]);
    @memcpy(g_emulated_ram[0..0x20000], rambak.?[0..0x20000]);
}

pub export fn RunOrigAsmCodeOneLoop(s: *Snes) callconv(.c) void {
    const c: *Cpu = @ptrCast(@alignCast(s.cpu.?));
    c.a = 0;
    c.x = 0;
    c.y = 0;
    c.e = false;
    c.irqWanted = false;
    c.nmiWanted = false;
    c.waiting = false;
    c.stopped = false;
    cpu_mod.cpu_setFlags(c, 0x30);

    // Run until the wait loop in Interrupt_Reset,
    // Or the polyhedral main function.
    var loops: c_int = 0;
    while (true) : (loops += 1) {
        snes_mod.snes_printCpuLine(s);
        _ = cpu_mod.cpu_runOpcode(c);
        const dma: *Dma = @ptrCast(@alignCast(s.dma.?));
        while (dma.dmaBusy)
            dma_mod.dma_doDma(dma);

        const pc = @as(u32, c.k) << 16 | c.pc;
        // && binds tighter than ||, so only the poly entry is loop-gated.
        if (pc == 0x8034 or (pc == 0x9f81d and loops >= 10) or pc == 0x8225 or pc == 0x82D2)
            break;
    }
}

fn RunEmulatedSnesFrame(s: *Snes, run_what: c_int) void {
    const c: *Cpu = @ptrCast(@alignCast(s.cpu.?));

    // First call runs until init
    if (c.pc == 0x8000 and c.k == 0) {
        RunOrigAsmCodeOneLoop(s);
        g_emulated_ram[0x12] = 1;
        // Fixup uninitialized variable
        std.mem.writeInt(u16, g_emulated_ram[0xAE0..][0..2], 0xb280, .little);
        std.mem.writeInt(u16, g_emulated_ram[0xAE2..][0..2], 0xb280 + 0x60, .little);
    }

    // Run poly code
    if (run_what & 2 != 0) {
        c.sp = 0x1f3e;
        c.pc = 0xf81d;
        c.db = 9;
        c.k = 9;
        c.dp = 0x1f00;
        RunOrigAsmCodeOneLoop(s);
    }

    // Run main code
    if (run_what & 1 != 0) {
        const mc = snesCpu();
        mc.sp = 0x1ff;
        mc.pc = 0x8034;
        mc.k = 0;
        mc.dp = 0;
        mc.db = 0;
        RunOrigAsmCodeOneLoop(s);
    }

    snes_mod.snes_doAutoJoypad(s);

    // animated_tile_vram_addr uninited
    if (s.ram.?[0xadd] == 0)
        std.mem.writeInt(u16, s.ram.?[0xadc..][0..2], 0xa680, .little);

    // In one code path flag_update_hud_in_nmi uses an undefined value
    snes_mod.snes_write(s, DMAP0, 0x01);
    snes_mod.snes_write(s, BBAD0, 0x18);

    // Run NMI handler
    const nc = snesCpu();
    nc.sp = 0x1ff;
    nc.pc = 0x80D9;
    nc.k = 0;
    nc.dp = 0;
    nc.db = 0;
    RunOrigAsmCodeOneLoop(s);
}

/// Copy state into the emulator, we can skip dsp/apu because
/// we're not emulating that.
fn EmuSynchronizeWholeState() callconv(.c) void {
    snesPpu().* = zenvPpu().*;
    @memcpy(snes().ram.?[0..0x20000], g_zenv.ram.?[0..0x20000]);
    @memcpy(snesCart().ram.?[0..0x2000], g_zenv.sram.?[0..0x2000]);

    const n = @sizeOf(Dma) - @offsetOf(Dma, "channel");
    const dst: [*]u8 = @ptrCast(&snesDma().channel);
    const src: [*]const u8 = @ptrCast(&zenvDma().channel);
    @memcpy(dst[0..n], src[0..n]);

    // todo: this is hacky
    if (vars.animated_tile_data_src.* == 0)
        cpu_mod.cpu_reset(snesCpu());
}

pub export fn EmuRunFrameWithCompare(input_state: u16, run_what: c_int) callconv(.c) void {
    MakeSnapshot(&g_snapshot_before);
    MakeMySnapshot(&g_snapshot_mine);
    MakeSnapshot(&g_snapshot_theirs);

    // Compare both snapshots before we run the frame, to see they match
    VerifySnapshotsEq(&g_snapshot_mine, &g_snapshot_theirs, &g_snapshot_before);
    if (g_fail) {
        _ = puts("early fail"); // puts supplies the newline the C printf spelled out
        unreachable; // assert(0)
    }

    // The C loops back to `again_theirs` on mismatch. Its `goto again_mine` is
    // guarded by `if (0)` and the block after the goto is unreachable, so this
    // is the whole of the retry behaviour.
    while (true) {
        // Run orig version then snapshot
        snesInput1().currentState = input_state;
        RunEmulatedSnesFrame(snes(), run_what);
        MakeSnapshot(&g_snapshot_theirs);

        // Run my version and snapshot
        ZeldaRunFrameInternal(input_state, run_what);
        MakeMySnapshot(&g_snapshot_mine);

        // Compare both snapshots
        VerifySnapshotsEq(&g_snapshot_mine, &g_snapshot_theirs, &g_snapshot_before);
        if (!g_fail)
            break;

        g_fail = false;
        RestoreMySnapshot(&g_snapshot_before);
        RestoreSnapshot(&g_snapshot_before);
    }
}

fn PatchRomBP(rom: [*]u8, addr: u32) void {
    rom[romOffset(addr)] = 0;
}

fn PatchRomByte(rom: [*]u8, addr: u32, old_value: u8, value: u8) void {
    std.debug.assert(rom[romOffset(addr)] == old_value);
    rom[romOffset(addr)] = value;
}

fn PatchRomWord(rom: [*]u8, addr: u32, old_value: u16, value: u16) void {
    const p = rom + romOffset(addr);
    std.debug.assert(std.mem.readInt(u16, p[0..2], .little) == old_value);
    std.mem.writeInt(u16, p[0..2], value, .little);
}

fn PatchRomArray(rom: [*]u8, addr_in: u32, values: []const u8) void {
    var addr = addr_in;
    for (values) |v| {
        rom[romOffset(addr)] = v;
        addr += 1;
    }
}

const kFixSoItWontDecodeSheetLessThan12 = [9]u8{ 0xc0, 0x0c, 0xb0, 0x02, 0xa0, 0x0c, 0x4c, 0x72, 0xe7 };

const kDoorDebrisX_Uses = [7]u32{ 0x1CFC6, 0x1d29d, 0x89794, 0x897a3, 0x8a0a1, 0x8edca, 0x99aa6 };
const kDoorDebrisX1_Uses = [2]u32{ 0x89797, 0x897A6 };
const kDoorDebrisY_Uses = [5]u32{ 0x1CFD7, 0x1D2AE, 0x8A099, 0x8EDC5, 0x99AA1 };
const kDoorDebrisDir_Uses = [3]u32{ 0x1CFB2, 0x1D2BA, 0x8A0B7 };
const ancilla_arr26_Uses = [4]u32{ 0x89fb9, 0x89fc0, 0x98157, 0x99c49 };
const ancilla_arr25_Uses = [17]u32{
    0x89fc3, 0x89fc6, 0x8a0ae, 0x8ab7c, 0x8aba7, 0x8abb6, 0x8ae92, 0x8bae2, 0x8baff,
    0x8f429, 0x98148, 0x98e0a, 0x98ebc, 0x9920a, 0x9931e, 0x9987f, 0x99c44,
};
const ancilla_arr22_Uses = [3]u32{ 0x9816e, 0xffde0, 0xffde7 };

fn PatchRom(rom: [*]u8) void {
    //  fix a bug with unitialized memory
    {
        const p = rom + 0x36434;
        std.mem.copyForwards(u8, p[0..7], (p + 2)[0..7]);
        p[7] = 0xb0;
        p[8] = 0x40 - 7;
    }

    // BufferAndBuildMap16Stripes_Y can read bad memory if int is negative
    {
        const p = rom + 0x10000 - 0x8000;
        const thunk: u32 = 0xFF6E;
        var tp = p + thunk;

        tp[0] = 0xc0;
        tp[1] = 0x00;
        tp[2] = 0x20;
        tp[3] = 0x90;
        tp[4] = 0x03;
        tp[5] = 0xa9;
        tp[6] = 0x00;
        tp[7] = 0x00;
        tp[8] = 0x9d;
        tp[9] = 0x00;
        tp[10] = 0x05;
        tp[11] = 0x60;

        p[0xf4a7] = 0x20;
        p[0xf4a8] = @truncate(thunk);
        p[0xf4a9] = @truncate(thunk >> 8);
        p[0xf4b5] = 0x20;
        p[0xf4b6] = @truncate(thunk);
        p[0xf4b7] = @truncate(thunk >> 8);

        p[0xf3dd] = 0x20;
        p[0xf3de] = @truncate(thunk);
        p[0xf3df] = @truncate(thunk >> 8);
        p[0xf3ef] = 0x20;
        p[0xf3f0] = @truncate(thunk);
        p[0xf3f1] = @truncate(thunk >> 8);
    }

    // Better random numbers
    {
        // 8D:FFC1                      new_random_gen:
        const new_routine: u32 = 0xffc1;
        const p = rom + 0x60000;
        const tp = p + new_routine;

        tp[0] = 0xad; // mov.b   A, byte_7E0FA1
        tp[1] = 0xa1;
        tp[2] = 0x0f;
        tp[3] = 0x18; // add.b   A, frame_counter
        tp[4] = 0x65;
        tp[5] = 0x1a;
        tp[6] = 0x4a; // lsr     A
        tp[7] = 0xb0; // jnb     loc_8DFFCC
        tp[8] = 0x02;
        tp[9] = 0x49; // eor.b   A, #0xB8
        tp[10] = 0xb8;
        tp[11] = 0x8d; // byte_7E0FA1, A
        tp[12] = 0xa1;
        tp[13] = 0x0f;
        tp[14] = 0x18; // clc
        tp[15] = 0x6b; // retf

        p[0xBA71] = 0x4c;
        p[0xBA72] = @truncate(new_routine);
        p[0xBA73] = @truncate(new_routine >> 8);
    }

    // Fix so SmashRockPile_fromLift / Overworld_DoMapUpdate32x32_B preserves R2/R0 destroyed
    {
        const tp = rom + 0x6ffd8;
        tp[0] = 0xa5;
        tp[1] = 0x00;
        tp[2] = 0x48;
        tp[3] = 0xa5;
        tp[4] = 0x02;
        tp[5] = 0x48;
        tp[6] = 0x22;
        tp[7] = 0x5c;
        tp[8] = 0xad;
        tp[9] = 0x02;
        tp[10] = 0xc2;
        tp[11] = 0x30;
        tp[12] = 0x68;
        tp[13] = 0x85;
        tp[14] = 0x02;
        tp[15] = 0x68;
        tp[16] = 0x85;
        tp[17] = 0x00;
        tp[18] = 0x6b;

        const target: u32 = 0xDFFD8; // DoorAnim_DoWork2_Preserving

        rom[0xdc0f2] = @truncate(target);
        rom[0xdc0f3] = @truncate(target >> 8);
        rom[0xdc0f4] = @truncate(target >> 16);
    }

    rom[0x2dec7] = 0; // Fix Uncle_Embark reading bad ram

    rom[0x4be5e] = 0; // Overlord05_FallingStalfos doesn't initialize the sprite_D memory location

    rom[0xD79A4] = 0; // 0x1AF9A4: // Lanmola_SpawnShrapnel uses undefined carry value

    rom[0xF0A46] = 0; // 0x1E8A46 Helmasaur Carry Junk
    rom[0xF0A52] = 0; // 0x1E8A52 Helmasaur Carry Junk

    rom[0xef9b9] = 0xb9; // TalkingTree_SpitBomb

    rom[0xdf107] = 0xa2;
    rom[0xdf108] = 0x03;
    rom[0xdf109] = 0x6b; // Palette_AgahnimClone destoys X

    rom[0x4a966] = 0; // Follower_AnimateMovement_preserved

    PatchRomBP(rom, 0x1de0e5);
    PatchRomBP(rom, 0x6d0b6);
    PatchRomBP(rom, 0x6d0c6);

    PatchRomBP(rom, 0x1d8f29); // adc instead of add
    PatchRomBP(rom, 0x1DDBD3); // adc instead of add
    PatchRomBP(rom, 0x1DF856); // adc instead of add
    PatchRomBP(rom, 0x1E88DA); // adc instead of add

    PatchRomBP(rom, 0x06ED0B);

    PatchRomBP(rom, 0x1dc812); // adc instead of add

    PatchRomBP(rom, 0x9b46c); // adc instead of add
    PatchRomBP(rom, 0x9b478); // adc instead of add

    PatchRomBP(rom, 0x9B468); // sbc
    PatchRomBP(rom, 0x9B46A);
    PatchRomBP(rom, 0x9B474);
    PatchRomBP(rom, 0x9B476);
    PatchRomBP(rom, 0x9B60C);

    PatchRomBP(rom, 0x8f708); // don't init scratch_c

    PatchRomBP(rom, 0x1DCDEB); // y is destroyed earlier, restore it..

    PatchRomBP(rom, 0x7B269); // Link_APress_LiftCarryThrow oob

    // Smithy_Frog doesn't save X
    std.mem.copyBackwards(u8, (rom + 0x332b8)[0..4], (rom + 0x332b7)[0..4]);
    rom[0x332b7] = 0xfa;

    // This needs to be here because the ancilla code reads
    // from the apu and we don't want to make the core code
    // dependent on the apu timings, so relocated this value
    // to 0x648.
    rom[0x443fe] = 0x48;
    rom[0x443ff] = 0x6;
    rom[0x44607] = 0x48;
    rom[0x44608] = 0x6;

    // AncillaAdd_AddAncilla_Bank09 destroys R14
    rom[0x49d0c] = 0xda;
    rom[0x49d0d] = 0xfa;
    rom[0x49d0f] = 0xda;
    rom[0x49d10] = 0xfa;

    // Prevent LoadSongBank from executing in the rom because it hangs
    rom[0x888] = 0x60;

    // CleanUpAndPrepDesertPrayerHDMA clearing too much
    PatchRomWord(rom, 0x2C7E5 + 1, 0x1df, 0x1cf);

    // Merge ancilla_arr23 with boomerang_arr1 because they're only 3 bytes long,
    // and boomerang might get allocated in slot 4.
    PatchRomByte(rom, 0x9816C, 0xd2, 0xCF);
    PatchRomByte(rom, 0xffdeb, 0xd2, 0xCF);
    PatchRomByte(rom, 0xffdee, 0xd2, 0xCF);
    PatchRomByte(rom, 0xffdf7, 0xd2, 0xCF);
    PatchRomByte(rom, 0xffdfa, 0xd2, 0xCF);

    // Relocate the door debris variables so they become 5 entries each (they were 2 before).
    for (kDoorDebrisX_Uses) |u| PatchRomWord(rom, u + 1, 0x3b6, 0x728);
    for (kDoorDebrisX1_Uses) |u| PatchRomWord(rom, u + 1, 0x3b7, 0x729);
    for (kDoorDebrisY_Uses) |u| PatchRomWord(rom, u + 1, 0x3ba, 0x732);
    for (kDoorDebrisDir_Uses) |u| PatchRomWord(rom, u + 1, 0x3be, 0x73c);
    for (ancilla_arr26_Uses) |u| PatchRomWord(rom, u + 1, 0x3c0, 0x741);
    for (ancilla_arr25_Uses) |u| PatchRomWord(rom, u + 1, 0x3c2, 0x746);
    for (ancilla_arr22_Uses) |u| PatchRomWord(rom, u + 1, 0x3e1, 0x74b);

    PatchRomWord(rom, 0xddfac + 1, 0xfa85, 0xfa70); // call Hud_Rebuild instead of Hud_UpdateOnly

    // Make sure it's not calling Decomp_spr on tilesheets less than 12
    PatchRomWord(rom, 0xe589, 0xe772, 0xe852); // call New addr
    PatchRomArray(rom, 0xe852, &kFixSoItWontDecodeSheetLessThan12);
}

pub export fn EmuInitialize(data: [*]u8, size: usize) callconv(.c) bool {
    PatchRom(data);
    const s = snes_mod.snes_init(&g_emulated_ram);
    g_snes = s;
    g_cpu = @ptrCast(@alignCast(s.cpu.?));

    ZeldaSetupEmuCallbacks(&g_emulated_ram, &EmuRunFrameWithCompare, &EmuSynchronizeWholeState);
    return snes_other.snes_loadRom(s, data, @intCast(size));
}

const testing = std.testing;

test "snes addresses fold into the LoROM image" {
    // The bank selects a 32k page and the low 15 bits index into it.
    try testing.expectEqual(0, romOffset(0x008000));
    try testing.expectEqual(0x8000, romOffset(0x018000));
    try testing.expectEqual(0x7fff, romOffset(0x00ffff));
    // Bit 15 of the address is discarded, so $008000 and $000000 collide.
    try testing.expectEqual(romOffset(0x000000), romOffset(0x008000));
    // A few of the real patch sites.
    try testing.expectEqual(0x6ffd8, romOffset(0xDFFD8));
}

test "a breakpoint patch zeroes exactly one byte" {
    var rom = [_]u8{0xff} ** 0x100;
    PatchRomBP(&rom, 0x000010);
    try testing.expectEqual(@as(u8, 0), rom[0x10]);
    try testing.expectEqual(@as(u8, 0xff), rom[0x0f]);
    try testing.expectEqual(@as(u8, 0xff), rom[0x11]);
}

test "byte and word patches check the value they replace" {
    var rom = [_]u8{0} ** 0x100;
    rom[0x20] = 0xd2;
    PatchRomByte(&rom, 0x000020, 0xd2, 0xcf);
    try testing.expectEqual(@as(u8, 0xcf), rom[0x20]);

    std.mem.writeInt(u16, rom[0x30..][0..2], 0x01df, .little);
    PatchRomWord(&rom, 0x000030, 0x01df, 0x01cf);
    try testing.expectEqual(@as(u16, 0x01cf), std.mem.readInt(u16, rom[0x30..][0..2], .little));
    // Words go in little endian, so the low byte lands first.
    try testing.expectEqual(@as(u8, 0xcf), rom[0x30]);
    try testing.expectEqual(@as(u8, 0x01), rom[0x31]);
}

test "an array patch writes consecutive bytes" {
    var rom = [_]u8{0} ** 0x100;
    PatchRomArray(&rom, 0x000040, &kFixSoItWontDecodeSheetLessThan12);
    try testing.expectEqualSlices(u8, &kFixSoItWontDecodeSheetLessThan12, rom[0x40..0x49]);
    try testing.expectEqual(@as(u8, 0), rom[0x49]);
}

test "the relocation tables came over at the right sizes" {
    try testing.expectEqual(7, kDoorDebrisX_Uses.len);
    try testing.expectEqual(2, kDoorDebrisX1_Uses.len);
    try testing.expectEqual(5, kDoorDebrisY_Uses.len);
    try testing.expectEqual(3, kDoorDebrisDir_Uses.len);
    try testing.expectEqual(4, ancilla_arr26_Uses.len);
    try testing.expectEqual(17, ancilla_arr25_Uses.len);
    try testing.expectEqual(3, ancilla_arr22_Uses.len);
    try testing.expectEqual(9, kFixSoItWontDecodeSheetLessThan12.len);
}

test "the snapshot holds a full copy of each memory the comparison covers" {
    // 128k of work ram, 64k of vram and 16k for the sram array.
    try testing.expectEqual(0x20000, @sizeOf(@FieldType(Snapshot, "ram")));
    try testing.expectEqual(0x8000 * 2, @sizeOf(@FieldType(Snapshot, "vram")));
    // The C declares sram as uint16[0x2000] but only ever copies 0x2000 bytes
    // into it, which is why the reporting loop can walk past the live data.
    try testing.expectEqual(0x2000 * 2, @sizeOf(@FieldType(Snapshot, "sram")));
}

test "the hooked rts only returns while a c-initiated call is in flight" {
    g_calling_asm_from_c = true;
    HookedFunctionRts(0);
    try testing.expectEqual(false, g_calling_asm_from_c);
}
