//! Port of src/features.h: the extensions this project adds on top of the
//! original game, plus the handful of work-ram locations they live in.
//!
//! These offsets sit in bytes the original game never used, which is why they
//! are declared here rather than in the generated variables.zig.
const std = @import("std");
const vars = @import("variables.zig");

const g_ram = &vars.g_ram;

/// Special RAM locations that are unused but used here for compat things.
pub const kRam_APUI00 = 0x648;
pub const kRam_CrystalRotateCounter = 0x649;
pub const kRam_BugsFixed = 0x64a;
pub const kRam_Features0 = 0x64c;

pub const kBugFix_PolyRenderer = 1;
pub const kBugFix_AncillaOverwrites = 1;
pub const kBugFix_Latest = 1;

// Enum values for kRam_Features0
pub const kFeatures0_ExtendScreen64: u32 = 1;
pub const kFeatures0_SwitchLR: u32 = 2;
pub const kFeatures0_TurnWhileDashing: u32 = 4;
pub const kFeatures0_MirrorToDarkworld: u32 = 8;
pub const kFeatures0_CollectItemsWithSword: u32 = 16;
pub const kFeatures0_BreakPotsWithSword: u32 = 32;
pub const kFeatures0_DisableLowHealthBeep: u32 = 64;
pub const kFeatures0_SkipIntroOnKeypress: u32 = 128;
pub const kFeatures0_ShowMaxItemsInYellow: u32 = 256;
pub const kFeatures0_MoreActiveBombs: u32 = 512;
/// This is set for visual fixes that don't affect game behavior but will
/// affect ram compare.
pub const kFeatures0_WidescreenVisualFixes: u32 = 1024;
pub const kFeatures0_CarryMoreRupees: u32 = 2048;
pub const kFeatures0_MiscBugFixes: u32 = 4096;
pub const kFeatures0_CancelBirdTravel: u32 = 8192;
pub const kFeatures0_GameChangingBugFixes: u32 = 16384;
pub const kFeatures0_SwitchLRLimit: u32 = 32768;
pub const kFeatures0_DimFlashes: u32 = 65536;
/// A second item on X: held on an item in the item menu, X takes it, and in
/// play X uses it (the map moves to L and R together once X has one). Split out of
/// SwitchLR, which used to switch it on along with L and R.
pub const kFeatures0_ItemOnX: u32 = 131072;
/// The digging game hands its heart piece over once you've gone long enough
/// without one, rather than leaving it entirely to the dice.
pub const kFeatures0_DiggingGamePity: u32 = 262144;

pub const enhanced_features0: *align(1) u32 = @ptrCast(&g_ram[0x64c]);
pub const msu_curr_sample: *align(1) u32 = @ptrCast(&g_ram[0x650]);
pub const msu_volume: *u8 = @ptrCast(&g_ram[0x654]);
pub const msu_track: *u8 = @ptrCast(&g_ram[0x655]);
/// 4x6 bytes
pub const hud_inventory_order: [*]u8 = @ptrCast(&g_ram[0x225]);
pub const hud_cur_item_x: *u8 = @ptrCast(&g_ram[0x656]);
pub const hud_cur_item_l: *u8 = @ptrCast(&g_ram[0x657]);
pub const hud_cur_item_r: *u8 = @ptrCast(&g_ram[0x658]);

const testing = std.testing;

test "feature accessors land on the documented ram offsets" {
    const base = @intFromPtr(&g_ram[0]);
    try testing.expectEqual(@as(usize, kRam_Features0), @intFromPtr(enhanced_features0) - base);
    try testing.expectEqual(@as(usize, 0x650), @intFromPtr(msu_curr_sample) - base);
    try testing.expectEqual(@as(usize, 0x654), @intFromPtr(msu_volume) - base);
    try testing.expectEqual(@as(usize, 0x655), @intFromPtr(msu_track) - base);
    try testing.expectEqual(@as(usize, 0x225), @intFromPtr(hud_inventory_order) - base);
    try testing.expectEqual(@as(usize, 0x656), @intFromPtr(hud_cur_item_x) - base);
    try testing.expectEqual(@as(usize, 0x658), @intFromPtr(hud_cur_item_r) - base);
}

test "the feature bits are distinct single bits" {
    const all = [_]u32{
        kFeatures0_ExtendScreen64,        kFeatures0_SwitchLR,
        kFeatures0_TurnWhileDashing,      kFeatures0_MirrorToDarkworld,
        kFeatures0_CollectItemsWithSword, kFeatures0_BreakPotsWithSword,
        kFeatures0_DisableLowHealthBeep,  kFeatures0_SkipIntroOnKeypress,
        kFeatures0_ShowMaxItemsInYellow,  kFeatures0_MoreActiveBombs,
        kFeatures0_WidescreenVisualFixes, kFeatures0_CarryMoreRupees,
        kFeatures0_MiscBugFixes,          kFeatures0_CancelBirdTravel,
        kFeatures0_GameChangingBugFixes,  kFeatures0_SwitchLRLimit,
        kFeatures0_DimFlashes,            kFeatures0_ItemOnX,
        kFeatures0_DiggingGamePity,
    };
    var seen: u32 = 0;
    for (all) |bit| {
        try testing.expectEqual(@as(u32, 1), @popCount(bit));
        try testing.expectEqual(@as(u32, 0), seen & bit); // no duplicates
        seen |= bit;
    }
}

test "the feature word is a 32-bit view of the same four bytes" {
    @memset(g_ram[0x648..0x660], 0);
    enhanced_features0.* = kFeatures0_TurnWhileDashing | kFeatures0_DimFlashes;
    try testing.expectEqual(@as(u8, 0x04), g_ram[0x64c]);
    try testing.expectEqual(@as(u8, 0x01), g_ram[0x64e]);
    try testing.expect(enhanced_features0.* & kFeatures0_TurnWhileDashing != 0);
    try testing.expect(enhanced_features0.* & kFeatures0_MiscBugFixes == 0);
}
