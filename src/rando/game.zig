//! The randomizer in the running game: which seed this file is, the
//! placement it makes, and what each spot that gives an item gives instead.
//! The game's own code asks here wherever it hands something over (a chest,
//! a dungeon's prize, an NPC), and gets the randomizer's item while a
//! randomized file is being played, or carries on as the game would.
//!
//! The placement isn't kept anywhere: it's made again from the seed, which
//! the save file carries (rando/save.zig), whenever that file's loaded.
const std = @import("std");
const fill = @import("fill.zig");
const world_mod = @import("world.zig");
const items_mod = @import("items.zig");
const locs = @import("locations.zig");
const chests = @import("chests.zig");

pub const Item = items_mod.Item;
pub const Loc = locs.Loc;
pub const World = world_mod.World;
pub const Config = world_mod.Config;

/// The file being played, while it's a randomized one.
var g_world: World = .{};
var g_seed: u64 = 0;
var g_active = false;

/// Whether a randomized file is being played.
pub fn active() bool {
    return g_active;
}

pub fn seed() u64 {
    return g_seed;
}

/// Makes seed `s`'s placement the one being played. False when it won't
/// fill (which a seed that ever made a file never does: the fill is the
/// same every time).
pub fn start(s: u64, cfg: Config) bool {
    g_world = fill.generate(s, cfg) catch return false;
    g_seed = s;
    g_active = true;
    return true;
}

/// Back to the game as it comes: a file that isn't randomized.
pub fn stop() void {
    g_active = false;
}

/// What's placed at `loc`, while randomized.
pub fn itemAt(loc: Loc) ?Item {
    if (!g_active) return null;
    return g_world.placed[@backingInt(loc)];
}

/// The receipt number the game should hand over at `loc` right now, while
/// randomized: the placed item, progressive items worked out from what Link
/// has (receipt.zig). Null when the file isn't randomized, so the caller
/// carries on as the game would. Every spot that gives an item asks this.
pub fn giveAt(loc: Loc) ?u8 {
    const item = itemAt(loc) orelse return null;
    return @import("receipt.zig").byteFor(item);
}

/// The location of the `nth` chest (in the chest table's order) of dungeon
/// room `room`, if it's one of the randomizer's.
pub fn chestLoc(room: u16, nth: u8) ?Loc {
    for (chests.kSlots) |s| {
        if (s.room == room and s.nth == nth) return s.loc;
    }
    return null;
}

/// What the `nth` chest of room `room` holds, while randomized.
pub fn chestItem(room: u16, nth: u8) ?Item {
    const loc = chestLoc(room, nth) orelse return null;
    return itemAt(loc);
}

/// For tests: a placement made the same way without a file.
pub fn startForTest(s: u64) void {
    _ = start(s, .{});
}

test "every table chest is one of the randomizer's, and a seed fills them all" {
    try std.testing.expect(start(3, .{}));
    defer stop();
    for (chests.kSlots) |s| {
        try std.testing.expectEqual(s.loc, chestLoc(s.room, s.nth).?);
        try std.testing.expect(chestItem(s.room, s.nth) != null);
    }
}
