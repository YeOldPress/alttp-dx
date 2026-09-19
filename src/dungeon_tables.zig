//! Dungeon data tables, transcribed from the original room engine.
const c = @import("dungeon_abi.zig");
pub const DungPalInfo = extern struct { pal0: u8, pal1: u8, pal2: u8, pal3: u8 };
pub const kBossRooms = [_]u16{ 200, 51, 7, 32, 6, 90, 41, 144, 222, 164, 172, 13 };
pub const kDungeonExit_From = [_]u8{ 200, 51, 7, 32, 6, 90, 41, 144, 222, 164, 172, 13 };
pub const kDungeonExit_To = [_]u8{ 201, 99, 119, 32, 40, 74, 89, 152, 14, 214, 219, 13 };
pub const kObjectSubtype1Params = [_]u16{
    0x3d8, 0x2e8,  0x2f8,  0x328,  0x338, 0x400,  0x410,  0x388, 0x390,  0x420,  0x42a, 0x434,  0x43e,  0x448,  0x452, 0x45c,
    0x466, 0x470,  0x47a,  0x484,  0x48e, 0x498,  0x4a2,  0x4ac, 0x4b6,  0x4c0,  0x4ca, 0x4d4,  0x4de,  0x4e8,  0x4f2, 0x4fc,
    0x506, 0x598,  0x600,  0x63c,  0x63c, 0x63c,  0x63c,  0x63c, 0x642,  0x64c,  0x652, 0x658,  0x65e,  0x664,  0x66a, 0x688,
    0x694, 0x6a8,  0x6a8,  0x6a8,  0x6c8, 0x0,    0x78a,  0x7aa, 0xe26,  0x84a,  0x86a, 0x882,  0x8ca,  0x85a,  0x8fa, 0x91a,
    0x920, 0x92a,  0x930,  0x936,  0x93c, 0x942,  0x948,  0x94e, 0x96c,  0x97e,  0x98e, 0x902,  0x99e,  0x9d8,  0x9d8, 0x9d8,
    0x9fa, 0x156c, 0x1590, 0x1d86, 0x0,   0xa14,  0xa24,  0xa54, 0xa54,  0xa84,  0xa84, 0x14dc, 0x1500, 0x61e,  0xe52, 0x600,
    0x3d8, 0x2c8,  0x2d8,  0x308,  0x318, 0x3e0,  0x3f0,  0x378, 0x380,  0x5fa,  0x648, 0x64a,  0x670,  0x67c,  0x6a8, 0x6a8,
    0x6a8, 0x6c8,  0x0,    0x7aa,  0x7ca, 0x84a,  0x89a,  0x8b2, 0x90a,  0x926,  0x928, 0x912,  0x9f8,  0x1d7e, 0x0,   0xa34,
    0xa44, 0xa54,  0xa6c,  0xa84,  0xa9c, 0x1524, 0x1548, 0x85a, 0x606,  0xe52,  0x5fa, 0x6a0,  0x6a2,  0xb12,  0xb14, 0x9b0,
    0xb46, 0xb56,  0x1f52, 0x1f5a, 0x288, 0xe82,  0x1df2, 0x0,   0x0,    0x0,    0x0,   0x0,    0x0,    0x0,    0x0,   0x0,
    0x3d8, 0x3d8,  0x3d8,  0x3d8,  0x5aa, 0x5b2,  0x5b2,  0x5b2, 0x5b2,  0xe0,   0xe0,  0xe0,   0xe0,   0x110,  0x0,   0x0,
    0x6a4, 0x6a6,  0xae6,  0xb06,  0xb0c, 0xb16,  0xb26,  0xb36, 0x1f52, 0x1f5a, 0x288, 0xeba,  0xe82,  0x1df2, 0x0,   0x0,
    0x3d8, 0x510,  0x5aa,  0x5aa,  0x0,   0x168,  0xe0,   0x158, 0x100,  0x110,  0x178, 0x72a,  0x72a,  0x72a,  0x75a, 0x670,
    0x670, 0x130,  0x148,  0x72a,  0x72a, 0x72a,  0x75a,  0xe0,  0x110,  0xf0,   0x110, 0x0,    0xab4,  0x8da,  0xade, 0x188,
    0x1a0, 0x1b0,  0x1c0,  0x1d0,  0x1e0, 0x1f0,  0x200,  0x120, 0x2a8,  0x0,    0x0,   0x0,    0x0,    0x0,    0x0,   0x0,
    0x0,   0x0,    0x0,    0x0,    0x0,   0x0,    0x0,    0x0,   0x0,    0x0,    0x0,   0x0,    0x0,    0x0,    0x0,   0x0,
};
pub const kObjectSubtype2Params = [_]u16{
    0xb66,  0xb86,  0xba6,  0xbc6,  0xc66, 0xc86,  0xca6,  0xcc6,  0xbe6,  0xc06,  0xc26,  0xc46,  0xce6,  0xd06,  0xd26,  0xd46,
    0xd66,  0xd7e,  0xd96,  0xdae,  0xdc6, 0xdde,  0xdf6,  0xe0e,  0x398,  0x3a0,  0x3a8,  0x3b0,  0xe32,  0xe26,  0xea2,  0xe9a,
    0xeca,  0xed2,  0xede,  0xede,  0xf1e, 0xf3e,  0xf5e,  0xf6a,  0xef6,  0xf72,  0xf92,  0xfa2,  0xfa2,  0x1088, 0x10a8, 0x10a8,
    0x10c8, 0x10c8, 0x10c8, 0x10c8, 0xe52, 0x1108, 0x1108, 0x12a8, 0x1148, 0x1160, 0x1178, 0x1190, 0x1458, 0x1488, 0x2062, 0x2086,
};
pub const kObjectSubtype3Params = [_]u16{
    0x1614, 0x162c, 0x1654, 0xa0e,  0xa0c,  0x9fc,  0x9fe,  0xa00,  0xa02,  0xa04,  0xa06,  0xa08,  0xa0a,  0x0,    0xa10,  0xa12,
    0x1dda, 0x1de2, 0x1dd6, 0x1dea, 0x15fc, 0x1dfa, 0x1df2, 0x1488, 0x1494, 0x149c, 0x14a4, 0x10e8, 0x10e8, 0x10e8, 0x11a8, 0x11c8,
    0x11e8, 0x1208, 0x3b8,  0x3c0,  0x3c8,  0x3d0,  0x1228, 0x1248, 0x1268, 0x1288, 0x0,    0xe5a,  0xe62,  0x0,    0x0,    0xe82,
    0xe8a,  0x14ac, 0x14c4, 0x10e8, 0x1614, 0x1614, 0x1614, 0x1614, 0x1614, 0x1614, 0x1cbe, 0x1cee, 0x1d1e, 0x1d4e, 0x1d8e, 0x1d96,
    0x1d9e, 0x1da6, 0x1dae, 0x1db6, 0x1dbe, 0x1dc6, 0x1dce, 0x220,  0x260,  0x280,  0x1f3a, 0x1f62, 0x1f92, 0x1ff2, 0x2016, 0x1f42,
    0xeaa,  0x1f4a, 0x1f52, 0x1f5a, 0x202e, 0x2062, 0x9b8,  0x9c0,  0x9c8,  0x9d0,  0xfa2,  0xfb2,  0xfc4,  0xff4,  0x1018, 0x1020,
    0x15b4, 0x15d8, 0x20f6, 0xeba,  0x22e6, 0x22ee, 0x5da,  0x281e, 0x2ae0, 0x2d2a, 0x2f2a, 0x22f6, 0x2316, 0x232e, 0x2346, 0x235e,
    0x2376, 0x23b6, 0x1e9a, 0x0,    0x2436, 0x149c, 0x24b6, 0x24e6, 0x2516, 0x1028, 0x1040, 0x1060, 0x1070, 0x1078, 0x1080, 0x0,
};
pub const kDoorTypeSrcData = [_]u16{
    0x2716, 0x272e, 0x272e, 0x2746, 0x2746, 0x2746, 0x2746, 0x2746, 0x2746, 0x275e, 0x275e, 0x275e, 0x275e, 0x2776, 0x278e, 0x27a6,
    0x27be, 0x27be, 0x27d6, 0x27d6, 0x27ee, 0x2806, 0x2806, 0x281e, 0x2836, 0x2836, 0x2836, 0x2836, 0x284e, 0x2866, 0x2866, 0x2866,
    0x2866, 0x287e, 0x2896, 0x28ae, 0x28c6, 0x28de, 0x28f6, 0x28f6, 0x28f6, 0x290e, 0x2926, 0x2958, 0x2978, 0x2990, 0x2990, 0x2990,
    0x2990, 0x29a8, 0x29c0, 0x29d8,
};
pub const kDoorTypeSrcData2 = [_]u16{
    0x29f0, 0x2a08, 0x2a08, 0x2a20, 0x2a20, 0x2a20, 0x2a20, 0x2a20, 0x2a20, 0x2a38, 0x2a38, 0x2a38, 0x2a38, 0x2a50, 0x2a68, 0x2a80,
    0x2a98, 0x2a98, 0x2a98, 0x2a98, 0x2a98, 0x2ab0, 0x2ac8, 0x2ae0, 0x2af8, 0x2af8, 0x2af8, 0x2af8, 0x2b10, 0x2b28, 0x2b28, 0x2b28,
    0x2b28, 0x2b40, 0x2b58, 0x2b70, 0x2b88, 0x2ba0, 0x2bb8, 0x2bb8, 0x2bb8, 0x2bd0, 0x2be8, 0x2c1a, 0x2c3a, 0x2c52, 0x2c6a, 0x2c6a,
};
pub const kDoorTypeSrcData3 = [_]u16{
    0x2c6a, 0x2c82, 0x2c82, 0x2c9a, 0x2c9a, 0x2c9a, 0x2c9a, 0x2c9a, 0x2c9a, 0x2cb2, 0x2cb2, 0x2cb2, 0x2cb2, 0x2cca, 0x2ce2, 0x2cfa,
    0x2cfa, 0x2cfa, 0x2cfa, 0x2cfa, 0x2cfa, 0x2d12, 0x2d12, 0x2d2a, 0x2d42, 0x2d42, 0x2d42, 0x2d42, 0x2d5a, 0x2d72, 0x2d72, 0x2d72,
    0x2d72, 0x2d8a, 0x2da2, 0x2dba, 0x2dd2, 0x2dea, 0x2e02, 0x2e02, 0x2e02, 0x2e1a, 0x2e32, 0x2e32, 0x2e52, 0x2e6a, 0x2e6a, 0x2e6a,
};
pub const kDoorTypeSrcData4 = [_]u16{
    0x2e6a, 0x2e82, 0x2e82, 0x2e9a, 0x2e9a, 0x2e9a, 0x2e9a, 0x2e9a, 0x2e9a, 0x2eb2, 0x2eb2, 0x2eb2, 0x2eb2, 0x2eca, 0x2ee2, 0x2efa,
    0x2efa, 0x2efa, 0x2efa, 0x2efa, 0x2efa, 0x2f12, 0x2f12, 0x2f2a, 0x2f42, 0x2f42, 0x2f42, 0x2f42, 0x2f5a, 0x2f72, 0x2f72, 0x2f72,
    0x2f72, 0x2f8a, 0x2fa2, 0x2fba, 0x2fd2, 0x2fea, 0x3002, 0x3002, 0x3002, 0x301a, 0x3032, 0x3032, 0x3052, 0x306a, 0x306a,
};
pub const kDoorPositionToTilemapOffs_Up = [_]u16{ 0x21c, 0x23c, 0x25c, 0x39c, 0x3bc, 0x3dc, 0x121c, 0x123c, 0x125c, 0x139c, 0x13bc, 0x13dc };
pub const kDoorPositionToTilemapOffs_Down = [_]u16{ 0xd1c, 0xd3c, 0xd5c, 0xb9c, 0xbbc, 0xbdc, 0x1d1c, 0x1d3c, 0x1d5c, 0x1b9c, 0x1bbc, 0x1bdc };
pub const kDoorPositionToTilemapOffs_Left = [_]u16{ 0x784, 0xf84, 0x1784, 0x78a, 0xf8a, 0x178a, 0x7c4, 0xfc4, 0x17c4, 0x7ca, 0xfca, 0x17ca };
pub const kDoorPositionToTilemapOffs_Right = [_]u16{ 0x7b4, 0xfb4, 0x17b4, 0x7ae, 0xfae, 0x17ae, 0x7f4, 0xff4, 0x17f4, 0x7ee, 0xfee, 0x17ee };
pub const kSpiralTab1 = [_]i8{ 0, 1, 1, -1, 1, 1, 1, 1 };
pub const kTeleportPitLevel1 = [_]i8{ 0, 1, 1 };
pub const kTeleportPitLevel2 = [_]i8{ 0, 0, 1 };
pub const kDoorTypeRemap = [_]u8{
    0,  2,  0,   0,   0,  0,  0,  0,  0,  18, 0, 0,  80, 0, 80, 80,
    96, 98, 100, 102, 82, 90, 80, 82, 84, 86, 0, 80, 80, 0, 0,  0,
    64, 88, 88,  0,   88, 88, 0,  0,
};
pub const kStaircaseTab2 = [_]i8{
    12,  32,  48,  56,  72, -44, -40, -64, -64, -88, 12, 24, 40, 48, 64, -28,
    -40, -56, -64, -80,
};
pub const kStaircaseTab3 = [_]i8{ 4, -4, 4, -4 };
pub const kStaircaseTab4 = [_]i8{ 52, 52, 59, 58 };
pub const kStaircaseTab5 = [_]i8{ 32, -64, 32, -32 };
pub const kMovingWall_Sizes0 = [_]u8{ 5, 7, 11, 15 };
pub const kMovingWall_Sizes1 = [_]u8{ 8, 16, 24, 32 };
pub const kWatergateLayout = [_]u8{
    0x1b, 0xa1, 0xc9,
    0x51, 0xa1, 0xc9,
    0x92, 0xa1, 0xc9,
    0xa1, 0x33, 0xc9,
    0xa1, 0x72, 0xc9,
    0xff, 0xff,
};
pub const kChestOpenMasks = [_]u16{ 0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000 };
pub const kLayoutQuadrantFlags = [_]u8{ 0xF, 0xF, 0xF, 0xF, 0xB, 0xB, 7, 7, 0xF, 0xB, 0xF, 7, 0xB, 0xF, 7, 0xF, 0xE, 0xD, 0xE, 0xD, 0xF, 0xF, 0xE, 0xD, 0xE, 0xD, 0xF, 0xF, 0xA, 9, 6, 5 };
pub const kQuadrantVisitingFlags = [_]u8{ 8, 4, 2, 1, 0xC, 0xC, 3, 3, 0xA, 5, 0xA, 5, 0xF, 0xF, 0xF, 0xF };
pub const kDungeon_MinigameChestPrizes1 = [_]u8{ 0x40, 0x41, 0x34, 0x42, 0x43, 0x44, 0x27, 0x17 };
pub const kDungeon_RupeeChestMinigamePrizes = [_]u8{
    0x47, 0x34, 0x46, 0x34, 0x46, 0x46, 0x34, 0x47, 0x46, 0x47, 0x34, 0x46, 0x47, 0x34, 0x46, 0x47,
    0x34, 0x47, 0x41, 0x47, 0x41, 0x41, 0x47, 0x34, 0x41, 0x34, 0x47, 0x41, 0x34, 0x47, 0x41, 0x34,
};
pub const kDungeon_QueryIfTileLiftable_x = [_]i8{ 7, 7, -3, 16 };
pub const kDungeon_QueryIfTileLiftable_y = [_]i8{ 3, 24, 14, 14 };
pub const kDungeon_QueryIfTileLiftable_rv = [_]u16{ 0x5252, 0x5050, 0x5454, 0x0, 0x2323, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
pub const kDoor_BlastWallUp_Dsts = [_]u16{ 0xd8a, 0xdaa, 0xdca, 0x2b6, 0xab6, 0x12b6 };
pub const kDungPalinfos = [_]DungPalInfo{
    .{ .pal0 = 0, .pal1 = 0, .pal2 = 3, .pal3 = 1 },
    .{ .pal0 = 2, .pal1 = 0, .pal2 = 3, .pal3 = 1 },
    .{ .pal0 = 4, .pal1 = 0, .pal2 = 10, .pal3 = 1 },
    .{ .pal0 = 6, .pal1 = 0, .pal2 = 1, .pal3 = 7 },
    .{ .pal0 = 10, .pal1 = 2, .pal2 = 2, .pal3 = 7 },
    .{ .pal0 = 4, .pal1 = 4, .pal2 = 3, .pal3 = 10 },
    .{ .pal0 = 12, .pal1 = 5, .pal2 = 8, .pal3 = 20 },
    .{ .pal0 = 14, .pal1 = 0, .pal2 = 3, .pal3 = 10 },
    .{ .pal0 = 2, .pal1 = 0, .pal2 = 15, .pal3 = 20 },
    .{ .pal0 = 10, .pal1 = 2, .pal2 = 0, .pal3 = 7 },
    .{ .pal0 = 2, .pal1 = 0, .pal2 = 15, .pal3 = 12 },
    .{ .pal0 = 6, .pal1 = 0, .pal2 = 6, .pal3 = 7 },
    .{ .pal0 = 0, .pal1 = 0, .pal2 = 14, .pal3 = 18 },
    .{ .pal0 = 18, .pal1 = 5, .pal2 = 5, .pal3 = 11 },
    .{ .pal0 = 18, .pal1 = 0, .pal2 = 2, .pal3 = 12 },
    .{ .pal0 = 16, .pal1 = 5, .pal2 = 10, .pal3 = 7 },
    .{ .pal0 = 16, .pal1 = 0, .pal2 = 16, .pal3 = 12 },
    .{ .pal0 = 22, .pal1 = 7, .pal2 = 2, .pal3 = 7 },
    .{ .pal0 = 22, .pal1 = 0, .pal2 = 7, .pal3 = 15 },
    .{ .pal0 = 8, .pal1 = 0, .pal2 = 4, .pal3 = 12 },
    .{ .pal0 = 8, .pal1 = 0, .pal2 = 4, .pal3 = 9 },
    .{ .pal0 = 4, .pal1 = 0, .pal2 = 3, .pal3 = 1 },
    .{ .pal0 = 20, .pal1 = 0, .pal2 = 4, .pal3 = 4 },
    .{ .pal0 = 20, .pal1 = 0, .pal2 = 20, .pal3 = 12 },
    .{ .pal0 = 24, .pal1 = 5, .pal2 = 7, .pal3 = 11 },
    .{ .pal0 = 24, .pal1 = 6, .pal2 = 16, .pal3 = 12 },
    .{ .pal0 = 26, .pal1 = 5, .pal2 = 8, .pal3 = 20 },
    .{ .pal0 = 26, .pal1 = 2, .pal2 = 0, .pal3 = 7 },
    .{ .pal0 = 6, .pal1 = 0, .pal2 = 3, .pal3 = 10 },
    .{ .pal0 = 28, .pal1 = 0, .pal2 = 3, .pal3 = 1 },
    .{ .pal0 = 30, .pal1 = 0, .pal2 = 11, .pal3 = 17 },
    .{ .pal0 = 4, .pal1 = 0, .pal2 = 11, .pal3 = 17 },
    .{ .pal0 = 14, .pal1 = 0, .pal2 = 0, .pal3 = 2 },
    .{ .pal0 = 32, .pal1 = 8, .pal2 = 19, .pal3 = 13 },
    .{ .pal0 = 10, .pal1 = 0, .pal2 = 3, .pal3 = 10 },
    .{ .pal0 = 20, .pal1 = 0, .pal2 = 4, .pal3 = 4 },
    .{ .pal0 = 26, .pal1 = 2, .pal2 = 2, .pal3 = 7 },
    .{ .pal0 = 26, .pal1 = 10, .pal2 = 0, .pal3 = 0 },
    .{ .pal0 = 0, .pal1 = 0, .pal2 = 3, .pal3 = 2 },
    .{ .pal0 = 14, .pal1 = 0, .pal2 = 3, .pal3 = 7 },
    .{ .pal0 = 26, .pal1 = 5, .pal2 = 5, .pal3 = 11 },
};
pub const kDungeon_DrawObjectOffsets_BG1 = [_]u8{
    0,    0x20, 0x7e, 2,    0x20, 0x7e, 4,    0x20, 0x7e, 6,    0x20, 0x7e, 0x80, 0x20, 0x7e, 0x82,
    0x20, 0x7e, 0x84, 0x20, 0x7e, 0x86, 0x20, 0x7e, 0,    0x21, 0x7e, 0x80, 0x21, 0x7e, 0,    0x22,
    0x7e,
};
pub const kDungeon_DrawObjectOffsets_BG2 = [_]u8{
    0,    0x40, 0x7e, 2,    0x40, 0x7e, 4,    0x40, 0x7e, 6,    0x40, 0x7e, 0x80, 0x40, 0x7e, 0x82,
    0x40, 0x7e, 0x84, 0x40, 0x7e, 0x86, 0x40, 0x7e, 0,    0x41, 0x7e, 0x80, 0x41, 0x7e, 0,    0x42,
    0x7e,
};
pub const kUploadBgSrcs = [_]u16{ 0x0, 0x1000, 0x0, 0x40, 0x40, 0x1040, 0x1000, 0x1040, 0x1000, 0x0, 0x40, 0x0, 0x1040, 0x40, 0x1040, 0x1000 };
pub const kUploadBgDsts = [_]u8{ 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15, 4, 8, 12, 16 };
pub const kTileAttrsByDoor = [_]u16{
    0x8080, 0x8484, 0x0,    0x101,  0x8484, 0x8e8e, 0x0,    0x0,    0x8888, 0x8e8e, 0x8080, 0x8080, 0x8282, 0x8080, 0x8080, 0x8080,
    0x8080, 0x8080, 0x8080, 0x8080, 0x8282, 0x8e8e, 0x8080, 0x8282, 0x8080, 0x8080, 0x8080, 0x8282, 0x8282, 0x8080, 0x8080, 0x8080,
    0x8484, 0x8484, 0x8686, 0x8888, 0x8686, 0x8686, 0x8080, 0x8080,
};
pub const kDungeon_Effect_Handler = [_]?*const fn () callconv(.c) void{ @ptrCast(&c.LayerEffect_Nothing), @ptrCast(&c.LayerEffect_Nothing), @ptrCast(&c.LayerEffect_Scroll), @ptrCast(&c.LayerEffect_WaterRapids), @ptrCast(&c.LayerEffect_Trinexx), @ptrCast(&c.LayerEffect_Agahnim2), @ptrCast(&c.LayerEffect_InvisibleFloor), @ptrCast(&c.LayerEffect_Ganon), null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null };
pub const kPushBlockMoveDistances = [_]i16{ -0x100, 0x100, -0x4, 0x4 };
pub const kDungTagroutines = [_]?*const fn (c_int) callconv(.c) void{
    @ptrCast(&c.Dung_TagRoutine_0x00),
    @ptrCast(&c.RoomTag_NorthWestTrigger),
    @ptrCast(&c.Dung_TagRoutine_0x2A),
    @ptrCast(&c.Dung_TagRoutine_0x2B),
    @ptrCast(&c.Dung_TagRoutine_0x2C),
    @ptrCast(&c.Dung_TagRoutine_0x2D),
    @ptrCast(&c.Dung_TagRoutine_0x2E),
    @ptrCast(&c.Dung_TagRoutine_0x2F),
    @ptrCast(&c.Dung_TagRoutine_0x30),
    @ptrCast(&c.RoomTag_QuadrantTrigger),
    @ptrCast(&c.RoomTag_RoomTrigger),
    @ptrCast(&c.RoomTag_NorthWestTrigger),
    @ptrCast(&c.Dung_TagRoutine_0x2A),
    @ptrCast(&c.Dung_TagRoutine_0x2B),
    @ptrCast(&c.Dung_TagRoutine_0x2C),
    @ptrCast(&c.Dung_TagRoutine_0x2D),
    @ptrCast(&c.Dung_TagRoutine_0x2E),
    @ptrCast(&c.Dung_TagRoutine_0x2F),
    @ptrCast(&c.Dung_TagRoutine_0x30),
    @ptrCast(&c.RoomTag_QuadrantTrigger),
    @ptrCast(&c.RoomTag_RoomTrigger_BlockDoor),
    @ptrCast(&c.RoomTag_PrizeTriggerDoorDoor),
    @ptrCast(&c.RoomTag_SwitchTrigger_HoldDoor),
    @ptrCast(&c.RoomTag_SwitchTrigger_ToggleDoor),
    @ptrCast(&c.RoomTag_WaterOff),
    @ptrCast(&c.RoomTag_WaterOn),
    @ptrCast(&c.RoomTag_WaterGate),
    @ptrCast(&c.Dung_TagRoutine_0x1B),
    @ptrCast(&c.RoomTag_MovingWall_East),
    @ptrCast(&c.RoomTag_MovingWall_West),
    @ptrCast(&c.RoomTag_MovingWallTorchesCheck),
    @ptrCast(&c.RoomTag_MovingWallTorchesCheck),
    @ptrCast(&c.RoomTag_Switch_ExplodingWall),
    @ptrCast(&c.RoomTag_Holes0),
    @ptrCast(&c.RoomTag_ChestHoles0),
    @ptrCast(&c.Dung_TagRoutine_0x23),
    @ptrCast(&c.RoomTag_Holes2),
    @ptrCast(&c.RoomTag_GetHeartForPrize),
    @ptrCast(&c.RoomTag_KillRoomBlock),
    @ptrCast(&c.RoomTag_TriggerChest),
    @ptrCast(&c.RoomTag_PullSwitchExplodingWall),
    @ptrCast(&c.RoomTag_NorthWestTrigger),
    @ptrCast(&c.Dung_TagRoutine_0x2A),
    @ptrCast(&c.Dung_TagRoutine_0x2B),
    @ptrCast(&c.Dung_TagRoutine_0x2C),
    @ptrCast(&c.Dung_TagRoutine_0x2D),
    @ptrCast(&c.Dung_TagRoutine_0x2E),
    @ptrCast(&c.Dung_TagRoutine_0x2F),
    @ptrCast(&c.Dung_TagRoutine_0x30),
    @ptrCast(&c.RoomTag_QuadrantTrigger),
    @ptrCast(&c.RoomTag_RoomTrigger),
    @ptrCast(&c.RoomTag_TorchPuzzleDoor),
    @ptrCast(&c.Dung_TagRoutine_0x34),
    @ptrCast(&c.Dung_TagRoutine_0x35),
    @ptrCast(&c.Dung_TagRoutine_0x36),
    @ptrCast(&c.Dung_TagRoutine_0x37),
    @ptrCast(&c.RoomTag_Agahnim),
    @ptrCast(&c.Dung_TagRoutine_0x39),
    @ptrCast(&c.Dung_TagRoutine_0x3A),
    @ptrCast(&c.Dung_TagRoutine_0x3B),
    @ptrCast(&c.RoomTag_PushBlockForChest),
    @ptrCast(&c.RoomTag_GanonDoor),
    @ptrCast(&c.RoomTag_TorchPuzzleChest),
    @ptrCast(&c.RoomTag_RekillableBoss),
};
pub const kDoorAnimUpSrc = [_]u16{ 0x306a, 0x306a, 0x3082, 0x309a, 0x30b2 };
pub const kDoorAnimDownSrc = [_]u16{ 0x30b2, 0x30ca, 0x30e2, 0x30fa, 0x3112 };
pub const kDoorAnimLeftSrc = [_]u16{ 0x3112, 0x312a, 0x3142, 0x315a, 0x3172 };
pub const kDoorAnimRightSrc = [_]u16{ 0x3172, 0x318a, 0x31a2, 0x31ba, 0x31D2 };
pub const kDungeon_IntraRoomTrans = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.DungeonTransition_Subtile_PrepTransition),
    @ptrCast(&c.DungeonTransition_Subtile_ApplyFilter),
    @ptrCast(&c.DungeonTransition_Subtile_ResetShutters),
    @ptrCast(&c.DungeonTransition_ScrollRoom),
    @ptrCast(&c.DungeonTransition_FindSubtileLanding),
    @ptrCast(&c.Dungeon_IntraRoomTrans_State5),
    @ptrCast(&c.DungeonTransition_Subtile_ApplyFilter),
    @ptrCast(&c.DungeonTransition_Subtile_TriggerShutters),
};
pub const kDungeon_InterRoomTrans = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.Module07_02_00_InitializeTransition),
    @ptrCast(&c.Module07_02_01_LoadNextRoom),
    @ptrCast(&c.Module07_02_FadedFilter),
    @ptrCast(&c.Dungeon_InterRoomTrans_State3),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_notDarkRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_State7),
    @ptrCast(&c.DungeonTransition_ScrollRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State9),
    @ptrCast(&c.Dungeon_InterRoomTrans_State10),
    @ptrCast(&c.Dungeon_InterRoomTrans_State9),
    @ptrCast(&c.Dungeon_InterRoomTrans_State12),
    @ptrCast(&c.Dungeon_InterRoomTrans_State13),
    @ptrCast(&c.Module07_02_FadedFilter),
    @ptrCast(&c.Dungeon_InterRoomTrans_State15),
};
pub const kDungeon_Submodule_7_DownFloorTrans = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.Module07_07_00_HandleMusicAndResetRoom),
    @ptrCast(&c.ApplyPaletteFilter_bounce),
    @ptrCast(&c.Dungeon_InitializeRoomFromSpecial),
    @ptrCast(&c.DungeonTransition_TriggerBGC34UpdateAndAdvance),
    @ptrCast(&c.DungeonTransition_TriggerBGC56UpdateAndAdvance),
    @ptrCast(&c.DungeonTransition_LoadSpriteGFX),
    @ptrCast(&c.Module07_07_06_SyncBG1and2),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_notDarkRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_notDarkRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_notDarkRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_Staircase14),
    @ptrCast(&c.Module07_07_0F_FallingFadeIn),
    @ptrCast(&c.Module07_07_10_LandLinkFromFalling),
    @ptrCast(&c.Module07_07_11_CacheRoomAndSetMusic),
};
pub const kWatergateFuncs = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.FloodDam_PrepTiles_init),
    @ptrCast(&c.Watergate_Main_State1),
    @ptrCast(&c.Watergate_Main_State1),
    @ptrCast(&c.Watergate_Main_State1),
    @ptrCast(&c.FloodDam_Expand),
    @ptrCast(&c.FloodDam_Fill),
};
pub const kSpiralStaircaseX = [_]i8{ -28, -28, 24, 24 };
pub const kSpiralStaircaseY = [_]i8{ 16, -10, -10, -32 };
pub const kDungeon_SpiralStaircase = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.Module07_0E_00_InitPriorityAndScreens),
    @ptrCast(&c.Module07_0E_01_HandleMusicAndResetProps),
    @ptrCast(&c.Module07_0E_02_ApplyFilterIf),
    @ptrCast(&c.Dungeon_InitializeRoomFromSpecial),
    @ptrCast(&c.DungeonTransition_TriggerBGC34UpdateAndAdvance),
    @ptrCast(&c.DungeonTransition_TriggerBGC56UpdateAndAdvance),
    @ptrCast(&c.DungeonTransition_LoadSpriteGFX),
    @ptrCast(&c.Dungeon_SyncBackgroundsFromSpiralStairs),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_notDarkRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_SpiralStaircase11),
    @ptrCast(&c.Dungeon_SpiralStaircase12),
    @ptrCast(&c.Dungeon_SpiralStaircase11),
    @ptrCast(&c.Dungeon_SpiralStaircase12),
    @ptrCast(&c.Dungeon_DoubleApplyAndIncrementGrayscale),
    @ptrCast(&c.Dungeon_AdvanceThenSetBossMusicUnorthodox),
    @ptrCast(&c.Dungeon_SpiralStaircase17),
    @ptrCast(&c.Dungeon_SpiralStaircase18),
    @ptrCast(&c.Module07_0E_13_SetRoomAndLayerAndCache),
};
pub const kDungeon_Submodule_F = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.Module07_0F_00_InitSpotlight),
    @ptrCast(&c.Module07_0F_01_OperateSpotlight),
};
pub const kDungeon_StraightStaircase = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.Module07_10_00_InitStairs),
    @ptrCast(&c.Module07_10_01_ClimbStairs),
};
pub const kDungeon_StraightStaircaseDown = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.Module07_08_00_InitStairs),
    @ptrCast(&c.Module07_08_01_ClimbStairs),
};
pub const kDungeon_StraightStairs = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.Module07_11_00_PrepAndReset),
    @ptrCast(&c.Module07_11_01_FadeOut),
    @ptrCast(&c.Module07_11_02_LoadAndPrepRoom),
    @ptrCast(&c.Module07_11_03_FilterAndLoadBGChars),
    @ptrCast(&c.Module07_11_04_FilterDoBGAndResetSprites),
    @ptrCast(&c.Dungeon_SpiralStaircase11),
    @ptrCast(&c.Dungeon_SpiralStaircase12),
    @ptrCast(&c.Dungeon_SpiralStaircase11),
    @ptrCast(&c.Dungeon_SpiralStaircase12),
    @ptrCast(&c.Module07_11_09_LoadSpriteGraphics),
    @ptrCast(&c.Module07_11_0A_ScrollCamera),
    @ptrCast(&c.Module07_11_0B_PrepDestination),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_notDarkRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_DoubleApplyAndIncrementGrayscale),
    @ptrCast(&c.Module07_11_19_SetSongAndFilter),
    @ptrCast(&c.Module07_11_11_KeepSliding),
    @ptrCast(&c.ResetThenCacheRoomEntryProperties),
};
pub const kDungeon_Teleport = [_]?*const fn () callconv(.c) void{
    @ptrCast(&c.ResetTransitionPropsAndAdvance_ResetInterface),
    @ptrCast(&c.Module07_15_01_ApplyMosaicAndFilter),
    @ptrCast(&c.Dungeon_InitializeRoomFromSpecial),
    @ptrCast(&c.DungeonTransition_LoadSpriteGFX),
    @ptrCast(&c.Module07_15_04_SyncRoomPropsAndBuildOverlay),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_notDarkRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_notDarkRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_InterRoomTrans_notDarkRoom),
    @ptrCast(&c.Dungeon_InterRoomTrans_State4),
    @ptrCast(&c.Dungeon_Staircase14),
    @ptrCast(&c.Module07_15_0E_FadeInFromWarp),
    @ptrCast(&c.Module07_15_0F_FinalizeAndCacheEntry),
};
pub const kDungeonSubmodules = [_]?*const fn () callconv(.c) void{ @ptrCast(&c.Module07_00_PlayerControl), @ptrCast(&c.Module07_01_SubtileTransition), @ptrCast(&c.Module07_02_SupertileTransition), @ptrCast(&c.Module07_03_OverlayChange), @ptrCast(&c.Module07_04_UnlockDoor), @ptrCast(&c.Module07_05_ControlShutters), @ptrCast(&c.Module07_06_FatInterRoomStairs), @ptrCast(&c.Module07_07_FallingTransition), @ptrCast(&c.Module07_08_NorthIntraRoomStairs), @ptrCast(&c.Module07_09_OpenCrackedDoor), @ptrCast(&c.Module07_0A_ChangeBrightness), @ptrCast(&c.Module07_0B_DrainSwampPool), @ptrCast(&c.Module07_0C_FloodSwampWater), @ptrCast(&c.Module07_0D_FloodDam), @ptrCast(&c.Module07_0E_SpiralStairs), @ptrCast(&c.Module07_0F_LandingWipe), @ptrCast(&c.Module07_10_SouthIntraRoomStairs), @ptrCast(&c.Module07_11_StraightInterroomStairs), @ptrCast(&c.Module07_11_StraightInterroomStairs), @ptrCast(&c.Module07_11_StraightInterroomStairs), @ptrCast(&c.Module07_14_RecoverFromFall), @ptrCast(&c.Module07_15_WarpPad), @ptrCast(&c.Module07_16_UpdatePegs), @ptrCast(&c.Module07_17_PressurePlate), @ptrCast(&c.Module07_18_RescuedMaiden), @ptrCast(&c.Module07_19_MirrorFade), @ptrCast(&c.Module07_1A_RoomDraw_OpenTriforceDoor_bounce), null, null, null, null };
pub const kDungAnimatedTiles = [_]u8{
    0x5d, 0x5d, 0x5d, 0x5d, 0x5d, 0x5d, 0x5d, 0x5f, 0x5d, 0x5f, 0x5f, 0x5e, 0x5f, 0x5e, 0x5e, 0x5d,
    0x5d, 0x5e, 0x5d, 0x5d, 0x5d, 0x5d, 0x5d, 0x5d,
};
