//! Where the randomizer keeps track of what the player has found, and where
//! each check sits on the map. Generated from the ALttPR community tracker
//! (github.com/kattothepast/alttptracker, js/autot.js, js/chests.js and
//! css/style.css), and checked against the randomizer's own RAM layout
//! (github.com/KatDevsGames/z3randomizer, sram.asm).
//!
//! Every offset is from $7EF000, the save data the game keeps in work ram.

pub const Check = struct { off: u16, mask: u8 };
pub const World = enum { light, dark };

/// A marker on the overworld map: one or more checks that open together.
pub const Location = struct { name: []const u8, checks: []const Check, world: World, x: f32, y: f32 };

pub const Dungeon = struct {
    name: []const u8,
    short: []const u8,
    /// Every item location inside, as room flags.
    checks: []const Check,
    map: Check,
    compass: Check,
    big_key: Check,
    /// Small keys found here so far, a counter.
    keys_found: u16,
    /// The boss room's defeated flag, where there is a boss.
    boss: ?Check,
    world: World,
    x: f32,
    y: f32,
};

pub const kDungeons = [_]Dungeon{
    .{ .name = "Eastern Palace", .short = "EP", .checks = &.{ .{ .off = 0x172, .mask = 0x10 }, .{ .off = 0x154, .mask = 0x10 }, .{ .off = 0x150, .mask = 0x10 }, .{ .off = 0x152, .mask = 0x10 }, .{ .off = 0x170, .mask = 0x10 }, .{ .off = 0x191, .mask = 0x08 } }, .map = .{ .off = 0x369, .mask = 0x20 }, .compass = .{ .off = 0x365, .mask = 0x20 }, .big_key = .{ .off = 0x367, .mask = 0x20 }, .keys_found = 0x4e2, .boss = .{ .off = 0x191, .mask = 0x08 }, .world = .light, .x = 93.6, .y = 38.8 },
    .{ .name = "Desert Palace", .short = "DP", .checks = &.{ .{ .off = 0x0e6, .mask = 0x10 }, .{ .off = 0x0e7, .mask = 0x04 }, .{ .off = 0x0e8, .mask = 0x10 }, .{ .off = 0x10a, .mask = 0x10 }, .{ .off = 0x0ea, .mask = 0x10 }, .{ .off = 0x067, .mask = 0x08 } }, .map = .{ .off = 0x369, .mask = 0x10 }, .compass = .{ .off = 0x365, .mask = 0x10 }, .big_key = .{ .off = 0x367, .mask = 0x10 }, .keys_found = 0x4e3, .boss = .{ .off = 0x067, .mask = 0x08 }, .world = .light, .x = 7.6, .y = 78.4 },
    .{ .name = "Tower of Hera", .short = "ToH", .checks = &.{ .{ .off = 0x10f, .mask = 0x04 }, .{ .off = 0x0ee, .mask = 0x10 }, .{ .off = 0x10e, .mask = 0x10 }, .{ .off = 0x04e, .mask = 0x10 }, .{ .off = 0x04e, .mask = 0x20 }, .{ .off = 0x00f, .mask = 0x08 } }, .map = .{ .off = 0x368, .mask = 0x20 }, .compass = .{ .off = 0x364, .mask = 0x20 }, .big_key = .{ .off = 0x366, .mask = 0x20 }, .keys_found = 0x4ea, .boss = .{ .off = 0x00f, .mask = 0x08 }, .world = .light, .x = 62.0, .y = 5.5 },
    .{ .name = "Palace of Darkness", .short = "PoD", .checks = &.{ .{ .off = 0x012, .mask = 0x10 }, .{ .off = 0x056, .mask = 0x10 }, .{ .off = 0x054, .mask = 0x10 }, .{ .off = 0x054, .mask = 0x20 }, .{ .off = 0x074, .mask = 0x10 }, .{ .off = 0x014, .mask = 0x10 }, .{ .off = 0x034, .mask = 0x10 }, .{ .off = 0x034, .mask = 0x20 }, .{ .off = 0x034, .mask = 0x40 }, .{ .off = 0x032, .mask = 0x10 }, .{ .off = 0x032, .mask = 0x20 }, .{ .off = 0x0d4, .mask = 0x10 }, .{ .off = 0x0d4, .mask = 0x20 }, .{ .off = 0x0b5, .mask = 0x08 } }, .map = .{ .off = 0x369, .mask = 0x02 }, .compass = .{ .off = 0x365, .mask = 0x02 }, .big_key = .{ .off = 0x367, .mask = 0x02 }, .keys_found = 0x4e6, .boss = .{ .off = 0x0b5, .mask = 0x08 }, .world = .dark, .x = 94.0, .y = 40.0 },
    .{ .name = "Swamp Palace", .short = "SP", .checks = &.{ .{ .off = 0x050, .mask = 0x10 }, .{ .off = 0x06e, .mask = 0x10 }, .{ .off = 0x06c, .mask = 0x10 }, .{ .off = 0x06a, .mask = 0x10 }, .{ .off = 0x068, .mask = 0x10 }, .{ .off = 0x08c, .mask = 0x10 }, .{ .off = 0x0ec, .mask = 0x10 }, .{ .off = 0x0ec, .mask = 0x20 }, .{ .off = 0x0cc, .mask = 0x10 }, .{ .off = 0x00d, .mask = 0x08 } }, .map = .{ .off = 0x369, .mask = 0x04 }, .compass = .{ .off = 0x365, .mask = 0x04 }, .big_key = .{ .off = 0x367, .mask = 0x04 }, .keys_found = 0x4e5, .boss = .{ .off = 0x00d, .mask = 0x08 }, .world = .dark, .x = 47.0, .y = 91.0 },
    .{ .name = "Skull Woods", .short = "SW", .checks = &.{ .{ .off = 0x0ce, .mask = 0x10 }, .{ .off = 0x0d0, .mask = 0x10 }, .{ .off = 0x0ae, .mask = 0x10 }, .{ .off = 0x0ae, .mask = 0x20 }, .{ .off = 0x0b0, .mask = 0x10 }, .{ .off = 0x0b0, .mask = 0x20 }, .{ .off = 0x0b2, .mask = 0x10 }, .{ .off = 0x053, .mask = 0x08 } }, .map = .{ .off = 0x368, .mask = 0x80 }, .compass = .{ .off = 0x364, .mask = 0x80 }, .big_key = .{ .off = 0x366, .mask = 0x80 }, .keys_found = 0x4e8, .boss = .{ .off = 0x053, .mask = 0x08 }, .world = .dark, .x = 6.6, .y = 5.4 },
    .{ .name = "Thieves' Town", .short = "TT", .checks = &.{ .{ .off = 0x1b6, .mask = 0x10 }, .{ .off = 0x1b6, .mask = 0x20 }, .{ .off = 0x196, .mask = 0x10 }, .{ .off = 0x1b8, .mask = 0x10 }, .{ .off = 0x0ca, .mask = 0x10 }, .{ .off = 0x08a, .mask = 0x10 }, .{ .off = 0x088, .mask = 0x10 }, .{ .off = 0x159, .mask = 0x08 } }, .map = .{ .off = 0x368, .mask = 0x10 }, .compass = .{ .off = 0x364, .mask = 0x10 }, .big_key = .{ .off = 0x366, .mask = 0x10 }, .keys_found = 0x4eb, .boss = .{ .off = 0x159, .mask = 0x08 }, .world = .dark, .x = 12.8, .y = 47.9 },
    .{ .name = "Ice Palace", .short = "IP", .checks = &.{ .{ .off = 0x05c, .mask = 0x10 }, .{ .off = 0x07e, .mask = 0x10 }, .{ .off = 0x03e, .mask = 0x10 }, .{ .off = 0x0be, .mask = 0x10 }, .{ .off = 0x0fc, .mask = 0x10 }, .{ .off = 0x15c, .mask = 0x10 }, .{ .off = 0x13c, .mask = 0x10 }, .{ .off = 0x1bd, .mask = 0x08 } }, .map = .{ .off = 0x368, .mask = 0x40 }, .compass = .{ .off = 0x364, .mask = 0x40 }, .big_key = .{ .off = 0x366, .mask = 0x40 }, .keys_found = 0x4e9, .boss = .{ .off = 0x1bd, .mask = 0x08 }, .world = .dark, .x = 79.6, .y = 85.8 },
    .{ .name = "Misery Mire", .short = "MM", .checks = &.{ .{ .off = 0x144, .mask = 0x10 }, .{ .off = 0x166, .mask = 0x10 }, .{ .off = 0x184, .mask = 0x10 }, .{ .off = 0x182, .mask = 0x10 }, .{ .off = 0x1a2, .mask = 0x10 }, .{ .off = 0x186, .mask = 0x10 }, .{ .off = 0x186, .mask = 0x20 }, .{ .off = 0x121, .mask = 0x08 } }, .map = .{ .off = 0x369, .mask = 0x01 }, .compass = .{ .off = 0x365, .mask = 0x01 }, .big_key = .{ .off = 0x367, .mask = 0x01 }, .keys_found = 0x4e7, .boss = .{ .off = 0x121, .mask = 0x08 }, .world = .dark, .x = 11.6, .y = 82.9 },
    .{ .name = "Turtle Rock", .short = "TR", .checks = &.{ .{ .off = 0x1ac, .mask = 0x10 }, .{ .off = 0x16e, .mask = 0x10 }, .{ .off = 0x16e, .mask = 0x20 }, .{ .off = 0x16c, .mask = 0x10 }, .{ .off = 0x028, .mask = 0x10 }, .{ .off = 0x048, .mask = 0x10 }, .{ .off = 0x008, .mask = 0x10 }, .{ .off = 0x1aa, .mask = 0x10 }, .{ .off = 0x1aa, .mask = 0x20 }, .{ .off = 0x1aa, .mask = 0x40 }, .{ .off = 0x1aa, .mask = 0x80 }, .{ .off = 0x149, .mask = 0x08 } }, .map = .{ .off = 0x368, .mask = 0x08 }, .compass = .{ .off = 0x364, .mask = 0x08 }, .big_key = .{ .off = 0x366, .mask = 0x08 }, .keys_found = 0x4ec, .boss = .{ .off = 0x149, .mask = 0x08 }, .world = .dark, .x = 93.8, .y = 7.0 },
    .{ .name = "Ganon's Tower", .short = "GT", .checks = &.{ .{ .off = 0x119, .mask = 0x04 }, .{ .off = 0x0f6, .mask = 0x10 }, .{ .off = 0x0f6, .mask = 0x20 }, .{ .off = 0x0f6, .mask = 0x40 }, .{ .off = 0x0f6, .mask = 0x80 }, .{ .off = 0x116, .mask = 0x10 }, .{ .off = 0x0fa, .mask = 0x10 }, .{ .off = 0x0f8, .mask = 0x10 }, .{ .off = 0x0f8, .mask = 0x20 }, .{ .off = 0x0f8, .mask = 0x40 }, .{ .off = 0x0f8, .mask = 0x80 }, .{ .off = 0x118, .mask = 0x10 }, .{ .off = 0x118, .mask = 0x20 }, .{ .off = 0x118, .mask = 0x40 }, .{ .off = 0x118, .mask = 0x80 }, .{ .off = 0x038, .mask = 0x10 }, .{ .off = 0x038, .mask = 0x20 }, .{ .off = 0x038, .mask = 0x40 }, .{ .off = 0x11a, .mask = 0x10 }, .{ .off = 0x13a, .mask = 0x10 }, .{ .off = 0x13a, .mask = 0x20 }, .{ .off = 0x13a, .mask = 0x40 }, .{ .off = 0x13a, .mask = 0x80 }, .{ .off = 0x07a, .mask = 0x10 }, .{ .off = 0x07a, .mask = 0x20 }, .{ .off = 0x07a, .mask = 0x40 }, .{ .off = 0x09a, .mask = 0x10 } }, .map = .{ .off = 0x368, .mask = 0x04 }, .compass = .{ .off = 0x364, .mask = 0x04 }, .big_key = .{ .off = 0x366, .mask = 0x04 }, .keys_found = 0x4ed, .boss = null, .world = .dark, .x = 58.0, .y = 5.5 },
    .{ .name = "Hyrule Castle", .short = "HC", .checks = &.{ .{ .off = 0x0e4, .mask = 0x10 }, .{ .off = 0x0e2, .mask = 0x10 }, .{ .off = 0x100, .mask = 0x10 }, .{ .off = 0x064, .mask = 0x10 }, .{ .off = 0x022, .mask = 0x10 }, .{ .off = 0x022, .mask = 0x20 }, .{ .off = 0x022, .mask = 0x40 }, .{ .off = 0x024, .mask = 0x10 } }, .map = .{ .off = 0x369, .mask = 0x40 }, .compass = .{ .off = 0x365, .mask = 0x40 }, .big_key = .{ .off = 0x367, .mask = 0x40 }, .keys_found = 0x4e0, .boss = null, .world = .light, .x = 50.0, .y = 37.5 },
    .{ .name = "Castle Tower", .short = "CT", .checks = &.{ .{ .off = 0x1c0, .mask = 0x10 }, .{ .off = 0x1a0, .mask = 0x10 } }, .map = .{ .off = 0x369, .mask = 0x08 }, .compass = .{ .off = 0x365, .mask = 0x08 }, .big_key = .{ .off = 0x367, .mask = 0x08 }, .keys_found = 0x4e4, .boss = null, .world = .light, .x = 50.0, .y = 52.6 },
};

pub const kLocations = [_]Location{
    .{ .name = "King's Tomb", .checks = &.{.{ .off = 0x226, .mask = 0x10 }}, .world = .light, .x = 61.6, .y = 29.6 },
    .{ .name = "Sunken Treasure", .checks = &.{ .{ .off = 0x2bb, .mask = 0x40 }, .{ .off = 0x216, .mask = 0x10 } }, .world = .light, .x = 46.8, .y = 93.4 },
    .{ .name = "Link's House", .checks = &.{.{ .off = 0x208, .mask = 0x10 }}, .world = .light, .x = 54.8, .y = 67.9 },
    .{ .name = "Spiral Cave", .checks = &.{.{ .off = 0x1fc, .mask = 0x10 }}, .world = .light, .x = 79.8, .y = 9.3 },
    .{ .name = "Mimic Cave", .checks = &.{.{ .off = 0x218, .mask = 0x10 }}, .world = .light, .x = 85.2, .y = 9.3 },
    .{ .name = "Tavern", .checks = &.{.{ .off = 0x206, .mask = 0x10 }}, .world = .light, .x = 16.2, .y = 57.8 },
    .{ .name = "Chicken House", .checks = &.{.{ .off = 0x210, .mask = 0x10 }}, .world = .light, .x = 8.8, .y = 54.2 },
    .{ .name = "Brewery", .checks = &.{.{ .off = 0x20c, .mask = 0x10 }}, .world = .dark, .x = 10.8, .y = 57.8 },
    .{ .name = "C-Shaped House", .checks = &.{.{ .off = 0x238, .mask = 0x10 }}, .world = .dark, .x = 21.6, .y = 47.9 },
    .{ .name = "Aginah's Cave", .checks = &.{.{ .off = 0x214, .mask = 0x10 }}, .world = .light, .x = 20.0, .y = 82.6 },
    .{ .name = "Mire Shed", .checks = &.{ .{ .off = 0x21a, .mask = 0x10 }, .{ .off = 0x21a, .mask = 0x20 } }, .world = .dark, .x = 3.4, .y = 79.5 },
    .{ .name = "Superbunny Cave", .checks = &.{ .{ .off = 0x1f0, .mask = 0x10 }, .{ .off = 0x1f0, .mask = 0x20 } }, .world = .dark, .x = 85.6, .y = 14.7 },
    .{ .name = "Sahasrahla's Hut", .checks = &.{ .{ .off = 0x20a, .mask = 0x10 }, .{ .off = 0x20a, .mask = 0x20 }, .{ .off = 0x20a, .mask = 0x40 } }, .world = .light, .x = 81.4, .y = 41.4 },
    .{ .name = "Spike Cave", .checks = &.{.{ .off = 0x22e, .mask = 0x10 }}, .world = .dark, .x = 57.2, .y = 14.9 },
    .{ .name = "Kakariko Well", .checks = &.{ .{ .off = 0x05e, .mask = 0x10 }, .{ .off = 0x05e, .mask = 0x20 }, .{ .off = 0x05e, .mask = 0x40 }, .{ .off = 0x05e, .mask = 0x80 }, .{ .off = 0x05f, .mask = 0x01 } }, .world = .light, .x = 3.4, .y = 41.0 },
    .{ .name = "Blind's Hut", .checks = &.{ .{ .off = 0x23a, .mask = 0x10 }, .{ .off = 0x23a, .mask = 0x20 }, .{ .off = 0x23a, .mask = 0x40 }, .{ .off = 0x23a, .mask = 0x80 }, .{ .off = 0x23b, .mask = 0x01 } }, .world = .light, .x = 12.8, .y = 41.0 },
    .{ .name = "Hype Cave", .checks = &.{ .{ .off = 0x23c, .mask = 0x10 }, .{ .off = 0x23c, .mask = 0x20 }, .{ .off = 0x23c, .mask = 0x40 }, .{ .off = 0x23c, .mask = 0x80 }, .{ .off = 0x23d, .mask = 0x04 } }, .world = .dark, .x = 60.0, .y = 77.1 },
    .{ .name = "Paradox Cave", .checks = &.{ .{ .off = 0x1de, .mask = 0x10 }, .{ .off = 0x1de, .mask = 0x20 }, .{ .off = 0x1de, .mask = 0x40 }, .{ .off = 0x1de, .mask = 0x80 }, .{ .off = 0x1df, .mask = 0x01 }, .{ .off = 0x1fe, .mask = 0x10 }, .{ .off = 0x1fe, .mask = 0x20 } }, .world = .light, .x = 82.8, .y = 17.1 },
    .{ .name = "Bonk Rock", .checks = &.{.{ .off = 0x248, .mask = 0x10 }}, .world = .light, .x = 39.0, .y = 29.3 },
    .{ .name = "Mini Moldorm Cave", .checks = &.{ .{ .off = 0x246, .mask = 0x10 }, .{ .off = 0x246, .mask = 0x20 }, .{ .off = 0x246, .mask = 0x40 }, .{ .off = 0x246, .mask = 0x80 }, .{ .off = 0x247, .mask = 0x04 } }, .world = .light, .x = 65.2, .y = 93.4 },
    .{ .name = "Ice Rod Cave", .checks = &.{.{ .off = 0x240, .mask = 0x10 }}, .world = .light, .x = 89.4, .y = 76.9 },
    .{ .name = "Hookshot Cave (Bottom)", .checks = &.{.{ .off = 0x078, .mask = 0x80 }}, .world = .dark, .x = 83.2, .y = 8.6 },
    .{ .name = "Hookshot Cave", .checks = &.{ .{ .off = 0x078, .mask = 0x10 }, .{ .off = 0x078, .mask = 0x20 }, .{ .off = 0x078, .mask = 0x40 } }, .world = .dark, .x = 83.2, .y = 3.4 },
    .{ .name = "Chest Game", .checks = &.{.{ .off = 0x20d, .mask = 0x04 }}, .world = .dark, .x = 4.2, .y = 46.4 },
    .{ .name = "Bottle Merchant", .checks = &.{.{ .off = 0x3c9, .mask = 0x02 }}, .world = .light, .x = 9.0, .y = 46.8 },
    .{ .name = "Sahasrahla", .checks = &.{.{ .off = 0x410, .mask = 0x10 }}, .world = .light, .x = 81.4, .y = 46.7 },
    .{ .name = "Stumpy", .checks = &.{.{ .off = 0x410, .mask = 0x08 }}, .world = .dark, .x = 31.0, .y = 68.6 },
    .{ .name = "Sick Kid", .checks = &.{.{ .off = 0x410, .mask = 0x04 }}, .world = .light, .x = 15.6, .y = 52.1 },
    .{ .name = "Purple Chest", .checks = &.{.{ .off = 0x3c9, .mask = 0x10 }}, .world = .dark, .x = 30.4, .y = 52.2 },
    .{ .name = "Hobo", .checks = &.{.{ .off = 0x3c9, .mask = 0x01 }}, .world = .light, .x = 70.8, .y = 69.7 },
    .{ .name = "Ether Tablet", .checks = &.{.{ .off = 0x411, .mask = 0x01 }}, .world = .light, .x = 42.0, .y = 3.0 },
    .{ .name = "Bombos Tablet", .checks = &.{.{ .off = 0x411, .mask = 0x02 }}, .world = .light, .x = 22.0, .y = 92.2 },
    .{ .name = "Catfish", .checks = &.{.{ .off = 0x410, .mask = 0x20 }}, .world = .dark, .x = 92.0, .y = 17.2 },
    .{ .name = "King Zora", .checks = &.{.{ .off = 0x410, .mask = 0x02 }}, .world = .light, .x = 96.0, .y = 12.1 },
    .{ .name = "Lost Old Man", .checks = &.{.{ .off = 0x410, .mask = 0x01 }}, .world = .light, .x = 41.6, .y = 20.4 },
    .{ .name = "Potion Shop", .checks = &.{.{ .off = 0x411, .mask = 0x20 }}, .world = .light, .x = 81.6, .y = 32.5 },
    .{ .name = "Lost Woods Hideout", .checks = &.{.{ .off = 0x1c3, .mask = 0x02 }}, .world = .light, .x = 18.8, .y = 13.0 },
    .{ .name = "Lumberjack Tree", .checks = &.{.{ .off = 0x1c5, .mask = 0x02 }}, .world = .light, .x = 30.2, .y = 7.6 },
    .{ .name = "Spectacle Rock Cave", .checks = &.{.{ .off = 0x1d5, .mask = 0x04 }}, .world = .light, .x = 48.6, .y = 14.8 },
    .{ .name = "Cave 45", .checks = &.{.{ .off = 0x237, .mask = 0x04 }}, .world = .light, .x = 28.2, .y = 84.1 },
    .{ .name = "Graveyard Ledge", .checks = &.{.{ .off = 0x237, .mask = 0x02 }}, .world = .light, .x = 56.2, .y = 27.0 },
    .{ .name = "Checkerboard Cave", .checks = &.{.{ .off = 0x24d, .mask = 0x02 }}, .world = .light, .x = 17.6, .y = 77.3 },
    .{ .name = "Hammer Pegs", .checks = &.{.{ .off = 0x24f, .mask = 0x04 }}, .world = .dark, .x = 31.6, .y = 60.1 },
    .{ .name = "Library", .checks = &.{.{ .off = 0x410, .mask = 0x80 }}, .world = .light, .x = 15.4, .y = 65.9 },
    .{ .name = "Mushroom", .checks = &.{.{ .off = 0x411, .mask = 0x10 }}, .world = .light, .x = 12.4, .y = 8.6 },
    .{ .name = "Spectacle Rock", .checks = &.{.{ .off = 0x283, .mask = 0x40 }}, .world = .light, .x = 50.8, .y = 8.5 },
    .{ .name = "Floating Island", .checks = &.{.{ .off = 0x285, .mask = 0x40 }}, .world = .light, .x = 80.4, .y = 3.0 },
    .{ .name = "Race Game", .checks = &.{.{ .off = 0x2a8, .mask = 0x40 }}, .world = .light, .x = 3.6, .y = 69.8 },
    .{ .name = "Desert Ledge", .checks = &.{.{ .off = 0x2b0, .mask = 0x40 }}, .world = .light, .x = 3.0, .y = 91.0 },
    .{ .name = "Lake Hylia Island", .checks = &.{.{ .off = 0x2b5, .mask = 0x40 }}, .world = .light, .x = 72.2, .y = 82.9 },
    .{ .name = "Bumper Cave Ledge", .checks = &.{.{ .off = 0x2ca, .mask = 0x40 }}, .world = .dark, .x = 34.2, .y = 15.2 },
    .{ .name = "Pyramid", .checks = &.{.{ .off = 0x2db, .mask = 0x40 }}, .world = .dark, .x = 58.0, .y = 43.5 },
    .{ .name = "Digging Game", .checks = &.{.{ .off = 0x2e8, .mask = 0x40 }}, .world = .dark, .x = 5.8, .y = 69.2 },
    .{ .name = "Zora's Ledge", .checks = &.{.{ .off = 0x301, .mask = 0x40 }}, .world = .light, .x = 95.4, .y = 17.3 },
    .{ .name = "Flute Spot", .checks = &.{.{ .off = 0x2aa, .mask = 0x40 }}, .world = .light, .x = 28.8, .y = 66.2 },
    .{ .name = "Link's Uncle", .checks = &.{ .{ .off = 0x3c6, .mask = 0x01 }, .{ .off = 0x0aa, .mask = 0x10 } }, .world = .light, .x = 59.6, .y = 41.8 },
    .{ .name = "Magic Bat", .checks = &.{.{ .off = 0x411, .mask = 0x80 }}, .world = .light, .x = 32.0, .y = 58.0 },
    .{ .name = "Blacksmith", .checks = &.{.{ .off = 0x411, .mask = 0x04 }}, .world = .light, .x = 30.4, .y = 51.8 },
    .{ .name = "Pyramid Fairy", .checks = &.{ .{ .off = 0x22c, .mask = 0x10 }, .{ .off = 0x22c, .mask = 0x20 } }, .world = .dark, .x = 47.0, .y = 48.5 },
    .{ .name = "Master Sword Pedestal", .checks = &.{.{ .off = 0x300, .mask = 0x40 }}, .world = .light, .x = 5.0, .y = 3.2 },
    .{ .name = "Waterfall Fairy", .checks = &.{ .{ .off = 0x228, .mask = 0x10 }, .{ .off = 0x228, .mask = 0x20 } }, .world = .light, .x = 89.8, .y = 14.7 },
};
