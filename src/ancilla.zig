//! Handwritten port of ancilla objects: projectiles, bombs, effects, and props.
//! Exported routines replace their definitions in ancilla.c. The remaining C
//! routines are declared at the temporary ABI boundary below and still linked.
const std = @import("std");
const vars = @import("variables.zig");
const tables = @import("ancilla_tables.zig");
const features = @import("features.zig");
const config = @import("config.zig");
const misc = @import("misc.zig");
const sprite = @import("sprite.zig");
const hud = @import("hud.zig");
const load_gfx = @import("load_gfx.zig");
const tagalong = @import("tagalong.zig");
const overworld = @import("overworld.zig");
const ow_tables = @import("overworld_tables.zig");
const tile_detect = @import("tile_detect.zig");
const player = @import("player.zig");
const audio = @import("audio.zig");
const rtl = @import("zelda_rtl.zig");
const main_mod = @import("main.zig");

const OamEnt = vars.OamEnt;

/// Aliases, not new definitions: Zig types are nominal, so a local copy would
/// not coerce into the struct the other module's functions expect.
pub const Point16U = overworld.Point16U;
pub const CheckPlayerCollOut = player.CheckPlayerCollOut;
const ProjectSpeedRet = sprite.ProjectSpeedRet;
const PairU8 = sprite.PairU8;
const SpriteHitBox = sprite.SpriteHitBox;
const SpriteSpawnInfo = sprite.SpriteSpawnInfo;

/// ancilla.h types that have no Zig definition yet.
pub const AncillaOamInfo = extern struct { x: u8, y: u8, flags: u8 };
pub const AncillaRadialProjection = extern struct { r0: u8, r2: u8, r4: u8, r6: u8 };

const HandlerFuncK = fn (c_int) callconv(.c) void;

// ---------------------------------------------------------------------------
// Scratch aliases over work RAM.
//
// ancilla.c #defines these over g_ram. Several names (ether_x, ether_y,
// ether_y3, ether_var1) also exist as accessors in variables.zig; inside
// ancilla.c the macro shadows the variable, so these addresses are what the C
// actually used and are what the port reproduces.
// ---------------------------------------------------------------------------
inline fn ramU8(comptime addr: usize) *u8 {
    return @ptrCast(&rtl.g_ram[addr]);
}
inline fn ramU16(comptime addr: usize) *align(1) u16 {
    return @ptrCast(&rtl.g_ram[addr]);
}
inline fn ramArr(comptime addr: usize) [*]u8 {
    return @ptrCast(&rtl.g_ram[addr]);
}

inline fn swordbeam_arr() [*]u8 {
    return ramArr(0x15800);
}
inline fn swordbeam_var1() *u8 {
    return ramU8(0x15804);
}
inline fn swordbeam_var2() *u8 {
    return ramU8(0x15808);
}
inline fn swordbeam_temp_x() *align(1) u16 {
    return ramU16(0x1580E);
}
inline fn swordbeam_temp_y() *align(1) u16 {
    return ramU16(0x15810);
}

inline fn ether_arr1() [*]u8 {
    return ramArr(0x15800);
}
inline fn ether_var2() *u8 {
    return ramU8(0x15808);
}
inline fn ether_y2() *align(1) u16 {
    return ramU16(0x1580A);
}
inline fn ether_y_adjusted() *align(1) u16 {
    return ramU16(0x1580C);
}
inline fn ether_x2() *align(1) u16 {
    return ramU16(0x1580E);
}
inline fn ether_y3() *align(1) u16 {
    return ramU16(0x15810);
}
inline fn ether_var1() *u8 {
    return ramU8(0x15812);
}
inline fn ether_y() *align(1) u16 {
    return ramU16(0x15813);
}
inline fn ether_x() *align(1) u16 {
    return ramU16(0x15815);
}

inline fn bombos_arr1() [*]u8 {
    return ramArr(0x15800);
}
inline fn bombos_arr2() [*]u8 {
    return ramArr(0x15810);
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

inline fn sign8(v: u8) bool {
    return v >= 0x80;
}
inline fn sign16(v: u16) bool {
    return v >= 0x8000;
}
inline fn abs8(v: u8) u8 {
    return if (sign8(v)) 0 -% v else v;
}
inline fn abs16(v: u16) u16 {
    return if (sign16(v)) 0 -% v else v;
}

/// types.h: #define XY(x, y) ((y)*64+(x))
inline fn XY(comptime x: i32, comptime y: i32) i32 {
    return y * 64 + x;
}

/// types.h BYTE(): the low byte of a 16-bit work-ram variable.
inline fn loPtr(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}
/// types.h HIBYTE().
inline fn hiPtr(p: *align(1) u16) *u8 {
    return @ptrCast(@as([*]u8, @ptrCast(p)) + 1);
}

inline fn assetU8(comptime i: usize) [*]const u8 {
    return main_mod.g_asset_ptrs[i].?;
}
/// assets.h: kGeneratedWishPondItem is asset 71, kGeneratedBombosArr is 72.
inline fn kGeneratedWishPondItem() [*]const u8 {
    return assetU8(71);
}
inline fn kGeneratedBombosArr() [*]const u8 {
    return assetU8(72);
}

inline fn GetOamCurPtr() [*]align(1) OamEnt {
    return @ptrCast(&rtl.g_ram[vars.oam_cur_ptr.*]);
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

/// sprite.h static inline.
inline fn SetOamPlain(oam: [*]align(1) OamEnt, x: u8, y: u8, charnum: u8, flags: u8, big: u8) void {
    oam[0].x = x;
    oam[0].y = y;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    vars.bytewise_extended_oam[oamIndex(oam)] = big;
}

inline fn oamIndex(oam: [*]align(1) OamEnt) usize {
    return (@intFromPtr(oam) - @intFromPtr(vars.oam_buf)) / @sizeOf(OamEnt);
}

// ---------------------------------------------------------------------------
// Functions still provided by the remaining C (dungeon.c, sprite_main.c).
// ---------------------------------------------------------------------------
extern fn Bomb_CheckForDestructibles(x: u16, y: u16, r14: u8) void;
extern fn Ancilla_TerminateSparkleObjects() void;
extern fn PrepareDungeonExitFromBossFight() void;
extern fn Sprite_SpawnPoofGarnish(j: c_int) void;

// ---------------------------------------------------------------------------
// Tables the generator could not emit.
//
// checkdims2 reports 0 dimension mismatches over the 351 generated tables; the
// three below are the only definitions in ancilla.c it does not cover, because
// it emits scalar arrays only. kQuakeItems/kQuakeItems2 are arrays of a struct
// and kAncilla_Funcs is an array of function pointers.
// ---------------------------------------------------------------------------

const QuakeItem = extern struct { x: i8, y: i8, f: u8 };

inline fn qi(x: i8, y: i8, f: u8) QuakeItem {
    return .{ .x = x, .y = y, .f = f };
}

const kQuakeItems = [_]QuakeItem{
    qi(0, -16, 0x00),     qi(0, -16, 0x01),    qi(0, -16, 0x02),     qi(0, -16, 0x03),
    qi(0, -16, 0x43),     qi(0, -16, 0x42),    qi(0, -16, 0x41),     qi(0, -16, 0x40),
    qi(0, -16, 0x40),     qi(14, -8, 0x84),    qi(29, -8, 0x44),     qi(13, -7, 0x84),
    qi(31, -7, 0x44),     qi(47, -4, 0x84),    qi(49, -11, 0x06),    qi(63, -5, 0x44),
    qi(47, -4, 0x84),     qi(36, -17, 0x08),   qi(49, -11, 0x06),    qi(63, -5, 0x44),
    qi(78, 4, 0x08),      qi(22, -31, 0x08),   qi(36, -17, 0x08),    qi(78, 4, 0x08),
    qi(93, 20, 0x08),     qi(7, -46, 0x08),    qi(23, -45, 0x48),    qi(22, -31, 0x08),
    qi(93, 20, 0x08),     qi(93, 36, 0x48),    qi(-7, -61, 0x08),    qi(37, -59, 0x48),
    qi(7, -46, 0x08),     qi(23, -45, 0x48),   qi(93, 36, 0x48),     qi(93, 52, 0x08),
    qi(-22, -75, 0x08),   qi(47, -74, 0x01),   qi(-8, -61, 0x08),    qi(36, -60, 0x48),
    qi(93, 52, 0x08),     qi(108, 67, 0x08),   qi(-37, -90, 0x08),   qi(-22, -75, 0x08),
    qi(47, -74, 0x01),    qi(59, -62, 0x81),   qi(108, 67, 0x08),    qi(121, 80, 0x08),
    qi(-44, -104, 0xc9),  qi(-37, -90, 0x08),  qi(73, -74, 0x48),    qi(59, -62, 0x81),
    qi(121, 80, 0x08),    qi(-44, -120, 0x09), qi(-44, -104, 0xc9),  qi(87, -89, 0x48),
    qi(73, -74, 0x48),    qi(-44, -120, 0x09), qi(102, -104, 0x48),  qi(87, -89, 0x48),
    qi(102, -104, 0x48),  qi(87, -89, 0x48),   qi(112, -116, 0x48),  qi(102, -104, 0x48),
    qi(112, -116, 0x48),  qi(-13, -16, 0x00),  qi(-13, -16, 0x01),   qi(-13, -16, 0x02),
    qi(-13, -16, 0x03),   qi(-11, -16, 0x43),  qi(-11, -16, 0x42),   qi(-11, -16, 0x41),
    qi(-11, -16, 0x40),   qi(-24, -10, 0x04),  qi(-38, -18, 0x08),   qi(-24, -10, 0x04),
    qi(-40, -7, 0xc4),    qi(-45, -33, 0xc9),  qi(-38, -18, 0x08),   qi(-57, -7, 0x04),
    qi(-40, -7, 0xc4),    qi(-48, -45, 0x07),  qi(-45, -33, 0xc9),   qi(-57, -7, 0x04),
    qi(-71, 2, 0x48),     qi(-48, -45, 0x06),  qi(-71, 2, 0x48),     qi(-70, 18, 0x08),
    qi(-48, -45, 0x05),   qi(-70, 18, 0x08),   qi(-56, 33, 0x08),    qi(-48, -45, 0x07),
    qi(-54, 34, 0x08),    qi(-54, 49, 0x88),   qi(-48, -45, 0x06),   qi(-54, 49, 0x88),
    qi(-69, 64, 0x88),    qi(-48, -45, 0x07),  qi(-69, 64, 0x88),    qi(-85, 73, 0xc4),
    qi(-48, -45, 0x05),   qi(-101, 73, 0x04),  qi(-85, 73, 0xc4),    qi(-60, -53, 0x08),
    qi(-48, -45, 0x06),   qi(-101, 73, 0x04),  qi(-116, 77, 0xc4),   qi(-75, -67, 0x08),
    qi(-60, -53, 0x08),   qi(-128, 76, 0x04),  qi(-116, 77, 0xc4),   qi(-90, -82, 0x08),
    qi(-75, -67, 0x08),   qi(-128, 76, 0x04),  qi(-105, -97, 0x08),  qi(-90, -82, 0x08),
    qi(-120, -111, 0x08), qi(-105, -97, 0x08), qi(-120, -111, 0x08), qi(0, -5, 0x0a),
    qi(0, -5, 0x0b),      qi(2, -3, 0x0c),     qi(1, -3, 0x0d),      qi(0, -3, 0x8d),
    qi(1, -3, 0x8c),      qi(1, -3, 0x8b),     qi(1, -3, 0x8a),      qi(-6, 12, 0x89),
    qi(-6, 12, 0x89),     qi(-10, 28, 0xc9),   qi(-10, 28, 0x49),    qi(-8, 44, 0x89),
    qi(-8, 44, 0x89),     qi(-10, 56, 0x02),   qi(-10, 56, 0x02),    qi(-23, 70, 0x48),
    qi(5, 70, 0x08),      qi(-23, 70, 0x48),   qi(5, 70, 0x08),      qi(-38, 85, 0x48),
    qi(19, 85, 0x08),     qi(-38, 85, 0x48),   qi(19, 85, 0x08),     qi(-52, 99, 0x48),
    qi(33, 101, 0x08),    qi(-52, 99, 0x48),   qi(33, 101, 0x08),    qi(-66, 113, 0x48),
    qi(47, 115, 0x08),    qi(-66, 113, 0x48),  qi(47, 115, 0x08),
};

const kQuakeItems2 = [_]QuakeItem{
    qi(-96, 112, 0x20),
    qi(-96, 112, 0x21),
    qi(-96, 112, 0x66),
    qi(-96, 112, 0x22),
    qi(-96, 112, 0x23),
    qi(-96, 112, 0x63),
    qi(-96, 112, 0x62),
    qi(-96, 112, 0x26),
    qi(-96, 112, 0x27),
    qi(-86, 124, 0x28),
    qi(-86, 124, 0x28),
    qi(-72, -117, 0x28),
    qi(-72, -117, 0x28),
    qi(-59, -102, 0xa1),
    qi(-59, -102, 0xa1),
    qi(-44, -116, 0x68),
    qi(-44, -116, 0x68),
    qi(-29, 126, 0x68),
    qi(-29, 126, 0x68),
    qi(-19, 125, 0xc5),
    qi(-112, 96, 0x2a),
    qi(-112, 96, 0x2b),
    qi(-112, 96, 0x2c),
    qi(-112, 96, 0x2d),
    qi(-119, 82, 0x29),
    qi(-112, 96, 0x2a),
    qi(-123, 66, 0xe9),
    qi(-119, 82, 0x29),
    qi(-121, 50, 0x29),
    qi(-123, 66, 0xe9),
    qi(126, 34, 0x28),
    qi(-115, 34, 0x68),
    qi(-121, 50, 0x29),
    qi(-106, 18, 0xa9),
    qi(111, 19, 0x28),
    qi(126, 34, 0x28),
    qi(-115, 34, 0x68),
    qi(-100, 2, 0x68),
    qi(102, 4, 0xe9),
    qi(-106, 18, 0xa9),
    qi(111, 19, 0x28),
    qi(-91, -14, 0xa9),
    qi(95, -11, 0x28),
    qi(-100, 2, 0x68),
    qi(102, 4, 0xe9),
    qi(96, 112, 0x60),
    qi(96, 112, 0x61),
    qi(96, 112, 0x26),
    qi(96, 112, 0x62),
    qi(96, 112, 0x63),
    qi(96, 112, 0x23),
    qi(96, 112, 0x22),
    qi(96, 112, 0x66),
    qi(85, 111, 0xe8),
    qi(96, 112, 0x67),
    qi(70, 104, 0x24),
    qi(85, 111, 0xe8),
    qi(70, 104, 0x24),
    qi(54, 108, 0xe4),
    qi(40, 100, 0x28),
    qi(38, 107, 0x24),
    qi(54, 108, 0xe4),
    qi(25, 85, 0x28),
    qi(40, 100, 0x28),
    qi(38, 107, 0x24),
    qi(22, 110, 0xe4),
    qi(11, 70, 0x28),
    qi(25, 85, 0x28),
    qi(7, 108, 0x24),
    qi(22, 110, 0xe4),
    qi(11, 70, 0x28),
    qi(7, 108, 0x24),
    qi(112, 112, 0x2a),
    qi(112, 112, 0x2b),
    qi(112, 112, 0x2c),
    qi(112, 112, 0x2d),
    qi(112, 112, 0x2a),
    qi(108, 125, 0x29),
    qi(108, 125, 0x29),
    qi(114, -116, 0x28),
    qi(114, -116, 0x28),
    qi(124, -100, 0x29),
    qi(124, -100, 0x29),
    qi(123, -84, 0xe9),
    qi(123, -84, 0xe9),
    qi(117, -74, 0xe4),
    qi(-124, -69, 0x28),
    qi(117, -74, 0xe4),
    qi(-124, -69, 0x28),
    qi(103, -67, 0x68),
    qi(-110, -54, 0x28),
    qi(103, -67, 0x68),
    qi(-110, -54, 0x28),
    qi(95, -52, 0x69),
    qi(-102, -39, 0x29),
    qi(95, -52, 0x69),
    qi(-102, -39, 0x29),
    qi(96, -36, 0xe9),
    qi(-102, -24, 0xe9),
    qi(96, -36, 0xe9),
    qi(-102, -24, 0xe9),
    qi(-123, -14, 0x29),
    qi(-115, -14, 0x2e),
    qi(49, -12, 0x28),
};

pub export fn Ancilla_GetX(k: c_int) callconv(.c) u16 {
    const u: usize = @intCast(k);
    return vars.ancilla_x_lo[u] | (@as(u16, vars.ancilla_x_hi[u]) << 8);
}

pub export fn Ancilla_GetY(k: c_int) callconv(.c) u16 {
    const u: usize = @intCast(k);
    return vars.ancilla_y_lo[u] | (@as(u16, vars.ancilla_y_hi[u]) << 8);
}

pub export fn Ancilla_SetX(k: c_int, x: u16) callconv(.c) void {
    const u: usize = @intCast(k);
    vars.ancilla_x_lo[u] = @truncate(x);
    vars.ancilla_x_hi[u] = @truncate(x >> 8);
}

pub export fn Ancilla_SetY(k: c_int, y: u16) callconv(.c) void {
    const u: usize = @intCast(k);
    vars.ancilla_y_lo[u] = @truncate(y);
    vars.ancilla_y_hi[u] = @truncate(y >> 8);
}

pub export fn Ancilla_AllocHigh() callconv(.c) c_int {
    var k: isize = 9;
    while (k >= 0) : (k -= 1) {
        if (vars.ancilla_type[@intCast(k)] == 0)
            return @intCast(k);
    }
    return -1;
}

/// File-local in the C (not declared in ancilla.h).
fn Ancilla_SetOam(oam: [*]align(1) OamEnt, x: u16, y: u16, charnum: u8, flags: u8, big_in: u8) void {
    var big = big_in;
    var yval: u8 = 0xf0;
    const xt: i32 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x40 else 0;
    const xsum: u16 = @truncate(@as(u32, @bitCast(@as(i32, x) +% xt)));
    if (@as(i32, xsum) < 256 + xt * 2 and y < 256) {
        big |= @as(u8, @truncate(x >> 8)) & 1;
        oam[0].x = @truncate(x);
        if (y < 0xf0)
            yval = @truncate(y);
    }
    oam[0].y = yval;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    vars.bytewise_extended_oam[oamIndex(oam)] = big;
}

/// File-local in the C (not declared in ancilla.h).
fn Ancilla_SetOam_Safe(oam: [*]align(1) OamEnt, x: u16, y: u16, charnum: u8, flags: u8, big_in: u8) void {
    var big = big_in;
    var yval: u8 = 0xf0;
    oam[0].x = @truncate(x);
    const xt: i32 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x48 else 0;
    if (@as(i32, @as(u16, x +% 0x80)) < 0x180 + xt) {
        big |= @as(u8, @truncate(x >> 8)) & 1;
        if (@as(u16, y +% 0x10) < 0x100)
            yval = @truncate(y);
    }
    oam[0].y = yval;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    vars.bytewise_extended_oam[oamIndex(oam)] = big;
}

pub export fn Ancilla_Empty(k: c_int) callconv(.c) void {
    _ = k;
}

pub export fn Ancilla_Unused_14(k: c_int) callconv(.c) void {
    _ = k;
    unreachable;
}

pub export fn Ancilla_Unused_25(k: c_int) callconv(.c) void {
    _ = k;
    unreachable;
}

pub export fn SpinSpark_Draw(k: c_int, offs: c_int) callconv(.c) void {
    // kInitialSpinSpark_Char runs past index 27 in the C ("wtf oob"); the
    // generated [32]u8 preserves that tail.
    var info: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &info);
    var oam = GetOamCurPtr();
    var t: usize = @intCast((@as(c_int, vars.ancilla_item_to_link[@intCast(k)]) + offs) * 4);
    var i: usize = 0;
    while (i < 4) : ({
        i += 1;
        t += 1;
    }) {
        if (tables.kInitialSpinSpark_Char[t] != 0xff) {
            Ancilla_SetOam(
                oam,
                info.x +% @as(u16, @bitCast(tables.kInitialSpinSpark_X[t])),
                info.y +% @as(u16, @bitCast(@as(i16, tables.kInitialSpinSpark_Y[t]))),
                tables.kInitialSpinSpark_Char[t],
                (tables.kInitialSpinSpark_Flags[t] & ~@as(u8, 0x30)) | hiPtr(vars.oam_priority_value).*,
                0,
            );
            oam += 1;
        }
    }
}

pub export fn SomarianBlock_CheckEmpty(oam: [*]align(1) OamEnt) callconv(.c) bool {
    const base = oamIndex(oam);
    var i: usize = 0;
    while (i != 4) : (i += 1) {
        if (oam[i].y == 0xf0)
            continue;
        var j: usize = 0;
        while (j < 4) : (j += 1) {
            if (vars.bytewise_extended_oam[base + j] & 1 == 0)
                return false;
        }
        break;
    }
    return true;
}

pub export fn AddDashingDustEx(a: u8, y: u8, flag: u8) callconv(.c) void {
    const k = Ancilla_AddAncilla(a, y);
    if (k >= 0) {
        const u: usize = @intCast(k);
        vars.ancilla_step[u] = flag;
        vars.ancilla_item_to_link[u] = 0;
        vars.ancilla_timer[u] = 3;
        const j: usize = vars.link_direction_facing.* >> 1;
        vars.ancilla_dir[u] = @truncate(j);
        if (flag == 0) {
            Ancilla_SetXY(k, vars.link_x_coord.*, vars.link_y_coord.* +% 20);
        } else {
            Ancilla_SetXY(
                k,
                vars.link_x_coord.* +% @as(u16, @bitCast(@as(i16, tables.kAddDashingDust_X[j]))),
                vars.link_y_coord.* +% @as(u16, @bitCast(@as(i16, tables.kAddDashingDust_Y[j]))),
            );
        }
    }
}

pub export fn AddBirdCommon(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    vars.ancilla_y_vel[u] = 0;
    vars.ancilla_item_to_link[u] = 0;
    vars.ancilla_aux_timer[u] = 1;
    vars.ancilla_x_vel[u] = 56;
    vars.ancilla_arr3[u] = 3;
    vars.ancilla_K[u] = 0;
    vars.ancilla_G[u] = 0;

    const xt: u16 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x40 else 0;
    Ancilla_SetXY(k, vars.BG2HOFS_copy2.* -% 16 -% xt, vars.link_y_coord.* -% 8);
}

pub export fn Bomb_ProjectSpeedTowardsPlayer(k: c_int, x: u16, y: u16, vel: u8) callconv(.c) ProjectSpeedRet {
    _ = k;
    const old_x = sprite.Sprite_GetX(0);
    const old_y = sprite.Sprite_GetY(0);
    const old_z = vars.sprite_z[0];
    sprite.Sprite_SetX(0, x);
    sprite.Sprite_SetY(0, y);
    vars.sprite_z[0] = 0;
    const pt = sprite.Sprite_ProjectSpeedTowardsLink(0, vel);
    vars.sprite_z[0] = old_z;
    sprite.Sprite_SetX(0, old_x);
    sprite.Sprite_SetY(0, old_y);
    return pt;
}

pub export fn Boomerang_CheatWhenNoOnesLooking(k: c_int, pt: *ProjectSpeedRet) callconv(.c) void {
    const x = vars.link_x_coord.* -% Ancilla_GetX(k) +% 0xf0;
    const y = vars.link_y_coord.* -% Ancilla_GetY(k) +% 0xf0;
    if (x >= 0x1e0) {
        pt.x = if (sign16(x -% 0x1e0)) 0x90 else 0x70;
    } else if (y >= 0x1e0) {
        pt.y = if (sign16(y -% 0x1e0)) 0x90 else 0x70;
    }
}

pub export fn Medallion_CheckSpriteDamage(k: c_int) callconv(.c) void {
    vars.tmp_counter.* = vars.ancilla_type[@intCast(k)];
    var j: isize = 15;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        if (vars.sprite_state[u] >= 9 and
            (vars.sprite_ignore_projectile[u] | vars.sprite_pause[u]) == 0)
        {
            Ancilla_CheckDamageToSprite_aggressive(@intCast(j), vars.tmp_counter.*);
        }
    }
}

pub export fn Ancilla_CheckDamageToSprite(k: c_int, stype: u8) callconv(.c) void {
    if (!sign8(vars.sprite_hit_timer[@intCast(k)]))
        Ancilla_CheckDamageToSprite_aggressive(k, stype);
}

pub export fn Ancilla_CheckDamageToSprite_aggressive(k: c_int, stype: u8) callconv(.c) void {
    const u: usize = @intCast(k);
    var dmg = tables.kAncilla_Damage[stype];
    if (dmg == 6 and vars.link_item_bow.* >= 3) {
        if (vars.sprite_type[u] == 0xd7)
            vars.sprite_delay_aux4[u] = 32;
        dmg = 9;
    }
    sprite.Ancilla_CheckDamageToSprite_preset(k, dmg);
}

pub export fn CallForDuckIndoors() callconv(.c) void {
    _ = misc.Ancilla_Sfx2_Near(0x13);
    AncillaAdd_Duck_take_off(0x27, 4);
}

pub export fn Ancilla_Sfx1_Pan(k: c_int, v: u8) callconv(.c) void {
    vars.byte_7E0CF8.* = v;
    vars.sound_effect_ambient.* = v | Ancilla_CalculateSfxPan(k);
}

pub export fn Ancilla_Sfx2_Pan(k: c_int, v: u8) callconv(.c) void {
    vars.byte_7E0CF8.* = v;
    vars.sound_effect_1.* = v | Ancilla_CalculateSfxPan(k);
}

pub export fn Ancilla_Sfx3_Pan(k: c_int, v: u8) callconv(.c) void {
    vars.byte_7E0CF8.* = v;
    vars.sound_effect_2.* = v | Ancilla_CalculateSfxPan(k);
}

pub export fn AncillaAdd_FireRodShot(stype: u8, y_in: u8) callconv(.c) void {
    _ = y_in; // the C overwrites its own parameter with 1
    var j = Ancilla_AllocInit(stype, 1);
    if (j < 0) {
        if (stype != 1)
            player.Refund_Magic(0);
        return;
    }

    if (stype != 1)
        _ = misc.Ancilla_Sfx2_Near(0xe);

    var ju: usize = @intCast(j);
    vars.ancilla_type[ju] = stype;
    vars.ancilla_numspr[ju] = tables.kAncilla_Pflags[stype];
    vars.ancilla_timer[ju] = 3;
    vars.ancilla_step[ju] = 0;
    vars.ancilla_item_to_link[ju] = 0;
    vars.ancilla_objprio[ju] = 0;
    vars.ancilla_U[ju] = 0;
    var i: usize = vars.link_direction_facing.* >> 1;
    vars.ancilla_dir[ju] = @truncate(i);

    if (Ancilla_CheckInitialTile_A(j) < 0) {
        Ancilla_SetXY(
            j,
            vars.link_x_coord.* +% @as(u16, @bitCast(@as(i16, tables.kFireRod_X[i]))),
            vars.link_y_coord.* +% @as(u16, @bitCast(@as(i16, tables.kFireRod_Y[i]))),
        );
        if (stype != 1) {
            vars.ancilla_x_vel[ju] = @bitCast(tables.kFireRod_Xvel[i]);
            vars.ancilla_y_vel[ju] = @bitCast(tables.kFireRod_Yvel[i]);
        } else {
            i +%= @as(usize, @intCast(@as(c_int, vars.link_sword_type.*) - 2)) *% 4;
            vars.ancilla_x_vel[ju] = @bitCast(tables.kFireRod_Xvel2[i]);
            vars.ancilla_y_vel[ju] = @bitCast(tables.kFireRod_Yvel2[i]);
        }
        vars.ancilla_floor[ju] = vars.link_is_on_lower_level.*;
        vars.ancilla_floor2[ju] = vars.link_is_on_lower_level_mirror.*;
    } else {
        if (stype == 1) {
            vars.ancilla_type[ju] = 4;
            vars.ancilla_timer[ju] = 7;
            vars.ancilla_numspr[ju] = 16;
        } else {
            vars.ancilla_step[ju] = 1;
            vars.ancilla_timer[ju] = 31;
            vars.ancilla_numspr[ju] = 8;
            j = @intCast(vars.link_direction_facing.* >> 1); // wtf
            ju = @intCast(j);
            Ancilla_Sfx2_Pan(j, 0x2a);
        }
    }
}

pub export fn SomariaBlock_SpawnBullets(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    const z: u16 = if (vars.ancilla_z[ku] == 0xff) 0 else vars.ancilla_z[ku];
    const x = Ancilla_GetX(k);
    const y = Ancilla_GetY(k) -% z;

    var i: isize = 3;
    while (i >= 0) : (i -= 1) {
        const iu: usize = @intCast(i);
        const j = Ancilla_AllocInit(1, 4);
        if (j >= 0) {
            const ju: usize = @intCast(j);
            vars.ancilla_type[ju] = 0x1;
            vars.ancilla_numspr[ju] = tables.kAncilla_Pflags[0x1];
            vars.ancilla_step[ju] = 4;
            vars.ancilla_item_to_link[ju] = 0;
            vars.ancilla_objprio[ju] = 0;
            vars.ancilla_dir[ju] = @truncate(iu);
            Ancilla_SetXY(
                j,
                x +% @as(u16, @bitCast(@as(i16, tables.kSpawnCentrifugalQuad_X[iu]))),
                y +% @as(u16, @bitCast(@as(i16, tables.kSpawnCentrifugalQuad_Y[iu]))),
            );
            Ancilla_TerminateIfOffscreen(j);
            vars.ancilla_x_vel[ju] = @bitCast(tables.kFireRod_Xvel2[iu]);
            vars.ancilla_y_vel[ju] = @bitCast(tables.kFireRod_Yvel2[iu]);
            vars.ancilla_floor[ju] = vars.ancilla_floor[ku];
            vars.ancilla_floor2[ju] = vars.link_is_on_lower_level_mirror.*;
        }
    }
    vars.tmp_counter.* = 0xff;
}

pub export fn Ancilla_Main() callconv(.c) void {
    Ancilla_WeaponTink();
    Ancilla_ExecuteAll();
}

pub export fn Ancilla_ProjectReflexiveSpeedOntoSprite(k: c_int, x: u16, y: u16, vel: u8) callconv(.c) ProjectSpeedRet {
    const old_x = vars.link_x_coord.*;
    const old_y = vars.link_y_coord.*;
    vars.link_x_coord.* = x;
    vars.link_y_coord.* = y;
    const pt = sprite.Sprite_ProjectSpeedTowardsLink(k, vel);
    vars.link_x_coord.* = old_x;
    vars.link_y_coord.* = old_y;
    return pt;
}

pub export fn Bomb_CheckSpriteDamage(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    var j: isize = 15;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        if (((@as(u8, @truncate(@as(usize, @bitCast(j)))) ^ vars.frame_counter.*) & 3) |
            vars.sprite_hit_timer[u] | vars.sprite_ignore_projectile[u] != 0)
            continue;
        if (vars.sprite_floor[u] != vars.ancilla_floor[ku] or vars.sprite_state[u] < 9)
            continue;
        var hb: SpriteHitBox = undefined;
        const ax: i32 = @as(i32, Ancilla_GetX(k)) - 24;
        const ay: i32 = @as(i32, Ancilla_GetY(k)) - 24 - @as(i32, vars.ancilla_z[ku]);
        hb.r0_xlo = @truncate(@as(u32, @bitCast(ax)));
        hb.r8_xhi = @truncate(@as(u32, @bitCast(ax)) >> 8);
        hb.r1_ylo = @truncate(@as(u32, @bitCast(ay)));
        hb.r9_yhi = @truncate(@as(u32, @bitCast(ay)) >> 8);
        hb.r2 = 48;
        hb.r3 = 48;
        sprite.Sprite_SetupHitBox(@intCast(j), &hb);
        if (!sprite.CheckIfHitBoxesOverlap(&hb))
            continue;
        if (vars.sprite_type[u] == 0x92 and vars.sprite_C[u] >= 3)
            continue;
        Ancilla_CheckDamageToSprite(@intCast(j), vars.ancilla_type[ku]);
        const pt = Ancilla_ProjectReflexiveSpeedOntoSprite(@intCast(j), Ancilla_GetX(k), Ancilla_GetY(k), 64);
        vars.sprite_x_recoil[u] = 0 -% pt.x;
        vars.sprite_y_recoil[u] = 0 -% pt.y;
    }
}

pub export fn Ancilla_ExecuteAll() callconv(.c) void {
    var i: isize = 9;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        vars.cur_object_index.* = @truncate(u);
        if (vars.ancilla_type[u] != 0)
            Ancilla_ExecuteOne(vars.ancilla_type[u], @intCast(i));
    }
}

pub export fn Ancilla_ExecuteOne(atype: u8, k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (k < 6) {
        vars.ancilla_oam_idx[u] = @truncate(@as(u32, @bitCast(
            Ancilla_AllocateOamFromRegion_A_or_D_or_F(k, vars.ancilla_numspr[u]),
        )));
    }

    if (vars.submodule_index.* == 0 and vars.ancilla_timer[u] != 0)
        vars.ancilla_timer[u] -%= 1;

    kAncilla_Funcs[atype - 1](k);
}

pub export fn Ancilla13_IceRodSparkle(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    if (vars.ancilla_timer[ku] == 0)
        vars.ancilla_type[ku] = 0;
    if (vars.submodule_index.* == 0) {
        Ancilla_MoveX(k);
        Ancilla_MoveY(k);
    }
    var info: AncillaOamInfo = undefined;
    if (Ancilla_ReturnIfOutsideBounds(k, &info))
        return;

    var j: isize = 4;
    while (j >= 0 and vars.ancilla_type[@intCast(j)] != 0xb) : (j -= 1) {}
    if (j >= 0 and vars.ancilla_objprio[@intCast(j)] != 0)
        info.flags = 0x30;

    if (vars.sort_sprites_setting.* != 0) {
        if (vars.ancilla_floor[ku] != 0) {
            _ = sprite.Oam_AllocateFromRegionE(0x10);
        } else {
            _ = sprite.Oam_AllocateFromRegionD(0x10);
        }
    } else {
        _ = sprite.Oam_AllocateFromRegionA(0x10);
    }

    var oam = GetOamCurPtr();
    const base: usize = vars.ancilla_timer[ku] & 0x1c;
    var i: isize = 3;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const t: usize = @as(usize, @intCast(i)) + base;
        SetOamPlain(
            oam,
            @truncate(info.x +% tables.kIceShotSparkle_X[t]),
            @truncate(info.y +% tables.kIceShotSparkle_Y[t]),
            tables.kIceShotSparkle_Char[t],
            info.flags | 4,
            0,
        );
    }
}

pub export fn AncillaAdd_IceRodSparkle(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    vars.ancilla_arr4[ku] -%= 1;
    if (vars.submodule_index.* != 0 or !sign8(vars.ancilla_arr4[ku]))
        return;

    vars.ancilla_arr4[ku] = 5;
    const j = Ancilla_AllocHigh();
    if (j >= 0) {
        const ju: usize = @intCast(j);
        vars.ancilla_type[ju] = 0x13;
        vars.ancilla_timer[ju] = 15;

        const i: usize = vars.ancilla_dir[ku];
        vars.ancilla_x_vel[ju] = @bitCast(tables.kIceShotSparkle_Xvel[i]);
        vars.ancilla_y_vel[ju] = @bitCast(tables.kIceShotSparkle_Yvel[i]);

        vars.ancilla_x_lo[ju] = vars.ancilla_x_lo[ku];
        vars.ancilla_y_lo[ju] = vars.ancilla_y_lo[ku];
        vars.ancilla_floor[ju] = vars.ancilla_floor[ku];
        vars.ancilla_numspr[ju] = 0;
    }
}

pub export fn Ancilla01_SomariaBullet(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        if (vars.frame_counter.* & tables.kSomarianBlast_Mask[vars.ancilla_step[ku]] == 0) {
            Ancilla_MoveX(k);
            Ancilla_MoveY(k);
        }
        if (vars.ancilla_timer[ku] == 0) {
            vars.ancilla_timer[ku] = 3;
            var a = vars.ancilla_step[ku] +% 1;
            if (a >= 6)
                a = 4;
            vars.ancilla_step[ku] = a;
        }
        if (Ancilla_CheckSpriteCollision(k) >= 0 or Ancilla_CheckTileCollision_staggered(k) != 0) {
            vars.ancilla_type[ku] = 4;
            vars.ancilla_timer[ku] = 7;
            vars.ancilla_numspr[ku] = 16;
        }
    }
    SomarianBlast_Draw(k);
}

pub export fn Ancilla_ReturnIfOutsideBounds(k: c_int, info: *AncillaOamInfo) callconv(.c) bool {
    const ku: usize = @intCast(k);
    info.flags = tables.kAncilla_FloorFlags[vars.ancilla_floor[ku]];
    info.x = vars.ancilla_x_lo[ku] -% @as(u8, @truncate(vars.BG2HOFS_copy2.*));
    info.y = vars.ancilla_y_lo[ku] -% @as(u8, @truncate(vars.BG2VOFS_copy2.*));
    if (info.x >= 0xf4 or info.y >= 0xf0) {
        vars.ancilla_type[ku] = 0;
        return true;
    }
    return false;
}

pub export fn SomarianBlast_Draw(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    var info: AncillaOamInfo = undefined;
    if (Ancilla_ReturnIfOutsideBounds(k, &info))
        return;
    info.flags |= tables.kSomarianBlast_Flags[vars.ancilla_item_to_link[ku]];
    if (vars.ancilla_objprio[ku] != 0)
        info.flags |= 0x30;

    const oam = GetOamCurPtr();
    const j: usize = @as(usize, vars.ancilla_dir[ku]) *% 6 +% vars.ancilla_step[ku];
    SetOamPlain(
        oam,
        info.x +% @as(u8, @bitCast(tables.kSomarianBlast_Draw_X0[j])),
        if (sign8(tables.kSomarianBlast_Draw_Y0[j])) 0xf0 else info.y +% tables.kSomarianBlast_Draw_Y0[j],
        0x82 +% tables.kSomarianBlast_Draw_Char0[j],
        info.flags | tables.kSomarianBlast_Draw_Flags0[j],
        0,
    );
    SetOamPlain(
        oam + 1,
        info.x +% @as(u8, @bitCast(tables.kSomarianBlast_Draw_X1[j])),
        if (sign8(tables.kSomarianBlast_Draw_Y1[j])) 0xf0 else info.y +% tables.kSomarianBlast_Draw_Y1[j],
        0x82 +% tables.kSomarianBlast_Draw_Char1[j],
        info.flags | tables.kSomarianBlast_Draw_Flags1[j],
        0,
    );
}

pub export fn Ancilla02_FireRodShot(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    if (vars.ancilla_step[ku] == 0) {
        if (vars.submodule_index.* == 0) {
            vars.ancilla_L[ku] = 0;
            Ancilla_MoveX(k);
            Ancilla_MoveY(k);
            var coll: u8 = @intFromBool(Ancilla_CheckSpriteCollision(k) >= 0);
            if (coll == 0) {
                vars.ancilla_dir[ku] |= 8;
                coll = Ancilla_CheckTileCollision(k);
                vars.ancilla_L[ku] = vars.ancilla_tile_attr[ku];
                if (coll == 0) {
                    vars.ancilla_dir[ku] |= 12;
                    const bak = vars.ancilla_U[ku];
                    coll = Ancilla_CheckTileCollision(k);
                    vars.ancilla_U[ku] = bak;
                }
            }
            if (coll != 0) {
                vars.ancilla_step[ku] +%= 1;
                vars.ancilla_timer[ku] = 31;
                vars.ancilla_numspr[ku] = 8;
                Ancilla_Sfx2_Pan(k, 0x2a);
            }
            vars.ancilla_item_to_link[ku] +%= 1;
            vars.ancilla_dir[ku] &= ~@as(u8, 0xC);
            vars.byte_7E0333.* = vars.ancilla_L[ku];
            const first = (vars.byte_7E0333.* & 0xf0) == 0xc0;
            if (!first) vars.byte_7E0333.* = vars.ancilla_tile_attr[ku];
            if (first or (vars.byte_7E0333.* & 0xf0) == 0xc0)
                misc.Dungeon_LightTorch();
        }
        FireShot_Draw(k);
    } else {
        var info: AncillaOamInfo = undefined;
        _ = Ancilla_CheckBasicSpriteCollision(k);
        if (Ancilla_ReturnIfOutsideBounds(k, &info))
            return;
        const oam = GetOamCurPtr();
        if (vars.ancilla_timer[ku] == 0) {
            const old_type = vars.ancilla_type[ku];
            vars.ancilla_type[ku] = 0;
            if (old_type != 0x2f and @as(u8, @truncate(vars.overworld_screen_index.*)) == 64 and
                vars.ancilla_tile_attr[ku] == 0x43)
                FireRodShot_BecomeSkullWoodsFire(k);
            return;
        }
        const j: usize = vars.ancilla_timer[ku] >> 3;
        if (j != 0) {
            SetOamPlain(oam, info.x, info.y, tables.kFireShot_Draw_Char[j - 1], info.flags | 2, 2);
        } else {
            SetOamPlain(oam + 0, info.x +% 0, info.y -% 3, 0xa4, info.flags | 2, 0);
            SetOamPlain(oam + 1, info.x +% 8, info.y -% 3, 0xa5, info.flags | 2, 0);
        }
    }
}

pub export fn FireShot_Draw(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    var info: AncillaOamInfo = undefined;
    if (Ancilla_ReturnIfOutsideBounds(k, &info))
        return;
    if (vars.ancilla_objprio[ku] != 0)
        info.flags |= 0x30;

    var oam = GetOamCurPtr();
    const j: usize = vars.ancilla_item_to_link[ku] & 0xc;
    var i: isize = 2;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const iu: usize = @intCast(i);
        SetOamPlain(
            oam,
            info.x +% tables.kFireShot_Draw_X2[j + iu],
            info.y +% tables.kFireShot_Draw_Y2[j + iu],
            tables.kFireShot_Draw_Char2[iu],
            info.flags | 2,
            0,
        );
    }
}

pub export fn Ancilla_CheckTileCollision_staggered(k: c_int) callconv(.c) u8 {
    if ((vars.frame_counter.* ^ @as(u8, @truncate(@as(u32, @bitCast(k))))) & 1 != 0)
        return Ancilla_CheckTileCollision(k);
    return 0;
}

pub export fn Ancilla_CheckTileCollision(k: c_int) callconv(.c) u8 {
    const ku: usize = @intCast(k);
    if (vars.player_is_indoors.* == 0 and vars.ancilla_objprio[ku] != 0) {
        vars.ancilla_tile_attr[ku] = 0;
        return 0;
    }
    if (vars.dung_hdr_collision.* == 0)
        return @intFromBool(Ancilla_CheckTileCollisionOneFloor(k));
    var x: u16 = 0;
    var y: u16 = 0;
    if (vars.dung_hdr_collision.* < 3) {
        x = vars.BG1HOFS_copy2.* -% vars.BG2HOFS_copy2.*;
        y = vars.BG1VOFS_copy2.* -% vars.BG2VOFS_copy2.*;
    }
    const oldx = Ancilla_GetX(k);
    const oldy = Ancilla_GetY(k);
    Ancilla_SetX(k, oldx +% x);
    Ancilla_SetY(k, oldy +% y);
    vars.ancilla_floor[ku] = 1;
    const b = @intFromBool(Ancilla_CheckTileCollisionOneFloor(k));
    vars.ancilla_floor[ku] = 0;
    Ancilla_SetX(k, oldx);
    Ancilla_SetY(k, oldy);
    return (@as(u8, b) << 1) | @intFromBool(Ancilla_CheckTileCollisionOneFloor(k));
}

pub export fn Ancilla_CheckTileCollisionOneFloor(k: c_int) callconv(.c) bool {
    const ku: usize = @intCast(k);
    const d: usize = vars.ancilla_dir[ku];
    const x = Ancilla_GetX(k) +% @as(u16, @bitCast(@as(i16, tables.kAncilla_CheckTileColl0_X[d])));
    const y = Ancilla_GetY(k) +% @as(u16, @bitCast(@as(i16, tables.kAncilla_CheckTileColl0_Y[d])));
    return Ancilla_CheckTileCollision_targeted(k, x, y);
}

/// How far past the 4:3 screen's sides an ancilla still checks the tiles it
/// touches. The game skips a point off the screen, and leaves its tile
/// attribute as it was: the lamp then reads the last one and lights whatever
/// torch that was. The 4:3 camera keeps Link on the screen; the widescreen
/// one stops short of a room's walls and can leave him in the margin, his
/// flame on a torch past the screen's edge. Widened as far as the screen
/// is, or the 64 pixels ExtendScreen64 widens the rest by.
fn tileCheckExtraX() u16 {
    var xt: u16 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x40 else 0;
    if (features.enhanced_features0.* & features.kFeatures0_WidescreenVisualFixes != 0)
        xt = @max(xt, @as(u16, config.g_config.extended_aspect_ratio));
    return xt;
}

pub export fn Ancilla_CheckTileCollision_targeted(k: c_int, x_in: u16, y: u16) callconv(.c) bool {
    const ku: usize = @intCast(k);
    var x = x_in;
    const xt = tileCheckExtraX();
    if ((y -% vars.BG2VOFS_copy2.*) >= 224 or (x -% vars.BG2HOFS_copy2.* +% xt) >= 256 + 2 * xt)
        return false;
    var tile_attr: u8 = undefined;
    if (vars.player_is_indoors.* == 0) {
        x >>= 3;
        tile_attr = tile_detect.Overworld_GetTileAttributeAtLocation(x, y);
    } else {
        tile_attr = sprite.GetTileAttribute(vars.ancilla_floor[ku], &x, y);
    }

    vars.ancilla_tile_attr[ku] = tile_attr;
    if (tile_attr == 3 and vars.ancilla_floor2[ku] != 0)
        return false;

    var t: u8 = tables.kAncilla_TileColl0_Attrs[tile_attr];

    if (vars.ancilla_type[ku] == 2 and (tile_attr & 0xf0) == 0xc0)
        t = 0;

    // `goto return_true_set_alert` from two places.
    var set_alert = false;
    if (vars.ancilla_objprio[ku] == 0) {
        if (t == 0)
            return false;
        if (t == 1) {
            set_alert = true;
        } else if (t == 2) {
            return sprite.Entity_CheckSlopedTileCollision(x, y);
        } else if (t == 3) {
            if (vars.ancilla_floor2[ku] != 0) {
                set_alert = true;
            } else {
                return false;
            }
        }
    }
    if (!set_alert) {
        vars.ancilla_U[ku] -%= 1;
        if (sign8(vars.ancilla_U[ku])) {
            vars.ancilla_U[ku] = 0;
            if (t == 4) {
                vars.ancilla_U[ku] = 6;
                vars.ancilla_objprio[ku] ^= 1;
            }
        }
        return false;
    }
    // return_true_set_alert:
    vars.sprite_alert_flag.* = 3;
    return true;
}

pub export fn Ancilla_CheckTileCollision_Class2(k: c_int) callconv(.c) bool {
    const ku: usize = @intCast(k);
    if (vars.dung_hdr_collision.* == 0)
        return Ancilla_CheckTileCollision_Class2_Inner(k);
    var x: u16 = 0;
    var y: u16 = 0;
    if (vars.dung_hdr_collision.* < 3) {
        x = vars.BG1HOFS_copy2.* -% vars.BG2HOFS_copy2.*;
        y = vars.BG1VOFS_copy2.* -% vars.BG2VOFS_copy2.*;
    }
    const oldx = Ancilla_GetX(k);
    const oldy = Ancilla_GetY(k);
    Ancilla_SetX(k, oldx +% x);
    Ancilla_SetY(k, oldy +% y);
    vars.ancilla_floor[ku] = 1;
    const b = Ancilla_CheckTileCollision_Class2_Inner(k);
    vars.ancilla_floor[ku] = 0;
    Ancilla_SetX(k, oldx);
    Ancilla_SetY(k, oldy);
    return (@intFromBool(b) | @intFromBool(Ancilla_CheckTileCollision_Class2_Inner(k))) != 0;
}

pub export fn Ancilla_CheckTileCollision_Class2_Inner(k: c_int) callconv(.c) bool {
    const ku: usize = @intCast(k);
    const d: usize = vars.ancilla_dir[ku];
    var x = Ancilla_GetX(k) +% @as(u16, @bitCast(@as(i16, tables.kAncilla_CheckTileColl_X[d])));
    const y = Ancilla_GetY(k) +% @as(u16, @bitCast(@as(i16, tables.kAncilla_CheckTileColl_Y[d])));

    if ((y -% vars.BG2VOFS_copy2.*) >= 224 or (x -% vars.BG2HOFS_copy2.*) >= 256)
        return false;
    var tile_attr: u8 = undefined;
    if (vars.player_is_indoors.* == 0) {
        x >>= 3;
        tile_attr = tile_detect.Overworld_GetTileAttributeAtLocation(x, y);
    } else {
        tile_attr = sprite.GetTileAttribute(vars.ancilla_floor[ku], &x, y);
    }

    vars.ancilla_tile_attr[ku] = tile_attr;
    if (tile_attr == 3 and vars.ancilla_floor2[ku] != 0)
        return false;

    // This table is int8 in the C while its sibling is uint8; values are 0..4.
    const t: u8 = @bitCast(tables.kAncilla_TileColl_Attrs[tile_attr]);
    if (t == 0)
        return false;
    if (t == 2)
        return sprite.Entity_CheckSlopedTileCollision(x, y);
    if (t == 4) {
        if (vars.ancilla_floor2[ku] != 0)
            return true;
        vars.ancilla_objprio[ku] = 1;
        return false;
    }
    if (t == 3)
        return vars.ancilla_floor2[ku] != 0;
    return true;
}

pub export fn Ancilla04_BeamHit(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    var info: AncillaOamInfo = undefined;
    if (Ancilla_ReturnIfOutsideBounds(k, &info))
        return;
    if (vars.ancilla_timer[ku] == 0) {
        vars.ancilla_type[ku] = 0;
        return;
    }
    var oam = GetOamCurPtr();
    const j: usize = vars.ancilla_timer[ku] >> 1;
    const ancilla_x = Ancilla_GetX(k);
    const ancilla_y = Ancilla_GetY(k);
    const r7: u8 = @truncate(ancilla_x -% vars.BG2HOFS_copy2.*);
    const r6: u8 = @truncate(ancilla_y -% vars.BG2VOFS_copy2.*);
    var i: isize = 3;
    while (i >= 0) : ({
        i -= 1;
        oam += 1;
    }) {
        const m: usize = j * 4 + @as(usize, @intCast(i));
        const x: u8 = info.x +% @as(u8, @bitCast(tables.kBeamHit_X[m]));
        const y: u8 = info.y +% @as(u8, @bitCast(tables.kBeamHit_Y[m]));
        const x_adj: u16 = ancilla_x +%
            @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(x -% r7))))) -% vars.BG2HOFS_copy2.*;
        const y_adj: u16 = ancilla_y +%
            @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(y -% r6))))) -% vars.BG2VOFS_copy2.* +% 0x10;
        SetOamPlain(
            oam,
            x,
            if (y_adj >= 0x100) 0xf0 else y,
            tables.kBeamHit_Char[m] +% 0x82,
            tables.kBeamHit_Flags[m] | 2 | info.flags,
            if (x_adj >= 0x100) 1 else 0,
        );
    }
}

pub export fn Ancilla_CheckSpriteCollision(k: c_int) callconv(.c) c_int {
    const ku: usize = @intCast(k);
    var j: isize = 15;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        const atype = vars.ancilla_type[ku];
        if (atype == 9 or atype == 0x1f or
            ((@as(u8, @truncate(@as(u32, @bitCast(@as(c_int, @intCast(j)))))) ^ vars.frame_counter.*) & 3 |
                vars.sprite_pause[u]) == 0)
        {
            if ((vars.sprite_state[u] >= 9 and
                (vars.sprite_defl_bits[u] & 2 != 0 or vars.ancilla_objprio[ku] == 0)) and
                vars.ancilla_floor[ku] == vars.sprite_floor[u])
            {
                if (Ancilla_CheckSpriteCollision_Single(k, @intCast(j)))
                    return @intCast(j);
            }
        }
    }
    return -1;
}

pub export fn Ancilla_CheckSpriteCollision_Single(k: c_int, j: c_int) callconv(.c) bool {
    const ku: usize = @intCast(k);
    const ju: usize = @intCast(j);
    var hb: SpriteHitBox = undefined;
    Ancilla_SetupHitBox(k, &hb);

    sprite.Sprite_SetupHitBox(j, &hb);
    if (!sprite.CheckIfHitBoxesOverlap(&hb))
        return false;

    var return_value = true;
    // Deflection may clear the ancilla: subsequent checks must reread its type.

    // Several `goto return_true_set_alert` sites share the tail below.
    alert: {
        if (vars.sprite_flags[ju] & 8 != 0 and vars.ancilla_type[ku] == 9) {
            if (vars.sprite_type[ju] != 0x1b) {
                Sprite_CreateDeflectedArrow(k);
                return false;
            }
            if (vars.link_item_bow.* < 3) {
                Sprite_CreateDeflectedArrow(k);
            } else {
                return_value = false;
            }
        }

        if (vars.sprite_defl_bits[ju] & 0x10 != 0) {
            vars.ancilla_dir[ku] &= 3;
            if (vars.ancilla_dir[ku] == tables.kAncilla_CheckSpriteColl_Dir[vars.ancilla_dir[ku]])
                break :alert;
        }

        if (vars.ancilla_type[ku] == 5 or vars.ancilla_type[ku] == 0x1f) {
            // `goto skip` enters the sprite_defl_bits arm directly.
            var do_skip = (vars.ancilla_type[ku] == 0x1f and vars.sprite_type[ju] == 0x8d);
            if (!do_skip) {
                if (vars.sprite_hit_timer[ju] != 0)
                    break :alert;
                if (vars.sprite_defl_bits[ju] & 2 != 0)
                    do_skip = true;
            }
            if (do_skip) {
                vars.sprite_B[ju] = @truncate(@as(u32, @bitCast(k +% 1)));
                vars.sprite_unk2[ju] = vars.ancilla_type[ku];
                break :alert;
            }
        }

        if (vars.sprite_ignore_projectile[ju] == 0) {
            if (vars.sprite_type[ju] == 0x92 and vars.sprite_C[ju] < 3)
                break :alert;
            const i: usize = vars.ancilla_dir[ku] & 3;
            vars.sprite_x_recoil[ju] = @bitCast(tables.kAncilla_CheckSpriteColl_RecoilX[i]);
            vars.sprite_y_recoil[ju] = @bitCast(tables.kAncilla_CheckSpriteColl_RecoilY[i]);
            vars.byte_7E0FB6.* = @truncate(@as(u32, @bitCast(k)));
            Ancilla_CheckDamageToSprite(j, vars.ancilla_type[ku]);
            break :alert;
        }
        return false;
    }
    // return_true_set_alert:
    vars.sprite_unk2[ju] = vars.ancilla_type[ku];
    vars.sprite_alert_flag.* = 3;
    return return_value;
}

pub export fn Ancilla_SetupHitBox(k: c_int, hb: *SpriteHitBox) callconv(.c) void {
    const ku: usize = @intCast(k);
    var j: usize = vars.ancilla_dir[ku];
    if (vars.ancilla_type[ku] == 0xc)
        j |= 8;
    const x: i32 = @as(i32, Ancilla_GetX(k)) + tables.kAncilla_HitBox_X[j];
    hb.r0_xlo = @truncate(@as(u32, @bitCast(x)));
    hb.r8_xhi = @truncate(@as(u32, @bitCast(x)) >> 8);
    const y: i32 = @as(i32, Ancilla_GetY(k)) + tables.kAncilla_HitBox_Y[j];
    hb.r1_ylo = @truncate(@as(u32, @bitCast(y)));
    hb.r9_yhi = @truncate(@as(u32, @bitCast(y)) >> 8);
    hb.r2 = tables.kAncilla_HitBox_W[j];
    hb.r3 = tables.kAncilla_HitBox_H[j];
}

pub export fn Ancilla_ProjectSpeedTowardsPlayer(k: c_int, vel_in: u8) callconv(.c) ProjectSpeedRet {
    if (vel_in == 0)
        return .{ .x = 0, .y = 0, .xdiff = 0, .ydiff = 0 };

    const below = Ancilla_IsBelowLink(k);
    var r12: u8 = if (sign8(below.b)) 0 -% below.b else below.b;

    const right = Ancilla_IsRightOfLink(k);
    var r13: u8 = if (sign8(right.b)) 0 -% right.b else right.b;

    var t: u8 = undefined;
    var swapped = false;
    if (r13 < r12) {
        swapped = true;
        t = r12;
        r12 = r13;
        r13 = t;
    }
    var xvel: u8 = vel_in;
    var yvel: u8 = 0;
    var vel = vel_in;
    t = 0;
    while (true) {
        t +%= r12;
        if (t >= r13) {
            t -%= r13;
            yvel +%= 1;
        }
        vel -%= 1;
        if (vel == 0) break;
    }
    if (swapped) {
        t = xvel;
        xvel = yvel;
        yvel = t;
    }
    return .{
        .x = if (right.a != 0) 0 -% xvel else xvel,
        .y = if (below.a != 0) 0 -% yvel else yvel,
        .xdiff = right.b,
        .ydiff = below.b,
    };
}

pub export fn Ancilla_IsRightOfLink(k: c_int) callconv(.c) PairU8 {
    const x = vars.link_x_coord.* -% Ancilla_GetX(k);
    return .{ .a = if (sign16(x)) 1 else 0, .b = @truncate(x) };
}

pub export fn Ancilla_IsBelowLink(k: c_int) callconv(.c) PairU8 {
    const y = vars.link_y_coord.* -% Ancilla_GetY(k);
    return .{ .a = if (sign16(y)) 1 else 0, .b = @truncate(y) };
}

pub export fn Ancilla_WeaponTink() callconv(.c) void {
    if (vars.repulsespark_timer.* == 0)
        return;
    vars.sprite_alert_flag.* = 2;
    vars.repulsespark_anim_delay.* -%= 1;
    if (sign8(vars.repulsespark_anim_delay.*)) {
        vars.repulsespark_timer.* -%= 1;
        vars.repulsespark_anim_delay.* = 1;
    }

    if (vars.sort_sprites_setting.* != 0) {
        if (vars.repulsespark_floor_status.* != 0) {
            _ = sprite.Oam_AllocateFromRegionF(0x10);
        } else {
            _ = sprite.Oam_AllocateFromRegionD(0x10);
        }
    } else {
        _ = sprite.Oam_AllocateFromRegionA(0x10);
    }

    const x: u8 = vars.repulsespark_x_lo.* -% @as(u8, @truncate(vars.BG2HOFS_copy2.*));
    const y: u8 = vars.repulsespark_y_lo.* -% @as(u8, @truncate(vars.BG2VOFS_copy2.*));

    if (x >= 0xf8 or y >= 0xf0) {
        vars.repulsespark_timer.* = 0;
        return;
    }

    const oam = GetOamCurPtr();
    const flags = tables.kRepulseSpark_Flags[vars.repulsespark_floor_status.*];
    if (vars.repulsespark_timer.* >= 3) {
        SetOamPlain(oam, x, y, if (vars.repulsespark_timer.* < 9) 0x92 else 0x80, flags, 0);
        return;
    }
    const c = tables.kRepulseSpark_Char[vars.repulsespark_timer.*];
    SetOamPlain(oam + 0, x -% 4, y -% 4, c, flags | 0x00, 0);
    SetOamPlain(oam + 1, x +% 4, y -% 4, c, flags | 0x40, 0);
    SetOamPlain(oam + 2, x -% 4, y +% 4, c, flags | 0x80, 0);
    SetOamPlain(oam + 3, x +% 4, y +% 4, c, flags | 0xc0, 0);
}

pub export fn Ancilla_MoveX(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    const t: u32 = @bitCast(@as(i32, vars.ancilla_x_subpixel[u]) +
        (@as(i32, vars.ancilla_x_lo[u]) << 8) +
        (@as(i32, vars.ancilla_x_hi[u]) << 16) +
        (@as(i32, @as(i8, @bitCast(vars.ancilla_x_vel[u]))) << 4));
    vars.ancilla_x_subpixel[u] = @truncate(t);
    vars.ancilla_x_lo[u] = @truncate(t >> 8);
    vars.ancilla_x_hi[u] = @truncate(t >> 16);
}

pub export fn Ancilla_MoveY(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    const t: u32 = @bitCast(@as(i32, vars.ancilla_y_subpixel[u]) +
        (@as(i32, vars.ancilla_y_lo[u]) << 8) +
        (@as(i32, vars.ancilla_y_hi[u]) << 16) +
        (@as(i32, @as(i8, @bitCast(vars.ancilla_y_vel[u]))) << 4));
    vars.ancilla_y_subpixel[u] = @truncate(t);
    vars.ancilla_y_lo[u] = @truncate(t >> 8);
    vars.ancilla_y_hi[u] = @truncate(t >> 16);
}

pub export fn Ancilla_MoveZ(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    const t: u32 = @bitCast(@as(i32, vars.ancilla_z_subpixel[u]) +
        (@as(i32, vars.ancilla_z[u]) << 8) +
        (@as(i32, @as(i8, @bitCast(vars.ancilla_z_vel[u]))) << 4));
    vars.ancilla_z_subpixel[u] = @truncate(t);
    vars.ancilla_z[u] = @truncate(t >> 8);
}

pub export fn Ancilla05_Boomerang(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    var hit_spr: c_int = undefined;

    // Every `goto exit_and_draw` lands on the single trailing draw call.
    draw: {
        var j: isize = 4;
        while (j >= 0) : (j -= 1) {
            if (vars.ancilla_type[@intCast(j)] == 0x22)
                break :draw;
        }
        if (vars.submodule_index.* != 0)
            break :draw;

        if (vars.frame_counter.* & 7 == 0)
            Ancilla_Sfx2_Pan(k, 0x9);

        if (vars.ancilla_aux_timer[ku] == 0) {
            if (vars.button_b_frames.* < 9 and vars.player_handler_timer.* == 0) {
                if (vars.link_is_bunny_mirror.* != 0 or vars.link_auxiliary_state.* != 0 or
                    (vars.link_item_in_hand.* == 0 and
                        (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes) != 0))
                {
                    Boomerang_Terminate(k);
                    return;
                }
                break :draw;
            }
            const i: usize = vars.ancilla_arr23[ku] >> 1;
            Ancilla_SetXY(
                k,
                vars.link_x_coord.* +% @as(u16, @bitCast(@as(i16, tables.kBoomerang_X0[i]))),
                vars.link_y_coord.* +% 8 +% @as(u16, @bitCast(@as(i16, tables.kBoomerang_Y0[i]))),
            );
            vars.ancilla_aux_timer[ku] +%= 1;
        }
        // endif_2
        if (vars.ancilla_G[ku] != 0 and vars.frame_counter.* & 1 == 0)
            AncillaAdd_SwordChargeSparkle(k);

        if (vars.ancilla_item_to_link[ku] != 0) {
            if (vars.ancilla_K[ku] != 0)
                vars.ancilla_K[ku] +%= 1;
            const aptr: *align(1) u16 = @ptrCast(&vars.ancilla_A[ku]);
            aptr.* = vars.link_y_coord.*;
            vars.link_y_coord.* +%= 8;
            var pt = Ancilla_ProjectSpeedTowardsPlayer(k, vars.ancilla_H[ku]);
            Boomerang_CheatWhenNoOnesLooking(k, &pt);
            vars.ancilla_x_vel[ku] = pt.x;
            vars.ancilla_y_vel[ku] = pt.y;
            vars.link_y_coord.* = aptr.*;
        }

        if (vars.ancilla_y_vel[ku] != 0)
            vars.ancilla_y_vel[ku] +%= vars.ancilla_K[ku];
        Ancilla_MoveY(k);

        if (vars.ancilla_x_vel[ku] != 0)
            vars.ancilla_x_vel[ku] +%= vars.ancilla_K[ku];
        Ancilla_MoveX(k);
        hit_spr = Ancilla_CheckSpriteCollision(k);

        if (vars.ancilla_item_to_link[ku] == 0) {
            if (hit_spr >= 0) {
                vars.ancilla_item_to_link[ku] ^= 1;
            } else if (Ancilla_CheckTileCollision(k) != 0) {
                AncillaAdd_BoomerangWallClink(k);
                Ancilla_Sfx2_Pan(k, if (vars.ancilla_tile_attr[ku] == 0xf0) 6 else 5);
                vars.ancilla_item_to_link[ku] ^= 1;
            } else {
                vars.ancilla_step[ku] -%= 1;
                if (Boomerang_ScreenEdge(k) or vars.ancilla_step[ku] == 0) {
                    vars.ancilla_item_to_link[ku] ^= 1;
                } else {
                    if (vars.ancilla_step[ku] < 5)
                        vars.ancilla_K[ku] -%= 1;
                }
            }
        } else {
            const bak0 = vars.ancilla_objprio[ku];
            const bak1 = vars.ancilla_floor[ku];
            vars.ancilla_floor[ku] = 0;
            _ = Ancilla_CheckTileCollision(k);
            vars.ancilla_floor[ku] = bak1;
            vars.ancilla_objprio[ku] = bak0;
            Boomerang_StopOffScreen(k);
        }
    }
    // exit_and_draw:
    Boomerang_Draw(k);
}

pub export fn Boomerang_ScreenEdge(k: c_int) callconv(.c) bool {
    const x = Ancilla_GetX(k);
    const y = Ancilla_GetY(k);
    if (vars.hookshot_effect_index.* & 3 != 0) {
        const t = x +% @as(u16, if (vars.hookshot_effect_index.* & 1 != 0) 16 else 0) -%
            vars.BG2HOFS_copy2.*;
        if (t >= 0x100)
            return true;
    }
    if (vars.hookshot_effect_index.* & 12 != 0) {
        const t = y +% @as(u16, if (vars.hookshot_effect_index.* & 4 != 0) 16 else 0) -%
            vars.BG2VOFS_copy2.*;
        if (t >= 0xe2)
            return true;
    }
    return false;
}

pub export fn Boomerang_StopOffScreen(k: c_int) callconv(.c) void {
    const x = Ancilla_GetX(k) +% 8;
    const y = Ancilla_GetY(k) +% 8;
    if (x >= vars.link_x_coord.* and x < vars.link_x_coord.* +% 16 and
        y >= vars.link_y_coord.* and y < vars.link_y_coord.* +% 24)
        Boomerang_Terminate(k);
}

pub export fn Boomerang_Terminate(k: c_int) callconv(.c) void {
    vars.ancilla_type[@intCast(k)] = 0;
    vars.flag_for_boomerang_in_place.* = 0;
    if (vars.link_item_in_hand.* & 0x80 != 0) {
        vars.link_item_in_hand.* = 0;
        vars.button_mask_b_y.* &= ~@as(u8, 0x40);
        if (vars.button_mask_b_y.* & 0x80 == 0)
            vars.link_cant_change_direction.* &= ~@as(u8, 1);
    }
}

pub export fn Boomerang_Draw(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    var info: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &info);

    if (vars.ancilla_item_to_link[ku] != 0) {
        vars.ancilla_floor[ku] = vars.link_is_on_lower_level.*;
        vars.oam_priority_value.* =
            @as(u16, tables.kTagalongLayerBits[vars.link_is_on_lower_level.*]) << 8;
    }

    if (vars.ancilla_objprio[ku] != 0)
        vars.oam_priority_value.* = 0x3000;

    if (vars.submodule_index.* == 0 and vars.ancilla_aux_timer[ku] != 0) {
        vars.ancilla_arr3[ku] -%= 1;
        if (sign8(vars.ancilla_arr3[ku])) {
            vars.ancilla_arr3[ku] = tables.kBoomerang_Draw_Tab0[vars.ancilla_G[ku]];
            vars.ancilla_arr1[ku] = (vars.ancilla_arr1[ku] +%
                (if (vars.ancilla_S[ku] != 0) @as(u8, 0xff) else 1)) & 3;
        }
    }

    const j: usize = vars.ancilla_arr1[ku];
    const x = info.x +% @as(u16, @bitCast(@as(i16, tables.kBoomerang_Draw_XY[j * 2 + 1])));
    const y = info.y +% @as(u16, @bitCast(@as(i16, tables.kBoomerang_Draw_XY[j * 2 + 0])));
    if (vars.ancilla_aux_timer[ku] == 0) {
        const i = tables.kBoomerang_Draw_OamIdx[vars.sort_sprites_setting.*];
        vars.oam_ext_cur_ptr.* = (i >> 2) +% 0xa20;
        vars.oam_cur_ptr.* = i +% 0x800;
    }
    Ancilla_SetOam_Safe(
        GetOamCurPtr(),
        x,
        y,
        0x26,
        (tables.kBoomerang_Flags[@as(usize, vars.ancilla_G[ku]) * 4 + j] & ~@as(u8, 0x30)) |
            hiPtr(vars.oam_priority_value).*,
        2,
    );
}

pub export fn Ancilla06_WallHit(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    vars.ancilla_arr3[ku] -%= 1;
    if (sign8(vars.ancilla_arr3[ku])) {
        const t = vars.ancilla_item_to_link[ku] +% 1;
        if (t == 5) {
            vars.ancilla_type[ku] = 0;
            return;
        }
        vars.ancilla_item_to_link[ku] = t;
        vars.ancilla_arr3[ku] = 1;
    }
    WallHit_Draw(k);
}

pub export fn Ancilla_SwordWallHit(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    vars.sprite_alert_flag.* = 3;
    vars.ancilla_aux_timer[ku] -%= 1;
    if (sign8(vars.ancilla_aux_timer[ku])) {
        const t = vars.ancilla_item_to_link[ku] +% 1;
        if (t == 8) {
            vars.ancilla_type[ku] = 0;
            return;
        }
        vars.ancilla_item_to_link[ku] = t;
        vars.ancilla_aux_timer[ku] = 1;
    }
    WallHit_Draw(k);
}

pub export fn WallHit_Draw(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    var info: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &info);

    var t: usize = @as(usize, vars.ancilla_item_to_link[ku]) * 4;

    var oam = GetOamCurPtr();
    var n: isize = 3;
    while (n >= 0) : ({
        n -= 1;
        t += 1;
    }) {
        if (tables.kWallHit_Char[t] != 0) {
            Ancilla_SetOam(
                oam,
                info.x +% @as(u16, @bitCast(@as(i16, tables.kWallHit_X[t]))),
                info.y +% @as(u16, @bitCast(@as(i16, tables.kWallHit_Y[t]))),
                tables.kWallHit_Char[t],
                (tables.kWallHit_Flags[t] & ~@as(u8, 0x30)) | hiPtr(vars.oam_priority_value).*,
                0,
            );
            oam += 1;
        }
        oam = Ancilla_AllocateOamFromCustomRegion(oam);
    }
}

pub export fn Ancilla07_Bomb(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    if (vars.submodule_index.* != 0) {
        if (vars.submodule_index.* == 8 or vars.submodule_index.* == 16) {
            Ancilla_HandleLiftLogic(k);
        } else if (k + 1 == vars.flag_is_ancilla_to_pick_up.* and vars.ancilla_K[ku] != 0) {
            if (vars.ancilla_K[ku] != 3) {
                Ancilla_LatchLinkCoordinates(k, 3);
                Ancilla_LatchAltitudeAboveLink(k);
                vars.ancilla_K[ku] = 3;
            }
            Ancilla_LatchCarriedPosition(k);
        }
        Bomb_Draw(k);
        return;
    }
    Ancilla_HandleLiftLogic(k);

    var old_y = Ancilla_LatchYCoordToZ(k);
    const s1a = vars.ancilla_dir[ku];
    const s1b = vars.ancilla_objprio[ku];
    vars.ancilla_objprio[ku] = 0;
    var flag = Ancilla_CheckTileCollision_Class2(k);

    if (vars.player_is_indoors.* != 0 and vars.ancilla_L[ku] != 0 and
        vars.ancilla_tile_attr[ku] == 0x1c)
        vars.ancilla_T[ku] = 1;

    // `goto label1` is a backward jump, so this is a loop in disguise.
    label1: while (true) {
        if (flag and ((vars.link_state_bits.* & 0x80) == 0 or vars.link_picking_throw_state.* != 0)) {
            if (s1b == 0 and vars.ancilla_arr4[ku] == 0) {
                vars.ancilla_arr4[ku] = 1;
                const qq: u8 = if (vars.ancilla_dir[ku] == 1) 16 else 4;
                if (vars.ancilla_y_vel[ku] != 0)
                    vars.ancilla_y_vel[ku] = if (sign8(vars.ancilla_y_vel[ku])) qq else 0 -% qq;
                if (vars.ancilla_x_vel[ku] != 0)
                    vars.ancilla_x_vel[ku] = if (sign8(vars.ancilla_x_vel[ku])) 4 else 0 -% @as(u8, 4);
                if (vars.ancilla_dir[ku] == 1 and vars.ancilla_z[ku] != 0) {
                    vars.ancilla_y_vel[ku] = 0 -% @as(u8, 4);
                    vars.ancilla_L[ku] = 2;
                }
            }
        } else if (!((k + 1 == vars.flag_is_ancilla_to_pick_up.*) and
            (vars.link_state_bits.* & 0x80) != 0) and
            (vars.ancilla_z[ku] == 0 or vars.ancilla_z[ku] == 0xff))
        {
            vars.ancilla_dir[ku] = 16;
            const bak0 = vars.ancilla_objprio[ku];
            _ = Ancilla_CheckTileCollision(k);
            vars.ancilla_objprio[ku] = bak0;
            const a = vars.ancilla_tile_attr[ku];
            if (a == 0x26) {
                flag = true;
                continue :label1;
            } else if (a == 0xc or a == 0x1c) {
                if (vars.dung_hdr_collision.* != 3) {
                    if (vars.ancilla_floor[ku] == 0 and vars.ancilla_z[ku] != 0 and
                        vars.ancilla_z[ku] != 0xff)
                        vars.ancilla_floor[ku] = 1;
                } else {
                    old_y = Ancilla_GetY(k) +% vars.dung_floor_y_vel.*;
                    Ancilla_SetX(k, Ancilla_GetX(k) +% vars.dung_floor_x_vel.*);
                }
            } else if (a == 0x20 or ((a & 0xf0) == 0xb0 and a != 0xb6 and a != 0xbc)) {
                if ((vars.link_state_bits.* & 0x80) == 0) {
                    if (k + 1 == vars.flag_is_ancilla_to_pick_up.*)
                        vars.flag_is_ancilla_to_pick_up.* = 0;
                    if (vars.ancilla_timer[ku] == 0) {
                        vars.ancilla_type[ku] = 0;
                        return;
                    }
                }
            } else if (a == 8) {
                if (k + 1 == vars.flag_is_ancilla_to_pick_up.*)
                    vars.flag_is_ancilla_to_pick_up.* = 0;
                if (vars.ancilla_timer[ku] == 0) {
                    Ancilla_SetY(k, Ancilla_GetY(k) -% 24);
                    Ancilla_TransmuteToSplash(k);
                    return;
                }
            } else if (a == 0x68 or a == 0x69 or a == 0x6a or a == 0x6b) {
                Ancilla_ApplyConveyor(k);
                old_y = Ancilla_GetY(k);
            } else {
                vars.ancilla_timer[ku] = if (vars.ancilla_L[ku] != 0) 0 else 2;
            }
        }
        break;
    }
    // endif_3

    Ancilla_SetY(k, old_y);
    vars.ancilla_dir[ku] = s1a;
    vars.ancilla_objprio[ku] |= s1b;
    Bomb_CheckSpriteAndPlayerDamage(k);
    vars.ancilla_arr3[ku] -%= 1;
    if (vars.ancilla_arr3[ku] == 0) {
        vars.ancilla_item_to_link[ku] +%= 1;
        if (vars.ancilla_item_to_link[ku] == 1) {
            Ancilla_Sfx2_Pan(k, 0xc);
            if (k + 1 == vars.flag_is_ancilla_to_pick_up.*) {
                vars.flag_is_ancilla_to_pick_up.* = 0;
                if (vars.link_state_bits.* & 0x80 != 0) {
                    vars.link_state_bits.* = 0;
                    vars.link_cant_change_direction.* = 0;
                }
            }
        }

        if (vars.ancilla_item_to_link[ku] == 11) {
            // transmute to door debris?
            vars.ancilla_type[ku] = if (vars.ancilla_step[ku] != 0) 8 else 0;
            return;
        }
        vars.ancilla_arr3[ku] = tables.kBomb_Tab0[vars.ancilla_item_to_link[ku]];
    }

    if (vars.ancilla_item_to_link[ku] == 7 and vars.ancilla_arr3[ku] == 2) {
        // check whether the bomb causes any door debris, the bomb
        // will transmute to debris later on.
        vars.door_debris_x[ku] = 0;
        Bomb_CheckForDestructibles(Ancilla_GetX(k), Ancilla_GetY(k), @truncate(@as(u32, @bitCast(k))));
        if (vars.door_debris_x[ku] != 0)
            vars.ancilla_step[ku] = 1;
    }
    Bomb_Draw(k);
}

pub export fn Ancilla_ApplyConveyor(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    const j: usize = vars.ancilla_tile_attr[ku] -% 0x68;
    vars.ancilla_y_vel[ku] = @bitCast(tables.kAncilla_Belt_Yvel[j]);
    vars.ancilla_x_vel[ku] = @bitCast(tables.kAncilla_Belt_Xvel[j]);
    Ancilla_MoveY(k);
    Ancilla_MoveX(k);
}

pub export fn Bomb_CheckSpriteAndPlayerDamage(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    if (vars.ancilla_item_to_link[ku] == 0 or vars.ancilla_item_to_link[ku] >= 9)
        return;
    Bomb_CheckSpriteDamage(k);
    if (vars.link_disable_sprite_damage.* != 0) {
        if (k + 1 == vars.flag_is_ancilla_to_pick_up.* and vars.link_state_bits.* & 0x80 != 0) {
            vars.link_state_bits.* &= ~@as(u8, 0x80);
            vars.link_cant_change_direction.* = 0;
        }
        return;
    }

    if (vars.link_auxiliary_state.* != 0 or vars.link_incapacitated_timer.* != 0 or
        vars.ancilla_floor[ku] != vars.link_is_on_lower_level.*)
        return;

    var hb: SpriteHitBox = undefined;
    hb.r0_xlo = @truncate(vars.link_x_coord.*);
    hb.r8_xhi = @truncate(vars.link_x_coord.* >> 8);
    hb.r1_ylo = @truncate(vars.link_y_coord.*);
    hb.r9_yhi = @truncate(vars.link_y_coord.* >> 8);
    hb.r2 = 0x10;
    hb.r3 = 0x18;

    const ax: i32 = @as(i32, Ancilla_GetX(k)) - 16;
    const ay: i32 = @as(i32, Ancilla_GetY(k)) - 16;
    hb.r6_spr_xsize = 32;
    hb.r7_spr_ysize = 32;
    hb.r4_spr_xlo = @truncate(@as(u32, @bitCast(ax)));
    hb.r10_spr_xhi = @truncate(@as(u32, @bitCast(ax)) >> 8);
    hb.r5_spr_ylo = @truncate(@as(u32, @bitCast(ay)));
    hb.r11_spr_yhi = @truncate(@as(u32, @bitCast(ay)) >> 8);

    if (!sprite.CheckIfHitBoxesOverlap(&hb))
        return;

    const x = Ancilla_GetX(k) -% 8;
    const y = Ancilla_GetY(k) -% 12;

    const j: usize = @intCast(Bomb_GetDisplacementFromLink(k));
    const pt = Bomb_ProjectSpeedTowardsPlayer(k, x, y, tables.kBomb_Dmg_Speed[j]);
    if (vars.countdown_for_blink.* != 0 or vars.flag_block_link_menu.* == 2)
        return;
    vars.link_actual_vel_x.* = pt.x;
    vars.link_actual_vel_y.* = pt.y;

    vars.link_actual_vel_z.* = tables.kBomb_Dmg_Zvel[j];
    vars.link_actual_vel_z_copy.* = vars.link_actual_vel_z.*;
    vars.link_incapacitated_timer.* = tables.kBomb_Dmg_Delay[j];
    vars.link_auxiliary_state.* = 1;
    vars.countdown_for_blink.* = 58;
    if (vars.dung_savegame_state_bits.* & 0x8000 == 0)
        vars.link_give_damage.* = tables.kBomb_Dmg_ToLink[vars.link_armor.*];
}

/// The `label_6` goto target inside Ancilla_HandleLiftLogic.
fn liftLogic_label6(k: c_int) void {
    const ku: usize = @intCast(k);
    if (vars.ancilla_item_to_link[ku] != 0)
        return;
    if (vars.ancilla_K[ku] == 3) {
        vars.ancilla_z_vel[ku] -%= 2;
        Ancilla_MoveZ(k);
        if (vars.ancilla_z[ku] != 0 and vars.ancilla_z[ku] < 252)
            return;
        vars.ancilla_z[ku] = 0;
        vars.ancilla_R[ku] +%= 1;
        if (vars.ancilla_R[ku] != 3) {
            vars.ancilla_z_vel[ku] = 24;
            return;
        }
        vars.ancilla_K[ku] = 0;
    }
    vars.ancilla_R[ku] = 0;
    vars.link_speed_setting.* = 0;
}

/// The `clear_pickup_item` goto target inside Ancilla_HandleLiftLogic.
fn liftLogic_clearPickupItem(k: c_int) void {
    const ku: usize = @intCast(k);
    vars.flag_is_ancilla_to_pick_up.* = 0;
    var coll: CheckPlayerCollOut = undefined;
    if (vars.ancilla_item_to_link[ku] != 0 or vars.link_state_bits.* != 0 or
        !Ancilla_CheckLinkCollision(k, 0, &coll) or
        vars.ancilla_floor[ku] != vars.link_is_on_lower_level.*)
        return;
    if (coll.r8 >= 16 or coll.r10 >= 12) {
        const j: u8 = if (coll.r8 >= coll.r10)
            (if (sign16(coll.r4)) @as(u8, 1) else 0)
        else
            (if (sign16(coll.r6)) @as(u8, 3) else 2);
        if (j *% 2 != vars.link_direction_facing.*)
            return;
    }
    vars.flag_is_ancilla_to_pick_up.* = @truncate(@as(u32, @bitCast(k +% 1)));
    vars.ancilla_K[ku] = 0;
    vars.ancilla_aux_timer[ku] = tables.kAncilla_Liftable_Delay[0];
    vars.ancilla_L[ku] = 0;
    vars.ancilla_z[ku] = 0;
}

pub export fn Ancilla_HandleLiftLogic(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);

    if (vars.ancilla_R[ku] != 0) {
        liftLogic_label6(k);
        return;
    }
    if (vars.ancilla_L[ku] == 0) {
        if (vars.flag_is_ancilla_to_pick_up.* == 0) {
            liftLogic_clearPickupItem(k);
            return;
        }

        if (vars.flag_is_ancilla_to_pick_up.* != k + 1)
            return;
        if ((vars.link_disable_sprite_damage.* == 0 and vars.link_incapacitated_timer.* != 0) or
            vars.byte_7E03FD.* != 0 or vars.link_auxiliary_state.* == 1)
        {
            vars.ancilla_R[ku] = 1;
            vars.ancilla_z_vel[ku] = 0;
            vars.flag_is_ancilla_to_pick_up.* = 0;
            vars.ancilla_arr4[ku] = 0;
            liftLogic_label6(k);
            return;
        }
        if (vars.link_state_bits.* & 0x80 == 0) {
            liftLogic_clearPickupItem(k);
            return;
        }
        var j: u8 = vars.ancilla_K[ku];
        if (vars.link_picking_throw_state.* != 2 and vars.flag_is_ancilla_to_pick_up.* != 0 and j != 3) {
            if (j == 0 and vars.ancilla_aux_timer[ku] == 16)
                Ancilla_Sfx2_Pan(k, 0x1d);
            vars.ancilla_aux_timer[ku] -%= 1;
            if (sign8(vars.ancilla_aux_timer[ku])) {
                j +%= 1;
                vars.ancilla_K[ku] = j;
                vars.ancilla_aux_timer[ku] = if (j == 3)
                    0 -% @as(u8, 2)
                else
                    tables.kAncilla_Liftable_Delay[j];
                if (j == 3) {
                    Ancilla_LatchAltitudeAboveLink(k);
                    return;
                }
            }
            Ancilla_LatchLinkCoordinates(k, j);
            return;
        }
        if (j != 3)
            return;

        if (vars.link_picking_throw_state.* != 2 and
            (vars.submodule_index.* != 0 or
                ((vars.filtered_joypad_L.* | vars.filtered_joypad_H.*) & 0x80) == 0))
        {
            if (vars.ancilla_item_to_link[ku] != 0)
                return;
            if (vars.player_near_pit_state.* >= 2) {
                vars.link_speed_setting.* = 0;
                if (k + 1 == vars.flag_is_ancilla_to_pick_up.*) {
                    vars.flag_is_ancilla_to_pick_up.* = 0;
                    vars.ancilla_type[ku] = 0;
                }
                return;
            }
            if ((vars.link_is_in_deep_water.* | vars.link_is_bunny_mirror.*) == 0) {
                Ancilla_LatchCarriedPosition(k);
                return;
            }
            vars.link_state_bits.* = 0;
        }
        const d: usize = vars.link_direction_facing.* >> 1;
        vars.ancilla_dir[ku] = @truncate(d);
        vars.ancilla_z_vel[ku] = 24;
        vars.ancilla_y_vel[ku] = @bitCast(tables.kAncilla_Liftable_Yvel[d]);
        vars.ancilla_x_vel[ku] = @bitCast(tables.kAncilla_Liftable_Xvel[d]);
        vars.link_picking_throw_state.* = 2;
        vars.ancilla_L[ku] = 1;
        vars.flag_is_ancilla_to_pick_up.* = 0;
        vars.ancilla_arr4[ku] = 0;
        vars.ancilla_K[ku] = 0;
        vars.ancilla_objprio[ku] = 0;
        Ancilla_Sfx3_Pan(k, 0x13);
    }
    // endif_1
    if (vars.ancilla_item_to_link[ku] == 0) {
        vars.ancilla_z_vel[ku] -%= 2;
        Ancilla_MoveY(k);
        Ancilla_MoveX(k);
        const old_z = vars.ancilla_z[ku];
        Ancilla_MoveZ(k);
        if (vars.ancilla_arr4[ku] != 0 and vars.ancilla_dir[ku] == 1 and !sign8(vars.ancilla_z[ku]))
            Ancilla_SetY(k, Ancilla_GetY(k) +%
                @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(vars.ancilla_z[ku] -% old_z))))));
        if (!sign8(vars.ancilla_z[ku]) or vars.ancilla_z[ku] == 0xff)
            return;
        vars.ancilla_z[ku] = 0;
        Ancilla_Sfx2_Pan(k, 0x21);
        vars.ancilla_L[ku] +%= 1;
        if (vars.ancilla_L[ku] != 3) {
            vars.ancilla_y_vel[ku] = @bitCast(@divTrunc(@as(i8, @bitCast(vars.ancilla_y_vel[ku])), 2));
            vars.ancilla_x_vel[ku] = @bitCast(@divTrunc(@as(i8, @bitCast(vars.ancilla_x_vel[ku])), 2));
            vars.ancilla_z_vel[ku] = 16;
            vars.ancilla_arr4[ku] = 0;
        } else {
            vars.ancilla_z[ku] = 0;
            vars.ancilla_L[ku] = 0;
            vars.ancilla_arr4[ku] = 0;
            vars.link_speed_setting.* = 0;
            vars.ancilla_y_vel[ku] = 0;
            vars.ancilla_x_vel[ku] = 0;
            vars.ancilla_z_vel[ku] = 0;
            if (vars.ancilla_T[ku] != 0) {
                vars.ancilla_floor[ku] = vars.ancilla_T[ku];
                vars.ancilla_T[ku] = 0;
            }
        }
    }
}

pub export fn Ancilla_LatchAltitudeAboveLink(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    vars.ancilla_z[ku] = 17;
    Ancilla_SetY(k, Ancilla_GetY(k) +% 17);
    vars.ancilla_objprio[ku] = 0;
}

pub export fn Ancilla_LatchLinkCoordinates(k: c_int, j_in: c_int) callconv(.c) void {
    const j: usize = @as(usize, @intCast(j_in)) * 4 + (vars.link_direction_facing.* >> 1);
    Ancilla_SetXY(
        k,
        vars.link_x_coord.* +% @as(u16, @bitCast(@as(i16, tables.kAncilla_Func3_X[j]))),
        vars.link_y_coord.* +% @as(u16, @bitCast(@as(i16, tables.kAncilla_Func3_Y[j]))),
    );
}

pub export fn Ancilla_LatchCarriedPosition(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    vars.link_speed_setting.* = 12;
    vars.ancilla_floor[ku] = vars.link_is_on_lower_level.*;
    vars.ancilla_floor2[ku] = vars.link_is_on_lower_level_mirror.*;
    var z = vars.link_z_coord.*;
    if (z == 0xffff)
        z = 0;
    Ancilla_SetXY(
        k,
        vars.link_x_coord.* +% 8,
        vars.link_y_coord.* -% z +% 18 +%
            @as(u16, @bitCast(@as(i16, tables.kAncilla_Func2_Y[vars.link_animation_steps.*]))),
    );
}

pub export fn Ancilla_LatchYCoordToZ(k: c_int) callconv(.c) u16 {
    const ku: usize = @intCast(k);
    const y = Ancilla_GetY(k);
    const z: i8 = @bitCast(vars.ancilla_z[ku]);
    if (vars.ancilla_dir[ku] == 1 and z != -1)
        Ancilla_SetY(k, y -% @as(u16, @bitCast(@as(i16, z))));
    return y;
}

pub export fn Bomb_GetDisplacementFromLink(k: c_int) callconv(.c) c_int {
    const x = Ancilla_GetX(k);
    const y = Ancilla_GetY(k);
    const sum = abs16(vars.link_x_coord.* +% 8 -% x) +% abs16(vars.link_y_coord.* +% 12 -% y);
    return @intCast((sum & 0xfc) >> 2);
}

pub export fn Bomb_Draw(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);

    const z: i8 = @bitCast(vars.ancilla_z[ku]);
    if (z != 0 and z != -1 and vars.ancilla_K[ku] != 3 and vars.ancilla_objprio[ku] != 0)
        vars.oam_priority_value.* = 0x3000;
    pt.y -%= @as(u16, @bitCast(@as(i16, z)));
    const j: usize = @as(usize, tables.kBomb_Draw_Tab0[vars.ancilla_item_to_link[ku]]) * 6;

    var r11: u8 = 2;
    if (vars.ancilla_item_to_link[ku] == 0) {
        r11 = if (vars.ancilla_arr3[ku] < 0x20) (vars.ancilla_arr3[ku] & 0xe) else 4;
    }

    if (vars.ancilla_item_to_link[ku] == 0) {
        if (vars.ancilla_L[ku] == 0 and
            (vars.sprite_type[0] == 0x92 or k + 1 == vars.flag_is_ancilla_to_pick_up.*) and
            ((vars.link_state_bits.* & 0x80) == 0 or
                (vars.ancilla_K[ku] != 3 and vars.link_direction_facing.* == 0)))
        {
            Ancilla_AllocateOamFromRegion_B_or_E(12);
        } else if (vars.sort_sprites_setting.* != 0 and vars.ancilla_floor[ku] != 0 and
            (vars.ancilla_L[ku] != 0 or
                (k + 1 == vars.flag_is_ancilla_to_pick_up.* and (vars.link_state_bits.* & 0x80) != 0)))
        {
            vars.oam_cur_ptr.* = 0x800 + 0x34 * 4;
            vars.oam_ext_cur_ptr.* = 0xa20 + 0x34;
        }
    }

    var oam = GetOamCurPtr();
    const oam_org = oam;
    const numframes = tables.kBomb_Draw_Tab2[vars.ancilla_item_to_link[ku]];

    oam += if (vars.ancilla_item_to_link[ku] == 0 and
        (vars.ancilla_tile_attr[ku] == 9 or vars.ancilla_tile_attr[ku] == 0x40)) @as(usize, 2) else 0;

    _ = AncillaDraw_Explosion(oam, @intCast(j), 0, numframes, r11, pt.x, pt.y);
    oam += numframes;

    var r10: u8 = undefined;
    if (!Bomb_CheckUndersideSpriteStatus(k, &pt, &r10)) {
        if (oam != oam_org + 1)
            oam = oam_org;
        AncillaDraw_Shadow(oam, r10, pt.x, pt.y, hiPtr(vars.oam_priority_value).*);
    }
}

pub export fn Ancilla08_DoorDebris(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    DoorDebris_Draw(k);
    vars.ancilla_arr26[ku] -%= 1;
    if (sign8(vars.ancilla_arr26[ku])) {
        vars.ancilla_arr26[ku] = 7;
        vars.ancilla_arr25[ku] +%= 1;
        if (vars.ancilla_arr25[ku] == 4)
            vars.ancilla_type[ku] = 0;
    }
}

pub export fn DoorDebris_Draw(k: c_int) callconv(.c) void {
    const ku: usize = @intCast(k);
    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    const y = vars.door_debris_y[ku] -% vars.BG2VOFS_copy2.*;
    const x = vars.door_debris_x[ku] -% vars.BG2HOFS_copy2.*;
    const j: usize = @as(usize, vars.ancilla_arr25[ku]) +
        @as(usize, vars.door_debris_direction[ku]) * 4;

    var i: usize = 0;
    while (i != 2) : (i += 1) {
        const t = j * 2 + i;
        const d = tables.kDoorDebris_CharFlags[t];
        Ancilla_SetOam(
            oam,
            x +% tables.kDoorDebris_XY[t * 2 + 1],
            y +% tables.kDoorDebris_XY[t * 2 + 0],
            @truncate(d),
            (@as(u8, @truncate(d >> 8)) & 0xc0) | hiPtr(vars.oam_priority_value).*,
            0,
        );
        oam = Ancilla_AllocateOamFromCustomRegion(oam + 1);
    }
}

pub export fn Ancilla_SetXY(k: c_int, x: u16, y: u16) callconv(.c) void {
    Ancilla_SetX(k, x);
    Ancilla_SetY(k, y);
}

fn initSlot(k: usize, atype: u8) void {
    vars.ancilla_type[k] = atype;
    vars.ancilla_floor[k] = vars.link_is_on_lower_level.*;
    vars.ancilla_floor2[k] = vars.link_is_on_lower_level_mirror.*;
    vars.ancilla_y_vel[k] = 0;
    vars.ancilla_x_vel[k] = 0;
    vars.ancilla_objprio[k] = 0;
    vars.ancilla_U[k] = 0;
    vars.ancilla_numspr[k] = tables.kAncilla_Pflags[atype];
}

pub export fn Ancilla_AddAncilla(atype: u8, limit: u8) callconv(.c) c_int {
    const k = Ancilla_AllocInit(atype, limit);
    if (k >= 0) initSlot(@intCast(k), atype);
    return k;
}

pub export fn AncillaAdd_AddAncilla_Bank08(atype: u8, limit: u8) callconv(.c) c_int {
    return Ancilla_AddAncilla(atype, limit);
}

pub export fn Ancilla_AllocInit(atype: u8, limit: u8) callconv(.c) c_int {
    // Preserve this scratch write: the original also uses R14 in tile detection.
    if (rtl.g_ram[features.kRam_BugsFixed] >= features.kBugFix_PolyRenderer)
        loPtr(vars.R14).* = limit +% 1;
    var count: usize = 0;
    for (0..5) |i| {
        if (vars.ancilla_type[i] == atype) count += 1;
    }
    if (@as(usize, limit) + 1 == count) return -1;
    var k: c_int = if (atype == 7 or atype == 8) limit else 4;
    while (k >= 0) : (k -= 1) {
        if (vars.ancilla_type[@intCast(k)] == 0) return k;
    }
    k = vars.ancilla_alloc_rotate.*;
    while (true) {
        k -= 1;
        if (k < 0) k = limit;
        const old = vars.ancilla_type[@intCast(k)];
        if (old == 0x3c or old == 0x13 or old == 0xa) {
            vars.ancilla_alloc_rotate.* = @intCast(k);
            return k;
        }
        if (k == 0) break;
    }
    vars.ancilla_alloc_rotate.* = 0;
    return -1;
}

pub export fn AncillaAdd_CheckForPresence(atype: u8) callconv(.c) bool {
    for (0..6) |i| {
        if (vars.ancilla_type[i] == atype) return true;
    }
    return false;
}

pub export fn AncillaAdd_ArrowFindSlot(atype: u8, limit: u8) callconv(.c) c_int {
    var count: usize = 0;
    for (0..5) |i| {
        if (vars.ancilla_type[i] == 10) count += 1;
    }
    var k: c_int = 4;
    if (count != @as(usize, limit) + 1) {
        while (k >= 0) : (k -= 1) {
            if (vars.ancilla_type[@intCast(k)] == 0) break;
        }
    } else {
        while (true) {
            vars.ancilla_alloc_rotate.* -%= 1;
            if (sign8(vars.ancilla_alloc_rotate.*)) vars.ancilla_alloc_rotate.* = 4;
            k = vars.ancilla_alloc_rotate.*;
            if (vars.ancilla_type[@intCast(k)] == 10) break;
        }
    }
    if (k >= 0) initSlot(@intCast(k), atype);
    return k;
}

pub export fn Ancilla_PrepOamCoord(k: c_int, info: *Point16U) callconv(.c) void {
    vars.oam_priority_value.* = @as(u16, tables.kTagalongLayerBits[vars.ancilla_floor[@intCast(k)]]) << 8;
    info.* = .{ .x = Ancilla_GetX(k) -% vars.BG2HOFS_copy2.*, .y = Ancilla_GetY(k) -% vars.BG2VOFS_copy2.* };
}

pub export fn Ancilla_PrepAdjustedOamCoord(k: c_int, info: *Point16U) callconv(.c) void {
    vars.oam_priority_value.* = @as(u16, tables.kTagalongLayerBits[vars.ancilla_floor[@intCast(k)]]) << 8;
    info.* = .{ .x = Ancilla_GetX(k) -% vars.BG2HOFS_copy.*, .y = Ancilla_GetY(k) -% vars.BG2VOFS_copy.* };
}

inline fn signedOffset(value: i16) u16 {
    return @bitCast(value);
}

inline fn lowWord(value: c_int) u16 {
    return @truncate(@as(u32, @bitCast(value)));
}

inline fn absWord(value: u16) u16 {
    return if (value & 0x8000 != 0) 0 -% value else value;
}

pub export fn Ancilla_CheckLinkCollision(k: c_int, j: c_int, out: *CheckPlayerCollOut) callconv(.c) bool {
    const i: usize = @intCast(j);
    const y = Ancilla_GetY(k) +% signedOffset(tables.kAncilla_Coll_Yoffs[i]) +% signedOffset(@as(i8, @bitCast(vars.ancilla_z[@intCast(k)])));
    const x = Ancilla_GetX(k) +% signedOffset(tables.kAncilla_Coll_Xoffs[i]);
    out.r4 = vars.link_y_coord.* +% signedOffset(tables.kAncilla_Coll_LinkYoffs[i]) -% y;
    out.r6 = vars.link_x_coord.* +% signedOffset(tables.kAncilla_Coll_LinkXoffs[i]) -% x;
    out.r8 = absWord(out.r4);
    out.r10 = absWord(out.r6);
    return out.r8 < tables.kAncilla_Coll_H[i] and out.r10 < tables.kAncilla_Coll_W[i];
}

pub export fn Hookshot_CheckProximityToLink(x: c_int, y: c_int) callconv(.c) bool {
    return absWord(vars.link_y_coord.* -% vars.BG2VOFS_copy2.* +% 8 -% lowWord(y)) < 12 and
        absWord(vars.link_x_coord.* -% vars.BG2HOFS_copy2.* +% 4 -% lowWord(x)) < 12;
}

pub export fn Ancilla_CheckForEntranceTrigger(what: c_int) callconv(.c) bool {
    const i: usize = @intCast(what);
    return absWord(vars.link_y_coord.* +% 12 -% tables.kEntranceTrigger_BaseY[i]) < tables.kEntranceTrigger_SizeY[i] and
        absWord(vars.link_x_coord.* +% 8 -% tables.kEntranceTrigger_BaseX[i]) < tables.kEntranceTrigger_SizeX[i];
}

pub export fn AncillaDraw_Shadow(oam: [*]align(1) OamEnt, k: c_int, x: c_int, y: c_int, pal: u8) callconv(.c) void {
    const i: usize = @intCast(k * 2);
    const xx = lowWord(x) +% @as(u16, if (k == 2) 4 else 0);
    Ancilla_SetOam_Safe(oam, xx, lowWord(y), tables.kAncilla_DrawShadow_Char[i], (tables.kAncilla_DrawShadow_Flags[i] & 0xcf) | pal, 0);
    if (tables.kAncilla_DrawShadow_Char[i + 1] != 0xff)
        Ancilla_SetOam_Safe(oam + 1, xx +% 8, lowWord(y), tables.kAncilla_DrawShadow_Char[i + 1], (tables.kAncilla_DrawShadow_Flags[i + 1] & 0xcf) | pal, 0);
}

pub export fn Ancilla_AllocateOamFromRegion_B_or_E(size: u8) callconv(.c) void {
    if (vars.sort_sprites_setting.* == 0) {
        _ = sprite.Oam_AllocateFromRegionB(size);
    } else {
        _ = sprite.Oam_AllocateFromRegionE(size);
    }
}

pub export fn Ancilla_AllocateOamFromRegion_A_or_D_or_F(k: c_int, size: u8) callconv(.c) c_int {
    if (vars.sort_sprites_setting.* == 0) return sprite.Oam_AllocateFromRegionA(size);
    return if (vars.ancilla_floor[@intCast(k)] != 0) sprite.Oam_AllocateFromRegionF(size) else sprite.Oam_AllocateFromRegionD(size);
}

pub export fn Ancilla_AllocateOamFromCustomRegion(oam: [*]align(1) OamEnt) callconv(.c) [*]align(1) OamEnt {
    var offset = @intFromPtr(oam) - @intFromPtr(&rtl.g_ram);
    if (vars.sort_sprites_setting.* != 0) {
        if (offset < 0x900) {
            if (offset < 0x8e0) return oam;
            offset = 0x820;
        } else {
            if (offset < 0x9d0) return oam;
            offset = 0x940;
        }
    } else {
        if (offset < 0x990) return oam;
        offset = 0x820;
    }
    vars.oam_cur_ptr.* = @intCast(offset);
    vars.oam_ext_cur_ptr.* = @intCast(((offset - 0x800) >> 2) + 0xa20);
    return GetOamCurPtr();
}

pub export fn HitStars_UpdateOamBufferPosition(oam: [*]align(1) OamEnt) callconv(.c) [*]align(1) OamEnt {
    const offset = @intFromPtr(oam) - @intFromPtr(&rtl.g_ram);
    if (vars.sort_sprites_setting.* == 0 and offset >= 0x9d0) {
        vars.oam_cur_ptr.* = 0x820;
        vars.oam_ext_cur_ptr.* = 0xa28;
        return GetOamCurPtr();
    }
    return oam;
}

pub export fn Ancilla_GetRadialProjection(angle: u8, radius: u8) callconv(.c) AncillaRadialProjection {
    const px = @as(u16, tables.kRadialProjection_Tab0[angle]) * radius;
    const py = @as(u16, tables.kRadialProjection_Tab2[angle]) * radius;
    return .{ .r0 = @intCast((px >> 8) + ((px >> 7) & 1)), .r2 = tables.kRadialProjection_Tab1[angle], .r4 = @intCast((py >> 8) + ((py >> 7) & 1)), .r6 = tables.kRadialProjection_Tab3[angle] };
}

pub export fn Ancilla_CalculateSfxPan(k: c_int) callconv(.c) u8 {
    return misc.CalculateSfxPan(Ancilla_GetX(k));
}

pub export fn Ancilla_TerminateIfOffscreen(k: c_int) callconv(.c) void {
    const extra: u16 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x40 else 0;
    const x = Ancilla_GetX(k) -% vars.BG2HOFS_copy2.* +% extra;
    const y = Ancilla_GetY(k) -% vars.BG2VOFS_copy2.*;
    if (x >= 244 + extra * 2 or y >= 240) vars.ancilla_type[@intCast(k)] = 0;
}

pub export fn Bomb_CheckUndersideSpriteStatus(k: c_int, pt: *Point16U, out: *u8) callconv(.c) bool {
    const i: usize = @intCast(k);
    if (vars.ancilla_item_to_link[i] != 0) return true;
    var shadow: u8 = 0;
    if (vars.ancilla_tile_attr[i] == 9) {
        vars.ancilla_arr22[i] -%= 1;
        if (sign8(vars.ancilla_arr22[i])) {
            vars.ancilla_arr22[i] = 3;
            vars.ancilla_arr23[i] +%= 1;
            if (vars.ancilla_arr23[i] == 3) vars.ancilla_arr23[i] = 0;
        }
        shadow = vars.ancilla_arr23[i] +% 4;
        const sound = vars.sound_effect_1.* & 0x3f;
        if (sound == 0xb or sound == 0x21) vars.sound_effect_1.* = Ancilla_CalculateSfxPan(k) | 0x28;
    } else if (vars.ancilla_tile_attr[i] == 0x40) {
        shadow = 3;
    }
    if (vars.ancilla_z[i] >= 2 and vars.ancilla_z[i] < 252) shadow = 2;
    if (k + 1 == vars.flag_is_ancilla_to_pick_up.* and vars.link_state_bits.* & 0x80 != 0) return true;
    pt.y +%= signedOffset(@as(i8, @bitCast(vars.ancilla_z[i]))) +% 2;
    pt.x -%= 8;
    out.* = shadow;
    return false;
}

pub export fn Ancilla_AddRupees(k: c_int) callconv(.c) bool {
    const amount: u16 = switch (vars.ancilla_item_to_link[@intCast(k)]) {
        0x34 => 1,
        0x35 => 5,
        0x36, 0x47 => 20,
        0x40 => 100,
        0x41 => 50,
        0x46 => 300,
        else => return false,
    };
    vars.link_rupees_goal.* +%= amount;
    return true;
}

pub export fn Ancilla_CheckInitialTile_A(k: c_int) callconv(.c) c_int {
    var j: usize = @as(usize, vars.ancilla_dir[@intCast(k)]) * 3;
    var n: c_int = 2;
    while (n >= 0) : ({
        n -= 1;
        j += 1;
    }) {
        Ancilla_SetXY(k, vars.link_x_coord.* +% signedOffset(tables.kAncilla_Xoffs_Hb[j]), vars.link_y_coord.* +% signedOffset(tables.kAncilla_Yoffs_Hb[j]));
        if (Ancilla_CheckTileCollision(k) != 0) break;
    }
    return n;
}

pub export fn Ancilla_CheckInitialTileCollision_Class2(k: c_int) callconv(.c) bool {
    const first = @as(usize, vars.ancilla_dir[@intCast(k)]) * 2;
    for (first..first + 3) |j| {
        Ancilla_SetXY(k, vars.link_x_coord.* +% signedOffset(tables.kAncilla_InitialTileColl_X[j]), vars.link_y_coord.* +% signedOffset(tables.kAncilla_InitialTileColl_Y[j]));
        if (Ancilla_CheckTileCollision_Class2(k)) return true;
    }
    return false;
}

pub export fn Ancilla09_Arrow(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    if (vars.submodule_index.* != 0) return Arrow_Draw(k);
    vars.ancilla_item_to_link[i] -%= 1;
    if (!sign8(vars.ancilla_item_to_link[i])) {
        if (vars.ancilla_item_to_link[i] >= 4) return;
    } else {
        vars.ancilla_item_to_link[i] = 0xff;
    }
    Ancilla_MoveY(k);
    Ancilla_MoveX(k);
    if (vars.link_item_bow.* & 4 != 0 and vars.frame_counter.* & 1 == 0) AncillaAdd_SilverArrowSparkle(k);
    vars.ancilla_S[i] = 255;
    const hit = Ancilla_CheckSpriteCollision(k);
    var j: usize = undefined;
    if (hit >= 0) {
        j = @intCast(hit);
        vars.ancilla_x_vel[i] = vars.ancilla_x_lo[i] -% vars.sprite_x_lo[j];
        vars.ancilla_y_vel[i] = vars.ancilla_y_lo[i] -% vars.sprite_y_lo[j] +% vars.sprite_z[j];
        vars.ancilla_S[i] = @intCast(j);
        if (vars.sprite_type[j] == 0x65) {
            if (vars.sprite_A[j] == 1) {
                vars.sound_effect_2.* = 0x2d;
                vars.sprite_delay_aux2[j] = 0x80;
                vars.sprite_delay_aux4[0] = 128;
                if (vars.byte_7E0B88.* < 9) vars.byte_7E0B88.* += 1;
                vars.sprite_B[j] = vars.byte_7E0B88.*;
                vars.sprite_G[j] +%= 1;
            } else {
                vars.sprite_delay_aux3[j] = 4;
                vars.byte_7E0B88.* = 0;
            }
        } else {
            vars.byte_7E0B88.* = 0;
        }
    } else {
        const collision = Ancilla_CheckTileCollision(k);
        if (collision == 0) return Arrow_Draw(k);
        vars.ancilla_H[i] = collision >> 1;
        j = vars.ancilla_dir[i] & 3;
        Ancilla_SetX(k, Ancilla_GetX(k) +% signedOffset(tables.kArrow_X[j]));
        Ancilla_SetY(k, Ancilla_GetY(k) +% signedOffset(tables.kArrow_Y[j]));
        vars.byte_7E0B88.* = 0;
    }
    // The original also uses the direction as a sprite index after a tile hit.
    if (vars.sprite_type[j] != 0x1b) Ancilla_Sfx2_Pan(k, 8);
    vars.ancilla_item_to_link[i] = 0;
    vars.ancilla_type[i] = 10;
    vars.ancilla_aux_timer[i] = 1;
    if (vars.ancilla_H[i] != 0) {
        vars.ancilla_x_lo[i] +%= @truncate(vars.BG1HOFS_copy2.* -% vars.BG2HOFS_copy2.*);
        vars.ancilla_y_lo[i] +%= @truncate(vars.BG1VOFS_copy2.* -% vars.BG2VOFS_copy2.*);
    }
    Arrow_Draw(k);
}

pub export fn Arrow_Draw(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    if (vars.ancilla_objprio[i] != 0) hiPtr(vars.oam_priority_value).* = 0x30;
    if (vars.ancilla_H[i] != 0) {
        pt.x +%= vars.BG2VOFS_copy2.* -% vars.BG1VOFS_copy2.*;
        pt.y +%= vars.BG2HOFS_copy2.* -% vars.BG1HOFS_copy2.*;
    }
    const frame = vars.ancilla_item_to_link[i];
    var j: usize = vars.ancilla_dir[i] & ~@as(u8, 4);
    if (vars.ancilla_type[i] == 0xa) {
        j = j * 4 + 8 + @as(usize, if (frame & 8 != 0) 1 else frame & 3);
    } else if (!sign8(frame)) {
        j |= 4;
    }
    j *= 2;
    const start = GetOamCurPtr();
    var oam = start;
    const palette: u8 = if (vars.link_item_bow.* & 4 != 0) 2 else 4;
    for (j..j + 2) |t| {
        if (tables.kArrow_Draw_Char[t] == 0xff) continue;
        Ancilla_SetOam(oam, pt.x +% signedOffset(tables.kArrow_Draw_X[t]), pt.y +% signedOffset(tables.kArrow_Draw_Y[t]), tables.kArrow_Draw_Char[t], (tables.kArrow_Draw_Flags[t] & 0xc1) | palette | hiPtr(vars.oam_priority_value).*, 0);
        oam += 1;
    }
    if (start[0].y == 0xf0 and start[1].y == 0xf0) vars.ancilla_type[i] = 0;
}

pub export fn Ancilla0A_ArrowInTheWall(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    const j = vars.ancilla_S[i];
    if (!sign8(j)) {
        if (vars.sprite_state[j] < 9 or sign8(vars.sprite_z[j]) or vars.sprite_ignore_projectile[j] != 0 or vars.sprite_defl_bits[j] & 2 != 0) {
            vars.ancilla_type[i] = 0;
            return;
        }
        Ancilla_SetX(k, sprite.Sprite_GetX(j) +% signedOffset(@as(i8, @bitCast(vars.ancilla_x_vel[i]))));
        Ancilla_SetY(k, sprite.Sprite_GetY(j) +% signedOffset(@as(i8, @bitCast(vars.ancilla_y_vel[i]))) -% vars.sprite_z[j]);
    }
    if (vars.submodule_index.* == 0) {
        vars.ancilla_aux_timer[i] -%= 1;
        if (vars.ancilla_aux_timer[i] == 0) {
            vars.ancilla_aux_timer[i] = 2;
            vars.ancilla_item_to_link[i] +%= 1;
            if (vars.ancilla_item_to_link[i] == 9) {
                vars.ancilla_type[i] = 0;
                return;
            } else if (vars.ancilla_item_to_link[i] & 8 != 0) {
                vars.ancilla_aux_timer[i] = 0x80;
            }
        }
    }
    Arrow_Draw(k);
}

pub export fn Ancilla0B_IceRodShot(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        vars.ancilla_aux_timer[i] -%= 1;
        if (sign8(vars.ancilla_aux_timer[i])) {
            vars.ancilla_item_to_link[i] +%= 1;
            if (vars.ancilla_item_to_link[i] & 0xfe != 0) {
                vars.ancilla_step[i] = 1;
                vars.ancilla_item_to_link[i] = (vars.ancilla_item_to_link[i] & 7) | 4;
            }
            vars.ancilla_aux_timer[i] = 3;
        }
        if (vars.ancilla_step[i] != 0) {
            var info: AncillaOamInfo = undefined;
            if (Ancilla_ReturnIfOutsideBounds(k, &info)) return;
            Ancilla_MoveY(k);
            Ancilla_MoveX(k);
            if (Ancilla_CheckSpriteCollision(k) >= 0 or Ancilla_CheckTileCollision(k) != 0) {
                vars.ancilla_type[i] = 0x11;
                vars.ancilla_numspr[i] = tables.kAncilla_Pflags[0x11];
                vars.ancilla_item_to_link[i] = 0;
                vars.ancilla_aux_timer[i] = 4;
            }
        }
    }
    AncillaAdd_IceRodSparkle(k);
}

pub export fn Ancilla11_IceRodWallHit(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.ancilla_aux_timer[i] -%= 1;
    if (sign8(vars.ancilla_aux_timer[i])) {
        vars.ancilla_aux_timer[i] = 7;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 2) {
            vars.ancilla_type[i] = 0;
            return;
        }
    }
    IceShotSpread_Draw(k);
}

pub export fn IceShotSpread_Draw(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    _ = Ancilla_AllocateOamFromRegion_A_or_D_or_F(k, vars.ancilla_numspr[i]);
    var oam = GetOamCurPtr();
    const first: usize = @as(usize, vars.ancilla_item_to_link[i]) * 4;
    for (first..first + 4) |j| {
        const y = pt.y +% signedOffset(@as(i8, @bitCast(tables.kIceShotSpread_XY[j * 2])));
        const x = pt.x +% signedOffset(@as(i8, @bitCast(tables.kIceShotSpread_XY[j * 2 + 1])));
        var y_value: u8 = 0xf0;
        if (x < 256 and y < 256) {
            oam[0].x = @truncate(x);
            if (y < 224) y_value = @truncate(y);
        }
        oam[0].y = y_value;
        oam[0].charnum = tables.kIceShotSpread_CharFlags[j * 2];
        oam[0].flags = (tables.kIceShotSpread_CharFlags[j * 2 + 1] & 0xcf) | hiPtr(vars.oam_priority_value).*;
        vars.bytewise_extended_oam[oamIndex(oam)] = 0;
        oam = Ancilla_AllocateOamFromCustomRegion(oam + 1);
    }
    oam = GetOamCurPtr();
    if (oam[0].y == 0xf0 and oam[1].y == 0xf0) vars.ancilla_type[i] = 0;
}

pub export fn AncillaDraw_Explosion(start: [*]align(1) OamEnt, frame: c_int, idx: c_int, idx_end: c_int, palette: u8, x: c_int, y: c_int) callconv(.c) [*]align(1) OamEnt {
    var oam = start;
    var f: usize = @intCast(frame);
    var index = idx;
    while (true) {
        if (tables.kBomb_DrawExplosion_CharFlags[f * 2] != 0xff) {
            const i: usize = @intCast(index + frame);
            Ancilla_SetOam_Safe(oam, lowWord(x) +% signedOffset(tables.kBomb_DrawExplosion_XY[i * 2 + 1]), lowWord(y) +% signedOffset(tables.kBomb_DrawExplosion_XY[i * 2]), tables.kBomb_DrawExplosion_CharFlags[f * 2], (tables.kBomb_DrawExplosion_CharFlags[f * 2 + 1] & 0xc1) | hiPtr(vars.oam_priority_value).* | palette, tables.kBomb_DrawExplosion_Ext[f]);
            oam += 1;
        }
        f += 1;
        index += 1;
        if (index == idx_end) break;
    }
    return oam;
}

pub export fn Sprite_CreateDeflectedArrow(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.ancilla_type[i] = 0;
    var info: SpriteSpawnInfo = undefined;
    const slot = sprite.Sprite_SpawnDynamically(k, 0x1b, &info);
    if (slot < 0) return;
    const j: usize = @intCast(slot);
    vars.sprite_x_lo[j] = vars.ancilla_x_lo[i];
    vars.sprite_x_hi[j] = vars.ancilla_x_hi[i];
    vars.sprite_y_lo[j] = vars.ancilla_y_lo[i];
    vars.sprite_y_hi[j] = vars.ancilla_y_hi[i];
    vars.sprite_state[j] = 6;
    vars.sprite_delay_main[j] = 31;
    vars.sprite_x_vel[j] = vars.ancilla_x_vel[i];
    vars.sprite_y_vel[j] = vars.ancilla_y_vel[i];
    vars.sprite_floor[j] = vars.link_is_on_lower_level.*;
    sprite.Sprite_PlaceWeaponTink(slot);
}

pub export fn Ancilla16_HitStars(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    vars.ancilla_arr3[i] -%= 1;
    if (!sign8(vars.ancilla_arr3[i])) return;
    vars.ancilla_arr3[i] = 0;
    if (vars.submodule_index.* == 0) {
        vars.ancilla_aux_timer[i] -%= 1;
        if (sign8(vars.ancilla_aux_timer[i])) {
            vars.ancilla_aux_timer[i] = 0;
            vars.ancilla_item_to_link[i] = 1;
        }
        if (vars.ancilla_item_to_link[i] != 0) {
            vars.ancilla_y_vel[i] -%= 4;
            vars.ancilla_x_vel[i] = vars.ancilla_y_vel[i];
            if (vars.ancilla_y_vel[i] < 232) {
                vars.ancilla_type[i] = 0;
                return;
            }
            Ancilla_MoveY(k);
            Ancilla_MoveX(k);
        }
    }
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    const center = (@as(u16, vars.ancilla_B[i]) << 8) | vars.ancilla_A[i];
    const mirrored = center *% 2 -% Ancilla_GetX(k) -% 8 -% vars.BG2HOFS_copy2.*;
    if (vars.ancilla_step[i] == 2) Ancilla_AllocateOamFromRegion_B_or_E(8);
    var oam = GetOamCurPtr();
    for (0..2) |n| {
        Ancilla_SetOam(oam, pt.x, pt.y, tables.kAncilla_HitStars_Char[vars.ancilla_item_to_link[i]], hiPtr(vars.oam_priority_value).* | 4 | @as(u8, if (n == 0) 0 else 0x40), 0);
        // Only the low byte changes in the original BYTE(x) assignment.
        pt.x = (pt.x & 0xff00) | (mirrored & 0xff);
        oam = HitStars_UpdateOamBufferPosition(oam + 1);
    }
}

pub export fn Ancilla17_ShovelDirt(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    if (vars.ancilla_timer[i] == 0) {
        vars.ancilla_timer[i] = 8;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 2) {
            vars.ancilla_type[i] = 0;
            return;
        }
    }
    const frame = vars.ancilla_item_to_link[i];
    const j = @as(usize, frame) + @as(usize, if (vars.link_direction_facing.* == 4) 0 else 2);
    pt.x +%= signedOffset(tables.kShovelDirt_XY[j * 2 + 1]);
    pt.y +%= signedOffset(tables.kShovelDirt_XY[j * 2]);
    for (0..2) |n| {
        Ancilla_SetOam(oam, pt.x +% @as(u16, @intCast(n * 8)), pt.y, @as(u8, @bitCast(tables.kShovelDirt_Char[frame])) +% @as(u8, @intCast(n)), 4 | hiPtr(vars.oam_priority_value).*, 0);
        oam = Ancilla_AllocateOamFromCustomRegion(oam + 1);
    }
}

pub export fn Ancilla1A_PowderDust(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        Powder_ApplyDamageToSprites(k);
        vars.ancilla_aux_timer[i] -%= 1;
        if (sign8(vars.ancilla_aux_timer[i])) {
            vars.ancilla_aux_timer[i] = 1;
            if (vars.ancilla_item_to_link[i] == 9) {
                vars.ancilla_type[i] = 0;
                vars.byte_7E0333.* = 0;
                return;
            }
            vars.ancilla_item_to_link[i] +%= 1;
            vars.ancilla_arr25[i] = tables.kMagicPowder_Tab0[@as(usize, vars.ancilla_item_to_link[i]) + @as(usize, vars.ancilla_dir[i]) * 10];
        }
    }
    Ancilla_AllocateOamFromRegion_B_or_E(vars.ancilla_numspr[i]);
    Ancilla_MagicPowder_Draw(k);
}

pub export fn Ancilla_MagicPowder_Draw(k: c_int) callconv(.c) void {
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    const oam = GetOamCurPtr();
    const frame = vars.ancilla_arr25[@intCast(k)];
    for (0..4) |i| {
        const j = @as(usize, frame) * 4 + i;
        Ancilla_SetOam(oam + i, pt.x +% signedOffset(tables.kMagicPowder_DrawX[j]), pt.y +% signedOffset(tables.kMagicPowder_DrawY[j]), tables.kMagicPowder_Draw_Char[frame], (tables.kMagicPowder_Draw_Flags[j] & 0xcf) | hiPtr(vars.oam_priority_value).*, 0);
    }
}

pub export fn Powder_ApplyDamageToSprites(k: c_int) callconv(.c) void {
    var j: c_int = 15;
    while (j >= 0) : (j -= 1) {
        const i: usize = @intCast(j);
        if ((vars.frame_counter.* ^ @as(u8, @intCast(j))) & 3 != 0 or vars.sprite_state[i] != 9 or vars.sprite_bump_damage[i] & 0x20 != 0) continue;
        var hb: SpriteHitBox = undefined;
        Ancilla_SetupBasicHitBox(k, &hb);
        sprite.Sprite_SetupHitBox(j, &hb);
        if (!sprite.CheckIfHitBoxesOverlap(&hb)) continue;
        // The C assignments in this condition deliberately reuse the byte.
        var value = vars.sprite_type[i];
        const special = blk: {
            if (value != 0xb) break :blk false;
            value = vars.player_is_indoors.*;
            if (value == 0) break :blk false;
            value = @truncate(vars.dungeon_room_index2.* -% 1);
            break :blk value == 0;
        };
        if (!special) {
            if (value != 0xd) {
                sprite.Ancilla_CheckDamageToSprite_preset(j, 10);
                continue;
            }
            if (vars.sprite_head_dir[i] != 0) continue;
        }
        vars.sprite_head_dir[i] = 1;
        Sprite_SpawnPoofGarnish(j);
    }
}

pub export fn DashDust_Motive(k: c_int) callconv(.c) void {
    const i: usize = @intCast(k);
    if (vars.ancilla_timer[i] == 0) {
        vars.ancilla_timer[i] = 3;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 3) {
            vars.ancilla_type[i] = 0;
            return;
        }
    }
    if (vars.link_direction_facing.* == 2) _ = sprite.Oam_AllocateFromRegionB(4);
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    Ancilla_SetOam(GetOamCurPtr(), pt.x, pt.y, tables.kMotiveDashDust_Draw_Char[vars.ancilla_item_to_link[i]], 4 | hiPtr(vars.oam_priority_value).*, 0);
}

pub export fn AncillaAdd_DashDust(atype: u8, limit: u8) callconv(.c) void {
    AddDashingDustEx(atype, limit, 1);
}

pub export fn AncillaAdd_DashDust_charging(atype: u8, limit: u8) callconv(.c) void {
    AddDashingDustEx(atype, limit, 0);
}

pub export fn AncillaAdd_DoorDebris() callconv(.c) c_int {
    const k = Ancilla_AddAncilla(8, 1);
    if (k >= 0) {
        vars.ancilla_arr25[@intCast(k)] = 0;
        vars.ancilla_arr26[@intCast(k)] = 7;
    }
    return k;
}

pub export fn AncillaAdd_WaterfallSplash() callconv(.c) void {
    if (AncillaAdd_CheckForPresence(0x41)) return;
    const k = Ancilla_AddAncilla(0x41, 4);
    if (k >= 0) {
        vars.ancilla_timer[@intCast(k)] = 2;
        vars.ancilla_item_to_link[@intCast(k)] = 0;
    }
}

pub export fn AncillaAdd_ChargedSpinAttackSparkle() callconv(.c) void {
    var k: usize = 10;
    while (k != 0) {
        k -= 1;
        if (vars.ancilla_type[k] == 0 or vars.ancilla_type[k] == 0x3c) {
            vars.ancilla_type[k] = 13;
            vars.ancilla_floor[k] = vars.link_is_on_lower_level.*;
            vars.ancilla_timer[k] = 6;
            return;
        }
    }
}

pub export fn AncillaAdd_LampFlame(atype: u8, limit: u8) callconv(.c) void {
    const slot = Ancilla_AddAncilla(atype, limit);
    if (slot < 0) return;
    const k: usize = @intCast(slot);
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_aux_timer[k] = 0;
    vars.ancilla_timer[k] = 23;
    const dir = vars.link_direction_facing.* >> 1;
    vars.ancilla_dir[k] = dir;
    Ancilla_SetXY(slot, vars.link_x_coord.* +% signedOffset(tables.kLampFlame_X[dir]), vars.link_y_coord.* +% signedOffset(tables.kLampFlame_Y[dir]));
    vars.sound_effect_1.* = Ancilla_CalculateSfxPan(slot) | 42;
}

pub export fn AncillaAdd_MSCutscene(atype: u8, limit: u8) callconv(.c) void {
    const slot = Ancilla_AddAncilla(atype, limit);
    if (slot < 0) return;
    const k: usize = @intCast(slot);
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_aux_timer[k] = 2;
    vars.ancilla_timer[k] = 64;
    Ancilla_SetXY(slot, vars.link_x_coord.* +% 8, vars.link_y_coord.* -% 8);
}

pub export fn AncillaAdd_BushPoof(x: u16, y: u16) callconv(.c) void {
    if (vars.link_item_in_hand.* & 0x40 == 0) return;
    const slot = Ancilla_AddAncilla(0x3f, 4);
    if (slot < 0) return;
    const k: usize = @intCast(slot);
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_timer[k] = 7;
    vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | 21;
    Ancilla_SetXY(slot, x, y -% 2);
}

test "ancilla allocation enforces limits and replaces only expendable slots" {
    @memset(&rtl.g_ram, 0);
    @memset(vars.ancilla_type[0..6], 0x2c);
    vars.ancilla_type[3] = 0x3c;
    vars.ancilla_alloc_rotate.* = 4;
    try std.testing.expectEqual(@as(c_int, 3), Ancilla_AllocInit(9, 4));
    vars.ancilla_type[3] = 9;
    try std.testing.expectEqual(@as(c_int, -1), Ancilla_AllocInit(9, 0));
    try std.testing.expectEqual(@as(c_int, -1), Ancilla_AllocInit(9, 4));
    vars.ancilla_type[4] = 0;
    vars.link_is_on_lower_level.* = 1;
    vars.link_is_on_lower_level_mirror.* = 2;
    try std.testing.expectEqual(@as(c_int, 4), Ancilla_AddAncilla(9, 4));
    try std.testing.expectEqual(@as(u8, 1), vars.ancilla_floor[4]);
    try std.testing.expectEqual(@as(u8, 2), vars.ancilla_floor2[4]);
    try std.testing.expectEqual(@as(u8, 8), vars.ancilla_numspr[4]);
}

test "ancilla movement carries fractions and wraps world coordinates" {
    @memset(&rtl.g_ram, 0);
    Ancilla_SetXY(0, 0, 0xffff);
    vars.ancilla_x_vel[0] = 0xff; // -1/16 pixel per frame
    vars.ancilla_y_vel[0] = 16;
    Ancilla_MoveX(0);
    Ancilla_MoveY(0);
    try std.testing.expectEqual(@as(u16, 0xffff), Ancilla_GetX(0));
    try std.testing.expectEqual(@as(u8, 0xf0), vars.ancilla_x_subpixel[0]);
    try std.testing.expectEqual(@as(u16, 0), Ancilla_GetY(0));
    vars.ancilla_z_vel[0] = 0x80;
    Ancilla_MoveZ(0);
    try std.testing.expectEqual(@as(u8, 0xf8), vars.ancilla_z[0]);
}

test "custom OAM regions wrap at the sorted and unsorted boundaries" {
    @memset(&rtl.g_ram, 0);
    const cases = [_]struct { sorted: u8, input: u16, expected: u16 }{
        .{ .sorted = 0, .input = 0x98c, .expected = 0x98c },
        .{ .sorted = 0, .input = 0x990, .expected = 0x820 },
        .{ .sorted = 1, .input = 0x8dc, .expected = 0x8dc },
        .{ .sorted = 1, .input = 0x8e0, .expected = 0x820 },
        .{ .sorted = 1, .input = 0x9cc, .expected = 0x9cc },
        .{ .sorted = 1, .input = 0x9d0, .expected = 0x940 },
    };
    for (cases) |case| {
        vars.sort_sprites_setting.* = case.sorted;
        const ptr: [*]align(1) OamEnt = @ptrCast(&rtl.g_ram[case.input]);
        const result = Ancilla_AllocateOamFromCustomRegion(ptr);
        try std.testing.expectEqual(@as(usize, case.expected), @intFromPtr(result) - @intFromPtr(&rtl.g_ram));
        if (case.input != case.expected) {
            try std.testing.expectEqual(case.expected, vars.oam_cur_ptr.*);
            try std.testing.expectEqual((case.expected - 0x800) / 4 + 0xa20, vars.oam_ext_cur_ptr.*);
        }
    }
}

test "deflected arrows use the cleared type in the collision result" {
    @memset(&rtl.g_ram, 0);
    Ancilla_SetXY(0, 100, 100);
    sprite.Sprite_SetX(1, 100);
    sprite.Sprite_SetY(1, 100);
    vars.ancilla_type[0] = 9;
    vars.sprite_type[1] = 0x1b;
    vars.sprite_state[1] = 9;
    vars.sprite_flags[1] = 8;
    vars.sprite_health[1] = 100;
    vars.link_item_bow.* = 2;
    try std.testing.expect(Ancilla_CheckSpriteCollision_Single(0, 1));
    try std.testing.expectEqual(@as(u8, 0), vars.ancilla_type[0]);
    try std.testing.expectEqual(@as(u8, 0), vars.sprite_unk2[1]);
    try std.testing.expectEqual(@as(u8, 3), vars.sprite_alert_flag.*);
}

test "wall arrows expire after their final hold frame" {
    @memset(&rtl.g_ram, 0);
    vars.ancilla_type[0] = 10;
    vars.ancilla_S[0] = 255;
    vars.ancilla_aux_timer[0] = 1;
    vars.ancilla_item_to_link[0] = 8;
    Ancilla0A_ArrowInTheWall(0);
    try std.testing.expectEqual(@as(u8, 0), vars.ancilla_type[0]);
    try std.testing.expectEqual(@as(u8, 9), vars.ancilla_item_to_link[0]);
}

test "ice rod wall-hit animation terminates at frame two" {
    @memset(&rtl.g_ram, 0);
    vars.ancilla_type[0] = 0x11;
    vars.ancilla_item_to_link[0] = 1;
    Ancilla11_IceRodWallHit(0);
    try std.testing.expectEqual(@as(u8, 0), vars.ancilla_type[0]);
    try std.testing.expectEqual(@as(u8, 7), vars.ancilla_aux_timer[0]);
}

fn expired(timer: *u8) bool {
    timer.* -%= 1;
    return sign8(timer.*);
}
fn inc(value: *u8) u8 {
    value.* +%= 1;
    return value.*;
}
fn radialX(p: AncillaRadialProjection) u16 {
    return if (p.r6 != 0) 0 -% @as(u16, p.r4) else p.r4;
}
fn radialY(p: AncillaRadialProjection) u16 {
    return if (p.r2 != 0) 0 -% @as(u16, p.r0) else p.r0;
}
fn allocateAD(size: u8) void {
    _ = if (vars.sort_sprites_setting.* != 0) sprite.Oam_AllocateFromRegionD(size) else sprite.Oam_AllocateFromRegionA(size);
}
fn finishMedallion(k: usize, receiving: u8) void {
    vars.ancilla_type[k] = 0;
    vars.load_chr_halfslot_even_odd.* = 1;
    vars.byte_7E0324.* = 0;
    vars.state_for_spin_attack.* = 0;
    vars.step_counter_for_spin_attack.* = 0;
    vars.link_cant_change_direction.* = 0;
    vars.flag_unk1.* = 0;
    if (vars.link_player_handler_state.* != receiving) {
        vars.link_player_handler_state.* = 0;
        vars.link_delay_timer_spin_attack.* = 0;
        vars.button_mask_b_y.* = if (vars.button_b_frames.* != 0) vars.joypad1H_last.* & 0x80 else 0;
    }
    vars.link_speed_setting.* = 0;
    vars.byte_7E0325.* = 0;
}

pub export fn Ancilla33_BlastWallExplosion(k: c_int) callconv(.c) void {
    var u: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        if (vars.blastwall_var5[u] != 0) {
            vars.blastwall_var6[u] -%= 1;
            if (vars.blastwall_var6[u] == 0) {
                const frame = inc(&vars.blastwall_var5[u]);
                if (frame != 0 and frame < 9) AncillaAdd_BlastWallFireball(0x32, 10, @intCast(u * 4));
                if (frame == 11) {
                    vars.blastwall_var5[u] = 0;
                    vars.blastwall_var6[u] = 0;
                } else vars.blastwall_var6[u] = 3;
            }
        } else {
            u ^= 1;
            if (vars.blastwall_var5[u] == 6 and vars.blastwall_var6[u] == 2 and vars.ancilla_item_to_link[0] +% 1 < 7) {
                vars.ancilla_item_to_link[0] +%= 1;
                vars.blastwall_var5[u] = 1;
                vars.blastwall_var6[u] = 3;
                var i: usize = 4;
                while (i != 0) {
                    i -= 1;
                    const delta: u16 = signedOffset(if (i & 2 != 0) -13 else 13);
                    const j = u * 4 + i;
                    if (vars.blastwall_var7.* < 4) vars.blastwall_var11[j] +%= delta else vars.blastwall_var10[j] +%= delta;
                    const x = vars.blastwall_var11[j] -% vars.BG2HOFS_copy2.*;
                    if (x < 256) vars.sound_effect_1.* = tables.kBombos_Sfx[x >> 5] | 0xc;
                }
            }
        }
    }
    if (vars.blastwall_var5[vars.ancilla_K[0]] != 0) {
        var i: usize = if (vars.ancilla_K[0] == 1) 8 else 4;
        const end = i - 4;
        while (i != end) {
            i -= 1;
            AncillaDraw_BlastWallBlast(vars.ancilla_K[0], vars.blastwall_var11[i], vars.blastwall_var10[i]);
        }
    }
    if (vars.ancilla_item_to_link[0] == 6 and vars.blastwall_var5[0] == 0 and vars.blastwall_var5[1] == 0) {
        vars.ancilla_type[0] = 0;
        vars.ancilla_type[1] = 0;
        vars.flag_custom_spell_anim_active.* = 0;
    }
}
pub export fn AncillaDraw_BlastWallBlast(k: c_int, x: c_int, y: c_int) callconv(.c) void {
    vars.oam_priority_value.* = 0x3000;
    allocateAD(0x18);
    const i = vars.blastwall_var5[@intCast(k)];
    _ = AncillaDraw_Explosion(GetOamCurPtr(), @as(c_int, tables.kBomb_Draw_Tab0[i]) * 6, 0, tables.kBomb_Draw_Tab2[i], 0x32, x - vars.BG2HOFS_copy2.*, y - vars.BG2VOFS_copy2.*);
}
pub export fn Ancilla15_JumpSplash(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        if (expired(&vars.ancilla_aux_timer[u])) {
            vars.ancilla_aux_timer[u] = 0;
            vars.ancilla_item_to_link[u] = 1;
        }
        if (vars.ancilla_item_to_link[u] != 0) {
            vars.ancilla_y_vel[u] -%= 4;
            vars.ancilla_x_vel[u] = vars.ancilla_y_vel[u];
            if (vars.ancilla_y_vel[u] < 232) {
                vars.ancilla_type[u] = 0;
                if ((vars.link_is_bunny_mirror.* != 0 or vars.link_player_handler_state.* == 4) and vars.link_is_in_deep_water.* != 0) player.CheckAbilityToSwim();
                return;
            }
            Ancilla_MoveX(k);
            Ancilla_MoveY(k);
        }
    }
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    const ax = Ancilla_GetX(k);
    const mirror = vars.link_x_coord.* *% 2 -% ax -% vars.BG2HOFS_copy2.*;
    const j = vars.ancilla_item_to_link[u];
    for (0..2) |i| {
        Ancilla_SetOam(oam, pt.x, pt.y, tables.kAncilla_JumpSplash_Char[j], if (i == 0) 0x24 else 0x64, 2);
        oam = Ancilla_AllocateOamFromCustomRegion(oam + 1);
        pt.x = mirror;
    }
    Ancilla_SetOam(oam, ax +% 12 -% vars.BG2HOFS_copy2.*, pt.y, 0xc0, 0x24, if (j == 1) 1 else 2);
}
pub export fn Ancilla32_BlastWallFireball(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        vars.ancilla_item_to_link[u] +%= 2;
        vars.ancilla_y_vel[u] +%= vars.ancilla_item_to_link[u];
        Ancilla_MoveY(k);
        Ancilla_MoveX(k);
        if (expired(&vars.blastwall_var12[u])) {
            vars.ancilla_type[u] = 0;
            return;
        }
    }
    allocateAD(4);
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    const frame: usize = if (vars.blastwall_var12[u] & 8 != 0) 0 else if (vars.blastwall_var12[u] & 4 != 0) 1 else 2;
    Ancilla_SetOam(GetOamCurPtr(), pt.x, pt.y, tables.kBlastWallFireball_Char[frame], 0x22, 0);
}
pub export fn Ancilla18_EtherSpell(k: c_int) callconv(.c) void {
    if (vars.submodule_index.* != 0) return;
    const u: usize = @intCast(k);
    if (vars.ancilla_step[u] != 0) {
        const flash = if (vars.step_counter_for_spin_attack.* == 0) inc(&vars.ancilla_arr4[u]) & 4 == 0 else vars.step_counter_for_spin_attack.* == 11;
        if (flash) {
            load_gfx.Palette_ElectroThemedGear();
            load_gfx.Filter_Majorly_Whiten_Bg();
        } else {
            load_gfx.LoadActualGearPalettes();
            load_gfx.Palette_Restore_BG_From_Flash();
        }
    }
    if (vars.ancilla_step[u] == 2) {
        if (expired(&vars.ancilla_aux_timer[u])) {
            vars.ancilla_aux_timer[u] = 2;
            if (inc(&vars.ancilla_item_to_link[u]) == 2) {
                vars.ancilla_item_to_link[u] -%= 1;
                vars.ancilla_x_vel[u] = 16;
                vars.ancilla_step[u] = 3;
            }
        }
        vars.ancilla_x_vel[u] +%= 1;
        EtherSpell_HandleRadialSpin(k);
        return;
    }
    if (expired(&vars.ancilla_aux_timer[u])) {
        vars.ancilla_aux_timer[u] = 2;
        vars.ancilla_item_to_link[u] ^= 1;
    }
    switch (vars.ancilla_step[u]) {
        0 => EtherSpell_HandleLightningStroke(k),
        1 => EtherSpell_HandleOrbPulse(k),
        3 => EtherSpell_HandleRadialSpin(k),
        4 => {
            ether_var1().* -%= 1;
            if (ether_var1().* == 0) vars.ancilla_step[u] = 5;
            EtherSpell_HandleRadialSpin(k);
        },
        else => {
            const vel = vars.ancilla_x_vel[u] +% 0x10;
            vars.ancilla_x_vel[u] = if (sign8(vel)) 0x7f else vel;
            EtherSpell_HandleRadialSpin(k);
        },
    }
}
pub export fn EtherSpell_HandleLightningStroke(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    Ancilla_MoveY(k);
    const y = Ancilla_GetY(k);
    if (loPtr(ether_y_adjusted()).* != y & 0xf0) {
        loPtr(ether_y_adjusted()).* = @truncate(y & 0xf0);
        vars.ancilla_arr25[u] +%= 1;
    }
    if (y < 0xe000 and ether_y2().* < 0xe000 and ether_y2().* <= y) vars.ancilla_step[u] = 1;
    AncillaDraw_EtherBlitz(k);
}
pub export fn EtherSpell_HandleOrbPulse(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (!sign8(vars.ancilla_arr25[u])) {
        if (!expired(&vars.ancilla_arr3[u])) return AncillaDraw_EtherBlitz(k);
        vars.ancilla_arr3[u] = 3;
        if (!expired(&vars.ancilla_arr25[u])) return AncillaDraw_EtherBlitz(k);
        vars.ancilla_arr3[u] = 9;
    }
    if (expired(&vars.ancilla_arr3[u])) {
        vars.ancilla_step[u] = 2;
        vars.ancilla_y_vel[u] = 0;
        vars.ancilla_x_vel[u] = 16;
        vars.ancilla_item_to_link[u] = 0;
        vars.ancilla_aux_timer[u] = 2;
        if (vars.step_counter_for_spin_attack.* != 0) Medallion_CheckSpriteDamage(k);
    }
    AncillaDraw_EtherOrb(k, GetOamCurPtr());
}
pub export fn EtherSpell_HandleRadialSpin(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.ancilla_step[u] == 4) {
        switch (vars.frame_counter.* & 7) {
            0 => vars.sound_effect_2.* = 0x2a,
            4 => vars.sound_effect_2.* = 0xaa,
            7 => vars.sound_effect_2.* = 0x6a,
            else => {},
        }
    } else {
        vars.ancilla_x_lo[u] = ether_var2().*;
        vars.ancilla_x_hi[u] = 0;
        Ancilla_MoveX(k);
        ether_var2().* = vars.ancilla_x_lo[u];
        if (ether_var2().* == 0x40) vars.ancilla_step[u] = 4;
    }
    const step = vars.ancilla_step[u];
    const frame = vars.ancilla_item_to_link[u];
    var oam = GetOamCurPtr();
    var i: usize = 8;
    while (i != 0) {
        i -= 1;
        if (step != 2 and step != 5) ether_arr1()[i] = (ether_arr1()[i] +% 1) & 0x3f;
        const p = Ancilla_GetRadialProjection(ether_arr1()[i], ether_var2().*);
        oam = if (step != 2) AncillaDraw_EtherBlitzBall(oam, &p, frame) else AncillaDraw_EtherBlitzSegment(oam, &p, frame, @intCast(i));
    }
    if (ether_var2().* < 0xf0) {
        const start = GetOamCurPtr();
        for (0..8) |j| {
            if (start[j].y != 0xf0) return;
        }
    }
    finishMedallion(u, 25);
    if (loPtr(vars.overworld_screen_index).* == 0x70 and vars.save_ow_event_info[0x70] & 0x20 == 0 and Ancilla_CheckForEntranceTrigger(2)) {
        vars.trigger_special_entrance.* = 3;
        vars.subsubmodule_index.* = 0;
        loPtr(vars.R16).* = 0;
    }
    load_gfx.LoadActualGearPalettes();
    load_gfx.Palette_Restore_BG_And_HUD();
}
pub export fn AncillaDraw_EtherBlitzBall(oam: [*]align(1) OamEnt, p: *const AncillaRadialProjection, s: c_int) callconv(.c) [*]align(1) OamEnt {
    Ancilla_SetOam(oam, radialX(p.*) +% ether_x2().* -% 8 -% vars.BG2HOFS_copy2.*, radialY(p.*) +% ether_y3().* -% 8 -% vars.BG2VOFS_copy2.*, tables.kEther_BlitzBall_Char[@intCast(s)], 0x3c, 2);
    return Ancilla_AllocateOamFromCustomRegion(oam + 1);
}
pub export fn AncillaDraw_EtherBlitzSegment(oam: [*]align(1) OamEnt, p: *const AncillaRadialProjection, s: c_int, k: c_int) callconv(.c) [*]align(1) OamEnt {
    const t: usize = @intCast(s * 8 + k);
    const x = radialX(p.*) +% ether_x2().* -% vars.BG2HOFS_copy2.*;
    const y = radialY(p.*) +% ether_y3().* -% vars.BG2VOFS_copy2.*;
    Ancilla_SetOam(oam, x -% 8, y -% 8, tables.kEther_SpllittingBlitzSegment_Char[t * 2], tables.kEther_SpllittingBlitzSegment_Flags[t * 2], 2);
    Ancilla_SetOam(oam + 1, x +% signedOffset(tables.kEther_SpllittingBlitzSegment_X[t]), y +% signedOffset(tables.kEther_SpllittingBlitzSegment_Y[t]), tables.kEther_SpllittingBlitzSegment_Char[t * 2 + 1], tables.kEther_SpllittingBlitzSegment_Flags[t * 2 + 1], 2);
    return Ancilla_AllocateOamFromCustomRegion(oam + 2);
}
pub export fn AncillaDraw_EtherBlitz(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    for (0..@as(usize, vars.ancilla_arr25[u]) + 1) |i| {
        Ancilla_SetOam(oam, pt.x, pt.y, tables.kEther_BlitzSegment_Char[@as(usize, vars.ancilla_item_to_link[u]) * 2 + (i & 1)], tables.kEther_BlitzOrb_Flags[0] | hiPtr(vars.oam_priority_value).*, 2);
        pt.y -%= 16;
        oam += 1;
    }
    if (vars.ancilla_step[u] == 1) AncillaDraw_EtherOrb(k, oam);
}
pub export fn AncillaDraw_EtherOrb(k: c_int, start: [*]align(1) OamEnt) callconv(.c) void {
    var oam = start;
    var y = ether_y().* -% 1 -% vars.BG2VOFS_copy2.*;
    var x = ether_x().* -% 8 -% vars.BG2HOFS_copy2.*;
    const t = @as(usize, vars.ancilla_item_to_link[@intCast(k)]) * 4;
    for (0..4) |i| {
        Ancilla_SetOam(oam, x, y, tables.kEther_BlitzOrb_Char[t + i], tables.kEther_BlitzOrb_Flags[t + i], 2);
        oam = Ancilla_AllocateOamFromCustomRegion(oam + 1);
        x +%= 16;
        if (i == 1) {
            x -%= 32;
            y +%= 16;
        }
    }
}

fn bombosPosition(j: usize, p: AncillaRadialProjection) u16 {
    const x = radialX(p) +% vars.bombos_x_coord2[0];
    const y = radialY(p) +% vars.bombos_y_coord2[0];
    vars.bombos_x_lo[j] = @truncate(x);
    vars.bombos_x_hi[j] = @truncate(x >> 8);
    vars.bombos_y_lo[j] = @truncate(y);
    vars.bombos_y_hi[j] = @truncate(y >> 8);
    return x;
}
pub export fn AncillaAdd_BombosSpell(a: u8, y: u8) callconv(.c) void {
    const k = AncillaAdd_AddAncilla_Bank08(a, y);
    if (k < 0) return;
    const u: usize = @intCast(k);
    @memset(bombos_arr2()[0..10], 0);
    @memset(bombos_arr1()[0..10], 3);
    @memset(vars.bombos_arr3[0..8], 0);
    @memset(vars.bombos_arr4[0..8], 3);
    vars.bombos_var4.* = 0;
    vars.bombos_var2.* = 0;
    vars.bombos_var3.* = 0x80;
    vars.bombos_arr7[0] = 0x10;
    vars.load_chr_halfslot_even_odd.* = 11;
    vars.flag_custom_spell_anim_active.* = 1;
    vars.ancilla_step[u] = 0;
    vars.ancilla_item_to_link[u] = 0;
    _ = misc.Ancilla_Sfx2_Near(0x2a);
    var t = kGeneratedBombosArr()[vars.frame_counter.*];
    if (t >= 0xe0) t &= 0x7f;
    vars.bombos_x_coord[0] = (vars.link_x_coord.* & 0xff00) | t;
    vars.bombos_y_coord[0] = (vars.link_y_coord.* & 0xff00) | t;
    vars.bombos_x_coord2[0] = vars.link_x_coord.* -% 16;
    vars.bombos_y_coord2[0] = vars.link_y_coord.* +% 16;
    vars.bombos_var1.* = 16;
    _ = bombosPosition(0, Ancilla_GetRadialProjection(vars.bombos_arr7[0], 16));
}
pub export fn Ancilla19_BombosSpell(k: c_int) callconv(.c) void {
    const phase = vars.bombos_var4.*;
    if (vars.submodule_index.* == 0) {
        if (phase == 0) BombosSpell_ControlFireColumns(k) else if (phase != 2) BombosSpell_FinishFireColumns(k) else BombosSpell_ControlBlasting(k);
        return;
    }
    var n: usize = if (phase == 2) @as(usize, vars.ancilla_step[@intCast(k)]) + 1 else 10;
    while (n != 0) {
        n -= 1;
        if (phase == 2) AncillaDraw_BombosBlast(@intCast(n)) else AncillaDraw_BombosFireColumn(@intCast(n));
    }
}
pub export fn BombosSpell_ControlFireColumns(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    const sa = vars.ancilla_item_to_link[u];
    var sb = vars.ancilla_step[u];
    var i: usize = @as(usize, sb) + 1;
    while (i != 0) {
        i -= 1;
        if (bombos_arr2()[i] == 13) continue;
        if (expired(&bombos_arr1()[i])) {
            bombos_arr1()[i] = 3;
            if (inc(&bombos_arr2()[i]) == 13) continue;
            if (bombos_arr2()[i] == 2) {
                if (sa != 0) continue;
                const j: usize = slot: {
                    if (sb == 9) {
                        var n: usize = 10;
                        while (n != 0) {
                            n -= 1;
                            if (bombos_arr2()[n] == 13) {
                                bombos_arr2()[n] = 0;
                                break :slot n;
                            }
                        }
                    }
                    sb = if (sb +% 1 != 10) sb +% 1 else 9;
                    break :slot sb;
                };
                vars.bombos_var1.* = @intCast(@min(@as(u16, vars.bombos_var1.*) + 3, 207));
                vars.bombos_arr7[0] +%= 6;
                const x = bombosPosition(j, Ancilla_GetRadialProjection(vars.bombos_arr7[0] & 0x3f, vars.bombos_var1.*));
                const t = x -% vars.BG2HOFS_copy2.* +% 8;
                if (t < 256) vars.sound_effect_1.* = tables.kBombos_Sfx[t >> 5] | 0x2a;
            }
        }
        AncillaDraw_BombosFireColumn(@intCast(i));
    }
    if (vars.bombos_arr7[0] >= 0x80) vars.bombos_var4.* = 1;
    vars.ancilla_step[u] = sb;
}
pub export fn BombosSpell_FinishFireColumns(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    var i: usize = @as(usize, vars.ancilla_step[u]) + 1;
    while (i != 0) {
        i -= 1;
        if (expired(&bombos_arr1()[i])) {
            bombos_arr1()[i] = 3;
            if (inc(&bombos_arr2()[i]) >= 13) bombos_arr2()[i] = 13;
        }
        AncillaDraw_BombosFireColumn(@intCast(i));
    }
    for (0..10) |j| {
        if (bombos_arr2()[j] != 13) return;
    }
    vars.bombos_var4.* = 2;
    Medallion_CheckSpriteDamage(k);
    vars.ancilla_step[u] = 0;
}
pub export fn AncillaDraw_BombosFireColumn(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    _ = Ancilla_AllocateOamFromRegion_A_or_D_or_F(k, 0x10);
    var oam = GetOamCurPtr();
    const frame = bombos_arr2()[u];
    if (frame == 13) return;
    var j: usize = @as(usize, frame) * 3 + 3;
    const end = j - 3;
    while (j != end) {
        j -= 1;
        if (tables.kBombosSpell_FireColumn_Char[j] != 0xff) {
            const x = (@as(u16, vars.bombos_x_hi[u]) << 8 | vars.bombos_x_lo[u]) +% signedOffset(tables.kBombosSpell_FireColumn_X[j]) -% vars.BG2HOFS_copy2.*;
            const y = (@as(u16, vars.bombos_y_hi[u]) << 8 | vars.bombos_y_lo[u]) +% signedOffset(tables.kBombosSpell_FireColumn_Y[j]) -% vars.BG2VOFS_copy2.*;
            Ancilla_SetOam(oam, x, y, tables.kBombosSpell_FireColumn_Char[j], tables.kBombosSpell_FireColumn_Flags[j], 2);
            oam += 1;
        }
        oam = Ancilla_AllocateOamFromCustomRegion(oam);
    }
}
pub export fn BombosSpell_ControlBlasting(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    var sb = vars.ancilla_step[u];
    var i: usize = @as(usize, sb) + 1;
    while (i != 0) {
        i -= 1;
        if (vars.bombos_arr3[i] != 8 and expired(&vars.bombos_arr4[i])) {
            vars.bombos_arr4[i] = 3;
            if (inc(&vars.bombos_arr3[i]) == 1 and vars.bombos_var2.* == 0) {
                var j: c_int = sb;
                if (j != 15) {
                    sb +%= 1;
                    j = sb;
                } else {
                    while (j >= 0 and vars.bombos_arr3[@intCast(j)] != 8) : (j -= 1) {}
                }
                const n: usize = @intCast(j);
                vars.bombos_arr3[n] = 0;
                vars.bombos_arr4[n] = 3;
                vars.bombos_y_coord[n] = tables.kBombosBlasts_Tab[vars.frame_counter.* & 0x3f] +% vars.BG2VOFS_copy2.*;
                vars.bombos_x_coord[n] = tables.kBombosBlasts_Tab[@as(usize, vars.frame_counter.* & 0x3f) + 3] +% vars.BG2HOFS_copy2.*;
                vars.sound_effect_1.* = 0xc | tables.kBombos_Sfx[(vars.bombos_x_coord[n] >> 5) & 7];
            }
        }
        AncillaDraw_BombosBlast(@intCast(i));
    }
    const done = blk: {
        for (0..16) |j| {
            if (vars.bombos_arr3[j] != 8) break :blk false;
        }
        break :blk true;
    };
    if (done) finishMedallion(u, 26) else vars.ancilla_step[u] = sb;
    vars.bombos_var3.* -%= 1;
    if (vars.bombos_var3.* == 0) {
        vars.bombos_var2.* = 1;
        vars.bombos_var3.* = 1;
    }
}
pub export fn AncillaDraw_BombosBlast(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    const x = vars.bombos_x_coord[u];
    const y = vars.bombos_y_coord[u];
    const frame = vars.bombos_arr3[u];
    if (frame == 8) return;
    _ = Ancilla_AllocateOamFromRegion_A_or_D_or_F(k, 0x10);
    var oam = GetOamCurPtr();
    var t: usize = @as(usize, frame) * 4 + 4;
    const end = t - 4;
    while (t != end) {
        t -= 1;
        if (tables.kBombosSpell_DrawBlast_Char[t] != 0xff) {
            Ancilla_SetOam(oam, x +% signedOffset(tables.kBombosSpell_DrawBlast_X[t]) -% vars.BG2HOFS_copy2.*, y +% signedOffset(tables.kBombosSpell_DrawBlast_Y[t]) -% vars.BG2VOFS_copy2.*, tables.kBombosSpell_DrawBlast_Char[t], tables.kBombosSpell_DrawBlast_Flags[t], 2);
            oam += 1;
        }
        oam = Ancilla_AllocateOamFromCustomRegion(oam);
    }
}
pub export fn Ancilla1C_QuakeSpell(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.submodule_index.* != 0) {
        if (vars.quake_arr2[4] != tables.kQuake_Tab1[4]) AncillaDraw_QuakeInitialBolts(k);
        return;
    }
    if (vars.ancilla_step[u] != 2) {
        QuakeSpell_ShakeScreen(k);
        QuakeSpell_ControlBolts(k);
        QuakeSpell_SpreadBolts(k);
        return;
    }
    Medallion_CheckSpriteDamage(k);
    sprite.Prepare_ApplyRumbleToSprites();
    finishMedallion(u, 255);
    vars.bg1_x_offset.* = 0;
    vars.bg1_y_offset.* = 0;
    if (loPtr(vars.overworld_screen_index).* == 0x47 and vars.save_ow_event_info[0x47] & 0x20 == 0 and Ancilla_CheckForEntranceTrigger(3)) {
        vars.trigger_special_entrance.* = 4;
        vars.subsubmodule_index.* = 0;
        loPtr(vars.R16).* = 0;
    }
}
pub export fn QuakeSpell_ShakeScreen(k: c_int) callconv(.c) void {
    _ = k;
    vars.bg1_y_offset.* = vars.quake_var3.*;
    vars.quake_var3.* = 0 -% vars.quake_var3.*;
    vars.link_y_vel.* +%= @truncate(vars.bg1_y_offset.*);
}
pub export fn QuakeSpell_ControlBolts(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    vars.quake_var4.* = vars.ancilla_step[u];
    var j: usize = @as(usize, vars.quake_var5.*) + 1;
    while (j != 0) {
        j -= 1;
        if (vars.quake_arr2[j] == tables.kQuake_Tab1[j]) continue;
        if (expired(&vars.quake_arr1[j])) {
            vars.quake_arr1[j] = 1;
            if (inc(&vars.quake_arr2[j]) == tables.kQuake_Tab1[j]) continue;
            if (j == 0 and vars.quake_arr2[j] == 2) {
                _ = misc.Ancilla_Sfx2_Near(0xc);
                vars.quake_var5.* = 1;
            } else if (j == 1 and vars.quake_arr2[j] == 2) vars.quake_var5.* = 4 else if (j == 4 and vars.quake_arr2[j] == 7) vars.quake_var4.* = 1;
        }
        AncillaDraw_QuakeInitialBolts(@intCast(j));
    }
    vars.ancilla_step[u] = vars.quake_var4.*;
}
pub export fn AncillaDraw_QuakeInitialBolts(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    const t = @as(usize, vars.quake_arr2[u]) + tables.kQuakeDrawGroundBolts_Tab[u];
    var oam = GetOamCurPtr();
    for (kQuakeItems[tables.kQuakeItemPos[t]..tables.kQuakeItemPos[t + 1]]) |p| {
        const x = signedOffset(p.x) +% vars.quake_var2.* -% vars.BG2HOFS_copy2.*;
        const y = signedOffset(p.y) +% vars.quake_var1.* -% vars.BG2VOFS_copy2.*;
        var xv = oam[0].x;
        var yv: u8 = 0xf0;
        if (x < 256 and y < 256) {
            xv = @truncate(x);
            if (y < 0xf0) yv = @truncate(y);
        }
        SetOamPlain(oam, xv, yv, tables.kQuakeDrawGroundBolts_Char[p.f & 15], (p.f & 0xc0) | 0x3c, 2);
        oam += 1;
        vars.oam_cur_ptr.* +%= 4;
        vars.oam_ext_cur_ptr.* +%= 1;
    }
}
pub export fn QuakeSpell_SpreadBolts(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.ancilla_step[u] != 1) return;
    if (vars.ancilla_timer[u] == 0) {
        vars.ancilla_timer[u] = 2;
        if (inc(&vars.ancilla_item_to_link[u]) == 55) {
            vars.ancilla_step[u] = 2;
            return;
        }
    }
    const t = vars.ancilla_item_to_link[u];
    var oam = GetOamCurPtr();
    for (kQuakeItems2[tables.kQuakeItemPos2[t]..tables.kQuakeItemPos2[@as(usize, t) + 1]]) |p| {
        SetOamPlain(oam, @bitCast(p.x), @bitCast(p.y), tables.kQuakeDrawGroundBolts_Char[p.f & 15], (p.f & 0xc0) | 0x3c, (p.f >> 4) & 3);
        vars.oam_cur_ptr.* +%= 4;
        vars.oam_ext_cur_ptr.* +%= 1;
        oam = Ancilla_AllocateOamFromCustomRegion(oam + 1);
    }
}

pub export fn Ancilla1D_ScreenShake(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        if (expired(&vars.ancilla_item_to_link[u])) {
            vars.bg1_x_offset.* = 0;
            vars.bg1_y_offset.* = 0;
            vars.ancilla_type[u] = 0;
            return;
        }
        const offs = lowWord(DashTremor_TwiddleOffset(k));
        if (vars.ancilla_dir[u] == 0) {
            vars.bg1_x_offset.* = offs;
            vars.link_x_vel.* +%= @truncate(offs);
        } else {
            vars.bg1_y_offset.* = offs;
            vars.link_y_vel.* +%= @truncate(offs);
        }
    }
    vars.sprite_alert_flag.* = 3;
}
pub export fn DashTremor_TwiddleOffset(k: c_int) callconv(.c) c_int {
    const y = 0 -% Ancilla_GetY(k);
    Ancilla_SetY(k, y);
    if (vars.player_is_indoors.* != 0) return y;
    const vertical = vars.ancilla_dir[@intCast(k)] == 2;
    const start = (if (vertical) vars.ow_scroll_vars0.ystart else vars.ow_scroll_vars0.xstart) +% 1;
    const end = (if (vertical) vars.ow_scroll_vars0.yend else vars.ow_scroll_vars0.xend) -% 1;
    const a = y +% (if (vertical) vars.BG2VOFS_copy2.* else vars.BG2HOFS_copy2.*);
    return if (a <= start or a >= end) 0 else y;
}
pub export fn Ancilla1E_DashDust(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.ancilla_step[u] != 0) return DashDust_Motive(k);
    if (vars.ancilla_timer[u] == 0) {
        vars.ancilla_timer[u] = 3;
        if (inc(&vars.ancilla_item_to_link[u]) == 5) return;
        if (vars.ancilla_item_to_link[u] == 6) {
            vars.ancilla_type[u] = 0;
            return;
        }
    }
    if (vars.ancilla_item_to_link[u] == 5) return;
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    const dx = signedOffset(tables.kDashDust_Draw_X1[vars.link_direction_facing.* >> 1]);
    const t = 3 * (@as(usize, vars.ancilla_item_to_link[u]) + @as(usize, if (vars.draw_water_ripples_or_grass.* == 1) 5 else 0));
    for (t..t + 3) |i| {
        if (tables.kDashDust_Draw_Char[i] != 0xff) {
            Ancilla_SetOam(oam, pt.x +% dx +% signedOffset(tables.kDashDust_Draw_X[i]), pt.y +% signedOffset(tables.kDashDust_Draw_Y[i]), tables.kDashDust_Draw_Char[i], 4 | hiPtr(vars.oam_priority_value).*, 0);
            oam += 1;
        }
    }
}
fn reverseHookshot(u: usize) void {
    vars.ancilla_step[u] = 1;
    vars.ancilla_x_vel[u] = 0 -% vars.ancilla_x_vel[u];
    vars.ancilla_y_vel[u] = 0 -% vars.ancilla_y_vel[u];
}
pub export fn Ancilla1F_Hookshot(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    advance: {
        if (vars.submodule_index.* != 0) break :advance;
        if (vars.ancilla_timer[u] == 0) {
            vars.ancilla_timer[u] = 7;
            Ancilla_Sfx2_Pan(k, 0xa);
        }
        if (vars.related_to_hookshot.* != 0) break :advance;
        Ancilla_MoveY(k);
        Ancilla_MoveX(k);
        if (vars.ancilla_step[u] != 0) {
            if (expired(&vars.ancilla_item_to_link[u])) {
                vars.ancilla_type[u] = 0;
                return;
            }
            break :advance;
        }
        if (inc(&vars.ancilla_item_to_link[u]) == 32) reverseHookshot(u);
        if (Hookshot_ShouldIEvenBotherWithTiles(k)) break :advance;
        if (vars.ancilla_L[u] == 0 and vars.ancilla_step[u] == 0 and Ancilla_CheckSpriteCollision(k) >= 0 and vars.ancilla_step[u] == 0) reverseHookshot(u);
        tile_detect.Hookshot_CheckTileCollision(k);
        var ledge: u8 = 0;
        const on_ledge = blk: {
            if (vars.player_is_indoors.* != 0) {
                ledge = @truncate(if (vars.ancilla_dir[u] & 2 == 0) (vars.tiledetect_vertical_ledge.* | (vars.tiledetect_vertical_ledge.* >> 4)) & 3 else vars.detection_of_ledge_tiles_horiz_uphoriz.* & 3);
                break :blk ledge != 0;
            }
            break :blk (vars.detection_of_ledge_tiles_horiz_uphoriz.* & 3 | vars.tiledetect_vertical_ledge.* | vars.detection_of_unknown_tile_types.*) & 0x33 != 0;
        };
        if (on_ledge and expired(&vars.ancilla_G[u])) {
            if (vars.ancilla_K[u] != 0 and (ledge & 3 != 0 or vars.ancilla_K[u] != loPtr(vars.index_of_interacting_tile).*)) {
                vars.ancilla_G[u] = 2;
                if (expired(&vars.ancilla_L[u])) vars.ancilla_L[u] = 0;
            } else {
                vars.ancilla_L[u] +%= 1;
                vars.ancilla_K[u] = @truncate(vars.index_of_interacting_tile.*);
                vars.ancilla_G[u] = 1;
            }
        }
        if (vars.ancilla_L[u] != 0) break :advance;
        if (!sign8(vars.ancilla_G[u])) {
            vars.ancilla_G[u] -%= 1;
            break :advance;
        }
        if ((vars.R14.* >> 4 | vars.R14.* | vars.tiledetect_stair_tile.* | vars.R12.*) & 3 != 0 and vars.ancilla_step[u] == 0) {
            reverseHookshot(u);
            if (vars.tiledetect_misc_tiles.* & 3 == 0) {
                AncillaAdd_HookshotWallClink(k, 6, 1);
                Ancilla_Sfx2_Pan(k, if (vars.tiledetect_misc_tiles.* & 0x30 != 0) 6 else 5);
            }
        }
        if (vars.tiledetect_misc_tiles.* & 3 != 0) {
            if (vars.ancilla_item_to_link[u] < 4) {
                vars.ancilla_type[u] = 0;
                return;
            }
            vars.related_to_hookshot.* = 1;
            vars.hookshot_effect_index.* = @intCast(k);
        }
    }
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    if (vars.ancilla_L[u] != 0) vars.oam_priority_value.* = 0x3000;
    var oam = GetOamCurPtr();
    const dir = vars.ancilla_dir[u];
    var x: c_int = pt.x;
    var y: c_int = pt.y;
    for (0..3) |i| {
        const j = @as(usize, dir) * 3 + i;
        if (tables.kHookShot_Draw_Char[j] != 0xff) {
            Ancilla_SetOam(oam, lowWord(x), lowWord(y), tables.kHookShot_Draw_Char[j], tables.kHookShot_Draw_Flags[j] | 2 | hiPtr(vars.oam_priority_value).*, 0);
            oam += 1;
        }
        if (i == 1) {
            x -= 8;
            y += 8;
        } else x += 8;
    }
    var n: c_int = vars.ancilla_item_to_link[u] >> 1;
    var extra: c_int = 0;
    if (n >= 7) {
        extra = n - 7;
        n = 6;
    }
    if (n == 0) return;
    if (dir & 1 != 0) extra = -extra;
    x = pt.x;
    y = pt.y;
    if (tables.kHookShot_Move_Y[dir] == 0) y += 4;
    if (tables.kHookShot_Move_X[dir] == 0) x += 4;
    while (n >= 0) : (n -= 1) {
        if (tables.kHookShot_Move_Y[dir] != 0) y += @as(c_int, tables.kHookShot_Move_Y[dir]) + extra;
        if (tables.kHookShot_Move_X[dir] != 0) x += @as(c_int, tables.kHookShot_Move_X[dir]) + extra;
        if (!Hookshot_CheckProximityToLink(x, y)) {
            Ancilla_SetOam(oam, lowWord(x), lowWord(y), 0x19, ((vars.frame_counter.* & 2) << 6) | 2 | hiPtr(vars.oam_priority_value).*, 0);
            oam += 1;
        }
    }
}
pub export fn Hookshot_ShouldIEvenBotherWithTiles(k: c_int) callconv(.c) bool {
    const x = Ancilla_GetX(k);
    const y = Ancilla_GetY(k);
    const vertical = vars.ancilla_dir[@intCast(k)] & 2 == 0;
    if (vars.player_is_indoors.* == 0) {
        const i = loPtr(vars.current_area_of_player).* >> 1;
        const t = if (vertical) y -% ow_tables.kOverworld_OffsetBaseY[i] else x -% ow_tables.kOverworld_OffsetBaseX[i];
        return t < @as(u16, if (vertical) 4 else 6) or t >= vars.overworld_right_bottom_bound_for_scroll.*;
    }
    return if (vertical) (y & 0x1ff) < 4 or (y & 0x1ff) >= 0x1e8 or (y & 0x200) != (vars.link_y_coord.* & 0x200) else (x & 0x1ff) < 4 or (x & 0x1ff) >= 0x1f0 or (x & 0x200) != (vars.link_x_coord.* & 0x200);
}
pub export fn Ancilla20_Blanket(k: c_int) callconv(.c) void {
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    const pose = vars.link_pose_during_opening.* != 0;
    _ = if (pose) sprite.Oam_AllocateFromRegionA(0x10) else sprite.Oam_AllocateFromRegionB(0x10);
    const oam = GetOamCurPtr();
    const base: usize = if (pose) 4 else 0;
    for (0..4) |i| {
        const j = base + i;
        Ancilla_SetOam(oam + i, pt.x, pt.y, tables.kBedSpread_Char[j], tables.kBedSpread_Flags[j] | 0xd | hiPtr(vars.oam_priority_value).*, 2);
        pt.x +%= 16;
        if (i == 1) {
            pt.x -%= 32;
            pt.y +%= 8;
        }
    }
}
pub export fn Ancilla21_Snore(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (expired(&vars.ancilla_aux_timer[u])) {
        if (vars.ancilla_item_to_link[u] != 2) vars.ancilla_item_to_link[u] +%= 1;
        vars.ancilla_aux_timer[u] = 7;
    }
    vars.ancilla_x_vel[u] +%= vars.ancilla_step[u];
    if (abs8(vars.ancilla_x_vel[u]) >= 8) vars.ancilla_step[u] = 0 -% vars.ancilla_step[u];
    Ancilla_MoveY(k);
    Ancilla_MoveX(k);
    if (Ancilla_GetY(k) <= vars.link_y_coord.* -% 24) vars.ancilla_type[u] = 0;
    vars.link_dma_var5.* = tables.kBedSpread_Dma[vars.ancilla_item_to_link[u]];
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    Ancilla_SetOam(GetOamCurPtr(), pt.x, pt.y, 9, 0x24, 0);
}
pub export fn Ancilla3B_SwordUpSparkle(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.ancilla_aux_timer[u] != 0) {
        vars.ancilla_aux_timer[u] -%= 1;
        return;
    }
    if (expired(&vars.ancilla_arr3[u])) {
        vars.ancilla_arr3[u] = 1;
        if (inc(&vars.ancilla_item_to_link[u]) == 4) {
            vars.ancilla_type[u] = 0;
            vars.ancilla_aux_timer[u] -%= 1;
            return;
        }
    }
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    const t = @as(usize, vars.ancilla_item_to_link[u]) * 4;
    for (t..t + 4) |j| {
        if (tables.kAncilla_VictorySparkle_Char[j] != 0xff) {
            Ancilla_SetOam(oam, vars.link_x_coord.* +% signedOffset(tables.kAncilla_VictorySparkle_X[j]) -% vars.BG2HOFS_copy2.*, vars.link_y_coord.* +% signedOffset(tables.kAncilla_VictorySparkle_Y[j]) -% vars.BG2VOFS_copy2.*, tables.kAncilla_VictorySparkle_Char[j], tables.kAncilla_VictorySparkle_Flags[j] | 4 | hiPtr(vars.oam_priority_value).*, 0);
            oam += 1;
        }
    }
}
pub export fn Ancilla3C_SpinAttackChargeSparkle(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.submodule_index.* == 0 and vars.ancilla_timer[u] == 0) {
        vars.ancilla_timer[u] = 4;
        if (inc(&vars.ancilla_item_to_link[u]) == 3) {
            vars.ancilla_type[u] = 0;
            return;
        }
    }
    vars.ancilla_oam_idx[u] = @intCast(Ancilla_AllocateOamFromRegion_A_or_D_or_F(k, 4));
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    const j = vars.ancilla_item_to_link[u];
    Ancilla_SetOam(GetOamCurPtr(), pt.x, pt.y, tables.kSwordChargeSpark_Char[j], tables.kSwordChargeSpark_Flags[j] | hiPtr(vars.oam_priority_value).*, 0);
}
pub export fn Ancilla35_MasterSwordReceipt(k: c_int) callconv(.c) void {
    const u: usize = @intCast(k);
    if (vars.ancilla_timer[u] == 0) {
        vars.ancilla_type[u] = 0;
        return;
    }
    if (expired(&vars.ancilla_aux_timer[u])) vars.ancilla_item_to_link[u] = if (vars.ancilla_item_to_link[u] == 2) 0 else vars.ancilla_item_to_link[u] +% 1;
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    const oam = GetOamCurPtr();
    if (vars.ancilla_item_to_link[u] == 0) return;
    const t = @as(usize, vars.ancilla_item_to_link[u] - 1) * 4;
    for (0..4) |i| {
        const j = t + i;
        Ancilla_SetOam(oam + i, pt.x +% signedOffset(tables.kSwordCeremony_X[j]), pt.y +% signedOffset(tables.kSwordCeremony_Y[j]), tables.kSwordCeremony_Char[j], (tables.kSwordCeremony_Flags[j] & 0xcf) | 4 | hiPtr(vars.oam_priority_value).*, 0);
    }
}

fn alloc(a: u8, limit: u8) ?usize {
    const k = Ancilla_AddAncilla(a, limit);
    return if (k < 0) null else @intCast(k);
}
fn placeFromLink(k: usize, x: i16, y: i16) void {
    Ancilla_SetXY(@intCast(k), vars.link_x_coord.* +% signedOffset(x), vars.link_y_coord.* +% signedOffset(y));
}
pub export fn Ancilla_AddHitStars(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_aux_timer[k] = 2;
    vars.ancilla_arr3[k] = 1;
    vars.ancilla_y_vel[k] = 0;
    vars.ancilla_x_vel[k] = 0;
    const j: usize = if (vars.link_item_in_hand.* != 0) @as(usize, vars.link_direction_facing.* >> 1) + 2 else if (vars.link_position_mode.* != 0) @intFromBool(vars.link_direction_facing.* != 4) else a;
    vars.ancilla_step[k] = @intCast(j);
    const t = vars.link_x_coord.* +% signedOffset(tables.kShovelHitStars_X2[j]);
    vars.ancilla_A[k] = @truncate(t);
    vars.ancilla_B[k] = @truncate(t >> 8);
    placeFromLink(k, tables.kShovelHitStars_XY[j * 2 + 1], tables.kShovelHitStars_XY[j * 2]);
}
pub export fn AncillaAdd_Blanket(a: u8) callconv(.c) void {
    vars.ancilla_type[0] = a;
    vars.ancilla_numspr[0] = tables.kAncilla_Pflags[a];
    vars.ancilla_floor[0] = vars.link_is_on_lower_level.*;
    vars.ancilla_floor2[0] = vars.link_is_on_lower_level_mirror.*;
    vars.ancilla_objprio[0] = 0;
    Ancilla_SetXY(0, 0x938, 0x2162);
}
pub export fn AncillaAdd_Snoring(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_y_vel[k] = 248;
    vars.ancilla_aux_timer[k] = 7;
    vars.ancilla_x_vel[k] = 8;
    vars.ancilla_step[k] = 255;
    placeFromLink(k, 16, 4);
}
pub export fn AncillaAdd_Bomb(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    if (vars.link_item_bombs.* == 0) {
        vars.ancilla_type[k] = 0;
        return;
    }
    vars.link_item_bombs.* -= 1;
    if (vars.link_item_bombs.* == 0) hud.Hud_RefreshIcon();
    vars.ancilla_R[k] = 0;
    vars.ancilla_step[k] = 0;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_L[k] = 0;
    vars.ancilla_arr3[k] = tables.kBomb_Tab0[0];
    vars.ancilla_arr25[k] = 0;
    vars.ancilla_arr26[k] = 7;
    vars.ancilla_z[k] = 0;
    vars.ancilla_timer[k] = 8;
    vars.ancilla_dir[k] = vars.link_direction_facing.* >> 1;
    vars.ancilla_T[k] = 0;
    vars.ancilla_arr23[k] = 0;
    vars.ancilla_arr22[k] = 0;
    const hit = Ancilla_CheckInitialTileCollision_Class2(@intCast(k));
    const j = vars.link_direction_facing.* >> 1;
    placeFromLink(k, if (hit) tables.kBomb_Place_X0[j] else tables.kBomb_Place_X1[j], if (hit) tables.kBomb_Place_Y0[j] else tables.kBomb_Place_Y1[j]);
    vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | 0xb;
}
pub export fn AncillaAdd_Boomerang(a: u8, limit: u8) callconv(.c) u8 {
    const k = alloc(a, limit) orelse return 0;
    vars.ancilla_aux_timer[k] = 0;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_K[k] = 0;
    vars.ancilla_z[k] = 0;
    vars.ancilla_L[k] = vars.ancilla_numspr[k];
    vars.flag_for_boomerang_in_place.* = 1;
    const variant = vars.link_item_boomerang.* - 1;
    vars.ancilla_G[k] = variant;
    vars.ancilla_step[k] = tables.kBoomerang_Tab1[variant];
    vars.ancilla_arr3[k] = tables.kBoomerang_Tab2[variant];
    const buttons = vars.joypad1H_last.*;
    const s = @as(usize, variant) * 2 + @intFromBool(buttons & 0xc != 0 and buttons & 3 != 0);
    const speed = tables.kBoomerang_Tab0[s];
    vars.ancilla_H[k] = speed;
    const direction = if (buttons & 15 != 0) buttons & 15 else tables.kBoomerang_Tab3[vars.link_direction_facing.* >> 1];
    vars.hookshot_effect_index.* = 0;
    if (direction & 0xc != 0) {
        vars.ancilla_y_vel[k] = if (direction & 8 != 0) 0 -% speed else speed;
        const i: u8 = if (sign8(vars.ancilla_y_vel[k])) 0 else 1;
        vars.ancilla_dir[k] = i;
        vars.hookshot_effect_index.* = tables.kBoomerang_Tab3[i];
    }
    vars.ancilla_S[k] = 0;
    if (direction & 3 != 0) {
        if (direction & 2 == 0) vars.ancilla_S[k] = 1;
        vars.ancilla_x_vel[k] = if (direction & 2 != 0) 0 -% speed else speed;
        const i: u8 = if (sign8(vars.ancilla_x_vel[k])) 2 else 3;
        vars.ancilla_dir[k] = i;
        vars.hookshot_effect_index.* |= tables.kBoomerang_Tab3[i];
    }
    var j: usize = @intCast(@max(FindInByteArray(&tables.kBoomerang_Tab4, direction, 8), 0));
    vars.ancilla_arr1[k] = tables.kBoomerang_Tab5[j];
    vars.ancilla_arr23[k] = @intCast(j * 2);
    if (vars.button_b_frames.* >= 9) vars.ancilla_aux_timer[k] +%= 1 else if (s != 0 or buttons & 15 == 0) {
        j = vars.link_direction_facing.* >> 1;
    }
    const collision = Ancilla_CheckInitialTile_A(@intCast(k));
    if (collision < 0) {
        if (vars.ancilla_aux_timer[k] != 0) placeFromLink(k, tables.kBoomerang_Tab9[j], 8 + @as(i16, tables.kBoomerang_Tab8[j])) else placeFromLink(k, tables.kBoomerang_Tab7[j], 8 + @as(i16, tables.kBoomerang_Tab6[j]));
    } else {
        vars.ancilla_type[k] = 0;
        vars.flag_for_boomerang_in_place.* = 0;
        vars.sound_effect_1.* = Ancilla_CalculateSfxPan(@intCast(k)) | @as(u8, if (vars.ancilla_tile_attr[k] != 0xf0) 5 else 6);
        AncillaAdd_BoomerangWallClink(@intCast(k));
    }
    return @truncate(@as(u32, @bitCast(collision)));
}
pub export fn AncillaAdd_ExplodingWeatherVane(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_aux_timer[k] = 10;
    vars.ancilla_G[k] = 128;
    vars.ancilla_step[k] = 0;
    vars.ancilla_arr3[k] = 0;
    vars.sound_effect_1.* = 0;
    vars.music_control.* = 0xf2;
    vars.sound_effect_ambient.* = 0x17;
    vars.weathervane_var1.* = 0;
    vars.weathervane_var2.* = 0x280;
    for (0..12) |i| {
        vars.weathervane_arr3[i] = 0;
        vars.weathervane_arr4[i] = @bitCast(tables.kWeathervane_Tab4[i]);
        vars.weathervane_arr5[i] = @bitCast(tables.kWeathervane_Tab5[i]);
        vars.weathervane_arr6[i] = tables.kWeathervane_Tab6[i];
        vars.weathervane_arr7[i] = 7;
        vars.weathervane_arr8[i] = tables.kWeathervane_Tab8[i];
        vars.weathervane_arr9[i] = 2;
        vars.weathervane_arr10[i] = tables.kWeathervane_Tab10[i];
        vars.weathervane_arr11[i] = 1;
        vars.weathervane_arr12[i] = @intCast(i & 1);
    }
}
pub export fn AncillaAdd_CutsceneDuck(a: u8, limit: u8) callconv(.c) void {
    if (AncillaAdd_CheckForPresence(a)) return;
    const k = alloc(a, limit) orelse return;
    vars.ancilla_dir[k] = 2;
    vars.ancilla_arr3[k] = 3;
    vars.ancilla_step[k] = 0;
    vars.ancilla_aux_timer[k] = 32;
    vars.ancilla_item_to_link[k] = 116;
    vars.ancilla_z_vel[k] = 0;
    vars.ancilla_L[k] = 0;
    vars.ancilla_z[k] = 0;
    vars.ancilla_S[k] = 0;
    Ancilla_SetXY(@intCast(k), 0x200, 0x788);
}
pub export fn AncillaAdd_SomariaPlatformPoof(k: c_int) callconv(.c) void {
    vars.ancilla_type[@intCast(k)] = 0x39;
    vars.ancilla_aux_timer[@intCast(k)] = 7;
    for (0..16) |j| {
        if (vars.sprite_type[j] == 0xed) {
            vars.sprite_state[j] = 0;
            vars.player_on_somaria_platform.* = 0;
        }
    }
    tile_detect.Player_TileDetectNearby();
}
pub export fn AncillaAdd_SuperBombExplosion(a: u8, limit: u8) callconv(.c) c_int {
    const k = alloc(a, limit) orelse return -1;
    vars.ancilla_R[k] = 0;
    vars.ancilla_step[k] = 0;
    vars.ancilla_arr25[k] = 0;
    vars.ancilla_L[k] = 0;
    vars.ancilla_arr3[k] = tables.kBomb_Tab0[1];
    vars.ancilla_item_to_link[k] = 1;
    const j = @as(*align(1) u16, @ptrCast(vars.tagalong_var2)).*;
    const x = @as(u16, vars.tagalong_x_hi[j]) << 8 | vars.tagalong_x_lo[j];
    const y = @as(u16, vars.tagalong_y_hi[j]) << 8 | vars.tagalong_y_lo[j];
    Ancilla_SetXY(@intCast(k), x +% 8, y +% 16);
    return @intCast(k);
}
pub export fn ConfigureRevivalAncillae() callconv(.c) void {
    vars.link_dma_var5.* = 80;
    vars.ancilla_arr3[0] = 64;
    vars.ancilla_step[0] = 0;
    vars.ancilla_z_vel[0] = 8;
    vars.ancilla_L[0] = 0;
    vars.ancilla_G[0] = 5;
    vars.ancilla_item_to_link[0] = 0;
    vars.ancilla_K[0] = 0;
    placeFromLink(0, 0, 0);
    vars.ancilla_z[0] = 0;
    vars.ancilla_z[1] = 0;
    vars.ancilla_arr3[1] = 240;
    vars.ancilla_step[1] = 0;
    vars.ancilla_K[1] = 0;
    vars.ancilla_item_to_link[2] = 2;
    vars.ancilla_aux_timer[2] = 3;
    vars.ancilla_arr3[2] = 8;
    vars.ancilla_step[2] = 0;
    vars.ancilla_dir[2] = 3;
    vars.ancilla_arr25[2] = tables.kMagicPowder_Tab0[32];
    placeFromLink(2, 20, 2);
}
pub export fn AncillaAdd_BlastWallFireball(a: u8, limit: u8, r4: c_int) callconv(.c) void {
    _ = a;
    _ = limit;
    var k: usize = 11;
    while (k > 5) {
        k -= 1;
        if (vars.ancilla_type[k] != 0) continue;
        vars.ancilla_type[k] = 0x32;
        vars.ancilla_floor[k] = vars.link_is_on_lower_level.*;
        vars.blastwall_var12[k] = 16;
        const j = @as(usize, vars.frame_counter.* & 15) * 2;
        vars.ancilla_y_vel[k] = @bitCast(tables.kBlastWall_XY[j]);
        vars.ancilla_x_vel[k] = @bitCast(tables.kBlastWall_XY[j + 1]);
        Ancilla_SetXY(@intCast(k), vars.blastwall_var11[@intCast(r4)] +% 16, vars.blastwall_var10[@intCast(r4)] +% 8);
        return;
    }
}
pub export fn AncillaAdd_Arrow(a: u8, ax: u8, ay: u8, x: u16, y: u16) callconv(.c) c_int {
    vars.scratch_0.* = y;
    vars.scratch_1.* = x;
    loPtr(vars.index_of_interacting_tile).* = ax;
    if (AncillaAdd_CheckForPresence(a)) return -1;
    const slot = AncillaAdd_ArrowFindSlot(a, ay);
    if (slot >= 0) {
        const k: usize = @intCast(slot);
        vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | 7;
        vars.ancilla_H[k] = 0;
        vars.ancilla_item_to_link[k] = 8;
        const j = ax >> 1;
        vars.ancilla_dir[k] = j | 4;
        vars.ancilla_y_vel[k] = @bitCast(tables.kShootBow_Yvel[j]);
        vars.ancilla_x_vel[k] = @bitCast(tables.kShootBow_Xvel[j]);
        Ancilla_SetXY(slot, x +% signedOffset(tables.kShootBow_X[j]), y +% 8 +% signedOffset(tables.kShootBow_Y[j]));
    }
    return slot;
}
pub export fn AncillaAdd_BunnyPoof(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.link_visibility_status.* = 0xc;
    vars.ancilla_step[k] = 0;
    vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | @as(u8, if (vars.link_is_bunny_mirror.* == 0) 0x14 else 0x15);
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_aux_timer[k] = 7;
    placeFromLink(k, 0, 4);
}
pub export fn AncillaAdd_CapePoof(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_step[k] = 1;
    vars.link_is_transforming.* = 1;
    vars.link_cant_change_direction.* |= 1;
    vars.link_direction.* = 0;
    vars.link_direction_last.* = 0;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_aux_timer[k] = 7;
    placeFromLink(k, 0, 4);
}
pub export fn AncillaAdd_DwarfPoof(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | @as(u8, if (vars.follower_indicator.* == 8) 0x14 else 0x15);
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_step[k] = 0;
    vars.ancilla_aux_timer[k] = 7;
    vars.tagalong_var5.* = 1;
    const j = vars.tagalong_var2.*;
    const x = @as(u16, vars.tagalong_x_hi[j]) << 8 | vars.tagalong_x_lo[j];
    const y = @as(u16, vars.tagalong_y_hi[j]) << 8 | vars.tagalong_y_lo[j];
    Ancilla_SetXY(@intCast(k), x, y +% 4);
}
pub export fn AncillaAdd_EtherSpell(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_arr25[k] = 0;
    vars.ancilla_step[k] = 0;
    vars.flag_custom_spell_anim_active.* = 1;
    vars.ancilla_aux_timer[k] = 2;
    vars.ancilla_arr3[k] = 3;
    vars.ancilla_y_vel[k] = 127;
    ether_var2().* = 40;
    vars.load_chr_halfslot_even_odd.* = 9;
    ether_var1().* = 0x40;
    vars.sound_effect_2.* = misc.Link_CalculateSfxPan() | 0x26;
    for (0..8) |i| ether_arr1()[i] = @intCast(i * 8);
    ether_y().* = vars.link_y_coord.*;
    const y = vars.BG2VOFS_copy2.* -% 16;
    ether_y_adjusted().* = y & 0xf0;
    ether_x().* = vars.link_x_coord.*;
    ether_x2().* = ether_x().* +% 8;
    ether_y2().* = vars.link_y_coord.* -% 16;
    ether_y3().* = ether_y2().* +% 0x24;
    Ancilla_SetXY(@intCast(k), vars.link_x_coord.*, y);
}
pub export fn AncillaAdd_VictorySpin() callconv(.c) void {
    if ((@as(u16, vars.link_sword_type.*) + 1) & 0xfe == 0) return;
    const k = alloc(0x3b, 0) orelse return;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_arr3[k] = 1;
    vars.ancilla_aux_timer[k] = 34;
}
pub export fn AncillaAdd_MagicPowder(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_z[k] = 0;
    vars.ancilla_aux_timer[k] = 1;
    vars.link_dma_var5.* = 80;
    const j = vars.link_direction_facing.* >> 1;
    vars.ancilla_dir[k] = j;
    vars.ancilla_arr25[k] = tables.kMagicPowder_Tab0[@as(usize, j) * 10];
    placeFromLink(k, tables.kMagicPower_X[j], tables.kMagicPower_Y[j]);
    _ = Ancilla_CheckTileCollision(@intCast(k));
    vars.byte_7E0333.* = vars.ancilla_tile_attr[k];
    if (vars.current_item_active.* == 9) {
        vars.ancilla_type[k] = 0;
        return;
    }
    vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | 0xd;
    placeFromLink(k, tables.kMagicPower_X1[j], tables.kMagicPower_Y1[j]);
}
pub export fn AncillaAdd_WallTapSpark(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_item_to_link[k] = 5;
    vars.ancilla_aux_timer[k] = 1;
    const j = vars.link_direction_facing.* >> 1;
    placeFromLink(k, tables.kWallTapSpark_X[j], tables.kWallTapSpark_Y[j]);
}
pub export fn AncillaAdd_SwordSwingSparkle(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_aux_timer[k] = 1;
    vars.ancilla_dir[k] = vars.link_direction_facing.* >> 1;
    placeFromLink(k, 0, 0);
}
pub export fn AncillaAdd_DashTremor(a: u8, limit: u8) callconv(.c) void {
    if (AncillaAdd_CheckForPresence(a)) return;
    const k = alloc(a, limit) orelse return;
    vars.ancilla_item_to_link[k] = 16;
    vars.ancilla_L[k] = 0;
    const j = tables.kAddDashTremor_Dir[vars.link_direction_facing.* >> 1];
    vars.ancilla_dir[k] = j;
    const y: u8 = @truncate(vars.link_y_coord.* -% vars.BG2VOFS_copy2.*);
    const x: u8 = @truncate(vars.link_x_coord.* -% vars.BG2HOFS_copy2.*);
    Ancilla_SetY(@intCast(k), if ((if (j != 0) y else x) < tables.kAddDashTremor_Tab[j >> 1]) 3 else 0xfffd);
}
pub export fn AncillaAdd_BoomerangWallClink(kin: c_int) callconv(.c) void {
    vars.boomerang_temp_x.* = Ancilla_GetX(kin);
    vars.boomerang_temp_y.* = Ancilla_GetY(kin);
    const k = alloc(6, 1) orelse return;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_arr3[k] = 1;
    const j = tables.kBoomerangWallHit_Tab0[vars.hookshot_effect_index.*] >> 1;
    Ancilla_SetXY(@intCast(k), vars.boomerang_temp_x.* +% signedOffset(tables.kBoomerangWallHit_X[j]), vars.boomerang_temp_y.* +% signedOffset(tables.kBoomerangWallHit_Y[j]));
}
pub export fn AncillaAdd_HookshotWallClink(kin: c_int, a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_arr3[k] = 1;
    const j = vars.ancilla_dir[@intCast(kin)];
    Ancilla_SetXY(@intCast(k), Ancilla_GetX(kin) +% signedOffset(tables.kHookshotWallHit_X[j]), Ancilla_GetY(kin) +% signedOffset(tables.kHookshotWallHit_Y[j]));
}
pub export fn AncillaAdd_Duck_take_off(a: u8, limit: u8) callconv(.c) void {
    if (AncillaAdd_CheckForPresence(a)) return;
    const k = alloc(a, limit) orelse return;
    vars.ancilla_timer[k] = 0x78;
    vars.ancilla_L[k] = 0;
    vars.ancilla_z_vel[k] = 0;
    vars.ancilla_z[k] = 0;
    vars.ancilla_step[k] = 0;
    AddBirdCommon(@intCast(k));
}
pub export fn AddBirdTravelSomething(a: u8, limit: u8) callconv(.c) void {
    if (AncillaAdd_CheckForPresence(a)) return;
    const k = alloc(a, limit) orelse return;
    vars.link_player_handler_state.* = 0;
    vars.link_speed_setting.* = 0;
    vars.button_mask_b_y.* &= 0x7e;
    vars.button_b_frames.* = 0;
    vars.link_delay_timer_spin_attack.* = 0;
    vars.link_cant_change_direction.* &= 0xfe;
    vars.ancilla_L[k] = 1;
    const wide = features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0;
    vars.ancilla_z_vel[k] = if (wide) 58 else 40;
    vars.ancilla_z[k] = if (wide) 151 else 205;
    vars.ancilla_step[k] = 2;
    AddBirdCommon(@intCast(k));
}
pub export fn AncillaAdd_QuakeSpell(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse return;
    vars.ancilla_step[k] = 0;
    vars.ancilla_item_to_link[k] = 0;
    vars.load_chr_halfslot_even_odd.* = 13;
    vars.sound_effect_1.* = 0x35;
    @memset(vars.quake_arr2[0..5], 0);
    vars.quake_var5.* = 0;
    @memset(vars.quake_arr1[0..5], 1);
    vars.flag_custom_spell_anim_active.* = 1;
    vars.ancilla_timer[k] = 2;
    vars.quake_var1.* = vars.link_y_coord.* +% 26;
    vars.quake_var2.* = vars.link_x_coord.* +% 8;
    vars.quake_var3.* = 3;
}
pub export fn AncillaAdd_SpinAttackInitSpark(a: u8, x: u8, limit: u8) callconv(.c) void {
    const slot = Ancilla_AddAncilla(a, limit);
    for (0..5) |i| {
        if (vars.ancilla_type[i] == 0x31) vars.ancilla_type[i] = 0;
    }
    // The caller reserves a slot before starting this animation.
    const k: usize = @intCast(slot);
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_step[k] = x;
    vars.ancilla_timer[k] = 4;
    vars.ancilla_aux_timer[k] = 3;
    const j = vars.link_direction_facing.* >> 1;
    placeFromLink(k, tables.kSpinAttackStartSparkle_X[j], tables.kSpinAttackStartSparkle_Y[j]);
}
pub export fn AncillaAdd_SwordChargeSparkle(kin: c_int) callconv(.c) void {
    const slot = Ancilla_AllocHigh();
    if (slot < 0) return;
    const k: usize = @intCast(slot);
    vars.ancilla_type[k] = 60;
    vars.ancilla_floor[k] = vars.link_is_on_lower_level.*;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_timer[k] = 4;
    const r = misc.GetRandomNumber();
    var z = vars.ancilla_z[@intCast(kin)];
    if (z >= 0xf8) z = 0;
    Ancilla_SetXY(slot, Ancilla_GetX(kin) +% 2 +% (r >> 5), Ancilla_GetY(kin) -% 2 -% z +% (r & 15));
}
pub export fn AncillaAdd_SilverArrowSparkle(kin: c_int) callconv(.c) void {
    const slot = Ancilla_AllocHigh();
    if (slot < 0) return;
    const k: usize = @intCast(slot);
    vars.ancilla_type[k] = 0x3c;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_timer[k] = 4;
    vars.ancilla_floor[k] = vars.link_is_on_lower_level.*;
    const m = misc.GetRandomNumber();
    const j = vars.ancilla_dir[@intCast(kin)] & 3;
    Ancilla_SetXY(slot, Ancilla_GetX(kin) +% signedOffset(tables.kSilverArrowSparkle_X[j]) +% ((m >> 4) & 7), Ancilla_GetY(kin) +% signedOffset(tables.kSilverArrowSparkle_Y[j]) +% (m & 7));
}
pub export fn AncillaAdd_IceRodShot(a: u8, limit: u8) callconv(.c) void {
    const k = alloc(a, limit) orelse {
        player.Refund_Magic(0);
        return;
    };
    vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | 15;
    vars.ancilla_step[k] = 0;
    vars.ancilla_arr25[k] = 0;
    vars.ancilla_item_to_link[k] = 255;
    vars.ancilla_L[k] = 1;
    vars.ancilla_aux_timer[k] = 3;
    vars.ancilla_arr3[k] = 6;
    const j = vars.link_direction_facing.* >> 1;
    vars.ancilla_dir[k] = j;
    vars.ancilla_y_vel[k] = @bitCast(tables.kIceRod_Yvel[j]);
    vars.ancilla_x_vel[k] = @bitCast(tables.kIceRod_Xvel[j]);
    if (Ancilla_CheckInitialTile_A(@intCast(k)) < 0) {
        const x = vars.link_x_coord.* +% signedOffset(tables.kIceRod_X[j]);
        const y = vars.link_y_coord.* +% signedOffset(tables.kIceRod_Y[j]);
        if (((x -% vars.BG2HOFS_copy2.*) | (y -% vars.BG2VOFS_copy2.*)) & 0xff00 != 0) {
            vars.ancilla_type[k] = 0;
            return;
        }
        Ancilla_SetXY(@intCast(k), x, y);
    } else {
        vars.ancilla_type[k] = 0x11;
        vars.ancilla_numspr[k] = tables.kAncilla_Pflags[0x11];
        vars.ancilla_item_to_link[k] = 0;
        vars.ancilla_aux_timer[k] = 4;
    }
}
pub export fn AncillaAdd_Splash(a: u8, limit: u8) callconv(.c) bool {
    const k = alloc(a, limit) orelse return true;
    vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | 0x24;
    vars.ancilla_item_to_link[k] = 0;
    vars.ancilla_aux_timer[k] = 2;
    if (vars.player_is_indoors.* != 0 and vars.link_is_in_deep_water.* == 0) vars.link_is_on_lower_level.* = 0;
    placeFromLink(k, -11, 8);
    return false;
}

// ---------------------------------------------------------------------------
// Item receipts, wish pond, and splashes.
// ---------------------------------------------------------------------------

/// player.zig keeps these private, so the handful used here are repeated.
const kPlayerState_Ground = 0;
const kPlayerState_Swimming = 4;
const kPlayerState_PermaBunny = 23;
const kPlayerState_ReceivingEther = 25;
const kPlayerState_ReceivingBombos = 26;

/// Defined in sprite_main_tables.zig.
extern const kWishPond2_OamFlags: [76]u8;

/// The `endif_11` tail of Ancilla22_ItemReceipt, also fallen into from `label_a`.
fn ItemReceipt_Finish(k: c_int) void {
    const i: usize = @intCast(k);
    vars.item_receipt_method.* = 0;
    var a = vars.ancilla_item_to_link[i];
    if (a == 23 and vars.link_heart_pieces.* == 0) {
        player.Link_ReceiveItem(0x26, 0);
        vars.ancilla_type[i] = 0;
        vars.flag_unk1.* = 0;
        return;
    }
    if (a == 0x26 or a == 0x3f) {
        if (vars.link_health_capacity.* != 0xa0) {
            vars.link_health_capacity.* +%= 8;
            vars.link_hearts_filler.* +%= vars.link_health_capacity.* -% vars.link_health_current.*;
            misc.Ancilla_Sfx3_Near(0xd);
        }
    } else if (a == 0x3e) {
        vars.flag_is_link_immobilized.* = 0;
        if (vars.link_health_capacity.* != 0xa0) {
            vars.link_health_capacity.* +%= 8;
            vars.link_hearts_filler.* +%= 8;
            misc.Ancilla_Sfx3_Near(0xd);
        }
    } else if (a == 0x42) {
        vars.link_hearts_filler.* +%= 8;
    } else if (a == 0x45) {
        vars.link_magic_filler.* +%= 16;
    } else if (a == 0x22 or a == 0x23) {
        load_gfx.Palette_Load_LinkArmorAndGloves();
    }
    vars.ancilla_type[i] = 0;
    vars.flag_unk1.* = 0;
    a = vars.ancilla_item_to_link[i];
    if (vars.ancilla_step[i] == 3 and a != 0x10 and a != 0x26 and a != 0xf and a != 0x20)
        PrepareDungeonExitFromBossFight();
    if (vars.ancilla_step[i] != 2) vars.flag_is_link_immobilized.* = 0;
}

pub export fn Ancilla22_ItemReceipt(k: c_int) callconv(.c) void { // 88c38a
    const i: usize = @intCast(k);
    endif_1: {
        if (vars.flag_is_link_immobilized.* == 2) break :endif_1;
        if (vars.submodule_index.* != 0 and vars.submodule_index.* != 43 and vars.submodule_index.* != 9) {
            if (vars.submodule_index.* == 2) vars.ancilla_timer[i] = 16;
            break :endif_1;
        }
        vars.flag_unk1.* +%= 1;

        label_b: {
            endif_6: {
                label_a: {
                    if (vars.ancilla_step[i] != 0 and vars.ancilla_step[i] != 3) {
                        vars.ancilla_aux_timer[i] -%= 1;
                        if (sign8(vars.ancilla_aux_timer[i])) {
                            ItemReceipt_Finish(k);
                            return;
                        }
                        if (vars.ancilla_aux_timer[i] == 0) break :endif_6;
                        if (vars.ancilla_aux_timer[i] == 40 and vars.ancilla_step[i] != 2) {
                            if (Ancilla_AddRupees(k) or vars.ancilla_item_to_link[i] != 0x17)
                                misc.Ancilla_Sfx3_Near(0xf);
                        }
                        break :label_b;
                    }
                    if (vars.ancilla_item_to_link[i] == 1 and vars.ancilla_step[i] != 2) {
                        if (vars.ancilla_timer[i] == 0) break :label_a;
                        if (vars.ancilla_timer[i] != 17) break :endif_1;
                        vars.word_7E02CD.* = 0xDF3;
                        vars.follower_indicator.* = 0xe;
                        break :endif_6;
                    }
                    vars.ancilla_aux_timer[i] -%= 1;
                    const a = vars.ancilla_aux_timer[i];
                    if (a == 0) break :label_a;
                    if (a == 1) {
                        const it = vars.ancilla_item_to_link[i];
                        if ((it != 0x37 and it != 0x38 and it != 0x39) or audio.zelda_read_apui00() == 0)
                            break :endif_6;
                        vars.ancilla_aux_timer[i] +%= 1;
                    }
                    break :endif_1;
                }
                // label_a
                if (vars.ancilla_item_to_link[i] == 1 and vars.ancilla_step[i] == 0) {
                    vars.sound_effect_ambient.* = 5;
                    vars.music_control.* = 2;
                }
                vars.link_player_handler_state.* = if (vars.link_is_in_deep_water.* != 0) kPlayerState_Swimming else 0;
                vars.link_receiveitem_index.* = 0;
                vars.link_pose_for_item.* = 0;
                vars.link_disable_sprite_damage.* = 0;
                _ = Ancilla_AddRupees(k);
                ItemReceipt_Finish(k);
                return;
            }
            // endif_6
            if (vars.player_is_indoors.* != 0) {
                const room = vars.dungeon_room_index.*;
                if (room == 0xff or room == 0x10f or room == 0x110 or room == 0x112 or room == 0x11f)
                    break :label_b;
            }
            var msg: i32 = -1;
            const it = vars.ancilla_item_to_link[i];
            if (it == 0x38 or it == 0x39) {
                msg = if (vars.link_which_pendants.* & 7 == 7)
                    tables.kReceiveItemMsgs2[it - 0x38]
                else
                    tables.kReceiveItemMsgs[it];
            } else if (vars.ancilla_step[i] != 2) {
                msg = if (it == 0x17)
                    tables.kReceiveItemMsgs3[vars.link_heart_pieces.*]
                else
                    tables.kReceiveItemMsgs[it];
            }
            if (msg != -1) {
                vars.dialogue_message_index.* = @intCast(msg);
                if (msg == 0x70) vars.sound_effect_ambient.* = 9;
                misc.Main_ShowTextMessage();
            }
            break :endif_1;
        }
        // label_b
        if (vars.ancilla_aux_timer[i] >= 24) {
            const a = vars.ancilla_y_vel[i] -% 1;
            if (a >= 248) vars.ancilla_y_vel[i] = a;
            Ancilla_MoveY(k);
        }
    }
    // endif_1
    if (vars.ancilla_item_to_link[i] == 0x20) {
        vars.ancilla_z[i] = 0;
        AncillaAdd_OccasionalSparkle(k);
        if (audio.zelda_read_apui00() == 0) {
            vars.music_control.* = 0x1a;
            ItemReceipt_TransmuteToRisingCrystal(k);
            return;
        }
    } else if (vars.ancilla_item_to_link[i] == 1) {
        vars.ancilla_arr4[i] = tables.kReceiveItem_Tab0[0];
        if (vars.ancilla_step[i] != 2) {
            skipit: {
                var a: u8 = 0;
                if (vars.ancilla_timer[i] >= 16) {
                    vars.ancilla_arr3[i] -%= 1;
                    if (!sign8(vars.ancilla_arr3[i])) break :skipit;
                    vars.ancilla_arr3[i] = 2;
                    a = vars.ancilla_arr1[i] +% 1;
                    if (a == 3) a = 0;
                }
                vars.ancilla_arr1[i] = a;
                vars.ancilla_arr4[i] = tables.kReceiveItem_Tab0[a];
            }
        }
    }

    const it = vars.ancilla_item_to_link[i];
    if (it == 0x34 or it == 0x35 or it == 0x36) {
        vars.ancilla_arr3[i] -%= 1;
        if (sign8(vars.ancilla_arr3[i])) {
            var a = vars.ancilla_arr1[i] +% 1;
            if (a == 3) a = 0;
            vars.ancilla_arr1[i] = a;
            vars.ancilla_arr3[i] = tables.kReceiveItem_Tab4[a];
            load_gfx.WriteTo4BPPBuffer_at_7F4000(tables.kReceiveItem_Tab5[a]);
        }
    }
    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    _ = Ancilla_ReceiveItem_Draw(k, pt.x, pt.y);
}

pub export fn Ancilla_ReceiveItem_Draw(k: c_int, x: c_int, y: c_int) callconv(.c) [*]align(1) OamEnt { // 88c690
    var oam = GetOamCurPtr();
    const j: usize = vars.ancilla_item_to_link[@intCast(k)];
    oam[0].charnum = 0x24;
    var a = kWishPond2_OamFlags[j];
    if (sign8(a)) a = vars.ancilla_arr4[@intCast(k)];
    Ancilla_SetOam(oam, lowWord(x), lowWord(y), 0x24, (a *% 2) | 0x30, misc.kReceiveItem_Tab1[j]);
    oam += 1;
    if (misc.kReceiveItem_Tab1[j] == 0) {
        Ancilla_SetOam(oam, lowWord(x), lowWord(y) +% 8, 0x34, (a *% 2) | 0x30, 0);
        oam += 1;
    }
    return oam;
}

pub export fn Ancilla28_WishPondItem(k: c_int) callconv(.c) void { // 88c6f2
    const i: usize = @intCast(k);
    _ = Ancilla_AllocateOamFromRegion_A_or_D_or_F(k, 0x10);

    if (vars.submodule_index.* == 0 and vars.ancilla_timer[i] == 0) {
        vars.link_picking_throw_state.* = 2;
        vars.link_state_bits.* = 0;
        vars.ancilla_z_vel[i] -%= 2;
        Ancilla_MoveZ(k);
        Ancilla_MoveY(k);
        Ancilla_MoveX(k);
        if (sign8(vars.ancilla_z[i]) and vars.ancilla_z[i] < 228) {
            vars.ancilla_z[i] = 228;
            Ancilla_SetXY(
                k,
                // The C reads the item-shape table here rather than an x offset.
                Ancilla_GetX(k) +% @as(u16, if (kGeneratedWishPondItem()[vars.ancilla_item_to_link[i]] != 0) 8 else 4),
                Ancilla_GetY(k) +% 18,
            );
            Ancilla_TransmuteToSplash(k);
            return;
        }
    }
    WishPondItem_Draw(k);
}

pub export fn WishPondItem_Draw(k: c_int) callconv(.c) void { // 88c760
    const i: usize = @intCast(k);
    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);

    if (vars.ancilla_item_to_link[i] == 1) vars.ancilla_arr4[i] = 5;

    const oam = Ancilla_ReceiveItem_Draw(k, pt.x, @as(c_int, pt.y) - @as(i8, @bitCast(vars.ancilla_z[i])));

    if (vars.link_picking_throw_state.* != 2 or
        (!sign8(vars.ancilla_z_vel[i]) and vars.ancilla_z_vel[i] >= 2)) return;

    const xx = kGeneratedWishPondItem()[vars.ancilla_item_to_link[i]];
    AncillaDraw_Shadow(
        oam,
        if (xx == 2) 1 else 2,
        @as(c_int, pt.x) - @as(c_int, if (xx == 2) 0 else 4),
        @as(c_int, pt.y) + 40,
        @truncate(vars.oam_priority_value.* >> 8),
    );
}

pub export fn Ancilla42_HappinessPondRupees(k: c_int) callconv(.c) void { // 88c7de
    vars.link_picking_throw_state.* = 2;
    vars.link_state_bits.* = 0;
    var i: c_int = 9;
    while (i >= 0) : (i -= 1) {
        const u: usize = @intCast(i);
        if (vars.happiness_pond_arr1[u] != 0) {
            HapinessPondRupees_ExecuteRupee(k, i);
            if (vars.happiness_pond_step[u] == 2) vars.happiness_pond_arr1[u] = 0;
        }
    }
    i = 9;
    while (i >= 0) : (i -= 1) {
        if (vars.happiness_pond_arr1[@intCast(i)] != 0) return;
    }
    vars.ancilla_type[@intCast(k)] = 0;
}

pub export fn HapinessPondRupees_ExecuteRupee(k: c_int, i: c_int) callconv(.c) void { // 88c819
    const u: usize = @intCast(k);
    _ = Ancilla_AllocateOamFromRegion_A_or_D_or_F(k, 0x10);
    HapinessPondRupees_GetState(k, i);

    done: {
        if (vars.ancilla_step[u] != 0) {
            if (vars.submodule_index.* == 0 and vars.ancilla_timer[u] == 0) {
                vars.ancilla_timer[u] = 6;
                vars.ancilla_item_to_link[u] +%= 1;
                if (vars.ancilla_item_to_link[u] == 5) {
                    vars.ancilla_step[u] +%= 1;
                } else {
                    ObjectSplash_Draw(k);
                }
            } else {
                ObjectSplash_Draw(k);
            }
            break :done;
        }
        if (vars.submodule_index.* == 0 and vars.ancilla_timer[u] == 0) {
            vars.ancilla_z_vel[u] -%= 2;
            Ancilla_MoveY(k);
            Ancilla_MoveX(k);
            Ancilla_MoveZ(k);
            if (sign8(vars.ancilla_z[u]) and vars.ancilla_z[u] < 0xe4) {
                vars.ancilla_z[u] = 0xe4;
                Ancilla_SetXY(k, Ancilla_GetX(k) -% 4, Ancilla_GetY(k) +% 30);
                vars.ancilla_item_to_link[u] = 0;
                vars.ancilla_timer[u] = 6;
                Ancilla_Sfx2_Pan(k, 0x28);
                vars.ancilla_step[u] +%= 1;
                ObjectSplash_Draw(k);
                break :done;
            }
        }
        vars.ancilla_arr4[u] = 2;
        vars.ancilla_floor[u] = 0;
        WishPondItem_Draw(k);
    }
    HapinessPondRupees_SaveState(i, k);
}

pub export fn HapinessPondRupees_GetState(j: c_int, k: c_int) callconv(.c) void { // 88c8be
    const a: usize = @intCast(j);
    const b: usize = @intCast(k);
    vars.ancilla_y_lo[a] = vars.happiness_pond_y_lo[b];
    vars.ancilla_y_hi[a] = vars.happiness_pond_y_hi[b];
    vars.ancilla_x_lo[a] = vars.happiness_pond_x_lo[b];
    vars.ancilla_x_hi[a] = vars.happiness_pond_x_hi[b];
    vars.ancilla_z[a] = vars.happiness_pond_z[b];
    vars.ancilla_y_vel[a] = vars.happiness_pond_y_vel[b];
    vars.ancilla_x_vel[a] = vars.happiness_pond_x_vel[b];
    vars.ancilla_z_vel[a] = vars.happiness_pond_z_vel[b];
    vars.ancilla_y_subpixel[a] = vars.happiness_pond_y_subpixel[b];
    vars.ancilla_x_subpixel[a] = vars.happiness_pond_x_subpixel[b];
    vars.ancilla_z_subpixel[a] = vars.happiness_pond_z_subpixel[b];
    vars.ancilla_item_to_link[a] = vars.happiness_pond_item_to_link[b];
    vars.ancilla_step[a] = vars.happiness_pond_step[b];
    vars.ancilla_timer[a] = if (vars.happiness_pond_timer[b] != 0) vars.happiness_pond_timer[b] - 1 else 0;
}

pub export fn HapinessPondRupees_SaveState(k: c_int, j: c_int) callconv(.c) void { // 88c924
    const a: usize = @intCast(k);
    const b: usize = @intCast(j);
    vars.happiness_pond_y_lo[a] = vars.ancilla_y_lo[b];
    vars.happiness_pond_y_hi[a] = vars.ancilla_y_hi[b];
    vars.happiness_pond_x_lo[a] = vars.ancilla_x_lo[b];
    vars.happiness_pond_x_hi[a] = vars.ancilla_x_hi[b];
    vars.happiness_pond_z[a] = vars.ancilla_z[b];
    vars.happiness_pond_y_vel[a] = vars.ancilla_y_vel[b];
    vars.happiness_pond_x_vel[a] = vars.ancilla_x_vel[b];
    vars.happiness_pond_z_vel[a] = vars.ancilla_z_vel[b];
    vars.happiness_pond_y_subpixel[a] = vars.ancilla_y_subpixel[b];
    vars.happiness_pond_x_subpixel[a] = vars.ancilla_x_subpixel[b];
    vars.happiness_pond_z_subpixel[a] = vars.ancilla_z_subpixel[b];
    vars.happiness_pond_item_to_link[a] = vars.ancilla_item_to_link[b];
    vars.happiness_pond_timer[a] = vars.ancilla_timer[b];
    vars.happiness_pond_step[a] = vars.ancilla_step[b];
}

pub export fn Ancilla_TransmuteToSplash(k: c_int) callconv(.c) void { // 88c9cd
    const i: usize = @intCast(k);
    vars.ancilla_type[i] = 0x3d;
    vars.ancilla_item_to_link[i] = 0;
    vars.ancilla_timer[i] = 6;
    Ancilla_SetXY(k, Ancilla_GetX(k) -% 8, Ancilla_GetY(k) +% 12);
    Ancilla_Sfx2_Pan(k, 0x28);
    Ancilla3D_ItemSplash(k);
}

pub export fn Ancilla3D_ItemSplash(k: c_int) callconv(.c) void { // 88ca01
    const i: usize = @intCast(k);
    _ = Ancilla_AllocateOamFromRegion_A_or_D_or_F(k, 8);
    if (vars.submodule_index.* == 0 and vars.ancilla_timer[i] == 0) {
        vars.ancilla_timer[i] = 6;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 5) {
            vars.ancilla_type[i] = 0;
            return;
        }
    }
    ObjectSplash_Draw(k);
}

pub export fn ObjectSplash_Draw(k: c_int) callconv(.c) void { // 88ca22
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    var j: usize = @as(usize, vars.ancilla_item_to_link[@intCast(k)]) * 2;
    for (0..2) |_| {
        if (tables.kObjectSplash_Draw_Char[j] != 0xff) {
            Ancilla_SetOam(
                oam,
                pt.x +% signedOffset(tables.kObjectSplash_Draw_X[j]),
                pt.y +% signedOffset(tables.kObjectSplash_Draw_Y[j]),
                tables.kObjectSplash_Draw_Char[j],
                tables.kObjectSplash_Draw_Flags[j] | 0x24,
                tables.kObjectSplash_Draw_Ext[j],
            );
            oam += 1;
        }
        j += 1;
    }
}

pub export fn Ancilla29_MilestoneItemReceipt(k: c_int) callconv(.c) void { // 88ca8c
    const i: usize = @intCast(k);
    if (vars.ancilla_item_to_link[i] != 0x10 and vars.ancilla_item_to_link[i] != 0x0f) {
        if (vars.dung_savegame_state_bits.* & 0x4000 != 0) {
            vars.ancilla_type[i] = 0;
            return;
        }
        if (vars.dung_savegame_state_bits.* & 0x8000 == 0) return;

        if (vars.byte_7E04C2.* != 0) {
            if (vars.byte_7E04C2.* == 1) {
                if (vars.ancilla_item_to_link[i] == 0x20) {
                    vars.sound_effect_ambient.* = 0x0f;
                    load_gfx.DecodeAnimatedSpriteTile_variable(0x28);
                } else {
                    load_gfx.DecodeAnimatedSpriteTile_variable(0x23);
                }
            }
            vars.byte_7E04C2.* -%= 1;
            return;
        }
        if (vars.ancilla_arr3[i] == 0 and vars.ancilla_item_to_link[i] == 0x20) {
            vars.ancilla_arr3[i] = 1;
            vars.palette_sp6r_indoors.* = 4;
            vars.overworld_palette_aux_or_main.* = 0x200;
            load_gfx.Palette_Load_SpriteEnvironment_Dungeon();
            vars.flag_update_cgram_in_nmi.* +%= 1;
        }
    } else {
        if (vars.ancilla_G[i] != 0) {
            vars.ancilla_G[i] -%= 1;
            return;
        }
    }

    if (vars.ancilla_item_to_link[i] == 0x20) AncillaAdd_OccasionalSparkle(k);

    if (vars.submodule_index.* == 0) {
        var coll_out: CheckPlayerCollOut = undefined;
        if (vars.ancilla_z[i] < 24 and Ancilla_CheckLinkCollision(k, 2, &coll_out) and
            vars.related_to_hookshot.* == 0 and vars.link_auxiliary_state.* == 0)
        {
            vars.ancilla_type[i] = 0;
            if (vars.link_player_handler_state.* == kPlayerState_ReceivingEther or
                vars.link_player_handler_state.* == kPlayerState_ReceivingBombos)
            {
                vars.flag_custom_spell_anim_active.* = 0;
                vars.link_force_hold_sword_up.* = 0;
                vars.link_player_handler_state.* = 0;
            }
            vars.item_receipt_method.* = 3;
            player.Link_ReceiveItem(vars.ancilla_item_to_link[i], 0);
            return;
        }

        if (vars.ancilla_step[i] != 2) {
            if (vars.ancilla_step[i] != 0) vars.ancilla_z_vel[i] -%= 1;
            Ancilla_MoveZ(k);
            if (vars.ancilla_z[i] >= 0xf8) {
                vars.ancilla_step[i] +%= 1;
                vars.ancilla_z_vel[i] = 0x18;
                vars.ancilla_z[i] = 0;
            }
        }
    }

    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    const oam = Ancilla_ReceiveItem_Draw(k, pt.x, @as(c_int, pt.y) - @as(c_int, vars.ancilla_z[i]));

    vars.ancilla_aux_timer[i] -%= 1;
    if (sign8(vars.ancilla_aux_timer[i])) {
        vars.ancilla_aux_timer[i] = 9;
        vars.ancilla_L[i] +%= 1;
        if (vars.ancilla_L[i] == 3) vars.ancilla_L[i] = 0;
    }

    const t: c_int = if (vars.ancilla_z[i] == 0)
        (if (vars.dungeon_room_index.* == 6) @as(c_int, vars.ancilla_L[i]) + 4 else 0)
    else if (vars.ancilla_z[i] < 0x20) 1 else 2;
    AncillaDraw_Shadow(oam, t, pt.x, @as(c_int, pt.y) + 12, 0x20);
}

pub export fn ItemReceipt_TransmuteToRisingCrystal(k: c_int) callconv(.c) void { // 88cbe4
    const i: usize = @intCast(k);
    vars.ancilla_type[i] = 0x3e;
    vars.ancilla_y_vel[i] = 0;
    vars.ancilla_x_vel[i] = 0;
    vars.ancilla_y_subpixel[i] = 0;
    Ancilla_RisingCrystal(k);
}

pub export fn Ancilla_RisingCrystal(k: c_int) callconv(.c) void { // 88cbf2
    const i: usize = @intCast(k);
    vars.ancilla_z[i] = 0;
    AncillaAdd_OccasionalSparkle(k);
    var yy = vars.ancilla_y_vel[i] -% 1;
    if (yy < 0xf0) yy = 0xf0;
    vars.ancilla_y_vel[i] = yy;
    Ancilla_MoveY(k);

    const y = Ancilla_GetY(k) -% vars.BG2VOFS_copy.*;
    if (y < 0x49) {
        Ancilla_SetY(k, 0x49 +% vars.BG2VOFS_copy.*);
        if (vars.submodule_index.* == 0) {
            vars.link_has_crystals.* |= rtl.kDungeonCrystalPendantBit[@as(u8, @truncate(vars.cur_palace_index_x2.*)) >> 1];
            vars.submodule_index.* = 0x18;
            vars.subsubmodule_index.* = 0;
            @memset(vars.aux_palette_buffer[0x20 .. 0x20 + 0x60], 0);
            vars.palette_filter_countdown.* = 0;
            vars.darkening_or_lightening_screen.* = 0;
        }
    }

    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    _ = Ancilla_ReceiveItem_Draw(k, pt.x, pt.y);
}

pub export fn AncillaAdd_OccasionalSparkle(k: c_int) callconv(.c) void { // 88cc93
    if (vars.frame_counter.* & 7 == 0) AncillaAdd_SwordChargeSparkle(k);
}

// ---------------------------------------------------------------------------
// Ganon's Tower cutscene, weathervane, flute, and poofs.
// ---------------------------------------------------------------------------

pub export fn Ancilla43_GanonsTowerCutscene(k: c_int) callconv(.c) void { // 88cca0
    const i: usize = @intCast(k);
    var oam = GetOamCurPtr();

    label_a: {
        label_b: {
            lbl_else: {
                if (vars.ancilla_step[i] == 0) {
                    const yy = vars.ancilla_y_vel[i] -% 1;
                    vars.ancilla_y_vel[i] = if (yy < 0xf0) 0xf0 else yy;
                    Ancilla_MoveY(k);
                    const x = Ancilla_GetX(k);
                    const y = Ancilla_GetY(k);
                    if (y -% vars.BG2VOFS_copy.* >= 0x38) break :lbl_else;
                    vars.breaktowerseal_y.* = 0x38 + 8 +% vars.BG2VOFS_copy.*;
                    vars.breaktowerseal_x.* = x +% 8;
                    Ancilla_SetY(k, 0x38 +% vars.BG2VOFS_copy.*);
                    vars.ancilla_step[i] +%= 1;
                    vars.sound_effect_ambient.* = 5;
                    vars.music_control.* = 0xf1;
                    vars.dialogue_message_index.* = 0x13b;
                    misc.Main_ShowTextMessage();
                    break :label_a;
                }
            }
            // lbl_else
            if (vars.ancilla_step[i] == 1 and vars.submodule_index.* == 0) {
                vars.ancilla_x_vel[i] = 16;
                const bak0 = vars.ancilla_x_lo[i];
                const bak1 = vars.ancilla_x_hi[i];
                vars.ancilla_x_lo[i] = vars.breaktowerseal_var4.*;
                vars.ancilla_x_hi[i] = 0;
                Ancilla_MoveX(k);
                vars.breaktowerseal_var4.* = vars.ancilla_x_lo[i];
                vars.ancilla_x_lo[i] = bak0;
                vars.ancilla_x_hi[i] = bak1;
                if (vars.breaktowerseal_var4.* >= 48) {
                    vars.breaktowerseal_var4.* = 48;
                    vars.ancilla_step[i] +%= 1;
                }
            }
            if (vars.submodule_index.* != 0) break :label_b;
            if (vars.ancilla_step[i] == 0) break :label_a;
            if (vars.ancilla_step[i] == 1) break :label_b;
            if (vars.ancilla_step[i] == 2) {
                vars.breaktowerseal_var5.* -%= 1;
                if (vars.breaktowerseal_var5.* == 0) {
                    vars.trigger_special_entrance.* = 5;
                    vars.subsubmodule_index.* = 0;
                    loPtr(vars.R16).* = 0;
                    vars.ancilla_step[i] +%= 1;
                }
            } else {
                vars.ancilla_x_vel[i] = 48;
                const bak0 = vars.ancilla_x_lo[i];
                const bak1 = vars.ancilla_x_hi[i];
                vars.ancilla_x_lo[i] = vars.breaktowerseal_var4.*;
                vars.ancilla_x_hi[i] = 0;
                Ancilla_MoveX(k);
                vars.breaktowerseal_var4.* = vars.ancilla_x_lo[i];
                vars.ancilla_x_lo[i] = bak0;
                vars.ancilla_x_hi[i] = bak1;
                if (vars.breaktowerseal_var4.* >= 240) {
                    vars.palette_sp6r_indoors.* = 0;
                    vars.overworld_palette_aux_or_main.* = 0x200;
                    load_gfx.Palette_Load_SpriteEnvironment_Dungeon();
                    vars.flag_update_cgram_in_nmi.* +%= 1;
                    vars.ancilla_type[i] = 0;
                    return;
                }
            }
        }
        // label_b
        const astep = vars.ancilla_step[i];
        if (astep != 0) oam = GTCutscene_SparkleALot(oam);

        var j: c_int = 6;
        while (j >= 0) : (j -= 1) {
            const u: usize = @intCast(j);
            if (vars.submodule_index.* == 0 and astep != 1 and vars.frame_counter.* & 1 == 0)
                vars.breaktowerseal_var3[u] = (vars.breaktowerseal_var3[u] +% 1) & 63;
            const arp = Ancilla_GetRadialProjection(vars.breaktowerseal_var3[u], vars.breaktowerseal_var4.*);
            const x = (if (arp.r6 != 0) -@as(i32, arp.r4) else @as(i32, arp.r4)) +
                @as(i32, vars.breaktowerseal_x.*) - 8 - @as(i32, vars.BG2HOFS_copy.*);
            const y = (if (arp.r2 != 0) -@as(i32, arp.r0) else @as(i32, arp.r0)) +
                @as(i32, vars.breaktowerseal_y.*) - 8 - @as(i32, vars.BG2VOFS_copy.*);

            vars.breaktowerseal_base_sparkle_x_lo[u] = @truncate(@as(u32, @bitCast(x)));
            vars.breaktowerseal_base_sparkle_x_hi[u] = @truncate(@as(u32, @bitCast(x)) >> 8);
            vars.breaktowerseal_base_sparkle_y_lo[u] = @truncate(@as(u32, @bitCast(y)));
            vars.breaktowerseal_base_sparkle_y_hi[u] = @truncate(@as(u32, @bitCast(y)) >> 8);

            AncillaDraw_GTCutsceneCrystal(oam, x, y);
            oam += 1;
        }
    }
    // label_a
    var info: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &info);

    vars.breaktowerseal_base_sparkle_x_lo[7] = @truncate(info.x);
    vars.breaktowerseal_base_sparkle_x_hi[7] = @truncate(info.x >> 8);
    vars.breaktowerseal_base_sparkle_y_lo[7] = @truncate(info.y);
    vars.breaktowerseal_base_sparkle_y_hi[7] = @truncate(info.y >> 8);

    AncillaDraw_GTCutsceneCrystal(oam, info.x, info.y);

    if (vars.ancilla_step[i] == 0) {
        AncillaAdd_OccasionalSparkle(k);
    } else if (vars.submodule_index.* == 0) {
        GTCutscene_ActivateSparkle();
    }
}

pub export fn AncillaDraw_GTCutsceneCrystal(oam: [*]align(1) OamEnt, x: c_int, y: c_int) callconv(.c) void { // 88ceaa
    Ancilla_SetOam_Safe(oam, lowWord(x), lowWord(y), 0x24, 0x3c, 2);
}

pub export fn GTCutscene_ActivateSparkle() callconv(.c) void { // 88cec7
    var k: c_int = 0x17;
    while (k >= 0) : (k -= 1) {
        const u: usize = @intCast(k);
        if (vars.breaktowerseal_sparkle_var1[u] != 0xff) continue;
        vars.breaktowerseal_sparkle_var1[u] = 0;
        vars.breaktowerseal_sparkle_var2[u] = 4;
        const r: i32 = misc.GetRandomNumber();
        const b: usize = @intCast(k & 7);
        const x = (@as(i32, vars.breaktowerseal_base_sparkle_x_hi[b]) << 8 |
            @as(i32, vars.breaktowerseal_base_sparkle_x_lo[b])) + (r >> 4);
        const y = (@as(i32, vars.breaktowerseal_base_sparkle_y_hi[b]) << 8 |
            @as(i32, vars.breaktowerseal_base_sparkle_y_lo[b])) + (r & 0xf);
        vars.breaktowerseal_sparkle_x_lo[u] = @truncate(@as(u32, @bitCast(x)));
        vars.breaktowerseal_sparkle_x_hi[u] = @truncate(@as(u32, @bitCast(x)) >> 8);
        vars.breaktowerseal_sparkle_y_lo[u] = @truncate(@as(u32, @bitCast(y)));
        vars.breaktowerseal_sparkle_y_hi[u] = @truncate(@as(u32, @bitCast(y)) >> 8);
        return;
    }
}

pub export fn GTCutscene_SparkleALot(oam_in: [*]align(1) OamEnt) callconv(.c) [*]align(1) OamEnt { // 88cf35
    var oam = oam_in;
    var k: c_int = 0x17;
    while (k >= 0) : (k -= 1) {
        const u: usize = @intCast(k);
        if (vars.breaktowerseal_sparkle_var1[u] == 0xff) continue;

        vars.breaktowerseal_sparkle_var2[u] -%= 1;
        if (sign8(vars.breaktowerseal_sparkle_var2[u])) {
            vars.breaktowerseal_sparkle_var2[u] = 4;
            vars.breaktowerseal_sparkle_var1[u] +%= 1;
            if (vars.breaktowerseal_sparkle_var1[u] == 3) {
                vars.breaktowerseal_sparkle_var1[u] = 0xff;
                continue;
            }
        }

        const x = @as(u16, vars.breaktowerseal_sparkle_x_hi[u]) << 8 | vars.breaktowerseal_sparkle_x_lo[u];
        const y = @as(u16, vars.breaktowerseal_sparkle_y_hi[u]) << 8 | vars.breaktowerseal_sparkle_y_lo[u];
        const j: usize = vars.breaktowerseal_sparkle_var1[u];
        Ancilla_SetOam(oam, x, y, tables.kSwordChargeSpark_Char[j], tables.kSwordChargeSpark_Flags[j] | 0x30, 0);
        oam += 1;
    }
    return oam;
}

pub export fn Ancilla36_Flute(k: c_int) callconv(.c) void { // 88cfaa
    const i: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        if (vars.ancilla_step[i] != 3) {
            vars.ancilla_z_vel[i] -%= 2;
            Ancilla_MoveX(k);
            Ancilla_MoveZ(k);
            if (sign8(vars.ancilla_z[i]) or vars.ancilla_z[i] >= 0xf0) {
                vars.ancilla_step[i] +%= 1;
                vars.ancilla_z_vel[i] = tables.kFlute_Vels[vars.ancilla_step[i]];
                vars.ancilla_z[i] = 0;
            }
        } else {
            var coll_out: CheckPlayerCollOut = undefined;
            if (Ancilla_CheckLinkCollision(k, 2, &coll_out) and vars.related_to_hookshot.* == 0 and
                vars.link_auxiliary_state.* == 0)
            {
                vars.ancilla_type[i] = 0;
                vars.item_receipt_method.* = 0;
                player.Link_ReceiveItem(0x14, 0);
                return;
            }
        }
    }

    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    const oam = GetOamCurPtr();
    Ancilla_SetOam(oam, pt.x, pt.y -% signedOffset(@as(i8, @bitCast(vars.ancilla_z[i]))), 0x24, @as(u8, @truncate(vars.oam_priority_value.* >> 8)) | 4, 2);
    if (oam[0].y == 0xf0) vars.ancilla_type[i] = 0;
}

pub export fn Ancilla37_WeathervaneExplosion(k: c_int) callconv(.c) void { // 88d03d
    const i: usize = @intCast(k);
    vars.weathervane_var2.* -%= 1;
    if (vars.weathervane_var2.* != 0) return;
    vars.weathervane_var2.* = 1;
    if (vars.weathervane_var1.* == 0) {
        vars.weathervane_var1.* = 1;
        vars.music_control.* = 0xf3;
    }
    vars.ancilla_G[i] -%= 1;
    if (vars.ancilla_G[i] != 0) return;
    vars.ancilla_G[i] = 1;
    if (vars.ancilla_arr3[i] == 0) {
        vars.ancilla_arr3[i] +%= 1;
        _ = misc.Ancilla_Sfx2_Near(0xc);
    }
    if (vars.ancilla_step[i] == 0) {
        vars.ancilla_aux_timer[i] -%= 1;
        if (sign8(vars.ancilla_aux_timer[i])) {
            vars.ancilla_step[i] = 1;
            overworld.Overworld_AlterWeathervane();
            AncillaAdd_CutsceneDuck(0x38, 0);
        }
    }
    vars.weathervane_var13.* = @truncate(@as(u32, @bitCast(k)));
    vars.weathervane_var14.* = 0;
    var n: c_int = 11;
    while (n >= 0) : (n -= 1) {
        const u: usize = @intCast(n);
        if (vars.weathervane_arr12[u] == 0xff) continue;
        vars.weathervane_arr11[u] -%= 1;
        if (sign8(vars.weathervane_arr11[u])) {
            vars.weathervane_arr11[u] = 1;
            vars.weathervane_arr12[u] ^= 1;
        }

        vars.ancilla_item_to_link[i] = vars.weathervane_arr12[u];
        vars.ancilla_y_lo[i] = vars.weathervane_arr6[u];
        vars.ancilla_y_hi[i] = vars.weathervane_arr7[u];
        vars.ancilla_x_lo[i] = vars.weathervane_arr8[u];
        vars.ancilla_x_hi[i] = vars.weathervane_arr9[u];
        vars.ancilla_z[i] = vars.weathervane_arr10[u];
        vars.ancilla_y_vel[i] = vars.weathervane_arr3[u];
        vars.ancilla_x_vel[i] = vars.weathervane_arr4[u];
        vars.ancilla_z_vel[i] = vars.weathervane_arr5[u] -% 1;
        vars.weathervane_arr5[u] = vars.ancilla_z_vel[i];

        Ancilla_MoveY(k);
        Ancilla_MoveX(k);
        Ancilla_MoveZ(k);

        const c: u8 = if (vars.ancilla_z[i] < 0xf0) 0 else 0xff;
        AncillaDraw_WeathervaneExplosionWoodDebris(k);
        if (sign8(c)) vars.weathervane_arr12[u] = c;
        vars.weathervane_arr6[u] = vars.ancilla_y_lo[i];
        vars.weathervane_arr7[u] = vars.ancilla_y_hi[i];
        vars.weathervane_arr8[u] = vars.ancilla_x_lo[i];
        vars.weathervane_arr9[u] = vars.ancilla_x_hi[i];
        vars.weathervane_arr10[u] = vars.ancilla_z[i];
    }
    n = 11;
    while (n >= 0) : (n -= 1) {
        if (vars.weathervane_arr12[@intCast(n)] != 0xff) return;
    }
    vars.ancilla_type[i] = 0;
}

pub export fn AncillaDraw_WeathervaneExplosionWoodDebris(k: c_int) callconv(.c) void { // 88d188
    const i: usize = @intCast(k);
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    pt.y -%= signedOffset(@as(i8, @bitCast(vars.ancilla_z[i])));
    const j = vars.ancilla_item_to_link[i];
    if (sign8(j)) return;
    Ancilla_SetOam(GetOamCurPtr() + (vars.weathervane_var14.* >> 2), pt.x, pt.y, tables.kWeathervane_Explode_Char[j], 0x3c, 0);
    vars.weathervane_var14.* +%= 4;
}

pub export fn Ancilla38_CutsceneDuck(k: c_int) callconv(.c) void { // 88d1d8
    const i: usize = @intCast(k);

    if (vars.frame_counter.* & 31 == 0) Ancilla_Sfx3_Pan(k, 0x1e);

    vars.ancilla_arr3[i] -%= 1;
    if (sign8(vars.ancilla_arr3[i])) {
        vars.ancilla_arr3[i] = 3;
        vars.ancilla_K[i] ^= 1;
    }

    after_stuff: {
        vars.ancilla_aux_timer[i] -%= 1;
        if (vars.ancilla_aux_timer[i] != 0) break :after_stuff;
        vars.ancilla_aux_timer[i] = 1;
        if (vars.ancilla_L[i] == 0) {
            vars.ancilla_item_to_link[i] -%= 1;
            if (!sign8(vars.ancilla_item_to_link[i])) {
                if (vars.ancilla_step[i] != 0) {
                    vars.ancilla_z_vel[i] +%= 1;
                } else {
                    vars.ancilla_z_vel[i] -%= 1;
                }
                if (abs8(vars.ancilla_z_vel[i]) >= 12) vars.ancilla_step[i] ^= 1;
                break :after_stuff;
            }
            vars.ancilla_item_to_link[i] = 0;
            vars.ancilla_x_vel[i] = tables.kTravelBirdIntro_Tab1[0];
            vars.ancilla_z_vel[i] = 0 -% @as(u8, 16);
            vars.ancilla_L[i] +%= 1;
            vars.ancilla_step[i] = 3;
        }
        if (vars.ancilla_step[i] & 1 == 0) {
            vars.ancilla_x_vel[i] +%= 1;
        } else {
            vars.ancilla_x_vel[i] -%= 1;
        }
        const absx = abs8(vars.ancilla_x_vel[i]);
        if (absx == 0) {
            vars.ancilla_L[i] +%= 1;
            if (vars.ancilla_L[i] == 7) vars.ancilla_S[i] = 1;
        }
        if (absx >= tables.kTravelBirdIntro_Tab1[vars.ancilla_S[i]]) vars.ancilla_step[i] ^= 3;
        vars.ancilla_dir[i] = if (sign8(vars.ancilla_x_vel[i])) 2 else 3;
        const t = (tables.kTravelBirdIntro_Tab1[vars.ancilla_S[i]] -% absx) >> 1;
        vars.ancilla_z_vel[i] = if (vars.ancilla_step[i] & 2 != 0) 0 -% t else t;
    }
    Ancilla_MoveX(k);
    Ancilla_MoveZ(k);
    loPtr(vars.flag_travel_bird).* = tables.kTravelBird_DmaStuffs[vars.ancilla_K[i] + 1];
    var info: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &info);
    var oam = GetOamCurPtr();
    Ancilla_SetOam(
        oam,
        info.x +% signedOffset(tables.kTravelBird_Draw_X[0]),
        info.y +% signedOffset(@as(i8, @bitCast(vars.ancilla_z[i]))) +% signedOffset(tables.kTravelBird_Draw_Y[0]),
        tables.kTravelBird_Draw_Char[0],
        tables.kTravelBird_Draw_Flags[0] | 0x30 | tables.kTravelBirdIntro_Tab0[vars.ancilla_dir[i] & 1],
        2,
    );
    oam += 1;
    AncillaDraw_Shadow(oam, 1, info.x, @as(c_int, info.y) + 48, 0x30);
    if (!sign16(info.x) and info.x >= 248) {
        vars.ancilla_type[i] = 0;
        vars.submodule_index.* = 0;
        vars.link_item_flute.* = 3;
    }
}

pub export fn Ancilla23_LinkPoof(k: c_int) callconv(.c) void { // 88d3bc
    const i: usize = @intCast(k);
    vars.ancilla_aux_timer[i] -%= 1;
    if (sign8(vars.ancilla_aux_timer[i])) {
        vars.ancilla_aux_timer[i] = 7;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 3) {
            vars.ancilla_type[i] = 0;
            vars.link_is_transforming.* = 0;
            vars.link_cant_change_direction.* = 0;
            if (vars.ancilla_step[i] == 0) {
                vars.link_animation_steps.* = 0;
                vars.link_visibility_status.* = 0;
                vars.link_is_bunny.* = if (@as(u8, @truncate(vars.overworld_screen_index.*)) & 0x40 != 0) 1 else 0;
                vars.link_is_bunny_mirror.* = vars.link_is_bunny.*;
                if (vars.link_is_bunny.* != 0) {
                    load_gfx.LoadGearPalettes_bunny();
                } else {
                    load_gfx.LoadActualGearPalettes();
                }
            }
            return;
        }
    }
    MorphPoof_Draw(k);
}

pub export fn MorphPoof_Draw(k: c_int) callconv(.c) void { // 88d3fd
    const i: usize = @intCast(k);
    if (vars.sort_sprites_setting.* != 0 and vars.ancilla_floor[i] != 0 and
        (vars.flag_for_boomerang_in_place.* == 0 or vars.frame_counter.* & 1 == 0))
    {
        vars.oam_cur_ptr.* = 0x8d0;
        vars.oam_ext_cur_ptr.* = 0xa20 + (0xd0 >> 2);
    }
    var info: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &info);
    var oam = GetOamCurPtr();
    const j: usize = vars.ancilla_item_to_link[i];
    const ext = tables.kMorphPoof_Ext[j];
    const chr = tables.kMorphPoof_Char[j];
    for (0..4) |n| {
        Ancilla_SetOam(
            oam,
            info.x +% signedOffset(tables.kMorphPoof_X[j * 4 + n]),
            info.y +% signedOffset(tables.kMorphPoof_Y[j * 4 + n]),
            chr,
            tables.kMorphPoof_Flags[j * 4 + n] | 4 | @as(u8, @truncate(vars.oam_priority_value.* >> 8)),
            ext,
        );
        if (ext == 2) break;
        oam += 1;
    }
}

pub export fn Ancilla40_DwarfPoof(k: c_int) callconv(.c) void { // 88d49a
    const i: usize = @intCast(k);
    vars.ancilla_aux_timer[i] -%= 1;
    if (sign8(vars.ancilla_aux_timer[i])) {
        vars.ancilla_aux_timer[i] = 7;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 3) {
            vars.ancilla_type[i] = 0;
            vars.tagalong_var5.* = 0;
            return;
        }
    }
    MorphPoof_Draw(k);
}

pub export fn Ancilla3F_BushPoof(k: c_int) callconv(.c) void { // 88d519
    const i: usize = @intCast(k);
    if (vars.ancilla_timer[i] == 0) {
        vars.ancilla_timer[i] = 7;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 4) {
            vars.ancilla_type[i] = 0;
            return;
        }
    }
    _ = sprite.Oam_AllocateFromRegionC(0x10);
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);
    var oam = GetOamCurPtr();

    var j: usize = @as(usize, vars.ancilla_item_to_link[i]) * 4;
    for (0..4) |_| {
        Ancilla_SetOam(
            oam,
            pt.x +% signedOffset(tables.kBushPoof_Draw_X[j]),
            pt.y +% signedOffset(tables.kBushPoof_Draw_Y[j]),
            tables.kBushPoof_Draw_Char[j],
            tables.kBushPoof_Draw_Flags[j] | 4 | @as(u8, @truncate(vars.oam_priority_value.* >> 8)),
            0,
        );
        j += 1;
        oam += 1;
    }
}

// ---------------------------------------------------------------------------
// Spin attack sparkles, Byrna sparks, sword beam, and the duck.
// ---------------------------------------------------------------------------

pub export fn Ancilla26_SwordSwingSparkle(k: c_int) callconv(.c) void { // 88d65a
    const i: usize = @intCast(k);
    vars.ancilla_aux_timer[i] -%= 1;
    if (sign8(vars.ancilla_aux_timer[i])) {
        vars.ancilla_aux_timer[i] = 0;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 4) {
            vars.ancilla_type[i] = 0;
            return;
        }
    }
    Ancilla_SetXY(k, vars.link_x_coord.*, vars.link_y_coord.*);

    var info: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &info);

    var j: usize = @as(usize, vars.ancilla_item_to_link[i]) * 3 + @as(usize, vars.ancilla_dir[i]) * 12;

    var oam = GetOamCurPtr();
    for (0..3) |_| {
        const chr = tables.kSwordSwingSparkle_Char[j];
        if (chr != 0xff) {
            Ancilla_SetOam(
                oam,
                info.x +% signedOffset(tables.kSwordSwingSparkle_X[j]),
                info.y +% signedOffset(tables.kSwordSwingSparkle_Y[j]),
                chr,
                tables.kSwordSwingSparkle_Flags[j] | 0x4 | @as(u8, @truncate(vars.oam_priority_value.* >> 8)),
                0,
            );
        }
        j += 1;
        oam += 1;
    }
}

pub export fn Ancilla2A_SpinAttackSparkleA(k: c_int) callconv(.c) void { // 88d7b2
    const i: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        vars.ancilla_aux_timer[i] -%= 1;
        if (sign8(vars.ancilla_aux_timer[i])) {
            vars.ancilla_aux_timer[i] = 0;
            if (vars.ancilla_timer[i] == 0) {
                vars.ancilla_item_to_link[i] +%= 1;
                const j = vars.ancilla_item_to_link[i];
                vars.ancilla_timer[i] = tables.kInitialSpinSpark_Timer[j];
                if (j == 5) {
                    if (vars.ancilla_step[i] != 0) {
                        AddSwordBeam(j);
                    } else {
                        SpinAttackSparkleA_TransmuteToNextSpark(k);
                    }
                    return;
                }
            }
        }
    }
    if (vars.ancilla_item_to_link[i] == 0) return;
    SpinSpark_Draw(k, -1);
}

pub export fn SpinAttackSparkleA_TransmuteToNextSpark(k: c_int) callconv(.c) void { // 88d86d
    const i: usize = @intCast(k);
    vars.ancilla_type[i] = 0x2b;
    const j: usize = @as(usize, vars.link_direction_facing.*) * 2;
    swordbeam_arr()[0] = tables.kTransmuteSpinSpark_Arr[j + 0];
    swordbeam_arr()[1] = tables.kTransmuteSpinSpark_Arr[j + 1];
    swordbeam_arr()[2] = tables.kTransmuteSpinSpark_Arr[j + 2];
    swordbeam_arr()[3] = tables.kTransmuteSpinSpark_Arr[j + 3];
    swordbeam_var1().* = tables.kTransmuteSpinSpark_Arr[j + 3];
    vars.ancilla_aux_timer[i] = 2;
    vars.ancilla_item_to_link[i] = 0x4c;
    vars.ancilla_arr3[i] = 8;
    vars.ancilla_step[i] = 0;
    vars.ancilla_L[i] = 0;
    vars.ancilla_arr1[i] = 255;
    swordbeam_var2().* = 20;

    swordbeam_temp_x().* = vars.link_x_coord.* +% 8;
    swordbeam_temp_y().* = vars.link_y_coord.* +% 12;

    const d: usize = vars.link_direction_facing.* >> 1;
    Ancilla_SetXY(
        k,
        vars.link_x_coord.* +% signedOffset(tables.kTransmuteSpinSpark_X[d]),
        vars.link_y_coord.* +% signedOffset(tables.kTransmuteSpinSpark_Y[d]),
    );
    Ancilla2B_SpinAttackSparkleB(k);
}

pub export fn Ancilla2B_SpinAttackSparkleB(k: c_int) callconv(.c) void { // 88d8fd
    const i: usize = @intCast(k);
    if (vars.ancilla_L[i] != 0) {
        SpinAttackSparkleB_Closer(k);
        return;
    }
    var flags: u8 = 2;
    if (vars.submodule_index.* == 0) {
        vars.ancilla_item_to_link[i] -%= 3;
        const t = vars.ancilla_item_to_link[i];
        if (t < 13) {
            vars.ancilla_aux_timer[i] = 1;
            vars.ancilla_L[i] = 1;
            vars.ancilla_item_to_link[i] = 0;
            SpinAttackSparkleB_Closer(k);
            return;
        }
        vars.ancilla_step[i] = if (t < 0x42) 3 else if (t == 0x46) 1 else if (t == 0x43) 2 else 0;
        vars.ancilla_aux_timer[i] -%= 1;
        if (sign8(vars.ancilla_aux_timer[i])) {
            flags = 4;
            vars.ancilla_aux_timer[i] = 2;
        }
    }
    var oam = GetOamCurPtr();
    const oam_org = oam;
    var n: c_int = vars.ancilla_step[i];
    while (true) {
        const u: usize = @intCast(n);
        if (vars.submodule_index.* == 0)
            swordbeam_arr()[u] = (swordbeam_arr()[u] +% 4) & 0x3f;
        const pt = Sparkle_PrepOamFromRadial(Ancilla_GetRadialProjection(swordbeam_arr()[u], swordbeam_var2().*));
        Ancilla_SetOam(oam, pt.x, pt.y, tables.kSpinSpark_Char[u], flags | @as(u8, @truncate(vars.oam_priority_value.* >> 8)), 0);
        oam += 1;
        n -= 1;
        if (n < 0) break;
    }

    endif_2: {
        if (vars.submodule_index.* == 0) {
            vars.ancilla_arr3[i] -%= 1;
            if (!sign8(vars.ancilla_arr3[i])) break :endif_2;
            vars.ancilla_arr3[i] = 0;
            vars.ancilla_arr1[i] = (vars.ancilla_arr1[i] +% 1) & 3;
            if (vars.ancilla_arr1[i] == 3)
                swordbeam_var1().* = (swordbeam_var1().* +% 9) & 0x3f;
        }
        const t = vars.ancilla_arr1[i];
        if (t != 3) {
            const pt = Sparkle_PrepOamFromRadial(Ancilla_GetRadialProjection(swordbeam_var1().*, swordbeam_var2().*));
            Ancilla_SetOam(oam, pt.x, pt.y, tables.kSpinSpark_Char2[t], 4 | @as(u8, @truncate(vars.oam_priority_value.* >> 8)), 0);
        }
    }
    if (vars.ancilla_item_to_link[i] == 7)
        vars.bytewise_extended_oam[oamIndex(oam_org) + 3] = 1;
}

pub export fn Sparkle_PrepOamFromRadial(p: AncillaRadialProjection) callconv(.c) Point16U { // 88da17
    return .{
        .x = (if (p.r6 != 0) 0 -% @as(u16, p.r4) else @as(u16, p.r4)) +% swordbeam_temp_x().* -% 4 -% vars.BG2HOFS_copy2.*,
        .y = (if (p.r2 != 0) 0 -% @as(u16, p.r0) else @as(u16, p.r0)) +% swordbeam_temp_y().* -% 4 -% vars.BG2VOFS_copy2.*,
    };
}

pub export fn SpinAttackSparkleB_Closer(k: c_int) callconv(.c) void { // 88da4c
    const i: usize = @intCast(k);
    vars.ancilla_aux_timer[i] -%= 1;
    if (sign8(vars.ancilla_aux_timer[i])) {
        vars.ancilla_aux_timer[i] = 1;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 3) vars.ancilla_type[i] = 0;
    }
    SpinSpark_Draw(k, 4);
}

pub export fn Ancilla30_ByrnaWindupSpark(k: c_int) callconv(.c) void { // 88db24
    const i: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        vars.ancilla_aux_timer[i] -%= 1;
        if (sign8(vars.ancilla_aux_timer[i])) {
            vars.ancilla_aux_timer[i] = 1;
            vars.ancilla_item_to_link[i] +%= 1;
            if (vars.ancilla_item_to_link[i] == 17) {
                ByrnaWindupSpark_TransmuteToNormal(k);
                return;
            }
        }
    }
    if (vars.ancilla_item_to_link[i] == 0) return;

    var j: usize = vars.player_handler_timer.*;
    if (j == 2) {
        var a = vars.ancilla_arr3[i] -% 1;
        if (sign8(a)) {
            a = 0;
            j = 3;
        }
        vars.ancilla_arr3[i] = a;
    }
    j += @as(usize, vars.link_direction_facing.*) * 2;
    Ancilla_SetXY(
        k,
        vars.link_x_coord.* +% signedOffset(tables.kInitialCaneSpark_X[j]),
        vars.link_y_coord.* +% signedOffset(tables.kInitialCaneSpark_Y[j]),
    );
    var pt: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &pt);

    const a = (vars.ancilla_item_to_link[i] -% 1) & 0xf;
    var d: usize = 0;
    if (a != 0) d = 4 * @as(usize, if (a != 15) (a & 1) + 1 else 3);

    var oam = GetOamCurPtr();
    for (0..4) |_| {
        if (tables.kInitialCaneSpark_Draw_Char[d] != 255) {
            Ancilla_SetOam(
                oam,
                pt.x +% signedOffset(tables.kInitialCaneSpark_Draw_X[d]),
                pt.y +% signedOffset(tables.kInitialCaneSpark_Draw_Y[d]),
                tables.kInitialCaneSpark_Draw_Char[d],
                (tables.kInitialCaneSpark_Draw_Flags[d] & ~@as(u8, 0x30)) | @as(u8, @truncate(vars.oam_priority_value.* >> 8)),
                0,
            );
            oam += 1;
        }
        d += 1;
    }
}

pub export fn ByrnaWindupSpark_TransmuteToNormal(k: c_int) callconv(.c) void { // 88dc21
    const i: usize = @intCast(k);
    vars.ancilla_type[i] = 0x31;
    const j: usize = @as(usize, vars.link_direction_facing.*) << 1;
    swordbeam_arr()[0] = tables.kCaneSpark_Transmute_Tab[j + 0];
    swordbeam_arr()[1] = tables.kCaneSpark_Transmute_Tab[j + 1];
    swordbeam_arr()[2] = tables.kCaneSpark_Transmute_Tab[j + 2];
    swordbeam_arr()[3] = tables.kCaneSpark_Transmute_Tab[j + 3];
    vars.ancilla_aux_timer[i] = 0x17;
    vars.ancilla_G[i] = 0;
    vars.ancilla_item_to_link[i] = 0;
    vars.ancilla_arr3[i] = 8;
    vars.ancilla_step[i] = 0;
    vars.ancilla_L[i] = 0;
    vars.ancilla_arr1[i] = 2;
    vars.ancilla_timer[i] = 21;
    swordbeam_var2().* = 20;
    misc.Ancilla_Sfx3_Near(0x30);
    Ancilla31_ByrnaSpark(k);
}

/// The `kill_me` label inside Ancilla31_ByrnaSpark.
fn ByrnaSpark_Kill(i: usize) void {
    vars.link_disable_sprite_damage.* = 0;
    vars.ancilla_type[i] = 0;
    vars.link_give_damage.* = 0;
}

pub export fn Ancilla31_ByrnaSpark(k: c_int) callconv(.c) void { // 88dc70
    const i: usize = @intCast(k);
    var flags: u8 = 2;
    if (vars.submodule_index.* == 0) {
        // Byrna has to still be on the button that swung it: Y, or X, L
        // or R with a second item.
        if (!hud.itemStillHeld(13)) {
            ByrnaSpark_Kill(i);
            return;
        }
        vars.link_disable_sprite_damage.* = 1;
        vars.ancilla_aux_timer[i] -%= 1;
        if (vars.ancilla_aux_timer[i] == 0) {
            vars.ancilla_aux_timer[i] = 1;
            var r0 = tables.kCaneSpark_Magic[vars.link_magic_consumption.*];
            if (vars.link_magic_power.* == 0) {
                ByrnaSpark_Kill(i);
                return;
            }
            r0 = vars.link_magic_power.* -% r0;
            if (r0 >= 0x80) {
                ByrnaSpark_Kill(i);
                return;
            }
            vars.ancilla_G[i] -%= 1;
            if (sign8(vars.ancilla_G[i])) {
                vars.ancilla_G[i] = 0x17;
                vars.link_magic_power.* = r0;
            }
            // Y, or the button that swung it, pressed again ends it.
            if (hud.itemButtonPressed()) {
                ByrnaSpark_Kill(i);
                return;
            }
        }
        if (vars.ancilla_step[i] != 3) {
            vars.ancilla_item_to_link[i] +%= 1;
            const a = vars.ancilla_item_to_link[i];
            vars.ancilla_step[i] = if (a >= 4) 3 else if (a == 2) 1 else if (a == 3) 2 else 0;
        }
        vars.ancilla_arr1[i] -%= 1;
        if (sign8(vars.ancilla_arr1[i])) {
            vars.ancilla_arr1[i] = 2;
            flags = 4;
        }
    }

    var z = @as(i8, @bitCast(@as(u8, @truncate(vars.link_z_coord.*))));
    if (z == -1) z = 0;
    swordbeam_temp_y().* = vars.link_y_coord.* +% 12 -% signedOffset(z);
    swordbeam_temp_x().* = vars.link_x_coord.* +% 8;
    if (vars.ancilla_timer[i] == 0) {
        vars.ancilla_timer[i] = 21;
        misc.Ancilla_Sfx3_Near(0x30);
    }
    var oam = GetOamCurPtr();
    var n: c_int = vars.ancilla_step[i];
    while (true) {
        const u: usize = @intCast(n);
        if (vars.submodule_index.* == 0)
            swordbeam_arr()[u] = (swordbeam_arr()[u] +% 3) & 0x3f;
        const pt = Sparkle_PrepOamFromRadial(Ancilla_GetRadialProjection(swordbeam_arr()[u], swordbeam_var2().*));
        Ancilla_SetOam(oam, pt.x, pt.y, tables.kCaneSpark_Char[u], flags | @as(u8, @truncate(vars.oam_priority_value.* >> 8)), 0);
        Ancilla_SetXY(k, pt.x +% vars.BG2HOFS_copy2.*, pt.y +% vars.BG2VOFS_copy2.*);
        vars.ancilla_dir[i] = 0;
        _ = Ancilla_CheckSpriteCollision(k);
        oam += 1;
        n -= 1;
        if (n < 0) break;
    }
}

pub export fn Ancilla_SwordBeam(k: c_int) callconv(.c) void { // 88ddc5
    const i: usize = @intCast(k);
    var flags: u8 = 2;

    if (vars.submodule_index.* == 0) {
        Ancilla_SetXY(k, swordbeam_temp_x().*, swordbeam_temp_y().*);
        Ancilla_MoveX(k);
        Ancilla_MoveY(k);
        swordbeam_temp_x().* = Ancilla_GetX(k);
        swordbeam_temp_y().* = Ancilla_GetY(k);

        if (vars.ancilla_G[i] & 0xf == 0)
            vars.sound_effect_2.* = Ancilla_CalculateSfxPan(k) | 1;
        vars.ancilla_G[i] +%= 1;

        if (Ancilla_CheckSpriteCollision(k) >= 0 or Ancilla_CheckTileCollision(k) != 0) {
            const j: usize = vars.ancilla_dir[i];
            Ancilla_SetXY(
                k,
                Ancilla_GetX(k) +% signedOffset(tables.kSwordBeam_Xvel2[j]),
                Ancilla_GetY(k) +% signedOffset(tables.kSwordBeam_Yvel2[j]),
            );
            vars.ancilla_type[i] = 4;
            vars.ancilla_timer[i] = 7;
            vars.ancilla_numspr[i] = 0x10;
            return;
        }
        vars.ancilla_aux_timer[i] -%= 1;
        if (sign8(vars.ancilla_aux_timer[i])) {
            flags = 4;
            vars.ancilla_aux_timer[i] = 2;
        }
    }

    var oam = GetOamCurPtr();
    const s = vars.ancilla_S[i];
    var n: c_int = 3;
    while (n >= 0) : (n -= 1) {
        const u: usize = @intCast(n);
        if (vars.submodule_index.* == 0)
            swordbeam_arr()[u] = (swordbeam_arr()[u] +% s) & 0x3f;
        const pt = Sparkle_PrepOamFromRadial(Ancilla_GetRadialProjection(swordbeam_arr()[u], swordbeam_var2().*));
        Ancilla_SetOam(oam, pt.x, pt.y, tables.kSwordBeam_Char[u], flags | @as(u8, @truncate(vars.oam_priority_value.* >> 8)), 0);
        oam += 1;
    }

    endif_2: {
        if (vars.submodule_index.* == 0) {
            vars.ancilla_arr3[i] -%= 1;
            if (!sign8(vars.ancilla_arr3[i])) break :endif_2;
            vars.ancilla_arr3[i] = 0;
            vars.ancilla_arr1[i] = (vars.ancilla_arr1[i] +% 1) & 3;
            if (vars.ancilla_arr1[i] == 3)
                swordbeam_var1().* = (swordbeam_var1().* +% s) & 0x3f;
        }
        const t = vars.ancilla_arr1[i];
        if (t != 3) {
            const pt = Sparkle_PrepOamFromRadial(Ancilla_GetRadialProjection(swordbeam_var1().*, swordbeam_var2().*));
            Ancilla_SetOam(oam, pt.x, pt.y, tables.kSwordBeam_Char2[t], 4 | @as(u8, @truncate(vars.oam_priority_value.* >> 8)), 0);
        }
    }
    oam -= 4;
    for (0..4) |m| {
        if (oam[m].y != 0xf0) return;
    }
    vars.ancilla_type[i] = 0;
}

pub export fn Ancilla0D_SpinAttackFullChargeSpark(k: c_int) callconv(.c) void { // 88ddca
    const i: usize = @intCast(k);
    vars.ancilla_oam_idx[i] = @truncate(@as(u32, @bitCast(Ancilla_AllocateOamFromRegion_A_or_D_or_F(k, 4))));

    if (vars.ancilla_timer[i] == 0) {
        vars.ancilla_type[i] = 0;
        return;
    }

    const j: usize = vars.link_direction_facing.* >> 1;

    const x = vars.link_x_coord.* +% signedOffset(tables.kSwordFullChargeSpark_X[j]) -% vars.BG2HOFS_copy2.*;
    const y = vars.link_y_coord.* +% signedOffset(tables.kSwordFullChargeSpark_Y[j]) -% vars.BG2VOFS_copy2.*;

    vars.oam_priority_value.* = @as(u16, tables.kSwordFullChargeSpark_Flags[vars.ancilla_floor[i]]) << 8;
    Ancilla_SetOam(GetOamCurPtr(), x, y, 0xd7, @as(u8, @truncate(vars.oam_priority_value.* >> 8)) | 2, 0);
}

pub export fn Ancilla27_Duck(k: c_int) callconv(.c) void { // 88dde8
    const i: usize = @intCast(k);
    var coll: CheckPlayerCollOut = undefined;
    var j: usize = undefined;

    endif_5: {
        endif_1: {
            if (vars.submodule_index.* != 0) break :endif_1;

            if (vars.ancilla_timer[i] != 0) {
                const xt: u16 = if (features.enhanced_features0.* & features.kFeatures0_ExtendScreen64 != 0) 0x40 else 0;
                Ancilla_SetXY(k, vars.BG2HOFS_copy2.* -% 16 -% xt, vars.link_y_coord.* -% 8);
                return;
            }

            vars.ancilla_G[i] -%= 1;
            if (sign8(vars.ancilla_G[i])) {
                vars.ancilla_G[i] = 0x28;
                Ancilla_Sfx3_Pan(k, 0x1e);
            }

            const rising = if (vars.ancilla_L[i] != 0) true else blk: {
                if (vars.ancilla_step[i] != 0) {
                    vars.flag_unk1.* +%= 1;
                    break :blk true;
                }
                break :blk false;
            };
            if (rising) {
                vars.ancilla_z_vel[i] -%= 1;
                Ancilla_MoveZ(k);
            }
            Ancilla_MoveX(k);

            if (vars.ancilla_L[i] != 0) {
                const x = Ancilla_GetX(k);
                if (vars.ancilla_step[i] != 0) vars.flag_unk1.* +%= 1;
                if (!sign16(x) and x >= vars.link_x_coord.*) {
                    if (vars.ancilla_step[i] != 0) {
                        vars.ancilla_step[i] = 0;
                        vars.link_visibility_status.* = 0;
                        vars.tagalong_var5.* = 0;
                        vars.link_pose_for_item.* = 0;
                        vars.ancilla_y_vel[i] = 0;
                        vars.flag_is_link_immobilized.* = 0;
                        vars.link_disable_sprite_damage.* = 0;
                        vars.byte_7E03FD.* = 0;
                        vars.countdown_for_blink.* = 144;
                        if (!((vars.follower_indicator.* == 12 or vars.follower_indicator.* == 13) and
                            vars.follower_dropped.* != 0))
                        {
                            tagalong.Follower_Initialize();
                        }
                    }
                } else if (vars.link_x_coord.* -% x < 48) {
                    j = 3;
                    break :endif_5;
                }
                break :endif_1;
            }

            if (!Ancilla_CheckLinkCollision(k, 1, &coll) or vars.main_module_index.* == 15) break :endif_1;

            if (vars.player_is_indoors.* == 0) {
                if (vars.link_player_handler_state.* == 8 or vars.link_player_handler_state.* == 9 or
                    vars.link_player_handler_state.* == 10 or vars.player_near_pit_state.* == 2 or
                    (vars.link_pose_for_item.* | vars.related_to_hookshot.* | vars.link_force_hold_sword_up.* |
                        vars.link_disable_sprite_damage.*) != 0 or
                    vars.link_state_bits.* & 0x80 != 0) break :endif_1;
                var n: c_int = 4;
                while (n >= 0) : (n -= 1) {
                    const a = vars.ancilla_type[@intCast(n)];
                    if (a == 0x2a or a == 0x1f or a == 0x30 or a == 0x31 or a == 0x41)
                        vars.ancilla_type[@intCast(n)] = 0;
                }
                if (vars.follower_indicator.* == 9) {
                    vars.follower_indicator.* = 0;
                    vars.tagalong_var5.* = 0;
                }
            }
            vars.link_state_bits.* = 0;
            vars.link_picking_throw_state.* = 0;

            vars.bg1_x_offset.* = 0;
            vars.bg1_y_offset.* = 0;
            player.Link_ResetProperties_A();
            vars.link_is_in_deep_water.* = 0;
            vars.link_need_for_pullforrupees_sprite.* = 0;
            vars.link_visibility_status.* = 12;
            vars.link_player_handler_state.* = 0;
            vars.link_pose_for_item.* = 1;
            vars.flag_is_link_immobilized.* = 1;
            vars.link_disable_sprite_damage.* = 1;
            vars.tagalong_var5.* = 1;
            vars.ancilla_step[i] = 2;
            vars.flag_unk1.* +%= 1;
            vars.link_give_damage.* = 0;
            if (vars.player_is_indoors.* != 0) vars.byte_7E03FD.* = vars.player_is_indoors.*;
        }
        // endif_1
        vars.ancilla_arr3[i] -%= 1;
        if (sign8(vars.ancilla_arr3[i])) {
            vars.ancilla_arr3[i] = 3;
            vars.ancilla_K[i] +%= 1;
            if (vars.ancilla_K[i] == 3) vars.ancilla_K[i] = 0;
        }
        j = vars.ancilla_K[i];
    }
    // endif_5
    loPtr(vars.flag_travel_bird).* = tables.kTravelBird_DmaStuffs[j];

    var info: Point16U = undefined;
    Ancilla_PrepOamCoord(k, &info);

    var oam = GetOamCurPtr();
    // The C sign-extends the altitude by or-ing in the high byte.
    const z: u16 = if (vars.ancilla_z[i] != 0) 0xff00 | @as(u16, vars.ancilla_z[i]) else 0;
    const count: usize = @as(usize, vars.ancilla_step[i]) + 1;
    for (0..count) |m| {
        Ancilla_SetOam(
            oam,
            info.x +% signedOffset(tables.kTravelBird_Draw_X[m]),
            info.y +% z +% signedOffset(tables.kTravelBird_Draw_Y[m]),
            tables.kTravelBird_Draw_Char[m],
            tables.kTravelBird_Draw_Flags[m] | 0x30,
            2,
        );
        oam += 1;
    }

    AncillaDraw_Shadow(oam, 1, info.x, @as(c_int, info.y) + 28, 0x30);
    oam += 2;
    if (vars.ancilla_step[i] != 0)
        AncillaDraw_Shadow(oam, 1, @as(c_int, info.x) - 7, @as(c_int, info.y) + 28, 0x30);

    if (!sign16(info.x) and info.x >= 0x130) {
        vars.ancilla_type[i] = 0;
        if (vars.ancilla_L[i] == 0 and vars.ancilla_step[i] != 0) {
            vars.submodule_index.* = 10;
            vars.saved_module_for_menu.* = vars.main_module_index.*;
            vars.main_module_index.* = 14;
        }
    }
}

// ---------------------------------------------------------------------------
// Somaria blocks and their collision helpers.
// ---------------------------------------------------------------------------

pub export fn AncillaAdd_SomariaBlock(atype: u8, y: u8) callconv(.c) c_int { // 88e078
    const k = AncillaAdd_AddAncilla_Bank08(atype, y);
    if (k < 0) return k;
    const i: usize = @intCast(k);
    var j: c_int = 4;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        if (j == k or vars.ancilla_type[u] != 0x2c) continue;
        if (j == @as(c_int, vars.flag_is_ancilla_to_pick_up.*) - 1) vars.flag_is_ancilla_to_pick_up.* = 0;
        AncillaAdd_ExplodingSomariaBlock(j);
        vars.ancilla_type[i] = 0;
        vars.dung_flag_somaria_block_switch.* = 0;
        if (vars.link_speed_setting.* == 0x12) {
            vars.bitmask_of_dragstate.* = 0;
            vars.link_speed_setting.* = 0;
        }
        return k;
    }

    misc.Ancilla_Sfx3_Near(0x2a);
    vars.ancilla_step[i] = 0;
    vars.ancilla_y_vel[i] = 0;
    vars.ancilla_x_vel[i] = 0;
    vars.ancilla_item_to_link[i] = 0;
    vars.ancilla_aux_timer[i] = 0;
    vars.ancilla_arr3[i] = 0;
    vars.ancilla_arr1[i] = 0;
    vars.ancilla_H[i] = 0;
    vars.ancilla_G[i] = 12;
    vars.ancilla_timer[i] = 18;
    vars.ancilla_L[i] = 0;
    vars.ancilla_z[i] = 0;
    vars.ancilla_K[i] = 0;
    vars.ancilla_R[i] = 0;
    vars.ancilla_arr4[i] = 0;
    vars.ancilla_S[i] = 9;
    vars.ancilla_T[i] = 0;
    vars.ancilla_dir[i] = vars.link_direction_facing.* >> 1;
    if (Ancilla_CheckInitialTileCollision_Class2(k)) {
        Ancilla_SetX(k, vars.link_x_coord.* +% 8);
        Ancilla_SetY(k, vars.link_y_coord.* +% 16);
    } else {
        const d: usize = vars.link_direction_facing.* >> 1;
        Ancilla_SetX(k, vars.link_x_coord.* +% signedOffset(tables.kCaneOfSomaria_X[d]));
        Ancilla_SetY(k, vars.link_y_coord.* +% signedOffset(tables.kCaneOfSomaria_Y[d]));
        SomariaBlock_CheckForTransitTile(k);
    }
    return k;
}

pub export fn SomariaBlock_CheckForTransitTile(k: c_int) callconv(.c) void { // 88e191
    const i: usize = @intCast(k);
    if (vars.dung_unk6.* == 0) return;
    var j: c_int = 11;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        const x = Ancilla_GetX(k) +% signedOffset(tables.kSomariaTransitLine_X[u]);
        const y = Ancilla_GetY(k) +% signedOffset(tables.kSomariaTransitLine_Y[u]);
        const bak = vars.ancilla_objprio[i];
        _ = Ancilla_CheckTileCollision_targeted(k, x, y);
        vars.ancilla_objprio[i] = bak;
        if (vars.ancilla_tile_attr[i] == 0xb6 or vars.ancilla_tile_attr[i] == 0xbc) {
            Ancilla_SetX(k, x);
            Ancilla_SetY(k, y);
            AncillaAdd_SomariaPlatformPoof(k);
            return;
        }
    }
}

pub export fn Ancilla_CheckBasicSpriteCollision(k: c_int) callconv(.c) c_int { // 88e1f9
    const i: usize = @intCast(k);
    var j: c_int = 15;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        if ((@as(u8, @truncate(@as(u32, @bitCast(j)))) ^ vars.frame_counter.*) & 3 |
            vars.sprite_pause[u] | vars.sprite_hit_timer[u] != 0) continue;
        if (vars.sprite_state[u] < 9 or
            (vars.sprite_defl_bits[u] & 2 == 0 and vars.ancilla_objprio[i] != 0)) continue;
        if (vars.ancilla_floor[i] != vars.sprite_floor[u]) continue;
        if (vars.ancilla_type[i] == 0x2c and (vars.sprite_type[u] == 0x1e or vars.sprite_type[u] == 0x90)) continue;
        if (Ancilla_CheckBasicSpriteCollision_Single(k, j)) return j;
    }
    return -1;
}

pub export fn Ancilla_CheckBasicSpriteCollision_Single(k: c_int, j: c_int) callconv(.c) bool { // 88e23d
    const i: usize = @intCast(k);
    const u: usize = @intCast(j);
    var hb: SpriteHitBox = undefined;
    Ancilla_SetupBasicHitBox(k, &hb);
    sprite.Sprite_SetupHitBox(j, &hb);
    if (!sprite.CheckIfHitBoxesOverlap(&hb)) return false;
    if (vars.sprite_type[u] == 0x92 and vars.sprite_C[u] < 3) return true;
    if (vars.sprite_type[u] == 0x80 and vars.sprite_delay_aux4[u] == 0) {
        vars.sprite_delay_aux4[u] = 24;
        vars.sprite_D[u] ^= 1;
    }
    if (vars.sprite_ignore_projectile[u] != 0) return false;

    const x = Ancilla_GetX(k) -% 8;
    const y = Ancilla_GetY(k) -% 8 -% @as(u16, vars.ancilla_z[i]);
    const pt = sprite.Sprite_ProjectSpeedTowardsLocation(j, x, y, 80);
    vars.sprite_y_recoil[u] = ~pt.y;
    vars.sprite_x_recoil[u] = ~pt.x;
    Ancilla_CheckDamageToSprite(j, vars.ancilla_type[i]);
    return true;
}

pub export fn Ancilla_SetupBasicHitBox(k: c_int, hb: *SpriteHitBox) callconv(.c) void { // 88e2ca
    const i: usize = @intCast(k);
    const x = Ancilla_GetX(k) -% 8;
    hb.r0_xlo = @truncate(x);
    hb.r8_xhi = @truncate(x >> 8);
    const y = Ancilla_GetY(k) -% 8 -% @as(u16, vars.ancilla_z[i]);
    hb.r1_ylo = @truncate(y);
    hb.r9_yhi = @truncate(y >> 8);
    hb.r2 = 15;
    hb.r3 = 15;
}

pub export fn Ancilla2C_SomariaBlock(k: c_int) callconv(.c) void { // 88e365
    const i: usize = @intCast(k);
    vars.ancilla_G[i] -%= 1;
    if (!sign8(vars.ancilla_G[i])) return;
    vars.ancilla_G[i] = 0;

    after_label_1: {
        skip_label_1: {
            if (vars.ancilla_H[i] != 0) break :skip_label_1;
            if (vars.submodule_index.* == 0 or vars.submodule_index.* == 8 or vars.submodule_index.* == 16) {
                Ancilla_HandleLiftLogic(k);
            } else if (k + 1 == vars.flag_is_ancilla_to_pick_up.* and vars.ancilla_K[i] != 0) {
                if (vars.ancilla_K[i] != 3) {
                    Ancilla_LatchLinkCoordinates(k, 3);
                    Ancilla_LatchAltitudeAboveLink(k);
                    vars.ancilla_K[i] = 3;
                }
                Ancilla_LatchCarriedPosition(k);
            }
            if (vars.player_is_indoors.* == 0) break :after_label_1;
            if (vars.ancilla_K[i] != 0 or vars.link_state_bits.* & 0x80 != 0 or
                !(vars.ancilla_z[i] == 0 or vars.ancilla_z[i] == 0xff)) break :skip_label_1;

            if (vars.dung_unk6.* != 0) {
                var j: usize = vars.frame_counter.* & 3;
                while (true) {
                    const bak = vars.ancilla_objprio[i];
                    const x = Ancilla_GetX(k) +% signedOffset(tables.kSomarianBlock_Coll_X[j]);
                    const y = Ancilla_GetY(k) +% signedOffset(tables.kSomarianBlock_Coll_Y[j]);
                    _ = Ancilla_CheckTileCollision_targeted(k, x, y);
                    vars.ancilla_objprio[i] = bak;
                    if (vars.ancilla_tile_attr[i] == 0xb6 or vars.ancilla_tile_attr[i] == 0xbc) {
                        Ancilla_SetXY(k, x, y);
                        AncillaAdd_SomariaPlatformPoof(k);
                        if (k + 1 == vars.flag_is_ancilla_to_pick_up.*) vars.flag_is_ancilla_to_pick_up.* = 0;
                        return;
                    }
                    j += 4;
                    if (j >= 12) break;
                }
            } else {
                if (!SomariaBlock_CheckForSwitch(k) and (vars.ancilla_z[i] == 0 or vars.ancilla_z[i] == 0xff))
                    vars.dung_flag_somaria_block_switch.* +%= 1;
            }
            break :after_label_1;
        }
        // label_1
        if (vars.flag_is_ancilla_to_pick_up.* == k + 1) vars.dung_flag_somaria_block_switch.* = 0;
    }

    var old_y = Ancilla_LatchYCoordToZ(k);
    const s1a = vars.ancilla_dir[i];
    var s1b = vars.ancilla_objprio[i];
    vars.ancilla_objprio[i] = 0;
    var flag = Ancilla_CheckTileCollision_Class2(k);

    if (vars.player_is_indoors.* != 0 and vars.ancilla_L[i] != 0 and vars.ancilla_tile_attr[i] == 0x1c)
        vars.ancilla_T[i] = 1;

    label1: while (true) {
        if (flag and (vars.link_state_bits.* & 0x80 == 0 or vars.link_picking_throw_state.* != 0)) {
            if (s1b == 0 and vars.ancilla_arr4[i] == 0 and vars.ancilla_z[i] != 0) {
                vars.ancilla_arr4[i] = 1;
                const qq: u8 = if (vars.ancilla_dir[i] == 1) 16 else 4;
                if (vars.ancilla_y_vel[i] != 0)
                    vars.ancilla_y_vel[i] = if (sign8(vars.ancilla_y_vel[i])) qq else 0 -% qq;
                if (vars.ancilla_x_vel[i] != 0)
                    vars.ancilla_x_vel[i] = if (sign8(vars.ancilla_x_vel[i])) 4 else 0 -% @as(u8, 4);
                if (vars.ancilla_dir[i] == 1 and vars.ancilla_z[i] != 0) {
                    vars.ancilla_y_vel[i] = 0 -% @as(u8, 4);
                    vars.ancilla_L[i] = 2;
                }
            }
        } else if (vars.link_state_bits.* & 0x80 == 0 and (vars.ancilla_z[i] == 0 or vars.ancilla_z[i] == 0xff)) {
            vars.ancilla_dir[i] = 16;
            const bak0 = vars.ancilla_objprio[i];
            _ = Ancilla_CheckTileCollision(k);
            vars.ancilla_objprio[i] = bak0;
            const a = vars.ancilla_tile_attr[i];
            if (a == 0x26) {
                flag = true;
                continue :label1;
            } else if (a == 0xc or a == 0x1c) {
                if (vars.dung_hdr_collision.* != 3) {
                    if (vars.ancilla_floor[i] == 0 and vars.ancilla_z[i] != 0 and vars.ancilla_z[i] != 0xff)
                        vars.ancilla_floor[i] = 1;
                } else {
                    old_y = Ancilla_GetY(k) +% vars.dung_floor_y_vel.*;
                    Ancilla_SetX(k, Ancilla_GetX(k) +% vars.dung_floor_x_vel.*);
                }
            } else if (a == 0x20 or (a & 0xf0 == 0xb0 and a != 0xb6 and a != 0xbc)) {
                if (vars.link_state_bits.* & 0x80 == 0) {
                    if (k + 1 == vars.flag_is_ancilla_to_pick_up.*) vars.flag_is_ancilla_to_pick_up.* = 0;
                    if (vars.ancilla_timer[i] == 0) {
                        if (vars.link_speed_setting.* == 18) {
                            vars.link_speed_setting.* = 0;
                            vars.bitmask_of_dragstate.* = 0;
                        }
                        vars.ancilla_type[i] = 0;
                        return;
                    }
                }
            } else if (a == 8) {
                if (k + 1 == vars.flag_is_ancilla_to_pick_up.*) vars.flag_is_ancilla_to_pick_up.* = 0;
                if (vars.ancilla_timer[i] == 0) {
                    Ancilla_SetY(k, Ancilla_GetY(k) -% 24);
                    Ancilla_TransmuteToSplash(k);
                    return;
                }
            } else if (a == 0x68 or a == 0x69 or a == 0x6a or a == 0x6b) {
                Ancilla_ApplyConveyor(k);
                old_y = Ancilla_GetY(k);
            } else {
                vars.ancilla_timer[i] = if ((vars.ancilla_L[i] | vars.ancilla_H[i]) != 0) 0 else 2;
            }
        }
        break;
    }
    // endif_3
    s1b |= vars.ancilla_objprio[i];

    if (vars.link_state_bits.* & 0x80 == 0) {
        vars.ancilla_S[i] -%= 1;
        if (vars.ancilla_S[i] == 0) {
            vars.ancilla_S[i] = 1;
            vars.ancilla_objprio[i] = 0;
            if (Ancilla_CheckBasicSpriteCollision(k) >= 0) {
                vars.ancilla_S[i] = 7;
                vars.ancilla_step[i] +%= 1;
                if (vars.ancilla_step[i] == 5) {
                    SomariaBlock_FizzleAway(k);
                    return;
                }
            }
        }
    }
    Ancilla_SetY(k, old_y);
    vars.ancilla_dir[i] = s1a;
    vars.ancilla_objprio[i] = s1b;

    AncillaDraw_SomariaBlock(k);
}

pub export fn AncillaDraw_SomariaBlock(k: c_int) callconv(.c) void { // 88e61b
    const i: usize = @intCast(k);
    if (k + 1 == vars.flag_is_ancilla_to_pick_up.* and vars.link_state_bits.* & 0x80 != 0 and
        vars.ancilla_K[i] != 3 and vars.link_direction_facing.* == 0)
    {
        Ancilla_AllocateOamFromRegion_B_or_E(vars.ancilla_numspr[i]);
    } else if (vars.sort_sprites_setting.* != 0 and vars.ancilla_floor[i] != 0 and
        (vars.ancilla_L[i] != 0 or
            (k + 1 == vars.flag_is_ancilla_to_pick_up.* and vars.link_state_bits.* & 0x80 != 0)))
    {
        vars.oam_cur_ptr.* = 0x8d0;
        vars.oam_ext_cur_ptr.* = 0xa20 + 0x34;
    }

    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    const oam_org = oam;
    const z = @as(i8, @bitCast(vars.ancilla_z[i]));
    if (z != 0 and z != -1 and vars.ancilla_K[i] != 3 and vars.ancilla_objprio[i] != 0)
        vars.oam_priority_value.* = 0x3000;
    pt.y -%= signedOffset(z);
    var j: usize = @as(usize, vars.ancilla_arr1[i]) * 4;
    for (0..4) |_| {
        Ancilla_SetOam_Safe(
            oam,
            pt.x +% signedOffset(tables.kSomarianBlock_Draw_X[j]),
            pt.y +% signedOffset(tables.kSomarianBlock_Draw_Y[j]),
            0xe9,
            (tables.kSomarianBlock_Draw_Flags[j] & ~@as(u8, 0x30)) | 2 | @as(u8, @truncate(vars.oam_priority_value.* >> 8)),
            0,
        );
        oam += 1;
        j += 1;
    }

    if (SomarianBlock_CheckEmpty(oam_org)) {
        vars.dung_flag_somaria_block_switch.* = 0;
        vars.ancilla_type[i] = 0;
        if (k + 1 == vars.flag_is_ancilla_to_pick_up.*) {
            vars.flag_is_ancilla_to_pick_up.* = 0;
            if (vars.link_state_bits.* & 128 != 0) vars.link_state_bits.* = 0;
        }
    }
}

pub export fn SomariaBlock_CheckForSwitch(k: c_int) callconv(.c) bool { // 88e75c
    const i: usize = @intCast(k);
    vars.dung_flag_somaria_block_switch.* = 0;
    vars.ancilla_arr24[i] = 0;
    var j: c_int = 3;
    while (j >= 0) : (j -= 1) {
        const u: usize = @intCast(j);
        const y = Ancilla_GetY(k) +% signedOffset(tables.kSomarianBlock_CheckCover_Y[u]);
        const x = Ancilla_GetX(k) +% signedOffset(tables.kSomarianBlock_CheckCover_X[u]);
        const bak = vars.ancilla_objprio[i];
        _ = Ancilla_CheckTileCollision_targeted(k, x, y);
        vars.ancilla_objprio[i] = bak;
        const a = vars.ancilla_tile_attr[i];
        if (a == 0x23 or a == 0x24 or a == 0x25 or a == 0x3b) vars.ancilla_arr24[i] +%= 1;
    }
    return vars.ancilla_arr24[i] != 4;
}

pub export fn SomariaBlock_FizzleAway(k: c_int) callconv(.c) void { // 88e9b2
    const i: usize = @intCast(k);
    if (vars.link_speed_setting.* == 18) {
        vars.bitmask_of_dragstate.* = 0;
        vars.link_speed_setting.* = 0;
    }
    vars.dung_flag_somaria_block_switch.* = 0;
    vars.ancilla_type[i] = 0x2d;
    vars.ancilla_aux_timer[i] = 0;
    vars.ancilla_step[i] = 0;
    vars.ancilla_item_to_link[i] = 0;
    vars.ancilla_arr3[i] = 0;
    vars.ancilla_arr1[i] = 0;
    vars.ancilla_R[i] = 0;
    if (k + 1 == vars.flag_is_ancilla_to_pick_up.*) {
        vars.flag_is_ancilla_to_pick_up.* = 0;
        vars.link_state_bits.* &= 0x80;
    }
    Ancilla2D_SomariaBlockFizz(k);
}

pub export fn Ancilla2D_SomariaBlockFizz(k: c_int) callconv(.c) void { // 88e9e8
    const i: usize = @intCast(k);
    vars.ancilla_aux_timer[i] -%= 1;
    if (sign8(vars.ancilla_aux_timer[i])) {
        vars.ancilla_aux_timer[i] = 3;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 3) {
            vars.ancilla_type[i] = 0;
            return;
        }
    }
    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    var z = vars.ancilla_z[i];
    if (z == 0xff) z = 0;
    const x = pt.x;
    const y = pt.y -% signedOffset(@as(i8, @bitCast(z)));
    var j: usize = @as(usize, vars.ancilla_item_to_link[i]) * 2;
    for (0..2) |_| {
        if (tables.kSomariaBlockFizzle_Char[j] != 0xff) {
            Ancilla_SetOam(
                oam,
                x +% signedOffset(tables.kSomariaBlockFizzle_X[j]),
                y +% signedOffset(tables.kSomariaBlockFizzle_Y[j]),
                tables.kSomariaBlockFizzle_Char[j],
                (tables.kSomariaBlockFizzle_Flags[j] & ~@as(u8, 0x30)) | @as(u8, @truncate(vars.oam_priority_value.* >> 8)),
                0,
            );
        }
        j += 1;
        oam += 1;
    }
}

pub export fn Ancilla39_SomariaPlatformPoof(k: c_int) callconv(.c) void { // 88ea83
    const i: usize = @intCast(k);
    vars.ancilla_aux_timer[i] -%= 1;
    if (!sign8(vars.ancilla_aux_timer[i])) return;
    vars.ancilla_type[i] = 0;
    var info: SpriteSpawnInfo = undefined;
    const x = (Ancilla_GetX(k) & ~@as(u16, 7)) | 4;
    const y = (Ancilla_GetY(k) & ~@as(u16, 7)) | 4;
    const floor = vars.ancilla_floor[i];
    const j = sprite.Sprite_SpawnDynamically(k, 0xed, &info); // the C passes the ancilla slot here
    if (j >= 0) {
        const u: usize = @intCast(j);
        vars.player_on_somaria_platform.* = 0;
        sprite.Sprite_SetX(j, x);
        sprite.Sprite_SetY(j, y);

        const pos: i32 = @as(i32, (x & 0x1f8) >> 3) + (@as(i32, y & 0x1f8) << 3) +
            @as(i32, if (floor >= 1) 0x1000 else 0);

        var t: usize = 0;
        if (vars.dung_bg2_attr_table[@intCast(pos + XY(0, -1))] & 0xf0 != 0xb0) {
            t += 1;
            if (vars.dung_bg2_attr_table[@intCast(pos + XY(0, 1))] & 0xf0 != 0xb0) {
                t += 1;
                if (vars.dung_bg2_attr_table[@intCast(pos + XY(-1, 0))] & 0xf0 != 0xb0) t += 1;
            }
        }
        vars.sprite_D[u] = tables.kSomarianPlatformPoof_Tab0[t];
        vars.sprite_floor[u] = 0;
    } else {
        AncillaDraw_SomariaBlock(k);
    }
}

pub export fn Ancilla2E_SomariaBlockFission(k: c_int) callconv(.c) void { // 88eb3e
    const i: usize = @intCast(k);
    vars.ancilla_aux_timer[i] -%= 1;
    if (sign8(vars.ancilla_aux_timer[i])) {
        vars.ancilla_aux_timer[i] = 3;
        vars.ancilla_item_to_link[i] +%= 1;
        if (vars.ancilla_item_to_link[i] == 2) {
            vars.ancilla_type[i] = 0;
            SomariaBlock_SpawnBullets(k);
            return;
        }
    }
    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    var oam = GetOamCurPtr();

    const link_z_lo = @as(u8, @truncate(vars.link_z_coord.*));
    const z = @as(i8, @bitCast(vars.ancilla_z[i] +%
        (if (vars.ancilla_K[i] == 3 and link_z_lo != 0xff) link_z_lo else 0)));
    var j: usize = @as(usize, vars.ancilla_item_to_link[i]) * 8;
    for (0..8) |_| {
        Ancilla_SetOam(
            oam,
            pt.x +% signedOffset(tables.kSomarianBlockDivide_X[j]),
            pt.y +% signedOffset(tables.kSomarianBlockDivide_Y[j]) -% signedOffset(z),
            tables.kSomarianBlockDivide_Char[j],
            (tables.kSomarianBlockDivide_Flags[j] & ~@as(u8, 0x30)) | @as(u8, @truncate(vars.oam_priority_value.* >> 8)),
            0,
        );
        j += 1;
        oam += 1;
    }
}

pub export fn Ancilla2F_LampFlame(k: c_int) callconv(.c) void { // 88ec13
    const i: usize = @intCast(k);
    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    var oam = GetOamCurPtr();
    if (vars.ancilla_timer[i] == 0) {
        vars.ancilla_type[i] = 0;
        return;
    }
    var j: usize = (vars.ancilla_timer[i] & 0xf8) >> 1;
    while (true) {
        if (tables.kLampFlame_Draw_Char[j] != 0xff) {
            Ancilla_SetOam(
                oam,
                pt.x +% signedOffset(tables.kLampFlame_Draw_X[j]),
                pt.y +% signedOffset(tables.kLampFlame_Draw_Y[j]),
                tables.kLampFlame_Draw_Char[j],
                @as(u8, @truncate(vars.oam_priority_value.* >> 8)) | 2,
                0,
            );
            oam += 1;
        }
        j += 1;
        if (j & 3 == 0) break;
    }
}

pub export fn Ancilla41_WaterfallSplash(k: c_int) callconv(.c) void { // 88ecaf
    const i: usize = @intCast(k);
    if (!Ancilla_CheckForEntranceTrigger(if (vars.player_is_indoors.* != 0) 0 else 1)) {
        vars.ancilla_type[i] = 0;
        return;
    }

    if (vars.submodule_index.* == 0 and vars.frame_counter.* & 7 == 0)
        _ = misc.Ancilla_Sfx2_Near(0x1c);

    vars.draw_water_ripples_or_grass.* = 1;
    if (!sign8(vars.link_animation_steps.* -% 6)) vars.link_animation_steps.* -%= 6;

    if (vars.ancilla_timer[i] == 0) {
        vars.ancilla_timer[i] = 2;
        vars.ancilla_item_to_link[i] = (vars.ancilla_item_to_link[i] +% 1) & 3;
    }

    if (vars.player_is_indoors.* != 0 and @as(u8, @truncate(vars.link_y_coord.*)) < 0x38) {
        Ancilla_SetY(k, 0xd38);
    } else {
        Ancilla_SetY(k, vars.link_y_coord.*);
    }
    Ancilla_SetX(k, vars.link_x_coord.*);

    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    var oam = GetOamCurPtr();

    const z = @as(u8, @truncate(vars.link_z_coord.*));
    pt.y -%= if (sign8(z)) 0 else @as(u16, z);

    var j: usize = @as(usize, vars.ancilla_item_to_link[i]) * 2;
    for (0..2) |_| {
        if (tables.kWaterfallSplash_Char[j] != 0xff) {
            Ancilla_SetOam(
                oam,
                pt.x +% signedOffset(tables.kWaterfallSplash_X[j]),
                pt.y +% signedOffset(tables.kWaterfallSplash_Y[j]),
                tables.kWaterfallSplash_Char[j],
                tables.kWaterfallSplash_Flags[j] | 0x30,
                tables.kWaterfallSplash_Ext[j],
            );
        }
        j += 1;
        oam += 1;
    }
}

pub export fn Ancilla24_Gravestone(k: c_int) callconv(.c) void { // 88ee01
    var pt: Point16U = undefined;
    Ancilla_PrepAdjustedOamCoord(k, &pt);
    _ = sprite.Oam_AllocateFromRegionB(16);
    var oam = GetOamCurPtr();
    var x = pt.x;
    var y = pt.y;
    for (0..4) |m| {
        Ancilla_SetOam(oam, x, y, tables.kAncilla_Gravestone_Char[m], tables.kAncilla_Gravestone_Flags[m] | 0x3d, 2);
        x +%= 16;
        if (m == 1) {
            x -%= 32;
            y +%= 8;
        }
        oam += 1;
    }
}

pub export fn Ancilla34_SkullWoodsFire(k: c_int) callconv(.c) void { // 88ef9a
    const i: usize = @intCast(k);
    if (vars.skullwoodsfire_var4.* != 0 and vars.ancilla_item_to_link[i] != 4) {
        vars.ancilla_aux_timer[i] -%= 1;
        if (sign8(vars.ancilla_aux_timer[i])) {
            vars.ancilla_aux_timer[i] = 5;
            vars.ancilla_item_to_link[i] +%= 1;
        }
    }
    var oam = GetOamCurPtr();
    var n: c_int = 3;
    while (n >= 0) : (n -= 1) {
        const u: usize = @intCast(n);
        endif_2: {
            vars.skullwoodsfire_var5[u] -%= 1;
            if (!sign8(vars.skullwoodsfire_var5[u])) break :endif_2;
            vars.skullwoodsfire_var5[u] = 5;
            if (vars.skullwoodsfire_var0[u] == 128) break :endif_2;
            vars.skullwoodsfire_var0[u] +%= 1;
            if (vars.skullwoodsfire_var0[u] != 0) {
                if (vars.skullwoodsfire_var0[u] != 4) break :endif_2;
                vars.skullwoodsfire_var0[u] = 0;
            }
            vars.skullwoodsfire_var9.* -%= 8;
            if (vars.skullwoodsfire_var9.* < 200 and vars.skullwoodsfire_var4.* != 1) {
                vars.skullwoodsfire_var4.* = 1;
                vars.sound_effect_1.* = tables.kBombos_Sfx[@as(u8, @truncate(0x98 -% vars.BG2HOFS_copy2.*)) >> 5] | 0xc;
            }
            if (vars.skullwoodsfire_var9.* < 168) vars.skullwoodsfire_var0[u] = 128;
            vars.skullwoodsfire_x_arr[u] = vars.skullwoodsfire_var11.*;
            vars.skullwoodsfire_y_arr[u] = vars.skullwoodsfire_var9.*;
            if (vars.sound_effect_1.* == 0)
                vars.sound_effect_1.* = tables.kBombos_Sfx[@as(u8, @truncate(vars.skullwoodsfire_var11.* -% vars.BG2HOFS_copy2.*)) >> 5] | 0x2a;
        }
        if (!sign8(vars.skullwoodsfire_var0[u])) {
            const j: usize = vars.skullwoodsfire_var0[u];
            const x = vars.skullwoodsfire_x_arr[u] -% vars.BG2HOFS_copy2.*;
            const y = vars.skullwoodsfire_y_arr[u] -% vars.BG2VOFS_copy2.* +% signedOffset(tables.kSkullWoodsFire_Draw_Y[j]);
            Ancilla_SetOam(oam, x, y, tables.kSkullWoodsFire_Draw_Char[j], 0x32, tables.kSkullWoodsFire_Draw_Ext[j]);
            oam += 1;
            if (tables.kSkullWoodsFire_Draw_Ext[j] != 2) {
                Ancilla_SetOam(oam, x +% 8, y, tables.kSkullWoodsFire_Draw_Char[j] +% 1, 0x32, tables.kSkullWoodsFire_Draw_Ext[j]);
                oam += 1;
            }
        }
    }

    var m: c_int = 3;
    while (sign8(vars.skullwoodsfire_var0[@intCast(m)])) {
        m -= 1;
        if (m < 0) {
            vars.ancilla_type[i] = 0;
            return;
        }
    }

    if (vars.skullwoodsfire_var4.* == 0 or vars.ancilla_item_to_link[i] == 4) return;

    var j: usize = @as(usize, vars.ancilla_item_to_link[i]) * 6;
    for (0..6) |_| {
        if (tables.kSkullWoodsFire_Draw2_Char[j] != 0xff) {
            Ancilla_SetOam(
                oam,
                168 -% vars.BG2HOFS_copy2.* +% signedOffset(tables.kSkullWoodsFire_Draw2_X[j]),
                200 -% vars.BG2VOFS_copy2.* +% signedOffset(tables.kSkullWoodsFire_Draw2_Y[j]),
                tables.kSkullWoodsFire_Draw2_Char[j],
                tables.kSkullWoodsFire_Draw2_Flags[j] | 0x32,
                tables.kSkullWoodsFire_Draw2_Ext[j],
            );
            oam += 1;
        }
        j += 1;
    }
}

pub export fn Ancilla3A_BigBombExplosion(k: c_int) callconv(.c) void { // 88f18d
    const i: usize = @intCast(k);
    if (vars.submodule_index.* == 0) {
        vars.ancilla_arr3[i] -%= 1;
        if (vars.ancilla_arr3[i] == 0) {
            vars.ancilla_item_to_link[i] +%= 1;
            if (vars.ancilla_item_to_link[i] == 2) Ancilla_Sfx2_Pan(k, 0xc);
            if (vars.ancilla_item_to_link[i] == 11) {
                vars.ancilla_type[i] = 0;
                return;
            }
            vars.ancilla_arr3[i] = tables.kBomb_Tab0[vars.ancilla_item_to_link[i]];
        }
    }
    vars.oam_priority_value.* = 0x3000;
    const numframes = tables.kBomb_Draw_Tab2[vars.ancilla_item_to_link[i]];
    const j: c_int = @as(c_int, tables.kBomb_Draw_Tab0[vars.ancilla_item_to_link[i]]) * 6;
    vars.ancilla_step[i] = @truncate(@as(u32, @bitCast(j * 2)));

    var yy: usize = 0;
    var n: c_int = 8;
    while (n >= 0) : (n -= 1) {
        const u: usize = @intCast(n);
        const x = Ancilla_GetX(k) +% signedOffset(tables.kSuperBombExplode_X[u]) -% vars.BG2HOFS_copy2.*;
        const y = Ancilla_GetY(k) +% signedOffset(tables.kSuperBombExplode_Y[u]) -% vars.BG2VOFS_copy2.*;
        if (x < 256 and y < 256) {
            // The C truncates the slot index to a byte here, which is what the
            // allocator sees; preserved verbatim.
            _ = Ancilla_AllocateOamFromRegion_A_or_D_or_F(@as(u8, @truncate(@as(u32, @bitCast(j * 2)))), 0x18);
            const oam = GetOamCurPtr() + yy;
            yy += (@intFromPtr(AncillaDraw_Explosion(oam, j, 0, numframes, 0x32, x, y)) - @intFromPtr(oam)) / @sizeOf(OamEnt);
        }
    }
    if (vars.ancilla_item_to_link[i] == 3 and vars.ancilla_arr3[i] == 1) {
        // Changed so this is reset elsewhere. Some code depends on the value 13.
        const old: u8 = if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
            vars.follower_indicator.*
        else
            0;
        vars.follower_indicator.* = 13;
        Bomb_CheckForDestructibles(Ancilla_GetX(k), Ancilla_GetY(k), 0);
        vars.follower_indicator.* = old;
    }
}

// ---------------------------------------------------------------------------
// Revival fairy and game over.
// ---------------------------------------------------------------------------

pub export fn RevivalFairy_Main() callconv(.c) void { // 88f283
    const i: usize = 0;
    skip_draw: {
        switch (vars.ancilla_step[i]) {
            0 => {
                vars.ancilla_arr3[i] -%= 1;
                if (vars.ancilla_arr3[i] == 0) {
                    vars.ancilla_step[i] +%= 1;
                    vars.ancilla_arr3[i] = tables.kAncilla_RevivalFaerie_Tab0[vars.ancilla_step[i]];
                    vars.ancilla_K[i] = 0;
                    vars.ancilla_z_vel[i] = 0;
                } else {
                    Ancilla_MoveZ(0);
                }
            },
            1 => {
                vars.ancilla_arr3[i] -%= 1;
                if (vars.ancilla_arr3[i] == 0) {
                    vars.ancilla_step[i] +%= 1;
                    vars.ancilla_z_vel[i] = 0;
                    vars.ancilla_x_vel[i] = 0;
                } else {
                    if (vars.ancilla_arr3[i] == 0x4f or vars.ancilla_arr3[i] == 0x8f) {
                        vars.ancilla_L[i] +%= 1;
                        Ancilla_Sfx2_Pan(0, 0x31);
                    }
                    if (vars.ancilla_L[i] != 0) {
                        vars.ancilla_G[i] -%= 1;
                        if (sign8(vars.ancilla_G[i])) {
                            vars.ancilla_G[i] = 5;
                            vars.ancilla_item_to_link[i] +%= 1;
                            if (vars.ancilla_item_to_link[i] == 3) {
                                vars.ancilla_item_to_link[i] = 0;
                                vars.ancilla_L[i] = 0;
                            }
                        }
                    }
                    if (vars.ancilla_K[i] != 0) {
                        vars.ancilla_z_vel[i] +%= 1;
                    } else {
                        vars.ancilla_z_vel[i] -%= 1;
                    }
                    if (abs8(vars.ancilla_z_vel[i]) == 8) vars.ancilla_K[i] ^= 1;
                    Ancilla_MoveZ(0);
                }
            },
            2 => {
                if (vars.ancilla_z_vel[i] < 24) vars.ancilla_z_vel[i] +%= 1;
                if (vars.ancilla_x_vel[i] < 16) vars.ancilla_x_vel[i] +%= 1;
                Ancilla_MoveX(0);
                Ancilla_MoveZ(0);
            },
            3 => break :skip_draw,
            else => {},
        }

        _ = sprite.Oam_AllocateFromRegionC(12);
        var pt: Point16U = undefined;
        Ancilla_PrepOamCoord(0, &pt);
        const oam = GetOamCurPtr();
        var t: usize = if (vars.ancilla_step[i] == 1 and vars.ancilla_L[i] != 0)
            @as(usize, vars.ancilla_item_to_link[i]) + 1
        else
            0;
        if (t != 0) t += 1 else t = (vars.frame_counter.* >> 2) & 1;
        Ancilla_SetOam(oam, pt.x, pt.y -% signedOffset(@as(i8, @bitCast(vars.ancilla_z[i]))), tables.kAncilla_RevivalFaerie_Tab1[t], 0x74, 2);
        if (oam[0].y == 0xf0) {
            vars.ancilla_step[i] = 3;
            vars.submodule_index.* +%= 1;
            vars.TM_copy.* = vars.mapbak_TM.*;
        }
    }
    RevivalFairy_Dust();
    RevivalFairy_MonitorHP();
}

pub export fn RevivalFairy_Dust() callconv(.c) void { // 88f3cf
    const i: usize = 2;
    if (vars.ancilla_step[0] == 0 or vars.ancilla_step[i] == 2) return;
    vars.ancilla_arr3[i] -%= 1;
    if (!sign8(vars.ancilla_arr3[i])) return;
    vars.ancilla_arr3[i] = 0;
    if (vars.sort_sprites_setting.* == 0) {
        _ = sprite.Oam_AllocateFromRegionA(16);
    } else {
        _ = sprite.Oam_AllocateFromRegionD(16);
    }
    vars.ancilla_aux_timer[i] -%= 1;
    if (sign8(vars.ancilla_aux_timer[i])) {
        vars.ancilla_aux_timer[i] = 3;
        if (vars.ancilla_item_to_link[i] == 9) {
            vars.ancilla_arr3[i] = 32;
            vars.ancilla_step[i] +%= 1;
            vars.ancilla_item_to_link[i] = 2;
            return;
        }
        vars.ancilla_item_to_link[i] +%= 1;
        vars.ancilla_arr25[i] = tables.kMagicPowder_Tab0[30 + @as(usize, vars.ancilla_item_to_link[i])];
    }
    Ancilla_MagicPowder_Draw(2);
}

pub export fn RevivalFairy_MonitorHP() callconv(.c) void { // 88f430
    if ((vars.link_health_current.* == vars.link_health_capacity.* or vars.link_health_current.* == 0x38) and
        vars.is_doing_heart_animation.* == 0)
    {
        if (vars.link_is_in_deep_water.* != 0) {
            vars.link_some_direction_bits.* = 4;
            vars.link_player_handler_state.* = kPlayerState_Swimming;
        } else if (vars.link_is_bunny.* != 0) {
            vars.link_player_handler_state.* = kPlayerState_PermaBunny;
            vars.link_is_bunny_mirror.* = 1;
            // bugfix: dying as permabunny doesn't restore link palette during death animation
            if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
                load_gfx.LoadGearPalettes_bunny();
        } else {
            vars.link_player_handler_state.* = kPlayerState_Ground;
        }
        vars.link_auxiliary_state.* = 0;
        vars.player_unk1.* = 0;
        vars.link_var30d.* = 0;
        vars.some_animation_timer_steps.* = 0;
        loPtr(vars.link_z_coord).* = 0;
        vars.link_incapacitated_timer.* = 0;
        for (0..5) |m| vars.ancilla_type[m] = 0;
        return;
    }
    const i: usize = 1;
    if (vars.ancilla_step[i] == 0) {
        vars.ancilla_arr3[i] -%= 1;
        if (vars.ancilla_arr3[i] == 0) {
            vars.ancilla_arr3[i] +%= 1;
            vars.ancilla_z_vel[i] = 4;
            Ancilla_MoveZ(1);
            if (vars.ancilla_z[i] >= 16) {
                vars.ancilla_step[i] +%= 1;
                vars.ancilla_z_vel[i] = 2;
            }
        }
    } else {
        vars.ancilla_K[i] -%= 1;
        if (sign8(vars.ancilla_K[i])) {
            vars.ancilla_K[i] = 32;
            vars.ancilla_z_vel[i] = 0 -% vars.ancilla_z_vel[i];
        }
        Ancilla_MoveZ(1);
    }
    loPtr(vars.link_z_coord).* = vars.ancilla_z[i];
}

pub export fn GameOverText_Draw() callconv(.c) void { // 88f5c4
    vars.oam_cur_ptr.* = 0x800;
    vars.oam_ext_cur_ptr.* = 0xa20;
    var oam = GetOamCurPtr();
    var k: c_int = vars.flag_for_boomerang_in_place.*;
    while (true) {
        const u: usize = @intCast(k);
        Ancilla_SetOam(oam, Ancilla_GetX(k), 0x57, tables.kGameOverText_Chars[u * 2 + 0], 0x3c, 0);
        Ancilla_SetOam(oam + 1, Ancilla_GetX(k), 0x5f, tables.kGameOverText_Chars[u * 2 + 1], 0x3c, 0);
        oam += 2;
        k -= 1;
        if (k < 0) break;
    }
}

// ---------------------------------------------------------------------------
// Spawners.
// ---------------------------------------------------------------------------

pub export fn AncillaAdd_TossedPondItem(a: u8, xin: u8, yin: u8) callconv(.c) void { // 898a32
    vars.link_receiveitem_index.* = xin;
    const k = Ancilla_AddAncilla(a, yin);
    if (k < 0) return;
    const i: usize = @intCast(k);
    vars.sound_effect_2.* = misc.Link_CalculateSfxPan() | 0x13;
    const sb = misc.kReceiveItemGfx[xin];

    if (sb != 0xff) {
        if (sb == 0x20) load_gfx.DecompressShieldGraphics();
        load_gfx.DecodeAnimatedSpriteTile_variable(sb);
    } else {
        load_gfx.DecodeAnimatedSpriteTile_variable(0);
    }
    if (sb == 6) load_gfx.DecompressSwordGraphics();

    vars.link_state_bits.* = 0x80;
    vars.link_picking_throw_state.* = 0;
    vars.link_direction_facing.* = 0;
    vars.link_animation_steps.* = 0;
    vars.ancilla_z_vel[i] = 20;
    vars.ancilla_y_vel[i] = 0 -% @as(u8, 40);
    vars.ancilla_x_vel[i] = 0;
    vars.ancilla_z[i] = 0;
    vars.ancilla_timer[i] = 16;
    vars.ancilla_item_to_link[i] = vars.link_receiveitem_index.*;
    const idx: usize = vars.link_receiveitem_index.*;
    Ancilla_SetXY(
        k,
        vars.link_x_coord.* +% tables.kWishPondItem_X[idx],
        vars.link_y_coord.* +% signedOffset(tables.kWishPondItem_Y[idx]),
    );
}

pub export fn AddHappinessPondRupees(arg: u8) callconv(.c) void { // 898ae0
    if (Ancilla_AddAncilla(0x42, 9) < 0) return;
    vars.sound_effect_2.* = misc.Link_CalculateSfxPan() | 0x13;
    load_gfx.DecodeAnimatedSpriteTile_variable(misc.kReceiveItemGfx[0x35]);
    vars.link_state_bits.* = 0x80;
    vars.link_picking_throw_state.* = 0;
    vars.link_direction_facing.* = 0;
    vars.link_animation_steps.* = 0;

    @memset(vars.happiness_pond_arr1[0..10], 0);

    var j: c_int = tables.kHappinessPond_Start[arg];
    const j_end: c_int = tables.kHappinessPond_End[arg];
    var k: c_int = 9;
    while (true) {
        const u: usize = @intCast(k);
        const v: usize = @intCast(j);
        vars.happiness_pond_arr1[u] = 1;
        vars.happiness_pond_z_vel[u] = @bitCast(tables.kHappinessPond_Zvel[v]);
        vars.happiness_pond_y_vel[u] = @bitCast(tables.kHappinessPond_Yvel[v]);
        vars.happiness_pond_x_vel[u] = @bitCast(tables.kHappinessPond_Xvel[v]);
        vars.happiness_pond_z[u] = 0;
        vars.happiness_pond_step[u] = 0;
        vars.happiness_pond_timer[u] = 16;
        vars.happiness_pond_item_to_link[u] = 53;
        const x = vars.link_x_coord.* +% 4;
        const y = vars.link_y_coord.* -% 12;
        vars.happiness_pond_x_lo[u] = @truncate(x);
        vars.happiness_pond_x_hi[u] = @truncate(x >> 8);
        vars.happiness_pond_y_lo[u] = @truncate(y);
        vars.happiness_pond_y_hi[u] = @truncate(y >> 8);
        k -= 1;
        j -= 1;
        if (j == j_end) break;
    }
}

pub export fn AncillaAdd_FallingPrize(a: u8, item_idx: u8, yv: u8) callconv(.c) c_int { // 898bc1
    vars.link_receiveitem_index.* = item_idx;
    const k = Ancilla_AddAncilla(a, yv);
    if (k < 0) return k;
    const i: usize = @intCast(k);
    const item_type: u8 = @bitCast(tables.kFallingItem_Type[item_idx]);
    vars.ancilla_item_to_link[i] = item_type;
    if (item_type == 0x10 or item_type == 0xf)
        load_gfx.DecodeAnimatedSpriteTile_variable(misc.kReceiveItemGfx[item_type]);

    vars.ancilla_z_vel[i] = 0 -% @as(u8, 48);
    vars.ancilla_y_vel[i] = 0;
    vars.ancilla_x_vel[i] = 0;
    vars.ancilla_step[i] = 0;
    vars.ancilla_z[i] = tables.kFallingItem_Z[item_idx];
    vars.ancilla_aux_timer[i] = 9;
    vars.ancilla_arr3[i] = 0;
    vars.ancilla_L[i] = 0;
    vars.ancilla_G[i] = @bitCast(tables.kFallingItem_G[item_idx]);
    vars.link_receiveitem_index.* = item_type;

    var x: u16 = undefined;
    var y: u16 = undefined;
    if (item_idx != 0 and item_idx != 5) {
        if (@as(u8, @truncate(vars.cur_palace_index_x2.*)) == 20) {
            x = (vars.link_x_coord.* & 0xff00) | 0x100;
            y = (vars.link_y_coord.* & 0xff00) | 0x100;
        } else {
            x = signedOffset(tables.kFallingItem_X[item_idx]) +% vars.BG2HOFS_copy2.*;
            y = signedOffset(tables.kFallingItem_Y[item_idx]) +% vars.BG2VOFS_copy2.*;
        }
    } else {
        x = vars.link_x_coord.*;
        y = signedOffset(tables.kFallingItem_Y[item_idx]) +% vars.BG2VOFS_copy2.*;
    }
    Ancilla_SetXY(k, x, y);
    return k;
}

pub export fn AncillaAdd_BlastWall() callconv(.c) void { // 899692
    vars.ancilla_type[0] = 0x33;
    vars.ancilla_type[1] = 0x33;
    vars.ancilla_type[2] = 0;
    vars.ancilla_type[3] = 0;
    vars.ancilla_type[4] = 0;
    vars.ancilla_type[5] = 0;

    vars.ancilla_item_to_link[0] = 0;
    vars.flag_is_ancilla_to_pick_up.* = 0;
    vars.link_state_bits.* = 0;
    vars.link_cant_change_direction.* = 0;
    vars.ancilla_K[0] = 0;
    vars.ancilla_floor[0] = vars.link_is_on_lower_level.*;
    vars.ancilla_floor[1] = vars.link_is_on_lower_level.*;
    vars.ancilla_floor2[0] = vars.link_is_on_lower_level_mirror.*;
    vars.blastwall_var1.* = 0;
    vars.blastwall_var6[1] = 0;
    vars.blastwall_var5[1] = 0;
    vars.blastwall_var4.* = 0;
    vars.blastwall_var5[0] = 1;
    vars.flag_custom_spell_anim_active.* = 1;
    vars.blastwall_var6[0] = 3;
    const dir: usize = vars.blastwall_var7.*;
    vars.blastwall_var8.* +%= signedOffset(tables.kBlastWall_Tab3[dir]);
    vars.blastwall_var9.* +%= signedOffset(tables.kBlastWall_Tab4[dir]);
    var j: usize = if (dir < 4) 4 else 0;
    var n: c_int = 3;
    while (n >= 0) : (n -= 1) {
        const u: usize = @intCast(n);
        vars.blastwall_var10[u] = vars.blastwall_var8.* +% signedOffset(tables.kBlastWall_Tab5[j * 2 + 0]);
        vars.blastwall_var11[u] = vars.blastwall_var9.* +% signedOffset(tables.kBlastWall_Tab5[j * 2 + 1]);
        const x = vars.blastwall_var11[u] -% vars.BG2HOFS_copy2.*;
        if (x < 256) vars.sound_effect_1.* = tables.kBombos_Sfx[x >> 5] | 0xc;
        j += 1;
    }
}

pub export fn AncillaAdd_GraveStone(ain: u8, yin: u8) callconv(.c) void { // 8999e9
    const k = Ancilla_AddAncilla(ain, yin);
    if (k < 0) return;
    const i: usize = @intCast(k);
    const t = (if (vars.link_y_coord.* & 0xf < 7) vars.link_y_coord.* else vars.link_y_coord.* +% 16) & ~@as(u16, 0xf);

    var n: c_int = 7;
    while (tables.kMoveGravestone_Y[@intCast(n)] != t) {
        n -= 1;
        if (n < 0) {
            vars.ancilla_type[i] = 0;
            return;
        }
    }

    var j: usize = tables.kMoveGravestone_Idx[@intCast(n)];
    const end: usize = tables.kMoveGravestone_Idx[@intCast(n + 1)];
    while (true) {
        const x = tables.kMoveGravestone_X[j];
        if (x < vars.link_x_coord.* and x +% 15 >= vars.link_x_coord.*) {
            const blocked = if (j == 13) vars.link_is_running.* == 0 else vars.link_is_running.* != 0;
            if (blocked) break;

            const pos = tables.kMoveGravestone_Pos[j];
            vars.big_rock_starting_address.* = pos;
            vars.door_open_closed_counter.* = tables.kMoveGravestone_Ctr[j];
            if (vars.door_open_closed_counter.* == 0x58) {
                vars.sound_effect_2.* = misc.Link_CalculateSfxPan() | 0x1b;
            } else if (vars.door_open_closed_counter.* == 0x38) {
                vars.save_ow_event_info[@as(u8, @truncate(vars.overworld_screen_index.*))] |= 0x20;
                vars.sound_effect_2.* = misc.Link_CalculateSfxPan() | 0x1b;
            }

            const debris_y: [*]u8 = @ptrCast(vars.door_debris_y);
            const debris_x: [*]u8 = @ptrCast(vars.door_debris_x);
            debris_y[i] = @truncate(pos -% 0x80);
            debris_x[i] = @truncate((pos -% 0x80) >> 8);

            overworld.Overworld_DoMapUpdate32x32_B();

            if (vars.sound_effect_2.* & 0x3f != 0x1b)
                vars.sound_effect_1.* = misc.Link_CalculateSfxPan() | 0x22;

            const yy = tables.kMoveGravestone_Y1[j];
            const xx = tables.kMoveGravestone_X1[j];
            vars.bitmask_of_dragstate.* = 4;
            vars.link_something_with_hookshot.* = 1;
            vars.ancilla_A[i] = @truncate(yy -% 18);
            vars.ancilla_B[i] = @truncate((yy -% 18) >> 8);
            Ancilla_SetXY(k, xx, yy -% 2);
            return;
        }
        j += 1;
        if (j == end) break;
    }
    vars.ancilla_type[i] = 0;
}

pub export fn AncillaAdd_GTCutscene() callconv(.c) void { // 899b83
    if ((vars.link_state_bits.* & 0x80 | vars.link_auxiliary_state.*) != 0 or
        (vars.link_has_crystals.* & 0x7f) != 0x7f or
        vars.save_ow_event_info[0x43] & 0x20 != 0) return;

    Ancilla_TerminateSparkleObjects();

    if (AncillaAdd_CheckForPresence(0x43)) return;

    const k = Ancilla_AddAncilla(0x43, 4);
    if (k < 0) return;
    const i: usize = @intCast(k);

    var n: c_int = 15;
    while (n >= 0) : (n -= 1) {
        if (vars.sprite_type[@intCast(n)] == 0x37) vars.sprite_state[@intCast(n)] = 0;
    }

    n = 0x17;
    while (n >= 0) : (n -= 1) vars.breaktowerseal_sparkle_var1[@intCast(n)] = 0xff;
    load_gfx.DecodeAnimatedSpriteTile_variable(0x28);
    vars.palette_sp6r_indoors.* = 4;
    vars.overworld_palette_aux_or_main.* = 0x200;
    load_gfx.Palette_Load_SpriteEnvironment_Dungeon();
    vars.flag_update_cgram_in_nmi.* +%= 1;
    vars.flag_is_link_immobilized.* = 1;
    vars.ancilla_y_subpixel[i] = 0;
    vars.ancilla_x_subpixel[i] = 0;
    vars.ancilla_step[i] = 0;
    vars.breaktowerseal_var5.* = 240;
    vars.breaktowerseal_var4.* = 0;

    vars.breaktowerseal_var3[0] = 0;
    vars.breaktowerseal_var3[1] = 10;
    vars.breaktowerseal_var3[2] = 22;
    vars.breaktowerseal_var3[3] = 32;
    vars.breaktowerseal_var3[4] = 42;
    vars.breaktowerseal_var3[5] = 54;

    Ancilla_SetXY(k, vars.link_x_coord.*, vars.link_y_coord.* -% 16);
}

pub export fn FireRodShot_BecomeSkullWoodsFire(k: c_int) callconv(.c) void { // 899c4f
    _ = k;
    if (vars.player_is_indoors.* != 0 or @as(u8, @truncate(vars.overworld_screen_index.*)) & 0x40 == 0) return;

    vars.ancilla_type[0] = 0x34;
    vars.ancilla_type[1] = 0;
    vars.ancilla_type[2] = 0;
    vars.ancilla_type[3] = 0;
    vars.ancilla_type[4] = 0;
    vars.ancilla_type[5] = 0;
    vars.flag_for_boomerang_in_place.* = 0;
    vars.ancilla_numspr[0] = tables.kAncilla_Pflags[0x34];
    vars.skullwoodsfire_var0[0] = 253;
    vars.skullwoodsfire_var0[1] = 254;
    vars.skullwoodsfire_var0[2] = 255;
    vars.skullwoodsfire_var0[3] = 0;
    vars.skullwoodsfire_var4.* = 0;
    vars.skullwoodsfire_var5[0] = 5;
    vars.skullwoodsfire_var5[1] = 5;
    vars.skullwoodsfire_var5[2] = 5;
    vars.skullwoodsfire_var5[3] = 5;
    vars.ancilla_aux_timer[0] = 5;
    vars.skullwoodsfire_var9.* = 0x100;
    vars.skullwoodsfire_var10.* = 0x100;
    vars.skullwoodsfire_var11.* = 0x98;
    vars.skullwoodsfire_var12.* = 0x98;

    vars.trigger_special_entrance.* = 2;
    vars.subsubmodule_index.* = 0;
    loPtr(vars.R16).* = 0;
    vars.ancilla_floor[0] = vars.link_is_on_lower_level.*;
    vars.ancilla_floor2[0] = vars.link_is_on_lower_level_mirror.*;
    vars.ancilla_item_to_link[0] = 0;
    vars.ancilla_step[0] = 0;
}

pub export fn Ancilla_TerminateSelectInteractives(y_in: u8) callconv(.c) u8 { // 89ac6b
    var y = y_in;
    var i: c_int = 5;
    while (true) {
        const u: usize = @intCast(i);
        if (vars.ancilla_type[u] == 0x3e) {
            y = @truncate(@as(u32, @bitCast(i)));
        } else if (vars.ancilla_type[u] == 0x2c) {
            vars.dung_flag_somaria_block_switch.* = 0;
            if (vars.bitmask_of_dragstate.* & 0x80 != 0) {
                vars.bitmask_of_dragstate.* = 0;
                vars.link_speed_setting.* = 0;
            }
        }

        if (sign8(vars.link_state_bits.*)) {
            if (i + 1 != vars.flag_is_ancilla_to_pick_up.*) vars.ancilla_type[u] = 0;
        } else {
            if (i + 1 == vars.flag_is_ancilla_to_pick_up.*) vars.flag_is_ancilla_to_pick_up.* = 0;
            vars.ancilla_type[u] = 0;
        }
        i -= 1;
        if (i < 0) break;
    }

    if (vars.link_position_mode.* & 0x10 != 0) {
        vars.link_incapacitated_timer.* = 0;
        vars.link_position_mode.* = 0;
    }
    vars.flute_countdown.* = 0;
    vars.tagalong_event_flags.* = 0;
    vars.byte_7E02F3.* = 0;
    vars.flag_for_boomerang_in_place.* = 0;
    vars.is_archer_or_shovel_game.* = 0;
    vars.link_disable_sprite_damage.* = 0;
    vars.byte_7E03FD.* = 0;
    vars.link_electrocute_on_touch.* = 0;
    if (vars.link_player_handler_state.* == 19) {
        vars.link_player_handler_state.* = 0;
        vars.button_mask_b_y.* &= ~@as(u8, 0x40);
        vars.link_cant_change_direction.* &= ~@as(u8, 1);
        vars.link_position_mode.* &= ~@as(u8, 4);
        vars.related_to_hookshot.* = 0;
    }
    return y;
}

pub export fn AncillaAdd_ExplodingSomariaBlock(k: c_int) callconv(.c) void { // 89ad30
    const i: usize = @intCast(k);
    vars.ancilla_type[i] = 0x2e;
    vars.ancilla_numspr[i] = tables.kAncilla_Pflags[0x2e];
    vars.ancilla_aux_timer[i] = 3;
    vars.ancilla_step[i] = 0;
    vars.ancilla_item_to_link[i] = 0;
    vars.ancilla_arr3[i] = 0;
    vars.ancilla_arr1[i] = 0;
    vars.ancilla_R[i] = 0;
    vars.ancilla_objprio[i] = 0;
    vars.dung_flag_somaria_block_switch.* = 0;
    vars.sound_effect_2.* = Ancilla_CalculateSfxPan(k) | 1;
}

pub export fn AddSwordBeam(y: u8) callconv(.c) void { // 8ff67b
    const k = Ancilla_AddAncilla(0xc, y);
    if (k < 0) return;
    const i: usize = @intCast(k);
    const j: usize = @as(usize, vars.link_direction_facing.*) * 2;
    swordbeam_arr()[0] = tables.kSwordBeam_Tab[j + 0];
    swordbeam_arr()[1] = tables.kSwordBeam_Tab[j + 1];
    swordbeam_arr()[2] = tables.kSwordBeam_Tab[j + 2];
    swordbeam_arr()[3] = tables.kSwordBeam_Tab[j + 3];
    swordbeam_var1().* = tables.kSwordBeam_Tab[j + 3];
    vars.ancilla_aux_timer[i] = 2;
    vars.ancilla_item_to_link[i] = 0x4c;
    vars.ancilla_arr3[i] = 8;
    vars.ancilla_step[i] = 0;
    vars.ancilla_L[i] = 0;
    vars.ancilla_G[i] = 0;
    vars.ancilla_arr1[i] = 0;
    swordbeam_var2().* = 14;
    const d: usize = vars.link_direction_facing.* >> 1;
    vars.ancilla_dir[i] = @truncate(d);
    vars.ancilla_y_vel[i] = @bitCast(tables.kSwordBeam_Yvel[d]);
    vars.ancilla_x_vel[i] = @bitCast(tables.kSwordBeam_Xvel[d]);
    vars.ancilla_S[i] = @bitCast(tables.kSwordBeam_S[d]);

    swordbeam_temp_y().* = vars.link_y_coord.* +% 12;
    swordbeam_temp_x().* = vars.link_x_coord.* +% 8;

    if (Ancilla_CheckInitialTile_A(k) >= 0) {
        Ancilla_SetXY(
            k,
            swordbeam_temp_x().* +% signedOffset(tables.kSwordBeam_X[d]),
            swordbeam_temp_y().* +% signedOffset(tables.kSwordBeam_Y[d]),
        );
        vars.sound_effect_2.* = 1 | Ancilla_CalculateSfxPan(k);
        vars.ancilla_type[i] = 4;
        vars.ancilla_timer[i] = 7;
        vars.ancilla_numspr[i] = 16;
    }
}

pub export fn AncillaSpawn_SwordChargeSparkle() callconv(.c) void { // 8ff979
    const k = Ancilla_AllocHigh();
    if (k < 0) return;
    const i: usize = @intCast(k);
    vars.ancilla_type[i] = 0x3c;
    vars.ancilla_item_to_link[i] = 0;
    vars.ancilla_timer[i] = 4;
    vars.ancilla_floor[i] = vars.link_is_on_lower_level.*;
    const j: usize = vars.link_direction_facing.* >> 1;
    var x: i8 = 0;
    var y: i8 = 0;
    const m0 = tables.kSwordChargeSparkle_A[j];
    if (m0 == 0) {
        y = @bitCast(vars.link_spin_attack_step_counter.* >> 2);
        if (j == 0) y = -%y;
    }
    const m1 = tables.kSwordChargeSparkle_B[j];
    if (m1 == 0) {
        x = @bitCast(vars.link_spin_attack_step_counter.* >> 2);
        if (j == 2) x = -%x;
    }
    const r = misc.GetRandomNumber();
    Ancilla_SetXY(
        k,
        vars.link_x_coord.* +% signedOffset(x) +% tables.kSwordChargeSparkle_X[j] +% ((r & m1) >> 4),
        vars.link_y_coord.* +% signedOffset(y) +% tables.kSwordChargeSparkle_Y[j] +% (r & m0),
    );
}

const kAncilla_Funcs = [_]*const HandlerFuncK{
    Ancilla01_SomariaBullet,
    Ancilla02_FireRodShot,
    Ancilla_Empty,
    Ancilla04_BeamHit,
    Ancilla05_Boomerang,
    Ancilla06_WallHit,
    Ancilla07_Bomb,
    Ancilla08_DoorDebris,
    Ancilla09_Arrow,
    Ancilla0A_ArrowInTheWall,
    Ancilla0B_IceRodShot,
    Ancilla_SwordBeam,
    Ancilla0D_SpinAttackFullChargeSpark,
    Ancilla33_BlastWallExplosion,
    Ancilla33_BlastWallExplosion,
    Ancilla33_BlastWallExplosion,
    Ancilla11_IceRodWallHit,
    Ancilla33_BlastWallExplosion,
    Ancilla13_IceRodSparkle,
    Ancilla_Unused_14,
    Ancilla15_JumpSplash,
    Ancilla16_HitStars,
    Ancilla17_ShovelDirt,
    Ancilla18_EtherSpell,
    Ancilla19_BombosSpell,
    Ancilla1A_PowderDust,
    Ancilla_SwordWallHit,
    Ancilla1C_QuakeSpell,
    Ancilla1D_ScreenShake,
    Ancilla1E_DashDust,
    Ancilla1F_Hookshot,
    Ancilla20_Blanket,
    Ancilla21_Snore,
    Ancilla22_ItemReceipt,
    Ancilla23_LinkPoof,
    Ancilla24_Gravestone,
    Ancilla_Unused_25,
    Ancilla26_SwordSwingSparkle,
    Ancilla27_Duck,
    Ancilla28_WishPondItem,
    Ancilla29_MilestoneItemReceipt,
    Ancilla2A_SpinAttackSparkleA,
    Ancilla2B_SpinAttackSparkleB,
    Ancilla2C_SomariaBlock,
    Ancilla2D_SomariaBlockFizz,
    Ancilla2E_SomariaBlockFission,
    Ancilla2F_LampFlame,
    Ancilla30_ByrnaWindupSpark,
    Ancilla31_ByrnaSpark,
    Ancilla32_BlastWallFireball,
    Ancilla33_BlastWallExplosion,
    Ancilla34_SkullWoodsFire,
    Ancilla35_MasterSwordReceipt,
    Ancilla36_Flute,
    Ancilla37_WeathervaneExplosion,
    Ancilla38_CutsceneDuck,
    Ancilla39_SomariaPlatformPoof,
    Ancilla3A_BigBombExplosion,
    Ancilla3B_SwordUpSparkle,
    Ancilla3C_SpinAttackChargeSparkle,
    Ancilla3D_ItemSplash,
    Ancilla_RisingCrystal,
    Ancilla3F_BushPoof,
    Ancilla40_DwarfPoof,
    Ancilla41_WaterfallSplash,
    Ancilla42_HappinessPondRupees,
    Ancilla43_GanonsTowerCutscene,
};
// END REMAINING C BINDINGS
