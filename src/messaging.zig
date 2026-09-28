//! Port of src/messaging.c: the interface module (potions, save menu, flute
//! menu, world map, dungeon map), the game-over sequence, and the whole
//! variable-width-font text renderer.
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl.zig");
const rtl_types = @import("zelda_rtl_types.zig");
const features = @import("features.zig");
const main_mod = @import("main.zig");
const util = @import("util.zig");
const tables = @import("messaging_tables.zig");
const load_gfx = @import("load_gfx.zig");
const misc = @import("misc.zig");
const hud = @import("hud.zig");
const nmi = @import("nmi.zig");
const audio = @import("audio.zig");
const attract = @import("attract.zig");
const player_oam = @import("player_oam.zig");
const settings_menu = @import("settings_menu.zig");

const MemBlk = util.MemBlk;
const OamEnt = vars.OamEnt;
const g_ram = &vars.g_ram;
const g_zenv = &rtl_types.g_zenv;
const oam_buf = vars.oam_buf;
const bytewise_extended_oam = vars.bytewise_extended_oam;

/// zelda_rtl.h: typedef void PlayerHandlerFunc();
const PlayerHandlerFunc = fn () callconv(.c) void;

// snes/snes_regs.h
const M7A = 0x211b;
const M7D = 0x211e;
const WH0 = 0x2126;

/// types.h
pub const Point16U = extern struct { x: u16, y: u16 };
/// types.h
pub const Pair16U = extern struct { a: u16, b: u16 };

// ---------------------------------------------------------------------------
// Helpers for the C macros this file leans on.
// ---------------------------------------------------------------------------

/// types.h BYTE(): the low byte of a 16-bit work-ram variable.
inline fn loPtr(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

/// types.h WORD() applied to a variable declared as a byte.
inline fn wordPtr(p: *u8) *align(1) u16 {
    return @ptrCast(p);
}

inline fn swap16(v: u16) u16 {
    return (v << 8) | (v >> 8);
}

inline fn sign8(v: u8) bool {
    return v & 0x80 != 0;
}

inline fn sign16(v: u16) bool {
    return v & 0x8000 != 0;
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

/// variables.h spells this one relative to SRAM rather than work ram, which is
/// why it has no generated accessor.
inline fn srm_var1() *align(1) u16 {
    return @ptrCast(g_zenv.sram.? + 0x1ffe);
}

/// link_item_bow is the base of the contiguous inventory block; the Y-item
/// pickers index off it.
inline fn linkItems() [*]u8 {
    return @ptrCast(vars.link_item_bow);
}

// assets.h
inline fn kOverworldMapGfx() [*]const u8 {
    return main_mod.g_asset_ptrs[66].?;
}
inline fn kLightOverworldTilemap() [*]const u8 {
    return main_mod.g_asset_ptrs[67].?;
}
inline fn kDarkOverworldTilemap() [*]const u8 {
    return main_mod.g_asset_ptrs[68].?;
}
inline fn kDungMap_FloorLayout(idx: c_int) MemBlk {
    return main_mod.FindInAssetArray(97, idx);
}
inline fn kDungMap_Tiles(idx: c_int) MemBlk {
    return main_mod.FindInAssetArray(98, idx);
}

// ---------------------------------------------------------------------------
// Text command encoding. The dialogue stream packs a parameter, a command and
// a multibyte flag into one word.
// ---------------------------------------------------------------------------

const kTextCommandStart_US = 0x67;
const kTextDictBase = 0x88;

const kTextCmd_NextPic = 0;
const kTextCmd_Choose = 1;
const kTextCmd_Item = 2;
const kTextCmd_Name = 3;
/// Only used with 2
const kTextCmd_Window = 4;
const kTextCmd_Number = 5;
const kTextCmd_Position = 6;
const kTextCmd_ScrollSpd = 7;
const kTextCmd_Selchg = 8;
const kTextCmd_Choose3 = 10;
const kTextCmd_Choose2 = 11;
const kTextCmd_Scroll = 12;
const kTextCmd_1 = 13;
const kTextCmd_2 = 14;
const kTextCmd_3 = 15;
const kTextCmd_Color = 16;
const kTextCmd_Wait = 17;
const kTextCmd_Sound = 18;
const kTextCmd_Speed = 19;
/// Unused
const kTextCmd_Mark = 20;
/// Unused
const kTextCmd_Mark2 = 21;
/// Unused
const kTextCmd_Clear = 22;
const kTextCmd_Waitkey = 23;
const kTextCmd_EndMessage = 24;
/// Pseudo cmd
const kTextCmd_IsLetter = 25;

const kTextCmd_EU_Rest = 0x87;

inline fn TEXTCMD_MULTIBYTE(a: u32) u32 {
    return a & 1;
}
inline fn TEXTCMD_CMD(a: u32) u32 {
    return (a >> 1) & 0x1f;
}
inline fn TEXTCMD_PARAM(a: u32) u32 {
    return a >> 6;
}
inline fn TEXTCMD_MK(c: u32, x: u32, m: u32) u32 {
    return c << 6 | x << 1 | m;
}

// ---------------------------------------------------------------------------
// Still in C.
// ---------------------------------------------------------------------------

// ancilla.c
extern fn AddBirdTravelSomething(a: u8, y: u8) void;
extern fn Ancilla_GetX(k: c_int) u16;
extern fn Ancilla_MoveX(k: c_int) void;
extern fn ConfigureRevivalAncillae() void;
extern fn GameOverText_Draw() void;
extern fn RevivalFairy_Main() void;
// dungeon.c
extern fn Dungeon_ApproachFixedColor_variable(a: u8) void;
extern fn Dungeon_FlagRoomData_Quadrants() void;
extern fn Dungeon_PrepareNextRoomQuadrantUpload() void;
extern fn Dungeon_PushBlock_Handler() void;
extern fn OrientLampLightCone() void;
extern fn ResetTransitionPropsAndAdvance_ResetInterface() void;
extern fn WaterFlood_BuildOneQuadrantForVRAM() void;
// overworld.c
extern fn AdjustLinkBunnyStatus() void;
extern fn FluteMenu_LoadSelectedScreenPalettes() void;
extern fn FluteMenu_LoadTransport() void;
extern fn ForceNonbunnyStatus() void;
extern fn OverworldOverlay_HandleRain() void;
extern fn Overworld_DwDeathMountainPaletteAnimation() void;
extern fn Overworld_LoadAndBuildScreen() void;
extern fn Overworld_LoadOverlays2() void;
extern fn Overworld_SetFixedColAndScroll() void;
// player.c
extern fn Link_ResetProperties_C() void;
extern fn ResetSomeThingsAfterDeath(a: u8) void;
// sprite.c
extern fn Sprite_Main() void;
extern fn Sprite_ResetAll() void;

// ---------------------------------------------------------------------------
// Dispatch tables.
// ---------------------------------------------------------------------------

const kDungMapInit = [5]*const PlayerHandlerFunc{
    &Module0E_03_01_00_PrepMapGraphics,
    &Module0E_03_01_01_DrawLEVEL,
    &Module0E_03_01_02_DrawFloorsBackdrop,
    &Module0E_03_01_03_DrawRooms,
    &DungeonMap_DrawRoomMarkers,
};

const kDungMapSubmodules = [9]*const PlayerHandlerFunc{
    &DungMap_Backup,
    &Module0E_03_01_DrawMap,
    &DungMap_LightenUpMap,
    &DungeonMap_HandleInputAndSprites,
    &DungMap_4,
    &DungMap_FadeMapToBlack,
    &DungeonMap_RecoverGFX,
    &ToggleStarTilesAndAdvance,
    &DungMap_RestoreOld,
};

const kText_Render = [5]*const PlayerHandlerFunc{
    &RenderText_Draw_Border,
    &RenderText_Draw_BorderIncremental,
    &RenderText_Draw_CharacterTilemap,
    &RenderText_Draw_MessageCharacters,
    &RenderText_Draw_Finish,
};

const kMessaging_Text = [3]*const PlayerHandlerFunc{
    &Text_Initialize,
    &Text_Render,
    &RenderText_PostDeathSaveOptions,
};

const kMessagingSubmodules = [12]*const PlayerHandlerFunc{
    &Module_Messaging_0,
    &hud.Hud_Module_Run,
    &RenderText,
    &Module0E_03_DungeonMap,
    &Module0E_04_RedPotion,
    &Module0E_05_DesertPrayer,
    &Module_Messaging_6,
    &Messaging_OverworldMap,
    &Module0E_08_GreenPotion,
    &Module0E_09_BluePotion,
    &Module0E_0A_FluteMenu,
    &Module0E_0B_SaveMenu,
};

const kModule_Death = [16]*const PlayerHandlerFunc{
    &GameOver_AdvanceImmediately,
    &Death_Func1,
    &GameOver_DelayBeforeIris,
    &GameOver_IrisWipe,
    &Death_Func4,
    &GameOver_SplatAndFade,
    &Death_Func6,
    &Animate_GAMEOVER_Letters_bounce,
    &GameOver_Finalize_GAMEOVR,
    &GameOver_SaveAndOrContinue,
    &GameOver_InitializeRevivalFairy,
    &RevivalFairy_Main_bounce,
    &GameOver_RiseALittle,
    &GameOver_Restore0D,
    &GameOver_Restore0E,
    &GameOver_ResituateLink,
};

/// Defined here rather than in variables.zig because messaging.c owns it.
pub export const kHealthAfterDeath = [21]u8{
    0x18, 0x18, 0x18, 0x18, 0x18, 0x20, 0x20, 0x28, 0x28, 0x30, 0x30,
    0x38, 0x38, 0x38, 0x40, 0x40, 0x40, 0x48, 0x48, 0x48, 0x50,
};

pub export fn GetDungmapFloorLayout() callconv(.c) [*]const u8 {
    return kDungMap_FloorLayout(@intCast(vars.cur_palace_index_x2.* >> 1)).ptr.?;
}

pub export fn GetOtherDungmapInfo(count: c_int) callconv(.c) u8 {
    const p = kDungMap_Tiles(@intCast(vars.cur_palace_index_x2.* >> 1)).ptr.?;
    return p[@intCast(count)];
}

pub export fn DungMap_4() callconv(.c) void {
    vars.BG2VOFS_copy2.* +%= vars.dungmap_var4.*;
    vars.dungmap_var5.* -%= vars.dungmap_var4.*;
    vars.bottle_menu_expand_row.* -%= 1;
    if (vars.bottle_menu_expand_row.* == 0)
        vars.overworld_map_state.* -%= 1;
}

pub export fn Module_Messaging_6() callconv(.c) void {
    unreachable; // assert(0)
}

pub export fn OverworldMap_SetupHdma() callconv(.c) void {
    // uint32 table; the generator only emits 8/16-bit ones.
    const kOverworldMap_TableLow = [2]u32{ 0xabdcf, 0xabdd6 };
    const a = kOverworldMap_TableLow[vars.overworld_map_flags.*];
    rtl.HdmaSetup(a, a, 0x42, @truncate(M7A), @truncate(M7D), 10);
}

pub export fn GetLightOverworldTilemap() callconv(.c) [*]const u8 {
    return kLightOverworldTilemap();
}

pub export fn SaveGameFile() callconv(.c) void {
    const offs: usize = @intCast((@as(i32, srm_var1().* >> 1) - 1) * 0x500);
    const sram = g_zenv.sram.?;
    const src: [*]const u8 = @ptrCast(vars.save_dung_info);
    @memcpy((sram + offs)[0..0x500], src[0..0x500]);
    @memcpy((sram + offs + 0xf00)[0..0x500], src[0..0x500]);
    var t: u16 = 0x5a5a;
    var i: usize = 0;
    while (i < 0x4fe) : (i += 2)
        t -%= std.mem.readInt(u16, (src + i)[0..2], .little);
    vars.word_7EF4FE.* = t;
    std.mem.writeInt(u16, (sram + offs + 0x4fe)[0..2], t, .little);
    std.mem.writeInt(u16, (sram + offs + 0x4fe + 0xf00)[0..2], t, .little);
    rtl.ZeldaWriteSram();
}

pub export fn TransferMode7Characters() callconv(.c) void {
    // The tilemap lives in the high byte of each vram word.
    const dst: [*]u8 = @ptrCast(g_zenv.vram.?);
    const src = kOverworldMapGfx();
    var i: usize = 0;
    while (i != 0x4000) : (i += 1)
        dst[i * 2 + 1] = src[i];
}

pub export fn Module0E_Interface() callconv(.c) void {
    var skip_run = false;
    if (vars.player_is_indoors.* != 0) {
        if (vars.submodule_index.* == 3) {
            skip_run = (vars.overworld_map_state.* != 0 and vars.overworld_map_state.* != 7);
        } else {
            Dungeon_PushBlock_Handler();
        }
    } else {
        skip_run = ((vars.submodule_index.* == 7 or vars.submodule_index.* == 10) and
            vars.overworld_map_state.* != 0);
    }
    if (!skip_run) {
        Sprite_Main();
        player_oam.LinkOam_Main();
        if (vars.player_is_indoors.* == 0)
            OverworldOverlay_HandleRain();
        hud.Hud_RefillLogic();
        if (vars.submodule_index.* != 2)
            OrientLampLightCone();
    }
    RunInterface();
    vars.BG2HOFS_copy.* = vars.BG2HOFS_copy2.* +% vars.bg1_x_offset.*;
    vars.BG2VOFS_copy.* = vars.BG2VOFS_copy2.* +% vars.bg1_y_offset.*;
    vars.BG1HOFS_copy.* = vars.BG1HOFS_copy2.* +% vars.bg1_x_offset.*;
    vars.BG1VOFS_copy.* = vars.BG1VOFS_copy2.* +% vars.bg1_y_offset.*;
}

pub export fn Module_Messaging_0() callconv(.c) void {
    unreachable; // assert(0)
}

fn RunInterface() void {
    kMessagingSubmodules[vars.submodule_index.*]();
}

pub export fn Module0E_05_DesertPrayer() callconv(.c) void {
    switch (vars.subsubmodule_index.*) {
        0 => ResetTransitionPropsAndAdvance_ResetInterface(),
        1 => load_gfx.ApplyPaletteFilter_bounce(),
        2 => {
            DesertPrayer_InitializeIrisHDMA();
            loPtr(vars.palette_filter_countdown).* = vars.mosaic_target_level.* -% 1;
            vars.mosaic_target_level.* = 0;
            loPtr(vars.darkening_or_lightening_screen).* = 2;
        },
        // Case 3 falls through into case 4.
        3, 4 => {
            if (vars.subsubmodule_index.* == 3)
                load_gfx.ApplyPaletteFilter_bounce();
            DesertPrayer_BuildIrisHDMATable();
        },
        else => {},
    }
}

pub export fn Module0E_04_RedPotion() callconv(.c) void {
    if (hud.Hud_RefillHealth()) {
        vars.button_mask_b_y.* &= ~@as(u8, 0x40);
        vars.flag_update_hud_in_nmi.* +%= 1;
        vars.submodule_index.* = 0;
        vars.main_module_index.* = vars.saved_module_for_menu.*;
    }
}

pub export fn Module0E_08_GreenPotion() callconv(.c) void {
    if (hud.Hud_RefillMagicPower()) {
        vars.button_mask_b_y.* &= ~@as(u8, 0x40);
        vars.flag_update_hud_in_nmi.* +%= 1;
        vars.submodule_index.* = 0;
        vars.main_module_index.* = vars.saved_module_for_menu.*;
    }
}

pub export fn Module0E_09_BluePotion() callconv(.c) void {
    if (hud.Hud_RefillHealth())
        vars.submodule_index.* = 8;
    if (hud.Hud_RefillMagicPower())
        vars.submodule_index.* = 4;
}

pub export fn Module0E_0B_SaveMenu() callconv(.c) void {
    // This is the continue / save and quit menu, and the settings screen that
    // hangs off it.
    if (vars.player_is_indoors.* == 0)
        Overworld_DwDeathMountainPaletteAnimation();
    if (settings_menu.isOpen())
        return settings_menu.update();
    RenderText();
    vars.flag_update_hud_in_nmi.* = 0;
    vars.nmi_disable_core_updates.* = 0;
    if (vars.subsubmodule_index.* < 3) {
        vars.subsubmodule_index.* +%= 1;
    } else {
        vars.nmi_load_bg_from_vram.* = 0;
    }
    if (vars.submodule_index.* == 0) {
        vars.subsubmodule_index.* = 0;
        vars.nmi_load_bg_from_vram.* = 1;
        if (settings_menu.afterBoxClosed())
            return;
        if (vars.choice_in_multiselect_box.* != 0) {
            vars.sound_effect_ambient.* = 15;
            vars.main_module_index.* = 23;
            vars.submodule_index.* = 1;
            vars.index_of_changable_dungeon_objs[0] = 0;
            vars.index_of_changable_dungeon_objs[1] = 0;
        } else {
            vars.choice_in_multiselect_box.* = vars.choice_in_multiselect_box_bak.*;
        }
    }
}

pub export fn Module1B_SpawnSelect() callconv(.c) void {
    RenderText();
    if (vars.submodule_index.* != 0) return;
    vars.nmi_load_bg_from_vram.* = 0;
    load_gfx.EnableForceBlank();
    load_gfx.EraseTileMaps_normal();
    const bak = vars.which_starting_point.*;
    vars.which_starting_point.* = tables.kLocationMenuStartPos[vars.choice_in_multiselect_box.*];
    vars.subsubmodule_index.* = 0;
    misc.LoadDungeonRoomRebuildHUD();
    vars.which_starting_point.* = bak;
}

pub export fn CleanUpAndPrepDesertPrayerHDMA() callconv(.c) void {
    rtl.HdmaSetup(0, 0x2c80c, 0x41, 0, @truncate(WH0), 0);

    vars.W12SEL_copy.* = 0x33;
    vars.W34SEL_copy.* = 3;
    vars.WOBJSEL_copy.* = 0x33;
    vars.TMW_copy.* = vars.TM_copy.*;
    vars.TSW_copy.* = vars.TS_copy.*;
    vars.HDMAEN_copy.* = 0x80;
    @memset(vars.hdma_table_dynamic[0..240], 0);
}

pub export fn DesertPrayer_InitializeIrisHDMA() callconv(.c) void {
    CleanUpAndPrepDesertPrayerHDMA();
    vars.spotlight_var1.* = 0x26;
    loPtr(vars.spotlight_var2).* = 0;
    DesertPrayer_BuildIrisHDMATable();
    vars.subsubmodule_index.* +%= 1;
}

pub export fn DesertPrayer_BuildIrisHDMATable() callconv(.c) void {
    const r14 = vars.link_y_coord.* -% vars.BG2VOFS_copy2.* +% 12;
    vars.spotlight_y_lower.* = r14 -% vars.spotlight_var1.*;
    var r4: u16 = if (sign16(vars.spotlight_y_lower.*)) vars.spotlight_y_lower.* else 0;
    var k: u16 = undefined;
    vars.spotlight_y_upper.* = vars.spotlight_y_lower.* +% vars.spotlight_var1.* *% 2;
    vars.spotlight_var3.* = vars.link_x_coord.* -% vars.BG2HOFS_copy2.* +% 8;
    vars.spotlight_var4.* = 1;

    while (true) {
        var r0: u16 = 0x100;
        var r2: u16 = 0x100;
        const inside = sign16(vars.spotlight_y_lower.*) or
            (r4 >= vars.spotlight_y_lower.* and r4 < vars.spotlight_y_upper.*);
        if (!inside) {
            k = r4 -% 1;
        } else if (vars.spotlight_var1.* < vars.spotlight_var4.*) {
            vars.spotlight_var4.* = 1;
            vars.spotlight_y_lower.* = 0;
            r4 = vars.spotlight_y_upper.*;
            if (r4 >= 225) break;
            k = r4 -% 1;
        } else {
            const pair = DesertHDMA_CalculateIrisShapeLine();
            if (pair.a == 0) {
                vars.spotlight_y_lower.* = 0;
            } else {
                r2 = vars.spotlight_var3.* +% pair.b;
                r0 = vars.spotlight_var3.* -% pair.b;
            }
            k = r14 -% loPtr(vars.spotlight_var4).* -% 1;
        }
        const t6: u8 = if (r0 < 256) @truncate(r0) else if (r0 < 512) 255 else 0;
        const t7: u8 = if (r2 < 256) @truncate(r2) else 255;
        const r6 = @as(u16, t7) << 8 | t6;
        if (k < 240)
            vars.hdma_table_dynamic[k] = if (r6 == 0xffff) 0xff else r6;
        if (sign16(vars.spotlight_y_lower.*) or
            (r4 >= vars.spotlight_y_lower.* and r4 < vars.spotlight_y_upper.*))
        {
            k = @as(u16, loPtr(vars.spotlight_var4).*) -% 2 +% r14;
            if (k < 240)
                vars.hdma_table_dynamic[k] = if (r6 == 0xffff) 0xff else r6;
            vars.spotlight_var4.* +%= 1;
        }
        r4 +%= 1;
        if (!(sign16(r4) or r4 < 225)) break;
    }

    if (vars.subsubmodule_index.* != 4) return;
    if (loPtr(vars.spotlight_var2).* != 1 and
        (vars.filtered_joypad_H.* | vars.filtered_joypad_L.*) & 0xc0 != 0)
    {
        loPtr(vars.spotlight_var2).* = 1;
        loPtr(vars.spotlight_var1).* >>= 1;
    }
    var grew = false;
    if (loPtr(vars.spotlight_var2).* != 0) {
        loPtr(vars.spotlight_var1).* +%= 8;
        grew = loPtr(vars.spotlight_var1).* >= 0xc0;
    }
    if (grew) {
        vars.byte_7E02F0.* ^= 1;
        vars.music_control.* = 0xf3;
        vars.sound_effect_ambient.* = 0;
        vars.flag_unk1.* = 0;
        vars.some_animation_timer_steps.* = 0;
        vars.button_mask_b_y.* = 0;
        vars.link_state_bits.* = 0;
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
        vars.subsubmodule_index.* = 0;
        vars.submodule_index.* = 0;
        vars.main_module_index.* = vars.saved_module_for_menu.*;
        vars.TMW_copy.* = 0;
        vars.TSW_copy.* = 0;
        vars.W12SEL_copy.* = 0;
        vars.W34SEL_copy.* = 0;
        vars.WOBJSEL_copy.* = 0;
        load_gfx.IrisSpotlight_ResetTable();
    } else {
        vars.link_delay_timer_spin_attack.* -%= 1;
        if (sign8(vars.link_delay_timer_spin_attack.*)) {
            const i = vars.some_animation_timer_steps.* +% 1;
            if (i != 4)
                vars.some_animation_timer_steps.* = i;
            vars.link_delay_timer_spin_attack.* = tables.kPrayingScene_Delays[i];
        }
    }
}

pub export fn DesertHDMA_CalculateIrisShapeLine() callconv(.c) Pair16U {
    const t: u8 = @truncate(load_gfx.snes_divide(
        @as(u16, loPtr(vars.spotlight_var4).*) << 8,
        loPtr(vars.spotlight_var1).*,
    ) >> 1);
    const r6: u8 = if (loPtr(vars.spotlight_var2).* != 0)
        tables.kPrayingScene_Tab1[t]
    else
        tables.kPrayingScene_Tab0[t];
    var r8: u16 = @truncate((@as(u32, r6) * loPtr(vars.spotlight_var1).*) >> 8);
    if (loPtr(vars.spotlight_var2).* != 0)
        r8 <<= 1;
    return .{ .a = r6, .b = r8 };
}

pub export fn Animate_GAMEOVER_Letters() callconv(.c) void {
    switch (vars.ancilla_type[0]) {
        0 => vars.submodule_index.* +%= 1,
        1 => GameOverText_SweepLeft(),
        2 => GameOverText_UnfurlRight(),
        3 => GameOverText_Draw(),
        else => {},
    }
}

pub export fn GameOverText_SweepLeft() callconv(.c) void {
    var k: c_int = vars.flag_for_boomerang_in_place.*;
    vars.cur_object_index.* = @intCast(k);
    vars.ancilla_x_vel[@intCast(k)] = 0x80;
    Ancilla_MoveX(k);
    draw: {
        if (Ancilla_GetX(k) < tables.kGameOverText_Tab1[@intCast(k)]) {
            vars.ancilla_x_lo[@intCast(k)] = tables.kGameOverText_Tab1[@intCast(k)];
            k += 1;
            vars.flag_for_boomerang_in_place.* = @intCast(k);
            if (k == 8) {
                vars.flag_for_boomerang_in_place.* = 7;
                vars.ancilla_type[0] +%= 1;
                vars.hookshot_effect_index.* = 0;
                vars.sound_effect_2.* = 38;
                break :draw;
            }
        }
        if (k == 7) {
            var j: c_int = 6;
            while (j != vars.hookshot_effect_index.*) {
                vars.ancilla_x_lo[@intCast(j)] = vars.ancilla_x_lo[@intCast(k)];
                j -= 1;
            }
            if (Ancilla_GetX(k) < tables.kGameOverText_Tab1[vars.hookshot_effect_index.*])
                vars.hookshot_effect_index.* -%= 1;
        }
    }
    GameOverText_Draw();
}

pub export fn GameOverText_UnfurlRight() callconv(.c) void {
    var k: c_int = vars.flag_for_boomerang_in_place.*;
    vars.cur_object_index.* = @intCast(k);
    vars.ancilla_x_vel[@intCast(k)] = 0x60;
    Ancilla_MoveX(k);
    draw: {
        var j: c_int = vars.hookshot_effect_index.*;
        if (vars.ancilla_x_lo[@intCast(k)] >= tables.kGameOverText_Tab2[@intCast(j)]) {
            vars.ancilla_x_lo[@intCast(j)] = tables.kGameOverText_Tab2[@intCast(j)];
            vars.hookshot_effect_index.* +%= 1;
            if (vars.hookshot_effect_index.* == 8) {
                vars.submodule_index.* +%= 1;
                vars.ancilla_type[0] +%= 1;
                break :draw;
            }
        }
        const end: c_int = @as(c_int, vars.hookshot_effect_index.*) - 1;
        k = vars.flag_for_boomerang_in_place.*;
        j = k;
        while (true) {
            vars.ancilla_x_lo[@intCast(j)] = vars.ancilla_x_lo[@intCast(k)];
            j -= 1;
            if (j == end) break;
        }
    }
    GameOverText_Draw();
}

pub export fn Module12_GameOver() callconv(.c) void {
    kModule_Death[vars.submodule_index.*]();
    if (vars.submodule_index.* != 9)
        player_oam.LinkOam_Main();
}

pub export fn GameOver_AdvanceImmediately() callconv(.c) void {
    vars.submodule_index.* +%= 1;
    Death_Func1();
}

pub export fn Death_Func1() callconv(.c) void {
    vars.music_unk1_death.* = vars.music_unk1.*;
    vars.sound_effect_ambient_last_death.* = vars.sound_effect_ambient_last.*;
    vars.music_control.* = 241;
    vars.sound_effect_ambient.* = 5;
    vars.overworld_map_state.* = 5;
    vars.link_on_conveyor_belt.* = 0;
    vars.byte_7E0322.* = 0;
    vars.link_cape_mode.* = 0;
    vars.mapbak_bg1_x_offset.* = vars.palette_filter_countdown.*;
    vars.mapbak_bg1_y_offset.* = vars.darkening_or_lightening_screen.*;
    @memcpy(vars.mapbak_palette[0..128], vars.aux_palette_buffer[0..128]);
    @memset(vars.aux_palette_buffer[32 .. 32 + 96], 0);
    vars.palette_filter_countdown.* = 0;
    vars.darkening_or_lightening_screen.* = 0;
    vars.bg1_x_offset.* = 0;
    vars.bg1_y_offset.* = 0;
    vars.mapbak_CGWSEL.* = wordPtr(vars.CGWSEL_copy).*;
    vars.some_menu_ctr.* = 32;
    vars.hud_floor_changed_timer.* = 0;
    hud.Hud_FloorIndicator();
    vars.flag_update_hud_in_nmi.* +%= 1;
    vars.sound_effect_ambient.* = 5;
    vars.submodule_index.* +%= 1;
}

pub export fn GameOver_DelayBeforeIris() callconv(.c) void {
    vars.some_menu_ctr.* -%= 1;
    if (vars.some_menu_ctr.* != 0) return;
    Death_InitializeGameOverLetters();
    load_gfx.IrisSpotlight_close();
    vars.WOBJSEL_copy.* = 0x30;
    vars.W34SEL_copy.* = 0;
    vars.submodule_index.* +%= 1;
}

pub export fn GameOver_IrisWipe() callconv(.c) void {
    load_gfx.PaletteFilter_RestoreBGSubstractiveStrict();
    vars.main_palette_buffer[0] = vars.main_palette_buffer[32];
    const bak = vars.main_module_index.*;
    load_gfx.IrisSpotlight_ConfigureTable();
    vars.main_module_index.* = bak;
    if (vars.submodule_index.* != 0) return;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        vars.main_palette_buffer[0x20 + i] = 0x18;
        vars.main_palette_buffer[0x30 + i] = 0x18;
        vars.main_palette_buffer[0x40 + i] = 0x18;
        vars.main_palette_buffer[0x50 + i] = 0x18;
        vars.main_palette_buffer[0x60 + i] = 0x18;
        vars.main_palette_buffer[0x70 + i] = 0x18;
    }
    vars.main_palette_buffer[32] = 0x18;
    vars.main_palette_buffer[0] = 0x18;

    load_gfx.IrisSpotlight_ResetTable();
    vars.COLDATA_copy0.* = 32;
    vars.COLDATA_copy1.* = 64;
    vars.COLDATA_copy2.* = 128;
    vars.W12SEL_copy.* = 0;
    vars.W34SEL_copy.* = 0;
    vars.WOBJSEL_copy.* = 0;
    vars.submodule_index.* = 4;
    vars.flag_update_cgram_in_nmi.* +%= 1;
    vars.INIDISP_copy.* = 15;
    vars.TM_copy.* = 20;
    vars.TS_copy.* = 0;
    vars.CGADSUB_copy.* = 32;
    vars.some_menu_ctr.* = 64;
    loPtr(vars.palette_filter_countdown).* = 0;
    loPtr(vars.darkening_or_lightening_screen).* = 0;
    Death_PrepFaint();
}

pub export fn GameOver_SplatAndFade() callconv(.c) void {
    if (vars.some_menu_ctr.* != 0) {
        vars.some_menu_ctr.* -%= 1;
        return;
    }
    load_gfx.PaletteFilter_RestoreBGSubstractiveStrict();
    vars.main_palette_buffer[0] = vars.main_palette_buffer[32];
    if (loPtr(vars.darkening_or_lightening_screen).* != 0xff) return;
    vars.mosaic_level.* = 0;
    vars.mosaic_inc_or_dec.* = 0;
    vars.MOSAIC_copy.* = 3;

    var i: usize = 0;
    while (i != 4) : (i += 1) {
        if (vars.link_bottle_info[i] == 6) {
            vars.link_bottle_info[i] = 2;
            vars.some_menu_ctr.* = 12;
            vars.load_chr_halfslot_even_odd.* = 15;
            load_gfx.Graphics_LoadChrHalfSlot();
            vars.load_chr_halfslot_even_odd.* = 0;
            vars.submodule_index.* = 10;
            return;
        }
    }
    vars.index_of_changable_dungeon_objs[0] = 0;
    vars.index_of_changable_dungeon_objs[1] = 0;
    vars.nmi_subroutine_index.* = 22;
    vars.nmi_disable_core_updates.* = 22;
    vars.submodule_index.* +%= 1;
}

pub export fn Death_Func6() callconv(.c) void {
    vars.some_menu_ctr.* = 12;
    vars.load_chr_halfslot_even_odd.* = 15;
    load_gfx.Graphics_LoadChrHalfSlot();
    vars.load_chr_halfslot_even_odd.* = 0;
    vars.palette_sp6r_indoors.* = 5;
    vars.overworld_palette_aux_or_main.* = 0x200;
    load_gfx.Palette_Load_SpriteEnvironment_Dungeon();
    load_gfx.Palette_Load_SpriteMain();
    vars.flag_update_cgram_in_nmi.* +%= 1;
    vars.submodule_index.* +%= 1;
    Death_PlayerSwoon();
}

pub export fn Death_Func4() callconv(.c) void {
    Death_PlayerSwoon();
}

pub export fn Animate_GAMEOVER_Letters_bounce() callconv(.c) void {
    Animate_GAMEOVER_Letters();
}

pub export fn GameOver_Finalize_GAMEOVR() callconv(.c) void {
    Animate_GAMEOVER_Letters();
    const bak1 = vars.main_module_index.*;
    const bak2 = vars.submodule_index.*;
    vars.messaging_module.* = 2;
    RenderText();
    vars.submodule_index.* = bak2 +% 1;
    vars.main_module_index.* = bak1;
    vars.some_menu_ctr.* = 2;
    vars.music_control.* = 11;
}

pub export fn GameOver_SaveAndOrContinue() callconv(.c) void {
    GameOver_AnimateChoiceFairy();
    // The C tests `ancilla_type`, an array that decays to a non-null pointer,
    // so this branch is always taken.
    Animate_GAMEOVER_Letters();

    // `goto do_inc` jumps into the nested if, past the counter handling.
    var changed = false;
    var inc = false;
    if (vars.filtered_joypad_H.* & 0x20 != 0) {
        changed = true;
        inc = true;
    } else {
        vars.some_menu_ctr.* -%= 1;
        if (vars.some_menu_ctr.* == 0) {
            vars.some_menu_ctr.* = 1;
            if (vars.joypad1H_last.* & 12 != 0) {
                changed = true;
                inc = vars.joypad1H_last.* & 4 != 0;
            }
        }
    }
    if (changed) {
        if (inc) {
            vars.subsubmodule_index.* +%= 1;
            if (vars.subsubmodule_index.* >= 3)
                vars.subsubmodule_index.* = 0;
        } else {
            vars.subsubmodule_index.* -%= 1;
            if (sign8(vars.subsubmodule_index.*))
                vars.subsubmodule_index.* = 2;
        }
        vars.some_menu_ctr.* = 12;
        vars.sound_effect_2.* = 32;
    }

    if ((vars.filtered_joypad_L.* & 0xc0 | vars.filtered_joypad_H.*) & 0xd0 == 0)
        return;
    vars.sound_effect_1.* = 44;
    // Only death with save/continue or save/quit counts as a death
    Death_Func15(vars.subsubmodule_index.* != 2);
}

pub export fn Death_Func15(count_as_death: bool) callconv(.c) void {
    vars.music_control.* = 0xf1;
    if (vars.player_is_indoors.* != 0)
        Dungeon_FlagRoomData_Quadrants();
    AdjustLinkBunnyStatus();
    if (vars.sram_progress_indicator.* < 3) {
        vars.savegame_is_darkworld.* = 0;
        if (vars.link_item_moon_pearl.* == 0)
            ForceNonbunnyStatus();
    }
    if (vars.dungeon_room_index.* == 0)
        vars.player_is_indoors.* = 0;

    ResetSomeThingsAfterDeath(@truncate(vars.dungeon_room_index.*));
    const fi = vars.follower_indicator.*;
    if (fi == 6 or fi == 9 or fi == 10 or fi == 13)
        vars.follower_indicator.* = 0;

    vars.link_health_current.* = kHealthAfterDeath[vars.link_health_capacity.* >> 3];
    vars.death_var4.* = vars.link_health_current.*;
    const i = loPtr(vars.cur_palace_index_x2).*;
    if (i != 0xff)
        vars.link_keys_earned_per_dungeon[(if (i == 2) @as(u8, 0) else i) >> 1] = vars.link_num_keys.*;
    Sprite_ResetAll();
    if (vars.death_var2.* == 0xffff and
        (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes == 0 or count_as_death))
        vars.death_save_counter.* +%= 1;
    vars.death_var5.* +%= 1;

    if (vars.subsubmodule_index.* != 1) {
        // `goto outdoors` skips straight to the darkworld room fixup.
        var outdoors = false;
        if (vars.player_is_indoors.* == 0) {
            outdoors = true;
        } else if (vars.follower_indicator.* != 1 and loPtr(vars.cur_palace_index_x2).* != 255) {
            vars.death_var4.* = 0;
        } else {
            vars.queued_music_control.* = 0;
            vars.player_is_indoors.* = 0;
            outdoors = true;
        }
        if (outdoors and vars.savegame_is_darkworld.* != 0)
            vars.dungeon_room_index.* = 32;

        if (vars.sram_progress_indicator.* != 0) {
            if (vars.subsubmodule_index.* == 0)
                SaveGameFile();
            vars.main_module_index.* = 5;
            vars.submodule_index.* = 0;
            vars.nmi_load_bg_from_vram.* = 0;
        } else {
            const slot = srm_var1().*;
            const offs = tables.kSrmOffsets[(slot >> 1) - 1];
            std.mem.writeInt(u16, g_ram[0..2], offs, .little);
            vars.death_var5.* = 0;
            CopySaveToWRAM();
        }
    } else {
        if (vars.sram_progress_indicator.* != 0)
            SaveGameFile();
        vars.TM_copy.* = 16;
        vars.player_is_indoors.* = 0;
        attract.Death_Func31();
        vars.death_var4.* = 0;
        vars.death_var5.* = 0;
        vars.queued_music_control.* = 0;
        vars.BG1HOFS_copy2.* = 0;
        vars.BG2HOFS_copy2.* = 0;
        vars.BG3HOFS_copy2.* = 0;
        vars.BG1VOFS_copy2.* = 0;
        vars.BG2VOFS_copy2.* = 0;
        vars.BG3VOFS_copy2.* = 0;
        vars.BG1HOFS_copy.* = 0;
        vars.BG2HOFS_copy.* = 0;
        vars.BG1VOFS_copy.* = 0;
        vars.BG2VOFS_copy.* = 0;
        @memset(@as([*]u8, @ptrCast(vars.save_dung_info))[0 .. 256 * 5], 0);
        vars.flag_which_music_type.* = 0;
        misc.LoadOverworldSongs();
    }
}

pub export fn GameOver_AnimateChoiceFairy() callconv(.c) void {
    SetOamPlain(
        oam_buf + 0x14,
        0x34,
        tables.kDeath_SprY0[vars.subsubmodule_index.*],
        tables.kDeath_SprChar0[vars.frame_counter.* >> 3 & 1],
        0x78,
        2,
    );
}

pub export fn GameOver_InitializeRevivalFairy() callconv(.c) void {
    ConfigureRevivalAncillae();
    vars.link_hearts_filler.* = 56;
    vars.submodule_index.* +%= 1;
    vars.overworld_map_state.* = 0;
}

pub export fn RevivalFairy_Main_bounce() callconv(.c) void {
    RevivalFairy_Main();
}

pub export fn GameOver_RiseALittle() callconv(.c) void {
    if (vars.link_hearts_filler.* == 0) {
        @memcpy(vars.aux_palette_buffer[0..128], vars.mapbak_palette[0..128]);
        @memset(vars.main_palette_buffer[32 .. 32 + 96], 0);
        vars.main_palette_buffer[0] = 0;
        vars.palette_filter_countdown.* = 0;
        vars.darkening_or_lightening_screen.* = 2;
        wordPtr(vars.CGWSEL_copy).* = vars.mapbak_CGWSEL.*;
        vars.submodule_index.* +%= 1;
    }
    RevivalFairy_Main();
    hud.Hud_RefillLogic();
}

pub export fn GameOver_Restore0D() callconv(.c) void {
    if (vars.is_doing_heart_animation.* == 0) {
        vars.load_chr_halfslot_even_odd.* = 1;
        load_gfx.Graphics_LoadChrHalfSlot();
        Dungeon_ApproachFixedColor_variable(vars.overworld_fixed_color_plusminus.*);
        vars.submodule_index.* +%= 1;
    }
    RevivalFairy_Main();
    hud.Hud_RefillLogic();
}

pub export fn GameOver_Restore0E() callconv(.c) void {
    load_gfx.Graphics_LoadChrHalfSlot();
    vars.TS_copy.* = vars.mapbak_TS.*;
    vars.submodule_index.* +%= 1;
}

pub export fn GameOver_ResituateLink() callconv(.c) void {
    load_gfx.PaletteFilter_RestoreBGAdditiveStrict();
    vars.main_palette_buffer[0] = vars.main_palette_buffer[32];
    if (loPtr(vars.palette_filter_countdown).* != 32) return;
    if (vars.player_is_indoors.* == 0)
        Overworld_SetFixedColAndScroll();
    vars.TS_copy.* = vars.mapbak_TS.*;
    vars.main_module_index.* = vars.saved_module_for_menu.*;
    vars.submodule_index.* = 0;
    vars.countdown_for_blink.* = 144;
    vars.music_control.* = vars.music_unk1_death.*;
    vars.sound_effect_ambient.* = vars.sound_effect_ambient_last_death.*;
    vars.palette_filter_countdown.* = vars.mapbak_bg1_x_offset.*;
    vars.darkening_or_lightening_screen.* = vars.mapbak_bg1_y_offset.*;
}

pub export fn Module0E_0A_FluteMenu() callconv(.c) void {
    switch (vars.overworld_map_state.*) {
        0 => WorldMap_FadeOut(),
        1 => {
            vars.birdtravel_var1[0] = 0;
            WorldMap_LoadLightWorldMap();
        },
        2 => WorldMap_LoadSpriteGFX(),
        3 => WorldMap_Brighten(),
        4 => {
            vars.some_menu_ctr.* = 0x10;
            vars.overworld_map_state.* +%= 1;
        },
        5 => FluteMenu_HandleSelection(),
        6 => WorldMap_RestoreGraphics(),
        7 => FluteMenu_LoadSelectedScreen(),
        8 => Overworld_LoadOverlayAndMap(),
        9 => FluteMenu_FadeInAndQuack(),
        else => unreachable, // assert(0)
    }
}

pub export fn FluteMenu_HandleSelection() callconv(.c) void {
    var pt: Point16U = undefined;

    if (vars.some_menu_ctr.* == 0) {
        if ((vars.joypad1L_last.* | vars.joypad1H_last.*) & 0xc0 != 0) {
            if (features.enhanced_features0.* & features.kFeatures0_CancelBirdTravel != 0)
                vars.some_menu_ctr.* = vars.joypad1L_last.*;
            vars.overworld_map_state.* +%= 1;
            return;
        }
    } else {
        vars.some_menu_ctr.* -%= 1;
    }
    if (vars.filtered_joypad_H.* & 10 != 0) {
        vars.birdtravel_var1[0] -%= 1;
        vars.sound_effect_2.* = 32;
    }
    if (vars.filtered_joypad_H.* & 5 != 0) {
        vars.birdtravel_var1[0] +%= 1;
        vars.sound_effect_2.* = 32;
    }
    vars.birdtravel_var1[0] &= 7;
    if (vars.frame_counter.* & 0x10 != 0 and WorldMap_CalculateOamCoordinates(&pt))
        WorldMap_AddSprite(16, 2, 0x3e, 0, pt.x -% 4, pt.y -% 4);

    const ybak = vars.link_y_coord_spexit.*;
    const xbak = vars.link_x_coord_spexit.*;
    var i: i32 = 7;
    while (i >= 0) : (i -= 1) {
        const ii: usize = @intCast(i);
        vars.bird_travel_x_lo[ii] = tables.kBirdTravel_x_lo[ii];
        vars.bird_travel_x_hi[ii] = tables.kBirdTravel_x_hi[ii];
        vars.link_x_coord_spexit.* = @as(u16, tables.kBirdTravel_x_hi[ii]) << 8 | tables.kBirdTravel_x_lo[ii];

        vars.bird_travel_y_lo[ii] = tables.kBirdTravel_y_lo[ii];
        vars.bird_travel_y_hi[ii] = tables.kBirdTravel_y_hi[ii];
        vars.link_y_coord_spexit.* = @as(u16, tables.kBirdTravel_y_hi[ii]) << 8 | tables.kBirdTravel_y_lo[ii];

        if (WorldMap_CalculateOamCoordinates(&pt)) {
            const flags: u8 = if (ii == vars.birdtravel_var1[0])
                0x30 +% (vars.frame_counter.* & 6)
            else
                0x32;
            WorldMap_AddSprite(i, 0, flags, tables.kBirdTravel_tab1[ii], pt.x, pt.y);
        }
    }
    vars.link_x_coord_spexit.* = xbak;
    vars.link_y_coord_spexit.* = ybak;
}

pub export fn FluteMenu_LoadSelectedScreen() callconv(.c) void {
    vars.save_ow_event_info[0x3b] &= ~@as(u8, 0x20);
    vars.save_ow_event_info[0x7b] &= ~@as(u8, 0x20);
    vars.save_dung_info[267] &= ~@as(u16, 0x80);
    vars.save_dung_info[40] &= ~@as(u16, 0x100);

    // This is kFeatures0_CancelBirdTravel
    if (vars.some_menu_ctr.* & 0x40 == 0)
        FluteMenu_LoadTransport();

    FluteMenu_LoadSelectedScreenPalettes();
    const t: u8 = @truncate(vars.overworld_screen_index.* & 0xbf);
    load_gfx.DecompressAnimatedOverworldTiles(if (t == 3 or t == 5 or t == 7) 0x58 else 0x5a);
    Overworld_SetFixedColAndScroll();
    vars.overworld_palette_aux_or_main.* = 0;
    vars.hud_palette.* = 0;
    load_gfx.InitializeTilesets();
    vars.overworld_map_state.* +%= 1;
    loPtr(vars.dung_draw_width_indicator).* = 0;
    Overworld_LoadOverlays2();
    vars.submodule_index.* -%= 1;
    vars.sound_effect_2.* = 16;
    const m = vars.overworld_music[loPtr(vars.overworld_screen_index).*];
    vars.sound_effect_ambient.* = m >> 4;
    vars.music_control.* = if (audio.ZeldaIsPlayingMusicTrack(m & 0xf)) 0xf3 else m & 0xf;
}

pub export fn Overworld_LoadOverlayAndMap() callconv(.c) void {
    const bak1 = wordPtr(vars.main_module_index).*;
    const bak2 = wordPtr(vars.overworld_map_state).*;
    Overworld_LoadAndBuildScreen();
    wordPtr(vars.overworld_map_state).* = bak2 +% 1;
    wordPtr(vars.main_module_index).* = bak1;
}

pub export fn FluteMenu_FadeInAndQuack() callconv(.c) void {
    vars.INIDISP_copy.* +%= 1;
    if (vars.INIDISP_copy.* == 15) {
        BirdTravel_Finish_Doit();
    } else {
        Sprite_Main();
    }
}

pub export fn BirdTravel_Finish_Doit() callconv(.c) void {
    vars.overworld_map_state.* = 0;
    vars.subsubmodule_index.* = 0;
    vars.main_module_index.* = vars.saved_module_for_menu.*;
    vars.submodule_index.* = 0;
    vars.HDMAEN_copy.* = vars.mapbak_HDMAEN.*;
    AddBirdTravelSomething(0x27, 4);
    Sprite_Main();
}

pub export fn Messaging_OverworldMap() callconv(.c) void {
    switch (vars.overworld_map_state.*) {
        0 => WorldMap_FadeOut(),
        1 => WorldMap_LoadLightWorldMap(),
        2 => WorldMap_LoadDarkWorldMap(),
        3 => WorldMap_LoadSpriteGFX(),
        4 => WorldMap_Brighten(),
        5 => WorldMap_PlayerControl(),
        6 => WorldMap_RestoreGraphics(),
        7 => WorldMap_ExitMap(),
        else => {},
    }
}

pub export fn WorldMap_FadeOut() callconv(.c) void {
    vars.INIDISP_copy.* -%= 1;
    if (vars.INIDISP_copy.* != 0) return;
    vars.mapbak_HDMAEN.* = vars.HDMAEN_copy.*;
    load_gfx.EnableForceBlank();
    vars.MOSAIC_copy.* = 3;
    vars.overworld_map_state.* +%= 1;
    wordPtr(vars.mapbak_TM).* = wordPtr(vars.TM_copy).*;
    vars.mapbak_BG1HOFS_copy2.* = vars.BG1HOFS_copy2.*;
    vars.mapbak_BG2HOFS_copy2.* = vars.BG2HOFS_copy2.*;
    vars.mapbak_BG1VOFS_copy2.* = vars.BG1VOFS_copy2.*;
    vars.mapbak_BG2VOFS_copy2.* = vars.BG2VOFS_copy2.*;
    vars.BG3HOFS_copy2.* = 0;
    vars.BG2HOFS_copy2.* = 0;
    vars.BG1HOFS_copy2.* = 0;
    vars.BG3VOFS_copy2.* = 0;
    vars.BG2VOFS_copy2.* = 0;
    vars.BG1VOFS_copy2.* = 0;
    vars.mapbak_CGWSEL.* = wordPtr(vars.CGWSEL_copy).*;
    vars.link_dma_graphics_index.* = 0x1fc;
    if (loPtr(vars.overworld_screen_index).* < 0x80) {
        vars.link_y_coord_spexit.* = vars.link_y_coord.*;
        vars.link_x_coord_spexit.* = vars.link_x_coord.*;
    }
    if (vars.sram_progress_indicator.* < 2) {
        vars.CGWSEL_copy.* = 0x80;
        vars.CGADSUB_copy.* = 0x61;
    }
    vars.sound_effect_2.* = 16;
    vars.sound_effect_ambient.* = 5;
    vars.music_control.* = 0xf2;
    vars.BGMODE_copy.* = 7;
}

pub export fn WorldMap_LoadLightWorldMap() callconv(.c) void {
    WorldMap_FillTilemapWithEF();
    vars.TM_copy.* = 0x11;
    vars.TS_copy.* = 0;
    TransferMode7Characters();
    WorldMap_SetUpHDMA();
    load_gfx.LoadOverworldMapPalette();
    load_gfx.LoadActualGearPalettes();
    vars.flag_update_cgram_in_nmi.* +%= 1;
    vars.nmi_subroutine_index.* = 7;
    vars.INIDISP_copy.* = 0;
    vars.nmi_disable_core_updates.* +%= 1;
    vars.overworld_map_state.* +%= 1;
}

pub export fn WorldMap_LoadDarkWorldMap() callconv(.c) void {
    if (vars.overworld_screen_index.* & 0x40 != 0) {
        const dst: [*]u8 = @ptrCast(vars.uvram);
        @memcpy(dst[0..1024], kDarkOverworldTilemap()[0..1024]);
        vars.nmi_subroutine_index.* = 21;
    }
    vars.overworld_map_state.* +%= 1;
}

pub export fn WorldMap_LoadSpriteGFX() callconv(.c) void {
    vars.load_chr_halfslot_even_odd.* = 0x10;
    load_gfx.Graphics_LoadChrHalfSlot();
    vars.load_chr_halfslot_even_odd.* = 0;
    vars.overworld_map_state.* +%= 1;
}

pub export fn WorldMap_Brighten() callconv(.c) void {
    vars.INIDISP_copy.* +%= 1;
    if (vars.INIDISP_copy.* == 15)
        vars.overworld_map_state.* +%= 1;
}

pub export fn DidPressButtonForMap() callconv(.c) bool {
    if (features.hud_cur_item_x.* != 0) {
        return vars.filtered_joypad_H.* & 0x20 != 0; // select
    } else {
        return vars.filtered_joypad_L.* & 0x40 != 0; // x
    }
}

pub export fn WorldMap_PlayerControl() callconv(.c) void {
    if (vars.overworld_map_flags.* & 0x80 != 0) {
        vars.overworld_map_flags.* &= ~@as(u8, 0x80);
        OverworldMap_SetupHdma();
    }

    if (vars.overworld_map_flags.* == 0 and DidPressButtonForMap()) { // X
        // getout
        vars.overworld_map_state.* +%= 1;
        return;
    }
    if (loPtr(vars.dung_draw_width_indicator).* != 0) {
        loPtr(vars.dung_draw_width_indicator).* -%= 1;
    } else if (vars.filtered_joypad_L.* & 0x30 != 0 or DidPressButtonForMap()) {
        // next zoom level
        vars.sound_effect_2.* = 36;
        loPtr(vars.dung_draw_width_indicator).* = 8;

        const t = vars.overworld_map_flags.* ^ 1;
        vars.overworld_map_flags.* = t | 0x80;
        vars.timer_for_mode7_zoom.* = tables.kOverworldMap_Timer[t];
        if (vars.timer_for_mode7_zoom.* == 12) {
            vars.BG1VOFS_copy2.* = ((vars.link_y_coord_spexit.* >> 4) -% 0x48) & ~@as(u16, 1);
            vars.M7Y_copy.* = vars.BG1VOFS_copy2.* +% 0x100;
            const t0 = (vars.link_x_coord_spexit.* >> 4) -% 0x80;
            const t1 = (5 *% (if (sign16(t0)) 0 -% t0 else t0)) >> 1;
            const t2 = if (sign16(t0)) 0 -% t1 else t1;
            vars.BG1HOFS_copy2.* = (t2 +% 0x80) & ~@as(u16, 1);
        } else {
            vars.BG1VOFS_copy2.* = 200;
            vars.M7Y_copy.* = 200 + 256;
            vars.BG1HOFS_copy2.* = 128;
        }
    }

    if (vars.overworld_map_flags.* != 0) {
        var k: usize = (vars.joypad1H_last.* & 12) >> 1;
        if (vars.BG1VOFS_copy2.* != @as(u16, @bitCast(tables.kOverworldMap_Table2[k]))) {
            vars.BG1VOFS_copy2.* +%= @bitCast(tables.kOverworldMap_Table3[k]);
            vars.M7Y_copy.* = vars.BG1VOFS_copy2.* +% 0x100;
        }
        k = @as(usize, vars.joypad1H_last.* & 3) * 2 + 1;
        if (vars.BG1HOFS_copy2.* != @as(u16, @bitCast(tables.kOverworldMap_Table2[k])))
            vars.BG1HOFS_copy2.* +%= @bitCast(tables.kOverworldMap_Table3[k]);
    }
    WorldMap_HandleSprites();
}

pub export fn WorldMap_RestoreGraphics() callconv(.c) void {
    vars.INIDISP_copy.* -%= 1;
    if (vars.INIDISP_copy.* != 0) return;
    load_gfx.EnableForceBlank();
    vars.overworld_map_state.* +%= 1;
    @memcpy(vars.main_palette_buffer[0..256], vars.aux_palette_buffer[0..256]);
    wordPtr(vars.CGWSEL_copy).* = vars.mapbak_CGWSEL.*;
    vars.BG3VOFS_copy2.* = 0;
    vars.BG3HOFS_copy2.* = 0;
    vars.BG1HOFS_copy2.* = vars.mapbak_BG1HOFS_copy2.*;
    vars.BG2HOFS_copy2.* = vars.mapbak_BG2HOFS_copy2.*;
    vars.BG1VOFS_copy2.* = vars.mapbak_BG1VOFS_copy2.*;
    vars.BG2VOFS_copy2.* = vars.mapbak_BG2VOFS_copy2.*;
    wordPtr(vars.TM_copy).* = wordPtr(vars.mapbak_TM).*;
    Attract_SetUpConclusionHDMA();
}

pub export fn Attract_SetUpConclusionHDMA() callconv(.c) void {
    rtl.HdmaSetup(0xABDDD, 0xABDDD, 0x42, @truncate(M7A), @truncate(M7D), 0);
    vars.HDMAEN_copy.* = 0x80;
    vars.BGMODE_copy.* = 9;
    vars.nmi_disable_core_updates.* = 0;
}

pub export fn WorldMap_ExitMap() callconv(.c) void {
    vars.overworld_palette_aux_or_main.* = 0;
    vars.hud_palette.* = 0;
    load_gfx.InitializeTilesets();
    vars.flag_update_cgram_in_nmi.* +%= 1;
    loPtr(vars.dung_draw_width_indicator).* = 0;
    vars.overworld_map_state.* = 0;
    vars.subsubmodule_index.* = 0;
    vars.main_module_index.* = vars.saved_module_for_menu.*;
    vars.submodule_index.* = 32;
    vars.vram_upload_offset.* = 0;
    vars.HDMAEN_copy.* = vars.mapbak_HDMAEN.*;
    vars.sound_effect_ambient.* = vars.overworld_music[loPtr(vars.overworld_screen_index).*] >> 4;
    vars.sound_effect_2.* = 0x10;
    vars.music_control.* = 0xf3;
}

pub export fn WorldMap_SetUpHDMA() callconv(.c) void {
    vars.BG1HOFS_copy2.* = 0x80;
    vars.BG1VOFS_copy2.* = 0xc8;
    vars.M7Y_copy.* = 0x1c9;
    vars.M7X_copy.* = 0x100;
    vars.W12SEL_copy.* = 0;
    vars.W34SEL_copy.* = 0;
    vars.WOBJSEL_copy.* = 0;
    vars.TMW_copy.* = 0;
    vars.TSW_copy.* = 0;

    if (vars.main_module_index.* == 20) {
        rtl.HdmaSetup(0xABDDD, 0xABDDD, 0x42, @truncate(M7A), @truncate(M7D), 0);
        vars.HDMAEN_copy.* = 0xc0;
    } else if (vars.submodule_index.* != 10) {
        vars.byte_7E0635.* = 4;
        vars.timer_for_mode7_zoom.* = 12;
        vars.overworld_map_flags.* = 1;
        vars.BG1VOFS_copy2.* = ((vars.link_y_coord_spexit.* >> 4) -% 0x48) & ~@as(u16, 1);
        vars.M7Y_copy.* = vars.BG1VOFS_copy2.* +% 0x100;
        const t0 = (vars.link_x_coord_spexit.* >> 4) -% 0x80;
        const t1 = (5 *% (if (sign16(t0)) 0 -% t0 else t0)) >> 1;
        const t2 = if (sign16(t0)) 0 -% t1 else t1;
        vars.BG1HOFS_copy2.* = (t2 +% 0x80) & ~@as(u16, 1);
        OverworldMap_SetupHdma();
        vars.HDMAEN_copy.* = 0xc0;
    } else {
        vars.byte_7E0635.* = 4;
        vars.timer_for_mode7_zoom.* = 33;
        vars.overworld_map_flags.* = 0;
        rtl.HdmaSetup(0xABDCF, 0xABDCF, 0x42, @truncate(M7A), @truncate(M7D), 10);
        vars.HDMAEN_copy.* = 0xc0;
    }
}

pub export fn WorldMap_FillTilemapWithEF() callconv(.c) void {
    // Only the low byte of each vram word.
    const dst: [*]u8 = @ptrCast(g_zenv.vram.?);
    var i: usize = 0;
    while (i != 0x4000) : (i += 1)
        dst[i * 2] = 0xef;
}

/// One of the seven crystal/pendant markers. The C repeats this body verbatim
/// per marker; `goto endif_crystalN` just skips that marker's draw.
fn worldMapDrawMarker(
    k: usize,
    idx: c_int,
    spr: c_int,
    check_pendant: bool,
    xs: []const u16,
    ys: []const u16,
    tabs: []const u16,
) void {
    if (check_pendant and OverworldMap_CheckForPendant(idx)) return;
    if (OverworldMap_CheckForCrystal(idx)) return;
    if (sign16(xs[k])) return;

    vars.link_x_coord_spexit.* = xs[k];
    vars.link_y_coord_spexit.* = ys[k];
    const t: u8 = @truncate(tabs[k] >> 8);
    if (t != 0) {
        if (t != 100 and vars.frame_counter.* & 0x10 != 0) return;
        vars.link_x_coord_spexit.* -%= 4;
        vars.link_y_coord_spexit.* -%= 4;
    }
    var pt: Point16U = undefined;
    if (WorldMap_CalculateOamCoordinates(&pt)) {
        var info = tabs[k];
        var ext: u8 = 2;
        if (info >> 8 == 0) {
            info = @as(u16, tables.kOwMap_tab2[vars.frame_counter.* >> 3 & 3]) << 8 | 0x32;
            ext = 0;
        }
        WorldMap_AddSprite(spr, ext, @truncate(info), @truncate(info >> 8), pt.x, pt.y);
    }
}

pub export fn WorldMap_HandleSprites() callconv(.c) void {
    var pt: Point16U = undefined;

    if (vars.frame_counter.* & 0x10 != 0 and WorldMap_CalculateOamCoordinates(&pt))
        WorldMap_AddSprite(0, 2, 0x3e, 0, pt.x -% 4, pt.y -% 4);

    const ybak = vars.link_y_coord_spexit.*;
    const xbak = vars.link_x_coord_spexit.*;

    out: {
        const j: usize = 15;
        if (loPtr(vars.overworld_screen_index).* < 0x40 and
            (vars.bird_travel_x_lo[j] | vars.bird_travel_x_hi[j] |
                vars.bird_travel_y_lo[j] | vars.bird_travel_y_hi[j]) != 0)
        {
            if (vars.frame_counter.* == 0)
                vars.birdtravel_var1[j] +%= 1;
            vars.link_x_coord_spexit.* = @as(u16, vars.bird_travel_x_hi[j]) << 8 | vars.bird_travel_x_lo[j];
            vars.link_y_coord_spexit.* = @as(u16, vars.bird_travel_y_hi[j]) << 8 | vars.bird_travel_y_lo[j];
            if (WorldMap_CalculateOamCoordinates(&pt))
                WorldMap_AddSprite(15, 2, tables.kOverworldMap_Table4[vars.frame_counter.* >> 1 & 3], 0x6a, pt.x, pt.y);
        }

        if (vars.save_ow_event_info[0x5b] & 0x20 != 0 or
            (((@intFromBool(vars.savegame_map_icons_indicator.* >= 6) ^ vars.is_in_dark_world.*) & 1) != 0))
            break :out;

        const k: usize = vars.savegame_map_icons_indicator.*;

        worldMapDrawMarker(k, 0, 14, true, &tables.kOwMapCrystal0_x, &tables.kOwMapCrystal0_y, &tables.kOwMapCrystal0_tab);
        worldMapDrawMarker(k, 1, 13, true, &tables.kOwMapCrystal1_x, &tables.kOwMapCrystal1_y, &tables.kOwMapCrystal1_tab);
        worldMapDrawMarker(k, 2, 12, true, &tables.kOwMapCrystal2_x, &tables.kOwMapCrystal2_y, &tables.kOwMapCrystal2_tab);
        worldMapDrawMarker(k, 3, 11, false, &tables.kOwMapCrystal3_x, &tables.kOwMapCrystal3_y, &tables.kOwMapCrystal3_tab);
        worldMapDrawMarker(k, 4, 10, false, &tables.kOwMapCrystal4_x, &tables.kOwMapCrystal4_y, &tables.kOwMapCrystal4_tab);
        worldMapDrawMarker(k, 5, 9, false, &tables.kOwMapCrystal5_x, &tables.kOwMapCrystal5_y, &tables.kOwMapCrystal5_tab);
        worldMapDrawMarker(k, 6, 8, false, &tables.kOwMapCrystal6_x, &tables.kOwMapCrystal6_y, &tables.kOwMapCrystal6_tab);
    }

    vars.link_x_coord_spexit.* = xbak;
    vars.link_y_coord_spexit.* = ybak;
}

fn WorldMap_CalculateOamCoordinates(pt: *Point16U) bool {
    if (vars.overworld_map_flags.* == 0) {
        const j: usize = @intCast((0 -% (vars.link_y_coord_spexit.* >> 4)) +%
            vars.M7Y_copy.* +% (vars.link_y_coord_spexit.* >> 3 & 1) -% 0xc0);
        const t0 = tables.kOverworldMap_tab1[j];
        const yval: u8 = @truncate((13 * @as(u16, t0)) >> 4);

        var at: u8 = @truncate(vars.link_x_coord_spexit.* >> 4);
        const below = at < 0x80;
        at -%= 0x80;
        if (sign8(at)) at = ~at;

        const t1: u8 = @truncate(((@as(u16, if (yval < 224) yval else 0) * 0x54) >> 8) + 0xb2);
        const t2: u8 = @truncate((@as(u16, at) * t1) >> 8);
        const t3: u8 = if (below) 0x80 -% t2 else t2 +% 0x80;

        pt.x = @as(u16, t3) -% vars.BG1HOFS_copy2.* +% 0x80;
        pt.y = @as(u16, yval) + 12;
        return true;
    } else {
        const t0 = (0 -% (vars.link_y_coord_spexit.* >> 4)) +% vars.M7Y_copy.* -% 0x80;
        if (t0 >= 0x100) return false;
        const t1 = (t0 *% 37) >> 4;
        if (t1 >= 333) return false;
        const yval = tables.kOverworldMap_tab1[t1];
        var t2 = vars.link_x_coord_spexit.*;
        const below = t2 < 0x7F8;
        t2 -%= 0x7f8;
        if (sign16(t2)) t2 = 0 -% t2;
        const t3: u8 = if (yval < 226) yval else 0;
        const t4: u8 = @truncate(((@as(u16, t3) * 84) >> 8) + 178); // r0
        const t5: u8 = @truncate((@as(u16, @as(u8, @truncate(t2))) * t4) >> 8); // r1
        const t6: u16 = @as(u16, @as(u8, @truncate(t2 >> 8))) *% t4 +% t5;
        const t7: u16 = if (below) 0x800 -% t6 else t6 +% 0x800;
        const below2 = t7 < 0x800;
        const t7b = t7 -% 0x800;
        const t8: u16 = if (below2) 0 -% t7b else t7b;
        const t9: u8 = @truncate((@as(u16, @as(u8, @truncate(t8))) * 45) >> 8);
        const t10: u16 = (t8 >> 8) *% 45 +% t9;
        const t11: u16 = if (below2) 0x80 -% t10 else t10 +% 0x80;
        const xval = t11 -% vars.BG1HOFS_copy2.*;
        const xt: u16 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x48 else 0;
        if (xval +% 0x80 +% xt >= 0x100 + xt * 2)
            return false;
        pt.x = xval +% 0x81;
        pt.y = @as(u16, yval) + 16;
        return true;
    }
}

fn WorldMap_AddSprite(spr: c_int, big_in: u8, flags_in: u8, ch_in: u8, x_in: u16, y_in: u16) void {
    var big = big_in;
    var flags = flags_in;
    var ch = ch_in;
    var x = x_in;
    var y = y_in;
    if (vars.frame_counter.* & 0x10 == 0 and ch == 100) {
        std.debug.assert(spr >= 8);
        ch = tables.kOverworldMapData[@intCast(spr - 8)];
        flags = 0x32;
        big = 0;
    } else {
        x -%= 4;
        y -%= 4;
    }
    if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0)
        big |= @as(u8, @truncate(x >> 8)) & 1;
    SetOamPlain(oam_buf + @as(usize, @intCast(spr)), @truncate(x), @truncate(y), ch, flags, big);
}

pub export fn OverworldMap_CheckForPendant(k: c_int) callconv(.c) bool {
    return (vars.savegame_map_icons_indicator.* == 3) and
        (vars.link_which_pendants.* & tables.kPendantBitMask[@intCast(k)]) != 0;
}

pub export fn OverworldMap_CheckForCrystal(k: c_int) callconv(.c) bool {
    return (vars.savegame_map_icons_indicator.* == 7) and
        (vars.link_has_crystals.* & tables.kCrystalBitMask[@intCast(k)]) != 0;
}

pub export fn Module0E_03_DungeonMap() callconv(.c) void {
    kDungMapSubmodules[vars.overworld_map_state.*]();
}

pub export fn Module0E_03_01_DrawMap() callconv(.c) void {
    kDungMapInit[vars.dungmap_init_state.*]();
}

pub export fn Module0E_03_01_00_PrepMapGraphics() callconv(.c) void {
    const hdmaen_bak = vars.HDMAEN_copy.*;
    vars.HDMAEN_copy.* = 0;
    vars.mapbak_main_tile_theme_index.* = vars.main_tile_theme_index.*;
    vars.mapbak_sprite_graphics_index.* = vars.sprite_graphics_index.*;
    vars.mapbak_aux_tile_theme_index.* = vars.aux_tile_theme_index.*;
    vars.mapbak_TM.* = vars.TM_copy.*;
    vars.mapbak_TS.* = vars.TS_copy.*;
    vars.main_tile_theme_index.* = 32;
    vars.sprite_graphics_index.* = 0x80 | loPtr(vars.cur_palace_index_x2).* >> 1;
    vars.aux_tile_theme_index.* = 64;
    vars.TM_copy.* = 0x16;
    vars.TS_copy.* = 1;
    load_gfx.EraseTileMaps_dungeonmap();
    load_gfx.InitializeTilesets();
    vars.overworld_palette_aux_or_main.* = 0x200;
    load_gfx.Palette_Load_DungeonMapBG();
    load_gfx.Palette_Load_DungeonMapSprite();
    vars.hud_palette.* = 1;
    load_gfx.Palette_Load_HUD();
    load_gfx.LoadActualGearPalettes();
    vars.flag_update_cgram_in_nmi.* +%= 1;
    vars.dungmap_init_state.* +%= 1;
    vars.HDMAEN_copy.* = hdmaen_bak;
    vars.nmi_load_bg_from_vram.* = 9;
    vars.nmi_disable_core_updates.* = 9;
}

pub export fn Module0E_03_01_01_DrawLEVEL() callconv(.c) void {
    // Display FLOOR instead of MAP
    const i: i32 = @as(i32, tables.kDungMap_Tab0[vars.cur_palace_index_x2.* >> 1]) >> 1;
    if (i >= 0) {
        const ii: usize = @intCast(i);
        const dst: [*]u8 = @ptrCast(vars.vram_upload_data);
        dst[32] = 0xff;
        std.mem.writeInt(u16, (dst + 14)[0..2], tables.kDungMap_Tab1[ii], .little);
        std.mem.writeInt(u16, (dst + 14 + 16)[0..2], tables.kDungMap_Tab2[ii], .little);
        var j: i32 = 13;
        while (j >= 0) : (j -= 1) {
            const ji: usize = @intCast(j);
            dst[ji] = tables.kDungMap_Tab3[ji];
            dst[ji + 16] = tables.kDungMap_Tab4[ji];
        }
        vars.nmi_load_bg_from_vram.* = 1;
    }
    vars.dungmap_init_state.* +%= 1;
}

pub export fn Module0E_03_01_02_DrawFloorsBackdrop() callconv(.c) void {
    var offs: usize = 0;
    const t5 = tables.kDungMap_Tab5[vars.cur_palace_index_x2.* >> 1];
    if (t5 & 0x100 != 0) {
        var i: usize = 0;
        while (i < 21) : (i += 1) {
            vars.vram_upload_data[offs] = tables.kDungMap_Tab6[i];
            offs += 1;
        }
        var t: u16 = 0x1123;
        i = 0;
        while (i < 16) : ({
            i += 1;
            t +%= 0x20;
            offs += 3;
        }) {
            vars.vram_upload_data[offs + 0] = swap16(t);
            vars.vram_upload_data[offs + 1] = 0xE40;
            vars.vram_upload_data[offs + 2] = 0x1B2E;
        }
    }
    const t5lo: u8 = @truncate(t5);
    const sel: usize = if (t5lo >= 0x50)
        @as(usize, t5lo >> 4) - 4
    else if ((t5 & 0xf) >= 5)
        t5 & 0xf
    else
        0;
    var t7: i32 = tables.kDungMap_Tab7[sel];
    const t7_org: u16 = @intCast(t7);
    var j: usize = 0;
    while (true) {
        vars.vram_upload_data[offs] = swap16(@truncate(@as(u32, @bitCast(t7))));
        offs += 1;
        vars.vram_upload_data[offs] = 0xe40;
        offs += 1;
        vars.vram_upload_data[offs] = tables.kDungMap_Tab8[j] +% (if (t5 & 0x200 != 0) @as(u16, 0x400) else 0);
        offs += 1;
        if (j != 6) j += 1;
        t7 += 0x20;
        if (!(t7 < 0x1360)) break;
    }
    vars.vram_upload_offset.* = @intCast(offs * 2);
    DungeonMap_BuildFloorListBoxes(t5lo, t7_org);
    @as([*]u8, @ptrCast(vars.vram_upload_data))[vars.vram_upload_offset.*] = 0xff;
    vars.dungmap_init_state.* +%= 1;
    vars.nmi_load_bg_from_vram.* = 1;
}

pub export fn DungeonMap_BuildFloorListBoxes(t5: u8, r14_in: u16) callconv(.c) void {
    var r14 = r14_in;
    const n: i32 = @as(i32, t5 & 0xf) + (t5 >> 4);
    r14 -%= 0x40 - 2;
    r14 +%= @as(u16, t5 & 0xf) *% 0x40;
    var offs: usize = vars.vram_upload_offset.* >> 1;
    var i: i32 = 0;
    while (true) {
        var x: usize = 0;
        // `goto loop2` re-emits the row header after every fourth entry.
        while (true) {
            vars.vram_upload_data[offs] = swap16(r14);
            offs += 1;
            vars.vram_upload_data[offs] = 0x700;
            offs += 1;
            while (true) {
                vars.vram_upload_data[offs] = tables.kDungMap_Tab9[x];
                offs += 1;
                x += 1;
                if (x == 4) {
                    r14 +%= 0x20;
                    break;
                }
                if (x == 8) break;
            }
            if (x == 8) break;
        }
        r14 -%= 0x40 + 0x20;
        i += 1;
        if (!(i < n)) break;
    }
    vars.vram_upload_offset.* = @intCast(offs * 2);
}

pub export fn Module0E_03_01_03_DrawRooms() callconv(.c) void {
    vars.dungmap_var2.* = 0;
    vars.dungmap_idx.* = 0;
    const t: u8 = 0 -% @as(u8, @truncate(tables.kDungMap_Tab5[vars.cur_palace_index_x2.* >> 1] & 0xf));
    if (wordPtr(vars.dung_cur_floor).* != t) {
        vars.dungmap_cur_floor.* = vars.dung_cur_floor.*;
    } else {
        vars.dungmap_cur_floor.* = wordPtr(vars.dung_cur_floor).* +% 1;
        vars.dungmap_idx.* +%= 2;
    }
    DungeonMap_DrawFloorNumbersByRoom(0, ~@as(u16, 0x1000));
    DungeonMap_DrawBorderForRooms(0, ~@as(u16, 0x1000));
    DungeonMap_DrawDungeonLayout(0);
    loPtr(vars.dungmap_cur_floor).* -%= 1;
    DungeonMap_DrawFloorNumbersByRoom(0x300, ~@as(u16, 0x1000));
    DungeonMap_DrawBorderForRooms(0x300, ~@as(u16, 0x1000));
    DungeonMap_DrawDungeonLayout(0x300);
    vars.dungmap_cur_floor.* +%= 1;
    std.mem.writeInt(u16, g_ram[6..8], 0, .little);
    std.mem.writeInt(u16, g_ram[10..12], 0, .little);
    vars.nmi_subroutine_index.* = 8;
    loPtr(vars.nmi_load_target_addr).* = 0x22;
    vars.dungmap_init_state.* +%= 1;
}

pub export fn DungeonMap_DrawBorderForRooms(pd: u16, mask: u16) callconv(.c) void {
    var i: usize = 0;
    while (i != 4) : (i += 1)
        vars.messaging_buf[((tables.kDungMap_Tab10[i] +% pd) & 0xfff) >> 1] = tables.kDungMap_Tab11[i] & mask;
    i = 0;
    while (i != 2) : (i += 1) {
        const r4 = tables.kDungMap_Tab12[i] +% pd;
        var j: u16 = 0;
        while (j != 20) : (j += 2)
            vars.messaging_buf[((r4 +% j) & 0xfff) >> 1] = tables.kDungMap_Tab13[i] & mask;
    }
    i = 0;
    while (i != 2) : (i += 1) {
        const r4 = tables.kDungMap_Tab14[i] +% pd;
        var j: u16 = 0;
        while (j != 0x280) : (j += 0x40)
            vars.messaging_buf[((r4 +% j) & 0xfff) >> 1] = tables.kDungMap_Tab15[i] & mask;
    }
}

pub export fn DungeonMap_DrawFloorNumbersByRoom(pd: u16, r8: u16) callconv(.c) void {
    var p: u16 = 0xDE;
    while (true) {
        const t = ((p +% pd) & 0xfff) >> 1;
        vars.messaging_buf[t] = 0xf00;
        vars.messaging_buf[t + 1] = 0xf00;
        p +%= 0x40;
        if (p == 0x39e) break;
    }
    const t = ((0x35e +% pd) & 0xfff) >> 1;
    const cur = vars.dungmap_cur_floor.*;
    const q1: u16 = if (cur & 0x80 != 0) 0x1F1C else tables.kDungMap_Tab16[cur & 0xf];
    const q2: u16 = if (cur & 0x80 != 0)
        tables.kDungMap_Tab16[@as(u8, @truncate(~cur))]
    else
        0x1F1D;
    vars.messaging_buf[t + 0] = q1 & r8;
    vars.messaging_buf[t + 1] = q2 & r8;
}

pub export fn DungeonMap_DrawDungeonLayout(pd: c_int) callconv(.c) void {
    var i: c_int = 0;
    while (i < 5) : (i += 1)
        DungeonMap_DrawSingleRowOfRooms(i, @intCast(((292 + 128 * i + pd) & 0xfff) >> 1));
}

/// The four `goto write_N` blocks are one repeated computation; the C's masks
/// run 8, 4, 2, 1 across the quadrant.
fn dungMapRoomTile(yv: usize, n: usize, r14: u16, dungmask: u16) u16 {
    const r12_org = tables.kDungMap_Tab23[yv * 4 + n];
    var r12 = r12_org;
    const mask: u16 = @as(u16, 8) >> @intCast(n);
    const mapped = vars.link_dungeon_map.* & dungmask != 0;
    if (r12 != 0xB00 and (r14 & mask) == 0) {
        if (r12 & 0x1000 == 0) {
            r12 = 0x400;
        } else if (mapped) {
            return (r12 & ~@as(u16, 0x1c00)) | 0xc00;
        } else {
            r12 = 0;
        }
    } else {
        r12 = 0;
    }
    return if (mapped or (r14 & mask) != 0) r12 +% r12_org else 0xb00;
}

pub export fn DungeonMap_DrawSingleRowOfRooms(i: c_int, arg_x_in: c_int) callconv(.c) void {
    const t5 = tables.kDungMap_Tab5[vars.cur_palace_index_x2.* >> 1];
    const dungmask = rtl.kUpperBitmasks[vars.cur_palace_index_x2.* >> 1];
    var arg_x: usize = @intCast(arg_x_in);

    var j: usize = 0;
    while (j < 5) : ({
        j += 1;
        arg_x += 2;
    }) {
        var r14: u16 = @as(u8, @truncate(vars.dungmap_cur_floor.* +% (t5 & 0xf)));
        const curp = GetDungmapFloorLayout();
        const v = curp[r14 * 25 + @as(usize, @intCast(i)) * 5 + j];
        var yv: usize = undefined;
        if (v == 0xf) {
            yv = 0x51;
        } else {
            r14 = vars.save_dung_info[v] & 0xf;
            var k: usize = 0;
            var count: c_int = 0;
            while (curp[k] != v) : (k += 1)
                count += @intFromBool(curp[k] != 0xf);
            yv = GetOtherDungmapInfo(count);
        }

        vars.messaging_buf[arg_x] = dungMapRoomTile(yv, 0, r14, dungmask);
        vars.messaging_buf[arg_x + 1] = dungMapRoomTile(yv, 1, r14, dungmask);
        vars.messaging_buf[arg_x + 32] = dungMapRoomTile(yv, 2, r14, dungmask);
        vars.messaging_buf[arg_x + 33] = dungMapRoomTile(yv, 3, r14, dungmask);
    }
}

pub export fn DungeonMap_DrawRoomMarkers() callconv(.c) void {
    const dung: usize = vars.cur_palace_index_x2.* >> 1;
    const t5: u8 = @truncate(tables.kDungMap_Tab5[dung] & 0xf);
    const floor1: u8 = t5 +% vars.dung_cur_floor.*;

    var room = vars.dungeon_room_index.*;
    var i: usize = 0;
    while (i != 3) : (i += 1) {
        if (room == tables.kDungMap_Tab21[i])
            room = tables.kDungMap_Tab22[i];
    }
    const roomp = GetDungmapFloorLayout();
    var curp = roomp + @as(usize, floor1) * 25;

    var xcoord: u8 = 0;
    var ycoord: u8 = 0;
    i = 0;
    while (i < 25) {
        const val = curp[0];
        curp += 1;
        if (val == @as(u8, @truncate(room))) break;
        if (xcoord < 64) {
            xcoord +%= 16;
        } else {
            xcoord = 0;
            ycoord +%= 16;
        }
        i += 1;
    }
    vars.dungmap_var3.* = @as(u16, xcoord) +% 0x90;
    vars.dungmap_var3.* +%= (vars.link_x_coord.* & 0x1e0) >> 5;

    vars.dungmap_var6.* = ycoord;

    vars.dungmap_var5.* = @as(u16, ycoord) +% tables.kDungMap_Tab24[vars.dungmap_idx.* >> 1];
    vars.dungmap_var5.* +%= (vars.link_y_coord.* & 0x1e0) >> 5;

    const floor2: u8 = t5 +% @as(u8, @truncate(@as(u16, @bitCast(tables.kDungMap_Tab28[dung]))));
    curp = roomp + @as(usize, floor2) * 25;

    vars.dungmap_var7.* = 0x40;
    vars.dungmap_var8.* = 0x40;

    const lookfor: u8 = @truncate(tables.kDungMap_Tab25[dung]);
    var j: i32 = 24;
    while (j >= 0) : (j -= 1) {
        const ji: usize = @intCast(j);
        if (curp[ji] != 0xf and curp[ji] == lookfor) break;
        vars.dungmap_var7.* -%= 0x10;
        if (@as(i16, @bitCast(vars.dungmap_var7.*)) < 0) {
            vars.dungmap_var7.* = 0x40;
            loPtr(vars.dungmap_var8).* -%= 0x10;
        }
    }

    const floor3: i8 = @truncate(@as(i32, @bitCast(@as(u32, vars.dungmap_cur_floor.*))) -%
        @as(i32, tables.kDungMap_Tab28[dung]));
    vars.dungmap_var8.* +%= @bitCast(@as(i16, 0x60) *% @as(i16, floor3));
    vars.dungmap_var8.* +%= tables.kDungMap_Tab24[0];
    vars.overworld_map_state.* +%= 1;
    vars.INIDISP_copy.* = 0;
    vars.dungmap_init_state.* = 0;
}

pub export fn DungeonMap_HandleInputAndSprites() callconv(.c) void {
    DungeonMap_HandleInput();
    DungeonMap_DrawSprites();
}

/// A static inline in the C.
fn WantExitDungeonMap() bool {
    if (features.hud_cur_item_x.* != 0) {
        return vars.filtered_joypad_H.* & 0x20 != 0; // Select
    } else {
        return vars.filtered_joypad_L.* & 0x40 != 0; // X
    }
}

pub export fn DungeonMap_HandleInput() callconv(.c) void {
    if (WantExitDungeonMap()) {
        vars.overworld_map_state.* +%= 2;
        vars.dungmap_init_state.* = 0;
    } else {
        DungeonMap_HandleMovementInput();
    }
}

pub export fn DungeonMap_HandleMovementInput() callconv(.c) void {
    DungeonMap_HandleFloorSelect();
    if (vars.dungmap_var2.* != 0)
        DungeonMap_ScrollFloors();
}

pub export fn DungeonMap_HandleFloorSelect() callconv(.c) void {
    const r2: u8 = @truncate(tables.kDungMap_Tab5[vars.cur_palace_index_x2.* >> 1] >> 4 & 0xf);
    const r3: u8 = @truncate(tables.kDungMap_Tab5[vars.cur_palace_index_x2.* >> 1] & 0xf);
    if (@as(u16, r2) + r3 < 3 or vars.dungmap_var2.* != 0 or vars.joypad1H_last.* & 0xc == 0)
        return;
    vars.dungmap_cur_floor.* &= 0xff;
    var r6 = std.mem.readInt(u16, g_ram[6..8], .little);
    if (vars.joypad1H_last.* & 8 != 0) {
        if (@as(i32, r2) - 1 == @as(i32, vars.dungmap_cur_floor.*)) return;
        vars.dungmap_cur_floor.* +%= 1;
        r6 = (r6 -% 0x300) & 0xfff;
    } else {
        if (@as(u8, 0 -% r3 +% 1) == @as(u8, @truncate(vars.dungmap_cur_floor.*))) return;
        vars.dungmap_cur_floor.* -%= 2;
        r6 = (r6 +% 0x600) & 0xfff;
    }
    DungeonMap_DrawFloorNumbersByRoom(r6, ~@as(u16, 0x1000));
    DungeonMap_DrawBorderForRooms(r6, ~@as(u16, 0x1000));
    DungeonMap_DrawDungeonLayout(r6);
    vars.dungmap_var2.* +%= 1;
    std.mem.writeInt(u16, g_ram[10..12], vars.joypad1H_last.*, .little);
    const x: usize = vars.joypad1H_last.* >> 3 & 1;
    vars.dungmap_var4.* = vars.BG2VOFS_copy2.* +% @as(u16, @bitCast(tables.kDungMap_Tab26[x]));
    if (x == 0) {
        r6 = (r6 -% 0x300) & 0xfff;
        vars.dungmap_cur_floor.* +%= 1;
    }
    std.mem.writeInt(u16, g_ram[6..8], r6, .little);
    vars.nmi_subroutine_index.* = 8;
}

pub export fn DungeonMap_ScrollFloors() callconv(.c) void {
    const x: usize = std.mem.readInt(u16, g_ram[10..12], .little) >> 3 & 1;
    vars.dungmap_var5.* +%= @bitCast(@as(i16, tables.kDungMap_Tab39[x]));
    vars.dungmap_var8.* +%= @bitCast(@as(i16, tables.kDungMap_Tab39[x]));
    vars.BG2VOFS_copy2.* +%= @bitCast(@as(i16, tables.kDungMap_Tab40[x]));
    if (vars.BG2VOFS_copy2.* == vars.dungmap_var4.*)
        vars.dungmap_var2.* = 0;
}

pub export fn DungeonMap_DrawSprites() callconv(.c) void {
    const dung: usize = vars.cur_palace_index_x2.* >> 1;
    const r2: u8 = @truncate(tables.kDungMap_Tab5[dung] & 0xf);
    const floor: u8 = r2 +% vars.dung_cur_floor.*;

    var spr_pos: c_int = 0;
    var r14: u16 = 0;
    DungeonMap_DrawLinkPointing(spr_pos, r2, floor);
    spr_pos += 1;
    while (true) {
        spr_pos = DungeonMap_DrawLocationMarker(spr_pos, r14);
        r14 +%= 1;
        if (spr_pos == 9) break;
    }
    spr_pos = DungeonMap_DrawBlinkingIndicator(spr_pos);
    spr_pos = DungeonMap_DrawBossIcon(spr_pos);
    spr_pos = DungeonMap_DrawFloorNumberObjects(spr_pos);
    DungeonMap_DrawFloorBlinker();
}

pub export fn DungeonMap_DrawLinkPointing(spr_pos: c_int, r2: u8, r3_in: u8) callconv(.c) void {
    const dung: usize = vars.cur_palace_index_x2.* >> 1;
    const t5: u8 = @truncate(tables.kDungMap_Tab5[dung]);
    var r3 = r3_in;
    if (@as(i32, 4) - r2 >= 0) {
        r3 +%= @truncate(@as(u32, @bitCast(@as(i32, 4) - r2)));
        const a: i8 = @truncate(@as(i32, t5 >> 4) - 4);
        if (a >= 0) r3 -%= @bitCast(a);
    }
    SetOamPlain(
        oam_buf + @as(usize, @intCast(spr_pos)),
        0x19,
        tables.kDungMap_Tab33[r3] -% 4,
        0,
        if (vars.palette_swap_flag.* != 0) 0x30 else 0x3e,
        2,
    );
}

pub export fn DungeonMap_DrawBlinkingIndicator(spr_pos: c_int) callconv(.c) c_int {
    const y: u16 = if (vars.dungmap_var5.* < 256) vars.dungmap_var5.* else 0xf0;
    SetOamPlain(
        oam_buf + @as(usize, @intCast(spr_pos)),
        @truncate(vars.dungmap_var3.* -% 3),
        @truncate(y -% 3),
        0x34,
        tables.kDungMap_Tab38[vars.frame_counter.* >> 2 & 3],
        0,
    );
    return spr_pos + 1;
}

pub export fn DungeonMap_DrawLocationMarker(spr_pos_in: c_int, r14: u16) callconv(.c) c_int {
    var spr_pos = spr_pos_in;
    var i: i32 = 3;
    while (i >= 0) : ({
        i -= 1;
        spr_pos += 1;
    }) {
        const ii: usize = @intCast(i);
        const r15: u8 = @truncate(vars.dungmap_var6.* +% tables.kDungMap_Tab24[r14]);
        var fr: usize = (vars.frame_counter.* >> 2) & 1;
        if (((vars.dungmap_var5.* +% 1) & 0xf0) == @as(u16, r15) + 1 and vars.dungmap_var5.* < 256)
            fr += 2;
        SetOamPlain(
            oam_buf + @as(usize, @intCast(spr_pos)),
            @as(u8, @bitCast(tables.kDungMap_Tab29[ii])) +% @as(u8, @truncate(vars.dungmap_var3.* & 0xf0)),
            r15 +% @as(u8, @bitCast(tables.kDungMap_Tab30[ii])),
            0,
            tables.kDungMap_Tab32[fr] | tables.kDungMap_Tab31[ii],
            2,
        );
    }
    return spr_pos;
}

pub export fn DungeonMap_DrawFloorNumberObjects(spr_pos_in: c_int) callconv(.c) c_int {
    var spr_pos = spr_pos_in;
    var r2: u8 = @truncate(tables.kDungMap_Tab5[vars.cur_palace_index_x2.* >> 1] >> 4 & 0xf);
    var r3: u8 = @truncate(tables.kDungMap_Tab5[vars.cur_palace_index_x2.* >> 1] & 0xf);
    var yv: u8 = 7;
    if (@as(u16, r2) + r3 != 8 and r2 < 4) {
        yv = 6;
        var i: u8 = 3;
        while (i != 0 and i != r2) : (i -= 1)
            yv -%= 1;
        if (r3 >= 5) {
            i = 5;
            while (i != r3 and r3 != 8) : (i += 1)
                yv +%= 1;
        }
    }

    var r4: u8 = tables.kDungMap_Tab33[yv] +% 1;
    r2 -%= 1;
    r3 = 0 -% r3;
    while (true) {
        const sp: usize = @intCast(spr_pos);
        SetOamPlain(
            oam_buf + sp,
            0x30,
            r4,
            if (sign8(r2)) 0x1c else tables.kDungMap_Tab34[r2],
            0x3d,
            0,
        );
        SetOamPlain(
            oam_buf + sp + 1,
            0x38,
            r4,
            if (sign8(r2)) tables.kDungMap_Tab34[r2 ^ 0xff] else 0x1d,
            0x3d,
            0,
        );
        r4 +%= 16;
        spr_pos += 2;
        const old = r2;
        r2 -%= 1;
        if (old == r3) break;
    }
    return spr_pos;
}

pub export fn DungeonMap_DrawFloorBlinker() callconv(.c) void {
    var floor: u8 = @truncate(vars.dungmap_cur_floor.*);
    const t5: u8 = @truncate(tables.kDungMap_Tab5[vars.cur_palace_index_x2.* >> 1]);
    var flag: u8 = @intFromBool((t5 >> 4 & 0xf) + (t5 & 0xf) != 1);
    floor -%= flag;
    var r0: u8 = 0;
    var i: u8 = flag;
    while (true) {
        r0 = floor +% (t5 & 0xf);
        var a: i8 = @truncate(@as(i32, 4) - (t5 & 0xf));
        if (a >= 0) {
            r0 +%= @bitCast(a);
            a = @truncate(@as(i32, t5 >> 4) - 4);
            if (a >= 0) r0 -%= @bitCast(a);
        }
        floor +%= 1;
        const old = i;
        i -%= 1;
        if (old == 0) break;
    }
    if (vars.frame_counter.* & 0x10 == 0) return;
    const y: u8 = tables.kDungMap_Tab33[r0] -% 4;
    while (true) {
        var x: u8 = 40;
        var spr_pos: usize = 0x40 + tables.kDungMap_Tab35[flag];
        var j: i32 = 3;
        while (j >= 0) : ({
            j -= 1;
            spr_pos += 1;
        }) {
            const ji: usize = @intCast(j);
            const t: u8 = 0x3d | (if (j != 0) @as(u8, 0) else 0x40);
            SetOamPlain(oam_buf + spr_pos, x, y +% flag *% 16 +% 0, tables.kDungMap_Tab36[ji], t, 0);
            SetOamPlain(oam_buf + spr_pos + 4, x, y +% flag *% 16 +% 8, tables.kDungMap_Tab36[ji], t | 0x80, 0);
            x +%= 8;
        }
        const old = flag;
        flag -%= 1;
        if (old == 0) break;
    }
}

pub export fn DungeonMap_DrawBossIcon(spr_pos_in: c_int) callconv(.c) c_int {
    var spr_pos = spr_pos_in;
    const dung: usize = vars.cur_palace_index_x2.* >> 1;
    if (vars.save_dung_info[tables.kDungMap_Tab25[dung]] & 0x800 != 0 or
        (vars.link_compass.* & rtl.kUpperBitmasks[dung]) == 0 or
        tables.kDungMap_Tab28[dung] < 0)
        return spr_pos;
    spr_pos = DungeonMap_DrawBossIconByFloor(spr_pos);
    if ((vars.frame_counter.* & 0xf) >= 10) return spr_pos;
    const xy: u16 = @bitCast(tables.kDungMap_Tab37[dung]);
    const yv: u16 = if (vars.dungmap_var8.* < 256) xy +% vars.dungmap_var8.* else 0xf0;
    SetOamPlain(
        oam_buf + @as(usize, @intCast(spr_pos)),
        @truncate((xy >> 8) +% vars.dungmap_var7.* +% 0x90),
        @truncate(yv),
        0x31,
        0x33,
        0,
    );
    return spr_pos + 1;
}

pub export fn DungeonMap_DrawBossIconByFloor(spr_pos: c_int) callconv(.c) c_int {
    const dung: usize = vars.cur_palace_index_x2.* >> 1;
    const t5: u8 = @truncate(tables.kDungMap_Tab5[dung]);
    const r2: u8 = t5 & 0xf;
    var r3: u8 = r2 +% @as(u8, @truncate(@as(u16, @bitCast(tables.kDungMap_Tab28[dung]))));
    if (@as(i32, 4) - r2 >= 0) {
        r3 +%= @truncate(@as(u32, @bitCast(@as(i32, 4) - r2)));
        const a: i8 = @truncate(@as(i32, t5 >> 4) - 4);
        if (a >= 0) r3 -%= @bitCast(a);
    }
    if ((vars.frame_counter.* & 0xf) >= 10) return spr_pos;
    SetOamPlain(oam_buf + @as(usize, @intCast(spr_pos)), 0x4c, tables.kDungMap_Tab33[r3], 0x31, 0x33, 0);
    return spr_pos + 1;
}

pub export fn DungeonMap_RecoverGFX() callconv(.c) void {
    const hdmaen_bak = vars.HDMAEN_copy.*;
    vars.HDMAEN_copy.* = 0;
    load_gfx.EraseTileMaps_normal();

    vars.TM_copy.* = vars.mapbak_TM.*;
    vars.TS_copy.* = vars.mapbak_TS.*;
    vars.main_tile_theme_index.* = vars.mapbak_main_tile_theme_index.*;
    vars.sprite_graphics_index.* = vars.mapbak_sprite_graphics_index.*;
    vars.aux_tile_theme_index.* = vars.mapbak_aux_tile_theme_index.*;
    load_gfx.InitializeTilesets();
    vars.overworld_palette_aux_or_main.* = 0;
    vars.hud_palette.* = 0;
    hud.Hud_Rebuild();

    vars.overworld_screen_transition.* = 0;
    vars.dung_cur_quadrant_upload.* = 0;
    while (true) {
        WaterFlood_BuildOneQuadrantForVRAM();
        nmi.NMI_UploadTilemap();
        Dungeon_PrepareNextRoomQuadrantUpload();
        nmi.NMI_UploadTilemap();
        if (vars.dung_cur_quadrant_upload.* == 0x10) break;
    }

    vars.nmi_subroutine_index.* = 0;
    vars.subsubmodule_index.* = 0;
    vars.HDMAEN_copy.* = hdmaen_bak;

    @memcpy(vars.main_palette_buffer[0..256], vars.mapbak_palette[0..256]);
    vars.COLDATA_copy0.* |= vars.overworld_fixed_color_plusminus.*;
    vars.COLDATA_copy1.* |= vars.overworld_fixed_color_plusminus.*;
    vars.COLDATA_copy2.* |= vars.overworld_fixed_color_plusminus.*;

    vars.sound_effect_2.* = 16;
    vars.music_control.* = 0xf3;
    load_gfx.RecoverPegGFXFromMapping();
    vars.flag_update_cgram_in_nmi.* +%= 1;
    vars.overworld_map_state.* +%= 1;
    vars.INIDISP_copy.* = 0;
    vars.nmi_disable_core_updates.* = 0;
}

pub export fn ToggleStarTilesAndAdvance() callconv(.c) void {
    load_gfx.Dungeon_RestoreStarTileChr();
    vars.overworld_map_state.* +%= 1;
}

pub export fn Death_InitializeGameOverLetters() callconv(.c) void {
    vars.flag_for_boomerang_in_place.* = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        vars.ancilla_x_lo[i] = 0xb0;
        vars.ancilla_x_hi[i] = 0;
    }
    vars.ancilla_type[0] = 1;
    vars.hookshot_effect_index.* = 6;
}

pub export fn CopySaveToWRAM() callconv(.c) void {
    const k: usize = 0xf;
    vars.bird_travel_x_hi[k] = 0;
    vars.bird_travel_y_hi[k] = 0;
    vars.bird_travel_x_lo[k] = 0;
    vars.bird_travel_y_lo[k] = 0;
    vars.birdtravel_var1[k] = 0;

    const off = std.mem.readInt(u16, g_ram[0..2], .little);
    const dst: [*]u8 = @ptrCast(vars.save_dung_info);
    @memcpy(dst[0..0x500], (g_zenv.sram.? + off)[0..0x500]);

    vars.bg_tile_animation_countdown.* = 7;
    vars.word_7EC013.* = 7;
    vars.word_7EC00F.* = 0;
    vars.word_7EC015.* = 0;
    vars.word_7E0219.* = 0x6040;
    vars.word_7E021D.* = 0x4841;
    vars.word_7E021F.* = 0x7f;
    vars.word_7E0221.* = 0xffff;

    // If you save / quit in the middle of a mosaic effect, such as
    // being electrocuted by a buzz blob, the resumed game will skip
    // the location prompt and start in the sanctuary.
    if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
        vars.mosaic_level.* = 0;

    vars.hud_var1.* = 128;
    vars.main_module_index.* = 5;
    vars.submodule_index.* = 0;
    vars.which_entrance.* = 0;
    vars.nmi_disable_core_updates.* = 0;
    vars.hud_palette.* = 0;
}

pub export fn RenderText() callconv(.c) void {
    kMessaging_Text[vars.messaging_module.*]();
}

pub export fn RenderText_PostDeathSaveOptions() callconv(.c) void {
    vars.dialogue_message_index.* = 3;
    Text_Initialize_initModuleStateLoop();
    vars.text_msgbox_topleft.* = 0x61e8;
    vars.text_render_state.* = 2;
    var i: usize = 0;
    while (i < 5) : (i += 1)
        Text_Render();
}

pub export fn Text_Initialize() callconv(.c) void {
    if (vars.main_module_index.* == 20)
        load_gfx.ResetHUDPalettes4and5();
    load_gfx.Attract_DecompressStoryGFX();
    Text_Initialize_initModuleStateLoop();
}

pub export fn Text_Initialize_initModuleStateLoop() callconv(.c) void {
    // text_msgbox_topleft_copy is the base of a 32-byte block of text state.
    const dst: [*]u8 = @ptrCast(vars.text_msgbox_topleft_copy);
    const src: [*]const u8 = @ptrCast(&tables.kText_InitializationData);
    @memcpy(dst[0..32], src[0..32]);
    Text_InitVwfState();
    RenderText_SetDefaultWindowPosition();
    vars.text_tilemap_cur.* = 0x3980;
    Text_LoadCharacterBuffer();
    @memset(@as([*]u8, @ptrCast(vars.messaging_buf))[0..0x7e0], 0);
    vars.nmi_subroutine_index.* = 2;
    vars.nmi_disable_core_updates.* = 2;
}

pub export fn Text_InitVwfState() callconv(.c) void {
    vars.vwf_curline.* = 0;
    vars.vwf_flag_next_line.* = 0;
    vars.vwf_var1.* = 0;
    vars.vwf_line_ptr.* = 0;
}

/// Not declared in messaging.h, but non-static in the C.
pub export fn Text_DecodeCmd(a_in: u8, src: [*]const u8) callconv(.c) u32 {
    var a = a_in;
    if (g_zenv.dialogue_flags & 1 == 0) {
        // US encoding
        if (a < kTextCommandStart_US)
            return TEXTCMD_MK(a, kTextCmd_IsLetter, 0);
        if (a >= 0x80)
            return TEXTCMD_MK(26, kTextCmd_IsLetter, 0); // could happen when loading snapshots
        std.debug.assert(a < 0x80);
        const idx = a - kTextCommandStart_US;
        if (tables.kText_CommandLengths_US[idx] != 0) {
            return TEXTCMD_MK(src[0], idx, 1);
        } else {
            return TEXTCMD_MK(0, idx, 0);
        }
    } else {
        // EU encoding
        if (a < 0x7f)
            return TEXTCMD_MK(a, kTextCmd_IsLetter, 0);
        if (a < kTextCmd_EU_Rest)
            return tables.kReturns_Simple[a - 0x7f];
        a = src[0];
        return switch (a >> 4) {
            0 => TEXTCMD_MK(a & 0xF, kTextCmd_Wait, 1),
            1 => TEXTCMD_MK(a & 0xF, kTextCmd_Color, 1),
            2 => TEXTCMD_MK(a & 0xF, kTextCmd_Number, 1),
            3 => TEXTCMD_MK(a & 0xF, kTextCmd_Speed, 1),
            4 => TEXTCMD_MK(tables.kSoundLut[a & 0xF], kTextCmd_Sound, 1),
            8 => tables.kReturns_Ext[a - 0x80],
            else => TEXTCMD_MK(26, kTextCmd_IsLetter, 0), // assert(0)
        };
    }
}

/// Perform initial parsing of the string, expanding words, processing some commands, etc.
pub export fn Text_LoadCharacterBuffer() callconv(.c) void {
    const dictionary = util.FindIndexInMemblk(@bitCast(g_zenv.dialogue_blk), 0);
    const dialogue = util.FindIndexInMemblk(@bitCast(g_zenv.dialogue_blk), 1);
    // Text written by the settings menu comes from there rather than from the
    // game's dialogue.
    const text_str: util.MemBlk = if (settings_menu.customMessage(vars.dialogue_message_index.*)) |custom|
        .{ .ptr = custom.ptr, .size = custom.len }
    else
        util.FindIndexInMemblk(dialogue, vars.dialogue_message_index.*);
    var src = text_str.ptr.?;
    const src_end = src + text_str.size;
    var dst = vars.messaging_text_buffer;
    while (@intFromPtr(src) < @intFromPtr(src_end)) {
        const c = src[0];
        src += 1;
        if (c >= kTextDictBase) {
            const blk = util.FindIndexInMemblk(dictionary, c - kTextDictBase);
            @memcpy(dst[0..blk.size], blk.ptr.?[0..blk.size]);
            dst += blk.size;
            continue;
        }
        // Decode the next byte or multibyte character (in case we support that in the future)
        // This is dependent on the current language cause US / PAL encode commands differently
        const cmd = Text_DecodeCmd(c, src);
        switch (TEXTCMD_CMD(cmd)) {
            kTextCmd_Name => dst = Text_WritePlayerName(dst),
            kTextCmd_Window => // RenderText_ExtendedCommand_SetWindowType
            {
                vars.text_render_state.* = @truncate(TEXTCMD_PARAM(cmd));
            },
            kTextCmd_Number => { // Text_WritePreloadedNumber
                const t: u8 = @truncate(TEXTCMD_PARAM(cmd));
                const v = vars.dialogue_number[t >> 1];
                dst[0] = 0x34 +% (if (t & 1 != 0) v >> 4 else v & 0xf);
                dst += 1;
            },
            kTextCmd_Position => {
                vars.text_msgbox_topleft.* = tables.kText_Positions[TEXTCMD_PARAM(cmd)];
            },
            kTextCmd_Color => {
                vars.text_tilemap_cur.* = @truncate(((0x387F & 0xe300) | 0x180) |
                    ((TEXTCMD_PARAM(cmd) << 10) & 0x3c00));
            },
            else => {
                // This combination is handled when rendering instead of here
                dst[0] = c;
                dst += 1;
                if (TEXTCMD_MULTIBYTE(cmd) != 0) {
                    dst[0] = src[0];
                    dst += 1;
                }
            },
        }
        src += TEXTCMD_MULTIBYTE(cmd);
    }
    dst[0] = 0x7f;
    vars.dialogue_msg_read_pos.* = 0;
}

pub export fn Text_WritePlayerName(p: [*]u8) callconv(.c) [*]u8 {
    const slot: u8 = @truncate(srm_var1().*);
    const offs: usize = @intCast((@as(i32, slot >> 1) - 1) * 0x500);
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        const pp = g_zenv.sram.? + 0x3d9 + offs + i * 2;
        const a = std.mem.readInt(u16, pp[0..2], .little);
        p[i] = Text_FilterPlayerNameCharacters(@truncate((a & 0xf) | ((a >> 1) & 0xf0)));
    }
    var n: usize = 6;
    while (n != 0 and p[n - 1] == 0x59)
        n -= 1;
    return p + n;
}

pub export fn Text_FilterPlayerNameCharacters(a_in: u8) callconv(.c) u8 {
    var a = a_in;
    if (a >= 0x5f) {
        if (a >= 0x76) {
            a -%= 0x42;
        } else if (a == 0x5f) {
            a = 8;
        } else if (a == 0x60) {
            a = 0x22;
        } else if (a == 0x61) {
            a = 0x3e;
        }
    }
    return a;
}

pub export fn Text_Render() callconv(.c) void {
    kText_Render[vars.text_render_state.*]();
}

pub export fn RenderText_Draw_Border() callconv(.c) void {
    RenderText_DrawBorderInitialize();
    var d = RenderText_DrawBorderRow(vars.vram_upload_data, 0);
    var i: usize = 0;
    while (i != 6) : (i += 1)
        d = RenderText_DrawBorderRow(d, 6);
    d = RenderText_DrawBorderRow(d, 12);
    vars.nmi_load_bg_from_vram.* = 1;
    vars.text_render_state.* = 2;
}

pub export fn RenderText_Draw_BorderIncremental() callconv(.c) void {
    vars.nmi_load_bg_from_vram.* = 1;
    var a = vars.text_incremental_state.*;
    const d = vars.vram_upload_data;
    if (a != 0) a = if (a < 7) 1 else 2;
    switch (a) {
        0 => {
            RenderText_DrawBorderInitialize();
            _ = RenderText_DrawBorderRow(d, 0);
            vars.text_incremental_state.* +%= 1;
        },
        1 => {
            _ = RenderText_DrawBorderRow(d, 6);
            vars.text_incremental_state.* +%= 1;
        },
        2 => {
            vars.text_render_state.* = 2;
            _ = RenderText_DrawBorderRow(d, 12);
            vars.text_incremental_state.* +%= 1;
        },
        else => {},
    }
}

pub export fn RenderText_Draw_CharacterTilemap() callconv(.c) void {
    Text_BuildCharacterTilemap();
    vars.text_render_state.* +%= 1;
}

pub export fn RenderText_Draw_MessageCharacters() callconv(.c) void {
    // `goto RESTART` loops; `goto COMMAND_DONE` jumps to the shared tail that
    // the C spells as `if (0) COMMAND_DONE: { ... }`.
    restart: while (true) {
        const pos = vars.dialogue_msg_read_pos.*;
        const cmd = Text_DecodeCmd(
            vars.messaging_text_buffer[pos],
            vars.messaging_text_buffer + pos + 1,
        );
        var command_done = false;

        switch (TEXTCMD_CMD(cmd)) {
            kTextCmd_IsLetter => {
                if (vars.vwf_line_speed_cur.* >= 2) {
                    vars.vwf_line_speed_cur.* -%= 1;
                } else {
                    VWF_RenderSingle(@intCast(TEXTCMD_PARAM(cmd)));
                    vars.dialogue_msg_read_pos.* +%= @intCast(1 + TEXTCMD_MULTIBYTE(cmd));
                    if (vars.vwf_line_speed_cur.* == 0) continue :restart;
                }
            },
            kTextCmd_NextPic => { // RenderText_Draw_NextImage
                if (vars.main_module_index.* == 20) {
                    load_gfx.PaletteFilterHistory();
                    if (loPtr(vars.palette_filter_countdown).* == 0)
                        command_done = true;
                } else {
                    command_done = true;
                }
            },
            kTextCmd_Choose => RenderText_Draw_Choose2LowOr3(),
            kTextCmd_Item => RenderText_Draw_ChooseItem(),
            // These get handled in Text_LoadCharacterBuffer, and these are unused.
            kTextCmd_Name,
            kTextCmd_Window,
            kTextCmd_Number,
            kTextCmd_Position,
            kTextCmd_Color,
            kTextCmd_Mark,
            kTextCmd_Mark2,
            kTextCmd_Clear,
            => unreachable, // assert(0)
            kTextCmd_ScrollSpd => {
                vars.dialogue_scroll_speed.* = @truncate(TEXTCMD_PARAM(cmd));
                command_done = true;
            },
            kTextCmd_Selchg => RenderText_Draw_Choose2HiOr3(),
            kTextCmd_Choose3 => RenderText_Draw_Choose3(),
            kTextCmd_Choose2 => RenderText_Draw_Choose1Or2(),
            kTextCmd_Scroll => {
                if (RenderText_Draw_Scroll()) command_done = true;
            },
            kTextCmd_1, kTextCmd_2, kTextCmd_3 => { // VWF_SetLine
                vars.vwf_curline.* = tables.kVWF_RowPositions[TEXTCMD_CMD(cmd) - kTextCmd_1];
                vars.vwf_flag_next_line.* = 1;
                command_done = true;
            },
            kTextCmd_Wait => { // RenderText_Draw_Wait
                const sel: u16 = if (vars.joypad1L_last.* & 0x80 != 0) 1 else vars.text_wait_countdown.*;
                switch (sel) {
                    0 => vars.text_wait_countdown.* = tables.kText_WaitDurations[TEXTCMD_PARAM(cmd)] -% 1,
                    1 => {
                        loPtr(vars.text_wait_countdown).* = 0;
                        command_done = true;
                    },
                    else => vars.text_wait_countdown.* -%= 1,
                }
            },
            kTextCmd_Sound => { // RenderText_Draw_PlaySfx
                vars.sound_effect_2.* = @truncate(TEXTCMD_PARAM(cmd));
                command_done = true;
            },
            kTextCmd_Speed => { // RenderText_Draw_SetSpeed
                vars.vwf_line_speed.* = @truncate(TEXTCMD_PARAM(cmd));
                vars.vwf_line_speed_cur.* = vars.vwf_line_speed.*;
                command_done = true;
            },
            kTextCmd_Waitkey => { // RenderText_Draw_PauseForInput
                if (vars.text_wait_countdown2.* != 0) {
                    vars.text_wait_countdown2.* -%= 1;
                    if (vars.text_wait_countdown2.* == 1)
                        vars.sound_effect_2.* = 36;
                } else {
                    if ((vars.filtered_joypad_H.* | vars.filtered_joypad_L.*) & 0xc0 != 0) {
                        vars.text_wait_countdown2.* = 28;
                        command_done = true;
                    }
                }
            },
            kTextCmd_EndMessage => { // RenderText_Draw_Terminate
                if (vars.text_wait_countdown2.* != 0) {
                    vars.text_wait_countdown2.* -%= 1;
                    if (vars.text_wait_countdown2.* == 1)
                        vars.sound_effect_2.* = 36;
                } else {
                    if ((vars.filtered_joypad_H.* | vars.filtered_joypad_L.*) != 0) {
                        vars.text_render_state.* = 4;
                        vars.text_wait_countdown2.* = 28;
                    }
                }
            },
            else => {},
        }

        if (command_done)
            vars.dialogue_msg_read_pos.* +%= @intCast(1 + TEXTCMD_MULTIBYTE(cmd));
        vars.nmi_subroutine_index.* = 2;
        vars.nmi_disable_core_updates.* = 2;
        break;
    }
}

pub export fn RenderText_Draw_Finish() callconv(.c) void {
    RenderText_DrawBorderInitialize();
    const d = vars.vram_upload_data;
    d[0] = swap16(vars.text_msgbox_topleft_copy.*);
    d[1] = 0x2E42;
    d[2] = 0x387F;
    d[3] = 0xffff;
    vars.nmi_load_bg_from_vram.* = 1;
    vars.messaging_module.* = 0;
    vars.submodule_index.* = 0;
    vars.main_module_index.* = vars.saved_module_for_menu.*;
}

/// One 16-row half of a glyph. The C writes this loop out twice, differing only
/// in the font rows it reads and the row base it writes to.
fn vwfBlitHalf(base_y: u16, src_in: [*]align(1) const u16, width: u8) void {
    var src = src_in;
    const mbuf: [*]u8 = @ptrCast(vars.messaging_buf);
    var i: u16 = 0;
    while (i != 16) : (i += 2) {
        var r4 = src[0];
        src += 1;
        var y: u16 = base_y;
        var x: usize = (y & 0xff0) + i;
        y = (y >> 1) & 7;
        var r3 = width;
        while (true) {
            if (r4 & 0x0080 != 0) {
                mbuf[x + 0] ^= tables.kVWF_RenderCharacter_setMasks[y];
            } else {
                mbuf[x + 0] &= ~tables.kVWF_RenderCharacter_setMasks[y];
            }
            if (r4 & 0x8000 != 0) {
                mbuf[x + 1] ^= tables.kVWF_RenderCharacter_setMasks[y];
            } else {
                mbuf[x + 1] &= ~tables.kVWF_RenderCharacter_setMasks[y];
            }
            r4 = (r4 & ~@as(u16, 0x8080)) << 1;
            r3 -%= 1;
            if (r3 == 0) break;
            y += 1;
            if (y == 8) break;
        }
        x += 16;
        if (r4 != 0)
            std.mem.writeInt(u16, (mbuf + x)[0..2], r4, .little);
    }
}

pub export fn VWF_RenderSingle(c: c_int) callconv(.c) void {
    if (c != 0x59)
        vars.sound_effect_2.* = 12;
    vars.vwf_line_speed_cur.* = vars.vwf_line_speed.*;

    if (vars.vwf_flag_next_line.* != 0) {
        vars.vwf_line_ptr.* = tables.kVWF_RenderCharacter_renderPos[vars.vwf_curline.* >> 1];
        vars.vwf_var1.* = tables.kVWF_RenderCharacter_linePositions[vars.vwf_curline.* >> 1];
        vars.vwf_flag_next_line.* = 0;
    }

    const kFontData = util.FindIndexInMemblk(@bitCast(g_zenv.dialogue_font_blk), 0).ptr.?;
    const width = util.FindIndexInMemblk(@bitCast(g_zenv.dialogue_font_blk), 1).ptr.?[@intCast(c)];
    std.debug.assert(width <= 8);

    const i = vars.vwf_var1.*;
    vars.vwf_var1.* = i +% 1;
    const arrval = vars.vwf_arr[i];
    vars.vwf_arr[i + 1] = arrval +% width;
    const r10: u16 = @as(u16, @intCast(c & 0x70)) * 2 + @as(u16, @intCast(c & 0xf));
    const r0: u16 = @as(u16, arrval) *% 2;

    const src2: [*]align(1) const u16 = @ptrCast(kFontData + @as(usize, r10) * 16);
    vwfBlitHalf(r0 +% vars.vwf_line_ptr.*, src2, width);

    const r8 = vars.vwf_line_ptr.* +% 0x150;
    const src3: [*]align(1) const u16 = @ptrCast(kFontData + (@as(usize, r10) + 16) * 16);
    vwfBlitHalf(r8 +% r0, src3, width);
}

pub export fn RenderText_Draw_Choose2LowOr3() callconv(.c) void {
    if (vars.text_wait_countdown2.* != 0) {
        vars.text_wait_countdown2.* -%= 1;
        if (vars.text_wait_countdown2.* == 1)
            vars.sound_effect_2.* = 36;
    } else if ((vars.filtered_joypad_H.* | vars.filtered_joypad_L.*) & 0xc0 != 0) {
        vars.sound_effect_1.* = 43;
        vars.text_render_state.* = 4;
    } else if (vars.filtered_joypad_H.* & 12 != 0) {
        const t: u8 = if (vars.filtered_joypad_H.* & 8 != 0) 0 else 1;
        if (vars.choice_in_multiselect_box.* == t) return;
        vars.choice_in_multiselect_box.* = t;
        vars.sound_effect_2.* = 32;
        vars.dialogue_message_index.* = @as(u16, t) + 1;
        Text_LoadCharacterBuffer();
        Text_InitVwfState();
    }
}

pub export fn RenderText_Draw_ChooseItem() callconv(.c) void {
    if (vars.text_wait_countdown2.* != 0) {
        vars.text_wait_countdown2.* -%= 1;
        if (vars.text_wait_countdown2.* == 1)
            RenderText_FindYItem_Next();
    } else if ((vars.filtered_joypad_H.* | vars.filtered_joypad_L.*) & 0xc0 != 0) {
        vars.text_render_state.* = 4;
    } else {
        if (vars.filtered_joypad_H.* & 5 != 0) {
            vars.choice_in_multiselect_box.* +%= 1;
        } else if (vars.filtered_joypad_H.* & 10 != 0) {
            vars.choice_in_multiselect_box.* -%= 1;
            RenderText_FindYItem_Previous();
            RenderText_Refresh();
            return;
        }
        RenderText_FindYItem_Next();
        RenderText_Refresh();
    }
}

pub export fn RenderText_FindYItem_Previous() callconv(.c) void {
    while (true) {
        var x = vars.choice_in_multiselect_box.*;
        if (sign8(x)) {
            x = 31;
            vars.choice_in_multiselect_box.* = x;
        }
        if (x != 15 and (linkItems()[x] != 0 or (x == 32 and linkItems()[x + 1] != 0)))
            break;
        vars.choice_in_multiselect_box.* -%= 1;
    }
    RenderText_DrawSelectedYItem();
}

pub export fn RenderText_FindYItem_Next() callconv(.c) void {
    while (true) {
        var x = vars.choice_in_multiselect_box.*;
        if (x >= 32) {
            x = 0;
            vars.choice_in_multiselect_box.* = x;
        }
        if (x != 15 and (linkItems()[x] != 0 or (x == 32 and linkItems()[x + 1] != 0)))
            break;
        vars.choice_in_multiselect_box.* +%= 1;
    }
    RenderText_DrawSelectedYItem();
}

pub export fn RenderText_DrawSelectedYItem() callconv(.c) void {
    const item: usize = vars.choice_in_multiselect_box.*;
    var p = hud.Hud_GetItemBoxPtr(@intCast(item));
    p += @as(usize, if (item == 3 or item == 32) 1 else linkItems()[item]) * 4;
    const vwf300 = g_ram[0x1300..].ptr;
    const src: [*]const u8 = @ptrCast(p);
    @memcpy((vwf300 + 0xc2)[0..4], src[0..4]);
    @memcpy((vwf300 + 0xec)[0..4], (src + 4)[0..4]);
}

pub export fn RenderText_Draw_Choose2HiOr3() callconv(.c) void {
    if (vars.text_wait_countdown2.* != 0) {
        vars.text_wait_countdown2.* -%= 1;
        if (vars.text_wait_countdown2.* == 1)
            vars.sound_effect_2.* = 36;
    } else if ((vars.filtered_joypad_H.* | vars.filtered_joypad_L.*) & 0xc0 != 0) {
        vars.sound_effect_1.* = 43;
        vars.text_render_state.* = 4;
    } else if (vars.filtered_joypad_H.* & 12 != 0) {
        const t: u8 = if (vars.filtered_joypad_H.* & 8 != 0) 0 else 1;
        if (vars.choice_in_multiselect_box.* == t) return;
        vars.choice_in_multiselect_box.* = t;
        vars.sound_effect_2.* = 32;
        vars.dialogue_message_index.* = @as(u16, t) + 11;
        Text_LoadCharacterBuffer();
        Text_InitVwfState();
    }
}

pub export fn RenderText_Draw_Choose3() callconv(.c) void {
    if (vars.text_wait_countdown2.* != 0) {
        vars.text_wait_countdown2.* -%= 1;
        if (vars.text_wait_countdown2.* == 1)
            vars.sound_effect_2.* = 36;
        return;
    }
    const y = vars.filtered_joypad_L.* & 0xc0 | vars.filtered_joypad_H.*;
    if (y & 0xd0 != 0) {
        vars.sound_effect_1.* = 43;
        vars.text_render_state.* = 4;
    } else if (y & 12 != 0) {
        var choice = vars.choice_in_multiselect_box.*;
        if (y & 8 != 0) {
            choice = if (choice == 0) 2 else choice -% 1;
        } else {
            choice = if (choice == 2) 0 else choice +% 1;
        }
        vars.choice_in_multiselect_box.* = choice;
        vars.sound_effect_2.* = 32;
        vars.dialogue_message_index.* = @as(u16, choice) + 6;
        Text_LoadCharacterBuffer();
        Text_InitVwfState();
    }
}

pub export fn RenderText_Draw_Choose1Or2() callconv(.c) void {
    if (vars.text_wait_countdown2.* != 0) {
        vars.text_wait_countdown2.* -%= 1;
        if (vars.text_wait_countdown2.* == 1)
            vars.sound_effect_2.* = 36;
        return;
    }
    const y = vars.filtered_joypad_L.* & 0xc0 | vars.filtered_joypad_H.*;
    if (y & 0xd0 != 0) {
        vars.sound_effect_1.* = 43;
        vars.text_render_state.* = 4;
    } else if (y & 12 != 0) {
        const t: u8 = if (y & 8 != 0) 0 else 1;
        if (vars.choice_in_multiselect_box.* == t) return;
        vars.choice_in_multiselect_box.* = t;
        vars.sound_effect_2.* = 32;
        vars.dialogue_message_index.* = @as(u16, t) + 9;
        Text_LoadCharacterBuffer();
        Text_InitVwfState();
    }
}

pub export fn RenderText_Draw_Scroll() callconv(.c) bool {
    var r2 = vars.dialogue_scroll_speed.*;
    while (true) {
        const mbuf: [*]u8 = @ptrCast(vars.messaging_buf);
        var i: usize = 0;
        while (i < 0x7e0) : (i += 16) {
            const p: [*]align(1) u16 = @ptrCast(mbuf + i);
            p[0] = p[1];
            p[1] = p[2];
            p[2] = p[3];
            p[3] = p[4];
            p[4] = p[5];
            p[5] = p[6];
            p[6] = p[7];
            p[7] = p[168];
        }
        var j: usize = 0x34f;
        while (j <= 0x3ef) : (j += 8)
            vars.messaging_buf[j] = 0;

        vars.byte_7E1CDF.* +%= 1;
        if (vars.byte_7E1CDF.* & 0xf == 0) {
            vars.vwf_curline.* = 4;
            vars.vwf_flag_next_line.* = 1;
            return true;
        }
        const old = r2;
        r2 -%= 1;
        if (old == 0) break;
    }
    return false;
}

pub export fn RenderText_SetDefaultWindowPosition() callconv(.c) void {
    const y = vars.link_y_coord.* -% vars.BG2VOFS_copy2.*;
    vars.text_msgbox_topleft.* = tables.kText_Positions[@intFromBool(y < 0x78)];
}

pub export fn RenderText_DrawBorderInitialize() callconv(.c) void {
    vars.text_msgbox_topleft_copy.* = vars.text_msgbox_topleft.*;
}

pub export fn RenderText_DrawBorderRow(d_in: [*]align(1) u16, y_in: c_int) callconv(.c) [*]align(1) u16 {
    var d = d_in;
    const y: usize = @intCast(y_in >> 1);
    d[0] = swap16(vars.text_msgbox_topleft_copy.*);
    d += 1;
    vars.text_msgbox_topleft_copy.* +%= 0x20;
    d[0] = 0x2F00;
    d += 1;
    d[0] = tables.kText_BorderTiles[y];
    d += 1;
    var i: usize = 0;
    while (i < 22) : (i += 1) {
        d[0] = tables.kText_BorderTiles[y + 1];
        d += 1;
    }
    d[0] = tables.kText_BorderTiles[y + 2];
    d += 1;
    d[0] = 0xffff;
    return d;
}

pub export fn Text_BuildCharacterTilemap() callconv(.c) void {
    const vwf300: [*]align(1) u16 = @ptrCast(g_ram[0x1300..].ptr);
    var i: usize = 0;
    while (i < 126) : (i += 1) {
        vwf300[i] = vars.text_tilemap_cur.*;
        vars.text_tilemap_cur.* +%= 1;
    }
    RenderText_Refresh();
}

pub export fn RenderText_Refresh() callconv(.c) void {
    RenderText_DrawBorderInitialize();
    vars.text_msgbox_topleft_copy.* +%= 0x21;
    var d = vars.vram_upload_data;
    var s: [*]align(1) u16 = @ptrCast(g_ram[0x1300..].ptr);
    var j: usize = 0;
    while (j != 6) : (j += 1) {
        d[0] = swap16(vars.text_msgbox_topleft_copy.*);
        d += 1;
        vars.text_msgbox_topleft_copy.* +%= 0x20;
        d[0] = 0x2900;
        d += 1;
        var i: usize = 0;
        while (i != 21) : (i += 1) {
            d[0] = s[0];
            d += 1;
            s += 1;
        }
    }
    d[0] = 0xffff;
    vars.nmi_load_bg_from_vram.* = 1;
}

pub export fn Text_GenerateMessagePointers() callconv(.c) void {
    // This is not actually used. Only for ram compat.
    const dialogue = util.FindIndexInMemblk(@bitCast(g_zenv.dialogue_blk), 1);
    var p: u32 = 0x1c8000;
    var dst = vars.kTextDialoguePointers;
    var i: usize = 0;
    while (i < 398) : (i += 1) {
        if (i == 359) p = 0xedf40;
        std.mem.writeInt(u16, dst[0..2], @truncate(p), .little);
        dst[2] = @truncate(p >> 16);
        dst += 3;
        p +%= @as(u32, @intCast(util.FindIndexInMemblk(dialogue, i).size)) + 1;
    }
}

pub export fn DungMap_LightenUpMap() callconv(.c) void {
    vars.INIDISP_copy.* +%= 1;
    if (vars.INIDISP_copy.* == 0xf)
        vars.overworld_map_state.* +%= 1;
}

pub export fn DungMap_Backup() callconv(.c) void {
    vars.INIDISP_copy.* -%= 1;
    if (vars.INIDISP_copy.* != 0) return;
    vars.MOSAIC_copy.* = 3;
    vars.mapbak_HDMAEN.* = vars.HDMAEN_copy.*;
    load_gfx.EnableForceBlank();
    vars.overworld_map_state.* +%= 1;
    vars.dungmap_init_state.* = 0;
    vars.COLDATA_copy0.* = 0x20;
    vars.COLDATA_copy1.* = 0x40;
    vars.COLDATA_copy2.* = 0x80;
    vars.link_dma_graphics_index.* = 0x250;
    @memcpy(vars.mapbak_palette[0..256], vars.main_palette_buffer[0..256]);
    vars.mapbak_bg1_x_offset.* = vars.bg1_x_offset.*;
    vars.mapbak_bg1_y_offset.* = vars.bg1_y_offset.*;
    vars.bg1_x_offset.* = 0;
    vars.bg1_y_offset.* = 0;
    vars.mapbak_BG1HOFS_copy2.* = vars.BG1HOFS_copy2.*;
    vars.mapbak_BG2HOFS_copy2.* = vars.BG2HOFS_copy2.*;
    vars.mapbak_BG1VOFS_copy2.* = vars.BG1VOFS_copy2.*;
    vars.mapbak_BG2VOFS_copy2.* = vars.BG2VOFS_copy2.*;
    vars.BG1VOFS_copy2.* = 0;
    vars.BG1HOFS_copy2.* = 0;
    vars.BG2VOFS_copy2.* = 0;
    vars.BG2HOFS_copy2.* = 0;
    vars.BG3VOFS_copy2.* = 0;
    vars.BG3HOFS_copy2.* = 0;
    vars.mapbak_CGWSEL.* = wordPtr(vars.CGWSEL_copy).*;
    vars.CGWSEL_copy.* = 0x02;
    vars.CGADSUB_copy.* = 0x20;
    var i: usize = 0;
    while (i < 2048) : (i += 1)
        vars.messaging_buf[i] = 0x300;
    vars.sound_effect_2.* = 16;
    vars.music_control.* = 0xf2;
}

pub export fn DungMap_FadeMapToBlack() callconv(.c) void {
    vars.INIDISP_copy.* -%= 1;
    if (vars.INIDISP_copy.* != 0) return;
    load_gfx.EnableForceBlank();
    vars.overworld_map_state.* +%= 1;
    wordPtr(vars.CGWSEL_copy).* = vars.mapbak_CGWSEL.*;
    vars.BG1HOFS_copy2.* = vars.mapbak_BG1HOFS_copy2.*;
    vars.BG2HOFS_copy2.* = vars.mapbak_BG2HOFS_copy2.*;
    vars.BG1VOFS_copy2.* = vars.mapbak_BG1VOFS_copy2.*;
    vars.BG2VOFS_copy2.* = vars.mapbak_BG2VOFS_copy2.*;
    vars.BG3HOFS_copy2.* = 0;
    vars.BG3VOFS_copy2.* = 0;
    vars.bg1_x_offset.* = vars.mapbak_bg1_x_offset.*;
    vars.bg1_y_offset.* = vars.mapbak_bg1_y_offset.*;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn DungMap_RestoreOld() callconv(.c) void {
    OrientLampLightCone();
    vars.INIDISP_copy.* +%= 1;
    if (vars.INIDISP_copy.* != 0xf) return;
    vars.main_module_index.* = vars.saved_module_for_menu.*;
    vars.submodule_index.* = 0;
    vars.overworld_map_state.* = 0;
    vars.subsubmodule_index.* = 0;
    vars.INIDISP_copy.* = 0xf;
    vars.HDMAEN_copy.* = vars.mapbak_HDMAEN.*;
}

pub export fn Death_PlayerSwoon() callconv(.c) void {
    var k: c_int = vars.link_var30d.*;
    vars.some_animation_timer.* -%= 1;
    if (sign8(vars.some_animation_timer.*)) {
        k += 1;
        if (k == 15) return;
        if (k == 14) vars.submodule_index.* +%= 1;
        vars.link_var30d.* = @intCast(k);
        vars.some_animation_timer_steps.* = tables.kDeath_AnimCtr0[@intCast(k)];
        vars.some_animation_timer.* = tables.kDeath_AnimCtr1[@intCast(k)];
    }
    if (k != 13 or vars.link_visibility_status.* == 12) return;
    const y: u8 = @truncate(vars.link_y_coord.* +% 16 -% vars.BG2VOFS_copy2.*);
    const x: u8 = @truncate(vars.link_x_coord.* +% 7 -% vars.BG2HOFS_copy2.*);
    SetOamPlain(oam_buf + 0x74, x, y, 0xaa, tables.kDeath_SprFlags[vars.link_is_on_lower_level.*] | 2, 2);
}

pub export fn Death_PrepFaint() callconv(.c) void {
    vars.link_direction_facing.* = 2;
    vars.player_unk1.* = 1;
    vars.link_var30d.* = 0;
    vars.some_animation_timer_steps.* = 0;
    vars.some_animation_timer.* = 5;
    vars.link_hearts_filler.* = 0;
    vars.link_health_current.* = 0;
    Link_ResetProperties_C();
    vars.player_on_somaria_platform.* = 0;
    vars.draw_water_ripples_or_grass.* = 0;
    vars.link_is_bunny_mirror.* = 0;
    vars.bitmask_of_dragstate.* = 0;
    vars.flag_is_ancilla_to_pick_up.* = 0;
    vars.link_auxiliary_state.* = 0;
    vars.link_incapacitated_timer.* = 0;
    vars.link_give_damage.* = 0;
    vars.link_is_transforming.* = 0;
    vars.link_speed_setting.* = 0;
    vars.link_need_for_poof_for_transform.* = 0;
    if (vars.link_item_moon_pearl.* != 0)
        vars.link_is_bunny.* = 0;
    vars.link_timer_tempbunny.* = 0;
    // bugfix: dying as permabunny doesn't restore link palette during death animation
    if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
        load_gfx.LoadActualGearPalettes();
    vars.sound_effect_1.* = 0x27 | misc.Link_CalculateSfxPan();
    var i: usize = 0;
    while (i != 4) : (i += 1) {
        if (vars.link_bottle_info[i] == 6) return;
    }
    vars.index_of_changable_dungeon_objs[0] = 0;
    vars.index_of_changable_dungeon_objs[1] = 0;
}

pub export fn DisplaySelectMenu() callconv(.c) void {
    vars.choice_in_multiselect_box_bak.* = vars.choice_in_multiselect_box.*;
    // Continue Game, Save and Quit, and this port's Settings when it can be
    // offered; the game's own two-choice message otherwise.
    vars.dialogue_message_index.* = if (settings_menu.offerSelectMenu()) settings_menu.kMsgCustom else 0x186;
    const bak = vars.main_module_index.*;
    misc.Main_ShowTextMessage();
    vars.main_module_index.* = bak;
    vars.subsubmodule_index.* = 0;
    vars.submodule_index.* = 11;
    vars.saved_module_for_menu.* = vars.main_module_index.*;
    vars.main_module_index.* = 14;
}

// ---------------------------------------------------------------------------

const testing = std.testing;

test "the text command encoding round-trips" {
    // TEXTCMD_MK packs param, command and the multibyte flag into one word.
    const cmd = TEXTCMD_MK(5, kTextCmd_Wait, 1);
    try testing.expectEqual(@as(u32, 355), cmd);
    try testing.expectEqual(@as(u32, kTextCmd_Wait), TEXTCMD_CMD(cmd));
    try testing.expectEqual(@as(u32, 5), TEXTCMD_PARAM(cmd));
    try testing.expectEqual(@as(u32, 1), TEXTCMD_MULTIBYTE(cmd));

    const letter = TEXTCMD_MK('A', kTextCmd_IsLetter, 0);
    try testing.expectEqual(@as(u32, kTextCmd_IsLetter), TEXTCMD_CMD(letter));
    try testing.expectEqual(@as(u32, 'A'), TEXTCMD_PARAM(letter));
    try testing.expectEqual(@as(u32, 0), TEXTCMD_MULTIBYTE(letter));
}

test "the EU simple-command table decodes to the documented commands" {
    // clang evaluated these TEXTCMD_MK() entries when the table was generated.
    try testing.expectEqual(8, tables.kReturns_Simple.len);
    try testing.expectEqual(@as(u32, kTextCmd_EndMessage), TEXTCMD_CMD(tables.kReturns_Simple[0]));
    try testing.expectEqual(@as(u32, kTextCmd_Scroll), TEXTCMD_CMD(tables.kReturns_Simple[1]));
    try testing.expectEqual(@as(u32, kTextCmd_Waitkey), TEXTCMD_CMD(tables.kReturns_Simple[2]));
    try testing.expectEqual(@as(u32, kTextCmd_1), TEXTCMD_CMD(tables.kReturns_Simple[3]));
    try testing.expectEqual(@as(u32, kTextCmd_Name), TEXTCMD_CMD(tables.kReturns_Simple[6]));
    // The extended table is one entry per 0x80..0x88 sub-command.
    try testing.expectEqual(9, tables.kReturns_Ext.len);
    try testing.expectEqual(@as(u32, kTextCmd_Choose), TEXTCMD_CMD(tables.kReturns_Ext[0]));
    try testing.expectEqual(@as(u32, 1), TEXTCMD_MULTIBYTE(tables.kReturns_Ext[0]));
}

test "Text_FilterPlayerNameCharacters remaps only the high punctuation" {
    // Below 0x5f the character passes through untouched.
    try testing.expectEqual(@as(u8, 0x20), Text_FilterPlayerNameCharacters(0x20));
    try testing.expectEqual(@as(u8, 0x5e), Text_FilterPlayerNameCharacters(0x5e));
    // The three singletons, then the 0x76+ range shifts down by 0x42.
    try testing.expectEqual(@as(u8, 8), Text_FilterPlayerNameCharacters(0x5f));
    try testing.expectEqual(@as(u8, 0x22), Text_FilterPlayerNameCharacters(0x60));
    try testing.expectEqual(@as(u8, 0x3e), Text_FilterPlayerNameCharacters(0x61));
    try testing.expectEqual(@as(u8, 0x34), Text_FilterPlayerNameCharacters(0x76));
    // Between 0x61 and 0x76 nothing matches, so the value is returned as-is.
    try testing.expectEqual(@as(u8, 0x70), Text_FilterPlayerNameCharacters(0x70));
}

test "RenderText_SetDefaultWindowPosition picks the box by player height" {
    vars.BG2VOFS_copy2.* = 0;
    vars.link_y_coord.* = 0x40; // above the midpoint
    RenderText_SetDefaultWindowPosition();
    try testing.expectEqual(tables.kText_Positions[1], vars.text_msgbox_topleft.*);

    vars.link_y_coord.* = 0x90; // below it
    RenderText_SetDefaultWindowPosition();
    try testing.expectEqual(tables.kText_Positions[0], vars.text_msgbox_topleft.*);
    try testing.expectEqual(@as(u16, 0x6125), tables.kText_Positions[0]);
    try testing.expectEqual(@as(u16, 0x6244), tables.kText_Positions[1]);
}

test "the dispatch tables have the sizes their indices assume" {
    try testing.expectEqual(12, kMessagingSubmodules.len);
    try testing.expectEqual(16, kModule_Death.len);
    try testing.expectEqual(9, kDungMapSubmodules.len);
    try testing.expectEqual(5, kDungMapInit.len);
    try testing.expectEqual(5, kText_Render.len);
    try testing.expectEqual(3, kMessaging_Text.len);
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &RenderText), kMessagingSubmodules[2]);
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &GameOver_ResituateLink), kModule_Death[15]);
}

test "the big dungeon-map and mode7 tables kept their declared sizes" {
    // Four entries per room across 186 rooms.
    try testing.expectEqual(744, tables.kDungMap_Tab23.len);
    try testing.expectEqual(0, tables.kDungMap_Tab23.len % 4);
    try testing.expectEqual(333, tables.kOverworldMap_tab1.len);
    try testing.expectEqual(129, tables.kPrayingScene_Tab0.len);
    try testing.expectEqual(129, tables.kPrayingScene_Tab1.len);
    // The iris tables run from fully open to fully closed.
    try testing.expectEqual(@as(u8, 0xff), tables.kPrayingScene_Tab1[0]);
    try testing.expectEqual(@as(u8, 0), tables.kPrayingScene_Tab1[128]);
    try testing.expectEqual(25, tables.kText_CommandLengths_US.len);
}

test "kHealthAfterDeath scales with the heart container count" {
    try testing.expectEqual(21, kHealthAfterDeath.len);
    // Three hearts at the low end, ten at the top.
    try testing.expectEqual(@as(u8, 0x18), kHealthAfterDeath[0]);
    try testing.expectEqual(@as(u8, 0x50), kHealthAfterDeath[20]);
    // It is indexed by capacity >> 3, so the table must cover the max capacity.
    try testing.expect(@as(usize, 0xa0 >> 3) < kHealthAfterDeath.len);
}

test "the signed dungeon-map tables kept their negative entries" {
    // -1 marks 'no floor offset'; a u8 table would turn these into 255.
    try testing.expectEqual(@as(i8, -1), tables.kDungMap_Tab0[0]);
    try testing.expectEqual(@as(i16, -1), tables.kDungMap_Tab28[0]);
    try testing.expectEqual(@as(i8, -9), tables.kDungMap_Tab29[0]);
    try testing.expectEqual(@as(i16, 0x60), tables.kDungMap_Tab26[0]);
    try testing.expectEqual(@as(i16, -0x60), tables.kDungMap_Tab26[1]);
}
