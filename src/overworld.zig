//! Port of src/overworld.c: overworld loading and screen transitions, the
//! map16/map32 tilemap decoders, camera scrolling, the mirror warp, and the
//! tile interactions (bushes, rocks, bombs, secrets, entrances).
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl.zig");
const rtl_types = @import("zelda_rtl_types.zig");
const features = @import("features.zig");
const main_mod = @import("main.zig");
const util = @import("util.zig");
const tables = @import("overworld_tables.zig");
const load_gfx = @import("load_gfx.zig");
const misc = @import("misc.zig");
const hud = @import("hud.zig");
const messaging = @import("messaging.zig");
const tagalong = @import("tagalong.zig");
const audio = @import("audio.zig");
const player_oam = @import("player_oam.zig");
const config = @import("config.zig");

const MemBlk = util.MemBlk;
const OamEnt = vars.OamEnt;
const g_ram = &vars.g_ram;
const g_zenv = &rtl_types.g_zenv;

/// zelda_rtl.h: typedef void PlayerHandlerFunc();
const PlayerHandlerFunc = fn () callconv(.c) void;

/// types.h
pub const Point16U = extern struct { x: u16, y: u16 };

// snes/snes_regs.h
const BG1HOFS = 0x210d;
const BG2HOFS = 0x210f;
const WH0 = 0x2126;

// player.h
const kPlayerState_Ground = 0;
const kPlayerState_Mirror = 20;
const kPlayerState_PermaBunny = 23;

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

/// misc.h, a static inline with no linkable symbol. The asset blobs are not
/// guaranteed aligned, hence align(1).
fn FindInWordArray(data: [*]align(1) const u16, lookfor: u16, size: usize) i32 {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (data[i] == lookfor) return @intCast(i);
    }
    return -1;
}

/// The overworld event overlay indexes a 64-wide grid.
inline fn XY(x: usize, y: usize) usize {
    return y * 64 + x;
}

// The C aliases these two counters onto some_menu_ctr.
const turtlerock_ctr = vars.some_menu_ctr;
const ganonentrance_ctr = vars.some_menu_ctr;

// ---------------------------------------------------------------------------
// assets.h
// ---------------------------------------------------------------------------

inline fn assetU8(comptime i: usize) [*]const u8 {
    return main_mod.g_asset_ptrs[i].?;
}
inline fn assetI8(comptime i: usize) [*]const i8 {
    return @ptrCast(main_mod.g_asset_ptrs[i].?);
}
inline fn assetU16(comptime i: usize) [*]align(1) const u16 {
    return @ptrCast(main_mod.g_asset_ptrs[i].?);
}
inline fn assetI16(comptime i: usize) [*]align(1) const i16 {
    return @ptrCast(main_mod.g_asset_ptrs[i].?);
}

inline fn kEnemyDamageData() [*]const u8 {
    return assetU8(56);
}
inline fn kEnemyDamageData_SIZE() u32 {
    return main_mod.g_asset_sizes[56];
}
inline fn kMap32ToMap16_0() [*]const u8 {
    return assetU8(60);
}
inline fn kMap32ToMap16_1() [*]const u8 {
    return assetU8(61);
}
inline fn kMap32ToMap16_2() [*]const u8 {
    return assetU8(62);
}
inline fn kMap32ToMap16_3() [*]const u8 {
    return assetU8(63);
}
inline fn kMap16ToMap8() [*]align(1) const u16 {
    return assetU16(70);
}
inline fn kOverworld_Hibytes_Comp(idx: c_int) MemBlk {
    return main_mod.FindInAssetArray(105, idx);
}
inline fn kOverworld_Lobytes_Comp(idx: c_int) MemBlk {
    return main_mod.FindInAssetArray(106, idx);
}
inline fn kOverworldMapIsSmall() [*]const u8 {
    return assetU8(107);
}
inline fn kOverworldAuxTileThemeIndexes() [*]const u8 {
    return assetU8(108);
}
inline fn kOverworldBgPalettes() [*]const u8 {
    return assetU8(109);
}
inline fn kOverworld_SignText() [*]align(1) const u16 {
    return assetU16(110);
}
inline fn kOwMusicSets() [*]const u8 {
    return assetU8(111);
}
inline fn kOwMusicSets2() [*]const u8 {
    return assetU8(112);
}
inline fn kBirdTravel_ScreenIndex() [*]align(1) const u16 {
    return assetU16(113);
}
inline fn kBirdTravel_Map16LoadSrcOff() [*]align(1) const u16 {
    return assetU16(114);
}
inline fn kBirdTravel_ScrollX() [*]align(1) const u16 {
    return assetU16(115);
}
inline fn kBirdTravel_ScrollY() [*]align(1) const u16 {
    return assetU16(116);
}
inline fn kBirdTravel_LinkXCoord() [*]align(1) const u16 {
    return assetU16(117);
}
inline fn kBirdTravel_LinkYCoord() [*]align(1) const u16 {
    return assetU16(118);
}
inline fn kBirdTravel_CameraXScroll() [*]align(1) const u16 {
    return assetU16(119);
}
inline fn kBirdTravel_CameraYScroll() [*]align(1) const u16 {
    return assetU16(120);
}
inline fn kBirdTravel_Unk1() [*]const i8 {
    return assetI8(121);
}
inline fn kBirdTravel_Unk3() [*]const i8 {
    return assetI8(122);
}
inline fn kWhirlpoolAreas() [*]align(1) const u16 {
    return assetU16(123);
}
inline fn kWhirlpoolAreas_SIZE() u32 {
    return main_mod.g_asset_sizes[123];
}
inline fn kOverworld_Entrance_Area() [*]align(1) const u16 {
    return assetU16(124);
}
inline fn kOverworld_Entrance_Pos() [*]align(1) const u16 {
    return assetU16(125);
}
inline fn kOverworld_Entrance_Id() [*]const u8 {
    return assetU8(126);
}
inline fn kFallHole_Area() [*]align(1) const u16 {
    return assetU16(127);
}
inline fn kFallHole_Pos() [*]align(1) const u16 {
    return assetU16(128);
}
inline fn kFallHole_Entrances() [*]const u8 {
    return assetU8(129);
}
inline fn kExitData_ScreenIndex() [*]const u8 {
    return assetU8(130);
}
inline fn kExitDataRooms() [*]align(1) const u16 {
    return assetU16(131);
}
inline fn kExitData_Map16LoadSrcOff() [*]align(1) const u16 {
    return assetU16(132);
}
inline fn kExitData_ScrollX() [*]align(1) const u16 {
    return assetU16(133);
}
inline fn kExitData_ScrollY() [*]align(1) const u16 {
    return assetU16(134);
}
inline fn kExitData_XCoord() [*]align(1) const u16 {
    return assetU16(135);
}
inline fn kExitData_YCoord() [*]align(1) const u16 {
    return assetU16(136);
}
inline fn kExitData_CameraXScroll() [*]align(1) const u16 {
    return assetU16(137);
}
inline fn kExitData_CameraYScroll() [*]align(1) const u16 {
    return assetU16(138);
}
inline fn kExitData_NormalDoor() [*]align(1) const u16 {
    return assetU16(139);
}
inline fn kExitData_FancyDoor() [*]align(1) const u16 {
    return assetU16(140);
}
inline fn kExitData_Unk1() [*]const i8 {
    return assetI8(141);
}
inline fn kExitData_Unk3() [*]const i8 {
    return assetI8(142);
}
inline fn kSpExit_Top() [*]align(1) const u16 {
    return assetU16(143);
}
inline fn kSpExit_Bottom() [*]align(1) const u16 {
    return assetU16(144);
}
inline fn kSpExit_Left() [*]align(1) const u16 {
    return assetU16(145);
}
inline fn kSpExit_Right() [*]align(1) const u16 {
    return assetU16(146);
}
inline fn kSpExit_Tab4() [*]align(1) const i16 {
    return assetI16(147);
}
inline fn kSpExit_Tab5() [*]align(1) const i16 {
    return assetI16(148);
}
inline fn kSpExit_Tab6() [*]align(1) const i16 {
    return assetI16(149);
}
inline fn kSpExit_Tab7() [*]align(1) const i16 {
    return assetI16(150);
}
inline fn kSpExit_LeftEdgeOfMap() [*]align(1) const u16 {
    return assetU16(151);
}
inline fn kSpExit_Dir() [*]const u8 {
    return assetU8(152);
}
inline fn kSpExit_SprGfx() [*]const u8 {
    return assetU8(153);
}
inline fn kSpExit_AuxGfx() [*]const u8 {
    return assetU8(154);
}
inline fn kSpExit_PalBg() [*]const u8 {
    return assetU8(155);
}
inline fn kSpExit_PalSpr() [*]const u8 {
    return assetU8(156);
}
inline fn kOverworldSecrets_Offs() [*]align(1) const u16 {
    return assetU16(157);
}
inline fn kOverworldSecrets() [*]const u8 {
    return assetU8(158);
}
inline fn kOverworldSpriteOffs() [*]align(1) const u16 {
    return assetU16(159);
}
inline fn kOverworldSprites() [*]const u8 {
    return assetU8(160);
}
inline fn kOverworldSpriteGfx() [*]const u8 {
    return assetU8(161);
}
inline fn kOverworldSpritePalettes() [*]const u8 {
    return assetU8(162);
}
inline fn kMap8DataToTileAttr() [*]const u8 {
    return assetU8(163);
}
inline fn kSomeTileAttr() [*]const u8 {
    return assetU8(164);
}

// ---------------------------------------------------------------------------
// Still in C.
// ---------------------------------------------------------------------------

// ancilla.c
extern fn AncillaAdd_BushPoof(x: u16, y: u16) void;
extern fn Ancilla_TerminateSelectInteractives(y: u8) u8;
// dungeon.c
extern fn Dungeon_ApproachFixedColor_variable(a: u8) void;
extern fn Dungeon_PlayBlipAndCacheQuadrantVisits() void;
extern fn Dungeon_ResetTorchBackgroundAndPlayerInner() void;
extern fn LoadOWMusicIfNeeded() void;
extern fn ResetTransitionPropsAndAdvance_ResetInterface() void;
// player.c
extern fn Link_CheckForEdgeScreenTransition() bool;
extern fn Link_HandleMovingAnimation_FullLongEntry() void;
extern fn Link_HandleVelocity() void;
extern fn Link_ItemReset_FromOverworldThings() void;
extern fn Link_Main() void;
extern fn Link_ResetStateAfterDamagingPit() void;
extern fn Link_ResetSwimmingState() void;
// sprite.c
extern fn Sprite_InitializeMirrorPortal() void;
extern fn Sprite_InitializeSlots() void;
extern fn Sprite_Main() void;
extern fn Sprite_OverworldReloadAll_justLoad() void;
extern fn Sprite_ReloadAll_Overworld() void;
extern fn Sprite_ResetAll() void;
extern fn Sprite_SpawnImmediatelySmashedTerrain(what: u8, x: u16, y: u16) void;

// ---------------------------------------------------------------------------
// Tables this file owns. The generator emits them as plain consts; these two
// are non-static in the C and other modules declare them extern.
// ---------------------------------------------------------------------------

pub export const kOverworld_OffsetBaseX = tables.kOverworld_OffsetBaseX;
pub export const kOverworld_OffsetBaseY = tables.kOverworld_OffsetBaseY;
pub export const kVariousPacks = tables.kVariousPacks;

// ---------------------------------------------------------------------------
// Dispatch tables.
// ---------------------------------------------------------------------------

const kOverworld_EntranceSequence = [5]*const PlayerHandlerFunc{
    &Overworld_AnimateEntrance_PoD,
    &Overworld_AnimateEntrance_Skull,
    &Overworld_AnimateEntrance_Mire,
    &Overworld_AnimateEntrance_TurtleRock,
    &Overworld_AnimateEntrance_GanonsTower,
};

const kOverworldSubmodules = [48]*const PlayerHandlerFunc{
    &Module09_00_PlayerControl,
    &Module09_LoadAuxGFX,
    &Overworld_FinishTransGfx,
    &Module09_LoadNewMapAndGFX,
    &Module09_LoadNewSprites,
    &Overworld_StartScrollTransition,
    &Overworld_RunScrollTransition,
    &Overworld_EaseOffScrollTransition,
    &Overworld_FinalizeEntryOntoScreen,
    &Module09_09_OpenBigDoorFromExiting,
    &Module09_0A_WalkFromExiting_FacingDown,
    &Module09_0B_WalkFromExiting_FacingUp,
    &Module09_0C_OpenBigDoor,
    &Overworld_StartMosaicTransition,
    &PreOverworld_LoadOverlays,
    &Module09_LoadAuxGFX,
    &Overworld_FinishTransGfx,
    &Module09_LoadNewMapAndGFX,
    &Module09_LoadNewSprites,
    &Overworld_StartScrollTransition,
    &Overworld_RunScrollTransition,
    &Overworld_EaseOffScrollTransition,
    &Module09_FadeBackInFromMosaic,
    &Overworld_StartMosaicTransition,
    &Overworld_Func18,
    &Overworld_Func19,
    &Module09_LoadAuxGFX,
    &Overworld_FinishTransGfx,
    &Overworld_Func1C,
    &Overworld_Func1D,
    &Overworld_Func1E,
    &Overworld_Func1F,
    &Overworld_LoadOverlays2,
    &Overworld_LoadAmbientOverlayFalse,
    &Overworld_Func22,
    &Module09_MirrorWarp,
    &Overworld_StartMosaicTransition,
    &Overworld_LoadOverlays,
    &Module09_LoadAuxGFX,
    &Overworld_FinishTransGfx,
    &Overworld_LoadAndBuildScreen,
    &Module09_FadeBackInFromMosaic,
    &Module09_2A_RecoverFromDrowning,
    &Overworld_Func2B,
    &Module09_MirrorWarp,
    &Overworld_WeathervaneExplosion,
    &Module09_2E_Whirlpool,
    &Overworld_Func2F,
};

const kModule_PreOverworld = [3]*const PlayerHandlerFunc{
    &PreOverworld_LoadProperties,
    &PreOverworld_LoadOverlays,
    &Module08_02_LoadAndAdvance,
};

pub export fn GetMap8toTileAttr() callconv(.c) [*]const u8 {
    return kMap8DataToTileAttr();
}

pub export fn GetMap16toMap8Table() callconv(.c) [*]align(1) const u16 {
    return kMap16ToMap8();
}

pub export fn LookupInOwEntranceTab(r0: u16, r2: u16) callconv(.c) bool {
    var i: i32 = tables.kOverworld_Entrance_Tab0.len - 1;
    while (i >= 0) : (i -= 1) {
        const ii: usize = @intCast(i);
        if (r0 == tables.kOverworld_Entrance_Tab0[ii] and r2 == tables.kOverworld_Entrance_Tab1[ii])
            return true;
    }
    return false;
}

pub export fn LookupInOwEntranceTab2(pos: u16) callconv(.c) c_int {
    var i: i32 = 128;
    while (i >= 0) : (i -= 1) {
        const ii: usize = @intCast(i);
        if (pos == kOverworld_Entrance_Pos()[ii] and
            vars.overworld_area_index.* == kOverworld_Entrance_Area()[ii])
            return i;
    }
    return -1;
}

pub export fn CanEnterWithTagalong(e: c_int) callconv(.c) bool {
    const t = vars.follower_indicator.*;
    return t == 0 or t == 5 or t == 14 or t == 1 or ((t == 7 or t == 8) and e >= 59);
}

pub export fn DirToEnum(dir_in: c_int) callconv(.c) c_int {
    var dir = dir_in;
    var xx: c_int = 3;
    while (dir & 1 == 0) {
        xx -= 1;
        dir >>= 1;
    }
    return xx;
}

pub export fn Overworld_ResetMosaicDown() callconv(.c) void {
    if (vars.palette_filter_countdown.* & 1 != 0)
        vars.mosaic_level.* -%= 0x10;
    vars.BGMODE_copy.* = 9;
    vars.MOSAIC_copy.* = vars.mosaic_level.* | 7;
}

pub export fn Overworld_Func1D() callconv(.c) void {
    unreachable; // assert(0)
}

pub export fn Overworld_Func1E() callconv(.c) void {
    unreachable; // assert(0)
}

pub export fn Overworld_GetSignText(area: c_int) callconv(.c) u16 {
    return kOverworld_SignText()[@intCast(area)];
}

pub export fn GetOverworldSpritePtr(area: c_int) callconv(.c) [*]const u8 {
    const base: usize = if (vars.sram_progress_indicator.* == 3)
        2
    else if (vars.sram_progress_indicator.* == 2)
        1
    else
        0;
    return kOverworldSprites() + kOverworldSpriteOffs()[@as(usize, @intCast(area)) + base * 144];
}

pub export fn GetOverworldBgPalette(idx: c_int) callconv(.c) u8 {
    return kOverworldBgPalettes()[@intCast(idx)];
}

pub export fn Sprite_LoadGraphicsProperties() callconv(.c) void {
    @memcpy((vars.overworld_sprite_gfx + 64)[0..64], (kOverworldSpriteGfx() + 0xc0)[0..64]);
    @memcpy((vars.overworld_sprite_palettes + 64)[0..64], (kOverworldSpritePalettes() + 0xc0)[0..64]);
    Sprite_LoadGraphicsProperties_light_world_only();
}

pub export fn Sprite_LoadGraphicsProperties_light_world_only() callconv(.c) void {
    const i: usize = if (vars.sram_progress_indicator.* < 2)
        0
    else if (vars.sram_progress_indicator.* != 3)
        1
    else
        2;
    @memcpy(vars.overworld_sprite_gfx[0..64], (kOverworldSpriteGfx() + i * 64)[0..64]);
    @memcpy(vars.overworld_sprite_palettes[0..64], (kOverworldSpritePalettes() + i * 64)[0..64]);
}

pub export fn InitializeMirrorHDMA() callconv(.c) void {
    vars.HDMAEN_copy.* = 0;

    vars.mirror_vars.var0 = 0;
    vars.mirror_vars.var6 = 0;
    vars.mirror_vars.var5 = 0;
    vars.mirror_vars.var7 = 0;
    vars.mirror_vars.var8 = 0;

    vars.mirror_vars.var10 = 8;
    vars.mirror_vars.var11 = 8;
    vars.mirror_vars.var9 = 21;
    vars.mirror_vars.var1[0] = @bitCast(@as(i16, -0x200));
    vars.mirror_vars.var1[1] = 0x200;
    vars.mirror_vars.var3[0] = @bitCast(@as(i16, -0x40));
    vars.mirror_vars.var3[1] = 0x40;

    rtl.HdmaSetup(0xF2FB, 0xF2FB, 0x42, @truncate(BG1HOFS), @truncate(BG2HOFS), 0);

    const v = vars.BG2HOFS_copy2.*;
    var i: usize = 0;
    while (i < 240) : (i += 1)
        vars.hdma_table_dynamic[i] = v;
    vars.HDMAEN_copy.* = 0xc0;
}

/// The HDMA table scrolls down by eight rows, copying each group of four.
fn mirrorShiftHdmaTable() void {
    var y: usize = 240 - 8;
    while (true) {
        const v = vars.hdma_table_dynamic[y - 8];
        vars.hdma_table_dynamic[y] = v;
        vars.hdma_table_dynamic[y + 2] = v;
        vars.hdma_table_dynamic[y + 4] = v;
        vars.hdma_table_dynamic[y + 6] = v;
        y -= 8;
        if (y == 0) break;
    }
}

pub export fn MirrorWarp_BuildWavingHDMATable() callconv(.c) void {
    load_gfx.MirrorWarp_RunAnimationSubmodules();
    if (vars.frame_counter.* & 1 != 0)
        return;

    mirrorShiftHdmaTable();

    const i: usize = vars.mirror_vars.var0 >> 1;
    var t: i32 = @as(i32, vars.mirror_vars.var6) + vars.mirror_vars.var3[i];
    const lim: i32 = vars.mirror_vars.var1[i];
    if (((t -% lim) ^ lim) & 0x8000 == 0) {
        t = lim;
        vars.mirror_vars.var5 = 0;
        vars.mirror_vars.var7 = 0;
        vars.mirror_vars.var0 ^= 2;
    }
    vars.mirror_vars.var6 = @truncate(@as(u32, @bitCast(t)));
    t +%= vars.mirror_vars.var7;
    vars.mirror_vars.var7 = @truncate(@as(u32, @bitCast(t)) & 0xff);
    if (t & 0x8000 != 0) {
        t |= 0xff;
    } else {
        t &= ~@as(i32, 0xff);
    }
    t = @as(i32, vars.mirror_vars.var5) +% swap16(@truncate(@as(u32, @bitCast(t))));
    vars.mirror_vars.var5 = @truncate(@as(u32, @bitCast(t)));
    if (vars.palette_filter_countdown.* >= 0x30 and (t & ~@as(i32, 7)) == 0) {
        vars.mirror_vars.var1[0] = @bitCast(@as(i16, -0x100));
        vars.mirror_vars.var1[1] = 0x100;
        vars.subsubmodule_index.* +%= 1;
        t = 0;
    }
    const v = @as(u16, @truncate(@as(u32, @bitCast(t)))) +% vars.BG2HOFS_copy2.*;
    vars.hdma_table_dynamic[0] = v;
    vars.hdma_table_dynamic[2] = v;
    vars.hdma_table_dynamic[4] = v;
    vars.hdma_table_dynamic[6] = v;
}

pub export fn MirrorWarp_BuildDewavingHDMATable() callconv(.c) void {
    load_gfx.MirrorWarp_RunAnimationSubmodules();
    if (vars.frame_counter.* & 1 != 0)
        return;

    mirrorShiftHdmaTable();

    const t = vars.hdma_table_dynamic[0xc0] | vars.hdma_table_dynamic[0xc8] |
        vars.hdma_table_dynamic[0xd0] | vars.hdma_table_dynamic[0xd8];
    if (t == vars.BG2HOFS_copy2.*) {
        vars.HDMAEN_copy.* = 0;
        vars.subsubmodule_index.* +%= 1;
        Overworld_SetFixedColAndScroll();
        if ((vars.overworld_screen_index.* & 0x3f) != 0x1b) {
            vars.BG2HOFS_copy.* = vars.BG2HOFS_copy2.*;
            vars.BG1HOFS_copy.* = vars.BG2HOFS_copy2.*;
            vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2.*;
            vars.BG2VOFS_copy.* = vars.BG2VOFS_copy2.*;
            vars.BG1VOFS_copy.* = vars.BG2VOFS_copy2.*;
            vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy2.*;
        }
    }
}

pub export fn TakeDamageFromPit() callconv(.c) void {
    vars.link_visibility_status.* = 12;
    vars.submodule_index.* = if (vars.player_is_indoors.* != 0) 20 else 42;
    vars.link_health_current.* -%= 8;
    if (vars.link_health_current.* >= 0xa8)
        vars.link_health_current.* = 0;
}

pub export fn Module08_OverworldLoad() callconv(.c) void {
    kModule_PreOverworld[vars.submodule_index.*]();
}

pub export fn PreOverworld_LoadProperties() callconv(.c) void {
    vars.CGWSEL_copy.* = 0x82;
    vars.dung_unk6.* = 0;
    AdjustLinkBunnyStatus();
    if (vars.main_module_index.* == 8) {
        LoadOverworldFromDungeon();
    } else {
        LoadOverworldFromSpecialOverworld();
    }
    Overworld_SetSongList();
    vars.link_num_keys.* = 0xff;
    hud.Hud_RefillLogic();

    const sc: u8 = @truncate(vars.overworld_screen_index.*);
    const dr: u8 = @truncate(vars.dungeon_room_index.*);
    var ow_anim_tiles: u8 = 0x58;
    var xt: u8 = 2;

    // `goto dark` is reached through a comma expression that also sets
    // ow_anim_tiles, and `goto setsong` skips the dark-world override.
    var skip_dark_override = false;
    pick: {
        if (sc == 3 or sc == 5 or sc == 7) {
            xt = 2;
            break :pick;
        }
        if (sc == 0x43 or sc == 0x45 or sc == 0x47) {
            xt = 9;
            break :pick;
        }
        ow_anim_tiles = 0x5a;
        var go_dark = sc >= 0x40;
        if (!go_dark) {
            if (dr == 0xe3 or dr == 0x18 or dr == 0x2f or (dr == 0x1f and sc == 0x18)) {
                xt = if (vars.sram_progress_indicator.* < 3) 7 else 2;
                break :pick;
            }
            xt = if (vars.savegame_has_master_sword_flags.* & 0x40 != 0) 2 else 5;
            if (dr == 0 or dr == 0xe1) break :pick;
            go_dark = true;
        }
        xt = 0xf3;
        if (vars.queued_music_control.* == 0xf2) {
            skip_dark_override = true;
            break :pick;
        }
        xt = if (vars.sram_progress_indicator.* < 2) 3 else 2;
    }
    if (!skip_dark_override and vars.savegame_is_darkworld.* != 0) {
        xt = if (sc == 0x40 or sc == 0x43 or sc == 0x45 or sc == 0x47) 13 else 9;
        if (vars.link_item_moon_pearl.* == 0)
            xt = 4;
    }
    vars.queued_music_control.* = xt;

    load_gfx.DecompressAnimatedOverworldTiles(ow_anim_tiles);
    load_gfx.InitializeTilesets();
    load_gfx.OverworldLoadScreensPaletteSet();
    load_gfx.Overworld_LoadPalettes(kOverworldBgPalettes()[sc], vars.overworld_sprite_palettes[sc]);
    load_gfx.Palette_SetOwBgColor();
    if (vars.main_module_index.* == 8) {
        load_gfx.Overworld_LoadPalettesInner();
    } else {
        load_gfx.SpecialOverworld_CopyPalettesToCache();
    }
    Overworld_SetFixedColAndScroll();
    vars.overworld_fixed_color_plusminus.* = 0;
    tagalong.Follower_Initialize();

    if (loPtr(vars.overworld_screen_index).* & 0x3f == 0)
        load_gfx.DecodeAnimatedSpriteTile_variable(0x1e);
    vars.saved_module_for_menu.* = 9;
    Sprite_ReloadAll_Overworld();
    if (vars.overworld_screen_index.* & 0x40 == 0)
        Sprite_InitializeMirrorPortal();
    vars.sound_effect_ambient.* = if (vars.sram_progress_indicator.* < 2) 1 else 5;
    if (vars.follower_indicator.* == 6)
        vars.follower_indicator.* = 0;

    vars.is_standing_in_doorway.* = 0;
    vars.button_mask_b_y.* = 0;
    vars.button_b_frames.* = 0;
    vars.link_cant_change_direction.* = 0;
    vars.link_speed_setting.* = 0;
    vars.draw_water_ripples_or_grass.* = 0;
    Dungeon_ResetTorchBackgroundAndPlayerInner();
    if (vars.link_item_moon_pearl.* == 0 and vars.savegame_is_darkworld.* != 0) {
        vars.link_is_bunny.* = 1;
        vars.link_is_bunny_mirror.* = 1;
        vars.link_player_handler_state.* = kPlayerState_PermaBunny;
        load_gfx.LoadGearPalettes_bunny();
    }
    vars.BGMODE_copy.* = 9;
    vars.dung_want_lights_out.* = 0;
    vars.dung_hdr_collision.* = 0;
    vars.link_is_on_lower_level.* = 0;
    vars.link_is_on_lower_level_mirror.* = 0;
    vars.submodule_index.* +%= 1;
    vars.flag_update_hud_in_nmi.* +%= 1;
    vars.dung_savegame_state_bits.* = 0;
    LoadOWMusicIfNeeded();
}

pub export fn AdjustLinkBunnyStatus() callconv(.c) void {
    if (vars.link_item_moon_pearl.* != 0)
        ForceNonbunnyStatus();
}

pub export fn ForceNonbunnyStatus() callconv(.c) void {
    vars.link_player_handler_state.* = kPlayerState_Ground;
    vars.link_timer_tempbunny.* = 0;
    vars.link_need_for_poof_for_transform.* = 0;
    vars.link_is_bunny.* = 0;
    vars.link_is_bunny_mirror.* = 0;

    if (features.enhanced_features0.* & features.kFeatures0_TurnWhileDashing != 0)
        vars.link_is_running.* = 0;
}

pub export fn RecoverPositionAfterDrowning() callconv(.c) void {
    vars.link_x_coord.* = vars.link_x_coord_cached.*;
    vars.link_y_coord.* = vars.link_y_coord_cached.*;
    vars.ow_scroll_vars0.ystart = vars.room_scroll_vars_y_vofs1_cached.*;
    vars.ow_scroll_vars0.xstart = vars.room_scroll_vars_y_vofs2_cached.*;
    vars.ow_scroll_vars1.ystart = vars.room_scroll_vars_x_vofs1_cached.*;
    vars.ow_scroll_vars1.xstart = vars.room_scroll_vars_x_vofs2_cached.*;

    vars.up_down_scroll_target.* = vars.up_down_scroll_target_cached.*;
    vars.up_down_scroll_target_end.* = vars.up_down_scroll_target_end_cached.*;
    vars.left_right_scroll_target.* = vars.left_right_scroll_target_cached.*;
    vars.left_right_scroll_target_end.* = vars.left_right_scroll_target_end_cached.*;

    if (vars.player_is_indoors.* != 0) {
        vars.camera_y_coord_scroll_low.* = vars.camera_y_coord_scroll_low_cached.*;
        vars.camera_y_coord_scroll_hi.* = vars.camera_y_coord_scroll_low.* +% 2;
        vars.camera_x_coord_scroll_low.* = vars.camera_x_coord_scroll_low_cached.*;
        vars.camera_x_coord_scroll_hi.* = vars.camera_x_coord_scroll_low.* +% 2;
    }
    wordPtr(vars.quadrant_fullsize_x).* = wordPtr(vars.quadrant_fullsize_x_cached).*;
    wordPtr(vars.link_quadrant_x).* = wordPtr(vars.link_quadrant_x_cached).*;
    if (vars.player_is_indoors.* == 0) {
        vars.camera_y_coord_scroll_hi.* = vars.camera_y_coord_scroll_low.* -% 2;
        vars.camera_x_coord_scroll_hi.* = vars.camera_x_coord_scroll_low.* -% 2;
    }

    vars.link_direction_facing.* = vars.link_direction_facing_cached.*;
    vars.link_is_on_lower_level.* = vars.link_is_on_lower_level_cached.*;
    vars.link_is_on_lower_level_mirror.* = vars.link_is_on_lower_level_mirror_cached.*;
    vars.is_standing_in_doorway.* = vars.is_standing_in_doorway_cahed.*;
    vars.dung_cur_floor.* = vars.dung_cur_floor_cached.*;
    vars.link_visibility_status.* = 0;
    vars.countdown_for_blink.* = 0x90;
    Dungeon_PlayBlipAndCacheQuadrantVisits();
    vars.link_disable_sprite_damage.* = 0;
    Link_ResetStateAfterDamagingPit();
    vars.tagalong_var5.* = 0;
    tagalong.Follower_Initialize();
    vars.dung_flag_statechange_waterpuzzle.* = 0;
    vars.overworld_map_state.* = 0;
    vars.subsubmodule_index.* = 0;
    vars.overworld_screen_transition.* = 0;
    vars.submodule_index.* = 0;
    if (vars.link_health_current.* == 0) {
        vars.mapbak_TM.* = vars.TM_copy.*;
        vars.mapbak_TS.* = vars.TS_copy.*;
        vars.saved_module_for_menu.* = vars.main_module_index.*;
        vars.main_module_index.* = 18;
        vars.submodule_index.* = 1;
        vars.countdown_for_blink.* = 0;
    }
}

pub export fn Module0F_SpotlightClose() callconv(.c) void {
    Sprite_Main();
    if (vars.submodule_index.* == 0) {
        Dungeon_PrepExitWithSpotlight();
    } else {
        Spotlight_ConfigureTableAndControl();
    }

    if (vars.player_is_indoors.* == 0) {
        if (loPtr(vars.overworld_screen_index).* == 0xf)
            vars.draw_water_ripples_or_grass.* = 1;
        vars.link_speed_setting.* = 6;
        Link_HandleVelocity();
        vars.link_x_vel.* = 0;
        vars.link_y_vel.* = 0;
    }

    var i: usize = vars.link_direction_facing.* >> 1;
    if (vars.player_is_indoors.* == 0)
        i = if (vars.which_entrance.* == 0x43) 1 else 0;

    vars.link_direction.* = tables.kTab[i];
    vars.link_direction_last.* = tables.kTab[i];
    Link_HandleMovingAnimation_FullLongEntry();
    player_oam.LinkOam_Main();
}

pub export fn Dungeon_PrepExitWithSpotlight() callconv(.c) void {
    vars.is_nmi_thread_active.* = 0;
    vars.nmi_flag_update_polyhedral.* = 0;
    if (vars.player_is_indoors.* == 0) {
        Ancilla_TerminateWaterfallSplashes();
        vars.link_y_coord_exit.* = vars.link_y_coord.*;
    }
    var m = audio.ZeldaGetEntranceMusicTrack(vars.which_entrance.*);
    if (m != 3 or blk: {
        m = vars.sram_progress_indicator.*;
        break :blk m >= 2;
    }) {
        if (m != 0xf2) { // fade to 0x40
            m = 0xf1; // fade to zero
        } else if (vars.music_unk1.* == 12) {
            m = 7;
        }
        vars.music_control.* = m;
    }
    vars.hud_floor_changed_timer.* = 0;
    hud.Hud_FloorIndicator();
    vars.flag_update_hud_in_nmi.* +%= 1;
    load_gfx.IrisSpotlight_close();
    vars.submodule_index.* +%= 1;
}

pub export fn Spotlight_ConfigureTableAndControl() callconv(.c) void {
    load_gfx.IrisSpotlight_ConfigureTable();
    vars.is_nmi_thread_active.* = 0;
    vars.nmi_flag_update_polyhedral.* = 0;
    if (vars.submodule_index.* != 0) return;
    if (vars.main_module_index.* == 6)
        vars.link_y_coord.* = vars.link_y_coord_exit.*;
    OpenSpotlight_Next2();
}

pub export fn OpenSpotlight_Next2() callconv(.c) void {
    if (vars.main_module_index.* != 9) {
        load_gfx.EnableForceBlank();
        Link_ItemReset_FromOverworldThings();
    }

    if (vars.main_module_index.* == 9) {
        if (vars.dungeon_room_index.* != 0x20)
            vars.submodule_index.* = if (vars.link_direction_facing.* != 0) 0xa else 0xb;

        vars.ow_countdown_transition.* = 16;
        // wtf
        if ((loPtr(vars.ow_entrance_value).* | loPtr(vars.big_rock_starting_address).*) != 0 and
            hiPtr(vars.big_rock_starting_address).* != 0)
        {
            loPtr(vars.door_open_closed_counter).* =
                if (vars.big_rock_starting_address.* & 0x8000 != 0) 0x18 else 0;
            vars.big_rock_starting_address.* &= 0x7fff;
            loPtr(vars.door_animation_step_indicator).* = 0;
            vars.submodule_index.* = 9;
            vars.subsubmodule_index.* = 0;
            vars.sound_effect_2.* = 21;
        }
    }
    vars.W12SEL_copy.* = 0;
    vars.W34SEL_copy.* = 0;
    vars.WOBJSEL_copy.* = 0;
    vars.TMW_copy.* = 0;
    vars.TSW_copy.* = 0;
    vars.link_force_hold_sword_up.* = 0;

    const sc: u8 = @truncate(vars.overworld_screen_index.*);
    if (sc == 3 or sc == 5 or sc == 7) {
        vars.COLDATA_copy0.* = 0x26;
        vars.COLDATA_copy1.* = 0x4c;
        vars.COLDATA_copy2.* = 0x8c;
    } else if (sc == 0x43 or sc == 0x45 or sc == 0x47) {
        vars.COLDATA_copy0.* = 0x26;
        vars.COLDATA_copy1.* = 0x4a;
        vars.COLDATA_copy2.* = 0x87;
    }
}

pub export fn Module10_SpotlightOpen() callconv(.c) void {
    Sprite_Main();
    if (vars.submodule_index.* == 0) {
        Module10_00_OpenIris();
    } else {
        Spotlight_ConfigureTableAndControl();
    }
    player_oam.LinkOam_Main();
}

pub export fn Module10_00_OpenIris() callconv(.c) void {
    load_gfx.Spotlight_open();
    vars.submodule_index.* +%= 1;
}

pub export fn SetTargetOverworldWarpToPyramid() callconv(.c) void {
    if (vars.main_module_index.* != 21) return;
    LoadOverworldFromDungeon();
    load_gfx.DecompressAnimatedOverworldTiles(0x5a);
    ResetAncillaAndCutscene();
}

pub export fn ResetAncillaAndCutscene() callconv(.c) void {
    _ = Ancilla_TerminateSelectInteractives(0);
    vars.link_disable_sprite_damage.* = 0;
    vars.button_b_frames.* = 0;
    vars.button_mask_b_y.* = 0;
    vars.link_force_hold_sword_up.* = 0;
    vars.flag_is_link_immobilized.* = 0;
}

pub export fn Module09_Overworld() callconv(.c) void {
    kOverworldSubmodules[vars.submodule_index.*]();

    const bg2x = vars.BG2HOFS_copy2.*;
    const bg2y = vars.BG2VOFS_copy2.*;
    const bg1x = vars.BG1HOFS_copy2.*;
    const bg1y = vars.BG1VOFS_copy2.*;

    vars.BG2HOFS_copy.* = bg2x +% vars.bg1_x_offset.*;
    vars.BG2HOFS_copy2.* = vars.BG2HOFS_copy.*;
    vars.BG2VOFS_copy.* = bg2y +% vars.bg1_y_offset.*;
    vars.BG2VOFS_copy2.* = vars.BG2VOFS_copy.*;
    vars.BG1HOFS_copy.* = bg1x +% vars.bg1_x_offset.*;
    vars.BG1HOFS_copy2.* = vars.BG1HOFS_copy.*;
    vars.BG1VOFS_copy.* = bg1y +% vars.bg1_y_offset.*;
    vars.BG1VOFS_copy2.* = vars.BG1VOFS_copy.*;

    Sprite_Main();

    vars.BG2HOFS_copy2.* = bg2x;
    vars.BG2VOFS_copy2.* = bg2y;
    vars.BG1HOFS_copy2.* = bg1x;
    vars.BG1VOFS_copy2.* = bg1y;

    player_oam.LinkOam_Main();
    hud.Hud_RefillLogic();
    OverworldOverlay_HandleRain();
}

pub export fn OverworldOverlay_HandleRain() callconv(.c) void {
    if ((loPtr(vars.overworld_screen_index).* != 0x70 and vars.sram_progress_indicator.* >= 2) or
        (vars.save_ow_event_info[0x70] & 0x20) != 0)
        return;
    const fc = vars.frame_counter.*;
    if (fc == 3 or fc == 88) {
        vars.CGADSUB_copy.* = 0x32;
    } else if (fc == 5 or fc == 44 or fc == 90) {
        vars.CGADSUB_copy.* = 0x72;
    } else if (fc == 36) {
        vars.sound_effect_1.* = 54;
        vars.CGADSUB_copy.* = 0x32;
    }
    if (fc & 3 != 0) return;
    const i: usize = (vars.move_overlay_ctr.* +% 1) & 3;
    vars.move_overlay_ctr.* = @intCast(i);
    vars.BG1HOFS_copy2.* +%= @as(u16, tables.kOverworld_DrawBadWeather_X[i]) << 8;
    vars.BG1VOFS_copy2.* +%= @as(u16, tables.kOverworld_DrawBadWeather_Y[i]) << 8;
}

pub export fn Module09_00_PlayerControl() callconv(.c) void {
    if ((vars.flag_custom_spell_anim_active.* | vars.flag_is_link_immobilized.* |
        vars.flag_block_link_menu.* | vars.trigger_special_entrance.*) == 0)
    {
        if (vars.filtered_joypad_H.* & 0x10 != 0) {
            vars.overworld_map_state.* = 0;
            vars.submodule_index.* = 1;
            vars.saved_module_for_menu.* = vars.main_module_index.*;
            vars.main_module_index.* = 14;
            return;
        }

        if (messaging.DidPressButtonForMap()) {
            vars.overworld_map_state.* = 0;
            vars.submodule_index.* = 7;
            vars.saved_module_for_menu.* = vars.main_module_index.*;
            vars.main_module_index.* = 14;
            return;
        }
        if (vars.joypad1H_last.* & 0x20 != 0) {
            messaging.DisplaySelectMenu();
            return;
        }
        hud.Hud_HandleItemSwitchInputs();
    }
    if (vars.trigger_special_entrance.* != 0)
        Overworld_AnimateEntrance();
    Link_Main();
    if (vars.super_bomb_indicator_unk2.* != 0xff)
        hud.Hud_SuperBombIndicator();
    vars.current_area_of_player.* = (vars.link_y_coord.* & 0x1e00) >> 5 |
        (vars.link_x_coord.* & 0x1e00) >> 8;
    load_gfx.Graphics_LoadChrHalfSlot();
    Overworld_OperateCameraScroll();
    if (vars.main_module_index.* != 11) {
        Overworld_UseEntrance();
        Overworld_DwDeathMountainPaletteAnimation();
        OverworldHandleTransitions();
    } else {
        ScrollAndCheckForSOWExit();
    }
}

pub export fn OverworldHandleTransitions() callconv(.c) void {
    if (loPtr(vars.overworld_screen_trans_dir_bits2).* != 0)
        OverworldHandleMapScroll();

    var dir: u16 = 0;
    var x: u16 = 0;
    var y: u16 = 0;
    var t: u16 = 0;
    const area: usize = loPtr(vars.current_area_of_player).* >> 1;

    // The C's comma expressions assign x and y even when the test fails.
    var compare = false;
    if (vars.link_y_vel.* != 0) {
        dir = vars.link_direction.* & 12;
        t = vars.link_y_coord.* -% tables.kOverworld_OffsetBaseY[area];
        y = 6;
        x = 8;
        if (t < 4) {
            compare = true;
        } else {
            y = 4;
            x = 4;
            if (t >= vars.overworld_right_bottom_bound_for_scroll.*) compare = true;
        }
    }
    if (!compare and vars.link_x_vel.* != 0) {
        dir = vars.link_direction.* & 3;
        t = vars.link_x_coord.* -% tables.kOverworld_OffsetBaseX[area];
        y = 2;
        x = 2;
        if (t < 6) {
            compare = true;
        } else {
            y = 0;
            x = 1;
            if (t >= vars.overworld_right_bottom_bound_for_scroll.* +% 4) compare = true;
        }
    }
    if (!(compare and x == dir and !Link_CheckForEdgeScreenTransition())) {
        Overworld_CheckSpecialSwitchArea();
        return;
    }

    // after:
    y >>= 1;
    Dungeon_ResetTorchBackgroundAndPlayerInner();
    vars.map16_load_src_off.* &= @bitCast(tables.kSwitchAreaTab0[y]);
    const pushed: usize = @intCast(((@as(i32, @intCast(vars.current_area_of_player.*)) +
        tables.kSwitchAreaTab3[y]) >> 1) & 0x3f);
    vars.map16_load_src_off.* +%= @bitCast(tables.kSwitchAreaTab1[@as(usize, y) * 64 + pushed]);

    const old_screen: u8 = @truncate(vars.overworld_screen_index.*);
    if (old_screen == 0x2a)
        vars.sound_effect_ambient.* = 0x80;

    const new_area = tables.kOverworldAreaHeads[pushed] | vars.savegame_is_darkworld.*;
    loPtr(vars.overworld_screen_index).* = new_area;
    loPtr(vars.overworld_area_index).* = new_area;
    if (vars.savegame_is_darkworld.* == 0 or vars.link_item_moon_pearl.* != 0) {
        const music = vars.overworld_music[new_area];
        if (music & 0xf0 == 0)
            vars.sound_effect_ambient.* = 5;
        if (!audio.ZeldaIsPlayingMusicTrack(music & 0xf))
            vars.music_control.* = 0xf1;
    }
    Overworld_LoadGFXAndScreenSize();
    vars.submodule_index.* = 1;
    loPtr(vars.overworld_screen_trans_dir_bits).* = @truncate(dir);
    loPtr(vars.overworld_screen_trans_dir_bits2).* = @truncate(dir);
    vars.overworld_screen_transition.* = @intCast(DirToEnum(@intCast(dir)));
    vars.byte_7E069C.* = vars.overworld_screen_transition.*;
    loPtr(vars.ow_entrance_value).* = 0;
    loPtr(vars.big_rock_starting_address).* = 0;
    vars.transition_counter.* = 0;

    if (old_screen & 0x3f == 0 or vars.overworld_screen_index.* & 0xbf == 0) {
        vars.subsubmodule_index.* = 0;
        vars.submodule_index.* = 13;
        vars.MOSAIC_copy.* = 0;
        vars.mosaic_level.* = 0;
    } else {
        const sc: u8 = @truncate(vars.overworld_screen_index.*);
        load_gfx.Overworld_LoadPalettes(kOverworldBgPalettes()[sc], vars.overworld_sprite_palettes[sc]);
        load_gfx.Overworld_CopyPalettesToCache();
    }
}

/// The overworld area's base offset, or null for an index the table does not
/// cover.
///
/// The screen index is masked with 0xbf, which clears bit 6 but keeps bit 7, so
/// a special area (screen index 0x80 and up) indexes past this 64-entry table.
/// The C reads whatever static data follows it; the value is dead either way,
/// because Overworld_EnterSpecialArea overwrites both offsets from the
/// kSpExit_* tables as soon as LoadOverworldFromDungeon returns. Leaving them
/// untouched keeps that outcome without reading out of bounds.
const OverworldOffsetBase = struct { y: u16, x: u16 };

fn overworldOffsetBase(j: usize) ?OverworldOffsetBase {
    if (j >= tables.kOverworld_OffsetBaseY.len) return null;
    return .{
        .y = tables.kOverworld_OffsetBaseY[j],
        .x = tables.kOverworld_OffsetBaseX[j] >> 3,
    };
}

pub export fn Overworld_LoadGFXAndScreenSize() callconv(.c) void {
    const i: usize = loPtr(vars.overworld_screen_index).*;
    vars.incremental_counter_for_vram.* = 0;
    vars.sprite_graphics_index.* = vars.overworld_sprite_gfx[i];
    vars.aux_tile_theme_index.* = kOverworldAuxTileThemeIndexes()[i];

    vars.overworld_area_is_big_backup.* = @truncate(vars.overworld_area_is_big.*);
    const small = kOverworldMapIsSmall()[i & 0x3f] != 0;
    loPtr(vars.overworld_area_is_big).* = if (small) 0 else 0x20;
    hiPtr(vars.overworld_right_bottom_bound_for_scroll).* = if (small) 1 else 3;
    vars.main_tile_theme_index.* = if (vars.overworld_screen_index.* & 0x40 != 0) 0x21 else 0x20;
    vars.misc_sprites_graphics_index.* =
        tables.kVariousPacks[6 + @as(usize, if (vars.overworld_screen_index.* & 0x40 != 0) 8 else 0)];

    const j: usize = vars.overworld_screen_index.* & 0xbf;
    if (overworldOffsetBase(j)) |base| {
        vars.overworld_offset_base_y.* = base.y;
        vars.overworld_offset_base_x.* = base.x;
    }

    const m: u16 = if (vars.overworld_area_is_big.* != 0) 0x3f0 else 0x1f0;
    vars.overworld_offset_mask_y.* = m;
    vars.overworld_offset_mask_x.* = m >> 3;
}

pub export fn ScrollAndCheckForSOWExit() callconv(.c) void {
    if (loPtr(vars.overworld_screen_trans_dir_bits2).* != 0)
        OverworldHandleMapScroll();

    const map8 = Overworld_GetMap16OfLink_Mult8();
    const a = map8[0] & 0x1ff;
    var i: i32 = 2;
    while (i >= 0) : (i -= 1) {
        const ii: usize = @intCast(i);
        if (tables.kSpecialSwitchAreaB_Map8[ii] == a and
            tables.kSpecialSwitchAreaB_Screen[ii] == vars.overworld_screen_index.*)
        {
            vars.link_direction.* = @truncate(tables.kSpecialSwitchAreaB_Direction[ii]);
            vars.overworld_screen_transition.* = @intCast(DirToEnum(vars.link_direction.*));
            vars.byte_7E069C.* = vars.overworld_screen_transition.*;
            vars.submodule_index.* = 36;
            vars.subsubmodule_index.* = 0;
            loPtr(vars.dungeon_room_index).* = 0;
            break;
        }
    }
}

pub export fn Module09_LoadAuxGFX() callconv(.c) void {
    vars.save_ow_event_info[0x3b] &= ~@as(u8, 0x20);
    vars.save_ow_event_info[0x7b] &= ~@as(u8, 0x20);
    vars.save_dung_info[267] &= ~@as(u16, 0x80);
    vars.save_dung_info[40] &= ~@as(u16, 0x100);
    load_gfx.LoadTransAuxGFX();
    load_gfx.PrepTransAuxGfx();
    vars.nmi_subroutine_index.* = 9;
    vars.nmi_disable_core_updates.* = 9;
    vars.submodule_index.* +%= 1;
}

pub export fn Overworld_FinishTransGfx() callconv(.c) void {
    vars.nmi_subroutine_index.* = 10;
    vars.nmi_disable_core_updates.* = 10;
    vars.submodule_index.* +%= 1;
}

pub export fn Module09_LoadNewMapAndGFX() callconv(.c) void {
    vars.word_7E04C8.* = 0;
    SomeTileMapChange();
    vars.nmi_disable_core_updates.* +%= 1;
    CreateInitialNewScreenMapToScroll();
    load_gfx.LoadNewSpriteGFXSet();
}

pub export fn Overworld_RunScrollTransition() callconv(.c) void {
    Link_HandleMovingAnimation_FullLongEntry();
    load_gfx.Graphics_IncrementalVRAMUpload();
    // A new column of map loads each time the scroll moves 16 pixels. The
    // original checks for the camera landing on a multiple of 16, which it
    // always does, starting from an area's edge; the widescreen camera starts
    // a margin in, and never lands on one, so there it's crossing one.
    const sideways = vars.overworld_screen_transition.* >= 2;
    const before = vars.BG2HOFS_copy2.*;
    const rv: u8 = @truncate(@as(u32, @bitCast(OverworldScrollTransition())));
    const wide = sideways and wideCameraOn();
    g_wide_sideways_scroll = wide;
    const load = if (wide)
        before >> 4 != vars.BG2HOFS_copy2.* >> 4 and wideColumnDue(before)
    else
        rv & 0xf == 0;
    if (wide and load) g_wide_stripes += 1;
    if (load) {
        loPtr(vars.overworld_screen_trans_dir_bits2).* = loPtr(vars.overworld_screen_trans_dir_bits).*;
        OverworldTransitionScrollAndLoadMap();
        loPtr(vars.overworld_screen_trans_dir_bits2).* = 0;
    }
}

pub export fn Module09_LoadNewSprites() callconv(.c) void {
    if (vars.overworld_screen_transition.* == 1) {
        vars.BG2VOFS_copy2.* +%= 2;
        vars.link_y_coord.* +%= 2;
    }
    Sprite_OverworldReloadAll_justLoad();
    vars.num_memorized_tiles.* = 0;
    if (vars.sram_progress_indicator.* >= 2 and vars.submodule_index.* != 18)
        Overworld_SetFixedColAndScroll();
    Overworld_StartScrollTransition();
}

pub export fn Overworld_StartScrollTransition() callconv(.c) void {
    vars.submodule_index.* +%= 1;
    if (loPtr(vars.overworld_screen_trans_dir_bits).* >= 4) {
        loPtr(vars.overworld_screen_trans_dir_bits2).* = loPtr(vars.overworld_screen_trans_dir_bits).*;
        OverworldTransitionScrollAndLoadMap();
        loPtr(vars.overworld_screen_trans_dir_bits2).* = 0;
    }
}

/// Whether the widescreen scroll loads a column at this 16-pixel crossing.
/// The load that follows each column along the map is one column further
/// on, not the one the camera's reached: a scroll loads as many as it
/// crosses, and after that walking loads one per 16 pixels, each a set
/// distance ahead of where the last one went. So a scroll that stops a
/// margin in should have loaded as far as the camera got, a margin's worth of
/// columns past the original's 16 and no more. The longer scroll crosses
/// more, and loading at every one runs ahead of the camera: the map's only
/// 32 columns wide and wraps, so the column that gets furthest ahead lands
/// on the one at the screen's other edge, and stays there as walking keeps
/// it ahead. The crossings that don't load are the first, while the old area
/// is still on screen and the columns loaded as the scroll started are ahead.
fn wideColumnDue(before: u16) bool {
    const y: usize = vars.overworld_screen_transition.*;
    const target = wideScrollTarget(y);
    const left: u16 = if (tables.kOverworld_Func6B_Tab1[y] > 0)
        (target >> 4) -% (before >> 4)
    else
        (before >> 4) -% (target >> 4);
    return left <= kScrollStripes + (wideScrollMargin() >> 4) + g_wide_held_columns;
}

/// Columns held back from what loads before a scroll, for the scroll to load.
var g_wide_held_columns: u32 = 0;

/// Map columns the widescreen camera's longer scroll loaded, counted so the
/// columns a small area loads once the scroll's over can leave out as many:
/// they've been loaded, and loading on past the area would wrap round the
/// 512-pixel map onto what's on screen.
var g_wide_stripes: u32 = 0;
/// Columns the original scroll loads: one each 16 pixels of 256.
const kScrollStripes = 16;

pub export fn Overworld_EaseOffScrollTransition() callconv(.c) void {
    const skip = g_wide_stripes > kScrollStripes + g_wide_held_columns;
    if (skip) g_wide_stripes -= 1;
    if (!skip and kOverworldMapIsSmall()[loPtr(vars.overworld_screen_index).*] != 0) {
        loPtr(vars.overworld_screen_trans_dir_bits2).* = loPtr(vars.overworld_screen_trans_dir_bits).*;
        OverworldTransitionScrollAndLoadMap();
        loPtr(vars.overworld_screen_trans_dir_bits2).* = 0;
    }
    vars.subsubmodule_index.* +%= 1;
    if (vars.subsubmodule_index.* < 8) return;
    const d = loPtr(vars.overworld_screen_trans_dir_bits).*;
    if ((d == 8 or d == 2) and vars.subsubmodule_index.* < 9) return;

    const wide_side = g_wide_sideways_scroll;
    vars.subsubmodule_index.* = 0;
    loPtr(vars.overworld_screen_trans_dir_bits).* = 0;
    g_wide_stripes = 0;
    g_wide_held_columns = 0;
    g_wide_sideways_scroll = false;

    if (kOverworldMapIsSmall()[loPtr(vars.overworld_screen_index).*] != 0) {
        vars.map16_load_src_off.* = vars.orange_blue_barrier_state.*;
        vars.map16_load_dst_off.* = vars.word_7EC174.*;
        vars.map16_load_var2.* = vars.word_7EC176.*;
        // Those are where the column loads stand with the camera at the 4:3
        // landing, and the widescreen camera's a margin further on. A small
        // area never loads while walking, so here it wouldn't show, but a
        // scroll up or down keeps the column, and a big area there would
        // load its columns that far off the camera: far enough to wrap round
        // the map onto the other edge of the screen.
        if (wide_side) {
            const k: u16 = wideScrollMargin() >> 4;
            if (d == 1) {
                vars.map16_load_src_off.* +%= 2 * k;
                vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* +% k) & 0x1f;
            } else {
                vars.map16_load_src_off.* -%= 2 * k;
                vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* -% k) & 0x1f;
            }
        }
    }
    vars.submodule_index.* +%= 1;
    tagalong.Follower_Disable();
}

pub export fn Module09_0A_WalkFromExiting_FacingDown() callconv(.c) void {
    vars.link_direction_last.* = 4;
    Link_HandleMovingAnimation_FullLongEntry();
    vars.link_y_coord.* +%= 1;
    vars.ow_countdown_transition.* -%= 1;
    if (vars.ow_countdown_transition.* != 0) return;
    vars.submodule_index.* = 0;
    vars.link_y_coord.* +%= 3;
    vars.link_y_vel.* = 3;
    Overworld_OperateCameraScroll();
    if (loPtr(vars.overworld_screen_trans_dir_bits2).* != 0)
        OverworldHandleMapScroll();
}

pub export fn Module09_0B_WalkFromExiting_FacingUp() callconv(.c) void {
    Link_HandleMovingAnimation_FullLongEntry();
    vars.link_y_coord.* -%= 1;
    vars.ow_countdown_transition.* -%= 1;
    if (vars.ow_countdown_transition.* != 0) return;
    vars.submodule_index.* = 0;
}

pub export fn Module09_09_OpenBigDoorFromExiting() callconv(.c) void {
    if (loPtr(vars.door_animation_step_indicator).* != 3) {
        Overworld_DoMapUpdate32x32_conditional();
        return;
    }
    vars.ow_countdown_transition.* = 36;
    loPtr(vars.overworld_screen_trans_dir_bits2).* = 0;
    vars.submodule_index.* +%= 1;
}

pub export fn Overworld_DoMapUpdate32x32_B() callconv(.c) void {
    Overworld_DoMapUpdate32x32();
    loPtr(vars.door_open_closed_counter).* = 0;
}

pub export fn Module09_0C_OpenBigDoor() callconv(.c) void {
    if (loPtr(vars.door_animation_step_indicator).* != 3) {
        Overworld_DoMapUpdate32x32_conditional();
        return;
    }
    vars.submodule_index.* = 0;
    vars.subsubmodule_index.* = 0;
    loPtr(vars.overworld_screen_trans_dir_bits2).* = 0;
}

pub export fn Overworld_DoMapUpdate32x32_conditional() callconv(.c) void {
    if (vars.door_open_closed_counter.* & 7 != 0) {
        loPtr(vars.door_open_closed_counter).* +%= 1;
    } else {
        Overworld_DoMapUpdate32x32();
    }
}

pub export fn Overworld_DoMapUpdate32x32() callconv(.c) void {
    const i: usize = vars.num_memorized_tiles.* >> 1;
    const j: usize = vars.door_open_closed_counter.* >> 1;

    const offsets = [4]u16{ 0, 2, 0x80, 0x82 };
    var n: usize = 0;
    while (n < 4) : (n += 1) {
        const pos = vars.big_rock_starting_address.* +% offsets[n];
        const tile = tables.kDoorAnimTiles[j + n];
        vars.memorized_tile_addr[i + n] = pos;
        vars.memorized_tile_value[i + n] = tile;
        Overworld_DrawMap16_Persist(pos, tile);
    }
    vars.vram_upload_data[vars.vram_upload_offset.* >> 1] = 0xffff;
    vars.num_memorized_tiles.* +%= 8;
    vars.door_animation_step_indicator.* +%= if (vars.door_open_closed_counter.* == 32) 2 else 1;
    vars.nmi_load_bg_from_vram.* = 1;
    loPtr(vars.door_open_closed_counter).* +%= 1;
}

pub export fn Overworld_StartMosaicTransition() callconv(.c) void {
    ConditionalMosaicControl();
    switch (vars.subsubmodule_index.*) {
        0 => {
            if (loPtr(vars.overworld_screen_index).* != 0x80) {
                if (!audio.ZeldaIsPlayingMusicTrack(
                    vars.overworld_music[loPtr(vars.overworld_screen_index).*] & 0xf,
                ))
                    vars.music_control.* = 0xf1;
            }
            ResetTransitionPropsAndAdvance_ResetInterface();
        },
        1 => load_gfx.ApplyPaletteFilter_bounce(),
        else => {
            vars.INIDISP_copy.* = 0x80;
            vars.subsubmodule_index.* = 0;
            if (vars.overworld_screen_index.* & 0x3f == 0)
                load_gfx.DecodeAnimatedSpriteTile_variable(0x1e);
            if (loPtr(vars.overworld_area_index).* != 0 and vars.main_module_index.* != 11) {
                vars.TM_copy.* = 0x16;
                vars.TS_copy.* = 1;
                vars.CGWSEL_copy.* = 0x82;
                vars.CGADSUB_copy.* = 0x20;
                vars.submodule_index.* +%= 1;
                return;
            }
            if (vars.submodule_index.* == 36) {
                LoadOverworldFromSpecialOverworld();
                if (vars.overworld_screen_index.* & 0x3f == 0)
                    load_gfx.DecodeAnimatedSpriteTile_variable(0x1e);
            }
            vars.submodule_index.* +%= 1;
        },
    }
}

pub export fn Overworld_LoadOverlays() callconv(.c) void {
    Sprite_InitializeSlots();
    Sprite_ReloadAll_Overworld();
    vars.link_state_bits.* = 0;
    vars.link_picking_throw_state.* = 0;
    vars.sound_effect_ambient.* = 5;
    Overworld_LoadOverlays2();
}

pub export fn PreOverworld_LoadOverlays() callconv(.c) void {
    vars.sound_effect_ambient.* = 5;
    Overworld_LoadOverlays2();
}

pub export fn Overworld_LoadOverlays2() callconv(.c) void {
    vars.overworld_screen_index_prev.* = vars.overworld_screen_index.*;
    vars.map16_load_src_off_prev.* = vars.map16_load_src_off.*;
    vars.map16_load_var2_prev.* = vars.map16_load_var2.*;
    vars.map16_load_dst_off_prev.* = vars.map16_load_dst_off.*;
    vars.overworld_screen_transition_prev.* = vars.overworld_screen_transition.*;
    vars.overworld_screen_trans_dir_bits_prev.* = vars.overworld_screen_trans_dir_bits.*;
    vars.overworld_screen_trans_dir_bits2_prev.* = vars.overworld_screen_trans_dir_bits2.*;

    vars.overlay_index.* = 0;
    vars.BG1VOFS_subpixel.* = 0;
    vars.BG1HOFS_subpixel.* = 0;

    const si = vars.overworld_screen_index.*;
    var xv: u16 = 0;
    var getout = false;

    // The comma expressions assign xv even when their test fails, so for screen
    // 0x70 with the event bit already set xv keeps 0x9c from the previous test.
    head: {
        if (si >= 0x80) {
            xv = 0x97;
            if (vars.dungeon_room_index.* == 0x180) {
                if (vars.save_ow_event_info[0x80] & 0x40 != 0) getout = true; // master sword retrieved?
                break :head;
            }
            xv = 0x94;
            if (vars.dungeon_room_index.* == 0x181) break :head;
            xv = 0x93;
            if (vars.dungeon_room_index.* == 0x189) break :head;
            if (vars.dungeon_room_index.* == 0x182 or vars.dungeon_room_index.* == 0x183)
                vars.sound_effect_ambient.* = 1; // zora falls
            getout = true;
            break :head;
        }
        if (si & 0x3f == 0) {
            xv = if (si & 0x40 == 0 and vars.save_ow_event_info[0x80] & 0x40 != 0) 0x9e else 0x9d; // forest
            break :head;
        }
        xv = 0x95;
        if (si == 0x3 or si == 0x5 or si == 0x7) break :head;
        xv = 0x9c;
        if (si == 0x43 or si == 0x45 or si == 0x47) break :head;
        if (si == 0x70) {
            if (vars.save_ow_event_info[0x70] & 0x20 == 0)
                xv = 0x9f; // rain
        } else {
            xv = if (vars.sram_progress_indicator.* < 2) 0x9f else 0x96;
        }
    }
    if (getout) {
        vars.TS_copy.* = 0;
        vars.submodule_index.* +%= 1;
        return;
    }

    // load_overlay:
    vars.map16_load_src_off.* = 0x390;
    vars.overworld_screen_index.* = xv;
    vars.overlay_index.* = xv;
    vars.map16_load_var2.* = (vars.map16_load_src_off.* -% 0x400 & 0xf80) >> 7;
    vars.map16_load_dst_off.* = (vars.map16_load_src_off.* -% 0x10 & 0x3e) >> 1;
    vars.overworld_screen_transition.* = 0;
    vars.overworld_screen_trans_dir_bits.* = 0;
    vars.overworld_screen_trans_dir_bits2.* = 0;
    vars.CGWSEL_copy.* = 0x82;
    vars.TM_copy.* = 0x16;
    vars.TS_copy.* = 1;
    vars.sound_effect_ambient.* = vars.overworld_music[loPtr(vars.overworld_screen_index).*] >> 4;

    const prev = loPtr(vars.overworld_screen_index_prev).*;
    if (xv == 0x97 or xv == 0x94 or xv == 0x93 or xv == 0x9d or xv == 0x9e or xv == 0x9f) {
        vars.CGADSUB_copy.* = 0x72;
    } else if (xv == 0x95 or xv == 0x9c or prev == 0x5b or
        (prev == 0x1b and (vars.submodule_index.* == 35 or vars.submodule_index.* == 44)))
    {
        vars.CGADSUB_copy.* = 0x20;
    } else {
        vars.TS_copy.* = 0;
        vars.CGADSUB_copy.* = 0x20;
    }

    LoadOverworldOverlay();
    if (loPtr(vars.overlay_index).* == 0x94)
        vars.BG1VOFS_copy2.* |= 0x100;

    vars.overworld_screen_index.* = vars.overworld_screen_index_prev.*;
    vars.map16_load_src_off.* = vars.map16_load_src_off_prev.*;
    vars.map16_load_var2.* = vars.map16_load_var2_prev.*;
    vars.map16_load_dst_off.* = vars.map16_load_dst_off_prev.*;
    vars.overworld_screen_transition.* = vars.overworld_screen_transition_prev.*;
    vars.overworld_screen_trans_dir_bits.* = vars.overworld_screen_trans_dir_bits_prev.*;
    vars.overworld_screen_trans_dir_bits2.* = vars.overworld_screen_trans_dir_bits2_prev.*;
}

pub export fn Module09_FadeBackInFromMosaic() callconv(.c) void {
    Overworld_ResetMosaicDown();
    switch (vars.subsubmodule_index.*) {
        0 => {
            const sc: u8 = @truncate(vars.overworld_screen_index.*);
            load_gfx.Overworld_LoadPalettes(kOverworldBgPalettes()[sc], vars.overworld_sprite_palettes[sc]);
            OverworldMosaicTransition_LoadSpriteGraphicsAndSetMosaic();
        },
        1 => {
            load_gfx.Graphics_IncrementalVRAMUpload();
            load_gfx.ApplyPaletteFilter_bounce();
        },
        else => {
            vars.last_music_control.* = vars.music_unk1.*;
            const si = loPtr(vars.overworld_screen_index).*;
            if (si != 0x80 and si != 0x2a) {
                const m = vars.overworld_music[si];
                vars.sound_effect_ambient.* = if (m >> 4 != 0) m >> 4 else 5;
                if (!audio.ZeldaIsPlayingMusicTrack(m & 0xf))
                    vars.music_control.* = m & 0xf;
            }
            vars.submodule_index.* = 8;
            vars.subsubmodule_index.* = 0;
            if (vars.main_module_index.* == 11) {
                vars.main_module_index.* = 9;
                vars.submodule_index.* = 31;
                vars.ow_countdown_transition.* = 12;
            }
        },
    }
}

pub export fn Overworld_Func1C() callconv(.c) void {
    Overworld_ResetMosaicDown();
    switch (vars.subsubmodule_index.*) {
        0 => OverworldMosaicTransition_LoadSpriteGraphicsAndSetMosaic(),
        1 => {
            load_gfx.Graphics_IncrementalVRAMUpload();
            load_gfx.ApplyPaletteFilter_bounce();
        },
        else => {
            if (loPtr(vars.overworld_screen_index).* < 0x80)
                vars.music_control.* = if (vars.overworld_screen_index.* & 0x3f != 0) 2 else 5;
            vars.submodule_index.* = 8;
            vars.subsubmodule_index.* = 0;
        },
    }
}

pub export fn OverworldMosaicTransition_LoadSpriteGraphicsAndSetMosaic() callconv(.c) void {
    load_gfx.LoadNewSpriteGFXSet();
    vars.INIDISP_copy.* = 0xf;
    vars.HDMAEN_copy.* = 0x80;
    loPtr(vars.palette_filter_countdown).* = vars.mosaic_target_level.* -% 1;
    vars.mosaic_target_level.* = 0;
    loPtr(vars.darkening_or_lightening_screen).* = 2;
    vars.subsubmodule_index.* +%= 1;
}

pub export fn Overworld_Func22() callconv(.c) void {
    vars.INIDISP_copy.* +%= 1;
    if (vars.INIDISP_copy.* == 15) {
        vars.submodule_index.* = 0;
        vars.subsubmodule_index.* = 0;
    }
}

pub export fn Overworld_Func18() callconv(.c) void {
    vars.link_maybe_swim_faster.* = 0;
    const m = vars.main_module_index.*;
    const sub = vars.submodule_index.*;
    Overworld_EnterSpecialArea();
    Overworld_LoadOverlays();
    vars.submodule_index.* = sub +% 1;
    vars.main_module_index.* = m;
}

pub export fn Overworld_Func19() callconv(.c) void {
    const m = vars.main_module_index.*;
    const sub = vars.submodule_index.*;
    Module08_02_LoadAndAdvance();
    vars.submodule_index.* = sub +% 1;
    vars.main_module_index.* = m;
}

pub export fn Module09_MirrorWarp() callconv(.c) void {
    vars.nmi_disable_core_updates.* +%= 1;
    const idx = vars.subsubmodule_index.*;
    switch (idx) {
        0 => {
            if (loPtr(vars.overworld_screen_index).* >= 0x80) {
                vars.submodule_index.* = 0;
                vars.subsubmodule_index.* = 0;
                vars.overworld_map_state.* = 0;
                return;
            }
            vars.music_control.* = 8;
            vars.flag_overworld_area_did_change.* = 8;
            vars.countdown_for_blink.* = 0x90;
            InitializeMirrorHDMA();
            vars.savegame_is_darkworld.* ^= 0x40;
            vars.word_7E04C8.* = 0;
            const v: u8 = @truncate((vars.overworld_screen_index.* & 0x3f) | vars.savegame_is_darkworld.*);
            loPtr(vars.overworld_screen_index).* = v;
            loPtr(vars.overworld_area_index).* = v;
            vars.overworld_map_state.* = 0;
            load_gfx.PaletteFilter_InitializeWhiteFilter();
            Overworld_LoadGFXAndScreenSize();
            vars.subsubmodule_index.* +%= 1;
        },
        // Case 1 falls through into case 2.
        1, 2 => {
            if (idx == 1) {
                vars.subsubmodule_index.* +%= 1;
                vars.HDMAEN_copy.* = 0xc0;
            }
            MirrorWarp_BuildWavingHDMATable();
        },
        3 => MirrorWarp_BuildDewavingHDMATable(),
        else => MirrorWarp_FinalizeAndLoadDestination(),
    }
}

pub export fn MirrorWarp_FinalizeAndLoadDestination() callconv(.c) void {
    rtl.HdmaSetup(0, 0xf2fb, 0x41, 0, @truncate(WH0), 0);
    load_gfx.IrisSpotlight_ResetTable();
    vars.palette_filter_countdown.* = 0;
    vars.darkening_or_lightening_screen.* = 0;
    load_gfx.ReloadPreviouslyLoadedSheets();
    Overworld_SetSongList();
    vars.HDMAEN_copy.* = 0x80;
    const m = vars.overworld_music[loPtr(vars.overworld_screen_index).*];
    vars.music_control.* = m & 0xf;
    vars.sound_effect_ambient.* = m >> 4;
    if (loPtr(vars.overworld_screen_index).* >= 0x40 and vars.link_item_moon_pearl.* == 0)
        vars.music_control.* = 4;

    vars.saved_module_for_menu.* = vars.submodule_index.*;
    vars.submodule_index.* = 0;
    vars.subsubmodule_index.* = 0;
    vars.overworld_map_state.* = 0;
    vars.nmi_disable_core_updates.* = 0;
}

pub export fn Overworld_DrawScreenAtCurrentMirrorPosition() callconv(.c) void {
    const bak1 = vars.map16_load_src_off.*;
    const bak2 = vars.map16_load_dst_off.*;
    const bak3 = vars.map16_load_var2.*;
    if (kOverworldMapIsSmall()[loPtr(vars.overworld_screen_index).*] != 0) {
        vars.map16_load_src_off.* = 0x390;
        vars.map16_load_var2.* = (0x390 - 0x400 & 0xf80) >> 7;
        vars.map16_load_dst_off.* = (0x390 - 0x10 & 0x3e) >> 1;
    }
    Overworld_DrawQuadrantsAndOverlays();
    if (vars.submodule_index.* == 44)
        MirrorBonk_RecoverChangedTiles();
    vars.map16_load_var2.* = bak3;
    vars.map16_load_dst_off.* = bak2;
    vars.map16_load_src_off.* = bak1;
}

pub export fn MirrorWarp_LoadSpritesAndColors() callconv(.c) void {
    vars.countdown_for_blink.* = 0x90;
    const bak1 = vars.map16_load_src_off.*;
    const bak2 = vars.map16_load_dst_off.*;
    const bak3 = vars.map16_load_var2.*;
    if (kOverworldMapIsSmall()[loPtr(vars.overworld_screen_index).*] != 0) {
        vars.map16_load_src_off.* = 0x390;
        vars.map16_load_var2.* = (0x390 - 0x400 & 0xf80) >> 7;
        vars.map16_load_dst_off.* = (0x390 - 0x10 & 0x3e) >> 1;
    }
    Map16ToMap8(g_ram[0x2000..].ptr, 0);
    vars.map16_load_var2.* = bak3;
    vars.map16_load_dst_off.* = bak2;
    vars.map16_load_src_off.* = bak1;

    load_gfx.OverworldLoadScreensPaletteSet();
    const sc: u8 = @truncate(vars.overworld_screen_index.*);
    load_gfx.Overworld_LoadPalettes(kOverworldBgPalettes()[sc], vars.overworld_sprite_palettes[sc]);
    load_gfx.Palette_SpecialOw();
    Overworld_SetFixedColAndScroll();
    if (loPtr(vars.overworld_screen_index).* == 0x1b or loPtr(vars.overworld_screen_index).* == 0x5b)
        vars.TS_copy.* = 1;
    var i: usize = 0;
    while (i < 16 * 6) : (i += 1)
        vars.main_palette_buffer[32 + i] = 0x7fff;
    vars.main_palette_buffer[0] = 0x7fff;
    if (vars.overworld_screen_index.* == 0x5b) {
        vars.main_palette_buffer[0] = 0;
        vars.main_palette_buffer[32] = 0;
    }
    Sprite_ResetAll();
    Sprite_ReloadAll_Overworld();
    Link_ItemReset_FromOverworldThings();
    Dungeon_ResetTorchBackgroundAndPlayerInner();
    vars.link_player_handler_state.* = kPlayerState_Mirror;
    if (vars.overworld_screen_index.* & 0x40 == 0)
        Sprite_InitializeMirrorPortal();
}

pub export fn Overworld_Func2B() callconv(.c) void {
    Palette_AnimGetMasterSword();
}

pub export fn Overworld_WeathervaneExplosion() callconv(.c) void {
    // empty
}

pub export fn Module09_2E_Whirlpool() callconv(.c) void {
    // this is called when entering the whirlpool
    vars.nmi_disable_core_updates.* +%= 1;
    switch (vars.subsubmodule_index.*) {
        0 => {
            vars.sound_effect_1.* = 0x34;
            vars.sound_effect_ambient.* = 5;
            vars.overworld_map_state.* = 0;
            vars.palette_filter_countdown.* = 0;
            vars.subsubmodule_index.* +%= 1;
        },
        1 => load_gfx.PaletteFilter_WhirlpoolBlue(),
        2 => load_gfx.PaletteFilter_IsolateWhirlpoolBlue(),
        3 => {
            vars.COLDATA_copy2.* = 0x9f;
            vars.overworld_palette_aux_or_main.* = 0;
            vars.hud_palette.* = 0;
            FindPartnerWhirlpoolExit();
            loPtr(vars.dung_draw_width_indicator).* = 0;
            Overworld_LoadOverlays2();
            vars.submodule_index.* -%= 1;
            vars.nmi_subroutine_index.* = 12;
            vars.flag_update_cgram_in_nmi.* = 0;
            vars.COLDATA_copy2.* = 0x80;
            vars.INIDISP_copy.* = 0xf;
            vars.nmi_disable_core_updates.* +%= 1;
            vars.subsubmodule_index.* +%= 1;
        },
        4, 6 => {
            vars.nmi_subroutine_index.* = 13;
            vars.nmi_disable_core_updates.* +%= 1;
            vars.subsubmodule_index.* +%= 1;
        },
        5 => {
            messaging.Overworld_LoadOverlayAndMap();
            vars.nmi_subroutine_index.* = 12;
            vars.INIDISP_copy.* = 0xf;
            vars.nmi_disable_core_updates.* +%= 1;
            vars.subsubmodule_index.* +%= 1;
        },
        7 => {
            Module09_LoadAuxGFX();
            vars.submodule_index.* -%= 1;
            vars.subsubmodule_index.* +%= 1;
        },
        8 => {
            Overworld_FinishTransGfx();
            vars.INIDISP_copy.* = 0xf;
            vars.nmi_disable_core_updates.* +%= 1;
            vars.submodule_index.* -%= 1;
            vars.subsubmodule_index.* +%= 1;
        },
        9 => {
            vars.overworld_palette_aux_or_main.* = 0;
            load_gfx.Palette_Load_SpriteMain();
            load_gfx.Palette_Load_SpriteEnvironment();
            load_gfx.Palette_Load_Sp0L();
            load_gfx.Palette_Load_HUD();
            load_gfx.Palette_Load_OWBGMain();
            const sc: u8 = @truncate(vars.overworld_screen_index.*);
            load_gfx.Overworld_LoadPalettes(kOverworldBgPalettes()[sc], vars.overworld_sprite_palettes[sc]);
            load_gfx.Palette_SetOwBgColor();
            Overworld_SetFixedColAndScroll();
            load_gfx.LoadNewSpriteGFXSet();
            vars.COLDATA_copy2.* = 0x80;
            vars.INIDISP_copy.* = 0xf;
            vars.nmi_disable_core_updates.* +%= 1;
            vars.subsubmodule_index.* +%= 1;
        },
        10 => {
            load_gfx.PaletteFilter_WhirlpoolRestoreRedGreen();
            if (loPtr(vars.palette_filter_countdown).* != 0)
                load_gfx.PaletteFilter_WhirlpoolRestoreRedGreen();
        },
        11 => {
            load_gfx.Graphics_IncrementalVRAMUpload();
            load_gfx.PaletteFilter_WhirlpoolRestoreBlue();
        },
        12 => {
            vars.countdown_for_blink.* = 144;
            load_gfx.ReloadPreviouslyLoadedSheets();
            vars.HDMAEN_copy.* = 0x80;
            vars.sound_effect_ambient.* = vars.overworld_music[loPtr(vars.overworld_screen_index).*] >> 4;
            vars.music_control.* = if (vars.savegame_is_darkworld.* != 0) 9 else 2;
            vars.submodule_index.* = 0;
            vars.subsubmodule_index.* = 0;
            vars.overworld_map_state.* = 0;
            vars.nmi_disable_core_updates.* = 0;
        },
        else => {},
    }
}

pub export fn Overworld_Func2F() callconv(.c) void {
    vars.dung_bg2[0x720 / 2] = 0x212;
    Overworld_Memorize_Map16_Change(0x720, 0x212);
    Overworld_DrawMap16(0x720, 0x212);
    vars.nmi_load_bg_from_vram.* = 1;
    vars.submodule_index.* = 0;
}

pub export fn Module09_2A_RecoverFromDrowning() callconv(.c) void {
    // this is called for example when entering water without swim capability
    switch (vars.subsubmodule_index.*) {
        0 => Module09_2A_00_ScrollToLand(),
        else => RecoverPositionAfterDrowning(),
    }
}

pub export fn Module09_2A_00_ScrollToLand() callconv(.c) void {
    var x = vars.link_x_coord.*;
    var xd: u16 = 0;
    if (x != vars.link_x_coord_cached.*) {
        const d: u16 = if (x > vars.link_x_coord_cached.*) 0xffff else 1;
        x +%= d;
        if (x != vars.link_x_coord_cached.*)
            x +%= d;
        xd = x -% vars.link_x_coord.*;
        vars.link_x_coord.* = x;
    }
    var y = vars.link_y_coord.*;
    var yd: u16 = 0;
    if (y != vars.link_y_coord_cached.*) {
        const d: u16 = if (y > vars.link_y_coord_cached.*) 0xffff else 1;
        y +%= d;
        if (y != vars.link_y_coord_cached.*)
            y +%= d;
        yd = y -% vars.link_y_coord.*;
        vars.link_y_coord.* = y;
    }
    vars.link_y_vel.* = @truncate(yd);
    vars.link_x_vel.* = @truncate(xd);
    if (y == vars.link_y_coord_cached.* and x == vars.link_x_coord_cached.*) {
        vars.subsubmodule_index.* +%= 1;
        vars.link_incapacitated_timer.* = 0;
        vars.set_when_damaging_enemies.* = 0;
    }
    Overworld_OperateCameraScroll();
    if (loPtr(vars.overworld_screen_trans_dir_bits2).* != 0)
        OverworldHandleMapScroll();
}

/// The C indexes across adjacent work-ram words (`(&overworld_unk1)[ya]` and
/// friends), so these address the block directly rather than via struct fields.
inline fn u16at(off: usize) *align(1) u16 {
    return @ptrCast(&g_ram[off]);
}

/// ow_scroll_vars0 = 0x600 {ystart, yend, xstart, xend}
inline fn scrollVar(i: usize) *align(1) u16 {
    return u16at(0x600 + i * 2);
}
/// overworld_unk1 = 0x624, _neg = 0x626, unk3 = 0x628, unk3_neg = 0x62a
inline fn owUnk(i: usize) *align(1) u16 {
    return u16at(0x624 + i * 2);
}
/// camera_y_coord_scroll_hi = 0x61a, camera_x_coord_scroll_hi = 0x61e
inline fn camHi(i: usize) *align(1) u16 {
    return u16at(0x61a + i * 2);
}
/// camera_y_coord_scroll_low = 0x618, camera_x_coord_scroll_low = 0x61c
inline fn camLow(i: usize) *align(1) u16 {
    return u16at(0x618 + i * 2);
}
/// up_down_scroll_target = 0x610, _end = 0x612, left_right = 0x614, _end = 0x616
inline fn scrollTarget(i: usize) *align(1) u16 {
    return u16at(0x610 + i * 2);
}

// ------------------------------------------------------ the widescreen camera
//
// The game keeps the camera between an area's left and right limits, which
// line the area's edges up with the edges of a 256-pixel screen. Widescreen
// was added long after, so in a wider frame those same limits leave the
// extra width at the sides looking past the area's edge, at nothing. With
// the widescreen camera on, the camera keeps the width of a margin further
// in, so the whole wide picture stays inside the area; scroll transitions
// carry it to the same spot in the next area, and after an entrance or a
// vertical transition it settles into range a couple of pixels a frame.
//
// Off, or at 4:3 where the margin is 0, every one of these takes the
// original's path, so the game plays and compares exactly as before.

/// How far in from an area's edges the camera stays: the widescreen margin,
/// or half the area's range for one too narrow to allow that. 0 is the
/// original behavior.
pub fn wideCameraMargin(range: u16) u16 {
    if (!config.g_widescreen_camera) return 0;
    const m: u16 = config.g_config.extended_aspect_ratio;
    return @min(m, range / 2);
}

/// The margin a sideways scroll's camera stops past the 4:3 landing.
fn wideScrollMargin() u16 {
    return wideCameraMargin(tables.kOverworld_Size2[@intFromBool(vars.overworld_area_is_big.* != 0)]);
}

/// Where a widescreen sideways scroll stops: the 4:3 landing, a margin on.
fn wideScrollTarget(y: usize) u16 {
    const m = wideScrollMargin();
    return if (tables.kOverworld_Func6B_Tab1[y] > 0) scrollTarget(y).* +% m else scrollTarget(y).* -% m;
}

pub fn wideCameraOn() bool {
    return config.g_widescreen_camera and config.g_config.extended_aspect_ratio != 0;
}

/// Set while a sideways scroll transition runs with the widescreen camera: the
/// picture's margins show in full then, as they do when the original's
/// transition starts right at the area's edge, rather than shrinking to
/// black for the first few steps and then coming back.
pub var g_wide_sideways_scroll: bool = false;

/// Moves BG1 - the overlay: fog, woods, the castle - along with a sideways
/// camera move of `r4` pixels, at its own rate, the way the game does as the
/// camera follows Link.
fn addOverlayScrollX(r4: u16) void {
    const oi = loPtr(vars.overlay_index).*;
    if (oi == 0x97 or oi == 0x9d or r4 == 0) return;
    var subp: u16 = undefined;
    var v = r4;
    if (oi == 0x95 or oi == 0x9e) {
        subp = (v & 3) << 14;
        v >>= 2;
        if (v >= 0x3000) v |= 0xf000;
    } else {
        subp = (v & 1) << 15;
        v >>= 1;
        if (v >= 0x7000) v |= 0xf000;
    }
    var tmp = @as(u32, vars.BG1HOFS_subpixel.*) | @as(u32, vars.BG1HOFS_copy2.*) << 16;
    tmp +%= @as(u32, subp) | @as(u32, v) << 16;
    vars.BG1HOFS_subpixel.* = @truncate(tmp);
    vars.BG1HOFS_copy2.* = @truncate(tmp >> 16);
}

/// Moves the camera one pixel toward the widescreen range when it's outside,
/// the way the camera moves when following Link, so the map loads and the
/// thresholds move along with it. Returns the step, for the overlays.
/// Puts the camera straight at the widescreen camera's range, for coming
/// out of a door whose exit has the camera where the 4:3 one goes (Link's
/// house and the Sanctuary, and the other exits the game keeps a table of),
/// before the map's drawn. Left to settle, it slides over as the circle opens.
/// The column loads go along: the map's drawn from them, and each 16 pixels
/// the camera moves right they're a column further on.
fn snapCameraX() void {
    if (!wideCameraOn()) return;
    // The room the Triforce is in borrows a special area to stand its scene
    // up in, and puts the camera somewhere of its own outside that area's
    // range. Pulling it into range tears the scene apart.
    if (vars.main_module_index.* == 25) return;
    const xs = vars.ow_scroll_vars0.xstart;
    const xe = vars.ow_scroll_vars0.xend;
    if (xe < xs) return;
    // An area with no room to scroll sideways has no margin, but the camera
    // still belongs in its range: one with none, a special area's, say, has
    // a single place for it, where the 4:3 camera would have come in.
    const m = wideCameraMargin(xe -% xs);
    const cam = vars.BG2HOFS_copy2.*;
    const to = if (cam < xs +% m) xs +% m else if (cam > xe -% m) xe -% m else return;
    const delta: i16 = @bitCast(to -% cam);
    const du: u16 = @bitCast(delta);
    vars.BG2HOFS_copy2.* = to;
    vars.BG2HOFS_copy.* = to;
    vars.BG1HOFS_copy2.* +%= du;
    vars.BG1HOFS_copy.* +%= du;
    vars.camera_x_coord_scroll_low.* +%= du;
    vars.camera_x_coord_scroll_hi.* +%= du;
    // overworld_unk3_neg counts the pixels moved right since the last column.
    const moved: i32 = @as(i16, @bitCast(vars.overworld_unk3_neg.*)) + @as(i32, delta);
    const cols: i32 = @divFloor(moved, 16);
    vars.overworld_unk3_neg.* = @intCast(moved - cols * 16);
    vars.overworld_unk3.* = 0 -% vars.overworld_unk3_neg.*;
    const cu: u16 = @bitCast(@as(i16, @intCast(cols)));
    vars.map16_load_src_off.* +%= 2 *% cu;
    vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* +% cu) & 0x1f;
}

fn settleCameraX() u16 {
    if (!wideCameraOn()) return 0;
    const xs = vars.ow_scroll_vars0.xstart;
    const xe = vars.ow_scroll_vars0.xend;
    const m = wideCameraMargin(xe -% xs);
    if (m == 0) return 0;
    const cam = vars.BG2HOFS_copy2.*;
    if (cam < xs +% m)
        return @truncate(@as(u32, @bitCast(OverworldCameraBoundaryCheck(0, 6, 1, 4))));
    if (cam > xe -% m)
        return @truncate(@as(u32, @bitCast(OverworldCameraBoundaryCheck(0, 4, -1, 4))));
    return 0;
}

pub export fn Overworld_OperateCameraScroll() callconv(.c) void {
    const z: u16 = if (vars.allow_scroll_z.* != 0 and vars.link_z_coord.* != 0xffff)
        vars.link_z_coord.*
    else
        0;
    const y = vars.link_y_coord.* -% z +% 12;

    if (vars.link_y_vel.* != 0) {
        const neg = sign8(vars.link_y_vel.*);
        const vy: c_int = if (neg) -1 else 1;
        var av: u32 = if (neg) (vars.link_y_vel.* ^ 0xff) +% 1 else vars.link_y_vel.*;
        var r4: u16 = 0;
        while (true) {
            if (neg) {
                if (y <= vars.camera_y_coord_scroll_low.*)
                    r4 +%= @truncate(@as(u32, @bitCast(OverworldCameraBoundaryCheck(6, 0, vy, 0))));
            } else {
                if (y >= vars.camera_y_coord_scroll_hi.*)
                    r4 +%= @truncate(@as(u32, @bitCast(OverworldCameraBoundaryCheck(6, 2, vy, 0))));
            }
            av -%= 1;
            if (av == 0) break;
        }
        std.mem.writeInt(u16, g_ram[0x69e..0x6a0], r4, .little);
        const oi = loPtr(vars.overlay_index).*;
        if (oi != 0x97 and oi != 0x9d and r4 != 0) {
            var subp: u16 = undefined;
            var v = r4;
            if (oi == 0xb5 or oi == 0xbe) {
                subp = (v & 3) << 14;
                v >>= 2;
                if (v >= 0x3000) v |= 0xf000;
            } else {
                subp = (v & 1) << 15;
                v >>= 1;
                if (v >= 0x7000) v |= 0xf000;
            }
            var tmp = @as(u32, vars.BG1VOFS_subpixel.*) | @as(u32, vars.BG1VOFS_copy2.*) << 16;
            tmp +%= @as(u32, subp) | @as(u32, v) << 16;
            vars.BG1VOFS_subpixel.* = @truncate(tmp);
            vars.BG1VOFS_copy2.* = @truncate(tmp >> 16);
            if (vars.overworld_screen_index.* & 0x3f == 0x1b) {
                if (vars.BG1VOFS_copy2.* <= 0x600) {
                    vars.BG1VOFS_copy2.* = 0x600;
                } else if (vars.BG1VOFS_copy2.* >= 0x6c0) {
                    vars.BG1VOFS_copy2.* = 0x6c0;
                }
            }
        }
    }

    const x = vars.link_x_coord.* +% 8;
    // Widescreen: a couple of pixels a frame toward the range, while outside.
    var settle: u16 = 0;
    settle +%= settleCameraX();
    settle +%= settleCameraX();
    if (vars.link_x_vel.* != 0 or settle != 0) {
        const neg = sign8(vars.link_x_vel.*);
        const vx: c_int = if (neg) -1 else 1;
        var ax: u32 = if (neg) (vars.link_x_vel.* ^ 0xff) +% 1 else vars.link_x_vel.*;
        var r4: u16 = settle;
        while (ax != 0) {
            if (neg) {
                if (x <= vars.camera_x_coord_scroll_low.*)
                    r4 +%= @truncate(@as(u32, @bitCast(OverworldCameraBoundaryCheck(0, 4, vx, 4))));
            } else {
                if (x >= vars.camera_x_coord_scroll_hi.*)
                    r4 +%= @truncate(@as(u32, @bitCast(OverworldCameraBoundaryCheck(0, 6, vx, 4))));
            }
            ax -%= 1;
        }
        std.mem.writeInt(u16, g_ram[0x69f..0x6a1], r4, .little);
        const oi = loPtr(vars.overlay_index).*;
        if (oi != 0x97 and oi != 0x9d and r4 != 0) {
            var subp: u16 = undefined;
            var v = r4;
            if (oi == 0x95 or oi == 0x9e) {
                subp = (v & 3) << 14;
                v >>= 2;
                if (v >= 0x3000) v |= 0xf000;
            } else {
                subp = (v & 1) << 15;
                v >>= 1;
                if (v >= 0x7000) v |= 0xf000;
            }
            var tmp = @as(u32, vars.BG1HOFS_subpixel.*) | @as(u32, vars.BG1HOFS_copy2.*) << 16;
            tmp +%= @as(u32, subp) | @as(u32, v) << 16;
            vars.BG1HOFS_subpixel.* = @truncate(tmp);
            vars.BG1HOFS_copy2.* = @truncate(tmp >> 16);
        }
    }

    if (loPtr(vars.overworld_screen_index).* != 0x47) {
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
    }

    if (vars.dungeon_room_index.* == 0x181) {
        vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy2.* | 0x100;
        vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2.*;
    }
}

pub export fn OverworldCameraBoundaryCheck(xa: c_int, ya_in: c_int, vd: c_int, r8_in: c_int) callconv(.c) c_int {
    const ya: usize = @intCast(ya_in >> 1);
    const r8: usize = @intCast(r8_in >> 1);

    const xp = if (xa != 0) vars.BG2VOFS_copy2 else vars.BG2HOFS_copy2;
    const yp = scrollVar(ya);
    const stop = if (xa == 0 and wideCameraOn()) blk: {
        // Widescreen: the limit is a margin in from the edge, and the camera
        // can start out past it, so it's a bound rather than a mark.
        const m = wideCameraMargin(scrollVar(3).* -% scrollVar(2).*);
        break :blk if (ya == 2) xp.* <= scrollVar(2).* +% m else xp.* >= scrollVar(3).* -% m;
    } else xp.* == yp.*;
    if (stop) {
        owUnk(ya).* = 0;
        owUnk(ya ^ 1).* = 0;
        return 0;
    }
    xp.* +%= @truncate(@as(u32, @bitCast(vd)));

    const tt: u16 = @truncate(@as(u32, @bitCast(vd)) +% camHi(r8).*);
    camHi(r8).* = tt;
    camLow(r8).* = tt +% 2;

    const op = owUnk(ya);
    op.* +%= 1;
    if (!sign16(op.* -% 0x10)) {
        op.* -%= 0x10;
        vars.overworld_screen_trans_dir_bits2.* |= tables.kOverworld_Func2_Tab[ya];
    }
    owUnk(ya ^ 1).* = 0 -% owUnk(ya).*;
    return vd;
}

pub export fn OverworldScrollTransition() callconv(.c) c_int {
    vars.transition_counter.* +%= 1;
    const y: usize = vars.overworld_screen_transition.*;
    const d: i16 = tables.kOverworld_Func6B_Tab1[y];
    const du: u16 = @bitCast(d);
    var rv: u16 = undefined;

    if (y < 2) {
        vars.byte_7E069E[0] = @truncate(du);
        vars.BG2VOFS_copy2.* +%= du;
        rv = vars.BG2VOFS_copy2.*;
        const si = loPtr(vars.overworld_screen_index).*;
        if (si != 0x1b and si != 0x5b)
            vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy2.*;
        if (vars.transition_counter.* >= @as(u16, @bitCast(tables.kOverworld_Func6B_Tab2[y])))
            vars.link_y_coord.* +%= du;
        if (rv != scrollTarget(y).*) return rv;
        if (y == 0)
            vars.BG2VOFS_copy2.* -%= 2;
        vars.link_y_coord.* &= ~@as(u16, 7);
        vars.camera_y_coord_scroll_hi.* = vars.link_y_coord.* +%
            @as(u16, @bitCast(tables.kOverworld_Func6B_Tab3[y])) +% 11;
        vars.camera_y_coord_scroll_low.* = vars.camera_y_coord_scroll_hi.* +% 2;
        vars.overworld_unk1.* = 0;
        vars.overworld_unk1_neg.* = 0;
    } else {
        vars.byte_7E069E[1] = @truncate(du);
        // Widescreen: on to the new area's widescreen position instead, a
        // margin further, the last step cut short to land on it exactly.
        const wide = wideCameraOn();
        const target = if (wide) wideScrollTarget(y) else scrollTarget(y).*;
        vars.BG2HOFS_copy2.* +%= du;
        if (wide) {
            const past: i16 = @bitCast(vars.BG2HOFS_copy2.* -% target);
            if ((d > 0 and past > 0) or (d < 0 and past < 0)) vars.BG2HOFS_copy2.* = target;
        }
        rv = vars.BG2HOFS_copy2.*;
        const si = loPtr(vars.overworld_screen_index).*;
        if (si != 0x1b and si != 0x5b)
            vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2.*;
        if (!wide) {
            if (vars.transition_counter.* >= @as(u16, @bitCast(tables.kOverworld_Func6B_Tab2[y])))
                vars.link_x_coord.* +%= du;
        } else {
            // Link walks in over the scroll's last stretch, the same
            // distance as the original's: its last 256 - 30 * 8 = 16 pixels,
            // however long the scroll turned out to be.
            const left: i32 = @intCast(@abs(@as(i32, @as(i16, @bitCast(target -% rv)))));
            const step: i32 = @intCast(@abs(@as(i32, d)));
            const walk_in: i32 = 256 - @as(i32, tables.kOverworld_Func6B_Tab2[y]) * step;
            if (left <= walk_in) vars.link_x_coord.* +%= du;
        }
        if (rv != target) return rv;
        // The castle and the pyramid hold their overlay still through the
        // scroll and set it for where the original's camera lands. This one
        // lands a margin further in, so the overlay moves on by as much, at
        // its own rate, as it would have if the camera had got there by
        // following Link.
        if (wide and (si == 0x1b or si == 0x5b))
            addOverlayScrollX(target -% scrollTarget(y).*);
        vars.link_x_coord.* &= ~@as(u16, 7);
        vars.camera_x_coord_scroll_hi.* = vars.link_x_coord.* +%
            @as(u16, @bitCast(tables.kOverworld_Func6B_Tab3[y])) +% 11;
        // Where Link has to get to for the camera to follow is set for the
        // original's camera; this one's a margin on, and so is that.
        if (wide) vars.camera_x_coord_scroll_hi.* +%= target -% scrollTarget(y).*;
        vars.camera_x_coord_scroll_low.* = vars.camera_x_coord_scroll_hi.* +% 2;
        vars.overworld_unk3.* = 0;
        vars.overworld_unk3_neg.* = 0;
    }
    const area: c_int = @as(c_int, @intCast(vars.current_area_of_player.* >> 1)) +
        tables.kOverworld_Func6B_AreaDelta[y];
    Overworld_SetCameraBoundaries(@intFromBool(vars.overworld_area_is_big.* != 0), area);

    vars.flag_overworld_area_did_change.* = 1;
    vars.submodule_index.* +%= 1;
    vars.subsubmodule_index.* = 0;
    vars.transition_counter.* = 0;
    Sprite_InitializeSlots();
    return rv;
}

pub export fn Overworld_SetCameraBoundaries(big: c_int, area: c_int) callconv(.c) void {
    const b: usize = @intCast(big);
    const a: usize = @intCast(area);
    vars.ow_scroll_vars0.ystart = tables.kOverworld_OffsetBaseY[a];
    vars.ow_scroll_vars0.yend = vars.ow_scroll_vars0.ystart +% tables.kOverworld_Size1[b];
    vars.ow_scroll_vars0.xstart = tables.kOverworld_OffsetBaseX[a];
    vars.ow_scroll_vars0.xend = vars.ow_scroll_vars0.xstart +% tables.kOverworld_Size2[b];
    vars.up_down_scroll_target.* = tables.kOverworld_UpDownScrollTarget[a];
    vars.up_down_scroll_target_end.* = vars.up_down_scroll_target.* +% tables.kOverworld_UpDownScrollSize[b];
    vars.left_right_scroll_target.* = tables.kOverworld_LeftRightScrollTarget[a];
    vars.left_right_scroll_target_end.* = vars.left_right_scroll_target.* +% tables.kOverworld_LeftRightScrollSize[b];
}

pub export fn Overworld_FinalizeEntryOntoScreen() callconv(.c) void {
    Link_HandleMovingAnimation_FullLongEntry();
    const dir = vars.byte_7E069C.*;
    var d: i32 = if (dir & 1 != 0) 2 else -2;
    if (dir & 2 != 0) {
        d +%= vars.link_x_coord.*;
        vars.link_x_coord.* = @truncate(@as(u32, @bitCast(d)));
    } else {
        d +%= vars.link_y_coord.*;
        vars.link_y_coord.* = @truncate(@as(u32, @bitCast(d)));
    }
    if ((d & 0xfe) == tables.kOverworld_Func8_tab[dir]) {
        vars.submodule_index.* = 0;
        vars.subsubmodule_index.* = 0;
        const m = vars.overworld_music[loPtr(vars.overworld_screen_index).*];
        vars.sound_effect_ambient.* = m >> 4;
        if (vars.music_unk1.* == 0xf1)
            vars.music_control.* = m & 0xf;
    }
    Overworld_OperateCameraScroll();
    if (loPtr(vars.overworld_screen_trans_dir_bits2).* != 0)
        OverworldHandleMapScroll();
}

pub export fn Overworld_Func1F() callconv(.c) void {
    Link_HandleMovingAnimation_FullLongEntry();
    const vel: i8 = if (vars.byte_7E069C.* & 1 != 0) 1 else -1;
    if (vars.byte_7E069C.* & 2 != 0) {
        vars.link_x_coord.* +%= @bitCast(@as(i16, vel));
        vars.link_x_vel.* = @bitCast(vel);
    } else {
        vars.link_y_coord.* +%= @bitCast(@as(i16, vel));
        vars.link_y_vel.* = @bitCast(vel);
    }
    vars.ow_countdown_transition.* -%= 1;
    if (vars.ow_countdown_transition.* == 0) {
        vars.main_module_index.* = 9;
        vars.submodule_index.* = 0;
        vars.subsubmodule_index.* = 0;
    }
    Overworld_OperateCameraScroll();
}

pub export fn ConditionalMosaicControl() callconv(.c) void {
    if (vars.palette_filter_countdown.* & 1 != 0)
        vars.mosaic_level.* +%= 0x10;
    vars.BGMODE_copy.* = 9;
    vars.MOSAIC_copy.* = vars.mosaic_level.* | 7;
}

pub export fn Overworld_ResetMosaic_alwaysIncrease() callconv(.c) void {
    vars.mosaic_level.* +%= 0x10;
    vars.BGMODE_copy.* = 9;
    vars.MOSAIC_copy.* = vars.mosaic_level.* | 7;
}

pub export fn Overworld_SetSongList() callconv(.c) void {
    var r0: u8 = 2;
    var y: usize = 0xc0;
    if (vars.sram_progress_indicator.* < 3) {
        y = 0x80;
        if (vars.link_sword_type.* < 2) {
            r0 = 5;
            y = 0x40;
            if (vars.sram_progress_indicator.* < 2)
                y = 0;
        }
    }
    @memcpy(vars.overworld_music[0..64], (kOwMusicSets() + y)[0..64]);
    @memcpy((vars.overworld_music + 64)[0..96], kOwMusicSets2()[0..96]);
    vars.overworld_music[128] = r0;
}

pub export fn LoadOverworldFromDungeon() callconv(.c) void {
    vars.player_is_indoors.* = 0;
    vars.hdr_dungeon_dark_with_lantern.* = 0;
    wordPtr(vars.overworld_fixed_color_plusminus).* = 0;
    vars.cur_palace_index_x2.* = 0xff;
    vars.num_memorized_tiles.* = 0;

    const dr = vars.dungeon_room_index.*;
    if (dr != 0x104 and dr < 0x180 and dr >= 0x100) {
        LoadCachedEntranceProperties();
    } else {
        var k: usize = 79;
        while (true) {
            k -= 1;
            if (kExitDataRooms()[k] == dr) break;
        }
        vars.BG2VOFS_copy.* = kExitData_ScrollY()[k];
        vars.BG1VOFS_copy.* = vars.BG2VOFS_copy.*;
        vars.BG2VOFS_copy2.* = vars.BG2VOFS_copy.*;
        vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy.*;
        vars.BG2HOFS_copy.* = kExitData_ScrollX()[k];
        vars.BG1HOFS_copy.* = vars.BG2HOFS_copy.*;
        vars.BG2HOFS_copy2.* = vars.BG2HOFS_copy.*;
        vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy.*;
        vars.link_y_coord.* = kExitData_YCoord()[k];
        vars.link_x_coord.* = kExitData_XCoord()[k];
        vars.map16_load_src_off.* = kExitData_Map16LoadSrcOff()[k];
        vars.map16_load_var2.* = (vars.map16_load_src_off.* -% 0x400 & 0xf80) >> 7;
        vars.map16_load_dst_off.* = (vars.map16_load_src_off.* -% 0x10 & 0x3e) >> 1;
        vars.camera_y_coord_scroll_low.* = kExitData_CameraYScroll()[k];
        vars.camera_y_coord_scroll_hi.* = vars.camera_y_coord_scroll_low.* -% 2;
        vars.camera_x_coord_scroll_low.* = kExitData_CameraXScroll()[k];
        vars.camera_x_coord_scroll_hi.* = vars.camera_x_coord_scroll_low.* -% 2;
        wordPtr(vars.link_direction_facing).* = 2;
        vars.ow_entrance_value.* = kExitData_NormalDoor()[k];
        vars.big_rock_starting_address.* = kExitData_FancyDoor()[k];
        vars.overworld_screen_index.* = kExitData_ScreenIndex()[k];
        vars.overworld_area_index.* = vars.overworld_screen_index.*;
        vars.overworld_unk1.* = @bitCast(@as(i16, kExitData_Unk1()[k]));
        vars.overworld_unk3.* = @bitCast(@as(i16, kExitData_Unk3()[k]));
        vars.overworld_unk1_neg.* = 0 -% vars.overworld_unk1.*;
        vars.overworld_unk3_neg.* = 0 -% vars.overworld_unk3.*;
    }
    Overworld_LoadNewScreenProperties();
    snapCameraX();
}

pub export fn Overworld_LoadNewScreenProperties() callconv(.c) void {
    vars.tilemap_location_calc_mask.* = ~@as(u16, 7);
    Overworld_LoadGFXAndScreenSize();
    loPtr(vars.overworld_right_bottom_bound_for_scroll).* = 0xe4;
    vars.overworld_area_is_big.* &= 0xff;
    Overworld_SetCameraBoundaries(
        @intFromBool(vars.overworld_area_is_big.* != 0),
        @intCast(vars.overworld_screen_index.* & 0x3f),
    );
    vars.link_quadrant_x.* = 0;
    vars.link_quadrant_y.* = 2;
    vars.quadrant_fullsize_x.* = 2;
    vars.quadrant_fullsize_y.* = 2;
    vars.player_oam_x_offset.* = 0x80;
    vars.player_oam_y_offset.* = 0x80;
    vars.link_direction_mask_a.* = 0xf;
    vars.link_direction_mask_b.* = 0xf;
    loPtr(vars.link_z_coord).* = 0xff;
    vars.link_actual_vel_z.* = 0xff;
}

pub export fn LoadCachedEntranceProperties() callconv(.c) void {
    vars.overworld_area_index.* = vars.overworld_area_index_exit.*;
    wordPtr(vars.TM_copy).* = vars.TM_copy_exit.*;
    vars.BG2VOFS_copy2.* = vars.BG2VOFS_copy2_exit.*;
    vars.BG2VOFS_copy.* = vars.BG2VOFS_copy2_exit.*;
    vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy2_exit.*;
    vars.BG1VOFS_copy.* = vars.BG2VOFS_copy2_exit.*;
    vars.BG2HOFS_copy2.* = vars.BG2HOFS_copy2_exit.*;
    vars.BG2HOFS_copy.* = vars.BG2HOFS_copy2_exit.*;
    vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2_exit.*;
    vars.BG1HOFS_copy.* = vars.BG2HOFS_copy2_exit.*;
    vars.link_x_coord.* = vars.link_x_coord_exit.*;
    vars.link_y_coord.* = vars.link_y_coord_exit.*;
    if (vars.dungeon_room_index.* < 0x124)
        vars.link_y_coord.* -%= 0x10;
    wordPtr(vars.link_direction_facing).* = 2;
    if (vars.ow_entrance_value.* == 0xffff) {
        vars.link_y_coord.* +%= 0x20;
        wordPtr(vars.link_direction_facing).* = 0;
    }
    vars.overworld_screen_index.* = vars.overworld_screen_index_exit.*;
    vars.map16_load_src_off.* = vars.map16_load_src_off_exit.*;
    vars.map16_load_var2.* = (vars.map16_load_src_off.* -% 0x400 & 0xf80) >> 7;
    vars.map16_load_dst_off.* = (vars.map16_load_src_off.* -% 0x10 & 0x3e) >> 1;
    vars.camera_y_coord_scroll_low.* = vars.camera_y_coord_scroll_low_exit.*;
    vars.camera_y_coord_scroll_hi.* = vars.camera_y_coord_scroll_low.* -% 2;
    vars.camera_x_coord_scroll_low.* = vars.camera_x_coord_scroll_low_exit.*;
    vars.camera_x_coord_scroll_hi.* = vars.camera_x_coord_scroll_low.* -% 2;
    vars.ow_scroll_vars0.* = vars.ow_scroll_vars0_exit.*;
    vars.up_down_scroll_target.* = vars.up_down_scroll_target_exit.*;
    vars.up_down_scroll_target_end.* = vars.up_down_scroll_target_end_exit.*;
    vars.left_right_scroll_target.* = vars.left_right_scroll_target_exit.*;
    vars.left_right_scroll_target_end.* = vars.left_right_scroll_target_end_exit.*;
    vars.overworld_unk1.* = vars.overworld_unk1_exit.*;
    vars.overworld_unk1_neg.* = vars.overworld_unk1_neg_exit.*;
    vars.overworld_unk3.* = vars.overworld_unk3_exit.*;
    vars.overworld_unk3_neg.* = vars.overworld_unk3_neg_exit.*;
    vars.byte_7E0AA0.* = vars.byte_7EC164.*;
    vars.main_tile_theme_index.* = vars.main_tile_theme_index_exit.*;
    vars.aux_tile_theme_index.* = vars.aux_tile_theme_index_exit.*;
    vars.sprite_graphics_index.* = vars.sprite_graphics_index_exit.*;
}

pub export fn Overworld_EnterSpecialArea() callconv(.c) void {
    vars.num_memorized_tiles.* = 0;
    vars.overworld_area_index_spexit.* = vars.overworld_area_index.*;
    wordPtr(vars.TM_copy_spexit).* = wordPtr(vars.TM_copy).*;
    vars.BG2VOFS_copy2_spexit.* = vars.BG2VOFS_copy2.*;
    vars.BG2HOFS_copy2_spexit.* = vars.BG2HOFS_copy2.*;

    vars.link_x_coord_spexit.* = vars.link_x_coord.*;
    vars.link_y_coord_spexit.* = vars.link_y_coord.*;

    vars.camera_y_coord_scroll_low_spexit.* = vars.camera_y_coord_scroll_low.*;
    vars.camera_x_coord_scroll_low_spexit.* = vars.camera_x_coord_scroll_low.*;
    vars.overworld_screen_index_spexit.* = vars.overworld_screen_index.*;
    vars.map16_load_src_off_spexit.* = vars.map16_load_src_off.*;
    vars.room_scroll_vars0_ystart_spexit.* = vars.ow_scroll_vars0.ystart;
    vars.room_scroll_vars0_yend_spexit.* = vars.ow_scroll_vars0.yend;
    vars.room_scroll_vars0_xstart_spexit.* = vars.ow_scroll_vars0.xstart;
    vars.room_scroll_vars0_xend_spexit.* = vars.ow_scroll_vars0.xend;

    vars.up_down_scroll_target_spexit.* = vars.up_down_scroll_target.*;
    vars.up_down_scroll_target_end_spexit.* = vars.up_down_scroll_target_end.*;
    vars.left_right_scroll_target_spexit.* = vars.left_right_scroll_target.*;
    vars.left_right_scroll_target_end_spexit.* = vars.left_right_scroll_target_end.*;
    vars.overworld_unk1_spexit.* = vars.overworld_unk1.*;
    vars.overworld_unk1_neg_spexit.* = vars.overworld_unk1_neg.*;
    vars.overworld_unk3_spexit.* = vars.overworld_unk3.*;
    vars.overworld_unk3_neg_spexit.* = vars.overworld_unk3_neg.*;
    vars.byte_7EC124.* = vars.byte_7E0AA0.*;
    vars.main_tile_theme_index_spexit.* = vars.main_tile_theme_index.*;
    vars.aux_tile_theme_index_spexit.* = vars.aux_tile_theme_index.*;
    vars.sprite_graphics_index_spexit.* = vars.sprite_graphics_index.*;
    LoadOverworldFromDungeon();
    if (vars.dungeon_room_index.* == 0x1010)
        vars.dungeon_room_index.* = 0x182;

    const roombak: u8 = @truncate(vars.dungeon_room_index.*);
    loPtr(vars.dungeon_room_index).* -%= 0x80;
    const i: usize = loPtr(vars.dungeon_room_index).*;
    vars.link_direction_facing.* = kSpExit_Dir()[i];
    vars.incremental_counter_for_vram.* = 0;
    vars.sprite_graphics_index.* = kSpExit_SprGfx()[i];
    vars.aux_tile_theme_index.* = kSpExit_AuxGfx()[i];
    load_gfx.Overworld_LoadPalettes(kSpExit_PalBg()[i], kSpExit_PalSpr()[i]);

    const j: usize = vars.dungeon_room_index.* & 0x3f;
    vars.overworld_offset_base_y.* = kSpExit_Top()[j];
    vars.overworld_offset_base_x.* = kSpExit_LeftEdgeOfMap()[j] >> 3;
    vars.overworld_offset_mask_y.* = 0x3f0;
    vars.overworld_offset_mask_x.* = 0x3f0 >> 3;

    const k: usize = vars.dungeon_room_index.* & 0x7f;
    vars.ow_scroll_vars0.ystart = kSpExit_Top()[k];
    vars.ow_scroll_vars0.yend = kSpExit_Bottom()[k];
    vars.ow_scroll_vars0.xstart = kSpExit_Left()[k];
    vars.ow_scroll_vars0.xend = kSpExit_Right()[k];
    vars.up_down_scroll_target.* = @bitCast(kSpExit_Tab4()[k]);
    vars.up_down_scroll_target_end.* = @bitCast(kSpExit_Tab5()[k]);
    vars.left_right_scroll_target.* = @bitCast(kSpExit_Tab6()[k]);
    vars.left_right_scroll_target_end.* = @bitCast(kSpExit_Tab7()[k]);

    loPtr(vars.dungeon_room_index).* = roombak;
    load_gfx.Palette_SpecialOw();
    // The camera's range is the special area's from here.
    snapCameraX();
}

pub export fn LoadOverworldFromSpecialOverworld() callconv(.c) void {
    vars.num_memorized_tiles.* = 0;
    vars.overworld_area_index.* = vars.overworld_area_index_spexit.*;
    wordPtr(vars.TM_copy).* = wordPtr(vars.TM_copy_spexit).*;
    vars.BG2VOFS_copy2.* = vars.BG2VOFS_copy2_spexit.*;
    vars.BG2VOFS_copy.* = vars.BG2VOFS_copy2_spexit.*;
    vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy2_spexit.*;
    vars.BG1VOFS_copy.* = vars.BG2VOFS_copy2_spexit.*;
    vars.BG2HOFS_copy2.* = vars.BG2HOFS_copy2_spexit.*;
    vars.BG2HOFS_copy.* = vars.BG2HOFS_copy2_spexit.*;
    vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2_spexit.*;
    vars.BG1HOFS_copy.* = vars.BG2HOFS_copy2_spexit.*;
    vars.link_x_coord.* = vars.link_x_coord_spexit.*;
    vars.link_y_coord.* = vars.link_y_coord_spexit.*;
    vars.overworld_screen_index.* = vars.overworld_screen_index_spexit.*;
    vars.map16_load_src_off.* = vars.map16_load_src_off_spexit.*;
    vars.map16_load_var2.* = (vars.map16_load_src_off.* -% 0x400 & 0xf80) >> 7;
    vars.map16_load_dst_off.* = (vars.map16_load_src_off.* -% 0x10 & 0x3e) >> 1;
    vars.camera_y_coord_scroll_low.* = vars.camera_y_coord_scroll_low_spexit.*;
    vars.camera_y_coord_scroll_hi.* = vars.camera_y_coord_scroll_low.* -% 2;
    vars.camera_x_coord_scroll_low.* = vars.camera_x_coord_scroll_low_spexit.*;
    vars.camera_x_coord_scroll_hi.* = vars.camera_x_coord_scroll_low.* -% 2;
    vars.ow_scroll_vars0.ystart = vars.room_scroll_vars0_ystart_spexit.*;
    vars.ow_scroll_vars0.yend = vars.room_scroll_vars0_yend_spexit.*;
    vars.ow_scroll_vars0.xstart = vars.room_scroll_vars0_xstart_spexit.*;
    vars.ow_scroll_vars0.xend = vars.room_scroll_vars0_xend_spexit.*;
    vars.up_down_scroll_target.* = vars.up_down_scroll_target_spexit.*;
    vars.up_down_scroll_target_end.* = vars.up_down_scroll_target_end_spexit.*;
    vars.left_right_scroll_target.* = vars.left_right_scroll_target_spexit.*;
    vars.left_right_scroll_target_end.* = vars.left_right_scroll_target_end_spexit.*;
    vars.overworld_unk1.* = vars.overworld_unk1_spexit.*;
    vars.overworld_unk1_neg.* = vars.overworld_unk1_neg_spexit.*;
    vars.overworld_unk3.* = vars.overworld_unk3_spexit.*;
    vars.overworld_unk3_neg.* = vars.overworld_unk3_neg_spexit.*;
    vars.byte_7E0AA0.* = vars.byte_7EC124.*;
    vars.main_tile_theme_index.* = vars.main_tile_theme_index_spexit.*;
    vars.aux_tile_theme_index.* = vars.aux_tile_theme_index_spexit.*;
    vars.sprite_graphics_index.* = vars.sprite_graphics_index_spexit.*;
    const sc: u8 = @truncate(vars.overworld_screen_index.*);
    load_gfx.Overworld_LoadPalettes(kOverworldBgPalettes()[sc], vars.overworld_sprite_palettes[sc]);
    load_gfx.Palette_SpecialOw();
    vars.link_quadrant_x.* = 0;
    vars.link_quadrant_y.* = 2;
    vars.quadrant_fullsize_x.* = 2;
    vars.quadrant_fullsize_y.* = 2;
    vars.player_oam_x_offset.* = 0x80;
    vars.player_oam_y_offset.* = 0x80;
    vars.link_direction_mask_a.* = 0xf;
    vars.link_direction_mask_b.* = 0xf;
    loPtr(vars.link_z_coord).* = 0xff;
    vars.link_actual_vel_z.* = 0xff;
    Link_ResetSwimmingState();
    Overworld_LoadGFXAndScreenSize();
    loPtr(vars.overworld_right_bottom_bound_for_scroll).* = 228;
    vars.overworld_area_is_big.* &= 0xff;
}

pub export fn FluteMenu_LoadTransport() callconv(.c) void {
    vars.num_memorized_tiles.* = 0;
    const k: c_int = vars.birdtravel_var1[0];
    wordPtr(&vars.birdtravel_var1[0]).* *%= 2;
    Overworld_LoadBirdTravelPos(k);
}

pub export fn Overworld_LoadBirdTravelPos(k_in: c_int) callconv(.c) void {
    const k: usize = @intCast(k_in);
    vars.BG2VOFS_copy.* = kBirdTravel_ScrollY()[k];
    vars.BG1VOFS_copy.* = vars.BG2VOFS_copy.*;
    vars.BG2VOFS_copy2.* = vars.BG2VOFS_copy.*;
    vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy.*;
    vars.BG2HOFS_copy.* = kBirdTravel_ScrollX()[k];
    vars.BG1HOFS_copy.* = vars.BG2HOFS_copy.*;
    vars.BG2HOFS_copy2.* = vars.BG2HOFS_copy.*;
    vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy.*;
    vars.link_y_coord.* = kBirdTravel_LinkYCoord()[k];
    vars.link_x_coord.* = kBirdTravel_LinkXCoord()[k];
    vars.overworld_unk1.* = @bitCast(@as(i16, kBirdTravel_Unk1()[k]));
    vars.overworld_unk3.* = @bitCast(@as(i16, kBirdTravel_Unk3()[k]));
    vars.overworld_unk1_neg.* = 0 -% vars.overworld_unk1.*;
    vars.overworld_unk3_neg.* = 0 -% vars.overworld_unk3.*;
    vars.overworld_screen_index.* = kBirdTravel_ScreenIndex()[k];
    vars.overworld_area_index.* = vars.overworld_screen_index.*;

    vars.map16_load_src_off.* = kBirdTravel_Map16LoadSrcOff()[k];
    vars.map16_load_var2.* = (vars.map16_load_src_off.* -% 0x400 & 0xf80) >> 7;
    vars.map16_load_dst_off.* = (vars.map16_load_src_off.* -% 0x10 & 0x3e) >> 1;
    vars.camera_y_coord_scroll_low.* = kBirdTravel_CameraYScroll()[k];
    vars.camera_y_coord_scroll_hi.* = vars.camera_y_coord_scroll_low.* -% 2;
    vars.camera_x_coord_scroll_low.* = kBirdTravel_CameraXScroll()[k];
    vars.camera_x_coord_scroll_hi.* = vars.camera_x_coord_scroll_low.* -% 2;
    vars.ow_entrance_value.* = 0;
    vars.big_rock_starting_address.* = 0;
    Overworld_LoadNewScreenProperties();
    Sprite_ResetAll();
    Sprite_ReloadAll_Overworld();
    vars.is_standing_in_doorway.* = 0;
    Dungeon_ResetTorchBackgroundAndPlayerInner();
}

pub export fn FluteMenu_LoadSelectedScreenPalettes() callconv(.c) void {
    load_gfx.OverworldLoadScreensPaletteSet();
    const sc: u8 = @truncate(vars.overworld_screen_index.*);
    load_gfx.Overworld_LoadPalettes(kOverworldBgPalettes()[sc], vars.overworld_sprite_palettes[sc]);
    load_gfx.Palette_SetOwBgColor();
    load_gfx.Overworld_LoadPalettesInner();
}

pub export fn FindPartnerWhirlpoolExit() callconv(.c) void {
    const j = FindInWordArray(kWhirlpoolAreas(), vars.overworld_screen_index.*, @intCast(kWhirlpoolAreas_SIZE() / 2));
    if (j >= 0) {
        vars.num_memorized_tiles.* = 0;
        Overworld_LoadBirdTravelPos(j + 9);
    }
}

pub export fn Overworld_LoadAmbientOverlay(load_map_data: bool) callconv(.c) void {
    const bak1 = vars.map16_load_src_off.*;
    const bak2 = vars.map16_load_dst_off.*;
    const bak3 = vars.map16_load_var2.*;

    if (kOverworldMapIsSmall()[loPtr(vars.overworld_screen_index).*] != 0) {
        vars.map16_load_src_off.* = 0x390;
        vars.map16_load_var2.* = (0x390 -% @as(u16, 0x400) & 0xf80) >> 7;
        vars.map16_load_dst_off.* = (0x390 -% @as(u16, 0x10) & 0x3e) >> 1;
    }

    if (load_map_data)
        Overworld_DrawQuadrantsAndOverlays();

    Map16ToMap8(g_ram[0x2000..].ptr, 0);
    vars.map16_load_var2.* = bak3;
    vars.map16_load_dst_off.* = bak2;
    vars.map16_load_src_off.* = bak1;

    vars.nmi_subroutine_index.* = 4;
    vars.nmi_disable_core_updates.* = 4;
    vars.submodule_index.* +%= 1;
    vars.INIDISP_copy.* = 0;
}

pub export fn Overworld_LoadAmbientOverlayFalse() callconv(.c) void {
    Overworld_LoadAmbientOverlay(false);
}

pub export fn Overworld_LoadAndBuildScreen() callconv(.c) void {
    Overworld_LoadAmbientOverlay(true);
}

pub export fn Module08_02_LoadAndAdvance() callconv(.c) void {
    Overworld_LoadAndBuildScreen();
    vars.main_module_index.* = 16;
    vars.submodule_index.* = 0;
    vars.subsubmodule_index.* = 0;
}

pub export fn Overworld_DrawQuadrantsAndOverlays() callconv(.c) void {
    Overworld_DecompressAndDrawAllQuadrants();
    for (0..16 * 4) |i| vars.dung_bg1[i] = 0xdc4;
    var pos = vars.ow_entrance_value.*;
    if (pos != 0 and pos != 0xffff) {
        if (pos < 0x8000) {
            vars.dung_bg2[pos >> 1] = 0xDA4;
            Overworld_Memorize_Map16_Change(pos, 0xda4);
            vars.dung_bg2[(pos +% 2) >> 1] = 0xda6;
            Overworld_Memorize_Map16_Change(pos +% 2, 0xda6);
        } else {
            pos &= 0x1fff;
            vars.dung_bg2[pos >> 1] = 0xdb4;
            Overworld_Memorize_Map16_Change(pos, 0xdb4);
            vars.dung_bg2[(pos +% 2) >> 1] = 0xdb5;
            Overworld_Memorize_Map16_Change(pos +% 2, 0xdb5);
        }
        vars.ow_entrance_value.* = 0;
    }
    Overworld_HandleOverlaysAndBombDoors();
}

pub export fn Overworld_HandleOverlaysAndBombDoors() callconv(.c) void {
    if (vars.overworld_screen_index.* == 0x33) {
        vars.dung_bg2[340] = 0x20f;
    } else if (vars.overworld_screen_index.* == 0x2f) {
        vars.dung_bg2[1497] = 0x20f;
    }
    const sc = loPtr(vars.overworld_screen_index).*;
    if (sc < 0x80 and vars.save_ow_event_info[sc] & 0x20 != 0)
        Overworld_LoadEventOverlay();
    if (vars.save_ow_event_info[sc] & 2 != 0) {
        const pos = tables.kSecondaryOverlayPerOw[vars.overworld_screen_index.*] >> 1;
        vars.dung_bg2[pos + 0] = 0xdb4;
        vars.dung_bg2[pos + 1] = 0xdb5;
    }
}

pub export fn TriggerAndFinishMapLoadStripe_Y(n_in: c_int) callconv(.c) void {
    var n = n_in;
    loPtr(vars.overworld_screen_trans_dir_bits2).* = 8;
    vars.nmi_subroutine_index.* = 3;
    var dst: [*]align(1) u16 = @ptrCast(&vars.uvram.data);
    dst[0] = 0x80;
    dst += 1;
    while (true) {
        dst = BufferAndBuildMap16Stripes_Y(dst);
        vars.map16_load_src_off.* -%= 0x80;
        vars.map16_load_var2.* = (vars.map16_load_var2.* -% 1) & 0x1f;
        n -= 1;
        if (n == 0) break;
    }
    dst[0] = 0xffff;
}

pub export fn TriggerAndFinishMapLoadStripe_X(n_in: c_int) callconv(.c) void {
    var n = n_in;
    loPtr(vars.overworld_screen_trans_dir_bits2).* = 2;
    vars.nmi_subroutine_index.* = 3;
    var dst: [*]align(1) u16 = @ptrCast(&vars.uvram.data);
    dst[0] = 0x8040;
    dst += 1;
    while (true) {
        dst = BufferAndBuildMap16Stripes_X(dst);
        vars.map16_load_src_off.* -%= 2;
        vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* -% 1) & 0x1f;
        n -= 1;
        if (n == 0) break;
    }
    dst[0] = 0xffff;
}

pub export fn SomeTileMapChange() callconv(.c) void {
    Overworld_DecompressAndDrawAllQuadrants();
    for (0..64) |i| vars.dung_bg1[i] = 0xdc4;
    Overworld_HandleOverlaysAndBombDoors();
    vars.submodule_index.* +%= 1;
}

pub export fn CreateInitialNewScreenMapToScroll() callconv(.c) void {
    if (kOverworldMapIsSmall()[loPtr(vars.overworld_screen_index).*] == 0) {
        switch (loPtr(vars.overworld_screen_trans_dir_bits2).*) {
            1 => CreateInitialOWScreenView_Big_East(),
            2 => CreateInitialOWScreenView_Big_West(),
            4 => CreateInitialOWScreenView_Big_South(),
            8 => CreateInitialOWScreenView_Big_North(),
            else => vars.submodule_index.* = 0,
        }
    } else {
        switch (loPtr(vars.overworld_screen_trans_dir_bits2).*) {
            1 => CreateInitialOWScreenView_Small_East(),
            2 => CreateInitialOWScreenView_Small_West(),
            4 => CreateInitialOWScreenView_Small_South(),
            8 => CreateInitialOWScreenView_Small_North(),
            else => vars.submodule_index.* = 0,
        }
    }
}

pub export fn CreateInitialOWScreenView_Big_North() callconv(.c) void {
    vars.map16_load_src_off.* +%= 0x380;
    vars.map16_load_var2.* = 31;
    TriggerAndFinishMapLoadStripe_Y(7);
}

pub export fn CreateInitialOWScreenView_Big_South() callconv(.c) void {
    var pos = vars.map16_load_src_off.*;
    while (pos >= 0x80) pos -%= 0x80;
    vars.map16_load_src_off.* = pos +% 0x780;
    vars.map16_load_var2.* = 7;
    TriggerAndFinishMapLoadStripe_Y(8);
    vars.map16_load_var2.* = (vars.map16_load_var2.* +% 9) & 0x1f;
    vars.map16_load_src_off.* -%= 0xB80;
}

pub export fn CreateInitialOWScreenView_Big_West() callconv(.c) void {
    vars.map16_load_src_off.* +%= 14;
    vars.map16_load_dst_off.* = 31;
    TriggerAndFinishMapLoadStripe_X(7);
}

pub export fn CreateInitialOWScreenView_Big_East() callconv(.c) void {
    vars.map16_load_src_off.* = vars.map16_load_src_off.* -% 0x60 +% 0x1e;
    vars.map16_load_dst_off.* = 7;
    loadInitialEastColumns();
}

/// The 8 columns an eastward scroll loads before it starts, rightmost first,
/// leaving the next load at the column after them. They come in 512 pixels
/// after the same columns of the area being left, and the widescreen camera
/// starts that area a margin later, so the last of them is on screen, at the
/// left edge, until the scroll's moved past it. Widescreen holds that one
/// back for the scroll to load with its first column instead.
fn loadInitialEastColumns() void {
    const hold: u16 = @intFromBool(wideCameraOn() and wideScrollMargin() != 0);
    g_wide_held_columns = hold;
    vars.map16_load_src_off.* -%= 2 * hold;
    vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* -% hold) & 0x1f;
    TriggerAndFinishMapLoadStripe_X(8 - @as(c_int, hold));
    vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* +% 9 -% hold) & 0x1f;
    vars.map16_load_src_off.* -%= 0x2e +% 2 * hold;
}

pub export fn CreateInitialOWScreenView_Small_North() callconv(.c) void {
    vars.orange_blue_barrier_state.* = vars.map16_load_src_off.* -% 0x700;
    vars.word_7EC174.* = vars.map16_load_dst_off.*;
    vars.word_7EC176.* = 10;
    vars.map16_load_src_off.* = 0x1390;
    vars.map16_load_dst_off.* = 0;
    vars.map16_load_var2.* = 31;
    TriggerAndFinishMapLoadStripe_Y(7);
}

pub export fn CreateInitialOWScreenView_Small_South() callconv(.c) void {
    vars.orange_blue_barrier_state.* = loPtr(vars.map16_load_src_off).*;
    vars.word_7EC174.* = vars.map16_load_dst_off.*;
    vars.word_7EC176.* = 24;
    vars.map16_load_src_off.* = 0x790;
    vars.map16_load_dst_off.* = 0;
    vars.map16_load_var2.* = 7;
    TriggerAndFinishMapLoadStripe_Y(8);
    vars.map16_load_var2.* = (vars.map16_load_var2.* +% 9) & 0x1f;
    vars.map16_load_src_off.* -%= 0xB80;
}

pub export fn CreateInitialOWScreenView_Small_West() callconv(.c) void {
    vars.orange_blue_barrier_state.* = vars.map16_load_src_off.* -% 0x20;
    vars.word_7EC174.* = 8;
    vars.word_7EC176.* = vars.map16_load_var2.*;
    vars.map16_load_src_off.* = 0x44e;
    vars.map16_load_var2.* = 0;
    vars.map16_load_dst_off.* = 31;
    TriggerAndFinishMapLoadStripe_X(7);
}

pub export fn CreateInitialOWScreenView_Small_East() callconv(.c) void {
    vars.orange_blue_barrier_state.* = vars.map16_load_src_off.* -% 0x60;
    vars.word_7EC174.* = 0x18;
    vars.word_7EC176.* = vars.map16_load_var2.*;
    vars.map16_load_src_off.* = 0x41e;
    vars.map16_load_var2.* = 0;
    vars.map16_load_dst_off.* = 7;
    loadInitialEastColumns();
}

pub export fn OverworldTransitionScrollAndLoadMap() callconv(.c) void {
    const base: [*]align(1) u16 = @ptrCast(&vars.uvram.data);
    var dst: [*]align(1) u16 = base;
    switch (loPtr(vars.overworld_screen_trans_dir_bits2).*) {
        1 => dst = BuildFullStripeDuringTransition_East(dst),
        2 => dst = BuildFullStripeDuringTransition_West(dst),
        4 => dst = BuildFullStripeDuringTransition_South(dst),
        8 => dst = BuildFullStripeDuringTransition_North(dst),
        else => vars.submodule_index.* = 0,
    }
    dst[0] = 0xffff;
    dst[1] = 0xffff;
    if (dst != base)
        vars.nmi_subroutine_index.* = 3;
}

fn BuildFullStripeDuringTransition_North(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    dst[0] = 0x80;
    dst += 1;
    dst = BufferAndBuildMap16Stripes_Y(dst);
    vars.map16_load_src_off.* -%= 0x80;
    vars.map16_load_var2.* = (vars.map16_load_var2.* -% 1) & 0x1f;
    return dst;
}

fn BuildFullStripeDuringTransition_South(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    dst[0] = 0x80;
    dst += 1;
    dst = BufferAndBuildMap16Stripes_Y(dst);
    vars.map16_load_src_off.* +%= 0x80;
    vars.map16_load_var2.* = (vars.map16_load_var2.* +% 1) & 0x1f;
    return dst;
}

fn BuildFullStripeDuringTransition_West(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    dst[0] = 0x8040;
    dst += 1;
    dst = BufferAndBuildMap16Stripes_X(dst);
    vars.map16_load_src_off.* -%= 2;
    vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* -% 1) & 0x1f;
    return dst;
}

fn BuildFullStripeDuringTransition_East(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    dst[0] = 0x8040;
    dst += 1;
    dst = BufferAndBuildMap16Stripes_X(dst);
    vars.map16_load_src_off.* +%= 2;
    vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* +% 1) & 0x1f;
    return dst;
}

pub export fn OverworldHandleMapScroll() callconv(.c) void {
    const base: [*]align(1) u16 = @ptrCast(&vars.uvram.data);
    var dst: [*]align(1) u16 = base;
    switch (loPtr(vars.overworld_screen_trans_dir_bits2).*) {
        1 => {
            dst = CheckForNewlyLoadedMapAreas_East(dst);
            loPtr(vars.overworld_screen_trans_dir_bits2).* = 0;
        },
        2 => {
            dst = CheckForNewlyLoadedMapAreas_West(dst);
            loPtr(vars.overworld_screen_trans_dir_bits2).* = 0;
        },
        4 => {
            dst = CheckForNewlyLoadedMapAreas_South(dst);
            loPtr(vars.overworld_screen_trans_dir_bits2).* = 0;
        },
        5, 6 => {
            dst = CheckForNewlyLoadedMapAreas_South(dst);
            loPtr(vars.overworld_screen_trans_dir_bits2).* &= 3;
        },
        8 => {
            dst = CheckForNewlyLoadedMapAreas_North(dst);
            loPtr(vars.overworld_screen_trans_dir_bits2).* = 0;
        },
        9, 10 => {
            dst = CheckForNewlyLoadedMapAreas_North(dst);
            loPtr(vars.overworld_screen_trans_dir_bits2).* &= 3;
        },
        else => vars.submodule_index.* = 0,
    }
    dst[0] = 0xffff;
    dst[1] = 0xffff;
    if (dst != base)
        vars.nmi_subroutine_index.* = 3;
    vars.overworld_screen_transition.* = @truncate(vars.overworld_screen_trans_dir_bits2.*);
}

fn CheckForNewlyLoadedMapAreas_North(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    if (@as(i16, @bitCast(vars.map16_load_src_off.* -% 0x80)) < 0)
        return dst;
    if (kOverworldMapIsSmall()[vars.overworld_screen_index.*] == 0) {
        dst[0] = 0x80;
        dst += 1;
        dst = BufferAndBuildMap16Stripes_Y(dst);
    }
    vars.map16_load_src_off.* -%= 0x80;
    vars.map16_load_var2.* = (vars.map16_load_var2.* -% 1) & 0x1f;
    return dst;
}

fn CheckForNewlyLoadedMapAreas_South(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    if (vars.map16_load_src_off.* >= 0x1800)
        return dst;
    if (kOverworldMapIsSmall()[vars.overworld_screen_index.*] == 0) {
        dst[0] = 0x80;
        dst += 1;
        dst = BufferAndBuildMap16Stripes_Y(dst);
    }
    vars.map16_load_src_off.* +%= 0x80;
    vars.map16_load_var2.* = (vars.map16_load_var2.* +% 1) & 0x1f;
    return dst;
}

fn CheckForNewlyLoadedMapAreas_West(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    var pos = vars.map16_load_src_off.*;
    while (pos >= 0x80) pos -%= 0x80;
    if (pos == 0)
        return dst;
    if (kOverworldMapIsSmall()[vars.overworld_screen_index.*] == 0) {
        dst[0] = 0x8040;
        dst += 1;
        dst = BufferAndBuildMap16Stripes_X(dst);
    }
    vars.map16_load_src_off.* -%= 2;
    vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* -% 1) & 0x1f;
    return dst;
}

fn CheckForNewlyLoadedMapAreas_East(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    var pos = vars.map16_load_src_off.*;
    while (pos >= 0x80) pos -%= 0x80;
    if (pos >= 0x60)
        return dst;
    if (kOverworldMapIsSmall()[vars.overworld_screen_index.*] == 0) {
        dst[0] = 0x8040;
        dst += 1;
        dst = BufferAndBuildMap16Stripes_X(dst);
    }
    vars.map16_load_src_off.* +%= 2;
    vars.map16_load_dst_off.* = (vars.map16_load_dst_off.* +% 1) & 0x1f;
    return dst;
}

fn BufferAndBuildMap16Stripes_X(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    var pos: u16 = vars.map16_load_src_off.* -%
        tables.kOverworld_DrawStrip_Tab[vars.overworld_screen_trans_dir_bits2.* >> 1 & 1];
    var d: usize = vars.map16_load_var2.*;
    const tmp: [*]align(1) u16 = vars.dung_replacement_tile_state;
    for (0..32) |_| {
        tmp[d] = if (pos >= 0x2000) 0 else vars.dung_bg2[pos >> 1];
        d = (d + 1) & 0x1f;
        pos +%= 128;
    }
    const map8 = GetMap16toMap8Table();
    var r0: u16 = 0;
    var of = vars.map16_load_dst_off.*;
    if (of >= 0x10) {
        of &= 0xf;
        r0 = 0x400;
    }
    r0 +%= of *% 2;
    var tp: [*]align(1) u16 = tmp;
    for (0..2) |_| {
        dst[0] = r0;
        dst[33] = r0 +% 1;
        dst += 1;
        for (0..16) |_| {
            const k: usize = tp[0];
            tp += 1;
            const s = map8 + k * 4;
            dst[0] = s[0];
            dst[33] = s[1];
            dst[1] = s[2];
            dst[34] = s[3];
            dst += 2;
        }
        dst += 33;
        r0 +%= 0x800;
    }
    return dst;
}

fn BufferAndBuildMap16Stripes_Y(dst_in: [*]align(1) u16) [*]align(1) u16 {
    var dst = dst_in;
    var pos: u16 = vars.map16_load_src_off.* -%
        tables.kOverworld_DrawStrip_Tab[1 + (vars.overworld_screen_trans_dir_bits2.* >> 2 & 1)];
    var d: usize = vars.map16_load_dst_off.*;
    const tmp: [*]align(1) u16 = vars.dung_replacement_tile_state;
    for (0..32) |_| {
        tmp[d] = if (pos >= 0x2000) 0 else vars.dung_bg2[pos >> 1];
        pos +%= 2;
        d = (d + 1) & 0x1f;
    }
    const map8 = GetMap16toMap8Table();
    var r0: u16 = 0;
    var of = vars.map16_load_var2.*;
    if (of >= 0x10) {
        of &= 0xf;
        r0 = 0x800;
    }
    r0 +%= of *% 64;
    var tp: [*]align(1) u16 = tmp;
    for (0..2) |_| {
        dst[0] = r0;
        dst += 1;
        for (0..16) |_| {
            const k: usize = tp[0];
            tp += 1;
            const s = map8 + k * 4;
            dst[0] = s[0];
            dst[32] = s[2];
            dst[1] = s[1];
            dst[33] = s[3];
            dst += 2;
        }
        dst += 32;
        r0 +%= 0x400;
    }
    return dst;
}

pub export fn Overworld_DecompressAndDrawAllQuadrants() callconv(.c) void {
    const si: c_int = @intCast(vars.overworld_screen_index.*);
    Overworld_DecompressAndDrawOneQuadrant(@ptrCast(g_ram[0x2000..].ptr), si + 0);
    Overworld_DecompressAndDrawOneQuadrant(@ptrCast(g_ram[0x2040..].ptr), si + 1);
    Overworld_DecompressAndDrawOneQuadrant(@ptrCast(g_ram[0x3000..].ptr), si + 8);
    Overworld_DecompressAndDrawOneQuadrant(@ptrCast(g_ram[0x3040..].ptr), si + 9);
}

fn GetOverworldHibytes(i: c_int) [*]const u8 {
    return kOverworld_Hibytes_Comp(i).ptr.?;
}

fn GetOverworldLobytes(i: c_int) [*]const u8 {
    return kOverworld_Lobytes_Comp(i).ptr.?;
}

pub export fn Overworld_DecompressAndDrawOneQuadrant(dst_in: [*]align(1) u16, screen: c_int) callconv(.c) void {
    var dst = dst_in;
    _ = Decompress_bank02(g_ram[0x14400..].ptr, GetOverworldHibytes(screen));
    for (0..256) |i| g_ram[0x14001 + i * 2] = g_ram[0x14400 + i];

    _ = Decompress_bank02(g_ram[0x14400..].ptr, GetOverworldLobytes(screen));
    for (0..256) |i| g_ram[0x14000 + i * 2] = g_ram[0x14400 + i];

    vars.map16_decode_last.* = 0xffff;

    var src: [*]align(1) const u16 = @ptrCast(&g_ram[0x14000]);
    for (0..16) |_| {
        for (0..16) |_| {
            Overworld_ParseMap32Definition(dst, src[0] *% 2);
            src += 1;
            dst += 2;
        }
        dst += 96;
    }
}

pub export fn Overworld_ParseMap32Definition(dst: [*]align(1) u16, input: u16) callconv(.c) void {
    const a = input & ~@as(u16, 7);
    if (a != vars.map16_decode_last.*) {
        vars.map16_decode_last.* = a;
        vars.map16_decode_tmp.* = a >> 1;
        const x: usize = (a >> 1) + (a >> 2);
        inline for (.{
            .{ kMap32ToMap16_0, "map16_decode_0" },
            .{ kMap32ToMap16_1, "map16_decode_1" },
            .{ kMap32ToMap16_2, "map16_decode_2" },
            .{ kMap32ToMap16_3, "map16_decode_3" },
        }) |pair| {
            const ov = pair[0]() + x;
            const out = @field(vars, pair[1]);
            out[0] = ov[0];
            out[2] = ov[1];
            out[4] = ov[2];
            out[6] = ov[3];
            out[1] = ov[4] >> 4;
            out[3] = ov[4] & 0xf;
            out[5] = ov[5] >> 4;
            out[7] = ov[5] & 0xf;
        }
    }
    const i: usize = input & 7;
    dst[0] = wordPtr(&vars.map16_decode_0[i]).*;
    dst[64] = wordPtr(&vars.map16_decode_2[i]).*;
    dst[1] = wordPtr(&vars.map16_decode_1[i]).*;
    dst[65] = wordPtr(&vars.map16_decode_3[i]).*;
}

pub export fn OverworldLoad_LoadSubOverlayMap32() callconv(.c) void {
    const si: c_int = @intCast(vars.overworld_screen_index.*);
    Overworld_DecompressAndDrawOneQuadrant(@ptrCast(g_ram[0x4000..].ptr), si);
}

pub export fn LoadOverworldOverlay() callconv(.c) void {
    OverworldLoad_LoadSubOverlayMap32();
    Map16ToMap8(g_ram[0x4000..].ptr, 0x1000);
    vars.nmi_subroutine_index.* = 4;
    vars.nmi_disable_core_updates.* = 4;
    vars.submodule_index.* +%= 1;
}

pub export fn Map16ToMap8(src: [*]const u8, r20: c_int) callconv(.c) void {
    vars.map16_load_src_off.* +%= 0x1000;
    var n: c_int = 32;
    var r14: c_int = 0;
    var r10: [*]align(1) u16 = @ptrCast(vars.word_7F4000);
    while (true) {
        OverworldCopyMap16ToBuffer(src, @intCast(r20), r14, r10);
        r14 += 0x100;
        r10 += 2;
        vars.map16_load_src_off.* -%= 0x80;
        vars.map16_load_var2.* = (vars.map16_load_var2.* -% 1) & 0x1f;
        n -= 1;
        if (n == 0) break;
    }
}

pub export fn OverworldCopyMap16ToBuffer(src: [*]const u8, r20: u16, r14_in: c_int, r10_in: [*]align(1) u16) callconv(.c) void {
    var r14 = r14_in;
    var r10 = r10_in;
    const map8 = GetMap16toMap8Table();

    var yr: usize = vars.map16_load_src_off.* -% 0x410 & 0x1fff;
    var xr: usize = vars.map16_load_dst_off.*;
    const tmp: [*]align(1) u16 = vars.dung_replacement_tile_state;
    var n: c_int = 32;
    while (true) {
        tmp[xr] = @as(*align(1) const u16, @ptrCast(&src[yr])).*;
        xr = (xr + 1) & 0x1f;
        yr = (yr + 2) & 0x1fff;
        n -= 1;
        if (n == 0) break;
    }

    var r0: u16 = 0;
    var of = vars.map16_load_var2.*;
    if (of >= 0x10) {
        of &= 0xf;
        r0 = 0x800;
    }
    r0 +%= of *% 64;

    var tp: [*]align(1) u16 = tmp;
    for (0..2) |_| {
        r10[0] = r0 | r20;
        r10 += 1;
        for (0..16) |_| {
            const m = map8 + 4 * @as(usize, tp[0]);
            tp += 1;
            const base: usize = @intCast(r14);
            wordPtr(&vars.dung_bg2_attr_table[base]).* = m[0];
            wordPtr(&vars.dung_bg2_attr_table[base + 64]).* = m[2];
            wordPtr(&vars.dung_bg2_attr_table[base + 2]).* = m[1];
            wordPtr(&vars.dung_bg2_attr_table[base + 66]).* = m[3];
            r14 += 4;
        }
        r0 +%= 0x400;
        r14 += 0x40;
    }
}

pub export fn MirrorBonk_RecoverChangedTiles() callconv(.c) void {
    const n = vars.num_memorized_tiles.* >> 1;
    var i: usize = 0;
    while (i != n) : (i += 1) {
        const pos = vars.memorized_tile_addr[i];
        vars.dung_bg2[pos >> 1] = vars.memorized_tile_value[i];
    }
}

pub export fn DecompressEnemyDamageSubclasses() callconv(.c) void {
    var tmp: [*]u8 = g_ram[0x14000..].ptr;
    @memcpy(tmp[0..kEnemyDamageData_SIZE()], kEnemyDamageData()[0..kEnemyDamageData_SIZE()]);
    var i: usize = 0;
    while (i < 0x1000) : (i += 2) {
        const t = tmp[0];
        tmp += 1;
        vars.enemy_damage_data[i + 0] = t >> 4;
        vars.enemy_damage_data[i + 1] = t & 0xf;
    }
}

pub export fn Decompress_bank02(dst_in: [*]u8, src_in: [*]const u8) callconv(.c) c_int {
    var dst = dst_in;
    var src = src_in;
    const dst_org = dst;
    var len: c_int = undefined;
    while (true) {
        var cmd = src[0];
        src += 1;
        if (cmd == 0xff)
            return @intCast(@intFromPtr(dst) - @intFromPtr(dst_org));
        if ((cmd & 0xe0) != 0xe0) {
            len = @as(c_int, cmd & 0x1f) + 1;
            cmd &= 0xe0;
        } else {
            len = src[0];
            src += 1;
            len += (@as(c_int, cmd & 3) << 8) + 1;
            cmd = (cmd << 3) & 0xe0;
        }
        if (cmd == 0) {
            while (true) {
                dst[0] = src[0];
                dst += 1;
                src += 1;
                len -= 1;
                if (len == 0) break;
            }
        } else if (cmd & 0x80 != 0) {
            var offs: u32 = @as(u32, src[0]) << 8;
            src += 1;
            offs |= src[0];
            src += 1;
            while (true) {
                dst[0] = dst_org[offs];
                offs +%= 1;
                dst += 1;
                len -= 1;
                if (len == 0) break;
            }
        } else if (cmd & 0x40 == 0) {
            const v = src[0];
            src += 1;
            while (true) {
                dst[0] = v;
                dst += 1;
                len -= 1;
                if (len == 0) break;
            }
        } else if (cmd & 0x20 == 0) {
            const lo = src[0];
            src += 1;
            const hi = src[0];
            src += 1;
            while (true) {
                dst[0] = lo;
                dst += 1;
                len -= 1;
                if (len == 0) break;
                dst[0] = hi;
                dst += 1;
                len -= 1;
                if (len == 0) break;
            }
        } else {
            // copy bytes with the byte incrementing by 1 in between
            var v = src[0];
            src += 1;
            while (true) {
                dst[0] = v;
                dst += 1;
                v +%= 1;
                len -= 1;
                if (len == 0) break;
            }
        }
    }
}

pub export fn Overworld_ReadTileAttribute(x: u16, y: u16) callconv(.c) u8 {
    var t: usize = (x -% vars.overworld_offset_base_x.*) & vars.overworld_offset_mask_x.*;
    t |= @as(usize, (y -% vars.overworld_offset_base_y.*) & vars.overworld_offset_mask_y.*) << 3;
    return kSomeTileAttr()[vars.dung_bg2[t >> 1]];
}

pub export fn Overworld_SetFixedColAndScroll() callconv(.c) void {
    vars.TS_copy.* = 0;
    var p: u16 = 0x19C6;
    const si = vars.overworld_screen_index.*;
    if (si == 0x80) {
        if (vars.dungeon_room_index.* == 0x181) {
            vars.TS_copy.* = 1;
            p = if (si & 0x40 != 0) 0x2A32 else 0x2669;
        }
    } else if (si != 0x81) {
        p = 0;
        if (si != 0x5b and (si & 0xbf) != 3 and (si & 0xbf) != 5 and (si & 0xbf) != 7)
            p = if (si & 0x40 != 0) 0x2A32 else 0x2669;
    }
    vars.main_palette_buffer[0] = p;
    vars.aux_palette_buffer[0] = p;
    vars.main_palette_buffer[32] = p;
    vars.aux_palette_buffer[32] = p;

    vars.COLDATA_copy0.* = 0x20;
    vars.COLDATA_copy1.* = 0x40;
    vars.COLDATA_copy2.* = 0x80;

    getout: {
        if (si != 0 and si != 0x40 and si != 0x5b) {
            if (si == 0x70) break :getout;
            var cv: u32 = 0x8c4c26;
            if (si != 3 and si != 5 and si != 7) {
                cv = 0x874a26;
                if (si != 0x43 and si != 0x45) {
                    vars.flag_update_cgram_in_nmi.* +%= 1;
                    return;
                }
            }
            vars.COLDATA_copy0.* = @truncate(cv);
            vars.COLDATA_copy1.* = @truncate(cv >> 8);
            vars.COLDATA_copy2.* = @truncate(cv >> 16);
        }

        if (vars.submodule_index.* != 4) {
            vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy2.*;
            vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2.*;
            if ((si & 0x3f) == 0x1b) {
                const y: i16 = @as(i16, @bitCast(vars.BG2HOFS_copy2.* -% 0x778)) >> 1;
                vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2.* -% @as(u16, @bitCast(y));
                var a = vars.BG1VOFS_copy2.*;
                if (a >= 0x6C0) {
                    a = (a -% 0x600) & 0x3ff;
                    vars.BG1VOFS_copy2.* = if (a < 0x180) (a >> 1) | 0x600 else 0x6c0;
                } else {
                    vars.BG1VOFS_copy2.* = (a & 0xff) >> 1 | 0x600;
                }
            }
        } else {
            if ((si & 0x3f) == 0x1b) {
                vars.BG1HOFS_copy2.* = if (loPtr(vars.overworld_screen_trans_dir_bits).* != 8) 0x838 else vars.BG2HOFS_copy2.*;
                vars.BG1VOFS_copy2.* = 0x6c0;
            }
        }
    }
    vars.TS_copy.* = 1;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Overworld_Memorize_Map16_Change(pos: u16, value: u16) callconv(.c) void {
    if (value == 0xdc5 or value == 0xdc9)
        return;

    const x = vars.num_memorized_tiles.*;
    vars.memorized_tile_value[x >> 1] = value;
    vars.memorized_tile_addr[x >> 1] = pos;
    vars.num_memorized_tiles.* = x +% 2;
}

pub export fn HandlePegPuzzles(pos: u16) callconv(.c) void {
    if (vars.overworld_screen_index.* == 7) {
        if (vars.save_ow_event_info[7] & 0x20 != 0)
            return;
        if (vars.word_7E04C8.* != 0xffff and
            tables.kLwTurtleRockPegPositions[vars.word_7E04C8.* >> 1] == pos)
        {
            wordPtr(vars.sound_effect_1).* = 0x2d00;
            vars.word_7E04C8.* +%= 2;
            if (vars.word_7E04C8.* == 6) {
                wordPtr(vars.sound_effect_1).* = 0x1b00;
                vars.save_ow_event_info[7] |= 0x20;
                vars.submodule_index.* = 47;
            }
        } else {
            wordPtr(vars.sound_effect_1).* = 0x3c;
            vars.word_7E04C8.* = 0xffff;
        }
    } else if (vars.overworld_screen_index.* == 98) {
        vars.word_7E04C8.* +%= 1;
        if (vars.word_7E04C8.* == 22) {
            vars.save_ow_event_info[0x62] |= 0x20;
            vars.sound_effect_2.* = 27;
            vars.door_open_closed_counter.* = 0x50;
            vars.big_rock_starting_address.* = 0xd20;
            Overworld_DoMapUpdate32x32_B();
        }
    }
}

pub export fn GanonTowerEntrance_Func1() callconv(.c) void {
    if (vars.subsubmodule_index.* == 0) {
        vars.sound_effect_1.* = 0x2e;
        Palette_AnimGetMasterSword2();
    } else {
        load_gfx.PaletteFilter_BlindingWhite();
        if (vars.darkening_or_lightening_screen.* == 255) {
            vars.palette_filter_countdown.* = 255;
            vars.subsubmodule_index.* +%= 1;
        } else {
            Palette_AnimGetMasterSword3();
        }
    }
}

pub export fn Overworld_CheckSpecialSwitchArea() callconv(.c) void {
    const map8 = Overworld_GetMap16OfLink_Mult8();
    const a = map8[0] & 0x1ff;
    var i: isize = 3;
    while (i >= 0) : (i -= 1) {
        const k: usize = @intCast(i);
        if (tables.kSpecialSwitchArea_Map8[k] == a and
            tables.kSpecialSwitchArea_Screen[k] == vars.overworld_screen_index.*)
        {
            vars.dungeon_room_index.* = tables.kSpecialSwitchArea_Exit[k];
            vars.link_direction.* = tables.kSpecialSwitchArea_Direction[k];
            loPtr(vars.overworld_screen_trans_dir_bits2).* = vars.link_direction.*;
            loPtr(vars.overworld_screen_trans_dir_bits).* = vars.link_direction.*;
            const e: u16 = @intCast(DirToEnum(vars.link_direction.*));
            wordPtr(vars.overworld_screen_transition).* = e;
            wordPtr(vars.byte_7E069C).* = e;
            vars.submodule_index.* = 23;
            vars.main_module_index.* = 11;
            break;
        }
    }
}

pub export fn Overworld_GetMap16OfLink_Mult8() callconv(.c) [*]align(1) const u16 {
    const map8 = GetMap16toMap8Table();
    const xc: u16 = (vars.link_x_coord.* +% 8) >> 3;
    const yc: u16 = vars.link_y_coord.* +% 12;
    const pos: u16 = ((yc -% vars.overworld_offset_base_y.*) & vars.overworld_offset_mask_y.*) *% 8 +%
        ((xc -% vars.overworld_offset_base_x.*) & vars.overworld_offset_mask_x.*);
    return map8 + @as(usize, vars.dung_bg2[pos >> 1]) * 4;
}

inline fn mapXY(x: usize, y: usize) usize {
    return y * 64 + x;
}

pub export fn Palette_AnimGetMasterSword() callconv(.c) void {
    if (vars.subsubmodule_index.* == 0) {
        Palette_AnimGetMasterSword2();
    } else {
        load_gfx.PaletteFilter_BlindingWhite();
        if (vars.darkening_or_lightening_screen.* == 0xff) {
            for (0..8) |i| {
                vars.main_palette_buffer[0x58 + i] = 0;
                vars.aux_palette_buffer[0x58 + i] = 0;
            }
            vars.palette_filter_countdown.* = 0;
            vars.darkening_or_lightening_screen.* = 0;
            vars.submodule_index.* = 0;
        } else {
            Palette_AnimGetMasterSword3();
        }
    }
}

pub export fn Palette_AnimGetMasterSword2() callconv(.c) void {
    @memcpy(vars.mapbak_palette[0..256], vars.aux_palette_buffer[0..256]);
    for (0..256) |i| vars.aux_palette_buffer[i] = 0x7fff;
    vars.main_palette_buffer[32] = vars.main_palette_buffer[0];
    vars.palette_filter_countdown.* = 0;
    vars.darkening_or_lightening_screen.* = 2;
    vars.subsubmodule_index.* +%= 1;
}

pub export fn Palette_AnimGetMasterSword3() callconv(.c) void {
    if (vars.darkening_or_lightening_screen.* != 0 or vars.palette_filter_countdown.* != 31)
        return;
    @memcpy(vars.aux_palette_buffer[0..256], vars.mapbak_palette[0..256]);
    vars.TS_copy.* = 0;
}

pub export fn Overworld_DwDeathMountainPaletteAnimation() callconv(.c) void {
    if (vars.trigger_special_entrance.* != 0)
        return;
    const sc: u8 = @truncate(vars.overworld_screen_index.*);
    if (sc != 0x43 and sc != 0x45 and sc != 0x47)
        return;
    const fc = vars.frame_counter.*;
    if (fc == 5 or fc == 44 or fc == 90) {
        for (1..8) |i| {
            vars.main_palette_buffer[0x30 + i] = vars.aux_palette_buffer[0x30 + i];
            vars.main_palette_buffer[0x38 + i] = vars.aux_palette_buffer[0x38 + i];
            vars.main_palette_buffer[0x48 + i] = vars.aux_palette_buffer[0x48 + i];
            vars.main_palette_buffer[0x70 + i] = vars.aux_palette_buffer[0x70 + i];
            vars.main_palette_buffer[0x78 + i] = vars.aux_palette_buffer[0x78 + i];
        }
    } else if (fc == 3 or fc == 36 or fc == 88) {
        if (fc == 36)
            vars.sound_effect_1.* = 54;
        for (1..8) |i| {
            vars.main_palette_buffer[0x30 + i] = tables.kDwPaletteAnim[i - 1 + 0];
            vars.main_palette_buffer[0x38 + i] = tables.kDwPaletteAnim[i - 1 + 7];
            vars.main_palette_buffer[0x48 + i] = tables.kDwPaletteAnim[i - 1 + 14];
            vars.main_palette_buffer[0x70 + i] = tables.kDwPaletteAnim[i - 1 + 21];
            vars.main_palette_buffer[0x78 + i] = tables.kDwPaletteAnim[i - 1 + 28];
        }
    }
    vars.flag_update_cgram_in_nmi.* +%= 1;
    var yy: usize = 32;
    if (sc == 0x43 or sc == 0x45) {
        if (vars.save_ow_event_info[0x43] & 0x20 != 0)
            return;
        yy = @as(usize, vars.frame_counter.* & 0xc) * 2;
    }
    for (0..8) |i| vars.main_palette_buffer[0x68 + i] = tables.kDwPaletteAnim2[yy + i];
}

pub export fn Overworld_LoadEventOverlay() callconv(.c) void {
    const dst = vars.dung_bg2;
    var x: usize = 0;
    var do_shared = false;
    switch (vars.overworld_screen_index.*) {
        0, 1, 2 => {
            dst[mapXY(11, 16)] = 0xe32;
            dst[mapXY(12, 16)] = 0xe32;
            dst[mapXY(13, 16)] = 0xe32;
            dst[mapXY(14, 16)] = 0xe32;
            dst[mapXY(11, 17)] = 0xe32;
            dst[mapXY(14, 17)] = 0xe32;
            dst[mapXY(12, 17)] = 0xe33;
            dst[mapXY(13, 17)] = 0xe34;
            dst[mapXY(11, 18)] = 0xe35;
            dst[mapXY(12, 18)] = 0xe36;
            dst[mapXY(13, 18)] = 0xe37;
            dst[mapXY(14, 18)] = 0xe38;
            dst[mapXY(11, 19)] = 0xe39;
            dst[mapXY(12, 19)] = 0xe3a;
            dst[mapXY(13, 19)] = 0xe3b;
            dst[mapXY(14, 19)] = 0xe3c;
            dst[mapXY(12, 20)] = 0xe3d;
            dst[mapXY(13, 20)] = 0xe3e;
        },
        3, 4, 5, 6, 7 => {
            dst[mapXY(16, 14)] = 0x212;
        },
        8...19 => {
            x = mapXY(3, 10);
            do_shared = true;
        },
        20 => {
            dst[mapXY(25, 10)] = 0xdd1;
            dst[mapXY(26, 10)] = 0xdd2;
            dst[mapXY(25, 11)] = 0xdd7;
            dst[mapXY(26, 11)] = 0xdd8;
            dst[mapXY(25, 12)] = 0xdd9;
            dst[mapXY(26, 12)] = 0xdda;
        },
        21...25, 32, 33 => {
            dst[mapXY(31, 24)] = 0xe21;
            dst[mapXY(33, 24)] = 0xe21;
            dst[mapXY(32, 24)] = 0xe22;
            dst[mapXY(31, 25)] = 0xe23;
            dst[mapXY(32, 25)] = 0xe24;
            dst[mapXY(33, 25)] = 0xe25;
        },
        26, 27, 28, 35, 36 => {
            dst[mapXY(30, 39)] = 0xdc1;
            dst[mapXY(31, 39)] = 0xdc2;
            dst[mapXY(30, 40)] = 0xdbe;
            dst[mapXY(31, 40)] = 0xdbf;
            dst[mapXY(32, 39)] = 0xdc2;
            dst[mapXY(33, 39)] = 0xdc3;
            dst[mapXY(32, 40)] = 0xdbf;
            dst[mapXY(33, 40)] = 0xdc0;
        },
        29, 30, 31, 34, 37...43, 107 => {
            x = mapXY(24, 6);
            do_shared = true;
        },
        44...49, 56, 57 => {
            x = mapXY(44, 6);
            do_shared = true;
        },
        50...55, 119 => {
            x = mapXY(6, 8);
            do_shared = true;
        },
        58 => {
            x = mapXY(15, 20);
            do_shared = true;
        },
        59, 123 => {
            dst[mapXY(22, 7)] = 0xddf;
            dst[mapXY(18, 8)] = 0xddf;
            dst[mapXY(16, 9)] = 0xddf;
            dst[mapXY(15, 10)] = 0xddf;
            dst[mapXY(14, 12)] = 0xddf;
            dst[mapXY(26, 14)] = 0xddf;
            dst[mapXY(23, 7)] = 0xde0;
            dst[mapXY(17, 9)] = 0xde0;
            dst[mapXY(24, 7)] = 0xde1;
            dst[mapXY(28, 8)] = 0xde1;
            dst[mapXY(29, 9)] = 0xde1;
            dst[mapXY(21, 11)] = 0xde1;
            dst[mapXY(29, 14)] = 0xde1;
            dst[mapXY(19, 8)] = 0xde2;
            dst[mapXY(20, 8)] = 0xde2;
            dst[mapXY(21, 8)] = 0xde2;
            dst[mapXY(25, 8)] = 0xde2;
            dst[mapXY(26, 8)] = 0xde2;
            dst[mapXY(27, 8)] = 0xde2;
            dst[mapXY(22, 8)] = 0xde3;
            dst[mapXY(18, 9)] = 0xde3;
            dst[mapXY(16, 10)] = 0xde3;
            dst[mapXY(15, 12)] = 0xde3;
            dst[mapXY(23, 8)] = 0xde4;
            dst[mapXY(19, 9)] = 0xde4;
            dst[mapXY(20, 9)] = 0xde4;
            dst[mapXY(24, 9)] = 0xde4;
            dst[mapXY(27, 9)] = 0xde4;
            dst[mapXY(17, 10)] = 0xde4;
            dst[mapXY(18, 10)] = 0xde4;
            dst[mapXY(19, 10)] = 0xde4;
            dst[mapXY(28, 10)] = 0xde4;
            dst[mapXY(16, 11)] = 0xde4;
            dst[mapXY(17, 11)] = 0xde4;
            dst[mapXY(18, 11)] = 0xde4;
            dst[mapXY(19, 11)] = 0xde4;
            dst[mapXY(16, 12)] = 0xde4;
            dst[mapXY(17, 12)] = 0xde4;
            dst[mapXY(15, 13)] = 0xde4;
            dst[mapXY(16, 13)] = 0xde4;
            dst[mapXY(15, 14)] = 0xde4;
            dst[mapXY(16, 14)] = 0xde4;
            dst[mapXY(19, 16)] = 0xde4;
            dst[mapXY(19, 17)] = 0xde4;
            dst[mapXY(20, 17)] = 0xde4;
            dst[mapXY(19, 18)] = 0xde4;
            dst[mapXY(24, 8)] = 0xde5;
            dst[mapXY(28, 9)] = 0xde5;
            dst[mapXY(20, 11)] = 0xde5;
            dst[mapXY(21, 12)] = 0xde5;
            dst[mapXY(21, 9)] = 0xde6;
            dst[mapXY(25, 9)] = 0xde6;
            dst[mapXY(20, 10)] = 0xde6;
            dst[mapXY(28, 11)] = 0xde6;
            dst[mapXY(21, 17)] = 0xde6;
            dst[mapXY(20, 18)] = 0xde6;
            dst[mapXY(22, 9)] = 0xde7;
            dst[mapXY(24, 10)] = 0xde7;
            dst[mapXY(15, 15)] = 0xde7;
            dst[mapXY(16, 15)] = 0xde7;
            dst[mapXY(19, 19)] = 0xde7;
            dst[mapXY(28, 19)] = 0xde7;
            dst[mapXY(23, 9)] = 0xde8;
            dst[mapXY(26, 9)] = 0xde8;
            dst[mapXY(27, 10)] = 0xde8;
            dst[mapXY(17, 15)] = 0xde8;
            dst[mapXY(18, 16)] = 0xde8;
            dst[mapXY(23, 10)] = 0xde9;
            dst[mapXY(26, 10)] = 0xde9;
            dst[mapXY(14, 15)] = 0xde9;
            dst[mapXY(17, 16)] = 0xde9;
            dst[mapXY(26, 18)] = 0xde9;
            dst[mapXY(27, 19)] = 0xde9;
            dst[mapXY(29, 10)] = 0xdea;
            dst[mapXY(28, 12)] = 0xdea;
            dst[mapXY(28, 13)] = 0xdea;
            dst[mapXY(29, 18)] = 0xdea;
            dst[mapXY(15, 11)] = 0xdeb;
            dst[mapXY(27, 11)] = 0xdeb;
            dst[mapXY(27, 12)] = 0xdeb;
            dst[mapXY(14, 13)] = 0xdeb;
            dst[mapXY(27, 13)] = 0xdeb;
            dst[mapXY(14, 14)] = 0xdeb;
            dst[mapXY(18, 17)] = 0xdeb;
            dst[mapXY(18, 18)] = 0xdeb;
            dst[mapXY(18, 12)] = 0xdec;
            dst[mapXY(17, 13)] = 0xdec;
            dst[mapXY(19, 12)] = 0xded;
            dst[mapXY(20, 12)] = 0xdee;
            dst[mapXY(18, 13)] = 0xdef;
            dst[mapXY(27, 15)] = 0xdef;
            dst[mapXY(19, 13)] = 0xdf0;
            dst[mapXY(19, 14)] = 0xdf0;
            dst[mapXY(20, 14)] = 0xdf0;
            dst[mapXY(21, 14)] = 0xdf0;
            dst[mapXY(21, 15)] = 0xdf0;
            dst[mapXY(27, 16)] = 0xdf0;
            dst[mapXY(28, 16)] = 0xdf0;
            dst[mapXY(20, 13)] = 0xdf1;
            dst[mapXY(28, 15)] = 0xdf1;
            dst[mapXY(21, 13)] = 0xdf2;
            dst[mapXY(17, 14)] = 0xdf3;
            dst[mapXY(18, 15)] = 0xdf3;
            dst[mapXY(20, 16)] = 0xdf3;
            dst[mapXY(18, 14)] = 0xdf4;
            dst[mapXY(19, 15)] = 0xdf5;
            dst[mapXY(20, 15)] = 0xdf6;
            dst[mapXY(27, 17)] = 0xdf6;
            dst[mapXY(26, 15)] = 0xdf7;
            dst[mapXY(29, 15)] = 0xdf8;
            dst[mapXY(21, 16)] = 0xdf9;
            dst[mapXY(26, 16)] = 0xdfa;
            dst[mapXY(29, 16)] = 0xdfb;
            dst[mapXY(26, 17)] = 0xdfc;
            dst[mapXY(28, 17)] = 0xdfd;
            dst[mapXY(29, 17)] = 0xdfe;
            dst[mapXY(27, 18)] = 0xdff;
            dst[mapXY(28, 18)] = 0xe00;
            dst[mapXY(21, 10)] = 0xe01;
            dst[mapXY(25, 10)] = 0xe01;
            dst[mapXY(21, 18)] = 0xe01;
            dst[mapXY(29, 11)] = 0xe02;
            dst[mapXY(20, 19)] = 0xe02;
            dst[mapXY(29, 19)] = 0xe02;
            dst[mapXY(18, 19)] = 0xe03;
            dst[mapXY(27, 14)] = 0xe04;
            dst[mapXY(28, 14)] = 0xe05;
        },
        60...65, 72, 73 => {
            dst[mapXY(8, 11)] = 0xe13;
            dst[mapXY(11, 11)] = 0xe14;
            dst[mapXY(8, 12)] = 0xe15;
            dst[mapXY(9, 12)] = 0xe16;
            dst[mapXY(10, 12)] = 0xe17;
            dst[mapXY(11, 12)] = 0xe18;
            dst[mapXY(9, 13)] = 0xe19;
            dst[mapXY(10, 13)] = 0xe1a;
            dst[mapXY(9, 16)] = 0xe06;
            dst[mapXY(10, 16)] = 0xe06;
            dst[mapXY(8, 14)] = 0xe07;
            dst[mapXY(8, 15)] = 0xe07;
            dst[mapXY(9, 14)] = 0xe08;
            dst[mapXY(9, 15)] = 0xe08;
            dst[mapXY(10, 14)] = 0xe09;
            dst[mapXY(10, 15)] = 0xe09;
            dst[mapXY(11, 14)] = 0xe0a;
            dst[mapXY(11, 15)] = 0xe0a;
        },
        66, 67, 68, 75, 76 => {
            dst[mapXY(47, 8)] = 0xe96;
            dst[mapXY(48, 8)] = 0xe97;
            dst[mapXY(47, 9)] = 0xe9c;
            dst[mapXY(47, 10)] = 0xe9c;
            dst[mapXY(48, 9)] = 0xe9d;
            dst[mapXY(48, 10)] = 0xe9d;
            dst[mapXY(47, 11)] = 0xe9a;
            dst[mapXY(48, 11)] = 0xe9b;
        },
        69, 70, 77, 78 => {
            x = mapXY(52, 16);
            do_shared = true;
        },
        71 => {
            dst[mapXY(15, 19)] = 0xe78;
            dst[mapXY(16, 19)] = 0xe79;
            dst[mapXY(17, 19)] = 0xe7a;
            dst[mapXY(18, 19)] = 0xe7b;
            dst[mapXY(15, 20)] = 0xe7c;
            dst[mapXY(16, 20)] = 0xe7d;
            dst[mapXY(17, 20)] = 0xe7e;
            dst[mapXY(18, 20)] = 0xe7f;
            dst[mapXY(15, 21)] = 0xe80;
            dst[mapXY(16, 21)] = 0xe81;
            dst[mapXY(17, 21)] = 0xe82;
            dst[mapXY(18, 21)] = 0xe83;
            dst[mapXY(15, 22)] = 0xe84;
            dst[mapXY(16, 22)] = 0xe85;
            dst[mapXY(17, 22)] = 0xe86;
            dst[mapXY(18, 22)] = 0xe87;
        },
        74, 79...89, 96, 97 => {
            dst[mapXY(31, 26)] = 0xe1b;
            dst[mapXY(32, 26)] = 0xe1c;
            dst[mapXY(31, 27)] = 0xe1d;
            dst[mapXY(32, 27)] = 0xe1e;
            dst[mapXY(31, 28)] = 0xe1f;
            dst[mapXY(32, 28)] = 0xe20;
        },
        90, 91, 92, 99, 100 => {
            dst[mapXY(30, 7)] = 0xe3f;
            dst[mapXY(31, 7)] = 0xe40;
            dst[mapXY(32, 7)] = 0xe41;
            dst[mapXY(30, 8)] = 0xe42;
            dst[mapXY(31, 8)] = 0xe43;
            dst[mapXY(32, 8)] = 0xe44;
            dst[mapXY(30, 9)] = 0xe45;
            dst[mapXY(31, 9)] = 0xe46;
            dst[mapXY(32, 9)] = 0xe47;
        },
        93, 94, 95, 102, 103 => {
            dst[mapXY(51, 3)] = 0xe31;
            dst[mapXY(53, 4)] = 0xe2d;
            dst[mapXY(53, 5)] = 0xe2e;
            dst[mapXY(53, 6)] = 0xe2f;
        },
        98 => {
            x = mapXY(16, 26);
            do_shared = true;
        },
        101, 104, 105, 106, 108...113, 120, 121 => {
            dst[mapXY(17, 10)] = 0xe64;
            dst[mapXY(18, 10)] = 0xe65;
            dst[mapXY(19, 10)] = 0xe66;
            dst[mapXY(20, 10)] = 0xe67;
            dst[mapXY(17, 11)] = 0xe68;
            dst[mapXY(18, 11)] = 0xe69;
            dst[mapXY(19, 11)] = 0xe6a;
            dst[mapXY(20, 11)] = 0xe6b;
            dst[mapXY(17, 12)] = 0xe6c;
            dst[mapXY(18, 12)] = 0xe6d;
            dst[mapXY(19, 12)] = 0xe6e;
            dst[mapXY(20, 12)] = 0xe6f;
            dst[mapXY(17, 13)] = 0xe70;
            dst[mapXY(18, 13)] = 0xe71;
            dst[mapXY(19, 13)] = 0xe72;
            dst[mapXY(20, 13)] = 0xe73;
            dst[mapXY(17, 14)] = 0xe74;
            dst[mapXY(18, 14)] = 0xe75;
            dst[mapXY(19, 14)] = 0xe76;
            dst[mapXY(20, 14)] = 0xe77;
        },
        else => {},
    }
    if (do_shared) {
        dst[x + mapXY(0, 0)] = 0x918;
        dst[x + mapXY(1, 0)] = 0x919;
        dst[x + mapXY(0, 1)] = 0x91a;
        dst[x + mapXY(1, 1)] = 0x91b;
    }
}

pub export fn Ancilla_TerminateWaterfallSplashes() callconv(.c) void {
    const t = loPtr(vars.overworld_screen_index).*;
    if (t == 0xf) {
        var i: isize = 4;
        while (i >= 0) : (i -= 1) {
            const k: usize = @intCast(i);
            if (vars.ancilla_type[k] == 0x41)
                vars.ancilla_type[k] = 0;
        }
    }
}

pub export fn Overworld_GetPitDestination() callconv(.c) void {
    const x: u16 = vars.link_x_coord.* & ~@as(u16, 7);
    const y: u16 = vars.link_y_coord.* & ~@as(u16, 7);
    var pos: u16 = ((y -% vars.overworld_offset_base_y.*) & vars.overworld_offset_mask_y.*) << 3;
    pos +%= ((x >> 3) -% vars.overworld_offset_base_x.*) & vars.overworld_offset_mask_x.*;

    var i: isize = 36 / 2;
    while (true) {
        const k: usize = @intCast(i);
        if (kFallHole_Pos()[k] == pos and kFallHole_Area()[k] == vars.overworld_area_index.*)
            break;
        i -= 1;
        if (i < 0) {
            vars.savegame_is_darkworld.* = 0;
            // Chris Houlihan's room
            vars.which_entrance.* = 130;
            vars.byte_7E010F.* = 0;
            return;
        }
    }
    vars.which_entrance.* = kFallHole_Entrances()[@intCast(i)];
    vars.byte_7E010F.* = 0;
}

pub export fn Overworld_UseEntrance() callconv(.c) void {
    const xc: u16 = vars.link_x_coord.* >> 3;
    const yc: u16 = vars.link_y_coord.* +% 7;
    var pos: u16 = ((yc -% vars.overworld_offset_base_y.*) & vars.overworld_offset_mask_y.*) *% 8 +%
        ((xc -% vars.overworld_offset_base_x.*) & vars.overworld_offset_mask_x.*);

    var x: usize = @as(usize, vars.dung_bg2[pos >> 1]) * 4;
    const map8p = GetMap16toMap8Table();

    after: {
        if (vars.link_direction_facing.* == 0) {
            var a = map8p[x + 1] & 0x41ff;
            var do_draw = false;
            var is_149_or_169 = false;
            if (a == 0xe9) {
                do_draw = true;
            } else if (a == 0x149 or a == 0x169) {
                is_149_or_169 = true;
            } else {
                x = @as(usize, vars.dung_bg2[(pos >> 1) + 1]) * 4;
                a = map8p[x] & 0x41ff;
                if (a == 0x40e9) {
                    pos -%= 2;
                    do_draw = true;
                } else if (a == 0x4149 or a == 0x4169) {
                    pos -%= 2;
                    is_149_or_169 = true;
                }
            }
            if (do_draw) {
                Overworld_DrawMap16_Persist(pos +% 0, 0xDA4);
                Overworld_DrawMap16_Persist(pos +% 2, 0xDA6);
                vars.sound_effect_2.* = 21;
                vars.nmi_load_bg_from_vram.* = 1;
                return;
            }
            if (is_149_or_169) {
                vars.door_open_closed_counter.* = 0;
                if (a & 0x20 != 0) {
                    // 0x169
                    if ((vars.sram_progress_indicator.* & 0xf) >= 3)
                        break :after;
                    vars.door_open_closed_counter.* = 24;
                }
                vars.big_rock_starting_address.* = pos -% 0x80;
                vars.sound_effect_2.* = 21;
                vars.subsubmodule_index.* = 0;
                loPtr(vars.door_animation_step_indicator).* = 0;
                vars.submodule_index.* = 12;
                return;
            }
        }
    }

    if (!LookupInOwEntranceTab(map8p[x + 2] & 0x1ff, map8p[x + 3] & 0x1ff)) {
        vars.big_key_door_message_triggered.* = 0;
        return;
    }

    const lx = LookupInOwEntranceTab2(pos);
    if (lx < 0)
        return;

    const eid = kOverworld_Entrance_Id()[@intCast(lx)];
    if (vars.follower_dropped.* == 0 and
        (vars.link_pose_for_item.* == 1 or !CanEnterWithTagalong(@as(c_int, eid) - 1)))
    {
        if (vars.big_key_door_message_triggered.* == 0) {
            vars.big_key_door_message_triggered.* = 1;
            vars.dialogue_message_index.* = 5;
            misc.Main_ShowTextMessage();
        }
    } else {
        vars.which_entrance.* = eid;
        vars.link_auxiliary_state.* = 0;
        vars.link_incapacitated_timer.* = 0;
        vars.main_module_index.* = 15;
        vars.saved_module_for_menu.* = 6;
        vars.submodule_index.* = 0;
        vars.subsubmodule_index.* = 0;
    }
}

pub export fn Overworld_ToolAndTileInteraction(x: u16, y: u16) callconv(.c) u16 {
    vars.word_7E04B2.* = 0;
    vars.index_of_interacting_tile.* = 0;
    const pos: u16 = ((y -% vars.overworld_offset_base_y.*) & vars.overworld_offset_mask_y.*) *% 8 +%
        ((x -% vars.overworld_offset_base_x.*) & vars.overworld_offset_mask_x.*);
    var attr: u16 = vars.overworld_tileattr[pos >> 1];
    var yv: u16 = 0;

    // Mirrors the C's `goto check_secret` / `goto memoize_getout` entry points:
    // 0 = plain `return attr`, 1 = check_secret, 2 = memoize_getout, 3 = shared tail only.
    var entry: u8 = 0;

    if (vars.link_item_in_hand.* & 2 == 0) {
        if (vars.link_item_in_hand.* & 0x40 == 0) {
            if (attr == 0x34 or attr == 0x71 or attr == 0x35 or attr == 0x10d or
                attr == 0x10f or attr == 0xe1 or attr == 0xe2 or attr == 0xda or
                attr == 0xf8 or attr == 0x10e)
            { // shovelable
                if (vars.link_position_mode.* != 1)
                    return attr;
                if (vars.overworld_screen_index.* == 0x2a and pos == 0x492)
                    vars.word_7E04B2.* = pos;
                yv = 0xdc9;
                entry = 1;
            } else if (attr == 0x37e) { // isThickGrass
                if (vars.link_position_mode.* == 1)
                    return attr;
                vars.scratch_0.* = x *% 8 -% 8;
                vars.scratch_1.* = (y -% 8) & ~@as(u16, 7);
                vars.index_of_interacting_tile.* = 3;
                yv = 0xdc5;
                entry = 1;
            }
        }
        if (entry == 0) {
            // (yv = 2, attr == 0x36) || (yv = 4, attr == 0x72a)
            var is_bush = false;
            if (attr == 0x36) {
                yv = 2;
                is_bush = true;
            } else if (attr == 0x72a) {
                yv = 4;
                is_bush = true;
            }
            if (!is_bush)
                return attr;
            if (vars.link_position_mode.* != 1) {
                vars.scratch_0.* = (x & ~@as(u16, 1)) *% 8;
                vars.scratch_1.* = y & ~@as(u16, 0xf);
                vars.index_of_interacting_tile.* = @truncate(yv);
                yv = if (attr == 0x72a) 0xdc8 else 0xdc7;
                entry = 1;
            } else {
                entry = 3;
            }
        }
    } else {
        if (attr == 0x21b) {
            vars.sound_effect_1.* = 17;
            HandlePegPuzzles(pos);
            yv = 0xdcb;
            entry = 2;
        } else {
            Overworld_PickHammerSfx(attr);
            return attr;
        }
    }

    if (entry == 1) {
        const result = Overworld_RevealSecret(pos);
        if (result != 0)
            yv = result;
        entry = 2;
    }
    if (entry == 2) {
        vars.overworld_tileattr[pos >> 1] = yv;
        Overworld_Memorize_Map16_Change(pos, yv);
        Overworld_DrawMap16(pos, yv);
        vars.nmi_load_bg_from_vram.* = 1;
    }

    const t: u16 = GetMap16toMap8Table()[@as(usize, attr) * 4 + ((y & 8) >> 2) + (x & 1)];
    attr = kMap8DataToTileAttr()[t & 0x1ff];
    if (vars.index_of_interacting_tile.* != 0) {
        Sprite_SpawnImmediatelySmashedTerrain(@truncate(vars.index_of_interacting_tile.*), vars.scratch_0.*, vars.scratch_1.*);
        AncillaAdd_BushPoof(vars.scratch_0.*, vars.scratch_1.*);
    }
    return attr;
}

pub export fn Overworld_PickHammerSfx(a: u16) callconv(.c) void {
    const attr: u16 = kMap8DataToTileAttr()[GetMap16toMap8Table()[@as(usize, a) * 4] & 0x1ff];
    var y: u8 = undefined;
    if (attr < 0x50) {
        return;
    } else if (attr < 0x52) {
        y = 26;
    } else if (attr < 0x54) {
        y = 17;
    } else if (attr < 0x58) {
        y = 5;
    } else {
        return;
    }
    vars.sound_effect_1.* = y;
}

pub export fn Overworld_GetLinkMap16Coords(xy: *Point16U) callconv(.c) u16 {
    const di: usize = vars.link_direction_facing.* >> 1;
    const x: u16 = (vars.link_x_coord.* +%
        @as(u16, @bitCast(@as(i16, rtl.kGetBestActionToPerformOnTile_x[di])))) & ~@as(u16, 0xf);
    const y: u16 = (vars.link_y_coord.* +%
        @as(u16, @bitCast(@as(i16, rtl.kGetBestActionToPerformOnTile_y[di])))) & ~@as(u16, 0xf);
    xy.x = x;
    xy.y = y;
    const rv: u16 = ((y -% vars.overworld_offset_base_y.*) & vars.overworld_offset_mask_y.*) << 3;
    return rv +% (((x >> 3) -% vars.overworld_offset_base_x.*) & vars.overworld_offset_mask_x.*);
}

pub export fn Overworld_HandleLiftableTiles(pt_arg: *Point16U) callconv(.c) u8 {
    const pos = Overworld_GetLinkMap16Coords(pt_arg);
    const pt = pt_arg.*;
    const a: u16 = vars.overworld_tileattr[pos >> 1];
    var y: u16 = 0;
    // 0 = neither, 1 = rock pile, 2 = small liftable object
    var kind: u8 = 0;
    if (a == 0x36d) {
        y = 0;
        kind = 1;
    } else if (a == 0x36e) {
        y = 1;
        kind = 1;
    } else if (a == 0x374) {
        y = 2;
        kind = 1;
    } else if (a == 0x375) {
        y = 3;
        kind = 1;
    } else if (a == 0x23b) {
        y = 0;
        kind = 1;
    } else if (a == 0x23c) {
        y = 1;
        kind = 1;
    } else if (a == 0x23d) {
        y = 2;
        kind = 1;
    } else if (a == 0x23e) {
        y = 3;
        kind = 1;
    } else if (a == 0x36) {
        y = 0xdc7;
        kind = 2;
    } else if (a == 0x72a) {
        y = 0xdc8;
        kind = 2;
    } else if (a == 0x20f) {
        y = 0xdca;
        kind = 2;
    } else if (a == 0x239) {
        y = 0xdca;
        kind = 2;
    } else if (a == 0x101) {
        y = 0xdc6;
        kind = 2;
    }

    if (kind == 1) {
        return SmashRockPile_fromLift(a, pos, y, pt);
    } else if (kind == 2) {
        return Overworld_LiftingSmallObj(a, pos, y, pt);
    } else {
        const t: usize = @as(usize, a) * 4 +
            (if (pt.x & 8 != 0) @as(usize, 2) else 0) +
            (if (pt.y & 8 != 0) @as(usize, 1) else 0);
        return kMap8DataToTileAttr()[GetMap16toMap8Table()[t] & 0x1ff];
    }
}

pub export fn Overworld_LiftingSmallObj(a: u16, pos: u16, y_in: u16, pt: Point16U) callconv(.c) u8 {
    var y = y_in;
    const secret = Overworld_RevealSecret(pos);
    if (secret != 0)
        y = secret;
    vars.overworld_tileattr[pos >> 1] = y;
    Overworld_Memorize_Map16_Change(pos, y);
    Overworld_DrawMap16(pos, y);
    vars.nmi_load_bg_from_vram.* = 1;
    const t: usize = @as(usize, a) * 4 +
        (if (pt.x & 8 != 0) @as(usize, 2) else 0) +
        (if (pt.y & 8 != 0) @as(usize, 1) else 0);
    return kMap8DataToTileAttr()[GetMap16toMap8Table()[t] & 0x1ff];
}

pub export fn Overworld_SmashRockPile(down_one_tile: bool, pt: *Point16U) callconv(.c) c_int {
    const bak = vars.link_y_coord.*;
    vars.link_y_coord.* +%= if (down_one_tile) 8 else 0;
    const pos = Overworld_GetLinkMap16Coords(pt);
    vars.link_y_coord.* = bak;
    const a: u16 = vars.dung_bg2[pos >> 1];
    var y: u16 = 0;
    var is_pile = false;
    if (a == 0x226) {
        y = 0;
        is_pile = true;
    } else if (a == 0x227) {
        y = 1;
        is_pile = true;
    } else if (a == 0x228) {
        y = 2;
        is_pile = true;
    } else if (a == 0x229) {
        y = 3;
        is_pile = true;
    }
    if (is_pile) {
        return SmashRockPile_fromLift(a, pos, y, pt.*);
    } else if (a == 0x36) {
        return Overworld_LiftingSmallObj(a, pos, 0xDC7, pt.*);
    } else {
        return -1;
    }
}

pub export fn SmashRockPile_fromLift(a: u16, pos_in: u16, y: u16, pt_in: Point16U) callconv(.c) u8 {
    var pt = pt_in;
    var pos = (pos_in >> 1) +% @as(u16, @bitCast(@as(i16, tables.kBigRockTab1[y])));
    pos = pos *% 2;
    vars.big_rock_starting_address.* = pos;
    vars.door_open_closed_counter.* = 40;

    @as(*align(1) u16, @ptrCast(&g_ram[0])).* = pt.y;
    @as(*align(1) u16, @ptrCast(&g_ram[2])).* = pt.x;

    const secret = Overworld_RevealSecret(pos);
    pt.y = @as(*align(1) u16, @ptrCast(&g_ram[0])).*;
    pt.x = @as(*align(1) u16, @ptrCast(&g_ram[2])).*;

    if (secret == 0xffff) {
        vars.save_ow_event_info[vars.overworld_screen_index.*] |= 0x20;
        vars.sound_effect_2.* = 27;
        vars.door_open_closed_counter.* = 80;
    }
    pt.x +%= @bitCast(@as(i16, tables.kBigRockTabX[y]) * 2);
    pt.y +%= @bitCast(@as(i16, tables.kBigRockTabY[y]) * 2);

    Overworld_DoMapUpdate32x32_B(); // WARNING: The original destroys ram[0] and ram[2]

    const t: usize = @as(usize, a) * 4 +
        (if (pt.x & 8 != 0) @as(usize, 2) else 0) +
        (if (pt.y & 8 != 0) @as(usize, 1) else 0);
    return kMap8DataToTileAttr()[GetMap16toMap8Table()[t] & 0x1ff];
}

pub export fn Overworld_BombTiles32x32(x_in: u16, y_in: u16) callconv(.c) void {
    const x: u16 = (x_in -% 23) & ~@as(u16, 7);
    var y: u16 = (y_in -% 20) & ~@as(u16, 7);

    var yy: c_int = 3;
    while (yy != 0) : ({
        yy -= 1;
        y +%= 16;
    }) {
        var xx: c_int = 3;
        var xt: u16 = x;
        while (xx != 0) : ({
            xx -= 1;
            xt +%= 16;
        }) {
            Overworld_BombTile(xt, y);
        }
    }
    vars.word_7E0486.* = x;
    vars.word_7E0488.* = y;
}

pub export fn Overworld_BombTile(x: u16, y: u16) callconv(.c) void {
    const pos: u16 = (((y -% vars.overworld_offset_base_y.*) & vars.overworld_offset_mask_y.*) << 3) +%
        (((x >> 3) -% vars.overworld_offset_base_x.*) & vars.overworld_offset_mask_x.*);

    var a: u16 = undefined;
    var j: u16 = undefined;
    var k: u8 = undefined;
    var to_label_a = false;

    if (vars.follower_indicator.* == 13) {
        to_label_a = true;
    } else {
        a = vars.dung_bg2[pos >> 1];
        if (a == 0x36) {
            k = 2;
            j = 0xdc7;
        } else if (a == 0x72a) {
            k = 4;
            j = 0xdc8;
        } else if (a == 0x37e) {
            k = 3;
            j = 0xdc5;
        } else {
            to_label_a = true;
        }
    }

    if (!to_label_a) {
        a = Overworld_RevealSecret(pos);
        if (a == 0)
            a = j;
        vars.dung_bg2[pos >> 1] = a;
        Overworld_Memorize_Map16_Change(pos, a);
        Overworld_DrawMap16(pos, a);

        Sprite_SpawnImmediatelySmashedTerrain(k, x & ~@as(u16, 7), y & ~@as(u16, 7));
        vars.nmi_load_bg_from_vram.* = 1;
        return;
    }

    a = Overworld_RevealSecret(pos);
    if (a == 0xdb4) {
        vars.dung_bg2[pos >> 1] = a;
        Overworld_Memorize_Map16_Change(pos, a);
        Overworld_DrawMap16(pos, a);

        vars.dung_bg2[(pos >> 1) + 1] = 0xDB5;
        Overworld_Memorize_Map16_Change(pos, 0xDB5); // wtf
        Overworld_DrawMap16(pos +% 2, 0xDB5);
        vars.nmi_load_bg_from_vram.* = 1;
        vars.save_ow_event_info[vars.overworld_screen_index.*] |= 2;
    }
}

pub export fn Overworld_AlterWeathervane() callconv(.c) void {
    vars.door_open_closed_counter.* = 0x68;
    vars.big_rock_starting_address.* = 0xc3e;
    Overworld_DoMapUpdate32x32_B();
    Overworld_DrawMap16_Persist(0xc42, 0xe21);
    Overworld_DrawMap16_Persist(0xcc2, 0xe25);

    vars.save_ow_event_info[0x18] |= 0x20;
    vars.nmi_load_bg_from_vram.* = 1;
}

pub export fn OpenGargoylesDomain() callconv(.c) void {
    Overworld_DrawMap16_Persist(0xd3e, 0xe1b);
    Overworld_DrawMap16_Persist(0xd40, 0xe1c);
    Overworld_DrawMap16_Persist(0xdbe, 0xe1d);
    Overworld_DrawMap16_Persist(0xdc0, 0xe1e);
    Overworld_DrawMap16_Persist(0xe3e, 0xe1f);
    Overworld_DrawMap16_Persist(0xe40, 0xe20);
    vars.save_ow_event_info[0x58] |= 0x20;
    vars.sound_effect_2.* = 0x1b;
    vars.nmi_load_bg_from_vram.* = 1;
}

pub export fn CreatePyramidHole() callconv(.c) void {
    Overworld_DrawMap16_Persist(0x3bc, 0xe3f);
    Overworld_DrawMap16_Persist(0x3be, 0xe40);
    Overworld_DrawMap16_Persist(0x3c0, 0xe41);
    Overworld_DrawMap16_Persist(0x43c, 0xe42);
    Overworld_DrawMap16_Persist(0x43e, 0xe43);
    Overworld_DrawMap16_Persist(0x440, 0xe44);
    Overworld_DrawMap16_Persist(0x4bc, 0xe45);
    Overworld_DrawMap16_Persist(0x4be, 0xe46);
    Overworld_DrawMap16_Persist(0x4c0, 0xe47);
    wordPtr(vars.sound_effect_ambient).* = 0x3515;
    vars.save_ow_event_info[0x5b] |= 0x20;
    vars.sound_effect_2.* = 3;
    vars.nmi_load_bg_from_vram.* = 1;
}

/// Strange return value in Carry/R14
pub export fn Overworld_RevealSecret(pos: u16) callconv(.c) u16 {
    loPtr(vars.dung_secrets_unk1).* = 0;

    fail: {
        if (vars.overworld_screen_index.* >= 0x80)
            break :fail;

        var ptr: [*]const u8 = kOverworldSecrets() +
            kOverworldSecrets_Offs()[vars.overworld_screen_index.*];
        while (true) {
            const x = @as(*align(1) const u16, @ptrCast(ptr)).*;
            if (x == 0xffff)
                break :fail;
            if ((x & 0x7fff) == pos)
                break;
            ptr += 3;
        }
        const data = ptr[2];
        if (data != 0 and data < 0x80)
            loPtr(vars.dung_secrets_unk1).* |= data;
        if (data < 0x80)
            break :fail; // carry set

        loPtr(vars.dung_secrets_unk1).* = 0xff;
        if (data != 0x84 and vars.save_ow_event_info[vars.overworld_screen_index.*] & 2 == 0) {
            if (vars.overworld_screen_index.* == 0x5b and vars.follower_indicator.* != 13)
                break :fail;
            vars.sound_effect_2.* = 0x1b;
            // The discovery chime is missing when lifting the rock covering the magic
            // portal leading to the Ice Temple
        } else if (data == 0x82 and
            features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
        {
            vars.sound_effect_2.* = 0x1b;
        }
        AdjustSecretForPowder();
        return tables.kTileBelow[(data & 0xf) >> 1];
    }
    AdjustSecretForPowder();
    return 0;
}

pub export fn AdjustSecretForPowder() callconv(.c) void {
    if (vars.link_item_in_hand.* & 0x40 != 0)
        vars.dung_secrets_unk1.* = 4;
}

pub export fn Overworld_DrawMap16_Persist(pos: u16, value: u16) callconv(.c) void {
    vars.dung_bg2[pos >> 1] = value;
    Overworld_DrawMap16(pos, value);
}

pub export fn Overworld_DrawMap16(pos_in: u16, value: u16) callconv(.c) void {
    const pos = Overworld_FindMap16VRAMAddress(pos_in);
    const dst = vars.vram_upload_data + (vars.vram_upload_offset.* >> 1);
    const src = GetMap16toMap8Table() + @as(usize, value) * 4;
    dst[0] = swap16(pos);
    dst[1] = 0x300;
    dst[2] = src[0];
    dst[3] = src[1];
    dst[4] = swap16(pos +% 0x20);
    dst[5] = 0x300;
    dst[6] = src[2];
    dst[7] = src[3];
    dst[8] = 0xffff;
    vars.vram_upload_offset.* +%= 16;
}

pub export fn Overworld_AlterTileHardcore(pos_in: u16, value: u16) callconv(.c) void {
    vars.dung_bg2[pos_in >> 1] = value;
    const pos = Overworld_FindMap16VRAMAddress(pos_in);
    const dst = vars.vram_upload_data + (vars.vram_upload_offset.* >> 1);
    const src = GetMap16toMap8Table() + @as(usize, value) * 4;
    dst[0] = swap16(pos);
    dst[1] = 0x300;
    dst[2] = src[0];
    dst[3] = src[1];
    dst[4] = swap16(pos +% 0x20);
    dst[5] = 0x300;
    dst[6] = src[2];
    dst[7] = src[3];
    dst[8] = 0xffff;
    vars.vram_upload_offset.* +%= 16;
}

pub export fn Overworld_FindMap16VRAMAddress(addr: u16) callconv(.c) u16 {
    return (if ((addr & 0x3f) >= 0x20) @as(u16, 0x400) else 0) +%
        (if ((addr & 0xfff) >= 0x800) @as(u16, 0x800) else 0) +%
        (addr & 0x1f) +% ((addr & 0x780) >> 1);
}

pub export fn Overworld_AnimateEntrance() callconv(.c) void {
    const j = vars.trigger_special_entrance.*;
    vars.flag_is_link_immobilized.* = j;
    vars.flag_unk1.* = j;
    vars.nmi_disable_core_updates.* = j;
    kOverworld_EntranceSequence[j - 1]();
}

pub export fn Overworld_AnimateEntrance_PoD() callconv(.c) void {
    switch (vars.subsubmodule_index.*) {
        0 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 0x40)
                return;
            OverworldEntrance_AdvanceAndBoom();
            vars.save_ow_event_info[0x5e] |= 0x20;
            Overworld_DrawMap16_Persist(0x1e6, 0xe31);
            Overworld_DrawMap16_Persist(0x2ea, 0xe30);
            Overworld_DrawMap16_Persist(0x26a, 0xe26);
            Overworld_DrawMap16_Persist(0x2ea, 0xe27);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        1 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 0x20)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x26a, 0xe28);
            Overworld_DrawMap16_Persist(0x2ea, 0xe29);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        2 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 0x20)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x26a, 0xe2a);
            Overworld_DrawMap16_Persist(0x2ea, 0xe2b);
            Overworld_DrawMap16_Persist(0x36a, 0xe2c);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        3 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 0x20)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x26a, 0xe2d);
            Overworld_DrawMap16_Persist(0x2ea, 0xe2e);
            Overworld_DrawMap16_Persist(0x36a, 0xe2f);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        4 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 0x20)
                return;
            OverworldEntrance_PlayJingle();
        },
        else => {},
    }
}

/// Dark Forest Palace
pub export fn Overworld_AnimateEntrance_Skull() callconv(.c) void {
    switch (vars.subsubmodule_index.*) {
        0 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 4)
                return;
            vars.overworld_entrance_sequence_counter.* = 0;
            vars.subsubmodule_index.* +%= 1;
            Overworld_DrawMap16_Persist(0x409 * 2, 0xe06);
            Overworld_DrawMap16_Persist(0x40a * 2, 0xe06);
            vars.save_ow_event_info[loPtr(vars.overworld_screen_index).*] |= 0x20;
            vars.nmi_load_bg_from_vram.* = 1;
            vars.sound_effect_2.* = 0x16;
        },
        1 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 12)
                return;
            vars.overworld_entrance_sequence_counter.* = 0;
            vars.subsubmodule_index.* +%= 1;
            Overworld_DrawMap16_Persist(0x3c8 * 2, 0xe07);
            Overworld_DrawMap16_Persist(0x3c9 * 2, 0xe08);
            Overworld_DrawMap16_Persist(0x3ca * 2, 0xe09);
            Overworld_DrawMap16_Persist(0x3cb * 2, 0xe0a);
            vars.nmi_load_bg_from_vram.* = 1;
            vars.sound_effect_2.* = 0x16;
        },
        2 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 12)
                return;
            vars.overworld_entrance_sequence_counter.* = 0;
            vars.subsubmodule_index.* +%= 1;
            Overworld_DrawMap16_Persist(0x388 * 2, 0xe07);
            Overworld_DrawMap16_Persist(0x389 * 2, 0xe08);
            Overworld_DrawMap16_Persist(0x38a * 2, 0xe09);
            Overworld_DrawMap16_Persist(0x38b * 2, 0xe0a);
            vars.nmi_load_bg_from_vram.* = 1;
            vars.sound_effect_2.* = 0x16;
        },
        3 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 12)
                return;
            vars.overworld_entrance_sequence_counter.* = 0;
            vars.subsubmodule_index.* +%= 1;
            Overworld_DrawMap16_Persist(0x2c8 * 2, 0xe11);
            Overworld_DrawMap16_Persist(0x2cb * 2, 0xe12);
            Overworld_DrawMap16_Persist(0x308 * 2, 0xe0d);
            Overworld_DrawMap16_Persist(0x309 * 2, 0xe0e);
            Overworld_DrawMap16_Persist(0x30a * 2, 0xe0f);
            Overworld_DrawMap16_Persist(0x30b * 2, 0xe10);
            Overworld_DrawMap16_Persist(0x349 * 2, 0xe0b);
            Overworld_DrawMap16_Persist(0x34a * 2, 0xe0c);
            vars.nmi_load_bg_from_vram.* = 1;
            vars.sound_effect_2.* = 0x16;
        },
        4 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 12)
                return;
            vars.overworld_entrance_sequence_counter.* = 0;
            vars.subsubmodule_index.* +%= 1;
            Overworld_DrawMap16_Persist(0x2c8 * 2, 0xe13);
            Overworld_DrawMap16_Persist(0x2cb * 2, 0xe14);
            Overworld_DrawMap16_Persist(0x308 * 2, 0xe15);
            Overworld_DrawMap16_Persist(0x309 * 2, 0xe16);
            Overworld_DrawMap16_Persist(0x30a * 2, 0xe17);
            Overworld_DrawMap16_Persist(0x30b * 2, 0xe18);
            Overworld_DrawMap16_Persist(0x349 * 2, 0xe19);
            Overworld_DrawMap16_Persist(0x34a * 2, 0xe1a);
            vars.nmi_load_bg_from_vram.* = 1;
            vars.sound_effect_2.* = 0x16;
            OverworldEntrance_PlayJingle();
        },
        else => {},
    }
}

/// The `draw_misery_2` label: 12 tiles, advancing `j` as it goes.
fn miseryDraw2(j_in: u16) void {
    var j = j_in;
    for ([_]u16{ 0x622, 0x624, 0x626, 0x628, 0x6a2, 0x6a4, 0x6a6, 0x6a8, 0x722, 0x724, 0x726, 0x728 }) |p| {
        Overworld_DrawMap16_Persist(p, j);
        j +%= 1;
    }
    vars.nmi_load_bg_from_vram.* = 1;
}

/// The `draw_misery_3` label: 4 tiles, then falls through into `draw_misery_2`.
fn miseryDraw3(j_in: u16) void {
    var j = j_in;
    for ([_]u16{ 0x5a2, 0x5a4, 0x5a6, 0x5a8 }) |p| {
        Overworld_DrawMap16_Persist(p, j);
        j +%= 1;
    }
    miseryDraw2(j);
}

pub export fn Overworld_AnimateEntrance_Mire() callconv(.c) void {
    if (vars.subsubmodule_index.* >= 2) {
        vars.bg1_x_offset.* = if (vars.frame_counter.* & 1 != 0) @bitCast(@as(i16, -1)) else 1;
        vars.bg1_y_offset.* = 0 -% vars.bg1_x_offset.*;
    }
    switch (vars.subsubmodule_index.*) {
        0 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            var j: u16 = vars.overworld_entrance_sequence_counter.*;
            if (j < 32)
                return;
            j -= 32;
            if (j == 207) {
                vars.subsubmodule_index.* = 1;
                vars.overworld_entrance_sequence_counter.* = 0;
            }
            vars.TS_copy.* = @intFromBool(
                (tables.kMiseryMireEntranceBits[j >> 3] & (@as(u8, 0x80) >> @intCast(j & 7))) != 0,
            );
        },
        1, 2 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            const j: u16 = vars.overworld_entrance_sequence_counter.*;
            if (j == 16) {
                vars.subsubmodule_index.* +%= 1;
                vars.sound_effect_ambient.* = 7;
            }
            if (j != 72)
                return;
            OverworldEntrance_AdvanceAndBoom();
            vars.save_ow_event_info[loPtr(vars.overworld_screen_index).*] |= 0x20;
            miseryDraw2(0xe48);
        },
        3 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 72)
                return;
            OverworldEntrance_AdvanceAndBoom();
            miseryDraw3(0xe54);
        },
        4 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 80)
                return;
            OverworldEntrance_AdvanceAndBoom();
            var j: u16 = 0xe64;
            for ([_]u16{ 0x522, 0x524, 0x526, 0x528 }) |p| {
                Overworld_DrawMap16_Persist(p, j);
                j +%= 1;
            }
            miseryDraw3(j);
        },
        5 => {
            vars.overworld_entrance_sequence_counter.* +%= 1;
            if (vars.overworld_entrance_sequence_counter.* != 128)
                return;
            OverworldEntrance_PlayJingle();
            vars.sound_effect_ambient.* = 5;
        },
        else => {},
    }
}

pub export fn Overworld_AnimateEntrance_TurtleRock() callconv(.c) void {
    vars.bg1_x_offset.* = if (vars.frame_counter.* & 1 != 0) @bitCast(@as(i16, -1)) else 1;
    vars.bg1_y_offset.* = 0 -% vars.bg1_x_offset.*;

    // The `common:` label shared by subsubmodules 0..3.
    var common: ?u16 = null;
    switch (vars.subsubmodule_index.*) {
        0 => {
            vars.save_ow_event_info[vars.overworld_screen_index.*] |= 0x20;
            Dungeon_ApproachFixedColor_variable(0);
            common = 0x10;
        },
        1 => common = 0x14,
        2 => common = 0x18,
        3 => common = 0x1c,
        4 => {
            for (0..8) |i| {
                vars.main_palette_buffer[0x58 + i] = 0;
                vars.aux_palette_buffer[0x68 + i] = 0;
            }
            vars.BG1VOFS_copy2.* = vars.BG2VOFS_copy2.*;
            vars.BG1HOFS_copy2.* = vars.BG2HOFS_copy2.*;
            vars.subsubmodule_index.* +%= 1;
            vars.flag_update_cgram_in_nmi.* +%= 1;
        },
        5 => {
            OverworldEntrance_DrawManyTR();
            vars.TS_copy.* = 1;
            vars.CGWSEL_copy.* = 2;
            vars.CGADSUB_copy.* = 0x22;
            var vram: [*]align(1) u16 = vars.vram_upload_data;
            const vram_end: [*]align(1) u16 = vars.vram_upload_data + (vars.vram_upload_offset.* >> 1);
            while (true) {
                vram[0] |= 0x10;
                if (vram[2] == 0x8aa)
                    vram[2] = 0x1e3;
                if (vram[3] == 0x8aa)
                    vram[3] = 0x1e3;
                vram += 4;
                if (vram == vram_end) break;
            }
            vars.some_menu_ctr.* = 0;
            vars.subsubmodule_index.* +%= 1;
        },
        6 => {
            if (vars.frame_counter.* & 1 == 0) {
                if (vars.some_menu_ctr.* & 7 == 0) {
                    load_gfx.PaletteFilter_RestoreAdditive(0xb0, 0xc0);
                    load_gfx.PaletteFilter_RestoreSubtractive(0xd0, 0xe0);
                    vars.flag_update_cgram_in_nmi.* +%= 1;
                    vars.sound_effect_2.* = 2;
                }
                vars.some_menu_ctr.* -%= 1;
                if (vars.some_menu_ctr.* == 0) {
                    vars.some_menu_ctr.* = 0x30;
                    vars.subsubmodule_index.* +%= 1;
                }
            }
        },
        7 => {
            if (vars.frame_counter.* & 1 == 0 and vars.some_menu_ctr.* & 7 == 0)
                vars.sound_effect_2.* = 2;
            vars.some_menu_ctr.* -%= 1;
            if (vars.some_menu_ctr.* == 0) {
                OverworldEntrance_DrawManyTR();
                vars.TS_copy.* = 0;
                vars.CGWSEL_copy.* = 0x82;
                vars.CGADSUB_copy.* = 0x20;
                vars.subsubmodule_index.* +%= 1;
                vars.sound_effect_ambient.* = 5;
            }
        },
        8 => OverworldEntrance_PlayJingle(),
        else => {},
    }
    if (common) |c| {
        vars.vram_upload_data[0] = c;
        vars.vram_upload_data[1] = 0xfe47;
        vars.vram_upload_data[2] = 0x1e3;
        loPtr(&vars.vram_upload_data[3]).* = 0xff;
        vars.subsubmodule_index.* +%= 1;
        vars.nmi_load_bg_from_vram.* = 1;
    }
}

pub export fn OverworldEntrance_PlayJingle() callconv(.c) void {
    vars.sound_effect_2.* = 27;
    vars.trigger_special_entrance.* = 0;
    vars.subsubmodule_index.* = 0;
    vars.nmi_disable_core_updates.* = 0;
    vars.flag_is_link_immobilized.* = 0;
    vars.flag_unk1.* = 0;
    vars.bg1_x_offset.* = 0;
    vars.bg1_y_offset.* = 0;
}

pub export fn OverworldEntrance_DrawManyTR() callconv(.c) void {
    var j: u16 = 0xe78;
    for ([_]u16{
        0x99e, 0x9a0, 0x9a2, 0x9a4,
        0xa1e, 0xa20, 0xa22, 0xa24,
        0xa9e, 0xaa0, 0xaa2, 0xaa4,
        0xb1e, 0xb20, 0xb22, 0xb24,
    }) |p| {
        Overworld_DrawMap16_Persist(p, j);
        j +%= 1;
    }
    vars.nmi_load_bg_from_vram.* = 1;
    vars.nmi_disable_core_updates.* = 1;
}

pub export fn Overworld_AnimateEntrance_GanonsTower() callconv(.c) void {
    switch (vars.subsubmodule_index.*) {
        0, 1 => {
            vars.save_ow_event_info[loPtr(vars.overworld_screen_index).*] |= 0x20;
            GanonTowerEntrance_Func1();
        },
        2 => {
            GanonTowerEntrance_Func1();
            if (vars.TS_copy.* == 0) {
                vars.TS_copy.* = 1;
                vars.some_menu_ctr.* +%= 1;
                if (vars.some_menu_ctr.* == 3) {
                    vars.some_menu_ctr.* = 0;
                    vars.sound_effect_ambient.* = 7;
                } else {
                    vars.subsubmodule_index.* = 0;
                }
            }
        },
        3 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 48)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x45e, 0xe88);
            Overworld_DrawMap16_Persist(0x460, 0xe89);
            Overworld_DrawMap16_Persist(0x4de, 0xea2);
            Overworld_DrawMap16_Persist(0x4e0, 0xea3);
            Overworld_DrawMap16_Persist(0x55e, 0xe8a);
            Overworld_DrawMap16_Persist(0x560, 0xe8b);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        4 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 48)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x45e, 0xe8c);
            Overworld_DrawMap16_Persist(0x460, 0xe8d);
            Overworld_DrawMap16_Persist(0x4de, 0xe8e);
            Overworld_DrawMap16_Persist(0x4e0, 0xe8f);
            Overworld_DrawMap16_Persist(0x55e, 0xe90);
            Overworld_DrawMap16_Persist(0x560, 0xe91);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        5 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 52)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x45e, 0xe92);
            Overworld_DrawMap16_Persist(0x460, 0xe93);
            Overworld_DrawMap16_Persist(0x4de, 0xe94);
            Overworld_DrawMap16_Persist(0x4e0, 0xe94);
            Overworld_DrawMap16_Persist(0x55e, 0xe95);
            Overworld_DrawMap16_Persist(0x560, 0xe95);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        6 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 32)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x45e, 0xe96);
            Overworld_DrawMap16_Persist(0x460, 0xe97);
            Overworld_DrawMap16_Persist(0x4de, 0xe98);
            Overworld_DrawMap16_Persist(0x4e0, 0xe99);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        7 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 32)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x4de, 0xe9a);
            Overworld_DrawMap16_Persist(0x4e0, 0xe9b);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        8 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 32)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x4de, 0xe9c);
            Overworld_DrawMap16_Persist(0x4e0, 0xe9d);
            Overworld_DrawMap16_Persist(0x55e, 0xe9e);
            Overworld_DrawMap16_Persist(0x560, 0xe9f);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        9 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 32)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x55e, 0xe9a);
            Overworld_DrawMap16_Persist(0x560, 0xe9b);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        10 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 32)
                return;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x55e, 0xe9c);
            Overworld_DrawMap16_Persist(0x560, 0xe9d);
            Overworld_DrawMap16_Persist(0x5de, 0xea0);
            Overworld_DrawMap16_Persist(0x5e0, 0xea1);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        11 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 32)
                return;
            vars.sound_effect_ambient.* = 5;
            OverworldEntrance_AdvanceAndBoom();
            Overworld_DrawMap16_Persist(0x5de, 0xe9a);
            Overworld_DrawMap16_Persist(0x5e0, 0xe9b);
            vars.nmi_load_bg_from_vram.* = 1;
        },
        12 => {
            vars.some_menu_ctr.* +%= 1;
            if (vars.some_menu_ctr.* != 72)
                return;
            OverworldEntrance_PlayJingle();
            vars.some_menu_ctr.* = 0;
            vars.music_control.* = 13;
            vars.sound_effect_ambient.* = 9;
        },
        else => {},
    }
}

pub export fn OverworldEntrance_AdvanceAndBoom() callconv(.c) void {
    vars.subsubmodule_index.* +%= 1;
    vars.overworld_entrance_sequence_counter.* = 0;
    vars.sound_effect_1.* = 12;
    vars.sound_effect_2.* = 7;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Overworld_FindMap16VRAMAddress matches the C bit arithmetic" {
    // (((addr & 0x3f) >= 0x20) ? 0x400 : 0) + (((addr & 0xfff) >= 0x800) ? 0x800 : 0)
    //   + (addr & 0x1f) + ((addr & 0x780) >> 1)
    try std.testing.expectEqual(@as(u16, 0x000), Overworld_FindMap16VRAMAddress(0x000));
    try std.testing.expectEqual(@as(u16, 0x400), Overworld_FindMap16VRAMAddress(0x020));
    try std.testing.expectEqual(@as(u16, 0x800), Overworld_FindMap16VRAMAddress(0x800));
    try std.testing.expectEqual(@as(u16, 0x45f), Overworld_FindMap16VRAMAddress(0x0ff));
    // 0xc42 is the tile Overworld_AlterWeathervane redraws.
    try std.testing.expectEqual(@as(u16, 0xa02), Overworld_FindMap16VRAMAddress(0xc42));
}

test "Decompress_bank02 handles each command form" {
    var dst: [32]u8 = @splat(0);

    // cmd 0x02: (cmd & 0xe0) == 0 -> copy (cmd & 0x1f) + 1 = 3 literal bytes.
    {
        const src = [_]u8{ 0x02, 'A', 'B', 'C', 0xff };
        try std.testing.expectEqual(@as(c_int, 3), Decompress_bank02(&dst, &src));
        try std.testing.expectEqualSlices(u8, "ABC", dst[0..3]);
    }
    // cmd 0x22 -> 0x20: single byte repeated.
    {
        const src = [_]u8{ 0x22, 0x5a, 0xff };
        try std.testing.expectEqual(@as(c_int, 3), Decompress_bank02(&dst, &src));
        try std.testing.expectEqualSlices(u8, &.{ 0x5a, 0x5a, 0x5a }, dst[0..3]);
    }
    // cmd 0x42 -> 0x40: two bytes alternating.
    {
        const src = [_]u8{ 0x42, 0x11, 0x22, 0xff };
        try std.testing.expectEqual(@as(c_int, 3), Decompress_bank02(&dst, &src));
        try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x11 }, dst[0..3]);
    }
    // cmd 0x62 -> 0x60: byte incrementing by one each step.
    {
        const src = [_]u8{ 0x62, 0x10, 0xff };
        try std.testing.expectEqual(@as(c_int, 3), Decompress_bank02(&dst, &src));
        try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x11, 0x12 }, dst[0..3]);
    }
    // cmd 0x82 -> 0x80: back-reference into what has been emitted so far.
    {
        const src = [_]u8{ 0x02, 'A', 'B', 'C', 0x82, 0x00, 0x00, 0xff };
        try std.testing.expectEqual(@as(c_int, 6), Decompress_bank02(&dst, &src));
        try std.testing.expectEqualSlices(u8, "ABCABC", dst[0..6]);
    }
}

test "Overworld_LoadEventOverlay writes the per-screen overlay tiles" {
    @memset(vars.dung_bg2[0 .. 64 * 64], 0);
    vars.overworld_screen_index.* = 3;
    Overworld_LoadEventOverlay();
    try std.testing.expectEqual(@as(u16, 0x212), vars.dung_bg2[mapXY(16, 14)]);

    @memset(vars.dung_bg2[0 .. 64 * 64], 0);
    vars.overworld_screen_index.* = 20;
    Overworld_LoadEventOverlay();
    try std.testing.expectEqual(@as(u16, 0xdd1), vars.dung_bg2[mapXY(25, 10)]);
    try std.testing.expectEqual(@as(u16, 0xdda), vars.dung_bg2[mapXY(26, 12)]);
}

test "Overworld_LoadEventOverlay shared goto target draws the 2x2 block" {
    // Screens that `goto loc_8EF7B4` in the C all draw 0x918..0x91b at their own
    // origin; this covers the restructure of that goto into a trailing block.
    @memset(vars.dung_bg2[0 .. 64 * 64], 0);
    vars.overworld_screen_index.* = 58;
    Overworld_LoadEventOverlay();
    const x = mapXY(15, 20);
    try std.testing.expectEqual(@as(u16, 0x918), vars.dung_bg2[x + mapXY(0, 0)]);
    try std.testing.expectEqual(@as(u16, 0x919), vars.dung_bg2[x + mapXY(1, 0)]);
    try std.testing.expectEqual(@as(u16, 0x91a), vars.dung_bg2[x + mapXY(0, 1)]);
    try std.testing.expectEqual(@as(u16, 0x91b), vars.dung_bg2[x + mapXY(1, 1)]);

    // A screen with its own tile list must not also run the shared block.
    @memset(vars.dung_bg2[0 .. 64 * 64], 0);
    vars.overworld_screen_index.* = 3;
    Overworld_LoadEventOverlay();
    try std.testing.expectEqual(@as(u16, 0), vars.dung_bg2[mapXY(3, 10)]);
}

test "Overworld_SetFixedColAndScroll picks the light world fixed color" {
    // Screen 0: not 0x80/0x81, not 0x5b, low bits not 3/5/7, bit 0x40 clear,
    // so p = 0x2669. The COLDATA override is skipped because si == 0, and the
    // `goto getout` path is not taken.
    vars.overworld_screen_index.* = 0;
    vars.submodule_index.* = 0;
    vars.flag_update_cgram_in_nmi.* = 0;
    vars.BG2VOFS_copy2.* = 0x1234;
    vars.BG2HOFS_copy2.* = 0x5678;
    Overworld_SetFixedColAndScroll();
    try std.testing.expectEqual(@as(u16, 0x2669), vars.main_palette_buffer[0]);
    try std.testing.expectEqual(@as(u16, 0x2669), vars.aux_palette_buffer[0]);
    try std.testing.expectEqual(@as(u16, 0x2669), vars.main_palette_buffer[32]);
    try std.testing.expectEqual(@as(u8, 0x20), vars.COLDATA_copy0.*);
    try std.testing.expectEqual(@as(u8, 0x40), vars.COLDATA_copy1.*);
    try std.testing.expectEqual(@as(u8, 0x80), vars.COLDATA_copy2.*);
    try std.testing.expectEqual(@as(u16, 0x1234), vars.BG1VOFS_copy2.*);
    try std.testing.expectEqual(@as(u16, 0x5678), vars.BG1HOFS_copy2.*);
    try std.testing.expectEqual(@as(u8, 1), vars.TS_copy.*);
    try std.testing.expectEqual(@as(u8, 1), vars.flag_update_cgram_in_nmi.*);
}

test "Overworld_Memorize_Map16_Change skips the two ignored tile values" {
    vars.num_memorized_tiles.* = 0;
    Overworld_Memorize_Map16_Change(0x100, 0xdc5);
    Overworld_Memorize_Map16_Change(0x200, 0xdc9);
    try std.testing.expectEqual(@as(u16, 0), vars.num_memorized_tiles.*);

    Overworld_Memorize_Map16_Change(0x300, 0xda4);
    try std.testing.expectEqual(@as(u16, 2), vars.num_memorized_tiles.*);
    try std.testing.expectEqual(@as(u16, 0x300), vars.memorized_tile_addr[0]);
    try std.testing.expectEqual(@as(u16, 0xda4), vars.memorized_tile_value[0]);
}

test "turtlerock_ctr and ganonentrance_ctr alias the same byte" {
    // overworld.c #defines both as (some_menu_ctr); the port must share storage.
    vars.some_menu_ctr.* = 0;
    vars.overworld_entrance_sequence_counter.* = 77;
    try std.testing.expectEqual(@as(u8, 77), vars.some_menu_ctr.*);
}

test "special overworld areas do not index past the offset base tables" {
    // overworld_screen_index & 0xbf keeps bit 7, so entering a special area
    // (0x80 and up) asks for an entry this 64-entry table does not have.
    try std.testing.expectEqual(@as(usize, 64), tables.kOverworld_OffsetBaseY.len);
    try std.testing.expectEqual(@as(usize, 64), tables.kOverworld_OffsetBaseX.len);

    // In range the lookup is unchanged.
    for ([_]usize{ 0, 1, 10, 63 }) |j| {
        const base = overworldOffsetBase(j).?;
        try std.testing.expectEqual(tables.kOverworld_OffsetBaseY[j], base.y);
        try std.testing.expectEqual(tables.kOverworld_OffsetBaseX[j] >> 3, base.x);
    }

    // A special area reports no entry, and the caller leaves the offsets alone;
    // Overworld_EnterSpecialArea sets them from kSpExit_* moments later.
    for ([_]u16{ 0x80, 0x81, 0x8f, 0xbf }) |idx|
        try std.testing.expect(overworldOffsetBase(idx & 0xbf) == null);
}
