//! Everything an alttpr.com seed says about itself, read from the ROM.
//!
//! The randomizer writes its settings into a table near the end of the ROM,
//! and its starting save data just after; the addresses here are the ones
//! its generator writes to (sporchia/alttp_vt_randomizer, app/Rom.php and
//! the Region files), all file offsets into the ROM. The items at every
//! location are there too, which is what makes a spoiler; this only reads
//! the handful a player might want to peek at, and only when asked.
const std = @import("std");

pub const kHashIcons = [32][]const u8{
    "Bow",     "Boomerang", "Hookshot", "Bomb",   "Mushroom", "Powder", "Rod",     "Pendant",
    "Bombos",  "Ether",     "Quake",    "Lamp",   "Hammer",   "Shovel", "Flute",   "Bug Net",
    "Book",    "Bottle",    "Potion",   "Cane",   "Cape",     "Mirror", "Boots",   "Gloves",
    "Flippers", "Pearl",    "Shield",   "Tunic",  "Heart",    "Map",    "Compass", "Key",
};

pub const Medallion = enum { bombos, ether, quake, unknown };
pub const Prize = enum { unknown, green_pendant, blue_pendant, red_pendant, crystal1, crystal2, crystal3, crystal4, crystal5, crystal6, crystal7 };

pub const Info = struct {
    title: [21]u8 = @splat(' '),
    hash: [5]u8 = @splat(0),
    logic: []const u8 = "?",
    game_type: []const u8 = "?",
    mode: []const u8 = "?",
    goal: []const u8 = "?",
    goal_count: u16 = 0,
    tower_crystals: u8 = 0,
    ganon_crystals: u8 = 0,
    swordless: bool = false,
    shuffled_maps_compasses: bool = false,
    shuffled_keys: bool = false,
    shuffled_big_keys: bool = false,
    retro_keys: bool = false,
    quickswap: bool = false,
    pseudo_boots: bool = false,
    silvers: []const u8 = "?",
    menu_speed: []const u8 = "?",
    heart_beep: []const u8 = "?",
    heart_color: []const u8 = "?",
    timer: []const u8 = "?",
    total_items: u16 = 0,
    tournament: bool = false,
    limits: struct { sword: u8, shield: u8, armor: u8, bottles: u8, bow: u8 } = .{ .sword = 0, .shield = 0, .armor = 0, .bottles = 0, .bow = 0 },
    /// The items the file starts with, as $7EF340.. has them.
    start_items: [0x40]u8 = @splat(0),
    // Spoilers: only shown when asked for.
    misery_mire: Medallion = .unknown,
    turtle_rock: Medallion = .unknown,
    prizes: [10]Prize = @splat(.unknown),

    pub fn titleText(self: *const Info) []const u8 {
        return std.mem.trimEnd(u8, &self.title, " ");
    }
};

/// The ten dungeons with prizes, in the order Info.prizes has them, and
/// where each one's prize is written.
pub const kPrizeDungeons = [10]struct { name: []const u8, id_at: u32, kind_at: u32 }{
    .{ .name = "Eastern Palace", .id_at = 0x1209D, .kind_at = 0x180052 },
    .{ .name = "Desert Palace", .id_at = 0x1209E, .kind_at = 0x180053 },
    .{ .name = "Tower of Hera", .id_at = 0x120A5, .kind_at = 0x18005A },
    .{ .name = "Dark Palace", .id_at = 0x120A1, .kind_at = 0x180056 },
    .{ .name = "Swamp Palace", .id_at = 0x120A0, .kind_at = 0x180055 },
    .{ .name = "Skull Woods", .id_at = 0x120A3, .kind_at = 0x180058 },
    .{ .name = "Thieves' Town", .id_at = 0x120A6, .kind_at = 0x18005B },
    .{ .name = "Ice Palace", .id_at = 0x120A4, .kind_at = 0x180059 },
    .{ .name = "Misery Mire", .id_at = 0x120A2, .kind_at = 0x180057 },
    .{ .name = "Turtle Rock", .id_at = 0x120A7, .kind_at = 0x18005C },
};

pub fn prizeName(p: Prize) []const u8 {
    return switch (p) {
        .unknown => "?",
        .green_pendant => "Green Pendant",
        .blue_pendant => "Blue Pendant",
        .red_pendant => "Red Pendant",
        .crystal1 => "Crystal 1",
        .crystal2 => "Crystal 2",
        .crystal3 => "Crystal 3",
        .crystal4 => "Crystal 4",
        .crystal5 => "Crystal 5 (Red)",
        .crystal6 => "Crystal 6 (Red)",
        .crystal7 => "Crystal 7",
    };
}

pub fn medallionName(m: Medallion) []const u8 {
    return switch (m) {
        .bombos => "Bombos",
        .ether => "Ether",
        .quake => "Quake",
        .unknown => "?",
    };
}

fn word(rom: []const u8, at: usize) u16 {
    return @as(u16, rom[at]) | @as(u16, rom[at + 1]) << 8;
}

/// Reads a seed. A ROM too small to be one comes back mostly unknown.
pub fn read(rom_in: []const u8) Info {
    var info = Info{};
    // A copier header is 0x200 bytes on top of a power-of-two image.
    const rom = if (rom_in.len & 0xfffff == 0x200) rom_in[0x200..] else rom_in;
    if (rom.len < 0x190000) return info;
    @memcpy(&info.title, rom[0x7fc0..][0..21]);
    for (&info.hash, 0..) |*h, i| h.* = rom[0x180215 + i] & 0x1f;

    info.logic = switch (rom[0x180210]) {
        0x00 => "No Glitches",
        0x01 => "Major Glitches",
        0x02 => "Overworld Glitches",
        0xff => "No Logic",
        else => "?",
    };
    const gt = rom[0x180211];
    info.game_type = if (gt & 0b1000 != 0) "Room Randomizer" else if (gt & 0b0010 != 0) "Entrance Randomizer" else if (gt & 0b0001 != 0) "Enemizer" else "Item Randomizer";

    // Mode: inverted has its own flag; otherwise the starting save says
    // whether the game begins at the uncle (standard) or already open.
    const sram = 0x183000;
    const inverted = rom[0x18004A] == 1;
    info.mode = if (inverted) "Inverted" else if (rom[sram + 0x3C5] == 0) "Standard" else "Open";

    info.goal_count = word(rom, 0x180167);
    const pyramid_open = rom[sram + 0x280 + 0x5B] & 0x20 != 0;
    info.goal = switch (rom[0x1801A8]) {
        0x01 => if (info.goal_count != 0) "Triforce Hunt" else "Master Sword Pedestal",
        0x02 => "All Dungeons",
        0x04 => if (pyramid_open) "Fast Ganon" else "Defeat Ganon",
        0x05 => "Ganon Hunt (Triforce Pieces)",
        0x03, 0x07 => "Defeat Ganon (crystals and bosses)",
        0x08 => "Completionist",
        0x00 => "Defeat Ganon",
        else => "?",
    };
    info.tower_crystals = rom[0x18019A];
    info.ganon_crystals = rom[0x1801A6];
    info.swordless = rom[0x18003F] == 1;

    const menu_flags = rom[0x180045];
    info.shuffled_maps_compasses = menu_flags & 0x0C != 0;
    info.shuffled_keys = menu_flags & 0x01 != 0;
    info.shuffled_big_keys = menu_flags & 0x02 != 0;
    info.retro_keys = rom[0x180172] == 1;
    info.quickswap = rom[0x18004B] == 1;
    info.pseudo_boots = rom[0x18008E] == 1;
    info.silvers = switch (rom[0x180182]) {
        0 => "Manual",
        1 => "Auto on Pickup",
        2 => "Auto at Ganon",
        3 => "Auto Always",
        else => "?",
    };
    info.menu_speed = switch (rom[0x180048]) {
        0xE8 => "Instant",
        0x10 => "Fast",
        0x08 => "Normal",
        0x04 => "Slow",
        else => "?",
    };
    info.heart_beep = switch (rom[0x180033]) {
        0x00 => "Off",
        0x40 => "Half",
        0x80 => "Quarter",
        0x10 => "Double",
        0x20 => "Normal",
        else => "?",
    };
    info.heart_color = switch (rom[0x187020]) {
        0 => "Red",
        1 => "Blue",
        2 => "Green",
        3 => "Yellow",
        else => "?",
    };
    info.timer = switch (rom[0x180190]) {
        0 => "Off",
        1 => switch (rom[0x180191]) {
            0 => "Countdown (stop)",
            1 => "Countdown (continue)",
            2 => "Countdown (OHKO)",
            3 => "Countdown (end)",
            else => "Countdown",
        },
        2 => "Stopwatch",
        else => "?",
    };
    info.total_items = word(rom, 0x180196);
    info.tournament = rom[0x180213] == 1;
    info.limits = .{ .sword = rom[0x180090], .shield = rom[0x180092], .armor = rom[0x180094], .bottles = rom[0x180096], .bow = rom[0x180098] };
    @memcpy(&info.start_items, rom[sram + 0x340 ..][0..0x40]);

    info.misery_mire = medallion(rom[0x180022]);
    info.turtle_rock = medallion(rom[0x180023]);
    for (kPrizeDungeons, 0..) |d, i| info.prizes[i] = prize(rom[d.kind_at], rom[d.id_at]);
    return info;
}

fn medallion(b: u8) Medallion {
    return switch (b) {
        0 => .bombos,
        1 => .ether,
        2 => .quake,
        else => .unknown,
    };
}

/// A crystal writes $40 where a pendant writes $00, and each carries its own
/// bit in the other byte.
fn prize(kind: u8, id: u8) Prize {
    if (kind == 0x40) return switch (id) {
        0x02 => .crystal1,
        0x10 => .crystal2,
        0x40 => .crystal3,
        0x20 => .crystal4,
        0x04 => .crystal5,
        0x01 => .crystal6,
        0x08 => .crystal7,
        else => .unknown,
    };
    if (kind == 0x00) return switch (id) {
        0x04 => .green_pendant,
        0x01 => .red_pendant,
        0x02 => .blue_pendant,
        else => .unknown,
    };
    return .unknown;
}

/// The starting items worth listing, from the starting save.
pub fn startingItems(info: *const Info, out: [][]const u8) [][]const u8 {
    const s = &info.start_items;
    var n: usize = 0;
    const Named = struct { off: usize, name: []const u8 };
    const list = [_]Named{
        .{ .off = 0x00, .name = "Bow" },        .{ .off = 0x01, .name = "Boomerang" }, .{ .off = 0x02, .name = "Hookshot" },
        .{ .off = 0x04, .name = "Mushroom" },   .{ .off = 0x05, .name = "Fire Rod" },  .{ .off = 0x06, .name = "Ice Rod" },
        .{ .off = 0x07, .name = "Bombos" },     .{ .off = 0x08, .name = "Ether" },     .{ .off = 0x09, .name = "Quake" },
        .{ .off = 0x0A, .name = "Lamp" },       .{ .off = 0x0B, .name = "Hammer" },    .{ .off = 0x0C, .name = "Flute/Shovel" },
        .{ .off = 0x0D, .name = "Bug Net" },    .{ .off = 0x0E, .name = "Book" },      .{ .off = 0x10, .name = "Somaria" },
        .{ .off = 0x11, .name = "Byrna" },      .{ .off = 0x12, .name = "Cape" },      .{ .off = 0x13, .name = "Mirror" },
        .{ .off = 0x14, .name = "Gloves" },     .{ .off = 0x15, .name = "Boots" },     .{ .off = 0x16, .name = "Flippers" },
        .{ .off = 0x17, .name = "Moon Pearl" }, .{ .off = 0x19, .name = "Sword" },     .{ .off = 0x1A, .name = "Shield" },
    };
    for (list) |l| {
        if (s[l.off] != 0 and n < out.len) {
            out[n] = l.name;
            n += 1;
        }
    }
    return out[0..n];
}

test "prizes and medallions decode the way the randomizer writes them" {
    try std.testing.expectEqual(Prize.crystal4, prize(0x40, 0x20));
    try std.testing.expectEqual(Prize.green_pendant, prize(0x00, 0x04));
    try std.testing.expectEqual(Medallion.quake, medallion(2));
    // Too small to be a seed: nothing is guessed.
    const info = read(&@as([16]u8, @splat(0)));
    try std.testing.expectEqualStrings("?", info.goal);
}
