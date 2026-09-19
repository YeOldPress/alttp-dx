//! Literal sprite data tables. Function bodies are handwritten in the sprite main modules.
const sprite = @import("sprite.zig");
const vars = @import("variables.zig");
const a = @import("sprite_main_abi.zig");
pub const DrawMultipleData = sprite.DrawMultipleData;
pub const OamEntSigned = vars.OamEntSigned;
pub const kSpriteKeese_Tab2: [16]i8 = .{ 0, 8, 11, 14, 16, 14, 11, 8, 0, -8, -11, -14, -16, -14, -11, -8 };
pub const kSpriteKeese_Tab3: [16]i8 = .{ -16, -14, -11, -8, 0, 8, 11, 14, 16, 14, 11, 8, 0, -9, -11, -14 };
pub const kZazak_Yvel: [4]i8 = .{ 0, 0, 16, -16 };
pub const kFluteBoyAnimal_Xvel: [4]i8 = .{ 16, -16, 0, 0 };
pub const kDesertBarrier_Xv: [4]i8 = .{ 16, -16, 0, 0 };
pub const kDesertBarrier_Yv: [4]i8 = .{ 0, 0, 16, -16 };
pub const kCrystalSwitchPal: [2]u8 = .{ 2, 4 };
pub const kZazak_Dir2: [8]u8 = .{ 2, 3, 2, 3, 0, 1, 0, 1 };
pub const kBadPullDownSwitch_X: [5]i8 = .{ -4, 12, 0, -4, 4 };
pub const kBadPullDownSwitch_Y: [5]i8 = .{ -3, -3, 0, 5, 5 };
pub const kBadPullDownSwitch_Char: [5]u8 = .{ 0xd2, 0xd2, 0xc4, 0xe4, 0xe4 };
pub const kBadPullDownSwitch_Flags: [5]u8 = .{ 0x40, 0, 0, 0x40, 0 };
pub const kBadPullDownSwitch_Big: [5]u8 = .{ 0, 0, 2, 2, 2 };
pub const kBadPullSwitch_Tab5: [6]u8 = .{ 0, 1, 2, 3, 4, 5 };
pub const kBadPullSwitch_Tab4: [12]u8 = .{ 0, 0, 1, 1, 2, 2, 3, 3, 4, 5, 5, 5 };
pub const kThief_Gfx: [12]u8 = .{ 11, 8, 2, 5, 9, 6, 0, 3, 10, 7, 1, 4 };
pub const kTutorialSoldier_X: [20]i16 = .{
    4,   0,  -6, -6, 2, 0, 0, -7, -7, -7, 0, 0, 0xf, 0xf, 0xf, 6,
    0xe, -4, 4,  0,
};
pub const kTutorialSoldier_Y: [20]i16 = .{
    0, -10, -4, 12, 12, 0, -9, -11, -3, 5, 0, -9, -11, -3, 5, -11,
    5, 0,   0,  -9,
};
pub const kTutorialSoldier_Char: [20]u8 = .{
    0x46, 0x40, 0,    0x28, 0x29, 0x4e, 0x42, 0x39, 0x2a, 0x3a, 0x4e, 0x42, 0x39, 0x2a, 0x3a, 0x26,
    0x38, 0x64, 0x64, 0x44,
};
pub const kTutorialSoldier_Flags: [20]u8 = .{
    0x40, 0, 0,    0, 0, 0, 0, 0, 0, 0, 0x40, 0x40, 0x40, 0x40, 0x40, 0,
    0x40, 0, 0x40, 0,
};
pub const kTutorialSoldier_Big: [20]u8 = .{
    2, 2, 2, 0, 0, 2, 2, 0, 0, 0, 2, 2, 0, 0, 0, 2,
    0, 2, 2, 2,
};
pub const kSprite_TutorialEntities_Tab: [4]u8 = .{ 2, 1, 0, 3 };
pub const kSoldier_DirectionLockSettings: [4]u8 = .{ 3, 2, 0, 1 };
pub const kWishPond_X: [8]u8 = .{ 0, 4, 8, 12, 16, 20, 24, 0 };
pub const kWishPond_Y: [8]u8 = .{ 0, 8, 16, 24, 32, 40, 4, 36 };
pub export const kWishPond2_OamFlags: [76]u8 = .{
    5, 0xff, 5, 5, 5, 5, 5, 1, 2, 1, 1, 1, 2, 2, 2, 4,
    4, 4,    1, 1, 2, 1, 1, 1, 2, 1, 2, 1, 4, 4, 2, 1,
    6, 1,    2, 1, 2, 2, 1, 2, 2, 4, 1, 1, 4, 2, 1, 4,
    2, 2,    4, 4, 4, 2, 1, 4, 1, 2, 2, 1, 2, 2, 1, 1,
    4, 4,    1, 2, 2, 4, 4, 4, 2, 5, 2, 1,
};
pub const kWishPondItemOffs: [32]u8 = .{ 0, 4, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 20, 21, 22, 22, 23, 24, 25, 28, 30, 31, 32, 33, 33, 37, 40, 42, 42, 42, 42 };
pub const kWishPondItemData: [50]u8 = .{ 0x3a, 0x3a, 0x3b, 0x3b, 0x0c, 0x2a, 0x0a, 0x27, 0x29, 0x0d, 0x07, 0x08, 0x0f, 0x10, 0x11, 0x12, 0x09, 0x13, 0x14, 0x4a, 0x21, 0x1d, 0x15, 0x18, 0x19, 0x31, 0x1a, 0x1a, 0x1b, 0x1c, 0x4b, 0x1e, 0x1f, 0x49, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x22, 0x23, 0x29, 0x16, 0x2b, 0x2c, 0x2d, 0x3d, 0x3c, 0x48 };
pub const kUncle_LeaveHouse_Delay: [2]u8 = .{ 64, 224 };
pub const kUncle_LeaveHouse_Dir: [2]u8 = .{ 2, 1 };
pub const kUncle_LeaveHouse_Xvel: [4]i8 = .{ 0, 0, -12, 12 };
pub const kUncle_LeaveHouse_Yvel: [4]i8 = .{ -12, 12, 0, 0 };
pub const kPriest_Dmd: [20]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x0e20, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0e26, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0e20, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4e26, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0e0e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0e24, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0e0e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0e24, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0e22, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0e28, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0e22, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0e2a, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4e22, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4e28, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4e22, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4e2a, .ext = 2 },
    .{ .x = -7, .y = 1, .char_flags = 0x0e0a, .ext = 2 },
    .{ .x = 3, .y = 3, .char_flags = 0x0e0c, .ext = 2 },
    .{ .x = -7, .y = 1, .char_flags = 0x0e0a, .ext = 2 },
    .{ .x = 3, .y = 3, .char_flags = 0x0e0c, .ext = 2 },
};
pub const kSageMantle_Dmd: [4]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x162c, .ext = 2 },
    .{ .x = 16, .y = 0, .char_flags = 0x562c, .ext = 2 },
    .{ .x = 0, .y = 16, .char_flags = 0x062e, .ext = 2 },
    .{ .x = 16, .y = 16, .char_flags = 0x462e, .ext = 2 },
};
pub const kCrystalMaiden_Dma: [16]u8 = .{ 0x20, 0xc0, 0x20, 0xc0, 0, 0xa0, 0, 0xa0, 0x40, 0x80, 0x40, 0x60, 0x40, 0x80, 0x40, 0x60 };
pub const kCrystalMaiden_SpriteData: [16]DrawMultipleData = .{
    .{ .x = 1, .y = -7, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 1, .y = 3, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 1, .y = -7, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 1, .y = 3, .char_flags = 0x4122, .ext = 2 },
    .{ .x = 1, .y = -7, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 1, .y = 3, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 1, .y = -7, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 1, .y = 3, .char_flags = 0x4122, .ext = 2 },
    .{ .x = 1, .y = -7, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 1, .y = 3, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 1, .y = -7, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 1, .y = 3, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 1, .y = -7, .char_flags = 0x4120, .ext = 2 },
    .{ .x = 1, .y = 3, .char_flags = 0x4122, .ext = 2 },
    .{ .x = 1, .y = -7, .char_flags = 0x4120, .ext = 2 },
    .{ .x = 1, .y = 3, .char_flags = 0x4122, .ext = 2 },
};
pub const kZelda_Xvel: [4]i8 = .{ 0, 0, -9, 9 };
pub const kZelda_Yvel: [4]i8 = .{ -9, 9, 0, 0 };
pub const kHeartRefill_AccelX: [2]i8 = .{ 1, -1 };
pub const kHeartRefill_VelTarget: [2]i8 = .{ 10, -10 };
pub const kFakeSword_Dmd: [2]DrawMultipleData = .{
    .{ .x = 4, .y = 0, .char_flags = 0x00f4, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x00f5, .ext = 0 },
};
pub const kThrowableScenery_Char: [12]u8 = .{ 0x42, 0x44, 0x46, 0, 0x46, 0x44, 0x42, 0x44, 0x44, 0, 0x46, 0x44 };
pub export const kThrowableScenery_Flags: [9]u8 = .{ 0xc, 0xc, 0xc, 0, 0, 0, 0xb0, 0x08, 0xb4 };
pub const kThrowableScenery_DrawLarge_X: [4]i16 = .{ -8, 8, -8, 8 };
pub const kThrowableScenery_DrawLarge_Y: [4]i16 = .{ -14, -14, 2, 2 };
pub const kThrowableScenery_DrawLarge_Flags: [4]u8 = .{ 0, 0x40, 0x80, 0xc0 };
pub const kThrowableScenery_DrawLarge_X2: [3]i16 = .{ -6, 0, 6 };
pub const kThrowableScenery_DrawLarge_OamFlags: [2]u8 = .{ 0xc, 0 };
pub const kScatterDebris_X: [4]i8 = .{ -8, 8, -8, 8 };
pub const kScatterDebris_Y: [4]i8 = .{ -8, -8, 8, 8 };
pub const kMovableMantle_X: [6]u8 = .{ 0, 0x10, 0x20, 0, 0x10, 0x20 };
pub const kMovableMantle_Y: [6]u8 = .{ 0, 0, 0, 0x10, 0x10, 0x10 };
pub const kMovableMantle_Char: [6]u8 = .{ 0xc, 0xe, 0xc, 0x2c, 0x2e, 0x2c };
pub const kMovableMantle_Flags: [6]u8 = .{ 0x31, 0x31, 0x71, 0x31, 0x31, 0x71 };
pub const kSprite_SimplifiedTileAttr: [256]u8 = .{
    0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 3, 3, 3,
    0, 0, 0, 0, 0, 0, 1, 1, 4, 4, 4, 4, 4, 4, 4, 4,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};
pub const kSoldier_Gfx: [4]u8 = .{ 8, 0, 12, 5 };
pub const kSoldier_Delay: [4]u8 = .{ 0x60, 0xc0, 0xff, 0x40 };
pub const kSoldier_Draw1_Char: [4]u8 = .{ 0x42, 0x42, 0x40, 0x44 };
pub const kSoldier_Draw1_Flags: [4]u8 = .{ 0x40, 0, 0, 0 };
pub const kSoldier_Draw1_Yd: [26]i8 = .{
    7, 8, 7, 8, 8, 7, 8, 7, 8, 7, 8, 8, 7, 8, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
};
pub const kSoldier_Draw2_Xd: [104]i8 = .{
    -4, 4,  10, 10, -4, 4,  10, 10, -4, 4,  10, 10, -4, 4,  10, 10,
    -4, -4, 0,  0,  -4, -4, 0,  0,  -3, -3, 0,  0,  -3, -3, -4, 4,
    -3, -3, -4, 4,  -3, -3, -4, 4,  -3, -3, -4, 4,  12, 12, 0,  0,
    12, 12, 0,  0,  11, 11, 0,  0,  -4, 4,  0,  0,  -4, 4,  0,  0,
    -4, 4,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    -4, 4,  0,  0,  -4, 4,  0,  0,  -4, 4,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,
};
pub const kSoldier_Draw2_Yd: [104]i8 = .{
    0,  0, 2, 10, 0,  0, 2, 10, 0,  0, 1, 9, 0,  0, 2, 10,
    -2, 6, 1, 1,  -2, 6, 2, 2,  -2, 6, 1, 1, -5, 3, 0, 0,
    -4, 4, 0, 0,  -4, 4, 0, 0,  -5, 3, 0, 0, -2, 6, 1, 1,
    -2, 6, 2, 2,  -2, 6, 1, 1,  0,  0, 8, 8, 0,  0, 8, 8,
    0,  0, 8, 8,  0,  0, 8, 8,  0,  0, 8, 8, 0,  0, 8, 8,
    0,  0, 8, 8,  0,  0, 8, 8,  0,  0, 8, 8, 0,  0, 8, 8,
    0,  0, 8, 8,  0,  0, 8, 8,
};
pub const kSoldier_Draw2_Char: [104]u8 = .{
    0x48, 0x49, 0x6d, 0x7d, 0x49, 0x48, 0x6d, 0x7d, 0x46, 0x46, 0x6d, 0x7d, 0x4b, 0x46, 0x6d, 0x7d,
    0x4d, 0x5d, 0x4e, 0x4e, 0x4d, 0x5d, 0x60, 0x60, 0x4d, 0x5d, 0x62, 0x62, 0x6d, 0x7d, 0x64, 0x64,
    0x6d, 0x7d, 0x66, 0x67, 0x6d, 0x7d, 0x67, 0x66, 0x6d, 0x7d, 0x64, 0x69, 0x4d, 0x5d, 0x4e, 0x4e,
    0x4d, 0x5d, 0x60, 0x60, 0x4d, 0x5d, 0x62, 0x62, 2,    3,    0x20, 0x20, 2,    0xc,  0x20, 0x20,
    2,    0xc,  0x20, 0x20, 8,    8,    0x20, 0x20, 0xe,  0xe,  0x20, 0x20, 0xe,  0xe,  0x20, 0x20,
    5,    6,    0x20, 0x20, 0x22, 6,    0x20, 0x20, 0x22, 6,    0x20, 0x20, 8,    8,    0x20, 0x20,
    0xe,  0xe,  0x20, 0x20, 0xe,  0xe,  0x20, 0x20,
};
pub const kSoldier_Draw2_Flags: [104]u8 = .{
    0,    0,    0,    0,    0x40, 0x40, 0,    0,    0, 0x40, 0, 0,    0,    0x40, 0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0, 0,    0, 0,    0,    0,    0,    0x40,
    0,    0,    0,    0,    0,    0,    0x40, 0x40, 0, 0,    0, 0x40, 0x40, 0x40, 0x40, 0x40,
    0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0, 0,    0, 0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0, 0,    0, 0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0, 0,    0, 0,    0x40, 0x40, 0x40, 0x40,
    0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,
};
pub const kSoldier_Draw2_Big: [104]u8 = .{
    2, 2, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0,
    0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 2, 2,
    0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 2, 2,
    0, 0, 2, 2, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2,
};
pub const kSoldier_Draw2_OamIdx: [4]u8 = .{ 12, 12, 12, 4 };
pub const kSoldier_Draw3_Xd: [28]i8 = .{
    -3, -3, -4, -4, -4, -4, -4, -4, -11, -3, -11, -3, -16, -8, 12, 12,
    12, 12, 12, 12, 12, 12, 21, 13, 21,  13, 24,  16,
};
pub const kSoldier_Draw3_Yd: [28]i8 = .{
    11, 19, 11, 19, 10,  18, 14, 22, 8, 8, 8, 8, 6, 6, -10, -2,
    -9, -1, -9, -1, -16, -8, 8,  8,  8, 8, 6, 6,
};
pub const kSoldier_Draw3_Char: [28]u8 = .{
    0x7b, 0x6b, 0x7b, 0x6b, 0x7b, 0x6b, 0x7b, 0x6b, 0x6c, 0x7c, 0x6c, 0x7c, 0x6c, 0x7c, 0x6b, 0x7b,
    0x6b, 0x7b, 0x6b, 0x7b, 0x6b, 0x7b, 0x6c, 0x7c, 0x6c, 0x7c, 0x6c, 0x7c,
};
pub const kSoldier_Draw3_Flags: [28]u8 = .{
    0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0,    0,    0,    0,    0, 0, 0, 0,
    0,    0,    0,    0,    0,    0,    0x40, 0x40, 0x40, 0x40, 0x40, 0x40,
};
pub const kSoldier_Draw3_OamIdx: [4]u8 = .{ 4, 4, 4, 20 };
pub const kSoldier_Xvel: [4]i8 = .{ 8, -8, 0, 0 };
pub const kSoldier_Yvel: [4]i8 = .{ 0, 0, 8, -8 };
pub const kSoldier_Gfx2: [32]u8 = .{
    11, 12, 13, 12, 4, 5, 6, 5, 0, 1, 2, 3, 7,  8,  9,  10,
    17, 18, 17, 18, 7, 8, 7, 8, 3, 4, 3, 4, 13, 14, 13, 14,
};
pub const kSoldierB_Xvel: [8]i8 = .{ 1, 1, -1, -1, -1, -1, 1, 1 };
pub const kSoldierB_Yvel: [8]i8 = .{ -1, 1, 1, -1, -1, 1, 1, -1 };
pub const kSoldierB_Xvel2: [8]i8 = .{ 8, 0, -8, 0, -8, 0, 8, 0 };
pub const kSoldierB_Yvel2: [8]i8 = .{ 0, 8, 0, -8, 0, 8, 0, -8 };
pub const kSoldierB_Dir: [8]u8 = .{ 0, 2, 1, 3, 1, 2, 0, 3 };
pub const kSoldierB_Mask2: [8]u8 = .{ 1, 4, 2, 8, 2, 4, 1, 8 };
pub const kSoldierB_Mask: [8]u8 = .{ 8, 1, 4, 2, 8, 2, 4, 1 };
pub const kSoldierB_NextB2: [8]u8 = .{ 1, 2, 3, 0, 5, 6, 7, 4 };
pub const kSoldierB_NextB: [8]u8 = .{ 3, 0, 1, 2, 7, 4, 5, 6 };
pub const kSoldier_HeadDirs: [32]u8 = .{
    0, 2, 2, 2, 0, 3, 3, 3, 1, 3, 3, 3, 1, 2, 2, 2,
    2, 0, 0, 0, 2, 1, 1, 1, 3, 1, 1, 1, 3, 0, 0, 0,
};
pub const kSoldier_Tab1: [4]u8 = .{ 13, 13, 12, 12 };
pub const kSoldier_DrawShadow: [4]u8 = .{ 0xc, 0xc, 0xa, 0xa };
pub const kSoldier_SetTowardsVel: [6]i8 = .{ 14, -14, 0, 0, 14, -14 };
pub const kSprite_SpawnProbeStaggered_Tab: [4]u8 = .{ 0x10, 0x30, 0, 0x20 };
pub const kSpawnProbe_Xvel: [64]i8 = .{
    -16, -16, -16, -16, -16, -16, -16, -16, -16, -14, -12, -10, -8,  -6,  -4,  -2,
    0,   2,   4,   6,   8,   10,  12,  14,  16,  16,  16,  16,  16,  16,  16,  16,
    16,  16,  16,  16,  16,  16,  16,  16,  14,  12,  10,  8,   6,   4,   2,   0,
    -2,  -4,  -6,  -8,  -10, -12, -14, -16, -16, -16, -16, -16, -16, -16, -16, -16,
};
pub const kSpawnProbe_Yvel: [64]i8 = .{
    0,   2,   4,   6,   8,   10,  12,  14,  16,  16,  16,  16,  16,  16,  16,  16,
    16,  16,  16,  16,  16,  16,  16,  16,  14,  12,  10,  8,   6,   4,   2,   0,
    -2,  -4,  -6,  -8,  -10, -12, -14, -16, -16, -16, -16, -16, -16, -16, -16, -16,
    -16, -16, -16, -16, -16, -16, -16, -16, -14, -12, -10, -8,  -6,  -4,  -2,  0,
};
pub const kChainBallTrooper_Tab1: [4]u8 = .{ 0x0d, 0x60, 0x22, 0x10 };
pub const kFlailTrooperGfx: [32]u8 = .{
    0x10, 0x11, 0x12, 0x13, 0x10, 0x11, 0x12, 0x13, 6,   7,   8,   9,   6,   7,   8,   9,
    0,    1,    2,    3,    0,    1,    4,    5,    0xa, 0xb, 0xc, 0xd, 0xa, 0xb, 0xe, 0xf,
};
pub const kJavelinTrooper_Tab2: [64]u8 = .{
    25, 25, 24, 24, 23, 23, 23, 23, 19, 19, 18, 18, 17, 17, 17, 17,
    16, 16, 15, 15, 14, 14, 14, 14, 22, 22, 21, 21, 20, 20, 20, 20,
    20, 20, 18, 18, 18, 16, 16, 16, 21, 21, 8,  8,  8,  6,  6,  6,
    22, 22, 4,  4,  4,  3,  3,  3,  23, 23, 15, 15, 15, 11, 11, 11,
};
pub const kSprite_Recruit_Xvel: [8]i8 = .{ 12, -12, 0, 0, 18, -18, 0, 0 };
pub const kSprite_Recruit_Yvel: [8]i8 = .{ 0, 0, 0xc, -0xc, 0, 0, 0x12, -0x12 };
pub const kSprite_Recruit_Gfx: [8]i8 = .{ 0, 2, 4, 6, 1, 3, 5, 7 };
pub const kRecruit_Moving_HeadDir: [8]u8 = .{ 2, 3, 2, 3, 0, 1, 0, 1 };
pub const kRecruit_Draw_X: [8]i16 = .{ 2, 2, -2, -2, 0, 0, 0, 0 };
pub const kRecruit_Draw_Char: [8]u8 = .{ 0x8a, 0x8c, 0x8a, 0x8c, 0x86, 0x88, 0x8e, 0xa0 };
pub const kRecruit_Draw_Flags: [8]u8 = .{ 0x40, 0x40, 0, 0, 0, 0, 0, 0 };
pub const kSprite_Zora_SurfacingGfx: [16]u8 = .{ 4, 3, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 0, 0 };
pub const kChainBallTrooperHead_Char: [4]u8 = .{ 2, 2, 0, 4 };
pub const kChainBallTrooperHead_Flags: [4]u8 = .{ 0x40, 0, 0, 0 };
pub const kFlailTrooperBody_X: [72]i8 = .{
    -4, 4,  12, -4, 4,  13, -4, 4,  13, -4, 4,  13, -4, 4,  13, -4,
    4,  13, 0,  0,  4,  0,  0,  5,  0,  0,  6,  0,  0,  4,  -4, 4,
    -6, -4, 4,  -5, -4, 4,  -5, -4, 4,  -6, -4, 4,  -5, -4, 4,  -6,
    0,  0,  4,  0,  0,  3,  0,  0,  2,  0,  0,  4,  0,  0,  0,  0,
    0,  0,  -4, 4,  4,  -4, 4,  4,
};
pub const kFlailTrooperBody_Y: [72]i8 = .{
    0,  0,  -4, 0,  0, -4, 0,  0, -3, 0,  0, -2, 0,  0, -3, 0,
    0,  -2, 0,  0,  1, 0,  0,  1, 0,  0,  2, 0,  0,  2, 0,  0,
    -2, 0,  0,  -2, 0, 0,  -1, 0, 0,  -1, 0, 0,  -1, 0, 0,  -1,
    0,  0,  1,  0,  0, 1,  0,  0, 2,  0,  0, 2,  0,  0, 0,  0,
    0,  0,  0,  0,  0, 0,  0,  0,
};
pub const kFlailTrooperBody_Char: [72]u8 = .{
    0x46, 6,    0x2f, 0x46, 6,    0x2f, 0x48, 0xd,  0x2f, 0x48, 0xd,  0x2f, 0x49, 0xc,  0x2f, 0x49,
    0xc,  0x2f, 8,    8,    0x2f, 8,    8,    0x2f, 0x22, 0x22, 0x2f, 0x22, 0x22, 0x2f, 0xa,  0x64,
    0x2f, 0xa,  0x64, 0x2f, 0x2c, 0x67, 0x2f, 0x2c, 0x67, 0x2f, 0x2d, 0x66, 0x2f, 0x2d, 0x66, 0x2f,
    8,    8,    0x2f, 8,    8,    0x2f, 0x22, 0x22, 0x2f, 0x22, 0x22, 0x2f, 0x62, 0x62, 0x62, 0x62,
    0x62, 0x62, 0x46, 0x4b, 0x4b, 0x69, 0x64, 0x64,
};
pub const kFlailTrooperBody_Flags: [72]u8 = .{
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0x40, 0x40, 0,    0x40,
    0x40, 0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0x40,
    0x40, 0,    0x40, 0x40, 0,    0,    0x40, 0,    0,    0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,
    0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0,
    0,    0,    0,    0x40, 0x40, 0,    0x40, 0x40,
};
pub const kFlailTrooperBody_Big: [72]u8 = .{
    2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 0, 2,
    2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2,
    0, 2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 0,
    2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2,
};
pub const kFlailTrooperBody_Num: [24]u8 = .{
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 1, 1, 1, 1,
};
pub const kFlailTrooperBody_SprOffs: [24]u8 = .{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 8, 8, 8, 8,
};
pub export const kSinusLookupTable: [256]u16 = .{
    0,   3,   6,   9,   12,  15,  18,  21,  25,  28,  31,  34,  37,  40,  40,  46,
    49,  53,  56,  59,  62,  65,  68,  71,  74,  77,  80,  83,  86,  89,  92,  95,
    97,  100, 103, 106, 109, 112, 115, 117, 120, 123, 126, 128, 131, 134, 136, 139,
    142, 144, 147, 149, 152, 155, 157, 159, 162, 164, 167, 169, 171, 174, 176, 178,
    181, 183, 185, 187, 189, 191, 193, 195, 197, 199, 201, 203, 205, 207, 209, 211,
    212, 214, 216, 217, 219, 221, 222, 224, 225, 227, 228, 230, 231, 232, 234, 235,
    236, 237, 238, 239, 241, 242, 243, 244, 244, 245, 246, 247, 248, 249, 249, 250,
    251, 251, 252, 252, 253, 253, 254, 254, 254, 255, 255, 255, 255, 255, 255, 255,
    256, 255, 255, 255, 255, 255, 255, 255, 254, 254, 254, 253, 253, 252, 252, 251,
    251, 250, 249, 249, 248, 247, 246, 245, 244, 244, 243, 242, 241, 239, 238, 237,
    236, 235, 234, 232, 231, 230, 228, 227, 225, 224, 222, 221, 219, 217, 216, 214,
    212, 211, 209, 207, 205, 203, 201, 199, 197, 195, 193, 191, 189, 187, 185, 183,
    181, 178, 176, 174, 171, 169, 167, 164, 162, 159, 157, 155, 152, 149, 147, 144,
    142, 139, 136, 134, 131, 128, 126, 123, 120, 117, 115, 112, 109, 106, 103, 100,
    97,  95,  92,  89,  86,  83,  80,  77,  74,  71,  68,  65,  62,  59,  56,  53,
    49,  46,  43,  40,  37,  34,  31,  28,  25,  21,  18,  15,  12,  9,   6,   3,
};
pub const kFlailTrooperWeapon_Tab4: [4]u8 = .{ 0x33, 0x66, 0x99, 0xcc };
pub const kFlailTrooperWeapon_Tab0: [32]u8 = .{
    0x10, 0x12, 0x14, 0x16, 0x18, 0x1a, 0x1c, 0x1e, 0x20, 0x22, 0x24, 0x26, 0x28, 0x2a, 0x2c, 0x2e,
    0x30, 0x2e, 0x2c, 0x2a, 0x28, 0x26, 0x24, 0x22, 0x20, 0x1e, 0x1c, 0x1a, 0x18, 0x16, 0x14, 0x12,
};
pub const kFlailTrooperWeapon_Tab1: [4]i8 = .{ 4, 4, 12, -5 };
pub const kFlailTrooperWeapon_Tab2: [4]i8 = .{ -2, -2, -6, -4 };
pub const kFlailTrooperAttackDir: [4]u8 = .{ 3, 1, 2, 0 };
pub const kSprite_WarpVortex_Flags: [4]u8 = .{ 0, 0x40, 0xc0, 0x80 };
pub const kSpriteRope_Gfx: [8]i8 = .{ 0, 0, 2, 3, 2, 3, 1, 1 };
pub const kSpriteRope_Flags: [8]i8 = .{ 0, 0x40, 0, 0, 0x40, 0x40, 0, 0x40 };
pub const kSpriteRope_Tab1: [8]i8 = .{ 4, 5, 2, 3, 0, 1, 6, 7 };
pub const kSpriteRope_Xvel: [8]i8 = .{ 8, -8, 0, 0, 16, -16, 0, 0 };
pub const kSpriteRope_Yvel: [8]i8 = .{ 0, 0, 8, -8, 0, 0, 0x10, -0x10 };
pub const kSpriteRope_Tab0: [4]i8 = .{ 2, 3, 1, 0 };
pub const kSpawnBee_InitDelay: [4]u8 = .{ 64, 64, 255, 255 };
pub const kSpawnBee_InitVel: [8]i8 = .{ 15, 5, -5, -15, 20, 10, -10, -20 };
pub const kLargeShadow_Dmd: [15]DrawMultipleData = .{
    .{ .x = -6, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 0, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 6, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = -5, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 0, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 5, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = -4, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 0, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 4, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = -3, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 0, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 3, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = -2, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 0, .y = 19, .char_flags = 0x086c, .ext = 2 },
    .{ .x = 2, .y = 19, .char_flags = 0x086c, .ext = 2 },
};
pub const kHelmasaur_Tab0: [32]u8 = .{
    0, 1, 2, 3, 4, 5, 6, 7, 8, 8, 8, 8, 8, 8, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 7, 6, 5, 4, 3, 2, 1,
};
pub const kFluteBoyAnimal_OamFlags: [2]u8 = .{ 0x40, 0 };
pub const kFluteBoyAnimal_Gfx: [3]u8 = .{ 0, 1, 2 };
pub const kGibo_OamFlags: [4]u8 = .{ 0, 0x40, 0xc0, 0x80 };
pub const kGibo_OamFlags2: [2]u8 = .{ 11, 7 };
pub const kBlindHead_Draw_Char: [16]u8 = .{ 0x86, 0x86, 0x84, 0x82, 0x80, 0x82, 0x84, 0x86, 0x86, 0x86, 0x88, 0x8a, 0x8c, 0x8a, 0x88, 0x86 };
pub const kBlindHead_Draw_Flags: [16]u8 = .{ 0, 0, 0, 0, 0, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0, 0, 0, 0 };
pub const kGanon_G_Func2: [16]u8 = .{ 8, 7, 6, 5, 4, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1 };
pub const kGanon_Draw_X: [204]i8 = .{
    18,  -8,  8,   -8, 8,   -18, -18, 18, -8,  8,   -8,  8,   18,  -8,  8,   -8,
    8,   -18, -18, 18, -8,  8,   -8,  8,  16,  -8,  8,   -8,  8,   -18, -18, 16,
    -8,  8,   -11, 11, 16,  -8,  8,   -8, 8,   -18, -18, 16,  -8,  8,   -11, 11,
    16,  -8,  8,   -8, 8,   -18, -18, 16, -8,  8,   -11, 11,  18,  -8,  8,   -8,
    8,   -18, -18, 18, -8,  8,   -8,  8,  18,  -8,  8,   -8,  8,   -18, -18, 18,
    -8,  8,   -8,  8,  18,  -8,  8,   -8, 8,   -18, -18, 18,  -8,  8,   -11, 11,
    -8,  8,   -8,  8,  -8,  8,   -8,  8,  -18, -18, 18,  18,  -8,  8,   -8,  8,
    -8,  8,   -8,  8,  -18, -18, 18,  18, -8,  8,   -8,  8,   -8,  8,   -10, 10,
    -18, -18, 18,  18, -8,  8,   -8,  8,  -8,  8,   -10, 10,  -18, -18, 18,  18,
    -8,  8,   -8,  8,  -8,  8,   -10, 10, -18, -18, 18,  18,  -8,  8,   -8,  8,
    -8,  8,   -8,  8,  -18, -18, 18,  18, -8,  8,   -8,  8,   -8,  8,   -8,  8,
    -18, -18, 18,  18, -7,  -8,  8,   -8, 8,   -9,  8,   -14, -14, -8,  8,   8,
    -8,  8,   -8,  8,  -18, -18, 18,  18, -8,  8,   -11, 11,
};
pub const kGanon_Draw_Y: [204]i8 = .{
    -8,  -16, -16, -13, -13, -9,  -1,  -16, 3,   3,   8,   8,   -8,  -16, -16, -13,
    -13, -9,  -1,  -16, 3,   3,   8,   8,   5,   -10, -10, -13, -13, -7,  1,   -3,
    3,   3,   8,   8,   5,   -10, -10, -13, -13, -7,  1,   -3,  3,   3,   8,   8,
    5,   -10, -10, -13, -13, -7,  1,   -3,  3,   3,   8,   8,   -1,  -16, -16, -13,
    -13, -9,  -1,  -9,  3,   3,   8,   8,   -10, -16, -16, -13, -13, -18, -10, -18,
    3,   3,   8,   8,   1,   -10, -10, -13, -13, -7,  1,   -7,  3,   3,   8,   8,
    -12, -12, 4,   4,   -18, -18, 10,  10,  -16, -8,  -4,  4,   -12, -12, 4,   4,
    -18, -18, 10,  10,  -16, -8,  -4,  4,   -12, -12, 4,   4,   -12, -12, 10,  10,
    -4,  4,   -4,  4,   -12, -12, 4,   4,   -12, -12, 10,  10,  -4,  4,   -4,  4,
    -12, -12, 4,   4,   -12, -12, 10,  10,  -4,  4,   -4,  4,   -12, -12, 4,   4,
    -18, -18, 10,  10,  -4,  4,   -4,  4,   -12, -12, 4,   4,   -18, -18, 10,  10,
    -16, -8,  -16, -8,  -7,  -12, -12, 4,   4,   7,   13,  -11, -4,  -16, -16, -16,
    -10, -10, -13, -13, -7,  -7,  -7,  -7,  3,   3,   8,   8,
};
pub const kGanon_Draw_Char: [204]u8 = .{
    0x16, 0,    0,    2,    2,    8,    0x18, 6,    0x22, 0x22, 0x20, 0x20, 0x46, 0,    0,    2,
    2,    8,    0x18, 0x36, 0x22, 0x22, 0x20, 0x20, 0x1a, 0,    0,    4,    4,    0x38, 0x48, 0xa,
    0x24, 0x24, 0x20, 0x20, 0x1a, 0x40, 0x42, 4,    4,    0x38, 0x48, 0xa,  0x24, 0x24, 0x20, 0x20,
    0x1a, 0x42, 0x40, 4,    4,    0x38, 0x48, 0xa,  0x24, 0x24, 0x20, 0x20, 0x18, 0,    0,    2,
    2,    8,    0x18, 8,    0x22, 0x22, 0x20, 0x20, 0x16, 0x6a, 0x6a, 0xe,  0xe,  6,    0x16, 6,
    0x22, 0x22, 0x20, 0x20, 0x48, 0,    0,    4,    4,    0x38, 0x48, 0x38, 0x24, 0x24, 0x20, 0x20,
    0x4e, 0x4e, 0x6e, 0x6e, 0x6c, 0x6c, 0xa2, 0xa2, 0xc,  0x1c, 0x3c, 0x4c, 0x4e, 0x4e, 0x6e, 0x6e,
    0x6c, 0x6c, 0xa2, 0xa2, 0x3a, 0x4a, 0x3c, 0x4c, 0x84, 0x84, 0xa4, 0xa4, 0xa0, 0xa0, 0xa2, 0xa2,
    0x3c, 0x4c, 0x3c, 0x4c, 0x84, 0x84, 0xa4, 0xa4, 0x80, 0x82, 0xa2, 0xa2, 0x3c, 0x4c, 0x3c, 0x4c,
    0x84, 0x84, 0xa4, 0xa4, 0x82, 0x80, 0xa2, 0xa2, 0x3c, 0x4c, 0x3c, 0x4c, 0x4e, 0x4e, 0x6e, 0x6e,
    0x6c, 0x6c, 0xa2, 0xa2, 0x3c, 0x4c, 0x3c, 0x4c, 0x4e, 0x4e, 0x6e, 0x6e, 0x6c, 0x6c, 0xa2, 0xa2,
    0xc,  0x1c, 0xc,  0x1c, 0xe0, 0xc6, 0xc8, 0xe6, 0xe8, 0x20, 0x20, 8,    0x18, 0xc0, 0xc2, 0xc2,
    0,    0,    0xce, 0xce, 0xec, 0xec, 0xec, 0xec, 0xee, 0xee, 0xc4, 0xc4,
};
pub const kGanon_Draw_Flags: [204]u8 = .{
    0x4c, 0xc,  0x4c, 0xa,  0x4a, 0xc,  0xc,  0x4c, 0xa,  0x4a, 0xc,  0x4c, 0x4c, 0xc,  0x4c, 0xa,
    0x4a, 0xc,  0xc,  0x4c, 0xa,  0x4a, 0xc,  0x4c, 0x4c, 0xc,  0x4c, 0xa,  0x4a, 0xc,  0xc,  0x4c,
    0xa,  0x4a, 0xc,  0x4c, 0x4c, 0xc,  0xc,  0xa,  0x4a, 0xc,  0xc,  0x4c, 0xa,  0x4a, 0xc,  0x4c,
    0x4c, 0x4c, 0x4c, 0xa,  0x4a, 0xc,  0xc,  0x4c, 0xa,  0x4a, 0xc,  0x4c, 0x4c, 0xc,  0x4c, 0xa,
    0x4a, 0xc,  0xc,  0x4c, 0xa,  0x4a, 0xc,  0x4c, 0x4c, 0xc,  0x4c, 0xa,  0x4a, 0xc,  0xc,  0x4c,
    0xa,  0x4a, 0xc,  0x4c, 0x4c, 0xc,  0x4c, 0xa,  0x4a, 0xc,  0xc,  0x4c, 0xa,  0x4a, 0xc,  0x4c,
    0xa,  0x4a, 0xa,  0x4a, 0xc,  0x4c, 0xc,  0x4c, 0xc,  0xc,  0x4c, 0x4c, 0xa,  0x4a, 0xa,  0x4a,
    0xc,  0x4c, 0xc,  0x4c, 0xc,  0xc,  0x4c, 0x4c, 0xa,  0x4a, 0xa,  0x4a, 0xc,  0x4c, 0xc,  0x4c,
    0xc,  0xc,  0x4c, 0x4c, 0xa,  0x4a, 0xa,  0x4a, 0xc,  0xc,  0xc,  0x4c, 0xc,  0xc,  0x4c, 0x4c,
    0xa,  0x4a, 0xa,  0x4a, 0x4c, 0x4c, 0xc,  0x4c, 0xc,  0xc,  0x4c, 0x4c, 0xa,  0x4a, 0xa,  0x4a,
    0xc,  0x4c, 0xc,  0x4c, 0xc,  0xc,  0x4c, 0x4c, 0xa,  0x4a, 0xa,  0x4a, 0xc,  0x4c, 0xc,  0x4c,
    0xc,  0xc,  0x4c, 0x4c, 0xc,  0xa,  0xa,  0xa,  0xa,  0xc,  0x4c, 0xc,  0xc,  0xc,  0xc,  0xc,
    0xc,  0x4c, 0xa,  0x4a, 0xc,  0xc,  0x4c, 0x4c, 0xa,  0x4a, 0xc,  0x4c,
};
pub const kGanon_Draw_Char2: [12]u8 = .{ 0x40, 0x42, 0, 0, 0x42, 0x40, 0x82, 0x80, 0xa0, 0xa0, 0x80, 0x82 };
pub const kGanon_Draw_Flags2: [12]u8 = .{ 0, 0, 0, 0x40, 0x40, 0x40, 0x40, 0x40, 0, 0x40, 0, 0 };
pub const kGiantMoldorm_SegA_Dmd: [8]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x0086, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x4086, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4084, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x40a4, .ext = 2 },
};
pub const kGiantMoldorm_OamFlags: [4]u8 = .{ 0, 0x40, 0xc0, 0x80 };
pub const kFortuneTeller_Prices: [4]u8 = .{ 10, 15, 20, 30 };
pub const kWishPondMsgs: [5]u8 = .{ 0x8f, 0x90, 0x92, 0x91, 0x93 };
pub const kArcheryGame_CashPrize: [10]u8 = .{ 4, 8, 16, 32, 64, 99, 99, 99, 99, 99 };
pub const kArcheryTarget_X: [2]i8 = .{ -24, 8 };
pub const kHobo_Dmd: [12]DrawMultipleData = .{
    .{ .x = -5, .y = 3, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 3, .y = 3, .char_flags = 0x00a7, .ext = 2 },
    .{ .x = -5, .y = 3, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 3, .y = 3, .char_flags = 0x00a7, .ext = 2 },
    .{ .x = -5, .y = 3, .char_flags = 0x00ab, .ext = 0 },
    .{ .x = 3, .y = 3, .char_flags = 0x00a7, .ext = 2 },
    .{ .x = -5, .y = 3, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 3, .y = 3, .char_flags = 0x00a7, .ext = 2 },
    .{ .x = 5, .y = -11, .char_flags = 0x008a, .ext = 2 },
    .{ .x = -5, .y = 3, .char_flags = 0x00ab, .ext = 0 },
    .{ .x = 3, .y = 3, .char_flags = 0x0088, .ext = 2 },
    .{ .x = -5, .y = 3, .char_flags = 0x00a6, .ext = 2 },
};
pub const kWaterTurbulence_Dmd: [6]DrawMultipleData = .{
    .{ .x = -10, .y = 14, .char_flags = 0x00c0, .ext = 2 },
    .{ .x = -5, .y = 16, .char_flags = 0x40c0, .ext = 2 },
    .{ .x = -2, .y = 18, .char_flags = 0x00c0, .ext = 2 },
    .{ .x = 2, .y = 18, .char_flags = 0x40c0, .ext = 2 },
    .{ .x = 5, .y = 16, .char_flags = 0x00c0, .ext = 2 },
    .{ .x = 10, .y = 14, .char_flags = 0x40c0, .ext = 2 },
};
pub const kSparkleGarnish_Coord: [4]i8 = .{ -4, 0, 4, 8 };
pub const kHelmasaurFireball_Char: [3]u8 = .{ 0xcc, 0xcc, 0xca };
pub const kHelmasaurFireball_Flags: [2]u8 = .{ 0x33, 0x73 };
pub const kHelmasaurFireball_Gfx: [4]u8 = .{ 2, 2, 1, 0 };
pub const kWallCannon_Xvel: [4]i8 = .{ 0, 0, -16, 16 };
pub const kWallCannon_Yvel: [4]i8 = .{ -16, 16, 0, 0 };
pub const kWallCannon_Gfx: [4]u8 = .{ 0, 0, 2, 2 };
pub const kWallCannon_OamFlags: [4]u8 = .{ 0x40, 0, 0, 0x80 };
pub const kWallCannon_Spawn_X: [4]i8 = .{ 8, -8, 0, 0 };
pub const kWallCannon_Spawn_Y: [4]i8 = .{ 0, 0, 8, -8 };
pub const kWallCannon_Spawn_Xvel: [4]i8 = .{ 24, -24, 0, 0 };
pub const kWallCannon_Spawn_Yvel: [4]i8 = .{ 0, 0, 24, -24 };
pub const kArcheryGameGuy_Gfx: [4]u8 = .{ 3, 4, 3, 2 };
pub const kArcheryGame_NumSpr: [6]u8 = .{ 5, 4, 3, 2, 1, 0 };
pub const kArcheryGame_X: [18]i8 = .{
    0,
    0,
    0,
    0,
    48,
    48,
    48,
    48,
    8,
    8,
    16,
    16,
    24,
    24,
    32,
    32,
    40,
    40,
};
pub const kArcheryGame_Y: [18]i8 = .{ -8, 0, 8, 16, -8, 0, 8, 16, 0, 8, 0, 8, 0, 8, 0, 8, 0, 8 };
pub const kArcheryGame_Char: [18]u8 = .{ 0x2b, 0x3b, 0x3b, 0x2b, 0x2b, 0x3b, 0x3b, 0x2b, 0x63, 0x73, 0x63, 0x73, 0x63, 0x73, 0x63, 0x73, 0x63, 0x73 };
pub const kArcheryGame_Flags: [18]u8 = .{ 0x33, 0x33, 0xb3, 0xb3, 0x73, 0x73, 0xf3, 0xf3, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32, 0x32 };
pub const kGoodArcheryTarget_X: [5]i8 = .{ -8, -8, 0, 8, 16 };
pub const kGoodArcheryTarget_Y: [5]i8 = .{ -24, -16, -20, -20, -20 };
pub const kGoodArcheryTarget_Draw_Char: [3]u8 = .{ 0xb, 0x1b, 0xb6 };
pub const kGoodArcheryTarget_Draw_Flags: [5]i8 = .{ 0x38, 0x38, 0x34, 0x35, 0x35 };
pub const kGoodArcheryTarget_Draw_Char3: [6]u8 = .{ 0x12, 0x32, 0x31, 3, 0x22, 0x33 };
pub const kGoodArcheryTarget_Draw_Char4: [6]u8 = .{ 0x7c, 0x7c, 0x22, 2, 0x12, 0x33 };
pub const kDebirandoPit_OpeningGfx: [4]u8 = .{ 5, 4, 3, 3 };
pub const kDebirandoPit_ClosingGfx: [4]u8 = .{ 3, 3, 4, 5 };
pub const kDebirandoPit_Draw_X: [24]i16 = .{
    -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, 0, 8, 0, 8,
    0,  8, 0,  8, -8, 8, -8, 8,
};
pub const kDebirandoPit_Draw_Y: [24]i16 = .{
    -8, -8, 8, 8, -8, -8, 8, 8, -8, -8, 8, 8, 0, 0, 8, 8,
    0,  0,  8, 8, -8, -8, 8, 8,
};
pub const kDebirandoPit_Draw_Char: [24]u8 = .{
    4,    4,    4,    4,    0x22, 0x22, 0x22, 0x22, 2, 2, 2, 2, 0x29, 0x29, 0x29, 0x29,
    0x39, 0x39, 0x39, 0x39, 0x2a, 0x2a, 0x2a, 0x2a,
};
pub const kDebirandoPit_Draw_Flags: [24]u8 = .{
    0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0,
    0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0,
};
pub const kDebirandoPit_Draw_Big: [6]u8 = .{ 2, 2, 2, 0, 0, 2 };
pub const kDebirando_Emerge_Gfx: [2]u8 = .{ 1, 0 };
pub const kDebirando_Submerge_Gfx: [2]u8 = .{ 0, 1 };
pub const kDebirando_Draw_X: [16]i8 = .{ 0, 8, 0, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0 };
pub const kDebirando_Draw_Y: [16]i8 = .{ 2, 2, 6, 6, -2, -2, 6, 6, -4, -4, -4, -4, -4, -4, -4, -4 };
pub const kDebirando_Draw_Char: [16]u8 = .{ 0, 0, 0xd8, 0xd8, 0, 0, 0xd9, 0xd9, 0, 0, 0, 0, 0x20, 0x20, 0x20, 0x20 };
pub const kDebirando_Draw_Flags: [16]u8 = .{ 1, 0x41, 0, 0x40, 1, 1, 0, 0x40, 1, 1, 1, 1, 1, 1, 1, 1 };
pub const kDebirando_Draw_Big: [16]u8 = .{ 0, 0, 0, 0, 2, 2, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2 };
pub const kMasterSword_Gfx1: [9]u8 = .{ 0, 1, 1, 2, 2, 2, 1, 1, 0 };
pub const kMasterSword_NumLightBeams: [9]u8 = .{ 0, 0, 1, 1, 2, 2, 0, 0, 0 };
pub const kMasterSword_LightBall_Dmd: [12]DrawMultipleData = .{
    .{ .x = -6, .y = 4, .char_flags = 0x0082, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0x4082, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0xc082, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0x8082, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0x40a0, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0xc0a0, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0x80a0, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0x0080, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0x4080, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0xc080, .ext = 2 },
    .{ .x = -6, .y = 4, .char_flags = 0x8080, .ext = 2 },
};
pub const kMasterSword_LightBeam_Xv0: [2]i8 = .{ 0, -48 };
pub const kMasterSword_LightBeam_Xv1: [2]i8 = .{ 0, 48 };
pub const kMasterSword_LightBeam_Xv2: [2]i8 = .{ -96, -48 };
pub const kMasterSword_LightBeam_Xv3: [2]i8 = .{ 96, 48 };
pub const kMasterSword_LightBeam_Yv0: [2]i8 = .{ -96, -48 };
pub const kMasterSword_LightBeam_Yv1: [2]i8 = .{ 96, 48 };
pub const kMasterSword_LightBeam_Yv2: [2]i8 = .{ 0, 48 };
pub const kMasterSword_LightBeam_Yv3: [2]i8 = .{ 0, -48 };
pub const kMasterSword_LightBeam_Gfx0: [2]u8 = .{ 1, 0 };
pub const kMasterSword_LightBeam_Gfx2: [2]u8 = .{ 3, 2 };
pub const kMasterSword_LightBeam_Flags0: [2]u8 = .{ 5, 0x45 };
pub const kMasterSword_LightBeam_Flags2: [2]u8 = .{ 5, 5 };
pub const kMasterSword_Pendant_Xv: [4]i8 = .{ -4, 4, 0, 0 };
pub const kMasterSword_Pendant_Yv: [4]i8 = .{ -2, -2, -4, -4 };
pub const kMasterSword_Draw_X: [6]i8 = .{ -8, 0, -8, 0, -8, 0 };
pub const kMasterSword_Draw_Y: [6]i8 = .{ -8, -8, 0, 0, 8, 8 };
pub const kMasterSword_Draw_Char: [6]u8 = .{ 0xc3, 0xc4, 0xd3, 0xd4, 0xe0, 0xf0 };
pub const kSpikeRoller_XYvel: [6]i8 = .{ -16, 16, 0, 0, -16, 16 };
pub const kSpikeRoller_Draw_X: [32]u8 = .{
    0, 0,    0,    0,    0,    0,    0,    0,    0, 0,    0,    0,    0,    0,    0,    0,
    0, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70,
};
pub const kSpikeRoller_Draw_Y: [32]u8 = .{
    0, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70,
    0, 0,    0,    0,    0,    0,    0,    0,    0, 0,    0,    0,    0,    0,    0,    0,
};
pub const kSpikeRoller_Draw_Char: [32]u8 = .{
    0x8e, 0x9e, 0x9e, 0x9e, 0x9e, 0x9e, 0x9e, 0x8e, 0x8e, 0x9e, 0x9e, 0x9e, 0x9e, 0x9e, 0x9e, 0x8e,
    0x88, 0x89, 0x89, 0x89, 0x89, 0x89, 0x89, 0x88, 0x88, 0x89, 0x89, 0x89, 0x89, 0x89, 0x89, 0x88,
};
pub const kSpikeRoller_Draw_Flags: [32]u8 = .{
    0, 0, 0, 0x80, 0, 0, 0, 0x80, 0x40, 0x40, 0x40, 0xc0, 0x40, 0x40, 0x40, 0xc0,
    0, 0, 0, 0x40, 0, 0, 0, 0x40, 0x80, 0x80, 0x80, 0xc0, 0x80, 0x80, 0x80, 0xc0,
};
pub const kBeamos_Draw_Y: [2]i8 = .{ -16, 0 };
pub const kBeamos_Draw_Char: [2]i8 = .{ 0x48, 0x68 };
pub const kBeamosEyeball_Draw_X: [32]i8 = .{
    -1, 0,  1,  2,  3,  4,  5,  7, 8, 10, 11, 12, 13, 14, 15, 16,
    17, 15, 14, 13, 12, 11, 10, 8, 7, 5,  4,  3,  2,  1,  0,  -2,
};
pub const kBeamosEyeball_Draw_Y: [32]i8 = .{
    11, 12, 13, 14, 14, 15, 15, 15, 15, 15, 15, 14, 14, 13, 12, 11,
    10, 9,  8,  7,  7,  6,  6,  6,  6,  6,  6,  7,  7,  8,  9,  10,
};
pub const kBeamosEyeball_Draw_Char: [32]u8 = .{
    0x5b, 0x5b, 0x5a, 0x5a, 0x4b, 0x4b, 0x4a, 0x4a, 0x4a, 0x4a, 0x4b, 0x4b, 0x5a, 0x5a, 0x5b, 0x5b,
    0x5b, 0x5b, 0x4c, 0x4c, 0x4c, 0x4c, 0x4c, 0x4c, 0x5b, 0x5b, 0x4c, 0x4c, 0x4c, 0x4c, 0x4c, 0x4c,
};
pub const kBeamosEyeball_Draw_Flags: [32]u8 = .{
    0,    0,    0,    0,    0,    0,    0,    0,    0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,
    0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0,    0,    0,    0,    0,    0,    0,    0,
};
pub const kBeamosLaserHit_Draw_X: [4]i8 = .{ -4, 4, -4, 4 };
pub const kBeamosLaserHit_Draw_Y: [4]i8 = .{ -4, -4, 4, 4 };
pub const kBeamosLaserHit_Draw_Flags: [4]u8 = .{ 6, 0x46, 0x86, 0xc6 };
pub const kSpark_OamFlags: [4]u8 = .{ 0, 0x40, 0x80, 0xc0 };
pub const kSpark_directions: [8]u8 = .{ 1, 3, 2, 0, 7, 5, 6, 4 };
pub const kCrab_Xvel: [4]i8 = .{ 28, -28, 0, 0 };
pub const kCrab_Yvel: [4]i8 = .{ 0, 0, 12, -12 };
pub const kCrab_Draw_X: [4]i16 = .{ -8, 8, -8, 8 };
pub const kCrab_Draw_Char: [4]u8 = .{ 0x8e, 0x8e, 0xae, 0xae };
pub const kCrab_Draw_Flags: [4]i8 = .{ 0, 0x40, 0, 0x40 };
pub const kDesertBarrier_NextD: [4]u8 = .{ 3, 2, 0, 1 };
pub const kDesertBarrier_Dmd: [4]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x408e, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x00ae, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x40ae, .ext = 2 },
};
pub const kSprite_ZoraFireball_Offs: [4]u8 = .{ 3, 2, 0, 0 };
pub const kSprite_ZoraFireball_X: [4]i8 = .{ 4, 4, -4, 16 };
pub const kSprite_ZoraFireball_Y: [4]i8 = .{ 0, 16, 8, 8 };
pub const kSprite_ZoraFireball_W: [4]u8 = .{ 8, 8, 4, 4 };
pub const kSprite_ZoraFireball_H: [4]u8 = .{ 4, 4, 8, 8 };
pub const kSprite_Zora_Surface_XY: [8]i8 = .{ -32, -24, -16, -8, 8, 16, 24, 32 };
pub const kSprite_Zora_AttackGfx: [8]u8 = .{ 5, 5, 6, 10, 6, 5, 5, 5 };
pub const kSprite_Zora_SubmergeGfx: [12]u8 = .{ 12, 11, 9, 8, 7, 0, 0, 0, 0, 0, 0, 0 };
pub const kZora_Draw_X: [26]i8 = .{
    4, 4, 0,  0,  0, 0, 0,  0,  0,  0,  0, 0, 0, 0, 0, 0,
    0, 0, -4, 11, 0, 4, -8, 18, -8, 18,
};
pub const kZora_Draw_Y: [26]i8 = .{
    4,  4,  0,  0,  0,  0, 0,   -3,  0,   -3,  -3, -3, -3, -3, -3, -3,
    -6, -6, -8, -9, -3, 5, -10, -11, -10, -11,
};
pub const kZora_Draw_Char: [26]u8 = .{
    0xa8, 0xa8, 0x88, 0x88, 0x88, 0x88, 0x88, 0xa4, 0x88, 0xa4, 0xa4, 0xa4, 0xa6, 0xa6, 0xa4, 0xc0,
    0x8a, 0x8a, 0xae, 0xaf, 0xa6, 0x8d, 0xcf, 0xcf, 0xdf, 0xdf,
};
pub const kZora_Draw_Flags: [26]u8 = .{
    0x25, 0x25, 0x25, 0x25, 0xe5, 0xe5, 0x25, 0x20, 0xe5, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x24,
    0x25, 0x25, 0x24, 0x64, 0x20, 0x26, 0x24, 0x64, 0x24, 0x64,
};
pub const kZora_Draw_Big: [26]u8 = .{
    0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 0, 0, 2, 0, 0, 0, 0, 0,
};
pub const kZoraKing_Surfacing_Gfx: [16]u8 = .{ 0, 0, 0, 3, 9, 8, 7, 6, 9, 8, 7, 6, 5, 4, 5, 4 };
pub const kZoraKing_Dialogue_Gfx: [8]u8 = .{ 0, 0, 1, 2, 1, 2, 0, 0 };
pub const kZoraKing_Submerge_Gfx: [21]u8 = .{
    12, 12, 12, 12, 12, 12, 11, 11, 11, 11, 11, 10, 10, 10, 10, 3,
    3,  3,  3,  3,  3,
};
pub const kSpawnSplashRing_X: [8]i8 = .{ -8, -5, 4, 13, 16, 13, 4, -5 };
pub const kSpawnSplashRing_Y: [8]i8 = .{ 4, -5, -8, -5, 4, 13, 16, 13 };
pub const kSpawnSplashRing_Xvel: [8]i8 = .{ -8, -6, 0, 6, 8, 6, 0, -6 };
pub const kSpawnSplashRing_Yvel: [8]i8 = .{ 0, -6, -8, -6, 0, 6, 8, 6 };
pub const kZoraKing_Draw_X0: [52]i8 = .{
    -8,  8,  -8,  8,  -8, 8, -8, 8, -8, 8, -8, 8, -8,  8,  -8,  8,
    0,   0,  0,   0,  0,  0, 0,  0, -8, 8, -8, 8, -8,  8,  -8,  8,
    -8,  8,  -8,  8,  -8, 8, -8, 8, -9, 9, -9, 9, -10, 10, -10, 10,
    -11, 11, -11, 11,
};
pub const kZoraKing_Draw_Y0: [52]i8 = .{
    -18, -18, -2, -2, -18, -18, -2, -2, -18, -18, -2, -2, -12, -12, 4, 4,
    0,   0,   0,  0,  0,   0,   0,  0,  -8,  -8,  8,  8,  -8,  -8,  8, 8,
    -8,  -8,  8,  8,  -8,  -8,  8,  8,  -5,  -5,  5,  5,  -5,  -5,  5, 5,
    -5,  -5,  5,  5,
};
pub const kZoraKing_Draw_Char0: [52]u8 = .{
    0xc0, 0xc0, 0xe0, 0xe0, 0xc2, 0xea, 0xe2, 0xe2, 0xea, 0xc2, 0xe2, 0xe2, 0xc0, 0xc0, 0xe4, 0xe6,
    0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0xc4, 0xc6, 0xe4, 0xe6, 0xc6, 0xc4, 0xe6, 0xe4,
    0xe6, 0xe4, 0xc6, 0xc4, 0xe4, 0xe6, 0xc4, 0xc6, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88,
    0x88, 0x88, 0x88, 0x88,
};
pub const kZoraKing_Draw_Flags0: [52]u8 = .{
    0,    0x40, 0,    0x40, 0,    0x40, 0,    0x40, 0, 0x40, 0,    0x40, 0,    0x40, 5,    5,
    5,    5,    5,    5,    0xc5, 0xc5, 0xc5, 0xc5, 5, 5,    5,    5,    0x45, 0x45, 0x45, 0x45,
    0xc5, 0xc5, 0xc5, 0xc5, 0x85, 0x85, 0x85, 0x85, 4, 0x44, 0x84, 0xc4, 4,    0x44, 0x84, 0xc4,
    4,    0x44, 0x84, 0xc4,
};
pub const kZoraKing_Draw_X1: [8]i8 = .{ -23, 23, 23, 23, -20, -15, 13, 18 };
pub const kZoraKing_Draw_Y1: [8]i8 = .{ -8, -8, -8, -8, -7, 0, 0, -7 };
pub const kZoraKing_Draw_Char1: [8]u8 = .{ 0xae, 0xae, 0xae, 0xae, 0xac, 0xac, 0xac, 0xac };
pub const kZoraKing_Draw_Flags1: [8]u8 = .{ 0, 0x40, 0x40, 0x40, 0, 0, 0x40, 0x40 };
pub const kWalkingZora_Draw_Char: [4]u8 = .{ 0xce, 0xce, 0xa4, 0xee };
pub const kWalkingZora_Draw_Flags: [4]u8 = .{ 0x40, 0, 0, 0 };
pub const kWalkingZora_Draw_Char2: [8]u8 = .{ 0xcc, 0xec, 0xcc, 0xec, 0xe8, 0xe8, 0xca, 0xca };
pub const kWalkingZora_Draw_Flags2: [8]u8 = .{ 0x40, 0x40, 0, 0, 0, 0x40, 0, 0x40 };
pub const kWaterRipple_Dmd: [6]DrawMultipleData = .{
    .{ .x = 0, .y = 10, .char_flags = 0x01d8, .ext = 0 },
    .{ .x = 8, .y = 10, .char_flags = 0x41d8, .ext = 0 },
    .{ .x = 0, .y = 10, .char_flags = 0x01d9, .ext = 0 },
    .{ .x = 8, .y = 10, .char_flags = 0x41d9, .ext = 0 },
    .{ .x = 0, .y = 10, .char_flags = 0x01da, .ext = 0 },
    .{ .x = 8, .y = 10, .char_flags = 0x41da, .ext = 0 },
};
pub const kWaterRipple_Idx: [4]u8 = .{ 0, 1, 2, 1 };
pub const kArmosKnight_Gfx1: [5]u8 = .{ 5, 4, 3, 2, 1 };
pub const kArmosKnight_Xv: [2]i8 = .{ 16, -16 };
pub const kArmosKnight_Draw_X: [24]i8 = .{
    -8,  8,  -8,  8,  -10, 10, -10, 10, -10, 10, -10, 10, -12, 12, -12, 12,
    -14, 14, -14, 14, -16, 24, -16, 24,
};
pub const kArmosKnight_Draw_Y: [24]i8 = .{
    -8,  -8,  8,  8,  -10, -10, 10, 10, -10, -10, 10, 10, -12, -12, 12, 12,
    -14, -14, 14, 14, -16, -16, 24, 24,
};
pub const kArmosKnight_Draw_Char: [24]u8 = .{
    0xc0, 0xc2, 0xe0, 0xe2, 0xc0, 0xc2, 0xe0, 0xe2, 0xc4, 0xc4, 0xc4, 0xc4, 0xc6, 0xc6, 0xc6, 0xc6,
    0xc8, 0xc8, 0xc8, 0xc8, 0xd8, 0xd8, 0xd8, 0xd8,
};
pub const kArmosKnight_Draw_Flags: [24]u8 = .{
    0,    0, 0,    0,    0,    0, 0,    0,    0x40, 0, 0xc0, 0x80, 0x40, 0, 0xc0, 0x80,
    0x40, 0, 0xc0, 0x80, 0x40, 0, 0xc0, 0x80,
};
pub const kArmosKnight_Draw_Big: [24]u8 = .{
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 0, 0, 0, 0,
};
pub const kLanmola_RandB: [8]u8 = .{ 0x58, 0x50, 0x60, 0x70, 0x80, 0x90, 0xa0, 0x98 };
pub const kLanmola_RandC: [8]u8 = .{ 0x68, 0x60, 0x70, 0x80, 0x90, 0xa0, 0xa8, 0x80 };
pub const kLanmola_ZVel: [2]i8 = .{ 2, -2 };
pub const kLanmola_SprOffs: [4]u8 = .{ 76, 60, 44, 28 };
pub const kLanmola_Draw_Char1: [16]u8 = .{ 0xc4, 0xe2, 0xc2, 0xe0, 0xc0, 0xe0, 0xc2, 0xe2, 0xc4, 0xe2, 0xc2, 0xe0, 0xc0, 0xe0, 0xc2, 0xe2 };
pub const kLanmola_Draw_Char0: [16]u8 = .{ 0xcc, 0xe4, 0xca, 0xe6, 0xc8, 0xe6, 0xca, 0xe4, 0xcc, 0xe4, 0xca, 0xe6, 0xc8, 0xe6, 0xca, 0xe4 };
pub const kLanmola_Draw_Flags: [16]u8 = .{ 0xc0, 0xc0, 0xc0, 0xc0, 0x80, 0x80, 0x80, 0x80, 0, 0, 0, 0, 0x40, 0x40, 0x40, 0x40 };
pub const kLanmola_Draw_Idx2: [16]u8 = .{ 4, 5, 4, 5, 4, 5, 4, 5, 4, 3, 2, 2, 1, 1, 0, 0 };
pub const kLanmola_Draw_Char2: [6]u8 = .{ 0xee, 0xee, 0xec, 0xec, 0xce, 0xce };
pub const kLanmola_Draw_Flags2: [6]u8 = .{ 0, 0x40, 0, 0x40, 0, 0x40 };
pub const kLanmola_Draw_X4: [8]i8 = .{ -8, 8, -10, 10, -16, 16, -24, 32 };
pub const kLanmola_Draw_Y4: [8]i8 = .{ 0, 0, -1, -1, -1, -1, 3, 3 };
pub const kLanmola_Draw_Char4: [8]u8 = .{ 0xe8, 0xe8, 0xe8, 0xe8, 0xea, 0xea, 0xea, 0xea };
pub const kLanmola_Draw_Flags4: [8]u8 = .{ 0, 0x40, 0, 0x40, 0, 0x40, 0, 0x40 };
pub const kLanmola_Draw_Big4: [8]u8 = .{ 2, 2, 2, 2, 2, 2, 0, 0 };
pub const kSpriteRat_Tab0: [16]u8 = .{ 0, 0, 3, 3, 1, 2, 4, 5, 1, 2, 4, 5, 0, 0, 3, 3 };
pub const kSpriteRat_Tab1: [16]u8 = .{ 0, 0x40, 0, 0x40, 0, 0, 0, 0, 0x40, 0x40, 0x40, 0x40, 0x80, 0xc0, 0x80, 0xc0 };
pub const kSpriteRat_Tab2: [8]u8 = .{ 10, 11, 6, 7, 2, 3, 14, 15 };
pub const kSpriteRat_Tab4: [8]u8 = .{ 8, 9, 4, 5, 0, 1, 12, 13 };
pub const kSpriteRat_Xvel: [4]i8 = .{ 24, -24, 0, 0 };
pub const kSpriteRat_Yvel: [4]i8 = .{ 0, 0, 24, -24 };
pub const kSpriteRat_Tab3: [4]u8 = .{ 2, 3, 1, 0 };
pub const kSpriteKeese_Tab1: [2]i8 = .{ 1, -1 };
pub const kSpriteKeese_Tab0: [4]i8 = .{ 2, 10, 6, 14 };
pub const kMetalBallLarge_X: [4]i8 = .{ -8, 8, -8, 8 };
pub const kMetalBallLarge_Y: [4]i8 = .{ -8, -8, 8, 8 };
pub const kMetalBallLarge_Char: [8]u8 = .{ 0x84, 0x88, 0x88, 0x88, 0x86, 0x88, 0x88, 0x88 };
pub const kMetalBallLarge_Flags: [4]u8 = .{ 0, 0, 0xc0, 0x80 };
pub const kArmos_Dmd: [2]DrawMultipleData = .{
    .{ .x = 0, .y = -16, .char_flags = 0x00c0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e0, .ext = 2 },
};
pub const kBot_Gfx: [4]u8 = .{ 0, 1, 0, 1 };
pub const kBot_OamFlags: [4]u8 = .{ 0, 0, 0x40, 0x40 };
pub const kGerudoMan_EmergeGfx: [8]u8 = .{ 3, 2, 0, 0, 0, 0, 0, 0 };
pub const kGerudoMan_PursueGfx: [2]u8 = .{ 4, 5 };
pub const kGerudoMan_SubmergeGfx: [5]u8 = .{ 0, 1, 2, 3, 3 };
pub const kGerudoMan_Draw_X: [18]i8 = .{ 4, 4, 4, 4, 4, 4, -8, 8, 8, -8, 8, 8, -16, 0, 16, -16, 0, 16 };
pub const kGerudoMan_Draw_Y: [18]i8 = .{ 8, 8, 8, 8, 8, 8, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
pub const kGerudoMan_Draw_Char: [18]u8 = .{
    0xb8, 0xb8, 0xb8, 0xb8, 0xb8, 0xb8, 0xa6, 0xa6, 0xa6, 0xa6, 0xa6, 0xa6, 0xa4, 0xa2, 0xa0, 0xa0, 0xa2, 0xa4,
};
pub const kGerudoMan_Draw_Flags: [18]u8 = .{
    0, 0, 0, 0x40, 0x40, 0x40, 0, 0x40, 0x40, 0, 0x40, 0x40, 0x40, 0x40, 0x40, 0, 0, 0,
};
pub const kGerudoMan_Draw_Big: [18]u8 = .{ 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 };
pub const kToppo_XOffs: [4]i8 = .{ -32, 32, 0, 0 };
pub const kToppo_YOffs: [4]i8 = .{ 0, 0, -32, 32 };
pub const kToppo_Draw_X: [15]i8 = .{ 0, 8, 8, 0, 8, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0 };
pub const kToppo_Draw_Y: [15]i8 = .{ 8, 8, 8, 8, 8, 8, 0, 8, 8, 0, 0, 0, 0, 0, 0 };
pub const kToppo_Draw_Char: [15]u8 = .{ 0xc8, 0xc8, 0xc8, 0xca, 0xca, 0xca, 0xc0, 0xc8, 0xc8, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2 };
pub const kToppo_Draw_Flags: [15]u8 = .{ 0, 0x40, 0x40, 0, 0x40, 0x40, 0, 0, 0x40, 0, 0, 0, 0x40, 0x40, 0x40 };
pub const kToppo_Draw_Big: [15]u8 = .{ 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 2, 2, 2, 2, 2 };
pub const kBombTrooperBomb_X: [4]i8 = .{ 0, 1, 9, -8 };
pub const kBombTrooperBomb_Y: [4]i8 = .{ -12, -12, -15, -13 };
pub const kBombTrooperBomb_Zvel: [16]i8 = .{ 32, 40, 48, 56, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64 };
pub const kBombTrooper_DrawArm_X: [8]i8 = .{ -1, 1, 2, 0, 9, 9, -8, -8 };
pub const kBombTrooper_DrawArm_Y: [8]i8 = .{ -12, -12, -12, -12, -16, -14, -12, -14 };
pub const kEnemyBombExplosion_X: [16]i8 = .{ -12, 12, -12, 12, -8, 8, -8, 8, -8, 8, -8, 8, 0, 0, 0, 0 };
pub const kEnemyBombExplosion_Y: [16]i8 = .{ -12, -12, 12, 12, -8, -8, 8, 8, -8, -8, 8, 8, 0, 0, 0, 0 };
pub const kEnemyBombExplosion_Char: [16]u8 = .{ 0x88, 0x88, 0x88, 0x88, 0x8a, 0x8a, 0x8a, 0x8a, 0x84, 0x84, 0x84, 0x84, 0x86, 0x86, 0x86, 0x86 };
pub const kEnemyBombExplosion_Flags: [16]u8 = .{ 0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0, 0, 0, 0, 0 };
pub const kSolderThrowing_Draw_X: [16]i8 = .{ 15, 7, 17, 9, -8, 0, -10, -2, 13, 13, 13, 13, -4, -4, -4, -4 };
pub const kSolderThrowing_Draw_Y: [16]i8 = .{ -2, -2, -2, -2, -2, -2, -2, -2, 8, 0, 10, 2, -14, -6, -16, -8 };
pub const kSolderThrowing_Draw_Char: [16]u8 = .{ 0x6f, 0x7f, 0x6f, 0x7f, 0x6f, 0x7f, 0x6f, 0x7f, 0x6e, 0x7e, 0x6e, 0x7e, 0x6e, 0x7e, 0x6e, 0x7e };
pub const kSolderThrowing_Draw_Flags: [16]u8 = .{ 0x40, 0x40, 0x40, 0x40, 0, 0, 0, 0, 0x80, 0x80, 0x80, 0x80, 0, 0, 0, 0 };
pub const kJavelinTrooper_Gfx: [4]u8 = .{ 12, 0, 18, 8 };
pub const kSolderThrowing_DirFlags: [4]u8 = .{ 3, 3, 12, 12 };
pub const kSolderThrowing_Xd: [8]i8 = .{ -80, 80, 0, -8, -80, 80, -8, 8 };
pub const kSolderThrowing_Yd: [8]i8 = .{ 8, 8, -80, 80, 8, 8, -80, 80 };
pub const kJavelinProjectile_X: [8]i8 = .{ 16, -8, 3, 11, 12, -4, 12, -4 };
pub const kJavelinProjectile_Y: [8]i8 = .{ 2, 2, 16, -8, -2, -2, 2, -8 };
pub const kJavelinProjectile_Xvel: [8]i8 = .{ 48, -48, 0, 0, 32, -32, 0, 0 };
pub const kJavelinProjectile_Yvel: [8]i8 = .{ 0, 0, 48, -48, 0, 0, 32, -32 };
pub const kJavelinProjectile_Flags4: [4]u8 = .{ 5, 5, 6, 6 };
pub const kBushSoldier_Gfx: [32]u8 = .{
    4, 4, 4, 4, 4, 4, 4, 4, 0, 1, 0, 1, 0, 1, 0, 1,
    0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1,
};
pub const kBushSoldier_Gfx2: [16]u8 = .{ 0, 1, 0, 1, 0, 1, 0, 1, 0, 2, 3, 4, 4, 4, 4, 4 };
pub const kBushSoldierCommon_Y: [14]i8 = .{ 8, 8, 8, 8, 2, 8, 0, 8, -3, 8, -3, 8, -3, 8 };
pub const kBushSoldierCommon_Char: [14]u8 = .{ 0x20, 0x20, 0x20, 0x20, 0x40, 0x20, 0x40, 0x20, 0x40, 0x20, 0x42, 0x20, 0x42, 0x20 };
pub const kBushSoldierCommon_Flags: [14]u8 = .{ 9, 3, 0x49, 0x43, 9, 3, 0x49, 0x43, 9, 3, 0x49, 0x43, 9, 3 };
pub const kArcherSoldier_WeaponOamOffs: [4]u8 = .{ 0, 0, 0, 16 };
pub const kArcherSoldier_HeadOamOffs: [4]u8 = .{ 16, 16, 16, 0 };
pub const kArcherSoldier_BodyOamOffs: [4]u8 = .{ 20, 20, 20, 4 };
pub const kArcherSoldier_Tab1: [4]u8 = .{ 9, 3, 0, 6 };
pub const kArcherSoldier_Draw_X: [48]i8 = .{
    -1, 7,  3,  3,  -1, 7,  3,  3,  -1, 7,  7,  7,  -5, -5, -10, -2,
    -4, -4, -6, 2,  -5, -5, -5, -5, 6,  14, 11, 11, 6,  14, 11,  11,
    6,  14, 14, 14, 11, 11, 18, 10, 12, 12, 14, 6,  11, 11, 11,  11,
};
pub const kArcherSoldier_Draw_Y: [48]i8 = .{
    7,  7,  3,  11, 6,  6, 1, 9, 7,  7,  7,   7,  -2, 6,  2,  2,
    -2, 6,  2,  2,  -2, 6, 6, 6, -6, -6, -12, -4, -6, -6, -9, -1,
    -6, -6, -6, -6, -2, 6, 2, 2, -2, 6,  2,   2,  -2, 6,  6,  6,
};
pub const kArcherSoldier_Draw_Char: [48]u8 = .{
    0xa,  0xa,  0x2a, 0x2b, 0x1a, 0x1a, 0x2a, 0x2b, 0xa,  0xa,  0xa,  0xa,  0xb, 0xb, 0x3d, 0x3a,
    0x1b, 0x1b, 0x3d, 0x3a, 0xb,  0xb,  0xb,  0xb,  0xa,  0xa,  0x2b, 0x2a, 0xa, 0xa, 0x2b, 0x2a,
    0xa,  0xa,  0xa,  0xa,  0xb,  0xb,  0x3d, 0x3a, 0x1b, 0x1b, 0x3d, 0x3a, 0xb, 0xb, 0xb,  0xb,
};
pub const kArcherSoldier_Draw_Flags: [48]u8 = .{
    0xd,  0x4d, 8,    8,    0xd,  0x4d, 8,    8,    0xd,  0x4d, 0x4d, 0x4d, 0xd,  0x8d, 0x48, 0x48,
    0xd,  0x8d, 0x48, 0x48, 0xd,  0x8d, 0x8d, 0x8d, 0x8d, 0xcd, 0x88, 0x88, 0x8d, 0xcd, 0x88, 0x88,
    0x8d, 0xcd, 0xcd, 0xcd, 0x4d, 0xcd, 8,    8,    0x4d, 0xcd, 8,    8,    0x4d, 0xcd, 0xcd, 0xcd,
};
pub const kBadPullSwitch_Tab1: [10]u8 = .{ 8, 24, 4, 4, 4, 4, 4, 4, 2, 10 };
pub const kBadPullSwitch_Tab0: [10]u8 = .{ 6, 7, 8, 8, 8, 8, 8, 9, 9, 9 };
pub const kBadPullUpSwitch_Tab2: [2]u8 = .{ 0xa2, 0xa4 };
pub const kGoodPullSwitch_Tab1: [12]u8 = .{ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 };
pub const kGoodPullSwitch_Tab0: [12]u8 = .{ 1, 1, 2, 2, 3, 3, 1, 1, 4, 4, 5, 5 };
pub const kGoodPullSwitch_YOffs: [12]u8 = .{ 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14 };
pub const kGoodPullSwitch_Tab2: [14]u8 = .{ 1, 1, 2, 3, 2, 3, 4, 5, 6, 7, 6, 7, 7, 7 };
pub const kQuarrelBros_Dmd: [16]DrawMultipleData = .{
    .{ .x = 0, .y = -12, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = -11, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x400a, .ext = 2 },
    .{ .x = 0, .y = -12, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = -11, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x400a, .ext = 2 },
    .{ .x = 0, .y = -12, .char_flags = 0x0008, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = -11, .char_flags = 0x0008, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x400a, .ext = 2 },
    .{ .x = 0, .y = -12, .char_flags = 0x4008, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = -11, .char_flags = 0x4008, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x400a, .ext = 2 },
};
pub const kYoungSnitchLady_Dmd: [16]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x0026, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e8, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0026, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x40e8, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0024, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00c2, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0024, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x40c2, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0028, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e4, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0028, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x00e6, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4028, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40e4, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x4028, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x40e6, .ext = 2 },
};
pub const kInnKeeper_Dmd: [2]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x00c4, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00ca, .ext = 2 },
};
pub const kWitch_DrawDataA: [16]OamEntSigned = .{
    .{ .x = -3, .y = 8, .charnum = 0xae, .flags = 0x00 },
    .{ .x = -3, .y = 16, .charnum = 0xbe, .flags = 0x00 },
    .{ .x = -2, .y = 8, .charnum = 0xae, .flags = 0x00 },
    .{ .x = -2, .y = 16, .charnum = 0xbe, .flags = 0x00 },
    .{ .x = -1, .y = 8, .charnum = 0xaf, .flags = 0x00 },
    .{ .x = -1, .y = 16, .charnum = 0xbf, .flags = 0x00 },
    .{ .x = 0, .y = 9, .charnum = 0xaf, .flags = 0x00 },
    .{ .x = 0, .y = 17, .charnum = 0xbf, .flags = 0x00 },
    .{ .x = 1, .y = 10, .charnum = 0xaf, .flags = 0x00 },
    .{ .x = 1, .y = 18, .charnum = 0xbf, .flags = 0x00 },
    .{ .x = 0, .y = 11, .charnum = 0xaf, .flags = 0x00 },
    .{ .x = 0, .y = 18, .charnum = 0xbf, .flags = 0x00 },
    .{ .x = -1, .y = 10, .charnum = 0xae, .flags = 0x00 },
    .{ .x = -1, .y = 18, .charnum = 0xbe, .flags = 0x00 },
    .{ .x = -3, .y = 9, .charnum = 0xae, .flags = 0x00 },
    .{ .x = -3, .y = 17, .charnum = 0xbe, .flags = 0x00 },
};
pub const kWitch_DrawDataB: [3]OamEntSigned = .{
    .{ .x = 0, .y = -4, .charnum = 0x80, .flags = 0x00 },
    .{ .x = -11, .y = 15, .charnum = 0x86, .flags = 0x04 },
    .{ .x = -3, .y = 15, .charnum = 0x86, .flags = 0x44 },
};
pub const kWitch_DrawDataC: [2]OamEntSigned = .{
    .{ .x = 0, .y = 4, .charnum = 0x84, .flags = 0x00 },
    .{ .x = 0, .y = 4, .charnum = 0x82, .flags = 0x00 },
};
pub const kOldSnitchLady_Xd: [2]i8 = .{ -32, 32 };
pub const kOldSnitchLady_Xvel: [4]i8 = .{ 0, 0, -9, 9 };
pub const kOldSnitchLady_Yvel: [4]i8 = .{ -9, 9, 0, 0 };
pub const kRunningMan_Xvel2: [2]i8 = .{ -24, 24 };
pub const kRunningMan_Xvel: [4]i8 = .{ 0, 0, -54, 54 };
pub const kRunningMan_Yvel: [4]i8 = .{ -54, 54, 0, 0 };
pub const kRunningMan_Dir: [4]i8 = .{ 3, 1, 3, -1 };
pub const kRunningMan_A: [4]u8 = .{ 120, 24, 128, 3 };
pub const kRunningMan_Dmd: [16]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x002c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x08ee, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x002c, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x48ee, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x002a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x08ca, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x002a, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x48ca, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x002e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x08cc, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x002e, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x08ce, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x402e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x48cc, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x402e, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x48ce, .ext = 2 },
};
pub const kBottleVendor_Dmd: [4]DrawMultipleData = .{
    .{ .x = 0, .y = -7, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0088, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a2, .ext = 2 },
};
pub const kZelda_Delay0: [4]u8 = .{ 38, 26, 44, 1 };
pub const kZelda_Dir0: [4]u8 = .{ 1, 3, 1, 2 };
pub const kHeartPieceMsg: [4]u16 = .{ 0x158, 0x155, 0x156, 0x157 };
pub const kElder_Dmd: [4]DrawMultipleData = .{
    .{ .x = 0, .y = -9, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a4, .ext = 2 },
};
pub const kDustCloud_Gfx: [9]u8 = .{ 0, 1, 2, 3, 4, 5, 1, 0, 0xff };
pub const kMedallionTabletMsg: [2]u16 = .{ 0x10d, 0x10f };
pub const kMedallionTabletEtherMsg: [2]u16 = .{ 0x10d, 0x10e };
pub const kElderWife_Dmd: [4]DrawMultipleData = .{
    .{ .x = 0, .y = -5, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 0, .y = 5, .char_flags = 0x0028, .ext = 2 },
    .{ .x = 0, .y = -4, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 0, .y = 5, .char_flags = 0x4028, .ext = 2 },
};
pub const kMagicPowder_Dmd: [2]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x04e6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x04e6, .ext = 2 },
};
pub const kGreenPotionItem_Dmd: [3]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x08c0, .ext = 2 },
    .{ .x = 8, .y = 18, .char_flags = 0x0a30, .ext = 0 },
    .{ .x = -1, .y = 18, .char_flags = 0x0a22, .ext = 0 },
};
pub const kBluePotionItem_Dmd: [4]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x04c0, .ext = 2 },
    .{ .x = 13, .y = 18, .char_flags = 0x0a30, .ext = 0 },
    .{ .x = 5, .y = 18, .char_flags = 0x0a22, .ext = 0 },
    .{ .x = -3, .y = 18, .char_flags = 0x0a31, .ext = 0 },
};
pub const kRedPotionItem_Dmd: [4]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x02c0, .ext = 2 },
    .{ .x = 13, .y = 18, .char_flags = 0x0a30, .ext = 0 },
    .{ .x = 5, .y = 18, .char_flags = 0x0a02, .ext = 0 },
    .{ .x = -3, .y = 18, .char_flags = 0x0a31, .ext = 0 },
};
pub const kShopkeeper_Dmd: [4]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x0c00, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c10, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0c00, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4c10, .ext = 2 },
};
pub const kDashTreeTop_CharFlags: [16]u16 = .{ 0x3100, 0x3102, 0x7102, 0x7100, 0x3120, 0x3122, 0x7122, 0x7120, 0x3104, 0x3106, 0x7106, 0x7104, 0x3124, 0x3126, 0x7126, 0x7124 };
pub const kDashTreeTop_X: [16]i8 = .{ 10, 22, 30, 1, 34, 5, 13, 29, 0, 17, 27, 44, 15, 33, 18, 26 };
pub const kDashTreeTop_Y: [16]i8 = .{ 0, 4, 2, 7, 10, 16, 24, 23, 34, 35, 30, 31, 46, 42, 10, 11 };
pub const kDashTreeTop_Char: [6]i8 = .{ 8, 8, 0x28, 0x28, 0x2a, 0x2a };
pub const kDashTreeTop_Flags: [6]i8 = .{ 0x31, 0x71, 0x31, 0x71, 0x31, 0x71 };
pub const kTroughBoy_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x0882, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0882, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4880, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0880, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
};
pub const kBottleVendor_FishRewardType: [5]u8 = .{ 0xdb, 0xe0, 0xde, 0xe2, 0xd9 };
pub const kBottleVendor_FishRewardXv: [5]i8 = .{ -6, -3, 0, 4, 7 };
pub const kBottleVendor_FishRewardYv: [5]i8 = .{ 11, 14, 16, 14, 11 };
pub const kSpriteRat_BumpDamage: [2]u8 = .{ 0, 5 };
pub const kSpriteRat_Health: [2]u8 = .{ 2, 8 };
pub const kSpriteKeese_BumpDamage: [2]u8 = .{ 0x80, 0x85 };
pub const kSpriteKeese_Health: [2]u8 = .{ 1, 4 };
pub const kSpriteKeese_Flags5: [2]u8 = .{ 0, 7 };
pub const kSpriteRope_BumpDamage: [2]u8 = .{ 1, 5 };
pub const kSpriteRope_Health: [2]u8 = .{ 4, 8 };
pub const kSpriteRope_Flags5: [2]u8 = .{ 1, 7 };
pub const kHokbok_InitXvel: [4]i8 = .{ 16, -16, 16, -16 };
pub const kHokbok_InitYvel: [4]i8 = .{ 16, 16, -16, -16 };
pub const kSprite_Octoballoon_Delay: [4]u8 = .{ 192, 208, 224, 240 };
pub const kSpriteRaven_BumpDamage: [2]u8 = .{ 0x81, 0x88 };
pub const kSpriteRaven_Health: [2]u8 = .{ 4, 8 };
pub const kSpriteRaven_Flags5: [2]u8 = .{ 6, 2 };
pub const kDebirando_OamFlags: [2]u8 = .{ 6, 8 };
pub const kArcheryGameGuy_X: [8]u8 = .{ 0, 0x40, 0x80, 0xc0, 0x30, 0x60, 0x90, 0xc0 };
pub const kArcheryGameGuy_Y: [8]u8 = .{ 0, 0x4f, 0x4f, 0x4f, 0x5a, 0x5a, 0x5a, 0x5a };
pub const kArcheryGameGuy_A: [8]u8 = .{ 0, 1, 1, 1, 2, 2, 2, 2 };
pub const kArcheryGameGuy_Xvel: [2]i8 = .{ -8, 12 };
pub const kArcheryGameGuy_Flags4: [2]u8 = .{ 0x1c, 0x15 };
pub const kShopKeeperWhere: [13]u8 = .{ 0xf, 0x10, 0, 6, 0x18, 0x12, 0x1e, 0xff, 0x1f, 0x23, 0x24, 0x25, 0x27 };
pub const kStoryTellerRooms: [5]u8 = .{ 0xe, 0xe, 0x12, 0x1a, 0x14 };
pub const kHumanMultiTypes: [3]u8 = .{ 3, 0xe1, 0x19 };
pub const kDashItemMask: [2]u16 = .{ 0x4000, 0x2000 };
pub const kGanonHelpers_OamFlags: [2]u8 = .{ 9, 7 };
pub const kGanonHelpers_Health: [2]u8 = .{ 8, 12 };
pub const kGanonHelpers_BumpDamage: [2]u8 = .{ 3, 5 };
pub const kLeever_OamFlags: [2]u8 = .{ 10, 2 };
pub const kBubble_Xvel: [2]i8 = .{ 16, -16 };
pub const kOctorock_BumpDamage: [2]u8 = .{ 3, 5 };
pub const kOctorock_Health: [2]u8 = .{ 2, 4 };
pub const kLanmola_InitDelay: [3]u8 = .{ 128, 192, 255 };
pub const kSpriteSoldier_Tab0: [8]u8 = .{ 0, 2, 1, 3, 6, 4, 5, 7 };
pub const kHardHatBeetle_OamFlags: [2]u8 = .{ 6, 8 };
pub const kHardHatBeetle_Health: [2]u8 = .{ 32, 6 };
pub const kHardHatBeetle_A: [2]u8 = .{ 16, 12 };
pub const kHardHatBeetle_State: [2]u8 = .{ 1, 3 };
pub const kHardHatBeetle_Flags5: [2]u8 = .{ 2, 6 };
pub const kHardHatBeetle_BumpDamage: [2]u8 = .{ 5, 3 };
pub const kAgahnim_OamFlags: [2]u8 = .{ 11, 7 };
pub const kGiantMoldorm_Xvel: [32]i8 = .{
    24, 22, 17, 9,  0, -9,  -17, -22, -24, -22, -17, -9,  0, 9,  17, 22,
    36, 33, 25, 13, 0, -13, -25, -33, -36, -33, -25, -13, 0, 13, 25, 33,
};
pub const kGiantMoldorm_Yvel: [32]i8 = .{
    0, 9,  17, 22, 24, 22, 17, 9,  0, -9,  -17, -22, -24, -22, -17, -9,
    0, 13, 25, 33, 36, 33, 25, 13, 0, -13, -25, -33, -36, -33, -25, -13,
};
pub const kGiantMoldorm_NextDir: [16]u8 = .{ 8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7 };
pub const kVulture_Gfx: [4]u8 = .{ 1, 2, 3, 2 };
pub const kDeadRock_Gfx: [9]u8 = .{ 0, 1, 0, 1, 2, 2, 3, 3, 4 };
pub const kDeadRock_OamFlags: [9]u8 = .{ 0x40, 0x40, 0, 0, 0, 0x40, 0, 0x40, 0 };
pub const kDeadRock_Xvel: [4]i8 = .{ 32, -32, 0, 0 };
pub const kDeadRock_Yvel: [4]i8 = .{ 0, 0, 32, -32 };
pub const kSluggula_Gfx: [8]u8 = .{ 0, 1, 0, 1, 2, 3, 4, 5 };
pub const kSluggula_OamFlags: [8]u8 = .{ 0x40, 0x40, 0, 0, 0, 0, 0, 0 };
pub const kSluggula_XYvel: [6]i8 = .{ 16, -16, 0, 0, 16, -16 };
pub const kPoe_Accel: [4]i8 = .{ 1, -1, 2, -2 };
pub const kPoe_ZvelTarget: [2]i8 = .{ 8, -8 };
pub const kPoe_XvelTarget: [4]i8 = .{ 16, -16, 28, -28 };
pub const kPoe_OamFlags: [2]u8 = .{ 0x40, 0 };
pub const kPoe_Yvel: [2]i8 = .{ 8, -8 };
pub const kPoe_Draw_X: [2]i8 = .{ 9, -1 };
pub const kPoe_Draw_Char: [4]u8 = .{ 0x7c, 0x80, 0xb7, 0x80 };
pub const kMoldorm_Xvel: [16]i8 = .{ 24, 22, 17, 9, 0, -9, -17, -22, -24, -22, -17, -9, 0, 9, 17, 22 };
pub const kMoldorm_Yvel: [16]i8 = .{ 0, 9, 17, 22, 24, 22, 17, 9, 0, -9, -17, -22, -24, -22, -17, -9 };
pub const kMoldorm_NextDir: [16]u8 = .{ 8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7 };
pub const kMoblin_Xvel: [4]i8 = .{ 16, -16, 0, 0 };
pub const kMoblin_Yvel: [4]i8 = .{ 0, 0, 16, -16 };
pub const kMoblin_Delay: [4]u8 = .{ 0x10, 0x20, 0x30, 0x40 };
pub const kMoblin_Gfx2: [8]u8 = .{ 11, 10, 8, 9, 7, 5, 0, 2 };
pub const kMoblin_Dirs: [8]u8 = .{ 2, 3, 2, 3, 0, 1, 0, 1 };
pub const kMoblin_Gfx: [4]u8 = .{ 6, 4, 0, 2 };
pub const kMoblinSpear_X: [4]i8 = .{ 11, -2, -3, 11 };
pub const kMoblinSpear_Y: [4]i8 = .{ -3, -3, 3, -11 };
pub const kMoblinSpear_Xvel: [4]i8 = .{ 32, -32, 0, 0 };
pub const kMoblinSpear_Yvel: [4]i8 = .{ 0, 0, 32, -32 };
pub const kMoblin_Dmd: [48]DrawMultipleData = .{
    .{ .x = -2, .y = 3, .char_flags = 0x8091, .ext = 0 },
    .{ .x = -2, .y = 11, .char_flags = 0x8090, .ext = 0 },
    .{ .x = 0, .y = -10, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x008a, .ext = 2 },
    .{ .x = -2, .y = 7, .char_flags = 0x8091, .ext = 0 },
    .{ .x = -2, .y = 15, .char_flags = 0x8090, .ext = 0 },
    .{ .x = 0, .y = -10, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x408a, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 11, .y = -5, .char_flags = 0x0090, .ext = 0 },
    .{ .x = 11, .y = 3, .char_flags = 0x0091, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a0, .ext = 2 },
    .{ .x = 11, .y = -8, .char_flags = 0x0090, .ext = 0 },
    .{ .x = 11, .y = 0, .char_flags = 0x0091, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0x0080, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x0081, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x0088, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = -9, .y = 6, .char_flags = 0x0080, .ext = 0 },
    .{ .x = -1, .y = 6, .char_flags = 0x0081, .ext = 0 },
    .{ .x = 0, .y = -8, .char_flags = 0x0088, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = 12, .y = 8, .char_flags = 0x4080, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x4081, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x4088, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = 17, .y = 6, .char_flags = 0x4080, .ext = 0 },
    .{ .x = 9, .y = 6, .char_flags = 0x4081, .ext = 0 },
    .{ .x = 0, .y = -8, .char_flags = 0x4088, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a4, .ext = 2 },
    .{ .x = -3, .y = -5, .char_flags = 0x8091, .ext = 0 },
    .{ .x = -3, .y = 3, .char_flags = 0x8090, .ext = 0 },
    .{ .x = 0, .y = -10, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = 11, .y = -11, .char_flags = 0x0090, .ext = 0 },
    .{ .x = 11, .y = -3, .char_flags = 0x0091, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4082, .ext = 2 },
    .{ .x = -2, .y = -3, .char_flags = 0x0080, .ext = 0 },
    .{ .x = 6, .y = -3, .char_flags = 0x0081, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x0088, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = 10, .y = -3, .char_flags = 0x4080, .ext = 0 },
    .{ .x = 2, .y = -3, .char_flags = 0x4081, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x4088, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a2, .ext = 2 },
};
pub const kMoblin_ObjOffs: [12]u8 = .{ 2, 2, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2 };
pub const kMoblin_HeadChar: [4]u8 = .{ 0x88, 0x88, 0x86, 0x84 };
pub const kMoblin_HeadFlags: [4]u8 = .{ 0x40, 0, 0, 0 };
pub const kSnapDragon_Delay: [4]u8 = .{ 0x20, 0x30, 0x40, 0x50 };
pub const kSnapDragon_Gfx: [4]u8 = .{ 4, 0, 6, 2 };
pub const kSnapDragon_Xvel: [8]i8 = .{ 8, -8, 8, -8, 16, -16, 16, -16 };
pub const kSnapDragon_Yvel: [8]i8 = .{ 8, 8, -8, -8, 16, 16, -16, -16 };
pub const kSnapDragon_Dmd: [32]DrawMultipleData = .{
    .{ .x = 4, .y = -8, .char_flags = 0x008f, .ext = 0 },
    .{ .x = 12, .y = -8, .char_flags = 0x009f, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x008d, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x002b, .ext = 0 },
    .{ .x = 12, .y = -8, .char_flags = 0x003b, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x0028, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x0029, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x003c, .ext = 0 },
    .{ .x = 4, .y = -8, .char_flags = 0x003d, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00ab, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x003e, .ext = 0 },
    .{ .x = 4, .y = -8, .char_flags = 0x003f, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x00ad, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00ae, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x409f, .ext = 0 },
    .{ .x = 4, .y = -8, .char_flags = 0x408f, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x408d, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x408c, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x403b, .ext = 0 },
    .{ .x = 4, .y = -8, .char_flags = 0x402b, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x4029, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x4028, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x403d, .ext = 0 },
    .{ .x = 12, .y = -8, .char_flags = 0x403c, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x40ab, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x403f, .ext = 0 },
    .{ .x = 12, .y = -8, .char_flags = 0x403e, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x40ae, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x40ad, .ext = 2 },
};
pub const kRopa_Dmd: [12]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x0026, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x0027, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0008, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0036, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x0037, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4027, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x4026, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x4008, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4037, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x4036, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x4008, .ext = 2 },
};
pub const kHinox_RandomDirs: [8]u8 = .{ 2, 3, 3, 2, 0, 1, 1, 0 };
pub const kHinox_WalkGfx: [4]u8 = .{ 6, 4, 0, 2 };
pub const kHinox_BombX: [4]i8 = .{ 8, -8, -13, 13 };
pub const kHinox_BombY: [4]i8 = .{ -11, -11, -16, -16 };
pub const kHinox_BombXvel: [4]i8 = .{ 24, -24, 0, 0 };
pub const kHinox_BombYvel: [4]i8 = .{ 0, 0, 24, -24 };
pub const kHinox_Gfx: [8]u8 = .{ 11, 10, 8, 9, 7, 5, 1, 3 };
pub const kHinox_Xvel: [4]i8 = .{ 8, -8, 0, 0 };
pub const kHinox_Yvel: [4]i8 = .{ 0, 0, 8, -8 };
pub const kHinox_Dmd: [46]DrawMultipleData = .{
    .{ .x = 0, .y = -13, .char_flags = 0x0600, .ext = 2 },
    .{ .x = -8, .y = -5, .char_flags = 0x0624, .ext = 2 },
    .{ .x = 8, .y = -5, .char_flags = 0x4624, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x0606, .ext = 2 },
    .{ .x = 0, .y = -13, .char_flags = 0x0600, .ext = 2 },
    .{ .x = -8, .y = -5, .char_flags = 0x0624, .ext = 2 },
    .{ .x = 8, .y = -5, .char_flags = 0x4624, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x4606, .ext = 2 },
    .{ .x = -8, .y = -6, .char_flags = 0x0624, .ext = 2 },
    .{ .x = 8, .y = -6, .char_flags = 0x4624, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0606, .ext = 2 },
    .{ .x = 0, .y = -13, .char_flags = 0x0604, .ext = 2 },
    .{ .x = -8, .y = -6, .char_flags = 0x0624, .ext = 2 },
    .{ .x = 8, .y = -6, .char_flags = 0x4624, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4606, .ext = 2 },
    .{ .x = 0, .y = -13, .char_flags = 0x0604, .ext = 2 },
    .{ .x = -3, .y = -13, .char_flags = 0x0602, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x060c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x061c, .ext = 2 },
    .{ .x = -3, .y = -12, .char_flags = 0x0602, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x060e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x061e, .ext = 2 },
    .{ .x = 3, .y = -13, .char_flags = 0x4602, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x460c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x461c, .ext = 2 },
    .{ .x = 3, .y = -12, .char_flags = 0x4602, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x460e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x461e, .ext = 2 },
    .{ .x = -13, .y = -16, .char_flags = 0x056e, .ext = 2 },
    .{ .x = 0, .y = -13, .char_flags = 0x0600, .ext = 2 },
    .{ .x = -8, .y = -5, .char_flags = 0x0620, .ext = 2 },
    .{ .x = 8, .y = -5, .char_flags = 0x4624, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x0606, .ext = 2 },
    .{ .x = -8, .y = -5, .char_flags = 0x0624, .ext = 2 },
    .{ .x = 8, .y = -5, .char_flags = 0x4620, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x0606, .ext = 2 },
    .{ .x = 0, .y = -13, .char_flags = 0x0604, .ext = 2 },
    .{ .x = 13, .y = -16, .char_flags = 0x056e, .ext = 2 },
    .{ .x = -8, .y = -11, .char_flags = 0x056e, .ext = 2 },
    .{ .x = -3, .y = -13, .char_flags = 0x0602, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0622, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x060c, .ext = 2 },
    .{ .x = 8, .y = -11, .char_flags = 0x056e, .ext = 2 },
    .{ .x = 3, .y = -13, .char_flags = 0x4602, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4622, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x460c, .ext = 2 },
};
pub const kHinoxNum: [12]u8 = .{ 4, 4, 4, 4, 3, 3, 3, 3, 5, 5, 4, 4 };
pub const kHinoxOffs: [12]u8 = .{ 0, 4, 8, 12, 16, 19, 22, 25, 28, 33, 38, 42 };
pub const kBari_Xvel2: [16]i8 = .{ 0, 8, 11, 14, 16, 14, 11, 8, 0, -8, -11, -14, -16, -14, -11, -8 };
pub const kBari_Yvel2: [16]i8 = .{ -16, -14, -11, -8, 0, 8, 11, 14, 16, 14, 11, 8, 0, -9, -11, -14 };
pub const kBari_Gfx: [2]u8 = .{ 0, 3 };
pub const kBari_Xvel: [2]i8 = .{ 8, -8 };
pub const kRedBari_SplitX: [2]i8 = .{ 0, 8 };
pub const kRedBari_SplitXvel: [2]i8 = .{ -32, 32 };
pub const kRedBari_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x0022, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x4022, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x0032, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x4032, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0023, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x4023, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x0033, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x4033, .ext = 0 },
};
pub const kHelmasaur_Gfx: [8]u8 = .{ 3, 4, 3, 4, 2, 2, 5, 5 };
pub const kHelmasaur_OamFlags: [8]u8 = .{ 0x40, 0x40, 0, 0, 0, 0x40, 0x40, 0 };
pub const kHardHatBeetle_Dmd: [4]DrawMultipleData = .{
    .{ .x = 0, .y = -4, .char_flags = 0x0140, .ext = 2 },
    .{ .x = 0, .y = 2, .char_flags = 0x0142, .ext = 2 },
    .{ .x = 0, .y = -5, .char_flags = 0x0140, .ext = 2 },
    .{ .x = 0, .y = 2, .char_flags = 0x0144, .ext = 2 },
};
pub const kChicken_Avenger: [2]u8 = .{ 0, 0xff };
pub const kRupeeCoveredGrab_Gfx: [4]u8 = .{ 3, 4, 5, 4 };
pub const kRupeeCoveredGrab_Xvel: [4]i8 = .{ -12, 12, 0, 0 };
pub const kRupeeCoveredGrab_Yvel: [4]i8 = .{ 0, 0, -12, 12 };
pub const kRupeeCrab_Gfx: [4]u8 = .{ 0, 1, 0, 1 };
pub const kRupeeCrab_OamFlags: [4]u8 = .{ 0, 0, 0x40, 0 };
pub const kRupeeCrab_Xvel: [4]i8 = .{ -16, 16, -16, 16 };
pub const kRupeeCrab_Yvel: [4]i8 = .{ -16, -16, 16, 16 };
pub const kCoveredRupeeCrab_DrawY: [12]i8 = .{ 0, 0, 0, -3, 0, -5, 0, -6, 0, -6, 0, -6 };
pub const kCoveredRupeeCrab_DrawChar: [12]u8 = .{ 0x44, 0x44, 0xe8, 0x44, 0xe8, 0x44, 0xe6, 0x44, 0xe8, 0x44, 0xe6, 0x44 };
pub const kCoveredRupeeCrab_DrawFlags: [12]u8 = .{ 0, 0xc, 3, 0xc, 3, 0xc, 3, 0xc, 3, 0xc, 0x43, 0xc };
pub const kStoryTeller_Dmd: [10]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x0a4a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4a6e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a24, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4a24, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0804, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4804, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a6a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a6c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a0e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a2e, .ext = 2 },
};
pub const kFluteAardvark_Gfx: [20]i8 = .{
    1, 1, 1, 1, 2, 1, 2, 1, 2, 1, 2, 3, 2, 3, 2, 3, 2, 3, 2, -1,
};
pub const kFluteAardvark_Delay: [19]i8 = .{
    -1, -1, -1, 16, 2, 12, 6, 8, 10, 4, 14, 2, 10, 6, 6, 10, 2, 14, 2,
};
pub const kReturningSmithy_Delay: [3]i8 = .{ 104, 12, 0 };
pub const kReturningSmithy_Dir: [3]i8 = .{ 0, 2, -1 };
pub const kReturningSmithy_Xvel: [4]i8 = .{ 0, 0, -13, 13 };
pub const kReturningSmithy_Yvel: [4]i8 = .{ -13, 13, 0, 0 };
pub const kReturningSmithy_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x4122, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4122, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4122, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4122, .ext = 2 },
};
pub const kReturningSmithy_Dma: [8]u8 = .{ 0xc0, 0xc0, 0xa0, 0xa0, 0x80, 0x60, 0x80, 0x60 };
pub const kSmithyFrog_Dmd: [1]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x00c8, .ext = 2 },
};
pub const kSmithy_Gfx: [8]u8 = .{ 0, 1, 2, 3, 3, 2, 1, 0 };
pub const kSmithy_B: [8]u8 = .{ 24, 4, 1, 16, 16, 5, 10, 16 };
pub const kSmithy_Dmd: [20]DrawMultipleData = .{
    .{ .x = 1, .y = 0, .char_flags = 0x4040, .ext = 2 },
    .{ .x = -11, .y = -10, .char_flags = 0x4060, .ext = 2 },
    .{ .x = -1, .y = 0, .char_flags = 0x0040, .ext = 2 },
    .{ .x = 11, .y = -10, .char_flags = 0x0060, .ext = 2 },
    .{ .x = 1, .y = 0, .char_flags = 0x4040, .ext = 2 },
    .{ .x = -3, .y = -14, .char_flags = 0x4044, .ext = 2 },
    .{ .x = -1, .y = 0, .char_flags = 0x0040, .ext = 2 },
    .{ .x = 3, .y = -14, .char_flags = 0x0044, .ext = 2 },
    .{ .x = 1, .y = 0, .char_flags = 0x4042, .ext = 2 },
    .{ .x = 11, .y = -10, .char_flags = 0x0060, .ext = 2 },
    .{ .x = -1, .y = 0, .char_flags = 0x0042, .ext = 2 },
    .{ .x = -11, .y = -10, .char_flags = 0x4060, .ext = 2 },
    .{ .x = 1, .y = 0, .char_flags = 0x4042, .ext = 2 },
    .{ .x = 13, .y = 2, .char_flags = 0x4062, .ext = 2 },
    .{ .x = -1, .y = 0, .char_flags = 0x0042, .ext = 2 },
    .{ .x = -13, .y = 2, .char_flags = 0x0062, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4064, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4062, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0064, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0064, .ext = 2 },
};
pub const kSmithySpark_Gfx: [7]i8 = .{ 0, 1, 2, 1, 2, 1, -1 };
pub const kSmithySpark_Delay: [6]i8 = .{ 4, 1, 3, 2, 1, 1 };
pub const kSmithySpark_Dmd: [6]DrawMultipleData = .{
    .{ .x = 0, .y = 3, .char_flags = 0x41aa, .ext = 2 },
    .{ .x = 0, .y = -1, .char_flags = 0x41aa, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x0190, .ext = 0 },
    .{ .x = 12, .y = 0, .char_flags = 0x4190, .ext = 0 },
    .{ .x = -5, .y = -2, .char_flags = 0x0191, .ext = 0 },
    .{ .x = 13, .y = -2, .char_flags = 0x0191, .ext = 0 },
};
pub const kEnemyArrow_Xvel: [8]i8 = .{ 0, 0, 16, 16, 0, 0, -16, -16 };
pub const kEnemyArrow_Yvel: [8]i8 = .{ 16, 16, 0, 0, -16, -16, 0, 0 };
pub const kEnemyArrow_Dirs: [4]u8 = .{ 0, 2, 1, 3 };
pub const kEnemyArrow_Draw_X: [8]i16 = .{ -8, 0, 0, 8, 0, 0, 0, 0 };
pub const kEnemyArrow_Draw_Y: [8]i16 = .{ 0, 0, 0, 0, -8, 0, 0, 8 };
pub const kEnemyArrow_Draw_Char: [32]u8 = .{
    0x3a, 0x3d, 0x3d, 0x3a, 0x2a, 0x2b, 0x2b, 0x2a, 0x7c, 0x6c, 0x6c, 0x7c, 0x7b, 0x6b, 0x6b, 0x7b,
    0x3a, 0x3b, 0x3b, 0x3a, 0x2a, 0x3c, 0x3c, 0x2a, 0x81, 0x80, 0x80, 0x81, 0x91, 0x90, 0x90, 0x91,
};
pub const kEnemyArrow_Draw_Flags: [32]u8 = .{
    8, 8,    0x48, 0x48, 8, 8, 0x88, 0x88, 9,    0x49, 9, 0x49, 9,    0x89, 9, 0x89,
    8, 0x88, 0xc8, 0x48, 8, 8, 0x88, 0x88, 0x49, 0x49, 9, 9,    0x89, 0x89, 9, 9,
};
pub const kBugNetKid_Gfx: [8]i8 = .{ 0, 1, 0, 1, 0, 1, 2, -1 };
pub const kBugNetKid_Delay: [7]u8 = .{ 8, 12, 8, 12, 8, 96, 16 };
pub const kPushSwitch_Delay: [10]u8 = .{ 40, 6, 3, 3, 3, 5, 1, 1, 3, 12 };
pub const kPushSwitch_Dir: [10]u8 = .{ 0, 1, 2, 3, 4, 5, 5, 6, 7, 6 };
pub const kPushSwitch_Oam: [40]OamEntSigned = .{
    .{ .x = 4, .y = 20, .charnum = 0xdc, .flags = 0x20 },
    .{ .x = 4, .y = 12, .charnum = 0xdd, .flags = 0x20 },
    .{ .x = 4, .y = 12, .charnum = 0xdd, .flags = 0x20 },
    .{ .x = 4, .y = 12, .charnum = 0xdd, .flags = 0x20 },
    .{ .x = 0, .y = 0, .charnum = 0xca, .flags = 0x20 },
    .{ .x = 3, .y = 12, .charnum = 0xdd, .flags = 0x20 },
    .{ .x = 3, .y = 20, .charnum = 0xdc, .flags = 0x20 },
    .{ .x = 3, .y = 20, .charnum = 0xdc, .flags = 0x20 },
    .{ .x = 3, .y = 20, .charnum = 0xdc, .flags = 0x20 },
    .{ .x = 0, .y = 0, .charnum = 0xca, .flags = 0x20 },
    .{ .x = -8, .y = 8, .charnum = 0xea, .flags = 0x20 },
    .{ .x = 0, .y = 8, .charnum = 0xeb, .flags = 0x20 },
    .{ .x = -8, .y = 16, .charnum = 0xfa, .flags = 0x20 },
    .{ .x = 0, .y = 16, .charnum = 0xfb, .flags = 0x20 },
    .{ .x = 0, .y = 0, .charnum = 0xca, .flags = 0x20 },
    .{ .x = -12, .y = 4, .charnum = 0xcc, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = 0, .y = 0, .charnum = 0xca, .flags = 0x20 },
    .{ .x = -10, .y = 4, .charnum = 0xcc, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = 0, .y = 0, .charnum = 0xca, .flags = 0x20 },
    .{ .x = -8, .y = 4, .charnum = 0xcc, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = 0, .y = 0, .charnum = 0xca, .flags = 0x20 },
    .{ .x = 4, .y = 3, .charnum = 0xe2, .flags = 0x20 },
    .{ .x = -6, .y = 4, .charnum = 0xcc, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = 0, .y = 0, .charnum = 0xca, .flags = 0x20 },
    .{ .x = 4, .y = 3, .charnum = 0xf1, .flags = 0x20 },
    .{ .x = -6, .y = 4, .charnum = 0xcc, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = -4, .y = 4, .charnum = 0xcd, .flags = 0x20 },
    .{ .x = 0, .y = 0, .charnum = 0xca, .flags = 0x20 },
};
pub const kPushSwitch_WH: [16]u8 = .{ 8, 6, 0x10, 0x10, 0x10, 8, 0x10, 8, 0x10, 8, 0x10, 8, 0x10, 3, 0x10, 8 };
pub const kMiddleAgedMan_Dmd: [2]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x00ea, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00ec, .ext = 2 },
};
pub const kHobo_Gfx: [7]i8 = .{ 0, 1, 0, 1, 0, 1, 2 };
pub const kHobo_Delay: [7]i8 = .{ 6, 2, 6, 6, 2, 100, 30 };
pub const kHoboSmoke_OamFlags: [4]u8 = .{ 0, 64, 128, 192 };
pub const kUncleAndSage_Y: [3]i16 = .{ 0, -9, 0 };
pub const kMadBatter_RisingUp_XAccel: [2]i8 = .{ -8, 7 };
pub const kMadBatter_PseudoAttack_OamFlags: [8]i8 = .{ 0xa, 4, 2, 4, 2, 0xa, 4, 2 };
pub const kMovableStatue_Dir: [4]u8 = .{ 4, 6, 0, 2 };
pub const kMovableStatue_Joypad: [4]u8 = .{ 1, 2, 4, 8 };
pub const kMovableStatue_Xvel: [4]i8 = .{ -16, 16, 0, 0 };
pub const kMovableStatue_Yvel: [4]i8 = .{ 0, 0, -16, 16 };
pub const kMovableStatue_SwitchX: [4]i8 = .{ 3, 12, 3, 12 };
pub const kMovableStatue_SwitchY: [4]i8 = .{ 3, 3, 12, 12 };
pub const kMovableStatue_Dmd: [3]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x00c2, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x40c2, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x00c0, .ext = 2 },
};
pub const kHappinessPondCost: [4]u8 = .{ 5, 20, 25, 50 };
pub const kHappinessPondCostHex: [4]u8 = .{ 5, 0x20, 0x25, 0x50 };
pub const kMaxBombsForLevelHex: [8]u8 = .{ 0x10, 0x15, 0x20, 0x25, 0x30, 0x35, 0x40, 0x50 };
pub const kMaxArrowsForLevelHex: [8]u8 = .{ 0x30, 0x35, 0x40, 0x45, 0x50, 0x55, 0x60, 0x70 };
pub const kHappinessPondLuckMsg: [4]u16 = .{ 0x150, 0x151, 0x152, 0x153 };
pub const kHappinessPondLuck: [4]u8 = .{ 1, 0, 0, 2 };
pub const kWishPond2_Dmd: [8]DrawMultipleData = .{
    .{ .x = 32, .y = -64, .char_flags = 0x0024, .ext = 0 },
    .{ .x = 32, .y = -56, .char_flags = 0x0034, .ext = 0 },
    .{ .x = 32, .y = -64, .char_flags = 0x0024, .ext = 0 },
    .{ .x = 32, .y = -56, .char_flags = 0x0034, .ext = 0 },
    .{ .x = 32, .y = -64, .char_flags = 0x0024, .ext = 2 },
    .{ .x = 32, .y = -64, .char_flags = 0x0024, .ext = 2 },
    .{ .x = 32, .y = -64, .char_flags = 0x0024, .ext = 2 },
    .{ .x = 32, .y = -64, .char_flags = 0x0024, .ext = 2 },
};
pub const kFaerieQueen_Draw_X: [24]u8 = .{
    0, 16, 0, 8, 16, 24, 0, 8, 16, 24, 0, 16, 0, 16, 0, 8, 16, 24, 0, 8, 16, 24, 0, 16,
};
pub const kFaerieQueen_Draw_Y: [24]u8 = .{
    0, 0, 16, 16, 16, 16, 24, 24, 24, 24, 32, 32, 0, 0, 16, 16, 16, 16, 24, 24, 24, 24, 32, 32,
};
pub const kFaerieQueen_Draw_Char: [24]u8 = .{
    0xc7, 0xc7, 0xcf, 0xca, 0xca, 0xcf, 0xdf, 0xda, 0xda, 0xdf, 0xcb, 0xcb, 0xcd, 0xcd, 0xc9, 0xca,
    0xca, 0xc9, 0xd9, 0xda, 0xda, 0xd9, 0xcb, 0xcb,
};
pub const kFaerieQueen_Draw_Flags: [24]u8 = .{
    0, 0x40, 0, 0, 0x40, 0x40, 0, 0, 0x40, 0x40, 0, 0x40, 0, 0x40, 0, 0, 0x40, 0x40, 0, 0, 0x40, 0x40, 0, 0x40,
};
pub const kFaerieQueen_Draw_Big: [24]u8 = .{
    2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2,
};
pub const kFaerieQueen_Dmd: [20]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x00e9, .ext = 2 },
    .{ .x = 16, .y = 0, .char_flags = 0x40e9, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e9, .ext = 2 },
    .{ .x = 16, .y = 0, .char_flags = 0x40e9, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e9, .ext = 2 },
    .{ .x = 16, .y = 0, .char_flags = 0x40e9, .ext = 2 },
    .{ .x = 0, .y = 16, .char_flags = 0x00eb, .ext = 2 },
    .{ .x = 16, .y = 16, .char_flags = 0x40eb, .ext = 2 },
    .{ .x = 0, .y = 32, .char_flags = 0x00ed, .ext = 2 },
    .{ .x = 16, .y = 32, .char_flags = 0x40ed, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00ef, .ext = 0 },
    .{ .x = 24, .y = 0, .char_flags = 0x40ef, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x00ff, .ext = 0 },
    .{ .x = 24, .y = 8, .char_flags = 0x40ff, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e9, .ext = 2 },
    .{ .x = 16, .y = 0, .char_flags = 0x40e9, .ext = 2 },
    .{ .x = 0, .y = 16, .char_flags = 0x00eb, .ext = 2 },
    .{ .x = 16, .y = 16, .char_flags = 0x40eb, .ext = 2 },
    .{ .x = 0, .y = 32, .char_flags = 0x00ed, .ext = 2 },
    .{ .x = 16, .y = 32, .char_flags = 0x40ed, .ext = 2 },
};
pub const kLeever_EmergeGfx: [16]u8 = .{ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 2, 1, 2, 1, 0, 0 };
pub const kLeever_AttackGfx: [4]u8 = .{ 9, 10, 11, 12 };
pub const kLeever_AttackSpd: [2]u8 = .{ 12, 8 };
pub const kLeever_SubmergeGfx: [16]u8 = .{ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 2, 1, 2, 1, 0, 0 };
pub const kLeever_Draw_Num: [14]u8 = .{ 1, 1, 1, 3, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1 };
pub const kLeever_Draw_X: [56]i8 = .{
    2, 6, 6, 6, 0, 8, 8, 8, 0, 8, 8, 8, 0, 8, 0, 8,
    0, 8, 0, 8, 0, 0, 0, 8, 0, 0, 0, 8, 0, 0, 0, 8,
    0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
};
pub const kLeever_Draw_Y: [56]i8 = .{
    8,  8,  8,  8, 8, 8,  8,  8, 8, 8,  8,  8, 5, 5,  8,  8,
    5,  5,  8,  8, 2, 2,  8,  8, 1, 1,  8,  8, 0, 0,  8,  8,
    -1, -1, 8,  8, 8, -2, -2, 0, 8, -2, -2, 0, 8, -2, -2, 0,
    8,  -2, -2, 0, 8, -2, -2, 0,
};
pub const kLeever_Draw_Char: [56]u8 = .{
    0x28, 0x28, 0x28, 0x28, 0x28, 0x28, 0x28, 0x28, 0x38, 0x38, 0x38, 0x38, 8,    9, 0x28, 0x28,
    8,    9,    0xd9, 0xd9, 8,    8,    0xd8, 0xd8, 8,    8,    0xda, 0xda, 6,    6, 0xd9, 0xd9,
    0x26, 0x26, 0xd8, 0xd8, 0x6c, 6,    6,    0,    0x6c, 0x26, 0x26, 0,    0x6c, 6, 6,    0,
    0x6c, 0x26, 0x26, 0,    0x6c, 8,    8,    0,
};
pub const kLeever_Draw_Flags: [56]u8 = .{
    1, 0x41, 0x41, 0x41, 1, 0x41, 0x41, 0x41, 1, 0x41, 0x41, 0x41, 1, 1, 1, 0x41,
    1, 1,    0,    0x40, 1, 1,    0,    0x40, 1, 1,    0,    0x40, 1, 1, 0, 0x40,
    0, 1,    0,    0x40, 6, 0x41, 0x41, 0,    6, 0x41, 0x41, 0,    6, 1, 1, 0,
    6, 1,    1,    0,    6, 1,    1,    0,
};
pub const kLeever_Draw_Big: [56]u8 = .{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0,
    2, 2, 0, 0, 2, 2, 2, 0, 2, 2, 2, 0, 2, 2, 2, 0,
    2, 2, 2, 0, 2, 2, 2, 0,
};
pub const kOctorock_Tab0: [20]u8 = .{
    0, 2, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 1, 1, 0,
};
pub const kOctorock_Tab1: [10]u8 = .{ 2, 2, 2, 2, 2, 2, 2, 2, 1, 0 };
pub const kOctorock_NextDir: [4]u8 = .{ 2, 3, 1, 0 };
pub const kOctorock_Dir: [4]u8 = .{ 3, 2, 0, 1 };
pub const kOctorock_Xvel: [4]i8 = .{ 24, -24, 0, 0 };
pub const kOctorock_Yvel: [4]i8 = .{ 0, 0, 24, -24 };
pub const kOctorock_OamFlags: [4]u8 = .{ 0x40, 0, 0, 0 };
pub const kOctorock_Spit_X: [4]i8 = .{ 12, -12, 0, 0 };
pub const kOctorock_Spit_Y: [4]i8 = .{ 4, 4, 12, -12 };
pub const kOctorock_Spit_Xvel: [4]i8 = .{ 44, -44, 0, 0 };
pub const kOctorock_Spit_Yvel: [4]i8 = .{ 0, 0, 44, -44 };
pub const kOctorock_Draw_X: [9]i8 = .{ 8, 0, 4, 8, 0, 4, 9, -1, 4 };
pub const kOctorock_Draw_Y: [9]i8 = .{ 6, 6, 9, 6, 6, 9, 6, 6, 9 };
pub const kOctorock_Draw_Char: [9]u8 = .{ 0xbb, 0xbb, 0xba, 0xab, 0xab, 0xaa, 0xa9, 0xa9, 0xb9 };
pub const kOctorock_Draw_Flags: [9]u8 = .{ 0x65, 0x25, 0x25, 0x65, 0x25, 0x25, 0x65, 0x25, 0x25 };
pub const kOctostone_Draw_X: [16]i8 = .{ 0, 8, 0, 8, -8, 16, -8, 16, -12, 20, -12, 20, -14, 22, -14, 22 };
pub const kOctostone_Draw_Y: [16]i8 = .{ 0, 0, 8, 8, -8, -8, 16, 16, -12, -12, 20, 20, -14, -14, 22, 22 };
pub const kOctostone_Draw_Flags: [16]u8 = .{ 0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0 };
pub const kSprite_Octoballoon_Z: [8]u8 = .{ 16, 17, 18, 19, 20, 19, 18, 17 };
pub const kOctoballoon_Draw_X: [12]i8 = .{ -4, 4, -4, 4, -8, 8, -8, 8, -4, 4, -4, 4 };
pub const kOctoballoon_Draw_Y: [12]i8 = .{ -4, -4, 4, 4, -8, -8, 8, 8, -4, -4, 4, 4 };
pub const kOctoballoon_Draw_Char: [12]u8 = .{ 0x8c, 0x8c, 0x9c, 0x9c, 0x86, 0x86, 0x86, 0x86, 0x86, 0x86, 0x86, 0x86 };
pub const kOctoballoon_Draw_Flags: [12]u8 = .{ 0, 0x40, 0, 0x40, 0, 0x40, 0x80, 0xc0, 0, 0x40, 0x80, 0xc0 };
pub const kOctoballoon_Spawn_Xv: [6]i8 = .{ 16, 11, -11, -16, -11, 11 };
pub const kOctoballoon_Spawn_Yv: [6]i8 = .{ 0, 11, 11, 0, -11, -11 };
pub const kBuzzBlob_Gfx: [4]u8 = .{ 0, 1, 0, 2 };
pub const kBuzzBlob_ObjPrio: [4]u8 = .{ 10, 2, 8, 2 };
pub const kBuzzBlob_Xvel: [8]i8 = .{ 3, 2, -2, -3, -2, 2, 0, 0 };
pub const kBuzzBlob_Yvel: [8]i8 = .{ 0, 2, 2, 0, -2, -2, 0, 0 };
pub const kBuzzBlob_Delay: [8]u8 = .{ 48, 48, 48, 48, 48, 48, 64, 64 };
pub const kBuzzBlob_DrawX: [3]u16 = .{ 0, 8, 0 };
pub const kBuzzBlob_DrawY: [3]i16 = .{ -8, -8, 0 };
pub const kBuzzBlob_DrawChar: [18]u8 = .{ 0xf0, 0xf0, 0xe1, 0, 0, 0xce, 0, 0, 0xce, 0xe3, 0xe3, 0xca, 0xe4, 0xe5, 0xcc, 0xe5, 0xe4, 0xcc };
pub const kBuzzBlob_DrawFlags: [18]u8 = .{ 0, 0x40, 0, 0, 0, 0, 0, 0, 0x40, 0, 0x40, 0, 0, 0, 0, 0x40, 0x40, 0x40 };
pub const kBuzzBlob_DrawExt: [3]u8 = .{ 0, 0, 2 };
pub const kStalfosHead_OamFlags: [4]u8 = .{ 0, 0, 0, 0x40 };
pub const kStalfosHead_Gfx: [4]u8 = .{ 0, 1, 2, 1 };
pub const kSpawnMadderBolts_Xvel: [4]i8 = .{ -8, -4, 4, 8 };
pub const kSpawnMadderBolts_St2: [4]i8 = .{ 0, 0x11, 0x22, 0x33 };
pub const kCrazyVillageSoldier_X: [3]u16 = .{ 0x120, 0x340, 0x2e0 };
pub const kCrazyVillageSoldier_Y: [3]u16 = .{ 0x100, 0x3b0, 0x160 };
pub const kBabusu_Dmd: [40]DrawMultipleData = .{
    .{ .x = 0, .y = 4, .char_flags = 0x4380, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x4380, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x43b6, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x43b6, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x43b7, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x0380, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x4380, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x03b6, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x03b7, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x03b7, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x0380, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x0380, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x8380, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x8380, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x83b6, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x83b6, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x83b7, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x0380, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x8380, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x03b6, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x03b7, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x03b7, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x0380, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x0380, .ext = 0 },
    .{ .x = 0, .y = -8, .char_flags = 0x0a4e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a5e, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4a4e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4a5e, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x0a6c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a6b, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x8a6c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x8a6b, .ext = 2 },
    .{ .x = 0, .y = 8, .char_flags = 0x8a4e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x8a5e, .ext = 2 },
    .{ .x = 0, .y = 8, .char_flags = 0xca4e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0xca5e, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x4a6c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4a6b, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0xca6c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0xca6b, .ext = 2 },
};
pub const kWizzrobe_Dmd: [24]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x00b2, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x00b3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0088, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00b2, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x00b3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00b2, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x00b3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00b2, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x00b3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00b2, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x00b3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x408c, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00b2, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x00b3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x408a, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00b2, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x00b3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00b2, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x00b3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x008e, .ext = 2 },
};
pub const kWizzbeam_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = -4, .char_flags = 0x00c5, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x80c5, .ext = 0 },
    .{ .x = 0, .y = -4, .char_flags = 0x40c5, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0xc0c5, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x40d2, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x00d2, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0xc0d2, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x80d2, .ext = 0 },
};
pub const kFreezor_Dmd0: [28]DrawMultipleData = .{
    .{ .x = -8, .y = 0, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = 0, .y = 11, .char_flags = 0x00ab, .ext = 0 },
    .{ .x = 8, .y = 11, .char_flags = 0x40ab, .ext = 0 },
    .{ .x = -8, .y = 0, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40a8, .ext = 2 },
    .{ .x = 0, .y = 11, .char_flags = 0x00ba, .ext = 0 },
    .{ .x = 8, .y = 11, .char_flags = 0x00bb, .ext = 0 },
    .{ .x = -8, .y = 0, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = 0, .y = 11, .char_flags = 0x40bb, .ext = 0 },
    .{ .x = 8, .y = 11, .char_flags = 0x40ba, .ext = 0 },
    .{ .x = 0, .y = 2, .char_flags = 0x00ae, .ext = 0 },
    .{ .x = 8, .y = 2, .char_flags = 0x40ae, .ext = 0 },
    .{ .x = 0, .y = 10, .char_flags = 0x00be, .ext = 0 },
    .{ .x = 8, .y = 10, .char_flags = 0x40be, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x00af, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x40af, .ext = 0 },
    .{ .x = 0, .y = 12, .char_flags = 0x00bf, .ext = 0 },
    .{ .x = 8, .y = 12, .char_flags = 0x40bf, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x00aa, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x40aa, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x00aa, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x40aa, .ext = 0 },
};
pub const kFreezor_Dmd1: [8]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x00ae, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x40ae, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x00be, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x40be, .ext = 0 },
    .{ .x = -2, .y = 0, .char_flags = 0x00ae, .ext = 0 },
    .{ .x = 10, .y = 0, .char_flags = 0x40ae, .ext = 0 },
    .{ .x = -2, .y = 8, .char_flags = 0x00be, .ext = 0 },
    .{ .x = 10, .y = 8, .char_flags = 0x40be, .ext = 0 },
};
pub const kZazak_Char: [8]u8 = .{ 0x82, 0x82, 0x80, 0x84, 0x88, 0x88, 0x86, 0x84 };
pub const kZazak_Flags: [8]u8 = .{ 0x40, 0, 0, 0, 0x40, 0, 0, 0 };
pub const kZazak_Dmd: [24]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x0008, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00a1, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0008, .ext = 2 },
    .{ .x = -4, .y = 1, .char_flags = 0x40a1, .ext = 2 },
    .{ .x = 4, .y = 1, .char_flags = 0x40a0, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x000e, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x00a3, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x000e, .ext = 2 },
    .{ .x = -4, .y = 1, .char_flags = 0x40a4, .ext = 2 },
    .{ .x = 4, .y = 1, .char_flags = 0x40a3, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x000c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x000c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x400c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x400c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a8, .ext = 2 },
};
pub const kStalfos_Char: [4]u8 = .{ 2, 2, 0, 4 };
pub const kStalfos_Flags: [4]u8 = .{ 0x70, 0x30, 0x30, 0x30 };
pub const kStalfos_Dmd: [36]DrawMultipleData = .{
    .{ .x = 0, .y = -10, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0006, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0006, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x4006, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x4006, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0006, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0006, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x4006, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x4006, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0002, .ext = 2 },
    .{ .x = 5, .y = 5, .char_flags = 0x002e, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0024, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x4002, .ext = 2 },
    .{ .x = 3, .y = 5, .char_flags = 0x402e, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x4024, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x4002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x400e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 2, .y = -8, .char_flags = 0x4002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4008, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4008, .ext = 2 },
    .{ .x = -2, .y = -8, .char_flags = 0x0002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0008, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0008, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x0004, .ext = 2 },
};
pub const kFluteBoyFather_Dmd: [6]DrawMultipleData = .{
    .{ .x = 0, .y = -7, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0088, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0088, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0088, .ext = 2 },
};
pub const kBlindHideoutGuy_Dmd: [16]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x000c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00ca, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x000c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40ca, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x000c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00ca, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x000c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40ca, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00ca, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40ca, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x400e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00ca, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x400e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40ca, .ext = 2 },
};
pub const kSweepingLadyDmd: [4]DrawMultipleData = .{
    .{ .x = 0, .y = -7, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 0, .y = 5, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 0, .y = 4, .char_flags = 0x008c, .ext = 2 },
};
pub const kLumberJackMsg: [4]u16 = .{ 0x12c, 0x12d, 0x12e, 0x12d };
pub const kLumberJacks_X: [2]u8 = .{ 48, 52 };
pub const kLumberJacks_Y: [2]u8 = .{ 19, 20 };
pub const kLumberJacks_W: [2]u8 = .{ 98, 106 };
pub const kLumberJacks_H: [2]u8 = .{ 37, 40 };
pub const kLumberJacks_Dmd: [33]DrawMultipleData = .{
    .{ .x = -23, .y = 5, .char_flags = 0x02be, .ext = 0 },
    .{ .x = -15, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = -7, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 1, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 9, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 17, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 25, .y = 5, .char_flags = 0x42be, .ext = 0 },
    .{ .x = -32, .y = -8, .char_flags = 0x40a8, .ext = 2 },
    .{ .x = -32, .y = 4, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = 30, .y = -8, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = 31, .y = 4, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = -19, .y = 5, .char_flags = 0x02be, .ext = 0 },
    .{ .x = -11, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = -3, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 5, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 13, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 21, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 29, .y = 5, .char_flags = 0x42be, .ext = 0 },
    .{ .x = -31, .y = -8, .char_flags = 0x40a8, .ext = 2 },
    .{ .x = -32, .y = 4, .char_flags = 0x40a4, .ext = 2 },
    .{ .x = 31, .y = -8, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = 31, .y = 4, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = -19, .y = 5, .char_flags = 0x02be, .ext = 0 },
    .{ .x = -11, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = -3, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 5, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 13, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 21, .y = 5, .char_flags = 0x02bf, .ext = 0 },
    .{ .x = 29, .y = 5, .char_flags = 0x42be, .ext = 0 },
    .{ .x = -32, .y = -8, .char_flags = 0x400e, .ext = 2 },
    .{ .x = -32, .y = 4, .char_flags = 0x40a4, .ext = 2 },
    .{ .x = 32, .y = -8, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 31, .y = 4, .char_flags = 0x00a6, .ext = 2 },
};
pub const kFortuneTeller_Readings: [16]u8 = .{ 0xea, 0xeb, 0xec, 0xed, 0xee, 0xef, 0xf0, 0xf1, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd };
pub const kFortuneTeller_Dmd: [12]DrawMultipleData = .{
    .{ .x = 0, .y = -48, .char_flags = 0x000c, .ext = 2 },
    .{ .x = 0, .y = -32, .char_flags = 0x002c, .ext = 0 },
    .{ .x = 8, .y = -32, .char_flags = 0x402c, .ext = 0 },
    .{ .x = 0, .y = -48, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = -32, .char_flags = 0x002a, .ext = 0 },
    .{ .x = 8, .y = -32, .char_flags = 0x402a, .ext = 0 },
    .{ .x = -4, .y = -40, .char_flags = 0x0066, .ext = 2 },
    .{ .x = 4, .y = -40, .char_flags = 0x4066, .ext = 2 },
    .{ .x = -4, .y = -40, .char_flags = 0x0066, .ext = 2 },
    .{ .x = -4, .y = -40, .char_flags = 0x0068, .ext = 2 },
    .{ .x = 4, .y = -40, .char_flags = 0x4068, .ext = 2 },
    .{ .x = -4, .y = -40, .char_flags = 0x0068, .ext = 2 },
};
pub const kMazeGameGuy_Dmd: [16]DrawMultipleData = .{
    .{ .x = 0, .y = -10, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x4002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x4002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0020, .ext = 2 },
};
pub const kFluteBoy_Dmd: [16]DrawMultipleData = .{
    .{ .x = -1, .y = -1, .char_flags = 0x0abe, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0aa8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = -1, .y = -1, .char_flags = 0x0abe, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x0abf, .ext = 0 },
    .{ .x = 0, .y = -10, .char_flags = 0x0aa8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = -1, .y = -1, .char_flags = 0x0abe, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0aa8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = -1, .y = -1, .char_flags = 0x0abe, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x0abf, .ext = 0 },
    .{ .x = 0, .y = -10, .char_flags = 0x0aa8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0aaa, .ext = 2 },
};
pub const kFluteAardvark_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = -16, .char_flags = 0x06e6, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x06c8, .ext = 2 },
    .{ .x = 0, .y = -16, .char_flags = 0x06e6, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x06ca, .ext = 2 },
    .{ .x = 0, .y = -16, .char_flags = 0x06e8, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x06ca, .ext = 2 },
    .{ .x = 0, .y = -16, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00dc, .ext = 2 },
};
pub const kDustCloud_Dmd: [24]DrawMultipleData = .{
    .{ .x = 0, .y = -3, .char_flags = 0x008b, .ext = 0 },
    .{ .x = 3, .y = 0, .char_flags = 0x009b, .ext = 0 },
    .{ .x = -3, .y = 0, .char_flags = 0xc08b, .ext = 0 },
    .{ .x = 0, .y = 3, .char_flags = 0xc09b, .ext = 0 },
    .{ .x = 0, .y = -5, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 5, .y = 0, .char_flags = 0x008a, .ext = 2 },
    .{ .x = -5, .y = 0, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 0, .y = 5, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 7, .y = 0, .char_flags = 0x0086, .ext = 2 },
    .{ .x = -7, .y = 0, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = 7, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x8086, .ext = 2 },
    .{ .x = 9, .y = 0, .char_flags = 0x8086, .ext = 2 },
    .{ .x = -9, .y = 0, .char_flags = 0x8086, .ext = 2 },
    .{ .x = 0, .y = 9, .char_flags = 0x8086, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0xc086, .ext = 2 },
    .{ .x = 9, .y = 0, .char_flags = 0xc086, .ext = 2 },
    .{ .x = -9, .y = 0, .char_flags = 0xc086, .ext = 2 },
    .{ .x = 0, .y = 9, .char_flags = 0xc086, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x4086, .ext = 2 },
    .{ .x = 7, .y = 0, .char_flags = 0x4086, .ext = 2 },
    .{ .x = -7, .y = 0, .char_flags = 0x4086, .ext = 2 },
    .{ .x = 0, .y = 7, .char_flags = 0x4086, .ext = 2 },
};
pub const kMedallionTablet_Dmd: [20]DrawMultipleData = .{
    .{ .x = -8, .y = -16, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 8, .y = -16, .char_flags = 0x408c, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = -8, .y = -13, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 8, .y = -13, .char_flags = 0x408a, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x408a, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = -8, .y = -4, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 8, .y = -4, .char_flags = 0x408a, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40aa, .ext = 2 },
};
pub const kUncleDraw_Table: [48]DrawMultipleData = .{
    .{ .x = 0, .y = -10, .char_flags = 0x0e00, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c06, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0e00, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c06, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0e00, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c06, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0e02, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c06, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0e02, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c06, .ext = 2 },
    .{ .x = 0, .y = -10, .char_flags = 0x0e02, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c06, .ext = 2 },
    .{ .x = -7, .y = 2, .char_flags = 0x0d07, .ext = 2 },
    .{ .x = -7, .y = 2, .char_flags = 0x0d07, .ext = 2 },
    .{ .x = 10, .y = 12, .char_flags = 0x8d05, .ext = 0 },
    .{ .x = 10, .y = 4, .char_flags = 0x8d15, .ext = 0 },
    .{ .x = 0, .y = -10, .char_flags = 0x0e00, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c04, .ext = 2 },
    .{ .x = -7, .y = 1, .char_flags = 0x0d07, .ext = 2 },
    .{ .x = -7, .y = 1, .char_flags = 0x0d07, .ext = 2 },
    .{ .x = 10, .y = 13, .char_flags = 0x8d05, .ext = 0 },
    .{ .x = 10, .y = 5, .char_flags = 0x8d15, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x0e00, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x4c04, .ext = 2 },
    .{ .x = -7, .y = 8, .char_flags = 0x8d05, .ext = 0 },
    .{ .x = 1, .y = 8, .char_flags = 0x8d06, .ext = 0 },
    .{ .x = 0, .y = -10, .char_flags = 0x0e02, .ext = 2 },
    .{ .x = -6, .y = -1, .char_flags = 0x4d07, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c23, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0c23, .ext = 2 },
    .{ .x = -9, .y = 7, .char_flags = 0x8d05, .ext = 0 },
    .{ .x = -1, .y = 7, .char_flags = 0x8d06, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x0e02, .ext = 2 },
    .{ .x = -6, .y = 0, .char_flags = 0x4d07, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x0c25, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x0c25, .ext = 2 },
    .{ .x = -10, .y = -17, .char_flags = 0x0d07, .ext = 2 },
    .{ .x = 15, .y = -12, .char_flags = 0x8d15, .ext = 0 },
    .{ .x = 15, .y = -4, .char_flags = 0x8d05, .ext = 0 },
    .{ .x = 0, .y = -28, .char_flags = 0x0e08, .ext = 2 },
    .{ .x = -8, .y = -19, .char_flags = 0x0c20, .ext = 2 },
    .{ .x = 8, .y = -19, .char_flags = 0x4c20, .ext = 2 },
    .{ .x = 0, .y = -28, .char_flags = 0x0e08, .ext = 2 },
    .{ .x = 0, .y = -28, .char_flags = 0x0e08, .ext = 2 },
    .{ .x = -8, .y = -19, .char_flags = 0x0c20, .ext = 2 },
    .{ .x = 8, .y = -19, .char_flags = 0x4c20, .ext = 2 },
    .{ .x = -8, .y = -19, .char_flags = 0x0c20, .ext = 2 },
    .{ .x = 8, .y = -19, .char_flags = 0x4c20, .ext = 2 },
};
pub const kUncleDraw_Dma3: [8]u8 = .{ 8, 8, 0, 0, 6, 6, 0, 0 };
pub const kUncleDraw_Dma4: [8]u8 = .{ 0, 0, 0, 0, 4, 4, 0, 0x8b };
pub const kBugNetKid_Dmd: [18]DrawMultipleData = .{
    .{ .x = 4, .y = 0, .char_flags = 0x0027, .ext = 0 },
    .{ .x = 0, .y = -5, .char_flags = 0x000e, .ext = 2 },
    .{ .x = -8, .y = 6, .char_flags = 0x040a, .ext = 2 },
    .{ .x = 8, .y = 6, .char_flags = 0x440a, .ext = 2 },
    .{ .x = -8, .y = 14, .char_flags = 0x840a, .ext = 2 },
    .{ .x = 8, .y = 14, .char_flags = 0xc40a, .ext = 2 },
    .{ .x = 0, .y = -5, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 0, .y = -5, .char_flags = 0x000e, .ext = 2 },
    .{ .x = -8, .y = 6, .char_flags = 0x040a, .ext = 2 },
    .{ .x = 8, .y = 6, .char_flags = 0x440a, .ext = 2 },
    .{ .x = -8, .y = 14, .char_flags = 0x840a, .ext = 2 },
    .{ .x = 8, .y = 14, .char_flags = 0xc40a, .ext = 2 },
    .{ .x = 0, .y = -5, .char_flags = 0x002e, .ext = 2 },
    .{ .x = 0, .y = -5, .char_flags = 0x002e, .ext = 2 },
    .{ .x = -8, .y = 7, .char_flags = 0x040a, .ext = 2 },
    .{ .x = 8, .y = 7, .char_flags = 0x440a, .ext = 2 },
    .{ .x = -8, .y = 14, .char_flags = 0x840a, .ext = 2 },
    .{ .x = 8, .y = 14, .char_flags = 0xc40a, .ext = 2 },
};
pub const kBomber_Dmd: [22]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x40c6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40c6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40c4, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40c4, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00c6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00c6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00c4, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00c4, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00c0, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40c0, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00c2, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40c2, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00e0, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40e0, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00e2, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40e2, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00e4, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40e4, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40e6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40e6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e6, .ext = 2 },
};
pub const kBomberPellet_Dmd: [15]DrawMultipleData = .{
    .{ .x = -11, .y = 0, .char_flags = 0x019b, .ext = 0 },
    .{ .x = 0, .y = -8, .char_flags = 0xc19b, .ext = 0 },
    .{ .x = 6, .y = 6, .char_flags = 0x419b, .ext = 0 },
    .{ .x = -15, .y = -6, .char_flags = 0x018a, .ext = 2 },
    .{ .x = -4, .y = -14, .char_flags = 0x018a, .ext = 2 },
    .{ .x = 2, .y = 0, .char_flags = 0x018a, .ext = 2 },
    .{ .x = -15, .y = -6, .char_flags = 0x0186, .ext = 2 },
    .{ .x = -4, .y = -14, .char_flags = 0x0186, .ext = 2 },
    .{ .x = 2, .y = 0, .char_flags = 0x0186, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x0186, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x0186, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x0186, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x01aa, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x01aa, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x01aa, .ext = 2 },
};
pub const kPikit_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x00c8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00c8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00ca, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00ca, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40cc, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00ce, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40ce, .ext = 2 },
};
pub const kPikit_TongueMult: [4]u8 = .{ 0x33, 0x66, 0x99, 0xcc };
pub const kPikit_Draw_Char: [8]u8 = .{ 0xee, 0xfd, 0xed, 0xfd, 0xee, 0xfd, 0xed, 0xfd };
pub const kPikit_Draw_Flags: [8]u8 = .{ 0, 0, 0, 0x40, 0x40, 0xc0, 0x80, 0x80 };
pub const kPikit_DrawGrabbedItem_X: [20]i8 = .{
    -4, 4, -4, 4, 0, 8, 0, 8, 0, 8, 0, 8, 0, 8, 0, 8, -4, 4, -4, 4,
};
pub const kPikit_DrawGrabbedItem_Y: [20]i8 = .{
    -4, -4, 4, 4, -4, -4, 4, 4, -4, -4, 4, 4, -4, -4, 4, 4, -4, -4, 4, 4,
};
pub const kPikit_DrawGrabbedItem_Char: [20]u8 = .{
    0x6e, 0x6f, 0x7e, 0x7f, 0x63, 0x7c, 0x73, 0x7c, 0xb, 0x7c, 0x1b, 0x7c, 0xec, 0xf9, 0xfc, 0xf9,
    0xea, 0xeb, 0xfa, 0xfb,
};
pub const kPikit_DrawGrabbedItem_Flags: [5]u8 = .{ 0x24, 0x24, 0x28, 0x29, 0x2f };
pub const kKholdstare_Dmd: [16]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x0082, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = -7, .y = -7, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 7, .y = -7, .char_flags = 0x0082, .ext = 2 },
    .{ .x = -7, .y = 7, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 7, .y = 7, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = -7, .y = -7, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 7, .y = -7, .char_flags = 0x0086, .ext = 2 },
    .{ .x = -7, .y = 7, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = 7, .y = 7, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x0086, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x00a6, .ext = 2 },
};
pub const kKholdstare_Draw_X: [16]i8 = .{ 8, 7, 4, 2, 0, -2, -4, -7, -8, -7, -4, -2, 0, 2, 4, 7 };
pub const kKholdstare_Draw_Y: [16]i8 = .{ 0, 2, 4, 7, 8, 7, 4, 2, 0, -2, -4, -7, -8, -7, -4, -2 };
pub const kKholdstare_Draw_Char: [16]u8 = .{ 0xac, 0xac, 0xaa, 0x8c, 0x8c, 0x8c, 0xaa, 0xac, 0xac, 0xaa, 0xaa, 0x8c, 0x8c, 0x8c, 0xaa, 0xac };
pub const kKholdstare_Draw_Flags: [16]u8 = .{ 0x40, 0x40, 0x40, 0, 0, 0, 0, 0, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0xc0, 0xc0 };
pub const kArcheryGameGuy_Draw_X: [15]i8 = .{ 0, 0, 0, 0, 0, -5, 0, -1, -1, 0, 0, 0, 0, 1, 1 };
pub const kArcheryGameGuy_Draw_Y: [15]i8 = .{ 0, -10, -10, 0, -10, -3, 0, -10, -10, 0, -10, -10, 0, -10, -10 };
pub const kArcheryGameGuy_Draw_Char: [15]u8 = .{ 0x26, 6, 6, 8, 6, 0x3a, 0x26, 6, 6, 0x26, 6, 6, 0x26, 6, 6 };
pub const kArcheryGameGuy_Draw_Flags: [15]u8 = .{ 8, 6, 6, 8, 6, 8, 8, 6, 6, 8, 6, 6, 8, 6, 6 };
pub const kArcheryGameGuy_Draw_Big: [15]u8 = .{ 2, 2, 2, 2, 2, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2 };
pub const kRetreatBat_Xpos: [4]u16 = .{ 0x7dc, 0x7f0, 0x820, 0x818 };
pub const kRetreatBat_Ypos: [4]u16 = .{ 0x62e, 0x636, 0x630, 0x5e0 };
pub const kRetreatBat_Delay: [5]u8 = .{ 4, 3, 4, 6, 0 };
pub const kRetreatBat_Oams: [8]OamEntSigned = .{
    .{ .x = 104, .y = -105, .charnum = 0x57, .flags = 0x01 },
    .{ .x = 120, .y = -105, .charnum = 0x57, .flags = 0x01 },
    .{ .x = -120, .y = -105, .charnum = 0x57, .flags = 0x01 },
    .{ .x = 104, .y = -89, .charnum = 0x57, .flags = 0x01 },
    .{ .x = 120, .y = -89, .charnum = 0x57, .flags = 0x01 },
    .{ .x = -120, .y = -89, .charnum = 0x57, .flags = 0x01 },
    .{ .x = 101, .y = -112, .charnum = 0x57, .flags = 0x01 },
    .{ .x = -117, .y = -112, .charnum = 0x57, .flags = 0x01 },
};
pub const kPyramidDebris_X: [30]i8 = .{
    -8, 0,  8,  16, 24, 32, -8, 0,  8,  16, 24, 32, -8, 0,  8, 16,
    24, 32, -8, 0,  8,  16, 24, 32, -8, 0,  8,  16, 24, 32,
};
pub const kPyramidDebris_Y: [30]i8 = .{
    0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x28, 0x28, 0x28, 0x28, 0x28, 0x28, 0x20, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10,
};
pub const kPyramidDebris_Xvel: [30]i8 = .{
    -30, -25, -8,  8,   25,  30, -50, -45, -20, 20,  45,  50, -50, -35, -25, 25,
    35,  50,  -45, -50, -60, 60, 50,  45,  -30, -35, -40, 40, 35,  30,
};
pub const kPyramidDebris_Yvel: [30]i8 = .{
    2,  5,  10,  10,  5,   2,   5,   20,  30,  30,  20,  5,   10,  30,  40, 40,
    30, 10, -20, -40, -60, -60, -40, -20, -10, -20, -40, -40, -20, -10,
};
pub const kRetreatBat_Dmds: [18]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x044b, .ext = 0 },
    .{ .x = 5, .y = -4, .char_flags = 0x045b, .ext = 0 },
    .{ .x = -2, .y = -4, .char_flags = 0x0464, .ext = 2 },
    .{ .x = -2, .y = -4, .char_flags = 0x0449, .ext = 2 },
    .{ .x = -8, .y = -9, .char_flags = 0x046c, .ext = 2 },
    .{ .x = 8, .y = -9, .char_flags = 0x446c, .ext = 2 },
    .{ .x = -8, .y = -7, .char_flags = 0x044c, .ext = 2 },
    .{ .x = 8, .y = -7, .char_flags = 0x444c, .ext = 2 },
    .{ .x = -8, .y = -9, .char_flags = 0x0444, .ext = 2 },
    .{ .x = 8, .y = -9, .char_flags = 0x4444, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0462, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4462, .ext = 2 },
    .{ .x = -8, .y = -7, .char_flags = 0x0460, .ext = 2 },
    .{ .x = 8, .y = -7, .char_flags = 0x4460, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x044e, .ext = 2 },
    .{ .x = 16, .y = 0, .char_flags = 0x444e, .ext = 2 },
    .{ .x = 0, .y = 16, .char_flags = 0x046e, .ext = 2 },
    .{ .x = 16, .y = 16, .char_flags = 0x446e, .ext = 2 },
};
pub const kOffs: [20]u8 = .{ 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 6, 6, 8, 10, 12, 10, 14, 14, 14, 14 };
pub const kCount: [20]u8 = .{
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    4,
    4,
    4,
    4,
};
pub const kDrinkingGuy_Dmd: [6]DrawMultipleData = .{
    .{ .x = 8, .y = 2, .char_flags = 0x00ae, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x0822, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0006, .ext = 2 },
    .{ .x = 7, .y = 0, .char_flags = 0x00af, .ext = 0 },
    .{ .x = 0, .y = -9, .char_flags = 0x0822, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0006, .ext = 2 },
};
pub const kLadyDmd: [16]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x00e0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e8, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x00e0, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x40e8, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00c0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00c2, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x00c0, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x40c2, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x00e2, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e4, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x00e2, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x00e6, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x40e2, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40e4, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x40e2, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x40e6, .ext = 2 },
};
pub const kLanmolaShrapnel_Yvel: [8]i8 = .{ 28, -28, 28, -28, 0, 36, 0, -36 };
pub const kLanmolaShrapnel_Xvel: [8]i8 = .{ -28, -28, 28, 28, -36, 0, 36, 0 };
pub const kCukeman_Dmd: [18]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x01f3, .ext = 0 },
    .{ .x = 7, .y = 0, .char_flags = 0x41f3, .ext = 0 },
    .{ .x = 4, .y = 7, .char_flags = 0x07e0, .ext = 0 },
    .{ .x = -1, .y = 2, .char_flags = 0x01f3, .ext = 0 },
    .{ .x = 6, .y = 1, .char_flags = 0x41f3, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x07e0, .ext = 0 },
    .{ .x = 1, .y = 1, .char_flags = 0x01f3, .ext = 0 },
    .{ .x = 8, .y = 2, .char_flags = 0x41f3, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x07e0, .ext = 0 },
    .{ .x = -2, .y = 0, .char_flags = 0x01f3, .ext = 0 },
    .{ .x = 10, .y = 0, .char_flags = 0x41f3, .ext = 0 },
    .{ .x = 4, .y = 7, .char_flags = 0x07e0, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x01f3, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x41f3, .ext = 0 },
    .{ .x = 4, .y = 6, .char_flags = 0x07e0, .ext = 0 },
    .{ .x = -5, .y = 0, .char_flags = 0x01f3, .ext = 0 },
    .{ .x = 16, .y = 0, .char_flags = 0x41f3, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x07e0, .ext = 0 },
};
pub const kMothula_Dmd: [24]DrawMultipleData = .{
    .{ .x = -24, .y = -8, .char_flags = 0x0080, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0082, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4082, .ext = 2 },
    .{ .x = 24, .y = -8, .char_flags = 0x4080, .ext = 2 },
    .{ .x = -24, .y = 8, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x40a2, .ext = 2 },
    .{ .x = 24, .y = 8, .char_flags = 0x40a0, .ext = 2 },
    .{ .x = -24, .y = -8, .char_flags = 0x0084, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4086, .ext = 2 },
    .{ .x = 24, .y = -8, .char_flags = 0x4084, .ext = 2 },
    .{ .x = -24, .y = 8, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = 24, .y = 8, .char_flags = 0x40a4, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0088, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0088, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4088, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4088, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x40a8, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x40a8, .ext = 2 },
};
pub const kMothula_Draw_X: [27]i8 = .{
    0,  3,  6, 9, 12, -3, -6, -9, -12, 0,  2,  4, 6, 8, -2, -4,
    -6, -8, 0, 1, 2,  3,  4,  -1, -2,  -3, -4,
};
pub const kBottleVendor_GoodBeeX: [5]i8 = .{ -6, -3, 0, 4, 7 };
pub const kBottleVendor_GoodBeeY: [5]i8 = .{ 11, 14, 16, 14, 11 };
pub const kLandMine_OamFlags: [4]u8 = .{ 4, 2, 8, 2 };
pub const kLandmine_Dmd: [2]DrawMultipleData = .{
    .{ .x = 0, .y = 4, .char_flags = 0x0070, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x4070, .ext = 0 },
};
pub const kStal_Gfx: [5]u8 = .{ 2, 2, 1, 0, 1 };
pub const kStal_Dmd: [6]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x0044, .ext = 2 },
    .{ .x = 4, .y = 11, .char_flags = 0x0070, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0044, .ext = 2 },
    .{ .x = 4, .y = 12, .char_flags = 0x0070, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0044, .ext = 2 },
    .{ .x = 4, .y = 13, .char_flags = 0x0070, .ext = 0 },
};
pub const kFish_Xvel: [8]i8 = .{ 0, 12, 16, 12, 0, -12, -16, -12 };
pub const kFish_Yvel: [8]i8 = .{ -16, -12, 0, 12, 16, 12, 0, -12 };
pub const kFish_Tab1: [2]u8 = .{ 2, 0 };
pub const kFish_Gfx: [3]u8 = .{ 1, 5, 3 };
pub const kFish_Gfx2: [17]u8 = .{ 5, 5, 6, 6, 5, 5, 4, 4, 3, 7, 7, 8, 8, 7, 7, 8, 8 };
pub const kFish_Dmd: [16]DrawMultipleData = .{
    .{ .x = -4, .y = 8, .char_flags = 0x045e, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x045f, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0x845e, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x845f, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0x445f, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x445e, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0xc45f, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0xc45e, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0461, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x0471, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x4461, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x4471, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x8471, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x8461, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0xc471, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0xc461, .ext = 0 },
};
pub const kFish_Dmd2: [9]DrawMultipleData = .{
    .{ .x = -2, .y = 11, .char_flags = 0x0438, .ext = 0 },
    .{ .x = 0, .y = 11, .char_flags = 0x0438, .ext = 0 },
    .{ .x = 2, .y = 11, .char_flags = 0x0438, .ext = 0 },
    .{ .x = -1, .y = 11, .char_flags = 0x0438, .ext = 0 },
    .{ .x = 0, .y = 11, .char_flags = 0x0438, .ext = 0 },
    .{ .x = 1, .y = 11, .char_flags = 0x0438, .ext = 0 },
    .{ .x = 0, .y = 11, .char_flags = 0x0438, .ext = 0 },
    .{ .x = 0, .y = 11, .char_flags = 0x0438, .ext = 0 },
    .{ .x = 0, .y = 11, .char_flags = 0x0438, .ext = 0 },
};
pub const kChimneySmoke_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x0086, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x0087, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x0096, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x0097, .ext = 0 },
    .{ .x = 1, .y = 1, .char_flags = 0x0086, .ext = 0 },
    .{ .x = 7, .y = 1, .char_flags = 0x0087, .ext = 0 },
    .{ .x = 1, .y = 7, .char_flags = 0x0096, .ext = 0 },
    .{ .x = 7, .y = 7, .char_flags = 0x0097, .ext = 0 },
};
pub const kRabbitBeam_Gfx: [6]u8 = .{ 0xd7, 0xd7, 0xd7, 0x91, 0x91, 0x91 };
pub const kLynel_AttackGfx: [4]i8 = .{ 5, 2, 8, 10 };
pub const kLynel_Gfx: [8]i8 = .{ 3, 0, 6, 9, 4, 1, 7, 10 };
pub const kLynel_Xtarget: [4]i8 = .{ -96, 96, 0, 0 };
pub const kLynel_Ytarget: [4]i8 = .{ 8, 8, -96, 112 };
pub const kLynel_Dmd: [33]DrawMultipleData = .{
    .{ .x = -5, .y = -11, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x00e4, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00e5, .ext = 2 },
    .{ .x = -5, .y = -10, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x00e7, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00e8, .ext = 2 },
    .{ .x = -5, .y = -11, .char_flags = 0x00c8, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x00e4, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00e5, .ext = 2 },
    .{ .x = 5, .y = -11, .char_flags = 0x40cc, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x40e5, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x40e4, .ext = 2 },
    .{ .x = 5, .y = -10, .char_flags = 0x40cc, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x40e8, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x40e7, .ext = 2 },
    .{ .x = 5, .y = -11, .char_flags = 0x40c8, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x40e8, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x40e7, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x00ce, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x00ea, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00eb, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x00ce, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x40eb, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x40ea, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x00ca, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x40eb, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00eb, .ext = 2 },
    .{ .x = 0, .y = -14, .char_flags = 0x00c6, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x00ed, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00ee, .ext = 2 },
    .{ .x = 0, .y = -14, .char_flags = 0x00c6, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x40ee, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x40ed, .ext = 2 },
};
pub const kGanonBat_Gfx: [4]u8 = .{ 0, 1, 2, 1 };
pub const kGanonBat_TargetXvel: [2]i8 = .{ 32, -32 };
pub const kGanonBat_TargetYvel: [2]i8 = .{ 16, -16 };
pub const kGanonBat_Dmd: [6]DrawMultipleData = .{
    .{ .x = -8, .y = 0, .char_flags = 0x0560, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4560, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x0562, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4562, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x0544, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4544, .ext = 2 },
};
pub const kPhantomGanon_Dmd: [16]DrawMultipleData = .{
    .{ .x = -16, .y = -8, .char_flags = 0x0d46, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0d47, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4d47, .ext = 2 },
    .{ .x = 16, .y = -8, .char_flags = 0x4d46, .ext = 2 },
    .{ .x = -16, .y = 8, .char_flags = 0x0d69, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x0d6a, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x4d6a, .ext = 2 },
    .{ .x = 16, .y = 8, .char_flags = 0x4d69, .ext = 2 },
    .{ .x = -16, .y = -8, .char_flags = 0x0d46, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0d47, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4d47, .ext = 2 },
    .{ .x = 16, .y = -8, .char_flags = 0x4d46, .ext = 2 },
    .{ .x = -16, .y = 8, .char_flags = 0x0d66, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x0d67, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x4d67, .ext = 2 },
    .{ .x = 16, .y = 8, .char_flags = 0x4d66, .ext = 2 },
};
pub const kFirebat_Gfx2: [9]u8 = .{ 4, 4, 4, 3, 3, 3, 2, 2, 2 };
pub const kFirebat_X: [2]i8 = .{ 20, -18 };
pub const kFirebat_Y: [2]i8 = .{ -20, -20 };
pub const kFirebat_Gfx: [4]u8 = .{ 4, 5, 6, 5 };
pub const kFirebat_Draw_X: [2]i8 = .{ -8, 8 };
pub const kFirebat_Draw_Char: [7]u8 = .{ 0x88, 0x88, 0x8a, 0x8c, 0x68, 0xaa, 0xa8 };
pub const kFirebat_Draw_Flags: [14]u8 = .{ 0, 0xc0, 0x80, 0x40, 0, 0x40, 0, 0x40, 0, 0x40, 0, 0x40, 0, 0x40 };
pub const kGanonMath_X: [16]i8 = .{ 0, 16, 24, 28, 32, 28, 24, 16, 0, -16, -24, -28, -32, -28, -24, -16 };
pub const kGanonMath_Y: [16]i8 = .{ 32, 28, 24, 16, 0, -16, -24, -28, -32, -28, -24, -16, 0, 16, 24, 28 };
pub const kGanon_GfxB: [2]u8 = .{ 16, 10 };
pub const kGanon_HeadDir0: [2]u8 = .{ 2, 0 };
pub const kGanon_Gfx1: [2]u8 = .{ 2, 10 };
pub const kGanon_X1: [2]i8 = .{ 24, -16 };
pub const kGanon_Y1: [2]i8 = .{ 4, 4 };
pub const kGanon_Xvel1: [16]i8 = .{ 32, 28, 24, 16, 0, -16, -24, -28, -32, -28, -24, -16, 0, 16, 24, 28 };
pub const kGanon_Yvel1: [16]i8 = .{ 0, 16, 24, 28, 32, 28, 24, 16, 0, -16, -24, -28, -32, -28, -24, -16 };
pub const kGanon_Gfx2_0: [2]u8 = .{ 0, 8 };
pub const kGanon_Gfx5: [2]u8 = .{ 2, 10 };
pub const kGanon_Tab2: [16]i8 = .{ 0, 0, 0, 0, -1, -1, -2, -1, 0, 0, 0, 0, 1, 2, 1, 1 };
pub const kGanon_Delay8: [8]u8 = .{ 0x10, 0x30, 0x50, 0x70, 0x90, 0xb0, 0xd0, 0xbd };
pub const kGanon_Gfx12: [6]u8 = .{ 5, 6, 7, 13, 14, 10 };
pub const kGanon_Gfx15: [2]u8 = .{ 6, 14 };
pub const kGanon_Gfx16: [2]u8 = .{ 2, 10 };
pub const kGanon_Gfx17b: [2]u8 = .{ 6, 14 };
pub const kGanon_Gfx17: [2]u8 = .{ 7, 10 };
pub const kGanon_Gfx19: [2]u8 = .{ 5, 13 };
pub const kGanon_Ov_Type: [4]u8 = .{ 12, 13, 14, 15 };
pub const kGanon_Ov_X: [4]u8 = .{ 0x18, 0xd8, 0xd8, 0x18 };
pub const kGanon_Ov_Y: [4]u8 = .{ 0x28, 0x28, 0xd8, 0xd8 };
pub const kGanon_Gfx16_Y: [2]i8 = .{ 0, -16 };
pub const kGanon_GfxFunc2: [16]u8 = .{ 0, 0, 1, 1, 0, 0, 1, 1, 8, 8, 9, 9, 8, 8, 9, 9 };
pub const kGanon_G: [2]u8 = .{ 9, 10 };
pub const kGanon_Gfx: [2]u8 = .{ 2, 10 };
pub const kGanon_NextSubtype: [32]u8 = .{
    4, 5, 6, 7, 4, 5, 6, 7, 4, 5, 6, 7, 4, 5, 6, 7,
    0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
};
pub const kGanon_NextY: [8]u8 = .{ 0x40, 0x30, 0x30, 0x40, 0xb0, 0xc0, 0xc0, 0xb0 };
pub const kGanon_NextX: [8]u8 = .{ 0x30, 0x50, 0xa0, 0xc0, 0x40, 0x60, 0x90, 0xb0 };
pub const kGanon_HeadDir: [18]u8 = .{
    0, 0,  0, 1, 2, 2, 2, 1, 0, 0, 0, 1, 1, 1, 1, 1,
    0, 16,
};
pub const kGanon_SprOffs: [17]u8 = .{
    1, 1, 1, 1, 1, 1, 15, 1, 4, 4, 4, 4, 4, 4, 4, 15, 15,
};
pub const kGanon_Dmd: [2]DrawMultipleData = .{
    .{ .x = 16, .y = -3, .char_flags = 0x4c0a, .ext = 2 },
    .{ .x = 16, .y = 5, .char_flags = 0x4c1a, .ext = 2 },
};
pub const kTrident_Dmd: [50]DrawMultipleData = .{
    .{ .x = 10, .y = -10, .char_flags = 0x0864, .ext = 0 },
    .{ .x = 5, .y = -15, .char_flags = 0x0864, .ext = 0 },
    .{ .x = 0, .y = -20, .char_flags = 0x0864, .ext = 0 },
    .{ .x = -5, .y = -25, .char_flags = 0x0864, .ext = 0 },
    .{ .x = -18, .y = -38, .char_flags = 0x0844, .ext = 2 },
    .{ .x = 1, .y = -4, .char_flags = 0x0865, .ext = 0 },
    .{ .x = 1, .y = -11, .char_flags = 0x0865, .ext = 0 },
    .{ .x = 1, .y = -18, .char_flags = 0x0865, .ext = 0 },
    .{ .x = 1, .y = -25, .char_flags = 0x0865, .ext = 0 },
    .{ .x = -3, .y = -40, .char_flags = 0x0862, .ext = 2 },
    .{ .x = -8, .y = -9, .char_flags = 0x4864, .ext = 0 },
    .{ .x = -3, .y = -14, .char_flags = 0x4864, .ext = 0 },
    .{ .x = 3, .y = -20, .char_flags = 0x4864, .ext = 0 },
    .{ .x = 9, .y = -26, .char_flags = 0x4864, .ext = 0 },
    .{ .x = 12, .y = -37, .char_flags = 0x4844, .ext = 2 },
    .{ .x = -10, .y = -20, .char_flags = 0x4874, .ext = 0 },
    .{ .x = -3, .y = -20, .char_flags = 0x4874, .ext = 0 },
    .{ .x = 4, .y = -20, .char_flags = 0x4874, .ext = 0 },
    .{ .x = 11, .y = -20, .char_flags = 0x4874, .ext = 0 },
    .{ .x = 18, .y = -23, .char_flags = 0x4860, .ext = 2 },
    .{ .x = -10, .y = -30, .char_flags = 0xc864, .ext = 0 },
    .{ .x = -4, .y = -24, .char_flags = 0xc864, .ext = 0 },
    .{ .x = 2, .y = -18, .char_flags = 0xc864, .ext = 0 },
    .{ .x = 8, .y = -12, .char_flags = 0xc864, .ext = 0 },
    .{ .x = 12, .y = -8, .char_flags = 0xc844, .ext = 2 },
    .{ .x = 1, .y = -32, .char_flags = 0x8865, .ext = 0 },
    .{ .x = 1, .y = -25, .char_flags = 0x8865, .ext = 0 },
    .{ .x = 1, .y = -18, .char_flags = 0x8865, .ext = 0 },
    .{ .x = 1, .y = -11, .char_flags = 0x8865, .ext = 0 },
    .{ .x = -3, .y = -5, .char_flags = 0x8862, .ext = 2 },
    .{ .x = 13, .y = -30, .char_flags = 0x8864, .ext = 0 },
    .{ .x = 8, .y = -25, .char_flags = 0x8864, .ext = 0 },
    .{ .x = 2, .y = -19, .char_flags = 0x8864, .ext = 0 },
    .{ .x = -4, .y = -13, .char_flags = 0x8864, .ext = 0 },
    .{ .x = -16, .y = -9, .char_flags = 0x8844, .ext = 2 },
    .{ .x = 14, .y = -20, .char_flags = 0x0874, .ext = 0 },
    .{ .x = 7, .y = -20, .char_flags = 0x0874, .ext = 0 },
    .{ .x = 0, .y = -20, .char_flags = 0x0874, .ext = 0 },
    .{ .x = -7, .y = -20, .char_flags = 0x0874, .ext = 0 },
    .{ .x = -21, .y = -23, .char_flags = 0x0860, .ext = 2 },
    .{ .x = 13, .y = -30, .char_flags = 0x8864, .ext = 0 },
    .{ .x = 8, .y = -25, .char_flags = 0x8864, .ext = 0 },
    .{ .x = 2, .y = -19, .char_flags = 0x8864, .ext = 0 },
    .{ .x = -4, .y = -13, .char_flags = 0x8864, .ext = 0 },
    .{ .x = -16, .y = -9, .char_flags = 0x8844, .ext = 2 },
    .{ .x = -10, .y = -30, .char_flags = 0xc864, .ext = 0 },
    .{ .x = -4, .y = -24, .char_flags = 0xc864, .ext = 0 },
    .{ .x = -4, .y = -24, .char_flags = 0xc864, .ext = 0 },
    .{ .x = -4, .y = -24, .char_flags = 0xc864, .ext = 0 },
    .{ .x = -4, .y = -24, .char_flags = 0xc864, .ext = 0 },
};
pub const kTrident_Draw_X: [5]i8 = .{ 24, -16, 0, 16, -8 };
pub const kTrident_Draw_Y: [5]i8 = .{ 4, 4, 16, 21, 19 };
pub const kBuggySwamolaLookup: [6]u8 = .{ 0x1c, 0xa9, 0x03, 0x9d, 0x90, 0x0d };
pub const kSwamola_Target_Dir: [8]u8 = .{ 1, 2, 3, 4, 5, 6, 7, 8 };
pub const kSwamola_Target_X: [9]i8 = .{ 0, 0, 32, 32, 32, 0, -32, -32, -32 };
pub const kSwamola_Target_Y: [9]i8 = .{ 0, -32, -32, 0, 32, 32, 32, 0, -32 };
pub const kSwamola_Z_Accel: [2]i8 = .{ 2, -2 };
pub const kSwamola_Z_Vel_Target: [2]i8 = .{ 12, -12 };
pub const kSwamolaRipples_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = 4, .char_flags = 0x00d8, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x40d8, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x00d9, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x40d9, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x00da, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x40da, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x00d9, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x40d9, .ext = 0 },
};
pub const kSwamola_Gfx: [16]u8 = .{ 7, 6, 5, 4, 3, 4, 5, 6, 7, 6, 5, 4, 3, 4, 5, 6 };
pub const kSwamola_Gfx2: [4]u8 = .{ 0, 0, 1, 2 };
pub const kSwamola_Draw_OamFlags: [16]u8 = .{ 0xc0, 0xc0, 0xc0, 0xc0, 0x80, 0x80, 0x80, 0x80, 0, 0, 0, 0, 0, 0x40, 0x40, 0x40 };
pub const kSwamola_HistOffs: [4]u8 = .{ 8, 16, 22, 26 };
pub const kBlindHead_XposLimit: [2]u8 = .{ 0x98, 0x58 };
pub const kBlindHead_YposLimit: [2]u8 = .{ 0xb0, 0x50 };
pub const kBlindHead_YvelLimit: [2]i8 = .{ 24, -24 };
pub const kBlindHead_XvelLimit: [2]i8 = .{ 32, -32 };
pub const kBlindLaser_Gfx: [16]u8 = .{ 7, 7, 8, 9, 10, 9, 8, 7, 7, 7, 8, 9, 10, 9, 8, 7 };
pub const kBlindLaser_OamFlags: [16]u8 = .{ 0, 0, 0, 0, 0, 0x40, 0x40, 0x40, 0x40, 0x40, 0xc0, 0xc0, 0x80, 0x80, 0x80, 0x80 };
pub const kBlind_Gfx0: [7]u8 = .{ 20, 19, 18, 17, 16, 15, 15 };
pub const kBlind_Oscillate_YVelTarget: [2]i8 = .{ 18, -18 };
pub const kBlind_Oscillate_XVelTarget: [2]i8 = .{ 24, -24 };
pub const kBlind_Oscillate_XPosTarget: [2]u8 = .{ 164, 76 };
pub const kBlind_SwitchWall_YVelTarget: [2]i8 = .{ 64, -64 };
pub const kBlind_SwitchWall_YPosTarget: [2]u8 = .{ 0x90, 0x50 };
pub const kBlind_WhirlAround_Gfx: [2]u8 = .{ 0, 9 };
pub const kBlind_Gfx_BehindCurtain: [4]u8 = .{ 14, 13, 12, 10 };
pub const kBlind_Gfx_Rerobe: [5]u8 = .{ 10, 11, 12, 13, 14 };
pub const kBlindHead_SpawnFireball_Xvel: [16]i8 = .{ -32, -28, -24, -16, 0, 16, 24, 28, 32, 28, 24, 16, 0, -16, -24, -28 };
pub const kBlindHead_SpawnFireball_Yvel: [16]i8 = .{ 0, 16, 24, 28, 32, 28, 24, 16, 0, -16, -24, -28, -32, -28, -24, -16 };
pub const kBlind_HeadDir: [17]u8 = .{ 0, 1, 2, 3, 4, 3, 2, 1, 0, 15, 14, 13, 12, 13, 14, 15, 0 };
pub const kBlind_Animate_Tab: [8]u8 = .{ 0, 1, 1, 2, 2, 3, 3, 4 };
pub const kBlind_Gfx_Animate: [8]u8 = .{ 7, 8, 9, 8, 0, 1, 2, 1 };
pub const kBlind_Laser_Xvel: [16]i8 = .{ -8, -8, -8, -4, 0, 4, 8, 8, 8, 8, 8, 4, 0, -4, -8, -8 };
pub const kBlind_Laser_Yvel: [16]i8 = .{ 0, 0, 4, 8, 8, 8, 4, 0, 0, 0, -4, -8, -8, -8, -4, 0 };
pub const kBlindPoof_Dmd: [37]DrawMultipleData = .{
    .{ .x = -16, .y = -20, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -11, .y = -28, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -23, .y = -26, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -8, .y = -17, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -20, .y = -13, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -16, .y = -37, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -27, .y = -31, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -10, .y = -28, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -5, .y = -28, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -20, .y = -27, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -27, .y = -17, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -4, .y = -17, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -16, .y = -13, .char_flags = 0x0586, .ext = 2 },
    .{ .x = -18, .y = -37, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -5, .y = -33, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -32, .y = -32, .char_flags = 0x058a, .ext = 2 },
    .{ .x = -23, .y = -31, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -15, .y = -24, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -23, .y = -31, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -15, .y = -24, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -29, .y = -22, .char_flags = 0x058a, .ext = 2 },
    .{ .x = -5, .y = -22, .char_flags = 0x058a, .ext = 2 },
    .{ .x = -16, .y = -14, .char_flags = 0x058a, .ext = 2 },
    .{ .x = -12, .y = -32, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -26, .y = -29, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -6, .y = -22, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -19, .y = -20, .char_flags = 0x058a, .ext = 2 },
    .{ .x = -26, .y = -29, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -6, .y = -22, .char_flags = 0x458a, .ext = 2 },
    .{ .x = -19, .y = -20, .char_flags = 0x058a, .ext = 2 },
    .{ .x = -17, .y = -27, .char_flags = 0x059b, .ext = 0 },
    .{ .x = -10, .y = -26, .char_flags = 0x059b, .ext = 0 },
    .{ .x = 0, .y = -22, .char_flags = 0x459b, .ext = 0 },
    .{ .x = -19, .y = -16, .char_flags = 0x459b, .ext = 0 },
    .{ .x = -6, .y = -12, .char_flags = 0x059b, .ext = 0 },
    .{ .x = 0, .y = 13, .char_flags = 0x0b20, .ext = 2 },
    .{ .x = 0, .y = 23, .char_flags = 0x0b22, .ext = 2 },
};
pub const kOffs_15858: [8]u8 = .{ 0, 1, 5, 13, 23, 30, 35, 37 };
pub const kBlind_Dmd: [105]DrawMultipleData = .{
    .{ .x = -8, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 8, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0ca0, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4ca4, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a8c, .ext = 2 },
    .{ .x = -19, .y = 3, .char_flags = 0x0aa6, .ext = 2 },
    .{ .x = 19, .y = 3, .char_flags = 0x4aa6, .ext = 2 },
    .{ .x = -8, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 8, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0ca2, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4ca0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a8c, .ext = 2 },
    .{ .x = -19, .y = 3, .char_flags = 0x0aa8, .ext = 2 },
    .{ .x = 19, .y = 3, .char_flags = 0x4aa8, .ext = 2 },
    .{ .x = -8, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 8, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0ca4, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4ca2, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a8c, .ext = 2 },
    .{ .x = -19, .y = 3, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = 19, .y = 3, .char_flags = 0x4aaa, .ext = 2 },
    .{ .x = -15, .y = 5, .char_flags = 0x0aa6, .ext = 2 },
    .{ .x = -6, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 6, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -6, .y = 23, .char_flags = 0x0ca4, .ext = 2 },
    .{ .x = 6, .y = 23, .char_flags = 0x4ca0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a8a, .ext = 2 },
    .{ .x = 16, .y = -1, .char_flags = 0x4aa6, .ext = 2 },
    .{ .x = -11, .y = 9, .char_flags = 0x0aa6, .ext = 2 },
    .{ .x = -4, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 5, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -4, .y = 23, .char_flags = 0x0ca4, .ext = 2 },
    .{ .x = 5, .y = 23, .char_flags = 0x4ca0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a88, .ext = 2 },
    .{ .x = 10, .y = -2, .char_flags = 0x4aa6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a84, .ext = 2 },
    .{ .x = 13, .y = 8, .char_flags = 0x4aa6, .ext = 2 },
    .{ .x = -10, .y = -2, .char_flags = 0x0aa6, .ext = 2 },
    .{ .x = -5, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 5, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -5, .y = 23, .char_flags = 0x0ca0, .ext = 2 },
    .{ .x = 5, .y = 23, .char_flags = 0x4ca4, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a82, .ext = 2 },
    .{ .x = 18, .y = 4, .char_flags = 0x4aa6, .ext = 2 },
    .{ .x = -15, .y = -1, .char_flags = 0x0aa6, .ext = 2 },
    .{ .x = -6, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 6, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -6, .y = 23, .char_flags = 0x0ca0, .ext = 2 },
    .{ .x = 6, .y = 23, .char_flags = 0x4ca4, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a80, .ext = 2 },
    .{ .x = -19, .y = 3, .char_flags = 0x0aa6, .ext = 2 },
    .{ .x = 19, .y = 3, .char_flags = 0x4aa6, .ext = 2 },
    .{ .x = -8, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 8, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0ca0, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4ca4, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a80, .ext = 2 },
    .{ .x = -19, .y = 3, .char_flags = 0x0aa8, .ext = 2 },
    .{ .x = 19, .y = 3, .char_flags = 0x4aa8, .ext = 2 },
    .{ .x = -8, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 8, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0ca2, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4ca0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a80, .ext = 2 },
    .{ .x = -19, .y = 3, .char_flags = 0x0aaa, .ext = 2 },
    .{ .x = 19, .y = 3, .char_flags = 0x4aaa, .ext = 2 },
    .{ .x = -8, .y = 7, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 8, .y = 7, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0ca0, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4ca4, .ext = 2 },
    .{ .x = -8, .y = 9, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 8, .y = 9, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 0, .y = 2, .char_flags = 0x0a8c, .ext = 2 },
    .{ .x = -8, .y = 16, .char_flags = 0x0c8e, .ext = 2 },
    .{ .x = 8, .y = 16, .char_flags = 0x4c8e, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 0, .y = 9, .char_flags = 0x0a8c, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cae, .ext = 2 },
    .{ .x = 0, .y = 16, .char_flags = 0x0a8c, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 0, .y = 20, .char_flags = 0x0a8c, .ext = 2 },
    .{ .x = -8, .y = 23, .char_flags = 0x0cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 8, .y = 23, .char_flags = 0x4cac, .ext = 2 },
    .{ .x = 0, .y = 23, .char_flags = 0x0a8c, .ext = 2 },
};
pub const kBlind_OamIdx: [10]u8 = .{ 4, 4, 4, 5, 5, 0, 0, 0, 0, 0 };
pub const kSprite_TrinexxD_Gfx3: [8]u8 = .{ 6, 7, 0, 1, 2, 3, 4, 5 };
pub const kSprite_TrinexxD_Gfx: [8]u8 = .{ 7, 7, 1, 1, 3, 3, 5, 5 };
pub const kSprite_TrinexxD_Xvel: [4]i8 = .{ 0, -31, 0, 31 };
pub const kSprite_TrinexxD_Yvel: [4]i8 = .{ 31, 0, -31, 0 };
pub const kTrinexxD_HistPos: [24]i8 = .{
    8,    0xc,  0x10, 0x18, 0x20, 0x28, 0x30, 0x34, 0x38, 0x3c, 0x40, 0x44, 0x48, 0x4c, 0x50, 0x54,
    0x58, 0x5c, 0x60, 0x64, 0x68, 0x6c, 0x70, 0x74,
};
pub const kSprite_TrinexxD_Gfx2: [24]i8 = .{
    2, 2, 2, 3, 3, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
};
pub const kTrinexxD_OamOffs: [24]i16 = .{
    0x10, 4, 4, 4, 0x10, 0x10, 0x10, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4,    4, 4, 4, 4,    4,    4,    4,
};
pub const kTrinexx_X0: [8]i8 = .{ 0, 8, 16, 24, -24, -16, -8, 0 };
pub const kTrinexx_Y0: [8]i8 = .{ 0, 8, 16, 24, -24, -16, -8, 0 };
pub const kTrinexx_Tab0: [4]u8 = .{ 0x60, 0x78, 0x78, 0x90 };
pub const kTrinexx_Tab1: [4]u8 = .{ 0x80, 0x70, 0x60, 0x80 };
pub const kTrinexx_Draw1_Dmd: [36]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x40c0, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x00c0, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x40e0, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x00e0, .ext = 2 },

    .{ .x = -8, .y = -8, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x0002, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x0022, .ext = 2 },

    .{ .x = -8, .y = -8, .char_flags = 0x00c2, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x00c4, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x80c2, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x80c4, .ext = 2 },

    .{ .x = -8, .y = -8, .char_flags = 0x8020, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x8022, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x8000, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x8002, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0xc0e0, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x80e0, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0xc0c0, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x80c0, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0xc022, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0xc020, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0xc002, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0xc000, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x40c4, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x40c2, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0xc0c4, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0xc0c2, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x4002, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4000, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x4022, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x4020, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0026, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4026, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x8026, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0xc026, .ext = 2 },
};
pub const kTrinexx_Draw_X: [35]i8 = .{
    0,  3,   9,   16, 24, 0,  2,  7,  13,  20, 0,  1,  4,   9,   15, 0,
    0,  0,   0,   0,  0,  -1, -4, -9, -15, 0,  -2, -7, -13, -20, 0,  -3,
    -9, -16, -24,
};
pub const kTrinexx_Draw_Y: [35]i8 = .{
    0x18, 0x20, 0x25, 0x25, 0x21, 0x18, 0x20, 0x27, 0x2a, 0x2c, 0x18, 0x20, 0x28, 0x2f, 0x34, 0x18,
    0x21, 0x2a, 0x34, 0x3d, 0x18, 0x20, 0x28, 0x2f, 0x34, 0x18, 0x20, 0x27, 0x2a, 0x2c, 0x18, 0x20,
    0x25, 0x25, 0x21,
};
pub const kTrinexx_Draw_Char: [5]u8 = .{ 6, 0x28, 0x28, 0x2c, 0x2c };
pub const kTrinexx_Mults: [8]u8 = .{ 0xfc, 0xe0, 0xc0, 0xa0, 0x80, 0x60, 0x40, 0x20 };
pub const kTrinexx_Draw_Xoffs: [16]i8 = .{ 0, 2, 3, 4, 4, 4, 3, 2, 0, -2, -3, -4, -4, -4, -3, -2 };
pub const kTrinexx_Draw_Yoffs: [16]i8 = .{ -4, -4, -3, -2, 0, 2, 3, 4, 4, 4, 3, 2, 0, -2, -3, -4 };
pub const kTrinexxHead_Xoffs: [2]i8 = .{ -14, 13 };
pub const kTrinexxHead_Target0: [45]u8 = .{
    0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x58, 0x64, 0x6a, 0x6f, 0x74, 0x7a, 0x7e,
    0x80, 0x80, 0x39, 0x48, 0x52, 0x5c, 0x65, 0x73, 0x77, 0x7a, 0x80, 0x1e, 0x24, 0x29, 0x2e, 0x34,
    0x3a, 0x44, 0x4d, 0x80, 0xa,  0x11, 0x17, 0x1c, 0x22, 0x2a, 0x36, 0x3a, 0x80,
};
pub const kTrinexxHead_Target1: [45]u8 = .{
    0x30, 0x28, 0x23, 0x1e, 0x19, 0x13, 0xc,  6,    0,    0x2f, 0x26, 0x21, 0x1d, 0x18, 0x12, 0xc,
    6,    0,    0x2f, 0x27, 0x22, 0x1d, 0x18, 0x12, 0xc,  6,    0,    0x2f, 0x27, 0x22, 0x1d, 0x18,
    0x12, 0xc,  6,    0,    0x48, 0x3a, 0x32, 0x29, 0x22, 0x19, 0x10, 7,    0,
};
pub const kTrinexxHead_FrameMask: [8]u8 = .{ 1, 1, 3, 3, 7, 0xf, 0x1f, 0x1f };
pub const kTrinexxHead_FirstPart_X: [5]i8 = .{ -8, 8, -8, 8, 0 };
pub const kTrinexxHead_FirstPart_Y: [5]i8 = .{ -8, -8, 8, 8, 2 };
pub const kTrinexxHead_FirstPart_Char: [5]u8 = .{ 4, 4, 0x24, 0x24, 0xa };
pub const kTrinexxHead_FirstPart_Flags: [5]u8 = .{ 0x40, 0, 0x40, 0, 0 };
pub const kChainChomp_Xvel: [16]i8 = .{ 0, 8, 11, 14, 16, 14, 11, 8, 0, -8, -11, -14, -16, -14, -11, -8 };
pub const kChainChomp_Yvel: [16]i8 = .{ -16, -14, -11, -8, 0, 8, 11, 14, 16, 14, 11, 8, 0, -9, -11, -14 };
pub const kChainChomp_Muls: [6]u8 = .{ 205, 154, 102, 51, 8, 0xbd };
pub const kChainChomp_Gfx: [16]u8 = .{ 0, 1, 2, 3, 3, 3, 2, 1, 0, 0, 0, 4, 4, 4, 0, 0 };
pub const kChainChomp_OamFlags: [16]u8 = .{ 0x40, 0x40, 0x40, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0x40, 0x40, 0x40, 0x40 };
pub const kTektite_Dir: [4]u8 = .{ 3, 2, 1, 0 };
pub const kTektite_Xvel: [4]i8 = .{ 16, -16, 16, -16 };
pub const kTektite_Yvel: [4]i8 = .{ 16, 16, -16, -16 };
pub const kTektite_Dmd: [6]DrawMultipleData = .{
    .{ .x = -8, .y = 0, .char_flags = 0x00c8, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40c8, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00ca, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40ca, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00ea, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40ea, .ext = 2 },
};
pub const kBigFaerie_Dmd: [16]DrawMultipleData = .{
    .{ .x = -4, .y = -8, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x408e, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x00ae, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x40ae, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x408c, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x408a, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x408c, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x40ac, .ext = 2 },
};
pub const kFaerieCloud_Draw_XY: [8]i8 = .{ -12, -6, 0, 6, 12, 18, 0, 6 };
pub const kHokbok_B: [8]u8 = .{ 8, 7, 6, 5, 4, 5, 6, 7 };
pub const kFireballJunction_X: [4]i8 = .{ 12, -12, 0, 0 };
pub const kFireballJunction_Y: [4]i8 = .{ 0, 0, 12, -12 };
pub const kFireballJunction_XYvel: [6]i8 = .{ 0, 0, 40, -40, 0, 0 };
pub const kThiefSpawn_Items: [4]u8 = .{ 0xd9, 0xe1, 0xdc, 0xd9 };
pub const kThiefSpawn_Xvel: [6]i8 = .{ 0, 24, 24, 0, -24, -24 };
pub const kThiefSpawn_Yvel: [6]i8 = .{ -32, -16, 16, 32, 16, -16 };
pub const kThief_Dmd: [24]DrawMultipleData = .{
    .{ .x = 0, .y = -6, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0006, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4006, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x0000, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0022, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4022, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0004, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0024, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x400a, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x4002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x400e, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x4002, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x400a, .ext = 2 },
};
pub const kThief_DrawChar: [4]u8 = .{ 2, 2, 0, 4 };
pub const kThief_DrawFlags: [4]u8 = .{ 0x40, 0, 0, 0 };
pub const kGibo_Xvel: [8]i8 = .{ 16, 16, 0, -16, -16, -16, 0, 16 };
pub const kGibo_Yvel: [8]i8 = .{ 0, 0, 16, -16, 16, 16, -16, -16 };
pub const kGibo_Dmd: [32]DrawMultipleData = .{
    .{ .x = 4, .y = -4, .char_flags = 0x408a, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x408f, .ext = 0 },
    .{ .x = 12, .y = 12, .char_flags = 0x408e, .ext = 0 },
    .{ .x = -4, .y = 4, .char_flags = 0x408c, .ext = 2 },
    .{ .x = 4, .y = -4, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x409f, .ext = 0 },
    .{ .x = 12, .y = 12, .char_flags = 0x409e, .ext = 0 },
    .{ .x = -4, .y = 4, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = 3, .y = -3, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = -3, .y = -3, .char_flags = 0x409f, .ext = 0 },
    .{ .x = 11, .y = 11, .char_flags = 0x409e, .ext = 0 },
    .{ .x = -3, .y = 3, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = 3, .y = -3, .char_flags = 0x408a, .ext = 2 },
    .{ .x = -3, .y = -3, .char_flags = 0x408f, .ext = 0 },
    .{ .x = 11, .y = 11, .char_flags = 0x408e, .ext = 0 },
    .{ .x = -3, .y = 3, .char_flags = 0x408c, .ext = 2 },
    .{ .x = -3, .y = -4, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 13, .y = -4, .char_flags = 0x008f, .ext = 0 },
    .{ .x = -3, .y = 12, .char_flags = 0x008e, .ext = 0 },
    .{ .x = 5, .y = 4, .char_flags = 0x008c, .ext = 2 },
    .{ .x = -3, .y = -4, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 13, .y = -4, .char_flags = 0x009f, .ext = 0 },
    .{ .x = -3, .y = 12, .char_flags = 0x009e, .ext = 0 },
    .{ .x = 5, .y = 4, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = -2, .y = -3, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 12, .y = -3, .char_flags = 0x009f, .ext = 0 },
    .{ .x = -2, .y = 11, .char_flags = 0x009e, .ext = 0 },
    .{ .x = 4, .y = 3, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = -2, .y = -3, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 12, .y = -3, .char_flags = 0x008f, .ext = 0 },
    .{ .x = -2, .y = 11, .char_flags = 0x008e, .ext = 0 },
    .{ .x = 4, .y = 3, .char_flags = 0x008c, .ext = 2 },
};
pub const kBoulder_Zvel: [2]i8 = .{ 32, 48 };
pub const kBoulder_Yvel: [2]i8 = .{ 8, 32 };
pub const kBoulder_Xvel: [4]i8 = .{ 24, 16, -24, -16 };
pub const kBoulder_Dmd: [16]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x01cc, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x01ce, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x01ec, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x01ee, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x41ce, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x41cc, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x41ee, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x41ec, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0xc1ee, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0xc1ec, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0xc1ce, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0xc1cc, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x81ec, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x81ee, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x81cc, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x81ce, .ext = 2 },
};
pub const kChattyAgahnim_LevitateGfx: [4]u8 = .{ 2, 0, 3, 0 };
pub const kChattyAgahnim_Dmd: [16]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x0b82, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4b82, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x0ba2, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x4ba2, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0b80, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4b80, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x0ba0, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x4ba0, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0b80, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4b82, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x0ba0, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x4ba2, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x0b82, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4b80, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x0ba2, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x4ba0, .ext = 2 },
};
pub const kChattyAgahnim_Telewarp_Data: [28]OamEntSigned = .{
    .{ .x = -10, .y = -16, .charnum = 0xce, .flags = 0x06 },
    .{ .x = 18, .y = -16, .charnum = 0xce, .flags = 0x06 },
    .{ .x = 20, .y = -13, .charnum = 0x26, .flags = 0x06 },
    .{ .x = 20, .y = -5, .charnum = 0x36, .flags = 0x06 },
    .{ .x = -12, .y = -13, .charnum = 0x26, .flags = 0x46 },
    .{ .x = -12, .y = -5, .charnum = 0x36, .flags = 0x46 },
    .{ .x = 18, .y = 0, .charnum = 0x26, .flags = 0x06 },
    .{ .x = 18, .y = 8, .charnum = 0x36, .flags = 0x06 },
    .{ .x = -10, .y = 0, .charnum = 0x26, .flags = 0x46 },
    .{ .x = -10, .y = 8, .charnum = 0x36, .flags = 0x46 },
    .{ .x = -8, .y = 0, .charnum = 0x22, .flags = 0x06 },
    .{ .x = 8, .y = 0, .charnum = 0x22, .flags = 0x46 },
    .{ .x = -8, .y = 16, .charnum = 0x22, .flags = 0x86 },
    .{ .x = 8, .y = 16, .charnum = 0x22, .flags = 0xc6 },
    .{ .x = -10, .y = -16, .charnum = 0xce, .flags = 0x04 },
    .{ .x = 18, .y = -16, .charnum = 0xce, .flags = 0x04 },
    .{ .x = 20, .y = -13, .charnum = 0x26, .flags = 0x44 },
    .{ .x = 20, .y = -5, .charnum = 0x36, .flags = 0x44 },
    .{ .x = -12, .y = -13, .charnum = 0x26, .flags = 0x04 },
    .{ .x = -12, .y = -5, .charnum = 0x36, .flags = 0x04 },
    .{ .x = 18, .y = 0, .charnum = 0x26, .flags = 0x44 },
    .{ .x = 18, .y = 8, .charnum = 0x36, .flags = 0x44 },
    .{ .x = -10, .y = 0, .charnum = 0x26, .flags = 0x04 },
    .{ .x = -10, .y = 8, .charnum = 0x36, .flags = 0x04 },
    .{ .x = -8, .y = 0, .charnum = 0x20, .flags = 0x04 },
    .{ .x = 8, .y = 0, .charnum = 0x20, .flags = 0x44 },
    .{ .x = -8, .y = 16, .charnum = 0x20, .flags = 0x84 },
    .{ .x = 8, .y = 16, .charnum = 0x20, .flags = 0xc4 },
};
pub const kChattyAgahnim_Telewarp_Data_Big: [14]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2 };
pub const kAltarZelda_Dmd: [4]DrawMultipleData = .{
    .{ .x = -4, .y = 0, .char_flags = 0x0103, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x0104, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x0100, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x0101, .ext = 2 },
};
pub const kAltarZelda_XOffs: [16]u8 = .{ 4, 4, 3, 3, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0 };
pub const kAltarZelda_Warp_Dmd: [10]DrawMultipleData = .{
    .{ .x = 4, .y = 4, .char_flags = 0x0480, .ext = 0 },
    .{ .x = 4, .y = 4, .char_flags = 0x0480, .ext = 0 },
    .{ .x = 4, .y = 4, .char_flags = 0x04b7, .ext = 0 },
    .{ .x = 4, .y = 4, .char_flags = 0x04b7, .ext = 0 },
    .{ .x = -6, .y = 0, .char_flags = 0x0524, .ext = 2 },
    .{ .x = 6, .y = 0, .char_flags = 0x4524, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x0524, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4524, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x05c6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x05c6, .ext = 2 },
};
pub const kGiantMoldorm_Head_Dmd: [16]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x0082, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x4082, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x4080, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x40a2, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x40a0, .ext = 2 },
    .{ .x = -6, .y = -6, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 6, .y = -6, .char_flags = 0x0082, .ext = 2 },
    .{ .x = -6, .y = 6, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 6, .y = 6, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = -6, .y = -6, .char_flags = 0x4082, .ext = 2 },
    .{ .x = 6, .y = -6, .char_flags = 0x4080, .ext = 2 },
    .{ .x = -6, .y = 6, .char_flags = 0x40a2, .ext = 2 },
    .{ .x = 6, .y = 6, .char_flags = 0x40a0, .ext = 2 },
};
pub const kGiantMoldorm_Eye_X: [16]i16 = .{ 16, 15, 12, 6, 0, -6, -12, -13, -16, -13, -12, -6, 0, 6, 12, 15 };
pub const kGiantMoldorm_Eye_Y: [16]i16 = .{ 0, 6, 12, 15, 16, 15, 12, 6, 0, -6, -12, -13, -16, -13, -12, -6 };
pub const kGiantMoldorm_Eye_Char: [16]u8 = .{ 0xaa, 0xaa, 0xa8, 0xa8, 0x8a, 0x8a, 0xa8, 0xa8, 0xaa, 0xaa, 0xa8, 0xa8, 0x8a, 0x8a, 0xa8, 0xa8 };
pub const kGiantMoldorm_Eye_Flags: [16]u8 = .{ 0, 0, 0, 0, 0x80, 0x80, 0x40, 0x40, 0x40, 0x40, 0xc0, 0xc0, 0, 0, 0x80, 0x80 };
pub const kVulture_Dmd: [8]DrawMultipleData = .{
    .{ .x = -8, .y = 0, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4086, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4080, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x0082, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4082, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4084, .ext = 2 },
};
pub const kRaven_AscendTime: [2]u8 = .{ 16, 248 };
pub const kVitreous_SpawnSmallerEyes_X: [13]i8 = .{ 8, 22, -8, -22, 0, 14, 19, 33, 26, -14, -19, -33, -26 };
pub const kVitreous_SpawnSmallerEyes_Y: [13]i8 = .{ -8, -12, -8, -12, 0, -20, -1, -12, -24, -20, -1, -12, -24 };
pub const kVitreous_SpawnSmallerEyes_Gfx: [13]i8 = .{ 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
pub const kStandaloneItem_Zvel: [4]u8 = .{ 0x20, 0x10, 8, 0 };
pub const kGreatCatfish_Emerge_Gfx: [16]u8 = .{ 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 0, 0, 0, 0 };
pub const kGreatCatfish_Conversate_Gfx: [20]u8 = .{ 0, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 6, 6 };
pub const kGreatCatfish_Dmd: [28]DrawMultipleData = .{
    .{ .x = -4, .y = 4, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0x008d, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0x008d, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 4, .y = -4, .char_flags = 0x008d, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0x009c, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0x009d, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x408d, .ext = 2 },
    .{ .x = 4, .y = -4, .char_flags = 0x408c, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0x409d, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0x409c, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0xc09d, .ext = 2 },
    .{ .x = 4, .y = -4, .char_flags = 0xc09c, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0xc08d, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0xc08c, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0xc09d, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0xc09c, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0xc09d, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0xc09c, .ext = 2 },
    .{ .x = 0, .y = 8, .char_flags = 0x00bd, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x40bd, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x40bd, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x40bd, .ext = 0 },
    .{ .x = -8, .y = 0, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4086, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4086, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4086, .ext = 2 },
};
pub const kWaterSplash_Dmd: [8]DrawMultipleData = .{
    .{ .x = -8, .y = -4, .char_flags = 0x0080, .ext = 0 },
    .{ .x = 18, .y = -7, .char_flags = 0x0080, .ext = 0 },
    .{ .x = -5, .y = -2, .char_flags = 0x00bf, .ext = 0 },
    .{ .x = 15, .y = -4, .char_flags = 0x40af, .ext = 0 },
    .{ .x = 0, .y = -4, .char_flags = 0x00e7, .ext = 2 },
    .{ .x = 0, .y = -4, .char_flags = 0x00e7, .ext = 2 },
    .{ .x = 0, .y = -4, .char_flags = 0x00c0, .ext = 2 },
    .{ .x = 0, .y = -4, .char_flags = 0x00c0, .ext = 2 },
};
pub const kSpriteLightning_Gfx: [8]u8 = .{ 0, 1, 2, 3, 0, 1, 2, 3 };
pub const kSpriteLightning_OamFlags: [8]u8 = .{ 0, 0, 0, 0, 0x40, 0x40, 0x40, 0x40 };
pub const kSpriteLightning_Xoff: [64]i8 = .{
    -15, 0,  0,  -15, 0,  -15, -15, 0,  -15, 0,  0,  -15, 0,  -15, -15, 0,
    0,   15, 15, 0,   15, 0,   0,   15, 0,   15, 15, 0,   15, 0,   0,   15,
    0,   15, 15, 0,   15, 0,   0,   15, 0,   15, 15, 0,   15, 0,   0,   15,
    -15, 0,  0,  -15, 0,  -15, -15, 0,  -15, 0,  0,  -15, 0,  -15, -15, 0,
};
pub const kVitreous_AfromG: [10]u8 = .{ 0x20, 0x20, 0x20, 0x40, 0x60, 0x80, 0xa0, 0xc0, 0xe0, 0 };
pub const kVitreous_Xvel: [2]i8 = .{ 8, -8 };
pub const kVitreous_Animate_Gfx: [2]i8 = .{ 2, 1 };
pub const kVitreous_WhichToActivate: [16]u8 = .{ 5, 6, 7, 8, 9, 10, 11, 12, 13, 5, 6, 7, 8, 9, 10, 11 };
pub const kAgahnim_Lighting_X: [8]i8 = .{ -8, 8, 8, -8, 8, -8, -8, 8 };
pub const kVitreous_Dmd: [24]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x01c0, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x41c0, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x01e0, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x41e0, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x01c8, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x01ca, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x01e8, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x01ea, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x41ca, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x41c8, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x41ea, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x41e8, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x01c2, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x41c2, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x01e2, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x41e2, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x01c4, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x41c4, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x01e4, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0x41e4, .ext = 2 },
    .{ .x = -7, .y = -7, .char_flags = 0x01c4, .ext = 2 },
    .{ .x = 7, .y = -7, .char_flags = 0x41c4, .ext = 2 },
    .{ .x = -7, .y = 7, .char_flags = 0x01e4, .ext = 2 },
    .{ .x = 7, .y = 7, .char_flags = 0x41e4, .ext = 2 },
};
pub const kSprite_Vitreolus_Dx: [4]i8 = .{ 1, 0, -1, 0 };
pub const kSprite_Vitreolus_Dy: [4]i8 = .{ 0, 1, 0, -1 };
pub const kHelmasaurFireball_TriSplit_Xvel: [3]i8 = .{ 0, 28, -28 };
pub const kHelmasaurFireball_TriSplit_Yvel: [3]i8 = .{ -32, 24, 24 };
pub const kHelmasaurFireball_TriSplit_Delay: [6]u8 = .{ 32, 80, 128, 32, 80, 128 };
pub const kHelmasaurFireball_QuadSplit_Xvel: [4]i8 = .{ 32, 32, -32, -32 };
pub const kHelmasaurFireball_QuadSplit_Yvel: [4]i8 = .{ -32, 32, -32, 32 };
pub const kEvilBarrier_Dmd: [45]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x00e8, .ext = 2 },
    .{ .x = -29, .y = 3, .char_flags = 0x00ca, .ext = 0 },
    .{ .x = -29, .y = 11, .char_flags = 0x00da, .ext = 0 },
    .{ .x = 37, .y = 3, .char_flags = 0x40ca, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40da, .ext = 0 },
    .{ .x = -24, .y = -2, .char_flags = 0x00e6, .ext = 2 },
    .{ .x = -8, .y = -2, .char_flags = 0x00e6, .ext = 2 },
    .{ .x = 8, .y = -2, .char_flags = 0x40e6, .ext = 2 },
    .{ .x = 24, .y = -2, .char_flags = 0x40e6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = -29, .y = 3, .char_flags = 0x00cb, .ext = 0 },
    .{ .x = -29, .y = 11, .char_flags = 0x00db, .ext = 0 },
    .{ .x = 37, .y = 3, .char_flags = 0x40cb, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40db, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00cc, .ext = 2 },
    .{ .x = -29, .y = 3, .char_flags = 0x00cb, .ext = 0 },
    .{ .x = -29, .y = 11, .char_flags = 0x00db, .ext = 0 },
    .{ .x = 37, .y = 3, .char_flags = 0x40cb, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40db, .ext = 0 },
    .{ .x = -24, .y = -2, .char_flags = 0x80e6, .ext = 2 },
    .{ .x = -8, .y = -2, .char_flags = 0x80e6, .ext = 2 },
    .{ .x = 8, .y = -2, .char_flags = 0xc0e6, .ext = 2 },
    .{ .x = 24, .y = -2, .char_flags = 0xc0e6, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e8, .ext = 2 },
    .{ .x = -29, .y = 3, .char_flags = 0x00ca, .ext = 0 },
    .{ .x = -29, .y = 11, .char_flags = 0x00da, .ext = 0 },
    .{ .x = 37, .y = 3, .char_flags = 0x40ca, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40da, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e8, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e8, .ext = 2 },
    .{ .x = -29, .y = 3, .char_flags = 0x00cb, .ext = 0 },
    .{ .x = -29, .y = 11, .char_flags = 0x00db, .ext = 0 },
    .{ .x = 37, .y = 3, .char_flags = 0x40cb, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40db, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40db, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40db, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40db, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40db, .ext = 0 },
    .{ .x = 37, .y = 11, .char_flags = 0x40db, .ext = 0 },
};
pub const kDrawFourAroundOne_Dmd: [30]DrawMultipleData = .{
    .{ .x = 4, .y = 2, .char_flags = 0x02e1, .ext = 0 },
    .{ .x = 4, .y = -3, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = -1, .y = 2, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 9, .y = 2, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 4, .y = 7, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 4, .y = 2, .char_flags = 0x02e1, .ext = 0 },
    .{ .x = 3, .y = -3, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 9, .y = 1, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = -1, .y = 3, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 5, .y = 7, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 4, .y = 2, .char_flags = 0x02e1, .ext = 0 },
    .{ .x = 1, .y = -3, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 9, .y = -1, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = -1, .y = 5, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 7, .y = 7, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 4, .y = 2, .char_flags = 0x02e1, .ext = 0 },
    .{ .x = 0, .y = -2, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 8, .y = -2, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 0, .y = 6, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 8, .y = 6, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 4, .y = 2, .char_flags = 0x02e1, .ext = 0 },
    .{ .x = 7, .y = -3, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = -1, .y = -1, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 9, .y = 5, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 1, .y = 7, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 4, .y = 2, .char_flags = 0x02e1, .ext = 0 },
    .{ .x = 5, .y = -3, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = -1, .y = 1, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 9, .y = 3, .char_flags = 0x02e3, .ext = 0 },
    .{ .x = 3, .y = 7, .char_flags = 0x02e3, .ext = 0 },
};
pub const kGoriya_Dmd2: [3]DrawMultipleData = .{
    .{ .x = 10, .y = 4, .char_flags = 0x4077, .ext = 0 },
    .{ .x = -2, .y = 4, .char_flags = 0x0077, .ext = 0 },
    .{ .x = 4, .y = 4, .char_flags = 0x0076, .ext = 0 },
};
pub const kGoriya_Dmd: [32]DrawMultipleData = .{
    .{ .x = -4, .y = -8, .char_flags = 0x0044, .ext = 2 },
    .{ .x = 12, .y = -8, .char_flags = 0x4044, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0x0064, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x4054, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x0044, .ext = 2 },
    .{ .x = 12, .y = -8, .char_flags = 0x4044, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0x4074, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x4062, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x0044, .ext = 0 },
    .{ .x = 4, .y = -8, .char_flags = 0x4044, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x0062, .ext = 2 },
    .{ .x = 12, .y = 8, .char_flags = 0x4064, .ext = 0 },
    .{ .x = -4, .y = -8, .char_flags = 0x0046, .ext = 2 },
    .{ .x = 12, .y = -8, .char_flags = 0x4046, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0x0066, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x4056, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x0046, .ext = 2 },
    .{ .x = 12, .y = -8, .char_flags = 0x4046, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0x4075, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x406a, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x0046, .ext = 0 },
    .{ .x = 4, .y = -8, .char_flags = 0x4046, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x006a, .ext = 2 },
    .{ .x = 12, .y = 8, .char_flags = 0x0075, .ext = 0 },
    .{ .x = -2, .y = -8, .char_flags = 0x004e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x006c, .ext = 2 },
    .{ .x = -2, .y = -7, .char_flags = 0x004e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x006e, .ext = 2 },
    .{ .x = 2, .y = -8, .char_flags = 0x404e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x406c, .ext = 2 },
    .{ .x = 2, .y = -7, .char_flags = 0x404e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x406e, .ext = 2 },
};
pub const kGoriyaDmdOffs: [11]u8 = .{ 0, 4, 8, 12, 16, 20, 24, 26, 28, 30, 32 };
pub const kMoldorm_Draw_X: [16]i8 = .{ 11, 10, 9, 6, 3, 0, -2, -3, -4, -3, -2, 1, 4, 7, 9, 10 };
pub const kMoldorm_Draw_Y: [16]i8 = .{ 4, 6, 9, 10, 11, 10, 9, 6, 3, 0, -2, -3, -4, -3, -2, 1 };
pub const kMoldorm_Draw_Char: [3]u8 = .{ 0x5d, 0x62, 0x60 };
pub const kMoldorm_Draw_XY: [3]i8 = .{ 4, 0, 0 };
pub const kMoldorm_Draw_Big: [3]u8 = .{ 0, 2, 2 };
pub const kMoldorm_Draw_GetOffs: [3]u8 = .{ 21, 26, 0 };
pub const kTalkingTree_Gfx2: [4]i8 = .{ 0, 2, 3, 1 };
pub const kTalkingTree_Msgs2: [2]u8 = .{ 0x82, 0x7d };
pub const kTalkingTree_Msgs: [4]u8 = .{ 0x7e, 0x7f, 0x80, 0x81 };
pub const kTalkingTree_Screens: [4]u8 = .{ 0x58, 0x5d, 0x72, 0x6b };
pub const kTalkingTree_Gfx: [8]u8 = .{ 1, 2, 3, 1, 3, 1, 2, 3 };
pub const kTalkingTree_Delay: [8]u8 = .{ 13, 13, 13, 11, 11, 6, 16, 8 };
pub const kTalkingTree_Dmd: [12]DrawMultipleData = .{
    .{ .x = 1, .y = -1, .char_flags = 0x00e8, .ext = 0 },
    .{ .x = 1, .y = 7, .char_flags = 0x00f8, .ext = 0 },
    .{ .x = 7, .y = -1, .char_flags = 0x40e8, .ext = 0 },
    .{ .x = 7, .y = 7, .char_flags = 0x40f8, .ext = 0 },
    .{ .x = 0, .y = -1, .char_flags = 0x00e8, .ext = 0 },
    .{ .x = 0, .y = 7, .char_flags = 0x00f8, .ext = 0 },
    .{ .x = 8, .y = -1, .char_flags = 0x40e8, .ext = 0 },
    .{ .x = 8, .y = 7, .char_flags = 0x40f8, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x00e8, .ext = 0 },
    .{ .x = 0, .y = 7, .char_flags = 0x00f8, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x40e8, .ext = 0 },
    .{ .x = 8, .y = 7, .char_flags = 0x40f8, .ext = 0 },
};
pub const kTalkingTree_Type1_X: [2]i8 = .{ 9, -9 };
pub const kTalkingTree_X1: [5]i8 = .{ -2, -1, 0, 1, 2 };
pub const kTalkingTree_Y1: [5]i8 = .{ -1, 0, 0, 0, -1 };
pub const kTalkingTree_SpawnX: [2]i8 = .{ -4, 14 };
pub const kSpawnRupees_Xvel: [4]i8 = .{ -18, -12, 12, 18 };
pub const kSpawnRupees_Yvel: [4]i8 = .{ 16, 24, 24, 16 };
pub const kSpawnRupees_Type: [3]u8 = .{ 0xd9, 0xda, 0xdb };
pub const kDiggingGameGuy_Dmd: [9]DrawMultipleData = .{
    .{ .x = 0, .y = -8, .char_flags = 0x0a40, .ext = 2 },
    .{ .x = 4, .y = 9, .char_flags = 0x0c56, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a42, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0a40, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a42, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a42, .ext = 2 },
    .{ .x = -1, .y = -7, .char_flags = 0x0a40, .ext = 2 },
    .{ .x = -1, .y = 0, .char_flags = 0x0a44, .ext = 2 },
    .{ .x = -1, .y = 0, .char_flags = 0x0a44, .ext = 2 },
};
pub const kOldMountainMan_Dmd0: [2]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 0, .y = 8, .char_flags = 0x00ae, .ext = 2 },
};
pub const kOldMountainMan_Dmd1: [16]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 0, .y = 8, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 0, .y = 9, .char_flags = 0x4122, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 0, .y = 8, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 0, .y = 9, .char_flags = 0x4122, .ext = 2 },
    .{ .x = -2, .y = 0, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 0, .y = 8, .char_flags = 0x0122, .ext = 2 },
    .{ .x = -2, .y = 1, .char_flags = 0x0120, .ext = 2 },
    .{ .x = 0, .y = 9, .char_flags = 0x0122, .ext = 2 },
    .{ .x = 2, .y = 0, .char_flags = 0x4120, .ext = 2 },
    .{ .x = 0, .y = 8, .char_flags = 0x4122, .ext = 2 },
    .{ .x = 2, .y = 1, .char_flags = 0x4120, .ext = 2 },
    .{ .x = 0, .y = 9, .char_flags = 0x4122, .ext = 2 },
};
pub const kOldMountainMan_Dma: [16]u8 = .{ 0x20, 0xc0, 0x20, 0xc0, 0, 0xa0, 0, 0xa0, 0x40, 0x80, 0x40, 0x60, 0x40, 0x80, 0x40, 0x60 };
pub const kHelmasaurKing_Tab1: [13]u8 = .{ 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 1, 1, 0 };
pub const kHelmasaurKing_Xvel0: [8]i8 = .{ -12, -12, -4, 0, 4, 12, 12, 0 };
pub const kHelmasaurKing_Yvel0: [8]i8 = .{ 0, 4, 12, 12, 12, 4, 0, 12 };
pub const kHelmasaurKing_Mask_X: [10]i8 = .{ -16, 0, 16, -16, 0, 16, -8, 8, -16, 16 };
pub const kHelmasaurKing_Mask_Y: [10]i8 = .{ 24, 27, 24, 24, 27, 24, 27, 27, 24, 24 };
pub const kHelmasaurKing_Mask_Z: [10]i8 = .{ 29, 32, 29, 13, 16, 13, 0, 0, 13, 13 };
pub const kHelmasaurKing_Mask_Xvel: [10]i8 = .{ -16, -4, 14, -12, 4, 18, -2, 2, -12, 18 };
pub const kHelmasaurKing_Mask_Yvel: [10]i8 = .{ -8, -4, -6, 4, 2, 7, 6, 8, 4, 7 };
pub const kHelmasaurKing_Mask_Zvel: [10]i8 = .{ 32, 40, 36, 37, 39, 34, 30, 33, 37, 34 };
pub const kHelmasaurKing_Mask_OamFlags: [10]u8 = .{ 0, 0, 0x40, 0, 0, 0x40, 0, 0x40, 0, 0x40 };
pub const kHelmasaurKing_Mask_Gfx: [10]u8 = .{ 0, 1, 0, 2, 3, 2, 4, 4, 5, 5 };
pub const kHelmasaurKing_DrawB_X: [2]i8 = .{ -3, 11 };
pub const kHelmasaurKing_DrawB_Char: [8]u8 = .{ 0xce, 0xcf, 0xde, 0xde, 0xde, 0xde, 0xcf, 0xce };
pub const kHelmasaurKing_DrawB_Flags: [2]u8 = .{ 0x3b, 0x7b };
pub const kHelmasaurKing_DrawC_Dmd: [24]DrawMultipleData = .{
    .{ .x = -16, .y = -5, .char_flags = 0x0dae, .ext = 2 },
    .{ .x = 0, .y = -5, .char_flags = 0x0dc0, .ext = 2 },
    .{ .x = 16, .y = -5, .char_flags = 0x4dae, .ext = 2 },
    .{ .x = -16, .y = 11, .char_flags = 0x0dc2, .ext = 2 },
    .{ .x = 0, .y = 11, .char_flags = 0x0dc4, .ext = 2 },
    .{ .x = 16, .y = 11, .char_flags = 0x4dc2, .ext = 2 },
    .{ .x = -8, .y = 27, .char_flags = 0x0dc6, .ext = 2 },
    .{ .x = 8, .y = 27, .char_flags = 0x4dc6, .ext = 2 },
    .{ .x = -16, .y = -5, .char_flags = 0x0dae, .ext = 2 },
    .{ .x = 0, .y = -5, .char_flags = 0x0dc0, .ext = 2 },
    .{ .x = 16, .y = -5, .char_flags = 0x4dae, .ext = 2 },
    .{ .x = -16, .y = 11, .char_flags = 0x0dc8, .ext = 2 },
    .{ .x = 0, .y = 11, .char_flags = 0x0dc4, .ext = 2 },
    .{ .x = 16, .y = 11, .char_flags = 0x4dc2, .ext = 2 },
    .{ .x = -8, .y = 27, .char_flags = 0x0dc6, .ext = 2 },
    .{ .x = 8, .y = 27, .char_flags = 0x4dc6, .ext = 2 },
    .{ .x = -16, .y = -5, .char_flags = 0x0dae, .ext = 2 },
    .{ .x = 0, .y = -5, .char_flags = 0x0dc0, .ext = 2 },
    .{ .x = 16, .y = -5, .char_flags = 0x4dae, .ext = 2 },
    .{ .x = -16, .y = 11, .char_flags = 0x0dc8, .ext = 2 },
    .{ .x = 0, .y = 11, .char_flags = 0x0dc4, .ext = 2 },
    .{ .x = 16, .y = 11, .char_flags = 0x4dc8, .ext = 2 },
    .{ .x = -8, .y = 27, .char_flags = 0x0dc6, .ext = 2 },
    .{ .x = 8, .y = 27, .char_flags = 0x4dc6, .ext = 2 },
};
pub const kHelmasaurKing_DrawD_Dmd: [19]DrawMultipleData = .{
    .{ .x = -24, .y = -32, .char_flags = 0x0b80, .ext = 2 },
    .{ .x = -8, .y = -32, .char_flags = 0x0b82, .ext = 2 },
    .{ .x = 8, .y = -32, .char_flags = 0x4b82, .ext = 2 },
    .{ .x = 24, .y = -32, .char_flags = 0x4b80, .ext = 2 },
    .{ .x = -24, .y = -16, .char_flags = 0x0b84, .ext = 2 },
    .{ .x = -8, .y = -16, .char_flags = 0x0b86, .ext = 2 },
    .{ .x = 8, .y = -16, .char_flags = 0x4b86, .ext = 2 },
    .{ .x = 24, .y = -16, .char_flags = 0x4b84, .ext = 2 },
    .{ .x = -24, .y = 0, .char_flags = 0x0b88, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x0b8a, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x4b8a, .ext = 2 },
    .{ .x = 24, .y = 0, .char_flags = 0x4b88, .ext = 2 },
    .{ .x = -24, .y = 16, .char_flags = 0x0b8c, .ext = 2 },
    .{ .x = -8, .y = 16, .char_flags = 0x0b8e, .ext = 2 },
    .{ .x = 8, .y = 16, .char_flags = 0x4b8e, .ext = 2 },
    .{ .x = 24, .y = 16, .char_flags = 0x4b8c, .ext = 2 },
    .{ .x = -8, .y = 32, .char_flags = 0x0ba0, .ext = 2 },
    .{ .x = 8, .y = 32, .char_flags = 0x4ba0, .ext = 2 },
    .{ .x = 0, .y = -40, .char_flags = 0x0bac, .ext = 2 },
};
pub const kHelmasaurKing_DrawE_X: [4]i8 = .{ -28, -28, 28, 28 };
pub const kHelmasaurKing_DrawE_Y: [4]i8 = .{ -28, 4, -28, 4 };
pub const kHelmasaurKing_DrawE_Char: [4]u8 = .{ 0xa2, 0xa6, 0xa2, 0xa6 };
pub const kHelmasaurKing_DrawE_Flags: [4]u8 = .{ 0xb, 0xb, 0x4b, 0x4b };
pub const kHelmasaurKing_DrawF_Y: [32]u8 = .{
    1,  2,  3,  4,  5,  6,  7,  8, 9, 10, 10, 10, 10, 10, 10, 10,
    10, 10, 10, 10, 10, 10, 10, 9, 8, 7,  6,  5,  4,  3,  2,  1,
};
pub const kHelmasaurKing_DrawA_Mult: [32]u8 = .{
    0xff, 0xf0, 0xe0, 0xd0, 0xc0, 0xb0, 0xa0, 0x90, 0x80, 0x70, 0x60, 0x50, 0x40, 0x30, 0x20, 0x10,
    0xff, 0xf8, 0xf0, 0xe8, 0xe0, 0xd8, 0xd0, 0xc8, 0xbc, 0xb0, 0xa0, 0x90, 0x70, 0x40, 0x20, 0x10,
};
pub const kHelmasaurKing_DrawA_MultB: [16]u8 = .{ 0xff, 0xf0, 0xe0, 0xd0, 0xc0, 0xb0, 0xa0, 0x90, 0x80, 0x70, 0x60, 0x50, 0x40, 0x30, 0x20, 0x10 };
pub const kMadderBolt_X: [8]i8 = .{ 0, 4, 8, 12, 12, 4, 8, 0 };
pub const kMadderBolt_Y: [8]i8 = .{ 0, 4, 8, 12, 12, 4, 8, 0 };
pub const kPikit_Gfx: [24]u8 = .{
    2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 2, 2, 2, 2,
};
pub const kPikit_XyOffs: [72]i8 = .{
    0,  0,  0,  0,  0,  0,  0,  0,  0,   0,   0,   0,   0,   0,   0,   0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,   0,   0,   0,   0,   0,   0,   0,
    12, 16, 24, 32, 32, 24, 16, 12, 0,   0,   0,   0,   0,   0,   0,   0,
    0,  0,  0,  0,  0,  0,  0,  0,  -12, -16, -24, -32, -32, -24, -16, -12,
    0,  0,  0,  0,  0,  0,  0,  0,
};
pub const kPikit_Tab0: [8]u8 = .{ 24, 24, 0, 48, 48, 48, 0, 24 };
pub const kPikit_Tab1: [8]u8 = .{ 0, 24, 24, 24, 0, 48, 48, 48 };
pub const kBomber_Gfx: [4]u8 = .{ 9, 10, 8, 7 };
pub const kBomber_Xvel: [8]i8 = .{ 16, 12, 0, -12, -16, -12, 0, 12 };
pub const kBomber_Yvel: [8]i8 = .{ 0, 12, 16, 12, 0, -12, -16, -12 };
pub const kBomber_Tab0: [4]u8 = .{ 0, 4, 2, 6 };
pub const kBomber_SpawnPellet_X: [4]i8 = .{ 14, -6, 4, 4 };
pub const kBomber_SpawnPellet_Y: [4]i8 = .{ 7, 7, 12, -4 };
pub const kStalfosBone_Dmd: [8]DrawMultipleData = .{
    .{ .x = -4, .y = -2, .char_flags = 0x802f, .ext = 0 },
    .{ .x = 4, .y = 2, .char_flags = 0x402f, .ext = 0 },
    .{ .x = -4, .y = 2, .char_flags = 0x002f, .ext = 0 },
    .{ .x = 4, .y = -2, .char_flags = 0xc02f, .ext = 0 },
    .{ .x = 2, .y = -4, .char_flags = 0x403f, .ext = 0 },
    .{ .x = -2, .y = 4, .char_flags = 0x803f, .ext = 0 },
    .{ .x = -2, .y = -4, .char_flags = 0x003f, .ext = 0 },
    .{ .x = 2, .y = 4, .char_flags = 0xc03f, .ext = 0 },
};
pub const kStalfos_AnimState2: [4]u8 = .{ 8, 9, 10, 11 };
pub const kStalfos_CheckDir: [4]u8 = .{ 3, 2, 1, 0 };
pub const kStalfos_AnimState1: [8]u8 = .{ 6, 4, 0, 2, 7, 5, 1, 3 };
pub const kStalfos_Delay: [4]u8 = .{ 16, 32, 64, 32 };
pub const kSpawnFirePhlegm_X: [4]i8 = .{ 16, -8, 4, 4 };
pub const kSpawnFirePhlegm_Y: [4]i8 = .{ -2, -2, 8, -20 };
pub const kSpawnFirePhlegm_Xvel: [4]i8 = .{ 48, -48, 0, 0 };
pub const kSpawnFirePhlegm_Yvel: [4]i8 = .{ 0, 0, 48, -48 };
pub const kFirePhlegm_Dmd: [16]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x00c3, .ext = 0 },
    .{ .x = -8, .y = 0, .char_flags = 0x00c2, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x80c3, .ext = 0 },
    .{ .x = -8, .y = 0, .char_flags = 0x80c2, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x40c3, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x40c2, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0xc0c3, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0xc0c2, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x00d4, .ext = 0 },
    .{ .x = 0, .y = -8, .char_flags = 0x00d3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x40d4, .ext = 0 },
    .{ .x = 0, .y = -8, .char_flags = 0x40d3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x80d4, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x80d3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0xc0d4, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0xc0d3, .ext = 0 },
};
pub const kKholdstare_Target_Xvel: [4]i8 = .{ 16, 16, -16, -16 };
pub const kKholdstare_Target_Yvel: [4]i8 = .{ -16, 16, 16, -16 };
pub const kKholdstare_Triplicate_Tab0: [3]i8 = .{ 32, -32, 0 };
pub const kKholdstare_Triplicate_Tab1: [3]i8 = .{ -32, -32, 48 };
pub const kNebuleGarnish_XY: [8]i8 = .{ -8, -6, -4, -2, 0, 2, 4, 6 };
pub const kIceBall_Quadruplicate_Xvel: [8]i8 = .{ 0, 32, 0, -32, 24, 24, -24, -24 };
pub const kIceBall_Quadruplicate_Yvel: [8]i8 = .{ -32, 0, 32, 0, -24, 24, -24, 24 };
pub const kFreezor_Xvel: [4]i8 = .{ 8, -8, 0, 0 };
pub const kFreezor_Yvel: [4]i8 = .{ 0, 0, 18, -18 };
pub const kFreezor_Moving_Gfx: [4]u8 = .{ 1, 2, 1, 3 };
pub const kFreezor_Sparkle_X: [8]i8 = .{ -4, -2, 0, 2, 4, 6, 8, 10 };
pub const kFreezor_Melting_Gfx: [4]u8 = .{ 6, 5, 4, 7 };
pub const kFluteBoyOstrich_Gfx: [4]u8 = .{ 0, 1, 0, 2 };
pub const kFluteBoyOstrich_Dmd: [16]DrawMultipleData = .{
    .{ .x = -4, .y = -8, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x0081, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x00a3, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x0081, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x00a1, .ext = 2 },
    .{ .x = -4, .y = -8, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x0081, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x0083, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x0084, .ext = 2 },
    .{ .x = -4, .y = -7, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 4, .y = -7, .char_flags = 0x0081, .ext = 2 },
    .{ .x = -4, .y = 9, .char_flags = 0x00a3, .ext = 2 },
    .{ .x = 4, .y = 9, .char_flags = 0x00a4, .ext = 2 },
};
pub const kFluteBoyBird_X: [2]i8 = .{ 8, 0 };
pub const kBabusu_Gfx: [6]u8 = .{ 5, 4, 3, 2, 1, 0 };
pub const kBabusu_DirGfx: [4]u8 = .{ 6, 6, 0, 0 };
pub const kBabusu_XyVel: [6]i8 = .{ 32, -32, 0, 0, 32, -32 };
pub const kBabusu_Scurry_Gfx: [4]u8 = .{ 18, 14, 12, 16 };
pub const kWizzrobe_Cloak_Gfx: [4]u8 = .{ 4, 2, 0, 6 };
pub const kWizzrobe_Attack_Gfx: [8]u8 = .{ 0, 1, 1, 1, 1, 1, 1, 0 };
pub const kWizzrobe_Attack_DirGfx: [4]u8 = .{ 4, 2, 0, 6 };
pub const kWizzrobe_Beam_XYvel: [6]i8 = .{ 32, -32, 0, 0, 32, -32 };
pub const kKyameron_Coagulate_Gfx: [8]i8 = .{ 4, 7, 14, 13, 12, 6, 6, 5 };
pub const kKyameron_Xvel: [4]i8 = .{ 32, -32, 32, -32 };
pub const kKyameron_Yvel: [4]i8 = .{ 32, 32, -32, -32 };
pub const kKyameron_Moving_Gfx: [4]u8 = .{ 3, 2, 1, 0 };
pub const kKyameron_OamFlags: [12]u8 = .{ 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0x40, 0xc0, 0x80 };
pub const kKyameron_Dmd: [28]DrawMultipleData = .{
    .{ .x = 1, .y = 8, .char_flags = 0x00b4, .ext = 0 },
    .{ .x = 7, .y = 8, .char_flags = 0x00b5, .ext = 0 },
    .{ .x = 4, .y = -3, .char_flags = 0x0086, .ext = 0 },
    .{ .x = 0, .y = -13, .char_flags = 0x80a2, .ext = 2 },
    .{ .x = 2, .y = 8, .char_flags = 0x00b4, .ext = 0 },
    .{ .x = 6, .y = 8, .char_flags = 0x00b5, .ext = 0 },
    .{ .x = 4, .y = -6, .char_flags = 0x0096, .ext = 0 },
    .{ .x = 0, .y = -20, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = 4, .y = -1, .char_flags = 0x0096, .ext = 0 },
    .{ .x = 0, .y = -27, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = 0, .y = -27, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = 0, .y = -27, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = -6, .y = -6, .char_flags = 0x01df, .ext = 0 },
    .{ .x = 14, .y = -6, .char_flags = 0x41df, .ext = 0 },
    .{ .x = -6, .y = 14, .char_flags = 0x81df, .ext = 0 },
    .{ .x = 14, .y = 14, .char_flags = 0xc1df, .ext = 0 },
    .{ .x = -6, .y = -6, .char_flags = 0x0096, .ext = 0 },
    .{ .x = 14, .y = -6, .char_flags = 0x4096, .ext = 0 },
    .{ .x = -6, .y = 14, .char_flags = 0x8096, .ext = 0 },
    .{ .x = 14, .y = 14, .char_flags = 0xc096, .ext = 0 },
    .{ .x = -4, .y = -4, .char_flags = 0x018d, .ext = 0 },
    .{ .x = 12, .y = -4, .char_flags = 0x418d, .ext = 0 },
    .{ .x = -4, .y = 12, .char_flags = 0x818d, .ext = 0 },
    .{ .x = 12, .y = 12, .char_flags = 0xc18d, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x018d, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x418d, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x818d, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0xc18d, .ext = 0 },
};
pub const kPengator_Gfx: [4]u8 = .{ 5, 0, 10, 15 };
pub const kPengator_XYVel: [6]i8 = .{ 1, -1, 0, 0, 1, -1 };
pub const kPengator_Jump: [4]u8 = .{ 4, 4, 3, 2 };
pub const kPengator_Garnish_Y: [8]i8 = .{ 8, 10, 12, 14, 12, 12, 12, 12 };
pub const kPengator_Garnish_X: [8]i8 = .{ 4, 4, 4, 4, 0, 4, 8, 12 };
pub const kPengator_Dmd0: [40]DrawMultipleData = .{
    .{ .x = -1, .y = -8, .char_flags = 0x0082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0088, .ext = 2 },
    .{ .x = -1, .y = -7, .char_flags = 0x0082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x008a, .ext = 2 },
    .{ .x = -3, .y = -6, .char_flags = 0x0082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0088, .ext = 2 },
    .{ .x = -6, .y = -4, .char_flags = 0x0082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x008a, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x00a3, .ext = 2 },
    .{ .x = 1, .y = -8, .char_flags = 0x4082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4088, .ext = 2 },
    .{ .x = 1, .y = -7, .char_flags = 0x4082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x408a, .ext = 2 },
    .{ .x = 3, .y = -6, .char_flags = 0x4082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4088, .ext = 2 },
    .{ .x = 6, .y = -4, .char_flags = 0x4082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x408a, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x40a2, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x40a3, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x4080, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4086, .ext = 2 },
    .{ .x = 0, .y = -4, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = -1, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0086, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x408e, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4084, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x408c, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x408c, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x4084, .ext = 2 },
    .{ .x = -8, .y = 0, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 8, .y = 0, .char_flags = 0x40a0, .ext = 2 },
};
pub const kPengator_Dmd1: [4]DrawMultipleData = .{
    .{ .x = 0, .y = 16, .char_flags = 0x00b5, .ext = 0 },
    .{ .x = 8, .y = 16, .char_flags = 0x40b5, .ext = 0 },
    .{ .x = 0, .y = -8, .char_flags = 0x00a5, .ext = 0 },
    .{ .x = 8, .y = -8, .char_flags = 0x40a5, .ext = 0 },
};
pub const kLaserEye_Dirs: [4]u8 = .{ 2, 3, 0, 1 };
pub const kLaserEye_SpawnXY: [6]i8 = .{ 12, -4, 4, 4, 12, -4 };
pub const kLaserEye_SpawnXYVel: [6]i8 = .{ 112, -112, 0, 0, 112, -112 };
pub const kLaserEye_Dmd: [24]DrawMultipleData = .{
    .{ .x = 8, .y = -4, .char_flags = 0x40c8, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x40d8, .ext = 0 },
    .{ .x = 8, .y = 12, .char_flags = 0xc0c8, .ext = 0 },
    .{ .x = 8, .y = -4, .char_flags = 0x40c9, .ext = 0 },
    .{ .x = 8, .y = 4, .char_flags = 0x40d9, .ext = 0 },
    .{ .x = 8, .y = 12, .char_flags = 0xc0c9, .ext = 0 },
    .{ .x = 0, .y = -4, .char_flags = 0x00c8, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x00d8, .ext = 0 },
    .{ .x = 0, .y = 12, .char_flags = 0x80c8, .ext = 0 },
    .{ .x = 0, .y = -4, .char_flags = 0x00c9, .ext = 0 },
    .{ .x = 0, .y = 4, .char_flags = 0x00d9, .ext = 0 },
    .{ .x = 0, .y = 12, .char_flags = 0x80c9, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0x00d6, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x00d7, .ext = 0 },
    .{ .x = 12, .y = 8, .char_flags = 0x40d6, .ext = 0 },
    .{ .x = -4, .y = 8, .char_flags = 0x00c6, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x00c7, .ext = 0 },
    .{ .x = 12, .y = 8, .char_flags = 0x40c6, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x80d6, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x80d7, .ext = 0 },
    .{ .x = 12, .y = 0, .char_flags = 0xc0d6, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x80c6, .ext = 0 },
    .{ .x = 4, .y = 0, .char_flags = 0x80c7, .ext = 0 },
    .{ .x = 12, .y = 0, .char_flags = 0xc0c6, .ext = 0 },
};
pub const kPirogusu_A0: [4]u8 = .{ 2, 3, 0, 1 };
pub const kPirogusu_A1: [8]u8 = .{ 9, 11, 5, 7, 5, 11, 7, 9 };
pub const kPirogusu_A2: [8]u8 = .{ 16, 17, 18, 19, 12, 13, 14, 15 };
pub const kPirogusu_XYvel: [6]i8 = .{ 0, 0, 4, -4, 0, 0 };
pub const kPirogusu_XYvel2: [6]i8 = .{ 2, -2, 0, 0, 2, -2 };
pub const kPirogusu_XYvel3: [6]i8 = .{ 24, -24, 0, 0, 24, -24 };
pub const kPirogusu_Dir: [8]u8 = .{ 2, 3, 2, 3, 0, 1, 0, 1 };
pub const kPirogusu_Tab0: [4]u8 = .{ 3, 4, 5, 4 };
pub const kPirogusu_OamFlags: [28]u8 = .{
    0,    0x80, 0x40, 0,    0, 0,    0,    0x80, 0x80, 0xc0, 0x40, 0x40, 0, 0x40, 0x80, 0xc0,
    0x40, 0xc0, 0,    0x80, 0, 0x40, 0x80, 0xc0, 0x40, 0xc0, 0,    0x80,
};
pub const kPirogusu_Gfx: [28]u8 = .{
    0, 0, 1, 1, 2, 3, 4, 3, 2, 3, 4, 3, 5, 5, 5, 5,
    7, 7, 7, 7, 6, 6, 6, 6, 8, 8, 8, 8,
};
pub const kBumper_Vels: [4]i8 = .{ 0, 2, -2, 0 };
pub const kBumper_Dmd: [8]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x00ec, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x40ec, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x80ec, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0xc0ec, .ext = 2 },
    .{ .x = -7, .y = -7, .char_flags = 0x00ec, .ext = 2 },
    .{ .x = 7, .y = -7, .char_flags = 0x40ec, .ext = 2 },
    .{ .x = -7, .y = 7, .char_flags = 0x80ec, .ext = 2 },
    .{ .x = 7, .y = 7, .char_flags = 0xc0ec, .ext = 2 },
};
pub const kStalfosKnight_Case2_Gfx: [2]u8 = .{ 0, 1 };
pub const kStalfosKnight_Case2_Dir: [16]u8 = .{ 0, 0, 0, 2, 1, 1, 1, 2, 0, 0, 0, 2, 1, 1, 1, 2 };
pub const kStalfosKnight_Case6_C: [32]u8 = .{
    0,  4,  8,  12, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
    14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 15, 14, 12, 8,  4,  0,
};
pub const kStalfosKnight_Case7_Gfx: [2]u8 = .{ 1, 4 };
pub const kStalfosKnight_Dmd: [35]DrawMultipleData = .{
    .{ .x = -4, .y = -8, .char_flags = 0x0064, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x0061, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x0062, .ext = 2 },
    .{ .x = -3, .y = 16, .char_flags = 0x0074, .ext = 0 },
    .{ .x = 11, .y = 16, .char_flags = 0x4074, .ext = 0 },
    .{ .x = -4, .y = -7, .char_flags = 0x0064, .ext = 0 },
    .{ .x = -4, .y = 1, .char_flags = 0x0061, .ext = 2 },
    .{ .x = 4, .y = 1, .char_flags = 0x0062, .ext = 2 },
    .{ .x = -3, .y = 16, .char_flags = 0x0065, .ext = 0 },
    .{ .x = 11, .y = 16, .char_flags = 0x4065, .ext = 0 },
    .{ .x = -4, .y = -8, .char_flags = 0x0048, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x0049, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x004b, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x004c, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x004c, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x0068, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x0069, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x0069, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x0069, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x0069, .ext = 2 },
    .{ .x = 12, .y = -7, .char_flags = 0x4064, .ext = 0 },
    .{ .x = -4, .y = 1, .char_flags = 0x4062, .ext = 2 },
    .{ .x = 4, .y = 1, .char_flags = 0x4061, .ext = 2 },
    .{ .x = -3, .y = 16, .char_flags = 0x0065, .ext = 0 },
    .{ .x = 11, .y = 16, .char_flags = 0x4065, .ext = 0 },
    .{ .x = 12, .y = -8, .char_flags = 0x4064, .ext = 0 },
    .{ .x = -4, .y = 0, .char_flags = 0x4062, .ext = 2 },
    .{ .x = 4, .y = 0, .char_flags = 0x4061, .ext = 2 },
    .{ .x = -3, .y = 16, .char_flags = 0x0074, .ext = 0 },
    .{ .x = 11, .y = 16, .char_flags = 0x4074, .ext = 0 },
    .{ .x = -4, .y = -8, .char_flags = 0x4049, .ext = 2 },
    .{ .x = 4, .y = -8, .char_flags = 0x4048, .ext = 2 },
    .{ .x = -4, .y = 8, .char_flags = 0x404c, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x404b, .ext = 2 },
    .{ .x = 4, .y = 8, .char_flags = 0x404b, .ext = 2 },
};
pub const kStalfosKnight_DrawHead_Char: [4]u8 = .{ 0x66, 0x66, 0x46, 0x46 };
pub const kStalfosKnight_DrawHead_Flags: [4]u8 = .{ 0x40, 0, 0, 0 };
pub const kWallMaster_Dmd: [8]DrawMultipleData = .{
    .{ .x = -4, .y = 0, .char_flags = 0x01a6, .ext = 2 },
    .{ .x = 12, .y = 0, .char_flags = 0x01aa, .ext = 0 },
    .{ .x = -4, .y = 16, .char_flags = 0x01ba, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x01a8, .ext = 2 },
    .{ .x = -4, .y = 0, .char_flags = 0x01ab, .ext = 2 },
    .{ .x = 12, .y = 0, .char_flags = 0x01af, .ext = 0 },
    .{ .x = -4, .y = 16, .char_flags = 0x01bf, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x01ad, .ext = 2 },
};
pub const kZol_PoppingOutGfx: [16]i8 = .{ 0, 1, 7, 7, 6, 6, 5, 5, 6, 6, 5, 5, 4, 4, 4, 4 };
pub const kZol_FallingXvel: [2]i8 = .{ -8, 8 };
pub const kZol_FallingGfx: [2]i8 = .{ 0, 1 };
pub const kZol_OamFlags: [4]u8 = .{ 0, 0, 0x40, 0x40 };
pub const kZol_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = 8, .char_flags = 0x036c, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x036d, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x0060, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x0070, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x4070, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0x4060, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0040, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0040, .ext = 2 },
};
pub const kTerrorpin_Xvel: [8]i8 = .{ 8, -8, 0, 0, 12, -12, 0, 0 };
pub const kTerrorpin_Yvel: [8]i8 = .{ 0, 0, 8, -8, 0, 0, 12, -12 };
pub const kTerrorpin_Oamflags: [2]u8 = .{ 0, 0x40 };
pub const kTerrorpin_Overturned_Xvel: [2]i8 = .{ 8, -8 };
pub const kArrghus_Gfx: [9]u8 = .{ 1, 1, 1, 2, 2, 1, 1, 0, 0 };
pub const kArrghus_Dmd: [5]DrawMultipleData = .{
    .{ .x = -8, .y = -4, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 8, .y = -4, .char_flags = 0x4080, .ext = 2 },
    .{ .x = -8, .y = 12, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 8, .y = 12, .char_flags = 0x40a0, .ext = 2 },
    .{ .x = 0, .y = 24, .char_flags = 0x00a8, .ext = 2 },
};
pub const kArrgi_Tab0: [13]u16 = .{ 0, 0x40, 0x80, 0xc0, 0x100, 0x140, 0x180, 0x1c0, 0, 0x66, 0xcc, 0x132, 0x198 };
pub const kArrgi_Tab1: [13]u16 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0x1ff, 0x1ff, 0x1ff, 0x1ff, 0x1ff };
pub const kArrgi_Tab2: [13]u8 = .{ 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0xc, 0xc, 0xc, 0xc, 0xc };
pub const kArrgi_Tab3: [52]i8 = .{
    0,  -1, -2, -3, -4, -5, -6, -6, -5, -4, -3, -2, -1, 0,  -1, -2,
    -3, -4, -5, -6, -6, -5, -4, -3, -2, -1, 0,  -1, -2, -3, -4, -5,
    -6, -6, -5, -4, -3, -2, -1, 0,  -1, -2, -3, -4, -5, -6, -6, -5,
    -4, -3, -2, -1,
};
pub const kArrgi_Gfx: [8]u8 = .{ 0, 1, 2, 2, 2, 2, 2, 1 };
pub const kGibdo_DirTarget: [4]u8 = .{ 2, 6, 4, 0 };
pub const kGibdo_Gfx: [8]u8 = .{ 4, 8, 11, 10, 0, 6, 3, 7 };
pub const kGibdo_XyVel: [10]i8 = .{ -16, 0, 0, 0, 16, 0, 0, 0, -16, 0 };
pub const kGibdo_Gfx2: [8]u8 = .{ 9, 2, 0, 4, 11, 3, 1, 5 };
pub const kGibdo_Dmd: [24]DrawMultipleData = .{
    .{ .x = 0, .y = -9, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0080, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x408a, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x0082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x0084, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x40a0, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x0086, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x0088, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x4088, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a4, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x4082, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x408c, .ext = 2 },
    .{ .x = 0, .y = -9, .char_flags = 0x4086, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x40a2, .ext = 2 },
    .{ .x = 0, .y = -8, .char_flags = 0x4082, .ext = 2 },
    .{ .x = 0, .y = 1, .char_flags = 0x408e, .ext = 2 },
};
pub const kFlyingTile_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x00d3, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x40d3, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x80d3, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0xc0d3, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x00c3, .ext = 0 },
    .{ .x = 8, .y = 0, .char_flags = 0x40c3, .ext = 0 },
    .{ .x = 0, .y = 8, .char_flags = 0x80c3, .ext = 0 },
    .{ .x = 8, .y = 8, .char_flags = 0xc0c3, .ext = 0 },
};
pub const kSpikeBlock_XVelTarget: [4]i8 = .{ 32, -32, 0, 0 };
pub const kSpikeBlock_YVelTarget: [4]i8 = .{ 0, 0, 32, -32 };
pub const kSpikeBlock_XVelDelta: [4]i8 = .{ 1, -1, 0, 0 };
pub const kSpikeBlock_YVelDelta: [4]i8 = .{ 0, 0, 1, -1 };
pub const kSpikeBlock_XVel: [4]i8 = .{ -16, 16, 0, 0 };
pub const kSpikeBlock_YVel: [4]i8 = .{ 0, 0, -16, 16 };
pub const kMothula_XYvel: [10]i8 = .{ -16, -12, 0, 12, 16, 12, 0, -12, -16, -12 };
pub const kMothula_FlapWingsGfx: [4]u8 = .{ 0, 1, 2, 1 };
pub const kMothula_Beam_Xvel: [3]i8 = .{ -16, 0, 16 };
pub const kMothula_Beam_Yvel: [3]i8 = .{ 24, 32, 24 };
pub const kMothula_Spike_XLo: [30]u8 = .{
    0x38, 0x48, 0x58, 0x68, 0x88, 0x98, 0xa8, 0xb8, 0xc8, 0xc8, 0xc8, 0xc8, 0xc8, 0xc8, 0xc8, 0xb8,
    0xa8, 0x98, 0x78, 0x68, 0x58, 0x48, 0x38, 0x28, 0x28, 0x28, 0x28, 0x28, 0x28, 0x28,
};
pub const kMothula_Spike_YLo: [30]u8 = .{
    0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x38, 0x48, 0x58, 0x68, 0x78, 0x98, 0xa8, 0xb8, 0xc8,
    0xc8, 0xc8, 0xc8, 0xc8, 0xc8, 0xc8, 0xc8, 0xb8, 0xa8, 0x98, 0x78, 0x68, 0x58, 0x48,
};
pub const kMothula_Spike_Dir: [30]u8 = .{
    2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 3,
    3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0,
};
pub const kKodondo_Xvel: [4]i8 = .{ 1, -1, 0, 0 };
pub const kKodondo_Yvel: [4]i8 = .{ 0, 0, 1, -1 };
pub const kKodondo_Gfx: [8]u8 = .{ 2, 2, 0, 5, 3, 3, 0, 5 };
pub const kKodondo_OamFlags: [8]u8 = .{ 0x40, 0, 0, 0, 0x40, 0, 0x40, 0x40 };
pub const kKodondo_FlameGfx: [8]u8 = .{ 2, 2, 0, 5, 4, 4, 1, 6 };
pub const kKodondo_Flame_X: [4]i8 = .{ 8, -8, 0, 0 };
pub const kKodondo_Flame_Y: [4]i8 = .{ 0, 0, 8, -8 };
pub const kKodondo_Flame_Xvel: [4]i8 = .{ 24, -24, 0, 0 };
pub const kKodondo_Flame_Yvel: [4]i8 = .{ 0, 0, 24, -24 };
pub const kFlame_OamFlags: [4]u8 = .{ 0, 0x40, 0xc0, 0x80 };
pub const kFlame_Gfx: [32]i8 = .{
    5, 4, 3, 1, 2, 0, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0,
    1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0,
};
pub const kFlame_Dmd: [12]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x018e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x018e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x01a0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x01a0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x418e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x418e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x41a0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x41a0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x01a2, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x01a2, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x01a4, .ext = 0 },
    .{ .x = 8, .y = -6, .char_flags = 0x01a5, .ext = 0 },
};
pub const kYellowStalfos_ObjPrio: [6]i8 = .{ 0x30, 0, 0, 0, 0x30, 0 };
pub const kYellowStalfos_Gfx: [32]i8 = .{
    8, 5, 1, 1, 8, 5, 1, 1, 8, 5, 1, 1, 7, 4, 2, 2,
    7, 4, 2, 2, 7, 4, 2, 2, 7, 4, 2, 2, 7, 4, 2, 2,
};
pub const kYellowStalfos_HeadX: [32]i8 = .{
    -0x80, -0x80, -0x80, -0x80, -0x80, -0x80, -0x80, -0x80, -0x80, -0x80, -0x80, -0x80, 0, 0, 0, 0,
    0,     0,     0,     0,     -1,    0,     1,     0,     -1,    0,     1,     0,     0, 0, 0, 0,
};
pub const kYellowStalfos_HeadY: [32]u8 = .{
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 12, 11, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
};
pub const kYellowStalfos_NeutralizedGfx: [16]i8 = .{ 1, 1, 1, 9, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 9 };
pub const kYellowStalfos_NeutralizedHeadY: [16]i8 = .{ 10, 10, 10, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7 };
pub const kYellowStalfos_Gfx2: [4]u8 = .{ 6, 3, 1, 1 };
pub const kYellowStalfos_Dmd: [22]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x002c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x002c, .ext = 2 },
    .{ .x = 5, .y = 5, .char_flags = 0x002e, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0024, .ext = 2 },
    .{ .x = 4, .y = 1, .char_flags = 0x003e, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x0024, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x000e, .ext = 2 },
    .{ .x = 3, .y = 5, .char_flags = 0x402e, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x4024, .ext = 2 },
    .{ .x = 4, .y = 1, .char_flags = 0x403e, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x4024, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x400e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x400e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x002a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x002a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x002a, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x002a, .ext = 2 },
};
pub const kYellowStalfos_Head_Char: [4]u8 = .{ 2, 2, 0, 4 };
pub const kYellowStalfos_Head_Flags: [4]u8 = .{ 0x40, 0, 0, 0 };
pub const kGoriya_Xvel: [32]i8 = .{
    0, 16,  -16, 0, 0, 13,  -13, 0, 0, 13,  -13, 0, 0, 0, 0, 0,
    0, -24, 24,  0, 0, -16, 16,  0, 0, -16, 16,  0, 0, 0, 0, 0,
};
pub const kGoriya_Yvel: [32]i8 = .{
    0, 0, 0, 0, -16, -5,  -5,  0, 16, 13, 13, 0, 0, 0, 0, 0,
    0, 0, 0, 0, -24, -16, -16, 0, 24, 16, 16, 0, 0, 0, 0, 0,
};
pub const kGoriya_Dir: [32]u8 = .{
    0, 0, 1, 0, 3, 3, 3, 0, 2, 2, 2, 0, 0, 0, 0, 0,
    0, 1, 0, 0, 3, 3, 3, 0, 2, 2, 2, 0, 0, 0, 0, 0,
};
pub const kGoriya_Gfx: [16]u8 = .{ 8, 6, 0, 3, 9, 7, 1, 4, 8, 6, 0, 3, 9, 7, 2, 5 };
pub const kEyeGore_Closing_Gfx: [8]u8 = .{ 0, 0, 1, 1, 2, 2, 2, 2 };
pub const kEyeGore_Opening_Gfx: [8]u8 = .{ 2, 2, 2, 2, 1, 1, 0, 0 };
pub const kEyeGore_Chasing_Gfx: [16]u8 = .{ 7, 5, 2, 9, 8, 6, 3, 10, 7, 5, 2, 9, 8, 6, 4, 11 };
pub const kEyeGore_Opening_Delay: [4]u8 = .{ 0x60, 0x80, 0xa0, 0x80 };
pub const kEyeGore_Dmd: [48]DrawMultipleData = .{
    .{ .x = -4, .y = -4, .char_flags = 0x00a2, .ext = 2 },
    .{ .x = 4, .y = -4, .char_flags = 0x40a2, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0x009c, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0x409c, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x00a4, .ext = 2 },
    .{ .x = 4, .y = -4, .char_flags = 0x40a4, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0x009c, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0x409c, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 4, .y = -4, .char_flags = 0x408c, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0x009c, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0x409c, .ext = 2 },
    .{ .x = -4, .y = -3, .char_flags = 0x008c, .ext = 2 },
    .{ .x = 12, .y = -3, .char_flags = 0x408c, .ext = 0 },
    .{ .x = -4, .y = 13, .char_flags = 0x00bc, .ext = 0 },
    .{ .x = 4, .y = 5, .char_flags = 0x408a, .ext = 2 },
    .{ .x = -4, .y = -3, .char_flags = 0x008c, .ext = 0 },
    .{ .x = 4, .y = -3, .char_flags = 0x408c, .ext = 2 },
    .{ .x = -4, .y = 5, .char_flags = 0x008a, .ext = 2 },
    .{ .x = 12, .y = 13, .char_flags = 0x40bc, .ext = 0 },
    .{ .x = 0, .y = -4, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 0, .y = 4, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 0, .y = -4, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 0, .y = 4, .char_flags = 0x00a6, .ext = 2 },
    .{ .x = 0, .y = -3, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 0, .y = 4, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = 0, .y = -3, .char_flags = 0x00aa, .ext = 2 },
    .{ .x = 0, .y = 4, .char_flags = 0x00a8, .ext = 2 },
    .{ .x = 0, .y = -4, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = 0, .y = 4, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = 0, .y = -4, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = 0, .y = 4, .char_flags = 0x40a6, .ext = 2 },
    .{ .x = 0, .y = -3, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = 0, .y = 4, .char_flags = 0x40a8, .ext = 2 },
    .{ .x = 0, .y = -3, .char_flags = 0x40aa, .ext = 2 },
    .{ .x = 0, .y = 4, .char_flags = 0x40a8, .ext = 2 },
    .{ .x = -4, .y = -4, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 4, .y = -4, .char_flags = 0x408e, .ext = 2 },
    .{ .x = -4, .y = 4, .char_flags = 0x009e, .ext = 2 },
    .{ .x = 4, .y = 4, .char_flags = 0x409e, .ext = 2 },
    .{ .x = -4, .y = -3, .char_flags = 0x008e, .ext = 2 },
    .{ .x = 12, .y = -3, .char_flags = 0x408e, .ext = 0 },
    .{ .x = -4, .y = 13, .char_flags = 0x00bd, .ext = 0 },
    .{ .x = 4, .y = 5, .char_flags = 0x40a0, .ext = 2 },
    .{ .x = -4, .y = -3, .char_flags = 0x008e, .ext = 0 },
    .{ .x = 4, .y = -3, .char_flags = 0x408e, .ext = 2 },
    .{ .x = -4, .y = 5, .char_flags = 0x00a0, .ext = 2 },
    .{ .x = 12, .y = 13, .char_flags = 0x40bd, .ext = 0 },
};
pub const kBubbleGroup_X: [3]i8 = .{ 10, 20, 10 };
pub const kBubbleGroup_Y: [3]i8 = .{ -10, 0, 10 };
pub const kBubbleGroup_Xvel: [3]i8 = .{ 18, 0, -18 };
pub const kBubbleGroup_Yvel: [3]i8 = .{ 0, 18, 0 };
pub const kBubbleGroup_A: [3]i8 = .{ 1, 1, 0 };
pub const kBubbleGroup_B: [3]i8 = .{ 0, 1, 1 };
pub const kBubbleGroup_Vel: [2]i8 = .{ 1, -1 };
pub const kBubbleGroup_VelTarget: [2]u8 = .{ 18, 238 };
pub const kHover_OamFlags: [4]i8 = .{ 0x40, 0, 0x40, 0 };
pub const kHover_AccelX0: [4]i8 = .{ 1, -1, 1, -1 };
pub const kHover_AccelY0: [4]i8 = .{ 1, 1, -1, -1 };
pub const kHover_AccelX1: [4]i8 = .{ -1, 1, -1, 1 };
pub const kHover_AccelY1: [4]i8 = .{ -1, -1, 1, 1 };
pub const kCrystalMaiden_Msgs: [9]u16 = .{ 0x133, 0x132, 0x137, 0x134, 0x136, 0x132, 0x135, 0x138, 0x13c };
pub const kSpikeTrap_Xvel: [4]i8 = .{ 32, -32, 0, 0 };
pub const kSpikeTrap_Xvel2: [4]i8 = .{ -16, 16, 0, 0 };
pub const kSpikeTrap_Yvel: [4]i8 = .{ 0, 0, 32, -32 };
pub const kSpikeTrap_Yvel2: [4]i8 = .{ 0, 0, -16, 16 };
pub const kSpikeTrap_Delay: [4]u8 = .{ 0x40, 0x40, 0x38, 0x38 };
pub const kSpikeTrap_Dmd: [4]DrawMultipleData = .{
    .{ .x = -8, .y = -8, .char_flags = 0x00c4, .ext = 2 },
    .{ .x = 8, .y = -8, .char_flags = 0x40c4, .ext = 2 },
    .{ .x = -8, .y = 8, .char_flags = 0x80c4, .ext = 2 },
    .{ .x = 8, .y = 8, .char_flags = 0xc0c4, .ext = 2 },
};
pub const kGuruguruBar_incr: [4]i8 = .{ -2, 2, -1, 1 };
pub const kWinder_OamFlags: [4]u8 = .{ 0, 0x40, 0x80, 0xc0 };
pub const kWinder_Xvel: [4]i8 = .{ 24, -24, 0, 0 };
pub const kWinder_Yvel: [4]i8 = .{ 0, 0, 24, -24 };
pub const kGreenStalfos_Dir: [4]u8 = .{ 4, 6, 0, 2 };
pub const kGreenStalfos_OamFlags: [4]u8 = .{ 0x40, 0, 0, 0 };
pub const kGreenStalfos_Gfx: [4]u8 = .{ 0, 0, 1, 2 };
pub const kAgahnim_StartState: [2]u8 = .{ 1, 6 };
pub const kAgahnim_Gfx0: [5]u8 = .{ 12, 13, 14, 15, 16 };
pub const kAgahnim_Tab5: [2]i8 = .{ 32, -32 };
pub const kAgahnim_Tab6: [2]u8 = .{ 9, 11 };
pub const kAgahnim_Dir: [25]u8 = .{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 0, 1, 1, 4,
    4, 0, 2, 2, 4, 4, 3, 2, 2,
};
pub const kAgahnim_Gfx1: [6]u8 = .{ 2, 10, 8, 0, 4, 6 };
pub const kAgahnim_Tab0: [16]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0 };
pub const kAgahnim_Tab1: [16]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 6, 5, 4, 3, 2, 1, 0, 0, 0 };
pub const kAgahnim_Tab2: [6]u8 = .{ 30, 24, 12, 0, 6, 18 };
pub const kAgahnim_Gfx2: [5]u8 = .{ 16, 15, 14, 13, 12 };
pub const kAgahnim_Tab3: [16]u8 = .{ 0x38, 0x38, 0x38, 0x58, 0x78, 0x98, 0xb8, 0xb8, 0xb8, 0x98, 0x58, 0x58, 0x60, 0x90, 0x98, 0x78 };
pub const kAgahnim_Tab4: [16]u8 = .{ 0xb8, 0x78, 0x58, 0x48, 0x48, 0x48, 0x58, 0x78, 0xb8, 0xb8, 0xb8, 0x90, 0x70, 0x70, 0x90, 0xa0 };
pub const kAgahnim_Gfx3: [7]u8 = .{ 0, 8, 10, 2, 2, 6, 4 };
pub const kAgahnim_X0: [6]i8 = .{ 0, 10, 8, 0, -10, -10 };
pub const kAgahnim_Y0: [6]i8 = .{ -9, -2, -2, -9, -2, -2 };
pub const kAgahnim_Draw_X0: [72]i8 = .{
    -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8,
    -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8,
    -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8, -8, 8,
    -8, 8, -8, 8, -6, 6, -6, 6, -8, 8, -8, 8, -6, 6, -6, 6,
    0,  8, 0,  8, -8, 8, -8, 8,
};
pub const kAgahnim_Draw_Y0: [72]i8 = .{
    -8, -8, 8, 8, -8, -8, 8, 8, -8, -8, 8, 8, -8, -8, 8, 8,
    -8, -8, 8, 8, -8, -8, 8, 8, -8, -8, 8, 8, -8, -8, 8, 8,
    -8, -8, 8, 8, -8, -8, 8, 8, -8, -8, 8, 8, -8, -8, 8, 8,
    -8, -8, 8, 8, -6, -6, 6, 6, -8, -8, 8, 8, -6, -6, 6, 6,
    0,  0,  8, 8, 8,  8,  8, 8,
};
pub const kAgahnim_Draw_Char0: [72]u8 = .{
    0x82, 0x82, 0xa2, 0xa2, 0x80, 0x80, 0xa0, 0xa0, 0x84, 0x84, 0xa4, 0xa4, 0x86, 0x86, 0xa6, 0xa6,
    0x88, 0x8a, 0xa8, 0xaa, 0x8c, 0x8e, 0xac, 0xae, 0xc4, 0xc2, 0xe4, 0xe6, 0xc0, 0xc2, 0xe0, 0xe2,
    0x8a, 0x88, 0xaa, 0xa8, 0x8e, 0x8c, 0xae, 0xac, 0xc2, 0xc4, 0xe6, 0xe4, 0xc2, 0xc0, 0xe2, 0xe0,
    0xec, 0xec, 0xec, 0xec, 0xec, 0xec, 0xec, 0xec, 0xee, 0xee, 0xee, 0xee, 0xee, 0xee, 0xee, 0xee,
    0xdf, 0xdf, 0xdf, 0xdf, 0x40, 0x42, 0x40, 0x42,
};
pub const kAgahnim_Draw_Flags0: [72]u8 = .{
    0,    0x40, 0,    0x40, 0,    0x40, 0,    0x40, 0,    0x40, 0,    0x40, 0,    0x40, 0,    0x40,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,
    0,    0x40, 0x80, 0xc0, 0,    0x40, 0x80, 0xc0, 0,    0x40, 0x80, 0xc0, 0,    0x40, 0x80, 0xc0,
    0,    0x40, 0x80, 0xc0, 0,    0,    0,    0,
};
pub const kAgahnim_Draw_X1: [72]i8 = .{
    -7,  15, -11, 11, -11, 11, -8,  8,   -4,  4,   0,   0,   -10, -1,  -14, -5,
    -14, -5, -12, -7, -10, -7, -10, -10, 16,  8,   12,  4,   12,  4,   10,  6,
    9,   7,  8,   8,  -6,  -6, -10, -10, -10, -10, -10, -10, -10, -10, -10, -10,
    14,  14, 10,  10, 10,  10, 10,  10,  10,  10,  10,  10,  -7,  15,  -11, 11,
    -11, 11, -8,  8,  -4,  4,  0,   0,
};
pub const kAgahnim_Draw_Y1: [72]i8 = .{
    -5, -5, -9, -9, -9, -9, -9, -9, -9, -9, -9, -9, -3, 9,  -7, 5,
    -7, 5,  -5, 3,  -3, 3,  -2, -2, -3, 9,  -7, 5,  -7, 5,  -5, 3,
    -3, 3,  -2, -2, -3, 9,  -7, 5,  -7, 5,  -5, 3,  -3, 3,  -2, -2,
    -3, 9,  -7, 5,  -7, 5,  -5, 3,  -3, 3,  -2, -2, -5, -5, -9, -9,
    -9, -9, -9, -9, -9, -9, -9, -9,
};
pub const kAgahnim_Draw_Char1: [36]u8 = .{
    0xce, 0xcc, 0xc6, 0xc6, 0xc6, 0xc6, 0xce, 0xcc, 0xc6, 0xc6, 0xc6, 0xc6, 0xce, 0xcc, 0xc6, 0xc6,
    0xc6, 0xc6, 0xce, 0xcc, 0xc6, 0xc6, 0xc6, 0xc6, 0xce, 0xcc, 0xc6, 0xc6, 0xc6, 0xc6, 0xce, 0xcc,
    0xc6, 0xc6, 0xc6, 0xc6,
};
pub const kAgahnim_Draw_Big1: [36]u8 = .{
    0, 2, 2, 2, 2, 2, 0, 2, 2, 2, 2, 2, 0, 2, 2, 2,
    2, 2, 0, 2, 2, 2, 2, 2, 0, 2, 2, 2, 2, 2, 0, 2,
    2, 2, 2, 2,
};
pub const kEnergyBall_Gfx: [16]u8 = .{ 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 0, 0 };
pub const kEnergyBall_SplitXVel: [6]i8 = .{ 0, 24, 24, 0, -24, -24 };
pub const kEnergyBall_SplitYVel: [6]i8 = .{ -32, -16, 16, 32, 16, -16 };
pub const kEnergyBall_Dmd: [8]DrawMultipleData = .{
    .{ .x = 4, .y = -3, .char_flags = 0x00ce, .ext = 0 },
    .{ .x = 11, .y = 4, .char_flags = 0x00ce, .ext = 0 },
    .{ .x = 4, .y = 11, .char_flags = 0x00ce, .ext = 0 },
    .{ .x = -3, .y = 4, .char_flags = 0x00ce, .ext = 0 },
    .{ .x = -1, .y = -1, .char_flags = 0x00ce, .ext = 0 },
    .{ .x = 9, .y = -1, .char_flags = 0x00ce, .ext = 0 },
    .{ .x = -1, .y = 9, .char_flags = 0x00ce, .ext = 0 },
    .{ .x = 9, .y = 9, .char_flags = 0x00ce, .ext = 0 },
};
pub const kSpawnBee_XY: [8]i8 = .{ 8, 2, -2, -8, 10, 5, -5, -10 };
pub const kGoodBee_Tab0: [2]u8 = .{ 0xa, 0x14 };
pub const kBombShopGuy_Gfx: [8]u8 = .{ 0, 1, 0, 1, 0, 1, 0, 1 };
pub const kBombShopGuy_Delay: [8]u8 = .{ 255, 32, 255, 24, 15, 24, 255, 15 };
pub const kSnoutPutt_Dmd: [4]u8 = .{ 4, 0x44, 0xc4, 0x84 };
pub const kBombShopEntity_Dmd: [6]DrawMultipleData = .{
    .{ .x = 0, .y = 0, .char_flags = 0x0a48, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0a4c, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x04c2, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x04c2, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x084e, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x084e, .ext = 2 },
};
pub const kKiki_Leave_X: [3]u16 = .{ 0xf4f, 0xf70, 0xf5d };
pub const kKiki_Leave_Y: [3]u16 = .{ 0x661, 0x64c, 0x624 };
pub const kKiki_Zvel: [2]u8 = .{ 32, 28 };
pub const kKiki_Tab7: [3]u8 = .{ 2, 1, 0xff };
pub const kKiki_Delay7: [2]u8 = .{ 82, 0 };
pub const kKiki_Xvel7: [4]i8 = .{ 0, 0, -9, 9 };
pub const kKiki_Yvel7: [4]i8 = .{ -9, 9, 0, 0 };
pub const kKiki_Dmd1: [32]DrawMultipleData = .{
    .{ .x = 0, .y = -6, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0022, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4022, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0022, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4022, .ext = 2 },
    .{ .x = -1, .y = -6, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0022, .ext = 2 },
    .{ .x = -1, .y = -6, .char_flags = 0x0020, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x0022, .ext = 2 },
    .{ .x = 1, .y = -6, .char_flags = 0x4020, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4022, .ext = 2 },
    .{ .x = 1, .y = -6, .char_flags = 0x4020, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x4022, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x01ce, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x01ee, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x01ce, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x01ee, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x41ce, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x41ee, .ext = 2 },
    .{ .x = 0, .y = -6, .char_flags = 0x41ce, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x41ee, .ext = 2 },
    .{ .x = -1, .y = -6, .char_flags = 0x01ce, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x01ec, .ext = 2 },
    .{ .x = -1, .y = -6, .char_flags = 0x41ce, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x01ec, .ext = 2 },
    .{ .x = 1, .y = -6, .char_flags = 0x41ce, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x41ec, .ext = 2 },
    .{ .x = 1, .y = -6, .char_flags = 0x01ce, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x41ec, .ext = 2 },
};
pub const kKiki_Dmd2: [12]DrawMultipleData = .{
    .{ .x = 0, .y = -6, .char_flags = 0x01ca, .ext = 0 },
    .{ .x = 8, .y = -6, .char_flags = 0x41ca, .ext = 0 },
    .{ .x = 0, .y = 2, .char_flags = 0x01da, .ext = 0 },
    .{ .x = 8, .y = 2, .char_flags = 0x41da, .ext = 0 },
    .{ .x = 0, .y = 10, .char_flags = 0x01cb, .ext = 0 },
    .{ .x = 8, .y = 10, .char_flags = 0x41cb, .ext = 0 },
    .{ .x = 0, .y = -6, .char_flags = 0x01db, .ext = 0 },
    .{ .x = 8, .y = -6, .char_flags = 0x41db, .ext = 0 },
    .{ .x = 0, .y = 2, .char_flags = 0x01cc, .ext = 0 },
    .{ .x = 8, .y = 2, .char_flags = 0x41cc, .ext = 0 },
    .{ .x = 0, .y = 10, .char_flags = 0x01dc, .ext = 0 },
    .{ .x = 8, .y = 10, .char_flags = 0x41dd, .ext = 0 },
};
pub const kKikiDma: [32]u8 = .{ 0x20, 0xc0, 0x20, 0xc0, 0, 0xa0, 0, 0xa0, 0x40, 0x80, 0x40, 0x60, 0x40, 0x80, 0x40, 0x60, 0, 0, 0xfa, 0xff, 0x20, 0, 0, 2, 0, 0, 0, 0, 0x22, 0, 0, 2 };
pub const kOldMountainManMsgs: [3]u16 = .{ 0x9e, 0x9f, 0xa0 };
pub const kBully_Dmd: [8]DrawMultipleData = .{
    .{ .x = 0, .y = -7, .char_flags = 0x46e0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x46e2, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x46e0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x46c4, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x06e0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x06e2, .ext = 2 },
    .{ .x = 0, .y = -7, .char_flags = 0x06e0, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0x06c4, .ext = 2 },
};
pub const kWhirlpool_OamFlags: [4]u8 = .{ 0, 0x40, 0xc0, 0x80 };
pub const kShopKeeper_ItemX: [3]i8 = .{ -44, 8, 60 };
pub const kShopKeeper_GiveItemMsgs: [7]u16 = .{ 0x168, 0x167, 0x167, 0x16c, 0x169, 0x16a, 0x16b };
pub const kShopKeeper_ItemWithPrice_Dmd: [35]DrawMultipleData = .{
    .{ .x = -4, .y = 16, .char_flags = 0x0231, .ext = 0 },
    .{ .x = 4, .y = 16, .char_flags = 0x0213, .ext = 0 },
    .{ .x = 12, .y = 16, .char_flags = 0x0230, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x02c0, .ext = 2 },
    .{ .x = 0, .y = 11, .char_flags = 0x036c, .ext = 2 },
    .{ .x = 0, .y = 16, .char_flags = 0x0213, .ext = 0 },
    .{ .x = 0, .y = 16, .char_flags = 0x0213, .ext = 0 },
    .{ .x = 8, .y = 16, .char_flags = 0x0230, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x04ce, .ext = 2 },
    .{ .x = 4, .y = 12, .char_flags = 0x0338, .ext = 0 },
    .{ .x = -4, .y = 16, .char_flags = 0x0213, .ext = 0 },
    .{ .x = 4, .y = 16, .char_flags = 0x0230, .ext = 0 },
    .{ .x = 12, .y = 16, .char_flags = 0x0230, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x08cc, .ext = 2 },
    .{ .x = 4, .y = 12, .char_flags = 0x0338, .ext = 0 },
    .{ .x = 0, .y = 16, .char_flags = 0x0231, .ext = 0 },
    .{ .x = 0, .y = 16, .char_flags = 0x0231, .ext = 0 },
    .{ .x = 8, .y = 16, .char_flags = 0x0230, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x0329, .ext = 0 },
    .{ .x = 4, .y = 11, .char_flags = 0x0338, .ext = 0 },
    .{ .x = -4, .y = 16, .char_flags = 0x0203, .ext = 0 },
    .{ .x = -4, .y = 16, .char_flags = 0x0203, .ext = 0 },
    .{ .x = 4, .y = 16, .char_flags = 0x0230, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x04c4, .ext = 2 },
    .{ .x = 0, .y = 11, .char_flags = 0x0338, .ext = 0 },
    .{ .x = 0, .y = 16, .char_flags = 0x0213, .ext = 0 },
    .{ .x = 0, .y = 16, .char_flags = 0x0213, .ext = 0 },
    .{ .x = 8, .y = 16, .char_flags = 0x0230, .ext = 0 },
    .{ .x = 0, .y = 0, .char_flags = 0x04e8, .ext = 2 },
    .{ .x = 0, .y = 11, .char_flags = 0x036c, .ext = 2 },
    .{ .x = 0, .y = 16, .char_flags = 0x0231, .ext = 0 },
    .{ .x = 0, .y = 16, .char_flags = 0x0231, .ext = 0 },
    .{ .x = 8, .y = 16, .char_flags = 0x0230, .ext = 0 },
    .{ .x = 4, .y = 8, .char_flags = 0x0ff4, .ext = 0 },
    .{ .x = 4, .y = 11, .char_flags = 0x0338, .ext = 0 },
};
pub const kSomariaPlatform_DragX: [8]i8 = .{ 0, 0, -1, 1, -1, 1, 1, -1 };
pub const kSomariaPlatform_DragY: [8]i8 = .{ -1, 1, 0, 0, -1, 1, -1, 1 };
pub const kSomariaPlatform_Xvel: [8]i8 = .{ 0, 0, -16, 16, -16, 16, 16, -16 };
pub const kSomariaPlatform_Yvel: [8]i8 = .{ -16, 16, 0, 0, -16, 16, -16, 16 };
pub const kSomariaPlatform_Dmd: [16]DrawMultipleData = .{
    .{ .x = -16, .y = -16, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = 0, .y = -16, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = -16, .y = 0, .char_flags = 0x80ac, .ext = 2 },
    .{ .x = 0, .y = 0, .char_flags = 0xc0ac, .ext = 2 },
    .{ .x = -13, .y = -13, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = -3, .y = -13, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = -13, .y = -3, .char_flags = 0x80ac, .ext = 2 },
    .{ .x = -3, .y = -3, .char_flags = 0xc0ac, .ext = 2 },
    .{ .x = -10, .y = -10, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = -6, .y = -10, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = -10, .y = -6, .char_flags = 0x80ac, .ext = 2 },
    .{ .x = -6, .y = -6, .char_flags = 0xc0ac, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x00ac, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x40ac, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0x80ac, .ext = 2 },
    .{ .x = -8, .y = -8, .char_flags = 0xc0ac, .ext = 2 },
};
pub const kSomariaPlatform_TransitDir: [4]u8 = .{ 4, 8, 1, 2 };
pub const kSomariaPlatform_Keys1: [4]u8 = .{ 3, 7, 6, 5 };
pub const kSomariaPlatform_Keys2: [4]u8 = .{ 11, 3, 10, 9 };
pub const kSomariaPlatform_Keys3: [4]u8 = .{ 9, 5, 12, 13 };
pub const kSomariaPlatform_Keys4: [4]u8 = .{ 0xa, 6, 0xe, 0xc };
pub const kSomariaPlatform_Keys5: [4]u8 = .{ 0xb, 7, 0xe, 0xd };
pub const kSomariaPlatform_Keys6: [4]u8 = .{ 0xc, 0xc, 3, 3 };
pub const kPipe_Dirs: [4]u8 = .{ 8, 4, 2, 1 };
pub const kSpriteActiveRoutines: [243]?*const fn (c_int) callconv(.c) void = .{
    &a.Sprite_Raven,
    &a.Sprite_01_Vulture_bounce,
    &a.Sprite_02_StalfosHead,
    null,
    &a.Sprite_PullSwitch_bounce,
    &a.Sprite_PullSwitch_bounce,
    &a.Sprite_PullSwitch_bounce,
    &a.Sprite_PullSwitch_bounce,
    &a.Sprite_08_Octorok,
    &a.Sprite_09_GiantMoldorm,
    &a.Sprite_08_Octorok,
    &a.Sprite_0B_Cucco,
    &a.Sprite_0C_OctorokStone,
    &a.Sprite_0D_Buzzblob,
    &a.Sprite_0E_Snapdragon,
    &a.Sprite_0F_Octoballoon,
    &a.Sprite_10_OctoballoonBaby,
    &a.Sprite_11_Hinox,
    &a.Sprite_12_Moblin,
    &a.Sprite_13_MiniHelmasaur,
    &a.Sprite_14_ThievesTownGrate,
    &a.Sprite_15_Antifairy,
    &a.Sprite_16_Elder_bounce,
    &a.Sprite_17_Hoarder,
    &a.Sprite_18_MiniMoldorm,
    &a.Sprite_19_Poe,
    &a.Sprite_1A_Smithy,
    &a.Sprite_1B_Arrow,
    &a.Sprite_1C_Statue,
    &a.Sprite_1D_FluteQuest,
    &a.Sprite_1E_CrystalSwitch,
    &a.Sprite_1F_SickKid,
    &a.Sprite_20_Sluggula,
    &a.Sprite_21_WaterSwitch,
    &a.Sprite_22_Ropa,
    &a.Sprite_23_RedBari,
    &a.Sprite_23_RedBari,
    &a.Sprite_25_TalkingTree,
    &a.Sprite_26_HardhatBeetle,
    &a.Sprite_27_Deadrock,
    &a.Sprite_28_DarkWorldHintNPC,
    &a.Sprite_HumanMulti_1,
    &a.Sprite_SweepingLady,
    &a.Sprite_2B_Hobo,
    &a.Sprite_Lumberjacks,
    &a.Sprite_2D_TelepathicTile,
    &a.Sprite_2E_FluteKid,
    &a.Sprite_MazeGameLady,
    &a.Sprite_MazeGameGuy,
    &a.Sprite_FortuneTeller,
    &a.Sprite_QuarrelBros,
    &a.Sprite_33_RupeePull,
    &a.Sprite_YoungSnitchLady,
    &a.Sprite_InnKeeper,
    &a.Sprite_Witch,
    &a.Sprite_37_Waterfall,
    &a.Sprite_38_EyeStatue,
    &a.Sprite_39_Locksmith,
    &a.Sprite_3A_MagicBat,
    &a.Sprite_DashItem,
    &a.Sprite_TroughBoy,
    &a.Sprite_OldSnitchLady,
    &a.Sprite_17_Hoarder,
    &a.Sprite_TutorialGuardOrBarrier,
    &a.Sprite_TutorialGuardOrBarrier,
    // Trampoline 48 entries
    &a.Sprite_41_BlueGuard,
    &a.Sprite_41_BlueGuard,
    &a.Sprite_41_BlueGuard,
    &a.Sprite_44_BluesainBolt,
    &a.Sprite_45_HogSpearMan,
    &a.Sprite_46_BlueArcher,
    &a.Sprite_47_GreenBushGuard,
    &a.Sprite_48_RedJavelinGuard,
    &a.Sprite_49_RedBushGuard,
    &a.Sprite_4A_BombGuard,
    &a.Sprite_4B_GreenKnifeGuard,
    &a.Sprite_4C_Geldman,
    &a.Sprite_4D_Toppo,
    &a.Sprite_4E_Popo,
    &a.Sprite_4E_Popo,
    &a.Sprite_50_Cannonball,
    &a.Sprite_51_ArmosStatue,
    &a.Sprite_52_KingZora,
    &a.Sprite_53_ArmosKnight,
    &a.Sprite_54_Lanmolas,
    &a.Sprite_55_Zora,
    &a.Sprite_56_WalkingZora,
    &a.Sprite_57_DesertStatue,
    &a.Sprite_58_Crab,
    &a.Sprite_59_LostWoodsBird,
    &a.Sprite_5A_LostWoodsSquirrel,
    &a.Sprite_5B_Spark_Clockwise,
    &a.Sprite_5B_Spark_Clockwise,
    &a.Sprite_5D_Roller_VerticalDownFirst,
    &a.Sprite_5D_Roller_VerticalDownFirst,
    &a.Sprite_5D_Roller_VerticalDownFirst,
    &a.Sprite_5D_Roller_VerticalDownFirst,
    &a.Sprite_61_Beamos,
    &a.Sprite_62_MasterSword,
    &a.Sprite_63_DebirandoPit,
    &a.Sprite_64_Debirando,
    &a.Sprite_65_ArcheryGame,
    &a.Sprite_66_WallCannonVerticalLeft,
    &a.Sprite_66_WallCannonVerticalLeft,
    &a.Sprite_66_WallCannonVerticalLeft,
    &a.Sprite_66_WallCannonVerticalLeft,
    &a.Sprite_6A_BallNChain,
    &a.Sprite_6B_CannonTrooper,
    &a.Sprite_6C_MirrorPortal,
    &a.Sprite_6D_Rat,
    &a.Sprite_6E_Rope,
    &a.Sprite_6F_Keese,
    &a.Sprite_70_KingHelmasaurFireball,
    &a.Sprite_71_Leever,
    &a.Sprite_72_FairyPond,
    &a.Sprite_73_UncleAndPriest,
    &a.Sprite_RunningMan,
    &a.Sprite_BottleVendor,
    &a.Sprite_76_Zelda,
    &a.Sprite_15_Antifairy,
    &a.Sprite_78_MrsSahasrahla,
    // Trampoline 68 entries
    &a.Sprite_79_Bee,
    &a.Sprite_7A_Agahnim,
    &a.Sprite_7B_AgahnimBalls,
    &a.Sprite_7C_GreenStalfos,
    &a.Sprite_7D_BigSpike,
    &a.Sprite_7E_Firebar_Clockwise,
    &a.Sprite_7E_Firebar_Clockwise,
    &a.Sprite_80_Firesnake,
    &a.Sprite_81_Hover,
    &a.Sprite_82_AntifairyCircle,
    &a.Sprite_83_GreenEyegore,
    &a.Sprite_83_GreenEyegore,
    &a.Sprite_85_YellowStalfos,
    &a.Sprite_86_Kodongo,
    &a.Sprite_87_KodongoFire,
    &a.Sprite_88_Mothula,
    &a.Sprite_89_MothulaBeam,
    &a.Sprite_8A_SpikeBlock,
    &a.Sprite_8B_Gibdo,
    &a.Sprite_8C_Arrghus,
    &a.Sprite_8D_Arrghi,
    &a.Sprite_8E_Terrorpin,
    &a.Sprite_8F_Blob,
    &a.Sprite_90_Wallmaster,
    &a.Sprite_91_StalfosKnight,
    &a.Sprite_92_HelmasaurKing,
    &a.Sprite_93_Bumper,
    &a.Sprite_94_Pirogusu,
    &a.Sprite_95_LaserEyeLeft,
    &a.Sprite_95_LaserEyeLeft,
    &a.Sprite_95_LaserEyeLeft,
    &a.Sprite_95_LaserEyeLeft,
    &a.Sprite_99_Pengator,
    &a.Sprite_9A_Kyameron,
    &a.Sprite_9B_Wizzrobe,
    &a.Sprite_9C_Zoro,
    &a.Sprite_9C_Zoro,
    &a.Sprite_9E_HauntedGroveOstritch,
    &a.Sprite_9F_HauntedGroveRabbit,
    &a.Sprite_A0_HauntedGroveBird,
    &a.Sprite_A1_Freezor,
    &a.Sprite_A2_Kholdstare,
    &a.Sprite_A3_KholdstareShell,
    &a.Sprite_A4_FallingIce,
    &a.Sprite_Zazak_Main,
    &a.Sprite_Zazak_Main,
    &a.Sprite_A7_Stalfos,
    &a.Sprite_A8_GreenZirro,
    &a.Sprite_A8_GreenZirro,
    &a.Sprite_AA_Pikit,
    &a.Sprite_AB_CrystalMaiden,
    &a.Sprite_AC_Apple,
    &a.Sprite_AD_OldMan,
    &a.Sprite_AE_Pipe_Down,
    &a.Sprite_AE_Pipe_Down,
    &a.Sprite_AE_Pipe_Down,
    &a.Sprite_AE_Pipe_Down,
    &a.Sprite_B2_PlayerBee,
    &a.Sprite_B3_PedestalPlaque,
    &a.Sprite_B4_PurpleChest,
    &a.Sprite_B5_BombShop,
    &a.Sprite_B6_Kiki,
    &a.Sprite_B7_BlindMaiden,
    &a.Sprite_B8_DialogueTester,
    &a.Sprite_B9_BullyAndPinkBall,
    &a.Sprite_BA_Whirlpool,
    &a.Sprite_BB_Shopkeeper,
    &a.Sprite_BC_Drunkard,
    // Trampoline 4, starts at 187, 27 entries
    &a.Sprite_BD_Vitreous,
    &a.Sprite_BE_VitreousEye,
    &a.Sprite_BF_Lightning,
    &a.Sprite_C0_Catfish,
    &a.Sprite_C1_CutsceneAgahnim,
    &a.Sprite_C2_Boulder,
    &a.Sprite_C3_Gibo,
    &a.Sprite_C4_Thief,
    &a.Sprite_C5_Medusa,
    &a.Sprite_C6_4WayShooter,
    &a.Sprite_C7_Pokey,
    &a.Sprite_C8_BigFairy,
    &a.Sprite_C9_Tektite,
    &a.Sprite_CA_ChainChomp,
    &a.Sprite_CB_TrinexxRockHead,
    &a.Sprite_CC,
    &a.Sprite_CD,
    &a.Sprite_CE_Blind,
    &a.Sprite_CF_Swamola,
    &a.Sprite_D0_Lynel,
    &a.Sprite_D1_BunnyBeam,
    &a.Sprite_D2_FloppingFish,
    &a.Sprite_D3_Stal,
    &a.Sprite_D4_Landmine,
    &a.Sprite_D5_DigGameGuy,
    &a.Sprite_D6_Ganon,
    &a.Sprite_D6_Ganon,
    &a.Sprite_D8_Heart,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_E3_Fairy,
    &a.Sprite_E4_SmallKey,
    &a.Sprite_E4_SmallKey,
    &a.Sprite_D9_GreenRupee,
    &a.Sprite_E7_Mushroom,
    &a.Sprite_E8_FakeSword,
    &a.Sprite_E9_PotionShop,
    &a.Sprite_HeartContainer,
    &a.Sprite_HeartPiece,
    &a.Sprite_EC_ThrownItem,
    &a.Sprite_ED_SomariaPlatform,
    &a.Sprite_EE_MovableMantle,
    &a.Sprite_ED_SomariaPlatform,
    &a.Sprite_ED_SomariaPlatform,
    &a.Sprite_ED_SomariaPlatform,
    &a.Sprite_F2_MedallionTablet,
};
pub const kSpritePrep_Main: [243]?*const fn (c_int) callconv(.c) void = .{
    &a.SpritePrep_Raven,
    &a.SpritePrep_Vulture,
    &a.SpritePrep_DoNothingA,
    null,
    &a.SpritePrep_Switch,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Switch,
    &a.SpritePrep_SwitchFacingUp,
    &a.SpritePrep_Octorok,
    &a.SpritePrep_Moldorm,
    &a.SpritePrep_Octorok,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Octoballoon,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_MiniHelmasaur,
    &a.SpritePrep_ThievesTownGrate,
    &a.SpritePrep_Antifairy,
    &a.SpritePrep_Sage,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_MiniMoldorm_bounce,
    &a.SpritePrep_Poe,
    &a.SpritePrep_Smithy,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Statue,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_CrystalSwitch,
    &a.SpritePrep_SickKid,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_WaterLever,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Bari,
    &a.SpritePrep_Bari,
    &a.SpritePrep_TalkingTree,
    &a.SpritePrep_HardhatBeetle,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Storyteller,
    &a.SpritePrep_Adults,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_Hobo,
    &a.SpritePrep_MagicBat,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_FluteKid,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_FortuneTeller,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_RupeePull,
    &a.SpritePrep_Snitch_bounce_2,
    &a.SpritePrep_Snitch_bounce_3,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Locksmith,
    &a.SpritePrep_MagicBat,
    &a.SpritePrep_BonkItem,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_Snitch_bounce_1,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_AgahnimsBarrier,
    &a.SpritePrep_StandardGuard,
    &a.SpritePrep_StandardGuard,
    &a.SpritePrep_StandardGuard,
    &a.SpritePrep_TrooperAndArcherSoldier,
    &a.SpritePrep_TrooperAndArcherSoldier,
    &a.SpritePrep_TrooperAndArcherSoldier,
    &a.SpritePrep_TrooperAndArcherSoldier,
    &a.SpritePrep_TrooperAndArcherSoldier,
    &a.SpritePrep_TrooperAndArcherSoldier,
    &a.SpritePrep_TrooperAndArcherSoldier,
    &a.SpritePrep_WeakGuard,
    &a.SpritePrep_Geldman,
    &a.SpritePrep_Kyameron,
    &a.SpritePrep_Popo,
    &a.SpritePrep_Popo2,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingD,
    &a.SpritePrep_KingZora,
    &a.SpritePrep_ArmosKnight,
    &a.SpritePrep_Lanmolas,
    &a.SpritePrep_SwimmingZora,
    &a.SpritePrep_WalkingZora,
    &a.SpritePrep_DesertStatue,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_LostWoodsBird,
    &a.SpritePrep_LostWoodsSquirrel,
    &a.SpritePrep_Spark,
    &a.SpritePrep_Spark,
    &a.SpritePrep_Roller_VerticalDownFirst,
    &a.SpritePrep_RollerUpDown,
    &a.SpritePrep_Roller_HorizontalRightFirst,
    &a.SpritePrep_RollerLeftRight,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_MasterSword,
    &a.SpritePrep_DebirandoPit,
    &a.SpritePrep_FireDebirando,
    &a.SpritePrep_ArrowGame_bounce,
    &a.SpritePrep_WallCannon,
    &a.SpritePrep_WallCannon,
    &a.SpritePrep_WallCannon,
    &a.SpritePrep_WallCannon,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Rat,
    &a.SpritePrep_Rope,
    &a.SpritePrep_Keese,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_FairyPond,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_UncleAndPriest_bounce,
    &a.SpritePrep_RunningMan,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_Zelda_bounce,
    &a.SpritePrep_Antifairy,
    &a.SpritePrep_MrsSahasrahla,
    &a.SpritePrep_OverworldBonkItem,
    &a.SpritePrep_Agahnim,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_GreenStalfos,
    &a.SpritePrep_BigSpike,
    &a.SpritePrep_FireBar,
    &a.SpritePrep_FireBar,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_AntifairyCircle,
    &a.SpritePrep_Eyegore,
    &a.SpritePrep_Eyegore,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_Kodongo,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_Mothula,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_Spike,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_Arrghus,
    &a.SpritePrep_Arrghi,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_Blob,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_DoNothingG,
    &a.SpritePrep_HelmasaurKing,
    &a.SpritePrep_Bumper,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_LaserEye_bounce,
    &a.SpritePrep_LaserEye_bounce,
    &a.SpritePrep_LaserEye_bounce,
    &a.SpritePrep_LaserEye_bounce,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Kyameron,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Zoro,
    &a.SpritePrep_Babasu,
    &a.SpritePrep_HauntedGroveOstritch,
    &a.SpritePrep_HauntedGroveAnimal,
    &a.SpritePrep_HauntedGroveAnimal,
    &a.SpritePrep_MoveDown_8px,
    &a.SpritePrep_Kholdstare,
    &a.SpritePrep_KholdstareShell,
    &a.SpritePrep_FallingIce,
    &a.SpritePrep_Zazakku,
    &a.SpritePrep_Zazakku,
    &a.SpritePrep_Stalfos,
    &a.SpritePrep_Bomber,
    &a.SpritePrep_Bomber,
    &a.SpritePrep_DoNothingC,
    &a.SpritePrep_DoNothingH,
    &a.SpritePrep_OverworldBonkItem,
    &a.SpritePrep_OldMan_bounce,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_NiceBee,
    &a.SpritePrep_PedestalPlaque,
    &a.SpritePrep_PurpleChest,
    &a.SpritePrep_BombShoppe,
    &a.SpritePrep_Kiki,
    &a.SpritePrep_BlindMaiden,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_BullyAndVictim,
    &a.SpritePrep_Whirlpool,
    &a.SpritePrep_Shopkeeper,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_Vitreous,
    &a.SpritePrep_MiniVitreous,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Catfish,
    &a.SpritePrep_CutsceneAgahnim,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Gibo,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_Pokey,
    &a.SpritePrep_BigFairy,
    &a.SpritePrep_Tektite,
    &a.SpritePrep_Chainchomp_bounce,
    &a.SpritePrep_Trinexx,
    &a.SpritePrep_Trinexx,
    &a.SpritePrep_Trinexx,
    &a.SpritePrep_Blind,
    &a.SpritePrep_Swamola,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_RockStal,
    &a.SpritePrep_IgnoreProjectiles,
    &a.SpritePrep_DiggingGameGuy_bounce,
    &a.SpritePrep_Ganon,
    &a.SpritePrep_Ganon,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Absorbable,
    &a.SpritePrep_Fairy,
    &a.SpritePrep_SmallKey,
    &a.SpritePrep_BigKey,
    &a.SpritePrep_ShieldPickup,
    &a.SpritePrep_Mushroom,
    &a.SpritePrep_FakeSword,
    &a.SpritePrep_PotionShop,
    &a.SpritePrep_HeartContainer,
    &a.SpritePrep_HeartPiece,
    &a.SpritePrep_ThrowableScenery,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_Mantle,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_DoNothingA,
    &a.SpritePrep_MedallionTable,
};
