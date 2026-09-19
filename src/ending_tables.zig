//! Data tables for ending, generated from src/ending.c -- do not edit by hand.
//! C constant expressions are evaluated and short initializers are zero
//! padded to their declared size, as C does.

pub const kPolyhedralPalette = [8]u16{
    0, 333, 432, 499, 598, 633, 765, 863,
};

pub const kIntroSprite0_Xvel = [3]i8{
    1, 0, -1,
};

pub const kIntroSprite0_Yvel = [3]i8{
    -1, 1, -1,
};

pub const kIntroSprite3_X = [4]u8{
    194, 152, 111, 52,
};

pub const kIntroSprite3_Y = [4]u8{
    124, 84, 124, 87,
};

pub const kIntroSprite3_State = [8]u8{
    0, 1, 2, 3, 2, 1, 255, 255,
};

pub const kTriforce_Xfinal = [3]u8{
    89, 95, 103,
};

pub const kTriforce_Yfinal = [3]u8{
    116, 104, 116,
};

pub const kEndingSprites_X = [85]u16{
    480, 512, 493, 515, 474, 534, 456, 552,
    448, 480, 520, 552, 248, 240, 632, 664,
    480, 512, 544, 648, 482, 224, 336, 232,
    360, 296, 368, 368, 821, 821, 768, 184,
    206, 172, 196, 944, 912, 976, 248, 200,
    128, 248, 248, 248, 248, 248, 232, 248,
    216, 248, 200, 264, 112, 112, 112, 104,
    136, 112, 64, 112, 79, 97, 55, 121,
    200, 632, 600, 472, 456, 392, 624, 384,
    744, 624, 624, 672, 672, 676, 764, 118,
    115, 118, 0, 208, 128,
};

pub const kEndingSprites_Y = [85]u16{
    344, 344, 312, 312, 320, 320, 336, 336,
    288, 288, 288, 288, 96, 55, 194, 194,
    363, 364, 363, 184, 363, 128, 96, 326,
    326, 454, 112, 112, 296, 296, 367, 245,
    252, 269, 269, 64, 64, 64, 336, 344,
    244, 288, 288, 288, 288, 288, 264, 256,
    216, 216, 240, 240, 60, 60, 60, 144,
    128, 60, 364, 364, 372, 372, 373, 373,
    592, 688, 688, 672, 688, 688, 696, 216,
    587, 432, 456, 456, 432, 560, 560, 139,
    131, 133, 44, 248, 256,
};

pub const kEndingSprites_Idx = [17]u8{
    0, 12, 14, 21, 28, 31, 35, 38, 40, 41, 52, 58, 64, 71, 72, 79,
    85,
};

pub const kEnding1_TargetScrollY = [16]u16{
    1778, 528, 1836, 3072, 268, 2715, 16, 1296,
    137, 2702, 8748, 9488, 2086, 92, 522, 48,
};

pub const kEnding1_TargetScrollX = [16]u16{
    1919, 1152, 403, 170, 2168, 2119, 1277, 3159,
    1039, 1144, 2560, 512, 513, 2721, 623, 0,
};

pub const kEnding1_Yvel = [16]i8{
    -1, -1, 1, -1, 1, 1, 0, 1, 0, -1, -1, 0, 0, 0, 1, -1,
};

pub const kEnding1_Xvel = [16]i8{
    0, 0, -1, 0, 0, -1, 1, 0, -1, 0, 0, 0, 1, -1, 1, 0,
};

pub const kEnding_Tab1 = [16]u16{
    4096, 2, 4098, 4114, 4100, 4102, 4112, 4116,
    4106, 4118, 93, 100, 4110, 4104, 4120, 384,
};

pub const kEnding_SpritePack = [17]u8{
    40, 70, 39, 46, 43, 43, 14, 44, 26, 41, 71, 40, 39, 40, 42, 40,
    45,
};

pub const kEnding_SpritePal = [17]u8{
    1, 64, 1, 4, 1, 1, 1, 17, 1, 1, 71, 64, 1, 1, 1, 1,
    1,
};

pub const kPolyThreadInit = [13]u8{
    9, 0, 31, 0, 0, 0, 0, 0, 0, 48, 29, 248, 9,
};

pub const kIntroSprite0_X = [3]i16{
    -38, 95, 230,
};

pub const kIntroSprite0_Y = [3]i16{
    200, -67, 200,
};

pub const kIntroSprite0_XLimit = [3]u8{
    75, 95, 117,
};

pub const kIntroSprite0_YLimit = [3]u8{
    88, 48, 88,
};

pub const kIntroTriforce_X = [3]i16{
    78, 95, 114,
};

pub const kIntroTriforce_Y = [3]i16{
    156, 156, 156,
};

pub const kIntroTriforce_Xvel = [3]i8{
    -2, 0, 2,
};

pub const kIntroTriforce_Yvel = [3]i8{
    4, -4, 4,
};

pub const kTriforce_Xacc = [3]i8{
    -1, 0, 1,
};

pub const kTriforce_Yacc = [3]i8{
    -1, -1, -1,
};

pub const kTriforce_Yfinal2 = [3]u8{
    114, 102, 114,
};

pub const kIntroSprite7_X = [3]u8{
    41, 95, 151,
};

pub const kIntroSprite7_Y = [3]u8{
    112, 32, 112,
};

pub const kIntroSprite7_XAcc = [3]i8{
    -1, 0, 1,
};

pub const kIntroSprite7_YAcc = [3]i8{
    1, -1, 1,
};

pub const kIntroLogo_X = [4]u8{
    96, 112, 128, 136,
};

pub const kIntroLogo_Tile = [4]u8{
    105, 107, 109, 110,
};

pub const kIntroSword_Char = [10]u8{
    0, 2, 32, 34, 4, 6, 8, 10, 12, 14,
};

pub const kIntroSword_X = [10]u8{
    64, 64, 48, 80, 64, 64, 64, 64, 64, 64,
};

pub const kIntroSword_Y = [10]u16{
    16, 32, 40, 40, 48, 64, 80, 96,
    112, 128,
};

pub const kSwordSparkle_Tab = [8]u8{
    4, 4, 6, 6, 6, 4, 4, 0,
};

pub const kSwordSparkle_Char = [7]u8{
    40, 55, 39, 54, 39, 55, 40,
};

pub const kIntroSwordSparkle_Char = [8]u8{
    38, 32, 36, 52, 37, 32, 53, 32,
};

pub const kEnding1_3_Tab0 = [16]u16{
    768, 640, 592, 736, 640, 592, 704, 704,
    592, 592, 640, 592, 1152, 1024, 592, 1280,
};

pub const kEndSequence_Case0_Tab1 = [12]u8{
    30, 32, 34, 34, 34, 34, 34, 34, 22, 22, 22, 22,
};

pub const kEndSequence_Case0_Tab0 = [12]u8{
    6, 3, 2, 2, 2, 2, 2, 2, 6, 6, 6, 6,
};

pub const kEndSequence_Case0_OamFlags = [12]u8{
    59, 49, 61, 63, 57, 59, 55, 61, 57, 55, 55, 57,
};

pub const kEnding_Case2_Tab0 = [2]u8{
    32, 64,
};

pub const kEnding_Case2_Tab1 = [2]i8{
    16, -16,
};

pub const kEnding_Case2_Tab2 = [5]i8{
    40, 42, 44, 46, 44,
};

pub const kEnding_Case2_Tab3 = [5]i8{
    3, 3, 3, 3, 3,
};

pub const kEnding_Case2_Delay = [2]u8{
    48, 16,
};

pub const kEnding_Case3_Gfx = [4]u8{
    1, 2, 3, 2,
};

pub const kEnding_Case4_Tab1 = [2]u8{
    48, 50,
};

pub const kEnding_Case4_Tab0 = [2]u8{
    2, 2,
};

pub const kEnding_Case4_Ctr = [2]u8{
    32, 0,
};

pub const kEnding_Case4_XYvel = [10]i8{
    0, -12, -16, -12, 0, 12, 16, 12, 0, -12,
};

pub const kEnding_Case4_DelayVel = [24]u8{
    59, 20, 30, 29, 44, 43, 66, 32, 39, 40, 46, 56, 58, 76, 50, 68,
    46, 47, 30, 40, 71, 53, 50, 48,
};

pub const kEnding_Case5_Tab0 = [2]u8{
    0, 4,
};

pub const kEnding_Case5_Tab1 = [2]u16{
    10, 548,
};

pub const kEnding_Case5_Tab2 = [2]u8{
    10, 14,
};

pub const kEnding_Case6_SprType = [3]u8{
    82, 85, 85,
};

pub const kEnding_Case6_OamSize = [3]u8{
    32, 8, 8,
};

pub const kEnding_Case6_State = [3]u8{
    3, 1, 1,
};

pub const kEnding_Case6_Gfx = [6]u8{
    0, 5, 5, 1, 6, 6,
};

pub const kEnding_Case7_Gfx = [2]i8{
    1, -1,
};

pub const kEnding_Case8_Delay1 = [4]u8{
    16, 14, 16, 18,
};

pub const kEnding_Case8_Delay2 = [4]u8{
    20, 48, 20, 20,
};

pub const kEnding_Case8_D = [4]u8{
    0, 1, 0, 1,
};

pub const kEnding_Case8_OamFlags = [4]u8{
    55, 55, 59, 61,
};

pub const kEnding_Case8_Tab0 = [4]u8{
    8, 8, 12, 12,
};

pub const kWishPond_X = [8]u8{
    0, 4, 8, 12, 16, 20, 24, 0,
};

pub const kWishPond_Y = [8]u8{
    0, 8, 16, 24, 32, 40, 4, 36,
};

pub const kEnding_Case11_Gfx = [16]u8{
    1, 1, 2, 2, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 0,
};

pub const kEnding_Case12_Tab = [3]u8{
    3, 3, 8,
};

pub const kEnding_Case12_Z = [15]u8{
    2, 4, 5, 6, 6, 7, 7, 7, 7, 6, 6, 5, 4, 2, 0,
};

pub const kEnding_Case14_Tab1 = [4]i8{
    0, 1, 0, 2,
};

pub const kEnding_Case14_Tab0 = [5]i8{
    2, 8, 32, 32, 8,
};

pub const kEnding_Case15_X = [4]u8{
    118, 115, 113, 120,
};

pub const kEnding_Case15_Y = [4]u8{
    139, 131, 141, 133,
};

pub const kEnding_Case15_Delay = [8]u8{
    6, 6, 6, 6, 6, 6, 10, 8,
};

pub const kEnding_Case15_OamFlags = [4]u8{
    97, 97, 59, 57,
};

pub const kEnding_Func2_Delay = [27]u8{
    10, 10, 10, 10, 20, 8, 8, 0, 255, 12, 12, 12, 12, 12, 12, 30,
    8, 4, 4, 4, 0, 0, 255, 255, 144, 4, 0,
};

pub const kEnding_Func2_Tab0 = [28]i8{
    0, 0, 1, 0, 1, 0, 2, 3, 0, 2, 0, 1, 0, 1, 0, 1,
    2, 3, 4, 5, 6, 3, 0, -1, -1, -1, 2, 3,
};

pub const kEnding_Func3_Delay = [6]u8{
    32, 4, 4, 4, 5, 6,
};

pub const kEnding_Func6_Dma = [8]u16{
    364, 366, 368, 370, 364, 372, 374, 376,
};

pub const kEnding_Func5_Xvel = [4]i8{
    32, 24, -32, -24,
};

pub const kEnding_Func5_Yvel = [4]i8{
    8, -8, -8, 8,
};

pub const kEnding_MoveSprite_Func1_TargetX = [2]i8{
    32, -32,
};

pub const kEnding_MoveSprite_Func1_TargetY = [2]i8{
    16, -16,
};

pub const kEnding_Func9_Tab2 = [14]u8{
    1, 0, 2, 3, 10, 6, 5, 8, 11, 9, 7, 12, 13, 15,
};

pub const kEnding_Digits_ScrollY = [14]u16{
    656, 664, 672, 680, 688, 698, 706, 714,
    722, 730, 738, 746, 754, 784,
};

pub const kEnding_Credits_DigitChar = [2]u16{
    15590, 15606,
};
