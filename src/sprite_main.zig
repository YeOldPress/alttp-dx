//! Handwritten sprite actors, drawing, cutscenes and boss AI from sprite_main.c.
//!
//! Merged from the sprite_main_partN modules the port was written in one band at a
//! time. Helpers several parts defined identically are shared; those with
//! incompatible signatures, that shadow an exported symbol, or whose name is used
//! as a local elsewhere keep suffixed names rather than being unified.
//! sprite_main_part3.zig is omitted: every symbol it exported is also defined in
//! sprite_main_extra.zig, whose actors call them internally.

const std = @import("std");
const v = @import("variables.zig");
const a = @import("sprite_main_abi.zig");
const t = @import("sprite_main_tables.zig");
const features = @import("features.zig");
const SpriteSpawnInfo = a.SpriteSpawnInfo;
const PrepOamCoordsRet = a.PrepOamCoordsRet;
const SpriteHitBox = a.SpriteHitBox;
const OamEnt = v.OamEnt;
inline fn ix_smz(k: c_int) usize {
    return @intCast(k);
}
inline fn byte(x: anytype) u8 {
    return @truncate(@as(u32, @bitCast(@as(i32, @intCast(x)))));
}
inline fn word(x: anytype) u16 {
    return @truncate(@as(u32, @bitCast(@as(i32, @intCast(x)))));
}
inline fn sign8_smz(x: anytype) bool {
    return byte(x) & 0x80 != 0;
}
inline fn sign16(x: anytype) bool {
    return word(x) & 0x8000 != 0;
}
inline fn lo_smz(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}
inline fn hi_smz(p: *align(1) u16) *u8 {
    return @ptrCast(@as([*]u8, @ptrCast(p)) + 1);
}
inline fn ram8(comptime off: usize) *u8 {
    return &v.g_ram[off];
}
inline fn ram16(comptime off: usize) *align(1) u16 {
    return @ptrCast(&v.g_ram[off]);
}
inline fn ram(comptime off: usize) [*]u8 {
    return @ptrCast(&v.g_ram[off]);
}
const moldorm_x_lo = ram(0x1fc00);
const moldorm_x_hi_smz = ram(0x1fc80);
const moldorm_y_lo = ram(0x1fd00);
const moldorm_y_hi_smz = ram(0x1fd80);
const byte_7FFE01_smz = ram8(0x1fe01);
const word_7FFE00 = ram16(0x1fe00);
const word_7FFE02 = ram16(0x1fe02);
const word_7FFE04 = ram16(0x1fe04);
const word_7FFE06 = ram16(0x1fe06);
fn garnishOverwrite(limit: u8) c_int {
    const k = GarnishAllocLimit(limit);
    if (k >= 0) return k;
    v.byte_7E0FF8.* -%= 1;
    if (sign8_smz(v.byte_7E0FF8.*)) v.byte_7E0FF8.* = limit;
    return v.byte_7E0FF8.*;
}
pub fn ChainBallMult_smz(x: u16, b: u8) u8 {
    if (x >= 256) return b;
    const p = @as(u32, x) * b;
    return @truncate((p >> 8) + (p >> 7 & 1));
}
pub const GuruguruBarMult_smz = ChainBallMult_smz;
pub const ArrgiMult_smz = ChainBallMult_smz;
pub const HelmasaurMult_smz = ChainBallMult_smz;
pub const TrinexxHeadMult_smz = ChainBallMult_smz;
pub const GanonMult_smz = ChainBallMult_smz;
pub fn GuruguruBarSin_smz(angle: u16, b: u8) i8 {
    const n = ChainBallMult_smz(t.kSinusLookupTable[angle & 0xff], b);
    return @bitCast(if (angle & 0x100 != 0) 0 -% n else n);
}
pub const ArrgiSin_smz = GuruguruBarSin_smz;
pub const HelmasaurSin_smz = GuruguruBarSin_smz;
pub const TrinexxHeadSin_smz = GuruguruBarSin_smz;
pub const GanonSin_smz = GuruguruBarSin_smz;
pub fn TrinexxMult_smz(x: u8, b: u8) u8 {
    const magnitude = if (sign8_smz(x)) 0 -% x else x;
    const result = ChainBallMult_smz(magnitude, b);
    return if (sign8_smz(x)) 0 -% result else result;
}
fn oamPtr_smz() [*]OamEnt {
    return @ptrCast(&v.g_ram[v.oam_cur_ptr.*]);
}
fn setOam_smz(p: [*]OamEnt, x: u16, y: u16, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = @truncate(x), .y = if (y +% 16 < 256) @truncate(y) else 0xf0, .charnum = ch, .flags = flags };
    const n = (@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt);
    v.bytewise_extended_oam[n] = big | byte(x >> 8 & 1);
}
fn setOamPlain_smz(p: [*]OamEnt, x: u8, y: u8, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = x, .y = y, .charnum = ch, .flags = flags };
    v.bytewise_extended_oam[(@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt)] = big;
}
inline fn ix_p1(k: c_int) usize {
    return @intCast(k);
}
inline fn sign8_p1(x: anytype) bool {
    return byte(x) & 0x80 != 0;
}
inline fn lo_p1(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}
inline fn hi_p1(p: *align(1) u16) *u8 {
    return @ptrCast(@as([*]u8, @ptrCast(p)) + 1);
}
fn oamPtr_p1() [*]OamEnt {
    return @ptrCast(&v.g_ram[v.oam_cur_ptr.*]);
}
fn setOam_p1(p: [*]OamEnt, x: u16, y: u16, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = @truncate(x), .y = if (y +% 16 < 256) @truncate(y) else 0xf0, .charnum = ch, .flags = flags };
    const n = (@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt);
    v.bytewise_extended_oam[n] = big | byte(x >> 8 & 1);
}
fn setOamPlain_p1(p: [*]OamEnt, x: u8, y: u8, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = x, .y = y, .charnum = ch, .flags = flags };
    v.bytewise_extended_oam[(@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt)] = big;
}
const PointU8 = a.PointU8;
inline fn ix_p2(k: c_int) usize {
    return @intCast(k);
}
inline fn sign8_p2(x: anytype) bool {
    return byte(x) & 0x80 != 0;
}
inline fn lo_p2(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}
inline fn hi_p2(p: *align(1) u16) *u8 {
    return @ptrCast(@as([*]u8, @ptrCast(p)) + 1);
}
fn oamPtr_p2() [*]OamEnt {
    return @ptrCast(&v.g_ram[v.oam_cur_ptr.*]);
}
fn setOam_p2(p: [*]OamEnt, x: u16, y: u16, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = @truncate(x), .y = if (y +% 16 < 256) @truncate(y) else 0xf0, .charnum = ch, .flags = flags };
    const n = (@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt);
    v.bytewise_extended_oam[n] = big | byte(x >> 8 & 1);
}
fn setOamPlain_p2(p: [*]OamEnt, x: u8, y: u8, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = x, .y = y, .charnum = ch, .flags = flags };
    v.bytewise_extended_oam[(@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt)] = big;
}
const kPlayerState_Mirror: u8 = 20;
fn lanmola_lblA(k: c_int) void {
    const i = ix_p2(k);
    v.sprite_D[i] = v.sprite_x_lo[i];
    v.sprite_wallcoll[i] = v.sprite_y_lo[i];
    v.sprite_delay_aux1[i] = 74;
}
const sprite_tables = @import("sprite_tables.zig");
const misc = @import("misc.zig");
const kCheckDamageFromPlayer_Ne: u8 = 2;
inline fn ix_p4(k: c_int) usize {
    return @intCast(k);
}
inline fn sign8_p4(x: u8) bool {
    return @as(i8, @bitCast(x)) < 0;
}
fn oamPtr_p4() [*]OamEnt {
    return @ptrCast(&v.g_ram[v.oam_cur_ptr.*]);
}
fn setOam_p4(p: [*]OamEnt, x: u16, y: u16, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = @truncate(x), .y = if (y +% 16 < 256) @truncate(y) else 0xf0, .charnum = ch, .flags = flags };
    const n = (@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt);
    v.bytewise_extended_oam[n] = big | byte(x >> 8 & 1);
}
fn setOamPlain_p4(p: [*]OamEnt, x: u8, y: u8, ch: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = x, .y = y, .charnum = ch, .flags = flags };
    v.bytewise_extended_oam[(@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt)] = big;
}
inline fn ix_p5(k: c_int) usize {
    return @intCast(k);
}
inline fn sign8_p5(x: u8) bool {
    return @as(i8, @bitCast(x)) < 0;
}
inline fn s16_p5(x: i8) u16 {
    return @bitCast(@as(i16, x));
}
const cm = @import("sprite_main_common.zig");
const ix = cm.ix;
const s16 = cm.s16;
const sign8 = cm.sign8;
const oamPtr = cm.oamPtr;
const setOam = cm.setOam;
fn stalfosKnightSetToGround(k: c_int) void {
    const i = ix(k);
    v.sprite_ai_state[i] = 2;
    v.sprite_ignore_projectile[i] = 0;
    v.sprite_z[i] = 0;
    v.sprite_z_vel[i] = 0;
    v.sprite_delay_main[i] = 63;
}
const kCheckDamageFromPlayer_Carry: u8 = 1;
const hud_tables = @import("hud_tables.zig");
const sign16_p11 = cm.sign16;
fn somariaDecodeKeys(i: usize, keys: u8) bool {
    const held = v.joypad1H_last.* & keys;
    if (held & 8 != 0) {
        v.sprite_D[i] = 0;
    } else if (held & 4 != 0) {
        v.sprite_D[i] = 1;
    } else if (held & 2 != 0) {
        v.sprite_D[i] = 2;
    } else if (held & 1 != 0) {
        v.sprite_D[i] = 3;
    } else {
        return false;
    }
    return true;
}
inline fn FindInByteArray(data: []const u8, lookfor: u8, size: usize) c_int {
    var i = size;
    while (i > 0) {
        i -= 1;
        if (data[i] == lookfor) return @intCast(i);
    }
    return -1;
}
inline fn asr8(x: u8, comptime n: u3) u8 {
    return @bitCast(@as(i8, @bitCast(x)) >> n);
}
const sign16_p16 = cm.sign16;
inline fn chainchompX() [*]align(1) u16 {
    return @ptrCast(&v.g_ram[0x1FC00]);
}
inline fn chainchompY() [*]align(1) u16 {
    return @ptrCast(&v.g_ram[0x1FD00]);
}
inline fn moldormXLo() [*]u8 {
    return @ptrCast(&v.g_ram[0x1fc00]);
}
inline fn moldormXHi() [*]u8 {
    return @ptrCast(&v.g_ram[0x1fc80]);
}
inline fn moldormYLo() [*]u8 {
    return @ptrCast(&v.g_ram[0x1fd00]);
}
inline fn moldormYHi() [*]u8 {
    return @ptrCast(&v.g_ram[0x1fd80]);
}
fn deadrockSetDir(i: usize, d: u8) void {
    v.sprite_D[i] = d;
    v.sprite_x_vel[i] = @bitCast(t.kDeadRock_Xvel[d]);
    v.sprite_y_vel[i] = @bitCast(t.kDeadRock_Yvel[d]);
}
fn sluggulaSetVel(i: usize, d: u8) void {
    v.sprite_x_vel[i] = @bitCast(t.kSluggula_XYvel[d]);
    v.sprite_y_vel[i] = @bitCast(t.kSluggula_XYvel[@as(usize, d) + 2]);
}
fn hintNpcCommon(k: c_int, paid_msg: u16) void {
    const i = ix(k);
    switch (v.sprite_ai_state[i]) {
        0 => a.DarkWorldHintNPC_Idle(k),
        1 => {
            if (v.choice_in_multiselect_box.* == 0 and a.DarkWorldHintNPC_HandlePayment()) {
                a.Sprite_ShowMessageUnconditional(paid_msg);
                v.sprite_ai_state[i] = 2;
            } else {
                a.Sprite_ShowMessageUnconditional(0x100);
                v.sprite_ai_state[i] = 0;
            }
        },
        2 => a.DarkWorldHintNPC_RestoreHealth(k),
        else => {},
    }
}
const kHudItem_Hammer: u8 = 12;
const kHudItem_Flute: u8 = 13;
fn spawnCauldron(k: c_int, subtype: u8, dx: i16, dy: i16) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xe9, &info);
    const ju = ix(j);
    v.sprite_subtype2[ju] = subtype;
    a.Sprite_SetX(j, info.r0_x +% @as(u16, @bitCast(dx)));
    a.Sprite_SetY(j, info.r2_y +% @as(u16, @bitCast(dy)));
    v.sprite_flags4[ju] = 3;
    v.sprite_defl_bits[ju] |= 0x20;
}
fn cauldronPurchase(k: c_int, cost: u16, item: u8) void {
    const i = ix(k);
    a.Sprite_BehaveAsBarrier(k);
    if (v.sprite_delay_main[i] != 0)
        return;
    if (!PotionCauldron_CheckBottles()) {
        if ((a.Sprite_ShowMessageOnContact(k, 0x4f) & 0x100) != 0)
            PotionCauldron_GoBeep(k);
        return;
    }
    if (!a.Sprite_CheckDamageToLink_same_layer(k) or (v.filtered_joypad_L.* & 0x80) == 0)
        return;
    if (v.link_rupees_goal.* < cost) {
        a.Sprite_ShowMessageUnconditional(0x17c);
        PotionCauldron_GoBeep(k);
        return;
    }
    if (a.Sprite_Find_EmptyBottle() < 0) {
        a.Sprite_ShowMessageUnconditional(0x50);
        PotionCauldron_GoBeep(k);
        return;
    }
    a.SpriteSfx_QueueSfx3WithPan(k, 0x1d);
    v.sprite_delay_main[i] = 64;
    v.link_rupees_goal.* -%= cost;
    v.item_receipt_method.* = 0;
    a.Link_ReceiveItem(item, 0);
}
fn soldierThrowingAnim(k: c_int) void {
    const i = ix(k);
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_subtype2[i] & 0xf == 0) {
        v.sprite_A[i] +%= 1;
        if (v.sprite_A[i] == 2)
            v.sprite_A[i] = 0;
    }
    const m: usize = @as(usize, v.sprite_D[i]) * 4 + v.sprite_A[i] +
        (if (v.sprite_type[i] == 0x48) @as(usize, 16) else 0);
    v.sprite_graphics[i] = t.kSoldier_Gfx2[m];
}
const setOamPlain = cm.setOamPlain;
fn ballNChainAttackCommon(k: c_int) void {
    const i = ix(k);
    v.sprite_subtype2[i] +%= 1;
    BallNChain_Animate(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 0xf == 0)
        a.SpriteSfx_QueueSfx3WithPan(k, 6);
}
fn bushGuardCase3(k: c_int) void {
    const i = ix(k);
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.sprite_delay_main[i] == 0) {
        v.sprite_ai_state[i] = 0;
        v.sprite_delay_main[i] = 64;
    } else {
        v.sprite_graphics[i] = t.kBushSoldier_Gfx2[v.sprite_delay_main[i] >> 2];
    }
}
fn sanctuaryMantleStates(k: c_int) void {
    const i = ix(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            const x = a.Sprite_GetX(k);
            a.Sprite_SetX(k, x +% 19);
            const dir = a.Sprite_DirectionToFaceLink(k, null);
            a.Sprite_SetX(k, x);
            if (dir == 1 or dir == 3) {
                v.sprite_A[i] +%= 1;
                if (v.sprite_A[i] >= 64) {
                    v.sprite_ai_state[i] +%= 1;
                    v.flag_is_link_immobilized.* = 1;
                }
            }
        },
        1 => {
            a.SpriteSfx_QueueSfx3WithPan(k, 24);
            v.sprite_ai_state[i] +%= 1;
            v.sprite_delay_main[i] = 168;
            v.sprite_x_vel[i] = 3;
            v.sprite_delay_aux1[i] = 2;
        },
        2 => {
            a.Sprite_MoveXY(k);
            if (v.sprite_delay_main[i] == 0) {
                v.flag_is_link_immobilized.* = 0;
                v.sprite_x_vel[i] = 0;
                v.sprite_C[i] = 0;
            } else {
                v.sprite_delay_aux1[i] = 2;
            }
        },
        else => {},
    }
}
fn sanctuaryMantleGrabbed(k: c_int) void {
    const i = ix(k);
    v.sprite_subtype2[i] = 0;
    v.bitmask_of_dragstate.* = 0x81;
    v.link_speed_setting.* = 8;
    sanctuaryMantleStates(k);
}
const byte_7FFE01: *u8 = @ptrCast(&v.g_ram[0x1fe01]);
const kHudItem_Mushroom: u8 = 5;
inline fn sb(x: i8) u8 {
    return @bitCast(x);
}
const kPlayerState_RecoilWall: u8 = 2;
const kHudItem_BookMudora: u8 = 15;
fn showLaterMsg(k: c_int) void {
    const i = ix(k);
    a.Sprite_ShowMessageUnconditional(0x14c);
    v.sprite_ai_state[i] = 0;
    v.sprite_delay_main[i] = 255;
}
const word_7FFE00_p39: *align(1) u16 = @ptrCast(&v.g_ram[0x1fe00]);
const word_7FFE02_p39: *align(1) u16 = @ptrCast(&v.g_ram[0x1fe02]);
const word_7FFE04_p39: *align(1) u16 = @ptrCast(&v.g_ram[0x1fe04]);
const word_7FFE06_p39: *align(1) u16 = @ptrCast(&v.g_ram[0x1fe06]);
const ProjectSpeedRet = a.ProjectSpeedRet;
const moldorm_x_hi: [*]u8 = @ptrCast(&v.g_ram[0x1fc80]);
const moldorm_y_hi: [*]u8 = @ptrCast(&v.g_ram[0x1fd80]);
fn trinexxInitCommon(k: c_int) void {
    const i = ix(k);
    var n: c_int = 0x1a;
    while (n >= 0) : (n -= 1) {
        const j = ix(n);
        v.alt_sprite_type[j] = 0x40;
        v.alt_sprite_x_hi[j] = 0;
        v.alt_sprite_y_hi[j] = 0;
    }
    v.sprite_subtype2[i] = 1;
    Trinexx_CachePosition(k);
}
const link_hearts_filler16: *align(1) u16 = @ptrCast(&v.g_ram[0xf372]);
fn tektiteResetState(k: c_int) void {
    const i = ix(k);
    v.sprite_ai_state[i] = 0;
    v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 72;
    v.sprite_y_vel[i] = 0;
    v.sprite_x_vel[i] = 0;
}
const st_p53 = @import("sprite_tables.zig");
fn thiefCommon(k: c_int) void {
    const i = ix(k);
    if (v.frame_counter.* & 31 == 0)
        v.sprite_D[i] = v.sprite_head_dir[i];
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = t.kThief_Gfx[4 + @as(usize, v.sprite_D[i]) + @as(usize, v.sprite_subtype2[i] & 4)];
}
fn helmasaurAnimClk(k: c_int) void {
    const i = ix(k);
    if (v.sprite_anim_clock[i] == 0) {
        v.sprite_anim_clock[i] +%= 1;
        v.sprite_delay_aux3[i] = 32;
    }
}
const overlord_gen1_w5: *align(1) u16 = @ptrCast(&v.g_ram[0xb2d]);
const overlord_gen2_w1: *align(1) u16 = @ptrCast(&v.g_ram[0xb31]);
fn zirroSetDir(k: c_int) void {
    const i = ix(k);
    v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = v.sprite_D[i] << 1 | (v.sprite_subtype2[i] >> 3 & 1);
}
fn kholdstareCheckColl(k: c_int) void {
    const i = ix(k);
    const j = a.Sprite_CheckTileCollision(k);
    if (j & 3 != 0) {
        v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
        v.sprite_z_vel[i] = 0 -% v.sprite_z_vel[i];
    }
    if (j & 12 != 0) {
        v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
        v.sprite_z_subpos[i] = 0 -% v.sprite_z_subpos[i];
    }
}
const overlord_x_lo_w0: *align(1) u16 = @ptrCast(&v.g_ram[0xb08]);
fn flyingTileAnimate(k: c_int) void {
    const i = ix(k);
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = v.sprite_subtype2[i] >> 2 & 1;
    if ((k ^ @as(c_int, v.frame_counter.*)) & 7 == 0)
        a.SpriteSfx_QueueSfx2WithPan(k, 0x7);
}
fn flyingTileShatter(k: c_int) void {
    const i = ix(k);
    a.SpriteSfx_QueueSfx2WithPan(k, 0x1f);
    v.sprite_state[i] = 6;
    v.sprite_delay_main[i] = 31;
    v.sprite_type[i] = 0xec;
    v.sprite_hit_timer[i] = 0;
    v.sprite_C[i] = 0x80;
}
const f_p75 = @import("features.zig");
const kPlayerState_OpeningDesertPalace: u8 = 27;
const dma_var6_lo: [*]u8 = @ptrCast(v.dma_var6);
const dma_var7_lo: [*]u8 = @ptrCast(v.dma_var7);
const kPlayerState_SpinAttacking: u8 = 3;
const kPlayerState_Hookshot: u8 = 19;
const s_ex = @import("sprite.zig");
const Info = s_ex.PrepOamCoordsRet;
const Spawn = s_ex.SpriteSpawnInfo;
inline fn ix_ex(n: anytype) usize { return @intCast(n); }
inline fn b_ex(n: anytype) u8 { return @truncate(@as(u32, @bitCast(@as(i32, @intCast(n))))); }
inline fn w_ex(n: anytype) u16 { return @truncate(@as(u32, @bitCast(@as(i32, @intCast(n))))); }
inline fn signed(n: u8) i32 { return @as(i8, @bitCast(n)); }
inline fn neg(n: u8) u8 { return 0 -% n; }
inline fn low(p: *align(1) u16) *u8 { return @ptrCast(p); }
inline fn oam_ex() [*]align(1) v.OamEnt { return @ptrCast(&v.g_ram[v.oam_cur_ptr.*]); }
fn draw(k: c_int, data: []const s_ex.DrawMultipleData, off: usize, count: c_int, deferred: bool, shadow: bool) void {
    var info: Info = undefined;
    if (deferred) a.Sprite_DrawMultiplePlayerDeferred(k, data.ptr + off, count, &info) else a.Sprite_DrawMultiple(k, data.ptr + off, count, &info);
    if (shadow) a.SpriteDraw_Shadow(k, &info);
}
fn batUpdatePosition(i: usize, j: usize) void { if (v.frame_counter.* & 7 == 0) v.sprite_y_vel[i] +%= if (t.kRetreatBat_Ypos[j] >= v.cur_sprite_y.*) @as(u8, 1) else 255; if (v.frame_counter.* & 15 == 0) v.sprite_x_vel[i] +%= 1; }
fn setOam_ex(p: [*]align(1) v.OamEnt, x: u16, y: u16, tile: u8, flags: u8, big: u8) void {
    p[0] = .{ .x = b_ex(x), .y = if (y +% 16 < 256) b_ex(y) else 0xf0, .charnum = tile, .flags = flags };
    v.bytewise_extended_oam[(@intFromPtr(p) - @intFromPtr(v.oam_buf)) / 4] = big | b_ex(x >> 8 & 1);
}
fn setOamPlain_ex(p: [*]align(1) v.OamEnt, x: u16, y: u16, tile: u8, flags: u8, big: u8) void { p[0] = .{.x=b_ex(x),.y=b_ex(y),.charnum=tile,.flags=flags}; v.bytewise_extended_oam[(@intFromPtr(p) - @intFromPtr(v.oam_buf)) / 4] = big; }

// ---------------------------------------------------------------------------
// from sprite_main.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_PullSwitch_bounce(k: c_int) callconv(.c) void {
    if (v.sprite_type[ix_smz(k)] == 5 or v.sprite_type[ix_smz(k)] == 7) a.PullSwitch_FacingUp(k) else a.PullSwitch_FacingDown(k);
}
pub export fn GiantMoldorm_DrawSegment_AB(k: c_int, lookback: c_int) callconv(.c) void {
    const i = ix_smz(k);
    const j = ix_smz((@as(c_int, v.sprite_subtype2[i]) - lookback) & 0x7f);
    v.cur_sprite_x.* = @as(u16, moldorm_x_lo[j]) | @as(u16, moldorm_x_hi_smz[j]) << 8;
    v.cur_sprite_y.* = @as(u16, moldorm_y_lo[j]) | @as(u16, moldorm_y_hi_smz[j]) << 8;
    v.oam_cur_ptr.* +%= 0x10;
    v.oam_ext_cur_ptr.* +%= 4;
    a.Sprite_DrawMultiple(k, @ptrCast(&t.kGiantMoldorm_SegA_Dmd[(v.sprite_subtype2[i] >> 1 & 1) * 4]), 4, null);
}
pub export fn GiantMoldorm_DrawSegment_C_OrTail(k: c_int, lookback: c_int) callconv(.c) void {
    const i = ix_smz(k);
    const j = ix_smz((@as(c_int, v.sprite_subtype2[i]) - lookback) & 0x7f);
    v.cur_sprite_x.* = @as(u16, moldorm_x_lo[j]) | @as(u16, moldorm_x_hi_smz[j]) << 8;
    v.cur_sprite_y.* = @as(u16, moldorm_y_lo[j]) | @as(u16, moldorm_y_hi_smz[j]) << 8;
    const bak = v.sprite_oam_flags[i];
    v.sprite_oam_flags[i] = (bak & 0x3f) | t.kGiantMoldorm_OamFlags[v.sprite_subtype2[i] >> 1 & 3];
    a.SpriteDraw_SingleLarge(k);
    v.sprite_oam_flags[i] = bak;
}
pub export fn Chicken_IncrSubtype2(k: c_int, j: c_int) callconv(.c) void {
    const i = ix_smz(k);
    v.sprite_subtype2[i] +%= byte(j);
    v.sprite_graphics[i] = v.sprite_subtype2[i] >> 4 & 1;
    _ = a.Sprite_ReturnIfLifted(k);
}
pub export fn Octoballoon_Find() callconv(.c) bool {
    var k: usize = 16;
    while (k != 0) {
        k -= 1;
        if (v.sprite_state[k] != 0 and v.sprite_type[k] == 0x10) return true;
    }
    return false;
}
pub export fn FluteBoy_CheckIfPlayerClose(k: c_int) callconv(.c) bool {
    const xx: c_int = a.Sprite_GetX(k);
    const yy: c_int = @as(c_int, a.Sprite_GetY(k)) - 16;
    var x = @as(c_int, v.link_x_coord.*) - xx - @intFromBool(yy < 0);
    var y = @as(c_int, v.link_y_coord.*) - yy - @intFromBool(x < 0);
    if (sign16(x)) x = ~x;
    if (sign16(y)) y = ~y;
    return word(x) < 48 and word(y) < 48;
}
pub export fn FortuneTeller_LightOrDarkWorld(k: c_int, dark_world: bool) callconv(.c) void {
    const i = ix_smz(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_graphics[i] = 0;
            const j = a.GetRandomNumber() & 3;
            v.sprite_A[i] = j << 1;
            v.sprite_ai_state[i] = if (v.link_rupees_goal.* < t.kFortuneTeller_Prices[j]) 1 else 2;
        },
        1 => {
            _ = a.Sprite_ShowSolicitedMessage(k, 0xf2);
        },
        2 => {
            if (a.Sprite_ShowSolicitedMessage(k, 0xf3) & 0x100 != 0) {
                v.sprite_delay_main[i] = 255;
                v.flag_is_link_immobilized.* = 1;
                v.sprite_ai_state[i] = 3;
            }
        },
        3 => {
            if (v.choice_in_multiselect_box.* == 0) {
                if (v.sprite_delay_main[i] == 0) v.sprite_ai_state[i] +%= 1;
                v.sprite_graphics[i] = v.frame_counter.* >> 4 & 1;
            } else {
                a.Sprite_ShowMessageUnconditional(0xf5);
                v.sprite_ai_state[i] = 2;
                v.flag_is_link_immobilized.* = 0;
            }
        },
        4 => a.FortuneTeller_PerformPseudoScience(k),
        5 => {
            if (!dark_world) v.sprite_graphics[i] = 0;
            const j = t.kFortuneTeller_Prices[v.sprite_A[i] >> 1];
            v.dialogue_number[0] = j / 10 | j % 10 << 4;
            v.dialogue_number[1] = 0;
            a.Sprite_ShowMessageUnconditional(0xf4);
            v.sprite_ai_state[i] +%= 1;
        },
        6 => {
            v.link_rupees_goal.* -%= t.kFortuneTeller_Prices[v.sprite_A[i] >> 1];
            v.sprite_ai_state[i] +%= 1;
            v.link_hearts_filler.* = 160;
            v.flag_is_link_immobilized.* = 0;
        },
        else => {},
    }
}
pub export fn GarnishAllocForce() callconv(.c) c_int {
    var k: c_int = 29;
    while (k >= 0) : (k -= 1) {
        if (v.garnish_type[ix_smz(k)] == 0) return k;
    }
    return 0;
}
pub export fn GarnishAlloc() callconv(.c) c_int {
    return GarnishAllocLimit(29);
}
pub export fn GarnishAllocLow() callconv(.c) c_int {
    return GarnishAllocLimit(14);
}
pub export fn GarnishAllocLimit(limit: c_int) callconv(.c) c_int {
    var k = limit;
    while (k >= 0 and v.garnish_type[ix_smz(k)] != 0) : (k -= 1) {}
    return k;
}
pub export fn GarnishAllocOverwriteOldLow() callconv(.c) c_int {
    return garnishOverwrite(14);
}
pub export fn GarnishAllocOverwriteOld() callconv(.c) c_int {
    return garnishOverwrite(29);
}
pub export fn Garnish_SetX(k: c_int, x: u16) callconv(.c) void {
    v.garnish_x_lo[ix_smz(k)] = @truncate(x);
    v.garnish_x_hi[ix_smz(k)] = @truncate(x >> 8);
}
pub export fn Garnish_SetY(k: c_int, y: u16) callconv(.c) void {
    v.garnish_y_lo[ix_smz(k)] = @truncate(y);
    v.garnish_y_hi[ix_smz(k)] = @truncate(y >> 8);
}
pub export fn Sprite_WishPond3(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    const items: [*]u8 = @ptrCast(v.link_item_bow);
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.flag_is_link_immobilized.* = 0;
            if (v.sprite_delay_main[i] != 0 or a.Sprite_CheckIfLinkIsBusy()) return;
            if (a.Sprite_ShowMessageOnContact(k, 0x14a) & 0x100 != 0) {
                v.sprite_ai_state[i] = 1;
                a.Link_ResetProperties_A();
                v.link_direction_facing.* = 0;
                v.sprite_head_dir[i] = 0;
            }
        },
        1 => {
            if (v.choice_in_multiselect_box.* == 0) {
                a.Sprite_ShowMessageUnconditional(0x8a);
                v.sprite_ai_state[i] = 2;
                v.flag_is_link_immobilized.* = 1;
            } else {
                a.Sprite_ShowMessageUnconditional(0x14b);
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 255;
            }
        },
        2 => {
            v.sprite_ai_state[i] = 3;
            const j = v.choice_in_multiselect_box.*;
            v.sprite_C[i] = j;
            const item = items[j];
            items[j] = 0;
            const n = @as(usize, t.kWishPondItemOffs[j]) + (if (j == 3 or j == 32) @as(usize, 1) else item) - 1;
            const item_id = t.kWishPondItemData[n];
            a.AncillaAdd_TossedPondItem(0x28, item_id, 4);
            a.Hud_RefreshIcon();
            v.sprite_graphics[i] = item_id;
            v.sprite_D[i] = item;
            v.sprite_delay_main[i] = 255;
        },
        3 => {
            if (v.sprite_delay_main[i] == 0) {
                var info: SpriteSpawnInfo = undefined;
                const j = a.Sprite_SpawnDynamically(k, 0x72, &info);
                std.debug.assert(j >= 0);
                a.Sprite_SetX(j, info.r0_x);
                a.Sprite_SetY(j, info.r2_y -% 80);
                v.music_control.* = 0x1b;
                v.last_music_control.* = 0;
                v.sprite_B[ix_smz(j)] = 1;
                a.Palette_AssertTranslucencySwap();
                a.PaletteFilter_WishPonds();
                v.sprite_E[i] = byte(j);
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 255;
            }
        },
        4 => {
            if (v.frame_counter.* & 7 == 0) {
                a.PaletteFilter_SP5F();
                if (lo_smz(v.palette_filter_countdown).* == 0) {
                    a.Sprite_ShowMessageUnconditional(0x8b);
                    a.Palette_RevertTranslucencySwap();
                    v.TS_copy.* = 0;
                    v.CGADSUB_copy.* = 0x20;
                    v.flag_update_cgram_in_nmi.* +%= 1;
                    v.sprite_ai_state[i] = 5;
                }
            }
        },
        5 => v.sprite_ai_state[i] = if (v.choice_in_multiselect_box.* == 0) 6 else 11,
        6 => {
            v.sprite_ai_state[i] = 7;
            if (v.savegame_is_darkworld.* == 0) {
                switch (v.sprite_graphics[i]) {
                    12 => {
                        v.sprite_graphics[i] = 42;
                        v.sprite_head_dir[i] = 1;
                    },
                    4 => {
                        v.sprite_graphics[i] = 5;
                        v.sprite_head_dir[i] = 2;
                    },
                    22 => {
                        v.sprite_graphics[i] = 44;
                        v.sprite_head_dir[i] = 3;
                    },
                    else => {
                        a.Sprite_ShowMessageUnconditional(0x14d);
                        return;
                    },
                }
            } else {
                switch (v.sprite_graphics[i]) {
                    58 => {
                        v.sprite_graphics[i] = 59;
                        v.sprite_head_dir[i] = 4;
                        a.Sprite_ShowMessageUnconditional(0x14f);
                        return;
                    },
                    2 => {
                        v.sprite_graphics[i] = 3;
                        v.sprite_head_dir[i] = 5;
                    },
                    22 => {
                        v.sprite_graphics[i] = 44;
                        v.sprite_head_dir[i] = 3;
                    },
                    else => {
                        a.Sprite_ShowMessageUnconditional(0x14d);
                        return;
                    },
                }
            }
            a.Sprite_ShowMessageUnconditional(0x8c);
        },
        7 => {
            if (v.sprite_C[i] == 3) items[v.sprite_C[i]] = v.sprite_D[i];
            a.Palette_AssertTranslucencySwap();
            v.TS_copy.* = 2;
            v.CGADSUB_copy.* = 0x30;
            v.flag_update_cgram_in_nmi.* +%= 1;
            v.sprite_ai_state[i] = 8;
        },
        8 => {
            if (v.frame_counter.* & 7 == 0) {
                a.PaletteFilter_SP5F();
                if (lo_smz(v.palette_filter_countdown).* == 30) {
                    v.sprite_state[v.sprite_E[i]] = 0;
                } else if (lo_smz(v.palette_filter_countdown).* == 0) {
                    v.sprite_ai_state[i] = 9;
                }
            }
        },
        9 => {
            a.PaletteFilter_RestoreSP5F();
            a.Palette_RevertTranslucencySwap();
            v.item_receipt_method.* = 2;
            a.Link_ReceiveItem(v.sprite_graphics[i], 0);
            v.sprite_ai_state[i] = 10;
        },
        10 => {
            if (v.sprite_head_dir[i] != 0) a.Sprite_ShowMessageUnconditional(t.kWishPondMsgs[v.sprite_head_dir[i] - 1]);
            v.sprite_ai_state[i] = 0;
            v.sprite_delay_main[i] = 255;
        },
        11 => {
            a.Sprite_ShowMessageUnconditional(0x8d);
            v.sprite_ai_state[i] = 12;
        },
        12 => v.sprite_ai_state[i] = if (v.choice_in_multiselect_box.* == 0) 13 else 6,
        13 => {
            a.Sprite_ShowMessageUnconditional(0x8e);
            v.sprite_ai_state[i] = 7;
        },
        else => {},
    }
}
pub export fn Sprite_SpawnSmallSplash(k: c_int) callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamicallyEx(k, 0xec, &info, 14);
    if (j >= 0) {
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sound_effect_1.* = 0;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x28);
        v.sprite_state[ix_smz(j)] = 3;
        v.sprite_delay_main[ix_smz(j)] = 15;
        v.sprite_ai_state[ix_smz(j)] = 0;
        v.sprite_flags2[ix_smz(j)] = 3;
    }
    return j;
}
pub export fn HeartUpgrade_CheckIfAlreadyObtained(k: c_int) callconv(.c) void {
    if (v.player_is_indoors.* == 0) {
        const screen = lo_smz(v.overworld_screen_index).*;
        if ((screen == 0x3b and v.save_ow_event_info[0x3b] & 0x20 == 0) or v.save_ow_event_info[screen] & 0x40 != 0) v.sprite_state[ix_smz(k)] = 0;
    } else {
        const mask: u16 = if (v.sprite_x_hi[ix_smz(k)] & 1 != 0) 0x2000 else 0x4000;
        if (v.dung_savegame_state_bits.* & mask != 0) v.sprite_state[ix_smz(k)] = 0;
    }
}
pub export fn Sprite_EE_MovableMantle(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    a.MovableMantle_Draw(k);
    if (a.Sprite_ReturnIfInactive(k) or !a.Sprite_CheckDamageToLink_same_layer(k)) return;
    a.Sprite_NullifyHookshotDrag();
    a.Sprite_RepelDash();
    if (v.follower_indicator.* != 1 or v.link_item_torch.* == 0 or v.link_is_running.* != 0 or v.sprite_G[i] == 0x90 or sign8_smz(@as(c_int, v.link_actual_vel_x.*) - 24)) return;
    v.which_starting_point.* = 4;
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_subtype2[i] & 1 == 0) v.sprite_G[i] +%= 1;
    if (v.sprite_G[i] < 8) return;
    if (v.sound_effect_1.* == 0) v.sound_effect_1.* = 34;
    v.sprite_x_vel[i] = 2;
    a.Sprite_MoveXY(k);
}
pub export fn Sprite_GoodOrBadArcheryTarget(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    if (v.sprite_A[i] == 1) {
        if (v.sprite_G[i] >= 5) v.sprite_B[i] = 6;
        v.sprite_flags2[i] &= 0xe0;
        const j = if (v.sprite_delay_aux2[i] != 0) v.sprite_delay_aux2[i] else v.sprite_subtype2[i] >> 3;
        v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0xbf) | (j & 4) << 4;
        lo_smz(v.cur_sprite_y).* -%= 3;
        a.SpriteDraw_SingleLarge(k);
        if (v.sprite_delay_aux2[i] != 0) {
            if (v.sprite_delay_aux2[i] == 96 and v.submodule_index.* == 0) {
                v.sprite_delay_main[0] = 112;
                v.link_rupees_goal.* +%= t.kArcheryGame_CashPrize[v.sprite_B[i] - 1];
            }
            v.sprite_flags2[i] |= 5;
            a.ArcheryGame_DrawPrize(k);
        }
    } else {
        v.sprite_flags2[i] &= 0xe0;
        lo_smz(v.cur_sprite_y).* +%= 3;
        a.SpriteDraw_SingleLarge(k);
    }
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_delay_aux3[i] == 1) v.sound_effect_1.* = 0x3c;
    v.sprite_subtype2[i] +%= 1;
    a.Sprite_MoveX(k);
    if (v.sprite_delay_aux1[i] == 0) {
        v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
        if (v.sprite_delay_main[i] == 0) {
            if (a.Sprite_CheckTileCollision(k) != 0) {
                v.sprite_delay_main[i] = 16;
                v.sprite_delay_aux2[i] = 0;
            }
        } else if (v.sprite_delay_main[i] == 1) {
            v.sprite_x_lo[i] = byte(t.kArcheryTarget_X[v.sprite_graphics[i]]);
            v.sprite_x_hi[i] = byte(v.link_x_coord.* >> 8);
            v.sprite_delay_aux1[i] = 32;
            v.sprite_G[i] = 0;
        }
    }
}
pub export fn ChainBallTrooper_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    a.SpriteDraw_GuardHead(k, &info, 6);
    a.SpriteDraw_BNCBody(k, &info, 5);
    a.SpriteDraw_BNCFlail(k, &info);
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    if (v.sprite_flags3[ix_smz(k)] & 0x10 != 0) a.SpriteDraw_Shadow_custom(k, &info, t.kSoldier_DrawShadow[v.sprite_D[ix_smz(k)]]);
}
pub export fn Sprite_6B_CannonTrooper(k: c_int) callconv(.c) void {
    if (v.sprite_C[ix_smz(k)] != 0) {
        a.Sprite_Cannonball(k);
        return;
    }
    std.debug.assert(false); // The original reserves this sprite ID for cannonballs only.
}
pub export fn Bee_PutInBottle(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    a.Bee_HandleInteractions(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.choice_in_multiselect_box.* == 0) {
        const j = a.Sprite_Find_EmptyBottle();
        if (j >= 0) {
            v.link_bottle_info[ix_smz(j)] = 7 +% v.sprite_head_dir[i];
            a.Hud_RefreshIcon();
            v.sprite_state[i] = 0;
            return;
        }
        a.Sprite_ShowMessageUnconditional(0xca);
    }
    v.sprite_delay_aux4[i] = 64;
    v.sprite_ai_state[i] = 1;
}
pub export fn Sprite_Wizzbeam(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    a.Wizzbeam_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_oam_flags[i] ^= 6;
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_ai_state[i] == 0) _ = a.Sprite_CheckDamageToLink(k);
    a.Sprite_MoveXY(k);
    if (a.Sprite_CheckTileCollision(k) != 0) v.sprite_state[i] = 0;
}
pub export fn Kiki_LyingInwait(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.link_is_bunny_mirror.* | v.link_disable_sprite_damage.* | v.countdown_for_blink.* != 0 or v.follower_indicator.* == 10) return;
    if (v.save_ow_event_info[lo_smz(v.overworld_screen_index).*] & 0x20 != 0) return;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0) v.follower_dropped.* = 0;
        v.follower_indicator.* = 10;
        v.tagalong_var5.* = 0;
        a.LoadFollowerGraphics();
        a.Follower_Initialize();
    }
}
pub export fn ChainChomp_OneMult(x: u8, b: u8) callconv(.c) c_int {
    const magnitude = if (sign8_smz(x)) 0 -% x else x;
    const product: u8 = @truncate(@as(u16, magnitude) * b >> 8);
    return if (sign8_smz(x)) ~@as(c_int, product) else product;
}
pub export fn Sprite_CC(k: c_int) callconv(.c) void {
    if (v.sprite_E[ix_smz(k)] == 0) {
        a.Sprite_Sidenexx(k);
        return;
    }
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_MoveXY(k);
    a.Sprite_TrinexxFire_AddFireGarnish(k);
    a.Sprite_CC_CD_Common(k);
}
pub export fn Sprite_CD(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    if (v.sprite_E[i] == 0) {
        a.Sprite_Sidenexx(k);
        return;
    }
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    const old = v.sprite_x_vel[i];
    v.sprite_x_vel[i] +%= v.sprite_C[i];
    a.Sprite_MoveXY(k);
    v.sprite_x_vel[i] = old;
    a.Sprite_CD_SpawnGarnish(k);
    a.Sprite_CC_CD_Common(k);
}
pub export fn SpritePrep_IncrXYLow8(k: c_int) callconv(.c) void {
    v.sprite_x_lo[ix_smz(k)] +%= 8;
    v.sprite_y_lo[ix_smz(k)] +%= 8;
}
pub export fn SpritePrep_FakeSword(k: c_int) callconv(.c) void {
    _ = k;
}
pub export fn SpritePrep_MedallionTable(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    v.sprite_ignore_projectile[i] +%= 1;
    if (lo_smz(v.overworld_screen_index).* != 3) {
        v.sprite_x_lo[i] +%= 8;
        if (v.link_item_bombos_medallion.* != 0) {
            v.sprite_graphics[i] = 4;
            v.sprite_ai_state[i] = 3;
        }
    } else if (v.link_item_ether_medallion.* != 0) {
        v.sprite_graphics[i] = 4;
        v.sprite_ai_state[i] = 3;
    }
}
pub export fn Hobo_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiplePlayerDeferred(k, @ptrCast(&t.kHobo_Dmd[@as(usize, v.sprite_graphics[ix_smz(k)]) * 4]), 4, null);
}
pub export fn Landmine_CheckDetonationFromHammer(k: c_int) callconv(.c) bool {
    if (v.link_item_in_hand.* & 10 == 0 or v.player_oam_y_offset.* == 0x80) return false;
    var hb: SpriteHitBox = undefined;
    a.Player_SetupActionHitBox(&hb);
    a.Sprite_SetupHitBox(k, &hb);
    return a.CheckIfHitBoxesOverlap(&hb);
}
pub export fn Sprite_DrawLargeWaterTurbulence(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    const bak = v.sprite_oam_flags[i];
    v.sprite_oam_flags[i] = if (v.sprite_subtype2[i] >> 1 & 1 != 0) 0x44 else 4;
    v.sprite_obj_prio[i] &= 0xf0;
    _ = a.Oam_AllocateFromRegionC(v.sprite_obj_prio[i]);
    a.Sprite_DrawMultiple(k, &t.kWaterTurbulence_Dmd, 6, null);
    v.sprite_oam_flags[i] = bak;
}
pub export fn Sprite_SpawnSparkleGarnish(k: c_int) callconv(.c) void {
    if (v.frame_counter.* & 3 != 0) return;
    const j = GarnishAllocForce();
    const n = ix_smz(j);
    v.garnish_type[n] = 0x12;
    v.garnish_active.* = 0x12;
    const x = a.Sprite_GetX(k) +% word(t.kSparkleGarnish_Coord[a.GetRandomNumber() & 3]);
    const y = a.Sprite_GetY(k) +% word(t.kSparkleGarnish_Coord[a.GetRandomNumber() & 3]);
    Garnish_SetX(j, x);
    Garnish_SetY(j, y);
    v.garnish_sprite[n] = byte(k);
    v.garnish_countdown[n] = 15;
}
pub export fn Sprite_70_KingHelmasaurFireball(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    const oam = oamPtr_smz();
    v.sprite_subtype2[i] +%= 1;
    const flags = t.kHelmasaurFireball_Flags[v.sprite_subtype2[i] >> 2 & 1];
    oam[0].x = v.sprite_x_lo[i] -% byte(v.BG2HOFS_copy2.*);
    if (oam[0].x +% 32 < 64) {
        v.sprite_state[i] = 0;
        return;
    }
    oam[0].y = v.sprite_y_lo[i] -% byte(v.BG2VOFS_copy2.*);
    if (oam[0].y +% 16 < 32) {
        v.sprite_state[i] = 0;
        return;
    }
    oam[0].charnum = t.kHelmasaurFireball_Char[v.sprite_graphics[i]];
    oam[0].flags = flags;
    v.bytewise_extended_oam[(@intFromPtr(oam) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt)] = 2;
    if (a.Sprite_ReturnIfInactive(k)) return;
    if ((byte(k) ^ v.frame_counter.*) & 3 == 0 and v.link_x_coord.* -% v.cur_sprite_x.* +% 8 < 16 and v.link_y_coord.* -% v.cur_sprite_y.* +% 16 < 16) a.Sprite_AttemptDamageToLinkPlusRecoil(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 18;
                v.sprite_ai_state[i] = 1;
                v.sprite_y_vel[i] = 36;
            }
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 31;
            }
            v.sprite_y_vel[i] -%= 2;
            a.Sprite_MoveY(k);
        },
        2 => {
            if (v.sprite_delay_main[i] == 0) a.HelmasaurFireball_TriSplit(k) else v.sprite_graphics[i] = t.kHelmasaurFireball_Gfx[v.sprite_delay_main[i] >> 3];
        },
        3 => {
            if (v.sprite_delay_main[i] == 0) {
                a.HelmasaurFireball_QuadSplit(k);
            } else if (v.sprite_head_dir[i] < 20) {
                v.sprite_head_dir[i] +%= 1;
                a.Sprite_MoveXY(k);
            }
        },
        4 => a.Sprite_MoveXY(k),
        else => {},
    }
}
pub export fn Sprite_66_WallCannonVerticalLeft(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    const d = v.sprite_D[i];
    v.sprite_graphics[i] = t.kWallCannon_Gfx[d] + @intFromBool(v.sprite_delay_aux2[i] != 0);
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0xbf) | t.kWallCannon_OamFlags[d];
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_delay_main[i] == 0) {
        v.sprite_delay_main[i] = 128;
        v.sprite_A[i] ^= 1;
    }
    v.sprite_x_vel[i] = byte(t.kWallCannon_Xvel[v.sprite_A[i]]);
    v.sprite_y_vel[i] = byte(t.kWallCannon_Yvel[v.sprite_A[i]]);
    a.Sprite_MoveXY(k);
    if (((k << 2) + v.frame_counter.*) & 31 == 0) v.sprite_delay_aux2[i] = 16;
    if (v.sprite_delay_aux2[i] != 1 or v.sprite_pause[i] != 0) return;
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamicallyEx(k, 0x6b, &info, 13);
    if (j < 0) return;
    const n = ix_smz(j);
    a.SpriteSfx_QueueSfx3WithPan(k, 7);
    v.sprite_C[n] = 1;
    v.sprite_graphics[n] = 1;
    const direction = v.sprite_D[i];
    a.Sprite_SetX(j, info.r0_x +% word(t.kWallCannon_Spawn_X[direction]));
    a.Sprite_SetY(j, info.r2_y +% word(t.kWallCannon_Spawn_Y[direction]));
    v.sprite_x_vel[n] = byte(t.kWallCannon_Spawn_Xvel[direction]);
    v.sprite_y_vel[n] = byte(t.kWallCannon_Spawn_Yvel[direction]);
    v.sprite_flags2[n] = (v.sprite_flags2[n] & 0xf0) | 1;
    v.sprite_flags3[n] |= 0x47;
    v.sprite_defl_bits[n] |= 0x44;
    v.sprite_delay_main[n] = 32;
}
pub export fn Sprite_65_ArcheryGame(k: c_int) callconv(.c) void {
    v.link_num_arrows.* = v.sprite_subtype[ix_smz(k)];
    if (v.sprite_A[ix_smz(k)] == 0) ArcheryGame_Host(k) else Sprite_GoodOrBadArcheryTarget(k);
}
pub export fn ArcheryGame_Host(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    if (v.archery_game_arrows_left.* == 0) v.archery_game_out_of_arrows.* +%= 1;
    a.ArcheryGameGuy_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_flags4[i] = 0;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Sprite_NullifyHookshotDrag();
        v.link_speed_setting.* = 0;
        a.Link_CancelDash();
    }
    if (v.sprite_delay_main[i] != 0) {
        if (v.sprite_delay_main[i] & 7 == 0) a.SpriteSfx_QueueSfx2WithPan(k, 0x11);
        v.sprite_graphics[i] = (v.sprite_delay_main[i] & 4) >> 2;
    } else v.sprite_graphics[i] = t.kArcheryGameGuy_Gfx[if (v.sprite_ai_state[i] != 0) v.frame_counter.* >> 5 & 3 else 0];
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_flags4[i] = 10;
            if (a.Sprite_CheckDamageToLink_same_layer(k) and v.filtered_joypad_L.* & 0x80 != 0) {
                v.sprite_ai_state[i] = 1;
                ArcheryGameGuy_ShowMsg(k, 0x85);
            }
        },
        1, 3 => {
            if (v.choice_in_multiselect_box.* == 0 and v.link_rupees_goal.* >= 20) {
                v.sprite_head_dir[i] = 0;
                v.byte_7E0B88.* = 0;
                v.sprite_ai_state[i] = 2;
                ArcheryGameGuy_ShowMsg(k, 0x86);
            } else {
                v.sprite_ai_state[i] = 0;
                ArcheryGameGuy_ShowMsg(k, 0x87);
            }
        },
        2 => ArcheryGame_Host_ProctorGame(k),
        else => {},
    }
}
pub export fn ArcheryGameGuy_ShowMsg(k: c_int, msg: c_int) callconv(.c) void {
    v.dialogue_message_index.* = word(msg);
    a.Sprite_ShowMessageMinimal();
    v.sprite_delay_main[ix_smz(k)] = 0;
}
pub export fn ArcheryGame_Host_ProctorGame(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    if (v.sprite_head_dir[i] == 0) {
        v.archery_game_arrows_left.* = 5;
        a.Sprite_InitializeSecondaryItemMinigame(2);
        v.sprite_delay_aux1[i] = 39;
        v.link_rupees_goal.* -%= 20;
        v.sprite_head_dir[i] +%= 1;
    }
    _ = a.Oam_AllocateFromRegionA(0x34);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var p = oamPtr_smz();
    const count = if (v.sprite_delay_aux1[i] != 0) t.kArcheryGame_NumSpr[v.sprite_delay_aux1[i] >> 3] else v.archery_game_arrows_left.*;
    var n: usize = @as(usize, count) * 2 + 8;
    while (n != 0) {
        n -= 1;
        setOamPlain_smz(p, byte(info.x -% 19 +% word(t.kArcheryGame_X[n])), byte(info.y -% 47 +% word(t.kArcheryGame_Y[n])), t.kArcheryGame_Char[n], t.kArcheryGame_Flags[n], 0);
        p += 1;
    }
    if (v.archery_game_arrows_left.* | v.sprite_delay_aux4[i] | v.ancilla_type[0] | v.ancilla_type[1] | v.ancilla_type[2] | v.ancilla_type[3] | v.ancilla_type[4] != 0) return;
    v.sprite_flags4[i] = 10;
    if (a.Sprite_CheckDamageToLink_same_layer(k) and v.filtered_joypad_L.* & 0x80 != 0) {
        ArcheryGameGuy_ShowMsg(k, 0x88);
        v.sprite_ai_state[i] = 3;
    }
}
pub export fn ArcheryGame_DrawPrize(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var p = oamPtr_smz() + 1;
    const b = v.sprite_B[ix_smz(k)];
    var n: usize = 5;
    while (n != 0) {
        n -= 1;
        const ch = if (n == 4) t.kGoodArcheryTarget_Draw_Char4[b - 1] else if (n == 3) t.kGoodArcheryTarget_Draw_Char3[b - 1] else t.kGoodArcheryTarget_Draw_Char[n];
        setOamPlain_smz(p, byte(info.x +% word(t.kGoodArcheryTarget_X[n])), byte(info.y +% word(t.kGoodArcheryTarget_Y[n])), ch, byte(t.kGoodArcheryTarget_Draw_Flags[n]) & (if (ch < 0x7c) @as(u8, 0xff) else 0xfe), 0);
        p += 1;
    }
    a.Sprite_DrawDistress_custom(info.x, info.y, v.frame_counter.*);
}
/// One pixel of pull towards the Debirando pit, for drag_player_x/y.
///
/// Those are 16-bit and are added straight onto link_x/y_coord, so the "back
/// one pixel" case has to be a 16-bit -1. Spelling it 255 - the 8-bit way, as
/// this port first did - drags Link 255 pixels the other way instead, which
/// threw him through walls and left the camera and his sprite far apart.
fn debirandoDragStep(vel: u8) u16 {
    return if (sign8_smz(vel)) 1 else 0xffff;
}

pub export fn Sprite_63_DebirandoPit(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    var pt: a.PointU8 = undefined;
    _ = a.Sprite_DirectionToFaceLink(k, &pt);
    if (pt.y +% 0x20 < 0x40 and pt.x +% 0x20 < 0x40) _ = a.Oam_AllocateFromRegionB(16);
    DebirandoPit_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    const j = v.sprite_head_dir[i];
    if (v.sprite_state[j] == 6) {
        v.sprite_state[i] = v.sprite_state[j];
        v.sprite_delay_main[i] = v.sprite_delay_main[j];
        v.sprite_flags2[i] +%= 4;
        return;
    }
    if (v.sprite_graphics[i] < 3 and a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Link_CancelDash();
        if (v.filtered_joypad_L.* & 16 == 0) v.link_prevent_from_moving.* = 1;
        a.Sprite_ApplySpeedTowardsLink(k, 16);
        const yv = v.sprite_y_vel[i];
        const sy = @as(u16, if (sign8_smz(yv)) 0 -% yv else yv) + v.sprite_A[i];
        v.sprite_A[i] = byte(sy);
        if (sy >= 256) v.drag_player_y.* = debirandoDragStep(yv);
        const xv = v.sprite_x_vel[i];
        const sx = @as(u16, if (sign8_smz(xv)) 0 -% xv else xv) + v.sprite_B[i];
        v.sprite_B[i] = byte(sx);
        if (sx >= 256) v.drag_player_x.* = debirandoDragStep(xv);
    }
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_graphics[i] = 6;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 63;
            }
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 255;
            } else v.sprite_graphics[i] = t.kDebirandoPit_OpeningGfx[v.sprite_delay_main[i] >> 4];
        },
        2 => {
            if (v.frame_counter.* & 15 == 0) {
                v.sprite_graphics[i] +%= 1;
                if (v.sprite_graphics[i] >= 3) v.sprite_graphics[i] = 0;
            }
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 63;
                v.sprite_ai_state[i] = 3;
            }
        },
        3 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 32;
            } else v.sprite_graphics[i] = t.kDebirandoPit_ClosingGfx[v.sprite_delay_main[i] >> 4];
        },
        else => {},
    }
}
pub export fn DebirandoPit_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    const g = v.sprite_graphics[ix_smz(k)];
    if (g == 6) return;
    var p = oamPtr_smz();
    var n: usize = 4;
    while (n != 0) {
        n -= 1;
        const j = @as(usize, g) * 4 + n;
        setOam_smz(p, info.x +% word(t.kDebirandoPit_Draw_X[j]), info.y +% word(t.kDebirandoPit_Draw_Y[j]), t.kDebirandoPit_Draw_Char[j], t.kDebirandoPit_Draw_Flags[j] | info.flags, t.kDebirandoPit_Draw_Big[g]);
        p += 1;
    }
}
pub export fn Sprite_64_Debirando(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    Debirando_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 31;
            }
        },
        1 => {
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 128;
            } else v.sprite_graphics[i] = t.kDebirando_Emerge_Gfx[v.sprite_delay_main[i] >> 4];
        },
        2 => {
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 31;
                v.sprite_ai_state[i] +%= 1;
            } else {
                if ((v.sprite_delay_main[i] & 31) | v.sprite_G[i] | v.submodule_index.* | v.sprite_pause[i] | v.flag_unk1.* == 0) _ = a.Sprite_SpawnFireball(k);
                v.sprite_subtype2[i] +%= 1;
                v.sprite_graphics[i] = (v.sprite_subtype2[i] >> 3 & 1) + 2;
            }
        },
        3 => {
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 223;
            } else v.sprite_graphics[i] = t.kDebirando_Submerge_Gfx[v.sprite_delay_main[i] >> 4];
        },
        else => {},
    }
}
pub export fn Debirando_Draw(k: c_int) callconv(.c) void {
    if (v.sprite_ai_state[ix_smz(k)] == 0) return;
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var p = oamPtr_smz();
    var n: usize = 4;
    const d = @as(usize, v.sprite_graphics[ix_smz(k)]) * 4;
    while (n != 0) {
        n -= 1;
        const j = d + n;
        const f = t.kDebirando_Draw_Flags[j];
        setOam_smz(p, info.x +% word(t.kDebirando_Draw_X[j]), info.y +% word(t.kDebirando_Draw_Y[j]), t.kDebirando_Draw_Char[j], (f ^ info.flags) & (if (f & 15 == 0) @as(u8, 0xf0) else 0xff), t.kDebirando_Draw_Big[j]);
        p += 1;
    }
}
pub export fn Sprite_62_MasterSword(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix_smz(k)]) {
        0 => MasterSword_Main(k),
        1 => a.Sprite_MasterSword_LightFountain(k),
        2 => a.Sprite_MasterSword_LightBeam(k),
        3 => a.Sprite_MasterSword_Prop(k),
        4 => a.Sprite_MasterSword_LightWell(k),
        else => {},
    }
}
pub export fn MasterSword_Main(k: c_int) callconv(.c) void {
    const i = ix_smz(k);
    if (v.main_module_index.* != 26 and v.save_ow_event_info[lo_smz(v.overworld_screen_index).*] & 0x40 != 0) {
        v.sprite_state[i] = 0;
        return;
    }
    if (v.sprite_ai_state[i] != 5) a.MasterSword_Draw(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (a.Sprite_CheckIfLinkIsBusy() or !a.Sprite_CheckDamageToLink_same_layer(k) or v.link_direction_facing.* != 2 or v.filtered_joypad_L.* & 0x80 == 0 or v.link_which_pendants.* & 7 != 7) return;
            v.music_control.* = 10;
            v.link_disable_sprite_damage.* = 1;
            a.MasterSword_SpawnPendantProp(k, 9);
            a.MasterSword_SpawnPendantProp(k, 11);
            a.MasterSword_SpawnPendantProp(k, 15);
            a.MasterSword_SpawnLightWell(k);
            v.sprite_ai_state[i] = 1;
            v.sprite_delay_main[i] = 240;
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                a.MasterSword_SpawnLightFountain(k);
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 192;
            }
            v.link_unk_master_sword.* = 10;
            v.flag_is_link_immobilized.* = 1;
        },
        2 => {
            if (v.sprite_delay_main[i] == 0) {
                a.MasterSword_SpawnLightBeam(k, 0, 255);
                v.sprite_ai_state[i] = 3;
                v.sprite_delay_main[i] = 8;
            }
            v.link_unk_master_sword.* = 10;
            v.flag_is_link_immobilized.* = 1;
        },
        3 => {
            if (v.sprite_delay_main[i] == 0) {
                a.MasterSword_SpawnLightBeam(k, 1, 255);
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 16;
            }
            v.link_unk_master_sword.* = 11;
            v.flag_is_link_immobilized.* = 1;
        },
        4 => {
            if (v.sprite_delay_main[i] == 0) {
                v.save_ow_event_info[lo_smz(v.overworld_screen_index).*] |= 0x40;
                v.item_receipt_method.* = 0;
                a.Link_ReceiveItem(1, 0);
                v.savegame_map_icons_indicator.* = 5;
                v.link_unk_master_sword.* = 0;
                v.sprite_ai_state[i] = 5;
            }
        },
        5 => v.sprite_state[i] = 0,
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part1.zig
// ---------------------------------------------------------------------------
pub export fn ChainBallMult(av: u16, b: u8) callconv(.c) u8 {
    if (av >= 256)
        return b;
    const p: c_int = @as(c_int, av) * @as(c_int, b);
    return byte((p >> 8) + (p >> 7 & 1));
}

pub export fn GuruguruBarMult(av: u16, b: u8) callconv(.c) u8 {
    if (av >= 256)
        return b;
    const p: c_int = @as(c_int, av) * @as(c_int, b);
    return byte((p >> 8) + (p >> 7 & 1));
}

pub export fn GuruguruBarSin(av: u16, b: u8) callconv(.c) i8 {
    const tv: u8 = GuruguruBarMult(t.kSinusLookupTable[av & 0xff], b);
    return if (av & 0x100 != 0) @bitCast(0 -% tv) else @bitCast(tv);
}

pub export fn ArrgiMult(av: u16, b: u8) callconv(.c) u8 {
    if (av >= 256)
        return b;
    const p: c_int = @as(c_int, av) * @as(c_int, b);
    return byte((p >> 8) + (p >> 7 & 1));
}

pub export fn ArrgiSin(av: u16, b: u8) callconv(.c) i8 {
    const tv: u8 = ArrgiMult(t.kSinusLookupTable[av & 0xff], b);
    return if (av & 0x100 != 0) @bitCast(0 -% tv) else @bitCast(tv);
}

pub export fn HelmasaurMult(av: u16, b: u8) callconv(.c) u8 {
    if (av >= 256)
        return b;
    const p: c_int = @as(c_int, av) * @as(c_int, b);
    return byte((p >> 8) + (p >> 7 & 1));
}

pub export fn HelmasaurSin(av: u16, b: u8) callconv(.c) i8 {
    const tv: u8 = HelmasaurMult(t.kSinusLookupTable[av & 0xff], b);
    return if (av & 0x100 != 0) @bitCast(0 -% tv) else @bitCast(tv);
}

pub export fn TrinexxMult(av: u8, b: u8) callconv(.c) u8 {
    const at: u8 = if (sign8_p1(av)) 0 -% av else av;
    const p: c_int = @as(c_int, at) * @as(c_int, b);
    const res: u8 = byte((p >> 8) + (p >> 7 & 1));
    return if (sign8_p1(av)) 0 -% res else res;
}

pub export fn TrinexxHeadMult(av: u16, b: u8) callconv(.c) u8 {
    if (av >= 256)
        return b;
    const p: c_int = @as(c_int, av) * @as(c_int, b);
    return byte((p >> 8) + (p >> 7 & 1));
}

pub export fn TrinexxHeadSin(av: u16, b: u8) callconv(.c) i8 {
    const tv: u8 = TrinexxHeadMult(t.kSinusLookupTable[av & 0xff], b);
    return if (av & 0x100 != 0) @bitCast(0 -% tv) else @bitCast(tv);
}

pub export fn GanonMult(av: u16, b: u8) callconv(.c) u8 {
    if (av >= 256)
        return b;
    const p: c_int = @as(c_int, av) * @as(c_int, b);
    return byte((p >> 8) + (p >> 7 & 1));
}

pub export fn GanonSin(av: u16, b: u8) callconv(.c) i8 {
    const tv: u8 = GanonMult(t.kSinusLookupTable[av & 0xff], b);
    return if (av & 0x100 != 0) @bitCast(0 -% tv) else @bitCast(tv);
}

pub export fn Sprite_MasterSword_LightFountain(k: c_int) callconv(.c) void { // 8589dc
    const i = ix_p1(k);
    SpriteDraw_LightFountain(k);
    v.sprite_A[i] +%= 1;
    if (v.sprite_A[i] == 0) {
        v.sprite_C[i] +%= 1;
        v.sprite_state[i] = 0;
    }
    v.sprite_D[i] = v.sprite_A[i] >> 2 & 3;
    const j: usize = v.sprite_A[i] >> 5 & 7;
    v.sprite_graphics[i] = t.kMasterSword_Gfx1[j];
    if (t.kMasterSword_NumLightBeams[j] != 0)
        MasterSword_SpawnLightBeam(k, v.sprite_A[i] >> 2 & 1, t.kMasterSword_NumLightBeams[j]);
}

pub export fn Sprite_MasterSword_LightWell(k: c_int) callconv(.c) void { // 858a16
    const i = ix_p1(k);
    SpriteDraw_LightFountain(k);
    v.sprite_A[i] +%= 1;
    if (v.sprite_A[i] == 0) {
        v.sprite_C[i] +%= 1;
        v.sprite_state[i] = 0;
    }
    v.sprite_D[i] = v.sprite_A[i] >> 2 & 3;
    v.sprite_graphics[i] = 0;
}

pub export fn SpriteDraw_LightFountain(k: c_int) callconv(.c) void { // 858a94
    const i = ix_p1(k);
    _ = a.Oam_AllocateFromRegionC(4);
    a.Sprite_DrawMultiple(k, @ptrCast(&t.kMasterSword_LightBall_Dmd[@as(usize, v.sprite_graphics[i]) * 4 + v.sprite_D[i]]), 1, null);
}

pub export fn MasterSword_SpawnLightWell(k: c_int) callconv(.c) void { // 858ab6
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x62, &info);
    a.Sprite_SetSpawnedCoordinates(j, &info);
    const n = ix_p1(j);
    v.sprite_subtype2[n] = 4;
    v.sprite_oam_flags[n] = 5;
    v.sprite_flags2[n] = 0;
}

pub export fn MasterSword_SpawnLightFountain(k: c_int) callconv(.c) void { // 858ad0
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x62, &info);
    a.Sprite_SetSpawnedCoordinates(j, &info);
    const n = ix_p1(j);
    v.sprite_subtype2[n] = 1;
    v.sprite_oam_flags[n] = 5;
    v.sprite_flags2[n] = 0;
}

pub export fn Sprite_MasterSword_LightBeam(k: c_int) callconv(.c) void { // 858aea
    const i = ix_p1(k);
    a.SpriteDraw_SingleLarge(k);
    if (v.sprite_A[i] != 0) {
        a.Sprite_MoveXY(k);
        if (v.frame_counter.* & 3 != 0)
            return;
        MasterSword_SpawnReplacementLightBeam(k);
    }
    v.sprite_B[i] -%= 1;
    if (v.sprite_B[i] == 0)
        v.sprite_state[i] = 0;
}

pub export fn MasterSword_SpawnReplacementLightBeam(k: c_int) callconv(.c) void { // 858b20
    const i = ix_p1(k);
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x62, &info);
    if (j < 0)
        return;
    const n = ix_p1(j);
    a.Sprite_SetX(j, info.r0_x);
    a.Sprite_SetY(j, info.r2_y);
    v.sprite_subtype2[n] = 2;
    v.sprite_B[n] = 3;
    v.sprite_graphics[n] = v.sprite_graphics[i];
    v.sprite_oam_flags[n] = v.sprite_oam_flags[i];
    v.sprite_flags2[n] = 0;
}

pub export fn MasterSword_SpawnLightBeam(k: c_int, ain: u8, yin: u8) callconv(.c) void { // 858b62
    var info: SpriteSpawnInfo = undefined;
    var j: c_int = undefined;

    j = a.Sprite_SpawnDynamically(k, 0x62, &info);
    if (j < 0)
        return;
    {
        const n = ix_p1(j);
        a.Sprite_SetX(j, info.r0_x -% 4);
        a.Sprite_SetY(j, info.r2_y +% 4);
        v.sprite_subtype2[n] = 2;
        v.sprite_A[n] = 2;
        v.sprite_flags2[n] = 0;
        v.sprite_x_vel[n] = @bitCast(t.kMasterSword_LightBeam_Xv0[ain]);
        v.sprite_y_vel[n] = @bitCast(t.kMasterSword_LightBeam_Yv0[ain]);
        v.sprite_graphics[n] = t.kMasterSword_LightBeam_Gfx0[ain];
        v.sprite_oam_flags[n] = t.kMasterSword_LightBeam_Flags0[ain];
        v.sprite_B[n] = yin;
    }

    j = a.Sprite_SpawnDynamically(k, 0x62, &info);
    if (j < 0)
        return;
    {
        const n = ix_p1(j);
        a.Sprite_SetX(j, info.r0_x -% 4);
        a.Sprite_SetY(j, info.r2_y +% 4);
        v.sprite_subtype2[n] = 2;
        v.sprite_A[n] = 2;
        v.sprite_flags2[n] = 0;
        v.sprite_x_vel[n] = @bitCast(t.kMasterSword_LightBeam_Xv1[ain]);
        v.sprite_y_vel[n] = @bitCast(t.kMasterSword_LightBeam_Yv1[ain]);
        v.sprite_graphics[n] = t.kMasterSword_LightBeam_Gfx0[ain];
        v.sprite_oam_flags[n] = t.kMasterSword_LightBeam_Flags0[ain];
        v.sprite_B[n] = yin;
    }

    j = a.Sprite_SpawnDynamically(k, 0x62, &info);
    if (j < 0)
        return;
    {
        const n = ix_p1(j);
        a.Sprite_SetX(j, info.r0_x -% 4);
        a.Sprite_SetY(j, info.r2_y +% 4);
        v.sprite_subtype2[n] = 2;
        v.sprite_A[n] = 2;
        v.sprite_flags2[n] = 0;
        v.sprite_x_vel[n] = @bitCast(t.kMasterSword_LightBeam_Xv2[ain]);
        v.sprite_y_vel[n] = @bitCast(t.kMasterSword_LightBeam_Yv2[ain]);
        v.sprite_graphics[n] = t.kMasterSword_LightBeam_Gfx2[ain];
        v.sprite_oam_flags[n] = t.kMasterSword_LightBeam_Flags2[ain];
        v.sprite_B[n] = yin;
    }

    j = a.Sprite_SpawnDynamically(k, 0x62, &info);
    if (j < 0)
        return;
    {
        const n = ix_p1(j);
        a.Sprite_SetX(j, info.r0_x -% 4);
        a.Sprite_SetY(j, info.r2_y +% 4);
        v.sprite_subtype2[n] = 2;
        v.sprite_A[n] = 2;
        v.sprite_flags2[n] = 0;
        v.sprite_x_vel[n] = @bitCast(t.kMasterSword_LightBeam_Xv3[ain]);
        v.sprite_y_vel[n] = @bitCast(t.kMasterSword_LightBeam_Yv3[ain]);
        v.sprite_graphics[n] = t.kMasterSword_LightBeam_Gfx2[ain];
        v.sprite_oam_flags[n] = t.kMasterSword_LightBeam_Flags2[ain];
        v.sprite_B[n] = yin;
    }
}

pub export fn MasterSword_SpawnPendantProp(k: c_int, ain: u8) callconv(.c) void { // 858cd3
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x62, &info);
    if (j < 0)
        return;
    const n = ix_p1(j);
    v.sprite_oam_flags[n] = ain;
    a.Sprite_SetX(j, v.link_x_coord.*);
    a.Sprite_SetY(j, v.link_y_coord.* +% 8);
    v.sprite_graphics[n] = 4;
    v.sprite_subtype2[n] = 3;
    v.sprite_flags2[n] = 64;
    v.sprite_delay_main[n] = 228;
    const i: usize = ain >> 1 & 3;
    v.sprite_x_vel[n] = @bitCast(t.kMasterSword_Pendant_Xv[i]);
    v.sprite_y_vel[n] = @bitCast(t.kMasterSword_Pendant_Yv[i]);
}

pub export fn Sprite_MasterSword_Prop(k: c_int) callconv(.c) void { // 858d29
    const i = ix_p1(k);
    _ = a.Oam_AllocateFromRegionB(4);
    a.SpriteDraw_SingleLarge(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // drifting away
            a.Sprite_MoveXY(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 208;
                v.sprite_A[i] = v.sprite_oam_flags[i];
            }
        },
        1 => { // flashing
            v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0xe)) | (byte((k << 1) ^ @as(c_int, v.frame_counter.*)) & 0xe);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_oam_flags[i] = v.sprite_A[i];
            }
        },
        2 => { // fly
            a.Sprite_MoveXY(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_x_vel[i] = v.sprite_x_vel[i] *% 2;
                v.sprite_y_vel[i] = v.sprite_y_vel[i] *% 2;
                v.sprite_delay_main[i] = 6;
            }
            v.sprite_E[i] +%= 1;
            if (v.sprite_E[i] == 0)
                v.sprite_state[i] = 0;
        },
        else => {},
    }
}

pub export fn MasterSword_Draw(k: c_int) callconv(.c) void { // 858da8
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p1();
    var i: c_int = 5;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const n = ix_p1(i);
        oam[0].x = byte(@as(c_int, t.kMasterSword_Draw_X[n]) + @as(c_int, info.x));
        oam[0].y = byte(@as(c_int, t.kMasterSword_Draw_Y[n]) + @as(c_int, info.y));
        oam[0].charnum = t.kMasterSword_Draw_Char[n];
        oam[0].flags = info.flags;
    }
    a.Sprite_CorrectOamEntries(k, 5, 0);
}

pub export fn Sprite_5D_Roller_VerticalDownFirst(k: c_int) callconv(.c) void { // 858dde
    const i = ix_p1(k);
    v.sprite_graphics[i] = (v.sprite_subtype2[i] >> 1 & 1) | (v.sprite_D[i] & 2);
    SpikeRoller_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.sprite_delay_main[i] == 0) {
        v.sprite_delay_main[i] = 112;
        v.sprite_D[i] ^= 1;
    }
    const j: usize = v.sprite_D[i];
    v.sprite_x_vel[i] = @bitCast(t.kSpikeRoller_XYvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kSpikeRoller_XYvel[j + 2]);
    a.Sprite_MoveXY(k);
    v.sprite_subtype2[i] +%= 1;
}

pub export fn SpikeRoller_Draw(k: c_int) callconv(.c) void { // 858ee3
    const idx = ix_p1(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p1();
    const g: usize = v.sprite_graphics[idx];
    var chr: u8 = t.kSpikeRoller_Draw_Char[g * 8];

    var i: c_int = if (v.sprite_ai_state[idx] != 0) 7 else 3;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const j: usize = g * 8 + ix_p1(i);
        setOam_p1(
            oam,
            info.x +% @as(u16, t.kSpikeRoller_Draw_X[j]),
            info.y +% @as(u16, t.kSpikeRoller_Draw_Y[j]),
            if (chr != 0) chr else t.kSpikeRoller_Draw_Char[j],
            t.kSpikeRoller_Draw_Flags[j] | info.flags,
            2,
        );
        chr = 0;
    }
}

pub export fn Sprite_61_Beamos(k: c_int) callconv(.c) void { // 858f54
    const i = ix_p1(k);
    if (v.sprite_C[i] == 1) {
        Sprite_Beamos_Laser(k);
        return;
    } else if (v.sprite_C[i] != 0) {
        Sprite_Beamos_LaserHit(k);
        return;
    }

    Beamos_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_CheckTileCollision(k);
    _ = a.Sprite_CheckDamageToLink(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0) {
                a.Sprite_SpawnProbeAlways(k, v.sprite_D[i]);
                v.sprite_D[i] +%= 1;
            }
            v.sprite_D[i] &= 63;
        },
        3 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 80;
                a.SpritePrep_LoadPalette(k);
            } else {
                if (v.sprite_delay_main[i] == 15)
                    Beamos_FireLaser(k);
                v.sprite_oam_flags[i] ^= (v.sprite_delay_main[i] >> 1 & 0xe);
            }
        },
        else => {
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] = 0;
        },
    }
}

pub export fn Beamos_FireLaser(k: c_int) callconv(.c) void { // 858fc2
    if (v.sprite_limit_instance.* >= 4)
        return;
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x61, &info);
    if (j < 0)
        return;
    const n = ix_p1(j);
    a.SpriteSfx_QueueSfx3WithPan(k, 0x19);
    a.Sprite_SetX(j, info.r0_x +% @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(lo_p1(v.dungmap_var7).*))))));
    a.Sprite_SetY(j, info.r2_y +% @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(hi_p1(v.dungmap_var7).*))))));
    a.Sprite_ApplySpeedTowardsLink(j, 0x20);
    v.sprite_flags2[n] = 0x3f;
    v.sprite_flags4[n] = 0x54;
    v.sprite_C[n] = 1;
    v.sprite_defl_bits[n] = 0x48;
    v.sprite_oam_flags[n] = 3;
    v.sprite_bump_damage[n] = 4;
    v.sprite_delay_aux1[n] = 12;
    const tt: usize = v.sprite_limit_instance.*;
    v.sprite_limit_instance.* +%= 1;
    v.sprite_graphics[n] = byte(tt);
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        v.beamos_x_lo[tt * 32 + i] = v.sprite_x_lo[n];
        v.beamos_x_hi[tt * 32 + i] = v.sprite_x_hi[n];
        v.beamos_y_lo[tt * 32 + i] = v.sprite_y_lo[n];
        v.beamos_y_hi[tt * 32 + i] = v.sprite_y_hi[n];
    }
}

pub export fn Beamos_Draw(k: c_int) callconv(.c) void { // 859068
    const idx = ix_p1(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var spr_offs: usize = 0;
    if (v.sprite_D[idx] < 0x20) {
        _ = a.Oam_AllocateFromRegionB(12);
        spr_offs = 1;
    } else {
        _ = a.Oam_AllocateFromRegionC(12);
    }
    var oam = oamPtr_p1() + spr_offs;
    var i: c_int = 1;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const n = ix_p1(i);
        setOam_p1(oam, info.x, info.y +% @as(u16, @bitCast(@as(i16, t.kBeamos_Draw_Y[n]))), @bitCast(t.kBeamos_Draw_Char[n]), info.flags, 2);
    }
    SpriteDraw_Beamos_Eyeball(k, &info);
}

pub export fn SpriteDraw_Beamos_Eyeball(k: c_int, info: [*c]PrepOamCoordsRet) callconv(.c) void { // 859151
    const idx = ix_p1(k);
    const n: usize = if (v.sprite_D[idx] < 0x20) 0 else 2;
    const oam = oamPtr_p1() + n;
    const i: usize = v.sprite_D[idx] >> 1;
    lo_p1(v.dungmap_var7).* = byte(@as(c_int, t.kBeamosEyeball_Draw_X[i]) - 3);
    oam[0].x = byte(@as(c_int, lo_p1(v.dungmap_var7).*) + @as(c_int, info.*.x));
    hi_p1(v.dungmap_var7).* = byte(@as(c_int, t.kBeamosEyeball_Draw_Y[i]) - 18);
    oam[0].y = byte(@as(c_int, hi_p1(v.dungmap_var7).*) + @as(c_int, info.*.y));
    oam[0].charnum = t.kBeamosEyeball_Draw_Char[i];
    oam[0].flags = (info.*.flags & 0x31) | 0xA | t.kBeamosEyeball_Draw_Flags[i];
    v.oam_cur_ptr.* +%= word(n * 4);
    v.oam_ext_cur_ptr.* +%= word(n);
    a.Sprite_CorrectOamEntries(k, 0, 0);
}

pub export fn Sprite_Beamos_Laser(k: c_int) callconv(.c) void { // 8591b5
    const idx = ix_p1(k);
    if (v.sprite_delay_aux1[idx] != 0)
        return;
    BeamosLaser_Draw(k);
    if (v.sprite_state[idx] == 0) {
        v.sprite_limit_instance.* -%= 1;
        return;
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    var i: c_int = 3;
    while (i >= 0) : (i -= 1) {
        const ti: usize = @as(usize, v.sprite_subtype2[idx] & 31) + @as(usize, v.sprite_graphics[idx]) * 32;
        v.sprite_subtype2[idx] +%= 1;
        v.beamos_y_hi[ti] = v.sprite_y_hi[idx];
        v.beamos_y_lo[ti] = v.sprite_y_lo[idx];
        v.beamos_x_hi[ti] = v.sprite_x_hi[idx];
        v.beamos_x_lo[ti] = v.sprite_x_lo[idx];
        a.Sprite_MoveXY(k);
    }

    if (v.sprite_delay_main[idx] != 0) {
        if (v.sprite_delay_main[idx] == 1) {
            v.sprite_state[idx] = 0;
            v.sprite_limit_instance.* -%= 1;
        }
        return;
    }
    if (!a.Sprite_CheckDamageToLink_same_layer(k) and a.Sprite_CheckTileCollision(k) == 0)
        return;
    a.SpriteSfx_QueueSfx3WithPan(k, 0x26);
    v.sprite_delay_main[idx] = 16;
    a.Sprite_ZeroVelocity_XY(k);
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x61, &info);
    if (j >= 0) {
        const n = ix_p1(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_delay_main[n] = 16;
        v.sprite_flags2[n] = 3;
        v.sprite_C[n] = 2;
        v.sprite_flags3[n] = 0x40;
    }
    v.sprite_y_hi[idx] = 128;
}

pub export fn BeamosLaser_Draw(k: c_int) callconv(.c) void { // 85925b
    const idx = ix_p1(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    var oam = oamPtr_p1();
    const g: usize = v.sprite_graphics[idx];
    var i: c_int = 31;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const j: usize = g * 32 + ix_p1(i);
        const x: u16 = (@as(u16, v.beamos_x_lo[j]) | @as(u16, v.beamos_x_hi[j]) << 8) -% v.BG2HOFS_copy2.*;
        const y: u16 = (@as(u16, v.beamos_y_lo[j]) | @as(u16, v.beamos_y_hi[j]) << 8) -% v.BG2VOFS_copy2.*;
        setOam_p1(oam, x, y, 0x5c, info.flags, 0);
    }
}

pub export fn Sprite_Beamos_LaserHit(k: c_int) callconv(.c) void { // 8592da
    const idx = ix_p1(k);
    if (v.sprite_delay_main[idx] == 0)
        v.sprite_state[idx] = 0;
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p1();
    var i: c_int = 3;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const n = ix_p1(i);
        setOam_p1(
            oam,
            info.x +% @as(u16, @bitCast(@as(i16, t.kBeamosLaserHit_Draw_X[n]))),
            info.y +% @as(u16, @bitCast(@as(i16, t.kBeamosLaserHit_Draw_Y[n]))),
            0xd6,
            t.kBeamosLaserHit_Draw_Flags[n] | (info.flags & 0x30),
            0,
        );
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part2.zig
// ---------------------------------------------------------------------------
/// misc.h GetOamCurPtr().
/// sprite.h SetOamHelper0().
/// sprite.h SetOamPlain().

pub export fn Sprite_5B_Spark_Clockwise(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.frame_counter.* & 1 == 0)
        v.sprite_oam_flags[i] ^= 6;
    if (v.sprite_ai_state[i] == 0) {
        v.sprite_ai_state[i] = 1;
        v.sprite_x_vel[i] = 1;
        v.sprite_y_vel[i] = 1;
        var coll = a.Sprite_CheckTileCollision(k);
        v.sprite_x_vel[i] = 0xff;
        v.sprite_y_vel[i] = 0xff;
        coll |= a.Sprite_CheckTileCollision(k);
        const j: usize = if (coll < 4)
            (if (coll & 1 != 0) @as(usize, 0) else 1)
        else
            (if (coll & 4 != 0) @as(usize, 2) else 3);
        // C promotes the bool to int before multiplying; in Zig @intFromBool is a
        // u1, which cannot hold 4, so widen before scaling.
        v.sprite_D[i] = t.kSpark_directions[@as(usize, @intFromBool(v.sprite_type[i] != 0x5c)) * 4 + j];
    }

    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) |
        t.kSpark_OamFlags[v.frame_counter.* >> 2 & 3];
    a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckDamageToLink(k);
    var j: usize = v.sprite_D[i];
    v.sprite_x_vel[i] = @bitCast(t.kSoldierB_Xvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kSoldierB_Yvel[j]);
    _ = a.Sprite_CheckTileCollision(k);

    j = v.sprite_D[i];
    if (v.sprite_delay_aux2[i] != 0) {
        if (v.sprite_delay_aux2[i] == 6)
            j = t.kSoldierB_NextB[j];
    } else {
        if (v.sprite_wallcoll[i] & t.kSoldierB_Mask[j] == 0)
            v.sprite_delay_aux2[i] = 10;
    }
    if (v.sprite_wallcoll[i] & t.kSoldierB_Mask2[j] != 0)
        j = t.kSoldierB_NextB2[j];
    v.sprite_D[i] = @truncate(j);
    v.sprite_x_vel[i] = byte(@as(i32, t.kSoldierB_Xvel2[j]) * 2);
    v.sprite_y_vel[i] = byte(@as(i32, t.kSoldierB_Yvel2[j]) * 2);
}

pub export fn Sprite_59_LostWoodsBird(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    if (v.sprite_delay_aux1[i] != 0)
        return;
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) |
        (if (sign8_p2(v.sprite_x_vel[i])) @as(u8, 0) else 0x40);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_MoveXY(k);
    a.Sprite_MoveZ(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_graphics[i] = 0;
            v.sprite_z_vel[i] -%= 1;
            if (sign8_p2(@as(i32, v.sprite_z_vel[i]) - 0xf1))
                v.sprite_ai_state[i] = 1;
        },
        1 => {
            v.sprite_z_vel[i] +%= 2;
            if (!sign8_p2(@as(i32, v.sprite_z_vel[i]) - 0x10))
                v.sprite_ai_state[i] = 0;
            v.sprite_subtype2[i] +%= 1;
            v.sprite_graphics[i] = v.sprite_subtype2[i] >> 1 & 1;
        },
        else => {},
    }
}

pub export fn Sprite_5A_LostWoodsSquirrel(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    if (v.sprite_delay_aux1[i] != 0)
        return;
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) |
        (if (sign8_p2(v.sprite_x_vel[i])) @as(u8, 0) else 0x40);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_MoveXY(k);
    a.Sprite_MoveZ(k);
    v.sprite_z_vel[i] -%= 2;
    if (sign8_p2(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = 16;
        v.sprite_delay_main[i] = 12;
    }
    v.sprite_graphics[i] = if (v.sprite_delay_main[i] != 0) 1 else 0;
}

pub export fn Sprite_58_Crab(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    Crab_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXY(k);
    if (a.Sprite_CheckTileCollision(k) != 0 or v.sprite_delay_main[i] == 0) {
        v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 32;
        v.sprite_D[i] = v.sprite_delay_main[i] & 3;
    }
    const j: usize = v.sprite_D[i];
    v.sprite_x_vel[i] = @bitCast(t.kCrab_Xvel[j & 3]);
    v.sprite_y_vel[i] = @bitCast(t.kCrab_Yvel[j & 3]);
    v.sprite_subtype2[i] +%= 1;
    const shift: u3 = if (j < 2) 1 else 3;
    v.sprite_graphics[i] = (v.sprite_subtype2[i] >> shift) & 1;
}

pub export fn Crab_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p2();
    const d: usize = @as(usize, v.sprite_graphics[i]) * 2;
    var n: isize = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = d + @as(usize, @intCast(n));
        setOam_p2(
            oam,
            info.x +% @as(u16, @bitCast(t.kCrab_Draw_X[j])),
            info.y,
            t.kCrab_Draw_Char[j],
            @as(u8, @bitCast(t.kCrab_Draw_Flags[j])) | info.flags,
            2,
        );
    }
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_57_DesertStatue(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    DesertBarrier_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    const dmg = a.Sprite_CheckDamageToLink_same_layer(k);
    if (dmg) {
        a.Sprite_NullifyHookshotDrag();
        a.Sprite_RepelDash();
    }
    if (v.sprite_delay_main[i] != 0 or sign8_p2(v.sprite_ai_state[i]))
        return;

    if (v.sprite_ai_state[i] == 0) {
        if (v.byte_7E02F0.* == 0)
            return;
        v.sprite_ai_state[i] = v.byte_7E02F0.*;
        v.sprite_delay_main[i] = 128;
        v.sound_effect_ambient.* = 7;
    }

    if (dmg and v.link_incapacitated_timer.* == 0) {
        v.link_incapacitated_timer.* = 16;
        a.Sprite_ApplySpeedTowardsLink(k, 32);
    }

    const j: usize = v.sprite_D[i];
    v.sprite_x_vel[i] = @bitCast(t.kDesertBarrier_Xv[j]);
    v.sprite_y_vel[i] = @bitCast(t.kDesertBarrier_Yv[j]);
    a.Sprite_MoveXY(k);
    if (a.Sprite_CheckTileCollision(k) != 0)
        v.sprite_D[i] = t.kDesertBarrier_NextD[v.sprite_D[i]];
    v.flag_is_link_immobilized.* = 1;
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_subtype2[i] & 1 == 0) {
        v.sprite_G[i] +%= 1;
        if (v.sprite_G[i] == 130) {
            v.sprite_ai_state[i] = 128;
            v.flag_is_link_immobilized.* = 0;
        }
    }
}

pub export fn DesertBarrier_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    if (v.sprite_delay_main[i] == 1) {
        v.sound_effect_2.* = 0x1b;
        v.sound_effect_ambient.* = 5;
    }
    lo_p2(v.cur_sprite_x).* +%= (v.sprite_delay_main[i] >> 1) & 1;
    var pt: PointU8 = undefined;
    _ = a.Sprite_DirectionToFaceLink(k, &pt);
    if (pt.x +% 0x20 < 0x40 and pt.y +% 0x20 < 0x40)
        _ = a.Oam_AllocateFromRegionB(16);
    a.Sprite_DrawMultiple(k, &t.kDesertBarrier_Dmd, 4, null);
}

pub export fn Sprite_55_Zora(k: c_int) callconv(.c) void {
    if (v.sprite_E[ix_p2(k)] != 0) {
        Sprite_Fireball(k);
    } else {
        Sprite_Zora_Main(k);
    }
}

pub export fn Sprite_Fireball(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    v.sprite_ignore_projectile[i] = v.sprite_E[i];
    if (v.sprite_delay_main[i] != 0)
        _ = a.Oam_AllocateFromRegionC(4);
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Fireball_SpawnTrailGarnish(k);
    if (a.Sprite_CheckDamageToLink(k)) {
        v.sprite_state[i] = 0;
        return;
    }
    a.Sprite_MoveXY(k);
    if (v.player_is_indoors.* != 0 and v.sprite_delay_aux1[i] == 0 and
        ((k ^ @as(c_int, v.frame_counter.*)) & 3) == 0 and a.Sprite_CheckTileCollision(k) != 0)
    {
        v.sprite_state[i] = 0;
        return;
    }

    if ((v.link_is_bunny_mirror.* | v.link_disable_sprite_damage.*) != 0 or
        sign8_p2(v.link_state_bits.*) or v.link_shield_type.* < 2 or
        v.link_is_on_lower_level.* != v.sprite_floor[i])
        return;
    var hb: SpriteHitBox = undefined;
    a.Sprite_SetupHitBox(k, &hb);
    var j: usize = v.link_direction_facing.* >> 1;
    if (v.button_b_frames.* != 0)
        j = t.kSprite_ZoraFireball_Offs[j];
    const x = v.link_x_coord.* +% @as(u16, @bitCast(@as(i16, t.kSprite_ZoraFireball_X[j])));
    const y = v.link_y_coord.* +% @as(u16, @bitCast(@as(i16, t.kSprite_ZoraFireball_Y[j])));
    hb.r0_xlo = @truncate(x);
    hb.r8_xhi = @truncate(x >> 8);
    hb.r2 = t.kSprite_ZoraFireball_W[j];
    hb.r1_ylo = @truncate(y);
    hb.r9_yhi = @truncate(y >> 8);
    hb.r3 = t.kSprite_ZoraFireball_H[j];
    if (a.CheckIfHitBoxesOverlap(&hb)) {
        a.Sprite_PlaceRupulseSpark_2(k);
        v.sprite_state[i] = 0;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x6);
    }
}

pub export fn Sprite_Zora_Main(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (v.sprite_ai_state[i] == 0) {
        a.Sprite_PrepOamCoord(k, &info);
    } else {
        Zora_Draw(k);
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // choose surfacing location
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                const org_x = @as(u16, v.sprite_A[i]) | (@as(u16, v.sprite_B[i]) << 8);
                const org_y = @as(u16, v.sprite_C[i]) | (@as(u16, v.sprite_head_dir[i]) << 8);
                a.Sprite_SetX(k, org_x +% @as(u16, @bitCast(@as(i16, t.kSprite_Zora_Surface_XY[a.GetRandomNumber() & 7]))));
                a.Sprite_SetY(k, org_y +% @as(u16, @bitCast(@as(i16, t.kSprite_Zora_Surface_XY[a.GetRandomNumber() & 7]))));
                a.Sprite_Get16BitCoords(k);
                _ = a.Sprite_CheckTileCollision(k);
                // `goto spawn_anyway` re-enters the success arm from the else.
                var spawn = v.sprite_tiletype.* == 8;
                if (!spawn) {
                    // In Misery Mire some Zoras are placed in shallow water so they
                    // can't spawn. This lets them spawn in shallow water after a delay.
                    if (features.enhanced_features0.* & features.kFeatures0_GameChangingBugFixes != 0) {
                        if (v.sprite_tiletype.* == 9 and v.sprite_delay_aux2[i] == 1) {
                            spawn = true;
                        } else {
                            a.Sprite_SetX(k, org_x);
                            a.Sprite_SetY(k, org_y);
                            v.sprite_ignore_projectile[i] = 1;
                            if (v.sprite_delay_aux2[i] == 0)
                                v.sprite_delay_aux2[i] = 32;
                        }
                    }
                }
                if (spawn) {
                    v.sprite_delay_main[i] = 127;
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_flags3[i] |= 0x40;
                }
            }
        },
        1 => { // surfacing
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 127;
                v.sprite_flags3[i] &= ~@as(u8, 0x40);
            } else {
                v.sprite_graphics[i] = t.kSprite_Zora_SurfacingGfx[v.sprite_delay_main[i] >> 3];
            }
        },
        2 => { // attack
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 23;
            } else {
                if (v.sprite_delay_main[i] == 48)
                    _ = a.Sprite_SpawnFireball(k);
                v.sprite_graphics[i] = t.kSprite_Zora_AttackGfx[v.sprite_delay_main[i] >> 4];
            }
        },
        3 => { // submerging
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 128;
                v.sprite_graphics[i] = 0;
                v.sprite_ai_state[i] = 0;
            } else {
                v.sprite_graphics[i] = t.kSprite_Zora_SubmergeGfx[v.sprite_delay_main[i] >> 2];
            }
        },
        else => {},
    }
}

pub export fn Zora_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p2();
    const d: usize = @as(usize, v.sprite_graphics[i]) * 2;
    var n: isize = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = d + @as(usize, @intCast(n));
        const f = t.kZora_Draw_Flags[j];
        setOam_p2(
            oam,
            info.x +% @as(u16, @bitCast(@as(i16, t.kZora_Draw_X[j]))),
            info.y +% @as(u16, @bitCast(@as(i16, t.kZora_Draw_Y[j]))),
            t.kZora_Draw_Char[j],
            f | (if (f & 0xf != 0) @as(u8, 0) else info.flags),
            t.kZora_Draw_Big[j],
        );
    }
}

pub export fn WalkingZora_AdjustShadow(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    v.sprite_anim_clock[i] = @intFromBool(v.sprite_z[i] == 0 and v.sprite_tiletype.* == 9);
}

pub export fn WalkingZora_DrawWaterRipples(k: c_int) callconv(.c) void {
    if (v.sprite_anim_clock[ix_p2(k)] != 0)
        SpriteDraw_WaterRipple_WithOamAdjust(k);
}

pub export fn SpriteDraw_WaterRipple_WithOamAdjust(k: c_int) callconv(.c) void {
    SpriteDraw_WaterRipple(k);
    v.oam_cur_ptr.* +%= 8;
    v.oam_ext_cur_ptr.* +%= 2;
}

pub export fn SpriteDraw_WaterRipple(k: c_int) callconv(.c) void {
    const idx: usize = t.kWaterRipple_Idx[v.frame_counter.* >> 2 & 3];
    a.Sprite_DrawMultiple(k, t.kWaterRipple_Dmd[0..].ptr + idx * 2, 2, null);
    const oam = oamPtr_p2();
    const f = (oam[0].flags & 0x30) | 0x4;
    oam[0].flags = f;
    oam[1].flags = f | 0x40;
}

/// player.h kPlayerState_Mirror. player.zig keeps its copy file-local.

/// The `lbl_a` goto target shared by Lanmolas states 1 and 3.

pub export fn Sprite_54_Lanmolas(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    Lanmola_Draw(k);
    if (a.Sprite_ReturnIfPaused(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => {
            if ((v.sprite_delay_main[i] | v.sprite_pause[i]) == 0) {
                v.sprite_delay_main[i] = 127;
                v.sprite_ai_state[i] = 1;
                a.SpriteSfx_QueueSfx2WithPan(k, 0x35);
            }
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                a.Lanmola_SpawnShrapnel(k);
                v.sound_effect_ambient.* = 0x13;
                v.sprite_B[i] = t.kLanmola_RandB[a.GetRandomNumber() & 7];
                v.sprite_C[i] = t.kLanmola_RandC[a.GetRandomNumber() & 7];
                v.sprite_ai_state[i] = 2;
                v.sprite_z_vel[i] = 24;
                v.sprite_anim_clock[i] = 0;
                v.sprite_G[i] = 0;
                lanmola_lblA(k);
            }
        },
        2 => {
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            a.Sprite_MoveZ(k);
            if (v.sprite_anim_clock[i] == 0) {
                v.sprite_z_vel[i] -%= 1;
                if (v.sprite_z_vel[i] == 0)
                    v.sprite_anim_clock[i] +%= 1;
            } else if (v.frame_counter.* & 1 == 0) {
                const j: usize = v.sprite_G[i] & 1;
                v.sprite_z_vel[i] +%= @bitCast(t.kLanmola_ZVel[j]);
                if (v.sprite_z_vel[i] == @as(u8, @bitCast(t.kDesertBarrier_Xv[j])))
                    v.sprite_G[i] +%= 1;
            }
            const x = a.Sprite_GetX(k);
            const y = a.Sprite_GetY(k);
            const x2 = (@as(u16, v.sprite_x_hi[i]) << 8) | v.sprite_B[i];
            const y2 = (@as(u16, v.sprite_y_hi[i]) << 8) | v.sprite_C[i];
            if (x -% x2 +% 2 < 4 and y -% y2 +% 2 < 4)
                v.sprite_ai_state[i] = 3;
            const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x2, y2, 10);
            v.sprite_y_vel[i] = pt.y;
            v.sprite_x_vel[i] = pt.x;
            a.Sprite_MoveXY(k);
        },
        3 => {
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            a.Sprite_MoveXY(k);
            a.Sprite_MoveZ(k);
            if (!sign8_p2(@as(i32, v.sprite_z_vel[i]) + 20))
                v.sprite_z_vel[i] -%= 1;
            if (sign8_p2(v.sprite_z[i])) {
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 128;
                lanmola_lblA(k);
            }
        },
        4 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_x_lo[i] = t.kLanmola_RandB[a.GetRandomNumber() & 7];
                v.sprite_y_lo[i] = t.kLanmola_RandC[a.GetRandomNumber() & 7];
            }
        },
        5 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_state[i] = 0;
                if (a.Sprite_CheckIfScreenIsClear()) {
                    var si: SpriteSpawnInfo = undefined;
                    const j = a.Sprite_SpawnDynamically(k, 0xEA, &si);
                    std.debug.assert(j >= 0);
                    a.Sprite_SetSpawnedCoordinates(j, &si);
                    v.sprite_z_vel[ix_p2(j)] = 32;
                    v.sprite_A[ix_p2(j)] = 3;
                }
            }
            if (v.sprite_delay_main[i] >= 32 and v.sprite_delay_main[i] < 160 and
                v.sprite_delay_main[i] & 15 == 0)
            {
                const n: usize = @as(usize, (v.sprite_subtype2[i] -%
                    v.garnish_y_lo[i] *% 8) & 0x3f) + ix_p2(k) * 0x40;
                const xlo: u8 = v.moldorm_x_lo[n] -% @as(u8, @truncate(v.BG2HOFS_copy2.*));
                const ylo: u8 = v.moldorm_y_lo[n] -% v.beamos_x_hi[n] -%
                    @as(u8, @truncate(v.BG2VOFS_copy2.*));
                var si: SpriteSpawnInfo = undefined;
                const j = a.Sprite_SpawnDynamically(k, 0x00, &si);
                if (j >= 0) {
                    const ju = ix_p2(j);
                    v.load_chr_halfslot_even_odd.* = 11;
                    v.sprite_state[ju] = 4;
                    v.sprite_delay_main[ju] = 31;
                    v.sprite_A[ju] = 31;
                    a.Sprite_SetX(j, v.BG2HOFS_copy2.* +% xlo);
                    a.Sprite_SetY(j, v.BG2VOFS_copy2.* +% ylo);
                    v.sprite_flags2[ju] = 3;
                    v.sprite_oam_flags[ju] = 0xc;
                    a.SpriteSfx_QueueSfx2WithPan(k, 0xc);
                    if (!sign8_p2(v.garnish_y_lo[i]))
                        v.garnish_y_lo[i] -%= 1;
                }
            }
        },
        else => {},
    }
}

pub export fn Lanmola_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    const spr_offs: u16 = t.kLanmola_SprOffs[i];
    v.oam_cur_ptr.* = 0x800 +% spr_offs *% 4;
    v.oam_ext_cur_ptr.* = 0xA20 +% spr_offs;
    v.sprite_graphics[i] = a.Sprite_ConvertVelocityToAngle(
        v.sprite_x_vel[i],
        v.sprite_y_vel[i] -% v.sprite_z_vel[i],
    );
    var r2: u8 = v.sprite_subtype2[i];
    var r5: u8 = r2;
    {
        const j: usize = i * 64 + r2;
        v.moldorm_x_lo[j] = v.sprite_x_lo[i];
        v.moldorm_y_lo[j] = v.sprite_y_lo[i];
        v.beamos_x_hi[j] = v.sprite_z[i];
        v.beamos_y_hi[j] = v.sprite_graphics[i];
    }
    if (v.sprite_state[i] == 9 and (v.submodule_index.* | v.flag_unk1.*) == 0)
        v.sprite_subtype2[i] = (v.sprite_subtype2[i] +% 1) & 63;
    const r3: u8 = v.sprite_oam_flags[i] | v.sprite_obj_prio[i];
    const n: u8 = v.garnish_y_lo[i];
    if (sign8_p2(n))
        return;

    const base = oamPtr_p2();
    const back = sign8_p2(v.sprite_y_vel[i]);
    const step: isize = if (back) -1 else 1;
    var oi: isize = if (back) 7 else 0;
    var c: u8 = n;
    while (true) {
        const j: usize = @as(usize, r2) + i * 64;
        r2 = (r2 -% 8) & 63;
        const p = &base[@intCast(oi)];
        p.x = v.moldorm_x_lo[j] -% @as(u8, @truncate(v.BG2HOFS_copy2.*));
        if (!sign8_p2(v.beamos_x_hi[j]))
            p.y = v.moldorm_y_lo[j] -% v.beamos_x_hi[j] -% @as(u8, @truncate(v.BG2VOFS_copy2.*));
        const g: usize = v.beamos_y_hi[j];
        if (n != 7 or c != 0) {
            p.charnum = if (n == c) t.kLanmola_Draw_Char1[g] else 0xc6;
        } else {
            p.charnum = t.kLanmola_Draw_Char0[g];
        }
        p.flags = t.kLanmola_Draw_Flags[g] | r3;
        v.bytewise_extended_oam[(@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt)] = 2;
        oi += step;
        c -%= 1;
        if (sign8_p2(c)) break;
    }

    var oj: usize = 8;
    c = n;
    while (true) {
        const j: usize = @as(usize, r5) + i * 64;
        r5 = (r5 -% 8) & 63;
        const p = &base[oj];
        p.x = v.moldorm_x_lo[j] -% @as(u8, @truncate(v.BG2HOFS_copy2.*));
        if (!sign8_p2(v.beamos_x_hi[j]))
            p.y = v.moldorm_y_lo[j] +% 10 -% @as(u8, @truncate(v.BG2VOFS_copy2.*));
        p.charnum = 0x6c;
        p.flags = 0x34;
        v.bytewise_extended_oam[(@intFromPtr(p) - @intFromPtr(v.oam_buf)) / @sizeOf(OamEnt)] = 2;
        oj += 1;
        c -%= 1;
        if (sign8_p2(c)) break;
    }

    if (v.sprite_ai_state[i] == 1) {
        _ = a.Oam_AllocateFromRegionB(4);
        const oam = oamPtr_p2();
        const j: usize = t.kLanmola_Draw_Idx2[v.sprite_delay_main[i] >> 3];
        setOamPlain_p2(
            oam,
            v.sprite_x_lo[i] -% @as(u8, @truncate(v.BG2HOFS_copy2.*)),
            v.sprite_y_lo[i] -% @as(u8, @truncate(v.BG2VOFS_copy2.*)),
            t.kLanmola_Draw_Char2[j],
            t.kLanmola_Draw_Flags2[j] | 0x31,
            2,
        );
    } else if (v.sprite_ai_state[i] != 5 and v.sprite_delay_aux1[i] != 0) {
        if (((v.sprite_y_vel[i] >> 6) ^ v.sprite_ai_state[i]) & 2 != 0) {
            _ = a.Oam_AllocateFromRegionB(8);
        } else {
            _ = a.Oam_AllocateFromRegionC(8);
        }
        var oam = oamPtr_p2();
        const r6: usize = @as(usize, ((v.sprite_delay_aux1[i] >> 2) & 3) ^ 3) * 2;
        const x: u8 = v.sprite_D[i] -% @as(u8, @truncate(v.BG2HOFS_copy2.*));
        const y: u8 = v.sprite_wallcoll[i] -% @as(u8, @truncate(v.BG2VOFS_copy2.*));
        var q: isize = 1;
        while (q >= 0) : ({
            q -= 1;
            oam += 1;
        }) {
            const j: usize = @as(usize, @intCast(q)) + r6;
            setOamPlain_p2(
                oam,
                x +% @as(u8, @bitCast(t.kLanmola_Draw_X4[j])),
                y +% @as(u8, @bitCast(t.kLanmola_Draw_Y4[j])),
                t.kLanmola_Draw_Char4[j],
                t.kLanmola_Draw_Flags4[j] | 0x31,
                t.kLanmola_Draw_Big4[j],
            );
        }
    }
}

pub export fn Sprite_50_Cannonball(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    if (v.sprite_ai_state[i] == 0) {
        a.SpriteDraw_SingleLarge(k);
    } else {
        SpriteDraw_BigCannonball(k);
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = v.sprite_subtype2[i] >> 2 & 1;
    a.Sprite_MoveXY(k);
    if (v.sprite_delay_main[i] != 0) {
        if (v.sprite_delay_main[i] == 1)
            v.sprite_state[i] = 0;
        return;
    }
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.sprite_delay_aux2[i] == 0 and a.Sprite_CheckTileCollision(k) != 0)
        v.sprite_delay_main[i] = 16;
}

pub export fn SpriteDraw_BigCannonball(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p2();
    const g: usize = v.sprite_graphics[i];
    var n: isize = 3;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const q: usize = @intCast(n);
        setOam_p2(
            oam,
            info.x +% @as(u16, @bitCast(@as(i16, t.kMetalBallLarge_X[q]))),
            info.y +% @as(u16, @bitCast(@as(i16, t.kMetalBallLarge_Y[q]))),
            t.kMetalBallLarge_Char[g * 4 + q],
            t.kMetalBallLarge_Flags[q] | info.flags,
            2,
        );
    }
}

pub export fn Sprite_51_ArmosStatue(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    Armos_Draw(k);
    if (v.sprite_F[i] != 0)
        a.Sprite_ZeroVelocity_XY(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_MoveZ(k);
    v.sprite_z_vel[i] -%= 2;
    if (sign8_p2(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = 0;
        a.Sprite_ZeroVelocity_XY(k);
    }
    if (v.sprite_ai_state[i] == 0) {
        v.sprite_flags3[i] |= 0x40;
        if (v.sprite_delay_main[i] == 1) {
            v.sprite_flags3[i] &= ~@as(u8, 0x40);
            v.sprite_ai_state[i] +%= 1;
            v.sprite_flags2[i] &= ~@as(u8, 0x80);
            v.sprite_flags3[i] &= ~@as(u8, 0x40);
            v.sprite_oam_flags[i] = 0xb;
        } else {
            if (((@as(u8, @truncate(@as(u32, @bitCast(k)))) ^ v.frame_counter.*) & 3) == 0 and
                v.link_x_coord.* -% v.cur_sprite_x.* +% 31 < 62 and
                v.link_y_coord.* +% 8 -% v.cur_sprite_y.* +% 48 < 88 and
                v.sprite_delay_main[i] == 0)
            {
                v.sprite_delay_main[i] = 48;
                a.SpriteSfx_QueueSfx2WithPan(k, 0x22);
            }
            if (a.Sprite_CheckDamageToLink_same_layer(k)) {
                a.Sprite_NullifyHookshotDrag();
                a.Sprite_RepelDash();
            }
            if (v.sprite_delay_main[i] != 0)
                v.sprite_oam_flags[i] ^= (v.sprite_delay_main[i] >> 1) & 0xe;
        }
    } else {
        _ = a.Sprite_CheckDamageToAndFromLink(k);
        if (a.Sprite_ReturnIfRecoiling(k))
            return;
        a.Sprite_MoveXY(k);
        _ = a.Sprite_CheckTileCollision(k);
        if ((v.sprite_delay_main[i] | v.sprite_z[i]) == 0) {
            v.sprite_delay_main[i] = 8;
            v.sprite_z_vel[i] = 16;
            a.Sprite_ApplySpeedTowardsLink(k, 12);
        }
    }
}

pub export fn Armos_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (v.sprite_ai_state[i] == 0) {
        if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
            return;
    }
    a.Sprite_DrawMultiple(k, &t.kArmos_Dmd, 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_4E_Popo(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    Bot_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    v.sprite_subtype2[i] +%= 1;
    v.sprite_A[i] = v.sprite_subtype2[i] >> 4 & 3;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 105;
            }
        },
        1 => {
            v.sprite_subtype2[i] +%= 1;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 128;
                v.sprite_ai_state[i] +%= 1;
                const j: usize = a.GetRandomNumber() & 15;
                v.sprite_x_vel[i] = byte(@as(i32, t.kSpriteKeese_Tab2[j]) << 2);
                v.sprite_y_vel[i] = byte(@as(i32, t.kSpriteKeese_Tab3[j]) << 2);
            }
        },
        2 => {
            v.sprite_subtype2[i] +%= 1;
            if (v.sprite_delay_main[i] != 0) {
                if (((@as(u8, @truncate(@as(u32, @bitCast(k)))) ^ v.frame_counter.*) &
                    v.sprite_B[i]) != 0)
                {
                    _ = a.Sprite_CheckTileCollision(k);
                    return;
                }
                a.Sprite_MoveXY(k);
                if (v.sprite_wallcoll[i] == 0) {
                    _ = a.Sprite_CheckTileCollision(k);
                    return;
                }
            }
            v.sprite_ai_state[i] = 0;
            v.sprite_delay_main[i] = 80;
        },
        else => {},
    }
}

pub export fn Sprite_4D_Toppo(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    if (v.sprite_ai_state[i] != 0) {
        v.sprite_obj_prio[i] |= 0x30;
        Toppo_Draw(k);
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // Toppo_Hiding
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 8;
                const j: usize = a.GetRandomNumber() & 3;
                const x = @as(u16, v.sprite_A[i]) | (@as(u16, v.sprite_B[i]) << 8);
                const y = @as(u16, v.sprite_C[i]) | (@as(u16, v.sprite_head_dir[i]) << 8);
                a.Sprite_SetX(k, x +% @as(u16, @bitCast(@as(i16, t.kToppo_XOffs[j]))));
                a.Sprite_SetY(k, y +% @as(u16, @bitCast(@as(i16, t.kToppo_YOffs[j]))));
            }
        },
        1 => { // Toppo_RustleGrass
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 16;
            } else {
                v.sprite_graphics[i] = v.sprite_delay_main[i] >> 2 & 1;
                Toppo_VerifyTile(k);
            }
        },
        2 => { // Toppo_PokingOut
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 3;
                v.sprite_z_vel[i] = 64;
            }
            v.sprite_graphics[i] = 2;
            Toppo_VerifyTile(k);
        },
        3 => { // Toppo_Leaping
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            a.Sprite_MoveZ(k);
            v.sprite_z_vel[i] -%= 2;
            if (sign8_p2(v.sprite_z[i])) {
                v.sprite_z[i] = 0;
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 16;
                Toppo_VerifyTile(k);
            }
        },
        4 => { // Toppo_Retreat
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 32;
            } else {
                v.sprite_graphics[i] = v.sprite_delay_main[i] >> 2 & 1;
            }
            Toppo_VerifyTile(k);
        },
        5 => a.Toppo_Flustered(k), // Toppo_Flustered
        else => {},
    }
}

pub export fn Toppo_VerifyTile(k: c_int) callconv(.c) void {
    var x = a.Sprite_GetX(k);
    if (a.GetTileAttribute(0, &x, a.Sprite_GetY(k)) != 0x40)
        v.sprite_ai_state[ix_p2(k)] = 5;
}

pub export fn Toppo_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p2();
    const g: usize = v.sprite_graphics[i];
    const ybase = a.Sprite_GetY(k) -% v.BG2VOFS_copy2.*;
    var n: isize = 2;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = @as(usize, @intCast(n)) + g * 3;
        const big = t.kToppo_Draw_Big[j];
        var flags = t.kToppo_Draw_Flags[j] | info.flags;
        if (big == 0)
            flags = (flags & ~@as(u8, 0xf)) | 2;
        setOam_p2(
            oam,
            info.x +% @as(u16, @bitCast(@as(i16, t.kToppo_Draw_X[j]))),
            (if (big != 0) info.y else ybase) +% @as(u16, @bitCast(@as(i16, t.kToppo_Draw_Y[j]))),
            t.kToppo_Draw_Char[j],
            flags,
            big,
        );
    }
}

pub export fn Sprite_4B_GreenKnifeGuard(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    v.sprite_graphics[i] = @bitCast(t.kSprite_Recruit_Gfx[
        @as(usize, v.sprite_D[i]) + (v.sprite_subtype2[i] >> 1 & 4)
    ]);
    Recruit_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckTileCollision(k);
    if (v.sprite_ai_state[i] != 0) {
        GreenKnifeGuard_Moving(k);
        return;
    }
    if (v.sprite_delay_main[i] != 0)
        return;

    v.sprite_delay_main[i] = (a.GetRandomNumber() & 0x3f) +% 0x30;
    v.sprite_ai_state[i] +%= 1;
    v.sprite_D[i] = v.sprite_head_dir[i];
    var out: PointU8 = undefined;
    var j: usize = v.sprite_D[i];
    if (j == a.Sprite_DirectionToFaceLink(k, &out) and
        (out.x +% 0x10 < 0x20 or out.y +% 0x10 < 0x20))
    {
        j += 4;
        v.sprite_delay_main[i] = 128;
    }
    v.sprite_x_vel[i] = @bitCast(t.kSprite_Recruit_Xvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kSprite_Recruit_Yvel[j]);
}

pub export fn GreenKnifeGuard_Moving(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var tt: u8 = 0x10;

    // `goto out` skips the reset block.
    var skip = false;
    if (v.sprite_wallcoll[i] == 0) {
        if (v.sprite_delay_main[i] != 0) {
            skip = true;
        } else {
            tt = 0x30;
        }
    }
    if (!skip) {
        v.sprite_delay_main[i] = tt;
        a.Sprite_ZeroVelocity_XY(k);
        v.sprite_head_dir[i] = t.kRecruit_Moving_HeadDir[
            (@as(usize, v.sprite_D[i]) * 2) | (a.GetRandomNumber() & 1)
        ];
        v.sprite_ai_state[i] = 0;
    }
    // out:
    v.sprite_subtype2[i] +%= if (v.sprite_delay_aux1[i] != 0) @as(u8, 2) else 1;
}

pub export fn Recruit_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    const oam = oamPtr_p2();
    const hd: usize = v.sprite_head_dir[i];
    setOam_p2(oam + 0, info.x, info.y -% 11, t.kSoldier_Draw1_Char[hd], t.kSoldier_Draw1_Flags[hd] | info.flags, 2);
    const r6: usize = v.sprite_graphics[i];
    setOam_p2(
        oam + 1,
        info.x +% @as(u16, @bitCast(t.kRecruit_Draw_X[r6])),
        info.y,
        t.kRecruit_Draw_Char[r6],
        t.kRecruit_Draw_Flags[r6] | info.flags,
        2,
    );
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_4A_BombGuard(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    if (v.sprite_C[i] == 0) {
        BombGuard(k);
        return;
    }
    if (v.sprite_C[i] < 2) {
        SpriteBomb_ExplosionIncoming(k);
        return;
    }

    if (v.sprite_C[i] == 2) {
        var j: isize = 15;
        while (j >= 0) : (j -= 1) {
            const u: usize = @intCast(j);
            if (u != v.cur_object_index.* and v.sprite_state[u] >= 9 and
                (((v.frame_counter.* ^ @as(u8, @truncate(@as(u32, @bitCast(@as(c_int, @intCast(j))))))) & 7) |
                    v.sprite_hit_timer[u]) == 0)
                SpriteBomb_CheckDamageToSprite(k, @intCast(j));
        }
        _ = a.Sprite_CheckDamageToLink(k);
    }
    SpriteDraw_SpriteBombExplosion(k);
    if (v.sprite_delay_aux1[i] == 0)
        v.sprite_state[i] = 0;
}

pub export fn SpriteBomb_CheckDamageToSprite(k: c_int, j: c_int) callconv(.c) void {
    const ju = ix_p2(j);
    var x: i32 = @as(i32, a.Sprite_GetX(k)) - 16;
    var y: i32 = @as(i32, a.Sprite_GetY(k)) - 16;
    var hb: SpriteHitBox = undefined;
    hb.r0_xlo = @truncate(@as(u32, @bitCast(x)));
    hb.r8_xhi = @truncate(@as(u32, @bitCast(x)) >> 8);
    hb.r2 = 48;
    hb.r3 = 48;
    hb.r1_ylo = @truncate(@as(u32, @bitCast(y)));
    hb.r9_yhi = @truncate(@as(u32, @bitCast(y)) >> 8);
    a.Sprite_SetupHitBox(j, &hb);
    if (!a.CheckIfHitBoxesOverlap(&hb) or v.sprite_type[ju] == 0x11)
        return;
    a.Ancilla_CheckDamageToSprite_preset(j, 8);
    x = @as(i32, a.Sprite_GetX(j));
    y = @as(i32, a.Sprite_GetY(j)) - @as(i32, v.sprite_z[ju]);
    const pt = a.Sprite_ProjectSpeedTowardsLocation(
        k,
        @truncate(@as(u32, @bitCast(x))),
        @truncate(@as(u32, @bitCast(y))),
        32,
    );
    v.sprite_y_recoil[ju] = pt.y;
    v.sprite_x_recoil[ju] = pt.x;
}

pub export fn SpriteBomb_ExplosionIncoming(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    if (v.sprite_E[i] != 0)
        v.sprite_obj_prio[i] |= 48;
    a.SpriteDraw_SingleLarge(k);
    if (v.sprite_hit_timer[i] != 0 or v.sprite_delay_aux1[i] == 1) {
        v.sprite_hit_timer[i] = 0;
        if (v.sprite_state[i] == 10) {
            v.link_state_bits.* = 0;
            v.link_picking_throw_state.* = 0;
        }
        a.SpriteSfx_QueueSfx2WithPan(k, 0xc);
        v.sprite_C[i] +%= 1;
        v.sprite_flags4[i] = 9;
        v.sprite_oam_flags[i] = 2;
        v.sprite_delay_aux1[i] = 31;
        v.sprite_state[i] = 6;
        v.sprite_flags2[i] = 3;
        return;
    }
    if (v.sprite_delay_aux1[i] < 64)
        v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0xe)) |
            ((v.sprite_delay_aux1[i] >> 1) & 0xe);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_delay_aux3[i] == 0)
        _ = a.Sprite_CheckDamageFromLink(k);
    a.Sprite_MoveXY(k);
    if (v.player_is_indoors.* != 0)
        _ = a.Sprite_CheckTileCollision(k);
    a.ThrownSprite_TileAndSpriteInteraction(k);
}

pub export fn BombGuard(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    BombTrooper_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
    v.sprite_head_dir[i] = v.sprite_D[i];
    if (v.sprite_ai_state[i] == 0) {
        if (v.sprite_delay_main[i] == 0) {
            v.sprite_ai_state[i] = 1;
            v.sprite_delay_main[i] = 112;
        }
    } else {
        const j: u8 = v.sprite_delay_main[i];
        if (j == 0) {
            v.sprite_ai_state[i] = 0;
            v.sprite_delay_main[i] = 32;
            return;
        }
        v.sprite_subtype2[i] = @intFromBool(j >= 80);
        if (j == 32)
            BombGuard_CreateBomb(k);
        v.sprite_graphics[i] = t.kJavelinTrooper_Tab2[
            (@as(usize, v.sprite_D[i]) << 3 | (j >> 4)) + 32
        ];
    }
}

pub export fn BombGuard_CreateBomb(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x4a, &info);
    if (j >= 0) {
        const ju = ix_p2(j);
        const d: usize = v.sprite_D[i];
        a.Sprite_SetX(j, info.r0_x +% @as(u16, @bitCast(@as(i16, t.kBombTrooperBomb_X[d]))));
        a.Sprite_SetY(j, info.r2_y +% @as(u16, @bitCast(@as(i16, t.kBombTrooperBomb_Y[d]))));
        a.Sprite_ApplySpeedTowardsLink(j, 16);
        var pt: PointU8 = undefined;
        v.sprite_C[ju] = 1;
        _ = a.Sprite_DirectionToFaceLink(j, &pt);
        if (sign8_p2(pt.x))
            pt.x = 0 -% pt.x;
        if (sign8_p2(pt.y))
            pt.y = 0 -% pt.y;
        v.sprite_z_vel[ju] = @bitCast(t.kBombTrooperBomb_Zvel[(pt.y | pt.x) >> 4]);
        v.sprite_flags3[ju] = (v.sprite_flags3[i] & 0xee) | 0x18;
        v.sprite_oam_flags[ju] = 8;
        v.sprite_delay_aux1[ju] = 255;
        v.sprite_health[ju] = 0;
        a.SpriteSfx_QueueSfx3WithPan(j, 0x13);
    }
}

pub export fn BombTrooper_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    a.SpriteDraw_GuardHead(k, &info, 2);
    a.SpriteDraw_BNCBody(k, &info, 1);
    if (v.sprite_graphics[i] < 20)
        SpriteDraw_BombGuard_Arm(k, &info);
    a.SpriteDraw_Shadow_custom(k, &info, 10);
}

pub export fn SpriteDraw_BombGuard_Arm(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix_p2(k);
    const oam = oamPtr_p2();
    const j: usize = (@as(usize, v.sprite_D[i]) * 2) | v.sprite_subtype2[i];
    setOam_p2(
        oam,
        info.x +% @as(u16, @bitCast(@as(i16, t.kBombTrooper_DrawArm_X[j]))),
        info.y +% @as(u16, @bitCast(@as(i16, t.kBombTrooper_DrawArm_Y[j]))),
        0x6e,
        (info.flags & 0x30) | 0x8,
        2,
    );
}

pub export fn SpriteDraw_SpriteBombExplosion(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p2();
    const base: usize = v.sprite_delay_aux1[i] >> 1 & 0xc;
    var n: isize = 3;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = base + @as(usize, @intCast(n));
        oam[0].x = byte(@as(i32, t.kEnemyBombExplosion_X[j]) + @as(i32, info.x));
        oam[0].y = byte(@as(i32, t.kEnemyBombExplosion_Y[j]) + @as(i32, info.y));
        oam[0].charnum = t.kEnemyBombExplosion_Char[j];
        oam[0].flags = t.kEnemyBombExplosion_Flags[j] | info.flags;
    }
    a.Sprite_CorrectOamEntries(k, 3, 2);
}

pub export fn Bot_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    const j: usize = v.sprite_A[i];
    v.sprite_graphics[i] = t.kBot_Gfx[j];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) | t.kBot_OamFlags[j];
    a.SpriteDraw_SingleLarge(k);
}

pub export fn Sprite_4C_Geldman(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (v.sprite_ai_state[i] < 2) {
        a.Sprite_PrepOamCoord(k, &info);
    } else {
        a.GerudoMan_Draw(k);
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    v.sprite_ignore_projectile[i] = 1;
    switch (v.sprite_ai_state[i]) {
        0 => { // return
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_x_lo[i] = v.sprite_A[i];
                v.sprite_x_hi[i] = v.sprite_B[i];
                v.sprite_y_lo[i] = v.sprite_C[i];
                v.sprite_y_hi[i] = v.sprite_head_dir[i];
                v.sprite_ai_state[i] = 1;
            }
        },
        1 => { // wait
            if (((@as(u8, @truncate(@as(u32, @bitCast(k)))) ^ v.frame_counter.*) & 7) == 0 and
                v.link_x_coord.* -% v.cur_sprite_x.* +% 0x30 < 0x60 and
                v.link_y_coord.* -% v.cur_sprite_y.* +% 0x30 < 0x60)
            {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 31;
            }
        },
        2 => { // emerge
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 3;
                v.sprite_delay_main[i] = 96;
                a.Sprite_ApplySpeedTowardsLink(k, 16);
            } else {
                v.sprite_graphics[i] = t.kGerudoMan_EmergeGfx[v.sprite_delay_main[i] >> 2];
            }
        },
        3 => { // pursue
            v.sprite_ignore_projectile[i] = 0;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 8;
            } else {
                v.sprite_graphics[i] = t.kGerudoMan_PursueGfx[v.sprite_delay_main[i] >> 2 & 1];
                _ = a.Sprite_CheckDamageToAndFromLink(k);
                a.Sprite_MoveXY(k);
            }
        },
        4 => { // submerge
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 16;
            } else {
                v.sprite_graphics[i] = t.kGerudoMan_SubmergeGfx[v.sprite_delay_main[i] >> 1];
            }
        },
        else => {},
    }
}

pub export fn Sprite_53_ArmosKnight(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    v.sprite_obj_prio[i] |= 0x30;
    ArmosKnight_Draw(k);
    if (a.Sprite_ReturnIfPaused(k))
        return;
    if (v.sprite_state[i] != 9) {
        if (v.sprite_delay_main[i] != 0) {
            v.sprite_graphics[i] = t.kArmosKnight_Gfx1[v.sprite_delay_main[i] >> 3];
            return;
        }
        v.byte_7E0FF8.* -%= 1;
        if (v.byte_7E0FF8.* == 1) {
            var j: isize = 5;
            while (j >= 0) : (j -= 1) {
                const u: usize = @intCast(j);
                v.sprite_health[u] = 48;
                v.sprite_x_vel[u] = 0;
                v.sprite_y_vel[u] = 0;
                v.sprite_z_vel[u] = 0;
            }
        }
        v.sprite_state[i] = 0;
        if (a.Sprite_CheckIfScreenIsClear()) {
            var info: SpriteSpawnInfo = undefined;
            const j = a.Sprite_SpawnDynamically(k, 0xea, &info);
            std.debug.assert(j >= 0);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_z_vel[ix_p2(j)] = 32;
            v.sprite_A[ix_p2(j)] = 1;
        }
        return;
    }
    a.Sprite_MoveXY(k);
    a.Sprite_MoveZ(k);
    v.sprite_z_vel[i] -%= 4;
    if (sign8_p2(v.sprite_z[i])) {
        v.sprite_z_vel[i] = 0;
        v.sprite_z[i] = 0;
        if (v.byte_7E0FF8.* != 1 and v.sprite_A[i] != 0) {
            v.sprite_z_vel[i] = 48;
            a.SpriteSfx_QueueSfx3WithPan(k, 0x16);
        }
    }
    if (v.sprite_F[i] != 0) {
        a.Sprite_ZeroVelocity_XY(k);
        v.sprite_ai_state[i] = 0;
        v.sprite_G[i] = 0;
    }
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    if (v.sprite_A[i] == 0) {
        if (v.sprite_delay_main[i] == 0) {
            v.sprite_A[i] +%= 1;
            v.sprite_flags2[i] = (v.sprite_flags2[i] & 0x7f) -% 2;
            v.sprite_defl_bits[i] &= ~@as(u8, 4);
            v.sprite_flags3[i] &= ~@as(u8, 0x40);
        } else {
            if (v.sprite_delay_main[i] == 64) {
                v.sound_effect_1.* = 0x35;
            } else if (v.sprite_delay_main[i] < 64) {
                const j: usize = @intCast(((v.sprite_delay_main[i] >> 1) ^ @as(u8, @truncate(@as(u32, @bitCast(k))))) & 1);
                v.sprite_x_vel[i] = @bitCast(t.kArmosKnight_Xv[j]);
                a.Sprite_MoveX(k);
                v.sprite_x_vel[i] = 0;
            }
            _ = a.Sprite_CheckDamageFromLink(k);
            if (a.Sprite_CheckDamageToLink_same_layer(k)) {
                a.Sprite_NullifyHookshotDrag();
                a.Sprite_RepelDash();
            }
        }
    } else if (v.byte_7E0FF8.* == 1) {
        a.Sprite_ArmosCrusher(k);
    } else {
        _ = a.Sprite_CheckDamageToAndFromLink(k);
        if (v.sprite_ai_state[i] == 0) {
            const x = (@as(u16, v.overlord_y_hi[i]) << 8) | v.overlord_x_hi[i];
            const y = (@as(u16, v.overlord_floor[i]) << 8) | v.overlord_gen2[i];
            const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 16);
            v.sprite_x_vel[i] = pt.x;
            v.sprite_y_vel[i] = pt.y;
            a.Sprite_Get16BitCoords(k);
            if (x -% v.cur_sprite_x.* +% 2 < 4 and y -% v.cur_sprite_y.* +% 2 < 4)
                v.sprite_ai_state[i] = 1;
        } else {
            v.sprite_x_lo[i] = v.overlord_x_hi[i];
            v.sprite_x_hi[i] = v.overlord_y_hi[i];
            v.sprite_y_lo[i] = v.overlord_gen2[i];
            v.sprite_y_hi[i] = v.overlord_floor[i];
        }
    }
}

pub export fn ArmosKnight_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    if (v.sprite_A[i] == 0 and v.submodule_index.* != 7)
        a.Oam_AllocateDeferToPlayer(k);
    var oam = oamPtr_p2();
    const g: usize = v.sprite_graphics[i];
    var n: isize = 3;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = g * 4 + @as(usize, @intCast(n));
        setOam_p2(
            oam,
            info.x +% @as(u16, @bitCast(@as(i16, t.kArmosKnight_Draw_X[j]))),
            info.y +% @as(u16, @bitCast(@as(i16, t.kArmosKnight_Draw_Y[j]))),
            t.kArmosKnight_Draw_Char[j],
            t.kArmosKnight_Draw_Flags[j] | info.flags,
            t.kArmosKnight_Draw_Big[j],
        );
    }
    if (g != 0)
        return;
    if (v.sprite_A[i] != 0) {
        const spr_idx: u16 = 76 +% @as(u16, @truncate(@as(u32, @bitCast(k)))) *% 2;
        v.oam_cur_ptr.* = 0x800 +% spr_idx *% 4;
        v.oam_ext_cur_ptr.* = 0xA20 +% spr_idx;
    }
    oam = oamPtr_p2();
    var z: u16 = v.sprite_z[i];
    z = (if (z >= 32) @as(u16, 32) else z) >> 3;
    const y = a.Sprite_GetY(k) -% v.BG2VOFS_copy2.*;
    setOam_p2(oam + 4, info.x -% 8 +% z, y +% 12, 0xe4, 0x25, 2);
    setOam_p2(oam + 5, info.x +% 8 -% z, y +% 12, 0xe4, 0x25 | 0x40, 2);
}

pub export fn Sprite_6D_Rat(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var j: usize = v.sprite_A[i];
    v.sprite_graphics[i] = t.kSpriteRat_Tab0[j];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) | t.kSpriteRat_Tab1[j];
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckTileCollision(k);
    if (v.sprite_ai_state[i] != 0) {
        if (v.sprite_delay_main[i] == 0) {
            if (v.is_in_dark_world.* == 0)
                a.SpriteSfx_QueueSfx3WithPan(k, 0x17);
            v.sprite_ai_state[i] = 0;
            v.sprite_delay_main[i] = 80;
        }
        j = v.sprite_D[i];
        if (v.sprite_wallcoll[i] != 0) {
            j = t.kSpriteRat_Tab3[j];
            v.sprite_D[i] = @truncate(j);
        }
        v.sprite_x_vel[i] = @bitCast(t.kSpriteRat_Xvel[j]);
        v.sprite_y_vel[i] = @bitCast(t.kSpriteRat_Yvel[j]);
        v.sprite_A[i] = t.kSpriteRat_Tab4[@as(usize, v.sprite_D[i]) * 2 + (v.frame_counter.* >> 2 & 1)];
    } else {
        a.Sprite_ZeroVelocity_XY(k);
        if (v.sprite_delay_main[i] == 0) {
            const r = a.GetRandomNumber();
            v.sprite_D[i] = r & 3;
            v.sprite_ai_state[i] +%= 1;
            v.sprite_delay_main[i] = (r & 0x7f) +% 0x40;
        }
        v.sprite_A[i] = t.kSpriteRat_Tab2[@as(usize, v.sprite_D[i]) * 2 + (v.frame_counter.* >> 3 & 1)];
    }
}

pub export fn Sprite_6E_Rope(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var j: usize = v.sprite_A[i];
    v.sprite_graphics[i] = @bitCast(t.kSpriteRope_Gfx[j]);
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) | @as(u8, @bitCast(t.kSpriteRope_Flags[j]));
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_E[i] != 0) {
        const oam = oamPtr_p2();
        oam[0].flags |= 0x30;

        const old_z = v.sprite_z[i];
        a.Sprite_MoveZ(k);
        if (!sign8_p2(@as(i32, v.sprite_z_vel[i]) - 0xc0))
            v.sprite_z_vel[i] -%= 2;
        if (!sign8_p2(old_z ^ v.sprite_z[i]) or !sign8_p2(v.sprite_z[i]))
            return;
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = 0;
        v.sprite_E[i] = 0;
        v.sprite_flags3[i] &= ~@as(u8, 0x10);
    } else {
        v.sprite_flags2[i] = 0;
        if (a.Sprite_ReturnIfRecoiling(k))
            return;
        _ = a.Sprite_CheckDamageToAndFromLink(k);
        a.Sprite_MoveXY(k);
        _ = a.Sprite_CheckTileCollision(k);
        if (v.sprite_ai_state[i] != 0) {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 32;
            }
            j = v.sprite_D[i];
            if (v.sprite_wallcoll[i] != 0) {
                j = @intCast(@as(u8, @bitCast(t.kSpriteRope_Tab0[j])));
                v.sprite_D[i] = @truncate(j);
            }

            j +%= v.sprite_G[i];
            v.sprite_x_vel[i] = @bitCast(t.kSpriteRope_Xvel[j]);
            v.sprite_y_vel[i] = @bitCast(t.kSpriteRope_Yvel[j]);

            var n: u32 = v.frame_counter.*;
            if (j < 4)
                n >>= 1;

            v.sprite_A[i] = @bitCast(t.kSpriteRope_Tab1[@as(usize, v.sprite_D[i]) * 2 + (n >> 1 & 1)]);
        } else {
            a.Sprite_ZeroVelocity_XY(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_G[i] = 0;
                const r = a.GetRandomNumber();
                v.sprite_D[i] = r & 3;
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = (r & 0x7f) +% 0x40;

                var pt: PointU8 = undefined;
                const dir = a.Sprite_DirectionToFaceLink(k, &pt);
                if (pt.y +% 0x10 < 0x20 or pt.x +% 0x18 < 0x20) {
                    v.sprite_G[i] = 4;
                    v.sprite_D[i] = dir;
                }
            }
            v.sprite_A[i] = @bitCast(t.kSpriteRope_Tab1[@as(usize, v.sprite_D[i]) * 2 + (v.frame_counter.* >> 3 & 1)]);
        }
    }
}

pub export fn Sprite_6F_Keese(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    v.sprite_obj_prio[i] |= 0x30;
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXY(k);
    if (v.sprite_ai_state[i] != 0) {
        if (v.sprite_delay_main[i] == 0) {
            v.sprite_ai_state[i] = 0;
            v.sprite_delay_main[i] = 64;
            v.sprite_graphics[i] = 0;
            a.Sprite_ZeroVelocity_XY(k);
        } else {
            if (v.sprite_delay_main[i] & 7 == 0) {
                v.sprite_A[i] +%= @bitCast(t.kSpriteKeese_Tab1[v.sprite_B[i] & 1]);
                if (a.GetRandomNumber() & 3 == 0)
                    v.sprite_B[i] +%= 1;
            }
            const j: usize = v.sprite_A[i] & 0xf;
            v.sprite_x_vel[i] = @bitCast(t.kSpriteKeese_Tab2[j]);
            v.sprite_y_vel[i] = @bitCast(t.kSpriteKeese_Tab3[j]);
            v.sprite_graphics[i] = ((v.frame_counter.* >> 2) & 1) +% 1;
        }
    } else {
        if ((((@as(u8, @truncate(@as(u32, @bitCast(k)))) ^ v.frame_counter.*) & 3) |
            v.sprite_delay_main[i]) != 0)
            return;

        var pt: PointU8 = undefined;
        const dir = a.Sprite_DirectionToFaceLink(k, &pt);
        if (pt.y +% 0x28 >= 0x50 or pt.x +% 0x28 >= 0x50)
            return;
        a.SpriteSfx_QueueSfx3WithPan(k, 0x1e);
        v.sprite_ai_state[i] +%= 1;
        v.sprite_delay_main[i] = 64;
        v.sprite_B[i] = 64;
        v.sprite_A[i] = @bitCast(t.kSpriteKeese_Tab0[dir]);
    }
}

pub export fn Sprite_Cannonball(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_MoveXY(k);
    if (v.sprite_delay_main[i] == 30) {
        Sprite_SpawnPoofGarnish(k);
    } else if (v.sprite_delay_main[i] == 0 and a.Sprite_CheckTileCollision(k) != 0) {
        v.sprite_state[i] = 0;
        v.sprite_x_lo[i] +%= 4;
        v.sprite_y_lo[i] +%= 4;
        a.Sprite_PlaceRupulseSpark_2(k);
        a.SpriteSfx_QueueSfx2WithPan(k, 0x5);
    }
    _ = a.Sprite_CheckDamageToAndFromLink(k);
}

pub export fn Sprite_SpawnPoofGarnish(j: c_int) callconv(.c) void {
    const ji = ix_p2(j);
    const k = ix_p2(a.GarnishAllocForce());
    v.garnish_type[k] = 10;
    v.garnish_active.* = 10;
    v.garnish_x_lo[k] = v.sprite_x_lo[ji];
    v.garnish_x_hi[k] = v.sprite_x_hi[ji];
    const y = a.Sprite_GetY(j) +% 16;
    v.garnish_y_lo[k] = @truncate(y);
    v.garnish_y_hi[k] = @truncate(y >> 8);
    v.garnish_sprite[k] = v.sprite_floor[ji];
    v.garnish_countdown[k] = 15;
}

pub export fn Sprite_6C_MirrorPortal(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    if (v.savegame_is_darkworld.* != 0) {
        v.sprite_state[i] = 0;
    } else {
        if (@as(u8, @truncate(v.overworld_screen_index.*)) >= 0x80)
            return;

        if (v.submodule_index.* != 0x23 and v.byte_7E0FC6.* < 3)
            a.SpriteDraw_SingleLarge(k);
        if (a.Sprite_ReturnIfInactive(k))
            return;
        const j: usize = v.frame_counter.* >> 2 & 3;
        v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) | t.kSprite_WarpVortex_Flags[j];
        if (a.Sprite_CheckIfLinkIsBusy())
            return;
        if (a.Sprite_CheckDamageToLink_same_layer(k)) {
            if (v.sprite_A[i] != 0 and
                (v.link_disable_sprite_damage.* | v.countdown_for_blink.*) == 0 and
                v.flag_is_link_immobilized.* == 0)
            {
                v.submodule_index.* = 0x23;
                v.link_triggered_by_whirlpool_sprite.* = 1;
                v.subsubmodule_index.* = 0;
                v.link_actual_vel_y.* = 0;
                v.link_actual_vel_x.* = 0;
                v.link_player_handler_state.* = kPlayerState_Mirror;
                v.last_light_vs_dark_world.* = @truncate(v.overworld_screen_index.* & 0x40);
                v.sprite_state[i] = 0;
            }
        } else {
            v.sprite_A[i] = 1;
        }
    }
    v.sprite_B[i] +%= 1;
    if (v.sprite_B[i] == 0)
        v.sprite_A[i] = 1;
    v.sprite_x_lo[i] = v.bird_travel_x_lo[15];
    v.sprite_x_hi[i] = v.bird_travel_x_hi[15];
    const tt = (@as(u16, v.bird_travel_y_lo[15]) | (@as(u16, v.bird_travel_y_hi[15]) << 8)) +% 8;
    v.sprite_y_lo[i] = @truncate(tt);
    v.sprite_y_hi[i] = @truncate(tt >> 8);
}

pub export fn WalkingZora_Draw(k: c_int) callconv(.c) void {
    const i = ix_p2(k);
    var info: PrepOamCoordsRet = undefined;
    WalkingZora_DrawWaterRipples(k);
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    const oam = oamPtr_p2();
    const g: usize = v.sprite_graphics[i];
    if (g == 0 or g == 2)
        info.y -%= 1;

    const hd: usize = v.sprite_head_dir[i];
    setOam_p2(oam + 0, info.x, info.y -% 6, t.kWalkingZora_Draw_Char[hd], info.flags | t.kWalkingZora_Draw_Flags[hd], 2);
    setOam_p2(oam + 1, info.x, info.y +% 2, t.kWalkingZora_Draw_Char2[g], info.flags | t.kWalkingZora_Draw_Flags2[g], 2);

    if (v.sprite_anim_clock[i] == 0)
        a.SpriteDraw_Shadow(k, &info);
}

// ---------------------------------------------------------------------------
// from sprite_main_part4.zig
// ---------------------------------------------------------------------------
/// sprite.h keeps this file-local in sprite.zig, so it needs a local copy.


pub export fn WishPond2_Draw(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    if (@as(u8, @truncate(v.dungeon_room_index.*)) == 21)
        return;
    const st = v.sprite_ai_state[i];
    if (st != 5 and st != 6 and st != 11 and st != 12)
        return;
    const g: usize = v.sprite_graphics[i];
    var f = t.kWishPond2_OamFlags[g];
    if (f == 0xff)
        f = 5;
    v.sprite_oam_flags[i] = (f & 7) * 2;
    a.Sprite_DrawMultiple(k, &t.kWishPond2_Dmd[@as(usize, misc.kReceiveItem_Tab1[g] >> 1) * 4], 4, null);
}

pub export fn FaerieQueen_Draw(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    if (v.savegame_is_darkworld.* == 0) {
        var info: PrepOamCoordsRet = undefined;
        if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
            return;
        var oam = oamPtr_p4();
        const g: usize = v.sprite_graphics[i];
        var n: isize = 11;
        while (n >= 0) : ({
            n -= 1;
            oam += 1;
        }) {
            const j: usize = g * 12 + @as(usize, @intCast(n));
            setOamPlain_p4(
                oam,
                t.kFaerieQueen_Draw_X[j] +% @as(u8, @truncate(info.x)),
                t.kFaerieQueen_Draw_Y[j] +% @as(u8, @truncate(info.y)),
                t.kFaerieQueen_Draw_Char[j],
                info.flags | t.kFaerieQueen_Draw_Flags[j],
                t.kFaerieQueen_Draw_Big[j],
            );
        }
        a.Sprite_CorrectOamEntries(k, 11, 0xff);
    } else {
        a.Sprite_DrawMultiple(k, &t.kFaerieQueen_Dmd[@as(usize, v.sprite_graphics[i]) * 10], 10, null);
    }
}

pub export fn Sprite_71_Leever(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    if (v.sprite_ai_state[i] != 0) {
        Leever_Draw(k);
    } else {
        var info: PrepOamCoordsRet = undefined;
        a.Sprite_PrepOamCoord(k, &info);
    }
    if (v.sprite_pause[i] != 0)
        v.sprite_state[i] = 8;
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // under sand
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 127;
            } else {
                a.Sprite_ApplySpeedTowardsLink(k, 16);
                a.Sprite_MoveXY(k);
                a.Sprite_CheckTileCollision2(k);
            }
        },
        1 => { // emerge
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 160;
                a.Sprite_ZeroVelocity_XY(k);
            } else {
                v.sprite_graphics[i] = t.kLeever_EmergeGfx[v.sprite_delay_main[i] >> 3];
            }
        },
        2 => { // attack
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            // `goto stop_attack` from two places.
            var stop = v.sprite_delay_main[i] == 0;
            if (!stop) {
                if (v.sprite_subtype2[i] & 7 == 0)
                    a.Sprite_ApplySpeedTowardsLink(k, t.kLeever_AttackSpd[v.sprite_A[i]]);
                a.Sprite_MoveXY(k);
                if (a.Sprite_CheckTileCollision(k) != 0) {
                    stop = true;
                } else {
                    v.sprite_subtype2[i] +%= 1;
                    v.sprite_graphics[i] = t.kLeever_AttackGfx[v.sprite_subtype2[i] >> 2 & 3];
                }
            }
            if (stop) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 127;
            }
        },
        3 => { // submerge
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 64;
            } else {
                v.sprite_graphics[i] = t.kLeever_SubmergeGfx[(v.sprite_delay_main[i] >> 3) ^ 15];
            }
        },
        else => {},
    }
}

pub export fn Leever_Draw(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p4();
    const d: usize = v.sprite_graphics[i];
    var n: isize = t.kLeever_Draw_Num[d];
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = d * 4 + @as(usize, @intCast(n));
        const charnum = t.kLeever_Draw_Char[j];
        var f = info.flags;
        if (charnum >= 0x60 or charnum == 0x28 or charnum == 0x38)
            f &= 0xf0;
        setOam_p4(
            oam,
            info.x +% @as(u16, @bitCast(@as(i16, t.kLeever_Draw_X[j]))),
            info.y +% @as(u16, @bitCast(@as(i16, t.kLeever_Draw_Y[j]))),
            charnum,
            t.kLeever_Draw_Flags[j] | f,
            t.kLeever_Draw_Big[j],
        );
    }
}

pub export fn Sprite_D8_Heart(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    if (a.SpriteDraw_AbsorbableTransient(k, true))
        return;
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_CheckAbsorptionByPlayer(k);

    // Avoid calling Sprite_HandleAbsorptionByPlayer twice, it's called
    // also from within Sprite_HandleDraggingByAncilla.
    if (v.sprite_state[i] == 0 and (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0)
        return;

    if (a.Sprite_HandleDraggingByAncilla(k))
        return;
    a.Sprite_MoveXY(k);
    a.Sprite_MoveZ(k);
    if (sign8_p4(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_ai_state[i] +%= 1;
        v.sprite_graphics[i] = 0;
    }
    v.sprite_oam_flags[i] &= ~@as(u8, 0x40);
    if (!sign8_p4(v.sprite_x_vel[i]))
        v.sprite_oam_flags[i] |= 0x40;
    switch (if (v.sprite_ai_state[i] >= 3) @as(u8, 3) else v.sprite_ai_state[i]) {
        0 => { // InitializeAscent
            v.sprite_ai_state[i] +%= 1;
            v.sprite_delay_main[i] = 18;
            v.sprite_z_vel[i] = 20;
            v.sprite_graphics[i] = 1;
            v.sprite_D[i] = 0;
        },
        1 => { // BeginDescending
            if (v.sprite_delay_main[i] != 0) {
                v.sprite_z_vel[i] -%= 1;
            } else {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_z_vel[i] = 253;
                v.sprite_x_vel[i] = 0;
            }
        },
        2 => { // GlideGroundward
            if (v.sprite_delay_main[i] == 0) {
                const j: usize = v.sprite_D[i] & 1;
                v.sprite_x_vel[i] +%= @bitCast(t.kHeartRefill_AccelX[j]);
                if (v.sprite_x_vel[i] == @as(u8, @bitCast(t.kHeartRefill_VelTarget[j]))) {
                    v.sprite_D[i] +%= 1;
                    v.sprite_delay_main[i] = 8;
                }
            }
        },
        3 => { // Grounded
            v.sprite_y_vel[i] = 0;
            v.sprite_x_vel[i] = 0;
            v.sprite_z_vel[i] = 0;
        },
        else => {},
    }
}

pub export fn Sprite_E3_Fairy(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    v.sprite_ignore_projectile[i] = 1;
    if (v.sprite_ai_state[i] == 0) {
        if (v.player_is_indoors.* == 0)
            v.sprite_obj_prio[i] = 48;
        if (a.SpriteDraw_AbsorbableTransient(k, true))
            return;
    }
    Fairy_CheckIfTouchable(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // normal
            if (v.sprite_delay_aux4[i] == 0) {
                if (a.Sprite_CheckDamageToLink(k)) {
                    a.Sprite_HandleAbsorptionByPlayer(k);
                } else if (a.Sprite_CheckDamageFromLink(k) & kCheckDamageFromPlayer_Ne != 0) {
                    v.sprite_ai_state[i] +%= 1;
                    a.Sprite_ShowMessageUnconditional(0xc9);
                    return;
                }
            }
            // Same double-absorption guard as the heart above.
            if (v.sprite_state[i] == 0 and (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0)
                return;
            if (a.Sprite_HandleDraggingByAncilla(k))
                return;
            a.Faerie_HandleMovement(k);
        },
        1 => { // capture
            if (v.choice_in_multiselect_box.* == 0) {
                const j = a.Sprite_Find_EmptyBottle();
                if (j >= 0) {
                    v.link_bottle_info[ix_p4(j)] = 6;
                    a.Hud_RefreshIcon();
                    v.sprite_state[i] = 0;
                    return;
                }
                a.Sprite_ShowMessageUnconditional(0xca);
            }
            v.sprite_delay_aux4[i] = 48;
            v.sprite_ai_state[i] = 0;
        },
        else => {},
    }
}

pub export fn Fairy_CheckIfTouchable(k: c_int) callconv(.c) void {
    if (v.submodule_index.* == 2 and
        (v.dialogue_message_index.* == 0xc9 or v.dialogue_message_index.* == 0xca))
        v.sprite_delay_aux4[ix_p4(k)] = 40;
}

pub export fn Sprite_E4_SmallKey(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    if (v.dung_savegame_state_bits.* &
        (@as(u16, sprite_tables.kAbsorbBigKey[v.sprite_die_action[i]]) << 8) != 0)
    {
        v.sprite_state[i] = 0;
        return;
    }
    a.Sprite_DrawRippleIfInWater(k);
    if (a.SpriteDraw_AbsorbableTransient(k, false))
        return;
    Sprite_Absorbable_Main(k);
}

pub export fn Sprite_D9_GreenRupee(k: c_int) callconv(.c) void {
    a.Sprite_DrawRippleIfInWater(k);
    if (a.SpriteDraw_AbsorbableTransient(k, true))
        return;
    Sprite_Absorbable_Main(k);
}

pub export fn Sprite_Absorbable_Main(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_MoveZ(k);
    a.Sprite_MoveXY(k);
    if (v.sprite_delay_aux3[i] == 0) {
        a.Sprite_CheckTileCollision2(k);
        a.Sprite_BounceOffWall(k);
    }
    v.sprite_z_vel[i] -%= 2;
    if (sign8_p4(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_x_vel[i] = @bitCast(@as(i8, @bitCast(v.sprite_x_vel[i])) >> 1);
        v.sprite_y_vel[i] = @bitCast(@as(i8, @bitCast(v.sprite_y_vel[i])) >> 1);
        var tt: u8 = 0 -% v.sprite_z_vel[i];
        tt >>= 1;
        if (tt < 9) {
            v.sprite_y_vel[i] = 0;
            v.sprite_x_vel[i] = 0;
            v.sprite_z_vel[i] = 0;
        } else {
            v.sprite_z_vel[i] = tt;
            if (v.sprite_I[i] == 8 or v.sprite_I[i] == 9) {
                v.sprite_z_vel[i] = 0;
                const j = a.Sprite_SpawnSmallSplash(k);
                if (j >= 0 and v.sprite_flags3[i] & 0x20 != 0) {
                    // wtf carry propagation
                    a.Sprite_SetX(j, a.Sprite_GetX(j) -% 4);
                    a.Sprite_SetY(j, a.Sprite_GetY(j) -% 4);
                }
            } else {
                if (v.sprite_type[i] >= 0xe4 and v.player_is_indoors.* != 0)
                    a.SpriteSfx_QueueSfx2WithPan(k, 5);
            }
        }
    }
    if (a.Sprite_HandleDraggingByAncilla(k))
        return;
    a.Sprite_CheckAbsorptionByPlayer(k);
}

pub export fn Sprite_08_Octorok(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    var j: usize = v.sprite_D[i];
    if (v.sprite_delay_aux1[i] != 0)
        v.sprite_D[i] = t.kOctorock_Dir[j];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) |
        t.kOctorock_OamFlags[j] |
        (if (v.sprite_graphics[i] == 7) @as(u8, 0x40) else 0);
    Octorok_Draw(k);
    v.sprite_D[i] = @truncate(j);

    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.sprite_ai_state[i] & 1 == 0) {
        v.sprite_subtype2[i] +%= 1;
        v.sprite_graphics[i] = ((v.sprite_subtype2[i] >> 3) & 3) | ((v.sprite_D[i] & 2) << 1);
        if (v.sprite_delay_main[i] == 0) {
            v.sprite_ai_state[i] +%= 1;
            v.sprite_delay_main[i] = if (v.sprite_type[i] == 8) 60 else 160;
        } else {
            j = v.sprite_D[i];
            v.sprite_x_vel[i] = @bitCast(t.kOctorock_Xvel[j]);
            v.sprite_y_vel[i] = @bitCast(t.kOctorock_Yvel[j]);
            if (a.Sprite_CheckTileCollision(k) != 0)
                v.sprite_D[i] ^= 1;
        }
        return;
    } else {
        a.Sprite_ZeroVelocity_XY(k);
        if (v.sprite_delay_main[i] == 0) {
            v.sprite_ai_state[i] +%= 1;
            v.sprite_delay_main[i] = (a.GetRandomNumber() & 0x3f) +% 48;
            v.sprite_D[i] = v.sprite_delay_main[i] & 3;
        } else {
            switch (v.sprite_type[i]) {
                8 => { // normal
                    j = v.sprite_delay_main[i];
                    if (j == 28)
                        Octorok_FireLoogie(k);
                    v.sprite_C[i] = t.kOctorock_Tab0[j >> 3];
                },
                10 => { // four shooter
                    j = v.sprite_delay_main[i];
                    if (j < 128) {
                        if (j & 15 == 0)
                            v.sprite_D[i] = t.kOctorock_NextDir[v.sprite_D[i]];
                        if (j & 15 == 8)
                            Octorok_FireLoogie(k);
                    }
                    v.sprite_C[i] = t.kOctorock_Tab1[j >> 4];
                },
                else => {},
            }
        }
    }
}

pub export fn Octorok_FireLoogie(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    a.SpriteSfx_QueueSfx2WithPan(k, 0x7);
    const j = a.Sprite_SpawnDynamically(k, 0xc, &info);
    if (j >= 0) {
        const i: usize = v.sprite_D[ix_p4(k)];
        a.Sprite_SetX(j, info.r0_x +% @as(u16, @bitCast(@as(i16, t.kOctorock_Spit_X[i]))));
        a.Sprite_SetY(j, info.r2_y +% @as(u16, @bitCast(@as(i16, t.kOctorock_Spit_Y[i]))));
        v.sprite_x_vel[ix_p4(j)] = @bitCast(t.kOctorock_Spit_Xvel[i]);
        v.sprite_y_vel[ix_p4(j)] = @bitCast(t.kOctorock_Spit_Yvel[i]);
    }
}

pub export fn Octorok_Draw(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    if (v.sprite_D[i] != 3) {
        const oam = oamPtr_p4();
        const j: usize = @as(usize, v.sprite_C[i]) * 3 + v.sprite_D[i];
        setOam_p4(
            oam,
            info.x +% @as(u16, @bitCast(@as(i16, t.kOctorock_Draw_X[j]))),
            info.y +% @as(u16, @bitCast(@as(i16, t.kOctorock_Draw_Y[j]))),
            t.kOctorock_Draw_Char[j],
            t.kOctorock_Draw_Flags[j] | info.flags,
            0,
        );
    }
    v.oam_cur_ptr.* +%= 4;
    v.oam_ext_cur_ptr.* +%= 1;
    v.sprite_flags2[i] -%= 1;
    a.Sprite_PrepAndDrawSingleLargeNoPrep(k, &info);
    v.sprite_flags2[i] +%= 1;
}

pub export fn Sprite_0C_OctorokStone(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    if (v.sprite_state[i] == 6) {
        SpriteDraw_OctorokStoneCrumbling(k);
        if (a.Sprite_ReturnIfPaused(k))
            return;
        if (v.sprite_delay_main[i] == 30)
            a.SpriteSfx_QueueSfx2WithPan(k, 0x1f);
    } else {
        a.SpriteDraw_SingleLarge(k);
        if (a.Sprite_ReturnIfInactive(k))
            return;
        _ = a.Sprite_CheckDamageToLink(k);
        a.Sprite_MoveXY(k);
        if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0 and a.Sprite_CheckTileCollision(k) != 0)
            a.Sprite_Func3(k);
    }
}

pub export fn SpriteDraw_OctorokStoneCrumbling(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p4();
    const g: usize = (v.sprite_delay_main[i] >> 1 & 0xc) ^ 0xc;
    var n: isize = 3;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = g + @as(usize, @intCast(n));
        setOam_p4(
            oam,
            info.x +% @as(u16, @bitCast(@as(i16, t.kOctostone_Draw_X[j]))),
            info.y +% @as(u16, @bitCast(@as(i16, t.kOctostone_Draw_Y[j]))),
            0xbc,
            t.kOctostone_Draw_Flags[j] | 0x2d,
            0,
        );
    }
}

pub export fn Sprite_0F_Octoballoon(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    v.sprite_z[i] = t.kSprite_Octoballoon_Z[v.sprite_subtype2[i] >> 3 & 7];
    Octoballoon_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_delay_main[i] == 0) {
        v.sprite_delay_main[i] = 3;
        if (!a.Octoballoon_Find()) {
            v.sprite_state[i] = 6;
            v.sprite_hit_timer[i] = 0;
            v.sprite_delay_main[i] = 15;
            return;
        }
    }
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    v.sprite_subtype2[i] +%= 1;
    if ((k ^ @as(c_int, v.frame_counter.*)) & 15 == 0) {
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 4);
        const dx = v.sprite_x_vel[i] -% pt.x;
        if (dx != 0)
            v.sprite_x_vel[i] +%= if (sign8_p4(dx)) 1 else @as(u8, @bitCast(@as(i8, -1)));
        const dy = v.sprite_y_vel[i] -% pt.y;
        if (dy != 0)
            v.sprite_y_vel[i] +%= if (sign8_p4(dy)) 1 else @as(u8, @bitCast(@as(i8, -1)));
    }
    a.Sprite_MoveXY(k);
    if (a.Sprite_CheckDamageToLink(k))
        Octoballoon_RecoilLink(k);
    _ = a.Sprite_CheckDamageFromLink(k);
    a.Sprite_CheckTileCollision2(k);
    a.Sprite_BounceOffWall(k);
}

pub export fn Octoballoon_RecoilLink(k: c_int) callconv(.c) void {
    if (v.link_incapacitated_timer.* == 0) {
        v.link_incapacitated_timer.* = 4;
        a.Sprite_ApplyRecoilToLink(k, 16);
        a.Sprite_InvertSpeed_XY(k);
    }
}

pub export fn Octoballoon_Draw(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    var d: usize = 0;
    if (v.sprite_state[i] == 6) {
        if (v.sprite_delay_main[i] == 6 and v.submodule_index.* == 0)
            Octoballoon_FormBabby(k);
        d = (v.sprite_delay_main[i] >> 1 & 4) + 4;
    }
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p4();
    var n: isize = 3;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = d + @as(usize, @intCast(n));
        setOam_p4(
            oam,
            info.x +% @as(u16, @bitCast(@as(i16, t.kOctoballoon_Draw_X[j]))),
            info.y +% @as(u16, @bitCast(@as(i16, t.kOctoballoon_Draw_Y[j]))),
            t.kOctoballoon_Draw_Char[j],
            t.kOctoballoon_Draw_Flags[j] | info.flags,
            2,
        );
    }
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Octoballoon_FormBabby(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx2WithPan(k, 0xc);
    var n: isize = 5;
    while (n >= 0) : (n -= 1) {
        const i: usize = @intCast(n);
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x10, &info);
        if (j >= 0) {
            const ju = ix_p4(j);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_x_vel[ju] = @bitCast(t.kOctoballoon_Spawn_Xv[i]);
            v.sprite_y_vel[ju] = @bitCast(t.kOctoballoon_Spawn_Yv[i]);
            v.sprite_z_vel[ju] = 48;
            v.sprite_subtype2[ju] = 255;
        }
    }
}

pub export fn Sprite_10_OctoballoonBaby(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    if (v.sprite_subtype2[i] == 0)
        v.sprite_state[i] = 0;
    if (v.sprite_subtype2[i] >= 64 or v.sprite_subtype2[i] & 1 == 0)
        a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    v.sprite_subtype2[i] -%= 1;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    v.sprite_z_vel[i] -%= 1;
    a.Sprite_MoveZ(k);
    if (sign8_p4(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = 16;
    }
    a.Sprite_MoveXY(k);
    a.Sprite_CheckTileCollision2(k);
    a.Sprite_BounceOffWall(k);
    _ = a.Sprite_CheckDamageToAndFromLink(k);
}

pub export fn Sprite_0D_Buzzblob(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    if (v.sprite_delay_aux1[i] != 0)
        v.sprite_obj_prio[i] = (v.sprite_obj_prio[i] & 0xf1) |
            t.kBuzzBlob_ObjPrio[v.sprite_delay_aux1[i] >> 1 & 3];
    a.Sprite_Cukeman(k);
    BuzzBlob_Draw(k);
    v.sprite_graphics[i] = t.kBuzzBlob_Gfx[v.sprite_subtype2[i] >> 3 & 3] +%
        (if (v.sprite_delay_aux1[i] != 0) @as(u8, 3) else 0);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_delay_main[i] == 0)
        Buzzblob_SelectNewDirection(k);
    if (v.sprite_delay_aux1[i] == 0)
        a.Sprite_MoveXY(k);
    a.Sprite_CheckTileCollision2(k);
    a.Sprite_BounceOffWall(k);
    _ = a.Sprite_CheckDamageToAndFromLink(k);
}

pub export fn Buzzblob_SelectNewDirection(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    const j: usize = a.GetRandomNumber() & 7;
    v.sprite_x_vel[i] = @bitCast(t.kBuzzBlob_Xvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kBuzzBlob_Yvel[j]);
    v.sprite_delay_main[i] = t.kBuzzBlob_Delay[j];
}

pub export fn BuzzBlob_Draw(k: c_int) callconv(.c) void {
    const i = ix_p4(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr_p4();
    const g: usize = v.sprite_graphics[i];
    var n: isize = 2;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const m: usize = @intCast(n);
        setOam_p4(
            oam,
            info.x +% t.kBuzzBlob_DrawX[m],
            info.y +% @as(u16, @bitCast(t.kBuzzBlob_DrawY[m])),
            t.kBuzzBlob_DrawChar[g * 3 + m],
            t.kBuzzBlob_DrawFlags[g * 3 + m] | info.flags,
            t.kBuzzBlob_DrawExt[m],
        );
        if (oam[0].charnum == 0)
            oam[0].y = 240;
    }
    a.SpriteDraw_Shadow(k, &info);
}

// ---------------------------------------------------------------------------
// from sprite_main_part5.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_ScheduleBossForDeath(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    v.sprite_state[i] = 4;
    v.sprite_A[i] = 0;
    v.sprite_delay_main[i] = 224;
}

pub export fn Sprite_MakeBossExplosion(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx2WithPan(k, 0xc);
    Sprite_MakeBossDeathExplosion_NoSound(k);
}

pub export fn Sprite_MakeBossDeathExplosion_NoSound(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x00, &info);
    if (j >= 0) {
        const ju = ix_p5(j);
        v.load_chr_halfslot_even_odd.* = 11;
        v.sprite_state[ju] = 4;
        v.sprite_flags2[ju] = 3;
        v.sprite_oam_flags[ju] = 12;
        a.Sprite_SetX(j, v.cur_sprite_x.*);
        a.Sprite_SetY(j, v.cur_sprite_y.*);
        v.sprite_delay_main[ju] = 31;
        v.sprite_A[ju] = 31;
        v.sprite_floor[ju] = 2;
    }
}

pub export fn Vulture_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kVulture_Dmd[@as(usize, v.sprite_graphics[ix_p5(k)]) * 2], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_Raven(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    v.sprite_obj_prio[i] |= 0x30;
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXY(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // inwait
            const r = a.Sprite_IsRightOfLink(k);
            v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) | (r.a *% 0x40);
            const x: i32 = @as(i32, v.link_x_coord.*) - @as(i32, v.cur_sprite_x.*);
            const y: i32 = @as(i32, v.link_y_coord.*) - @as(i32, v.cur_sprite_y.*);
            if (@as(u16, @truncate(@as(u32, @bitCast(x + 0x50 + @intFromBool(x >= 0))))) < 0xa0 and
                @as(u16, @truncate(@as(u32, @bitCast(y + 0x58 + @intFromBool(y >= 0))))) < 0xa0)
            {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 24;
                a.SpriteSfx_QueueSfx3WithPan(k, 0x1e);
            }
        },
        1 => { // ascend
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = t.kRaven_AscendTime[v.sprite_A[i]];
                a.Sprite_ApplySpeedTowardsLink(k, 32);
            }
            v.sprite_z[i] +%= 1;
            v.sprite_graphics[i] = @as(u8, @truncate(v.frame_counter.* >> 1 & 1)) +% 1;
        },
        // `goto fly` merges the attack and flee states; state 3 only differs by
        // running away rather than towards.
        2, 3 => {
            const fleeing = v.sprite_ai_state[i] == 3;
            if (!fleeing) {
                if (v.sprite_delay_main[i] == 0 and
                    !(v.is_in_dark_world.* != 0 and v.sprite_A[i] != 0))
                    v.sprite_ai_state[i] +%= 1;
            }
            if ((k ^ @as(c_int, v.frame_counter.*)) & 1 == 0) {
                var pt = a.Sprite_ProjectSpeedTowardsLink(k, if (fleeing) 48 else 32);
                if (fleeing) {
                    pt.x = 0 -% pt.x;
                    pt.y = 0 -% pt.y;
                }
                const dx = v.sprite_x_vel[i] -% pt.x;
                if (dx != 0)
                    v.sprite_x_vel[i] +%= if (sign8_p5(dx)) 1 else @as(u8, 0xff);
                const dy = v.sprite_y_vel[i] -% pt.y;
                if (dy != 0)
                    v.sprite_y_vel[i] +%= if (sign8_p5(dy)) 1 else @as(u8, 0xff);
            }
            v.sprite_graphics[i] = @as(u8, @truncate(v.frame_counter.* >> 1 & 1)) +% 1;
            const j: u8 = (v.sprite_x_vel[i] >> 7) & 1;
            v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) | (j *% 0x40);
        },
        else => {},
    }
}

pub export fn Sprite_SpawnLightning(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xBF, &info);
    if (j >= 0) {
        const ju = ix_p5(j);
        v.sound_effect_2.* = 0x26;
        a.Sprite_SetSpawnedCoordinates(j, &info);
        const i: usize = a.GetRandomNumber() & 7;
        v.sprite_A[ju] = @truncate(i);
        // The C keeps `t` as a 32-bit sum and then shifts by 16, so the carry it
        // adds to the y coordinate is always zero.
        const tt: u32 = @as(u32, info.r0_x) + @as(u32, s16_p5(t.kAgahnim_Lighting_X[i]));
        a.Sprite_SetX(j, info.r0_x +% s16_p5(t.kAgahnim_Lighting_X[i]));
        v.sprite_y_lo[ju] = @truncate(info.r2_y +% 12 +% @as(u16, @truncate(tt >> 16)));
        v.sprite_delay_main[ju] = 2;
        v.intro_times_pal_flash.* = 32;
    }
}

pub export fn Vitreous_Animate(k: c_int, arg: u8) callconv(.c) void {
    const i = ix_p5(k);
    if (arg == 0x40 or arg == 0x41 or arg == 0x42)
        Sprite_SpawnLightning(k);
    v.sprite_graphics[i] = 0;
    const pair = a.Sprite_IsRightOfLink(k);
    if (pair.b +% 16 >= 32)
        v.sprite_graphics[i] = @bitCast(t.kVitreous_Animate_Gfx[pair.a]);
}

pub export fn Vitreous_SetMinionsForth(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_subtype2[i] & 63 == 0) {
        const j: usize = t.kVitreous_WhichToActivate[a.GetRandomNumber() & 15];
        if (v.sprite_ai_state[j] == 0) {
            v.sprite_ai_state[j] = 1;
            v.sound_effect_1.* = 0x15;
        } else {
            v.sprite_subtype2[i] -%= 1;
        }
    }
}

pub export fn Vitreous_Draw(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    if (v.sprite_ai_state[i] == 2 and v.sprite_state[i] == 9) {
        v.oam_cur_ptr.* = 0x800;
        v.oam_ext_cur_ptr.* = 0xa20;
    }
    a.Sprite_DrawMultiple(k, &t.kVitreous_Dmd[@as(usize, v.sprite_graphics[i]) * 4], 4, null);
    if (v.sprite_ai_state[i] == 2) {
        v.sprite_obj_prio[i] &= ~@as(u8, 0xe);
        a.Sprite_DrawLargeShadow2(k);
    }
}

pub export fn Sprite_BE_VitreousEye(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    const d: usize = v.sprite_subtype2[i] >> 4 & 3;
    v.cur_sprite_x.* +%= s16_p5(t.kSprite_Vitreolus_Dx[d]);
    v.cur_sprite_y.* +%= s16_p5(t.kSprite_Vitreolus_Dy[d]);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_graphics[i] != 0)
        return;
    _ = a.Sprite_CheckDamageFromLink(k);
    _ = a.Sprite_CheckDamageToLink(k);
    if (v.sprite_F[i] == 14)
        v.sprite_F[i] = 5;
    switch (v.sprite_ai_state[i]) {
        0 => { // target player
            v.sprite_G[i] = @truncate(v.link_x_coord.*);
            v.sprite_head_dir[i] = @truncate(v.link_x_coord.* >> 8);
            v.sprite_anim_clock[i] = @truncate(v.link_y_coord.*);
            v.sprite_subtype[i] = @truncate(v.link_y_coord.* >> 8);
        },
        1 => { // pursue player
            if (a.Sprite_ReturnIfRecoiling(k))
                return;
            if ((k ^ @as(c_int, v.frame_counter.*)) & 1 == 0) {
                const x = (@as(u16, v.sprite_head_dir[i]) << 8) | v.sprite_G[i];
                const y = (@as(u16, v.sprite_subtype[i]) << 8) | v.sprite_anim_clock[i];
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 16);
                v.sprite_x_vel[i] = pt.x;
                v.sprite_y_vel[i] = pt.y;
            }
            a.Sprite_MoveXY(k);
            if (v.sprite_G[i] -% v.sprite_x_lo[i] +% 4 < 8 and
                v.sprite_anim_clock[i] -% v.sprite_y_lo[i] +% 4 < 8)
                v.sprite_ai_state[i] = 2;
        },
        2 => { // return
            if (a.Sprite_ReturnIfRecoiling(k))
                return;
            if ((k ^ @as(c_int, v.frame_counter.*)) & 1 == 0) {
                const x = @as(u16, v.sprite_A[i]) | (@as(u16, v.sprite_B[i]) << 8);
                const y = @as(u16, v.sprite_C[i]) | (@as(u16, v.sprite_D[i]) << 8);
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 16);
                v.sprite_x_vel[i] = pt.x;
                v.sprite_y_vel[i] = pt.y;
            }
            a.Sprite_MoveXY(k);
            if (v.sprite_A[i] -% v.sprite_x_lo[i] +% 4 < 8 and
                v.sprite_C[i] -% v.sprite_y_lo[i] +% 4 < 8)
            {
                v.sprite_x_lo[i] = v.sprite_A[i];
                v.sprite_x_hi[i] = v.sprite_B[i];
                v.sprite_y_lo[i] = v.sprite_C[i];
                v.sprite_y_hi[i] = v.sprite_D[i];
                v.sprite_ai_state[i] = 0;
            }
        },
        else => {},
    }
}

pub export fn HelmasaurFireball_TriSplit(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    a.SpriteSfx_QueueSfx3WithPan(k, 0x36);
    v.sprite_state[i] = 0;

    v.byte_7E0FB6.* = a.GetRandomNumber();
    var n: isize = 2;
    while (n >= 0) : (n -= 1) {
        const m: usize = @intCast(n);
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x70, &info);
        if (j >= 0) {
            const ju = ix_p5(j);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_x_vel[ju] = @bitCast(t.kHelmasaurFireball_TriSplit_Xvel[m]);
            v.sprite_y_vel[ju] = @bitCast(t.kHelmasaurFireball_TriSplit_Yvel[m]);
            v.sprite_ai_state[ju] = 3;
            v.sprite_ignore_projectile[ju] = 3;
            v.sprite_delay_main[ju] = t.kHelmasaurFireball_TriSplit_Delay[@as(usize, v.byte_7E0FB6.* & 3) + m];
            v.sprite_head_dir[ju] = 0;
            v.sprite_graphics[ju] = 1;
        }
    }
    v.tmp_counter.* = 0xff;
}

pub export fn HelmasaurFireball_QuadSplit(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    a.SpriteSfx_QueueSfx3WithPan(k, 0x36);
    v.sprite_state[i] = 0;
    var n: isize = 3;
    while (n >= 0) : (n -= 1) {
        const m: usize = @intCast(n);
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x70, &info);
        if (j >= 0) {
            const ju = ix_p5(j);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_x_vel[ju] = @bitCast(t.kHelmasaurFireball_QuadSplit_Xvel[m]);
            v.sprite_y_vel[ju] = @bitCast(t.kHelmasaurFireball_QuadSplit_Yvel[m]);
            v.sprite_ai_state[ju] = 4;
            v.sprite_ignore_projectile[ju] = 4;
        }
    }
    v.tmp_counter.* = 0xff;
}

pub export fn Sprite_ArmosCrusher(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    v.sprite_oam_flags[i] = 7;
    v.bg1_y_offset.* = if (v.sprite_delay_aux4[i] != 0)
        (if (v.sprite_delay_aux4[i] & 1 != 0) @as(u16, 0xffff) else 1)
    else
        0;
    switch (v.sprite_G[i]) {
        0 => { // retarget
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if ((v.sprite_delay_main[i] | v.sprite_z[i]) == 0) {
                a.Sprite_ApplySpeedTowardsLink(k, 32);
                v.sprite_z_vel[i] = 32;
                v.sprite_G[i] +%= 1;
                v.sprite_B[i] = @truncate(v.link_x_coord.*);
                v.sprite_C[i] = @truncate(v.link_x_coord.* >> 8);
                v.sprite_E[i] = @truncate(v.link_y_coord.*);
                v.sprite_head_dir[i] = @truncate(v.link_y_coord.* >> 8);
                a.SpriteSfx_QueueSfx2WithPan(k, 0x20);
            }
        },
        1 => { // approach target
            v.sprite_z_vel[i] +%= 3;
            // `goto advance` from the tile-collision test.
            var advance = a.Sprite_CheckTileCollision(k) != 0;
            if (!advance) {
                a.Sprite_Get16BitCoords(k);
                const x = @as(u16, v.sprite_B[i]) | (@as(u16, v.sprite_C[i]) << 8);
                const y = @as(u16, v.sprite_E[i]) | (@as(u16, v.sprite_head_dir[i]) << 8);
                advance = (x -% v.cur_sprite_x.* +% 16 < 32) and (y -% v.cur_sprite_y.* +% 16 < 32);
            }
            if (advance) {
                v.sprite_G[i] +%= 1;
                v.sprite_delay_main[i] = 16;
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
            }
        },
        2 => { // hover
            v.sprite_z_vel[i] = 0;
            if (v.sprite_delay_main[i] == 0)
                v.sprite_G[i] +%= 1;
        },
        3 => { // crush
            v.sprite_z_vel[i] = @bitCast(@as(i8, -104));
            if (!sign8_p5(v.sprite_z[i])) {
                v.sprite_delay_main[i] = 32;
                v.sprite_delay_aux4[i] = 32;
                v.sprite_G[i] = 0;
                a.SpriteSfx_QueueSfx2WithPan(k, 0xc);
            }
        },
        else => {},
    }
}

pub export fn SpriteDraw_Antfairy(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    v.sprite_subtype2[i] +%= 1;
    if ((v.sprite_subtype2[i] & 1) | v.submodule_index.* | v.flag_unk1.* == 0) {
        v.sprite_graphics[i] +%= 1;
        if (v.sprite_graphics[i] == 6)
            v.sprite_graphics[i] = 0;
    }
    a.Sprite_DrawMultiple(k, &t.kDrawFourAroundOne_Dmd[@as(usize, v.sprite_graphics[i]) * 5], 5, null);
}

pub export fn Toppo_Flustered(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    v.sprite_flags2[i] = 130;
    v.sprite_ignore_projectile[i] = 130;
    v.sprite_flags3[i] = 73;
    if (v.sprite_subtype[i] == 0) {
        if (a.Sprite_CheckDamageToLink(k)) {
            v.dialogue_message_index.* = 0x174;
            a.Sprite_ShowMessageMinimal();
            v.sprite_subtype[i] = 1;
        }
    } else if (v.sprite_subtype[i] < 16) {
        v.sprite_subtype[i] +%= 1;
    } else if (v.sprite_subtype[i] == 16) {
        v.sprite_flags5[i] = 0;
        v.sprite_state[i] = 6;
        v.sprite_delay_main[i] = 15;
        v.sprite_flags2[i] +%= 4;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x15);
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x4d, &info);
        if (j >= 0) {
            a.Sprite_SetSpawnedCoordinates(j, &info);
            a.ForcePrizeDrop(j, 6, 6);
        }
        v.sprite_subtype[i] +%= 1;
    }
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = ((v.sprite_subtype2[i] & 4) >> 2) +% 3;
}

pub export fn Lightning_SpawnGarnish(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    const j = ix_p5(a.GarnishAllocOverwriteOld());
    v.garnish_type[j] = 9;
    v.garnish_active.* = 9;
    v.garnish_sprite[j] = v.sprite_A[i];
    v.garnish_x_lo[j] = v.sprite_x_lo[i];
    v.garnish_x_hi[j] = v.sprite_x_hi[i];
    const y = a.Sprite_GetY(k) +% 16;
    v.garnish_y_lo[j] = @truncate(y);
    v.garnish_y_hi[j] = @truncate(y >> 8);
    v.garnish_countdown[j] = 32;
}

pub export fn Sprite_BF_Lightning(k: c_int) callconv(.c) void {
    const i = ix_p5(k);
    const j: usize = v.sprite_A[i];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0xb1) |
        t.kSpriteLightning_OamFlags[j] |
        @as(u8, @truncate(v.frame_counter.* << 1 & 14));
    v.sprite_graphics[i] = t.kSpriteLightning_Gfx[j] +%
        (if (@as(u8, @truncate(v.dungeon_room_index2.*)) == 0x20) @as(u8, 4) else 0);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_delay_main[i] != 0)
        return;
    Lightning_SpawnGarnish(k);
    v.sprite_delay_main[i] = 2;
    a.Sprite_SetY(k, a.Sprite_GetY(k) +% 16);
    if (v.sprite_y_lo[i] -% @as(u8, @truncate(v.BG2VOFS_copy2.*)) >= 0xd0) {
        v.sprite_state[i] = 0;
        return;
    }
    const rr: u8 = a.GetRandomNumber() & 7;
    a.Sprite_SetX(k, a.Sprite_GetX(k) +%
        s16_p5(t.kSpriteLightning_Xoff[(@as(usize, v.sprite_A[i]) << 3) | rr]));
    v.sprite_A[i] = rr;
}

// ---------------------------------------------------------------------------
// from sprite_main_part6.zig
// ---------------------------------------------------------------------------
pub export fn Zirro_DropBomb(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xa8, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.SpriteSfx_QueueSfx2WithPan(k, 0x20);
        v.sprite_z[ju] = info.r4_z;
        // Reads the *spawned* sprite's direction, which Sprite_SpawnDynamically
        // has just zeroed; kept as-is.
        const i: usize = v.sprite_D[ju];
        a.Sprite_SetX(j, info.r0_x +% s16(t.kBomber_SpawnPellet_X[i]));
        a.Sprite_SetY(j, info.r2_y +% s16(t.kBomber_SpawnPellet_Y[i]));
        v.sprite_x_vel[ju] = @bitCast(t.kFluteBoyAnimal_Xvel[i]);
        v.sprite_y_vel[ju] = @bitCast(t.kZazak_Yvel[i]);
        v.sprite_A[ju] = 1;
        v.sprite_ignore_projectile[ju] = 1;
        v.sprite_flags4[ju] = 9;
        v.sprite_flags3[ju] = 0x33;
        v.sprite_oam_flags[ju] = 0x33 & 15;
    }
}

pub export fn Sprite_StalfosBone(k: c_int) callconv(.c) void {
    const i = ix(k);
    StalfosBone_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_CheckDamageToLink(k);
    v.sprite_subtype2[i] +%= 1;
    a.Sprite_MoveXY(k);
    if (v.sprite_delay_main[i] == 0 and a.Sprite_CheckTileCollision(k) != 0) {
        v.sprite_state[i] = 0;
        a.Sprite_PlaceWeaponTink(k);
    }
}

pub export fn StalfosBone_Draw(k: c_int) callconv(.c) void {
    const g: usize = v.sprite_subtype2[ix(k)] >> 2 & 3;
    a.Sprite_DrawMultiple(k, &t.kStalfosBone_Dmd[g * 2], 2, null);
}

pub export fn Sprite_A7_Stalfos(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_A[i] != 0) {
        Sprite_StalfosBone(k);
        return;
    }
    if (v.sprite_E[i] == 0) {
        a.Stalfos_Skellington(k);
        return;
    }
    if (v.sprite_delay_main[i] == 0) {
        v.sprite_x_vel[i] = 1;
        v.sprite_y_vel[i] = 1;
        if (a.Sprite_CheckTileCollision(k) != 0) {
            v.sprite_state[i] = 0;
            return;
        }
        v.sprite_E[i] = 0;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x15);
        a.Sprite_SpawnPoofGarnish(k);
        v.sprite_delay_aux2[i] = 8;
        v.sprite_delay_main[i] = 64;
        v.sprite_y_vel[i] = 0;
        v.sprite_x_vel[i] = 0;
    }
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
}

pub export fn Stalfos_ThrowBone(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xa7, &info);
    if (j >= 0) {
        const ju = ix(j);
        v.sprite_A[ju] = 1;
        a.Sprite_SetSpawnedCoordinates(j, &info);
        a.Sprite_ApplySpeedTowardsLink(j, 32);
        v.sprite_flags2[ju] = 0x21;
        v.sprite_ignore_projectile[ju] = 33;
        v.sprite_flags3[ju] |= 0x40;
        v.sprite_defl_bits[ju] = 0x48;
        v.sprite_delay_main[ju] = 16;
        v.sprite_flags4[ju] = 0x14;
        v.sprite_oam_flags[ju] = 7;
        v.sprite_bump_damage[ju] = 32;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x2);
    }
}

pub export fn Sprite_SpawnFirePhlegm(k: c_int) callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xa5, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.SpriteSfx_QueueSfx3WithPan(k, 0x5);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        const i: usize = v.sprite_D[ix(k)];
        a.Sprite_SetX(j, info.r0_x +% s16(t.kSpawnFirePhlegm_X[i]));
        a.Sprite_SetY(j, info.r2_y +% s16(t.kSpawnFirePhlegm_Y[i]));
        v.sprite_x_vel[ju] = @bitCast(t.kSpawnFirePhlegm_Xvel[i]);
        v.sprite_y_vel[ju] = @bitCast(t.kSpawnFirePhlegm_Yvel[i]);
        v.sprite_flags3[ju] |= 0x40;
        v.sprite_defl_bits[ju] = 0x40;
        v.sprite_flags2[ju] = 0x21;
        v.sprite_B[ju] = 0x21;
        v.sprite_oam_flags[ju] = 2;
        v.sprite_flags4[ju] = 0x14;
        v.sprite_ignore_projectile[ju] = 20;
        v.sprite_bump_damage[ju] = 37;
        if (v.link_shield_type.* >= 3)
            v.sprite_flags5[ju] = 0x20;
    }
    return j;
}

pub export fn FirePhlegm_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j = @as(usize, v.sprite_D[i]) * 4 + @as(usize, v.sprite_graphics[i]) * 2;
    a.Sprite_DrawMultiple(k, &t.kFirePhlegm_Dmd[j], 2, null);
}

pub export fn Sprite_A3_KholdstareShell(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfPaused(k))
        return;
    var pt: a.PointU8 = undefined;
    _ = a.Sprite_DirectionToFaceLink(k, &pt);
    if (pt.x +% 32 < 64 and pt.y +% 32 < 64) {
        a.Sprite_NullifyHookshotDrag();
        a.Sprite_RepelDash();
    }
    _ = a.Sprite_CheckDamageFromLink(k);
    if (v.sprite_ai_state[i] == 0) {
        if (v.sprite_state[i] == 6) {
            v.sprite_flags3[i] = 0xc0;
            v.sprite_ai_state[i] = 1;
            v.sprite_state[i] = 9;
        } else if (v.sprite_hit_timer[i] != 0) {
            v.dung_floor_x_offs.* = if (v.sprite_hit_timer[i] & 2 != 0) 0xffff else 1;
            v.dung_hdr_collision_2_mirror.* = 1;
        } else {
            v.dung_hdr_collision_2_mirror.* = 0;
        }
    } else {
        const old = v.sprite_ai_state[i];
        v.sprite_ai_state[i] +%= 1;
        if (old != 18) {
            a.KholdstareShell_PaletteFiltering();
        } else {
            v.sprite_state[i] = 0;
            v.sprite_ai_state[2] = 2;
            v.sprite_delay_main[2] = 128;
        }
    }
}

pub export fn GenerateIceball(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_subtype2[i] +%= 1;
    if (((v.sprite_subtype2[i] & 127) | v.sprite_delay_aux1[i]) != 0)
        return;
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xa4, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetX(j, v.link_x_coord.*);
        a.Sprite_SetY(j, v.link_y_coord.*);
        v.sprite_z[ju] = @bitCast(@as(i8, -32));
        v.sprite_C[ju] = @bitCast(@as(i8, -32));
        a.SpriteSfx_QueueSfx2WithPan(j, 0x20);
    }
}

pub export fn Kholdstare_SpawnPuffCloudGarnish(k: c_int) callconv(.c) void {
    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 != 0)
        return;
    const j = a.GarnishAllocLow();
    if (j < 0)
        return;
    const ju = ix(j);
    v.garnish_type[ju] = 7;
    v.garnish_active.* = 7;
    v.garnish_countdown[ju] = 31;
    a.Garnish_SetX(j, v.cur_sprite_x.* +% s16(t.kNebuleGarnish_XY[a.GetRandomNumber() & 7]));
    a.Garnish_SetY(j, v.cur_sprite_y.* +% s16(t.kNebuleGarnish_XY[a.GetRandomNumber() & 7]) +% 16);
    v.garnish_floor[ju] = 0;
}

pub export fn IceBall_Split(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx2WithPan(k, 0x1f);
    const b: usize = a.GetRandomNumber() & 4;
    var n: isize = 3;
    while (n >= 0) : (n -= 1) {
        const i: usize = @intCast(n);
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0xa4, &info);
        if (j >= 0) {
            const ju = ix(j);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_ai_state[ju] = 1;
            v.sprite_graphics[ju] = 1;
            v.sprite_C[ju] = 1;
            v.sprite_z_vel[ju] = 32;
            v.sprite_x_vel[ju] = @bitCast(t.kIceBall_Quadruplicate_Xvel[i + b]);
            v.sprite_y_vel[ju] = @bitCast(t.kIceBall_Quadruplicate_Yvel[i + b]);
            v.sprite_flags4[ju] = 0x1c;
        }
    }
    v.tmp_counter.* = 0xff;
}

pub export fn Sprite_A4_FallingIce(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_C[i] == 0) {
        if (a.Sprite_ReturnIfInactive(k))
            return;
        if (v.sprite_state[2] < 9 and v.sprite_state[3] < 9 and v.sprite_state[4] < 9)
            v.sprite_state[i] = 0;
        GenerateIceball(k);
        return;
    }

    v.sprite_ignore_projectile[i] = 1;
    v.sprite_obj_prio[i] = 0x30;
    a.SpriteDraw_SingleLarge(k);
    if (v.sprite_ai_state[i] == 0)
        v.sprite_flags3[i] ^= 16;
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_delay_main[i] != 0) {
        if (v.sprite_delay_main[i] == 1)
            v.sprite_state[i] = 0;
        v.sprite_graphics[i] = (v.sprite_delay_main[i] >> 3) +% 2;
        return;
    }

    a.Sprite_MoveXY(k);
    // The comma operator runs the damage check for its side effect and then
    // tests the tile collision.
    var fall = v.sprite_ai_state[i] == 0;
    if (!fall) {
        _ = a.Sprite_CheckDamageToLink(k);
        fall = a.Sprite_CheckTileCollision(k) == 0;
    }
    if (fall) {
        const old_z = v.sprite_z[i];
        a.Sprite_MoveZ(k);
        if (!sign8(v.sprite_z_vel[i] +% 64))
            v.sprite_z_vel[i] -%= 3;
        if (!(sign8(old_z ^ v.sprite_z[i]) and sign8(v.sprite_z[i])))
            return;
        v.sprite_z[i] = 0;
        if (v.sprite_ai_state[i] == 0) {
            v.sprite_state[i] = 0;
            IceBall_Split(k);
            return;
        }
    }
    v.sprite_delay_main[i] = 15;
    v.sprite_oam_flags[i] = 4;
    if (v.sound_effect_1.* == 0) {
        a.SpriteSfx_QueueSfx2WithPan(k, 0x1e);
        v.sprite_graphics[i] = 3;
    }
}

pub export fn FluteBoyOstrich_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kFluteBoyOstrich_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 4], 4, &info);
    a.SpriteDraw_Shadow_custom(k, &info, 18);
}

// ---------------------------------------------------------------------------
// from sprite_main_part7.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_9E_HauntedGroveOstritch(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.FluteBoyOstrich_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // wait
            v.sprite_graphics[i] = if (v.frame_counter.* & 0x18 != 0) 3 else 0;
            if (v.byte_7E0FDD.* != 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_y_vel[i] = @bitCast(@as(i8, -8));
                v.sprite_x_vel[i] = @bitCast(@as(i8, -16));
            }
        },
        1 => { // run away
            a.Sprite_MoveXYZ(k);
            v.sprite_z_vel[i] -%= 2;
            if (sign8(v.sprite_z[i])) {
                v.sprite_z_vel[i] = 32;
                v.sprite_z[i] = 0;
                v.sprite_subtype2[i] = 0;
                v.sprite_A[i] = 0;
            }
            v.sprite_subtype2[i] +%= 1;
            if (v.sprite_subtype2[i] & 7 == 0 and v.sprite_A[i] != 3)
                v.sprite_A[i] +%= 1;
            v.sprite_graphics[i] = t.kFluteBoyOstrich_Gfx[v.sprite_A[i]];
        },
        else => {},
    }
}

pub export fn Sprite_9F_HauntedGroveRabbit(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) |
        t.kFluteBoyAnimal_OamFlags[v.sprite_D[i]];
    a.SpriteDraw_SingleLarge(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // wait
            v.sprite_graphics[i] = 3;
            if (v.byte_7E0FDD.* != 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_D[i] ^= 1;
                v.sprite_x_vel[i] = @bitCast(t.kFluteBoyAnimal_Xvel[v.sprite_D[i]]);
                v.sprite_y_vel[i] = @bitCast(@as(i8, -8));
            }
        },
        1 => { // run
            a.Sprite_MoveXYZ(k);
            v.sprite_z_vel[i] -%= 3;
            if (sign8(v.sprite_z[i])) {
                v.sprite_z_vel[i] = 24;
                v.sprite_z[i] = 0;
                v.sprite_subtype2[i] = 0;
                v.sprite_A[i] = 0;
            }
            v.sprite_subtype2[i] +%= 1;
            if (v.sprite_subtype2[i] & 3 == 0 and v.sprite_A[i] != 2)
                v.sprite_A[i] +%= 1;
            v.sprite_graphics[i] = t.kFluteBoyAnimal_Gfx[v.sprite_A[i]];
        },
        else => {},
    }
}

pub export fn Sprite_A0_HauntedGroveBird(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_graphics[i] == 3)
        HauntedGroveBird_Blink(k);
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) |
        t.kFluteBoyAnimal_OamFlags[v.sprite_D[i]];
    v.oam_cur_ptr.* +%= 4;
    v.oam_ext_cur_ptr.* +%= 1;
    v.sprite_flags2[i] -%= 1;
    a.SpriteDraw_SingleLarge(k);
    v.sprite_flags2[i] +%= 1;
    a.Sprite_MoveXYZ(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // wait
            v.sprite_graphics[i] = if (v.frame_counter.* & 0x18 != 0) 0 else 3;
            if (v.byte_7E0FDD.* != 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_D[i] ^= 1;
                v.sprite_x_vel[i] = @bitCast(t.kFluteBoyAnimal_Xvel[v.sprite_D[i]]);
                v.sprite_delay_main[i] = 32;
                v.sprite_z_vel[i] = 16;
                v.sprite_y_vel[i] = @bitCast(@as(i8, -8));
            }
        },
        1 => { // rising
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_z_vel[i] +%= 2;
                if (!sign8(v.sprite_z_vel[i] -% 0x10))
                    v.sprite_ai_state[i] = 2;
            }
            v.sprite_subtype2[i] +%= 1;
            v.sprite_graphics[i] = ((v.sprite_subtype2[i] >> 1) & 1) +% 1;
        },
        2 => { // falling
            v.sprite_graphics[i] = 1;
            v.sprite_z_vel[i] -%= 1;
            if (sign8(v.sprite_z_vel[i] +% 15))
                v.sprite_ai_state[i] = 1;
        },
        else => {},
    }
}

pub export fn HauntedGroveBird_Blink(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    const oam = oamPtr();
    const j: usize = v.sprite_D[i];
    oam[0].x = @truncate(info.x +% s16(t.kFluteBoyBird_X[j]));
    oam[0].y = @truncate(info.y);
    oam[0].charnum = 0xae;
    oam[0].flags = info.flags | t.kFluteBoyAnimal_OamFlags[j];
    a.Sprite_CorrectOamEntries(k, 0, 0);
}

pub export fn Sprite_9C_Zoro(k: c_int) callconv(.c) void {
    if (v.sprite_E[ix(k)] != 0) {
        Zoro(k);
    } else {
        Babasu(k);
    }
}

pub export fn Zoro(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_C[i] == 0) {
        v.sprite_C[i] +%= 1;
        if (a.Sprite_IsBelowLink(k).a != 0) {
            v.sprite_state[i] = 0;
            return;
        }
    }
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = (v.sprite_subtype2[i] >> 1) & 1;
    v.sprite_x_vel[i] = @bitCast(t.kFluteBoyAnimal_Xvel[v.sprite_subtype2[i] >> 2 & 1]);
    a.Sprite_MoveXY(k);
    if (v.sprite_delay_main[i] == 0 and a.Sprite_CheckTileCollision(k) != 0)
        v.sprite_state[i] = 0;

    if (v.sprite_subtype2[i] & 3 != 0)
        return;

    const j = a.GarnishAlloc();
    if (j < 0)
        return;
    const ju = ix(j);
    v.garnish_type[ju] = 6;
    v.garnish_active.* = 6;
    a.Garnish_SetX(j, a.Sprite_GetX(k));
    a.Garnish_SetY(j, a.Sprite_GetY(k) +% 16);
    v.garnish_countdown[ju] = 10;
    v.garnish_sprite[ju] = @truncate(@as(u32, @bitCast(k)));
    v.garnish_floor[ju] = v.sprite_floor[i];
}

pub export fn Babasu(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Babusu_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // reset
            v.sprite_ai_state[i] +%= 1;
            v.sprite_delay_main[i] = 128;
            v.sprite_graphics[i] = 255;
        },
        1 => { // hiding
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 55;
            }
        },
        2 => { // terror sprinkles
            const j = v.sprite_delay_main[i];
            const d: usize = v.sprite_D[i];
            if (j == 0) {
                v.sprite_ai_state[i] = 3;
                v.sprite_x_vel[i] = @bitCast(t.kBabusu_XyVel[d]);
                v.sprite_y_vel[i] = @bitCast(t.kBabusu_XyVel[d + 2]);
                v.sprite_delay_main[i] = 32;
            }
            if (j >= 32) {
                v.sprite_graphics[i] = t.kBabusu_Gfx[(j - 32) >> 2] +% t.kBabusu_DirGfx[d];
            } else {
                v.sprite_graphics[i] = 0xff;
            }
        },
        3 => { // scurry across
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            a.Sprite_MoveXY(k);
            v.sprite_graphics[i] = @as(u8, @truncate(v.frame_counter.* >> 1 & 1)) +%
                t.kBabusu_Scurry_Gfx[v.sprite_D[i]];
            if (v.sprite_delay_main[i] == 0 and a.Sprite_CheckTileCollision(k) != 0) {
                v.sprite_D[i] ^= 1;
                v.sprite_ai_state[i] = 0;
            }
        },
        else => {},
    }
}

pub export fn Sprite_9B_Wizzrobe(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_C[i] != 0) {
        a.Sprite_Wizzbeam(k);
        return;
    }
    // C's `||` binds looser than `&&`, which binds looser than `&`.
    if (v.sprite_ai_state[i] == 0 or
        ((v.sprite_ai_state[i] & 1) != 0 and (v.sprite_delay_main[i] & 1) != 0))
    {
        var info: PrepOamCoordsRet = undefined;
        a.Sprite_PrepOamCoord(k, &info);
    } else {
        a.Wizzrobe_Draw(k);
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    v.sprite_ignore_projectile[i] = 1;
    switch (v.sprite_ai_state[i]) {
        0 => { // cloaked
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_y_vel[i] = 1;
                v.sprite_x_vel[i] = 1;
                if (a.Sprite_CheckTileCollision(k) == 0) {
                    v.sprite_ai_state[i] = 1;
                    v.sprite_delay_main[i] = 63;
                    const j = a.Sprite_DirectionToFaceLink(k, null);
                    v.sprite_D[i] = j;
                    v.sprite_graphics[i] = t.kWizzrobe_Cloak_Gfx[j];
                } else {
                    v.sprite_state[i] = 0;
                }
            }
        },
        1 => { // phasing in
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 63;
            }
        },
        2 => { // attack
            v.sprite_ignore_projectile[i] = 0;
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                v.sprite_ai_state[i] = 3;
                v.sprite_delay_main[i] = 63;
                return;
            }
            if (j == 32)
                Wizzrobe_FireBeam(k);
            v.sprite_graphics[i] = t.kWizzrobe_Attack_Gfx[j >> 3] +%
                t.kWizzrobe_Attack_DirGfx[v.sprite_D[i]];
        },
        3 => { // phasing out
            if (v.sprite_delay_main[i] == 0) {
                if (v.sprite_B[i] != 0)
                    v.sprite_state[i] = 0;
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 32;
            }
        },
        else => {},
    }
}

pub export fn Wizzrobe_FireBeam(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x9b, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.SpriteSfx_QueueSfx3WithPan(k, 0x36);
        v.sprite_C[ju] = 1;
        v.sprite_ignore_projectile[ju] = 1;
        a.Sprite_SetX(j, info.r0_x +% 4);
        a.Sprite_SetY(j, info.r2_y);
        const i: usize = v.sprite_D[ix(k)];
        v.sprite_x_vel[ju] = @bitCast(t.kWizzrobe_Beam_XYvel[i]);
        v.sprite_y_vel[ju] = @bitCast(t.kWizzrobe_Beam_XYvel[i + 2]);
        v.sprite_defl_bits[ju] = 0x48;
        v.sprite_oam_flags[ju] = 2;
        v.sprite_flags5[ju] = if (v.link_shield_type.* == 3) 0x20 else 0;
        v.sprite_flags4[ju] = 0x14;
    }
}

pub export fn Sprite_9A_Kyameron(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (v.sprite_ai_state[i] == 0) {
        a.Sprite_PrepOamCoord(k, &info);
    } else {
        a.Kyameron_Draw(k);
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    v.sprite_ignore_projectile[i] = 1;
    switch (v.sprite_ai_state[i]) {
        0 => { // reset
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 96;
                v.sprite_x_lo[i] = v.sprite_A[i];
                v.sprite_x_hi[i] = v.sprite_B[i];
                v.sprite_y_lo[i] = v.sprite_C[i];
                v.sprite_y_hi[i] = v.sprite_head_dir[i];
                v.sprite_subtype2[i] = 5;
                v.sprite_graphics[i] = 8;
            }
        },
        1 => { // puddleup
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 31;
                v.sprite_ai_state[i] = 2;
            }
            v.sprite_subtype2[i] -%= 1;
            if (sign8(v.sprite_subtype2[i])) {
                v.sprite_subtype2[i] = 5;
                v.sprite_graphics[i] = ((v.sprite_graphics[i] +% 1) & 3) +% 8;
            }
        },
        2 => { // coagulate
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                v.sprite_ai_state[i] = 3;
                const d: usize = @as(usize, a.Sprite_IsBelowLink(k).a) * 2 + a.Sprite_IsRightOfLink(k).a;
                v.sprite_x_vel[i] = @bitCast(t.kKyameron_Xvel[d]);
                v.sprite_y_vel[i] = @bitCast(t.kKyameron_Yvel[d]);
            } else {
                if (j == 7)
                    a.Sprite_SetY(k, a.Sprite_GetY(k) -% 29);
                v.sprite_graphics[i] = @bitCast(t.kKyameron_Coagulate_Gfx[j >> 2]);
            }
        },
        3 => { // moving
            v.sprite_ignore_projectile[i] = 0;
            // `goto skip_sound` bails out of the disperse transition.
            var disperse = true;
            if (!a.Sprite_CheckDamageToAndFromLink(k)) {
                a.Sprite_MoveXY(k);
                const j = a.Sprite_CheckTileCollision(k);
                if (j & 3 != 0) {
                    v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
                    v.sprite_anim_clock[i] +%= 1;
                }
                if (j & 12 != 0) {
                    v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
                    v.sprite_anim_clock[i] +%= 1;
                }
                if (v.sprite_anim_clock[i] < 3)
                    disperse = false;
            }
            if (disperse) {
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 15;
                a.SpriteSfx_QueueSfx2WithPan(k, 0x28);
            }
            v.sprite_subtype2[i] +%= 1;
            v.sprite_graphics[i] = t.kKyameron_Moving_Gfx[v.sprite_subtype2[i] >> 3 & 3];
            if ((k ^ @as(c_int, v.frame_counter.*)) & 7 == 0) {
                const x: u16 = (a.GetRandomNumber() & 0xf) -% 4;
                const y: u16 = (a.GetRandomNumber() & 0xf) -% 4;
                _ = a.Sprite_GarnishSpawn_Sparkle(k, x, y);
            }
        },
        4 => { // disperse
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_anim_clock[i] = 0;
                v.sprite_ai_state[i] = 0;
                v.sprite_z[i] = 0;
                v.sprite_delay_main[i] = 64;
            } else {
                v.sprite_graphics[i] = (v.sprite_delay_main[i] >> 2) +% 15;
            }
        },
        else => {},
    }
}

pub export fn Kyameron_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.sprite_graphics[i];
    if (j < 12) {
        const bak = v.sprite_oam_flags[i];
        v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) | t.kKyameron_OamFlags[j];
        a.SpriteDraw_SingleLarge(k);
        v.sprite_oam_flags[i] = bak;
    } else {
        a.Sprite_DrawMultiple(k, &t.kKyameron_Dmd[(j - 12) * 4], 4, null);
    }
}

pub export fn Sprite_LaserBeam(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    LaserBeam_BuildUpGarnish(k);
    a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckDamageToLink_same_layer(k);
    if (v.sprite_delay_main[i] == 0 and a.Sprite_CheckTileCollision(k) != 0) {
        v.sprite_state[i] = 0;
        a.SpriteSfx_QueueSfx3WithPan(k, 0x26);
    }
}

pub export fn LaserBeam_BuildUpGarnish(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j = a.GarnishAllocOverwriteOld();
    const ju = ix(j);
    v.garnish_type[ju] = 4;
    v.garnish_active.* = 4;
    a.Garnish_SetX(j, a.Sprite_GetX(k));
    a.Garnish_SetY(j, a.Sprite_GetY(k) +% 16);
    v.garnish_countdown[ju] = 16;
    v.garnish_oam_flags[ju] = v.sprite_graphics[i];
    v.garnish_sprite[ju] = @truncate(@as(u32, @bitCast(k)));
    v.garnish_floor[ju] = v.sprite_floor[i];
}

pub export fn Sprite_95_LaserEyeLeft(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_A[i] != 0) {
        Sprite_LaserBeam(k);
        return;
    }
    LaserEye_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // monitor firing zone
            if (v.sprite_head_dir[i] == 0 and
                v.sprite_D[i] != t.kLaserEye_Dirs[v.link_direction_facing.* >> 1])
            {
                v.sprite_graphics[i] = 0;
            } else {
                const j: u16 = if (v.sprite_D[i] < 2)
                    v.link_y_coord.* -% v.cur_sprite_y.*
                else
                    v.link_x_coord.* -% v.cur_sprite_x.*;
                if (j +% 16 < 32) {
                    v.sprite_delay_main[i] = 32;
                    v.sprite_ai_state[i] = 1;
                } else {
                    v.sprite_graphics[i] = 0;
                }
            }
        },
        1 => { // firing beam
            v.sprite_graphics[i] = 1;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                LaserEye_FireBeam(k);
                v.sprite_delay_aux4[i] = 12;
            }
        },
        else => {},
    }
}

pub export fn LaserEye_FireBeam(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x95, &info);
    if (j >= 0) {
        const ju = ix(j);
        const i: usize = v.sprite_D[ix(k)];
        v.sprite_graphics[ju] = @truncate((i & 2) >> 1);
        a.Sprite_SetX(j, info.r0_x +% s16(t.kLaserEye_SpawnXY[i]));
        a.Sprite_SetY(j, info.r2_y +% s16(t.kLaserEye_SpawnXY[i + 2]));
        v.sprite_x_vel[ju] = @bitCast(t.kLaserEye_SpawnXYVel[i]);
        v.sprite_y_vel[ju] = @bitCast(t.kLaserEye_SpawnXYVel[i + 2]);
        v.sprite_flags2[ju] = 0x20;
        v.sprite_A[ju] = 0x20;
        v.sprite_oam_flags[ju] = 5;
        v.sprite_defl_bits[ju] = 0x48;
        v.sprite_ignore_projectile[ju] = 0x48;
        v.sprite_delay_main[ju] = 5;
        if (v.link_shield_type.* == 3)
            v.sprite_flags5[ju] = 32;
        a.SpriteSfx_QueueSfx3WithPan(k, 0x19);
    }
}

pub export fn LaserEye_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_head_dir[i] != 0)
        v.sprite_graphics[i] = @intFromBool(v.sprite_delay_aux4[i] == 0);
    v.sprite_obj_prio[i] = 0x30;
    const j = (@as(usize, v.sprite_graphics[i]) + @as(usize, v.sprite_D[i]) * 2) * 3;
    a.Sprite_DrawMultiple(k, &t.kLaserEye_Dmd[j], 3, null);
}

pub export fn Pirogusu_SpawnSplash(k: c_int) callconv(.c) void {
    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 != 0)
        return;
    const x = t.kPirogusu_Tab0[a.GetRandomNumber() & 3];
    const y = t.kPirogusu_Tab0[a.GetRandomNumber() & 3];
    const j = a.GarnishAllocLow();
    if (j >= 0) {
        const ju = ix(j);
        v.garnish_type[ju] = 11;
        v.garnish_active.* = 11;
        a.Garnish_SetX(j, a.Sprite_GetX(k) +% x);
        a.Garnish_SetY(j, a.Sprite_GetY(k) +% y +% 16);
        v.garnish_countdown[ju] = 15;
    }
}

pub export fn Pirogusu_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.sprite_A[i];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) | t.kPirogusu_OamFlags[j];
    v.sprite_graphics[i] = t.kPirogusu_Gfx[j];
    if (j < 4) {
        v.cur_sprite_x.* +%= 4;
        v.cur_sprite_y.* +%= 4;
        a.SpriteDraw_SingleSmall(k);
    } else {
        a.SpriteDraw_SingleLarge(k);
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part8.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_93_Bumper(k: c_int) callconv(.c) void {
    const i = ix(k);
    Bumper_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_CheckTileCollision(k);
    if (v.link_cape_mode.* == 0 and a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Link_CancelDash();
        v.sprite_delay_main[i] = 32;
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 0x30);
        v.link_actual_vel_y.* = pt.y +% @as(u8, @bitCast(t.kBumper_Vels[v.joypad1H_last.* >> 2 & 3]));
        v.link_actual_vel_x.* = pt.x +% @as(u8, @bitCast(t.kBumper_Vels[v.joypad1H_last.* & 3]));
        v.link_incapacitated_timer.* = 20;
        a.Link_ResetSwimmingState();
        a.SpriteSfx_QueueSfx3WithPan(k, 0x32);
    }
    var n: isize = 15;
    while (n >= 0) : (n -= 1) {
        const j: usize = @intCast(n);
        if (((@as(c_int, @intCast(n)) ^ @as(c_int, v.frame_counter.*)) & 3) | v.sprite_z[j] != 0)
            continue;
        if (v.sprite_state[j] < 9 or ((v.sprite_flags3[j] | v.sprite_flags4[j]) & 0x40) != 0)
            continue;
        const jj: c_int = @intCast(n);
        const x = a.Sprite_GetX(jj);
        const y = a.Sprite_GetY(jj);
        if (v.cur_sprite_x.* -% x +% 16 < 32 and v.cur_sprite_y.* -% y +% 16 < 32) {
            v.sprite_F[j] = 15;
            const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 0x40);
            v.sprite_y_recoil[j] = pt.y;
            v.sprite_x_recoil[j] = pt.x;
            v.sprite_delay_main[i] = 32;
            a.SpriteSfx_QueueSfx3WithPan(k, 0x32);
        }
    }
}

pub export fn Bumper_Draw(k: c_int) callconv(.c) void {
    const g: usize = v.sprite_delay_main[ix(k)] >> 1 & 1;
    a.Sprite_DrawMultiple(k, &t.kBumper_Dmd[g * 4], 4, null);
}

/// The `SetToGround` label, which cases 5, 6 and 7 all jump into.

pub export fn Sprite_91_StalfosKnight(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_ai_state[i] == 0) {
        var info: PrepOamCoordsRet = undefined;
        a.Sprite_PrepOamCoord(k, &info);
    } else {
        StalfosKnight_Draw(k);
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if ((v.sprite_hit_timer[i] & 127) == 1) {
        v.sprite_hit_timer[i] = 0;
        v.sprite_ai_state[i] = 6;
        v.sprite_delay_main[i] = 255;
        v.sprite_x_vel[i] = 0;
        v.sprite_y_vel[i] = 0;
        v.enemy_damage_data[0x918] = 2;
    }
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // waiting for player
            v.sprite_flags4[i] = 9;
            v.sprite_ignore_projectile[i] = 9;
            const bak0 = v.sprite_flags2[i];
            v.sprite_flags2[i] |= 128;
            const flag = a.Sprite_CheckDamageToLink(k);
            v.sprite_flags2[i] = bak0;
            if (flag) {
                v.sprite_z[i] = 144;
                v.sprite_ai_state[i] = 1;
                v.sprite_head_dir[i] = 2;
                v.sprite_graphics[i] = 2;
                a.SpriteSfx_QueueSfx2WithPan(k, 0x20);
            }
        },
        1 => { // falling
            const old_z = v.sprite_z[i];
            a.Sprite_MoveZ(k);
            if (!sign8(v.sprite_z_vel[i] +% 64))
                v.sprite_z_vel[i] -%= 3;
            if (sign8(old_z ^ v.sprite_z[i]) and sign8(v.sprite_z[i])) {
                v.sprite_ai_state[i] = 2;
                v.sprite_ignore_projectile[i] = 0;
                v.sprite_z[i] = 0;
                v.sprite_z_vel[i] = 0;
                v.sprite_delay_main[i] = 63;
            }
        },
        2 => {
            v.enemy_damage_data[0x918] = 0;
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 3;
                v.sprite_B[i] = a.GetRandomNumber() & 63;
                v.sprite_delay_main[i] = 127;
            } else {
                v.sprite_graphics[i] = t.kStalfosKnight_Case2_Gfx[v.sprite_delay_main[i] >> 5];
                v.sprite_C[i] = v.sprite_graphics[i];
                v.sprite_head_dir[i] = 2;
            }
        },
        3 => {
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == v.sprite_B[i]) {
                v.sprite_head_dir[i] = a.Sprite_IsRightOfLink(k).a;
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 32;
            } else {
                v.sprite_head_dir[i] = t.kStalfosKnight_Case2_Dir[v.sprite_delay_main[i] >> 3];
                v.sprite_C[i] = 0;
                v.sprite_graphics[i] = 0;
            }
        },
        4 => {
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 5;
                v.sprite_delay_main[i] = 255;
                v.sprite_delay_aux1[i] = 32;
            }
            v.sprite_C[i] = 1;
            v.sprite_graphics[i] = 1;
        },
        5 => {
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_aux1[i] == 0) {
                a.Sprite_MoveXYZ(k);
                _ = a.Sprite_CheckTileCollision(k);
                if (!sign8(v.sprite_z_vel[i] +% 64))
                    v.sprite_z_vel[i] -%= 2;
                if (sign8(v.sprite_z[i] -% 1)) {
                    v.sprite_z[i] = 0;
                    v.sprite_z_vel[i] = 0;
                    if (v.sprite_delay_main[i] == 0) {
                        stalfosKnightSetToGround(k);
                        return;
                    }
                    v.sprite_delay_aux1[i] = 16;
                }
                v.sprite_graphics[i] = if (sign8(v.sprite_z_vel[i] -% 24)) 2 else 0;
            } else {
                if (v.sprite_delay_aux1[i] == 1) {
                    v.sprite_z_vel[i] = 48;
                    a.Sprite_ApplySpeedTowardsLink(k, 16);
                    v.sprite_head_dir[i] = a.Sprite_IsRightOfLink(k).a;
                    a.SpriteSfx_QueueSfx3WithPan(k, 0x13);
                }
                v.sprite_C[i] = 1;
                v.sprite_graphics[i] = 1;
            }
        },
        6 => {
            a.Sprite_MoveXYZ(k);
            _ = a.Sprite_CheckTileCollision(k);
            if (!sign8(v.sprite_z_vel[i] +% 64))
                v.sprite_z_vel[i] -%= 2;
            if (sign8(v.sprite_z[i] -% 1)) {
                v.sprite_z[i] = 0;
                v.sprite_z_vel[i] = 0;
            }
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                if (a.GetRandomNumber() & 1 != 0) {
                    stalfosKnightSetToGround(k);
                    return;
                }
                v.sprite_ai_state[i] = 7;
                v.sprite_delay_main[i] = 80;
            } else {
                if (j >= 224 and (j & 3) == 0)
                    a.SpriteSfx_QueueSfx3WithPan(k, 0x14);
                v.sprite_C[i] = t.kStalfosKnight_Case6_C[j >> 3];
                v.sprite_graphics[i] = 3;
                v.sprite_head_dir[i] = 2;
            }
        },
        7 => {
            if (v.sprite_delay_main[i] == 0) {
                stalfosKnightSetToGround(k);
            } else {
                v.sprite_graphics[i] = t.kStalfosKnight_Case7_Gfx[v.sprite_delay_main[i] >> 2 & 1];
            }
        },
        else => {},
    }
}

pub export fn StalfosKnight_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    SpriteDraw_StalfosKnight_Head(k, &info);
    v.oam_cur_ptr.* +%= 4;
    v.oam_ext_cur_ptr.* +%= 1;
    a.Sprite_DrawMultiple(k, &t.kStalfosKnight_Dmd[@as(usize, v.sprite_graphics[i]) * 5], 5, &info);
    v.oam_cur_ptr.* -%= 4;
    v.oam_ext_cur_ptr.* -%= 1;
    a.SpriteDraw_Shadow_custom(k, &info, 18);
}

pub export fn SpriteDraw_StalfosKnight_Head(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_graphics[i] == 2)
        return;
    const j: usize = v.sprite_head_dir[i];
    const oam = oamPtr();
    setOam(
        oam,
        info.x,
        info.y +% v.sprite_C[i] -% 12,
        t.kStalfosKnight_DrawHead_Char[j],
        info.flags | t.kStalfosKnight_DrawHead_Flags[j],
        2,
    );
}

pub export fn Sprite_90_Wallmaster(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_obj_prio[i] |= 0x30;
    WallMaster_Draw(k);
    if (v.sprite_state[i] != 9) {
        v.flag_is_link_immobilized.* = 0;
        v.link_disable_sprite_damage.* = 0;
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_A[i] != 0) {
        v.link_x_coord.* = a.Sprite_GetX(k);
        v.link_y_coord.* = a.Sprite_GetY(k) -% v.sprite_z[i] +% 3;
        v.flag_is_link_immobilized.* = 1;
        v.link_disable_sprite_damage.* = 1;
        v.link_incapacitated_timer.* = 0;
        v.link_actual_vel_x.* = 0;
        v.link_actual_vel_y.* = 0;
        v.link_y_vel.* = 0;
        v.link_x_vel.* = 0;
        // A 16-bit compare: the subtraction has to leave the high byte set.
        if (@as(u32, v.link_y_coord.* -% v.BG2VOFS_copy2.* -% 16) >= 0x100) {
            v.flag_is_link_immobilized.* = 0;
            v.link_disable_sprite_damage.* = 0;
            a.WallMaster_SendPlayerToLastEntrance();
            a.Link_Initialize();
            return;
        }
    } else {
        _ = a.Sprite_CheckDamageFromLink(k);
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // Descend
            const old_z = v.sprite_z[i];
            a.Sprite_MoveZ(k);
            if (!sign8(v.sprite_z_vel[i] +% 64))
                v.sprite_z_vel[i] -%= 3;
            if (sign8(old_z ^ v.sprite_z[i]) and sign8(v.sprite_z[i])) {
                v.sprite_ai_state[i] = 1;
                v.sprite_z[i] = 0;
                v.sprite_z_vel[i] = 0;
                v.sprite_delay_main[i] = 63;
            }
        },
        1 => { // Attempt Grab
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] = 2;
            v.sprite_graphics[i] = if (v.sprite_delay_main[i] & 0x20 != 0) 0 else 1;
            if (a.Sprite_CheckDamageToLink(k)) {
                v.sprite_A[i] = 1;
                v.sprite_flags3[i] = 64;
                a.SpriteSfx_QueueSfx3WithPan(k, 0x2a);
            }
        },
        2 => { // Ascend
            const old_z = v.sprite_z[i];
            a.Sprite_MoveZ(k);
            if (sign8(v.sprite_z_vel[i] -% 64))
                v.sprite_z_vel[i] +%= 2;
            if (sign8(old_z ^ v.sprite_z[i]) and !sign8(v.sprite_z[i]))
                v.sprite_state[i] = 0;
        },
        else => {},
    }
}

pub export fn WallMaster_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiple(k, &t.kWallMaster_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 4], 4, null);
    a.Sprite_DrawLargeShadow2(k);
}

pub export fn Sprite_8B_Gibdo(k: c_int) callconv(.c) void {
    const i = ix(k);
    Gibdo_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_graphics[i] = t.kGibdo_Gfx[v.sprite_D[i]];
            if (v.frame_counter.* & 7 == 0) {
                const j: usize = v.sprite_A[i];
                const d = v.sprite_D[i] -% t.kGibdo_DirTarget[j];
                if (d != 0) {
                    v.sprite_D[i] +%= if (sign8(d)) 1 else @as(u8, 0xff);
                } else {
                    v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 48;
                    v.sprite_ai_state[i] = 1;
                }
            }
        },
        1 => {
            const d: usize = v.sprite_D[i];
            v.sprite_x_vel[i] = @bitCast(t.kGibdo_XyVel[d + 2]);
            v.sprite_y_vel[i] = @bitCast(t.kGibdo_XyVel[d]);
            a.Sprite_MoveXY(k);
            _ = a.Sprite_CheckTileCollision(k);
            const face = a.Sprite_DirectionToFaceLink(k, null);
            if ((v.sprite_delay_main[i] == 0 or v.sprite_wallcoll[i] != 0) and face != v.sprite_A[i]) {
                v.sprite_A[i] = face;
                v.sprite_ai_state[i] = 0;
            } else {
                v.sprite_B[i] -%= 1;
                if (sign8(v.sprite_B[i])) {
                    v.sprite_B[i] = 14;
                    v.sprite_subtype2[i] +%= 1;
                }
                v.sprite_graphics[i] = t.kGibdo_Gfx2[((v.sprite_subtype2[i] & 1) << 2) | v.sprite_A[i]];
            }
        },
        else => {},
    }
}

pub export fn Gibdo_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kGibdo_Dmd[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    if (v.sprite_pause[i] == 0)
        a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_89_MothulaBeam(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_CheckDamageToLink(k);
    if (v.frame_counter.* & 1 == 0)
        v.sprite_oam_flags[i] ^= 0x80;
    a.Sprite_MoveXY(k);
    if (v.sprite_delay_main[i] == 0 and a.Sprite_CheckTileCollision(k) != 0)
        v.sprite_state[i] = 0;
    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 != 0)
        return;
    var n: isize = 14;
    while (n >= 0) : (n -= 1) {
        const g: usize = @intCast(n);
        if (v.garnish_type[g] == 0) {
            v.garnish_type[g] = 2;
            v.garnish_active.* = 2;
            v.garnish_x_lo[g] = v.sprite_x_lo[i];
            v.garnish_x_hi[g] = v.sprite_x_hi[i];
            v.garnish_y_lo[g] = v.sprite_y_lo[i];
            v.garnish_y_hi[g] = v.sprite_y_hi[i];
            v.garnish_countdown[g] = 16;
            v.garnish_sprite[g] = @truncate(@as(u32, @bitCast(k)));
            v.garnish_floor[g] = v.sprite_floor[i];
            break;
        }
    }
}

pub export fn FlyingTile_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kFlyingTile_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 4], 4, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn SpikeBlock_CheckStatueCollision(k: c_int) callconv(.c) bool {
    var n: isize = 15;
    while (n >= 0) : (n -= 1) {
        const j: usize = @intCast(n);
        const jj: c_int = @intCast(n);
        if ((jj ^ @as(c_int, v.frame_counter.*)) & 1 == 0 and
            v.sprite_state[j] != 0 and v.sprite_type[j] == 0x1c)
        {
            const x0 = a.Sprite_GetX(k);
            const y0 = a.Sprite_GetY(k);
            const x1 = a.Sprite_GetX(jj);
            const y1 = a.Sprite_GetY(jj);
            if (x0 -% x1 +% 16 < 32 and y0 -% y1 +% 16 < 32)
                return false;
        }
    }
    return true;
}

pub export fn Mothula_FlapWings(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_subtype2[i] +%= 1;
    const j: usize = v.sprite_subtype2[i] >> 2 & 3;
    if (j == 0)
        a.SpriteSfx_QueueSfx3WithPan(k, 0x2);
    v.sprite_graphics[i] = t.kMothula_FlapWingsGfx[j];
}

pub export fn Mothula_SpawnBeams(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx3WithPan(k, 0x36);
    var n: isize = 2;
    while (n >= 0) : (n -= 1) {
        const m: usize = @intCast(n);
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x89, &info);
        if (j >= 0) {
            const ju = ix(j);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_y_lo[ju] = @truncate(info.r2_y -% info.r4_z +% 3);
            v.sprite_delay_main[ju] = 16;
            v.sprite_ignore_projectile[ju] = 16;
            v.sprite_x_lo[ju] = @truncate(info.r0_x +% s16(t.kMothula_Beam_Xvel[m]));
            v.sprite_x_vel[ju] = @bitCast(t.kMothula_Beam_Xvel[m]);
            v.sprite_y_vel[ju] = @bitCast(t.kMothula_Beam_Yvel[m]);
            v.sprite_z[ju] = 0;
        }
    }
    v.tmp_counter.* = 0xff;
}

pub export fn Kodongo_SetDirection(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.sprite_D[i];
    v.sprite_x_vel[i] = @bitCast(t.kFluteBoyAnimal_Xvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kZazak_Yvel[j]);
}

pub export fn Kodongo_SpawnFire(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamicallyEx(k, 0x87, &info, 13);
    if (j >= 0) {
        const ju = ix(j);
        const i: usize = v.sprite_D[ix(k)];
        a.Sprite_SetX(j, info.r0_x +% s16(t.kKodondo_Flame_X[i]));
        a.Sprite_SetY(j, info.r2_y +% s16(t.kKodondo_Flame_Y[i]));
        v.sprite_x_vel[ju] = @bitCast(t.kKodondo_Flame_Xvel[i]);
        v.sprite_y_vel[ju] = @bitCast(t.kKodondo_Flame_Yvel[i]);
        v.sprite_ignore_projectile[ju] = 1;
    }
}

pub export fn Flame_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiple(k, &t.kFlame_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 2], 2, null);
}

pub export fn Terrorpin_SetUpHammerHitBox(k: c_int, hb: *SpriteHitBox) callconv(.c) void {
    const x = a.Sprite_GetX(k) -% 16;
    const y = a.Sprite_GetY(k) -% 16;
    hb.r4_spr_xlo = @truncate(x);
    hb.r10_spr_xhi = @truncate(x >> 8);
    hb.r5_spr_ylo = @truncate(y);
    hb.r11_spr_yhi = @truncate(y >> 8);
    hb.r6_spr_xsize = 48;
    hb.r7_spr_ysize = 48;
}

pub export fn Terrorpin_CheckForHammer(k: c_int) callconv(.c) void {
    const i = ix(k);
    if ((v.sprite_z[i] | v.sprite_delay_aux2[i]) == 0 and
        v.sprite_floor[i] == v.link_is_on_lower_level.* and
        v.player_oam_y_offset.* != 0x80 and
        (v.link_item_in_hand.* & 0xa) != 0)
    {
        var hb: SpriteHitBox = undefined;
        a.Player_SetupActionHitBox(&hb);
        Terrorpin_SetUpHammerHitBox(k, &hb);
        if (a.CheckIfHitBoxesOverlap(&hb)) {
            v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
            v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
            v.sprite_delay_aux2[i] = 32;
            v.sprite_z_vel[i] = 32;
            v.sprite_G[i] = 4;
            v.sprite_B[i] ^= 1;
            v.sprite_delay_aux4[i] = if (v.sprite_B[i] != 0) 0xff else 0x40;
        }
    }
    v.sprite_head_dir[i] = 0;
}

// ---------------------------------------------------------------------------
// from sprite_main_part9.zig
// ---------------------------------------------------------------------------
/// sprite.h keeps these file-local in sprite.zig, so they need local copies.

pub export fn Sprite_87_KodongoFire(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_main[i] == 0) {
        a.SpriteDraw_SingleLarge(k);
        if (a.Sprite_ReturnIfInactive(k))
            return;
        v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) |
            t.kFlame_OamFlags[v.frame_counter.* >> 2 & 3];
        if (!a.Sprite_CheckDamageToLink(k)) {
            a.Sprite_MoveXY(k);
            if (a.Sprite_CheckTileCollision(k) == 0)
                return;
        }
        v.sprite_delay_main[i] = 127;
        v.sprite_oam_flags[i] &= 63;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x2a);
    } else {
        // `&&` binds tighter than `||`, and the decrement only happens when the
        // carry bit is set, so it has to stay inside the short-circuit.
        var expire = false;
        if ((a.Sprite_CheckDamageFromLink(k) & kCheckDamageFromPlayer_Carry) != 0) {
            v.sprite_delay_main[i] -%= 1;
            if (v.sprite_delay_main[i] == 0)
                expire = true;
        }
        if (expire or v.sprite_delay_main[i] == 1)
            v.sprite_state[i] = 0;
        v.sprite_graphics[i] = @bitCast(t.kFlame_Gfx[v.sprite_delay_main[i] >> 3]);
        a.Flame_Draw(k);
        _ = a.Sprite_CheckDamageToLink(k);
    }
}

pub export fn YellowStalfos_Animate(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_graphics[i] = t.kYellowStalfos_Gfx2[v.sprite_D[i]];
    v.sprite_flags3[i] &= ~@as(u8, 0x40);
}

pub export fn YellowStalfos_EmancipateHead(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 2, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_z[ju] = 13;
        a.Sprite_ApplySpeedTowardsLink(j, 16);
        v.sprite_delay_main[ju] = 255;
        v.sprite_delay_aux1[ju] = 32;
    }
}

pub export fn YellowStalfos_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.oam_cur_ptr.* +%= 4;
    v.oam_ext_cur_ptr.* +%= 1;
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kYellowStalfos_Dmd[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    v.oam_cur_ptr.* -%= 4;
    v.oam_ext_cur_ptr.* -%= 1;
    if (v.sprite_pause[i] == 0) {
        YellowStalfos_DrawHead(k, &info);
        a.SpriteDraw_Shadow(k, &info);
    }
}

pub export fn YellowStalfos_DrawHead(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    const oam = oamPtr();
    if (v.sprite_graphics[i] == 10 or v.sprite_B[i] == 0x80)
        return;
    const j: usize = v.sprite_head_dir[i];
    setOam(
        oam,
        info.x +% s16(@bitCast(v.sprite_B[i])),
        info.y -% v.sprite_C[i],
        t.kYellowStalfos_Head_Char[j],
        t.kYellowStalfos_Head_Flags[j] | info.flags,
        2,
    );
}

pub export fn SpritePrep_Eyegore(k: c_int) callconv(.c) void {
    const i = ix(k);
    const room: u8 = @truncate(v.dungeon_room_index2.*);
    if (room == 12 or room == 27 or room == 75 or room == 107) {
        v.sprite_B[i] +%= 1;
        if (v.sprite_type[i] == 0x83)
            v.sprite_defl_bits[i] = 0;
    }
}

pub export fn Eyegore_Main(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Eyegore_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_flags3[i] |= 64;
    v.sprite_defl_bits[i] |= 4;
    switch (v.sprite_ai_state[i]) {
        0 => { // wait until player
            if (v.sprite_delay_main[i] == 0) {
                var pt: PointU8 = undefined;
                _ = a.Sprite_DirectionToFaceLink(k, &pt);
                if (pt.x +% 48 < 96 and pt.y +% 48 < 96) {
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_delay_main[i] = 63;
                }
            }
        },
        1 => { // opening eye
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = t.kEyeGore_Opening_Delay[a.GetRandomNumber() & 3];
            } else {
                v.sprite_graphics[i] = t.kEyeGore_Opening_Gfx[v.sprite_delay_main[i] >> 3];
            }
        },
        2 => { // chase player
            v.sprite_flags3[i] &= ~@as(u8, 0x40);
            if (v.sprite_type[i] != 0x84)
                v.sprite_defl_bits[i] &= ~@as(u8, 4);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 63;
                v.sprite_ai_state[i] +%= 1;
                v.sprite_graphics[i] = 0;
            } else {
                if ((k ^ @as(c_int, v.frame_counter.*)) & 31 == 0)
                    v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
                const d: usize = v.sprite_D[i];
                v.sprite_x_vel[i] = @bitCast(t.kFluteBoyAnimal_Xvel[d]);
                v.sprite_y_vel[i] = @bitCast(t.kZazak_Yvel[d]);
                if (v.sprite_wallcoll[i] == 0)
                    a.Sprite_MoveXY(k);
                _ = a.Sprite_CheckTileCollision(k);
                v.sprite_subtype2[i] +%= 1;
                v.sprite_graphics[i] = t.kEyeGore_Chasing_Gfx[(v.sprite_subtype2[i] & 12) | v.sprite_D[i]];
            }
        },
        3 => { // closing eye
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 96;
            } else {
                v.sprite_graphics[i] = t.kEyeGore_Closing_Gfx[v.sprite_delay_main[i] >> 3];
            }
        },
        else => {},
    }
}

pub export fn Eyegore_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kEyeGore_Dmd[@as(usize, v.sprite_graphics[i]) * 4], 4, &info);
    if (v.sprite_pause[i] == 0)
        a.SpriteDraw_Shadow_custom(k, &info, 14);
}

pub export fn SpritePrep_AntifairyCircle(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Sprite_SetX(k, a.Sprite_GetX(k) -% 10);
    v.sprite_y_vel[i] = @bitCast(@as(i8, -18));
    v.sprite_x_vel[i] = 0;
    v.sprite_A[i] = 0;
    v.sprite_B[i] = 0;
    v.tmp_counter.* = 2;
    while (true) {
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x82, &info);
        if (j >= 0) {
            const ju = ix(j);
            const m: usize = v.tmp_counter.*;
            a.Sprite_SetX(j, info.r0_x +% s16(t.kBubbleGroup_X[m]));
            a.Sprite_SetY(j, info.r2_y +% s16(t.kBubbleGroup_Y[m]));
            v.sprite_x_vel[ju] = @bitCast(t.kBubbleGroup_Xvel[m]);
            v.sprite_y_vel[ju] = @bitCast(t.kBubbleGroup_Yvel[m]);
            v.sprite_A[ju] = @bitCast(t.kBubbleGroup_A[m]);
            v.sprite_B[ju] = @bitCast(t.kBubbleGroup_B[m]);
        }
        v.tmp_counter.* -%= 1;
        if (sign8(v.tmp_counter.*))
            break;
    }
}

pub export fn Sprite_82_AntifairyCircle(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_Antfairy(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    var j: usize = v.sprite_A[i] & 1;
    v.sprite_x_vel[i] +%= @bitCast(t.kBubbleGroup_Vel[j]);
    if (v.sprite_x_vel[i] == t.kBubbleGroup_VelTarget[j])
        v.sprite_A[i] +%= 1;

    j = v.sprite_B[i] & 1;
    v.sprite_y_vel[i] +%= @bitCast(t.kBubbleGroup_Vel[j]);
    if (v.sprite_y_vel[i] == t.kBubbleGroup_VelTarget[j])
        v.sprite_B[i] +%= 1;

    a.Sprite_MoveXY(k);
    if (v.sprite_x_vel[i] != 0 and v.sprite_y_vel[i] != 0 and a.Sprite_CheckIfRoomIsClear()) {
        v.sprite_type[i] = 0x15;
        v.sprite_x_vel[i] = if (sign8(v.sprite_x_vel[i])) @bitCast(@as(i8, -16)) else 16;
        v.sprite_y_vel[i] = if (sign8(v.sprite_y_vel[i])) @bitCast(@as(i8, -16)) else 16;
    }
    _ = a.Sprite_CheckDamageToLink(k);
}

pub export fn Sprite_81_Hover(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_obj_prio[i] |= 48;
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_F[i] != 0)
        v.sprite_ai_state[i] = 0;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.sprite_wallcoll[i] == 0)
        a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckTileCollision(k);
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = (v.sprite_subtype2[i] >> 3) & 2;
    switch (v.sprite_ai_state[i]) {
        0 => { // stopped
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                const j: usize = @as(usize, a.Sprite_IsRightOfLink(k).a) +
                    @as(usize, a.Sprite_IsBelowLink(k).a) * 2;
                v.sprite_D[i] = @truncate(j);
                v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) |
                    @as(u8, @bitCast(t.kHover_OamFlags[j]));
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 15) +% 12;
                a.Sprite_ZeroVelocity_XY(k);
            }
        },
        1 => { // moving
            const j: usize = v.sprite_D[i];
            if (v.sprite_delay_main[i] != 0) {
                v.sprite_x_vel[i] +%= @bitCast(t.kHover_AccelX0[j]);
                v.sprite_y_vel[i] +%= @bitCast(t.kHover_AccelY0[j]);
                v.sprite_graphics[i] = (v.sprite_subtype2[i] >> 3) & 1;
            } else {
                v.sprite_x_vel[i] +%= @bitCast(t.kHover_AccelX1[j]);
                v.sprite_y_vel[i] +%= @bitCast(t.kHover_AccelY1[j]);
                if (v.sprite_y_vel[i] == 0) {
                    v.sprite_ai_state[i] = 0;
                    v.sprite_delay_main[i] = 64;
                }
            }
        },
        else => {},
    }
}

pub export fn Sprite_7D_BigSpike(k: c_int) callconv(.c) void {
    const i = ix(k);
    SpikeTrap_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.sprite_ai_state[i] == 0) {
        var pt: PointU8 = undefined;
        const j = a.Sprite_DirectionToFaceLink(k, &pt);
        v.sprite_D[i] = j;
        if (pt.x +% 16 < 32 or pt.y +% 16 < 32) {
            v.sprite_delay_main[i] = t.kSpikeTrap_Delay[j];
            v.sprite_ai_state[i] = 1;
            v.sprite_x_vel[i] = @bitCast(t.kSpikeTrap_Xvel[j]);
            v.sprite_y_vel[i] = @bitCast(t.kSpikeTrap_Yvel[j]);
        }
    } else if (v.sprite_ai_state[i] == 1) {
        if (a.Sprite_CheckTileCollision(k) != 0 or v.sprite_delay_main[i] == 0) {
            v.sprite_ai_state[i] = 2;
            v.sprite_delay_main[i] = 96;
        }
        a.Sprite_MoveXY(k);
    } else {
        if (v.sprite_delay_main[i] == 0) {
            const j: usize = v.sprite_D[i];
            v.sprite_x_vel[i] = @bitCast(t.kSpikeTrap_Xvel2[j]);
            v.sprite_y_vel[i] = @bitCast(t.kSpikeTrap_Yvel2[j]);
            a.Sprite_MoveXY(k);
            if (v.sprite_x_lo[i] == v.sprite_A[i] and v.sprite_y_lo[i] == v.sprite_C[i])
                v.sprite_ai_state[i] = 0;
        }
    }
}

pub export fn SpikeTrap_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiple(k, &t.kSpikeTrap_Dmd[0], 4, null);
}

pub export fn Sprite_80_Firesnake(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) |
        t.kWinder_OamFlags[v.frame_counter.* >> 2 & 3];
    if (v.sprite_A[i] != 0) {
        v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
        if (v.sprite_delay_main[i] == 0)
            v.sprite_state[i] = 0;
        return;
    }
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    Firesnake_SpawnFireball(k);
    if (v.sprite_wallcoll[i] == 0)
        a.Sprite_MoveXY(k);
    if (a.Sprite_CheckTileCollision(k) != 0)
        v.sprite_D[i] = t.kZazak_Dir2[@as(usize, v.sprite_D[i]) * 2 + (a.GetRandomNumber() & 1)];
    const j: usize = v.sprite_D[i];
    v.sprite_x_vel[i] = @bitCast(t.kWinder_Xvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kWinder_Yvel[j]);
}

pub export fn Firesnake_SpawnFireball(j: c_int) callconv(.c) void {
    const ju = ix(j);
    if ((j ^ @as(c_int, v.frame_counter.*)) & 7 != 0)
        return;
    const k = a.GarnishAlloc();
    const ku = ix(k);
    v.garnish_type[ku] = 1;
    v.garnish_active.* = 1;
    v.garnish_x_lo[ku] = v.sprite_x_lo[ju];
    v.garnish_x_hi[ku] = v.sprite_x_hi[ju];
    const y = a.Sprite_GetY(j) +% 16;
    v.garnish_y_lo[ku] = @truncate(y);
    v.garnish_y_hi[ku] = @truncate(y >> 8);
    v.garnish_countdown[ku] = 32;
    v.garnish_sprite[ku] = @truncate(@as(u32, @bitCast(j)));
    v.garnish_floor[ku] = v.sprite_floor[ju];
}

pub export fn Sprite_7C_GreenStalfos(k: c_int) callconv(.c) void {
    const i = ix(k);
    var j: usize = v.sprite_D[i];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) | t.kGreenStalfos_OamFlags[j];
    v.sprite_graphics[i] = t.kGreenStalfos_Gfx[j];
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    j = a.Sprite_DirectionToFaceLink(k, null);
    if (t.kGreenStalfos_Dir[j] != v.link_direction_facing.*) {
        v.sprite_A[i] = 0;
        if ((k ^ @as(c_int, v.frame_counter.*)) & 7 == 0) {
            const vel = v.sprite_B[i];
            if (vel != 4)
                v.sprite_B[i] +%= 1;
            a.Sprite_ApplySpeedTowardsLink(k, vel);
            v.sprite_D[i] = a.Sprite_IsRightOfLink(k).a;
        }
    } else {
        v.sprite_A[i] = 1;
        if ((k ^ @as(c_int, v.frame_counter.*)) & 15 == 0) {
            const vel = v.sprite_B[i];
            if (vel != 0)
                v.sprite_B[i] -%= 1;
            a.Sprite_ApplySpeedTowardsLink(k, vel);
            v.sprite_D[i] = a.Sprite_IsRightOfLink(k).a;
        }
    }
    a.Sprite_MoveXY(k);
}

pub export fn CreateSixBlueBalls(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx3WithPan(k, 0x36);
    v.tmp_counter.* = 5;
    while (true) {
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x55, &info);
        if (j >= 0) {
            const ju = ix(j);
            const m: usize = v.tmp_counter.*;
            a.Sprite_SetX(j, info.r0_x +% 4);
            a.Sprite_SetY(j, info.r2_y +% 4);
            v.sprite_flags3[ju] = (v.sprite_flags3[ju] & ~@as(u8, 1)) | 0x40;
            v.sprite_oam_flags[ju] = 4;
            v.sprite_delay_aux1[ju] = 4;
            v.sprite_flags4[ju] = 20;
            v.sprite_C[ju] = 20;
            v.sprite_E[ju] = 20;
            v.sprite_x_vel[ju] = @bitCast(t.kEnergyBall_SplitXVel[m]);
            v.sprite_y_vel[ju] = @bitCast(t.kEnergyBall_SplitYVel[m]);
        }
        v.tmp_counter.* -%= 1;
        if (sign8(v.tmp_counter.*))
            break;
    }
    v.tmp_counter.* = 0;
}

pub export fn SeekerEnergyBall_Draw(k: c_int) callconv(.c) void {
    const g: usize = v.sprite_subtype2[ix(k)] >> 2 & 1;
    a.Sprite_DrawMultiple(k, &t.kEnergyBall_Dmd[g * 4], 4, null);
}

pub export fn Bee_DormantHive(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_E[i] != 0)
        return;
    v.sprite_state[i] = 0;
    var n: isize = 11;
    while (n >= 0) : (n -= 1)
        SpawnBeeFromHive(k);
}

pub export fn SpawnBeeFromHive(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x79, &info);
    if (j >= 0) {
        a.Sprite_SetSpawnedCoordinates(j, &info);
        InitializeSpawnedBee(j);
    }
}

pub export fn InitializeSpawnedBee(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ai_state[i] = 1;
    v.sprite_delay_main[i] = t.kSpawnBee_InitDelay[i & 3];
    v.sprite_A[i] = v.sprite_delay_main[i];
    v.sprite_delay_aux4[i] = 96;
    v.sprite_x_vel[i] = @bitCast(t.kSpawnBee_InitVel[a.GetRandomNumber() & 7]);
    v.sprite_y_vel[i] = @bitCast(t.kSpawnBee_InitVel[a.GetRandomNumber() & 7]);
}

pub export fn GoldBee_SpawnSelf(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x79, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_ai_state[ju] = 1;
        v.sprite_delay_main[ju] = 64;
        v.sprite_A[ju] = 64;
        v.sprite_delay_aux4[ju] = 96;
        v.sprite_head_dir[ju] = 1;
        v.sprite_x_vel[ju] = @bitCast(t.kSpawnBee_InitVel[a.GetRandomNumber() & 7]);
        v.sprite_y_vel[ju] = @bitCast(t.kSpawnBee_InitVel[a.GetRandomNumber() & 7]);
    }
}

pub export fn Bee_HandleZ(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_z[i] = 16;
    if (v.sprite_head_dir[i] != 0)
        v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0xf1) |
            ((@as(u8, @truncate(v.frame_counter.* >> 4 & 3)) +% 1) << 1);
}

pub export fn Bee_Bzzt(k: c_int) callconv(.c) void {
    if ((k ^ @as(c_int, v.frame_counter.*)) & 31 == 0)
        a.SpriteSfx_QueueSfx3WithPan(k, 0x2c);
}

pub export fn Bee_HandleInteractions(k: c_int) callconv(.c) void {
    if (v.submodule_index.* == 2 and
        (v.dialogue_message_index.* == 0xc8 or v.dialogue_message_index.* == 0xca))
        v.sprite_delay_aux4[ix(k)] = 40;
}

pub export fn Sprite_Find_EmptyBottle() callconv(.c) c_int {
    for (0..4) |i| {
        if (v.link_bottle_info[i] == 2)
            return @intCast(i);
    }
    return -1;
}

// ---------------------------------------------------------------------------
// from sprite_main_part10.zig
// ---------------------------------------------------------------------------
pub export fn ShopItem_PlayBeep(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx2WithPan(k, 0x3c);
}

pub export fn ShopItem_CheckForAPress(k: c_int) callconv(.c) bool {
    if (v.filtered_joypad_L.* & 0x80 == 0)
        return false;
    return a.Sprite_CheckDamageToLink_same_layer(k);
}

pub export fn ShopItem_HandleCost(amt: c_int) callconv(.c) bool {
    if (amt > @as(c_int, v.link_rupees_goal.*))
        return false;
    v.link_rupees_goal.* -%= @truncate(@as(u32, @bitCast(amt)));
    return true;
}

pub export fn ShopItem_HandleReceipt(k: c_int, item: u8) callconv(.c) void {
    v.item_receipt_method.* = 0;
    a.Link_ReceiveItem(item, 0);
    const j: usize = v.sprite_subtype2[ix(k)];
    if (j >= 7) {
        a.Sprite_ShowMessageUnconditional(t.kShopKeeper_GiveItemMsgs[j - 7]);
        a.ShopKeeper_RapidTerminateReceiveItem();
    }
}

pub export fn SpriteDraw_ShopItem(k: c_int) callconv(.c) void {
    const g: usize = v.sprite_subtype2[ix(k)] -% 7;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kShopKeeper_ItemWithPrice_Dmd[g * 5], 5, null);
}

pub export fn ShopKeeper_SpawnShopItem(k: c_int, pos: c_int, what: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamicallyEx(k, 0xbb, &info, 12);
    const ju = ix(j);
    v.sprite_subtype2[ju] = @truncate(@as(u32, @bitCast(what)));
    v.sprite_ignore_projectile[ju] = v.sprite_subtype2[ju];
    a.Sprite_SetX(j, info.r0_x +% s16(t.kShopKeeper_ItemX[ix(pos)]));
    a.Sprite_SetY(j, info.r2_y +% 0x27);
    v.sprite_flags2[ju] |= 4;
}

pub export fn ShopItem_MakeShieldsDeflect(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] = 0;
    v.sprite_flags[i] = 8;
    v.sprite_defl_bits[i] = 4;
    v.sprite_flags4[i] = 0x1c;
    _ = a.Sprite_CheckDamageFromLink(k);
    v.sprite_flags4[i] = 0xa;
}

pub export fn ShopItem_RedPotion150(k: c_int) callconv(.c) void {
    const i = ix(k);
    SpriteDraw_ShopItem(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (ShopItem_CheckForAPress(k)) {
        if (a.Sprite_Find_EmptyBottle() < 0) {
            a.Sprite_ShowMessageUnconditional(0x16d);
            ShopItem_PlayBeep(k);
        } else if (ShopItem_HandleCost(150)) {
            v.sprite_state[i] = 0;
            ShopItem_HandleReceipt(k, 0x2e);
        } else {
            a.Sprite_ShowMessageUnconditional(0x17c);
            ShopItem_PlayBeep(k);
        }
    }
}

pub export fn ShopItem_FighterShield(k: c_int) callconv(.c) void {
    const i = ix(k);
    SpriteDraw_ShopItem(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    ShopItem_MakeShieldsDeflect(k);
    if (ShopItem_CheckForAPress(k)) {
        if (v.link_shield_type.* != 0) {
            a.Sprite_ShowMessageUnconditional(0x166);
            ShopItem_PlayBeep(k);
            return;
        }
        if (!ShopItem_HandleCost(50)) {
            a.Sprite_ShowMessageUnconditional(0x17c);
            ShopItem_PlayBeep(k);
            return;
        }
        v.sprite_state[i] = 0;
        ShopItem_HandleReceipt(k, 4);
    }
    v.sprite_flags4[i] = 0x1c;
}

pub export fn ShopItem_FireShield(k: c_int) callconv(.c) void {
    const i = ix(k);
    SpriteDraw_ShopItem(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    ShopItem_MakeShieldsDeflect(k);
    if (ShopItem_CheckForAPress(k)) {
        if (v.link_shield_type.* >= 2) {
            a.Sprite_ShowMessageUnconditional(0x166);
            ShopItem_PlayBeep(k);
            return;
        }
        if (!ShopItem_HandleCost(500)) {
            a.Sprite_ShowMessageUnconditional(0x17c);
            ShopItem_PlayBeep(k);
            return;
        }
        v.sprite_state[i] = 0;
        ShopItem_HandleReceipt(k, 5);
    }
    v.sprite_flags4[i] = 0x1c;
}

pub export fn ShopItem_Heart(k: c_int) callconv(.c) void {
    const i = ix(k);
    SpriteDraw_ShopItem(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (ShopItem_CheckForAPress(k)) {
        if (v.link_health_current.* == v.link_health_capacity.*) {
            ShopItem_PlayBeep(k);
        } else if (ShopItem_HandleCost(10)) {
            v.sprite_state[i] = 0;
            ShopItem_HandleReceipt(k, 0x42);
        } else {
            a.Sprite_ShowMessageUnconditional(0x17c);
            ShopItem_PlayBeep(k);
        }
    }
}

pub export fn ShopItem_Arrows(k: c_int) callconv(.c) void {
    const i = ix(k);
    SpriteDraw_ShopItem(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (ShopItem_CheckForAPress(k)) {
        if (v.link_num_arrows.* == hud_tables.kMaxArrowsForLevel[v.link_arrow_upgrades.*]) {
            _ = a.Sprite_ShowSolicitedMessage(k, 0x16e);
            ShopItem_PlayBeep(k);
        } else if (ShopItem_HandleCost(30)) {
            v.sprite_state[i] = 0;
            ShopItem_HandleReceipt(k, 0x44);
        } else {
            a.Sprite_ShowMessageUnconditional(0x17c);
            ShopItem_PlayBeep(k);
        }
    }
}

pub export fn ShopItem_Bombs(k: c_int) callconv(.c) void {
    const i = ix(k);
    SpriteDraw_ShopItem(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (ShopItem_CheckForAPress(k)) {
        if (v.link_item_bombs.* == hud_tables.kMaxBombsForLevel[v.link_bomb_upgrades.*]) {
            _ = a.Sprite_ShowSolicitedMessage(k, 0x16e);
            ShopItem_PlayBeep(k);
        } else if (ShopItem_HandleCost(50)) {
            v.sprite_state[i] = 0;
            ShopItem_HandleReceipt(k, 0x31);
        } else {
            a.Sprite_ShowMessageUnconditional(0x17c);
            ShopItem_PlayBeep(k);
        }
    }
}

pub export fn ShopItem_Bee(k: c_int) callconv(.c) void {
    const i = ix(k);
    SpriteDraw_ShopItem(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (ShopItem_CheckForAPress(k)) {
        if (a.Sprite_Find_EmptyBottle() < 0) {
            _ = a.Sprite_ShowSolicitedMessage(k, 0x16d);
            ShopItem_PlayBeep(k);
        } else if (ShopItem_HandleCost(10)) {
            v.sprite_state[i] = 0;
            ShopItem_HandleReceipt(k, 0xe);
        } else {
            a.Sprite_ShowMessageUnconditional(0x17c);
            ShopItem_PlayBeep(k);
        }
    }
}

pub export fn BombShopEntity_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    const j = @as(usize, v.sprite_subtype2[i]) * 2 + v.sprite_graphics[i];
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kBombShopEntity_Dmd[j], 1, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn BombShop_ClerkExhalation(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xb5, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetX(j, info.r0_x +% 4);
        a.Sprite_SetY(j, info.r2_y +% 16);
        v.sprite_subtype2[ju] = 3;
        v.sprite_ignore_projectile[ju] = 3;
        v.sprite_z[ju] = 4;
        v.sprite_z_vel[ju] = @bitCast(@as(i8, -12));
        v.sprite_delay_main[ju] = 23;
        v.sprite_flags3[ju] &= ~@as(u8, 0x11);
    }
}

pub export fn Sprite_BombShop_Huff(k: c_int) callconv(.c) void {
    const i = ix(k);
    _ = a.Oam_AllocateFromRegionC(4);
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    v.sprite_oam_flags[i] &= 0x30;
    v.sprite_oam_flags[i] |= t.kSnoutPutt_Dmd[v.frame_counter.* >> 2 & 3];
    v.sprite_z_vel[i] +%= 1;
    a.Sprite_MoveZ(k);
    if (v.sprite_delay_main[i] == 0)
        v.sprite_state[i] = 0;
    v.sprite_graphics[i] = v.sprite_delay_main[i] >> 3 & 3;
}

pub export fn BallGuy_PlayBounceNoise(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx3WithPan(k, 0x32);
}

pub export fn PinkBall_HandleDeceleration(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_x_vel[i] != 0)
        v.sprite_x_vel[i] +%= if (sign8(v.sprite_x_vel[i])) 2 else @as(u8, 0xfe);
    if (v.sprite_y_vel[i] != 0)
        v.sprite_y_vel[i] +%= if (sign8(v.sprite_y_vel[i])) 2 else @as(u8, 0xfe);
}

pub export fn PinkBall_Distress(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    a.Sprite_DrawDistress_custom(info.x, info.y, v.frame_counter.*);
}

pub export fn PinkBall_HandleMessage(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_aux4[i] != 0)
        return;
    const msg: u16 = if (v.link_item_moon_pearl.* & 1 != 0) 0x15c else 0x15b;
    if (a.Sprite_ShowMessageOnContact(k, msg) & 0x100 != 0) {
        v.sprite_x_vel[i] ^= 255;
        v.sprite_y_vel[i] ^= 255;
        if (v.sprite_E[i] != 0)
            BallGuy_PlayBounceNoise(k);
        v.sprite_delay_aux4[i] = 64;
    }
}

pub export fn Bully_HandleMessage(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_aux4[i] != 0)
        return;
    const msg: u16 = if (v.link_item_moon_pearl.* & 1 != 0) 0x15e else 0x15d;
    if (a.Sprite_ShowMessageOnContact(k, msg) & 0x100 != 0) {
        v.sprite_x_vel[i] ^= 255;
        v.sprite_y_vel[i] ^= 255;
        v.sprite_delay_aux4[i] = 64;
    }
}

pub export fn Bully_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    const j = @as(usize, v.sprite_D[i]) * 4 + @as(usize, v.sprite_graphics[i]) * 2;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kBully_Dmd[j], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn SpawnBully(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xB9, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_subtype2[ju] = 2;
        v.sprite_head_dir[ju] = @truncate(@as(u32, @bitCast(k)));
        v.sprite_ignore_projectile[ju] = 1;
    }
}

pub export fn Sprite_Bully(k: c_int) callconv(.c) void {
    const i = ix(k);
    Bully_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    Bully_HandleMessage(k);
    a.Sprite_MoveXYZ(k);
    const coll = a.Sprite_CheckTileCollision(k);
    if (coll != 0) {
        if (coll & 3 == 0) {
            v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
        } else {
            v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
        }
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // chase
            v.sprite_graphics[i] = @truncate(@as(u32, @bitCast((k ^ @as(c_int, v.frame_counter.*)) >> 3 & 1)));
            const j: c_int = v.sprite_head_dir[i];
            const ju = ix(j);
            if ((k ^ @as(c_int, v.frame_counter.*)) & 0x1f == 0) {
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, a.Sprite_GetX(j), a.Sprite_GetY(j), 14);
                v.sprite_y_vel[i] = pt.y;
                v.sprite_x_vel[i] = pt.x;
                if (pt.x != 0)
                    v.sprite_D[i] = v.sprite_x_vel[i] >> 7;
            }
            if (v.sprite_z[ju] == 0) {
                if (v.sprite_x_lo[i] -% v.sprite_x_lo[ju] +% 8 < 16 and
                    v.sprite_y_lo[i] -% v.sprite_y_lo[ju] +% 8 < 16)
                {
                    v.sprite_ai_state[i] +%= 1;
                    BallGuy_PlayBounceNoise(k);
                }
            }
        },
        1 => { // kick ball
            v.sprite_ai_state[i] = 2;
            const ju = ix(@as(c_int, v.sprite_head_dir[i]));
            v.sprite_x_vel[ju] = v.sprite_x_vel[i] << 1;
            v.sprite_y_vel[ju] = v.sprite_y_vel[i] << 1;
            v.sprite_x_vel[i] = 0;
            v.sprite_y_vel[i] = 0;
            v.sprite_z_vel[ju] = a.GetRandomNumber() & 31;
            v.sprite_delay_main[i] = 96;
            v.sprite_graphics[i] = 1;
            v.sprite_E[ju] = 1;
        },
        2 => { // waiting
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] = 0;
        },
        else => {},
    }
}

pub export fn SpawnApple(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xac, &info);
    if (j < 0)
        return;
    const ju = ix(j);
    a.Sprite_SetSpawnedCoordinates(j, &info);
    v.sprite_ai_state[ju] = 1;
    v.sprite_A[ju] = 255;
    v.sprite_z[ju] = 8;
    v.sprite_z_vel[ju] = 22;
    const x = (info.r0_x & 0xff00) | @as(u16, a.GetRandomNumber());
    const y = (info.r2_y & 0xff00) | @as(u16, a.GetRandomNumber());
    const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 10);
    v.sprite_x_vel[ju] = pt.x;
    v.sprite_y_vel[ju] = pt.y;
}

pub export fn Sprite_AC_Apple(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_ai_state[i] != 0) {
        a.Sprite_Apple(k);
        return;
    }
    if (v.sprite_E[i] == 0) {
        v.sprite_state[i] = 0;
        // do/while(--n >= 0) runs one more time than n suggests.
        var n: c_int = @as(c_int, a.GetRandomNumber() & 3) + 2;
        while (true) {
            SpawnApple(k);
            n -= 1;
            if (n < 0)
                break;
        }
    }
}

pub export fn Sprite_Apple(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_A[i] >= 16 or v.frame_counter.* & 2 != 0)
        a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_A[i] == 0) {
        v.sprite_state[i] = 0;
        return;
    }
    a.Sprite_MoveXYZ(k);
    if (a.Sprite_CheckDamageToLink(k)) {
        a.SpriteSfx_QueueSfx3WithPan(k, 0xb);
        v.link_hearts_filler.* +%= 8;
        v.sprite_state[i] = 0;
        return;
    }
    if (v.frame_counter.* & 1 == 0)
        v.sprite_A[i] -%= 1;

    if (!sign8(v.sprite_z[i] -% 1)) {
        v.sprite_z_vel[i] -%= 1;
        return;
    }
    v.sprite_z[i] = 0;
    const av: u8 = if (sign8(v.sprite_z_vel[i])) v.sprite_z_vel[i] else 0;
    v.sprite_z_vel[i] = (0 -% av) >> 1;
    if (v.sprite_x_vel[i] != 0)
        v.sprite_x_vel[i] +%= if (sign8(v.sprite_x_vel[i])) 1 else @as(u8, 0xff);
    if (v.sprite_y_vel[i] != 0)
        v.sprite_y_vel[i] +%= if (sign8(v.sprite_y_vel[i])) 1 else @as(u8, 0xff);
}

pub export fn Sprite_BC_Drunkard(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.DrinkingGuy_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (a.GetRandomNumber() == 0)
        v.sprite_delay_main[i] = 32;
    v.sprite_graphics[i] = if (v.sprite_delay_main[i] != 0) 1 else 0;
    if (a.Sprite_ShowSolicitedMessage(k, 0x175) & 0x100 != 0)
        v.sprite_graphics[i] = 0;
}

pub export fn NiceThief_Animate(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.frame_counter.* & 3 == 0) {
        v.sprite_graphics[i] = 2;
        const dir = a.Sprite_DirectionToFaceLink(k, null);
        v.sprite_head_dir[i] = if (dir == 3) 2 else dir;
    }
    a.Oam_AllocateDeferToPlayer(k);
    a.Thief_Draw(k);
}

pub export fn NiceThiefUnderRock(k: c_int) callconv(.c) void {
    NiceThief_Animate(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    _ = a.Sprite_ShowSolicitedMessage(k, if (v.sprite_subtype2[ix(k)] == 5) 0x177 else 0x178);
}

pub export fn OldMan_EnableCutscene() callconv(.c) void {
    v.flag_is_link_immobilized.* = 1;
    v.link_disable_sprite_damage.* = 1;
}

// ---------------------------------------------------------------------------
// from sprite_main_part11.zig
// ---------------------------------------------------------------------------
pub export fn SomariaPlatformAndPipe_CheckTile(k: c_int) callconv(.c) u8 {
    var x = a.Sprite_GetX(k);
    return a.GetTileAttribute(0, &x, a.Sprite_GetY(k));
}

pub export fn SomariaPlatformAndPipe_HandleMovement(k: c_int) callconv(.c) void {
    const i = ix(k);
    SomariaPlatform_HandleJunctions(k);
    const j: usize = v.sprite_D[i];
    v.sprite_x_vel[i] = @bitCast(t.kSomariaPlatform_Xvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kSomariaPlatform_Yvel[j]);
}

pub export fn SomariaPlatform_Draw(k: c_int) callconv(.c) void {
    _ = a.Oam_AllocateFromRegionB(0x10);
    const g: usize = v.sprite_delay_aux4[ix(k)] & 12;
    a.Sprite_DrawMultiple(k, &t.kSomariaPlatform_Dmd[g], 4, null);
}

/// The junction tiles all decode the d-pad the same way; only the mask and the
/// fallback direction differ. Returns false when no direction key was held.

pub export fn SomariaPlatform_HandleJunctions(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_E[i]) {
        0xb2, 0xb5 => v.sprite_D[i] ^= 3, // ZigZagRisingSlope
        0xb3, 0xb4 => v.sprite_D[i] ^= 2, // ZigZagFallingSlope
        0xb6 => { // TransitTile
            v.sprite_ai_state[i] = 1;
            if (v.link_auxiliary_state.* == 0 and
                (v.joypad1H_last.* & t.kSomariaPlatform_TransitDir[v.sprite_D[i]]) != 0)
            {
                v.sprite_ai_state[i] = 0;
                v.sprite_D[i] ^= 1;
            }
            v.link_visibility_status.* = 0;
            v.player_on_somaria_platform.* = 1;
        },
        0xb7 => { // Tjunc_NoUp
            if (!somariaDecodeKeys(i, t.kSomariaPlatform_Keys1[v.sprite_D[i]]) and v.sprite_D[i] == 0)
                v.sprite_D[i] = 2;
            v.sprite_ai_state[i] = 0;
        },
        0xb8 => { // Tjunc_NoDown
            if (!somariaDecodeKeys(i, t.kSomariaPlatform_Keys2[v.sprite_D[i]]) and v.sprite_D[i] == 1)
                v.sprite_D[i] = 2;
            v.sprite_ai_state[i] = 0;
        },
        0xb9 => { // Tjunc_NoLeft
            if (!somariaDecodeKeys(i, t.kSomariaPlatform_Keys3[v.sprite_D[i]]) and v.sprite_D[i] == 2)
                v.sprite_D[i] = 0;
            v.sprite_ai_state[i] = 0;
        },
        0xba => { // Tjunc_NoRight
            if (!somariaDecodeKeys(i, t.kSomariaPlatform_Keys4[v.sprite_D[i]]) and v.sprite_D[i] == 3)
                v.sprite_D[i] = 0;
            v.sprite_ai_state[i] = 0;
        },
        0xbb => { // TransitTileNoBack
            _ = somariaDecodeKeys(i, t.kSomariaPlatform_Keys5[v.sprite_D[i]]);
        },
        0xbc => { // TransitTileQuestion
            v.sprite_ai_state[i] = 1;
            if (somariaDecodeKeys(i, t.kSomariaPlatform_Keys6[v.sprite_D[i]]))
                v.sprite_ai_state[i] = 0;
            v.player_on_somaria_platform.* = 1;
        },
        0xbe => { // endpoint
            v.sprite_ai_state[i] = 0;
            v.sprite_D[i] ^= 1;
            v.link_visibility_status.* = 0;
            v.player_on_somaria_platform.* = 1;
        },
        else => {},
    }
}

pub export fn SomariaPlatform_HandleDragX(k: c_int) callconv(.c) void {
    const i = ix(k);
    if ((v.sprite_D[i] ^ v.sprite_head_dir[i]) & 2 != 0) {
        const x: u8 = (v.sprite_x_lo[i] & ~@as(u8, 7)) +% 4;
        const d: u8 = x -% v.sprite_x_lo[i];
        if (d == 0)
            return;
        v.drag_player_x.* = @bitCast(@as(i16, @as(i8, @bitCast(d))));
        v.sprite_x_lo[i] = x;
    }
}

pub export fn SomariaPlatform_HandleDragY(k: c_int) callconv(.c) void {
    const i = ix(k);
    if ((v.sprite_D[i] ^ v.sprite_head_dir[i]) & 2 != 0) {
        const y: u8 = (v.sprite_y_lo[i] & ~@as(u8, 7)) +% 4;
        const d: u8 = y -% v.sprite_y_lo[i];
        if (d == 0)
            return;
        v.drag_player_y.* = @bitCast(@as(i16, @as(i8, @bitCast(d))));
        v.sprite_y_lo[i] = y;
    }
}

pub export fn SomariaPlatform_HandleDrag(k: c_int) callconv(.c) void {
    SomariaPlatform_HandleDragX(k);
    SomariaPlatform_HandleDragY(k);
}

pub export fn SomariaPlatform_DragLink(k: c_int) callconv(.c) void {
    // The C takes `k` but works purely off the cached sprite coordinates.
    _ = k;
    const x = v.cur_sprite_x.* -% 8 -% v.link_x_coord.*;
    if (x != 0)
        v.drag_player_x.* +%= if (sign16_p11(x)) @as(u16, 0xffff) else 1;
    const y = v.cur_sprite_y.* -% 16 -% v.link_y_coord.*;
    if (y != 0)
        v.drag_player_y.* +%= if (sign16_p11(y)) @as(u16, 0xffff) else 1;
}

pub export fn Pipe_ValidateEntry() callconv(.c) bool {
    var i: isize = 4;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        if (v.ancilla_type[u] == 0x31) {
            v.link_position_mode.* = 0;
            v.link_cant_change_direction.* = 0;
            v.ancilla_type[u] = 0;
            break;
        }
    }
    return ((v.link_state_bits.* & 0x80) | v.link_auxiliary_state.*) != 0;
}

pub export fn Ancilla_TerminateSparkleObjects() callconv(.c) void {
    var i: isize = 4;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        const ty = v.ancilla_type[u];
        if (ty == 0x2a or ty == 0x2b or ty == 0x30 or ty == 0x31 or
            ty == 0x18 or ty == 0x19 or ty == 0xc)
            v.ancilla_type[u] = 0;
    }
}

pub export fn Pipe_HandlePlayerMovement(dir: u8) callconv(.c) void {
    v.link_direction.* = dir;
    v.link_direction_last.* = dir;
    a.Link_HandleVelocity();
    a.Link_HandleMovingAnimation_FullLongEntry();
    a.HandleIndoorCameraAndDoors();
}

pub export fn Sprite_AE_Pipe_Down(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_graphics[i]) {
        0 => { // locate transit tile
            v.alt_sprite_spawned_flag[0] = 255;
            v.sprite_D[i] = v.sprite_type[i] -% 0xae;
            a.SomariaPlatform_LocatePath(k);
        },
        1 => { // locate endpoint
            var tile = SomariaPlatformAndPipe_CheckTile(k);
            if (tile == 0xbe) {
                v.sprite_graphics[i] +%= 1;
                v.sprite_D[i] ^= 1;
                tile = v.sprite_D[i];
            }
            v.sprite_E[i] = tile;
            v.sprite_head_dir[i] = v.sprite_D[i];
            SomariaPlatformAndPipe_HandleMovement(k);
            a.Sprite_MoveXY(k);
        },
        2 => { // wait for player
            if (v.alt_sprite_spawned_flag[0] == 255 and a.Sprite_CheckDamageToLink_ignore_layer(k)) {
                if (!Pipe_ValidateEntry()) {
                    v.sprite_graphics[i] +%= 1;
                    v.sprite_delay_aux1[i] = 4;
                    a.Link_ResetProperties_A();
                    v.flag_is_link_immobilized.* = 1;
                    v.link_disable_sprite_damage.* = 1;
                    v.alt_sprite_spawned_flag[0] = @truncate(@as(u32, @bitCast(k)));
                } else {
                    a.Sprite_HaltAllMovement();
                }
            }
        },
        3 => { // draw player in
            if (v.sprite_delay_aux1[i] == 0) {
                v.sprite_graphics[i] +%= 1;
                v.link_visibility_status.* = 12;
            } else {
                v.flag_is_link_immobilized.* = 1;
                v.link_disable_sprite_damage.* = 1;
                Pipe_HandlePlayerMovement(t.kPipe_Dirs[v.sprite_D[i]]);
            }
        },
        4 => { // draw player along
            v.sprite_subtype2[i] = 3;
            v.link_x_coord_safe_return_lo.* = @truncate(v.link_x_coord.*);
            v.link_x_coord_safe_return_hi.* = @truncate(v.link_x_coord.* >> 8);
            v.link_y_coord_safe_return_lo.* = @truncate(v.link_y_coord.*);
            v.link_y_coord_safe_return_hi.* = @truncate(v.link_y_coord.* >> 8);
            while (true) {
                v.sprite_A[i] +%= 1;
                if (v.sprite_A[i] & 7 == 0) {
                    const tile = SomariaPlatformAndPipe_CheckTile(k);
                    if (tile >= 0xb2 and tile < 0xb6)
                        a.SpriteSfx_QueueSfx2WithPan(k, 0xb);
                    if (tile != v.sprite_E[i]) {
                        v.sprite_E[i] = tile;
                        if (tile == 0xbe) {
                            v.sprite_graphics[i] +%= 1;
                            v.sprite_delay_aux1[i] = 24;
                        }
                        v.sprite_head_dir[i] = v.sprite_D[i];
                        SomariaPlatformAndPipe_HandleMovement(k);
                        SomariaPlatform_HandleDrag(k);
                    }
                }
                a.Sprite_MoveXY(k);
                const x = a.Sprite_GetX(k) -% 8;
                const y = a.Sprite_GetY(k) -% 14;
                if (x != v.link_x_coord.*)
                    v.link_x_coord.* +%= if (x < v.link_x_coord.*) @as(u16, 0xffff) else 1;
                if (y != v.link_y_coord.*)
                    v.link_y_coord.* +%= if (y < v.link_y_coord.*) @as(u16, 0xffff) else 1;
                v.sprite_subtype2[i] -%= 1;
                if (v.sprite_subtype2[i] == 0)
                    break;
            }
            v.link_x_vel.* = @as(u8, @truncate(v.link_x_coord.*)) -% v.link_x_coord_safe_return_lo.*;
            v.link_y_vel.* = @as(u8, @truncate(v.link_y_coord.*)) -% v.link_y_coord_safe_return_lo.*;
            v.link_direction_last.* = t.kPipe_Dirs[v.sprite_D[i]];
            a.Link_HandleMovingAnimation_FullLongEntry();
            a.HandleIndoorCameraAndDoors();
            a.Link_CancelDash();
        },
        5 => {
            if (v.sprite_delay_aux1[i] == 0) {
                v.flag_is_link_immobilized.* = 0;
                v.player_on_somaria_platform.* = 0;
                v.link_disable_sprite_damage.* = 0;
                v.link_visibility_status.* = 0;
                v.link_x_vel.* = 0;
                v.link_y_vel.* = 0;
                v.alt_sprite_spawned_flag[0] = 255;
                v.sprite_graphics[i] = 2;
            } else {
                Pipe_HandlePlayerMovement(t.kPipe_Dirs[v.sprite_D[i] ^ 1]);
            }
        },
        else => {},
    }
}

pub export fn Faerie_HandleMovement(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_graphics[i] = @truncate(v.frame_counter.* >> 3 & 1);
    if (v.player_is_indoors.* != 0 and v.sprite_delay_aux1[i] == 0) {
        if (a.Sprite_CheckTileCollision(k) & 3 != 0) {
            v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
            v.sprite_D[i] = 0 -% v.sprite_D[i];
            v.sprite_delay_aux1[i] = 32;
        }
        if (v.sprite_wallcoll[i] & 12 != 0) {
            v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
            v.sprite_A[i] = 0 -% v.sprite_A[i];
            v.sprite_delay_aux1[i] = 32;
        }
    }
    if (v.sprite_x_vel[i] != 0) {
        if (sign8(v.sprite_x_vel[i])) {
            v.sprite_oam_flags[i] &= ~@as(u8, 0x40);
        } else {
            v.sprite_oam_flags[i] |= 0x40;
        }
    }
    a.Sprite_MoveXY(k);
    if (v.frame_counter.* & 63 == 0) {
        const x = (v.link_x_coord.* & 0xff00) +% @as(u16, a.GetRandomNumber());
        const y = (v.link_y_coord.* & 0xff00) +% @as(u16, a.GetRandomNumber());
        const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 16);
        v.sprite_A[i] = pt.y;
        v.sprite_D[i] = pt.x;
    }
    if (v.frame_counter.* & 15 == 0) {
        // The sum is done in ints and shifted arithmetically before narrowing.
        const sy: i32 = @as(i32, @as(i8, @bitCast(v.sprite_A[i]))) +
            @as(i32, @as(i8, @bitCast(v.sprite_y_vel[i])));
        v.sprite_y_vel[i] = @truncate(@as(u32, @bitCast(sy >> 1)));
        const sx: i32 = @as(i32, @as(i8, @bitCast(v.sprite_D[i]))) +
            @as(i32, @as(i8, @bitCast(v.sprite_x_vel[i])));
        v.sprite_x_vel[i] = @truncate(@as(u32, @bitCast(sx >> 1)));
    }
    a.Sprite_MoveZ(k);
    v.sprite_z_vel[i] +%= if (a.GetRandomNumber() & 1 != 0) @as(u8, 0xff) else 1;
    if (v.sprite_z[i] < 8) {
        v.sprite_z[i] = 8;
        v.sprite_z_vel[i] = 5;
    } else if (v.sprite_z[i] >= 24) {
        v.sprite_z[i] = 24;
        v.sprite_z_vel[i] = @bitCast(@as(i8, -5));
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part12.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_BA_Whirlpool(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (@as(u8, @truncate(v.overworld_screen_index.*)) == 0x1b) {
        var info: PrepOamCoordsRet = undefined;
        a.Sprite_PrepOamCoord(k, &info);
        if (a.Sprite_ReturnIfInactive(k))
            return;
        const x = v.cur_sprite_x.* -% v.link_x_coord.* +% 0x40;
        const y = v.cur_sprite_y.* -% v.link_y_coord.* +% 0xf;
        if (x < 0x51 and y < 0x12) {
            v.submodule_index.* = 35;
            v.link_triggered_by_whirlpool_sprite.* = 1;
            v.subsubmodule_index.* = 0;
            v.link_actual_vel_y.* = 0;
            v.link_actual_vel_x.* = 0;
            v.link_player_handler_state.* = 20;
            v.last_light_vs_dark_world.* = @truncate(v.overworld_screen_index.* & 0x40);
        }
    } else {
        v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) |
            t.kWhirlpool_OamFlags[v.frame_counter.* >> 3 & 3];
        _ = a.Oam_AllocateFromRegionB(4);
        v.cur_sprite_x.* -%= 5;
        a.SpriteDraw_SingleLarge(k);
        if (a.Sprite_ReturnIfInactive(k))
            return;
        if (a.Sprite_CheckDamageToLink_same_layer(k)) {
            if (v.sprite_A[i] == 0) {
                v.submodule_index.* = 46;
                v.subsubmodule_index.* = 0;
            }
        } else {
            v.sprite_A[i] = 0;
        }
    }
}

pub export fn Sprite_BB_Shopkeeper(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => Shopkeeper_StandardClerk(k),
        1 => ChestGameGuy(k),
        2 => NiceThiefWithGift(k),
        3 => MiniChestGameGuy(k),
        4 => LostWoodsChestGameGuy(k),
        5, 6 => a.NiceThiefUnderRock(k),
        7 => a.ShopItem_RedPotion150(k),
        8 => a.ShopItem_FighterShield(k),
        9 => a.ShopItem_FireShield(k),
        10 => a.ShopItem_Heart(k),
        11 => a.ShopItem_Arrows(k),
        12 => a.ShopItem_Bombs(k),
        13 => a.ShopItem_Bee(k),
        else => {},
    }
}

pub export fn Shopkeeper_StandardClerk(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.is_in_dark_world.* != 0) {
        a.Oam_AllocateDeferToPlayer(k);
        a.SpriteDraw_SingleLarge(k);
        if (a.Sprite_ReturnIfInactive(k))
            return;
        v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 63) |
            @as(u8, @truncate(v.frame_counter.* << 3 & 64));
    } else {
        v.sprite_oam_flags[i] = 7;
        a.Shopkeeper_Draw(k);
        if (a.Sprite_ReturnIfInactive(k))
            return;
        v.sprite_graphics[i] = @truncate(v.frame_counter.* >> 4 & 1);
    }
    a.Sprite_BehaveAsBarrier(k);
    const msg: u16 = if (v.is_in_dark_world.* == 0) 0x165 else 0x15f;
    _ = a.Sprite_ShowSolicitedMessage(k, msg);
    if (v.sprite_ai_state[i] == 0 and (v.cur_sprite_y.* +% 0x60) >= v.link_y_coord.*) {
        a.Sprite_ShowMessageUnconditional(msg);
        v.sprite_ai_state[i] = 1;
    }
}

pub export fn ChestGameGuy(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Oam_AllocateDeferToPlayer(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 63) |
        @as(u8, @truncate(v.frame_counter.* << 3 & 64));
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.minigame_credits.* -% 1 >= 2 and
                (a.Sprite_ShowSolicitedMessage(k, 0x160) & 0x100) != 0)
                v.sprite_ai_state[i] = 1;
        },
        1 => {
            if (v.choice_in_multiselect_box.* == 0 and a.ShopItem_HandleCost(30)) {
                v.minigame_credits.* = 2;
                a.Sprite_ShowMessageUnconditional(0x164);
                v.sprite_ai_state[i] = 2;
            } else {
                a.Sprite_ShowMessageUnconditional(0x161);
                v.sprite_ai_state[i] = 0;
            }
        },
        2 => {
            _ = a.Sprite_ShowSolicitedMessage(k, if (v.minigame_credits.* == 0) 0x163 else 0x17f);
        },
        else => {},
    }
}

pub export fn NiceThiefWithGift(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.NiceThief_Animate(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            if ((a.Sprite_ShowSolicitedMessage(k, 0x176) & 0x100) != 0)
                v.sprite_ai_state[i] = 1;
        },
        1 => {
            if (v.dung_savegame_state_bits.* & 0x4000 == 0) {
                v.dung_savegame_state_bits.* |= 0x4000;
                v.sprite_ai_state[i] = 2;
                a.ShopItem_HandleReceipt(k, 0x46);
            } else {
                v.sprite_ai_state[i] = 0;
            }
        },
        2 => v.sprite_ai_state[i] = 0,
        else => {},
    }
}

pub export fn MiniChestGameGuy(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
    v.sprite_graphics[i] = 0;
    a.MazeGameGuy_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.minigame_credits.* -% 1 >= 2 and
                (a.Sprite_ShowSolicitedMessage(k, 0x17e) & 0x100) != 0)
                v.sprite_ai_state[i] = 1;
        },
        1 => {
            if (v.choice_in_multiselect_box.* == 0 and a.ShopItem_HandleCost(20)) {
                v.minigame_credits.* = 1;
                a.Sprite_ShowMessageUnconditional(0x17f);
                v.sprite_ai_state[i] = 2;
            } else {
                a.Sprite_ShowMessageUnconditional(0x180);
                v.sprite_ai_state[i] = 0;
            }
        },
        2 => {
            _ = a.Sprite_ShowSolicitedMessage(k, if (v.minigame_credits.* == 0) 0x163 else 0x17f);
        },
        else => {},
    }
}

pub export fn LostWoodsChestGameGuy(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.NiceThief_Animate(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.minigame_credits.* -% 1 >= 2 and
                (a.Sprite_ShowSolicitedMessage(k, 0x181) & 0x100) != 0)
                v.sprite_ai_state[i] = 1;
        },
        1 => {
            if (v.choice_in_multiselect_box.* == 0 and a.ShopItem_HandleCost(100)) {
                v.minigame_credits.* = 1;
                a.Sprite_ShowMessageUnconditional(0x17f);
                v.sprite_ai_state[i] = 2;
            } else {
                a.Sprite_ShowMessageUnconditional(0x180);
                v.sprite_ai_state[i] = 0;
            }
        },
        2 => {
            _ = a.Sprite_ShowSolicitedMessage(k, if (v.minigame_credits.* == 0) 0x163 else 0x17f);
        },
        else => {},
    }
}

pub export fn Sprite_B5_BombShop(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => Sprite_BombShop_Clerk(k),
        1 => Sprite_BombShop_Bomb(k),
        2 => Sprite_BombShop_SuperBomb(k),
        3 => a.Sprite_BombShop_Huff(k),
        else => {},
    }
}

pub export fn Sprite_BombShop_Clerk(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.BombShopEntity_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_delay_main[i] == 0) {
        const j: usize = v.sprite_E[i];
        v.sprite_E[i] = @truncate((j + 1) & 7);
        v.sprite_delay_main[i] = t.kBombShopGuy_Delay[j];
        v.sprite_graphics[i] = t.kBombShopGuy_Gfx[j];
        if (v.sprite_graphics[i] == 0) {
            a.SpriteSfx_QueueSfx3WithPan(k, 0x11);
            a.BombShop_ClerkExhalation(k);
        } else {
            a.SpriteSfx_QueueSfx3WithPan(k, 0x12);
        }
    }
    const flag = (v.link_has_crystals.* & 5) == 5 and (v.sram_progress_indicator_3.* & 32) != 0;
    _ = a.Sprite_ShowSolicitedMessage(k, if (flag) 0x118 else 0x117);
    a.Sprite_BehaveAsBarrier(k);
}

pub export fn Sprite_BombShop_Bomb(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.BombShopEntity_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (!a.ShopItem_CheckForAPress(k))
        return;

    if (v.link_item_bombs.* != hud_tables.kMaxBombsForLevel[v.link_bomb_upgrades.*]) {
        if (!a.ShopItem_HandleCost(100)) {
            a.Sprite_ShowMessageUnconditional(0x17c);
            a.ShopItem_PlayBeep(k);
        } else {
            v.link_bomb_filler.* = 27;
            v.sprite_state[i] = 0;
            a.Sprite_ShowMessageUnconditional(0x119);
            a.ShopItem_HandleReceipt(k, 0x28);
        }
    } else {
        a.Sprite_ShowMessageUnconditional(0x16e);
        a.ShopItem_PlayBeep(k);
    }
}

pub export fn Sprite_BombShop_SuperBomb(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.BombShopEntity_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (a.ShopItem_CheckForAPress(k)) {
        if (!a.ShopItem_HandleCost(100)) {
            a.Sprite_ShowMessageUnconditional(0x17c);
            a.ShopItem_PlayBeep(k);
        } else {
            v.follower_indicator.* = 13;
            a.LoadFollowerGraphics();
            a.Sprite_BecomeFollower(k);
            v.sprite_state[i] = 0;
            a.Sprite_ShowMessageUnconditional(0x11a);
        }
    }
}

pub export fn Sprite_B4_PurpleChest(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_ai_state[i] == 0) {
        if ((a.Sprite_ShowMessageOnContact(k, 0x116) & 0x100) != 0 and v.follower_indicator.* == 0)
            v.sprite_ai_state[i] = 1;
    } else {
        v.sprite_state[i] = 0;
        v.follower_indicator.* = 12;
        a.LoadFollowerGraphics();
        a.Sprite_BecomeFollower(k);
    }
}

pub export fn Sprite_B7_BlindMaiden(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.CrystalMaiden_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_TrackBodyToHead(k);
    v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
    if (v.sprite_ai_state[i] == 0) {
        if ((a.Sprite_ShowMessageOnContact(k, 0x122) & 0x100) != 0)
            v.sprite_ai_state[i] = 1;
    } else {
        v.sprite_state[i] = 0;
        v.follower_indicator.* = 6;
        a.LoadFollowerGraphics();
        a.Sprite_BecomeFollower(k);
    }
}

pub export fn OldMan_RevertToSprite(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: a.SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xAD, &info);
    const ju = ix(j);
    v.sprite_D[ju] = v.tagalong_layerbits[i] & 3;
    v.sprite_head_dir[ju] = v.sprite_D[ju];
    a.Sprite_SetY(j, (@as(u16, v.tagalong_y_lo[i]) | (@as(u16, v.tagalong_y_hi[i]) << 8)) +% 2);
    a.Sprite_SetX(j, (@as(u16, v.tagalong_x_lo[i]) | (@as(u16, v.tagalong_x_hi[i]) << 8)) +% 2);
    v.sprite_floor[ju] = v.link_is_on_lower_level.*;
    v.sprite_ignore_projectile[ju] = 1;
    v.sprite_subtype2[ju] = 1;
    a.OldMan_EnableCutscene();
    v.follower_indicator.* = 0;
    v.link_speed_setting.* = 0;
}

// ---------------------------------------------------------------------------
// from sprite_main_part13.zig
// ---------------------------------------------------------------------------
/// misc.h keeps this a `static inline` with no linkable symbol, and it searches
/// *backwards*.

pub export fn SpriteModule_Initialize(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpritePrep_LoadProperties(k);
    v.sprite_state[i] +%= 1;
    t.kSpritePrep_Main[v.sprite_type[i]].?(k);
}

pub export fn SpritePrep_ThrowableScenery(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn SpritePrep_SwitchFacingUp(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn SpritePrep_DoNothingA(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn SpritePrep_DoNothingC(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn SpritePrep_IgnoreProjectiles(k: c_int) callconv(.c) void {
    v.sprite_ignore_projectile[ix(k)] +%= 1;
}

pub export fn SpritePrep_Mantle(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_y_lo[i] +%= 3;
    v.sprite_x_lo[i] +%= 8;
}

pub export fn SpritePrep_Switch(k: c_int) callconv(.c) void {
    const room: u8 = @truncate(v.dungeon_room_index2.*);
    if (room == 0xce or room == 4 or room == 0x3f)
        v.sprite_oam_flags[ix(k)] = 0xD;
}

pub export fn SpritePrep_Snitch_bounce_1(k: c_int) callconv(.c) void {
    a.SpritePrep_Snitches(k);
}

pub export fn SpritePrep_Rat(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.is_in_dark_world.*;
    v.sprite_bump_damage[i] = t.kSpriteRat_BumpDamage[j];
    v.sprite_health[i] = t.kSpriteRat_Health[j];
}

pub export fn SpritePrep_Keese(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.is_in_dark_world.*;
    v.sprite_bump_damage[i] = t.kSpriteKeese_BumpDamage[j];
    v.sprite_health[i] = t.kSpriteKeese_Health[j];
    v.sprite_flags5[i] = t.kSpriteKeese_Flags5[j];
}

pub export fn SpritePrep_Rope(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.is_in_dark_world.*;
    v.sprite_bump_damage[i] = t.kSpriteRope_BumpDamage[j];
    v.sprite_health[i] = t.kSpriteRope_Health[j];
    v.sprite_flags5[i] = t.kSpriteRope_Flags5[j];
}

pub export fn SpritePrep_Raven(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.is_in_dark_world.*;
    v.sprite_bump_damage[i] = t.kSpriteRaven_BumpDamage[j];
    v.sprite_health[i] = t.kSpriteRaven_Health[j];
    v.sprite_flags5[i] = t.kSpriteRaven_Flags5[j];
    v.sprite_z[i] = 0;
    v.sprite_A[i] = (v.sprite_x_lo[i] & 16) >> 4;
    v.sprite_subtype[i] = 254;
}

pub export fn SpritePrep_Vulture(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_z[i] = 0;
    v.sprite_A[i] = (v.sprite_x_lo[i] & 16) >> 4;
    v.sprite_subtype[i] = 254;
}

pub export fn SpritePrep_Poe(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_z[i] = 12;
    v.sprite_subtype[i] = 254;
}

pub export fn SpritePrep_Bomber(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_z[i] = 16;
    v.sprite_subtype[i] = 254;
}

pub export fn SpritePrep_Swamola(k: c_int) callconv(.c) void {
    a.SpritePrep_Swamola_InitializeSegments(k);
    a.SpritePrep_Kyameron(k);
}

pub export fn SpritePrep_Blind(k: c_int) callconv(.c) void {
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    a.SpritePrep_Blind_PrepareBattle(k);
}

pub export fn SpritePrep_Ganon(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    a.Ganon_HandleAnimation_Idle(k);
    v.sprite_delay_main[i] = 128;
    v.sprite_room[i] = 2;
    v.music_control.* = 0x1e;
}

pub export fn SpritePrep_Pokey(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_A[i] = 3;
    v.sprite_B[i] = 8;
    const j: usize = a.GetRandomNumber() & 3;
    v.sprite_x_vel[i] = @bitCast(t.kHokbok_InitXvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kHokbok_InitYvel[j]);
}

pub export fn SpritePrep_MiniVitreous(k: c_int) callconv(.c) void {
    _ = a.Sprite_ReturnIfBossFinished(k);
}

pub export fn SpritePrep_Gibo(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_z[i] = 16;
    v.sprite_G[i] = 8;
}

pub export fn SpritePrep_Octoballoon(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_delay_main[i] = t.kSprite_Octoballoon_Delay[i & 3];
}

pub export fn SpritePrep_AgahnimsBarrier(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.save_ow_event_info[@as(u8, @truncate(v.overworld_screen_index.*))] & 0x40 != 0)
        v.sprite_graphics[i] = 4;
    a.SpritePrep_MoveDown_8px_Right8px(k);
    v.sprite_y_lo[i] -%= 12;
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_Catfish(k: c_int) callconv(.c) void {
    a.SpritePrep_MoveDown_8px_Right8px(k);
    v.sprite_y_lo[ix(k)] -%= 12;
    SpritePrep_IgnoreProjectiles(k);
}

pub export fn SpritePrep_CutsceneAgahnim(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.dung_savegame_state_bits.* & 0x4000 != 0) {
        v.sprite_state[i] = 0;
    } else {
        a.CutsceneAgahnim_SpawnZeldaOnAltar(k);
        v.sprite_ignore_projectile[i] +%= 1;
    }
}

pub export fn SpritePrep_Vitreous(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    a.SpritePrep_MoveDown_8px_Right8px(k);
    v.sprite_y_lo[i] -%= 16;
    a.Vitreous_SpawnSmallerEyes(k);
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_BlindMaiden(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.save_dung_info[0xac] & 0x800 == 0) {
        v.sprite_ignore_projectile[i] +%= 1;
        if (v.follower_indicator.* != 6) {
            v.follower_indicator.* = 6;
            v.follower_dropped.* = 0;
            v.tagalong_var5.* = 0;
            a.LoadFollowerGraphics();
            a.Follower_Initialize();
            v.follower_indicator.* = 0;
            return;
        }
    }
    v.sprite_state[i] = 0;
}

pub export fn SpritePrep_BombShoppe(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xb5, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetX(j, info.r0_x -% 24);
        a.Sprite_SetY(j, info.r2_y -% 24);
        v.sprite_subtype2[ju] = 1;
        v.sprite_ignore_projectile[ju] = 1;
    }
    if ((v.link_has_crystals.* & 5) == 5 and (v.sram_progress_indicator_3.* & 32) != 0) {
        const j2 = a.Sprite_SpawnDynamically(k, 0xb5, &info);
        if (j2 >= 0) {
            const ju = ix(j2);
            a.Sprite_SetX(j2, info.r0_x -% 56);
            a.Sprite_SetY(j2, info.r2_y -% 24);
            v.sprite_subtype2[ju] = 2;
            v.sprite_ignore_projectile[ju] = 2;
        }
    }
}

pub export fn SpritePrep_BullyAndVictim(k: c_int) callconv(.c) void {
    a.SpawnBully(k);
    v.sprite_ignore_projectile[ix(k)] +%= 1;
}

pub export fn SpritePrep_PurpleChest(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.follower_indicator.* != 12 and
        (v.sram_progress_indicator_3.* & 16) == 0 and
        (v.sram_progress_indicator_3.* & 32) != 0)
    {
        v.sprite_ignore_projectile[i] +%= 1;
    } else {
        v.sprite_state[i] = 0;
    }
}

pub export fn SpritePrep_Smithy(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    if (v.savegame_is_darkworld.* & 64 != 0) {
        if ((v.sram_progress_indicator_3.* & 32) != 0 or v.follower_indicator.* != 0) {
            v.sprite_state[i] = 0;
        } else {
            v.sprite_subtype2[i] = 2;
        }
        return;
    }
    a.Smithy_SpawnDumbBarrierSprite(k);
    if (v.sram_progress_indicator_3.* & 32 == 0) {
        v.sprite_x_lo[i] +%= 2;
        v.sprite_y_lo[i] -%= 3;
        return;
    }
    v.sprite_x_lo[i] +%= 2;
    v.sprite_y_lo[i] -%= 3;
    const j = a.Smithy_SpawnDwarfPal(k);
    a.Smithy_SpawnDumbBarrierSprite(j);
    const ju = ix(j);
    v.sprite_E[ju] = @truncate(@as(u32, @bitCast(k)));
    v.sprite_E[i] = @truncate(@as(u32, @bitCast(j)));

    if (v.sram_progress_indicator_3.* & 0x80 != 0) {
        v.sprite_ai_state[i] = 5;
        v.sprite_ai_state[ju] = 5;
    }
}

pub export fn SpritePrep_Babasu(k: c_int) callconv(.c) void {
    a.SpritePrep_MoveDown_8px(k);
    SpritePrep_Zoro(k);
}

pub export fn SpritePrep_Zoro(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_D[i] = (v.sprite_type[i] -% 0x9c) << 1;
    v.sprite_graphics[i] -%= 1;
}

pub export fn SpritePrep_LaserEye_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    const ty = v.sprite_type[i];
    v.sprite_D[i] = ty -% 0x95;
    if (ty >= 0x97) {
        v.sprite_x_lo[i] +%= 8;
        v.sprite_head_dir[i] = (v.sprite_x_lo[i] & 16) ^ 16;
        if (v.sprite_head_dir[i] == 0)
            v.sprite_y_lo[i] +%= if (ty & 1 != 0) @as(u8, 0xf8) else 8;
    } else {
        v.sprite_head_dir[i] = v.sprite_y_lo[i] & 16;
        if (v.sprite_head_dir[i] == 0)
            v.sprite_x_lo[i] +%= if (ty & 1 != 0) @as(u8, 0xf8) else 8;
    }
}

pub export fn SpritePrep_Popo(k: c_int) callconv(.c) void {
    v.sprite_B[ix(k)] = 7;
}

pub export fn SpritePrep_Popo2(k: c_int) callconv(.c) void {
    v.sprite_B[ix(k)] = 15;
}

pub export fn SpritePrep_Statue(k: c_int) callconv(.c) void {
    v.sprite_y_lo[ix(k)] +%= 7;
}

pub export fn SpritePrep_Bari(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_z[i] = 6;
    if (@as(u8, @truncate(v.dungeon_room_index2.*)) == 206)
        v.sprite_C[i] -%= 1;
    v.sprite_delay_aux1[i] = (a.GetRandomNumber() & 63) +% 128;
}

pub export fn SpritePrep_GreenStalfos(k: c_int) callconv(.c) void {
    v.sprite_z[ix(k)] = 9;
}

pub export fn SpritePrep_WaterLever(k: c_int) callconv(.c) void {
    v.sprite_y_lo[ix(k)] +%= 5;
}

pub export fn SpritePrep_FireDebirando(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_type[i] = 0x63;
    a.SpritePrep_LoadProperties(k);
    v.sprite_G[i] -%= 1;
    SpritePrep_DebirandoPit(k);
}

pub export fn SpritePrep_DebirandoPit(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_G[i] +%= 1;
    v.sprite_delay_main[i] = 0;
    v.sprite_graphics[i] = 6;
    SpritePrep_IgnoreProjectiles(k);
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x64, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_delay_main[ju] = 96;
        v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
        v.sprite_G[ju] = v.sprite_G[i];
        v.sprite_oam_flags[ju] = t.kDebirando_OamFlags[v.sprite_G[ju]];
    }
}

pub export fn SpritePrep_WeakGuard(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_D[i] = a.GetRandomNumber() & 3;
    v.sprite_head_dir[i] = v.sprite_D[i];
    v.sprite_delay_main[i] = 16;
}

pub export fn SpritePrep_WallCannon(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_D[i] = v.sprite_type[i] -% 0x66;
    v.sprite_A[i] = v.sprite_D[i] & 2;
}

pub export fn SpritePrep_ArrowGame_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.byte_7E0B88.* = 0;
    v.sprite_y_lo[i] -%= 9;
    var n: usize = 7;
    while (n != 0) : (n -= 1) {
        v.sprite_type[n] = 0x65;
        v.sprite_state[n] = 9;
        a.SpritePrep_LoadProperties(@intCast(n));
        v.sprite_x_hi[n] = @truncate(v.link_x_coord.* >> 8);
        v.sprite_x_lo[n] = t.kArcheryGameGuy_X[n];
        v.sprite_y_hi[n] = @truncate(v.link_y_coord.* >> 8);
        v.sprite_y_lo[n] = t.kArcheryGameGuy_Y[n];
        v.sprite_A[n] = t.kArcheryGameGuy_A[n];
        const j: usize = t.kArcheryGameGuy_A[n] -% 1;
        v.sprite_graphics[n] = @truncate(j);
        v.sprite_x_vel[n] = @bitCast(t.kArcheryGameGuy_Xvel[j]);
        v.sprite_flags4[n] = t.kArcheryGameGuy_Flags4[j];
        v.sprite_oam_flags[n] = 13;
        v.sprite_floor[n] = v.link_is_on_lower_level.*;
        v.sprite_subtype2[n] = a.GetRandomNumber();
    }
    v.sprite_ignore_projectile[i] +%= 1;
    v.sprite_subtype[i] = v.link_num_arrows.*;
}

pub export fn SpritePrep_HauntedGroveAnimal(k: c_int) callconv(.c) void {
    v.sprite_D[ix(k)] = a.Sprite_IsRightOfLink(k).a;
    SpritePrep_HauntedGroveOstritch(k);
}

pub export fn SpritePrep_HauntedGroveOstritch(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.link_item_flute.* >= 2)
        v.sprite_state[i] = 0;
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_DiggingGameGuy_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.link_y_coord.* < a.Sprite_GetY(k)) {
        v.sprite_ai_state[i] = 5;
        v.sprite_x_lo[i] -%= 9;
        v.sprite_graphics[i] = 1;
    }
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_ThievesTownGrate(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.save_ow_event_info[0x58] & 0x20 != 0)
        v.sprite_state[i] = 0;
    v.sprite_ignore_projectile[i] +%= 1;
    a.Sprite_SetX(k, a.Sprite_GetX(k) -% 8);
}

pub export fn SpritePrep_RupeePull(k: c_int) callconv(.c) void {
    v.sprite_ignore_projectile[ix(k)] +%= 1;
    a.Sprite_SetX(k, a.Sprite_GetX(k) -% 8);
}

pub export fn SpritePrep_Shopkeeper(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    v.sprite_flags2[i] |= 2;
    v.sprite_oam_flags[i] |= 12;
    v.sprite_flags3[i] |= 16;
    const room: u8 = @truncate(v.dungeon_room_index.*);
    switch (FindInByteArray(&t.kShopKeeperWhere, room, 13)) {
        0 => {
            a.ShopKeeper_SpawnShopItem(k, 0, 7);
            a.ShopKeeper_SpawnShopItem(k, 1, 8);
            a.ShopKeeper_SpawnShopItem(k, 2, 12);
        },
        1 => {
            a.ShopKeeper_SpawnShopItem(k, 0, 9);
            a.ShopKeeper_SpawnShopItem(k, 1, 13);
            a.ShopKeeper_SpawnShopItem(k, 2, 11);
        },
        2 => {
            v.sprite_subtype2[i] = 4;
            v.minigame_credits.* = 0xff;
        },
        3 => {
            v.sprite_subtype2[i] = 1;
            v.sprite_graphics[i] = 1;
            v.minigame_credits.* = 0xff;
        },
        4 => {
            v.sprite_subtype2[i] = 3;
            v.minigame_credits.* = 0xff;
        },
        5, 7, 8 => {
            a.ShopKeeper_SpawnShopItem(k, 0, 7);
            a.ShopKeeper_SpawnShopItem(k, 1, 10);
            a.ShopKeeper_SpawnShopItem(k, 2, 12);
        },
        6, 9, 12 => v.sprite_subtype2[i] = 2,
        10 => v.sprite_subtype2[i] = 5,
        11 => v.sprite_subtype2[i] = 6,
        else => {},
    }
}

pub export fn SpritePrep_Storyteller(k: c_int) callconv(.c) void {
    const i = ix(k);
    var r = FindInByteArray(&t.kStoryTellerRooms, @truncate(v.dungeon_room_index.*), 5);
    if (r == 0 and v.sprite_x_hi[i] & 1 != 0)
        r = 1;
    v.sprite_subtype2[i] = @truncate(@as(u32, @bitCast(r)));
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn Sprite_BookOfMudora(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_CheckDamageToLink_same_layer(k))
        v.sprite_ai_state[i] = 3;
    a.Sprite_MoveXY(k);
    v.sprite_z_vel[i] -%= 1;
    a.Sprite_MoveZ(k);
    if (sign8(v.sprite_z[i])) {
        v.sprite_y_vel[i] = 0;
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = (0 -% v.sprite_z_vel[i]) >> 2;
        if (v.sprite_z_vel[i] & 254 != 0)
            a.SpriteSfx_QueueSfx2WithPan(k, 0x21);
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // wait for dash
            if (v.link_direction_facing.* == 0 and
                v.cur_sprite_x.* -% v.link_x_coord.* +% 39 < 47 and
                v.cur_sprite_y.* -% v.link_y_coord.* +% 40 < 46 and
                (v.bg1_x_offset.* | v.bg1_y_offset.*) != 0)
                v.sprite_ai_state[i] = 1;
        },
        1 => { // begin falling
            v.sprite_z_vel[i] = 32;
            v.sprite_y_vel[i] = @bitCast(@as(i8, -5));
            v.sound_effect_2.* = 27;
            v.sprite_ai_state[i] = 2;
        },
        2 => { // falling
            if (v.sprite_z[i] == 0)
                v.sprite_floor[i] = v.link_is_on_lower_level.*;
        },
        3 => { // give to player
            a.Link_CancelDash();
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(0x1d, 0);
            v.sprite_state[i] = 0;
        },
        else => {},
    }
}

pub export fn LumberjackTree_SpawnLeaves(k: c_int) callconv(.c) c_int {
    const i = ix(k);
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x3B, &info);
    const ju = ix(j);
    v.sprite_graphics[ju] = 2;
    v.sprite_z_vel[ju] = v.sprite_z_vel[i];
    v.sprite_subtype2[ju] = 1;
    v.sprite_ai_state[ju] = 2;
    v.sprite_delay_main[ju] = 8;
    a.Sprite_SetSpawnedCoordinates(j, &info);
    return j;
}

pub export fn Sprite_TroughBoy(k: c_int) callconv(.c) void {
    const i = ix(k);
    TroughBoy_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    _ = a.Sprite_TrackBodyToHead(k);
    v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;

    if (v.savegame_map_icons_indicator.* < 3) {
        if ((a.Sprite_ShowSolicitedMessage(k, 0x147) & 0x100) != 0)
            v.savegame_map_icons_indicator.* = 2;
    } else {
        _ = a.Sprite_ShowSolicitedMessage(k, 0x148);
    }
}

pub export fn TroughBoy_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kTroughBoy_Dmd[@as(usize, v.sprite_D[ix(k)]) * 2], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn BottleMerchant_DetectFish(k: c_int) callconv(.c) void {
    const i = ix(k);
    var n: isize = 15;
    while (n >= 0) : (n -= 1) {
        const j: usize = @intCast(n);
        if (v.sprite_state[j] != 0 and v.sprite_type[j] == 0xd2) {
            var hb: SpriteHitBox = undefined;
            hb.r0_xlo = v.sprite_x_lo[i];
            hb.r8_xhi = v.sprite_x_hi[i];
            hb.r2 = 16;
            hb.r1_ylo = v.sprite_y_lo[i];
            hb.r9_yhi = v.sprite_y_hi[i];
            hb.r3 = 16;
            a.Sprite_SetupHitBox(@intCast(n), &hb);
            if (a.CheckIfHitBoxesOverlap(&hb))
                v.sprite_E[i] = 0x80 | @as(u8, @intCast(n));
            return;
        }
    }
}

pub export fn BottleMerchant_BuyFish(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    a.SpriteSfx_QueueSfx3WithPan(k, 0x13);
    v.tmp_counter.* = 4;
    while (true) {
        const m: usize = v.tmp_counter.*;
        const j = a.Sprite_SpawnDynamically(k, t.kBottleVendor_FishRewardType[m], &info);
        if (j < 0)
            return;
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_x_lo[ju] = @truncate(info.r0_x +% 4);
        v.sprite_stunned[ju] = 0xff;
        v.sprite_x_vel[ju] = @bitCast(t.kBottleVendor_FishRewardXv[m]);
        v.sprite_y_vel[ju] = @bitCast(t.kBottleVendor_FishRewardYv[m]);
        v.sprite_z_vel[ju] = 32;
        v.sprite_delay_aux4[ju] = 32;
        v.tmp_counter.* -%= 1;
        if (sign8(v.tmp_counter.*))
            break;
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part14.zig
// ---------------------------------------------------------------------------
pub export fn SpritePrep_Whirlpool(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    v.sprite_A[i] = 1;
}

pub export fn SpritePrep_Sage(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    if (@as(u8, @truncate(v.dungeon_room_index.*)) == 10) {
        v.sprite_subtype2[i] +%= 1;
        v.sprite_oam_flags[i] = 11;
    }
}

pub export fn SpritePrep_BonkItem(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.player_is_indoors.* == 0) {
        v.sprite_graphics[i] = 2;
        return;
    }
    v.sprite_floor[i] = 2;
    if (v.dungeon_room_index.* == 0x107) {
        if (v.link_item_book_of_mudora.* != 0) {
            v.sprite_state[i] = 0;
        } else {
            a.DecodeAnimatedSpriteTile_variable(0xe);
        }
    } else {
        const j: usize = v.byte_7E0B9B.*;
        v.byte_7E0B9B.* +%= 1;
        v.sprite_die_action[i] = @truncate(j);
        if (v.dung_savegame_state_bits.* & t.kDashItemMask[j] != 0)
            v.sprite_state[i] = 0;
        v.sprite_graphics[i] +%= 1;
        v.sprite_oam_flags[i] = 8;
        v.sprite_flags3[i] |= 0x20;
    }
}

pub export fn SpritePrep_Kiki(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    if (v.save_ow_event_info[@as(u8, @truncate(v.overworld_screen_index.*))] & 0x20 != 0)
        v.sprite_state[i] = 0;
}

pub export fn SpritePrep_Locksmith(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    if (v.follower_indicator.* == 9) {
        v.sprite_state[i] = 0;
        return;
    }
    if (v.follower_indicator.* == 12)
        v.sprite_ai_state[i] = 2;
    if (v.sram_progress_indicator_3.* & 0x10 != 0)
        v.sprite_ai_state[i] = 4;
}

pub export fn SpritePrep_SickKid(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.link_item_bug_net.* != 0)
        v.sprite_ai_state[i] = 3;
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_Tektite(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.sprite_x_lo[i] >> 4 & 1;
    v.sprite_A[i] = @truncate(j);
    v.sprite_oam_flags[i] = t.kGanonHelpers_OamFlags[j];
    v.sprite_health[i] = t.kGanonHelpers_Health[j];
    v.sprite_bump_damage[i] = t.kGanonHelpers_BumpDamage[j];
    a.Sprite_ApplySpeedTowardsLink(k, 16);
    v.sprite_z_vel[i] = 32;
    v.sprite_ai_state[i] +%= 1;
}

pub export fn SpritePrep_BigFairy(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_z[i] = 24;
    a.SpritePrep_MoveDown_8px_Right8px(k);
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_MrsSahasrahla(k: c_int) callconv(.c) void {
    v.sprite_y_lo[ix(k)] +%= 8;
    SpritePrep_MagicBat(k);
}

pub export fn SpritePrep_MagicBat(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_lo[i] +%= 8;
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_FortuneTeller(k: c_int) callconv(.c) void {
    a.SpritePrep_IncrXYLow8(k);
    v.sprite_ignore_projectile[ix(k)] +%= 1;
}

pub export fn SpritePrep_FairyPond(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.sprite_x_lo[i] >> 4 & 1;
    v.sprite_A[i] = @truncate(j);
    v.sprite_oam_flags[i] = t.kLeever_OamFlags[j];
}

pub export fn SpritePrep_Hobo(k: c_int) callconv(.c) void {
    var n: usize = 15;
    while (n != 0) : (n -= 1)
        a.SpritePrep_Hobo_SpawnSmoke(k);
    n = 15;
    while (n != 0) : (n -= 1) {
        if (v.sprite_type[n] == 0x2b)
            v.sprite_state[n] = 0;
    }
    a.SpritePrep_Hobo_SpawnFire(k);
    if (v.sram_progress_indicator_3.* & 1 != 0)
        v.sprite_ai_state[0] = 3;
    v.sprite_ignore_projectile[0] = 1;
}

pub export fn SpritePrep_MasterSword(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_lo[i] +%= 6;
    v.sprite_y_lo[i] +%= 6;
}

pub export fn SpritePrep_Roller_HorizontalRightFirst(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ai_state[i] = (~v.sprite_x_lo[i] & 16) >> 4;
    if (v.sprite_ai_state[i] != 0)
        v.sprite_flags4[i] +%= 1;
    v.sprite_D[i] = 0;
}

pub export fn SpritePrep_RollerLeftRight(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ai_state[i] = (~v.sprite_x_lo[i] & 16) >> 4;
    if (v.sprite_ai_state[i] != 0)
        v.sprite_flags4[i] +%= 1;
    v.sprite_D[i] = 1;
}

pub export fn SpritePrep_Roller_VerticalDownFirst(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ai_state[i] = (v.sprite_y_lo[i] & 16) >> 4;
    if (v.sprite_ai_state[i] != 0)
        v.sprite_flags4[i] +%= 1;
    v.sprite_D[i] = 2;
}

pub export fn SpritePrep_RollerUpDown(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ai_state[i] = (v.sprite_y_lo[i] & 16) >> 4;
    if (v.sprite_ai_state[i] != 0)
        v.sprite_flags4[i] +%= 1;
    v.sprite_D[i] = 3;
}

pub export fn SpritePrep_Kodongo(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_lo[i] +%= 4;
    a.Sprite_SetY(k, a.Sprite_GetY(k) -% 5);
    v.sprite_subtype[i] -%= 1;
}

pub export fn SpritePrep_Spark(k: c_int) callconv(.c) void {
    v.sprite_subtype[ix(k)] -%= 1;
}

pub export fn SpritePrep_LostWoodsBird(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_z_vel[i] = (a.GetRandomNumber() & 0x1f) -% 0x10;
    v.sprite_z[i] = 64;
    SpritePrep_LostWoodsSquirrel(k);
}

pub export fn SpritePrep_LostWoodsSquirrel(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_vel[i] = if (a.Sprite_IsRightOfLink(k).a != 0) @as(u8, @bitCast(@as(i8, -16))) else 16;
    v.sprite_y_vel[i] = if (sign8(v.byte_7E069E[0])) 4 else @as(u8, @bitCast(@as(i8, -4)));
    v.sprite_ignore_projectile[i] = v.sprite_y_vel[i];
}

pub export fn SpritePrep_Antifairy(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_vel[i] = @bitCast(t.kBubble_Xvel[v.sprite_x_lo[i] >> 4 & 1]);
    v.sprite_y_vel[i] = @bitCast(@as(i8, -16));
}

pub export fn SpritePrep_FallingIce(k: c_int) callconv(.c) void {
    if (Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_ignore_projectile[ix(k)] +%= 1;
}

pub export fn SpritePrep_KingZora(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.link_item_flippers.* != 0) {
        v.sprite_state[i] = 0;
    } else {
        v.sprite_ignore_projectile[i] +%= 1;
    }
}

pub export fn Sprite_ReturnIfBossFinished(k: c_int) callconv(.c) bool {
    const i = ix(k);
    if (v.dung_savegame_state_bits.* & 0x8000 != 0) {
        v.sprite_state[i] = 0;
        return true;
    }
    var n: isize = 15;
    while (n >= 0) : (n -= 1) {
        const j: usize = @intCast(n);
        if (sprite_tables.kSpriteInit_BumpDamage[v.sprite_type[j]] & 0x10 == 0)
            v.sprite_state[j] = 0;
    }
    return false;
}


pub export fn SpritePrep_ArmosKnight(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_delay_main[i] = 255;
    v.byte_7E0FF8.* +%= 1;
    a.SpritePrep_MoveDown_8px_Right8px(k);
}

pub export fn SpritePrep_DesertStatue(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_A[i] = v.sprite_limit_instance.*;
    v.sprite_limit_instance.* +%= 1;
    a.SpritePrep_MoveDown_8px_Right8px(k);
    v.sprite_D[i] = if (v.sprite_x_lo[i] < 0x30) 1 else if (v.sprite_x_lo[i] < 0xe0) 3 else 2;
}

pub export fn SpritePrep_DoNothingD(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn SpritePrep_Octorok(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.is_in_dark_world.*;
    v.sprite_health[i] = t.kOctorock_Health[j];
    v.sprite_bump_damage[i] = t.kOctorock_BumpDamage[j];
    v.sprite_delay_main[i] = a.GetRandomNumber() & 127;
}

pub export fn SpritePrep_Lanmolas(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_delay_main[i] = t.kLanmola_InitDelay[i];
    v.sprite_z[i] = 0xff;
    for (0..64) |n|
        v.beamos_x_hi[i * 0x40 + n] = 0xff;
    v.garnish_y_lo[i] = 7;
}

pub export fn SpritePrep_BigSpike(k: c_int) callconv(.c) void {
    a.SpritePrep_MoveDown_8px_Right8px(k);
    SpritePrep_Kyameron(k);
}

pub export fn SpritePrep_SwimmingZora(k: c_int) callconv(.c) void {
    v.sprite_delay_main[ix(k)] = 64;
    SpritePrep_Geldman(k);
}

pub export fn SpritePrep_Geldman(k: c_int) callconv(.c) void {
    v.sprite_x_lo[ix(k)] +%= 8;
    SpritePrep_Kyameron(k);
}

pub export fn SpritePrep_Kyameron(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_A[i] = v.sprite_x_lo[i];
    v.sprite_B[i] = v.sprite_x_hi[i];
    v.sprite_C[i] = v.sprite_y_lo[i];
    v.sprite_head_dir[i] = v.sprite_y_hi[i];
}

pub export fn SpritePrep_WalkingZora(k: c_int) callconv(.c) void {
    v.sprite_delay_main[ix(k)] = 96;
}

pub export fn SpritePrep_StandardGuard(k: c_int) callconv(.c) void {
    const i = ix(k);
    const subtype = v.sprite_subtype[i];
    if (subtype != 0) {
        if ((subtype & 7) >= 5) {
            const j: usize = @as(usize, @intFromBool((subtype & 7) != 5)) * 4 + (subtype >> 3 & 3);
            v.sprite_B[i] = t.kSpriteSoldier_Tab0[j];
            v.sprite_flags[i] = (v.sprite_flags[i] & 0xf) | 0x50;
            SpritePrep_TrooperAndArcherSoldier(k);
            return;
        }
        v.sprite_D[i] = ((subtype & 7) -% 1) ^ 1;
    }
    if (v.player_is_indoors.* != 0) {
        v.sprite_flags5[i] &= ~@as(u8, 0x80);
        return;
    }
    v.sprite_ai_state[i] = 1;
    v.sprite_delay_main[i] = 112;
    v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
    v.sprite_head_dir[i] = v.sprite_D[i];
    SpritePrep_TrooperAndArcherSoldier(k);
}

pub export fn SpritePrep_TrooperAndArcherSoldier(k: c_int) callconv(.c) void {
    const i = ix(k);
    const bak0 = v.submodule_index.*;
    v.submodule_index.* = 0;
    v.sprite_defl_bits[i] = (v.sprite_defl_bits[i] >> 1) | 0x80;
    SpriteActive_Main(k);
    SpriteActive_Main(k);
    v.sprite_defl_bits[i] <<= 1;
    v.submodule_index.* = bak0;
}

pub export fn SpritePrep_TalkingTree(k: c_int) callconv(.c) void {
    v.sprite_ignore_projectile[ix(k)] +%= 1;
    a.Sprite_SetX(k, a.Sprite_GetX(k) -% 8);
    a.SpritePrep_TalkingTree_SpawnEyeball(k, 0);
    a.SpritePrep_TalkingTree_SpawnEyeball(k, 1);
}

pub export fn SpritePrep_CrystalSwitch(k: c_int) callconv(.c) void {
    v.sprite_oam_flags[ix(k)] |= t.kCrystalSwitchPal[v.orange_blue_barrier_state.* & 1];
}

pub export fn SpritePrep_FluteKid(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    v.sprite_subtype2[i] = v.savegame_is_darkworld.* >> 6 & 1;
    if (v.sprite_subtype2[i] != 0) {
        if ((v.sram_progress_indicator_3.* & 8) != 0 or v.link_item_flute.* > 2) {
            v.sprite_graphics[i] = 3;
            v.sprite_ai_state[i] = 5;
        } else if (v.link_item_flute.* == 2) {
            v.sprite_graphics[i] = 1;
        }
        v.sprite_x_lo[i] +%= 8;
        v.sprite_y_lo[i] -%= 8;
    } else {
        if (v.link_item_flute.* >= 2) {
            v.sprite_state[i] = 0;
        } else {
            v.sprite_x_lo[i] +%= 7;
        }
    }
}

pub export fn SpritePrep_MoveDown_8px(k: c_int) callconv(.c) void {
    v.sprite_y_lo[ix(k)] +%= 8;
}

pub export fn SpritePrep_Zazakku(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn SpritePrep_PedestalPlaque(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    if (@as(u8, @truncate(v.overworld_screen_index.*)) == 48)
        v.sprite_x_lo[i] +%= 7;
}

pub export fn SpritePrep_Stalfos(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_subtype[i] = v.sprite_x_lo[i] & 16;
    if (v.sprite_subtype[i] != 0)
        v.sprite_oam_flags[i] = 7;
}

pub export fn SpritePrep_KholdstareShell(k: c_int) callconv(.c) void {
    if (Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_delay_aux1[ix(k)] = 192;
    a.SpritePrep_MoveDown_8px_Right8px(k);
}

pub export fn SpritePrep_Kholdstare(k: c_int) callconv(.c) void {
    if (Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_ai_state[ix(k)] = 3;
    a.SpritePrep_IgnoreProjectiles(k);
    a.SpritePrep_MoveDown_8px_Right8px(k);
}

pub export fn SpritePrep_Bumper(k: c_int) callconv(.c) void {
    v.sprite_ignore_projectile[ix(k)] +%= 1;
    a.SpritePrep_MoveDown_8px_Right8px(k);
}

pub export fn SpritePrep_MoveDown_8px_Right8px(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_lo[i] +%= 8;
    v.sprite_y_lo[i] +%= 8;
}

pub export fn SpriteActive_Main(k: c_int) callconv(.c) void {
    t.kSpriteActiveRoutines[v.sprite_type[ix(k)]].?(k);
}

// ---------------------------------------------------------------------------
// from sprite_main_part15.zig
// ---------------------------------------------------------------------------
/// C's `(int8)x >> 2` keeps the sign.

pub export fn SpritePrep_HardhatBeetle(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = @intFromBool((v.sprite_x_lo[i] & 0x10) != 0);
    v.sprite_oam_flags[i] = t.kHardHatBeetle_OamFlags[j];
    v.sprite_health[i] = t.kHardHatBeetle_Health[j];
    v.sprite_A[i] = t.kHardHatBeetle_A[j];
    v.sprite_ai_state[i] = t.kHardHatBeetle_State[j];
    v.sprite_flags5[i] = t.kHardHatBeetle_Flags5[j];
    v.sprite_bump_damage[i] = t.kHardHatBeetle_BumpDamage[j];
}

pub export fn SpritePrep_MiniHelmasaur(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_A[i] = 16;
    v.sprite_ai_state[i] = 1;
}

pub export fn SpritePrep_Fairy(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_A[i] = a.GetRandomNumber() & 1;
    v.sprite_D[i] = v.sprite_A[i] ^ 1;
    SpritePrep_Absorbable(k);
}

pub export fn SpritePrep_Absorbable(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.player_is_indoors.* == 0) {
        v.sprite_E[i] +%= 1;
        v.sprite_ignore_projectile[i] +%= 1;
    }
}

pub export fn SpritePrep_OverworldBonkItem(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_E[i] +%= 1;
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_ShieldPickup(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn SpritePrep_NiceBee(k: c_int) callconv(.c) void {
    const i = ix(k);
    const or_bottle = v.link_bottle_info[0] | v.link_bottle_info[1] |
        v.link_bottle_info[2] | v.link_bottle_info[3];
    if (or_bottle & 8 != 0)
        v.sprite_state[i] = 0;
    v.sprite_E[i] +%= 1;
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_Agahnim(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_graphics[i] = 0;
    v.sprite_D[i] = 3;
    a.SpritePrep_MoveDown_8px_Right8px(k);
    v.sprite_oam_flags[i] = t.kAgahnim_OamFlags[v.is_in_dark_world.*];
}

pub export fn SpritePrep_DoNothingG(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn SpritePrep_DoNothingH(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn SpritePrep_FireBar(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_B[i] +%= 1;
    v.sprite_ignore_projectile[i] +%= 1;
}

pub export fn SpritePrep_Trinexx(k: c_int) callconv(.c) void {
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    a.TrinexxComponents_Initialize(k);
    var n: isize = 15;
    while (n >= 0) : (n -= 1)
        v.alt_sprite_state[@as(usize, @intCast(n))] = 0;
}

pub export fn SpritePrep_HelmasaurKing(k: c_int) callconv(.c) void {
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    a.HelmasaurKing_Initialize(k);
    @memset(v.alt_sprite_state[0..16], 0);
}

pub export fn SpritePrep_Spike(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_vel[i] = 32;
    v.sprite_y_vel[i] = @bitCast(@as(i8, -16));
    a.Sprite_MoveY(k);
    v.sprite_y_vel[i] = 0;
}

pub export fn SpritePrep_RockStal(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_y_vel[i] = @bitCast(@as(i8, -16));
    a.Sprite_MoveY(k);
    v.sprite_y_vel[i] = 0;
}

pub export fn SpritePrep_Blob(k: c_int) callconv(.c) void {
    v.sprite_graphics[ix(k)] = 4;
    a.SpritePrep_IgnoreProjectiles(k);
}

pub export fn SpritePrep_Arrghus(k: c_int) callconv(.c) void {
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_z[ix(k)] = 24;
}

pub export fn SpritePrep_Arrghi(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_subtype2[i] = a.GetRandomNumber();
    if (k == 13) {
        v.overlord_x_lo[2] = 0;
        v.overlord_x_lo[3] = 0;
        a.Arrghus_HandlePuffs(0);
    }
    v.sprite_x_lo[i] = v.overlord_x_lo[i + 7];
    v.sprite_x_hi[i] = v.overlord_y_lo[i + 7];
    v.sprite_y_lo[i] = v.overlord_gen1[i + 7];
    v.sprite_y_hi[i] = v.overlord_gen3[i + 7];
}

pub export fn SpritePrep_Mothula(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_delay_main[i] = 80;
    v.sprite_ignore_projectile[i] +%= 1;
    v.sprite_graphics[i] = 2;
    // BYTE(...)++ touches only the low byte, with no carry into the high one.
    const lo: u8 = @as(u8, @truncate(v.dung_floor_move_flags.*)) +% 1;
    v.dung_floor_move_flags.* = (v.dung_floor_move_flags.* & 0xff00) | lo;
    v.sprite_C[i] = 112;
}

pub export fn SpritePrep_BigKey(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_lo[i] +%= 8;
    v.sprite_subtype[i] = 0xff;
    SpritePrep_BigKey_load_graphics(k);
}

pub export fn SpritePrep_BigKey_load_graphics(k: c_int) callconv(.c) void {
    a.DecodeAnimatedSpriteTile_variable(0x22);
    SpritePrep_KeySetItemDrop(k);
}

pub export fn SpritePrep_SmallKey(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_subtype[i] = 255;
    v.sprite_die_action[i] = v.byte_7E0B9B.*;
    v.byte_7E0B9B.* +%= 1;
}

pub export fn SpritePrep_KeySetItemDrop(k: c_int) callconv(.c) void {
    v.sprite_die_action[ix(k)] = v.byte_7E0B9B.*;
    v.byte_7E0B9B.* +%= 1;
}

pub export fn Sprite_09_GiantMoldorm(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.GiantMoldorm_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_ai_state[i] == 3) {
        // await death
        if (v.sprite_delay_aux4[i] == 0) {
            v.sprite_state[i] = 4;
            v.sprite_A[i] = 0;
            v.sprite_delay_main[i] = 224;
        } else {
            v.sprite_hit_timer[i] = v.sprite_delay_aux4[i] | 224;
        }
        return;
    }

    _ = a.Sprite_CheckDamageFromLink(k);
    const low_health = v.sprite_health[i] < 3;
    v.sprite_subtype2[i] +%= if (low_health) 2 else 1;
    if (v.frame_counter.* & (if (low_health) @as(u8, 3) else 7) == 0)
        a.SpriteSfx_QueueSfx3WithPan(k, 0x31);

    if (v.sprite_F[i] != 0) {
        v.sprite_delay_aux2[i] = 64;
        if (v.frame_counter.* & 3 == 0)
            v.sprite_F[i] -%= 1;
        return;
    }

    if (v.link_incapacitated_timer.* == 0 and a.Sprite_CheckDamageToLink(k)) {
        a.Link_CancelDash();
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 0x28);
        v.link_actual_vel_y.* = pt.y;
        v.link_actual_vel_x.* = pt.x;
        v.link_incapacitated_timer.* = 24;
        v.sprite_delay_aux1[i] = 48;
        // For some reason they forgot to or in the sfx.
        v.sound_effect_2.* = a.Sprite_CalculateSfxPan(k) |
            (if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0) @as(u8, 0x32) else 0);
    }

    const j: usize = @as(usize, v.sprite_D[i]) + @as(usize, @intFromBool(low_health)) * 16;
    v.sprite_x_vel[i] = @bitCast(t.kGiantMoldorm_Xvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kGiantMoldorm_Yvel[j]);
    a.Sprite_MoveXY(k);
    if (a.Sprite_CheckTileCollision(k) != 0) {
        v.sprite_D[i] = t.kGiantMoldorm_NextDir[v.sprite_D[i]];
        a.SpriteSfx_QueueSfx2WithPan(k, 0x21);
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // straight path
            if (v.sprite_delay_main[i] == 0) {
                var s: u8 = 1;
                v.sprite_G[i] +%= 1;
                if (v.sprite_G[i] == 3) {
                    v.sprite_G[i] = 0;
                    s = 2;
                }
                v.sprite_ai_state[i] = s;
                v.sprite_head_dir[i] = (a.GetRandomNumber() & 2) -% 1;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 32;
            }
        },
        1 => { // spinning meander
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 15) +% 8;
                v.sprite_ai_state[i] = 0;
            } else if (v.sprite_delay_main[i] & 3 == 0) {
                v.sprite_D[i] = (v.sprite_D[i] +% v.sprite_head_dir[i]) & 0xf;
            }
        },
        2 => { // lunge at player
            if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0) {
                a.Sprite_ApplySpeedTowardsLink(k, 0x1f);
                const dir = a.Sprite_ConvertVelocityToAngle(v.sprite_x_vel[i], v.sprite_y_vel[i]) -% v.sprite_D[i];
                if (dir == 0) {
                    v.sprite_ai_state[i] = 0;
                    v.sprite_delay_main[i] = 48;
                } else {
                    v.sprite_D[i] +%= if (sign8(dir)) @as(u8, 0xff) else 1;
                }
            }
        },
        else => {},
    }
}

pub export fn Sprite_01_Vulture_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_obj_prio[i] |= 0x30;
    a.Vulture_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXY(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // dormant
            v.sprite_subtype2[i] +%= 1;
            if (v.sprite_subtype2[i] == 160) {
                v.sprite_ai_state[i] = 1;
                a.SpriteSfx_QueueSfx3WithPan(k, 0x1e);
                v.sprite_delay_main[i] = 16;
            }
        },
        1 => { // circling
            v.sprite_graphics[i] = t.kVulture_Gfx[v.frame_counter.* >> 1 & 3];
            if (v.sprite_delay_main[i] != 0) {
                v.sprite_z[i] +%= 1;
                return;
            }
            if ((k ^ @as(c_int, v.frame_counter.*)) & 1 != 0)
                return;
            const pt = a.Sprite_ProjectSpeedTowardsLink(k, @as(u8, @truncate(@as(u32, @bitCast(k)) & 0xf)) +% 24);
            v.sprite_x_vel[i] = 0 -% pt.y;
            v.sprite_y_vel[i] = pt.x;
            if (pt.xdiff +% 0x28 < 0x50 and pt.ydiff +% 0x28 < 0x50)
                return;
            v.sprite_y_vel[i] +%= asr8(pt.y, 2);
            v.sprite_x_vel[i] +%= asr8(pt.x, 2);
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part16.zig
// ---------------------------------------------------------------------------
/// sprite_main.c declares these as `(uint16*)(g_ram+0x1FC00)` and `+0x1FD00`,
/// aliasing the same work RAM the moldorm segment history uses.

pub export fn SpritePrep_Chainchomp_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    const hx = chainchompX();
    const hy = chainchompY();
    var pos: usize = i * 8;
    var n: isize = 5;
    while (n >= 0) : ({
        n -= 1;
        pos += 1;
    }) {
        hx[pos] = v.cur_sprite_x.*;
        hy[pos] = v.cur_sprite_y.*;
    }
    v.sprite_A[i] = v.sprite_x_lo[i];
    v.sprite_B[i] = v.sprite_x_hi[i];
    v.sprite_C[i] = v.sprite_y_lo[i];
    v.sprite_G[i] = v.sprite_y_hi[i];
}

pub export fn ChainChomp_HandleLeash(k: c_int) callconv(.c) void {
    const hx = chainchompX();
    const hy = chainchompY();
    var pos: usize = ix(k) * 8;
    hx[pos] = v.cur_sprite_x.*;
    hy[pos] = v.cur_sprite_y.*;
    for (0..6) |_| {
        const x = hx[pos] -% hx[pos + 1];
        if (!sign16_p16(x -% 8)) {
            hx[pos + 1] = hx[pos] -% 8;
        } else if (sign16_p16(x +% 8)) {
            hx[pos + 1] = hx[pos] +% 8;
        }

        const y = hy[pos] -% hy[pos + 1];
        if (!sign16_p16(y -% 8)) {
            hy[pos + 1] = hy[pos] -% 8;
        } else if (sign16_p16(y +% 8)) {
            hy[pos + 1] = hy[pos] +% 8;
        }
        pos += 1;
    }
}

pub export fn ChainChomp_MoveChain(k: c_int) callconv(.c) void {
    const i = ix(k);
    const hx = chainchompX();
    const hy = chainchompY();
    const x = @as(u16, v.sprite_A[i]) | (@as(u16, v.sprite_B[i]) << 8);
    const y = @as(u16, v.sprite_C[i]) | (@as(u16, v.sprite_G[i]) << 8);
    var pos: usize = i * 8;
    const x2 = hx[pos] -% x;
    const y2 = hy[pos] -% y;
    pos += 1;
    var n: isize = 5;
    while (n >= 0) : (n -= 1) {
        // C passes the 16-bit delta into a uint8 parameter and adds the int
        // result back onto a uint16, so both narrowings are implicit there.
        const mul = t.kChainChomp_Muls[(pos & 7) - 1];
        const x3 = x +% @as(u16, @truncate(@as(u32, @bitCast(a.ChainChomp_OneMult(@truncate(x2), mul)))));
        const y3 = y +% @as(u16, @truncate(@as(u32, @bitCast(a.ChainChomp_OneMult(@truncate(y2), mul)))));
        if (hx[pos] -% x3 != 0)
            hx[pos] +%= if (sign16_p16(hx[pos] -% x3)) 1 else @as(u16, 0xffff);
        if (hy[pos] -% y3 != 0)
            hy[pos] +%= if (sign16_p16(hy[pos] -% y3)) 1 else @as(u16, 0xffff);
        pos += 1;
    }
}

pub export fn ChainChomp_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = v.sprite_D[i];
    v.sprite_graphics[i] = t.kChainChomp_Gfx[j];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0x3f) | t.kChainChomp_OamFlags[j];
    a.SpriteDraw_SingleLarge(k);
    var oam: [*]v.OamEnt = @ptrCast(&v.g_ram[v.oam_cur_ptr.*]);
    oam += 1;
    const flags = v.sprite_oam_flags[i] ^ v.sprite_obj_prio[i];
    const r8: u16 = @as(u16, v.sprite_delay_aux1[i] & 1) + 4;
    const hx = chainchompX();
    const hy = chainchompY();
    var pos: usize = i * 8;
    var n: isize = 5;
    while (n >= 0) : ({
        n -= 1;
        pos += 1;
        oam += 1;
    }) {
        setOam(
            oam,
            hx[pos] +% r8 -% v.BG2HOFS_copy2.*,
            hy[pos] +% r8 -% v.BG2VOFS_copy2.*,
            0x8b,
            (flags & 0xf0) | 0xd,
            0,
        );
    }
}

pub export fn Sprite_CA_ChainChomp(k: c_int) callconv(.c) void {
    const i = ix(k);
    ChainChomp_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    ChainChomp_HandleLeash(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0 and
        (v.sprite_x_vel[i] | v.sprite_y_vel[i]) != 0)
        v.sprite_D[i] = a.Sprite_ConvertVelocityToAngle(v.sprite_x_vel[i], v.sprite_y_vel[i]) & 0xf;
    a.Sprite_MoveXYZ(k);
    v.sprite_z_vel[i] -%= 2;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = 0;
    }
    a.Sprite_Get16BitCoords(k);
    const x = @as(u16, v.sprite_A[i]) | (@as(u16, v.sprite_B[i]) << 8);
    const y = @as(u16, v.sprite_C[i]) | (@as(u16, v.sprite_G[i]) << 8);
    v.sprite_anim_clock[i] = @intFromBool(v.cur_sprite_x.* -% x +% 48 < 96 and
        v.cur_sprite_y.* -% y +% 48 < 96);
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_subtype2[i] +%= 1;
                if (v.sprite_subtype2[i] == 4) {
                    v.sprite_subtype2[i] = 0;
                    v.sprite_ai_state[i] = 2;
                    const j: usize = a.GetRandomNumber() & 15;
                    v.sprite_x_vel[i] = @as(u8, @bitCast(t.kChainChomp_Xvel[j])) << 2;
                    v.sprite_y_vel[i] = @as(u8, @bitCast(t.kChainChomp_Yvel[j])) << 2;
                    _ = a.GetRandomNumber();
                    a.Sprite_ApplySpeedTowardsLink(k, 64);
                    a.SpriteSfx_QueueSfx3WithPan(k, 0x4);
                } else {
                    v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 16;
                    const j: usize = a.GetRandomNumber() & 15;
                    v.sprite_x_vel[i] = @bitCast(t.kChainChomp_Xvel[j]);
                    v.sprite_y_vel[i] = @bitCast(t.kChainChomp_Yvel[j]);
                    v.sprite_ai_state[i] = 1;
                }
            } else {
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
            }
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 32;
                v.sprite_ai_state[i] = 0;
            }
            if (v.sprite_delay_main[i] & 15 == 0)
                ChainChomp_MoveChain(k);
            if (v.sprite_z[i] == 0)
                v.sprite_z_vel[i] = 16;
            if (v.sprite_anim_clock[i] == 0) {
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 16);
                v.sprite_x_vel[i] = pt.x;
                v.sprite_y_vel[i] = pt.y;
                a.Sprite_MoveXY(k);
                v.sprite_delay_main[i] = 12;
            }
        },
        2 => {
            if (v.sprite_anim_clock[i] == 0) {
                v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
                v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
                a.Sprite_MoveXY(k);
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
                v.sprite_ai_state[i] = 3;
                v.sprite_delay_aux1[i] = 48;
            }
            ChainChomp_MoveChain(k);
            ChainChomp_MoveChain(k);
        },
        3 => {
            if (v.sprite_delay_aux1[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 48;
            }
            ChainChomp_MoveChain(k);
            ChainChomp_MoveChain(k);
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part17.zig
// ---------------------------------------------------------------------------
/// sprite_main.c reaches these segment histories through raw work-RAM pointers.

pub export fn SpritePrep_MiniMoldorm_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    const xl = moldormXLo();
    const xh = moldormXHi();
    const yl = moldormYLo();
    const yh = moldormYHi();
    var j: usize = 32 * i;
    for (0..32) |_| {
        xl[j] = v.sprite_x_lo[i];
        xh[j] = v.sprite_x_hi[i];
        yl[j] = v.sprite_y_lo[i];
        yh[j] = v.sprite_y_hi[i];
        j += 1;
    }
}

pub export fn Sprite_27_Deadrock(k: c_int) callconv(.c) void {
    const i = ix(k);
    const pick = if (v.sprite_delay_aux2[i] != 0)
        (v.sprite_delay_aux2[i] & 4) != 0
    else
        v.sprite_ai_state[i] != 2;
    const g: usize = if (pick) v.sprite_A[i] else 8;
    v.sprite_graphics[i] = t.kDeadRock_Gfx[g];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) | t.kDeadRock_OamFlags[g];
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_F[i] == 0 and
        (a.Sprite_CheckDamageFromLink(k) & 1) != 0 and
        v.sound_effect_1.* == 0)
        a.SpriteSfx_QueueSfx2WithPan(k, 0xb);
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Sprite_NullifyHookshotDrag();
        a.Sprite_RepelDash();
    }
    if (v.sprite_F[i] == 14) {
        v.sprite_ai_state[i] = 2;
        v.sprite_delay_aux1[i] = 255;
        v.sprite_delay_aux2[i] = 64;
    }
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // pick dir
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_flags2[i] &= ~@as(u8, 0x80);
                v.sprite_defl_bits[i] &= ~@as(u8, 4);
                v.sprite_flags3[i] &= ~@as(u8, 0x40);
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 32;
                v.sprite_B[i] +%= 1;
                const d: u8 = if (v.sprite_B[i] == 4) blk: {
                    v.sprite_B[i] = 0;
                    break :blk a.Sprite_DirectionToFaceLink(k, null);
                } else a.GetRandomNumber() & 3;
                deadrockSetDir(i, d);
            }
        },
        1 => { // walk
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 32;
            } else {
                a.Sprite_MoveXY(k);
                if (a.Sprite_CheckTileCollision(k) != 0) {
                    deadrockSetDir(i, v.sprite_D[i] ^ 1);
                    return;
                }
                v.sprite_subtype2[i] +%= 1;
                v.sprite_A[i] = (v.sprite_D[i] << 1) | ((v.sprite_subtype2[i] >> 2) & 1);
            }
        },
        2 => { // petrified
            v.sprite_flags2[i] |= 0x80;
            v.sprite_defl_bits[i] |= 4;
            v.sprite_flags3[i] |= 0x40;
            if (v.frame_counter.* & 1 == 0) {
                if (v.sprite_delay_aux1[i] == 0) {
                    v.sprite_ai_state[i] = 0;
                    v.sprite_delay_main[i] = 16;
                } else if (v.sprite_delay_aux1[i] == 0x20) {
                    v.sprite_delay_aux2[i] = 0x40;
                }
            } else {
                v.sprite_delay_aux1[i] +%= 1;
            }
        },
        else => {},
    }
}

/// The shared `set_dir` label.

pub export fn Sprite_20_Sluggula(k: c_int) callconv(.c) void {
    const i = ix(k);
    const g: usize = (@as(usize, v.sprite_D[i]) << 1) | ((v.sprite_subtype2[i] & 8) >> 3);
    v.sprite_graphics[i] = t.kSluggula_Gfx[g];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 191) | t.kSluggula_OamFlags[g];
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_subtype2[i] +%= 1;
    switch (v.sprite_ai_state[i]) {
        0 => { // normal
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 32;
                v.sprite_D[i] = v.sprite_delay_main[i] & 3;
                sluggulaSetVel(i, v.sprite_D[i]);
            } else if (v.sprite_delay_main[i] == 16 and (a.GetRandomNumber() & 1) == 0) {
                Sluggula_DropBomb(k);
            }
        },
        1 => { // break from bombing
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 32;
            }
            a.Sprite_MoveXY(k);
            if (a.Sprite_CheckTileCollision(k) == 0)
                return;
            v.sprite_D[i] ^= 1;
            sluggulaSetVel(i, v.sprite_D[i]);
        },
        else => {},
    }
}

/// The shared `set_vel` label.

pub export fn Sluggula_DropBomb(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamicallyEx(k, 0x4a, &info, 11);
    if (j >= 0) {
        a.Sprite_SetSpawnedCoordinates(j, &info);
        a.Sprite_TransmuteToBomb(j);
    }
}

pub export fn Sprite_19_Poe(k: c_int) callconv(.c) void {
    const i = ix(k);
    var j: usize = v.sprite_x_vel[i] >> 7;
    v.sprite_D[i] = @truncate(j);
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) | t.kPoe_OamFlags[j];
    if (v.sprite_E[i] == 0)
        v.sprite_obj_prio[i] |= 0x30;
    Poe_Draw(k);
    v.oam_cur_ptr.* +%= 4;
    v.oam_ext_cur_ptr.* +%= 1;
    v.sprite_flags2[i] -%= 1;
    a.SpriteDraw_SingleLarge(k);
    v.sprite_flags2[i] +%= 1;
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    if (v.sprite_E[i] != 0) {
        v.sprite_z[i] +%= 1;
        if (v.sprite_z[i] == 12)
            v.sprite_E[i] = 0;
        return;
    }
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_subtype2[i] +%= 1;
    a.Sprite_MoveXY(k);
    if (v.frame_counter.* & 1 == 0) {
        j = v.sprite_G[i] & 1;
        v.sprite_z_vel[i] +%= @bitCast(t.kPoe_Accel[j]);
        if (v.sprite_z_vel[i] == @as(u8, @bitCast(t.kPoe_ZvelTarget[j])))
            v.sprite_G[i] +%= 1;
    }
    a.Sprite_MoveZ(k);
    v.sprite_y_vel[i] = 0;
    switch (v.sprite_ai_state[i]) {
        0 => { // select vertical dir
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                if (a.GetRandomNumber() & 12 == 0) {
                    v.sprite_head_dir[i] = a.Sprite_IsBelowLink(k).a;
                } else {
                    v.sprite_head_dir[i] = a.GetRandomNumber() & 1;
                }
            }
        },
        1 => { // roaming
            if (v.frame_counter.* & 1 == 0) {
                const m: usize = (v.sprite_anim_clock[i] & 1) + @as(usize, v.is_in_dark_world.*) * 2;
                v.sprite_x_vel[i] +%= @bitCast(t.kPoe_Accel[m]);
                if (v.sprite_x_vel[i] == @as(u8, @bitCast(t.kPoe_XvelTarget[m]))) {
                    v.sprite_anim_clock[i] +%= 1;
                    v.sprite_ai_state[i] = 0;
                    v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 16;
                }
            }
            v.sprite_y_vel[i] = @bitCast(t.kPoe_Yvel[v.sprite_head_dir[i]]);
        },
        else => {},
    }
}

pub export fn Poe_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    const oam = oamPtr();
    setOam(
        oam,
        info.x +% s16(t.kPoe_Draw_X[v.sprite_D[i]]),
        info.y +% 9,
        t.kPoe_Draw_Char[v.sprite_subtype2[i] >> 3 & 3],
        (info.flags & 0xf0) | 2,
        0,
    );
}

pub export fn Sprite_18_MiniMoldorm(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Moldorm_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_F[i] != 0)
        SpritePrep_MiniMoldorm_bounce(k);
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_subtype2[i] +%= 1;
    const d: usize = v.sprite_D[i];
    v.sprite_x_vel[i] = @bitCast(t.kMoldorm_Xvel[d]);
    v.sprite_y_vel[i] = @bitCast(t.kMoldorm_Yvel[d]);
    a.Sprite_MoveXY(k);
    if (a.Sprite_CheckTileCollision(k) != 0) {
        if (a.GetRandomNumber() & 1 != 0)
            v.sprite_head_dir[i] = 0 -% v.sprite_head_dir[i];
        v.sprite_D[i] = t.kMoldorm_NextDir[v.sprite_D[i]];
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // configure
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_G[i] +%= 1;
                if (v.sprite_G[i] == 6) {
                    v.sprite_G[i] = 0;
                    v.sprite_ai_state[i] = 2;
                } else {
                    v.sprite_ai_state[i] = 1;
                }
                v.sprite_head_dir[i] = (a.GetRandomNumber() & 2) -% 1;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 0x1f) +% 0x20;
            }
        },
        1 => { // meander
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 15) +% 8;
                v.sprite_ai_state[i] = 0;
            } else if (v.sprite_delay_main[i] & 3 == 0) {
                v.sprite_D[i] = (v.sprite_D[i] +% v.sprite_head_dir[i]) & 0xf;
            }
        },
        2 => { // seek player
            if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0) {
                a.Sprite_ApplySpeedTowardsLink(k, 31);
                const dd = a.Sprite_ConvertVelocityToAngle(v.sprite_x_vel[i], v.sprite_y_vel[i]) -% v.sprite_D[i];
                if (dd == 0) {
                    v.sprite_ai_state[i] = 0;
                    v.sprite_delay_main[i] = 48;
                } else {
                    v.sprite_D[i] = (v.sprite_D[i] +% (if (sign8(dd)) @as(u8, 0xff) else 1)) & 0xf;
                }
            }
        },
        else => {},
    }
}

pub export fn Sprite_22_Ropa(k: c_int) callconv(.c) void {
    const i = ix(k);
    Ropa_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = v.sprite_subtype2[i] >> 3 & 3;
    switch (v.sprite_ai_state[i]) {
        0 => { // stationary
            if (v.sprite_delay_main[i] == 0) {
                a.Sprite_ApplySpeedTowardsLink(k, 16);
                v.sprite_z_vel[i] = (a.GetRandomNumber() & 15) +% 20;
                v.sprite_ai_state[i] +%= 1;
            }
        },
        1 => { // pounce
            a.Sprite_MoveXY(k);
            if (a.Sprite_CheckTileCollision(k) != 0)
                a.Sprite_ZeroVelocity_XY(k);
            a.Sprite_MoveZ(k);
            v.sprite_z_vel[i] -%= 2;
            if (sign8(v.sprite_z[i])) {
                v.sprite_z[i] = 0;
                v.sprite_delay_main[i] = 48;
                v.sprite_ai_state[i] = 0;
            }
        },
        else => {},
    }
}

pub export fn Ropa_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kRopa_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 3], 3, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Moblin_MaterializeSpear(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x1b, &info);
    if (j >= 0) {
        const ju = ix(j);
        v.sprite_A[ju] = 3;
        const d: usize = v.sprite_D[ix(k)];
        v.sprite_D[ju] = @truncate(d);
        a.Sprite_SetX(j, info.r0_x +% s16(t.kMoblinSpear_X[d]));
        a.Sprite_SetY(j, info.r2_y +% s16(t.kMoblinSpear_Y[d]));
        v.sprite_x_vel[ju] = @bitCast(t.kMoblinSpear_Xvel[d]);
        v.sprite_y_vel[ju] = @bitCast(t.kMoblinSpear_Yvel[d]);
    }
}

pub export fn Moblin_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kMoblin_Dmd[@as(usize, v.sprite_graphics[i]) * 4], 4, &info);
    if (v.sprite_pause[i] != 0)
        return;
    var oam = oamPtr();
    if (v.sprite_delay_aux1[i] != 0) {
        for (0..4) |_| {
            const n = (@intFromPtr(oam) - @intFromPtr(v.oam_buf)) / @sizeOf(v.OamEnt);
            if (v.bytewise_extended_oam[n] & 2 == 0)
                oam[0].y = 0xf0;
            oam += 1;
        }
    }
    const head = oamPtr() + t.kMoblin_ObjOffs[v.sprite_graphics[i]];
    const j: usize = v.sprite_head_dir[i];
    head[0].charnum = t.kMoblin_HeadChar[j];
    head[0].flags = (head[0].flags & ~@as(u8, 0x40)) | t.kMoblin_HeadFlags[j];
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Hinox_ThrowBomb(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn Hinox_SetDirection(k: c_int, dir: u8) callconv(.c) void {
    const i = ix(k);
    v.sprite_D[i] = dir;
    v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 96;
    v.sprite_ai_state[i] +%= 1;
    v.sprite_x_vel[i] = @bitCast(t.kHinox_Xvel[dir]);
    v.sprite_y_vel[i] = @bitCast(t.kHinox_Yvel[dir]);
}

pub export fn Hinox_FaceLink(k: c_int) callconv(.c) void {
    const i = ix(k);
    Hinox_SetDirection(k, a.Sprite_DirectionToFaceLink(k, null));
    v.sprite_x_vel[i] <<= 1;
    v.sprite_y_vel[i] <<= 1;
}

// ---------------------------------------------------------------------------
// from sprite_main_part18.zig
// ---------------------------------------------------------------------------
pub export fn Hinox_Draw(k: c_int) callconv(.c) void {
    const j: usize = v.sprite_graphics[ix(k)];
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kHinox_Dmd[t.kHinoxOffs[j]], t.kHinoxNum[j], &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_23_RedBari(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (sign8(v.sprite_C[i])) {
        if (v.sprite_head_dir[i] != 16) {
            v.sprite_head_dir[i] +%= 1;
            return;
        }
        v.sprite_x_vel[i] = 255;
        v.sprite_subtype[i] = 255;
        a.Sprite_CheckTileCollision2(k);
        v.sprite_subtype[i] = 0;
        if (v.sprite_tiletype.* == 0) {
            v.sprite_C[i] = 0;
            v.sprite_ignore_projectile[i] = 0;
            // goto set_electrocute_delay
            v.sprite_delay_aux1[i] = (a.GetRandomNumber() & 63) +% 128;
            return;
        }
        v.sprite_ignore_projectile[i] = v.sprite_tiletype.*;
        return;
    }
    if (v.sprite_C[i] != 0) {
        a.SpriteDraw_SingleSmall(k);
    } else if (v.sprite_graphics[i] >= 2) {
        a.SpriteDraw_SingleLarge(k);
    } else {
        RedBari_Draw(k);
    }

    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;

    // `goto recoil_from_split` skips straight to the movement step.
    var recoil = v.sprite_delay_aux2[i] != 0;
    if (!recoil) {
        if (v.sprite_ai_state[i] == 2) {
            v.sprite_ignore_projectile[i] = v.sprite_ai_state[i];
            v.sprite_x_vel[i] = @bitCast(t.kBari_Xvel[v.frame_counter.* >> 1 & 1]);
            a.Sprite_MoveX(k);
            if (v.sprite_delay_main[i] == 0) {
                RedBari_Split(k);
                v.sprite_state[i] = 0;
            }
            return;
        }

        _ = a.Sprite_CheckDamageToAndFromLink(k);
        if ((k ^ @as(c_int, v.frame_counter.*)) & 15 == 0) {
            v.sprite_A[i] +%= if (v.sprite_B[i] & 1 != 0) @as(u8, 0xff) else 1;
            if (a.GetRandomNumber() & 3 == 0)
                v.sprite_B[i] +%= 1;
        }
        const m: usize = v.sprite_A[i] & 15;
        v.sprite_x_vel[i] = @bitCast(t.kBari_Xvel2[m]);
        v.sprite_y_vel[i] = @bitCast(t.kBari_Yvel2[m]);

        recoil = (((k ^ @as(c_int, v.frame_counter.*)) & 3) |
            @as(c_int, v.sprite_delay_main[i])) == 0;
    }
    if (recoil) {
        if (v.sprite_wallcoll[i] == 0)
            a.Sprite_MoveXY(k);
        a.Sprite_CheckTileCollision2(k);
    }
    const g: usize = v.sprite_C[i];
    v.sprite_graphics[i] = @as(u8, @truncate(v.frame_counter.* >> 3 & 1)) +% t.kBari_Gfx[g];
    if (v.sprite_ai_state[i] != 0) {
        if (v.sprite_delay_main[i] != 0) {
            v.sprite_graphics[i] = @as(u8, @truncate(v.frame_counter.* >> 1 & 2)) +% t.kBari_Gfx[g];
            return;
        }
        v.sprite_ai_state[i] = 0;
    } else if (v.sprite_delay_aux1[i] != 0) {
        return;
    } else if (a.GetRandomNumber() & 1 == 0) {
        v.sprite_delay_main[i] = 128;
        v.sprite_ai_state[i] +%= 1;
        return;
    }
    // set_electrocute_delay:
    v.sprite_delay_aux1[i] = (a.GetRandomNumber() & 63) +% 128;
}

pub export fn RedBari_Split(k: c_int) callconv(.c) void {
    v.tmp_counter.* = 1;
    while (true) {
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x23, &info);
        if (j >= 0) {
            const ju = ix(j);
            const m: usize = v.tmp_counter.*;
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_flags3[ju] = 0x33;
            v.sprite_oam_flags[ju] = 3;
            v.sprite_flags4[ju] = 1;
            v.sprite_C[ju] = 1;
            a.Sprite_SetX(j, info.r0_x +% @as(u16, @bitCast(@as(i16, t.kRedBari_SplitX[m]))));
            v.sprite_x_vel[ju] = @bitCast(t.kRedBari_SplitXvel[m]);
            v.sprite_delay_aux2[ju] = 8;
            v.sprite_delay_aux1[ju] = 64;
        }
        v.tmp_counter.* -%= 1;
        if (sign8(v.tmp_counter.*))
            break;
    }
}

pub export fn RedBari_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kRedBari_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 4], 4, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_13_MiniHelmasaur(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = (v.sprite_subtype2[i] >> 2 & 1) | (@as(usize, v.sprite_D[i]) << 1);
    v.sprite_graphics[i] = t.kHelmasaur_Gfx[j];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) | t.kHelmasaur_OamFlags[j];
    if ((k ^ @as(c_int, v.frame_counter.*)) & 15 == 0) {
        var x = v.sprite_x_vel[i];
        if (sign8(x)) x = 0 -% x;
        var y = v.sprite_y_vel[i];
        if (sign8(y)) y = 0 -% y;
        v.sprite_D[i] = if (x >= y) (v.sprite_x_vel[i] >> 7) else (v.sprite_y_vel[i] >> 7) +% 2;
    }
    a.SpriteDraw_SingleLarge(k);
    HelmasaurHardHatBeetleCommon(k);
}

pub export fn Sprite_26_HardhatBeetle(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_graphics[i] = v.sprite_subtype2[i] >> 2 & 1;
    HardHatBeetle_Draw(k);
    HelmasaurHardHatBeetleCommon(k);
}

pub export fn HelmasaurHardHatBeetleCommon(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    v.sprite_subtype2[i] +%= 1;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.sprite_wallcoll[i] & 15 != 0) {
        if (v.sprite_wallcoll[i] & 3 != 0)
            v.sprite_x_vel[i] = 0;
        v.sprite_y_vel[i] = 0;
    } else {
        a.Sprite_MoveXY(k);
    }
    _ = a.Sprite_CheckTileCollision(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 31 == 0) {
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, v.sprite_A[i]);
        v.sprite_B[i] = pt.y;
        v.sprite_C[i] = pt.x;
    }
    if ((k ^ @as(c_int, v.frame_counter.*)) & @as(c_int, v.sprite_ai_state[i]) != 0)
        return;
    v.sprite_y_vel[i] +%= if (sign8(v.sprite_y_vel[i] -% v.sprite_B[i])) 1 else @as(u8, 0xff);
    v.sprite_x_vel[i] +%= if (sign8(v.sprite_x_vel[i] -% v.sprite_C[i])) 1 else @as(u8, 0xff);
}

pub export fn HardHatBeetle_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kHardHatBeetle_Dmd[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    if (v.sprite_flags3[i] & 0x10 != 0)
        a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_15_Antifairy(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_Antfairy(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_CheckDamageToLink(k) and v.sprite_delay_main[i] == 0) {
        v.sprite_delay_main[i] = 16;
        const m: i32 = @as(i32, v.link_magic_power.*) - 8;
        if (m < 0) {
            v.link_magic_power.* = 0;
        } else {
            v.sound_effect_2.* = 0x1d;
            v.link_magic_power.* = @truncate(@as(u32, @bitCast(m)));
        }
    }
    a.Sprite_MoveXY(k);
    _ = a.Sprite_BounceFromTileCollision(k);
}

pub export fn BawkBawk(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx2WithPan(k, 0x30);
}

pub export fn Cucco_DoMovement_XY(k: c_int) callconv(.c) u8 {
    a.Sprite_MoveXY(k);
    return a.Sprite_CheckTileCollision(k);
}

pub export fn Cucco_DrawPANIC(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    a.Sprite_DrawDistress_custom(info.x, info.y, v.frame_counter.*);
}

pub export fn Cucco_Calm(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_main[i] == 0) {
        const j: usize = a.GetRandomNumber() & 0xf;
        v.sprite_x_vel[i] = @bitCast(t.kSpriteKeese_Tab2[j]);
        v.sprite_y_vel[i] = @bitCast(t.kSpriteKeese_Tab3[j]);
        v.sprite_delay_main[i] = (a.GetRandomNumber() & 0x1f) +% 0x10;
        v.sprite_ai_state[i] +%= 1;
    }
    v.sprite_graphics[i] = 0;
    _ = a.Sprite_ReturnIfLifted(k);
}

pub export fn Chicken_Hopping(k: c_int) callconv(.c) void {
    const i = ix(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 1 != 0 and Cucco_DoMovement_XY(k) != 0)
        v.sprite_ai_state[i] = 0;
    a.Sprite_MoveZ(k);
    v.sprite_z_vel[i] -%= 2;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        if (v.sprite_delay_main[i] == 0) {
            v.sprite_delay_main[i] = 32;
            v.sprite_ai_state[i] = 0;
        }
        v.sprite_z_vel[i] = 10;
    }
    a.Chicken_IncrSubtype2(k, 4);
}

pub export fn Cucco_Flee(k: c_int) callconv(.c) void {
    const i = ix(k);
    _ = a.Sprite_ReturnIfLifted(k);
    _ = Cucco_DoMovement_XY(k);
    v.sprite_z[i] = 0;
    if ((k ^ @as(c_int, v.frame_counter.*)) & 0x1f == 0) {
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 16);
        v.sprite_x_vel[i] = 0 -% pt.x;
        v.sprite_y_vel[i] = 0 -% pt.y;
    }
    a.Chicken_IncrSubtype2(k, 5);
    Cucco_DrawPANIC(k);
}

pub export fn Cucco_Carried(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Sprite_MoveZ(k);
    if (Cucco_DoMovement_XY(k) != 0) {
        v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
        v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
        a.Sprite_MoveXY(k);
        a.Sprite_HalveSpeed_XY(k);
        a.Sprite_HalveSpeed_XY(k);
        BawkBawk(k);
    }
    v.sprite_z_vel[i] -%= 1;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_ai_state[i] = 2;
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 16);
        v.sprite_x_vel[i] = 0 -% pt.x;
        v.sprite_y_vel[i] = 0 -% pt.y;
        a.Chicken_IncrSubtype2(k, 5);
        Cucco_DrawPANIC(k);
    } else {
        a.Chicken_IncrSubtype2(k, 4);
    }
}

pub export fn Cucco_SummonAvenger(k: c_int) callconv(.c) void {
    if ((((k ^ @as(c_int, v.frame_counter.*)) & 0xf) | @as(c_int, v.player_is_indoors.*)) != 0)
        return;
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamicallyEx(k, 0xB, &info, 10);
    if (j < 0)
        return;
    a.SpriteSfx_QueueSfx3WithPan(j, 0x1e);
    v.sprite_C[ix(j)] = 1;
    const r = a.GetRandomNumber();
    var x: u16 = v.BG2HOFS_copy2.*;
    var y: u16 = v.BG2VOFS_copy2.*;
    if (r & 2 != 0) {
        x +%= r;
        y +%= t.kChicken_Avenger[r & 1];
    } else {
        y +%= r;
        x +%= t.kChicken_Avenger[r & 1];
    }
    a.Sprite_SetX(j, x);
    a.Sprite_SetY(j, y);
    a.Sprite_ApplySpeedTowardsLink(j, 32);
    BawkBawk(k);
}

pub export fn Sprite_TransmuteToBomb(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_type[i] = 0x4a;
    v.sprite_C[i] = 1;
    v.sprite_delay_aux1[i] = 255;
    v.sprite_flags3[i] = 0x18;
    v.sprite_oam_flags[i] = 8;
    v.sprite_health[i] = 0;
}

pub export fn DarkWorldHintNPC_Idle(k: c_int) callconv(.c) void {
    if ((a.Sprite_ShowSolicitedMessage(k, 0xfe) & 0x100) != 0)
        v.sprite_ai_state[ix(k)] = 1;
}

pub export fn DarkWorldHintNPC_RestoreHealth(k: c_int) callconv(.c) void {
    v.link_hearts_filler.* = 0xa0;
    v.sprite_ai_state[ix(k)] = 0;
}

pub export fn DarkWorldHintNPC_HandlePayment() callconv(.c) bool {
    if (v.link_rupees_goal.* < 20)
        return false;
    v.link_rupees_goal.* -%= 20;
    return true;
}

// ---------------------------------------------------------------------------
// from sprite_main_part19.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_17_Hoarder(k: c_int) callconv(.c) void {
    if (v.sprite_ai_state[ix(k)] != 0) {
        Sprite_Hoarder_Frantic(k);
    } else {
        Sprite_Hoarder_Covered(k);
    }
}

pub export fn Sprite_Hoarder_Covered(k: c_int) callconv(.c) void {
    const i = ix(k);
    CoveredRupeeCrab_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    v.sprite_graphics[i] = 0;
    var pt: PointU8 = undefined;
    const dir: usize = a.Sprite_DirectionToFaceLink(k, &pt);
    // `goto lbl` enters the body without re-testing the proximity box.
    const move = v.sprite_delay_main[i] != 0 or
        (pt.y +% 0x30 < 0x60 and pt.x +% 0x20 < 0x40);
    if (move) {
        if (v.sprite_delay_main[i] == 0)
            v.sprite_delay_main[i] = 32;
        v.sprite_x_vel[i] = @bitCast(t.kRupeeCoveredGrab_Xvel[dir]);
        v.sprite_y_vel[i] = @bitCast(t.kRupeeCoveredGrab_Yvel[dir]);
        if (v.sprite_wallcoll[i] == 0)
            a.Sprite_MoveXY(k);
        a.Sprite_CheckTileCollision2(k);
        _ = a.Sprite_CheckDamageFromLink(k);
        v.sprite_subtype2[i] +%= 1;
        v.sprite_graphics[i] = t.kRupeeCoveredGrab_Gfx[v.sprite_subtype2[i] >> 1 & 3];
    }
    if (v.sprite_type[i] != 0x3e or v.link_item_gloves.* >= 1)
        _ = a.Sprite_ReturnIfLiftedPermissive(k); // note, dont ret
    if (v.sprite_state[i] != 9) {
        v.sprite_C[i] = if (v.sprite_type[i] == 0x17) 2 else 1;
        v.sprite_type[i] = 0xec;
        v.sprite_oam_flags[i] &= ~@as(u8, 1);
        v.sprite_graphics[i] = 0;
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x3e, &info);
        if (j >= 0) {
            const ju = ix(j);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_flags2[ju] &= ~@as(u8, 0x80);
            v.sprite_delay_aux2[ju] = 128;
            v.sprite_oam_flags[ju] = 9;
            v.sprite_ai_state[ju] = 9;
        }
    }
}

pub export fn Sprite_Hoarder_Frantic(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    _ = a.Sprite_CheckDamageFromLink(k);
    if (v.sprite_delay_aux2[i] == 0)
        _ = a.Sprite_CheckDamageToLink(k);
    v.sprite_subtype2[i] +%= 1;
    var j: usize = v.sprite_subtype2[i] >> 1 & 3;
    v.sprite_graphics[i] = t.kRupeeCrab_Gfx[j];
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) | t.kRupeeCrab_OamFlags[j];
    if (v.sprite_wallcoll[i] != 0) {
        v.sprite_delay_aux4[i] = 16;
        j = a.GetRandomNumber() & 3;
        v.sprite_x_vel[i] = @bitCast(t.kRupeeCrab_Xvel[j]);
        v.sprite_y_vel[i] = @bitCast(t.kRupeeCrab_Yvel[j]);
    } else {
        a.Sprite_MoveXY(k);
    }
    a.Sprite_CheckTileCollision2(k);
    if (v.sprite_delay_aux4[i] == 0 and (k ^ @as(c_int, v.frame_counter.*)) & 31 == 0) {
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 16);
        v.sprite_y_vel[i] = 0 -% pt.y;
        v.sprite_x_vel[i] = 0 -% pt.x;
    }
    if (v.frame_counter.* & 1 != 0)
        return;

    var end: c_int = undefined;
    var ty: u8 = undefined;
    v.sprite_G[i] +%= 1;
    if (v.sprite_G[i] == 192) {
        v.sprite_delay_main[i] = 15;
        v.sprite_state[i] = 6;
        v.sprite_flags2[i] +%= 4;
        end = 1;
        ty = 0xd9;
    } else {
        if (v.sprite_G[i] & 15 != 0)
            return;
        end = 0;
        ty = if (v.sprite_head_dir[i] == 6) 0xdb else 0xd9;
    }
    var info: SpriteSpawnInfo = undefined;
    const sp = a.Sprite_SpawnDynamicallyEx(k, ty, &info, end);
    if (sp >= 0) {
        const ju = ix(sp);
        v.sprite_head_dir[i] +%= 1;
        a.Sprite_SetSpawnedCoordinates(sp, &info);
        a.Sprite_SetX(sp, info.r0_x +% 8);
        v.sprite_z_vel[ju] = 32;
        v.sprite_delay_aux4[ju] = 16;
        const pt = a.Sprite_ProjectSpeedTowardsLink(sp, 16);
        v.sprite_y_vel[ju] = ~pt.y;
        v.sprite_x_vel[ju] = ~pt.x;
        a.SpriteSfx_QueueSfx3WithPan(k, 0x30);
    }
}

pub export fn CoveredRupeeCrab_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    if (v.byte_7E0FC6.* >= 3)
        return;
    var oam = oamPtr();
    const r7: u8 = if (v.sprite_type[i] == 0x17) 2 else 0;
    const r6: usize = @as(usize, v.sprite_graphics[i]) * 2;
    var n: isize = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = @as(usize, @intCast(n)) + r6;
        const ch = t.kCoveredRupeeCrab_DrawChar[j];
        setOam(
            oam,
            info.x,
            info.y +% s16(t.kCoveredRupeeCrab_DrawY[j]),
            ch +% (if (ch == 0x44) r7 else 0),
            (info.flags & ~@as(u8, 1)) | t.kCoveredRupeeCrab_DrawFlags[j],
            2,
        );
    }
}

pub export fn Sprite_EC_ThrownItem(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.byte_7E0FC6.* < 3) {
        if (v.sort_sprites_setting.* != 0 and v.sprite_floor[i] != 0) {
            const spr_slot: u16 = 0x2c + @as(u16, @truncate(@as(u32, @bitCast(k)) & 3));
            v.oam_cur_ptr.* = 0x0800 + spr_slot * 4;
            v.oam_ext_cur_ptr.* = 0x0A20 + spr_slot;
        }
        v.sprite_ignore_projectile[i] = v.sprite_state[i];
        if (v.sprite_C[i] >= 6) {
            SpriteDraw_ThrownItem_Gigantic(k);
        } else {
            a.SpriteDraw_SingleLarge(k);
            const oam = oamPtr();
            const tt: u8 = v.player_is_indoors.* +% v.is_in_dark_world.*;
            const j: usize = v.sprite_C[i];
            oam[0].charnum = t.kThrowableScenery_Char[j + (if (tt >= 2) @as(usize, 6) else 0)];
            oam[0].flags = (oam[0].flags & 0xf0) | t.kThrowableScenery_Flags[j];
            v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & 0xc0) | (oam[0].flags & 0xf);
        }
    }
    if (v.sprite_state[i] == 9) {
        if (a.Sprite_ReturnIfInactive(k))
            return;
        a.ThrowableScenery_InteractWithSpritesAndTiles(k);
    }
}

pub export fn SpriteDraw_ThrownItem_Gigantic(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    v.sprite_oam_flags[i] = t.kThrowableScenery_DrawLarge_OamFlags[v.sprite_C[i] -% 6];

    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;

    var oam = oamPtr();
    var n: isize = 3;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = @intCast(n);
        setOam(
            oam,
            info.x +% @as(u16, @bitCast(t.kThrowableScenery_DrawLarge_X[j])),
            info.y +% @as(u16, @bitCast(t.kThrowableScenery_DrawLarge_Y[j])),
            0x4a,
            t.kThrowableScenery_DrawLarge_Flags[j] | info.flags,
            2,
        );
    }
    _ = a.Oam_AllocateFromRegionB(12);
    oam = oamPtr();
    info.y = a.Sprite_GetY(k) -% v.BG2VOFS_copy2.*;
    n = 2;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = @intCast(n);
        setOam(oam, info.x +% @as(u16, @bitCast(t.kThrowableScenery_DrawLarge_X2[j])), info.y +% 12, 0x6c, 0x24, 2);
    }
}

pub export fn ThrowableScenery_ScatterIntoDebris(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (!sign8(v.sprite_C[i]) and v.sprite_C[i] >= 6) {
        var n: isize = 3;
        while (n >= 0) : (n -= 1) {
            const m: usize = @intCast(n);
            var info: SpriteSpawnInfo = undefined;
            const j = a.Sprite_SpawnDynamically(k, 0xec, &info);
            if (j >= 0) {
                const ju = ix(j);
                v.sprite_z[ju] = v.sprite_z[i];
                a.Sprite_SetX(j, info.r0_x +% s16(t.kScatterDebris_X[m]));
                a.Sprite_SetY(j, info.r2_y +% s16(t.kScatterDebris_Y[m]));
                v.sprite_C[ju] = 1;
                a.Sprite_ScheduleForBreakage(j);
                v.sprite_oam_flags[ju] = if (v.sprite_C[i] < 7) 12 else 0;
            }
        }
        v.sprite_state[i] = 0;
    } else {
        v.sprite_state[i] = 0;
        var info: PrepOamCoordsRet = undefined;
        if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
            return;
        // `while (garnish_type[j--] && j >= 0) {}` then `j++`: the index is
        // decremented before the bounds test, so it never reads below zero.
        var j: isize = 29;
        while (true) {
            const cur = v.garnish_type[@intCast(j)];
            j -= 1;
            if (!(cur != 0 and j >= 0))
                break;
        }
        j += 1;
        const g: usize = @intCast(j);
        v.garnish_type[g] = 22;
        v.garnish_active.* = 22;
        v.garnish_x_lo[g] = v.sprite_x_lo[i];
        v.garnish_x_hi[g] = v.sprite_x_hi[i];
        const y = a.Sprite_GetY(k) -% v.sprite_z[i] +% 0x10;
        v.garnish_y_lo[g] = @truncate(y);
        v.garnish_y_hi[g] = @truncate(y >> 8);
        v.garnish_oam_flags[g] = info.flags;
        v.garnish_floor[g] = v.sprite_floor[i];
        v.garnish_countdown[g] = 31;
        v.garnish_sprite[g] = v.sprite_C[i];
    }
}

pub export fn Sprite_0B_Cucco(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_x_vel[i] != 0)
        v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0x40)) |
            (if (sign8(v.sprite_x_vel[i])) @as(u8, 0) else 0x40);

    a.SpriteDraw_SingleLarge(k);
    if (v.sprite_head_dir[i] != 0) {
        v.sprite_type[i] = 0x3d;
        a.SpritePrep_LoadProperties(k);
        v.sprite_subtype[i] +%= 1;
        v.sprite_delay_main[i] = 48;
        v.sound_effect_1.* = 21;
        v.sprite_ignore_projectile[i] = 21;
        return;
    }
    if (v.sprite_state[i] == 10) {
        v.sprite_ai_state[i] = 3;
        if (v.submodule_index.* == 0) {
            a.Chicken_IncrSubtype2(k, 3);
            a.Cucco_DrawPANIC(k);
            if (v.frame_counter.* & 0xf == 0)
                a.BawkBawk(k);
        }
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_C[i] != 0) {
        v.sprite_oam_flags[i] |= 0x10;
        a.Sprite_MoveXY(k);
        v.sprite_z[i] = 12;
        v.sprite_ignore_projectile[i] = 12;
        if ((k ^ @as(c_int, v.frame_counter.*)) & 7 == 0)
            _ = a.Sprite_CheckDamageToLink(k);
        a.Chicken_IncrSubtype2(k, 4);
    } else {
        v.sprite_health[i] = 255;
        if (v.sprite_B[i] >= 35)
            a.Cucco_SummonAvenger(k);
        if (v.sprite_F[i] != 0) {
            v.sprite_F[i] = 0;
            if (v.sprite_B[i] < 35) {
                v.sprite_B[i] +%= 1;
                a.BawkBawk(k);
            }
            v.sprite_ai_state[i] = 2;
        }
        _ = a.Sprite_CheckDamageFromLink(k);
        switch (v.sprite_ai_state[i]) {
            0 => a.Cucco_Calm(k),
            1 => a.Chicken_Hopping(k),
            2 => a.Cucco_Flee(k),
            3 => a.Cucco_Carried(k),
            else => {},
        }
    }
}

pub export fn StoryTeller_1_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    const j = @as(usize, v.sprite_subtype2[i]) * 2 + v.sprite_graphics[i];
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kStoryTeller_Dmd[j], 1, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_28_DarkWorldHintNPC(k: c_int) callconv(.c) void {
    const i = ix(k);
    StoryTeller_1_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (v.sprite_delay_main[i] == 0)
        v.sprite_graphics[i] = @truncate(v.frame_counter.* >> 4 & 1);

    switch (v.sprite_subtype2[i]) {
        0 => hintNpcCommon(k, 0xff),
        1 => hintNpcCommon(k, 0x101),
        2 => hintNpcCommon(k, 0x102),
        3 => {
            if (v.sprite_delay_main[i] == 0) {
                if (v.frame_counter.* & 0x3f == 0)
                    v.sprite_oam_flags[i] ^= 0x40;
                if (a.GetRandomNumber() == 0)
                    v.sprite_delay_main[i] = 32;
            }
            _ = a.Sprite_ShowSolicitedMessage(k, 0x149);
        },
        4 => {
            v.sprite_graphics[i] = @truncate(v.frame_counter.* >> 1 & 1);
            a.Sprite_MoveZ(k);
            if (sign8(v.sprite_z[i]))
                v.sprite_z[i] = 0;
            v.sprite_z_vel[i] +%= if (v.sprite_z[i] >= 4) @as(u8, 0xff) else 1;
            hintNpcCommon(k, 0x103);
        },
        else => {},
    }
}

/// Every hint NPC runs the same idle/pay/heal cycle; only the thank-you
/// message differs.

// ---------------------------------------------------------------------------
// from sprite_main_part20.zig
// ---------------------------------------------------------------------------
/// hud.zig keeps these file-local, so they need local copies.

pub export fn Sprite_2E_FluteKid(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_head_dir[i]) {
        0 => switch (v.sprite_subtype2[i]) {
            0 => FluteKid_Human(k),
            1 => Sprite_FluteKid_Stumpy(k),
            else => {},
        },
        1 => Sprite_FluteKid_Quaver(k),
        else => {},
    }
}

pub export fn FluteKid_Human(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_ai_state[i] != 3)
        v.sprite_C[i] = a.FluteBoy_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_C[i] == 0 and v.sprite_B[i] == 0) {
        v.sound_effect_ambient.* = 11;
        v.sprite_B[i] = 11;
    }
    v.sprite_graphics[i] = @truncate(v.frame_counter.* >> 5 & 1);
    switch (v.sprite_ai_state[i]) {
        0 => { // wait
            if (v.link_item_flute.* >= 2 or a.FluteBoy_CheckIfPlayerClose(k)) {
                v.sprite_ai_state[i] = 1;
                v.sprite_D[i] +%= 1;
                v.byte_7E0FDD.* +%= 1;
                v.sprite_delay_main[i] = 176;
                v.flag_is_link_immobilized.* = 1;
            }
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 25;
                FluteKid_SpawnQuaver(k);
            }
        },
        1 => { // prep phase out
            v.flag_is_link_immobilized.* = 1;
            if (v.sprite_delay_main[i] == 0) {
                v.TS_copy.* = 2;
                v.CGADSUB_copy.* = 48;
                v.palette_filter_countdown.* = (v.palette_filter_countdown.* & 0xff00);
                v.darkening_or_lightening_screen.* = (v.darkening_or_lightening_screen.* & 0xff00);
                a.Palette_AssertTranslucencySwap();
                v.sprite_ai_state[i] = 2;
                v.sound_effect_ambient.* = 128;
                a.SpriteSfx_QueueSfx2WithPan(k, 0x33);
            }
        },
        2 => { // phase out
            if (v.frame_counter.* & 15 == 0) {
                a.PaletteFilter_SP5F();
                if (@as(u8, @truncate(v.palette_filter_countdown.*)) == 0)
                    v.sprite_ai_state[i] = 3;
            }
        },
        3 => { // phased out
            a.PaletteFilter_RestoreSP5F();
            a.Palette_RevertTranslucencySwap();
            v.sprite_state[i] = 0;
            v.flag_is_link_immobilized.* = 0;
        },
        else => {},
    }
}

pub export fn Sprite_FluteKid_Stumpy(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.FluteAardvark_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => {
            switch (v.link_item_flute.* & 3) {
                0 => { // supplicate
                    if ((a.Sprite_ShowSolicitedMessage(k, 0xe5) & 0x100) != 0)
                        v.sprite_ai_state[i] = 1;
                },
                1 => _ = a.Sprite_ShowSolicitedMessage(k, 0xe8),
                2 => { // thanks
                    v.sprite_graphics[i] = 1;
                    if ((a.Sprite_ShowSolicitedMessage(k, 0xe9) & 0x100) != 0)
                        v.sprite_ai_state[i] = 3;
                },
                3 => v.sprite_graphics[i] = 3, // already did
                else => {},
            }
        },
        1 => {
            if (v.choice_in_multiselect_box.* == 0) {
                a.Sprite_ShowMessageUnconditional(0xe6);
                v.sprite_ai_state[i] = 2;
            } else {
                a.Sprite_ShowMessageUnconditional(0xe7);
                v.sprite_ai_state[i] = 0;
            }
        },
        2 => { // grant shovel
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(0x13, 0);
            v.sprite_ai_state[i] = 0;
        },
        3 => { // wait for music
            if (v.hud_cur_item.* == kHudItem_Flute and (v.joypad1H_last.* & 0x40) != 0) {
                v.sprite_ai_state[i] = 4;
                v.music_control.* = 0xf2;
                v.sound_effect_1.* = 0;
                v.sound_effect_ambient.* = 23;
                v.flag_is_link_immobilized.* +%= 1;
            }
        },
        4 => {
            if (v.sprite_delay_main[i] == 0) {
                if (v.sprite_A[i] >= 3)
                    a.SpriteSfx_QueueSfx2WithPan(k, 0x33);
                const j: usize = v.sprite_A[i];
                v.sprite_A[i] +%= 1;
                if (t.kFluteAardvark_Gfx[j] >= 0) {
                    v.sprite_graphics[i] = @bitCast(t.kFluteAardvark_Gfx[j]);
                    v.sprite_delay_main[i] = @bitCast(t.kFluteAardvark_Delay[j]);
                } else {
                    v.music_control.* = 0xf3;
                    v.sprite_ai_state[i] = 5;
                    v.flag_is_link_immobilized.* = 0;
                }
            }
        },
        5 => { // done
            v.sprite_graphics[i] = 3;
            v.sram_progress_indicator_3.* |= 8;
        },
        else => {},
    }
}

pub export fn Sprite_FluteKid_Quaver(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_MoveXY(k);
    a.Sprite_MoveZ(k);
    if (v.sprite_delay_main[i] == 0)
        v.sprite_state[i] = 0;
    if (v.frame_counter.* & 1 == 0)
        v.sprite_x_vel[i] +%= if (((v.frame_counter.* >> 5) ^ v.cur_object_index.*) & 1 != 0)
            @as(u8, 0xff)
        else
            1;
}

pub export fn FluteKid_SpawnQuaver(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x2e, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetX(j, info.r0_x +% 4);
        a.Sprite_SetY(j, info.r2_y -% 4);
        v.sprite_head_dir[ju] = 1;
        v.sprite_z_vel[ju] = 8;
        v.sprite_delay_main[ju] = 96;
        v.sprite_ignore_projectile[ju] = 96;
    }
}

pub export fn Sprite_1A_Smithy(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => a.Smithy_Main(k),
        1 => Smithy_Spark(k),
        2 => Smithy_Frog(k),
        3 => Smithy_Homecoming(k),
        else => {},
    }
}

pub export fn Smithy_Homecoming(k: c_int) callconv(.c) void {
    const i = ix(k);
    ReturningSmithy_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // ApproachTheBench
            a.Sprite_MoveXY(k);
            v.sprite_graphics[i] = @truncate(v.frame_counter.* >> 3 & 1);
            if (v.sprite_delay_main[i] != 0)
                return;
            const m: usize = v.sprite_A[i];
            v.sprite_A[i] +%= 1;
            v.sprite_delay_main[i] = @bitCast(t.kReturningSmithy_Delay[m]);
            const d = t.kReturningSmithy_Dir[m];
            if (d >= 0) {
                const du: usize = @intCast(d);
                v.sprite_D[i] = @intCast(d);
                v.sprite_x_vel[i] = @bitCast(t.kReturningSmithy_Xvel[du]);
                v.sprite_y_vel[i] = @bitCast(t.kReturningSmithy_Yvel[du]);
            } else {
                v.sprite_ai_state[i] = 1;
            }
        },
        1 => { // Thankful
            a.Sprite_BehaveAsBarrier(k);
            _ = a.Sprite_ShowSolicitedMessage(k, 0xe3);
            v.flag_is_link_immobilized.* = 0;
            v.sprite_D[i] = 1;
            v.sram_progress_indicator_3.* |= 32;
        },
        else => {},
    }
}

pub export fn Smithy_Frog(k: c_int) callconv(.c) void {
    const i = ix(k);
    SmithyFrog_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    v.sprite_z_vel[i] -%= 2;
    a.Sprite_MoveZ(k);
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = 16;
    }
    if (v.sprite_ai_state[i] == 0) {
        v.sprite_D[i] = 1;
        if ((a.Sprite_ShowSolicitedMessage(k, 0xe1) & 0x100) != 0)
            v.sprite_ai_state[i] = 1;
    } else {
        v.follower_indicator.* = 7;
        a.LoadFollowerGraphics();
        a.Sprite_BecomeFollower(k); // zelda bug: doesn't save X
        v.sprite_state[i] = 0;
    }
}

pub export fn ReturningSmithy_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = @as(usize, v.sprite_D[i]) * 2 + v.sprite_graphics[i];
    var info: PrepOamCoordsRet = undefined;
    v.dma_var7.* = (v.dma_var7.* & 0xff00) | t.kReturningSmithy_Dma[j];
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kReturningSmithy_Dmd[j], 1, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn SmithyFrog_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kSmithyFrog_Dmd[0], 1, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Smithy_ListenForHammer(k: c_int) callconv(.c) bool {
    const i = ix(k);
    return v.sprite_delay_aux1[i] == 0 and
        v.hud_cur_item.* == kHudItem_Hammer and
        (v.link_item_in_hand.* & 2) != 0 and
        v.player_handler_timer.* == 2 and
        a.Sprite_CheckDamageToLink_same_layer(k);
}

pub export fn Smithy_SpawnDwarfPal(k: c_int) callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x1a, &info);
    if (j < 0)
        return j;
    const ju = ix(j);
    a.Sprite_SetX(j, info.r0_x);
    a.Sprite_SetY(j, info.r2_y);
    v.sprite_x_lo[ju] +%= 0x2C;
    v.sprite_D[ju] = 1;
    v.sprite_A[ju] = 4;
    v.sprite_ignore_projectile[ju] = 4;
    return j;
}

pub export fn Smithy_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    const j = @as(usize, v.sprite_graphics[i]) * 4 + @as(usize, v.sprite_D[i]) * 2;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kSmithy_Dmd[j], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Smithy_Spark(k: c_int) callconv(.c) void {
    const i = ix(k);
    SmithySpark_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_delay_main[i] == 0) {
        const j: usize = v.sprite_A[i];
        v.sprite_A[i] = @truncate((j + 1) & 7);
        if (sign8(@bitCast(t.kSmithySpark_Gfx[j]))) {
            v.sprite_state[i] = 0;
            return;
        }
        v.sprite_graphics[i] = @bitCast(t.kSmithySpark_Gfx[j]);
        v.sprite_delay_main[i] = @bitCast(t.kSmithySpark_Delay[j]);
    }
}

pub export fn Smithy_SpawnSpark(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x1a, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetX(j, info.r0_x);
        a.Sprite_SetY(j, info.r2_y);
        v.sprite_x_lo[ju] +%= if (v.sprite_D[i] != 0) @as(u8, @bitCast(@as(i8, -15))) else 15;
        v.sprite_y_lo[ju] +%= 2;
        v.sprite_subtype2[ju] = 1;
    }
}

pub export fn SmithySpark_Draw(k: c_int) callconv(.c) void {
    _ = a.Oam_AllocateFromRegionB(8);
    a.Sprite_DrawMultiple(k, &t.kSmithySpark_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 2], 2, null);
}

pub export fn Sprite_1B_Arrow(k: c_int) callconv(.c) void {
    const i = ix(k);
    EnemyArrow_Draw(k);
    if (a.Sprite_ReturnIfPaused(k))
        return;
    if (v.sprite_state[i] == 9) {
        var j: u8 = v.sprite_delay_main[i];
        if (j != 0) {
            j -%= 1;
            if (j == 0) {
                v.sprite_state[i] = 0;
            } else if (j >= 32 and j & 1 == 0) {
                const m: usize = @as(usize, @truncate(v.frame_counter.* << 1 & 4)) | v.sprite_D[i];
                v.sprite_x_vel[i] = @bitCast(t.kEnemyArrow_Xvel[m]);
                v.sprite_y_vel[i] = @bitCast(t.kEnemyArrow_Yvel[m]);
                a.Sprite_MoveXY(k);
            }
            return;
        }
        _ = a.Sprite_CheckDamageToLink_same_layer(k);
        if (v.sprite_E[i] == 0 and a.Sprite_CheckTileCollision(k) != 0) {
            if (v.sprite_A[i] != 0) {
                a.SpriteSfx_QueueSfx2WithPan(k, 0x5);
                a.Sprite_ScheduleForBreakage(k);
                a.Sprite_PlaceWeaponTink(k);
            } else {
                v.sprite_delay_main[i] = 48;
                v.sprite_A[i] = 2;
                a.SpriteSfx_QueueSfx2WithPan(k, 0x8);
            }
        } else {
            a.Sprite_MoveXY(k);
        }
    } else {
        if (v.sprite_ai_state[i] == 0) {
            a.Sprite_ApplyRicochet(k);
            v.sprite_z_vel[i] = 24;
            v.sprite_delay_main[i] = 255;
            v.sprite_ai_state[i] +%= 1;
            v.sprite_hit_timer[i] = 0;
        }
        v.sprite_D[i] = t.kEnemyArrow_Dirs[v.sprite_delay_main[i] >> 3 & 3];
        a.Sprite_MoveZ(k);
        a.Sprite_MoveXY(k);
        v.sprite_z_vel[i] -%= 2;
        if (sign8(v.sprite_z[i]))
            v.sprite_state[i] = 0;
    }
}

pub export fn EnemyArrow_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = oamPtr();
    const r6: usize = @as(usize, v.sprite_D[i]) * 2;
    const r7: usize = @as(usize, v.sprite_A[i]) * 8;
    var n: isize = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = r6 + @as(usize, @intCast(n));
        setOam(
            oam,
            info.x +% @as(u16, @bitCast(t.kEnemyArrow_Draw_X[j])),
            info.y +% @as(u16, @bitCast(t.kEnemyArrow_Draw_Y[j])),
            t.kEnemyArrow_Draw_Char[j + r7],
            t.kEnemyArrow_Draw_Flags[j + r7] | info.flags,
            0,
        );
    }
}

pub export fn Sprite_1E_CrystalSwitch(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_oam_flags[i] = (v.sprite_oam_flags[i] & ~@as(u8, 0xe)) |
        t.kCrystalSwitchPal[v.orange_blue_barrier_state.* & 1];
    a.Oam_AllocateDeferToPlayer(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Sprite_NullifyHookshotDrag();
        v.link_speed_setting.* = 0;
        a.Sprite_RepelDash();
    }
    if (v.sprite_delay_main[i] == 0) {
        _ = a.Sprite_GarnishSpawn_Sparkle(k, v.frame_counter.* & 7, a.GetRandomNumber() & 7);
        v.sprite_delay_main[i] = 31;
    }
    if (v.sprite_F[i] == 0) {
        if (sign8(v.button_b_frames.* -% 9))
            _ = a.Sprite_CheckDamageFromLink(k);
    } else {
        const old = v.sprite_F[i];
        v.sprite_F[i] -%= 1;
        if (old == 11) {
            v.orange_blue_barrier_state.* ^= 1;
            v.submodule_index.* = 22;
            a.SpriteSfx_QueueSfx3WithPan(k, 0x25);
        }
    }
}

pub export fn Sprite_1F_SickKid(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.BugNetKid_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // resting
            if (a.Sprite_CheckIfLinkIsBusy() or !a.Sprite_CheckDamageToLink_same_layer(k))
                return;
            if ((v.link_bottle_info[0] | v.link_bottle_info[1] |
                v.link_bottle_info[2] | v.link_bottle_info[3]) < 2)
            {
                _ = a.Sprite_ShowSolicitedMessage(k, 0x104);
            } else {
                v.flag_is_link_immobilized.* +%= 1;
                v.sprite_ai_state[i] = 1;
            }
        },
        1 => { // perk
            if (v.sprite_delay_main[i] != 0)
                return;
            const j: usize = v.sprite_A[i];
            if (t.kBugNetKid_Gfx[j] >= 0) {
                v.sprite_graphics[i] = @bitCast(t.kBugNetKid_Gfx[j]);
                v.sprite_delay_main[i] = t.kBugNetKid_Delay[j];
                v.sprite_A[i] = @truncate(j + 1);
            } else {
                a.Sprite_ShowMessageUnconditional(0x105);
                v.sprite_ai_state[i] = 2;
            }
        },
        2 => { // grant
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(0x21, 0);
            v.flag_is_link_immobilized.* = 0;
            v.sprite_ai_state[i] = 3;
        },
        3 => { // back to rest
            v.sprite_graphics[i] = 1;
            _ = a.Sprite_ShowSolicitedMessage(k, 0x106);
        },
        else => {},
    }
}

pub export fn Sprite_21_WaterSwitch(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.PushSwitch_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_C[i] != 0) {
                v.sprite_B[i] -%= 1;
                if (v.sprite_B[i] == 0)
                    v.sprite_ai_state[i] = 1;
                if (v.frame_counter.* & 3 == 0)
                    a.SpriteSfx_QueueSfx2WithPan(k, 0x22);
            } else {
                v.sprite_B[i] = 48;
            }
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_A[i] +%= 1;
                const j: usize = v.sprite_A[i];
                if (j == 10) {
                    v.sprite_ai_state[i] = 2;
                    v.dung_flag_statechange_waterpuzzle.* +%= 1;
                    a.SpriteSfx_QueueSfx3WithPan(k, 0x25);
                } else {
                    v.sprite_delay_main[i] = t.kPushSwitch_Delay[j];
                    v.sprite_D[i] = t.kPushSwitch_Dir[j];
                    a.SpriteSfx_QueueSfx2WithPan(k, 0x22);
                }
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part21.zig
// ---------------------------------------------------------------------------
pub export fn SpritePrep_PotionShop(k: c_int) callconv(.c) void {
    MagicShopAssistant_SpawnPowder(k);
    MagicShopAssistant_SpawnGreenCauldron(k);
    MagicShopAssistant_SpawnBlueCauldron(k);
    MagicShopAssistant_SpawnRedCauldron(k);
    v.sprite_ignore_projectile[ix(k)] +%= 1;
}

pub export fn MagicShopAssistant_SpawnPowder(k: c_int) callconv(.c) void {
    if (v.flag_overworld_area_did_change.* == 0 or v.link_item_mushroom.* == 2)
        return;
    if (v.save_dung_info[0x109] & 0x80 != 0) {
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0xe9, &info);
        const ju = ix(j);
        v.sprite_subtype2[ju] = 1;
        a.Sprite_SetX(j, info.r0_x -% 16);
        a.Sprite_SetY(j, info.r2_y);
        v.sprite_flags4[ju] = 3;
        v.sprite_defl_bits[ju] |= 0x20;
    }
}

/// The three cauldron spawns differ only in subtype and offset. The C indexes
/// the spawned slot without checking for failure; kept as-is.

pub export fn MagicShopAssistant_SpawnGreenCauldron(k: c_int) callconv(.c) void {
    spawnCauldron(k, 2, -40, -72);
}

pub export fn MagicShopAssistant_SpawnBlueCauldron(k: c_int) callconv(.c) void {
    spawnCauldron(k, 3, 8, -72);
}

pub export fn MagicShopAssistant_SpawnRedCauldron(k: c_int) callconv(.c) void {
    spawnCauldron(k, 4, -88, -72);
}

pub export fn Sprite_E9_PotionShop(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => Sprite_MagicShopAssistant_Main(k),
        1 => Sprite_BagOfPowder(k),
        2 => Sprite_GreenCauldron(k),
        3 => Sprite_BlueCauldron(k),
        4 => Sprite_RedCauldron(k),
        else => {},
    }
}

pub export fn Sprite_BagOfPowder(k: c_int) callconv(.c) void {
    const i = ix(k);
    MagicPowderItem_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (!a.Sprite_CheckDamageToLink_same_layer(k) or (v.filtered_joypad_L.* & 0x80) == 0)
        return;
    a.Link_CancelDash();
    v.item_receipt_method.* = 0;
    a.Link_ReceiveItem(0xd, 0);
    v.sprite_state[i] = 0;
}

pub export fn MagicPowderItem_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kMagicPowder_Dmd[0], 2, null);
}

/// Shared tail of the three cauldrons: barrier, bottle check, price, bottle
/// space, then hand over the potion.

pub export fn Sprite_GreenCauldron(k: c_int) callconv(.c) void {
    GreenPotionItem_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    cauldronPurchase(k, 60, 0x2f);
}

pub export fn GreenPotionItem_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kGreenPotionItem_Dmd[0], 3, null);
}

pub export fn Sprite_BlueCauldron(k: c_int) callconv(.c) void {
    BluePotionItem_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    cauldronPurchase(k, 160, 0x30);
}

pub export fn BluePotionItem_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kBluePotionItem_Dmd[0], 4, null);
}

pub export fn Sprite_RedCauldron(k: c_int) callconv(.c) void {
    RedPotionItem_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    cauldronPurchase(k, 120, 0x2e);
}

pub export fn RedPotionItem_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kRedPotionItem_Dmd[0], 4, null);
}

pub export fn PotionCauldron_GoBeep(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx2WithPan(k, 0x3c);
}

pub export fn PotionCauldron_CheckBottles() callconv(.c) bool {
    return (v.link_bottle_info[0] | v.link_bottle_info[1] |
        v.link_bottle_info[2] | v.link_bottle_info[3]) >= 2;
}

pub export fn Sprite_MagicShopAssistant_Main(k: c_int) callconv(.c) void {
    const i = ix(k);
    Shopkeeper_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Sprite_BehaveAsBarrier(k);
    if (a.Sprite_CheckIfLinkIsBusy())
        return;
    if (v.sprite_ai_state[i] != 0) {
        v.link_hearts_filler.* = 160;
        v.sprite_ai_state[i] = 0;
    }
    v.sprite_graphics[i] = @truncate(v.frame_counter.* >> 5 & 1);
    const msg: u16 = if (v.link_bottle_info[0] >= 2 or v.link_bottle_info[1] >= 2 or
        v.link_bottle_info[2] >= 2 or v.link_bottle_info[3] >= 2 or
        v.flag_overworld_area_did_change.* == 0) 0x4e else 0x4d;
    if ((a.Sprite_ShowSolicitedMessage(k, msg) & 0x100) != 0)
        v.sprite_ai_state[i] = 1;
}

pub export fn Shopkeeper_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kShopkeeper_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 2], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Elder_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kElder_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 2], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn ElderWife_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kElderWife_Dmd[@as(usize, v.sprite_graphics[ix(k)]) * 2], 2, null);
}

pub export fn Sprite_Aginah(k: c_int) callconv(.c) void {
    const i = ix(k);
    // `goto default_msg` from the top test, and the final else falls into it.
    var use_default = (v.sram_progress_flags.* & 0x20) == 0;
    if (!use_default) {
        if (v.link_sword_type.* >= 2) {
            _ = a.Sprite_ShowSolicitedMessage(k, 0x128);
        } else if ((v.link_which_pendants.* & 7) == 7) {
            _ = a.Sprite_ShowSolicitedMessage(k, 0x126);
        } else if ((v.link_which_pendants.* & 2) != 0) {
            _ = a.Sprite_ShowSolicitedMessage(k, 0x129);
        } else if (v.link_item_book_of_mudora.* != 0) {
            _ = a.Sprite_ShowSolicitedMessage(k, 0x127);
        } else {
            use_default = true;
        }
    }
    if (use_default) {
        v.sram_progress_flags.* |= 0x20;
        _ = a.Sprite_ShowSolicitedMessage(k, 0x125);
    }
    v.sprite_graphics[i] = @truncate(v.frame_counter.* >> 5 & 1);
}

pub export fn Sprite_Sahasrahla(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_ai_state[i]) {
        0 => Sasha_Idle(k), // dialogue
        1 => { // mark map
            a.Sprite_ShowMessageUnconditional(0x33);
            v.sprite_ai_state[i] = 0;
            v.savegame_map_icons_indicator.* = 3;
        },
        2 => { // grant boots
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(0x4b, 0);
            v.sprite_ai_state[i] = 3;
            v.savegame_map_icons_indicator.* = 3;
        },
        3 => { // shamelessly promote ice rod
            a.Sprite_ShowMessageUnconditional(0x37);
            v.sprite_ai_state[i] = 0;
        },
        else => {},
    }
}

pub export fn Sasha_Idle(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.link_which_pendants.* & 4 == 0) {
        if ((a.Sprite_ShowSolicitedMessage(k, 0x32) & 0x100) != 0)
            v.sprite_ai_state[i] = 1;
    } else if (v.link_item_boots.* == 0) {
        const m: u16 = if (v.savegame_map_icons_indicator.* >= 3) 0x38 else 0x39;
        if ((a.Sprite_ShowSolicitedMessage(k, m) & 0x100) != 0)
            v.sprite_ai_state[i] = 2;
    } else if (v.link_item_ice_rod.* == 0) {
        _ = a.Sprite_ShowSolicitedMessage(k, 0x37);
    } else if ((v.link_which_pendants.* & 7) != 7) {
        _ = a.Sprite_ShowSolicitedMessage(k, 0x34);
    } else if (v.link_sword_type.* < 2) {
        _ = a.Sprite_ShowSolicitedMessage(k, 0x30);
    } else {
        _ = a.Sprite_ShowSolicitedMessage(k, 0x31);
    }
    v.sprite_graphics[i] = @truncate(v.frame_counter.* >> 5 & 1);
}

pub export fn Sprite_DustCloud(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.DustCloud_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (v.sprite_delay_main[i] != 0)
        return;
    v.sprite_delay_main[i] = 5;
    if (!sign8(t.kDustCloud_Gfx[v.sprite_A[i]])) {
        v.sprite_graphics[i] = t.kDustCloud_Gfx[v.sprite_A[i]];
        v.sprite_A[i] +%= 1;
    } else {
        v.sprite_state[i] = 0;
    }
}

pub export fn Sprite_SpawnDustCloud(k: c_int) callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xF2, &info);
    if (j >= 0) {
        info.r2_y +%= a.GetRandomNumber() & 15;
        info.r0_x +%= (a.GetRandomNumber() & 15) -% 8;
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_subtype2[ix(j)] = 1;
    }
    return j;
}

pub export fn FakeSword_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kFakeSword_Dmd[0], 2, null);
}

pub export fn SpritePrep_HeartContainer(k: c_int) callconv(.c) void {
    a.HeartUpgrade_CheckIfAlreadyObtained(k);
}

pub export fn HeartUpgrade_SetObtainedFlag(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.player_is_indoors.* == 0) {
        v.save_ow_event_info[@as(u8, @truncate(v.overworld_screen_index.*))] |= 0x40;
    } else {
        v.dung_savegame_state_bits.* |= if (v.sprite_x_hi[i] & 1 != 0) @as(u16, 0x2000) else 0x4000;
    }
}

pub export fn Sprite_HeartPiece(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_ai_state[i] == 0) {
        v.sprite_ai_state[i] +%= 1;
        a.HeartUpgrade_CheckIfAlreadyObtained(k);
        if (v.sprite_state[i] == 0)
            return;
    }
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    if (a.Sprite_CheckIfLinkIsBusy())
        return;

    if (a.Sprite_CheckTileCollision(k) & 3 != 0)
        v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];

    v.sprite_z_vel[i] -%= 1;
    a.Sprite_MoveZ(k);
    a.Sprite_MoveXY(k);
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = ((v.sprite_z_vel[i] ^ 255) & 248) >> 1;
        v.sprite_x_vel[i] = @bitCast(@as(i8, @bitCast(v.sprite_x_vel[i])) >> 1);
    }

    if (v.sprite_delay_aux4[i] != 0 or !a.Sprite_CheckDamageToLink_same_layer(k))
        return;

    v.link_heart_pieces.* = (v.link_heart_pieces.* +% 1) & 3;
    if (v.link_heart_pieces.* == 0) {
        a.Link_CancelDash();
        v.item_receipt_method.* = 0;
        a.Link_ReceiveItem(0x26, 0);
    } else {
        a.SpriteSfx_QueueSfx3WithPan(k, 0x2d);
        a.Sprite_ShowMessageUnconditional(t.kHeartPieceMsg[v.link_heart_pieces.*]);
    }
    v.sprite_state[i] = 0;
    HeartUpgrade_SetObtainedFlag(k);
}

// ---------------------------------------------------------------------------
// from sprite_main_part22.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_41_BlueGuard(k: c_int) callconv(.c) void {
    if (v.sprite_C[ix(k)] != 0) {
        Probe(k);
    } else {
        Guard_Main(k);
    }
}

pub export fn Probe(k: c_int) callconv(.c) void {
    const i = ix(k);
    // The C sign-extends each velocity byte through int8 before widening.
    a.SpriteAddXY(k, @as(i8, @bitCast(v.sprite_x_vel[i])), @as(i8, @bitCast(v.sprite_y_vel[i])));
    var is_close: bool = undefined;
    const parent: usize = v.sprite_C[i] -% 1;
    if (v.sprite_type[parent] == 0xce) {
        // parent is blind the thief?
        const x = v.cur_sprite_x.* -% v.link_x_coord.* +% 16;
        const y = v.link_y_coord.* -% v.cur_sprite_y.* +% 24;
        is_close = (x < 32 and y < 32);
    } else {
        if ((a.Probe_CheckTileSolidity(k) and v.sprite_tiletype.* != 9) or v.link_cape_mode.* != 0) {
            v.sprite_state[i] = 0;
            return;
        }
        const x = v.cur_sprite_x.* -% v.link_x_coord.*;
        const y = v.cur_sprite_y.* -% v.link_y_coord.*;
        is_close = (x < 16 and y < 16 and v.sprite_floor[i] == v.link_is_on_lower_level.*);
    }
    if (is_close) {
        if (v.sprite_ai_state[parent] != 3) {
            v.sprite_ai_state[parent] = 3;
            if (v.sprite_type[parent] != 0xce) {
                v.sprite_delay_main[parent] = 16;
                v.sprite_subtype2[parent] = 0;
            }
        }
        v.sprite_state[i] = 0;
    } else {
        var oam: PrepOamCoordsRet = undefined;
        if (a.Sprite_PrepOamCoordOrDoubleRet(k, &oam))
            return;
        if ((oam.x | oam.y) >= 256)
            v.sprite_state[i] = 0;
    }
}

pub export fn Guard_Main(k: c_int) callconv(.c) void {
    const i = ix(k);
    const bak1 = v.sprite_graphics[i];
    const bak2 = v.sprite_D[i];

    if (v.sprite_delay_aux1[i] != 0) {
        v.sprite_D[i] = t.kSoldier_DirectionLockSettings[bak2];
        v.sprite_graphics[i] = t.kSoldier_Gfx[bak2];
    }
    Guard_HandleAllAnimation(k);
    v.sprite_D[i] = bak2;
    v.sprite_graphics[i] = bak1;

    if (v.sprite_state[i] == 5) {
        if (v.submodule_index.* == 0) {
            v.sprite_subtype2[i] +%= 1;
            Guard_TickAndUpdateBody(k);
            v.sprite_subtype2[i] +%= 1;
            Guard_TickAndUpdateBody(k);
        }
        return;
    }
    if (a.Sprite_ReturnIfInactive(k))
        return;
    a.Guard_ParrySwordAttacks(k);
    if ((a.Sprite_CheckDamageToLink(k) or v.sprite_alert_flag.* != 0) and v.sprite_ai_state[i] < 3) {
        v.sprite_ai_state[i] = 3;
        Guard_SetTimerAndAssertTileHitBox(k, 0x20);
    } else if (v.sprite_F[i] != 0 and v.sprite_F[i] >= 4) {
        v.sprite_ai_state[i] = 4;
        Guard_SetTimerAndAssertTileHitBox(k, 0x80);
    }
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    if ((v.sprite_subtype[i] & 7) < 5) {
        if (v.sprite_wallcoll[i] == 0)
            a.Sprite_MoveXY(k);
        _ = a.Sprite_CheckTileCollision(k);
    } else {
        a.Sprite_MoveXY(k);
    }
    if (v.sprite_ai_state[i] != 4)
        v.sprite_G[i] = 0;

    switch (v.sprite_ai_state[i]) {
        0 => {
            a.Sprite_ZeroVelocity_XY(k);
            if (v.sprite_delay_main[i] != 0)
                return;
            v.sprite_ai_state[i] +%= 1;
            if (v.sprite_subtype[i] != 0 and (v.sprite_subtype[i] & 7) < 5) {
                v.sprite_delay_main[i] = t.kSoldier_Delay[v.sprite_subtype[i] >> 3 & 3];
                v.sprite_D[i] ^= 1;
                v.sprite_subtype2[i] = 0;
            } else {
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 0x3f) +% 0x28; // note: adc
                const old = v.sprite_D[i];
                const nd = a.GetRandomNumber() & 3;
                v.sprite_D[i] = nd;
                if (old == nd or ((old ^ nd) & 2) != 0)
                    return;
            }
            v.sprite_delay_aux1[i] = 12;
        },
        1 => {
            Sprite_Guard_SendOutProbe(k);
            if ((v.sprite_subtype[i] & 7) >= 5) {
                Guard_ShootProbeAndStuff(k);
                return;
            }
            if (v.sprite_delay_main[i] == 0) {
                a.Sprite_ZeroVelocity_XY(k);
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 160;
                return;
            }
            if (v.sprite_subtype2[i] & 1 == 0)
                v.sprite_delay_main[i] +%= 1;
            if (v.sprite_wallcoll[i] & 0xf != 0) {
                v.sprite_D[i] ^= 1;
                Guard_SetGlanceTo12(k);
            }
            const dir: usize = v.sprite_D[i];
            v.sprite_x_vel[i] = @bitCast(t.kSoldier_Xvel[dir]);
            v.sprite_y_vel[i] = @bitCast(t.kSoldier_Yvel[dir]);
            v.sprite_head_dir[i] = @truncate(dir);
            Guard_TickAndUpdateBody(k);
        },
        2 => {
            a.Sprite_ZeroVelocity_XY(k);
            Sprite_Guard_SendOutProbe(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 0x20;
                v.sprite_ai_state[i] = 0;
            } else if (v.sprite_delay_main[i] < 0x80) {
                const m: usize = (@as(usize, v.sprite_D[i]) * 8) | (v.sprite_delay_main[i] >> 3 & 7);
                v.sprite_head_dir[i] = t.kSoldier_HeadDirs[m];
            }
        },
        3 => {
            a.Sprite_ZeroVelocity_XY(k);
            v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 4;
                Guard_SetTimerAndAssertTileHitBox(k, 255);
            }
        },
        4 => {
            if (v.sprite_delay_main[i] != 0) {
                Soldier_Func12(k);
            } else {
                v.sprite_anim_clock[i] = t.kSoldier_Tab1[v.sprite_D[i]];
                a.Sprite_ZeroVelocity_XY(k);
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 160;
            }
        },
        else => {},
    }
}

pub export fn Guard_SetGlanceTo12(k: c_int) callconv(.c) void {
    v.sprite_delay_aux1[ix(k)] = 12;
}

pub export fn Guard_ShootProbeAndStuff(k: c_int) callconv(.c) void {
    const i = ix(k);
    var m: usize = v.sprite_B[i];
    v.sprite_x_vel[i] = @bitCast(t.kSoldierB_Xvel[m]);
    v.sprite_y_vel[i] = @bitCast(t.kSoldierB_Yvel[m]);
    _ = a.Sprite_CheckTileCollision(k);
    if (v.sprite_delay_aux2[i] != 0) {
        if (v.sprite_delay_aux2[i] == 44) {
            v.sprite_B[i] = t.kSoldierB_NextB[m];
            m = v.sprite_B[i];
        }
    } else if (v.sprite_wallcoll[i] & t.kSoldierB_Mask[m] == 0) {
        v.sprite_delay_aux2[i] = 88;
    }
    if (v.sprite_wallcoll[i] & t.kSoldierB_Mask2[m] != 0) {
        v.sprite_B[i] = t.kSoldierB_NextB2[m];
        m = v.sprite_B[i];
    }
    v.sprite_x_vel[i] = @bitCast(t.kSoldierB_Xvel2[m]);
    v.sprite_y_vel[i] = @bitCast(t.kSoldierB_Yvel2[m]);
    v.sprite_D[i] = t.kSoldierB_Dir[m];
    v.sprite_head_dir[i] = v.sprite_D[i];
    Guard_TickAndUpdateBody(k);
}

pub export fn Guard_TickAndUpdateBody(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_subtype2[i] +%= 1;
    const m: usize = @as(usize, v.sprite_D[i]) * 4 + (v.sprite_subtype2[i] >> 3 & 3);
    v.sprite_graphics[i] = t.kSoldier_Gfx2[m];
}

pub export fn Guard_SetTimerAndAssertTileHitBox(k: c_int, arg: u8) callconv(.c) void {
    const i = ix(k);
    v.sprite_delay_main[i] = arg;
    v.sprite_subtype[i] = 0;
    v.sprite_flags[i] = (v.sprite_flags[i] & 0xf) | 0x60;
}

pub export fn Soldier_Func12(k: c_int) callconv(.c) void {
    const i = ix(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 0x1f == 0) {
        if (v.sprite_G[i] == 0) {
            v.sprite_G[i] = 1;
            a.SpriteSfx_QueueSfx3WithPan(k, 4);
        }
        a.Sprite_ApplySpeedTowardsLink(k, 16);
        v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
        v.sprite_head_dir[i] = v.sprite_D[i];
    }
    Guard_ApplySpeedInDirection(k);
    v.sprite_subtype2[i] +%= 1;
    Guard_TickAndUpdateBody(k);
}

pub export fn Guard_ApplySpeedInDirection(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_wallcoll[i] == 0)
        return;
    const m: usize = if (v.sprite_wallcoll[i] & 3 != 0)
        2 + @as(usize, a.Sprite_IsBelowLink(k).a)
    else
        a.Sprite_IsRightOfLink(k).a;
    v.sprite_x_vel[i] = @bitCast(t.kSoldier_SetTowardsVel[m]);
    v.sprite_y_vel[i] = @bitCast(t.kSoldier_SetTowardsVel[m + 2]);
}

pub export fn Sprite_Guard_SendOutProbe(k: c_int) callconv(.c) void {
    const i = ix(k);
    if ((((k +% @as(c_int, v.frame_counter.*)) & 3) | @as(c_int, v.sprite_pause[i])) != 0)
        return;
    const clock = v.sprite_anim_clock[i];
    v.sprite_anim_clock[i] +%= 1;
    const r15: u8 = ((clock & 0x1f) +% t.kSprite_SpawnProbeStaggered_Tab[v.sprite_D[i]]) & 0x3f;
    Sprite_SpawnProbeAlways(k, r15);
}

pub export fn Sprite_SpawnProbeAlways(k: c_int, r15: u8) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamicallyEx(k, 0x41, &info, 10);
    if (j < 0)
        return;
    const ju = ix(j);
    var p = info.r0_x +% 8;
    v.sprite_x_lo[ju] = @truncate(p);
    v.sprite_x_hi[ju] = @truncate(p >> 8);
    p = info.r2_y +% 4;
    v.sprite_y_lo[ju] = @truncate(p);
    v.sprite_y_hi[ju] = @truncate(p >> 8);
    v.sprite_D[ju] = r15;
    v.sprite_x_vel[ju] = @bitCast(t.kSpawnProbe_Xvel[r15]);
    v.sprite_y_vel[ju] = @bitCast(t.kSpawnProbe_Yvel[r15]);
    v.sprite_flags2[ju] = (v.sprite_flags2[ju] & 0xf0) | 0xa0;
    v.sprite_C[ju] = @truncate(@as(u32, @bitCast(k +% 1)));
    v.sprite_ignore_projectile[ju] = v.sprite_C[ju];
    v.sprite_flags4[ju] = 0x40;
    v.sprite_flags3[ju] = 0x40;
    v.sprite_defl_bits[ju] = 2;
}

pub export fn Guard_HandleAllAnimation(k: c_int) callconv(.c) void {
    const i = ix(k);
    var poc: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &poc))
        return;
    Guard_AnimateHead(k, 0, &poc);
    Guard_AnimateBody(k, t.kSoldier_Draw2_OamIdx[v.sprite_D[i]] >> 2, &poc);
    Guard_AnimateWeapon(k, &poc);
    if (v.sprite_flags3[i] & 0x10 != 0)
        a.SpriteDraw_Shadow_custom(k, &poc, t.kSoldier_DrawShadow[v.sprite_D[i]]);
}

pub export fn Guard_AnimateHead(k: c_int, oam_offs: c_int, poc: *const PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    const oam = oamPtr() + ix(oam_offs);
    const dir: usize = v.sprite_head_dir[i];
    setOam(
        oam,
        poc.x,
        poc.y -% s16(t.kSoldier_Draw1_Yd[v.sprite_graphics[i]]),
        t.kSoldier_Draw1_Char[dir],
        t.kSoldier_Draw1_Flags[dir] | poc.flags,
        2,
    );
}

pub export fn Guard_AnimateBody(k: c_int, oam_idx: c_int, poc: *const PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    const g: usize = @as(usize, v.sprite_graphics[i]) * 4;
    const ty = v.sprite_type[i];
    var oam = oamPtr() + ix(oam_idx);
    var n: isize = 3;
    while (n >= 0) : (n -= 1) {
        const m: usize = @intCast(n);
        const j: usize = m + g;
        // `&&` binds tighter than `||` here.
        if (ty >= 0x46 and (t.kSoldier_Draw2_Big[j] == 0 or
            (m == 3 and t.kSoldier_Draw2_Char[j] == 0x20)))
            continue;
        var flags = t.kSoldier_Draw2_Flags[j] | poc.flags;
        if (t.kSoldier_Draw2_Char[j] == 0x20) {
            flags = (flags & 0xf1) | 2;
        } else if (t.kSoldier_Draw2_Big[j] == 0) {
            flags = (flags & 0xf1) | 8;
        }
        setOam(
            oam,
            poc.x +% s16(t.kSoldier_Draw2_Xd[j]),
            poc.y +% s16(t.kSoldier_Draw2_Yd[j]),
            t.kSoldier_Draw2_Char[j],
            flags,
            t.kSoldier_Draw2_Big[j],
        );
        if (oam[0].charnum == 0x20 and ty == 0x46)
            oam[0].y = 0xf0;
        oam += 1;
    }
}

pub export fn Guard_AnimateWeapon(k: c_int, poc: *const PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    const oam_idx: usize = t.kSoldier_Draw3_OamIdx[v.sprite_D[i]] >> 2;
    const g: usize = @as(usize, v.sprite_graphics[i]) * 2;
    const ty = v.sprite_type[i];
    var oam = oamPtr() + oam_idx;
    var n: isize = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = @as(usize, @intCast(n)) + g;
        v.dungmap_var8.* = (@as(u16, @bitCast(@as(i16, t.kSoldier_Draw3_Xd[j]))) << 8) |
            @as(u8, @bitCast(t.kSoldier_Draw3_Yd[j]));
        setOam(
            oam,
            poc.x +% s16(t.kSoldier_Draw3_Xd[j]),
            poc.y +% s16(t.kSoldier_Draw3_Yd[j]),
            t.kSoldier_Draw3_Char[j] +% (if (ty < 0x43) @as(u8, 3) else 0),
            t.kSoldier_Draw3_Flags[j] | poc.flags,
            0,
        );
    }
}

pub export fn Sprite_45_HogSpearMan(k: c_int) callconv(.c) void {
    const i = ix(k);
    Guard_HandleAllAnimation(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    BoltGuard_TriggerChaseTheme(k);
    a.Guard_ParrySwordAttacks(k);
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    if (v.sprite_wallcoll[i] == 0)
        a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckTileCollision(k);
    _ = a.Sprite_CheckDamageToLink(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 15 == 0) {
        v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
        v.sprite_head_dir[i] = v.sprite_D[i];
        a.Sprite_ApplySpeedTowardsLink(k, 18);
        Guard_ApplySpeedInDirection(k);
    }
    v.sprite_subtype2[i] +%= 1;
    Guard_TickAndUpdateBody(k);
}

pub export fn BoltGuard_TriggerChaseTheme(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_G[i] != 16) {
        const old = v.sprite_G[i];
        v.sprite_G[i] +%= 1;
        if (old == 15) {
            a.SpriteSfx_QueueSfx3WithPan(k, 0x4);
            if (v.sram_progress_indicator.* == 2 and
                @as(u8, @truncate(v.overworld_area_index.*)) == 24)
                v.music_control.* = 12;
        }
    }
}

pub export fn Sprite_44_BluesainBolt(k: c_int) callconv(.c) void {
    const i = ix(k);
    PsychoTrooper_Draw(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;
    BoltGuard_TriggerChaseTheme(k);
    a.Guard_ParrySwordAttacks(k);
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    if (v.sprite_wallcoll[i] == 0)
        a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckTileCollision(k);
    _ = a.Sprite_CheckDamageToLink(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 15 == 0) {
        v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
        v.sprite_head_dir[i] = v.sprite_D[i];
        a.Sprite_ApplySpeedTowardsLink(k, 18);
        Guard_ApplySpeedInDirection(k);
    }
    v.sprite_subtype2[i] +%= 1;
    const m: usize = (v.sprite_subtype2[i] >> 1 & 7) | (@as(usize, v.sprite_D[i]) << 3);
    v.sprite_graphics[i] = t.kFlailTrooperGfx[m];
}

pub export fn PsychoTrooper_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    a.SpriteDraw_GuardHead(k, &info, 3);
    a.SpriteDraw_BNCBody(k, &info, 2);
    SpriteDraw_GuardSpear(k, &info, 0);
    if (v.sprite_flags3[i] & 0x10 != 0)
        a.SpriteDraw_Shadow_custom(k, &info, t.kSoldier_DrawShadow[v.sprite_D[i]]);
}

pub export fn SpriteDraw_GuardSpear(k: c_int, info: *PrepOamCoordsRet, spr_offs: c_int) callconv(.c) void {
    const i = ix(k);
    var oam = oamPtr() + ix(spr_offs);
    const r6: usize = @as(usize, v.sprite_D[i]) * 4 + (((v.sprite_A[i] ^ 1) << 1) & 2);
    var n: isize = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j: usize = r6 + @as(usize, @intCast(n));
        const x = info.x +% s16(t.kSolderThrowing_Draw_X[j]);
        const y = info.y +% s16(t.kSolderThrowing_Draw_Y[j]);
        v.dungmap_var8.* = (@as(u16, @as(u8, @bitCast(t.kSolderThrowing_Draw_X[j]))) << 8) |
            @as(u8, @bitCast(t.kSolderThrowing_Draw_Y[j]));
        setOam(
            oam,
            x,
            y,
            t.kSolderThrowing_Draw_Char[j] -% (if (v.sprite_type[i] >= 0x48) @as(u8, 3) else 0),
            ((t.kSolderThrowing_Draw_Flags[j] | info.flags) & 0xf1) | 8,
            0,
        );
    }
}

pub export fn Sprite_48_RedJavelinGuard(k: c_int) callconv(.c) void {
    const i = ix(k);
    const bak0 = v.sprite_graphics[i];
    const j: usize = v.sprite_D[i];
    if (v.sprite_delay_aux1[i] != 0) {
        v.sprite_D[i] = t.kSoldier_DirectionLockSettings[j];
        v.sprite_graphics[i] = t.kJavelinTrooper_Gfx[j];
    }
    a.JavelinTrooper_Draw(k);
    v.sprite_D[i] = @truncate(j);
    v.sprite_graphics[i] = bak0;
    SoldierThrowing_Common(k);
}

pub export fn Sprite_46_BlueArcher(k: c_int) callconv(.c) void {
    const i = ix(k);
    const bak0 = v.sprite_graphics[i];
    const j: usize = v.sprite_D[i];
    if (v.sprite_delay_aux1[i] != 0) {
        v.sprite_D[i] = t.kSoldier_DirectionLockSettings[j];
        v.sprite_graphics[i] = t.kSoldier_Gfx[j];
    }
    a.ArcherSoldier_Draw(k);
    v.sprite_D[i] = @truncate(j);
    v.sprite_graphics[i] = bak0;
    SoldierThrowing_Common(k);
}

/// The `agitated_jump_to` label, shared by the walking and agitated states.

pub export fn SoldierThrowing_Common(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfInactive(k))
        return;

    if ((a.Sprite_CheckDamageToAndFromLink(k) or v.sprite_alert_flag.* != 0) and
        v.sprite_ai_state[i] < 3)
    {
        v.sprite_ai_state[i] = 3;
        v.sprite_delay_main[i] = 32;
    }
    if (v.sprite_F[i] >= 4) {
        v.sprite_ai_state[i] = 4;
        v.sprite_delay_main[i] = 60;
        v.sprite_subtype2[i] = 0;
    }
    if (a.Sprite_ReturnIfRecoiling(k))
        return;
    if (v.sprite_wallcoll[i] == 0)
        a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckTileCollision(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // resting
            a.Sprite_ZeroVelocity_XY(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 0x50 +% (a.GetRandomNumber() & 0x7f);
                const jbak = v.sprite_D[i];
                v.sprite_D[i] = a.GetRandomNumber() & 3;
                if (v.sprite_D[i] != jbak and ((v.sprite_D[i] ^ jbak) & 2) == 0)
                    v.sprite_delay_aux1[i] = 12;
            }
        },
        1 => { // walking
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 160;
                return;
            }
            Sprite_Guard_SendOutProbe(k);
            if (v.sprite_wallcoll[i] & 0xf != 0) {
                v.sprite_D[i] ^= 1;
                Guard_SetGlanceTo12(k);
            }
            const d: usize = v.sprite_D[i];
            v.sprite_x_vel[i] = @bitCast(t.kSoldier_Xvel[d]);
            v.sprite_y_vel[i] = @bitCast(t.kSoldier_Yvel[d]);
            v.sprite_head_dir[i] = @truncate(d);
            soldierThrowingAnim(k);
        },
        2 => { // looking
            a.Sprite_ZeroVelocity_XY(k);
            Sprite_Guard_SendOutProbe(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 32;
                v.sprite_ai_state[i] = 0;
            } else if (v.sprite_delay_main[i] < 0x80) {
                const m: usize = (@as(usize, v.sprite_D[i]) * 8) | (v.sprite_delay_main[i] >> 3 & 7);
                v.sprite_head_dir[i] = t.kSoldier_HeadDirs[m];
            }
        },
        3 => { // noticed player
            a.Sprite_ZeroVelocity_XY(k);
            v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 60;
                v.sprite_subtype2[i] = 0;
            }
        },
        4 => { // agitated
            var d: usize = v.sprite_D[i];
            if ((v.sprite_wallcoll[i] & t.kSolderThrowing_DirFlags[d]) != 0 or
                v.sprite_delay_main[i] == 0)
            {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 24;
                return;
            }
            if (((@as(c_int, v.frame_counter.*) ^ k) & 7) == 0) {
                v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
                v.sprite_head_dir[i] = v.sprite_D[i];
                d = v.sprite_D[i];
                if (v.sprite_type[i] == 0x48)
                    d += 4;
                const x = v.link_x_coord.* +% s16(t.kSolderThrowing_Xd[d]);
                const y = v.link_y_coord.* +% s16(t.kSolderThrowing_Yd[d]);
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 24);
                v.sprite_x_vel[i] = pt.x;
                v.sprite_y_vel[i] = pt.y;
                if (pt.xdiff +% 6 < 12 and pt.ydiff +% 6 < 12) {
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_delay_main[i] = 24;
                    return;
                }
            }
            v.sprite_subtype2[i] +%= 1;
            soldierThrowingAnim(k);
        },
        5 => { // attack
            v.sprite_anim_clock[i] = t.kSoldier_Tab1[v.sprite_D[i]];
            a.Sprite_ZeroVelocity_XY(k);
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 160;
                return;
            }
            v.sprite_subtype2[i] = if (j >= 40) 255 else 0;
            if (j == 12)
                a.Guard_LaunchProjectile(k);
            const m: usize = @as(usize, v.sprite_D[i]) * 8 + (j >> 3) +
                (if (v.sprite_type[i] == 0x48) @as(usize, 32) else 0);
            v.sprite_graphics[i] = t.kJavelinTrooper_Tab2[m];
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part23.zig
// ---------------------------------------------------------------------------
// ChainBallMult is `static` in the C, so it is absent from the ABI header and
// has to come from the module that ported it.

/// The tail shared by the `attack_common` label in Sprite_6A_BallNChain.

pub export fn Sprite_6A_BallNChain(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.ChainBallTrooper_Draw(k);
    if (v.sprite_ai_state[i] < 2)
        v.dungmap_var8.* = (v.dungmap_var8.* & 0x00ff) | 0x8000;
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Guard_ParrySwordAttacks(k);

    var tv: u16 = (@as(u16, v.sprite_B[i]) << 8) | v.sprite_A[i];
    tv +%= @as(u16, t.kChainBallTrooper_Tab1[v.sprite_ai_state[i]]);
    v.sprite_A[i] = @truncate(tv);
    v.sprite_B[i] = @truncate(tv >> 8 & 1);
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckTileCollision(k);
    a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckDamageToLink(k);

    var pt: PointU8 = .{ .x = 0, .y = 0 };

    if ((k ^ @as(c_int, v.frame_counter.*)) & 0xf == 0)
        v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, &pt);

    switch (v.sprite_ai_state[i]) {
        0 => {
            if ((k ^ @as(c_int, v.frame_counter.*)) & 0xf == 0) {
                v.sprite_D[i] = v.sprite_head_dir[i];
                if (pt.y +% 0x40 < 0x68 and pt.x +% 0x30 < 0x60) {
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_delay_main[i] = 24;
                    return;
                }
                a.Sprite_ApplySpeedTowardsLink(k, 8);
            }
            BallNChain_Animate(k);
        },
        1 => {
            a.Sprite_ZeroVelocity_XY(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 48;
                v.sprite_ai_state[i] +%= 1;
            }
        },
        2 => {
            if (v.sprite_delay_main[i] == 0 and
                v.sprite_head_dir[i] == t.kFlailTrooperAttackDir[@as(usize, v.sprite_A[i] >> 7 & 1) + @as(usize, v.sprite_B[i]) * 2])
            {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_aux2[i] = 31;
            }
            ballNChainAttackCommon(k);
        },
        3 => {
            a.Sprite_ZeroVelocity_XY(k);
            const d = v.sprite_delay_aux2[i];
            if (d == 0) {
                v.sprite_ai_state[i] = 0;
            } else if (d >= 0x10) {
                ballNChainAttackCommon(k);
                return;
            }
            v.sprite_subtype2[i] +%= 1;
            BallNChain_Animate(k);
        },
        else => {},
    }
}

pub export fn BallNChain_Animate(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = t.kFlailTrooperGfx[@as(usize, v.sprite_D[i]) * 8 + (v.sprite_subtype2[i] >> 2 & 7)];
}

pub export fn SpriteDraw_GuardHead(k: c_int, info: *PrepOamCoordsRet, spr_offs: c_int) callconv(.c) void {
    const j: usize = v.sprite_head_dir[ix(k)];
    const oam = oamPtr() + ix(spr_offs);
    setOam(oam, info.x, info.y -% 9, t.kChainBallTrooperHead_Char[j], info.flags | t.kChainBallTrooperHead_Flags[j], 2);
}

pub export fn SpriteDraw_BNCBody(k: c_int, info: *PrepOamCoordsRet, spr_offs: c_int) callconv(.c) void {
    const g: usize = v.sprite_graphics[ix(k)];
    var oam = oamPtr() + ix(spr_offs + @as(c_int, t.kFlailTrooperBody_SprOffs[g] >> 2));
    var n: c_int = t.kFlailTrooperBody_Num[g];
    while (true) {
        const j = g * 3 + ix(n);
        setOam(
            oam,
            info.x +% s16(t.kFlailTrooperBody_X[j]),
            info.y +% s16(t.kFlailTrooperBody_Y[j]),
            t.kFlailTrooperBody_Char[j],
            info.flags | t.kFlailTrooperBody_Flags[j],
            t.kFlailTrooperBody_Big[j],
        );
        if (n == 2) oam += 1;
        oam += 1;
        n -= 1;
        if (n < 0) break;
    }
}

pub export fn SpriteDraw_BNCFlail(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    var oam = oamPtr();

    // BYTE(dungmap_var7) = info->x; HIBYTE(dungmap_var7) = info->y;
    const xb: u8 = @truncate(info.x);
    const yb: u8 = @truncate(info.y);
    v.dungmap_var7.* = (@as(u16, yb) << 8) | xb;

    const r0: u16 = v.sprite_A[i] | (@as(u16, v.sprite_B[i]) << 8);
    const qq: u8 = if (v.sprite_ai_state[i] < 2) 0 else t.kFlailTrooperWeapon_Tab0[v.sprite_delay_aux2[i]];
    const r12: u8 = @bitCast(t.kFlailTrooperWeapon_Tab1[v.sprite_D[i]]);
    const r13: u8 = @bitCast(t.kFlailTrooperWeapon_Tab2[v.sprite_D[i]]);

    const r2: u16 = (r0 +% 0x80) & 0x1ff;

    const r14: u8 = ChainBallMult(t.kSinusLookupTable[r0 & 0xff], qq);
    const r4: u8 = if (r0 & 0x100 != 0) 0 -% r14 else r14;

    const r15: u8 = ChainBallMult(t.kSinusLookupTable[r2 & 0xff], qq);
    const r6: u8 = if (r2 & 0x100 != 0) 0 -% r15 else r15;

    // HIBYTE(dungmap_var8) = r4 - 4 + r12; BYTE(dungmap_var8) = r6 - 4 + r13;
    const hi8: u8 = r4 -% 4 +% r12;
    const lo8: u8 = r6 -% 4 +% r13;
    v.dungmap_var8.* = (@as(u16, hi8) << 8) | lo8;

    setOamPlain(oam, hi8 +% xb, lo8 +% yb, 0x2a, 0x2d, 2);
    oam += 1;

    var n: c_int = 3;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const idx = ix(n);
        var tb: u8 = @truncate((@as(u16, t.kFlailTrooperWeapon_Tab4[idx]) *% @as(u16, r14)) >> 8);
        if (sign8(r4)) tb = 0 -% tb;
        const x: u8 = tb +% xb +% r12;
        var ty: u8 = @truncate((@as(u16, t.kFlailTrooperWeapon_Tab4[idx]) *% @as(u16, r15)) >> 8);
        if (sign8(r6)) ty = 0 -% ty;
        const y: u8 = ty +% yb +% r13;
        setOamPlain(oam, x, y, 0x3f, 0x2d, 0);
    }
    a.Sprite_CorrectOamEntries(k, 4, 0xff);
}

pub export fn GerudoMan_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var oam = oamPtr();
    const g: usize = v.sprite_graphics[i];
    var n: c_int = 2;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j = g * 3 + ix(n);
        setOam(
            oam,
            info.x +% s16(t.kGerudoMan_Draw_X[j]),
            info.y +% s16(t.kGerudoMan_Draw_Y[j]),
            t.kGerudoMan_Draw_Char[j],
            t.kGerudoMan_Draw_Flags[j] | info.flags,
            t.kGerudoMan_Draw_Big[j],
        );
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part24.zig
// ---------------------------------------------------------------------------
pub export fn Guard_LaunchProjectile(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x1b, &info);
    if (j < 0) return;
    const ju = ix(j);
    a.SpriteSfx_QueueSfx3WithPan(k, 0x5);
    var m: usize = @as(usize, v.sprite_D[i]) + @as(usize, if (v.sprite_type[i] >= 0x48) 4 else 0);

    a.Sprite_SetX(j, info.r0_x +% s16(t.kJavelinProjectile_X[m]));
    a.Sprite_SetY(j, info.r2_y +% s16(t.kJavelinProjectile_Y[m]));
    v.sprite_x_vel[ju] = @bitCast(t.kJavelinProjectile_Xvel[m]);
    v.sprite_y_vel[ju] = @bitCast(t.kJavelinProjectile_Yvel[m]);
    m &= 3;
    v.sprite_D[ju] = @truncate(m);
    v.sprite_flags4[ju] = t.kJavelinProjectile_Flags4[m];
    v.sprite_z[ju] = 0;
    v.sprite_A[ju] = @intFromBool(v.sprite_type[i] >= 0x48);
    if (v.sprite_A[ju] != 0 and v.link_shield_type.* == 0)
        v.sprite_flags5[ju] &= ~@as(u8, 0x20);
}

pub export fn BushJavelinSoldier_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const bak0 = v.sprite_graphics[i];
    v.sprite_graphics[i] = 0;
    const bak1 = v.sprite_oam_flags[i];
    v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & 0xf1 | 2;
    const bak2 = v.cur_sprite_y.*;
    v.cur_sprite_y.* +%= 8;
    a.SpriteDraw_SingleLarge(k);
    v.cur_sprite_y.* = bak2;
    v.sprite_oam_flags[i] = bak1;
    v.sprite_graphics[i] = bak0;

    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    a.Guard_AnimateHead(k, 0x10 / 4, &info);
    a.SpriteDraw_BNCBody(k, &info, 0xc / 4);
    if (v.sprite_graphics[i] < 20)
        a.SpriteDraw_GuardSpear(k, &info, 4 / 4);
    if (v.sprite_flags3[i] & 0x10 != 0)
        a.SpriteDraw_Shadow_custom(k, &info, t.kSoldier_DrawShadow[v.sprite_D[i]]);
}

pub export fn JavelinTrooper_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    a.SpriteDraw_GuardHead(k, &info, 3);
    a.SpriteDraw_BNCBody(k, &info, 2);
    if (v.sprite_graphics[i] < 20)
        a.SpriteDraw_GuardSpear(k, &info, 0);
    if (v.sprite_flags3[i] & 0x10 != 0)
        a.SpriteDraw_Shadow_custom(k, &info, t.kSoldier_DrawShadow[v.sprite_D[i]]);
}

pub export fn Sprite_49_RedBushGuard(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_ai_state[i] != 0) {
        if (v.sprite_ai_state[i] == 2)
            BushJavelinSoldier_Draw(k)
        else
            BushSoldierCommon_Draw(k);
    }
    Sprite_BushGuard_Main(k);
}

pub export fn Sprite_47_GreenBushGuard(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_ai_state[i] != 0) {
        if (v.sprite_graphics[i] >= 14)
            ArcherSoldier_Draw(k)
        else
            BushSoldierCommon_Draw(k);
    }
    Sprite_BushGuard_Main(k);
}

/// The body of `case 3`, which case 2 also reaches through `goto case_3`.

pub export fn Sprite_BushGuard_Main(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_ignore_projectile[i] = 1;
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 64;
            }
        },
        1 => {
            _ = a.Sprite_CheckDamageFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 48;
                v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
                v.sprite_head_dir[i] = v.sprite_D[i];
            } else {
                if (v.sprite_delay_main[i] == 0x20)
                    BushGuard_SpawnFoliage(k);
                v.sprite_graphics[i] = t.kBushSoldier_Gfx[v.sprite_delay_main[i] >> 2];
            }
        },
        2 => {
            v.sprite_ignore_projectile[i] = 0;
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                v.sprite_ai_state[i] = 3;
                v.sprite_delay_main[i] = 48;
                bushGuardCase3(k);
                return;
            }
            v.sprite_A[i] = if (j < 40) 0xff else 0x00;
            if (j == 16)
                Guard_LaunchProjectile(k);
            v.sprite_graphics[i] = t.kJavelinTrooper_Tab2[@as(usize, v.sprite_D[i]) * 8 + @as(usize, j >> 3) +
                @as(usize, if (v.sprite_type[i] == 0x49) 32 else 0)];
        },
        3 => bushGuardCase3(k),
        else => {},
    }
}

pub export fn BushGuard_SpawnFoliage(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xec, &info);
    if (j < 0) return;
    const ju = ix(j);
    a.Sprite_SetSpawnedCoordinates(j, &info);
    v.sprite_state[ju] = 6;
    v.sprite_delay_main[ju] = 32;
    v.sprite_flags2[ju] +%= 3;
    v.sprite_C[ju] = 2;
}

pub export fn BushSoldierCommon_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var oam = oamPtr();
    const g: usize = @as(usize, v.sprite_graphics[i]) * 2;
    var n: c_int = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j = g + ix(n);
        var flags = t.kBushSoldierCommon_Flags[j] | 0x20;
        if (n == 0)
            flags = flags & ~@as(u8, 0xe) | info.flags;
        setOam(oam, info.x, info.y +% s16(t.kBushSoldierCommon_Y[j]), t.kBushSoldierCommon_Char[j], flags, 2);
    }
}

pub export fn ArcherSoldier_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    const d: usize = v.sprite_D[i];
    a.Guard_AnimateHead(k, t.kArcherSoldier_HeadOamOffs[d] >> 2, &info);
    a.Guard_AnimateBody(k, t.kArcherSoldier_BodyOamOffs[d] >> 2, &info);
    SpriteDraw_Archer_Weapon(k, t.kArcherSoldier_WeaponOamOffs[d] >> 2, &info);
    if (v.sprite_flags3[i] & 0x10 != 0)
        a.SpriteDraw_Shadow_custom(k, &info, t.kSoldier_DrawShadow[d]);
}

pub export fn SpriteDraw_Archer_Weapon(k: c_int, spr_offs: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    var oam = oamPtr() + ix(spr_offs);
    var base: c_int = @as(c_int, v.sprite_graphics[i]) - 14;
    if (base < 0)
        base = t.kArcherSoldier_Tab1[v.sprite_D[i]];
    var n: c_int = 3;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j = ix(base * 4 + n);
        setOam(
            oam,
            info.x +% s16(t.kArcherSoldier_Draw_X[j]),
            info.y +% s16(t.kArcherSoldier_Draw_Y[j]),
            t.kArcherSoldier_Draw_Char[j],
            t.kArcherSoldier_Draw_Flags[j] | 0x20,
            0,
        );
    }
}

pub export fn TutorialSoldier_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var oam = oamPtr();
    const d: usize = @as(usize, v.sprite_graphics[i]) * 5;
    var n: c_int = 4;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const j = d + ix(n);
        var flags = t.kTutorialSoldier_Flags[j] | info.flags;
        if (t.kTutorialSoldier_Char[j] < 0x40)
            flags = (flags & 0xf1) | 8;
        // kTutorialSoldier_X/Y are i16 rather than the usual i8 offset tables.
        setOam(
            oam,
            info.x +% @as(u16, @bitCast(t.kTutorialSoldier_X[j])),
            info.y +% @as(u16, @bitCast(t.kTutorialSoldier_Y[j])),
            t.kTutorialSoldier_Char[j],
            flags,
            t.kTutorialSoldier_Big[j],
        );
    }
    a.SpriteDraw_Shadow_custom(k, &info, 12);
}

pub export fn PullSwitch_FacingUp(k: c_int) callconv(.c) void {
    const i = ix(k);
    PullSwitch_HandleUpPulling(k);
    var j: u8 = v.sprite_graphics[i];
    if (j != 0 and j != 11) {
        v.link_unk_master_sword.* = t.kBadPullSwitch_Tab0[j - 1];
        v.link_y_coord.* = a.Sprite_GetY(k) -% 19;
        v.link_x_coord.* = a.Sprite_GetX(k);
        if (v.sprite_delay_main[i] == 0) {
            j +%= 1;
            v.sprite_graphics[i] = j;
            if (j == 11) {
                v.sound_effect_2.* = 0x1b;
                v.dung_flag_statechange_waterpuzzle.* = 1;
            }
            v.sprite_delay_main[i] = t.kBadPullSwitch_Tab1[j - 2];
        }
    }
    if (v.sprite_type[i] != 7)
        BadPullDownSwitch_Draw(k)
    else
        BadPullUpSwitch_Draw(k);
}

pub export fn PullSwitch_HandleUpPulling(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (!a.Sprite_CheckDamageToLink_same_layer(k)) return;
    v.link_actual_vel_y.* = 0;
    v.link_actual_vel_x.* = 0;
    a.Sprite_RepelDash();
    v.bitmask_of_dragstate.* = 0;
    const y: u8 = @as(u8, @truncate(v.link_y_coord.*)) -% v.sprite_y_lo[i];
    if (!sign8(y -% 2)) {
        v.link_y_coord.* = a.Sprite_GetY(k) +% 9;
    } else if (sign8(y -% 244)) {
        v.byte_7E0379.* +%= 1;
        if (v.joypad1L_last.* & 0x80 != 0 and v.joypad1H_last.* & 3 == 0 and v.sprite_graphics[i] == 0) {
            v.sprite_graphics[i] = 1;
            v.sprite_delay_main[i] = 8;
            a.SpriteSfx_QueueSfx2WithPan(k, 0x22);
        }
        v.link_y_coord.* = a.Sprite_GetY(k) -% 21;
    } else {
        if (sign8(@as(u8, @truncate(v.link_x_coord.*)) -% v.sprite_x_lo[i]))
            v.link_x_coord.* = a.Sprite_GetX(k) -% 16
        else
            v.link_x_coord.* = a.Sprite_GetX(k) +% 14;
    }
}

pub export fn BadPullDownSwitch_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    a.Oam_AllocateDeferToPlayer(k);
    var oam = oamPtr();
    const yoff: u8 = t.kBadPullSwitch_Tab5[t.kBadPullSwitch_Tab4[v.sprite_graphics[i]]];
    var n: c_int = 4;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const idx = ix(n);
        const xx: u8 = @truncate(info.x +% s16(t.kBadPullDownSwitch_X[idx]));
        const yy: u8 = @truncate(info.y +% s16(t.kBadPullDownSwitch_Y[idx]) -% (if (n == 2) @as(u16, yoff) else 0));
        setOamPlain(oam, xx, yy, t.kBadPullDownSwitch_Char[idx], t.kBadPullDownSwitch_Flags[idx] | 0x21, t.kBadPullDownSwitch_Big[idx]);
    }
    a.Sprite_CorrectOamEntries(k, 4, 0xff);
}

pub export fn BadPullUpSwitch_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    a.Oam_AllocateDeferToPlayer(k);
    var oam = oamPtr();
    const yoff: u8 = t.kBadPullSwitch_Tab5[t.kBadPullSwitch_Tab4[v.sprite_graphics[i]]];
    var n: c_int = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        setOam(
            oam,
            info.x,
            info.y -% (if (n == 0) @as(u16, yoff) else 0),
            t.kBadPullUpSwitch_Tab2[ix(n)],
            info.flags,
            2,
        );
    }
}

pub export fn PullSwitch_FacingDown(k: c_int) callconv(.c) void {
    const i = ix(k);
    PullSwitch_HandleDownPulling(k);
    var j: u8 = v.sprite_graphics[i];
    if (j != 0 and j != 13) {
        v.link_unk_master_sword.* = t.kGoodPullSwitch_Tab0[j - 1];
        v.link_y_coord.* = a.Sprite_GetY(k) +% t.kGoodPullSwitch_YOffs[j - 1];
        v.link_x_coord.* = a.Sprite_GetX(k);
        if (v.sprite_delay_main[i] == 0) {
            j +%= 1;
            v.sprite_graphics[i] = j;
            if (j == 13) {
                if (v.sprite_type[i] == 6) {
                    v.activate_bomb_trap_overlord.* = 1;
                    v.sound_effect_1.* = 0x3c;
                } else {
                    v.dung_flag_statechange_waterpuzzle.* = 1;
                    v.sound_effect_2.* = 0x1b;
                }
            }
            v.sprite_delay_main[i] = t.kGoodPullSwitch_Tab1[j - 2];
        }
    }
    GoodPullSwitch_Draw(k);
    if (v.sprite_pause[i] != 0)
        v.sprite_graphics[i] = 0;
}

pub export fn GoodPullSwitch_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    a.Oam_AllocateDeferToPlayer(k);
    const oam = oamPtr();
    const tv: u8 = t.kGoodPullSwitch_Tab2[v.sprite_graphics[i]];
    oam[0].x = @truncate(info.x);
    oam[1].x = @truncate(info.x);
    oam[0].y = @truncate(info.y -% 1);
    oam[1].y = @truncate(info.y -% 1 +% tv);
    oam[0].charnum = 0xee;
    oam[1].charnum = 0xce;
    oam[0].flags = info.flags;
    oam[1].flags = info.flags;
    a.Sprite_CorrectOamEntries(k, 1, 2);
}

pub export fn PullSwitch_HandleDownPulling(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (!a.Sprite_CheckDamageToLink_same_layer(k)) return;
    v.link_actual_vel_y.* = 0;
    v.link_actual_vel_x.* = 0;
    a.Sprite_RepelDash();
    v.bitmask_of_dragstate.* = 0;
    const y: u8 = @as(u8, @truncate(v.link_y_coord.*)) -% v.sprite_y_lo[i];
    if (!sign8(y -% 2)) {
        v.byte_7E0379.* +%= 1;
        if (v.joypad1L_last.* & 0x80 != 0 and v.joypad1H_last.* & 3 == 0) {
            v.link_unk_master_sword.* +%= 1;
            if (v.joypad1H_last.* & 4 != 0 and v.sprite_graphics[i] == 0) {
                v.sprite_graphics[i] = 1;
                v.sprite_delay_main[i] = 12;
                a.SpriteSfx_QueueSfx2WithPan(k, 0x22);
            }
        }
        v.link_y_coord.* = a.Sprite_GetY(k) +% 9;
    } else if (sign8(y -% 244)) {
        v.link_y_coord.* = a.Sprite_GetY(k) -% 21;
    } else {
        if (sign8(@as(u8, @truncate(v.link_x_coord.*)) -% v.sprite_x_lo[i]))
            v.link_x_coord.* = a.Sprite_GetX(k) -% 16
        else
            v.link_x_coord.* = a.Sprite_GetX(k) +% 14;
    }
}

pub export fn Priest_SpawnMantle(k: c_int) callconv(.c) void {
    v.sprite_state[15] +%= 1;
    var info: SpriteSpawnInfo = undefined;
    // The C never checks the spawn for failure here and indexes with the result
    // regardless; slot 15 was just freed above so it always succeeds.
    const j = a.Sprite_SpawnDynamically(k, 0x73, &info);
    v.sprite_state[15] = 0;
    const ju = ix(j);
    v.sprite_flags2[ju] = v.sprite_flags2[ju] & 0xf0 | 0x3;
    v.sprite_x_lo[ju] = 0xf0;
    v.sprite_x_hi[ju] = 4;
    v.sprite_y_lo[ju] = 0x37;
    v.sprite_y_hi[ju] = 2;
    v.sprite_E[ju] = 2;
    v.sprite_flags4[ju] = 11;
    v.sprite_defl_bits[ju] |= 0x20;
    v.sprite_subtype2[ju] = 1;
    if (v.link_y_coord.* < a.Sprite_GetY(j))
        v.sprite_C[ju] = 1;
}

/// The `lbl2` tail: the mantle's own state machine.

/// The `lbl` entry point, reached both on contact and while the grab timer runs.

pub export fn Sprite_SanctuaryMantle(k: c_int) callconv(.c) void {
    const i = ix(k);
    SageMantle_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;

    if (v.sprite_C[i] != 0) {
        v.sprite_A[i] = 0x40;
        sanctuaryMantleStates(k);
        return;
    }
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Sprite_NullifyHookshotDrag();
        v.link_speed_setting.* = 0;
        a.Sprite_RepelDash();
        v.sprite_delay_aux1[i] = 7;
        sanctuaryMantleGrabbed(k);
    } else { // no collision
        if (v.sprite_delay_aux1[i] != 0) {
            sanctuaryMantleGrabbed(k);
            return;
        }
        switch (v.sprite_subtype2[i]) {
            0 => {
                v.sprite_A[i] = 0;
                v.bitmask_of_dragstate.* = 0;
                v.link_speed_setting.* = 0;
                v.sprite_subtype2[i] +%= 1;
            },
            else => {},
        }
    }
}

pub export fn SageMantle_Draw(k: c_int) callconv(.c) void {
    if (v.sprite_C[ix(k)] == 0)
        _ = a.Oam_AllocateFromRegionB(0x10);
    a.Sprite_DrawMultiple(k, &t.kSageMantle_Dmd[0], 4, null);
}

pub export fn Sprite_Priest(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_A[i] == 0)
        a.Priest_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);
    if (a.Sprite_TrackBodyToHead(k))
        a.Sprite_MoveXY(k);
    switch (v.sprite_subtype2[i]) {
        0 => Priest_Dying(k),
        1 => a.Priest_RunRescueCutscene(k),
        2 => a.Priest_Chillin(k),
        else => {},
    }
}

pub export fn Priest_Dying(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_head_dir[i] = 4;
    v.sprite_D[i] = 4;
    switch (v.sprite_ai_state[i]) {
        0 => { // Priest_LyingOnGround
            if (a.Sprite_ShowSolicitedMessage(k, 0x1b) & 0x100 != 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_graphics[i] +%= 1;
                v.sram_progress_flags.* |= 0x2;
                v.sprite_delay_aux2[i] = 128;
            }
        },
        1 => { // Priest_FinalWords
            v.sprite_graphics[i] = 0;
            if (v.sprite_delay_aux2[i] == 0)
                v.sprite_ai_state[i] +%= 1;
            v.sprite_A[i] = v.frame_counter.* & 2;
            if (v.sprite_delay_aux2[i] & 7 == 0)
                a.SpriteSfx_QueueSfx2WithPan(k, 0x33);
        },
        2 => v.sprite_state[i] = 0, // Priest_Die
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part25.zig
// ---------------------------------------------------------------------------
/// sprite_main.c keeps this as a file-local accessor into work RAM rather than
/// a name in variables.zig, so it is re-derived here.

pub export fn Priest_RunRescueCutscene(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_head_dir[i] = 0;
            v.sprite_D[i] = 0;
            if (v.sprite_delay_main[i] == 0) {
                a.Sprite_ShowMessageUnconditional(0x17);
                v.sprite_ai_state[i] +%= 1;
                byte_7FFE01.* = 1;
                a.Priest_SpawnRescuedPrincess();
                v.flag_is_link_immobilized.* = 1;
                v.savegame_map_icons_indicator.* = 1;
            }
        },
        1 => {
            if (byte_7FFE01.* == 2) {
                a.Sprite_ShowMessageUnconditional(0x18);
                v.sprite_ai_state[i] +%= 1;
            }
        },
        2 => {
            if (v.choice_in_multiselect_box.* == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.flag_is_link_immobilized.* = 0;
            } else {
                v.sprite_ai_state[i] = 1;
            }
        },
        3 => {
            v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
            const j = a.Sprite_ShowSolicitedMessage(k, 0x16);
            if (j & 0x100 != 0) {
                v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
                v.sprite_D[i] = v.sprite_head_dir[i];
            }
        },
        else => {},
    }
}

pub export fn Priest_Chillin(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
    const m: u16 = if (v.link_which_pendants.* & 7 == 7)
        0x1a
    else if (v.savegame_map_icons_indicator.* >= 3)
        0x19
    else
        0x16;
    const j = a.Sprite_ShowSolicitedMessage(k, m);
    if (j & 0x100 != 0) {
        v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
        v.sprite_D[i] = v.sprite_head_dir[i];
        v.link_hearts_filler.* = 0xa0;
    }
}

pub export fn Sprite_Uncle(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Uncle_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_subtype2[i] == 0)
        Uncle_AtHouse(k)
    else
        Uncle_InPassage(k);
}

pub export fn Uncle_AtHouse(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Sprite_MoveXY(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // Uncle_TriggerTelepathy
            v.link_x_coord_prev.* = 0x940;
            v.link_y_coord_prev.* = 0x215a;
            a.Sprite_ShowMessageUnconditional(0x1f);
            v.sprite_ai_state[i] +%= 1;
        },
        1 => { // Uncle_AwakenLink
            if (v.frame_counter.* & 3 != 0) return;
            if (v.COLDATA_copy0.* != 32) {
                v.COLDATA_copy0.* -%= 1;
                v.COLDATA_copy1.* -%= 1;
                return;
            }
            v.link_pose_during_opening.* +%= 1;
            v.player_sleep_in_bed_state.* +%= 1;
            v.link_y_coord.* = 0x2157;
            v.flag_is_link_immobilized.* = 1;
            v.sprite_ai_state[i] +%= 1;
        },
        2 => { // Uncle_DeclareCurfew
            a.Sprite_ShowMessageUnconditional(0x0d);
            v.music_control.* = 3;
            v.sprite_graphics[i] = 1;
            v.sprite_ai_state[i] +%= 1;
        },
        3 => { // Uncle_Embark
            v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
            if (v.sprite_delay_main[i] == 0) {
                var j: usize = v.sprite_A[i];
                if (j == 2) {
                    v.sprite_ai_state[i] +%= 1;
                } else {
                    v.sprite_A[i] +%= 1;
                    if (j == 0)
                        v.sprite_y_lo[i] -%= 2;
                    v.sprite_delay_main[i] = t.kUncle_LeaveHouse_Delay[j];
                    j = t.kUncle_LeaveHouse_Dir[j];
                    v.sprite_D[i] = @truncate(j);
                    v.sprite_x_vel[i] = @bitCast(t.kUncle_LeaveHouse_Xvel[j]);
                    v.sprite_y_vel[i] = @bitCast(t.kUncle_LeaveHouse_Yvel[j]);
                }
            }
        },
        4 => { // Uncle_ApplyTelepathyFollower
            v.follower_indicator.* = 5;
            v.word_7E02CD.* = 0xdf3;
            v.sram_progress_flags.* |= 0x10;
            v.sprite_state[i] = 0;
            v.flag_is_link_immobilized.* = 0;
        },
        else => {},
    }
}

pub export fn Uncle_InPassage(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // RemoveZeldaTelepathTagalong
            if (a.Sprite_CheckDamageToLink_same_layer(k))
                a.Link_CancelDash();
            if (a.Sprite_ShowMessageOnContact(k, 0xe) & 0x100 != 0) {
                v.follower_indicator.* = 0;
                v.sprite_ai_state[i] +%= 1;
            }
        },
        1 => { // GiveSwordAndShield
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(0, 0);
            v.sprite_ai_state[i] +%= 1;
            v.sprite_graphics[i] = 1;
            v.which_starting_point.* = 3;
            v.sram_progress_flags.* |= 1;
            v.sram_progress_indicator.* = 1;
        },
        else => {},
    }
}

pub export fn Sprite_QuarrelBros(k: c_int) callconv(.c) void {
    const i = ix(k);
    QuarrelBros_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    _ = a.Sprite_TrackBodyToHead(k);
    v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
    if (v.dungeon_room_index.* & 1 == 0) {
        _ = a.Sprite_ShowSolicitedMessage(k, 0x131);
    } else if (v.dung_door_opened.* & 0xff00 == 0) {
        _ = a.Sprite_ShowSolicitedMessage(k, 0x12f);
    } else {
        _ = a.Sprite_ShowSolicitedMessage(k, 0x130);
    }
    a.Sprite_BehaveAsBarrier(k);
}

pub export fn QuarrelBros_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(
        k,
        &t.kQuarrelBros_Dmd[@as(usize, v.sprite_graphics[i]) * 2 + @as(usize, v.sprite_D[i]) * 4],
        2,
        &info,
    );
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_YoungSnitchLady(k: c_int) callconv(.c) void {
    a.Sprite_OldSnitchLady(k);
}

// ---------------------------------------------------------------------------
// from sprite_main_part26.zig
// ---------------------------------------------------------------------------
/// hud.zig keeps this as a file-local constant, so it is repeated here.

/// Reinterpret a signed oam offset as the byte the coordinate maths wants.

pub export fn YoungSnitchLady_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(
        k,
        &t.kYoungSnitchLady_Dmd[@as(usize, v.sprite_graphics[i]) * 2 + @as(usize, v.sprite_D[i]) * 4],
        2,
        &info,
    );
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_InnKeeper(k: c_int) callconv(.c) void {
    InnKeeper_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);
    _ = a.Sprite_ShowSolicitedMessage(k, if (v.link_item_flippers.* != 0) 0x183 else 0x182);
}

pub export fn InnKeeper_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kInnKeeper_Dmd[0], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_Witch(k: c_int) callconv(.c) void {
    const i = ix(k);
    Witch_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    const bak0 = v.sprite_flags4[i];
    v.sprite_flags4[i] = 2;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Sprite_NullifyHookshotDrag();
        v.link_speed_setting.* = 0;
        a.Link_CancelDash();
    }
    v.sprite_flags4[i] = bak0;
    if (v.frame_counter.* == 0)
        v.sprite_A[i] = (a.GetRandomNumber() & 1) +% 2;
    // The C promotes the counter to int before shifting by the sprite's stride.
    const shift: u5 = @truncate(v.sprite_A[i] +% 1);
    v.sprite_graphics[i] = @truncate((@as(u32, v.frame_counter.*) >> shift) & 7);
    if (a.Sprite_CheckIfLinkIsBusy()) return;
    switch (v.sprite_ai_state[i]) {
        0 => { // main
            if (v.link_item_mushroom.* == 0) {
                if (v.save_dung_info[0x109] & 0x80 != 0)
                    _ = a.Sprite_ShowSolicitedMessage(k, 0x4b)
                else
                    _ = a.Sprite_ShowSolicitedMessage(k, 0x4a);
            } else if (v.link_item_mushroom.* == 1) {
                if (v.joypad1H_last.* & 0x40 == 0) {
                    _ = a.Sprite_ShowSolicitedMessage(k, 0x4c);
                } else if (a.Sprite_CheckDamageToLink_same_layer(k) and v.hud_cur_item.* == kHudItem_Mushroom) {
                    Witch_AcceptShroom(k);
                }
            } else {
                _ = a.Sprite_ShowSolicitedMessage(k, 0x4a);
            }
        },
        1 => { // grant cane of byrna
            v.sprite_ai_state[i] = 0;
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(0x18, 0);
        },
        else => {},
    }
}

pub export fn Witch_AcceptShroom(k: c_int) callconv(.c) void {
    v.link_item_mushroom.* = 0;
    v.save_dung_info[0x109] |= 0x80;
    v.sound_effect_1.* = 0;
    a.Hud_RefreshIcon();
    a.Sprite_ShowMessageUnconditional(0x4b);
    a.SpriteSfx_QueueSfx1WithPan(k, 0xd);
    v.flag_overworld_area_did_change.* = 0;
}

pub export fn Witch_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    a.Oam_AllocateDeferToPlayer(k);
    const oam = oamPtr();
    const g: usize = @as(usize, v.sprite_graphics[i]) * 2;
    const xb: u8 = @truncate(v.dungmap_var7.*);
    const yb: u8 = @truncate(v.dungmap_var7.* >> 8);

    setOamPlain(
        oam + 0,
        xb +% sb(t.kWitch_DrawDataA[g + 0].x),
        yb +% sb(t.kWitch_DrawDataA[g + 0].y),
        info.r4 | t.kWitch_DrawDataA[g + 0].charnum,
        info.flags,
        0,
    );
    setOamPlain(
        oam + 1,
        xb +% sb(t.kWitch_DrawDataA[g + 1].x),
        yb +% sb(t.kWitch_DrawDataA[g + 1].y),
        info.r4 | t.kWitch_DrawDataA[g + 1].charnum,
        info.flags,
        0,
    );

    var n: usize = 0;
    while (n < 3) : (n += 1) {
        setOamPlain(
            oam + n + 2,
            xb +% sb(t.kWitch_DrawDataB[n].x),
            yb +% sb(t.kWitch_DrawDataB[n].y),
            info.r4 ^ t.kWitch_DrawDataB[n].charnum,
            info.flags ^ t.kWitch_DrawDataB[n].flags,
            2,
        );
    }
    const c: usize = @intFromBool(@as(u16, @truncate(g -% 6)) < 6);
    setOamPlain(
        oam + 5,
        xb +% sb(t.kWitch_DrawDataC[c].x),
        yb +% sb(t.kWitch_DrawDataC[c].y),
        info.r4 | t.kWitch_DrawDataC[c].charnum,
        info.flags,
        2,
    );
    a.Sprite_CorrectOamEntries(k, 5, 0xff);
}

pub export fn SpritePrep_Snitches(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_D[i] = 2;
    v.sprite_head_dir[i] = 2;
    v.sprite_ignore_projectile[i] +%= 1;
    v.sprite_A[i] = v.sprite_x_lo[i];
    v.sprite_B[i] = v.sprite_x_hi[i];
    v.sprite_x_vel[i] = sb(-9);
}

pub export fn Sprite_OldSnitchLady(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.sprite_type[i] == 0x34) {
        if (v.sprite_ai_state[i] < 2)
            YoungSnitchLady_Draw(k);
    } else {
        if (v.sprite_subtype[i] != 0) {
            a.Sprite_ChickenLady(k);
            return;
        }
        if (v.sprite_ai_state[i] < 3)
            a.Lady_Draw(k);
    }

    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_ai_state[i] < 3) {
        if (v.player_is_indoors.* != 0) {
            _ = a.Sprite_TrackBodyToHead(k);
            v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
            _ = a.Sprite_ShowSolicitedMessage(k, 0xad);
            return;
        }
        if (v.sprite_ai_state[i] == 0 and a.Sprite_CheckDamageToLink_same_layer(k)) {
            v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
            v.sprite_delay_main[i] = 1;
        } else {
            if (a.Sprite_TrackBodyToHead(k))
                a.Sprite_MoveXY(k)
            else
                v.sprite_delay_main[i] = 1;
        }
    }

    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_delay_main[i] == 0) {
                const tx: u16 = (@as(u16, v.sprite_A[i]) | (@as(u16, v.sprite_B[i]) << 8)) +%
                    s16(t.kOldSnitchLady_Xd[v.sprite_C[i]]);
                if (tx == a.Sprite_GetX(k)) {
                    const j: usize = v.sprite_D[i] ^ 1;
                    v.sprite_head_dir[i] = @truncate(j);
                    v.sprite_x_vel[i] = @bitCast(t.kOldSnitchLady_Xvel[j]);
                    v.sprite_y_vel[i] = @bitCast(t.kOldSnitchLady_Yvel[j]);
                    v.sprite_C[i] ^= 1;
                }
            }
            v.sprite_graphics[i] = @truncate(@as(u32, @bitCast(k ^ @as(c_int, v.frame_counter.*))) >> 4 & 1);
            const bak0 = v.sprite_flags4[i];
            v.sprite_flags4[i] = 3;
            const j = a.Sprite_ShowMessageOnContact(k, 0x2f);
            v.sprite_flags4[i] = bak0;
            if (j & 0x100 != 0) {
                v.sprite_D[i] = @truncate(@as(u32, @bitCast(j)));
                a.Snitch_SpawnGuard(k);
                v.sprite_ai_state[i] = 1;
            }
        },
        1 => {
            const oi: usize = v.byte_7E0FDE.*;
            const ovx: u16 = @as(u16, v.overlord_x_lo[oi]) | (@as(u16, v.overlord_x_hi[oi]) << 8);
            const ovy: u16 = @as(u16, v.overlord_y_lo[oi]) | (@as(u16, v.overlord_y_hi[oi]) << 8);
            if (ovy >= a.Sprite_GetY(k)) {
                v.sprite_ai_state[i] = 2;
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
                v.sprite_flags4[i] = 2;
                var pos: u16 = ((ovy -% v.overworld_offset_base_y.*) & v.overworld_offset_mask_y.*) *% 8;
                pos +%= ((ovx >> 3) -% v.overworld_offset_base_x.*) & v.overworld_offset_mask_x.*;
                a.Overworld_DrawWoodenDoor(pos, false);
                v.sprite_delay_main[i] = 16;
            } else {
                v.flag_is_link_immobilized.* = 1;
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, ovx, ovy, 64);
                v.sprite_x_vel[i] = pt.x;
                v.sprite_y_vel[i] = pt.y;
                v.sprite_D[i] = 0;
                v.sprite_head_dir[i] = 0;
                v.sprite_graphics[i] = @truncate(@as(u32, @bitCast(k ^ @as(c_int, v.frame_counter.*))) >> 3 & 1);
            }
        },
        2 => {
            if (v.sprite_delay_main[i] == 0) {
                const oi: usize = v.byte_7E0FDE.*;
                const ovx: u16 = @as(u16, v.overlord_x_lo[oi]) | (@as(u16, v.overlord_x_hi[oi]) << 8);
                const ovy: u16 = @as(u16, v.overlord_y_lo[oi]) | (@as(u16, v.overlord_y_hi[oi]) << 8);
                a.Sprite_SetX(k, ovx);
                a.Sprite_SetY(k, ovy);
                var pos: u16 = ((ovy -% v.overworld_offset_base_y.*) & v.overworld_offset_mask_y.*) *% 8;
                pos +%= ((ovx >> 3) -% v.overworld_offset_base_x.*) & v.overworld_offset_mask_x.*;
                a.Overworld_DrawWoodenDoor(pos, true);
                v.sprite_ai_state[i] = 3;
            }
            a.Sprite_MoveXY(k);
        },
        3 => {
            v.sprite_state[i] = 0;
            v.flag_is_link_immobilized.* = 0;
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part27.zig
// ---------------------------------------------------------------------------
/// player.zig keeps this as a file-local constant, so it is repeated here.

pub export fn Sprite_RunningMan(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.RunningMan_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    _ = a.Sprite_TrackBodyToHead(k);
    a.Sprite_BehaveAsBarrier(k);
    v.sprite_subtype[i] = 255;
    _ = a.Sprite_CheckTileCollision(k);
    const bak0 = v.sprite_flags4[i];
    v.sprite_flags4[i] = 7;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        v.sprite_C[i] = v.sprite_ai_state[i];
        v.sprite_ai_state[i] = 3;
    }
    v.sprite_flags4[i] = bak0;
    switch (v.sprite_ai_state[i]) {
        0 => { // chill
            _ = a.Sprite_TrackBodyToHead(k);
            const j: u8 = a.Sprite_DirectionToFaceLink(k, null);
            v.sprite_head_dir[i] = j ^ 3;
            if (a.Sprite_CheckDamageToLink_same_layer(k)) {
                a.Link_CancelDash();
                v.sprite_D[i] = j ^ 3;
                v.sprite_head_dir[i] = j | 2;
                v.sprite_ai_state[i] = (j & 1) +% 1;
                v.sprite_x_vel[i] = @bitCast(t.kRunningMan_Xvel2[j & 1]);
                v.sprite_delay_main[i] = 32;
            } else {
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
            }
        },
        1, 2 => { // run left / run right
            if (v.sprite_delay_main[i] != 0) {
                v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
                a.Sprite_MoveXY(k);
            } else {
                a.RunningBoy_SpawnDustGarnish(k);
                v.sprite_graphics[i] = v.frame_counter.* >> 2 & 1;
                const d: usize = v.sprite_head_dir[i];
                v.sprite_x_vel[i] = @bitCast(t.kRunningMan_Xvel[d]);
                v.sprite_y_vel[i] = @bitCast(t.kRunningMan_Yvel[d]);
                a.Sprite_MoveXY(k);
                if (v.sprite_A[i] != 0) {
                    v.sprite_A[i] -%= 1;
                    return;
                }
                if (v.sprite_ai_state[i] == 1) { // left
                    v.sprite_A[i] = 255;
                    v.sprite_head_dir[i] = 2;
                } else {
                    const j: usize = v.sprite_B[i];
                    v.sprite_B[i] +%= 1;
                    v.sprite_A[i] = t.kRunningMan_A[j];
                    if (t.kRunningMan_Dir[j] < 0) {
                        v.sprite_ai_state[i] = 0;
                        v.sprite_subtype2[i] = 0;
                    } else {
                        v.sprite_head_dir[i] = @bitCast(t.kRunningMan_Dir[j]);
                    }
                }
            }
        },
        3 => { // caught
            a.Sprite_ShowMessageUnconditional(0xa6);
            if (v.link_player_handler_state.* >= kPlayerState_RecoilWall) // wtf
                v.sprite_D[i] = v.link_player_handler_state.*;
            v.sprite_ai_state[i] = v.sprite_C[i];
        },
        else => {},
    }
}

pub export fn RunningMan_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(
        k,
        &t.kRunningMan_Dmd[(@as(usize, v.sprite_D[i]) * 4 + @as(usize, v.sprite_graphics[i]) * 2) & 0xf],
        2,
        &info,
    );
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_BottleVendor(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_A[i] = BottleVendor_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.BottleMerchant_DetectFish(k);
    a.Sprite_BehaveAsBarrier(k);
    if (a.Sprite_CheckIfLinkIsBusy()) return;
    if (a.GetRandomNumber() == 0) {
        v.sprite_delay_main[i] = 20;
        v.sprite_graphics[i] = 1;
    } else if (v.sprite_delay_main[i] == 0) {
        v.sprite_graphics[i] = 0;
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // base
            if (v.sprite_A[i] == 0 and v.sprite_E[i] != 0)
                v.sprite_ai_state[i] = 3
            else if (v.sram_progress_indicator_3.* & 2 != 0)
                _ = a.Sprite_ShowSolicitedMessage(k, 0xd4)
            else if (a.Sprite_ShowSolicitedMessage(k, 0xd1) & 0x100 != 0)
                v.sprite_ai_state[i] = 1;
        },
        1 => { // selling
            if (v.choice_in_multiselect_box.* == 0 and v.link_rupees_goal.* >= 100) {
                a.Sprite_ShowMessageUnconditional(0xd2);
                v.sprite_ai_state[i] = 2;
            } else {
                a.Sprite_ShowMessageUnconditional(0xd3);
                v.sprite_ai_state[i] = 0;
            }
        },
        2 => { // giving
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(0x16, 0);
            v.sram_progress_indicator_3.* |= 2;
            v.link_rupees_goal.* -%= 100;
            v.sprite_ai_state[i] = 0;
        },
        3 => { // buying
            if (!sign8(v.sprite_E[i]))
                a.Sprite_ShowMessageUnconditional(0xd5)
            else
                a.Sprite_ShowMessageUnconditional(0xd6);
            v.sprite_ai_state[i] = 4;
        },
        4 => { // reward
            const j = v.sprite_E[i];
            if (!sign8(j)) {
                // Only reachable with a non-zero slot, set by BottleMerchant_DetectFish.
                v.sprite_state[@as(usize, j) - 1] = 0;
                a.BottleMerchant_BuyBee(k);
            } else {
                v.sprite_state[j & 0xf] = 0;
                a.BottleMerchant_BuyFish(k);
            }
            v.sprite_E[i] = 0;
            v.sprite_ai_state[i] = 0;
        },
        else => {},
    }
}

pub export fn BottleVendor_Draw(k: c_int) callconv(.c) u8 {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kBottleVendor_Dmd[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
    return @truncate((info.x | info.y) >> 8);
}

pub export fn Priest_SpawnRescuedPrincess() callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const k = a.Sprite_SpawnDynamically(0, 0x76, &info);
    if (k < 0) return;
    const i = ix(k);
    v.sprite_head_dir[i] = v.tagalong_layerbits[v.tagalong_var2.*] & 3;
    v.sprite_D[i] = v.sprite_head_dir[i];
    a.Sprite_SetX(k, v.link_x_coord.*);
    a.Sprite_SetY(k, v.link_y_coord.*);
    v.sprite_subtype2[i] = 1;
    v.follower_indicator.* = 0;
    v.sprite_ignore_projectile[i] +%= 1;
    v.sprite_flags4[i] = 3;
}

// ---------------------------------------------------------------------------
// from sprite_main_part28.zig
// ---------------------------------------------------------------------------
/// sprite_main.c keeps this as a file-local accessor into work RAM rather than
/// a name in variables.zig, so it is re-derived here.

pub export fn Sprite_76_Zelda(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.CrystalMaiden_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);
    if (a.Sprite_TrackBodyToHead(k))
        a.Sprite_MoveXY(k);
    switch (v.sprite_subtype2[i]) {
        0 => Zelda_InCell(k),
        1 => Zelda_EnteringSanctuary(k),
        2 => Zelda_AtSanctuary(k),
        else => {},
    }
}

pub export fn Zelda_InCell(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
    switch (v.sprite_ai_state[i]) {
        0 => { // AwaitingRescue
            if (!a.Sprite_CheckDamageToLink_same_layer(k)) return;
            v.sprite_ai_state[i] +%= 1;
            v.flag_is_link_immobilized.* +%= 1;
            const j: usize = v.sprite_head_dir[i];
            v.sprite_x_vel[i] = @bitCast(t.kZelda_Xvel[j]);
            v.sprite_y_vel[i] = @bitCast(t.kZelda_Yvel[j]);
            v.sprite_delay_main[i] = 16;
        },
        1 => { // ApproachingPlayer
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                a.Sprite_ShowMessageUnconditional(0x1c);
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
                v.music_control.* = 25;
            }
            v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
        },
        2 => { // TheWizardIsBadMkay
            v.sprite_ai_state[i] +%= 1;
            a.Sprite_ShowMessageUnconditional(0x25);
        },
        3 => { // WaitUntilPlayerPaysAttention
            if (v.choice_in_multiselect_box.* != 0) {
                v.sprite_ai_state[i] = 2;
            } else {
                v.sprite_ai_state[i] +%= 1;
                a.Sprite_ShowMessageUnconditional(0x24);
            }
        },
        4 => { // TransitionToTagalong
            v.flag_is_link_immobilized.* = 0;
            v.which_starting_point.* = 2;
            a.SavePalaceDeaths();
            v.follower_indicator.* = 1;
            a.Dungeon_FlagRoomData_Quadrants();
            a.Sprite_BecomeFollower(k);
            v.sprite_state[i] = 0;
            v.music_control.* = 16;
        },
        else => {},
    }
}

pub export fn Zelda_EnteringSanctuary(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // walk to priest
            if (v.sprite_delay_main[i] == 0) {
                var j: usize = v.sprite_A[i];
                if (j >= 4) {
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_D[i] = 0;
                    v.sprite_head_dir[i] = 0;
                    v.sprite_x_vel[i] = 0;
                    v.sprite_y_vel[i] = 0;
                    return;
                }
                v.sprite_delay_main[i] = t.kZelda_Delay0[j];
                j = t.kZelda_Dir0[j];
                v.sprite_head_dir[i] = @truncate(j);
                v.sprite_D[i] = v.sprite_head_dir[i];
                v.sprite_A[i] +%= 1;
                v.sprite_x_vel[i] = @bitCast(t.kZelda_Xvel[j]);
                v.sprite_y_vel[i] = @bitCast(t.kZelda_Yvel[j]);
            }
            v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
        },
        1 => { // respond to priest
            a.Sprite_ShowMessageUnconditional(0x1d);
            v.sprite_ai_state[i] +%= 1;
            byte_7FFE01.* = 2;
            v.which_starting_point.* = 1;
            a.SavePalaceDeaths();
            v.sram_progress_indicator.* = 2;
            a.Sprite_LoadGraphicsProperties_light_world_only();
        },
        2 => { // be careful
            v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
            const j = a.Sprite_ShowSolicitedMessage(k, 0x1e);
            if (j & 0x100 != 0) {
                v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
                v.sprite_D[i] = v.sprite_head_dir[i];
            }
        },
        else => {},
    }
}

pub export fn Zelda_AtSanctuary(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
    const m: u16 = if (v.link_which_pendants.* & 7 == 7)
        0x27
    else if (v.savegame_map_icons_indicator.* >= 3)
        0x26
    else
        0x1e;
    const j = a.Sprite_ShowSolicitedMessage(k, m);
    if (j & 0x100 != 0) {
        v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
        v.sprite_D[i] = v.sprite_head_dir[i];
        v.link_hearts_filler.* = 0xa0;
    }
}

pub export fn SpritePrep_Mushroom(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.link_item_mushroom.* >= 2) {
        v.sprite_state[i] = 0;
    } else {
        v.sprite_graphics[i] = 0;
        v.sprite_oam_flags[i] |= 8;
        v.sprite_ignore_projectile[i] +%= 1;
    }
}

pub export fn Sprite_E7_Mushroom(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_CheckIfLinkIsBusy()) return;

    // If we're in the middle of a mirror warp, don't get the mushroom yet
    if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0 and v.submodule_index.* != 0)
        return;

    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        v.sprite_state[i] = 0;
        v.item_receipt_method.* = 0;
        a.Link_ReceiveItem(0x29, 0);
    } else if (v.frame_counter.* & 0x1f == 0) {
        v.sprite_oam_flags[i] ^= 0x40;
    }
}

pub export fn Sprite_E8_FakeSword(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.FakeSword_Draw(k);
    if (a.Sprite_ReturnIfPaused(k)) return;
    if (v.sprite_unk3[i] == 3) {
        if (v.sprite_C[i] == 0) {
            v.sprite_C[i] = 1;
            a.Sprite_ShowMessageUnconditional(0x6f);
        }
    } else {
        a.Sprite_MoveXY(k);
        a.ThrownSprite_TileAndSpriteInteraction(k);
    }
}

pub export fn Sprite_HeartContainer(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (@as(u8, @truncate(v.cur_palace_index_x2.*)) == 26) {
        v.sprite_state[i] = 0;
        return;
    }
    v.sprite_ignore_projectile[i] = v.sprite_G[i];
    if (v.sprite_G[i] == 0) {
        a.DecodeAnimatedSpriteTile_variable(3);
        a.Sprite_Get16BitCoords(k);
        v.sprite_G[i] = 1;
    }

    if (@as(u8, @truncate(v.dungeon_room_index2.*)) == 6 and v.sprite_z[i] == 0)
        a.SpriteDraw_WaterRipple_WithOamAdjust(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_z_vel[i] -%= 2;
    a.Sprite_MoveZ(k);
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = (0 -% v.sprite_z_vel[i]) >> 2;
        if (@as(u8, @truncate(v.dungeon_room_index2.*)) == 6 and v.sprite_subtype[i] == 0) {
            v.sprite_flags2[i] +%= 2;
            v.sprite_subtype[i] = 1;
            _ = a.Sprite_SpawnWaterSplash(k);
        }
    }
    if (a.Sprite_CheckIfLinkIsBusy()) return;
    if (!a.Sprite_CheckDamageToLink_same_layer(k)) return;
    v.sprite_state[i] = 0;
    if (v.sprite_A[i] != 0) {
        v.item_receipt_method.* = 2;
        a.Link_ReceiveItem(0x3e, 0);
        v.dung_savegame_state_bits.* |= 0x8000;
        return;
    }
    a.Link_CancelDash();
    v.item_receipt_method.* = 0;
    a.Link_ReceiveItem(0x26, 0);
    if (v.player_is_indoors.* == 0)
        v.save_ow_event_info[@as(u8, @truncate(v.overworld_screen_index.*))] |= 0x40
    else
        v.dung_savegame_state_bits.* |= if (v.sprite_x_hi[i] & 1 != 0) 0x2000 else 0x4000;
}

// ---------------------------------------------------------------------------
// from sprite_main_part29.zig
// ---------------------------------------------------------------------------
/// hud.zig keeps this as a file-local constant, so it is repeated here.

pub export fn MedallionTablet_Main(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.MedallionTablet_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.link_position_mode.* &= ~@as(u8, 0x20);
    v.sprite_A[i] = 0;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Sprite_NullifyHookshotDrag();
        v.link_speed_setting.* = 0;
        a.Sprite_RepelDash();
        v.sprite_A[i] +%= 1;
    }
    if (a.Sprite_CheckIfLinkIsBusy()) return;
    switch (v.sprite_ai_state[i]) {
        0 => { // wait for mudora
            if (@as(u8, @truncate(v.overworld_screen_index.*)) != 3)
                BombosTablet(k)
            else
                EtherTablet(k);
        },
        1 => { // delay
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 128;
            }
        },
        2 => { // crumbling
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 240;
            } else {
                if (v.sprite_delay_main[i] == 0x20 or v.sprite_delay_main[i] == 0x40 or v.sprite_delay_main[i] == 0x60)
                    v.sprite_graphics[i] +%= 1;
                if (v.frame_counter.* & 7 == 0)
                    _ = a.Sprite_SpawnDustCloud(k);
            }
        },
        3 => v.sprite_graphics[i] = 4, // final animstate
        else => {},
    }
}

pub export fn BombosTablet(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.link_direction_facing.* != 0 or a.Sprite_DirectionToFaceLink(k, null) != 2)
        return;
    if (v.cur_sprite_y.* +% 16 < v.link_y_coord.*)
        return;
    if (v.filtered_joypad_H.* & 0x80 != 0 and v.link_sword_type.* == 2)
        return;

    // The C folds `j = 0` into the second operand with a comma expression.
    var j: usize = 1;
    if (!(v.hud_cur_item.* == kHudItem_BookMudora and v.filtered_joypad_H.* & 0x40 != 0)) {
        j = 0;
        if (v.filtered_joypad_L.* & 0x80 == 0)
            return;
    }
    if (j != 0) {
        v.player_handler_timer.* = 0;
        v.link_position_mode.* = 32;
        v.sound_effect_1.* = 0;
        if (!sign8(v.link_sword_type.*) and v.link_sword_type.* >= 2) {
            v.sprite_ai_state[i] +%= 1;
            a.BombosTablet_StartCutscene();
            v.sprite_delay_main[i] = 64;
        }
    }
    a.Sprite_ShowMessageUnconditional(t.kMedallionTabletMsg[j]);
}

pub export fn EtherTablet(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.link_direction_facing.* != 0 or a.Sprite_DirectionToFaceLink(k, null) != 2)
        return;
    if (v.sprite_y_lo[i] +% 16 < @as(u8, @truncate(v.link_y_coord.*)))
        return;
    if (v.filtered_joypad_H.* & 0x80 != 0 and v.link_sword_type.* == 2)
        return;

    var j: usize = 1;
    if (!(v.hud_cur_item.* == kHudItem_BookMudora and v.filtered_joypad_H.* & 0x40 != 0)) {
        j = 0;
        if (v.filtered_joypad_L.* & 0x80 == 0)
            return;
    }
    if (j != 0) {
        v.player_handler_timer.* = 0;
        v.link_position_mode.* = 32;
        v.sound_effect_1.* = 0;
        if (!sign8(v.link_sword_type.*) and v.link_sword_type.* >= 2) {
            v.sprite_ai_state[i] +%= 1;
            a.EtherTablet_StartCutscene();
            v.sprite_delay_main[i] = 64;
        }
    }
    a.Sprite_ShowMessageUnconditional(t.kMedallionTabletEtherMsg[j]);
}

pub export fn Sprite_DashItem(k: c_int) callconv(.c) void {
    switch (v.sprite_graphics[ix(k)]) {
        0 => a.Sprite_BookOfMudora(k),
        1 => Sprite_BonkKey(k),
        2 => Sprite_LumberjackTree(k),
        else => {},
    }
}

pub export fn Sprite_BonkKey(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Sprite_DrawThinAndTall(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_CheckDamageToLink_same_layer(k))
        v.sprite_ai_state[i] = 3;
    a.Sprite_MoveXY(k);
    v.sprite_z_vel[i] -%= 1;
    a.Sprite_MoveZ(k);
    if (sign8(v.sprite_z[i])) {
        v.sprite_y_vel[i] = 0;
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = (0 -% v.sprite_z_vel[i]) >> 2;
        if (v.sprite_z_vel[i] & 254 != 0)
            a.SpriteSfx_QueueSfx3WithPan(k, 0x14);
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // wait for dash
            if (v.cur_sprite_x.* -% v.link_x_coord.* +% 16 < 33 and
                v.cur_sprite_y.* -% v.link_y_coord.* +% 24 < 41 and
                (v.bg1_x_offset.* | v.bg1_y_offset.*) != 0)
                v.sprite_ai_state[i] = 1;
        },
        1 => { // begin falling
            v.sprite_z_vel[i] = 32;
            v.sprite_y_vel[i] = cm.byte(-5);
            v.sound_effect_2.* = 27;
            v.sprite_ai_state[i] = 2;
        },
        2 => { // falling
            if (v.sprite_z[i] == 0)
                v.sprite_floor[i] = v.link_is_on_lower_level.*;
        },
        3 => { // give to player
            v.link_num_keys.* +%= 1;
            v.sprite_state[i] = 0;
            v.dung_savegame_state_bits.* |= if (v.sprite_die_action[i] != 0) 0x2000 else 0x4000;
            a.SpriteSfx_QueueSfx3WithPan(k, 0x2f);
        },
        else => {},
    }
}

pub export fn Sprite_LumberjackTree(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_flags2[i] = 0x8f;
    v.sprite_flags4[i] = 0x47;
    a.DashTreeTop_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Sprite_NullifyHookshotDrag();
        v.link_speed_setting.* = 0;
        a.Sprite_RepelDash();
    }
    a.Sprite_MoveXY(k);
    v.sprite_z_vel[i] -%= 1;
    a.Sprite_MoveZ(k);
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = (0 -% v.sprite_z_vel[i]) >> 2;
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // wait for dash
            v.sprite_subtype2[i] = 0;
            if (v.cur_sprite_x.* -% v.link_x_coord.* +% 24 < 65 and
                v.cur_sprite_y.* -% v.link_y_coord.* +% 32 < 81 and
                (v.bg1_x_offset.* | v.bg1_y_offset.*) & 0xff != 0)
            {
                v.sprite_z_vel[i] = 20;
                v.sprite_ai_state[i] = 1;
            }
        },
        1 => { // spawn leaves
            if (v.sprite_z[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sound_effect_2.* = 0x1b;
                v.sprite_x_vel[i] = cm.byte(-4);
                v.sprite_y_vel[i] = cm.byte(-4);
                var j = ix(a.LumberjackTree_SpawnLeaves(k));
                v.sprite_x_vel[j] = 5;
                v.sprite_y_vel[j] = 5;
                j = ix(a.LumberjackTree_SpawnLeaves(k));
                v.sprite_x_vel[j] = 5;
                v.sprite_y_vel[j] = cm.byte(-4);
                j = ix(a.LumberjackTree_SpawnLeaves(k));
                v.sprite_x_vel[j] = cm.byte(-4);
                v.sprite_y_vel[j] = 4;
            }
        },
        2 => { // dancing leaves
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 8;
                if (v.sprite_subtype2[i] == 6)
                    v.sprite_state[i] = 0;
                v.sprite_subtype2[i] +%= 1;
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part30.zig
// ---------------------------------------------------------------------------
pub export fn DashTreeTop_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var oam = cm.oamPtr();

    // BYTE(dungmap_var7) -= 0x20; HIBYTE(dungmap_var7) -= 0x20;
    const xb: u8 = @as(u8, @truncate(v.dungmap_var7.*)) -% 0x20;
    const yb: u8 = @as(u8, @truncate(v.dungmap_var7.* >> 8)) -% 0x20;
    v.dungmap_var7.* = (@as(u16, yb) << 8) | xb;

    if (v.sprite_subtype2[i] == 0) {
        var n: usize = 0;
        while (n < 16) : (n += 1) {
            oam[n].x = xb +% @as(u8, @truncate((n & 3) * 0x10));
            oam[n].y = yb +% @as(u8, @truncate((n >> 2) * 0x10));
            // WORD(oam[i].charnum): the low byte is the tile, the high byte the flags.
            oam[n].charnum = @truncate(t.kDashTreeTop_CharFlags[n]);
            oam[n].flags = @truncate(t.kDashTreeTop_CharFlags[n] >> 8);
        }
        a.Sprite_CorrectOamEntries(k, 15, 2);
    } else {
        const j: usize = v.sprite_subtype2[i] - 1;
        var n: c_int = 15;
        while (n >= 0) : ({
            n -= 1;
            oam += 1;
        }) {
            const idx = ix(n);
            oam[0].x = xb +% cm.byte(t.kDashTreeTop_X[idx]);
            oam[0].y = yb +% cm.byte(t.kDashTreeTop_Y[idx]);
            oam[0].charnum = @bitCast(t.kDashTreeTop_Char[j]);
            oam[0].flags = @bitCast(t.kDashTreeTop_Flags[j]);
        }
        a.Sprite_CorrectOamEntries(k, 15, 2);
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part31.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_12_Moblin(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Moblin_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXY(k);
    a.Sprite_CheckTileCollision2(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // select dir
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = t.kMoblin_Delay[a.GetRandomNumber() & 3];
                v.sprite_ai_state[i] +%= 1;
                v.sprite_D[i] = v.sprite_head_dir[i];
                const j: usize = v.sprite_head_dir[i];
                v.sprite_x_vel[i] = @bitCast(t.kMoblin_Xvel[j]);
                v.sprite_y_vel[i] = @bitCast(t.kMoblin_Yvel[j]);
            }
        },
        1 => { // walk
            v.sprite_graphics[i] = (v.sprite_subtype2[i] & 1) +% t.kMoblin_Gfx[v.sprite_D[i]];
            if (v.sprite_wallcoll[i] == 0) {
                if (v.sprite_delay_main[i] != 0) {
                    v.sprite_E[i] -%= 1;
                    if (sign8(v.sprite_E[i])) {
                        v.sprite_E[i] = 11;
                        v.sprite_subtype2[i] +%= 1;
                    }
                    return;
                }
                if (v.sprite_D[i] == a.Sprite_DirectionToFaceLink(k, null)) {
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_delay_main[i] = 32;
                    a.Sprite_ZeroVelocity_XY(k);
                    v.sprite_z_vel[i] = 0;
                    return;
                }
                v.sprite_delay_main[i] = 0x10;
            } else {
                v.sprite_delay_main[i] = 0xc;
            }
            v.sprite_head_dir[i] = t.kMoblin_Dirs[@as(usize, v.sprite_D[i]) << 1 | @as(usize, a.GetRandomNumber() & 1)];
            v.sprite_ai_state[i] = 0;
            v.sprite_C[i] +%= 1;
            if (v.sprite_C[i] == 4) {
                v.sprite_C[i] = 0;
                v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null);
            }
            a.Sprite_ZeroVelocity_XY(k);
            v.sprite_z_vel[i] = 0;
        },
        2 => { // throw spear
            var j: usize = v.sprite_D[i];
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] = 0;
            if (v.sprite_delay_main[i] < 16) {
                if (v.sprite_delay_main[i] == 15) {
                    a.Moblin_MaterializeSpear(k);
                    v.sprite_delay_aux1[i] = 32;
                }
                j += 4;
            }
            v.sprite_graphics[i] = t.kMoblin_Gfx2[j];
        },
        else => {},
    }
}

pub export fn Sprite_0E_Snapdragon(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_graphics[i] = v.sprite_B[i] +% t.kSnapDragon_Gfx[v.sprite_D[i]];
    SnapDragon_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_B[i] = 0;
    switch (v.sprite_ai_state[i]) {
        0 => { // resting
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = t.kSnapDragon_Delay[(a.GetRandomNumber() & 12) >> 2];
                v.sprite_A[i] -%= 1;
                if (sign8(v.sprite_A[i])) {
                    v.sprite_A[i] = 3;
                    v.sprite_delay_main[i] = 96;
                    v.sprite_C[i] +%= 1;
                    v.sprite_D[i] = a.Sprite_IsBelowLink(k).a *% 2 +% a.Sprite_IsRightOfLink(k).a;
                } else {
                    v.sprite_D[i] = a.GetRandomNumber() & 3;
                }
            } else if (v.sprite_delay_main[i] & 0x18 != 0) {
                v.sprite_B[i] +%= 1;
            }
        },
        1 => { // attack
            v.sprite_B[i] +%= 1;
            a.Sprite_MoveXY(k);
            if (a.Sprite_CheckTileCollision(k) != 0)
                v.sprite_D[i] ^= 3;
            const j: usize = @as(usize, v.sprite_D[i]) + @as(usize, if (v.sprite_C[i] != 0) 4 else 0);
            v.sprite_x_vel[i] = @bitCast(t.kSnapDragon_Xvel[j]);
            v.sprite_y_vel[i] = @bitCast(t.kSnapDragon_Yvel[j]);
            a.Sprite_MoveZ(k);
            v.sprite_z_vel[i] -%= 4;
            if (sign8(v.sprite_z[i])) {
                v.sprite_z[i] = 0;
                if (v.sprite_delay_main[i] == 0) {
                    v.sprite_ai_state[i] = 0;
                    v.sprite_C[i] = 0;
                    v.sprite_delay_main[i] = 63;
                } else {
                    v.sprite_z_vel[i] = 20;
                }
            }
        },
        else => {},
    }
}

pub export fn SnapDragon_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kSnapDragon_Dmd[@as(usize, v.sprite_graphics[i]) * 4], 4, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_11_Hinox(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Hinox_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_F[i] != 0) {
        a.Hinox_FaceLink(k);
        v.sprite_ai_state[i] = 2;
        v.sprite_delay_main[i] = 48;
    }
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // select dir
            if (v.sprite_delay_main[i] == 0) {
                if (a.GetRandomNumber() & 3 == 0) {
                    v.sprite_ai_state[i] = 2;
                    v.sprite_delay_main[i] = 64;
                } else {
                    v.sprite_C[i] +%= 1;
                    if (v.sprite_C[i] == 4) {
                        v.sprite_C[i] = 0;
                        a.Hinox_FaceLink(k);
                    } else {
                        a.Hinox_SetDirection(k, t.kHinox_RandomDirs[@as(usize, v.sprite_D[i]) * 2 + @as(usize, a.GetRandomNumber() & 1)]);
                    }
                }
            }
        },
        1 => { // walk
            if (v.sprite_delay_main[i] != 0) {
                v.sprite_A[i] -%= 1;
                if (sign8(v.sprite_A[i])) {
                    v.sprite_A[i] = 11;
                    v.sprite_subtype2[i] +%= 1;
                }
                a.Sprite_MoveXY(k);
                if (a.Sprite_CheckTileCollision(k) == 0) {
                    v.sprite_graphics[i] = t.kHinox_WalkGfx[v.sprite_D[i]] +% (v.sprite_subtype2[i] & 1);
                    return;
                }
            }
            v.sprite_delay_main[i] = 16;
            v.sprite_ai_state[i] = 0;
        },
        2 => { // throw bomb
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 2;
                return;
            }
            if (v.sprite_delay_main[i] == 32) {
                var info: SpriteSpawnInfo = undefined;
                const j = a.Sprite_SpawnDynamically(k, 0x4a, &info);
                if (j >= 0) {
                    const ju = ix(j);
                    a.Sprite_TransmuteToBomb(j);
                    v.sprite_delay_aux1[ju] = 64;
                    const d: usize = v.sprite_D[i];
                    a.Sprite_SetX(j, info.r0_x +% s16(t.kHinox_BombX[d]));
                    a.Sprite_SetY(j, info.r2_y +% s16(t.kHinox_BombY[d]));
                    v.sprite_x_vel[ju] = @bitCast(t.kHinox_BombXvel[d]);
                    v.sprite_y_vel[ju] = @bitCast(t.kHinox_BombYvel[d]);
                    v.sprite_z_vel[ju] = 40;
                }
            } else {
                v.sprite_graphics[i] = t.kHinox_Gfx[@as(usize, v.sprite_D[i]) +
                    @as(usize, if (v.sprite_delay_main[i] < 32) 4 else 0)];
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part32.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_39_Locksmith(k: c_int) callconv(.c) void {
    const i = ix(k);
    MiddleAgedMan_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);

    switch (v.sprite_ai_state[i]) {
        0 => { // chilling
            _ = a.Sprite_ShowSolicitedMessage(k, 0x107);
            const bak = v.sprite_x_lo[i];
            v.sprite_x_lo[i] -%= 16;
            a.Sprite_Get16BitCoords(k);
            v.sprite_x_vel[i] = 1;
            v.sprite_y_vel[i] = 1;
            if (a.Sprite_CheckTileCollision(k) == 0) {
                v.sprite_ai_state[i] +%= 1;
                if (v.follower_indicator.* != 0)
                    v.sprite_ai_state[i] = 5;
            }
            v.sprite_x_lo[i] = bak;
        },
        1 => { // transition to tagalong
            v.follower_indicator.* = 9;
            v.tagalong_var5.* = 0;
            a.LoadFollowerGraphics();
            a.Follower_Initialize();
            v.word_7E02CD.* = 0x40;
            v.sprite_state[i] = 0;
        },
        2 => { // offer chest
            if (a.Sprite_CheckIfLinkIsBusy()) return;
            const j = if (v.follower_dropped.* != 0)
                a.Sprite_ShowSolicitedMessage(k, 0x109)
            else
                a.Sprite_ShowMessageOnContact(k, 0x109);
            if (j & 0x100 != 0)
                v.sprite_ai_state[i] = 3;
        },
        3 => { // react to secret keeping
            if (v.choice_in_multiselect_box.* == 0) {
                if (v.follower_dropped.* != 0) {
                    a.Sprite_ShowMessageUnconditional(0x10c);
                    v.sprite_ai_state[i] = 2;
                } else {
                    v.item_receipt_method.* = 0;
                    a.Link_ReceiveItem(0x16, 0);
                    v.sram_progress_indicator_3.* |= 0x10;
                    v.sprite_ai_state[i] = 4;
                    v.follower_indicator.* = 0;
                }
            } else {
                a.Sprite_ShowMessageUnconditional(0x10a);
                v.sprite_ai_state[i] = 2;
            }
        },
        4 => _ = a.Sprite_ShowSolicitedMessage(k, 0x10b), // promise reminder
        5 => _ = a.Sprite_ShowSolicitedMessage(k, 0x107), // silence other tagalong
        else => {},
    }
}

pub export fn MiddleAgedMan_Draw(k: c_int) callconv(.c) void {
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kMiddleAgedMan_Dmd[0], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_2B_Hobo(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => Sprite_Hobo_Bum(k),
        1 => Sprite_Hobo_Bubble(k),
        2 => Sprite_Hobo_Fire(k),
        3 => Sprite_Hobo_Smoke(k),
        else => {},
    }
}

pub export fn Sprite_Hobo_Bum(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Hobo_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_flags4[i] = 3;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        a.Sprite_NullifyHookshotDrag();
        v.link_speed_setting.* = 0;
        a.Link_CancelDash();
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // sleeping
            v.sprite_flags4[i] = 7;
            if (a.Sprite_CheckDamageToLink_same_layer(k) and v.filtered_joypad_L.* & 0x80 != 0) {
                v.sprite_ai_state[i] = 1;
                const j = ix(v.sprite_E[i]);
                v.sprite_delay_main[j] = 4;
                v.flag_is_link_immobilized.* = 1;
            }
            if (v.sprite_delay_aux2[i] == 0) {
                v.sprite_delay_aux2[i] = 160;
                v.sprite_E[i] = @truncate(@as(u32, @bitCast(Hobo_SpawnBubble(k))));
            }
        },
        1 => { // wake up
            if (v.sprite_delay_main[i] == 0) {
                const j: usize = v.sprite_A[i];
                if (j != 7) {
                    v.sprite_graphics[i] = @bitCast(t.kHobo_Gfx[j]);
                    v.sprite_delay_main[i] = @bitCast(t.kHobo_Delay[j]);
                    v.sprite_A[i] +%= 1;
                } else {
                    a.Sprite_ShowMessageUnconditional(0xd7);
                    v.sprite_ai_state[i] = 2;
                }
            }
        },
        2 => { // grant bottle
            v.sprite_ai_state[i] = 3;
            v.sprite_graphics[i] = 1;
            v.save_ow_event_info[@as(u8, @truncate(v.overworld_screen_index.*))] |= 0x20;
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(0x16, 0);
            v.sram_progress_indicator_3.* |= 1;
        },
        3 => { // back to sleep
            v.flag_is_link_immobilized.* = 0;
            v.sprite_graphics[i] = 0;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 160;
                _ = Hobo_SpawnBubble(k);
            }
        },
        else => {},
    }
}

pub export fn SpritePrep_Hobo_SpawnSmoke(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x2b, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_subtype2[ju] = 0;
        v.sprite_ignore_projectile[ju] = 0;
    }
}

pub export fn Sprite_Hobo_Bubble(k: c_int) callconv(.c) void {
    const i = ix(k);
    _ = a.Oam_AllocateFromRegionC(4);
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_graphics[i] = (v.frame_counter.* >> 4 & 1) +% 2;
    if (v.sprite_delay_aux1[i] == 0) {
        v.sprite_graphics[i] +%= 1;
        a.Sprite_MoveZ(k);
        if (v.sprite_delay_main[i] == 0)
            v.sprite_state[i] = 0;
    }
    if (v.sprite_delay_main[i] < 4)
        v.sprite_graphics[i] = 3;
}

pub export fn Hobo_SpawnBubble(k: c_int) callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x2b, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_subtype2[ju] = 1;
        v.sprite_z_vel[ju] = 2;
        v.sprite_delay_main[ju] = 96;
        v.sprite_delay_aux1[ju] = 96 >> 1;
        v.sprite_ignore_projectile[ju] = 96 >> 1;
        v.sprite_flags2[ju] = 0;
    }
    return j;
}

pub export fn Sprite_Hobo_Fire(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
    v.sprite_oam_flags[i] &= ~@as(u8, 0x40);
    if (v.sprite_delay_main[i] == 0) {
        Hobo_SpawnSmoke(k);
        v.sprite_delay_main[i] = 47;
    }
}

pub export fn SpritePrep_Hobo_SpawnFire(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x2b, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetX(j, 0x194);
        a.Sprite_SetY(j, 0x03f);
        v.sprite_subtype2[ju] = 2;
        v.sprite_ignore_projectile[ju] = 2;
        v.sprite_flags2[ju] = 0;
        v.sprite_oam_flags[ju] = v.sprite_oam_flags[ju] & ~@as(u8, 0xe) | 2;
    }
}

pub export fn Sprite_Hobo_Smoke(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_graphics[i] = 6;
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_MoveXY(k);
    a.Sprite_MoveZ(k);
    v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & 0x3f | t.kHoboSmoke_OamFlags[v.frame_counter.* >> 4 & 3];
    if (v.sprite_delay_main[i] == 0)
        v.sprite_state[i] = 0;
}

pub export fn Hobo_SpawnSmoke(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x2b, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        a.Sprite_SetY(j, info.r2_y -% 4);
        v.sprite_subtype2[ju] = 3;
        v.sprite_z_vel[ju] = 7;
        v.sprite_delay_main[ju] = 96;
        v.sprite_ignore_projectile[ju] = 96;
        v.sprite_flags2[ju] = 0;
    }
}

pub export fn Sprite_73_UncleAndPriest(k: c_int) callconv(.c) void {
    switch (v.sprite_E[ix(k)]) {
        0 => a.Sprite_Uncle(k),
        1 => a.Sprite_Priest(k),
        2 => a.Sprite_SanctuaryMantle(k),
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part33.zig
// ---------------------------------------------------------------------------
/// sprite_main.c keeps this as a file-local accessor into work RAM rather than
/// a name in variables.zig, so it is re-derived here.

pub export fn SpritePrep_UncleAndPriest_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (@as(u8, @truncate(v.dungeon_room_index.*)) == 18) {
        a.Priest_SpawnMantle(k);
        if (v.sram_progress_indicator.* >= 3)
            v.sram_progress_flags.* |= 2;
        if (v.sram_progress_flags.* & 2 != 0) {
            v.sprite_state[i] = 0;
            return;
        }
        v.sprite_E[i] = 1;
        v.sprite_flags2[i] = v.sprite_flags2[i] & 0xf0 | 0x2;
        v.sprite_flags4[i] = 3;
        var j: usize = undefined;
        if (v.link_sword_type.* >= 2) {
            v.sprite_D[i] = 4;
            v.sprite_graphics[i] = 0;
            j = 0;
        } else {
            v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
            v.sprite_head_dir[i] = v.sprite_D[i];
            if (v.follower_indicator.* == 1) {
                v.sram_progress_flags.* |= 0x4;
                v.save_ow_event_info[0x1b] |= 0x20;
                v.sprite_delay_main[i] = 170;
                j = 1;
            } else {
                j = 2;
            }
        }
        v.sprite_subtype2[i] = @truncate(j);
        a.Sprite_SetX(k, a.Sprite_GetX(k) -% 6);
        a.Sprite_SetY(k, a.Sprite_GetY(k) +% @as(u16, @bitCast(t.kUncleAndSage_Y[j])));
        v.sprite_ignore_projectile[i] +%= 1;
        byte_7FFE01.* = 0;
    } else if (@as(u8, @truncate(v.dungeon_room_index.*)) == 4) {
        if (v.sram_progress_flags.* & 0x10 == 0)
            v.sprite_x_lo[i] +%= 8
        else
            v.sprite_state[i] = 0;
    } else {
        if (v.sram_progress_flags.* & 1 == 0) {
            v.sprite_D[i] = 3;
            v.sprite_subtype2[i] = 1;
        } else {
            v.sprite_state[i] = 0;
        }
    }
}

pub export fn SpritePrep_OldMan_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    if (@as(u8, @truncate(v.dungeon_room_index.*)) == 0xe4) {
        v.sprite_subtype2[i] = 2;
        return;
    }
    if (v.follower_indicator.* == 0) {
        if (v.link_item_mirror.* == 2)
            v.sprite_state[i] = 0;
        v.follower_indicator.* = 4;
        a.LoadFollowerGraphics();
        v.follower_indicator.* = 0;
    } else {
        v.sprite_state[i] = 0;
        a.LoadFollowerGraphics();
    }
}

pub export fn Sprite_TutorialGuardOrBarrier(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_type[i] == 0x40) {
        a.Sprite_EvilBarrier(k);
        return;
    }
    const jbak = v.sprite_D[i];
    if (v.sprite_delay_aux1[i] != 0)
        v.sprite_D[i] = t.kSoldier_DirectionLockSettings[jbak];

    v.sprite_graphics[i] = t.kSprite_TutorialEntities_Tab[v.sprite_D[i]];
    a.TutorialSoldier_Draw(k);
    v.sprite_D[i] = jbak;

    if (a.Sprite_ReturnIfInactive(k)) return;
    _ = a.Sprite_CheckDamageFromLink(k);

    if (@as(u8, @truncate(v.overworld_area_index.*)) == 0x1b and
        (v.sprite_y_lo[i] == 0x50 or v.sprite_y_lo[i] == 0x90))
    {
        _ = a.Sprite_TutorialGuard_ShowMessageOnContact(k, if (v.sprite_y_lo[i] == 0x50) 0xb2 else 0xb3);
    } else {
        if (a.Sprite_TutorialGuard_ShowMessageOnContact(k, @as(u16, v.byte_7E0B69.*) + 0xf))
            v.byte_7E0B69.* = if (v.byte_7E0B69.* != 6) v.byte_7E0B69.* +% 1 else 0;
    }
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 0x1f == 0) {
        const prev = v.sprite_D[i];
        v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
        if (v.sprite_D[i] != prev and (v.sprite_D[i] ^ prev) & 2 == 0)
            v.sprite_delay_aux1[i] = 12;
    }
}

pub export fn Sprite_F2_MedallionTablet(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => a.MedallionTablet_Main(k),
        1 => a.Sprite_DustCloud(k),
        else => {},
    }
}

pub export fn Sprite_33_RupeePull(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_CheckIfLinkIsBusy()) return;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        v.link_need_for_pullforrupees_sprite.* = 1;
        v.sprite_A[i] = 1;
    } else {
        if (v.sprite_A[i] != 0) {
            v.link_need_for_pullforrupees_sprite.* = 0;
            if (v.link_state_bits.* & 1 != 0) {
                v.sprite_state[i] = 0;
                a.RupeePull_SpawnPrize(k);
                a.Sprite_SpawnPoofGarnish(k);
            }
        }
    }
}

pub export fn Sprite_14_ThievesTownGrate(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_CheckIfLinkIsBusy()) return;
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        v.link_need_for_pullforrupees_sprite.* = 1;
        v.sprite_A[i] = 1;
    } else {
        if (v.sprite_A[i] == 0) return;
        v.link_need_for_pullforrupees_sprite.* = 0;
        if (v.link_state_bits.* & 1 == 0) return;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x1f);
        a.OpenGargoylesDomain();
        const j = a.Sprite_SpawnDustCloud(k);
        a.Sprite_SetX(j, a.Sprite_GetX(k));
        a.Sprite_SetY(j, a.Sprite_GetY(k));
        v.sprite_state[i] = 0;
    }
}

pub export fn SpritePrep_Snitch_bounce_2(k: c_int) callconv(.c) void {
    a.SpritePrep_Snitches(k);
}

pub export fn SpritePrep_Snitch_bounce_3(k: c_int) callconv(.c) void {
    a.SpritePrep_Snitches(k);
}

pub export fn Sprite_37_Waterfall(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => a.Waterfall(k),
        1 => a.Sprite_BatCrash(k),
        else => {},
    }
}

pub export fn Sprite_38_EyeStatue(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_B[i] == 0) {
        var info: PrepOamCoordsRet = undefined;
        a.Sprite_PrepOamCoord(k, &info);
        if (a.Sprite_ReturnIfInactive(k)) return;
        if (a.Sprite_DirectionToFaceLink(k, null) == 2 and v.sprite_unk2[i] == 9) {
            v.dung_flag_statechange_waterpuzzle.* +%= 1;
            v.sprite_B[i] = 1;
        }
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part34.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_3A_MagicBat(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_head_dir[i] != 0) {
        a.Sprite_MadBatterBolt(k);
        return;
    }

    if (v.sprite_ai_state[i] != 0)
        a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_MoveXY(k);
    a.Sprite_MoveZ(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // wait for summon
            if (v.link_magic_consumption.* >= 2) return;
            if (!a.Sprite_CheckDamageToLink_same_layer(k)) return;
            var n: c_int = 4;
            while (n >= 0) : (n -= 1) {
                if (v.ancilla_type[ix(n)] == 0x1a) {
                    _ = a.Sprite_SpawnSuperficialBombBlast(k);
                    a.SpriteSfx_QueueSfx1WithPan(k, 0xd);
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_A[i] = 20;
                    v.flag_is_link_immobilized.* = 1;
                    v.sprite_oam_flags[i] |= 32;
                    return;
                }
            }
        },
        1 => { // RisingUp
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_A[i] -%= 1;
                v.sprite_delay_main[i] = v.sprite_A[i];
                if (v.sprite_delay_main[i] != 1) {
                    v.sprite_z_vel[i] = v.sprite_delay_main[i] >> 2;
                    v.sprite_x_vel[i] +%= @bitCast(t.kMadBatter_RisingUp_XAccel[v.sprite_A[i] & 1]);
                    v.sprite_graphics[i] ^= 1;
                } else {
                    a.Sprite_ShowMessageUnconditional(0x110);
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_graphics[i] = 0;
                    v.sprite_z_vel[i] = 0;
                    v.sprite_x_vel[i] = 0;
                    v.sprite_delay_main[i] = 255;
                }
            }
        },
        2 => { // PseudoAttackPlayer
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_aux1[i] = 64;
            }
            v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & ~@as(u8, 0xe) |
                @as(u8, @bitCast(t.kMadBatter_PseudoAttack_OamFlags[v.sprite_delay_main[i] >> 1 & 7]));
            if (v.sprite_delay_main[i] == 240)
                a.Sprite_MagicBat_SpawnLightning(k);
        },
        3 => { // DoublePlayerMagicPower
            if (v.sprite_delay_aux1[i] == 0) {
                a.Sprite_ShowMessageUnconditional(0x111);
                a.Palette_Restore_BG_And_HUD();
                v.flag_update_cgram_in_nmi.* +%= 1;
                v.sprite_ai_state[i] +%= 1;
                v.link_magic_consumption.* = 1;
                a.Hud_RefreshIcon();
            } else if (v.sprite_delay_aux1[i] == 0x10) {
                v.intro_times_pal_flash.* = 0x10;
            }
        },
        4 => { // LaterBitches
            a.Sprite_SpawnDummyDeathAnimation(k);
            v.sprite_state[i] = 0;
            v.flag_is_link_immobilized.* = 0;
        },
        else => {},
    }
}

pub export fn SpritePrep_Zelda_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.link_sword_type.* >= 2) {
        v.sprite_state[i] = 0;
        return;
    }
    v.sprite_ignore_projectile[i] +%= 1;
    v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
    v.sprite_head_dir[i] = v.sprite_D[i];
    const bak0 = v.follower_indicator.*;
    v.follower_indicator.* = 1;
    a.LoadFollowerGraphics();
    v.follower_indicator.* = bak0;

    if (@as(u8, @truncate(v.dungeon_room_index.*)) == 0x12) {
        v.sprite_subtype2[i] = 2;
        if (v.sram_progress_flags.* & 4 == 0) {
            v.sprite_state[i] = 0;
        } else {
            a.Sprite_SetX(k, a.Sprite_GetX(k) +% 6);
            a.Sprite_SetY(k, a.Sprite_GetY(k) +% 15);
            v.sprite_flags4[i] = 3;
        }
    } else {
        v.sprite_subtype2[i] = 0;
        if (v.follower_indicator.* == 1 or v.sram_progress_flags.* & 4 != 0)
            v.sprite_state[i] = 0;
    }
}

pub export fn Sprite_78_MrsSahasrahla(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.ElderWife_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // initial
            if (v.link_sword_type.* < 2) {
                if (a.Sprite_ShowSolicitedMessage(k, 0x2b) & 0x100 != 0)
                    v.sprite_ai_state[i] = 1;
            } else {
                _ = a.Sprite_ShowSolicitedMessage(k, 0x2e);
            }
            v.sprite_graphics[i] = v.frame_counter.* >> 4 & 1;
        },
        1 => { // tell legend
            a.Sprite_ShowMessageUnconditional(0x2c);
            v.sprite_ai_state[i] = 2;
        },
        2 => { // loop until player not dumb
            if (v.choice_in_multiselect_box.* == 0) {
                v.sprite_ai_state[i] = 3;
                a.Sprite_ShowMessageUnconditional(0x2d);
            } else {
                a.Sprite_ShowMessageUnconditional(0x2c);
            }
        },
        3 => { // go away find old man
            _ = a.Sprite_ShowSolicitedMessage(k, 0x2d);
            v.sprite_graphics[i] = v.frame_counter.* >> 4 & 1;
        },
        else => {},
    }
}

pub export fn Sprite_16_Elder_bounce(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Elder_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);
    switch (v.sprite_subtype2[i]) {
        0 => a.Sprite_Sahasrahla(k),
        1 => a.Sprite_Aginah(k),
        else => {},
    }
}

pub export fn SpritePrep_HeartPiece(k: c_int) callconv(.c) void {
    a.HeartUpgrade_CheckIfAlreadyObtained(k);
}

pub export fn Sprite_2D_TelepathicTile(k: c_int) callconv(.c) void {
    // The C body is a bare assert(0): this sprite is never dispatched.
    _ = k;
    unreachable;
}

// ---------------------------------------------------------------------------
// from sprite_main_part35.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_25_TalkingTree(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => a.TalkingTree_Mouth(k),
        1 => a.TalkingTree_Eye(k),
        else => {},
    }
}

pub export fn Sprite_1C_Statue(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_D[i] != 0) {
        v.sprite_D[i] = 0;
        v.link_speed_setting.* = 0;
        v.bitmask_of_dragstate.* = 0;
    }
    if (v.sprite_delay_main[i] != 0) {
        v.sprite_D[i] = 1;
        v.bitmask_of_dragstate.* = 129;
        v.link_speed_setting.* = 8;
    }
    MovableStatue_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    Statue_BlockSprites(k);
    v.dung_flag_statechange_waterpuzzle.* = 0;
    if (Statue_CheckForSwitch(k))
        v.dung_flag_statechange_waterpuzzle.* = 1;
    a.Sprite_MoveXY(k);
    a.Sprite_Get16BitCoords(k);
    a.Sprite_CheckTileCollision2(k);
    a.Sprite_ZeroVelocity_XY(k);
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        v.sprite_delay_main[i] = 7;
        a.Sprite_RepelDash();
        if (v.sprite_delay_aux1[i] != 0) {
            a.Sprite_NullifyHookshotDrag();
            return;
        }
        const j: usize = a.Sprite_DirectionToFaceLink(k, null);
        v.sprite_x_vel[i] = @bitCast(t.kMovableStatue_Xvel[j]);
        v.sprite_y_vel[i] = @bitCast(t.kMovableStatue_Yvel[j]);
    } else {
        if (v.sprite_delay_main[i] == 0)
            v.sprite_delay_aux1[i] = 13;
        // The C assigns j inside the third operand of the && chain, so the
        // direction lookup only happens once the proximity checks pass.
        var j: usize = 0;
        var near = false;
        if (v.cur_sprite_x.* -% v.link_x_coord.* +% 16 < 35 and
            v.cur_sprite_y.* -% v.link_y_coord.* +% 12 < 36)
        {
            j = a.Sprite_DirectionToFaceLink(k, null);
            near = v.link_direction_facing.* == t.kMovableStatue_Dir[j] and v.link_is_running.* == 0;
        }
        if (near) {
            v.link_is_near_moveable_statue.* = 1;
            v.sprite_A[i] = 1;
            if (v.link_grabbing_wall.* & 2 == 0 or
                t.kMovableStatue_Joypad[j] & v.joypad1H_last.* == 0 or
                (v.link_x_vel.* | v.link_y_vel.*) == 0)
                return;
            j ^= 1;
            v.sprite_x_vel[i] = @bitCast(t.kMovableStatue_Xvel[j]);
            v.sprite_y_vel[i] = @bitCast(t.kMovableStatue_Yvel[j]);
        } else {
            if (v.sprite_A[i] != 0) {
                v.sprite_A[i] = 0;
                v.link_speed_setting.* = 0;
                v.link_grabbing_wall.* = 0;
                v.link_is_near_moveable_statue.* = 0;
                v.link_cant_change_direction.* &= ~@as(u8, 1);
            }
            return;
        }
    }
    if (v.link_grabbing_wall.* & 2 == 0)
        a.Sprite_NullifyHookshotDrag();
    if (v.sprite_wallcoll[i] & 15 == 0 and v.sprite_delay_aux4[i] == 0) {
        a.SpriteSfx_QueueSfx2WithPan(k, 0x22);
        v.sprite_delay_aux4[i] = 8;
    }
}

pub export fn Statue_CheckForSwitch(k: c_int) callconv(.c) bool {
    const i = ix(k);
    var n: c_int = 3;
    while (n >= 0) : (n -= 1) {
        const j = ix(n);
        var x: u16 = a.Sprite_GetX(k) +% s16(t.kMovableStatue_SwitchX[j]);
        const y: u16 = a.Sprite_GetY(k) +% s16(t.kMovableStatue_SwitchY[j]);
        const attr = a.GetTileAttribute(v.sprite_floor[i], &x, y);
        if (attr != 0x23 and attr != 0x24 and attr != 0x25 and attr != 0x3b)
            return false;
    }
    return true;
}

pub export fn MovableStatue_Draw(k: c_int) callconv(.c) void {
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kMovableStatue_Dmd[0], 3, null);
}

pub export fn Statue_BlockSprites(k: c_int) callconv(.c) void {
    var n: c_int = 15;
    while (n >= 0) : (n -= 1) {
        const j = ix(n);
        if (v.sprite_type[j] == 0x1c or n == k or
            (n ^ @as(c_int, v.frame_counter.*)) & 1 != 0 or v.sprite_state[j] < 9)
            continue;
        const x = a.Sprite_GetX(n);
        const y = a.Sprite_GetY(n);
        if (v.cur_sprite_x.* -% x +% 12 < 24 and v.cur_sprite_y.* -% y +% 12 < 36) {
            v.sprite_F[j] = 4;
            const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 32);
            v.sprite_y_recoil[j] = pt.y;
            v.sprite_x_recoil[j] = pt.x;
        }
    }
}

pub export fn Sprite_1D_FluteQuest(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (@as(u8, @truncate(v.overworld_screen_index.*)) == 0x18) {
        if (v.link_item_flute.* == 3)
            v.sprite_state[i] = 0;
    } else {
        if (v.link_item_flute.* & 2 != 0)
            v.sprite_state[i] = 0;
    }
}

pub export fn Sprite_72_FairyPond(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_A[i] != 0) {
        v.sprite_C[i] -%= 1;
        if (v.sprite_C[i] == 0)
            v.sprite_state[i] = 0;
        v.sprite_graphics[i] = v.sprite_C[i] >> 3;
        _ = a.Oam_AllocateFromRegionC(4);
        a.SpriteDraw_SingleSmall(k);
        return;
    }
    if (v.sprite_B[i] != 0) {
        a.FaerieQueen_Draw(k);
        v.sprite_graphics[i] = v.frame_counter.* >> 4 & 1;
        if (v.frame_counter.* & 15 != 0) return;
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x72, &info);
        if (j >= 0) {
            const ju = ix(j);
            a.Sprite_SetX(j, info.r0_x +% t.kWishPond_X[a.GetRandomNumber() & 7]);
            a.Sprite_SetY(j, info.r2_y +% t.kWishPond_Y[a.GetRandomNumber() & 7]);
            v.sprite_C[ju] = 31;
            v.sprite_A[ju] = 31;
            v.sprite_flags2[ju] = 0;
            v.sprite_flags3[ju] = 0x48;
            v.sprite_oam_flags[ju] = 0x48 & 0xf;
            v.sprite_B[ju] = 1;
        }
        return;
    }
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    Sprite_WishPond2(k);
}

pub export fn Sprite_WishPond2(k: c_int) callconv(.c) void {
    a.WishPond2_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (@as(u8, @truncate(v.dungeon_room_index.*)) != 21)
        a.Sprite_WishPond3(k)
    else
        a.Sprite_HappinessPond(k);
}

// ---------------------------------------------------------------------------
// from sprite_main_part36.zig
// ---------------------------------------------------------------------------
/// The `show_later_msg` label, which case 2 reaches with a goto into case 1.

pub export fn Sprite_HappinessPond(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.flag_is_link_immobilized.* = 0;
            if (v.sprite_delay_main[i] != 0 or a.Sprite_CheckIfLinkIsBusy()) return;
            if (a.Sprite_ShowMessageOnContact(k, 0x89) & 0x100 != 0) {
                v.sprite_ai_state[i] = 1;
                a.Link_ResetProperties_A();
                a.Ancilla_TerminateSparkleObjects();
                v.link_direction_facing.* = 0;
            }
        },
        1 => {
            if (v.choice_in_multiselect_box.* == 0) {
                const n: usize = @intFromBool((v.link_bomb_upgrades.* | v.link_arrow_upgrades.*) != 0);
                v.sprite_graphics[i] = @truncate(n * 2);
                // WORD(dialogue_number[0]) = WORD(kHappinessPondCostHex[n * 2]);
                v.dialogue_number[0] = t.kHappinessPondCostHex[n * 2];
                v.dialogue_number[1] = t.kHappinessPondCostHex[n * 2 + 1];
                a.Sprite_ShowMessageUnconditional(0x14e);
                v.sprite_ai_state[i] = 2;
                v.flag_is_link_immobilized.* = 1;
            } else {
                showLaterMsg(k);
            }
        },
        2 => {
            const n: usize = @as(usize, v.sprite_graphics[i]) + v.choice_in_multiselect_box.*;
            v.dialogue_number[1] = t.kHappinessPondCostHex[n];
            if (v.link_rupees_goal.* < t.kHappinessPondCost[n]) {
                showLaterMsg(k);
            } else {
                v.sprite_D[i] = t.kHappinessPondCost[n];
                v.sprite_head_dir[i] = @truncate(n);
                v.sprite_ai_state[i] = 3;
            }
        },
        3 => {
            v.sprite_delay_main[i] = 80;
            const n = v.sprite_D[i];
            v.link_rupees_goal.* -%= n;
            v.link_rupees_in_pond.* +%= n;
            a.AddHappinessPondRupees(v.sprite_head_dir[i]);
            if (v.link_rupees_in_pond.* >= 100) {
                v.link_rupees_in_pond.* -%= 100;
                v.sprite_ai_state[i] = 5;
                return;
            }
            v.dialogue_number[0] = (v.link_rupees_in_pond.* / 10) *% 16 +% (v.link_rupees_in_pond.* % 10);
            v.sprite_ai_state[i] = 4;
        },
        4 => {
            if (v.sprite_delay_main[i] == 0) {
                a.Sprite_ShowMessageUnconditional(0x94);
                v.sprite_ai_state[i] = 13;
            }
        },
        5 => {
            if (v.sprite_delay_main[i] == 0) {
                var info: SpriteSpawnInfo = undefined;
                const j = a.Sprite_SpawnDynamically(k, 0x72, &info);
                const ju = ix(j);
                a.Sprite_SetX(j, info.r0_x);
                a.Sprite_SetY(j, info.r2_y -% 80);
                v.music_control.* = 0x1b;
                v.last_music_control.* = 0;
                v.sprite_B[ju] = 1;
                a.Palette_AssertTranslucencySwap();
                a.PaletteFilter_WishPonds();
                v.sprite_E[i] = @truncate(@as(u32, @bitCast(j)));
                v.sprite_ai_state[i] = 6;
                v.sprite_delay_main[i] = 255;
            }
        },
        6 => {
            if (v.frame_counter.* & 7 == 0) {
                a.PaletteFilter_SP5F();
                if (@as(u8, @truncate(v.palette_filter_countdown.*)) == 0) {
                    a.Sprite_ShowMessageUnconditional(0x95);
                    a.Palette_RevertTranslucencySwap();
                    v.TS_copy.* = 0;
                    v.CGADSUB_copy.* = 0x20;
                    v.flag_update_cgram_in_nmi.* +%= 1;
                    v.sprite_ai_state[i] = 7;
                }
            }
        },
        7 => {
            v.sprite_ai_state[i] = if (v.choice_in_multiselect_box.* == 0) 8 else 12;
        },
        8 => {
            const n: usize = @as(usize, v.link_bomb_upgrades.*) + 1;
            if (n != 8) {
                v.link_bomb_upgrades.* = @truncate(n);
                v.link_bomb_filler.* = t.kMaxBombsForLevelHex[n];
                v.dialogue_number[0] = v.link_bomb_filler.*;
                a.Sprite_ShowMessageUnconditional(0x96);
            } else {
                v.link_rupees_goal.* +%= 100;
                a.Sprite_ShowMessageUnconditional(0x98);
            }
            v.sprite_ai_state[i] = 9;
        },
        9 => {
            a.Palette_AssertTranslucencySwap();
            v.TS_copy.* = 2;
            v.CGADSUB_copy.* = 0x30;
            v.flag_update_cgram_in_nmi.* +%= 1;
            v.sprite_ai_state[i] = 10;
        },
        10 => {
            if (v.frame_counter.* & 7 == 0) {
                a.PaletteFilter_SP5F();
                const pfc: u8 = @truncate(v.palette_filter_countdown.*);
                if (pfc == 30) {
                    v.sprite_state[v.sprite_E[i]] = 0;
                } else if (pfc == 0) {
                    v.sprite_ai_state[i] = 11;
                }
            }
        },
        11 => {
            a.PaletteFilter_RestoreSP5F();
            a.Palette_RevertTranslucencySwap();
            v.sprite_ai_state[i] = 0;
            v.sprite_delay_main[i] = 255;
        },
        12 => {
            const n: usize = @as(usize, v.link_arrow_upgrades.*) + 1;
            if (n != 8) {
                v.link_arrow_upgrades.* = @truncate(n);
                v.link_arrow_filler.* = t.kMaxArrowsForLevelHex[n];
                v.dialogue_number[0] = v.link_arrow_filler.*;
                a.Sprite_ShowMessageUnconditional(0x97);
            } else {
                v.link_rupees_goal.* +%= 100;
                a.Sprite_ShowMessageUnconditional(0x98);
            }
            v.sprite_ai_state[i] = 9;
        },
        13 => {
            a.Sprite_ShowMessageUnconditional(0x154);
            v.sprite_ai_state[i] = 14;
        },
        14 => {
            const n: usize = a.GetRandomNumber() & 3;
            v.item_drop_luck.* = t.kHappinessPondLuck[n];
            v.luck_kill_counter.* = 0;
            a.Sprite_ShowMessageUnconditional(t.kHappinessPondLuckMsg[n]);
            v.sprite_ai_state[i] = 0;
            v.sprite_delay_main[i] = 255;
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part37.zig
// ---------------------------------------------------------------------------
pub export fn Octorock_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    if (v.sprite_D[i] != 3) {
        const oam = oamPtr();
        const j = @as(usize, v.sprite_C[i]) * 3 + @as(usize, v.sprite_D[i]);
        setOam(
            oam,
            info.x +% s16(t.kOctorock_Draw_X[j]),
            info.y +% s16(t.kOctorock_Draw_Y[j]),
            t.kOctorock_Draw_Char[j],
            t.kOctorock_Draw_Flags[j] | info.flags,
            0,
        );
    }
    v.oam_cur_ptr.* +%= 4;
    v.oam_ext_cur_ptr.* +%= 1;
    v.sprite_flags2[i] -%= 1;
    a.Sprite_PrepAndDrawSingleLargeNoPrep(k, &info);
    v.sprite_flags2[i] +%= 1;
}

pub export fn Sprite_02_StalfosHead(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_floor[i] = v.link_is_on_lower_level.*;
    if (v.sprite_delay_aux1[i] != 0)
        _ = a.Oam_AllocateFromRegionC(8);
    const j: usize = v.sprite_subtype2[i] >> 3 & 3;
    v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & ~@as(u8, 0x40) | t.kStalfosHead_OamFlags[j];
    v.sprite_graphics[i] = t.kStalfosHead_Gfx[j];
    v.sprite_obj_prio[i] = 0x30;
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.sprite_F[i] != 0)
        a.Sprite_ZeroVelocity_XY(k);
    a.Sprite_MoveXY(k);
    v.sprite_subtype2[i] +%= 1;

    var pt: a.ProjectSpeedRet = undefined;
    if (v.sprite_delay_main[i] != 0) {
        if (v.sprite_delay_main[i] & 1 != 0) return;
        pt = a.Sprite_ProjectSpeedTowardsLink(k, 16);
    } else {
        if ((k ^ @as(c_int, v.frame_counter.*)) & 3 != 0) return;
        pt = a.Sprite_ProjectSpeedTowardsLink(k, 16);
        pt.x = 0 -% pt.x;
        pt.y = 0 -% pt.y;
    }
    const dx: u8 = v.sprite_x_vel[i] -% pt.x;
    if (dx != 0)
        v.sprite_x_vel[i] +%= if (sign8(dx)) 1 else 0 -% @as(u8, 1);
    const dy: u8 = v.sprite_y_vel[i] -% pt.y;
    if (dy != 0)
        v.sprite_y_vel[i] +%= if (sign8(dy)) 1 else 0 -% @as(u8, 1);
}

pub export fn Sprite_SpawnSuperficialBombBlast(k: c_int) callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x4a, &info);
    if (j >= 0) {
        const ju = ix(j);
        v.sprite_state[ju] = 6;
        v.sprite_delay_aux1[ju] = 31;
        v.sprite_C[ju] = 3;
        v.sprite_flags2[ju] = 3;
        v.sprite_oam_flags[ju] = 4;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x15);
        a.Sprite_SetSpawnedCoordinates(j, &info);
    }
    return j;
}

pub export fn Sprite_SpawnDummyDeathAnimation(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xb, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_state[ju] = 6;
        v.sprite_delay_main[ju] = 15;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x14);
        v.sprite_floor[ju] = 2;
    }
}

pub export fn Sprite_MagicBat_SpawnLightning(k: c_int) callconv(.c) void {
    const i = ix(k);
    var n: usize = 0;
    while (n < 4) : (n += 1) {
        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x3a, &info);
        if (j >= 0) {
            const ju = ix(j);
            a.SpriteSfx_QueueSfx3WithPan(k, 0x1);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            a.Sprite_SetX(j, info.r0_x +% 4);
            a.Sprite_SetY(j, info.r2_y +% 12 -% v.sprite_z[i]);
            v.sprite_z[ju] = 0;
            v.sprite_y_vel[ju] = 24;
            v.sprite_head_dir[ju] = 24;
            v.sprite_ignore_projectile[ju] = 24;
            v.sprite_flags2[ju] = 0x80;
            v.sprite_flags3[ju] = 3;
            v.sprite_oam_flags[ju] = 3;
            v.sprite_delay_main[ju] = 32;
            v.sprite_graphics[ju] = 2;
            // The C shadows the loop counter with the sprite's own bolt index.
            const g: usize = v.sprite_G[i];
            v.sprite_x_vel[ju] = @bitCast(t.kSpawnMadderBolts_Xvel[g]);
            v.sprite_subtype2[ju] = @bitCast(t.kSpawnMadderBolts_St2[g]);
            v.sprite_floor[ju] = 2;
            v.sprite_G[i] +%= 1;
        }
    }
}

pub export fn Fireball_SpawnTrailGarnish(k: c_int) callconv(.c) void {
    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 != 0)
        return;
    const j = ix(a.GarnishAlloc());
    v.garnish_type[j] = 8;
    v.garnish_active.* = 8;
    v.garnish_countdown[j] = 11;
    v.garnish_x_lo[j] = @truncate(v.cur_sprite_x.*);
    v.garnish_x_hi[j] = @truncate(v.cur_sprite_x.* >> 8);
    v.garnish_y_lo[j] = @truncate(v.cur_sprite_y.* +% 16);
    v.garnish_y_hi[j] = @truncate((v.cur_sprite_y.* +% 16) >> 8);
    v.garnish_sprite[j] = @truncate(@as(u32, @bitCast(k)));
}

pub export fn GarnishSpawn_PyramidDebris(x: i8, y: i8, xvel: i8, yvel: i8) callconv(.c) void {
    const k = ix(a.GarnishAllocForce());
    v.sound_effect_2.* = 3;
    v.sound_effect_1.* = 31;
    v.sound_effect_ambient.* = 5;

    v.garnish_type[k] = 19;
    v.garnish_active.* = 19;
    v.garnish_x_lo[k] = 232 +% @as(u8, @bitCast(x));
    v.garnish_y_lo[k] = 96 +% @as(u8, @bitCast(y));
    v.garnish_x_vel[k] = @bitCast(xvel);
    v.garnish_y_vel[k] = @bitCast(yvel);
    v.garnish_countdown[k] = (a.GetRandomNumber() & 31) +% 48;
}

pub export fn Snitch_SpawnGuard(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamicallyEx(k, 0x45, &info, 0);
    if (j < 0) return;
    const ju = ix(j);
    const n: usize = if (v.sprite_type[i] == 0x3d)
        0
    else if (v.sprite_type[i] == 0x35)
        1
    else
        2;
    a.Sprite_SetX(j, t.kCrazyVillageSoldier_X[n] +% (v.sprcoll_x_base.* & 0xff00));
    a.Sprite_SetY(j, t.kCrazyVillageSoldier_Y[n] +% (v.sprcoll_y_base.* & 0xff00));
    v.sprite_floor[ju] = 0;
    v.sprite_health[ju] = 4;
    v.sprite_defl_bits[ju] = 0x80;
    v.sprite_flags5[ju] = 0x90;
    v.sprite_oam_flags[ju] = 0xb;
}

// ---------------------------------------------------------------------------
// from sprite_main_part38.zig
// ---------------------------------------------------------------------------
pub export fn Babusu_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_graphics[i] != 0xff) {
        a.Sprite_DrawMultiple(k, &t.kBabusu_Dmd[@as(usize, v.sprite_graphics[i]) * 2], 2, null);
    } else {
        var info: PrepOamCoordsRet = undefined;
        a.Sprite_PrepOamCoord(k, &info);
    }
}

pub export fn Wizzrobe_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Sprite_DrawMultiple(k, &t.kWizzrobe_Dmd[@as(usize, v.sprite_graphics[i]) * 3], 3, null);
}

pub export fn Wizzbeam_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Sprite_DrawMultiple(k, &t.kWizzbeam_Dmd[@as(usize, v.sprite_D[i]) * 2], 2, null);
}

pub export fn Freezor_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_graphics[i] != 7) {
        a.Sprite_DrawMultiple(k, &t.kFreezor_Dmd0[@as(usize, v.sprite_graphics[i]) * 4], 4, null);
    } else {
        a.Sprite_DrawMultiple(k, &t.kFreezor_Dmd1[0], 8, null);
    }
}

pub export fn Zazak_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kZazak_Dmd[@as(usize, v.sprite_graphics[i]) * 3], 3, &info);
    if (v.sprite_pause[i] != 0) return;
    const j: usize = @as(usize, v.sprite_head_dir[i]) + @as(usize, if (v.sprite_delay_aux1[i] == 0) 0 else 4);
    const oam = oamPtr();
    oam[0].charnum = t.kZazak_Char[j];
    oam[0].flags = (oam[0].flags & ~@as(u8, 0x40)) | t.kZazak_Flags[j];
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Stalfos_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (v.sprite_delay_aux2[i] != 0) {
        a.Sprite_PrepOamCoord(k, &info);
        return;
    }
    a.Sprite_DrawMultiple(k, &t.kStalfos_Dmd[@as(usize, v.sprite_graphics[i]) * 3], 3, &info);
    if (v.sprite_graphics[i] < 8 and v.sprite_pause[i] == 0) {
        const oam = oamPtr();
        const j: usize = v.sprite_head_dir[i];
        oam[0].charnum = t.kStalfos_Char[j];
        oam[0].flags = (oam[0].flags & ~@as(u8, 0x70)) | t.kStalfos_Flags[j];
    }
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Probe_CheckTileSolidity(k: c_int) callconv(.c) bool {
    const i = ix(k);
    var tiletype: u8 = undefined;
    if (v.player_is_indoors.* != 0) {
        var n: usize = if (v.sprite_floor[i] >= 1) 0x1000 else 0;
        n += @as(usize, v.cur_sprite_x.* & 0x1f8) >> 3;
        n += @as(usize, v.cur_sprite_y.* & 0x1f8) << 3;
        tiletype = v.dung_bg2_attr_table[n];
    } else {
        tiletype = a.Overworld_ReadTileAttribute(v.cur_sprite_x.* >> 3, v.cur_sprite_y.*);
    }
    v.sprite_tiletype.* = tiletype;
    return t.kSprite_SimplifiedTileAttr[tiletype] >= 1;
}

pub export fn Sprite_HumanMulti_1(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => a.Sprite_FluteDad(k),
        1 => a.Sprite_ThiefHideoutGuy(k),
        2 => a.Sprite_BlindsHutGuy(k),
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part39.zig
// ---------------------------------------------------------------------------
/// hud.zig keeps this as a file-local constant, so it is repeated here.

/// sprite_main.c keeps these as file-local accessors into work RAM rather than
/// names in variables.zig, so they are re-derived here.

pub export fn Sprite_BlindsHutGuy(k: c_int) callconv(.c) void {
    const i = ix(k);
    BlindHideoutGuy_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);
    _ = a.Sprite_TrackBodyToHead(k);
    v.sprite_head_dir[i] = 0;
    const j = a.Sprite_ShowSolicitedMessage(k, 0x172);
    if (j & 0x100 != 0) {
        v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
        v.sprite_D[i] = v.sprite_head_dir[i];
    }
}

pub export fn Sprite_ThiefHideoutGuy(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.frame_counter.* & 3 == 0) {
        v.sprite_graphics[i] = 2;
        const dir = a.Sprite_DirectionToFaceLink(k, null);
        v.sprite_head_dir[i] = if (dir == 3) 2 else dir;
    }
    v.sprite_oam_flags[i] = 15;
    a.Oam_AllocateDeferToPlayer(k);
    a.Thief_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);
    _ = a.Sprite_ShowSolicitedMessage(k, 0x171);
    v.sprite_graphics[i] = 2;
}

pub export fn Sprite_FluteDad(k: c_int) callconv(.c) void {
    const i = ix(k);
    FluteBoyFather_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);
    v.sprite_graphics[i] = if (v.frame_counter.* < 48) 2 else (v.frame_counter.* >> 7) & 1;

    if (v.sprite_ai_state[i] != 0) {
        _ = a.Sprite_ShowSolicitedMessage(k, 0xa3);
        v.sprite_graphics[i] = 2;
    } else if (v.link_item_flute.* < 2) {
        _ = a.Sprite_ShowSolicitedMessage(k, 0xa1);
    } else if (a.Sprite_ShowSolicitedMessage(k, 0xa4) & 0x100 == 0 and
        v.hud_cur_item.* == kHudItem_Flute and v.joypad1H_last.* & 0x40 != 0 and
        a.Sprite_CheckDamageToLink_same_layer(k))
    {
        a.Sprite_ShowMessageUnconditional(0xa2);
        v.sprite_ai_state[i] +%= 1;
        v.sprite_graphics[i] = 2;
    }
}

pub export fn FluteBoyFather_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kFluteBoyFather_Dmd[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn BlindHideoutGuy_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(
        k,
        &t.kBlindHideoutGuy_Dmd[@as(usize, v.sprite_graphics[i]) * 2 + @as(usize, v.sprite_D[i]) * 4],
        2,
        &info,
    );
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_SweepingLady(k: c_int) callconv(.c) void {
    const i = ix(k);
    SweepingLady_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    _ = a.Sprite_ShowSolicitedMessage(k, 0xa5);
    a.Sprite_BehaveAsBarrier(k);
    v.sprite_graphics[i] = v.frame_counter.* >> 4 & 1;
}

pub export fn SweepingLady_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kSweepingLadyDmd[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_Lumberjacks(k: c_int) callconv(.c) void {
    const i = ix(k);
    Lumberjacks_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (Lumberjack_CheckProximity(k, 0)) {
        a.Sprite_NullifyHookshotDrag();
        v.link_speed_setting.* = 0;
        a.Link_CancelDash();
    }
    if (!a.Sprite_CheckIfLinkIsBusy() and Lumberjack_CheckProximity(k, 1) and v.filtered_joypad_L.* & 0x80 != 0) {
        const msg: usize = @intFromBool(@as(u8, @truncate(v.link_x_coord.*)) >= v.sprite_x_lo[i]) +
            @as(usize, @intFromBool(v.link_sword_type.* >= 2)) * 2;
        a.Sprite_ShowMessageUnconditional(t.kLumberJackMsg[msg]);
    }
    v.sprite_graphics[i] = v.frame_counter.* >> 5 & 1;
}

pub export fn Lumberjack_CheckProximity(k: c_int, j: c_int) callconv(.c) bool {
    _ = k;
    const n = ix(j);
    return v.cur_sprite_x.* -% v.link_x_coord.* +% t.kLumberJacks_X[n] < t.kLumberJacks_W[n] and
        v.cur_sprite_y.* -% v.link_y_coord.* +% t.kLumberJacks_Y[n] < t.kLumberJacks_H[n];
}

pub export fn Lumberjacks_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Sprite_DrawMultiple(k, &t.kLumberJacks_Dmd[@as(usize, v.sprite_graphics[i]) * 11], 11, null);
}

pub export fn Sprite_FortuneTeller(k: c_int) callconv(.c) void {
    switch (v.sprite_subtype2[ix(k)]) {
        0 => { // fortuneteller main
            FortuneTeller_Draw(k);
            if (a.Sprite_ReturnIfInactive(k)) return;
            a.FortuneTeller_LightOrDarkWorld(k, (v.savegame_is_darkworld.* >> 6 & 1) != 0);
        },
        1 => { // dwarf solidity
            if (a.Sprite_ReturnIfInactive(k)) return;
            if (a.Sprite_CheckDamageToLink_same_layer(k)) {
                a.Sprite_NullifyHookshotDrag();
                v.link_speed_setting.* = 0;
                a.Link_CancelDash();
            }
        },
        else => {},
    }
}

pub export fn FortuneTeller_PerformPseudoScience(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_graphics[i] = 0;
    v.sprite_ai_state[i] +%= 1;

    // The C fills two message slots with a macro that jumps to `done` as soon
    // as both are taken; the labelled block reproduces that early exit.
    var slots = [2]u8{ 0, 0 };
    var n: usize = 0;
    fill: {
        if (v.savegame_map_icons_indicator.* < 3) break :fill;
        if (v.link_item_book_of_mudora.* == 0) {
            slots[n] = 2;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.link_which_pendants.* & 2 == 0) {
            slots[n] = 1;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.link_item_mushroom.* < 2) {
            slots[n] = 3;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.link_item_flippers.* == 0) {
            slots[n] = 4;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.link_item_moon_pearl.* == 0) {
            slots[n] = 5;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.sram_progress_indicator.* < 3) {
            slots[n] = 6;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.link_magic_consumption.* == 0) {
            slots[n] = 7;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.link_item_bombos_medallion.* == 0) {
            slots[n] = 8;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.sram_progress_indicator_3.* & 0x10 == 0) {
            slots[n] = 9;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.sram_progress_indicator_3.* & 0x20 == 0) {
            slots[n] = 10;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.link_item_cape.* == 0) {
            slots[n] = 11;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.save_ow_event_info[0x5b] & 2 == 0) {
            slots[n] = 12;
            n += 1;
            if (n == 2) break :fill;
        }
        if (v.link_sword_type.* < 4) {
            slots[n] = 13;
            n += 1;
            if (n == 2) break :fill;
        }
        slots[n] = 14;
        n += 1;
        if (n == 2) break :fill;
        slots[n] = 15;
        n += 1;
    }
    v.sram_progress_flags.* ^= 0x40;
    const j: usize = @intFromBool(v.sram_progress_flags.* & 0x40 != 0);
    a.Sprite_ShowMessageUnconditional(t.kFortuneTeller_Readings[slots[j]]);
}

pub export fn FortuneTeller_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = @as(usize, v.savegame_is_darkworld.* >> 6 & 1) * 2 + @as(usize, v.sprite_graphics[i]);
    a.Sprite_DrawMultiple(k, &t.kFortuneTeller_Dmd[j * 3], 3, null);
}

pub export fn Smithy_SpawnDumbBarrierSprite(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x31, &info);
    if (j < 0) return;
    const ju = ix(j);
    a.Sprite_SetX(j, info.r0_x);
    a.Sprite_SetY(j, info.r2_y);
    v.sprite_subtype2[ju] = 1;
    v.sprite_flags4[ju] = 0;
    v.sprite_ignore_projectile[ju] = 1;
}

pub export fn Sprite_MazeGameLady(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Lady_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    _ = a.Sprite_TrackBodyToHead(k);
    v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
    switch (v.sprite_ai_state[i]) {
        0 => { // startup
            if (v.sprite_x_lo[i] < @as(u8, @truncate(v.link_x_coord.*))) {
                const j = a.Sprite_ShowMessageOnContact(k, 0xcc);
                if (j & 0x100 != 0) {
                    v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
                    v.sprite_D[i] = v.sprite_head_dir[i];
                    v.sprite_ai_state[i] = 1;
                    word_7FFE00_p39.* = 0;
                    word_7FFE02_p39.* = 0;
                    v.sprite_A[i] = 0;
                    v.flag_overworld_area_did_change.* = 0;
                }
            } else {
                _ = a.Sprite_ShowMessageOnContact(k, 0xd0);
            }
        },
        1 => { // sound
            a.SpriteSfx_QueueSfx3WithPan(k, 0x7);
            v.sprite_ai_state[i] = 2;
        },
        2 => { // accumulate time
            v.sprite_A[i] +%= 1;
            if (v.sprite_A[i] == 63) {
                v.sprite_A[i] = 0;
                word_7FFE00_p39.* +%= 1;
                if (word_7FFE00_p39.* == 0)
                    word_7FFE02_p39.* +%= 1;
            }
        },
        else => {},
    }
}

pub export fn Sprite_MazeGameGuy(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.MazeGameGuy_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    _ = a.Sprite_TrackBodyToHead(k);
    v.sprite_head_dir[i] = 0;
    a.Sprite_BehaveAsBarrier(k);
    v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
    if (v.flag_overworld_area_did_change.* != 0) {
        _ = a.Sprite_ShowMessageOnContact(k, 0xd0);
        return;
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // parse time
            word_7FFE04_p39.* = word_7FFE00_p39.*;
            word_7FFE06_p39.* = word_7FFE02_p39.*;
            var rem: u16 = word_7FFE04_p39.* % 6000;
            const hi = rem / 600;
            rem %= 600;
            const mid = rem / 60;
            rem %= 60;
            const lo = rem / 10;
            rem %= 10;
            v.dialogue_number[0] = @truncate(rem | lo << 4);
            v.dialogue_number[1] = @truncate(mid | hi << 4);
            const j = a.Sprite_ShowMessageOnContact(k, 0xcb);
            if (j & 0x100 != 0) {
                v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
                v.sprite_D[i] = v.sprite_head_dir[i];
                v.sprite_ai_state[i] = 1;
            }
        },
        1 => { // check qualify
            if (v.save_ow_event_info[@as(u8, @truncate(v.overworld_screen_index.*))] & 0x40 != 0) {
                a.Sprite_ShowMessageUnconditional(0xcf);
                v.sprite_ai_state[i] = 4;
            } else if (word_7FFE04_p39.* < 16) {
                a.Sprite_ShowMessageUnconditional(0xcd);
                v.sprite_head_dir[i] = v.link_player_handler_state.*; // wtf
                v.sprite_D[i] = v.sprite_head_dir[i];
                v.sprite_ai_state[i] = 3;
            } else {
                a.Sprite_ShowMessageUnconditional(0xce);
                v.sprite_head_dir[i] = v.link_player_handler_state.*; // wtf
                v.sprite_D[i] = v.sprite_head_dir[i];
                v.sprite_ai_state[i] = 2;
            }
        },
        2 => { // sorry
            const j = a.Sprite_ShowMessageOnContact(k, 0xce);
            if (j & 0x100 != 0) {
                v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
                v.sprite_D[i] = v.sprite_head_dir[i];
            }
        },
        3 => { // can have it
            const j = a.Sprite_ShowSolicitedMessage(k, 0xcd);
            if (j & 0x100 != 0) {
                v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
                v.sprite_D[i] = v.sprite_head_dir[i];
            }
        },
        4 => { // nothing more
            const j = a.Sprite_ShowSolicitedMessage(k, 0xcf);
            if (j & 0x100 != 0) {
                v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
                v.sprite_D[i] = v.sprite_head_dir[i];
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part40.zig
// ---------------------------------------------------------------------------
pub export fn Ganon_EnableInvincibility(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_hit_timer[i] & 127 == 26) {
        v.sprite_hit_timer[i] = 0;
        v.sprite_ai_state[i] = 19;
        v.sprite_delay_main[i] = 127;
        v.sprite_type[i] = 215;
    }
}

pub export fn Ganon_SpawnFallingTilesOverlord(k: c_int) callconv(.c) void {
    const i = ix(k);
    // The C scans for a free overlord slot and, when every slot is taken, walks
    // j down to -1 and indexes out of bounds; here that traps instead.
    var n: c_int = 7;
    while (n >= 0 and v.overlord_type[ix(n)] != 0) : (n -= 1) {}

    const c = v.sprite_anim_clock[i];
    if (c >= 4) return;
    v.sprite_anim_clock[i] = c + 1;

    const j = ix(n);
    const g: usize = c;
    v.overlord_type[j] = t.kGanon_Ov_Type[g];
    v.overlord_x_lo[j] = t.kGanon_Ov_X[g];
    v.overlord_x_hi[j] = @truncate(v.link_x_coord.* >> 8);
    v.overlord_y_lo[j] = t.kGanon_Ov_Y[g];
    v.overlord_y_hi[j] = @truncate(v.link_y_coord.* >> 8);
    v.overlord_gen1[j] = 0;
    v.overlord_gen2[j] = 0;
}

pub export fn Ganon_Func1(k: c_int, c: c_int) callconv(.c) void {
    const i = ix(k);
    v.tmp_counter.* = @truncate(@as(u32, @bitCast(c)));
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamicallyEx(k, 0xc9, &info, 8);
    if (j < 0) return;
    const ju = ix(j);
    a.SpriteSfx_QueueSfx2WithPan(k, 0x2a);
    a.Sprite_SetSpawnedCoordinates(j, &info);
    v.sprite_anim_clock[ju] = @truncate(@as(u32, @bitCast(c)));
    v.sprite_ignore_projectile[ju] = v.sprite_anim_clock[ju];
    v.sprite_oam_flags[ju] = 3;
    v.sprite_flags3[ju] = 0x40;
    v.sprite_flags2[ju] = 0x21;
    v.sprite_defl_bits[ju] = 0x40;
    a.Sprite_SetY(j, info.r2_y +% s16(t.kGanon_Gfx16_Y[v.sprite_D[i]]));
    a.Sprite_ApplySpeedTowardsLink(j, 32);
    v.sprite_delay_main[ju] = 16;
    v.sprite_A[ju] = v.sprite_x_lo[0];
    v.sprite_B[ju] = v.sprite_x_hi[0];
    v.sprite_C[ju] = v.sprite_y_lo[0];
    v.sprite_E[ju] = v.sprite_y_hi[0];
    v.sprite_bump_damage[ju] = 7;
    v.sprite_ignore_projectile[ju] = 7;
}

pub export fn Ganon_Phase1_AnimateTridentSpin(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = @as(usize, v.sprite_delay_main[i] >> 2 & 7) + @as(usize, if (v.sprite_D[i] != 0) 8 else 0);
    v.sprite_G[i] = t.kGanon_G_Func2[j];
    v.sprite_graphics[i] = t.kGanon_GfxFunc2[j];
    a.SwishEvery16Frames(k);
}

pub export fn Ganon_HandleAnimation_Idle(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_G[i] = t.kGanon_G[v.sprite_D[i]];
    v.sprite_graphics[i] = t.kGanon_Gfx[v.sprite_D[i]];
}

pub export fn Ganon_SelectWarpLocation(k: c_int, state: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = t.kGanon_NextSubtype[a.GetRandomNumber() & 3 | @as(usize, v.sprite_subtype[i]) << 2];
    v.sprite_subtype[i] = @truncate(j);
    v.swamola_target_x_lo[0] = t.kGanon_NextX[j];
    v.swamola_target_y_lo[0] = t.kGanon_NextY[j];
    v.sprite_ai_state[i] = @truncate(@as(u32, @bitCast(state)));
    v.sprite_x_vel[i] = 0;
    v.sprite_y_vel[i] = 0;
    v.sprite_delay_main[i] = 48;
    a.SpriteSfx_QueueSfx3WithPan(k, 0x28);
}

pub export fn Ganon_ShakeHead(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_head_dir[i] = t.kGanon_HeadDir[v.sprite_delay_main[i] >> 3];
}

pub export fn Ganon_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (sign8(v.sprite_graphics[i]) or
        (v.sprite_ai_state[i] != 19 and v.sprite_delay_aux4[i] == 0 and v.byte_7E04C5.* == 0))
    {
        _ = a.Sprite_PrepOamCoordOrDoubleRet(k, &info);
        return;
    }
    Trident_Draw(k);
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    const base = oamPtr() + 5;
    var oam = base;
    const g: usize = v.sprite_graphics[i];
    var n: usize = 0;
    while (n < 12) : ({
        n += 1;
        oam += 1;
    }) {
        const j = g * 12 + n;
        const mask: u8 = if (info.flags & 0xf >= 5) 0xf0 else 0xff;
        setOamPlain(
            oam,
            @truncate(info.x +% s16(t.kGanon_Draw_X[j])),
            @truncate(info.y +% s16(t.kGanon_Draw_Y[j])),
            t.kGanon_Draw_Char[j],
            info.flags | (t.kGanon_Draw_Flags[j] & mask),
            2,
        );
    }
    if (t.kGanon_SprOffs[g] != 15) {
        const head = base + t.kGanon_SprOffs[g];
        const j: usize = @as(usize, v.sprite_head_dir[i]) * 2 + @as(usize, if (v.sprite_D[i] != 0) 6 else 0);
        head[0].charnum = t.kGanon_Draw_Char2[j];
        head[0].flags = (head[0].flags & 0x3f) | t.kGanon_Draw_Flags2[j];

        head[1].charnum = t.kGanon_Draw_Char2[j + 1];
        head[1].flags = (head[1].flags & 0x3f) | t.kGanon_Draw_Flags2[j + 1];
    }
    if (v.submodule_index.* != 0)
        a.Sprite_CorrectOamEntries(k, 9, 0xff);

    if (v.sprite_G[i] == 9) {
        v.oam_cur_ptr.* = 0x828;
        v.oam_ext_cur_ptr.* = 0xa2a;
        a.Sprite_DrawMultiple(k, &t.kGanon_Dmd[0], 2, null);
    }

    const z: u16 = @as(u16, v.sprite_z[i]) -% 1;
    const frame: usize = if (z >> 11 > 4) 4 else z >> 11;
    v.cur_sprite_y.* +%= z;
    v.oam_cur_ptr.* = 0x9f4;
    v.oam_ext_cur_ptr.* = 0xa9d;
    const bak = v.sprite_oam_flags[i];
    v.sprite_oam_flags[i] = 0;
    v.sprite_obj_prio[i] = 48;
    a.Sprite_DrawMultiple(k, &t.kLargeShadow_Dmd[frame * 3], 3, null);
    v.sprite_oam_flags[i] = bak;
    a.Sprite_Get16BitCoords(k);
}

pub export fn Trident_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const g: usize = v.sprite_G[i];
    if (g == 0) return;

    const j: usize = if (v.sprite_G[i] == 9)
        3
    else if (v.sprite_G[i] >= 9)
        4
    else
        v.sprite_D[i];
    v.cur_sprite_x.* +%= s16(t.kTrident_Draw_X[j]);
    v.cur_sprite_y.* +%= s16(t.kTrident_Draw_Y[j]);
    const bak = v.sprite_obj_prio[i];
    v.sprite_obj_prio[i] &= ~@as(u8, 0xf);
    a.Sprite_DrawMultiple(k, &t.kTrident_Dmd[(g - 1) * 5], 5, null);
    v.sprite_obj_prio[i] = bak;
    a.Sprite_Get16BitCoords(k);
}

// ---------------------------------------------------------------------------
// from sprite_main_part41.zig
// ---------------------------------------------------------------------------
pub export fn SpritePrep_Swamola_InitializeSegments(k: c_int) callconv(.c) void {
    const i = ix(k);
    // The snes code uses the wrong bank, which glitches lanmolas in misery mire.
    var j: usize = if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
        i * 32
    else
        t.kBuggySwamolaLookup[i];
    var n: usize = 0;
    while (n < 32) : ({
        n += 1;
        j += 1;
    }) {
        v.swamola_x_lo[j] = v.sprite_x_lo[i];
        v.swamola_x_hi[j] = v.sprite_x_hi[i];
        v.swamola_y_lo[j] = v.sprite_y_lo[i];
        v.swamola_y_hi[j] = v.sprite_y_hi[i];
    }
}

pub export fn Sprite_CF_Swamola(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.sprite_ai_state[i] != 0) {
        if (sign8(v.sprite_ai_state[i])) {
            Sprite_Swamola_Ripples(k);
            return;
        }
        a.Swamola_Draw(k);
    }
    a.Sprite_Get16BitCoords(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_subtype2[i] +%= 1;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    const old_vel = v.sprite_y_vel[i];
    v.sprite_y_vel[i] +%= v.sprite_z_vel[i];
    a.Sprite_MoveXY(k);
    v.sprite_y_vel[i] = old_vel;
    switch (v.sprite_ai_state[i]) {
        0 => { // emerge
            // The C folds the direction roll into the && chain, so it is only
            // rolled once the delay has expired.
            if (v.sprite_delay_main[i] == 0) {
                const j: usize = t.kSwamola_Target_Dir[a.GetRandomNumber() & 7];
                if (j != v.sprite_D[i]) {
                    var tv: u16 = ((@as(u16, v.sprite_B[i]) << 8) | v.sprite_A[i]) +% s16(t.kSwamola_Target_X[j]);
                    v.swamola_target_x_lo[i] = @truncate(tv);
                    v.swamola_target_x_hi[i] = @truncate(tv >> 8);
                    tv = ((@as(u16, v.sprite_head_dir[i]) << 8) | v.sprite_C[i]) +% s16(t.kSwamola_Target_Y[j]);
                    v.swamola_target_y_lo[i] = @truncate(tv);
                    v.swamola_target_y_hi[i] = @truncate(tv >> 8);
                    v.sprite_ai_state[i] = 1;
                    v.sprite_x_vel[i] = 0;
                    v.sprite_y_vel[i] = 0;
                    v.sprite_z_vel[i] = cm.byte(-15);
                    Swamola_SpawnRipples(k);
                }
            }
        },
        1 => { // ascending
            if (v.sprite_subtype2[i] & 3 == 0) {
                v.sprite_z_vel[i] +%= 1;
                if (v.sprite_z_vel[i] == 0)
                    v.sprite_ai_state[i] = 2;
                const pt = Swamola_ProjectVelocityTowardsTarget(k);
                a.Sprite_ApproachTargetSpeed(k, pt.x, pt.y);
            }
        },
        2 => { // wiggle
            const j: usize = v.sprite_G[i] & 1;
            v.sprite_z_vel[i] +%= @bitCast(t.kSwamola_Z_Accel[j]);
            if (v.sprite_z_vel[i] == @as(u8, @bitCast(t.kSwamola_Z_Vel_Target[j])))
                v.sprite_G[i] +%= 1;
            const x: u16 = (@as(u16, v.swamola_target_x_hi[i]) << 8) | v.swamola_target_x_lo[i];
            const y: u16 = (@as(u16, v.swamola_target_y_hi[i]) << 8) | v.swamola_target_y_lo[i];
            if (v.cur_sprite_x.* -% x +% 8 < 16 and v.cur_sprite_y.* -% y +% 8 < 16)
                v.sprite_ai_state[i] = 3;
            const pt = Swamola_ProjectVelocityTowardsTarget(k);
            v.sprite_x_vel[i] = pt.x;
            v.sprite_y_vel[i] = pt.y;
        },
        3 => { // descending
            if (v.sprite_subtype2[i] & 3 == 0) {
                v.sprite_z_vel[i] +%= 1;
                if (v.sprite_z_vel[i] == 16) {
                    v.sprite_ai_state[i] = 4;
                    Swamola_SpawnRipples(k);
                    v.sprite_y_hi[i] = 128;
                    v.sprite_delay_main[i] = 80;
                }
            }
            if (v.sprite_subtype2[i] & 3 == 0)
                a.Sprite_ApproachTargetSpeed(k, 0, 0);
        },
        4 => { // submerge
            if (v.sprite_delay_main[i] == 0) {
                const j: usize = t.kSwamola_Target_Dir[a.GetRandomNumber() & 7];
                v.sprite_D[i] = @truncate(j);
                a.Sprite_SetX(k, ((@as(u16, v.sprite_B[i]) << 8) | v.sprite_A[i]) +% s16(t.kSwamola_Target_X[j]));
                a.Sprite_SetY(k, ((@as(u16, v.sprite_head_dir[i]) << 8) | v.sprite_C[i]) +% s16(t.kSwamola_Target_Y[j]));
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 48;
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
                v.sprite_z_vel[i] = 0;
            }
        },
        else => {},
    }
}

pub export fn Swamola_ProjectVelocityTowardsTarget(k: c_int) callconv(.c) ProjectSpeedRet {
    const i = ix(k);
    const x: u16 = (@as(u16, v.swamola_target_x_hi[i]) << 8) | v.swamola_target_x_lo[i];
    const y: u16 = (@as(u16, v.swamola_target_y_hi[i]) << 8) | v.swamola_target_y_lo[i];
    return a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 15);
}

pub export fn Swamola_SpawnRipples(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xcf, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_ai_state[ju] = 128;
        v.sprite_delay_main[ju] = 32;
        v.sprite_oam_flags[ju] = 4;
        v.sprite_ignore_projectile[ju] = 4;
        v.sprite_flags2[ju] = 0;
    }
}

pub export fn Sprite_Swamola_Ripples(k: c_int) callconv(.c) void {
    const i = ix(k);
    SwamolaRipples_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_delay_main[i] == 0)
        v.sprite_state[i] = 0;
}

pub export fn SwamolaRipples_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    _ = a.Oam_AllocateFromRegionB(8);
    a.Sprite_DrawMultiple(k, &t.kSwamolaRipples_Dmd[@as(usize, v.sprite_delay_main[i] >> 2 & 3) * 2], 2, null);
}

// ---------------------------------------------------------------------------
// from sprite_main_part42.zig
// ---------------------------------------------------------------------------
pub export fn Swamola_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const ang: usize = a.Sprite_ConvertVelocityToAngle(v.sprite_x_vel[i], v.sprite_y_vel[i] +% v.sprite_z_vel[i]);
    v.sprite_graphics[i] = t.kSwamola_Gfx[ang];
    v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & 63 | t.kSwamola_Draw_OamFlags[ang];
    a.SpriteDraw_SingleLarge(k);

    const cur = @as(usize, v.sprite_subtype2[i] & 0x1f) + i * 32;
    v.swamola_x_lo[cur] = v.sprite_x_lo[i];
    v.swamola_x_hi[cur] = v.sprite_x_hi[i];
    v.swamola_y_lo[cur] = v.sprite_y_lo[i];
    v.swamola_y_hi[cur] = v.sprite_y_hi[i];

    // Rising segments walk the oam window backwards, sinking ones forwards.
    const rising = sign8(v.sprite_y_vel[i]);
    const off: u16 = if (rising) 5 else 0;
    v.oam_cur_ptr.* +%= off * 4;
    v.oam_ext_cur_ptr.* +%= off;
    var n: usize = 0;
    while (n < 4) : (n += 1) {
        v.sprite_graphics[i] = t.kSwamola_Gfx2[n];
        const h = @as(usize, (v.sprite_subtype2[i] -% t.kSwamola_HistOffs[n]) & 31) + i * 32;
        v.cur_sprite_x.* = (@as(u16, v.swamola_x_hi[h]) << 8) | v.swamola_x_lo[h];
        v.cur_sprite_y.* = (@as(u16, v.swamola_y_hi[h]) << 8) | v.swamola_y_lo[h];
        if (rising) {
            v.oam_cur_ptr.* -%= 4;
            v.oam_ext_cur_ptr.* -%= 1;
        } else {
            v.oam_cur_ptr.* +%= 4;
            v.oam_ext_cur_ptr.* +%= 1;
        }
        a.SpriteDraw_SingleLarge(k);
    }
    v.byte_7E0FB6.* = 4;
}

pub export fn SpritePrep_Blind_PrepareBattle(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.follower_indicator.* != 6 and v.dung_savegame_state_bits.* & 0x2000 != 0) {
        v.sprite_delay_aux2[i] = 96;
        v.sprite_C[i] = 1;
        v.sprite_D[i] = 2;
        v.sprite_head_dir[i] = 4;
        v.sprite_graphics[i] = 7;
        v.byte_7E0B69.* = 0;
    } else {
        v.sprite_state[i] = 0;
    }
}

pub export fn BlindLaser_SpawnTrailGarnish(j: c_int) callconv(.c) void {
    const ji = ix(j);
    const k = ix(a.GarnishAllocOverwriteOld());
    v.garnish_type[k] = 15;
    v.garnish_active.* = 15;
    v.garnish_oam_flags[k] = v.sprite_graphics[ji];
    v.garnish_sprite[k] = @truncate(@as(u32, @bitCast(j)));
    v.garnish_x_lo[k] = v.sprite_x_lo[ji];
    v.garnish_x_hi[k] = v.sprite_x_hi[ji];
    const y = a.Sprite_GetY(j) +% 16;
    v.garnish_y_lo[k] = @truncate(y);
    v.garnish_y_hi[k] = @truncate(y >> 8);
    v.garnish_countdown[k] = 10;
}

// ---------------------------------------------------------------------------
// from sprite_main_part43.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_Blind_Head(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_obj_prio[i] |= 48;
    a.SpriteDraw_SingleLarge(k);
    const oam = oamPtr();
    {
        const d: usize = v.sprite_head_dir[i];
        oam[0].charnum = t.kBlindHead_Draw_Char[d];
        oam[0].flags = oam[0].flags & 0x3f | t.kBlindHead_Draw_Flags[d];
    }

    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_F[i] == 14)
        v.sprite_F[i] = 8;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    v.sprite_subtype[i] -%= 1;
    if (sign8(v.sprite_subtype[i])) {
        v.sprite_subtype[i] = 2;
        v.sprite_head_dir[i] = v.sprite_head_dir[i] +% 1 & 15;
    }
    if (v.sprite_delay_main[i] != 0) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_subtype2[i] +%= 1;

    // The C only decrements the spit timer once a fireball actually spawned.
    const j = a.Blind_SpitFireball(k, 0x1f);
    if (j >= 0) {
        v.sprite_z_subpos[i] -%= 1;
        if (sign8(v.sprite_z_subpos[i])) {
            v.sprite_z_subpos[i] = 4;
            const pt = a.Sprite_ProjectSpeedTowardsLink(k, 32);
            const ju = ix(j);
            v.sprite_x_vel[ju] = pt.x;
            v.sprite_y_vel[ju] = pt.y;
        }
    }

    var n: usize = v.sprite_G[i] & 1;
    if (v.sprite_x_vel[i] != @as(u8, @bitCast(t.kBlindHead_XvelLimit[n])))
        v.sprite_x_vel[i] +%= if (n != 0) 0 -% @as(u8, 1) else 1;
    if (v.sprite_x_lo[i] & 0xfe == t.kBlindHead_XposLimit[n])
        v.sprite_G[i] +%= 1;

    n = v.sprite_anim_clock[i] & 1;
    if (v.sprite_y_vel[i] != @as(u8, @bitCast(t.kBlindHead_YvelLimit[n])))
        v.sprite_y_vel[i] +%= if (n != 0) 0 -% @as(u8, 1) else 1;
    if (v.sprite_y_lo[i] & 0xfe == t.kBlindHead_YposLimit[n])
        v.sprite_anim_clock[i] +%= 1;

    if (v.sprite_F[i] == 0)
        a.Sprite_MoveXY(k);
}

pub export fn Blind_SpawnHead(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xce, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_flags3[ju] = 0x5b;
        v.sprite_oam_flags[ju] = 0x5b & 15;
        v.sprite_defl_bits[ju] = 4;
        v.sprite_A[ju] = 2;
        v.sprite_flags2[ju] = 1;
        v.sprite_flags4[ju] = 0;
        v.sprite_flags[ju] = 0;
        v.sprite_z[ju] = 23;
        v.sprite_y_lo[ju] = @truncate(23 +% info.r2_y);
        v.sprite_G[ju] = @truncate((info.r0_x >> 7) & 1);
        v.sprite_anim_clock[ju] = @truncate((info.r2_y >> 7) & 1);
        v.sprite_delay_main[ju] = 48;
    }
}

pub export fn Sprite_CE_Blind(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (sign8(v.sprite_A[i]))
        Sprite_BlindLaser(k)
    else if (v.sprite_A[i] == 2)
        Sprite_Blind_Head(k)
    else
        a.Sprite_Blind_Blind_Blind(k);
}

pub export fn Sprite_BlindLaser(k: c_int) callconv(.c) void {
    const i = ix(k);
    const d: usize = v.sprite_head_dir[i];
    v.sprite_graphics[i] = t.kBlindLaser_Gfx[d];
    v.sprite_oam_flags[i] = t.kBlindLaser_OamFlags[d] | 3;
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_delay_main[i] != 0) {
        if (v.sprite_delay_main[i] == 1)
            v.sprite_state[i] = 0;
        return;
    }
    _ = a.Sprite_CheckDamageToLink_same_layer(k);
    a.Sprite_SetX(k, a.Sprite_GetX(k) +% cm.s16(@bitCast(v.sprite_x_vel[i])));
    a.Sprite_SetY(k, a.Sprite_GetY(k) +% cm.s16(@bitCast(v.sprite_y_vel[i])));
    if (a.Sprite_CheckTileCollision(k) != 0)
        v.sprite_delay_main[i] = 12;
    a.BlindLaser_SpawnTrailGarnish(k);
}

// ---------------------------------------------------------------------------
// from sprite_main_part44.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_Blind_Blind_Blind(k: c_int) callconv(.c) void {
    const i = ix(k);

    v.sprite_obj_prio[i] |= 0x30;
    a.Blind_Draw(k);
    v.sprite_oam_flags[i] = 1;
    if (a.Sprite_ReturnIfInactive(k)) return;
    const f = v.sprite_F[i];
    if (f != 0)
        v.sprite_F[i] -%= 1;

    if (f == 11) {
        v.sprite_hit_timer[i] = 0;
        v.sprite_wallcoll[i] = 0;
        if (v.sprite_delay_aux4[i] == 0) {
            v.sprite_health[i] = 128;
            v.sprite_delay_aux4[i] = 48;
            v.sprite_oam_flags[i] &= 1;
            v.sprite_z_subpos[i] +%= 1;
            if (v.sprite_z_subpos[i] < 3) {
                v.sprite_wallcoll[i] = 96;
                v.sprite_subtype[i] = 1;
            } else {
                v.sprite_z_subpos[i] = 0;
                v.sprite_limit_instance.* +%= 1;
                if (v.sprite_limit_instance.* == 3) {
                    a.Sprite_KillFriends();
                    v.sprite_state[i] = 4;
                    v.sprite_A[i] = 0;
                    v.sprite_delay_main[i] = 255;
                    v.sprite_hit_timer[i] = 255;
                    v.flag_block_link_menu.* +%= 1;
                    a.SpriteSfx_QueueSfx3WithPan(k, 0x22);
                    return;
                }
                v.sprite_y_vel[i] = 0;
                v.sprite_x_vel[i] = 0;
                v.sprite_C[i] = 6;
                v.sprite_delay_aux2[i] = 255;
                v.sprite_ignore_projectile[i] = 255;
                a.Blind_SpawnHead(k);
            }
        }
    }

    if (v.sprite_A[i] != 0) {
        if (v.sprite_delay_main[i] == 0)
            v.sprite_state[i] = 0;
        v.sprite_graphics[i] = t.kBlind_Gfx0[v.sprite_delay_main[i] >> 3];
        return;
    }
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_subtype2[i] & 1 == 0)
        v.sprite_delay_main[i] +%= 1;

    if (v.sprite_delay_aux1[i] != 0) {
        v.sprite_ai_state[i] = 0;
        if (v.sprite_delay_aux1[i] == 8)
            a.Blind_SpawnLaser(k);
        a.Blind_CheckBumpDamage(k);
        return;
    }
    v.byte_7E0B69.* +%= 1;
    if (v.sprite_stunned[i] == 0) {
        if (v.sprite_ai_state[i] != 0) {
            v.sprite_delay_aux1[i] = 16;
            v.sprite_stunned[i] = 128;
            v.sprite_ai_state[i] = 0;
        }
    } else {
        v.sprite_stunned[i] -%= 1;
        v.sprite_ai_state[i] = 0;
    }
    v.sprite_x_hi[i] = @truncate(v.link_x_coord.* >> 8);
    v.sprite_y_hi[i] = @truncate(v.link_y_coord.* >> 8);

    switch (v.sprite_C[i]) {
        0 => { // blinded
            v.dma_var6.* = (v.dma_var6.* & 0xff00) | 0;
            v.dma_var7.* = (v.dma_var7.* & 0xff00) | 0xa0;
            if (v.sprite_delay_aux2[i] == 0) {
                v.sprite_C[i] +%= 1;
                v.sprite_delay_aux2[i] = 96;
            } else if (v.sprite_delay_aux2[i] == 80) {
                v.dialogue_message_index.* = 0x123;
                a.Sprite_ShowMessageMinimal();
            } else if (v.sprite_delay_aux2[i] == 24) {
                _ = a.SpawnBossPoof(k);
            }
        },
        1 => { // retreat to back wall
            a.Blind_CheckBumpDamage(k);
            v.sprite_graphics[i] = 9;
            if (v.sprite_delay_aux2[i] == 0) {
                v.sprite_C[i] +%= 1;
                v.sprite_delay_main[i] = 255;
                v.sprite_ignore_projectile[i] = 0;
            } else if (v.sprite_delay_aux2[i] < 64) {
                v.sprite_y_vel[i] = cm.byte(-8);
                a.Sprite_MoveY(k);
            }
            a.Blind_Animate(k);
            v.sprite_head_dir[i] = 4;
        },
        2 => { // oscillate
            a.Blind_CheckBumpDamage(k);
            a.Blind_Animate(k);
            // The C only samples Link's side once the oscillation counter wraps.
            var turned = false;
            if (v.sprite_subtype2[i] & 127 == 0)
                turned = a.Sprite_IsBelowLink(k).a +% 2 != v.sprite_D[i];
            if ((turned or v.sprite_delay_main[i] == 0) and v.sprite_x_lo[i] < 0x78) {
                v.sprite_C[i] +%= 1;
                v.sprite_y_vel[i] &= ~@as(u8, 1);
                v.sprite_x_vel[i] &= ~@as(u8, 1);
                v.sprite_delay_aux2[i] = 0x30;
                return;
            }
            var n: usize = v.sprite_B[i] & 1;
            v.sprite_y_vel[i] +%= if (n != 0) 0 -% @as(u8, 1) else 1;
            if (v.sprite_y_vel[i] == @as(u8, @bitCast(t.kBlind_Oscillate_YVelTarget[n])))
                v.sprite_B[i] +%= 1;
            n = v.sprite_G[i] & 1;
            if (v.sprite_x_vel[i] != @as(u8, @bitCast(t.kBlind_Oscillate_XVelTarget[n])))
                v.sprite_x_vel[i] +%= if (n != 0) 0 -% @as(u8, 1) else 1;
            if (v.sprite_x_lo[i] & 0xfe == t.kBlind_Oscillate_XPosTarget[n])
                v.sprite_G[i] +%= 1;
            a.Sprite_MoveXY(k);
            if (v.sprite_wallcoll[i] != 0) {
                a.Blind_FireballFlurry(k, v.sprite_wallcoll[i]);
            } else if (v.sprite_subtype2[i] & 7 == 0) {
                a.Sprite_SpawnProbeAlways(k, v.sprite_head_dir[i] << 2);
            }
        },
        3 => { // switch walls
            a.Blind_CheckBumpDamage(k);
            if (v.sprite_delay_aux2[i] != 0) {
                a.Blind_Decelerate_X(k);
                a.Sprite_MoveX(k);
                a.Blind_Decelerate_Y(k);
            } else {
                const n: usize = v.sprite_D[i] -% 2;
                if (v.sprite_y_vel[i] != @as(u8, @bitCast(t.kBlind_SwitchWall_YVelTarget[n])))
                    v.sprite_y_vel[i] +%= if (n != 0) 0 -% @as(u8, 2) else 2;
                if (v.sprite_y_lo[i] & 0xfc == t.kBlind_SwitchWall_YPosTarget[n]) {
                    v.sprite_C[i] +%= 1;
                    v.sprite_B[i] = v.sprite_D[i] -% 1;
                }
                a.Sprite_MoveXY(k);
                a.Blind_Decelerate_X(k);
            }
        },
        4 => { // whirl around
            a.Blind_CheckBumpDamage(k);
            if (v.sprite_subtype2[i] & 7 == 0) {
                const n: usize = v.sprite_D[i] -% 2;
                if (v.sprite_graphics[i] == t.kBlind_WhirlAround_Gfx[n]) {
                    v.sprite_delay_main[i] = 254;
                    v.sprite_C[i] = 2;
                    v.sprite_D[i] ^= 1;
                    v.sprite_G[i] = v.sprite_x_lo[i] >> 7;
                } else {
                    v.sprite_graphics[i] +%= if (n != 0) 1 else 0 -% @as(u8, 1);
                }
            }
            a.Blind_Decelerate_Y(k);
        },
        5 => a.Blind_FireballFlurry(k, 0x65), // fireball reprisal; wtf: argument
        6 => { // behind the curtain
            v.sprite_hit_timer[i] = 0;
            v.sprite_head_dir[i] = 12;
            if (v.sprite_delay_aux2[i] == 0) {
                v.sprite_C[i] +%= 1;
                v.sprite_delay_aux2[i] = 39;
                a.SpriteSfx_QueueSfx1WithPan(k, 0x13);
            } else if (v.sprite_delay_aux2[i] >= 224) {
                v.sprite_graphics[i] = t.kBlind_Gfx_BehindCurtain[(v.sprite_delay_aux2[i] -% 224) >> 3];
            } else {
                v.sprite_graphics[i] = 14;
            }
        },
        7 => { // rerobe
            if (v.sprite_delay_aux2[i] == 0) {
                v.sprite_C[i] = 2;
                v.sprite_delay_main[i] = 128;
                v.sprite_D[i] = (v.sprite_y_lo[i] >> 7) +% 2;
                v.sprite_G[i] = (v.sprite_x_lo[i] << 2) | (v.sprite_x_lo[i] >> 7);
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
                v.sprite_ignore_projectile[i] = 0;
            } else {
                v.sprite_graphics[i] = t.kBlind_Gfx_Rerobe[v.sprite_delay_aux2[i] >> 3];
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part45.zig
// ---------------------------------------------------------------------------
pub export fn Blind_FireballFlurry(k: c_int, w: u8) callconv(.c) void {
    const i = ix(k);
    v.sprite_wallcoll[i] -%= 1;
    v.sprite_oam_flags[i] = (w & 7) *% 2 +% 1;
    v.sprite_E[i] -%= 1;
    if (sign8(v.sprite_E[i])) {
        v.sprite_E[i] = v.sprite_subtype[i];
        v.sprite_head_dir[i] = v.sprite_head_dir[i] +% 1 & 15;
    }
    if (v.sprite_subtype2[i] & 31 == 0 and v.sprite_subtype[i] != 5)
        v.sprite_subtype[i] +%= 1;
    Blind_AnimateRobes(k);
    _ = Blind_SpitFireball(k, 0xf);
}

pub export fn Blind_SpitFireball(k: c_int, mask: u8) callconv(.c) c_int {
    const i = ix(k);
    if (v.sprite_subtype2[i] & mask != 0)
        return -1;
    const j = a.Sprite_SpawnFireball(k);
    if (j >= 0) {
        const ju = ix(j);
        a.SpriteSfx_QueueSfx3WithPan(k, 0x19);
        const d: usize = v.sprite_head_dir[i];
        v.sprite_x_vel[ju] = @bitCast(t.kBlindHead_SpawnFireball_Xvel[d]);
        v.sprite_y_vel[ju] = @bitCast(t.kBlindHead_SpawnFireball_Yvel[d]);
        v.sprite_defl_bits[ju] |= 8;
        v.sprite_bump_damage[ju] = 4;
    }
    return j;
}

pub export fn SpawnBossPoof(k: c_int) callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    // The C never checks this spawn for failure and indexes with the result.
    const j = a.Sprite_SpawnDynamically(k, 0xce, &info);
    const ju = ix(j);
    a.Sprite_SetX(j, info.r0_x +% 16);
    a.Sprite_SetY(j, info.r2_y +% 40);
    v.sprite_graphics[ju] = 0xf;
    v.sprite_A[ju] = 1;
    v.sprite_delay_main[ju] = 47;
    v.sprite_flags2[ju] = 9;
    v.sprite_ignore_projectile[ju] = 9;
    v.sound_effect_1.* = 12;
    return j;
}

pub export fn Blind_Decelerate_X(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_x_vel[i] != 0)
        v.sprite_x_vel[i] +%= if (sign8(v.sprite_x_vel[i])) 2 else 0 -% @as(u8, 2);
    Blind_AnimateRobes(k);
    if (v.sprite_wallcoll[i] != 0)
        Blind_FireballFlurry(k, v.sprite_wallcoll[i]);
}

pub export fn Blind_Decelerate_Y(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_y_vel[i] != 0)
        v.sprite_y_vel[i] +%= if (sign8(v.sprite_y_vel[i])) 4 else 0 -% @as(u8, 4);
    a.Sprite_MoveY(k);
    if (v.sprite_wallcoll[i] != 0)
        Blind_FireballFlurry(k, v.sprite_wallcoll[i]);
}

pub export fn Blind_CheckBumpDamage(k: c_int) callconv(.c) void {
    const i = ix(k);
    if ((v.sprite_delay_aux4[i] | v.sprite_F[i]) == 0)
        _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.link_x_coord.* -% v.cur_sprite_x.* +% 14 < 28 and
        v.link_y_coord.* -% v.cur_sprite_y.* < 28 and
        (v.countdown_for_blink.* | v.link_disable_sprite_damage.*) == 0)
    {
        v.link_auxiliary_state.* = 1;
        v.link_give_damage.* = 8;
        v.link_incapacitated_timer.* = 16;
        v.link_actual_vel_x.* ^= 255;
        v.link_actual_vel_y.* ^= 255;
    }
}

pub export fn Blind_Animate(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_wallcoll[i] == 0) {
        var t1: i32 = t.kBlind_Animate_Tab[@as(u8, @truncate(v.link_x_coord.*)) >> 5];
        if (v.sprite_D[i] == 3) t1 = -t1;
        const t0: usize = @as(usize, v.sprite_D[i] -% 2) * 8;
        const idx: usize = @as(usize, v.byte_7E0B69.* >> 3 & 7) + @as(usize, v.byte_7E0B69.* >> 2 & 1) + t0;
        v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(@as(i32, t.kBlind_HeadDir[idx]) + t1)) & 15);
    }
    Blind_AnimateRobes(k);
}

pub export fn Blind_AnimateRobes(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j: usize = @as(usize, v.sprite_subtype2[i] >> 3 & 3) + (@as(usize, v.sprite_D[i] -% 2) << 2);
    v.sprite_graphics[i] = t.kBlind_Gfx_Animate[j];
}

pub export fn Blind_SpawnLaser(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xce, &info);
    if (j >= 0) {
        const ju = ix(j);
        v.sound_effect_2.* = a.Sprite_CalculateSfxPan(k) | 0x26;
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_x_lo[ju] = @truncate(info.r0_x +% 4);
        const d: usize = v.sprite_head_dir[i];
        v.sprite_head_dir[ju] = @truncate(d);
        v.sprite_x_vel[ju] = @bitCast(t.kBlind_Laser_Xvel[d]);
        v.sprite_y_vel[ju] = @bitCast(t.kBlind_Laser_Yvel[d]);
        v.sprite_A[ju] = 128;
        v.sprite_ignore_projectile[ju] = 128;
        v.sprite_flags2[ju] = 0x40;
        v.sprite_flags4[ju] = 0x14;
    }
}

pub export fn Blind_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.sprite_graphics[i] >= 15) {
        // The poof spans are indexed by kOffs_15858, not the unrelated kOffs.
        const j: usize = v.sprite_graphics[i] - 15;
        a.Sprite_DrawMultiple(
            k,
            &t.kBlindPoof_Dmd[t.kOffs_15858[j]],
            @as(c_int, t.kOffs_15858[j + 1]) - @as(c_int, t.kOffs_15858[j]),
            null,
        );
        return;
    }
    a.Sprite_DrawMultiple(k, &t.kBlind_Dmd[@as(usize, v.sprite_graphics[i]) * 7], 7, null);
    var oam = oamPtr();
    if (v.sprite_wallcoll[i] == 0) {
        if (v.sprite_C[i] == 6) {
            oam[6].y = 0xf0;
            return;
        }
        if (v.sprite_C[i] == 4)
            return;
    }
    if (v.sprite_graphics[i] >= 10)
        return;
    oam += t.kBlind_OamIdx[v.sprite_graphics[i]];
    const d: usize = v.sprite_head_dir[i];
    oam[0].charnum = t.kBlindHead_Draw_Char[d];
    oam[0].flags = oam[0].flags & 0x3f | t.kBlindHead_Draw_Flags[d];
}

// ---------------------------------------------------------------------------
// from sprite_main_part46.zig
// ---------------------------------------------------------------------------
/// variables.zig spells the x array `moldorm_x_hi_` and has no y counterpart at
/// all (0x1fd80 is declared there as beamos_x_lo over the same bytes), so these
/// follow sprite_main.zig, which derives both from work RAM directly.

/// The `common` label, which the 0xcd case reaches with a goto.

pub export fn TrinexxComponents_Initialize(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_type[i]) {
        0xcb => {
            v.sprite_x_lo[i] +%= 8;
            v.sprite_y_lo[i] +%= 16;
            Trinexx_CachePosition(k);
            v.overlord_x_lo[2] = 0;
            v.overlord_x_lo[3] = 0;
            v.overlord_x_lo[5] = 0;
            v.overlord_x_lo[7] = 0;
            v.overlord_x_hi[0] = 0;
            v.overlord_x_lo[6] = 255;
            Trinexx_RestoreXY(k);
        },
        0xcc => {
            v.sprite_graphics[i] = 3;
            v.sprite_delay_main[i] = 128;
            trinexxInitCommon(k);
        },
        0xcd => {
            v.sprite_delay_main[i] = 255;
            trinexxInitCommon(k);
        },
        else => {},
    }
}

pub export fn Trinexx_RestoreXY(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_lo[i] = v.sprite_A[i];
    a.Sprite_SetY(k, (@as(u16, v.sprite_G[i]) << 8) +% v.sprite_C[i] +% 12);
}

pub export fn Trinexx_CachePosition(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_A[i] = v.sprite_x_lo[i];
    v.sprite_B[i] = v.sprite_x_hi[i];
    v.sprite_C[i] = v.sprite_y_lo[i];
    v.sprite_G[i] = v.sprite_y_hi[i];
}

pub export fn Sprite_Trinexx_FinalPhase(k: c_int) callconv(.c) void {
    const i = ix(k);

    const ang: usize = a.Sprite_ConvertVelocityToAngle(v.sprite_x_vel[i], v.sprite_y_vel[i]) >> 1;
    const gfx = t.kSprite_TrinexxD_Gfx3[ang];
    v.sprite_graphics[i] = if (v.sprite_delay_aux1[i] != 0) t.kSprite_TrinexxD_Gfx[gfx] else gfx;

    Sprite_TrinexxD_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (sign8(v.sprite_ai_state[i])) {
        const d = v.sprite_delay_main[i];
        v.sprite_hit_timer[i] = d | 0xe0;
        if (d == 0) {
            v.sprite_delay_main[i] = 12;
            if (v.sprite_anim_clock[i] == 0) {
                v.sprite_hit_timer[i] = 255;
                a.Sprite_ScheduleBossForDeath(k);
            } else {
                v.sprite_anim_clock[i] -%= 1;
                a.Sprite_MakeBossExplosion(k);
            }
        }
        return;
    }
    if (v.frame_counter.* & 7 == 0)
        a.SpriteSfx_QueueSfx3WithPan(k, 0x31);

    v.sprite_subtype2[i] +%= 1;
    const h: usize = v.sprite_subtype2[i] & 0x7f;
    v.moldorm_x_lo[h] = v.sprite_x_lo[i];
    v.moldorm_y_lo[h] = v.sprite_y_lo[i];
    moldorm_x_hi[h] = v.sprite_x_hi[i];
    moldorm_y_hi[h] = v.sprite_y_hi[i];

    if (v.sprite_F[i] == 14) {
        v.sprite_F[i] = 8;
        if (v.sprite_ai_state[i] == 0)
            v.sprite_ai_state[i] = 2;
    }
    a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_A[i] -%= 1;
            if (v.sprite_A[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 192;
            }
            a.Sprite_Get16BitCoords(k);
            if (a.Sprite_CheckTileCollision(k) != 0) {
                v.sprite_D[i] = v.sprite_D[i] +% 1 & 3;
                v.sprite_delay_aux1[i] = 8;
            }
            const d: usize = v.sprite_D[i];
            v.sprite_x_vel[i] = @bitCast(t.kSprite_TrinexxD_Xvel[d]);
            v.sprite_y_vel[i] = @bitCast(t.kSprite_TrinexxD_Yvel[d]);
        },
        1 => {
            if (v.frame_counter.* & 1 == 0) {
                const pt = a.Sprite_ProjectSpeedTowardsLink(k, 31);
                a.Sprite_ApproachTargetSpeed(k, pt.x, pt.y);
            }
        },
        else => {},
    }
}

pub export fn Sprite_TrinexxD_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_obj_prio[i] |= 0x30;
    var info: PrepOamCoordsRet = undefined;
    a.SpriteDraw_TrinexxRockHead(k, &info);
    var n: usize = 0;
    while (n != v.sprite_anim_clock[i]) : (n += 1) {
        const h: usize = (v.sprite_subtype2[i] -% @as(u8, @bitCast(t.kTrinexxD_HistPos[n]))) & 0x7f;
        v.cur_sprite_x.* = (@as(u16, moldorm_x_hi[h]) << 8) | v.moldorm_x_lo[h];
        v.cur_sprite_y.* = (@as(u16, moldorm_y_hi[h]) << 8) | v.moldorm_y_lo[h];

        if (v.link_x_coord.* -% v.cur_sprite_x.* +% 8 < 16 and
            v.link_y_coord.* -% v.cur_sprite_y.* +% 16 < 16 and
            !sign8(v.sprite_ai_state[i]) and
            (v.countdown_for_blink.* | v.link_disable_sprite_damage.* | v.submodule_index.* | v.flag_unk1.*) == 0)
        {
            v.link_auxiliary_state.* = 1;
            v.link_give_damage.* = 8;
            v.link_incapacitated_timer.* = 16;
            v.link_actual_vel_x.* ^= 255;
            v.link_actual_vel_y.* ^= 255;
        }
        v.oam_cur_ptr.* +%= @bitCast(t.kTrinexxD_OamOffs[n]);
        v.oam_ext_cur_ptr.* +%= @bitCast(t.kTrinexxD_OamOffs[n] >> 2);
        v.sprite_oam_flags[i] = 1;
        if (n == 4 and v.sprite_ai_state[i] != 0) {
            Sprite_Trinexx_CheckDamageToFlashingSegment(k);
            v.sprite_oam_flags[i] = (v.sprite_subtype2[i] & 6) ^ v.sprite_oam_flags[i];
        }
        v.sprite_graphics[i] = @bitCast(t.kSprite_TrinexxD_Gfx2[n]);
        if (v.sprite_graphics[i] != 3) {
            a.SpriteDraw_SingleLarge(k);
        } else {
            v.sprite_graphics[i] = 8;
            a.SpriteDraw_TrinexxRockHead(k, &info);
        }
    }
    v.byte_7E0FB6.* = v.sprite_anim_clock[i];
}

pub export fn Sprite_Trinexx_CheckDamageToFlashingSegment(k: c_int) callconv(.c) void {
    const i = ix(k);
    const old_x = a.Sprite_GetX(k);
    const old_y = a.Sprite_GetY(k);
    a.Sprite_SetX(k, v.cur_sprite_x.*);
    a.Sprite_SetY(k, v.cur_sprite_y.*);
    v.sprite_defl_bits[i] = 0x80;
    v.sprite_flags3[i] = 0;
    _ = a.Sprite_CheckDamageFromLink(k);
    v.sprite_defl_bits[i] = 0x84;
    v.sprite_flags3[i] = 0x40;
    a.Sprite_SetX(k, old_x);
    a.Sprite_SetY(k, old_y);
}

pub export fn Trinexx_WagTail(k: c_int) callconv(.c) void {
    _ = k;
    if (v.overlord_x_lo[5] == 0) {
        v.overlord_x_lo[4] +%= 1;
        if (v.overlord_x_lo[4] & 3 == 0) {
            const j: u8 = v.overlord_x_lo[3] & 1;
            v.overlord_x_lo[2] +%= if (j != 0) 0 -% @as(u8, 1) else 1;
            if (v.overlord_x_lo[2] == (if (j != 0) @as(u8, 0) else 6)) {
                v.overlord_x_lo[3] +%= 1;
                v.overlord_x_lo[5] = 8;
            }
        }
    } else {
        v.overlord_x_lo[5] -%= 1;
    }
}

pub export fn Trinexx_HandleShellCollision(k: c_int) callconv(.c) void {
    const i = ix(k);
    const x: u16 = v.sprite_A[i] | (@as(u16, v.sprite_B[i]) << 8);
    const y: u16 = v.sprite_C[i] | (@as(u16, v.sprite_G[i]) << 8);
    if (x -% v.link_x_coord.* +% 40 < 80 and y -% v.link_y_coord.* +% 16 < 64 and
        (v.countdown_for_blink.* | v.link_disable_sprite_damage.*) == 0)
    {
        v.link_auxiliary_state.* = 1;
        v.link_give_damage.* = 8;
        v.link_incapacitated_timer.* = 16;
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 32);
        v.link_actual_vel_x.* = pt.x;
        v.link_actual_vel_y.* = pt.y;
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part47.zig
// ---------------------------------------------------------------------------
pub export fn SpriteDraw_TrinexxRockHead(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    if (!sign8(v.sprite_ai_state[i]))
        v.sprite_obj_prio[i] |= 0x30;
    a.Sprite_DrawMultiple(k, &t.kTrinexx_Draw1_Dmd[@as(usize, v.sprite_graphics[i]) * 4], 4, info);
}

pub export fn Sprite_CB_TrinexxRockHead(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.overlord_x_hi[0] != 0) {
        a.Sprite_Trinexx_FinalPhase(k);
        return;
    }
    v.TM_copy.* = 0x17;
    v.TS_copy.* = 0;
    a.SpriteDraw_TrinexxRockHeadAndBody(k);
    if (a.Sprite_ReturnIfInactive(k)) return;

    if (sign8(v.sprite_ai_state[i])) {
        v.flag_block_link_menu.* = v.sprite_ai_state[i];
        if (v.sprite_delay_main[i] == 0) {
            v.overlord_x_hi[0] +%= 1;
            a.Sprite_InitializedSegmented(k);
            v.sprite_subtype2[i] = 0;
            v.sprite_head_dir[i] = 0;
            v.sprite_flags3[i] &= ~@as(u8, 0x40);
            v.sprite_defl_bits[i] = 0x80;
            v.sprite_ai_state[i] = 0;
            v.sprite_D[i] = 0;
            v.sprite_A[i] = 0;
            v.sprite_anim_clock[i] = 16;
            v.sprite_x_vel[i] = 0;
            v.sprite_y_vel[i] = 0;
            v.sprite_A[i] = 128;
            // HIBYTE(dung_floor_y_vel) = 255
            v.dung_floor_y_vel.* = (v.dung_floor_y_vel.* & 0x00ff) | 0xff00;
        } else if (v.sprite_delay_main[i] >= 0xff) {
            // The C leaves this branch empty.
        } else if (v.sprite_delay_main[i] >= 0xe0) {
            if (v.sprite_delay_main[i] & 3 == 0) {
                v.dung_floor_y_vel.* = 0xffff;
                v.dung_hdr_collision_2_mirror.* = 1;
            }
            v.sprite_y_vel[i] = cm.byte(-8);
            a.Sprite_MoveY(k);
            a.Trinexx_CachePosition(k);
            v.sprite_C[i] = v.sprite_y_lo[i] -% 12;
            v.overlord_x_lo[7] +%= 2;
        } else {
            if (v.sprite_delay_main[i] & 3 == 0)
                a.SpriteSfx_QueueSfx2WithPan(k, 0xc);
            if (v.sprite_delay_main[i] & 1 == 0) {
                v.cur_sprite_x.* = a.Sprite_GetX(k) +% s16(t.kTrinexx_X0[a.GetRandomNumber() & 7]);
                v.cur_sprite_y.* = a.Sprite_GetY(k) +% s16(t.kTrinexx_Y0[a.GetRandomNumber() & 7]) -% 8;
                a.Sprite_MakeBossDeathExplosion_NoSound(k);
            }
            v.sprite_head_dir[i] = 255;
        }
        return;
    }

    if ((v.sprite_state[1] | v.sprite_state[2]) == 0 and v.sprite_ai_state[i] < 2) {
        v.sprite_delay_main[i] = 255;
        v.sprite_ai_state[i] = 255;
        v.sound_effect_2.* = 0x22;
        return;
    }

    a.Trinexx_WagTail(k);
    a.Trinexx_HandleShellCollision(k);
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.frame_counter.* & 63 == 0) {
        const pair = a.Sprite_IsRightOfLink(k);
        v.sprite_graphics[i] = if (pair.b +% 24 < 48) 0 else if (pair.a != 0) @as(u8, 1) else 7;
    }
    if (v.overlord_x_lo[6] != 0) {
        if (v.frame_counter.* & 1 == 0)
            v.overlord_x_lo[6] -%= 1;
        return;
    }
    if (v.sprite_state[1] != 0 and v.sprite_ai_state[1] == 3) return;
    if (v.sprite_state[2] != 0 and v.sprite_ai_state[2] == 3) return;

    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_delay_main[i] == 0) {
                const j: usize = a.GetRandomNumber() & 3;
                if (v.sprite_subtype[i] & 0x7f == j)
                    return;
                v.sprite_anim_clock[i] +%= 1;
                if (v.sprite_anim_clock[i] == 2) {
                    v.sprite_anim_clock[i] = 0;
                    v.sprite_ai_state[i] = 2;
                    v.sprite_delay_main[i] = 80;
                    return;
                }
                v.overlord_x_lo[0] = t.kTrinexx_Tab0[j];
                v.overlord_x_lo[1] = t.kTrinexx_Tab1[j];
                v.sprite_subtype[i] = @as(u8, @truncate(j)) +%
                    (@as(u8, @intFromBool(a.GetRandomNumber() & 3 == 0)) *% 0x80);
                v.sprite_ai_state[i] = 1;
            }
        },
        1 => {
            if (v.sprite_subtype[i] == 0xff and
                (v.sprite_delay_main[i] == 0 or a.Sprite_IsBelowLink(k).a == 0))
            {
                v.sprite_subtype[i] = 0;
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 48;
            } else {
                const x: u16 = (@as(u16, v.sprite_x_hi[i]) << 8) | v.overlord_x_lo[0];
                const y: u16 = (@as(u16, v.sprite_y_hi[i]) << 8) | v.overlord_x_lo[1];
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, if (sign8(v.sprite_subtype[i])) 16 else 8);
                v.sprite_x_vel[i] = pt.x;
                v.sprite_y_vel[i] = pt.y;

                const bakx = v.sprite_x_lo[i];
                const baky = v.sprite_y_lo[i];
                a.Sprite_MoveXY(k);
                v.dung_floor_y_vel.* = s16(@bitCast(baky -% v.sprite_y_lo[i]));
                v.dung_floor_x_vel.* = s16(@bitCast(bakx -% v.sprite_x_lo[i]));

                v.dung_hdr_collision_2_mirror.* = 1;
                a.Trinexx_CachePosition(k);
                v.sprite_C[i] = v.sprite_y_lo[i] -% 12;
                if (v.overlord_x_lo[0] -% v.sprite_x_lo[i] +% 2 < 4 and
                    v.overlord_x_lo[1] -% v.sprite_y_lo[i] +% 2 < 4)
                {
                    v.sprite_ai_state[i] = 0;
                    v.sprite_delay_main[i] = 48;
                }
            }
            var n: u8 = if (sign8(v.sprite_subtype[i])) 2 else 1;
            while (true) {
                v.sprite_subtype2[i] +%= if (sign8(v.sprite_x_vel[i])) 1 else 0 -% @as(u8, 1);
                if (v.sprite_subtype2[i] & 0xf == 0)
                    a.SpriteSfx_QueueSfx2WithPan(k, 0x21);
                n -= 1;
                if (n == 0) break;
            }
        },
        2 => {
            a.Trinexx_WagTail(k);
            a.Trinexx_WagTail(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 3;
                a.Sprite_ApplySpeedTowardsLink(k, 48);
                v.sprite_delay_main[i] = 64;
                v.sound_effect_2.* = 0x26;
            }
        },
        3 => {
            a.Sprite_MoveXY(k);
            if (v.sprite_delay_main[i] == 0) {
                a.Trinexx_RestoreXY(k);
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 48;
            } else if (v.sprite_delay_main[i] == 0x20) {
                v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
                v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part48.zig
// ---------------------------------------------------------------------------
// TrinexxMult is `static` in the C, so it is absent from the ABI header and
// has to come from the module that ported it.

pub export fn SpriteDraw_TrinexxRockHeadAndBody(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (sign8(v.sprite_head_dir[i])) return;

    var info: PrepOamCoordsRet = undefined;
    a.SpriteDraw_TrinexxRockHead(k, &info);

    info.flags &= ~@as(u8, 0x10);

    if (v.sprite_ai_state[i] == 3) {
        var oam = oamPtr() + 4;
        const dx: u8 = v.sprite_A[i] -% v.sprite_x_lo[i];
        const dy: u8 = v.sprite_C[i] -% v.sprite_y_lo[i];
        var n: c_int = 7;
        while (n >= 0) : ({
            n -= 1;
            oam += 1;
        }) {
            const idx = ix(n);
            setOamPlain(
                oam,
                @truncate(info.x +% TrinexxMult(dx, t.kTrinexx_Mults[idx])),
                @truncate(info.y +% TrinexxMult(dy, t.kTrinexx_Mults[idx])),
                0x28,
                info.flags,
                2,
            );
        }
        v.byte_7E0FB6.* = 0x30;
    }

    v.oam_cur_ptr.* = 0x9f0;
    v.oam_ext_cur_ptr.* = 0xa9c;
    var oam = oamPtr();
    const xb: u8 = v.sprite_A[i] -% @as(u8, @truncate(v.BG2HOFS_copy2.*));
    const yb: u16 = ((@as(u16, v.sprite_y_hi[i]) << 8) | v.sprite_C[i]) -% v.BG2VOFS_copy2.*;

    const xidx: usize = if (v.sprite_x_vel[i] +% 3 < 7) 0 else v.sprite_subtype2[i] >> 2;
    const yidx: usize = v.sprite_subtype2[i] >> 2;

    var n: c_int = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 2;
    }) {
        const hi = n != 0;
        const x: u8 = xb +% (if (hi) 0 -% @as(u8, 28) else 28) +%
            @as(u8, @bitCast(t.kTrinexx_Draw_Xoffs[(xidx + @as(usize, if (hi) 0 else 8)) & 0xf]));
        const y: u8 = @as(u8, @truncate(yb)) -% 8 +%
            @as(u8, @bitCast(t.kTrinexx_Draw_Yoffs[(yidx + @as(usize, if (hi) 8 else 0)) & 0xf]));
        const f: u8 = info.flags | (if (hi) @as(u8, 0) else 0x40);
        setOamPlain(oam + 0, x, y, 0xc, f, 2);
        setOamPlain(oam + 1, x, y +% 16, 0x2a, f, 2);
    }

    var neck = v.oam_buf + 91;
    const g: usize = v.overlord_x_lo[2];
    // WORD(overlord_x_lo[7]) reads one byte past the array, into overlord_x_hi.
    const tail: u16 = @as(u16, v.overlord_x_lo[7]) | (@as(u16, v.overlord_x_hi[0]) << 8);
    var m: usize = 0;
    while (m < 5) : ({
        m += 1;
        neck += 1;
    }) {
        const j = g * 5 + m;
        setOam(
            neck,
            @as(u16, xb) +% s16(t.kTrinexx_Draw_X[j]),
            yb -% s16(t.kTrinexx_Draw_Y[j]) -% 0x20 +% tail,
            t.kTrinexx_Draw_Char[m],
            info.flags,
            2,
        );
    }
    v.tmp_counter.* = 0xff;

    if (v.submodule_index.* != 0)
        a.Sprite_CorrectOamEntries(k, 3, 2);
}

// ---------------------------------------------------------------------------
// from sprite_main_part49.zig
// ---------------------------------------------------------------------------
// TrinexxHeadSin is `static` in the C, so it is absent from the ABI header and
// has to come from the module that ported it.

pub export fn Sidenexx_ExhaleDanger(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: SpriteSpawnInfo = undefined;
    if (v.sprite_type[i] == 0xcd) {
        var n: usize = 0;
        while (n < 2) : (n += 1) {
            const j = a.Sprite_SpawnDynamically(k, 0xcd, &info);
            if (j >= 0) {
                const ju = ix(j);
                a.Sprite_SetSpawnedCoordinates(j, &info);
                v.sprite_C[ju] = if (n != 0) 1 else cm.byte(-2);
                a.SpriteSfx_QueueSfx3WithPan(k, 0x19);
                v.sprite_E[ju] = 1;
                v.sprite_ignore_projectile[ju] = 1;
                v.sprite_y_vel[ju] = 24;
                v.sprite_flags2[ju] = 0;
                v.sprite_flags3[ju] = 0x40;
            }
        }
        v.byte_7E0FB6.* = 1;
    } else {
        const j = a.Sprite_SpawnDynamically(k, v.sprite_type[i], &info);
        if (j >= 0) {
            const ju = ix(j);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            a.SpriteSfx_QueueSfx2WithPan(k, 0x2a);
            v.sprite_E[ju] = 1;
            v.sprite_ignore_projectile[ju] = 1;
            v.sprite_y_vel[ju] = 24;
            v.sprite_flags2[ju] = 0;
            v.sprite_flags3[ju] = 0x40;
        }
    }
}

pub export fn Sidenexx_Explode(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_main[i] == 0) {
        v.sprite_delay_main[i] = 12;
        if (v.sprite_subtype2[i] == 1)
            v.sprite_state[i] = 0;
        v.sprite_subtype2[i] -%= 1;
        // BYTE(cur_sprite_x) += BG2HOFS_copy2, low byte only.
        const nx: u8 = @as(u8, @truncate(v.cur_sprite_x.*)) +% @as(u8, @truncate(v.BG2HOFS_copy2.*));
        v.cur_sprite_x.* = (v.cur_sprite_x.* & 0xff00) | nx;
        const ny: u8 = @as(u8, @truncate(v.cur_sprite_y.*)) +% @as(u8, @truncate(v.BG2VOFS_copy2.*));
        v.cur_sprite_y.* = (v.cur_sprite_y.* & 0xff00) | ny;
        a.Sprite_MakeBossExplosion(k);
    }
}

pub export fn TrinexxHead_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_lo[i] = v.sprite_A[i];
    v.sprite_x_hi[i] = v.sprite_B[i];
    v.sprite_y_lo[i] = v.sprite_C[i];
    v.sprite_y_hi[i] = v.sprite_G[i];
    a.Sprite_Get16BitCoords(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var oam = oamPtr();
    var n: usize = 0;
    while (true) {
        const j = n + i * 9;

        const r6: u16 = if (k != 2)
            0x100 +% @as(u16, 0 -% v.alt_sprite_type[j])
        else
            v.alt_sprite_type[j];
        const r15: u8 = v.alt_sprite_y_hi[j];

        const xoff: u8 = @bitCast(TrinexxHeadSin(r6, r15));
        const yoff: u8 = @bitCast(TrinexxHeadSin(r6 +% 0x80, r15));
        v.dungmap_var7.* = (@as(u16, yoff) << 8) | xoff;

        if (n == 0) {
            var m: usize = 0;
            while (m < 5) : (m += 1) {
                const cx: u8 = @as(u8, @truncate(info.x)) +% xoff;
                v.cur_sprite_x.* = (v.cur_sprite_x.* & 0xff00) | cx;
                const x: u8 = cx +% @as(u8, @bitCast(t.kTrinexxHead_FirstPart_X[m]));

                const cy: u8 = @as(u8, @truncate(info.y)) +% yoff;
                v.cur_sprite_y.* = (v.cur_sprite_y.* & 0xff00) | cy;
                const y: u8 = cy +% @as(u8, @bitCast(t.kTrinexxHead_FirstPart_Y[m])) +%
                    (if (m == 4) v.sprite_subtype[i] else 0);

                setOamPlain(
                    oam,
                    x,
                    y,
                    t.kTrinexxHead_FirstPart_Char[m],
                    info.flags | t.kTrinexxHead_FirstPart_Flags[m],
                    2,
                );
                oam += 1;
            }
            a.Sprite_SetX(k, ((@as(u16, v.sprite_B[i]) << 8) | v.sprite_A[i]) +% s16(@bitCast(xoff)));
            a.Sprite_SetY(k, ((@as(u16, v.sprite_G[i]) << 8) | v.sprite_C[i]) +% s16(@bitCast(yoff)));
        } else {
            const x: u8 = @as(u8, @truncate(info.x)) +% xoff;
            const y: u8 = @as(u8, @truncate(info.y)) +% yoff;
            v.cur_sprite_x.* = (v.cur_sprite_x.* & 0xff00) | x;
            v.cur_sprite_y.* = (v.cur_sprite_y.* & 0xff00) | y;
            setOamPlain(oam, x, y, 8, info.flags, 2);
            oam += 1;
        }
        n += 1;
        if (n == v.sprite_subtype2[i]) break;
    }
    v.tmp_counter.* = @truncate(n);
    v.byte_7E0FB6.* = @truncate(n * 4 + 16);
    if (v.submodule_index.* != 0)
        a.Sprite_CorrectOamEntries(k, 4, 2);
}

pub export fn Sprite_CC_CD_Common(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.frame_counter.* & 3 == 0) {
        const step: u8 = if (a.Sprite_IsRightOfLink(k).a != 0) 0 -% @as(u8, 1) else 1;
        if (v.sprite_x_vel[i] != step *% 16)
            v.sprite_x_vel[i] +%= step;
    }
    if (a.Sprite_CheckTileCollision(k) != 0)
        v.sprite_state[i] = 0;
}

pub export fn Sprite_CD_SpawnGarnish(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_subtype2[i] & 7 != 0)
        return;
    a.SpriteSfx_QueueSfx3WithPan(k, 0x14);
    const j = a.GarnishAllocOverwriteOld();
    const ju = ix(j);
    v.garnish_type[ju] = 0xc;
    v.garnish_active.* = 0xc;
    v.garnish_sprite[ju] = @truncate(@as(u32, @bitCast(k)));
    a.Garnish_SetX(j, a.Sprite_GetX(k));
    a.Garnish_SetY(j, a.Sprite_GetY(k) +% 16);
    v.garnish_countdown[ju] = 127;
}

// ---------------------------------------------------------------------------
// from sprite_main_part50.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_Sidenexx(k: c_int) callconv(.c) void {
    const i = ix(k);

    const xx: u16 = ((@as(u16, v.sprite_B[0]) << 8) | v.sprite_A[0]) +%
        s16(t.kTrinexxHead_Xoffs[v.sprite_type[i] - 0xcc]);
    v.sprite_A[i] = @truncate(xx);
    v.sprite_B[i] = @truncate(xx >> 8);

    const yy: u16 = ((@as(u16, v.sprite_G[0]) << 8) | v.sprite_C[0]) -% 0x20;
    v.sprite_C[i] = @truncate(yy);
    v.sprite_G[i] = @truncate(yy >> 8);

    v.sprite_obj_prio[i] |= 0x30;
    a.TrinexxHead_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (sign8(v.sprite_ai_state[i])) {
        v.sprite_ignore_projectile[i] = v.sprite_ai_state[i];
        a.Sidenexx_Explode(k);
        return;
    }

    if (v.sprite_hit_timer[i] != 0 and v.sprite_ai_state[i] != 4) {
        v.sprite_hit_timer[i] = 0;
        v.sprite_delay_main[i] = 128;
        v.sprite_ai_state[i] = 4;
        v.sprite_z_vel[i] = v.sprite_oam_flags[i];
        v.sprite_oam_flags[i] = 3;
    }
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_defl_bits[i] |= 4;

    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_flags3[i] |= 0x40;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_subtype2[i] = 9;
                v.sprite_flags3[i] &= ~@as(u8, 0x40);
            }
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                const r: u8 = (a.GetRandomNumber() & 7) + 1;
                const prev = v.sprite_D[i];
                if (r < 5 and v.sprite_D[i] != r) {
                    v.sprite_D[i] = r;
                    v.sprite_ai_state[i] = 2;
                    if (prev == 1 and a.GetRandomNumber() & 1 == 0 and v.sprite_ai_state[0] < 2) {
                        v.sprite_graphics[i] = 0;
                        v.sprite_ai_state[i] = 3;
                        v.sprite_delay_main[i] = 127;
                    }
                }
            }
        },
        2 => {
            var j: usize = @as(usize, v.sprite_D[i]) * 9;
            var f: usize = i * 9;
            var n: u32 = 0;
            var c: c_int = 8;
            while (c >= 0) : ({
                c -= 1;
                j += 1;
                f += 1;
            }) {
                // Upstream steps the x component twice per iteration: the C
                // repeats this block verbatim before the y component.
                if (v.alt_sprite_type[f] != t.kTrinexxHead_Target0[j]) {
                    v.alt_sprite_type[f] +%= if (sign8(v.alt_sprite_type[f] -% t.kTrinexxHead_Target0[j])) 1 else 0 -% @as(u8, 1);
                    n += 1;
                }
                if (v.alt_sprite_type[f] != t.kTrinexxHead_Target0[j]) {
                    v.alt_sprite_type[f] +%= if (sign8(v.alt_sprite_type[f] -% t.kTrinexxHead_Target0[j])) 1 else 0 -% @as(u8, 1);
                    n += 1;
                }
                if (v.alt_sprite_y_hi[f] != t.kTrinexxHead_Target1[j]) {
                    v.alt_sprite_y_hi[f] +%= if (sign8(v.alt_sprite_y_hi[f] -% t.kTrinexxHead_Target1[j])) 1 else 0 -% @as(u8, 1);
                    n += 1;
                }
            }
            if (n == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = a.GetRandomNumber() & 15;
            }
        },
        3 => {
            const d = v.sprite_delay_main[i];
            if (d == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 32;
                return;
            }
            if (d == 64)
                a.Sidenexx_ExhaleDanger(k);
            v.sprite_subtype[i] = if (d < 8)
                d
            else if (d < 121)
                8
            else
                ~(v.sprite_delay_main[i] +% 0x80);
            if (d >= 64 and v.frame_counter.* & t.kTrinexxHead_FrameMask[(d - 64) >> 3] == 0) {
                const gx: i16 = @as(i16, a.GetRandomNumber() & 0xf) - 3;
                const gy: i16 = @as(i16, a.GetRandomNumber() & 0xf) + 12;
                const g = a.Sprite_GarnishSpawn_Sparkle(k, @bitCast(gx), @bitCast(gy));
                if (v.sprite_type[i] == 0xcc)
                    v.garnish_type[ix(g)] = 0xe;
            }
        },
        4 => {
            v.sprite_defl_bits[i] &= ~@as(u8, 4);
            v.sprite_subtype[i] = 0;
            const d = v.sprite_delay_main[i];
            if (d == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 32;
                v.sprite_oam_flags[i] = v.sprite_z_vel[i];
                v.sprite_hit_timer[i] = 0;
            }
            if (d >= 15) {
                if (d >= 63 and d < 78) {
                    if (v.sprite_type[i] == 0xcd)
                        a.Trinexx_FlashShellPalette_Blue()
                    else
                        a.Trinexx_FlashShellPalette_Red();
                }
            } else {
                if (v.sprite_type[i] == 0xcd)
                    a.Trinexx_UnflashShellPalette_Blue()
                else
                    a.Trinexx_UnflashShellPalette_Red();
            }
        },
        else => {},
    }
}

pub export fn Sprite_TrinexxFire_AddFireGarnish(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_subtype2[i] +%= 1;
    if (v.sprite_subtype2[i] & 7 != 0)
        return;
    a.SpriteSfx_QueueSfx2WithPan(k, 0x2a);
    _ = Garnish_FlameTrail(k, false);
}

pub export fn Garnish_FlameTrail(k: c_int, is_low: bool) callconv(.c) c_int {
    const j = if (is_low) a.GarnishAllocOverwriteOldLow() else a.GarnishAllocOverwriteOld();
    const ju = ix(j);
    v.garnish_type[ju] = 0x10;
    v.garnish_active.* = 0x10;
    v.garnish_sprite[ju] = @truncate(@as(u32, @bitCast(k)));
    a.Garnish_SetX(j, a.Sprite_GetX(k));
    a.Garnish_SetY(j, a.Sprite_GetY(k) +% 16);
    v.garnish_countdown[ju] = 127;
    return j;
}

// ---------------------------------------------------------------------------
// from sprite_main_part51.zig
// ---------------------------------------------------------------------------
/// The C widens link_hearts_filler to 16 bits for this add, so the carry runs
/// on into link_magic_filler at 0xf373.

pub export fn Sprite_C9_Tektite(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j = v.sprite_anim_clock[i];
    if (j != 0) {
        v.sprite_ignore_projectile[i] = j;
        v.sprite_obj_prio[i] = 0x30;
    }
    switch (j) {
        0 => Sprite_Tektite(k),
        1 => a.Sprite_PhantomGanon(k),
        2 => a.Sprite_GanonTrident(k),
        3 => a.Sprite_SpiralFireBat(k),
        4 => a.Sprite_FireBat_Launched(k),
        5 => a.Sprite_FireBat_Trailer(k),
        else => {},
    }
}

/// The `reset_state` label, which case 2 reaches with a goto into case 1.

pub export fn Sprite_Tektite(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_aux1[i] != 0)
        v.sprite_graphics[i] = 0;
    Tektite_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXYZ(k);
    _ = a.Sprite_BounceFromTileCollision(k);
    v.sprite_z_vel[i] -%= 1;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = 0;
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // Stationary
            var pt: PointU8 = undefined;
            var j: usize = a.Sprite_DirectionToFaceLink(k, &pt);
            if (pt.x +% 40 < 80 and pt.y +% 40 < 80 and v.player_oam_y_offset.* != 0x80 and
                (v.sprite_z[i] | v.sprite_pause[i]) == 0 and
                v.link_is_on_lower_level.* == v.sprite_floor[i] and
                j != t.kTektite_Dir[v.link_direction_facing.* >> 1])
            {
                const sp = a.Sprite_ProjectSpeedTowardsLink(k, 32);
                v.sprite_x_vel[i] = 0 -% sp.x;
                v.sprite_y_vel[i] = 0 -% sp.y;
                v.sprite_z_vel[i] = 16;
                v.sprite_ai_state[i] = 1;
                return;
            }
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_B[i] +%= 1;
                if (v.sprite_B[i] == 4) {
                    v.sprite_B[i] = 0;
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 48;
                    v.sprite_z_vel[i] = 12;
                    j = @as(usize, a.Sprite_IsBelowLink(k).a) * 2 + a.Sprite_IsRightOfLink(k).a;
                } else {
                    v.sprite_z_vel[i] = (a.GetRandomNumber() & 7) +% 24;
                    j = a.GetRandomNumber() & 3;
                }
                v.sprite_x_vel[i] = @bitCast(t.kTektite_Xvel[j]);
                v.sprite_y_vel[i] = @bitCast(t.kTektite_Yvel[j]);
            } else {
                v.sprite_graphics[i] = v.sprite_delay_main[i] >> 4 & 1;
            }
        },
        1 => { // Aloft
            if (v.sprite_z[i] == 0) {
                tektiteResetState(k);
            } else {
                v.sprite_graphics[i] = 2;
            }
        },
        2 => { // RepeatingHop
            if (v.sprite_delay_main[i] == 0) {
                tektiteResetState(k);
                return;
            }
            if (v.sprite_z[i] == 0) {
                v.sprite_z_vel[i] = 12;
                v.sprite_z[i] +%= 1;
                v.sprite_delay_aux1[i] = 8;
            }
            v.sprite_graphics[i] = 2;
        },
        else => {},
    }
}

pub export fn Tektite_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kTektite_Dmd[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_C8_BigFairy(k: c_int) callconv(.c) void {
    if (v.sprite_head_dir[ix(k)] != 0)
        Sprite_FairyCloud(k)
    else
        Sprite_BigFairy(k);
}

pub export fn Sprite_FairyCloud(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_subtype2[i] +%= 1;
    FaerieCloud_Draw(k);
    if (v.sprite_subtype2[i] & 31 == 0)
        a.SpriteSfx_QueueSfx2WithPan(k, 0x31);
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_A[i] = 0;
            a.Sprite_ApplySpeedTowardsLink(k, 8);
            a.Sprite_MoveXY(k);
            a.Sprite_Get16BitCoords(k);
            if (v.link_x_coord.* -% v.cur_sprite_x.* +% 3 < 6 and
                v.link_y_coord.* -% v.cur_sprite_y.* +% 11 < 6)
            {
                link_hearts_filler16.* +%= 0xa0;
                v.sprite_ai_state[i] = 1;
            }
        },
        1 => {
            if (v.link_health_current.* == v.link_health_capacity.*) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_aux2[0] = 112; // zelda bug
            }
        },
        2 => {
            if (v.sprite_subtype2[i] & 15 != 0 or sign8(v.sprite_A[i]))
                return;
            v.sprite_A[i] = v.sprite_A[i] *% 2 +% 1;
            if (v.sprite_A[i] >= 0x80) {
                v.sprite_A[i] = 255;
                v.flag_is_link_immobilized.* = 0;
                v.sprite_state[i] = 0;
            }
        },
        else => {},
    }
}

pub export fn Sprite_BigFairy(k: c_int) callconv(.c) void {
    const i = ix(k);
    var pt: PointU8 = undefined;
    // The C decrements only its local copy of the timer here.
    var d = v.sprite_delay_aux2[i];
    if (d != 0 and d < 0x40) {
        d -%= 1;
        if (d == 0)
            v.sprite_state[i] = 0;
        if (d & 1 != 0)
            return;
    }
    BigFaerie_Draw(k);
    v.sprite_G[i] -%= 1;
    if (sign8(v.sprite_G[i])) {
        v.sprite_G[i] = 5;
        v.sprite_graphics[i] = v.sprite_graphics[i] +% 1 & 3;
    }
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_subtype2[i] +%= 1;
    switch (v.sprite_ai_state[i]) {
        0 => { // await close player
            FaerieCloud_Draw(k);
            v.sprite_A[i] = 1;
            _ = a.Sprite_DirectionToFaceLink(k, &pt);
            if (pt.x +% 0x30 < 0x60 and pt.y +% 0x30 < 0x60) {
                a.Link_CancelDash();
                v.sprite_ai_state[i] = 1;
                v.dialogue_message_index.* = 0x15a;
                a.Sprite_ShowMessageMinimal();
                v.flag_is_link_immobilized.* = 1;
                var info: SpriteSpawnInfo = undefined;
                const j = a.Sprite_SpawnDynamically(k, 0xc8, &info);
                const ju = ix(j);
                a.Sprite_SetSpawnedCoordinates(j, &info);
                v.sprite_head_dir[ju] = 1;
                v.sprite_y_lo[ju] -%= v.sprite_z[i];
                v.sprite_z[ju] = 0;
            }
        },
        1 => {}, // dormant
        else => {},
    }
}

pub export fn BigFaerie_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kBigFaerie_Dmd[@as(usize, v.sprite_graphics[i]) * 4], 4, &info);
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn FaerieCloud_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (!sign8(v.sprite_A[i]) and (v.sprite_A[i] & v.sprite_subtype2[i]) == 0) {
        const x = s16(t.kFaerieCloud_Draw_XY[a.GetRandomNumber() & 7]);
        const y = s16(t.kFaerieCloud_Draw_XY[a.GetRandomNumber() & 7]);
        _ = a.Sprite_GarnishSpawn_Sparkle(k, x, y);
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part52.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_C7_Pokey(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_C[i] != 0) {
        a.SpriteDraw_SingleLarge(k);
        if (a.Sprite_ReturnIfInactive(k)) return;
        _ = a.Sprite_CheckDamageToAndFromLink(k);
        a.Sprite_MoveXYZ(k);
        v.sprite_z_vel[i] -%= 2;
        if (sign8(v.sprite_z[i])) {
            v.sprite_z_vel[i] = 16;
            v.sprite_z[i] = 0;
        }
        if (a.Sprite_BounceFromTileCollision(k) != 0)
            a.SpriteSfx_QueueSfx2WithPan(k, 0x21);
        if (v.sprite_G[i] >= 3) {
            v.sprite_state[i] = 6;
            v.sprite_delay_main[i] = 10;
            v.sprite_flags5[i] = 0;
            a.SpriteSfx_QueueSfx2WithPan(k, 0x1e);
        }
        return;
    }

    a.Hokbok_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_A[i] != 0 and v.sprite_F[i] == 15) {
        v.sprite_F[i] = 6;
        v.sprite_z[i] +%= v.sprite_B[i];
        v.sprite_A[i] -%= 1;
        if (v.sprite_A[i] == 0)
            v.sprite_health[i] = 17;
        v.sprite_x_vel[i] +%= if (sign8(v.sprite_x_vel[i])) 0 -% @as(u8, 4) else 4;
        v.sprite_y_vel[i] +%= if (sign8(v.sprite_y_vel[i])) 0 -% @as(u8, 4) else 4;

        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0xc7, &info);
        if (j >= 0) {
            const ju = ix(j);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_C[ju] = 1;
            v.sprite_health[ju] = 1;
            v.sprite_x_vel[ju] = v.sprite_x_recoil[i];
            v.sprite_y_vel[ju] = v.sprite_y_recoil[i];
            v.sprite_defl_bits[ju] = 64;
        }
    }
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_z_vel[i] = 16;
            } else {
                v.sprite_B[i] = t.kHokbok_B[v.sprite_delay_main[i] >> 1];
            }
        },
        1 => {
            a.Sprite_MoveXYZ(k);
            v.sprite_z_vel[i] -%= 2;
            if (sign8(v.sprite_z[i])) {
                v.sprite_z[i] = 0;
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 15;
            }
            _ = a.Sprite_BounceFromTileCollision(k);
        },
        else => {},
    }
}

pub export fn Hokbok_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var oam = oamPtr() + 3;
    const d: u8 = v.sprite_B[i];
    var y: u16 = info.y;
    var n: c_int = v.sprite_A[i];
    while (n >= 0) : ({
        n -= 1;
        oam -= 1;
    }) {
        const ch: u8 = (if (n == 0) @as(u8, 0xa2) else 0xa0) -% (if (d < 7) @as(u8, 0x20) else 0);
        setOam(oam, info.x, y, ch, info.flags, 2);
        y -%= d;
    }
    a.SpriteDraw_Shadow(k, &info);
}

pub export fn Sprite_C5_Medusa(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (v.player_is_indoors.* == 0) {
        v.sprite_x_vel[i] = 255;
        v.sprite_subtype[i] = 255;
        if (a.Sprite_CheckTileCollision(k) == 0) return;
        if (a.Sprite_ReturnIfInactive(k)) return;
        v.sprite_type[i] = 0x19;
        a.SpritePrep_LoadProperties(k);
        v.sprite_E[i] +%= 1;
        v.sprite_x_lo[i] +%= 8;
        v.sprite_y_lo[i] -%= 8;
        a.SpriteSfx_QueueSfx3WithPan(k, 0x19);
        v.sprite_defl_bits[i] = 0x80;
    } else {
        if (a.Sprite_ReturnIfInactive(k)) return;
        v.sprite_subtype2[i] +%= 1;
        if (v.sprite_subtype2[i] & 0x7f == 0 and v.sprite_floor[i] == v.link_is_on_lower_level.*) {
            const j = a.Sprite_SpawnFireball(k);
            if (j >= 0) {
                const ju = ix(j);
                v.sprite_defl_bits[ju] = v.sprite_defl_bits[ju] | 8;
                v.sprite_bump_damage[ju] = 4;
            }
        }
    }
}

pub export fn Sprite_C6_4WayShooter(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_delay_main[i] == 24) {
        const j = a.Sprite_SpawnFireball(k);
        if (j >= 0) {
            const ju = ix(j);
            v.sprite_defl_bits[ju] |= 8;
            v.sprite_bump_damage[ju] = 4;
            const d: usize = a.Sprite_DirectionToFaceLink(j, null);
            v.sprite_x_vel[ju] = @bitCast(t.kFireballJunction_XYvel[d + 2]);
            v.sprite_y_vel[ju] = @bitCast(t.kFireballJunction_XYvel[d]);
            a.Sprite_SetX(j, a.Sprite_GetX(j) +% s16(t.kFireballJunction_X[d]));
            a.Sprite_SetY(j, a.Sprite_GetY(j) +% s16(t.kFireballJunction_Y[d]));
        }
    } else if (v.sprite_delay_main[i] == 0) {
        if (v.button_b_frames.* != 0 and v.sprite_floor[i] == v.link_is_on_lower_level.*)
            v.sprite_delay_main[i] = 32;
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part53.zig
// ---------------------------------------------------------------------------
/// The `thief_common` label, which case 2 reaches with a goto into case 1.

pub export fn Sprite_C4_Thief(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Thief_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageFromLink(k);
    if (v.sprite_ai_state[i] != 3) {
        const d = a.Sprite_DirectionToFaceLink(k, null);
        v.sprite_head_dir[i] = d;
        if ((d ^ v.sprite_D[i]) == 1)
            v.sprite_D[i] = d;
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // loitering
            a.Thief_CheckCollisionWithLink(k);
            if (v.sprite_delay_main[i] == 0) {
                if (v.link_x_coord.* -% v.cur_sprite_x.* +% 0x50 < 0xa0 and
                    v.link_y_coord.* -% v.cur_sprite_y.* +% 0x50 < 0xa0)
                {
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_delay_main[i] = 16;
                }
            }
            v.sprite_graphics[i] = t.kThief_Gfx[v.sprite_D[i]];
        },
        1 => { // watch player
            a.Thief_CheckCollisionWithLink(k);
            v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null);
            v.sprite_D[i] = v.sprite_head_dir[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 32;
            }
            thiefCommon(k);
        },
        2 => { // chase player
            a.Sprite_ApplySpeedTowardsLink(k, 18);
            if (v.sprite_wallcoll[i] == 0)
                a.Sprite_MoveXY(k);
            _ = a.Sprite_CheckTileCollision(k);
            if (v.sprite_delay_main[i] == 0) {
                if (v.link_x_coord.* -% v.cur_sprite_x.* +% 0x50 >= 0xa0 or
                    v.link_y_coord.* -% v.cur_sprite_y.* +% 0x50 >= 0xa0)
                {
                    v.sprite_ai_state[i] = 0;
                    v.sprite_delay_main[i] = 128;
                }
            }
            if (a.Sprite_CheckDamageToLink(k)) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 32;
                a.Thief_SpillItems(k);
                a.SpriteSfx_QueueSfx2WithPan(k, 0xb);
            }
            thiefCommon(k);
        },
        3 => { // steal
            a.Thief_CheckCollisionWithLink(k);
            const j = a.Thief_ScanForBooty(k);

            if (v.sprite_delay_main[i] == 0) {
                v.sprite_subtype2[i] +%= 1;
                v.sprite_graphics[i] = t.kThief_Gfx[4 + @as(usize, v.sprite_D[i]) + @as(usize, v.sprite_subtype2[i] & 4)];
                if (v.sprite_wallcoll[i] == 0)
                    a.Sprite_MoveXY(k);
                _ = a.Sprite_CheckTileCollision(k);
                v.sprite_D[i] = v.sprite_head_dir[i];
            }
            if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0)
                v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLocation(k, a.Sprite_GetX(j), a.Sprite_GetY(j));
        },
        else => {},
    }
}

pub export fn Thief_ScanForBooty(k: c_int) callconv(.c) u8 {
    const i = ix(k);
    var n: c_int = 15;
    while (n >= 0) : (n -= 1) {
        const j = ix(n);
        if (v.sprite_state[j] != 0 and
            (v.sprite_type[j] == 0xdc or v.sprite_type[j] == 0xe1 or v.sprite_type[j] == 0xd9))
        {
            a.Thief_TargetBooty(k, n);
            return @truncate(@as(u32, @bitCast(n)));
        }
    }
    v.sprite_ai_state[i] = 0;
    v.sprite_delay_main[i] = 64;
    return 0xff;
}

pub export fn Thief_TargetBooty(k: c_int, j: c_int) callconv(.c) void {
    const i = ix(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0) {
        const pt = a.Sprite_ProjectSpeedTowardsLocation(k, a.Sprite_GetX(j), a.Sprite_GetY(j), 19);
        v.sprite_x_vel[i] = pt.x;
        v.sprite_y_vel[i] = pt.y;
    }
    var n: c_int = 15;
    while (n >= 0) : (n -= 1) {
        const ji = ix(n);
        if (((n ^ @as(c_int, v.frame_counter.*)) & 3 | @as(c_int, v.sprite_delay_aux4[ji])) == 0 and
            v.sprite_state[ji] != 0 and
            (v.sprite_type[ji] == 0xdc or v.sprite_type[ji] == 0xe1 or v.sprite_type[ji] == 0xd9))
        {
            a.Thief_GrabBooty(k, n);
        }
    }
}

pub export fn Thief_GrabBooty(k: c_int, j: c_int) callconv(.c) void {
    const i = ix(k);
    const ji = ix(j);
    if (a.Sprite_GetX(j) -% v.cur_sprite_x.* +% 8 < 16 and
        a.Sprite_GetY(j) -% v.cur_sprite_y.* +% 12 < 24)
    {
        v.sprite_state[ji] = 0;

        // Upstream passes the item offset where a sprite index is expected.
        const n: c_int = @as(c_int, v.sprite_type[ji]) - 0xd8;
        a.SpriteSfx_QueueSfx3WithPan(n, st_p53.kAbsorptionSfx[ix(n)]);
        v.sprite_delay_main[i] = 14;
    }
}

pub export fn Thief_CheckCollisionWithLink(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_CheckDamageToLink_same_layer(k)) {
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 32);
        v.link_actual_vel_y.* = pt.y;
        v.sprite_y_recoil[i] = pt.y ^ 0xff;
        v.link_actual_vel_x.* = pt.x;
        v.sprite_x_recoil[i] = pt.x ^ 0xff;
        v.link_incapacitated_timer.* = 4;
        v.sprite_F[i] = 12;
        a.SpriteSfx_QueueSfx2WithPan(k, 0xb);
    }
}

pub export fn Thief_SpillItems(k: c_int) callconv(.c) void {
    v.tmp_counter.* = 5;
    while (true) {
        v.byte_7E0FB6.* = a.GetRandomNumber() & 3;
        const have: u16 = if (v.byte_7E0FB6.* == 1)
            v.link_num_arrows.*
        else if (v.byte_7E0FB6.* == 2)
            v.link_item_bombs.*
        else
            v.link_rupees_goal.*;
        if (have == 0) return;

        var info: SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamicallyEx(k, t.kThiefSpawn_Items[v.byte_7E0FB6.*], &info, 7);
        if (j < 0) return;
        const ju = ix(j);
        if (v.byte_7E0FB6.* == 1)
            v.link_num_arrows.* -%= 1
        else if (v.byte_7E0FB6.* == 2)
            v.link_item_bombs.* -%= 1
        else
            v.link_rupees_goal.* -%= 1;
        a.Sprite_SetX(j, v.link_x_coord.*);
        a.Sprite_SetY(j, v.link_y_coord.*);
        v.sprite_z_vel[ju] = 0x18;
        v.sprite_x_vel[ju] = @bitCast(t.kThiefSpawn_Xvel[v.tmp_counter.*]);
        v.sprite_y_vel[ju] = @bitCast(t.kThiefSpawn_Yvel[v.tmp_counter.*]);
        v.sprite_delay_aux4[ju] = 32;
        v.sprite_head_dir[ju] = 1;
        v.sprite_stunned[ju] = 255;

        v.tmp_counter.* -%= 1;
        if (sign8(v.tmp_counter.*)) break;
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part54.zig
// ---------------------------------------------------------------------------
pub export fn Thief_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kThief_Dmd[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    if (v.sprite_pause[i] == 0) {
        const oam = oamPtr();
        const j: usize = v.sprite_head_dir[i];
        oam[0].charnum = t.kThief_DrawChar[j];
        oam[0].flags = (oam[0].flags & ~@as(u8, 0x40)) | t.kThief_DrawFlags[j];
        a.SpriteDraw_Shadow(k, &info);
    }
}

pub export fn Sprite_C3_Gibo(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_B[i] != 0) {
        a.SpriteDraw_SingleLarge(k);
        if (a.Sprite_ReturnIfInactive(k)) return;
        _ = a.Sprite_CheckDamageToAndFromLink(k);
        v.sprite_subtype2[i] +%= 1;
        v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & 0x3f | t.kGibo_OamFlags[v.sprite_subtype2[i] >> 2 & 3];
        if (v.sprite_delay_main[i] != 0) {
            a.Sprite_MoveXY(k);
            _ = a.Sprite_BounceFromTileCollision(k);
        }
        return;
    }
    Gibo_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_anim_clock[i] +%= 1;
    var j: usize = v.sprite_head_dir[i];
    if (v.sprite_state[j] == 6) {
        v.sprite_state[i] = v.sprite_state[j];
        v.sprite_delay_main[i] = v.sprite_delay_main[j];
        v.sprite_flags2[i] +%= 4;
        return;
    }
    v.sprite_subtype2[i] = v.frame_counter.* >> 3 & 3;
    if (v.frame_counter.* & 63 == 0)
        v.sprite_D[i] = a.Sprite_IsRightOfLink(k).a << 2;
    _ = a.Sprite_CheckDamageToLink(k); // original destroys y which is a bug
    switch (v.sprite_ai_state[i]) {
        0 => { // expel nucleus
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 48;
                v.sprite_A[i] +%= 1;
                var info: SpriteSpawnInfo = undefined;
                const s = a.Sprite_SpawnDynamically(k, 0xc3, &info);
                if (s >= 0) {
                    const su = ix(s);
                    a.Sprite_SetSpawnedCoordinates(s, &info);
                    v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(s)));
                    v.sprite_flags2[su] = 1;
                    v.sprite_B[su] = 1;
                    v.sprite_flags3[su] = 16;
                    v.sprite_health[su] = v.sprite_G[i];
                    v.sprite_oam_flags[su] = 7;
                    v.sprite_delay_main[su] = 48;
                    var d: usize = undefined;
                    v.sprite_C[i] +%= 1;
                    if (v.sprite_C[i] == 3) {
                        v.sprite_C[i] = 0;
                        d = a.Sprite_DirectionToFaceLink(k, null);
                    } else {
                        d = a.GetRandomNumber() & 7;
                    }
                    v.sprite_x_vel[su] = @bitCast(t.kGibo_Xvel[d]);
                    v.sprite_y_vel[su] = @bitCast(t.kGibo_Yvel[d]);
                }
            } else if (v.sprite_delay_main[i] == 32) {
                v.sprite_delay_aux1[i] = 32;
            }
        },
        1 => { // delay pursuit
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] +%= 1;
        },
        2 => { // pursue nucleus
            if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0) {
                const jc: c_int = @intCast(j);
                const x = a.Sprite_GetX(jc);
                const y = a.Sprite_GetY(jc);
                if (v.cur_sprite_x.* -% x +% 2 < 4 and v.cur_sprite_y.* -% y +% 2 < 4) {
                    j = v.sprite_head_dir[i];
                    v.sprite_state[j] = 0;
                    v.sprite_A[i] = 0;
                    v.sprite_ai_state[i] = 0;
                    v.sprite_G[i] = v.sprite_health[j];
                    v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 32;
                    return;
                }
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 16);
                v.sprite_x_vel[i] = pt.x;
                v.sprite_y_vel[i] = pt.y;
            }
            a.Sprite_MoveXY(k);
        },
        else => {},
    }
}

pub export fn Gibo_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_A[i] == 0) {
        const bak0 = v.sprite_flags2[i];
        v.sprite_flags2[i] = 1;
        const bak1 = v.sprite_oam_flags[i];
        v.sprite_oam_flags[i] = t.kGibo_OamFlags[v.sprite_anim_clock[i] >> 2 & 3] |
            t.kGibo_OamFlags2[v.sprite_delay_aux1[i] >> 2 & 1];
        a.SpriteDraw_SingleLarge(k);
        v.sprite_oam_flags[i] = bak1;
        v.sprite_flags2[i] = bak0;
    }
    v.oam_cur_ptr.* +%= 8;
    v.oam_ext_cur_ptr.* +%= 2;
    a.Sprite_DrawMultiple(k, &t.kGibo_Dmd[(@as(usize, v.sprite_subtype2[i]) + @as(usize, v.sprite_D[i])) * 4], 4, null);
}

pub export fn Sprite_C2_Boulder(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.player_is_indoors.* == 0) {
        Boulder_OutdoorsMain(k);
        return;
    }
    if (v.byte_7E0FC6.* < 3)
        a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_oam_flags[i] = v.frame_counter.* << 2 & 0xc0;
    a.Sprite_MoveXYZ(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 != 0)
        return;
    if (v.cur_sprite_x.* -% v.link_x_coord.* +% 4 < 16 and v.cur_sprite_y.* -% v.link_y_coord.* -% 4 < 12)
        a.Sprite_AttemptDamageToLinkPlusRecoil(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0 and a.Sprite_CheckTileCollision(k) != 0)
        v.sprite_state[i] = 0;
}

pub export fn Boulder_OutdoorsMain(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_obj_prio[i] = 0x30;
    Boulder_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_subtype2[i] -%= v.sprite_D[i];
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXYZ(k);
    v.sprite_z_vel[i] -%= 2;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        var j: usize = @intFromBool(a.Sprite_CheckTileCollision(k) != 0);
        v.sprite_z_vel[i] = @bitCast(t.kBoulder_Zvel[j]);
        v.sprite_y_vel[i] = @bitCast(t.kBoulder_Yvel[j]);
        j += @as(usize, a.GetRandomNumber() & 1) * 2;
        v.sprite_x_vel[i] = @bitCast(t.kBoulder_Xvel[j]);
        v.sprite_D[i] = @as(u8, @truncate(j & 2)) -% 1;
        a.SpriteSfx_QueueSfx2WithPan(k, 0xb);
    }
}

pub export fn Boulder_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kBoulder_Dmd[@as(usize, v.sprite_subtype2[i] >> 3 & 3) * 4], 4, &info);
    Sprite_DrawLargeShadow2(k);
}

pub export fn SpriteDraw_BigShadow(k: c_int, anim: c_int) callconv(.c) void {
    const i = ix(k);
    v.cur_sprite_y.* +%= v.sprite_z[i];
    v.oam_cur_ptr.* +%= 16;
    v.oam_ext_cur_ptr.* +%= 4;
    a.Sprite_DrawMultiple(k, &t.kLargeShadow_Dmd[ix(anim) * 3], 3, null);
    a.Sprite_Get16BitCoords(k);
}

pub export fn Sprite_DrawLargeShadow2(k: c_int) callconv(.c) void {
    const z: c_int = v.sprite_z[ix(k)] >> 3;
    SpriteDraw_BigShadow(k, if (z > 4) 4 else z);
}

pub export fn CutsceneAgahnim_SpawnZeldaOnAltar(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_x_lo[i] +%= 8;
    v.sprite_y_lo[i] +%= 6;
    var info: SpriteSpawnInfo = undefined;
    // The C never checks this spawn for failure and indexes with the result.
    const j = a.Sprite_SpawnDynamically(k, 0xc1, &info);
    const ju = ix(j);
    v.sprite_A[ju] = 1;
    v.sprite_ignore_projectile[ju] = 1;
    a.Sprite_SetSpawnedCoordinates(j, &info);
    v.sprite_y_lo[ju] = @truncate(info.r2_y +% 40);
    v.sprite_flags2[ju] = 0;
    v.sprite_oam_flags[ju] = 12;
}

pub export fn Sprite_C1_CutsceneAgahnim(k: c_int) callconv(.c) void {
    switch (v.sprite_A[ix(k)]) {
        0 => a.CutsceneAgahnim_Agahnim(k),
        1 => a.Sprite_CutsceneAgahnim_Zelda(k),
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part55.zig
// ---------------------------------------------------------------------------
pub export fn CutsceneAgahnim_Agahnim(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;

    if (v.sprite_C[i] != 0) {
        if (v.sprite_delay_main[i] == 0)
            v.sprite_state[i] = 0;
        if (v.sprite_delay_main[i] & 1 == 0)
            ChattyAgahnim_Draw(k, &info);
        return;
    }
    ChattyAgahnim_Draw(k, &info);
    SpriteDraw_CutsceneAgahnimSpell(k, &info);
    if (v.sprite_pause[i] != 0) {
        v.sprite_ai_state[i] = 0;
        v.sprite_B[i] = 0;
        v.sprite_graphics[i] = 0;
        v.sprite_delay_main[i] = 64;
    }
    if (a.Sprite_ReturnIfInactive(k)) return;
    switch (v.sprite_ai_state[i]) {
        0 => { // problab
            if (v.sprite_delay_main[i] == 0) {
                v.flag_is_link_immobilized.* = 1;
                v.dialogue_message_index.* = 0x13d;
                a.Sprite_ShowMessageMinimal();
                v.sprite_ai_state[i] +%= 1;
            }
        },
        1 => { // levitate zelda
            v.sprite_B[i] +%= 1;
            const j = v.sprite_B[i];
            v.sprite_graphics[i] = if (v.sprite_z[15] < 16)
                t.kChattyAgahnim_LevitateGfx[j >> 5 & 3]
            else
                1;
            if (j & 15 == 0) {
                v.sprite_graphics[15] = 1;
                v.sprite_z[15] +%= 1;
                if (v.sprite_z[15] == 22) {
                    v.sound_effect_2.* = 0x27;
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_delay_main[i] = 255;
                    v.sprite_subtype2[i] = 2;
                    v.sprite_subtype[i] = 255;
                }
            }
        },
        2 => { // do telewarp
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 80;
            } else if (v.sprite_delay_main[i] == 120) {
                v.intro_times_pal_flash.* = 120;
            } else if (v.sprite_delay_main[i] < 128 and v.sprite_delay_main[i] & 3 == 0) {
                v.sound_effect_2.* = 0x2b;
                if (v.sprite_subtype2[i] != 14)
                    v.sprite_subtype2[i] +%= 4;
            }
        },
        3 => { // complete telewarp
            if (v.sprite_delay_main[i] != 0) {
                if (v.sprite_delay_main[i] & 3 == 0 and v.sprite_subtype[i] != 9)
                    v.sprite_subtype[i] +%= 2;
            } else {
                v.sprite_delay_main[15] = 19;
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 80;
                v.sprite_subtype2[i] = 0;
                v.sound_effect_1.* = 0x33;
            }
        },
        4 => { // epiblab
            if (v.sprite_delay_main[i] == 0) {
                v.dialogue_message_index.* = 0x13e;
                a.Sprite_ShowMessageMinimal();
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 2;
            }
        },
        5 => { // teleport to curtains
            if (v.sprite_delay_main[i] == 1)
                v.sound_effect_2.* = 0x28;
            v.sprite_y_vel[i] = cm.byte(-32);
            a.Sprite_MoveY(k);
            if (v.sprite_y_lo[i] < 48) {
                v.sprite_delay_aux4[i] = 66;
                v.sprite_ai_state[i] +%= 1;
            }
            _ = Sprite_Agahnim_ApplyMotionBlur(k);
        },
        6 => { // linger then terminate
            if (v.sprite_delay_aux4[i] == 0) {
                v.flag_is_link_immobilized.* = 0;
                v.sprite_state[i] = 0;
                a.Sprite_ManuallySetDeathFlagUW(k);
                v.dung_savegame_state_bits.* |= 0x4000;
            }
        },
        else => {},
    }
}

pub export fn Sprite_Agahnim_ApplyMotionBlur(k: c_int) callconv(.c) c_int {
    const i = ix(k);
    if (v.frame_counter.* & 3 != 0)
        return -1;
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xc1, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_graphics[ju] = v.sprite_graphics[i];
        v.sprite_delay_main[ju] = 32;
        v.sprite_ignore_projectile[ju] = 32;
        v.sprite_C[ju] = 32;
    }
    return j;
}

pub export fn ChattyAgahnim_Draw(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_aux4[i] & 1 != 0)
        return;

    if (v.sprite_C[i] == 0) {
        v.oam_cur_ptr.* = 0x900;
        v.oam_ext_cur_ptr.* = 0xa60;
    }
    a.Sprite_DrawMultiple(k, &t.kChattyAgahnim_Dmd[@as(usize, v.sprite_graphics[i]) * 4], 4, info);
    a.SpriteDraw_Shadow_custom(k, info, 18);
}

pub export fn SpriteDraw_CutsceneAgahnimSpell(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    _ = a.Oam_AllocateFromRegionA(0x38);
    // The C picks the second half of the table on alternate frames.
    var di: usize = if (v.frame_counter.* & 2 == 0) 14 else 0;
    var bi: usize = 0;
    if (v.sprite_subtype2[i] == 0)
        return;
    var oam = oamPtr();
    var kn: u8 = v.sprite_subtype2[i] -% 1;
    const end: u8 = v.sprite_subtype[i];
    const off: u8 = end +% 1;
    oam += off;
    di += off;
    bi += off;
    while (true) {
        const d = t.kChattyAgahnim_Telewarp_Data[di];
        setOamPlain(
            oam,
            @truncate(info.x +% s16(d.x)),
            @truncate(info.y +% s16(d.y) -% 8),
            d.charnum,
            d.flags | 0x31,
            t.kChattyAgahnim_Telewarp_Data_Big[bi],
        );
        di += 1;
        bi += 1;
        oam += 1;
        kn -%= 1;
        if (kn == end) break;
    }
}

pub export fn Sprite_CutsceneAgahnim_Zelda(k: c_int) callconv(.c) void {
    const i = ix(k);
    const j = v.sprite_delay_main[i];
    if (j != 0) {
        a.SpriteDraw_AltarZeldaWarp(k);
        if (j == 1)
            v.sprite_state[i] = 0;
        if (j < 12)
            return;
    }
    _ = a.Oam_AllocateFromRegionA(8);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kAltarZelda_Dmd[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    AltarZelda_DrawBody(k, &info);
}

pub export fn AltarZelda_DrawBody(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    _ = a.Oam_AllocateFromRegionA(8);
    const z: usize = if (v.sprite_z[i] < 31) v.sprite_z[i] else 31;
    const xoffs: u16 = t.kAltarZelda_XOffs[z >> 1];
    const y: u16 = a.Sprite_GetY(k) -% v.BG2VOFS_copy2.*;
    const oam = oamPtr();
    setOam(oam + 0, info.x +% xoffs, y +% 7, 0x6c, 0x24, 2);
    setOam(oam + 1, info.x -% xoffs, y +% 7, 0x6c, 0x24, 2);
}

// ---------------------------------------------------------------------------
// from sprite_main_part56.zig
// ---------------------------------------------------------------------------
/// variables.zig spells the x array `moldorm_x_hi_` and has no y counterpart,
/// so these follow sprite_main.zig and derive both from work RAM directly.

pub export fn SpriteDraw_AltarZeldaWarp(k: c_int) callconv(.c) void {
    const i = ix(k);
    _ = a.Oam_AllocateFromRegionA(8);
    a.Sprite_DrawMultiple(k, &t.kAltarZelda_Warp_Dmd[@as(usize, v.sprite_delay_main[i] >> 2) * 2], 2, null);
}

pub export fn Sprite_InitializedSegmented(k: c_int) callconv(.c) void {
    const i = ix(k);
    var n: usize = 0;
    while (n < 128) : (n += 1) {
        v.moldorm_x_lo[n] = v.sprite_x_lo[i];
        moldorm_x_hi[n] = v.sprite_x_hi[i];
        v.moldorm_y_lo[n] = v.sprite_y_lo[i];
        moldorm_y_hi[n] = v.sprite_y_hi[i];
    }
}

pub export fn GiantMoldorm_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    v.sprite_oam_flags[i] = 11;
    SpriteDraw_Moldorm_Eyeballs(k, &info);
    v.oam_cur_ptr.* +%= 8;
    v.oam_ext_cur_ptr.* +%= 2;

    const h: usize = v.sprite_subtype2[i] & 0x7f;
    v.moldorm_x_lo[h] = v.sprite_x_lo[i];
    moldorm_x_hi[h] = v.sprite_x_hi[i];
    v.moldorm_y_lo[h] = v.sprite_y_lo[i];
    moldorm_y_hi[h] = v.sprite_y_hi[i];

    SpriteDraw_Moldorm_Head(k);
    if (v.sprite_B[i] < 4) {
        a.GiantMoldorm_DrawSegment_AB(k, 16);
        if (v.sprite_B[i] < 3) {
            a.GiantMoldorm_DrawSegment_AB(k, 28);
            if (v.sprite_B[i] < 2) {
                SpriteDraw_Moldorm_SegmentC(k);
                if (v.sprite_B[i] == 0)
                    Moldorm_HandleTail(k);
            }
        }
    }
    GiantMoldorm_IncrementalSegmentExplosion(k);
    a.Sprite_Get16BitCoords(k);
}

pub export fn GiantMoldorm_IncrementalSegmentExplosion(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_state[i] == 9 and v.sprite_delay_aux4[i] != 0 and v.sprite_delay_aux4[i] < 80 and
        (v.sprite_delay_aux4[i] & 15 | v.submodule_index.* | v.flag_unk1.*) == 0)
    {
        v.sprite_B[i] +%= 1;
        a.Sprite_MakeBossExplosion(k);
    }
}

pub export fn SpriteDraw_Moldorm_Head(k: c_int) callconv(.c) void {
    const i = ix(k);
    const n: usize = @as(usize, v.sprite_subtype2[i] >> 1 & 1) + @as(usize, v.sprite_delay_aux1[i] & 2);
    a.Sprite_DrawMultiple(k, &t.kGiantMoldorm_Head_Dmd[n * 4], 4, null);
}

pub export fn SpriteDraw_Moldorm_SegmentC(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_graphics[i] = 0;
    v.oam_cur_ptr.* +%= 0x10;
    v.oam_ext_cur_ptr.* +%= 4;
    a.GiantMoldorm_DrawSegment_C_OrTail(k, 0x28);
}

pub export fn Moldorm_HandleTail(k: c_int) callconv(.c) void {
    const i = ix(k);
    SpriteDraw_Moldorm_Tail(k);
    if (v.sprite_delay_aux2[i] == 0) {
        v.sprite_A[i] = 1;
        v.sprite_flags4[i] = 0;
        v.sprite_defl_bits[i] = 0;
        const oldx = a.Sprite_GetX(k);
        const oldy = a.Sprite_GetY(k);
        a.Sprite_SetX(k, v.cur_sprite_x.*);
        a.Sprite_SetY(k, v.cur_sprite_y.*);
        _ = a.Sprite_CheckDamageFromLink(k);
        v.sprite_A[i] = 0;
        v.sprite_flags4[i] = 9;
        v.sprite_defl_bits[i] = 4;
        a.Sprite_SetX(k, oldx);
        a.Sprite_SetY(k, oldy);
    }
}

pub export fn SpriteDraw_Moldorm_Tail(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.oam_cur_ptr.* +%= 4;
    v.oam_ext_cur_ptr.* +%= 1;
    v.sprite_graphics[i] +%= 1;
    v.sprite_oam_flags[i] = 13;
    a.GiantMoldorm_DrawSegment_C_OrTail(k, 0x30);
}

pub export fn SpriteDraw_Moldorm_Eyeballs(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    var oam = oamPtr();
    const r7: c_int = if (v.sprite_F[i] != 0) v.frame_counter.* else 0;
    var r6: c_int = @as(c_int, v.sprite_D[i]) - 1;
    var n: c_int = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
        r6 += 2;
    }) {
        const e: usize = @intCast(r6 & 0xf);
        const c: usize = @intCast((r6 + r7) & 0xf);
        const x: u16 = info.x +% @as(u16, @bitCast(t.kGiantMoldorm_Eye_X[e]));
        const y: u16 = info.y +% @as(u16, @bitCast(t.kGiantMoldorm_Eye_Y[e]));
        setOam(oam, x, y, t.kGiantMoldorm_Eye_Char[c], info.flags | t.kGiantMoldorm_Eye_Flags[c], 2);
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part57.zig
// ---------------------------------------------------------------------------
pub export fn Vitreous_SpawnSmallerEyes(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_G[i] = 9;
    v.sprite_graphics[i] = 4;

    var info: SpriteSpawnInfo = undefined;
    // The C discards this spawn's slot and reuses j as the loop counter; only
    // the coordinates it filled in are kept.
    _ = a.Sprite_SpawnDynamicallyEx(k, 0x4, &info, 13);

    var n: c_int = 13;
    while (n != 0) : (n -= 1) {
        const j = ix(n);
        const e = j - 1;
        v.sprite_state[j] = 9;
        v.sprite_type[j] = 0xbe;
        a.SpritePrep_LoadProperties(n);
        v.sprite_floor[j] = 0;
        a.Sprite_SetX(n, info.r0_x +% s16(t.kVitreous_SpawnSmallerEyes_X[e]));
        a.Sprite_SetY(n, info.r2_y +% s16(t.kVitreous_SpawnSmallerEyes_Y[e]) +% 32);
        v.sprite_A[j] = v.sprite_x_lo[j];
        v.sprite_B[j] = v.sprite_x_hi[j];
        v.sprite_C[j] = v.sprite_y_lo[j];
        v.sprite_D[j] = v.sprite_y_hi[j];
        v.sprite_graphics[j] = @bitCast(t.kVitreous_SpawnSmallerEyes_Gfx[e]);
        v.sprite_ignore_projectile[j] = v.sprite_graphics[j];
        v.sprite_subtype2[j] = @as(u8, @truncate(e)) *% 8 +% a.GetRandomNumber();
    }
}

pub export fn Sprite_C0_Catfish(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_A[i] & 0x80 != 0)
        Sprite_Catfish_SplashOfWater(k)
    else if (v.sprite_A[i] == 0)
        Catfish_BigFish(k)
    else
        Sprite_Catfish_QuakeMedallion(k);
}

pub export fn Sprite_Catfish_QuakeMedallion(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_z[i] == 0) {
        a.SpriteDraw_WaterRipple_WithOamAdjust(k);
        if (v.submodule_index.* == 0 and a.Sprite_CheckDamageToLink_same_layer(k)) {
            v.sprite_state[i] = 0;
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(v.sprite_A[i], 0);
        }
    }
    if (v.sprite_delay_aux3[i] != 0)
        _ = a.Oam_AllocateFromRegionC(8);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_MoveXYZ(k);
    v.sprite_z_vel[i] -%= 2;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_x_vel[i] = @bitCast(@as(i8, @bitCast(v.sprite_x_vel[i])) >> 1);
        v.sprite_y_vel[i] = @bitCast(@as(i8, @bitCast(v.sprite_y_vel[i])) >> 1);
        const j = v.sprite_ai_state[i];
        if (j == 4) {
            v.sprite_x_vel[i] = 0;
            v.sprite_y_vel[i] = 0;
            v.sprite_z_vel[i] = 0;
        } else {
            v.sprite_ai_state[i] +%= 1;
            v.sprite_z_vel[i] = t.kStandaloneItem_Zvel[j];
            if (j < 2) {
                const s = Sprite_SpawnWaterSplash(k);
                if (s >= 0)
                    v.sprite_delay_main[ix(s)] = 16;
            }
        }
    }
}

pub export fn Catfish_BigFish(k: c_int) callconv(.c) void {
    const i = ix(k);
    GreatCatfish_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    switch (v.sprite_ai_state[i]) {
        0 => { // AwaitSpriteThrownInCircle
            var n: c_int = 15;
            while (n >= 0) : (n -= 1) {
                const j = ix(n);
                if (n == k or v.sprite_state[j] != 3)
                    continue;
                if (v.cur_sprite_x.* -% a.Sprite_GetX(n) +% 32 < 64 and
                    v.cur_sprite_y.* -% a.Sprite_GetY(n) +% 32 < 64)
                {
                    v.sprite_ai_state[i] = 1;
                    v.sprite_delay_main[i] = 255;
                    return;
                }
            }
        },
        1 => { // RumbleBeforeEmergence
            const j = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 255;
                v.bg1_x_offset.* = 0;
                v.sound_effect_ambient.* = 5;
                v.sprite_z_vel[i] = 48;
                v.sprite_x_vel[i] = 0;
                Catfish_SpawnPlop(k);
            } else if (v.sprite_delay_main[i] < 0xc0) {
                if (v.sprite_delay_main[i] == 0xbf)
                    v.sound_effect_ambient.* = 7;
                v.bg1_x_offset.* = if (j & 1 != 0) 0xffff else 1;
                v.flag_is_link_immobilized.* = 1;
            }
        },
        2 => { // Emerge
            v.sprite_subtype2[i] +%= 1;
            a.Sprite_MoveXYZ(k);
            v.sprite_z_vel[i] -%= 2;
            if (v.sprite_z_vel[i] == cm.byte(-48))
                Catfish_SpawnPlop(k);
            if (sign8(v.sprite_z[i])) {
                v.sprite_z[i] = 0;
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 255;
            }
            v.sprite_graphics[i] = t.kGreatCatfish_Emerge_Gfx[v.sprite_subtype2[i] >> 2];
        },
        3 => { // ConversateThenSubmerge
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                v.sprite_state[i] = 0;
            } else {
                if (j == 160 or j == 252 or j == 4) {
                    _ = Sprite_SpawnWaterSplash(k);
                } else if (j == 10) {
                    Catfish_SpawnPlop(k);
                } else if (j == 96) {
                    v.flag_is_link_immobilized.* = 0;
                    v.dialogue_message_index.* = if (v.link_item_quake_medallion.* != 0) 0x12b else 0x12a;
                    a.Sprite_ShowMessageMinimal();
                    return;
                } else if (j == 80) {
                    if (v.link_item_quake_medallion.* != 0) {
                        if (a.GetRandomNumber() & 1 != 0)
                            _ = Sprite_SpawnBomb(k)
                        else
                            _ = a.Sprite_SpawnFireball(k);
                    } else {
                        Catfish_RegurgitateMedallion(k);
                    }
                }
                if (j < 160)
                    v.sprite_graphics[i] = t.kGreatCatfish_Conversate_Gfx[j >> 3];
            }
        },
        else => {},
    }
}

pub export fn Sprite_SpawnBomb(k: c_int) callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x4a, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        a.Sprite_TransmuteToBomb(j);
        v.sprite_delay_aux1[ju] = 80;
        v.sprite_x_vel[ju] = 24;
        v.sprite_z_vel[ju] = 48;
    }
    return j;
}

pub export fn Catfish_RegurgitateMedallion(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xc0, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_x_vel[ju] = 24;
        v.sprite_z_vel[ju] = 48;
        v.sprite_A[ju] = 17;
        a.SpriteSfx_QueueSfx2WithPan(j, 0x20);
        v.sprite_flags2[ju] = 0x83;
        v.sprite_flags3[ju] = 0x58;
        v.sprite_oam_flags[ju] = 0x58 & 0xf;
        a.DecodeAnimatedSpriteTile_variable(0x1c);
    }
}

pub export fn Sprite_Zora_RegurgitateFlippers(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xc0, &info);
    if (j < 0) return;
    const ju = ix(j);
    a.Sprite_SetSpawnedCoordinates(j, &info);
    v.sprite_z_vel[ju] = 32;
    v.sprite_y_vel[ju] = 16;
    v.sprite_A[ju] = 30;
    a.SpriteSfx_QueueSfx2WithPan(j, 0x20);
    v.sprite_flags2[ju] = 0x83;
    v.sprite_flags3[ju] = 0x54;
    v.sprite_oam_flags[ju] = 0x54 & 15;
    v.sprite_delay_aux3[ju] = 0x30;
    a.DecodeAnimatedSpriteTile_variable(0x11);
}

pub export fn Catfish_SpawnPlop(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xec, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_state[ju] = 3;
        v.sprite_delay_main[ju] = 15;
        v.sprite_ai_state[ju] = 0;
        v.sprite_flags2[ju] = 3;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x28);
    }
}

pub export fn Sprite_SpawnWaterSplash(k: c_int) callconv(.c) c_int {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0xc0, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_A[ju] = 0x80;
        v.sprite_flags2[ju] = 2;
        v.sprite_ignore_projectile[ju] = 2;
        v.sprite_oam_flags[ju] = 4;
        v.sprite_delay_main[ju] = 31;
    }
    return j;
}

pub export fn GreatCatfish_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_graphics[i] != 0)
        a.Sprite_DrawMultiple(k, &t.kGreatCatfish_Dmd[(@as(usize, v.sprite_graphics[i]) - 1) * 4], 4, null);
}

pub export fn Sprite_Catfish_SplashOfWater(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_main[i] == 0)
        v.sprite_state[i] = 0;
    a.Sprite_DrawMultiple(k, &t.kWaterSplash_Dmd[@as(usize, v.sprite_delay_main[i] >> 3) * 2], 2, null);
}

// ---------------------------------------------------------------------------
// from sprite_main_part58.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_BD_Vitreous(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_aux4[i] != 0)
        v.sprite_graphics[i] = 3;
    a.Vitreous_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Vitreous_SetMinionsForth(k);
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // dormant
            v.byte_7E0FF8.* = 0;
            v.sprite_F[i] = 0;
            v.sprite_flags3[i] |= 64;
            // The C only decrements the timer on even frames.
            if (v.frame_counter.* & 1 == 0) {
                v.sprite_A[i] -%= 1;
                if (v.sprite_A[i] == 0) {
                    v.sprite_flags3[i] &= ~@as(u8, 0x40);
                    v.sprite_delay_aux4[i] = 16;
                    v.sprite_ai_state[i] = 1;
                    v.sprite_delay_main[i] = 128;
                    if (v.sprite_G[i] == 0) {
                        v.sprite_ai_state[i] = 2;
                        v.sprite_delay_main[i] = 64;
                        v.sprite_ignore_projectile[i] = 0;
                        v.sound_effect_1.* = 0x35;
                        return;
                    }
                }
            }
            v.sprite_graphics[i] = if (v.frame_counter.* & 0x30 != 0) 4 else 5;
        },
        1 => { // spew lighting
            v.sprite_F[i] = 0;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_aux4[i] = 16;
                v.sprite_ai_state[i] = 0;
                v.sprite_A[i] = t.kVitreous_AfromG[v.sprite_G[i]];
            } else {
                a.Vitreous_Animate(k, v.sprite_delay_main[i]);
            }
        },
        2 => { // pursue player
            a.Vitreous_Animate(k, 0x8b);
            if (a.Sprite_ReturnIfRecoiling(k)) return;
            if (v.sprite_delay_main[i] != 0) {
                v.sprite_x_vel[i] = @bitCast(t.kVitreous_Xvel[(v.sprite_delay_main[i] & 2) >> 1]);
                a.Sprite_MoveX(k);
            } else {
                a.Sprite_MoveXYZ(k);
                _ = a.Sprite_CheckTileCollision(k);
                v.sprite_z_vel[i] -%= 2;
                if (sign8(v.sprite_z[i])) {
                    v.sprite_z[i] = 0;
                    v.sprite_z_vel[i] = 32;
                    a.Sprite_ApplySpeedTowardsLink(k, 16);
                    a.SpriteSfx_QueueSfx2WithPan(k, 0x21);
                }
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part59.zig
// ---------------------------------------------------------------------------
/// variables.zig spells the x array `moldorm_x_hi_` and has no y counterpart,
/// so these follow sprite_main.zig and derive both from work RAM directly.

pub export fn Sprite_EvilBarrier(k: c_int) callconv(.c) void {
    const i = ix(k);
    EvilBarrier_Draw(k);
    if (v.sprite_graphics[i] == 4)
        return;

    v.sprite_graphics[i] = v.frame_counter.* >> 1 & 3;
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_CheckDamageFromLink(k) != 0 and v.link_sword_type.* < 2) {
        v.sprite_hit_timer[i] = 0;
        a.Sprite_AttemptDamageToLinkPlusRecoil(k);
        if (v.countdown_for_blink.* == 0)
            v.link_electrocute_on_touch.* = 64;
    }

    if (v.link_y_coord.* -% v.cur_sprite_y.* +% 8 < 24 and
        v.link_x_coord.* -% v.cur_sprite_x.* +% 32 < 64 and
        sign8(v.link_actual_vel_y.* -% 1))
    {
        v.link_electrocute_on_touch.* = 64;
        v.link_incapacitated_timer.* = 12;
        v.link_auxiliary_state.* = 1;
        v.link_give_damage.* = 2;
        v.link_actual_vel_x.* = 0;
        v.link_actual_vel_y.* = 48;
    }
}

pub export fn EvilBarrier_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.cur_sprite_y.* +%= 8;
    a.Sprite_DrawMultiple(k, &t.kEvilBarrier_Dmd[@as(usize, v.sprite_graphics[i]) * 9], 9, null);
    a.Sprite_Get16BitCoords(k);
}

pub export fn Goriya_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_aux1[i] != 0 and v.sprite_D[i] != 3)
        a.Sprite_DrawMultiple(k, &t.kGoriya_Dmd2[v.sprite_D[i]], 1, null);

    var info: PrepOamCoordsRet = undefined;
    v.oam_cur_ptr.* +%= 4;
    v.oam_ext_cur_ptr.* +%= 1;
    const g: usize = v.sprite_graphics[i];
    a.Sprite_DrawMultiple(
        k,
        &t.kGoriya_Dmd[t.kGoriyaDmdOffs[g]],
        @as(c_int, t.kGoriyaDmdOffs[g + 1]) - @as(c_int, t.kGoriyaDmdOffs[g]),
        &info,
    );
    v.sprite_flags2[i] -%= 1;
    a.SpriteDraw_Shadow(k, &info);
    v.sprite_flags2[i] +%= 1;
}

pub export fn Moldorm_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    var oam = oamPtr();
    var base: u8 = v.sprite_D[i] -% 1;
    var n: c_int = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
        base +%= 2;
    }) {
        const e: usize = base & 0xf;
        setOam(
            oam,
            info.x +% s16(t.kMoldorm_Draw_X[e]),
            info.y +% s16(t.kMoldorm_Draw_Y[e]),
            0x4d,
            info.flags,
            0,
        );
    }
    v.oam_cur_ptr.* +%= 8;
    v.oam_ext_cur_ptr.* +%= 2;

    const cur: usize = @as(usize, v.sprite_subtype2[i] & 0x1f) + i * 32;
    v.moldorm_x_lo[cur] = v.sprite_x_lo[i];
    moldorm_x_hi[cur] = v.sprite_x_hi[i];
    v.moldorm_y_lo[cur] = v.sprite_y_lo[i];
    moldorm_y_hi[cur] = v.sprite_y_hi[i];

    var m: c_int = 2;
    while (m >= 0) : ({
        m -= 1;
        oam += 1;
    }) {
        const e = ix(m);
        const h: usize = @as(usize, (v.sprite_subtype2[i] +% t.kMoldorm_Draw_GetOffs[e]) & 0x1f) + i * 32;
        const x: u16 = ((@as(u16, moldorm_x_hi[h]) << 8) | v.moldorm_x_lo[h]) -%
            v.BG2HOFS_copy2.* +% s16(t.kMoldorm_Draw_XY[e]);
        const y: u16 = ((@as(u16, moldorm_y_hi[h]) << 8) | v.moldorm_y_lo[h]) -%
            v.BG2VOFS_copy2.* +% s16(t.kMoldorm_Draw_XY[e]);
        setOam(oam, x, y, t.kMoldorm_Draw_Char[e], info.flags, t.kMoldorm_Draw_Big[e]);
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part60.zig
// ---------------------------------------------------------------------------
/// misc.h keeps this a `static inline` with no linkable symbol, and it searches
/// *backwards*, returning -1 when the value is absent.

pub export fn TalkingTree_Mouth(k: c_int) callconv(.c) void {
    const i = ix(k);
    TalkingTree_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_flags4[i] = 0;
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_graphics[i] = 0;
            if (a.Sprite_CheckDamageToLink_same_layer(k)) {
                a.Link_CancelDash();
                v.link_incapacitated_timer.* = 16;
                const pt = a.Sprite_ProjectSpeedTowardsLink(k, 48);
                v.link_actual_vel_y.* = pt.y;
                v.link_actual_vel_x.* = pt.x;
                a.SpriteSfx_QueueSfx3WithPan(k, 0x32);
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 48;
            }
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 8;
            }
            v.sprite_graphics[i] = v.sprite_delay_main[i] >> 1 & 3;
        },
        2 => {
            // zelda bug wtf: the index is not masked, so it relies on the delay
            // having already ticked below 8 by the time this state runs.
            v.sprite_graphics[i] = @bitCast(t.kTalkingTree_Gfx2[v.sprite_delay_main[i] >> 1]);
            if (v.sprite_delay_main[i] == 7)
                TalkingTree_SpawnBomb(k);
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] +%= 1;
        },
        3 => {
            v.sprite_flags4[i] = 7;
            if (v.sprite_A[i] == 0) {
                const j: usize = v.sprite_x_lo[i] >> 4 & 1 ^ 1;
                v.sprite_A[i] = @truncate(j);
                if (a.Sprite_ShowSolicitedMessage(k, t.kTalkingTree_Msgs2[j]) & 0x100 == 0)
                    v.sprite_A[i] = 0;
            } else {
                // Upstream indexes with -1 when the screen is not in the table.
                const j = FindInByteArray(&t.kTalkingTree_Screens, @truncate(v.overworld_screen_index.*), 4);
                a.Sprite_ShowMessageUnconditional(t.kTalkingTree_Msgs[ix(j)]);
                v.sprite_A[i] = 0;
            }
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_B[i] = v.sprite_B[i] +% 1 & 7;
                const j: usize = v.sprite_B[i];
                v.sprite_graphics[i] = t.kTalkingTree_Gfx[j];
                v.sprite_delay_main[i] = t.kTalkingTree_Delay[j];
            }
        },
        else => {},
    }
}

pub export fn TalkingTree_SpawnBomb(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x4a, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_TransmuteToBomb(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        v.sprite_delay_aux1[ju] = 64;
        v.sprite_y_vel[ju] = 24;
        v.sprite_z_vel[ju] = 18;
    }
}

pub export fn TalkingTree_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    const g: c_int = @as(c_int, v.sprite_graphics[i]) - 1;
    if (g < 0)
        return;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kTalkingTree_Dmd[ix(g) * 4], 4, null);
}

// ---------------------------------------------------------------------------
// from sprite_main_part61.zig
// ---------------------------------------------------------------------------
pub export fn TalkingTree_Eye(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    const base_x: u16 = v.sprite_A[i] | (@as(u16, v.sprite_B[i]) << 8);
    const base_y: u16 = v.sprite_C[i] | (@as(u16, v.sprite_E[i]) << 8);
    a.Sprite_SetX(k, base_x +% s16(t.kTalkingTree_Type1_X[v.sprite_head_dir[i]]));
    a.Sprite_SetY(k, base_y);
    const pt = a.Sprite_ProjectSpeedTowardsLink(k, 2);
    if (!sign8(pt.y)) {
        v.sprite_D[i] = pt.x +% 2;
    } else if (v.sprite_D[i] != 2) {
        v.sprite_D[i] +%= if (v.sprite_D[i] >= 2) 0 -% @as(u8, 1) else 1;
    }
    const j: usize = v.sprite_D[i];
    a.Sprite_SetX(k, base_x +% s16(t.kTalkingTree_X1[j]));
    a.Sprite_SetY(k, base_y +% s16(t.kTalkingTree_Y1[j]));
}

pub export fn SpritePrep_TalkingTree_SpawnEyeball(k: c_int, dir: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x25, &info);
    if (j >= 0) {
        const ju = ix(j);
        v.sprite_head_dir[ju] = @truncate(@as(u32, @bitCast(dir)));
        const x: u16 = info.r0_x +% s16(t.kTalkingTree_SpawnX[ix(dir)]);
        const y: u16 = info.r2_y -% 11;
        a.Sprite_SetX(j, x);
        a.Sprite_SetY(j, y);
        v.sprite_A[ju] = @truncate(x);
        v.sprite_B[ju] = @truncate(x >> 8);
        v.sprite_C[ju] = @truncate(y);
        v.sprite_E[ju] = @truncate(y >> 8);
        v.sprite_subtype2[ju] = 1;
    }
}

pub export fn RupeePull_SpawnPrize(k: c_int) callconv(.c) void {
    if (v.num_sprites_killed.* != 0) {
        v.byte_7E0FB6.* = if (v.num_sprites_killed.* < 4)
            0
        else if (v.number_of_times_hurt_by_sprites.* != 0)
            1
        else
            2;
        v.tmp_counter.* = 3;
        while (true) {
            var info: SpriteSpawnInfo = undefined;
            const j = a.Sprite_SpawnDynamically(k, t.kSpawnRupees_Type[v.byte_7E0FB6.*], &info);
            if (j < 0) break;
            const ju = ix(j);
            a.Sprite_SetSpawnedCoordinates(j, &info);
            v.sprite_x_vel[ju] = @bitCast(t.kSpawnRupees_Xvel[v.tmp_counter.*]);
            v.sprite_y_vel[ju] = @bitCast(t.kSpawnRupees_Yvel[v.tmp_counter.*]);
            v.sprite_stunned[ju] = 255;
            v.sprite_delay_aux4[ju] = 32;
            v.sprite_delay_aux3[ju] = 32;
            v.sprite_z_vel[ju] = 32;

            v.tmp_counter.* -%= 1;
            if (sign8(v.tmp_counter.*)) break;
        }
    }
    v.num_sprites_killed.* = 0;
    v.number_of_times_hurt_by_sprites.* = 0;
}

pub export fn Sprite_D5_DigGameGuy(k: c_int) callconv(.c) void {
    const i = ix(k);
    DiggingGameGuy_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_BehaveAsBarrier(k);
    a.Sprite_MoveXY(k);
    v.sprite_x_vel[i] = 0;
    switch (v.sprite_ai_state[i]) {
        0 => { // intro
            if (v.sprite_y_lo[i] +% 7 < @as(u8, @truncate(v.link_y_coord.*)) and
                a.Sprite_DirectionToFaceLink(k, null) == 2)
            {
                if (v.follower_indicator.* == 0) {
                    if (a.Sprite_ShowSolicitedMessage(k, 0x187) & 0x100 != 0)
                        v.sprite_ai_state[i] +%= 1;
                } else {
                    _ = a.Sprite_ShowSolicitedMessage(k, 0x18c);
                }
            }
        },
        1 => { // do you want to play
            if (v.choice_in_multiselect_box.* == 0 and v.link_rupees_goal.* >= 80) {
                v.link_rupees_goal.* -%= 80;
                a.Sprite_ShowMessageUnconditional(0x188);
                v.sprite_ai_state[i] = 2;
                v.sprite_graphics[i] = 1;
                v.sprite_delay_main[i] = 80;
                v.beamos_x_hi[0] = 0;
                v.beamos_x_hi[1] = 0;
                v.sprite_delay_aux1[i] = 5;
                a.Sprite_InitializeSecondaryItemMinigame(1);
                v.music_control.* = 14;
            } else {
                a.Sprite_ShowMessageUnconditional(0x189);
                v.sprite_ai_state[i] = 0;
            }
        },
        2 => { // move out of the way
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_graphics[i] = 1;
            } else if (v.sprite_delay_aux1[i] == 0) {
                v.sprite_graphics[i] ^= 3;
                if (v.sprite_graphics[i] & 1 != 0)
                    v.sprite_x_vel[i] = cm.byte(-16);
                v.sprite_delay_aux1[i] = 5;
            }
        },
        3 => { // start timer
            v.sprite_ai_state[i] +%= 1;
            v.super_bomb_indicator_unk1.* = 0;
            v.super_bomb_indicator_unk2.* = 30;
        },
        4 => { // terminate
            if (@as(i8, @bitCast(v.super_bomb_indicator_unk2.*)) > 0 or v.link_position_mode.* & 1 != 0)
                return;
            v.music_control.* = 9;
            v.sprite_ai_state[i] +%= 1;
            v.is_archer_or_shovel_game.* = 0;
            v.dialogue_message_index.* = 0x18a;
            a.Sprite_ShowMessageMinimal();
            v.super_bomb_indicator_unk2.* = 254;
        },
        5 => { // come back later
            _ = a.Sprite_ShowSolicitedMessage(k, 0x18b);
        },
        else => {},
    }
}

pub export fn DiggingGameGuy_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiplePlayerDeferred(k, &t.kDiggingGameGuy_Dmd[@as(usize, v.sprite_graphics[i]) * 3], 3, &info);
    a.SpriteDraw_Shadow(k, &info);
}

// ---------------------------------------------------------------------------
// from sprite_main_part62.zig
// ---------------------------------------------------------------------------
pub export fn OldMountainMan_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_subtype2[i] != 2) {
        const j: usize = @as(usize, v.sprite_D[i]) * 4 + @as(usize, v.sprite_graphics[i]) * 2;
        // BYTE(dma_var6) / BYTE(dma_var7): low byte only.
        v.dma_var6.* = (v.dma_var6.* & 0xff00) | t.kOldMountainMan_Dma[j + 0];
        v.dma_var7.* = (v.dma_var7.* & 0xff00) | t.kOldMountainMan_Dma[j + 1];
        a.Sprite_DrawMultiplePlayerDeferred(k, &t.kOldMountainMan_Dmd1[j], 2, null);
    } else {
        a.Sprite_DrawMultiplePlayerDeferred(k, &t.kOldMountainMan_Dmd0[0], 2, null);
    }
}

pub export fn HelmasaurKing_Initialize(k: c_int) callconv(.c) void {
    v.overlord_gen1[7] = 0x30;
    v.overlord_gen1[5] = 0x80;
    v.overlord_gen1[6] = 0;
    v.overlord_gen2[0] = 0;
    v.overlord_gen2[3] = 0;
    v.overlord_gen2[1] = 0;
    v.overlord_gen2[2] = 0;
    HelmasaurKing_Reinitialize(k);
}

pub export fn HelmasaurKing_Reinitialize(k: c_int) callconv(.c) void {
    const i = ix(k);
    const s: usize = v.sprite_subtype2[i];
    var n: c_int = 3;
    while (n >= 0) : (n -= 1) {
        const j = ix(n);
        v.overlord_x_lo[j] = t.kHelmasaur_Tab0[(s + j * 8) & 0x1f];
    }
}

/// The `anim_clk` label, which the aux1 == 96 path reaches with a goto.

pub export fn Sprite_92_HelmasaurKing(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (sign8(v.sprite_C[i])) {
        if (v.sprite_delay_main[i] == 1)
            v.sprite_state[i] = 0;
        a.SpriteDraw_SingleLarge(k);
        if (a.Sprite_ReturnIfInactive(k)) return;
        if ((v.frame_counter.* & 7 | v.sprite_delay_aux1[i]) == 0)
            v.sprite_oam_flags[i] ^= 0x40;
        a.Sprite_MoveXYZ(k);
        v.sprite_z_vel[i] -%= 2;
        if (sign8(v.sprite_z[i])) {
            v.sprite_z[i] = 0;
            v.sprite_delay_main[i] = 12;
            v.sprite_z_vel[i] = 24;
            v.sprite_graphics[i] = 6;
        }
        return;
    }
    if (v.sprite_C[i] < 3) {
        v.sprite_obj_prio[i] &= ~@as(u8, 0xe);
        v.sprite_flags[i] = 0xa;
    } else {
        v.sprite_flags4[i] = 0x1f;
        v.sprite_flags[i] = 2;
    }
    a.HelmasaurKing_Draw(k);
    if (v.sprite_state[i] == 6) {
        const d = v.sprite_delay_main[i];
        if (d == 0) {
            v.sprite_state[i] = 4;
            v.sprite_A[i] = 0;
            v.sprite_delay_main[i] = 224;
            return;
        }
        v.sprite_hit_timer[i] = d | 240;
        if (d < 128 and d & 7 == 0 and v.overlord_gen2[3] != 0x10) {
            const j: usize = v.overlord_gen2[3];
            v.overlord_gen2[3] +%= 1;
            v.cur_sprite_x.* = a.Sprite_GetX(k) +% s16(@bitCast(v.overlord_x_lo[5 + j]));
            v.cur_sprite_y.* = a.Sprite_GetY(k) +% s16(@bitCast(v.overlord_y_lo[5 + j]));
            a.Sprite_MakeBossExplosion(k);
        }
        return;
    }

    if (a.Sprite_ReturnIfInactive(k)) return;
    const stage = t.kHelmasaurKing_Tab1[v.sprite_health[i] >> 2];
    v.sprite_C[i] = stage;
    if (stage == 3) {
        if (stage != v.sprite_E[i]) {
            v.sprite_hit_timer[i] = 0;
            a.HelmasaurKing_ExplodeMask(k);
        }
    } else {
        if (stage != v.sprite_E[i])
            a.HelmasaurKing_ChipAwayAtMask(k);
    }
    v.sprite_E[i] = v.sprite_C[i];
    _ = a.Sprite_CheckDamageFromLink(k);
    a.HelmasaurKing_SwingTail(k);
    a.HelmasaurKing_AttemptDamage(k);
    a.HelmasaurKing_CheckMaskDamageFromHammer(k);

    if (v.sprite_delay_aux1[i] == 0) {
        if (v.sprite_delay_aux2[i] != 0) {
            if (v.sprite_delay_aux2[i] == 0x40) {
                a.HelmasaurKing_SpitFireball(k);
                if (v.sprite_C[i] >= 3)
                    helmasaurAnimClk(k);
            }
            return;
        }
    } else {
        if (v.sprite_delay_aux1[i] == 96)
            helmasaurAnimClk(k);
        return;
    }

    switch (v.sprite_ai_state[i]) {
        0 => {
            if ((v.sprite_hit_timer[i] != 0 or v.sprite_delay_main[i] == 0) and
                !a.HelmasaurKing_MaybeFireball(k))
            {
                const j: usize = a.GetRandomNumber() & 7;
                v.sprite_x_vel[i] = @bitCast(t.kHelmasaurKing_Xvel0[j]);
                v.sprite_y_vel[i] = @bitCast(t.kHelmasaurKing_Yvel0[j]);
                v.sprite_delay_main[i] = 64;
                if (v.sprite_C[i] >= 3) {
                    v.sprite_x_vel[i] = v.sprite_x_vel[i] << 1;
                    v.sprite_y_vel[i] = v.sprite_y_vel[i] << 1;
                    v.sprite_delay_main[i] >>= 1;
                }
                v.sprite_ai_state[i] +%= 1;
            }
        },
        1 => {
            a.HelmasaurKing_HandleMovement(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 32;
                v.sprite_ai_state[i] +%= 1;
            }
        },
        2 => {
            if ((v.sprite_hit_timer[i] != 0 or v.sprite_delay_main[i] == 0) and
                !a.HelmasaurKing_MaybeFireball(k))
            {
                v.sprite_delay_main[i] = 64;
                if (v.sprite_E[i] >= 3)
                    v.sprite_delay_main[i] >>= 1;
                v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
                v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
                v.sprite_ai_state[i] +%= 1;
            }
        },
        3 => {
            a.HelmasaurKing_HandleMovement(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 64;
            }
        },
        else => {},
    }
}

pub export fn HelmasaurKing_HandleMovement(k: c_int) callconv(.c) void {
    const i = ix(k);
    var n: c_int = 1 + @as(c_int, @intFromBool(v.frame_counter.* & 3 == 0)) +
        @as(c_int, @intFromBool(v.sprite_C[i] >= 3));
    while (true) {
        v.sprite_subtype2[i] +%= 1;
        if (v.sprite_subtype2[i] & 15 == 0)
            v.sound_effect_1.* = 0x21;
        n -= 1;
        if (n == 0) break;
    }
    a.Sprite_MoveXY(k);
}

pub export fn HelmasaurKing_MaybeFireball(k: c_int) callconv(.c) bool {
    const i = ix(k);
    v.sprite_subtype[i] +%= 1;
    if (v.sprite_subtype[i] != 4)
        return false;
    v.sprite_subtype[i] = 0;
    if (a.GetRandomNumber() & 1 != 0) {
        v.sprite_delay_aux2[i] = 127;
        a.SpriteSfx_QueueSfx3WithPan(k, 0x2a);
    } else {
        v.sprite_delay_aux1[i] = 160;
    }
    return true;
}

pub export fn HelmasaurKing_AttemptDamage(k: c_int) callconv(.c) void {
    if (v.frame_counter.* & 7 == 0 and
        v.link_x_coord.* -% v.cur_sprite_x.* +% 36 < 72 and
        v.link_y_coord.* -% v.cur_sprite_y.* +% 40 < 64)
        a.Sprite_AttemptDamageToLinkPlusRecoil(k);
}

pub export fn HelmasaurKing_ChipAwayAtMask(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.tmp_counter.* = v.sprite_C[i] +% 7;
    a.HelmasaurKing_SpawnMaskDebris(k);
    a.SpriteSfx_QueueSfx2WithPan(k, 0x1f);
}

pub export fn HelmasaurKing_ExplodeMask(k: c_int) callconv(.c) void {
    var j: usize = 1;
    while (j < 16) : (j += 1)
        v.sprite_state[j] = 0;
    v.tmp_counter.* = 7;
    while (true) {
        a.HelmasaurKing_SpawnMaskDebris(k);
        v.tmp_counter.* -%= 1;
        if (sign8(v.tmp_counter.*)) break;
    }
    a.SpriteSfx_QueueSfx2WithPan(k, 0x1f);
}

pub export fn HelmasaurKing_SpitFireball(k: c_int) callconv(.c) void {
    var info: a.SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x70, &info);
    if (j >= 0) {
        const ju = ix(j);
        a.Sprite_SetSpawnedCoordinates(j, &info);
        a.Sprite_SetY(j, info.r2_y +% 28);
        v.sprite_delay_main[ju] = 32;
        v.sprite_ignore_projectile[ju] = 32;
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part63.zig
// ---------------------------------------------------------------------------
/// The C widens these overlord bytes to 16 bits, so the adds carry into the
/// following byte: overlord_gen1 is at 0xb28 and overlord_gen2 at 0xb30.

pub export fn HelmasaurKing_SwingTail(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.overlord_x_lo[4] +%= 1;
    a.HelmasaurKing_Reinitialize(k);
    const mask: u8 = if (v.sprite_anim_clock[i] != 0) 0 else 1;
    if (v.frame_counter.* & mask == 0) {
        const j: usize = v.sprite_D[i] & 1;
        v.overlord_gen2[0] +%= if (j != 0) 0 -% @as(u8, 1) else 1;
        if (v.overlord_gen2[0] == @as(u8, @bitCast(t.kFluteBoyAnimal_Xvel[j])))
            v.sprite_D[i] +%= 1;
        overlord_gen1_w5.* +%= s16(@bitCast(v.overlord_gen2[0]));
    }
    if (v.sprite_anim_clock[i] == 0)
        return;
    if (v.overlord_gen2[0] == 0)
        a.SpriteSfx_QueueSfx3WithPan(k, 0x6);

    if (v.sprite_anim_clock[i] == 2) {
        const j: u8 = v.sprite_head_dir[i];
        overlord_gen2_w1.* +%= if (j != 0) 0 -% @as(u16, 4) else 4;
        if (v.overlord_gen2[1] == (if (j != 0) cm.byte(-124) else @as(u8, 124)))
            v.sprite_anim_clock[i] = 3;
        v.overlord_gen1[7] +%= 3;
    } else if (v.sprite_anim_clock[i] == 3) {
        const j: u8 = v.sprite_head_dir[i] ^ 1;
        overlord_gen2_w1.* +%= if (j != 0) 0 -% @as(u16, 4) else 4;
        if (v.overlord_gen2[1] == 0)
            v.sprite_anim_clock[i] = 0;
        v.overlord_gen1[7] -%= 3;
    } else {
        if ((v.overlord_gen2[0] | v.sprite_delay_aux3[i]) == 0) {
            v.sprite_head_dir[i] = v.overlord_gen1[6] & 1;
            const dir: u8 = a.Sprite_IsRightOfLink(k).a ^ 1;
            if (dir == v.sprite_head_dir[i]) {
                v.sprite_anim_clock[i] = 2;
                v.sound_effect_2.* = a.Sprite_CalculateSfxPan(k) | 0x26;
            }
        }
    }
}

pub export fn HelmasaurKing_CheckMaskDamageFromHammer(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_C[i] >= 3 or v.link_item_in_hand.* & 10 == 0 or v.player_oam_y_offset.* == 0x80)
        return;
    var hb: SpriteHitBox = undefined;
    a.Player_SetupActionHitBox(&hb);
    const bak = v.sprite_y_lo[i];
    v.sprite_y_lo[i] +%= 8;
    a.Sprite_SetupHitBox(k, &hb);
    v.sprite_y_lo[i] = bak;
    if (a.CheckIfHitBoxesOverlap(&hb)) {
        v.sprite_health[i] -%= 1;
        v.sound_effect_2.* = 0x21;
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 0x30);
        v.link_actual_vel_y.* = pt.y;
        v.link_actual_vel_x.* = pt.x;
        v.link_incapacitated_timer.* = 8;
        if (v.repulsespark_timer.* == 0) {
            v.repulsespark_x_lo.* = pt.y;
            v.repulsespark_y_lo.* = pt.x;
            v.repulsespark_timer.* = 5;
        }
        a.SpriteSfx_QueueSfx2WithPan(k, 0x5);
    }
}

pub export fn HelmasaurKing_SpawnMaskDebris(k: c_int) callconv(.c) void {
    var info: SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x92, &info);
    if (j >= 0) {
        const ju = ix(j);
        const n: usize = v.tmp_counter.*;
        a.Sprite_SetX(j, info.r0_x +% s16(t.kHelmasaurKing_Mask_X[n]));
        a.Sprite_SetY(j, info.r2_y +% s16(t.kHelmasaurKing_Mask_Y[n]));
        v.sprite_z[ju] = @bitCast(t.kHelmasaurKing_Mask_Z[n]);
        v.sprite_x_vel[ju] = @bitCast(t.kHelmasaurKing_Mask_Xvel[n]);
        v.sprite_y_vel[ju] = @bitCast(t.kHelmasaurKing_Mask_Yvel[n]);
        v.sprite_z_vel[ju] = @bitCast(t.kHelmasaurKing_Mask_Zvel[n]);
        v.sprite_oam_flags[ju] = t.kHelmasaurKing_Mask_OamFlags[n] | 13;
        v.sprite_graphics[ju] = t.kHelmasaurKing_Mask_Gfx[n];
        v.sprite_C[ju] = 128;
        v.sprite_flags2[ju] = 0;
        v.sprite_delay_aux1[ju] = 12;
        v.sprite_ignore_projectile[ju] = 12;
        v.sprite_subtype[ju] = v.tmp_counter.*;
    }
}

pub export fn HelmasaurKing_Draw(k: c_int) callconv(.c) void {
    v.oam_cur_ptr.* = 0x89c;
    v.oam_ext_cur_ptr.* = 0xa47;
    var info: PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    a.KingHelmasaur_OperateTail(k, &info);
    SpriteDraw_KingHelmasaur_Eyes(k, &info);
    a.KingHelmasaurMask(k, &info);
    a.SpriteDraw_KingHelmasaur_Body(k, &info);
    a.SpriteDraw_KingHelmasaur_Legs(k, &info);
    a.SpriteDraw_KingHelmasaur_Mouth(k, &info);
}

pub export fn SpriteDraw_KingHelmasaur_Eyes(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    v.oam_cur_ptr.* +%= 0x40;
    v.oam_ext_cur_ptr.* +%= 0x10;
    var oam = oamPtr();
    var n: c_int = 1;
    while (n >= 0) : ({
        n -= 1;
        oam += 1;
    }) {
        const e = ix(n);
        const j: usize = v.overlord_x_lo[4] >> 2 & 7;
        setOamPlain(
            oam,
            @truncate(info.x +% s16(t.kHelmasaurKing_DrawB_X[e])),
            @truncate(info.y +% 0x14),
            t.kHelmasaurKing_DrawB_Char[j],
            t.kHelmasaurKing_DrawB_Flags[e],
            0,
        );
    }
    if (v.submodule_index.* != 0)
        a.Sprite_CorrectOamEntries(k, 1, 0);
}

// ---------------------------------------------------------------------------
// from sprite_main_part64.zig
// ---------------------------------------------------------------------------
// HelmasaurSin is `static` in the C, so it is absent from the ABI header and
// has to come from the module that ported it.

/// The C widens these overlord bytes to 16 bits; overlord_gen1 is at 0xb28 and
/// overlord_gen2 at 0xb30.

pub export fn KingHelmasaurMask(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    v.oam_cur_ptr.* +%= 8;
    v.oam_ext_cur_ptr.* +%= 2;
    if (v.sprite_C[i] >= 3)
        return;
    a.Sprite_DrawMultiple(k, &t.kHelmasaurKing_DrawC_Dmd[@as(usize, v.sprite_C[i]) * 8], 8, info);
    v.oam_cur_ptr.* +%= 0x20;
    v.oam_ext_cur_ptr.* +%= 8;
    if (v.sprite_delay_aux4[i] != 0)
        return;
    var n: c_int = 1;
    while (n >= 0) : (n -= 1) {
        const j = ix(n);
        if (v.ancilla_type[j] == 7 and (v.ancilla_x_vel[j] | v.ancilla_y_vel[j]) != 0)
            a.KingHelmasaur_CheckBombDamage(k, n);
    }
}

pub export fn KingHelmasaur_CheckBombDamage(k: c_int, j: c_int) callconv(.c) void {
    const i = ix(k);
    const ji = ix(j);
    var hb: SpriteHitBox = undefined;
    a.Sprite_SetupHitBox(k, &hb);
    const x: u16 = ((@as(u16, v.ancilla_x_hi[ji]) << 8) | v.ancilla_x_lo[ji]) -% 6;
    const y: u16 = ((@as(u16, v.ancilla_y_hi[ji]) << 8) | v.ancilla_y_lo[ji]) -% v.ancilla_z[ji];
    hb.r0_xlo = @truncate(x);
    hb.r8_xhi = @truncate(x >> 8);
    hb.r1_ylo = @truncate(y);
    hb.r9_yhi = @truncate(y >> 8);
    hb.r2 = 2;
    hb.r3 = 15;
    if (a.CheckIfHitBoxesOverlap(&hb)) {
        v.ancilla_x_vel[ji] = 0 -% v.ancilla_x_vel[ji];
        v.ancilla_y_vel[ji] = @bitCast(@as(i8, @bitCast(0 -% v.ancilla_y_vel[ji])) >> 1);
        v.sprite_delay_aux4[i] = 32;
        v.repulsespark_timer.* = 5;
        v.repulsespark_x_lo.* = v.ancilla_x_lo[ji];
        v.repulsespark_y_lo.* = v.ancilla_y_lo[ji] -% v.ancilla_z[ji];
        v.sound_effect_1.* = 5;
    }
}

pub export fn SpriteDraw_KingHelmasaur_Body(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    a.Sprite_DrawMultiple(k, &t.kHelmasaurKing_DrawD_Dmd[0], 19, info);
}

pub export fn SpriteDraw_KingHelmasaur_Legs(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    v.oam_cur_ptr.* +%= 19 * 4;
    v.oam_ext_cur_ptr.* +%= 19;
    var oam = oamPtr();
    var n: c_int = 3;
    while (n >= 0) : ({
        n -= 1;
        oam += 2;
    }) {
        const e = ix(n);
        const x: u8 = @as(u8, @truncate(info.x)) +% @as(u8, @bitCast(t.kHelmasaurKing_DrawE_X[e]));
        const y: u8 = @as(u8, @truncate(info.y)) +% @as(u8, @bitCast(t.kHelmasaurKing_DrawE_Y[e])) +%
            v.overlord_x_lo[e];
        const f: u8 = t.kHelmasaurKing_DrawE_Flags[e] ^ info.flags;
        setOamPlain(oam + 0, x, y, t.kHelmasaurKing_DrawE_Char[e], f, 2);
        setOamPlain(oam + 1, x, y +% 16, t.kHelmasaurKing_DrawE_Char[e] +% 2, f, 2);
    }
    v.tmp_counter.* = 0xff;
    if (v.submodule_index.* != 0) {
        a.Sprite_CorrectOamEntries(k, 7, 2);
        _ = a.Sprite_PrepOamCoordOrDoubleRet(k, info);
    }
}

pub export fn SpriteDraw_KingHelmasaur_Mouth(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_delay_aux2[i] == 0)
        return;
    const yd: u8 = t.kHelmasaurKing_DrawF_Y[v.sprite_delay_aux2[i] >> 2];
    _ = a.Oam_AllocateFromRegionB(4);
    const oam = oamPtr();
    setOamPlain(oam, @truncate(info.x), @as(u8, @truncate(info.y)) +% yd +% 0x13, 0xaa, info.flags ^ 0xb, 2);
}

pub export fn KingHelmasaur_OperateTail(k: c_int, info: *PrepOamCoordsRet) callconv(.c) void {
    const i = ix(k);
    var n: usize = 0;
    while (n < 16) : (n += 1) {
        const j: usize = n + @as(usize, if (v.sprite_anim_clock[i] != 0) 16 else 0);
        const rs: u16 = overlord_gen1_w5.* +% overlord_gen2_w1.*;
        const f: u8 = @as(u8, @truncate(rs >> 8)) -% 1;
        const mag: u8 = @truncate(if (sign8(f)) 0 -% rs else rs);
        const r6: u8 = @truncate((@as(u16, mag) *% @as(u16, t.kHelmasaurKing_DrawA_Mult[j])) >> 8);
        const angle: u16 = (rs & 0xff00) | (if (sign8(f)) r6 ^ 0xff else r6);
        const r15: u8 = @truncate((@as(u16, v.overlord_gen1[7]) *% @as(u16, t.kHelmasaurKing_DrawA_MultB[n])) >> 8);
        v.overlord_x_lo[n + 5] = @bitCast(HelmasaurSin(angle, r15));
        v.overlord_y_lo[n + 5] = @as(u8, @bitCast(HelmasaurSin(angle +% 0x80, r15))) -% 40;
    }

    var oam = oamPtr();
    var is_hit = false;
    var m: usize = v.overlord_gen2[3];
    while (m != 16) : ({
        m += 1;
        oam += 1;
    }) {
        const x: u8 = v.overlord_x_lo[m + 5] +% @as(u8, @truncate(info.x));
        const y: u8 = v.overlord_y_lo[m + 5] +% @as(u8, @truncate(info.y));
        oam[0].x = x;
        oam[0].y = y;
        oam[0].charnum = if (m == v.overlord_gen2[3]) 0xe4 else 0xac;
        oam[0].flags = info.flags ^ 0x1b;

        if (v.countdown_for_blink.* == 0 and v.sprite_anim_clock[i] != 0) {
            const dx: u8 = @truncate(v.link_x_coord.* -% v.BG2HOFS_copy2.* -% x +% 12);
            const dy: u8 = @truncate(v.link_y_coord.* -% v.BG2VOFS_copy2.* +% 8 -% y +% 8);
            if (dx < 24 and dy < 16) {
                is_hit = true;
                v.link_actual_vel_x.* = 0;
                v.link_actual_vel_y.* = 56;
            }
        }
    }

    if (is_hit and v.flag_block_link_menu.* == 0)
        a.Sprite_AttemptDamageToLinkPlusRecoil(k);
    a.Sprite_CorrectOamEntries(k, 16, 2);
    _ = a.Sprite_PrepOamCoordOrDoubleRet(k, info);
    v.tmp_counter.* = 16;
}

pub export fn Sprite_MadBatterBolt(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_subtype2[i] & 16 != 0)
        _ = a.Oam_AllocateFromRegionB(4);
    a.SpriteDraw_SingleSmall(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_ai_state[i] == 0) {
        a.Sprite_MoveXY(k);
        if (v.sprite_delay_main[i] == 0)
            v.sprite_ai_state[i] = 1;
    } else {
        v.sprite_ai_state[i] +%= 1;
        if (v.sprite_ai_state[i] == 0)
            v.sprite_state[i] = 0;
        v.sprite_subtype2[i] +%= 1;
        const j = v.sprite_subtype2[i];
        if (j & 7 == 0)
            v.sound_effect_2.* = 48;
        a.Sprite_SetX(k, v.link_x_coord.* +% s16(t.kMadderBolt_X[j >> 2 & 7]));
        a.Sprite_SetY(k, v.link_y_coord.* +% s16(t.kMadderBolt_Y[j >> 4 & 7]));
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part65.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_AA_Pikit(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Pikit_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // set next vel
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_C[i] +%= 1;
                const j: usize = if (v.sprite_C[i] == 4) blk: {
                    v.sprite_C[i] = 0;
                    break :blk a.Sprite_DirectionToFaceLink(k, null);
                } else a.GetRandomNumber() & 3;
                v.sprite_x_vel[i] = @bitCast(t.kFluteBoyAnimal_Xvel[j]);
                v.sprite_y_vel[i] = @bitCast(t.kZazak_Yvel[j]);
                v.sprite_z_vel[i] = (a.GetRandomNumber() & 7) +% 19;
            }
            v.sprite_subtype2[i] +%= 1;
            v.sprite_graphics[i] = v.sprite_subtype2[i] >> 3 & 1;
        },
        1 => { // finish jump then attack
            a.Sprite_MoveXYZ(k);
            _ = a.Sprite_CheckTileCollision(k);
            v.sprite_z_vel[i] -%= 1;
            v.sprite_z_vel[i] -%= 1;
            if (sign8(v.sprite_z[i])) {
                v.sprite_z[i] = 0;
                v.sprite_z_vel[i] = 0;
                var pt: PointU8 = undefined;
                _ = a.Sprite_DirectionToFaceLink(k, &pt);
                if (pt.x +% 48 < 96 and pt.y +% 48 < 96) {
                    v.sprite_ai_state[i] +%= 1;
                    const pp = a.Sprite_ProjectSpeedTowardsLink(k, 31);
                    v.sprite_D[i] = a.Sprite_ConvertVelocityToAngle(pp.x, pp.y) >> 1;
                    v.sprite_delay_main[i] = 95;
                    return;
                }
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 16;
            }
            v.sprite_subtype2[i] +%= 1;
            v.sprite_graphics[i] = v.sprite_subtype2[i] >> 3 & 1;
        },
        2 => { // attempt item grab
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 16;
                v.sprite_A[i] = 0;
                v.sprite_B[i] = 0;
                v.sprite_G[i] = 0;
                return;
            }
            const f: usize = v.sprite_delay_main[i] >> 2;
            v.sprite_graphics[i] = t.kPikit_Gfx[f];
            const xo: i8 = t.kPikit_XyOffs[f + t.kPikit_Tab0[v.sprite_D[i]]];
            const yo: i8 = t.kPikit_XyOffs[f + t.kPikit_Tab1[v.sprite_D[i]]];
            v.sprite_A[i] = @bitCast(xo);
            v.sprite_B[i] = @bitCast(yo);
            if (v.sprite_G[i] == 0 and
                v.cur_sprite_x.* +% s16(xo) -% v.link_x_coord.* +% 12 < 24 and
                v.cur_sprite_y.* +% s16(yo) -% v.link_y_coord.* +% 12 < 32 and
                v.sprite_delay_main[i] < 46)
            {
                v.sound_effect_1.* = a.Link_CalculateSfxPan() | 0x26;
                const j: u8 = (a.GetRandomNumber() & 3) +% 1;
                v.sprite_G[i] = j;
                v.sprite_E[i] = j;
                if (j == 1) {
                    if (v.link_item_bombs.* != 0)
                        v.link_item_bombs.* -%= 1
                    else
                        v.sprite_G[i] = 0;
                } else if (j == 2) {
                    if (v.link_num_arrows.* != 0)
                        v.link_num_arrows.* -%= 1
                    else
                        v.sprite_G[i] = 0;
                } else if (j == 3) {
                    if (v.link_rupees_goal.* != 0)
                        v.link_rupees_goal.* -%= 1
                    else
                        v.sprite_G[i] = 0;
                } else {
                    v.sprite_subtype[i] = v.link_shield_type.*;
                    if (v.link_shield_type.* != 0 and v.link_shield_type.* != 3)
                        v.link_shield_type.* = 0
                    else
                        v.sprite_G[i] = 0;
                }
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part66.zig
// ---------------------------------------------------------------------------
/// The `set_dir` label, which cases 0 and 2 reach with a goto into case 1.

pub export fn Sprite_A8_GreenZirro(k: c_int) callconv(.c) void {
    const i = ix(k);

    v.sprite_obj_prio[i] = 0x30;
    if (v.sprite_A[i] != 0) {
        switch (v.sprite_ai_state[i]) {
            0 => { // bomberpellet falling
                a.SpriteDraw_SingleSmall(k);
                if (a.Sprite_ReturnIfInactive(k)) return;
                a.Sprite_MoveXY(k);
                a.Sprite_MoveZ(k);
                v.sprite_z_vel[i] -%= 2;
                if (sign8(v.sprite_z[i])) {
                    v.sprite_z[i] = 0;
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_delay_main[i] = 19;
                    v.sprite_flags2[i] +%= 1;
                    a.SpriteSfx_QueueSfx2WithPan(k, 0xc);
                }
            },
            1 => { // bomberpellet exploding
                a.SpriteDraw_ZirroBomb(k);
                if (a.Sprite_ReturnIfInactive(k)) return;
                if (v.frame_counter.* & 3 == 0)
                    v.sprite_delay_main[i] +%= 1;
                _ = a.Sprite_CheckDamageToLink(k);
            },
            else => {},
        }
        return;
    }

    if (v.sprite_delay_aux1[i] != 0)
        v.sprite_graphics[i] = t.kBomber_Gfx[v.sprite_D[i]];
    v.sprite_obj_prio[i] |= 0x30;
    a.Bomber_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    if (v.sprite_delay_aux1[i] == 8)
        a.Zirro_DropBomb(k);
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.frame_counter.* & 1 == 0) {
        const j: usize = v.sprite_G[i] & 1;
        v.sprite_z_vel[i] +%= if (j != 0) 0 -% @as(u8, 1) else 1;
        if (v.sprite_z_vel[i] == (if (j != 0) cm.byte(-8) else @as(u8, 8)))
            v.sprite_G[i] +%= 1;
    }
    a.Sprite_MoveZ(k);
    var pt: PointU8 = undefined;
    _ = a.Sprite_DirectionToFaceLink(k, &pt);
    if (pt.x +% 40 < 80 and pt.y +% 40 < 80 and v.player_oam_y_offset.* != 0x80 and
        (v.link_is_running.* != 0 or sign8(v.button_b_frames.* -% 9)))
    {
        const pp = a.Sprite_ProjectSpeedTowardsLink(k, 0x30);
        v.sprite_x_vel[i] = 0 -% pp.x;
        v.sprite_y_vel[i] = 0 -% pp.y;
        v.sprite_delay_main[i] = 8;
        v.sprite_ai_state[i] = 2;
    }
    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_B[i] +%= 1;
                var j: usize = undefined;
                if (v.sprite_B[i] == 3) {
                    v.sprite_B[i] = 0;
                    v.sprite_delay_main[i] = 48;
                    j = t.kBomber_Tab0[a.Sprite_DirectionToFaceLink(k, null)];
                } else {
                    const r = a.GetRandomNumber();
                    v.sprite_delay_main[i] = r & 0x1f | 0x20;
                    j = r & 7;
                }
                v.sprite_x_vel[i] = @bitCast(t.kBomber_Xvel[j]);
                v.sprite_y_vel[i] = @bitCast(t.kBomber_Yvel[j]);
            }
            zirroSetDir(k);
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = 10;
                if (v.sprite_type[i] == 0xa8)
                    v.sprite_delay_aux1[i] = 16;
            } else {
                a.Sprite_MoveXY(k);
                zirroSetDir(k);
            }
        },
        2 => {
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] = 0;
            v.sprite_subtype2[i] +%= 2;
            a.Sprite_MoveXY(k);
            zirroSetDir(k);
        },
        else => {},
    }
}

pub export fn Stalfos_Skellington(k: c_int) callconv(.c) void {
    const i = ix(k);

    // The C uses two labels here: one to force the leap, one to skip past it.
    check: {
        if (v.sprite_state[i] == 9 and
            v.link_x_coord.* -% v.cur_sprite_x.* +% 40 < 80 and
            v.link_y_coord.* -% v.cur_sprite_y.* +% 48 < 80 and
            v.player_oam_y_offset.* != 0x80 and
            (v.sprite_z[i] | v.sprite_pause[i]) == 0 and
            v.sprite_floor[i] == v.link_is_on_lower_level.*)
        {
            const dir = a.Sprite_DirectionToFaceLink(k, null);
            var forced = false;
            if (v.link_is_running.* == 0) {
                if (v.button_b_frames.* >= 0x90) {
                    forced = true;
                } else if (!sign8(v.button_b_frames.* -% 9)) {
                    break :check;
                }
            }
            if (forced or dir != t.kStalfos_CheckDir[v.link_direction_facing.* >> 1]) {
                v.sprite_D[i] = dir;
                const pt = a.Sprite_ProjectSpeedTowardsLink(k, 32);
                v.sprite_x_vel[i] = 0 -% pt.x;
                v.sprite_y_vel[i] = 0 -% pt.y;
                v.sprite_z_vel[i] = 32;
                a.SpriteSfx_QueueSfx3WithPan(k, 0x13);
                v.sprite_z[i] +%= 1;
            }
        }
    }

    if (v.sprite_z[i] == 0) {
        a.Sprite_Zazak_Main(k);
        return;
    }
    v.sprite_graphics[i] = t.kStalfos_AnimState2[v.sprite_D[i]];
    a.Stalfos_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_F[i] != 0)
        v.sprite_z_vel[i] = 0;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    const coll = a.Sprite_CheckTileCollision(k);
    if (coll & 3 != 0)
        v.sprite_x_vel[i] = 0;
    if (coll & 12 != 0)
        v.sprite_y_vel[i] = 0;
    a.Sprite_MoveXYZ(k);
    v.sprite_z_vel[i] -%= 2;
    if (sign8(v.sprite_z[i] -% 1)) {
        v.sprite_z[i] = 0;
        a.Sprite_ZeroVelocity_XY(k);
        a.SpriteSfx_QueueSfx2WithPan(k, 0x21);
        if (v.sprite_subtype[i] != 0) {
            v.sprite_delay_aux3[i] = 16;
            v.sprite_subtype2[i] = 0;
        }
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part67.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_Zazak_Main(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.sprite_B[i] != 0) {
        a.FirePhlegm_Draw(k);
        if (a.Sprite_ReturnIfInactive(k)) return;
        v.sprite_graphics[i] = v.frame_counter.* >> 1 & 1;
        _ = a.Sprite_CheckDamageToLink(k);
        a.Sprite_MoveXY(k);
        if (a.Sprite_CheckTileCollision(k) != 0) {
            v.sprite_state[i] = 0;
            a.Sprite_PlaceRupulseSpark_2(k);
        }
        return;
    }

    const aux3 = v.sprite_delay_aux3[i];
    if (aux3 != 0) {
        v.sprite_ai_state[i] = 0;
        v.sprite_delay_main[i] = 32;
        a.Sprite_ZeroVelocity_XY(k);
        v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null);
    }
    if (aux3 == 1) {
        a.Stalfos_ThrowBone(k);
        v.sprite_subtype2[i] = 1;
    }
    v.sprite_graphics[i] = t.kStalfos_AnimState1[@as(usize, v.sprite_subtype2[i] & 1) * 4 + @as(usize, v.sprite_D[i])];
    if (v.sprite_type[i] == 0xa7)
        a.Stalfos_Draw(k)
    else
        a.Zazak_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckTileCollision(k);

    switch (v.sprite_ai_state[i]) {
        0 => { // walk then track head
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = t.kStalfos_Delay[a.GetRandomNumber() & 3];
                v.sprite_ai_state[i] = 1;
                const j: usize = v.sprite_head_dir[i];
                v.sprite_D[i] = @truncate(j);
                v.sprite_x_vel[i] = @bitCast(t.kFluteBoyAnimal_Xvel[j]);
                v.sprite_y_vel[i] = @bitCast(t.kZazak_Yvel[j]);
            }
        },
        1 => { // halt and change dir
            if (v.sprite_wallcoll[i] != 0) {
                v.sprite_delay_main[i] = 16;
            } else {
                if (v.sprite_delay_main[i] != 0) {
                    v.sprite_G[i] -%= 1;
                    if (sign8(v.sprite_G[i])) {
                        v.sprite_G[i] = 11;
                        v.sprite_subtype2[i] +%= 1;
                    }
                    return;
                } else if (v.sprite_type[i] == 0xa6 and
                    v.sprite_D[i] == a.Sprite_DirectionToFaceLink(k, null) and
                    v.sprite_floor[i] == v.link_is_on_lower_level.*)
                {
                    v.sprite_ai_state[i] = 2;
                    v.sprite_delay_main[i] = 48;
                    v.sprite_delay_aux1[i] = 48;
                    v.sprite_y_vel[i] = 0;
                    v.sprite_x_vel[i] = 0;
                    return;
                }
                v.sprite_delay_main[i] = 32;
            }
            v.sprite_head_dir[i] = t.kZazak_Dir2[@as(usize, v.sprite_D[i]) * 2 + @as(usize, a.GetRandomNumber() & 1)];
            v.sprite_ai_state[i] = 0;
            v.sprite_C[i] +%= 1;
            if (v.sprite_C[i] == 4) {
                v.sprite_C[i] = 0;
                v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null);
                v.sprite_delay_main[i] = 24;
            }
            v.sprite_y_vel[i] = 0;
            v.sprite_x_vel[i] = 0;
        },
        2 => { // shoot
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] = 0
            else if (v.sprite_delay_main[i] == 24)
                _ = a.Sprite_SpawnFirePhlegm(k);
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part68.zig
// ---------------------------------------------------------------------------
/// The `check_coll` label, which case 1 reaches with a goto into case 0.

pub export fn Sprite_A2_Kholdstare(k: c_int) callconv(.c) void {
    const i = ix(k);

    a.Kholdstare_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_ai_state[i] < 2) {
        a.Kholdstare_SpawnPuffCloudGarnish(k);
        if (v.frame_counter.* & 7 == 0)
            v.sound_effect_1.* = 2;
    }
    if (a.Sprite_ReturnIfRecoiling(k)) return;

    v.sprite_subtype2[i] -%= 1;
    if (sign8(v.sprite_subtype2[i])) {
        v.sprite_subtype2[i] = 10;
        v.sprite_graphics[i] = v.sprite_graphics[i] +% 1 & 3;
    }

    if (v.frame_counter.* & 3 == 0) {
        const pt = a.Sprite_ProjectSpeedTowardsLink(k, 31);
        v.sprite_A[i] = a.Sprite_ConvertVelocityToAngle(pt.x, pt.y);
    }

    a.Sprite_MoveXY(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // Accelerate
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 32;
                return;
            }
            const dx: u8 = v.sprite_x_vel[i] -% v.sprite_z_vel[i];
            if (dx != 0)
                v.sprite_x_vel[i] +%= if (sign8(dx)) 1 else 0 -% @as(u8, 1);
            const dy: u8 = v.sprite_y_vel[i] -% v.sprite_z_subpos[i];
            if (dy != 0)
                v.sprite_y_vel[i] +%= if (sign8(dy)) 1 else 0 -% @as(u8, 1);
            kholdstareCheckColl(k);
        },
        1 => { // Decelerate
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 96;
                const r = a.GetRandomNumber();
                if (r & 0x1c == 0) {
                    const pt = a.Sprite_ProjectSpeedTowardsLink(k, 24);
                    v.sprite_z_vel[i] = pt.x;
                    v.sprite_z_subpos[i] = pt.y;
                } else {
                    v.sprite_z_vel[i] = @bitCast(t.kKholdstare_Target_Xvel[r & 3]);
                    v.sprite_z_subpos[i] = @bitCast(t.kKholdstare_Target_Yvel[r & 3]);
                }
            } else {
                if (v.sprite_x_vel[i] != 0)
                    v.sprite_x_vel[i] +%= if (sign8(v.sprite_x_vel[i])) 1 else 0 -% @as(u8, 1);
                if (v.sprite_y_vel[i] != 0)
                    v.sprite_y_vel[i] +%= if (sign8(v.sprite_y_vel[i])) 1 else 0 -% @as(u8, 1);
                kholdstareCheckColl(k);
            }
        },
        2 => { // Triplicate
            if (v.sprite_delay_main[i] == 1) {
                v.sprite_state[i] = 0;
                v.sprite_state[i + 1] = 0;
                v.sprite_state[i + 2] = 0;
                var n: c_int = 2;
                while (n >= 0) : (n -= 1) {
                    const e = ix(n);
                    var info: SpriteSpawnInfo = undefined;
                    const j = a.Sprite_SpawnDynamicallyEx(k, 0xa2, &info, 4);
                    if (j >= 0) {
                        const ju = ix(j);
                        a.Sprite_SetSpawnedCoordinates(j, &info);
                        v.sprite_z_vel[ju] = @bitCast(t.kKholdstare_Triplicate_Tab0[e]);
                        v.sprite_z_subpos[ju] = @bitCast(t.kKholdstare_Triplicate_Tab1[e]);
                        v.sprite_delay_main[ju] = 32;
                    }
                }
                v.tmp_counter.* = 0xff;
            } else {
                v.sprite_hit_timer[i] |= 0xe0;
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part69.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_A1_Freezor(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Freezor_Draw(k);
    if (v.sprite_state[i] != 9) {
        v.sprite_ai_state[i] = 3;
        v.sprite_delay_main[i] = 31;
        v.sprite_ignore_projectile[i] = 31;
        v.sprite_state[i] = 9;
        v.sprite_hit_timer[i] = 0;
    }
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.sprite_ai_state[i] != 3) {
        if (a.Sprite_ReturnIfRecoiling(k)) return;
    }
    switch (v.sprite_ai_state[i]) {
        0 => { // stasis
            v.sprite_ignore_projectile[i] +%= 1;
            if (a.Sprite_IsRightOfLink(k).b +% 16 < 32) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 32;
            }
        },
        1 => { // awakening
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                const x: u16 = a.Sprite_GetX(k) -% 5;
                const y: u16 = a.Sprite_GetY(k);
                a.Dungeon_UpdateTileMapWithCommonTile(x, y, 8);
                v.sprite_delay_aux1[i] = 96;
                v.sprite_D[i] = 2;
                v.sprite_delay_main[i] = 80;
            } else {
                v.sprite_x_vel[i] = if (v.sprite_delay_main[i] & 1 != 0) cm.byte(-16) else 16;
                a.Sprite_MoveX(k);
            }
        },
        2 => { // moving
            _ = a.Sprite_CheckDamageToLink(k);
            if (a.Sprite_CheckDamageFromLink(k) != 0)
                v.sprite_hit_timer[i] = 0;
            if (v.sprite_delay_aux1[i] != 0 and (k ^ @as(c_int, v.frame_counter.*)) & 7 == 0) {
                _ = a.Sprite_GarnishSpawn_Sparkle(
                    k,
                    s16(t.kFreezor_Sparkle_X[a.GetRandomNumber() & 7]),
                    s16(-4),
                );
            }
            if (v.sprite_delay_main[i] == 0)
                v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
            const j: usize = v.sprite_D[i];
            v.sprite_x_vel[i] = @bitCast(t.kFreezor_Xvel[j]);
            v.sprite_y_vel[i] = @bitCast(t.kFreezor_Yvel[j]);
            if (v.sprite_wallcoll[i] & 15 == 0)
                a.Sprite_MoveXY(k);
            _ = a.Sprite_CheckTileCollision(k);
            const g: usize = @intCast((k ^ @as(c_int, v.frame_counter.*)) >> 2 & 3);
            v.sprite_graphics[i] = t.kFreezor_Moving_Gfx[g];
        },
        3 => { // melting
            if (v.sprite_delay_main[i] == 0) {
                a.Sprite_ManuallySetDeathFlagUW(k);
                v.sprite_state[i] = 0;
            }
            v.sprite_graphics[i] = t.kFreezor_Melting_Gfx[v.sprite_delay_main[i] >> 3];
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part70.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_99_Pengator(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_graphics[i] = v.sprite_A[i] +% t.kPengator_Gfx[v.sprite_D[i]];
    Pengator_Draw(k);
    if (v.sprite_F[i] != 0 or v.sprite_wallcoll[i] & 15 != 0) {
        v.sprite_ai_state[i] = 0;
        v.sprite_x_vel[i] = 0;
        v.sprite_y_vel[i] = 0;
    }
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    a.Sprite_MoveXYZ(k);
    v.sprite_z_vel[i] -%= 2;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z_vel[i] = 0;
        v.sprite_z[i] = 0;
    }
    _ = a.Sprite_CheckTileCollision(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // face player
            v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
            v.sprite_ai_state[i] = 1;
        },
        1 => { // speedup
            if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0) {
                var moved = false;
                const j: usize = v.sprite_D[i];
                if (v.sprite_x_vel[i] != @as(u8, @bitCast(t.kFluteBoyAnimal_Xvel[j]))) {
                    v.sprite_x_vel[i] +%= @bitCast(t.kPengator_XYVel[j]);
                    moved = true;
                }
                if (v.sprite_y_vel[i] != @as(u8, @bitCast(t.kZazak_Yvel[j]))) {
                    v.sprite_y_vel[i] +%= @bitCast(t.kPengator_XYVel[j + 2]);
                    moved = true;
                }
                if (!moved) {
                    v.sprite_delay_main[i] = 15;
                    v.sprite_ai_state[i] = 2;
                }
            }
            v.sprite_A[i] = (v.frame_counter.* & 4) >> 2;
        },
        2 => { // jump
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] +%= 1
            else if (v.sprite_delay_main[i] == 5)
                v.sprite_z_vel[i] = 24;
            v.sprite_A[i] = t.kPengator_Jump[v.sprite_delay_main[i] >> 2];
        },
        3 => { // slide and sparkle
            if (((k ^ @as(c_int, v.frame_counter.*)) & 7 | @as(c_int, v.sprite_z[i])) == 0) {
                const d: usize = v.sprite_D[i];
                const half: usize = if (d >= 2) 4 else 0;
                const x = t.kPengator_Garnish_X[@as(usize, a.GetRandomNumber() & 3) + half];
                const y = t.kPengator_Garnish_Y[@as(usize, a.GetRandomNumber() & 3) + half];
                a.Sprite_GarnishSpawn_Sparkle_limited(k, s16(x), s16(y));
            }
        },
        else => {},
    }
}

pub export fn Pengator_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    a.Sprite_DrawMultiple(k, &t.kPengator_Dmd0[@as(usize, v.sprite_graphics[i]) * 2], 2, &info);
    // The C selects the overlay with comma expressions inside the || chain.
    var sel: usize = 0;
    var overlay = v.sprite_graphics[i] == 14;
    if (!overlay) {
        sel = 1;
        overlay = v.sprite_graphics[i] == 19;
    }
    if (overlay) {
        v.oam_cur_ptr.* +%= 8;
        v.oam_ext_cur_ptr.* +%= 2;
        a.Sprite_DrawMultiple(k, &t.kPengator_Dmd1[sel * 2], 2, &info);
    }
    a.SpriteDraw_Shadow(k, &info);
}

// ---------------------------------------------------------------------------
// from sprite_main_part71.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_94_Pirogusu(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.sprite_E[i] != 0) {
        a.Sprite_94_Tile(k);
        return;
    }
    v.sprite_obj_prio[i] |= 0x30;
    a.Pirogusu_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    switch (v.sprite_ai_state[i]) {
        0 => { // wriggle in hole
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 31;
            }
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            v.sprite_A[i] = t.kPirogusu_A0[v.sprite_D[i]];
        },
        1 => { // emerge
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 32;
                v.sprite_ignore_projectile[i] = 0;
                a.Sprite_ZeroVelocity_XY(k);
            } else {
                v.sprite_A[i] = t.kPirogusu_A1[@as(usize, v.sprite_delay_main[i] >> 3 & 1) |
                    (@as(usize, v.sprite_D[i]) << 1)];
                const j: usize = v.sprite_D[i];
                v.sprite_x_vel[i] = @bitCast(t.kPirogusu_XYvel[j + 2]);
                v.sprite_y_vel[i] = @bitCast(t.kPirogusu_XYvel[j]);
                a.Sprite_MoveXY(k);
            }
        },
        2 => { // splash into play
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            a.Sprite_MoveXY(k);
            const j: usize = v.sprite_D[i];
            v.sprite_x_vel[i] +%= @bitCast(t.kPirogusu_XYvel2[j]);
            v.sprite_y_vel[i] +%= @bitCast(t.kPirogusu_XYvel2[j + 2]);
            if (v.sprite_delay_main[i] == 0) {
                _ = a.Sprite_SpawnSmallSplash(k);
                v.sprite_delay_aux1[i] = 16;
                v.sprite_ai_state[i] = 3;
            }
            v.sprite_A[i] = t.kPirogusu_A2[@as(usize, v.frame_counter.* >> 2 & 1) |
                (@as(usize, v.sprite_D[i]) << 1)];
        },
        3 => { // swim
            if (a.Sprite_ReturnIfRecoiling(k)) return;
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            v.sprite_A[i] = t.kPirogusu_A2[@as(usize, v.frame_counter.* >> 2 & 1) |
                (@as(usize, v.sprite_D[i]) << 1)] +% 8;
            if (v.sprite_delay_aux1[i] == 0) {
                a.Pirogusu_SpawnSplash(k);
                a.Sprite_MoveXY(k);
                if (a.Sprite_CheckTileCollision(k) & 15 != 0) {
                    v.sprite_D[i] = t.kPirogusu_Dir[(@as(usize, v.sprite_D[i]) << 1) |
                        @as(usize, a.GetRandomNumber() & 1)];
                }
                const j: usize = v.sprite_D[i];
                v.sprite_x_vel[i] = @bitCast(t.kPirogusu_XYvel3[j]);
                v.sprite_y_vel[i] = @bitCast(t.kPirogusu_XYvel3[j + 2]);
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part72.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_8F_Blob(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.sprite_state[i] == 9 and v.sprite_E[i] != 0) {
        v.sprite_E[i] = 0;
        v.sprite_x_vel[i] = 1;
        const coll = a.Sprite_CheckTileCollision(k);
        v.sprite_x_vel[i] = 0;
        if (coll != 0) {
            v.sprite_state[i] = 0;
            return;
        }
        a.SpriteSfx_QueueSfx2WithPan(k, 0x20);
    }
    if (v.sprite_C[i] != 0)
        v.sprite_obj_prio[i] = 0x30;
    Zol_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;

    if (v.sprite_ai_state[i] >= 2)
        _ = a.Sprite_CheckDamageFromLink(k);
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    switch (v.sprite_ai_state[i]) {
        0 => { // hiding unseen
            const bak = v.sprite_flags4[i];
            v.sprite_flags4[i] |= 9;
            v.sprite_flags2[i] |= 0x80;
            const hit = a.Sprite_CheckDamageToLink(k);
            v.sprite_flags4[i] = bak;
            if (hit) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 127;
                v.sprite_flags2[i] &= ~@as(u8, 0x80);
                a.Sprite_SetX(k, v.link_x_coord.*);
                a.Sprite_SetY(k, v.link_y_coord.* +% 8);
                v.sprite_delay_aux4[i] = 48;
                v.sprite_ignore_projectile[i] = 0;
            }
        },
        1 => { // popping out
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_z_vel[i] = 32;
                a.Sprite_ApplySpeedTowardsLink(k, 16);
                a.SpriteSfx_QueueSfx3WithPan(k, 0x30);
            } else {
                v.sprite_graphics[i] = @bitCast(t.kZol_PoppingOutGfx[v.sprite_delay_main[i] >> 3]);
            }
        },
        2 => { // falling
            if (v.sprite_delay_main[i] == 0) {
                _ = a.Sprite_CheckDamageFromLink(k);
                a.Sprite_MoveXY(k);
                _ = a.Sprite_CheckTileCollision(k);
                const oldz = v.sprite_z[i];
                a.Sprite_MoveZ(k);
                if (!sign8(v.sprite_z_vel[i] +% 64))
                    v.sprite_z_vel[i] -%= 2;
                if (sign8(v.sprite_z[i] ^ oldz) and sign8(v.sprite_z[i])) {
                    v.sprite_z_vel[i] = 0;
                    v.sprite_z[i] = 0;
                    v.sprite_C[i] = 0;
                    v.sprite_delay_main[i] = 31;
                    v.sprite_head_dir[i] = 8;
                }
            } else if (v.sprite_delay_main[i] == 1) {
                v.sprite_delay_main[i] = 32;
                v.sprite_ai_state[i] +%= 1;
                v.sprite_graphics[i] = 0;
            } else {
                v.sprite_graphics[i] = @bitCast(t.kZol_FallingGfx[(v.sprite_delay_main[i] -% 1) >> 4]);
                v.sprite_x_vel[i] = @bitCast(t.kZol_FallingXvel[v.frame_counter.* >> 1 & 1]);
                a.Sprite_MoveX(k);
            }
        },
        3 => { // active
            _ = a.Sprite_CheckDamageToLink(k);
            if (v.sprite_delay_aux1[i] == 0) {
                a.Sprite_ApplySpeedTowardsLink(k, 48);
                v.sprite_delay_aux1[i] = a.GetRandomNumber() & 63 | 96;
                v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & 0x3f |
                    (if (sign8(v.sprite_x_vel[i])) @as(u8, 0x40) else 0);
            }
            if (v.sprite_delay_aux2[i] == 0) {
                v.sprite_subtype2[i] +%= 1;
                if ((v.sprite_subtype2[i] & 14 | v.sprite_wallcoll[i]) == 0) {
                    a.Sprite_MoveXY(k);
                    v.sprite_G[i] +%= 1;
                    if (v.sprite_G[i] == v.sprite_head_dir[i]) {
                        v.sprite_G[i] = 0;
                        v.sprite_delay_aux2[i] = (a.GetRandomNumber() & 31) +% 64;
                        v.sprite_head_dir[i] = a.GetRandomNumber() & 31 | 16;
                    }
                }
                _ = a.Sprite_CheckTileCollision(k);
                v.sprite_graphics[i] = (v.sprite_subtype2[i] & 8) >> 3;
            } else {
                v.sprite_graphics[i] = if (v.sprite_delay_aux2[i] & 0x10 != 0) 1 else 0;
            }
        },
        else => {},
    }
}

pub export fn Zol_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: PrepOamCoordsRet = undefined;
    if (v.sprite_oam_flags[i] & 1 == 0 and v.byte_7E0FC6.* >= 3)
        return;

    if (v.sprite_delay_aux4[i] != 0)
        _ = a.Oam_AllocateFromRegionB(8);

    if (v.sprite_ai_state[i] == 0) {
        a.Sprite_PrepOamCoord(k, &info);
        return;
    }
    const gfx = v.sprite_graphics[i];
    if (gfx < 4) {
        const bak1 = v.sprite_oam_flags[i];
        v.sprite_oam_flags[i] = bak1 ^ t.kZol_OamFlags[gfx];
        v.sprite_graphics[i] = gfx +% ((v.sprite_oam_flags[i] & 1 ^ 1) << 2);
        a.SpriteDraw_SingleLarge(k);
        v.sprite_graphics[i] = gfx;
        v.sprite_oam_flags[i] = bak1;
    } else {
        a.Sprite_DrawMultiple(k, &t.kZol_Dmd[@as(usize, gfx - 4) * 2], 2, null);
    }
}

pub export fn Sprite_8E_Terrorpin(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleLarge(k);
    _ = a.Sprite_CheckTileCollision(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    if (v.sprite_delay_aux2[i] == 0)
        _ = a.Sprite_CheckDamageFromLink(k);
    a.Terrorpin_CheckForHammer(k);
    a.Sprite_MoveXYZ(k);
    switch (v.sprite_B[i]) {
        0 => { // upright
            if (v.sprite_delay_aux4[i] == 0) {
                v.sprite_delay_aux4[i] = (a.GetRandomNumber() & 31) +% 32;
                v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
            }
            const j: usize = @as(usize, v.sprite_D[i]) + @as(usize, v.sprite_G[i]);
            v.sprite_x_vel[i] = @bitCast(t.kTerrorpin_Xvel[j]);
            v.sprite_y_vel[i] = @bitCast(t.kTerrorpin_Yvel[j]);
            v.sprite_z_vel[i] -%= 2;
            if (sign8(v.sprite_z[i])) {
                v.sprite_z[i] = 0;
                v.sprite_z_vel[i] = 0;
            }
            const shift: u3 = if (v.sprite_G[i] != 0) 2 else 3;
            v.sprite_graphics[i] = v.frame_counter.* >> shift & 1;
            v.sprite_flags3[i] |= 64;
            v.sprite_defl_bits[i] = 4;
            _ = a.Sprite_CheckDamageToLink(k);
        },
        1 => { // overturned
            v.sprite_flags3[i] &= 191;
            v.sprite_defl_bits[i] = 0;
            if (v.sprite_delay_aux4[i] == 0) {
                v.sprite_B[i] = 0;
                v.sprite_z_vel[i] = 32;
                v.sprite_delay_aux4[i] = 64;
                return;
            }
            v.sprite_z_vel[i] -%= 2;
            if (sign8(v.sprite_z[i])) {
                v.sprite_z[i] = 0;
                const bounce: u8 = (0 -% v.sprite_z_vel[i]) >> 1;
                v.sprite_z_vel[i] = if (bounce < 9) 0 else bounce;
                v.sprite_x_vel[i] = @bitCast(@as(i8, @bitCast(v.sprite_x_vel[i])) >> 1);
                if (v.sprite_x_vel[i] == 0xff)
                    v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = @bitCast(@as(i8, @bitCast(v.sprite_y_vel[i])) >> 1);
                if (v.sprite_y_vel[i] == 0xff)
                    v.sprite_y_vel[i] = 0;
            }
            if (v.sprite_delay_aux4[i] < 64) {
                v.sprite_x_vel[i] = @bitCast(t.kTerrorpin_Overturned_Xvel[v.sprite_delay_aux4[i] >> 1 & 1]);
                v.sprite_subtype2[i] +%= 1;
            }
            v.sprite_graphics[i] = 2;
            v.sprite_subtype2[i] +%= 1;
            v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & ~@as(u8, 0x40) |
                t.kTerrorpin_Oamflags[v.sprite_subtype2[i] >> 3 & 1];
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part73.zig
// ---------------------------------------------------------------------------
// ArrgiSin is `static` in the C, so it is absent from the ABI header and has to
// come from the module that ported it.

/// The C widens overlord_x_lo[0] to 16 bits; the array starts at 0xb08.

pub export fn Sprite_8C_Arrghus(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_obj_prio[i] |= 0x30;
    Arrghus_Draw(k);
    if (v.sprite_state[i] != 9 or v.sprite_z[i] < 96) {
        if (a.Sprite_ReturnIfInactive(k)) return;
    }
    Arrghus_HandlePuffs(k);
    v.overlord_x_lo[4] = 1;
    if (v.sprite_hit_timer[i] & 127 == 2) {
        v.sprite_ai_state[i] = 3;
        a.SpriteSfx_QueueSfx3WithPan(k, 0x32);
        v.sprite_subtype2[i] = 0;
        v.sprite_flags3[i] = 64;
    }
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToLink(k);
    const tick = v.sprite_subtype2[i];
    v.sprite_subtype2[i] +%= 1;
    if (tick & 3 == 0) {
        v.sprite_G[i] +%= 1;
        if (v.sprite_G[i] == 9)
            v.sprite_G[i] = 0;
        v.sprite_graphics[i] = t.kArrghus_Gfx[v.sprite_G[i]];
    }

    const coll = a.Sprite_CheckTileCollision(k);
    if (coll != 0) {
        if (v.sprite_ai_state[i] == 5) {
            if (coll & 3 != 0)
                v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i]
            else
                v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
        } else {
            a.Sprite_ZeroVelocity_XY(k);
        }
    }

    switch (v.sprite_ai_state[i]) {
        0 => { // approach speed
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 48;
            }
            a.Sprite_MoveXY(k);
            a.Sprite_ApproachTargetSpeed(k, v.sprite_head_dir[i], v.sprite_D[i]);
        },
        1 => { // decelerate
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 0;
                if (!a.Sprite_CheckIfScreenIsClear()) {
                    v.overlord_x_lo[3] +%= 1;
                    if (v.overlord_x_lo[3] == 4) {
                        v.overlord_x_lo[3] = 0;
                        v.sprite_ai_state[i] = 2;
                        v.sprite_delay_main[i] = 176;
                    } else {
                        v.sprite_delay_main[i] = (a.GetRandomNumber() & 63) +% 48;
                        const pt = a.Sprite_ProjectSpeedTowardsLink(k, (v.sprite_delay_main[i] & 3) +% 8);
                        v.sprite_head_dir[i] = pt.x;
                        v.sprite_D[i] = pt.y;
                    }
                } else {
                    v.sprite_ai_state[i] = 3;
                    a.SpriteSfx_QueueSfx3WithPan(k, 0x32);
                    v.sprite_subtype2[i] = 0;
                }
            } else {
                a.Sprite_MoveXY(k);
                a.Sprite_ApproachTargetSpeed(k, 0, 0);
            }
        },
        2 => { // case2
            v.overlord_x_lo[4] = 8;
            if (v.sprite_delay_main[i] < 32) {
                v.overlord_x_lo[2] -%= 1;
                if (sign8(v.overlord_x_lo[2])) {
                    v.overlord_x_lo[2] = 0;
                    v.sprite_ai_state[i] = 1;
                    v.sprite_delay_main[i] = 112;
                }
            } else if (v.sprite_delay_main[i] < 96) {
                v.overlord_x_lo[2] +%= 1;
            } else if (v.sprite_delay_main[i] == 96) {
                a.SpriteSfx_QueueSfx3WithPan(k, 0x26);
            } else if (v.sprite_delay_main[i] & 0xf == 0) {
                a.SpriteSfx_QueueSfx3WithPan(k, 0x6);
            }
        },
        3 => { // jump way up
            v.sprite_z_vel[i] = 120;
            a.Sprite_MoveZ(k);
            if (v.sprite_z[i] >= 224) {
                v.sprite_delay_main[i] = 64;
                v.sprite_ai_state[i] = 4;
                v.sprite_z_vel[i] = 0;
                v.sprite_x_lo[i] = @truncate(v.link_x_coord.*);
                v.sprite_y_lo[i] = @truncate(v.link_y_coord.*);
            }
        },
        4 => { // swoosh from above
            // The C keeps reusing `a` here, so the tail test sees whichever
            // value the chain last assigned.
            var av: u8 = v.sprite_delay_main[i];
            if (av == 0) {
                v.sprite_z_vel[i] = 144;
                const old_z = v.sprite_z[i];
                a.Sprite_MoveZ(k);
                av = old_z ^ v.sprite_z[i];
                if (sign8(av)) {
                    av = v.sprite_z[i];
                    if (sign8(av)) {
                        v.sprite_z[i] = 0;
                        a.Sprite_SpawnBigSplash(k);
                        v.sprite_ai_state[i] = 5;
                        v.sprite_delay_main[i] = 32;
                        a.SpriteSfx_QueueSfx3WithPan(k, 0x3);
                        v.sprite_x_vel[i] = 32;
                        v.sprite_y_vel[i] = 32;
                    }
                }
            }
            if (av == 1) { // wtf
                a.SpriteSfx_QueueSfx2WithPan(k, 0x20);
            }
        },
        5 => { // swim frantically
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_flags3[i] = 0;
                a.Sprite_MoveXY(k);
                _ = a.Sprite_CheckDamageFromLink(k);
                if (v.frame_counter.* & 7 == 0) {
                    a.SpriteSfx_QueueSfx2WithPan(k, 0x28);
                    const j = a.GarnishAllocLimit(if (sign8(v.sprite_y_vel[i])) 29 else 14);
                    if (j >= 0) {
                        const ju = ix(j);
                        v.garnish_type[ju] = 21;
                        v.garnish_active.* = 21;
                        v.garnish_x_lo[ju] = v.sprite_x_lo[i];
                        v.garnish_x_hi[ju] = v.sprite_x_hi[i];
                        v.garnish_y_lo[ju] = v.sprite_y_lo[i] +% 24; // why no carry propagation
                        v.garnish_y_hi[ju] = v.sprite_y_hi[i];
                        v.garnish_countdown[ju] = 15;
                    }
                }
            }
        },
        else => {},
    }
}

pub export fn Arrghus_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Sprite_DrawMultiple(k, &t.kArrghus_Dmd[0], 5, null);
    const oam = oamPtr();
    const chr: u8 = v.sprite_graphics[i] *% 2;
    var n: usize = 0;
    while (n < 4) : (n += 1)
        oam[n].charnum +%= chr;
    if (v.sprite_ai_state[i] == 5)
        oam[4].y = 0xf0;
    if (v.sprite_subtype2[i] & 8 != 0)
        oam[4].flags |= 0x40;

    if (v.sprite_ai_state[i] != 5) {
        v.oam_cur_ptr.* +%= 4;
        v.oam_ext_cur_ptr.* +%= 1;
        if (v.sprite_z[i] < 0xa0) {
            const bak = v.sprite_oam_flags[i];
            v.sprite_oam_flags[i] &= ~@as(u8, 1);
            a.SpriteDraw_BigShadow(k, 0);
            v.sprite_oam_flags[i] = bak;
        }
    } else {
        a.Sprite_DrawLargeWaterTurbulence(k);
    }
}

pub export fn Arrghus_HandlePuffs(k: c_int) callconv(.c) void {
    const i = ix(k);
    overlord_x_lo_w0.* +%= v.overlord_x_lo[4];
    if (v.frame_counter.* & 3 == 0) {
        v.sprite_A[i] +%= 1;
        if (v.sprite_A[i] == 13)
            v.sprite_A[i] = 0;
    }
    if (v.frame_counter.* & 7 == 0) {
        v.sprite_B[i] +%= 1;
        if (v.sprite_B[i] == 13)
            v.sprite_B[i] = 0;
    }
    var n: usize = 0;
    while (n != 13) : (n += 1) {
        const r0: u16 = (overlord_x_lo_w0.* +% t.kArrgi_Tab0[n]) ^ t.kArrgi_Tab1[n];
        const r14: u8 = v.overlord_x_lo[2] +% t.kArrgi_Tab2[n];

        const sin_val = ArrgiSin(r0, r14 +% @as(u8, @bitCast(t.kArrgi_Tab3[@as(usize, v.sprite_A[i]) + n])));
        const cos_val = ArrgiSin(r0 +% 0x80, r14 +% @as(u8, @bitCast(t.kArrgi_Tab3[@as(usize, v.sprite_B[i]) + n])));

        const tx: u16 = a.Sprite_GetX(k) +% cm.s16(sin_val);
        v.overlord_x_hi[n] = @truncate(tx);
        v.overlord_y_hi[n] = @truncate(tx >> 8);

        const ty: u16 = a.Sprite_GetY(k) +% cm.s16(cos_val) -% 0x10;
        v.overlord_gen2[n] = @truncate(ty);
        v.overlord_floor[n] = @truncate(ty >> 8);
    }
    v.tmp_counter.* = 13;
}

// ---------------------------------------------------------------------------
// from sprite_main_part74.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_8D_Arrghi(k: c_int) callconv(.c) void {
    const i = ix(k);

    v.sprite_obj_prio[i] |= 0x30;
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = t.kArrgi_Gfx[v.sprite_subtype2[i] >> 3 & 7];
    if (v.sprite_B[i] != 0) {
        const j: usize = v.sprite_B[i] - 1;
        if (v.ancilla_type[j] != 0) {
            v.sprite_x_lo[i] = v.ancilla_x_lo[j];
            v.sprite_x_hi[i] = v.ancilla_x_hi[j];
            v.sprite_y_lo[i] = v.ancilla_y_lo[j];
            v.sprite_y_hi[i] = v.ancilla_y_hi[j];
            v.sprite_oam_flags[i] = 5;
            v.sprite_flags3[i] &= ~@as(u8, 0x40);
            return;
        }
        v.sprite_ai_state[i] = 1;
        v.sprite_B[i] = 0;
        v.sprite_delay_main[i] = 32;
    }
    if (v.sprite_delay_main[i] == 0)
        _ = a.Sprite_CheckDamageToLink(k);

    const s = i + 7;
    if (v.sprite_ai_state[i] == 0) {
        v.sprite_x_lo[i] = v.overlord_x_lo[s];
        v.sprite_x_hi[i] = v.overlord_y_lo[s];
        v.sprite_y_lo[i] = v.overlord_gen1[s];
        v.sprite_y_hi[i] = v.overlord_gen3[s];
        return;
    }
    _ = a.Sprite_CheckDamageFromLink(k);
    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 == 0) {
        const x: u16 = (@as(u16, v.overlord_y_lo[s]) << 8) | v.overlord_x_lo[s];
        const y: u16 = (@as(u16, v.overlord_gen3[s]) << 8) | v.overlord_gen1[s];
        const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 4);
        v.sprite_y_vel[i] = pt.y;
        v.sprite_x_vel[i] = pt.x;
        if (v.sprite_x_lo[i] -% v.overlord_x_lo[s] +% 8 < 16 and
            v.sprite_y_lo[i] -% v.overlord_gen1[s] +% 8 < 16)
        {
            v.sprite_ai_state[i] = 0;
            v.sprite_oam_flags[i] = 0xd;
            v.sprite_flags3[i] |= 0x40;
        }
    }
    a.Sprite_MoveXY(k);
}

/// The `lbl_b` label: the flap animation shared by states 1 and 2.

/// The `lbl_a` label: shatter into a puff of debris.

pub export fn Sprite_94_Tile(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_obj_prio[i] = 0x30;
    a.FlyingTile_Draw(k);
    if (a.Sprite_ReturnIfPaused(k)) return;
    if (v.sprite_hit_timer[i] != 0) {
        flyingTileShatter(k);
        return;
    }
    v.sprite_ignore_projectile[i] = 1;
    switch (v.sprite_ai_state[i]) {
        0 => { // erase tilemap
            const y: u16 = (@as(u16, v.sprite_y_lo[i]) +% 8) & 0xff | (@as(u16, v.sprite_y_hi[i]) << 8);
            a.Dungeon_UpdateTileMapWithCommonTile(a.Sprite_GetX(k), y, 6);
            v.sprite_ai_state[i] = 1;
            v.sprite_delay_main[i] = 128;
        },
        1 => { // rise up
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 16;
                a.Sprite_ApplySpeedTowardsLink(k, 32);
            } else {
                if (v.sprite_delay_main[i] >= 0x40) {
                    v.sprite_z_vel[i] = 4;
                    a.Sprite_MoveZ(k);
                }
                flyingTileAnimate(k);
            }
        },
        2 => { // towards player
            v.sprite_ignore_projectile[i] = 0;
            if (v.sprite_delay_main[i] != 0 and v.sprite_delay_main[i] & 3 == 0)
                a.Sprite_ApplySpeedTowardsLink(k, 32);
            if (!a.Sprite_CheckDamageToAndFromLink(k)) {
                a.Sprite_MoveXY(k);
                v.cur_sprite_y.* -%= v.sprite_z[i];
                if (a.Sprite_CheckTileCollision(k) == 0) {
                    flyingTileAnimate(k);
                    return;
                }
            }
            flyingTileShatter(k);
        },
        else => {},
    }
}

pub export fn Sprite_8A_SpikeBlock(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_E[i] == 0) {
        a.SpriteDraw_SingleLarge(k);
        if (a.Sprite_ReturnIfInactive(k)) return;
        _ = a.Sprite_CheckDamageToAndFromLink(k);
        a.Sprite_MoveXY(k);
        _ = a.Sprite_CheckTileCollision(k);
        if (v.sprite_delay_main[i] == 0 and
            (!a.SpikeBlock_CheckStatueCollision(k) or v.sprite_wallcoll[i] & 0xf != 0))
        {
            v.sprite_delay_main[i] = 4;
            v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
            a.SpriteSfx_QueueSfx2WithPan(k, 0x5);
        }
        return;
    }
    _ = a.Oam_AllocateFromRegionB(4);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    if (v.sprite_ai_state[i] == 0) {
        a.Dungeon_UpdateTileMapWithCommonTile(a.Sprite_GetX(k), a.Sprite_GetY(k), 0);
        v.sprite_ai_state[i] = 1;
        v.sprite_delay_main[i] = 64;
        v.sprite_delay_aux1[i] = 105;
    } else if (v.sprite_delay_main[i] != 0) {
        if (v.sprite_delay_main[i] == 1) {
            v.sprite_x_lo[i] = v.sprite_A[i];
            v.sprite_y_lo[i] = v.sprite_B[i];
        } else {
            v.sprite_x_vel[i] = if ((v.sprite_delay_main[i] >> 1) & 1 != 0) cm.byte(-8) else 8;
            a.Sprite_MoveX(k);
            v.sprite_x_vel[i] = 0;
        }
    } else if (v.sprite_ai_state[i] == 1) {
        const j: usize = v.sprite_D[i];
        if (v.sprite_x_vel[i] != @as(u8, @bitCast(t.kSpikeBlock_XVelTarget[j])))
            v.sprite_x_vel[i] +%= @bitCast(t.kSpikeBlock_XVelDelta[j]);
        if (v.sprite_y_vel[i] != @as(u8, @bitCast(t.kSpikeBlock_YVelTarget[j])))
            v.sprite_y_vel[i] +%= @bitCast(t.kSpikeBlock_YVelDelta[j]);
        a.Sprite_MoveXY(k);
        if (v.sprite_delay_aux1[i] == 0) {
            a.Sprite_Get16BitCoords(k);
            if (a.Sprite_CheckTileCollision(k) != 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_aux1[i] = 64;
            }
        }
    } else if (v.sprite_delay_aux1[i] == 0) {
        const j: usize = v.sprite_D[i];
        v.sprite_x_vel[i] = @bitCast(t.kSpikeBlock_XVel[j]);
        v.sprite_y_vel[i] = @bitCast(t.kSpikeBlock_YVel[j]);
        a.Sprite_MoveXY(k);
        if (v.sprite_x_lo[i] == v.sprite_A[i] and v.sprite_y_lo[i] == v.sprite_B[i]) {
            v.sprite_state[i] = 0;
            a.Dungeon_UpdateTileMapWithCommonTile(a.Sprite_GetX(k), a.Sprite_GetY(k), 2);
        }
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part75.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_88_Mothula(k: c_int) callconv(.c) void {
    if (f_p75.enhanced_features0.* & f_p75.kFeatures0_MiscBugFixes != 0) {
        // L4 sword and L3 spin slash can now damage Mothula
        v.enemy_damage_data[0x884] = 1;
        v.enemy_damage_data[0x885] = 1;
    }
    Mothula_Main(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    Mothula_HandleSpikes(k);
}

pub export fn Mothula_Main(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Mothula_Draw(k);
    if (v.sprite_state[i] == 11)
        v.sprite_ai_state[i] = 0;
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_flags3[i] = 0;
    if (v.sprite_delay_aux3[i] != 0)
        v.sprite_flags3[i] = 64;
    if (v.sprite_F[i] & 127 == 6) {
        v.sprite_F[i] = 0;
        v.sprite_delay_aux3[i] = 32;
        v.sprite_ai_state[i] = 2;
        v.sprite_delay_main[i] = 0;
        v.sprite_G[i] = 64;
    }
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    switch (v.sprite_ai_state[i]) {
        0 => { // Delay
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] = 1;
        },
        1 => { // Ascend
            v.sprite_z_vel[i] = 8;
            a.Sprite_MoveZ(k);
            v.sprite_z_vel[i] = 0;
            if (v.sprite_z[i] >= 24) {
                v.sprite_G[i] = 128;
                v.sprite_ai_state[i] = 2;
                v.sprite_ignore_projectile[i] = 0;
                v.sprite_delay_main[i] = 64;
            }
            a.Mothula_FlapWings(k);
        },
        2 => { // FlyAbout
            if (v.sprite_G[i] == 0) {
                v.sprite_delay_main[i] = 63;
                v.sprite_ai_state[i] = 3;
                return;
            }
            v.sprite_G[i] -%= 1;
            a.Mothula_FlapWings(k);
            const up = v.sprite_A[i] & 1 != 0;
            v.sprite_z_vel[i] +%= if (up) cm.byte(-1) else 1;
            if (v.sprite_z_vel[i] == (if (up) cm.byte(-16) else @as(u8, 16)))
                v.sprite_A[i] +%= 1;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_C[i] +%= 1;
                if (v.sprite_C[i] == 7) {
                    v.sprite_C[i] = 0;
                    a.Sprite_ApplySpeedTowardsLink(k, 32);
                    v.sprite_delay_main[i] = 128;
                } else {
                    const j: usize = a.GetRandomNumber() & 7;
                    v.sprite_x_vel[i] = @bitCast(t.kMothula_XYvel[j + 2]);
                    v.sprite_y_vel[i] = @bitCast(t.kMothula_XYvel[j]);
                    v.sprite_delay_main[i] = (a.GetRandomNumber() & 31) +% 64;
                }
            }
            if (v.sprite_wallcoll[i] == 0)
                a.Sprite_MoveXY(k);
            a.Sprite_MoveZ(k);
            if (a.Sprite_CheckTileCollision(k) != 0)
                v.sprite_delay_main[i] = 0;
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            v.sprite_subtype2[i] +%= 2;
        },
        3 => { // FireBeams
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] -%= 1;
                v.sprite_G[i] = a.GetRandomNumber() & 31 | 64;
            } else {
                if (v.sprite_delay_main[i] == 0x20)
                    a.Mothula_SpawnBeams(k);
                a.Mothula_FlapWings(k);
            }
        },
        else => {},
    }
}

pub export fn Mothula_HandleSpikes(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_head_dir[i] -%= 1;
    if (v.sprite_head_dir[i] != 0)
        return;
    v.sprite_head_dir[i] = 0x40;

    var info: a.SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x8a, &info);
    if (j < 0)
        return;
    const ju = ix(j);

    var n: usize = a.GetRandomNumber() & 0x1f;
    if (n >= 30) n -= 30;
    // The C chains the assignment, so the spawn coord and its backup both take
    // the table value.
    v.sprite_x_lo[ju] = t.kMothula_Spike_XLo[n];
    v.sprite_A[ju] = v.sprite_x_lo[ju];
    v.sprite_y_lo[ju] = t.kMothula_Spike_YLo[n] -% 1;
    v.sprite_B[ju] = v.sprite_y_lo[ju];
    v.sprite_D[ju] = t.kMothula_Spike_Dir[n];
    v.sprite_E[ju] = 1;
    v.sprite_x_hi[ju] = v.byte_7E0FB0.* +% 1;
    v.sprite_y_hi[ju] = v.byte_7E0FB1.* +% 1;
    v.sprite_x_vel[ju] = 1;
    a.Sprite_Get16BitCoords(j);
    _ = a.Sprite_CheckTileCollision(j);
    v.sprite_x_vel[ju] = 0;
    v.sprite_x_lo[ju] = v.sprite_A[ju];
    v.sprite_y_lo[ju] = v.sprite_B[ju];
    if (v.sprite_wallcoll[ju] == 0) {
        // Nothing solid to cling to: drop the spike and retry next frame.
        v.sprite_state[ju] = 0;
        v.sprite_head_dir[i] = 1;
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part76.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_86_Kodongo(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_flags[i] = 0;
    switch (v.sprite_ai_state[i]) {
        0 => { // choose dir
            v.sprite_ai_state[i] +%= 1;
            v.sprite_D[i] = a.GetRandomNumber() & 3;
            v.sprite_flags[i] = 176;
            // Rotate through the four directions until one is not walled off.
            while (true) {
                const j: usize = v.sprite_D[i];
                v.sprite_x_vel[i] = @bitCast(t.kKodondo_Xvel[j]);
                v.sprite_y_vel[i] = @bitCast(t.kKodondo_Yvel[j]);
                if (a.Sprite_CheckTileCollision(k) == 0)
                    break;
                v.sprite_D[i] = (v.sprite_D[i] +% 1) & 3;
            }
            a.Kodongo_SetDirection(k);
        },
        1 => { // move
            a.Sprite_MoveXY(k);
            if (a.Sprite_CheckTileCollision(k) != 0) {
                v.sprite_D[i] ^= 1;
                a.Kodongo_SetDirection(k);
            }
            if (v.sprite_x_lo[i] & 0x1f == 4 and
                v.sprite_y_lo[i] & 0x1f == 0x1b and
                a.GetRandomNumber() & 3 == 0)
            {
                v.sprite_delay_main[i] = 111;
                v.sprite_ai_state[i] = 2;
                v.sprite_A[i] = 0;
            }
            v.sprite_subtype2[i] +%= 1;
            const j: usize = (v.sprite_subtype2[i] & 4) | v.sprite_D[i];
            v.sprite_graphics[i] = t.kKodondo_Gfx[j];
            v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & ~@as(u8, 0x40) | t.kKodondo_OamFlags[j];
        },
        2 => { // breathe flame
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] = 0;
            const j: usize = @intFromBool(v.sprite_delay_main[i] -% 0x20 < 0x30);
            if (j != 0 and v.sprite_delay_main[i] & 0xf == 0)
                a.Kodongo_SpawnFire(k);
            v.sprite_graphics[i] = t.kKodondo_FlameGfx[j * 4 + @as(usize, v.sprite_D[i])];
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part77.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_85_YellowStalfos(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.sprite_A[i] == 0) {
        // First frame: refuse to materialize inside a wall.
        v.sprite_x_vel[i] = 1;
        v.sprite_y_vel[i] = 1;
        if (a.Sprite_CheckTileCollision(k) != 0) {
            v.sprite_state[i] = 0;
            return;
        }
        v.sprite_A[i] +%= 1;
        v.sprite_C[i] = 10;
        v.sprite_flags3[i] |= 64;
        a.SpriteSfx_QueueSfx2WithPan(k, 0x20);
    }

    v.sprite_obj_prio[i] |= @bitCast(t.kYellowStalfos_ObjPrio[v.sprite_ai_state[i]]);
    a.YellowStalfos_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.link_sword_type.* >= 3) {
        if (a.Sprite_ReturnIfRecoiling(k)) return;
    } else if (v.sprite_ai_state[i] != 5 and v.sprite_hit_timer[i] != 0) {
        // A weak sword only stuns it.
        v.sprite_hit_timer[i] = 0;
        v.sprite_ai_state[i] = 5;
        v.sprite_delay_main[i] = 255;
    }
    v.sprite_ignore_projectile[i] = 1;
    switch (v.sprite_ai_state[i]) {
        0 => { // descend
            v.sprite_head_dir[i] = 2;
            const bak0 = v.sprite_z[i];
            a.Sprite_MoveZ(k);
            if (!sign8(v.sprite_z_vel[i] -% 192))
                v.sprite_z_vel[i] -%= 3;
            if (!sign8(bak0) and sign8(v.sprite_z[i])) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_z[i] = 0;
                v.sprite_z_vel[i] = 0;
                v.sprite_delay_main[i] = 64;
                a.YellowStalfos_Animate(k);
            }
        },
        1 => { // face player
            v.sprite_ignore_projectile[i] = 0;
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
            v.sprite_head_dir[i] = v.sprite_D[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 127;
            }
            v.sprite_flags3[i] &= ~@as(u8, 0x40);
        },
        2 => { // pause then detach head
            v.sprite_ignore_projectile[i] = 0;
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 64;
                return;
            }
            if (j == 48)
                a.YellowStalfos_EmancipateHead(k);
            v.sprite_graphics[i] = @bitCast(t.kYellowStalfos_Gfx[(j >> 2) & ~@as(u8, 3) | v.sprite_D[i]]);
            const h: usize = v.sprite_delay_main[i] >> 2;
            v.sprite_B[i] = @bitCast(t.kYellowStalfos_HeadX[h]);
            v.sprite_C[i] = t.kYellowStalfos_HeadY[h];
            v.sprite_flags3[i] &= ~@as(u8, 0x40);
        },
        3 => { // delay before ascending
            v.sprite_ignore_projectile[i] = 0;
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            if (v.sprite_delay_main[i] == 0)
                v.sprite_ai_state[i] +%= 1;
            a.YellowStalfos_Animate(k);
        },
        4 => { // ascend
            v.sprite_graphics[i] = 0;
            v.sprite_head_dir[i] = 2;
            const j = v.sprite_z[i];
            a.Sprite_MoveZ(k);
            if (sign8(v.sprite_z_vel[i] -% 64))
                v.sprite_z_vel[i] +%= 2;
            if (sign8(j) and !sign8(v.sprite_z[i]))
                v.sprite_state[i] = 0;
        },
        5 => { // neutralized
            v.sprite_ignore_projectile[i] = 0;
            _ = a.Sprite_CheckDamageFromLink(k);
            const j = v.sprite_delay_main[i];
            if (j == 0)
                v.sprite_ai_state[i] -%= 1;
            v.sprite_graphics[i] = @bitCast(t.kYellowStalfos_NeutralizedGfx[j >> 4]);
            v.sprite_C[i] = @bitCast(t.kYellowStalfos_NeutralizedHeadY[j >> 4]);
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part78.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_83_GreenEyegore(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.sprite_B[i] == 0) {
        a.Eyegore_Main(k);
        return;
    }
    a.Goriya_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    if (v.sprite_delay_aux1[i] == 8)
        _ = a.Sprite_SpawnFirePhlegm(k);

    if (v.bitmask_of_dragstate.* != 0 or v.joypad1H_last.* & 0xf == 0) {
        v.sprite_A[i] = 0;
        _ = a.Sprite_CheckDamageToAndFromLink(k);
        _ = a.Sprite_CheckTileCollision(k);
        return;
    }

    const j: usize = @as(usize, v.joypad1H_last.* & 0xf) |
        (@as(usize, @intFromBool(v.sprite_type[i] == 0x84)) * 16);
    v.sprite_D[i] = t.kGoriya_Dir[j];
    v.sprite_x_vel[i] = @bitCast(t.kGoriya_Xvel[j]);
    v.sprite_y_vel[i] = @bitCast(t.kGoriya_Yvel[j]);
    if (v.sprite_wallcoll[i] == 0)
        a.Sprite_MoveXY(k);
    _ = a.Sprite_CheckDamageToAndFromLink(k);
    _ = a.Sprite_CheckTileCollision(k);
    v.sprite_subtype2[i] +%= 1;
    v.sprite_graphics[i] = t.kGoriya_Gfx[(v.sprite_subtype2[i] & 12) | v.sprite_D[i]];

    if (v.sprite_type[i] == 0x84) {
        var pt: a.PointU8 = undefined;
        const dir = a.Sprite_DirectionToFaceLink(k, &pt);
        if ((pt.x +% 8 < 16 or pt.y +% 8 < 16) and v.sprite_D[i] == dir) {
            if (v.sprite_A[i] & 0x1f == 0)
                v.sprite_delay_aux1[i] = 16;
            v.sprite_A[i] +%= 1;
            return;
        }
    }
    v.sprite_A[i] = 0;
}

// ---------------------------------------------------------------------------
// from sprite_main_part79.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_AB_CrystalMaiden(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.cur_sprite_x.* -%= v.dung_floor_x_offs.*;
    v.cur_sprite_y.* -%= v.dung_floor_y_offs.*;

    if (v.sprite_ai_state[i] >= 3)
        a.CrystalMaiden_Draw(k);
    v.is_nmi_thread_active.* = 1;
    if (v.intro_did_run_step.* == 0) {
        CrystalMaiden_RunCutscene(k);
        v.intro_did_run_step.* = 1;
    }
}

pub export fn CrystalMaiden_RunCutscene(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_E[i] +%= 1;
    v.poly_b.* +%= 6;
    if (v.submodule_index.* != 0)
        return;
    switch (v.sprite_ai_state[i]) {
        0 => { // disable subscreen
            v.TS_copy.* = 0;
            v.sprite_ai_state[i] +%= 1;
        },
        1 => { // enable subscreen
            v.TS_copy.* = 1;
            v.sprite_ai_state[i] +%= 1;
        },
        2 => { // generate sparkles
            if (v.poly_config1.* < 6) {
                v.poly_config1.* = 0;
                v.sprite_ai_state[i] +%= 1;
            } else {
                v.poly_config1.* -%= 3;
                if (v.poly_config1.* >= 64)
                    a.AncillaAdd_SwordChargeSparkle(v.sprite_A[i]);
            }
        },
        // Case 3 falls through into case 4 in the C, so the state bump and the
        // filter step both run on the same frame.
        3, 4 => { // filter palette
            if (v.sprite_ai_state[i] == 3)
                v.sprite_ai_state[i] +%= 1;
            if (v.sprite_E[i] & 1 == 0) {
                a.PaletteFilter_SP5F();
                if (@as(u8, @truncate(v.palette_filter_countdown.*)) == 0) {
                    v.sprite_ai_state[i] +%= 1;
                    v.flag_is_link_immobilized.* = 1;
                    v.link_receiveitem_index.* = 0;
                    v.link_pose_for_item.* = 0;
                    v.link_animation_steps.* = 0;
                    v.link_direction_facing.* = 0;
                }
            }
        },
        5 => { // show message
            var j: c_int = @as(c_int, @as(u8, @truncate(v.cur_palace_index_x2.*))) - 10;
            if (j == 2 and v.savegame_map_icons_indicator.* < 7)
                v.savegame_map_icons_indicator.* = 7;
            if (j == 14 and v.link_has_crystals.* & 0x7f != 0x7f)
                j = 16;
            a.Sprite_ShowMessageUnconditional(t.kCrystalMaiden_Msgs[@intCast(j >> 1)]);
            v.sprite_ai_state[i] +%= 1;
            if (v.link_has_crystals.* & 0x7f == 0x7f)
                v.savegame_map_icons_indicator.* = 8;
        },
        6 => { // reading comprehension exam
            a.Sprite_ShowMessageUnconditional(0x13a);
            v.sprite_ai_state[i] +%= 1;
        },
        7 => { // may the way of the hero
            if (v.choice_in_multiselect_box.* != 0) {
                v.sprite_ai_state[i] = 5;
            } else {
                a.Sprite_ShowMessageUnconditional(0x139);
                v.sprite_ai_state[i] +%= 1;
            }
        },
        8 => { // initiate dungeon exit
            v.TS_copy.* = 0;
            a.PrepareDungeonExitFromBossFight();
            v.sprite_state[i] = 0;
        },
        else => {},
    }
}

pub export fn Sprite_7E_Firebar_Clockwise(k: c_int) callconv(.c) void {
    const i = ix(k);
    Firebar_Main(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_subtype2[i] +%= 1;
    const j: usize = @as(usize, v.sprite_type[i] -% 0x7e) +
        (@as(usize, @intFromBool(@as(u8, @truncate(v.cur_palace_index_x2.*)) == 18)) * 2);

    var angle: c_int = @as(c_int, v.sprite_A[i]) | (@as(c_int, v.sprite_B[i]) << 8);
    angle = (angle + t.kGuruguruBar_incr[j]) & 0x1ff;
    v.sprite_A[i] = @truncate(@as(u32, @bitCast(angle)));
    v.sprite_B[i] = @truncate(@as(u32, @bitCast(angle)) >> 8);
}

pub export fn Firebar_Main(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: a.PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    const oam = cm.oamPtr();
    v.byte_7E0FB6.* = info.flags;
    v.dungmap_var7.* = @as(u16, info.x) | (@as(u16, info.y) << 8);

    const angle: u16 = @as(u16, v.sprite_A[i]) | (@as(u16, v.sprite_B[i]) << 8);
    const sinval = GuruguruBarSin(angle, 0x40);
    const cosval = GuruguruBarSin((angle +% 0x80) & 0x1ff, 0x40);
    const flags: u8 = ((v.sprite_subtype2[i] << 4) & 0xc0) | info.flags;

    // The C walks the arm outwards from the hub, one segment per OAM entry.
    var n: usize = 0;
    while (n < 4) : (n += 1) {
        const seg: c_int = @intCast(4 - n);
        const x = @as(c_int, info.x) + @divTrunc(@as(c_int, sinval) * seg, 4);
        const y = @as(c_int, info.y) + @divTrunc(@as(c_int, cosval) * seg, 4);
        cm.setOamPlain(oam + n, @truncate(@as(u32, @bitCast(x))), @truncate(@as(u32, @bitCast(y))), 0x28, flags, 2);
    }
    a.Sprite_CorrectOamEntries(k, 3, 0xff);

    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 |
        @as(c_int, v.submodule_index.*) |
        @as(c_int, v.flag_unk1.*) == 0)
    {
        const base = (@intFromPtr(oam) - @intFromPtr(v.oam_buf)) / @sizeOf(@TypeOf(oam[0]));
        var m: usize = 0;
        while (m < 4) : (m += 1) {
            if (v.bytewise_extended_oam[base + m] & 1 != 0)
                continue;
            const dx: u8 = @truncate(@as(u32, @bitCast(
                @as(c_int, oam[m].x) + @as(c_int, v.BG2HOFS_copy2.*) - @as(c_int, v.link_x_coord.*) + 12,
            )));
            const dy: u8 = @truncate(@as(u32, @bitCast(
                @as(c_int, oam[m].y) + @as(c_int, v.BG2VOFS_copy2.*) - @as(c_int, v.link_y_coord.*) + 4,
            )));
            if (dx < 24 and oam[m].y < 0xf0 and dy < 16)
                a.Sprite_AttemptDamageToLinkPlusRecoil(k);
        }
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part80.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_7A_Agahnim(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Agahnim_Draw(k);
    if (v.sprite_pause[i] != 0) {
        v.sprite_delay_main[i] = 32;
        v.sprite_graphics[i] = 0;
        v.sprite_D[i] = 3;
    }
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    v.sprite_ignore_projectile[i] = 1;
    switch (v.sprite_ai_state[i]) {
        0 => {
            v.sprite_ai_state[i] = t.kAgahnim_StartState[v.is_in_dark_world.*];
        },
        1 => {
            if (v.sprite_delay_main[i] == 0) {
                v.dialogue_message_index.* = 0x13f;
                a.Sprite_ShowMessageMinimal();
                v.sprite_ai_state[i] = 3;
                v.sprite_delay_main[i] = 32;
            }
        },
        2 => {
            v.byte_7E0FF8.* = 0;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 255;
            } else {
                v.sprite_graphics[i] = t.kAgahnim_Gfx0[v.sprite_delay_main[i] >> 3];
            }
        },
        3 => {
            const d = v.sprite_delay_main[i];
            if (d == 192)
                a.SpriteSfx_QueueSfx3WithPan(k, 0x27);
            if (d >= 239 or d < 16) {
                a.AgahnimWarpShadowFilter(if (v.is_in_dark_world.* != 0) k else 2);
            } else {
                if (k == 0) {
                    _ = a.Sprite_CheckDamageToAndFromLink(k);
                    v.sprite_ignore_projectile[i] = 0;
                }
            }
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 39;
                return;
            }
            if (v.sprite_delay_main[i] >= 128) {
                // Probe the direction with a slow step, then commit at speed.
                a.Sprite_ApplySpeedTowardsLink(k, 2);
                const yv: c_int = @as(i8, @bitCast(v.sprite_y_vel[i]));
                const xv: c_int = @as(i8, @bitCast(v.sprite_x_vel[i]));
                v.sprite_D[i] = t.kAgahnim_Dir[@intCast((yv + 2) * 5 + 2 + xv)];
                a.Sprite_ApplySpeedTowardsLink(k, 32);
                if (v.sprite_subtype[i] == 4)
                    v.sprite_D[i] = 3;
            } else if (v.sprite_delay_main[i] == 112) {
                Agahnim_PerformAttack(k);
            }
            const j: usize = v.sprite_delay_main[i] >> 4;
            v.sprite_A[i] = t.kAgahnim_Tab0[j];
            const tv = t.kAgahnim_Tab1[j];
            v.sprite_head_dir[i] = if (tv != 0) tv +% t.kAgahnim_Tab2[v.sprite_D[i]] else tv;
            v.sprite_graphics[i] = t.kAgahnim_Gfx1[v.sprite_D[i]] +% v.sprite_A[i];
        },
        4 => {
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                const j: usize = if (v.sprite_subtype[i] == 4) 4 else a.GetRandomNumber() & 0xf;
                v.sprite_C[i] = t.kAgahnim_Tab3[j];
                v.sprite_E[i] = t.kAgahnim_Tab4[j];
                v.sprite_G[i] = 8;
            } else {
                v.sprite_graphics[i] = t.kAgahnim_Gfx2[v.sprite_delay_main[i] >> 3];
            }
        },
        5 => {
            if (@as(u16, v.sprite_x_lo[i]) -% v.sprite_C[i] +% 7 < 14 and
                @as(u16, v.sprite_y_lo[i]) -% v.sprite_E[i] +% 7 < 14)
            {
                v.sprite_x_lo[i] = v.sprite_C[i];
                v.sprite_y_lo[i] = v.sprite_E[i];
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 39;
                return;
            }
            const x: u16 = (@as(u16, v.sprite_x_hi[i]) << 8) | v.sprite_C[i];
            const y: u16 = (@as(u16, v.sprite_y_hi[i]) << 8) | v.sprite_E[i];
            const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, v.sprite_G[i]);
            v.sprite_y_vel[i] = pt.y;
            v.sprite_x_vel[i] = pt.x;
            if (v.sprite_G[i] < 64)
                v.sprite_G[i] +%= 1;
            a.Sprite_MoveXY(k);
        },
        6 => {
            if (v.sprite_delay_main[i] == 0) {
                v.dialogue_message_index.* = 0x141;
                a.Sprite_ShowMessageMinimal();
                v.sprite_ai_state[i] +%= 1;
                v.sprite_delay_main[i] = 80;
            }
        },
        7 => {
            if (v.sprite_anim_clock[i] != 0) {
                if (v.sprite_delay_main[i] == 0) {
                    v.sprite_ai_state[i] = 3;
                    v.sprite_delay_main[i] = 32;
                } else {
                    v.sprite_x_vel[i] = @bitCast(t.kAgahnim_Tab5[ix(k - 1)]);
                    v.sprite_y_vel[i] +%= 2;
                    a.Sprite_MoveXY(k);
                    const j = a.Sprite_Agahnim_ApplyMotionBlur(k);
                    if (j >= 0)
                        v.sprite_oam_flags[ix(j)] = 4;
                }
            } else {
                if (v.sprite_delay_main[i] == 0) {
                    v.sprite_ai_state[i] = 3;
                    v.sprite_delay_main[i] = 32;
                } else if (v.sprite_delay_main[i] == 64) {
                    v.sound_effect_2.* = 0x28;
                    v.tmp_counter.* = 1;
                    // The C spawns both decoys without checking the return, so a
                    // failed spawn would index at -1; kept as-is.
                    while (true) {
                        var info: a.SpriteSpawnInfo = undefined;
                        const j = a.Sprite_SpawnDynamicallyEx(k, 0x7A, &info, 2);
                        a.Sprite_SetSpawnedCoordinates(j, &info);
                        const ju = ix(j);
                        v.sprite_flags3[ju] = t.kAgahnim_Tab6[ix(j - 1)];
                        v.sprite_oam_flags[ju] = v.sprite_flags3[ju] & 15;
                        v.sprite_anim_clock[ju] = v.sprite_oam_flags[ju];
                        v.sprite_ai_state[ju] = v.sprite_ai_state[i];
                        v.sprite_delay_main[ju] = 32;
                        v.tmp_counter.* -%= 1;
                        if (sign8(v.tmp_counter.*)) break;
                    }
                }
            }
        },
        8 => {
            v.flag_block_link_menu.* = 2;
            v.sprite_head_dir[i] = 0;
            if (v.sprite_delay_main[i] >= 64) {
                v.sprite_hit_timer[i] |= 0xe0;
            } else {
                if (v.sprite_delay_main[i] == 1) {
                    a.Sprite_SpawnPhantomGanon(k);
                    v.music_control.* = 0x1d;
                }
                v.sprite_hit_timer[i] = 0;
                v.sprite_graphics[i] = 17;
            }
        },
        9 => {
            v.sprite_head_dir[i] = 0;
            const x = a.Sprite_GetX(0);
            const y = a.Sprite_GetY(0);
            if (v.cur_sprite_x.* -% x +% 4 < 8 and v.cur_sprite_y.* -% y +% 4 < 8)
                v.sprite_state[i] = 0;
            const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 0x20);
            v.sprite_y_vel[i] = pt.y;
            v.sprite_x_vel[i] = pt.x;
            a.Sprite_MoveXY(k);
            _ = a.Sprite_Agahnim_ApplyMotionBlur(k);
        },
        10 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_state[i] = 0;
                a.PrepareDungeonExitFromBossFight();
            }
            if (v.sprite_delay_main[i] < 16) {
                v.CGADSUB_copy.* = 0x7f;
                v.TM_copy.* = 6;
                v.TS_copy.* = 0x10;
                a.PaletteFilter_SP5F();
            }
            if (v.sprite_z_vel[i] != 0xff)
                v.sprite_z_vel[i] +%= 1;
            const j: c_int = @as(c_int, v.sprite_z_subpos[i]) + @as(c_int, v.sprite_z_vel[i]);
            v.sprite_z_subpos[i] = @truncate(@as(u32, @bitCast(j)));
            if (j & 0x100 != 0) {
                v.sprite_subtype2[i] +%= 1;
                if (v.sprite_subtype2[i] == 7) {
                    v.sprite_subtype2[i] = 0;
                    a.SpriteSfx_QueueSfx2WithPan(k, 0x4);
                }
            }
            v.sprite_graphics[i] = t.kAgahnim_Gfx3[v.sprite_subtype2[i]];
        },
        else => {},
    }
}

pub export fn Agahnim_PerformAttack(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (k == 0) {
        v.sprite_subtype[i] +%= 1;
        if (v.is_in_dark_world.* != 0)
            v.sprite_subtype[i] &= 3;
    }
    if (v.sprite_subtype[i] == 5) {
        v.sprite_subtype[i] = 0;
        a.SpriteSfx_QueueSfx3WithPan(k, 0x26);
        var n: usize = 0;
        while (n < 4) : (n += 1)
            _ = a.Sprite_SpawnLightning(k);
    } else {
        var info: a.SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 0x7B, &info);
        if (j >= 0) {
            const ju = ix(j);
            a.SpriteSfx_QueueSfx3WithPan(k, 0x29);
            const d: usize = v.sprite_D[i];
            a.Sprite_SetX(j, info.r0_x +% cm.s16(t.kAgahnim_X0[d]));
            a.Sprite_SetY(j, info.r2_y +% cm.s16(t.kAgahnim_Y0[d]));
            v.sprite_ignore_projectile[ju] = v.sprite_y_hi[ju];
            v.sprite_x_vel[ju] = v.sprite_x_vel[i];
            v.sprite_y_vel[ju] = v.sprite_y_vel[i];
            if (v.sprite_subtype[i] >= 2 and a.GetRandomNumber() & 1 == 0) {
                v.sprite_B[ju] = 1;
                v.sprite_delay_main[ju] = 32;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part81.zig
// ---------------------------------------------------------------------------
pub export fn Agahnim_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: a.PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;
    var oam = cm.oamPtr();
    var g: usize = v.sprite_graphics[i];

    // The C counts i down from 3 while advancing oam, so entry n takes 3 - n.
    var n: usize = 0;
    while (n < 4) : (n += 1) {
        const j: usize = g * 4 + (3 - n);
        const x = @as(c_int, info.x) + @as(c_int, t.kAgahnim_Draw_X0[j]);
        const y = @as(c_int, info.y) + @as(c_int, t.kAgahnim_Draw_Y0[j]);
        cm.setOamPlain(
            oam + n,
            @truncate(@as(u32, @bitCast(x))),
            @truncate(@as(u32, @bitCast(y))),
            t.kAgahnim_Draw_Char0[j],
            info.flags | t.kAgahnim_Draw_Flags0[j],
            if (j >= 0x40 and j < 0x44) 0 else 2,
        );
    }
    if (g < 12)
        a.SpriteDraw_Shadow_custom(k, &info, 18);
    if (v.submodule_index.* != 0)
        a.Sprite_CorrectOamEntries(k, 3, 0xff);

    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;

    if (v.sprite_D[i] != 0)
        _ = a.Oam_AllocateFromRegionC(8)
    else
        _ = a.Oam_AllocateFromRegionB(8);
    oam = cm.oamPtr();

    if (v.sprite_head_dir[i] == 0)
        return;
    g = v.sprite_head_dir[i] - 1;
    const flags: u8 = (((v.frame_counter.* >> 1) & 2) +% 2) +% 0x31;
    n = 0;
    while (n < 2) : (n += 1) {
        const j: usize = g * 2 + (1 - n);
        const x = @as(c_int, info.x) + @as(c_int, t.kAgahnim_Draw_X1[j]);
        const y = @as(c_int, info.y) + @as(c_int, t.kAgahnim_Draw_Y1[j]);
        cm.setOamPlain(
            oam + n,
            @truncate(@as(u32, @bitCast(x))),
            @truncate(@as(u32, @bitCast(y))),
            t.kAgahnim_Draw_Char1[g],
            flags,
            t.kAgahnim_Draw_Big1[g],
        );
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part82.zig
// ---------------------------------------------------------------------------
/// Not exported from its home file, so each porting module carries its own.

pub export fn Sprite_7B_AgahnimBalls(k: c_int) callconv(.c) void {
    const i = ix(k);

    if (v.sprite_B[i] != 0) {
        if (v.sprite_delay_main[i] != 0)
            a.Sprite_ApplySpeedTowardsLink(k, 32);
        v.sprite_oam_flags[i] = 5;
    } else {
        v.sprite_oam_flags[i] = ((v.frame_counter.* >> 1) & 2) +% 3;
    }

    if (v.sprite_ai_state[i] != 0) {
        // The short-lived spark left behind when a ball is deflected.
        if (v.sprite_graphics[i] != 2)
            a.SpriteDraw_SingleLarge(k)
        else
            a.SpriteDraw_SingleSmall(k);
        if (a.Sprite_ReturnIfInactive(k)) return;
        v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
        if (v.sprite_delay_main[i] == 0) {
            v.sprite_state[i] = 0;
        } else if (v.sprite_delay_main[i] == 6) {
            v.sprite_x_vel[i] = 64;
            v.sprite_y_vel[i] = 64;
            a.Sprite_MoveXY(k);
        }
        v.sprite_graphics[i] = t.kEnergyBall_Gfx[v.sprite_delay_main[i]];
        return;
    }

    if (v.sprite_B[i] != 0)
        a.SeekerEnergyBall_Draw(k)
    else
        a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    v.sprite_subtype2[i] +%= 1;
    a.Sprite_MoveXY(k);
    if (a.Sprite_CheckTileCollision(k) != 0) {
        v.sprite_state[i] = 0;
        if (v.sprite_B[i] != 0) {
            a.SpriteSfx_QueueSfx3WithPan(k, 0x36);
            a.CreateSixBlueBalls(k);
            return;
        }
    }

    if (v.sprite_A[i] != 0 and v.sprite_ignore_projectile[0] == 0) {
        // Already deflected once: now it hurts Agahnim instead of Link.
        var hb: a.SpriteHitBox = undefined;
        hb.r0_xlo = v.sprite_x_lo[i];
        hb.r8_xhi = v.sprite_x_hi[i];
        hb.r2 = 15;
        hb.r3 = 15;
        hb.r1_ylo = v.sprite_y_lo[i];
        hb.r9_yhi = v.sprite_y_hi[i];
        a.Sprite_SetupHitBox(0, &hb);
        if (a.CheckIfHitBoxesOverlap(&hb)) {
            a.Sprite_GiveDamage(0, 16, 0xa0);
            v.sprite_state[i] = 0;
            v.sprite_x_recoil[0] = v.sprite_x_vel[i];
            v.sprite_y_recoil[0] = v.sprite_y_vel[i];
        }
    } else {
        _ = a.Sprite_CheckDamageToLink(k);
        if (a.Sprite_CheckDamageFromLink(k) & kCheckDamageFromPlayer_Carry != 0) {
            if (v.sprite_B[i] != 0) {
                v.sprite_state[i] = 0;
                a.SpriteSfx_QueueSfx3WithPan(k, 0x36);
                a.CreateSixBlueBalls(k);
                return;
            }
            a.SpriteSfx_QueueSfx2WithPan(k, 0x5);
            a.SpriteSfx_QueueSfx3WithPan(k, 0x29);
            a.Sprite_ApplySpeedTowardsLink(k, 0x30);
            v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
            v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
            v.sprite_A[i] +%= 1;
        }
    }

    if ((k ^ @as(c_int, v.frame_counter.*)) & 3 | @as(c_int, v.sprite_B[i]) != 0)
        return;
    // Trail a short-lived spark behind the ball.
    var info: a.SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(k, 0x7B, &info);
    if (j < 0)
        return;
    const ju = ix(j);
    a.Sprite_SetSpawnedCoordinates(j, &info);
    v.sprite_delay_main[ju] = 15;
    v.sprite_ai_state[ju] = 15;
    v.sprite_B[ju] = v.sprite_B[i];
}

// ---------------------------------------------------------------------------
// from sprite_main_part83.zig
// ---------------------------------------------------------------------------
/// Not exported from its home file, so each porting module carries its own.

pub export fn Sprite_79_Bee(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_ai_state[i]) {
        0 => a.Bee_DormantHive(k),
        1 => Bee_Main(k),
        2 => a.Bee_PutInBottle(k),
        else => {},
    }
}

pub export fn ReleaseBeeFromBottle(x_value: c_int) callconv(.c) c_int {
    var info: a.SpriteSpawnInfo = undefined;
    const j = a.Sprite_SpawnDynamically(x_value, 0xb2, &info);
    if (j >= 0) {
        const ju = ix(j);
        v.sprite_floor[ju] = v.link_is_on_lower_level.*;
        a.Sprite_SetX(j, v.link_x_coord.* +% 8);
        a.Sprite_SetY(j, v.link_y_coord.* +% 16);
        // A gold bee keeps its identity through the bottle.
        if (v.link_bottle_info[ix(@as(c_int, v.link_item_bottle_index.*) - 1)] == 8)
            v.sprite_head_dir[ju] = 1;
        a.InitializeSpawnedBee(j);
        v.sprite_x_vel[ju] = @bitCast(t.kSpawnBee_XY[a.GetRandomNumber() & 7]);
        v.sprite_y_vel[ju] = @bitCast(t.kSpawnBee_XY[a.GetRandomNumber() & 7]);
        v.sprite_delay_main[ju] = 64;
        v.sprite_A[ju] = 64;
    }
    return j;
}

pub export fn Bee_Main(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Bee_HandleZ(k);
    a.SpriteDraw_SingleSmall(k);
    a.Bee_HandleInteractions(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (a.Sprite_ReturnIfRecoiling(k)) return;
    if (v.sprite_head_dir[i] != 0)
        a.Sprite_SpawnSparkleGarnish(k);
    a.Bee_Bzzt(k);
    a.Sprite_MoveXY(k);
    v.sprite_graphics[i] = @truncate(@as(u32, @bitCast(k ^ @as(c_int, v.frame_counter.*))) >> 1 & 1);

    if (v.sprite_delay_aux4[i] == 0) {
        _ = a.Sprite_CheckDamageToLink(k);
        if (a.Sprite_CheckDamageFromLink(k) & kCheckDamageFromPlayer_Ne != 0) {
            a.Sprite_ShowMessageUnconditional(0xc8);
            v.sprite_ai_state[i] = 2; // put in bottle
            return;
        }
    }

    // Every 256 frames the bee tires and picks a slower retarget interval.
    if (v.frame_counter.* == 0 and v.sprite_A[i] != 16)
        v.sprite_A[i] -%= 8;

    if (v.sprite_delay_main[i] == 0) {
        const x: u16 = v.link_x_coord.* +% (@as(u16, a.GetRandomNumber() & 3) * 5);
        const y: u16 = v.link_y_coord.* +% (@as(u16, a.GetRandomNumber() & 3) * 5);
        const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 20);
        v.sprite_y_vel[i] = pt.y;
        v.sprite_x_vel[i] = pt.x;
        v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & ~@as(u8, 0x40) |
            (if (sign8(pt.x)) @as(u8, 0) else 0x40);
        v.sprite_delay_main[i] = @truncate(@as(u32, @bitCast(k +% @as(c_int, v.sprite_A[i]))));
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part84.zig
// ---------------------------------------------------------------------------
/// None of these are exported from their home files, so this module carries
/// its own copies.

pub export fn Sprite_B2_PlayerBee(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_ai_state[i]) {
        0 => { // wait
            if (v.sprite_E[i] == 0) {
                v.sprite_state[i] = 0;
                const or_bottle = v.link_bottle_info[0] | v.link_bottle_info[1] |
                    v.link_bottle_info[2] | v.link_bottle_info[3];
                if (or_bottle & 8 == 0)
                    a.GoldBee_SpawnSelf(k);
            }
        },
        1 => { // activated
            v.sprite_ignore_projectile[i] = 1;
            a.Bee_HandleZ(k);
            a.SpriteDraw_SingleSmall(k);
            a.Bee_HandleInteractions(k);
            if (a.Sprite_ReturnIfInactive(k)) return;
            a.Bee_Bzzt(k);
            a.Sprite_MoveXY(k);
            v.sprite_graphics[i] = @truncate(@as(u32, @bitCast(k ^ @as(c_int, v.frame_counter.*))) >> 1 & 1);
            if (v.sprite_head_dir[i] != 0)
                a.Sprite_SpawnSparkleGarnish(k);
            // A bee only has so many stings in it.
            if (v.sprite_B[i] >= t.kGoodBee_Tab0[v.sprite_head_dir[i]]) {
                v.sprite_defl_bits[i] = 64;
                return;
            }
            if (v.sprite_delay_aux4[i] != 0)
                return;
            if (a.Sprite_CheckDamageFromLink(k) & kCheckDamageFromPlayer_Ne != 0) {
                a.Sprite_ShowMessageUnconditional(0xc8);
                v.sprite_ai_state[i] +%= 1;
                return;
            }
            if ((k ^ @as(c_int, v.frame_counter.*)) & 3 != 0)
                return;
            var pt2: a.Point16U = undefined;
            if (!PlayerBee_FindTarget(k, &pt2)) {
                pt2.x = v.link_x_coord.* +% (@as(u16, a.GetRandomNumber() & 3) * 5);
                pt2.y = v.link_y_coord.* +% (@as(u16, a.GetRandomNumber() & 3) * 5);
            }
            if ((k ^ @as(c_int, v.frame_counter.*)) & 7 != 0)
                return;
            const pt = a.Sprite_ProjectSpeedTowardsLocation(k, pt2.x, pt2.y, 32);
            v.sprite_x_vel[i] = pt.x;
            v.sprite_y_vel[i] = pt.y;
            v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & ~@as(u8, 0x40) |
                (if (sign8(pt.x)) @as(u8, 0) else 0x40);
        },
        2 => { // bottle
            a.Bee_PutInBottle(k);
        },
        else => {},
    }
}

pub export fn PlayerBee_FindTarget(k: c_int, pt: [*c]a.Point16U) callconv(.c) bool {
    var n: c_int = 16;
    var j: c_int = (k * 4) & 0xf;
    // A do-while in the C, so `continue` falls through to the decrement.
    while (true) {
        skip: {
            const ju = ix(j);
            if (j == k or v.sprite_state[ju] < 9 or v.sprite_pause[ju] != 0)
                break :skip;
            if (v.sprite_flags2[ju] & 0x80 == 0) {
                if (v.sprite_floor[ix(k)] != v.sprite_floor[ju] or
                    v.sprite_flags4[ju] & 0x40 != 0 or
                    v.sprite_ignore_projectile[ju] != 0)
                    break :skip;
            } else {
                // Only a gold bee will go after these.
                if (v.sprite_head_dir[ix(k)] == 0 or v.sprite_bump_damage[ju] & 0x40 == 0)
                    break :skip;
            }
            a.PlayerBee_HoneInOnTarget(j, k);
            pt.*.x = a.Sprite_GetX(j) +% (@as(u16, a.GetRandomNumber() & 3) * 5);
            pt.*.y = a.Sprite_GetY(j) +% (@as(u16, a.GetRandomNumber() & 3) * 5);
            return true;
        }
        j = (j - 1) & 0xf;
        n -= 1;
        if (n == 0) break;
    }
    return false;
}

pub export fn Sprite_B3_PedestalPlaque(k: c_int) callconv(.c) void {
    var info: a.PrepOamCoordsRet = undefined;
    a.Sprite_PrepOamCoord(k, &info);
    if (a.Sprite_ReturnIfInactive(k)) return;
    if (v.flag_is_link_immobilized.* == 0 and a.Sprite_CheckIfLinkIsBusy())
        return;

    v.link_position_mode.* &= ~@as(u8, 0x20);
    if (@as(u8, @truncate(v.overworld_screen_index.*)) != 48) {
        if (v.link_direction_facing.* != 0 or !a.Sprite_CheckDamageToLink_same_layer(k))
            return;
        if (v.hud_cur_item.* != kHudItem_BookMudora or v.filtered_joypad_H.* & 0x40 == 0) {
            if (v.filtered_joypad_L.* & 0x80 == 0)
                return;
            a.Sprite_ShowMessageUnconditional(0xb6);
        } else {
            v.player_handler_timer.* = 0;
            v.link_position_mode.* = 32;
            v.sound_effect_1.* = 0;
            a.Sprite_ShowMessageUnconditional(0xb7);
        }
    } else {
        // The desert palace plaque, which also opens the palace.
        if (v.link_direction_facing.* != 0 or !a.Sprite_CheckDamageToLink_same_layer(k))
            return;
        if (v.hud_cur_item.* != kHudItem_BookMudora or v.filtered_joypad_H.* & 0x40 == 0) {
            if (v.filtered_joypad_L.* & 0x80 == 0)
                return;
            a.Sprite_ShowMessageUnconditional(0xbc);
        } else {
            v.player_handler_timer.* = 0;
            v.link_position_mode.* = 32;
            v.sound_effect_1.* = 0;
            v.button_b_frames.* = 1;
            v.link_delay_timer_spin_attack.* = 0;
            v.link_player_handler_state.* = kPlayerState_OpeningDesertPalace;
            a.Sprite_ShowMessageUnconditional(0xbd);
        }
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part85.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_B6_Kiki(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_subtype2[i]) {
        0 => a.Kiki_LyingInwait(k),
        1 => Kiki_OfferEntranceService(k),
        2 => Kiki_OfferInitialService(k),
        3 => Kiki_Flee(k),
        else => {},
    }
}

pub export fn Kiki_Flee(k: c_int) callconv(.c) void {
    const i = ix(k);
    var flag = a.Kiki_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    // Despawn once he has scampered off the visible stretch of map.
    if (v.sprite_z[i] == 0 and
        v.cur_sprite_x.* -% 0xc98 < 0xd0 and
        v.cur_sprite_y.* -% 0x6a5 < 0xd0)
        flag = true;

    if (flag)
        v.sprite_state[i] = 0;
    v.sprite_z_vel[i] -%= 2;
    a.Sprite_MoveXYZ(k);
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = a.GetRandomNumber() & 15 | 16;
    }
    var pt = a.Sprite_ProjectSpeedTowardsLocation(k, 0xcf5, 0x6fe, 16);
    v.sprite_x_vel[i] = pt.x << 1;
    v.sprite_y_vel[i] = pt.y << 1;
    v.tagalong_event_flags.* &= ~@as(u8, 3);
    if (sign8(pt.x)) pt.x = 0 -% pt.x;
    if (sign8(pt.y)) pt.y = 0 -% pt.y;
    v.sprite_D[i] = if (pt.x >= pt.y)
        (v.sprite_x_vel[i] >> 7) ^ 3
    else
        (v.sprite_y_vel[i] >> 7) ^ 1;
    v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
}

pub export fn Kiki_OfferInitialService(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (!sign8(v.sprite_ai_state[i] -% 2))
        _ = a.Kiki_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_MoveXYZ(k);
    v.sprite_z_vel[i] -%= 1;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z_vel[i] = 0;
        v.sprite_z[i] = 0;
    }
    v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
    switch (v.sprite_ai_state[i]) {
        0 => {
            a.Sprite_ShowMessageUnconditional(0x11e);
            v.sprite_ai_state[i] +%= 1;
        },
        1 => {
            if (v.choice_in_multiselect_box.* == 0 and a.ShopItem_HandleCost(10)) {
                a.Sprite_ShowMessageUnconditional(0x11f);
                v.tagalong_event_flags.* |= 3;
                v.sprite_state[i] = 0;
            } else {
                a.Sprite_ShowMessageUnconditional(0x120);
                v.tagalong_event_flags.* &= ~@as(u8, 3);
                v.follower_indicator.* = 0;
                v.sprite_ai_state[i] +%= 1;
                v.flag_is_link_immobilized.* +%= 1;
            }
        },
        2 => {
            v.sprite_ai_state[i] +%= 1;
            const pt = a.Sprite_ProjectSpeedTowardsLocation(k, 0xc45, 0x6fe, 9);
            v.sprite_y_vel[i] = pt.y;
            v.sprite_x_vel[i] = pt.x;
            v.sprite_D[i] = (pt.x >> 7) ^ 3;
            v.sprite_delay_main[i] = 32;
        },
        3 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_z_vel[i] = 16;
                v.sprite_delay_main[i] = 16;
            }
        },
        4 => {
            if (v.sprite_delay_main[i] == 0 and v.sprite_z[i] == 0) {
                v.sprite_state[i] = 0;
                v.flag_is_link_immobilized.* = 0;
            }
        },
        else => {},
    }
}

pub export fn Kiki_OfferEntranceService(k: c_int) callconv(.c) void {
    const i = ix(k);
    _ = a.Kiki_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_MoveXYZ(k);
    v.sprite_z_vel[i] -%= 1;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z_vel[i] = 0;
        v.sprite_z[i] = 0;
    }
    switch (v.sprite_ai_state[i]) {
        0 => {
            a.Sprite_ShowMessageUnconditional(0x11b);
            v.sprite_ai_state[i] +%= 1;
        },
        1 => {
            if (v.choice_in_multiselect_box.* != 0 or !a.ShopItem_HandleCost(100)) {
                a.Sprite_ShowMessageUnconditional(0x11c);
                v.sprite_subtype2[i] = 3;
            } else {
                a.Sprite_ShowMessageUnconditional(0x11d);
                v.flag_is_link_immobilized.* +%= 1;
                v.sprite_ai_state[i] +%= 1;
                v.sprite_D[i] = 0;
            }
        },
        // Three walk legs, one per door position.
        2, 4, 6 => {
            v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
            const j: usize = (v.sprite_ai_state[i] >> 1) - 1;
            if (@as(u8, @truncate(t.kKiki_Leave_X[j] -% @as(u16, v.sprite_x_lo[i]) +% 2)) < 4 and
                @as(u8, @truncate(t.kKiki_Leave_Y[j] -% @as(u16, v.sprite_y_lo[i]) +% 2)) < 4)
            {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
                v.sprite_delay_aux1[i] = 32;
                a.SpriteSfx_QueueSfx2WithPan(k, 0x21);
                return;
            }
            const pt = a.Sprite_ProjectSpeedTowardsLocation(k, t.kKiki_Leave_X[j], t.kKiki_Leave_Y[j], 9);
            v.sprite_x_vel[i] = pt.x;
            v.sprite_y_vel[i] = pt.y;
        },
        // The hop between legs.
        3, 5 => {
            if (v.sprite_delay_aux1[i] == 0) {
                const old = v.sprite_ai_state[i];
                v.sprite_ai_state[i] +%= 1;
                v.sprite_z_vel[i] = t.kKiki_Zvel[(old >> 1) & 1];
                a.SpriteSfx_QueueSfx2WithPan(k, 0x20);
                v.sprite_D[i] = (v.sprite_ai_state[i] >> 1 & 1) | 4;
            } else {
                v.sprite_D[i] = (v.sprite_ai_state[i] >> 1 & 1) | 6;
                v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
            }
        },
        7 => {
            v.sprite_graphics[i] = v.frame_counter.* >> 3 & 1;
            if (v.sprite_z[i] != 0 or v.sprite_delay_main[i] != 0)
                return;
            const j: usize = v.sprite_A[i];
            v.sprite_A[i] +%= 1;
            const tv = t.kKiki_Tab7[j];
            if (!sign8(tv)) {
                v.sprite_D[i] = tv;
                v.sprite_delay_main[i] = t.kKiki_Delay7[j];
                v.sprite_x_vel[i] = @bitCast(t.kKiki_Xvel7[tv]);
                v.sprite_y_vel[i] = @bitCast(t.kKiki_Yvel7[tv]);
            } else {
                v.sprite_ai_state[i] +%= 1;
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
                v.trigger_special_entrance.* = 1;
                v.subsubmodule_index.* = 0;
                v.overworld_entrance_sequence_counter.* = 0;
                v.sprite_D[i] = 0;
                v.flag_is_link_immobilized.* = 0;
            }
        },
        8 => {
            v.sprite_D[i] = 8;
            v.sprite_graphics[i] = 0;
            v.sprite_z_vel[i] = (a.GetRandomNumber() & 15) +% 16;
            v.sprite_ai_state[i] +%= 1;
        },
        9 => {
            if (sign8(v.sprite_z_vel[i]) and v.sprite_z[i] == 0) {
                v.sprite_ai_state[i] +%= 1;
                a.SpriteSfx_QueueSfx3WithPan(k, 0x25);
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part86.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_AD_OldMan(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.OldMountainMan_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    switch (v.sprite_subtype2[i]) {
        0 => { // lost
            switch (v.sprite_ai_state[i]) {
                0 => { // supplicate
                    _ = a.Sprite_TrackBodyToHead(k);
                    v.sprite_head_dir[i] = a.Sprite_DirectionToFaceLink(k, null) ^ 3;
                    const j = a.Sprite_ShowMessageOnContact(k, 0x9c);
                    if (j & 0x100 != 0) {
                        v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast(j)));
                        v.sprite_D[i] = v.sprite_head_dir[i];
                        v.sprite_ai_state[i] = 1;
                    }
                },
                1 => { // switch to tagalong
                    v.follower_indicator.* = 4;
                    a.Sprite_BecomeFollower(k);
                    v.which_starting_point.* = 5;
                    v.sprite_state[i] = 0;
                    a.CacheCameraProperties();
                },
                else => {},
            }
        },
        1 => { // entering domicile
            a.Sprite_MoveXY(k);
            switch (v.sprite_ai_state[i]) {
                0 => { // grant mirror
                    v.sprite_ai_state[i] +%= 1;
                    v.item_receipt_method.* = 0;
                    a.Link_ReceiveItem(0x1a, 0);
                    v.which_starting_point.* = 1;
                    a.OldMan_EnableCutscene();
                    v.sprite_delay_main[i] = 48;
                    v.sprite_x_vel[i] = 8;
                    v.sprite_y_vel[i] = 4;
                    v.sprite_head_dir[i] = 3;
                    v.sprite_D[i] = 3;
                },
                1 => { // shuffle away
                    a.OldMan_EnableCutscene();
                    if (v.sprite_delay_main[i] == 0)
                        v.sprite_ai_state[i] +%= 1;
                    v.sprite_graphics[i] = @truncate(@as(u32, @bitCast(k ^ @as(c_int, v.frame_counter.*))) >> 3 & 1);
                },
                2 => { // approach door
                    v.sprite_head_dir[i] = 0;
                    v.sprite_D[i] = 0;
                    const j: usize = v.byte_7E0FDE.*;
                    const x: u16 = @as(u16, v.overlord_x_lo[j]) | (@as(u16, v.overlord_x_hi[j]) << 8);
                    const y: u16 = @as(u16, v.overlord_y_lo[j]) | (@as(u16, v.overlord_y_hi[j]) << 8);
                    if (y >= a.Sprite_GetY(k)) {
                        v.sprite_ai_state[i] +%= 1;
                        v.sprite_y_vel[i] = 0;
                        v.sprite_x_vel[i] = 0;
                    } else {
                        const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 8);
                        v.sprite_y_vel[i] = pt.y;
                        v.sprite_x_vel[i] = pt.x;
                        v.sprite_graphics[i] = @truncate(@as(u32, @bitCast(k ^ @as(c_int, v.frame_counter.*))) >> 3 & 1);
                        a.OldMan_EnableCutscene();
                    }
                },
                3 => { // made it inside
                    v.sprite_state[i] = 0;
                    v.flag_is_link_immobilized.* = 0;
                    v.link_disable_sprite_damage.* = 0;
                },
                else => {},
            }
        },
        2 => { // sitting at home
            a.Sprite_BehaveAsBarrier(k);
            if (v.sprite_ai_state[i] != 0) {
                v.link_hearts_filler.* = 160;
                v.sprite_ai_state[i] = 0;
            }
            const j: usize = if (v.sram_progress_indicator.* >= 3) 2 else v.link_item_moon_pearl.*;
            if (a.Sprite_ShowSolicitedMessage(k, t.kOldMountainManMsgs[j]) & 0x100 != 0)
                v.sprite_ai_state[i] +%= 1;
        },
        else => {},
    }
}

pub export fn Sprite_B8_DialogueTester(k: c_int) callconv(.c) void {
    _ = k;
    // assert(0) in the C: this sprite is a debugging stub that is never spawned.
    unreachable;
}

// ---------------------------------------------------------------------------
// from sprite_main_part87.zig
// ---------------------------------------------------------------------------
/// The C writes only the low byte of these 16-bit DMA slots.

pub export fn Kiki_Draw(k: c_int) callconv(.c) bool {
    const i = ix(k);
    var info: a.PrepOamCoordsRet = undefined;
    if (v.sprite_D[i] < 8) {
        const j: usize = @as(usize, v.sprite_D[i]) * 2 + v.sprite_graphics[i];
        // kKikiDma only holds 32 entries, so the high indices read past its
        // end, an out-of-bounds read the original game shipped with.
        dma_var6_lo[0] = t.kKikiDma[j * 2 + 0];
        dma_var7_lo[0] = t.kKikiDma[j * 2 + 1];
        a.Sprite_DrawMultiple(k, &t.kKiki_Dmd1[j * 2], 2, &info);
        if (v.sprite_pause[i] == 0)
            a.SpriteDraw_Shadow(k, &info);
    } else {
        a.Sprite_DrawMultiple(k, &t.kKiki_Dmd2[@as(usize, v.sprite_graphics[i]) * 6], 6, &info);
        if (v.sprite_pause[i] == 0)
            a.SpriteDraw_Shadow(k, &info);
    }
    return ((info.x | info.y) & 0xff00) != 0;
}

pub export fn Sprite_B9_BullyAndPinkBall(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_subtype2[i]) {
        0 => Sprite_PinkBall(k),
        1 => a.PinkBall_Distress(k),
        2 => a.Sprite_Bully(k),
        else => {},
    }
}

pub export fn Sprite_PinkBall(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Oam_AllocateDeferToPlayer(k);
    a.SpriteDraw_SingleLarge(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    a.PinkBall_HandleMessage(k);
    v.sprite_oam_flags[i] = v.sprite_oam_flags[i] & ~@as(u8, 0x80) | v.sprite_head_dir[i];
    a.Sprite_MoveXYZ(k);

    const tc = a.Sprite_CheckTileCollision(k);
    if (tc != 0) {
        // The C jumps into the second sound check, skipping the x flip.
        var play = false;
        if (tc & 3 == 0) {
            v.sprite_y_vel[i] = 0 -% v.sprite_y_vel[i];
            if (v.sprite_E[i] != 0) play = true;
        }
        if (!play) {
            v.sprite_x_vel[i] = 0 -% v.sprite_x_vel[i];
            if (v.sprite_E[i] != 0) play = true;
        }
        if (play)
            a.BallGuy_PlayBounceNoise(k);
    }

    v.sprite_z_vel[i] -%= 1;
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = (0 -% v.sprite_z_vel[i]) >> 2;
        if (v.sprite_z_vel[i] & 0xfc != 0)
            a.BallGuy_PlayBounceNoise(k);
        a.PinkBall_HandleDeceleration(k);
    }

    if (v.sprite_E[i] == 0) {
        if (v.sprite_head_dir[i] == 0) {
            a.PinkBall_Distress(k);
            v.sprite_graphics[i] = @truncate(@as(u32, @bitCast(k ^ @as(c_int, v.frame_counter.*))) >> 3 & 1);
            if ((k ^ @as(c_int, v.frame_counter.*)) & 0x3f == 0) {
                // Drift back towards Link's tile, but at a random offset in it.
                const x: u16 = (v.link_x_coord.* & 0xff00) | a.GetRandomNumber();
                const y: u16 = (v.link_y_coord.* & 0xff00) | a.GetRandomNumber();
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 8);
                v.sprite_B[i] = pt.x;
                v.sprite_A[i] = pt.y;
                if (pt.y != 0) {
                    v.sprite_oam_flags[i] |= 64;
                    v.sprite_oam_flags[i] ^= v.sprite_x_vel[i] >> 1 & 64;
                }
            }
            v.sprite_x_vel[i] = v.sprite_B[i];
            v.sprite_y_vel[i] = v.sprite_A[i];
        } else {
            a.PinkBall_Distress(k);
            if (k ^ @as(c_int, v.frame_counter.*) != 0) {
                v.sprite_graphics[i] = @truncate(@as(u32, @bitCast(k ^ @as(c_int, v.frame_counter.*))) >> 2 & 1);
                v.sprite_x_vel[i] = 0;
                v.sprite_y_vel[i] = 0;
            } else {
                v.sprite_head_dir[i] = 0;
            }
        }
    } else {
        if ((v.sprite_x_vel[i] | v.sprite_y_vel[i]) == 0) {
            v.sprite_E[i] = 0;
        } else {
            v.sprite_graphics[i] = @truncate(@as(u32, @bitCast(k ^ @as(c_int, v.frame_counter.*))) >> 2 & 1);
            v.sprite_head_dir[i] = @truncate(@as(u32, @bitCast((k ^ @as(c_int, v.frame_counter.*)) << 2)) & 128);
        }
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part88.zig
// ---------------------------------------------------------------------------
/// Not exported from player.zig, so this module carries its own copies.

pub export fn SomariaPlatform_LocatePath(k: c_int) callconv(.c) void {
    const i = ix(k);
    // Walk diagonally until a track tile turns up underneath.
    while (true) {
        const tiletype = a.SomariaPlatformAndPipe_CheckTile(k);
        v.sprite_E[i] = tiletype;
        if (tiletype >= 0xb0 and tiletype < 0xbf)
            break;
        a.Sprite_SetX(k, a.Sprite_GetX(k) +% 8);
        a.Sprite_SetY(k, a.Sprite_GetY(k) +% 8);
    }
    v.sprite_x_lo[i] = (v.sprite_x_lo[i] & ~@as(u8, 7)) +% 4;
    v.sprite_y_lo[i] = (v.sprite_y_lo[i] & ~@as(u8, 7)) +% 4;
    v.sprite_head_dir[i] = v.sprite_D[i];
    a.SomariaPlatformAndPipe_HandleMovement(k);
    v.sprite_ignore_projectile[i] +%= 1;
    v.player_on_somaria_platform.* = 0;
    v.sprite_delay_aux4[i] = 14;
    v.sprite_graphics[i] +%= 1;
}

pub export fn Sprite_ED_SomariaPlatform(k: c_int) callconv(.c) void {
    const i = ix(k);
    switch (v.sprite_graphics[i]) {
        0 => {
            SomariaPlatform_LocatePath(k);
            const j = a.Sprite_SpawnSuperficialBombBlast(k);
            if (j >= 0) {
                a.Sprite_SetX(j, a.Sprite_GetX(j) -% 8);
                a.Sprite_SetY(j, a.Sprite_GetY(j) -% 8);
            }
        },
        1 => {
            a.SomariaPlatform_Draw(k);
            if (a.Sprite_ReturnIfInactive(k)) return;
            if ((v.drag_player_x.* | v.drag_player_y.*) == 0 and
                sign8(v.player_near_pit_state.* -% 2) and
                a.Sprite_CheckDamageToLink_ignore_layer(k))
            {
                v.sprite_C[i] = 1;
                a.Link_CancelDash();
                if (v.link_player_handler_state.* != kPlayerState_Hookshot and
                    v.link_player_handler_state.* != kPlayerState_SpinAttacking)
                {
                    if (v.sprite_ai_state[i] != 0) {
                        a.SomariaPlatformAndPipe_HandleMovement(k);
                        return;
                    }
                    v.sprite_A[i] +%= 1;
                    v.player_on_somaria_platform.* = 2;
                    // Re-read the track every eighth frame; a new tile type
                    // means a junction or a turn.
                    if (v.sprite_A[i] & 7 == 0) {
                        const tile = a.SomariaPlatformAndPipe_CheckTile(k);
                        if (tile != v.sprite_E[i]) {
                            v.sprite_E[i] = tile;
                            v.sprite_head_dir[i] = v.sprite_D[i];
                            a.SomariaPlatformAndPipe_HandleMovement(k);
                            a.SomariaPlatform_HandleDrag(k);
                        }
                    }
                    if (@as(u8, @truncate(v.dungeon_room_index.*)) != 36) {
                        const j: usize = v.sprite_D[i];
                        v.drag_player_x.* +%= cm.s16(t.kSomariaPlatform_DragX[j]);
                        v.drag_player_y.* +%= cm.s16(t.kSomariaPlatform_DragY[j]);
                        a.Sprite_MoveXY(k);
                        a.SomariaPlatform_DragLink(k);
                    } else {
                        v.player_on_somaria_platform.* = 1;
                    }
                    return;
                }
            }
            if (v.sprite_C[i] != 0) {
                v.player_on_somaria_platform.* = 0;
                v.sprite_C[i] = 0;
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part89.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_52_KingZora(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.ZoraKing_Draw(k);
    if (a.Sprite_ReturnIfInactive(k)) return;
    switch (v.sprite_ai_state[i]) {
        0 => { // WaitingForPlayer
            if (v.link_x_coord.* -% v.cur_sprite_x.* +% 16 < 32 and
                v.link_y_coord.* -% v.cur_sprite_y.* +% 48 < 96)
            {
                a.Link_CancelDash();
                v.sprite_delay_main[i] = 127;
                v.sound_effect_1.* = 0x35;
                v.sprite_ai_state[i] = 1;
                // Clear the pool of everything else before the cutscene.
                var j: c_int = 15;
                while (j >= 0) : (j -= 1) {
                    const ju = ix(j);
                    if (j != k and v.sprite_defl_bits[ju] & 0x80 == 0) {
                        if (v.sprite_state[ju] == 10) {
                            v.link_state_bits.* = 0;
                            v.link_picking_throw_state.* = 0;
                        }
                        a.Sprite_KillSelf(j);
                    }
                }
            }
        },
        1 => { // RumblingGround
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 2;
                v.sprite_delay_main[i] = 127;
                v.bg1_x_offset.* = 0;
                v.sprite_graphics[i] = 4;
            } else {
                v.bg1_x_offset.* = if (v.sprite_delay_main[i] & 1 != 0) 0xffff else 1;
                v.flag_is_link_immobilized.* = 1;
            }
        },
        2 => { // Surfacing
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 3;
                v.sprite_delay_main[i] = 127;
            } else {
                if (v.sprite_delay_main[i] == 28) {
                    v.sprite_delay_aux2[i] = 15;
                    Sprite_SpawnBigSplash(k);
                }
                v.sprite_graphics[i] = t.kZoraKing_Surfacing_Gfx[v.sprite_delay_main[i] >> 3];
            }
        },
        3 => { // Dialogue
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                v.sprite_ai_state[i] = 4;
                v.sprite_delay_main[i] = 36;
                return;
            }
            v.sprite_graphics[i] = t.kZoraKing_Dialogue_Gfx[j >> 4];
            if (j == 80) {
                v.dialogue_message_index.* = 0x142;
                a.Sprite_ShowMessageMinimal();
            } else if (j == 79) {
                if (v.choice_in_multiselect_box.* == 0) {
                    v.dialogue_message_index.* = 0x143;
                    a.Sprite_ShowMessageMinimal();
                } else {
                    v.dialogue_message_index.* = 0x146;
                    a.Sprite_ShowMessageMinimal();
                    v.sprite_delay_main[i] = 0x30;
                }
            } else if (j == 78) {
                if (v.choice_in_multiselect_box.* == 0 and v.link_rupees_goal.* >= 500) {
                    v.link_rupees_goal.* -%= 500;
                    v.dialogue_message_index.* = 0x144;
                    a.Sprite_ShowMessageMinimal();
                    v.sprite_E[i] = 1;
                } else {
                    v.dialogue_message_index.* = 0x145;
                    a.Sprite_ShowMessageMinimal();
                    v.sprite_delay_main[i] = 0x30;
                }
            } else if (j == 77) {
                if (v.sprite_E[i] != 0)
                    a.Sprite_Zora_RegurgitateFlippers(k);
            }
        },
        4 => { // Submerge
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                a.Sprite_KillSelf(k);
                v.flag_is_link_immobilized.* = 0;
            } else {
                if (j == 29) {
                    v.sprite_delay_aux2[i] = 15;
                    Sprite_SpawnBigSplash(k);
                }
                v.sprite_graphics[i] = t.kZoraKing_Submerge_Gfx[v.sprite_delay_main[i] >> 1];
            }
        },
        else => {},
    }
}

pub export fn Sprite_SpawnBigSplash(k: c_int) callconv(.c) void {
    a.SpriteSfx_QueueSfx2WithPan(k, 0x24);

    // A ring of eight droplets thrown outwards.
    var n: usize = 8;
    while (n > 0) {
        n -= 1;
        var info: a.SpriteSpawnInfo = undefined;
        const j = a.Sprite_SpawnDynamically(k, 8, &info);
        if (j >= 0) {
            const ju = ix(j);
            v.sprite_state[ju] = 3;
            a.Sprite_SetX(j, info.r0_x +% cm.s16(t.kSpawnSplashRing_X[n]) -% 4);
            a.Sprite_SetY(j, info.r2_y +% cm.s16(t.kSpawnSplashRing_Y[n]) -% 4);
            v.sprite_x_vel[ju] = @bitCast(t.kSpawnSplashRing_Xvel[n]);
            v.sprite_y_vel[ju] = @bitCast(t.kSpawnSplashRing_Yvel[n]);
            v.sprite_A[ju] = @truncate(n);
            v.sprite_z_vel[ju] = (a.GetRandomNumber() & 15) +% 24;
            v.sprite_ai_state[ju] = 1;
            v.sprite_z[ju] = 0;
            v.sprite_flags3[ju] |= 0x40;
            v.sprite_ignore_projectile[ju] = v.sprite_flags3[ju];
        }
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part90.zig
// ---------------------------------------------------------------------------
pub export fn ZoraKing_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    var info: a.PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;

    if (v.sprite_ai_state[i] >= 2) {
        const oam = cm.oamPtr();
        const g: usize = v.sprite_graphics[i];
        // The C counts i down from 3 while advancing oam, so entry n takes 3 - n.
        var n: usize = 0;
        while (n < 4) : (n += 1) {
            const j: usize = g * 4 + (3 - n);
            oam[n].x = @truncate(@as(u32, @bitCast(@as(c_int, t.kZoraKing_Draw_X0[j]) + @as(c_int, info.x))));
            oam[n].y = @truncate(@as(u32, @bitCast(@as(c_int, t.kZoraKing_Draw_Y0[j]) + @as(c_int, info.y))));
            oam[n].charnum = t.kZoraKing_Draw_Char0[j];
            const f = t.kZoraKing_Draw_Flags0[j];
            oam[n].flags = (if (f & 0xf != 0) f else f | info.flags) | 0x20;
        }
        a.Sprite_CorrectOamEntries(k, 3, 2);
        if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
            return;
    }

    if (v.sprite_delay_aux2[i] == 0)
        return;

    // The splash thrown up as he surfaces or submerges.
    _ = a.Oam_AllocateFromRegionC(0x10);
    const oam = cm.oamPtr();
    const g: usize = (v.sprite_delay_aux2[i] >> 1) & 4;
    var n: usize = 0;
    while (n < 4) : (n += 1) {
        const j: usize = g + (3 - n);
        const x = @as(c_int, t.kZoraKing_Draw_X1[j]) + @as(c_int, info.x);
        const y = @as(c_int, t.kZoraKing_Draw_Y1[j]) + @as(c_int, info.y);
        cm.setOamPlain(
            oam + n,
            @truncate(@as(u32, @bitCast(x))),
            @truncate(@as(u32, @bitCast(y))),
            t.kZoraKing_Draw_Char1[j],
            t.kZoraKing_Draw_Flags1[j] | 0x24,
            2,
        );
    }
}

pub export fn Sprite_56_WalkingZora(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (v.sprite_F[i] != 0) {
        // Knocked back: halve the recoil into a slide.
        v.sprite_F[i] = 0;
        v.sprite_B[i] = 3;
        v.sprite_G[i] = 192;
        v.sprite_x_vel[i] = @bitCast(@as(i8, @bitCast(v.sprite_x_recoil[i])) >> 1);
        v.sprite_y_vel[i] = @bitCast(@as(i8, @bitCast(v.sprite_y_recoil[i])) >> 1);
    }
    var info: a.PrepOamCoordsRet = undefined;
    switch (v.sprite_B[i]) {
        0 => { // Waiting
            a.Sprite_PrepOamCoord(k, &info);
            if (a.Sprite_ReturnIfInactive(k)) return;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 127;
                v.sprite_B[i] +%= 1;
                v.sprite_flags3[i] |= 64;
            }
        },
        1 => { // Surfacing
            a.Zora_Draw(k);
            if (a.Sprite_ReturnIfInactive(k)) return;
            v.sprite_ignore_projectile[i] = v.sprite_delay_main[i];
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_flags3[i] &= ~@as(u8, 0x40);
                a.SpriteSfx_QueueSfx2WithPan(k, 0x28);
                v.sprite_B[i] +%= 1;
                v.sprite_z_vel[i] = 48;
                v.sprite_D[i] = a.Sprite_DirectionToFaceLink(k, null);
                v.sprite_head_dir[i] = v.sprite_D[i];
            } else {
                v.sprite_graphics[i] = t.kSprite_Zora_SurfacingGfx[v.sprite_delay_main[i] >> 3];
            }
        },
        2 => { // Ambulating
            v.sprite_graphics[i] = @bitCast(t.kSprite_Recruit_Gfx[(v.sprite_subtype2[i] >> 1 & 4) + v.sprite_D[i]]);
            a.WalkingZora_Draw(k);
            if (a.Sprite_ReturnIfInactive(k)) return;
            _ = a.Sprite_CheckDamageToAndFromLink(k);
            a.Sprite_MoveZ(k);
            v.sprite_z_vel[i] -%= 2;
            if (sign8(v.sprite_z[i] -% 1)) {
                if (sign8(v.sprite_z_vel[i] +% 16))
                    a.Sprite_ZeroVelocity_XY(k);
                v.sprite_z[i] = 0;
                v.sprite_z_vel[i] = 0;
                if ((k ^ @as(c_int, v.frame_counter.*)) & 15 == 0) {
                    const j = a.Sprite_DirectionToFaceLink(k, null);
                    v.sprite_head_dir[i] = j;
                    if ((k ^ @as(c_int, v.frame_counter.*)) & 31 == 0) {
                        v.sprite_D[i] = j;
                        a.Sprite_ApplySpeedTowardsLink(k, 8);
                    }
                }
            }
            a.Sprite_MoveXY(k);
            _ = a.Sprite_CheckTileCollision(k);
            if (sign8(v.sprite_z[i] -% 1)) {
                a.WalkingZora_AdjustShadow(k);
                // Deep water: dive and vanish.
                if (v.sprite_tiletype.* == 8) {
                    a.Sprite_KillSelf(k);
                    a.SpriteSfx_QueueSfx2WithPan(k, 0x28);
                    v.sprite_state[i] = 3;
                    v.sprite_delay_main[i] = 15;
                    v.sprite_ai_state[i] = 0;
                    v.sprite_flags2[i] = 3;
                }
            }
            v.sprite_subtype2[i] +%= 1;
        },
        3 => { // Depressed
            _ = a.Sprite_CheckDamageFromLink(k);
            if (v.frame_counter.* & 3 == 0) {
                v.sprite_G[i] -%= 1;
                if (v.sprite_G[i] == 0) {
                    v.sprite_B[i] = 2;
                    if (v.sprite_state[i] == 10) {
                        v.link_state_bits.* = 0;
                        v.link_picking_throw_state.* = 0;
                    }
                    v.sprite_state[i] = 9;
                }
            }
            if (v.sprite_G[i] < 48 and v.frame_counter.* & 1 == 0)
                a.Sprite_SetX(k, a.Sprite_GetX(k) +% (if (v.frame_counter.* & 2 != 0) @as(u16, 0xffff) else 1));
            v.sprite_graphics[i] = 0;
            v.sprite_wallcoll[i] = 0;
            a.WalkingZora_DrawWaterRipples(k);
            v.sprite_flags2[i] -%= 2;
            a.SpriteDraw_SingleLarge(k);
            v.sprite_flags2[i] +%= 2;
            v.sprite_anim_clock[i] = 0;
            if (a.Sprite_ReturnIfInactive(k)) return;
            if (a.Sprite_ReturnIfRecoiling(k)) return;
            a.Sprite_MoveXY(k);
            a.ThrownSprite_TileAndSpriteInteraction(k);
            a.WalkingZora_AdjustShadow(k);
        },
        else => {},
    }
}

pub export fn SpritePrep_RunningMan(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_head_dir[i] = 2;
    v.sprite_D[i] = 2;
    v.sprite_ignore_projectile[i] +%= 1;
}

// ---------------------------------------------------------------------------
// from sprite_main_part91.zig
// ---------------------------------------------------------------------------
/// misc.h keeps this a `static inline` with no linkable symbol, and it searches
/// *backwards*.

pub export fn SpritePrep_Adults(k: c_int) callconv(.c) void {
    const i = ix(k);
    v.sprite_ignore_projectile[i] +%= 1;
    // Not found yields -1, which the C narrows to 255.
    const j = FindInByteArray(&t.kHumanMultiTypes, @truncate(v.dungeon_room_index.*), 3);
    v.sprite_subtype2[i] = @truncate(@as(u32, @bitCast(j)));
}

pub export fn SpritePrep_Moldorm(k: c_int) callconv(.c) void {
    const i = ix(k);
    if (a.Sprite_ReturnIfBossFinished(k))
        return;
    v.sprite_ignore_projectile[i] +%= 1;
    a.Sprite_InitializedSegmented(k);
}

// ---------------------------------------------------------------------------
// from sprite_main_part92.zig
// ---------------------------------------------------------------------------
pub export fn Smithy_Main(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Smithy_Draw(k);
    v.sprite_z_vel[i] -%= 2;
    a.Sprite_MoveZ(k);
    if (sign8(v.sprite_z[i])) {
        v.sprite_z[i] = 0;
        v.sprite_z_vel[i] = 0;
    }
    if (a.Sprite_ReturnIfInactive(k)) return;

    // Both smiths hammer in step; either one being mid-temper drives the loop.
    const st_e = v.sprite_ai_state[ix(v.sprite_E[i])];
    const st_k = v.sprite_ai_state[i];
    if (st_e == 5 or st_e == 7 or st_e == 9 or
        st_k == 5 or st_k == 7 or st_k == 9 or
        (st_k | st_e) == 0)
    {
        // The C post-decrements, so the test sees the value before the step.
        const old_b = v.sprite_B[i];
        v.sprite_B[i] -%= 1;
        if (old_b == 0) {
            const j: usize = v.sprite_A[i];
            v.sprite_A[i] = @truncate((j + 1) & 7);
            v.sprite_graphics[i] = t.kSmithy_Gfx[j];
            v.sprite_B[i] = t.kSmithy_B[j];
            if (j == 1)
                v.sprite_z_vel[i] = 16;
            if (j == 3) {
                a.Smithy_SpawnSpark(k);
                a.SpriteSfx_QueueSfx2WithPan(k, 0x5);
            }
        }
    }

    switch (v.sprite_ai_state[i]) {
        0 => { // ConversationStart
            v.sprite_C[i] = 0;
            if (v.follower_indicator.* != 8) {
                if (a.Smithy_ListenForHammer(k)) {
                    a.Sprite_ShowMessageUnconditional(0xe4);
                    v.sprite_delay_aux1[i] = 96;
                    v.sprite_C[i] +%= 1;
                } else if (v.sram_progress_indicator_3.* & 0x20 != 0) {
                    if (a.Sprite_ShowSolicitedMessage(k, 0xd8) & 0x100 != 0) {
                        v.sprite_ai_state[i] +%= 1;
                        v.sprite_C[i] +%= 1;
                    }
                } else {
                    _ = a.Sprite_ShowSolicitedMessage(k, 0xdf);
                }
            } else {
                if (@as(u8, @truncate(v.link_y_coord.*)) < 0xc2) {
                    a.Sprite_ShowMessageUnconditional(0xe0);
                    v.sprite_ai_state[i] = 10;
                    v.flag_is_link_immobilized.* +%= 1;
                }
            }
        },
        1 => { // ProvideTemperingChoice
            if (v.choice_in_multiselect_box.* == 0) {
                a.Sprite_ShowMessageUnconditional(0xd9);
                v.sprite_ai_state[i] = 2;
            } else {
                a.Sprite_ShowMessageUnconditional(0xdc);
                v.sprite_ai_state[i] = 0;
            }
        },
        2 => { // HandleTemperingChoice
            if (v.choice_in_multiselect_box.* == 0) {
                if (v.link_sword_type.* < 3) {
                    a.Sprite_ShowMessageUnconditional(0xda);
                    v.sprite_ai_state[i] = 3;
                } else {
                    a.Sprite_ShowMessageUnconditional(0xdb);
                    v.sprite_ai_state[i] = 0;
                }
            } else {
                a.Sprite_ShowMessageUnconditional(0xdc);
                v.sprite_ai_state[i] = 0;
            }
        },
        3 => { // HandleTemperingCost
            if (v.choice_in_multiselect_box.* != 0 or v.link_rupees_goal.* < 10) {
                a.Sprite_ShowMessageUnconditional(0xdc);
                v.sprite_ai_state[i] = 0;
            } else {
                v.link_rupees_goal.* -%= 10;
                a.Sprite_ShowMessageUnconditional(0xdd);
                v.sprite_ai_state[ix(v.sprite_E[i])] = 5;
                v.sprite_ai_state[i] = 5;
                v.flag_overworld_area_did_change.* = 0;
                v.link_sword_type.* = 255;
                v.sram_progress_indicator_3.* |= 128;
            }
        },
        4, 5 => { // TemperingSword
            v.sprite_C[i] = 0;
            if (a.Smithy_ListenForHammer(k)) {
                a.Sprite_ShowMessageUnconditional(0xe4);
                v.sprite_delay_aux1[i] = 96;
                v.sprite_C[i] +%= 1;
            } else if (v.flag_overworld_area_did_change.* != 0) {
                if (a.Sprite_ShowSolicitedMessage(k, 0xde) & 0x100 != 0) {
                    v.sprite_ai_state[i] +%= 1;
                    v.sprite_graphics[i] = 4;
                }
            } else {
                _ = a.Sprite_ShowSolicitedMessage(k, 0xe2);
            }
        },
        6 => { // Smithy_GiveTemperedSword
            v.sprite_ai_state[i] = 0;
            v.sprite_ai_state[ix(v.sprite_E[i])] = 0;
            v.item_receipt_method.* = 0;
            a.Link_ReceiveItem(2, 0);
            v.sram_progress_indicator_3.* &= ~@as(u8, 0x80);
        },
        7, 8, 9 => {},
        10 => { // Smithy_SpawnFriend
            var info: a.SpriteSpawnInfo = undefined;
            const j = a.Sprite_SpawnDynamically(k, 0x1a, &info);
            if (j >= 0) {
                const ju = ix(j);
                a.Sprite_SetX(j, v.link_x_coord.*);
                a.Sprite_SetY(j, v.link_y_coord.*);
                v.sprite_subtype2[ju] = 3;
                v.sprite_ignore_projectile[ju] = 3;
            }
            v.sprite_ai_state[i] = 11;
            v.follower_indicator.* = 0;
            v.sprite_graphics[i] = 4;
        },
        11 => { // Smithy_CopiouslyThankful
            _ = a.Sprite_ShowSolicitedMessage(k, 0xe3);
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part93.zig
// ---------------------------------------------------------------------------
pub export fn PushSwitch_Draw(k: c_int) callconv(.c) void {
    const i = ix(k);
    a.Oam_AllocateDeferToPlayer(k);
    var info: a.PrepOamCoordsRet = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info))
        return;

    const flags: u8 = if (v.palette_swap_flag.* != 0)
        v.sprite_oam_flags[i] | 0xe
    else
        v.sprite_oam_flags[i] & ~@as(u8, 0xe);
    v.sprite_oam_flags[i] = flags;
    const r1: u8 = v.sprite_B[i] >> 2 & 3;

    v.oam_cur_ptr.* +%= 4;
    v.oam_ext_cur_ptr.* +%= 1;

    // The C memcpy's five signed OAM templates over the live entries.
    const oam = cm.oamPtr();
    const base: usize = @as(usize, v.sprite_D[i]) * 5;
    var n: usize = 0;
    while (n < 5) : (n += 1) {
        const src = t.kPushSwitch_Oam[base + n];
        oam[n].x = @bitCast(src.x);
        oam[n].y = @bitCast(src.y);
        oam[n].charnum = src.charnum;
        oam[n].flags = src.flags;
    }

    const dm_lo: u8 = @truncate(v.dungmap_var7.*);
    const dm_hi: u8 = @truncate(v.dungmap_var7.* >> 8);
    const xv: u8 = (0 -% r1) +% dm_lo;
    const yv: u8 = dm_hi -% (r1 >> 1);

    // The first four entries are the depressible part; the fifth is the base.
    n = 0;
    while (n < 4) : (n += 1) {
        oam[n].x +%= xv;
        oam[n].y +%= yv;
    }
    oam[4].x +%= dm_lo;
    oam[4].y +%= dm_hi;
    n = 0;
    while (n < 5) : (n += 1)
        oam[n].flags |= flags;

    const big: [*]u8 = @ptrCast(&v.g_ram[v.oam_ext_cur_ptr.*]);
    big[0] = 0;
    big[1] = 0;
    big[2] = 0;
    big[3] = 0;
    big[4] = 2;

    a.Sprite_CorrectOamEntries(k, 4, 0xff);

    if (v.sprite_floor[i] == v.link_is_on_lower_level.*) {
        v.sprite_C[i] = 0;
        const d: usize = v.sprite_D[i];
        // The hitbox indexes the template table by 4, not the 5 used above.
        const x = a.Sprite_GetX(k) +% cm.s16(t.kPushSwitch_Oam[d * 4].x);
        const y = a.Sprite_GetY(k) +% cm.s16(t.kPushSwitch_Oam[d * 4].y);

        var hb: a.SpriteHitBox = undefined;
        hb.r4_spr_xlo = @truncate(x);
        hb.r10_spr_xhi = @truncate(x >> 8);
        hb.r5_spr_ylo = @truncate(y);
        hb.r11_spr_yhi = @truncate(y >> 8);
        hb.r6_spr_xsize = t.kPushSwitch_WH[d * 2 + 0];
        hb.r7_spr_ysize = t.kPushSwitch_WH[d * 2 + 1];
        a.Link_SetupHitBox(&hb);
        if (a.CheckIfHitBoxesOverlap(&hb)) {
            // Probe from 19px lower so only an approach from above counts.
            const oldy = a.Sprite_GetY(k);
            a.Sprite_SetY(k, oldy +% 19);
            const new_dir = a.Sprite_DirectionToFaceLink(k, null);
            a.Sprite_SetY(k, oldy);
            if (new_dir == 0 and v.link_direction_facing.* == 4)
                v.sprite_C[i] +%= 1;
        } else {
            if (!a.Sprite_CheckDamageToLink_same_layer(k))
                return;
        }
        a.Sprite_NullifyHookshotDrag();
        v.link_speed_setting.* = 0;
        a.Sprite_RepelDash();
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_part94.zig
// ---------------------------------------------------------------------------
pub export fn Sprite_D6_Ganon(k: c_int) callconv(.c) void {
    const i = ix(k);

    // A negative state marks one of the after-images he leaves while warping.
    if (sign8(v.sprite_ai_state[i])) {
        if (a.Sprite_ReturnIfInactive(k)) return;
        if (v.sprite_delay_main[i] == 0)
            v.sprite_state[i] = 0;
        if (v.sprite_delay_main[i] & 1 == 0)
            a.Ganon_Draw(k);
        return;
    }

    if (v.sprite_delay_aux4[i] != 0)
        v.sprite_graphics[i] = t.kGanon_GfxB[v.sprite_D[i]];

    if (v.byte_7E04C5.* == 2 and v.byte_7E04C5.* != v.sprite_room[i])
        v.sprite_delay_aux1[i] = 64;
    v.sprite_room[i] = v.byte_7E04C5.*;

    a.Ganon_Draw(k);
    if (v.sprite_delay_aux1[i] != 0) {
        v.sprite_graphics[i] = 15;
        a.Ganon_EnableInvincibility(k);
        _ = a.Sprite_CheckDamageToAndFromLink(k);
        return;
    }

    if (a.Sprite_ReturnIfInactive(k)) return;

    if (v.sprite_delay_aux2[i] == 1)
        a.Ganon_ExtinguishTorch()
    else if (v.sprite_delay_aux2[i] == 16)
        a.Ganon_ExtinguishTorch_adjust_translucency();

    const pair = a.Sprite_IsRightOfLink(k);
    v.sprite_head_dir[i] = if (pair.b +% 32 < 64) 1 else t.kGanon_HeadDir0[pair.a];

    if (v.sprite_delay_aux4[i] != 0) {
        v.sprite_ignore_projectile[i] = v.sprite_delay_aux4[i];
        if (a.Sprite_ReturnIfRecoiling(k)) return;
        v.sprite_delay_main[i] = 0;
        return;
    }

    if ((v.sprite_ignore_projectile[i] | v.flag_is_link_immobilized.*) == 0 and v.byte_7E04C5.* == 2)
        _ = a.Sprite_CheckDamageToAndFromLink(k);
    v.sprite_ignore_projectile[i] = 0;

    switch (v.sprite_ai_state[i]) {
        0 => {
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 1;
                v.sprite_delay_main[i] = 128;
            } else if (v.sprite_delay_main[i] == 32) {
                v.music_control.* = 0x1f;
            } else if (v.sprite_delay_main[i] == 64) {
                v.dialogue_message_index.* = 0x16f;
                a.Sprite_ShowMessageMinimal();
            }
        },
        1 => {
            if (v.sprite_health[i] < 209)
                v.sprite_health[i] = 208;
            if (v.sprite_delay_main[i] < 64) {
                if (v.sprite_delay_main[i] == 0) {
                    a.Ganon_SelectWarpLocation(k, 5);
                } else {
                    v.sprite_graphics[i] = t.kGanon_Gfx1[v.sprite_D[i]];
                }
            } else if (v.sprite_delay_main[i] != 64) {
                a.Ganon_Phase1_AnimateTridentSpin(k);
            } else {
                // Launch the trident on the frame the wind-up ends.
                v.sprite_G[i] = 0;
                var info: a.SpriteSpawnInfo = undefined;
                const j = a.Sprite_SpawnDynamically(k, 0xc9, &info);
                const ju = ix(j);
                const d: usize = v.sprite_D[i];
                a.Sprite_SetX(j, info.r0_x +% cm.s16(t.kGanon_X1[d]));
                a.Sprite_SetY(j, info.r2_y +% cm.s16(t.kGanon_Y1[d]));
                a.Sprite_ApplySpeedTowardsLink(k, 31);
                const angle = a.Sprite_ConvertVelocityToAngle(v.sprite_x_vel[i], v.sprite_y_vel[i]);
                v.sprite_x_vel[ju] = @bitCast(t.kGanon_Xvel1[angle -% 2 & 0xf]);
                v.sprite_y_vel[ju] = @bitCast(t.kGanon_Yvel1[angle -% 2 & 0xf]);
                v.sprite_delay_main[ju] = 112;
                v.sprite_anim_clock[ju] = 2;
                v.sprite_oam_flags[ju] = 1;
                v.sprite_flags2[ju] = 4;
                v.sprite_defl_bits[ju] = 0x84;
                v.sprite_D[ju] = 2;
                v.sprite_bump_damage[ju] = 7;
                v.sprite_ignore_projectile[ju] = 7;
            }
        },
        2 => {
            if (v.sprite_health[i] < 209)
                v.sprite_health[i] = 208;
            v.sprite_graphics[i] = t.kGanon_Gfx2_0[v.sprite_D[i]];
            if (v.sprite_delay_main[i] != 0) {
                v.sprite_ignore_projectile[i] +%= 1;
                if (v.sprite_delay_main[i] & 1 != 0)
                    v.sprite_graphics[i] = 255;
            }
        },
        3 => {
            if (v.sprite_health[i] < 209)
                v.sprite_health[i] = 208;
            if (v.sprite_delay_main[i] != 0) {
                a.Ganon_Phase1_AnimateTridentSpin(k);
            } else {
                v.sprite_ai_state[i] = 6;
                v.sprite_delay_main[i] = 127;
                a.Ganon_HandleAnimation_Idle(k);
            }
        },
        4 => {
            if (v.sprite_health[i] < 209)
                v.sprite_health[i] = 208;
            if (v.sprite_delay_main[i] != 0)
                a.Ganon_ShakeHead(k)
            else
                a.Ganon_SelectWarpLocation(k, 5);
        },
        // Case 13 falls through into the shared warp-chase body in the C.
        13, 5, 10, 18 => {
            if (v.sprite_ai_state[i] == 13)
                v.sprite_health[i] = 100;

            v.sprite_ignore_projectile[i] +%= 1;
            const x: u16 = (@as(u16, v.sprite_x_hi[i]) << 8) | v.swamola_target_x_lo[0];
            const y: u16 = (@as(u16, v.sprite_y_hi[i]) << 8) | v.swamola_target_y_lo[0];
            if (a.Ganon_AttemptTridentCatch(x, y)) {
                v.sprite_D[i] = v.sprite_subtype[i] >> 2;
                if (v.sprite_ai_state[i] == 5) {
                    v.sprite_ai_state[i] = 2;
                    v.sprite_delay_main[i] = 32;
                } else if (v.sprite_health[i] >= 161) {
                    v.sprite_ai_state[i] = 11;
                    v.sprite_delay_main[i] = 40;
                } else if (v.sprite_health[i] >= 97) {
                    v.sprite_ai_state[i] = 14;
                    v.sprite_delay_main[i] = 40;
                } else {
                    v.sprite_ai_state[i] = 17;
                    v.sprite_delay_main[i] = 104;
                }
            } else {
                const pt = a.Sprite_ProjectSpeedTowardsLocation(k, x, y, 32);
                a.Sprite_ApproachTargetSpeed(k, pt.x, pt.y);
                a.Sprite_MoveXY(k);
                if (v.sprite_delay_main[i] == 0 or v.frame_counter.* & 1 != 0) {
                    v.sprite_graphics[i] = 255;
                    return;
                }
                v.sprite_graphics[i] = t.kGanon_Gfx5[v.sprite_D[i]];
                if (v.frame_counter.* & 7 == 0) {
                    // Trail an after-image behind him as he glides.
                    var info: a.SpriteSpawnInfo = undefined;
                    const j = a.Sprite_SpawnDynamically(k, 0xd6, &info);
                    if (j >= 0) {
                        const ju = ix(j);
                        a.Sprite_SetSpawnedCoordinates(j, &info);
                        v.sprite_ignore_projectile[ju] = 24;
                        v.sprite_delay_main[ju] = 24;
                        v.sprite_ai_state[ju] = 255;
                        v.sprite_graphics[ju] = v.sprite_graphics[i];
                        v.sprite_head_dir[ju] = v.sprite_head_dir[i];
                    }
                }
            }
        },
        6 => {
            if (v.sprite_health[i] < 209)
                v.sprite_health[i] = 208;
            if (v.sprite_delay_main[i] == 0) {
                if (v.sprite_health[i] >= 209) {
                    v.sprite_ai_state[i] = 1;
                    v.sprite_delay_main[i] = 128;
                } else {
                    v.sprite_delay_main[i] = 255;
                    v.sprite_ai_state[i] = 7;
                }
            } else {
                a.Ganon_ShakeHead(k);
            }
        },
        7 => {
            if (v.sprite_health[i] < 161)
                v.sprite_health[i] = 160;
            v.overlord_x_lo[2] = 40;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 8;
                v.sprite_delay_main[i] = 255;
            } else {
                if (v.sprite_delay_main[i] < 0xc0 and v.sprite_delay_main[i] & 0xf == 0)
                    a.Ganon_SpawnSpiralBat(k);
                a.Ganon_Phase1_AnimateTridentSpin(k);
                a.Ganon_HandleFireBatCircle(k);
            }
        },
        8 => {
            if (v.sprite_health[i] < 161)
                v.sprite_health[i] = 160;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_ai_state[i] = 9;
                v.sprite_delay_main[i] = 127;
                a.Ganon_HandleAnimation_Idle(k);
                // Stagger the eight bats already circling.
                var j: usize = 8;
                while (j != 0) : (j -= 1) {
                    v.sprite_ai_state[j] = 2;
                    v.sprite_delay_main[j] = t.kGanon_Delay8[j - 1];
                }
            } else {
                v.overlord_x_lo[2] +%= @bitCast(t.kGanon_Tab2[v.sprite_delay_main[i] >> 4 & 15]);
                a.Ganon_Phase1_AnimateTridentSpin(k);
                a.Ganon_HandleFireBatCircle(k);
            }
        },
        9 => {
            if (v.sprite_health[i] < 161)
                v.sprite_health[i] = 160;
            if (v.sprite_delay_main[i] == 0)
                a.Ganon_SelectWarpLocation(k, 10)
            else
                a.Ganon_ShakeHead(k);
        },
        11 => {
            v.sprite_ignore_projectile[i] +%= 1;
            a.Ganon_HandleAnimation_Idle(k);
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_delay_main[i] = 255;
                v.sprite_ai_state[i] = 7;
            } else if (v.sprite_delay_main[i] & 1 != 0) {
                v.sprite_graphics[i] = 255;
            }
        },
        12 => {
            const j = v.sprite_delay_main[i];
            if (j == 0) {
                a.Ganon_SelectWarpLocation(k, 13);
                return;
            }
            var idx: usize = 0;
            if (j < 96) {
                idx = 1;
                if (j < 72) {
                    if (j == 66)
                        a.Ganon_Func1(k, 3);
                    idx = 2;
                }
            }
            if (v.sprite_D[i] != 0)
                idx += 3;
            v.sprite_graphics[i] = t.kGanon_Gfx12[idx];
            if (v.sprite_hit_timer[i] & 127 == 1) {
                v.sprite_ai_state[i] = 15;
                v.sprite_z_vel[i] = 24;
                v.sprite_delay_main[i] = 0;
            }
        },
        14 => {
            v.sprite_ignore_projectile[i] +%= 1;
            a.Ganon_HandleAnimation_Idle(k);
            v.sprite_G[i] = 0;
            if (v.sprite_delay_main[i] == 0) {
                if (a.GetRandomNumber() & 1 != 0) {
                    a.Ganon_SelectWarpLocation(k, 13);
                } else {
                    v.sprite_delay_main[i] = 127;
                    v.sprite_ai_state[i] = 12;
                }
            } else if (v.sprite_delay_main[i] & 1 != 0) {
                v.sprite_graphics[i] = 255;
            }
        },
        15 => {
            if (v.sprite_delay_main[i] != 0) {
                if (v.sprite_delay_main[i] == 1) {
                    v.sprite_ai_state[i] = 16;
                    v.sprite_z_vel[i] = 160;
                    return;
                }
            } else {
                a.Sprite_MoveZ(k);
                v.sprite_z_vel[i] -%= 1;
                if (v.sprite_z_vel[i] == 0)
                    v.sprite_delay_main[i] = 32;
            }
            v.sprite_graphics[i] = t.kGanon_Gfx15[v.sprite_D[i]];
        },
        16 => {
            v.bg1_y_offset.* = 0;
            if (v.sprite_delay_main[i] != 0) {
                if (v.sprite_delay_main[i] == 1) {
                    v.sound_effect_ambient.* = 5;
                    a.Ganon_SelectWarpLocation(k, 13);
                    v.flag_is_link_immobilized.* = 0;
                    a.Ganon_SpawnFallingTilesOverlord(k);
                    if (v.sprite_anim_clock[i] >= 4) {
                        a.Ganon_SelectWarpLocation(k, 10);
                        v.sprite_health[i] = 96;
                        v.sprite_delay_aux2[i] = 224;
                        v.dialogue_message_index.* = 0x170;
                        a.Sprite_ShowMessageMinimal();
                    }
                } else {
                    // Shake the room while the ceiling comes down.
                    v.bg1_y_offset.* = if ((v.sprite_delay_main[i] -% 1) & 1 != 0) 0xffff else 1;
                    v.flag_is_link_immobilized.* = 1;
                }
            } else {
                a.Sprite_MoveZ(k);
                if (sign8(v.sprite_z[i])) {
                    v.sprite_z_vel[i] = 0;
                    v.sprite_z[i] = 0;
                    v.sprite_delay_main[i] = 96;
                    v.sound_effect_ambient.* = 7;
                    a.SpriteSfx_QueueSfx2WithPan(k, 0xc);
                }
                v.sprite_graphics[i] = t.kGanon_Gfx16[v.sprite_D[i]];
            }
        },
        17 => {
            v.sprite_graphics[i] = t.kGanon_Gfx17b[v.sprite_D[i]];
            if (v.sprite_delay_main[i] == 0) {
                a.Ganon_SelectWarpLocation(k, 0x12);
                return;
            } else if (v.sprite_delay_main[i] == 52) {
                a.Ganon_Func1(k, 5);
            } else if (v.sprite_delay_main[i] < 52) {
                v.sprite_graphics[i] = t.kGanon_Gfx17[v.sprite_D[i]];
            }
            if (v.sprite_delay_main[i] >= 72 or v.sprite_delay_main[i] < 40) {
                v.sprite_ignore_projectile[i] +%= 1;
                if (v.sprite_delay_main[i] & 1 != 0)
                    v.sprite_graphics[i] = 0xff;
            }
            a.Ganon_EnableInvincibility(k);
        },
        19 => {
            v.sprite_oam_flags[i] = 5;
            v.sprite_flags[i] = 2;
            if (v.sprite_delay_main[i] == 0) {
                v.sprite_oam_flags[i] = 1;
                a.Ganon_SelectWarpLocation(k, 18);
                v.sprite_type[i] = 0xd6;
                v.sprite_hit_timer[i] = 0;
            } else {
                v.sprite_graphics[i] = t.kGanon_Gfx19[v.sprite_D[i]];
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// from sprite_main_extra.zig
// ---------------------------------------------------------------------------
pub export fn MazeGameGuy_Draw(k: c_int) void { const i = ix_ex(k); draw(k, &t.kMazeGameGuy_Dmd, @as(usize, v.sprite_graphics[i]) * 2 + @as(usize, v.sprite_D[i]) * 4, 2, true, true); }
pub export fn CrystalMaiden_Draw(k: c_int) void {
    const i = ix_ex(k); const j = @as(usize, v.sprite_D[i]) * 2 + v.sprite_graphics[i];
    low(v.dma_var6).* = t.kCrystalMaiden_Dma[j * 2]; low(v.dma_var7).* = t.kCrystalMaiden_Dma[j * 2 + 1];
    draw(k, &t.kCrystalMaiden_SpriteData, j * 2, 2, true, false);
}
pub export fn Priest_Draw(k: c_int) void { const i = ix_ex(k); draw(k, &t.kPriest_Dmd, (@as(usize, v.sprite_D[i]) * 2 + v.sprite_graphics[i]) * 2, 2, true, true); }
pub export fn FluteBoy_Draw(k: c_int) u8 {
    const i = ix_ex(k); _ = a.Oam_AllocateFromRegionB(0x10); var info: Info = undefined;
    a.Sprite_DrawMultiple(k, t.kFluteBoy_Dmd[0..].ptr + @as(usize, v.sprite_D[i]) * 8 + @as(usize, v.sprite_graphics[i]) * 4, 4, &info);
    return b_ex((info.x | info.y) >> 8);
}
pub export fn FluteAardvark_Draw(k: c_int) void { draw(k, &t.kFluteAardvark_Dmd, @as(usize, v.sprite_graphics[ix_ex(k)]) * 2, 2, true, false); }
pub export fn DustCloud_Draw(k: c_int) void { v.sprite_oam_flags[ix_ex(k)] = 0x14; draw(k, &t.kDustCloud_Dmd, @as(usize, v.sprite_graphics[ix_ex(k)]) * 4, 4, false, false); }
pub export fn MedallionTablet_Draw(k: c_int) void { draw(k, &t.kMedallionTablet_Dmd, @as(usize, v.sprite_graphics[ix_ex(k)]) * 4, 4, true, false); }
pub export fn Uncle_Draw(k: c_int) void {
    const i = ix_ex(k); _ = a.Oam_AllocateFromRegionB(0x18); const j = @as(usize, v.sprite_D[i]) * 2 + v.sprite_graphics[i];
    v.link_dma_var3.* = t.kUncleDraw_Dma3[j]; v.link_dma_var4.* = t.kUncleDraw_Dma4[j];
    draw(k, &t.kUncleDraw_Table, @as(usize, v.sprite_D[i]) * 12 + @as(usize, v.sprite_graphics[i]) * 6, 6, false, v.sprite_D[i] != 0 and v.sprite_D[i] != 3);
}
pub export fn BugNetKid_Draw(k: c_int) void { draw(k, &t.kBugNetKid_Dmd, @as(usize, v.sprite_graphics[ix_ex(k)]) * 6, 6, true, false); }
pub export fn Bomber_Draw(k: c_int) void { draw(k, &t.kBomber_Dmd, @as(usize, v.sprite_graphics[ix_ex(k)]) * 2, 2, false, true); }
pub export fn SpriteDraw_ZirroBomb(k: c_int) void { const i = ix_ex(k); if (v.sprite_delay_main[i] == 0) v.sprite_state[i] = 0; draw(k, &t.kBomberPellet_Dmd, @as(usize, v.sprite_delay_main[i] >> 2) * 3, 3, false, false); }
pub export fn PlayerBee_HoneInOnTarget(j: c_int, k: c_int) void {
    const n = ix_ex(j); const i = ix_ex(k);
    if (v.sprite_type[n] != 0x88 and v.sprite_flags[n] & 2 != 0) return;
    if (v.cur_sprite_x.* -% a.Sprite_GetX(j) +% 16 >= 24 or v.cur_sprite_y.* -% a.Sprite_GetY(j) -% 8 >= 24) return;
    if (v.sprite_type[n] == 0x75) { v.sprite_E[n] = b_ex(k + 1); return; }
    a.Ancilla_CheckDamageToSprite_preset(j, 1); v.sprite_F[n] = 15;
    v.sprite_x_recoil[n] = v.sprite_x_vel[i] << 1; v.sprite_y_recoil[n] = v.sprite_y_vel[i] << 1; v.sprite_B[i] +%= 1;
}
pub export fn Pikit_Draw(k: c_int) void {
    const i = ix_ex(k); var info: Info = undefined;
    if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    SpriteDraw_Pikit_Tongue(k, &info); v.tmp_counter.* = oam_ex()[0].x; v.byte_7E0FB6.* = oam_ex()[0].y;
    v.oam_cur_ptr.* +%= 24; v.oam_ext_cur_ptr.* +%= 6;
    a.Sprite_DrawMultiple(k, t.kPikit_Dmd[0..].ptr + @as(usize, v.sprite_graphics[i]) * 2, 2, &info);
    const saved = v.sprite_flags2[i]; v.sprite_flags2[i] -%= 6; a.SpriteDraw_Shadow(k, &info); v.sprite_flags2[i] = saved;
    SpriteDraw_Pikit_Loot(k, &info);
}
pub export fn SpriteDraw_Pikit_Tongue(k: c_int, info: *Info) void {
    const i = ix_ex(k); if (v.sprite_ai_state[i] != 2 or v.sprite_pause[i] != 0) return;
    const p = oam_ex(); const x = @as(i32, info.x) + 4; const y = @as(i32, info.y) + 3;
    p[5].x = b_ex(x); p[5].y = b_ex(y); p[0].x = b_ex(x + v.sprite_A[i]); p[0].y = b_ex(y + v.sprite_B[i]);
    p[0].charnum = 0xfe; p[5].charnum = 0xfe; p[0].flags = info.flags; p[5].flags = info.flags;
    for (0..4) |n| { const j = 3 - n; p[n + 1] = .{ .x = b_ex(x + @divTrunc(signed(v.sprite_A[i]) * t.kPikit_TongueMult[j], 256)), .y = b_ex(y + @divTrunc(signed(v.sprite_B[i]) * t.kPikit_TongueMult[j], 256)), .charnum = t.kPikit_Draw_Char[v.sprite_D[i]], .flags = t.kPikit_Draw_Flags[v.sprite_D[i]] | info.flags }; }
    a.Sprite_CorrectOamEntries(k, 5, 0);
}
pub export fn SpriteDraw_Pikit_Loot(k: c_int, info: *Info) void {
    _ = info; const i = ix_ex(k); if (v.sprite_G[i] == 0) return;
    var g: usize = v.sprite_G[i] - 1; if (g == 3) g = @as(usize, v.sprite_subtype[i]) + 2;
    _ = a.Oam_AllocateFromRegionC(0x10); const p = oam_ex();
    for (0..4) |n| { const j = g * 4 + 3 - n; p[n] = .{ .x = b_ex(@as(i32, v.tmp_counter.*) + t.kPikit_DrawGrabbedItem_X[j]), .y = b_ex(@as(i32, v.byte_7E0FB6.*) + t.kPikit_DrawGrabbedItem_Y[j]), .charnum = t.kPikit_DrawGrabbedItem_Char[j], .flags = t.kPikit_DrawGrabbedItem_Flags[g] }; }
    a.Sprite_CorrectOamEntries(k, 3, 0);
}
pub export fn Kholdstare_Draw(k: c_int) void {
    const i = ix_ex(k); var info: Info = undefined; if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return;
    const j = v.sprite_A[i]; setOam_ex(oam_ex(), w_ex(@as(i32, info.x) + t.kKholdstare_Draw_X[j]), w_ex(@as(i32, info.y) + t.kKholdstare_Draw_Y[j]), t.kKholdstare_Draw_Char[j], t.kKholdstare_Draw_Flags[j] | info.flags, 2);
    v.oam_cur_ptr.* +%= 4; v.oam_ext_cur_ptr.* +%= 1;
    a.Sprite_DrawMultiple(k, t.kKholdstare_Dmd[0..].ptr + @as(usize, v.sprite_graphics[i]) * 4, 4, &info);
}
pub export fn Sprite_SpawnFireball(k: c_int) c_int {
    var info: Spawn = undefined; a.SpriteSfx_QueueSfx3WithPan(k, 0x19); const j = a.Sprite_SpawnDynamicallyEx(k, 0x55, &info, 13); if (j < 0) return j;
    const n = ix_ex(j); a.Sprite_SetX(j, info.r0_x +% 4); a.Sprite_SetY(j, info.r2_y +% 4 -% info.r4_z);
    v.sprite_flags3[n] = v.sprite_flags3[n] & 0xfe | 0x40; v.sprite_oam_flags[n] = 6; v.sprite_flags4[n] = 0x54; v.sprite_E[n] = 0x54; v.sprite_flags2[n] = 0x20;
    a.Sprite_ApplySpeedTowardsLink(j, 0x20); v.sprite_delay_main[n] = 20; v.sprite_delay_aux1[n] = 16; v.sprite_flags5[n] = 0; v.sprite_defl_bits[n] = 0x48; return j;
}
pub export fn ArcheryGameGuy_Draw(k: c_int) void {
    a.Oam_AllocateDeferToPlayer(k); var info: Info = undefined; a.Sprite_PrepOamCoord(k, &info); const p = oam_ex();
    for (0..3) |n| { const j = @as(usize, v.sprite_graphics[ix_ex(k)]) * 3 + 2 - n; setOamPlain_ex(p + n, w_ex(@as(i32, info.x) + t.kArcheryGameGuy_Draw_X[j]), w_ex(@as(i32, info.y) + t.kArcheryGameGuy_Draw_Y[j]), t.kArcheryGameGuy_Draw_Char[j], t.kArcheryGameGuy_Draw_Flags[j] | info.flags, t.kArcheryGameGuy_Draw_Big[j]); }
    a.SpriteDraw_Shadow(k, &info);
}
pub export fn ShopKeeper_RapidTerminateReceiveItem() void { for (0..5) |i| { if (v.ancilla_type[4 - i] == 0x22) v.ancilla_aux_timer[4 - i] = 1; } }
pub export fn Sprite_InitializeSecondaryItemMinigame(what: c_int) void {
    v.is_archer_or_shovel_game.* = b_ex(what); a.Link_ResetProperties_C();
    for (0..5) |i| { const j = 4 - i; if (v.ancilla_type[j] == 0x30 or v.ancilla_type[j] == 0x31) { v.ancilla_type[j] = 0; } else if (v.ancilla_type[j] == 5) { v.flag_for_boomerang_in_place.* = 0; v.ancilla_type[j] = 0; } }
}
pub export fn Waterfall(k: c_int) void { if (a.Sprite_ReturnIfInactive(k)) return; if (a.Sprite_CheckDamageToLink_same_layer(k)) { if (b_ex(v.overworld_screen_index.*) == 0x43) a.AncillaAdd_GTCutscene() else a.AncillaAdd_WaterfallSplash(); } }
pub export fn Sprite_BatCrash(k: c_int) void {
    const i = ix_ex(k); RetreatBat_Draw(k); if (a.Sprite_ReturnIfInactive(k)) return;
    a.Sprite_MoveXY(k); BatCrash_DrawHardcodedGarbage(k); v.bg1_y_offset.* = 0;
    if (v.sprite_delay_aux3[i] != 0) { if (v.sprite_delay_aux3[i] == 1) v.sound_effect_ambient.* = 5; v.bg1_y_offset.* = if (v.sprite_delay_aux3[i] & 1 != 0) 1 else 0xffff; }
    if (v.sprite_delay_main[i] == 0) { v.sprite_graphics[i] = (v.sprite_graphics[i] +% 1) & 3; if (v.sprite_graphics[i] == 0 and v.sprite_ai_state[i] < 2) a.SpriteSfx_QueueSfx2WithPan(k, 3); v.sprite_delay_main[i] = t.kRetreatBat_Delay[v.sprite_D[i]]; }
    switch (v.sprite_ai_state[i]) {
        0 => { const j = v.sprite_A[i]; if (t.kRetreatBat_Xpos[j] < v.cur_sprite_x.*) { if (j >= 2) { v.sprite_ai_state[i] +%= 1; v.sprite_delay_aux1[i] = 208; } v.sprite_A[i] +%= 1; v.sprite_D[i] +%= 1; } batUpdatePosition(i, j); },
        1 => { if (v.sprite_delay_aux1[i] == 0) { v.sprite_ai_state[i] +%= 1; a.SpriteSfx_QueueSfx3WithPan(k, 0x26); v.sprite_D[i] +%= 1; v.sprite_x_lo[i] = 232; v.sprite_x_hi[i] = 7; v.sprite_y_lo[i] = 224; v.sprite_y_hi[i] = 5; v.sprite_x_vel[i] = 0; v.sprite_y_vel[i] = 64; v.sprite_delay_aux1[i] = 45; } else { if (v.frame_counter.* & 3 == 0) v.sprite_x_vel[i] -%= 1; batUpdatePosition(i, v.sprite_A[i]); } },
        2 => { if (v.sprite_delay_aux1[i] == 0) { v.sprite_y_vel[i] = 0; v.sprite_delay_aux1[i] = 96; v.sprite_ai_state[i] +%= 1; } if (v.sprite_delay_aux1[i] == 9) { BatCrash_SpawnDebris(k); a.CreatePyramidHole(); } },
        3 => { if (v.sprite_delay_aux1[i] == 0) { v.sprite_state[i] = 0; v.overworld_map_state.* +%= 1; } }, else => {},
    }
}
pub export fn Sprite_SpawnBatCrashCutscene() void {
    var info: Spawn = undefined; const j = a.Sprite_SpawnDynamically(0, 0x37, &info); if (j < 0) return; const n = ix_ex(j);
    v.sprite_y_vel[n] = 0; v.sprite_B[n] = 0; v.sprite_D[n] = 0; v.sprite_floor[n] = 0; v.sprite_subtype2[n] = 1; v.sprite_flags2[n] = 1; v.sprite_flags3[n] = 1; v.sprite_oam_flags[n] = 1;
    v.sprite_x_lo[n] = 204; v.sprite_x_hi[n] = 7; v.sprite_y_lo[n] = 50; v.sprite_y_hi[n] = 6; v.sprite_defl_bits[n] = 128;
}
pub export fn BatCrash_DrawHardcodedGarbage(k: c_int) void { _ = k; const dst: [*]u8 = @ptrCast(v.oam_buf + 76); @memcpy(dst[0..32], std.mem.asBytes(&t.kRetreatBat_Oams)); @memset(v.bytewise_extended_oam[76..85], 2); }
pub export fn BatCrash_SpawnDebris(k: c_int) void { for (0..30) |n| { const j = 29 - n; a.GarnishSpawn_PyramidDebris(t.kPyramidDebris_X[j], t.kPyramidDebris_Y[j], t.kPyramidDebris_Xvel[j], t.kPyramidDebris_Yvel[j]); } v.sprite_delay_aux3[ix_ex(k)] = 32; }
pub export fn RetreatBat_Draw(k: c_int) void {
    const offsets = [_]u8{0,0,1,1,2,2,3,3,4,4,6,6,8,10,12,10,14,14,14,14}; const counts = [_]u8{1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,4,4,4,4};
    v.oam_cur_ptr.* = 0x960; v.oam_ext_cur_ptr.* = 0xa78; const j = @as(usize, v.sprite_D[ix_ex(k)]) * 4 + v.sprite_graphics[ix_ex(k)]; draw(k, &t.kRetreatBat_Dmds, offsets[j], counts[j], false, false);
}
pub export fn DrinkingGuy_Draw(k: c_int) void { draw(k, &t.kDrinkingGuy_Dmd, @as(usize, v.sprite_graphics[ix_ex(k)]) * 3, 3, true, true); }
pub export fn Lady_Draw(k: c_int) void { const i = ix_ex(k); draw(k, &t.kLadyDmd, @as(usize, v.sprite_graphics[i]) * 2 + @as(usize, v.sprite_D[i]) * 4, 2, true, true); }
pub export fn Lanmola_SpawnShrapnel(k: c_int) void {
    v.tmp_counter.* = if (@as(u16, v.sprite_state[0]) + v.sprite_state[1] + v.sprite_state[2] < 10) 7 else 3;
    while (true) { var info: Spawn = undefined; const j = a.Sprite_SpawnDynamically(k, 0xc2, &info); if (j >= 0) { const n = ix_ex(j); a.Sprite_SetSpawnedCoordinates(j, &info); v.sprite_x_lo[n] = b_ex(info.r0_x +% 4); v.sprite_y_lo[n] = b_ex(info.r2_y +% 4); v.sprite_ignore_projectile[n] = 1; v.sprite_bump_damage[n] = 1; v.sprite_flags4[n] = 1; v.sprite_z[n] = 0; v.sprite_flags2[n] = 0x20; v.sprite_x_vel[n] = b_ex(t.kLanmolaShrapnel_Xvel[v.tmp_counter.*]); v.sprite_y_vel[n] = b_ex(t.kLanmolaShrapnel_Yvel[v.tmp_counter.*]); v.sprite_graphics[n] = a.GetRandomNumber() & 1; } v.tmp_counter.* -%= 1; if (v.tmp_counter.* & 0x80 != 0) break; }
}
pub export fn Sprite_Cukeman(k: c_int) void {
    const i = ix_ex(k); if (v.sprite_head_dir[i] == 0) return;
    if (v.sprite_state[i] == 9 and v.submodule_index.* | v.flag_unk1.* == 0 and v.cur_sprite_x.* -% v.link_x_coord.* +% 0x18 < 0x30 and v.link_y_coord.* -% v.cur_sprite_y.* +% 0x20 < 0x30 and v.filtered_joypad_L.* & 0x80 != 0) { v.dialogue_message_index.* = 0x17a + @as(u16, v.sprite_subtype[i] & 1); v.sprite_subtype[i] +%= 1; a.Sprite_ShowMessageMinimal(); }
    const old = v.sprite_oam_flags[i] & 0xf0; v.sprite_oam_flags[i] = old | 8; Cukeman_Draw(k); v.sprite_oam_flags[i] = old | 0xd; _ = a.Oam_AllocateFromRegionA(0x10);
}
pub export fn Cukeman_Draw(k: c_int) void { draw(k, &t.kCukeman_Dmd, @as(usize, v.sprite_graphics[ix_ex(k)]) * 3, 3, false, false); }
pub export fn RunningBoy_SpawnDustGarnish(k: c_int) void { const i = ix_ex(k); v.sprite_die_action[i] +%= 1; if (v.sprite_die_action[i] & 15 != 0) return; const j = a.GarnishAllocForce(); const n = ix_ex(j); v.garnish_type[n] = 20; v.garnish_active.* = 20; a.Garnish_SetX(j, a.Sprite_GetX(k) +% 4); a.Garnish_SetY(j, a.Sprite_GetY(k) +% 28); v.garnish_countdown[n] = 10; }
pub export fn MovableMantle_Draw(k: c_int) void { _ = a.Oam_AllocateFromRegionB(0x20); var info: Info = undefined; if (a.Sprite_PrepOamCoordOrDoubleRet(k, &info)) return; const p = oam_ex(); for (0..6) |n| { const j = 5 - n; p[n] = .{ .x = b_ex(@as(i32, info.x) + t.kMovableMantle_X[j]), .y = b_ex(@as(i32, info.y) + t.kMovableMantle_Y[j]), .charnum = t.kMovableMantle_Char[j], .flags = t.kMovableMantle_Flags[j] }; } a.Sprite_CorrectOamEntries(k, 5, 2); }
pub export fn Mothula_Draw(k: c_int) void {
    const i = ix_ex(k); v.oam_cur_ptr.* = 0x920; v.oam_ext_cur_ptr.* = 0xa68; var info: Info = undefined; a.Sprite_DrawMultiple(k, t.kMothula_Dmd[0..].ptr + @as(usize, v.sprite_graphics[i]) * 8, 8, &info); if (v.sprite_pause[i] != 0) return;
    info.y +%= v.sprite_z[i]; const p = oam_ex() + 10; for (0..9) |n| { const j = @as(usize, v.sprite_graphics[i]) * 9 + 8 - n; setOam_ex(p + n, w_ex(@as(i32, info.x) + t.kMothula_Draw_X[j]), info.y +% 16, 0x6c, 0x24, 2); }
}
pub export fn BottleMerchant_BuyBee(k: c_int) void {
    var info: Spawn = undefined; a.SpriteSfx_QueueSfx3WithPan(k,0x13); v.tmp_counter.*=4;
    while (true) { const j=a.Sprite_SpawnDynamically(k,0xdb,&info); if (j>=0) { const n=ix_ex(j); a.Sprite_SetSpawnedCoordinates(j,&info); v.sprite_x_lo[n]=b_ex(info.r0_x+%4); v.sprite_stunned[n]=255; v.sprite_x_vel[n]=b_ex(t.kBottleVendor_GoodBeeX[v.tmp_counter.*]); v.sprite_y_vel[n]=b_ex(t.kBottleVendor_GoodBeeY[v.tmp_counter.*]); v.sprite_z_vel[n]=32; v.sprite_delay_aux4[n]=32; } v.tmp_counter.*-%=1; if (v.tmp_counter.* & 128 != 0) break; }
}
pub export fn Sprite_ChickenLady(k:c_int) void { const i=ix_ex(k); v.sprite_D[i]=1; Lady_Draw(k); if(a.Sprite_ReturnIfInactive(k)) return; if(v.sprite_delay_main[i]==1) {v.dialogue_message_index.*=0x17d; a.Sprite_ShowMessageMinimal();} v.sprite_graphics[i]=v.frame_counter.* >> 4 & 1; }
pub export fn Overworld_DrawWoodenDoor(pos:u16, unlocked:bool) void { a.Overworld_DrawMap16_Persist(pos,if(unlocked) 0xda5 else 0xda4); a.Overworld_DrawMap16_Persist(pos+%2,if(unlocked) 0xda7 else 0xda6); v.nmi_load_bg_from_vram.*=1; }
pub export fn Sprite_D4_Landmine(k:c_int) void {
    const i=ix_ex(k); Landmine_Draw(k); if(a.Sprite_ReturnIfInactive(k)) return;
    if(!a.Landmine_CheckDetonationFromHammer(k)) { if(v.sprite_delay_main[i]==0) {v.sprite_oam_flags[i]=4; if(a.Sprite_CheckDamageToLink(k)) v.sprite_delay_main[i]=8; return;} if(v.sprite_delay_main[i]!=1) {v.sprite_oam_flags[i]=t.kLandMine_OamFlags[v.sprite_delay_main[i] >> 1 & 3]; return;} }
    v.sprite_state[i]=0; const j=a.Sprite_SpawnBomb(k); if(j>=0) {const n=ix_ex(j); v.sprite_state[n]=6; v.sprite_C[n]=2; v.sprite_oam_flags[n]=2; v.sprite_flags4[n]=9; v.sprite_delay_aux1[n]=31; v.sprite_flags2[n]=3; v.sound_effect_1.*=a.Sprite_CalculateSfxPan(k)|12;}
}
pub export fn Landmine_Draw(k:c_int) void { _=a.Oam_AllocateFromRegionB(8); if(v.byte_7E0FC6.*>=3) return; draw(k,&t.kLandmine_Dmd,0,2,false,false); }
pub export fn Sprite_D3_Stal(k:c_int) void {
    const i=ix_ex(k); if(v.byte_7E0FC6.*<3) {if(v.sprite_ai_state[i]==0) _=a.Oam_AllocateFromRegionB(4); Stal_Draw(k);} if(a.Sprite_ReturnIfInactive(k) or a.Sprite_ReturnIfRecoiling(k)) return;
    switch(v.sprite_ai_state[i]) {
        0=>{ v.sprite_ignore_projectile[i]=1; if(a.Sprite_CheckDamageToLink_same_layer(k)) {a.Sprite_NullifyHookshotDrag(); a.Sprite_RepelDash(); if(v.sprite_delay_main[i]==0) {v.sprite_delay_main[i]=64; a.SpriteSfx_QueueSfx2WithPan(k,0x22);}} if(v.sprite_delay_main[i]!=0) {if(v.sprite_delay_main[i]!=1) {v.sprite_hit_timer[i]=(v.sprite_delay_main[i]-1)|64;} else {v.sprite_ignore_projectile[i]=0; v.sprite_ai_state[i]+%=1; v.sprite_hit_timer[i]=0; v.sprite_flags3[i]&=0xbf; v.sprite_flags2[i]&=0x7f;}} },
        1=>{ _ = a.Sprite_CheckDamageToAndFromLink(k); a.Sprite_MoveXYZ(k); _=a.Sprite_CheckTileCollision(k); v.sprite_z_vel[i]-%=2; if(v.sprite_z[i]&128!=0) {v.sprite_z[i]=0; v.sprite_z_vel[i]=16; a.Sprite_ApplySpeedTowardsLink(k,12);} if(v.frame_counter.*&3==0) {v.sprite_subtype2[i]+%=1; if(v.sprite_subtype2[i]==5) v.sprite_subtype2[i]=0;} v.sprite_graphics[i]=t.kStal_Gfx[v.sprite_subtype2[i]]; }, else=>{},
    }
}
pub export fn Stal_Draw(k:c_int) void {const i=ix_ex(k); const active=v.sprite_ai_state[i]!=0; draw(k,&t.kStal_Dmd,@as(usize,v.sprite_graphics[i])*2,if(active) 2 else 1,false,active);}
pub export fn Sprite_D2_FloppingFish(k:c_int) void {
    const i=ix_ex(k); if(v.byte_7E0FC6.*<3) Fish_Draw(k); if(v.sprite_state[i]==10) {v.sprite_ai_state[i]=4; v.sprite_graphics[i]=(v.frame_counter.*>>4&1)+3;} if(a.Sprite_ReturnIfInactive(k)) return;
    switch(v.sprite_ai_state[i]) {
        0=>{_=a.Sprite_CheckTileCollision(k); if(v.sprite_tiletype.*==8) {v.sprite_state[i]=0;} else {v.sprite_ai_state[i]=1;}},
        1=>{_=a.Sprite_CheckIfLifted_permissive(k); _ = a.Sprite_BounceFromTileCollision(k); a.Sprite_MoveXYZ(k); v.sprite_z_vel[i]-%=2; if(v.sprite_z[i]&128!=0) {v.sprite_z[i]=0; if(v.sprite_tiletype.*==9) {_ = a.Sprite_SpawnSmallSplash(k);} else if(v.sprite_tiletype.*==8) {v.sprite_state[i]=0; _ = a.Sprite_SpawnSmallSplash(k);} v.sprite_z_vel[i]=(a.GetRandomNumber()&15)+16; const j=a.GetRandomNumber()&7; v.sprite_x_vel[i]=b_ex(t.kFish_Xvel[j]); v.sprite_y_vel[i]=b_ex(t.kFish_Yvel[j]); v.sprite_D[i]+%=1; v.sprite_subtype2[i]=3;} v.sprite_subtype2[i]+%=1; if(v.sprite_subtype2[i]&7==0) {const j=v.sprite_D[i]&1; if(v.sprite_A[i]!=t.kFish_Tab1[j]) v.sprite_A[i]+%=if(j!=0) @as(u8,255) else 1;} v.sprite_graphics[i]=t.kFish_Gfx[v.sprite_A[i]]+%(v.frame_counter.*>>3&1);},
        2=>{if(v.sprite_delay_main[i]==0) {v.sprite_ai_state[i]=3; v.sprite_z_vel[i]=48; _ = a.Sprite_SpawnSmallSplash(k);}},
        3=>{a.Sprite_MoveZ(k); v.sprite_z_vel[i]-%=2; if(v.sprite_z_vel[i]==0 and v.sprite_A[i]!=0) {v.dialogue_message_index.*=0x176; a.Sprite_ShowMessageMinimal();} if(v.sprite_z[i]&128!=0) {v.sprite_z[i]=0; _ = a.Sprite_SpawnSmallSplash(k); if(v.sprite_A[i]!=0) {var info:Spawn=undefined; const j=a.Sprite_SpawnDynamically(k,0xdb,&info); if(j>=0) {const n=ix_ex(j); a.Sprite_SetSpawnedCoordinates(j,&info); a.Sprite_SetX(j,info.r0_x+%4); v.sprite_stunned[n]=255; v.sprite_z_vel[n]=48; v.sprite_delay_aux3[n]=48; a.Sprite_ApplySpeedTowardsLink(j,16);}} v.sprite_state[i]=0;} v.sprite_subtype2[i]+%=1; v.sprite_graphics[i]=t.kFish_Gfx2[v.sprite_subtype2[i]>>2];},
        4=>{if(v.sprite_z[i]==0) v.sprite_ai_state[i]=1; a.Sprite_MoveXY(k); a.ThrownSprite_TileAndSpriteInteraction(k);}, else=>{},
    }
}
pub export fn Fish_Draw(k:c_int) void {
    const i=ix_ex(k); var info:Info=undefined; if(v.sprite_graphics[i]==0) {a.Sprite_PrepOamCoord(k,&info); return;}
    v.cur_sprite_x.*+%=4; a.Sprite_DrawMultiple(k,t.kFish_Dmd[0..].ptr+(@as(usize,v.sprite_graphics[i])-1)*2,2,&info); v.cur_sprite_y.*+%=v.sprite_z[i]; const j=@min(v.sprite_z[i]>>2,2); v.oam_cur_ptr.*+%=8; v.oam_ext_cur_ptr.*+%=2; a.Sprite_DrawMultiple(k,t.kFish_Dmd2[0..].ptr+@as(usize,j)*3,3,&info); a.Sprite_Get16BitCoords(k);
}
pub export fn ChimneySmoke_Draw(k:c_int) void {draw(k,&t.kChimneySmoke_Dmd,@as(usize,v.sprite_graphics[ix_ex(k)]&1)*4,4,false,false);}
pub export fn Sprite_D1_BunnyBeam(k:c_int) void {if(v.player_is_indoors.*!=0) Sprite_BunnyBeam(k) else Sprite_Chimney(k);}
pub export fn Sprite_Chimney(k:c_int) void {
    const i=ix_ex(k); v.sprite_flags3[i]=64; v.sprite_ignore_projectile[i]=64;
    if(v.sprite_ai_state[i]==0) {if(a.Sprite_ReturnIfInactive(k) or v.sprite_delay_main[i]!=0) return; v.sprite_delay_main[i]=67; var info:Spawn=undefined; const j=a.Sprite_SpawnDynamically(k,0xd1,&info); if(j<0) return; const n=ix_ex(j); a.Sprite_SetSpawnedCoordinates(j,&info); const x=@as(u16,b_ex(info.r0_x))+8; v.sprite_x_lo[n]=b_ex(x); v.sprite_y_lo[n]=b_ex(info.r2_y+%4+%(x>>8)); v.sprite_oam_flags[n]=4; v.sprite_ai_state[n]=4; v.sprite_flags2[n]=67; v.sprite_flags3[n]=67; v.sprite_x_vel[n]=252; v.sprite_y_vel[n]=250;
    } else {v.sprite_obj_prio[i]=0x30; ChimneySmoke_Draw(k); if(a.Sprite_ReturnIfInactive(k)) return; a.Sprite_MoveXY(k); v.sprite_subtype2[i]+%=1; if(v.sprite_subtype2[i]&7==0) {const j=v.sprite_D[i]&1; v.sprite_x_vel[i]+%=if(j!=0) @as(u8,255) else 1; if(v.sprite_x_vel[i]==@as(u8,if(j!=0) 252 else 4)) v.sprite_D[i]+%=1;} if(v.sprite_subtype2[i]&31==0) v.sprite_graphics[i]+%=1;}
}
pub export fn Sprite_BunnyBeam(k:c_int) void {
    const i=ix_ex(k); if(v.sprite_ai_state[i]==0) {var info:Info=undefined; a.Sprite_PrepOamCoord(k,&info); if(a.Sprite_ReturnIfInactive(k)) return; if(a.Sprite_CheckTileCollision(k)==0) {v.sprite_ai_state[i]+%=1; v.sprite_delay_main[i]=128;} return;}
    a.SpriteDraw_Antfairy(k); if(v.sprite_pause[i]==0) {const p=oam_ex(); for(0..5) |n| {p[n].charnum=t.kRabbitBeam_Gfx[v.sprite_graphics[i]]; p[n].flags=p[n].flags&0xf0|2;}}
    if(a.Sprite_ReturnIfInactive(k)) return; if(v.sprite_delay_main[i]==0) {v.sprite_bump_damage[i]=0x30; if(a.Sprite_CheckDamageToLink(k)) {v.sprite_state[i]=0; v.link_timer_tempbunny.*=256;} if(v.link_is_on_lower_level.*==v.sprite_floor[i]) a.Sprite_ApplySpeedTowardsLink(k,16); a.Sprite_MoveXY(k); if(a.Sprite_CheckTileCollision(k)!=0) {v.sprite_state[i]=0; a.Sprite_SpawnPoofGarnish(k); a.SpriteSfx_QueueSfx2WithPan(k,0x15);}}
}
pub export fn Sprite_D0_Lynel(k:c_int) void {
    const i=ix_ex(k); Lynel_Draw(k); if(a.Sprite_ReturnIfInactive(k) or a.Sprite_ReturnIfRecoiling(k)) return; v.sprite_D[i]=a.Sprite_DirectionToFaceLink(k,null); _ = a.Sprite_CheckDamageToAndFromLink(k);
    switch(v.sprite_ai_state[i]) {
        0=>{if(v.sprite_delay_main[i]==0) {const j=v.sprite_D[i]; const x=w_ex(@as(i32,v.link_x_coord.*)+t.kLynel_Xtarget[j]); v.sprite_A[i]=b_ex(x); v.sprite_B[i]=b_ex(x>>8); const y=w_ex(@as(i32,v.link_y_coord.*)+t.kLynel_Ytarget[j]); v.sprite_C[i]=b_ex(y); v.sprite_E[i]=b_ex(y>>8); v.sprite_ai_state[i]+%=1; v.sprite_delay_main[i]=80;} v.sprite_graphics[i]=b_ex(t.kLynel_Gfx[v.sprite_subtype2[i]&4|v.sprite_D[i]]);},
        1=>{const advance=blk:{if(v.sprite_delay_main[i]==0) break :blk true; if((b_ex(k)^v.frame_counter.*)&3==0) {const x=@as(u16,v.sprite_A[i])|@as(u16,v.sprite_B[i])<<8; const y=@as(u16,v.sprite_C[i])|@as(u16,v.sprite_E[i])<<8; if(x-%v.cur_sprite_x.*+%5<10 and y-%v.cur_sprite_y.*+%5<10) break :blk true; const pt=a.Sprite_ProjectSpeedTowardsLocation(k,x,y,24); v.sprite_x_vel[i]=pt.x; v.sprite_y_vel[i]=pt.y;} a.Sprite_MoveXY(k); if(a.Sprite_CheckTileCollision(k)!=0) break :blk true; v.sprite_subtype2[i]+%=1; v.sprite_graphics[i]=b_ex(t.kLynel_Gfx[v.sprite_subtype2[i]&4|v.sprite_D[i]]); break :blk false;}; if(advance) {v.sprite_ai_state[i]+%=1; v.sprite_delay_main[i]=32;}},
        2=>{if(v.sprite_delay_main[i]==0) {v.sprite_delay_main[i]=(a.GetRandomNumber()&15)+16; v.sprite_ai_state[i]=0; return;} if(v.sprite_delay_main[i]==16) {const j=a.Sprite_SpawnFirePhlegm(k); if(j>=0 and v.link_shield_type.*!=3) v.sprite_flags5[ix_ex(j)]=0;} v.sprite_graphics[i]=b_ex(t.kLynel_AttackGfx[v.sprite_D[i]]); _=a.Sprite_CheckTileCollision(k);}, else=>{},
    }
}
pub export fn Lynel_Draw(k:c_int) void {draw(k,&t.kLynel_Dmd,@as(usize,v.sprite_graphics[ix_ex(k)])*3,3,false,true);}
pub export fn Sprite_SpawnPhantomGanon(k:c_int) void {var info:Spawn=undefined; const j=a.Sprite_SpawnDynamically(k,0xc9,&info); a.Sprite_SetSpawnedCoordinates(j,&info); const n=ix_ex(j); v.sprite_flags2[n]=2; v.sprite_ignore_projectile[n]=2; v.sprite_anim_clock[n]=1; v.sprite_oam_flags[n]=0;}
pub export fn Sprite_PhantomGanon(k:c_int) void {
    const i=ix_ex(k); if(v.sprite_ai_state[i]==0) {PhantomGanon_Draw(k); if(a.Sprite_ReturnIfInactive(k)) return; a.Sprite_MoveY(k); v.sprite_subtype2[i]+%=1; if(v.sprite_subtype2[i]&31==0) {v.sprite_y_vel[i]-%=1; if(v.sprite_y_vel[i]==252) {const j=a.SpawnBossPoof(k); a.Sprite_SetY(j,a.Sprite_GetY(j)-%20);} else if(v.sprite_y_vel[i]==251) {v.sprite_ai_state[i]+%=1; v.sprite_delay_main[i]=255; v.sprite_y_vel[i]=252;}}}
    else {GanonBat_Draw(k); if(v.sprite_pause[i]!=0) {v.sprite_state[i]=0; v.dung_savegame_state_bits.*|=0x8000;} if(a.Sprite_ReturnIfInactive(k)) return; v.sprite_graphics[i]=t.kGanonBat_Gfx[v.frame_counter.*>>2&3]; if(v.sprite_delay_main[i]!=0) {if(v.sprite_delay_main[i]<208) {var j=v.sprite_head_dir[i]&1; v.sprite_y_vel[i]+%=if(j!=0) @as(u8,255) else 1; if(v.sprite_y_vel[i]==b_ex(t.kGanonBat_TargetYvel[j])) v.sprite_head_dir[i]+%=1; j=v.sprite_D[i]&1; v.sprite_x_vel[i]+%=if(j!=0) @as(u8,255) else 1; if(v.sprite_x_vel[i]==b_ex(t.kGanonBat_TargetXvel[j])) v.sprite_D[i]+%=1; if(v.sprite_x_vel[i]==0) a.SpriteSfx_QueueSfx3WithPan(k,0x1e);} const pt=a.Sprite_ProjectSpeedTowardsLocation(k,v.link_x_coord.*&0xff00|0x78,v.link_y_coord.*&0xff00|0x50,5); const xv=v.sprite_x_vel[i]; const yv=v.sprite_y_vel[i]; v.sprite_x_vel[i]+%=pt.x; v.sprite_y_vel[i]+%=pt.y; a.Sprite_MoveXY(k); v.sprite_x_vel[i]=xv; v.sprite_y_vel[i]=yv;} else {a.Sprite_MoveXY(k); if(v.sprite_x_vel[i]!=64) {v.sprite_x_vel[i]+%=1; v.sprite_y_vel[i]-%=1;}}}
}
pub export fn GanonBat_Draw(k:c_int) void {draw(k,&t.kGanonBat_Dmd,@as(usize,v.sprite_graphics[ix_ex(k)])*2,2,false,false);}
pub export fn PhantomGanon_Draw(k:c_int) void {v.oam_cur_ptr.*=0x950; v.oam_ext_cur_ptr.*=0xa74; draw(k,&t.kPhantomGanon_Dmd,@as(usize,v.sprite_graphics[ix_ex(k)])*8,8,false,false);}
pub export fn SwishEvery16Frames(k:c_int) void {if(v.frame_counter.*&15==0) a.SpriteSfx_QueueSfx3WithPan(k,6);}
pub export fn Sprite_GanonTrident(k:c_int) void {
    const i=ix_ex(k); a.Trident_Draw(k); if(a.Sprite_ReturnIfInactive(k)) return; _ = a.Sprite_CheckDamageToAndFromLink(k); SwishEvery16Frames(k); a.Sprite_MoveXY(k); v.sprite_subtype2[i]-%=1; v.sprite_G[i]=t.kGanon_G_Func2[v.sprite_subtype2[i]>>2&7];
    if(v.sprite_delay_main[i]!=0) {if(v.sprite_delay_main[i]&1!=0) return; const pt=a.Sprite_ProjectSpeedTowardsLink(k,32); a.Sprite_ApproachTargetSpeed(k,pt.x,pt.y);} else {const x=w_ex(@as(i32,a.Sprite_GetX(0))+@as(i32,if(v.sprite_D[0]!=0) -16 else 24)); const y=a.Sprite_GetY(0)-%16; if(Ganon_AttemptTridentCatch(x,y)) {v.sprite_state[i]=0; v.sprite_ai_state[0]=3; v.sprite_delay_main[0]=16;} const pt=a.Sprite_ProjectSpeedTowardsLocation(k,x,y,32); a.Sprite_ApproachTargetSpeed(k,pt.x,pt.y);}
}
pub export fn Sprite_FireBat_Trailer(k:c_int) void {FireBat_Draw(k); if(a.Sprite_ReturnIfInactive(k)) return; FireBat_Move(k);}
pub export fn Sprite_SpiralFireBat(k:c_int) void {const i=ix_ex(k); FireBat_Draw(k); if(a.Sprite_ReturnIfInactive(k)) return; const x=@as(u16,v.sprite_A[i])|@as(u16,v.sprite_B[i])<<8; const y=@as(u16,v.sprite_C[i])|@as(u16,v.sprite_E[i])<<8; const pt=a.Sprite_ProjectSpeedTowardsLocation(k,x,y,2); const pt2=a.Sprite_ProjectSpeedTowardsLocation(k,x,y,80); v.sprite_x_vel[i]=pt2.y-%pt.x; v.sprite_y_vel[i]=neg(pt2.x)-%pt.y; FireBat_Move(k);}
pub export fn FireBat_Move(k:c_int) void {const i=ix_ex(k); FireBat_Animate(k); a.Sprite_MoveXY(k); if(v.sprite_subtype2[i]&7!=0) return; const j=a.Garnish_FlameTrail(k,true); v.garnish_countdown[ix_ex(j)]=if(v.sprite_anim_clock[i]==5) 0x2f else 0x4f;}
pub export fn Sprite_FireBat_Launched(k:c_int) void {
    const i=ix_ex(k); FireBat_Draw(k); if(a.Sprite_ReturnIfInactive(k)) return; _=a.Sprite_CheckDamageToLink(k);
    switch(v.sprite_ai_state[i]) {
        0=>{GetPositionRelativeToTheGreatOverlordGanon(k); if(v.sprite_delay_main[i]==0) {v.sprite_ai_state[i]=1;} else {v.sprite_graphics[i]=v.sprite_delay_main[i]>>2&1;}},
        1=>{GetPositionRelativeToTheGreatOverlordGanon(k); v.sprite_subtype2[i]+%=1; v.sprite_graphics[i]=v.sprite_subtype2[i]>>2&1;},
        2=>{a.Sprite_MoveXY(k); v.sprite_defl_bits[i]=64; if(v.sprite_delay_aux1[i]==0) {if(v.sprite_delay_main[i]==0) {FireBat_Animate(k); FireBat_Animate(k);} else {var delay=v.sprite_delay_main[i]-1; if(delay==0) {delay=35; v.sprite_delay_aux1[i]=35;} v.sprite_graphics[i]=delay>>2&1;}} else if(v.sprite_delay_aux1[i]==1) {a.Sprite_ApplySpeedTowardsLink(k,48); a.SpriteSfx_QueueSfx3WithPan(k,0x1e); FireBat_Animate(k); FireBat_Animate(k);} else {v.sprite_graphics[i]=t.kFirebat_Gfx2[v.sprite_delay_aux1[i]>>2];}}, else=>{},
    }
}
pub export fn GetPositionRelativeToTheGreatOverlordGanon(k:c_int) void {const i=ix_ex(k); const j=v.sprite_D[0]; const x=@as(u16,v.overlord_x_hi[i])|@as(u16,v.overlord_y_hi[i])<<8; const y=@as(u16,v.overlord_gen2[i])|@as(u16,v.overlord_floor[i])<<8; a.Sprite_SetX(k,w_ex(@as(i32,x)+t.kFirebat_X[j])); a.Sprite_SetY(k,w_ex(@as(i32,y)+t.kFirebat_Y[j]));}
pub export fn FireBat_Animate(k:c_int) void {const i=ix_ex(k); v.sprite_subtype2[i]+%=1; v.sprite_graphics[i]=t.kFirebat_Gfx[v.sprite_subtype2[i]>>2&3];}
pub export fn FireBat_Draw(k:c_int) void {var info:Info=undefined; if(a.Sprite_PrepOamCoordOrDoubleRet(k,&info)) return; const g=v.sprite_graphics[ix_ex(k)]; const p=oam_ex(); for(0..2) |n| {const j=1-n; setOam_ex(p+n,w_ex(@as(i32,info.x)+t.kFirebat_Draw_X[j]),info.y,t.kFirebat_Draw_Char[g],t.kFirebat_Draw_Flags[@as(usize,g)*2+j]|info.flags,2);}}
pub export fn Ganon_AttemptTridentCatch(x:u16,y:u16) bool {return v.cur_sprite_x.*-%x+%4<8 and v.cur_sprite_y.*-%y+%4<8;}
pub export fn Ganon_HandleFireBatCircle(k:c_int) void {
    _=k; const angle:*align(1) u16=@ptrCast(&v.overlord_x_lo[0]); angle.*-%=4;
    for(0..8) |i| {const theta=angle.*+%@as(u16,@intCast(i*64))&0x1ff; if(v.sprite_ai_state[i+1]!=2) {const j=(theta>>5)-%4&15; v.sprite_x_vel[i+1]=b_ex(@as(i32,t.kGanonMath_X[j])>>2); v.sprite_y_vel[i+1]=b_ex(@as(i32,t.kGanonMath_Y[j])>>2);} const x=w_ex(@as(i32,a.Sprite_GetX(0))+GanonSin_smz(theta,v.overlord_x_lo[2])); v.overlord_x_hi[i+1]=b_ex(x); v.overlord_y_hi[i+1]=b_ex(x>>8); const y=w_ex(@as(i32,a.Sprite_GetY(0))+GanonSin_smz(theta+0x80,v.overlord_x_lo[2])); v.overlord_gen2[i+1]=b_ex(y); v.overlord_floor[i+1]=b_ex(y>>8); } v.tmp_counter.*=8;
}
pub export fn Ganon_SpawnSpiralBat(k:c_int) void {var info:Spawn=undefined; const j=a.Sprite_SpawnDynamicallyEx(k,0xc9,&info,8); if(j<0) return; const n=ix_ex(j); a.Sprite_SetSpawnedCoordinates(j,&info); v.sprite_anim_clock[n]=4; v.sprite_oam_flags[n]=3; v.sprite_flags3[n]=0x40; v.sprite_flags2[n]=1; v.sprite_defl_bits[n]=128; v.sprite_y_hi[n]=128; v.sprite_delay_main[n]=48; v.sprite_bump_damage[n]=7; v.sprite_ignore_projectile[n]=7;}


const testing = std.testing;

test "the debirando pit drags the player back one pixel, not 255 forward" {
    // drag_player_x/y are 16-bit and get added straight onto link_x/y_coord.
    // Away-from-the-pit has to be a 16-bit -1; the 8-bit spelling (255) sends
    // Link most of a screen in the wrong direction, which is what broke Desert
    // Palace: he shot through walls and his sprite parted ways with the camera.
    const back = debirandoDragStep(0); // positive velocity -> pull back
    try testing.expectEqual(@as(u16, 0xffff), back);

    var link_x: u16 = 100;
    link_x +%= back;
    try testing.expectEqual(@as(u16, 99), link_x);

    // A negative velocity pulls the other way, by one pixel.
    const fwd = debirandoDragStep(0x80);
    try testing.expectEqual(@as(u16, 1), fwd);
    link_x = 100;
    link_x +%= fwd;
    try testing.expectEqual(@as(u16, 101), link_x);
}
