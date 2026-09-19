//! Port of src/overlord.c: "overlords" are the invisible controllers that sit
//! in a room and spawn or steer real sprites -- cannon emplacements, falling
//! tiles, the Armos knight coordinator, and so on.
const std = @import("std");
const vars = @import("variables.zig");

/// zelda_rtl.h: typedef void HandlerFuncK(int k);
const HandlerFuncK = fn (c_int) callconv(.c) void;

/// sprite.h
const SpriteSpawnInfo = extern struct {
    r0_x: u16,
    r2_y: u16,
    r4_z: u8,
    r5_overlord_x: u16,
    r7_overlord_y: u16,
};

// Still in C: sprite.c, sprite_main.c and misc.c.
extern const kSinusLookupTable: [256]u16;
extern fn Sprite_SpawnDynamically(k: c_int, what: u8, info: *SpriteSpawnInfo) c_int;
extern fn Sprite_SpawnDynamicallyEx(k: c_int, what: u8, info: *SpriteSpawnInfo, j: c_int) c_int;
extern fn Sprite_SetX(k: c_int, x: u16) void;
extern fn Sprite_SetY(k: c_int, y: u16) void;
extern fn Sprite_TransmuteToBomb(k: c_int) void;
extern fn SpriteSfx_QueueSfx2WithPan(k: c_int, a: u8) void;
extern fn SpriteSfx_QueueSfx3WithPan(k: c_int, a: u8) void;
extern fn CalculateSfxPan_Arbitrary(a: u8) u8;
extern fn GetRandomNumber() u8;
extern fn GetTileAttribute(floor: u8, x: *u16, y: u16) u8;
extern fn GarnishAlloc() c_int;

const overlord_type = vars.overlord_type;
const overlord_x_lo = vars.overlord_x_lo;
const overlord_x_hi = vars.overlord_x_hi;
const overlord_y_lo = vars.overlord_y_lo;
const overlord_y_hi = vars.overlord_y_hi;
const overlord_gen1 = vars.overlord_gen1;
const overlord_gen2 = vars.overlord_gen2;
const overlord_gen3 = vars.overlord_gen3;
const overlord_floor = vars.overlord_floor;
const overlord_offset_sprite_pos = vars.overlord_offset_sprite_pos;

const sprite_state = vars.sprite_state;
const sprite_type = vars.sprite_type;
const sprite_floor = vars.sprite_floor;
const sprite_A = vars.sprite_A;
const sprite_B = vars.sprite_B;
const sprite_C = vars.sprite_C;
const sprite_D = vars.sprite_D;
const sprite_E = vars.sprite_E;
const sprite_z = vars.sprite_z;
const sprite_x_lo = vars.sprite_x_lo;
const sprite_x_hi = vars.sprite_x_hi;
const sprite_y_lo = vars.sprite_y_lo;
const sprite_y_hi = vars.sprite_y_hi;
const sprite_x_vel = vars.sprite_x_vel;
const sprite_y_vel = vars.sprite_y_vel;
const sprite_health = vars.sprite_health;
const sprite_delay_main = vars.sprite_delay_main;
const sprite_delay_aux1 = vars.sprite_delay_aux1;
const sprite_delay_aux2 = vars.sprite_delay_aux2;
const sprite_flags2 = vars.sprite_flags2;
const sprite_flags3 = vars.sprite_flags3;
const sprite_flags4 = vars.sprite_flags4;
const sprite_flags5 = vars.sprite_flags5;
const sprite_defl_bits = vars.sprite_defl_bits;
const sprite_oam_flags = vars.sprite_oam_flags;
const sprite_bump_damage = vars.sprite_bump_damage;
const sprite_ai_state = vars.sprite_ai_state;
const sprite_head_dir = vars.sprite_head_dir;
const sprite_subtype2 = vars.sprite_subtype2;
const sprite_ignore_projectile = vars.sprite_ignore_projectile;

const garnish_type = vars.garnish_type;
const garnish_x_lo = vars.garnish_x_lo;
const garnish_x_hi = vars.garnish_x_hi;
const garnish_y_lo = vars.garnish_y_lo;
const garnish_y_hi = vars.garnish_y_hi;
const garnish_countdown = vars.garnish_countdown;
const garnish_active = vars.garnish_active;

const link_x_coord = vars.link_x_coord;
const link_y_coord = vars.link_y_coord;
const link_direction_facing = vars.link_direction_facing;
const link_is_on_lower_level = vars.link_is_on_lower_level;
const player_is_indoors = vars.player_is_indoors;
const submodule_index = vars.submodule_index;
const frame_counter = vars.frame_counter;
const flag_unk1 = vars.flag_unk1;
const tmp_counter = vars.tmp_counter;
const sound_effect_1 = vars.sound_effect_1;
const sprcoll_y_base = vars.sprcoll_y_base;
const activate_bomb_trap_overlord = vars.activate_bomb_trap_overlord;
const dung_floor_move_flags = vars.dung_floor_move_flags;
const overworld_sprite_was_loaded = vars.overworld_sprite_was_loaded;
const BG2HOFS_copy2 = vars.BG2HOFS_copy2;
const BG2VOFS_copy2 = vars.BG2VOFS_copy2;
const byte_7E0B9E = vars.byte_7E0B9E;
const byte_7E0FB0 = vars.byte_7E0FB0;
const byte_7E0FB1 = vars.byte_7E0FB1;
const byte_7E0FB6 = vars.byte_7E0FB6;
const byte_7E0FDE = vars.byte_7E0FDE;
const byte_7E0FFD = vars.byte_7E0FFD;
const byte_7E0FFE = vars.byte_7E0FFE;

/// types.h WORD(x): a 16-bit view over two bytes of a work-ram array.
fn wordAt(p: [*]u8, i: usize) *align(1) u16 {
    return @ptrCast(&p[i]);
}

/// types.h BYTE(x): the low byte of a 16-bit work-ram word.
fn loByte(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

fn sign8(v: i32) bool {
    return v & 0x80 != 0;
}

/// Sign extend an int8 table entry before adding it to a coordinate.
fn rel(v: i8) u16 {
    return @bitCast(@as(i16, v));
}

pub export fn Overlord_GetX(k: c_int) callconv(.c) u16 {
    const i: usize = @intCast(k);
    return @as(u16, overlord_x_lo[i]) | (@as(u16, overlord_x_hi[i]) << 8);
}

pub export fn Overlord_GetY(k: c_int) callconv(.c) u16 {
    const i: usize = @intCast(k);
    return @as(u16, overlord_y_lo[i]) | (@as(u16, overlord_y_hi[i]) << 8);
}

const kOverlordFuncs = [26]*const HandlerFuncK{
    &Overlord01_PositionTarget,
    &Overlord02_FullRoomCannons,
    &Overlord03_VerticalCannon,
    &Overlord_StalfosFactory,
    &Overlord05_FallingStalfos,
    &Overlord06_BadSwitchSnake,
    &Overlord07_MovingFloor,
    &Overlord08_BlobSpawner,
    &Overlord09_WallmasterSpawner,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord0A_FallingSquare,
    &Overlord10_PirogusuSpawner_left,
    &Overlord10_PirogusuSpawner_left,
    &Overlord10_PirogusuSpawner_left,
    &Overlord10_PirogusuSpawner_left,
    &Overlord14_TileRoom,
    &Overlord15_WizzrobeSpawner,
    &Overlord16_ZoroSpawner,
    &Overlord17_PotTrap,
    &Overlord18_InvisibleStalfos,
    &Overlord19_ArmosCoordinator_bounce,
    &Overlord06_BadSwitchSnake,
};

pub export fn Overlord_StalfosFactory(k: c_int) callconv(.c) void {
    _ = k;
    // unused
    unreachable;
}

pub export fn Overlord_SetX(k: c_int, v: u16) callconv(.c) void {
    const i: usize = @intCast(k);
    overlord_x_lo[i] = @truncate(v);
    overlord_x_hi[i] = @truncate(v >> 8);
}

pub export fn Overlord_SetY(k: c_int, v: u16) callconv(.c) void {
    const i: usize = @intCast(k);
    overlord_y_lo[i] = @truncate(v);
    overlord_y_hi[i] = @truncate(v >> 8);
}

fn ArmosMult(a: u16, b: u8) u8 {
    if (a >= 256)
        return b;
    const p: u32 = @as(u32, a) * b;
    return @truncate((p >> 8) + (p >> 7 & 1));
}

fn ArmosSin(a: u16, b: u8) i8 {
    const t = ArmosMult(kSinusLookupTable[a & 0xff], b);
    return if (a & 0x100 != 0) @bitCast(0 -% t) else @bitCast(t);
}

pub export fn Overlord_SpawnBoulder() callconv(.c) void { // 89b714
    if (player_is_indoors.* != 0 or byte_7E0FFD.* == 0 or (submodule_index.* | flag_unk1.*) != 0)
        return;
    byte_7E0FFE.* +%= 1;
    if (byte_7E0FFE.* & 63 != 0)
        return;

    if (sign8(@as(i32, BG2VOFS_copy2.* >> 8) - @as(i32, sprcoll_y_base.* >> 8) - 2))
        return;

    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(0, 0xc2, &info);
    if (j >= 0) {
        const i: usize = @intCast(j);
        Sprite_SetX(j, BG2HOFS_copy2.* +% (GetRandomNumber() & 127) +% 64);
        Sprite_SetY(j, BG2VOFS_copy2.* -% 0x30);
        sprite_floor[i] = 0;
        sprite_D[i] = 0;
        sprite_z[i] = 0;
    }
}

pub export fn Overlord_Main() callconv(.c) void { // 89b773
    Overlord_ExecuteAll();
    Overlord_SpawnBoulder();
}

pub export fn Overlord_ExecuteAll() callconv(.c) void { // 89b77e
    if ((submodule_index.* | flag_unk1.*) != 0)
        return;
    var i: c_int = 7;
    while (i >= 0) : (i -= 1) {
        if (overlord_type[@intCast(i)] != 0)
            Overlord_ExecuteSingle(i);
    }
}

pub export fn Overlord_ExecuteSingle(k: c_int) callconv(.c) void { // 89b793
    const j = overlord_type[@intCast(k)];
    Overlord_CheckIfActive(k);
    kOverlordFuncs[j - 1](k);
}

pub export fn Overlord19_ArmosCoordinator_bounce(k: c_int) callconv(.c) void { // 89b7dc
    const kArmosCoordinator_BackWallX = [6]u8{ 49, 77, 105, 131, 159, 187 };
    const i: usize = @intCast(k);

    if (overlord_gen2[i] != 0)
        overlord_gen2[i] -%= 1;
    switch (overlord_gen1[i]) {
        0 => { // wait for knight activation
            if (sprite_A[0] != 0) {
                overlord_x_lo[i] = 120;
                overlord_floor[i] = 255;
                overlord_x_lo[2] = 64;
                overlord_x_lo[0] = 192;
                overlord_x_lo[1] = 1;
                ArmosCoordinator_RotateKnights(k);
            }
        },
        1 => { // wait knight under coercion
            if (ArmosCoordinator_CheckKnights()) {
                overlord_gen1[i] +%= 1;
                overlord_gen2[i] = 0xff;
            }
        },
        // timed rotate then transition
        2, 4 => ArmosCoordinator_RotateKnights(k),
        3 => { // radial contraction
            overlord_x_lo[2] -%= 1;
            if (overlord_x_lo[2] == 32) {
                overlord_gen1[i] +%= 1;
                overlord_gen2[i] = 64;
            }
            ArmosCoordinator_Rotate(k);
        },
        5 => { // radial dilation
            overlord_x_lo[2] +%= 1;
            if (overlord_x_lo[2] == 64) {
                overlord_gen1[i] +%= 1;
                overlord_gen2[i] = 64;
            }
            ArmosCoordinator_Rotate(k);
        },
        6 => { // order knights to back wall
            if (overlord_gen2[i] != 0)
                return;
            ArmosCoordinator_DisableCoercion(k);
            var j: i32 = 5;
            while (j >= 0) : (j -= 1) {
                overlord_x_hi[@intCast(j)] = kArmosCoordinator_BackWallX[@intCast(j)];
                overlord_gen2[@intCast(j)] = 48;
            }
            overlord_gen1[i] +%= 1;
            overlord_gen2[i] = 255;
        },
        7 => { // cascade knights to front wall
            if (overlord_gen2[i] != 0)
                return;
            var j: i32 = 5;
            while (j >= 0) : (j -= 1) {
                overlord_gen2[@intCast(j)] +%= 1;
                if (overlord_gen2[@intCast(j)] == 192) {
                    overlord_gen1[i] = 1;
                    overlord_floor[i] = 0 -% overlord_floor[i];
                    ArmosCoordinator_DisableCoercion(k);
                    ArmosCoordinator_Rotate(k);
                    return;
                }
            }
        },
        else => {},
    }
}

pub export fn Overlord18_InvisibleStalfos(k: c_int) callconv(.c) void { // 89b7f5
    const kRedStalfosTrap_X = [4]i8{ 0, 0, -48, 48 };
    const kRedStalfosTrap_Y = [4]i8{ -40, 56, 8, 8 };
    const kRedStalfosTrap_Delay = [4]u8{ 0x30, 0x50, 0x70, 0x90 };
    const i: usize = @intCast(k);

    const x = Overlord_GetX(k);
    const y = Overlord_GetY(k);
    if ((x -% link_x_coord.* +% 24) >= 48 or (y -% link_y_coord.* +% 24) >= 48)
        return;
    overlord_type[i] = 0;
    tmp_counter.* = 3;
    while (true) {
        var info: SpriteSpawnInfo = undefined;
        const j = Sprite_SpawnDynamicallyEx(k, 0xa7, &info, 12);
        if (j < 0)
            return;
        const s: usize = @intCast(j);
        const t: usize = tmp_counter.*;
        Sprite_SetX(j, link_x_coord.* +% rel(kRedStalfosTrap_X[t]));
        Sprite_SetY(j, link_y_coord.* +% rel(kRedStalfosTrap_Y[t]));
        sprite_delay_main[s] = kRedStalfosTrap_Delay[t];
        sprite_floor[s] = overlord_floor[i];
        sprite_E[s] = 1;
        sprite_flags2[s] = 3;
        sprite_D[s] = 2;
        tmp_counter.* -%= 1;
        if (sign8(tmp_counter.*)) break;
    }
}

pub export fn Overlord17_PotTrap(k: c_int) callconv(.c) void { // 89b884
    const i: usize = @intCast(k);
    const x = Overlord_GetX(k);
    const y = Overlord_GetY(k);
    if ((x -% link_x_coord.* +% 32) < 64 and
        (y -% link_y_coord.* +% 32) < 64)
    {
        overlord_type[i] = 0;
        byte_7E0B9E.* +%= 1;
    }
}

pub export fn Overlord16_ZoroSpawner(k: c_int) callconv(.c) void { // 89b8d1
    const kOverlordZoroFactory_X = [8]i8{ -4, -2, 0, 2, 4, 6, 8, 12 };
    const i: usize = @intCast(k);
    overlord_gen2[i] -%= 1;
    var x = Overlord_GetX(k) +% 8;
    const y = Overlord_GetY(k) +% 8;
    if (GetTileAttribute(overlord_floor[i], &x, y) != 0x82)
        return;
    if (overlord_gen2[i] >= 0x18 or (overlord_gen2[i] & 3) != 0)
        return;
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamicallyEx(k, 0x9c, &info, 12);
    if (j >= 0) {
        const s: usize = @intCast(j);
        Sprite_SetX(j, info.r5_overlord_x +% rel(kOverlordZoroFactory_X[GetRandomNumber() & 7]) +% 8);
        sprite_y_lo[s] = @truncate(info.r7_overlord_y +% 8);
        sprite_y_hi[s] = @truncate(info.r7_overlord_y >> 8);
        sprite_floor[s] = overlord_floor[i];
        sprite_flags4[s] = 1;
        sprite_E[s] = 1;
        sprite_ignore_projectile[s] = 1;
        sprite_y_vel[s] = 16;
        sprite_flags2[s] = 32;
        sprite_oam_flags[s] = 13;
        sprite_subtype2[s] = GetRandomNumber();
        sprite_delay_main[s] = 48;
        sprite_bump_damage[s] = 3;
    }
}

pub export fn Overlord15_WizzrobeSpawner(k: c_int) callconv(.c) void { // 89b986
    const kOverlordWizzrobe_X = [4]i8{ 48, -48, 0, 0 };
    const kOverlordWizzrobe_Y = [4]i8{ 16, 16, 64, -32 };
    const kOverlordWizzrobe_Delay = [4]u8{ 0, 16, 32, 48 };
    const i: usize = @intCast(k);
    if (overlord_gen2[i] != 128) {
        if (frame_counter.* & 1 != 0)
            overlord_gen2[i] -%= 1;
        return;
    }
    overlord_gen2[i] = 127;
    var n: i32 = 3;
    while (n >= 0) : (n -= 1) {
        var info: SpriteSpawnInfo = undefined;
        const j = Sprite_SpawnDynamicallyEx(k, 0x9b, &info, 12);
        if (j >= 0) {
            const s: usize = @intCast(j);
            const t: usize = @intCast(n);
            Sprite_SetX(j, link_x_coord.* +% rel(kOverlordWizzrobe_X[t]));
            Sprite_SetY(j, link_y_coord.* +% rel(kOverlordWizzrobe_Y[t]));
            sprite_delay_main[s] = kOverlordWizzrobe_Delay[t];
            sprite_floor[s] = overlord_floor[i];
            sprite_B[s] = 1;
        }
    }
    tmp_counter.* = 0xff;
}

pub export fn Overlord14_TileRoom(k: c_int) callconv(.c) void { // 89b9e8
    const i: usize = @intCast(k);
    const x = Overlord_GetX(k) -% BG2HOFS_copy2.*;
    const y = Overlord_GetY(k) -% BG2VOFS_copy2.*;
    if (x & 0xff00 != 0 or y & 0xff00 != 0)
        return;
    overlord_gen2[i] -%= 1;
    if (overlord_gen2[i] != 0x80)
        return;
    const j = TileRoom_SpawnTile(k);
    if (j < 0) {
        overlord_gen2[i] = 0x81;
        return;
    }
    overlord_gen1[i] +%= 1;
    if (overlord_gen1[i] != 22)
        overlord_gen2[i] = 0xE0
    else
        overlord_type[i] = 0;
}

pub export fn TileRoom_SpawnTile(k: c_int) callconv(.c) c_int { // 89ba56
    const kSpawnFlyingTile_X = [22]u8{
        0x70, 0x80, 0x60, 0x90, 0x90, 0x60, 0x70, 0x80, 0x80, 0x70, 0x50, 0xa0, 0xa0, 0x50, 0x50, 0xa0,
        0xa0, 0x50, 0x70, 0x80, 0x80, 0x70,
    };
    const kSpawnFlyingTile_Y = [22]u8{
        0x80, 0x80, 0x70, 0x90, 0x70, 0x90, 0x60, 0xa0, 0x60, 0xa0, 0x60, 0xb0, 0x60, 0xb0, 0x80, 0x90,
        0x80, 0x90, 0x70, 0x90, 0x70, 0x90,
    };
    const i: usize = @intCast(k);
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, 0x94, &info);
    if (j < 0)
        return j;
    const s: usize = @intCast(j);
    sprite_E[s] = 1;
    const t: usize = overlord_gen1[i];
    sprite_x_lo[s] = kSpawnFlyingTile_X[t];
    sprite_y_lo[s] = kSpawnFlyingTile_Y[t] -% 8;
    sprite_y_hi[s] = overlord_y_hi[i];
    sprite_x_hi[s] = overlord_x_hi[i];
    sprite_floor[s] = overlord_floor[i];
    sprite_health[s] = 4;
    sprite_flags5[s] = 0;
    sprite_health[s] = 0;
    sprite_defl_bits[s] = 8;
    sprite_flags2[s] = 4;
    sprite_oam_flags[s] = 1;
    sprite_bump_damage[s] = 4;
    return j;
}

pub export fn Overlord10_PirogusuSpawner_left(k: c_int) callconv(.c) void { // 89baac
    const kOverlordPirogusu_A = [4]u8{ 2, 3, 0, 1 };
    const i: usize = @intCast(k);

    tmp_counter.* = overlord_type[i] -% 16;
    if (overlord_gen2[i] != 128) {
        overlord_gen2[i] -%= 1;
        return;
    }
    overlord_gen2[i] = (GetRandomNumber() & 31) +% 96;
    var n: i32 = 0;
    for (0..16) |t| {
        if (sprite_state[t] != 0 and sprite_type[t] == 0x10)
            n += 1;
    }
    if (n >= 5)
        return;
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamicallyEx(k, 0x94, &info, 12);
    if (j >= 0) {
        const s: usize = @intCast(j);
        Sprite_SetX(j, info.r5_overlord_x);
        Sprite_SetY(j, info.r7_overlord_y);
        sprite_floor[s] = overlord_floor[i];
        sprite_delay_main[s] = 32;
        sprite_D[s] = tmp_counter.*;
        sprite_A[s] = kOverlordPirogusu_A[tmp_counter.*];
    }
}

pub export fn Overlord0A_FallingSquare(k: c_int) callconv(.c) void { // 89bbb2
    const kCrumbleTilePathData = [108 + 1]u8{
        2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 3, 3, 3,
        3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 3, 1, 3, 0, 3, 1,
        3, 0, 3, 1, 3, 0, 3, 1, 3, 0, 3, 1, 3, 0, 3, 1,
        3, 0, 3, 1, 3, 0, 3, 1, 3, 0, 3, 1, 3, 0, 3, 1,
        3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2,
        2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0xff,
    };
    const kCrumbleTilePathOffs = [7]u8{ 0, 25, 66, 77, 87, 98, 108 };
    const kCrumbleTilePath_X = [4]i8{ 16, -16, 0, 0 };
    const kCrumbleTilePath_Y = [4]i8{ 0, 0, 16, -16 };
    const i: usize = @intCast(k);

    if (overlord_gen2[i] != 0) {
        if (overlord_gen3[i] != 0) {
            overlord_gen2[i] -%= 1;
            return;
        }
        const x = Overlord_GetX(k) -% BG2HOFS_copy2.*;
        const y = Overlord_GetY(k) -% BG2VOFS_copy2.*;
        if (!(x & 0xff00 != 0 or y & 0xff00 != 0))
            overlord_gen3[i] +%= 1;
        return;
    }

    overlord_gen2[i] = 16;
    SpawnFallingTile(k);
    const j: usize = overlord_type[i] - 10;
    const t: usize = overlord_gen1[i];
    overlord_gen1[i] +%= 1;
    if (t == kCrumbleTilePathOffs[j + 1] - kCrumbleTilePathOffs[j]) {
        overlord_type[i] = 0;
    }
    const step = kCrumbleTilePathData[kCrumbleTilePathOffs[j] + t];
    if (step == 0xff) {
        Overlord_SetX(k, Overlord_GetX(k) +% 0xc1a);
        Overlord_SetY(k, Overlord_GetY(k) +% 0xbb66);
    } else {
        Overlord_SetX(k, Overlord_GetX(k) +% rel(kCrumbleTilePath_X[step]));
        Overlord_SetY(k, Overlord_GetY(k) +% rel(kCrumbleTilePath_Y[step]));
    }
}

pub export fn SpawnFallingTile(k: c_int) callconv(.c) void { // 89bc31
    const i: usize = @intCast(k);
    const j = GarnishAlloc();
    if (j >= 0) {
        const s: usize = @intCast(j);
        garnish_type[s] = 3;
        garnish_x_hi[s] = overlord_x_hi[i];
        garnish_x_lo[s] = overlord_x_lo[i];
        sound_effect_1.* = CalculateSfxPan_Arbitrary(garnish_x_lo[s]) | 0x1f;
        const y = Overlord_GetY(k) +% 16;
        garnish_y_lo[s] = @truncate(y);
        garnish_y_hi[s] = @truncate(y >> 8);
        garnish_countdown[s] = 31;
        garnish_active.* = 31;
    }
}

pub export fn Overlord09_WallmasterSpawner(k: c_int) callconv(.c) void { // 89bc7b
    const i: usize = @intCast(k);
    if (overlord_gen2[i] != 128) {
        if (!(frame_counter.* & 1 != 0))
            overlord_gen2[i] -%= 1;
        return;
    }
    overlord_gen2[i] = 127;
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamicallyEx(k, 0x90, &info, 12);
    if (j < 0)
        return;
    const s: usize = @intCast(j);
    Sprite_SetX(j, link_x_coord.*);
    Sprite_SetY(j, link_y_coord.*);
    sprite_z[s] = 208;
    SpriteSfx_QueueSfx2WithPan(j, 0x20);
    sprite_floor[s] = link_is_on_lower_level.*;
}

pub export fn Overlord08_BlobSpawner(k: c_int) callconv(.c) void { // 89bcc3
    const i: usize = @intCast(k);
    if (overlord_gen2[i] != 0) {
        overlord_gen2[i] -%= 1;
        return;
    }
    overlord_gen2[i] = 0xa0;
    var n: i32 = 0;
    for (0..16) |t| {
        if (sprite_state[t] != 0 and sprite_type[t] == 0x8f)
            n += 1;
    }
    if (n >= 5)
        return;

    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamicallyEx(k, 0x8f, &info, 12);
    if (j >= 0) {
        const kOverlordZol_X = [4]i8{ 0, 0, -48, 48 };
        const kOverlordZol_Y = [4]i8{ -40, 56, 8, 8 };
        const s: usize = @intCast(j);
        const t: usize = link_direction_facing.* >> 1;
        Sprite_SetX(j, link_x_coord.* +% rel(kOverlordZol_X[t]));
        Sprite_SetY(j, link_y_coord.* +% rel(kOverlordZol_Y[t]));
        sprite_z[s] = 192;
        sprite_floor[s] = link_is_on_lower_level.*;
        sprite_ai_state[s] = 2;
        sprite_E[s] = 2;
        sprite_C[s] = 2;
        sprite_head_dir[s] = GetRandomNumber() & 31 | 16;
    }
}

pub export fn Overlord07_MovingFloor(k: c_int) callconv(.c) void { // 89bd3f
    const i: usize = @intCast(k);
    if (sprite_state[0] == 4) {
        overlord_type[i] = 0;
        loByte(dung_floor_move_flags).* = 1;
        return;
    }
    if (overlord_gen1[i] == 0) {
        overlord_gen2[i] +%= 1;
        if (overlord_gen2[i] == 32) {
            overlord_gen2[i] = 0;
            loByte(dung_floor_move_flags).* = (GetRandomNumber() & (if (overlord_x_lo[i] != 0) @as(u8, 3) else 1)) *% 2;
            overlord_gen2[i] = (GetRandomNumber() & 127) +% 128;
            overlord_gen1[i] +%= 1;
        } else {
            loByte(dung_floor_move_flags).* = 1;
        }
    } else {
        overlord_gen2[i] -%= 1;
        if (overlord_gen2[i] == 0)
            overlord_gen1[i] = 0;
    }
}

pub export fn Sprite_Overlord_PlayFallingSfx(k: c_int) callconv(.c) void { // 89bdfd
    SpriteSfx_QueueSfx2WithPan(k, 0x20);
}

pub export fn Overlord05_FallingStalfos(k: c_int) callconv(.c) void { // 89be0f
    const kStalfosTrap_Trigger = [8]u8{ 255, 224, 192, 160, 128, 96, 64, 32 };
    const i: usize = @intCast(k);

    const x = Overlord_GetX(k) -% BG2HOFS_copy2.*;
    const y = Overlord_GetY(k) -% BG2VOFS_copy2.*;
    if (x & 0xff00 != 0 or y & 0xff00 != 0)
        return;
    if (overlord_gen1[i] == 0) {
        if (byte_7E0B9E.* != 0)
            overlord_gen1[i] +%= 1;
        return;
    }
    const before = overlord_gen1[i];
    overlord_gen1[i] +%= 1;
    if (before == kStalfosTrap_Trigger[i]) {
        overlord_type[i] = 0;
        var info: SpriteSpawnInfo = undefined;
        const j = Sprite_SpawnDynamicallyEx(k, 0x85, &info, 12);
        if (j < 0)
            return;
        const s: usize = @intCast(j);
        Sprite_SetX(j, info.r5_overlord_x);
        Sprite_SetY(j, info.r7_overlord_y);
        sprite_z[s] = 224;
        sprite_floor[s] = overlord_floor[i];
        sprite_D[s] = 0; // zelda bug: unitialized
        Sprite_Overlord_PlayFallingSfx(j);
    }
}

pub export fn Overlord06_BadSwitchSnake(k: c_int) callconv(.c) void { // 89be75
    const kSnakeTrapOverlord_Tab1 = [8]u8{ 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90 };
    const i: usize = @intCast(k);

    const a = overlord_gen1[i];
    if (a == 0) {
        if (activate_bomb_trap_overlord.* != 0)
            overlord_gen1[i] = 1;
        return;
    }
    overlord_gen1[i] = a +% 1;

    if (a != kSnakeTrapOverlord_Tab1[i])
        return;

    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, 0x6e, &info);
    if (j < 0)
        return;
    const s: usize = @intCast(j);
    Sprite_SetX(j, info.r5_overlord_x);
    Sprite_SetY(j, info.r7_overlord_y);

    sprite_z[s] = 192;
    sprite_E[s] = 192;

    sprite_flags3[s] |= 0x10;
    sprite_floor[s] = overlord_floor[i];
    SpriteSfx_QueueSfx2WithPan(j, 0x20);
    const kind = overlord_type[i];
    overlord_type[i] = 0;
    if (kind == 26) {
        sprite_type[s] = 74;
        Sprite_TransmuteToBomb(j);
        sprite_delay_aux1[s] = 112;
    }
}

pub export fn Overlord02_FullRoomCannons(k: c_int) callconv(.c) void { // 89bf09
    const kAllDirectionMetalBallFactory_Idx = [16]u8{ 2, 2, 2, 2, 1, 1, 1, 1, 3, 3, 3, 3, 0, 0, 0, 0 };
    const kAllDirectionMetalBallFactory_X = [16]u8{ 64, 96, 144, 176, 240, 240, 240, 240, 176, 144, 96, 64, 0, 0, 0, 0 };
    const kAllDirectionMetalBallFactory_Y = [16]u8{ 16, 16, 16, 16, 64, 96, 160, 192, 240, 240, 240, 240, 192, 160, 96, 64 };
    const i: usize = @intCast(k);
    const x = Overlord_GetX(k) -% BG2HOFS_copy2.*;
    const y = Overlord_GetY(k) -% BG2VOFS_copy2.*;
    if ((x | y) & 0xff00 != 0 or frame_counter.* & 0xf != 0)
        return;

    byte_7E0FB6.* = 0;
    const j: usize = GetRandomNumber() & 15;
    tmp_counter.* = kAllDirectionMetalBallFactory_Idx[j];
    overlord_x_lo[i] = kAllDirectionMetalBallFactory_X[j];
    overlord_x_hi[i] = byte_7E0FB0.*;
    overlord_y_lo[i] = kAllDirectionMetalBallFactory_Y[j];
    overlord_y_hi[i] = byte_7E0FB1.* +% 1;
    Overlord_SpawnCannonBall(k, 0);
}

pub export fn Overlord03_VerticalCannon(k: c_int) callconv(.c) void { // 89bf5b
    const i: usize = @intCast(k);
    const x = Overlord_GetX(k) -% BG2HOFS_copy2.*;
    if (x & 0xff00 != 0) {
        overlord_gen2[i] = 255;
        return;
    }
    if (!(frame_counter.* & 1 != 0) and overlord_gen2[i] != 0)
        overlord_gen2[i] -%= 1;
    tmp_counter.* = 2;
    byte_7E0FB6.* = 0;
    overlord_gen1[i] -%= 1;
    if (!sign8(overlord_gen1[i]))
        return;
    overlord_gen1[i] = 56;
    var xd: c_int = undefined;
    if (overlord_gen2[i] == 0) {
        overlord_gen2[i] = 160;
        byte_7E0FB6.* = 160;
        xd = 8;
    } else {
        xd = @as(c_int, GetRandomNumber() & 2) * 8;
    }
    Overlord_SpawnCannonBall(k, xd);
}

pub export fn Overlord_SpawnCannonBall(k: c_int, xd: c_int) callconv(.c) void { // 89bfaf
    const kOverlordSpawnBall_Xvel = [4]i8{ 24, -24, 0, 0 };
    const kOverlordSpawnBall_Yvel = [4]i8{ 0, 0, 24, -24 };
    const i: usize = @intCast(k);
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, 0x50, &info);
    if (j < 0)
        return;
    const s: usize = @intCast(j);

    Sprite_SetX(j, info.r5_overlord_x +% @as(u16, @bitCast(@as(i16, @truncate(xd)))));
    Sprite_SetY(j, info.r7_overlord_y -% 1);

    const t: usize = tmp_counter.*;
    sprite_x_vel[s] = @bitCast(kOverlordSpawnBall_Xvel[t]);
    sprite_y_vel[s] = @bitCast(kOverlordSpawnBall_Yvel[t]);
    sprite_floor[s] = overlord_floor[i];
    if (byte_7E0FB6.* != 0) {
        sprite_ai_state[s] = byte_7E0FB6.*;
        sprite_y_lo[s] = sprite_y_lo[s] +% 8;
        sprite_flags2[s] = 3;
        sprite_flags4[s] = 9;
    }
    sprite_delay_aux2[s] = 64;
    SpriteSfx_QueueSfx3WithPan(j, 0x7);
}

pub export fn Overlord01_PositionTarget(k: c_int) callconv(.c) void { // 89c01e
    byte_7E0FDE.* = @truncate(@as(c_uint, @bitCast(k)));
}

pub export fn Overlord_CheckIfActive(k: c_int) callconv(.c) void { // 89c08d
    const kOverlordInRangeOffs = [2]i16{ 0x130, -0x40 };
    const i: usize = @intCast(k);
    if (player_is_indoors.* != 0)
        return;
    const j: u16 = frame_counter.* & 1;
    const off: u16 = @bitCast(kOverlordInRangeOffs[j]);
    const x = BG2HOFS_copy2.* +% off -% Overlord_GetX(k);
    const y = BG2VOFS_copy2.* +% off -% Overlord_GetY(k);
    if ((x >> 15) != j or (y >> 15) != j) {
        overlord_type[i] = 0;
        const blk = overlord_offset_sprite_pos[i];
        if (blk != 0xffff) {
            const loadedmask: u8 = @as(u8, 0x80) >> @intCast(blk & 7);
            overworld_sprite_was_loaded[blk >> 3] &= ~loadedmask;
        }
    }
}

pub export fn ArmosCoordinator_RotateKnights(k: c_int) callconv(.c) void { // 9deccc
    const i: usize = @intCast(k);
    if (overlord_gen2[i] == 0)
        overlord_gen1[i] +%= 1;
    ArmosCoordinator_Rotate(k);
}

pub export fn ArmosCoordinator_Rotate(k: c_int) callconv(.c) void { // 9decd4
    const kArmosCoordinator_Tab0 = [6]u16{ 0, 425, 340, 255, 170, 85 };
    const i: usize = @intCast(k);

    const angle = wordAt(overlord_x_lo, 0);
    angle.* +%= rel(@bitCast(overlord_floor[i]));
    for (0..6) |t| {
        const t0: u16 = angle.* +% kArmosCoordinator_Tab0[t];
        const size = overlord_x_lo[2];
        const tx: u16 = Overlord_GetX(k) +% rel(ArmosSin(t0, size));
        overlord_x_hi[t] = @truncate(tx);
        overlord_y_hi[t] = @truncate(tx >> 8);
        const ty: u16 = Overlord_GetY(k) +% rel(ArmosSin(t0 +% 0x80, size));
        overlord_gen2[t] = @truncate(ty);
        overlord_floor[t] = @truncate(ty >> 8);
    }
    tmp_counter.* = 6;
}

pub export fn ArmosCoordinator_CheckKnights() callconv(.c) bool { // 9dedb8
    var j: i32 = 5;
    while (j >= 0) : (j -= 1) {
        const t: usize = @intCast(j);
        if (sprite_state[t] != 0 and sprite_ai_state[t] == 0)
            return false;
    }
    return true;
}

pub export fn ArmosCoordinator_DisableCoercion(k: c_int) callconv(.c) void { // 9dedcb
    _ = k;
    var j: i32 = 5;
    while (j >= 0) : (j -= 1)
        sprite_ai_state[@intCast(j)] = 0;
}

const testing = std.testing;

fn resetRam() void {
    @memset(vars.g_ram[0..0x2000], 0);
    player_is_indoors.* = 0;
    submodule_index.* = 0;
    flag_unk1.* = 0;
}

test "overlord coordinates split across two byte arrays" {
    resetRam();
    Overlord_SetX(3, 0x1234);
    Overlord_SetY(3, 0xabcd);
    try testing.expectEqual(@as(u8, 0x34), overlord_x_lo[3]);
    try testing.expectEqual(@as(u8, 0x12), overlord_x_hi[3]);
    try testing.expectEqual(@as(u16, 0x1234), Overlord_GetX(3));
    try testing.expectEqual(@as(u16, 0xabcd), Overlord_GetY(3));
}

test "Overlord_ExecuteAll stands down while a submodule is running" {
    resetRam();
    overlord_type[0] = 0xff; // would index past the handler table if run
    submodule_index.* = 1;
    Overlord_ExecuteAll(); // must return before dispatching
    flag_unk1.* = 1;
    submodule_index.* = 0;
    Overlord_ExecuteAll();
}

test "the pot trap fires only when Link is inside its box" {
    resetRam();
    link_x_coord.* = 100;
    link_y_coord.* = 100;
    Overlord_SetX(1, 100);
    Overlord_SetY(1, 100);
    overlord_type[1] = 23;

    Overlord17_PotTrap(1);
    try testing.expectEqual(@as(u8, 0), overlord_type[1]); // consumed
    try testing.expectEqual(@as(u8, 1), byte_7E0B9E.*);

    // Far away: nothing happens.
    resetRam();
    link_x_coord.* = 100;
    link_y_coord.* = 100;
    Overlord_SetX(1, 400);
    Overlord_SetY(1, 100);
    overlord_type[1] = 23;
    Overlord17_PotTrap(1);
    try testing.expectEqual(@as(u8, 23), overlord_type[1]);
    try testing.expectEqual(@as(u8, 0), byte_7E0B9E.*);
}

test "the position target overlord just records its own slot" {
    resetRam();
    Overlord01_PositionTarget(5);
    try testing.expectEqual(@as(u8, 5), byte_7E0FDE.*);
}

test "an overlord scrolled out of range is retired and unmarked" {
    resetRam();
    player_is_indoors.* = 0;
    frame_counter.* = 0; // picks the +0x130 edge
    BG2HOFS_copy2.* = 0;
    BG2VOFS_copy2.* = 0;
    overlord_type[2] = 5;
    overlord_offset_sprite_pos[2] = 9; // byte 1, bit 1
    overworld_sprite_was_loaded[1] = 0xff;
    Overlord_SetX(2, 0x4000); // far off screen
    Overlord_SetY(2, 0x4000);

    Overlord_CheckIfActive(2);
    try testing.expectEqual(@as(u8, 0), overlord_type[2]);
    // 0x80 >> (9 & 7) = 0x40 is cleared, the rest is untouched.
    try testing.expectEqual(@as(u8, 0xff & ~@as(u8, 0x40)), overworld_sprite_was_loaded[1]);
}

test "an overlord still on screen is left alone" {
    resetRam();
    frame_counter.* = 0;
    BG2HOFS_copy2.* = 0;
    BG2VOFS_copy2.* = 0;
    overlord_type[2] = 5;
    Overlord_SetX(2, 0x80);
    Overlord_SetY(2, 0x80);
    Overlord_CheckIfActive(2);
    try testing.expectEqual(@as(u8, 5), overlord_type[2]);
}

test "indoors the range check never retires anything" {
    resetRam();
    player_is_indoors.* = 1;
    overlord_type[2] = 5;
    Overlord_SetX(2, 0x4000);
    Overlord_CheckIfActive(2);
    try testing.expectEqual(@as(u8, 5), overlord_type[2]);
}

test "the armos coordinator waits for every knight to be coerced" {
    resetRam();
    // No live knights at all: vacuously ready.
    try testing.expect(ArmosCoordinator_CheckKnights());

    sprite_state[3] = 1;
    sprite_ai_state[3] = 0; // alive but not yet coerced
    try testing.expect(!ArmosCoordinator_CheckKnights());

    sprite_ai_state[3] = 2;
    try testing.expect(ArmosCoordinator_CheckKnights());
}

test "disabling coercion clears the six knights" {
    resetRam();
    for (0..8) |i| sprite_ai_state[i] = 9;
    ArmosCoordinator_DisableCoercion(0);
    for (0..6) |i|
        try testing.expectEqual(@as(u8, 0), sprite_ai_state[i]);
    // Only the six knights are touched.
    try testing.expectEqual(@as(u8, 9), sprite_ai_state[6]);
}

test "ArmosMult rounds on the dropped bit and saturates past 256" {
    try testing.expectEqual(@as(u8, 7), ArmosMult(300, 7)); // a >= 256 returns b
    try testing.expectEqual(@as(u8, 0), ArmosMult(0, 200));
    // 128 * 64 = 8192; >> 8 is 32, and bit 7 of the product is 0.
    try testing.expectEqual(@as(u8, 32), ArmosMult(128, 64));
    // 255 * 2 = 510; >> 8 is 1, bit 7 is 1, so it rounds up to 2.
    try testing.expectEqual(@as(u8, 2), ArmosMult(255, 2));
}

test "the moving floor stops when the player dies" {
    resetRam();
    sprite_state[0] = 4; // dying
    overlord_type[1] = 7;
    Overlord07_MovingFloor(1);
    try testing.expectEqual(@as(u8, 0), overlord_type[1]);
    try testing.expectEqual(@as(u8, 1), loByte(dung_floor_move_flags).*);
}

test "the moving floor ticks up to its reshuffle point" {
    resetRam();
    overlord_gen1[1] = 0;
    overlord_gen2[1] = 5;
    Overlord07_MovingFloor(1);
    try testing.expectEqual(@as(u8, 6), overlord_gen2[1]);
    try testing.expectEqual(@as(u8, 1), loByte(dung_floor_move_flags).*);

    // Counting down on the other branch.
    overlord_gen1[1] = 1;
    overlord_gen2[1] = 2;
    Overlord07_MovingFloor(1);
    try testing.expectEqual(@as(u8, 1), overlord_gen2[1]);
    try testing.expectEqual(@as(u8, 1), overlord_gen1[1]);
    Overlord07_MovingFloor(1);
    try testing.expectEqual(@as(u8, 0), overlord_gen1[1]); // hit zero, restart
}

test "the falling stalfos waits for the trap to be armed" {
    resetRam();
    BG2HOFS_copy2.* = 0;
    BG2VOFS_copy2.* = 0;
    Overlord_SetX(0, 0x40);
    Overlord_SetY(0, 0x40);
    overlord_gen1[0] = 0;
    byte_7E0B9E.* = 0;
    Overlord05_FallingStalfos(0);
    try testing.expectEqual(@as(u8, 0), overlord_gen1[0]); // still waiting

    byte_7E0B9E.* = 1;
    Overlord05_FallingStalfos(0);
    try testing.expectEqual(@as(u8, 1), overlord_gen1[0]); // armed
}

test "an off-screen overlord does nothing" {
    resetRam();
    BG2HOFS_copy2.* = 0x400; // scrolled far away
    BG2VOFS_copy2.* = 0;
    Overlord_SetX(0, 0x40);
    Overlord_SetY(0, 0x40);
    overlord_gen1[0] = 0;
    byte_7E0B9E.* = 1;
    Overlord05_FallingStalfos(0);
    try testing.expectEqual(@as(u8, 0), overlord_gen1[0]);
}

test "the handler table has one entry per overlord type" {
    try testing.expectEqual(26, kOverlordFuncs.len);
    // The six falling-square variants share one handler, as do the four
    // pirogusu spawners.
    try testing.expectEqual(kOverlordFuncs[9], kOverlordFuncs[14]);
    try testing.expectEqual(kOverlordFuncs[15], kOverlordFuncs[18]);
    // Type 26 reuses the bad switch snake.
    try testing.expectEqual(kOverlordFuncs[5], kOverlordFuncs[25]);
}
