//! Port of src/ending.c: the intro sequence (triforce polyhedron, the falling
//! sword, the logo), the Ganon-emerges and triforce-room modules, and the whole
//! end credits -- scene loading, scrolling, per-scene sprite choreography and
//! the scrolling attribution text.
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl.zig");
const rtl_types = @import("zelda_rtl_types.zig");
const features = @import("features.zig");
const main_mod = @import("main.zig");
const tables = @import("ending_tables.zig");
const load_gfx = @import("load_gfx.zig");
const misc = @import("misc.zig");
const hud = @import("hud.zig");
const player_oam = @import("player_oam.zig");

const OamEnt = vars.OamEnt;
const g_ram = &vars.g_ram;
const g_zenv = &rtl_types.g_zenv;
const oam_buf = vars.oam_buf;
const bytewise_extended_oam = vars.bytewise_extended_oam;

/// zelda_rtl.h: typedef void PlayerHandlerFunc();
const PlayerHandlerFunc = fn () callconv(.c) void;

// snes/snes_regs.h
const BG1SC = 0x2107;
const BG2SC = 0x2108;
const BG3SC = 0x2109;
const BG2HOFS = 0x210f;

/// ending.h
pub const IntroSpriteEnt = extern struct {
    x: i8,
    y: i8,
    charnum: u8,
    flags: u8,
    ext: u8,
};

/// sprite.h
pub const DrawMultipleData = extern struct {
    x: i8,
    y: i8,
    char_flags: u16,
    ext: u8,
};

/// sprite.h
pub const PrepOamCoordsRet = extern struct {
    x: u16,
    y: u16,
    r4: u8,
    flags: u8,
};

/// dungeon.h
pub const DungPalInfo = extern struct {
    pal0: u8,
    pal1: u8,
    pal2: u8,
    pal3: u8,
};

// ---------------------------------------------------------------------------
// Helpers for the C macros this file leans on.
// ---------------------------------------------------------------------------

/// types.h BYTE(): the low byte of a 16-bit work-ram variable.
inline fn loPtr(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

/// types.h HIBYTE().
inline fn hiPtr(p: *align(1) u16) *u8 {
    return @ptrCast(@as([*]u8, @ptrCast(p)) + 1);
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

inline fn abs8(t: u8) u8 {
    return if (sign8(t)) 0 -% t else t;
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

/// sprite.h. The y clamp keeps sprites that wrapped off the top parked at 0xf0,
/// and the high bit of x rides along in the extended oam byte.
fn SetOamHelper0(oam: [*]align(1) OamEnt, x: u16, y: u16, charnum: u8, flags: u8, big: u8) void {
    oam[0].x = @truncate(x);
    oam[0].y = if (y +% 0x10 < 0x100) @as(u8, @truncate(y)) else 0xf0;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    const index = (@intFromPtr(oam) - @intFromPtr(oam_buf)) / @sizeOf(OamEnt);
    // Zig gives |, ^ and & equal precedence (left-assoc), unlike C where & binds
    // tighter, so the mask needs explicit parens to keep the C's `big | (hi & 1)`.
    bytewise_extended_oam[index] = big | (@as(u8, @truncate(x >> 8)) & 1);
}

// ---------------------------------------------------------------------------
// Work-ram locations ending.c names with its own file-local macros. Several of
// these deliberately alias R16/R18, exactly as the original does.
// ---------------------------------------------------------------------------

const ending_which_dung: *align(1) u16 = @ptrCast(&vars.g_ram[0xcc]);
const kPolyThreadRam = 0x1f00;

const intro_sword_ypos: *align(1) u16 = @ptrCast(&vars.g_ram[0xc8]);
const intro_sword_18: *u8 = &vars.g_ram[0xca];
const intro_sword_19: *u8 = &vars.g_ram[0xcb];
const intro_sword_20: *u8 = &vars.g_ram[0xcc];
const intro_sword_21: *u8 = &vars.g_ram[0xcd];
const intro_sword_24: *u8 = &vars.g_ram[0xd0];

/// COLDATA_copy0..2 are three consecutive bytes; the sword flash indexes them.
const coldata_copies: [*]u8 = @ptrCast(&vars.g_ram[0x9c]);

// assets.h
inline fn kGeneratedEndSequence15() [*]const u8 {
    return main_mod.g_asset_ptrs[73].?;
}
inline fn kEnding_Credits_Text() [*]const u8 {
    return main_mod.g_asset_ptrs[74].?;
}
inline fn kEnding_Credits_Offs() [*]align(1) const u16 {
    return @ptrCast(main_mod.g_asset_ptrs[75].?);
}
inline fn kEnding_MapData() [*]align(1) const u16 {
    return @ptrCast(main_mod.g_asset_ptrs[76].?);
}
inline fn kEnding0_Offs() [*]align(1) const u16 {
    return @ptrCast(main_mod.g_asset_ptrs[77].?);
}
inline fn kEnding0_Data() [*]const u8 {
    return main_mod.g_asset_ptrs[78].?;
}

var g_ending_coords: PrepOamCoordsRet = std.mem.zeroes(PrepOamCoordsRet);

// ---------------------------------------------------------------------------
// Still in C.
// ---------------------------------------------------------------------------

// messaging.c
extern const kHealthAfterDeath: [21]u8;
extern fn BirdTravel_Finish_Doit() void;
extern fn FluteMenu_LoadSelectedScreen() void;
extern fn Overworld_LoadOverlayAndMap() void;
extern fn RenderText() void;
extern fn SaveGameFile() void;
extern fn Text_GenerateMessagePointers() void;
// dungeon.c
extern const kDungAnimatedTiles: [24]u8;
extern fn Dungeon_HandleLayerEffect() void;
extern fn Dungeon_LoadAndDrawRoom() void;
extern fn Dungeon_LoadEntrance() void;
extern fn GetDungPalInfo(idx: c_int) *const DungPalInfo;
extern fn LoadOWMusicIfNeeded() void;
extern fn ResetTransitionPropsAndAdvance_ResetInterface() void;
extern fn SaveDungeonKeys() void;
// overworld.c
extern fn ConditionalMosaicControl() void;
extern fn GetOverworldBgPalette(idx: c_int) u8;
extern fn LoadOverworldFromDungeon() void;
extern fn Module08_02_LoadAndAdvance() void;
extern fn OverworldHandleMapScroll() void;
extern fn Overworld_EnterSpecialArea() void;
extern fn Overworld_LoadAndBuildScreen() void;
extern fn Overworld_LoadOverlays2() void;
extern fn Overworld_SetFixedColAndScroll() void;
extern fn Palette_AnimGetMasterSword2() void;
// player.c
extern fn Link_HandleMovingAnimation_FullLongEntry() void;
extern fn Link_HandleVelocity() void;
extern fn Link_ResetProperties_A() void;
// ancilla.c
extern fn CallForDuckIndoors() void;
// sprite.c
extern fn Oam_AllocateFromRegionA(num: u8) u8;
extern fn SpriteDraw_Shadow(k: c_int, oam: *PrepOamCoordsRet) void;
extern fn SpritePrep_ResetProperties(k: c_int) void;
extern fn Sprite_DrawMultiple(k: c_int, src: [*]const DrawMultipleData, n: c_int, info: *PrepOamCoordsRet) void;
extern fn Sprite_Get16BitCoords(k: c_int) void;
extern fn Sprite_Main() void;
extern fn Sprite_MoveXY(k: c_int) void;
extern fn Sprite_SetX(k: c_int, x: u16) void;
extern fn Sprite_SetY(k: c_int, y: u16) void;
// sprite_main.c
extern fn SpriteActive_Main(k: c_int) void;
extern fn Sprite_SpawnBatCrashCutscene() void;

// ---------------------------------------------------------------------------
// Module dispatch tables.
// ---------------------------------------------------------------------------

const kEndSequence0_Funcs = [3]*const PlayerHandlerFunc{
    &Credits_LoadScene_Overworld_PrepGFX,
    &Credits_LoadScene_Overworld_Overlay,
    &Credits_LoadScene_Overworld_LoadMap,
};

const kEndSequence_Funcs = [39]*const PlayerHandlerFunc{
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Dungeon,   &Credits_ScrollScene_Dungeon,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Dungeon,   &Credits_ScrollScene_Dungeon,
    &Credits_LoadNextScene_Dungeon,   &Credits_ScrollScene_Dungeon,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &Credits_LoadNextScene_Overworld, &Credits_ScrollScene_Overworld,
    &EndSequence_32,                  &Credits_BrightenTriangles,
    &Credits_FadeColorAndBeginAnimating, &Credits_StopCreditsScroll,
    &Credits_FadeAndDisperseTriangles, &Credits_FadeInTheEnd,
    &Credits_HangForever,
};

pub export fn Intro_SetupScreen() callconv(.c) void {
    vars.nmi_disable_core_updates.* = 0x80;
    load_gfx.EnableForceBlank();
    vars.TM_copy.* = 16;
    vars.TS_copy.* = 0;
    Intro_InitializeBackgroundSettings();
    vars.CGWSEL_copy.* = 0x20;
    vars.load_chr_halfslot_even_odd.* = 20;
    load_gfx.Graphics_LoadChrHalfSlot();
    vars.load_chr_halfslot_even_odd.* = 0;
    LoadOWMusicIfNeeded();

    // why 17?
    var i: usize = 0;
    while (i < 17) : (i += 1)
        vars.main_palette_buffer[144 + i] = 0x7fff;

    i = 0;
    while (i < 17) : (i += 1)
        g_zenv.vram.?[0x27f0 + i] = 0;

    vars.R16.* = 0x1ffe;
    vars.R18.* = 0x1bfe;
}

pub export fn Intro_LoadTextPointersAndPalettes() callconv(.c) void {
    Text_GenerateMessagePointers();
    load_gfx.Overworld_LoadAllPalettes();
}

pub export fn Credits_LoadScene_Overworld_PrepGFX() callconv(.c) void {
    load_gfx.EnableForceBlank();
    load_gfx.EraseTileMaps_normal();
    vars.CGWSEL_copy.* = 0x82;
    var k: usize = vars.submodule_index.* >> 1;
    vars.dungeon_room_index.* = tables.kEnding_Tab1[k];

    if (k != 6 and k != 15) {
        LoadOverworldFromDungeon();
    } else {
        Overworld_EnterSpecialArea();
    }
    vars.music_control.* = 0;
    vars.sound_effect_ambient.* = 0;

    const t = loPtr(vars.overworld_screen_index).* & ~@as(u8, 0x40);
    load_gfx.DecompressAnimatedOverworldTiles(if (t == 3 or t == 5 or t == 7) 0x58 else 0x5a);

    k = vars.submodule_index.* >> 1;
    vars.sprite_graphics_index.* = tables.kEnding_SpritePack[k];
    const sprpal = tables.kEnding_SpritePal[k];
    load_gfx.InitializeTilesets();
    load_gfx.OverworldLoadScreensPaletteSet();
    load_gfx.Overworld_LoadPalettes(GetOverworldBgPalette(loPtr(vars.overworld_screen_index).*), sprpal);

    vars.hud_palette.* = 1;
    load_gfx.Palette_Load_HUD();
    if (vars.submodule_index.* == 0)
        load_gfx.TransferFontToVRAM();
    load_gfx.Overworld_LoadPalettesInner();
    Overworld_SetFixedColAndScroll();
    if (loPtr(vars.overworld_screen_index).* >= 128)
        load_gfx.Palette_SetOwBgColor();
    vars.BGMODE_copy.* = 9;
    vars.subsubmodule_index.* +%= 1;
}

pub export fn Credits_LoadScene_Overworld_Overlay() callconv(.c) void {
    Overworld_LoadOverlays2();
    vars.music_control.* = 0;
    vars.sound_effect_ambient.* = 0;
    vars.submodule_index.* -%= 1;
    vars.subsubmodule_index.* +%= 1;
}

pub export fn Credits_LoadScene_Overworld_LoadMap() callconv(.c) void {
    Overworld_LoadAndBuildScreen();
    Credits_PrepAndLoadSprites();
    vars.R16.* = 0;
    vars.subsubmodule_index.* = 0;
}

pub export fn Credits_OperateScrollingAndTileMap() callconv(.c) void {
    Credits_HandleCameraScrollControl();
    if (loPtr(vars.overworld_screen_trans_dir_bits2).* != 0)
        OverworldHandleMapScroll();
}

pub export fn Credits_LoadCoolBackground() callconv(.c) void {
    vars.main_tile_theme_index.* = 33;
    vars.aux_tile_theme_index.* = 59;
    vars.sprite_graphics_index.* = 45;
    load_gfx.InitializeTilesets();
    loPtr(vars.overworld_screen_index).* = 0x5b;
    load_gfx.Overworld_LoadPalettes(GetOverworldBgPalette(loPtr(vars.overworld_screen_index).*), 0x13);
    vars.overworld_palette_aux2_bp5to7_hi.* = 3;
    load_gfx.Palette_Load_OWBG2();
    load_gfx.Overworld_CopyPalettesToCache();
    Overworld_LoadOverlays2();
    vars.BG1VOFS_copy2.* = 0;
    vars.BG1HOFS_copy2.* = 0;
    vars.submodule_index.* -%= 1;
}

pub export fn Credits_LoadScene_Dungeon() callconv(.c) void {
    load_gfx.EnableForceBlank();
    load_gfx.EraseTileMaps_normal();
    wordPtr(vars.which_entrance).* = tables.kEnding_Tab1[vars.submodule_index.* >> 1];

    Dungeon_LoadEntrance();
    vars.dung_num_lit_torches.* = 0;
    vars.hdr_dungeon_dark_with_lantern.* = 0;
    Dungeon_LoadAndDrawRoom();
    load_gfx.DecompressAnimatedDungeonTiles(kDungAnimatedTiles[vars.main_tile_theme_index.*]);

    const i: usize = vars.submodule_index.* >> 1;
    vars.sprite_graphics_index.* = tables.kEnding_SpritePack[i];
    const dpi = GetDungPalInfo(tables.kEnding_SpritePal[i] & 0x3f);
    vars.palette_sp5l.* = dpi.pal2;
    vars.palette_sp6l.* = dpi.pal3;
    vars.misc_sprites_graphics_index.* = 10;
    load_gfx.InitializeTilesets();
    vars.palette_sp6r_indoors.* = 10;
    load_gfx.Dungeon_LoadPalettes();
    vars.BGMODE_copy.* = 9;
    vars.R16.* = 0;
    vars.INIDISP_copy.* = 0;
    vars.submodule_index.* +%= 1;
    Credits_PrepAndLoadSprites();
}

pub export fn Module18_GanonEmerges() callconv(.c) void {
    const hofs2 = vars.BG2HOFS_copy2.*;
    const vofs2 = vars.BG2VOFS_copy2.*;
    const hofs1 = vars.BG1HOFS_copy2.*;
    const vofs1 = vars.BG1VOFS_copy2.*;

    vars.BG2HOFS_copy.* = hofs2 +% vars.bg1_x_offset.*;
    vars.BG2HOFS_copy2.* = vars.BG2HOFS_copy.*;
    vars.BG2VOFS_copy.* = vofs2 +% vars.bg1_y_offset.*;
    vars.BG2VOFS_copy2.* = vars.BG2VOFS_copy.*;
    vars.BG1HOFS_copy.* = hofs1 +% vars.bg1_x_offset.*;
    vars.BG1HOFS_copy2.* = vars.BG1HOFS_copy.*;
    vars.BG1VOFS_copy.* = vofs1 +% vars.bg1_y_offset.*;
    vars.BG1VOFS_copy2.* = vars.BG1VOFS_copy.*;
    Sprite_Main();
    vars.BG1VOFS_copy2.* = vofs1;
    vars.BG1HOFS_copy2.* = hofs1;
    vars.BG2VOFS_copy2.* = vofs2;
    vars.BG2HOFS_copy2.* = hofs2;

    switch (vars.overworld_map_state.*) {
        0 => { // GetBirdForPursuit
            Dungeon_HandleLayerEffect();
            CallForDuckIndoors();
            SaveDungeonKeys();
            vars.overworld_map_state.* +%= 1;
            vars.flag_is_link_immobilized.* +%= 1;
        },
        1 => { // PrepForPyramidLocation
            Dungeon_HandleLayerEffect();
            if (vars.submodule_index.* == 10) {
                vars.overworld_screen_index.* = 91;
                vars.player_is_indoors.* = 0;
                vars.main_module_index.* = 24;
                vars.submodule_index.* = 0;
                vars.overworld_map_state.* = 2;
            }
        },
        2 => { // FadeOutDungeonScreen
            Dungeon_HandleLayerEffect();
            vars.INIDISP_copy.* -%= 1;
            if (vars.INIDISP_copy.* != 0) return;
            load_gfx.EnableForceBlank();
            vars.overworld_map_state.* +%= 1;
            hud.Hud_RebuildIndoor();
            vars.link_y_vel.* = 0;
            vars.link_x_vel.* = 0;
        },
        3 => { // LoadPyramidArea
            vars.birdtravel_var1[0] = 8;
            vars.birdtravel_var1[1] = 0;
            FluteMenu_LoadSelectedScreen();
            LoadOWMusicIfNeeded();
            vars.music_control.* = 9;
        },
        4 => { // LoadAmbientOverlay
            Overworld_LoadOverlayAndMap();
            vars.subsubmodule_index.* = 0;
        },
        5 => { // BrightenScreenThenSpawnBat
            vars.INIDISP_copy.* +%= 1;
            if (vars.INIDISP_copy.* == 15) {
                vars.dung_savegame_state_bits.* = 0;
                vars.flag_unk1.* = 0;
                Sprite_SpawnBatCrashCutscene();
                vars.link_direction_facing.* = 2;
                vars.saved_module_for_menu.* = 9;
                vars.player_is_indoors.* = 0;
                vars.overworld_map_state.* +%= 1;
                vars.subsubmodule_index.* = 128;
                loPtr(vars.cur_palace_index_x2).* = 255;
            }
        },
        6 => {}, // DelayForBatSmashIntoPyramid
        7 => { // DelayPlayerDropOff
            vars.subsubmodule_index.* -%= 1;
            if (vars.subsubmodule_index.* == 0)
                vars.overworld_map_state.* +%= 1;
        },
        8 => BirdTravel_Finish_Doit(), // DropOffPlayerAtPyramid
        else => {},
    }

    player_oam.LinkOam_Main();
}

pub export fn Module19_TriforceRoom() callconv(.c) void {
    switch (vars.subsubmodule_index.*) {
        0 => {
            Link_ResetProperties_A();
            vars.link_last_direction_moved_towards.* = 0;
            vars.music_control.* = 0xf1;
            ResetTransitionPropsAndAdvance_ResetInterface();
        },
        1 => {
            ConditionalMosaicControl();
            load_gfx.ApplyPaletteFilter_bounce();
        },
        2 => {
            load_gfx.EnableForceBlank();
            misc.LoadCreditsSongs();
            vars.dungeon_room_index.* = 0x189;
            load_gfx.EraseTileMaps_normal();
            load_gfx.Palette_RevertTranslucencySwap();
            Overworld_EnterSpecialArea();
            Overworld_LoadOverlays2();
            vars.subsubmodule_index.* +%= 1;
            vars.main_module_index.* = 25;
            vars.submodule_index.* = 0;
        },
        3 => {
            vars.main_tile_theme_index.* = 36;
            vars.sprite_graphics_index.* = 125;
            vars.aux_tile_theme_index.* = 81;
            load_gfx.InitializeTilesets();
            load_gfx.Overworld_LoadAreaPalettesEx(4);
            load_gfx.Overworld_LoadPalettes(14, 0);
            load_gfx.SpecialOverworld_CopyPalettesToCache();
            vars.subsubmodule_index.* +%= 1;
        },
        4 => {
            const bak0 = vars.subsubmodule_index.*;
            Module08_02_LoadAndAdvance();
            vars.subsubmodule_index.* = bak0 +% 1;
            vars.INIDISP_copy.* = 15;
            vars.palette_filter_countdown.* = 31;
            vars.mosaic_target_level.* = 0;
            hiPtr(vars.BG1HOFS_copy2).* = 1;
            vars.CGWSEL_copy.* = 2;
            vars.CGADSUB_copy.* = 50;
            vars.mosaic_level.* = 240;
            loPtr(vars.link_y_coord).* = 236;
            loPtr(vars.link_x_coord).* = 120;
            vars.link_is_on_lower_level.* = 2;
            vars.music_control.* = 32;
            vars.main_module_index.* = 25;
            vars.submodule_index.* = 0;
        },
        5 => {
            vars.link_direction.* = 8;
            vars.link_direction_last.* = 8;
            vars.link_direction_facing.* = 0;
            if (loPtr(vars.link_y_coord).* < 192) {
                vars.link_direction.* = 0;
                vars.link_direction_last.* = 0;
                vars.link_animation_steps.* = 0;
                vars.subsubmodule_index.* +%= 1;
            }
        },
        6 => {
            if (vars.palette_filter_countdown.* & 1 == 0 and vars.mosaic_level.* != 0)
                vars.mosaic_level.* -%= 0x10;
            vars.BGMODE_copy.* = 9;
            vars.MOSAIC_copy.* = vars.mosaic_level.* | 7;
            load_gfx.ApplyPaletteFilter_bounce();
        },
        7 => {
            TriforceRoom_PrepGFXSlotForPoly();
            vars.dialogue_message_index.* = 0x173;
            misc.Main_ShowTextMessage();
            RenderText();
            loPtr(vars.R16).* = 0x80;
            vars.main_module_index.* = 25;
            vars.subsubmodule_index.* +%= 1;
        },
        8, 10 => {
            AdvancePolyhedral();
            if (vars.subsubmodule_index.* == 11) {
                vars.music_control.* = 33;
                vars.main_module_index.* = 25;
                vars.link_direction.* = 0;
                vars.link_direction_last.* = 0;
                vars.submodule_index.* +%= 1;
            }
        },
        9 => {
            AdvancePolyhedral();
            RenderText();
            if (vars.submodule_index.* == 0) {
                vars.overworld_map_state.* = 0;
                vars.main_module_index.* = 25;
                vars.subsubmodule_index.* +%= 1;
            }
        },
        11 => {
            AdvancePolyhedral();
            misc.TriforceRoom_LinkApproachTriforce();
            if (vars.subsubmodule_index.* == 12) {
                vars.link_direction.* = 0;
                vars.link_direction_last.* = 0;
            }
        },
        12 => {
            AdvancePolyhedral();
            loPtr(vars.R16).* -%= 1;
            if (loPtr(vars.R16).* == 0) {
                Palette_AnimGetMasterSword2();
                vars.submodule_index.* +%= 1;
            }
        },
        13 => {
            AdvancePolyhedral();
            load_gfx.PaletteFilter_BlindingWhiteTriforce();
            if (loPtr(vars.darkening_or_lightening_screen).* == 255)
                vars.subsubmodule_index.* +%= 1;
        },
        14 => {
            vars.INIDISP_copy.* -%= 1;
            if (vars.INIDISP_copy.* == 0) {
                vars.main_module_index.* = 26;
                vars.submodule_index.* = 0;
                vars.subsubmodule_index.* = 0;
                vars.irq_flag.* = 255;
                vars.is_nmi_thread_active.* = 0;
                vars.nmi_flag_update_polyhedral.* = 0;
                vars.savegame_is_darkworld.* = 0;
            }
        },
        else => {},
    }
    vars.BG1HOFS_copy.* = vars.BG1HOFS_copy2.*;
    vars.BG1VOFS_copy.* = vars.BG1VOFS_copy2.*;
    vars.BG2HOFS_copy.* = vars.BG2HOFS_copy2.*;
    vars.BG2VOFS_copy.* = vars.BG2VOFS_copy2.*;
    if (vars.subsubmodule_index.* < 7 or vars.subsubmodule_index.* >= 11) {
        Link_HandleVelocity();
        Link_HandleMovingAnimation_FullLongEntry();
    }
    player_oam.LinkOam_Main();
}

pub export fn Intro_InitializeBackgroundSettings() callconv(.c) void {
    vars.BGMODE_copy.* = 9;
    vars.MOSAIC_copy.* = 0;
    rtl.zelda_ppu_write(BG1SC, 0x13);
    rtl.zelda_ppu_write(BG2SC, 3);
    rtl.zelda_ppu_write(BG3SC, 0x63);
    vars.CGADSUB_copy.* = 32;
    vars.COLDATA_copy0.* = 32;
    vars.COLDATA_copy1.* = 64;
    vars.COLDATA_copy2.* = 128;
}

pub export fn Polyhedral_InitializeThread() callconv(.c) void {
    @memset(g_ram[kPolyThreadRam .. kPolyThreadRam + 256], 0);
    vars.thread_other_stack.* = 0x1f31;
    @memcpy(g_ram[0x1f32 .. 0x1f32 + 13], &tables.kPolyThreadInit);
}

pub export fn Module00_Intro() callconv(.c) void {
    const skip_at: u8 = if (features.enhanced_features0.* & features.kFeatures0_SkipIntroOnKeypress != 0) 4 else 8;

    if (vars.submodule_index.* >= skip_at and
        ((vars.filtered_joypad_L.* & 0xc0 | vars.filtered_joypad_H.*) & 0xd0) != 0)
    {
        FadeMusicAndResetSRAMMirror();
        return;
    }
    switch (vars.submodule_index.*) {
        0 => Intro_Init(),
        1 => Intro_Init_Continue(),
        10, 2 => Intro_InitializeTriforcePolyThread(),
        3, 4, 9, 11 => Intro_HandleAllTriforceAnimations(),
        5 => IntroZeldaFadein(),
        6 => Intro_SwordComingDown(),
        7 => Intro_FadeInBg(),
        8 => Intro_WaitPlayer(),
        else => {},
    }
}

pub export fn Intro_Init() callconv(.c) void {
    Intro_SetupScreen();
    vars.INIDISP_copy.* = 15;
    vars.subsubmodule_index.* = 0;
    vars.flag_update_cgram_in_nmi.* +%= 1;
    vars.submodule_index.* +%= 1;
    vars.sound_effect_2.* = 10;
    Intro_Init_Continue();
}

pub export fn Intro_Init_Continue() callconv(.c) void {
    Intro_DisplayLogo();
    const t = vars.subsubmodule_index.*;
    vars.subsubmodule_index.* = t +% 1;
    if (t >= 11) {
        vars.INIDISP_copy.* -%= 1;
        if (vars.INIDISP_copy.* != 0) return;
        Intro_InitializeMemory_darken();
        return;
    }
    switch (t) {
        0, 1, 2, 3, 4, 5, 6, 7 => Intro_Clear1kbBlocksOfWRAM(),
        8 => Intro_LoadTextPointersAndPalettes(),
        9 => load_gfx.LoadItemGFXIntoWRAM4BPPBuffer(),
        10 => load_gfx.LoadFollowerGraphics(),
        else => {},
    }
}

pub export fn Intro_Clear1kbBlocksOfWRAM() callconv(.c) void {
    var i = vars.R16.*;
    const dst = g_ram[0x2000..].ptr;
    while (true) {
        var j: usize = 0;
        while (j < 15) : (j += 1)
            std.mem.writeInt(u16, (dst + i + j * 0x2000)[0..2], 0, .little);
        i -%= 2;
        if (i == vars.R18.*) break;
    }
    vars.R16.* = i;
    vars.R18.* = i -% 0x400;
}

pub export fn Intro_InitializeMemory_darken() callconv(.c) void {
    load_gfx.EnableForceBlank();
    load_gfx.EraseTileMaps_normal();
    vars.main_tile_theme_index.* = 35;
    vars.sprite_graphics_index.* = 125;
    vars.aux_tile_theme_index.* = 81;
    vars.misc_sprites_graphics_index.* = 8;
    load_gfx.LoadDefaultGraphics();
    load_gfx.InitializeTilesets();
    load_gfx.DecompressAnimatedDungeonTiles(0x5d);
    vars.bg_tile_animation_countdown.* = 2;
    loPtr(vars.overworld_screen_index).* = 0;
    vars.palette_main_indoors.* = 0;
    vars.overworld_palette_aux3_bp7_lo.* = 0;
    vars.R16.* = 0;
    vars.R18.* = 0;
    vars.darkening_or_lightening_screen.* = 2;
    vars.palette_filter_countdown.* = 31;
    vars.mosaic_target_level.* = 0;
    vars.submodule_index.* +%= 1;
}

pub export fn IntroZeldaFadein() callconv(.c) void {
    Intro_HandleAllTriforceAnimations();
    if (vars.frame_counter.* & 1 == 0) return;
    load_gfx.Palette_FadeIntroOneStep();
    if (loPtr(vars.palette_filter_countdown).* == 0) {
        vars.subsubmodule_index.* = 42;
        vars.submodule_index.* +%= 1;
        Intro_SetupSwordAndIntroFlash();
    } else if (loPtr(vars.palette_filter_countdown).* == 13) {
        vars.TM_copy.* = 0x15;
        vars.TS_copy.* = 0;
    }
}

pub export fn Intro_FadeInBg() callconv(.c) void {
    Intro_PeriodicSwordAndIntroFlash();
    Intro_HandleAllTriforceAnimations();
    if (loPtr(vars.palette_filter_countdown).* != 0) {
        if (vars.frame_counter.* & 1 != 0)
            load_gfx.Palette_FadeIntro2();
    } else {
        if (((vars.filtered_joypad_L.* & 0xc0 | vars.filtered_joypad_H.*) & 0xd0) != 0) {
            FadeMusicAndResetSRAMMirror();
        } else {
            vars.subsubmodule_index.* -%= 1;
            if (vars.subsubmodule_index.* == 0)
                vars.submodule_index.* +%= 1;
        }
    }
}

pub export fn Intro_SwordComingDown() callconv(.c) void {
    Intro_HandleAllTriforceAnimations();
    vars.intro_did_run_step.* = 0;
    vars.is_nmi_thread_active.* = 0;
    Intro_PeriodicSwordAndIntroFlash();
    vars.subsubmodule_index.* -%= 1;
    if (vars.subsubmodule_index.* == 0) {
        vars.submodule_index.* +%= 1;
        vars.CGWSEL_copy.* = 2;
        vars.CGADSUB_copy.* = 0x22;
        vars.palette_filter_countdown.* = 31;
        vars.TS_copy.* = 2;
    }
}

pub export fn Intro_WaitPlayer() callconv(.c) void {
    Intro_HandleAllTriforceAnimations();
    vars.intro_did_run_step.* = 0;
    vars.is_nmi_thread_active.* = 0;
    Intro_PeriodicSwordAndIntroFlash();
    vars.subsubmodule_index.* -%= 1;
    if (vars.subsubmodule_index.* == 0) {
        vars.submodule_index.* +%= 1;
        vars.main_module_index.* = 20;
        vars.submodule_index.* = 0;
        loPtr(vars.link_x_coord).* = 0;
    }
}

pub export fn FadeMusicAndResetSRAMMirror() callconv(.c) void {
    vars.irq_flag.* = 255;
    vars.TM_copy.* = 0x15;
    vars.TS_copy.* = 0;
    vars.player_is_indoors.* = 0;
    vars.music_control.* = 0xf1;
    load_gfx.SetBackdropcolorBlack();

    // link_y_coord is the base of a 0x70-byte block of player state.
    @memset(g_ram[0x20 .. 0x20 + 0x70], 0);
    @memset(@as([*]u8, @ptrCast(vars.save_dung_info))[0 .. 256 * 5], 0);

    vars.main_module_index.* = 1;
    vars.death_var4.* = 1;
    vars.submodule_index.* = 0;
}

pub export fn Intro_InitializeTriforcePolyThread() callconv(.c) void {
    vars.misc_sprites_graphics_index.* = 8;
    load_gfx.LoadCommonSprites();
    Intro_InitGfx_Helper();
    vars.intro_sprite_isinited[0] = 1;
    vars.intro_sprite_isinited[1] = 1;
    vars.intro_sprite_isinited[2] = 1;
    vars.intro_sprite_subtype[0] = 0;
    vars.intro_sprite_subtype[1] = 0;
    vars.intro_sprite_subtype[2] = 0;
    vars.intro_sprite_isinited[4] = 1;
    vars.intro_sprite_subtype[4] = 2;
    vars.INIDISP_copy.* = 15;
    vars.submodule_index.* +%= 1;
}

pub export fn Intro_InitGfx_Helper() callconv(.c) void {
    Polyhedral_InitializeThread();
    LoadTriforceSpritePalette();
    vars.virq_trigger.* = 0x90;
    vars.poly_config1.* = 255;
    vars.poly_base_x.* = 32;
    vars.poly_base_y.* = 32;
    loPtr(vars.poly_var1).* = 32;
    vars.poly_a.* = 0xA0;
    vars.poly_b.* = 0x60;
    vars.poly_config_color_mode.* = 1;
    vars.poly_which_model.* = 1;
    vars.is_nmi_thread_active.* = 1;
    vars.intro_did_run_step.* = 1;
    // intro_step_index is the base of a 7 x 16 block of per-object state.
    @memset(g_ram[0x1e00 .. 0x1e00 + 7 * 16], 0);
}

pub export fn LoadTriforceSpritePalette() callconv(.c) void {
    @memcpy(vars.main_palette_buffer[0xd0 .. 0xd0 + 8], &tables.kPolyhedralPalette);
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Intro_HandleAllTriforceAnimations() callconv(.c) void {
    vars.intro_frame_ctr.* +%= 1;
    Intro_AnimateTriforce();
    Scene_AnimateEverySprite();
}

pub export fn Scene_AnimateEverySprite() callconv(.c) void {
    vars.intro_sprite_alloc.* = 0x800;
    var k: i32 = 7;
    while (k >= 0) : (k -= 1)
        Intro_AnimOneObj(k);
}

pub export fn Intro_AnimateTriforce() callconv(.c) void {
    vars.is_nmi_thread_active.* = 1;
    if (vars.intro_did_run_step.* == 0) {
        Intro_RunStep();
        vars.intro_did_run_step.* = 1;
    }
}

pub export fn Intro_RunStep() callconv(.c) void {
    switch (vars.intro_step_index.*) {
        0 => {
            vars.intro_step_timer.* +%= 1;
            if (vars.intro_step_timer.* == 64)
                vars.intro_step_index.* +%= 1;
            vars.poly_b.* +%= 5;
            vars.poly_a.* +%= 3;
        },
        1 => {
            if (vars.poly_config1.* < 2) {
                vars.poly_config1.* = 0;
                vars.intro_step_index.* +%= 1;
                vars.intro_step_timer.* = 64;
                return;
            }
            vars.poly_config1.* -%= 2;
            vars.poly_b.* +%= 5;
            vars.poly_a.* +%= 3;
            if (vars.poly_config1.* < 225)
                vars.submodule_index.* = 4;
            if (vars.poly_config1.* == 113)
                vars.music_control.* = 1;
        },
        2 => {
            vars.intro_step_timer.* -%= 1;
            if (vars.intro_step_timer.* == 0) {
                vars.intro_step_index.* +%= 1;
            } else {
                vars.poly_b.* +%= 5;
                vars.poly_a.* +%= 3;
            }
        },
        3 => {
            if (vars.poly_b.* >= 250 and vars.poly_a.* >= 252) {
                vars.intro_step_index.* +%= 1;
                vars.intro_step_timer.* = 32;
            } else {
                vars.poly_b.* +%= 5;
                vars.poly_a.* +%= 3;
            }
        },
        4 => {
            vars.poly_b.* = 0;
            vars.poly_a.* = 0;
            vars.intro_step_timer.* -%= 1;
            if (vars.intro_step_timer.* == 0) {
                vars.intro_step_index.* +%= 1;
                vars.intro_sprite_isinited[5] = 1;
                vars.intro_sprite_subtype[5] = 3;
                vars.TM_copy.* = 0x10;
                vars.TS_copy.* = 5;
                vars.CGWSEL_copy.* = 2;
                vars.CGADSUB_copy.* = 0x31;
                vars.subsubmodule_index.* = 0;
                vars.flag_update_cgram_in_nmi.* +%= 1;
                vars.nmi_load_bg_from_vram.* = 3;
                vars.submodule_index.* +%= 1;
            }
        },
        else => {},
    }
}

pub export fn Intro_AnimOneObj(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    switch (vars.intro_sprite_isinited[ki]) {
        0 => {},
        1 => switch (vars.intro_sprite_subtype[ki]) {
            0 => Intro_SpriteType_A_0(k),
            1 => EXIT_0CCA90(k),
            2 => InitializeSceneSprite_Copyright(k),
            3 => InitializeSceneSprite_Sparkle(k),
            4, 5, 6 => InitializeSceneSprite_TriforceRoomTriangle(k),
            7 => InitializeSceneSprite_CreditsTriangle(k),
            else => {},
        },
        2 => switch (vars.intro_sprite_subtype[ki]) {
            0 => Intro_SpriteType_B_0(k),
            1 => EXIT_0CCA90(k),
            2 => AnimateSceneSprite_Copyright(k),
            3 => AnimateSceneSprite_Sparkle(k),
            4, 5, 6 => Intro_SpriteType_B_456(k),
            7 => AnimateSceneSprite_CreditsTriangle(k),
            else => {},
        },
        else => {},
    }
}

pub export fn Intro_SpriteType_A_0(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.intro_x_lo[ki] = @truncate(@as(u16, @bitCast(tables.kIntroSprite0_X[ki])));
    vars.intro_x_hi[ki] = @truncate(@as(u16, @bitCast(tables.kIntroSprite0_X[ki] >> 8)));
    vars.intro_y_lo[ki] = @truncate(@as(u16, @bitCast(tables.kIntroSprite0_Y[ki])));
    vars.intro_y_hi[ki] = @truncate(@as(u16, @bitCast(tables.kIntroSprite0_Y[ki] >> 8)));
    vars.intro_x_vel[ki] = @bitCast(tables.kIntroSprite0_Xvel[ki]);
    vars.intro_y_vel[ki] = @bitCast(tables.kIntroSprite0_Yvel[ki]);
    vars.intro_sprite_isinited[ki] +%= 1;
}

pub export fn Intro_SpriteType_B_0(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    AnimateSceneSprite_DrawTriangle(k);
    AnimateSceneSprite_MoveTriangle(k);
    if (vars.intro_step_index.* != 5) {
        if (vars.intro_frame_ctr.* & 31 == 0) {
            vars.intro_x_vel[ki] +%= @bitCast(tables.kIntroSprite0_Xvel[ki]);
            vars.intro_y_vel[ki] +%= @bitCast(tables.kIntroSprite0_Yvel[ki]);
        }
        if (vars.intro_x_lo[ki] == tables.kIntroSprite0_XLimit[ki])
            vars.intro_x_vel[ki] = 0;
        if (vars.intro_y_lo[ki] == tables.kIntroSprite0_YLimit[ki])
            vars.intro_y_vel[ki] = 0;
    } else {
        vars.intro_x_vel[ki] = 0;
        vars.intro_y_vel[ki] = 0;
    }
}

pub export fn AnimateSceneSprite_DrawTriangle(k: c_int) callconv(.c) void {
    const kIntroSprite0_Left_Ents = [16]IntroSpriteEnt{
        .{ .x = 0, .y = 0, .charnum = 0x80, .flags = 0x1b, .ext = 2 },
        .{ .x = 16, .y = 0, .charnum = 0x82, .flags = 0x1b, .ext = 2 },
        .{ .x = 32, .y = 0, .charnum = 0x84, .flags = 0x1b, .ext = 2 },
        .{ .x = 48, .y = 0, .charnum = 0x86, .flags = 0x1b, .ext = 2 },
        .{ .x = 0, .y = 16, .charnum = 0xa0, .flags = 0x1b, .ext = 2 },
        .{ .x = 16, .y = 16, .charnum = 0xa2, .flags = 0x1b, .ext = 2 },
        .{ .x = 32, .y = 16, .charnum = 0xa4, .flags = 0x1b, .ext = 2 },
        .{ .x = 48, .y = 16, .charnum = 0xa6, .flags = 0x1b, .ext = 2 },
        .{ .x = 0, .y = 32, .charnum = 0x88, .flags = 0x1b, .ext = 2 },
        .{ .x = 16, .y = 32, .charnum = 0x8a, .flags = 0x1b, .ext = 2 },
        .{ .x = 32, .y = 32, .charnum = 0x8c, .flags = 0x1b, .ext = 2 },
        .{ .x = 48, .y = 32, .charnum = 0x8e, .flags = 0x1b, .ext = 2 },
        .{ .x = 0, .y = 48, .charnum = 0xa8, .flags = 0x1b, .ext = 2 },
        .{ .x = 16, .y = 48, .charnum = 0xaa, .flags = 0x1b, .ext = 2 },
        .{ .x = 32, .y = 48, .charnum = 0xac, .flags = 0x1b, .ext = 2 },
        .{ .x = 48, .y = 48, .charnum = 0xae, .flags = 0x1b, .ext = 2 },
    };
    const kIntroSprite0_Right_Ents = [16]IntroSpriteEnt{
        .{ .x = 48, .y = 0, .charnum = 0x80, .flags = 0x5b, .ext = 2 },
        .{ .x = 32, .y = 0, .charnum = 0x82, .flags = 0x5b, .ext = 2 },
        .{ .x = 16, .y = 0, .charnum = 0x84, .flags = 0x5b, .ext = 2 },
        .{ .x = 0, .y = 0, .charnum = 0x86, .flags = 0x5b, .ext = 2 },
        .{ .x = 48, .y = 16, .charnum = 0xa0, .flags = 0x5b, .ext = 2 },
        .{ .x = 32, .y = 16, .charnum = 0xa2, .flags = 0x5b, .ext = 2 },
        .{ .x = 16, .y = 16, .charnum = 0xa4, .flags = 0x5b, .ext = 2 },
        .{ .x = 0, .y = 16, .charnum = 0xa6, .flags = 0x5b, .ext = 2 },
        .{ .x = 48, .y = 32, .charnum = 0x88, .flags = 0x5b, .ext = 2 },
        .{ .x = 32, .y = 32, .charnum = 0x8a, .flags = 0x5b, .ext = 2 },
        .{ .x = 16, .y = 32, .charnum = 0x8c, .flags = 0x5b, .ext = 2 },
        .{ .x = 0, .y = 32, .charnum = 0x8e, .flags = 0x5b, .ext = 2 },
        .{ .x = 48, .y = 48, .charnum = 0xa8, .flags = 0x5b, .ext = 2 },
        .{ .x = 32, .y = 48, .charnum = 0xaa, .flags = 0x5b, .ext = 2 },
        .{ .x = 16, .y = 48, .charnum = 0xac, .flags = 0x5b, .ext = 2 },
        .{ .x = 0, .y = 48, .charnum = 0xae, .flags = 0x5b, .ext = 2 },
    };
    const src = if (k == 2) &kIntroSprite0_Right_Ents else &kIntroSprite0_Left_Ents;
    AnimateSceneSprite_AddObjectsToOamBuffer(k, src, 16);
}

pub export fn Intro_CopySpriteType4ToOam(k: c_int) callconv(.c) void {
    const kIntroTriforceOam_Left = [16]IntroSpriteEnt{
        .{ .x = 0, .y = 0, .charnum = 0x80, .flags = 0x2b, .ext = 2 },
        .{ .x = 16, .y = 0, .charnum = 0x82, .flags = 0x2b, .ext = 2 },
        .{ .x = 32, .y = 0, .charnum = 0x84, .flags = 0x2b, .ext = 2 },
        .{ .x = 48, .y = 0, .charnum = 0x86, .flags = 0x2b, .ext = 2 },
        .{ .x = 0, .y = 16, .charnum = 0xa0, .flags = 0x2b, .ext = 2 },
        .{ .x = 16, .y = 16, .charnum = 0xa2, .flags = 0x2b, .ext = 2 },
        .{ .x = 32, .y = 16, .charnum = 0xa4, .flags = 0x2b, .ext = 2 },
        .{ .x = 48, .y = 16, .charnum = 0xa6, .flags = 0x2b, .ext = 2 },
        .{ .x = 0, .y = 32, .charnum = 0x88, .flags = 0x2b, .ext = 2 },
        .{ .x = 16, .y = 32, .charnum = 0x8a, .flags = 0x2b, .ext = 2 },
        .{ .x = 32, .y = 32, .charnum = 0x8c, .flags = 0x2b, .ext = 2 },
        .{ .x = 48, .y = 32, .charnum = 0x8e, .flags = 0x2b, .ext = 2 },
        .{ .x = 0, .y = 48, .charnum = 0xa8, .flags = 0x2b, .ext = 2 },
        .{ .x = 16, .y = 48, .charnum = 0xaa, .flags = 0x2b, .ext = 2 },
        .{ .x = 32, .y = 48, .charnum = 0xac, .flags = 0x2b, .ext = 2 },
        .{ .x = 48, .y = 48, .charnum = 0xae, .flags = 0x2b, .ext = 2 },
    };
    const kIntroTriforceOam_Right = [16]IntroSpriteEnt{
        .{ .x = 48, .y = 0, .charnum = 0x80, .flags = 0x6b, .ext = 2 },
        .{ .x = 32, .y = 0, .charnum = 0x82, .flags = 0x6b, .ext = 2 },
        .{ .x = 16, .y = 0, .charnum = 0x84, .flags = 0x6b, .ext = 2 },
        .{ .x = 0, .y = 0, .charnum = 0x86, .flags = 0x6b, .ext = 2 },
        .{ .x = 48, .y = 16, .charnum = 0xa0, .flags = 0x6b, .ext = 2 },
        .{ .x = 32, .y = 16, .charnum = 0xa2, .flags = 0x6b, .ext = 2 },
        .{ .x = 16, .y = 16, .charnum = 0xa4, .flags = 0x6b, .ext = 2 },
        .{ .x = 0, .y = 16, .charnum = 0xa6, .flags = 0x6b, .ext = 2 },
        .{ .x = 48, .y = 32, .charnum = 0x88, .flags = 0x6b, .ext = 2 },
        .{ .x = 32, .y = 32, .charnum = 0x8a, .flags = 0x6b, .ext = 2 },
        .{ .x = 16, .y = 32, .charnum = 0x8c, .flags = 0x6b, .ext = 2 },
        .{ .x = 0, .y = 32, .charnum = 0x8e, .flags = 0x6b, .ext = 2 },
        .{ .x = 48, .y = 48, .charnum = 0xa8, .flags = 0x6b, .ext = 2 },
        .{ .x = 32, .y = 48, .charnum = 0xaa, .flags = 0x6b, .ext = 2 },
        .{ .x = 16, .y = 48, .charnum = 0xac, .flags = 0x6b, .ext = 2 },
        .{ .x = 0, .y = 48, .charnum = 0xae, .flags = 0x6b, .ext = 2 },
    };
    const src = if (k == 2) &kIntroTriforceOam_Right else &kIntroTriforceOam_Left;
    AnimateSceneSprite_AddObjectsToOamBuffer(k, src, 16);
}

pub export fn EXIT_0CCA90(k: c_int) callconv(.c) void {
    _ = k; // empty
}

pub export fn InitializeSceneSprite_Copyright(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.intro_x_lo[ki] = 76;
    vars.intro_x_hi[ki] = 0;
    vars.intro_y_lo[ki] = 184;
    vars.intro_y_hi[ki] = 0;
    vars.intro_sprite_isinited[ki] +%= 1;
}

pub export fn AnimateSceneSprite_Copyright(k: c_int) callconv(.c) void {
    const kIntroSprite2_Ents = [13]IntroSpriteEnt{
        .{ .x = 0, .y = 0, .charnum = 0x40, .flags = 0x0a, .ext = 0 },
        .{ .x = 8, .y = 0, .charnum = 0x41, .flags = 0x0a, .ext = 0 },
        .{ .x = 16, .y = 0, .charnum = 0x42, .flags = 0x0a, .ext = 0 },
        .{ .x = 24, .y = 0, .charnum = 0x68, .flags = 0x0a, .ext = 0 },
        .{ .x = 32, .y = 0, .charnum = 0x41, .flags = 0x0a, .ext = 0 },
        .{ .x = 40, .y = 0, .charnum = 0x42, .flags = 0x0a, .ext = 0 },
        .{ .x = 48, .y = 0, .charnum = 0x43, .flags = 0x0a, .ext = 0 },
        .{ .x = 56, .y = 0, .charnum = 0x44, .flags = 0x0a, .ext = 0 },
        .{ .x = 64, .y = 0, .charnum = 0x50, .flags = 0x0a, .ext = 0 },
        .{ .x = 72, .y = 0, .charnum = 0x51, .flags = 0x0a, .ext = 0 },
        .{ .x = 80, .y = 0, .charnum = 0x52, .flags = 0x0a, .ext = 0 },
        .{ .x = 88, .y = 0, .charnum = 0x53, .flags = 0x0a, .ext = 0 },
        .{ .x = 96, .y = 0, .charnum = 0x54, .flags = 0x0a, .ext = 0 },
    };
    AnimateSceneSprite_AddObjectsToOamBuffer(k, &kIntroSprite2_Ents, 13);
}

pub export fn InitializeSceneSprite_Sparkle(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const j = vars.intro_frame_ctr.* >> 5 & 3;
    vars.intro_x_lo[ki] = tables.kIntroSprite3_X[j];
    vars.intro_x_hi[ki] = 0;
    vars.intro_y_lo[ki] = tables.kIntroSprite3_Y[j];
    vars.intro_y_hi[ki] = 0;
    vars.intro_sprite_isinited[ki] +%= 1;
}

pub export fn AnimateSceneSprite_Sparkle(k: c_int) callconv(.c) void {
    const kIntroSprite3_Ents = [4]IntroSpriteEnt{
        .{ .x = 0, .y = 0, .charnum = 0x80, .flags = 0x34, .ext = 0 },
        .{ .x = 0, .y = 0, .charnum = 0xb7, .flags = 0x34, .ext = 0 },
        .{ .x = -4, .y = -3, .charnum = 0x64, .flags = 0x38, .ext = 2 },
        .{ .x = -4, .y = -3, .charnum = 0x62, .flags = 0x34, .ext = 2 },
    };
    const ki: usize = @intCast(k);
    if (vars.intro_sprite_state[ki] < 4)
        AnimateSceneSprite_AddObjectsToOamBuffer(k, kIntroSprite3_Ents[vars.intro_sprite_state[ki]..].ptr, 1);

    vars.intro_sprite_state[ki] = tables.kIntroSprite3_State[vars.intro_frame_ctr.* >> 2 & 7];
    const j = vars.intro_frame_ctr.* >> 5 & 3;
    vars.intro_x_lo[ki] = tables.kIntroSprite3_X[j];
    vars.intro_y_lo[ki] = tables.kIntroSprite3_Y[j];
}

pub export fn AnimateSceneSprite_AddObjectsToOamBuffer(k: c_int, src_in: [*]const IntroSpriteEnt, num_in: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const x = @as(u16, vars.intro_x_hi[ki]) << 8 | vars.intro_x_lo[ki];
    const y = @as(u16, vars.intro_y_hi[ki]) << 8 | vars.intro_y_lo[ki];
    var oam: [*]align(1) OamEnt = @ptrCast(&g_ram[vars.intro_sprite_alloc.*]);
    vars.intro_sprite_alloc.* +%= @intCast(num_in * 4);
    var src = src_in;
    var num = num_in;
    while (true) {
        const dx: u16 = @bitCast(@as(i16, src[0].x));
        const dy: u16 = @bitCast(@as(i16, src[0].y));
        SetOamHelper0(oam, x +% dx, y +% dy, src[0].charnum, src[0].flags, src[0].ext);
        oam += 1;
        src += 1;
        num -= 1;
        if (num == 0) break;
    }
}

pub export fn AnimateSceneSprite_MoveTriangle(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.intro_x_vel[ki] != 0) {
        const vel: u32 = @bitCast(@as(i32, @as(i8, @bitCast(vars.intro_x_vel[ki]))) << 4);
        const t = @as(u32, vars.intro_x_subpixel[ki]) +%
            (@as(u32, vars.intro_x_lo[ki]) << 8) +%
            (@as(u32, vars.intro_x_hi[ki]) << 16) +% vel;
        vars.intro_x_subpixel[ki] = @truncate(t);
        vars.intro_x_lo[ki] = @truncate(t >> 8);
        vars.intro_x_hi[ki] = @truncate(t >> 16);
    }
    if (vars.intro_y_vel[ki] != 0) {
        const vel: u32 = @bitCast(@as(i32, @as(i8, @bitCast(vars.intro_y_vel[ki]))) << 4);
        const t = @as(u32, vars.intro_y_subpixel[ki]) +%
            (@as(u32, vars.intro_y_lo[ki]) << 8) +%
            (@as(u32, vars.intro_y_hi[ki]) << 16) +% vel;
        vars.intro_y_subpixel[ki] = @truncate(t);
        vars.intro_y_lo[ki] = @truncate(t >> 8);
        vars.intro_y_hi[ki] = @truncate(t >> 16);
    }
}

pub export fn TriforceRoom_PrepGFXSlotForPoly() callconv(.c) void {
    vars.misc_sprites_graphics_index.* = 8;
    load_gfx.LoadCommonSprites();
    Intro_InitGfx_Helper();
    vars.intro_sprite_isinited[0] = 1;
    vars.intro_sprite_isinited[1] = 1;
    vars.intro_sprite_isinited[2] = 1;
    vars.intro_sprite_subtype[0] = 4;
    vars.intro_sprite_subtype[1] = 5;
    vars.intro_sprite_subtype[2] = 6;
    vars.INIDISP_copy.* = 15;
    vars.submodule_index.* +%= 1;
}

pub export fn Credits_InitializePolyhedral() callconv(.c) void {
    vars.misc_sprites_graphics_index.* = 8;
    load_gfx.LoadCommonSprites();
    Intro_InitGfx_Helper();
    vars.poly_config1.* = 0;
    vars.intro_sprite_isinited[0] = 1;
    vars.intro_sprite_isinited[1] = 1;
    vars.intro_sprite_isinited[2] = 1;
    vars.intro_sprite_subtype[0] = 7;
    vars.intro_sprite_subtype[1] = 7;
    vars.intro_sprite_subtype[2] = 7;
    vars.INIDISP_copy.* = 15;
    vars.submodule_index.* +%= 1;
}

pub export fn AdvancePolyhedral() callconv(.c) void {
    TriforceRoom_HandlePoly();
    Scene_AnimateEverySprite();
}

pub export fn TriforceRoom_HandlePoly() callconv(.c) void {
    vars.is_nmi_thread_active.* = 1;
    vars.intro_want_double_ret.* = 1;
    if (vars.intro_did_run_step.* != 0) return;

    const step = vars.intro_step_index.*;
    switch (step) {
        // The C lets case 0 fall through into case 1.
        0, 1 => {
            if (step == 0) {
                vars.poly_config1.* -%= 2;
                if (vars.poly_config1.* < 2) {
                    vars.poly_config1.* = 0;
                    vars.intro_step_index.* +%= 1;
                    vars.subsubmodule_index.* +%= 1;
                }
            }
            if (vars.subsubmodule_index.* >= 10) {
                vars.intro_step_index.* +%= 1;
                vars.intro_y_vel[1] = 5;
            }
            vars.poly_b.* +%= 2;
            vars.poly_a.* +%= 1;
        },
        2 => {
            vars.triforce_ctr.* = 0x1c0;
            var done = false;
            if (vars.poly_config1.* < 128) {
                vars.poly_config1.* +%= 1;
            } else {
                if ((vars.poly_b.* -% 10 & 0x7f) >= 92 and (vars.poly_a.* -% 11) >= 220) {
                    vars.poly_a.* = 0;
                    vars.poly_b.* = 0;
                    vars.subsubmodule_index.* +%= 1;
                    vars.intro_step_index.* +%= 1;
                    vars.sound_effect_1.* = 44;
                    vars.main_palette_buffer[0xd7] = 0x7fff;
                    vars.flag_update_cgram_in_nmi.* +%= 1;
                    vars.intro_step_timer.* = 6;
                    done = true;
                }
            }
            if (!done) {
                vars.poly_b.* +%= 5;
                vars.poly_a.* +%= 3;
            }
        },
        3 => {
            vars.intro_step_timer.* -%= 1;
            if (vars.intro_step_timer.* == 0) {
                vars.main_palette_buffer[0xd7] = tables.kPolyhedralPalette[7];
                vars.flag_update_cgram_in_nmi.* +%= 1;
                vars.intro_step_index.* +%= 1;
            }
        },
        4 => {},
        else => {},
    }
    vars.intro_did_run_step.* = 1;
    vars.intro_want_double_ret.* = 0;
    vars.intro_frame_ctr.* +%= 1;
}

pub export fn Credits_AnimateTheTriangles() callconv(.c) void {
    vars.intro_frame_ctr.* +%= 1;
    vars.is_nmi_thread_active.* = 1;
    if (vars.intro_did_run_step.* == 0) {
        vars.poly_b.* +%= 3;
        vars.poly_a.* +%= 1;
        vars.intro_did_run_step.* = 1;
    }
    Scene_AnimateEverySprite();
}

pub export fn InitializeSceneSprite_TriforceRoomTriangle(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.intro_x_lo[ki] = @truncate(@as(u16, @bitCast(tables.kIntroTriforce_X[ki])));
    vars.intro_x_hi[ki] = 0;
    vars.intro_y_lo[ki] = @truncate(@as(u16, @bitCast(tables.kIntroTriforce_Y[ki])));
    vars.intro_y_hi[ki] = 0;
    vars.intro_x_vel[ki] = @bitCast(tables.kIntroTriforce_Xvel[ki]);
    vars.intro_y_vel[ki] = @bitCast(tables.kIntroTriforce_Yvel[ki]);
    vars.intro_sprite_isinited[ki] +%= 1;
}

pub export fn Intro_SpriteType_B_456(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    Intro_CopySpriteType4ToOam(k);
    if (vars.intro_want_double_ret.* != 0) return;
    AnimateSceneSprite_MoveTriangle(k);
    switch (vars.intro_step_index.*) {
        0 => {
            if (vars.intro_frame_ctr.* & 7 == 0)
                vars.intro_x_vel[ki] +%= @bitCast(tables.kTriforce_Xacc[ki]);
            if (vars.intro_frame_ctr.* & 3 == 0)
                vars.intro_y_vel[ki] +%= @bitCast(tables.kTriforce_Yacc[ki]);
        },
        1 => {
            vars.intro_x_vel[ki] = 0;
            vars.intro_y_vel[ki] = 0;
        },
        2 => {
            if (vars.intro_frame_ctr.* & 3 == 0)
                AnimateTriforceRoomTriangle_HandleContracting(k);
            if (tables.kTriforce_Xfinal[ki] == vars.intro_x_lo[ki])
                vars.intro_x_vel[ki] = 0;
            if (tables.kTriforce_Yfinal[ki] == vars.intro_y_lo[ki])
                vars.intro_y_vel[ki] = 0;
        },
        3, 4 => {
            if (vars.triforce_ctr.* == 0) {
                vars.intro_y_lo[ki] = tables.kTriforce_Yfinal2[ki];
            } else {
                vars.triforce_ctr.* -%= 1;
            }
        },
        else => {},
    }
}

pub export fn AnimateTriforceRoomTriangle_HandleContracting(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var new_vel = vars.intro_x_vel[ki] +%
        (if (vars.intro_x_lo[ki] <= tables.kTriforce_Xfinal[ki]) @as(u8, 1) else @as(u8, 0xff));
    vars.intro_x_vel[ki] = if (new_vel == 0x11) 0x10 else if (new_vel == 0xef) 0xf0 else new_vel;
    new_vel = vars.intro_y_vel[ki] +%
        (if (vars.intro_y_lo[ki] <= tables.kTriforce_Yfinal[ki]) @as(u8, 1) else @as(u8, 0xff));
    vars.intro_y_vel[ki] = if (new_vel == 0x11) 0x10 else if (new_vel == 0xef) 0xf0 else new_vel;
}

pub export fn InitializeSceneSprite_CreditsTriangle(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.intro_x_lo[ki] = tables.kIntroSprite7_X[ki];
    vars.intro_x_hi[ki] = 0;
    vars.intro_y_lo[ki] = tables.kIntroSprite7_Y[ki];
    vars.intro_y_hi[ki] = 0;
    vars.intro_sprite_isinited[ki] +%= 1;
}

pub export fn AnimateSceneSprite_CreditsTriangle(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    LoadTriforceSpritePalette();
    Intro_CopySpriteType4ToOam(k);
    AnimateSceneSprite_MoveTriangle(k);
    if (vars.submodule_index.* != 36) {
        vars.intro_sprite_state[ki] = 0;
        return;
    }
    if (vars.intro_sprite_state[ki] != 80) {
        vars.intro_sprite_state[ki] +%= 1;
        vars.intro_x_vel[ki] +%= @bitCast(tables.kIntroSprite7_XAcc[ki]);
        vars.intro_y_vel[ki] +%= @bitCast(tables.kIntroSprite7_YAcc[ki]);
    }
}

pub export fn Intro_DisplayLogo() callconv(.c) void {
    var i: usize = 0;
    while (i < 4) : (i += 1)
        SetOamPlain(oam_buf + i, tables.kIntroLogo_X[i], 0x68, tables.kIntroLogo_Tile[i], 0x32, 2);
}

pub export fn Intro_SetupSwordAndIntroFlash() callconv(.c) void {
    intro_sword_19.* = 7;
    intro_sword_20.* = 0;
    intro_sword_21.* = 0;
    intro_sword_ypos.* = @bitCast(@as(i16, -130));

    Intro_PeriodicSwordAndIntroFlash();
}

pub export fn Intro_PeriodicSwordAndIntroFlash() callconv(.c) void {
    if (intro_sword_18.* != 0)
        intro_sword_18.* -%= 1;
    load_gfx.SetBackdropcolorBlack();
    if (vars.intro_times_pal_flash.* != 0) {
        if (vars.intro_times_pal_flash.* & 3 != 0) {
            const bits: u8 = if (features.enhanced_features0.* & features.kFeatures0_DimFlashes != 0) 0x05 else 0x1f;
            coldata_copies[intro_sword_24.*] |= bits;
            intro_sword_24.* = if (intro_sword_24.* == 2) 0 else intro_sword_24.* +% 1;
        }
        vars.intro_times_pal_flash.* -%= 1;
    }

    const oam = oam_buf + 0x52;
    var j: i32 = 9;
    while (j >= 0) : (j -= 1) {
        const ji: usize = @intCast(j);
        const y = intro_sword_ypos.* +% tables.kIntroSword_Y[ji];
        const yb: u8 = if (y & 0xff00 != 0) 0xf8 else @truncate(y);
        SetOamPlain(oam + ji, tables.kIntroSword_X[ji], yb -% 8, tables.kIntroSword_Char[ji], 0x21, 2);
    }

    if (intro_sword_ypos.* != 30) {
        if (intro_sword_ypos.* == 0xffbe) {
            vars.sound_effect_1.* = 1;
        } else if (intro_sword_ypos.* == 14) {
            wordPtr(intro_sword_24).* = 0;
            vars.intro_times_pal_flash.* = 0x20;
            vars.sound_effect_1.* = 0x2c;
        }
        intro_sword_ypos.* +%= 16;
    }

    switch (intro_sword_20.* >> 1) {
        0 => {
            if (vars.intro_times_pal_flash.* == 0 and intro_sword_ypos.* == 30)
                intro_sword_20.* +%= 2;
        },
        1 => {
            if (intro_sword_18.* == 0) {
                intro_sword_19.* -%= 1;
                if (sign8(intro_sword_19.*)) {
                    intro_sword_19.* = 0;
                    intro_sword_18.* = 2;
                    intro_sword_20.* +%= 2;
                    return;
                }
                intro_sword_18.* = tables.kSwordSparkle_Tab[intro_sword_19.*];
            }
            const kSwordSparkle_Char = tables.kSwordSparkle_Char;
            SetOamPlain(oam_buf + 0x50, 0x44, 0x43, kSwordSparkle_Char[intro_sword_19.*], 0x25, 0);
        },
        2 => {
            const k = intro_sword_19.*;
            if (k >= 7) return;
            const base: u8 = if (intro_sword_21.* < 0x50) intro_sword_21.* else 0x4f;
            const y: u8 = base +% @as(u8, @truncate(intro_sword_ypos.*)) +% 0x31;
            SetOamPlain(oam_buf + 0x50, 0x42, y +% 0, tables.kIntroSwordSparkle_Char[k + 0], 0x23, 0);
            SetOamPlain(oam_buf + 0x51, 0x42, y +% 8, tables.kIntroSwordSparkle_Char[k + 1], 0x23, 0);
            if (intro_sword_18.* == 0) {
                intro_sword_21.* +%= 4;
                const t = intro_sword_21.*;
                if (t == 0x4 or t == 0x48 or t == 0x4c or t == 0x58)
                    intro_sword_19.* +%= 2;
            }
        },
        else => {},
    }
}

pub export fn Module1A_Credits() callconv(.c) void {
    vars.oam_region_base[0] = 0x30;
    vars.oam_region_base[1] = 0x1d0;
    vars.oam_region_base[2] = 0x0;

    kEndSequence_Funcs[vars.submodule_index.*]();
}

pub export fn Credits_LoadNextScene_Overworld() callconv(.c) void {
    kEndSequence0_Funcs[vars.subsubmodule_index.*]();
    Credits_AddEndingSequenceText();
}

pub export fn Credits_LoadNextScene_Dungeon() callconv(.c) void {
    Credits_LoadScene_Dungeon();
    Credits_AddEndingSequenceText();
}

/// The body the C reaches through `goto init_sprites_0`.
fn creditsInitSpritesOverworld(scene: usize) void {
    const idx = tables.kEndingSprites_Idx[scene];
    const num: i32 = @as(i32, tables.kEndingSprites_Idx[scene + 1]) - idx;
    const px = tables.kEndingSprites_X[idx..];
    const py = tables.kEndingSprites_Y[idx..];
    var k: i32 = num - 1;
    while (k >= 0) : (k -= 1) {
        const ki: usize = @intCast(k);
        vars.sprcoll_x_size.* = 0xffff;
        vars.sprcoll_y_size.* = 0xffff;
        const x = (swap16(vars.overworld_area_index.* << 1) & 0xf00) +% px[ki];
        const y = (swap16(vars.overworld_area_index.* >> 2) & 0xe00) +% py[ki];
        Sprite_SetX(k, x);
        Sprite_SetY(k, y);
    }
}

/// The body the C reaches through `goto init_sprites_1`.
fn creditsInitSpritesDungeon(scene: usize) void {
    const idx = tables.kEndingSprites_Idx[scene];
    const num: i32 = @as(i32, tables.kEndingSprites_Idx[scene + 1]) - idx;
    const px = tables.kEndingSprites_X[idx..];
    const py = tables.kEndingSprites_Y[idx..];
    vars.byte_7E0FB1.* = @truncate(vars.dungeon_room_index2.* >> 3 & 254);
    vars.byte_7E0FB0.* = @truncate((vars.dungeon_room_index2.* & 15) << 1);
    var k: i32 = num - 1;
    while (k >= 0) : (k -= 1) {
        const ki: usize = @intCast(k);
        vars.sprcoll_x_size.* = 0xffff;
        vars.sprcoll_y_size.* = 0xffff;
        const x = @as(u16, vars.byte_7E0FB0.*) *% 256 +% px[ki];
        const y = @as(u16, vars.byte_7E0FB1.*) *% 256 +% py[ki];
        Sprite_SetX(k, x);
        Sprite_SetY(k, y);
    }
}

pub export fn Credits_PrepAndLoadSprites() callconv(.c) void {
    var k: i32 = 15;
    while (k >= 0) : (k -= 1) {
        const ki: usize = @intCast(k);
        SpritePrep_ResetProperties(k);
        vars.sprite_state[ki] = 0;
        vars.sprite_flags5[ki] = 0;
        vars.sprite_defl_bits[ki] = 0;
    }
    const scene: usize = vars.submodule_index.* >> 1;
    switch (scene) {
        0, 4, 5, 8, 13 => creditsInitSpritesOverworld(scene),
        1 => creditsInitSpritesDungeon(scene),
        2 => {
            vars.sprite_y_vel[6] = @bitCast(@as(i8, -16));
            creditsInitSpritesOverworld(scene);
        },
        3 => {
            vars.sprite_A[5] = 22;
            vars.sprite_y_vel[0] = @bitCast(@as(i8, -16));
            vars.sprite_y_vel[1] = 16;
            vars.sprite_head_dir[1] = 1;
            var j: i32 = 2;
            while (j >= 0) : (j -= 1) {
                const ji: usize = @intCast(j);
                vars.sprite_type[2 + ji] = 0x57;
                vars.sprite_oam_flags[2 + ji] = 0x31;
            }
            creditsInitSpritesOverworld(scene);
        },
        6 => {
            vars.sprite_delay_main[0] = 255;
            vars.sprite_delay_main[1] = 255;
            vars.sprite_delay_main[2] = 255;
            creditsInitSpritesOverworld(scene);
        },
        7 => {
            vars.sprite_delay_main[1] = 255;
            creditsInitSpritesOverworld(scene);
        },
        9 => {
            var j: i32 = 4;
            while (j >= 0) : (j -= 1) {
                const ji: usize = @intCast(j);
                vars.sprite_delay_main[ji] = @truncate(ji * 19);
                vars.sprite_state[ji] = 0;
            }
            vars.sprite_type[5] = 0x2e;
            j = 1;
            while (j >= 0) : (j -= 1) {
                const ji: usize = @intCast(j);
                vars.sprite_type[7 + ji] = 0x9f;
                vars.sprite_type[9 + ji] = 0xa0;
                vars.sprite_flags2[7 + ji] = 1;
                vars.sprite_flags2[9 + ji] = 2;
                vars.sprite_flags3[7 + ji] = 0x10;
                vars.sprite_flags3[9 + ji] = 0x10;
            }
            creditsInitSpritesOverworld(scene);
        },
        10 => {
            vars.sprite_delay_main[1] = 0x10;
            vars.sprite_delay_main[2] = 0x20;
            vars.sprite_oam_flags[3] = 8;
            vars.sprite_oam_flags[4] = 8;
            creditsInitSpritesDungeon(scene);
        },
        11 => {
            vars.sprite_oam_flags[4] = 0x79;
            vars.sprite_oam_flags[5] = 0x39;
            vars.sprite_D[1] = 1;
            vars.sprite_A[1] = 4;
            creditsInitSpritesDungeon(scene);
        },
        12 => {
            var j: i32 = 1;
            while (j >= 0) : (j -= 1) {
                const ji: usize = @intCast(j);
                vars.sprite_oam_flags[ji + 3] = 0x39;
                vars.sprite_type[ji + 3] = 0xb;
                vars.sprite_flags3[ji + 3] = 0x10;
                vars.sprite_flags2[ji + 3] = 1;
            }
            vars.sprite_type[5] = 0x2a;
            vars.sprite_type[6] = 0x79;
            vars.sprite_ai_state[6] = 1;
            vars.sprite_z[6] = 5;
            creditsInitSpritesOverworld(scene);
        },
        14 => {
            vars.sprite_y_vel[5] = @bitCast(@as(i8, -16));
            vars.sprite_y_vel[6] = 16;
            vars.sprite_head_dir[6] = 1;
            vars.sprite_A[0] = 8;
            var j: i32 = 3;
            while (j >= 0) : (j -= 1)
                vars.sprite_y_vel[1 + @as(usize, @intCast(j))] = 4;
            creditsInitSpritesOverworld(scene);
        },
        15 => {
            vars.sprite_C[4] = 2;
            vars.sprite_y_vel[5] = 8;
            vars.sprite_delay_main[1] = 0x13;
            vars.sprite_delay_main[4] = 0x40;
            creditsInitSpritesOverworld(scene);
        },
        else => {},
    }
}

pub export fn Credits_ScrollScene_Overworld() callconv(.c) void {
    var k: i32 = 15;
    while (k >= 0) : (k -= 1) {
        const ki: usize = @intCast(k);
        if (vars.sprite_delay_main[ki] != 0)
            vars.sprite_delay_main[ki] -%= 1;
    }

    const i: usize = vars.submodule_index.* >> 1;

    vars.link_x_vel.* = 0;
    vars.link_y_vel.* = 0;
    if (vars.R16.* >= 0x40 and vars.R16.* & 1 == 0) {
        if (vars.BG2VOFS_copy2.* != tables.kEnding1_TargetScrollY[i])
            vars.link_y_vel.* = @bitCast(tables.kEnding1_Yvel[i]);
        if (vars.BG2HOFS_copy2.* != tables.kEnding1_TargetScrollX[i])
            vars.link_x_vel.* = @bitCast(tables.kEnding1_Xvel[i]);
    }

    Credits_OperateScrollingAndTileMap();
    Credits_HandleSceneFade();
}

pub export fn Credits_ScrollScene_Dungeon() callconv(.c) void {
    var k: i32 = 15;
    while (k >= 0) : (k -= 1) {
        const ki: usize = @intCast(k);
        if (vars.sprite_delay_main[ki] != 0)
            vars.sprite_delay_main[ki] -%= 1;
    }

    const i: usize = vars.submodule_index.* >> 1;
    if (vars.R16.* >= 0x40 and vars.R16.* & 1 == 0) {
        if (vars.BG2VOFS_copy2.* != tables.kEnding1_TargetScrollY[i])
            vars.BG2VOFS_copy2.* +%= @bitCast(@as(i16, tables.kEnding1_Yvel[i]));
        if (vars.BG2HOFS_copy2.* != tables.kEnding1_TargetScrollX[i])
            vars.BG2HOFS_copy2.* +%= @bitCast(@as(i16, tables.kEnding1_Xvel[i]));
    }
    Credits_HandleSceneFade();
}

pub export fn Credits_HandleSceneFade() callconv(.c) void {
    const i: usize = vars.submodule_index.* >> 1;
    var j: i32 = 0;
    var k: i32 = 0;

    switch (i) {
        0 => {
            var m: usize = 11;
            while (m != 7) : (m -= 1) {
                vars.sprite_oam_flags[m] = tables.kEndSequence_Case0_OamFlags[m];
                Credits_SpriteDraw_Single(@intCast(m), tables.kEndSequence_Case0_Tab0[m], tables.kEndSequence_Case0_Tab1[m]);
            }
            while (m != 1) : (m -= 1) {
                vars.sprite_oam_flags[m] = tables.kEndSequence_Case0_OamFlags[m] |
                    (vars.frame_counter.* << 2 & 0x40);
                Credits_SpriteDraw_Single(@intCast(m), tables.kEndSequence_Case0_Tab0[m], tables.kEndSequence_Case0_Tab1[m]);
            }
            var n: i32 = 1;
            while (n >= 0) : (n -= 1) {
                const ni: usize = @intCast(n);
                vars.sprite_oam_flags[ni] = tables.kEndSequence_Case0_OamFlags[ni];
                Credits_SpriteDraw_Single(n, tables.kEndSequence_Case0_Tab0[ni], tables.kEndSequence_Case0_Tab1[ni]);
            }
        },
        1 => {
            Credits_SpriteDraw_Single(0, 3, 12);
            Credits_SpriteDraw_DrawShadow(0);
            k = 1;
            vars.sprite_type[1] = 0x73;
            vars.sprite_oam_flags[1] = 0x27;
            vars.sprite_E[1] = 2;
            Credits_SpriteDraw_PreexistingSpriteDraw(k, 16);
        },
        2 => {
            loPtr(vars.flag_travel_bird).* = tables.kEnding_Case2_Tab0[vars.frame_counter.* >> 2 & 1];
            k = 6;
            var ki: usize = 6;
            j = @intCast(vars.sprite_x_vel[ki] >> 7 & 1);
            vars.sprite_oam_flags[ki] = (vars.sprite_x_vel[ki] +%
                @as(u8, @bitCast(tables.kEnding_Case2_Tab1[@intCast(j)]))) >> 1 & 0x40 | 0x32;
            Credits_SpriteDraw_Single(k, 2, 0x24);
            Credits_SpriteDraw_CirclingBirds(k);
            k -= 1;
            ki = 5;
            vars.sprite_oam_flags[ki] = 0x31;
            if (vars.sprite_delay_main[ki] == 0) {
                j = vars.sprite_A[ki];
                vars.sprite_A[ki] ^= 1;
                vars.sprite_delay_main[ki] = tables.kEnding_Case2_Delay[@intCast(j)];
                vars.sprite_graphics[ki] = vars.sprite_graphics[ki] +% 1 & 3;
            }
            Credits_SpriteDraw_Single(k, 2, 0x26);
            k -= 1;
            while (true) {
                const kk: usize = @intCast(k);
                if (vars.frame_counter.* & 15 == 0)
                    vars.sprite_graphics[kk] ^= 1;
                vars.sprite_oam_flags[kk] = 0x31;
                Credits_SpriteDraw_Single(k, @bitCast(tables.kEnding_Case2_Tab3[kk]), @bitCast(tables.kEnding_Case2_Tab2[kk]));
                EndSequence_DrawShadow2(k);
                k -= 1;
                if (k < 0) break;
            }
        },
        3 => {
            k = 0;
            while (k < 5) : (k += 1) {
                const ki: usize = @intCast(k);
                if (k < 2) {
                    vars.sprite_type[ki] = 1;
                    vars.sprite_oam_flags[ki] = 0xb;
                    Credits_SpriteDraw_SetShadowProp(k, 2);
                    vars.sprite_z[ki] = 48;
                    const bias: u32 = if (k != 0) 0x5f else 0x7d;
                    j = @intCast((@as(u32, vars.frame_counter.*) + bias) >> 2 & 3);
                    vars.sprite_graphics[ki] = tables.kEnding_Case3_Gfx[@intCast(j)];
                    Credits_SpriteDraw_CirclingBirds(k);
                    Credits_SpriteDraw_PreexistingSpriteDraw(k, 12);
                } else {
                    Credits_SpriteDraw_PreexistingSpriteDraw(k, 16);
                }
            }
            Credits_SpriteDraw_Single(k, 2, 0x38);
            Ending_Func2(k, 0x30);
            k += 1;
            Credits_SpriteDraw_Single(k, 3, 0x3a);
        },
        4 => {
            k = 2;
            vars.sprite_oam_flags[2] = 0x35;
            Credits_SpriteDraw_Single(k, 1, 0x3c);
            k -= 1;
            while (true) {
                const ki: usize = @intCast(k);
                vars.sprite_oam_flags[ki] = (vars.sprite_x_vel[ki] -% 1) >> 1 & 0x40 ^ 0x71;
                vars.sprite_graphics[ki] = vars.frame_counter.* >> 3 & 1;
                if (vars.R16.* >= tables.kEnding_Case4_Ctr[ki] and vars.sprite_delay_main[ki] == 0) {
                    const a = tables.kEnding_Case4_DelayVel[vars.sprite_A[ki]];
                    vars.sprite_delay_main[ki] = a & 0xf8;
                    vars.sprite_y_vel[ki] = @bitCast(tables.kEnding_Case4_XYvel[(a & 7) + 2]);
                    vars.sprite_x_vel[ki] = @bitCast(tables.kEnding_Case4_XYvel[a & 7]);
                    vars.sprite_A[ki] +%= 1;
                }
                Credits_SpriteDraw_Single(k, tables.kEnding_Case4_Tab0[ki], tables.kEnding_Case4_Tab1[ki]);
                EndSequence_DrawShadow2(k);
                Sprite_MoveXY(k);
                k -= 1;
                if (k < 0) break;
            }
        },
        5 => {
            if (vars.R16.* == 0x200) {
                vars.sound_effect_1.* = 1;
            } else if (vars.R16.* == 0x208) {
                vars.sound_effect_1.* = 0x2c;
            }
            if (vars.R16.* -% 0x208 < 0x30)
                Credits_SpriteDraw_AddSparkle(2, 10, @truncate(vars.R16.* -% 0x208)); // wtf x,y
            k = 3;
            if (vars.R16.* >= 0x200)
                vars.sprite_graphics[3] = 1;
            vars.sprite_oam_flags[3] = 0x31;
            Credits_SpriteDraw_Single(k, 4, 8);
            EndSequence_DrawShadow2(k);
            const g = vars.sprite_graphics[3];
            k -= 1;
            vars.sprite_graphics[2] = g;
            vars.link_dma_var3.* = 0;
            vars.link_dma_var4.* = tables.kEnding_Case5_Tab0[g];
            vars.sprite_oam_flags[2] = 0x30;

            vars.link_dma_graphics_index.* = tables.kEnding_Case5_Tab1[g];
            Credits_SpriteDraw_Single(k, 5, tables.kEnding_Case5_Tab2[g]);
            EndSequence_DrawShadow2(k);
        },
        6 => {
            const idx = tables.kEndingSprites_Idx[i];
            const num: i32 = @as(i32, tables.kEndingSprites_Idx[i + 1]) - idx;
            var m: i32 = num - 1;
            while (m >= 0) : (m -= 1) {
                const mi: usize = @intCast(m);
                vars.cur_object_index.* = @intCast(mi);
                vars.sprite_type[mi] = tables.kEnding_Case6_SprType[mi];
                _ = Oam_AllocateFromRegionA(tables.kEnding_Case6_OamSize[mi]);
                vars.sprite_ai_state[mi] = tables.kEnding_Case6_State[mi];
                j = if (vars.R16.* >= 0x26f) m + 3 else m;
                if (vars.R16.* == 0x26f)
                    vars.sound_effect_2.* = 0x21;
                vars.sprite_graphics[mi] = tables.kEnding_Case6_Gfx[@intCast(j)];
                vars.sprite_oam_flags[mi] = 0x33;
                Sprite_Get16BitCoords(m);
                SpriteActive_Main(m);
            }
        },
        7 => {
            k = 1;
            Credits_SpriteDraw_SetShadowProp(k, 2);
            vars.sprite_type[1] = 0xe9;
            _ = Oam_AllocateFromRegionA(0xc);
            vars.sprite_oam_flags[1] = 0x37;
            Sprite_Get16BitCoords(k);
            if (vars.frame_counter.* & 15 == 0)
                vars.sprite_graphics[1] ^= 1;
            SpriteActive_Main(k);
            if (vars.R16.* >= 0x180) {
                vars.sprite_y_vel[1] = 4;
                if (vars.sprite_y_lo[1] != 0x7c)
                    Sprite_MoveXY(k);
            }
            k -= 1;
            vars.sprite_type[0] = 0x36;
            _ = Oam_AllocateFromRegionA(0x18);
            vars.sprite_oam_flags[0] = 0x39;
            Sprite_Get16BitCoords(k);
            if (vars.sprite_delay_main[0] == 0) {
                vars.sprite_delay_main[0] = 4;
                const gfx_delta: u8 = @bitCast(tables.kEnding_Case7_Gfx[vars.R16.* >> 9 & 1]);
                vars.sprite_graphics[0] = vars.sprite_graphics[0] +% gfx_delta & 7;
            }
            SpriteActive_Main(k);
        },
        8 => {
            k = 0;
            vars.sprite_type[0] = 0x2c;
            _ = Oam_AllocateFromRegionA(0x2c);
            vars.sprite_oam_flags[0] = 0x3b;
            Sprite_Get16BitCoords(k);
            vars.sprite_graphics[0] = if (vars.R16.* < 0x1c0) @truncate(vars.R16.* >> 5 & 1) else 2;
            SpriteActive_Main(k);
        },
        9 => {
            k = 0;
            while (k < 5) : (k += 1) {
                const ki: usize = @intCast(k);
                if (vars.sprite_delay_main[ki] == 0) {
                    vars.sprite_delay_main[ki] = 96;
                    vars.sprite_state[ki] = 96;
                    vars.sprite_x_vel[ki] = 0;
                    vars.sprite_x_lo[ki] = 238;
                    vars.sprite_x_hi[ki] = 4;
                    vars.sprite_y_lo[ki] = 24;
                    vars.sprite_y_hi[ki] = 11;
                }
                if (vars.sprite_state[ki] != 0) {
                    vars.sprite_y_vel[ki] = @bitCast(@as(i8, -8));
                    Sprite_MoveXY(k);
                    if (vars.frame_counter.* & 1 == 0) {
                        const neg = ((@as(i32, vars.frame_counter.* >> 5) ^ k) & 1) != 0;
                        vars.sprite_x_vel[ki] +%= if (neg) 0xff else 1;
                    }
                    Credits_SpriteDraw_Single(k, 1, 0x10);
                }
            }
            while (true) {
                const ki: usize = @intCast(k);
                if (vars.sprite_delay_main[ki] == 0) {
                    vars.sprite_delay_main[ki] = if (k == 5)
                        tables.kEnding_Case8_Delay1[vars.sprite_A[ki]]
                    else
                        tables.kEnding_Case8_Delay2[vars.sprite_A[ki]];
                    vars.sprite_A[ki] = vars.sprite_A[ki] +% 1 & 3;
                    vars.sprite_graphics[ki] ^= 1;
                }
                if (k == 5) {
                    vars.sprite_oam_flags[ki] = 0x31;
                    Credits_SpriteDraw_PreexistingSpriteDraw(k, 0x10);
                    k += 1;
                } else {
                    Credits_SpriteDraw_Single(k, 2, 0x12);
                    k += 1;
                    break;
                }
            }
            while (true) {
                const ki: usize = @intCast(k);
                const t: usize = @intCast(k - 7);
                vars.sprite_oam_flags[ki] = tables.kEnding_Case8_OamFlags[t];
                vars.sprite_D[ki] = tables.kEnding_Case8_D[t];
                Credits_SpriteDraw_ActivateAndRunSprite(k, tables.kEnding_Case8_Tab0[t]);
                k += 1;
                if (k == 11) break;
            }
        },
        10 => {
            k = 5;
            Sprite_Get16BitCoords(k);
            if (vars.sprite_pause[5] == 0) {
                const xb = tables.kWishPond_X[misc.GetRandomNumber() & 7] +% @as(u8, @truncate(vars.cur_sprite_x.*));
                const yb = tables.kWishPond_Y[misc.GetRandomNumber() & 7] +% @as(u8, @truncate(vars.cur_sprite_y.*));
                Credits_SpriteDraw_AddSparkle(3, xb, yb);
            }
            var m: i32 = 3;
            while (m < 5) : (m += 1) {
                const mi: usize = @intCast(m);
                if (vars.sprite_delay_aux1[mi] != 0)
                    vars.sprite_delay_aux1[mi] -%= 1;
                vars.sprite_type[mi] = 0xe3;
                Credits_SpriteDraw_SetShadowProp(m, 1);
                Credits_SpriteDraw_ActivateAndRunSprite(m, 8);
            }
            vars.sprite_type[5] = 0x72;
            vars.sprite_oam_flags[5] = 0x3b;
            vars.sprite_state[5] = 9;
            vars.sprite_B[5] = 9;
            Credits_SpriteDraw_PreexistingSpriteDraw(k, 0x30);
        },
        11 => {
            if (vars.R16.* >= 0x170) {
                var m: i32 = 4;
                while (m != 6) : (m += 1)
                    Credits_SpriteDraw_Single(m, 1, 0x3e);
                k = 0;
                vars.sprite_oam_flags[0] = 0x39;
                if (vars.R16.* < 0x1c0) {
                    vars.sprite_graphics[0] = 2;
                } else if (vars.sprite_delay_main[0] == 0) {
                    vars.sprite_delay_main[0] = 0x20;
                    vars.sprite_graphics[0] = (vars.sprite_graphics[0] ^ 1) & 1;
                }
                Credits_SpriteDraw_Single(k, 4, 6);
            } else {
                var m: i32 = 0;
                while (m < 2) : (m += 1) {
                    const mi: usize = @intCast(m);
                    vars.sprite_type[mi] = 0x1a;
                    vars.sprite_oam_flags[mi] = 0x39;
                    Credits_SpriteDraw_SetShadowProp(m, 2);
                    const bak0 = vars.main_module_index.*;
                    Credits_SpriteDraw_ActivateAndRunSprite(m, 0xc);
                    vars.main_module_index.* = bak0;
                    if (vars.sprite_B[mi] == 15 and vars.sprite_A[mi] == 4)
                        vars.sprite_delay_main[mi + 2] = 15;
                    const jj = vars.sprite_delay_main[mi + 2];
                    if (jj != 0) {
                        vars.sprite_oam_flags[mi + 2] = 2;
                        vars.sprite_graphics[mi + 2] = tables.kEnding_Case11_Gfx[jj];
                        Credits_SpriteDraw_Single(m + 2, 2, 0x36);
                    }
                }
            }
        },
        12 => {
            k = 6;
            vars.sprite_graphics[6] = vars.frame_counter.* & 1;
            if (vars.sprite_graphics[6] == 0) {
                vars.sprite_x_vel[6] +%= if (sign8(vars.sprite_x_lo[6] -% 0x80)) 1 else 0xff;
                vars.sprite_y_vel[6] +%= if (sign8(vars.sprite_y_lo[6] -% 0xb0)) 1 else 0xff;
                Sprite_MoveXY(k);
            }

            vars.sprite_oam_flags[6] = vars.sprite_x_vel[6] >> 1 & 0x40 ^ 0x7e;
            vars.sprite_flags2[6] = 1;
            vars.sprite_flags3[6] = 0x30;
            vars.sprite_z[6] = 16;
            Credits_SpriteDraw_PreexistingSpriteDraw(k, 8);
            k -= 1;
            vars.sprite_oam_flags[5] = 0x37;
            Credits_SpriteDraw_SetShadowProp(k, 2);
            Credits_SpriteDraw_ActivateAndRunSprite(k, 12);
            k -= 1;
            Credits_SpriteDraw_ActivateAndRunSprite(k, 8);
            k -= 1;
            Credits_SpriteDraw_ActivateAndRunSprite(k, 8);
            k -= 1;
            while (true) {
                const ki: usize = @intCast(k);
                Credits_SpriteDraw_Single(k, tables.kEnding_Case12_Tab[ki], @intCast(k * 2));
                if (k == 0) {
                    Ending_Func2(k, 0x30);
                } else if (k & ~@as(i32, 1) != 0) {
                    vars.sprite_graphics[ki] = vars.frame_counter.* >> 3 & 1;
                } else {
                    const jj = vars.frame_counter.* & 0x1f;
                    if (jj < 0xf)
                        vars.sprite_z[ki] = tables.kEnding_Case12_Z[jj];
                    vars.sprite_graphics[ki] = if (jj < 0xf) 1 else 0;
                    Credits_SpriteDraw_DrawShadow(k);
                }
                k -= 1;
                if (k < 0) break;
            }
        },
        13 => {
            k = 0;
            if (vars.R16.* == 0x200)
                vars.sprite_x_vel[0] = @bitCast(@as(i8, -4));
            vars.sprite_graphics[0] = vars.frame_counter.* >> 4 & 1;
            if (vars.sprite_x_lo[0] == 56) {
                vars.sprite_x_vel[0] = 0;
                vars.sprite_graphics[0] +%= 2;
            }
            Credits_SpriteDraw_Single(k, 3, 0x34);
            Sprite_MoveXY(k);
        },
        14 => {
            k = 6;
            while (k != 0) : (k -= 1) {
                const ki: usize = @intCast(k);
                if (k >= 5) {
                    vars.sprite_type[ki] = 0;
                    Credits_SpriteDraw_SetShadowProp(k, 1);
                    vars.sprite_graphics[ki] = (vars.frame_counter.* +% 0x4a & 8) >> 3;
                    vars.sprite_z[ki] = 32;
                    Credits_SpriteDraw_CirclingBirds(k);
                    vars.sprite_oam_flags[ki] = (vars.sprite_x_vel[ki] >> 1 & 0x40) ^ 0xf;
                    Credits_SpriteDraw_PreexistingSpriteDraw(k, 8);
                } else {
                    vars.sprite_type[ki] = 0xd;
                    if (k == 1)
                        vars.sprite_head_dir[ki] = 0xd;
                    Credits_SpriteDraw_SetShadowProp(k, 3);
                    vars.sprite_oam_flags[ki] = 0x2b;
                    var a = vars.sprite_delay_main[ki];
                    if (a == 0) {
                        a = 0xc0;
                        vars.sprite_delay_main[ki] = a;
                    }
                    a >>= 1;
                    if (a == 0) {
                        vars.sprite_x_vel[ki] = 0;
                        vars.sprite_y_vel[ki] = 0;
                    } else {
                        if (a < @as(u8, @bitCast(tables.kEnding_Case14_Tab0[ki])) and
                            vars.frame_counter.* & 3 == 0)
                        {
                            a = vars.sprite_y_vel[ki];
                            if (a != 0) {
                                a -%= 1;
                                vars.sprite_y_vel[ki] = a;
                                a -%= 4;
                                if (k < 3) a = 0 -% a;
                                vars.sprite_x_vel[ki] = a;
                            }
                        }
                    }
                    Sprite_MoveXY(k);
                    vars.sprite_graphics[ki] = @bitCast(tables.kEnding_Case14_Tab1[vars.frame_counter.* >> 3 & 3]);
                    Credits_SpriteDraw_PreexistingSpriteDraw(k, 16);
                }
            }
            Credits_SpriteDraw_Single(k, 3, 0x18);
            Ending_Func2(k, 0x20);
        },
        15 => {
            j = kGeneratedEndSequence15()[vars.frame_counter.*] & 3;
            Credits_SpriteDraw_AddSparkle(2, tables.kEnding_Case15_X[@intCast(j)], tables.kEnding_Case15_Y[@intCast(j)]);
            k = 2;
            vars.sprite_type[2] = 0x62;
            vars.sprite_oam_flags[2] = 0x39;
            Credits_SpriteDraw_PreexistingSpriteDraw(k, 0x18);
            j = 1;
            while (j >= 0) : (j -= 1) {
                k += 1;
                const ki: usize = @intCast(k);
                if (vars.sprite_delay_aux1[ki] != 0)
                    vars.sprite_delay_aux1[ki] -%= 1;
                vars.sprite_oam_flags[ki] = (vars.sprite_x_vel[ki] >> 1 & 0x40) ^
                    tables.kEnding_Case15_OamFlags[@intCast(j)];
                if (vars.sprite_delay_main[ki] == 0) {
                    vars.sprite_delay_main[ki] = 128;
                    vars.sprite_A[ki] = 0;
                }
                if (vars.sprite_A[ki] == 0) {
                    vars.sprite_graphics[ki] = (vars.frame_counter.* >> 2 & 1) +% 2;
                    Credits_SpriteDraw_MoveSquirrel(k);
                } else if (vars.sprite_delay_aux1[ki] == 0) {
                    if (vars.sprite_B[ki] == 8)
                        vars.sprite_B[ki] = 0;
                    vars.sprite_delay_aux1[ki] = tables.kEnding_Case15_Delay[vars.sprite_B[ki] & 7];
                    vars.sprite_graphics[ki] = vars.sprite_graphics[ki] & 1 ^ 1;
                    vars.sprite_B[ki] +%= 1;
                }
                Credits_SpriteDraw_Single(k, 1, 20);
                EndSequence_DrawShadow2(k);
            }
            Credits_SpriteDraw_WalkLinkAwayFromPedestal(k + 1);
        },
        else => {},
    }

    const scene: usize = vars.submodule_index.* >> 1;
    if (vars.R16.* >= tables.kEnding1_3_Tab0[scene]) {
        // INIDISP_copy is only stepped on even frames; the C's && short circuits.
        var advanced = false;
        if (vars.R16.* & 1 == 0) {
            vars.INIDISP_copy.* -%= 1;
            if (vars.INIDISP_copy.* == 0) {
                vars.submodule_index.* +%= 1;
                advanced = true;
            }
        }
        if (!advanced) vars.R16.* +%= 1;
    } else {
        if (vars.R16.* & 1 == 0 and vars.INIDISP_copy.* != 15)
            vars.INIDISP_copy.* +%= 1;
        vars.R16.* +%= 1;
    }
    vars.BG2HOFS_copy.* = vars.BG2HOFS_copy2.*;
    vars.BG2VOFS_copy.* = vars.BG2VOFS_copy2.*;
    vars.BG1HOFS_copy.* = vars.BG1HOFS_copy2.*;
    vars.BG1VOFS_copy.* = vars.BG1VOFS_copy2.*;
}

pub export fn Credits_SpriteDraw_DrawShadow(k: c_int) callconv(.c) void {
    vars.sprite_oam_flags[@intCast(k)] = 0x30;
    Credits_SpriteDraw_SetShadowProp(k, 0);
    _ = Oam_AllocateFromRegionA(4);
    SpriteDraw_Shadow(k, &g_ending_coords);
}

pub export fn EndSequence_DrawShadow2(k: c_int) callconv(.c) void {
    Credits_SpriteDraw_SetShadowProp(k, 0);
    _ = Oam_AllocateFromRegionA(4);
    SpriteDraw_Shadow(k, &g_ending_coords);
}

pub export fn Ending_Func2(k: c_int, ain: u8) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_oam_flags[ki] = ain;
    EndSequence_DrawShadow2(k);
    var j: u32 = vars.sprite_A[ki];
    if (vars.sprite_delay_main[ki] == 0) {
        j += 1;
        if (j == 8) {
            j = 6;
        } else if (j == 22) {
            j = 21;
        } else if (j == 28) {
            j = 27;
        }
        vars.sprite_A[ki] = @truncate(j);
        vars.sprite_delay_main[ki] = tables.kEnding_Func2_Delay[j - 1];
    }
    // The table is signed; its -1 entries read back as the 255 sentinel.
    const a: u8 = @bitCast(tables.kEnding_Func2_Tab0[j]);
    vars.sprite_graphics[ki] = if (a == 255) vars.frame_counter.* >> 3 & 1 else a;
    if ((j < 5 or (j >= 10 and j < 15)) and vars.frame_counter.* & 1 == 0)
        vars.sprite_y_lo[ki] +%= 1;
}

pub export fn Credits_SpriteDraw_ActivateAndRunSprite(k: c_int, a: u8) callconv(.c) void {
    vars.cur_object_index.* = @intCast(k);
    _ = Oam_AllocateFromRegionA(a);
    Sprite_Get16BitCoords(k);
    const bak0 = vars.submodule_index.*;
    vars.submodule_index.* = 0;
    vars.sprite_state[@intCast(k)] = 9;
    SpriteActive_Main(k);
    vars.submodule_index.* = bak0;
}

pub export fn Credits_SpriteDraw_PreexistingSpriteDraw(k: c_int, a: u8) callconv(.c) void {
    _ = Oam_AllocateFromRegionA(a);
    vars.cur_object_index.* = @intCast(k);
    Sprite_Get16BitCoords(k);
    SpriteActive_Main(k);
}

inline fn d(x: i8, y: i8, cf: u16, e: u8) DrawMultipleData {
    return .{ .x = x, .y = y, .char_flags = cf, .ext = e };
}

const kEndSequence_Dmd0 = [12]DrawMultipleData{
    d(0, -8, 0x072a, 2), d(0, -8, 0x072a, 2), d(0, 0, 0x4fca, 2), d(0, -8, 0x072a, 2),
    d(0, -8, 0x072a, 2), d(0, 0, 0x0fca, 2),  d(-2, 0, 0x0f77, 0), d(0, -8, 0x072a, 2),
    d(0, 0, 0x4fca, 2),  d(-3, 0, 0x0f66, 0), d(0, -8, 0x072a, 2), d(0, 0, 0x4fca, 2),
};
const kEndSequence_Dmd1 = [6]DrawMultipleData{
    d(14, -7, 0x0d48, 2),  d(0, -6, 0x0944, 2), d(0, 0, 0x094e, 2),
    d(13, -14, 0x0d48, 2), d(0, -8, 0x0944, 2), d(0, 0, 0x0946, 2),
};
const kEndSequence_Dmd2 = [16]DrawMultipleData{
    d(-2, -16, 0x3d78, 0), d(0, -24, 0x3d24, 2),  d(0, -16, 0x3dc2, 2),
    d(61, -16, 0x3777, 0), d(64, -24, 0x37c4, 2), d(64, -16, 0x77ca, 2),
    d(0, -6, 0x326c, 2),   d(64, -6, 0x326c, 2),  d(-2, -16, 0x3d68, 0),
    d(0, -24, 0x3d24, 2),  d(0, -16, 0x3dc2, 2),  d(61, -16, 0x3766, 0),
    d(64, -24, 0x37c4, 2), d(64, -16, 0x77ca, 2), d(0, -6, 0x326c, 2),
    d(64, -6, 0x326c, 2),
};
const kEndSequence_Dmd3 = [12]DrawMultipleData{
    d(0, 0, 0x0022, 2),  d(48, 0, 0x0064, 2),  d(0, 10, 0x016c, 2), d(48, 10, 0x016c, 2),
    d(0, 0, 0x0064, 2),  d(48, 0, 0x0022, 2),  d(0, 10, 0x016c, 2), d(48, 10, 0x016c, 2),
    d(0, 0, 0x0064, 2),  d(48, 0, 0x0064, 2),  d(0, 10, 0x016c, 2), d(48, 10, 0x016c, 2),
};
const kEndSequence_Dmd4 = [8]DrawMultipleData{
    d(10, 8, 0x8a32, 0),   d(10, 16, 0x8a22, 0), d(0, -10, 0x0800, 2), d(0, 0, 0x082c, 2),
    d(10, -14, 0x0a22, 0), d(10, -6, 0x0a32, 0), d(0, -10, 0x082a, 2), d(0, 0, 0x0828, 2),
};
const kEndSequence_Dmd5 = [10]DrawMultipleData{
    d(10, 16, 0x8a05, 0),  d(10, 8, 0x8a15, 0),   d(-4, 2, 0x0a07, 2), d(0, -7, 0x0e00, 2),
    d(0, 1, 0x0e02, 2),    d(10, -20, 0x0a05, 0), d(10, -12, 0x0a15, 0), d(-7, 1, 0x4a07, 2),
    d(0, -7, 0x0e00, 2),   d(0, 1, 0x0e02, 2),
};
const kEndSequence_Dmd6 = [3]DrawMultipleData{
    d(-6, -2, 0x0706, 2), d(0, -9, 0x090e, 2), d(0, -1, 0x0908, 2),
};
const kEndSequence_Dmd7 = [10]DrawMultipleData{
    d(0, -10, 0x082a, 2),  d(0, 0, 0x0828, 2),    d(10, 16, 0x8a05, 0), d(10, 8, 0x8a15, 0),
    d(-4, 2, 0x0a07, 2),   d(0, -7, 0x0e00, 2),   d(0, 1, 0x0e02, 2),   d(10, -20, 0x0a05, 0),
    d(10, -12, 0x0a15, 0), d(-7, 1, 0x4a07, 2),
};
const kEndSequence_Dmd8 = [1]DrawMultipleData{d(0, -19, 0x39af, 0)};
const kEndSequence_Dmd9 = [4]DrawMultipleData{
    d(-16, -24, 0x3704, 2), d(-16, -16, 0x3764, 2), d(-16, -24, 0x3762, 2), d(-16, -16, 0x3764, 2),
};
const kEndSequence_Dmd10 = [4]DrawMultipleData{
    d(0, 0, 0x0c0c, 2), d(0, 0, 0x0c0a, 2), d(0, 0, 0x0cc5, 2), d(0, 0, 0x0ce1, 2),
};
const kEndSequence_Dmd11 = [6]DrawMultipleData{
    d(1, 4, 0x002a, 0), d(1, 12, 0x003a, 0), d(4, 0, 0x0026, 2),
    d(0, 9, 0x0024, 2), d(8, 9, 0x4024, 2),  d(4, 20, 0x016c, 2),
};
const kEndSequence_Dmd12 = [21]DrawMultipleData{
    d(0, -7, 0x0d00, 2), d(0, -7, 0x0d00, 2), d(0, 0, 0x0d06, 2),
    d(0, -7, 0x0d00, 2), d(0, -7, 0x0d00, 2), d(0, 0, 0x4d06, 2),
    d(0, -8, 0x0d00, 2), d(0, -8, 0x0d00, 2), d(0, 0, 0x0d20, 2),
    d(0, -8, 0x0d02, 2), d(0, -8, 0x0d02, 2), d(0, 0, 0x0d2c, 2),
    d(-3, 0, 0x0d2f, 0), d(0, -7, 0x0d02, 2), d(0, 0, 0x0d2c, 2),
    d(-5, 2, 0x0d2f, 0), d(0, -8, 0x0d02, 2), d(0, 0, 0x0d2c, 2),
    d(-5, 2, 0x0d3f, 0), d(0, -8, 0x0d02, 2), d(0, 0, 0x0d2c, 2),
};
const kEndSequence_Dmd13 = [16]DrawMultipleData{
    d(0, -7, 0x0e00, 2), d(0, 1, 0x4e02, 2), d(0, -8, 0x0e00, 2), d(0, 1, 0x0e02, 2),
    d(0, -9, 0x0e00, 2), d(0, 1, 0x0e02, 2), d(0, -7, 0x0e00, 2), d(0, 1, 0x0e02, 2),
    d(0, -7, 0x0e00, 2), d(0, 1, 0x4e02, 2), d(0, -8, 0x0e00, 2), d(0, 1, 0x4e02, 2),
    d(0, -9, 0x0e00, 2), d(0, 1, 0x4e02, 2), d(0, -7, 0x0e00, 2), d(0, 1, 0x4e02, 2),
};
const kEndSequence_Dmd14 = [6]DrawMultipleData{
    d(0, 0, 0, 0),           d(0, 0, 0x34c7, 0), d(0, 0, 0x3480, 0),
    d(0, 0, 0x34b6, 0),      d(0, 0, 0x34b7, 0), d(0, 0, 0x34a6, 0),
};
const kEndSequence_Dmd15 = [6]DrawMultipleData{
    d(-3, 17, 0x002b, 0), d(-3, 25, 0x003b, 0), d(0, 0, 0x000e, 2),
    d(16, 0, 0x400e, 2),  d(0, 16, 0x002e, 2),  d(16, 16, 0x402e, 2),
};
const kEndSequence_Dmd16 = [3]DrawMultipleData{
    d(8, 5, 0x0a04, 2), d(0, 16, 0x0806, 2), d(16, 16, 0x4806, 2),
};
const kEndSequence_Dmd17 = [2]DrawMultipleData{ d(0, 0, 0x0000, 2), d(0, 11, 0x0002, 2) };
const kEndSequence_Dmd18 = [2]DrawMultipleData{ d(0, 0, 0x000e, 2), d(0, 64, 0x006c, 2) };
const kEndSequence_Dmd19 = [8]DrawMultipleData{
    d(0, 0, 0x0882, 2), d(0, 7, 0x0a4e, 2), d(0, 0, 0x4880, 2), d(0, 7, 0x0a4e, 2),
    d(0, 0, 0x0882, 2), d(0, 7, 0x0a4e, 2), d(0, 0, 0x0880, 2), d(0, 7, 0x0a4e, 2),
};
const kEndSequence_Dmd20 = [6]DrawMultipleData{
    d(-4, 1, 0x0c68, 0), d(0, -8, 0x0c40, 2), d(0, 1, 0x0c42, 2),
    d(-4, 1, 0x0c78, 0), d(0, -8, 0x0c40, 2), d(0, 1, 0x0c42, 2),
};
const kEndSequence_Dmd21 = [6]DrawMultipleData{
    d(8, 5, 0x0679, 0),   d(0, -10, 0x088e, 2), d(0, 0, 0x066e, 2),
    d(0, -10, 0x088e, 2), d(0, -10, 0x088e, 2), d(0, 0, 0x066e, 2),
};
const kEndSequence_Dmd22 = [6]DrawMultipleData{
    d(11, -3, 0x0869, 0), d(0, -12, 0x0804, 2), d(0, 0, 0x0860, 2),
    d(10, -3, 0x0867, 0), d(0, -12, 0x0804, 2), d(0, 0, 0x0860, 2),
};
const kEndSequence_Dmd23 = [6]DrawMultipleData{
    d(-2, 1, 0x0868, 0), d(0, -8, 0x08c0, 2), d(0, 0, 0x08c2, 2),
    d(-3, 1, 0x0878, 0), d(0, -8, 0x08c0, 2), d(0, 0, 0x08c2, 2),
};
const kEndSequence_Dmd24 = [4]DrawMultipleData{
    d(0, -10, 0x084c, 2), d(0, 0, 0x0a6c, 2), d(0, -9, 0x084c, 2), d(0, 0, 0x0aa8, 2),
};
const kEndSequence_Dmd25 = [4]DrawMultipleData{
    d(0, -7, 0x084a, 2), d(0, 0, 0x0c6a, 2), d(0, -7, 0x084a, 2), d(0, 0, 0x0ca6, 2),
};
const kEndSequence_Dmd26 = [12]DrawMultipleData{
    d(-18, -24, 0x39a4, 2), d(-16, -16, 0x39a8, 2), d(-18, -24, 0x39a4, 2),
    d(-18, -24, 0x39a4, 2), d(-16, -16, 0x39a6, 2), d(-18, -24, 0x39a4, 2),
    d(-6, -17, 0x392d, 0),  d(-16, -24, 0x39a0, 2), d(-16, -16, 0x39aa, 2),
    d(-5, -17, 0x392c, 0),  d(-16, -24, 0x39a0, 2), d(-16, -16, 0x39aa, 2),
};
const kEndSequence_Dmd27 = [6]DrawMultipleData{
    d(0, -4, 0x30aa, 2),  d(0, -4, 0x30aa, 2),   d(-4, -8, 0x3090, 0),
    d(12, -8, 0x7090, 0), d(-6, -10, 0x3091, 0), d(14, -10, 0x7091, 0),
};
const kEndSequence_Dmd28 = [8]DrawMultipleData{
    d(0, 0, 0x0722, 2),  d(0, -8, 0x09c2, 2), d(0, 0, 0x4722, 2), d(0, -8, 0x09c2, 2),
    d(0, -9, 0x09c4, 2), d(0, 0, 0x0722, 2),  d(0, -9, 0x0924, 2), d(0, 0, 0x0722, 2),
};
const kEndSequence_Dmd29 = [3]DrawMultipleData{
    d(-16, -12, 0x3f08, 2), d(0, -12, 0x3f20, 2), d(16, -12, 0x3f20, 2),
};
const kEndSequence_Dmd30 = [1]DrawMultipleData{d(0, 0, 0x0086, 2)};
const kEndSequence_Dmd31 = [1]DrawMultipleData{d(0, 0, 0x8060, 2)};

const kEndSequence_Dmds = [32][*]const DrawMultipleData{
    &kEndSequence_Dmd0,  &kEndSequence_Dmd1,  &kEndSequence_Dmd2,  &kEndSequence_Dmd3,
    &kEndSequence_Dmd4,  &kEndSequence_Dmd5,  &kEndSequence_Dmd6,  &kEndSequence_Dmd7,
    &kEndSequence_Dmd8,  &kEndSequence_Dmd9,  &kEndSequence_Dmd10, &kEndSequence_Dmd11,
    &kEndSequence_Dmd12, &kEndSequence_Dmd13, &kEndSequence_Dmd14, &kEndSequence_Dmd15,
    &kEndSequence_Dmd16, &kEndSequence_Dmd17, &kEndSequence_Dmd18, &kEndSequence_Dmd19,
    &kEndSequence_Dmd20, &kEndSequence_Dmd21, &kEndSequence_Dmd22, &kEndSequence_Dmd23,
    &kEndSequence_Dmd24, &kEndSequence_Dmd25, &kEndSequence_Dmd26, &kEndSequence_Dmd27,
    &kEndSequence_Dmd28, &kEndSequence_Dmd29, &kEndSequence_Dmd30, &kEndSequence_Dmd31,
};

pub export fn Credits_SpriteDraw_Single(k: c_int, a: u8, j: u8) callconv(.c) void {
    _ = Oam_AllocateFromRegionA(@truncate(@as(u16, a) * 4));
    Sprite_Get16BitCoords(k);
    const src = kEndSequence_Dmds[j >> 1] + @as(usize, a) * vars.sprite_graphics[@intCast(k)];
    Sprite_DrawMultiple(k, src, a, &g_ending_coords);
}

pub export fn Credits_SpriteDraw_SetShadowProp(k: c_int, a: u8) callconv(.c) void {
    vars.sprite_flags2[@intCast(k)] = a;
    vars.sprite_flags3[@intCast(k)] = 16;
}

pub export fn Credits_SpriteDraw_AddSparkle(j_count: c_int, xb: u8, yb: u8) callconv(.c) void {
    vars.sprite_C[0] = @intCast(j_count);
    var k: c_int = 0;
    while (k < j_count) : (k += 1) {
        const ki: usize = @intCast(k);
        var j: u32 = vars.sprite_graphics[ki];
        if (vars.sprite_delay_main[ki] == 0) {
            j += 1;
            if (j >= 6) {
                vars.sprite_x_lo[ki] = xb;
                vars.sprite_y_lo[ki] = yb;
                j = 0;
            }
            vars.sprite_graphics[ki] = @truncate(j);
            vars.sprite_delay_main[ki] = tables.kEnding_Func3_Delay[j];
        }
        if (j != 0)
            Credits_SpriteDraw_Single(k, 1, 0x1c);
    }
}

pub export fn Credits_SpriteDraw_WalkLinkAwayFromPedestal(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_delay_main[ki] == 0) {
        vars.sprite_graphics[ki] = vars.sprite_graphics[ki] +% 1 & 7;
        vars.sprite_delay_main[ki] = 4;
    }
    vars.link_dma_graphics_index.* = tables.kEnding_Func6_Dma[vars.sprite_graphics[ki]];
    vars.sprite_oam_flags[ki] = 32;
    Credits_SpriteDraw_Single(k, 2, 26);
    EndSequence_DrawShadow2(k);
    Sprite_MoveXY(k);
}

pub export fn Credits_SpriteDraw_MoveSquirrel(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_delay_main[ki] < 64) {
        vars.sprite_C[ki] = vars.sprite_C[ki] +% 1 & 3;
        vars.sprite_A[ki] +%= 1;
    } else {
        const j = vars.sprite_C[ki];
        vars.sprite_x_vel[ki] = @bitCast(tables.kEnding_Func5_Xvel[j]);
        vars.sprite_y_vel[ki] = @bitCast(tables.kEnding_Func5_Yvel[j]);
        Sprite_MoveXY(k);
    }
}

pub export fn Credits_SpriteDraw_CirclingBirds(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var j: usize = vars.sprite_D[ki] & 1;
    vars.sprite_x_vel[ki] +%= if (j != 0) 0xff else 1;
    if (vars.sprite_x_vel[ki] == @as(u8, @bitCast(tables.kEnding_MoveSprite_Func1_TargetX[j])))
        vars.sprite_D[ki] +%= 1;
    if (vars.frame_counter.* & 1 == 0) {
        j = vars.sprite_head_dir[ki] & 1;
        vars.sprite_y_vel[ki] +%= if (j != 0) 0xff else 1;
        if (vars.sprite_y_vel[ki] == @as(u8, @bitCast(tables.kEnding_MoveSprite_Func1_TargetY[j])))
            vars.sprite_head_dir[ki] +%= 1;
    }
    Sprite_MoveXY(k);
}

pub export fn Credits_HandleCameraScrollControl() callconv(.c) void {
    if (vars.link_y_vel.* != 0) {
        const yvel = vars.link_y_vel.*;
        vars.BG2VOFS_copy2.* +%= @bitCast(@as(i16, @as(i8, @bitCast(yvel))));
        const which = if (sign8(yvel)) vars.overworld_unk1 else vars.overworld_unk1_neg;
        which.* +%= abs8(yvel);
        if (!sign16(which.* -% 0x10)) {
            which.* -%= 0x10;
            loPtr(vars.overworld_screen_trans_dir_bits2).* |= if (sign8(yvel)) 8 else 4;
        }
        const other = if (sign8(yvel)) vars.overworld_unk1_neg else vars.overworld_unk1;
        other.* = 0 -% which.*;

        var r4: u16 = @bitCast(@as(i16, @as(i8, @bitCast(yvel))));
        var subp: u16 = undefined;
        std.mem.writeInt(u16, g_ram[0x69e..0x6a0], r4, .little);
        const oi = loPtr(vars.overlay_index).*;
        if (oi != 0x97 and oi != 0x9d) {
            if (oi == 0xb5 or oi == 0xbe) {
                subp = (r4 & 3) << 14;
                r4 >>= 2;
                if (r4 >= 0x3000) r4 |= 0xf000;
            } else {
                subp = (r4 & 1) << 15;
                r4 >>= 1;
                if (r4 >= 0x7000) r4 |= 0xf000;
            }
            var tmp = @as(u32, vars.BG1VOFS_subpixel.*) | @as(u32, vars.BG1VOFS_copy2.*) << 16;
            tmp +%= @as(u32, subp) | @as(u32, r4) << 16;
            vars.BG1VOFS_subpixel.* = @truncate(tmp);
            vars.BG1VOFS_copy2.* = @truncate(tmp >> 16);
        }
    }

    if (vars.link_x_vel.* != 0) {
        const xvel = vars.link_x_vel.*;
        vars.BG2HOFS_copy2.* +%= @bitCast(@as(i16, @as(i8, @bitCast(xvel))));
        const which = if (sign8(xvel)) vars.overworld_unk3 else vars.overworld_unk3_neg;
        which.* +%= abs8(xvel);
        if (!sign16(which.* -% 0x10)) {
            which.* -%= 0x10;
            loPtr(vars.overworld_screen_trans_dir_bits2).* |= if (sign8(xvel)) 2 else 1;
        }
        const other = if (sign8(xvel)) vars.overworld_unk3_neg else vars.overworld_unk3;
        other.* = 0 -% which.*;

        var r4: u16 = @bitCast(@as(i16, @as(i8, @bitCast(xvel))));
        var subp: u16 = undefined;
        // The C writes this word one byte later, overlapping the y one above.
        std.mem.writeInt(u16, g_ram[0x69f..0x6a1], r4, .little);
        const oi = loPtr(vars.overlay_index).*;
        if (oi != 0x97 and oi != 0x9d and r4 != 0) {
            if (oi == 0x95 or oi == 0x9e) {
                subp = (r4 & 3) << 14;
                r4 >>= 2;
                if (r4 >= 0x3000) r4 |= 0xf000;
            } else {
                subp = (r4 & 1) << 15;
                r4 >>= 1;
                if (r4 >= 0x7000) r4 |= 0xf000;
            }
            var tmp = @as(u32, vars.BG1HOFS_subpixel.*) | @as(u32, vars.BG1HOFS_copy2.*) << 16;
            tmp +%= @as(u32, subp) | @as(u32, r4) << 16;
            vars.BG1HOFS_subpixel.* = @truncate(tmp);
            vars.BG1HOFS_copy2.* = @truncate(tmp >> 16);
        }
    }

    const oi = loPtr(vars.overlay_index).*;
    if (oi == 0x9c) {
        var tmp = @as(u32, vars.BG1VOFS_subpixel.*) | @as(u32, vars.BG1VOFS_copy2.*) << 16;
        tmp -%= 0x2000;
        vars.BG1VOFS_subpixel.* = @truncate(tmp);
        vars.BG1VOFS_copy2.* = @as(u16, @truncate(tmp >> 16)) +%
            std.mem.readInt(u16, g_ram[0x69e..0x6a0], .little);
        vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2.*;
    } else if (oi == 0x97 or oi == 0x9d) {
        var tmp = @as(u32, vars.BG1VOFS_subpixel.*) | @as(u32, vars.BG1VOFS_copy2.*) << 16;
        tmp +%= 0x2000;
        vars.BG1VOFS_subpixel.* = @truncate(tmp);
        vars.BG1VOFS_copy2.* = @truncate(tmp >> 16);
        tmp = @as(u32, vars.BG1HOFS_subpixel.*) | @as(u32, vars.BG1HOFS_copy2.*) << 16;
        tmp +%= 0x2000;
        vars.BG1HOFS_subpixel.* = @truncate(tmp);
        vars.BG1HOFS_copy2.* = @truncate(tmp >> 16);
    }

    if (vars.dungeon_room_index.* == 0x181) {
        vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy2.* | 0x100;
        vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2.*;
    }
}

pub export fn EndSequence_32() callconv(.c) void {
    load_gfx.EnableForceBlank();
    load_gfx.EraseTileMaps_triforce();
    load_gfx.TransferFontToVRAM();
    Credits_LoadCoolBackground();
    Credits_InitializePolyhedral();
    vars.INIDISP_copy.* = 128;
    vars.overworld_palette_aux_or_main.* = 0x200;
    vars.hud_palette.* = 1;
    load_gfx.Palette_Load_HUD();
    vars.flag_update_cgram_in_nmi.* +%= 1;
    vars.deaths_per_palace[4] = 0;
    vars.deaths_per_palace[13] +%= vars.death_save_counter.*;
    var sum: u16 = vars.deaths_per_palace[13];
    var i: i32 = 12;
    while (i >= 0) : (i -= 1)
        sum +%= vars.deaths_per_palace[@intCast(i)];
    vars.death_var2.* = sum;
    vars.death_save_counter.* = 0;
    vars.link_health_current.* = kHealthAfterDeath[vars.link_health_capacity.* >> 3];
    vars.savegame_is_darkworld.* = 0x40;
    SaveGameFile();
    vars.aux_palette_buffer[38] = 0;
    vars.main_palette_buffer[38] = 0;
    vars.aux_palette_buffer[0] = 0;
    vars.main_palette_buffer[0] = 0;
    vars.TM_copy.* = 0x16;
    vars.TS_copy.* = 0;
    vars.R16.* = 0x6800;
    vars.R18.* = 0;
    ending_which_dung.* = 0;
    vars.BG2VOFS_copy2.* = @bitCast(@as(i16, -0x48));
    vars.BG2HOFS_copy2.* = 0x90;
    vars.BG3VOFS_copy2.* = 0;
    vars.BG3HOFS_copy2.* = 0;
    Credits_AddNextAttribution();
    vars.music_control.* = 0x22;
    vars.CGWSEL_copy.* = 0;
    vars.CGADSUB_copy.* = 162;
    // real zelda does 0x12 here but this seems to work too
    rtl.zelda_ppu_write(BG2SC, 0x13);
    vars.COLDATA_copy0.* = 0x3f;
    vars.COLDATA_copy1.* = 0x5f;
    vars.COLDATA_copy2.* = 0x9f;
    vars.subsubmodule_index.* = 64;
    vars.INIDISP_copy.* = 0;

    rtl.HdmaSetup(0, 0xebd53, 0x42, 0, @truncate(BG2HOFS), 0);
    vars.HDMAEN_copy.* = 0x80;

    vars.BG2HOFS_copy.* = vars.BG2HOFS_copy2.*;
    vars.BG2VOFS_copy.* = vars.BG2VOFS_copy2.*;
    vars.BG1HOFS_copy.* = vars.BG1HOFS_copy2.*;
    vars.BG1VOFS_copy.* = vars.BG1VOFS_copy2.*;
}

pub export fn Credits_FadeOutFixedCol() callconv(.c) void {
    vars.subsubmodule_index.* -%= 1;
    if (vars.subsubmodule_index.* == 0) {
        vars.subsubmodule_index.* = 16;
        if (vars.COLDATA_copy0.* != 32) {
            vars.COLDATA_copy0.* -%= 1;
        } else if (vars.COLDATA_copy1.* != 64) {
            vars.COLDATA_copy1.* -%= 1;
        } else if (vars.COLDATA_copy2.* != 128) {
            vars.COLDATA_copy2.* -%= 1;
        }
    }
}

pub export fn Credits_FadeColorAndBeginAnimating() callconv(.c) void {
    Credits_FadeOutFixedCol();
    vars.nmi_disable_core_updates.* = 1;
    Credits_AnimateTheTriangles();
    if (vars.frame_counter.* & 3 == 0) {
        vars.BG2HOFS_copy2.* +%= 1;
        if (vars.BG2HOFS_copy2.* == 0xc00) {
            // real zelda writes 0x00 to BG1SC here but that doesn't seem needed
            rtl.zelda_ppu_write(BG2SC, 0x13);
        }
        vars.room_bounds_y.named.a1 = vars.BG2HOFS_copy2.* >> 1;
        vars.room_bounds_y.named.a0 = vars.room_bounds_y.named.a1 +% vars.BG2HOFS_copy2.*;
        vars.room_bounds_y.named.b0 = vars.room_bounds_y.named.a0 >> 1;
        vars.room_bounds_y.named.b1 = vars.room_bounds_y.named.a1 >> 1;
        if (vars.BG3VOFS_copy2.* == 3288) {
            vars.R16.* = 0x80;
            vars.submodule_index.* +%= 1;
        } else {
            vars.BG3VOFS_copy2.* +%= 1;
            if (vars.BG3VOFS_copy2.* & 7 == 0) {
                vars.R18.* = vars.BG3VOFS_copy2.* >> 3;
                Credits_AddNextAttribution();
            }
        }
    }
    vars.BG2HOFS_copy.* = vars.BG2HOFS_copy2.*;
    vars.BG2VOFS_copy.* = vars.BG2VOFS_copy2.*;
    vars.BG1HOFS_copy.* = vars.BG1HOFS_copy2.*;
    vars.BG1VOFS_copy.* = vars.BG1VOFS_copy2.*;
}

pub export fn Credits_AddNextAttribution() callconv(.c) void {
    var dst = vars.vram_upload_data + (vars.vram_upload_offset.* >> 1);

    dst[0] = swap16(vars.R16.*);
    dst[1] = 0x3e40;
    dst[2] = kEnding_MapData()[159];
    dst += 3;

    if (vars.R18.* < 394) {
        var src = kEnding_Credits_Text() + kEnding_Credits_Offs()[vars.R18.*];
        if (src[0] != 0xff) {
            dst[0] = swap16(vars.R16.* +% src[0]);
            dst += 1;
            src += 1;
            var n: i32 = src[0];
            src += 1;
            dst[0] = swap16(@intCast(n));
            dst += 1;
            n = (n + 1) >> 1;
            while (true) {
                dst[0] = kEnding_MapData()[src[0]];
                dst += 1;
                src += 1;
                n -= 1;
                if (n == 0) break;
            }
        }

        if (ending_which_dung.* & 1 != 0 or
            vars.R18.* *% 2 == tables.kEnding_Digits_ScrollY[ending_which_dung.* >> 1])
        {
            const t = tables.kEnding_Credits_DigitChar[ending_which_dung.* & 1];
            std.mem.writeInt(u16, g_ram[0xce..0xd0], t, .little);

            dst[0] = swap16(vars.R16.* +% 0x19);
            dst[1] = 0x500;

            var deaths = vars.deaths_per_palace[tables.kEnding_Func9_Tab2[ending_which_dung.* >> 1]];
            if (deaths >= 1000) deaths = 999;

            dst[4] = t +% deaths % 10;
            deaths /= 10;
            dst[3] = t +% deaths % 10;
            deaths /= 10;
            dst[2] = t +% deaths;
            dst += 5;
            ending_which_dung.* +%= 1;
        }
    }

    vars.R16.* +%= 0x20;
    if (vars.R16.* & 0x3ff == 0)
        vars.R16.* = (vars.R16.* & 0x6800) ^ 0x800;
    vars.vram_upload_offset.* = @intCast(@intFromPtr(dst) - @intFromPtr(vars.vram_upload_data));
    @as(*u8, @ptrCast(dst)).* = 0xff;
    vars.nmi_load_bg_from_vram.* = 1;
}

pub export fn Credits_AddEndingSequenceText() callconv(.c) void {
    var dst = vars.vram_upload_data;
    dst[0] = 0x60;
    dst[1] = 0xfe47;
    dst[2] = kEnding_MapData()[159];
    dst += 3;

    var curo = kEnding0_Data() + kEnding0_Offs()[vars.submodule_index.* >> 1];
    const endo = kEnding0_Data() + kEnding0_Offs()[(vars.submodule_index.* >> 1) + 1];
    while (true) {
        dst[0] = std.mem.readInt(u16, curo[0..2], .little);
        dst[1] = std.mem.readInt(u16, curo[2..4], .little);
        var m: i32 = @intCast((dst[1] >> 9) & 0x7f);
        dst += 2;
        curo += 4;
        while (true) {
            dst[0] = kEnding_MapData()[curo[0]];
            dst += 1;
            curo += 1;
            m -= 1;
            if (m < 0) break;
        }
        if (curo == endo) break;
    }

    vars.vram_upload_offset.* = @intCast(@intFromPtr(dst) - @intFromPtr(vars.vram_upload_data));
    @as(*u8, @ptrCast(dst)).* = 0xff;
    vars.nmi_load_bg_from_vram.* = 1;
}

pub export fn Credits_BrightenTriangles() callconv(.c) void {
    if (vars.frame_counter.* & 15 == 0) {
        vars.INIDISP_copy.* +%= 1;
        if (vars.INIDISP_copy.* == 15)
            vars.submodule_index.* +%= 1;
    }
    Credits_AnimateTheTriangles();
}

pub export fn Credits_StopCreditsScroll() callconv(.c) void {
    loPtr(vars.R16).* -%= 1;
    if (loPtr(vars.R16).* == 0) {
        vars.darkening_or_lightening_screen.* = 0;
        vars.palette_filter_countdown.* = 0;
        wordPtr(vars.mosaic_target_level).* = 0x1f;
        vars.submodule_index.* +%= 1;
        vars.R16.* = 0xc0;
        vars.R18.* = 0;
    }
    Credits_AnimateTheTriangles();
}

pub export fn Credits_FadeAndDisperseTriangles() callconv(.c) void {
    loPtr(vars.R16).* -%= 1;
    if (loPtr(vars.R18).* == 0) {
        load_gfx.ApplyPaletteFilter_bounce();
        if (loPtr(vars.palette_filter_countdown).* != 0) {
            Credits_AnimateTheTriangles();
            return;
        }
        loPtr(vars.R18).* +%= 1;
    }
    if (loPtr(vars.R16).* != 0) {
        Credits_AnimateTheTriangles();
        return;
    }
    vars.submodule_index.* +%= 1;
    load_gfx.PaletteFilter_WishPonds_Inner();
}

pub export fn Credits_FadeInTheEnd() callconv(.c) void {
    if (vars.frame_counter.* & 7 == 0) {
        load_gfx.PaletteFilter_SP5F();
        if (loPtr(vars.palette_filter_countdown).* == 0)
            vars.submodule_index.* +%= 1;
    }
    Credits_HangForever();
}

pub export fn Credits_HangForever() callconv(.c) void {
    SetOamPlain(oam_buf + 0, 0xa0, 0xb8, 0x00, 0x3b, 2);
    SetOamPlain(oam_buf + 1, 0xb0, 0xb8, 0x02, 0x3b, 2);
    SetOamPlain(oam_buf + 2, 0xc0, 0xb8, 0x04, 0x3b, 2);
    SetOamPlain(oam_buf + 3, 0xd0, 0xb8, 0x06, 0x3b, 2);
}

pub export fn CrystalCutscene_InitializePolyhedral() callconv(.c) void {
    vars.poly_config1.* = 156;
    vars.poly_config_color_mode.* = 1;
    vars.is_nmi_thread_active.* = 1;
    vars.intro_did_run_step.* = 1;
    vars.poly_base_x.* = 32;
    vars.poly_base_y.* = 32;
    loPtr(vars.poly_var1).* = 32;
    vars.poly_which_model.* = 0;
    vars.poly_a.* = 16;
    vars.TS_copy.* = 0;
    vars.TM_copy.* = 0x16;
}

// ---------------------------------------------------------------------------

const testing = std.testing;

test "the struct mirrors match the C layouts" {
    // Values taken from a C probe on this target.
    try testing.expectEqual(5, @sizeOf(IntroSpriteEnt));
    try testing.expectEqual(6, @sizeOf(DrawMultipleData));
    try testing.expectEqual(2, @offsetOf(DrawMultipleData, "char_flags"));
    try testing.expectEqual(4, @offsetOf(DrawMultipleData, "ext"));
    try testing.expectEqual(6, @sizeOf(PrepOamCoordsRet));
    try testing.expectEqual(4, @offsetOf(PrepOamCoordsRet, "r4"));
    try testing.expectEqual(4, @sizeOf(DungPalInfo));
}

test "the credits dispatch table is 39 entries in the documented order" {
    try testing.expectEqual(39, kEndSequence_Funcs.len);
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &Credits_LoadNextScene_Overworld), kEndSequence_Funcs[0]);
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &Credits_ScrollScene_Overworld), kEndSequence_Funcs[1]);
    // The two dungeon scenes sit at 2/3 and again at 20..23.
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &Credits_LoadNextScene_Dungeon), kEndSequence_Funcs[2]);
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &Credits_ScrollScene_Dungeon), kEndSequence_Funcs[23]);
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &EndSequence_32), kEndSequence_Funcs[32]);
    try testing.expectEqual(@as(*const PlayerHandlerFunc, &Credits_HangForever), kEndSequence_Funcs[38]);
    try testing.expectEqual(3, kEndSequence0_Funcs.len);
}

test "the sprite-draw pointer table covers all 32 entries" {
    try testing.expectEqual(32, kEndSequence_Dmds.len);
    // j >> 1 indexes it, so scene byte 0x3e reaches the last table.
    try testing.expectEqual(31, 0x3e >> 1);
    try testing.expectEqual(@as(i8, 0), kEndSequence_Dmd31[0].x);
    try testing.expectEqual(@as(u16, 0x8060), kEndSequence_Dmd31[0].char_flags);
    try testing.expectEqual(21, kEndSequence_Dmd12.len);
}

test "Ending_Func2's animation table uses -1 as the 255 sentinel" {
    // The C reads this signed table into a uint8 and compares against 255.
    try testing.expectEqual(@as(i8, -1), tables.kEnding_Func2_Tab0[23]);
    try testing.expectEqual(@as(u8, 255), @as(u8, @bitCast(tables.kEnding_Func2_Tab0[23])));
    try testing.expectEqual(28, tables.kEnding_Func2_Tab0.len);
    try testing.expectEqual(27, tables.kEnding_Func2_Delay.len);
}

test "AnimateTriforceRoomTriangle_HandleContracting clamps at the step boundaries" {
    // Moving toward the final x steps +1, and 0x11 snaps back to 0x10.
    vars.intro_x_lo[0] = 0;
    vars.intro_y_lo[0] = 0;
    vars.intro_x_vel[0] = 0x10;
    vars.intro_y_vel[0] = 0x10;
    AnimateTriforceRoomTriangle_HandleContracting(0);
    try testing.expectEqual(@as(u8, 0x10), vars.intro_x_vel[0]);
    try testing.expectEqual(@as(u8, 0x10), vars.intro_y_vel[0]);

    // Past the final coordinate it steps -1, and 0xef snaps back to 0xf0.
    vars.intro_x_lo[0] = 0xff;
    vars.intro_y_lo[0] = 0xff;
    vars.intro_x_vel[0] = 0xf0;
    vars.intro_y_vel[0] = 0xf0;
    AnimateTriforceRoomTriangle_HandleContracting(0);
    try testing.expectEqual(@as(u8, 0xf0), vars.intro_x_vel[0]);
    try testing.expectEqual(@as(u8, 0xf0), vars.intro_y_vel[0]);

    // An unclamped value just moves by one.
    vars.intro_x_lo[0] = 0;
    vars.intro_x_vel[0] = 4;
    AnimateTriforceRoomTriangle_HandleContracting(0);
    try testing.expectEqual(@as(u8, 5), vars.intro_x_vel[0]);
}

test "swap16 exchanges the halves" {
    try testing.expectEqual(@as(u16, 0x3412), swap16(0x1234));
    try testing.expectEqual(@as(u16, 0x0080), swap16(0x8000));
}

test "Credits_SpriteDraw_SetShadowProp writes both flag bytes" {
    Credits_SpriteDraw_SetShadowProp(3, 2);
    try testing.expectEqual(@as(u8, 2), vars.sprite_flags2[3]);
    try testing.expectEqual(@as(u8, 16), vars.sprite_flags3[3]);
}

test "Intro_Clear1kbBlocksOfWRAM walks R16 down and trails R18 by 0x400" {
    @memset(g_ram[0x2000..0x20000], 0xcd);
    vars.R16.* = 0x1ffe;
    vars.R18.* = 0x1bfe;
    Intro_Clear1kbBlocksOfWRAM();
    try testing.expectEqual(@as(u16, 0x1bfe), vars.R16.*);
    try testing.expectEqual(@as(u16, 0x17fe), vars.R18.*);
    // The do-while steps i down by 2 and stops once it equals R18, so the range
    // cleared is 0x1ffe down to 0x1c00 inclusive, in each of the 15 banks.
    try testing.expectEqual(@as(u8, 0), g_ram[0x2000 + 0x1ffe]);
    try testing.expectEqual(@as(u8, 0), g_ram[0x2000 + 0x1c00]);
    try testing.expectEqual(@as(u8, 0), g_ram[0x2000 + 0x1c00 + 14 * 0x2000]);
    // It exits before clearing the word at R18 itself.
    try testing.expectEqual(@as(u8, 0xcd), g_ram[0x2000 + 0x1bfe]);
}

test "the scene tables line up with the 16 credit scenes" {
    try testing.expectEqual(17, tables.kEndingSprites_Idx.len);
    try testing.expectEqual(85, tables.kEndingSprites_X.len);
    try testing.expectEqual(85, tables.kEndingSprites_Y.len);
    // The index table ends at the sprite count, so every scene slices in range.
    try testing.expectEqual(@as(u8, 85), tables.kEndingSprites_Idx[16]);
    try testing.expectEqual(16, tables.kEnding1_TargetScrollX.len);
    try testing.expectEqual(16, tables.kEnding1_3_Tab0.len);
    try testing.expectEqual(17, tables.kEnding_SpritePack.len);
}

