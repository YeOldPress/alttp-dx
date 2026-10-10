//! Every achievement there is, and the file that remembers which are done.
//!
//! Kept apart from achievements.zig, which watches the game for them, so the
//! start menu can list them and read the file before there's any game to
//! watch. Unlocks count across every save file: get one in any file and it
//! stays got, in saves/achievements.txt, one name a line.
const std = @import("std");
const fileio = @import("fileio.zig");
const hud = @import("hud_tables.zig");

pub const kPath = "saves/achievements.txt";

pub const Category = enum {
    story,
    collection,
    secrets,
    challenges,

    pub fn label(self: Category) []const u8 {
        return switch (self) {
            .story => "Story",
            .collection => "Collection",
            .secrets => "Secrets",
            .challenges => "Challenges",
        };
    }
};

/// The names in the file. Renaming one forgets everyone's unlock of it, so
/// they stay put; what players see is `name`.
pub const Id = enum {
    uncle,
    zelda,
    eastern,
    desert,
    hera,
    master_sword,
    agahnim,
    dark_world,
    darkness,
    swamp,
    skull,
    thieves,
    ice,
    mire,
    turtle,
    agahnim2,
    ganon,

    heart_piece,
    twenty_hearts,
    bottles,
    medallions,
    all_items,
    silver_arrows,
    golden_sword,
    mirror_shield,
    red_mail,
    titans_mitt,
    max_capacity,
    rupees,

    witch,
    mad_batter,
    flute,
    smiths,
    fairy_boomerang,
    purple_chest,
    tablets,
    hobo,
    sick_kid,
    stumpy,
    zora,
    sahasrahla,
    bee,

    untouchable,
    flawless_ganon,
    three_hearts,
    deathless,
    green_tunic,
};

pub const Achievement = struct {
    id: Id,
    name: []const u8,
    about: []const u8,
    category: Category,
    /// An inventory icon, as the HUD's ItemBoxGfx lays one out.
    icon: [4]u16,
};

fn a(id: Id, category: Category, name: []const u8, about: []const u8, icon: hud.ItemBoxGfx) Achievement {
    return .{ .id = id, .name = name, .about = about, .category = category, .icon = icon.v };
}

/// In the order they're listed, a category at a time.
pub const kList = [_]Achievement{
    a(.uncle, .story, "It's Dangerous to Go Alone", "Take the sword your uncle leaves you.", hud.kHudItemSword[1]),
    a(.zelda, .story, "Princess Rescue", "Lead Princess Zelda safely to the Sanctuary.", hud.kHudItemTorch[1]),
    a(.eastern, .story, "Pendant of Courage", "Defeat the Armos Knights in the Eastern Palace.", hud.kHudPendants2[1]),
    a(.desert, .story, "Pendant of Power", "Defeat the Lanmolas in the Desert Palace.", hud.kHudPendants0[1]),
    a(.hera, .story, "Pendant of Wisdom", "Defeat Moldorm at the top of the Tower of Hera.", hud.kHudPendants1[1]),
    a(.master_sword, .story, "Blade of Evil's Bane", "Draw the Master Sword in the Lost Woods.", hud.kHudItemSword[2]),
    a(.agahnim, .story, "Wizard Down", "Defeat Agahnim at the top of Hyrule Castle.", hud.kHudItemCape[1]),
    a(.dark_world, .story, "Welcome to the Dark World", "Set foot in the Dark World.", hud.kHudItemMoonPearl[1]),
    a(.darkness, .story, "Palace of Darkness", "Defeat the Helmasaur King.", hud.kHudItemHammer[1]),
    a(.swamp, .story, "Swamp Palace", "Defeat Arrghus.", hud.kHudItemHookshot[1]),
    a(.skull, .story, "Skull Woods", "Defeat Mothula.", hud.kHudItemFireRod[1]),
    a(.thieves, .story, "Thieves' Town", "Defeat Blind the Thief.", hud.kHudItemGloves[2]),
    a(.ice, .story, "Ice Palace", "Defeat Kholdstare.", hud.kHudItemArmor[1]),
    a(.mire, .story, "Misery Mire", "Defeat Vitreous.", hud.kHudItemCaneSomaria[1]),
    a(.turtle, .story, "Turtle Rock", "Defeat Trinexx.", hud.kHudItemCaneByrna[1]),
    a(.agahnim2, .story, "Second Time's the Charm", "Defeat Agahnim again, at the top of Ganon's Tower.", hud.kHudItemMirror[2]),
    a(.ganon, .story, "The Golden Power", "Defeat Ganon and claim the Triforce.", hud.kHudItemBow[4]),

    a(.heart_piece, .collection, "Piece of Heart", "Find a Piece of Heart.", hud.kHudItemHeartPieces[1]),
    a(.twenty_hearts, .collection, "All Heart", "Have all twenty heart containers.", hud.kHudItemHeartPieces[3]),
    a(.bottles, .collection, "Bottled Up", "Carry four bottles.", hud.kHudItemBottles[3]),
    a(.medallions, .collection, "Medallion Collector", "Have Bombos, Ether and Quake.", hud.kHudItemBombos[1]),
    a(.all_items, .collection, "Fully Equipped", "Fill every slot in the inventory.", hud.kHudItemBookMudora[1]),
    a(.silver_arrows, .collection, "Silver Lining", "Get the Silver Arrows.", hud.kHudItemBow[3]),
    a(.golden_sword, .collection, "Golden Sword", "Have the Golden Sword.", hud.kHudItemSword[4]),
    a(.mirror_shield, .collection, "Mirror Shield", "Have the Mirror Shield.", hud.kHudItemShield[3]),
    a(.red_mail, .collection, "Red Mail", "Have the Red Mail.", hud.kHudItemArmor[2]),
    a(.titans_mitt, .collection, "Heavy Lifting", "Have the Titan's Mitt.", hud.kHudItemGloves[2]),
    a(.max_capacity, .collection, "Packing Heat", "Carry 50 bombs and 70 arrows.", hud.kHudItemBombs[1]),
    a(.rupees, .collection, "Rupee Hoarder", "Hold 999 rupees.", hud.kHudItemPalaceItem[0]),

    a(.witch, .secrets, "Witch's Brew", "Trade the mushroom for Magic Powder.", hud.kHudItemMushroom[2]),
    a(.mad_batter, .secrets, "Half the Magic", "Let the Mad Batter halve your magic use.", hud.kHudItemMushroom[1]),
    a(.flute, .secrets, "Bird Is the Word", "Wake the bird with the flute in Kakariko.", hud.kHudItemFlute[3]),
    a(.smiths, .secrets, "Tempered Steel", "Reunite the blacksmiths and temper your sword.", hud.kHudItemSword[3]),
    a(.fairy_boomerang, .secrets, "Waterfall of Wishing", "Throw your boomerang to the fairy and get a better one.", hud.kHudItemBoomerang[2]),
    a(.purple_chest, .secrets, "Locked Box", "Bring the purple chest home to the smithy.", hud.kHudItemPalaceItem[1]),
    a(.tablets, .secrets, "Ancient Tablets", "Read both stone tablets.", hud.kHudItemEther[1]),
    a(.hobo, .secrets, "Under the Bridge", "Get a bottle from the man under the bridge.", hud.kHudItemBottles[2]),
    a(.sick_kid, .secrets, "Bug Catcher", "Bring a bottle to the sick boy in Kakariko.", hud.kHudItemBugNet[1]),
    a(.stumpy, .secrets, "Talk to the Trees", "Get the shovel from Stumpy in the Dark World.", hud.kHudItemFlute[1]),
    a(.zora, .secrets, "Royal Purchase", "Buy the Zora's Flippers from King Zora.", hud.kHudItemFlippers[1]),
    a(.sahasrahla, .secrets, "Elder's Gift", "Show Sahasrahla the Pendant of Courage.", hud.kHudItemBoots[1]),
    a(.bee, .secrets, "Bee Keeper", "Catch a bee in a bottle.", hud.kHudItemBottles[7]),

    a(.untouchable, .challenges, "Untouchable", "Defeat a dungeon's boss without being hit.", hud.kHudItemShield[1]),
    a(.flawless_ganon, .challenges, "Flawless Victory", "Defeat Ganon without being hit.", hud.kHudItemShield[2]),
    a(.three_hearts, .challenges, "Three Heart Hero", "Defeat Ganon with only three heart containers.", hud.kHudItemHeartPieces[0]),
    a(.deathless, .challenges, "Never Say Die", "Reach the credits without dying once.", hud.kHudItemBottles[6]),
    a(.green_tunic, .challenges, "It's Not Easy Being Green", "Defeat Ganon in the green tunic.", hud.kHudItemArmor[0]),
};

pub fn get(id: Id) Achievement {
    return kList[indexOf(id)];
}

pub fn indexOf(id: Id) usize {
    return kIndexOf[@backingInt(id)];
}

const kIndexOf = blk: {
    var out: [std.meta.fieldNames(Id).len]usize = undefined;
    for (kList, 0..) |ach, i| out[@backingInt(ach.id)] = i;
    break :blk out;
};

/// Which are done.
pub const Unlocked = struct {
    set: std.EnumSet(Id) = .{},

    pub fn has(self: Unlocked, id: Id) bool {
        return self.set.contains(id);
    }

    pub fn count(self: Unlocked) usize {
        return self.set.count();
    }

    /// No file yet means nothing done yet. Names it doesn't know, from some
    /// other build, are passed over.
    pub fn load(alloc: std.mem.Allocator) Unlocked {
        var self = Unlocked{};
        const text = fileio.readWholeFile(alloc, kPath) catch return self;
        defer alloc.free(text);
        self.parse(text);
        return self;
    }

    pub fn parse(self: *Unlocked, text: []const u8) void {
        var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
        while (it.next()) |word| {
            if (std.meta.stringToEnum(Id, word)) |id| self.set.insert(id);
        }
    }

    pub fn write(self: Unlocked, buf: []u8) []const u8 {
        var n: usize = 0;
        for (kList) |ach| {
            if (!self.has(ach.id)) continue;
            const name = @tagName(ach.id);
            if (n + name.len + 1 > buf.len) break;
            @memcpy(buf[n..][0..name.len], name);
            buf[n + name.len] = '\n';
            n += name.len + 1;
        }
        return buf[0..n];
    }

    pub fn save(self: Unlocked) !void {
        var buf: [1024]u8 = undefined;
        try fileio.writeWholeFile(kPath, self.write(&buf));
    }
};

test "every achievement is listed once, a category at a time" {
    var seen = std.EnumSet(Id){};
    var last: Category = .story;
    for (kList) |ach| {
        try std.testing.expect(!seen.contains(ach.id));
        seen.insert(ach.id);
        try std.testing.expect(@backingInt(ach.category) >= @backingInt(last));
        last = ach.category;
        // The game's font has no colon or slash.
        for (ach.name) |ch| try std.testing.expect(ch != ':' and ch != '/');
    }
    try std.testing.expectEqual(std.meta.fieldNames(Id).len, seen.count());
}

test "the file round trips, and names it doesn't know are skipped" {
    var u = Unlocked{};
    u.parse("ganon\nnot_a_thing\r\nuncle  \n");
    try std.testing.expect(u.has(.ganon) and u.has(.uncle));
    try std.testing.expectEqual(@as(usize, 2), u.count());
    var buf: [1024]u8 = undefined;
    var back = Unlocked{};
    back.parse(u.write(&buf));
    try std.testing.expect(back.set.eql(u.set));
}
