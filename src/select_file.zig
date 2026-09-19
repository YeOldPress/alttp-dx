//! Port of src/select_file.c: the file select, copy, erase and naming screens.
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl_types.zig");

const OamEnt = vars.OamEnt;
const g_ram = &vars.g_ram;
const g_zenv = &rtl.g_zenv;

// load_gfx.h
const kSrmOffs_Sword = 0x359;
const kSrmOffs_Shield = 0x35a;
const kSrmOffs_DiedCounter = 0x405;
const kSrmOffs_Name = 0x3d9;
const kSrmOffs_Health = 0x36c;

// Still in C: load_gfx.c, overworld.c, messaging.c, misc.c and zelda_rtl.c.
extern fn Decomp_spr(dst: [*]u8, gfx: c_int) c_int;
extern fn Do3To4High(vram_ptr: [*]u16, decomp_addr: [*]const u8) void;
extern fn TransferFontToVRAM() void;
extern fn LoadDefaultGraphics() void;
extern fn InitializeTilesets() void;
extern fn DecompressEnemyDamageSubclasses() void;
extern fn EnableForceBlank() void;
extern fn EraseTileMaps_triforce() void;
extern fn CopySaveToWRAM() void;
extern fn Palette_Load_DungeonSet() void;
extern fn Palette_Load_OWBG3() void;
extern fn Palette_Load_HUD() void;
extern fn Palette_LoadForFileSelect() void;
extern fn ZeldaWriteSram() void;

const oam_buf = vars.oam_buf;
const bytewise_extended_oam = vars.bytewise_extended_oam;
const vram_upload_data = vars.vram_upload_data;
const vram_upload_offset = vars.vram_upload_offset;
const selectfile_arr1 = vars.selectfile_arr1;
const selectfile_arr2 = vars.selectfile_arr2;
const selectfile_var2 = vars.selectfile_var2;
const selectfile_var3 = vars.selectfile_var3;
const selectfile_var4 = vars.selectfile_var4;
const selectfile_var5 = vars.selectfile_var5;
const selectfile_var6 = vars.selectfile_var6;
const selectfile_var7 = vars.selectfile_var7;
const selectfile_var8 = vars.selectfile_var8;
const selectfile_var9 = vars.selectfile_var9;
const selectfile_var10 = vars.selectfile_var10;
const selectfile_var11 = vars.selectfile_var11;
const link_dma_graphics_index = vars.link_dma_graphics_index;
const filtered_joypad_L = vars.filtered_joypad_L;
const filtered_joypad_H = vars.filtered_joypad_H;
const joypad1H_last = vars.joypad1H_last;
const sound_effect_1 = vars.sound_effect_1;
const sound_effect_2 = vars.sound_effect_2;
const music_control = vars.music_control;
const main_module_index = vars.main_module_index;
const submodule_index = vars.submodule_index;
const subsubmodule_index = vars.subsubmodule_index;
const frame_counter = vars.frame_counter;
const nmi_load_bg_from_vram = vars.nmi_load_bg_from_vram;
const nmi_disable_core_updates = vars.nmi_disable_core_updates;
const nmi_flag_update_polyhedral = vars.nmi_flag_update_polyhedral;
const flag_update_cgram_in_nmi = vars.flag_update_cgram_in_nmi;
const is_nmi_thread_active = vars.is_nmi_thread_active;
const INIDISP_copy = vars.INIDISP_copy;
const BG3HOFS_copy2 = vars.BG3HOFS_copy2;
const BG3VOFS_copy2 = vars.BG3VOFS_copy2;
const overworld_palette_aux_or_main = vars.overworld_palette_aux_or_main;
const palette_main_indoors = vars.palette_main_indoors;
const hud_palette = vars.hud_palette;
const hud_cur_item = vars.hud_cur_item;
const misc_sprites_graphics_index = vars.misc_sprites_graphics_index;
const main_tile_theme_index = vars.main_tile_theme_index;
const aux_tile_theme_index = vars.aux_tile_theme_index;
const attract_legend_ctr = vars.attract_legend_ctr;
const irq_flag = vars.irq_flag;

// select_file.c keeps four scratch values in direct page under its own names.
const selectfile_R16: *u8 = &g_ram[0xc8];
const selectfile_R17: *u8 = &g_ram[0xc9];
const selectfile_R18: *align(1) u16 = @ptrCast(&g_ram[0xca]);
const selectfile_R20: *align(1) u16 = @ptrCast(&g_ram[0xcc]);

/// variables.h keeps this one in sram rather than work ram, so it has to be
/// resolved through g_zenv at run time.
fn srm_var1() *align(1) u16 {
    return @ptrCast(&g_zenv.sram.?[0x1ffe]);
}

fn sram() [*]u8 {
    return g_zenv.sram.?;
}

fn sign8(v: u8) bool {
    return v & 0x80 != 0;
}

fn swap16(v: u16) u16 {
    return (v << 8) | (v >> 8);
}

fn readWord(p: [*]const u8) u16 {
    return std.mem.readInt(u16, p[0..2], .little);
}

fn writeWord(p: [*]u8, v: u16) void {
    std.mem.writeInt(u16, p[0..2], v, .little);
}

/// sprite.h, a static inline with no linkable symbol.
fn SetOamPlain(oam: [*]align(1) OamEnt, x: u8, y: u8, charnum: u8, flags: u8, big: u8) void {
    oam[0].x = x;
    oam[0].y = y;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    const index = (@intFromPtr(oam) - @intFromPtr(oam_buf)) / @sizeOf(OamEnt);
    bytewise_extended_oam[index] = big;
}

const kSelectFile_Draw_Y = [3]u8{ 0x43, 0x63, 0x83 };

pub export fn Intro_CheckCksum(s: [*]const u8) callconv(.c) bool {
    var sum: u16 = 0;
    for (0..0x280) |i|
        sum +%= readWord(s + i * 2);
    return sum == 0x5a5a;
}

pub export fn SelectFile_Func1() callconv(.c) [*]align(1) u16 {
    const kSelectFile_Func1_Tab = [4]u16{ 0x3581, 0x3582, 0x3591, 0x3592 };
    var dst: [*]align(1) u16 = @ptrCast(&g_ram[0x1002]);
    dst[0] = 0x10;
    dst += 1;
    dst[0] = 0xff07;
    dst += 1;
    for (0..1024) |i| {
        dst[0] = kSelectFile_Func1_Tab[((i & 0x20) >> 4) + (i & 1)];
        dst += 1;
    }
    return dst;
}

pub export fn SelectFile_Func5_DrawOams(k: c_int) callconv(.c) void {
    const kSelectFile_Draw_OamIdx = [3]u8{ 0x28, 0x3c, 0x50 };
    const kSelectFile_Draw_SwordChar = [4]u8{ 0x85, 0xa1, 0xa1, 0xa1 };
    const kSelectFile_Draw_ShieldChar = [3]u8{ 0xc4, 0xca, 0xe0 };
    const kSelectFile_Draw_Flags = [3]u8{ 0x72, 0x76, 0x7a };
    const kSelectFile_Draw_Flags2 = [3]u8{ 0x32, 0x36, 0x3a };
    const kSelectFile_Draw_Flags3 = [3]u8{ 0x30, 0x34, 0x38 };
    const i: usize = @intCast(k);

    link_dma_graphics_index.* = 0x116 * 2;
    const srm = sram() + 0x500 * i;

    const oam = oam_buf + kSelectFile_Draw_OamIdx[i] / 4;
    const x: u8 = 0x34;
    const y: u8 = kSelectFile_Draw_Y[i];

    const sword = srm[kSrmOffs_Sword] -% 1;
    const swordchar = kSelectFile_Draw_SwordChar[if (sign8(sword)) 0 else sword];
    SetOamPlain(oam + 0, x +% 0xc, y -% 5, swordchar, kSelectFile_Draw_Flags[i], 0);
    SetOamPlain(oam + 1, x +% 0xc, y +% 3, swordchar +% 16, kSelectFile_Draw_Flags[i], 0);
    if (sign8(sword)) {
        oam[0].y = 0xf0;
        oam[1].y = 0xf0;
    }
    const shield = srm[kSrmOffs_Shield] -% 1;
    SetOamPlain(
        oam + 2,
        x -% 5,
        y +% 10,
        kSelectFile_Draw_ShieldChar[if (sign8(shield)) 0 else shield],
        kSelectFile_Draw_Flags2[i],
        2,
    );
    if (sign8(shield))
        oam[2].y = 0xf0;
    SetOamPlain(oam + 3, x, y +% 0, 0, kSelectFile_Draw_Flags3[i], 2);
    SetOamPlain(oam + 4, x, y +% 8, 2, kSelectFile_Draw_Flags3[i] | 0x40, 2);
}

pub export fn SelectFile_Func6_DrawOams2(k: c_int) callconv(.c) void {
    const kSelectFile_DrawDigit_Char = [10]u8{ 0xd0, 0xac, 0xad, 0xbc, 0xbd, 0xae, 0xaf, 0xbe, 0xbf, 0xc0 };
    const kSelectFile_DrawDigit_OamIdx = [3]i8{ 4, 16, 28 };
    const kSelectFile_DrawDigit_X = [3]i8{ 12, 4, -4 };
    const idx: usize = @intCast(k);

    const srm = sram() + 0x500 * idx;
    const x: u8 = 0x34;
    const y: u8 = kSelectFile_Draw_Y[idx];

    var died_ctr: u32 = readWord(srm + kSrmOffs_DiedCounter);
    if (died_ctr == 0xffff)
        return;

    if (died_ctr > 999)
        died_ctr = 999;

    var digits: [3]u8 = undefined;
    digits[2] = @intCast(died_ctr / 100);
    died_ctr %= 100;
    digits[1] = @intCast(died_ctr / 10);
    digits[0] = @intCast(died_ctr % 10);

    var i: i32 = if (digits[2] != 0) 2 else if (digits[1] != 0) 1 else 0;
    var oam = oam_buf + @as(usize, @intCast(kSelectFile_DrawDigit_OamIdx[idx])) / 4;
    while (true) {
        SetOamPlain(
            oam,
            x +% @as(u8, @bitCast(kSelectFile_DrawDigit_X[@intCast(i)])),
            y +% 0x10,
            kSelectFile_DrawDigit_Char[digits[@intCast(i)]],
            0x3c,
            0,
        );
        oam += 1;
        i -= 1;
        if (i < 0) break;
    }
}

pub export fn SelectFile_Func17(k: c_int) callconv(.c) void {
    const kSelectFile_DrawName_VramOffs = [3]u16{ 8, 0x5c, 0xb0 };
    const kSelectFile_DrawName_HealthVramOffs = [3]u16{ 0x16, 0x6a, 0xbe };
    const idx: usize = @intCast(k);
    const srm = sram() + 0x500 * idx;
    var name = srm + kSrmOffs_Name;
    var dst = vram_upload_data + kSelectFile_DrawName_VramOffs[idx] / 2;
    var i: i32 = 5;
    while (i >= 0) : (i -= 1) {
        const t = readWord(name) +% 0x1800;
        name += 2;
        dst[0] = t;
        dst[21] = t +% 0x10;
        dst += 1;
    }
    var health: i32 = srm[kSrmOffs_Health] >> 3;
    dst = vram_upload_data + kSelectFile_DrawName_HealthVramOffs[idx] / 2;
    const dst_org = dst;
    var row: i32 = 10;
    while (true) {
        dst[0] = 0x520;
        dst += 1;
        row -= 1;
        if (row == 0)
            dst = dst_org + 21;
        health -= 1;
        if (health == 0) break;
    }
}

pub export fn SelectFile_Func16() callconv(.c) void {
    const kSelectFile_Func16_FaerieY = [2]u8{ 175, 191 };
    FileSelect_DrawFairy(0x1c, kSelectFile_Func16_FaerieY[selectfile_R16.*]);

    var k: i32 = selectfile_R16.*;
    if (filtered_joypad_H.* & 0x2c != 0) {
        k += if (filtered_joypad_H.* & 0x24 != 0) 1 else -1;
        selectfile_R16.* = @intCast(k & 1);
        sound_effect_2.* = 0x20;
    }

    const a = ((filtered_joypad_L.* & 0xc0) | filtered_joypad_H.*) & 0xd0;
    if (a != 0) {
        sound_effect_1.* = 0x2c;
        if (selectfile_R16.* == 0) {
            sound_effect_2.* = 0x22;
            sound_effect_1.* = 0x0;
            const j: usize = subsubmodule_index.*;
            selectfile_arr1[j] = 0;
            @memset((sram() + j * 0x500)[0..0x500], 0);
            @memset((sram() + j * 0x500 + 0xf00)[0..0x500], 0);
            ZeldaWriteSram();
        }
        ReturnToFileSelect();
        subsubmodule_index.* = 0;
    }
}

pub export fn Module_NamePlayer_1() callconv(.c) void {
    const dst = SelectFile_Func1();
    dst[0] = 0xffff;
    nmi_load_bg_from_vram.* = 1;
    submodule_index.* +%= 1;
}

pub export fn Module_NamePlayer_2() callconv(.c) void {
    nmi_load_bg_from_vram.* = 5;
    submodule_index.* +%= 1;
    INIDISP_copy.* = 15;
    nmi_disable_core_updates.* = 0;
}

pub export fn Intro_FixCksum(s: [*]u8) callconv(.c) void {
    var sum: u16 = 0;
    for (0..0x27f) |i|
        sum +%= readWord(s + i * 2);
    writeWord(s + 0x27f * 2, 0x5a5a -% sum);
}

pub export fn LoadFileSelectGraphics() callconv(.c) void { // 80e4e9
    _ = Decomp_spr(g_ram[0x14000..].ptr, 0x5e);
    Do3To4High(@ptrCast(&g_zenv.vram.?[0x5000]), g_ram[0x14000..].ptr);

    _ = Decomp_spr(g_ram[0x14000..].ptr, 0x5f);
    Do3To4High(@ptrCast(&g_zenv.vram.?[0x5400]), g_ram[0x14000..].ptr);

    TransferFontToVRAM();

    _ = Decomp_spr(g_ram[0x14000..].ptr, 0x6b);
    const dst: [*]u8 = @ptrCast(&g_zenv.vram.?[0x7800]);
    @memcpy(dst[0 .. 0x300 * @sizeOf(u16)], g_ram[0x14000..][0 .. 0x300 * @sizeOf(u16)]);
}

pub export fn Intro_ValidateSram() callconv(.c) void { // 828054
    const cart = sram();
    for (0..3) |i| {
        const c = cart + i * 0x500;
        if (!Intro_CheckCksum(c)) {
            if (Intro_CheckCksum(c + 0xf00)) {
                @memcpy(c[0..0x500], (c + 0xf00)[0..0x500]);
            } else {
                @memset(c[0..0x500], 0);
                @memset((c + 0xf00)[0..0x500], 0);
            }
        }
    }
    @memset(g_ram[0xd00..][0 .. 256 * 3], 0);
}

pub export fn Module01_FileSelect() callconv(.c) void { // 8ccd7d
    BG3HOFS_copy2.* = 0;
    BG3VOFS_copy2.* = 0;
    switch (submodule_index.*) {
        0 => Module_SelectFile_0(),
        1 => FileSelect_ReInitSaveFlagsAndEraseTriforce(),
        2 => Module_EraseFile_1(),
        3 => FileSelect_TriggerStripesAndAdvance(),
        4 => FileSelect_TriggerNameStripesAndAdvance(),
        5 => FileSelect_Main(),
        else => {},
    }
}

pub export fn Module_SelectFile_0() callconv(.c) void { // 8ccd9d
    EnableForceBlank();
    is_nmi_thread_active.* = 0;
    nmi_flag_update_polyhedral.* = 0;
    music_control.* = 11;
    submodule_index.* +%= 1;
    overworld_palette_aux_or_main.* = 0x200;
    palette_main_indoors.* = 6;
    nmi_disable_core_updates.* = 6;
    Palette_Load_DungeonSet();
    Palette_Load_OWBG3();
    hud_palette.* = 0;
    Palette_Load_HUD();
    hud_cur_item.* = 0;
    misc_sprites_graphics_index.* = 1;
    main_tile_theme_index.* = 35;
    aux_tile_theme_index.* = 81;
    LoadDefaultGraphics();
    InitializeTilesets();
    LoadFileSelectGraphics();
    Intro_ValidateSram();
    DecompressEnemyDamageSubclasses();
}

pub export fn FileSelect_ReInitSaveFlagsAndEraseTriforce() callconv(.c) void { // 8ccdf2
    @memset(@as([*]u8, @ptrCast(selectfile_arr1))[0..6], 0);
    FileSelect_EraseTriforce();
}

pub export fn FileSelect_EraseTriforce() callconv(.c) void { // 8ccdf9
    nmi_disable_core_updates.* = 128;
    EnableForceBlank();
    EraseTileMaps_triforce();
    Palette_LoadForFileSelect();
    flag_update_cgram_in_nmi.* +%= 1;
    submodule_index.* +%= 1;
}

const kSelectFile_Gfx0 = [224]u8{
    0x10, 0x42, 0,    0x27, 0x89, 0x35, 0x8a, 0x35, 0x8b, 0x35, 0x8c, 0x35, 0x8b, 0x35, 0x8c, 0x35,
    0x8b, 0x35, 0x8c, 0x35, 0x8b, 0x35, 0x8c, 0x35, 0x8b, 0x35, 0x8c, 0x35, 0x8b, 0x35, 0x8c, 0x35,
    0x8b, 0x35, 0x8c, 0x35, 0x8b, 0x35, 0x8c, 0x35, 0x8a, 0x75, 0x89, 0x75, 0x10, 0x62, 0,    3,
    0x99, 0x35, 0x9a, 0x35, 0x10, 0x64, 0x40, 0x1e, 0x7f, 0x34, 0x10, 0x74, 0,    3,    0x9a, 0x75,
    0x99, 0x75, 0x10, 0x82, 0,    3,    0xa9, 0x35, 0xaa, 0x35, 0x10, 0x84, 0x40, 0x1e, 0x7f, 0x34,
    0x10, 0x94, 0,    3,    0xaa, 0x75, 0xa9, 0x75, 0x10, 0xa2, 0,    0x27, 0x9d, 0x35, 0xad, 0x35,
    0x9b, 0x35, 0x9c, 0x35, 0x9b, 0x35, 0x9c, 0x35, 0x9b, 0x35, 0x9c, 0x35, 0x9b, 0x35, 0x9c, 0x35,
    0x9b, 0x35, 0x9c, 0x35, 0x9b, 0x35, 0x9c, 0x35, 0x9b, 0x35, 0x9c, 0x35, 0x9b, 0x35, 0x9c, 0x35,
    0xad, 0x75, 0x9d, 0x75, 0x10, 0xc2, 0,    0x27, 0xab, 0x35, 0xac, 0x35, 0xab, 0x35, 0xac, 0x35,
    0xab, 0x35, 0xac, 0x35, 0xab, 0x35, 0xac, 0x35, 0xab, 0x35, 0xac, 0x35, 0xab, 0x35, 0xac, 0x35,
    0xab, 0x35, 0xac, 0x35, 0xab, 0x35, 0xac, 0x35, 0xab, 0x35, 0xac, 0x35, 0xab, 0x75, 0xac, 0x75,
    0x10, 0xe2, 0,    1,    0x83, 0x35, 0x10, 0xe3, 0x40, 0x32, 0x85, 0x35, 0x10, 0xfd, 0,    1,
    0x84, 0x35, 0x11, 2,    0xc0, 0x22, 0x86, 0x35, 0x11, 0x1d, 0xc0, 0x22, 0x96, 0x35, 0x13, 0x42,
    0,    1,    0x93, 0x35, 0x13, 0x43, 0x40, 0x32, 0x95, 0x35, 0x13, 0x5d, 0,    1,    0x94, 0x35,
};

pub export fn Module_EraseFile_1() callconv(.c) void { // 8cce53
    var dst = SelectFile_Func1();
    @memcpy(@as([*]u8, @ptrCast(dst))[0..224], &kSelectFile_Gfx0);
    dst += 224 / 2;
    var t: u16 = 0x1103;
    var i: i32 = 17;
    while (i >= 0) : (i -= 1) {
        dst[0] = swap16(t);
        dst += 1;
        t +%= 0x20;
        dst[0] = 0x3240;
        dst += 1;
        dst[0] = 0x347f;
        dst += 1;
    }
    @as([*]u8, @ptrCast(dst))[0] = 0xff;
    submodule_index.* +%= 1;
    nmi_load_bg_from_vram.* = 1;
}

pub export fn FileSelect_TriggerStripesAndAdvance() callconv(.c) void { // 8ccea5
    selectfile_R16.* = selectfile_var2.*;
    submodule_index.* +%= 1;
    nmi_load_bg_from_vram.* = 6;
}

const kSelectFile_Func3_Data = [253]u8{
    0x61, 0x29, 0,    0x25, 0xe7, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x61, 0x49, 0,    0x25, 0xf7, 0x18,
    0x91, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0x61, 0xa9, 0,    0x25, 0xe8, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x61, 0xc9,
    0,    0x25, 0xf8, 0x18, 0x91, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x62, 0x29, 0,    0x25, 0xe9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0x62, 0x49, 0,    0x25, 0xf9, 0x18, 0x91, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xff,
};

pub export fn FileSelect_TriggerNameStripesAndAdvance() callconv(.c) void { // 8cceb1
    @memcpy(@as([*]u8, @ptrCast(vram_upload_data))[0..253], &kSelectFile_Func3_Data);
    INIDISP_copy.* = 0xf;
    nmi_disable_core_updates.* = 0;
    submodule_index.* +%= 1;
    nmi_load_bg_from_vram.* = 6;
}

pub export fn FileSelect_Main() callconv(.c) void { // 8ccebd
    const kSelectFile_Faerie_Y = [5]u8{ 0x4a, 0x6a, 0x8a, 0xaf, 0xbf };

    const cart = sram();

    if (selectfile_R16.* < 3)
        selectfile_var2.* = selectfile_R16.*;

    for (0..3) |k| {
        if (readWord(cart + k * 0x500 + 0x3E5) == 0x55AA) {
            selectfile_arr1[k] = 1;
            SelectFile_Func5_DrawOams(@intCast(k));
            SelectFile_Func6_DrawOams2(@intCast(k));
            SelectFile_Func17(@intCast(k));
        }
    }

    FileSelect_DrawFairy(0x1c, kSelectFile_Faerie_Y[selectfile_R16.*]);
    nmi_load_bg_from_vram.* = 1;

    const a = ((filtered_joypad_L.* & 0xc0) | filtered_joypad_H.*) & 0xfc;
    if (a & 0x2c != 0) {
        if (a & 8 != 0) {
            sound_effect_2.* = 0x20;
            selectfile_R16.* -%= 1;
            if (sign8(selectfile_R16.*))
                selectfile_R16.* = 4;
        } else {
            sound_effect_2.* = 0x20;
            selectfile_R16.* +%= 1;
            if (selectfile_R16.* == 5)
                selectfile_R16.* = 0;
        }
    } else if (a != 0) {
        sound_effect_1.* = 0x2c;
        if (selectfile_R16.* < 3) {
            selectfile_R17.* = 0;
            if (selectfile_arr1[selectfile_R16.*] == 0) {
                main_module_index.* = 4;
                submodule_index.* = 0;
                subsubmodule_index.* = 0;
            } else {
                music_control.* = 0xf1;
                srm_var1().* = @as(u16, selectfile_R16.*) * 2 + 2;
                writeWord(g_ram[0..].ptr, @as(u16, selectfile_R16.*) *% 0x500);
                CopySaveToWRAM();
            }
        } else if ((selectfile_arr1[0] | selectfile_arr1[1] | selectfile_arr1[2]) != 0) {
            main_module_index.* = if (selectfile_R16.* == 3) 2 else 3;
            selectfile_R16.* = 0;
            submodule_index.* = 0;
            subsubmodule_index.* = 0;
        } else {
            sound_effect_1.* = 0x3c;
        }
    }
}

pub export fn Module02_CopyFile() callconv(.c) void { // 8cd053
    selectfile_var2.* = 0;
    switch (submodule_index.*) {
        0 => FileSelect_EraseTriforce(),
        1 => Module_EraseFile_1(),
        2 => Module_CopyFile_2(),
        3 => CopyFile_ChooseSelection(),
        4 => CopyFile_ChooseTarget(),
        5 => CopyFile_ConfirmSelection(),
        else => {},
    }
}

pub export fn Module_CopyFile_2() callconv(.c) void { // 8cd06e
    nmi_load_bg_from_vram.* = 7;
    submodule_index.* +%= 1;
    INIDISP_copy.* = 0xf;
    nmi_disable_core_updates.* = 0;
    var i: usize = 0;
    while (selectfile_arr1[i] == 0) : (i += 1) {}
    selectfile_R16.* = @intCast(i);
}

pub export fn CopyFile_ChooseSelection() callconv(.c) void { // 8cd087
    CopyFile_SelectionAndBlinker();
    if (submodule_index.* == 3 and (frame_counter.* & 0x30) == 0)
        FilePicker_DeleteHeaderStripe();
    nmi_load_bg_from_vram.* = 1;
}

pub export fn CopyFile_ChooseTarget() callconv(.c) void { // 8cd0a2
    CopyFile_TargetSelectionAndBlink();
    if (submodule_index.* == 4 and (frame_counter.* & 0x30) == 0)
        FilePicker_DeleteHeaderStripe();
    nmi_load_bg_from_vram.* = 1;
}

pub export fn CopyFile_ConfirmSelection() callconv(.c) void { // 8cd0b9
    CopyFile_HandleConfirmation();
    nmi_load_bg_from_vram.* = 1;
}

pub export fn FilePicker_DeleteHeaderStripe() callconv(.c) void { // 8cd0c6
    const kFilePicker_DeleteHeaderStripe_Dst = [2]u16{ 4, 0x1e };
    var j: i32 = 1;
    while (j >= 0) : (j -= 1) {
        const dst = vram_upload_data + kFilePicker_DeleteHeaderStripe_Dst[@intCast(j)] / 2;
        for (0..11) |i|
            dst[i] = 0xa9;
    }
}

const kCopyFile_SelectionAndBlinker_Tab = [173]u8{
    0x61, 4,    0,    0x15, 0x85, 0x18, 0x26, 0x18, 7,    0x18, 0xaf, 0x18, 2,    0x18, 7,    0x18,
    0x6f, 0x18, 0x86, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x61, 0x24, 0,    0x15, 0x95, 0x18,
    0x36, 0x18, 0x17, 0x18, 0xbf, 0x18, 0x12, 0x18, 0x17, 0x18, 0x7f, 0x18, 0x96, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0x61, 0x67, 0,    0xf,  0xe7, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x61, 0x87, 0,    0xf,  0xf7, 0x18, 0x91, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x61, 0xc7, 0,    0xf,
    0xe8, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0x61, 0xe7, 0,    0xf,  0xf8, 0x18, 0x91, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0x62, 0x27, 0,    0xf,  0xe9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x62, 0x47, 0,    0xf,  0xf9, 0x18, 0x91, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xff,
};

const kCopyFile_SelectionAndBlinker_Tab1 = [73]u8{
    0x61, 0x67, 0x40, 0xe,  0xa9, 0,    0x61, 0x87, 0x40, 0xe,  0xa9, 0,    0x61, 0xc7, 0x40, 0xe,
    0xa9, 0,    0x61, 0xe7, 0x40, 0xe,  0xa9, 0,    0x11, 0x30, 0,    1,    0x83, 0x35, 0x11, 0x31,
    0x40, 0x14, 0x85, 0x35, 0x11, 0x3c, 0,    1,    0x84, 0x35, 0x11, 0x50, 0xc0, 0xe,  0x86, 0x35,
    0x11, 0x5c, 0xc0, 0xe,  0x96, 0x35, 0x12, 0x50, 0,    1,    0x93, 0x35, 0x12, 0x51, 0x40, 0x14,
    0x95, 0x35, 0x12, 0x5c, 0,    1,    0x94, 0x35, 0xff,
};

pub export fn CopyFile_SelectionAndBlinker() callconv(.c) void { // 8cd13f
    const kCopyFile_SelectionAndBlinker_Dst = [3]u16{ 0x3c, 0x64, 0x8c };
    const kCopyFile_SelectionAndBlinker_FaerieX = [4]u8{ 36, 36, 36, 28 };
    const kCopyFile_SelectionAndBlinker_FaerieY = [4]u8{ 87, 111, 135, 191 };

    vram_upload_offset.* = 0xac;
    @memcpy(@as([*]u8, @ptrCast(vram_upload_data))[0..173], &kCopyFile_SelectionAndBlinker_Tab);

    for (0..3) |k| {
        if (selectfile_arr1[k] & 1 != 0) {
            var name = sram() + 0x500 * k + kSrmOffs_Name;
            var dst = vram_upload_data + kCopyFile_SelectionAndBlinker_Dst[k] / 2;
            for (0..6) |_| {
                const t = readWord(name) +% 0x1800;
                name += 2;
                dst[0] = t;
                dst[10] = t +% 0x10;
                dst += 1;
            }
        }
    }
    FileSelect_DrawFairy(
        kCopyFile_SelectionAndBlinker_FaerieX[selectfile_R16.*],
        kCopyFile_SelectionAndBlinker_FaerieY[selectfile_R16.*],
    );

    const a = ((filtered_joypad_L.* & 0xc0) | filtered_joypad_H.*) & 0xfc;
    if (a & 0x2c != 0) {
        var k = selectfile_R16.*;
        if (a & 8 != 0) {
            while (true) {
                k -%= 1;
                if (sign8(k)) {
                    k = 3;
                    break;
                }
                if (selectfile_arr1[k] != 0) break;
            }
        } else {
            while (true) {
                k +%= 1;
                if (k >= 4)
                    k = 0;
                if (k == 3 or selectfile_arr1[k] != 0) break;
            }
        }
        selectfile_R16.* = k;
        sound_effect_2.* = 0x20;
    } else if (a != 0) {
        sound_effect_1.* = 0x2c;
        if (selectfile_R16.* == 3) {
            ReturnToFileSelect();
            return;
        }
        selectfile_R20.* = @as(u16, selectfile_R16.*) * 2;
        @memcpy(
            @as([*]u8, @ptrCast(vram_upload_data + 26))[0..73],
            &kCopyFile_SelectionAndBlinker_Tab1,
        );
        if (selectfile_R16.* != 2) {
            const dst = vram_upload_data + @as(usize, selectfile_R16.*) * 6;
            dst[26] = 0x2762;
            dst[29] = 0x4762;
        }
        submodule_index.* +%= 1;
        selectfile_R16.* = 0;
    }
}

pub export fn ReturnToFileSelect() callconv(.c) void { // 8cd22d
    main_module_index.* = 1;
    submodule_index.* = 1;
    subsubmodule_index.* = 0;
    selectfile_R16.* = 0;
}

const kCopyFile_TargetSelectionAndBlink_Tab0 = [133]u8{
    0x61, 0x51, 0,    0x15, 0x85, 0x18, 0x23, 0x18, 0xe,  0x18, 0xa9, 0x18, 0x26, 0x18, 7,    0x18,
    0xaf, 0x18, 2,    0x18, 7,    0x18, 0x6f, 0x18, 0x86, 0x18, 0x61, 0x71, 0,    0x15, 0x95, 0x18,
    0x33, 0x18, 0x1e, 0x18, 0xb9, 0x18, 0x36, 0x18, 0x17, 0x18, 0xbf, 0x18, 0x12, 0x18, 0x17, 0x18,
    0x7f, 0x18, 0x96, 0x18, 0x61, 0xb4, 0,    0xf,  0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x61, 0xd4, 0,    0xf,  0xa9, 0x18, 0x91, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x62, 0x14, 0,    0xf,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0x62, 0x34, 0,    0xf,  0xa9, 0x18, 0x91, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xff,
};

const kCopyFile_TargetSelectionAndBlink_Tab2 = [49]u8{
    0x61, 0xb4, 0x40, 0xe,  0xa9, 0,    0x61, 0xd4, 0x40, 0xe,  0xa9, 0,    0x62, 0xc6, 0,    0xd,
    2,    0x18, 0xe,  0x18, 0xf,  0x18, 0x28, 0x18, 0xa9, 0x18, 0xe,  0x18, 0xa,  0x18, 0x62, 0xe6,
    0,    0xd,  0x12, 0x18, 0x1e, 0x18, 0x1f, 0x18, 0x38, 0x18, 0xa9, 0x18, 0x1e, 0x18, 0x1a, 0x18,
    0xff,
};

pub export fn CopyFile_TargetSelectionAndBlink() callconv(.c) void { // 8cd27b
    {
        var k: i32 = 1;
        var t: i32 = 4;
        while (true) {
            if (t != selectfile_R20.*) {
                selectfile_arr2[@intCast(k)] = @intCast(t);
                k -= 1;
            }
            t -= 2;
            if (t < 0) break;
        }
    }

    const kCopyFile_TargetSelectionAndBlink_FaerieX = [3]u8{ 0x8c, 0x8c, 0x1c };
    const kCopyFile_TargetSelectionAndBlink_FaerieY = [3]u8{ 0x67, 0x7f, 0xbf };
    const kCopyFile_TargetSelectionAndBlink_Dst = [2]u16{ 0x38, 0x60 };
    const kCopyFile_TargetSelectionAndBlink_Tab1 = [3]u16{ 0x18e7, 0x18e8, 0x18e9 };
    @memcpy(
        @as([*]u8, @ptrCast(vram_upload_data))[0..133],
        &kCopyFile_TargetSelectionAndBlink_Tab0,
    );

    var j: usize = 0;
    for (0..3) |k| {
        if (k * 2 == selectfile_R20.*)
            continue;

        var dst = vram_upload_data + kCopyFile_TargetSelectionAndBlink_Dst[j] / 2;
        j += 1;
        const t = kCopyFile_TargetSelectionAndBlink_Tab1[k];
        dst[0] = t;
        dst[10] = t +% 0x10;
        dst += 2;
        if (selectfile_arr1[k] != 0) {
            var name = sram() + 0x500 * k + kSrmOffs_Name;
            for (0..6) |_| {
                const v = readWord(name) +% 0x1800;
                name += 2;
                dst[0] = v;
                dst[10] = v +% 0x10;
                dst += 1;
            }
        }
    }

    vram_upload_offset.* = 132;

    FileSelect_DrawFairy(
        kCopyFile_TargetSelectionAndBlink_FaerieX[selectfile_R16.*],
        kCopyFile_TargetSelectionAndBlink_FaerieY[selectfile_R16.*],
    );

    const a = ((filtered_joypad_L.* & 0xc0) | filtered_joypad_H.*) & 0xfc;
    if (a & 0x2c != 0) {
        var k = selectfile_R16.*;
        if (a & 8 != 0) {
            k -%= 1;
            if (sign8(k))
                k = 2;
        } else {
            k +%= 1;
            if (k >= 3)
                k = 0;
        }
        selectfile_R16.* = k;
        sound_effect_2.* = 0x20;
    } else if (a != 0) {
        sound_effect_1.* = 0x2c;
        if (selectfile_R16.* == 2) {
            ReturnToFileSelect();
            selectfile_R16.* = 0;
            return;
        }
        selectfile_R18.* = selectfile_arr2[selectfile_R16.*];
        @memcpy(
            @as([*]u8, @ptrCast(vram_upload_data + 26))[0..49],
            &kCopyFile_TargetSelectionAndBlink_Tab2,
        );
        if (selectfile_R16.* == 0) {
            const dst = vram_upload_data;
            dst[26] = 0x1462;
            dst[29] = 0x3462;
        }
        submodule_index.* +%= 1;
        selectfile_R16.* = 0;
    }
}

pub export fn CopyFile_HandleConfirmation() callconv(.c) void { // 8cd371
    const kCopyFile_HandleConfirmation_FaerieY = [2]u8{ 0xaf, 0xbf };
    FileSelect_DrawFairy(0x1c, kCopyFile_HandleConfirmation_FaerieY[selectfile_R16.*]);

    const a = ((filtered_joypad_L.* & 0xc0) | filtered_joypad_H.*) & 0xfc;
    if (a & 0x2c != 0) {
        sound_effect_2.* = 0x20;
        if (a & 0x24 != 0) {
            selectfile_R16.* +%= 1;
            if (selectfile_R16.* >= 2)
                selectfile_R16.* = 0;
        } else {
            selectfile_R16.* -%= 1;
            if (sign8(selectfile_R16.*))
                selectfile_R16.* = 1;
        }
    } else if (a != 0) {
        sound_effect_1.* = 0x2c;
        if (selectfile_R16.* == 0) {
            const dst = sram() + (selectfile_R18.* >> 1) * 0x500;
            const src = sram() + (selectfile_R20.* >> 1) * 0x500;
            @memcpy(dst[0..0x500], src[0..0x500]);
            selectfile_arr1[selectfile_R18.* >> 1] = 1;
            ZeldaWriteSram();
        }
        ReturnToFileSelect();
        selectfile_R16.* = 0;
    }
}

pub export fn Module03_KILLFile() callconv(.c) void { // 8cd485
    switch (submodule_index.*) {
        0 => FileSelect_EraseTriforce(),
        1 => Module_EraseFile_1(),
        2 => KILLFile_SetUp(),
        3 => KILLFile_HandleSelection(),
        4 => KILLFile_HandleConfirmation(),
        else => {},
    }
}

pub export fn KILLFile_SetUp() callconv(.c) void { // 8cd49a
    nmi_load_bg_from_vram.* = 8;
    submodule_index.* +%= 1;
    INIDISP_copy.* = 0xf;
    nmi_disable_core_updates.* = 0;
    var i: usize = 0;
    while (selectfile_arr1[i] == 0) : (i += 1) {}
    selectfile_R16.* = @intCast(i);
}

pub export fn KILLFile_HandleSelection() callconv(.c) void { // 8cd49f
    if (selectfile_R16.* < 3)
        selectfile_var2.* = selectfile_R16.*;
    KILLFile_ChooseTarget();
    nmi_load_bg_from_vram.* = 1;
}

pub export fn KILLFile_HandleConfirmation() callconv(.c) void { // 8cd4b1
    SelectFile_Func16();
    nmi_load_bg_from_vram.* = 1;
}

const kKILLFile_ChooseTarget_Tab = [253]u8{
    0x61, 0xa7, 0,    0x25, 0xe7, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x61, 0xc7, 0,    0x25, 0xf7, 0x18,
    0x91, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0x62, 7,    0,    0x25, 0xe8, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x62, 0x27,
    0,    0x25, 0xf8, 0x18, 0x91, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0x62, 0x67, 0,    0x25, 0xe9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0x62, 0x87, 0,    0x25, 0xf9, 0x18, 0x91, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18,
    0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xa9, 0x18, 0xff,
};

const kKILLFile_ChooseTarget_Tab2 = [101]u8{
    0x61, 0xa7, 0x40, 0x24, 0xa9, 0,    0x61, 0xc7, 0x40, 0x24, 0xa9, 0,    0x62, 7,    0x40, 0x24,
    0xa9, 0,    0x62, 0x27, 0x40, 0x24, 0xa9, 0,    0x62, 0xc6, 0,    0x21, 4,    0x18, 0x21, 0x18,
    0,    0x18, 0x22, 0x18, 4,    0x18, 0xa9, 0x18, 0x23, 0x18, 7,    0x18, 0xaf, 0x18, 0x22, 0x18,
    0xa9, 0x18, 0xf,  0x18, 0xb,  0x18, 0,    0x18, 0x28, 0x18, 4,    0x18, 0x21, 0x18, 0x62, 0xe6,
    0,    0x21, 0x14, 0x18, 0x31, 0x18, 0x10, 0x18, 0x32, 0x18, 0x14, 0x18, 0xa9, 0x18, 0x33, 0x18,
    0x17, 0x18, 0xbf, 0x18, 0x32, 0x18, 0xa9, 0x18, 0x1f, 0x18, 0x1b, 0x18, 0x10, 0x18, 0x38, 0x18,
    0x14, 0x18, 0x31, 0x18, 0xff,
};

pub export fn KILLFile_ChooseTarget() callconv(.c) void { // 8cd4ba
    const kKILLFile_ChooseTarget_FaerieX = [4]u8{ 36, 36, 36, 28 };
    const kKILLFile_ChooseTarget_FaerieY = [4]u8{ 103, 127, 151, 191 };
    @memcpy(@as([*]u8, @ptrCast(vram_upload_data))[0..253], &kKILLFile_ChooseTarget_Tab);
    for (0..3) |k| {
        if (selectfile_arr1[k] != 0)
            SelectFile_Func17(@intCast(k));
    }

    FileSelect_DrawFairy(
        kKILLFile_ChooseTarget_FaerieX[selectfile_R16.*],
        kKILLFile_ChooseTarget_FaerieY[selectfile_R16.*],
    );

    var k = selectfile_R16.*;
    if (filtered_joypad_H.* & 0x2c != 0) {
        if (!(filtered_joypad_H.* & 0x24 != 0)) {
            while (true) {
                k -%= 1;
                if (sign8(k)) {
                    k = 3;
                    break;
                }
                if (selectfile_arr1[k] != 0) break;
            }
        } else {
            while (true) {
                k +%= 1;
                if (k >= 4)
                    k = 0;
                if (k == 3 or selectfile_arr1[k] != 0) break;
            }
        }
        sound_effect_2.* = 0x20;
    }
    selectfile_R16.* = k;

    const a = ((filtered_joypad_L.* & 0xc0) | filtered_joypad_H.*) & 0xd0;
    if (a != 0) {
        sound_effect_1.* = 0x2c;
        if (k == 3) {
            ReturnToFileSelect();
            return;
        }

        @memcpy(@as([*]u8, @ptrCast(vram_upload_data))[0..101], &kKILLFile_ChooseTarget_Tab2);
        submodule_index.* +%= 1;
        if (selectfile_R16.* != 2) {
            const dst = vram_upload_data + @as(usize, selectfile_R16.*) * 6;
            dst[0] = 0x6762;
            dst[3] = 0x8762;
        }
        subsubmodule_index.* = selectfile_R16.*;
        selectfile_R16.* = 0;
    }
}

pub export fn FileSelect_DrawFairy(x: u8, y: u8) callconv(.c) void { // 8cd7a5
    SetOamPlain(oam_buf, x, y, if (frame_counter.* & 8 != 0) 0xaa else 0xa8, 0x7e, 2);
}

pub export fn Module04_NameFile() callconv(.c) void { // 8cd88a
    switch (submodule_index.*) {
        0 => NameFile_EraseSave(),
        1 => Module_NamePlayer_1(),
        2 => Module_NamePlayer_2(),
        3 => NameFile_DoTheNaming(),
        else => {},
    }
}

pub export fn NameFile_EraseSave() callconv(.c) void { // 8cd89c
    FileSelect_EraseTriforce();
    irq_flag.* = 1;
    selectfile_var3.* = 0;
    selectfile_var4.* = 0;
    selectfile_var5.* = 0;
    selectfile_arr2[0] = 0;
    selectfile_var6.* = 0;
    selectfile_var7.* = 0x83;
    selectfile_var8.* = 0x1f0;
    BG3HOFS_copy2.* = 0;
    const offs: usize = @as(usize, selectfile_R16.*) * 0x500;
    attract_legend_ctr.* = @intCast(offs);
    @memset((sram() + offs)[0..0x500], 0);
    const name = sram() + offs + kSrmOffs_Name;
    for (0..6) |i|
        writeWord(name + i * 2, 0xa9);
}

const kNamePlayer_Tab1 = [26]i16{
    -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1,
    -2, 2, -2, 2, -2, 2, -2, 2, -4, 4,
};

const kNamePlayer_Tab3 = [128]i8{
    6,    7,    0x5f, 9,    0x59, 0x59, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x60, 0x23,
    0x59, 0x59, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x59, 0x59, 0x59, 0,    1,    2,    3,    4,    5,
    0x10, 0x11, 0x12, 0x13, 0x59, 0x59, 0x24, 0x5f, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d,
    0x59, 0x59, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f, 0x59, 0x59, 0x59, 0xa,  0xb,  0xc,  0xd,  0xe,  0xf,
    0x40, 0x41, 0x42, 0x59, 0x59, 0x59, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x40, 0x41, 0x42, 0x59,
    0x59, 0x59, 0x61, 0x3f, 0x45, 0x46, 0x59, 0x59, 0x59, 0x59, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19,
    0x44, 0x59, 0x6f, 0x6f, 0x59, 0x59, 0x59, 0x59, 0x59, 0x59, 0x59, 0x5a, 0x44, 0x59, 0x6f, 0x6f,
    0x59, 0x59, 0x5a, 0x44, 0x59, 0x6f, 0x6f, 0x59, 0x59, 0x59, 0x59, 0x59, 0x59, 0x59, 0x59, 0x5a,
};

const kSramInit_Normal = [60]u8{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    0, 0, 0,    0,    0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    0, 0, 0,    0,    0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,    0, 0, 0x18, 0x18, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0xf8, 0, 0,
};

pub export fn NameFile_DoTheNaming() callconv(.c) void { // 8cda4d
    const kNamePlayer_Tab2 = [4]u8{ 131, 147, 163, 179 };
    const kNamePlayer_X = [6]i8{ 31, 47, 63, 79, 95, 111 };
    const kNamePlayer_Tab0 = [32]i16{
        0x1f0, 0,     0x10,  0x20,  0x30,  0x40,  0x50,  0x60,  0x70,  0x80,  0x90,  0xa0,  0xb0,  0xc0,  0xd0,  0xe0,
        0xf0,  0x100, 0x110, 0x120, 0x130, 0x140, 0x150, 0x160, 0x170, 0x180, 0x190, 0x1a0, 0x1b0, 0x1c0, 0x1d0, 0x1e0,
    };
    while (true) {
        var j: i32 = selectfile_var9.*;
        if (j == 0) {
            NameFile_CheckForScrollInputX();
            break;
        }
        if (j != 0x31)
            selectfile_var9.* +%= 4;
        j -= 1;
        if (kNamePlayer_Tab0[selectfile_var3.*] == @as(i16, @bitCast(selectfile_var8.*))) {
            selectfile_var9.* = if (joypad1H_last.* & 3 != 0) 0x30 else 0;
            NameFile_CheckForScrollInputX();
            continue;
        }
        if (selectfile_var10.* == 0)
            j += 2;
        // The C indexes the int16 table by BYTE offset and reads unaligned.
        const raw: [*]const u8 = @ptrCast(&kNamePlayer_Tab1);
        selectfile_var8.* = (selectfile_var8.* +% readWord(raw + @as(usize, @intCast(j)))) & 0x1ff;
        break;
    }

    while (true) {
        if (selectfile_var11.* == 0) {
            NameFile_CheckForScrollInputY();
            break;
        }
        const diff = selectfile_var7.* -% kNamePlayer_Tab2[selectfile_var5.*];
        if (diff != 0) {
            selectfile_var7.* = if (sign8(diff)) selectfile_var7.* +% 2 else selectfile_var7.* -% 2;
            break;
        }
        selectfile_var11.* = 0;
        NameFile_CheckForScrollInputY();
    }

    var oam = oam_buf;
    for (0..26) |i| {
        SetOamPlain(oam, @truncate(0x18 + i * 8), selectfile_var7.*, 0x2e, 0x3c, 0);
        oam += 1;
    }
    SetOamPlain(oam, @bitCast(kNamePlayer_X[selectfile_var4.*]), 0x58, 0x29, 0xc, 0);

    if ((selectfile_var9.* | selectfile_var11.*) != 0)
        return;

    if (!(filtered_joypad_H.* & 0x10 != 0)) {
        if (!((filtered_joypad_H.* & 0xc0) != 0 or (filtered_joypad_L.* & 0xc0) != 0))
            return;

        sound_effect_1.* = 0x2b;
        const t = kNamePlayer_Tab3[@as(usize, selectfile_var3.*) + @as(usize, selectfile_var5.*) * 0x20];
        if (t == 0x5a) {
            if (selectfile_var4.* == 0)
                selectfile_var4.* = 5
            else
                selectfile_var4.* -%= 1;
            return;
        } else if (t == 0x44) {
            selectfile_var4.* +%= 1;
            if (selectfile_var4.* == 6)
                selectfile_var4.* = 0;
            return;
        } else if (t != 0x6f) {
            const p: usize = @as(usize, selectfile_var4.*) * 2 + attract_legend_ctr.*;
            const tv: u16 = @intCast(t);
            const chr: u16 = (tv & 0xfff0) *% 2 +% (tv & 0xf);
            writeWord(sram() + p + kSrmOffs_Name, chr);
            NameFile_DrawSelectedCharacter(selectfile_var4.*, chr);
            selectfile_var4.* +%= 1;
            if (selectfile_var4.* == 6)
                selectfile_var4.* = 0;
            return;
        }
    }
    var i: usize = 0;
    while (true) {
        const a = readWord(sram() + i * 2 + attract_legend_ctr.* + kSrmOffs_Name);
        if (a != 0xa9)
            break;
        i += 1;
        if (i == 6) {
            sound_effect_1.* = 0x3c;
            return;
        }
    }
    srm_var1().* = @as(u16, selectfile_R16.*) * 2 + 2;
    const srm = sram() + @as(usize, selectfile_R16.*) * 0x500;
    writeWord(srm + 0x3e5, 0x55aa);
    writeWord(srm + 0x20c, 0xf000);
    writeWord(srm + 0x20e, 0xf000);
    writeWord(srm + kSrmOffs_DiedCounter, 0xffff);
    @memcpy((srm + 0x340)[0..60], &kSramInit_Normal);
    Intro_FixCksum(srm);
    ZeldaWriteSram();
    ReturnToFileSelect();
    irq_flag.* = 0xff;
    sound_effect_1.* = 0x2c;
}

pub export fn NameFile_CheckForScrollInputX() callconv(.c) void { // 8cdc8c
    const kNameFile_CheckForScrollInputX_Add = [2]u16{ 1, 0xff };
    const kNameFile_CheckForScrollInputX_Cmp = [2]i16{ 0x20, 0xff };
    const kNameFile_CheckForScrollInputX_Set = [2]i16{ 0, 0x1f };
    if (joypad1H_last.* & 3 != 0) {
        const k: usize = (joypad1H_last.* & 3) - 1;
        selectfile_var10.* = @intCast(k);
        selectfile_var9.* +%= 1;
        var t: u8 = selectfile_var3.* +% @as(u8, @truncate(kNameFile_CheckForScrollInputX_Add[k]));
        if (t == @as(u8, @truncate(@as(u16, @bitCast(kNameFile_CheckForScrollInputX_Cmp[k])))))
            t = @truncate(@as(u16, @bitCast(kNameFile_CheckForScrollInputX_Set[k])));
        selectfile_var3.* = t;
    }
}

pub export fn NameFile_CheckForScrollInputY() callconv(.c) void { // 8cdcbf
    const kNameFile_CheckForScrollInputY_Add = [2]i8{ 1, -1 };
    const kNameFile_CheckForScrollInputY_Cmp = [2]i8{ 4, -1 };
    const kNameFile_CheckForScrollInputY_Set = [2]i8{ 0, 3 };

    var a = joypad1H_last.* & 0xc;
    if (a != 0) {
        if ((@as(u32, a) * 2 | selectfile_var5.*) == 0x10 or (@as(u32, a) * 4 | selectfile_var5.*) == 0x13) {
            selectfile_arr2[1] = a;
            return;
        }
        a >>= 2;
        var t: i32 = @as(i32, selectfile_var5.*) + kNameFile_CheckForScrollInputY_Add[a - 1];
        if (t == kNameFile_CheckForScrollInputY_Cmp[a - 1])
            t = kNameFile_CheckForScrollInputY_Set[a - 1];
        selectfile_var5.* = @truncate(@as(u32, @bitCast(t)));

        selectfile_var11.* +%= 1;
        selectfile_arr2[1] = a;
    } else {
        selectfile_arr2[0] = 0;
    }
}

pub export fn NameFile_DrawSelectedCharacter(k: c_int, chr: u16) callconv(.c) void { // 8cdd30
    const kNameFile_DrawSelectedCharacter_Tab = [6]u16{ 0x84, 0x86, 0x88, 0x8a, 0x8c, 0x8e };
    const dst = vram_upload_data;
    const a = kNameFile_DrawSelectedCharacter_Tab[@intCast(k)] | 0x6100;
    dst[0] = swap16(a);
    dst[1] = 0x100;
    dst[2] = 0x1800 | chr;
    dst[3] = swap16(a +% 0x20);
    dst[4] = 0x100;
    dst[5] = (0x1800 | chr) +% 0x10;
    @as([*]u8, @ptrCast(dst + 6))[0] = 0xff;
    nmi_load_bg_from_vram.* = 1;
}

const testing = std.testing;

/// The screens read and write save ram, so tests need one to point g_zenv at.
const TestSram = struct {
    buf: *[0x2000]u8,

    fn init() !TestSram {
        const buf = try testing.allocator.create([0x2000]u8);
        @memset(buf, 0);
        g_zenv.sram = buf;
        @memset(g_ram[0..0x2000], 0);
        return .{ .buf = buf };
    }

    /// A many-item pointer, so tests can do the same offset arithmetic the
    /// screens themselves do.
    fn ptr(self: TestSram) [*]u8 {
        return self.buf;
    }

    fn deinit(self: TestSram) void {
        g_zenv.sram = null;
        testing.allocator.destroy(self.buf);
    }
};

test "the save checksum sums to a fixed constant" {
    const t = try TestSram.init();
    defer t.deinit();

    // A freshly zeroed block does not check out.
    try testing.expect(!Intro_CheckCksum(t.buf));
    // Fixing it up makes it valid, and the fix lives in the last word.
    Intro_FixCksum(t.buf);
    try testing.expect(Intro_CheckCksum(t.buf));
    try testing.expectEqual(@as(u16, 0x5a5a), readWord(t.ptr() + 0x27f * 2));

    // Any later change invalidates it again.
    t.buf[4] = 1;
    try testing.expect(!Intro_CheckCksum(t.buf));
    Intro_FixCksum(t.buf);
    try testing.expect(Intro_CheckCksum(t.buf));
}

test "a corrupt save is restored from its backup copy" {
    const t = try TestSram.init();
    defer t.deinit();

    // File 0's backup at +0xf00 is valid and carries a marker.
    t.buf[0xf00 + 8] = 0x42;
    Intro_FixCksum(t.ptr() + 0xf00);
    Intro_ValidateSram();
    try testing.expectEqual(@as(u8, 0x42), t.buf[8]);
    try testing.expect(Intro_CheckCksum(t.buf));
}

test "a save with no valid backup is wiped" {
    const t = try TestSram.init();
    defer t.deinit();

    t.buf[8] = 0x99;
    t.buf[0xf00 + 8] = 0x77; // neither has a valid checksum
    Intro_ValidateSram();
    try testing.expectEqual(@as(u8, 0), t.buf[8]);
    try testing.expectEqual(@as(u8, 0), t.buf[0xf00 + 8]);
}

test "SelectFile_Func1 lays down a tile pattern and returns the end" {
    @memset(g_ram[0x1000..0x2000], 0);
    const end = SelectFile_Func1();
    const base: [*]align(1) u16 = @ptrCast(&g_ram[0x1002]);
    try testing.expectEqual(@as(u16, 0x10), base[0]);
    try testing.expectEqual(@as(u16, 0xff07), base[1]);
    // i=0 picks index 0, i=1 picks index 1, i=0x20 picks index 2.
    try testing.expectEqual(@as(u16, 0x3581), base[2]);
    try testing.expectEqual(@as(u16, 0x3582), base[3]);
    try testing.expectEqual(@as(u16, 0x3591), base[2 + 0x20]);
    // Two header words plus 1024 entries.
    try testing.expectEqual(@intFromPtr(base + 2 + 1024), @intFromPtr(end));
}

test "the fairy sprite alternates with the frame counter" {
    @memset(g_ram[0x800..0xa40], 0);
    frame_counter.* = 0;
    FileSelect_DrawFairy(0x1c, 0x4a);
    try testing.expectEqual(@as(u8, 0x1c), oam_buf[0].x);
    try testing.expectEqual(@as(u8, 0x4a), oam_buf[0].y);
    try testing.expectEqual(@as(u8, 0xa8), oam_buf[0].charnum);
    try testing.expectEqual(@as(u8, 2), bytewise_extended_oam[0]);

    frame_counter.* = 8;
    FileSelect_DrawFairy(0x1c, 0x4a);
    try testing.expectEqual(@as(u8, 0xaa), oam_buf[0].charnum);
}

test "ReturnToFileSelect resets the module state" {
    @memset(g_ram[0..0x200], 0);
    main_module_index.* = 3;
    submodule_index.* = 4;
    subsubmodule_index.* = 5;
    selectfile_R16.* = 2;
    ReturnToFileSelect();
    try testing.expectEqual(@as(u8, 1), main_module_index.*);
    try testing.expectEqual(@as(u8, 1), submodule_index.*);
    try testing.expectEqual(@as(u8, 0), subsubmodule_index.*);
    try testing.expectEqual(@as(u8, 0), selectfile_R16.*);
}

test "the header stripe is blanked in both halves" {
    @memset(g_ram[0x1000..0x1200], 0);
    FilePicker_DeleteHeaderStripe();
    // Offsets 4 and 0x1e, eleven words each.
    for (0..11) |i| {
        try testing.expectEqual(@as(u16, 0xa9), vram_upload_data[4 / 2 + i]);
        try testing.expectEqual(@as(u16, 0xa9), vram_upload_data[0x1e / 2 + i]);
    }
}

test "drawing a chosen name character builds a vram stripe" {
    @memset(g_ram[0x1000..0x1100], 0);
    NameFile_DrawSelectedCharacter(2, 0x34);
    // Entry 2 of the table is 0x88, or'd with 0x6100 and byte swapped.
    try testing.expectEqual(swap16(0x6188), vram_upload_data[0]);
    try testing.expectEqual(@as(u16, 0x100), vram_upload_data[1]);
    try testing.expectEqual(@as(u16, 0x1834), vram_upload_data[2]);
    try testing.expectEqual(swap16(0x61a8), vram_upload_data[3]);
    try testing.expectEqual(@as(u16, 0x1844), vram_upload_data[5]);
    try testing.expectEqual(@as(u8, 0xff), @as([*]u8, @ptrCast(vram_upload_data + 6))[0]);
    try testing.expectEqual(@as(u8, 1), nmi_load_bg_from_vram.*);
}

test "horizontal name scrolling wraps at both ends" {
    @memset(g_ram[0..0x2000], 0);
    // Right: index 0x1f wraps back to 0.
    selectfile_var3.* = 0x1f;
    joypad1H_last.* = 1;
    NameFile_CheckForScrollInputX();
    try testing.expectEqual(@as(u8, 0), selectfile_var3.*);
    try testing.expectEqual(@as(u8, 0), selectfile_var10.*);

    // Left: index 0 wraps to 0x1f.
    selectfile_var3.* = 0;
    joypad1H_last.* = 2;
    NameFile_CheckForScrollInputX();
    try testing.expectEqual(@as(u8, 0x1f), selectfile_var3.*);
    try testing.expectEqual(@as(u8, 1), selectfile_var10.*);

    // No input leaves it alone.
    joypad1H_last.* = 0;
    NameFile_CheckForScrollInputX();
    try testing.expectEqual(@as(u8, 0x1f), selectfile_var3.*);
}

test "vertical name scrolling clamps at the top and bottom rows" {
    @memset(g_ram[0..0x2000], 0);
    // Down through the four rows of the character grid.
    selectfile_var5.* = 0;
    joypad1H_last.* = 4;
    NameFile_CheckForScrollInputY();
    try testing.expectEqual(1, selectfile_var5.*);
    try testing.expect(selectfile_var11.* != 0);

    // Unlike the horizontal case this one does not wrap: the guard bails out
    // of down-from-the-last-row without even starting a scroll.
    selectfile_var5.* = 3;
    selectfile_var11.* = 0;
    NameFile_CheckForScrollInputY();
    try testing.expectEqual(3, selectfile_var5.*);
    try testing.expectEqual(0, selectfile_var11.*);

    // Up moves back the other way, and is blocked the same at the top.
    joypad1H_last.* = 8;
    NameFile_CheckForScrollInputY();
    try testing.expectEqual(2, selectfile_var5.*);

    selectfile_var5.* = 0;
    selectfile_var11.* = 0;
    NameFile_CheckForScrollInputY();
    try testing.expectEqual(0, selectfile_var5.*);
    try testing.expectEqual(0, selectfile_var11.*);

    // No input at all clears the scratch byte instead.
    selectfile_arr2[0] = 9;
    joypad1H_last.* = 0;
    NameFile_CheckForScrollInputY();
    try testing.expectEqual(0, selectfile_arr2[0]);
}

test "the file name is drawn into the upload buffer" {
    const t = try TestSram.init();
    defer t.deinit();
    @memset(g_ram[0x1000..0x1200], 0);

    // Six name characters for file 0, and one heart of health.
    for (0..6) |i|
        writeWord(t.ptr() + kSrmOffs_Name + i * 2, @intCast(0x20 + i));
    t.buf[kSrmOffs_Health] = 8; // 8 >> 3 == 1

    SelectFile_Func17(0);
    // Offset 8 / 2 == word 4 is where file 0's name starts.
    try testing.expectEqual(@as(u16, 0x1820), vram_upload_data[4]);
    try testing.expectEqual(@as(u16, 0x1830), vram_upload_data[4 + 21]);
    try testing.expectEqual(@as(u16, 0x1825), vram_upload_data[9]);
    // One heart drawn at the health offset.
    try testing.expectEqual(@as(u16, 0x520), vram_upload_data[0x16 / 2]);
}

test "the death counter is split into digits" {
    const t = try TestSram.init();
    defer t.deinit();
    @memset(g_ram[0x800..0xa40], 0);

    writeWord(t.ptr() + kSrmOffs_DiedCounter, 123);
    SelectFile_Func6_DrawOams2(0);
    // Digits are drawn from the most significant down; entry 4/4 == oam 1.
    const oam = oam_buf + 1;
    try testing.expectEqual(@as(u8, 0xac), oam[0].charnum); // '1'
    try testing.expectEqual(@as(u8, 0xad), oam[1].charnum); // '2'
    try testing.expectEqual(@as(u8, 0xbc), oam[2].charnum); // '3'

    // 0xffff means "no file", and nothing is drawn.
    @memset(g_ram[0x800..0xa40], 0);
    writeWord(t.ptr() + kSrmOffs_DiedCounter, 0xffff);
    SelectFile_Func6_DrawOams2(0);
    try testing.expectEqual(@as(u8, 0), oam[0].charnum);
}

test "the stripe tables came over intact" {
    try testing.expectEqual(224, kSelectFile_Gfx0.len);
    try testing.expectEqual(253, kSelectFile_Func3_Data.len);
    try testing.expectEqual(173, kCopyFile_SelectionAndBlinker_Tab.len);
    try testing.expectEqual(73, kCopyFile_SelectionAndBlinker_Tab1.len);
    try testing.expectEqual(133, kCopyFile_TargetSelectionAndBlink_Tab0.len);
    try testing.expectEqual(49, kCopyFile_TargetSelectionAndBlink_Tab2.len);
    try testing.expectEqual(253, kKILLFile_ChooseTarget_Tab.len);
    try testing.expectEqual(101, kKILLFile_ChooseTarget_Tab2.len);
    try testing.expectEqual(60, kSramInit_Normal.len);
    try testing.expectEqual(128, kNamePlayer_Tab3.len);
    try testing.expectEqual(26, kNamePlayer_Tab1.len);
    // Every stripe table ends with the 0xff terminator.
    try testing.expectEqual(@as(u8, 0xff), kSelectFile_Func3_Data[252]);
    try testing.expectEqual(@as(u8, 0xff), kCopyFile_SelectionAndBlinker_Tab[172]);
    try testing.expectEqual(@as(u8, 0xff), kKILLFile_ChooseTarget_Tab[252]);
}
