//! Which pendant or crystal each dungeon gives, for the game's own code to
//! ask wherever it hands a prize over or checks whether one's been taken.
//! The game keys all of that on the dungeon (cur_palace_index_x2 >> 1, the
//! "palace index"); while a randomized file is being played these follow
//! the placement's prize locations instead, and otherwise they give the
//! game's own answers.
//!
//! A pendant's bit is the one the game sets in $7EF374 when its item is
//! received (Courage 4, Wisdom 1, Power 2), and a crystal's the one VT
//! gives it in $7EF37A, so the award, every later check of the bit, and the
//! pause menu all agree on which prize it is.
const std = @import("std");
const game = @import("game.zig");
const items = @import("items.zig");
const locs = @import("locations.zig");

const Item = items.Item;
const Loc = locs.Loc;

/// The game's own prize bit per palace index (rtl.kDungeonCrystalPendantBit):
/// a pendant's bit for the pendant dungeons, a crystal's for the crystal
/// ones, and 0 for the dungeons without a prize.
pub const kVanillaBit = [13]u8{ 0, 0, 4, 2, 0, 16, 2, 1, 64, 4, 1, 32, 8 };

/// The game's own falling item per palace index (kBossFinishedFallingItem
/// in RoomTag_GetHeartForPrize): 1 the Pendant of Courage, 2 Power, 3
/// Wisdom, 6 a crystal.
pub const kVanillaFalling = [13]u8{ 0, 0, 1, 2, 0, 6, 6, 6, 6, 6, 3, 6, 6 };

/// The randomizer's prize location for each palace index, where it has one.
/// Palace indexes: 0 sewers, 1 Hyrule Castle, 2 Eastern, 3 Desert, 4
/// Agahnim's Tower, 5 Swamp, 6 Palace of Darkness, 7 Misery Mire, 8 Skull
/// Woods, 9 Ice Palace, 10 Tower of Hera, 11 Thieves' Town, 12 Turtle Rock,
/// 13 Ganon's Tower.
const kPrizeLoc = [13]?Loc{
    null,               null,                .eastern_palace_prize,     .desert_palace_prize,
    null,               .swamp_palace_prize, .palace_of_darkness_prize, .misery_mire_prize,
    .skull_woods_prize, .ice_palace_prize,   .tower_of_hera_prize,      .thieves_town_prize,
    .turtle_rock_prize,
};

/// The palace index of each of the world map's pendant markers, in the
/// order WorldMap_HandleSprites draws them (kPendantBitMask's order).
const kPendantMarkerPalace = [3]u8{ 2, 10, 3 };

/// The palace index of each of the world map's crystal markers, in the
/// order WorldMap_HandleSprites draws them (kCrystalBitMask's order).
const kCrystalMarkerPalace = [7]u8{ 6, 8, 12, 11, 7, 9, 5 };

/// The bit a prize item sets: in $7EF374 for a pendant, $7EF37A for a
/// crystal. 0 for anything else.
pub fn itemBit(it: Item) u8 {
    return switch (it) {
        .pendant_of_courage => 0x04,
        .pendant_of_power => 0x02,
        .pendant_of_wisdom => 0x01,
        .crystal1 => 0x02,
        .crystal2 => 0x10,
        .crystal3 => 0x40,
        .crystal4 => 0x20,
        .crystal5 => 0x04,
        .crystal6 => 0x01,
        .crystal7 => 0x08,
        else => 0,
    };
}

/// The prize item placed at palace index `palace`, while randomized and if
/// it's a pendant or crystal (v1 keeps them so; anything else falls back to
/// the game's own prize).
fn placed(palace: u8) ?Item {
    if (palace >= kPrizeLoc.len) return null;
    const loc = kPrizeLoc[palace] orelse return null;
    const it = game.itemAt(loc) orelse return null;
    return switch (items.kind(it)) {
        .pendant, .crystal => it,
        else => null,
    };
}

/// The bit for palace index `palace`'s prize, for testing or setting in
/// $7EF374 (a pendant dungeon) or $7EF37A (a crystal one): what
/// rtl.kDungeonCrystalPendantBit gives, following the placement.
pub fn prizeBit(palace: u8) u8 {
    if (palace >= kVanillaBit.len) return 0;
    const it = placed(palace) orelse return kVanillaBit[palace];
    return itemBit(it);
}

/// What palace index `palace`'s boss drops, as Ancilla_SpawnFallingPrize's
/// item (an index into kFallingItem_Type): the placed pendant, or a crystal.
pub fn fallingItem(palace: u8) u8 {
    if (palace >= kVanillaFalling.len) return 0;
    const it = placed(palace) orelse return kVanillaFalling[palace];
    return switch (it) {
        .pendant_of_courage => 1,
        .pendant_of_power => 2,
        .pendant_of_wisdom => 3,
        else => 6,
    };
}

/// The pendant bit that hides world map pendant marker `k` once Link has it:
/// the prize of the dungeon the marker stands on.
pub fn pendantMarkerBit(k: usize, vanilla: u8) u8 {
    if (!game.active() or k >= kPendantMarkerPalace.len) return vanilla;
    return prizeBit(kPendantMarkerPalace[k]);
}

/// The crystal bit that hides world map crystal marker `k` once Link has it.
pub fn crystalMarkerBit(k: usize, vanilla: u8) u8 {
    if (!game.active() or k >= kCrystalMarkerPalace.len) return vanilla;
    return prizeBit(kCrystalMarkerPalace[k]);
}

/// World map pendant marker `k`'s sprite word (character in the high byte,
/// attributes in the low), recolored for the pendant its dungeon holds:
/// Courage green, Power blue, Wisdom red, as the game colors them.
pub fn pendantMarkerSprite(k: usize, vanilla: u16) u16 {
    if (!game.active() or k >= kPendantMarkerPalace.len or vanilla >> 8 == 0) return vanilla;
    const it = placed(kPendantMarkerPalace[k]) orelse return vanilla;
    const attr: u16 = switch (it) {
        .pendant_of_courage => 0x38,
        .pendant_of_power => 0x34,
        .pendant_of_wisdom => 0x32,
        else => return vanilla,
    };
    return (vanilla & 0xff00) | attr;
}

test "inactive, every answer is the game's own" {
    game.stop();
    for (0..13) |p| {
        try std.testing.expectEqual(kVanillaBit[p], prizeBit(@intCast(p)));
        try std.testing.expectEqual(kVanillaFalling[p], fallingItem(@intCast(p)));
    }
    try std.testing.expectEqual(@as(u8, 4), pendantMarkerBit(0, 4));
    try std.testing.expectEqual(@as(u16, 0x6038), pendantMarkerSprite(0, 0x6038));
}

test "the vanilla tables are the vanilla prizes' bits" {
    // Eastern Courage, Desert Power, Hera Wisdom; PoD Crystal1 and so on.
    try std.testing.expectEqual(itemBit(.pendant_of_courage), kVanillaBit[2]);
    try std.testing.expectEqual(itemBit(.pendant_of_power), kVanillaBit[3]);
    try std.testing.expectEqual(itemBit(.pendant_of_wisdom), kVanillaBit[10]);
    try std.testing.expectEqual(itemBit(.crystal1), kVanillaBit[6]);
    try std.testing.expectEqual(itemBit(.crystal2), kVanillaBit[5]);
    try std.testing.expectEqual(itemBit(.crystal3), kVanillaBit[8]);
    try std.testing.expectEqual(itemBit(.crystal4), kVanillaBit[11]);
    try std.testing.expectEqual(itemBit(.crystal5), kVanillaBit[9]);
    try std.testing.expectEqual(itemBit(.crystal6), kVanillaBit[7]);
    try std.testing.expectEqual(itemBit(.crystal7), kVanillaBit[12]);
}

test "a seed's prizes cover each pendant and crystal bit once" {
    var s: u64 = 1;
    while (s <= 20) : (s += 1) {
        try std.testing.expect(game.start(s, .{}));
        defer game.stop();
        var pendants: u8 = 0;
        var crystals: u8 = 0;
        for (kPendantMarkerPalace) |p| {
            const b = prizeBit(p);
            try std.testing.expect(@popCount(b) == 1 and pendants & b == 0);
            pendants |= b;
            const f = fallingItem(p);
            try std.testing.expect(f >= 1 and f <= 3);
        }
        for (kCrystalMarkerPalace) |p| {
            const b = prizeBit(p);
            try std.testing.expect(@popCount(b) == 1 and crystals & b == 0);
            crystals |= b;
            try std.testing.expectEqual(@as(u8, 6), fallingItem(p));
        }
        try std.testing.expectEqual(@as(u8, 7), pendants);
        try std.testing.expectEqual(@as(u8, 0x7f), crystals);
    }
}
