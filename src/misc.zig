//! Port of src/misc.c: the main module routing table, per-frame sprite DMA
//! setup, item receipt, sound effect panning and a handful of cutscene modules.
const std = @import("std");
const vars = @import("variables.zig");
const messaging = @import("messaging.zig");
const rtl = @import("zelda_rtl.zig");
const audio = @import("audio.zig");
const select_file = @import("select_file.zig");

const g_ram = &vars.g_ram;

const PlayerHandlerFunc = fn () callconv(.c) void;

// assets.h
extern const g_asset_ptrs: [165]?[*]const u8;
fn kSoundBank_intro() [*]const u8 {
    return g_asset_ptrs[0].?;
}
fn kSoundBank_indoor() [*]const u8 {
    return g_asset_ptrs[1].?;
}
fn kSoundBank_ending() [*]const u8 {
    return g_asset_ptrs[2].?;
}
fn kPredefinedTileData() [*]align(1) const u16 {
    return @ptrCast(g_asset_ptrs[69].?);
}

// player.h
const kPlayerState_Ground: u8 = 0;
const kPlayerState_Mirror: u8 = 20;

// hud.c
extern fn Hud_SearchForEquippedItem() void;
extern fn Hud_Rebuild() void;
extern fn Hud_UpdateEquippedItem() void;
extern fn Hud_RebuildIndoor() void;
extern fn Hud_RefillMagicPower() bool;
extern fn Hud_RefillHealth() bool;
extern fn Hud_RefillLogic() void;
extern fn Hud_RefreshIcon() void;
// dungeon.c
extern fn Module_PreDungeon() void;
extern fn Module07_Dungeon() void;
extern fn Module11_DungeonFallingEntrance() void;
extern fn Dungeon_PrepExitWithSpotlight() void;
extern fn Dungeon_ResetTorchBackgroundAndPlayerInner() void;
extern fn Dungeon_LoadPalettes() void;
extern fn Dungeon_FlagRoomData_Quadrants() void;
extern fn SaveDungeonKeys() void;
extern fn HandleItemTileAction_Dungeon(x: u16, y: u16) u8;
// overworld.c
extern fn Module08_OverworldLoad() void;
extern fn Module09_Overworld() void;
extern fn LoadOWMusicIfNeeded() void;
extern fn Overworld_LoadGFXAndScreenSize() void;
extern fn Overworld_SetSongList() void;
extern fn Overworld_ToolAndTileInteraction(x: u16, y: u16) u16;
// load_gfx.c
extern fn LoadDefaultGraphics() void;
extern fn DecompressSwordGraphics() void;
extern fn DecompressShieldGraphics() void;
extern fn LoadFollowerGraphics() void;
extern fn ReloadPreviouslyLoadedSheets() void;
extern fn Palette_Load_Shield() void;
extern fn Palette_Load_Sword() void;
extern fn Palette_UpdateGlovesColor() void;
extern fn Palette_RevertTranslucencySwap() void;
extern fn DecodeAnimatedSpriteTile_variable(a: u8) void;
extern fn EraseTileMaps_normal() void;
extern fn InitializeMirrorHDMA() void;
extern fn PaletteFilter_InitializeWhiteFilter() void;
extern fn MirrorWarp_BuildWavingHDMATable() void;
extern fn MirrorWarp_BuildDewavingHDMATable() void;
extern fn EnableForceBlank() void;
extern fn Spotlight_ConfigureTableAndControl() void;
extern fn OpenSpotlight_Next2() void;
extern fn Module0F_SpotlightClose() void;
extern fn Module10_SpotlightOpen() void;
// sprite.c
extern fn Sprite_LoadGraphicsProperties() void;
extern fn Sprite_Main() void;
extern fn Sprite_ResetAll() void;
extern fn Sprite_GetX(k: c_int) u16;
// player.c
extern fn Link_Initialize() void;
extern fn Link_Main() void;
extern fn Link_ResetProperties_A() void;
extern fn Link_AnimateVictorySpin() void;
extern fn Death_Func15(count_as_death: bool) void;
extern fn ResetSomeThingsAfterDeath(a: u8) void;
extern fn Module12_GameOver() void;
// player_oam.c
extern fn LinkOam_Main() void;
// ancilla.c
extern fn Ancilla_AddAncilla(a: u8, y: u8) c_int;
extern fn Ancilla_TerminateSelectInteractives(y: u8) u8;
extern fn Ancilla_SetXY(k: c_int, x: u16, y: u16) void;
extern fn AncillaAdd_VictorySpin() void;
extern fn AncillaAdd_CapePoof(a: u8, y: u8) void;
extern fn AncillaAdd_MSCutscene(a: u8, y: u8) void;
extern fn ResetAncillaAndCutscene() void;
// messaging.c
extern fn RenderText() void;
extern fn Module0E_Interface() void;
// attract.c / ending.c
extern fn Module00_Intro() void;
extern fn Module14_Attract() void;
extern fn Module18_GanonEmerges() void;
extern fn Module19_TriforceRoom() void;
extern fn Module1A_Credits() void;
extern fn Module1B_SpawnSelect() void;

pub export const kReceiveItem_Tab1 = [76]u8{
    0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 2, 2, 2,
    2, 2, 2, 0, 2, 0, 2, 2, 0, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 0, 2, 2, 2, 2, 2, 0, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 0, 0, 2, 0, 2, 2, 2, 0, 2, 2,
};
const kReceiveItem_Tab2 = [76]i8{
    -5, -5, -5, -5, -5, -4, -4, -5, -5, -4, -4, -4, -2, -4, -4, -4,
    -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4,
    -4, -4, -4, -5, -4, -4, -4, -4, -4, -4, -2, -4, -4, -4, -4, -4,
    -4, -4, -4, -4, -2, -2, -2, -4, -4, -4, -4, -4, -4, -4, -4, -4,
    -4, -4, -2, -2, -4, -2, -4, -4, -4, -5, -4, -4,
};
const kReceiveItem_Tab3 = [76]u8{
    4, 4, 4, 4, 4, 0, 0, 4, 4, 4, 4, 4, 5, 0, 0, 0,
    0, 0, 0, 4, 0, 4, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 4, 4, 0, 4, 0, 0, 0, 4, 0, 0,
};
pub export const kReceiveItemGfx = [76]u8{
    6,    0x18, 0x18, 0x18, 0x2d, 0x20, 0x2e, 9,    9,    0xa,  8,    5,    0x10, 0xb,  0x2c, 0x1b,
    0x1a, 0x1c, 0x14, 0x19, 0xc,  7,    0x1d, 0x2f, 7,    0x15, 0x12, 0xd,  0xd,  0xe,  0x11, 0x17,
    0x28, 0x27, 4,    4,    0xf,  0x16, 3,    0x13, 1,    0x1e, 0x10, 0,    0,    0,    0,    0,
    0,    0x30, 0x22, 0x21, 0x24, 0x24, 0x24, 0x23, 0x23, 0x23, 0x29, 0x2a, 0x2c, 0x2b, 3,    3,
    0x34, 0x35, 0x31, 0x33, 2,    0x32, 0x36, 0x37, 0x2c, 6,    0xc,  0x38,
};
pub export const kMemoryLocationToGiveItemTo = [76]u16{
    0xf359, 0xf359, 0xf359, 0xf359,
    0xf35a, 0xf35a, 0xf35a, 0xf345,
    0xf346, 0xf34b, 0xf342, 0xf340,
    0xf341, 0xf344, 0xf35c, 0xf347,
    0xf348, 0xf349, 0xf34a, 0xf34c,
    0xf34c, 0xf350, 0xf35c, 0xf36b,
    0xf351, 0xf352, 0xf353, 0xf354,
    0xf354, 0xf34e, 0xf356, 0xf357,
    0xf37a, 0xf34d, 0xf35b, 0xf35b,
    0xf36f, 0xf364, 0xf36c, 0xf375,
    0xf375, 0xf344, 0xf341, 0xf35c,
    0xf35c, 0xf35c, 0xf36d, 0xf36e,
    0xf36e, 0xf375, 0xf366, 0xf368,
    0xf360, 0xf360, 0xf360, 0xf374,
    0xf374, 0xf374, 0xf340, 0xf340,
    0xf35c, 0xf35c, 0xf36c, 0xf36c,
    0xf360, 0xf360, 0xf372, 0xf376,
    0xf376, 0xf373, 0xf360, 0xf360,
    0xf35c, 0xf359, 0xf34c, 0xf355,
};
const kValueToGiveItemTo = [76]i8{
    1,    2,   3,   4,
    1,    2,   3,   1,
    1,    1,   1,   1,
    1,    2,   -1,  1,
    1,    1,   1,   1,
    2,    1,   -1,  -1,
    1,    1,   2,   1,
    2,    1,   1,   1,
    -1,   1,   -1,  2,
    -1,   -1,  -1,  -1,
    -1,   -1,  2,   -1,
    -1,   -1,  -1,  -1,
    -1,   -1,  -1,  -1,
    -1,   -5,  -20, -1,
    -1,   -1,  1,   3,
    -1,   -1,  -1,  -1,
    -100, -50, -1,  1,
    10,   -1,  -1,  -1,
    -1,   1,   3,   1,
};
const kDungeon_DefaultAttr = [384]u8{
    1,    1,    1,    0,    2,    1,    2,    0,    1,    1,    2,    2,    2,    2,    2,    2,
    2,    2,    2,    0,    0,    1,    0,    0,    2,    0,    0,    2,    2,    2,    2,    2,
    2,    2,    2,    2,    1,    1,    1,    2,    2,    2,    2,    2,    1,    1,    0,    0,
    2,    2,    2,    2,    2,    2,    1,    2,    2,    2,    2,    2,    1,    1,    0,    0,
    0,    0,    0,    0x2a, 1,    0x20, 1,    1,    4,    1,    1,    0x18, 1,    2,    0x1c, 1,
    0x28, 0x28, 0x2a, 0x2a, 1,    2,    1,    1,    4,    0,    0,    0,    0x28, 1,    0xa,  0,
    1,    1,    0xc,  0xc,  2,    2,    2,    2,    0x28, 0x2a, 0x20, 0x20, 0x20, 2,    8,    0,
    4,    4,    1,    1,    1,    2,    2,    2,    0,    0,    0x20, 0x20, 0,    2,    0,    0,
    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    2,    2,
    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    0x18, 0x10, 0x10, 1,    1,    1,
    1,    1,    4,    4,    4,    4,    4,    4,    1,    2,    2,    0,    0,    0,    0,    0,
    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    2,    2,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0x62, 0x62,
    0,    0,    0x24, 0x24, 0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0x62, 0x62,
    0x27, 2,    2,    2,    0x27, 0x27, 1,    0,    0,    0,    0,    0x24, 0,    0,    0,    0,
    0x27, 0x27, 0x27, 0x27, 0x27, 0x10, 2,    1,    0,    0,    0,    0x24, 0,    0,    0,    0,
    0x27, 2,    2,    2,    0x27, 0x27, 0x27, 0x27, 2,    2,    2,    0x24, 0,    0,    0,    0,
    0x27, 0x27, 0x27, 0x27, 0x27, 0x20, 2,    2,    1,    2,    2,    0x23, 2,    0,    0,    0,
    0x27, 0x27, 0x27, 0x27, 0x27, 0x20, 2,    0x27, 2,    0x54, 0,    0,    0x27, 2,    2,    2,
    0x27, 0x27, 0x27, 0x27, 0x27, 0x27, 2,    0x27, 2,    0x54, 0,    0,    0x27, 2,    2,    2,
    0x27, 0x27, 0,    0x27, 0x60, 0x60, 1,    1,    1,    1,    2,    2,    0xd,  0,    0,    0x4b,
    0x67, 0x67, 0x67, 0x67, 0x66, 0x66, 0x66, 0x66, 0,    0,    0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    0x27, 0x63, 0x27, 0x55, 0x55, 1,    0x44, 0,    1,    0x20, 2,    2,    0x1c, 0x3a, 0x3b, 0,
    0x27, 0x63, 0x27, 0x53, 0x53, 1,    0x44, 1,    0xd,  0,    0,    0,    9,    9,    9,    9,
};

const kModule_BossVictory = [6]*const PlayerHandlerFunc{
    &BossVictory_Heal,
    &Dungeon_StartVictorySpin,
    &Dungeon_RunVictorySpin,
    &Dungeon_CloseVictorySpin,
    &Dungeon_PrepExitWithSpotlight,
    &Spotlight_ConfigureTableAndControl,
};
const kModule_KillAgahnim = [13]*const PlayerHandlerFunc{
    &KillAgahnim_LoadMusic,
    &KillAghanim_Init,
    &KillAghanim_Func2,
    &KillAghanim_Func3,
    &KillAghanim_Func4,
    &KillAghanim_Func5,
    &KillAghanim_Func6,
    &KillAghanim_Func7,
    &KillAghanim_Func8,
    &BossVictory_Heal,
    &Dungeon_StartVictorySpin,
    &Dungeon_RunVictorySpin,
    &KillAghanim_Func12,
};
const kMainRouting = [28]*const PlayerHandlerFunc{
    &Module00_Intro,
    &select_file.Module01_FileSelect,
    &select_file.Module02_CopyFile,
    &select_file.Module03_KILLFile,
    &select_file.Module04_NameFile,
    &Module05_LoadFile,
    &Module_PreDungeon,
    &Module07_Dungeon,
    &Module08_OverworldLoad,
    &Module09_Overworld,
    &Module08_OverworldLoad,
    &Module09_Overworld,
    &Module_Unknown0,
    &Module_Unknown1,
    &Module0E_Interface,
    &Module0F_SpotlightClose,
    &Module10_SpotlightOpen,
    &Module11_DungeonFallingEntrance,
    &Module12_GameOver,
    &Module13_BossVictory_Pendant,
    &Module14_Attract,
    &Module15_MirrorWarpFromAga,
    &Module16_BossVictory_Crystal,
    &Module17_SaveAndQuit,
    &Module18_GanonEmerges,
    &Module19_TriforceRoom,
    &Module1A_Credits,
    &Module1B_SpawnSelect,
};

pub export fn SrcPtr(src: u16) callconv(.c) [*]align(1) const u16 {
    return kPredefinedTileData() + (src >> 1);
}

pub export fn Ancilla_Sfx2_Near(a: u8) callconv(.c) u8 {
    vars.sound_effect_1.* = PlaySfx_SetPan(a);
    return vars.sound_effect_1.*;
}

pub export fn Ancilla_Sfx3_Near(a: u8) callconv(.c) void {
    vars.sound_effect_2.* = PlaySfx_SetPan(a);
}

pub export fn LoadDungeonRoomRebuildHUD() callconv(.c) void {
    vars.mosaic_level.* = 0;
    vars.MOSAIC_copy.* = 7;
    Hud_SearchForEquippedItem();
    Hud_Rebuild();
    Hud_UpdateEquippedItem();
    Module_PreDungeon();
}

pub export fn Module_Unknown0() callconv(.c) void {
    unreachable; // assert(0)
}

pub export fn Module_Unknown1() callconv(.c) void {
    unreachable; // assert(0)
}

fn KillAgahnim_LoadMusic() callconv(.c) void {
    vars.nmi_disable_core_updates.* = 0;
    vars.overworld_map_state.* +%= 1;
    vars.submodule_index.* +%= 1;
    LoadOWMusicIfNeeded();
}

fn KillAghanim_Init() callconv(.c) void {
    vars.music_control.* = 8;
    @as([*]u8, @ptrCast(vars.overworld_screen_trans_dir_bits))[0] = 8;
    InitializeMirrorHDMA();
    vars.overworld_map_state.* = 0;
    PaletteFilter_InitializeWhiteFilter();
    Overworld_LoadGFXAndScreenSize();
    vars.submodule_index.* +%= 1;
    vars.link_player_handler_state.* = kPlayerState_Mirror;
    vars.bg1_x_offset.* = 0;
    vars.bg1_y_offset.* = 0;
    vars.dung_savegame_state_bits.* = 0;
    // WORD(link_y_vel) covers link_y_vel and link_x_vel together.
    std.mem.writeInt(u16, @as([*]u8, @ptrCast(vars.link_y_vel))[0..2], 0, .little);
    vars.main_palette_buffer[0] = 0x7fff;
    vars.main_palette_buffer[32] = 0x7fff;
    _ = Ancilla_TerminateSelectInteractives(0);
    Link_ResetProperties_A();
}

fn KillAghanim_Func2() callconv(.c) void {
    vars.HDMAEN_copy.* = 192;
    MirrorWarp_BuildWavingHDMATable();
    vars.submodule_index.* +%= 1;
    vars.subsubmodule_index.* = 0;
}

fn KillAghanim_Func3() callconv(.c) void {
    MirrorWarp_BuildWavingHDMATable();
    if (vars.subsubmodule_index.* != 0) {
        vars.subsubmodule_index.* = 0;
        vars.submodule_index.* +%= 1;
    }
}

fn KillAghanim_Func4() callconv(.c) void {
    MirrorWarp_BuildDewavingHDMATable();
    if (vars.subsubmodule_index.* != 0) {
        vars.subsubmodule_index.* = 0;
        vars.submodule_index.* +%= 1;
    }
}

const WH0 = 0x2126; // snes/snes_regs.h

fn KillAghanim_Func5() callconv(.c) void {
    rtl.HdmaSetup(0, 0xf2fb, 0x41, 0, @truncate(WH0), 0);
    for (0..240) |i|
        vars.hdma_table_dynamic[i] = 0xff00;
    vars.palette_filter_countdown.* = 0;
    vars.darkening_or_lightening_screen.* = 0;
    vars.dialogue_message_index.* = 0x35;
    Main_ShowTextMessage();
    ReloadPreviouslyLoadedSheets();
    Hud_RebuildIndoor();
    vars.HDMAEN_copy.* = 0x80;
    vars.main_module_index.* = 21;
    vars.submodule_index.* = 6;
    vars.subsubmodule_index.* = 24;
}

fn KillAghanim_Func6() callconv(.c) void {
    vars.subsubmodule_index.* -%= 1;
    if (vars.subsubmodule_index.* == 0) {
        vars.submodule_index.* +%= 1;
        vars.sound_effect_ambient.* = 9;
    }
}

fn KillAghanim_Func7() callconv(.c) void {
    RenderText();
    if (vars.submodule_index.* == 0) {
        vars.overworld_map_state.* = 0;
        vars.sound_effect_ambient.* = 5;
        if (vars.link_item_moon_pearl.* == 0) {
            vars.dialogue_message_index.* = 0x36;
            Main_ShowTextMessage();
            vars.sound_effect_ambient.* = 0;
            vars.main_module_index.* = 21;
            vars.submodule_index.* = 8;
        } else {
            vars.submodule_index.* = 9;
        }
    }
}

fn KillAghanim_Func8() callconv(.c) void {
    RenderText();
    if (vars.submodule_index.* == 0) {
        vars.subsubmodule_index.* = 32;
        vars.submodule_index.* = 12;
    }
}

fn KillAghanim_Func12() callconv(.c) void {
    vars.subsubmodule_index.* -%= 1;
    if (vars.subsubmodule_index.* != 0)
        return;
    ResetAncillaAndCutscene();
    Overworld_SetSongList();
    vars.save_ow_event_info[0x1b] |= 32;
    @as([*]u8, @ptrCast(vars.cur_palace_index_x2))[0] = 255;
    vars.submodule_index.* = 0;
    vars.overworld_map_state.* = 0;
    vars.nmi_disable_core_updates.* = 0;
    vars.main_module_index.* = 9;
    @as([*]u8, @ptrCast(vars.BG1VOFS_copy2))[0] = 0;
    vars.music_control.* = if (vars.link_item_moon_pearl.* != 0) 9 else 4;
    vars.savegame_map_icons_indicator.* = 6;
}

pub export fn Module_MainRouting() callconv(.c) void { // 8080b5
    kMainRouting[vars.main_module_index.*]();
}

const kLinkDmaSources1 = [303]u16{
    0x8080, 0x8080, 0x8080, 0x8080, 0x8080, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
    0x9440, 0x8080, 0x8080, 0x8080, 0x9400, 0x8040, 0x80c0, 0x80c0, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000,
    0x8080, 0x8080, 0x8080, 0x8080, 0x8080, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8000, 0xa8c0, 0xa900, 0x8000, 0xa8c0, 0xa900,
    0x9100, 0x8080, 0x8080, 0x90c0, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x9a00, 0x9140, 0x9180, 0x8000, 0x9500,
    0x9480, 0x94c0, 0x94c0, 0x9ae0, 0x8080, 0x8080, 0x9a60, 0x80c0, 0x80c0, 0x9aa0, 0x8000, 0x8000, 0x9aa0, 0x8000, 0x8000, 0x8080,
    0x8080, 0x8100, 0x8100, 0x85c0, 0x8000, 0x8000, 0x85c0, 0x8000, 0x8000, 0xadc0, 0xadc0, 0xadc0, 0xadc0, 0xadc0, 0xad40, 0xad40,
    0xad40, 0xad40, 0xad40, 0xad80, 0xad80, 0xad80, 0xad80, 0xad80, 0xad80, 0x8040, 0x9400, 0x8040, 0x8000, 0x8080, 0x8080, 0x9440,
    0x8000, 0x8000, 0x8000, 0x8000, 0x8080, 0x8040, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0xc440, 0x8140, 0x8140,
    0xca40, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8000, 0x8040, 0x85c0, 0x8040, 0x85c0, 0x8100, 0x80c0, 0x91c0, 0x8080, 0x8080,
    0x8040, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0x8080, 0x8080, 0x9100, 0xa0c0, 0xa100, 0xa100, 0xa1c0, 0xa400, 0xa440, 0xa1c0,
    0xa400, 0xa440, 0x8080, 0xc480, 0x8080, 0x8040, 0x8040, 0xca80, 0xca80, 0xca00, 0xc400, 0xca00, 0xc400, 0x81c0, 0x8080, 0x8080,
    0x8080, 0x8080, 0x8080, 0x8080, 0x8080, 0x8080, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8040, 0x8000, 0xa8c0, 0xa900,
    0x8000, 0x8000, 0xa8c0, 0xa900, 0x8000, 0xa8c0, 0xa900, 0x8000, 0x8000, 0xa8c0, 0xa900, 0x8040, 0x8040, 0x8040, 0x8080, 0x8080,
    0x8040, 0x8040, 0x8040, 0x8040, 0x8000, 0x8000, 0x8000, 0x8000, 0xd080, 0x8080, 0x90c0, 0xd000, 0x9080, 0xd040, 0x9080, 0xd040,
    0xd080, 0xd080, 0xd080, 0xd080, 0xd080, 0xd000, 0xd000, 0xd000, 0xd000, 0xd000, 0xd040, 0xd040, 0xd040, 0xd040, 0xd040, 0xd040,
    0x8040, 0xd000, 0x85c0, 0x85c0, 0x85c0, 0xdc40, 0xdc40, 0xdc40, 0x85c0, 0x85c0, 0x85c0, 0xdc40, 0xdc40, 0xdc40, 0xe1c0, 0xd000,
    0x8000, 0xe400, 0xe400, 0xe440, 0x90c0, 0x90c0, 0xd000, 0x8000, 0x8000, 0xd040, 0x8000, 0x8000, 0xd040, 0xe400, 0xe400, 0xe400,
    0x9080, 0xa5c0, 0xac40, 0xe480, 0x8180, 0x90c0, 0x80c0, 0xe180, 0xd000, 0xe4c0, 0xe4c0, 0xe840, 0xe840, 0xe840, 0xe540, 0xe540,
    0xe540, 0xe900, 0xe900, 0xe900, 0xe900, 0x8080, 0x8080, 0x8000, 0xa9c0, 0x8080, 0x8140, 0x91c0, 0x8040, 0xa800, 0xa840,
};
const kLinkDmaSources2 = [303]u16{
    0x8840, 0x8800, 0x8580, 0x8800, 0x8580, 0x84c0, 0x8500, 0x8540, 0x8500, 0x8540, 0x8400, 0x8440, 0x8480, 0x8400, 0x8440, 0x8480,
    0x9640, 0x8c40, 0x8c80, 0xad00, 0x9600, 0x8980, 0x8c00, 0xacc0, 0x8880, 0x88c0, 0x8900, 0x8940, 0x8880, 0x88c0, 0x8900, 0x8940,
    0xb0c0, 0xb100, 0xb140, 0xb100, 0xb140, 0xb000, 0xb040, 0xb080, 0xec80, 0xecc0, 0xb180, 0xd440, 0xb1c0, 0xb180, 0xd440, 0xb1c0,
    0x8c80, 0xad00, 0x95c0, 0x99c0, 0xb440, 0x9580, 0xb480, 0xb4c0, 0x9580, 0xb480, 0xb4c0, 0x9c20, 0x8000, 0x8000, 0x8000, 0x9700,
    0x9680, 0x96c0, 0x96c0, 0x9ce0, 0x8c80, 0xb540, 0x9c60, 0xb580, 0x8c00, 0x9ca0, 0x8900, 0xb500, 0x9ca0, 0x8900, 0xb500, 0x8c40,
    0xec40, 0x8c00, 0xec00, 0x8dc0, 0x9540, 0x89c0, 0x8dc0, 0x9540, 0x89c0, 0xb940, 0xb980, 0xb9c0, 0xb980, 0xb9c0, 0xb5c0, 0xb800,
    0xb840, 0xb800, 0xb840, 0xb880, 0xb8c0, 0xb900, 0xb880, 0xb8c0, 0xb900, 0x8980, 0x9600, 0xbcc0, 0x8400, 0xbc80, 0x8c40, 0x9640,
    0xa040, 0xa080, 0xa000, 0xbc40, 0xbd40, 0x8500, 0xbd00, 0xbd80, 0xbd80, 0x88c0, 0x8900, 0xe9c0, 0x8900, 0xc640, 0xc040, 0xc000,
    0xcc40, 0x8940, 0x88c0, 0x8900, 0xe9c0, 0x8900, 0x8940, 0x8d40, 0x8d80, 0x8d40, 0x8d80, 0xbd00, 0xb000, 0xb000, 0xa480, 0xa480,
    0xa480, 0xa480, 0xac00, 0xac00, 0xac00, 0xac00, 0xa140, 0xa180, 0xa180, 0xa4c0, 0xa4c0, 0xa500, 0x9d40, 0x9d80, 0x9dc0, 0x9d40,
    0x9d80, 0x9dc0, 0x8d00, 0xc680, 0xc180, 0xc140, 0x8c00, 0xcc80, 0xcc80, 0xcc00, 0xc600, 0xcc00, 0xc600, 0xbd00, 0x8580, 0x8800,
    0xc9c0, 0xccc0, 0xcdc0, 0xcd00, 0xcd40, 0xcd80, 0x8500, 0x8540, 0xc940, 0xc980, 0x8540, 0xc940, 0xc980, 0x8440, 0x8480, 0xc1c0,
    0xc900, 0xc580, 0xc5c0, 0xc8c0, 0x8440, 0x8480, 0xc1c0, 0xc900, 0xc580, 0xc5c0, 0xc8c0, 0xbd00, 0xacc0, 0xc040, 0xd540, 0xd580,
    0xd4c0, 0xd500, 0xd4c0, 0xd500, 0xd440, 0xd480, 0xd440, 0xd480, 0xd1c0, 0xd400, 0xd100, 0xd100, 0xd140, 0xd180, 0xd140, 0xd180,
    0xb0c0, 0xb100, 0xb140, 0xb100, 0xb140, 0xdd40, 0xdd80, 0xddc0, 0xdd80, 0xddc0, 0xdc80, 0xdcc0, 0xdd00, 0xdc80, 0xdcc0, 0xdd00,
    0xd100, 0xd100, 0xe000, 0xe040, 0xe080, 0xe0c0, 0xe100, 0xe140, 0xe000, 0xe040, 0xe080, 0xe0c0, 0xe100, 0xe140, 0x8000, 0xd0c0,
    0x8000, 0xb940, 0xb980, 0xb940, 0xdd40, 0xdd80, 0xdd40, 0xdc80, 0xdcc0, 0xc0c0, 0xdc80, 0xdcc0, 0xc0c0, 0xb9c0, 0xb980, 0xb9c0,
    0xa560, 0xa5a0, 0xac80, 0xed00, 0x8000, 0x8cc0, 0xbd00, 0xe380, 0xbdc0, 0xe500, 0xe500, 0xe880, 0xe8c0, 0xe8c0, 0xe800, 0xe5c0,
    0xe5c0, 0xe940, 0xe980, 0xe940, 0xe980, 0xbd40, 0x8c80, 0xa080, 0x8000, 0xa980, 0xbd00, 0xbdc0, 0xb400, 0xa880, 0xedc0,
};
const kLinkDmaSources3 = [27]u16{
    0x9a40, 0x9e00, 0x9d20, 0x9f20, 0x9b20, 0xbc20, 0xbc20, 0xbe20, 0xbe20, 0xbe00, 0xbe00, 0xbe00, 0xbe00, 0xa540, 0xa540, 0xa540,
    0xa540, 0xbc00, 0xbc00, 0xbc00, 0xbc00, 0xa740, 0xa740, 0xa740, 0xa740, 0xe780, 0xe780,
};
const kLinkDmaSources4 = [8]u16{ 0x9000, 0x9020, 0x9060, 0x91e0, 0x90a0, 0x90c0, 0x9100, 0x9140 };
const kLinkDmaSources5 = [3]u16{ 0x9300, 0x9340, 0x9380 };
const kLinkDmaSources6 = [128]u16{
    0x9480, 0x94c0, 0x94e0, 0x95c0, 0x9500, 0x9520, 0x9540, 0x9480, 0x9640, 0x9680, 0x96a0, 0x9780, 0x96c0, 0x96e0, 0x9700, 0x9480,
    0x9800, 0x9840, 0x98a0, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9ac0, 0x9b00, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
    0x9bc0, 0x9c00, 0x9c40, 0x9c80, 0x9cc0, 0x9d00, 0x9d40, 0x9480, 0x9f40, 0x9f80, 0x9fc0, 0x9fe0, 0xa000, 0x9480, 0x9480, 0x9480,
    0xa100, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
    0x98c0, 0x9900, 0x99c0, 0x99e0, 0x9a00, 0x9a20, 0x9a40, 0x9a60, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
    0x9a80, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
    0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
    0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480, 0x9480,
};
const kLinkDmaSources7 = [16]u16{ 0xe0, 0xe0, 0x60, 0x80, 0x1c0, 0xe0, 0x40, 0, 0x80, 0, 0x40, 0, 0, 0, 0, 0 };
const kLinkDmaCtrs0 = [6]u16{ 14, 4, 6, 16, 6, 8 };
const kLinkDmaSources9 = [15]u16{ 0, 0x20, 0x40, 0, 0x20, 0x40, 0, 0x40, 0x80, 0, 0x40, 0x80, 0xb340, 0xb400, 0xb4c0 };
const kLinkDmaSources8 = [4]u16{ 0xa480, 0xa4c0, 0xa500, 0xa540 };

pub export fn NMI_PrepareSprites() callconv(.c) void { // 8085fc
    for (0..32) |i| {
        vars.extended_oam[i] = @as(u8, vars.bytewise_extended_oam[3 + 4 * i]) << 6 |
            @as(u8, vars.bytewise_extended_oam[2 + 4 * i]) << 4 |
            @as(u8, vars.bytewise_extended_oam[1 + 4 * i]) << 2 |
            @as(u8, vars.bytewise_extended_oam[0 + 4 * i]) << 0;
    }

    vars.dma_source_addr_3.* = kLinkDmaSources1[vars.link_dma_graphics_index.* >> 1];
    vars.dma_source_addr_0.* = vars.dma_source_addr_3.* +% 0x200;
    vars.dma_source_addr_4.* = kLinkDmaSources2[vars.link_dma_graphics_index.* >> 1];
    vars.dma_source_addr_1.* = vars.dma_source_addr_4.* +% 0x200;
    vars.dma_source_addr_5.* = kLinkDmaSources3[vars.link_dma_var1.* >> 1];
    vars.dma_source_addr_2.* = kLinkDmaSources3[vars.link_dma_var2.* >> 1];

    vars.dma_source_addr_6.* = kLinkDmaSources4[vars.link_dma_var3.* >> 1];
    vars.dma_source_addr_11.* = vars.dma_source_addr_6.* +% 0x180;

    if (vars.link_dma_var4.* == 0x8b) {
        vars.dma_source_addr_7.* = 0xe099;
    } else {
        vars.dma_source_addr_7.* = kLinkDmaSources5[vars.link_dma_var4.* >> 1];
    }
    vars.dma_source_addr_12.* = vars.dma_source_addr_7.* +% 0xc0;

    const j = (vars.link_dma_var5.* & 0xf8) >> 3;
    vars.dma_source_addr_8.* = kLinkDmaSources6[vars.link_dma_var5.*];
    vars.dma_source_addr_13.* = vars.dma_source_addr_8.* +% kLinkDmaSources7[j];
    vars.dma_source_addr_10.* = kLinkDmaSources8[vars.pushedblocks_some_index.* & 3];
    vars.dma_source_addr_15.* = vars.dma_source_addr_10.* +% 0x100;

    vars.bg_tile_animation_countdown.* -%= 1;
    if (vars.bg_tile_animation_countdown.* == 0) {
        const ov: u8 = @truncate(vars.overlay_index.*);
        vars.bg_tile_animation_countdown.* = if (ov == 0xb5 or ov == 0xbc) 0x17 else 9;

        var t = vars.word_7EC00F.* +% 0x400;
        if (t == 0xc00)
            t = 0;
        vars.word_7EC00F.* = t;
        vars.animated_tile_data_src.* = 0xa680 +% vars.word_7EC00F.*;
    }

    vars.word_7EC013.* -%= 1;
    if (vars.word_7EC013.* == 0) {
        var t = vars.word_7EC015.* +% 2;
        if (t == 12)
            t = 0;
        vars.word_7EC015.* = t;
        vars.word_7EC013.* = kLinkDmaCtrs0[t >> 1];
        vars.dma_source_addr_9.* = kLinkDmaSources9[t >> 1] +% 0xb280;
        vars.dma_source_addr_14.* = vars.dma_source_addr_9.* +% 0x60;
    }

    vars.dma_source_addr_16.* = 0xB940 +% vars.dma_var6.* *% 2;
    vars.dma_source_addr_18.* = vars.dma_source_addr_16.* +% 0x200;

    vars.dma_source_addr_17.* = 0xB940 +% vars.dma_var7.* *% 2;
    vars.dma_source_addr_19.* = vars.dma_source_addr_17.* +% 0x200;

    vars.dma_source_addr_20.* = 0xB540 +% vars.flag_travel_bird.* *% 2;
    vars.dma_source_addr_21.* = vars.dma_source_addr_20.* +% 0x200;
}

pub export fn Sound_LoadIntroSongBank() callconv(.c) void { // 808901
    audio.LoadSongBank(kSoundBank_intro());
}

pub export fn LoadOverworldSongs() callconv(.c) void { // 808913
    audio.LoadSongBank(kSoundBank_intro());
}

pub export fn LoadDungeonSongs() callconv(.c) void { // 808925
    audio.LoadSongBank(kSoundBank_indoor());
}

pub export fn LoadCreditsSongs() callconv(.c) void { // 808931
    audio.LoadSongBank(kSoundBank_ending());
}

pub export fn Dungeon_LightTorch() callconv(.c) void { // 81f3ec
    if ((vars.byte_7E0333.* & 0xf0) != 0xc0) {
        vars.byte_7E0333.* = 0;
        return;
    }
    const r8: u8 = if (@as(u8, @truncate(vars.dungeon_room_index.*)) == 0) 0x80 else 0xc0;

    const i: usize = (vars.byte_7E0333.* & 0xf) + (vars.dung_index_of_torches_start.* >> 1);
    const opos = vars.dung_object_pos_in_objdata[i];
    if (vars.dung_object_tilemap_pos[i] & 0x8000 != 0)
        return;
    vars.dung_object_tilemap_pos[i] |= 0x8000;
    if (r8 == 0)
        vars.dung_torch_data[opos] = vars.dung_object_tilemap_pos[i];

    const x = vars.dung_object_tilemap_pos[i] & 0x3fff;
    RoomDraw_AdjustTorchLightingChange(x, 0xeca, x);

    vars.sound_effect_1.* = 42 | CalculateSfxPan_Arbitrary(@truncate((x & 0x7f) * 2));

    vars.nmi_copy_packets_flag.* = 1;
    if (vars.dung_want_lights_out.* != 0) {
        const n = vars.dung_num_lit_torches.*;
        vars.dung_num_lit_torches.* +%= 1;
        if (n < 3) {
            vars.TS_copy.* = 0;
            vars.overworld_fixed_color_plusminus.* = rtl.kLitTorchesColorPlus[vars.dung_num_lit_torches.*];
            vars.submodule_index.* = 10;
            vars.subsubmodule_index.* = 0;
        }
    }

    vars.dung_torch_timers[vars.byte_7E0333.* & 0xf] = r8;
    vars.byte_7E0333.* = 0;
}

pub export fn RoomDraw_AdjustTorchLightingChange(x_in: u16, y: u16, r8: u16) callconv(.c) void { // 81f746
    const ptr = SrcPtr(y);
    const x = x_in >> 1;
    vars.overworld_tileattr[x + 0] = ptr[0];
    vars.overworld_tileattr[x + 64] = ptr[1];
    vars.overworld_tileattr[x + 1] = ptr[2];
    vars.overworld_tileattr[x + 65] = ptr[3];
    _ = Dungeon_PrepOverlayDma_nextPrep(0, r8);
}

pub export fn Dungeon_PrepOverlayDma_nextPrep(dst: c_int, r8: u16) callconv(.c) c_int { // 81f764
    const r6: u16 = 0x880 + @as(u16, @intFromBool((r8 & 0x3f) >= 0x3a));
    return Dungeon_PrepOverlayDma_watergate(dst, r8, r6, 4);
}

pub export fn Dungeon_PrepOverlayDma_watergate(dst_in: c_int, r8_in: u16, r6: u16, loops: c_int) callconv(.c) c_int { // 81f77c
    var dst: usize = @intCast(dst_in);
    var r8 = r8_in;
    var k: c_int = 0;
    while (k < loops) : (k += 1) {
        const x = r8 >> 1;
        vars.vram_upload_tile_buf[dst + 0] = ((r8 & 0x40) << 4) | ((r8 & 0x303f) >> 1) | ((r8 & 0xf80) >> 2);
        vars.vram_upload_tile_buf[dst + 1] = r6;
        vars.vram_upload_tile_buf[dst + 2] = vars.overworld_tileattr[x + 0];
        if ((r6 & 1) == 0) {
            vars.vram_upload_tile_buf[dst + 3] = vars.overworld_tileattr[x + 1];
            vars.vram_upload_tile_buf[dst + 4] = vars.overworld_tileattr[x + 2];
            vars.vram_upload_tile_buf[dst + 5] = vars.overworld_tileattr[x + 3];
            r8 +%= 128;
        } else {
            vars.vram_upload_tile_buf[dst + 3] = vars.overworld_tileattr[x + 64];
            vars.vram_upload_tile_buf[dst + 4] = vars.overworld_tileattr[x + 128];
            vars.vram_upload_tile_buf[dst + 5] = vars.overworld_tileattr[x + 192];
            r8 +%= 2;
        }
        dst += 6;
    }
    vars.vram_upload_tile_buf[dst] = 0xffff;
    return @intCast(dst);
}

pub export fn Module05_LoadFile() callconv(.c) void { // 828136
    EnableForceBlank();
    vars.overworld_map_state.* = 0;
    vars.dung_unk6.* = 0;
    vars.byte_7E02D4.* = 0;
    vars.byte_7E02D7.* = 0;
    vars.tagalong_var5.* = 0;
    vars.byte_7E0379.* = 0;
    vars.byte_7E03FD.* = 0;
    EraseTileMaps_normal();
    LoadDefaultGraphics();
    Sprite_LoadGraphicsProperties();
    Init_LoadDefaultTileAttr();
    DecompressSwordGraphics();
    DecompressShieldGraphics();
    Link_Initialize();
    LoadFollowerGraphics();
    vars.sprite_gfx_subset_0.* = 70;
    vars.sprite_gfx_subset_1.* = 70;
    vars.sprite_gfx_subset_2.* = 70;
    vars.sprite_gfx_subset_3.* = 70;
    vars.word_7E02CD.* = 0x200;
    vars.virq_trigger.* = 48;
    // Saved inside a dungeon: back in through its entrance, as after falling
    // in battle there, rather than the choice of places to start.
    if (messaging.dungeonContinueEntrance()) |entrance| {
        vars.which_entrance.* = entrance;
        vars.player_is_indoors.* = 1;
        vars.death_var4.* = 0;
        LoadDungeonRoomRebuildHUD();
        return;
    }
    if (vars.savegame_is_darkworld.* != 0) {
        if (vars.player_is_indoors.* != 0) {
            LoadDungeonRoomRebuildHUD();
            return;
        }
        Hud_SearchForEquippedItem();
        Hud_Rebuild();
        Hud_UpdateEquippedItem();
        vars.death_var5.* = 0;
        vars.dungeon_room_index.* = 32;
        vars.main_module_index.* = 8;
        vars.submodule_index.* = 0;
        vars.subsubmodule_index.* = 0;
        vars.death_var4.* = 0;
    } else {
        if (vars.mosaic_level.* != 0 or
            (vars.death_var5.* != 0 and vars.death_var4.* == 0) or
            vars.sram_progress_indicator.* < 2 or
            vars.which_starting_point.* == 5)
        {
            LoadDungeonRoomRebuildHUD();
            return;
        }
        vars.dialogue_message_index.* = if (vars.link_item_mirror.* == 2) 0x185 else 0x184;
        Main_ShowTextMessage();
        Dungeon_LoadPalettes();
        vars.INIDISP_copy.* = 15;
        vars.TM_copy.* = 4;
        vars.TS_copy.* = 0;
        vars.main_module_index.* = 27;
    }
}

pub export fn Module13_BossVictory_Pendant() callconv(.c) void { // 829c4a
    kModule_BossVictory[vars.submodule_index.*]();
    Sprite_Main();
    LinkOam_Main();
}

pub export fn BossVictory_Heal() callconv(.c) void { // 829c59
    if (!Hud_RefillMagicPower())
        vars.overworld_map_state.* +%= 1;
    if (!Hud_RefillHealth())
        vars.overworld_map_state.* +%= 1;
    if (vars.overworld_map_state.* == 0) {
        vars.button_mask_b_y.* &= ~@as(u8, 0x40);
        Dungeon_ResetTorchBackgroundAndPlayerInner();
        vars.link_direction_facing.* = 2;
        vars.link_direction_last.* = 2 << 1;
        vars.flag_update_hud_in_nmi.* +%= 1;
        vars.submodule_index.* +%= 1;
        vars.subsubmodule_index.* = 16;
        vars.flag_is_link_immobilized.* +%= 1;
    }
    vars.overworld_map_state.* = 0;
    Hud_RefillLogic();
}

pub export fn Dungeon_StartVictorySpin() callconv(.c) void { // 829c93
    vars.subsubmodule_index.* -%= 1;
    if (vars.subsubmodule_index.* != 0)
        return;
    vars.flag_is_link_immobilized.* = 0;
    vars.link_direction_facing.* = 2;
    Link_AnimateVictorySpin();
    _ = Ancilla_TerminateSelectInteractives(0);
    AncillaAdd_VictorySpin();
    vars.submodule_index.* +%= 1;
}

pub export fn Dungeon_RunVictorySpin() callconv(.c) void { // 829cad
    Link_Main();
    if (vars.link_player_handler_state.* != 0)
        return;
    if ((vars.link_sword_type.* +% 1) & 0xfe != 0)
        vars.sound_effect_1.* = 0x2C;
    vars.link_force_hold_sword_up.* = 1;
    vars.subsubmodule_index.* = 32;
    vars.submodule_index.* +%= 1;
}

pub export fn Dungeon_CloseVictorySpin() callconv(.c) void { // 829cd1
    vars.subsubmodule_index.* -%= 1;
    if (vars.subsubmodule_index.* != 0)
        return;
    vars.submodule_index.* +%= 1;
    vars.link_y_vel.* = 0;
    vars.link_x_vel.* = 0;
    vars.overworld_fixed_color_plusminus.* = 0;
}

pub export fn Module15_MirrorWarpFromAga() callconv(.c) void { // 829cfc
    kModule_KillAgahnim[vars.submodule_index.*]();
    if (vars.submodule_index.* < 2 or vars.submodule_index.* >= 5) {
        Sprite_Main();
        LinkOam_Main();
    }
}

pub export fn Module16_BossVictory_Crystal() callconv(.c) void { // 829e8a
    switch (vars.submodule_index.*) {
        0 => BossVictory_Heal(),
        1 => Dungeon_StartVictorySpin(),
        2 => Dungeon_RunVictorySpin(),
        3 => Dungeon_CloseVictorySpin(),
        4 => Module16_04_FadeAndEnd(),
        else => {},
    }
    Sprite_Main();
    LinkOam_Main();
}

pub export fn Module16_04_FadeAndEnd() callconv(.c) void { // 829e9a
    vars.INIDISP_copy.* -%= 1;
    if (vars.INIDISP_copy.* != 0)
        return;
    vars.bg1_x_offset.* = 0;
    vars.bg1_y_offset.* = 0;
    vars.link_y_vel.* = 0;
    vars.flag_is_link_immobilized.* = 0;
    Palette_RevertTranslucencySwap();
    vars.link_player_handler_state.* = kPlayerState_Ground;
    vars.link_receiveitem_index.* = 0;
    vars.link_pose_for_item.* = 0;
    vars.link_disable_sprite_damage.* = 0;
    vars.main_module_index.* = vars.saved_module_for_menu.*;
    vars.submodule_index.* = 0;
    vars.subsubmodule_index.* = 0;
    OpenSpotlight_Next2();
}

fn PlaySfx_SetPan(a: u8) u8 { // 878036
    vars.byte_7E0CF8.* = a;
    return a | Link_CalculateSfxPan();
}

pub export fn TriforceRoom_LinkApproachTriforce() callconv(.c) void { // 87f49c
    const y: u8 = @truncate(vars.link_y_coord.*);
    if (y < 152) {
        vars.link_animation_steps.* = 0;
        vars.link_direction.* = 0;
        vars.link_direction_last.* = 0;
        vars.link_delay_timer_spin_attack.* -%= 1;
        if (vars.link_delay_timer_spin_attack.* == 0) {
            vars.link_pose_for_item.* = 2;
            vars.subsubmodule_index.* +%= 1;
        }
    } else {
        if (y < 169)
            vars.link_speed_setting.* = 0x14;
        vars.link_direction.* = 8;
        vars.link_direction_last.* = 8;
        vars.link_direction_facing.* = 0;
        vars.link_delay_timer_spin_attack.* = 64;
    }
}

pub export fn AncillaAdd_ItemReceipt(ain: u8, yin: u8, chest_pos: c_int) callconv(.c) void { // 8985e8
    const ancilla = Ancilla_AddAncilla(ain, yin);
    if (ancilla < 0)
        return;
    const a: usize = @intCast(ancilla);

    vars.flag_is_link_immobilized.* = if (vars.link_receiveitem_index.* == 0x20) 2 else 1;

    const j: usize = vars.link_receiveitem_index.*;
    if (j == 0)
        g_ram[kMemoryLocationToGiveItemTo[4]] = @bitCast(kValueToGiveItemTo[0]);

    const v: u8 = @bitCast(kValueToGiveItemTo[j]);
    const p: [*]u8 = g_ram[kMemoryLocationToGiveItemTo[j]..].ptr;
    if (v & 0x80 == 0)
        p[0] = v;

    if (j == 0x1f) {
        vars.link_is_bunny.* = 0;
    } else if (j == 0x4b or j == 0x1e) {
        vars.link_ability_flags.* |= if (j == 0x4b) 4 else 2;
    }

    if (j == 0x1b or j == 0x1c) {
        Palette_UpdateGlovesColor();
    } else if (j == 0x37 or j == 0x38 or j == 0x39) {
        // The C assigns t through the comma operator as it tests each case.
        const t: u8 = if (j == 0x37) 4 else if (j == 0x38) 1 else 2;
        p[0] |= t;
        if ((p[0] & 7) == 7)
            vars.savegame_map_icons_indicator.* = 4;
        vars.overworld_map_state.* +%= 1;
    } else if (j == 0x22) {
        if (p[0] == 0)
            p[0] = 1;
    } else if (j == 0x25 or j == 0x32 or j == 0x33) {
        const cur = std.mem.readInt(u16, p[0..2], .little);
        const bit = @as(u16, 0x8000) >> @intCast(@as(u8, @truncate(vars.cur_palace_index_x2.*)) >> 1);
        std.mem.writeInt(u16, p[0..2], cur | bit, .little);
    } else if (j == 0x3e) {
        if (vars.link_state_bits.* & 0x80 != 0)
            vars.link_picking_throw_state.* = 2;
    } else if (j == 0x20) {
        vars.overworld_map_state.* +%= 1;
        var i: i32 = 4;
        while (i >= 0) : (i -= 1) {
            const idx: usize = @intCast(i);
            if (vars.ancilla_type[idx] == 7 or vars.ancilla_type[idx] == 0x2c) {
                vars.ancilla_type[idx] = 0;
                vars.link_state_bits.* = 0;
                vars.link_picking_throw_state.* = 0;
            }
        }
        if (vars.link_cape_mode.* != 0) {
            vars.link_bunny_transform_timer.* = 32;
            vars.link_disable_sprite_damage.* = 0;
            vars.link_cape_mode.* = 0;
            AncillaAdd_CapePoof(0x23, 4);
            vars.sound_effect_1.* = 0x15 | Link_CalculateSfxPan();
        }
    } else if (j == 0x29) {
        if (vars.link_item_mushroom.* != 2) {
            p[0] = 1;
            Hud_RefreshIcon();
        }
    } else if (j == 0x24 or (vars.item_receipt_method.* != 2 and (j == 0x27 or j == 0x28 or j == 0x31))) {
        const t: u8 = switch (j) {
            0x28 => 3,
            0x31 => 10,
            else => 1,
        };
        p[0] +%= t;
        if (p[0] > 99)
            p[0] = 99;
        Hud_RefreshIcon();
    } else if (j == 0x17) {
        p[0] = (p[0] +% 1) & 3;
        vars.sound_effect_2.* = 0x2d | Link_CalculateSfxPan();
    } else if (j == 1) {
        Overworld_SetSongList();
    } else {
        ItemReceipt_GiveBottledItem(@intCast(j));
    }

    var gfx = kReceiveItemGfx[j];
    if (gfx == 0xff) {
        gfx = 0;
    } else if (gfx == 0x20 or gfx == 0x2d or gfx == 0x2e) {
        DecompressShieldGraphics();
        Palette_Load_Shield();
    }
    DecodeAnimatedSpriteTile_variable(gfx);

    if ((gfx == 6 or gfx == 0x18) and j != 0) {
        DecompressSwordGraphics();
        Palette_Load_Sword();
    }

    vars.ancilla_item_to_link[a] = @intCast(j);
    vars.ancilla_arr1[a] = 0;

    if (j == 1 and vars.item_receipt_method.* != 2) {
        vars.ancilla_timer[a] = 160;
        vars.submodule_index.* = 43;
        @as([*]u8, @ptrCast(vars.palette_filter_countdown))[0] = 0;
        AncillaAdd_MSCutscene(0x35, 4);
        vars.ancilla_arr3[a] = 2;
    } else {
        vars.ancilla_arr3[a] = 9;
    }
    vars.ancilla_arr4[a] = 5;
    vars.ancilla_step[a] = vars.item_receipt_method.*;

    vars.ancilla_aux_timer[a] = if (j == 0x20 or j == 0x37 or j == 0x38 or j == 0x39)
        0x68
    else if (j == 0x26)
        0x2
    else if (vars.item_receipt_method.* != 0)
        0x38
    else
        0x60;

    var x: i32 = undefined;
    var y: i32 = undefined;

    if (vars.item_receipt_method.* == 1) {
        y = (chest_pos & 0x1f80) >> 4;
        x = (chest_pos & 0x7e) << 2;
        y += @as(i32, vars.dung_loade_bgoffs_v_copy.*) & ~@as(i32, 0xff);
        x += @as(i32, vars.dung_loade_bgoffs_h_copy.*) & ~@as(i32, 0xff);
        y += kReceiveItem_Tab2[j];
        x += kReceiveItem_Tab3[j];
    } else {
        if (vars.ancilla_step[a] == 0 and j == 1) {
            vars.sound_effect_1.* = Link_CalculateSfxPan() | 0x2c;
        } else if (j == 0x20 or j == 0x37 or j == 0x38 or j == 0x39) {
            vars.music_control.* = Link_CalculateSfxPan() | 0x13;
        } else if (j != 0x3e and j != 0x17) {
            vars.sound_effect_2.* = Link_CalculateSfxPan() | 0xf;
        }
        const method: u8 = if (vars.item_receipt_method.* == 3) 0 else vars.item_receipt_method.*;
        x = if (method != 0)
            kReceiveItem_Tab3[j]
        else if (kReceiveItem_Tab1[j] == 0)
            10
        else if (j == 0x20)
            0
        else
            6;
        x += vars.link_x_coord.*;
        y = if (method != 0) kReceiveItem_Tab2[j] else -14;
        y += @as(i32, vars.link_y_coord.*) + (if (method == 2) @as(i32, -8) else 0);
    }
    Ancilla_SetXY(ancilla, @truncate(@as(u32, @bitCast(x))), @truncate(@as(u32, @bitCast(y))));
}

pub export fn ItemReceipt_GiveBottledItem(item: u8) callconv(.c) void { // 89893e
    const kBottleList = [7]u8{ 0x16, 0x2b, 0x2c, 0x2d, 0x3d, 0x3c, 0x48 };
    const kPotionList = [5]u8{ 0x2e, 0x2f, 0x30, 0xff, 0xe };
    if (findInByteArray(&kBottleList, item)) |j| {
        for (0..4) |i| {
            if (vars.link_bottle_info[i] < 2) {
                vars.link_bottle_info[i] = @intCast(j + 2);
                return;
            }
        }
    }
    if (findInByteArray(&kPotionList, item)) |j| {
        for (0..4) |i| {
            if (vars.link_bottle_info[i] == 2) {
                vars.link_bottle_info[i] = @intCast(j + 3);
                return;
            }
        }
    }
}

/// misc.h's FindInByteArray, which searches backwards.
fn findInByteArray(data: []const u8, lookfor: u8) ?usize {
    var i = data.len;
    while (i != 0) {
        i -= 1;
        if (data[i] == lookfor)
            return i;
    }
    return null;
}

pub export fn Module17_SaveAndQuit() callconv(.c) void { // 89f79f
    switch (vars.submodule_index.*) {
        0 => {
            vars.submodule_index.* +%= 1;
            // falls through to case 1
            vars.INIDISP_copy.* -%= 1;
            if (vars.INIDISP_copy.* == 0) {
                vars.MOSAIC_copy.* = 15;
                vars.subsubmodule_index.* = 1;
                Death_Func15(false);
            }
        },
        1 => {
            vars.INIDISP_copy.* -%= 1;
            if (vars.INIDISP_copy.* == 0) {
                vars.MOSAIC_copy.* = 15;
                vars.subsubmodule_index.* = 1;
                Death_Func15(false);
            }
        },
        else => {},
    }
    Sprite_Main();
    LinkOam_Main();
}

pub export fn WallMaster_SendPlayerToLastEntrance() callconv(.c) void { // 8bffa8
    SaveDungeonKeys();
    Dungeon_FlagRoomData_Quadrants();
    Sprite_ResetAll();
    vars.death_var4.* = 0;
    vars.main_module_index.* = 17;
    vars.submodule_index.* = 0;
    vars.nmi_load_bg_from_vram.* = 0;
    ResetSomeThingsAfterDeath(17); // wtf: argument?
}

pub export fn GetRandomNumber() callconv(.c) u8 { // 8dba71
    var t = vars.byte_7E0FA1.* +% vars.frame_counter.*;
    t = if (t & 1 != 0) (t >> 1) else (t >> 1) ^ 0xb8;
    vars.byte_7E0FA1.* = t;
    return t;
}

pub export fn Link_CalculateSfxPan() callconv(.c) u8 { // 8dbb67
    return CalculateSfxPan(vars.link_x_coord.*);
}

pub export fn SpriteSfx_QueueSfx1WithPan(k: c_int, a: u8) callconv(.c) void { // 8dbb6e
    if (vars.sound_effect_ambient.* == 0)
        vars.sound_effect_ambient.* = a | Sprite_CalculateSfxPan(k);
}

pub export fn SpriteSfx_QueueSfx2WithPan(k: c_int, a: u8) callconv(.c) void { // 8dbb7c
    if (vars.sound_effect_1.* == 0)
        vars.sound_effect_1.* = a | Sprite_CalculateSfxPan(k);
}

pub export fn SpriteSfx_QueueSfx3WithPan(k: c_int, a: u8) callconv(.c) void { // 8dbb8a
    if (vars.sound_effect_2.* == 0)
        vars.sound_effect_2.* = a | Sprite_CalculateSfxPan(k);
}

pub export fn Sprite_CalculateSfxPan(k: c_int) callconv(.c) u8 { // 8dbba1
    return CalculateSfxPan(Sprite_GetX(k));
}

const kPanTable = [3]u8{ 0, 0x80, 0x40 };

pub export fn CalculateSfxPan(x_in: u16) callconv(.c) u8 { // 8dbba8
    var o: usize = 0;
    const x = x_in -% (vars.BG2HOFS_copy2.* +% 80);
    if (x >= 80)
        o = 1 + @as(usize, @intFromBool(@as(i16, @bitCast(x)) >= 0));
    return kPanTable[o];
}

const kTorchPans = [8]u8{ 0x80, 0x80, 0x80, 0, 0, 0x40, 0x40, 0x40 };

pub export fn CalculateSfxPan_Arbitrary(a: u8) callconv(.c) u8 { // 8dbbd0
    return kTorchPans[((a -% @as(u8, @truncate(vars.BG2HOFS_copy2.*))) >> 5) & 7];
}

pub export fn Init_LoadDefaultTileAttr() callconv(.c) void { // 8e97d9
    @memcpy(vars.attributes_for_tile[0..0x140], kDungeon_DefaultAttr[0..0x140]);
    @memcpy(vars.attributes_for_tile[0x1c0..][0..64], kDungeon_DefaultAttr[0x140..][0..64]);
}

pub export fn Main_ShowTextMessage() callconv(.c) void { // 8ffdaa
    if (vars.main_module_index.* != 14) {
        vars.byte_7E0223.* = 0;
        vars.messaging_module.* = 0;
        vars.submodule_index.* = 2;
        vars.saved_module_for_menu.* = vars.main_module_index.*;
        vars.main_module_index.* = 14;
    }
}

pub export fn HandleItemTileAction_Overworld(x: u16, y: u16) callconv(.c) u8 { // 9bbd7a
    if (vars.player_is_indoors.* != 0)
        return HandleItemTileAction_Dungeon(x, y);
    return @truncate(Overworld_ToolAndTileInteraction(x, y));
}

const testing = std.testing;

test "the item receipt tables all cover the same 76 items" {
    try testing.expectEqual(76, kReceiveItem_Tab1.len);
    try testing.expectEqual(76, kReceiveItem_Tab2.len);
    try testing.expectEqual(76, kReceiveItem_Tab3.len);
    try testing.expectEqual(76, kReceiveItemGfx.len);
    try testing.expectEqual(76, kMemoryLocationToGiveItemTo.len);
    try testing.expectEqual(76, kValueToGiveItemTo.len);
    // Every target address is inside the save-game block.
    for (kMemoryLocationToGiveItemTo) |addr|
        try testing.expect(addr >= 0xf340 and addr <= 0xf37a);
}

test "the dungeon default tile attributes fill both copied ranges" {
    try testing.expectEqual(384, kDungeon_DefaultAttr.len);
    // Init_LoadDefaultTileAttr copies 0x140 then another 64 bytes.
    try testing.expectEqual(0x140 + 64, 384);
    try testing.expectEqual(@as(u8, 1), kDungeon_DefaultAttr[0]);
    try testing.expectEqual(@as(u8, 9), kDungeon_DefaultAttr[383]);
}

test "the link dma tables came over at the right sizes" {
    try testing.expectEqual(303, kLinkDmaSources1.len);
    try testing.expectEqual(303, kLinkDmaSources2.len);
    try testing.expectEqual(27, kLinkDmaSources3.len);
    try testing.expectEqual(8, kLinkDmaSources4.len);
    try testing.expectEqual(3, kLinkDmaSources5.len);
    try testing.expectEqual(128, kLinkDmaSources6.len);
    try testing.expectEqual(16, kLinkDmaSources7.len);
    try testing.expectEqual(6, kLinkDmaCtrs0.len);
    try testing.expectEqual(15, kLinkDmaSources9.len);
    try testing.expectEqual(4, kLinkDmaSources8.len);
    try testing.expectEqual(@as(u16, 0x8080), kLinkDmaSources1[0]);
    try testing.expectEqual(@as(u16, 0xa840), kLinkDmaSources1[302]);
    try testing.expectEqual(@as(u16, 0x8840), kLinkDmaSources2[0]);
    try testing.expectEqual(@as(u16, 0xedc0), kLinkDmaSources2[302]);
}

test "the main routing table dispatches all 28 modules" {
    try testing.expectEqual(28, kMainRouting.len);
    try testing.expectEqual(6, kModule_BossVictory.len);
    try testing.expectEqual(13, kModule_KillAgahnim.len);
    // The overworld load/run pair repeats at 8..11.
    try testing.expectEqual(kMainRouting[8], kMainRouting[10]);
    try testing.expectEqual(kMainRouting[9], kMainRouting[11]);
    // File select's four modules are the ported Zig ones.
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &select_file.Module01_FileSelect), kMainRouting[1]);
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &select_file.Module04_NameFile), kMainRouting[4]);
}

test "sfx panning splits the screen into three zones" {
    @memset(g_ram[0..0x1000], 0);
    vars.BG2HOFS_copy2.* = 0;
    // Left of the window pans left, the middle is centered, the right pans right.
    try testing.expectEqual(@as(u8, 0), CalculateSfxPan(80)); // dead center
    try testing.expectEqual(@as(u8, 0x40), CalculateSfxPan(200)); // far right
    try testing.expectEqual(@as(u8, 0x80), CalculateSfxPan(0)); // far left
    try testing.expectEqual(3, kPanTable.len);
}

test "torch panning buckets by distance from the scroll position" {
    @memset(g_ram[0..0x1000], 0);
    vars.BG2HOFS_copy2.* = 0;
    try testing.expectEqual(@as(u8, 0x80), CalculateSfxPan_Arbitrary(0));
    try testing.expectEqual(@as(u8, 0), CalculateSfxPan_Arbitrary(0x60));
    try testing.expectEqual(@as(u8, 0x40), CalculateSfxPan_Arbitrary(0xa0));
    try testing.expectEqual(8, kTorchPans.len);
}

test "the random generator is a feedback shift over two ram bytes" {
    @memset(g_ram[0..0x1000], 0);
    vars.byte_7E0FA1.* = 0;
    vars.frame_counter.* = 1;
    // 0 + 1 = 1, odd, so it just shifts right to 0.
    try testing.expectEqual(@as(u8, 0), GetRandomNumber());

    vars.byte_7E0FA1.* = 0;
    vars.frame_counter.* = 2;
    // 2 is even, so it shifts and xors with 0xb8.
    try testing.expectEqual(@as(u8, 1 ^ 0xb8), GetRandomNumber());
    try testing.expectEqual(@as(u8, 1 ^ 0xb8), vars.byte_7E0FA1.*);
}

test "the backwards array search matches the C helper" {
    const data = [_]u8{ 1, 2, 3, 2, 5 };
    // It walks backwards, so the LAST match wins.
    try testing.expectEqual(@as(?usize, 3), findInByteArray(&data, 2));
    try testing.expectEqual(@as(?usize, 0), findInByteArray(&data, 1));
    try testing.expectEqual(@as(?usize, 4), findInByteArray(&data, 5));
    try testing.expectEqual(@as(?usize, null), findInByteArray(&data, 9));
}

test "bottles and potions land in the first free slot" {
    @memset(g_ram[0..0x20000], 0);
    // 0x16 is the first bottle; index 0 in the list, so the slot gets 2.
    ItemReceipt_GiveBottledItem(0x16);
    try testing.expectEqual(@as(u8, 2), vars.link_bottle_info[0]);
    // A second bottle fills the next free slot.
    ItemReceipt_GiveBottledItem(0x2b);
    try testing.expectEqual(@as(u8, 3), vars.link_bottle_info[1]);
    // A potion replaces an empty bottle (value 2) rather than taking a slot.
    ItemReceipt_GiveBottledItem(0x2e);
    try testing.expectEqual(@as(u8, 3), vars.link_bottle_info[0]);
}
