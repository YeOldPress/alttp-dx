//! The people who hand Link something, and how a randomized file remembers
//! that each one has.
//!
//! In the game an NPC mostly decides whether it's already given its item by
//! looking at Link's inventory: King Zora leaves once Link has flippers, the
//! sick kid's done once there's a bug net, Sahasrahla once there are boots.
//! In a randomizer Link can own flippers before ever meeting King Zora, so
//! while a randomized file is played each of those asks a flag of its own
//! instead. The flags are z3randomizer's NpcFlags (its sram.asm, MIT), the two
//! bytes at $7EF410, which the game itself never touches (its save data ends
//! at 0x406), and which the item tracker (tracker_data.zig) already reads:
//!
//!   0x410: 0x01 Old Man, 0x02 King Zora, 0x04 Sick Kid, 0x08 Stumpy,
//!          0x10 Sahasrahla, 0x20 Catfish, 0x80 Library
//!   0x411: 0x01 Ether Tablet, 0x02 Bombos Tablet, 0x04 Blacksmith,
//!          0x10 Lost Woods mushroom, 0x20 Potion Shop (the powder),
//!          0x80 Magic Bat
//!
//! The rest already have a flag of the game's own that says nothing about
//! Link's inventory, which z3randomizer keeps too, and so does this:
//!
//!   Link's Uncle      0x3c6 0x01 (sram_progress_flags: the uncle's item
//!                     taken)
//!   Bottle Merchant   0x3c9 0x02 (sram_progress_indicator_3)
//!   Hobo              0x3c9 0x01
//!   Purple Chest      0x3c9 0x10 (the middle-aged man opened it)
//!   Hype Cave and Mini Moldorm Cave NPCs: their room's flag 0x4000
//!                     (dung_savegame_state_bits, saved with the room, 0x400
//!                     in its save word)
//!
//! Each NPC's code (sprite_main.zig, and misc.zig for the old man's start
//! location) asks given() where it used to look at the inventory, while
//! game.active(), and takes its item with take(), which gives the placed
//! item's receipt number and sets the flag in one go, or null when the file
//! isn't randomized, so the game carries on as it was.
const std = @import("std");
const game = @import("game.zig");

const Loc = game.Loc;

/// The NPC spots, by VT's location.
pub const Npc = enum {
    links_uncle,
    sahasrahla,
    king_zora,
    old_man,
    bottle_merchant,
    magic_bat,
    sick_kid,
    potion_shop,
    hobo,
    stumpy,
    purple_chest,
    blacksmith,
    hype_cave_npc,
    mini_moldorm_cave_npc,

    pub fn loc(n: Npc) Loc {
        return switch (n) {
            .links_uncle => .links_uncle,
            .sahasrahla => .sahasrahla,
            .king_zora => .king_zora,
            .old_man => .old_man,
            .bottle_merchant => .bottle_merchant,
            .magic_bat => .magic_bat,
            .sick_kid => .sick_kid,
            .potion_shop => .potion_shop,
            .hobo => .hobo,
            .stumpy => .stumpy,
            .purple_chest => .purple_chest,
            .blacksmith => .blacksmith,
            .hype_cave_npc => .hype_cave_npc,
            .mini_moldorm_cave_npc => .mini_moldorm_cave_npc,
        };
    }
};

/// Where an NPC's "already given" lives.
pub const Flag = union(enum) {
    /// A bit in the save block (offsets from $7EF000).
    save: struct { at: u16, bit: u8 },
    /// The room's own flag, kept by the room's save word: the game sets it
    /// as it hands the item over and saves it with the room.
    room: struct { room: u16, mask: u16 },
};

pub const kNpcFlags = 0x410;

pub fn flagOf(n: Npc) Flag {
    return switch (n) {
        .old_man => save(kNpcFlags, 0x01),
        .king_zora => save(kNpcFlags, 0x02),
        .sick_kid => save(kNpcFlags, 0x04),
        .stumpy => save(kNpcFlags, 0x08),
        .sahasrahla => save(kNpcFlags, 0x10),
        .blacksmith => save(kNpcFlags + 1, 0x04),
        .potion_shop => save(kNpcFlags + 1, 0x20),
        .magic_bat => save(kNpcFlags + 1, 0x80),
        .links_uncle => save(0x3c6, 0x01),
        .bottle_merchant => save(0x3c9, 0x02),
        .hobo => save(0x3c9, 0x01),
        .purple_chest => save(0x3c9, 0x10),
        .hype_cave_npc => .{ .room = .{ .room = 0x11e, .mask = 0x4000 } },
        .mini_moldorm_cave_npc => .{ .room = .{ .room = 0x123, .mask = 0x4000 } },
    };
}

fn save(at: u16, bit: u8) Flag {
    return .{ .save = .{ .at = at, .bit = bit } };
}

/// Whether save block `block` (0x500 bytes from $7EF000) says `n` has given
/// its item. A room flag is read from the room's save word, so a room
/// that's being played (whose flag is in dung_savegame_state_bits until it's
/// left) is the caller's to ask about.
pub fn givenIn(block: []const u8, n: Npc) bool {
    return switch (flagOf(n)) {
        .save => |f| block[f.at] & f.bit != 0,
        .room => |f| std.mem.readInt(u16, block[f.room * 2 ..][0..2], .little) & (f.mask >> 4) != 0,
    };
}

/// Notes in `block` that `n` has given its item. A room flag is left to the
/// game, which sets it in the room being played.
pub fn markIn(block: []u8, n: Npc) void {
    switch (flagOf(n)) {
        .save => |f| block[f.at] |= f.bit,
        .room => {},
    }
}

/// The game's ram, as variables.zig declares it. Only the functions that
/// run in the game reach it, so the randomizer's tests build without it.
extern var g_ram: [131072]u8;

fn sram() []u8 {
    return g_ram[0xf000..0xf500];
}

/// Whether `n` has given its item, by its flag. Only meaningful while a
/// randomized file is played (game.active()): otherwise the caller decides
/// as the game does.
pub fn given(n: Npc) bool {
    return givenIn(sram(), n);
}

/// Notes that `n` has given its item, for an NPC whose item is handed over
/// apart from take() (King Zora's, when it's picked up).
pub fn mark(n: Npc) void {
    markIn(sram(), n);
}

/// While randomized, the receipt number `n` hands over now (game.giveAt),
/// noting that it has. Null when the file isn't randomized: the caller hands
/// over the game's own item.
pub fn take(n: Npc) ?u8 {
    const r = game.giveAt(n.loc()) orelse return null;
    markIn(sram(), n);
    return r;
}

test "the flags are z3randomizer's, where the tracker reads them" {
    var block: [0x500]u8 = @splat(0);
    for (std.enums.values(Npc)) |n| try std.testing.expect(!givenIn(&block, n));
    markIn(&block, .old_man);
    markIn(&block, .king_zora);
    markIn(&block, .sahasrahla);
    markIn(&block, .magic_bat);
    markIn(&block, .blacksmith);
    try std.testing.expectEqual(@as(u8, 0x13), block[0x410]);
    try std.testing.expectEqual(@as(u8, 0x84), block[0x411]);
    try std.testing.expect(givenIn(&block, .king_zora));
    try std.testing.expect(!givenIn(&block, .sick_kid));
    markIn(&block, .bottle_merchant);
    try std.testing.expectEqual(@as(u8, 0x02), block[0x3c9]);
}

test "no two NPCs share a flag" {
    const all = std.enums.values(Npc);
    for (all, 0..) |a, i| for (all[i + 1 ..]) |b| {
        try std.testing.expect(!std.meta.eql(flagOf(a), flagOf(b)));
    };
}

test "the cave NPCs' room flags are the save word's 0x400" {
    var block: [0x500]u8 = @splat(0);
    block[0x11e * 2 + 1] = 0x04;
    try std.testing.expect(givenIn(&block, .hype_cave_npc));
    try std.testing.expect(!givenIn(&block, .mini_moldorm_cave_npc));
}

test "every NPC spot holds an item in a seed, and none unrandomized" {
    game.startForTest(7);
    for (std.enums.values(Npc)) |n| try std.testing.expect(game.itemAt(n.loc()) != null);
    game.stop();
    for (std.enums.values(Npc)) |n| try std.testing.expect(game.itemAt(n.loc()) == null);
}
