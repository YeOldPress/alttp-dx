//! Port of src/attract.c: the attract-mode story sequence: the legend text
//! crawl, world map zoom, throne room, Zelda's prison and the maiden warp.
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl.zig");
const rtl_types = @import("zelda_rtl_types.zig");

const OamEnt = vars.OamEnt;
const g_ram = &vars.g_ram;
const g_zenv = &rtl_types.g_zenv;
const oam_buf = vars.oam_buf;
const bytewise_extended_oam = vars.bytewise_extended_oam;

// snes/snes_regs.h
const BG1SC = 0x2107;
const BG2SC = 0x2108;
const WH0 = 0x2126;
const WH2 = 0x2128;

pub const AttractOamInfo = extern struct {
    x: i8,
    y: i8,
    c: u8,
    f: u8,
    e: u8,
};

// dungeon.c
extern fn Dungeon_LoadEntrance() void;
extern fn Dungeon_LoadAndDrawRoom() void;
extern fn Dungeon_ResetTorchBackgroundAndPlayer() void;
// load_gfx.c
extern fn InitializeTilesets() void;
extern fn EnableForceBlank() void;
extern fn EraseTileMaps_normal() void;
extern fn Attract_LoadBG3GFX() void;
extern fn LoadCommonSprites() void;
extern fn Palette_BgAndFixedColor_Black() void;
extern fn Palette_Load_Sp0L() void;
extern fn Palette_Load_SpriteMain() void;
extern fn Palette_Load_Sp5L() void;
extern fn Palette_Load_Sp6L() void;
extern fn Palette_Load_SpriteEnvironment_Dungeon() void;
extern fn Palette_Load_HUD() void;
extern fn Palette_Load_DungeonSet() void;
extern fn Palette_Load_OWBGMain() void;
extern fn Palette_Load_LinkArmorAndGloves() void;
// overworld.c
extern fn Overworld_LoadAllPalettes() void;
extern fn WorldMap_LoadLightWorldMap() void;
// ending.c
extern fn Attract_SetUpConclusionHDMA() void;
extern fn Intro_HandleAllTriforceAnimations() void;
extern fn Intro_PeriodicSwordAndIntroFlash() void;
extern fn Intro_InitializeMemory_darken() void;
extern fn FadeMusicAndResetSRAMMirror() void;
extern fn HandleScreenFlash() void;
// messaging.c
extern fn RenderText() void;
// sprite.c
extern fn Sprite_SetX(k: c_int, x: u16) void;
extern fn Sprite_SetY(k: c_int, y: u16) void;
extern fn Sprite_Get16BitCoords(k: c_int) void;
extern fn SpritePrep_ResetProperties(k: c_int) void;
// sprite_main.c
extern fn Guard_HandleAllAnimation(k: c_int) void;

/// sprite.h, a static inline with no linkable symbol.
fn SetOamPlain(oam: [*]align(1) OamEnt, x: u8, y: u8, charnum: u8, flags: u8, big: u8) void {
    oam[0].x = x;
    oam[0].y = y;
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    const index = (@intFromPtr(oam) - @intFromPtr(oam_buf)) / @sizeOf(OamEnt);
    bytewise_extended_oam[index] = big;
}

fn sign8(v: u8) bool {
    return v & 0x80 != 0;
}

fn sign16(v: u16) bool {
    return v & 0x8000 != 0;
}

/// The low byte of a 16-bit work-ram variable, as the C's BYTE() macro reads it.
fn loPtr(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

pub export const kMapMode_Zooms1 = [240]u16{
    375, 374, 373, 373, 372, 371, 371, 370, 369, 369, 368, 367, 367, 366, 365, 365,
    364, 363, 363, 361, 361, 360, 359, 359, 358, 357, 357, 356, 355, 355, 354, 354,
    353, 352, 352, 351, 351, 350, 349, 349, 348, 348, 347, 346, 346, 345, 345, 344,
    343, 343, 342, 342, 341, 341, 340, 339, 339, 338, 338, 337, 337, 336, 335, 335,
    334, 334, 333, 333, 332, 332, 331, 331, 330, 330, 328, 327, 327, 326, 326, 325,
    325, 324, 324, 323, 323, 322, 322, 321, 321, 320, 320, 319, 319, 318, 318, 317,
    317, 316, 316, 315, 315, 314, 314, 313, 313, 312, 312, 311, 311, 310, 310, 309,
    309, 309, 308, 308, 307, 307, 306, 306, 305, 305, 304, 304, 303, 303, 303, 302,
    302, 301, 301, 300, 300, 299, 299, 299, 298, 298, 297, 297, 295, 295, 294, 294,
    294, 293, 293, 292, 292, 292, 291, 291, 290, 290, 289, 289, 289, 288, 288, 287,
    287, 287, 286, 286, 285, 285, 285, 284, 284, 283, 283, 283, 282, 282, 281, 281,
    281, 280, 280, 279, 279, 279, 278, 278, 278, 277, 277, 276, 276, 276, 275, 275,
    275, 274, 274, 273, 273, 273, 272, 272, 272, 271, 271, 271, 270, 270, 269, 269,
    269, 268, 268, 268, 267, 267, 267, 266, 266, 266, 265, 265, 265, 264, 264, 264,
    263, 263, 262, 262, 262, 261, 261, 261, 260, 260, 260, 259, 259, 259, 258, 258,
};
pub export const kMapMode_Zooms2 = [240]u16{
    136, 136, 135, 135, 135, 135, 135, 134, 134, 134, 133, 133, 133, 133, 132, 132,
    132, 132, 132, 131, 131, 131, 130, 130, 130, 130, 130, 129, 129, 129, 129, 129,
    128, 128, 128, 127, 127, 127, 127, 127, 126, 126, 126, 126, 126, 125, 125, 125,
    124, 124, 124, 124, 124, 124, 123, 123, 123, 123, 123, 122, 122, 122, 121, 121,
    121, 121, 121, 121, 120, 120, 120, 120, 120, 120, 119, 119, 119, 118, 118, 118,
    118, 118, 118, 117, 117, 117, 117, 117, 117, 116, 116, 116, 116, 115, 115, 115,
    115, 115, 115, 114, 114, 114, 114, 114, 114, 113, 113, 113, 113, 112, 112, 112,
    112, 112, 112, 112, 111, 111, 111, 111, 111, 111, 110, 110, 110, 110, 110, 109,
    109, 109, 109, 109, 109, 108, 108, 108, 108, 108, 108, 108, 107, 107, 107, 107,
    107, 106, 106, 106, 106, 106, 106, 106, 105, 105, 105, 105, 105, 105, 105, 104,
    104, 104, 104, 104, 103, 103, 103, 103, 103, 103, 103, 103, 102, 102, 102, 102,
    102, 102, 102, 101, 101, 101, 101, 101, 101, 100, 100, 100, 100, 100, 100, 100,
    100, 99,  99,  99,  99,  99,  99,  99,  99,  98,  98,  98,  98,  98,  97,  97,
    97,  97,  97,  97,  97,  97,  97,  96,  96,  96,  96,  96,  96,  96,  96,  96,
    95,  95,  95,  95,  95,  95,  95,  94,  94,  94,  94,  94,  94,  94,  94,  94,
};

const kAttract_Legendgraphics_0 = [157 + 1]u8{
    0x61, 0x65, 0x40, 0x28, 0,    0x35, 0x61, 0x85, 0x40, 0x28, 0x10, 0x35, 0x61, 0xa5, 0,    0x29,
    1,    0x35, 2,    0x35, 1,    0x35, 2,    0x35, 1,    0x35, 2,    0x35, 1,    0x35, 2,    0x35,
    1,    0x35, 3,    0x31, 3,    0x71, 2,    0x35, 1,    0x35, 2,    0x35, 1,    0x35, 2,    0x35,
    1,    0x35, 2,    0x35, 1,    0x35, 2,    0x35, 1,    0x35, 0x61, 0xc5, 0,    0x29, 0x11, 0x35,
    0x12, 0x35, 0x11, 0x35, 0x12, 0x35, 0x11, 0x35, 0x12, 0x35, 0x11, 0x35, 0x12, 0x35, 0x11, 0x35,
    0x13, 0x35, 0x13, 0x75, 0x12, 0x35, 0x11, 0x35, 0x12, 0x35, 0x11, 0x35, 0x12, 0x35, 0x11, 0x35,
    0x12, 0x35, 0x11, 0x35, 0x12, 0x35, 0x11, 0x35, 0x61, 0xe5, 0,    0x29, 0x20, 0x35, 0x21, 0x35,
    0x20, 0x35, 0x21, 0x35, 0x20, 0x35, 0x21, 0x35, 0x20, 0x35, 0x21, 0x35, 0x20, 0x35, 0x21, 0x35,
    0x20, 0x35, 0x21, 0x35, 0x20, 0x35, 0x21, 0x35, 0x20, 0x35, 0x21, 0x35, 0x20, 0x35, 0x21, 0x35,
    0x20, 0x35, 0x21, 0x35, 0x20, 0x35, 0x62, 5,    0x40, 0x28, 0,    0xb5, 0xff, 0x61,
};
const kAttract_Legendgraphics_1 = [237 + 1]u8{
    0x61, 0x65, 0x40, 0x28, 0,    0x35, 0x61, 0x85, 0,    0x13, 0x10, 0x35, 0x4e, 0x75, 0x6e, 0x35,
    0x10, 0x35, 0x4e, 0x35, 0x10, 0x35, 0x4c, 0x35, 0x10, 0x35, 0x4e, 0x75, 0x49, 0x35, 0x61, 0x8f,
    0x40, 8,    0x10, 0x35, 0x61, 0x94, 0,    0xb,  0x4e, 0x75, 0x6e, 0x35, 0x10, 0x35, 0x4e, 0x35,
    0x10, 0x35, 0x4c, 0x35, 0x61, 0xa5, 0,    0x29, 0x5f, 0x75, 0x5e, 0x75, 0x7e, 0x35, 0x7f, 0x35,
    0x5e, 0x35, 0x5f, 0x35, 0x4d, 0x35, 0x5f, 0x75, 0x5e, 0x75, 0x4a, 0x35, 0x4b, 0x35, 0x10, 0x35,
    0x49, 0x75, 0x10, 0x35, 0x5f, 0x75, 0x5e, 0x75, 0x7e, 0x35, 0x7f, 0x35, 0x5e, 0x35, 0x5f, 0x35,
    0x4d, 0x35, 0x61, 0xc5, 0,    0x29, 0x50, 0x35, 0x51, 0x35, 0x52, 0x35, 0x53, 0x35, 0x54, 0x35,
    0x55, 0x35, 0x56, 0x35, 0x57, 0x35, 0x58, 0x35, 0x59, 0x35, 0x5a, 0x35, 0x5b, 0x35, 0x5c, 0x35,
    0x5d, 0x35, 0x50, 0x35, 0x51, 0x35, 0x52, 0x35, 0x53, 0x35, 0x54, 0x35, 0x55, 0x35, 0x56, 0x35,
    0x61, 0xe5, 0,    0x29, 0x60, 0x35, 0x61, 0x35, 0x62, 0x35, 0x63, 0x35, 0x64, 0x35, 0x65, 0x35,
    0x66, 0x35, 0x67, 0x35, 0x68, 0x35, 0x69, 0x35, 0x6a, 0x35, 0x6b, 0x35, 0x6c, 0x35, 0x6d, 0x35,
    0x60, 0x35, 0x61, 0x35, 0x62, 0x35, 0x63, 0x35, 0x64, 0x35, 0x65, 0x35, 0x66, 0x35, 0x62, 5,
    0,    0x29, 0x70, 0x35, 0x71, 0x35, 0x72, 0x35, 0x73, 0x35, 0x74, 0x35, 0x75, 0x35, 0x76, 0x35,
    0x77, 0x35, 0x78, 0x35, 0x79, 0x35, 0x7a, 0x35, 0x7b, 0x35, 0x7c, 0x35, 0x7d, 0x35, 0x70, 0x35,
    0x71, 0x35, 0x72, 0x35, 0x73, 0x35, 0x74, 0x35, 0x75, 0x35, 0x76, 0x35, 0xff, 0x61,
};
const kAttract_Legendgraphics_2 = [199 + 1]u8{
    0x61, 0x65, 0x40, 0x28, 0,    0x35, 0x61, 0x85, 0x40, 0x28, 0x10, 0x35, 0x61, 0xa5, 0,    0x1d,
    0x22, 0x35, 0x23, 0x35, 0x10, 0x35, 0x22, 0x35, 0x23, 0x35, 0x10, 0x35, 0x22, 0x35, 0x23, 0x35,
    0x10, 0x35, 0x22, 0x35, 0x23, 0x35, 0x10, 0x35, 0x10, 0x75, 0x23, 0x75, 0x22, 0x75, 0x61, 0xb4,
    0x40, 6,    0x10, 0x35, 0x61, 0xb8, 0,    3,    0x23, 0x75, 0x22, 0x75, 0x61, 0xc5, 0,    0x29,
    4,    0x35, 5,    0x35, 6,    0x35, 4,    0x35, 5,    0x35, 6,    0x35, 4,    0x35, 5,    0x35,
    6,    0x35, 4,    0x35, 5,    0x35, 6,    0x35, 6,    0x75, 5,    0x75, 4,    0x75, 0x10, 0x75,
    0x23, 0x75, 0x22, 0x75, 6,    0x75, 5,    0x75, 4,    0x75, 0x61, 0xe5, 0,    0x29, 0x14, 0x35,
    0x15, 0x35, 0x16, 0x35, 0x14, 0x35, 0x15, 0x35, 0x16, 0x35, 0x14, 0x35, 0x15, 0x35, 0x16, 0x35,
    0x14, 0x35, 0x15, 0x35, 0x16, 0x35, 0x16, 0x75, 0x15, 0x75, 0x14, 0x75, 6,    0x75, 5,    0x75,
    4,    0x75, 0x16, 0x75, 0x15, 0x75, 0x14, 0x75, 0x62, 5,    0,    0x29, 0x24, 0x35, 0x25, 0x35,
    0x26, 0x35, 0x24, 0x35, 0x25, 0x35, 0x26, 0x35, 0x24, 0x35, 0x25, 0x35, 0x26, 0x35, 0x24, 0x35,
    0x25, 0x35, 0x26, 0x35, 0x26, 0x75, 0x25, 0x75, 0x24, 0x75, 0x26, 0x75, 0x25, 0x75, 0x24, 0x75,
    0x26, 0x75, 0x25, 0x75, 0x24, 0x75, 0xff, 0x61,
};
const kAttract_Legendgraphics_3 = [265 + 1]u8{
    0x61, 0x65, 0,    0x29, 0,    0x35, 0,    0x35, 0x1b, 0x35, 0x30, 0x35, 0x31, 0x35, 0x32, 0x35,
    0,    0x35, 0,    0x35, 0,    0x35, 0x33, 0x35, 0x41, 0x35, 0x41, 0x75, 0x33, 0x75, 0,    0x75,
    0,    0x75, 0,    0x75, 0x32, 0x75, 0x31, 0x75, 0x30, 0x75, 0x1b, 0x75, 0,    0x75, 0x61, 0x85,
    0x40, 0x1e, 0x10, 0x35, 0x61, 0x86, 0,    9,    0x34, 0x35, 0xb,  0x35, 0x40, 0x35, 0x41, 0x35,
    0x42, 0x35, 0x61, 0x95, 0,    9,    0x42, 0x75, 0x41, 0x75, 0x40, 0x75, 0xb,  0x75, 0x34, 0x75,
    0x61, 0xa5, 0,    0x29, 0x43, 0x35, 0x44, 0x35, 7,    0x35, 8,    0x35, 9,    0x35, 0xa,  0x35,
    0x10, 0x35, 0xc,  0x35, 0xd,  0x35, 0xe,  0x35, 0xf,  0x35, 0xf,  0x75, 0xe,  0x75, 0xd,  0x75,
    0xc,  0x75, 0x10, 0x75, 0xa,  0x75, 9,    0x75, 8,    0x75, 7,    0x75, 0x44, 0x75, 0x61, 0xc5,
    0,    0x29, 0x35, 0x35, 0x36, 0x35, 0x17, 0x35, 0x18, 0x35, 0x19, 0x35, 0x1a, 0x35, 0x10, 0x35,
    0x1c, 0x35, 0x1d, 0x35, 0x1e, 0x35, 0x1f, 0x35, 0x1f, 0x75, 0x1e, 0x75, 0x1d, 0x75, 0x1c, 0x75,
    0x10, 0x75, 0x1a, 0x75, 0x19, 0x75, 0x18, 0x75, 0x17, 0x75, 0x36, 0x75, 0x61, 0xe5, 0,    0x29,
    0x45, 0x35, 0x46, 0x35, 0x27, 0x35, 0x28, 0x35, 0x29, 0x35, 0x2a, 0x35, 0x2b, 0x35, 0x2c, 0x35,
    0x2d, 0x35, 0x2e, 0x35, 0x2f, 0x35, 0x2f, 0x75, 0x2e, 0x75, 0x2d, 0x75, 0x2c, 0x75, 0x2b, 0x75,
    0x2a, 0x75, 0x29, 0x75, 0x28, 0x75, 0x27, 0x75, 0x46, 0x75, 0x62, 5,    0,    0x29, 0x47, 0x35,
    0x48, 0x35, 0x37, 0x35, 0x38, 0x35, 0x39, 0x35, 0x3a, 0x35, 0x3b, 0x35, 0x3c, 0x35, 0x3d, 0x35,
    0x3e, 0x35, 0x3f, 0x35, 0x3f, 0x75, 0x3e, 0x75, 0x3d, 0x75, 0x3c, 0x75, 0x3b, 0x75, 0x3a, 0x75,
    0x39, 0x75, 0x38, 0x75, 0x37, 0x75, 0x48, 0x75, 0xff, 0x0,
};

pub export fn Attract_DrawSpriteSet2(p: [*]const AttractOamInfo, n: c_int) callconv(.c) void {
    var oam = oam_buf + (@as(usize, vars.attract_oam_idx.*) + 64);
    vars.attract_oam_idx.* +%= @truncate(@as(c_uint, @bitCast(n)));
    // The C counts n down while walking oam forward.
    var i = n;
    while (i > 0) {
        i -= 1;
        const e = p[@intCast(i)];
        SetOamPlain(
            oam,
            vars.attract_x_base.* +% @as(u8, @bitCast(e.x)),
            vars.attract_y_base.* +% @as(u8, @bitCast(e.y)),
            e.c,
            e.f,
            e.e,
        );
        oam += 1;
    }
}

const kZeldaPrison_Oams0 = [6]AttractOamInfo{
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x84, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x84, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa4, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa4, .f = 0x7b, .e = 2 },
};

pub export fn Attract_ZeldaPrison_Case0() callconv(.c) void {
    if (vars.attract_var4.* == 0)
        vars.attract_var5.* +%= 1;
    if (vars.frame_counter.* & 1 != 0)
        vars.attract_vram_dst.* -%= 1;
    vars.attract_x_base.* = 0x58;
    vars.attract_y_base.* = vars.attract_var9.*;
    Attract_DrawSpriteSet2(&kZeldaPrison_Oams0, 6);
    vars.attract_var7.* = 0xf8d9;
}

const kZeldaPrison_Oams1 = [30]AttractOamInfo{
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x84, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x84, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa4, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa4, .f = 0x7b, .e = 2 },

    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0xc4, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0xc2, .f = 0x3b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xe4, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xe6, .f = 0x3b, .e = 2 },

    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x88, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x8a, .f = 0x3b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa8, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xaa, .f = 0x3b, .e = 2 },

    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x82, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x82, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa2, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa2, .f = 0x7b, .e = 2 },

    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x80, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x80, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa0, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa0, .f = 0x7b, .e = 2 },
};

pub export fn Attract_ZeldaPrison_Case1() callconv(.c) void {
    var k: usize = undefined;
    var decided = false;

    // The C evaluates ShowTimedTextMessage inside the && via the comma operator,
    // so it only runs when the first test passes.
    if (vars.attract_var10.* < 0x80) {
        Attract_ShowTimedTextMessage();
        if (vars.oam_priority_value.* != 0) {
            k = 4;
            decided = true;
        }
    }
    if (!decided) {
        if (vars.attract_var9.* != 0x6e) {
            vars.attract_var9.* -%= 1;
            k = 0;
        } else {
            if (vars.attract_var10.* < 31 and (vars.attract_var10.* & 1) == 0)
                vars.INIDISP_copy.* -%= 1;
            vars.attract_var10.* -%= 1;
            if (vars.attract_var10.* == 0) {
                vars.attract_sequence.* +%= 1;
                vars.attract_state.* -%= 2;
                return;
            }
            const v = vars.attract_var10.*;
            k = if (v >= 0xc0) 0 else if (v >= 0xb8) 1 else if (v >= 0xb0) 2 else if (v >= 0xa0) 3 else 4;
        }
    }
    if (vars.frame_counter.* & 1 != 0)
        vars.attract_vram_dst.* -%= 1;
    vars.attract_x_base.* = 0x58;
    vars.attract_y_base.* = vars.attract_var9.*;
    Attract_DrawSpriteSet2(kZeldaPrison_Oams1[k * 6 ..].ptr, 6);
}

pub export fn Attract_ZeldaPrison_DrawA() callconv(.c) void {
    const oam = oam_buf + (64 + @as(usize, vars.attract_oam_idx.*));
    const ext: u8 = if (vars.attract_x_base_hi.* != 0) 3 else 2;
    const j: u8 = (vars.attract_var1.* >> 3) & 1;
    SetOamPlain(oam + 0, vars.attract_x_base.*, vars.attract_y_base.* +% j, 6, 0x3d, ext);
    SetOamPlain(oam + 1, vars.attract_x_base.*, vars.attract_y_base.* +% 10, if (j != 0) 10 else 8, 0x3d, ext);
    vars.attract_oam_idx.* +%= 2;
}

pub export fn Attract_MaidenWarp_Case0() callconv(.c) void {
    if (vars.attract_var11.* != 0)
        vars.attract_var5.* +%= 1;
}

const kZeldaPrison_MaidenWarpCase1_Oam = [28]AttractOamInfo{
    .{ .x = 0, .y = 0, .c = 0xce, .f = 0x35, .e = 0 },
    .{ .x = 28, .y = 0, .c = 0xce, .f = 0x35, .e = 0 },
    .{ .x = -2, .y = 3, .c = 0x26, .f = 0x75, .e = 0 },
    .{ .x = 30, .y = 3, .c = 0x26, .f = 0x35, .e = 0 },
    .{ .x = -2, .y = 11, .c = 0x36, .f = 0x75, .e = 0 },
    .{ .x = 30, .y = 11, .c = 0x36, .f = 0x35, .e = 0 },
    .{ .x = 0, .y = 16, .c = 0x26, .f = 0x75, .e = 0 },
    .{ .x = 28, .y = 16, .c = 0x26, .f = 0x35, .e = 0 },
    .{ .x = 0, .y = 24, .c = 0x36, .f = 0x75, .e = 0 },
    .{ .x = 28, .y = 24, .c = 0x36, .f = 0x35, .e = 0 },
    .{ .x = 2, .y = 16, .c = 0x20, .f = 0x35, .e = 2 },
    .{ .x = 18, .y = 16, .c = 0x20, .f = 0x75, .e = 2 },
    .{ .x = 2, .y = 32, .c = 0x20, .f = 0xb5, .e = 2 },
    .{ .x = 18, .y = 32, .c = 0x20, .f = 0xf5, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0xce, .f = 0x37, .e = 0 },
    .{ .x = 28, .y = 0, .c = 0xce, .f = 0x37, .e = 0 },
    .{ .x = -2, .y = 3, .c = 0x26, .f = 0x77, .e = 0 },
    .{ .x = 30, .y = 3, .c = 0x26, .f = 0x37, .e = 0 },
    .{ .x = -2, .y = 11, .c = 0x36, .f = 0x77, .e = 0 },
    .{ .x = 30, .y = 11, .c = 0x36, .f = 0x37, .e = 0 },
    .{ .x = 0, .y = 16, .c = 0x26, .f = 0x77, .e = 0 },
    .{ .x = 28, .y = 16, .c = 0x26, .f = 0x37, .e = 0 },
    .{ .x = 0, .y = 24, .c = 0x36, .f = 0x77, .e = 0 },
    .{ .x = 28, .y = 24, .c = 0x36, .f = 0x37, .e = 0 },
    .{ .x = 2, .y = 16, .c = 0x22, .f = 0x37, .e = 2 },
    .{ .x = 18, .y = 16, .c = 0x22, .f = 0x77, .e = 2 },
    .{ .x = 2, .y = 32, .c = 0x22, .f = 0xb7, .e = 2 },
    .{ .x = 18, .y = 32, .c = 0x22, .f = 0xf7, .e = 2 },
};
const kAttract_MaidenWarp_Case1_Num = [8]u8{ 2, 2, 2, 6, 6, 10, 10, 14 };

pub export fn Attract_MaidenWarp_Case1() callconv(.c) void {
    const k: usize = (vars.frame_counter.* >> 2) & 1;
    vars.attract_x_base.* = 110;
    vars.attract_y_base.* = 72;
    Attract_DrawSpriteSet2(
        kZeldaPrison_MaidenWarpCase1_Oam[k * 14 ..].ptr,
        kAttract_MaidenWarp_Case1_Num[(vars.attract_var21.* >> 1) & 7],
    );

    if (vars.attract_var21.* == 0 and vars.attract_var20.* == 0x70)
        vars.sound_effect_2.* = 0x27;

    if (vars.attract_var21.* == 15) {
        vars.attract_var5.* +%= 1;
    } else {
        if (vars.attract_var21.* == 6) {
            vars.intro_times_pal_flash.* = 0x90;
            vars.sound_effect_2.* = 0x2b;
        }
        if (vars.attract_var20.* != 0) {
            vars.attract_var20.* -%= 1;
        } else {
            vars.attract_var21.* +%= 1;
        }
    }
}

const kMaidenWarp_Case2_Num = [8]u8{ 4, 4, 8, 8, 12, 12, 14, 14 };
const kAttract_MaidenWarpCase2_Oam = kZeldaPrison_MaidenWarpCase1_Oam;

pub export fn Attract_MaidenWarp_Case2() callconv(.c) void {
    vars.attract_x_base.* = 110;
    vars.attract_y_base.* = 72;
    const k: usize = (vars.frame_counter.* >> 2) & 1;
    const n = kMaidenWarp_Case2_Num[(vars.attract_var21.* >> 1) & 7];
    Attract_DrawSpriteSet2(kAttract_MaidenWarpCase2_Oam[k * 14 + (14 - n) ..].ptr, n);
    if (vars.attract_var21.* == 0) {
        vars.attract_var19.* -%= 1;
        if (vars.attract_var19.* == 0)
            vars.attract_var5.* +%= 1;
    } else {
        vars.attract_var21.* -%= 1;
    }
}

const kAttract_MaidenWarpCase3_Oam = [3]AttractOamInfo{
    .{ .x = 0, .y = 0, .c = 0xc6, .f = 0x3d, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x24, .f = 0x35, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x24, .f = 0x75, .e = 2 },
};
const kMaidenWarp_Case3_Xbase = [2]u8{ 0x78, 0x70 };

pub export fn Attract_MaidenWarp_Case3() callconv(.c) void {
    if (vars.attract_var21.* == 6) {
        vars.attract_var15.* +%= 1;
        vars.sound_effect_1.* = 51;
    } else if (vars.attract_var21.* == 0x40) {
        vars.attract_var21.* = 224;
        vars.attract_var5.* +%= 1;
    } else if (vars.attract_var21.* < 0xf) {
        const k: usize = (vars.attract_var21.* >> 3) & 1;
        vars.attract_x_base.* = kMaidenWarp_Case3_Xbase[k];
        vars.attract_y_base.* = 0x60;
        Attract_DrawSpriteSet2(kAttract_MaidenWarpCase3_Oam[k..].ptr, if (k != 0) 2 else 1);
    }
    vars.attract_var21.* +%= 1;
}

pub export fn Attract_MaidenWarp_Case4() callconv(.c) void {
    Attract_ShowTimedTextMessage();
    if (vars.oam_priority_value.* == 0) {
        if (vars.attract_var21.* < 31 and (vars.attract_var21.* & 1) == 0)
            vars.INIDISP_copy.* -%= 1;
        vars.attract_var21.* -%= 1;
        if (vars.attract_var21.* == 0)
            vars.attract_var22.* +%= 1;
    }
}

pub export fn Dungeon_LoadAndDrawEntranceRoom(a: u8) callconv(.c) void { // 82c533
    vars.attract_room_index.* = a;
    Dungeon_LoadEntrance();
    vars.dung_num_lit_torches.* = 0;
    vars.hdr_dungeon_dark_with_lantern.* = 0;
    Dungeon_LoadAndDrawRoom();
    Dungeon_ResetTorchBackgroundAndPlayer();
}

pub export fn Dungeon_SaveAndLoadLoadAllPalettes(a: u8, k: u8) callconv(.c) void { // 82c546
    vars.sprite_graphics_index.* = k;
    vars.main_tile_theme_index.* = a;
    vars.aux_tile_theme_index.* = a;
    InitializeTilesets();
    vars.overworld_palette_aux_or_main.* = 0x200;
    vars.flag_update_cgram_in_nmi.* +%= 1;
    Palette_BgAndFixedColor_Black();
    Palette_Load_Sp0L();
    Palette_Load_SpriteMain();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
    Palette_Load_SpriteEnvironment_Dungeon();
    Palette_Load_HUD();
    Palette_Load_DungeonSet();
}

pub export fn Module14_Attract() callconv(.c) void { // 8cedad
    var st = vars.attract_state.*;
    if (vars.INIDISP_copy.* != 0 and vars.INIDISP_copy.* != 128 and st != 0 and
        st != 2 and st != 6 and (vars.filtered_joypad_H.* & 0x90) != 0)
    {
        st = 9;
        vars.attract_state.* = 9;
    }

    switch (st) {
        0 => Attract_Fade(),
        1 => Attract_InitGraphics(),
        2 => Attract_FadeOutSequence(),
        3 => Attract_LoadNewScene(),
        4 => Attract_FadeInSequence(),
        5 => Attract_EnactStory(),
        6 => Attract_FadeOutSequence(),
        7 => Attract_LoadNewScene(),
        8 => Attract_EnactStory(),
        9 => Attract_SkipToFileSelect(),
        else => {},
    }
}

pub export fn Attract_Fade() callconv(.c) void { // 8cede6
    Intro_HandleAllTriforceAnimations();
    vars.intro_did_run_step.* = 0;
    vars.is_nmi_thread_active.* = 0;
    Intro_PeriodicSwordAndIntroFlash();
    if (vars.INIDISP_copy.* != 0) {
        vars.INIDISP_copy.* -%= 1;
        return;
    }
    EnableForceBlank();
    vars.irq_flag.* = 255;
    vars.is_nmi_thread_active.* = 0;
    vars.nmi_flag_update_polyhedral.* = 0;
    vars.attract_state.* +%= 1;
}

pub export fn Attract_InitGraphics() callconv(.c) void { // 8cee0c
    // attract_var12 lives at g_ram[0x20]; the C clears 0x51 bytes from there.
    @memset(g_ram[0x20..][0..0x51], 0);
    EraseTileMaps_normal();
    Attract_LoadBG3GFX();
    vars.overworld_palette_mode.* = 4;
    vars.hud_palette.* = 1;
    vars.overworld_palette_aux_or_main.* = 0;
    Palette_Load_HUD();
    vars.overworld_palette_aux_or_main.* = 0x200;
    Palette_Load_OWBGMain();
    Palette_Load_HUD();
    Palette_Load_LinkArmorAndGloves();
    vars.main_palette_buffer[0x1d] = 0x3800;
    vars.flag_update_cgram_in_nmi.* +%= 1;
    loPtr(vars.BG3VOFS_copy2).* = 20;
    Attract_BuildBackgrounds();
    vars.messaging_module.* = 0;
    vars.dialogue_message_index.* = 0x112;
    vars.BG2VOFS_copy2.* = 0;
    vars.attract_legend_ctr.* = 0x1010;
    vars.attract_state.* +%= 3;
    rtl.HdmaSetup(0xCFA87, 0xCFA94, 1, @truncate(WH0), @truncate(WH2), 0);
    vars.HDMAEN_copy.* = 0xc0;

    vars.W12SEL_copy.* = 0;
    vars.W34SEL_copy.* = 0;
    vars.WOBJSEL_copy.* = 0xb0;
    vars.TMW_copy.* = 3;
    vars.TSW_copy.* = 0;
    vars.COLDATA_copy0.* = 0x25;
    vars.COLDATA_copy1.* = 0x45;
    vars.COLDATA_copy2.* = 0x85;
    vars.CGWSEL_copy.* = 0x10;
    vars.CGADSUB_copy.* = 0xa3;

    vars.music_control.* = 6;
    vars.attract_legend_flag.* +%= 1;
}

pub export fn Attract_FadeInStep() callconv(.c) void { // 8ceea6
    if (vars.INIDISP_copy.* != 15) {
        vars.link_speed_setting.* -%= 1;
        if (sign8(vars.link_speed_setting.*)) {
            vars.INIDISP_copy.* +%= 1;
            vars.link_speed_setting.* = 1;
        }
    } else {
        vars.attract_var18.* +%= 1;
    }
}

pub export fn Attract_FadeInSequence() callconv(.c) void { // 8ceeba
    if (vars.INIDISP_copy.* != 15) {
        vars.link_speed_setting.* -%= 1;
        if (sign8(vars.link_speed_setting.*)) {
            vars.INIDISP_copy.* +%= 1;
            vars.link_speed_setting.* = 1;
        }
    } else {
        vars.attract_state.* +%= 1;
    }
}

pub export fn Attract_FadeOutSequence() callconv(.c) void { // 8ceecb
    if (vars.INIDISP_copy.* != 0) {
        vars.link_speed_setting.* -%= 1;
        if (sign8(vars.link_speed_setting.*)) {
            vars.INIDISP_copy.* -%= 1;
            vars.link_speed_setting.* = 1;
        }
    } else {
        EnableForceBlank();
        EraseTileMaps_normal();
        vars.attract_state.* +%= 1;
    }
}

pub export fn Attract_LoadNewScene() callconv(.c) void { // 8ceee5
    switch (vars.attract_sequence.*) {
        0 => AttractScene_PolkaDots(),
        1 => AttractScene_WorldMap(),
        2 => AttractScene_ThroneRoom(),
        3 => Attract_PrepZeldaPrison(),
        4 => Attract_PrepMaidenWarp(),
        5 => AttractScene_EndOfStory(),
        else => {},
    }
}

pub export fn AttractScene_PolkaDots() callconv(.c) void { // 8ceef8
    vars.attract_next_legend_gfx.* = 0;
    vars.attract_state.* +%= 1;
    vars.INIDISP_copy.* = 0;
}

pub export fn AttractScene_WorldMap() callconv(.c) void { // 8ceeff
    rtl.zelda_ppu_write(BG1SC, 0x13);
    rtl.zelda_ppu_write(BG2SC, 0x3);
    vars.CGWSEL_copy.* = 0x80;
    vars.CGADSUB_copy.* = 0x21;
    vars.BGMODE_copy.* = 7;
    WorldMap_LoadLightWorldMap();
    vars.M7Y_copy.* = 0xed;
    vars.M7X_copy.* = 0x100;
    vars.BG1HOFS_copy.* = 0x80;
    vars.BG1VOFS_copy.* = 0xc0;
    vars.timer_for_mode7_zoom.* = 255;
    Attract_ControlMapZoom();
    vars.attract_var10.* = 1;
    vars.attract_state.* +%= 1;
    vars.INIDISP_copy.* = 0;
}

pub export fn AttractScene_ThroneRoom() callconv(.c) void { // 8cef4e
    vars.HDMAEN_copy.* = 0;
    vars.CGWSEL_copy.* = 2;
    vars.CGADSUB_copy.* = 0x20;
    vars.misc_sprites_graphics_index.* = 10;
    LoadCommonSprites();
    const bak0 = vars.attract_var12.*;
    const bak1 = std.mem.readInt(u16, @as([*]u8, @ptrCast(vars.attract_state))[0..2], .little);
    Dungeon_LoadAndDrawEntranceRoom(0x74);
    std.mem.writeInt(u16, @as([*]u8, @ptrCast(vars.attract_state))[0..2], bak1, .little);
    vars.attract_var12.* = bak0;
    vars.palette_main_indoors.* = 0;
    vars.palette_sp0l.* = 0;
    vars.palette_sp5l.* = 14;
    vars.palette_sp6l.* = 3;
    Dungeon_SaveAndLoadLoadAllPalettes(0, 0x7e);

    vars.main_palette_buffer[0x1d] = 0x3800;
    vars.messaging_module.* = 0;
    vars.dialogue_message_index.* = 0x113;
    vars.attract_var10.* = 2;
    vars.attract_var13.* = 0xe0;
    vars.oam_priority_value.* = 0x210;

    Attract_PrepFinish();
}

pub export fn Attract_PrepFinish() callconv(.c) void { // 8cefc0
    vars.attract_state.* +%= 1;
    vars.INIDISP_copy.* = 0;
    loPtr(vars.BG3VOFS_copy2).* = 0;
    vars.BG2HOFS_copy.* &= 0x1ff;
    vars.BG2VOFS_copy.* &= 0x1ff;
    vars.BG2HOFS_copy2.* &= 0x1ff;
    vars.BG2VOFS_copy2.* &= 0x1ff;
}

pub export fn Attract_PrepZeldaPrison() callconv(.c) void { // 8cefe3
    vars.CGWSEL_copy.* = 0;
    vars.CGADSUB_copy.* = 0;

    const bak0 = vars.attract_var12.*;
    const bak1 = std.mem.readInt(u16, @as([*]u8, @ptrCast(vars.attract_state))[0..2], .little);
    Dungeon_LoadAndDrawEntranceRoom(0x73);
    std.mem.writeInt(u16, @as([*]u8, @ptrCast(vars.attract_state))[0..2], bak1, .little);
    vars.attract_var12.* = bak0;

    vars.palette_main_indoors.* = 2;
    vars.palette_sp0l.* = 0;
    vars.palette_sp5l.* = 14;
    vars.palette_sp6l.* = 3;
    Dungeon_SaveAndLoadLoadAllPalettes(1, 0x7f);
    vars.main_palette_buffer[0x1d] = 0x3800;

    vars.messaging_module.* = 0;
    vars.dialogue_message_index.* = 0x114;

    vars.attract_var9.* = 148;
    vars.attract_vram_dst.* = 0x68;
    vars.attract_var1.* = 0;
    vars.attract_var3.* = 0;
    vars.attract_x_base_hi.* = 0;
    vars.attract_var17.* = 0;
    vars.attract_var18.* = 0;
    vars.attract_var10.* = 255;
    vars.oam_priority_value.* = 0x240;
    Attract_PrepFinish();
}

pub export fn Attract_PrepMaidenWarp() callconv(.c) void { // 8cf058
    const bak0 = vars.attract_var12.*;
    const bak1 = std.mem.readInt(u16, @as([*]u8, @ptrCast(vars.attract_state))[0..2], .little);
    Dungeon_LoadAndDrawEntranceRoom(0x75);
    std.mem.writeInt(u16, @as([*]u8, @ptrCast(vars.attract_state))[0..2], bak1, .little);
    vars.attract_var12.* = bak0;

    vars.palette_main_indoors.* = 0;
    vars.palette_sp0l.* = 0;
    vars.palette_sp5l.* = 14;
    vars.palette_sp6l.* = 3;

    vars.overworld_palette_aux_or_main.* = 0;
    Palette_Load_Sp0L();
    Palette_Load_SpriteMain();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
    Palette_Load_SpriteEnvironment_Dungeon();
    Palette_Load_HUD();
    Palette_Load_DungeonSet();
    Dungeon_SaveAndLoadLoadAllPalettes(2, 0x7f);
    vars.main_palette_buffer[0x1d] = 0x3800;
    vars.aux_palette_buffer[0x1d] = 0x3800;

    vars.messaging_module.* = 0;
    vars.dialogue_message_index.* = 0x115;
    vars.attract_var10.* = 255;
    loPtr(vars.attract_vram_dst).* = 112;
    vars.attract_var19.* = 112;
    vars.attract_var20.* = 112;
    vars.attract_var1.* = 8;
    vars.attract_var17.* = 0;
    vars.attract_var21.* = 0;
    vars.attract_var15.* = 0;
    vars.attract_var18.* = 0;
    vars.attract_var5.* = 0;
    vars.attract_var11.* = 0;

    vars.oam_priority_value.* = 0xc0;
    Attract_PrepFinish();
}

pub export fn AttractScene_EndOfStory() callconv(.c) void { // 8cf0dc
    Attract_SetUpConclusionHDMA();
    Death_Func31();
}

pub export fn Death_Func31() callconv(.c) void { // 8cf0e2
    vars.nmi_disable_core_updates.* +%= 1;
    Intro_InitializeMemory_darken();
    Overworld_LoadAllPalettes();
    loPtr(vars.BG3VOFS_copy2).* = 0;
    vars.M7Y_copy.* = 0;
    vars.M7X_copy.* = 0;
    vars.BG1HOFS_copy.* = 0;
    vars.BG1VOFS_copy.* = 0;
    vars.BG2HOFS_copy.* = 0;
    vars.BG2VOFS_copy.* = 0;
    vars.music_control.* = 0xF1;
    vars.attract_sequence.* = 0;
    vars.main_module_index.* = 0;
    vars.submodule_index.* = 10;
    vars.subsubmodule_index.* = 10;
}

pub export fn Attract_EnactStory() callconv(.c) void { // 8cf115
    switch (vars.attract_sequence.*) {
        0 => AttractDramatize_PolkaDots(),
        1 => AttractDramatize_WorldMap(),
        2 => Attract_ThroneRoom(),
        3 => AttractDramatize_Prison(),
        4 => AttractDramatize_AgahnimAltar(),
        else => {},
    }
}

pub export fn AttractDramatize_PolkaDots() callconv(.c) void { // 8cf126
    if ((vars.frame_counter.* & 3) == 0) {
        loPtr(vars.BG1VOFS_copy).* +%= 1;
        loPtr(vars.BG1HOFS_copy).* +%= 1;
        loPtr(vars.BG2VOFS_copy).* +%= 1;
        loPtr(vars.BG2HOFS_copy).* -%= 1;
    }

    if (vars.attract_legend_flag.* != 0) {
        Attract_BuildNextImageTileMap();
        vars.attract_legend_flag.* = 0;
        vars.attract_next_legend_gfx.* +%= 2;
    }
    vars.joypad1L_last.* = 0;
    vars.filtered_joypad_L.* = 0;
    vars.filtered_joypad_H.* = 0;
    RenderText();
    vars.attract_legend_ctr.* -%= 1;
    if (vars.attract_legend_ctr.* == 0) {
        vars.attract_sequence.* +%= 1;
        vars.attract_state.* -%= 3;
    } else {
        if (vars.attract_legend_ctr.* < 0x18 and vars.attract_legend_ctr.* & 1 != 0)
            vars.INIDISP_copy.* -%= 1;
    }
}

pub export fn AttractDramatize_WorldMap() callconv(.c) void { // 8cf176
    if (vars.timer_for_mode7_zoom.* != 0) {
        if (vars.timer_for_mode7_zoom.* < 15)
            vars.INIDISP_copy.* -%= 1;
        vars.attract_var10.* -%= 1;
        if (vars.attract_var10.* == 0) {
            vars.attract_var10.* = 1;
            vars.timer_for_mode7_zoom.* -%= 1;
            Attract_ControlMapZoom();
        }
    } else {
        EnableForceBlank();
        vars.BGMODE_copy.* = 9;
        EraseTileMaps_normal();
        vars.attract_sequence.* +%= 1;
        vars.attract_state.* -%= 2;
    }
}

const kThroneRoom_Oams = [10]AttractOamInfo{
    .{ .x = 16, .y = 16, .c = 0x2a, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0x2a, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x0a, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x0a, .f = 0x3b, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x0c, .f = 0x31, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x0e, .f = 0x31, .e = 2 },
    .{ .x = 32, .y = 0, .c = 0x0c, .f = 0x71, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0x2c, .f = 0x31, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0x2e, .f = 0x31, .e = 2 },
    .{ .x = 32, .y = 16, .c = 0x2c, .f = 0x71, .e = 2 },
};
const kThroneRoom_OamOffs = [3]u8{ 0, 4, 10 };
const kAttract_ThroneRoom_Xbase = [2]i8{ 80, 104 };
const kAttract_ThroneRoom_Ybase = [2]i8{ 88, 32 };

pub export fn Attract_ThroneRoom() callconv(.c) void { // 8cf1c8
    vars.attract_oam_idx.* = 0;
    if (vars.attract_var15.* == 0) {
        if (vars.INIDISP_copy.* != 15) {
            vars.INIDISP_copy.* +%= 1;
        } else {
            vars.attract_var15.* +%= 1;
        }
    }
    if (vars.BG2VOFS_copy.* == 0) {
        Attract_ShowTimedTextMessage();
        if (vars.oam_priority_value.* == 0) {
            if (vars.attract_var13.* < 31 and (vars.attract_var13.* & 1) == 0)
                vars.INIDISP_copy.* -%= 1;
            vars.attract_var13.* -%= 1;
            if (vars.attract_var13.* == 0) {
                vars.attract_sequence.* +%= 1;
                vars.attract_state.* +%= 1;
                return;
            }
        }
    } else {
        vars.BG2VOFS_copy.* -%= 1;
        vars.BG1VOFS_copy.* -%= 1;
    }
    var i: i32 = 1;
    while (i >= 0) : (i -= 1) {
        const idx: usize = @intCast(i);
        const oamp = kThroneRoom_Oams[kThroneRoom_OamOffs[idx]..].ptr;
        const n: c_int = @as(c_int, kThroneRoom_OamOffs[idx + 1]) - kThroneRoom_OamOffs[idx];
        const y: u16 = @as(u16, @bitCast(@as(i16, kAttract_ThroneRoom_Ybase[idx]))) -% vars.BG2VOFS_copy.*;
        if (!sign16(y +% 32)) {
            vars.attract_x_base.* = @bitCast(kAttract_ThroneRoom_Xbase[idx]);
            vars.attract_y_base.* = @truncate(y);
            Attract_DrawSpriteSet2(oamp, n);
        }
    }

    vars.attract_var7.* = 0xf8a7;
}

const kAttract_ZeldaPrison_Tab0 = [16]u8{ 0, 1, 2, 3, 4, 5, 5, 5, 4, 4, 3, 3, 2, 2, 1, 1 };
const kZeldaPrison_Soldier_X = [2]i8{ 32, -12 };
const kZeldaPrison_Soldier_Y = [2]i8{ 24, 24 };
const kZeldaPrison_Soldier_Dir = [2]u8{ 1, 1 };
const kZeldaPrison_Soldier_Flags = [2]u8{ 9, 7 };

pub export fn AttractDramatize_Prison() callconv(.c) void { // 8cf27a
    vars.attract_oam_idx.* = 0;
    if (vars.attract_var18.* == 0)
        Attract_FadeInStep();
    vars.attract_x_base.* = 56;
    Attract_DrawZelda();
    if (vars.attract_var10.* >= 192) {
        vars.attract_y_base.* = 112;
        vars.attract_var17.* -%= 1;
        if (sign8(vars.attract_var17.*))
            vars.attract_var17.* = 0xf;
        const t = vars.attract_vram_dst.* +% kAttract_ZeldaPrison_Tab0[vars.attract_var17.*];
        vars.attract_x_base_hi.* = @truncate(t >> 8);
        vars.attract_x_base.* = @truncate(t);
        Attract_ZeldaPrison_DrawA();

        var k: i32 = 1;
        while (k >= 0) : (k -= 1) {
            const ki: usize = @intCast(k);
            SpritePrep_ResetProperties(k * 2);
            const x: u16 = @as(u16, @bitCast(@as(i16, kZeldaPrison_Soldier_X[ki]))) +%
                vars.attract_vram_dst.* +% 0x100;
            vars.attract_var4.* = @truncate(x);
            Sprite_SimulateSoldier(
                k * 2,
                x,
                vars.attract_y_base.* +% @as(u8, @bitCast(kZeldaPrison_Soldier_Y[ki])),
                kZeldaPrison_Soldier_Dir[ki],
                kZeldaPrison_Soldier_Flags[ki],
                vars.attract_var3.*,
            );
        }

        vars.attract_var1.* +%= 1;
        if ((vars.attract_var1.* & 7) == 0) {
            if (vars.attract_var3.* == 2) {
                vars.attract_var3.* = 0xff;
                if ((vars.attract_vram_dst.* >> 8) == 0 and vars.attract_var1.* & 8 != 0)
                    vars.sound_effect_2.* = 4;
            }
            vars.attract_var3.* +%= 1;
        }
    }

    switch (vars.attract_var5.*) {
        0 => Attract_ZeldaPrison_Case0(),
        1 => Attract_ZeldaPrison_Case1(),
        else => {},
    }
}

const kMaidenWarp_Soldier_X = [6]u8{ 48, 192, 48, 192, 80, 160 };
const kMaidenWarp_Soldier_Y = [6]u8{ 112, 112, 152, 152, 192, 192 };
const kMaidenWarp_Soldier_Dir = [6]u8{ 0, 1, 0, 1, 3, 3 };
const kMaidenWarp_Soldier_Flags = [6]u8{ 9, 9, 9, 9, 7, 9 };
const kZeldaPrison_MaidenWarp0 = [4]AttractOamInfo{
    .{ .x = 0, .y = 0, .c = 0x03, .f = 0x3d, .e = 2 },
    .{ .x = 8, .y = 0, .c = 0x04, .f = 0x3d, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x00, .f = 0x3d, .e = 2 },
    .{ .x = 8, .y = 0, .c = 0x01, .f = 0x3d, .e = 2 },
};
const kAttract_MaidenWarp_Xbase = [8]u8{ 4, 4, 3, 3, 2, 2, 1, 0 };
const kZeldaPrison_MaidenWarp1 = [16]AttractOamInfo{
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 2, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 2, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 4, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 4, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 6, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 8, .y = 0, .c = 0x6c, .f = 0x38, .e = 2 },
};
const kZeldaPrison_MaidenWarp2 = [48]AttractOamInfo{
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x82, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x82, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa2, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa2, .f = 0x7b, .e = 2 },
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x80, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x82, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa0, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa2, .f = 0x7b, .e = 2 },
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x82, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x82, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa2, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa2, .f = 0x7b, .e = 2 },
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x82, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x80, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa2, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa0, .f = 0x7b, .e = 2 },
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x82, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x82, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa2, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa2, .f = 0x7b, .e = 2 },
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x80, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x82, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa0, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa2, .f = 0x7b, .e = 2 },
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x82, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x82, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa2, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa2, .f = 0x7b, .e = 2 },
    .{ .x = 5, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 11, .y = 25, .c = 0x6c, .f = 0x38, .e = 2 },
    .{ .x = 0, .y = 0, .c = 0x80, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 0, .c = 0x80, .f = 0x7b, .e = 2 },
    .{ .x = 0, .y = 16, .c = 0xa0, .f = 0x3b, .e = 2 },
    .{ .x = 16, .y = 16, .c = 0xa0, .f = 0x7b, .e = 2 },
};

pub export fn AttractDramatize_AgahnimAltar() callconv(.c) void { // 8cf423
    if (vars.attract_var22.* != 0) {
        vars.attract_sequence.* +%= 1;
        vars.attract_state.* -%= 2;
        return;
    }
    vars.attract_oam_idx.* = 0;
    HandleScreenFlash();
    if (vars.attract_var18.* == 0)
        Attract_FadeInStep();
    if (vars.attract_var17.* != 255)
        vars.attract_var17.* +%= 1;
    if (vars.intro_times_pal_flash.* & 4 != 0)
        vars.sound_effect_2.* = 0x2b;
    switch (vars.attract_var5.*) {
        0 => Attract_MaidenWarp_Case0(),
        1 => Attract_MaidenWarp_Case1(),
        2 => Attract_MaidenWarp_Case2(),
        3 => Attract_MaidenWarp_Case3(),
        4 => Attract_MaidenWarp_Case4(),
        else => {},
    }

    var k: i32 = 5;
    while (k >= 0) : (k -= 1) {
        const ki: usize = @intCast(k);
        SpritePrep_ResetProperties(k);
        Sprite_SimulateSoldier(
            k,
            kMaidenWarp_Soldier_X[ki],
            kMaidenWarp_Soldier_Y[ki],
            kMaidenWarp_Soldier_Dir[ki],
            kMaidenWarp_Soldier_Flags[ki],
            0,
        );
    }

    if (vars.attract_var17.* >= 0xa0) {
        if (loPtr(vars.attract_vram_dst).* != 0x60) {
            vars.attract_var1.* -%= 1;
            if (vars.attract_var1.* == 0) {
                loPtr(vars.attract_vram_dst).* -%= 1;
                vars.attract_var1.* = 8;
            }
        } else {
            vars.attract_var11.* +%= 1;
        }
    }

    if (vars.attract_var15.* == 0) {
        vars.attract_x_base.* = 116;
        vars.attract_y_base.* = @truncate(vars.attract_vram_dst.*);
        const off: usize = if (loPtr(vars.attract_vram_dst).* == 0x70) 0 else 2;
        Attract_DrawSpriteSet2(kZeldaPrison_MaidenWarp0[off..].ptr, 2);

        var kk: usize = 7;
        if (loPtr(vars.attract_vram_dst).* < 0x68)
            kk = (loPtr(vars.attract_vram_dst).* -% 0x68) & 7;
        vars.attract_x_base.* = 0x74 +% kAttract_MaidenWarp_Xbase[kk];
        vars.attract_y_base.* = 0x76;
        Attract_DrawSpriteSet2(kZeldaPrison_MaidenWarp1[kk * 2 ..].ptr, 2);
    }
    const k2: usize = (vars.attract_var17.* >> 5) & 7;
    vars.attract_x_base.* = 112;
    vars.attract_y_base.* = 70;
    Attract_DrawSpriteSet2(kZeldaPrison_MaidenWarp2[k2 * 6 ..].ptr, 6);
}

pub export fn Attract_SkipToFileSelect() callconv(.c) void { // 8cf700
    vars.INIDISP_copy.* -%= 1;
    if (vars.INIDISP_copy.* != 0)
        return;
    EnableForceBlank();
    rtl.zelda_ppu_write(BG1SC, 0x13);
    rtl.zelda_ppu_write(BG2SC, 0x3);
    Attract_SetUpConclusionHDMA();
    vars.M7Y_copy.* = 0;
    vars.M7X_copy.* = 0;
    vars.BG1HOFS_copy.* = 0;
    vars.BG1VOFS_copy.* = 0;
    vars.BG3VOFS_copy2.* = 0;
    FadeMusicAndResetSRAMMirror();
}

const kAttract_LegendGraphics_sizes = [4]u16{ 157 + 1, 237 + 1, 199 + 1, 265 + 1 };

pub export fn Attract_BuildNextImageTileMap() callconv(.c) void { // 8cf73e
    const ptrs = [4][*]const u8{
        &kAttract_Legendgraphics_0,
        &kAttract_Legendgraphics_1,
        &kAttract_Legendgraphics_2,
        &kAttract_Legendgraphics_3,
    };
    const i: usize = vars.attract_next_legend_gfx.* >> 1;
    const n = kAttract_LegendGraphics_sizes[i];
    @memcpy(g_ram[0x1002..][0..n], ptrs[i][0..n]);
    vars.nmi_load_bg_from_vram.* = 1;
}

pub export fn Attract_ShowTimedTextMessage() callconv(.c) void { // 8cf766
    vars.attract_var12.* = vars.BG2VOFS_copy2.*;
    vars.joypad1L_last.* = 0;
    vars.filtered_joypad_L.* = 0;
    vars.filtered_joypad_H.* = 0;
    RenderText();
    if (vars.oam_priority_value.* != 0)
        vars.oam_priority_value.* -%= 1;
}

pub export fn Attract_ControlMapZoom() callconv(.c) void { // 8cf783
    var i: i32 = 240 - 1;
    while (i >= 0) : (i -= 1) {
        const idx: usize = @intCast(i);
        vars.hdma_table_dynamic[idx] = @truncate(
            (@as(u32, kMapMode_Zooms1[idx]) * vars.timer_for_mode7_zoom.*) >> 8,
        );
    }
}

const kAttract_CopyToVram_Tab0 = [16]u16{
    0x1a0, 0x9a6, 0x89a5, 0x1a0, 0x9a5, 0x1a0, 0x1a0, 0x89a6,
    0x49a5, 0x1a0, 0x1a0, 0x49a5, 0x1a0, 0x89a5, 0xc9a5, 0x1a0,
};
const kAttract_CopyToVram_Tab1 = [4]u16{ 0x9a1, 0x9a2, 0x9a3, 0x9a4 };

pub export fn Attract_BuildBackgrounds() callconv(.c) void { // 8cf7e6
    vars.BGMODE_copy.* = 9;
    vars.TM_copy.* = 0x17;
    vars.TS_copy.* = 0;

    rtl.zelda_ppu_write(BG1SC, 0x10);
    rtl.zelda_ppu_write(BG2SC, 0x0);

    const dst: [*]align(1) u16 = @ptrCast(&g_ram[0x1006]);
    {
        var k: usize = 0;
        var p: usize = 0; // index into kAttract_CopyToVram_Tab0
        while (true) {
            var j = k & 3;
            while (true) {
                dst[k] = kAttract_CopyToVram_Tab0[p + j];
                k += 1;
                j += 1;
                if (j & 3 == 0) break;
            }
            if (k & 0x1f != 0) continue;
            p += 4;
            if (k == 0x80) break;
        }
        Attract_TriggerBGDMA(0x1000);
    }

    {
        var k: usize = 0;
        while (true) {
            var j = k & 1;
            const p = (k & 0x20) >> 4;
            while (true) {
                dst[k] = kAttract_CopyToVram_Tab1[p + j];
                k += 1;
                j += 1;
                if (j & 1 == 0) break;
            }
            if (k == 0x80) break;
        }
        Attract_TriggerBGDMA(0);
    }
    vars.attract_vram_dst.* = 0;
}

pub export fn Attract_TriggerBGDMA(dstv: u16) callconv(.c) void { // 8cf879
    var dst = g_zenv.vram.? + dstv;
    for (0..8) |_| {
        @memcpy(@as([*]u8, @ptrCast(dst))[0..0x100], g_ram[0x1006..][0..0x100]);
        dst += 0x80;
    }
}

pub export fn Attract_DrawPreloadedSprite(
    xp: [*]const u8,
    yp: [*]const u8,
    cp: [*]const u8,
    fp: [*]const u8,
    ep: [*]const u8,
    n: c_int,
) callconv(.c) void { // 8cf9b5
    var oam = oam_buf + (@as(usize, vars.attract_oam_idx.*) + 64);
    vars.attract_oam_idx.* +%= @truncate(@as(c_uint, @bitCast(n + 1)));
    var i = n;
    while (true) {
        const idx: usize = @intCast(i);
        SetOamPlain(
            oam,
            vars.attract_x_base.* +% xp[idx],
            vars.attract_y_base.* +% yp[idx],
            cp[idx],
            fp[idx],
            ep[idx],
        );
        oam += 1;
        i -= 1;
        if (i < 0) break;
    }
}

pub export fn Attract_DrawZelda() callconv(.c) void { // 8cf9e8
    const oam = oam_buf + (64 + @as(usize, vars.attract_oam_idx.*));
    SetOamPlain(oam + 0, 0x60, vars.attract_x_base.*, 0x28, 0x29, 2);
    SetOamPlain(oam + 1, 0x60, vars.attract_x_base.* +% 10, 0x2a, 0x29, 2);
    vars.attract_oam_idx.* +%= 2;
}

const kSimulateSoldier_Gfx = [4]u8{ 11, 4, 0, 7 };

pub export fn Sprite_SimulateSoldier(k: c_int, x: u16, y: u16, dir: u8, flags: u8, gfx: u8) callconv(.c) void { // 9deb84
    const ki: usize = @intCast(k);
    Sprite_SetX(k, x);
    Sprite_SetY(k, y);
    vars.sprite_z[ki] = 0;
    Sprite_Get16BitCoords(k);
    vars.sprite_head_dir[ki] = dir;
    vars.sprite_D[ki] = dir;
    vars.sprite_graphics[ki] = kSimulateSoldier_Gfx[dir] +% gfx;
    vars.sprite_flags3[ki] = 16;
    vars.sprite_obj_prio[ki] = 0;
    vars.sprite_oam_flags[ki] = flags | 0x30;
    vars.sprite_type[ki] = if (flags == 9) 0x41 else 0x43;
    vars.sprite_flags2[ki] = 7;
    const oam_idx: u16 = @intCast(k * 8);
    vars.oam_cur_ptr.* = 0x800 + oam_idx * 4;
    vars.oam_ext_cur_ptr.* = 0xa20 + oam_idx;
    Guard_HandleAllAnimation(k);
}

const testing = std.testing;

test "the map zoom tables are 240 descending entries" {
    try testing.expectEqual(240, kMapMode_Zooms1.len);
    try testing.expectEqual(240, kMapMode_Zooms2.len);
    try testing.expectEqual(@as(u16, 375), kMapMode_Zooms1[0]);
    try testing.expectEqual(@as(u16, 258), kMapMode_Zooms1[239]);
    try testing.expectEqual(@as(u16, 136), kMapMode_Zooms2[0]);
    try testing.expectEqual(@as(u16, 94), kMapMode_Zooms2[239]);
    // Both ramp monotonically downwards.
    for (1..240) |i| {
        try testing.expect(kMapMode_Zooms1[i] <= kMapMode_Zooms1[i - 1]);
        try testing.expect(kMapMode_Zooms2[i] <= kMapMode_Zooms2[i - 1]);
    }
}

test "the legend tilemap blobs kept their declared sizes" {
    try testing.expectEqual(158, kAttract_Legendgraphics_0.len);
    try testing.expectEqual(238, kAttract_Legendgraphics_1.len);
    try testing.expectEqual(200, kAttract_Legendgraphics_2.len);
    try testing.expectEqual(266, kAttract_Legendgraphics_3.len);
    try testing.expectEqualSlices(u16, &.{ 158, 238, 200, 266 }, &kAttract_LegendGraphics_sizes);
    // The first three end with the 0xff terminator then a bank byte.
    try testing.expectEqual(@as(u8, 0xff), kAttract_Legendgraphics_0[156]);
    try testing.expectEqual(@as(u8, 0xff), kAttract_Legendgraphics_1[236]);
    try testing.expectEqual(@as(u8, 0xff), kAttract_Legendgraphics_2[198]);
    try testing.expectEqual(@as(u8, 0xff), kAttract_Legendgraphics_3[264]);
}

test "the oam info struct matches the C layout" {
    try testing.expectEqual(5, @sizeOf(AttractOamInfo));
    try testing.expectEqual(0, @offsetOf(AttractOamInfo, "x"));
    try testing.expectEqual(1, @offsetOf(AttractOamInfo, "y"));
    try testing.expectEqual(2, @offsetOf(AttractOamInfo, "c"));
    try testing.expectEqual(3, @offsetOf(AttractOamInfo, "f"));
    try testing.expectEqual(4, @offsetOf(AttractOamInfo, "e"));
}

test "drawing a sprite set walks the table backwards into forward oam slots" {
    @memset(g_ram[0..0x2000], 0);
    vars.attract_oam_idx.* = 0;
    vars.attract_x_base.* = 100;
    vars.attract_y_base.* = 50;

    Attract_DrawSpriteSet2(&kZeldaPrison_Oams0, 6);
    try testing.expectEqual(@as(u8, 6), vars.attract_oam_idx.*);
    // The C counts the table index down while stepping oam up, so oam slot 64
    // gets the LAST table entry.
    const last = kZeldaPrison_Oams0[5];
    try testing.expectEqual(100 +% @as(u8, @bitCast(last.x)), oam_buf[64].x);
    try testing.expectEqual(last.c, oam_buf[64].charnum);
    const first = kZeldaPrison_Oams0[0];
    try testing.expectEqual(first.c, oam_buf[69].charnum);
}

test "the prison and maiden warp oam tables have whole numbers of frames" {
    try testing.expectEqual(6, kZeldaPrison_Oams0.len);
    try testing.expectEqual(30, kZeldaPrison_Oams1.len); // 5 frames of 6
    try testing.expectEqual(28, kZeldaPrison_MaidenWarpCase1_Oam.len); // 2 frames of 14
    try testing.expectEqual(48, kZeldaPrison_MaidenWarp2.len); // 8 frames of 6
    try testing.expectEqual(16, kZeldaPrison_MaidenWarp1.len); // 8 frames of 2
    try testing.expectEqual(4, kZeldaPrison_MaidenWarp0.len);
    try testing.expectEqual(10, kThroneRoom_Oams.len);
    try testing.expectEqual(3, kThroneRoom_OamOffs.len);
    // The offsets carve the throne room table into two runs.
    try testing.expectEqual(10, kThroneRoom_OamOffs[2]);
    try testing.expectEqual(4, kThroneRoom_OamOffs[1] - kThroneRoom_OamOffs[0]);
    try testing.expectEqual(6, kThroneRoom_OamOffs[2] - kThroneRoom_OamOffs[1]);
}

test "the map zoom hdma table scales by the zoom timer" {
    @memset(g_ram[0..0x20000], 0);
    // At full zoom every entry is the source value scaled by 255/256.
    vars.timer_for_mode7_zoom.* = 255;
    Attract_ControlMapZoom();
    try testing.expectEqual(@as(u16, @truncate((@as(u32, 375) * 255) >> 8)), vars.hdma_table_dynamic[0]);
    try testing.expectEqual(@as(u16, @truncate((@as(u32, 258) * 255) >> 8)), vars.hdma_table_dynamic[239]);
    // At zero the whole table collapses.
    vars.timer_for_mode7_zoom.* = 0;
    Attract_ControlMapZoom();
    for (0..240) |i|
        try testing.expectEqual(@as(u16, 0), vars.hdma_table_dynamic[i]);
}

test "the background builder fills 0x80 words from the four-entry groups" {
    @memset(g_ram[0..0x20000], 0);
    const dst: [*]align(1) u16 = @ptrCast(&g_ram[0x1006]);
    // Replicate just the first loop's addressing to pin the pattern.
    var k: usize = 0;
    var p: usize = 0;
    while (true) {
        var j = k & 3;
        while (true) {
            dst[k] = kAttract_CopyToVram_Tab0[p + j];
            k += 1;
            j += 1;
            if (j & 3 == 0) break;
        }
        if (k & 0x1f != 0) continue;
        p += 4;
        if (k == 0x80) break;
    }
    try testing.expectEqual(0x80, k);
    try testing.expectEqual(kAttract_CopyToVram_Tab0[0], dst[0]);
    try testing.expectEqual(kAttract_CopyToVram_Tab0[1], dst[1]);
    try testing.expectEqual(16, kAttract_CopyToVram_Tab0.len);
    try testing.expectEqual(4, kAttract_CopyToVram_Tab1.len);
}

test "soldier graphics are picked by facing direction" {
    try testing.expectEqualSlices(u8, &.{ 11, 4, 0, 7 }, &kSimulateSoldier_Gfx);
    try testing.expectEqual(6, kMaidenWarp_Soldier_X.len);
    try testing.expectEqual(6, kMaidenWarp_Soldier_Y.len);
    try testing.expectEqual(6, kMaidenWarp_Soldier_Dir.len);
    try testing.expectEqual(6, kMaidenWarp_Soldier_Flags.len);
    // Every direction indexes inside the gfx table.
    for (kMaidenWarp_Soldier_Dir) |d|
        try testing.expect(d < kSimulateSoldier_Gfx.len);
}
