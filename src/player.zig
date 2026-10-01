//! Port of src/player.c: Link himself -- the player state machine, movement and
//! collision, item usage, sword and spin attack, dashing, swimming, ledge hops,
//! pits, and the camera/door handling that follows his position.
const std = @import("std");
const vars = @import("variables.zig");
const tables = @import("player_tables.zig");
const features = @import("features.zig");
const misc = @import("misc.zig");
const load_gfx = @import("load_gfx.zig");
const hud = @import("hud.zig");
const overworld = @import("overworld.zig");
const sprite = @import("sprite.zig");
const tagalong = @import("tagalong.zig");
const tile_detect = @import("tile_detect.zig");
const player_oam = @import("player_oam.zig");
const rtl = @import("zelda_rtl.zig");

const g_ram = &vars.g_ram;
const OamEnt = vars.OamEnt;

/// zelda_rtl.h: typedef void PlayerHandlerFunc();
const PlayerHandlerFunc = fn () callconv(.c) void;

// ---------------------------------------------------------------------------
// types.h
// ---------------------------------------------------------------------------

/// Alias rather than a second definition: Zig types are nominal, so a local
/// copy would not coerce into overworld.zig's identical struct.
pub const Point16U = overworld.Point16U;
pub const PointU8 = extern struct { x: u8, y: u8 };

/// ancilla.h
pub const CheckPlayerCollOut = extern struct {
    r4: u16,
    r6: u16,
    r8: u16,
    r10: u16,
};

// ---------------------------------------------------------------------------
// player.h -- the player state machine's states. These are compared as plain
// integers all over the file, so the values must match exactly.
// ---------------------------------------------------------------------------

const kPlayerState_Ground = 0;
const kPlayerState_FallingIntoHole = 1;
const kPlayerState_RecoilWall = 2;
const kPlayerState_SpinAttacking = 3;
const kPlayerState_Swimming = 4;
const kPlayerState_TurtleRock = 5;
const kPlayerState_RecoilOther = 6;
const kPlayerState_Electrocution = 7;
const kPlayerState_Ether = 8;
const kPlayerState_Bombos = 9;
const kPlayerState_Quake = 10;
const kPlayerState_FallOfLeftRightLedge = 12;
const kPlayerState_JumpOffLedgeDiag = 14;
const kPlayerState_StartDash = 17;
const kPlayerState_StopDash = 18;
const kPlayerState_Hookshot = 19;
const kPlayerState_Mirror = 20;
const kPlayerState_HoldUpItem = 21;
const kPlayerState_AsleepInBed = 22;
const kPlayerState_PermaBunny = 23;
const kPlayerState_ReceivingEther = 25;
const kPlayerState_ReceivingBombos = 26;
const kPlayerState_OpeningDesertPalace = 27;
const kPlayerState_TempBunny = 28;
const kPlayerState_PullForRupees = 29;
const kPlayerState_SpinAttackMotion = 30;

/// zelda_rtl.h button bits, spelled the same way hud.zig does.
const kJoypadL_A: u8 = 0x80;
const kJoypadL_X: u8 = 0x40;
const kJoypadL_L: u8 = 0x20;
const kJoypadL_R: u8 = 0x10;
const kJoypadH_B: u8 = 0x80;
const kJoypadH_Y: u8 = 0x40;
const kJoypadH_Select: u8 = 0x20;
const kJoypadH_Start: u8 = 0x10;
const kJoypadH_Up: u8 = 0x8;
const kJoypadH_Down: u8 = 0x4;
const kJoypadH_Left: u8 = 0x2;
const kJoypadH_Right: u8 = 0x1;
const kJoypadH_AnyDir: u8 = 0xf;

/// hud.h
const kHudItem_Bottle1: u8 = 21;

// ---------------------------------------------------------------------------
// Helpers for the C macros and static inlines this file leans on.
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

inline fn sign8(v: u8) bool {
    return v & 0x80 != 0;
}

inline fn sign16(v: u16) bool {
    return v & 0x8000 != 0;
}

inline fn abs16(v: u16) u16 {
    return if (sign16(v)) 0 -% v else v;
}

inline fn IntMin(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

/// misc.h: the current oam write cursor, as a pointer into work ram.
fn GetOamCurPtr() [*]align(1) OamEnt {
    return @ptrCast(&g_ram[vars.oam_cur_ptr.*]);
}

/// The index of an OamEnt pointer within oam_buf, for bytewise_extended_oam.
inline fn oamIndex(oam: [*]align(1) OamEnt) usize {
    return (@intFromPtr(oam) - @intFromPtr(vars.oam_buf)) / @sizeOf(OamEnt);
}

/// sprite.h static inline.
fn SetOamPlain(oam: [*]align(1) OamEnt, x: u8, y: u8, charnum: u8, flags: u8, big: u8) void {
    oam[0].x = x;
    oam[0].y = y;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    vars.bytewise_extended_oam[oamIndex(oam)] = big;
}

// ---------------------------------------------------------------------------
// Still in C: ancilla.c, dungeon.c and sprite_main.c.
// ---------------------------------------------------------------------------

extern fn AddSwordBeam(y: u8) void;
extern fn AdjustQuadrantAndCamera_down() void;
extern fn AdjustQuadrantAndCamera_left() void;
extern fn AdjustQuadrantAndCamera_right() void;
extern fn AdjustQuadrantAndCamera_up() void;
extern fn AncillaAdd_Arrow(a: u8, ax: u8, ay: u8, xcoord: u16, ycoord: u16) c_int;
extern fn AncillaAdd_Blanket(a: u8) void;
extern fn AncillaAdd_Bomb(a: u8, y: u8) void;
extern fn AncillaAdd_BombosSpell(a: u8, y: u8) void;
extern fn AncillaAdd_Boomerang(a: u8, y: u8) u8;
extern fn AncillaAdd_BunnyPoof(a: u8, y: u8) void;
extern fn AncillaAdd_CapePoof(a: u8, y: u8) void;
extern fn AncillaAdd_ChargedSpinAttackSparkle() void;
extern fn AncillaAdd_DashDust(a: u8, y: u8) void;
extern fn AncillaAdd_DashDust_charging(a: u8, y: u8) void;
extern fn AncillaAdd_DashTremor(a: u8, y: u8) void;
extern fn AncillaAdd_Duck_take_off(a: u8, y: u8) void;
extern fn AncillaAdd_DwarfPoof(ain: u8, yin: u8) void;
extern fn AncillaAdd_EtherSpell(a: u8, y: u8) void;
extern fn AncillaAdd_ExplodingWeatherVane(a: u8, y: u8) void;
extern fn AncillaAdd_FallingPrize(a: u8, item_idx: u8, yv: u8) c_int;
extern fn AncillaAdd_FireRodShot(stype: u8, y: u8) void;
extern fn AncillaAdd_GraveStone(ain: u8, yin: u8) void;
extern fn AncillaAdd_IceRodShot(a: u8, y: u8) void;
extern fn AncillaAdd_LampFlame(a: u8, y: u8) void;
extern fn AncillaAdd_MagicPowder(a: u8, y: u8) void;
extern fn AncillaAdd_QuakeSpell(a: u8, y: u8) void;
extern fn AncillaAdd_Snoring(a: u8, y: u8) void;
extern fn AncillaAdd_SomariaBlock(stype: u8, y: u8) c_int;
extern fn AncillaAdd_SpinAttackInitSpark(a: u8, x: u8, y: u8) void;
extern fn AncillaAdd_Splash(a: u8, y: u8) bool;
extern fn AncillaAdd_SwordSwingSparkle(a: u8, y: u8) void;
extern fn AncillaAdd_WallTapSpark(a: u8, y: u8) void;
extern fn AncillaSpawn_SwordChargeSparkle() void;
extern fn Ancilla_AddAncilla(a: u8, y: u8) c_int;
extern fn Ancilla_AddHitStars(a: u8, y: u8) void;
extern fn Ancilla_CheckLinkCollision(k: c_int, j: c_int, out: *CheckPlayerCollOut) bool;
extern fn Ancilla_CheckTileCollision_Class2(k: c_int) bool;
extern fn Ancilla_GetX(k: c_int) u16;
extern fn Ancilla_GetY(k: c_int) u16;
extern fn Ancilla_MoveX(k: c_int) void;
extern fn Ancilla_MoveY(k: c_int) void;
extern fn Ancilla_MoveZ(k: c_int) void;
extern fn Ancilla_SetXY(k: c_int, x: u16, y: u16) void;
extern fn Ancilla_Sfx2_Pan(k: c_int, v: u8) void;
extern fn Ancilla_Sfx3_Pan(k: c_int, v: u8) void;
extern fn Ancilla_TerminateSelectInteractives(y: u8) u8;
extern fn Dung_StartInterRoomTrans_Left_Plus() void;
extern fn Dungeon_CheckForAndIDLiftableTile() u16;
extern fn Dungeon_DeleteRupeeTile(x: u16, y: u16) void;
extern fn Dungeon_FlagRoomData_Quadrants() void;
extern fn Dungeon_GetTeleMsg(room: c_int) u16;
extern fn Dungeon_IsPitThatHurtsPlayer() bool;
extern fn Dungeon_LiftAndReplaceLiftable(pt: *Point16U) u8;
extern fn Dungeon_StartInterRoomTrans_Up() void;
extern fn HandleEdgeTransitionMovementEast_RightBy8() void;
extern fn HandleEdgeTransitionMovementSouth_DownBy16() void;
extern fn Mirror_SaveRoomData() void;
extern fn OpenChestForItem(tile: u8, chest_position: *c_int) u8;
extern fn ReleaseBeeFromBottle(x_value: c_int) c_int;
extern fn SetAndSaveVisitedQuadrantFlags() void;
extern fn Sprite_SpawnSmallSplash(k: c_int) c_int;

// ---------------------------------------------------------------------------
// Tables the generator cannot emit.
//
// The seven below are function-local statics whose names do not start with `k`,
// so the generator's `k\w+` pattern never saw them. They are transcribed here
// verbatim, including the deliberate out-of-bounds tail on y1 that the C marks
// as a bug in the original game.
// ---------------------------------------------------------------------------

/// Link_HandleDiagonalKickback
const kKickback_x0 = [10]i8{ 0, 1, 1, 1, 2, 2, 2, 3, 3, 3 };
const kKickback_x1 = [10]i8{ 0, -1, -1, -1, -2, -2, -2, -3, -3, -3 };
const kKickback_y0 = [10]i8{ 0, 0, 0, 1, 1, 1, 2, 2, 2, 3 };
/// "Bug in zelda, might read index 15" -- the tail past index 9 is whatever
/// followed the array in the original ROM, and is reproduced rather than fixed.
const kKickback_y1 = [16]i8{
    0,          1,          1,          2,          2,          2,          3,          3,
    3,          3,          @bitCast(@as(u8, 0xa5)), 0x30,      @bitCast(@as(u8, 0xf0)), 0x04,
    @bitCast(@as(u8, 0xa5)), 0x31,
};

/// PushBlock_AttemptToPushTheBlock. Indexed by PushBlock_GetTargetTileFlag's
/// u8 return, so all 256 entries are reachable.
const kPushBlockTileFlags = [256]u8{
    0, 1, 2, 3, 2, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
    0, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1,
    0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};

/// Link_HandleMovingAnimation_StartWithDash
const kAnimDelayByDir = [16]u8{ 4, 4, 4, 4, 1, 1, 1, 1, 2, 2, 2, 2, 8, 8, 8, 8 };
const kAnimDelayByStep = [24]u8{
    1, 2, 3, 2, 2, 2, 3, 2, 1, 1, 2, 1,
    1, 1, 2, 1, 2, 2, 3, 2, 2, 2, 3, 2,
};

/// The player state dispatch table. States 5 and 15/16 map to handlers that
/// assert in the C; they are reproduced as-is.
const kPlayerHandlers = [31]*const PlayerHandlerFunc{
    &LinkState_Default,
    &LinkState_Pits,
    &LinkState_Recoil,
    &LinkState_SpinAttack,
    &PlayerHandler_04_Swimming,
    &LinkState_OnIce,
    &LinkState_Recoil,
    &LinkState_Zapped,
    &LinkState_UsingEther,
    &LinkState_UsingBombos,
    &LinkState_UsingQuake,
    &LinkHop_HoppingSouthOW,
    &LinkState_HoppingHorizontallyOW,
    &LinkState_HoppingDiagonallyUpOW,
    &LinkState_HoppingDiagonallyDownOW,
    &LinkState_0F,
    &LinkState_0F,
    &LinkState_Dashing,
    &LinkState_ExitingDash,
    &LinkState_Hookshotting,
    &LinkState_CrossingWorlds,
    &PlayerHandler_15_HoldItem,
    &LinkState_Sleeping,
    &PlayerHandler_17_Bunny,
    &LinkState_HoldingBigRock,
    &LinkState_ReceivingEther,
    &LinkState_ReceivingBombos,
    &LinkState_ReadingDesertTablet,
    &LinkState_TemporaryBunny,
    &LinkState_TreePull,
    &LinkState_SpinAttack,
};

/// player.c file-scope: guards HandleIndoorCameraAndDoors against running twice
/// in one frame, which would corrupt camera positioning.
var g_ApplyLinksMovementToCamera_called: bool = false;

/// player.c defined this non-static and player.h declares it, so player_oam.zig
/// links against it. player_tables.zig only holds a `pub const`, which emits no
/// symbol, so the export has to live here.
pub export const kSwimmingTab1 = tables.kSwimmingTab1;
pub export const kSwimmingTab2 = tables.kSwimmingTab2;

/// player.c: static inline uint8 BitSum4(uint8 t)
inline fn BitSum4(t: u8) u8 {
    return (t & 1) + ((t >> 1) & 1) + ((t >> 2) & 1) + ((t >> 3) & 1);
}

// ---------------------------------------------------------------------------
// Entry points and the ground state
// ---------------------------------------------------------------------------

pub export fn Dungeon_HandleLayerChange() callconv(.c) void {
    vars.link_is_on_lower_level_mirror.* = 1;
    if (vars.kind_of_in_room_staircase.* == 0)
        loPtr(vars.dungeon_room_index).* +%= 16;
    if (vars.kind_of_in_room_staircase.* != 2)
        vars.link_is_on_lower_level.* = 1;
    vars.about_to_jump_off_ledge.* = 0;
    SetAndSaveVisitedQuadrantFlags();
}

pub export fn CacheCameraProperties() callconv(.c) void {
    vars.BG2HOFS_copy2_cached.* = vars.BG2HOFS_copy2.*;
    vars.BG2VOFS_copy2_cached.* = vars.BG2VOFS_copy2.*;
    vars.link_y_coord_cached.* = vars.link_y_coord.*;
    vars.link_x_coord_cached.* = vars.link_x_coord.*;
    vars.room_scroll_vars_y_vofs1_cached.* = vars.room_bounds_y.named.a0;
    vars.room_scroll_vars_y_vofs2_cached.* = vars.room_bounds_y.named.a1;
    vars.room_scroll_vars_x_vofs1_cached.* = vars.room_bounds_x.named.a0;
    vars.room_scroll_vars_x_vofs2_cached.* = vars.room_bounds_x.named.a1;
    vars.up_down_scroll_target_cached.* = vars.up_down_scroll_target.*;
    vars.up_down_scroll_target_end_cached.* = vars.up_down_scroll_target_end.*;
    vars.left_right_scroll_target_cached.* = vars.left_right_scroll_target.*;
    vars.left_right_scroll_target_end_cached.* = vars.left_right_scroll_target_end.*;
    vars.camera_y_coord_scroll_low_cached.* = vars.camera_y_coord_scroll_low.*;
    vars.camera_x_coord_scroll_low_cached.* = vars.camera_x_coord_scroll_low.*;
    vars.quadrant_fullsize_x_cached.* = vars.quadrant_fullsize_x.*;
    vars.quadrant_fullsize_y_cached.* = vars.quadrant_fullsize_y.*;
    vars.link_quadrant_x_cached.* = vars.link_quadrant_x.*;
    vars.link_quadrant_y_cached.* = vars.link_quadrant_y.*;
    vars.link_direction_facing_cached.* = vars.link_direction_facing.*;
    vars.link_is_on_lower_level_cached.* = vars.link_is_on_lower_level.*;
    vars.link_is_on_lower_level_mirror_cached.* = vars.link_is_on_lower_level_mirror.*;
    vars.is_standing_in_doorway_cahed.* = vars.is_standing_in_doorway.*;
    vars.dung_cur_floor_cached.* = vars.dung_cur_floor.*;
}

pub export fn CheckAbilityToSwim() callconv(.c) void {
    if (vars.link_is_bunny_mirror.* == 0 and vars.link_item_flippers.* != 0)
        return;
    if (vars.link_item_moon_pearl.* != 0)
        vars.link_is_bunny_mirror.* = 0;
    vars.link_visibility_status.* = 0xc;
    vars.submodule_index.* = if (vars.player_is_indoors.* != 0) 20 else 42;
}

pub export fn Link_Main() callconv(.c) void {
    vars.link_x_coord_prev.* = vars.link_x_coord.*;
    vars.link_y_coord_prev.* = vars.link_y_coord.*;
    vars.flag_unk1.* = 0;
    if (vars.flag_is_link_immobilized.* == 0)
        Link_ControlHandler();
    HandleSomariaAndGraves();
}

pub export fn Link_ControlHandler() callconv(.c) void {
    if (vars.link_give_damage.* != 0) {
        if (vars.link_cape_mode.* != 0) {
            vars.link_give_damage.* = 0;
            vars.link_auxiliary_state.* = 0;
            vars.link_incapacitated_timer.* = 0;
        } else {
            if (vars.link_disable_sprite_damage.* == 0) {
                const dmg = vars.link_give_damage.*;
                vars.link_give_damage.* = 0;
                if (vars.ancilla_type[0] == 5 and vars.player_handler_timer.* == 0 and
                    vars.link_delay_timer_spin_attack.* != 0)
                {
                    vars.ancilla_type[0] = 0;
                    vars.flag_for_boomerang_in_place.* = 0;
                }
                if (vars.countdown_for_blink.* == 0)
                    vars.countdown_for_blink.* = 58;
                _ = misc.Ancilla_Sfx2_Near(38);
                vars.number_of_times_hurt_by_sprites.* +%= 1;
                var new_dmg = vars.link_health_current.* -% dmg;
                if (new_dmg == 0 or new_dmg >= 0xa8) {
                    vars.mapbak_TM.* = vars.TM_copy.*;
                    vars.mapbak_TS.* = vars.TS_copy.*;
                    vars.saved_module_for_menu.* = vars.main_module_index.*;
                    vars.main_module_index.* = 18;
                    vars.submodule_index.* = 1;
                    vars.countdown_for_blink.* = 0;
                    vars.link_hearts_filler.* = 0;
                    new_dmg = 0;
                }
                vars.link_health_current.* = new_dmg;
            }
        }
    }
    if (vars.link_player_handler_state.* != 0)
        Player_CheckHandleCapeStuff();
    kPlayerHandlers[vars.link_player_handler_state.*]();
}

pub export fn LinkState_Default() callconv(.c) void {
    CacheCameraPropertiesIfOutdoors();
    if (Link_HandleBunnyTransformation()) {
        if (vars.link_player_handler_state.* == 23)
            PlayerHandler_17_Bunny();
        return;
    }
    vars.fallhole_var2.* = 0;
    if (vars.link_auxiliary_state.* != 0) {
        HandleLink_From1D();
    } else {
        PlayerHandler_00_Ground_3();
    }
}

pub export fn HandleLink_From1D() callconv(.c) void {
    vars.link_item_in_hand.* = 0;
    vars.link_position_mode.* = 0;
    vars.link_debug_value_1.* = 0;
    vars.link_debug_value_2.* = 0;
    vars.link_var30d.* = 0;
    vars.link_var30e.* = 0;
    vars.some_animation_timer_steps.* = 0;
    vars.bitfield_for_a_button.* = 0;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
    vars.link_state_bits.* = 0;
    vars.link_picking_throw_state.* = 0;
    vars.link_grabbing_wall.* = 0;
    vars.bitmask_of_dragstate.* = 0;
    Link_ResetSwimmingState();
    vars.link_cant_change_direction.* &= ~@as(u8, 1);
    vars.link_z_coord.* &= 0xff;
    if (vars.link_electrocute_on_touch.* != 0) {
        if (vars.link_cape_mode.* != 0)
            Link_ForceUnequipCape_quietly();
        Link_ResetSwordAndItemUsage();
        vars.link_disable_sprite_damage.* = 1;
        vars.player_handler_timer.* = 0;
        vars.link_delay_timer_spin_attack.* = 2;
        vars.link_animation_steps.* = 0;
        vars.link_direction.* &= ~@as(u8, 0xf);
        misc.Ancilla_Sfx3_Near(43);
        vars.link_player_handler_state.* = 7;
        LinkState_Zapped();
    } else {
        vars.link_moving_against_diag_tile.* = 0;
        vars.link_player_handler_state.* = 2;
        LinkState_Recoil();
    }
}

pub export fn PlayerHandler_00_Ground_3() callconv(.c) void {
    g_ApplyLinksMovementToCamera_called = false;

    vars.link_z_coord.* = 0xffff;
    vars.link_actual_vel_z.* = 0xff;
    vars.link_recoilmode_timer.* = 0;

    // `goto getout_clear_vel` lands on a label inside the `if (link_unk_master_sword)`
    // body near the end, so taking it clears the velocities unconditionally.
    var clear_vel = false;

    if (!Link_HandleToss()) {
        Link_HandleAPress();
        if ((vars.link_state_bits.* | vars.link_grabbing_wall.*) == 0 and
            vars.link_unk_master_sword.* == 0 and
            vars.link_player_handler_state.* != kPlayerState_StartDash)
        {
            Link_HandleYItem();
            // Ensure we're not handling potions. Things further down don't assume
            // this and change the module indexes randomly. This also fixes a bug
            // where bombos, ether, quake get aborted if you use spin attack at the
            // same time.
            if ((features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0 and
                ((vars.main_module_index.* == 14 and vars.submodule_index.* != 2) or
                    vars.link_player_handler_state.* == kPlayerState_Bombos or
                    vars.link_player_handler_state.* == kPlayerState_Ether or
                    vars.link_player_handler_state.* == kPlayerState_Quake))
            {
                clear_vel = true;
            } else if (vars.sram_progress_indicator.* != 0) {
                Link_HandleSwordCooldown();
                if (vars.link_player_handler_state.* == 3)
                    clear_vel = true;
            }
        }
    }

    if (!clear_vel) {
        Link_HandleCape_passive_LiftCheck();
        if (vars.link_incapacitated_timer.* != 0) {
            vars.link_moving_against_diag_tile.* = 0;
            vars.link_var30d.* = 0;
            vars.link_var30e.* = 0;
            vars.some_animation_timer_steps.* = 0;
            vars.bitfield_for_a_button.* = 0;
            vars.link_picking_throw_state.* = 0;
            vars.link_state_bits.* = 0;
            vars.link_grabbing_wall.* = 0;
            if (vars.button_mask_b_y.* & 0x80 == 0)
                vars.link_cant_change_direction.* &= ~@as(u8, 1);
            Link_HandleRecoilAndTimer(false);
            return;
        }

        // Both `goto endif_3` jumps land just past this chain.
        bail: {
            if (vars.link_unk_master_sword.* != 0) {
                vars.link_direction.* = 0;
            } else if (vars.link_is_transforming.* == 0 and
                (vars.link_grabbing_wall.* & ~@as(u8, 2)) == 0 and
                (vars.link_state_bits.* & 0x7f) == 0 and
                ((vars.link_state_bits.* & 0x80) == 0 or (vars.link_picking_throw_state.* & 1) == 0) and
                vars.link_item_in_hand.* == 0 and vars.link_position_mode.* == 0 and
                (vars.button_b_frames.* >= 9 or (vars.button_mask_b_y.* & 0x20) != 0 or
                    (vars.button_mask_b_y.* & 0x80) == 0))
            {
                // if_4
                if (vars.link_flag_moving.* != 0) {
                    vars.swimcoll_var9[0] = 0x180;
                    vars.swimcoll_var9[1] = 0x180;
                    Link_HandleSwimMovements();
                    return;
                }
                ResetAllAcceleration();

                var dir: u8 = @truncate(vars.force_move_any_direction.* & 0xf);
                if (dir == 0) {
                    if (vars.link_grabbing_wall.* & 2 != 0)
                        break :bail;
                    dir = vars.joypad1H_last.* & kJoypadH_AnyDir;
                    if (dir == 0) {
                        vars.link_x_vel.* = 0;
                        vars.link_y_vel.* = 0;
                        vars.link_direction.* = 0;
                        vars.link_direction_last.* = 0;
                        vars.link_animation_steps.* = 0;
                        vars.bitmask_of_dragstate.* &= ~@as(u8, 0xf);
                        vars.link_timer_push_get_tired.* = 32;
                        vars.link_timer_jump_ledge.* = 19;
                        break :bail;
                    }
                }
                vars.link_direction.* = dir;
                if (dir != vars.link_direction_last.*) {
                    vars.link_direction_last.* = dir;
                    vars.link_subpixel_x.* = 0;
                    vars.link_subpixel_y.* = 0;
                    vars.link_moving_against_diag_tile.* = 0;
                    vars.bitmask_of_dragstate.* = 0;
                    vars.link_timer_push_get_tired.* = 32;
                    vars.link_timer_jump_ledge.* = 19;
                }
            }
        }
        // endif_3:
        Link_HandleDiagonalCollision();
        Link_HandleVelocity();
        Link_HandleCardinalCollision();
        Link_HandleMovingAnimation_FullLongEntry();
    }

    // getout_clear_vel:
    if (clear_vel or vars.link_unk_master_sword.* != 0) {
        vars.link_y_vel.* = 0;
        vars.link_x_vel.* = 0;
    }

    vars.fallhole_var1.* = 0;

    // HandleIndoorCameraAndDoors must not be called twice in the same frame,
    // this might mess up camera positioning. For example when using spin attack
    // in between bumpers.
    if (g_ApplyLinksMovementToCamera_called and
        (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0)
        return;

    HandleIndoorCameraAndDoors();
}

pub export fn Link_HandleBunnyTransformation() callconv(.c) bool {
    if (vars.link_timer_tempbunny.* == 0)
        return false;

    if (vars.link_need_for_poof_for_transform.* == 0) {
        if (vars.link_player_handler_state.* == kPlayerState_PermaBunny or
            vars.link_player_handler_state.* == kPlayerState_TempBunny)
        {
            vars.link_timer_tempbunny.* = 0;
            return false;
        }
        if (vars.link_picking_throw_state.* & 2 != 0)
            vars.link_state_bits.* = 0;
        const bak = vars.link_state_bits.* & 0x80;
        Link_ResetProperties_A();
        vars.link_state_bits.* = bak;

        var i: isize = 4;
        while (i >= 0) : (i -= 1) {
            const u: usize = @intCast(i);
            if (vars.ancilla_type[u] == 0x30 or vars.ancilla_type[u] == 0x31)
                vars.ancilla_type[u] = 0;
        }
        Link_CancelDash();
        AncillaAdd_CapePoof(0x23, 4);
        _ = misc.Ancilla_Sfx2_Near(0x14);
        vars.link_bunny_transform_timer.* = 20;
        vars.link_disable_sprite_damage.* = 1;
        vars.link_need_for_poof_for_transform.* = 1;
        vars.link_visibility_status.* = 12;
    }
    vars.link_bunny_transform_timer.* -%= 1;
    if (sign8(vars.link_bunny_transform_timer.*)) {
        vars.link_player_handler_state.* = kPlayerState_TempBunny;
        vars.link_is_bunny_mirror.* = 1;
        vars.link_is_bunny.* = 1;
        load_gfx.LoadGearPalettes_bunny();
        vars.link_visibility_status.* = 0;
        vars.link_disable_sprite_damage.* = 0;
        vars.link_need_for_poof_for_transform.* = 0;
    }
    return true;
}

pub export fn LinkState_TemporaryBunny() callconv(.c) void {
    if (vars.link_timer_tempbunny.* == 0) {
        AncillaAdd_CapePoof(0x23, 4);
        _ = misc.Ancilla_Sfx2_Near(0x15);
        vars.link_bunny_transform_timer.* = 32;
        vars.link_player_handler_state.* = 0;
        Link_ResetProperties_C();
        vars.link_need_for_poof_for_transform.* = 0;
        vars.link_is_bunny.* = 0;
        vars.link_is_bunny_mirror.* = 0;
        load_gfx.LoadActualGearPalettes();
        vars.link_need_for_poof_for_transform.* = 0;
        LinkState_Default();
    } else {
        vars.link_timer_tempbunny.* -%= 1;
        PlayerHandler_17_Bunny();
    }
}

pub export fn PlayerHandler_17_Bunny() callconv(.c) void {
    CacheCameraPropertiesIfOutdoors();
    vars.fallhole_var2.* = 0;
    if (vars.link_is_in_deep_water.* == 0) {
        if (vars.link_auxiliary_state.* == 0) {
            Link_TempBunny_Func2();
            return;
        }
        if (vars.link_item_moon_pearl.* != 0)
            vars.link_is_bunny_mirror.* = 0;
    }
    LinkState_Bunny_recache();
}

pub export fn LinkState_Bunny_recache() callconv(.c) void {
    vars.link_need_for_poof_for_transform.* = 0;
    vars.link_timer_tempbunny.* = 0;
    if (vars.link_item_moon_pearl.* != 0) {
        vars.link_is_bunny.* = 0;
        vars.link_auxiliary_state.* = 0;
    }
    vars.link_animation_steps.* = 0;
    vars.link_is_transforming.* = 0;
    vars.link_cant_change_direction.* = 0;
    Link_ResetSwimmingState();
    vars.link_player_handler_state.* = kPlayerState_RecoilWall;
    if (vars.link_item_moon_pearl.* != 0) {
        vars.link_player_handler_state.* = kPlayerState_Ground;
        load_gfx.LoadActualGearPalettes();
    }
}

pub export fn Link_TempBunny_Func2() callconv(.c) void {
    if (vars.link_incapacitated_timer.* != 0) {
        Link_HandleRecoilAndTimer(false);
        return;
    }
    vars.link_z_coord.* = 0xffff;
    vars.link_actual_vel_z.* = 0xff;
    vars.link_recoilmode_timer.* = 0;
    if (vars.link_flag_moving.* != 0) {
        vars.swimcoll_var9[0] = 0x180;
        vars.swimcoll_var9[1] = 0x180;
        Link_HandleSwimMovements();
        return;
    }

    ResetAllAcceleration();
    Link_HandleYItem();
    var dir: u8 = @truncate(vars.force_move_any_direction.* & 0xf);
    if (dir == 0) dir = vars.joypad1H_last.* & kJoypadH_AnyDir;
    if (dir == 0) {
        vars.link_x_vel.* = 0;
        vars.link_y_vel.* = 0;
        vars.link_direction.* = 0;
        vars.link_direction_last.* = 0;
        vars.link_animation_steps.* = 0;
        vars.bitmask_of_dragstate.* &= ~@as(u8, 9);
        vars.link_timer_push_get_tired.* = 32;
        vars.link_timer_jump_ledge.* = 19;
    } else {
        vars.link_direction.* = dir;
        if (dir != vars.link_direction_last.*) {
            vars.link_direction_last.* = dir;
            vars.link_subpixel_x.* = 0;
            vars.link_subpixel_y.* = 0;
            vars.link_moving_against_diag_tile.* = 0;
            vars.bitmask_of_dragstate.* = 0;
            vars.link_timer_push_get_tired.* = 32;
            vars.link_timer_jump_ledge.* = 19;
        }
    }
    Link_HandleDiagonalCollision();
    Link_HandleVelocity();
    Link_HandleCardinalCollision();
    Link_HandleMovingAnimation_FullLongEntry();
    vars.fallhole_var1.* = 0;
    HandleIndoorCameraAndDoors();
}

// ---------------------------------------------------------------------------
// Big rock, tablets, recoil
// ---------------------------------------------------------------------------

pub export fn LinkState_HoldingBigRock() callconv(.c) void {
    if (vars.link_auxiliary_state.* != 0) {
        vars.link_item_in_hand.* = 0;
        vars.link_position_mode.* = 0;
        vars.link_debug_value_1.* = 0;
        vars.link_debug_value_2.* = 0;
        vars.link_var30d.* = 0;
        vars.link_var30e.* = 0;
        vars.some_animation_timer_steps.* = 0;
        vars.bitfield_for_a_button.* = 0;
        vars.link_state_bits.* = 0;
        vars.link_picking_throw_state.* = 0;
        vars.link_grabbing_wall.* = 0;
        vars.bitmask_of_dragstate.* = 0;
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
        vars.link_z_coord.* &= ~@as(u16, 0xff);
        if (vars.link_electrocute_on_touch.* != 0) {
            Link_ResetSwordAndItemUsage();
            vars.link_disable_sprite_damage.* = 1;
            vars.player_handler_timer.* = 0;
            vars.link_delay_timer_spin_attack.* = 2;
            vars.link_animation_steps.* = 0;
            vars.link_direction.* &= ~@as(u8, 0xf);
            misc.Ancilla_Sfx3_Near(43);
            vars.link_player_handler_state.* = kPlayerState_Electrocution;
            LinkState_Zapped();
        } else {
            vars.link_player_handler_state.* = kPlayerState_RecoilWall;
            LinkState_Recoil();
        }
        return;
    }

    vars.link_z_coord.* = 0xffff;
    vars.link_actual_vel_z.* = 0xff;
    vars.link_recoilmode_timer.* = 0;
    if (vars.link_incapacitated_timer.* != 0) {
        vars.link_var30d.* = 0;
        vars.link_var30e.* = 0;
        vars.some_animation_timer_steps.* = 0;
        vars.bitfield_for_a_button.* = 0;
        vars.link_state_bits.* = 0;
        vars.link_picking_throw_state.* = 0;
        vars.link_grabbing_wall.* = 0;
        if (vars.button_mask_b_y.* & 0x80 == 0)
            vars.link_cant_change_direction.* &= ~@as(u8, 1);
        Link_HandleRecoilAndTimer(false);
        return;
    }

    Link_HandleAPress();
    if (vars.joypad1H_last.* & kJoypadH_AnyDir == 0) {
        vars.link_y_vel.* = 0;
        vars.link_x_vel.* = 0;
        vars.link_direction.* = 0;
        vars.link_direction_last.* = 0;
        vars.link_animation_steps.* = 0;
        vars.bitmask_of_dragstate.* &= ~@as(u8, 9);
        vars.link_timer_push_get_tired.* = 32;
        vars.link_timer_jump_ledge.* = 19;
    } else {
        vars.link_direction.* = vars.joypad1H_last.* & kJoypadH_AnyDir;
        if (vars.link_direction.* != vars.link_direction_last.*) {
            vars.link_direction_last.* = vars.link_direction.*;
            vars.link_subpixel_x.* = 0;
            vars.link_subpixel_y.* = 0;
            vars.link_moving_against_diag_tile.* = 0;
            vars.bitmask_of_dragstate.* = 0;
            vars.link_timer_push_get_tired.* = 32;
            vars.link_timer_jump_ledge.* = 19;
        }
    }
    Link_HandleMovingAnimation_FullLongEntry();
    vars.fallhole_var1.* = 0;
    HandleIndoorCameraAndDoors();
}

pub export fn EtherTablet_StartCutscene() callconv(.c) void {
    vars.button_b_frames.* = 0xc0;
    vars.link_delay_timer_spin_attack.* = 0;
    vars.link_player_handler_state.* = kPlayerState_ReceivingEther;
    vars.link_disable_sprite_damage.* = 1;
    vars.flag_block_link_menu.* = 1;
}

pub export fn LinkState_ReceivingEther() callconv(.c) void {
    vars.link_auxiliary_state.* = 0;
    vars.link_incapacitated_timer.* = 0;
    vars.link_give_damage.* = 0;
    // The C decrements a 16-bit view over button_b_frames and its neighbor.
    const bbf = wordPtr(vars.button_b_frames);
    bbf.* -%= 1;
    const i = bbf.*;
    if (sign16(i)) {
        vars.button_b_frames.* = 0;
        vars.link_delay_timer_spin_attack.* = 0;
    } else if (i == 0xbf) {
        vars.link_force_hold_sword_up.* = 1;
    } else if (i == 160) {
        const x = vars.link_x_coord.*;
        const y = vars.link_y_coord.*;
        vars.link_x_coord.* = 0x6b0;
        vars.link_y_coord.* = 0x37;
        AncillaAdd_EtherSpell(0x18, 0);
        vars.link_x_coord.* = x;
        vars.link_y_coord.* = y;
    } else if (i == 0) {
        _ = AncillaAdd_FallingPrize(0x29, 0, 4);
        vars.flag_is_link_immobilized.* = 1;
        vars.flag_block_link_menu.* = 0;
    }
}

pub export fn BombosTablet_StartCutscene() callconv(.c) void {
    vars.button_b_frames.* = 0xe0;
    vars.link_delay_timer_spin_attack.* = 0;
    vars.link_player_handler_state.* = kPlayerState_ReceivingBombos;
    vars.link_disable_sprite_damage.* = 1;
    vars.flag_custom_spell_anim_active.* = 1;
}

pub export fn LinkState_ReceivingBombos() callconv(.c) void {
    vars.link_auxiliary_state.* = 0;
    vars.link_incapacitated_timer.* = 0;
    vars.link_give_damage.* = 0;
    const bbf = wordPtr(vars.button_b_frames);
    bbf.* -%= 1;
    const i = bbf.*;
    if (sign16(i)) {
        vars.button_b_frames.* = 0;
        vars.link_delay_timer_spin_attack.* = 0;
    } else if (i == 223) {
        vars.link_force_hold_sword_up.* = 1;
    } else if (i == 160) {
        const x = vars.link_x_coord.*;
        const y = vars.link_y_coord.*;
        vars.link_x_coord.* = 0x378;
        vars.link_y_coord.* = 0xeb0;
        AncillaAdd_BombosSpell(0x19, 0);
        vars.link_x_coord.* = x;
        vars.link_y_coord.* = y;
    } else if (i == 0) {
        _ = AncillaAdd_FallingPrize(0x29, 5, 4);
        vars.flag_is_link_immobilized.* = 1;
    }
}

pub export fn LinkState_ReadingDesertTablet() callconv(.c) void {
    vars.button_b_frames.* -%= 1;
    if (vars.button_b_frames.* == 0) {
        vars.link_player_handler_state.* = kPlayerState_Ground;
        Link_PerformDesertPrayer();
    }
}

pub export fn HandleSomariaAndGraves() callconv(.c) void {
    if (vars.player_is_indoors.* == 0 and vars.link_something_with_hookshot.* != 0) {
        var i: isize = 4;
        while (true) {
            if (vars.ancilla_type[@intCast(i)] == 0x24)
                Gravestone_Move(@intCast(i));
            i -= 1;
            if (i < 0) break;
        }
    }
    var i: isize = 4;
    while (true) {
        if (vars.ancilla_type[@intCast(i)] == 0x2C) {
            SomariaBlock_HandlePlayerInteraction(@intCast(i));
            return;
        }
        i -= 1;
        if (i < 0) break;
    }
}

pub export fn LinkState_Recoil() callconv(.c) void {
    vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
    vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
    vars.link_x_coord_safe_return_lo.* = @truncate(vars.link_x_coord.*);
    vars.link_x_coord_safe_return_hi.* = @truncate(vars.link_x_coord.* >> 8);
    Link_HandleChangeInZVelocity();
    vars.link_cant_change_direction.* = 0;
    vars.draw_water_ripples_or_grass.* = 0;
    if (!sign8(@truncate(vars.link_z_coord.*)) or !sign8(vars.link_actual_vel_z.*)) {
        Link_HandleRecoilAndTimer(false);
        return;
    }
    TileDetect_MainHandler(5);
    if (vars.tiledetect_deepwater.* & 1 != 0) {
        vars.link_player_handler_state.* = kPlayerState_Swimming;
        Link_SetToDeepWater();
        Link_ResetSwordAndItemUsage();
        _ = AncillaAdd_Splash(21, 0);
        Link_HandleRecoilAndTimer(true);
    } else {
        vars.link_recoilmode_timer.* +%= 1;
        if (vars.link_recoilmode_timer.* != 4) {
            // `do { t >>= 1; } while (!--s)` continues only while the decrement
            // lands on zero: two shifts for s==1, one for s==2 or 3.
            var t = vars.link_actual_vel_z_copy.*;
            var s = vars.link_recoilmode_timer.*;
            while (true) {
                t >>= 1;
                s -%= 1;
                if (s != 0) break;
            }
            vars.link_actual_vel_z.* = t;
        } else {
            vars.link_recoilmode_timer.* = 3;
        }
        Link_HandleRecoilAndTimer(false);
    }
}

pub export fn Link_HandleRecoilAndTimer(jump_into_middle: bool) callconv(.c) void {
    // `goto lbl_jump_into_middle` lands three blocks deep, so the jump path has
    // to run each enclosing block's tail on the way back out.
    var run_tail = true;

    if (jump_into_middle) {
        // lbl_jump_into_middle:
        if (vars.link_is_on_lower_level.* == 2)
            vars.link_is_on_lower_level.* = 0;
        if (vars.about_to_jump_off_ledge.* != 0)
            Dungeon_HandleLayerChange();
        // tail of `if (link_auxiliary_state != 0)`
        vars.link_z_coord.* = 0;
        vars.link_auxiliary_state.* = 0;
        vars.link_speed_setting.* = 0;
        vars.link_cant_change_direction.* = 0;
        vars.link_item_in_hand.* = 0;
        vars.link_position_mode.* = 0;
        vars.player_handler_timer.* = 0;
        vars.link_disable_sprite_damage.* = 0;
        vars.link_electrocute_on_touch.* = 0;
        vars.link_actual_vel_x.* = 0;
        vars.link_actual_vel_y.* = 0;
        // tail of `if (z <= 0 && ...)`
        vars.link_animation_steps.* = 0;
        vars.link_incapacitated_timer.* = 0;
    } else {
        vars.link_x_page_movement_delta.* = 0;
        vars.link_y_page_movement_delta.* = 0;
        vars.link_num_orthogonal_directions.* = 0;
        Link_HandleRecoiling();
        vars.link_incapacitated_timer.* -%= 1;
        if (vars.link_incapacitated_timer.* == 0) {
            vars.link_incapacitated_timer.* = 1;
            const z: i8 = @bitCast(@as(u8, @truncate(vars.link_z_coord.* & 0xfe)));
            if (z <= 0 and @as(i8, @bitCast(vars.link_actual_vel_z.*)) < 0) {
                if (vars.link_auxiliary_state.* != 0) {
                    vars.link_disable_sprite_damage.* = 0;
                    vars.scratch_0.* = vars.link_player_handler_state.*;
                    if (vars.link_player_handler_state.* != 6) {
                        vars.button_b_frames.* = 0;
                        vars.button_mask_b_y.* = 0;
                        vars.link_delay_timer_spin_attack.* = 0;
                        vars.link_spin_attack_step_counter.* = 0;
                    }
                    Link_SplashUponLanding();
                    if (vars.link_is_bunny_mirror.* == 0 or vars.link_is_in_deep_water.* == 0) {
                        if (vars.link_want_make_noise_when_dashed.* != 0) {
                            vars.link_want_make_noise_when_dashed.* = 0;
                            _ = misc.Ancilla_Sfx2_Near(33);
                        } else if (vars.scratch_0.* != 2 and vars.link_player_handler_state.* != 4) {
                            _ = misc.Ancilla_Sfx2_Near(33);
                        }
                        if (vars.link_player_handler_state.* == 4) {
                            Link_ForceUnequipCape_quietly();
                            if (vars.player_is_indoors.* != 0 and vars.scratch_0.* != 2 and
                                vars.link_item_flippers.* != 0)
                            {
                                vars.link_is_on_lower_level.* = 1;
                            }
                            _ = AncillaAdd_Splash(21, 0);
                        }
                        TileDetect_MainHandler(0);
                        if (vars.tiledetect_thick_grass.* & 1 != 0)
                            _ = misc.Ancilla_Sfx2_Near(26);
                        if (vars.tiledetect_shallow_water.* & 1 != 0 and vars.sound_effect_1.* != 36)
                            _ = misc.Ancilla_Sfx2_Near(28);

                        if (vars.tiledetect_deepwater.* & 1 != 0) {
                            vars.link_player_handler_state.* = kPlayerState_Swimming;
                            Link_SetToDeepWater();
                            Link_ResetSwordAndItemUsage();
                            _ = AncillaAdd_Splash(21, 0);
                        }

                        // lbl_jump_into_middle:
                        if (vars.link_is_on_lower_level.* == 2)
                            vars.link_is_on_lower_level.* = 0;
                        if (vars.about_to_jump_off_ledge.* != 0)
                            Dungeon_HandleLayerChange();
                    }
                    vars.link_z_coord.* = 0;
                    vars.link_auxiliary_state.* = 0;
                    vars.link_speed_setting.* = 0;
                    vars.link_cant_change_direction.* = 0;
                    vars.link_item_in_hand.* = 0;
                    vars.link_position_mode.* = 0;
                    vars.player_handler_timer.* = 0;
                    vars.link_disable_sprite_damage.* = 0;
                    vars.link_electrocute_on_touch.* = 0;
                    vars.link_actual_vel_x.* = 0;
                    vars.link_actual_vel_y.* = 0;
                }
                vars.link_animation_steps.* = 0;
                vars.link_incapacitated_timer.* = 0;
            }
        }
    }

    if (vars.link_player_handler_state.* != 5 and vars.link_incapacitated_timer.* >= 33) {
        vars.byte_7E02C5.* -%= 1;
        if (!sign8(vars.byte_7E02C5.*)) {
            run_tail = false; // goto timer_running
        } else {
            vars.byte_7E02C5.* = vars.link_incapacitated_timer.* >> 4;
        }
    }

    if (run_tail) {
        Flag67WithDirections();
        if (vars.link_player_handler_state.* != 6) {
            Link_HandleDiagonalCollision();
            if (vars.link_direction.* & 3 == 0)
                vars.link_actual_vel_x.* = 0;
            if (vars.link_direction.* & 0xc == 0)
                vars.link_actual_vel_y.* = 0;
        }
        Link_MovePosition();
    }
    // timer_running:
    if (vars.link_player_handler_state.* != 6) {
        Link_HandleCardinalCollision();
        vars.fallhole_var1.* = 0;
    }
    HandleIndoorCameraAndDoors();
    if (loPtr(vars.link_z_coord).* == 0 or loPtr(vars.link_z_coord).* >= 0xe0) {
        tile_detect.Player_TileDetectNearby();
        if ((vars.tiledetect_pit_tile.* & 0xf) == 0xf) {
            vars.link_player_handler_state.* = kPlayerState_FallingIntoHole;
            vars.link_speed_setting.* = 4;
        }
    }
    hiPtr(vars.link_z_coord).* = 0;
}

/// The C body is just `assert(0)`, which is a no-op in release builds.
pub export fn LinkState_OnIce() callconv(.c) void {}

pub export fn Link_HandleChangeInZVelocity() callconv(.c) void {
    Player_ChangeZ(if (vars.link_player_handler_state.* == kPlayerState_TurtleRock) 1 else 2);
}

pub export fn Player_ChangeZ(zd: u8) callconv(.c) void {
    if (sign8(vars.link_actual_vel_z.*)) {
        if (loPtr(vars.link_z_coord).* == 0)
            return;
        if (sign8(loPtr(vars.link_z_coord).*)) {
            vars.link_z_coord.* = 0xffff;
            vars.link_actual_vel_z.* = 0xff;
            return;
        }
    }
    vars.link_actual_vel_z.* -%= zd;
}

// ---------------------------------------------------------------------------
// Ledge hops and landings
// ---------------------------------------------------------------------------

pub export fn LinkHop_HoppingSouthOW() callconv(.c) void {
    vars.link_last_direction_moved_towards.* = 1;
    vars.link_cant_change_direction.* = 0;
    vars.link_actual_vel_x.* = 0;
    vars.link_actual_vel_y.* = 0;
    vars.draw_water_ripples_or_grass.* = 0;
    if (vars.link_incapacitated_timer.* == 0 and vars.link_actual_vel_z_mirror.* == 0) {
        _ = misc.Ancilla_Sfx2_Near(32);
        LinkHop_FindTileToLandOnSouth();
        if (vars.player_is_indoors.* == 0)
            vars.link_is_on_lower_level.* = 2;
    }
    vars.link_actual_vel_z.* = vars.link_actual_vel_z_mirror.*;
    vars.link_actual_vel_z_copy.* = vars.link_actual_vel_z_copy_mirror.*;
    vars.link_z_coord.* = vars.link_z_coord_mirror.*;
    vars.link_actual_vel_z.* -%= 2;
    Link_MovePosition();
    if (sign8(vars.link_actual_vel_z.*)) {
        if (vars.link_actual_vel_z.* < 0xa0)
            vars.link_actual_vel_z.* = 0xa0;
        if (vars.link_z_coord.* >= 0xfff0) {
            vars.link_z_coord.* = 0;
            Link_SplashUponLanding();
            // This is the place that caused the water walking bug after bonk,
            // player_near_pit_state was not reset.
            if (vars.player_near_pit_state.* != 0)
                vars.link_player_handler_state.* = kPlayerState_FallingIntoHole;
            if (vars.link_player_handler_state.* != kPlayerState_Swimming and
                vars.link_player_handler_state.* != kPlayerState_FallingIntoHole and
                vars.link_is_in_deep_water.* == 0)
                _ = misc.Ancilla_Sfx2_Near(33);
            vars.link_disable_sprite_damage.* = 0;
            vars.allow_scroll_z.* = 0;
            vars.link_auxiliary_state.* = 0;
            vars.link_actual_vel_z.* = 0xff;
            vars.link_z_coord.* = 0xffff;
            vars.link_incapacitated_timer.* = 0;
            if (vars.player_is_indoors.* == 0)
                vars.link_is_on_lower_level.* = 0;
        } else {
            vars.link_y_vel.* = @truncate(vars.link_z_coord_mirror.* -% vars.link_z_coord.*);
        }
    } else {
        vars.link_y_vel.* = @truncate(vars.link_z_coord_mirror.* -% vars.link_z_coord.*);
    }
    vars.link_actual_vel_z_mirror.* = vars.link_actual_vel_z.*;
    vars.link_actual_vel_z_copy_mirror.* = vars.link_actual_vel_z_copy.*;
    vars.link_z_coord_mirror.* = vars.link_z_coord.*;
}

pub export fn LinkState_HandlingJump() callconv(.c) void {
    vars.link_actual_vel_z.* = vars.link_actual_vel_z_mirror.*;
    vars.link_actual_vel_z_copy.* = vars.link_actual_vel_z_copy_mirror.*;
    loPtr(vars.link_z_coord).* = @truncate(vars.link_z_coord_mirror.*);
    vars.link_actual_vel_z.* -%= 2;
    Link_MovePosition();

    var after_pit = false;
    if (sign8(vars.link_actual_vel_z.*)) {
        if (vars.link_actual_vel_z.* < 0xa0)
            vars.link_actual_vel_z.* = 0xa0;
        if (loPtr(vars.link_z_coord).* >= 0xf0) {
            vars.link_z_coord.* = 0;
            if (vars.link_player_handler_state.* == kPlayerState_FallOfLeftRightLedge or
                vars.link_player_handler_state.* == kPlayerState_JumpOffLedgeDiag)
            {
                TileDetect_MainHandler(0);
                if (vars.tiledetect_deepwater.* & 1 != 0) {
                    vars.link_player_handler_state.* = kPlayerState_Swimming;
                    Link_SetToDeepWater();
                    Link_ResetSwordAndItemUsage();
                    _ = AncillaAdd_Splash(21, 0);
                } else if (vars.tiledetect_pit_tile.* & 1 != 0) {
                    vars.byte_7E005C.* = 9;
                    vars.link_this_controls_sprite_oam.* = 0;
                    vars.player_near_pit_state.* = 1;
                    vars.link_player_handler_state.* = kPlayerState_FallingIntoHole;
                    after_pit = true;
                }
            }
            if (!after_pit) {
                Link_SplashUponLanding();
                if (vars.link_player_handler_state.* != kPlayerState_Swimming and
                    vars.link_is_in_deep_water.* == 0)
                    _ = misc.Ancilla_Sfx2_Near(33);
            }
            // after_pit:
            if (vars.link_player_handler_state.* != kPlayerState_Swimming or
                vars.link_is_bunny_mirror.* == 0)
                vars.link_disable_sprite_damage.* = 0;

            vars.allow_scroll_z.* = 0;
            vars.link_auxiliary_state.* = 0;
            vars.link_actual_vel_z.* = 0xff;
            vars.link_z_coord.* = 0xffff;
            vars.link_incapacitated_timer.* = 0;
            if (vars.player_is_indoors.* == 0)
                vars.link_is_on_lower_level.* = 0;
        } else {
            vars.link_y_vel.* = @truncate(vars.link_z_coord_mirror.* -% vars.link_z_coord.*);
        }
    } else {
        vars.link_y_vel.* = @truncate(vars.link_z_coord_mirror.* -% vars.link_z_coord.*);
    }
    vars.link_actual_vel_z_mirror.* = vars.link_actual_vel_z.*;
    vars.link_actual_vel_z_copy_mirror.* = vars.link_actual_vel_z_copy.*;
    loPtr(vars.link_z_coord_mirror).* = @truncate(vars.link_z_coord.*);
}

pub export fn LinkHop_FindTileToLandOnSouth() callconv(.c) void {
    vars.link_y_coord_original.* = vars.link_y_coord.*;
    vars.link_y_vel.* = @truncate(vars.link_y_coord.* -% vars.link_y_coord_safe_return_lo.*);
    while (true) {
        const d: usize = vars.link_last_direction_moved_towards.*;
        vars.link_y_coord.* +%= @bitCast(@as(i16, tables.kLink_DoMoveXCoord_Outdoors_Helper2_y[d]));
        tile_detect.TileDetect_Movement_Y(vars.link_last_direction_moved_towards.*);
        const k: u8 = @truncate(vars.tiledetect_normal_tiles.* | vars.tiledetect_pit_tile.* |
            vars.tiledetect_destruction_aftermath.* | vars.tiledetect_thick_grass.* |
            vars.tiledetect_deepwater.*);
        if ((k & 7) == 7) break;
    }
    if (vars.tiledetect_deepwater.* & 7 != 0) {
        vars.link_is_in_deep_water.* = 1;
        if (vars.link_auxiliary_state.* != 4)
            vars.link_auxiliary_state.* = 2;
        vars.link_some_direction_bits.* = vars.link_direction_last.*;
        Link_ResetSwimmingState();
        vars.link_grabbing_wall.* = 0;
        vars.link_speed_setting.* = 0;
    }
    if (vars.tiledetect_pit_tile.* & 7 != 0) {
        vars.byte_7E005C.* = 9;
        vars.link_this_controls_sprite_oam.* = 0;
        vars.player_near_pit_state.* = 1;
    }
    const d: usize = vars.link_last_direction_moved_towards.*;
    vars.link_y_coord.* +%= @bitCast(@as(i16, tables.kLink_DoMoveXCoord_Outdoors_Helper2_y2[d]));
    vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
    vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
    vars.link_incapacitated_timer.* = 1;
    var z: u8 = @truncate(vars.link_z_coord.*);
    if (z >= 0xf0) z = 0;
    const nz = vars.link_y_coord.* -% vars.link_y_coord_original.* +% z;
    vars.link_z_coord.* = nz;
    vars.link_z_coord_mirror.* = nz;
}

/// used on right ledges
pub export fn LinkState_HoppingHorizontallyOW() callconv(.c) void {
    vars.link_direction.* = if (sign8(vars.link_actual_vel_x.*)) 6 else 5;
    vars.link_cant_change_direction.* = 0;
    vars.link_actual_vel_y.* = 0;
    vars.draw_water_ripples_or_grass.* = 0;
    LinkState_HandlingJump();
}

pub export fn Link_HoppingHorizontally_FindTile_Y() callconv(.c) void {
    vars.link_y_coord_original.* = vars.link_y_coord.*;
    vars.link_y_vel.* = @truncate(vars.link_y_coord.* -% vars.link_y_coord_safe_return_lo.*);

    const d: usize = vars.link_last_direction_moved_towards.*;
    vars.link_y_coord.* +%= @bitCast(@as(i16, tables.kLink_DoMoveXCoord_Outdoors_Helper2_y[d]));
    tile_detect.TileDetect_Movement_Y(vars.link_last_direction_moved_towards.*);

    const tt: u8 = @truncate(vars.tiledetect_normal_tiles.* | vars.tiledetect_destruction_aftermath.* |
        vars.tiledetect_thick_grass.* | vars.tiledetect_deepwater.*);

    if ((tt & 7) != 7) {
        vars.link_y_coord.* = vars.link_y_coord_original.*;
        vars.link_incapacitated_timer.* = 1;

        const org_velx: i8 = @bitCast(vars.link_actual_vel_x.*);
        var velx = org_velx;
        if (velx < 0) velx = -velx;
        const vi: usize = @intCast(velx >> 4);
        const vz = tables.kLink_DoMoveXCoord_Outdoors_Helper2_velz[vi];
        vars.link_actual_vel_z_mirror.* = vz;
        vars.link_actual_vel_z_copy_mirror.* = vz;

        var xt = tables.kLink_DoMoveXCoord_Outdoors_Helper2_velx[vi];
        if (org_velx < 0) xt = 0 -% xt;
        vars.link_actual_vel_x.* = xt;
    } else { // else_1
        vars.link_y_coord.* +%= @bitCast(@as(i16, tables.kLink_DoMoveXCoord_Outdoors_Helper2_y2[d]));
        vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
        vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
        vars.link_incapacitated_timer.* = 1;
        var z: u8 = @truncate(vars.link_z_coord.*);
        if (z == 255) z = 0;
        const nz = vars.link_y_coord.* -% vars.link_y_coord_original.* +% z;
        vars.link_z_coord_mirror.* = nz;
        vars.link_z_coord.* = nz;
    } // endif_1

    if (vars.tiledetect_deepwater.* & 7 != 0) {
        vars.link_auxiliary_state.* = 2;
        Link_SetToDeepWater();
    }
}

pub export fn Link_SetToDeepWater() callconv(.c) void {
    vars.link_is_in_deep_water.* = 1;
    vars.link_some_direction_bits.* = vars.link_direction_last.*;
    Link_ResetSwimmingState();
    vars.link_grabbing_wall.* = 0;
    vars.link_speed_setting.* = 0;
}

/// The C body is just `assert(0)`, which is a no-op in release builds.
pub export fn LinkState_0F() callconv(.c) void {}

pub export fn Link_HoppingHorizontally_FindTile_X(o: u8) callconv(.c) u8 {
    // the C asserts o == 0 || o == 2
    vars.link_y_coord_original.* = vars.link_x_coord.*;
    var i: isize = 7;
    const oi: usize = o >> 1;
    var finish = false;
    while (true) {
        vars.link_x_coord.* +%= @bitCast(@as(i16, tables.kLink_DoMoveXCoord_Outdoors_Helper1_tab1[oi]));
        tile_detect.TileDetect_Movement_X(vars.link_last_direction_moved_towards.*);

        const tt: u8 = @truncate(vars.tiledetect_normal_tiles.* | vars.tiledetect_destruction_aftermath.* |
            vars.tiledetect_thick_grass.* | vars.tiledetect_deepwater.* | vars.tiledetect_pit_tile.*);

        if ((tt & 7) == 7) {
            if ((vars.tiledetect_deepwater.* & 7) == 7) {
                vars.link_is_in_deep_water.* = 1;
                vars.link_auxiliary_state.* = 2;
                vars.link_some_direction_bits.* = vars.link_direction_last.*;
                vars.swimming_countdown.* = 0;
                vars.link_speed_setting.* = 0;
                vars.link_grabbing_wall.* = 0;
                ResetAllAcceleration();
            }
            finish = true;
            break;
        }
        i -= 1;
        if (i < 0) break;
    }

    if (!finish)
        vars.link_x_coord.* = vars.link_y_coord_original.* +%
            @as(u16, @bitCast(@as(i16, tables.kLink_DoMoveXCoord_Outdoors_Helper1_tab2[oi])));
    // finish:
    vars.link_x_coord.* +%= @bitCast(@as(i16, tables.kLink_DoMoveXCoord_Outdoors_Helper1_tab3[oi]));
    var xt: i16 = @bitCast(vars.link_y_coord_original.* -% vars.link_x_coord.*);
    if (xt < 0) xt = -xt;
    xt >>= 3;
    const xi: usize = @intCast(xt);
    var velx = tables.kLink_DoMoveXCoord_Outdoors_Helper1_velx[xi];
    if (o != 2) velx = 0 -% velx;
    vars.link_actual_vel_x.* = velx;
    const vz = tables.kLink_DoMoveXCoord_Outdoors_Helper1_velz[xi];
    vars.link_actual_vel_z_mirror.* = vz;
    vars.link_actual_vel_z_copy_mirror.* = vz;

    return @truncate(@as(u32, @bitCast(@as(i32, @intCast(i)))));
}

/// used on diag ledges
pub export fn LinkState_HoppingDiagonallyUpOW() callconv(.c) void {
    vars.draw_water_ripples_or_grass.* = 0;
    Player_ChangeZ(2);
    Link_MovePosition();
    if (sign8(@truncate(vars.link_z_coord.*))) {
        Link_SplashUponLanding();
        if (vars.link_player_handler_state.* != kPlayerState_Swimming and
            vars.link_is_in_deep_water.* == 0)
            _ = misc.Ancilla_Sfx2_Near(33);
        vars.link_disable_sprite_damage.* = 0;
        vars.link_auxiliary_state.* = 0;
        vars.link_actual_vel_z.* = 0xff;
        vars.link_z_coord.* = 0xffff;
        vars.link_incapacitated_timer.* = 0;
        vars.link_cant_change_direction.* = 0;
    }
}

pub export fn LinkState_HoppingDiagonallyDownOW() callconv(.c) void {
    const dir: u8 = if (sign8(vars.link_actual_vel_x.*)) 2 else 3;
    vars.link_last_direction_moved_towards.* = dir;
    vars.link_cant_change_direction.* = 0;
    vars.link_actual_vel_y.* = 0;
    vars.draw_water_ripples_or_grass.* = 0;
    if (vars.link_incapacitated_timer.* == 0 and vars.link_actual_vel_z_mirror.* == 0) {
        vars.link_last_direction_moved_towards.* = 1;
        const old_x = vars.link_x_coord.*;
        _ = misc.Ancilla_Sfx2_Near(32);
        LinkHop_FindLandingSpotDiagonallyDown();
        vars.link_x_coord.* = old_x;

        const t: c_int = @intCast(vars.link_y_coord.* -% vars.link_y_coord_original.*);
        // Fix out of bounds read
        const velx: i8 = @bitCast(tables.kLedgeVelX[@intCast(IntMin(t >> 3, 23))]);
        vars.link_actual_vel_x.* = if (dir != 2) @bitCast(velx) else @bitCast(-velx);
        if (vars.player_is_indoors.* == 0)
            vars.link_is_on_lower_level.* = 2;
    }
    LinkState_HandlingJump();
}

pub export fn LinkHop_FindLandingSpotDiagonallyDown() callconv(.c) void {
    vars.link_y_coord_original.* = vars.link_y_coord.*;
    vars.link_y_vel.* = @truncate(vars.link_y_coord.* -% vars.link_y_coord_safe_return_lo.*);

    var scratch: u8 = undefined;
    while (true) {
        const o: usize = if (sign8(vars.link_actual_vel_x.*)) 0 else 1;
        const d: usize = vars.link_last_direction_moved_towards.*;

        vars.link_x_coord.* +%= @bitCast(@as(i16, tables.kLink_Ledge_Func1_dx[o]));
        vars.link_y_coord.* +%= @bitCast(@as(i16, tables.kLink_Ledge_Func1_dy[d]));
        tile_detect.TileDetect_Movement_Y(vars.link_last_direction_moved_towards.*);
        scratch = tables.kLink_Ledge_Func1_bits[o];
        const k: u8 = @truncate(vars.tiledetect_normal_tiles.* | vars.tiledetect_destruction_aftermath.* |
            vars.tiledetect_thick_grass.* | vars.tiledetect_deepwater.*);
        if ((k & scratch) == scratch) break;
    }

    if (vars.tiledetect_deepwater.* & scratch != 0) {
        vars.link_is_in_deep_water.* = 1;
        vars.link_auxiliary_state.* = 2;
        vars.link_some_direction_bits.* = vars.link_direction_last.*;
        Link_ResetSwimmingState();
        vars.link_speed_setting.* = 0;
        vars.link_grabbing_wall.* = 0;
    }

    const d: usize = vars.link_last_direction_moved_towards.*;
    vars.link_y_coord.* +%= @bitCast(@as(i16, tables.kLink_Ledge_Func1_dy2[d]));
    vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
    vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
    vars.link_incapacitated_timer.* = 1;
    const nz = vars.link_y_coord.* -% vars.link_y_coord_original.* +%
        @as(u16, loPtr(vars.link_z_coord).*);
    vars.link_z_coord_mirror.* = nz;
    vars.link_z_coord.* = nz;
}

pub export fn Link_SplashUponLanding() callconv(.c) void {
    if (vars.link_is_bunny_mirror.* != 0) {
        if (vars.link_is_in_deep_water.* != 0) {
            _ = AncillaAdd_Splash(21, 0);
            LinkState_Bunny_recache();
            return;
        }
        vars.link_player_handler_state.* = if (vars.link_item_moon_pearl.* != 0)
            kPlayerState_TempBunny
        else
            kPlayerState_PermaBunny;
    } else if (vars.link_is_in_deep_water.* != 0) {
        if (vars.link_player_handler_state.* != kPlayerState_RecoilOther)
            _ = AncillaAdd_Splash(21, 0);
        Link_ForceUnequipCape_quietly();
        vars.link_player_handler_state.* = kPlayerState_Swimming;
    } else {
        vars.link_player_handler_state.* = kPlayerState_Ground;
    }
}

// ---------------------------------------------------------------------------
// Dashing
// ---------------------------------------------------------------------------

pub export fn LinkState_Dashing() callconv(.c) void {
    CacheCameraPropertiesIfOutdoors();
    if (Link_HandleBunnyTransformation()) {
        if (vars.link_player_handler_state.* == 23)
            PlayerHandler_17_Bunny();
        return;
    }
    if (vars.link_is_running.* == 0) {
        vars.link_disable_sprite_damage.* = 0;
        vars.link_countdown_for_dash.* = 0;
        vars.link_speed_setting.* = 0;
        vars.link_player_handler_state.* = kPlayerState_Ground;
        vars.link_cant_change_direction.* = 0;
        return;
    }

    if (vars.button_mask_b_y.* & 0x80 != 0) {
        if (vars.button_b_frames.* >= 9)
            vars.button_b_frames.* = 9;
    }
    vars.fallhole_var2.* = 0;

    if (vars.link_auxiliary_state.* != 0) {
        vars.link_disable_sprite_damage.* = 0;
        vars.link_countdown_for_dash.* = 0;
        vars.link_speed_setting.* = 0;
        vars.link_cant_change_direction.* = 0;
        vars.link_is_running.* = 0;
        vars.bitmask_of_dragstate.* = 0;
        if (vars.link_electrocute_on_touch.* != 0) {
            if (vars.link_cape_mode.* != 0)
                Link_ForceUnequipCape_quietly();
            Link_ResetSwordAndItemUsage();
            vars.link_disable_sprite_damage.* = 1;
            vars.player_handler_timer.* = 0;
            vars.link_delay_timer_spin_attack.* = 2;
            vars.link_animation_steps.* = 0;
            vars.link_direction.* &= ~@as(u8, 0xf);
            misc.Ancilla_Sfx3_Near(43);
            vars.link_player_handler_state.* = kPlayerState_Electrocution;
            LinkState_Zapped();
        } else {
            vars.link_player_handler_state.* = kPlayerState_RecoilWall;
            LinkState_Recoil();
        }
        return;
    }

    // post-decrement: `a` takes the old index_of_dashing_sfx
    var a = vars.link_countdown_for_dash.*;
    if (a == 0) {
        a = vars.index_of_dashing_sfx.*;
        vars.index_of_dashing_sfx.* -%= 1;
    }
    if (tables.kDashTab1[vars.link_countdown_for_dash.* >> 4] & a == 0)
        _ = misc.Ancilla_Sfx2_Near(35);

    vars.link_countdown_for_dash.* -%= 1;
    if (sign8(vars.link_countdown_for_dash.*)) {
        vars.link_countdown_for_dash.* = 0;
        const fi: usize = vars.follower_indicator.*;
        if (@as(i32, vars.follower_indicator.*) == @as(i32, tables.kTagalongArr1[fi]))
            vars.follower_indicator.* = @bitCast(tables.kTagalongArr2[fi]);
    } else {
        vars.index_of_dashing_sfx.* = 0;
        if (vars.joypad1L_last.* & kJoypadL_A == 0) {
            vars.link_animation_steps.* = 0;
            vars.link_countdown_for_dash.* = 0;
            vars.link_speed_setting.* = 0;
            vars.link_player_handler_state.* = kPlayerState_Ground;
            vars.link_is_running.* = 0;
            if (vars.button_mask_b_y.* & 0x80 == 0)
                vars.link_cant_change_direction.* = 0;
            return;
        }
        AncillaAdd_DashDust_charging(30, 0);
        vars.link_x_vel.* = 0;
        vars.link_y_vel.* = 0;
        vars.link_dash_ctr.* = 64;
        vars.link_speed_setting.* = 16;
        var dir: u8 = 0;
        if (vars.button_mask_b_y.* & 0x80 != 0 or vars.is_standing_in_doorway.* != 0) {
            dir = tables.kDashTab2[vars.link_direction_facing.* >> 1];
        } else {
            dir = vars.joypad1H_last.* & kJoypadH_AnyDir;
            if (dir == 0)
                dir = tables.kDashTab2[vars.link_direction_facing.* >> 1];
        }
        vars.link_some_direction_bits.* = dir;
        vars.link_direction.* = dir;
        vars.link_direction_last.* = dir;
        vars.link_moving_against_diag_tile.* = 0;
        Link_HandleMovingAnimation_FullLongEntry();
        const org_x = vars.link_x_coord.*;
        const org_y = vars.link_y_coord.*;
        vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
        vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
        vars.link_x_coord_safe_return_lo.* = @truncate(vars.link_x_coord.*);
        vars.link_x_coord_safe_return_hi.* = @truncate(vars.link_x_coord.* >> 8);
        Link_HandleMovingFloor();
        Link_ApplyConveyor();
        if (vars.player_on_somaria_platform.* != 0)
            Link_HandleVelocityAndSandDrag(org_x, org_y);
        vars.link_y_vel.* = @truncate(vars.link_y_coord.* -% vars.link_y_coord_safe_return_lo.*);
        vars.link_x_vel.* = @truncate(vars.link_x_coord.* -% vars.link_x_coord_safe_return_lo.*);
        Link_HandleCardinalCollision();
        HandleIndoorCameraAndDoors();
        return;
    }

    if (vars.link_animation_steps.* >= 6)
        vars.link_animation_steps.* = 0;

    vars.link_dash_ctr.* -%= 1;
    if (vars.link_dash_ctr.* < 32)
        vars.link_dash_ctr.* = 32;

    AncillaAdd_DashDust(30, 0);
    vars.link_spin_attack_step_counter.* = 0;

    if ((vars.link_sword_type.* +% 1) & 0xfe != 0)
        TileDetect_MainHandler(7);

    if (vars.sram_progress_indicator.* != 0) {
        vars.button_mask_b_y.* |= 0x80;
        vars.button_b_frames.* = 9;
    }

    vars.link_incapacitated_timer.* = 0;

    var want_stop_dash = false;

    if (features.enhanced_features0.* & features.kFeatures0_TurnWhileDashing != 0) {
        if (vars.joypad1L_last.* & kJoypadL_A == 0) {
            vars.link_countdown_for_dash.* = 0x11;
            want_stop_dash = true;
        } else {
            const t = tables.kDashCtrlsToDir[vars.joypad1H_last.* & kJoypadH_AnyDir];
            if (t != 0 and t != vars.link_direction_last.*) {
                vars.link_direction.* = t;
                vars.link_direction_last.* = t;
                vars.link_some_direction_bits.* = t;
                Link_HandleMovingAnimation_FullLongEntry();
            }
        }
    } else {
        const joy = vars.joypad1H_last.* & kJoypadH_AnyDir;
        want_stop_dash = joy != 0 and joy != tables.kDashTab2[vars.link_direction_facing.* >> 1];
    }

    if (want_stop_dash) {
        vars.link_player_handler_state.* = kPlayerState_StopDash;
        vars.button_mask_b_y.* &= ~@as(u8, 0x80);
        vars.button_b_frames.* = 0;
        vars.link_delay_timer_spin_attack.* = 0;
        LinkState_ExitingDash();
        return;
    }

    if (vars.link_speed_setting.* == 0 and
        features.enhanced_features0.* & features.kFeatures0_TurnWhileDashing != 0)
        vars.link_speed_setting.* = 16;

    var dir: u8 = @truncate(vars.force_move_any_direction.* & 0xf);
    if (dir == 0)
        dir = tables.kDashTab2[vars.link_direction_facing.* >> 1];
    vars.link_direction.* = dir;
    vars.link_direction_last.* = dir;
    Link_HandleDiagonalCollision();
    Link_HandleVelocity();
    Link_HandleCardinalCollision();
    Link_HandleMovingAnimation_FullLongEntry();
    vars.fallhole_var1.* = 0;
    HandleIndoorCameraAndDoors();
}

pub export fn LinkState_ExitingDash() callconv(.c) void {
    CacheCameraPropertiesIfOutdoors();
    if (vars.joypad1H_last.* & kJoypadH_AnyDir != 0 or vars.link_countdown_for_dash.* >= 16) {
        vars.link_countdown_for_dash.* = 0;
        vars.link_speed_setting.* = 0;
        vars.link_player_handler_state.* = kPlayerState_Ground;
        vars.link_is_running.* = 0;
        vars.swimcoll_var5[0] &= 0xff00;
        if (vars.button_b_frames.* < 9)
            vars.link_cant_change_direction.* = 0;
    } else {
        vars.link_countdown_for_dash.* +%= 1;
    }
    Link_HandleMovingAnimation_FullLongEntry();
}

pub export fn Link_CancelDash() callconv(.c) void {
    if (vars.link_is_running.* != 0) {
        var i: isize = 4;
        while (true) {
            if (vars.ancilla_type[@intCast(i)] == 0x1e)
                vars.ancilla_type[@intCast(i)] = 0;
            i -= 1;
            if (i < 0) break;
        }
        vars.link_countdown_for_dash.* = 0;
        vars.link_speed_setting.* = 0;
        vars.link_is_running.* = 0;
        vars.link_cant_change_direction.* = 0;
        vars.swimcoll_var5[0] = 0;
    }
}

pub export fn RepelDash() callconv(.c) void {
    if (vars.link_is_running.* != 0 and vars.link_dash_ctr.* != 64) {
        Link_ResetSwimmingState();
        AncillaAdd_DashTremor(29, 1);
        sprite.Prepare_ApplyRumbleToSprites();
        if ((vars.sound_effect_2.* & 0x3f) != 27 and (vars.sound_effect_2.* & 0x3f) != 50)
            misc.Ancilla_Sfx3_Near(3);
        LinkApplyTileRebound();
    }
}

pub export fn LinkApplyTileRebound() callconv(.c) void {
    const d: usize = vars.link_last_direction_moved_towards.*;
    vars.link_actual_vel_y.* = @bitCast(tables.kDashTab6Y[d]);
    vars.link_actual_vel_x.* = @bitCast(tables.kDashTab6X[d]);
    vars.link_incapacitated_timer.* = 24;
    vars.link_actual_vel_z.* = 36;
    vars.link_actual_vel_z_copy.* = 36;
    if (vars.link_flag_moving.* != 0) {
        vars.link_some_direction_bits.* = tables.kDashTabDir[d];
        vars.link_direction.* = tables.kDashTabDir[d];
        vars.swimcoll_var11[0] = @bitCast(@as(i16, tables.kDashTabSw11Y[d]));
        vars.swimcoll_var11[1] = @bitCast(@as(i16, tables.kDashTabSw11X[d]));

        const i: usize = @as(usize, vars.link_flag_moving.* - 1) * 4 + d;
        vars.swimcoll_var7[0] = tables.kDashTabSw7Y[i];
        vars.swimcoll_var7[1] = tables.kDashTabSw7X[i];
    }
    vars.link_auxiliary_state.* = 1;
    vars.link_want_make_noise_when_dashed.* = 1;
    loPtr(vars.scratch_1).* = 0;
    vars.link_electrocute_on_touch.* = 0;
    vars.link_speed_setting.* = 0;
    vars.link_cant_change_direction.* = 0;
    vars.link_moving_against_diag_tile.* = 0;
    if (vars.link_last_direction_moved_towards.* & 2 != 0) {
        vars.link_y_vel.* = 0;
    } else {
        vars.link_x_vel.* = 0;
    }
}

pub export fn Sprite_RepelDash() callconv(.c) void {
    vars.link_last_direction_moved_towards.* = vars.link_direction_facing.* >> 1;
    RepelDash();
}

pub export fn Flag67WithDirections() callconv(.c) void {
    vars.link_direction.* = 0;
    if (vars.link_actual_vel_y.* != 0)
        vars.link_direction.* |= if (sign8(vars.link_actual_vel_y.*)) @as(u8, 8) else 4;
    if (vars.link_actual_vel_x.* != 0)
        vars.link_direction.* |= if (sign8(vars.link_actual_vel_x.*)) @as(u8, 2) else 1;
}

// ---------------------------------------------------------------------------
// Pits
// ---------------------------------------------------------------------------

pub export fn LinkState_Pits() callconv(.c) void {
    vars.link_direction.* = 0;

    // `goto aux_state` jumps into the body of the inner direction test below.
    var aux_state = false;
    if (vars.fallhole_var1.* != 0) {
        vars.fallhole_var2.* +%= 1;
        if (vars.fallhole_var2.* == 0x20) {
            vars.fallhole_var2.* = 31;
        } else {
            aux_state = pitsPreamble();
            if (aux_state == false and pits_returned) return;
        }
    } else {
        aux_state = pitsPreamble();
        if (aux_state == false and pits_returned) return;
    }
    if (aux_state) {
        if (vars.link_auxiliary_state.* != 1)
            vars.link_direction.* = vars.joypad1H_last.* & kJoypadH_AnyDir;
    }

    TileDetect_MainHandler(4);
    if (vars.tiledetect_pit_tile.* & 1 == 0) {
        // Reset player_near_pit_state if we're no longer near a hole. This fixes
        // a bug where you could walk on water.
        if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
            vars.player_near_pit_state.* = 0;

        if (vars.link_is_running.* != 0) {
            LinkState_Dashing();
            return;
        }
        vars.link_speed_setting.* = 0;
        Link_CancelDash();
        if (vars.button_mask_b_y.* & 0x80 == 0)
            vars.link_cant_change_direction.* &= ~@as(u8, 1);
        vars.player_near_pit_state.* = 0;
        vars.link_player_handler_state.* = if (vars.link_is_bunny_mirror.* == 0)
            kPlayerState_Ground
        else if (vars.link_item_moon_pearl.* != 0)
            kPlayerState_TempBunny
        else
            kPlayerState_PermaBunny;
        if (vars.link_player_handler_state.* == kPlayerState_PermaBunny) {
            PlayerHandler_17_Bunny();
        } else if (vars.link_player_handler_state.* == kPlayerState_TempBunny) {
            LinkState_TemporaryBunny();
        } else {
            LinkState_Default();
        }
        return;
    }

    tile_detect.Player_TileDetectNearby();
    vars.link_speed_setting.* = 4;
    if (vars.tiledetect_pit_tile.* & 0xf == 0) {
        vars.player_near_pit_state.* = 0;
        vars.link_speed_setting.* = 0;
        vars.link_player_handler_state.* = if (vars.link_is_bunny_mirror.* == 0)
            kPlayerState_Ground
        else if (vars.link_item_moon_pearl.* != 0)
            kPlayerState_TempBunny
        else
            kPlayerState_PermaBunny;
        Link_CancelDash();
        if (vars.button_mask_b_y.* & 0x80 == 0)
            vars.link_cant_change_direction.* &= ~@as(u8, 1);
        return;
    }

    if ((vars.tiledetect_pit_tile.* & 0xf) != 0xf) {
        var i: isize = 3;
        var found = false;
        while (true) {
            if ((vars.tiledetect_pit_tile.* & 0xf) == tables.kFallHolePitDirs[@intCast(i)]) {
                i += 4;
                found = true;
                break;
            }
            i -= 1;
            if (i < 0) break;
        }
        if (!found) {
            // The fallback scan counts *down* from 3 as it shifts right, which
            // reads oddly but is what the original does.
            i = 3;
            var pit_tile: u8 = @truncate(vars.tiledetect_pit_tile.*);
            while (pit_tile & 1 == 0) {
                i -= 1;
                pit_tile >>= 1;
            }
        }
        // endif_1:
        vars.byte_7E02C9.* = @truncate(@as(u32, @bitCast(@as(i32, @intCast(i)))));
        if (vars.link_direction.* & tables.kFallHoleDirs[@intCast(i)] != 0) {
            vars.link_direction_last.* = vars.link_direction.*;
            vars.link_speed_setting.* = 6;
            Link_HandleMovingAnimation_FullLongEntry();
        } else {
            const old_dir = vars.link_direction.*;
            vars.link_direction.* |= tables.kFallHoleDirs2[vars.byte_7E02C9.*];
            if (old_dir != 0)
                Link_HandleMovingAnimation_FullLongEntry();
        }
        Link_HandleDiagonalCollision();
        Link_HandleVelocity();
        Link_HandleCardinalCollision();
        ApplyLinksMovementToCamera();
        return;
    }

    // Initiate fall down
    if (vars.player_near_pit_state.* != 2) {
        if (vars.link_item_moon_pearl.* != 0) {
            vars.link_need_for_poof_for_transform.* = 0;
            vars.link_is_bunny.* = 0;
            vars.link_is_bunny_mirror.* = 0;
            vars.link_timer_tempbunny.* = 0;
        }
        vars.link_direction.* = 0;
        vars.player_near_pit_state.* = 2;
        vars.link_disable_sprite_damage.* = 1;
        vars.button_mask_b_y.* = 0;
        vars.button_b_frames.* = 0;
        vars.link_item_in_hand.* = 0;
        vars.link_position_mode.* = 0;
        vars.link_incapacitated_timer.* = 0;
        vars.link_auxiliary_state.* = 0;
        misc.Ancilla_Sfx3_Near(31);
    }

    vars.link_cant_change_direction.* = 0;
    vars.link_incapacitated_timer.* = 0;
    vars.link_z_coord.* = 0;
    vars.link_actual_vel_z.* = 0;
    vars.link_auxiliary_state.* = 0;
    vars.link_give_damage.* = 0;
    vars.link_is_transforming.* = 0;
    Link_ForceUnequipCape_quietly();
    vars.link_disable_sprite_damage.* +%= 1;
    vars.byte_7E005C.* -%= 1;
    if (!sign8(vars.byte_7E005C.*))
        return;
    vars.link_this_controls_sprite_oam.* +%= 1;
    const x = vars.link_this_controls_sprite_oam.*;
    vars.byte_7E005C.* = 9;
    if (vars.follower_indicator.* != 13 and x == 1)
        vars.tagalong_var5.* = x;

    if (x == 6) {
        Link_CancelDash();
        vars.submodule_index.* = 7;
        vars.link_this_controls_sprite_oam.* = 6;
        vars.player_near_pit_state.* = 3;
        vars.link_visibility_status.* = 12;
        vars.link_speed_modifier.* = 16;
        const y: u16 = @as(u8, @truncate(vars.link_y_coord.* -% vars.BG2VOFS_copy2.*));
        vars.link_state_bits.* = 0;
        vars.link_picking_throw_state.* = 0;
        vars.link_grabbing_wall.* = 0;
        vars.some_animation_timer.* = 0;
        if (vars.player_is_indoors.* != 0) {
            loPtr(vars.dungeon_room_index_prev).* = @truncate(vars.dungeon_room_index.*);
            Dungeon_FlagRoomData_Quadrants();
            if (Dungeon_IsPitThatHurtsPlayer()) {
                DungeonPitDoDamage();
                return;
            }
        }
        loPtr(vars.dungeon_room_index_prev).* = @truncate(vars.dungeon_room_index.*);
        loPtr(vars.dungeon_room_index).* = vars.dung_hdr_travel_destinations[0];
        vars.tiledetect_which_y_pos[0] = vars.link_y_coord.*;
        vars.link_y_coord.* = vars.link_y_coord.* -% y -% 0x10;
        if (vars.player_is_indoors.* != 0) {
            HandleLayerOfDestination();
        } else {
            if (loPtr(vars.overworld_screen_index).* != 5) {
                overworld.Overworld_GetPitDestination();
                vars.main_module_index.* = 17;
                vars.submodule_index.* = 0;
                vars.subsubmodule_index.* = 0;
            } else {
                overworld.TakeDamageFromPit();
            }
        }
    }
}

/// Shared preamble of LinkState_Pits' else branch. Returns true when the C would
/// have reached `aux_state:`; sets pits_returned when the caller must return.
var pits_returned: bool = false;

fn pitsPreamble() bool {
    pits_returned = false;
    if (vars.link_is_running.* == 0)
        return true; // goto aux_state
    // If you use a turbo controller to perfectly spam the dash button, the check
    // for Link being in a hole is endlessly skipped and you can levitate across
    // chasms. Fix by ensuring the dash button is held before dashing.
    if (vars.link_countdown_for_dash.* != 0 and
        (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes == 0 or
            vars.joypad1L_last.* & kJoypadL_A != 0))
    {
        LinkState_Dashing();
        pits_returned = true;
        return false;
    }
    const joy = vars.joypad1H_last.* & kJoypadH_AnyDir;
    if (joy != 0 and (joy & vars.link_direction.*) == 0) {
        Link_CancelDash();
        return true; // falls into aux_state
    }
    return false;
}

pub export fn HandleLayerOfDestination() callconv(.c) void {
    vars.link_is_on_lower_level_mirror.* = @intFromBool(vars.dung_hdr_hole_teleporter_plane.* >= 1);
    vars.link_is_on_lower_level.* = @intFromBool(vars.dung_hdr_hole_teleporter_plane.* >= 2);
}

pub export fn DungeonPitDoDamage() callconv(.c) void {
    vars.submodule_index.* = 20;
    vars.link_health_current.* -%= 8;
    if (vars.link_health_current.* >= 0xa8)
        vars.link_health_current.* = 0;
}

pub export fn HandleDungeonLandingFromPit() callconv(.c) void {
    player_oam.LinkOam_Main();
    vars.link_x_coord_prev.* = vars.link_x_coord.*;
    vars.link_y_coord_prev.* = vars.link_y_coord.*;
    if (vars.submodule_index.* == 7)
        vars.link_visibility_status.* = 0;
    if (vars.frame_counter.* & 3 == 0) {
        vars.link_this_controls_sprite_oam.* +%= 1;
        if (vars.link_this_controls_sprite_oam.* == 10)
            vars.link_this_controls_sprite_oam.* = 6;
    }
    vars.link_direction.* = 4;
    Link_HandleVelocity();
    if (sign16(vars.link_y_coord.*) and !sign16(vars.tiledetect_which_y_pos[0])) {
        if (!sign16((0 -% vars.link_y_coord.*) +% vars.tiledetect_which_y_pos[0]))
            return;
    } else {
        if (vars.tiledetect_which_y_pos[0] >= vars.link_y_coord.*)
            return;
    }
    // exploration glitch could also be armed without quitting by jumping off a
    // dungeon ledge into an access pit
    if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
        vars.about_to_jump_off_ledge.* = 0;

    vars.link_y_coord.* = vars.tiledetect_which_y_pos[0];
    vars.link_animation_steps.* = 0;
    vars.link_speed_modifier.* = 0;
    vars.link_this_controls_sprite_oam.* = 0;
    vars.player_near_pit_state.* = 0;
    vars.link_speed_setting.* = 0;
    vars.subsubmodule_index.* = 0;
    vars.submodule_index.* = 0;
    vars.link_disable_sprite_damage.* = 0;
    if (vars.follower_indicator.* != 0 and vars.follower_indicator.* != 3) {
        vars.tagalong_var5.* = 0;
        if (vars.follower_indicator.* == 13) {
            vars.follower_indicator.* = 0;
            vars.super_bomb_indicator_unk2.* = 0;
            vars.super_bomb_indicator_unk1.* = 0;
            vars.follower_dropped.* = 0;
        } else {
            tagalong.Follower_Initialize();
        }
    }
    TileDetect_MainHandler(0);
    if (vars.tiledetect_shallow_water.* & 1 != 0)
        _ = misc.Ancilla_Sfx2_Near(0x24);
    tile_detect.Player_TileDetectNearby();
    if ((vars.sound_effect_1.* & 0x3f) != 0x24)
        _ = misc.Ancilla_Sfx2_Near(0x21);

    if (vars.dung_hdr_collision_2.* == 2 and (vars.tiledetect_water_staircase.* & 0xf) != 0)
        vars.byte_7E0322.* = 3;
    if ((vars.tiledetect_deepwater.* & 0xf) == 0xf) {
        vars.link_is_in_deep_water.* = 1;
        vars.link_some_direction_bits.* = vars.link_direction_last.*;
        Link_ResetSwimmingState();
        vars.link_is_on_lower_level.* = 1;
        _ = AncillaAdd_Splash(0x15, 1);
        vars.link_player_handler_state.* = kPlayerState_Swimming;
        Link_ForceUnequipCape_quietly();
        vars.link_state_bits.* = 0;
        vars.link_picking_throw_state.* = 0;
        vars.link_grabbing_wall.* = 0;
        vars.link_speed_setting.* = 0;
    } else {
        vars.link_player_handler_state.* = if (vars.tiledetect_pit_tile.* & 0xf != 0)
            kPlayerState_FallingIntoHole
        else
            kPlayerState_Ground;
    }
}

// ---------------------------------------------------------------------------
// Swimming
// ---------------------------------------------------------------------------

pub export fn PlayerHandler_04_Swimming() callconv(.c) void {
    if (vars.link_auxiliary_state.* != 0) {
        vars.link_player_handler_state.* = kPlayerState_RecoilWall;
        vars.link_z_coord.* &= 0xff;
        ResetAllAcceleration();
        vars.link_maybe_swim_faster.* = 0;
        vars.link_swim_hard_stroke.* = 0;
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
        LinkState_Recoil();
        return;
    }

    vars.button_mask_b_y.* = 0;
    vars.button_b_frames.* = 0;
    vars.link_delay_timer_spin_attack.* = 0;
    vars.link_spin_attack_step_counter.* = 0;
    vars.link_state_bits.* = 0;
    vars.link_picking_throw_state.* = 0;
    if (vars.link_item_flippers.* == 0)
        return;

    if ((vars.swimcoll_var7[0] | vars.swimcoll_var7[1]) == 0) {
        if (@as(u8, @truncate(vars.swimcoll_var5[0])) != 2 and
            @as(u8, @truncate(vars.swimcoll_var5[1])) != 2)
            ResetAllAcceleration();
        vars.link_animation_steps.* &= 1;
        vars.link_counter_var1.* +%= 1;
        if (vars.link_counter_var1.* >= 16) {
            vars.link_counter_var1.* = 0;
            vars.byte_7E02CC.* = 0;
            vars.link_animation_steps.* = (vars.link_animation_steps.* & 1) ^ 1;
        }
    } else {
        vars.link_counter_var1.* +%= 1;
        if (vars.link_counter_var1.* >= 8) {
            vars.link_counter_var1.* = 0;
            vars.link_animation_steps.* = (vars.link_animation_steps.* +% 1) & 3;
            vars.byte_7E02CC.* = tables.kSwimmingTab1[vars.link_animation_steps.*];
        }
    }

    if (vars.link_swim_hard_stroke.* == 0) {
        if ((vars.swimcoll_var7[0] | vars.swimcoll_var7[1]) == 0) {
            Link_HandleSwimMovements();
            return;
        }
        const t = ((vars.filtered_joypad_L.* & kJoypadL_A) | vars.filtered_joypad_H.*) & 0xc0;
        if (t == 0) {
            Link_HandleSwimMovements();
            return;
        }
        vars.link_swim_hard_stroke.* = t;
        _ = misc.Ancilla_Sfx2_Near(37);
        vars.link_maybe_swim_faster.* = 1;
        vars.swimming_countdown.* = 7;
        Link_HandleSwimAccels();
    }
    vars.swimming_countdown.* -%= 1;
    if (sign8(vars.swimming_countdown.*)) {
        vars.swimming_countdown.* = 7;
        vars.link_maybe_swim_faster.* +%= 1;
        if (vars.link_maybe_swim_faster.* == 5) {
            vars.link_maybe_swim_faster.* = 0;
            vars.link_swim_hard_stroke.* &= ~@as(u8, 0xC0);
        }
    }

    Link_HandleSwimMovements();
}

pub export fn Link_HandleSwimMovements() callconv(.c) void {
    var t: u8 = @truncate(vars.force_move_any_direction.* & 0xf);
    if (t == 0) t = vars.joypad1H_last.* & kJoypadH_AnyDir;

    out: {
        if (t == 0) {
            vars.link_y_vel.* = 0;
            vars.link_x_vel.* = 0;
            Link_FlagMaxAccels();
            if (vars.link_flag_moving.* != 0) {
                if (vars.link_is_running.* != 0) {
                    t = vars.link_some_direction_bits.*;
                } else {
                    if ((vars.swimcoll_var7[0] | vars.swimcoll_var7[1]) == 0) {
                        vars.bitmask_of_dragstate.* = 0;
                        Link_ResetSwimmingState();
                    }
                    break :out;
                }
            } else {
                if (vars.link_player_handler_state.* != kPlayerState_Swimming)
                    vars.link_animation_steps.* = 0;
                break :out;
            }
        }

        if (t != vars.link_some_direction_bits.*) {
            vars.link_some_direction_bits.* = t;
            vars.link_subpixel_x.* = 0;
            vars.link_subpixel_y.* = 0;
            vars.link_moving_against_diag_tile.* = 0;
            vars.bitmask_of_dragstate.* = 0;
        }
        Link_SetIceMaxAccel();
        Link_SetMomentum();
        Link_SetTheMaxAccel();
    }
    // out:
    Link_HandleDiagonalCollision();
    Link_HandleVelocity();
    Link_HandleCardinalCollision();
    Link_HandleMovingAnimation_FullLongEntry();
    vars.fallhole_var1.* = 0;
    HandleIndoorCameraAndDoors();
}

pub export fn Link_FlagMaxAccels() callconv(.c) void {
    if (vars.link_flag_moving.* == 0)
        return;
    var i: isize = 1;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        if (vars.swimcoll_var7[u] != 0) {
            vars.swimcoll_var9[u] = vars.swimcoll_var7[u];
            vars.swimcoll_var5[u] = 1;
        }
    }
}

pub export fn Link_SetIceMaxAccel() callconv(.c) void {
    if (vars.link_flag_moving.* == 0)
        return;
    vars.swimcoll_var9[0] = 0x180;
    vars.swimcoll_var9[1] = 0x180;
}

pub export fn Link_SetMomentum() callconv(.c) void {
    const joy = vars.joypad1H_last.* & kJoypadH_AnyDir;
    var mask: u8 = 12;
    var bit: u8 = 8;
    var i: usize = 0;
    while (i < 2) : ({
        i += 1;
        mask >>= 2;
        bit >>= 2;
    }) {
        if (joy & mask != 0) {
            vars.swimcoll_var3[i] = if (vars.link_flag_moving.* != 0)
                tables.kSwimmingTab2[vars.link_flag_moving.* - 1]
            else
                32;
            if (((vars.link_some_direction_bits.* | vars.link_direction.*) & mask) == mask) {
                vars.swimcoll_var5[i] = 2;
            } else {
                vars.swimcoll_var11[i] = if (joy & bit != 0) 0 else 1;
                vars.swimcoll_var5[i] = 0;
            }
            if (vars.swimcoll_var9[i] == 0)
                vars.swimcoll_var9[i] = 240;
        }
    }
}

pub export fn Link_ResetSwimmingState() callconv(.c) void {
    vars.swimming_countdown.* = 0;
    vars.link_swim_hard_stroke.* = 0;
    vars.link_maybe_swim_faster.* = 0;
    ResetAllAcceleration();
}

pub export fn Link_ResetStateAfterDamagingPit() callconv(.c) void {
    Link_ResetSwimmingState();
    vars.link_player_handler_state.* = if (vars.link_is_bunny.* != 0 and vars.link_item_moon_pearl.* == 0)
        kPlayerState_PermaBunny
    else
        kPlayerState_Ground;
    vars.link_direction_last.* = vars.link_some_direction_bits.*;
    vars.link_is_in_deep_water.* = 0;
    vars.link_disable_sprite_damage.* = 0;
    vars.link_this_controls_sprite_oam.* = 0;
    vars.player_near_pit_state.* = 0;
}

pub export fn ResetAllAcceleration() callconv(.c) void {
    vars.swimcoll_var1[0] = 0;
    vars.swimcoll_var1[1] = 0;
    vars.swimcoll_var3[0] = 0;
    vars.swimcoll_var3[1] = 0;
    vars.swimcoll_var5[0] = 0;
    vars.swimcoll_var5[1] = 0;
    vars.swimcoll_var7[0] = 0;
    vars.swimcoll_var7[1] = 0;
    vars.swimcoll_var9[0] = 0;
    vars.swimcoll_var9[1] = 0;
}

pub export fn Link_HandleSwimAccels() callconv(.c) void {
    var mask: u8 = 12;
    var i: usize = 0;
    while (i < 2) : ({
        i += 1;
        mask >>= 2;
    }) {
        if (vars.joypad1H_last.* & mask != 0) {
            if (vars.swimcoll_var7[i] != 0 and vars.swimcoll_var9[i] >= 384) {
                // `t` keeps the last probed entry when the scan runs off the end.
                var t: u16 = undefined;
                var j: usize = 0;
                while (j < 9) : (j += 1) {
                    t = tables.kSwimmingTab3[j];
                    if (!(t < vars.swimcoll_var7[i])) break;
                }
                vars.swimcoll_var9[i] = t;
            } else {
                var t = vars.swimcoll_var9[i];
                if (t != 0) {
                    t +%= 160;
                    if (t >= 384) t = 384;
                    vars.swimcoll_var9[i] = t;
                } else {
                    vars.swimcoll_var7[i] = 1;
                    vars.swimcoll_var9[i] = 240;
                }
            }
        }
    }
}

pub export fn Link_SetTheMaxAccel() callconv(.c) void {
    if (vars.link_flag_moving.* != 0 or vars.link_swim_hard_stroke.* != 0)
        return;
    var mask: u8 = 12;
    var i: usize = 0;
    while (i < 2) : ({
        i += 1;
        mask >>= 2;
    }) {
        if (vars.joypad1H_last.* & mask != 0 and vars.swimcoll_var5[i] != 2) {
            if (vars.swimcoll_var1[i] != 0 or
                (vars.swimcoll_var7[i] >= 240 and vars.swimcoll_var7[i] >= vars.swimcoll_var9[i]))
            {
                vars.swimcoll_var5[i] = 0;
                if (vars.swimcoll_var7[i] >= 240) {
                    vars.swimcoll_var1[i] = 1;
                    vars.swimcoll_var5[i] = 1;
                } else {
                    vars.swimcoll_var9[i] = 240;
                    vars.swimcoll_var1[i] = 0;
                }
            }
        } else {
            vars.swimcoll_var9[i] = 240;
            vars.swimcoll_var1[i] = 0;
        }
    }
}

pub export fn LinkState_Zapped() callconv(.c) void {
    CacheCameraPropertiesIfOutdoors();
    load_gfx.LinkZap_HandleMosaic();
    vars.link_delay_timer_spin_attack.* -%= 1;
    if (!sign8(vars.link_delay_timer_spin_attack.*))
        return;
    vars.link_delay_timer_spin_attack.* = 2;
    vars.player_handler_timer.* +%= 1;
    if (vars.player_handler_timer.* & 1 != 0) {
        load_gfx.Palette_ElectroThemedGear();
    } else {
        load_gfx.LoadActualGearPalettes();
    }
    if (vars.player_handler_timer.* == 8) {
        vars.player_handler_timer.* = 0;
        vars.link_player_handler_state.* = kPlayerState_Ground;
        vars.link_disable_sprite_damage.* = 0;
        vars.link_electrocute_on_touch.* = 0;
        vars.link_auxiliary_state.* = 0;
        load_gfx.Player_SetCustomMosaicLevel(0);
    }
}

/// empty by design
pub export fn PlayerHandler_15_HoldItem() callconv(.c) void {}

pub export fn Link_ReceiveItem(item: u8, chest_position: c_int) callconv(.c) void {
    if (vars.link_auxiliary_state.* != 0) {
        vars.link_auxiliary_state.* = 0;
        vars.link_incapacitated_timer.* = 0;
        vars.countdown_for_blink.* = 0;
        vars.link_state_bits.* = 0;
    }
    vars.link_receiveitem_index.* = item;
    if (item == 0x3e)
        misc.Ancilla_Sfx3_Near(0x2e);
    vars.link_receiveitem_var1.* = 0x60;
    if (vars.item_receipt_method.* == 0 or vars.item_receipt_method.* == 3) {
        vars.link_state_bits.* = 0;
        vars.button_mask_b_y.* = 0;
        vars.bitfield_for_a_button.* = 0;
        vars.button_b_frames.* = 0;
        vars.link_speed_setting.* = 0;
        vars.link_cant_change_direction.* = 0;
        vars.link_item_in_hand.* = 0;
        vars.link_position_mode.* = 0;
        vars.player_handler_timer.* = 0;
        vars.link_player_handler_state.* = kPlayerState_HoldUpItem;
        vars.link_pose_for_item.* = 1;
        vars.link_disable_sprite_damage.* = 1;
        if (item == 0x20)
            vars.link_pose_for_item.* = 2;
    }
    misc.AncillaAdd_ItemReceipt(0x22, 4, chest_position);
    if (item != 0x20 and item != 0x37 and item != 0x38 and item != 0x39)
        hud.Hud_RefreshIcon();
    Link_CancelDash();
}

pub export fn Link_TuckIntoBed() callconv(.c) void {
    vars.link_y_coord.* = 0x215a;
    vars.link_x_coord.* = 0x940;
    vars.link_player_handler_state.* = kPlayerState_AsleepInBed;
    vars.player_sleep_in_bed_state.* = 0;
    vars.link_pose_during_opening.* = 0;
    vars.link_countdown_for_dash.* = 3;
    AncillaAdd_Blanket(0x20);
}

pub export fn LinkState_Sleeping() callconv(.c) void {
    switch (vars.player_sleep_in_bed_state.*) {
        0 => {
            if (vars.frame_counter.* & 0x1f == 0)
                AncillaAdd_Snoring(0x21, 1);
        },
        1 => {
            if (vars.submodule_index.* == 0) {
                vars.link_countdown_for_dash.* -%= 1;
                if (sign8(vars.link_countdown_for_dash.*)) {
                    vars.link_countdown_for_dash.* = 0;
                    const bits = ((vars.filtered_joypad_H.* & 0xe0) |
                        (vars.filtered_joypad_H.* << 4) | vars.filtered_joypad_L.*) & 0xf0;
                    if (bits != 0) {
                        vars.link_pose_during_opening.* +%= 1;
                        vars.link_direction_facing.* = 6;
                        vars.player_sleep_in_bed_state.* +%= 1;
                        vars.link_countdown_for_dash.* = 4;
                    }
                }
            }
        },
        2 => {
            vars.link_countdown_for_dash.* -%= 1;
            if (sign8(vars.link_countdown_for_dash.*)) {
                vars.link_actual_vel_y.* = 4;
                vars.link_actual_vel_x.* = 21;
                vars.link_actual_vel_z.* = 24;
                vars.link_actual_vel_z_copy.* = 24;
                vars.link_incapacitated_timer.* = 16;
                vars.link_auxiliary_state.* = 2;
                vars.link_player_handler_state.* = kPlayerState_RecoilOther;
            }
        },
        else => {},
    }
}

pub export fn Link_HandleSwordCooldown() callconv(.c) void {
    vars.link_sword_delay_timer.* -%= 1;
    if (!sign8(vars.link_sword_delay_timer.*))
        return;

    vars.link_sword_delay_timer.* = 0;
    if ((vars.link_item_in_hand.* | vars.link_position_mode.*) != 0)
        return;

    if (vars.button_b_frames.* < 9) {
        if (vars.link_is_running.* == 0)
            Link_CheckForSwordSwing();
    } else {
        HandleSwordControls();
    }
}

pub export fn Link_HandleYItem() callconv(.c) void {
    if (vars.button_b_frames.* != 0 and vars.button_b_frames.* < 9)
        return;

    var item = vars.current_item_y.*;

    if (vars.link_is_bunny_mirror.* != 0 and item != 11 and item != 20)
        return;

    if (vars.is_archer_or_shovel_game.* != 0 and vars.link_is_bunny_mirror.* == 0) {
        if (vars.is_archer_or_shovel_game.* == 2) {
            LinkItem_Bow();
        } else {
            LinkItem_Shovel();
        }
        return;
    }

    const old_down = vars.joypad1H_last.*;
    const old_pressed = vars.filtered_joypad_H.*;
    const old_bottle = vars.link_item_bottle_index.*;
    // The cape's cooldown ticks every frame on Y, since its code runs every
    // frame there. On X, L or R it'd only tick while the button's held; tick
    // it here the rest of the time, so it's ready when it would be on Y.
    if (vars.link_cape_mode.* == 0 and vars.current_item_active.* != 19 and
        !sign8(vars.link_bunny_transform_timer.*) and hud.capeOnItemButton())
        vars.link_bunny_transform_timer.* -%= 1;
    if ((vars.link_item_in_hand.* | vars.link_position_mode.*) == 0 and
        (old_down & kJoypadH_Y) == 0)
    {
        // Is any special key held down?
        const btn_index = hud.GetCurrentItemButtonIndex();
        if (btn_index != 0) {
            const cur_item_ptr = hud.GetCurrentItemButtonPtr(btn_index);
            if (cur_item_ptr.* != 0) {
                if (cur_item_ptr.* >= kHudItem_Bottle1)
                    vars.link_item_bottle_index.* = cur_item_ptr.* - kHudItem_Bottle1 + 1;
                item = hud.Hud_LookupInventoryItem(cur_item_ptr.*);
                hud.g_item_source = btn_index;
                // Pretend it's actually Y that's down
                vars.joypad1H_last.* = old_down | kJoypadH_Y;
                vars.filtered_joypad_H.* = old_pressed |
                    (if (vars.filtered_joypad_L.* & tables.kButtonIndexKeys[@intCast(btn_index)] != 0)
                        kJoypadH_Y
                    else
                        @as(u8, 0));
            }
        } else if (hud.lastingItemFromButton()) |lasting| {
            // The cape or Byrna, started from X, L or R, keeps going with its
            // button let go; pressing that button again works like Y would,
            // and takes it off.
            item = lasting;
            if (hud.sourceButtonPressed()) {
                vars.joypad1H_last.* = old_down | kJoypadH_Y;
                vars.filtered_joypad_H.* = old_pressed | kJoypadH_Y;
            }
        } else {
            hud.g_item_source = 0;
        }
    } else if (hud.g_item_source != 0) {
        // Mid-animation, an item from X, L or R is still the one in use.
        // The original fell back to Y here, which was the same item when Y
        // was the only item button; now it would take the cape straight back
        // off as it went on.
        item = vars.current_item_active.*;
    }

    if (item != vars.current_item_active.*) {
        if (vars.current_item_active.* == 8 and (vars.link_item_flute.* & 2) != 0)
            vars.button_mask_b_y.* &= ~@as(u8, 0x40);
        if (vars.current_item_active.* == 19 and vars.link_cape_mode.* != 0)
            Link_ForceUnequipCape();
    }

    if ((vars.link_item_in_hand.* | vars.link_position_mode.*) == 0)
        vars.current_item_active.* = item;

    if (vars.current_item_active.* == 5 or vars.current_item_active.* == 6)
        vars.eq_selected_rod.* = vars.current_item_active.* - 5 + 1;

    switch (vars.current_item_active.*) {
        0 => {},
        1 => LinkItem_Bombs(),
        2 => LinkItem_Boomerang(),
        3 => LinkItem_Bow(),
        4 => LinkItem_Hammer(),
        5 => LinkItem_Rod(),
        6 => LinkItem_Rod(),
        7 => LinkItem_Net(),
        8 => LinkItem_ShovelAndFlute(),
        9 => LinkItem_Lamp(),
        10 => LinkItem_Powder(),
        11 => LinkItem_Bottle(),
        12 => LinkItem_Book(),
        13 => LinkItem_CaneOfByrna(),
        14 => LinkItem_Hookshot(),
        15 => LinkItem_Bombos(),
        16 => LinkItem_Ether(),
        17 => LinkItem_Quake(),
        18 => LinkItem_CaneOfSomaria(),
        19 => LinkItem_Cape(),
        20 => LinkItem_Mirror(),
        21 => LinkItem_Shovel(),
        else => {},
    }

    vars.joypad1H_last.* = old_down;
    vars.filtered_joypad_H.* = old_pressed;
    vars.link_item_bottle_index.* = old_bottle;
}

pub export fn Link_HandleAPress() callconv(.c) void {
    vars.flag_is_sprite_to_pick_up_cached.* = 0;
    if (vars.link_item_in_hand.* != 0 or (vars.link_position_mode.* & 0x1f) != 0 or
        vars.byte_7E0379.* != 0)
        return;

    if (vars.button_b_frames.* < 9 and (vars.button_mask_b_y.* & 0x80) != 0)
        return;

    var action = vars.tile_action_index.*;

    if ((vars.link_state_bits.* | vars.link_grabbing_wall.*) == 0) {
        if (!Link_CheckNewAPress()) {
            vars.bitfield_for_a_button.* = 0;
            return;
        }

        // `goto attempt_action` skips the remaining action selection.
        var have_action = false;
        if (vars.link_need_for_pullforrupees_sprite.* != 0 and vars.link_direction_facing.* == 0) {
            action = 7;
        } else if (vars.link_is_near_moveable_statue.* != 0) {
            action = 6;
        } else {
            if (vars.flag_is_ancilla_to_pick_up.* == 0) {
                if (vars.flag_is_sprite_to_pick_up.* == 0) {
                    action = Link_HandleLiftables();
                    have_action = true;
                } else {
                    vars.flag_is_sprite_to_pick_up_cached.* = vars.flag_is_sprite_to_pick_up.*;
                }
            }
            if (!have_action) {
                if (vars.button_b_frames.* != 0)
                    Link_ResetSwordAndItemUsage();

                if ((vars.link_item_in_hand.* | vars.link_position_mode.*) != 0) {
                    vars.link_item_in_hand.* = 0;
                    vars.link_position_mode.* = 0;
                    Link_ResetBoomerangYStuff();
                    vars.flag_for_boomerang_in_place.* = 0;
                    if (vars.ancilla_type[0] == 5)
                        vars.ancilla_type[0] = 0;
                }
                action = 1;
            }
        }
        // attempt_action:
        if (tables.kAbilityBitmasks[action] & vars.link_ability_flags.* == 0) {
            vars.bitfield_for_a_button.* = 0;
            return;
        }

        vars.tile_action_index.* = action;
        Link_APress_PerformBasic(action *% 2);
    }

    // actionInProgress
    vars.unused_2.* = vars.tile_action_index.*;
    switch (vars.tile_action_index.*) {
        1 => Link_APress_LiftCarryThrow(),
        3 => Link_APress_PullObject(),
        6 => Link_APress_StatueDrag(),
        else => {},
    }
}

pub export fn Link_APress_PerformBasic(action_x2: u8) callconv(.c) void {
    switch (action_x2 >> 1) {
        0 => Link_PerformDesertPrayer(),
        1 => Link_PerformThrow(),
        2 => Link_PerformDash(),
        3 => Link_PerformGrab(),
        4 => Link_PerformRead(),
        5 => Link_PerformOpenChest(),
        6 => Link_PerformStatueDrag(),
        7 => Link_PerformRupeePull(),
        else => {},
    }
}

pub export fn HandleSwordSfxAndBeam() callconv(.c) void {
    vars.link_direction.* &= ~@as(u8, 0xf);
    vars.button_b_frames.* = 0;
    vars.link_spin_attack_step_counter.* = 0;

    const health = vars.link_health_capacity.* -% 4;
    if (health < vars.link_health_current.* and
        ((vars.link_sword_type.* +% 1) & 0xfe) != 0 and vars.link_sword_type.* >= 2)
    {
        var i: isize = 4;
        while (vars.ancilla_type[@intCast(i)] != 0x31) {
            i -= 1;
            if (i < 0) {
                AddSwordBeam(0);
                break;
            }
        }
    }
    const sword = vars.link_sword_type.* -% 1;
    if (sword != 0xfe and sword != 0xff)
        vars.sound_effect_1.* = tables.kFireBeamSounds[sword] | misc.Link_CalculateSfxPan();
    vars.link_delay_timer_spin_attack.* = 1;
}

pub export fn Link_CheckForSwordSwing() callconv(.c) void {
    if (vars.bitfield_for_a_button.* & 0x10 != 0)
        return;

    if (vars.button_mask_b_y.* & 0x80 == 0) {
        if (vars.filtered_joypad_H.* & 0x80 == 0)
            return;
        if (vars.is_standing_in_doorway.* != 0) {
            tile_detect.TileDetect_SwordSwingDeepInDoor(vars.is_standing_in_doorway.*);
            if ((vars.R14.* & 0x30) == 0x30)
                return;
        }
        vars.button_mask_b_y.* |= 0x80;
        HandleSwordSfxAndBeam();
        vars.link_cant_change_direction.* |= 1;
        vars.link_animation_steps.* = 0;
    }

    if (vars.joypad1H_last.* & kJoypadH_B == 0)
        vars.button_mask_b_y.* |= 1;
    HaltLinkWhenUsingItems();
    vars.link_direction.* &= ~@as(u8, 0xf);
    vars.link_delay_timer_spin_attack.* -%= 1;
    if (sign8(vars.link_delay_timer_spin_attack.*)) {
        vars.button_b_frames.* +%= 1;
        if (vars.button_b_frames.* >= 9) {
            HandleSwordControls();
            return;
        }
        vars.link_delay_timer_spin_attack.* = spinAttackDelay(vars.button_b_frames.*);
        if (vars.button_b_frames.* == 5) {
            if (vars.link_sword_type.* != 0 and vars.link_sword_type.* != 1 and
                vars.link_sword_type.* != 0xff)
                AncillaAdd_SwordSwingSparkle(0x26, 4);
            if (vars.link_sword_type.* != 0 and vars.link_sword_type.* != 0xff)
                TileDetect_MainHandler(if (vars.link_sword_type.* == 1) 1 else 6);
        } else if (vars.button_b_frames.* >= 4 and (vars.button_mask_b_y.* & 1) != 0 and
            (vars.joypad1H_last.* & kJoypadH_B) != 0)
        {
            vars.button_mask_b_y.* &= ~@as(u8, 1);
            HandleSwordSfxAndBeam();
            return;
        }
    }
    player_oam.CalculateSwordHitBox();
}

/// The delay before the next frame of a sword swing or charge. The game
/// can come here with the frame counter still at what a tablet cutscene or
/// the victory spin left it at (0xc0, 0xe0, 144), and counts on from there,
/// past the table's end; the original reads whatever comes after it there.
/// Take the last entry instead of running off the table.
fn spinAttackDelay(frame: u8) u8 {
    const t = &tables.kSpinAttackDelays;
    return t[@min(frame, t.len - 1)];
}

pub export fn HandleSwordControls() callconv(.c) void {
    if (vars.joypad1H_last.* & kJoypadH_B != 0) {
        Player_Sword_SpinAttackJerks_HoldDown();
    } else {
        if (vars.link_spin_attack_step_counter.* < 48) {
            Link_ResetSwordAndItemUsage();
        } else {
            Link_ResetSwordAndItemUsage();
            vars.link_spin_attack_step_counter.* = 0;
            Link_ActivateSpinAttack();
        }
    }
}

pub export fn Link_ResetSwordAndItemUsage() callconv(.c) void {
    vars.link_speed_setting.* = 0;
    vars.bitmask_of_dragstate.* &= ~@as(u8, 9);
    vars.link_delay_timer_spin_attack.* = 0;
    vars.button_b_frames.* = 0;
    vars.button_mask_b_y.* &= ~@as(u8, 0x81);
    vars.link_cant_change_direction.* &= ~@as(u8, 1);
}

pub export fn Player_Sword_SpinAttackJerks_HoldDown() callconv(.c) void {
    if ((vars.bitmask_of_dragstate.* & 0x80) != 0 or (vars.bitmask_of_dragstate.* & 9) == 0) {
        if (vars.set_when_damaging_enemies.* == 0) {
            vars.button_b_frames.* = 9;
            vars.link_cant_change_direction.* |= 1;
            vars.link_delay_timer_spin_attack.* = 0;
            if (vars.link_speed_setting.* != 4 and vars.link_speed_setting.* != 16) {
                vars.link_speed_setting.* = 12;
                if ((vars.link_sword_type.* +% 1) & ~@as(u8, 1) == 0)
                    return;
                var i: isize = 4;
                while (true) {
                    const u: usize = @intCast(i);
                    if (vars.ancilla_type[u] == 0x30 or vars.ancilla_type[u] == 0x31)
                        return;
                    i -= 1;
                    if (i < 0) break;
                }

                if (vars.link_spin_attack_step_counter.* >= 6 and (vars.frame_counter.* & 3) == 0)
                    AncillaSpawn_SwordChargeSparkle();

                if (vars.link_spin_attack_step_counter.* < 64) {
                    vars.link_spin_attack_step_counter.* +%= 1;
                    if (vars.link_spin_attack_step_counter.* == 48) {
                        _ = misc.Ancilla_Sfx2_Near(55);
                        AncillaAdd_ChargedSpinAttackSparkle();
                    }
                }
            } else {
                player_oam.CalculateSwordHitBox();
            }
            return;
        } else if (vars.set_when_damaging_enemies.* == 1) {
            Link_ResetSwordAndItemUsage();
            return;
        }
    }
    // endif_2
    if (vars.button_b_frames.* == 9) {
        vars.button_b_frames.* = 10;
        vars.link_delay_timer_spin_attack.* = spinAttackDelay(vars.button_b_frames.*);
    }

    vars.link_delay_timer_spin_attack.* -%= 1;
    if (sign8(vars.link_delay_timer_spin_attack.*)) {
        var frames = vars.button_b_frames.* +% 1;
        if (frames == 13) {
            if ((vars.link_sword_type.* +% 1) & ~@as(u8, 1) != 0 and
                (vars.bitmask_of_dragstate.* & 9) != 0)
            {
                AncillaAdd_WallTapSpark(27, 1);
                _ = misc.Ancilla_Sfx2_Near(if (vars.bitmask_of_dragstate.* & 8 != 0) 6 else 5);
                TileDetect_MainHandler(1);
            }
            frames = 10;
        }
        vars.button_b_frames.* = frames;
        vars.link_delay_timer_spin_attack.* = spinAttackDelay(vars.button_b_frames.*);
    }
    player_oam.CalculateSwordHitBox();
}

// ---------------------------------------------------------------------------
// Item handlers
// ---------------------------------------------------------------------------

pub export fn LinkItem_Rod() callconv(.c) void {
    var out = false;
    if (vars.button_mask_b_y.* & 0x40 == 0) {
        if (vars.is_standing_in_doorway.* != 0 or !CheckYButtonPress())
            return;
        if (!LinkCheckMagicCost(0)) {
            out = true;
        } else {
            vars.link_debug_value_2.* = 1;
            if (vars.eq_selected_rod.* == 1) {
                AncillaAdd_FireRodShot(2, 1);
            } else {
                AncillaAdd_IceRodShot(11, 1);
            }
            vars.link_delay_timer_spin_attack.* = tables.kRodAnimDelays[0];
            vars.link_animation_steps.* = 0;
            vars.player_handler_timer.* = 0;
            vars.link_item_in_hand.* = 1;
        }
    }
    if (!out) {
        HaltLinkWhenUsingItems();
        vars.link_direction.* &= ~@as(u8, 0xf);
        vars.link_delay_timer_spin_attack.* -%= 1;
        if (!sign8(vars.link_delay_timer_spin_attack.*))
            return;
        vars.player_handler_timer.* +%= 1;

        // The C reads one past the end of this three-entry table on the last
        // step; see the note on kRodAnimDelays. The value is dead, so skip it.
        if (vars.player_handler_timer.* != 3) {
            vars.link_delay_timer_spin_attack.* = tables.kRodAnimDelays[vars.player_handler_timer.*];
            return;
        }
        vars.link_debug_value_2.* = 0;
        vars.link_speed_setting.* = 0;
        vars.player_handler_timer.* = 0;
        vars.link_delay_timer_spin_attack.* = 0;
        vars.link_item_in_hand.* &= ~@as(u8, 1);
    }
    // out:
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
}

pub export fn LinkItem_Hammer() callconv(.c) void {
    if (vars.link_item_in_hand.* & 0x10 != 0)
        return;
    if (vars.button_mask_b_y.* & 0x40 == 0) {
        if (vars.is_standing_in_doorway.* != 0 or (vars.filtered_joypad_H.* & kJoypadH_Y) == 0)
            return;
        vars.button_mask_b_y.* |= 0x40;
        vars.link_delay_timer_spin_attack.* = tables.kHammerAnimDelays[0];
        vars.link_cant_change_direction.* |= 1;
        vars.link_animation_steps.* = 0;
        vars.player_handler_timer.* = 0;
        vars.link_item_in_hand.* = 2;
    }

    HaltLinkWhenUsingItems();
    vars.link_direction.* &= ~@as(u8, 0xf);
    vars.link_delay_timer_spin_attack.* -%= 1;
    if (!sign8(vars.link_delay_timer_spin_attack.*))
        return;
    vars.player_handler_timer.* +%= 1;

    // The C reads one past the end of this three-entry table on the last step;
    // see the note on kRodAnimDelays. The value is dead, so skip it.
    if (vars.player_handler_timer.* != 3)
        vars.link_delay_timer_spin_attack.* = tables.kHammerAnimDelays[vars.player_handler_timer.*];
    if (vars.player_handler_timer.* == 1) {
        TileDetect_MainHandler(3);
        Ancilla_AddHitStars(22, 0);
        if (vars.sound_effect_1.* == 0) {
            _ = misc.Ancilla_Sfx2_Near(16);
            SpawnHammerWaterSplash();
        }
    } else if (vars.player_handler_timer.* == 3) {
        vars.player_handler_timer.* = 0;
        vars.link_delay_timer_spin_attack.* = 0;
        vars.button_mask_b_y.* &= ~@as(u8, 0x40);
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
        vars.link_item_in_hand.* &= ~@as(u8, 2);
    }
}

pub export fn LinkItem_Bow() callconv(.c) void {
    if (vars.button_mask_b_y.* & 0x40 == 0) {
        if (vars.is_standing_in_doorway.* != 0 or !CheckYButtonPress())
            return;
        vars.link_cant_change_direction.* |= 1;
        vars.link_delay_timer_spin_attack.* = tables.kBowDelays[0];
        vars.link_animation_steps.* = 0;
        vars.player_handler_timer.* = 0;
        vars.link_item_in_hand.* = 16;
    }
    HaltLinkWhenUsingItems();
    vars.link_direction.* &= ~@as(u8, 0xf);
    vars.link_delay_timer_spin_attack.* -%= 1;
    if (!sign8(vars.link_delay_timer_spin_attack.*))
        return;
    vars.player_handler_timer.* +%= 1;

    // The C reads one past the end of this three-entry table on the last step;
    // see the note on kRodAnimDelays. The value is dead, so skip it.
    if (vars.player_handler_timer.* != 3) {
        vars.link_delay_timer_spin_attack.* = tables.kBowDelays[vars.player_handler_timer.*];
        return;
    }

    const obj = AncillaAdd_Arrow(9, vars.link_direction_facing.*, 2,
        vars.link_x_coord.*, vars.link_y_coord.*);
    if (obj >= 0) {
        if (vars.archery_game_arrows_left.* != 0) {
            vars.archery_game_arrows_left.* -%= 1;
            vars.link_num_arrows.* +%= 2;
        }
        if (vars.archery_game_out_of_arrows.* == 0 and vars.link_num_arrows.* != 0) {
            vars.link_num_arrows.* -%= 1;
            if (vars.link_num_arrows.* == 0)
                hud.Hud_RefreshIcon();
        } else {
            vars.ancilla_type[@intCast(obj)] = 0;
            _ = misc.Ancilla_Sfx2_Near(60);
        }
    }

    vars.player_handler_timer.* = 0;
    vars.link_delay_timer_spin_attack.* = 0;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
    vars.link_cant_change_direction.* &= ~@as(u8, 1);
    vars.link_item_in_hand.* &= ~@as(u8, 0x10);
    if (vars.button_b_frames.* >= 9)
        vars.button_b_frames.* = 9;
}

pub export fn LinkItem_Boomerang() callconv(.c) void {
    if (vars.button_mask_b_y.* & 0x40 == 0) {
        if (vars.is_standing_in_doorway.* != 0 or !CheckYButtonPress() or
            vars.flag_for_boomerang_in_place.* != 0)
            return;
        vars.link_animation_steps.* = 0;
        vars.link_item_in_hand.* = 0x80;
        vars.player_handler_timer.* = 0;
        vars.link_delay_timer_spin_attack.* = 7;

        const s0 = AncillaAdd_Boomerang(5, 0);

        if (vars.button_b_frames.* >= 9) {
            Link_ResetBoomerangYStuff();
            return;
        }

        if (s0 == 0) {
            vars.link_direction_last.* = vars.joypad1H_last.* & kJoypadH_AnyDir;
        } else {
            vars.link_cant_change_direction.* |= 1;
        }
    } else {
        vars.link_cant_change_direction.* |= 1;
    }

    if (vars.link_item_in_hand.* != 0) {
        HaltLinkWhenUsingItems();
        vars.link_direction.* &= ~@as(u8, 0xf);
        vars.link_delay_timer_spin_attack.* -%= 1;
        if (!sign8(vars.link_delay_timer_spin_attack.*))
            return;
        vars.link_delay_timer_spin_attack.* = 5;
        vars.player_handler_timer.* +%= 1;
        if (vars.player_handler_timer.* != 2)
            return;
    }
    Link_ResetBoomerangYStuff();
}

pub export fn Link_ResetBoomerangYStuff() callconv(.c) void {
    vars.link_item_in_hand.* = 0;
    vars.player_handler_timer.* = 0;
    vars.link_delay_timer_spin_attack.* = 0;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
    if (vars.button_mask_b_y.* & 0x80 == 0)
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
}

pub export fn LinkItem_Bombs() callconv(.c) void {
    if (vars.is_standing_in_doorway.* != 0 or vars.follower_indicator.* == 13 or
        !CheckYButtonPress())
        return;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
    AncillaAdd_Bomb(7, if (features.enhanced_features0.* & features.kFeatures0_MoreActiveBombs != 0) 3 else 1);
    vars.link_item_in_hand.* = 0;
}

pub export fn LinkItem_Bottle() callconv(.c) void {
    if (!CheckYButtonPress())
        return;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
    const btidx: usize = vars.link_item_bottle_index.* - 1;
    const b = vars.link_bottle_info[btidx];
    if (b == 0)
        return;

    // Several branches `goto fail`, which is the b < 3 arm's body.
    var fail = b < 3;
    if (!fail) {
        if (b == 3) { // red potion
            if (vars.link_health_capacity.* == vars.link_health_current.*) {
                fail = true;
            } else {
                vars.link_bottle_info[btidx] = 2;
                vars.link_item_in_hand.* = 0;
                vars.submodule_index.* = 4;
                vars.saved_module_for_menu.* = vars.main_module_index.*;
                vars.main_module_index.* = 14;
                vars.animate_heart_refill_countdown.* = 7;
                hud.Hud_Rebuild();
            }
        } else if (b == 4) { // green potion
            if (vars.link_magic_power.* == 128) {
                fail = true;
            } else {
                vars.link_bottle_info[btidx] = 2;
                vars.link_item_in_hand.* = 0;
                vars.submodule_index.* = 8;
                vars.saved_module_for_menu.* = vars.main_module_index.*;
                vars.main_module_index.* = 14;
                vars.animate_heart_refill_countdown.* = 7;
                hud.Hud_Rebuild();
            }
        } else if (b == 5) { // blue potion
            if (vars.link_health_capacity.* == vars.link_health_current.* and
                vars.link_magic_power.* == 128)
            {
                fail = true;
            } else {
                vars.link_bottle_info[btidx] = 2;
                vars.link_item_in_hand.* = 0;
                vars.submodule_index.* = 9;
                vars.saved_module_for_menu.* = vars.main_module_index.*;
                vars.main_module_index.* = 14;
                vars.animate_heart_refill_countdown.* = 7;
                hud.Hud_Rebuild();
            }
        } else if (b == 6) { // fairy
            vars.link_item_in_hand.* = 0;
            if (sprite.ReleaseFairy() < 0) {
                fail = true;
            } else {
                vars.link_bottle_info[btidx] = 2;
                hud.Hud_Rebuild();
            }
        } else if (b == 7 or b == 8) { // bad/good bee
            if (ReleaseBeeFromBottle(@intCast(btidx)) == 0) {
                fail = true;
            } else {
                vars.link_bottle_info[btidx] = 2;
                hud.Hud_Rebuild();
            }
        }
    }
    if (fail)
        _ = misc.Ancilla_Sfx2_Near(60);
}

pub export fn LinkItem_Lamp() callconv(.c) void {
    if (vars.is_standing_in_doorway.* != 0 or !CheckYButtonPress())
        return;
    if (vars.link_item_torch.* != 0 and LinkCheckMagicCost(6)) {
        AncillaAdd_MagicPowder(0x1a, 0);
        misc.Dungeon_LightTorch();
        AncillaAdd_LampFlame(0x2f, 2);
    }
    vars.link_item_in_hand.* = 0;
    vars.button_mask_b_y.* = 0;
    vars.button_b_frames.* = 0;
    vars.link_cant_change_direction.* = 0;
    // button_b_frames was just zeroed, so this never fires. Kept as-is.
    if (vars.button_b_frames.* == 9)
        vars.link_speed_setting.* = 0;
}

pub export fn LinkItem_Powder() callconv(.c) void {
    const kMushroomTimer = [10]u8{ 2, 1, 1, 3, 2, 2, 2, 2, 6, 0 };

    // Two `goto out` jumps skip straight to the shared tail.
    var out = false;
    if (vars.button_mask_b_y.* & 0x40 == 0) {
        if (vars.is_standing_in_doorway.* != 0 or !CheckYButtonPress())
            return;
        if (vars.link_item_mushroom.* != 2) {
            _ = misc.Ancilla_Sfx2_Near(60);
            out = true;
        } else if (!LinkCheckMagicCost(2)) {
            out = true;
        } else {
            vars.link_delay_timer_spin_attack.* = kMushroomTimer[0];
            vars.player_handler_timer.* = 0;
            vars.link_animation_steps.* = 0;
            vars.link_direction.* &= ~@as(u8, 0xf);
            vars.link_item_in_hand.* = 0x40;
        }
    }
    if (!out) {
        vars.link_y_vel.* = 0;
        vars.link_x_vel.* = 0;
        vars.link_direction.* = 0;
        vars.link_subpixel_y.* = 0;
        vars.link_subpixel_x.* = 0;
        vars.link_moving_against_diag_tile.* = 0;
        vars.link_delay_timer_spin_attack.* -%= 1;
        if (!sign8(vars.link_delay_timer_spin_attack.*))
            return;
        vars.player_handler_timer.* +%= 1;
        vars.link_delay_timer_spin_attack.* = kMushroomTimer[vars.player_handler_timer.*];
        if (vars.player_handler_timer.* == 4)
            AncillaAdd_MagicPowder(26, 0);
        if (vars.player_handler_timer.* != 9)
            return;
        if (vars.submodule_index.* == 0)
            TileDetect_MainHandler(1);
    }
    // out:
    vars.link_item_in_hand.* = 0;
    vars.player_handler_timer.* = 0;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
}

pub export fn LinkItem_ShovelAndFlute() callconv(.c) void {
    if (vars.link_item_flute.* == 1) {
        LinkItem_Shovel();
    } else if (vars.link_item_flute.* != 0) {
        LinkItem_Flute();
    }
}

pub export fn LinkItem_Shovel() callconv(.c) void {
    const kShovelAnimDelay = [6]u8{ 7, 18, 16, 7, 18, 16 };
    const kShovelAnimDelay2 = [6]u8{ 0, 1, 2, 0, 1, 2 };
    if (vars.button_mask_b_y.* & 0x40 == 0) {
        if (vars.is_standing_in_doorway.* != 0 or !CheckYButtonPress())
            return;

        vars.link_delay_timer_spin_attack.* = kShovelAnimDelay[0];
        vars.link_var30d.* = 0;
        vars.player_handler_timer.* = 0;
        vars.link_position_mode.* = 1;
        vars.link_cant_change_direction.* |= 1;
        vars.link_animation_steps.* = 0;
    }
    HaltLinkWhenUsingItems();
    vars.link_direction.* &= ~@as(u8, 0xf);
    vars.link_delay_timer_spin_attack.* -%= 1;
    if (!sign8(vars.link_delay_timer_spin_attack.*))
        return;
    vars.link_var30d.* +%= 1;
    vars.link_delay_timer_spin_attack.* = kShovelAnimDelay[vars.link_var30d.*];
    vars.player_handler_timer.* = kShovelAnimDelay2[vars.link_var30d.*];

    if (vars.player_handler_timer.* == 1) {
        TileDetect_MainHandler(2);
        if (loPtr(vars.word_7E04B2).* != 0) {
            misc.Ancilla_Sfx3_Near(27);
            AncillaAdd_DugUpFlute(54, 0);
        }

        if ((vars.tiledetect_thick_grass.* | vars.tiledetect_destruction_aftermath.*) & 1 == 0) {
            Ancilla_AddHitStars(22, 0); // hit stars
            _ = misc.Ancilla_Sfx2_Near(5);
        } else {
            AncillaAdd_ShovelDirt(23, 0); // shovel dirt
            if (vars.is_archer_or_shovel_game.* != 0)
                DiggingGameGuy_AttemptPrizeSpawn();
            _ = misc.Ancilla_Sfx2_Near(18);
        }
    }

    if (vars.link_var30d.* == 3) {
        vars.link_var30d.* = 0;
        vars.player_handler_timer.* = 0;
        vars.button_mask_b_y.* &= 0x80;
        vars.link_position_mode.* = 0;
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
    }
}

pub export fn LinkItem_Flute() callconv(.c) void {
    if (vars.button_mask_b_y.* & 0x40 != 0) {
        vars.flute_countdown.* -%= 1;
        if (vars.flute_countdown.* != 0)
            return;
        vars.button_mask_b_y.* &= ~@as(u8, 0x40);
    }
    if (!CheckYButtonPress())
        return;
    vars.flute_countdown.* = 128;
    _ = misc.Ancilla_Sfx2_Near(19);
    if (vars.player_is_indoors.* != 0 or (vars.overworld_screen_index.* & 0x40) != 0 or
        vars.main_module_index.* == 11)
        return;
    var i: isize = 4;
    while (true) {
        if (vars.ancilla_type[@intCast(i)] == 0x27)
            return;
        i -= 1;
        if (i < 0) break;
    }
    if (vars.link_item_flute.* == 2) {
        if (vars.overworld_screen_index.* == 0x18 and
            vars.link_y_coord.* >= 0x760 and vars.link_y_coord.* < 0x7e0 and
            vars.link_x_coord.* >= 0x1cf and vars.link_x_coord.* < 0x230)
        {
            vars.submodule_index.* = 45;
            AncillaAdd_ExplodingWeatherVane(55, 0);
        }
    } else {
        AncillaAdd_Duck_take_off(39, 4);
        vars.link_need_for_pullforrupees_sprite.* = 0;
    }
}

pub export fn LinkItem_Book() callconv(.c) void {
    if (vars.button_mask_b_y.* & 0x40 != 0 or vars.is_standing_in_doorway.* != 0 or
        !CheckYButtonPress())
        return;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
    if (vars.byte_7E02ED.* != 0) {
        Link_PerformDesertPrayer();
    } else {
        _ = misc.Ancilla_Sfx2_Near(60);
    }
}

/// The three medallions share this guard verbatim in the C.
inline fn medallionBlocked() bool {
    return vars.is_standing_in_doorway.* != 0 or vars.flag_block_link_menu.* != 0 or
        (vars.dung_savegame_state_bits.* & 0x8000) != 0 or
        ((vars.link_sword_type.* +% 1) & ~@as(u8, 1)) == 0 or
        (vars.follower_dropped.* != 0 and vars.follower_indicator.* == 13);
}

pub export fn LinkItem_Ether() callconv(.c) void {
    if (!CheckYButtonPress())
        return;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);

    if (medallionBlocked()) {
        _ = misc.Ancilla_Sfx2_Near(60);
        return;
    }

    if ((vars.ancilla_type[0] | vars.ancilla_type[1] | vars.ancilla_type[2]) != 0)
        return;

    if (!LinkCheckMagicCost(1))
        return;
    vars.link_player_handler_state.* = kPlayerState_Ether;
    vars.link_cant_change_direction.* |= 1;
    vars.link_delay_timer_spin_attack.* = tables.kEtherAnimDelays[0];
    vars.state_for_spin_attack.* = 0;
    vars.step_counter_for_spin_attack.* = 0;
    vars.byte_7E0324.* = 0;
    misc.Ancilla_Sfx3_Near(35);
}

pub export fn LinkState_UsingEther() callconv(.c) void {
    vars.flag_unk1.* +%= 1;
    vars.link_delay_timer_spin_attack.* -%= 1;
    if (!sign8(vars.link_delay_timer_spin_attack.*))
        return;

    vars.step_counter_for_spin_attack.* +%= 1;
    if (vars.step_counter_for_spin_attack.* == 4) {
        misc.Ancilla_Sfx3_Near(35);
    } else if (vars.step_counter_for_spin_attack.* == 9) {
        _ = misc.Ancilla_Sfx2_Near(44);
    } else if (vars.step_counter_for_spin_attack.* == 12) {
        vars.step_counter_for_spin_attack.* = 10;
    }
    const table: []const u8 = if (features.enhanced_features0.* & features.kFeatures0_DimFlashes != 0)
        &tables.kEtherAnimDelaysNoFlash
    else
        &tables.kEtherAnimDelays;
    vars.link_delay_timer_spin_attack.* = table[vars.step_counter_for_spin_attack.*];
    vars.state_for_spin_attack.* = tables.kEtherAnimStates[vars.step_counter_for_spin_attack.*];
    if (vars.byte_7E0324.* == 0 and vars.step_counter_for_spin_attack.* == 10) {
        vars.byte_7E0324.* = 1;
        AncillaAdd_EtherSpell(24, 0);
        vars.link_auxiliary_state.* = 0;
        vars.link_incapacitated_timer.* = 0;
    }
}

pub export fn LinkItem_Bombos() callconv(.c) void {
    if (!CheckYButtonPress())
        return;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);

    if (medallionBlocked()) {
        _ = misc.Ancilla_Sfx2_Near(60);
        return;
    }

    if ((vars.ancilla_type[0] | vars.ancilla_type[1] | vars.ancilla_type[2]) != 0)
        return;

    if (!LinkCheckMagicCost(1))
        return;
    vars.link_player_handler_state.* = kPlayerState_Bombos;
    vars.link_cant_change_direction.* |= 1;
    vars.link_delay_timer_spin_attack.* = tables.kBombosAnimDelays[0];
    vars.state_for_spin_attack.* = tables.kBombosAnimStates[0];
    vars.step_counter_for_spin_attack.* = 0;
    vars.byte_7E0324.* = 0;
    misc.Ancilla_Sfx3_Near(35);
}

pub export fn LinkState_UsingBombos() callconv(.c) void {
    vars.flag_unk1.* +%= 1;
    vars.link_delay_timer_spin_attack.* -%= 1;
    if (!sign8(vars.link_delay_timer_spin_attack.*))
        return;

    vars.step_counter_for_spin_attack.* +%= 1;
    if (vars.step_counter_for_spin_attack.* == 4) {
        misc.Ancilla_Sfx3_Near(35);
    } else if (vars.step_counter_for_spin_attack.* == 10) {
        _ = misc.Ancilla_Sfx2_Near(44);
    } else if (vars.step_counter_for_spin_attack.* == 20) {
        vars.step_counter_for_spin_attack.* = 19;
    }
    vars.link_delay_timer_spin_attack.* = tables.kBombosAnimDelays[vars.step_counter_for_spin_attack.*];
    vars.state_for_spin_attack.* = tables.kBombosAnimStates[vars.step_counter_for_spin_attack.*];
    if (vars.byte_7E0324.* == 0 and vars.step_counter_for_spin_attack.* == 19) {
        vars.byte_7E0324.* = 1;
        AncillaAdd_BombosSpell(25, 0);
        vars.link_auxiliary_state.* = 0;
        vars.link_incapacitated_timer.* = 0;
    }
}

pub export fn LinkItem_Quake() callconv(.c) void {
    if (!CheckYButtonPress())
        return;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);

    if (medallionBlocked()) {
        _ = misc.Ancilla_Sfx2_Near(60);
        return;
    }

    if ((vars.ancilla_type[0] | vars.ancilla_type[1] | vars.ancilla_type[2]) != 0)
        return;

    if (!LinkCheckMagicCost(1))
        return;
    vars.link_player_handler_state.* = kPlayerState_Quake;
    vars.link_cant_change_direction.* |= 1;
    vars.link_delay_timer_spin_attack.* = tables.kQuakeAnimDelays[0];
    vars.state_for_spin_attack.* = tables.kQuakeAnimStates[0];
    vars.step_counter_for_spin_attack.* = 0;
    vars.byte_7E0324.* = 0;
    vars.link_actual_vel_z_mirror.* = 40;
    vars.link_actual_vel_z_copy_mirror.* = 40;
    loPtr(vars.link_z_coord_mirror).* = 0;
    misc.Ancilla_Sfx3_Near(35);
}

pub export fn LinkState_UsingQuake() callconv(.c) void {
    vars.flag_unk1.* +%= 1;
    vars.link_actual_vel_x.* = 0;
    vars.link_actual_vel_y.* = 0;

    if (vars.step_counter_for_spin_attack.* == 10) {
        vars.link_actual_vel_z.* = vars.link_actual_vel_z_mirror.*;
        vars.link_actual_vel_z_copy.* = vars.link_actual_vel_z_copy_mirror.*;
        loPtr(vars.link_z_coord).* = @truncate(vars.link_z_coord_mirror.*);
        vars.link_auxiliary_state.* = 2;
        Player_ChangeZ(2);
        Link_MovePosition();
        vars.link_actual_vel_z_mirror.* = vars.link_actual_vel_z.*;
        vars.link_actual_vel_z_copy_mirror.* = vars.link_actual_vel_z_copy.*;
        loPtr(vars.link_z_coord_mirror).* = @truncate(vars.link_z_coord.*);
        if (!sign8(@truncate(vars.link_z_coord.*))) {
            vars.state_for_spin_attack.* = if (sign8(vars.link_actual_vel_z.*)) 21 else 20;
            return;
        }
    } else {
        vars.link_delay_timer_spin_attack.* -%= 1;
        if (!sign8(vars.link_delay_timer_spin_attack.*))
            return;
    }

    vars.step_counter_for_spin_attack.* +%= 1;
    if (vars.step_counter_for_spin_attack.* == 4) {
        misc.Ancilla_Sfx3_Near(35);
    } else if (vars.step_counter_for_spin_attack.* == 10) {
        _ = misc.Ancilla_Sfx2_Near(44);
    } else if (vars.step_counter_for_spin_attack.* == 11) {
        _ = misc.Ancilla_Sfx2_Near(12);
    } else if (vars.step_counter_for_spin_attack.* == 12) {
        vars.step_counter_for_spin_attack.* = 11;
    }
    vars.link_delay_timer_spin_attack.* = tables.kQuakeAnimDelays[vars.step_counter_for_spin_attack.*];
    vars.state_for_spin_attack.* = tables.kQuakeAnimStates[vars.step_counter_for_spin_attack.*];
    if (vars.byte_7E0324.* == 0 and vars.step_counter_for_spin_attack.* == 11) {
        vars.byte_7E0324.* = 1;
        AncillaAdd_QuakeSpell(28, 0);
        vars.link_auxiliary_state.* = 0;
        vars.link_incapacitated_timer.* = 0;
    }
}

pub export fn Link_ActivateSpinAttack() callconv(.c) void {
    AncillaAdd_SpinAttackInitSpark(42, 0, 0);
    Link_AnimateVictorySpin();
}

pub export fn Link_AnimateVictorySpin() callconv(.c) void {
    vars.link_player_handler_state.* = 3;
    vars.link_spin_offsets.* = (vars.link_direction_facing.* >> 1) *% 12;
    vars.link_delay_timer_spin_attack.* = 3;
    vars.state_for_spin_attack.* = tables.kLinkSpinGraphicsByDir[vars.link_spin_offsets.*];
    vars.step_counter_for_spin_attack.* = 0;
    vars.button_b_frames.* = 144;
    vars.link_cant_change_direction.* |= 1;
    vars.button_mask_b_y.* = 0x80;
    LinkState_SpinAttack();
}

pub export fn LinkState_SpinAttack() callconv(.c) void {
    CacheCameraPropertiesIfOutdoors();

    if (vars.link_auxiliary_state.* != 0) {
        var i: isize = 4;
        while (true) {
            const u: usize = @intCast(i);
            if (vars.ancilla_type[u] == 0x2a or vars.ancilla_type[u] == 0x2b)
                vars.ancilla_type[u] = 0;
            i -= 1;
            if (i < 0) break;
        }
        vars.link_z_coord.* &= 0xff;
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
        vars.link_delay_timer_spin_attack.* = 0;
        vars.button_b_frames.* = 0;
        vars.button_mask_b_y.* = 0;
        vars.bitfield_for_a_button.* = 0;
        vars.state_for_spin_attack.* = 0;
        vars.step_counter_for_spin_attack.* = 0;
        vars.link_speed_setting.* = 0;
        if (vars.link_electrocute_on_touch.* != 0) {
            if (vars.link_cape_mode.* != 0)
                Link_ForceUnequipCape_quietly();
            Link_ResetSwordAndItemUsage();
            vars.link_disable_sprite_damage.* = 1;
            vars.player_handler_timer.* = 0;
            vars.link_delay_timer_spin_attack.* = 2;
            vars.link_animation_steps.* = 0;
            vars.link_direction.* &= ~@as(u8, 0xf);
            misc.Ancilla_Sfx3_Near(43);
            vars.link_player_handler_state.* = kPlayerState_Electrocution;
            LinkState_Zapped();
        } else {
            vars.link_player_handler_state.* = kPlayerState_RecoilWall;
            LinkState_Recoil();
        }
        return;
    }

    if (vars.link_incapacitated_timer.* != 0) {
        Link_HandleRecoilAndTimer(false);
    } else {
        vars.link_direction.* = 0;
        Link_HandleVelocity();
        Link_HandleCardinalCollision();
        vars.link_player_handler_state.* = kPlayerState_SpinAttacking;
        vars.fallhole_var1.* = 0;
        HandleIndoorCameraAndDoors();
    }

    vars.link_delay_timer_spin_attack.* -%= 1;
    if (!sign8(vars.link_delay_timer_spin_attack.*))
        return;

    vars.step_counter_for_spin_attack.* +%= 1;

    if (vars.step_counter_for_spin_attack.* == 2)
        misc.Ancilla_Sfx3_Near(35);

    if (vars.step_counter_for_spin_attack.* == 12) {
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
        vars.link_delay_timer_spin_attack.* = 0;
        vars.button_b_frames.* = 0;
        vars.state_for_spin_attack.* = 0;
        vars.step_counter_for_spin_attack.* = 0;
        if (vars.link_player_handler_state.* != kPlayerState_SpinAttackMotion) {
            // wtf, it's zero -- button_b_frames was cleared three lines up.
            vars.button_mask_b_y.* = if (vars.button_b_frames.* != 0)
                (vars.joypad1H_last.* & kJoypadH_B)
            else
                0;
        }
        vars.link_player_handler_state.* = kPlayerState_Ground;
    } else {
        vars.state_for_spin_attack.* = tables.kLinkSpinGraphicsByDir[
            vars.step_counter_for_spin_attack.* +% vars.link_spin_offsets.*
        ];
        vars.link_delay_timer_spin_attack.* = tables.kLinkSpinDelays[vars.step_counter_for_spin_attack.*];
        TileDetect_MainHandler(8);
    }
}

pub export fn LinkItem_Mirror() callconv(.c) void {
    if (vars.button_mask_b_y.* & 0x40 == 0) {
        if (!CheckYButtonPress())
            return;

        if (vars.follower_indicator.* == 10) {
            vars.dialogue_message_index.* = 289;
            misc.Main_ShowTextMessage();
            return;
        }
    }
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);

    if (vars.is_standing_in_doorway.* != 0 or
        (vars.cheatWalkThroughWalls.* == 0 and
            (features.enhanced_features0.* & features.kFeatures0_MirrorToDarkworld) == 0 and
            vars.player_is_indoors.* == 0 and (vars.overworld_screen_index.* & 0x40) == 0))
    {
        _ = misc.Ancilla_Sfx2_Near(60);
        return;
    }

    DoSwordInteractionWithTiles_Mirror();
}

pub export fn DoSwordInteractionWithTiles_Mirror() callconv(.c) void {
    if (vars.player_is_indoors.* != 0) {
        if (vars.flag_block_link_menu.* != 0)
            return;
        Mirror_SaveRoomData();
        if (vars.sound_effect_1.* != 60) {
            vars.index_of_changable_dungeon_objs[0] = 0;
            vars.index_of_changable_dungeon_objs[1] = 0;
        }
    } else if (vars.main_module_index.* != 11) {
        vars.last_light_vs_dark_world.* = @truncate(vars.overworld_screen_index.* & 0x40);
        if (vars.last_light_vs_dark_world.* != 0) {
            vars.bird_travel_y_lo[15] = @truncate(vars.link_y_coord.*);
            vars.bird_travel_y_hi[15] = @truncate(vars.link_y_coord.* >> 8);
            vars.bird_travel_x_lo[15] = @truncate(vars.link_x_coord.*);
            vars.bird_travel_x_hi[15] = @truncate(vars.link_x_coord.* >> 8);
        }
        vars.submodule_index.* = 35;
        vars.link_need_for_pullforrupees_sprite.* = 0;
        vars.link_triggered_by_whirlpool_sprite.* = 1;
        vars.subsubmodule_index.* = 0;
        vars.link_actual_vel_x.* = 0;
        vars.link_actual_vel_y.* = 0;
        vars.link_player_handler_state.* = kPlayerState_Mirror;
    }
}

pub export fn LinkState_CrossingWorlds() callconv(.c) void {
    Link_ResetProperties_B();
    tile_detect.TileCheckForMirrorBonk();

    // `goto do_mirror` is reached from two places.
    const t: u8 = @truncate(vars.R12.* | vars.R14.*);
    var do_mirror = (vars.overworld_screen_index.* & 0x40) != vars.last_light_vs_dark_world.* and
        (t & 0xc) != 0 and BitSum4(t) >= 2;

    if (!do_mirror and BitSum4(@truncate(vars.tiledetect_deepwater.*)) >= 2) {
        if (vars.link_item_flippers.* != 0) {
            vars.link_is_in_deep_water.* = 1;
            vars.link_some_direction_bits.* = vars.link_direction_last.*;
            Link_ResetSwimmingState();
            vars.link_player_handler_state.* = kPlayerState_Swimming;
            Link_ForceUnequipCape_quietly();
            vars.link_speed_setting.* = 0;
            return;
        }
        if ((vars.overworld_screen_index.* & 0x40) != vars.last_light_vs_dark_world.*) {
            do_mirror = true;
        } else {
            CheckAbilityToSwim();
        }
    }

    if (do_mirror) {
        vars.submodule_index.* = 44;
        vars.link_need_for_pullforrupees_sprite.* = 0;
        vars.link_triggered_by_whirlpool_sprite.* = 1;
        vars.subsubmodule_index.* = 0;
        vars.link_actual_vel_x.* = 0;
        vars.link_actual_vel_y.* = 0;
        vars.link_player_handler_state.* = kPlayerState_Mirror;
        return;
    }

    if (vars.link_is_in_deep_water.* != 0) {
        vars.link_is_in_deep_water.* = 0;
        vars.link_direction_last.* = vars.link_some_direction_bits.*;
    }

    vars.link_countdown_for_dash.* = 0;
    vars.link_is_running.* = 0;
    vars.link_speed_setting.* = 0;
    vars.button_mask_b_y.* = 0;
    vars.button_b_frames.* = 0;
    vars.link_cant_change_direction.* = 0;
    vars.swimcoll_var5[0] &= ~@as(u16, 0xff);
    vars.link_actual_vel_y.* = 0;

    if ((vars.overworld_screen_index.* & 0x40) != vars.last_light_vs_dark_world.*)
        vars.num_memorized_tiles.* = 0;

    vars.link_player_handler_state.* =
        if (vars.link_item_moon_pearl.* != 0 or (vars.overworld_screen_index.* & 0x40) == 0)
            kPlayerState_Ground
        else
            kPlayerState_PermaBunny;
}

pub export fn Link_PerformDesertPrayer() callconv(.c) void {
    vars.submodule_index.* = 5;
    vars.saved_module_for_menu.* = vars.main_module_index.*;
    vars.main_module_index.* = 14;
    vars.flag_unk1.* = 1;
    vars.some_animation_timer.* = 22;
    vars.some_animation_timer_steps.* = 0;
    vars.link_state_bits.* = 2;
    vars.link_cant_change_direction.* |= 1;
    vars.link_animation_steps.* = 0;
    vars.link_direction.* &= ~@as(u8, 0xf);
    vars.sound_effect_ambient.* = 17;
    vars.music_control.* = 242;
}

pub export fn HandleFollowersAfterMirroring() callconv(.c) void {
    TileDetect_MainHandler(0);
    vars.link_animation_steps.* = 0;
    if (vars.follower_indicator.* == 12 or vars.follower_indicator.* == 13) {
        if (vars.follower_indicator.* == 13) {
            vars.super_bomb_indicator_unk2.* = 0xfe;
            vars.super_bomb_indicator_unk1.* = 0;
        }
        if (vars.follower_dropped.* != 0) {
            vars.follower_dropped.* = 0;
            vars.follower_indicator.* = 0;
        }
    } else if (vars.follower_indicator.* == 9 or vars.follower_indicator.* == 10) {
        vars.follower_indicator.* = 0;
    } else if (vars.follower_indicator.* == 7 or vars.follower_indicator.* == 8) {
        vars.follower_indicator.* ^= (7 ^ 8);
        load_gfx.LoadFollowerGraphics();
        AncillaAdd_DwarfPoof(0x40, 4);
    }

    if (vars.link_item_moon_pearl.* == 0) {
        AncillaAdd_BunnyPoof(0x23, 4);
        Link_ForceUnequipCape_quietly();
        vars.link_bunny_transform_timer.* = 0;
    } else if (vars.link_cape_mode.* != 0) {
        Link_ForceUnequipCape();
        vars.link_bunny_transform_timer.* = 0;
    }
}

pub export fn LinkItem_Hookshot() callconv(.c) void {
    if (vars.button_mask_b_y.* & 0x40 != 0 or vars.is_standing_in_doorway.* != 0 or
        vars.bitmask_of_dragstate.* & 2 != 0 or !CheckYButtonPress())
        return;

    ResetAllAcceleration();
    vars.player_handler_timer.* = 0;
    vars.link_cant_change_direction.* |= 1;
    vars.link_delay_timer_spin_attack.* = 7;
    vars.link_animation_steps.* = 0;
    vars.link_direction.* &= ~@as(u8, 0xf);
    vars.link_position_mode.* = 4;
    vars.link_player_handler_state.* = kPlayerState_Hookshot;
    vars.link_disable_sprite_damage.* = 1;
    AncillaAdd_Hookshot(31, 3);
}

pub export fn LinkState_Hookshotting() callconv(.c) void {
    const kHookshotArrA = [4]i8{ -8, -16, 0, 0 };
    const kHookshotArrB = [4]i8{ 0, 0, 4, -12 };
    const kHookshotArrC = [4]i8{ -64, 64, 0, 0 };
    const kHookshotArrD = [4]i8{ 0, 0, -64, 64 };

    vars.link_give_damage.* = 0;
    vars.link_auxiliary_state.* = 0;
    vars.link_incapacitated_timer.* = 0;
    var i: isize = 4;
    while (vars.ancilla_type[@intCast(i)] != 0x1f) {
        i -= 1;
        if (i < 0) {
            vars.link_delay_timer_spin_attack.* -%= 1;
            if (!sign8(vars.link_delay_timer_spin_attack.*))
                return;
            vars.player_handler_timer.* = 0;
            vars.link_disable_sprite_damage.* = 0;
            vars.button_mask_b_y.* &= ~@as(u8, 0x40);
            vars.link_cant_change_direction.* &= ~@as(u8, 1);
            vars.link_position_mode.* &= ~@as(u8, 4);
            vars.link_player_handler_state.* = kPlayerState_Ground;
            if (vars.button_b_frames.* >= 9)
                vars.button_b_frames.* = 9;
            return;
        }
    }

    vars.link_delay_timer_spin_attack.* -%= 1;
    if (sign8(vars.link_delay_timer_spin_attack.*))
        vars.link_delay_timer_spin_attack.* = 0;

    if (vars.related_to_hookshot.* == 0) {
        vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
        vars.link_x_coord_safe_return_lo.* = @truncate(vars.link_x_coord.*);
        vars.link_y_vel.* = 0;
        vars.link_x_vel.* = 0;
        Link_HandleCardinalCollision();
        return;
    }

    vars.player_on_somaria_platform.* = 0;

    const hei: usize = vars.hookshot_effect_index.*;
    // `goto loc_87AD49` leaves the cleanup block below unexecuted.
    var pulling = false;
    vars.ancilla_item_to_link[hei] -%= 1;
    if (sign8(vars.ancilla_item_to_link[hei])) {
        vars.ancilla_item_to_link[hei] = 0;
    } else {
        const x: u16 = vars.ancilla_x_lo[hei] | (@as(u16, vars.ancilla_x_hi[hei]) << 8);
        const y: u16 = vars.ancilla_y_lo[hei] | (@as(u16, vars.ancilla_y_hi[hei]) << 8);
        const dir: usize = vars.ancilla_dir[hei];
        const r4 = kHookshotArrA[dir];
        const r6 = kHookshotArrB[dir];
        vars.link_actual_vel_x.* = 0;
        vars.link_actual_vel_y.* = 0;
        const r8 = kHookshotArrC[dir];
        const r10 = kHookshotArrD[dir];

        var yd: u16 = @bitCast(@as(i16, @truncate(
            @as(i32, y) + @as(i32, r4) - @as(i32, vars.link_y_coord.*),
        )));
        if (@as(i16, @bitCast(yd)) < 0) yd = 0 -% yd;
        if (yd >= 2) vars.link_actual_vel_y.* = @bitCast(r8);

        var xd: u16 = @bitCast(@as(i16, @truncate(
            @as(i32, x) + @as(i32, r6) - @as(i32, vars.link_x_coord.*),
        )));
        if (@as(i16, @bitCast(xd)) < 0) xd = 0 -% xd;
        if (xd >= 2) vars.link_actual_vel_x.* = @bitCast(r10);

        if ((vars.link_actual_vel_x.* | vars.link_actual_vel_y.*) != 0)
            pulling = true;
    }

    if (!pulling) {
        vars.ancilla_type[hei] = 0;
        vars.tagalong_var7.* = vars.tagalong_var1.*;
        vars.link_player_handler_state.* = kPlayerState_Ground;
        vars.player_handler_timer.* = 0;
        vars.link_delay_timer_spin_attack.* = 0;
        vars.related_to_hookshot.* = 0;
        vars.button_mask_b_y.* &= ~@as(u8, 0x40);
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
        vars.link_position_mode.* &= ~@as(u8, 4);
        vars.link_disable_sprite_damage.* = 0;

        if (vars.ancilla_arr1[hei] != 0) {
            vars.link_is_on_lower_level_mirror.* ^= 1;
            vars.dung_cur_floor.* -%= 1;
            if (vars.kind_of_in_room_staircase.* == 0) {
                loPtr(vars.dungeon_room_index2).* = @truncate(vars.dungeon_room_index.*);
                loPtr(vars.dungeon_room_index).* +%= 0x10;
            }
            if (vars.kind_of_in_room_staircase.* != 2) {
                vars.link_is_on_lower_level.* ^= 1;
            }
            Dungeon_FlagRoomData_Quadrants();
        }
        tile_detect.Player_TileDetectNearby();
        if (vars.tiledetect_deepwater.* & 0xf != 0 and vars.link_is_in_deep_water.* == 0) {
            vars.link_is_in_deep_water.* = 1;
            vars.link_some_direction_bits.* = vars.link_direction_last.*;
            Link_ResetSwimmingState();
            _ = AncillaAdd_Splash(21, 0);
            vars.link_player_handler_state.* = kPlayerState_Swimming;
            Link_ForceUnequipCape_quietly();
            vars.link_state_bits.* = 0;
            vars.link_picking_throw_state.* = 0;
            vars.link_grabbing_wall.* = 0;
            vars.link_speed_setting.* = 0;
            if (vars.player_is_indoors.* != 0)
                vars.link_is_on_lower_level.* = 1;
            if (vars.button_b_frames.* >= 9)
                vars.button_b_frames.* = 9;
        } else if (vars.tiledetect_pit_tile.* & 0xf != 0) {
            vars.byte_7E005C.* = 9;
            vars.link_this_controls_sprite_oam.* = 0;
            vars.player_near_pit_state.* = 1;
            vars.link_player_handler_state.* = kPlayerState_FallingIntoHole;
            if (vars.button_b_frames.* >= 9)
                vars.button_b_frames.* = 9;
        } else {
            vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
            vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
            vars.link_x_coord_safe_return_lo.* = @truncate(vars.link_x_coord.*);
            vars.link_x_coord_safe_return_hi.* = @truncate(vars.link_x_coord.* >> 8);
            Link_HandleCardinalCollision();
            HandleIndoorCameraAndDoors();
        }
        return;
    }

    // loc_87AD49:
    Link_MovePosition();
    TileDetect_MainHandler(5);
    if (vars.player_is_indoors.* != 0) {
        const x = (vars.tiledetect_vertical_ledge.* >> 4) | vars.tiledetect_vertical_ledge.* |
            vars.detection_of_ledge_tiles_horiz_uphoriz.*;
        if (x & 1 != 0) {
            vars.hookshot_var1.* -%= 1;
            if (sign8(vars.hookshot_var1.*)) {
                vars.hookshot_var1.* = 3;
                vars.related_to_hookshot.* ^= 2;
            }
        }
    }
    vars.draw_water_ripples_or_grass.* = 0;
    if (vars.related_to_hookshot.* & 2 == 0) {
        if (vars.tiledetect_thick_grass.* & 1 != 0) {
            vars.draw_water_ripples_or_grass.* = 2;
            if (!Link_PermissionForSloshSounds())
                _ = misc.Ancilla_Sfx2_Near(26);
        } else if ((vars.tiledetect_shallow_water.* | vars.tiledetect_deepwater.*) & 1 != 0) {
            vars.draw_water_ripples_or_grass.* +%= 1;
            _ = misc.Ancilla_Sfx2_Near(
                if (@as(u8, @truncate(vars.overworld_screen_index.*)) == 0x70) 27 else 28,
            );
        }
    }

    HandleIndoorCameraAndDoors();
}

pub export fn LinkItem_Cape() callconv(.c) void {
    if (vars.link_cape_mode.* == 0) {
        vars.link_bunny_transform_timer.* -%= 1;
        if (!sign8(vars.link_bunny_transform_timer.*)) {
            vars.link_direction.* &= ~@as(u8, 0xf);
            HaltLinkWhenUsingItems();
            return;
        }
        vars.link_bunny_transform_timer.* = 0;
        if (vars.is_standing_in_doorway.* != 0 or !CheckYButtonPress())
            return;
        vars.button_mask_b_y.* &= ~@as(u8, 0x40);
        if (vars.link_magic_power.* == 0) {
            _ = misc.Ancilla_Sfx2_Near(60);
            vars.dialogue_message_index.* = 123;
            misc.Main_ShowTextMessage();
            return;
        }
        vars.player_handler_timer.* = 0;
        vars.link_cape_mode.* = 1;
        vars.cape_decrement_counter.* = tables.kCapeDepletionTimers[vars.link_magic_consumption.*];
        vars.link_bunny_transform_timer.* = 20;
        AncillaAdd_CapePoof(35, 4);
        _ = misc.Ancilla_Sfx2_Near(20);
    } else {
        vars.link_disable_sprite_damage.* = 1;
        HaltLinkWhenUsingItems();
        vars.link_direction.* &= ~@as(u8, 0xf);
        vars.cape_decrement_counter.* -%= 1;
        if (vars.cape_decrement_counter.* == 0) {
            vars.cape_decrement_counter.* = tables.kCapeDepletionTimers[vars.link_magic_consumption.*];
            // Avoid magic underflow if an anti-fairy consumes magic.
            const guarded = vars.link_magic_power.* == 0 and
                (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0;
            if (guarded or blk: {
                vars.link_magic_power.* -%= 1;
                break :blk vars.link_magic_power.* == 0;
            }) {
                Link_ForceUnequipCape();
                return;
            }
        }
        vars.link_bunny_transform_timer.* -%= 1;
        if (sign8(vars.link_bunny_transform_timer.*)) {
            vars.link_bunny_transform_timer.* = 0;
            if (vars.filtered_joypad_H.* & kJoypadH_Y != 0)
                Link_ForceUnequipCape();
        }
    }
}

pub export fn Link_ForceUnequipCape() callconv(.c) void {
    AncillaAdd_CapePoof(35, 4);
    _ = misc.Ancilla_Sfx2_Near(21);
    Link_ForceUnequipCape_quietly();
}

pub export fn Link_ForceUnequipCape_quietly() callconv(.c) void {
    vars.link_bunny_transform_timer.* = 32;
    vars.link_disable_sprite_damage.* = 0;
    vars.link_cape_mode.* = 0;
    vars.link_electrocute_on_touch.* = 0;
}

pub export fn HaltLinkWhenUsingItems() callconv(.c) void {
    if (vars.dung_hdr_collision_2.* == 2 and (vars.byte_7E0322.* & 3) == 3) {
        vars.link_y_vel.* = 0;
        vars.link_x_vel.* = 0;
        vars.link_direction.* = 0;
        vars.link_subpixel_y.* = 0;
        vars.link_subpixel_x.* = 0;
        vars.link_moving_against_diag_tile.* = 0;
    }
    if (vars.player_on_somaria_platform.* != 0)
        vars.link_direction.* = 0;
}

pub export fn Link_HandleCape_passive_LiftCheck() callconv(.c) void {
    // bugfix: grabbing or pulling while wearing cape didn't drain magic
    if (vars.link_state_bits.* & 0x80 != 0 or
        ((features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0 and
            vars.link_grabbing_wall.* != 0))
        Player_CheckHandleCapeStuff();
}

pub export fn Player_CheckHandleCapeStuff() callconv(.c) void {
    if (vars.link_cape_mode.* != 0 and vars.current_item_active.* == 19) {
        // Still the cape on whichever button put it on, not just Y.
        if (hud.itemStillHeld(vars.current_item_active.*)) {
            vars.cape_decrement_counter.* -%= 1;
            if (vars.cape_decrement_counter.* != 0)
                return;
            vars.cape_decrement_counter.* = tables.kCapeDepletionTimers[vars.link_magic_consumption.*];
            if (vars.link_magic_power.* == 0) return;
            vars.link_magic_power.* -%= 1;
            if (vars.link_magic_power.* != 0) return;
        }
        Link_ForceUnequipCape();
    }
}

pub export fn LinkItem_CaneOfSomaria() callconv(.c) void {
    const kRodAnimDelaysLocal = [3]u8{ 3, 3, 5 };
    // `goto out` skips to the trailing button clear.
    out_blk: {
        if (vars.button_mask_b_y.* & 0x40 == 0) {
            if (vars.player_on_somaria_platform.* != 0 or vars.is_standing_in_doorway.* != 0 or
                !CheckYButtonPress())
                return;
            var i: isize = 4;
            var did_charge_magic = false;

            while (vars.ancilla_type[@intCast(i)] != 0x2c) {
                i -= 1;
                if (i < 0) {
                    if (!LinkCheckMagicCost(4)) {
                        // If you use the Cane of Somaria with an empty magic meter,
                        // then quickly switch to the mushroom or magic powder after
                        // the "no magic" prompt, you will automatically sprinkle
                        // magic powder despite pressing no button and having no magic.
                        if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
                            break :out_blk;
                        return;
                    }
                    did_charge_magic = true;
                    break;
                }
            }
            vars.link_debug_value_2.* = 1;
            if (AncillaAdd_SomariaBlock(0x2c, 1) < 0) {
                // If you use the Cane of Somaria while two bombs and the boomerang
                // are active, magic will be refunded instead of used.
                if (did_charge_magic or
                    (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) == 0)
                    Refund_Magic(4);
            }
            vars.link_delay_timer_spin_attack.* = kRodAnimDelaysLocal[0];
            vars.link_animation_steps.* = 0;
            vars.player_handler_timer.* = 0;
            vars.link_item_in_hand.* = 0;
            vars.link_position_mode.* |= 8;
        }

        HaltLinkWhenUsingItems();
        vars.link_direction.* &= ~@as(u8, 0xf);
        vars.link_delay_timer_spin_attack.* -%= 1;
        if (!sign8(vars.link_delay_timer_spin_attack.*))
            return;
        vars.player_handler_timer.* +%= 1;

        // The C reads one past the end of this three-entry table on the last
        // step; see the note on kRodAnimDelays. The value is dead, so skip it.
        if (vars.player_handler_timer.* != 3) {
            vars.link_delay_timer_spin_attack.* = kRodAnimDelaysLocal[vars.player_handler_timer.*];
            return;
        }
        vars.link_speed_setting.* = 0;
        vars.player_handler_timer.* = 0;
        vars.link_delay_timer_spin_attack.* = 0;
        vars.link_debug_value_2.* = 0;
        vars.link_position_mode.* &= ~@as(u8, 8);
    }
    // out:
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
}

pub export fn LinkItem_CaneOfByrna() callconv(.c) void {
    const kByrnaDelays = [4]u8{ 19, 7, 13, 32 };
    if (SearchForByrnaSpark())
        return;
    // `goto out` lands inside the player_handler_timer == 3 arm.
    var do_out = false;
    if (vars.button_mask_b_y.* & 0x40 == 0) {
        if (vars.is_standing_in_doorway.* != 0 or !CheckYButtonPress())
            return;
        if (!LinkCheckMagicCost(8)) {
            do_out = true;
        } else {
            AncillaAdd_CaneOfByrnaInitSpark(48, 0);
            vars.link_spin_attack_step_counter.* = 0;
            vars.link_delay_timer_spin_attack.* = kByrnaDelays[0];
            vars.link_var30d.* = 0;
            vars.player_handler_timer.* = 0;
            vars.link_position_mode.* = 8;
            vars.link_cant_change_direction.* |= 1;
            vars.link_animation_steps.* = 0;
        }
    }
    if (!do_out) {
        HaltLinkWhenUsingItems();
        vars.link_direction.* &= ~@as(u8, 0xf);
        vars.link_delay_timer_spin_attack.* -%= 1;
        if (!sign8(vars.link_delay_timer_spin_attack.*))
            return;
        vars.player_handler_timer.* +%= 1;
        vars.link_delay_timer_spin_attack.* = kByrnaDelays[vars.player_handler_timer.*];
        if (vars.player_handler_timer.* == 1) {
            misc.Ancilla_Sfx3_Near(42);
        } else if (vars.player_handler_timer.* == 3) {
            do_out = true;
        }
    }
    if (do_out) {
        vars.link_var30d.* = 0;
        vars.player_handler_timer.* = 0;
        vars.button_mask_b_y.* &= 0x80;
        vars.link_position_mode.* = 0;
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
    }
}

pub export fn SearchForByrnaSpark() callconv(.c) bool {
    if (vars.link_position_mode.* & 8 != 0)
        return false;
    var i: isize = 4;
    while (true) {
        if (vars.ancilla_type[@intCast(i)] == 0x31)
            return true;
        i -= 1;
        if (i < 0) break;
    }
    return false;
}

pub export fn LinkItem_Net() callconv(.c) void {
    const kBugNetTimers = [40]u8{
        11, 6, 7, 8, 1,  2, 3, 4, 5, 6,
        1,  2, 3, 4, 5,  6, 7, 8, 1, 2,
        9,  4, 5, 6, 7,  8, 1, 2, 3, 4,
        10, 8, 1, 2, 3,  4, 5, 6, 7, 8,
    };
    if (vars.button_mask_b_y.* & 0x40 == 0) {
        if (vars.is_standing_in_doorway.* != 0 or !CheckYButtonPress())
            return;

        vars.player_handler_timer.* = kBugNetTimers[(vars.link_direction_facing.* >> 1) *% 10];
        vars.link_delay_timer_spin_attack.* = 3;
        vars.link_var30d.* = 0;
        vars.link_position_mode.* = 16;
        vars.link_cant_change_direction.* |= 1;
        vars.link_animation_steps.* = 0;
        _ = misc.Ancilla_Sfx2_Near(50);
    }

    HaltLinkWhenUsingItems();
    vars.link_direction.* &= ~@as(u8, 0xf);
    vars.link_delay_timer_spin_attack.* -%= 1;
    if (!sign8(vars.link_delay_timer_spin_attack.*))
        return;

    vars.link_var30d.* +%= 1;
    vars.link_delay_timer_spin_attack.* = 3;
    // link_var30d is bumped before this lookup and only reset afterwards, so the
    // last step of each swing indexes one past its ten-entry block - entry 40 of
    // 40 for the final direction. The C reads past the table there; the value is
    // dead, because that is exactly the var30d == 10 case below, which stores 0
    // over it. Skip the read instead of reproducing it.
    {
        const idx: usize = (vars.link_direction_facing.* >> 1) *% 10 +% vars.link_var30d.*;
        if (idx < kBugNetTimers.len)
            vars.player_handler_timer.* = kBugNetTimers[idx];
    }

    if (vars.link_var30d.* == 10) {
        vars.link_var30d.* = 0;
        vars.player_handler_timer.* = 0;
        vars.button_mask_b_y.* &= 0x80;
        vars.link_position_mode.* = 0;
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
        vars.player_oam_x_offset.* = 0x80;
        vars.player_oam_y_offset.* = 0x80;
    }
}

pub export fn CheckYButtonPress() callconv(.c) bool {
    if (vars.button_mask_b_y.* & 0x40 != 0 or vars.link_incapacitated_timer.* != 0 or
        (vars.filtered_joypad_H.* & kJoypadH_Y) == 0)
        return false;
    vars.button_mask_b_y.* |= 0x40;
    return true;
}

pub export fn LinkCheckMagicCost(x: u8) callconv(.c) bool {
    const cost = tables.kLinkItem_MagicCosts[x *% 3 +% vars.link_magic_consumption.*];
    var a = vars.link_magic_power.*;
    if (a != 0 and blk: {
        a -%= cost;
        break :blk a < 0x80;
    }) {
        vars.link_magic_power.* = a;
        return true;
    }
    if (x != 3) {
        _ = misc.Ancilla_Sfx2_Near(60);
        vars.dialogue_message_index.* = 123;
        misc.Main_ShowTextMessage();
    }
    return false;
}

pub export fn Refund_Magic(x: u8) callconv(.c) void {
    const cost = tables.kLinkItem_MagicCosts[x *% 3 +% vars.link_magic_consumption.*];

    var new_magic: c_int = @as(c_int, vars.link_magic_power.*) + cost;
    // Ensure magic can't overflow (for example the cane of somaria bug)
    if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0 and new_magic >= 128)
        new_magic = 128;
    vars.link_magic_power.* = @truncate(@as(u32, @bitCast(new_magic)));
}

pub export fn Link_ItemReset_FromOverworldThings() callconv(.c) void {
    vars.some_animation_timer_steps.* = 0;
    vars.bitfield_for_a_button.* = 0;
    vars.link_state_bits.* = 0;
    vars.link_picking_throw_state.* = 0;
    vars.link_grabbing_wall.* = 0;
    vars.link_cant_change_direction.* &= ~@as(u8, 1);
}

pub export fn Link_PerformThrow() callconv(.c) void {
    if ((vars.flag_is_sprite_to_pick_up.* | vars.flag_is_ancilla_to_pick_up.*) == 0) {
        Link_ResetSwordAndItemUsage();
        vars.bitfield_for_a_button.* = 0;
        var i: isize = 15;
        while (vars.sprite_state[@intCast(i)] != 0) {
            i -= 1;
            if (i < 0)
                return;
        }

        if (vars.interacting_with_liftable_tile_x1.* == 5 or
            vars.interacting_with_liftable_tile_x1.* == 6)
        {
            vars.player_handler_timer.* = 1;
        } else {
            var pt: Point16U = undefined;
            const attr = if (vars.player_is_indoors.* != 0)
                Dungeon_LiftAndReplaceLiftable(&pt)
            else
                overworld.Overworld_HandleLiftableTiles(&pt);

            i = 8;
            while (tables.kLink_Lift_tab[@intCast(i)] != attr) {
                i -= 1;
                if (i < 0)
                    return;
            }

            vars.flag_is_sprite_to_pick_up.* = 1;
            sprite.Sprite_SpawnThrowableTerrain(@intCast(i), pt.x, pt.y);
            vars.filtered_joypad_L.* &= ~kJoypadL_A;
            vars.player_handler_timer.* = 0;
        }
    } else {
        vars.player_handler_timer.* = 0;
    }

    vars.button_mask_b_y.* = 0;
    vars.some_animation_timer.* = 6;
    vars.link_picking_throw_state.* = 1;
    vars.link_state_bits.* = 0x80;
    vars.some_animation_timer_steps.* = 0;
    vars.link_speed_setting.* = 12;
    vars.link_animation_steps.* = 0;
    vars.link_direction.* &= 0xf0;
    vars.link_cant_change_direction.* |= 1;
}

pub export fn Link_APress_LiftCarryThrow() callconv(.c) void {
    if (vars.link_state_bits.* == 0)
        return;

    // throwing?
    if ((vars.link_picking_throw_state.* & 2) != 0 and vars.some_animation_timer.* >= 5)
        vars.some_animation_timer.* = 5;

    // picking up?
    if (vars.link_picking_throw_state.* != 0)
        HaltLinkWhenUsingItems();

    if (vars.link_picking_throw_state.* & 1 != 0) {
        vars.link_animation_steps.* = 0;
        vars.link_counter_var1.* = 0;
        vars.link_direction.* &= ~@as(u8, 0xf);
    }

    vars.some_animation_timer.* -%= 1;
    if (vars.some_animation_timer.* != 0)
        return;

    if (vars.link_picking_throw_state.* & 2 != 0) {
        vars.link_state_bits.* = 0;
        vars.bitmask_of_dragstate.* = 0;
        vars.link_speed_setting.* = 0;
        if (vars.link_player_handler_state.* == 24)
            vars.link_player_handler_state.* = 0;
    } else {
        const kLiftTab0 = [10]u8{ 8, 24, 8, 24, 8, 32, 6, 8, 13, 13 };
        const kLiftTab1 = [10]u8{ 0, 1, 0, 1, 0, 1, 0, 1, 2, 3 };
        const kLiftTab2 = [29]u8{
            6,    7,    7,    5,    10,   0,    23, 0,    18,   0,
            18,   0,    8,    0,    8,    0,    254, 255, 17,   0,
            0x54, 0x52, 0x50, 0xFF, 0x51, 0x53, 0x55, 0x56, 0x57,
        };

        if (vars.player_handler_timer.* != 0) {
            if (@as(c_int, vars.player_handler_timer.*) + 1 != 9) {
                vars.player_handler_timer.* +%= 1;
                vars.some_animation_timer.* = kLiftTab0[vars.player_handler_timer.*];
                vars.some_animation_timer_steps.* = kLiftTab1[vars.player_handler_timer.*];
                if (vars.player_handler_timer.* == 6) {
                    loPtr(vars.dung_secrets_unk1).* = 0;
                    var pt: Point16U = undefined;
                    const what = if (vars.player_is_indoors.* != 0)
                        Dungeon_LiftAndReplaceLiftable(&pt)
                    else
                        overworld.Overworld_HandleLiftableTiles(&pt);
                    vars.link_player_handler_state.* = 24;
                    vars.flag_is_sprite_to_pick_up.* = 1;
                    sprite.Sprite_SpawnThrowableTerrain((what & 0xf) + 1, pt.x, pt.y);
                    vars.filtered_joypad_L.* &= ~kJoypadL_A;
                }
                return;
            }
        } else {
            // fix OOB read triggered when lifting for too long
            if (vars.some_animation_timer_steps.* >= kLiftTab2.len - 1)
                return;
            vars.some_animation_timer_steps.* +%= 1;
            vars.some_animation_timer.* = kLiftTab2[vars.some_animation_timer_steps.*];
            if (vars.some_animation_timer_steps.* != 3)
                return;
        }
    }

    // stop animation
    vars.link_picking_throw_state.* = 0;
    vars.link_cant_change_direction.* &= ~@as(u8, 1);
}

pub export fn Link_PerformDash() callconv(.c) void {
    if (vars.player_on_somaria_platform.* != 0)
        return;
    if ((vars.flag_is_sprite_to_pick_up.* | vars.flag_is_ancilla_to_pick_up.*) != 0)
        return;
    if (vars.link_state_bits.* & 0x80 != 0)
        return;
    vars.bitfield_for_a_button.* = 0;
    vars.link_countdown_for_dash.* = 29;
    vars.link_dash_ctr.* = 64;
    vars.link_player_handler_state.* = kPlayerState_StartDash;
    vars.link_is_running.* = 1;
    vars.button_mask_b_y.* &= 0x80;
    vars.link_state_bits.* = 0;
    vars.link_item_in_hand.* = 0;
    vars.bitmask_of_dragstate.* = 0;
    vars.link_moving_against_diag_tile.* = 0;

    if (vars.follower_indicator.* == tables.kTagalongArr1[vars.follower_indicator.*]) {
        std.debug.print("Warning: Write to CART!\n", .{});
        vars.link_speed_setting.* = 0;
        vars.timer_tagalong_reacquire.* = 64;
    }
}

pub export fn Link_PerformGrab() callconv(.c) void {
    if ((vars.button_mask_b_y.* & 0x80) != 0 and vars.button_b_frames.* >= 9)
        return;

    vars.link_grabbing_wall.* = 1;
    vars.link_cant_change_direction.* |= 1;
    vars.link_animation_steps.* = 0;
    vars.some_animation_timer_steps.* = 0;
    vars.some_animation_timer.* = 0;
    vars.link_var30d.* = 0;
}

pub export fn Link_APress_PullObject() callconv(.c) void {
    vars.link_direction.* &= ~@as(u8, 0xf);

    // `goto set` shares the tail of the else-if arm.
    var do_set = false;
    if (tables.kGrabWallDirs[vars.link_direction_facing.* >> 1] & vars.joypad1H_last.* == 0) {
        vars.link_var30d.* = 0;
        do_set = true;
    } else {
        vars.some_animation_timer.* -%= 1;
        if (sign8(vars.some_animation_timer.*)) {
            vars.link_var30d.* = if (vars.link_var30d.* +% 1 == 7) 1 else vars.link_var30d.* +% 1;
            do_set = true;
        }
    }
    if (do_set) {
        vars.some_animation_timer_steps.* = tables.kGrabWall_AnimSteps[vars.link_var30d.*];
        vars.some_animation_timer.* = tables.kGrabWall_AnimTimer[vars.link_var30d.*];
    }

    if (vars.joypad1L_last.* & kJoypadL_A == 0) {
        vars.link_var30d.* = 0;
        vars.some_animation_timer_steps.* = 0;
        vars.link_grabbing_wall.* = 0;
        vars.bitfield_for_a_button.* = 0;
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
    }
}

pub export fn Link_PerformStatueDrag() callconv(.c) void {
    vars.link_grabbing_wall.* = 2;
    vars.link_cant_change_direction.* |= 1;
    vars.link_animation_steps.* = 0;
    vars.some_animation_timer_steps.* = 0;
    vars.some_animation_timer.* = tables.kGrabWall_AnimTimer[0];
    vars.link_var30d.* = 0;
}

pub export fn Link_APress_StatueDrag() callconv(.c) void {
    vars.link_speed_setting.* = 20;
    // `goto skip_set` jumps past the shared animation-step assignment.
    var skip_set = false;
    const j = vars.joypad1H_last.* & tables.kGrabWallDirs[vars.link_direction_facing.* >> 1];
    if (j == 0) {
        vars.link_direction.* = 0;
        vars.link_x_vel.* = 0;
        vars.link_y_vel.* = 0;
        vars.link_animation_steps.* = 0;
        vars.link_var30d.* = 0;
    } else {
        vars.link_direction.* = j;
        vars.some_animation_timer.* -%= 1;
        if (!sign8(vars.some_animation_timer.*)) {
            skip_set = true;
        } else {
            vars.link_var30d.* = if (vars.link_var30d.* +% 1 == 7) 1 else vars.link_var30d.* +% 1;
        }
    }
    if (!skip_set) {
        vars.some_animation_timer_steps.* = tables.kGrabWall_AnimSteps[vars.link_var30d.*];
        vars.some_animation_timer.* = tables.kGrabWall_AnimTimer[vars.link_var30d.*];
    }
    // skip_set:
    if (vars.joypad1L_last.* & kJoypadL_A == 0) {
        vars.link_speed_setting.* = 0;
        vars.link_is_near_moveable_statue.* = 0;
        vars.link_var30d.* = 0;
        vars.some_animation_timer_steps.* = 0;
        vars.link_grabbing_wall.* = 0;
        vars.bitfield_for_a_button.* = 0;
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
    }
}

pub export fn Link_PerformRupeePull() callconv(.c) void {
    if (vars.link_direction_facing.* != 0)
        return;
    Link_ResetProperties_A();
    vars.link_grabbing_wall.* = 2;
    vars.link_cant_change_direction.* |= 2;

    vars.link_animation_steps.* = 0;
    vars.some_animation_timer_steps.* = 0;
    vars.some_animation_timer.* = tables.kGrabWall_AnimTimer[0];
    vars.link_var30d.* = 0;
    vars.link_player_handler_state.* = kPlayerState_PullForRupees;
    vars.link_actual_vel_y.* = 0;
    vars.link_actual_vel_x.* = 0;
    vars.button_mask_b_y.* = 0;
}

/// Shared by the two `goto reset_to_normal` sites in LinkState_TreePull.
inline fn treePullResetToNormal() void {
    vars.link_direction_facing.* = 0;
    vars.link_state_bits.* = 0;
    vars.link_cant_change_direction.* = 0;
    vars.link_player_handler_state.* = kPlayerState_Ground;
}

pub export fn LinkState_TreePull() callconv(.c) void {
    CacheCameraPropertiesIfOutdoors();
    if (vars.link_auxiliary_state.* != 0) {
        HandleLink_From1D();
        return;
    }

    // `goto out` reaches the trailing three calls; `goto out2` skips Link_MovePosition.
    var skip_move = false;
    tail: {
        if (vars.link_grabbing_wall.* != 0) {
            if (vars.button_mask_b_y.* == 0) {
                if (vars.joypad1L_last.* & kJoypadL_A == 0) {
                    vars.link_grabbing_wall.* = 0;
                    vars.link_var30d.* = 0;
                    vars.some_animation_timer.* = 2;
                    vars.some_animation_timer_steps.* = 0;
                    vars.link_cant_change_direction.* = 0;
                    vars.link_player_handler_state.* = 0;
                    LinkState_Default();
                    return;
                }
                if (vars.joypad1H_last.* & kJoypadH_Down == 0)
                    break :tail;
                vars.button_mask_b_y.* = 4;
                _ = misc.Ancilla_Sfx2_Near(0x22);
            }

            vars.some_animation_timer.* -%= 1;
            if (!sign8(vars.some_animation_timer.*))
                break :tail;
            vars.link_var30d.* +%= 1;
            const j = vars.link_var30d.*;
            // link_var30d is bumped before these lookups and only reset
            // afterwards, so the last step indexes one past both seven-entry
            // tables; see the note on kRodAnimDelays. The values are dead,
            // because that is the j == 7 case below, which stores over both
            // before anything reads them. Skip the reads.
            if (j != 7) {
                vars.some_animation_timer_steps.* = tables.kGrabWall_AnimSteps[j];
                vars.some_animation_timer.* = tables.kGrabWall_AnimTimer[j];
                break :tail;
            }

            vars.link_grabbing_wall.* = 0;
            vars.link_var30d.* = 0;
            vars.some_animation_timer.* = 2;
            vars.some_animation_timer_steps.* = 0;
            vars.link_state_bits.* = 1;
            vars.link_picking_throw_state.* = 0;
        }

        if (vars.bitmask_of_dragstate.* & 9 != 0) {
            treePullResetToNormal();
            return;
        }
        if (vars.link_var30d.* == 9) {
            if (vars.filtered_joypad_H.* & kJoypadH_AnyDir == 0) {
                skip_move = true;
                break :tail;
            }
            vars.link_player_handler_state.* = kPlayerState_Ground;
            LinkState_Default();
            return;
        }
        AncillaAdd_DashDust_charging(0x1e, 0);
        vars.some_animation_timer.* -%= 1;
        if (sign8(vars.some_animation_timer.*)) {
            const kGrabWall_AnimSteps2 = [10]u8{ 0, 1, 2, 3, 4, 0, 1, 2, 3, 0x20 }; // oob read
            vars.link_var30d.* +%= 1;
            const j = vars.link_var30d.*;
            vars.some_animation_timer_steps.* = kGrabWall_AnimSteps2[j];
            vars.some_animation_timer.* = 2;
            vars.link_actual_vel_y.* = 48;
            if (j == 9) {
                treePullResetToNormal();
                return;
            }
        }
        Flag67WithDirections();
        if (vars.link_direction.* & 3 == 0)
            vars.link_actual_vel_x.* = 0;
        if (vars.link_direction.* & 0xc == 0)
            vars.link_actual_vel_y.* = 0;
    }
    // out:
    if (!skip_move)
        Link_MovePosition();
    // out2:
    Link_HandleCardinalCollision();
    HandleIndoorCameraAndDoors();
}

pub export fn Link_PerformRead() callconv(.c) void {
    if (vars.player_is_indoors.* != 0) {
        vars.dialogue_message_index.* = Dungeon_GetTeleMsg(vars.dungeon_room_index.*);
    } else {
        vars.dialogue_message_index.* = if (vars.sram_progress_indicator.* < 2)
            0x3A
        else
            overworld.Overworld_GetSignText(vars.overworld_screen_index.*);
    }
    misc.Main_ShowTextMessage();
    vars.bitfield_for_a_button.* = 0;
}

pub export fn Link_PerformOpenChest() callconv(.c) void {
    const kReceiveItemAlternates = [76]u8{
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        255, 255, 68,  255, 255, 255, 255, 255, 53,  255,
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        255, 255, 70,  255, 255, 255, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255,
    };
    if (vars.link_direction_facing.* != 0 or vars.item_receipt_method.* != 0 or
        vars.link_auxiliary_state.* != 0)
        return;
    vars.bitfield_for_a_button.* = 0;
    var chest_position: c_int = -1;
    var item = OpenChestForItem(@truncate(vars.index_of_interacting_tile.*), &chest_position);
    if (sign8(item)) {
        vars.item_receipt_method.* = 0;
        return;
    }
    vars.item_receipt_method.* = 1;
    const alt = kReceiveItemAlternates[item];
    if (alt != 0xff) {
        const ram_addr = misc.kMemoryLocationToGiveItemTo[item];
        if (rtl.g_ram[ram_addr] != 0)
            item = alt;
    }

    Link_ReceiveItem(item, chest_position);
}

pub export fn Link_CheckNewAPress() callconv(.c) bool {
    if (vars.bitfield_for_a_button.* & 0x80 != 0 or vars.link_incapacitated_timer.* != 0 or
        (vars.filtered_joypad_L.* & kJoypadL_A) == 0)
        return false;
    vars.bitfield_for_a_button.* |= 0x80;
    return true;
}

pub export fn Link_HandleToss() callconv(.c) bool {
    if ((vars.bitfield_for_a_button.* & 0x80) == 0 or
        (vars.filtered_joypad_L.* & kJoypadL_A) == 0 or
        (vars.link_picking_throw_state.* & 1) != 0)
        return false;
    vars.link_var30d.* = 0;
    vars.link_var30e.* = 0;
    vars.some_animation_timer_steps.* = 0;
    vars.bitfield_for_a_button.* = 0;
    vars.link_cant_change_direction.* &= ~@as(u8, 1);
    // debug stuff here
    return true;
}

pub export fn Link_HandleDiagonalCollision() callconv(.c) void {
    if (CheckIfRoomNeedsDoubleLayerCheck()) {
        Player_LimitDirections_Inner();
        CreateVelocityFromMovingBackground();
    }
    vars.link_direction.* &= 0xf;
    Player_LimitDirections_Inner();
}

pub export fn Player_LimitDirections_Inner() callconv(.c) void {
    vars.link_direction_mask_a.* = 0xf;
    vars.link_direction_mask_b.* = 0xf;
    vars.link_num_orthogonal_directions.* = 0;

    const kMasks = [4]u8{ 7, 0xB, 0xD, 0xE };

    if (vars.link_direction.* & 0xC != 0) {
        vars.link_num_orthogonal_directions.* +%= 1;

        vars.link_last_direction_moved_towards.* = if (vars.link_direction.* & 8 != 0) 0 else 1;
        tile_detect.TileDetect_Movement_VerticalSlopes(vars.link_last_direction_moved_towards.*);

        if ((vars.R14.* & 0x30) != 0 and (vars.tiledetect_var1.* & 2) == 0 and
            (((vars.R14.* & 0x30) >> 4) & vars.link_direction.*) == 0 and
            (vars.link_direction.* & 3) != 0)
        {
            vars.link_direction_mask_a.* = kMasks[if (vars.link_direction.* & 2 != 0) 2 else 3];
        } else {
            // `goto set_thingy` skips the body but still runs the tail.
            var set_thingy = vars.dung_hdr_collision.* == 0 and
                vars.link_auxiliary_state.* != 0 and (vars.R12.* & 3) != 0;

            if (!set_thingy and (vars.R14.* & 3) != 0) {
                vars.link_moving_against_diag_tile.* = 0;
                if (vars.link_flag_moving.* != 0 and
                    (vars.bitfield_spike_cactus_tiles.* & 3) == 0 and
                    (vars.link_direction.* & 3) != 0)
                {
                    vars.swimcoll_var1[0] = 0;
                    vars.swimcoll_var5[0] = 0;
                    vars.swimcoll_var7[0] = 0;
                    vars.swimcoll_var9[0] = 0;
                }
                set_thingy = true;
            }
            if (set_thingy) {
                vars.fallhole_var1.* = 1;
                vars.link_direction_mask_a.* = kMasks[vars.link_last_direction_moved_towards.*];
            }
        }

        if (vars.link_direction.* & 3 != 0) {
            vars.link_num_orthogonal_directions.* +%= 1;

            vars.link_last_direction_moved_towards.* = if (vars.link_direction.* & 2 != 0) 2 else 3;
            tile_detect.TileDetect_Movement_HorizontalSlopes(vars.link_last_direction_moved_towards.*);

            if ((vars.R14.* & 0x30) != 0 and (vars.tiledetect_var1.* & 2) != 0 and
                (((vars.R14.* & 0x30) >> 2) & vars.link_direction.*) == 0 and
                (vars.link_direction.* & 0xC) != 0)
            {
                vars.link_direction_mask_b.* = kMasks[if (vars.link_direction.* & 8 != 0) 0 else 1];
            } else {
                var set_thingy_b = vars.dung_hdr_collision.* == 0 and
                    vars.link_auxiliary_state.* != 0 and (vars.R12.* & 3) != 0;

                if (!set_thingy_b and (vars.R14.* & 3) != 0) {
                    vars.link_moving_against_diag_tile.* = 0;
                    if (vars.link_flag_moving.* != 0 and
                        (vars.bitfield_spike_cactus_tiles.* & 3) == 0 and
                        (vars.link_direction.* & 0xC) != 0)
                    {
                        vars.swimcoll_var1[1] = 0;
                        vars.swimcoll_var5[1] = 0;
                        vars.swimcoll_var7[1] = 0;
                        vars.swimcoll_var9[1] = 0;
                    }
                    set_thingy_b = true;
                }
                if (set_thingy_b) {
                    vars.fallhole_var1.* = 1;
                    vars.link_direction_mask_b.* = kMasks[vars.link_last_direction_moved_towards.*];
                }
            }

            vars.link_direction.* &= vars.link_direction_mask_a.* & vars.link_direction_mask_b.*;
        }
    }

    // ending
    if ((vars.link_direction.* & 0xf) != 0 and (vars.link_moving_against_diag_tile.* & 0xf) != 0)
        vars.link_direction.* = vars.link_moving_against_diag_tile.* & 0xf;

    if (vars.link_num_orthogonal_directions.* == 2) {
        vars.link_num_orthogonal_directions.* = if (vars.link_direction_facing.* & 4 != 0) 2 else 1;
    } else {
        vars.link_num_orthogonal_directions.* = 0;
    }
}

pub export fn Link_HandleCardinalCollision() callconv(.c) void {
    vars.tiledetect_diag_state.* = 0;
    vars.tiledetect_diagonal_tile.* = 0;

    const cond1 = (vars.link_moving_against_diag_tile.* & 0x30) != 0 or blk: {
        Link_HandleDiagonalKickback();
        break :blk vars.moving_against_diag_deadlocked.* == 0;
    };

    if (cond1 and CheckIfRoomNeedsDoubleLayerCheck()) {
        // The yx/xy labels pick which axis runs first; both then fall through.
        const vertical_first = pick: {
            if (vars.dung_hdr_collision.* < 2 or vars.dung_hdr_collision.* == 3)
                break :pick true;
            vars.tile_coll_flag.* = 2;
            tile_detect.Player_TileDetectNearby();
            vars.byte_7E0316.* = @truncate(vars.R14.*);
            if (vars.byte_7E0316.* == 0)
                break :pick true;
            vars.link_y_vel.* +%= @truncate(vars.dung_floor_y_vel.*);
            vars.link_x_vel.* +%= @truncate(vars.dung_floor_x_vel.*);

            const a: u8 = @truncate(vars.R14.*);
            if (a == 12 or a == 3)
                break :pick true;
            if (a == 10 or a == 5)
                break :pick false;
            if ((a & 0xc) == 0 and (a & 3) == 0)
                break :pick true;

            if (vars.link_y_vel.* != 0)
                break :pick false;
            if (vars.link_x_vel.* == 0)
                break :pick true;

            break :pick sign8(@truncate(vars.dung_floor_y_vel.*));
        };
        if (vertical_first) {
            RunSlopeCollisionChecks_VerticalFirst();
        } else {
            RunSlopeCollisionChecks_HorizontalFirst();
        }
        CreateVelocityFromMovingBackground();
    } // endif_1

    if (vars.dung_hdr_collision.* == 2) {
        tile_detect.Player_TileDetectNearby();
        if ((@as(u8, @truncate(vars.R14.*)) | vars.byte_7E0316.*) == 0xf) {
            if (vars.countdown_for_blink.* == 0)
                vars.countdown_for_blink.* = 58;
            if (vars.link_direction.* == 0) {
                if (loPtr(vars.dung_floor_y_vel).* != 0)
                    vars.link_y_vel.* = 0 -% vars.link_y_vel.*;
                if (loPtr(vars.dung_floor_x_vel).* != 0)
                    vars.link_x_vel.* = 0 -% vars.link_x_vel.*;
            }
        }
        vars.tile_coll_flag.* = 1;
        RunSlopeCollisionChecks_VerticalFirst();
    } else if (vars.dung_hdr_collision.* == 3) {
        vars.tile_coll_flag.* = 1;
        RunSlopeCollisionChecks_HorizontalFirst();
    } else if (vars.dung_hdr_collision.* == 4 or
        (vars.link_x_vel.* | vars.link_y_vel.*) != 0)
    {
        vars.tile_coll_flag.* = 1;
        RunSlopeCollisionChecks_VerticalFirst();
    } else {
        const st = vars.link_player_handler_state.*;
        if (st != 19 and st != 8 and st != 9 and st != 10 and st != 3) {
            tile_detect.Player_TileDetectNearby();
            if (vars.tiledetect_pit_tile.* & 0xf != 0) {
                vars.link_player_handler_state.* = kPlayerState_FallingIntoHole;
                if (vars.link_is_running.* == 0)
                    vars.link_speed_setting.* = 4;
            }
        }
    }

    TileDetect_MainHandler(0);
    if (vars.link_num_orthogonal_directions.* != 0)
        vars.link_moving_against_diag_tile.* = 0;

    if (vars.link_player_handler_state.* != 11) {
        vars.link_y_vel.* = @truncate(vars.link_y_coord.* -% vars.link_y_coord_safe_return_lo.*);
        if (vars.link_y_vel.* != 0)
            vars.link_direction.* = (vars.link_direction.* & 3) |
                (if (sign8(vars.link_y_vel.*)) @as(u8, 8) else 4);
    }

    vars.link_x_vel.* = @truncate(vars.link_x_coord.* -% vars.link_x_coord_safe_return_lo.*);
    if (vars.link_x_vel.* != 0)
        vars.link_direction.* = (vars.link_direction.* & 0xC) |
            (if (sign8(vars.link_x_vel.*)) @as(u8, 2) else 1);

    if (vars.player_is_indoors.* == 0 or vars.dung_hdr_collision.* != 4 or
        vars.link_player_handler_state.* != kPlayerState_Swimming)
        return;

    if (vars.dung_floor_y_vel.* != 0 and
        @as(u8, vars.link_y_vel.* -% @as(u8, @truncate(vars.dung_floor_y_vel.*))) == 0)
        vars.link_direction.* &= if (sign8(@truncate(vars.dung_floor_y_vel.*)))
            ~@as(u8, 8)
        else
            ~@as(u8, 4);

    if (vars.dung_floor_x_vel.* != 0 and
        @as(u8, vars.link_x_vel.* -% @as(u8, @truncate(vars.dung_floor_x_vel.*))) == 0)
        vars.link_direction.* &= if (sign8(@truncate(vars.dung_floor_x_vel.*)))
            ~@as(u8, 2)
        else
            ~@as(u8, 1);
}

pub export fn RunSlopeCollisionChecks_VerticalFirst() callconv(.c) void {
    if (vars.link_moving_against_diag_tile.* & 0x20 == 0)
        StartMovementCollisionChecks_Y();
    if (vars.link_moving_against_diag_tile.* & 0x10 == 0)
        StartMovementCollisionChecks_X();
}

pub export fn RunSlopeCollisionChecks_HorizontalFirst() callconv(.c) void {
    if (vars.link_moving_against_diag_tile.* & 0x10 == 0)
        StartMovementCollisionChecks_X();
    if (vars.link_moving_against_diag_tile.* & 0x20 == 0)
        StartMovementCollisionChecks_Y();
}

pub export fn CheckIfRoomNeedsDoubleLayerCheck() callconv(.c) bool {
    if (vars.dung_hdr_collision.* == 0 or vars.dung_hdr_collision.* == 4)
        return false;

    if (vars.dung_hdr_collision.* >= 2) {
        vars.link_y_coord.* +%= vars.BG1VOFS_copy2.* -% vars.BG2VOFS_copy2.*;
        vars.related_to_moving_floor_y.* = vars.link_y_coord.*;
        vars.link_x_coord.* +%= vars.BG1HOFS_copy2.* -% vars.BG2HOFS_copy2.*;
        vars.related_to_moving_floor_x.* = vars.link_x_coord.*;
    }
    vars.link_is_on_lower_level.* = 1;
    return true;
}

pub export fn CreateVelocityFromMovingBackground() callconv(.c) void {
    if (vars.dung_hdr_collision.* != 1) {
        const x = vars.link_x_coord.* -% vars.related_to_moving_floor_x.*;
        const y = vars.link_y_coord.* -% vars.related_to_moving_floor_y.*;
        vars.link_y_coord.* +%= vars.BG2VOFS_copy2.* -% vars.BG1VOFS_copy2.*;
        vars.link_x_coord.* +%= vars.BG2HOFS_copy2.* -% vars.BG1HOFS_copy2.*;
        if (vars.link_direction.* != 0) {
            vars.link_x_vel.* +%= @truncate(x);
            vars.link_y_vel.* +%= @truncate(y);
        }
    }
    vars.link_is_on_lower_level.* = 0;
}

pub export fn StartMovementCollisionChecks_Y() callconv(.c) void {
    if (vars.link_y_vel.* == 0)
        return;

    if (vars.is_standing_in_doorway.* == 1) {
        vars.link_last_direction_moved_towards.* =
            if (@as(u8, @truncate(vars.link_y_coord.*)) < 0x80) 0 else 1;
    } else {
        vars.link_last_direction_moved_towards.* = if (sign8(vars.link_y_vel.*)) 0 else 1;
    }
    tile_detect.TileDetect_Movement_Y(vars.link_last_direction_moved_towards.*);
    if (vars.player_is_indoors.* != 0) {
        StartMovementCollisionChecks_Y_HandleIndoors();
    } else {
        StartMovementCollisionChecks_Y_HandleOutdoors();
    }
}

pub export fn StartMovementCollisionChecks_Y_HandleIndoors() callconv(.c) void {
    // Three entry points into the tail: normal fall-through, `endif_1b`, `label_3`.
    const Entry = enum { normal, endif_1b, label_3 };
    var entry: Entry = .normal;
    var do_else_7 = false;

    outer: {
        if (sign8(vars.link_state_bits.*) or vars.link_incapacitated_timer.* != 0) {
            vars.R14.* |= vars.R14.* >> 4;
        } else {
            if (vars.is_standing_in_doorway.* == 2) {
                if (vars.link_num_orthogonal_directions.* == 0) {
                    if (vars.dung_hdr_collision.* != 3 or vars.link_is_on_lower_level.* == 0) {
                        Link_AddInVelocityY();
                        ChangeAxisOfPerpendicularDoorMovement_Y();
                        return;
                    }
                    entry = .label_3;
                    break :outer;
                } else if (vars.tiledetect_var1.* != 0) {
                    Link_AddInVelocityY();
                    entry = .endif_1b;
                    break :outer;
                }
            } // else_3
            if (vars.R14.* & 0x70 != 0) {
                if ((vars.R14.* >> 8) & 7 != 0) {
                    vars.force_move_any_direction.* = if (sign8(vars.link_y_vel.*)) 8 else 4;
                } // endif_6

                vars.is_standing_in_doorway.* = 1;
                vars.link_on_conveyor_belt.* = 0;
                if ((vars.R14.* & 0x70) != 0x70) {
                    if (vars.R14.* & 5 != 0) { // if_7
                        vars.link_moving_against_diag_tile.* = 0;
                        Link_AddInVelocityYFalling();
                        CalculateSnapScratch_Y();
                        vars.is_standing_in_doorway.* = 0;

                        if (vars.R14.* & 0x20 != 0 and (vars.R14.* & 1) == 0 and
                            (vars.link_x_coord.* & 7) == 1)
                            vars.link_x_coord.* &= ~@as(u16, 7);
                        do_else_7 = true;
                        break :outer;
                    }
                    if (vars.R14.* & 0x20 != 0) {
                        do_else_7 = true;
                        break :outer;
                    }
                } else { // else_7
                    do_else_7 = true;
                    break :outer;
                }
            }
        }
    } // endif_1

    if (do_else_7) {
        if (vars.tile_coll_flag.* & 2 == 0)
            vars.link_cant_change_direction.* &= ~@as(u8, 2);
        return;
    }

    if (entry == .normal) {
        if (vars.tile_coll_flag.* & 2 == 0)
            vars.is_standing_in_doorway.* = 0;
    }

    // endif_1b:
    if (entry != .label_3) {
        if (vars.tile_coll_flag.* & 2 == 0) {
            vars.link_cant_change_direction.* &= ~@as(u8, 2);
            vars.room_transitioning_flags.* = 0;
            vars.force_move_any_direction.* = 0;
        }
    }

    // label_3:
    endif_26: {
        if ((vars.R14.* & 7) == 0 and (vars.R12.* & 5) != 0) {
            vars.link_on_conveyor_belt.* = 0;
            FlagMovingIntoSlopes_Y();
            if ((vars.link_moving_against_diag_tile.* & 0xf) != 0)
                return;
        } // endif_9

        vars.link_moving_against_diag_tile.* = 0;
        if (vars.tiledetect_key_lock_gravestones.* & 0x20 != 0) {
            const bak = vars.R14.*;
            var dummy: c_int = undefined;
            _ = OpenChestForItem(@truncate(vars.tiledetect_tile_type.*), &dummy);
            vars.tiledetect_tile_type.* = 0;
            vars.R14.* = bak;
        }
        if (vars.link_is_on_lower_level.* == 0) {
            if (vars.tiledetect_water_staircase.* & 7 != 0) {
                vars.byte_7E0322.* |= 1;
            } else if ((vars.bitfield_spike_cactus_tiles.* & 7) == 0 and
                (vars.R14.* & 2) == 0)
            { // else_11
                vars.byte_7E0322.* &= ~@as(u8, 1);
            } // endif_11
        } else { // else_10
            if ((vars.tiledetect_moving_floor_tiles.* & 7) != 0) {
                vars.byte_7E0322.* |= 2;
            } else {
                vars.byte_7E0322.* &= ~@as(u8, 2);
            }
        } // endif_11

        if (vars.tiledetect_misc_tiles.* & 0x2200 != 0) {
            const dy: u16 = if (vars.tiledetect_misc_tiles.* & 0x2000 != 0) 8 else 0;

            vars.link_rupees_goal.* +%= 5;
            const y = vars.link_y_coord.* +%
                tables.kLink_DoMoveXCoord_Indoors_dy[vars.link_last_direction_moved_towards.*] -% dy;
            const x = vars.link_x_coord.* +%
                tables.kLink_DoMoveXCoord_Indoors_dx[vars.link_last_direction_moved_towards.*];

            Dungeon_DeleteRupeeTile(x, y);
            misc.Ancilla_Sfx3_Near(10);
        } // endif_12_norupee

        if (vars.tiledetect_var4.* & 0x22 != 0) {
            vars.link_on_conveyor_belt.* = if (vars.tiledetect_var4.* & 0x20 != 0) 2 else 1;
        } else if (vars.tiledetect_var4.* & 0x2200 != 0) {
            vars.link_on_conveyor_belt.* = if (vars.tiledetect_var4.* & 0x2000 != 0) 4 else 3;
        } else {
            if (vars.bitfield_spike_cactus_tiles.* & 7 == 0 and vars.R14.* & 2 == 0)
                vars.link_on_conveyor_belt.* = 0;
        } // endif_15

        // `goto endif_19` shares the water-hop tail.
        var hop = false;
        if ((vars.tiledetect_vertical_ledge.* & 7) == 7 and RunLedgeHopTimer()) {
            Link_CancelDash();
            vars.about_to_jump_off_ledge.* +%= 1;
            vars.link_disable_sprite_damage.* = 1;
            vars.link_auxiliary_state.* = 2;
            _ = misc.Ancilla_Sfx2_Near(0x20);
            hop = true;
        } else if ((vars.tiledetect_deepwater.* & 7) == 7 and vars.link_is_in_deep_water.* == 0) {
            // if_20
            Link_CancelDash();
            if (vars.TS_copy.* == 0) {
                Dungeon_HandleLayerChange();
            } else {
                vars.link_is_in_deep_water.* = 1;
                vars.link_some_direction_bits.* = vars.link_direction_last.*;
                vars.link_state_bits.* = 0;
                vars.link_picking_throw_state.* = 0;
                vars.link_grabbing_wall.* = 0;
                vars.link_speed_setting.* = 0;
                Link_ResetSwimmingState();
                _ = misc.Ancilla_Sfx2_Near(0x20);
            }
            hop = true;
        } else {
            // else_20
            if ((vars.tiledetect_normal_tiles.* & 2) != 0 and vars.link_is_in_deep_water.* != 0) {
                if (vars.link_auxiliary_state.* != 0) {
                    vars.R14.* = 7;
                } else {
                    Link_CancelDash();
                    vars.link_direction_last.* = vars.link_some_direction_bits.*;
                    vars.link_is_in_deep_water.* = 0;
                    if (AncillaAdd_Splash(0x15, 0)) {
                        vars.link_is_in_deep_water.* = 1;
                        vars.R14.* = 7;
                    } else {
                        vars.link_disable_sprite_damage.* = 1;
                        Link_HopInOrOutOfWater_Y();
                    }
                }
            }
        } // endif_21
        if (hop) {
            // endif_19:
            vars.link_disable_sprite_damage.* = 1;
            Link_HopInOrOutOfWater_Y();
        }

        if ((vars.tiledetect_stair_tile.* & 7) == 7) {
            if (vars.link_incapacitated_timer.* != 0) {
                vars.R14.* &= ~@as(u16, 0xff);
                vars.R14.* |= vars.tiledetect_stair_tile.* & 7;
                HandlePushingBonkingSnaps_Y();
                return;
            }
            if (vars.tiledetect_inroom_staircase.* & 0x77 != 0) {
                vars.submodule_index.* =
                    if (vars.tiledetect_inroom_staircase.* & 0x70 != 0) 16 else 8;
                vars.main_module_index.* = 7;
                Link_CancelDash();
            } else if (features.enhanced_features0.* & features.kFeatures0_TurnWhileDashing != 0) {
                // avoid weirdness in stairs
                Link_CancelDash();
            }

            if ((vars.link_last_direction_moved_towards.* & 2) == 0) {
                vars.link_speed_setting.* = 2;
                vars.link_speed_modifier.* = 1;
                return;
            }
        }

        if (vars.link_speed_setting.* == 2)
            vars.link_speed_setting.* = if (vars.link_is_running.* != 0) 16 else 0;

        if (vars.link_speed_modifier.* == 1)
            vars.link_speed_modifier.* = 2;

        if (vars.tiledetect_pit_tile.* & 5 != 0 and (vars.R14.* & 2) == 0) {
            if (vars.link_player_handler_state.* == 5 or vars.link_player_handler_state.* == 2)
                return;
            vars.byte_7E005C.* = 9;
            vars.link_this_controls_sprite_oam.* = 0;
            vars.player_near_pit_state.* = 1;
            vars.link_player_handler_state.* = kPlayerState_FallingIntoHole;
            return;
        } // endif_23

        vars.link_this_controls_sprite_oam.* = 0;

        if (vars.bitfield_spike_cactus_tiles.* & 7 != 0) {
            if ((vars.link_incapacitated_timer.* | vars.countdown_for_blink.* |
                vars.link_cape_mode.*) == 0)
            {
                const on_beat = if (vars.link_last_direction_moved_towards.* == 0)
                    (vars.link_y_coord.* & 4) == 0
                else
                    (vars.link_y_coord.* & 4) != 0;
                if (on_beat and vars.countdown_for_blink.* == 0) {
                    vars.link_give_damage.* = 8;
                    Link_CancelDash();
                    Link_ForceUnequipCape_quietly();
                    LinkApplyTileRebound();
                    return;
                }
            } else {
                vars.R14.* &= ~@as(u16, 0xFF);
                vars.R14.* |= vars.bitfield_spike_cactus_tiles.* & 7;
            } // endif_24
        } // endif_24

        if (vars.dung_hdr_collision.* == 0 or vars.dung_hdr_collision.* == 4 or
            vars.link_is_on_lower_level.* == 0)
        {
            if (vars.tiledetect_var2.* != 0 and vars.link_num_orthogonal_directions.* == 0) {
                vars.byte_7E02C2.* = @truncate(vars.tiledetect_var2.*);
                vars.gravestone_push_timeout.* -%= 1;
                if (!sign8(vars.gravestone_push_timeout.*))
                    break :endif_26;
                var bits: u16 = vars.tiledetect_var2.*;
                var i: isize = 15;
                while (true) {
                    if (bits & 0x8000 != 0) {
                        const idx = FindFreeMovingBlockSlot(@intCast(i));
                        if (idx != 0xff) {
                            vars.R14.* = idx; // Unwanted side effect
                            if (!InitializePushBlock(idx, @intCast(i * 2))) {
                                Sprite_Dungeon_DrawSinglePushBlock(idx *% 2);
                                vars.R14.* = 4;
                                const d = vars.link_last_direction_moved_towards.* *% 2;
                                vars.pushedblock_facing[idx] = d;
                                vars.push_block_direction.* = d;
                                vars.pushedblocks_target[idx] = (vars.pushedblocks_y_lo[idx] -%
                                    @intFromBool(vars.link_last_direction_moved_towards.* == 1)) & 0xf;
                            }
                        }
                    }
                    bits <<= 1;
                    i -= 1;
                    if (i < 0) break;
                }
            }
            // endif_27
            vars.gravestone_push_timeout.* = 21;
        }
    }
    // endif_26:
    HandlePushingBonkingSnaps_Y();
}

pub export fn HandlePushingBonkingSnaps_Y() callconv(.c) void {
    // `goto returnb` skips to the trailing two stores; `goto label_a` skips the
    // velocity block but still runs the bonk/nudge section.
    returnb: {
        if (vars.R14.* & 7 != 0) {
            var to_label_a = false;
            if (vars.link_player_handler_state.* == kPlayerState_Swimming) {
                if (@as(u8, @truncate(vars.dung_floor_y_vel.*)) == 0)
                    ResetAllAcceleration();

                if (vars.link_num_orthogonal_directions.* != 0) {
                    Link_AddInVelocityYFalling();
                    to_label_a = true;
                }
            } // endif_2

            if (!to_label_a) {
                if (vars.R14.* & 2 != 0 or (vars.R14.* & 5) == 5) {
                    const bak = vars.R14.*;
                    Link_BonkAndSmash();
                    RepelDash();
                    vars.R14.* = bak;
                }

                vars.fallhole_var1.* = 1;

                if ((vars.R14.* & 2) == 2) {
                    Link_AddInVelocityYFalling();
                } else {
                    if (vars.link_num_orthogonal_directions.* == 1)
                        break :returnb;
                    Link_AddInVelocityYFalling();
                    if (vars.link_num_orthogonal_directions.* == 2)
                        break :returnb;
                } // endif_4
            }

            // label_a:
            if ((vars.R14.* & 5) == 5) {
                Link_BonkAndSmash();
                RepelDash();
            } else if (vars.R14.* & 4 != 0) {
                const tt = if (sign8(vars.link_y_vel.*))
                    vars.link_y_vel.*
                else
                    0 -% vars.link_y_vel.*;
                const r0: u8 = if (sign8(tt)) 0xff else 1;
                if ((vars.R14.* & 2) == 0) {
                    if (vars.link_y_coord.* & 7 != 0) {
                        // C adds the byte as a signed displacement.
                        vars.link_x_coord.* +%= @bitCast(@as(i16, @as(i8, @bitCast(r0))));
                        HandleNudging(@bitCast(r0));
                        return;
                    }
                    Link_BonkAndSmash();
                    RepelDash();
                }
            } else { // else_7
                const tt = if (sign8(vars.link_y_vel.*))
                    0 -% vars.link_y_vel.*
                else
                    vars.link_y_vel.*;
                const r0: u8 = if (sign8(tt)) 0xff else 1;
                if ((vars.R14.* & 2) == 0) {
                    if (vars.link_x_coord.* & 7 != 0) {
                        vars.link_x_coord.* +%= @bitCast(@as(i16, @as(i8, @bitCast(r0))));
                        HandleNudging(@bitCast(r0));
                        return;
                    }
                    Link_BonkAndSmash();
                    RepelDash();
                }
            }
            // endif_10
            if (vars.link_last_direction_moved_towards.* *% 2 == vars.link_direction_facing.*) {
                vars.bitmask_of_dragstate.* |= (vars.tile_coll_flag.* & 1) << 1;
                if (vars.button_b_frames.* == 0) {
                    vars.link_timer_push_get_tired.* -%= 1;
                    if (!sign8(vars.link_timer_push_get_tired.*))
                        return;
                }

                vars.bitmask_of_dragstate.* |= if (vars.tiledetect_misc_tiles.* & 0x20 != 0)
                    vars.tile_coll_flag.* << 3
                else
                    vars.tile_coll_flag.*;
            }
        } else { // else_1
            if (vars.link_is_on_lower_level.* != 0)
                return;
            vars.bitmask_of_dragstate.* &= ~@as(u8, 9);
        } // endif_1
    }

    // returnb:
    vars.link_timer_push_get_tired.* = 32;
    vars.bitmask_of_dragstate.* &= ~@as(u8, 2);
}

pub export fn StartMovementCollisionChecks_Y_HandleOutdoors() callconv(.c) void {
    if (vars.link_speed_setting.* == 2)
        vars.link_speed_setting.* = if (vars.link_is_running.* != 0) 16 else 0;

    if ((vars.tiledetect_pit_tile.* & 5) != 0 and (vars.R14.* & 2) == 0) {
        if (vars.link_player_handler_state.* != 5 and vars.link_player_handler_state.* != 2) {
            // start fall into hole
            vars.byte_7E005C.* = 9;
            vars.link_this_controls_sprite_oam.* = 0;
            vars.player_near_pit_state.* = 1;
            vars.link_player_handler_state.* = kPlayerState_FallingIntoHole;
        }
        return;
    }

    if (vars.tiledetect_read_something.* & 2 != 0) {
        vars.interacting_with_liftable_tile_x1.* =
            @truncate(vars.interacting_with_liftable_tile_x2.* >> 1);
    } else {
        vars.interacting_with_liftable_tile_x1.* = 0;
    } // endif_2

    if ((vars.tiledetect_deepwater.* & 2) != 0 and vars.link_is_in_deep_water.* == 0 and
        vars.link_auxiliary_state.* == 0)
    {
        Link_ResetSwordAndItemUsage();
        Link_CancelDash();
        vars.link_is_in_deep_water.* = 1;
        vars.link_some_direction_bits.* = vars.link_direction_last.*;
        vars.link_grabbing_wall.* = 0;
        vars.link_speed_setting.* = 0;
        Link_ResetSwimmingState();
        // The comma operator runs the unequip only when the first test passes.
        if (vars.draw_water_ripples_or_grass.* == 1 and blk: {
            Link_ForceUnequipCape_quietly();
            break :blk vars.link_item_flippers.* != 0;
        }) {
            if (vars.link_is_bunny_mirror.* == 0)
                vars.link_player_handler_state.* = kPlayerState_Swimming;
        } else {
            _ = misc.Ancilla_Sfx2_Near(0x20);
            vars.link_y_coord.* = (@as(u16, vars.link_y_coord_safe_return_hi.*) << 8) |
                vars.link_y_coord_safe_return_lo.*;
            vars.link_x_coord.* = (@as(u16, vars.link_x_coord_safe_return_hi.*) << 8) |
                vars.link_x_coord_safe_return_lo.*;
            vars.link_disable_sprite_damage.* = 1;
            Link_HopInOrOutOfWater_Y();
        }
    } // endif_afterSwimCheck

    if (vars.link_is_in_deep_water.* != 0) {
        if (vars.tiledetect_vertical_ledge.* & 7 != 0) {
            vars.R14.* = vars.tiledetect_vertical_ledge.* & 7;
            HandlePushingBonkingSnaps_Y();
            return;
        }
        if ((vars.tiledetect_stair_tile.* & 7) == 7 or
            (vars.tiledetect_normal_tiles.* & 7) == 7)
        {
            Link_CancelDash();
            vars.link_is_in_deep_water.* = 0;
            if (vars.link_auxiliary_state.* == 0) {
                vars.link_direction_last.* = vars.link_some_direction_bits.*;
                vars.link_disable_sprite_damage.* = 1;
                _ = AncillaAdd_Splash(0x15, 0);
                Link_HopInOrOutOfWater_Y();
                return;
            }
        }
    }

    if (vars.detection_of_ledge_tiles_horiz_uphoriz.* & 2 != 0 or
        vars.detection_of_unknown_tile_types.* & 0x22 != 0)
    {
        vars.R14.* = 7;
        HandlePushingBonkingSnaps_Y();
        return;
    }

    if (vars.tiledetect_vertical_ledge.* & 0x70 != 0 and RunLedgeHopTimer()) {
        Link_CancelDash();
        vars.link_disable_sprite_damage.* = 1;
        vars.allow_scroll_z.* = 1;
        vars.link_player_handler_state.* = 11;
        vars.link_incapacitated_timer.* = 0;
        vars.link_z_coord_mirror.* = 0xffff;
        vars.bitmask_of_dragstate.* = 0;
        vars.link_speed_setting.* = 0;
        const v: u8 = if (vars.link_is_in_deep_water.* != 0) 14 else 20;
        vars.link_actual_vel_z_mirror.* = v;
        vars.link_actual_vel_z_copy_mirror.* = v;
        vars.link_auxiliary_state.* = if (vars.link_is_in_deep_water.* != 0) 4 else 2;
        return;
    }

    if (vars.tiledetect_vertical_ledge.* & 7 != 0 and RunLedgeHopTimer()) {
        _ = misc.Ancilla_Sfx2_Near(0x20);
        vars.link_disable_sprite_damage.* = 1;
        Link_CancelDash();
        vars.bitmask_of_dragstate.* = 0;
        vars.link_speed_setting.* = 0;
        Link_FindValidLandingTile_North();
        return;
    }

    if (vars.link_is_in_deep_water.* == 0) {
        if (vars.tiledetect_ledges_down_leftright.* & 7 != 0 and
            (vars.tiledetect_vertical_ledge.* & 0x77) == 0)
        {
            const xand: u8 = if (vars.index_of_interacting_tile.* == 0x2f) 4 else 1;
            if ((vars.tiledetect_ledges_down_leftright.* & xand) != 0 and RunLedgeHopTimer()) {
                Link_CancelDash();
                vars.link_actual_vel_x.* =
                    if (vars.tiledetect_ledges_down_leftright.* & 4 != 0) 16 else @bitCast(@as(i8, -16));
                vars.link_disable_sprite_damage.* = 1;
                vars.bitmask_of_dragstate.* = 0;
                vars.link_speed_setting.* = 0;
                vars.allow_scroll_z.* = 1;
                vars.link_auxiliary_state.* = 2;
                vars.link_actual_vel_z_mirror.* = 20;
                vars.link_actual_vel_z_copy_mirror.* = 20;
                vars.link_z_coord_mirror.* |= 0xff;
                vars.link_incapacitated_timer.* = 0;
                vars.link_player_handler_state.* = 14;
                return;
            }
        } // endif_6

        if (vars.detection_of_ledge_tiles_horiz_uphoriz.* & 0x70 != 0 and
            (vars.tiledetect_vertical_ledge.* & 0x77) == 0 and RunLedgeHopTimer())
        {
            Link_CancelDash();
            _ = misc.Ancilla_Sfx2_Near(0x20);
            vars.link_last_direction_moved_towards.* =
                if (vars.detection_of_ledge_tiles_horiz_uphoriz.* & 0x40 != 0) 3 else 2;
            vars.link_disable_sprite_damage.* = 1;
            vars.bitmask_of_dragstate.* = 0;
            vars.link_speed_setting.* = 0;
            Link_FindValidLandingTile_DiagonalNorth();
            return;
        }
    } // endif_7

    if ((vars.tiledetect_stair_tile.* & 7) == 7) {
        if (vars.link_incapacitated_timer.* != 0) {
            vars.R14.* = vars.tiledetect_stair_tile.* & 7;
            HandlePushingBonkingSnaps_Y();
            return;
        } else if (vars.link_last_direction_moved_towards.* & 2 == 0) {
            vars.link_speed_setting.* = 2;
            vars.link_speed_modifier.* = 1;
            return;
        }
    } // endif_8

    if (vars.link_speed_setting.* == 2)
        vars.link_speed_setting.* = if (vars.link_is_running.* != 0) 16 else 0;

    if (vars.link_speed_modifier.* == 1)
        vars.link_speed_modifier.* = 2;

    if ((vars.R14.* & 7) == 0 and (vars.R12.* & 5) != 0) {
        FlagMovingIntoSlopes_Y();
        if ((vars.link_moving_against_diag_tile.* & 0xf) != 0)
            return;
    } // endif_11

    vars.link_moving_against_diag_tile.* = 0;
    if (vars.tiledetect_key_lock_gravestones.* & 2 != 0 and
        vars.link_last_direction_moved_towards.* == 0)
    {
        const push = vars.link_is_running.* != 0 or blk: {
            vars.gravestone_push_timeout.* -%= 1;
            break :blk sign8(vars.gravestone_push_timeout.*);
        };
        if (push) {
            const bak = vars.R14.*;
            AncillaAdd_GraveStone(0x24, 4);
            vars.R14.* = bak;
            vars.gravestone_push_timeout.* = 52;
        }
    } else {
        vars.gravestone_push_timeout.* = 52;
    } // endif_12

    if ((vars.bitfield_spike_cactus_tiles.* & 7) != 0) {
        if ((vars.link_incapacitated_timer.* | vars.countdown_for_blink.* |
            vars.link_cape_mode.*) == 0)
        {
            const on_beat = if (vars.link_last_direction_moved_towards.* == 0)
                (vars.link_y_coord.* & 4) == 0
            else
                (vars.link_y_coord.* & 4) != 0;
            if (on_beat) {
                vars.link_give_damage.* = 8;
                Link_CancelDash();
                Link_ForceUnequipCape_quietly();
                LinkApplyTileRebound();
                return;
            }
        } else {
            vars.R14.* = vars.bitfield_spike_cactus_tiles.* & 7;
        }
    } // endif_13
    HandlePushingBonkingSnaps_Y();
}

pub export fn RunLedgeHopTimer() callconv(.c) bool {
    var rv = false;
    if (vars.link_auxiliary_state.* != 1) {
        if (vars.link_is_running.* == 0) {
            vars.link_timer_jump_ledge.* -%= 1;
            if (sign8(vars.link_timer_jump_ledge.*)) {
                vars.link_timer_jump_ledge.* = 19;
                return true;
            }
        } else {
            rv = true;
        }
    }
    vars.link_y_coord.* = vars.link_y_coord_prev.*;
    vars.link_x_coord.* = vars.link_x_coord_prev.*;
    vars.link_subpixel_y.* = 0;
    vars.link_subpixel_x.* = 0;
    return rv;
}

/// misc.h keeps this as a `static inline` with no linkable symbol, and it
/// searches *backwards*.
inline fn FindInByteArray(data: []const u8, lookfor: u8, size: usize) c_int {
    var i = size;
    while (i > 0) {
        i -= 1;
        if (data[i] == lookfor)
            return @intCast(i);
    }
    return -1;
}

pub export fn Link_BonkAndSmash() callconv(.c) void {
    if (vars.link_is_running.* == 0 or vars.link_dash_ctr.* == 64 or
        (vars.bitmask_for_dashable_tiles.* & 0x70) == 0)
        return;
    var i: usize = 0;
    while (i < 2) : (i += 1) {
        var pt: Point16U = undefined;
        const j = overworld.Overworld_SmashRockPile(i != 0, &pt);
        if (j >= 0) {
            const k = FindInByteArray(&tables.kLink_Lift_tab, @truncate(@as(u32, @bitCast(j))), 9);
            if (k >= 0) {
                if (k == 2 or k == 4)
                    misc.Ancilla_Sfx3_Near(0x32);
                sprite.Sprite_SpawnImmediatelySmashedTerrain(@intCast(k), pt.x, pt.y);
            }
        }
    }
}

pub export fn Link_AddInVelocityYFalling() callconv(.c) void {
    const sub = (vars.tiledetect_which_y_pos[0] & 7) -%
        @as(u16, if (sign8(vars.link_y_vel.*)) 8 else 0);
    vars.link_y_coord.* -%= sub;
}

/// Adjust X coord to fit through door
pub export fn CalculateSnapScratch_Y() callconv(.c) void {
    var yv = vars.link_y_vel.*;
    if (vars.R14.* & 4 != 0) {
        if (!sign8(yv)) yv = 0 -% yv;
    } else {
        if (sign8(yv)) yv = 0 -% yv;
    }
    vars.link_x_coord.* +%= if (!sign8(yv)) 1 else @as(u16, 0xffff);
}

pub export fn ChangeAxisOfPerpendicularDoorMovement_Y() callconv(.c) void {
    vars.link_cant_change_direction.* |= 2;
    const t: u8 = @truncate((vars.R14.* | (vars.R14.* >> 4)) & 0xf);
    if (t & 7 == 0) {
        vars.is_standing_in_doorway.* = 0;
        return;
    }
    var vel: i8 = undefined;
    var dir: u8 = undefined;

    if (@as(u8, @truncate(vars.link_x_coord.*)) >= 0x80) {
        var tv = vars.link_y_vel.*;
        if (!sign8(tv)) tv = 0 -% tv;
        vel = if (sign8(tv)) -1 else 1;
        dir = 4;
    } else {
        var tv = vars.link_y_vel.*;
        if (sign8(tv)) tv = 0 -% tv;
        vel = if (sign8(tv)) -1 else 1;
        dir = 6;
    }
    if (vars.link_cant_change_direction.* & 1 == 0)
        vars.link_direction_facing.* = dir;
    vars.link_x_coord.* +%= @bitCast(@as(i16, vel));
}

pub export fn Link_AddInVelocityY() callconv(.c) void {
    vars.link_y_coord.* -%= @bitCast(@as(i16, @as(i8, @bitCast(vars.link_y_vel.*))));
}

pub export fn Link_HopInOrOutOfWater_Y() callconv(.c) void {
    const kRecoilVelY = [3]u8{ 24, 16, 16 };

    const ts: usize = if (vars.player_is_indoors.* == 0)
        2
    else if (vars.about_to_jump_off_ledge.* != 0)
        0
    else
        vars.TS_copy.*;

    var vel: i8 = @bitCast(kRecoilVelY[ts]);
    if (vars.link_last_direction_moved_towards.* == 0)
        vel = -%vel;

    vars.link_actual_vel_y.* = @bitCast(vel);
    vars.link_actual_vel_x.* = 0;
    vars.link_actual_vel_z.* = tables.kRecoilVelZ__Link_HopInOrOutOfWater_Y[ts];
    vars.link_actual_vel_z_copy.* = vars.link_actual_vel_z.*;
    vars.link_z_coord.* = 0;
    vars.link_incapacitated_timer.* = 16;
    if (vars.link_auxiliary_state.* != 2) {
        vars.link_auxiliary_state.* = 1;
        vars.link_electrocute_on_touch.* = 0;
    }
    vars.link_player_handler_state.* = 6;
}

pub export fn Link_FindValidLandingTile_North() callconv(.c) void {
    const y_coord_bak = vars.link_y_coord.*;
    vars.link_y_coord_original.* = vars.link_y_coord.*;

    while (true) {
        vars.link_y_coord.* -%= 16;
        tile_detect.TileDetect_Movement_Y(vars.link_last_direction_moved_towards.*);
        const k: u8 = @truncate(vars.tiledetect_normal_tiles.* |
            vars.tiledetect_destruction_aftermath.* | vars.tiledetect_thick_grass.* |
            vars.tiledetect_deepwater.*);
        if ((k & 7) == 7)
            break;
    }

    if (vars.tiledetect_deepwater.* & 7 != 0) {
        vars.link_auxiliary_state.* = 1;
        vars.link_electrocute_on_touch.* = 0;
        vars.link_is_in_deep_water.* = 1;
        vars.link_some_direction_bits.* = vars.link_direction_last.*;
        Link_ResetSwimmingState();
        vars.link_grabbing_wall.* = 0;
        vars.link_speed_setting.* = 0;
    }

    vars.link_y_coord.* -%= 16;
    vars.link_y_coord_original.* -%= vars.link_y_coord.*;
    vars.link_y_coord.* = y_coord_bak;

    const o: usize = @as(u8, @truncate(vars.link_y_coord_original.*)) >> 3;

    const dy: i8 = @bitCast(tables.kLink_MoveY_RecoilOther_dy[o]);
    vars.link_actual_vel_y.* = @bitCast(
        if (vars.link_last_direction_moved_towards.* != 0) dy else -%dy,
    );
    vars.link_actual_vel_x.* = 0;
    vars.link_actual_vel_z.* = tables.kLink_MoveY_RecoilOther_dz[o];
    vars.link_actual_vel_z_copy.* = vars.link_actual_vel_z.*;
    vars.link_z_coord.* = 0;
    vars.link_incapacitated_timer.* = tables.kLink_MoveY_RecoilOther_timer[o];
    vars.link_auxiliary_state.* = 2;
    vars.link_electrocute_on_touch.* = 0;
    vars.link_player_handler_state.* = 6;
}

pub export fn Link_FindValidLandingTile_DiagonalNorth() callconv(.c) void {
    const b0 = vars.link_y_coord_safe_return_lo.*;
    const b1 = vars.link_x_coord.*;
    const dir = vars.link_last_direction_moved_towards.*;

    vars.link_actual_vel_x.* =
        if (vars.link_last_direction_moved_towards.* != 2) 1 else @bitCast(@as(i8, -1));
    vars.link_last_direction_moved_towards.* = 0;
    LinkHop_FindLandingSpotDiagonallyDown();

    vars.link_x_coord.* = b1;
    vars.link_y_coord_safe_return_lo.* = b0;

    const o: usize = (vars.link_y_coord_original.* -% vars.link_y_coord.*) >> 3;
    vars.link_y_coord.* = vars.link_y_coord_original.*;

    vars.link_actual_vel_y.* = 0 -% tables.kLink_JumpOffLedgeUpDown_dy[o];
    const dx: i8 = @bitCast(tables.kLink_JumpOffLedgeUpDown_dx[o]);
    vars.link_actual_vel_x.* = @bitCast(if (dir != 2) dx else -%dx);
    vars.link_actual_vel_z.* = tables.kLink_JumpOffLedgeUpDown_dz[o];
    vars.link_actual_vel_z_copy.* = vars.link_actual_vel_z.*;
    vars.link_z_coord.* = 0;
    vars.link_z_coord_mirror.* &= ~@as(u16, 0xff);
    vars.link_auxiliary_state.* = 2;
    vars.link_electrocute_on_touch.* = 0;
    vars.link_player_handler_state.* = 13;
}

pub export fn StartMovementCollisionChecks_X() callconv(.c) void {
    if (vars.link_x_vel.* == 0)
        return;

    if (vars.is_standing_in_doorway.* == 2) {
        vars.link_last_direction_moved_towards.* =
            if (@as(u8, @truncate(vars.link_x_coord.*)) < 0x80) 2 else 3;
    } else {
        vars.link_last_direction_moved_towards.* = if (sign8(vars.link_x_vel.*)) 2 else 3;
    }
    tile_detect.TileDetect_Movement_X(vars.link_last_direction_moved_towards.*);
    if (vars.player_is_indoors.* != 0) {
        StartMovementCollisionChecks_X_HandleIndoors();
    } else {
        StartMovementCollisionChecks_X_HandleOutdoors();
    }
}

pub export fn StartMovementCollisionChecks_X_HandleIndoors() callconv(.c) void {
    const Entry = enum { normal, label_3 };
    var entry: Entry = .normal;
    var do_else_7 = false;

    outer: {
        if (sign8(vars.link_state_bits.*) or vars.link_incapacitated_timer.* != 0) {
            vars.R14.* |= vars.R14.* >> 4;
        } else {
            if (vars.link_num_orthogonal_directions.* == 0)
                vars.link_speed_modifier.* = 0;
            if (vars.is_standing_in_doorway.* == 1 and vars.link_num_orthogonal_directions.* == 0) {
                if (vars.dung_hdr_collision.* != 3 or vars.link_is_on_lower_level.* == 0) {
                    SnapOnX();
                    const spd = ChangeAxisOfPerpendicularDoorMovement_X();
                    tile_detect.HandleNudgingInADoor(spd);
                    return;
                }
                entry = .label_3;
                break :outer;
            } // else_3

            if (vars.R14.* & 0x70 != 0) {
                if ((vars.R14.* >> 8) & 7 != 0) {
                    vars.force_move_any_direction.* = if (sign8(vars.link_x_vel.*)) 2 else 1;
                } // endif_6

                vars.is_standing_in_doorway.* = 2;
                vars.link_on_conveyor_belt.* = 0;
                if ((vars.R14.* & 0x70) != 0x70) {
                    if (vars.R14.* & 7 != 0) { // if_7
                        vars.link_moving_against_diag_tile.* = 0;
                        vars.is_standing_in_doorway.* = 0;
                        SnapOnX();
                        CalculateSnapScratch_X();
                        return;
                    }
                    if (vars.R14.* & 0x70 != 0) {
                        do_else_7 = true;
                        break :outer;
                    }
                } else { // else_7
                    do_else_7 = true;
                    break :outer;
                }
            }
        }
    } // endif_1

    if (do_else_7) {
        if (vars.tile_coll_flag.* & 2 == 0)
            vars.link_cant_change_direction.* &= ~@as(u8, 2);
        return;
    }

    if (entry != .label_3) {
        if (vars.tile_coll_flag.* & 2 == 0) {
            vars.link_cant_change_direction.* &= ~@as(u8, 2);
            vars.is_standing_in_doorway.* = 0;
            vars.room_transitioning_flags.* = 0;
            vars.force_move_any_direction.* = 0;
        }
    } // label_3

    // label_3:
    if ((vars.R14.* & 2) == 0 and (vars.R12.* & 5) != 0) {
        vars.link_on_conveyor_belt.* = 0;
        FlagMovingIntoSlopes_X();
        if ((vars.link_moving_against_diag_tile.* & 0xf) != 0)
            return;
    } // endif_9

    vars.link_moving_against_diag_tile.* = 0;
    if (vars.link_is_on_lower_level.* == 0) {
        if (vars.tiledetect_water_staircase.* & 7 != 0) {
            vars.byte_7E0322.* |= 1;
        } else if ((vars.bitfield_spike_cactus_tiles.* & 7) == 0 and (vars.R14.* & 2) == 0) {
            vars.byte_7E0322.* &= ~@as(u8, 1);
        } // endif_11
    } else { // else_10
        if ((vars.tiledetect_moving_floor_tiles.* & 7) != 0) {
            vars.byte_7E0322.* |= 2;
        } else {
            vars.byte_7E0322.* &= ~@as(u8, 2);
        }
    } // endif_11

    if (vars.tiledetect_misc_tiles.* & 0x2200 != 0) {
        const dy: u16 = if (vars.tiledetect_misc_tiles.* & 0x2000 != 0) 8 else 0;

        vars.link_rupees_goal.* +%= 5;
        const y = vars.link_y_coord.* +%
            tables.kLink_DoMoveXCoord_Indoors_dy[vars.link_last_direction_moved_towards.*] -% dy;
        const x = vars.link_x_coord.* +%
            tables.kLink_DoMoveXCoord_Indoors_dx[vars.link_last_direction_moved_towards.*];

        Dungeon_DeleteRupeeTile(x, y);
        misc.Ancilla_Sfx3_Near(10);
    } // endif_12_norupee

    if (vars.tiledetect_var4.* & 0x22 != 0) {
        vars.link_on_conveyor_belt.* = if (vars.tiledetect_var4.* & 0x20 != 0) 2 else 1;
    } else if (vars.tiledetect_var4.* & 0x2200 != 0) {
        vars.link_on_conveyor_belt.* = if (vars.tiledetect_var4.* & 0x2000 != 0) 4 else 3;
    } else {
        if (vars.bitfield_spike_cactus_tiles.* & 7 == 0 and vars.R14.* & 2 == 0)
            vars.link_on_conveyor_belt.* = 0;
    } // endif_15

    // `goto endif_19` shares the water-hop tail.
    var hop = false;
    if ((vars.detection_of_ledge_tiles_horiz_uphoriz.* & 7) == 7 and RunLedgeHopTimer()) {
        Link_CancelDash();
        vars.about_to_jump_off_ledge.* +%= 1;
        vars.link_auxiliary_state.* = 2;
        hop = true;
    } else if ((vars.tiledetect_deepwater.* & 7) == 7 and vars.link_is_in_deep_water.* == 0 and
        vars.link_player_handler_state.* != 6)
    {
        // if_20
        vars.link_y_coord.* = vars.link_y_coord_safe_return_lo.* |
            (@as(u16, vars.link_y_coord_safe_return_hi.*) << 8);
        vars.link_x_coord.* = vars.link_x_coord_safe_return_lo.* |
            (@as(u16, vars.link_x_coord_safe_return_hi.*) << 8);
        Link_CancelDash();
        if (vars.TS_copy.* == 0) {
            Dungeon_HandleLayerChange();
        } else {
            vars.link_is_in_deep_water.* = 1;
            vars.link_some_direction_bits.* = vars.link_direction_last.*;
            vars.link_state_bits.* = 0;
            vars.link_picking_throw_state.* = 0;
            vars.link_grabbing_wall.* = 0;
            vars.link_speed_setting.* = 0;
            Link_ResetSwimmingState();
        }
        hop = true;
    } else {
        // else_20
        if ((vars.tiledetect_normal_tiles.* & 7) == 7 and vars.link_is_in_deep_water.* != 0) {
            if (vars.link_auxiliary_state.* != 0) {
                vars.R14.* = 7;
            } else {
                Link_CancelDash();
                // The inner re-test is dead in the C; kept verbatim.
                if (vars.link_auxiliary_state.* == 0) {
                    vars.link_direction_last.* = vars.link_some_direction_bits.*;
                    vars.link_is_in_deep_water.* = 0;
                    _ = AncillaAdd_Splash(0x15, 0);
                    vars.link_disable_sprite_damage.* = 1;
                    Link_HopInOrOutOfWater_X();
                }
            }
        }
    } // endif_21
    if (hop) {
        // endif_19:
        vars.link_disable_sprite_damage.* = 1;
        Link_HopInOrOutOfWater_X();
        _ = misc.Ancilla_Sfx2_Near(0x20);
    }

    if (vars.tiledetect_pit_tile.* & 5 != 0 and (vars.R14.* & 2) == 0) {
        if (vars.link_player_handler_state.* == 5 or vars.link_player_handler_state.* == 2)
            return;
        vars.byte_7E005C.* = 9;
        vars.link_this_controls_sprite_oam.* = 0;
        vars.player_near_pit_state.* = 1;
        vars.link_player_handler_state.* = kPlayerState_FallingIntoHole;
        return;
    } // endif_23

    vars.player_near_pit_state.* = 0;

    endif_26: {
        if (vars.bitfield_spike_cactus_tiles.* & 7 != 0) {
            if ((vars.link_incapacitated_timer.* | vars.countdown_for_blink.* |
                vars.link_cape_mode.*) == 0)
            {
                const on_beat = if (vars.link_last_direction_moved_towards.* == 2)
                    (vars.link_x_coord.* & 4) == 0
                else
                    (vars.link_x_coord.* & 4) != 0;
                if (on_beat and vars.countdown_for_blink.* == 0) {
                    vars.link_give_damage.* = 8;
                    Link_CancelDash();
                    Link_ForceUnequipCape_quietly();
                    LinkApplyTileRebound();
                    return;
                }
            } else {
                vars.R14.* &= ~@as(u16, 0xFF);
                vars.R14.* |= vars.bitfield_spike_cactus_tiles.* & 7;
            } // endif_24
        } // endif_24

        if (vars.dung_hdr_collision.* == 0 or vars.dung_hdr_collision.* == 4 or
            vars.link_is_on_lower_level.* == 0)
        {
            if (vars.tiledetect_var2.* != 0 and vars.link_num_orthogonal_directions.* == 0) {
                vars.byte_7E02C2.* = @truncate(vars.tiledetect_var2.*);
                vars.gravestone_push_timeout.* -%= 1;
                if (!sign8(vars.gravestone_push_timeout.*))
                    break :endif_26;
                var bits: u16 = vars.tiledetect_var2.*;
                var i: isize = 15;
                while (true) {
                    if (bits & 0x8000 != 0) {
                        const idx = FindFreeMovingBlockSlot(@intCast(i));
                        if (idx != 0xff) {
                            // This seems like it's overwriting the tiledetector's stuff
                            vars.R14.* = idx;
                            if (!InitializePushBlock(idx, @intCast(i * 2))) {
                                Sprite_Dungeon_DrawSinglePushBlock(idx *% 2);
                                vars.R14.* = 4;
                                const d = vars.link_last_direction_moved_towards.* *% 2;
                                vars.pushedblock_facing[idx] = d;
                                vars.push_block_direction.* = d;
                                vars.pushedblocks_target[idx] = (vars.pushedblocks_x_lo[idx] -%
                                    @intFromBool(vars.link_last_direction_moved_towards.* != 2)) & 0xf;
                            }
                        }
                    }
                    bits <<= 1;
                    i -= 1;
                    if (i < 0) break;
                }
            }
            // endif_27
            vars.gravestone_push_timeout.* = 21;
        }
    }
    // endif_26:
    if (vars.link_num_orthogonal_directions.* == 0) {
        vars.link_speed_modifier.* = 0;
        if (vars.link_speed_setting.* == 2)
            vars.link_speed_setting.* = 0;
    }
    HandlePushingBonkingSnaps_X();
}

pub export fn HandlePushingBonkingSnaps_X() callconv(.c) void {
    returnb: {
        if (vars.R14.* & 7 != 0) {
            if (vars.link_player_handler_state.* == kPlayerState_Swimming and
                @as(u8, @truncate(vars.dung_floor_x_vel.*)) == 0)
                ResetAllAcceleration();

            if (vars.R14.* & 2 != 0) {
                const bak = vars.R14.*;
                Link_BonkAndSmash();
                RepelDash();
                vars.R14.* = bak;
            }

            vars.fallhole_var1.* = 1;

            if ((vars.R14.* & 7) == 7) {
                SnapOnX();
            } else {
                if (vars.link_num_orthogonal_directions.* == 2)
                    break :returnb;
                SnapOnX();
                if (vars.link_num_orthogonal_directions.* == 1)
                    break :returnb;
            } // endif_4

            if ((vars.R14.* & 5) == 5) {
                Link_BonkAndSmash();
                RepelDash();
            } else if (vars.R14.* & 4 != 0) {
                const tt = if (sign8(vars.link_x_vel.*))
                    vars.link_x_vel.*
                else
                    0 -% vars.link_x_vel.*;
                const r0: u8 = if (sign8(tt)) 0xff else 1;
                if ((vars.R14.* & 2) == 0) {
                    if (vars.link_y_coord.* & 7 != 0) {
                        vars.link_y_coord.* +%= @bitCast(@as(i16, @as(i8, @bitCast(r0))));
                        HandleNudging(@bitCast(r0));
                        return;
                    }
                    Link_BonkAndSmash();
                    RepelDash();
                }
            } else { // else_7
                const tt = if (sign8(vars.link_x_vel.*))
                    0 -% vars.link_x_vel.*
                else
                    vars.link_x_vel.*;
                const r0: u8 = if (sign8(tt)) 0xff else 1;
                if ((vars.R14.* & 2) == 0) {
                    if (vars.link_y_coord.* & 7 != 0) {
                        vars.link_y_coord.* +%= @bitCast(@as(i16, @as(i8, @bitCast(r0))));
                        HandleNudging(@bitCast(r0));
                        return;
                    }
                    Link_BonkAndSmash();
                    RepelDash();
                }
            }
            // endif_10
            if (vars.link_last_direction_moved_towards.* *% 2 == vars.link_direction_facing.*) {
                vars.bitmask_of_dragstate.* |= (vars.tile_coll_flag.* & 1) << 1;
                if (vars.button_b_frames.* == 0) {
                    vars.link_timer_push_get_tired.* -%= 1;
                    if (!sign8(vars.link_timer_push_get_tired.*))
                        return;
                }

                vars.bitmask_of_dragstate.* |= if (vars.tiledetect_misc_tiles.* & 0x20 != 0)
                    vars.tile_coll_flag.* << 3
                else
                    vars.tile_coll_flag.*;
            }
        } else { // else_1
            if (vars.link_is_on_lower_level.* != 0)
                return;
            vars.bitmask_of_dragstate.* &= ~@as(u8, 9);
        } // endif_1
    }

    // returnb:
    vars.link_timer_push_get_tired.* = 32;
    vars.bitmask_of_dragstate.* &= ~@as(u8, 2);
}

pub export fn StartMovementCollisionChecks_X_HandleOutdoors() callconv(.c) void {
    if (vars.link_num_orthogonal_directions.* == 0) {
        vars.link_speed_modifier.* = 0;
        if (vars.link_speed_setting.* == 2)
            vars.link_speed_setting.* = 0;
    }

    if ((vars.tiledetect_pit_tile.* & 5) != 0 and (vars.R14.* & 2) == 0) {
        if (vars.link_player_handler_state.* != 5 and vars.link_player_handler_state.* != 2) {
            // start fall into hole
            vars.byte_7E005C.* = 9;
            vars.link_this_controls_sprite_oam.* = 0;
            vars.player_near_pit_state.* = 1;
            vars.link_player_handler_state.* = kPlayerState_FallingIntoHole;
        }
        return;
    }

    if (vars.tiledetect_read_something.* & 2 != 0) {
        vars.interacting_with_liftable_tile_x1b.* =
            @truncate(vars.interacting_with_liftable_tile_x2.* >> 1);
    } else {
        vars.interacting_with_liftable_tile_x1b.* = 0;
    } // endif_2

    if ((vars.tiledetect_deepwater.* & 4) != 0 and vars.link_is_in_deep_water.* == 0 and
        vars.link_auxiliary_state.* == 0)
    {
        Link_CancelDash();
        Link_ResetSwordAndItemUsage();
        vars.link_is_in_deep_water.* = 1;
        vars.link_some_direction_bits.* = vars.link_direction_last.*;
        Link_ResetSwimmingState();
        vars.link_grabbing_wall.* = 0;
        vars.link_speed_setting.* = 0;
        if (vars.draw_water_ripples_or_grass.* == 1 and blk: {
            Link_ForceUnequipCape_quietly();
            break :blk vars.link_item_flippers.* != 0;
        }) {
            if (vars.link_is_bunny_mirror.* == 0)
                vars.link_player_handler_state.* = kPlayerState_Swimming;
        } else {
            vars.link_y_coord.* = (@as(u16, vars.link_y_coord_safe_return_hi.*) << 8) |
                vars.link_y_coord_safe_return_lo.*;
            vars.link_x_coord.* = (@as(u16, vars.link_x_coord_safe_return_hi.*) << 8) |
                vars.link_x_coord_safe_return_lo.*;
            vars.link_disable_sprite_damage.* = 1;
            Link_HopInOrOutOfWater_X();
            _ = misc.Ancilla_Sfx2_Near(0x20);
        }
    } // endif_afterSwimCheck

    const ledge_block = if (vars.link_is_in_deep_water.* != 0)
        (vars.detection_of_ledge_tiles_horiz_uphoriz.* & 7) == 7
    else
        (vars.tiledetect_vertical_ledge.* & 0x42) != 0;
    if (ledge_block) {
        // not implemented, jumps to another routine
        vars.R14.* = 7;
        HandlePushingBonkingSnaps_X();
        return;
    } // endif_3

    if ((vars.tiledetect_normal_tiles.* & 7) == 7 and vars.link_is_in_deep_water.* != 0) {
        Link_CancelDash();
        if (vars.link_auxiliary_state.* == 0) {
            vars.link_direction_last.* = vars.link_some_direction_bits.*;
            vars.link_is_in_deep_water.* = 0;
            _ = AncillaAdd_Splash(0x15, 0);
            vars.link_disable_sprite_damage.* = 1;
            Link_HopInOrOutOfWater_X();
            return;
        }
    } // endif_4

    if ((vars.detection_of_ledge_tiles_horiz_uphoriz.* & 7) != 0 and RunLedgeHopTimer()) {
        _ = misc.Ancilla_Sfx2_Near(0x20);
        vars.link_actual_vel_x.* =
            if (vars.link_last_direction_moved_towards.* & 1 != 0) 0x10 else @bitCast(@as(i8, -0x10));
        Link_CancelDash();
        vars.link_auxiliary_state.* = 2;
        vars.link_actual_vel_z_mirror.* = 20;
        vars.link_actual_vel_z_copy_mirror.* = 20;
        vars.link_z_coord_mirror.* |= 0xff;
        vars.link_player_handler_state.* = kPlayerState_FallOfLeftRightLedge;
        vars.link_disable_sprite_damage.* = 1;
        vars.allow_scroll_z.* = 1;
        vars.bitmask_of_dragstate.* = 0;
        vars.link_speed_setting.* = 0;
        if (vars.player_is_indoors.* == 0)
            vars.link_is_on_lower_level.* = 2;

        const xbak = vars.link_x_coord.*;
        const rv = Link_HoppingHorizontally_FindTile_X(
            (vars.link_last_direction_moved_towards.* & ~@as(u8, 2)) *% 2,
        );
        vars.link_last_direction_moved_towards.* = 1;
        if (rv != 0xff) {
            Link_HoppingHorizontally_FindTile_Y();
        } else {
            LinkHop_FindTileToLandOnSouth();
        }
        vars.link_x_coord.* = xbak;
        return;
    } // endif_5

    if ((vars.detection_of_unknown_tile_types.* & 0x77) != 0 and RunLedgeHopTimer()) {
        const sfx = misc.Ancilla_Sfx2_Near(0x20);
        vars.link_player_handler_state.* = if ((sfx & 7) == 0) 16 else 15;
        vars.link_actual_vel_x.* =
            if (vars.link_last_direction_moved_towards.* & 1 != 0) 0x10 else @bitCast(@as(i8, -0x10));
        Link_CancelDash();
        vars.link_auxiliary_state.* = 2;
        vars.link_actual_vel_z_mirror.* = 20;
        vars.link_actual_vel_z_copy_mirror.* = 20;
        vars.link_z_coord_mirror.* |= 0xff;
        vars.link_incapacitated_timer.* = 0;
        vars.link_disable_sprite_damage.* = 1;
        vars.allow_scroll_z.* = 1;
        vars.bitmask_of_dragstate.* = 0;
        vars.link_speed_setting.* = 0;
        return;
    } // endif_6

    if ((vars.detection_of_ledge_tiles_horiz_uphoriz.* & 0x70) != 0 and
        (vars.detection_of_ledge_tiles_horiz_uphoriz.* & 0x7) == 0 and
        (vars.detection_of_unknown_tile_types.* & 0x77) == 0 and
        vars.link_player_handler_state.* != 13 and RunLedgeHopTimer())
    {
        _ = misc.Ancilla_Sfx2_Near(0x20);
        Link_CancelDash();
        vars.link_disable_sprite_damage.* = 1;
        vars.bitmask_of_dragstate.* = 0;
        vars.link_speed_setting.* = 0;
        Link_FindValidLandingTile_DiagonalNorth();
        return;
    } // endif_7

    if ((vars.tiledetect_ledges_down_leftright.* & 7) != 0 and
        (vars.detection_of_ledge_tiles_horiz_uphoriz.* & 7) == 0 and
        (vars.detection_of_unknown_tile_types.* & 0x77) == 0 and RunLedgeHopTimer())
    {
        vars.link_actual_vel_x.* =
            if (vars.link_last_direction_moved_towards.* & 1 != 0) 0x10 else @bitCast(@as(i8, -0x10));
        Link_CancelDash();
        vars.link_auxiliary_state.* = 2;
        vars.link_actual_vel_z_mirror.* = 20;
        vars.link_actual_vel_z_copy_mirror.* = 20;
        vars.link_z_coord_mirror.* |= 0xff;
        vars.link_player_handler_state.* = 14;
        vars.link_incapacitated_timer.* = 0;
        vars.link_disable_sprite_damage.* = 1;
        vars.allow_scroll_z.* = 1;
        vars.bitmask_of_dragstate.* = 0;
        vars.link_speed_setting.* = 0;
        return;
    } // endif_8

    // If force facing down (hold B button), while turboing on the Run key, we'll never
    // reach FlagMovingIntoSlopes_X causing a Dash Buffering glitch.
    // Fix by always calling it, not sure why you wouldn't always want to call it.
    if ((vars.R14.* & 2) == 0 and (vars.R12.* & 5) != 0) {
        const skip_check = vars.link_is_running.* != 0 and
            (vars.link_direction_facing.* & 4) == 0;
        if (!skip_check or
            (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0)
        {
            FlagMovingIntoSlopes_X();
            if ((vars.link_moving_against_diag_tile.* & 0xf) != 0)
                return;
        } // endif_9
    }

    vars.link_moving_against_diag_tile.* = 0;

    if ((vars.bitfield_spike_cactus_tiles.* & 7) != 0) {
        if ((vars.link_incapacitated_timer.* | vars.countdown_for_blink.* |
            vars.link_cape_mode.*) == 0)
        {
            const on_beat = if (vars.link_last_direction_moved_towards.* == 2)
                (vars.link_x_coord.* & 4) == 0
            else
                (vars.link_x_coord.* & 4) != 0;
            if (on_beat) {
                vars.link_give_damage.* = 8;
                Link_CancelDash();
                LinkApplyTileRebound();
                return;
            }
        } else {
            vars.R14.* = vars.bitfield_spike_cactus_tiles.* & 7;
        }
    } // endif_10
    HandlePushingBonkingSnaps_X();
}

pub export fn SnapOnX() callconv(.c) void {
    const sub = (vars.link_x_coord.* & 7) -%
        @as(u16, if (sign8(vars.link_x_vel.*)) 8 else 0);
    vars.link_x_coord.* -%= sub;
}

pub export fn CalculateSnapScratch_X() callconv(.c) void {
    if (vars.R14.* & 4 != 0) {
        var x: i8 = @bitCast(vars.link_x_vel.*);
        if (x >= 0) x = -%x; // wtf
        vars.link_y_coord.* +%= if (x < 0) @as(u16, 0xffff) else 1;
    } else {
        var x: i8 = @bitCast(vars.link_x_vel.*);
        if (x < 0) x = -%x;
        vars.link_y_coord.* +%= if (x < 0) @as(u16, 0xffff) else 1;
    }
}

pub export fn ChangeAxisOfPerpendicularDoorMovement_X() callconv(.c) i8 {
    vars.link_cant_change_direction.* |= 2;
    const r0: u8 = @truncate((vars.R14.* | (vars.R14.* >> 4)) & 0xf);
    if ((r0 & 7) == 0) {
        vars.is_standing_in_doorway.* = 0;
        return @bitCast(r0); // wtf?
    }

    var x_vel: i8 = @bitCast(vars.link_x_vel.*);
    var dir: u8 = undefined;
    if (@as(u8, @truncate(vars.link_y_coord.*)) >= 0x80) {
        if (x_vel >= 0) x_vel = -%x_vel;
        dir = 0;
    } else {
        if (x_vel < 0) x_vel = -%x_vel;
        dir = 2;
    }
    if (vars.link_cant_change_direction.* & 1 == 0)
        vars.link_direction_facing.* = dir;
    vars.link_y_coord.* +%= @bitCast(@as(i16, x_vel));
    return x_vel;
}

pub export fn Link_HopInOrOutOfWater_X() callconv(.c) void {
    const kRecoilVelX = [3]u8{ 28, 24, 16 };

    const ts: usize = if (vars.player_is_indoors.* == 0)
        2
    else if (vars.about_to_jump_off_ledge.* != 0)
        0
    else
        vars.TS_copy.*;

    var vel: i8 = @bitCast(kRecoilVelX[ts]);
    if (vars.link_last_direction_moved_towards.* & 1 == 0)
        vel = -%vel;
    vars.link_actual_vel_x.* = @bitCast(vel);
    vars.link_actual_vel_y.* = 0;
    vars.link_actual_vel_z.* = tables.kRecoilVelZ__Link_HopInOrOutOfWater_X[ts];
    vars.link_actual_vel_z_copy.* = vars.link_actual_vel_z.*;
    vars.link_incapacitated_timer.* = 16;
    if (vars.link_auxiliary_state.* != 2) {
        vars.link_auxiliary_state.* = 1;
        vars.link_electrocute_on_touch.* = 0;
    }
    vars.link_player_handler_state.* = 6;
}

pub export fn Link_HandleDiagonalKickback() callconv(.c) void {
    // Every `goto noHorizOrNoVertical` lands on the same single store.
    diag: {
        if (vars.link_x_vel.* != 0 and vars.link_y_vel.* != 0) {
            vars.link_y_coord_copy.* = vars.link_y_coord.*;
            vars.link_x_coord_copy.* = vars.link_x_coord.*;

            tile_detect.TileDetect_Movement_X(if (sign8(vars.link_x_vel.*)) 2 else 3);
            if ((vars.R12.* & 5) == 0)
                break :diag;
            FlagMovingIntoSlopes_X();
            if (vars.link_moving_against_diag_tile.* & 0xf == 0)
                break :diag;

            const xd: i8 = @truncate(@as(i16, @bitCast(
                vars.link_x_coord.* -% vars.link_x_coord_copy.*,
            )));
            vars.link_x_coord.* = vars.link_x_coord_copy.*;
            vars.link_x_vel.* = @bitCast(xd);

            tile_detect.TileDetect_Movement_Y(if (sign8(vars.link_y_vel.*)) 0 else 1);
            if ((vars.R12.* & 5) == 0)
                break :diag;
            FlagMovingIntoSlopes_Y();
            if (vars.link_moving_against_diag_tile.* & 0xf == 0)
                break :diag;

            vars.moving_against_diag_deadlocked.* = vars.link_moving_against_diag_tile.*;

            const yd: i8 = @truncate(@as(i16, @bitCast(
                vars.link_y_coord.* -% vars.link_y_coord_copy.*,
            )));
            vars.link_y_vel.* = @bitCast(yd);

            const xadj: i8 = if (sign8(vars.link_x_vel.*))
                kKickback_x1[@intCast(-%@as(i8, @bitCast(vars.link_x_vel.*)))]
            else
                kKickback_x0[vars.link_x_vel.*];
            vars.link_x_coord.* +%= @bitCast(@as(i16, xadj));

            const yadj: i8 = if (sign8(vars.link_y_vel.*))
                kKickback_y1[@intCast(-%@as(i8, @bitCast(vars.link_y_vel.*)))]
            else
                kKickback_y0[vars.link_y_vel.*];
            vars.link_y_coord.* +%= @bitCast(@as(i16, yadj));

            vars.link_moving_against_diag_tile.* = 0;
            return;
        }
    }
    // noHorizOrNoVertical:
    vars.moving_against_diag_deadlocked.* = 0;
    vars.link_moving_against_diag_tile.* = 0;
}

pub export fn TileDetect_MainHandler(item: u8) callconv(.c) void {
    vars.tiledetect_pit_tile.* = 0;
    tile_detect.TileDetect_ResetState();
    var o: u16 = undefined;

    if (item == 8) {
        const a: i16 = @as(i16, vars.state_for_spin_attack.*) - 2;
        if (a < 0 or a >= 8)
            return;
        const kDoSwordInteractionWithTiles_o = [8]u8{ 10, 6, 14, 2, 12, 4, 8, 0 };
        o = @as(u16, kDoSwordInteractionWithTiles_o[@intCast(a)]) + 0x40;
    } else {
        o = @as(u16, item) *% 8 +% vars.link_direction_facing.*;
    }
    o >>= 1;

    const x = ((vars.link_x_coord.* +%
        @as(u16, @bitCast(@as(i16, tables.kDoSwordInteractionWithTiles_x[o])))) &
        vars.tilemap_location_calc_mask.*) >> 3;
    const y = (vars.link_y_coord.* +%
        @as(u16, @bitCast(@as(i16, tables.kDoSwordInteractionWithTiles_y[o])))) &
        vars.tilemap_location_calc_mask.*;

    if (item == 1 or item == 2 or item == 3 or item == 6 or item == 7 or item == 8) {
        TileBehavior_HandleItemAndExecute(x, y);
        return;
    }

    tile_detect.TileDetection_Execute(x, y, 1);

    if (item == 5)
        return;

    if (vars.tiledetect_thick_grass.* & 0x10 != 0) {
        const tx: u8 = @truncate((vars.link_x_coord.* +% 0) & 0xf);
        const ty: u8 = @truncate((vars.link_y_coord.* +% 8) & 0xf);

        if ((ty < 4 or ty >= 11) and (tx < 4 or tx >= 12) and
            vars.countdown_for_blink.* == 0 and vars.link_auxiliary_state.* == 0)
        {
            if (vars.player_is_indoors.* != 0) {
                Dungeon_FlagRoomData_Quadrants();
                _ = misc.Ancilla_Sfx2_Near(0x33);
                vars.link_speed_setting.* = 0;
                vars.submodule_index.* = 21;
                loPtr(vars.dungeon_room_index_prev).* = @truncate(vars.dungeon_room_index.*);
                loPtr(vars.dungeon_room_index).* = vars.dung_hdr_travel_destinations[0];
                HandleLayerOfDestination();
            } else if (vars.link_triggered_by_whirlpool_sprite.* == 0) {
                DoSwordInteractionWithTiles_Mirror();
            }
        }
    } else { // else_3
        vars.link_triggered_by_whirlpool_sprite.* = 0;
        if (vars.tiledetect_thick_grass.* & 1 != 0) {
            vars.draw_water_ripples_or_grass.* = 2;
            if (!Link_PermissionForSloshSounds() and vars.link_auxiliary_state.* == 0)
                _ = misc.Ancilla_Sfx2_Near(26);
            return;
        }

        if (vars.tiledetect_shallow_water.* & 1 != 0) {
            vars.draw_water_ripples_or_grass.* = 1;

            if (vars.player_is_indoors.* == 0 and vars.link_is_in_deep_water.* != 0 and
                vars.link_is_bunny_mirror.* == 0)
            {
                if (vars.link_item_flippers.* != 0) {
                    vars.link_is_in_deep_water.* = 0;
                    vars.link_direction_last.* = vars.link_some_direction_bits.*;
                    vars.link_player_handler_state.* = 0;
                }
            } else if (!Link_PermissionForSloshSounds()) {
                if (@as(u8, @truncate(vars.overworld_screen_index.*)) == 0x70) {
                    _ = misc.Ancilla_Sfx2_Near(27);
                } else if (vars.link_auxiliary_state.* == 0) {
                    _ = misc.Ancilla_Sfx2_Near(28);
                }
            }
            return;
        }

        if (vars.player_is_indoors.* == 0 and vars.link_is_in_deep_water.* == 0 and
            (vars.tiledetect_deepwater.* & 1) != 0)
        {
            vars.draw_water_ripples_or_grass.* = 1;
            if (!Link_PermissionForSloshSounds()) {
                if (@as(u8, @truncate(vars.overworld_screen_index.*)) == 0x70) {
                    _ = misc.Ancilla_Sfx2_Near(27);
                } else if (vars.link_auxiliary_state.* == 0) {
                    _ = misc.Ancilla_Sfx2_Near(28);
                }
            }
            return;
        }
    }
    // else_6
    vars.draw_water_ripples_or_grass.* = 0;

    if (vars.tiledetect_spike_floor_and_tile_triggers.* & 1 != 0) {
        vars.byte_7E02ED.* = 1;
        return;
    }

    vars.byte_7E02ED.* = 0;

    if (vars.tiledetect_spike_floor_and_tile_triggers.* & 0x10 != 0) {
        vars.link_give_damage.* = 0;
        if (vars.link_cape_mode.* == 0 and !SearchForByrnaSpark() and
            vars.countdown_for_blink.* == 0)
        {
            vars.link_need_for_poof_for_transform.* = 0;
            vars.link_timer_tempbunny.* = 0;
            if (vars.link_item_moon_pearl.* != 0) {
                vars.link_is_bunny.* = 0;
                vars.link_is_bunny_mirror.* = 0;
            }
            vars.link_give_damage.* = 8;
            Link_CancelDash();
            return;
        }
    }

    if (vars.tiledetect_icy_floor.* & 0x11 != 0) {
        if (vars.link_flag_moving.* != 0) {
            if (vars.link_num_orthogonal_directions.* != 0)
                vars.link_direction_last.* = vars.link_some_direction_bits.*;
        } else { // else_11
            if (vars.link_direction.* & 0xC != 0)
                vars.swimcoll_var7[0] = 0x180;
            if (vars.link_direction.* & 3 != 0)
                vars.swimcoll_var7[0] = 0x180;

            vars.link_flag_moving.* = if (vars.tiledetect_icy_floor.* & 1 != 0) 1 else 2;
            vars.link_some_direction_bits.* = vars.link_direction_last.*;
            Link_ResetSwimmingState();
        }
    } else {
        if (vars.link_player_handler_state.* != 4) {
            if (vars.link_flag_moving.* != 0)
                vars.link_direction_last.* = vars.link_some_direction_bits.*;
            Link_ResetSwimmingState();
        }
        vars.link_flag_moving.* = 0;
    }

    if ((vars.bitfield_spike_cactus_tiles.* & 0x10) != 0 and vars.countdown_for_blink.* == 0)
        vars.countdown_for_blink.* = 58;
}

pub export fn Link_PermissionForSloshSounds() callconv(.c) bool {
    if (vars.link_direction.* & 0xf == 0)
        return true;
    if (vars.link_player_handler_state.* != 17) {
        return (vars.frame_counter.* & 0xf) != 0;
    } else {
        return (vars.frame_counter.* & 0x7) != 0;
    }
}

pub export fn PushBlock_AttemptToPushTheBlock(what: u8, x: u16, y: u16) callconv(.c) bool {
    const kChangableDungeonObj_Func1B_y0 = [4]i8{ -4, 20, 4, 4 };
    const kChangableDungeonObj_Func1B_y1 = [4]i8{ -4, 20, 12, 12 };
    const kChangableDungeonObj_Func1B_x0 = [4]i8{ 4, 4, -4, 20 };
    const kChangableDungeonObj_Func1B_x1 = [4]i8{ 12, 12, -4, 20 };

    const idx: usize = what *% 4 +% vars.link_last_direction_moved_towards.*;
    var xt: u8 = undefined;
    var new_x: u16 = undefined;
    var new_y: u16 = undefined;

    new_x = ((x +% @as(u16, @bitCast(@as(i16, kChangableDungeonObj_Func1B_x0[idx])))) &
        vars.tilemap_location_calc_mask.*) >> 3;
    new_y = (y +% @as(u16, @bitCast(@as(i16, kChangableDungeonObj_Func1B_y0[idx])))) &
        vars.tilemap_location_calc_mask.*;
    xt = PushBlock_GetTargetTileFlag(new_x, new_y);
    if (kPushBlockTileFlags[xt] != 0 and xt != 9)
        return true;

    new_x = ((x +% @as(u16, @bitCast(@as(i16, kChangableDungeonObj_Func1B_x1[idx])))) &
        vars.tilemap_location_calc_mask.*) >> 3;
    new_y = (y +% @as(u16, @bitCast(@as(i16, kChangableDungeonObj_Func1B_y1[idx])))) &
        vars.tilemap_location_calc_mask.*;
    xt = PushBlock_GetTargetTileFlag(new_x, new_y);
    if (kPushBlockTileFlags[xt] != 0 and xt != 9)
        return true;

    return false;
}

pub export fn Link_HandleLiftables() callconv(.c) u8 {
    const kGetBestActionToPerformOnTile_a = [7]u8{ 0, 1, 0, 0, 2, 1, 2 };
    const kGetBestActionToPerformOnTile_b = [7]u8{ 2, 3, 1, 4, 0, 5, 6 };

    vars.tiledetect_pit_tile.* = 0;
    tile_detect.TileDetect_ResetState();

    // These two live in zelda_rtl.zig, not player_tables.zig, and are int8.
    const y0 = (vars.link_y_coord.* +% @as(u16, @bitCast(@as(i16,
        rtl.kGetBestActionToPerformOnTile_y[vars.link_direction_facing.* >> 1],
    )))) & vars.tilemap_location_calc_mask.*;
    const y1 = (vars.link_y_coord.* +% 20) & vars.tilemap_location_calc_mask.*;

    const x0 = ((vars.link_x_coord.* +% @as(u16, @bitCast(@as(i16,
        rtl.kGetBestActionToPerformOnTile_x[vars.link_direction_facing.* >> 1],
    )))) & vars.tilemap_location_calc_mask.*) >> 3;
    const x1 = ((vars.link_x_coord.* +% 8) & vars.tilemap_location_calc_mask.*) >> 3;

    tile_detect.TileDetection_Execute(x0, y0, 1);
    tile_detect.TileDetection_Execute(x1, y1, 2);

    var action: u8 = if ((vars.R14.* | vars.tiledetect_vertical_ledge.*) & 1 != 0) 3 else 2;

    // `goto getout` skips the gloves comparison.
    getout: {
        if (vars.player_is_indoors.* != 0) {
            const a: u8 = @truncate(Dungeon_CheckForAndIDLiftableTile());
            if (a != 0xff) {
                vars.interacting_with_liftable_tile_x1.* =
                    kGetBestActionToPerformOnTile_b[a & 0xf];
            } else {
                if ((vars.tiledetect_read_something.* & 1) != 0 and
                    vars.link_direction_facing.* == 0 and
                    vars.interacting_with_liftable_tile_x2.* == 0)
                    action = 4;
                break :getout;
            }
        } else {
            if (vars.tiledetect_read_something.* & 1 == 0)
                break :getout;
            if (vars.link_direction_facing.* == 0 and
                vars.interacting_with_liftable_tile_x2.* == 0)
            {
                action = 4;
                break :getout;
            }
            vars.interacting_with_liftable_tile_x1.* =
                @truncate(vars.interacting_with_liftable_tile_x2.* >> 1);
        }
        if (@as(c_int, kGetBestActionToPerformOnTile_a[vars.interacting_with_liftable_tile_x1.*]) -
            @as(c_int, vars.link_item_gloves.*) <= 0)
            action = 1;
    }
    // getout:
    if (vars.tiledetect_chest.* & 1 != 0)
        action = 5;
    return action;
}

pub export fn HandleNudging(arg_r0: i8) callconv(.c) void {
    var p: u8 = undefined;
    var o: u8 = undefined;

    if ((vars.link_last_direction_moved_towards.* & 2) == 0) {
        p = if (vars.link_last_direction_moved_towards.* & 1 != 0) 4 else 0;
        o = if (vars.R14.* & 4 != 0) 0 else 2;
    } else {
        p = if (vars.link_last_direction_moved_towards.* & 1 != 0) 12 else 8;
        o = if (vars.R14.* & 4 != 0) 0 else 2;
    }
    o = (o +% p) >> 1;

    vars.tiledetect_pit_tile.* = 0;
    tile_detect.TileDetect_ResetState();

    const y0 = (vars.link_y_coord.* +%
        @as(u16, @bitCast(@as(i16, tables.kLink_Move_Helper6_tab0[o])))) &
        vars.tilemap_location_calc_mask.*;
    const x0 = ((vars.link_x_coord.* +%
        @as(u16, @bitCast(@as(i16, tables.kLink_Move_Helper6_tab1[o])))) &
        vars.tilemap_location_calc_mask.*) >> 3;

    const y1 = (vars.link_y_coord.* +%
        @as(u16, @bitCast(@as(i16, tables.kLink_Move_Helper6_tab2[o])))) &
        vars.tilemap_location_calc_mask.*;
    const x1 = ((vars.link_x_coord.* +%
        @as(u16, @bitCast(@as(i16, tables.kLink_Move_Helper6_tab3[o])))) &
        vars.tilemap_location_calc_mask.*) >> 3;

    tile_detect.TileDetection_Execute(x0, y0, 1);
    tile_detect.TileDetection_Execute(x1, y1, 2);

    if ((vars.R14.* | vars.detection_of_ledge_tiles_horiz_uphoriz.*) & 3 != 0 or
        (vars.tiledetect_vertical_ledge.* | vars.detection_of_unknown_tile_types.*) & 0x33 != 0)
    {
        if (vars.link_last_direction_moved_towards.* & 2 != 0) {
            vars.link_y_coord.* -%= @bitCast(@as(i16, arg_r0));
        } else {
            vars.link_x_coord.* -%= @bitCast(@as(i16, arg_r0));
        }
    }
}

pub export fn TileBehavior_HandleItemAndExecute(x: u16, y: u16) callconv(.c) void {
    const tile = misc.HandleItemTileAction_Overworld(x, y);
    tile_detect.TileDetect_ExecuteInner(tile, 0, 1, false);
}

pub export fn PushBlock_GetTargetTileFlag(x: u16, y: u16) callconv(.c) u8 {
    const base: usize = (@as(usize, y & ~@as(u16, 7)) * 8) + (x & 0x3f) +
        (if (vars.link_is_on_lower_level.* != 0) @as(usize, 0x1000) else 0);
    return vars.dung_bg2_attr_table[base];
}

pub export fn FlagMovingIntoSlopes_Y() callconv(.c) void {
    var y: i8 = @intCast(vars.tiledetect_which_y_pos[0] & 7);
    const o: u8 = @as(u8, @truncate(vars.tiledetect_diag_state.* *% 4)) +%
        @as(u8, @truncate((vars.link_x_coord.* -%
            @intFromBool((vars.R12.* & 4) != 0)) & 7));

    if (vars.tiledetect_diagonal_tile.* & 5 != 0) {
        var ym: i32 = @intCast(vars.tiledetect_which_y_pos[0] & 7);

        if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0) {
            if (vars.tiledetect_diag_state.* & 2 != 0) {
                ym = -ym;
            } else {
                ym = @as(i32, tables.kAvoidJudder1[o]) - (8 - ym);
            }
        } else {
            // This code is bad because it could cause the player
            // to move up to 15 pixels, causing an array out bounds read.
            // Not sure how it works, but changed it to look more like the X version.
            if (vars.tiledetect_diag_state.* & 2 == 0) {
                ym = 8 - ym; // 0 to 8
            } else {
                ym += 8; // 8 to 15
            }
            // -15 to 7
            ym = @as(i32, tables.kAvoidJudder1[o]) - ym;
        }

        if (vars.link_y_vel.* == 0)
            return;
        var ym8: i8 = @truncate(ym);
        if (sign8(vars.link_y_vel.*))
            ym8 = -%ym8;
        y = ym8;
    } else { // else_1
        y = @truncate(@as(i32, tables.kAvoidJudder1[o]) - @as(i32, y));
    } // endif_1

    if (sign8(vars.link_y_vel.*)) {
        if (y <= 0)
            return;
        vars.link_y_coord.* +%= @bitCast(@as(i16, y));
        vars.link_moving_against_diag_tile.* = 8;
    } else {
        if (y >= 0)
            return;
        vars.link_y_coord.* +%= @bitCast(@as(i16, y));
        vars.link_moving_against_diag_tile.* = 4;
    }
    vars.link_moving_against_diag_tile.* |= if (vars.R12.* & 4 != 0) 0x10 + 2 else 0x10 + 1;
}

pub export fn FlagMovingIntoSlopes_X() callconv(.c) void {
    var x: i8 = @intCast((vars.link_x_coord.* -%
        @intFromBool(vars.tiledetect_diag_state.* == 6)) & 7);
    const o: u8 = @as(u8, @truncate(vars.tiledetect_diag_state.* *% 4)) +%
        @as(u8, @truncate(vars.tiledetect_which_y_pos[
            if (vars.R12.* & 4 != 0) @as(usize, 1) else 0
        ] & 7));

    if (vars.tiledetect_diagonal_tile.* & 5 != 0) {
        var xm: i32 = @intCast(vars.link_x_coord.* & 7);

        if (vars.tiledetect_diag_state.* != 4 and vars.tiledetect_diag_state.* != 6) {
            xm = -xm;
        } else {
            xm = @as(i32, tables.kAvoidJudder1[o]) - (8 - xm);
        } // endif_5
        if (vars.link_x_vel.* == 0)
            return;
        var xm8: i8 = @truncate(xm);
        if (sign8(vars.link_x_vel.*))
            xm8 = -%xm8;
        x = xm8;
    } else { // else_1
        x = @truncate(@as(i32, tables.kAvoidJudder1[o]) - @as(i32, x));
    } // endif_1

    if (sign8(vars.link_x_vel.*)) {
        if (x <= 0)
            return;
        vars.link_x_coord.* +%= @bitCast(@as(i16, x));
        vars.link_moving_against_diag_tile.* = 2;
    } else {
        if (x >= 0)
            return;
        vars.link_x_coord.* +%= @bitCast(@as(i16, x));
        vars.link_moving_against_diag_tile.* = 1;
    }
    vars.link_moving_against_diag_tile.* |=
        if (vars.tiledetect_diag_state.* & 2 != 0) 0x20 + 8 else 0x20 + 4;
}

pub export fn Link_HandleRecoiling() callconv(.c) void {
    vars.link_direction.* = 0;
    if (vars.link_actual_vel_y.* != 0) {
        vars.link_direction.* |= if (sign8(vars.link_actual_vel_y.*)) 8 else 4;
        vars.link_direction_last.* = vars.link_direction.*;
        Player_HandleIncapacitated_Inner2();
    }
    if (vars.link_actual_vel_x.* != 0) {
        vars.link_direction.* |= if (sign8(vars.link_actual_vel_x.*)) 2 else 1;
        vars.link_direction_last.* = vars.link_direction.*;
    }
    Player_HandleIncapacitated_Inner2();
}

pub export fn Player_HandleIncapacitated_Inner2() callconv(.c) void {
    if ((vars.link_moving_against_diag_tile.* & 0xc) != 0 and
        (vars.link_moving_against_diag_tile.* & 3) != 0 and
        vars.link_player_handler_state.* == 2)
    {
        vars.link_actual_vel_x.* = 0 -% vars.link_actual_vel_x.*;
        vars.link_actual_vel_y.* = 0 -% vars.link_actual_vel_y.*;
    }
    if (vars.is_standing_in_doorway.* == 1) {
        vars.link_direction_last.* &= 0xc;
        vars.link_direction.* &= 0xc;
        vars.link_actual_vel_x.* = 0;
    } else if (vars.is_standing_in_doorway.* == 2) {
        vars.link_direction_last.* &= 3;
        vars.link_direction.* &= 3;
        vars.link_actual_vel_y.* = 0;
    }
}

pub export fn Link_HandleVelocity() callconv(.c) void {
    if ((vars.submodule_index.* == 2 and vars.main_module_index.* == 14) or
        vars.link_prevent_from_moving.* != 0)
    {
        vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
        vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
        vars.link_x_coord_safe_return_lo.* = @truncate(vars.link_x_coord.*);
        vars.link_x_coord_safe_return_hi.* = @truncate(vars.link_x_coord.* >> 8);
        Link_HandleVelocityAndSandDrag(vars.link_x_coord.*, vars.link_y_coord.*);
        return;
    }

    if (vars.link_player_handler_state.* == kPlayerState_Swimming) {
        HandleSwimStrokeAndSubpixels();
        return;
    }
    var r0: u8 = undefined;

    if (vars.link_flag_moving.* != 0) {
        if (vars.link_is_running.* == 0) {
            HandleSwimStrokeAndSubpixels();
            return;
        }
        r0 = 24;
    } else {
        if (vars.link_is_running.* != 0) {
            vars.link_speed_modifier.* = 0;
            std.debug.assert(vars.link_dash_ctr.* >= 32);
        }

        if ((vars.byte_7E0316.* | vars.byte_7E0317.*) == 0xf)
            return;

        r0 = vars.link_speed_setting.*;
        if (vars.draw_water_ripples_or_grass.* != 0) {
            r0 = if (vars.link_speed_setting.* == 16)
                22
            else if (vars.link_speed_setting.* == 12) 14 else 12;
        }
    } // endif_4

    vars.link_actual_vel_x.* = 0;
    vars.link_actual_vel_y.* = 0;
    vars.link_y_page_movement_delta.* = 0;
    vars.link_x_page_movement_delta.* = 0;

    r0 +%= @intFromBool((vars.link_direction.* & 0xC) != 0 and (vars.link_direction.* & 3) != 0);

    if (vars.player_near_pit_state.* != 0) {
        if (vars.player_near_pit_state.* == 3)
            vars.link_speed_modifier.* = if (vars.link_speed_modifier.* < 48)
                vars.link_speed_modifier.* +% 8
            else
                32;
    } else {
        if (vars.link_speed_modifier.* != 0) {
            r0 = if (vars.submodule_index.* == 8 or vars.submodule_index.* == 16) 10 else 2;
            if (vars.link_speed_modifier.* != 1) {
                if (vars.link_speed_modifier.* < 16) {
                    vars.link_speed_modifier.* +%= 1;
                    r0 = 26; // kSpeedMod[26] is 0
                } else {
                    vars.link_speed_modifier.* = 0;
                    vars.link_speed_setting.* = 0;
                }
            }
        }
    } // endif_7

    const kSpeedMod = [27]u8{
        24, 16, 10, 24, 16, 8, 8, 4, 12, 16, 9, 25, 20, 13,
        16, 8, 64, 42, 16, 8, 4, 2, 48, 24, 32, 21, 0,
    };

    const vel = vars.link_speed_modifier.* +% kSpeedMod[r0];
    if (vars.link_direction.* & 3 != 0)
        vars.link_actual_vel_x.* = if (vars.link_direction.* & 2 != 0) 0 -% vel else vel;
    if (vars.link_direction.* & 0xC != 0)
        vars.link_actual_vel_y.* = if (vars.link_direction.* & 8 != 0) 0 -% vel else vel;

    vars.link_actual_vel_z.* = 0xff;
    vars.link_z_coord.* = 0xffff;
    vars.link_subpixel_z.* = 0;
    Link_MovePosition();
}

pub export fn Link_MovePosition() callconv(.c) void {
    const x = vars.link_x_coord.*;
    const y = vars.link_y_coord.*;
    vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
    vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
    vars.link_x_coord_safe_return_lo.* = @truncate(vars.link_x_coord.*);
    vars.link_x_coord_safe_return_hi.* = @truncate(vars.link_x_coord.* >> 8);

    if (vars.link_player_handler_state.* != 10 and vars.player_on_somaria_platform.* == 2) {
        Link_HandleVelocityAndSandDrag(x, y);
        return;
    }

    var tmp: u32 = undefined;
    tmp = @bitCast(@as(i32, vars.link_subpixel_x.*) +
        @as(i32, @as(i8, @bitCast(vars.link_actual_vel_x.*))) * 16 +
        @as(i32, vars.link_x_coord.*) * 256);
    vars.link_subpixel_x.* = @truncate(tmp);
    vars.link_x_coord.* = @truncate(tmp >> 8);

    tmp = @bitCast(@as(i32, vars.link_subpixel_y.*) +
        @as(i32, @as(i8, @bitCast(vars.link_actual_vel_y.*))) * 16 +
        @as(i32, vars.link_y_coord.*) * 256);
    vars.link_subpixel_y.* = @truncate(tmp);
    vars.link_y_coord.* = @truncate(tmp >> 8);

    if (vars.link_auxiliary_state.* != 0) {
        tmp = @bitCast(@as(i32, vars.link_subpixel_z.*) +
            @as(i32, @as(i8, @bitCast(vars.link_actual_vel_z.*))) * 16 +
            @as(i32, vars.link_z_coord.*) * 256);
        vars.link_subpixel_z.* = @truncate(tmp);
        vars.link_z_coord.* = @truncate(tmp >> 8);
    }

    Link_HandleMovingFloor();
    Link_ApplyConveyor();
    Link_HandleVelocityAndSandDrag(x, y);
}

pub export fn Link_HandleVelocityAndSandDrag(x: u16, y: u16) callconv(.c) void {
    vars.link_y_coord.* +%= vars.drag_player_y.*;
    vars.link_x_coord.* +%= vars.drag_player_x.*;
    vars.link_y_vel.* = @truncate(vars.link_y_coord.* -% y);
    vars.link_x_vel.* = @truncate(vars.link_x_coord.* -% x);
}

pub export fn HandleSwimStrokeAndSubpixels() callconv(.c) void {
    vars.link_actual_vel_x.* = 0;
    vars.link_actual_vel_y.* = 0;

    const kSwimmingTab4 = [12]i8{ 8, -12, -8, -16, 4, -6, -12, -6, 10, -16, -12, -6 };
    const kSwimmingTab5 = [2]u8{ ~@as(u8, 0xc), ~@as(u8, 3) };
    const kSwimmingTab6 = [4]u8{ 8, 4, 2, 1 };
    var S: [2]u16 = undefined;
    var i: isize = 1;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        vars.swimcoll_var3[u] -%= 1;
        if (@as(i16, @bitCast(vars.swimcoll_var3[u])) < 0) {
            vars.swimcoll_var3[u] = 0;
            vars.swimcoll_var5[u] = 1;
        }
        var t = vars.swimcoll_var5[u];
        if (vars.link_flag_moving.* != 0)
            t +%= @as(u16, vars.link_flag_moving.*) *% 4;

        const sum_i: i32 = @as(i32, vars.swimcoll_var7[u]) + kSwimmingTab4[t];
        var sum: u16 = @truncate(@as(u32, @bitCast(sum_i)));
        if (@as(i16, @bitCast(sum)) <= 0) {
            vars.link_direction.* &= kSwimmingTab5[u];
            vars.link_direction_last.* = vars.link_direction.*;
            // link_actual_vel_y = link_y_page_movement_delta; // WTF bug?!
            if (vars.swimcoll_var5[u] == 2) {
                vars.swimcoll_var5[u] = 0;
                vars.swimcoll_var9[u] = 240;
                vars.swimcoll_var7[u] = 2;
            } else {
                vars.swimcoll_var5[u] = 0;
                vars.swimcoll_var9[u] = 0;
                vars.swimcoll_var7[u] = 0;
            }
        } else {
            vars.link_direction.* |= kSwimmingTab6[vars.swimcoll_var11[u] + u * 2];
            if (sum >= vars.swimcoll_var9[u])
                sum = vars.swimcoll_var9[u];
            vars.swimcoll_var7[u] = sum;
        }
        S[u] = vars.swimcoll_var7[u];
        if ((vars.link_num_orthogonal_directions.* | vars.link_moving_against_diag_tile.*) != 0)
            S[u] -%= S[u] >> 2;
        if (vars.swimcoll_var11[u] == 0)
            S[u] = 0 -% S[u];
    }

    Player_SomethingWithVelocity_TiredOrSwim(S[1], S[0]);
}

pub export fn Player_SomethingWithVelocity_TiredOrSwim(xvel: u16, yvel: u16) callconv(.c) void {
    const org_x = vars.link_x_coord.*;
    const org_y = vars.link_y_coord.*;
    vars.link_y_coord_safe_return_lo.* = @truncate(vars.link_y_coord.*);
    vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
    vars.link_x_coord_safe_return_lo.* = @truncate(vars.link_x_coord.*);
    vars.link_x_coord_safe_return_hi.* = @truncate(vars.link_x_coord.* >> 8);

    var u: u8 = undefined;
    var tmp: u32 = undefined;

    tmp = @bitCast(@as(i32, vars.link_subpixel_x.*) +
        @as(i32, @as(i16, @bitCast(xvel))) + @as(i32, vars.link_x_coord.*) * 256);
    vars.link_subpixel_x.* = @truncate(tmp);
    vars.link_x_coord.* = @truncate(tmp >> 8);

    u = @truncate(xvel >> 8);
    vars.link_actual_vel_x.* = ((if (sign8(u)) 0 -% u else u) << 4) |
        (@as(u8, @truncate(xvel)) >> 4);

    tmp = @bitCast(@as(i32, vars.link_subpixel_y.*) +
        @as(i32, @as(i16, @bitCast(yvel))) + @as(i32, vars.link_y_coord.*) * 256);
    vars.link_subpixel_y.* = @truncate(tmp);
    vars.link_y_coord.* = @truncate(tmp >> 8);

    u = @truncate(yvel >> 8);
    vars.link_actual_vel_y.* = ((if (sign8(u)) 0 -% u else u) << 4) |
        (@as(u8, @truncate(yvel)) >> 4);

    if (vars.dung_hdr_collision.* == 4)
        Link_ApplyMovingFloorVelocity();
    vars.link_x_page_movement_delta.* = 0;
    vars.link_y_page_movement_delta.* = 0;
    Link_HandleVelocityAndSandDrag(org_x, org_y);
}

pub export fn Link_HandleMovingFloor() callconv(.c) void {
    if (vars.dung_hdr_collision.* == 0)
        return;
    const zlo = loPtr(vars.link_z_coord).*;
    if (zlo != 0 and zlo != 255)
        return;
    if ((vars.byte_7E0322.* & 3) != 3)
        return;
    if (vars.link_player_handler_state.* == 19) // hookshot
        return;

    if (vars.dung_floor_y_vel.* != 0)
        vars.link_direction.* |= if (sign8(@truncate(vars.dung_floor_y_vel.*))) 8 else 4;

    if (vars.dung_floor_x_vel.* != 0)
        vars.link_direction.* |= if (sign8(@truncate(vars.dung_floor_x_vel.*))) 2 else 1;

    Link_ApplyMovingFloorVelocity();
}

pub export fn Link_ApplyMovingFloorVelocity() callconv(.c) void {
    vars.link_num_orthogonal_directions.* = 0;
    vars.link_y_coord.* +%= vars.dung_floor_y_vel.*;
    vars.link_x_coord.* +%= vars.dung_floor_x_vel.*;
}

pub export fn Link_ApplyConveyor() callconv(.c) void {
    const kMovePosDirFlag = [4]u8{ 8, 4, 2, 1 };
    const kMovingBeltY = [4]i8{ -8, 8, 0, 0 };
    const kMovingBeltX = [4]i8{ 0, 0, -8, 8 };

    if (vars.link_on_conveyor_belt.* == 0)
        return;
    const zlo = loPtr(vars.link_z_coord).*;
    if (zlo != 0 and zlo != 0xff)
        return;
    if (vars.link_grabbing_wall.* & 1 != 0 or
        vars.link_player_handler_state.* == kPlayerState_Hookshot or
        vars.link_auxiliary_state.* != 0)
        return;

    const j: usize = vars.link_on_conveyor_belt.* - 1;
    if (vars.link_is_running.* != 0 and vars.link_dash_ctr.* == 32 and
        (vars.link_direction.* & kMovePosDirFlag[j]) != 0)
        return;

    vars.link_num_orthogonal_directions.* = 0;
    vars.link_direction.* |= kMovePosDirFlag[j];

    var t: u32 = (@as(u32, vars.link_y_coord.*) << 8) | vars.dung_some_subpixel[0];
    t = @bitCast(@as(i32, @bitCast(t)) + (@as(i32, kMovingBeltY[j]) << 4));
    vars.dung_some_subpixel[0] = @truncate(t);
    vars.link_y_coord.* = @truncate(t >> 8);

    t = (@as(u32, vars.link_x_coord.*) << 8) | vars.dung_some_subpixel[1];
    t = @bitCast(@as(i32, @bitCast(t)) + (@as(i32, kMovingBeltX[j]) << 4));
    vars.dung_some_subpixel[1] = @truncate(t);
    vars.link_x_coord.* = @truncate(t >> 8);
}

pub export fn Link_HandleMovingAnimation_FullLongEntry() callconv(.c) void {
    if (vars.link_player_handler_state.* == 4) {
        Link_HandleMovingAnimationSwimming();
        return;
    }

    const kTab = [4]u8{ 8, 4, 2, 1 };

    // `goto bail` skips straight to the trailing call; `goto not_diag` enters
    // the else-arm's last statement.
    bail: {
        var r0 = vars.link_direction_last.*;
        if (r0 == 0)
            return;
        if (vars.link_flag_moving.* != 0)
            r0 = vars.link_some_direction_bits.*;
        if (vars.link_cant_change_direction.* != 0)
            break :bail;

        var y: u8 = undefined;
        var have_y = false;
        if (vars.link_num_orthogonal_directions.* != 0) {
            if (vars.is_standing_in_doorway.* != 0) {
                y = (vars.is_standing_in_doorway.* *% 2) & ~@as(u8, 3);
                have_y = true;
            } else {
                if (r0 & kTab[vars.link_direction_facing.* >> 1] != 0)
                    break :bail;
            }
        }
        if (!have_y) {
            // not_diag:
            y = if (r0 & 0xc != 0) 0 else 4;
        }

        if (y != 4) {
            y +%= if (r0 & 4 != 0) 2 else 0;
        } else {
            y +%= if (r0 & 1 != 0) 2 else 0;
        }
        vars.link_direction_facing.* = y;
    }
    // bail:
    Link_HandleMovingAnimation_StartWithDash();
}

pub export fn Link_HandleMovingAnimation_StartWithDash() callconv(.c) void {
    if (vars.link_is_running.* != 0) {
        Link_HandleMovingAnimation_Dash();
        return;
    }

    var x = vars.link_direction_facing.* >> 1;
    if (vars.link_speed_setting.* == 6) {
        x +%= 4;
    } else if (vars.link_flag_moving.* != 0) {
        if (vars.joypad1H_last.* & kJoypadH_AnyDir == 0) {
            vars.link_animation_steps.* = 0;
            return;
        }
        x +%= 4;
    }

    // bugfix: tempbunny animation steps are wrong due to missing check
    if (vars.link_player_handler_state.* == 23 or
        ((features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0 and
            vars.link_player_handler_state.* == 28))
    { // bunny states
        if (vars.link_animation_steps.* < 4 and vars.player_on_somaria_platform.* != 2) {
            vars.link_counter_var1.* +%= 1;
            if (vars.link_counter_var1.* >= kAnimDelayByDir[x]) {
                vars.link_counter_var1.* = 0;
                vars.link_animation_steps.* +%= 1;
                if (vars.link_animation_steps.* == 4)
                    vars.link_animation_steps.* = 0;
            }
        } else {
            vars.link_animation_steps.* = 0;
        }
        return;
    }

    if (vars.submodule_index.* == 18 or vars.submodule_index.* == 19) {
        x = 12;
    } else if (vars.submodule_index.* != kPlayerState_JumpOffLedgeDiag and
        (vars.link_state_bits.* & 0x80) == 0)
    {
        if (vars.bitmask_of_dragstate.* & 0x8d != 0) {
            x = 12;
        } else if (vars.draw_water_ripples_or_grass.* == 0 and vars.button_b_frames.* == 0) {
            // else_6
            x = vars.link_animation_steps.*;
            if (vars.link_speed_setting.* == 6)
                x +%= 8;
            if (vars.link_flag_moving.* != 0)
                x +%= 8;
            if (vars.player_on_somaria_platform.* == 2)
                return;
            vars.link_counter_var1.* +%= 1;
            if (vars.link_counter_var1.* >= kAnimDelayByStep[x]) {
                vars.link_counter_var1.* = 0;
                vars.link_animation_steps.* +%= 1;
                if (vars.link_animation_steps.* == 9)
                    vars.link_animation_steps.* = 1;
            }
            return;
        }
    }
    // endif_4

    if (vars.link_animation_steps.* < 6 and vars.player_on_somaria_platform.* != 2) {
        vars.link_counter_var1.* +%= 1;
        if (vars.link_counter_var1.* >= kAnimDelayByDir[x]) {
            vars.link_counter_var1.* = 0;
            vars.link_animation_steps.* +%= 1;
            if (vars.link_animation_steps.* == 6)
                vars.link_animation_steps.* = 0;
        }
    } else {
        vars.link_animation_steps.* = 0;
    }
}

pub export fn Link_HandleMovingAnimationSwimming() callconv(.c) void {
    const kTab = [4]u8{ 8, 4, 2, 1 };
    if (vars.link_some_direction_bits.* == 0 or vars.link_cant_change_direction.* != 0)
        return;
    var y: u8 = undefined;

    if (vars.link_num_orthogonal_directions.* != 0) {
        if (vars.is_standing_in_doorway.* != 0) {
            y = (vars.is_standing_in_doorway.* *% 2) & ~@as(u8, 3);
        } else {
            if (vars.link_some_direction_bits.* & kTab[vars.link_direction_facing.* >> 1] != 0)
                return;
            y = if (vars.link_some_direction_bits.* & 0xC != 0) 0 else 4;
        }
    } else {
        y = if (vars.link_some_direction_bits.* & 0xC != 0) 0 else 4;
    }
    if (y != 4) {
        y +%= if (vars.link_some_direction_bits.* & 4 != 0) 2 else 0;
    } else {
        y +%= if (vars.link_some_direction_bits.* & 1 != 0) 2 else 0;
    }
    vars.link_direction_facing.* = y;
}

pub export fn Link_HandleMovingAnimation_Dash() callconv(.c) void {
    const kDashTab3 = [7]u8{ 48, 36, 24, 16, 12, 8, 4 };
    const kDashTab4 = [56]u8{
        3, 3, 5, 3, 3, 3, 5, 3, 2, 2, 4, 2, 2, 2, 4, 2,
        2, 2, 3, 2, 2, 2, 3, 2, 1, 1, 2, 1, 1, 1, 2, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0, 1, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
    };
    const kDashTab5 = [7]u8{ 1, 2, 2, 2, 2, 2, 2 };

    var t: usize = 6;
    while (vars.link_countdown_for_dash.* >= kDashTab3[t] and t != 0)
        t -= 1;

    if (vars.button_b_frames.* < 9 and vars.draw_water_ripples_or_grass.* == 0) {
        vars.link_counter_var1.* +%= 1;
        if (vars.link_counter_var1.* >= kDashTab4[t * 8]) {
            vars.link_counter_var1.* = 0;
            vars.link_animation_steps.* +%= 1;
            if (vars.link_animation_steps.* == 9)
                vars.link_animation_steps.* = 1;
        }
    } else {
        vars.link_counter_var1.* +%= 1;
        if (vars.link_counter_var1.* >= kDashTab5[t]) {
            vars.link_counter_var1.* = 0;
            vars.link_animation_steps.* +%= 1;
            if (vars.link_animation_steps.* >= 6)
                vars.link_animation_steps.* = 0;
        }
    }
}

pub export fn HandleIndoorCameraAndDoors() callconv(.c) void {
    if (vars.player_is_indoors.* != 0) {
        if (vars.is_standing_in_doorway.* != 0) {
            HandleDoorTransitions();
        } else {
            ApplyLinksMovementToCamera();
        }
    }
}

pub export fn HandleDoorTransitions() callconv(.c) void {
    var t: u16 = undefined;

    vars.link_x_page_movement_delta.* = 0;
    vars.link_y_page_movement_delta.* = 0;

    // Using a potion might have changed us into a different module, and the routines
    // below just increment the submodule value, causing all kinds of havoc.
    // There's an added return to catch the same behavior a bit up, but this one catches
    // more cases, at the expense of link already having done his movement, so by
    // returning here we might miss handling the door causing other kinds of issues.
    if ((features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0 and
        !(vars.main_module_index.* == 7 and vars.submodule_index.* == 0))
        return;

    if (vars.link_direction_last.* & 0xC != 0 and vars.is_standing_in_doorway.* == 1) {
        if (vars.link_direction_last.* & 4 != 0) {
            t = vars.link_y_coord.* +% 28;
            if ((t & 0xfc) == 0)
                vars.link_y_page_movement_delta.* =
                    @truncate((t >> 8) -% vars.link_y_coord_safe_return_hi.*);
        } else {
            t = vars.link_y_coord.* -% 18;
            vars.link_y_page_movement_delta.* =
                @truncate((t >> 8) -% vars.link_y_coord_safe_return_hi.*);
        }
    }

    if (vars.link_direction_last.* & 3 != 0 and vars.is_standing_in_doorway.* == 2) {
        if (vars.link_direction_last.* & 1 != 0) {
            t = vars.link_x_coord.* +% 21;
            if ((t & 0xfc) == 0)
                vars.link_x_page_movement_delta.* =
                    @truncate((t >> 8) -% vars.link_x_coord_safe_return_hi.*);
        } else {
            t = vars.link_x_coord.* -% 8;
            vars.link_x_page_movement_delta.* =
                @truncate((t >> 8) -% vars.link_x_coord_safe_return_hi.*);
        }
    }

    if (vars.link_x_page_movement_delta.* != 0) {
        vars.some_animation_timer.* = 0;
        vars.link_state_bits.* = 0;
        vars.link_picking_throw_state.* = 0;
        vars.link_grabbing_wall.* = 0;
        if (sign8(vars.link_x_page_movement_delta.*)) {
            Dung_StartInterRoomTrans_Left_Plus();
        } else {
            HandleEdgeTransitionMovementEast_RightBy8();
        }
    } else if (vars.link_y_page_movement_delta.* != 0) {
        vars.some_animation_timer.* = 0;
        vars.link_state_bits.* = 0;
        vars.link_picking_throw_state.* = 0;
        vars.link_grabbing_wall.* = 0;
        if (sign8(vars.link_y_page_movement_delta.*)) {
            Dungeon_StartInterRoomTrans_Up();
        } else {
            HandleEdgeTransitionMovementSouth_DownBy16();
        }
    }
}

pub export fn ApplyLinksMovementToCamera() callconv(.c) void {
    // Sometimes, when using spin attack, this routine will end up getting
    // called twice in the same frame, which messes up things.
    g_ApplyLinksMovementToCamera_called = true;

    vars.link_y_page_movement_delta.* =
        @truncate((vars.link_y_coord.* >> 8) -% vars.link_y_coord_safe_return_hi.*);
    vars.link_x_page_movement_delta.* =
        @truncate((vars.link_x_coord.* >> 8) -% vars.link_x_coord_safe_return_hi.*);

    if (vars.link_x_page_movement_delta.* != 0) {
        if (sign8(vars.link_x_page_movement_delta.*)) {
            AdjustQuadrantAndCamera_left();
        } else {
            AdjustQuadrantAndCamera_right();
        }
    }

    if (vars.link_y_page_movement_delta.* != 0) {
        if (sign8(vars.link_y_page_movement_delta.*)) {
            AdjustQuadrantAndCamera_up();
        } else {
            AdjustQuadrantAndCamera_down();
        }
    }
}

pub export fn FindFreeMovingBlockSlot(x: u8) callconv(.c) u8 {
    if (vars.index_of_changable_dungeon_objs[1] == 0) {
        vars.index_of_changable_dungeon_objs[1] = x +% 1;
        return 1;
    }
    if (vars.index_of_changable_dungeon_objs[0] == 0) {
        vars.index_of_changable_dungeon_objs[0] = x +% 1;
        return 0;
    }
    return 0xff;
}

pub export fn InitializePushBlock(r14: u8, idx: u8) callconv(.c) bool {
    const pos = vars.dung_object_tilemap_pos[idx >> 1];
    var x: u16 = (pos & 0x007e) << 2;
    var y: u16 = (pos & 0x1f80) >> 4;

    x +%= (vars.dung_loade_bgoffs_h_copy.* & 0xff00);
    y +%= (vars.dung_loade_bgoffs_v_copy.* & 0xff00);

    vars.pushedblocks_x_lo[r14] = @truncate(x);
    vars.pushedblocks_x_hi[r14] = @truncate(x >> 8);
    vars.pushedblocks_y_lo[r14] = @truncate(y);
    vars.pushedblocks_y_hi[r14] = @truncate(y >> 8);
    vars.pushedblocks_target[r14] = 0;
    vars.pushedblocks_subpixel[r14] = 0;

    if (vars.dung_hdr_tag[0] != 38 and vars.dung_replacement_tile_state[idx >> 1] == 0) {
        if (!PushBlock_AttemptToPushTheBlock(0, x, y)) {
            _ = misc.Ancilla_Sfx2_Near(0x22);
            vars.dung_replacement_tile_state[idx >> 1] = 1;
            return false;
        }
    }

    vars.index_of_changable_dungeon_objs[r14] = 0;
    return true;
}

pub export fn Sprite_Dungeon_DrawSinglePushBlock(j_in: c_int) callconv(.c) void {
    const kPushedBlock_Tab1 = [9]u8{ 0, 1, 2, 3, 4, 0, 0, 0, 0 };
    const kPushedblock_Char = [4]u8{ 0xc, 0xc, 0xc, 0xff };
    const j: usize = @intCast(j_in >> 1);
    _ = sprite.Oam_AllocateFromRegionB(4);
    const oam = GetOamCurPtr();
    var y: c_int = @as(c_int, vars.pushedblocks_y_lo[j]) |
        (@as(c_int, vars.pushedblocks_y_hi[j]) << 8);
    var x: c_int = @as(c_int, vars.pushedblocks_x_lo[j]) |
        (@as(c_int, vars.pushedblocks_x_hi[j]) << 8);
    y -= @as(c_int, vars.BG2VOFS_copy2.*) + 1;
    x -= @as(c_int, vars.BG2HOFS_copy2.*);
    const ch = kPushedblock_Char[kPushedBlock_Tab1[vars.pushedblocks_some_index.*]];
    if (ch != 0xff)
        SetOamPlain(oam, @truncate(@as(u32, @bitCast(x))), @truncate(@as(u32, @bitCast(y))), ch, 0x20, 2);
}

pub export fn Link_Initialize() callconv(.c) void {
    vars.link_direction_facing.* = 2;
    vars.link_direction_last.* = 0;
    vars.link_item_in_hand.* = 0;
    vars.link_position_mode.* = 0;
    vars.link_debug_value_1.* = 0;
    vars.link_debug_value_2.* = 0;
    vars.link_var30d.* = 0;
    vars.link_var30e.* = 0;
    vars.some_animation_timer_steps.* = 0;
    vars.link_is_transforming.* = 0;
    vars.bitfield_for_a_button.* = 0;
    vars.button_mask_b_y.* &= ~@as(u8, 0x40);
    vars.link_state_bits.* = 0;
    vars.link_picking_throw_state.* = 0;
    vars.link_grabbing_wall.* = 0;
    Link_ResetSwimmingState();
    vars.link_cant_change_direction.* &= ~@as(u8, 1);
    vars.link_z_coord.* &= 0xff;
    vars.link_auxiliary_state.* = 0;
    vars.link_incapacitated_timer.* = 0;
    vars.countdown_for_blink.* = 0;
    vars.link_electrocute_on_touch.* = 0;
    vars.link_pose_for_item.* = 0;
    vars.link_cape_mode.* = 0;
    Link_ForceUnequipCape_quietly();
    Link_ResetSwordAndItemUsage();
    vars.link_disable_sprite_damage.* = 0;
    vars.player_handler_timer.* = 0;
    vars.link_direction.* &= ~@as(u8, 0xf);
    vars.player_on_somaria_platform.* = 0;
    vars.link_spin_attack_step_counter.* = 0;

    if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0) {
        // If you quit while jumping from a ledge and get hit on a platform you can
        // go under solid layers
        vars.about_to_jump_off_ledge.* = 0;

        // If you use the mirror near a moveable statue you can pull thin air and
        // glitch the camera
        vars.link_is_near_moveable_statue.* = 0;

        // If you use the mirror on a conveyor belt you will retain momentum and clip
        // into the entrance wall
        vars.link_on_conveyor_belt.* = 0;

        // bugfix: you use the mirror on ice, you retain momentum
        vars.link_flag_moving.* = 0;

        // If you quit in the middle of red armos knight stomp the lumberjack tree
        // will fall on its own
        vars.bg1_x_offset.* = 0;
        vars.bg1_y_offset.* = 0;

        // bugfix: if you die in a dungeon as a permabunny and continue, you revert
        // back to link
        if (vars.link_item_moon_pearl.* == 0 and vars.savegame_is_darkworld.* != 0) {
            vars.link_player_handler_state.* = kPlayerState_PermaBunny;
            vars.link_is_bunny.* = 1;
            vars.link_is_bunny_mirror.* = 1;
            load_gfx.LoadGearPalettes_bunny();
        }
    }
}

pub export fn Link_ResetProperties_A() callconv(.c) void {
    vars.link_direction_last.* = 0;
    vars.link_direction.* = 0;
    vars.link_flag_moving.* = 0;
    Link_ResetSwimmingState();
    vars.link_is_transforming.* = 0;
    vars.countdown_for_blink.* = 0;
    vars.ancilla_arr24[0] = 0;
    vars.link_is_bunny.* = 0;
    vars.link_is_bunny_mirror.* = 0;
    loPtr(vars.link_timer_tempbunny).* = 0;
    vars.link_need_for_poof_for_transform.* = 0;
    vars.is_archer_or_shovel_game.* = 0;
    vars.link_need_for_pullforrupees_sprite.* = 0;
    loPtr(vars.bit9_of_xcoord).* = 0;
    vars.link_something_with_hookshot.* = 0;
    vars.link_give_damage.* = 0;
    vars.link_spin_offsets.* = 0;
    vars.tagalong_event_flags.* = 0;
    vars.link_want_make_noise_when_dashed.* = 0;
    loPtr(vars.tiledetect_tile_type).* = 0;
    vars.item_receipt_method.* = 0;
    vars.link_triggered_by_whirlpool_sprite.* = 0;
    Link_ResetProperties_B();
}

pub export fn Link_ResetProperties_B() callconv(.c) void {
    vars.player_on_somaria_platform.* = 0;
    vars.link_spin_attack_step_counter.* = 0;
    vars.fallhole_var1.* = 0;
    vars.flag_is_sprite_to_pick_up_cached.* = 0;
    vars.bitmask_of_dragstate.* = 0;
    vars.link_this_controls_sprite_oam.* = 0;
    vars.player_near_pit_state.* = 0;
    Link_ResetProperties_C();
}

pub export fn Link_ResetProperties_C() callconv(.c) void {
    if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0) {
        // Fix save menu lockout when dying after medallion cast (#126)
        vars.flag_custom_spell_anim_active.* = 0;
    }

    vars.tile_action_index.* = 0;
    vars.state_for_spin_attack.* = 0;
    vars.step_counter_for_spin_attack.* = 0;
    vars.tile_coll_flag.* = 0;
    vars.link_force_hold_sword_up.* = 0;
    vars.link_sword_delay_timer.* = 0;
    vars.tiledetect_misc_tiles.* = 0;
    vars.link_item_in_hand.* = 0;
    vars.link_position_mode.* = 0;
    vars.link_debug_value_1.* = 0;
    vars.link_debug_value_2.* = 0;
    vars.link_var30d.* = 0;
    vars.link_var30e.* = 0;
    vars.some_animation_timer_steps.* = 0;
    vars.bitfield_for_a_button.* = 0;
    vars.button_mask_b_y.* = 0;
    vars.button_b_frames.* = 0;
    vars.link_state_bits.* = 0;
    vars.link_picking_throw_state.* = 0;
    vars.link_grabbing_wall.* = 0;
    vars.link_cant_change_direction.* = 0;
    vars.link_auxiliary_state.* = 0;
    vars.link_incapacitated_timer.* = 0;
    vars.link_electrocute_on_touch.* = 0;
    vars.link_pose_for_item.* = 0;
    vars.link_cape_mode.* = 0;
    Link_ResetSwordAndItemUsage();
    vars.link_disable_sprite_damage.* = 0;
    vars.player_handler_timer.* = 0;
    vars.related_to_hookshot.* = 0;
    vars.flag_is_ancilla_to_pick_up.* = 0;
    vars.flag_is_sprite_to_pick_up.* = 0;
    vars.link_need_for_pullforrupees_sprite.* = 0;
    vars.link_is_near_moveable_statue.* = 0;
}

pub export fn Link_CheckForEdgeScreenTransition() callconv(.c) bool {
    const st = vars.link_player_handler_state.*;
    if (st == 3 or st == 8 or st == 9 or st == 10 or vars.link_incapacitated_timer.* == 0)
        return false;
    vars.link_actual_vel_x.* = 0;
    vars.link_actual_vel_y.* = 0;
    vars.link_recoilmode_timer.* = 3;
    vars.link_x_coord.* = vars.link_x_coord_prev.*;
    vars.link_y_coord.* = vars.link_y_coord_prev.*;
    return true;
}

pub export fn CacheCameraPropertiesIfOutdoors() callconv(.c) void {
    if (vars.player_is_indoors.* == 0)
        CacheCameraProperties();
}

pub export fn SomariaBlock_HandlePlayerInteraction(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    vars.cur_object_index.* = @truncate(@as(u32, @bitCast(k)));
    if (vars.ancilla_G[u] != 0)
        return;

    if (vars.ancilla_H[u] == 0) {
        if (vars.link_auxiliary_state.* != 0 or (vars.link_state_bits.* & 1) != 0 or
            (vars.ancilla_z[u] != 0 and vars.ancilla_z[u] != 0xff) or
            vars.ancilla_K[u] != 0 or vars.ancilla_L[u] != 0)
            return;
        if (vars.joypad1H_last.* & kJoypadH_AnyDir == 0) {
            vars.ancilla_arr3[u] = 0;
            vars.bitmask_of_dragstate.* = 0;
            vars.ancilla_A[u] = 255;
            if (vars.link_is_running.* == 0) {
                vars.link_speed_setting.* = 0;
                return;
            }
        } else if ((vars.joypad1H_last.* & kJoypadH_AnyDir) == vars.ancilla_arr3[u]) {
            if (vars.link_speed_setting.* == 18)
                vars.bitmask_of_dragstate.* |= 0x81;
        } else {
            vars.ancilla_arr3[u] = vars.joypad1H_last.* & kJoypadH_AnyDir;
            vars.link_speed_setting.* = 0;
        }

        var coll_out: CheckPlayerCollOut = undefined;
        if (!Ancilla_CheckLinkCollision(k, 4, &coll_out) or
            vars.ancilla_floor[u] != vars.link_is_on_lower_level.*)
            return;

        if (vars.link_is_running.* == 0 or vars.link_dash_ctr.* == 64) {
            vars.ancilla_x_vel[u] = 0;
            vars.ancilla_y_vel[u] = 0;
            const t = vars.joypad1H_last.* & kJoypadH_AnyDir;
            vars.ancilla_arr3[u] = t;
            if (t & 3 != 0) {
                vars.ancilla_x_vel[u] = if (t & 1 != 0) 16 else @bitCast(@as(i8, -16));
                vars.ancilla_dir[u] = if (t & 1 != 0) 3 else 2;
            } else {
                vars.ancilla_y_vel[u] = if (t & 8 != 0) @bitCast(@as(i8, -16)) else 16;
                vars.ancilla_dir[u] = if (t & 8 != 0) 0 else 1;
            }
            if (vars.link_actual_vel_y.* == 0 or vars.link_actual_vel_x.* == 0) {
                if (!Ancilla_CheckTileCollision_Class2(k)) {
                    Ancilla_MoveY(k);
                    Ancilla_MoveX(k);
                    if ((vars.link_state_bits.* & 0x80) == 0) {
                        vars.ancilla_A[u] +%= 1;
                        if (vars.ancilla_A[u] & 7 == 0)
                            Ancilla_Sfx2_Pan(k, 0x22);
                    }
                }
                vars.bitmask_of_dragstate.* = 0x81;
                vars.link_speed_setting.* = 0x12;
            }
            sprite.Sprite_NullifyHookshotDrag();
            return;
        }
        const kSomarianBlock_Yvel = [4]i8{ -40, 40, 0, 0 };
        const kSomarianBlock_Xvel = [4]i8{ 0, 0, -40, 40 };
        if (vars.flag_is_ancilla_to_pick_up.* == k + 1)
            vars.flag_is_ancilla_to_pick_up.* = 0;
        Link_CancelDash();
        Ancilla_Sfx3_Pan(k, 0x32);
        const j: usize = vars.link_direction_facing.* >> 1;
        vars.ancilla_dir[u] = @truncate(j);
        vars.ancilla_y_vel[u] = @bitCast(kSomarianBlock_Yvel[j]);
        vars.ancilla_x_vel[u] = @bitCast(kSomarianBlock_Xvel[j]);
        vars.ancilla_z_vel[u] = 48;
        vars.ancilla_H[u] = 1;
        vars.ancilla_z[u] = 0;
    }

    vars.ancilla_z_vel[u] -%= 2;
    Ancilla_MoveY(k);
    Ancilla_MoveX(k);
    Ancilla_MoveZ(k);
    if (vars.ancilla_z[u] != 0 and vars.ancilla_z[u] < 252)
        return;

    Ancilla_Sfx2_Pan(k, 0x21);
    vars.ancilla_z[u] = 0;
    const j = vars.ancilla_H[u];
    vars.ancilla_H[u] +%= 1;
    if (j == 3) {
        vars.ancilla_arr4[u] = 0;
        vars.ancilla_H[u] = 0;
    } else {
        const kSomarianBlock_Zvel = [4]i8{ 48, 24, 16, 8 };
        vars.ancilla_z_vel[u] = @bitCast(kSomarianBlock_Zvel[j - 1]);
        vars.ancilla_y_vel[u] = @bitCast(@divTrunc(@as(i8, @bitCast(vars.ancilla_y_vel[u])), 2));
        vars.ancilla_x_vel[u] = @bitCast(@divTrunc(@as(i8, @bitCast(vars.ancilla_x_vel[u])), 2));
    }
}

pub export fn Gravestone_Move(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.submodule_index.* != 0)
        return;
    vars.ancilla_y_vel[u] = @bitCast(@as(i8, -8));
    Ancilla_MoveY(k);

    Gravestone_ActAsBarrier(k);
    const y_target: u16 = (@as(u16, vars.ancilla_B[u]) << 8) | vars.ancilla_A[u];
    const y_cur = Ancilla_GetY(k);

    if (y_cur >= y_target)
        return;

    vars.ancilla_type[u] = 0;
    vars.link_something_with_hookshot.* = 0;
    vars.bitmask_of_dragstate.* &= ~@as(u8, 4);
    // The C indexes the u16 arrays through a byte pointer.
    const dby: [*]u8 = @ptrCast(vars.door_debris_y);
    const dbx: [*]u8 = @ptrCast(vars.door_debris_x);
    loPtr(vars.scratch_0).* = dby[u];
    hiPtr(vars.scratch_0).* = dbx[u];
    vars.big_rock_starting_address.* = vars.scratch_0.*;

    vars.door_open_closed_counter.* = if (vars.big_rock_starting_address.* == 0x532)
        0x48
    else if (vars.big_rock_starting_address.* == 0x488) 0x60 else 0x40;
    overworld.Overworld_DoMapUpdate32x32_B();
}

pub export fn Gravestone_ActAsBarrier(k: c_int) callconv(.c) void {
    const x = Ancilla_GetX(k);
    const y = Ancilla_GetY(k);
    const r4 = y +% 0x18;
    const r6 = x +% 0x20;
    const lx = vars.link_x_coord.* +% 8;
    const ly = vars.link_y_coord.* +% 8;
    if (ly >= y and ly < r4 and lx >= x and lx < r6) {
        const r10 = abs16(ly -% r4);
        vars.link_y_coord.* +%= r10;
        vars.link_y_vel.* +%= @truncate(r10);
        vars.bitmask_of_dragstate.* |= 4;
    }
    if (vars.link_direction_facing.* != 0)
        vars.link_direction_facing.* &= ~@as(u8, 4);
}

pub export fn AncillaAdd_DugUpFlute(a: u8, y: u8) callconv(.c) void {
    const k = Ancilla_AddAncilla(a, y);
    if (k < 0)
        return;
    const u: usize = @intCast(k);
    vars.ancilla_step[u] = 0;
    vars.ancilla_z[u] = 0;
    vars.ancilla_z_vel[u] = 24;
    vars.ancilla_x_vel[u] =
        if (vars.link_direction_facing.* == 4) @bitCast(@as(i8, -8)) else 8;
    load_gfx.DecodeAnimatedSpriteTile_variable(12);
    Ancilla_SetXY(k, 0x490, 0xa8a);
}

pub export fn AncillaAdd_CaneOfByrnaInitSpark(a: u8, y: u8) callconv(.c) void {
    var i: isize = 4;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        if (vars.ancilla_type[u] == 0x31)
            vars.ancilla_type[u] = 0;
    }
    const k = Ancilla_AddAncilla(a, y);
    if (k >= 0) {
        const u: usize = @intCast(k);
        vars.ancilla_item_to_link[u] = 0;
        vars.ancilla_aux_timer[u] = 9;
        vars.link_disable_sprite_damage.* = 1;
        vars.ancilla_arr3[u] = 2;
    }
}

pub export fn AncillaAdd_ShovelDirt(a: u8, y: u8) callconv(.c) void {
    const k = Ancilla_AddAncilla(a, y);
    if (k >= 0) {
        const u: usize = @intCast(k);
        vars.ancilla_item_to_link[u] = 0;
        vars.ancilla_timer[u] = 20;
        Ancilla_SetXY(k, vars.link_x_coord.*, vars.link_y_coord.*);
    }
}

pub export fn AncillaAdd_Hookshot(a: u8, y: u8) callconv(.c) void {
    const kHookshot_Yvel = [4]i8{ -64, 64, 0, 0 };
    const kHookshot_Xvel = [4]i8{ 0, 0, -64, 64 };
    const kHookshot_Yd = [4]i8{ 4, 20, 8, 8 };
    const kHookshot_Xd = [4]i8{ 0, 0, -4, 11 };

    const k = Ancilla_AddAncilla(a, y);
    if (k >= 0) {
        const u: usize = @intCast(k);
        vars.ancilla_aux_timer[u] = 3;
        vars.ancilla_item_to_link[u] = 0;
        vars.ancilla_step[u] = 0;
        vars.ancilla_L[u] = 0;
        vars.related_to_hookshot.* = 0;
        vars.hookshot_effect_index.* = @truncate(u);
        vars.ancilla_K[u] = 0;
        vars.ancilla_G[u] = 255;
        vars.ancilla_arr1[u] = 0;
        vars.ancilla_timer[u] = 0;
        const j: usize = vars.link_direction_facing.* >> 1;
        vars.ancilla_dir[u] = @truncate(j);
        vars.ancilla_x_vel[u] = @bitCast(kHookshot_Xvel[j]);
        vars.ancilla_y_vel[u] = @bitCast(kHookshot_Yvel[j]);
        Ancilla_SetXY(
            k,
            vars.link_x_coord.* +% @as(u16, @bitCast(@as(i16, kHookshot_Xd[j]))),
            vars.link_y_coord.* +% @as(u16, @bitCast(@as(i16, kHookshot_Yd[j]))),
        );
    }
}

pub export fn ResetSomeThingsAfterDeath(a: u8) callconv(.c) void {
    vars.link_is_in_deep_water.* = 0;
    vars.link_speed_setting.* = a;
    vars.link_on_conveyor_belt.* = 0;
    vars.byte_7E0322.* = 0;
    vars.flag_is_link_immobilized.* = 0;
    vars.palette_swap_flag.* = 0;
    vars.player_unk1.* = 0;
    vars.link_give_damage.* = 0;
    vars.link_actual_vel_y.* = 0;
    vars.link_actual_vel_x.* = 0;
    vars.link_actual_vel_z.* = 0;
    loPtr(vars.link_z_coord).* = 0;
    vars.draw_water_ripples_or_grass.* = 0;
    vars.byte_7E0316.* = 0;
    vars.countdown_for_blink.* = 0;
    vars.link_player_handler_state.* = 0;
    vars.link_visibility_status.* = 0;
    _ = Ancilla_TerminateSelectInteractives(0);
    Link_ResetProperties_A();
}

pub export fn SpawnHammerWaterSplash() callconv(.c) void {
    const kItem_Hammer_SpawnWater_X = [4]i8{ 0, 12, -8, 24 };
    const kItem_Hammer_SpawnWater_Y = [4]i8{ 8, 32, 24, 24 };
    if ((vars.submodule_index.* | vars.flag_is_link_immobilized.* | vars.flag_unk1.*) != 0)
        return;
    const i: usize = vars.link_direction_facing.* >> 1;
    const x = vars.link_x_coord.* +%
        @as(u16, @bitCast(@as(i16, kItem_Hammer_SpawnWater_X[i])));
    const y = vars.link_y_coord.* +%
        @as(u16, @bitCast(@as(i16, kItem_Hammer_SpawnWater_Y[i])));
    var tiletype: u8 = undefined;
    if (vars.player_is_indoors.* != 0) {
        var t: usize = if (vars.link_is_on_lower_level.* >= 1) 0x1000 else 0;
        t += (x & 0x1f8) >> 3;
        t += @as(usize, y & 0x1f8) << 3;
        tiletype = vars.dung_bg2_attr_table[t];
    } else {
        tiletype = overworld.Overworld_ReadTileAttribute(x >> 3, y);
    }

    if (tiletype == 8 or tiletype == 9) {
        const j = Sprite_SpawnSmallSplash(0);
        if (j >= 0) {
            const u: usize = @intCast(j);
            sprite.Sprite_SetX(j, x -% 8);
            sprite.Sprite_SetY(j, y -% 16);
            vars.sprite_floor[u] = vars.link_is_on_lower_level.*;
            vars.sprite_z[u] = 0;
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
//
// These stick to functions that touch only work RAM and the generated tables.
// Anything that reaches into ancilla.c / dungeon.c / sprite_main.c would hit a
// panicking stub in the test binary.
// ---------------------------------------------------------------------------

test "FindInByteArray searches backwards and honours the size window" {
    const data = [_]u8{ 3, 1, 4, 1, 5 };
    // Two matches for 1; the backwards scan must report the later one.
    try std.testing.expectEqual(@as(c_int, 3), FindInByteArray(&data, 1, 5));
    try std.testing.expectEqual(@as(c_int, -1), FindInByteArray(&data, 9, 5));
    // A shorter window hides the later match.
    try std.testing.expectEqual(@as(c_int, 1), FindInByteArray(&data, 1, 3));
}

test "swimming tables are re-exported with player.c's values" {
    try std.testing.expectEqualSlices(u8, &.{ 2, 0, 1, 0 }, &kSwimmingTab1);
    try std.testing.expectEqualSlices(u8, &.{ 32, 8 }, &kSwimmingTab2);
}

test "FindFreeMovingBlockSlot fills slot 1, then 0, then reports full" {
    vars.index_of_changable_dungeon_objs[0] = 0;
    vars.index_of_changable_dungeon_objs[1] = 0;
    try std.testing.expectEqual(@as(u8, 1), FindFreeMovingBlockSlot(5));
    try std.testing.expectEqual(@as(u8, 6), vars.index_of_changable_dungeon_objs[1]);
    try std.testing.expectEqual(@as(u8, 0), FindFreeMovingBlockSlot(7));
    try std.testing.expectEqual(@as(u8, 8), vars.index_of_changable_dungeon_objs[0]);
    try std.testing.expectEqual(@as(u8, 0xff), FindFreeMovingBlockSlot(9));
}

test "CheckYButtonPress latches the mask and refuses while incapacitated" {
    vars.button_mask_b_y.* = 0;
    vars.link_incapacitated_timer.* = 0;
    vars.filtered_joypad_H.* = kJoypadH_Y;
    try std.testing.expect(CheckYButtonPress());
    try std.testing.expectEqual(@as(u8, 0x40), vars.button_mask_b_y.* & 0x40);
    // The latched mask blocks a repeat in the same press.
    try std.testing.expect(!CheckYButtonPress());

    vars.button_mask_b_y.* = 0;
    vars.link_incapacitated_timer.* = 5;
    try std.testing.expect(!CheckYButtonPress());
    vars.link_incapacitated_timer.* = 0;
    vars.filtered_joypad_H.* = 0;
}

test "Link_PermissionForSloshSounds gates on direction, state and frame" {
    vars.link_direction.* = 0;
    try std.testing.expect(Link_PermissionForSloshSounds());

    vars.link_direction.* = 1;
    vars.link_player_handler_state.* = 0;
    vars.frame_counter.* = 0x10; // 0x10 & 0xf == 0
    try std.testing.expect(!Link_PermissionForSloshSounds());
    vars.frame_counter.* = 0x11;
    try std.testing.expect(Link_PermissionForSloshSounds());

    // State 17 uses the narrower 0x7 mask.
    vars.link_player_handler_state.* = 17;
    vars.frame_counter.* = 0x08;
    try std.testing.expect(!Link_PermissionForSloshSounds());
    vars.link_player_handler_state.* = 0;
    vars.link_direction.* = 0;
}

test "SnapOnX snaps to the 8px grid in the direction of travel" {
    vars.link_x_coord.* = 0x105; // low three bits = 5
    vars.link_x_vel.* = 1; // moving right: pull back to 0x100
    SnapOnX();
    try std.testing.expectEqual(@as(u16, 0x100), vars.link_x_coord.*);

    vars.link_x_coord.* = 0x105;
    vars.link_x_vel.* = 0xff; // moving left: push on to 0x108
    SnapOnX();
    try std.testing.expectEqual(@as(u16, 0x108), vars.link_x_coord.*);
    vars.link_x_vel.* = 0;
}

test "Refund_Magic clamps at 128 only when the bugfix flag is set" {
    vars.link_magic_consumption.* = 0;
    const cost = tables.kLinkItem_MagicCosts[4 * 3];

    vars.link_magic_power.* = 127;
    features.enhanced_features0.* = features.kFeatures0_MiscBugFixes;
    Refund_Magic(4);
    try std.testing.expectEqual(@as(u8, 128), vars.link_magic_power.*);

    // Without the fix the original overflow behavior is preserved.
    vars.link_magic_power.* = 127;
    features.enhanced_features0.* = 0;
    Refund_Magic(4);
    try std.testing.expectEqual(@as(u8, 127 +% cost), vars.link_magic_power.*);
}

test "the item handlers survive their last animation step" {
    // Every one of these used to read one past the end of a three-entry delay
    // table on the step where player_handler_timer reaches 3, which panics
    // under Zig's bounds checking. Drive each handler straight to that step.
    //
    // button_mask_b_y bit 0x40 means "already mid-animation", so the handlers
    // skip their setup block; link_delay_timer_spin_attack == 0 makes the
    // decrement underflow, which is what advances the timer.
    const handlers = [_]struct { name: []const u8, f: *const fn () callconv(.c) void }{
        .{ .name = "Rod", .f = &LinkItem_Rod },
        .{ .name = "Hammer", .f = &LinkItem_Hammer },
        .{ .name = "Bow", .f = &LinkItem_Bow },
        .{ .name = "CaneOfSomaria", .f = &LinkItem_CaneOfSomaria },
    };
    for (handlers) |h| {
        vars.button_mask_b_y.* = 0x40;
        vars.link_delay_timer_spin_attack.* = 0;
        vars.player_handler_timer.* = 2;
        vars.link_incapacitated_timer.* = 0;

        h.f();

        // Reaching the last step ends the animation and clears the latch.
        try std.testing.expectEqual(@as(u8, 0), vars.player_handler_timer.*);
        try std.testing.expectEqual(@as(u8, 0), vars.link_delay_timer_spin_attack.*);
        try std.testing.expectEqual(@as(u8, 0), vars.button_mask_b_y.* & 0x40);
    }

    // The earlier steps still take their delay from the table.
    vars.button_mask_b_y.* = 0x40;
    vars.link_delay_timer_spin_attack.* = 0;
    vars.player_handler_timer.* = 0;
    LinkItem_Bow();
    try std.testing.expectEqual(@as(u8, 1), vars.player_handler_timer.*);
    try std.testing.expectEqual(tables.kBowDelays[1], vars.link_delay_timer_spin_attack.*);

    vars.button_mask_b_y.* = 0;
    vars.player_handler_timer.* = 0;
    vars.link_delay_timer_spin_attack.* = 0;
}

test "the wall grab survives its last animation step" {
    // The final step bumps link_var30d to 7 and used to index both seven-entry
    // grab tables with it, which panics under Zig's bounds checking. Drive the
    // handler straight to that step.
    //
    // button_mask_b_y non-zero means "already mid-animation", so the A and Down
    // checks are skipped, and some_animation_timer == 0 makes the decrement
    // underflow, which is what advances the step. bitmask_of_dragstate is set
    // so the handler returns through treePullResetToNormal rather than running
    // on into tile detection, which wants a loaded map this test has no use for.
    vars.link_grabbing_wall.* = 1;
    vars.button_mask_b_y.* = 4;
    vars.some_animation_timer.* = 0;
    vars.link_var30d.* = 6;
    vars.bitmask_of_dragstate.* = 1;

    LinkState_TreePull();

    // Reaching the last step ends the grab and resets the animation.
    try std.testing.expectEqual(@as(u8, 0), vars.link_grabbing_wall.*);
    try std.testing.expectEqual(@as(u8, 0), vars.link_var30d.*);
    try std.testing.expectEqual(@as(u8, 2), vars.some_animation_timer.*);
    try std.testing.expectEqual(@as(u8, 0), vars.some_animation_timer_steps.*);

    // The earlier steps cannot be driven from here: they leave through
    // `break :tail`, which runs on into tile detection and wants a loaded map.

    vars.link_grabbing_wall.* = 0;
    vars.button_mask_b_y.* = 0;
    vars.some_animation_timer.* = 0;
    vars.some_animation_timer_steps.* = 0;
    vars.link_var30d.* = 0;
    vars.bitmask_of_dragstate.* = 0;
    vars.link_state_bits.* = 0;
}

test "Link_ResetProperties_C clears item and button state" {
    features.enhanced_features0.* = 0;
    vars.link_item_in_hand.* = 0xff;
    vars.button_b_frames.* = 9;
    vars.link_grabbing_wall.* = 2;
    vars.link_cape_mode.* = 1;
    vars.link_auxiliary_state.* = 3;
    Link_ResetProperties_C();
    try std.testing.expectEqual(@as(u8, 0), vars.link_item_in_hand.*);
    try std.testing.expectEqual(@as(u8, 0), vars.button_b_frames.*);
    try std.testing.expectEqual(@as(u8, 0), vars.link_grabbing_wall.*);
    try std.testing.expectEqual(@as(u8, 0), vars.link_cape_mode.*);
    try std.testing.expectEqual(@as(u8, 0), vars.link_auxiliary_state.*);
}

pub export fn DiggingGameGuy_AttemptPrizeSpawn() callconv(.c) void {
    const kDiggingGameGuy_Xvel = [2]i8{ -16, 16 };
    const kDiggingGameGuy_X = [2]i8{ 0, 19 };
    const kDiggingGameGuy_Items = [4]u8{ 0xdb, 0xda, 0xd9, 0xdf };

    vars.beamos_x_hi[1] +%= 1;
    if (vars.link_y_coord.* >= 0xb18)
        return;
    var j: c_int = misc.GetRandomNumber() & 7;
    var item_to_spawn: u8 = undefined;
    switch (j) {
        0, 1, 2, 3 => item_to_spawn = kDiggingGameGuy_Items[@intCast(j)],
        4 => {
            if (vars.beamos_x_hi[1] < 25 or vars.beamos_x_hi[0] != 0 or
                (misc.GetRandomNumber() & 3) != 0)
                return;
            vars.beamos_x_hi[0] = 0xeb;
            item_to_spawn = 0xeb;
        },
        else => return,
    }
    var info: sprite.SpriteSpawnInfo = undefined;
    j = sprite.Sprite_SpawnDynamically(4, item_to_spawn, &info); // zelda bug: 4 wtf...
    if (j >= 0) {
        const u: usize = @intCast(j);
        const i: usize = @intFromBool(vars.link_direction_facing.* != 4);
        vars.sprite_x_vel[u] = @bitCast(kDiggingGameGuy_Xvel[i]);
        vars.sprite_y_vel[u] = 0;
        vars.sprite_z_vel[u] = 24;
        vars.sprite_stunned[u] = 255;
        vars.sprite_delay_aux4[u] = 48;
        sprite.Sprite_SetX(j, (vars.link_x_coord.* +%
            @as(u16, @bitCast(@as(i16, kDiggingGameGuy_X[i])))) & ~@as(u16, 0xf));
        sprite.Sprite_SetY(j, (vars.link_y_coord.* +% 22) & ~@as(u16, 0xf));
        vars.sprite_floor[u] = 0;
        misc.SpriteSfx_QueueSfx3WithPan(j, 0x30);
    }
}
