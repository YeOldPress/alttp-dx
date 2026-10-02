//! Port of src/sprite.c: the shared sprite engine -- coordinates and movement,
//! OAM allocation and drawing, hitboxes and damage, the carry/throw/stun/death
//! state modules, garnishes, and sprite loading for both overworld and dungeon.
//!
//! The per-sprite AI lives in sprite_main.c, which is still C and calls into
//! most of what this file exports.
const std = @import("std");
const vars = @import("variables.zig");
const tables = @import("sprite_tables.zig");
const config = @import("config.zig");
const features = @import("features.zig");
const misc = @import("misc.zig");
const load_gfx = @import("load_gfx.zig");
const overlord = @import("overlord.zig");
const overworld = @import("overworld.zig");
const tagalong = @import("tagalong.zig");
const tile_detect = @import("tile_detect.zig");
const zelda_rtl = @import("zelda_rtl.zig");
const main_mod = @import("main.zig");

const g_ram = &vars.g_ram;
const OamEnt = vars.OamEnt;

// ---------------------------------------------------------------------------
// assets.h
// ---------------------------------------------------------------------------

inline fn assetU8(comptime i: usize) [*]const u8 {
    return main_mod.g_asset_ptrs[i].?;
}
inline fn assetU16(comptime i: usize) [*]align(1) const u16 {
    return @ptrCast(main_mod.g_asset_ptrs[i].?);
}

inline fn kDungeonSprites() [*]const u8 {
    return assetU8(58);
}
inline fn kDungeonSpriteOffs() [*]align(1) const u16 {
    return assetU16(59);
}

/// zelda_rtl.h: typedef void HandlerFuncK(int k);
const HandlerFuncK = fn (c_int) callconv(.c) void;

// ---------------------------------------------------------------------------
// types.h / sprite.h structs
// ---------------------------------------------------------------------------

pub const Point16U = extern struct { x: u16, y: u16 };
pub const PointU8 = extern struct { x: u8, y: u8 };
pub const PairU8 = extern struct { a: u8, b: u8 };
pub const ProjectSpeedRet = extern struct { x: u8, y: u8, xdiff: u8, ydiff: u8 };

pub const PrepOamCoordsRet = extern struct {
    x: u16,
    y: u16,
    r4: u8,
    flags: u8,
};

pub const SpriteHitBox = extern struct {
    r0_xlo: u8,
    r8_xhi: u8,
    r1_ylo: u8,
    r9_yhi: u8,
    r2: u8,
    r3: u8,

    r4_spr_xlo: u8,
    r10_spr_xhi: u8,

    r5_spr_ylo: u8,
    r11_spr_yhi: u8,
    r6_spr_xsize: u8,
    r7_spr_ysize: u8,
};

pub const SpriteSpawnInfo = extern struct {
    r0_x: u16,
    r2_y: u16,
    r4_z: u8,
    r5_overlord_x: u16,
    r7_overlord_y: u16,
};

pub const DrawMultipleData = extern struct {
    x: i8,
    y: i8,
    char_flags: u16,
    ext: u8,
};

/// sprite.h
const kCheckDamageFromPlayer_Carry = 1;
const kCheckDamageFromPlayer_Ne = 2;

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

inline fn IntMin(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

/// sprite.c: #define R0 WORD(g_ram[0]) / #define R2 WORD(g_ram[2])
inline fn R0() *align(1) u16 {
    return @ptrCast(&g_ram[0]);
}

inline fn R2() *align(1) u16 {
    return @ptrCast(&g_ram[2]);
}

/// misc.h: the current oam write cursor, as a pointer into work ram.
fn GetOamCurPtr() [*]align(1) OamEnt {
    return @ptrCast(&g_ram[vars.oam_cur_ptr.*]);
}

/// misc.h, a static inline with no linkable symbol.
fn FindInWordArray(data: [*]align(1) const u16, lookfor: u16, size: usize) i32 {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (data[i] == lookfor) return @intCast(i);
    }
    return -1;
}

/// The index of an OamEnt pointer within oam_buf, for bytewise_extended_oam.
inline fn oamIndex(oam: [*]align(1) OamEnt) usize {
    return (@intFromPtr(oam) - @intFromPtr(vars.oam_buf)) / @sizeOf(OamEnt);
}

/// sprite.h static inlines.
fn SetOamHelper0(oam: [*]align(1) OamEnt, x: u16, y: u16, charnum: u8, flags: u8, big: u8) void {
    oam[0].x = @truncate(x);
    oam[0].y = if (y +% 0x10 < 0x100) @truncate(y) else 0xf0;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    vars.bytewise_extended_oam[oamIndex(oam)] = big | @as(u8, @truncate(x >> 8 & 1));
}

fn SetOamHelper1(oam: [*]align(1) OamEnt, x: u16, y: u8, charnum: u8, flags: u8, big: u8) void {
    oam[0].x = @truncate(x);
    oam[0].y = y;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    vars.bytewise_extended_oam[oamIndex(oam)] = big | @as(u8, @truncate(x >> 8 & 1));
}

fn SetOamPlain(oam: [*]align(1) OamEnt, x: u8, y: u8, charnum: u8, flags: u8, big: u8) void {
    oam[0].x = x;
    oam[0].y = y;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    vars.bytewise_extended_oam[oamIndex(oam)] = big;
}

// ---------------------------------------------------------------------------
// Still in C: ancilla.c, dungeon.c, player.c and sprite_main.c.
// ---------------------------------------------------------------------------

extern fn AncillaAdd_FallingPrize(a: u8, item_idx: u8, yv: u8) c_int;
extern fn Ancilla_Main() void;
extern fn Dungeon_UpdateTileMapWithCommonTile(x: c_int, y: c_int, v: u8) void;
extern fn Flame_Draw(k: c_int) void;
extern fn GarnishAllocLimit(k: c_int) c_int;
extern fn Garnish_SetX(k: c_int, x: u16) void;
extern fn Garnish_SetY(k: c_int, y: u16) void;
extern fn HandleIndoorCameraAndDoors() void;
extern fn Link_CancelDash() void;
extern fn Link_ReceiveItem(item: u8, chest_position: c_int) void;
extern fn PrepareDungeonExitFromBossFight() void;
extern fn SpriteActive_Main(k: c_int) void;
extern fn SpriteDraw_WaterRipple(k: c_int) void;
extern fn SpriteModule_Initialize(k: c_int) void;
extern fn SpritePrep_BigKey_load_graphics(k: c_int) void;
extern fn SpritePrep_KeySetItemDrop(k: c_int) void;
extern fn SpritePrep_SmallKey(k: c_int) void;
extern fn Sprite_SpawnPoofGarnish(j: c_int) void;
extern fn Sprite_TransmuteToBomb(k: c_int) void;
extern fn ThrowableScenery_ScatterIntoDebris(k: c_int) void;

// Tables that live in sprite_main.c, not here.
extern const kSinusLookupTable: [256]u16;
extern const kThrowableScenery_Flags: [9]u8;
extern const kWishPond2_OamFlags: [76]u8;

// sprite.h declares these extern for sprite_main.c to link against, so they
// need real symbols rather than the plain consts the generator emits.
pub export const kAbsorbBigKey = tables.kAbsorbBigKey;
pub export const kAbsorptionSfx = tables.kAbsorptionSfx;
pub export const kSpriteInit_BumpDamage = tables.kSpriteInit_BumpDamage;

// ---------------------------------------------------------------------------
// Tables the generator cannot emit: struct arrays and dispatch tables.
// ---------------------------------------------------------------------------

inline fn d(x: i8, y: i8, cf: u16, e: u8) DrawMultipleData {
    return .{ .x = x, .y = y, .char_flags = cf, .ext = e };
}

const kSpriteDrawFall0Data = [12]DrawMultipleData{
    d(0, 0, 0x0146, 2),
    d(0, 0, 0x0148, 2),
    d(0, 0, 0x014a, 2),
    d(4, 4, 0x014c, 0),
    d(4, 4, 0x00b7, 0),
    d(4, 4, 0x0080, 0),
    d(0, 0, 0x016c, 2),
    d(0, 0, 0x016e, 2),
    d(0, 0, 0x014e, 2),
    d(4, 4, 0x015c, 0),
    d(4, 4, 0x00b7, 0),
    d(4, 4, 0x0080, 0),
};

/// Index 12 is NULL in the C, so the element type is optional.
const kGarnish_Funcs = [22]?*const HandlerFuncK{
    &Garnish01_FireSnakeTail,
    &Garnish02_MothulaBeamTrail,
    &Garnish03_FallingTile,
    &Garnish04_LaserTrail,
    &Garnish_SimpleSparkle,
    &Garnish06_ZoroTrail,
    &Garnish07_BabasuFlash,
    &Garnish08_KholdstareTrail,
    &Garnish09_LightningTrail,
    &Garnish0A_CannonSmoke,
    &Garnish_WaterTrail,
    &Garnish0C_TrinexxIceBreath,
    null,
    &Garnish0E_TrinexxFireBreath,
    &Garnish0F_BlindLaserTrail,
    &Garnish10_GanonBatFlame,
    &Garnish11_WitheringGanonBatFlame,
    &Garnish12_Sparkle,
    &Garnish13_PyramidDebris,
    &Garnish14_KakKidDashDust,
    &Garnish15_ArrghusSplash,
    &Garnish16_ThrownItemDebris,
};

const kSprite_ExecuteSingle = [12]*const HandlerFuncK{
    &Sprite_inactiveSprite,
    &SpriteModule_Fall1,
    &SpriteModule_Poof,
    &SpriteModule_Drown,
    &SpriteModule_Explode,
    &SpriteModule_Fall2,
    &SpriteModule_Die,
    &SpriteModule_Burn,
    &SpriteModule_Initialize,
    &SpriteActive_Main,
    &SpriteModule_Carried,
    &SpriteModule_Stunned,
};

// ---------------------------------------------------------------------------
// Coordinates and velocity
// ---------------------------------------------------------------------------

pub export fn Sprite_GetX(k: c_int) callconv(.c) u16 {
    const i: usize = @intCast(k);
    return @as(u16, vars.sprite_x_lo[i]) | @as(u16, vars.sprite_x_hi[i]) << 8;
}

pub export fn Sprite_GetY(k: c_int) callconv(.c) u16 {
    const i: usize = @intCast(k);
    return @as(u16, vars.sprite_y_lo[i]) | @as(u16, vars.sprite_y_hi[i]) << 8;
}

pub export fn Sprite_SetX(k: c_int, x: u16) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.sprite_x_lo[i] = @truncate(x);
    vars.sprite_x_hi[i] = @truncate(x >> 8);
}

pub export fn Sprite_SetY(k: c_int, y: u16) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.sprite_y_lo[i] = @truncate(y);
    vars.sprite_y_hi[i] = @truncate(y >> 8);
}

pub export fn Sprite_ApproachTargetSpeed(k: c_int, x: u8, y: u8) callconv(.c) void {
    const i: usize = @intCast(k);
    const dx = vars.sprite_x_vel[i] -% x;
    if (dx != 0)
        vars.sprite_x_vel[i] +%= if (sign8(dx)) @as(u8, 1) else @as(u8, 255);
    const dy = vars.sprite_y_vel[i] -% y;
    if (dy != 0)
        vars.sprite_y_vel[i] +%= if (sign8(dy)) @as(u8, 1) else @as(u8, 255);
}

pub export fn SpriteAddXY(k: c_int, xv: c_int, yv: c_int) callconv(.c) void {
    Sprite_SetX(k, Sprite_GetX(k) +% @as(u16, @truncate(@as(u32, @bitCast(xv)))));
    Sprite_SetY(k, Sprite_GetY(k) +% @as(u16, @truncate(@as(u32, @bitCast(yv)))));
}

pub export fn Sprite_MoveXYZ(k: c_int) callconv(.c) void {
    Sprite_MoveZ(k);
    Sprite_MoveX(k);
    Sprite_MoveY(k);
}

pub export fn Sprite_Invert_XY_Speeds(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.sprite_x_vel[i] = 0 -% vars.sprite_x_vel[i];
    vars.sprite_y_vel[i] = 0 -% vars.sprite_y_vel[i];
}

pub export fn Sprite_SpawnSimpleSparkleGarnishEx(k: c_int, x: u16, y: u16, limit: c_int) callconv(.c) c_int {
    const j = GarnishAllocLimit(limit);
    if (j >= 0) {
        const ji: usize = @intCast(j);
        const ki: usize = @intCast(k);
        vars.garnish_type[ji] = 5;
        vars.garnish_active.* = 5;
        Garnish_SetX(j, Sprite_GetX(k) +% x);
        Garnish_SetY(j, Sprite_GetY(k) +% y -% vars.sprite_z[ki] +% 16);
        vars.garnish_countdown[ji] = 31;
        vars.garnish_sprite[ji] = @truncate(@as(u32, @bitCast(k)));
        vars.garnish_floor[ji] = vars.sprite_floor[ki];
    }
    g_ram[15] = @truncate(@as(u32, @bitCast(j)));
    return j;
}

fn AllocOverlord() c_int {
    var i: c_int = 7;
    while (i >= 0 and vars.overlord_type[@intCast(i)] != 0) i -= 1;
    return i;
}

fn Overworld_AllocSprite(stype: u8) c_int {
    var i: c_int = if (stype == 0x58) 4 else if (stype == 0xd0) 5 else if (stype == 0xeb or stype == 0x53 or stype == 0xf3) 14 else 13;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        if (vars.sprite_state[u] == 0 or (vars.sprite_type[u] == 0x41 and vars.sprite_C[u] != 0))
            break;
    }
    return i;
}

pub export fn Garnish_GetX(k: c_int) callconv(.c) u16 {
    const i: usize = @intCast(k);
    return @as(u16, vars.garnish_x_lo[i]) | @as(u16, vars.garnish_x_hi[i]) << 8;
}

pub export fn Garnish_GetY(k: c_int) callconv(.c) u16 {
    const i: usize = @intCast(k);
    return @as(u16, vars.garnish_y_lo[i]) | @as(u16, vars.garnish_y_hi[i]) << 8;
}

pub export fn Garnish_SparkleCommon(k: c_int, shift: u8) callconv(.c) void {
    const ki: usize = @intCast(k);
    const tv = vars.garnish_countdown[ki] >> @intCast(shift);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const oam = GetOamCurPtr();
    const j: usize = vars.garnish_sprite[ki];
    SetOamHelper1(
        oam,
        pt.x,
        @truncate(pt.y),
        tables.kGarnishSparkle_Char[tv],
        ((vars.sprite_oam_flags[j] | vars.sprite_obj_prio[j]) & 0xf0) | 4,
        0,
    );
}

pub export fn Garnish_DustCommon(k: c_int, shift: u8) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.tmp_counter.* = vars.garnish_countdown[ki] >> @intCast(shift);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const oam = GetOamCurPtr();
    SetOamHelper1(
        oam,
        pt.x,
        @truncate(pt.y),
        tables.kRunningManDust_Char[vars.tmp_counter.*],
        0x24,
        0,
    );
}

pub export fn SpriteModule_Explode(k: c_int) callconv(.c) void {
    const kSpriteExplode_Dmd = [32]DrawMultipleData{
        d(0, 0, 0x0060, 2),   d(0, 0, 0x0060, 2),  d(0, 0, 0x0060, 2),  d(0, 0, 0x0060, 2),
        d(-5, -5, 0x0062, 2), d(5, -5, 0x4062, 2), d(-5, 5, 0x8062, 2), d(5, 5, 0xc062, 2),
        d(-8, -8, 0x0062, 2), d(8, -8, 0x4062, 2), d(-8, 8, 0x8062, 2), d(8, 8, 0xc062, 2),
        d(-8, -8, 0x0064, 2), d(8, -8, 0x4064, 2), d(-8, 8, 0x8064, 2), d(8, 8, 0xc064, 2),
        d(-8, -8, 0x0066, 2), d(8, -8, 0x4066, 2), d(-8, 8, 0x8066, 2), d(8, 8, 0xc066, 2),
        d(-8, -8, 0x0068, 2), d(8, -8, 0x0068, 2), d(-8, 8, 0x0068, 2), d(8, 8, 0x0068, 2),
        d(-8, -8, 0x006a, 2), d(8, -8, 0x406a, 2), d(-8, 8, 0x806a, 2), d(8, 8, 0xc06a, 2),
        d(-8, -8, 0x004e, 2), d(8, -8, 0x404e, 2), d(-8, 8, 0x804e, 2), d(8, 8, 0xc04e, 2),
    };

    const ki: usize = @intCast(k);
    if (vars.sprite_A[ki] != 0) {
        if (vars.sprite_delay_main[ki] == 0) {
            vars.sprite_state[ki] = 0;
            var j: isize = 15;
            while (j >= 0) : (j -= 1) {
                if (vars.sprite_state[@intCast(j)] == 4)
                    return;
            }
            vars.load_chr_halfslot_even_odd.* = 1;
            if (!Sprite_CheckIfScreenIsClear())
                vars.flag_block_link_menu.* = 0;
        } else {
            const idx: usize = @as(usize, (vars.sprite_delay_main[ki] >> 2) ^ 7) * 4;
            Sprite_DrawMultiple(k, @as([*]const DrawMultipleData, &kSpriteExplode_Dmd) + idx, 4, null);
        }
        return;
    }
    vars.sprite_floor[ki] = 2;

    if (vars.sprite_delay_main[ki] == 32) {
        vars.sprite_state[ki] = 0;
        vars.flag_is_link_immobilized.* = 0;
        if (vars.player_near_pit_state.* != 2 and Sprite_CheckIfScreenIsClear()) {
            if (vars.sprite_type[ki] >= 0xd6) {
                vars.music_control.* = 0x13;
            } else if (vars.sprite_type[ki] == 0x7a) {
                PrepareDungeonExitFromBossFight();
            } else {
                SpriteExplode_SpawnEA(k);
                return;
            }
        }
    }

    if (vars.sprite_delay_main[ki] >= 64 and
        (vars.sprite_delay_main[ki] >= 0x70 or vars.sprite_delay_main[ki] & 1 == 0))
        SpriteActive_Main(k);

    const stype = vars.sprite_type[ki];
    if (vars.sprite_delay_main[ki] >= 0xc0)
        return;
    if (vars.sprite_delay_main[ki] & 3 == 0)
        misc.SpriteSfx_QueueSfx2WithPan(k, 0xc);
    if (vars.sprite_delay_main[ki] & (if (stype == 0x92) @as(u8, 3) else 7) != 0)
        return;

    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, 0x1c, &info);
    if (j >= 0) {
        const ji: usize = @intCast(j);
        vars.load_chr_halfslot_even_odd.* = 11;
        vars.sprite_state[ji] = 4;
        vars.sprite_flags2[ji] = 3;
        vars.sprite_oam_flags[ji] = 0xc;
        const hi: usize = if (stype == 0x92) 8 else 0;
        const xoff = tables.kSpriteExplode_RandomXY[(misc.GetRandomNumber() & 7) | hi];
        const yoff = tables.kSpriteExplode_RandomXY[(misc.GetRandomNumber() & 7) | hi];
        Sprite_SetX(j, info.r0_x +% @as(u16, @bitCast(@as(i16, xoff))));
        Sprite_SetY(j, info.r2_y +% @as(u16, @bitCast(@as(i16, yoff))) -% info.r4_z);
        vars.sprite_delay_main[ji] = 31;
        vars.sprite_A[ji] = 31;
    }
}

// ---------------------------------------------------------------------------
// Death, burn and stun modules
// ---------------------------------------------------------------------------

pub export fn SpriteDeath_MainEx(k: c_int, second_entry: bool) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (!second_entry) {
        const stype = vars.sprite_type[ki];
        if (stype == 0xec) {
            ThrowableScenery_ScatterIntoDebris(k);
            return;
        }
        if (stype == 0x53 or stype == 0x54 or stype == 0x92 or
            (stype == 0x4a and vars.sprite_C[ki] >= 2))
        {
            SpriteActive_Main(k);
            return;
        }
        if (vars.sprite_delay_main[ki] == 0) {
            Sprite_DoTheDeath(k);
            return;
        }
    }
    if (sign8(vars.sprite_flags3[ki])) {
        SpriteActive_Main(k);
        return;
    }
    if ((vars.frame_counter.* & 3) | vars.submodule_index.* | vars.flag_unk1.* == 0)
        vars.sprite_delay_main[ki] +%= 1;
    SpriteDeath_DrawPoof(k);

    if (vars.sprite_type[ki] != 0x40 and vars.sprite_delay_main[ki] < 10)
        return;
    vars.oam_cur_ptr.* +%= 16;
    vars.oam_ext_cur_ptr.* +%= 4;
    const bak = vars.sprite_flags2[ki];
    vars.sprite_flags2[ki] -%= 4;
    SpriteActive_Main(k);
    vars.sprite_flags2[ki] = bak;
}

pub export fn SpriteModule_Burn(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_hit_timer[ki] = 0;
    const j: c_int = @as(c_int, vars.sprite_delay_main[ki]) - 1;
    if (j == 0) {
        Sprite_DoTheDeath(k);
        return;
    }
    const bak = vars.sprite_graphics[ki];
    const bak1 = vars.sprite_oam_flags[ki];
    vars.sprite_graphics[ki] = tables.kFlame_Gfx[@intCast(j >> 3)];
    vars.sprite_oam_flags[ki] = 3;
    Flame_Draw(k);
    vars.sprite_oam_flags[ki] = bak1;
    vars.sprite_graphics[ki] = bak;

    vars.oam_cur_ptr.* +%= 8;
    vars.oam_ext_cur_ptr.* +%= 2;
    if (vars.sprite_delay_main[ki] >= 0x10) {
        const bak2 = vars.sprite_flags2[ki];
        vars.sprite_flags2[ki] -%= 2;
        SpriteActive_Main(k);
        vars.sprite_flags2[ki] = bak2;
    }
}

pub export fn Sprite_HitTimer31(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_type[ki] != 0x7a or vars.is_in_dark_world.* != 0)
        return;
    if (vars.sprite_health[ki] <= vars.sprite_give_damage[ki]) {
        vars.dialogue_message_index.* = 0x140;
        Sprite_ShowMessageMinimal();
    }
}

pub export fn SpriteStunned_MainEx(k: c_int, second_entry: bool) callconv(.c) void {
    const ki: usize = @intCast(k);

    // The C `goto ThrownSprite_TileAndSpriteInteraction` jumps into the middle
    // of the `if (!sprite_E[k])` block, skipping both the preamble and the test.
    if (!second_entry) {
        Sprite_DrawRippleIfInWater(k);
        SpriteStunned_Main_Func1(k);
        if (Sprite_ReturnIfPaused(k))
            return;
        if (vars.sprite_F[ki] != 0) {
            if (sign8(vars.sprite_F[ki]))
                vars.sprite_F[ki] = 0;
            vars.sprite_x_vel[ki] = 0;
            vars.sprite_y_vel[ki] = 0;
        }
        if (vars.sprite_delay_main[ki] < 0x20)
            _ = Sprite_CheckDamageFromLink(k);
        if (Sprite_ReturnIfRecoiling(k))
            return;
        Sprite_MoveXY(k);
    }

    if (second_entry or vars.sprite_E[ki] == 0) {
        if (!second_entry) {
            _ = Sprite_CheckTileCollision(k);
            if (vars.sprite_state[ki] == 0)
                return;
        }
        // ThrownSprite_TileAndSpriteInteraction:
        if (vars.sprite_wallcoll[ki] & 0xf != 0) {
            Sprite_ApplyRicochet(k);
            if (vars.sprite_state[ki] == 11)
                misc.SpriteSfx_QueueSfx2WithPan(k, 5);
        }
    }
    _ = Sprite_CheckTileProperty(k, 0x68);

    if (tables.kSpriteInit_Flags3[vars.sprite_type[ki]] & 0x10 != 0) {
        vars.sprite_flags3[ki] |= 0x10;
        if (vars.sprite_tiletype.* == 32)
            vars.sprite_flags3[ki] &= ~@as(u8, 0x10);
    }
    Sprite_MoveZ(k);
    vars.sprite_z_vel[ki] -%= 2;
    var z = vars.sprite_z[ki] -% 1;
    if (z >= 0xf0) {
        vars.sprite_z[ki] = 0;
        if (vars.sprite_type[ki] == 0xe8 and sign8(vars.sprite_z_vel[ki] -% 0xe8)) {
            vars.sprite_state[ki] = 6;
            vars.sprite_delay_main[ki] = 8;
            vars.sprite_flags2[ki] = 3;
            return;
        }
        ThrowableScenery_TransmuteIfValid(k);
        var a = vars.sprite_tiletype.*;
        // The C comma expression assigns `a` only when the && reaches it.
        if (vars.sprite_tiletype.* == 32) {
            a = vars.sprite_flags[ki] >> 1;
            if (vars.sprite_flags[ki] & 1 == 0) {
                Sprite_Func8(k);
                return;
            }
        }
        if (a == 9) {
            z = vars.sprite_z_vel[ki];
            vars.sprite_z_vel[ki] = 0;
            var info: SpriteSpawnInfo = undefined;
            if (sign8(z -% 0xf0)) {
                const j = Sprite_SpawnDynamically(k, 0xec, &info);
                if (j >= 0) {
                    Sprite_SetSpawnedCoordinates(j, &info);
                    Sprite_Func22(j);
                }
            }
        } else if (a == 8) {
            if (vars.sprite_type[ki] == 0xd2 or (misc.GetRandomNumber() & 1) != 0)
                Sprite_SpawnLeapingFish(k);
            Sprite_Func22(k);
            return;
        }
        z = vars.sprite_z_vel[ki];
        if (sign8(z)) {
            z = (0 -% z) >> 1;
            vars.sprite_z_vel[ki] = if (z < 9) 0 else z;
        }
        vars.sprite_x_vel[ki] = @bitCast(@as(i8, @bitCast(vars.sprite_x_vel[ki])) >> 1);
        if (vars.sprite_x_vel[ki] == 255)
            vars.sprite_x_vel[ki] = 0;
        vars.sprite_y_vel[ki] = @bitCast(@as(i8, @bitCast(vars.sprite_y_vel[ki])) >> 1);
        if (vars.sprite_y_vel[ki] == 255)
            vars.sprite_y_vel[ki] = 0;
    }
    if (vars.sprite_state[ki] != 11 or vars.sprite_unk5[ki] != 0) {
        if (Sprite_ReturnIfLifted(k))
            return;
        if (vars.sprite_type[ki] != 0x4a)
            ThrownSprite_CheckDamageToSprites(k);
    }
}

pub export fn Ancilla_SpawnFallingPrize(item: u8) callconv(.c) c_int {
    return AncillaAdd_FallingPrize(0x29, item, 4);
}

pub export fn Sprite_CheckDamageToAndFromLink(k: c_int) callconv(.c) bool {
    _ = Sprite_CheckDamageFromLink(k);
    return Sprite_CheckDamageToLink(k);
}

pub export fn Sprite_CheckTileCollision(k: c_int) callconv(.c) u8 {
    Sprite_CheckTileCollision2(k);
    return vars.sprite_wallcoll[@intCast(k)];
}

pub export fn Sprite_TrackBodyToHead(k: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    if (vars.sprite_head_dir[ki] != vars.sprite_D[ki]) {
        if (vars.frame_counter.* & 0x1f != 0)
            return false;
        if ((vars.sprite_head_dir[ki] ^ vars.sprite_D[ki]) & 2 == 0) {
            const kk: u32 = @bitCast(k);
            const mixed: u32 = (kk ^ @as(u32, vars.frame_counter.*)) >> 5;
            vars.sprite_D[ki] = @truncate(((mixed | 2) & 3) ^ (vars.sprite_head_dir[ki] & 2));
            return false;
        }
    }
    vars.sprite_D[ki] = vars.sprite_head_dir[ki];
    return true;
}

// ---------------------------------------------------------------------------
// Drawing helpers
// ---------------------------------------------------------------------------

pub export fn Sprite_DrawMultiple(k: c_int, src_in: [*]const DrawMultipleData, n_in: c_int, info_in: ?*PrepOamCoordsRet) callconv(.c) void {
    const ki: usize = @intCast(k);
    var info_buf: PrepOamCoordsRet = undefined;
    const info = info_in orelse &info_buf;
    if (Sprite_PrepOamCoordOrDoubleRet(k, info))
        return;
    vars.word_7E0CFE.* = 0;
    var a = vars.sprite_state[ki];
    if (a == 10)
        a = vars.sprite_unk4[ki];
    if (a == 11)
        loPtr(vars.word_7E0CFE).* = vars.sprite_unk5[ki];
    var oam = GetOamCurPtr();
    var src = src_in;
    var n = n_in;
    while (true) {
        var dv = src[0].char_flags ^ @as(*align(1) const u16, @ptrCast(&info.r4)).*;
        if (vars.word_7E0CFE.* >= 1)
            dv = (dv & ~@as(u16, 0xE00)) | 0x400;
        SetOamHelper0(
            oam,
            @as(u16, @bitCast(@as(i16, src[0].x))) +% info.x,
            @as(u16, @bitCast(@as(i16, src[0].y))) +% info.y,
            @truncate(dv),
            @truncate(dv >> 8),
            src[0].ext,
        );
        src += 1;
        oam += 1;
        n -= 1;
        if (n == 0) break;
    }
}

pub export fn Sprite_DrawMultiplePlayerDeferred(k: c_int, src: [*]const DrawMultipleData, n: c_int, info: ?*PrepOamCoordsRet) callconv(.c) void {
    Oam_AllocateDeferToPlayer(k);
    Sprite_DrawMultiple(k, src, n, info);
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

pub export fn Sprite_ShowSolicitedMessage(k: c_int, msg: u16) callconv(.c) c_int {
    const ki: usize = @intCast(k);
    vars.dialogue_message_index.* = msg;
    if (!Sprite_CheckDamageToLink_same_layer(k) or
        Sprite_CheckIfLinkIsBusy() or
        vars.filtered_joypad_L.* & 0x80 == 0 or
        vars.sprite_delay_aux4[ki] != 0 or
        vars.link_auxiliary_state.* == 2)
        return vars.sprite_D[ki];
    const dir = Sprite_DirectionToFaceLink(k, null);
    if (vars.link_direction_facing.* != tables.kShowMessageFacing_Tab0[dir])
        return vars.sprite_D[ki];
    Sprite_ShowMessageUnconditional(vars.dialogue_message_index.*);
    vars.sprite_delay_aux4[ki] = 64;
    return @as(c_int, dir) ^ 0x103;
}

pub export fn Sprite_ShowMessageOnContact(k: c_int, msg: u16) callconv(.c) c_int {
    const ki: usize = @intCast(k);
    vars.dialogue_message_index.* = msg;
    if (!Sprite_CheckDamageToLink_same_layer(k) or vars.link_auxiliary_state.* == 2)
        return vars.sprite_D[ki];
    Sprite_ShowMessageUnconditional(vars.dialogue_message_index.*);
    return @as(c_int, Sprite_DirectionToFaceLink(k, null)) ^ 0x103;
}

pub export fn Sprite_ShowMessageUnconditional(msg: u16) callconv(.c) void {
    vars.dialogue_message_index.* = msg;
    vars.byte_7E0223.* = 0;
    vars.messaging_module.* = 0;
    vars.submodule_index.* = 2;
    vars.saved_module_for_menu.* = vars.main_module_index.*;
    vars.main_module_index.* = 14;
    Sprite_NullifyHookshotDrag();
    vars.link_speed_setting.* = 0;
    Link_CancelDash();
    vars.link_auxiliary_state.* = 0;
    vars.link_incapacitated_timer.* = 0;
    // player.h: kPlayerState_RecoilWall = 2, kPlayerState_Ground = 0
    if (vars.link_player_handler_state.* == 2)
        vars.link_player_handler_state.* = 0;
}

pub export fn Sprite_TutorialGuard_ShowMessageOnContact(k: c_int, msg: u16) callconv(.c) bool {
    const ki: usize = @intCast(k);
    vars.dialogue_message_index.* = msg;
    const bak2 = vars.sprite_flags2[ki];
    const bak4 = vars.sprite_flags4[ki];
    vars.sprite_flags2[ki] = 0x80;
    vars.sprite_flags4[ki] = 0x07;
    const rv = Sprite_CheckDamageToLink_same_layer(k);
    vars.sprite_flags2[ki] = bak2;
    vars.sprite_flags4[ki] = bak4;
    if (!rv)
        return rv;
    Sprite_NullifyHookshotDrag();
    vars.link_is_running.* = 0;
    vars.link_speed_setting.* = 0;
    if (vars.link_auxiliary_state.* == 0)
        Sprite_ShowMessageMinimal();
    return rv;
}

pub export fn Sprite_ShowMessageMinimal() callconv(.c) void {
    vars.byte_7E0223.* = 0;
    vars.messaging_module.* = 0;
    vars.submodule_index.* = 2;
    vars.saved_module_for_menu.* = vars.main_module_index.*;
    vars.main_module_index.* = 14;
}

// ---------------------------------------------------------------------------
// Terrain spawning
// ---------------------------------------------------------------------------

pub export fn Prepare_ApplyRumbleToSprites() callconv(.c) void {
    const j: usize = vars.link_direction_facing.* >> 1;
    var hb: SpriteHitBox = undefined;
    const x = vars.link_x_coord.* +% @as(u16, @bitCast(@as(i16, tables.kApplyRumble_X[j])));
    const y = vars.link_y_coord.* +% @as(u16, @bitCast(@as(i16, tables.kApplyRumble_Y[j])));
    hb.r0_xlo = @truncate(x);
    hb.r8_xhi = @truncate(x >> 8);
    hb.r1_ylo = @truncate(y);
    hb.r9_yhi = @truncate(y >> 8);
    hb.r2 = tables.kApplyRumble_WH[j];
    hb.r3 = tables.kApplyRumble_WH[j + 2];
    Entity_ApplyRumbleToSprites(&hb);
}

pub export fn Sprite_SpawnImmediatelySmashedTerrain(what: u8, x: u16, y: u16) callconv(.c) void {
    const bak1 = vars.flag_is_sprite_to_pick_up.*;
    const bak2 = vars.byte_7E0FB2.*;
    const k = Sprite_SpawnThrowableTerrain_silently(what, x, y);
    if (k >= 0)
        ThrowableScenery_TransmuteToDebris(k);
    vars.byte_7E0FB2.* = bak2;
    vars.flag_is_sprite_to_pick_up.* = bak1;
}

pub export fn Sprite_SpawnThrowableTerrain(what: u8, x: u16, y: u16) callconv(.c) void {
    vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | 29;
    _ = Sprite_SpawnThrowableTerrain_silently(what, x, y);
}

pub export fn Sprite_SpawnThrowableTerrain_silently(what: u8, x: u16, y: u16) callconv(.c) c_int {
    var k: c_int = 15;
    while (k >= 0 and vars.sprite_state[@intCast(k)] != 0) k -= 1;
    if (k < 0)
        return k;
    const ki: usize = @intCast(k);
    vars.sprite_state[ki] = 10;
    vars.sprite_type[ki] = 0xEC;
    Sprite_SetX(k, x);
    Sprite_SetY(k, y);
    SpritePrep_LoadProperties(k);
    vars.sprite_floor[ki] = vars.link_is_on_lower_level.*;
    vars.sprite_C[ki] = what;
    if (what >= 6)
        vars.sprite_flags2[ki] = 0xa6;
    // oob read, this array has only 6 elements.
    var flags = kThrowableScenery_Flags[what];
    if (what == 2) {
        if (vars.player_is_indoors.* != 0) {
            vars.sprite_oam_flags[ki] = 0x80;
            flags = 0x50; // wtf
        }
    }
    vars.sprite_oam_flags[ki] = flags;
    vars.sprite_unk4[ki] = 9;
    vars.flag_is_sprite_to_pick_up.* = 2;
    vars.byte_7E0FB2.* = 2;
    vars.sprite_delay_main[ki] = 16;
    vars.sprite_floor[ki] = vars.link_is_on_lower_level.*;
    vars.sprite_graphics[ki] = 0;
    if (loPtr(vars.dung_secrets_unk1).* != 255) {
        if ((loPtr(vars.dung_secrets_unk1).* | vars.player_is_indoors.*) == 0 and
            (vars.sprite_C[ki] -% 2) < 2)
            Overworld_SubstituteAlternateSecret();
        if (vars.dung_secrets_unk1.* & 0x80 != 0) {
            vars.sprite_graphics[ki] = @truncate(vars.dung_secrets_unk1.* & 0x7f);
            loPtr(vars.dung_secrets_unk1).* = 0;
        }
        Sprite_SpawnSecret(k);
    }
    return k;
}

pub export fn Sprite_SpawnSecret(k: c_int) callconv(.c) void {
    if (vars.player_is_indoors.* == 0 and (misc.GetRandomNumber() & 8) != 0)
        return;
    var b: usize = loPtr(vars.dung_secrets_unk1).*;
    if (b == 0)
        return;
    if (b == 4)
        b = 19 + (misc.GetRandomNumber() & 3);
    if (tables.kSpawnSecretItems[b - 1] == 0)
        return;
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, tables.kSpawnSecretItems[b - 1], &info);
    if (j < 0)
        return;
    const ji: usize = @intCast(j);
    vars.sprite_ai_state[ji] = tables.kSpawnSecretItem_SpawnFlag[b - 1];
    vars.sprite_ignore_projectile[ji] = tables.kSpawnSecretItem_IgnoreProj[b - 1];
    vars.sprite_z_vel[ji] = tables.kSpawnSecretItem_ZVel[b - 1];
    Sprite_SetX(j, info.r0_x +% tables.kSpawnSecretItem_XLo[b - 1]);
    Sprite_SetY(j, info.r2_y);
    vars.sprite_z[ji] = info.r4_z;
    vars.sprite_graphics[ji] = 0;
    vars.sprite_delay_aux4[ji] = 32;
    vars.sprite_delay_aux2[ji] = 48;
    const stype = vars.sprite_type[ji];
    if (stype == 0xe4) {
        SpritePrep_SmallKey(j);
        vars.sprite_stunned[ji] = 255;
    } else if (stype == 0xb) {
        vars.sound_effect_1.* = 0x30;
        if (loPtr(vars.dungeon_room_index2).* == 1)
            vars.sprite_subtype[ji] = 1;
        vars.sprite_stunned[ji] = 255;
    } else if (stype == 0x41 or stype == 0x42) {
        vars.sound_effect_2.* = 4;
        vars.sprite_give_damage[ji] = 0;
        vars.sprite_hit_timer[ji] = 160;
    } else if (stype == 0x3e) {
        vars.sprite_oam_flags[ji] = 9;
    } else {
        vars.sprite_stunned[ji] = 255;
        if (stype == 0x79)
            vars.sprite_A[ji] = 32;
    }
}

// ---------------------------------------------------------------------------
// Main loop, timers and OAM regions
// ---------------------------------------------------------------------------

pub export fn Sprite_Main() callconv(.c) void {
    if (vars.player_is_indoors.* == 0) {
        vars.ancilla_floor[0] = 0;
        vars.ancilla_floor[1] = 0;
        vars.ancilla_floor[2] = 0;
        vars.ancilla_floor[3] = 0;
        vars.ancilla_floor[4] = 0;
        Sprite_ProximityActivation();
    }
    vars.is_in_dark_world.* = @intFromBool(vars.savegame_is_darkworld.* != 0);
    if (vars.submodule_index.* == 0) {
        vars.drag_player_x.* = 0;
        vars.drag_player_y.* = 0;
    }
    Oam_ResetRegionBases();
    Garnish_ExecuteUpperSlots();
    tagalong.Follower_Main();
    vars.byte_7E0FB2.* = vars.flag_is_sprite_to_pick_up.*;
    vars.flag_is_sprite_to_pick_up.* = 0;
    hiPtr(vars.dungmap_var8).* = 0x80;

    if (vars.set_when_damaging_enemies.* & 0x7f != 0) {
        vars.set_when_damaging_enemies.* -%= 1;
    } else {
        vars.set_when_damaging_enemies.* = 0;
    }
    vars.byte_7E0379.* = 0;
    vars.link_unk_master_sword.* = 0;
    vars.link_prevent_from_moving.* = 0;
    if (vars.sprite_alert_flag.* != 0)
        vars.sprite_alert_flag.* -%= 1;
    Ancilla_Main();
    overlord.Overlord_Main();
    vars.archery_game_out_of_arrows.* = 0;
    var i: isize = 15;
    while (i >= 0) : (i -= 1) {
        vars.cur_object_index.* = @intCast(i);
        Sprite_ExecuteSingle(@intCast(i));
    }
    Garnish_ExecuteLowerSlots();
    vars.byte_7E069E[0] = 0;
    vars.byte_7E069E[1] = 0;
    ExecuteCachedSprites();
    if (vars.load_chr_halfslot_even_odd.* != 0)
        vars.byte_7E0FC6.* = vars.load_chr_halfslot_even_odd.*;
}

pub export fn Oam_ResetRegionBases() callconv(.c) void {
    @memcpy(vars.oam_region_base[0..6], tables.kOam_ResetRegionBases[0..6]);
}

pub export fn Sprite_TimersAndOam(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    Sprite_Get16BitCoords(k);

    const num: u8 = ((vars.sprite_flags2[ki] & 0x1f) +% 1) *% 4;

    if (vars.sort_sprites_setting.* != 0) {
        if (vars.sprite_floor[ki] != 0) {
            _ = Oam_AllocateFromRegionF(num);
        } else {
            _ = Oam_AllocateFromRegionD(num);
        }
    } else {
        _ = Oam_AllocateFromRegionA(num);
    }

    if (vars.submodule_index.* | vars.flag_unk1.* == 0) {
        if (vars.sprite_delay_main[ki] != 0) vars.sprite_delay_main[ki] -%= 1;
        if (vars.sprite_delay_aux1[ki] != 0) vars.sprite_delay_aux1[ki] -%= 1;
        if (vars.sprite_delay_aux2[ki] != 0) vars.sprite_delay_aux2[ki] -%= 1;
        if (vars.sprite_delay_aux3[ki] != 0) vars.sprite_delay_aux3[ki] -%= 1;

        const timer = vars.sprite_hit_timer[ki] & 0x7f;
        if (timer != 0) {
            if (vars.sprite_state[ki] >= 9) {
                if (timer == 31) {
                    Sprite_HitTimer31(k);
                } else if (timer == 24) {
                    Sprite_MiniMoldorm_Recoil(k);
                }
            }
            if (vars.sprite_give_damage[ki] < 251)
                vars.sprite_obj_prio[ki] = (vars.sprite_hit_timer[ki] *% 2) & 0xe;
            vars.sprite_hit_timer[ki] -%= 1;
        } else {
            vars.sprite_hit_timer[ki] = 0;
            vars.sprite_obj_prio[ki] = 0;
        }
        if (vars.sprite_delay_aux4[ki] != 0) vars.sprite_delay_aux4[ki] -%= 1;
    }

    var floor: usize = vars.link_is_on_lower_level.*;
    if (floor != 3)
        floor = vars.sprite_floor[ki];
    vars.sprite_obj_prio[ki] = (vars.sprite_obj_prio[ki] & 0xcf) | tables.kSpritePrios[floor];
}

pub export fn Sprite_Get16BitCoords(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.cur_sprite_x.* = @as(u16, vars.sprite_x_lo[i]) | @as(u16, vars.sprite_x_hi[i]) << 8;
    vars.cur_sprite_y.* = @as(u16, vars.sprite_y_lo[i]) | @as(u16, vars.sprite_y_hi[i]) << 8;
}

pub export fn Sprite_ExecuteSingle(k: c_int) callconv(.c) void {
    const st = vars.sprite_state[@intCast(k)];
    if (st != 0)
        Sprite_TimersAndOam(k);
    kSprite_ExecuteSingle[st](k);
}

pub export fn Sprite_inactiveSprite(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    if (vars.player_is_indoors.* == 0) {
        vars.sprite_N_word[i] = 0xffff;
    } else {
        vars.sprite_N[i] = 0xff;
    }
}

pub export fn SpriteModule_Fall1(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_delay_main[ki] == 0) {
        vars.sprite_state[ki] = 0;
        Sprite_ManuallySetDeathFlagUW(k);
    } else {
        var info: PrepOamCoordsRet = undefined;
        if (Sprite_PrepOamCoordOrDoubleRet(k, &info))
            return;
        SpriteFall_Draw(k, &info);
    }
}

pub export fn SpriteModule_Drown(k: c_int) callconv(.c) void {
    const kSpriteDrown_Dmd = [8]DrawMultipleData{
        d(-7, -7, 0x0480, 0),
        d(14, -6, 0x0483, 0),
        d(-6, -6, 0x04cf, 0),
        d(13, -5, 0x04df, 0),
        d(-4, -4, 0x04ae, 0),
        d(12, -4, 0x44af, 0),
        d(0, 0, 0x04e7, 2),
        d(0, 0, 0x04e7, 2),
    };

    const ki: usize = @intCast(k);
    if (vars.sprite_ai_state[ki] != 0) {
        if (vars.sprite_A[ki] == 6)
            _ = Oam_AllocateFromRegionC(8);
        vars.sprite_flags3[ki] ^= 16;
        SpriteDraw_SingleLarge(k);
        const oam = GetOamCurPtr();
        const j = vars.sprite_delay_main[ki];
        if (j == 1)
            vars.sprite_state[ki] = 0;
        if (j != 0) {
            oam[0].charnum = tables.kSpriteDrown_Oam_Char[j >> 1];
            oam[0].flags = 0x24;
            return;
        }
        oam[0].charnum = 0x8a;
        oam[0].flags = tables.kSpriteDrown_Oam_Flags[(vars.sprite_subtype2[ki] >> 2) & 3] | 0x24;

        if (Sprite_ReturnIfPaused(k))
            return;
        vars.sprite_subtype2[ki] +%= 1;
        Sprite_MoveXY(k);
        Sprite_MoveZ(k);
        vars.sprite_z_vel[ki] -%= 2;
        if (sign8(vars.sprite_z[ki])) {
            vars.sprite_z[ki] = 0;
            vars.sprite_delay_main[ki] = 18;
            vars.sprite_flags3[ki] &= ~@as(u8, 0x10);
        }
    } else {
        if (Sprite_ReturnIfPaused(k))
            return;
        if (vars.frame_counter.* & 1 == 0)
            vars.sprite_delay_main[ki] +%= 1;
        vars.sprite_oam_flags[ki] = 0;
        vars.sprite_hit_timer[ki] = 0;
        if (vars.sprite_delay_main[ki] == 0)
            vars.sprite_state[ki] = 0;
        const idx: usize = ((@as(usize, vars.sprite_delay_main[ki]) << 1) & 0xf8) >> 2;
        Sprite_DrawMultiple(k, @as([*]const DrawMultipleData, &kSpriteDrown_Dmd) + idx, 2, null);
    }
}

pub export fn Sprite_DrawDistress_custom(xin: u16, yin: u16, time: u8) callconv(.c) void {
    _ = Oam_AllocateFromRegionA(0x10);
    if (time & 0x18 == 0)
        return;
    var i: isize = 3;
    var oam = GetOamCurPtr();
    while (true) {
        const u: usize = @intCast(i);
        SetOamHelper0(
            oam,
            xin +% @as(u16, @bitCast(@as(i16, tables.kSpriteDistress_X[u]))),
            yin +% @as(u16, @bitCast(@as(i16, tables.kSpriteDistress_Y[u]))),
            0x83,
            0x22,
            0,
        );
        oam += 1;
        i -= 1;
        if (i < 0) break;
    }
}

pub export fn Sprite_CheckIfLifted_permissive(k: c_int) callconv(.c) void {
    _ = Sprite_ReturnIfLiftedPermissive(k);
}

pub export fn Entity_ApplyRumbleToSprites(hb: *SpriteHitBox) callconv(.c) void {
    var j: isize = 15;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        if (vars.sprite_defl_bits[u] & 2 == 0 or vars.sprite_E[u] == 0)
            continue;
        if (vars.byte_7E0FC6.* != 0xe) {
            Sprite_SetupHitBox(@intCast(j), hb);
            if (!CheckIfHitBoxesOverlap(hb))
                continue;
        }
        vars.sprite_E[u] = 0;
        vars.sound_effect_2.* = 0x30;
        vars.sprite_z_vel[u] = 0x30;
        vars.sprite_x_vel[u] = 0x10;
        vars.sprite_delay_aux3[u] = 0x30;
        vars.sprite_stunned[u] = 255;
        if (vars.sprite_type[u] == 0xd8)
            Sprite_TransmuteToBomb(@intCast(j));
    }
}

pub export fn Sprite_ZeroVelocity_XY(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.sprite_x_vel[i] = 0;
    vars.sprite_y_vel[i] = 0;
}

pub export fn Sprite_HandleDraggingByAncilla(k: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    const jb = vars.sprite_B[ki];
    if (jb == 0)
        return false;
    const j: usize = jb - 1;
    if (vars.ancilla_type[j] == 0) {
        Sprite_HandleAbsorptionByPlayer(k);
    } else {
        vars.sprite_x_lo[ki] = vars.ancilla_x_lo[j];
        vars.sprite_x_hi[ki] = vars.ancilla_x_hi[j];
        vars.sprite_y_lo[ki] = vars.ancilla_y_lo[j];
        vars.sprite_y_hi[ki] = vars.ancilla_y_hi[j];
        vars.sprite_z[ki] = 0;
    }
    return true;
}

pub export fn Sprite_ReturnIfPhasingOut(k: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    if (vars.sprite_stunned[ki] == 0 or (vars.submodule_index.* | vars.flag_unk1.*) != 0)
        return false;
    if (vars.frame_counter.* & 1 == 0)
        vars.sprite_stunned[ki] -%= 1;
    const a = vars.sprite_stunned[ki];
    if (a == 0) {
        vars.sprite_state[ki] = 0;
    } else if (a >= 0x28 or (a & 1) != 0) {
        return false;
    }
    var info: PrepOamCoordsRet = undefined;
    _ = Sprite_PrepOamCoordOrDoubleRet(k, &info);
    return true;
}

pub export fn Sprite_CheckAbsorptionByPlayer(k: c_int) callconv(.c) void {
    if (vars.sprite_delay_aux4[@intCast(k)] == 0 and Sprite_CheckDamageToPlayer_1(k))
        Sprite_HandleAbsorptionByPlayer(k);
}

pub export fn Sprite_HandleAbsorptionByPlayer(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_state[ki] = 0;
    const t: usize = vars.sprite_type[ki] -% 0xd8;
    misc.SpriteSfx_QueueSfx3WithPan(k, tables.kAbsorptionSfx[t]);
    switch (t) {
        0 => vars.link_hearts_filler.* +%= 8,
        1, 2, 3 => vars.link_rupees_goal.* +%= tables.kRupeesAbsorption[t - 1],
        4, 5, 6 => vars.link_bomb_filler.* +%= tables.kBombsAbsorption[t - 4],
        7 => vars.link_magic_filler.* +%= 0x10,
        8 => vars.link_magic_filler.* = 0x80,
        9 => vars.link_arrow_filler.* +%= if (vars.sprite_head_dir[ki] == 0) 5 else vars.sprite_head_dir[ki],
        10 => vars.link_arrow_filler.* +%= 10,
        11 => {
            misc.SpriteSfx_QueueSfx2WithPan(k, 0x31);
            vars.link_hearts_filler.* +%= 56;
        },
        // case 12 jumps into case 13's tail via `goto after_getkey`.
        12, 13 => {
            if (t == 13) {
                vars.item_receipt_method.* = 0;
                Link_ReceiveItem(0x32, 0);
            } else {
                vars.link_num_keys.* +%= 1;
            }
            // after_getkey:
            vars.sprite_N[ki] = vars.sprite_subtype[ki];
            vars.dung_savegame_state_bits.* |=
                @as(u16, tables.kAbsorbBigKey[vars.sprite_die_action[ki]]) << 8;
            Sprite_ManuallySetDeathFlagUW(k);
        },
        14 => {
            vars.link_shield_type.* = vars.sprite_subtype[ki];
            // Shield needs to have the right palette after pikit
            if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
                load_gfx.Palette_Load_Shield();
        },
        else => {},
    }
}

pub export fn SpriteDraw_AbsorbableTransient(k: c_int, transient: bool) callconv(.c) bool {
    const ki: usize = @intCast(k);
    if (transient and Sprite_ReturnIfPhasingOut(k))
        return false;
    if (vars.sort_sprites_setting.* == 0 and vars.player_is_indoors.* != 0)
        vars.sprite_obj_prio[ki] = 0x30;
    if (vars.byte_7E0FC6.* >= 3)
        return false;
    if (vars.sprite_delay_aux2[ki] != 0)
        _ = Oam_AllocateFromRegionC(12);
    if (vars.sprite_E[ki] != 0) {
        // This code runs when an absorbable is hidden under say a rock.
        // sprite_B holds the sprite that grabbed us with a hookshot.
        // Cancel the grab if we're hidden.
        if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
            vars.sprite_B[ki] = 0;
        return true;
    }
    const j: usize = vars.sprite_type[ki];
    const a = tables.kAbsorbable_Tab2[j - 0xd8];
    if (a != 0) {
        Sprite_DrawNumberedAbsorbable(k, a);
        return false;
    }
    const tv = tables.kAbsorbable_Tab1[j - 0xd8];
    if (tv == 0) {
        SpriteDraw_SingleSmall(k);
        return false;
    }
    // `goto draw_key` skips the SingleLarge draw below.
    var draw_key = false;
    if (tv == 2) {
        if (vars.sprite_type[ki] == 0xe6) {
            if (vars.sprite_subtype[ki] == 1) {
                draw_key = true;
            } else {
                vars.sprite_graphics[ki] = 1;
            }
        }
        if (!draw_key) {
            SpriteDraw_SingleLarge(k);
            return false;
        }
    }
    Sprite_DrawThinAndTall(k);
    return false;
}

pub export fn Sprite_DrawNumberedAbsorbable(k: c_int, a_in: c_int) callconv(.c) void {
    const a: usize = @intCast((a_in - 1) * 3);
    var info: PrepOamCoordsRet = undefined;
    if (Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = GetOamCurPtr();
    var n: isize = if (vars.sprite_head_dir[@intCast(k)] < 1) 2 else 1;
    while (true) {
        const j: usize = @as(usize, @intCast(n)) + a;
        SetOamHelper0(
            oam,
            info.x +% @as(u16, @bitCast(tables.kNumberedAbsorbable_X[j])),
            info.y +% @as(u16, @bitCast(tables.kNumberedAbsorbable_Y[j])),
            tables.kNumberedAbsorbable_Char[j],
            info.flags,
            tables.kNumberedAbsorbable_Ext[j],
        );
        oam += 1;
        n -= 1;
        if (n < 0) break;
    }
    SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_BounceOffWall(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    if (vars.sprite_wallcoll[i] & 3 != 0)
        vars.sprite_x_vel[i] = 0 -% vars.sprite_x_vel[i];
    if (vars.sprite_wallcoll[i] & 12 != 0)
        vars.sprite_y_vel[i] = 0 -% vars.sprite_y_vel[i];
}

pub export fn Sprite_InvertSpeed_XY(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.sprite_x_vel[i] = 0 -% vars.sprite_x_vel[i];
    vars.sprite_y_vel[i] = 0 -% vars.sprite_y_vel[i];
}

pub export fn Sprite_ReturnIfInactive(k: c_int) callconv(.c) bool {
    const i: usize = @intCast(k);
    return vars.sprite_state[i] != 9 or vars.flag_unk1.* != 0 or vars.submodule_index.* != 0 or
        (vars.sprite_defl_bits[i] & 0x80 == 0 and vars.sprite_pause[i] != 0);
}

pub export fn Sprite_ReturnIfPaused(k: c_int) callconv(.c) bool {
    const i: usize = @intCast(k);
    return vars.flag_unk1.* != 0 or vars.submodule_index.* != 0 or
        (vars.sprite_defl_bits[i] & 0x80 == 0 and vars.sprite_pause[i] != 0);
}

// ---------------------------------------------------------------------------
// Single-sprite draw routines
// ---------------------------------------------------------------------------

pub export fn SpriteDraw_SingleLarge(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    if (Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    Sprite_PrepAndDrawSingleLargeNoPrep(k, &info);
}

pub export fn Sprite_PrepAndDrawSingleLargeNoPrep(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const ki: usize = @intCast(k);
    const oam = GetOamCurPtr();
    oam[0].x = @truncate(info.x);
    if (info.y +% 0x10 < 0x100) {
        oam[0].y = @truncate(info.y);
        // sprite_type 0xEC (thrown item) is 236, one past the end of this
        // 236-entry table. The C read whatever followed it in memory, and
        // Sprite_EC_ThrownItem overwrites charnum on the very next line, so
        // that value never reaches the screen. Skip the lookup rather than
        // trapping; every in-range sprite type behaves exactly as before.
        const st: usize = vars.sprite_type[ki];
        if (st < tables.kSprite_PrepAndDrawSingleLarge_Tab1.len) {
            const idx: usize = @as(usize, tables.kSprite_PrepAndDrawSingleLarge_Tab1[st]) +
                vars.sprite_graphics[ki];
            oam[0].charnum = tables.kSprite_PrepAndDrawSingleLarge_Tab2[idx];
        }
        oam[0].flags = info.flags;
    }
    vars.bytewise_extended_oam[oamIndex(oam)] = 2 | @as(u8, if (info.x >= 256) 1 else 0);
    if (vars.sprite_flags3[ki] & 0x10 != 0)
        SpriteDraw_Shadow(k, info);
}

pub export fn SpriteDraw_Shadow_custom(k: c_int, info: *PrepOamCoordsRet, a: u8) callconv(.c) void {
    const ki: usize = @intCast(k);
    var y = Sprite_GetY(k) +% a;
    info.y = y;
    if (vars.sprite_pause[ki] != 0 or (vars.sprite_state[ki] == 10 and vars.sprite_unk3[ki] == 3))
        return;
    y -%= vars.BG2VOFS_copy2.*;
    info.y = y;
    if (y +% 0x10 >= 0x100)
        return;
    const oam = GetOamCurPtr() + (vars.sprite_flags2[ki] & 0x1f);
    if (vars.sprite_flags3[ki] & 0x20 != 0) {
        SetOamHelper1(oam, info.x, @truncate(y +% 1), 0x38, (info.flags & 0x30) | 8, 0);
    } else {
        SetOamHelper1(oam, info.x, @truncate(y), 0x6c, (info.flags & 0x30) | 8, 2);
    }
}

pub export fn SpriteDraw_Shadow(k: c_int, oam: *PrepOamCoordsRet) callconv(.c) void {
    SpriteDraw_Shadow_custom(k, oam, 10);
}

pub export fn SpriteDraw_SingleSmall(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var info: PrepOamCoordsRet = undefined;
    if (Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    const oam = GetOamCurPtr();
    oam[0].x = @truncate(info.x);
    if (info.y +% 0x10 < 0x100) {
        oam[0].y = @truncate(info.y);
        // sprite_type 0xEC (thrown item) is 236, one past the end of this
        // 236-entry table. The C read whatever followed it in memory, and
        // Sprite_EC_ThrownItem overwrites charnum on the very next line, so
        // that value never reaches the screen. Skip the lookup rather than
        // trapping; every in-range sprite type behaves exactly as before.
        const st: usize = vars.sprite_type[ki];
        if (st < tables.kSprite_PrepAndDrawSingleLarge_Tab1.len) {
            const idx: usize = @as(usize, tables.kSprite_PrepAndDrawSingleLarge_Tab1[st]) +
                vars.sprite_graphics[ki];
            oam[0].charnum = tables.kSprite_PrepAndDrawSingleLarge_Tab2[idx];
        }
        oam[0].flags = info.flags;
    }
    vars.bytewise_extended_oam[oamIndex(oam)] = @intFromBool(info.x >= 256);
    if (vars.sprite_flags3[ki] & 0x10 != 0)
        SpriteDraw_Shadow_custom(k, &info, 2);
}

pub export fn Sprite_DrawThinAndTall(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var info: PrepOamCoordsRet = undefined;
    if (Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    const oam = GetOamCurPtr();
    // Same one-past-the-end read as the other two draw routines. Unlike those,
    // the byte is used here rather than overwritten by the caller, so fall back
    // to 0 instead of skipping; no sprite type that reaches this routine is out
    // of range today, so the guard is defensive only.
    const st: usize = vars.sprite_type[ki];
    const base: usize = if (st < tables.kSprite_PrepAndDrawSingleLarge_Tab1.len)
        tables.kSprite_PrepAndDrawSingleLarge_Tab1[st]
    else
        0;
    const a = tables.kSprite_PrepAndDrawSingleLarge_Tab2[base + vars.sprite_graphics[ki]];
    SetOamHelper0(oam + 0, info.x, info.y +% 0, a +% 0x00, info.flags, 0);
    SetOamHelper0(oam + 1, info.x, info.y +% 8, a +% 0x10, info.flags, 0);
    if (vars.sprite_flags3[ki] & 0x10 != 0)
        SpriteDraw_Shadow(k, &info);
}

// ---------------------------------------------------------------------------
// Carry, throw and stun
// ---------------------------------------------------------------------------

pub export fn SpriteModule_Carried(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_room[ki] = @truncate(vars.overworld_area_index.*);
    if (vars.sprite_unk3[ki] != 3) {
        if (vars.sprite_delay_main[ki] == 0) {
            vars.sprite_delay_main[ki] = if (vars.sprite_C[ki] == 6) 8 else 4;
            vars.sprite_unk3[ki] +%= 1;
        }
    } else {
        vars.sprite_flags3[ki] &= ~@as(u8, 0x10);
    }

    const tt = vars.sprite_delay_aux4[ki] -% 1;
    const r0: u8 = @intFromBool(tt < 63 and (tt & 2) != 0);
    const j: usize = @as(usize, vars.link_direction_facing.*) * 2 + vars.sprite_unk3[ki];

    // The C does the 16-bit add by hand, propagating carries a byte at a time.
    const hx: i8 = tables.kSpriteHeld_X[j];
    const hx_lo: u8 = @bitCast(hx);
    const hx_hi: u8 = if (hx < 0) 255 else 0; // (uint8)((int)hx >> 8)
    const t0: i32 = @as(i32, loPtr(vars.link_x_coord).*) + @as(i32, hx_lo);
    const t1: i32 = @as(i32, @as(u8, @truncate(@as(u32, @bitCast(t0))))) + ((t0 >> 8) & 1) + @as(i32, r0);
    const t2: i32 = @as(i32, hiPtr(vars.link_x_coord).*) + ((t1 >> 8) & 1) + ((t0 >> 8) & 1) + @as(i32, hx_hi);
    vars.sprite_x_lo[ki] = @truncate(@as(u32, @bitCast(t1)));
    vars.sprite_x_hi[ki] = @truncate(@as(u32, @bitCast(t2)));

    vars.sprite_z[ki] = tables.kSpriteHeld_Z[j];
    const an: usize = if (vars.link_animation_steps.* < 6) vars.link_animation_steps.* else 0;
    const z = vars.link_z_coord.* +% 1 +% tables.kSpriteHeld_ZForFrame[an];
    Sprite_SetY(k, vars.link_y_coord.* +% 8 -% z);
    vars.sprite_floor[ki] = vars.link_is_on_lower_level.* & 1;
    CarriedSprite_CheckForThrow(k);
    Sprite_Get16BitCoords(k);
    if (vars.sprite_unk4[ki] != 11) {
        SpriteActive_Main(k);
        if (vars.sprite_delay_aux4[ki] == 1) {
            vars.sprite_state[ki] = 9;
            vars.sprite_B[ki] = 0;
            vars.sprite_delay_aux4[ki] = 96;
            vars.sprite_z_vel[ki] = 32;
            vars.sprite_flags3[ki] |= 0x10;
            vars.link_picking_throw_state.* = 2;
        }
    } else {
        SpriteStunned_Main_Func1(k);
    }
}

pub export fn CarriedSprite_CheckForThrow(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.main_module_index.* == 14)
        return;

    if (vars.player_near_pit_state.* != 2) {
        const tt = (vars.link_auxiliary_state.* & 1) | vars.link_is_in_deep_water.* |
            vars.link_is_bunny_mirror.* | vars.link_pose_for_item.* |
            (if (vars.link_disable_sprite_damage.* != 0) @as(u8, 0) else vars.link_incapacitated_timer.*);
        if (tt == 0) {
            if (vars.sprite_unk3[ki] != 3 or
                (vars.filtered_joypad_H.* | vars.filtered_joypad_L.*) & 0x80 == 0)
                return;
            vars.filtered_joypad_L.* &= 0x7f;
        }
    }

    misc.SpriteSfx_QueueSfx3WithPan(k, 0x13);
    vars.link_picking_throw_state.* = 2;
    vars.sprite_state[ki] = vars.sprite_unk4[ki];
    vars.sprite_z_vel[ki] = 0;
    vars.sprite_unk3[ki] = 0;
    vars.sprite_flags3[ki] = (vars.sprite_flags3[ki] & ~@as(u8, 0x10)) |
        (tables.kSpriteInit_Flags3[vars.sprite_type[ki]] & 0x10);
    const j: usize = vars.link_direction_facing.* >> 1;
    vars.sprite_x_vel[ki] = @bitCast(tables.kSpriteHeld_Throw_Xvel[j]);
    vars.sprite_y_vel[ki] = @bitCast(tables.kSpriteHeld_Throw_Yvel[j]);
    vars.sprite_z_vel[ki] = tables.kSpriteHeld_Throw_Zvel[j];
    vars.sprite_delay_aux4[ki] = 0;
}

pub export fn SpriteModule_Stunned(k: c_int) callconv(.c) void {
    SpriteStunned_MainEx(k, false);
}

pub export fn ThrownSprite_TileAndSpriteInteraction(k: c_int) callconv(.c) void {
    SpriteStunned_MainEx(k, true);
}

pub export fn Sprite_Func8(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_state[ki] = 1;
    vars.sprite_delay_main[ki] = 0x1f;
    vars.sound_effect_1.* = 0;
    misc.SpriteSfx_QueueSfx2WithPan(k, 0x20);
}

pub export fn Sprite_Func22(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sound_effect_1.* = misc.Sprite_CalculateSfxPan(k) | 0x28;
    vars.sprite_state[ki] = 3;
    vars.sprite_delay_main[ki] = 15;
    vars.sprite_ai_state[ki] = 0;
    _ = misc.GetRandomNumber(); // wtf
    vars.sprite_flags2[ki] = 3;
}

pub export fn ThrowableScenery_InteractWithSpritesAndTiles(k: c_int) callconv(.c) void {
    Sprite_MoveXY(k);
    if (vars.sprite_E[@intCast(k)] == 0)
        _ = Sprite_CheckTileCollision(k);
    ThrownSprite_TileAndSpriteInteraction(k);
}

pub export fn ThrownSprite_CheckDamageToSprites(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_delay_aux4[ki] != 0 or (vars.sprite_x_vel[ki] | vars.sprite_y_vel[ki]) == 0)
        return;
    var i: isize = 15;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        const mixed: u8 = @truncate(@as(u32, @bitCast(@as(i32, @intCast(i)))) ^ @as(u32, vars.frame_counter.*));
        if (@as(c_int, @intCast(i)) != vars.cur_object_index.* and
            vars.sprite_type[ki] != 0xd2 and
            vars.sprite_state[u] >= 9 and
            ((mixed & 3) | vars.sprite_ignore_projectile[u] | vars.sprite_hit_timer[u]) == 0 and
            vars.sprite_floor[ki] == vars.sprite_floor[u])
            ThrownSprite_CheckDamageToSingleSprite(k, @intCast(i));
    }
}

pub export fn ThrownSprite_CheckDamageToSingleSprite(k: c_int, j: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const ji: usize = @intCast(j);
    var hb: SpriteHitBox = undefined;
    hb.r0_xlo = vars.sprite_x_lo[ki];
    hb.r8_xhi = vars.sprite_x_hi[ki];
    hb.r2 = 15;
    const t: i32 = @as(i32, vars.sprite_y_lo[ki]) - @as(i32, vars.sprite_z[ki]);
    const u: i32 = (t & 0xff) + 8;
    hb.r1_ylo = @truncate(@as(u32, @bitCast(u)));
    hb.r9_yhi = @truncate(@as(u32, @bitCast(@as(i32, vars.sprite_y_hi[ki]) + (u >> 8) - @intFromBool(t < 0))));
    hb.r3 = 8;
    Sprite_SetupHitBox(j, &hb);
    if (!CheckIfHitBoxesOverlap(&hb))
        return;
    if (vars.sprite_type[ji] == 0x3f) {
        Sprite_PlaceWeaponTink(k);
    } else {
        const a: c_int = if (vars.sprite_type[ki] == 0xec and vars.sprite_C[ki] == 2 and
            vars.player_is_indoors.* == 0) 1 else 3;
        Ancilla_CheckDamageToSprite_preset(j, a);

        vars.sprite_x_recoil[ji] = vars.sprite_x_vel[ki] *% 2;
        vars.sprite_y_recoil[ji] = vars.sprite_y_vel[ki] *% 2;
        vars.sprite_delay_aux4[ki] = 16;
    }
    Sprite_ApplyRicochet(k);
}

pub export fn Sprite_ApplyRicochet(k: c_int) callconv(.c) void {
    Sprite_InvertSpeed_XY(k);
    Sprite_HalveSpeed_XY(k);
    ThrowableScenery_TransmuteIfValid(k);
}

pub export fn ThrowableScenery_TransmuteIfValid(k: c_int) callconv(.c) void {
    if (vars.sprite_type[@intCast(k)] != 0xec)
        return;
    vars.repulsespark_timer.* = 0;
    ThrowableScenery_TransmuteToDebris(k);
}

pub export fn ThrowableScenery_TransmuteToDebris(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const g = vars.sprite_graphics[ki];
    if (g != 0) {
        loPtr(vars.dung_secrets_unk1).* = g;
        Sprite_SpawnSecret(k);
        loPtr(vars.dung_secrets_unk1).* = 0;
    }
    const a: usize = if (vars.player_is_indoors.* != 0) 0 else vars.sprite_C[ki];
    vars.sound_effect_1.* = 0;
    misc.SpriteSfx_QueueSfx2WithPan(k, tables.kSprite_Func21_Sfx[a]);
    Sprite_ScheduleForBreakage(k);
}

pub export fn Sprite_ScheduleForBreakage(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_delay_main[ki] = 31;
    vars.sprite_state[ki] = 6;
    vars.sprite_flags2[ki] +%= 4;
}

pub export fn Sprite_HalveSpeed_XY(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.sprite_x_vel[i] = @bitCast(@as(i8, @bitCast(vars.sprite_x_vel[i])) >> 1);
    vars.sprite_y_vel[i] = @bitCast(@as(i8, @bitCast(vars.sprite_y_vel[i])) >> 1);
}

pub export fn Sprite_SpawnLeapingFish(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, 0xd2, &info);
    if (j < 0)
        return;
    Sprite_SetSpawnedCoordinates(j, &info);
    const ji: usize = @intCast(j);
    vars.sprite_ai_state[ji] = 2;
    vars.sprite_delay_main[ji] = 48;
    if (vars.sprite_type[@intCast(k)] == 0xd2)
        vars.sprite_A[ji] = 0xd2;
}

pub export fn SpriteStunned_Main_Func1(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    SpriteActive_Main(k);
    if (vars.sprite_unk5[ki] != 0) {
        if (vars.sprite_delay_main[ki] < 32)
            vars.sprite_oam_flags[ki] = (vars.sprite_oam_flags[ki] & 0xf1) | 4;
        const kk: u32 = @bitCast(k);
        const tt: u8 = @truncate((kk << 4) ^ @as(u32, vars.frame_counter.*));
        if ((tt | vars.submodule_index.*) &
            tables.kSpriteStunned_Main_Func1_Masks[vars.sprite_delay_main[ki] >> 4] != 0)
            return;
        const x: u16 = @bitCast(@as(i16, tables.kSparkleGarnish_XY[misc.GetRandomNumber() & 3]));
        const y: u16 = @bitCast(@as(i16, tables.kSparkleGarnish_XY[misc.GetRandomNumber() & 3]));
        _ = Sprite_GarnishSpawn_Sparkle(k, x, y);
    } else {
        if ((vars.frame_counter.* & 1) | vars.submodule_index.* | vars.flag_unk1.* != 0)
            return;
        const tt = vars.sprite_stunned[ki];
        if (tt != 0) {
            vars.sprite_stunned[ki] -%= 1;
            if (tt < 0x38) {
                vars.sprite_x_vel[ki] = if (tt & 1 != 0) 0 -% @as(u8, 8) else 8;
                Sprite_MoveX(k);
            }
            return;
        }
        vars.sprite_state[ki] = 9;
        vars.sprite_x_recoil[ki] = 0;
        vars.sprite_y_recoil[ki] = 0;
    }
}

pub export fn SpriteModule_Poof(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    // Frozen sprite pulverized by hammer
    if (vars.sprite_delay_main[ki] == 0) {
        if (vars.sprite_type[ki] == 0xd and vars.sprite_head_dir[ki] != 0) {
            // buzz blob?
            const bakx = Sprite_GetX(k);
            PrepareEnemyDrop(k, 0xd);
            Sprite_SetX(k, bakx);
            vars.sprite_z_vel[ki] = 0;
            vars.sprite_ignore_projectile[ki] = 0;
        } else {
            if (vars.sprite_die_action[ki] == 0) {
                ForcePrizeDrop(k, 2, 2);
            } else {
                Sprite_DoTheDeath(k);
            }
        }
    } else {
        var info: PrepOamCoordsRet = undefined;
        if (Sprite_PrepOamCoordOrDoubleRet(k, &info))
            return;
        var oam = GetOamCurPtr();
        var j: isize = @as(isize, (vars.sprite_delay_main[ki] >> 1) & ~@as(u8, 3)) + 3;
        var i: isize = 3;
        while (i >= 0) : ({
            i -= 1;
            j -= 1;
            oam += 1;
        }) {
            const u: usize = @intCast(j);
            SetOamPlain(
                oam,
                @as(u8, @bitCast(tables.kSpritePoof_X[u])) +% loPtr(vars.dungmap_var7).*,
                @as(u8, @bitCast(tables.kSpritePoof_Y[u])) +% hiPtr(vars.dungmap_var7).*,
                tables.kSpritePoof_Char[u],
                tables.kSpritePoof_Flags[u],
                tables.kSpritePoof_Ext[u],
            );
        }
        Sprite_CorrectOamEntries(k, 3, 0xff);
    }
}

pub export fn Sprite_PrepOamCoord(k: c_int, ret: *PrepOamCoordsRet) callconv(.c) void {
    _ = Sprite_PrepOamCoordOrDoubleRet(k, ret);
}

pub export fn Sprite_PrepOamCoordOrDoubleRet(k: c_int, ret: *PrepOamCoordsRet) callconv(.c) bool {
    const ki: usize = @intCast(k);
    vars.sprite_pause[ki] = 0;
    const x = vars.cur_sprite_x.* -% vars.BG2HOFS_copy2.*;
    const y = vars.cur_sprite_y.* -% vars.BG2VOFS_copy2.*;
    var out_of_bounds = false;
    R0().* = x;
    R2().* = y -% vars.sprite_z[ki];
    ret.flags = vars.sprite_oam_flags[ki] ^ vars.sprite_obj_prio[ki];
    ret.r4 = 0;
    const xs = zelda_rtl.spriteSideSpace();

    if ((x +% 0x40 +% xs.left) >= (0x170 + xs.left + xs.right) or
        ((y +% 0x40) >= 0x170 and vars.sprite_flags4[ki] & 0x20 == 0))
    {
        vars.sprite_pause[ki] +%= 1;
        if (vars.sprite_defl_bits[ki] & 0x80 == 0)
            Sprite_KillSelf(k);
        out_of_bounds = true;
    }
    ret.x = R0().*;
    ret.y = R2().*;
    loPtr(vars.dungmap_var7).* = @truncate(ret.x);
    hiPtr(vars.dungmap_var7).* = @truncate(ret.y);
    return out_of_bounds;
}

// ---------------------------------------------------------------------------
// Tile collision
// ---------------------------------------------------------------------------

pub export fn Sprite_CheckTileCollision2(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_wallcoll[ki] = 0;
    if (sign8(vars.sprite_flags4[ki]) or vars.dung_hdr_collision.* == 0) {
        Sprite_CheckTileCollisionSingleLayer(k);
        return;
    }
    vars.byte_7E0FB6.* = vars.sprite_floor[ki];
    vars.sprite_floor[ki] = 1;
    Sprite_CheckTileCollisionSingleLayer(k);
    if (vars.dung_hdr_collision.* == 4) {
        vars.sprite_floor[ki] = vars.byte_7E0FB6.*;
        return;
    }
    vars.sprite_floor[ki] = 0;
    Sprite_CheckTileCollisionSingleLayer(k);
    vars.byte_7FFABC[ki] = vars.sprite_tiletype.*;
}

pub export fn Sprite_CheckTileCollisionSingleLayer(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_flags2[ki] & 0x20 != 0) {
        if (Sprite_CheckTileProperty(k, 0x6a))
            vars.sprite_wallcoll[ki] +%= 1;
        return;
    }

    if (sign8(vars.sprite_flags4[ki]) or vars.dung_hdr_collision.* == 0) {
        if (vars.sprite_y_vel[ki] != 0)
            Sprite_CheckForTileInDirection_vertical(k, if (sign8(vars.sprite_y_vel[ki])) 0 else 1);
        if (vars.sprite_x_vel[ki] != 0)
            Sprite_CheckForTileInDirection_horizontal(k, if (sign8(vars.sprite_x_vel[ki])) 2 else 3);
    } else {
        Sprite_CheckForTileInDirection_vertical(k, 1);
        Sprite_CheckForTileInDirection_vertical(k, 0);
        Sprite_CheckForTileInDirection_horizontal(k, 3);
        Sprite_CheckForTileInDirection_horizontal(k, 2);
    }

    if (sign8(vars.sprite_flags5[ki]) or vars.sprite_z[ki] != 0)
        return;

    _ = Sprite_CheckTileProperty(k, 0x68);
    vars.sprite_I[ki] = vars.sprite_tiletype.*;
    const tt = vars.sprite_tiletype.*;
    if (tt == 0x1c) {
        if (vars.sort_sprites_setting.* != 0 and vars.sprite_state[ki] == 11)
            vars.sprite_floor[ki] = 1;
    } else if (tt == 0x20) {
        if (vars.sprite_flags[ki] & 1 != 0) {
            if (vars.player_is_indoors.* == 0) {
                Sprite_Func8(k);
            } else {
                vars.sprite_state[ki] = 5;
                if (vars.sprite_type[ki] == 0x13 or vars.sprite_type[ki] == 0x26) {
                    vars.sprite_oam_flags[ki] &= ~@as(u8, 1);
                    vars.sprite_delay_main[ki] = 63;
                } else {
                    vars.sprite_delay_main[ki] = 95;
                }
            }
        }
    } else if (tt == 0xc) {
        if (vars.byte_7FFABC[ki] == 0x1c) {
            SpriteFall_AdjustPosition(k);
            vars.sprite_wallcoll[ki] |= 0x20;
        }
    } else if (tt >= 0x68 and tt < 0x6c) {
        Sprite_ApplyConveyor(k, tt);
    } else if (tt == 8) {
        if (vars.dung_hdr_collision.* == 4)
            Sprite_ApplyConveyor(k, 0x6a);
    }
}

pub export fn Sprite_CheckForTileInDirection_horizontal(k: c_int, yy: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (!Sprite_CheckTileInDirection(k, yy))
        return;
    vars.sprite_wallcoll[ki] |= tables.kSprite_Func7_Tab[@intCast(yy)];
    if ((vars.sprite_subtype[ki] & 7) < 5) {
        const n: i8 = if (vars.sprite_F[ki] != 0) 3 else 1;
        SpriteAddXY(k, if (yy & 1 != 0) -@as(c_int, n) else n, 0);
    }
}

pub export fn Sprite_CheckForTileInDirection_vertical(k: c_int, yy: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (!Sprite_CheckTileInDirection(k, yy))
        return;
    vars.sprite_wallcoll[ki] |= tables.kSprite_Func7_Tab[@intCast(yy)];
    if ((vars.sprite_subtype[ki] & 7) < 5) {
        const n: i8 = if (vars.sprite_F[ki] != 0) 3 else 1;
        SpriteAddXY(k, 0, if (yy & 1 != 0) -@as(c_int, n) else n);
    }
}

pub export fn SpriteFall_AdjustPosition(k: c_int) callconv(.c) void {
    SpriteAddXY(k, vars.dung_floor_x_vel.*, vars.dung_floor_y_vel.*);
}

pub export fn Sprite_CheckTileInDirection(k: c_int, yy_in: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    const t = vars.sprite_flags[ki] & 0xf0;
    const yy = 2 * (@as(c_int, t >> 2) + yy_in);
    return Sprite_CheckTileProperty(k, yy);
}

pub export fn Sprite_CheckTileProperty(k: c_int, j_in: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    const j: usize = @intCast(j_in >> 1);
    var x: u16 = undefined;
    var y: u16 = undefined;
    var in_bounds: bool = undefined;

    const fx: u16 = @bitCast(@as(i16, tables.kSprite_Func5_X[j]));
    const fy: u16 = @bitCast(@as(i16, tables.kSprite_Func5_Y[j]));

    if (vars.player_is_indoors.* != 0) {
        x = ((vars.cur_sprite_x.* +% 8) & 0x1ff) +% fx -% 8;
        y = ((vars.cur_sprite_y.* +% 8) & 0x1ff) +% fy -% 8;
        in_bounds = (x < 0x200) and (y < 0x200);
    } else {
        x = vars.cur_sprite_x.* +% fx;
        y = vars.cur_sprite_y.* +% fy;
        in_bounds = (x -% vars.sprcoll_x_base.*) < vars.sprcoll_x_size.* and
            (y -% vars.sprcoll_y_base.*) < vars.sprcoll_y_size.*;
    }
    if (!in_bounds) {
        if (vars.sprite_flags2[ki] & 0x40 != 0) {
            vars.sprite_state[ki] = 0;
            return false;
        } else {
            return true;
        }
    }

    const b: usize = Sprite_GetTileAttribute(k, &x, y);

    if (vars.sprite_defl_bits[ki] & 8 != 0) {
        const a = tables.kSprite_SimplifiedTileAttr[b];
        if (a == 4) {
            if (vars.player_is_indoors.* == 0)
                vars.sprite_E[ki] = 4;
        } else if (a >= 1) {
            return if (vars.sprite_tiletype.* >= 0x10 and vars.sprite_tiletype.* < 0x14)
                Entity_CheckSlopedTileCollision(x, y)
            else
                true;
        }
        return false;
    }

    if (vars.sprite_flags5[ki] & 0x40 != 0) {
        const stype = vars.sprite_type[ki];
        if ((stype == 0xd2 or stype == 0x8a) and b == 9)
            return false;
        if ((stype == 0x94 and vars.sprite_E[ki] == 0) or stype == 0xe3 or
            stype == 0x8c or stype == 0x9a or stype == 0x81)
            return (b != 8) and (b != 9);
    }

    if (tables.kSprite_Func5_Tab3[b] == 0)
        return false;

    if (vars.sprite_tiletype.* >= 0x10 and vars.sprite_tiletype.* < 0x14)
        return Entity_CheckSlopedTileCollision(x, y);

    if (vars.sprite_tiletype.* == 0x44) {
        if (vars.sprite_F[ki] != 0 and !sign8(vars.sprite_give_damage[ki])) {
            // Some mothula bug fix because we changed damage class 4.
            if (vars.sprite_type[ki] == 0x88 and
                (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0)
            {
                if (vars.sprite_hit_timer[ki] == 0)
                    Ancilla_CheckDamageToSprite_preset(k, 6);
            } else {
                Ancilla_CheckDamageToSprite_preset(k, 4);
            }
            if (vars.sprite_hit_timer[ki] != 0) {
                vars.sprite_hit_timer[ki] = 153;
                vars.sprite_F[ki] = 0;
            }
        }
    } else if (vars.sprite_tiletype.* == 0x20) {
        return (vars.sprite_flags[ki] & 1 == 0) or (vars.sprite_F[ki] == 0);
    }
    return true;
}

pub export fn GetTileAttribute(floor: u8, x: *u16, y: u16) callconv(.c) u8 {
    var tiletype: u8 = undefined;
    if (vars.player_is_indoors.* != 0) {
        var t: usize = if (floor >= 1) 0x1000 else 0;
        t += (x.* & 0x1f8) >> 3;
        t += @as(usize, y & 0x1f8) << 3;
        tiletype = vars.dung_bg2_attr_table[t];
    } else {
        // the C mutates *x in place before the lookup
        x.* >>= 3;
        tiletype = tile_detect.Overworld_GetTileAttributeAtLocation(x.*, y);
    }
    vars.sprite_tiletype.* = tiletype;
    return tiletype;
}

pub export fn Sprite_GetTileAttribute(k: c_int, x: *u16, y: u16) callconv(.c) u8 {
    return GetTileAttribute(vars.sprite_floor[@intCast(k)], x, y);
}

pub export fn Entity_CheckSlopedTileCollision(x: u16, y: u16) callconv(.c) bool {
    const a: u8 = @truncate(y & 7);
    const r6: u8 = vars.sprite_tiletype.* -% 0x10;
    const b: i8 = tables.kSlopedTile[@as(usize, r6) * 8 + (x & 7)];
    // C promotes both to int, so this is a signed comparison.
    return if (r6 < 2) (@as(i32, b) >= @as(i32, a)) else (@as(i32, a) >= @as(i32, b));
}

// ---------------------------------------------------------------------------
// Movement and speed projection
// ---------------------------------------------------------------------------

pub export fn Sprite_MoveXY(k: c_int) callconv(.c) void {
    Sprite_MoveX(k);
    Sprite_MoveY(k);
}

pub export fn Sprite_MoveX(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    if (vars.sprite_x_vel[i] != 0) {
        const vel: i32 = @as(i32, @as(i8, @bitCast(vars.sprite_x_vel[i]))) << 4;
        const t: u32 = @as(u32, vars.sprite_x_subpixel[i]) +%
            (@as(u32, vars.sprite_x_lo[i]) << 8) +%
            (@as(u32, vars.sprite_x_hi[i]) << 16) +%
            @as(u32, @bitCast(vel));
        vars.sprite_x_subpixel[i] = @truncate(t);
        vars.sprite_x_lo[i] = @truncate(t >> 8);
        vars.sprite_x_hi[i] = @truncate(t >> 16);
    }
}

pub export fn Sprite_MoveY(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    if (vars.sprite_y_vel[i] != 0) {
        const vel: i32 = @as(i32, @as(i8, @bitCast(vars.sprite_y_vel[i]))) << 4;
        const t: u32 = @as(u32, vars.sprite_y_subpixel[i]) +%
            (@as(u32, vars.sprite_y_lo[i]) << 8) +%
            (@as(u32, vars.sprite_y_hi[i]) << 16) +%
            @as(u32, @bitCast(vel));
        vars.sprite_y_subpixel[i] = @truncate(t);
        vars.sprite_y_lo[i] = @truncate(t >> 8);
        vars.sprite_y_hi[i] = @truncate(t >> 16);
    }
}

pub export fn Sprite_MoveZ(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    const vel: i16 = @as(i16, @as(i8, @bitCast(vars.sprite_z_vel[i]))) << 4;
    const z: u16 = ((@as(u16, vars.sprite_z[i]) << 8) | vars.sprite_z_subpos[i]) +%
        @as(u16, @bitCast(vel));
    vars.sprite_z_subpos[i] = @truncate(z);
    vars.sprite_z[i] = @truncate(z >> 8);
}

/// The C walks a Bresenham-style division loop to split `vel` between the axes.
fn projectSpeed(below: PairU8, right: PairU8, vel_in: u8) ProjectSpeedRet {
    var r12: u8 = if (sign8(below.b)) 0 -% below.b else below.b;
    var r13: u8 = if (sign8(right.b)) 0 -% right.b else right.b;
    var tv: u8 = undefined;
    var swapped = false;
    if (r13 < r12) {
        swapped = true;
        tv = r12;
        r12 = r13;
        r13 = tv;
    }
    var vel = vel_in;
    var xvel: u8 = vel;
    var yvel: u8 = 0;
    tv = 0;
    while (true) {
        tv +%= r12;
        if (tv >= r13) {
            tv -%= r13;
            yvel +%= 1;
        }
        vel -%= 1;
        if (vel == 0) break;
    }
    if (swapped) {
        tv = xvel;
        xvel = yvel;
        yvel = tv;
    }
    return .{
        .x = if (right.a != 0) 0 -% xvel else xvel,
        .y = if (below.a != 0) 0 -% yvel else yvel,
        .xdiff = right.b,
        .ydiff = below.b,
    };
}

pub export fn Sprite_ProjectSpeedTowardsLink(k: c_int, vel: u8) callconv(.c) ProjectSpeedRet {
    if (vel == 0)
        return .{ .x = 0, .y = 0, .xdiff = 0, .ydiff = 0 };
    return projectSpeed(Sprite_IsBelowLink(k), Sprite_IsRightOfLink(k), vel);
}

pub export fn Sprite_ApplySpeedTowardsLink(k: c_int, vel: u8) callconv(.c) void {
    const pt = Sprite_ProjectSpeedTowardsLink(k, vel);
    const i: usize = @intCast(k);
    vars.sprite_x_vel[i] = pt.x;
    vars.sprite_y_vel[i] = pt.y;
}

pub export fn Sprite_ProjectSpeedTowardsLocation(k: c_int, x: u16, y: u16, vel: u8) callconv(.c) ProjectSpeedRet {
    if (vel == 0)
        return .{ .x = 0, .y = 0, .xdiff = 0, .ydiff = 0 };
    return projectSpeed(Sprite_IsBelowLocation(k, y), Sprite_IsRightOfLocation(k, x), vel);
}

pub export fn Sprite_DirectionToFaceLink(k: c_int, coords_out: ?*PointU8) callconv(.c) u8 {
    const below = Sprite_IsBelowLink(k);
    const right = Sprite_IsRightOfLink(k);
    const ym: u8 = if (sign8(below.b)) 0 -% below.b else below.b;
    vars.tmp_counter.* = ym;
    const xm: u8 = if (sign8(right.b)) 0 -% right.b else right.b;
    if (coords_out) |co| {
        co.x = right.b;
        co.y = below.b;
    }
    return if (xm >= ym) right.a else below.a +% 2;
}

pub export fn Sprite_IsRightOfLink(k: c_int) callconv(.c) PairU8 {
    const x = vars.link_x_coord.* -% Sprite_GetX(k);
    return .{ .a = @intFromBool(sign16(x)), .b = @truncate(x) };
}

pub export fn Sprite_IsBelowLink(k: c_int) callconv(.c) PairU8 {
    const ki: usize = @intCast(k);
    const t: i32 = @as(i32, loPtr(vars.link_y_coord).*) + 8;
    const u: i32 = (t & 0xff) + @as(i32, vars.sprite_z[ki]);
    const v: i32 = (u & 0xff) - @as(i32, vars.sprite_y_lo[ki]);
    const w: i32 = @as(i32, hiPtr(vars.link_y_coord).*) - @as(i32, vars.sprite_y_hi[ki]) - @intFromBool(v < 0);
    const y: u8 = @truncate(@as(u32, @bitCast((w & 0xff) + (t >> 8) + (u >> 8))));
    return .{ .a = @intFromBool(sign8(y)), .b = @truncate(@as(u32, @bitCast(v))) };
}

pub export fn Sprite_IsRightOfLocation(k: c_int, x: u16) callconv(.c) PairU8 {
    const xv = x -% Sprite_GetX(k);
    return .{ .a = @intFromBool(sign16(xv)), .b = @truncate(xv) };
}

pub export fn Sprite_IsBelowLocation(k: c_int, y: u16) callconv(.c) PairU8 {
    const yv = y -% Sprite_GetY(k);
    return .{ .a = @intFromBool(sign16(yv)), .b = @truncate(yv) };
}

pub export fn Sprite_DirectionToFaceLocation(k: c_int, x: u16, y: u16) callconv(.c) u8 {
    const below = Sprite_IsBelowLocation(k, y);
    const right = Sprite_IsRightOfLocation(k, x);
    const ym: u8 = if (sign8(below.b)) 0 -% below.b else below.b;
    vars.tmp_counter.* = ym;
    const xm: u8 = if (sign8(right.b)) 0 -% right.b else right.b;
    return if (xm >= ym) right.a else below.a +% 2;
}

// ---------------------------------------------------------------------------
// Damage
// ---------------------------------------------------------------------------

pub export fn Guard_ParrySwordAttacks(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.link_is_on_lower_level.* != vars.sprite_floor[ki] or
        (vars.link_incapacitated_timer.* | vars.link_auxiliary_state.*) != 0 or
        sign8(vars.sprite_hit_timer[ki]))
        return;
    var hb: SpriteHitBox = undefined;
    Sprite_DoHitBoxesFast(k, &hb);
    if (vars.link_position_mode.* & 0x10 != 0 or vars.player_oam_y_offset.* == 0x80) {
        Sprite_AttemptDamageToLinkWithCollisionCheck(k);
        return;
    }
    Player_SetupActionHitBox(&hb);
    if (sign8(vars.button_b_frames.*) or !CheckIfHitBoxesOverlap(&hb)) {
        Sprite_SetupHitBox(k, &hb);
        if (!CheckIfHitBoxesOverlap(&hb)) {
            Sprite_AttemptDamageToLinkWithCollisionCheck(k);
        } else {
            Sprite_AttemptZapDamage(k);
        }
        return;
    }
    if (vars.sprite_type[ki] != 0x6a)
        vars.sprite_F[ki] = tables.kSprite_Func1_Tab[misc.GetRandomNumber() & 7];
    vars.link_incapacitated_timer.* = tables.kSprite_Func1_Tab2[misc.GetRandomNumber() & 7];
    const pt = Sprite_ProjectSpeedTowardsLink(k, if (sign8(vars.button_b_frames.* -% 9)) 32 else 24);
    vars.sprite_x_recoil[ki] = 0 -% pt.x;
    vars.sprite_y_recoil[ki] = 0 -% pt.y;
    Sprite_ApplyRecoilToLink(k, if (sign8(vars.button_b_frames.* -% 9)) 8 else 16);
    Link_PlaceWeaponTink();
    vars.set_when_damaging_enemies.* = 0x90;
}

pub export fn Sprite_AttemptZapDamage(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var a = vars.sprite_type[ki];
    // The C reassigns `a` inside the condition via `a = link_sword_type`.
    var cond = false;
    if (a == 0x7a) {
        cond = true;
    } else if (a == 0xd) {
        a = vars.link_sword_type.*;
        cond = a < 4;
    } else if (a == 0x24 or a == 0x23) {
        cond = vars.sprite_delay_main[ki] != 0;
    }
    if (cond and vars.sprite_state[ki] == 9) {
        if (vars.countdown_for_blink.* == 0) {
            vars.sprite_delay_aux1[ki] = 64;
            vars.link_electrocute_on_touch.* = 64;
            Sprite_AttemptDamageToLinkPlusRecoil(k);
        }
    } else {
        const pt = Sprite_ProjectSpeedTowardsLink(k, if (sign8(vars.button_b_frames.* -% 9)) 0x50 else 0x40);
        vars.sprite_x_recoil[ki] = 0 -% pt.x;
        vars.sprite_y_recoil[ki] = 0 -% pt.y;
        Sprite_CalculateSwordDamage(k);
    }
}

pub export fn Ancilla_CheckDamageToSprite_preset(k: c_int, a: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (a == 15 and vars.sprite_z[ki] != 0)
        return;

    if (a != 0 and a != 7) {
        Sprite_Func15(k, a);
        return;
    }
    Sprite_Func15(k, a);
    if (vars.sprite_give_damage[ki] != 0 or vars.repulsespark_timer.* != 0)
        return;
    // Called when hitting enemy which is frozen
    vars.repulsespark_timer.* = 5;
    const j: usize = vars.byte_7E0FB6.*;
    vars.repulsespark_x_lo.* = vars.ancilla_x_lo[j] +% 4;
    vars.repulsespark_y_lo.* = vars.ancilla_y_lo[j];
    vars.repulsespark_floor_status.* = vars.link_is_on_lower_level.*;
    vars.sound_effect_1.* = 0;
    misc.SpriteSfx_QueueSfx2WithPan(k, 5);
}

pub export fn Sprite_Func15(k: c_int, a: c_int) callconv(.c) void {
    vars.damage_type_determiner.* = @truncate(@as(u32, @bitCast(a)));
    Sprite_ApplyCalculatedDamage(k, if (a == 8) 0x35 else 0x20);
}

pub export fn Sprite_CalculateSwordDamage(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_flags3[ki] & 0x40 != 0)
        return;
    vars.sprite_unk1[ki] = vars.link_is_running.*;
    var a = vars.link_sword_type.* -% 1;
    if (vars.link_is_running.* == 0)
        a |= if (sign8(vars.button_b_frames.*)) @as(u8, 4) else if (sign8(vars.button_b_frames.* -% 9)) @as(u8, 0) else 8;
    // With no sword this index runs off the end of the table. Sword type 0 and
    // the 0xff the blacksmiths leave behind while they temper it both decrement
    // into the high end, and a dash reaches here without a swing, so bumping
    // something while the smiths have your sword lands on entry 254 of 12.
    //
    // The C reads past the table and feeds the result to the two lookups in
    // Sprite_ApplyCalculatedDamage, which are indexed by this value and would
    // run off their own ends in turn, so there is no faithful value to copy.
    // Take the weakest entry, which is what a dash with no sword amounts to.
    // Entry 0 is also the only safe floor: a determiner of 0 selects the
    // kEnemyDamages row holding 255, 252 and 251, which are not damage amounts.
    const idx: usize = if (a < tables.kSprite_Func14_Damage.len) a else 0;
    vars.damage_type_determiner.* = tables.kSprite_Func14_Damage[idx];
    if (vars.link_item_in_hand.* & 10 != 0)
        vars.damage_type_determiner.* = 3;
    vars.link_sword_delay_timer.* = 4;
    vars.set_when_damaging_enemies.* = 16;
    Sprite_ApplyCalculatedDamage(k, 0x9d);
}

pub export fn Sprite_ApplyCalculatedDamage(k: c_int, a: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_flags3[ki] & 0x40 != 0 or vars.sprite_type[ki] >= 0xD8)
        return;
    const dtd: usize = vars.damage_type_determiner.*;
    const sub = vars.enemy_damage_data[(@as(usize, vars.sprite_type[ki]) * 16) | dtd];
    const dmg = tables.kEnemyDamages[(dtd * 8) | sub];
    Sprite_GiveDamage(k, dmg, @truncate(@as(u32, @bitCast(a))));
}

pub export fn Sprite_GiveDamage(k: c_int, dmg: u8, r0_hit_timer: u8) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (dmg == 249) {
        Sprite_Func18(k, 0xe3);
        return;
    }
    if (dmg == 250) {
        Sprite_Func18(k, 0x8f);
        vars.sprite_ai_state[ki] = 2;
        vars.sprite_z_vel[ki] = 32;
        vars.sprite_oam_flags[ki] = 8;
        vars.sprite_F[ki] = 0;
        vars.sprite_hit_timer[ki] = 0;
        vars.sprite_health[ki] = 0;
        vars.sprite_bump_damage[ki] = 1;
        vars.sprite_flags5[ki] = 1;
        return;
    }
    if (dmg >= vars.sprite_give_damage[ki])
        vars.sprite_give_damage[ki] = dmg;

    // `goto flag4` skips the whole middle and lands on the tail below.
    var to_flag4 = false;
    if (dmg == 0) {
        if (vars.damage_type_determiner.* != 10) {
            if (vars.sprite_flags[ki] & 4 != 0) {
                to_flag4 = true;
            } else {
                vars.link_sword_delay_timer.* = 0;
            }
        }
        if (!to_flag4) {
            vars.sprite_hit_timer[ki] = 0;
            vars.sprite_give_damage[ki] = 0;
            return;
        }
    }

    if (!to_flag4) {
        if (dmg >= 254 and vars.sprite_state[ki] == 11) {
            vars.sprite_hit_timer[ki] = 0;
            vars.sprite_give_damage[ki] = 0;
            return;
        }
        if (vars.sprite_type[ki] == 0x9a and vars.sprite_give_damage[ki] < 0xf0) {
            vars.sprite_state[ki] = 9;
            vars.sprite_ai_state[ki] = 4;
            vars.sprite_delay_main[ki] = 15;
            misc.SpriteSfx_QueueSfx2WithPan(k, 0x28);
            return;
        }
        if (vars.sprite_type[ki] == 0x1b) {
            misc.SpriteSfx_QueueSfx2WithPan(k, 5);
            Sprite_ScheduleForBreakage(k);
            Sprite_PlaceWeaponTink(k);
            return;
        }
        vars.sprite_hit_timer[ki] = r0_hit_timer;
        if (vars.sprite_type[ki] != 0x92 or vars.sprite_C[ki] >= 3) {
            const sfx: u8 = if (vars.sprite_flags[ki] & 2 != 0)
                0x21
            else if (vars.sprite_flags5[ki] & 0x10 != 0)
                0x1c
            else
                8;
            vars.sound_effect_2.* = sfx | misc.Sprite_CalculateSfxPan(k);
        }
    }

    // flag4:
    const stype = vars.sprite_type[ki];
    vars.sprite_F[ki] = if (vars.damage_type_determiner.* >= 13)
        0
    else if (stype == 9)
        20
    else if (stype == 0x53 or stype == 0x18)
        11
    else
        15;
}

pub export fn Sprite_Func18(k: c_int, new_type: u8) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_type[ki] = new_type;
    SpritePrep_LoadProperties(k);
    Sprite_SpawnPoofGarnish(k);
    vars.sound_effect_2.* = 0;
    misc.SpriteSfx_QueueSfx3WithPan(k, 0x32);
    vars.sprite_hit_timer[ki] = 0;
    vars.sprite_give_damage[ki] = 0;
}

pub export fn Sprite_MiniMoldorm_Recoil(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_state[ki] < 9)
        return;
    vars.tmp_counter.* = vars.sprite_state[ki];

    const dmg = vars.sprite_give_damage[ki];
    if (dmg == 253) {
        vars.sprite_give_damage[ki] = 0;
        misc.SpriteSfx_QueueSfx3WithPan(k, 9);
        vars.sprite_state[ki] = 7;
        vars.sprite_delay_main[ki] = 0x70;
        vars.sprite_flags2[ki] +%= 2;
        vars.sprite_give_damage[ki] = 0;
        return;
    }

    if (dmg >= 251) {
        vars.sprite_give_damage[ki] = 0;
        if (vars.sprite_state[ki] == 11)
            return;
        vars.sprite_unk5[ki] = @intFromBool(dmg == 254);
        if (vars.sprite_unk5[ki] != 0) {
            vars.sprite_defl_bits[ki] |= 8;
            vars.sprite_flags5[ki] &= ~@as(u8, 0x80);
            misc.SpriteSfx_QueueSfx2WithPan(k, 15);
            vars.sprite_z_vel[ki] = 24;
            vars.sprite_bump_damage[ki] &= ~@as(u8, 0x80);
            Sprite_ZeroVelocity_XY(k);
        }
        vars.sprite_state[ki] = 11;
        vars.sprite_delay_main[ki] = 64;
        vars.sprite_stunned[ki] = tables.kHitTimer24StunValues[dmg +% 5];
        if (vars.sprite_type[ki] == 0x23)
            vars.sprite_type[ki] = 0x24;
        return;
    }

    const t: i32 = @as(i32, vars.sprite_health[ki]) - @as(i32, vars.sprite_give_damage[ki]);
    vars.sprite_health[ki] = @truncate(@as(u32, @bitCast(t)));
    vars.sprite_give_damage[ki] = 0;
    if (t > 0)
        return;

    if (vars.sprite_die_action[ki] == 0) {
        if (vars.sprite_state[ki] == 11)
            vars.sprite_die_action[ki] = 3;
        if (vars.sprite_unk1[ki] != 0) {
            vars.sprite_unk1[ki] = 0;
            vars.sprite_flags5[ki] = 0;
        }
    }

    const stype = vars.sprite_type[ki];
    if (stype != 0x1b)
        misc.SpriteSfx_QueueSfx3WithPan(k, 9);

    if (stype == 0x40) {
        vars.save_ow_event_info[loPtr(vars.overworld_screen_index).*] |= 0x40;
    } else if (stype == 0xec) {
        if (vars.sprite_C[ki] == 2)
            ThrowableScenery_TransmuteToDebris(k);
        return;
    }

    if (vars.sprite_state[ki] == 10) {
        vars.link_state_bits.* = 0;
        vars.link_picking_throw_state.* = 0;
    }
    vars.sprite_state[ki] = 6;

    // 0 = fall out, 1 = out_common, 2 = out_common2
    var jump: u8 = 0;
    if (stype == 0xc) {
        Sprite_Func3(k);
    } else if (stype == 0x92) {
        Sprite_KillFriends();
        vars.sprite_delay_main[ki] = 255;
        jump = 1;
    } else if (stype == 0xcb) {
        vars.sprite_ai_state[ki] = 128;
        vars.sprite_delay_main[ki] = 128;
        vars.sprite_state[ki] = 9;
        jump = 1;
    } else if (stype == 0xcc or stype == 0xcd) {
        vars.sprite_ai_state[ki] = 128;
        vars.sprite_delay_main[ki] = 96;
        vars.sprite_state[ki] = 9;
        jump = 1;
    } else if (stype == 0x53) {
        vars.sprite_delay_main[ki] = 35;
        vars.sprite_hit_timer[ki] = 0;
        jump = 2;
    } else if (stype == 0x54) {
        vars.sprite_ai_state[ki] = 5;
        vars.sprite_delay_main[ki] = 0xc0;
        vars.sprite_hit_timer[ki] = 0xc0;
        jump = 1;
    } else if (stype == 0x9) {
        vars.sprite_ai_state[ki] = 3;
        vars.sprite_delay_aux4[ki] = 160;
        vars.sprite_state[ki] = 9;
        jump = 1;
    } else if (stype == 0x7a) {
        Sprite_KillFriends();
        vars.sprite_state[ki] = 9;
        vars.sprite_ignore_projectile[ki] = 9;
        if (vars.is_in_dark_world.* == 0) {
            vars.sprite_ai_state[ki] = 10;
            vars.sprite_delay_main[ki] = 255;
            vars.sprite_z_vel[ki] = 32;
        } else {
            vars.sprite_delay_main[ki] = 255;
            vars.sprite_ai_state[ki] = 8;
            vars.sprite_ai_state[1] = 9;
            vars.sprite_ai_state[2] = 9;
            vars.sprite_graphics[1] = 0;
            vars.sprite_graphics[2] = 0;
        }
        jump = 1;
    } else if (stype == 0x23 and vars.sprite_C[ki] == 0) {
        vars.sprite_ai_state[ki] = 2;
        vars.sprite_delay_main[ki] = 32;
        vars.sprite_state[ki] = 9;
        vars.sprite_hit_timer[ki] = 0;
    } else if (stype == 0xf) {
        vars.sprite_hit_timer[ki] = 0;
        vars.sprite_delay_main[ki] = 15;
    } else if (vars.sprite_flags[ki] & 2 == 0) {
        vars.sprite_delay_main[ki] = if (vars.sprite_hit_timer[ki] & 0x80 != 0) 31 else 15;
        vars.sprite_flags2[ki] +%= 4;
        if (vars.tmp_counter.* == 11)
            vars.sprite_flags5[ki] = 1;
    } else {
        if (stype != 0xa2)
            Sprite_KillFriends();
        vars.sprite_state[ki] = 4;
        vars.sprite_A[ki] = 0;
        vars.sprite_delay_main[ki] = 255;
        vars.sprite_hit_timer[ki] = 255;
        jump = 1;
    }
    if (jump == 1) {
        // out_common:
        vars.flag_block_link_menu.* +%= 1;
        jump = 2;
    }
    if (jump == 2) {
        // out_common2:
        vars.sound_effect_2.* = 0;
        misc.SpriteSfx_QueueSfx3WithPan(k, 0x22);
    }
}

pub export fn Sprite_Func3(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_state[ki] = 6;
    vars.sprite_delay_main[ki] = 31;
    vars.sprite_flags2[ki] = 3;
}

// ---------------------------------------------------------------------------
// Damage to and from Link
// ---------------------------------------------------------------------------

pub export fn Sprite_CheckDamageToLink(k: c_int) callconv(.c) bool {
    if (vars.link_disable_sprite_damage.* != 0)
        return false;
    return Sprite_CheckDamageToPlayer_1(k);
}

pub export fn Sprite_CheckDamageToPlayer_1(k: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    const kk: u32 = @bitCast(k);
    const mixed: u8 = @truncate(kk ^ @as(u32, vars.frame_counter.*));
    if (((mixed & 3) | vars.sprite_hit_timer[ki]) != 0)
        return false;
    return Sprite_CheckDamageToLink_same_layer(k);
}

pub export fn Sprite_CheckDamageToLink_same_layer(k: c_int) callconv(.c) bool {
    if (vars.link_is_on_lower_level.* != vars.sprite_floor[@intCast(k)])
        return false;
    return Sprite_CheckDamageToLink_ignore_layer(k);
}

pub export fn Sprite_CheckDamageToLink_ignore_layer(k: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    var carry: bool = undefined;
    if (vars.sprite_flags4[ki] != 0) {
        var hitbox: SpriteHitBox = undefined;
        Link_SetupHitBox(&hitbox);

        // Set hitbox to the sword hitbox if the item type is an absorbable
        if (vars.sprite_type[ki] >= 0xd8 and vars.sprite_type[ki] <= 0xe6 and
            (features.enhanced_features0.* & features.kFeatures0_CollectItemsWithSword) != 0)
            Link_UpdateHitBoxWithSword(&hitbox);

        Sprite_SetupHitBox(k, &hitbox);
        carry = CheckIfHitBoxesOverlap(&hitbox);
    } else {
        carry = Sprite_SetupHitBox00(k);
    }

    if (sign8(vars.sprite_flags2[ki]))
        return carry;

    if (!carry or vars.link_auxiliary_state.* != 0)
        return false;

    // `goto if_3` jumps into the body of the shield-facing test below.
    var do_if3 = false;
    if (vars.link_is_bunny_mirror.* != 0 or sign8(vars.link_state_bits.*) or
        (vars.sprite_flags5[ki] & 0x20) == 0 or vars.link_shield_type.* == 0)
    {
        do_if3 = true;
    } else {
        vars.sprite_state[ki] = 0;
        const t: u8 = if (vars.button_b_frames.* != 0)
            tables.kSpriteDamage_Tab2[vars.link_direction_facing.* >> 1]
        else
            vars.link_direction_facing.*;
        if (t != tables.kSpriteDamage_Tab3[vars.sprite_D[ki]])
            do_if3 = true;
    }

    if (do_if3) {
        // if_3:
        Sprite_AttemptDamageToLinkPlusRecoil(k);
        if (vars.sprite_type[ki] == 0xc)
            Sprite_Func3(k);
        return true;
    }

    misc.SpriteSfx_QueueSfx2WithPan(k, 6);
    Sprite_PlaceRupulseSpark_2(k);
    if (vars.sprite_type[ki] == 0x95) {
        misc.SpriteSfx_QueueSfx3WithPan(k, 0x26);
        return false;
    } else if (vars.sprite_type[ki] == 0x9B) {
        Sprite_Invert_XY_Speeds(k);
        vars.sprite_D[ki] ^= 1;
        vars.sprite_ai_state[ki] +%= 1;
        vars.sprite_state[ki] = 9;
        return false;
    } else if (vars.sprite_type[ki] == 0x1B) { // arrow
        Sprite_ScheduleForBreakage(k);
        return false; // unk ret val
    } else if (vars.sprite_type[ki] == 0xc) {
        Sprite_Func3(k);
        return true;
    } else {
        return false; // unk ret val
    }
}

pub export fn Sprite_SetupHitBox00(k: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    return (vars.link_x_coord.* -% vars.cur_sprite_x.* +% 11) < 23 and
        (vars.link_y_coord.* -% vars.cur_sprite_y.* +% vars.sprite_z[ki] +% 16) < 24;
}

pub export fn Sprite_ReturnIfLifted(k: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    if ((vars.submodule_index.* | vars.button_b_frames.* | vars.flag_unk1.*) != 0 or
        vars.sprite_floor[ki] != vars.link_is_on_lower_level.*)
        return false;
    var j: isize = 15;
    while (j >= 0) : (j -= 1) {
        if (vars.sprite_state[@intCast(j)] == 10)
            return false;
    }
    if (vars.sprite_type[ki] != 0xb and vars.sprite_type[ki] != 0x4a and
        (vars.sprite_x_vel[ki] | vars.sprite_y_vel[ki]) != 0)
        return false;
    if (vars.link_is_running.* != 0)
        return false;
    return Sprite_ReturnIfLiftedPermissive(k);
}

pub export fn Sprite_ReturnIfLiftedPermissive(k: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    if (vars.link_is_running.* != 0)
        return false;
    if ((vars.flag_is_sprite_to_pick_up_cached.* -% 1) != vars.cur_object_index.*) {
        var hb: SpriteHitBox = undefined;
        Link_SetupHitBox_conditional(&hb);
        Sprite_SetupHitBox(k, &hb);
        if (CheckIfHitBoxesOverlap(&hb)) {
            const v: u8 = @truncate(@as(u32, @bitCast(k + 1)));
            vars.flag_is_sprite_to_pick_up.* = v;
            vars.byte_7E0FB2.* = v;
        }
        return false;
    } else {
        vars.filtered_joypad_L.* = 0;
        vars.sprite_E[ki] = 0;
        misc.SpriteSfx_QueueSfx2WithPan(k, 0x1d);
        vars.sprite_unk4[ki] = vars.sprite_state[ki];
        vars.sprite_state[ki] = 10;
        vars.sprite_delay_main[ki] = 16;
        vars.sprite_unk3[ki] = 0;
        vars.sprite_I[ki] = 0;
        vars.link_direction_facing.* =
            tables.kSprite_ReturnIfLifted_Dirs[Sprite_DirectionToFaceLink(k, null)];
        return true;
    }
}

pub export fn Sprite_CheckDamageFromLink(k: c_int) callconv(.c) u8 {
    const ki: usize = @intCast(k);
    if (vars.sprite_hit_timer[ki] & 0x80 != 0 or
        vars.sprite_floor[ki] != vars.link_is_on_lower_level.* or
        vars.player_oam_y_offset.* == 0x80)
        return 0;

    var hb: SpriteHitBox = undefined;
    Player_SetupActionHitBox(&hb);
    Sprite_SetupHitBox(k, &hb);
    if (!CheckIfHitBoxesOverlap(&hb))
        return 0;

    vars.set_when_damaging_enemies.* = 0;
    if (vars.link_position_mode.* & 0x10 != 0)
        return kCheckDamageFromPlayer_Carry | kCheckDamageFromPlayer_Ne;

    if (vars.link_item_in_hand.* & 10 != 0) {
        if (vars.sprite_type[ki] >= 0xd6)
            return 0;
        if (vars.sprite_state[ki] == 11 and vars.sprite_unk5[ki] != 0) {
            vars.sprite_state[ki] = 2;
            vars.sprite_delay_main[ki] = 32;
            vars.sprite_flags2[ki] = (vars.sprite_flags2[ki] & 0xe0) | 3;
            misc.SpriteSfx_QueueSfx2WithPan(k, 0x1f);
            return kCheckDamageFromPlayer_Carry | kCheckDamageFromPlayer_Ne;
        }
    }

    // 0 = fall through, 1 = `goto is_many`, 2 = `goto getting_out`
    var jump: u8 = 0;
    const stype = vars.sprite_type[ki];
    if (stype == 0x7b) {
        if (!sign8(vars.button_b_frames.* -% 9))
            return 0;
    } else if (stype == 9) {
        if (vars.sprite_A[ki] == 0) {
            Sprite_ApplyRecoilToLink(k, 48);
            vars.set_when_damaging_enemies.* = 144;
            vars.link_incapacitated_timer.* = 16;
            misc.SpriteSfx_QueueSfx2WithPan(k, 0x21);
            vars.sprite_delay_aux1[ki] = 48;
            vars.sound_effect_2.* = misc.Sprite_CalculateSfxPan(k) |
                @as(u8, if ((features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0) 0x32 else 0);
            Link_PlaceWeaponTink();
            return kCheckDamageFromPlayer_Carry;
        }
    } else if (stype == 0x92) {
        jump = if (vars.sprite_C[ki] >= 3) 1 else 2;
    } else if (stype == 0x26 or stype == 0x13 or stype == 2) {
        const cond = (stype == 0x13 and
            tables.kSpriteDamage_Tab3[vars.sprite_D[ki]] == vars.link_direction_facing.*) or
            (stype == 2);
        Sprite_AttemptZapDamage(k);
        Sprite_ApplyRecoilToLink(k, 32);
        vars.set_when_damaging_enemies.* = 16;
        vars.link_incapacitated_timer.* = 16;
        if (cond) {
            vars.sprite_hit_timer[ki] = 0;
            Link_PlaceWeaponTink();
        }
        return 0; // what return value?
    } else if (stype == 0xcb or stype == 0xcd or stype == 0xcc or stype == 0xd6 or
        stype == 0xd7 or stype == 0xce or stype == 0x54)
    {
        jump = 1;
    }

    if (jump == 1) {
        // is_many:
        Sprite_ApplyRecoilToLink(k, 32);
        vars.set_when_damaging_enemies.* = 144;
        vars.link_incapacitated_timer.* = 16;
    }

    if (jump != 2) {
        if (vars.sprite_defl_bits[ki] & 4 == 0) {
            Sprite_AttemptZapDamage(k);
            return kCheckDamageFromPlayer_Carry;
        }
    }

    // getting_out:
    if (vars.set_when_damaging_enemies.* == 0) {
        Sprite_ApplyRecoilToLink(k, 4);
        vars.link_incapacitated_timer.* = 16;
        vars.set_when_damaging_enemies.* = 16;
    }
    Link_PlaceWeaponTink();
    return kCheckDamageFromPlayer_Carry;
}

// ---------------------------------------------------------------------------
// Hitboxes and recoil
// ---------------------------------------------------------------------------

pub export fn Sprite_AttemptDamageToLinkWithCollisionCheck(k: c_int) callconv(.c) void {
    const kk: u32 = @bitCast(k);
    if ((@as(u8, @truncate(kk ^ @as(u32, vars.frame_counter.*))) & 1) != 0)
        return;
    var hb: SpriteHitBox = undefined;
    Sprite_DoHitBoxesFast(k, &hb);
    Link_SetupHitBox_conditional(&hb);
    if (CheckIfHitBoxesOverlap(&hb))
        Sprite_AttemptDamageToLinkPlusRecoil(k);
}

pub export fn Sprite_AttemptDamageToLinkPlusRecoil(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if ((vars.countdown_for_blink.* | vars.link_disable_sprite_damage.*) != 0)
        return;
    vars.link_incapacitated_timer.* = 19;
    Sprite_ApplyRecoilToLink(k, 24);
    vars.link_auxiliary_state.* = 1;
    const idx: usize = 3 * @as(usize, vars.sprite_bump_damage[ki] & 0xf) + vars.link_armor.*;
    vars.link_give_damage.* = @bitCast(tables.kPlayerDamages[idx]);
    if (vars.sprite_type[ki] == 0x61 and vars.sprite_C[ki] != 0) {
        vars.link_actual_vel_x.* = vars.sprite_x_vel[ki] *% 2;
        vars.link_actual_vel_y.* = vars.sprite_y_vel[ki] *% 2;
    }
}

pub export fn Player_SetupActionHitBox(hb: *SpriteHitBox) callconv(.c) void {
    if (vars.link_is_running.* != 0) {
        const j: usize = vars.link_direction_facing.* >> 1;
        const xoff: u16 = @as(u16, tables.kPlayerActionBoxRun_XLo[j]) |
            (@as(u16, tables.kPlayerActionBoxRun_XHi[j]) << 8);
        const yoff: u16 = @as(u16, tables.kPlayerActionBoxRun_YLo[j]) |
            (@as(u16, tables.kPlayerActionBoxRun_YHi[j]) << 8);
        const x = vars.link_x_coord.* +% xoff;
        const y = vars.link_y_coord.* +% yoff;
        hb.r0_xlo = @truncate(x);
        hb.r8_xhi = @truncate(x >> 8);
        hb.r1_ylo = @truncate(y);
        hb.r9_yhi = @truncate(y >> 8);
        hb.r2 = 16;
        hb.r3 = 16;
    } else {
        var t: usize = 0;
        if (vars.link_item_in_hand.* & 10 == 0 and vars.link_position_mode.* & 0x10 == 0) {
            if (sign8(vars.button_b_frames.*)) {
                const x = vars.link_x_coord.* -% 14;
                const y = vars.link_y_coord.* -% 10;
                hb.r0_xlo = @truncate(x);
                hb.r8_xhi = @truncate(x >> 8);
                hb.r1_ylo = @truncate(y);
                hb.r9_yhi = @truncate(y >> 8);
                hb.r2 = 44;
                hb.r3 = 45;
                return;
            } else if (tables.kPlayer_SetupActionHitBox_Tab4[vars.button_b_frames.*] != 0) {
                hb.r8_xhi = 0x80;
                return;
            }
            t = @as(usize, vars.link_direction_facing.*) * 8 + vars.button_b_frames.* + 1;
        }
        const dx: i8 = @bitCast(@as(u8, @bitCast(tables.kPlayer_SetupActionHitBox_X[t])) +%
            vars.player_oam_x_offset.*);
        const dy: i8 = @bitCast(@as(u8, @bitCast(tables.kPlayer_SetupActionHitBox_Y[t])) +%
            vars.player_oam_y_offset.*);
        const x = vars.link_x_coord.* +% @as(u16, @bitCast(@as(i16, dx)));
        const y = vars.link_y_coord.* +% @as(u16, @bitCast(@as(i16, dy)));
        hb.r0_xlo = @truncate(x);
        hb.r8_xhi = @truncate(x >> 8);
        hb.r1_ylo = @truncate(y);
        hb.r9_yhi = @truncate(y >> 8);
        hb.r2 = @bitCast(tables.kPlayer_SetupActionHitBox_W[t]);
        hb.r3 = @bitCast(tables.kPlayer_SetupActionHitBox_H[t]);
    }
}

pub export fn Link_UpdateHitBoxWithSword(hb: *SpriteHitBox) callconv(.c) void {
    if (vars.link_spin_attack_step_counter.* != 0 or sign8(vars.button_b_frames.*) or
        tables.kPlayer_SetupActionHitBox_Tab4[vars.button_b_frames.*] != 0)
        return;
    const t: usize = @as(usize, vars.link_direction_facing.*) * 8 + vars.button_b_frames.* + 1;
    const dx: i8 = @bitCast(@as(u8, @bitCast(tables.kPlayer_SetupActionHitBox_X[t])) +%
        vars.player_oam_x_offset.*);
    const dy: i8 = @bitCast(@as(u8, @bitCast(tables.kPlayer_SetupActionHitBox_Y[t])) +%
        vars.player_oam_y_offset.*);
    var x = vars.link_x_coord.* +% @as(u16, @bitCast(@as(i16, dx)));
    var y = vars.link_y_coord.* +% @as(u16, @bitCast(@as(i16, dy)));
    var r: c_int = undefined;
    // Reduce size of hitbox if 'too' big.
    hb.r2 = @bitCast(tables.kPlayer_SetupActionHitBox_W[t]);
    if (@as(c_int, hb.r2) - 2 >= 0) {
        r = IntMin(6, @as(c_int, hb.r2) - 2);
        hb.r2 -%= @truncate(@as(u32, @bitCast(r)));
        x +%= @truncate(@as(u32, @bitCast(r >> 1)));
    }
    hb.r3 = @bitCast(tables.kPlayer_SetupActionHitBox_H[t]);
    if (@as(c_int, hb.r3) - 2 >= 0) {
        r = IntMin(6, @as(c_int, hb.r3) - 2);
        hb.r3 -%= @truncate(@as(u32, @bitCast(r)));
        y +%= @truncate(@as(u32, @bitCast(r >> 1)));
    }
    hb.r0_xlo = @truncate(x);
    hb.r8_xhi = @truncate(x >> 8);
    hb.r1_ylo = @truncate(y);
    hb.r9_yhi = @truncate(y >> 8);
}

pub export fn Sprite_DoHitBoxesFast(k: c_int, hb: *SpriteHitBox) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (hiPtr(vars.dungmap_var8).* == 0x80) {
        hb.r10_spr_xhi = 0x80;
        return;
    }
    var t: u16 = Sprite_GetX(k) +%
        @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(hiPtr(vars.dungmap_var8).*)))));
    hb.r4_spr_xlo = @truncate(t);
    hb.r10_spr_xhi = @truncate(t >> 8);
    t = Sprite_GetY(k) +%
        @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(loPtr(vars.dungmap_var8).*)))));
    hb.r5_spr_ylo = @truncate(t);
    hb.r11_spr_yhi = @truncate(t >> 8);
    const sz: u8 = if (vars.sprite_type[ki] == 0x6a) 16 else 3;
    hb.r6_spr_xsize = sz;
    hb.r7_spr_ysize = sz;
}

pub export fn Sprite_ApplyRecoilToLink(k: c_int, vel: u8) callconv(.c) void {
    const pt = Sprite_ProjectSpeedTowardsLink(k, vel);
    vars.link_actual_vel_x.* = pt.x;
    vars.link_actual_vel_y.* = pt.y;
    vars.link_actual_vel_z.* = vel >> 1;
    g_ram[0xc7] = vars.link_actual_vel_z.*;
    vars.link_z_coord.* = 0;
}

pub export fn Link_PlaceWeaponTink() callconv(.c) void {
    if (vars.repulsespark_timer.* != 0)
        return;
    vars.repulsespark_timer.* = 5;
    var t: c_int = @as(c_int, loPtr(vars.link_x_coord).*) + @as(c_int, vars.player_oam_x_offset.*);
    vars.repulsespark_x_lo.* = @truncate(@as(u32, @bitCast(t)));
    t = @as(c_int, loPtr(vars.link_y_coord).*) + @as(c_int, vars.player_oam_y_offset.*) + (t >> 8); // carry wtf
    vars.repulsespark_y_lo.* = @truncate(@as(u32, @bitCast(t)));
    vars.repulsespark_floor_status.* = vars.link_is_on_lower_level.*;
    vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | 5;
}

pub export fn Sprite_PlaceWeaponTink(k: c_int) callconv(.c) void {
    if (vars.repulsespark_timer.* != 0)
        return;
    misc.SpriteSfx_QueueSfx2WithPan(k, 5);
    Sprite_PlaceRupulseSpark_2(k);
}

pub export fn Sprite_PlaceRupulseSpark_2(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const x = Sprite_GetX(k) -% vars.BG2HOFS_copy2.*;
    const y = Sprite_GetY(k) -% vars.BG2VOFS_copy2.*;
    if ((x & ~@as(u16, 0xff)) != 0 or (y & ~@as(u16, 0xff)) != 0)
        return;
    vars.repulsespark_x_lo.* = vars.sprite_x_lo[ki];
    vars.repulsespark_y_lo.* = vars.sprite_y_lo[ki];
    vars.repulsespark_timer.* = 5;
    vars.repulsespark_floor_status.* = vars.sprite_floor[ki];
}

pub export fn Link_SetupHitBox_conditional(hb: *SpriteHitBox) callconv(.c) void {
    if (vars.link_disable_sprite_damage.* != 0) {
        hb.r9_yhi = 0x80;
    } else {
        Link_SetupHitBox(hb);
    }
}

pub export fn Link_SetupHitBox(hb: *SpriteHitBox) callconv(.c) void {
    hb.r2 = 8;
    hb.r3 = 8;
    const x = vars.link_x_coord.* +% 4;
    hb.r0_xlo = @truncate(x);
    hb.r8_xhi = @truncate(x >> 8);
    const y = vars.link_y_coord.* +% 8;
    hb.r1_ylo = @truncate(y);
    hb.r9_yhi = @truncate(y >> 8);
}

pub export fn Sprite_SetupHitBox(k: c_int, hb: *SpriteHitBox) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (sign8(vars.sprite_z[ki])) {
        hb.r10_spr_xhi = 0x80;
        return;
    }
    const i: usize = vars.sprite_flags4[ki] & 0x1f;
    var t: c_int = undefined;
    var u: c_int = undefined;

    t = @as(c_int, vars.sprite_x_lo[ki]) + @as(c_int, @as(u8, @bitCast(tables.kSpriteHitbox_XLo[i])));
    hb.r4_spr_xlo = @truncate(@as(u32, @bitCast(t)));
    t = @as(c_int, vars.sprite_x_hi[ki]) + @as(c_int, @as(u8, @bitCast(tables.kSpriteHitbox_XHi[i]))) + (t >> 8);
    hb.r10_spr_xhi = @truncate(@as(u32, @bitCast(t)));

    t = @as(c_int, vars.sprite_y_lo[ki]) + @as(c_int, @as(u8, @bitCast(tables.kSpriteHitbox_YLo[i])));
    u = t >> 8;
    t = (t & 0xff) - @as(c_int, vars.sprite_z[ki]);
    hb.r5_spr_ylo = @truncate(@as(u32, @bitCast(t)));
    t = @as(c_int, vars.sprite_y_hi[ki]) - @intFromBool(t < 0);
    hb.r11_spr_yhi = @truncate(@as(u32, @bitCast(t + u + @as(c_int, @as(u8, @bitCast(tables.kSpriteHitbox_YHi[i]))))));

    hb.r6_spr_xsize = tables.kSpriteHitbox_XSize[i];
    hb.r7_spr_ysize = tables.kSpriteHitbox_YSize[i];
}

/// Returns the carry flag
pub export fn CheckIfHitBoxesOverlap(hb: *SpriteHitBox) callconv(.c) bool {
    var t: c_int = undefined;
    var r15: u8 = undefined;
    var r12: u8 = undefined;

    if (hb.r8_xhi == 0x80 or hb.r10_spr_xhi == 0x80)
        return false;

    t = @as(c_int, hb.r5_spr_ylo) - @as(c_int, hb.r1_ylo);
    r15 = @truncate(@as(u32, @bitCast(t + @as(c_int, hb.r7_spr_ysize))));
    r12 = @truncate(@as(u32, @bitCast(@as(c_int, hb.r11_spr_yhi) - @as(c_int, hb.r9_yhi) - @intFromBool(t < 0))));
    t = @as(c_int, r12) + (((t & 0xff) + 0x80) >> 8);
    if (t & 0xff != 0)
        return (t >= 0x100);
    if ((hb.r3 +% hb.r7_spr_ysize) < r15)
        return false;

    t = @as(c_int, hb.r4_spr_xlo) - @as(c_int, hb.r0_xlo);
    r15 = @truncate(@as(u32, @bitCast(t + @as(c_int, hb.r6_spr_xsize))));
    r12 = @truncate(@as(u32, @bitCast(@as(c_int, hb.r10_spr_xhi) - @as(c_int, hb.r8_xhi) - @intFromBool(t < 0))));
    t = @as(c_int, r12) + (((t & 0xff) + 0x80) >> 8);
    if (t & 0xff != 0)
        return (t >= 0x100);
    if ((hb.r2 +% hb.r6_spr_xsize) < r15)
        return false;

    return true;
}

pub export fn Oam_AllocateDeferToPlayer(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_floor[ki] != vars.link_is_on_lower_level.*)
        return;
    const right = Sprite_IsRightOfLink(k);
    if ((right.b +% 0x10) >= 0x20)
        return;
    const below = Sprite_IsBelowLink(k);
    if ((below.b +% 0x20) >= 0x48)
        return;
    const nslots: u8 = ((vars.sprite_flags2[ki] & 0x1f) +% 1) << 2;
    if (below.a != 0) {
        _ = Oam_AllocateFromRegionC(nslots);
    } else {
        _ = Oam_AllocateFromRegionB(nslots);
    }
}

// ---------------------------------------------------------------------------
// Death and prize drops
// ---------------------------------------------------------------------------

pub export fn SpriteModule_Die(k: c_int) callconv(.c) void {
    SpriteDeath_MainEx(k, false);
}

pub export fn Sprite_DoTheDeath(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const stype = vars.sprite_type[ki];
    // This is how Vitreous knows whether to come out of his slime pool
    if (stype == 0xBE)
        vars.sprite_G[0] -%= 1;

    if (stype == 0xaa and vars.sprite_E[ki] != 0) {
        const bak = vars.sprite_subtype[ki];
        PrepareEnemyDrop(k, tables.kPikitDropItems[vars.sprite_E[ki] - 1]);
        vars.sprite_subtype[ki] = bak;
        if (bak == 1) {
            vars.sprite_oam_flags[ki] = 9;
            vars.sprite_flags3[ki] = 0xf0;
        }
        vars.sprite_head_dir[ki] +%= 1;
        return;
    }

    // Resets the music in the village when the crazy green guards are killed.
    if (stype == 0x45 and vars.sram_progress_indicator.* == 2 and
        loPtr(vars.overworld_area_index).* == 0x18)
        vars.music_control.* = 7;

    const drop_item = vars.sprite_die_action[ki];
    if (drop_item != 0) {
        vars.sprite_subtype[ki] = vars.sprite_N[ki];
        vars.sprite_N[ki] = 255;
        const arg: u8 = if (drop_item == 1) 0xe4 else if (drop_item == 3) 0xd9 else 0xe5;
        PrepareEnemyDrop(k, arg);
        return;
    }

    var prize = vars.sprite_flags5[ki] & 0xf;
    if (prize != 0) {
        prize -%= 1;
        const luck = vars.item_drop_luck.*;
        if (luck != 0) {
            vars.luck_kill_counter.* +%= 1;
            if (vars.luck_kill_counter.* >= 10)
                vars.item_drop_luck.* = 0;
            if (luck == 1) {
                ForcePrizeDrop(k, prize, 1);
                return;
            }
        } else {
            if ((misc.GetRandomNumber() & tables.kPrizeMasks[prize]) == 0) {
                ForcePrizeDrop(k, prize, prize);
                return;
            }
        }
    }
    vars.sprite_state[ki] = 0;
    SpriteDeath_Func4(k);
}

pub export fn ForcePrizeDrop(k: c_int, prize_in: u8, slot: u8) callconv(.c) void {
    const s: usize = slot;
    const prize: usize = (@as(usize, prize_in) * 8) | vars.prizes_arr1[s];
    vars.prizes_arr1[s] = (vars.prizes_arr1[s] +% 1) & 7;
    PrepareEnemyDrop(k, tables.kPrizeItems[prize]);
}

pub export fn PrepareEnemyDrop(k: c_int, item: u8) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_type[ki] = item;
    if (item == 0xe5) {
        SpritePrep_BigKey_load_graphics(k);
    } else if (item == 0xe4) {
        SpritePrep_KeySetItemDrop(k);
    }

    vars.sprite_state[ki] = 9;
    const zbak = vars.sprite_z[ki];
    SpritePrep_LoadProperties(k);
    vars.sprite_ignore_projectile[ki] +%= 1;

    const pz = tables.kPrizeZ[vars.sprite_type[ki] -% 0xd8];
    vars.sprite_z_vel[ki] = pz & 0xf0;
    Sprite_SetX(k, Sprite_GetX(k) +% (pz & 0xf));
    vars.sprite_z[ki] = zbak;
    vars.sprite_delay_aux4[ki] = 21;
    vars.sprite_stunned[ki] = 255;
    SpriteDeath_Func4(k);
}

pub export fn SpriteDeath_Func4(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_type[ki] == 0xa2 and Sprite_CheckIfScreenIsClear())
        _ = Ancilla_SpawnFallingPrize(4);
    Sprite_ManuallySetDeathFlagUW(k);
    vars.num_sprites_killed.* +%= 1;
    if (vars.sprite_type[ki] == 0x40) {
        // evil barrier
        vars.sprite_state[ki] = 9;
        vars.sprite_graphics[ki] = 4;
        SpriteDeath_MainEx(k, true);
    }
}

pub export fn SpriteDeath_DrawPoof(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.dung_hdr_collision.* == 4)
        vars.sprite_obj_prio[ki] = 0x30;
    var info: PrepOamCoordsRet = undefined;
    if (Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = GetOamCurPtr();
    const r12: u8 = (vars.sprite_flags3[ki] & 0x20) >> 3;
    var i: isize = @as(isize, (vars.sprite_delay_main[ki] & 0x1c) ^ 0x1c) + 3;
    var n: isize = 3;
    while (true) {
        const u: usize = @intCast(i);
        if (tables.kPerishOverlay_Char[u] != 0) {
            oam[0].charnum = tables.kPerishOverlay_Char[u];
            oam[0].y = hiPtr(vars.dungmap_var7).* -% r12 +%
                @as(u8, @bitCast(tables.kPerishOverlay_Y[u]));
            oam[0].x = loPtr(vars.dungmap_var7).* -% r12 +%
                @as(u8, @bitCast(tables.kPerishOverlay_X[u]));
            oam[0].flags = (info.flags & 0x30) | tables.kPerishOverlay_Flags[u];
        }
        oam += 1;
        i -= 1;
        n -= 1;
        if (n < 0) break;
    }
    Sprite_CorrectOamEntries(k, 3, 0);
}

pub export fn SpriteModule_Fall2(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var delay = vars.sprite_delay_main[ki];
    if (delay == 0) {
        vars.sprite_state[ki] = 0;
        Sprite_ManuallySetDeathFlagUW(k);
        return;
    }

    if (delay >= 0x40) {
        if (vars.sprite_oam_flags[ki] != 5) {
            if ((delay & 7) | vars.submodule_index.* | vars.flag_unk1.* == 0)
                misc.SpriteSfx_QueueSfx3WithPan(k, 0x31);
            SpriteActive_Main(k);
            var info: PrepOamCoordsRet = undefined;
            if (Sprite_PrepOamCoordOrDoubleRet(k, &info))
                return;
            Sprite_DrawDistress_custom(info.x, info.y -% 8, delay +% 20);
            return;
        }
        vars.sprite_delay_main[ki] = 63;
        delay = 63;
    }

    if (delay == 61)
        misc.SpriteSfx_QueueSfx2WithPan(k, 0x20);

    const j: usize = delay >> 1;

    if (vars.sprite_type[ki] == 0x26 or vars.sprite_type[ki] == 0x13) {
        vars.sprite_graphics[ki] = tables.kSpriteFall_Tab2[j];
        SpriteDraw_FallingHelmaBeetle(k);
    } else {
        var t = tables.kSpriteFall_Tab1[j];
        if (t < 12)
            t +%= @bitCast(tables.kSpriteFall_Tab4[vars.sprite_D[ki]]);
        vars.sprite_graphics[ki] = t;
        SpriteDraw_FallingHumanoid(k);
    }
    if ((vars.frame_counter.* & tables.kSpriteFall_Tab3[vars.sprite_delay_main[ki] >> 3]) |
        vars.submodule_index.* != 0)
        return;
    _ = Sprite_CheckTileProperty(k, 0x68);
    if (vars.sprite_tiletype.* != 0x20) {
        vars.sprite_y_recoil[ki] = 0;
        vars.sprite_x_recoil[ki] = 0;
    }
    vars.sprite_y_vel[ki] = @bitCast(@as(i8, @bitCast(vars.sprite_y_recoil[ki])) >> 2);
    vars.sprite_x_vel[ki] = @bitCast(@as(i8, @bitCast(vars.sprite_x_recoil[ki])) >> 2);
    Sprite_MoveXY(k);
}

pub export fn SpriteDraw_FallingHelmaBeetle(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var info: PrepOamCoordsRet = undefined;
    var src: [*]const DrawMultipleData =
        @as([*]const DrawMultipleData, &kSpriteDrawFall0Data) + vars.sprite_graphics[ki];
    if (vars.sprite_type[ki] == 0x13)
        src += 6;
    Sprite_DrawMultiple(k, src, 1, &info);
}

pub export fn SpriteDraw_FallingHumanoid(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var info: PrepOamCoordsRet = undefined;
    if (Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;

    const q: usize = vars.sprite_graphics[ki];
    var oam = GetOamCurPtr();
    var n: isize = if (q < 12 and (q & 3) == 0) 3 else 0;
    const nn = n;
    while (true) {
        const i: usize = q * 4 + @as(usize, @intCast(n));
        SetOamPlain(
            oam,
            @truncate(info.x +% @as(u16, @bitCast(@as(i16, tables.kSpriteDrawFall1_X[i])))),
            @truncate(info.y +% @as(u16, @bitCast(@as(i16, tables.kSpriteDrawFall1_Y[i])))),
            tables.kSpriteDrawFall1_Char[i],
            info.flags ^ tables.kSpriteDrawFall1_Flags[i],
            tables.kSpriteDrawFall1_Ext[i],
        );
        oam += 1;
        n -= 1;
        if (n < 0) break;
    }
    Sprite_CorrectOamEntries(k, @intCast(nn), 0xff);
}

pub export fn Sprite_CorrectOamEntries(k: c_int, n_in: c_int, islarge: u8) callconv(.c) void {
    var oam = GetOamCurPtr();
    var extp: [*]u8 = @ptrCast(&g_ram[vars.oam_ext_cur_ptr.*]);
    const spr_x = Sprite_GetX(k);
    const spr_y = Sprite_GetY(k);
    const scrollx: u8 = @truncate(spr_x -% vars.BG2HOFS_copy2.*);
    const scrolly: u8 = @truncate(spr_y -% vars.BG2VOFS_copy2.*);
    var n = n_in;
    while (true) {
        const dx: i8 = @bitCast(oam[0].x -% scrollx);
        const dy: i8 = @bitCast(oam[0].y -% scrolly);
        const x = spr_x +% @as(u16, @bitCast(@as(i16, dx)));
        const y = spr_y +% @as(u16, @bitCast(@as(i16, dy)));
        const ext: u8 = if (sign8(islarge)) (extp[0] & 2) else islarge;
        extp[0] = ext +% @intFromBool((x -% vars.BG2HOFS_copy2.*) >= 0x100);
        if ((y +% 0x10 -% vars.BG2VOFS_copy2.*) >= 0x100)
            oam[0].y = 0xf0;
        oam += 1;
        extp += 1;
        n -= 1;
        if (n < 0) break;
    }
}

// ---------------------------------------------------------------------------
// Recoil, spawn bookkeeping and slot initialization
// ---------------------------------------------------------------------------

pub export fn Sprite_ReturnIfRecoiling(k: c_int) callconv(.c) bool {
    const ki: usize = @intCast(k);
    if (vars.sprite_F[ki] == 0)
        return false;
    if (vars.sprite_F[ki] & 0x7f == 0) {
        vars.sprite_F[ki] = 0;
        return false;
    }
    const yvbak = vars.sprite_y_vel[ki];
    const xvbak = vars.sprite_x_vel[ki];
    vars.sprite_F[ki] -%= 1;
    if (vars.sprite_F[ki] == 0 and
        ((vars.sprite_x_recoil[ki] +% 0x20) >= 0x40 or (vars.sprite_y_recoil[ki] +% 0x20) >= 0x40))
        vars.sprite_F[ki] = 144;

    const i = vars.sprite_F[ki];
    if (!sign8(i) and
        (vars.frame_counter.* & tables.kSprite2_ReturnIfRecoiling_Masks[i >> 2]) == 0)
    {
        vars.sprite_y_vel[ki] = vars.sprite_y_recoil[ki];
        vars.sprite_x_vel[ki] = vars.sprite_x_recoil[ki];
        const t = Sprite_CheckTileCollision(k) & 0xf;
        if (!sign8(vars.sprite_bump_damage[ki]) and t != 0) {
            if (t < 4) {
                vars.sprite_x_recoil[ki] = 0;
                vars.sprite_x_vel[ki] = 0;
            } else {
                vars.sprite_y_recoil[ki] = 0;
                vars.sprite_y_vel[ki] = 0;
            }
        } else {
            Sprite_MoveXY(k);
        }
    }
    vars.sprite_y_vel[ki] = yvbak;
    vars.sprite_x_vel[ki] = xvbak;
    return vars.sprite_type[ki] != 0x7a;
}

pub export fn Sprite_CheckIfLinkIsBusy() callconv(.c) bool {
    if ((vars.link_auxiliary_state.* | vars.link_pose_for_item.* |
        (vars.link_state_bits.* & 0x80)) != 0)
        return true;
    var i: isize = 4;
    while (i >= 0) : (i -= 1) {
        if (vars.ancilla_type[@intCast(i)] == 0x27)
            return true;
    }
    return false;
}

pub export fn Sprite_SetSpawnedCoordinates(k: c_int, info: *SpriteSpawnInfo) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_x_lo[ki] = @truncate(info.r0_x);
    vars.sprite_x_hi[ki] = @truncate(info.r0_x >> 8);
    vars.sprite_y_lo[ki] = @truncate(info.r2_y);
    vars.sprite_y_hi[ki] = @truncate(info.r2_y >> 8);
    vars.sprite_z[ki] = info.r4_z;
}

pub export fn Sprite_CheckIfScreenIsClear() callconv(.c) bool {
    var i: isize = 15;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        if (vars.sprite_state[u] != 0 and vars.sprite_flags4[u] & 0x40 == 0) {
            const x = Sprite_GetX(@intCast(i)) -% vars.BG2HOFS_copy2.*;
            const y = Sprite_GetY(@intCast(i)) -% vars.BG2VOFS_copy2.*;
            if (x < 256 and y < 256)
                return false;
        }
    }
    return Sprite_CheckIfOverlordsClear();
}

pub export fn Sprite_CheckIfRoomIsClear() callconv(.c) bool {
    var i: isize = 15;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        if (vars.sprite_state[u] != 0 and vars.sprite_flags4[u] & 0x40 == 0)
            return false;
    }
    return Sprite_CheckIfOverlordsClear();
}

pub export fn Sprite_CheckIfOverlordsClear() callconv(.c) bool {
    var i: isize = 7;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        if (vars.overlord_type[u] == 0x14 or vars.overlord_type[u] == 0x18)
            return false;
    }
    return true;
}

pub export fn Sprite_InitializeMirrorPortal() callconv(.c) void {
    var k: isize = 15;
    while (k >= 0) : (k -= 1) {
        const u: usize = @intCast(k);
        if (vars.sprite_state[u] != 0 and vars.sprite_type[u] == 0x6c)
            vars.sprite_state[u] = 0;
    }

    var info: SpriteSpawnInfo = undefined;
    var j = Sprite_SpawnDynamically(0xff, 0x6c, &info);
    if (j < 0)
        j = 0;
    const ji: usize = @intCast(j);

    Sprite_SetX(j, @as(u16, vars.bird_travel_x_hi[15]) << 8 | vars.bird_travel_x_lo[15]);
    Sprite_SetY(j, (@as(u16, vars.bird_travel_y_hi[15]) << 8 | vars.bird_travel_y_lo[15]) +% 8);

    vars.sprite_floor[ji] = 0;
    vars.sprite_ignore_projectile[ji] = 1;
}

pub export fn Sprite_InitializeSlots() callconv(.c) void {
    var k: isize = 15;
    while (k >= 0) : (k -= 1) {
        const u: usize = @intCast(k);
        const st = vars.sprite_state[u];
        const ty = vars.sprite_type[u];
        if (st != 0) {
            if (st == 10) {
                if (ty != 0xec and ty != 0xd2) {
                    vars.link_picking_throw_state.* = 0;
                    vars.link_state_bits.* = 0;
                    vars.sprite_state[u] = 0;
                }
            } else {
                if (ty != 0x6c and vars.sprite_room[u] != loPtr(vars.overworld_area_index).*)
                    vars.sprite_state[u] = 0;
            }
        }
    }
    var j: isize = 7;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        if (vars.overlord_type[u] != 0 and
            vars.overlord_spawned_in_area[u] != loPtr(vars.overworld_area_index).*)
            vars.overlord_type[u] = 0;
    }
}

// ---------------------------------------------------------------------------
// Sprite loading: dungeon and overworld
// ---------------------------------------------------------------------------

pub export fn Dungeon_ResetSprites() callconv(.c) void {
    Dungeon_CacheTransSprites();
    vars.link_picking_throw_state.* = 0;
    vars.link_state_bits.* = 0;
    Sprite_DisableAll();
    vars.sprcoll_x_size.* = 0xffff;
    vars.sprcoll_y_size.* = 0xffff;
    const j = FindInWordArray(vars.dungeon_room_history, vars.dungeon_room_index2.*, 4);
    if (j < 0) {
        const blk = vars.dungeon_room_history[3];
        vars.dungeon_room_history[3] = vars.dungeon_room_history[2];
        vars.dungeon_room_history[2] = vars.dungeon_room_history[1];
        vars.dungeon_room_history[1] = vars.dungeon_room_history[0];
        vars.dungeon_room_history[0] = vars.dungeon_room_index2.*;
        if (blk != 0xffff)
            vars.sprite_where_in_room[blk] = 0;
    }
    Dungeon_LoadSprites();
}

pub export fn Dungeon_CacheTransSprites() callconv(.c) void {
    if (vars.player_is_indoors.* == 0)
        return;
    vars.alt_sprites_flag.* = vars.player_is_indoors.*;
    var k: isize = 15;
    while (k >= 0) : (k -= 1) {
        const u: usize = @intCast(k);
        vars.alt_sprite_state[u] = 0;
        vars.alt_sprite_type[u] = vars.sprite_type[u];
        vars.alt_sprite_x_lo[u] = vars.sprite_x_lo[u];
        vars.alt_sprite_graphics[u] = vars.sprite_graphics[u];
        vars.alt_sprite_x_hi[u] = vars.sprite_x_hi[u];
        vars.alt_sprite_y_lo[u] = vars.sprite_y_lo[u];
        vars.alt_sprite_y_hi[u] = vars.sprite_y_hi[u];
        if (vars.sprite_pause[u] != 0 or vars.sprite_state[u] == 4 or vars.sprite_state[u] == 10)
            continue;
        vars.alt_sprite_state[u] = vars.sprite_state[u];
        vars.alt_sprite_A[u] = vars.sprite_A[u];
        vars.alt_sprite_head_dir[u] = vars.sprite_head_dir[u];
        vars.alt_sprite_oam_flags[u] = vars.sprite_oam_flags[u];
        vars.alt_sprite_obj_prio[u] = vars.sprite_obj_prio[u];
        vars.alt_sprite_D[u] = vars.sprite_D[u];
        vars.alt_sprite_flags2[u] = vars.sprite_flags2[u];
        vars.alt_sprite_floor[u] = vars.sprite_floor[u];
        vars.alt_sprite_spawned_flag[u] = vars.sprite_ai_state[u];
        vars.alt_sprite_flags3[u] = vars.sprite_flags3[u];
        vars.alt_sprite_B[u] = vars.sprite_B[u];
        vars.alt_sprite_C[u] = vars.sprite_C[u];
        vars.alt_sprite_E[u] = vars.sprite_E[u];
        vars.alt_sprite_subtype2[u] = vars.sprite_subtype2[u];
        vars.alt_sprite_height_above_shadow[u] = vars.sprite_z[u];
        vars.alt_sprite_delay_main[u] = vars.sprite_delay_main[u];
        vars.alt_sprite_I[u] = vars.sprite_I[u];
        vars.alt_sprite_maybe_ignore_projectile[u] = vars.sprite_ignore_projectile[u];
    }
}

pub export fn Sprite_DisableAll() callconv(.c) void {
    var k: isize = 15;
    while (k >= 0) : (k -= 1) {
        const u: usize = @intCast(k);
        if (vars.sprite_state[u] != 0 and
            (vars.player_is_indoors.* != 0 or vars.sprite_type[u] != 0x6c))
            vars.sprite_state[u] = 0;
    }
    var a: isize = 9;
    while (a >= 0) : (a -= 1) vars.ancilla_type[@intCast(a)] = 0;
    vars.flag_is_ancilla_to_pick_up.* = 0;
    vars.sprite_limit_instance.* = 0;
    vars.byte_7E0B9B.* = 0;
    vars.byte_7E0B88.* = 0;
    vars.archery_game_arrows_left.* = 0;
    vars.garnish_active.* = 0;
    vars.byte_7E0B9E.* = 0;
    vars.activate_bomb_trap_overlord.* = 0;
    vars.intro_times_pal_flash.* = 0;
    vars.byte_7E0FF8.* = 0;
    vars.byte_7E0FFB.* = 0;
    vars.flag_block_link_menu.* = 0;
    vars.byte_7E0FFD.* = 0;
    vars.byte_7E0FC6.* = 0;
    vars.is_archer_or_shovel_game.* = 0;
    var o: isize = 7;
    while (o >= 0) : (o -= 1) vars.overlord_type[@intCast(o)] = 0;
    var g: isize = 29;
    while (g >= 0) : (g -= 1) vars.garnish_type[@intCast(g)] = 0;
}

pub export fn Dungeon_LoadSprites() callconv(.c) void {
    var src: [*]const u8 = kDungeonSprites() + kDungeonSpriteOffs()[vars.dungeon_room_index2.*];
    vars.byte_7E0FB1.* = @truncate((vars.dungeon_room_index2.* >> 3) & 0xfe);
    vars.byte_7E0FB0.* = @truncate((vars.dungeon_room_index2.* & 0xf) << 1);
    vars.sort_sprites_setting.* = src[0];
    src += 1;
    var k: c_int = 0;
    while (src[0] != 0xff) : (src += 3) {
        k = Dungeon_LoadSingleSprite(k, src) + 1;
    }
}

pub export fn Sprite_ManuallySetDeathFlagUW(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.player_is_indoors.* == 0 or vars.sprite_defl_bits[ki] & 1 != 0 or
        sign8(vars.sprite_N[ki]))
        return;
    vars.sprite_where_in_room[vars.dungeon_room_index2.*] |=
        @as(u16, 1) << @intCast(vars.sprite_N[ki]);
}

pub export fn Dungeon_LoadSingleSprite(k: c_int, src: [*]const u8) callconv(.c) c_int {
    const y = src[0];
    const x = src[1];
    const stype = src[2];
    if (stype == 0xe4) {
        if (y == 0xfe or y == 0xfd) {
            vars.sprite_die_action[@intCast(k - 1)] = if (y == 0xfe) 1 else 2;
            return k - 1;
        }
    } else if (x >= 0xe0) {
        Dungeon_LoadSingleOverlord(src);
        return k - 1;
    }
    const ki: usize = @intCast(k);
    if (tables.kSpriteInit_DeflBits[stype] & 1 == 0 and
        (vars.sprite_where_in_room[vars.dungeon_room_index2.*] & (@as(u16, 1) << @intCast(k))) != 0)
        return k;
    vars.sprite_state[ki] = 8;
    vars.tmp_counter.* = y;
    vars.sprite_floor[ki] = y >> 7;
    Sprite_SetY(k, ((@as(u16, y) << 4) & 0x1ff) +% (@as(u16, vars.byte_7E0FB1.*) << 8));
    vars.byte_7E0FB6.* = x;
    Sprite_SetX(k, ((@as(u16, x) << 4) & 0x1ff) +% (@as(u16, vars.byte_7E0FB0.*) << 8));
    vars.sprite_type[ki] = stype;
    vars.tmp_counter.* = (vars.tmp_counter.* & 0x60) >> 2;
    vars.sprite_subtype[ki] = vars.tmp_counter.* | (vars.byte_7E0FB6.* >> 5);
    vars.sprite_N[ki] = @truncate(@as(u32, @bitCast(k)));
    vars.sprite_die_action[ki] = 0;
    return k;
}

pub export fn Dungeon_LoadSingleOverlord(src: [*]const u8) callconv(.c) void {
    const k = AllocOverlord();
    if (k < 0)
        return;
    const ki: usize = @intCast(k);
    const y = src[0];
    const x = src[1];
    const stype = src[2];
    vars.overlord_type[ki] = stype;
    vars.overlord_floor[ki] = y >> 7;
    var t: u16 = ((@as(u16, y) << 4) & 0x1ff) +% (@as(u16, vars.byte_7E0FB1.*) << 8);
    vars.overlord_y_lo[ki] = @truncate(t);
    vars.overlord_y_hi[ki] = @truncate(t >> 8);
    t = ((@as(u16, x) << 4) & 0x1ff) +% (@as(u16, vars.byte_7E0FB0.*) << 8);
    vars.overlord_x_lo[ki] = @truncate(t);
    vars.overlord_x_hi[ki] = @truncate(t >> 8);
    vars.overlord_spawned_in_area[ki] = @truncate(vars.overworld_area_index.*);
    vars.overlord_gen2[ki] = 0;
    vars.overlord_gen1[ki] = 0;
    vars.overlord_gen3[ki] = 0;
    if (vars.overlord_type[ki] == 10 or vars.overlord_type[ki] == 11) {
        vars.overlord_gen2[ki] = 160;
    } else if (vars.overlord_type[ki] == 3) {
        vars.overlord_gen2[ki] = 255;
        vars.overlord_x_lo[ki] -%= 8;
    }
}

pub export fn Sprite_ResetAll() callconv(.c) void {
    Sprite_DisableAll();
    Sprite_ResetAll_noDisable();
}

pub export fn Sprite_ResetAll_noDisable() callconv(.c) void {
    vars.byte_7E0FDD.* = 0;
    vars.sprite_alert_flag.* = 0;
    vars.byte_7E0FFD.* = 0;
    vars.byte_7E02F0.* = 0;
    vars.byte_7E0FC6.* = 0;
    vars.sprite_limit_instance.* = 0;
    vars.sort_sprites_setting.* = 0;
    if (vars.follower_indicator.* != 13)
        vars.super_bomb_indicator_unk2.* = 0xfe;
    // The C memsets are byte counts over u16 arrays: 0x1000 bytes = 0x800 words,
    // and 8 bytes of 0xff = 4 words of 0xffff.
    @memset(vars.sprite_where_in_room[0..0x800], 0);
    @memset(vars.overworld_sprite_was_loaded[0..0x200], 0);
    @memset(vars.dungeon_room_history[0..4], 0xffff);
}

pub export fn Sprite_ReloadAll_Overworld() callconv(.c) void {
    Sprite_DisableAll();
    Sprite_OverworldReloadAll_justLoad();
}

pub export fn Sprite_OverworldReloadAll_justLoad() callconv(.c) void {
    Sprite_ResetAll_noDisable();
    Overworld_LoadSprites();
    Sprite_ActivateAllProxima();
}

pub export fn Overworld_LoadSprites() callconv(.c) void {
    vars.sprcoll_x_base.* = (vars.overworld_area_index.* & 7) << 9;
    vars.sprcoll_y_base.* = (((vars.overworld_area_index.* & 0x3f) >> 2) & 0xe) << 8;
    const sz = @as(u16, tables.kOverworldAreaSprcollSizes[loPtr(vars.overworld_area_index).*]) << 8;
    vars.sprcoll_x_size.* = sz;
    vars.sprcoll_y_size.* = sz;
    var src: [*]const u8 = overworld.GetOverworldSpritePtr(@intCast(vars.overworld_area_index.*));

    while (src[0] != 0xff) : (src += 3) {
        if (src[2] == 0xf4) {
            vars.byte_7E0FFD.* +%= 1;
            continue;
        }
        const r2: u8 = (src[0] >> 4) << 2;
        const r6: u8 = (src[1] >> 4) +% r2;
        const r5: u8 = (src[1] & 0xf) | (src[0] << 4);
        vars.sprite_where_in_overworld[@as(usize, r5) | (@as(usize, r6) << 8)] = src[2] +% 1;
    }
}

// ---------------------------------------------------------------------------
// Proximity activation
// ---------------------------------------------------------------------------

pub export fn Sprite_ActivateAllProxima() callconv(.c) void {
    const bak0 = vars.BG2HOFS_copy2.*;
    const bak1 = vars.byte_7E069E[1];
    vars.byte_7E069E[1] = 0xff;

    const xt: u16 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x40 else 0;
    vars.BG2HOFS_copy2.* -%= xt;
    var i: isize = 21 + @as(isize, xt >> 3);
    while (i >= 0) : (i -= 1) {
        Sprite_ActivateWhenProximal();
        vars.BG2HOFS_copy2.* +%= 16;
    }
    vars.byte_7E069E[1] = bak1;
    vars.BG2HOFS_copy2.* = bak0;
}

pub export fn Sprite_ProximityActivation() callconv(.c) void {
    if (vars.submodule_index.* != 0) {
        Sprite_ActivateWhenProximal();
        Sprite_ActivateWhenProximalBig();
    } else {
        if (vars.spr_ranged_based_toggler.* & 1 == 0)
            Sprite_ActivateWhenProximal();
        if (vars.spr_ranged_based_toggler.* & 1 != 0)
            Sprite_ActivateWhenProximalBig();
        vars.spr_ranged_based_toggler.* +%= 1;
    }
}

pub export fn Sprite_ActivateWhenProximal() callconv(.c) void {
    if (vars.byte_7E069E[1] != 0) {
        const xt: u16 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x40 else 0;
        const x = vars.BG2HOFS_copy2.* +%
            (if (sign8(vars.byte_7E069E[1])) (0 -% @as(u16, 0x10) -% xt) else (0x110 +% xt));
        var y = vars.BG2VOFS_copy2.* -% 0x30;
        var i: isize = 21;
        while (i >= 0) : ({
            i -= 1;
            y +%= 16;
        }) {
            Sprite_Overworld_ProximityMotivatedLoad(x, y);
        }
    }
}

pub export fn Sprite_ActivateWhenProximalBig() callconv(.c) void {
    if (vars.byte_7E069E[0] != 0) {
        const xt: u16 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x40 else 0;
        var x = vars.BG2HOFS_copy2.* -% 0x30 -% xt;
        const y = vars.BG2VOFS_copy2.* +%
            (if (sign8(vars.byte_7E069E[0])) (0 -% @as(u16, 0x10)) else 0x110);
        var i: isize = 21 + @as(isize, xt >> 3);
        while (i >= 0) : ({
            i -= 1;
            x +%= 16;
        }) {
            Sprite_Overworld_ProximityMotivatedLoad(x, y);
        }
    }
}

pub export fn Sprite_Overworld_ProximityMotivatedLoad(x: u16, y: u16) callconv(.c) void {
    const xt = x -% vars.sprcoll_x_base.*;
    const yt = y -% vars.sprcoll_y_base.*;
    if (xt >= vars.sprcoll_x_size.* or yt >= vars.sprcoll_y_size.*)
        return;

    const r1: u8 = @truncate(((yt >> 8) * 4) | (xt >> 8));
    const r0: u8 = @truncate((y & 0xf0) | ((x >> 4) & 0xf));
    Overworld_LoadProximaSpriteIfAlive((@as(u16, r1) << 8) | r0);
}

pub export fn Overworld_LoadProximaSpriteIfAlive(blk: u16) callconv(.c) void {
    const sprite_to_spawn = vars.sprite_where_in_overworld[blk];
    if (sprite_to_spawn == 0)
        return;

    const loadedmask: u8 = @as(u8, 0x80) >> @intCast(blk & 7);
    const loadedp = &vars.overworld_sprite_was_loaded[blk >> 3];

    if (loadedp.* & loadedmask != 0)
        return;

    if (sprite_to_spawn >= 0xf4) {
        // load overlord
        const k = AllocOverlord();
        if (k < 0)
            return;
        const ki: usize = @intCast(k);
        loadedp.* |= loadedmask;
        vars.overlord_offset_sprite_pos[ki] = blk;
        vars.overlord_type[ki] = sprite_to_spawn -% 0xf3;
        vars.overlord_x_lo[ki] = @as(u8, @truncate(blk << 4)) & 0xf0;
        if (vars.overlord_type[ki] == 1)
            vars.overlord_x_lo[ki] +%= 8;
        vars.overlord_y_lo[ki] = @truncate(blk & 0xf0);
        vars.overlord_x_hi[ki] = @as(u8, @truncate((blk >> 8) & 3)) +% hiPtr(vars.sprcoll_x_base).*;
        vars.overlord_y_hi[ki] = @as(u8, @truncate(blk >> 10)) +% hiPtr(vars.sprcoll_y_base).*;
        vars.overlord_floor[ki] = 0;
        vars.overlord_spawned_in_area[ki] = @truncate(vars.overworld_area_index.*);
        vars.overlord_gen2[ki] = 0;
        vars.overlord_gen1[ki] = 0;
        vars.overlord_gen3[ki] = 0;
    } else {
        // load regular sprite
        const k = Overworld_AllocSprite(sprite_to_spawn);
        if (k < 0)
            return;
        const ki: usize = @intCast(k);
        loadedp.* |= loadedmask;

        vars.sprite_N_word[ki] = blk;
        vars.sprite_type[ki] = sprite_to_spawn -% 1;
        vars.sprite_state[ki] = 8;
        vars.sprite_x_lo[ki] = @as(u8, @truncate(blk << 4)) & 0xf0;
        vars.sprite_y_lo[ki] = @truncate(blk & 0xf0);
        vars.sprite_x_hi[ki] = @as(u8, @truncate((blk >> 8) & 3)) +% hiPtr(vars.sprcoll_x_base).*;
        vars.sprite_y_hi[ki] = @as(u8, @truncate(blk >> 10)) +% hiPtr(vars.sprcoll_y_base).*;
        vars.sprite_floor[ki] = 0;
        vars.sprite_subtype[ki] = 0;
        vars.sprite_die_action[ki] = 0;
    }
}

pub export fn SpriteExplode_SpawnEA(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.tmp_counter.* = vars.sprite_type[ki];
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamicallyEx(k, 0xea, &info, 14);
    Sprite_SetSpawnedCoordinates(j, &info);
    const ji: usize = @intCast(j);
    vars.sprite_z_vel[ji] = 32;
    vars.sprite_floor[ji] = vars.link_is_on_lower_level.*;
    vars.sprite_A[ji] = if (j == 9) 2 else 6;
    Sprite_SetY(j, info.r2_y +% 3);
    if (vars.tmp_counter.* == 0xce) {
        Sprite_SetY(j, info.r2_y +% 16);
        return;
    }
    if (vars.tmp_counter.* == 0xcb) {
        vars.sprite_y_lo[ji] = 0x78;
        vars.sprite_x_lo[ji] = 0x78;
        vars.sprite_x_hi[ji] = hiPtr(vars.link_x_coord).*;
        vars.sprite_y_hi[ji] = hiPtr(vars.link_y_coord).*;
    }
}

pub export fn Sprite_KillFriends() callconv(.c) void {
    var j: isize = 15;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        if (@as(c_int, @intCast(j)) != vars.cur_object_index.* and vars.sprite_state[u] != 0 and
            vars.sprite_defl_bits[u] & 2 == 0 and vars.sprite_type[u] != 0x7a)
        {
            vars.sprite_state[u] = 6;
            vars.sprite_delay_main[u] = 15;
            vars.sprite_flags3[u] = 0;
            vars.sprite_flags5[u] = 0;
            vars.sprite_flags2[u] = 3;
        }
    }
}

pub export fn Garnish16_ThrownItemDebris(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const r5 = vars.garnish_oam_flags[ki];
    if (vars.byte_7E0FC6.* >= 3)
        return;
    if (vars.garnish_sprite[ki] == 3) {
        ScatterDebris_Draw(k, pt);
        return;
    }
    var oam = GetOamCurPtr();
    vars.tmp_counter.* = vars.garnish_sprite[ki];
    var base: u8 = ((vars.garnish_countdown[ki] >> 2) ^ 7) << 2;
    if (vars.tmp_counter.* == 4 or (vars.tmp_counter.* == 2 and vars.player_is_indoors.* == 0))
        base +%= 0x20;
    var i: isize = 3;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const j: usize = @as(usize, @intCast(i)) + base;
        const ch: u8 = if (vars.tmp_counter.* == 0)
            0x4E
        else if (vars.tmp_counter.* >= 0x80)
            0xF2
        else
            @bitCast(tables.kScatterDebris_Draw_Char[j]);
        SetOamHelper1(
            oam,
            pt.x +% @as(u16, @bitCast(tables.kScatterDebris_Draw_X[j])),
            @truncate(pt.y +% @as(u16, @bitCast(@as(i16, tables.kScatterDebris_Draw_Y[j])))),
            ch,
            tables.kScatterDebris_Draw_Flags[j] | r5,
            0,
        );
    }
}

pub export fn ScatterDebris_Draw(k: c_int, pt: Point16U) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.garnish_countdown[ki] == 16)
        vars.garnish_type[ki] = 0;

    var oam = GetOamCurPtr();
    const base: usize = @as(usize, (vars.garnish_countdown[ki] & 0xf) >> 2) * 3;

    var i: isize = 2;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const j: usize = @as(usize, @intCast(i)) + base;
        SetOamHelper1(
            oam,
            pt.x +% @as(u16, @bitCast(@as(i16, tables.kScatterDebris_Draw_X2[j]))),
            @truncate(pt.y +% @as(u16, @bitCast(@as(i16, tables.kScatterDebris_Draw_Y2[j])))),
            tables.kScatterDebris_Draw_Char2[j],
            tables.kScatterDebris_Draw_Flags2[j] | 0x22,
            0,
        );
    }
}

pub export fn Sprite_KillSelf(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_defl_bits[ki] & 0x40 == 0 and vars.player_is_indoors.* != 0)
        return;
    vars.sprite_state[ki] = 0;
    const blk = vars.sprite_N_word[ki];
    g_ram[0] = @truncate(blk); // Sprite_PrepOamCoordOrDoubleRet reads this!
    @as(*align(1) u16, @ptrCast(&g_ram[1])).* = (blk >> 3) +% 0xef80; // and this!
    const loadedmask: u8 = @as(u8, 0x80) >> @intCast(blk & 7);
    // warning: blk may be bad, seen with cannon balls in 2nd dungeon
    const addr: u16 = 0xEF80 +% (blk >> 3);

    const loadedp = &g_ram[@as(usize, addr) + 0x10000];

    if (blk < 0xffff)
        loadedp.* &= ~loadedmask;
    if (vars.player_is_indoors.* == 0) {
        vars.sprite_N_word[ki] = 0xffff;
    } else {
        vars.sprite_N[ki] = 0xff;
    }
}

// ---------------------------------------------------------------------------
// Garnishes
// ---------------------------------------------------------------------------

pub export fn Garnish_ExecuteUpperSlots() callconv(.c) void {
    load_gfx.HandleScreenFlash();

    if (vars.garnish_active.* != 0) {
        var i: isize = 29;
        while (i >= 15) : (i -= 1) Garnish_ExecuteSingle(@intCast(i));
    }
}

pub export fn Garnish_ExecuteLowerSlots() callconv(.c) void {
    if (vars.garnish_active.* != 0) {
        var i: isize = 14;
        while (i >= 0) : (i -= 1) Garnish_ExecuteSingle(@intCast(i));
    }
}

pub export fn Garnish_ExecuteSingle(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.cur_object_index.* = @truncate(@as(u32, @bitCast(k)));
    const gtype = vars.garnish_type[ki];
    if (gtype == 0)
        return;
    // The decrement is a side effect of the third operand, so it only happens
    // when the first two hold.
    if ((gtype == 5 or (vars.submodule_index.* | vars.flag_unk1.*) == 0) and
        vars.garnish_countdown[ki] != 0)
    {
        vars.garnish_countdown[ki] -%= 1;
        if (vars.garnish_countdown[ki] == 0) {
            vars.garnish_type[ki] = 0;
            return;
        }
    }
    const sprsize = tables.kGarnish_OamMemSize[vars.garnish_type[ki]];
    if (vars.sort_sprites_setting.* != 0) {
        if (vars.garnish_floor[ki] != 0) {
            _ = Oam_AllocateFromRegionF(sprsize);
        } else {
            _ = Oam_AllocateFromRegionD(sprsize);
        }
    } else {
        _ = Oam_AllocateFromRegionA(sprsize);
    }
    kGarnish_Funcs[vars.garnish_type[ki] - 1].?(k);
}

pub export fn Garnish15_ArrghusSplash(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    var oam = GetOamCurPtr();
    const g: usize = (vars.garnish_countdown[ki] >> 1) & 6;
    var i: isize = 1;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const j: usize = @as(usize, @intCast(i)) + g;
        SetOamHelper1(
            oam,
            pt.x +% @as(u16, @bitCast(@as(i16, tables.kArrghusSplash_X[j]))),
            @truncate(pt.y +% @as(u16, @bitCast(@as(i16, tables.kArrghusSplash_Y[j])))),
            tables.kArrghusSplash_Char[j],
            tables.kArrghusSplash_Flags[j],
            tables.kArrghusSplash_Ext[j],
        );
    }
}

pub export fn Garnish13_PyramidDebris(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const oam = GetOamCurPtr();

    const yv: i32 = @as(i32, @as(i8, @bitCast(vars.garnish_y_vel[ki]))) << 4;
    const y: i32 = (@as(i32, vars.garnish_y_lo[ki]) << 8) + @as(i32, vars.garnish_y_subpixel[ki]) + yv;
    vars.garnish_y_subpixel[ki] = @truncate(@as(u32, @bitCast(y)));
    vars.garnish_y_lo[ki] = @truncate(@as(u32, @bitCast(y)) >> 8);

    const xv: i32 = @as(i32, @as(i8, @bitCast(vars.garnish_x_vel[ki]))) << 4;
    const x: i32 = (@as(i32, vars.garnish_x_lo[ki]) << 8) + @as(i32, vars.garnish_x_subpixel[ki]) + xv;
    vars.garnish_x_subpixel[ki] = @truncate(@as(u32, @bitCast(x)));
    vars.garnish_x_lo[ki] = @truncate(@as(u32, @bitCast(x)) >> 8);

    vars.garnish_y_vel[ki] = vars.garnish_y_vel[ki] +% 3;
    var t: u8 = vars.garnish_x_lo[ki] -% @as(u8, @truncate(vars.BG2HOFS_copy2.*));
    if (t >= 248) {
        vars.garnish_type[ki] = 0;
        return;
    }
    oam[0].x = t;
    t = vars.garnish_y_lo[ki] -% @as(u8, @truncate(vars.BG2VOFS_copy2.*));
    if (t >= 240) {
        vars.garnish_type[ki] = 0;
        return;
    }
    oam[0].y = t;
    oam[0].charnum = 0x5c;
    oam[0].flags = ((vars.frame_counter.* << 3) & 0xc0) | 0x34;
    vars.bytewise_extended_oam[oamIndex(oam)] = 0;
}

pub export fn Garnish11_WitheringGanonBatFlame(k: c_int) callconv(.c) void {
    if ((vars.submodule_index.* | vars.flag_unk1.*) == 0)
        Garnish_SetY(k, Garnish_GetY(k) -% 1);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const oam = GetOamCurPtr();
    SetOamHelper1(oam + 0, pt.x +% 0, @truncate(pt.y), 0xa4, 0x22, 0);
    SetOamHelper1(oam + 1, pt.x +% 8, @truncate(pt.y), 0xa5, 0x22, 0);
}

pub export fn Garnish10_GanonBatFlame(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.garnish_countdown[ki] == 8)
        vars.garnish_type[ki] = 0x11;
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const j: usize = tables.kGanonBatFlame_Idx[vars.garnish_countdown[ki] >> 3];
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        tables.kGanonBatFlame_Char[j],
        tables.kGanonBatFlame_Flags[j] | 0x22,
        2,
    );
    Garnish_CheckPlayerCollision(k, pt.x, pt.y);
}

pub export fn Garnish0C_TrinexxIceBreath(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.garnish_countdown[ki] == 0x50 and (vars.submodule_index.* | vars.flag_unk1.*) == 0) {
        Dungeon_UpdateTileMapWithCommonTile(Garnish_GetX(k), @as(c_int, Garnish_GetY(k)) - 16, 18);
    }
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        tables.kTrinexxIce_Char[vars.garnish_countdown[ki] >> 4],
        tables.kTrinexxIce_Flags[(vars.garnish_countdown[ki] >> 2) & 3] | 0x35,
        2,
    );
}

pub export fn Garnish14_KakKidDashDust(k: c_int) callconv(.c) void {
    Garnish_DustCommon(k, 2);
}

pub export fn Garnish_WaterTrail(k: c_int) callconv(.c) void {
    Garnish_DustCommon(k, 3);
}

pub export fn Garnish0A_CannonSmoke(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const j: usize = vars.garnish_sprite[ki];
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        tables.kGarnish_CannonPoof_Char[vars.garnish_countdown[ki] >> 3],
        tables.kGarnish_CannonPoof_Flags[j] | 4,
        2,
    );
}

pub export fn Garnish09_LightningTrail(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const j: usize = vars.garnish_sprite[ki];
    const sub: u8 = if (loPtr(vars.dungeon_room_index2).* == 0x20) 0x80 else 0;
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        tables.kLightningTrail_Char[j] -% sub,
        ((vars.frame_counter.* << 1) & 0xe) | tables.kLightningTrail_Flags[j],
        2,
    );
    Garnish_CheckPlayerCollision(k, pt.x, pt.y);
}

pub export fn Garnish_CheckPlayerCollision(k: c_int, x: c_int, y: c_int) callconv(.c) void {
    const kk: u32 = @bitCast(k);
    const mixed: u8 = @truncate(kk ^ @as(u32, vars.frame_counter.*));
    if (((mixed & 7) | vars.countdown_for_blink.* | vars.link_disable_sprite_damage.*) != 0)
        return;

    const dx: u8 = @truncate(@as(u32, @bitCast(
        @as(i32, vars.link_x_coord.*) - @as(i32, vars.BG2HOFS_copy2.*) - x + 12,
    )));
    const dy: u8 = @truncate(@as(u32, @bitCast(
        @as(i32, vars.link_y_coord.*) - @as(i32, vars.BG2VOFS_copy2.*) - y + 22,
    )));
    if (dx < 24 and dy < 28) {
        vars.link_auxiliary_state.* = 1;
        vars.link_incapacitated_timer.* = 16;
        vars.link_give_damage.* = 16;
        vars.link_actual_vel_x.* ^= 255;
        vars.link_actual_vel_y.* ^= 255;
    }
}

pub export fn Garnish07_BabasuFlash(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const j: usize = vars.garnish_countdown[ki] >> 3;
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        tables.kBabusuFlash_Char[j],
        tables.kBabusuFlash_Flags[j],
        2,
    );
}

pub export fn Garnish08_KholdstareTrail(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const i: usize = vars.garnish_countdown[ki] >> 2;
    const j: usize = vars.garnish_sprite[ki];
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x +% @as(u16, @bitCast(@as(i16, tables.kGarnish_Nebule_XY[i]))),
        @truncate(pt.y +% @as(u16, @bitCast(@as(i16, tables.kGarnish_Nebule_XY[i])))),
        tables.kGarnish_Nebule_Char[i],
        (vars.sprite_oam_flags[j] | vars.sprite_obj_prio[j]) & ~@as(u8, 1),
        0,
    );
}

pub export fn Garnish06_ZoroTrail(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const j: usize = vars.garnish_sprite[ki];
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        0x75,
        vars.sprite_oam_flags[j] | vars.sprite_obj_prio[j],
        0,
    );
}

pub export fn Garnish12_Sparkle(k: c_int) callconv(.c) void {
    Garnish_SparkleCommon(k, 2);
}

pub export fn Garnish_SimpleSparkle(k: c_int) callconv(.c) void {
    Garnish_SparkleCommon(k, 3);
}

pub export fn Garnish0E_TrinexxFireBreath(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const j: usize = vars.garnish_sprite[ki];
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        tables.kTrinexxLavaBubble_Char[vars.garnish_countdown[ki] >> 3],
        ((vars.sprite_oam_flags[j] | vars.sprite_obj_prio[j]) & 0xf0) | 0xe,
        0,
    );
}

pub export fn Garnish0F_BlindLaserTrail(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const j: usize = vars.garnish_sprite[ki];
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        tables.kBlindLaserTrail_Char[vars.garnish_oam_flags[ki] - 7],
        vars.sprite_oam_flags[j] | vars.sprite_obj_prio[j],
        0,
    );
}

pub export fn Garnish04_LaserTrail(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        tables.kLaserBeamTrail_Char[vars.garnish_oam_flags[ki]],
        0x25,
        0,
    );
}

/// How far past the 4:3 screen's sides a garnish still counts as on screen.
fn garnishExtraX() u16 {
    if (features.enhanced_features0.* & features.kFeatures0_WidescreenVisualFixes == 0) return 0;
    return config.g_config.extended_aspect_ratio;
}

/// A garnish is thrown away the moment it leaves the screen, which the game
/// sizes at 256 pixels. The margins are screen too, so a fire snake's tail
/// and the like would vanish out there while you can still see them. `pt.x`
/// comes back as the 9 bit coordinate OAM takes, which reaches either way
/// past the 4:3 edges.
pub export fn Garnish_ReturnIfPrepFails(k: c_int, pt: *Point16U) callconv(.c) bool {
    const ki: usize = @intCast(k);
    const xt = garnishExtraX();
    const x = Garnish_GetX(k) -% vars.BG2HOFS_copy2.*;
    const y = Garnish_GetY(k) -% vars.BG2VOFS_copy2.*;

    if (x +% xt >= 256 + 2 * xt or y >= 256) {
        vars.garnish_type[ki] = 0;
        return true;
    }
    pt.x = x & 0x1ff;
    pt.y = y -% 16;
    return false;
}

pub export fn Garnish03_FallingTile(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    // The C reuses `j` for both the countdown test and the submodule test.
    var j: usize = vars.garnish_countdown[ki];
    if (j == 0x1e) {
        j = vars.submodule_index.* | vars.flag_unk1.*;
        if (j == 0)
            Dungeon_UpdateTileMapWithCommonTile(Garnish_GetX(k), @as(c_int, Garnish_GetY(k)) - 16, 4);
    }
    j >>= 3;
    const x = Garnish_GetX(k) +% tables.kCrumbleTile_XY[j] -% vars.BG2HOFS_copy2.*;
    const y = Garnish_GetY(k) +% tables.kCrumbleTile_XY[j] -% vars.BG2VOFS_copy2.*;
    if (x < 256 and y < 256)
        SetOamPlain(
            GetOamCurPtr(),
            @truncate(x),
            @truncate(y -% 16),
            tables.kCrumbleTile_Char[j],
            tables.kCrumbleTile_Flags[j],
            tables.kCrumbleTile_Ext[j],
        );
}

pub export fn Garnish01_FireSnakeTail(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    var pt: Point16U = undefined;
    if (Garnish_ReturnIfPrepFails(k, &pt))
        return;
    const j: usize = vars.garnish_sprite[ki];
    SetOamHelper1(
        GetOamCurPtr(),
        pt.x,
        @truncate(pt.y),
        0x28,
        vars.sprite_oam_flags[j] | vars.sprite_obj_prio[j],
        2,
    );
}

pub export fn Garnish02_MothulaBeamTrail(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const j: usize = vars.garnish_sprite[ki];
    SetOamPlain(
        GetOamCurPtr(),
        vars.garnish_x_lo[ki] -% @as(u8, @truncate(vars.BG2HOFS_copy2.*)),
        vars.garnish_y_lo[ki] -% @as(u8, @truncate(vars.BG2VOFS_copy2.*)),
        0xaa,
        vars.sprite_oam_flags[j] | vars.sprite_obj_prio[j],
        2,
    );
}

// ---------------------------------------------------------------------------
// Sprite property setup and OAM allocation
// ---------------------------------------------------------------------------

pub export fn SpritePrep_LoadProperties(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    SpritePrep_ResetProperties(k);
    const j: usize = vars.sprite_type[ki];
    vars.sprite_flags2[ki] = tables.kSpriteInit_Flags2[j];
    vars.sprite_health[ki] = tables.kSpriteInit_Health[j];
    vars.sprite_flags4[ki] = tables.kSpriteInit_Flags4[j];
    vars.sprite_flags5[ki] = tables.kSpriteInit_Flags5[j];
    vars.sprite_defl_bits[ki] = tables.kSpriteInit_DeflBits[j];
    vars.sprite_bump_damage[ki] = tables.kSpriteInit_BumpDamage[j];
    vars.sprite_flags[ki] = tables.kSpriteInit_Flags[j];
    vars.sprite_room[ki] = if (vars.player_is_indoors.* != 0)
        @truncate(vars.dungeon_room_index2.*)
    else
        @truncate(vars.overworld_area_index.*);
    vars.sprite_flags3[ki] = tables.kSpriteInit_Flags3[j];
    vars.sprite_oam_flags[ki] = tables.kSpriteInit_Flags3[j] & 0xf;
}

pub export fn SpritePrep_LoadPalette(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const f = tables.kSpriteInit_Flags3[vars.sprite_type[ki]];
    vars.sprite_flags3[ki] = f;
    vars.sprite_oam_flags[ki] = f & 15;
}

pub export fn SpritePrep_ResetProperties(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.sprite_pause[ki] = 0;
    vars.sprite_E[ki] = 0;
    vars.sprite_x_vel[ki] = 0;
    vars.sprite_y_vel[ki] = 0;
    vars.sprite_z_vel[ki] = 0;
    vars.sprite_x_subpixel[ki] = 0;
    vars.sprite_y_subpixel[ki] = 0;
    vars.sprite_z_subpos[ki] = 0;
    vars.sprite_ai_state[ki] = 0;
    vars.sprite_graphics[ki] = 0;
    vars.sprite_D[ki] = 0;
    vars.sprite_delay_main[ki] = 0;
    vars.sprite_delay_aux1[ki] = 0;
    vars.sprite_delay_aux2[ki] = 0;
    vars.sprite_delay_aux4[ki] = 0;
    vars.sprite_head_dir[ki] = 0;
    vars.sprite_anim_clock[ki] = 0;
    vars.sprite_G[ki] = 0;
    vars.sprite_hit_timer[ki] = 0;
    vars.sprite_wallcoll[ki] = 0;
    vars.sprite_z[ki] = 0;
    vars.sprite_health[ki] = 0;
    vars.sprite_F[ki] = 0;
    vars.sprite_x_recoil[ki] = 0;
    vars.sprite_y_recoil[ki] = 0;
    vars.sprite_A[ki] = 0;
    vars.sprite_B[ki] = 0;
    vars.sprite_C[ki] = 0;
    vars.sprite_unk2[ki] = 0;
    vars.sprite_subtype2[ki] = 0;
    vars.sprite_ignore_projectile[ki] = 0;
    vars.sprite_obj_prio[ki] = 0;
    vars.sprite_oam_flags[ki] = 0;
    vars.sprite_stunned[ki] = 0;
    vars.sprite_give_damage[ki] = 0;
    vars.sprite_unk3[ki] = 0;
    vars.sprite_unk4[ki] = 0;
    vars.sprite_unk5[ki] = 0;
    vars.sprite_unk1[ki] = 0;
    vars.sprite_I[ki] = 0;
}

pub export fn Oam_AllocateFromRegionA(num: u8) callconv(.c) u8 {
    return Oam_GetBufferPosition(num, 0);
}

pub export fn Oam_AllocateFromRegionB(num: u8) callconv(.c) u8 {
    return Oam_GetBufferPosition(num, 2);
}

pub export fn Oam_AllocateFromRegionC(num: u8) callconv(.c) u8 {
    return Oam_GetBufferPosition(num, 4);
}

pub export fn Oam_AllocateFromRegionD(num: u8) callconv(.c) u8 {
    return Oam_GetBufferPosition(num, 6);
}

pub export fn Oam_AllocateFromRegionE(num: u8) callconv(.c) u8 {
    return Oam_GetBufferPosition(num, 8);
}

pub export fn Oam_AllocateFromRegionF(num: u8) callconv(.c) u8 {
    return Oam_GetBufferPosition(num, 10);
}

pub export fn Oam_GetBufferPosition(num: u8, y_in: u8) callconv(.c) u8 {
    const y: usize = y_in >> 1;
    var p: u16 = vars.oam_region_base[y];
    var pstart: u16 = p;
    p +%= num;
    if (p >= tables.kOamGetBufferPos_Tab0[y]) {
        // post-increment: the index uses the old value
        const j: usize = vars.oam_alloc_arr1[y] & 7;
        vars.oam_alloc_arr1[y] +%= 1;
        pstart = tables.kOamGetBufferPos_Tab1[y * 8 + j];
    } else {
        vars.oam_region_base[y] = p;
    }
    vars.oam_ext_cur_ptr.* = 0xa20 +% (pstart >> 2);
    vars.oam_cur_ptr.* = 0x800 +% pstart;
    return @truncate(vars.oam_cur_ptr.*);
}

pub export fn Sprite_NullifyHookshotDrag() callconv(.c) void {
    var i: isize = 4;
    while (i >= 0) : (i -= 1) {
        if (vars.ancilla_type[@intCast(i)] & 0x1f == 0 and vars.related_to_hookshot.* != 0) {
            vars.related_to_hookshot.* = 0;
            break;
        }
    }
    vars.link_x_coord_safe_return_hi.* = @truncate(vars.link_x_coord.* >> 8);
    vars.link_y_coord_safe_return_hi.* = @truncate(vars.link_y_coord.* >> 8);
    vars.link_x_coord.* = vars.link_x_coord_prev.*;
    vars.link_y_coord.* = vars.link_y_coord_prev.*;
    HandleIndoorCameraAndDoors();
}

pub export fn Overworld_SubstituteAlternateSecret() callconv(.c) void {
    if (misc.GetRandomNumber() & 1 != 0)
        return;
    var n: c_int = 0;
    var i: isize = 15;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        if (vars.sprite_state[u] != 0 and vars.sprite_type[u] != 0x6c)
            n += 1;
    }
    if (n >= 4 or vars.sram_progress_indicator.* < 2)
        return;
    const j: usize = @as(usize, vars.overworld_secret_subst_ctr.* & 7) +
        (if (vars.is_in_dark_world.* != 0) @as(usize, 8) else 0);
    vars.overworld_secret_subst_ctr.* +%= 1;
    if (tables.kSecretSubst_Tab0[loPtr(vars.overworld_area_index).* & 0x3f] &
        tables.kSecretSubst_Tab1[j] == 0)
        loPtr(vars.dung_secrets_unk1).* = tables.kSecretSubst_Tab2[j];
}

pub export fn Sprite_ApplyConveyor(k: c_int, j: c_int) callconv(.c) void {
    if (vars.frame_counter.* & 1 == 0)
        return;
    const u: usize = @intCast(j - 0x68);
    Sprite_SetX(k, Sprite_GetX(k) +% @as(u16, @bitCast(@as(i16, tables.kConveyorAdjustment_X[u]))));
    Sprite_SetY(k, Sprite_GetY(k) +% @as(u16, @bitCast(@as(i16, tables.kConveyorAdjustment_Y[u]))));
}

pub export fn Sprite_BounceFromTileCollision(k: c_int) callconv(.c) u8 {
    const ki: usize = @intCast(k);
    const j = Sprite_CheckTileCollision(k);
    if (j & 3 != 0) {
        vars.sprite_x_vel[ki] = 0 -% vars.sprite_x_vel[ki];
        vars.sprite_G[ki] +%= 1;
    }
    if (j & 12 != 0) {
        vars.sprite_y_vel[ki] = 0 -% vars.sprite_y_vel[ki];
        vars.sprite_G[ki] +%= 1;
        return vars.sprite_G[ki]; // wtf
    }
    return 0;
}

pub export fn ExecuteCachedSprites() callconv(.c) void {
    if (vars.player_is_indoors.* == 0 or vars.submodule_index.* == 0 or
        vars.submodule_index.* == 14 or vars.alt_sprites_flag.* == 0)
    {
        vars.alt_sprites_flag.* = 0;
        return;
    }
    var i: isize = 15;
    while (i >= 0) : (i -= 1) {
        vars.cur_object_index.* = @intCast(i);
        if (vars.alt_sprite_state[@intCast(i)] != 0)
            UncacheAndExecuteSprite(@intCast(i));
    }
}

pub export fn UncacheAndExecuteSprite(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const bak0 = vars.sprite_state[ki];
    const bak1 = vars.sprite_type[ki];
    const bak2 = vars.sprite_x_lo[ki];
    const bak3 = vars.sprite_x_hi[ki];
    const bak4 = vars.sprite_y_lo[ki];
    const bak5 = vars.sprite_y_hi[ki];
    const bak6 = vars.sprite_graphics[ki];
    const bak7 = vars.sprite_A[ki];
    const bak8 = vars.sprite_head_dir[ki];
    const bak9 = vars.sprite_oam_flags[ki];
    const bak10 = vars.sprite_obj_prio[ki];
    const bak11 = vars.sprite_D[ki];
    const bak12 = vars.sprite_flags2[ki];
    const bak13 = vars.sprite_floor[ki];
    const bak14 = vars.sprite_ai_state[ki];
    const bak15 = vars.sprite_flags3[ki];
    const bak16 = vars.sprite_B[ki];
    const bak17 = vars.sprite_C[ki];
    const bak18 = vars.sprite_E[ki];
    const bak19 = vars.sprite_subtype2[ki];
    const bak20 = vars.sprite_z[ki];
    const bak21 = vars.sprite_delay_main[ki];
    const bak22 = vars.sprite_I[ki];
    const bak23 = vars.sprite_ignore_projectile[ki];
    vars.sprite_state[ki] = vars.alt_sprite_state[ki];
    vars.sprite_type[ki] = vars.alt_sprite_type[ki];
    vars.sprite_x_lo[ki] = vars.alt_sprite_x_lo[ki];
    vars.sprite_x_hi[ki] = vars.alt_sprite_x_hi[ki];
    vars.sprite_y_lo[ki] = vars.alt_sprite_y_lo[ki];
    vars.sprite_y_hi[ki] = vars.alt_sprite_y_hi[ki];
    vars.sprite_graphics[ki] = vars.alt_sprite_graphics[ki];
    vars.sprite_A[ki] = vars.alt_sprite_A[ki];
    vars.sprite_head_dir[ki] = vars.alt_sprite_head_dir[ki];
    vars.sprite_oam_flags[ki] = vars.alt_sprite_oam_flags[ki];
    vars.sprite_obj_prio[ki] = vars.alt_sprite_obj_prio[ki];
    vars.sprite_D[ki] = vars.alt_sprite_D[ki];
    vars.sprite_flags2[ki] = vars.alt_sprite_flags2[ki];
    vars.sprite_floor[ki] = vars.alt_sprite_floor[ki];
    vars.sprite_ai_state[ki] = vars.alt_sprite_spawned_flag[ki];
    vars.sprite_flags3[ki] = vars.alt_sprite_flags3[ki];
    vars.sprite_B[ki] = vars.alt_sprite_B[ki];
    vars.sprite_C[ki] = vars.alt_sprite_C[ki];
    vars.sprite_E[ki] = vars.alt_sprite_E[ki];
    vars.sprite_subtype2[ki] = vars.alt_sprite_subtype2[ki];
    vars.sprite_z[ki] = vars.alt_sprite_height_above_shadow[ki];
    vars.sprite_delay_main[ki] = vars.alt_sprite_delay_main[ki];
    vars.sprite_I[ki] = vars.alt_sprite_I[ki];
    vars.sprite_ignore_projectile[ki] = vars.alt_sprite_maybe_ignore_projectile[ki];
    Sprite_ExecuteSingle(k);
    if (vars.sprite_pause[ki] != 0)
        vars.alt_sprite_state[ki] = 0;
    vars.sprite_ignore_projectile[ki] = bak23;
    vars.sprite_I[ki] = bak22;
    vars.sprite_delay_main[ki] = bak21;
    vars.sprite_z[ki] = bak20;
    vars.sprite_subtype2[ki] = bak19;
    vars.sprite_E[ki] = bak18;
    vars.sprite_C[ki] = bak17;
    vars.sprite_B[ki] = bak16;
    vars.sprite_flags3[ki] = bak15;
    vars.sprite_ai_state[ki] = bak14;
    vars.sprite_floor[ki] = bak13;
    vars.sprite_flags2[ki] = bak12;
    vars.sprite_D[ki] = bak11;
    vars.sprite_obj_prio[ki] = bak10;
    vars.sprite_oam_flags[ki] = bak9;
    vars.sprite_head_dir[ki] = bak8;
    vars.sprite_A[ki] = bak7;
    vars.sprite_graphics[ki] = bak6;
    vars.sprite_y_hi[ki] = bak5;
    vars.sprite_y_lo[ki] = bak4;
    vars.sprite_x_hi[ki] = bak3;
    vars.sprite_x_lo[ki] = bak2;
    vars.sprite_type[ki] = bak1;
    vars.sprite_state[ki] = bak0;
}

pub export fn Sprite_ConvertVelocityToAngle(x_in: u8, y_in: u8) callconv(.c) u8 {
    var x = x_in;
    var y = y_in;
    const s: usize = (@as(usize, y >> 7) + @as(usize, x >> 7) * 2) * 8;
    if (sign8(x)) x = 0 -% x;
    if (sign8(y)) y = 0 -% y;
    // s picks one of four eight-entry quadrant rows and the smaller component
    // over four picks within it, so anything past 31 in the minor component
    // walks into the following row. The C does that on purpose often enough
    // that it is pinned by a test below, so it has to stay.
    //
    // What cannot stay is walking off the end entirely. A chain chomp at
    // (112, -112) asks for entry 36 of 32, and 0x80 negates to itself so it
    // arrives here still looking negative and reaches further still. The C
    // reads past the table and masks whatever it finds into a direction, so
    // there is no right answer to copy; saturating at the last entry is simply
    // a bounded one, and it leaves every index the table does hold untouched.
    const raw = @as(usize, if (x >= y) y >> 2 else x >> 2) + s;
    const i = @min(raw, tables.kConvertVelocityToAngle_Tab0.len - 1);
    return if (x >= y)
        tables.kConvertVelocityToAngle_Tab0[i]
    else
        tables.kConvertVelocityToAngle_Tab1[i];
}

pub export fn Sprite_SpawnDynamically(k: c_int, what: u8, info: *SpriteSpawnInfo) callconv(.c) c_int {
    return Sprite_SpawnDynamicallyEx(k, what, info, 15);
}

pub export fn Sprite_SpawnDynamicallyEx(k: c_int, what: u8, info: *SpriteSpawnInfo, j_in: c_int) callconv(.c) c_int {
    const ki: usize = @intCast(k);
    var j = j_in;
    while (true) {
        const ju: usize = @intCast(j);
        if (vars.sprite_state[ju] == 0) {
            vars.sprite_type[ju] = what;
            vars.sprite_state[ju] = 9;
            info.r0_x = Sprite_GetX(k);
            info.r2_y = Sprite_GetY(k);
            info.r4_z = vars.sprite_z[ki];
            info.r5_overlord_x = @as(u16, vars.overlord_x_lo[ki]) | @as(u16, vars.overlord_x_hi[ki]) << 8;
            info.r7_overlord_y = @as(u16, vars.overlord_y_lo[ki]) | @as(u16, vars.overlord_y_hi[ki]) << 8;
            SpritePrep_LoadProperties(j);
            if (vars.player_is_indoors.* == 0) {
                vars.sprite_N_word[ju] = 0xffff;
            } else {
                vars.sprite_N[ju] = 0xff;
            }
            vars.sprite_floor[ju] = vars.sprite_floor[ki];
            vars.sprite_D[ju] = vars.sprite_D[ki];
            vars.sprite_die_action[ju] = 0;
            vars.sprite_subtype[ju] = 0;
            break;
        }
        j -= 1;
        if (j < 0) break;
    }
    return j;
}

pub export fn SpriteFall_Draw(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const ki: usize = @intCast(k);
    const oam = GetOamCurPtr();
    oam[0].x = @truncate(info.x +% 4);
    oam[0].y = @truncate(info.y +% 4);
    oam[0].charnum = tables.kSpriteFall_Char[vars.sprite_delay_main[ki] >> 2];
    oam[0].flags = (info.flags & 0x30) | 0x04;
    Sprite_CorrectOamEntries(k, 0, 0);
}

pub export fn Sprite_GarnishSpawn_Sparkle_limited(k: c_int, x: u16, y: u16) callconv(.c) void {
    _ = Sprite_SpawnSimpleSparkleGarnishEx(k, x, y, 14);
}

pub export fn Sprite_GarnishSpawn_Sparkle(k: c_int, x: u16, y: u16) callconv(.c) c_int {
    return Sprite_SpawnSimpleSparkleGarnishEx(k, x, y, 29);
}

pub export fn Sprite_BehaveAsBarrier(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    const bak = vars.sprite_flags4[ki];
    vars.sprite_flags4[ki] = 0;
    if (Sprite_CheckDamageToLink_same_layer(k))
        Sprite_HaltAllMovement();
    vars.sprite_flags4[ki] = bak;
}

pub export fn Sprite_HaltAllMovement() callconv(.c) void {
    Sprite_NullifyHookshotDrag();
    vars.link_speed_setting.* = 0;
    Link_CancelDash();
}

pub export fn ReleaseFairy() callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(0, 0xe3, &info);
    if (j >= 0) {
        const ji: usize = @intCast(j);
        vars.sprite_floor[ji] = vars.link_is_on_lower_level.*;
        Sprite_SetX(j, vars.link_x_coord.* +% 8);
        Sprite_SetY(j, vars.link_y_coord.* +% 16);
        vars.sprite_D[ji] = 0;
        vars.sprite_delay_aux4[ji] = 96;
    }
    return j;
}

pub export fn Sprite_DrawRippleIfInWater(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    if (vars.sprite_I[ki] != 8 and vars.sprite_I[ki] != 9)
        return;

    if (vars.sprite_flags3[ki] & 0x20 != 0) {
        vars.cur_sprite_x.* -%= 4;
        if (vars.sprite_type[ki] == 0xdf)
            vars.cur_sprite_y.* -%= 7;
    }
    SpriteDraw_WaterRipple(k);
    Sprite_Get16BitCoords(k);
    _ = Oam_AllocateFromRegionA(((vars.sprite_flags2[ki] & 0x1f) +% 1) *% 4);
}

// ---------------------------------------------------------------------------
// Tests
//
// Expected values for the arithmetic-heavy functions were produced by compiling
// the original C bodies with clang and reading off the results, rather than by
// hand-evaluating them.
// ---------------------------------------------------------------------------

test "Sprite_GetX/SetX and GetY/SetY round-trip through the split byte arrays" {
    Sprite_SetX(3, 0x1234);
    Sprite_SetY(3, 0xabcd);
    try std.testing.expectEqual(@as(u8, 0x34), vars.sprite_x_lo[3]);
    try std.testing.expectEqual(@as(u8, 0x12), vars.sprite_x_hi[3]);
    try std.testing.expectEqual(@as(u16, 0x1234), Sprite_GetX(3));
    try std.testing.expectEqual(@as(u16, 0xabcd), Sprite_GetY(3));
}

test "Sprite_ConvertVelocityToAngle matches the C quadrant tables" {
    try std.testing.expectEqual(@as(u8, 0), Sprite_ConvertVelocityToAngle(0, 0));
    try std.testing.expectEqual(@as(u8, 0), Sprite_ConvertVelocityToAngle(16, 0));
    try std.testing.expectEqual(@as(u8, 4), Sprite_ConvertVelocityToAngle(0, 16));
    try std.testing.expectEqual(@as(u8, 1), Sprite_ConvertVelocityToAngle(16, 16));
    // high bit set selects the negative quadrants
    try std.testing.expectEqual(@as(u8, 7), Sprite_ConvertVelocityToAngle(200, 16));
    try std.testing.expectEqual(@as(u8, 13), Sprite_ConvertVelocityToAngle(16, 200));
    // (200, 200) indexes kConvertVelocityToAngle_Tab0[38] on a 32-entry table
    // in the C, reading out of bounds. There is no correct expected value, so
    // the index now saturates at the last entry instead of crashing; see the
    // note in Sprite_ConvertVelocityToAngle.
    try std.testing.expectEqual(@as(u8, 10), Sprite_ConvertVelocityToAngle(200, 200));
    try std.testing.expectEqual(@as(u8, 0), Sprite_ConvertVelocityToAngle(0x40, 0x20));
    try std.testing.expectEqual(@as(u8, 12), Sprite_ConvertVelocityToAngle(0x20, 0x40));
}

test "Entity_CheckSlopedTileCollision compares the slope table as signed" {
    // Each tiletype picks an 8-entry run of kSlopedTile; 0x10/0x11 compare
    // b >= a and 0x12/0x13 compare a >= b.
    const cases = [_]struct { tt: u8, x: u16, y: u16, want: bool }{
        .{ .tt = 0x10, .x = 0, .y = 0, .want = true },
        .{ .tt = 0x10, .x = 3, .y = 2, .want = true },
        .{ .tt = 0x10, .x = 6, .y = 4, .want = false },
        .{ .tt = 0x11, .x = 0, .y = 0, .want = true },
        .{ .tt = 0x11, .x = 3, .y = 2, .want = true },
        .{ .tt = 0x11, .x = 6, .y = 4, .want = true },
        .{ .tt = 0x12, .x = 0, .y = 0, .want = true },
        .{ .tt = 0x12, .x = 3, .y = 2, .want = false },
        .{ .tt = 0x12, .x = 6, .y = 4, .want = false },
        .{ .tt = 0x13, .x = 0, .y = 0, .want = false },
        .{ .tt = 0x13, .x = 3, .y = 2, .want = false },
        .{ .tt = 0x13, .x = 6, .y = 4, .want = true },
    };
    for (cases) |c| {
        vars.sprite_tiletype.* = c.tt;
        try std.testing.expectEqual(c.want, Entity_CheckSlopedTileCollision(c.x, c.y));
    }
}

test "CheckIfHitBoxesOverlap handles overlap, separation and the 0x80 disable" {
    var hb: SpriteHitBox = std.mem.zeroes(SpriteHitBox);
    hb.r0_xlo = 100;
    hb.r8_xhi = 0;
    hb.r1_ylo = 100;
    hb.r9_yhi = 0;
    hb.r2 = 8;
    hb.r3 = 8;
    hb.r4_spr_xlo = 102;
    hb.r10_spr_xhi = 0;
    hb.r5_spr_ylo = 102;
    hb.r11_spr_yhi = 0;
    hb.r6_spr_xsize = 8;
    hb.r7_spr_ysize = 8;
    try std.testing.expect(CheckIfHitBoxesOverlap(&hb));

    var far = hb;
    far.r4_spr_xlo = 200;
    try std.testing.expect(!CheckIfHitBoxesOverlap(&far));

    // 0x80 in either high byte means "no box".
    var off = hb;
    off.r8_xhi = 0x80;
    try std.testing.expect(!CheckIfHitBoxesOverlap(&off));
}

test "Oam_GetBufferPosition advances the region base and wraps via alloc_arr1" {
    @memset(vars.oam_region_base[0..6], 0);
    @memset(vars.oam_alloc_arr1[0..6], 0);

    try std.testing.expectEqual(@as(u8, 0), Oam_GetBufferPosition(16, 0));
    try std.testing.expectEqual(@as(u16, 16), vars.oam_region_base[0]);
    try std.testing.expectEqual(@as(u16, 0xa20), vars.oam_ext_cur_ptr.*);
    try std.testing.expectEqual(@as(u16, 0x800), vars.oam_cur_ptr.*);

    try std.testing.expectEqual(@as(u8, 16), Oam_GetBufferPosition(16, 0));
    try std.testing.expectEqual(@as(u16, 32), vars.oam_region_base[0]);

    try std.testing.expectEqual(@as(u8, 32), Oam_GetBufferPosition(16, 0));
    try std.testing.expectEqual(@as(u16, 48), vars.oam_region_base[0]);

    // Past the region limit it restarts from kOamGetBufferPos_Tab1, and the
    // index uses alloc_arr1's value *before* the post-increment.
    vars.oam_region_base[0] = 0x170;
    try std.testing.expectEqual(@as(u8, 48), Oam_GetBufferPosition(16, 0));
    try std.testing.expectEqual(@as(u16, 1), vars.oam_alloc_arr1[0]);
    try std.testing.expectEqual(@as(u16, 0xa2c), vars.oam_ext_cur_ptr.*);
    try std.testing.expectEqual(@as(u16, 0x830), vars.oam_cur_ptr.*);
}

test "Sprite_MoveX leaves position untouched at zero velocity" {
    Sprite_SetX(5, 0x0140);
    vars.sprite_x_vel[5] = 0;
    vars.sprite_x_subpixel[5] = 0x80;
    Sprite_MoveX(5);
    try std.testing.expectEqual(@as(u16, 0x0140), Sprite_GetX(5));
    try std.testing.expectEqual(@as(u8, 0x80), vars.sprite_x_subpixel[5]);
}

test "dispatch tables match the C layout, including the NULL garnish slot" {
    // overworld.c's kGarnish_Funcs has a NULL at index 12.
    try std.testing.expectEqual(@as(usize, 22), kGarnish_Funcs.len);
    try std.testing.expect(kGarnish_Funcs[12] == null);
    try std.testing.expectEqual(@as(?*const HandlerFuncK, &Garnish01_FireSnakeTail), kGarnish_Funcs[0]);
    try std.testing.expectEqual(@as(?*const HandlerFuncK, &Garnish16_ThrownItemDebris), kGarnish_Funcs[21]);

    try std.testing.expectEqual(@as(usize, 12), kSprite_ExecuteSingle.len);
    try std.testing.expectEqual(@as(*const HandlerFuncK, &Sprite_inactiveSprite), kSprite_ExecuteSingle[0]);
    try std.testing.expectEqual(@as(*const HandlerFuncK, &SpriteModule_Stunned), kSprite_ExecuteSingle[11]);
}

test "velocity to angle survives a component the table cannot reach" {
    // A minor component past 31 walks out of its quadrant row, and far enough
    // out it leaves the table. A chain chomp at (112, -112) asked for entry 36
    // of 32. These all saturate on the last entry now.
    const off_the_end = [_]struct { x: u8, y: u8 }{
        .{ .x = 112, .y = 0x90 }, // (112, -112), the reported crash, Tab0
        .{ .x = 0xB0, .y = 0xC0 }, // (-80, -64), Tab0
        .{ .x = 0xC0, .y = 0xB0 }, // (-64, -80), the same in Tab1
        .{ .x = 0x80, .y = 0x80 }, // 0x80 negates to itself, so it reads as negative
    };
    for (off_the_end) |c| {
        try std.testing.expectEqual(@as(u8, 10), Sprite_ConvertVelocityToAngle(c.x, c.y));
    }

    // Everything the table does hold is untouched, the deliberate walk into the
    // next quadrant row included: the value still comes from the raw index.
    const in_range = [_]struct { x: u8, y: u8 }{
        .{ .x = 0, .y = 0 }, .{ .x = 16, .y = 0 },
        .{ .x = 0x40, .y = 0x20 }, // minor 32, so index 8: into the next row
        .{ .x = 0x7c, .y = 0x1c },
        .{ .x = 200, .y = 16 },
    };
    for (in_range) |c| {
        var x = c.x;
        var y = c.y;
        const s_base: usize = (@as(usize, y >> 7) + @as(usize, x >> 7) * 2) * 8;
        if (x & 0x80 != 0) x = 0 -% x;
        if (y & 0x80 != 0) y = 0 -% y;
        const raw = @as(usize, if (x >= y) y >> 2 else x >> 2) + s_base;
        try std.testing.expect(raw < 32);
        const want = if (x >= y)
            tables.kConvertVelocityToAngle_Tab0[raw]
        else
            tables.kConvertVelocityToAngle_Tab1[raw];
        try std.testing.expectEqual(want, Sprite_ConvertVelocityToAngle(c.x, c.y));
    }
}

test "sword damage survives having no sword" {
    // The blacksmiths leave link_sword_type at 0xff while they temper it, and a
    // dash reaches the damage calculation without a swing, so running into
    // something in that state used to index entry 254 of a 12-entry table.
    @memset(g_ram[0..0x20000], 0);
    const k: c_int = 0;
    vars.sprite_type[0] = 0x0b; // a cucco, which is what turned this up
    vars.link_is_running.* = 1; // dashing, so the timing bits are not folded in

    for ([_]u8{ 0xff, 0 }) |no_sword| {
        vars.link_sword_type.* = no_sword;
        Sprite_CalculateSwordDamage(k);
        // The weakest entry, and in range for the two lookups downstream.
        try std.testing.expectEqual(tables.kSprite_Func14_Damage[0], vars.damage_type_determiner.*);
    }

    // A real sword still reads the entry it always did.
    for ([_]u8{ 1, 2, 3, 4 }) |sword| {
        vars.link_sword_type.* = sword;
        Sprite_CalculateSwordDamage(k);
        try std.testing.expectEqual(tables.kSprite_Func14_Damage[sword - 1], vars.damage_type_determiner.*);
    }

    @memset(g_ram[0..0x20000], 0);
}

test "Sprite_ScheduleForBreakage sets the breakage state the C does" {
    vars.sprite_delay_main[2] = 0;
    vars.sprite_state[2] = 9;
    vars.sprite_flags2[2] = 1;
    Sprite_ScheduleForBreakage(2);
    try std.testing.expectEqual(@as(u8, 31), vars.sprite_delay_main[2]);
    try std.testing.expectEqual(@as(u8, 6), vars.sprite_state[2]);
    try std.testing.expectEqual(@as(u8, 5), vars.sprite_flags2[2]);
}
