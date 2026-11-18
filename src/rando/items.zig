//! The randomizer's items, as the VT randomizer (github.com/sporchia/
//! alttp_vt_randomizer, MIT) names and counts them, and what the logic asks
//! of a set of them: VT's app/Item.php and app/Support/ItemCollection.php.
//!
//! An item's `byte` is the game's own item receipt number, where it has
//! one: what a chest or an NPC hands over. VT's dungeon items (KeyD1 and so
//! on) say which dungeon they belong to; since v1 keeps them in their own
//! dungeons, the game gives each its plain key, map, compass or big key.
const std = @import("std");

pub const Item = enum(u8) {
    nothing,
    // Swords. The uncle's is a progressive sword the logic counts apart.
    l1_sword,
    l1_sword_and_shield,
    l2_sword,
    master_sword,
    l3_sword,
    l4_sword,
    progressive_sword,
    uncle_sword,
    // Shields and mail.
    blue_shield,
    red_shield,
    mirror_shield,
    progressive_shield,
    blue_mail,
    red_mail,
    progressive_armor,
    // Equipment.
    fire_rod,
    ice_rod,
    hammer,
    hookshot,
    bow,
    bow_and_arrows,
    bow_and_silver_arrows,
    progressive_bow,
    silver_arrow_upgrade,
    boomerang,
    red_boomerang,
    powder,
    mushroom,
    bombos,
    ether,
    quake,
    lamp,
    shovel,
    ocarina_inactive,
    ocarina_active,
    cane_of_somaria,
    cane_of_byrna,
    cape,
    magic_mirror,
    power_glove,
    titans_mitt,
    progressive_glove,
    book_of_mudora,
    flippers,
    moon_pearl,
    bug_catching_net,
    pegasus_boots,
    half_magic,
    quarter_magic,
    // Bottles.
    bottle,
    bottle_with_red_potion,
    bottle_with_green_potion,
    bottle_with_blue_potion,
    bottle_with_bee,
    bottle_with_gold_bee,
    bottle_with_fairy,
    // Health.
    piece_of_heart,
    boss_heart_container,
    heart_container,
    // Junk.
    bomb,
    three_bombs,
    ten_bombs,
    arrow,
    ten_arrows,
    one_rupee,
    five_rupees,
    twenty_rupees,
    twenty_rupees2,
    fifty_rupees,
    one_hundred_rupees,
    three_hundred_rupees,
    heart,
    small_magic,
    bomb_upgrade5,
    bomb_upgrade10,
    arrow_upgrade5,
    arrow_upgrade10,
    // Prizes.
    pendant_of_courage,
    pendant_of_power,
    pendant_of_wisdom,
    crystal1,
    crystal2,
    crystal3,
    crystal4,
    crystal5,
    crystal6,
    crystal7,
    triforce,
    // Dungeon items. H2 is Hyrule Castle and the escape, A1 Agahnim's
    // tower, P1 to P3 the pendant dungeons, D1 to D7 the crystal ones in
    // VT's numbering, A2 Ganon's Tower.
    key_h2,
    key_p2,
    key_p3,
    key_a1,
    key_d1,
    key_d2,
    key_d3,
    key_d4,
    key_d5,
    key_d6,
    key_d7,
    key_a2,
    big_key_p1,
    big_key_p2,
    big_key_p3,
    big_key_d1,
    big_key_d2,
    big_key_d3,
    big_key_d4,
    big_key_d5,
    big_key_d6,
    big_key_d7,
    big_key_a2,
    map_h2,
    map_p1,
    map_p2,
    map_p3,
    map_d1,
    map_d2,
    map_d3,
    map_d4,
    map_d5,
    map_d6,
    map_d7,
    map_a2,
    compass_p1,
    compass_p2,
    compass_p3,
    compass_d1,
    compass_d2,
    compass_d3,
    compass_d4,
    compass_d5,
    compass_d6,
    compass_d7,
    compass_a2,
    // Events: things done, which the logic counts as items.
    rescue_zelda,
    defeat_agahnim,
    defeat_agahnim2,
    defeat_ganon,
    big_red_bomb,
};

pub const kCount = std.enums.values(Item).len;

pub const Kind = enum { other, sword, shield, armor, bow, bottle, health, key, big_key, map, compass, pendant, crystal, event, medallion };

pub fn kind(it: Item) Kind {
    return switch (it) {
        .l1_sword, .l1_sword_and_shield, .l2_sword, .master_sword, .l3_sword, .l4_sword, .progressive_sword, .uncle_sword => .sword,
        .blue_shield, .red_shield, .mirror_shield, .progressive_shield => .shield,
        .blue_mail, .red_mail, .progressive_armor => .armor,
        .bow, .bow_and_arrows, .bow_and_silver_arrows, .progressive_bow => .bow,
        .bottle, .bottle_with_red_potion, .bottle_with_green_potion, .bottle_with_blue_potion, .bottle_with_bee, .bottle_with_gold_bee, .bottle_with_fairy => .bottle,
        .piece_of_heart, .boss_heart_container, .heart_container => .health,
        .key_h2, .key_p2, .key_p3, .key_a1, .key_d1, .key_d2, .key_d3, .key_d4, .key_d5, .key_d6, .key_d7, .key_a2 => .key,
        .big_key_p1, .big_key_p2, .big_key_p3, .big_key_d1, .big_key_d2, .big_key_d3, .big_key_d4, .big_key_d5, .big_key_d6, .big_key_d7, .big_key_a2 => .big_key,
        .map_h2, .map_p1, .map_p2, .map_p3, .map_d1, .map_d2, .map_d3, .map_d4, .map_d5, .map_d6, .map_d7, .map_a2 => .map,
        .compass_p1, .compass_p2, .compass_p3, .compass_d1, .compass_d2, .compass_d3, .compass_d4, .compass_d5, .compass_d6, .compass_d7, .compass_a2 => .compass,
        .pendant_of_courage, .pendant_of_power, .pendant_of_wisdom => .pendant,
        .crystal1, .crystal2, .crystal3, .crystal4, .crystal5, .crystal6, .crystal7 => .crystal,
        .rescue_zelda, .defeat_agahnim, .defeat_agahnim2, .defeat_ganon, .big_red_bomb, .triforce => .event,
        .bombos, .ether, .quake => .medallion,
        else => .other,
    };
}

/// Whether it's a dungeon's own key, big key, map or compass.
pub fn isDungeonItem(it: Item) bool {
    return switch (kind(it)) {
        .key, .big_key, .map, .compass => true,
        else => false,
    };
}

/// The game's item receipt number for it: what the chest or NPC gives.
/// Progressive items and the uncle's sword are worked out when they're
/// picked up, from what Link has; their numbers here are the first level.
pub fn byte(it: Item) u8 {
    return switch (it) {
        .nothing => 0x5a,
        .l1_sword, .progressive_sword, .uncle_sword => 0x49,
        .l1_sword_and_shield => 0x00,
        .l2_sword, .master_sword => 0x50,
        .l3_sword => 0x02,
        .l4_sword => 0x03,
        .blue_shield, .progressive_shield => 0x04,
        .red_shield => 0x05,
        .mirror_shield => 0x06,
        .blue_mail, .progressive_armor => 0x22,
        .red_mail => 0x23,
        .fire_rod => 0x07,
        .ice_rod => 0x08,
        .hammer => 0x09,
        .hookshot => 0x0a,
        .bow, .progressive_bow => 0x0b,
        .bow_and_arrows => 0x3a,
        .bow_and_silver_arrows => 0x3b,
        .silver_arrow_upgrade => 0x58,
        .boomerang => 0x0c,
        .red_boomerang => 0x2a,
        .powder => 0x0d,
        .mushroom => 0x29,
        .bombos => 0x0f,
        .ether => 0x10,
        .quake => 0x11,
        .lamp => 0x12,
        .shovel => 0x13,
        .ocarina_inactive => 0x14,
        .ocarina_active => 0x4a,
        .cane_of_somaria => 0x15,
        .cane_of_byrna => 0x18,
        .cape => 0x19,
        .magic_mirror => 0x1a,
        .power_glove, .progressive_glove => 0x1b,
        .titans_mitt => 0x1c,
        .book_of_mudora => 0x1d,
        .flippers => 0x1e,
        .moon_pearl => 0x1f,
        .bug_catching_net => 0x21,
        .pegasus_boots => 0x4b,
        .half_magic => 0x4e,
        .quarter_magic => 0x4f,
        .bottle => 0x16,
        .bottle_with_red_potion => 0x2b,
        .bottle_with_green_potion => 0x2c,
        .bottle_with_blue_potion => 0x2d,
        .bottle_with_bee => 0x3c,
        .bottle_with_gold_bee => 0x48,
        .bottle_with_fairy => 0x3d,
        .piece_of_heart => 0x17,
        .boss_heart_container => 0x3e,
        .heart_container => 0x3f,
        .bomb => 0x27,
        .three_bombs => 0x28,
        .ten_bombs => 0x31,
        .arrow => 0x43,
        .ten_arrows => 0x44,
        .one_rupee => 0x34,
        .five_rupees => 0x35,
        .twenty_rupees => 0x36,
        .twenty_rupees2 => 0x47,
        .fifty_rupees => 0x41,
        .one_hundred_rupees => 0x40,
        .three_hundred_rupees => 0x46,
        .heart => 0x42,
        .small_magic => 0x45,
        .bomb_upgrade5 => 0x51,
        .bomb_upgrade10 => 0x52,
        .arrow_upgrade5 => 0x53,
        .arrow_upgrade10 => 0x54,
        .pendant_of_courage => 0x37,
        .pendant_of_wisdom => 0x38,
        .pendant_of_power => 0x39,
        .crystal1, .crystal2, .crystal3, .crystal4, .crystal5, .crystal6, .crystal7 => 0x20,
        .triforce => 0x6a,
        .key_h2, .key_p2, .key_p3, .key_a1, .key_d1, .key_d2, .key_d3, .key_d4, .key_d5, .key_d6, .key_d7, .key_a2 => 0x24,
        .big_key_p1, .big_key_p2, .big_key_p3, .big_key_d1, .big_key_d2, .big_key_d3, .big_key_d4, .big_key_d5, .big_key_d6, .big_key_d7, .big_key_a2 => 0x32,
        .map_h2, .map_p1, .map_p2, .map_p3, .map_d1, .map_d2, .map_d3, .map_d4, .map_d5, .map_d6, .map_d7, .map_a2 => 0x33,
        .compass_p1, .compass_p2, .compass_p3, .compass_d1, .compass_d2, .compass_d3, .compass_d4, .compass_d5, .compass_d6, .compass_d7, .compass_a2 => 0x25,
        .rescue_zelda, .defeat_agahnim, .defeat_agahnim2, .defeat_ganon, .big_red_bomb => 0x5a,
    };
}

/// How many of each item there are: what's been found, or what the logic
/// assumes will be.
pub const Items = struct {
    n: [kCount]u8 = @splat(0),

    pub fn add(self: *Items, it: Item) void {
        self.n[@backingInt(it)] +|= 1;
    }

    pub fn remove(self: *Items, it: Item) void {
        self.n[@backingInt(it)] -|= 1;
    }

    pub fn merge(self: *Items, other: *const Items) void {
        for (&self.n, other.n) |*a, b| a.* +|= b;
    }

    pub fn has(self: *const Items, it: Item) bool {
        return self.n[@backingInt(it)] >= 1;
    }

    /// At least `at_least` of it.
    pub fn hasN(self: *const Items, it: Item, at_least: u8) bool {
        return self.n[@backingInt(it)] >= at_least;
    }

    pub fn count(self: *const Items, it: Item) u8 {
        return self.n[@backingInt(it)];
    }

    // ------------------------------------------------- what they add up to

    pub fn canLiftRocks(self: *const Items) bool {
        return self.has(.power_glove) or self.has(.progressive_glove) or self.has(.titans_mitt);
    }

    pub fn canLiftDarkRocks(self: *const Items) bool {
        return self.has(.titans_mitt) or self.hasN(.progressive_glove, 2);
    }

    pub fn canLightTorches(self: *const Items) bool {
        return self.has(.fire_rod) or self.has(.lamp);
    }

    pub fn canMeltThings(self: *const Items) bool {
        return self.has(.fire_rod) or (self.has(.bombos) and self.hasSword(1));
    }

    /// The flute, in the Open world: it plays wherever it's found.
    pub fn canFly(self: *const Items) bool {
        return self.has(.ocarina_active) or self.has(.ocarina_inactive);
    }

    pub fn canSpinSpeed(self: *const Items) bool {
        return self.has(.pegasus_boots) and (self.hasSword(1) or self.has(.hookshot));
    }

    pub fn canShootArrows(self: *const Items, min_level: u8) bool {
        if (min_level >= 2) {
            return self.has(.bow_and_silver_arrows) or
                self.hasN(.progressive_bow, 2) or
                (self.has(.silver_arrow_upgrade) and (self.has(.bow) or self.has(.bow_and_arrows) or self.has(.progressive_bow)));
        }
        return self.has(.bow) or self.has(.progressive_bow) or self.has(.bow_and_arrows) or self.has(.bow_and_silver_arrows);
    }

    pub fn canBlockLasers(self: *const Items) bool {
        return self.has(.mirror_shield) or self.hasN(.progressive_shield, 3);
    }

    /// Enough magic, counting each bottle as a refill, for `bars` bars.
    pub fn canExtendMagic(self: *const Items, bars: f32) bool {
        const base: f32 = if (self.has(.quarter_magic)) 4 else if (self.has(.half_magic)) 2 else 1;
        const bottles: f32 = @floatFromInt(self.bottleCount());
        return base + base * bottles >= bars;
    }

    pub fn hasHealth(self: *const Items, minimum: f32) bool {
        return self.heartCount(0) >= minimum;
    }

    /// Hearts: `initial`, a whole one for each container and a quarter for
    /// each piece.
    pub fn heartCount(self: *const Items, initial: f32) f32 {
        const pieces: f32 = @floatFromInt(self.count(.piece_of_heart));
        const whole: f32 = @floatFromInt(@as(u16, self.count(.boss_heart_container)) + self.count(.heart_container));
        return initial + whole + pieces * 0.25;
    }

    pub fn canKillEscapeThings(self: *const Items) bool {
        return self.has(.uncle_sword) or self.has(.cane_of_somaria) or self.has(.ten_bombs) or
            self.has(.cane_of_byrna) or self.canShootArrows(1) or self.has(.hammer) or self.has(.fire_rod);
    }

    pub fn canKillMostThings(self: *const Items, enemies: u8) bool {
        return self.hasSword(1) or self.has(.cane_of_somaria) or
            (self.canBombThings() and enemies < 6) or
            (self.has(.cane_of_byrna) and (enemies < 6 or self.canExtendMagic(2))) or
            self.canShootArrows(1) or self.has(.hammer) or self.has(.fire_rod);
    }

    pub fn canBombThings(self: *const Items) bool {
        _ = self;
        return true;
    }

    pub fn canGetGoodBee(self: *const Items) bool {
        return self.has(.bug_catching_net) and self.hasABottle() and
            (self.has(.pegasus_boots) or (self.hasSword(1) and self.has(.quake)));
    }

    pub fn hasSword(self: *const Items, min_level: u8) bool {
        const prog = self.count(.progressive_sword);
        const uncle: u8 = @intFromBool(self.has(.uncle_sword));
        // The uncle's counts as one more progressive sword.
        const levels = prog + uncle;
        return switch (min_level) {
            0, 1 => levels >= 1 or self.has(.l1_sword) or self.has(.l1_sword_and_shield) or self.has(.l2_sword) or
                self.has(.master_sword) or self.has(.l3_sword) or self.has(.l4_sword),
            2 => levels >= 2 or self.has(.l2_sword) or self.has(.master_sword) or self.has(.l3_sword) or self.has(.l4_sword),
            3 => levels >= 3 or self.has(.l3_sword) or self.has(.l4_sword),
            else => levels >= 4 or self.has(.l4_sword),
        };
    }

    pub fn hasArmor(self: *const Items, min_level: u8) bool {
        if (min_level >= 2) return self.hasN(.progressive_armor, 2) or self.has(.red_mail);
        return self.has(.progressive_armor) or self.has(.blue_mail) or self.has(.red_mail);
    }

    pub fn bottleCount(self: *const Items) u16 {
        var n: u16 = 0;
        inline for (.{ .bottle, .bottle_with_red_potion, .bottle_with_green_potion, .bottle_with_blue_potion, .bottle_with_bee, .bottle_with_gold_bee, .bottle_with_fairy }) |b| n += self.count(b);
        return n;
    }

    pub fn hasABottle(self: *const Items) bool {
        return self.bottleCount() >= 1;
    }

    pub fn hasBottle(self: *const Items, at_least: u16) bool {
        return self.bottleCount() >= at_least;
    }

    pub fn crystalCount(self: *const Items) u8 {
        var n: u8 = 0;
        inline for (.{ .crystal1, .crystal2, .crystal3, .crystal4, .crystal5, .crystal6, .crystal7 }) |c| n += @intFromBool(self.has(c));
        return n;
    }
};

test "the sword levels count the uncle's as a progressive one" {
    var it = Items{};
    try std.testing.expect(!it.hasSword(1));
    it.add(.uncle_sword);
    try std.testing.expect(it.hasSword(1));
    try std.testing.expect(!it.hasSword(2));
    it.add(.progressive_sword);
    try std.testing.expect(it.hasSword(2));
    it.add(.progressive_sword);
    it.add(.progressive_sword);
    try std.testing.expect(it.hasSword(4));
}

test "magic and bottles add up as VT's do" {
    var it = Items{};
    try std.testing.expect(!it.canExtendMagic(2));
    it.add(.bottle);
    try std.testing.expect(it.canExtendMagic(2));
    try std.testing.expect(!it.canExtendMagic(3));
    it.add(.half_magic);
    try std.testing.expect(it.canExtendMagic(4));
    it.add(.piece_of_heart);
    it.add(.piece_of_heart);
    it.add(.boss_heart_container);
    try std.testing.expectEqual(@as(f32, 4.5), it.heartCount(3));
}
