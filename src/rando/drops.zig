//! The spots that hand an item over without a chest or an NPC: the heart
//! container each boss leaves, the two medallion tablets, the Master Sword
//! Pedestal, and the three things Link dashes into (the Library's Book of
//! Mudora and the keys in Desert Palace's and Ganon's Tower's torches).
//!
//! The game code at each one asks here which randomizer location it is,
//! and gives game.giveAt's item instead of its own while a randomized file
//! is being played. Most keep the game's own "taken" flag: the boss's
//! room bit, the pedestal's overworld bit, the torch's room bit. The
//! tablets and the Library can't, since the game's flag for them is having
//! the medallion or the book, which a randomized file can come by
//! elsewhere; those use z3randomizer's NPC flags at 0x410 and 0x411 of the
//! save block (its npcitems.asm and tablets.asm), the same bits the item
//! tracker reads.
const std = @import("std");
const game = @import("game.zig");
const locs = @import("locations.zig");

const Loc = locs.Loc;

/// The game's ram, as variables.zig declares it. Only the functions that run
/// in the game reach it, so the randomizer's own tests build without it.
extern var g_ram: [131072]u8;

/// A bit in the save block that says a spot's item has been taken.
pub const Flag = struct { offset: u16, mask: u8 };

/// The Library's book (z3randomizer's ItemSet_Library).
pub const kLibraryFlag = Flag{ .offset = 0x410, .mask = 0x80 };
/// The Ether Tablet's item (ItemSet_EtherTablet).
pub const kEtherTabletFlag = Flag{ .offset = 0x411, .mask = 0x01 };
/// The Bombos Tablet's item (ItemSet_BombosTablet).
pub const kBombosTabletFlag = Flag{ .offset = 0x411, .mask = 0x02 };

/// Each boss room and the location of the heart container its boss leaves,
/// as z3randomizer's LoadBossValue keys them. Ganon's Tower's rematches
/// with the Armos Knights, the Lanmolas and Moldorm happen in rooms of
/// their own, and the game never lets those drop anything.
const kBossRooms = [_]struct { room: u16, loc: Loc }{
    .{ .room = 0xc8, .loc = .eastern_palace_boss }, // Armos Knights
    .{ .room = 0x33, .loc = .desert_palace_boss }, // Lanmolas
    .{ .room = 0x07, .loc = .tower_of_hera_boss }, // Moldorm
    .{ .room = 0x5a, .loc = .palace_of_darkness_boss }, // Helmasaur King
    .{ .room = 0x06, .loc = .swamp_palace_boss }, // Arrghus
    .{ .room = 0x29, .loc = .skull_woods_boss }, // Mothula
    .{ .room = 0xac, .loc = .thieves_town_boss }, // Blind
    .{ .room = 0xde, .loc = .ice_palace_boss }, // Kholdstare
    .{ .room = 0x90, .loc = .misery_mire_boss }, // Vitreous
    .{ .room = 0xa4, .loc = .turtle_rock_boss }, // Trinexx
};

/// The rooms of the dash items (the game's sprite 0x3b), and their
/// locations. The Library is the only one indoors that isn't a key.
const kDashRooms = [_]struct { room: u16, loc: Loc }{
    .{ .room = 0x107, .loc = .library },
    .{ .room = 0x73, .loc = .desert_palace_torch },
    .{ .room = 0x8c, .loc = .ganons_tower_bobs_torch },
};

/// The overworld screen of the Ether Tablet. The game tells the two tablets
/// apart by it, and anywhere else is the Bombos Tablet.
const kEtherScreen = 3;

/// The location of the heart container a boss leaves in dungeon room
/// `room`, or null when it isn't a boss room.
pub fn bossLoc(room: u16) ?Loc {
    for (kBossRooms) |b| {
        if (b.room == room) return b.loc;
    }
    return null;
}

/// The location of the dash item in dungeon room `room`, if it has one.
pub fn dashLoc(room: u16) ?Loc {
    for (kDashRooms) |d| {
        if (d.room == room) return d.loc;
    }
    return null;
}

/// The location of the tablet on overworld screen `screen`.
pub fn tabletLoc(screen: u8) Loc {
    return if (screen == kEtherScreen) .ether_tablet else .bombos_tablet;
}

/// The flag that says the tablet on overworld screen `screen` gave its item.
pub fn tabletFlag(screen: u8) Flag {
    return if (screen == kEtherScreen) kEtherTabletFlag else kBombosTabletFlag;
}

/// What the boss of room `room` leaves while randomized, as a receipt
/// number, or null to leave the game's heart container.
pub fn bossGive(room: u16) ?u8 {
    return game.giveAt(bossLoc(room) orelse return null);
}

/// What the dash item in room `room` gives while randomized, or null.
pub fn dashGive(room: u16) ?u8 {
    return game.giveAt(dashLoc(room) orelse return null);
}

/// What the tablet on overworld screen `screen` gives while randomized, or
/// null.
pub fn tabletGive(screen: u8) ?u8 {
    return game.giveAt(tabletLoc(screen));
}

/// Whether `flag` is set in save block `block`.
pub fn isSetIn(flag: Flag, block: []const u8) bool {
    return block[flag.offset] & flag.mask != 0;
}

/// Whether `flag` is set in Link's save block.
pub fn taken(flag: Flag) bool {
    return isSetIn(flag, g_ram[0xf000..0xf500]);
}

/// Sets `flag` in Link's save block.
pub fn take(flag: Flag) void {
    g_ram[0xf000 + @as(usize, flag.offset)] |= flag.mask;
}

test "each boss and dash location has one room" {
    var seen = std.EnumSet(Loc){};
    for (kBossRooms) |b| {
        try std.testing.expectEqual(locs.Kind.drop, locs.kLocs[@backingInt(b.loc)].kind);
        try std.testing.expect(!seen.contains(b.loc));
        seen.insert(b.loc);
        try std.testing.expectEqual(b.loc, bossLoc(b.room).?);
    }
    for (kDashRooms) |d| {
        try std.testing.expectEqual(locs.Kind.dash, locs.kLocs[@backingInt(d.loc)].kind);
        try std.testing.expectEqual(d.loc, dashLoc(d.room).?);
    }
    // Agahnim's room, and Ganon's Tower's Moldorm.
    try std.testing.expectEqual(@as(?Loc, null), bossLoc(0x20));
    try std.testing.expectEqual(@as(?Loc, null), bossLoc(0x4d));
}

test "the tablets are told apart by their screen" {
    try std.testing.expectEqual(Loc.ether_tablet, tabletLoc(3));
    try std.testing.expectEqual(Loc.bombos_tablet, tabletLoc(0x30));
    try std.testing.expectEqual(locs.Kind.drop_ether, locs.kLocs[@backingInt(tabletLoc(3))].kind);
    try std.testing.expectEqual(locs.Kind.drop_bombos, locs.kLocs[@backingInt(tabletLoc(0x30))].kind);
    var block: [0x500]u8 = @splat(0);
    try std.testing.expect(!isSetIn(tabletFlag(3), &block));
    block[0x411] = 0x02;
    try std.testing.expect(isSetIn(tabletFlag(0x30), &block));
    try std.testing.expect(!isSetIn(tabletFlag(3), &block));
}

test "a seed places something at every one of these spots" {
    // The give functions read Link's inventory from the game's ram, which
    // these tests don't have, so this checks what they'd hand over from.
    try std.testing.expect(game.start(7, .{}));
    defer game.stop();
    for (kBossRooms) |b| try std.testing.expect(game.itemAt(b.loc) != null);
    for (kDashRooms) |d| try std.testing.expect(game.itemAt(d.loc) != null);
    try std.testing.expect(game.itemAt(tabletLoc(3)) != null);
    try std.testing.expect(game.itemAt(tabletLoc(0x30)) != null);
    try std.testing.expect(game.itemAt(.master_sword_pedestal) != null);
}
