//! Port of src/nmi.c: everything the game does during vblank -- pushing
//! graphics into vram, latching the joypads, and writing back the shadow copies
//! of the PPU registers.
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl_types.zig");
const ppu_types = @import("../snes/ppu_types.zig");

const Ppu = ppu_types.Ppu;
const g_zenv = &rtl.g_zenv;

/// zelda_rtl.h: typedef void PlayerHandlerFunc();
const PlayerHandlerFunc = fn () callconv(.c) void;

// assets.h
const kNumberOfAssets = 165;
extern const g_asset_ptrs: [kNumberOfAssets]?[*]const u8;

fn kLinkGraphics() [*]const u8 {
    return g_asset_ptrs[57].?;
}

/// kBgTilemap_0 through kBgTilemap_5 are assets 99..104.
fn kBgTilemap(n: usize) [*]const u8 {
    return g_asset_ptrs[99 + n].?;
}

// Still in C: zelda_rtl.c, audio.c and messaging.c.
extern fn zelda_ppu_write(adr: u32, val: u8) void;
extern fn zelda_apu_write(adr: u32, val: u8) void;
extern fn zelda_apu_read(adr: u32) u8;
extern fn ZeldaIsPlayingMusicTrackWithBug(track: u8) bool;
extern fn ZeldaPlayMsuAudioTrack(track: u8) void;
extern fn GetLightOverworldTilemap() [*]const u8;

// snes_regs.h
const INIDISP = 0x2100;
const BGMODE = 0x2105;
const MOSAIC = 0x2106;
const BG12NBA = 0x210b;
const BG34NBA = 0x210c;
const BG1HOFS = 0x210d;
const BG1VOFS = 0x210e;
const BG2HOFS = 0x210f;
const BG2VOFS = 0x2110;
const BG3HOFS = 0x2111;
const BG3VOFS = 0x2112;
const M7B = 0x211c;
const M7C = 0x211d;
const M7X = 0x211f;
const M7Y = 0x2120;
const W12SEL = 0x2123;
const W34SEL = 0x2124;
const WOBJSEL = 0x2125;
const TM = 0x212c;
const TS = 0x212d;
const TMW = 0x212e;
const TSW = 0x212f;
const CGWSEL = 0x2130;
const CGADSUB = 0x2131;
const COLDATA = 0x2132;
const APUI00 = 0x2140;
const APUI01 = 0x2141;
const APUI02 = 0x2142;
const APUI03 = 0x2143;

const g_ram = &vars.g_ram;
const uvram = vars.uvram;
const nmi_boolean = vars.nmi_boolean;
const nmi_disable_core_updates = vars.nmi_disable_core_updates;
const nmi_load_bg_from_vram = vars.nmi_load_bg_from_vram;
const nmi_subroutine_index = vars.nmi_subroutine_index;
const nmi_copy_packets_flag = vars.nmi_copy_packets_flag;
const nmi_update_tilemap_dst = vars.nmi_update_tilemap_dst;
const nmi_update_tilemap_src = vars.nmi_update_tilemap_src;
const nmi_load_target_addr = vars.nmi_load_target_addr;
const nmi_flag_update_polyhedral = vars.nmi_flag_update_polyhedral;
const flag_update_hud_in_nmi = vars.flag_update_hud_in_nmi;
const flag_update_cgram_in_nmi = vars.flag_update_cgram_in_nmi;
const flag_travel_bird = vars.flag_travel_bird;
const vram_upload_offset = vars.vram_upload_offset;
const word_7E0219 = vars.word_7E0219;
const word_7F4000 = vars.word_7F4000;
const hud_tile_indices_buffer = vars.hud_tile_indices_buffer;
const main_palette_buffer = vars.main_palette_buffer;
const animated_tile_vram_addr = vars.animated_tile_vram_addr;
const animated_tile_data_src = vars.animated_tile_data_src;
const is_nmi_thread_active = vars.is_nmi_thread_active;
const thread_other_stack = vars.thread_other_stack;

const music_control = vars.music_control;
const last_music_control = vars.last_music_control;
const music_unk1 = vars.music_unk1;
const sound_effect_ambient = vars.sound_effect_ambient;
const sound_effect_ambient_last = vars.sound_effect_ambient_last;
const sound_effect_1 = vars.sound_effect_1;
const sound_effect_2 = vars.sound_effect_2;

const joypad1L_last = vars.joypad1L_last;
const joypad1L_last2 = vars.joypad1L_last2;
const joypad1H_last = vars.joypad1H_last;
const joypad1H_last2 = vars.joypad1H_last2;
const filtered_joypad_L = vars.filtered_joypad_L;
const filtered_joypad_H = vars.filtered_joypad_H;

const W12SEL_copy = vars.W12SEL_copy;
const W34SEL_copy = vars.W34SEL_copy;
const WOBJSEL_copy = vars.WOBJSEL_copy;
const CGWSEL_copy = vars.CGWSEL_copy;
const CGADSUB_copy = vars.CGADSUB_copy;
const COLDATA_copy0 = vars.COLDATA_copy0;
const COLDATA_copy1 = vars.COLDATA_copy1;
const COLDATA_copy2 = vars.COLDATA_copy2;
const TM_copy = vars.TM_copy;
const TS_copy = vars.TS_copy;
const TMW_copy = vars.TMW_copy;
const TSW_copy = vars.TSW_copy;
const BG1HOFS_copy = vars.BG1HOFS_copy;
const BG1VOFS_copy = vars.BG1VOFS_copy;
const BG2HOFS_copy = vars.BG2HOFS_copy;
const BG2VOFS_copy = vars.BG2VOFS_copy;
const BG3HOFS_copy2 = vars.BG3HOFS_copy2;
const BG3VOFS_copy2 = vars.BG3VOFS_copy2;
const INIDISP_copy = vars.INIDISP_copy;
const MOSAIC_copy = vars.MOSAIC_copy;
const BGMODE_copy = vars.BGMODE_copy;
const M7X_copy = vars.M7X_copy;
const M7Y_copy = vars.M7Y_copy;

const dma_source_addr_0 = vars.dma_source_addr_0;
const dma_source_addr_1 = vars.dma_source_addr_1;
const dma_source_addr_2 = vars.dma_source_addr_2;
const dma_source_addr_3 = vars.dma_source_addr_3;
const dma_source_addr_4 = vars.dma_source_addr_4;
const dma_source_addr_5 = vars.dma_source_addr_5;
const dma_source_addr_6 = vars.dma_source_addr_6;
const dma_source_addr_7 = vars.dma_source_addr_7;
const dma_source_addr_8 = vars.dma_source_addr_8;
const dma_source_addr_9 = vars.dma_source_addr_9;
const dma_source_addr_10 = vars.dma_source_addr_10;
const dma_source_addr_11 = vars.dma_source_addr_11;
const dma_source_addr_12 = vars.dma_source_addr_12;
const dma_source_addr_13 = vars.dma_source_addr_13;
const dma_source_addr_14 = vars.dma_source_addr_14;
const dma_source_addr_15 = vars.dma_source_addr_15;
const dma_source_addr_16 = vars.dma_source_addr_16;
const dma_source_addr_17 = vars.dma_source_addr_17;
const dma_source_addr_18 = vars.dma_source_addr_18;
const dma_source_addr_19 = vars.dma_source_addr_19;
const dma_source_addr_20 = vars.dma_source_addr_20;
const dma_source_addr_21 = vars.dma_source_addr_21;

/// types.h BYTE(x): the low byte of a 16-bit work-ram word.
fn loByte(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

/// types.h WORD(x): an unaligned 16-bit view over a byte run.
fn wordPtr(p: [*]u8) *align(1) u16 {
    return @ptrCast(p);
}

fn readWord(p: [*]const u8) u16 {
    return std.mem.readInt(u16, p[0..2], .little);
}

fn swap16(v: u16) u16 {
    return (v << 8) | (v >> 8);
}

/// vram is addressed in words, but every length here is a byte count.
fn vramBytes(word_index: u32) [*]u8 {
    return @ptrCast(&g_zenv.vram.?[word_index]);
}

fn ppu() *Ppu {
    return @ptrCast(@alignCast(g_zenv.ppu.?));
}

const kNmiVramAddrs = [_]u8{
    0,  0,  4,  8,  12, 8,  12, 0,  4,  0,  8,  4,  12, 4,  12, 0,
    8,  16, 20, 24, 28, 24, 28, 16, 20, 16, 24, 20, 28, 20, 28, 16,
    24, 96, 104,
};

const kNmiSubroutines = [25]*const PlayerHandlerFunc{
    &NMI_UploadTilemap_doNothing,
    &NMI_UploadTilemap,
    &NMI_UploadBG3Text,
    &NMI_UpdateOWScroll,
    &NMI_UpdateSubscreenOverlay,
    &NMI_UpdateBG1Wall,
    &NMI_TileMapNothing,
    &NMI_UpdateLoadLightWorldMap,
    &NMI_UpdateBG2Left,
    &NMI_UpdateBGChar3and4,
    &NMI_UpdateBGChar5and6,
    &NMI_UpdateBGCharHalf,
    &NMI_UploadSubscreenOverlayLatter,
    &NMI_UploadSubscreenOverlayFormer,
    &NMI_UpdateBGChar0,
    &NMI_UpdateBGChar1,
    &NMI_UpdateBGChar2,
    &NMI_UpdateBGChar3,
    &NMI_UpdateObjChar0,
    &NMI_UpdateObjChar2,
    &NMI_UpdateObjChar3,
    &NMI_UploadDarkWorldMap,
    &NMI_UploadGameOverText,
    &NMI_UpdatePegTiles,
    &NMI_UpdateStarTiles,
};

pub export fn NMI_UploadSubscreenOverlayFormer() callconv(.c) void {
    NMI_HandleArbitraryTileMap(g_ram[0x12000..].ptr, 0, 0x40);
}

pub export fn NMI_UploadSubscreenOverlayLatter() callconv(.c) void {
    NMI_HandleArbitraryTileMap(g_ram[0x13000..].ptr, 0x40, 0x80);
}

fn CopyToVram(dstv: u32, src: [*]const u8, len: usize) void {
    @memcpy(vramBytes(dstv)[0..len], src[0..len]);
}

fn CopyToVramVertical(dstv: u32, src_in: [*]const u8, len: usize) void {
    std.debug.assert(!(len & 1 != 0));
    var dst: [*]u16 = @ptrCast(&g_zenv.vram.?[dstv]);
    var src = src_in;
    var i: usize = 0;
    const i_end = len >> 1;
    while (i < i_end) : ({
        i += 1;
        dst += 32;
        src += 2;
    }) {
        dst[0] = readWord(src);
    }
}

fn CopyToVramLow(src: [*]const u8, addr: u32, num: usize) void {
    const dst: [*]u16 = @ptrCast(&g_zenv.vram.?[addr]);
    for (0..num) |i|
        dst[i] = (dst[i] & ~@as(u16, 0xff)) | src[i];
}

pub export fn WritePpuRegisters() callconv(.c) void {
    zelda_ppu_write(W12SEL, W12SEL_copy.*);
    zelda_ppu_write(W34SEL, W34SEL_copy.*);
    zelda_ppu_write(WOBJSEL, WOBJSEL_copy.*);
    zelda_ppu_write(CGWSEL, CGWSEL_copy.*);
    zelda_ppu_write(CGADSUB, CGADSUB_copy.*);
    zelda_ppu_write(COLDATA, COLDATA_copy0.*);
    zelda_ppu_write(COLDATA, COLDATA_copy1.*);
    zelda_ppu_write(COLDATA, COLDATA_copy2.*);
    zelda_ppu_write(TM, TM_copy.*);
    zelda_ppu_write(TS, TS_copy.*);
    zelda_ppu_write(TMW, TMW_copy.*);
    zelda_ppu_write(TSW, TSW_copy.*);
    zelda_ppu_write(BG1HOFS, @truncate(BG1HOFS_copy.*));
    zelda_ppu_write(BG1HOFS, @truncate(BG1HOFS_copy.* >> 8));
    zelda_ppu_write(BG1VOFS, @truncate(BG1VOFS_copy.*));
    zelda_ppu_write(BG1VOFS, @truncate(BG1VOFS_copy.* >> 8));
    zelda_ppu_write(BG2HOFS, @truncate(BG2HOFS_copy.*));
    zelda_ppu_write(BG2HOFS, @truncate(BG2HOFS_copy.* >> 8));
    zelda_ppu_write(BG2VOFS, @truncate(BG2VOFS_copy.*));
    zelda_ppu_write(BG2VOFS, @truncate(BG2VOFS_copy.* >> 8));
    zelda_ppu_write(BG3HOFS, @truncate(BG3HOFS_copy2.*));
    zelda_ppu_write(BG3HOFS, @truncate(BG3HOFS_copy2.* >> 8));
    zelda_ppu_write(BG3VOFS, @truncate(BG3VOFS_copy2.*));
    zelda_ppu_write(BG3VOFS, @truncate(BG3VOFS_copy2.* >> 8));
    zelda_ppu_write(INIDISP, INIDISP_copy.*);
    zelda_ppu_write(MOSAIC, MOSAIC_copy.*);
    zelda_ppu_write(BGMODE, BGMODE_copy.*);
    if ((BGMODE_copy.* & 7) == 7) {
        zelda_ppu_write(M7B, 0);
        zelda_ppu_write(M7B, 0);
        zelda_ppu_write(M7C, 0);
        zelda_ppu_write(M7C, 0);
        zelda_ppu_write(M7X, @truncate(M7X_copy.*));
        zelda_ppu_write(M7X, @truncate(M7X_copy.* >> 8));
        zelda_ppu_write(M7Y, @truncate(M7Y_copy.*));
        zelda_ppu_write(M7Y, @truncate(M7Y_copy.* >> 8));
    }
    zelda_ppu_write(BG12NBA, 0x22);
    zelda_ppu_write(BG34NBA, 7);
}

fn Interrupt_NMI_AudioParts_Locked() void {
    if (music_control.* == 0) {
        // Zelda causes unwanted music change when going in a portal.
        // last_music_control doesn't hold the song but the last applied effect.
    } else if (!ZeldaIsPlayingMusicTrackWithBug(music_control.*)) {
        last_music_control.* = music_control.*;
        ZeldaPlayMsuAudioTrack(music_control.*);
        if (music_control.* < 0xf2)
            music_unk1.* = music_control.*;
        music_control.* = 0;
    }

    if (sound_effect_ambient.* == 0) {
        if (zelda_apu_read(APUI01) == sound_effect_ambient_last.*)
            zelda_apu_write(APUI01, 0);
    } else {
        sound_effect_ambient_last.* = sound_effect_ambient.*;
        zelda_apu_write(APUI01, sound_effect_ambient.*);
        sound_effect_ambient.* = 0;
    }
    zelda_apu_write(APUI02, sound_effect_1.*);
    zelda_apu_write(APUI03, sound_effect_2.*);
    sound_effect_1.* = 0;
    sound_effect_2.* = 0;
}

pub export fn Interrupt_NMI(joypad_input: u16) callconv(.c) void { // 8080c9
    Interrupt_NMI_AudioParts_Locked();

    if (nmi_boolean.* == 0) {
        nmi_boolean.* = 1;
        NMI_DoUpdates();
        NMI_ReadJoypads(joypad_input);
    }

    if (is_nmi_thread_active.* != 0) {
        NMI_UpdateIRQGFX();
        thread_other_stack.* = if (thread_other_stack.* != 0x1f31) 0x1f31 else 0x1f2;
    }
    WritePpuRegisters();
}

pub export fn NMI_ReadJoypads(joypad_input: u16) callconv(.c) void { // 8083d1
    var both = joypad_input;
    var reversed: u16 = 0;
    for (0..16) |_| {
        reversed = reversed *% 2 +% (both & 1);
        both >>= 1;
    }
    const r0: u8 = @truncate(reversed);
    const r1: u8 = @truncate(reversed >> 8);

    joypad1L_last.* = r0;
    filtered_joypad_L.* = (r0 ^ joypad1L_last2.*) & r0;
    joypad1L_last2.* = r0;

    joypad1H_last.* = r1;
    filtered_joypad_H.* = (r1 ^ joypad1H_last2.*) & r1;
    joypad1H_last2.* = r1;
}

pub export fn NMI_DoUpdates() callconv(.c) void { // 8089e0
    if (nmi_disable_core_updates.* == 0) {
        const link = kLinkGraphics();
        CopyToVram(0x4100, link + (dma_source_addr_0.* - 0x8000), 0x40);
        CopyToVram(0x4120, link + (dma_source_addr_1.* - 0x8000), 0x40);
        CopyToVram(0x4140, link + (dma_source_addr_2.* - 0x8000), 0x20);

        CopyToVram(0x4000, link + (dma_source_addr_3.* - 0x8000), 0x40);
        CopyToVram(0x4020, link + (dma_source_addr_4.* - 0x8000), 0x40);
        CopyToVram(0x4040, link + (dma_source_addr_5.* - 0x8000), 0x20);

        CopyToVram(0x4050, g_ram[dma_source_addr_6.*..].ptr, 0x40);
        CopyToVram(0x4070, g_ram[dma_source_addr_7.*..].ptr, 0x40);
        CopyToVram(0x4090, g_ram[dma_source_addr_8.*..].ptr, 0x40);
        CopyToVram(0x40b0, g_ram[dma_source_addr_9.*..].ptr, 0x20);
        CopyToVram(0x40c0, g_ram[dma_source_addr_10.*..].ptr, 0x40);
        CopyToVram(0x4150, g_ram[dma_source_addr_11.*..].ptr, 0x40);
        CopyToVram(0x4170, g_ram[dma_source_addr_12.*..].ptr, 0x40);
        CopyToVram(0x4190, g_ram[dma_source_addr_13.*..].ptr, 0x40);
        CopyToVram(0x41b0, g_ram[dma_source_addr_14.*..].ptr, 0x20);
        CopyToVram(0x41c0, g_ram[dma_source_addr_15.*..].ptr, 0x40);
        CopyToVram(0x4200, g_ram[dma_source_addr_16.*..].ptr, 0x40);
        CopyToVram(0x4220, g_ram[dma_source_addr_17.*..].ptr, 0x40);
        CopyToVram(0x4240, g_ram[0xbd40..].ptr, 0x40);
        CopyToVram(0x4300, g_ram[dma_source_addr_18.*..].ptr, 0x40);
        CopyToVram(0x4320, g_ram[dma_source_addr_19.*..].ptr, 0x40);
        CopyToVram(0x4340, g_ram[0xbd80..].ptr, 0x40);

        if (loByte(flag_travel_bird).* != 0) {
            CopyToVram(0x40e0, g_ram[dma_source_addr_20.*..].ptr, 0x40);
            CopyToVram(0x41e0, g_ram[dma_source_addr_21.*..].ptr, 0x40);
        }

        CopyToVram(animated_tile_vram_addr.*, g_ram[animated_tile_data_src.*..].ptr, 0x400);
    }

    if (flag_update_hud_in_nmi.* != 0) {
        CopyToVram(word_7E0219.*, @ptrCast(hud_tile_indices_buffer), 165 * @sizeOf(u16));
    }

    if (flag_update_cgram_in_nmi.* != 0) {
        const dst: [*]u8 = @ptrCast(&ppu().cgram);
        @memcpy(dst[0..0x200], @as([*]const u8, @ptrCast(main_palette_buffer))[0..0x200]);
    }

    flag_update_hud_in_nmi.* = 0;
    flag_update_cgram_in_nmi.* = 0;

    const oam_dst: [*]u8 = @ptrCast(&ppu().oam);
    @memcpy(oam_dst[0..0x220], g_ram[0x800..][0..0x220]);

    if (nmi_load_bg_from_vram.* != 0) {
        const p: [*]const u8 = switch (nmi_load_bg_from_vram.*) {
            1 => g_ram[0x1002..].ptr,
            2 => g_ram[0x1000..].ptr,
            3 => kBgTilemap(0),
            4 => g_ram[0x21b..].ptr,
            5 => kBgTilemap(1),
            6 => kBgTilemap(2),
            7 => kBgTilemap(3),
            8 => kBgTilemap(4),
            9 => kBgTilemap(5),
            else => unreachable,
        };
        HandleStripes14(p);
        if (nmi_load_bg_from_vram.* == 1)
            vram_upload_offset.* = 0;
        nmi_load_bg_from_vram.* = 0;
    }

    if (nmi_update_tilemap_dst.* != 0) {
        CopyToVram(@as(u32, nmi_update_tilemap_dst.*) * 256, g_ram[0x10000 + @as(u32, nmi_update_tilemap_src.*)..].ptr, 0x200);
        nmi_update_tilemap_dst.* = 0;
    }

    if (nmi_copy_packets_flag.* != 0) {
        var p: [*]u8 = @ptrCast(&uvram.data);
        while (true) {
            const dst = readWord(p);
            const vmain = p[2];
            const len: usize = p[3];
            p += 4;
            if (vmain == 0x80) {
                // plain copy
                CopyToVram(dst, p, len);
            } else if (vmain == 0x81) {
                // copy with other increment
                std.debug.assert((len & 1) == 0);
                var dp: [*]u16 = @ptrCast(&g_zenv.vram.?[dst]);
                var i: usize = 0;
                while (i < len) : ({
                    i += 2;
                    dp += 32;
                }) {
                    dp[0] = readWord(p + i);
                }
            } else {
                unreachable;
            }
            p += len;
            if (readWord(p) == 0xffff) break;
        }
        nmi_copy_packets_flag.* = 0;
        nmi_disable_core_updates.* = 0;
    }

    const idx = nmi_subroutine_index.*;
    nmi_subroutine_index.* = 0;
    kNmiSubroutines[idx]();
}

pub export fn NMI_UploadTilemap() callconv(.c) void { // 808cb0
    CopyToVram(@as(u32, kNmiVramAddrs[loByte(nmi_load_target_addr).*]) << 8, g_ram[0x1000..].ptr, 0x800);

    wordPtr(g_ram[0x1000..].ptr).* = 0;
    nmi_disable_core_updates.* = 0;
}

pub export fn NMI_UploadTilemap_doNothing() callconv(.c) void {} // 808ce3

pub export fn NMI_UploadBG3Text() callconv(.c) void { // 808ce4
    CopyToVram(0x7c00, g_ram[0x10000..].ptr, 0x7e0);
    nmi_disable_core_updates.* = 0;
}

pub export fn NMI_UpdateOWScroll() callconv(.c) void { // 808d13
    var src: [*]u8 = @ptrCast(&uvram.data);
    const f = readWord(src);
    const step: usize = if (f & 0x8000 != 0) 32 else 1;
    const len: usize = f & 0x3fff;
    src += 2;
    while (true) {
        var dst: [*]u16 = @ptrCast(&g_zenv.vram.?[readWord(src)]);
        src += 2;
        var i: usize = 0;
        const i_end = len >> 1;
        while (i < i_end) : ({
            i += 1;
            dst += step;
            src += 2;
        }) {
            dst[0] = readWord(src);
        }
        if (src[1] & 0x80 != 0) break;
    }
    nmi_disable_core_updates.* = 0;
}

pub export fn NMI_UpdateSubscreenOverlay() callconv(.c) void { // 808d62
    NMI_HandleArbitraryTileMap(g_ram[0x12000..].ptr, 0, 0x80);
}

pub export fn NMI_HandleArbitraryTileMap(src_in: [*]const u8, i_in: c_int, i_end: c_int) callconv(.c) void { // 808dae
    const r10: [*]align(1) u16 = @ptrCast(word_7F4000);
    var src = src_in;
    var i = i_in;
    while (true) {
        CopyToVram(r10[@intCast(i >> 1)], src, 0x80);
        src += 0x80;
        i += 2;
        if (i == i_end) break;
    }
    nmi_disable_core_updates.* = 0;
}

pub export fn NMI_UpdateBG1Wall() callconv(.c) void { // 808e09
    // Secret Wall Right
    CopyToVramVertical(nmi_load_target_addr.*, g_ram[0xc880..].ptr, 0x40);
    CopyToVramVertical(@as(u32, nmi_load_target_addr.*) + 0x800, g_ram[0xc8c0..].ptr, 0x40);
}

pub export fn NMI_TileMapNothing() callconv(.c) void {} // 808e4b

pub export fn NMI_UpdateLoadLightWorldMap() callconv(.c) void { // 808e54
    const kLightWorldTileMapDsts = [4]u16{ 0, 0x20, 0x1000, 0x1020 };
    var src = GetLightOverworldTilemap();
    for (0..4) |j| {
        var t: u32 = kLightWorldTileMapDsts[j];
        var i: u32 = 0x20;
        while (i != 0) : (i -= 1) {
            CopyToVramLow(src, t, 0x20);
            src += 32;
            t += 0x80;
        }
    }
}

pub export fn NMI_UpdateBG2Left() callconv(.c) void { // 808ea9
    CopyToVram(0, g_ram[0x10000..].ptr, 0x800);
    CopyToVram(0x800, g_ram[0x10800..].ptr, 0x800);
}

pub export fn NMI_UpdateBGChar3and4() callconv(.c) void { // 808ee7
    CopyToVram(0x2c00, g_ram[0x10000..].ptr, 0x1000);
    nmi_disable_core_updates.* = 0;
}

pub export fn NMI_UpdateBGChar5and6() callconv(.c) void { // 808f16
    CopyToVram(0x3400, g_ram[0x11000..].ptr, 0x1000);
    nmi_disable_core_updates.* = 0;
}

pub export fn NMI_UpdateBGCharHalf() callconv(.c) void { // 808f45
    CopyToVram(@as(u32, loByte(nmi_load_target_addr).*) * 256, g_ram[0x11000..].ptr, 0x400);
}

pub export fn NMI_UpdateBGChar0() callconv(.c) void { // 808f72
    NMI_RunTileMapUpdateDMA(0x2000);
}

pub export fn NMI_UpdateBGChar1() callconv(.c) void { // 808f79
    NMI_RunTileMapUpdateDMA(0x2800);
}

pub export fn NMI_UpdateBGChar2() callconv(.c) void { // 808f80
    NMI_RunTileMapUpdateDMA(0x3000);
}

pub export fn NMI_UpdateBGChar3() callconv(.c) void { // 808f87
    NMI_RunTileMapUpdateDMA(0x3800);
}

pub export fn NMI_UpdateObjChar0() callconv(.c) void { // 808f8e
    CopyToVram(0x4400, g_ram[0x10000..].ptr, 0x800);
    nmi_disable_core_updates.* = 0;
}

pub export fn NMI_UpdateObjChar2() callconv(.c) void { // 808fbd
    NMI_RunTileMapUpdateDMA(0x5000);
}

pub export fn NMI_UpdateObjChar3() callconv(.c) void { // 808fc4
    NMI_RunTileMapUpdateDMA(0x5800);
}

pub export fn NMI_RunTileMapUpdateDMA(dst: c_int) callconv(.c) void { // 808fc9
    CopyToVram(@intCast(dst), g_ram[0x10000..].ptr, 0x1000);
    nmi_disable_core_updates.* = 0;
}

pub export fn NMI_UploadDarkWorldMap() callconv(.c) void { // 808ff3
    var src: [*]const u8 = g_ram[0x1000..].ptr;
    var t: u32 = 0x810;
    var i: u32 = 0x20;
    while (i != 0) : (i -= 1) {
        CopyToVramLow(src, t, 0x20);
        src += 32;
        t += 0x80;
    }
}

pub export fn NMI_UploadGameOverText() callconv(.c) void { // 809038
    CopyToVram(0x7800, g_ram[0x2000..].ptr, 0x800);
    CopyToVram(0x7d00, g_ram[0x3400..].ptr, 0x600);
}

pub export fn NMI_UpdatePegTiles() callconv(.c) void { // 80908b
    CopyToVram(0x3d00, g_ram[0x10000..].ptr, 0x100);
}

pub export fn NMI_UpdateStarTiles() callconv(.c) void { // 8090b7
    CopyToVram(0x3ed0, g_ram[0x10000..].ptr, 0x40);
}

pub export fn HandleStripes14(p_in: [*]const u8) callconv(.c) void { // 8092a1
    var p = p_in;
    while (!(p[0] & 0x80 != 0)) {
        const vmem_addr = swap16(readWord(p));
        const vram_incr_amount = (p[2] & 0x80) >> 7;
        // Cpu BUS Address Step (0=Increment, 2=Decrement, 1/3=Fixed) (DMA only)
        const is_memset = p[2] & 0x40;
        var len: usize = (swap16(readWord(p + 2)) & 0x3fff) + 1;
        p += 4;

        if (vram_incr_amount == 0) {
            const dst: [*]u16 = @ptrCast(&g_zenv.vram.?[vmem_addr]);
            if (is_memset != 0) {
                const v: u16 = @as(u16, p[0]) | (@as(u16, p[1]) << 8);
                len = (len + 1) >> 1;
                for (0..len) |i| dst[i] = v;
                p += 2;
            } else {
                const bytes: [*]u8 = @ptrCast(dst);
                @memcpy(bytes[0..len], p[0..len]);
                p += len;
            }
        } else {
            // increment vram by 32 instead of 1
            var dst: [*]u16 = @ptrCast(&g_zenv.vram.?[vmem_addr]);
            if (is_memset != 0) {
                const v: u16 = @as(u16, p[0]) | (@as(u16, p[1]) << 8);
                len = (len + 1) >> 1;
                var i: usize = 0;
                while (i < len) : ({
                    i += 1;
                    dst += 32;
                }) {
                    dst[0] = v;
                }
                p += 2;
            } else {
                std.debug.assert((len & 1) == 0);
                len >>= 1;
                var i: usize = 0;
                while (i < len) : ({
                    i += 1;
                    dst += 32;
                    p += 2;
                }) {
                    dst[0] = readWord(p);
                }
            }
        }
    }
}

pub export fn NMI_UpdateIRQGFX() callconv(.c) void { // 809347
    if (nmi_flag_update_polyhedral.* != 0) {
        CopyToVram(0x5800, g_ram[0xe800..].ptr, 0x800);
        nmi_flag_update_polyhedral.* = 0;
    }
}

const testing = std.testing;

/// The vram updates need somewhere to write; point g_zenv at a scratch buffer.
const TestVram = struct {
    vram: *[0x8000]u16,

    fn init() !TestVram {
        const vram = try testing.allocator.create([0x8000]u16);
        @memset(vram, 0);
        g_zenv.vram = vram;
        @memset(g_ram[0..0x20000], 0);
        return .{ .vram = vram };
    }

    fn deinit(self: TestVram) void {
        g_zenv.vram = null;
        testing.allocator.destroy(self.vram);
    }
};

test "joypad bits are reversed and edge triggered" {
    @memset(g_ram[0..0x200], 0);
    // Bit 0 of the input ends up as bit 15 of the reversed value.
    NMI_ReadJoypads(0x0001);
    try testing.expectEqual(@as(u8, 0x80), joypad1H_last.*);
    try testing.expectEqual(@as(u8, 0x00), joypad1L_last.*);
    // First press: the filtered value reports the new edge.
    try testing.expectEqual(@as(u8, 0x80), filtered_joypad_H.*);

    // Held down: the edge is gone the second time round.
    NMI_ReadJoypads(0x0001);
    try testing.expectEqual(@as(u8, 0x80), joypad1H_last.*);
    try testing.expectEqual(@as(u8, 0x00), filtered_joypad_H.*);

    // Released then pressed again: the edge comes back.
    NMI_ReadJoypads(0x0000);
    try testing.expectEqual(@as(u8, 0x00), filtered_joypad_H.*);
    NMI_ReadJoypads(0x0001);
    try testing.expectEqual(@as(u8, 0x80), filtered_joypad_H.*);
}

test "the low half of the reversed joypad word" {
    @memset(g_ram[0..0x200], 0);
    // Bit 15 of the input becomes bit 0, which lands in the low byte.
    NMI_ReadJoypads(0x8000);
    try testing.expectEqual(@as(u8, 0x01), joypad1L_last.*);
    try testing.expectEqual(@as(u8, 0x00), joypad1H_last.*);
}

test "a plain vram copy moves bytes at a word address" {
    const t = try TestVram.init();
    defer t.deinit();

    g_ram[0x10000] = 0x11;
    g_ram[0x10001] = 0x22;
    g_ram[0x10002] = 0x33;
    NMI_UpdatePegTiles(); // copies 0x100 bytes from $10000 to vram word 0x3d00

    try testing.expectEqual(@as(u16, 0x2211), t.vram[0x3d00]);
    try testing.expectEqual(@as(u8, 0x33), @as([*]const u8, @ptrCast(t.vram))[0x3d00 * 2 + 2]);
    try testing.expectEqual(@as(u8, 0), nmi_disable_core_updates.*);
}

test "the vertical copy strides 32 words at a time" {
    const t = try TestVram.init();
    defer t.deinit();

    for (0..8) |i| {
        g_ram[0xc880 + i * 2] = @intCast(i + 1);
        g_ram[0xc880 + i * 2 + 1] = 0;
    }
    nmi_load_target_addr.* = 0x100;
    NMI_UpdateBG1Wall();

    // Four of the eight words land 32 apart from the base.
    try testing.expectEqual(@as(u16, 1), t.vram[0x100]);
    try testing.expectEqual(@as(u16, 2), t.vram[0x100 + 32]);
    try testing.expectEqual(@as(u16, 3), t.vram[0x100 + 64]);
    // The second half goes to base + 0x800.
    try testing.expectEqual(@as(u16, 0), t.vram[0x101]); // untouched between strides
}

test "the low-byte copy leaves the high byte alone" {
    const t = try TestVram.init();
    defer t.deinit();

    for (0..0x20) |i| t.vram[0x810 + i] = 0xff00;
    for (0..0x20) |i| g_ram[0x1000 + i] = @intCast(i);
    NMI_UploadDarkWorldMap();

    try testing.expectEqual(@as(u16, 0xff00), t.vram[0x810]);
    try testing.expectEqual(@as(u16, 0xff01), t.vram[0x811]);
    try testing.expectEqual(@as(u16, 0xff1f), t.vram[0x810 + 0x1f]);
}

test "HandleStripes14 copies a plain stripe" {
    const t = try TestVram.init();
    defer t.deinit();

    // Header is big endian: address $0040, then a length of 4 bytes.
    var buf = [_]u8{
        0x00, 0x40, // vram word address 0x0040
        0x00, 0x03, // increment by 1, copy, length 3+1 = 4
        0xaa, 0xbb, 0xcc, 0xdd,
        0x80, // terminator
    };
    HandleStripes14(&buf);
    try testing.expectEqual(@as(u16, 0xbbaa), t.vram[0x40]);
    try testing.expectEqual(@as(u16, 0xddcc), t.vram[0x41]);
}

test "HandleStripes14 fills when the memset bit is set" {
    const t = try TestVram.init();
    defer t.deinit();

    var buf = [_]u8{
        0x00, 0x10, // vram word address 0x0010
        0x40, 0x07, // memset, length 7+1 = 8 bytes -> 4 words
        0x34, 0x12, // the fill value
        0x80,
    };
    HandleStripes14(&buf);
    for (0..4) |i|
        try testing.expectEqual(@as(u16, 0x1234), t.vram[0x10 + i]);
    try testing.expectEqual(@as(u16, 0), t.vram[0x14]);
}

test "HandleStripes14 strides by 32 when the increment bit is set" {
    const t = try TestVram.init();
    defer t.deinit();

    var buf = [_]u8{
        0x00, 0x20, // vram word address 0x0020
        0xc0, 0x03, // increment by 32 and memset, 4 bytes -> 2 words
        0x99, 0x88,
        0x80,
    };
    HandleStripes14(&buf);
    try testing.expectEqual(@as(u16, 0x8899), t.vram[0x20]);
    try testing.expectEqual(@as(u16, 0x8899), t.vram[0x20 + 32]);
    try testing.expectEqual(@as(u16, 0), t.vram[0x21]);
}

test "the polyhedral buffer is only pushed when flagged" {
    const t = try TestVram.init();
    defer t.deinit();

    g_ram[0xe800] = 0x77;
    nmi_flag_update_polyhedral.* = 0;
    NMI_UpdateIRQGFX();
    try testing.expectEqual(@as(u16, 0), t.vram[0x5800]);

    nmi_flag_update_polyhedral.* = 1;
    NMI_UpdateIRQGFX();
    try testing.expectEqual(@as(u16, 0x77), t.vram[0x5800]);
    try testing.expectEqual(@as(u8, 0), nmi_flag_update_polyhedral.*); // cleared
}

test "NMI_UploadTilemap picks its destination from the address table" {
    const t = try TestVram.init();
    defer t.deinit();

    g_ram[0x1000] = 0xab;
    g_ram[0x1001] = 0xcd;
    loByte(nmi_load_target_addr).* = 2; // kNmiVramAddrs[2] == 4
    NMI_UploadTilemap();

    try testing.expectEqual(@as(u16, 0xcdab), t.vram[4 << 8]);
    // The source word is cleared afterwards.
    try testing.expectEqual(@as(u16, 0), @as(*align(1) u16, @ptrCast(g_ram[0x1000..].ptr)).*);
    try testing.expectEqual(@as(u8, 0), nmi_disable_core_updates.*);
}

test "the nmi tables came over intact" {
    try testing.expectEqual(35, kNmiVramAddrs.len);
    try testing.expectEqual(@as(u8, 0), kNmiVramAddrs[0]);
    try testing.expectEqual(@as(u8, 12), kNmiVramAddrs[4]);
    try testing.expectEqual(@as(u8, 96), kNmiVramAddrs[33]);
    try testing.expectEqual(@as(u8, 104), kNmiVramAddrs[34]);
    try testing.expectEqual(25, kNmiSubroutines.len);
    // Index 0 and 6 are both no-ops, but distinct functions.
    try testing.expectEqual(kNmiSubroutines[0], @as(*const PlayerHandlerFunc, &NMI_UploadTilemap_doNothing));
    try testing.expectEqual(kNmiSubroutines[6], @as(*const PlayerHandlerFunc, &NMI_TileMapNothing));
}
