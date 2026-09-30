//! Port of src/zelda_rtl.c.
//!
//! This file defines various things related to the runtime environment
//! of the code: the work RAM itself, the simplified HDMA engine that drives
//! the PPU per scanline, frame stepping, and the save/replay state recorder.
const std = @import("std");
const vars = @import("variables.zig");
const config = @import("config.zig");
const hud_second_item = @import("hud_second_item.zig");
const rtl = @import("zelda_rtl_types.zig");
const features = @import("features.zig");
const util = @import("util.zig");
const audio = @import("audio.zig");
const main_mod = @import("main.zig");
const poly = @import("poly.zig");
const nmi = @import("nmi.zig");
const snes_pkg = @import("snes");
const ppu_mod = snes_pkg.ppu;
const ppu_types = snes_pkg.ppu_types;
const dma_mod = snes_pkg.dma;
const dsp_mod = snes_pkg.dsp;
const snes_types = snes_pkg.snes_types;

const Ppu = ppu_types.Ppu;
const Dma = dma_mod.Dma;
const DmaChannel = dma_mod.DmaChannel;
const SaveLoadFunc = snes_types.SaveLoadFunc;
const ByteArray = util.ByteArray;
const MemBlk = util.MemBlk;
const SpcPlayer = audio.SpcPlayer;
const ZeldaEnv = rtl.ZeldaEnv;

const kPpuExtraLeftRight = ppu_types.kPpuExtraLeftRight;
const kPpuRenderFlags_4x4Mode7 = ppu_types.kPpuRenderFlags_4x4Mode7;
const kPpuRenderFlags_Height240 = ppu_types.kPpuRenderFlags_Height240;

const kRam_APUI00 = features.kRam_APUI00;
const kRam_CrystalRotateCounter = features.kRam_CrystalRotateCounter;
const kRam_BugsFixed = features.kRam_BugsFixed;
const kRam_Features0 = features.kRam_Features0;
const kBugFix_PolyRenderer = features.kBugFix_PolyRenderer;
const kBugFix_Latest = features.kBugFix_Latest;

// snes/snes_regs.h
const INIDISP = 0x2100;
const BG3HOFS = 0x2111;
const BG3VOFS = 0x2112;
const STAT78 = 0x213f;
const NMITIMEN = 0x4200;
const MDMAEN = 0x420b;
const HDMAEN = 0x420c;
const DMAP6 = 0x4360;
const BBAD6 = 0x4361;
const A1T6L = 0x4362;
const A1T6H = 0x4363;
const A1B6 = 0x4364;
const DAS60 = 0x4367;
const DMAP7 = 0x4370;
const BBAD7 = 0x4371;
const A1T7L = 0x4372;
const A1T7H = 0x4373;
const A1B7 = 0x4374;
const DAS70 = 0x4377;

const kSaveLoad_Save: c_int = 0;
const kSaveLoad_Load: c_int = 1;
const kSaveLoad_Replay: c_int = 2;

// Still in C: misc.c
extern fn Module_MainRouting() void;
extern fn NMI_PrepareSprites() void;
extern fn Sound_LoadIntroSongBank() void;
// Still in C: spc_player.c
extern fn SpcPlayer_Create() *SpcPlayer;
extern fn SpcPlayer_Initialize(p: *SpcPlayer) void;
// Still in C: attract.c
extern const kMapMode_Zooms1: [240]u16;
extern const kMapMode_Zooms2: [240]u16;

const FILE = anyopaque;
extern fn calloc(n: usize, size: usize) ?*anyopaque;
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern fn fclose(f: *FILE) c_int;
extern fn fread(ptr: *anyopaque, size: usize, n: usize, f: *FILE) usize;
extern fn fwrite(ptr: *const anyopaque, size: usize, n: usize, f: *FILE) usize;
extern fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
extern fn sprintf(buf: [*]u8, fmt: [*:0]const u8, ...) c_int;
extern fn printf(fmt: [*:0]const u8, ...) c_int;
extern fn Die(err: [*:0]const u8) noreturn;

pub export var g_zenv: ZeldaEnv = std.mem.zeroes(ZeldaEnv);
pub export var g_ram: [131072]u8 = @splat(0);

pub export var g_wanted_zelda_features: u32 = 0;

const SimpleHdma = struct {
    table: ?[*]const u8,
    indir_ptr: [*]const u8,
    rep_count: u8,
    mode: u8,
    ppu_addr: u8,
    indir_bank: u8,
};

const bAdrOffsets = [8][4]u8{
    .{ 0, 0, 0, 0 },
    .{ 0, 1, 0, 1 },
    .{ 0, 0, 0, 0 },
    .{ 0, 0, 1, 1 },
    .{ 0, 1, 2, 3 },
    .{ 0, 1, 0, 1 },
    .{ 0, 0, 0, 0 },
    .{ 0, 0, 1, 1 },
};
const transferLength = [8]u8{ 1, 2, 2, 4, 4, 4, 2, 4 };

pub export const kUpperBitmasks = [16]u16{
    0x8000, 0x4000, 0x2000, 0x1000, 0x800, 0x400, 0x200, 0x100,
    0x80,   0x40,   0x20,   0x10,   8,     4,     2,     1,
};
pub export const kLitTorchesColorPlus = [4]u8{ 31, 8, 4, 0 };
pub export const kDungeonCrystalPendantBit = [13]u8{ 0, 0, 4, 2, 0, 16, 2, 1, 64, 4, 1, 32, 8 };
pub export const kGetBestActionToPerformOnTile_x = [4]i8{ 7, 7, -3, 16 };
pub export const kGetBestActionToPerformOnTile_y = [4]i8{ 6, 24, 12, 12 };

/// The C spells these with an AT_WORD() macro that splits a word little endian.
fn atWord(comptime x: u16) [2]u8 {
    return .{ @truncate(x), @truncate(x >> 8) };
}

// direct
const kAttractDmaTable0 = [_]u8{0x20} ++ atWord(0x00ff) ++ [_]u8{0x50} ++ atWord(0xe018) ++
    [_]u8{0x50} ++ atWord(0xe018) ++ [_]u8{1} ++ atWord(0x00ff) ++ [_]u8{0};
const kAttractDmaTable1 = [_]u8{0x48} ++ atWord(0x00ff) ++ [_]u8{0x30} ++ atWord(0xd830) ++
    [_]u8{1} ++ atWord(0x00ff) ++ [_]u8{0};
const kHdmaTableForEnding = [_]u8{0x52} ++ atWord(0x600) ++ [_]u8{8} ++ atWord(0xe2) ++
    [_]u8{8} ++ atWord(0x602) ++ [_]u8{5} ++ atWord(0x604) ++ [_]u8{0x10} ++ atWord(0x606) ++
    [_]u8{0x81} ++ atWord(0xe2) ++ [_]u8{0};
const kSpotlightIndirectHdma = [_]u8{0xf8} ++ atWord(0x1b00) ++ [_]u8{0xf8} ++ atWord(0x1bf0) ++ [_]u8{0};
const kMapModeHdma0 = [_]u8{0xf0} ++ atWord(0xdd27) ++ [_]u8{0xf0} ++ atWord(0xde07) ++ [_]u8{0};
const kMapModeHdma1 = [_]u8{0xf0} ++ atWord(0xdee7) ++ [_]u8{0xf0} ++ atWord(0xdfc7) ++ [_]u8{0};
const kAttractIndirectHdmaTab = [_]u8{0xf0} ++ atWord(0x1b00) ++ [_]u8{0xf0} ++ atWord(0x1be0) ++ [_]u8{0};
const kHdmaTableForPrayingScene = [_]u8{0xf8} ++ atWord(0x1b00) ++ [_]u8{0xf8} ++ atWord(0x1bf0) ++ [_]u8{0};

fn zenvPpu() *Ppu {
    return @ptrCast(@alignCast(g_zenv.ppu.?));
}

fn zenvDma() *Dma {
    return @ptrCast(@alignCast(g_zenv.dma.?));
}

fn zenvPlayer() *SpcPlayer {
    return @ptrCast(@alignCast(g_zenv.player.?));
}

/// variables.h keeps this one in sram rather than work ram.
fn srm_var1() *align(1) u16 {
    return @ptrCast(&g_zenv.sram.?[0x1ffe]);
}

pub export fn zelda_ppu_write(adr: u32, val: u8) callconv(.c) void {
    std.debug.assert(adr >= INIDISP and adr <= STAT78);
    ppu_mod.ppu_write(zenvPpu(), @truncate(adr), val);
}

pub export fn zelda_ppu_write_word(adr: u32, val: u16) callconv(.c) void {
    zelda_ppu_write(adr, @truncate(val));
    zelda_ppu_write(adr + 1, @truncate(val >> 8));
}

fn SimpleHdma_GetPtr(p: u32) [*]const u8 {
    return switch (p) {
        0xCFA87 => &kAttractDmaTable0,
        0xCFA94 => &kAttractDmaTable1,
        0xebd53 => &kHdmaTableForEnding,
        0x0F2FB => &kSpotlightIndirectHdma,
        0xabdcf => &kMapModeHdma0, // mode7
        0xabdd6 => &kMapModeHdma1, // mode7
        0xABDDD => &kAttractIndirectHdmaTab, // mode7
        0x2c80c => &kHdmaTableForPrayingScene,

        0x1b00 => @ptrCast(vars.hdma_table_dynamic),
        0x1be0 => @as([*]const u8, @ptrCast(vars.hdma_table_dynamic)) + 0xe0,
        0x1bf0 => @as([*]const u8, @ptrCast(vars.hdma_table_dynamic)) + 0xf0,
        0xadd27 => @ptrCast(&kMapMode_Zooms1),
        0xade07 => @as([*]const u8, @ptrCast(&kMapMode_Zooms1)) + 0xe0,
        0xadee7 => @ptrCast(&kMapMode_Zooms2),
        0xadfc7 => @as([*]const u8, @ptrCast(&kMapMode_Zooms2)) + 0xe0,
        0x600 => g_ram[0x600..].ptr,
        0x602 => g_ram[0x602..].ptr,
        0x604 => g_ram[0x604..].ptr,
        0x606 => g_ram[0x606..].ptr,
        0xe2 => g_ram[0xe2..].ptr,
        else => unreachable, // assert(0)
    };
}

fn SimpleHdma_Init(c: *SimpleHdma, dc: *DmaChannel) void {
    if (!dc.hdmaActive) {
        c.table = null;
        return;
    }
    c.table = SimpleHdma_GetPtr(@as(u32, dc.aAdr) | @as(u32, dc.aBank) << 16);
    c.rep_count = 0;
    c.mode = dc.mode | @as(u8, @intFromBool(dc.indirect)) << 6;
    c.ppu_addr = dc.bAdr;
    c.indir_bank = dc.indBank;
}

fn SimpleHdma_DoLine(c: *SimpleHdma) void {
    if (c.table == null)
        return;
    var do_transfer = false;
    if ((c.rep_count & 0x7f) == 0) {
        c.rep_count = c.table.?[0];
        c.table = c.table.? + 1;
        if (c.rep_count == 0) {
            c.table = null;
            return;
        }
        if (c.mode & 0x40 != 0) {
            c.indir_ptr = SimpleHdma_GetPtr(@as(u32, c.indir_bank) << 16 |
                @as(u32, c.table.?[0]) | @as(u32, c.table.?[1]) * 256);
            c.table = c.table.? + 2;
        }
        do_transfer = true;
    }
    if (do_transfer or c.rep_count & 0x80 != 0) {
        const j_end = transferLength[c.mode & 7];
        var j: usize = 0;
        while (j < j_end) : (j += 1) {
            var v: u8 = undefined;
            if (c.mode & 0x40 != 0) {
                v = c.indir_ptr[0];
                c.indir_ptr += 1;
            } else {
                v = c.table.?[0];
                c.table = c.table.? + 1;
            }
            zelda_ppu_write(0x2100 + @as(u32, c.ppu_addr) + bAdrOffsets[c.mode & 7][j], v);
        }
    }
    c.rep_count -%= 1;
}

fn intMax(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

/// Whether the HUD is on screen, in BG3's tilemap rows 2 to 7: playing in
/// a dungeon or outdoors, and the interface's states that keep the game
/// showing behind them - the item menu (whose slide pushes the HUD down the
/// screen), text, potion refills, the desert prayer, the save menu. The maps
/// draw their own things there, and the title and file screens have no HUD.
pub fn hudOnScreen() bool {
    return switch (vars.main_module_index.*) {
        7, 9, 0x0b, 0x0f, 0x10, 0x11, 0x15 => true,
        0x0e => switch (vars.submodule_index.*) {
            1, 2, 4, 5, 8, 9, 0x0b => true,
            else => false,
        },
        else => false,
    };
}

/// Tells the PPU to spread the HUD out this frame, when that's wanted and
/// there's a widescreen margin to spread it into.
fn ConfigureHudSplit(ppu: *const Ppu) void {
    ppu_mod.g_hud_split = .{};
    defer hud_second_item.configure(ppu, ppu_mod.g_hud_split.shift != 0);
    if (!config.g_widescreen_hud or ppu.extraLeftRight == 0 or !hudOnScreen()) return;
    ppu_mod.g_hud_split = .{ .ppu = ppu, .shift = ppu.extraLeftRight };
    // With a second item on X, its box goes beside the item box, and the
    // counters step aside for it.
    if (hud_second_item.shown()) ppu_mod.g_hud_split.gap = hud_second_item.kBesideGap;
}

fn ConfigurePpuSideSpace() void {
    const s = widescreenSideSpace(kPpuExtraLeftRight);
    ppu_mod.PpuSetExtraSideSpace(zenvPpu(), s.left, s.right, s.bottom);
}

/// How far past the original screen there's something real to show, from
/// what the game has in ram: the room or area's bounds, or the full margin
/// on screens that are drawn edge to edge anyway. Randomizer mode fills
/// g_ram from the emulated console to use the same rules.
pub fn widescreenSideSpace(max: c_int) struct { left: c_int, right: c_int, bottom: c_int } {
    var extra_right: c_int = 0;
    var extra_left: c_int = 0;
    var extra_bottom: c_int = 0;
    var mod: c_int = vars.main_module_index.*;
    if (mod == 14)
        mod = vars.saved_module_for_menu.*;
    if (mod == 9) {
        if (vars.main_module_index.* == 14 and vars.submodule_index.* == 7 and vars.overworld_map_state.* >= 4) {
            // World map
            extra_left = max;
            extra_right = max;
            extra_bottom = 16;
        } else {
            // outdoors
            extra_left = @as(c_int, vars.BG2HOFS_copy2.*) - vars.ow_scroll_vars0.xstart;
            extra_right = @as(c_int, vars.ow_scroll_vars0.xend) - vars.BG2HOFS_copy2.*;
            extra_bottom = @as(c_int, vars.ow_scroll_vars0.yend) - vars.BG2VOFS_copy2.*;
        }
    } else if (mod == 7) {
        // indoors, except when the light cone is in use
        if (!(vars.hdr_dungeon_dark_with_lantern.* != 0 and vars.TS_copy.* != 0)) {
            const qm = vars.quadrant_fullsize_x.* >> 1;
            extra_left = intMax(@as(c_int, vars.BG2HOFS_copy2.*) - vars.room_bounds_x.v[qm], 0);
            extra_right = intMax(@as(c_int, vars.room_bounds_x.v[qm + 2]) - vars.BG2HOFS_copy2.*, 0);
        }

        const qy = vars.quadrant_fullsize_y.* >> 1;
        extra_bottom = intMax(@as(c_int, vars.room_bounds_y.v[qy + 2]) - vars.BG2VOFS_copy2.*, 0);
    } else if (mod == 20 or mod == 0 or mod == 1) {
        extra_left = max;
        extra_right = max;
        extra_bottom = 16;
    }
    return .{ .left = extra_left, .right = extra_right, .bottom = extra_bottom };
}

pub export fn ZeldaDrawPpuFrame(pixel_buffer: [*]u8, pitch: usize, render_flags: u32) callconv(.c) void {
    var hdma_chans: [2]SimpleHdma = undefined;
    const ppu = zenvPpu();

    ppu_mod.PpuBeginDrawing(ppu, pixel_buffer, pitch, render_flags);

    dma_mod.dma_startDma(zenvDma(), vars.HDMAEN_copy.*, true);

    SimpleHdma_Init(&hdma_chans[0], &zenvDma().channel[6]);
    SimpleHdma_Init(&hdma_chans[1], &zenvDma().channel[7]);

    // Cheat: Let the PPU impl know about the hdma perspective correction so it can avoid guessing.
    if ((render_flags & kPpuRenderFlags_4x4Mode7) != 0 and ppu.mode == 7) {
        const t = @intFromPtr(hdma_chans[0].table);
        if (t == @intFromPtr(&kMapModeHdma0)) {
            ppu_mod.PpuSetMode7PerspectiveCorrection(ppu, kMapMode_Zooms1[0], kMapMode_Zooms1[223]);
        } else if (t == @intFromPtr(&kMapModeHdma1)) {
            ppu_mod.PpuSetMode7PerspectiveCorrection(ppu, kMapMode_Zooms2[0], kMapMode_Zooms2[223]);
        } else if (t == @intFromPtr(&kAttractIndirectHdmaTab)) {
            ppu_mod.PpuSetMode7PerspectiveCorrection(ppu, vars.hdma_table_dynamic[0], vars.hdma_table_dynamic[223]);
        } else {
            ppu_mod.PpuSetMode7PerspectiveCorrection(ppu, 0, 0);
        }
    }

    if (ppu.extraLeftRight != 0 or render_flags & kPpuRenderFlags_Height240 != 0)
        ConfigurePpuSideSpace();
    ConfigureHudSplit(ppu);

    const height: c_int = if (render_flags & kPpuRenderFlags_Height240 != 0) 240 else 224;

    var i: c_int = 0;
    while (i <= height) : (i += 1) {
        if (i == 128 and vars.irq_flag.* != 0) {
            zelda_ppu_write(BG3HOFS, @truncate(vars.selectfile_var8.*));
            zelda_ppu_write(BG3HOFS, @truncate(vars.selectfile_var8.* >> 8));
            zelda_ppu_write(BG3VOFS, 0);
            zelda_ppu_write(BG3VOFS, 0);
            if (vars.irq_flag.* & 0x80 != 0) {
                vars.irq_flag.* = 0;
                // zelda_snes_dummy_write(NMITIMEN, 0x81) is a no-op inline
            }
        }
        ppu_mod.ppu_runLine(ppu, i);
        SimpleHdma_DoLine(&hdma_chans[0]);
        SimpleHdma_DoLine(&hdma_chans[1]);
    }
}

pub export fn HdmaSetup(
    addr6: u32,
    addr7: u32,
    transfer_unit: u8,
    reg6: u8,
    reg7: u8,
    indirect_bank: u8,
) callconv(.c) void {
    const dma = zenvDma();
    if (addr6 != 0) {
        dma_mod.dma_write(dma, DMAP6, transfer_unit);
        dma_mod.dma_write(dma, BBAD6, reg6);
        dma_mod.dma_write(dma, A1T6L, @truncate(addr6));
        dma_mod.dma_write(dma, A1T6H, @truncate(addr6 >> 8));
        dma_mod.dma_write(dma, A1B6, @truncate(addr6 >> 16));
        dma_mod.dma_write(dma, DAS60, indirect_bank);
    }
    dma_mod.dma_write(dma, DMAP7, transfer_unit);
    dma_mod.dma_write(dma, BBAD7, reg7);
    dma_mod.dma_write(dma, A1T7L, @truncate(addr7));
    dma_mod.dma_write(dma, A1T7H, @truncate(addr7 >> 8));
    dma_mod.dma_write(dma, A1B7, @truncate(addr7 >> 16));
    dma_mod.dma_write(dma, DAS70, indirect_bank);
}

fn ZeldaInitializationCode() void {
    // The three zelda_snes_dummy_write calls are no-op inlines.
    Sound_LoadIntroSongBank();

    Startup_InitializeMemory();

    vars.animated_tile_data_src.* = 0xa680;
    vars.dma_source_addr_9.* = 0xb280;
    vars.dma_source_addr_14.* = 0xb280 + 0x60;
}

fn ClearOamBuffer() void { // 80841e
    for (0..128) |i|
        vars.oam_buf[i].y = 0xf0;
}

fn ZeldaRunGameLoop() void {
    vars.frame_counter.* +%= 1;
    ClearOamBuffer();
    Module_MainRouting();
    NMI_PrepareSprites();
    vars.nmi_boolean.* = 0;
}

pub export fn ZeldaInitialize() callconv(.c) void {
    g_zenv.dma = dma_mod.dma_init(null);
    g_zenv.ppu = ppu_mod.ppu_init();
    g_zenv.ram = &g_ram;
    g_zenv.sram = @ptrCast(calloc(8192, 1));
    g_zenv.vram = @ptrCast(&zenvPpu().vram);
    g_zenv.player = SpcPlayer_Create();
    SpcPlayer_Initialize(zenvPlayer());
    dma_mod.dma_reset(zenvDma());
    ppu_mod.ppu_reset(zenvPpu());
}

fn ZeldaRunPolyLoop() void {
    if (vars.intro_did_run_step.* != 0 and vars.nmi_flag_update_polyhedral.* == 0) {
        poly.Poly_RunFrame();
        vars.intro_did_run_step.* = 0;
        vars.nmi_flag_update_polyhedral.* = 0xff;
    }
}

pub export fn ZeldaRunFrameInternal(input: u16, run_what: c_int) callconv(.c) void {
    if (vars.animated_tile_data_src.* == 0)
        ZeldaInitializationCode();

    if (run_what & 2 != 0)
        ZeldaRunPolyLoop();
    if (run_what & 1 != 0)
        ZeldaRunGameLoop();
    nmi.Interrupt_NMI(input);
}

fn IncrementCrystalCountdown(a: *u8, v: c_int) c_int {
    const t = @as(c_int, a.*) + v;
    a.* = @truncate(@as(c_uint, @bitCast(t)));
    return t >> 8;
}

pub export var frame_ctr_dbg: c_int = 0;
var g_emu_memory_ptr: ?[*]u8 = null;
var g_emu_runframe: ?*const fn (input: u16, run_what: c_int) callconv(.c) void = null;
var g_emu_syncall: ?*const fn () callconv(.c) void = null;

pub export fn ZeldaSetupEmuCallbacks(
    emu_ram: ?[*]u8,
    func: ?*const fn (input: u16, run_what: c_int) callconv(.c) void,
    sync_all: ?*const fn () callconv(.c) void,
) callconv(.c) void {
    g_emu_memory_ptr = emu_ram;
    g_emu_runframe = func;
    g_emu_syncall = sync_all;
}

fn EmuSynchronizeWholeState() void {
    if (g_emu_syncall) |f|
        f();
}

/// |ptr| must be a pointer into g_ram, will synchronize the RAM memory with the
/// emulator.
fn EmuSyncMemoryRegion(ptr: [*]const u8, n: usize) void {
    const off = @intFromPtr(ptr) - @intFromPtr(&g_ram);
    std.debug.assert(off < 0x20000);
    if (g_emu_memory_ptr) |dst|
        @memcpy((dst + off)[0..n], ptr[0..n]);
}

fn Startup_InitializeMemory() void { // 8087c0
    @memset(g_ram[0..0x2000], 0);
    vars.main_palette_buffer[0] = 0;
    srm_var1().* = 0;
    const sram = g_zenv.sram.?;
    if (std.mem.readInt(u16, sram[0x3e5..][0..2], .little) != 0x55aa)
        std.mem.writeInt(u16, sram[0x3e5..][0..2], 0, .little);
    if (std.mem.readInt(u16, sram[0x8e5..][0..2], .little) != 0x55aa)
        std.mem.writeInt(u16, sram[0x8e5..][0..2], 0, .little);
    if (std.mem.readInt(u16, sram[0xde5..][0..2], .little) != 0x55aa)
        std.mem.writeInt(u16, sram[0xde5..][0..2], 0, .little);
    vars.INIDISP_copy.* = 0x80;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn ByteArray_AppendVl(arr: *ByteArray, v_in: u32) callconv(.c) void {
    var v = v_in;
    while (v >= 255) : (v -= 255)
        util.ByteArray_AppendByte(arr, 255);
    util.ByteArray_AppendByte(arr, @truncate(v));
}

pub export fn saveFunc(ctx_in: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    const arr: *ByteArray = @ptrCast(@alignCast(ctx_in.?));
    util.ByteArray_AppendData(arr, @ptrCast(data.?), data_size);
}

const LoadFuncState = extern struct {
    p: [*]u8,
    pend: [*]u8,
};

pub export fn loadFunc(ctx: ?*anyopaque, data: ?*anyopaque, data_size: usize) callconv(.c) void {
    const st: *LoadFuncState = @ptrCast(@alignCast(ctx.?));
    std.debug.assert(@intFromPtr(st.pend) - @intFromPtr(st.p) >= data_size);
    const dst: [*]u8 = @ptrCast(data.?);
    @memcpy(dst[0..data_size], st.p[0..data_size]);
    st.p += data_size;
}

fn InternalSaveLoad(func: *const SaveLoadFunc, ctx: ?*anyopaque) void {
    var junk: [58]u8 = @splat(0);
    func(ctx, &junk, 27);
    func(ctx, &zenvPlayer().ram, 0x10000); // apu ram
    func(ctx, &junk, 40); // junk
    dsp_mod.dsp_saveload(zenvPlayer().dsp.?, func, ctx); // 3024 bytes of dsp
    func(ctx, &junk, 15); // spc junk
    dma_mod.dma_saveload(zenvDma(), func, ctx); // 192 bytes of dma state
    ppu_mod.ppu_saveload(zenvPpu(), func, ctx); // 66619 + 512 + 174
    func(ctx, g_zenv.sram.?, 0x2000); // 8192 bytes of sram
    func(ctx, &junk, 58); // snes junk
    func(ctx, &g_ram, 0x20000); // 0x20000 bytes of ram
    func(ctx, &junk, 4); // snes junk
}

pub export fn ZeldaReset(preserve_sram: bool) callconv(.c) void {
    frame_ctr_dbg = 0;
    dma_mod.dma_reset(zenvDma());
    ppu_mod.ppu_reset(zenvPpu());
    @memset(g_ram[0..0x20000], 0);
    if (!preserve_sram)
        @memset(g_zenv.sram.?[0..0x2000], 0);
    main_mod.ZeldaApuLock();
    audio.ZeldaRestoreMusicAfterLoad_Locked(true);
    main_mod.ZeldaApuUnlock();
    EmuSynchronizeWholeState();
}

fn LoadSnesState(func: *const SaveLoadFunc, ctx: ?*anyopaque) void {
    // Do the actual loading
    main_mod.ZeldaApuLock();
    InternalSaveLoad(func, ctx);
    // hdma table was moved
    std.mem.copyForwards(u8, g_ram[0x1DBA0..][0 .. 224 * 2], g_ram[0x1b00..][0 .. 224 * 2]);

    audio.ZeldaRestoreMusicAfterLoad_Locked(false);
    main_mod.ZeldaApuUnlock();
    EmuSynchronizeWholeState();
}

fn SaveSnesState(func: *const SaveLoadFunc, ctx: ?*anyopaque) void {
    // hdma table was moved
    std.mem.copyForwards(u8, g_ram[0x1b00..][0 .. 224 * 2], g_ram[0x1DBA0..][0 .. 224 * 2]);
    main_mod.ZeldaApuLock();
    audio.ZeldaSaveMusicStateToRam_Locked();
    InternalSaveLoad(func, ctx);
    main_mod.ZeldaApuUnlock();
}

const StateRecorder = struct {
    last_inputs: u16 = 0,
    frames_since_last: u32 = 0,
    total_frames: u32 = 0,

    // For replay
    replay_pos: u32 = 0,
    replay_pos_last_complete: u32 = 0,
    replay_frame_counter: u32 = 0,
    replay_next_cmd_at: u32 = 0,
    replay_cmd: u8 = 0,
    replay_mode: bool = false,

    log: ByteArray = .{ .data = null, .size = 0, .capacity = 0 },
    base_snapshot: ByteArray = .{ .data = null, .size = 0, .capacity = 0 },
};

var state_recorder: StateRecorder = .{};

fn StateRecorder_RecordCmd(sr: *StateRecorder, cmd: u8) void {
    const frames = sr.frames_since_last;
    sr.frames_since_last = 0;
    const x: u32 = if (cmd < 0xc0) 0xf else 0x1;
    util.ByteArray_AppendByte(&sr.log, cmd | @as(u8, @truncate(if (frames < x) frames else x)));
    if (frames >= x)
        ByteArray_AppendVl(&sr.log, frames - x);
}

fn StateRecorder_Record(sr: *StateRecorder, inputs: u16) void {
    const diff = inputs ^ sr.last_inputs;
    if (diff != 0) {
        sr.last_inputs = inputs;
        for (0..12) |i| {
            if ((diff >> @intCast(i)) & 1 != 0)
                StateRecorder_RecordCmd(sr, @intCast(i << 4));
        }
    }
    sr.frames_since_last += 1;
    sr.total_frames += 1;
}

fn StateRecorder_RecordPatchByte(sr: *StateRecorder, addr: u32, value: [*]const u8, num: u32) void {
    std.debug.assert(addr < 0x20000);

    const lq: u32 = if (num - 1 <= 3) num - 1 else 3;
    StateRecorder_RecordCmd(sr, @intCast(0xc0 | (if (addr & 0x10000 != 0) @as(u32, 2) else 0) | lq << 2));
    if (lq == 3)
        ByteArray_AppendVl(&sr.log, num - 1 - 3);
    util.ByteArray_AppendByte(&sr.log, @truncate(addr >> 8));
    util.ByteArray_AppendByte(&sr.log, @truncate(addr));
    for (0..num) |i|
        util.ByteArray_AppendByte(&sr.log, value[i]);
}

fn ReadFromFile(f: *FILE, data: *anyopaque, n: usize) void {
    if (fread(data, 1, n, f) != n)
        Die("fread failed\n");
}

/// Read a whole ByteArray back, tolerating the null pointer an empty one
/// carries: ByteArray_Resize never allocates for a size of 0, and the C passes
/// that NULL straight to fread with a length of 0, which reads nothing and
/// succeeds. Unwrapping it instead would panic.
fn ReadArrayFromFile(f: *FILE, arr: *const ByteArray) void {
    if (arr.size == 0) return;
    ReadFromFile(f, arr.data.?, arr.size);
}

/// The write side of the same thing: fwrite(NULL, 1, 0, f) is a no-op in the C.
fn WriteArrayToFile(f: *FILE, arr: *const ByteArray) void {
    if (arr.size == 0) return;
    _ = fwrite(arr.data.?, 1, arr.size, f);
}

fn StateRecorder_Load(sr: *StateRecorder, f: *FILE, replay_mode: bool) void {
    // todo: fix robustness on invalid data.
    var hdr: [8]u32 = @splat(0);
    ReadFromFile(f, &hdr, @sizeOf(@TypeOf(hdr)));

    std.debug.assert(hdr[0] == 1);

    sr.total_frames = hdr[1];
    util.ByteArray_Resize(&sr.log, hdr[2]);
    ReadArrayFromFile(f, &sr.log);
    sr.last_inputs = @truncate(hdr[3]);
    sr.frames_since_last = hdr[4];

    util.ByteArray_Resize(&sr.base_snapshot, if (hdr[5] & 1 != 0) hdr[6] else 0);
    ReadArrayFromFile(f, &sr.base_snapshot);

    sr.replay_next_cmd_at = 0;

    sr.replay_mode = replay_mode;
    if (replay_mode) {
        sr.frames_since_last = 0;
        sr.last_inputs = 0;
        sr.replay_pos = 0;
        sr.replay_pos_last_complete = 0;
        sr.replay_frame_counter = 0;
        // Load snapshot from |base_snapshot_|, or reset if empty.
        if (sr.base_snapshot.size != 0) {
            var state = LoadFuncState{
                .p = sr.base_snapshot.data.?,
                .pend = sr.base_snapshot.data.? + sr.base_snapshot.size,
            };
            LoadSnesState(&loadFunc, &state);
            std.debug.assert(state.p == state.pend);
        } else {
            ZeldaReset(false);
        }
    } else {
        // Resume replay from the saved position?
        sr.replay_pos = hdr[5] >> 1;
        sr.replay_pos_last_complete = sr.replay_pos;
        sr.replay_frame_counter = hdr[7];
        sr.replay_mode = sr.replay_frame_counter != 0;

        var arr = ByteArray{ .data = null, .size = 0, .capacity = 0 };
        util.ByteArray_Resize(&arr, hdr[6]);
        ReadArrayFromFile(f, &arr);
        var state = LoadFuncState{ .p = arr.data.?, .pend = arr.data.? + arr.size };
        LoadSnesState(&loadFunc, &state);
        util.ByteArray_Destroy(&arr);
        std.debug.assert(state.p == state.pend);
    }
}

fn StateRecorder_Save(sr: *StateRecorder, f: *FILE) void {
    var hdr: [8]u32 = @splat(0);
    var arr = ByteArray{ .data = null, .size = 0, .capacity = 0 };
    SaveSnesState(&saveFunc, &arr);
    std.debug.assert(sr.base_snapshot.size == 0 or sr.base_snapshot.size == arr.size);

    hdr[0] = 1;
    hdr[1] = sr.total_frames;
    hdr[2] = @intCast(sr.log.size);
    hdr[3] = sr.last_inputs;
    hdr[4] = sr.frames_since_last;
    hdr[5] = if (sr.base_snapshot.size != 0) 1 else 0;
    hdr[6] = @intCast(arr.size);
    // If saving while in replay mode, also need to persist
    // sr->replay_pos_last_complete and sr->replay_frame_counter
    // so the replaying can be resumed.
    if (sr.replay_mode) {
        hdr[5] |= sr.replay_pos_last_complete << 1;
        hdr[7] = sr.replay_frame_counter;
    }
    _ = fwrite(&hdr, 1, @sizeOf(@TypeOf(hdr)), f);
    WriteArrayToFile(f, &sr.log);
    WriteArrayToFile(f, &sr.base_snapshot);
    WriteArrayToFile(f, &arr);

    util.ByteArray_Destroy(&arr);
}

fn StateRecorder_ClearKeyLog(sr: *StateRecorder) void {
    _ = printf("Clearing key log!\n");
    sr.base_snapshot.size = 0;
    SaveSnesState(&saveFunc, &sr.base_snapshot);
    const old_log = sr.log;
    const old_frames_since_last = sr.frames_since_last;
    sr.log = .{ .data = null, .size = 0, .capacity = 0 };
    // If there are currently any active inputs, record them initially at timestamp 0.
    sr.frames_since_last = 0;
    if (sr.last_inputs != 0) {
        for (0..12) |i| {
            if ((sr.last_inputs >> @intCast(i)) & 1 != 0)
                StateRecorder_RecordCmd(sr, @intCast(i << 4));
        }
    }
    if (sr.replay_mode) {
        // When clearing the key log while in replay mode, we want to keep
        // replaying but discarding all key history up until this point.
        if (sr.replay_next_cmd_at != 0xffffffff) {
            sr.replay_next_cmd_at -%= old_frames_since_last;
            sr.frames_since_last = sr.replay_next_cmd_at;
            sr.replay_pos_last_complete = @intCast(sr.log.size);
            StateRecorder_RecordCmd(sr, sr.replay_cmd);
            const old_replay_pos = sr.replay_pos;
            sr.replay_pos = @intCast(sr.log.size);
            util.ByteArray_AppendData(&sr.log, old_log.data.? + old_replay_pos, old_log.size - old_replay_pos);
        }
        sr.total_frames -%= sr.replay_frame_counter;
        sr.replay_frame_counter = 0;
    } else {
        sr.total_frames = 0;
    }
    var old = old_log;
    util.ByteArray_Destroy(&old);
    sr.frames_since_last = 0;
}

fn StateRecorder_ReadNextReplayState(sr: *StateRecorder) u16 {
    std.debug.assert(sr.replay_mode);
    while (sr.frames_since_last >= sr.replay_next_cmd_at) {
        var replay_pos = sr.replay_pos;
        if (replay_pos != sr.replay_pos_last_complete) {
            // Apply next command
            sr.frames_since_last = 0;
            if (sr.replay_cmd < 0xc0) {
                sr.last_inputs ^= @as(u16, 1) << @intCast(sr.replay_cmd >> 4);
            } else if (sr.replay_cmd < 0xd0) {
                var nb: u32 = 1 + ((sr.replay_cmd >> 2) & 3);
                if (nb == 4) {
                    while (true) {
                        const t = sr.log.data.?[replay_pos];
                        replay_pos += 1;
                        nb += t;
                        if (t != 255) break;
                    }
                }
                var addr: u32 = @as(u32, (sr.replay_cmd >> 1) & 1) << 16;
                addr |= @as(u32, sr.log.data.?[replay_pos]) << 8;
                replay_pos += 1;
                addr |= sr.log.data.?[replay_pos];
                replay_pos += 1;
                while (true) {
                    g_ram[addr & 0x1ffff] = sr.log.data.?[replay_pos];
                    replay_pos += 1;
                    EmuSyncMemoryRegion(g_ram[addr & 0x1ffff ..].ptr, 1);
                    addr +%= 1;
                    nb -= 1;
                    if (nb == 0) break;
                }
            } else {
                unreachable; // assert(0)
            }
        }
        sr.replay_pos_last_complete = replay_pos;
        if (replay_pos >= sr.log.size) {
            sr.replay_pos = replay_pos;
            sr.replay_next_cmd_at = 0xffffffff;
            break;
        }
        // Read the next one
        const cmd = sr.log.data.?[replay_pos];
        replay_pos += 1;
        const mask: u32 = if (cmd < 0xc0) 0xf else 0x1;
        var frames: u32 = cmd & mask;
        if (frames == mask) {
            while (true) {
                const t = sr.log.data.?[replay_pos];
                replay_pos += 1;
                frames += t;
                if (t != 255) break;
            }
        }
        sr.replay_next_cmd_at = frames;
        sr.replay_cmd = cmd;
        sr.replay_pos = replay_pos;
    }
    sr.frames_since_last += 1;
    // Turn off replay mode after we reached the final frame position
    sr.replay_frame_counter += 1;
    if (sr.replay_frame_counter >= sr.total_frames)
        sr.replay_mode = false;
    return sr.last_inputs;
}

fn StateRecorder_StopReplay(sr: *StateRecorder) void {
    if (!sr.replay_mode)
        return;
    sr.replay_mode = false;
    sr.total_frames = sr.replay_frame_counter;
    sr.log.size = sr.replay_pos_last_complete;
}

pub export fn ZeldaRunFrame(inputs_in: c_int) callconv(.c) bool {
    var inputs = inputs_in;

    // Avoid up/down and left/right from being pressed at the same time
    if ((inputs & 0x30) == 0x30) inputs ^= 0x30;
    if ((inputs & 0xc0) == 0xc0) inputs ^= 0xc0;

    frame_ctr_dbg +%= 1;

    const is_replay = state_recorder.replay_mode;

    // Either copy state or apply state
    if (is_replay) {
        inputs = StateRecorder_ReadNextReplayState(&state_recorder);
    } else {
        StateRecorder_Record(&state_recorder, @truncate(@as(c_uint, @bitCast(inputs))));

        // This is whether APUI00 is true or false, this is used by the ancilla code.
        const apui00: u8 = @intFromBool(audio.ZeldaIsMusicPlaying());
        if (apui00 != g_ram[kRam_APUI00]) {
            g_ram[kRam_APUI00] = apui00;
            EmuSyncMemoryRegion(g_ram[kRam_APUI00..].ptr, 1);
            StateRecorder_RecordPatchByte(&state_recorder, 0x648, g_ram[kRam_APUI00..].ptr, 1);
        }

        if (vars.animated_tile_data_src.* != 0) {
            // Whenever we're no longer replaying, we'll remember what bugs were fixed,
            // but only if game is initialized.
            if (g_ram[kRam_BugsFixed] < kBugFix_Latest) {
                g_ram[kRam_BugsFixed] = kBugFix_Latest;
                EmuSyncMemoryRegion(g_ram[kRam_BugsFixed..].ptr, 1);
                StateRecorder_RecordPatchByte(&state_recorder, kRam_BugsFixed, g_ram[kRam_BugsFixed..].ptr, 1);
            }

            if (features.enhanced_features0.* != g_wanted_zelda_features) {
                features.enhanced_features0.* = g_wanted_zelda_features;
                const p: [*]const u8 = @ptrCast(features.enhanced_features0);
                EmuSyncMemoryRegion(p, 4);
                StateRecorder_RecordPatchByte(&state_recorder, kRam_Features0, p, 4);
            }
        }
    }

    var run_what: c_int = undefined;
    if (g_ram[kRam_BugsFixed] < kBugFix_PolyRenderer) {
        // A previous version of this code alternated the game loop with
        // the poly renderer.
        run_what = if (vars.is_nmi_thread_active.* != 0 and vars.thread_other_stack.* != 0x1f31) 2 else 1;
    } else {
        // The snes seems to let poly rendering run for a little
        // while each fram until it eventually completes a frame.
        // Simulate this by rendering the poly every n:th frame.
        const busy = vars.is_nmi_thread_active.* != 0 and
            IncrementCrystalCountdown(&g_ram[kRam_CrystalRotateCounter], vars.virq_trigger.*) != 0;
        run_what = if (busy) 3 else 1;
        EmuSyncMemoryRegion(g_ram[kRam_CrystalRotateCounter..].ptr, 1);
    }

    if (g_emu_runframe == null or features.enhanced_features0.* != 0 or g_zenv.dialogue_flags != 0) {
        // can't compare against real impl when running with extra features.
        ZeldaRunFrameInternal(@truncate(@as(c_uint, @bitCast(inputs))), run_what);
    } else {
        g_emu_runframe.?(@truncate(@as(c_uint, @bitCast(inputs))), run_what);
    }

    audio.ZeldaPushApuState();

    return is_replay;
}

pub export fn ZeldaSetLanguage(language: ?[*:0]const u8) callconv(.c) void {
    const kDefaultConf = [3]u8{ 0, 0, 0 };
    var found = MemBlk{ .ptr = &kDefaultConf, .size = 3 };
    if (language) |lang| {
        const n = std.mem.len(lang);
        var i: c_int = 0;
        while (true) : (i += 1) {
            const mb = main_mod.FindInAssetArray(96, i); // kDialogueMap
            if (mb.ptr == null) {
                std.debug.print("Unable to find language '{s}'\n", .{lang});
                break;
            }
            const name = util.FindIndexInMemblk(mb, 0);
            if (name.size == n and std.mem.eql(u8, name.ptr.?[0..n], lang[0..n])) {
                found = util.FindIndexInMemblk(mb, 1);
                break;
            }
        }
    }
    g_zenv.dialogue_blk = @bitCast(main_mod.FindInAssetArray(94, found.ptr.?[0])); // kDialogue
    g_zenv.dialogue_font_blk = @bitCast(main_mod.FindInAssetArray(95, found.ptr.?[1])); // kDialogueFont
    g_zenv.dialogue_flags = found.ptr.?[2];
}

const kReferenceSaves = [13][*:0]const u8{
    "Chapter 1 - Zelda's Rescue.sav",
    "Chapter 2 - After Eastern Palace.sav",
    "Chapter 3 - After Desert Palace.sav",
    "Chapter 4 - After Tower of Hera.sav",
    "Chapter 5 - After Hyrule Castle Tower.sav",
    "Chapter 6 - After Dark Palace.sav",
    "Chapter 7 - After Swamp Palace.sav",
    "Chapter 8 - After Skull Woods.sav",
    "Chapter 9 - After Gargoyle's Domain.sav",
    "Chapter 10 - After Ice Palace.sav",
    "Chapter 11 - After Misery Mire.sav",
    "Chapter 12 - After Turtle Rock.sav",
    "Chapter 13 - After Ganon's Tower.sav",
};

pub export fn SaveLoadSlot(cmd: c_int, which: c_int) callconv(.c) void {
    var name: [128]u8 = undefined;
    if (which & 256 != 0) {
        if (cmd == kSaveLoad_Save)
            return;
        _ = sprintf(&name, "saves/ref/%s", kReferenceSaves[@intCast(which - 256)]);
    } else {
        _ = sprintf(&name, "saves/save%d.sav", which);
    }
    const f = fopen(@ptrCast(&name), if (cmd != kSaveLoad_Save) "rb" else "wb");
    if (f) |file| {
        _ = printf("*** %s slot %d\n", if (cmd == kSaveLoad_Save)
            @as([*:0]const u8, "Saving")
        else if (cmd == kSaveLoad_Load)
            @as([*:0]const u8, "Loading")
        else
            @as([*:0]const u8, "Replaying"), which);

        if (cmd != kSaveLoad_Save)
            StateRecorder_Load(&state_recorder, file, cmd == kSaveLoad_Replay)
        else
            StateRecorder_Save(&state_recorder, file);

        _ = fclose(file);
    }
}

const StateRecoderMultiPatch = struct {
    count: u32,
    addr: u32,
    vals: [256]u8,
};

fn StateRecoderMultiPatch_Init(mp: *StateRecoderMultiPatch) void {
    mp.count = 0;
    mp.addr = 0;
}

fn StateRecoderMultiPatch_Commit(mp: *StateRecoderMultiPatch) void {
    if (mp.count != 0)
        StateRecorder_RecordPatchByte(&state_recorder, mp.addr, &mp.vals, mp.count);
}

fn StateRecoderMultiPatch_Patch(mp: *StateRecoderMultiPatch, addr: u32, value: u8) void {
    if (mp.count >= 256 or addr != mp.addr + mp.count) {
        StateRecoderMultiPatch_Commit(mp);
        mp.addr = addr;
        mp.count = 0;
    }
    mp.vals[mp.count] = value;
    mp.count += 1;
    g_ram[addr] = value;
    EmuSyncMemoryRegion(g_ram[addr..].ptr, 1);
}

pub export fn PatchCommand(ch: u8) callconv(.c) void {
    var mp: StateRecoderMultiPatch = undefined;

    StateRecoderMultiPatch_Init(&mp);
    if (ch == 'w') {
        StateRecoderMultiPatch_Patch(&mp, 0xf372, 80); // health filler
        StateRecoderMultiPatch_Patch(&mp, 0xf373, 80); // magic filler
    } else if (ch == 'W') {
        StateRecoderMultiPatch_Patch(&mp, 0xf375, 10); // link_bomb_filler
        StateRecoderMultiPatch_Patch(&mp, 0xf376, 10); // link_arrow_filler
        const rupees = vars.link_rupees_goal.* +% 100;
        StateRecoderMultiPatch_Patch(&mp, 0xf360, @truncate(rupees)); // link_rupees_goal
        StateRecoderMultiPatch_Patch(&mp, 0xf361, @truncate(rupees >> 8)); // link_rupees_goal
    } else if (ch == 'k') {
        StateRecorder_ClearKeyLog(&state_recorder);
    } else if (ch == 'o') {
        StateRecoderMultiPatch_Patch(&mp, 0xf36f, 1);
    } else if (ch == 'l') {
        StateRecorder_StopReplay(&state_recorder);
    } else if (ch == 'E') {
        StateRecoderMultiPatch_Patch(&mp, 0x37f, g_ram[0x37f] ^ 1);
    }
    StateRecoderMultiPatch_Commit(&mp);
}

pub export fn ZeldaReadSram() callconv(.c) void {
    const f = fopen("saves/sram.dat", "rb");
    if (f) |file| {
        if (fread(g_zenv.sram.?, 1, 8192, file) != 8192)
            std.debug.print("Error reading saves/sram.dat\n", .{});
        _ = fclose(file);
        EmuSynchronizeWholeState();
    }
}

pub export fn ZeldaWriteSram() callconv(.c) void {
    _ = rename("saves/sram.dat", "saves/sram.bak");
    const f = fopen("saves/sram.dat", "wb");
    if (f) |file| {
        _ = fwrite(g_zenv.sram.?, 1, 8192, file);
        _ = fclose(file);
    } else {
        std.debug.print("Unable to write saves/sram.dat\n", .{});
    }
}

const testing = std.testing;

extern fn tmpfile() ?*FILE;
extern fn rewind(f: *FILE) void;

test "the state file helpers tolerate the null pointer an empty array carries" {
    const f = tmpfile() orelse return error.SkipZigTest;
    defer _ = fclose(f);

    // ByteArray_Resize never allocates for a size of 0, so an empty array's
    // data stays null. The C hands that null to fwrite/fread with a length of
    // 0, which does nothing; unwrapping it panicked instead, which truncated
    // every save state the port wrote at the first empty section.
    var empty = ByteArray{ .data = null, .size = 0, .capacity = 0 };
    try testing.expect(empty.data == null);
    WriteArrayToFile(f, &empty);

    var src = ByteArray{ .data = null, .size = 0, .capacity = 0 };
    defer util.ByteArray_Destroy(&src);
    util.ByteArray_Resize(&src, 4);
    @memcpy(src.data.?[0..4], "abcd");
    WriteArrayToFile(f, &src);

    rewind(f);

    // The empty write contributed no bytes, so the populated one is all there is.
    ReadArrayFromFile(f, &empty);
    var dst = ByteArray{ .data = null, .size = 0, .capacity = 0 };
    defer util.ByteArray_Destroy(&dst);
    util.ByteArray_Resize(&dst, 4);
    ReadArrayFromFile(f, &dst);
    try testing.expectEqualSlices(u8, "abcd", dst.data.?[0..4]);
}

test "the hdma mode tables came over intact" {
    try testing.expectEqual(8, bAdrOffsets.len);
    try testing.expectEqual(8, transferLength.len);
    // Mode 4 writes four consecutive registers, mode 0 writes one repeatedly.
    try testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3 }, &bAdrOffsets[4]);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &bAdrOffsets[0]);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 2, 4, 4, 4, 2, 4 }, &transferLength);
}

test "the exported tables match the C" {
    try testing.expectEqual(16, kUpperBitmasks.len);
    try testing.expectEqual(0x8000, kUpperBitmasks[0]);
    try testing.expectEqual(1, kUpperBitmasks[15]);
    // Each entry is a single bit walking down from the top.
    for (kUpperBitmasks, 0..) |v, i|
        try testing.expectEqual(@as(u16, 0x8000) >> @intCast(i), v);

    try testing.expectEqualSlices(u8, &.{ 31, 8, 4, 0 }, &kLitTorchesColorPlus);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 4, 2, 0, 16, 2, 1, 64, 4, 1, 32, 8 }, &kDungeonCrystalPendantBit);
    try testing.expectEqualSlices(i8, &.{ 7, 7, -3, 16 }, &kGetBestActionToPerformOnTile_x);
    try testing.expectEqualSlices(i8, &.{ 6, 24, 12, 12 }, &kGetBestActionToPerformOnTile_y);
}

test "AT_WORD splits a word little endian" {
    try testing.expectEqualSlices(u8, &.{ 0xff, 0x00 }, &atWord(0x00ff));
    try testing.expectEqualSlices(u8, &.{ 0x18, 0xe0 }, &atWord(0xe018));
    // The assembled hdma tables keep the lengths the C declared.
    try testing.expectEqual(13, kAttractDmaTable0.len);
    try testing.expectEqual(10, kAttractDmaTable1.len);
    try testing.expectEqual(19, kHdmaTableForEnding.len);
    try testing.expectEqual(7, kSpotlightIndirectHdma.len);
    try testing.expectEqual(7, kMapModeHdma0.len);
    try testing.expectEqual(7, kMapModeHdma1.len);
    try testing.expectEqual(7, kAttractIndirectHdmaTab.len);
    try testing.expectEqual(7, kHdmaTableForPrayingScene.len);
    // The assembled bytes, expanded by hand from the C's AT_WORD() spellings.
    try testing.expectEqualSlices(u8, &.{
        0x20, 0xff, 0x00, 0x50, 0x18, 0xe0, 0x50, 0x18, 0xe0, 0x01, 0xff, 0x00, 0x00,
    }, &kAttractDmaTable0);
    try testing.expectEqualSlices(u8, &.{
        0x48, 0xff, 0x00, 0x30, 0x30, 0xd8, 0x01, 0xff, 0x00, 0x00,
    }, &kAttractDmaTable1);
    try testing.expectEqualSlices(u8, &.{
        0x52, 0x00, 0x06, 0x08, 0xe2, 0x00, 0x08, 0x02, 0x06, 0x05,
        0x04, 0x06, 0x10, 0x06, 0x06, 0x81, 0xe2, 0x00, 0x00,
    }, &kHdmaTableForEnding);
    try testing.expectEqualSlices(u8, &.{ 0xf8, 0x00, 0x1b, 0xf8, 0xf0, 0x1b, 0x00 }, &kSpotlightIndirectHdma);
    try testing.expectEqualSlices(u8, &.{ 0xf0, 0x27, 0xdd, 0xf0, 0x07, 0xde, 0x00 }, &kMapModeHdma0);
    try testing.expectEqualSlices(u8, &.{ 0xf0, 0xe7, 0xde, 0xf0, 0xc7, 0xdf, 0x00 }, &kMapModeHdma1);
    try testing.expectEqualSlices(u8, &.{ 0xf0, 0x00, 0x1b, 0xf0, 0xe0, 0x1b, 0x00 }, &kAttractIndirectHdmaTab);
    try testing.expectEqualSlices(u8, &.{ 0xf8, 0x00, 0x1b, 0xf8, 0xf0, 0x1b, 0x00 }, &kHdmaTableForPrayingScene);
    // Every table is terminated by a zero repeat count.
    try testing.expectEqual(0, kAttractDmaTable0[12]);
    try testing.expectEqual(0, kHdmaTableForEnding[18]);
}

test "variable length integers use 255 as a continuation" {
    var arr = ByteArray{ .data = null, .size = 0, .capacity = 0 };
    defer util.ByteArray_Destroy(&arr);

    ByteArray_AppendVl(&arr, 5);
    try testing.expectEqual(1, arr.size);
    try testing.expectEqual(@as(u8, 5), arr.data.?[0]);

    // 255 needs a full continuation byte followed by the remainder.
    arr.size = 0;
    ByteArray_AppendVl(&arr, 255);
    try testing.expectEqual(2, arr.size);
    try testing.expectEqual(@as(u8, 255), arr.data.?[0]);
    try testing.expectEqual(@as(u8, 0), arr.data.?[1]);

    arr.size = 0;
    ByteArray_AppendVl(&arr, 600);
    try testing.expectEqual(3, arr.size);
    try testing.expectEqual(@as(u8, 255), arr.data.?[0]);
    try testing.expectEqual(@as(u8, 255), arr.data.?[1]);
    try testing.expectEqual(@as(u8, 90), arr.data.?[2]); // 600 - 510
}

test "input changes are recorded one bit at a time" {
    var sr = StateRecorder{};
    defer util.ByteArray_Destroy(&sr.log);

    // No change records nothing but still advances the frame counters.
    StateRecorder_Record(&sr, 0);
    try testing.expectEqual(0, sr.log.size);
    try testing.expectEqual(1, sr.total_frames);
    try testing.expectEqual(1, sr.frames_since_last);

    // Pressing bit 0 emits one command, and resets frames_since_last.
    StateRecorder_Record(&sr, 1);
    try testing.expectEqual(1, sr.log.size);
    try testing.expectEqual(@as(u16, 1), sr.last_inputs);
    // cmd is (bit << 4) | frames, with one frame elapsed.
    try testing.expectEqual(@as(u8, 0x01), sr.log.data.?[0]);

    // Two bits changing at once emit two commands.
    const before = sr.log.size;
    StateRecorder_Record(&sr, 1 | (1 << 3) | (1 << 5));
    try testing.expectEqual(before + 2, sr.log.size);
}

test "the crystal countdown carries out of a byte" {
    var a: u8 = 0;
    try testing.expectEqual(0, IncrementCrystalCountdown(&a, 200));
    try testing.expectEqual(@as(u8, 200), a);
    // 200 + 100 overflows the byte and reports the carry.
    try testing.expectEqual(1, IncrementCrystalCountdown(&a, 100));
    try testing.expectEqual(@as(u8, 44), a);
    try testing.expectEqual(0, IncrementCrystalCountdown(&a, 0));
}

test "work ram and the environment are this module's own" {
    try testing.expectEqual(131072, g_ram.len);
    // variables.zig's accessors point into exactly this array.
    try testing.expectEqual(@intFromPtr(&g_ram[0x10]), @intFromPtr(vars.main_module_index));
    try testing.expectEqual(@intFromPtr(&g_ram[0x1A]), @intFromPtr(vars.frame_counter));
}

test "the reference save list covers all thirteen chapters" {
    try testing.expectEqual(13, kReferenceSaves.len);
    try testing.expectEqualStrings("Chapter 1 - Zelda's Rescue.sav", std.mem.span(kReferenceSaves[0]));
    try testing.expectEqualStrings("Chapter 13 - After Ganon's Tower.sav", std.mem.span(kReferenceSaves[12]));
}
