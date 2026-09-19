//! Optional differential checks against the original C implementation.
//! Run with python3 other/check_ancilla_parity.py.
const std = @import("std");
const ancilla = @import("../src/ancilla.zig");
const vars = @import("../src/variables.zig");
const rtl = @import("../src/zelda_rtl.zig");
const sprite = @import("../src/sprite.zig");
const features = @import("../src/features.zig");
const Point16U = ancilla.Point16U;
const CheckPlayerCollOut = ancilla.CheckPlayerCollOut;
const AncillaRadialProjection = ancilla.AncillaRadialProjection;
const ProjectSpeedRet = sprite.ProjectSpeedRet;
const AncillaAdd_ArrowFindSlot = ancilla.AncillaAdd_ArrowFindSlot;
const Ancilla_AllocInit = ancilla.Ancilla_AllocInit;
const Ancilla_CheckLinkCollision = ancilla.Ancilla_CheckLinkCollision;
const Ancilla_CheckSpriteCollision_Single = ancilla.Ancilla_CheckSpriteCollision_Single;
const Ancilla_GetRadialProjection = ancilla.Ancilla_GetRadialProjection;
const Ancilla_MoveX = ancilla.Ancilla_MoveX;
const Ancilla_MoveY = ancilla.Ancilla_MoveY;
const Ancilla_MoveZ = ancilla.Ancilla_MoveZ;
const Ancilla_ProjectSpeedTowardsPlayer = ancilla.Ancilla_ProjectSpeedTowardsPlayer;
const Ancilla_SetXY = ancilla.Ancilla_SetXY;
const Arrow_Draw = ancilla.Arrow_Draw;
const Bomb_CheckUndersideSpriteStatus = ancilla.Bomb_CheckUndersideSpriteStatus;

fn loPtr(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

extern fn Ref_Ancilla_MoveX(k: c_int) void;
extern fn Ref_Ancilla_MoveY(k: c_int) void;
extern fn Ref_Ancilla_MoveZ(k: c_int) void;
extern fn Ref_Ancilla_AllocInit(atype: u8, limit: u8) c_int;
extern fn Ref_AncillaAdd_ArrowFindSlot(atype: u8, limit: u8) c_int;
extern fn Ref_Arrow_Draw(k: c_int) void;
extern fn Ref_Ancilla_CheckLinkCollision(k: c_int, j: c_int, out: *CheckPlayerCollOut) bool;
extern fn Ref_Ancilla_GetRadialProjection(a: u8, radius: u8) AncillaRadialProjection;
extern fn Ref_Bomb_CheckUndersideSpriteStatus(k: c_int, pt: *Point16U, shadow: *u8) bool;
extern fn Ref_Ancilla_ProjectSpeedTowardsPlayer(k: c_int, vel: u8) ProjectSpeedRet;
extern fn Ref_Ancilla_CheckSpriteCollision_Single(k: c_int, j: c_int) bool;

test "C parity: fixed point movement covers every velocity and carry boundary" {
    for (0..256) |v| {
        for ([_]u16{ 0, 1, 0xff, 0x100, 0x7fff, 0xffff }) |coord| {
            for ([_]u8{ 0, 1, 15, 16, 127, 255 }) |fraction| {
                @memset(&rtl.g_ram, 0);
                Ancilla_SetXY(0, coord, coord);
                vars.ancilla_z[0] = @truncate(coord);
                vars.ancilla_x_subpixel[0] = fraction;
                vars.ancilla_y_subpixel[0] = fraction;
                vars.ancilla_z_subpixel[0] = fraction;
                vars.ancilla_x_vel[0] = @intCast(v);
                vars.ancilla_y_vel[0] = @intCast(v);
                vars.ancilla_z_vel[0] = @intCast(v);
                const before = rtl.g_ram;
                Ref_Ancilla_MoveX(0);
                Ref_Ancilla_MoveY(0);
                Ref_Ancilla_MoveZ(0);
                const expected = rtl.g_ram;
                rtl.g_ram = before;
                Ancilla_MoveX(0);
                Ancilla_MoveY(0);
                Ancilla_MoveZ(0);
                try std.testing.expectEqualSlices(u8, &expected, &rtl.g_ram);
            }
        }
    }
}

test "C parity: allocation limits and rotating replacement" {
    var prng = std.Random.DefaultPrng.init(419);
    const choices = [_]u8{ 0, 7, 8, 9, 10, 0x13, 0x3c, 0x2c };
    for (0..3000) |n| {
        @memset(&rtl.g_ram, 0);
        const atype = choices[1 + n % 7];
        const limit: u8 = @intCast(n % 5);
        for (0..6) |i| vars.ancilla_type[i] = choices[prng.random().uintLessThan(usize, choices.len)];
        vars.ancilla_alloc_rotate.* = @intCast(n % 5);
        rtl.g_ram[features.kRam_BugsFixed] = @intCast(n % 2);
        loPtr(vars.R14).* = 77;
        const before = rtl.g_ram;
        const expected_slot = Ref_Ancilla_AllocInit(atype, limit);
        const expected = rtl.g_ram;
        rtl.g_ram = before;
        try std.testing.expectEqual(expected_slot, Ancilla_AllocInit(atype, limit));
        try std.testing.expectEqualSlices(u8, &expected, &rtl.g_ram);
        rtl.g_ram = before;
        const expected_arrow = Ref_AncillaAdd_ArrowFindSlot(9, limit);
        const expected_arrow_ram = rtl.g_ram;
        rtl.g_ram = before;
        try std.testing.expectEqual(expected_arrow, AncillaAdd_ArrowFindSlot(9, limit));
        try std.testing.expectEqualSlices(u8, &expected_arrow_ram, &rtl.g_ram);
    }
}

test "C parity: arrow drawing at screen edges and on moving floors" {
    for (0..8) |dir| for (0..9) |frame| for ([_]u16{ 0, 1, 8, 127, 224, 240, 255, 256, 0xfffc }) |xy| {
        for (0..8) |mode| {
            @memset(&rtl.g_ram, 0);
            @memset(rtl.g_ram[0x800..0xa00], 0xf0);
            vars.oam_cur_ptr.* = 0x820;
            vars.ancilla_type[0] = if (mode & 1 != 0) 10 else 9;
            vars.ancilla_dir[0] = @intCast(dir);
            vars.ancilla_item_to_link[0] = @intCast(frame);
            vars.ancilla_H[0] = @intCast(mode & 2);
            vars.link_item_bow.* = @intCast(mode & 4);
            vars.BG1HOFS_copy2.* = 9;
            vars.BG1VOFS_copy2.* = 13;
            features.enhanced_features0.* = if (mode & 4 != 0) features.kFeatures0_ExtendScreen64 else 0;
            Ancilla_SetXY(0, xy, xy);
            const before = rtl.g_ram;
            Ref_Arrow_Draw(0);
            const expected = rtl.g_ram;
            rtl.g_ram = before;
            Arrow_Draw(0);
            try std.testing.expectEqualSlices(u8, &expected, &rtl.g_ram);
        }
    };
}

test "C parity: radial projections at every angle and radius" {
    for (0..64) |a| for (0..256) |r| {
        try std.testing.expectEqual(Ref_Ancilla_GetRadialProjection(@intCast(a), @intCast(r)), Ancilla_GetRadialProjection(@intCast(a), @intCast(r)));
    };
}

test "C parity: player collision and bomb shadows preserve signed altitude" {
    for (0..256) |z| for (0..5) |kind| {
        @memset(&rtl.g_ram, 0);
        Ancilla_SetXY(0, 0xfff8, 0xfffd);
        vars.link_x_coord.* = 0;
        vars.link_y_coord.* = 4;
        vars.ancilla_z[0] = @intCast(z);
        var expected_out: CheckPlayerCollOut = undefined;
        var out: CheckPlayerCollOut = undefined;
        const expected_hit = Ref_Ancilla_CheckLinkCollision(0, @intCast(kind), &expected_out);
        try std.testing.expectEqual(expected_hit, Ancilla_CheckLinkCollision(0, @intCast(kind), &out));
        try std.testing.expectEqual(expected_out, out);
        vars.ancilla_tile_attr[0] = if (kind == 0) 9 else if (kind == 1) 0x40 else 0;
        vars.ancilla_arr22[0] = @intCast(kind);
        vars.ancilla_arr23[0] = @intCast(kind % 3);
        vars.sound_effect_1.* = 0xb;
        var pt = Point16U{ .x = 1, .y = 0xfffc };
        var expected_pt = pt;
        var shadow: u8 = 0;
        var expected_shadow: u8 = 0;
        const before = rtl.g_ram;
        const expected_result = Ref_Bomb_CheckUndersideSpriteStatus(0, &expected_pt, &expected_shadow);
        const expected = rtl.g_ram;
        rtl.g_ram = before;
        try std.testing.expectEqual(expected_result, Bomb_CheckUndersideSpriteStatus(0, &pt, &shadow));
        try std.testing.expectEqual(expected_pt, pt);
        try std.testing.expectEqual(expected_shadow, shadow);
        try std.testing.expectEqualSlices(u8, &expected, &rtl.g_ram);
    };
}

test "C parity: projected speeds preserve byte arithmetic" {
    var prng = std.Random.DefaultPrng.init(712);
    for (0..4000) |_| {
        @memset(&rtl.g_ram, 0);
        Ancilla_SetXY(0, prng.random().int(u16), prng.random().int(u16));
        vars.link_x_coord.* = prng.random().int(u16);
        vars.link_y_coord.* = prng.random().int(u16);
        const vel = prng.random().int(u8);
        try std.testing.expectEqual(Ref_Ancilla_ProjectSpeedTowardsPlayer(0, vel), Ancilla_ProjectSpeedTowardsPlayer(0, vel));
    }
}

test "C parity: deflected arrows reread their type after sprite creation" {
    for ([_]u8{ 0, 2, 3 }) |bow| {
        @memset(&rtl.g_ram, 0);
        Ancilla_SetXY(0, 100, 100);
        sprite.Sprite_SetX(1, 100);
        sprite.Sprite_SetY(1, 100);
        vars.ancilla_type[0] = 9;
        vars.ancilla_dir[0] = 0;
        vars.sprite_type[1] = 0x1b;
        vars.sprite_state[1] = 9;
        vars.sprite_flags[1] = 8;
        vars.sprite_C[1] = 3;
        vars.sprite_health[1] = 100;
        vars.link_item_bow.* = bow;
        const before = rtl.g_ram;
        const expected_hit = Ref_Ancilla_CheckSpriteCollision_Single(0, 1);
        const expected = rtl.g_ram;
        rtl.g_ram = before;
        try std.testing.expectEqual(expected_hit, Ancilla_CheckSpriteCollision_Single(0, 1));
        try std.testing.expectEqualSlices(u8, &expected, &rtl.g_ram);
    }
}

extern fn Ref_Ancilla16_HitStars(k: c_int) void;
extern fn Ref_Ancilla17_ShovelDirt(k: c_int) void;
extern fn Ref_Ancilla_MagicPowder_Draw(k: c_int) void;
extern fn Ref_DashDust_Motive(k: c_int) void;
extern fn Ref_Ancilla0A_ArrowInTheWall(k: c_int) void;
extern fn Ref_Ancilla11_IceRodWallHit(k: c_int) void;
extern fn Ref_DoorDebris_Draw(k: c_int) void;
extern fn Ref_WallHit_Draw(k: c_int) void;
extern fn Ref_Boomerang_Draw(k: c_int) void;

extern fn Ref_Ancilla15_JumpSplash(k: c_int) void;
extern fn Ref_Ancilla32_BlastWallFireball(k: c_int) void;
extern fn Ref_EtherSpell_HandleLightningStroke(k: c_int) void;
extern fn Ref_EtherSpell_HandleOrbPulse(k: c_int) void;
extern fn Ref_AncillaDraw_EtherBlitz(k: c_int) void;

test "C parity: effect animation and OAM writes match across pauses and edges" {
    const Handler = *const fn (c_int) callconv(.c) void;
    const pairs = [_]struct { original: Handler, port: Handler }{
        .{ .original = Ref_Ancilla15_JumpSplash, .port = ancilla.Ancilla15_JumpSplash },
        .{ .original = Ref_Ancilla32_BlastWallFireball, .port = ancilla.Ancilla32_BlastWallFireball },
        .{ .original = Ref_EtherSpell_HandleLightningStroke, .port = ancilla.EtherSpell_HandleLightningStroke },
        .{ .original = Ref_EtherSpell_HandleOrbPulse, .port = ancilla.EtherSpell_HandleOrbPulse },
        .{ .original = Ref_AncillaDraw_EtherBlitz, .port = ancilla.AncillaDraw_EtherBlitz },
        .{ .original = Ref_Ancilla16_HitStars, .port = ancilla.Ancilla16_HitStars },
        .{ .original = Ref_Ancilla17_ShovelDirt, .port = ancilla.Ancilla17_ShovelDirt },
        .{ .original = Ref_Ancilla_MagicPowder_Draw, .port = ancilla.Ancilla_MagicPowder_Draw },
        .{ .original = Ref_DashDust_Motive, .port = ancilla.DashDust_Motive },
        .{ .original = Ref_Ancilla0A_ArrowInTheWall, .port = ancilla.Ancilla0A_ArrowInTheWall },
        .{ .original = Ref_Ancilla11_IceRodWallHit, .port = ancilla.Ancilla11_IceRodWallHit },
        .{ .original = Ref_DoorDebris_Draw, .port = ancilla.DoorDebris_Draw },
        .{ .original = Ref_WallHit_Draw, .port = ancilla.WallHit_Draw },
        .{ .original = Ref_Boomerang_Draw, .port = ancilla.Boomerang_Draw },
    };
    for (pairs, 0..) |pair, handler| for (0..128) |n| {
        @memset(&rtl.g_ram, 0);
        sprite.Oam_ResetRegionBases();
        vars.oam_cur_ptr.* = 0x820;
        vars.oam_ext_cur_ptr.* = 0xa28;
        vars.sort_sprites_setting.* = @intCast(n & 1);
        vars.submodule_index.* = @intCast((n >> 1) & 1);
        vars.link_direction_facing.* = @intCast((n & 3) * 2);
        vars.ancilla_type[0] = 10;
        vars.ancilla_dir[0] = @intCast(n & 3);
        vars.ancilla_floor[0] = @intCast(n & 3);
        vars.ancilla_item_to_link[0] = @intCast(n & 1);
        vars.ancilla_timer[0] = @intCast(n & 3);
        vars.ancilla_aux_timer[0] = @intCast(n & 3);
        vars.ancilla_arr3[0] = @intCast(n & 3);
        vars.ancilla_arr25[0] = @intCast(n & 3);
        vars.ancilla_step[0] = @intCast(n & 3);
        vars.ancilla_S[0] = 255;
        vars.ancilla_L[0] = 4;
        vars.ancilla_y_vel[0] = 0xfc;
        vars.ancilla_A[0] = 250;
        vars.door_debris_x[0] = 250;
        vars.door_debris_y[0] = 250;
        vars.door_debris_direction[0] = @intCast(n & 3);
        vars.BG2HOFS_copy2.* = 8;
        vars.BG2VOFS_copy2.* = 8;
        Ancilla_SetXY(0, @intCast(n * 4), @intCast(n * 4));
        const before = rtl.g_ram;
        pair.original(0);
        const expected = rtl.g_ram;
        rtl.g_ram = before;
        pair.port(0);
        if (!std.mem.eql(u8, &expected, &rtl.g_ram)) std.debug.print("handler {d}, case {d}\n", .{ handler, n });
        try std.testing.expectEqualSlices(u8, &expected, &rtl.g_ram);
    };
}

extern fn Ref_AncillaDraw_EtherBlitzBall(oam: [*]align(1) vars.OamEnt, p: *const AncillaRadialProjection, frame: c_int) [*]align(1) vars.OamEnt;
extern fn Ref_AncillaDraw_EtherBlitzSegment(oam: [*]align(1) vars.OamEnt, p: *const AncillaRadialProjection, frame: c_int, k: c_int) [*]align(1) vars.OamEnt;
extern fn Ref_AncillaDraw_EtherOrb(k: c_int, oam: [*]align(1) vars.OamEnt) void;

test "C parity: Ether radial drawing preserves signed offsets and OAM wrapping" {
    for (0..64) |angle| for (0..2) |frame| for (0..8) |segment| {
        @memset(&rtl.g_ram, 0);
        vars.oam_cur_ptr.* = if (segment & 1 == 0) 0x8dc else 0x9cc;
        vars.sort_sprites_setting.* = @intCast(segment & 1);
        vars.BG2HOFS_copy2.* = 200;
        vars.BG2VOFS_copy2.* = 180;
        // Ether's file-local scratch aliases differ from variables.h.
        const x: *align(1) u16 = @ptrCast(&rtl.g_ram[0x1580e]);
        const y: *align(1) u16 = @ptrCast(&rtl.g_ram[0x15810]);
        x.* = @intCast(angle * 8);
        y.* = @intCast(angle * 7);
        const p = Ancilla_GetRadialProjection(@intCast(angle), @intCast(segment * 32));
        const oam: [*]align(1) vars.OamEnt = @ptrCast(&rtl.g_ram[vars.oam_cur_ptr.*]);
        const before = rtl.g_ram;
        const expected_end = Ref_AncillaDraw_EtherBlitzBall(oam, &p, @intCast(frame));
        const expected = rtl.g_ram;
        rtl.g_ram = before;
        try std.testing.expectEqual(@intFromPtr(expected_end), @intFromPtr(ancilla.AncillaDraw_EtherBlitzBall(oam, &p, @intCast(frame))));
        try std.testing.expectEqualSlices(u8, &expected, &rtl.g_ram);
        rtl.g_ram = before;
        const expected_segment_end = Ref_AncillaDraw_EtherBlitzSegment(oam, &p, @intCast(frame), @intCast(segment));
        const expected_segment = rtl.g_ram;
        rtl.g_ram = before;
        try std.testing.expectEqual(@intFromPtr(expected_segment_end), @intFromPtr(ancilla.AncillaDraw_EtherBlitzSegment(oam, &p, @intCast(frame), @intCast(segment))));
        try std.testing.expectEqualSlices(u8, &expected_segment, &rtl.g_ram);
        vars.ancilla_item_to_link[0] = @intCast(frame);
        const orb_before = rtl.g_ram;
        Ref_AncillaDraw_EtherOrb(0, oam);
        const expected_orb = rtl.g_ram;
        rtl.g_ram = orb_before;
        ancilla.AncillaDraw_EtherOrb(0, oam);
        try std.testing.expectEqualSlices(u8, &expected_orb, &rtl.g_ram);
    };
}
