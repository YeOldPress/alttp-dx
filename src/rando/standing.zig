//! The items that stand on the ground or come out of the water rather than
//! out of a chest: the heart pieces, the Lost Woods mushroom, the catfish's
//! gift and the key caged in the Tower of Hera's basement. Which location
//! each of the game's sprites is, and the flags that say it's been taken.
//!
//! One heart piece sprite serves sixteen of these, told apart as
//! z3randomizer does (heartpieces.asm, LoadIndoorValue and LoadOutdoorValue):
//! by the dungeon room it's in, or the overworld area outside. Two share an
//! area with a tablet (Spectacle Rock with the Ether Tablet, Desert Ledge
//! with the Bombos Tablet) and are told from it by where they stand, and the
//! two of room 0x11b (Cave 45 and the Graveyard Ledge cave, two halves of
//! one room) by which half, the same bit the game keeps each one's taken
//! flag by. Every heart piece keeps the game's own taken flag: bit 6 of its
//! area's overworld event byte, or a room flag (HeartUpgrade_SetObtainedFlag
//! in sprite_main.zig). The Digging Game's heart piece (area 0x68) isn't one
//! of these; it's left to the digging game.
//!
//! The mushroom and the catfish say they've been taken with the item the
//! game gives there (the mushroom in Link's hands, the Quake Medallion), so
//! a randomized file uses z3randomizer's NpcFlags (sram.asm) instead, which
//! the item tracker reads: 0x20 of 0x410 the catfish, 0x10 of 0x411 the
//! mushroom. The caged key keeps the game's flag for it, the room's 0x4000.
const std = @import("std");
const locs = @import("locations.zig");
const game = @import("game.zig");

const Loc = locs.Loc;

/// The game's ram, as variables.zig declares it. Only the functions that run
/// in the game reach it, so the randomizer's own tests build without it.
extern var g_ram: [131072]u8;

/// The save block (0x500 bytes, $7EF000 on).
fn sram() []u8 {
    return g_ram[0xf000..0xf500];
}

/// The heart piece sprites that stand in a dungeon room (a cave, here), by
/// room number.
const kIndoor = [_]struct { room: u16, loc: Loc }{
    .{ .room = 0xe1, .loc = .lost_woods_hideout },
    .{ .room = 0xe2, .loc = .lumberjack_tree },
    .{ .room = 0xea, .loc = .spectacle_rock_cave },
    .{ .room = 0x126, .loc = .checkerboard_cave },
    .{ .room = 0x127, .loc = .hammer_pegs },
};

/// Room 0x11b holds two: Cave 45 in its left half, the Graveyard Ledge's in
/// its right.
const kTwinRoom = 0x11b;

/// The heart piece sprites that stand outside, by overworld area.
const kOutdoor = [_]struct { area: u16, loc: Loc }{
    .{ .area = 0x03, .loc = .spectacle_rock },
    .{ .area = 0x05, .loc = .floating_island },
    .{ .area = 0x28, .loc = .maze_race },
    .{ .area = 0x30, .loc = .desert_ledge },
    .{ .area = 0x35, .loc = .lake_hylia_island },
    .{ .area = 0x3b, .loc = .sunken_treasure },
    .{ .area = 0x4a, .loc = .bumper_cave },
    .{ .area = 0x5b, .loc = .pyramid },
    .{ .area = 0x81, .loc = .zoras_ledge },
};

/// The location of a heart piece sprite standing at world x `x` (and, for a
/// room, sprite_x_hi `x_hi`) in dungeon room `room` when `indoors`, else in
/// overworld area `area`. Null for a heart piece that isn't one of these.
pub fn heartPieceLoc(indoors: bool, room: u16, area: u16, x: u16, x_hi: u8) ?Loc {
    if (indoors) {
        if (room == kTwinRoom) return if (x_hi & 1 == 0) .cave_45 else .graveyard_ledge;
        for (kIndoor) |e| if (e.room == room) return e.loc;
        return null;
    }
    // The tablets stand at the left of Spectacle Rock's area and the right
    // of the Desert Ledge's: z3randomizer's 1890 and 512.
    if (area == 0x03 and x < 1890) return null;
    if (area == 0x30 and x >= 512) return null;
    for (kOutdoor) |e| if (e.area == area) return e.loc;
    return null;
}

/// The receipt numbers of the game's own items at these spots, which are
/// given the game's own way (a heart piece's quarter and its message, a key
/// for the dungeon's count) when they're what's placed.
pub const kHeartPiece: u8 = 0x17;
pub const kSmallKey: u8 = 0x24;

/// What the heart piece sprite heartPieceLoc describes gives while
/// randomized, or null when it should be the game's heart piece: the file
/// isn't randomized, the sprite isn't one of these, or a heart piece is
/// what's placed there.
pub fn heartPieceGive(indoors: bool, room: u16, area: u16, x: u16, x_hi: u8) ?u8 {
    if (!game.active()) return null;
    const loc = heartPieceLoc(indoors, room, area, x, x_hi) orelse return null;
    const b = game.giveAt(loc) orelse return null;
    return if (b == kHeartPiece) null else b;
}

/// The Tower of Hera's basement, where the caged key stands.
pub const kHeraBasementRoom = 0x87;

/// Whether the small key sprite with sprite_die_action `die_action` in
/// dungeon room `room` is the caged one: the room's first key, whose taken
/// flag is 0x4000.
pub fn isHeraBasementKey(room: u16, die_action: u8) bool {
    return room == kHeraBasementRoom and die_action == 0;
}

/// What the small key sprite isHeraBasementKey describes gives while
/// randomized, or null when it should be the game's key: the file isn't
/// randomized, it's another key, or a small key is what's placed there.
pub fn heraCageGive(room: u16, die_action: u8) ?u8 {
    if (!isHeraBasementKey(room, die_action)) return null;
    const b = game.giveAt(.tower_of_hera_basement_cage) orelse return null;
    return if (b == kSmallKey) null else b;
}

/// z3randomizer's NpcFlags, which the tracker reads, as offsets into the
/// save block and their bits.
pub const kCatfishFlag: Flag = .{ .off = 0x410, .mask = 0x20 };
pub const kMushroomFlag: Flag = .{ .off = 0x411, .mask = 0x10 };
pub const Flag = struct { off: u16, mask: u8 };

pub fn takenIn(block: []const u8, f: Flag) bool {
    return block[f.off] & f.mask != 0;
}

pub fn markIn(block: []u8, f: Flag) void {
    block[f.off] |= f.mask;
}

/// Whether flag `f` says its item's been taken in the file being played.
pub fn taken(f: Flag) bool {
    return takenIn(sram(), f);
}

/// Notes in the file being played that flag `f`'s item has been taken.
pub fn mark(f: Flag) void {
    markIn(sram(), f);
}

const testing = std.testing;

test "every standing location is one of the game's sprites, once" {
    var seen: [locs.kLocs.len]u8 = @splat(0);
    for (kIndoor) |e| seen[@backingInt(e.loc)] += 1;
    for (kOutdoor) |e| seen[@backingInt(e.loc)] += 1;
    seen[@backingInt(Loc.cave_45)] += 1;
    seen[@backingInt(Loc.graveyard_ledge)] += 1;
    seen[@backingInt(Loc.mushroom)] += 1;
    seen[@backingInt(Loc.catfish)] += 1;
    seen[@backingInt(Loc.tower_of_hera_basement_cage)] += 1;
    for (locs.kLocs, 0..) |info, i| {
        const want: u8 = switch (info.kind) {
            .standing, .standing_hera_basement => 1,
            else => 0,
        };
        try testing.expectEqual(want, seen[i]);
    }
}

test "heart pieces are told apart by room, area and where they stand" {
    try testing.expectEqual(Loc.cave_45, heartPieceLoc(true, 0x11b, 0, 0, 0x02).?);
    try testing.expectEqual(Loc.graveyard_ledge, heartPieceLoc(true, 0x11b, 0, 0, 0x03).?);
    try testing.expectEqual(Loc.hammer_pegs, heartPieceLoc(true, 0x127, 0x40, 0, 0).?);
    try testing.expectEqual(@as(?Loc, null), heartPieceLoc(true, 0x81, 0x81, 0, 0));
    try testing.expectEqual(Loc.zoras_ledge, heartPieceLoc(false, 0x127, 0x81, 0, 0).?);
    try testing.expectEqual(Loc.spectacle_rock, heartPieceLoc(false, 0, 0x03, 1900, 7).?);
    try testing.expectEqual(@as(?Loc, null), heartPieceLoc(false, 0, 0x03, 1700, 6));
    try testing.expectEqual(Loc.desert_ledge, heartPieceLoc(false, 0, 0x30, 300, 1).?);
    try testing.expectEqual(@as(?Loc, null), heartPieceLoc(false, 0, 0x30, 700, 2));
    // The Digging Game's is the digging game's.
    try testing.expectEqual(@as(?Loc, null), heartPieceLoc(false, 0, 0x68, 0x100, 1));
}

test "the npc flags are the tracker's" {
    const tracker = [_]Flag{ kCatfishFlag, kMushroomFlag };
    var block: [0x500]u8 = @splat(0);
    for (tracker) |f| {
        try testing.expect(!takenIn(&block, f));
        markIn(&block, f);
        try testing.expect(takenIn(&block, f));
    }
    try testing.expectEqual(@as(u8, 0x20), block[0x410]);
    try testing.expectEqual(@as(u8, 0x10), block[0x411]);
}
