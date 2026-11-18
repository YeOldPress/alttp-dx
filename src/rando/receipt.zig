//! What the game hands over for a randomizer item, and the little the item
//! receipt (misc.zig's AncillaAdd_ItemReceipt and the tables it reads) does
//! differently while a randomized file is being played.
//!
//! An item's receipt number is the index into the game's item receipt
//! tables: what it sets in Link's inventory, the graphic that rises out of
//! the chest, the text that follows. The game has 0x00 to 0x4b. The tables
//! carry on past them with z3randomizer's numbers (its tables.asm) for the
//! few the randomizer needs and the game never had: 0x4e half magic, 0x50
//! a master sword with no pedestal cutscene, and their neighbors (see
//! kReceiptCount).
//!
//! Progressive items are worked out from what Link has when the item's
//! handed over, as z3randomizer does (its ProgressiveSword and friends in
//! itemdowngrade.asm and newitems.asm):
//!
//!   progressive or uncle's sword: none (0 or 0xff) -> 0x49 Fighter's
//!       Sword, Fighter's -> 0x50 Master Sword, Master -> 0x02 Tempered,
//!       Tempered or Golden -> 0x03 Golden Sword.
//!   progressive shield: none -> 0x04 Fighter's Shield, Fighter's -> 0x05
//!       Fire Shield, Fire or Mirror -> 0x06 Mirror Shield.
//!   progressive armor: green -> 0x22 Blue Mail, blue or red -> 0x23 Red.
//!   progressive glove: none -> 0x1b Power Glove, either -> 0x1c Titan's
//!       Mitt.
//!   progressive bow: none -> 0x0b the Bow, any bow -> 0x3b the Bow with
//!       Silver Arrows. The game keeps both in link_item_bow: 1 a bow, 3
//!       a silver bow, each one higher once there are arrows to shoot (the
//!       HUD sees to that), so 0x0b sets 1 and 0x3b sets 3. Neither gives
//!       arrows, as neither does in VT; 0x3a, "bow and arrows", sets the
//!       same 1 as 0x0b, only with no text, so 0x0b it is.
//!
//! Past the top level each gives the top level again, as z3randomizer does
//! with no progressive limit set: the text and the jingle, and nothing
//! changes. VT's v1 pool never has more than the levels there are.
//!
//! The flute: VT's OcarinaInactive is the flute as the haunted grove's
//! digging spot gives it, the one that has to be played at Kakariko's
//! weathervane before the bird will come. The logic's canFly takes either
//! flute in Open mode, so it's handed over as 0x4a, the flute that's been
//! woken (link_item_flute 3): the bird comes the first time it's played,
//! from anywhere the game lets it. The weathervane just stays standing.
//!
//! While randomized, the receipt also: never lowers an inventory slot that
//! holds a level (keepsBetter), notes the items that share a slot in
//! z3randomizer's tracking bytes (track), chooses a first bottle for the
//! item menu (afterReceive), and fixes the few texts that would be wrong
//! (message). player.zig's Link_PerformOpenChest skips the game's chest
//! substitutions (a second lamp as rupees, a boomerang as arrows or
//! rupees), since a randomized chest gives what was placed in it.
//!
//! What the receipt can't do alone: the game keeps the boomerangs, the
//! mushroom and powder, and the shovel and flute each in one slot, so the
//! lesser of a pair found after the better one is noted but can't be used.
//! z3randomizer lets the item menu swap between them; until the menu does
//! that here, a shovel found after the flute can't dig (VT's Flute Spot),
//! and a mushroom found after the powder can't go to the Potion Shop.
const std = @import("std");
const items = @import("items.zig");

const Item = items.Item;

/// The game's ram, as variables.zig declares it. Only the functions that run
/// in the game reach it, so the randomizer's own tests build without it.
extern var g_ram: [131072]u8;

/// The save block (0x500 bytes, $7EF000 on), where Link's inventory lives.
fn sram() []u8 {
    return g_ram[0xf000..0xf500];
}

// Offsets into the save block.
pub const kBow = 0x340;
pub const kBoomerang = 0x341;
pub const kMushroom = 0x344;
pub const kFlute = 0x34c;
pub const kBottleIndex = 0x34f;
pub const kMirror = 0x353;
pub const kGloves = 0x354;
pub const kSword = 0x359;
pub const kShield = 0x35a;
pub const kArmor = 0x35b;
pub const kBottles = 0x35c;
/// z3randomizer's InventoryTracking (sram.asm), which the tracker reads:
/// which of the items that share an inventory slot have been found.
pub const kInventoryTracking = 0x38c;
/// z3randomizer's BowTracking: 0x80 the bow, 0x40 silver arrows.
pub const kBowTracking = 0x38e;

// The receipt numbers past the game's own, in z3randomizer's numbering.
pub const kBombCapacity50 = 0x4c;
pub const kArrowCapacity70 = 0x4d;
pub const kHalfMagic = 0x4e;
pub const kQuarterMagic = 0x4f;
pub const kMasterSword = 0x50;
/// How many receipt numbers the game's tables have: its own 0x4c and the
/// five above.
pub const kReceiptCount = 0x51;

/// What's given for an item the game has no receipt for (VT's capacity
/// upgrades, the lone silver arrows, the Triforce, "nothing"), none of which
/// v1's pool has: a green rupee, rather than an index past the tables.
pub const kFallback = 0x34;

/// The receipt number to hand over for `item` right now, from what Link has.
pub fn byteFor(item: Item) u8 {
    return byteIn(item, sram());
}

/// byteFor, with Link's inventory read from save block `block`.
pub fn byteIn(item: Item, block: []const u8) u8 {
    return switch (item) {
        .progressive_sword, .uncle_sword => switch (block[kSword]) {
            1 => kMasterSword,
            2 => 0x02,
            3, 4 => 0x03,
            else => 0x49,
        },
        .progressive_shield => switch (block[kShield]) {
            0 => 0x04,
            1 => 0x05,
            else => 0x06,
        },
        .progressive_armor => if (block[kArmor] == 0) 0x22 else 0x23,
        .progressive_glove => if (block[kGloves] == 0) 0x1b else 0x1c,
        .progressive_bow => if (block[kBow] == 0) 0x0b else 0x3b,
        .ocarina_inactive => 0x4a,
        else => {
            const b = items.byte(item);
            return if (b < kReceiptCount) b else kFallback;
        },
    };
}

/// The inventory slots that hold a level, where a higher value is a better
/// item: the bow, the boomerang, mushroom or powder, shovel or flute, the
/// mirror, gloves, sword, shield and mail.
fn holdsLevel(slot: u16) bool {
    return switch (slot) {
        kBow, kBoomerang, kMushroom, kFlute, kMirror, kGloves, kSword, kShield, kArmor => true,
        else => false,
    };
}

/// Whether the receipt should leave inventory byte `slot` (an offset into
/// the save block) as it is rather than set it to `value`: it holds a level
/// and Link already has a better one. In the game each slot's items come in
/// order (the mushroom's traded for the powder, the shovel's put down for
/// the flute); placed at random, a blue boomerang after the red one, or the
/// shovel after the flute, would take the better one away. A sword of 0xff
/// is no sword.
pub fn keepsBetter(slot: u16, value: u8, block: []const u8) bool {
    if (!holdsLevel(slot)) return false;
    const cur = block[slot];
    if (slot == kSword and cur == 0xff) return false;
    return value < cur;
}

/// Notes receipt `j` in z3randomizer's tracking bytes, so what's been found
/// of the items that share a slot is known even when the slot shows another
/// one: kInventoryTracking's 0x80 blue boomerang, 0x40 red, 0x20 mushroom,
/// 0x10 powder, 0x04 shovel, 0x02 the flute asleep, 0x01 awake; and
/// kBowTracking's 0x80 bow, 0x40 silver arrows.
pub fn track(j: u8, block: []u8) void {
    switch (j) {
        0x0c => block[kInventoryTracking] |= 0x80,
        0x2a => block[kInventoryTracking] |= 0x40,
        0x29 => block[kInventoryTracking] |= 0x20,
        0x0d => block[kInventoryTracking] |= 0x10,
        0x13 => block[kInventoryTracking] |= 0x04,
        0x14 => block[kInventoryTracking] |= 0x02,
        0x4a => block[kInventoryTracking] |= 0x01,
        0x0b, 0x3a => block[kBowTracking] |= 0x80,
        0x3b => block[kBowTracking] |= 0xc0,
        else => {},
    }
}

/// After a receipt: when Link has a bottle and none is chosen for the
/// item menu, choose the first, as the menu would once it's opened. A
/// bottle can be a randomized file's first item, and with nothing chosen
/// the menu thinks there's nothing to show.
pub fn afterReceive(block: []u8) void {
    if (block[kBottleIndex] != 0) return;
    for (0..4) |i| {
        if (block[kBottles + i] != 0) {
            block[kBottleIndex] = @intCast(i + 1);
            return;
        }
    }
}

/// The text to show for receipt `j`, given the game's own `msg` (-1 for
/// none). The game's text follows how it gives each item, and a few given
/// from a chest would say the wrong thing: the Golden Sword's says "You got
/// the Boomerang!" (the fairy gives it without), the Fire Shield's is the
/// Mirror Shield's, and the Fighter's Sword's is the smiths' "we can't make
/// it any stronger". The silver arrows and a boss's heart container have
/// none, since the fairy and the boss fight do the talking. Each gets the
/// nearest the game has (message numbers as the game counts them, one less
/// than dialogue.txt's): 119 "Your sword is stronger!", 144 "Your shield
/// is improved!", 145 "These are the Silver Arrows", 345 "You found a
/// Heart Container!", or none for the Fighter's Sword.
pub fn message(j: u8, msg: i16) i16 {
    return switch (j) {
        0x03 => 119,
        0x05 => 144,
        0x49 => -1,
        0x3b => 145,
        0x3e => 345,
        else => msg,
    };
}

const testing = std.testing;

fn blockWith(pokes: []const [2]u16) [0x500]u8 {
    var block: [0x500]u8 = @splat(0);
    for (pokes) |p| block[p[0]] = @intCast(p[1]);
    return block;
}

test "a progressive sword climbs a level from what Link holds, and stays golden" {
    const want = [_][2]u8{ .{ 0, 0x49 }, .{ 0xff, 0x49 }, .{ 1, 0x50 }, .{ 2, 0x02 }, .{ 3, 0x03 }, .{ 4, 0x03 } };
    for (want) |w| {
        const block = blockWith(&.{.{ kSword, w[0] }});
        try testing.expectEqual(w[1], byteIn(.progressive_sword, &block));
        try testing.expectEqual(w[1], byteIn(.uncle_sword, &block));
    }
}

test "shield, mail, gloves and bow climb the same way" {
    const Case = struct { item: Item, slot: u16, have: u8, want: u8 };
    const cases = [_]Case{
        .{ .item = .progressive_shield, .slot = kShield, .have = 0, .want = 0x04 },
        .{ .item = .progressive_shield, .slot = kShield, .have = 1, .want = 0x05 },
        .{ .item = .progressive_shield, .slot = kShield, .have = 2, .want = 0x06 },
        .{ .item = .progressive_shield, .slot = kShield, .have = 3, .want = 0x06 },
        .{ .item = .progressive_armor, .slot = kArmor, .have = 0, .want = 0x22 },
        .{ .item = .progressive_armor, .slot = kArmor, .have = 1, .want = 0x23 },
        .{ .item = .progressive_armor, .slot = kArmor, .have = 2, .want = 0x23 },
        .{ .item = .progressive_glove, .slot = kGloves, .have = 0, .want = 0x1b },
        .{ .item = .progressive_glove, .slot = kGloves, .have = 1, .want = 0x1c },
        .{ .item = .progressive_glove, .slot = kGloves, .have = 2, .want = 0x1c },
        .{ .item = .progressive_bow, .slot = kBow, .have = 0, .want = 0x0b },
        .{ .item = .progressive_bow, .slot = kBow, .have = 1, .want = 0x3b },
        .{ .item = .progressive_bow, .slot = kBow, .have = 2, .want = 0x3b },
        .{ .item = .progressive_bow, .slot = kBow, .have = 4, .want = 0x3b },
    };
    for (cases) |c| {
        const block = blockWith(&.{.{ c.slot, c.have }});
        try testing.expectEqual(c.want, byteIn(c.item, &block));
    }
}

test "every item in a seed's pool has a receipt the tables cover" {
    const fill = @import("fill.zig");
    const w = try fill.generate(11, .{});
    const block: [0x500]u8 = @splat(0);
    for (w.placed) |maybe| {
        const it = maybe orelse continue;
        if (items.kind(it) == .event) continue;
        const b = byteIn(it, &block);
        try testing.expect(b < kReceiptCount);
        try testing.expect(b != kFallback or it == .one_rupee);
    }
}

test "the flute comes awake, everything else as items.byte has it" {
    const block: [0x500]u8 = @splat(0);
    try testing.expectEqual(@as(u8, 0x4a), byteIn(.ocarina_inactive, &block));
    try testing.expectEqual(@as(u8, 0x4e), byteIn(.half_magic, &block));
    try testing.expectEqual(@as(u8, 0x46), byteIn(.three_hundred_rupees, &block));
    try testing.expectEqual(kFallback, byteIn(.bomb_upgrade5, &block));
    try testing.expectEqual(kFallback, byteIn(.triforce, &block));
}

test "a shared slot keeps the better item, and the tracking bytes say what was found" {
    var block = blockWith(&.{ .{ kBoomerang, 2 }, .{ kFlute, 3 }, .{ kSword, 0xff } });
    try testing.expect(keepsBetter(kBoomerang, 1, &block));
    try testing.expect(keepsBetter(kFlute, 1, &block));
    try testing.expect(!keepsBetter(kSword, 1, &block));
    try testing.expect(!keepsBetter(0x345, 0, &block)); // the fire rod's no level
    track(0x2a, &block);
    track(0x0c, &block);
    track(0x13, &block);
    track(0x3b, &block);
    try testing.expectEqual(@as(u8, 0xc4), block[kInventoryTracking]);
    try testing.expectEqual(@as(u8, 0xc0), block[kBowTracking]);
}

test "the first bottle found is chosen for the item menu" {
    var block = blockWith(&.{.{ kBottles + 2, 3 }});
    afterReceive(&block);
    try testing.expectEqual(@as(u8, 3), block[kBottleIndex]);
    block[kBottles] = 2;
    afterReceive(&block);
    try testing.expectEqual(@as(u8, 3), block[kBottleIndex]);
}
