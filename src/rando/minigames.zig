//! The randomizer's digging spots and minigames, and the item menu's swap
//! between the items that share an inventory slot, as z3randomizer does them.
//!
//! The digging spots: VT's Flute Spot (the haunted grove, where the shovel
//! digs up the flute) and the Digging Game's prize (its heart piece). In a
//! randomized file each digs up its placed item once. player.zig's shovel
//! and digging game spawn it as the flute's dug-up ancilla (ancilla.zig's
//! Ancilla36_Flute), drawn as whatever the item is, and touching it hands the
//! item over and sets the screen's taken flag, the bit 0x40 of its overworld
//! event byte that the game sets for a screen's heart piece. z3randomizer
//! uses that same bit for both (its flute.asm and the heart piece sprite).
//! The haunted grove gives its item at the spot the flute is buried, as the
//! game does. The digging game gives it on the 15th dig of a round, as
//! z3randomizer's RigDigRNG does with VT's default DiggingGameRNG of 15, and
//! never a heart piece of its own.
//!
//! The Chest Game (the Village of Outcasts' treasure chest game, room 0x106)
//! gives its placed item where the game gives its heart piece: prize 7 of the
//! minigame's table, once, with the room's 0x4000 flag. z3randomizer's
//! RigChestRNG (rngfixes.asm) makes it the second chest of a game (VT's
//! default ChestGameRNG of 0, the chest that leaves no credit), and rolls
//! again when chance would give it, so it's never a chest's luck; dungeon.zig's
//! OpenMiniGameChest does the same.
//!
//! The swap: the game keeps the boomerangs, the mushroom and the Magic
//! Powder, and the shovel and the flute each in one slot, so in a randomized
//! file a pair can both be found. z3randomizer's ProcessMenuButtons
//! (inventory.asm) lets Y in the item menu switch the circled slot to the
//! other once both have been found, from the tracking bits the receipt sets
//! (receipt.zig's track). swapFor is that choice; hud.zig presses the button.
const std = @import("std");
const locs = @import("locations.zig");
const receipt = @import("receipt.zig");

pub const Loc = locs.Loc;

/// The bit of an overworld screen's event byte that says its item was taken.
pub const kTakenBit: u8 = 0x40;

pub const kHauntedGrove: u8 = 0x2a;
pub const kDiggingGameField: u8 = 0x68;

/// The location dug up on overworld screen `screen`, if it has one.
pub fn digLoc(screen: u16) ?Loc {
    return switch (screen) {
        kHauntedGrove => .flute_spot,
        kDiggingGameField => .digging_game,
        else => null,
    };
}

/// The dig of a digging game round that turns up the placed item.
pub const kDigsForPrize: u8 = 15;

/// Whether the digging game's dig number `digs` of a round turns up the
/// placed item: it hasn't been taken, and none's been dug up this round
/// (`prize_out`, the game's byte for that, still 0).
pub fn digPrizeDue(taken: bool, prize_out: u8, digs: u8) bool {
    return !taken and prize_out == 0 and digs >= kDigsForPrize;
}

/// The Chest Game's prize, its index in the minigame's prize table.
pub const kChestGamePrize: u8 = 7;

/// Whether the Chest Game's chest being opened gives the placed item: it
/// hasn't been taken, and it's the game's last chest (`credits_left`, the
/// chests left after this one, is 0).
pub fn chestGamePrizeDue(credits_left: u8, taken: bool) bool {
    return credits_left == 0 and !taken;
}

// The item menu's numbers for the shared slots (hud.zig's hud_cur_item).
pub const kHudBoomerang: u8 = 2;
pub const kHudMushroom: u8 = 5;
pub const kHudFlute: u8 = 13;

/// One switch of a shared slot: the save block byte, and its new value.
pub const Swap = struct { slot: u16, value: u8 };

/// What Y does to the item menu's slot `hud_item` in save block `block`:
/// the blue and red boomerangs trade places once both are found, as do the
/// mushroom and the powder; the flute's slot goes to the shovel and back to
/// the flute (awake if that one's been found) once the shovel and a flute
/// are. Null when the slot doesn't share or its pair isn't complete.
pub fn swapFor(hud_item: u8, block: []const u8) ?Swap {
    const inv = block[receipt.kInventoryTracking];
    switch (hud_item) {
        kHudBoomerang => {
            const cur = block[receipt.kBoomerang];
            if (inv & 0xc0 != 0xc0 or cur == 0) return null;
            return .{ .slot = receipt.kBoomerang, .value = cur ^ 3 };
        },
        kHudMushroom => {
            const cur = block[receipt.kMushroom];
            if (inv & 0x30 != 0x30 or cur == 0) return null;
            return .{ .slot = receipt.kMushroom, .value = cur ^ 3 };
        },
        kHudFlute => {
            if (inv & 0x04 == 0 or inv & 0x03 == 0) return null;
            const value: u8 = if (block[receipt.kFlute] != 1) 1 else if (inv & 0x01 != 0) 3 else 2;
            return .{ .slot = receipt.kFlute, .value = value };
        },
        else => return null,
    }
}

/// After the witch takes the mushroom: it's gone from the tracking bits, and
/// the slot holds the powder if that's been found (the game empties it),
/// as z3randomizer's RemoveMushroom does.
pub fn afterMushroomTraded(block: []u8) void {
    block[receipt.kInventoryTracking] &= ~@as(u8, 0x20);
    block[receipt.kMushroom] = if (block[receipt.kInventoryTracking] & 0x10 != 0) 2 else 0;
}

const testing = std.testing;

fn blockWith(pokes: []const [2]u16) [0x500]u8 {
    var block: [0x500]u8 = @splat(0);
    for (pokes) |p| block[p[0]] = @intCast(p[1]);
    return block;
}

test "the dug-up spots and their prizes" {
    try testing.expectEqual(Loc.flute_spot, digLoc(0x2a).?);
    try testing.expectEqual(Loc.digging_game, digLoc(0x68).?);
    try testing.expect(digLoc(0x6a) == null);
    try testing.expect(!digPrizeDue(false, 0, 14));
    try testing.expect(digPrizeDue(false, 0, 15));
    try testing.expect(digPrizeDue(false, 0, 40));
    try testing.expect(!digPrizeDue(true, 0, 15));
    try testing.expect(!digPrizeDue(false, 0xeb, 15));
    try testing.expect(!chestGamePrizeDue(1, false));
    try testing.expect(chestGamePrizeDue(0, false));
    try testing.expect(!chestGamePrizeDue(0, true));
}

test "a pair swaps once both are found, and not before" {
    const T = receipt.kInventoryTracking;
    // The red boomerang alone: nothing to swap to.
    var block = blockWith(&.{ .{ receipt.kBoomerang, 2 }, .{ T, 0x40 } });
    try testing.expect(swapFor(kHudBoomerang, &block) == null);
    block[T] = 0xc0;
    try testing.expectEqual(Swap{ .slot = receipt.kBoomerang, .value = 1 }, swapFor(kHudBoomerang, &block).?);
    block[receipt.kBoomerang] = 1;
    try testing.expectEqual(@as(u8, 2), swapFor(kHudBoomerang, &block).?.value);

    // Powder found first, then the mushroom.
    block = blockWith(&.{ .{ receipt.kMushroom, 2 }, .{ T, 0x10 } });
    try testing.expect(swapFor(kHudMushroom, &block) == null);
    block[T] |= 0x20;
    try testing.expectEqual(@as(u8, 1), swapFor(kHudMushroom, &block).?.value);

    // The awake flute, then the shovel: shovel, and back to the awake flute.
    block = blockWith(&.{ .{ receipt.kFlute, 3 }, .{ T, 0x01 } });
    try testing.expect(swapFor(kHudFlute, &block) == null);
    block[T] |= 0x04;
    try testing.expectEqual(@as(u8, 1), swapFor(kHudFlute, &block).?.value);
    block[receipt.kFlute] = 1;
    try testing.expectEqual(@as(u8, 3), swapFor(kHudFlute, &block).?.value);
    // The sleeping flute comes back asleep.
    block[T] = 0x06;
    try testing.expectEqual(@as(u8, 2), swapFor(kHudFlute, &block).?.value);

    try testing.expect(swapFor(1, &block) == null); // the bow's not one of them
}

test "the witch leaves the powder behind" {
    const T = receipt.kInventoryTracking;
    var block = blockWith(&.{ .{ receipt.kMushroom, 1 }, .{ T, 0x30 } });
    afterMushroomTraded(&block);
    try testing.expectEqual(@as(u8, 2), block[receipt.kMushroom]);
    try testing.expectEqual(@as(u8, 0x10), block[T]);
    try testing.expect(swapFor(kHudMushroom, &block) == null);
    block = blockWith(&.{ .{ receipt.kMushroom, 1 }, .{ T, 0x20 } });
    afterMushroomTraded(&block);
    try testing.expectEqual(@as(u8, 0), block[receipt.kMushroom]);
}
