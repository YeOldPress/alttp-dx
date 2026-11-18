//! Making a seed: the item pool, the pendants and crystals, and the fill
//! that places everything so the game can always be finished. A port of the
//! VT randomizer's app/Randomizer.php (prepareWorld, fillPrizes),
//! app/Filler/RandomAssumed.php and the item counts in config/item.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT).
//!
//! The same seed always makes the same placement here, but not the same as
//! alttpr.com's: VT's PHP random numbers aren't ours.
//!
//! v1 differs from VT's defaults in two places, to keep the game's own code
//! honest: pendants stay pendants and crystals crystals (each dungeon's
//! ending is the right one), and Misery Mire and Turtle Rock open with their
//! vanilla medallions.
const std = @import("std");
const world_mod = @import("world.zig");
const items_mod = @import("items.zig");
const locs = @import("locations.zig");

const World = world_mod.World;
const Config = world_mod.Config;
const Item = items_mod.Item;
const Items = items_mod.Items;
const Loc = locs.Loc;

pub const Error = error{ NoAvailableLocation, TooManyItems, CannotPlacePrize };

/// A list of items, in order, with room for the whole pool.
const List = struct {
    buf: [256]Item = undefined,
    len: usize = 0,

    fn add(self: *List, it: Item) void {
        self.buf[self.len] = it;
        self.len += 1;
    }

    fn addN(self: *List, it: Item, n: usize) void {
        for (0..n) |_| self.add(it);
    }

    fn slice(self: *List) []Item {
        return self.buf[0..self.len];
    }

    fn pop(self: *List) ?Item {
        if (self.len == 0) return null;
        self.len -= 1;
        return self.buf[self.len];
    }

    fn appendAll(self: *List, other: []const Item) void {
        for (other) |it| self.add(it);
    }

    fn toItems(self: *const List) Items {
        var out = Items{};
        for (self.buf[0..self.len]) |it| out.add(it);
        return out;
    }
};

/// A list of locations, in order.
const LocList = struct {
    buf: [locs.kLocs.len]Loc = undefined,
    len: usize = 0,

    fn add(self: *LocList, l: Loc) void {
        self.buf[self.len] = l;
        self.len += 1;
    }

    fn slice(self: *LocList) []Loc {
        return self.buf[0..self.len];
    }

    fn empty(self: *const LocList, w: *const World) LocList {
        var out = LocList{};
        for (self.buf[0..self.len]) |l| {
            if (w.itemAt(l) == null) out.add(l);
        }
        return out;
    }

    fn reversed(self: *const LocList) LocList {
        var out = LocList{};
        var i = self.len;
        while (i > 0) {
            i -= 1;
            out.add(self.buf[i]);
        }
        return out;
    }
};

const Gen = struct {
    rng: std.Random.DefaultPrng,
    w: World,

    fn random(g: *Gen) std.Random {
        return g.rng.random();
    }

    /// get_random_int(min, max), both ends included.
    fn int(g: *Gen, min: usize, max: usize) usize {
        return g.random().intRangeAtMost(usize, min, max);
    }

    fn shuffle(g: *Gen, list: []Item) void {
        g.random().shuffle(Item, list);
    }

    /// Collection::randomCollection(n): n of them, in random order.
    fn randomLocs(g: *Gen, from: *const LocList, n: usize) LocList {
        var old = from.*;
        var out = LocList{};
        var left = n;
        while (left > 0 and old.len > 0) : (left -= 1) {
            const i = g.int(0, old.len - 1);
            out.add(old.buf[i]);
            std.mem.copyForwards(Loc, old.buf[i .. old.len - 1], old.buf[i + 1 .. old.len]);
            old.len -= 1;
        }
        return out;
    }

    /// World.getBottle: a bottle, empty or with anything catchable in it.
    fn bottle(g: *Gen, filled: bool) Item {
        const kBottles = [_]Item{ .bottle, .bottle_with_red_potion, .bottle_with_green_potion, .bottle_with_blue_potion, .bottle_with_bee, .bottle_with_gold_bee, .bottle_with_fairy };
        return kBottles[g.int(if (filled) 1 else 0, kBottles.len - 1)];
    }

    // ------------------------------------------------------------ pools

    /// config/item.php's 'dungeon': every dungeon's keys, big key, map and
    /// compass.
    fn dungeonPool(list: *List) void {
        const kCounts = [_]struct { Item, usize }{
            .{ .big_key_a2, 1 }, .{ .big_key_d1, 1 }, .{ .big_key_d2, 1 }, .{ .big_key_d3, 1 },
            .{ .big_key_d4, 1 }, .{ .big_key_d5, 1 }, .{ .big_key_d6, 1 }, .{ .big_key_d7, 1 },
            .{ .big_key_p1, 1 }, .{ .big_key_p2, 1 }, .{ .big_key_p3, 1 }, .{ .key_a2, 4 },
            .{ .key_d1, 6 },     .{ .key_d2, 1 },     .{ .key_d3, 3 },     .{ .key_d4, 1 },
            .{ .key_d5, 2 },     .{ .key_d6, 3 },     .{ .key_d7, 4 },     .{ .key_a1, 2 },
            .{ .key_h2, 1 },     .{ .key_p2, 1 },     .{ .key_p3, 1 },     .{ .map_a2, 1 },
            .{ .map_d1, 1 },     .{ .map_d2, 1 },     .{ .map_d3, 1 },     .{ .map_d4, 1 },
            .{ .map_d5, 1 },     .{ .map_d6, 1 },     .{ .map_d7, 1 },     .{ .map_h2, 1 },
            .{ .map_p1, 1 },     .{ .map_p2, 1 },     .{ .map_p3, 1 },     .{ .compass_a2, 1 },
            .{ .compass_d1, 1 }, .{ .compass_d2, 1 }, .{ .compass_d3, 1 }, .{ .compass_d4, 1 },
            .{ .compass_d5, 1 }, .{ .compass_d6, 1 }, .{ .compass_d7, 1 }, .{ .compass_p1, 1 },
            .{ .compass_p2, 1 }, .{ .compass_p3, 1 },
        };
        for (kCounts) |e| list.addN(e[0], e[1]);
    }

    /// config/item.php's 'advancement', the bottles each drawn at random.
    fn advancementPool(g: *Gen, list: *List) void {
        list.addN(.progressive_sword, 4);
        list.addN(.boss_heart_container, 10);
        for (0..4) |_| list.add(g.bottle(false));
        inline for (.{ .bombos, .book_of_mudora, .cane_of_somaria, .cape, .ether, .fire_rod, .flippers, .hammer, .hookshot, .ice_rod, .lamp, .magic_mirror, .moon_pearl, .mushroom, .ocarina_inactive, .pegasus_boots, .powder, .quake, .shovel }) |it| list.add(it);
        list.addN(.progressive_glove, 2);
        list.addN(.progressive_bow, 2);
        list.add(.bug_catching_net);
        list.addN(.progressive_shield, 3);
        list.add(.cane_of_byrna);
        list.add(.ten_bombs);
        list.add(.half_magic);
    }

    /// config/item.php's 'nice'.
    fn nicePool(list: *List) void {
        list.add(.heart_container);
        list.addN(.progressive_armor, 2);
        list.add(.boomerang);
        list.add(.red_boomerang);
        list.add(.one_hundred_rupees);
        list.addN(.three_hundred_rupees, 5);
    }

    /// config/item.php's 'junk'.
    fn junkPool(list: *List) void {
        list.addN(.piece_of_heart, 24);
        list.add(.arrow);
        list.addN(.ten_arrows, 12);
        list.addN(.three_bombs, 16);
        list.addN(.one_rupee, 2);
        list.addN(.five_rupees, 4);
        list.addN(.twenty_rupees, 28);
        list.addN(.fifty_rupees, 7);
    }

    // ----------------------------------------------------------- prizes

    fn isPrize(l: Loc) bool {
        return switch (World.info(l).kind) {
            .prize_crystal, .prize_pendant => true,
            else => false,
        };
    }

    /// Randomizer.fillPrizes, with the prizes kept to their kind: each
    /// crystal dungeon gets a crystal and each pendant one a pendant, the
    /// one it'd take to finish still reachable with everything else
    /// assumed.
    fn fillPrizes(g: *Gen) Error!void {
        var all = LocList{};
        for (0..locs.kLocs.len) |i| {
            const l: Loc = @fromBackingInt(@intCast(i));
            if (isPrize(l)) all.add(l);
        }
        var attempts: usize = 6;
        while (attempts > 0) : (attempts -= 1) {
            const order = g.randomLocs(&all, 15);
            var ok = true;
            inline for (.{ .prize_crystal, .prize_pendant }) |want| {
                var places = List{};
                if (want == .prize_crystal) {
                    inline for (.{ .crystal1, .crystal2, .crystal3, .crystal4, .crystal5, .crystal6, .crystal7 }) |c| places.add(c);
                } else {
                    inline for (.{ .pendant_of_courage, .pendant_of_power, .pendant_of_wisdom }) |p| places.add(p);
                }
                g.shuffle(places.slice());
                for (order.buf[0..order.len]) |loc| {
                    if (!ok) break;
                    if (World.info(loc).kind != want or g.w.itemAt(loc) != null) continue;
                    const total = places.len;
                    var placed: ?Item = null;
                    var assumed: Items = .{};
                    var tries: usize = 0;
                    while (tries < total) : (tries += 1) {
                        const prize = places.pop().?;
                        g.w.resetCollected();
                        var base = List{};
                        dungeonPool(&base);
                        g.advancementPool(&base);
                        base.appendAll(places.slice());
                        assumed = g.w.collectItems(base.toItems());
                        if (g.w.canAccess(loc, &assumed)) {
                            placed = prize;
                            break;
                        }
                        // Back to the front of the line.
                        std.mem.copyBackwards(Item, places.buf[1 .. places.len + 1], places.buf[0..places.len]);
                        places.buf[0] = prize;
                        places.len += 1;
                    }
                    const prize = placed orelse continue;
                    g.w.placed[@backingInt(loc)] = prize;
                    if (!g.w.won(assumed)) ok = false;
                }
            }
            // Every one filled, and still a way to the end: done. Otherwise
            // empty them and try another order.
            var full = ok;
            for (all.buf[0..all.len]) |l| full = full and g.w.itemAt(l) != null;
            if (full) return;
            for (all.buf[0..all.len]) |l| g.w.placed[@backingInt(l)] = null;
        }
        return Error.CannotPlacePrize;
    }

    // ------------------------------------------------------------- fill

    /// RandomAssumed.fillItemsInLocations: each item into the first of
    /// `locations` it can go in (a random one for a map or compass), with
    /// every item not yet placed, and `base`, assumed in hand.
    fn fillItems(g: *Gen, fill: []const Item, locations: *const LocList, base: *const Items) Error!void {
        var remaining = Items{};
        for (fill) |it| remaining.add(it);
        var empty_count: usize = 0;
        for (locations.buf[0..locations.len]) |l| empty_count += @intFromBool(g.w.itemAt(l) == null);
        if (fill.len > empty_count) return Error.TooManyItems;

        for (fill) |item| {
            remaining.remove(item);
            var assumed = remaining;
            assumed.merge(base);
            assumed.merge(&g.w.pre_collected);
            g.w.resetCollected();
            var found: usize = 0;
            while (true) {
                const more = g.w.collectOtherItems(&assumed);
                assumed.merge(&more);
                const now = g.w.collectedCount();
                if (now == found) break;
                found = now;
            }
            var fillable = LocList{};
            for (locations.buf[0..locations.len]) |l| {
                if (g.w.itemAt(l) == null and g.w.canFill(l, item, &assumed, true)) fillable.add(l);
            }
            if (fillable.len == 0) return Error.NoAvailableLocation;
            const at = switch (items_mod.kind(item)) {
                .map, .compass => fillable.buf[g.int(0, fillable.len - 1)],
                else => fillable.buf[0],
            };
            g.w.placed[@backingInt(at)] = item;
        }
    }

    /// Filler.fastFillItemsInLocations: the last of `items` into the first
    /// empty location, and so on, no questions asked.
    fn fastFill(g: *Gen, items: *List, locations: *const LocList) void {
        for (locations.buf[0..locations.len]) |l| {
            if (g.w.itemAt(l) != null) continue;
            const it = items.pop() orelse return;
            g.w.placed[@backingInt(l)] = it;
        }
    }

    /// RandomAssumed.fill.
    fn assumedFill(g: *Gen, dungeon: []const Item, required: []Item, nice: []Item, extra: *List) Error!void {
        var all = LocList{};
        for (0..locs.kLocs.len) |i| {
            const l: Loc = @fromBackingInt(@intCast(i));
            if (g.w.itemAt(l) == null) all.add(l);
        }
        var order = g.randomLocs(&all, all.len);

        var base = Items{};
        for (required) |it| base.add(it);
        for (nice) |it| base.add(it);
        try g.fillItems(dungeon, &order, &base);

        // Some junk in Ganon's Tower, so the good stuff's spread around.
        var gt = LocList{};
        for (all.buf[0..all.len]) |l| {
            if (World.info(l).region == .ganons_tower and g.w.itemAt(l) == null) gt.add(l);
        }
        const gt_pick = g.randomLocs(&gt, g.int(0, 15 * g.w.cfg.crystals_tower / 7));
        g.shuffle(extra.slice());
        var trash = List{};
        const take = @min(gt_pick.len, extra.len);
        trash.appendAll(extra.buf[0..take]);
        std.mem.copyForwards(Item, extra.buf[0 .. extra.len - take], extra.buf[take..extra.len]);
        extra.len -= take;
        g.fastFill(&trash, &gt_pick);

        order = order.empty(&g.w).reversed();
        g.shuffle(required);
        try g.fillItems(required, &order, &Items{});

        var rest = order.empty(&g.w);
        rest = g.randomLocs(&rest, rest.len);
        g.shuffle(nice);
        var nice_list = List{};
        nice_list.appendAll(nice);
        g.fastFill(&nice_list, &rest);

        g.shuffle(extra.slice());
        const last = rest.empty(&g.w);
        g.fastFill(extra, &last);
    }

    /// Randomizer.prepareWorld, then the fill.
    fn run(g: *Gen) Error!void {
        const w = &g.w;
        // The goal: the Triforce, from Ganon.
        w.placed[@backingInt(Loc.ganon)] = .triforce;

        var dungeon = List{};
        dungeonPool(&dungeon);
        var advancement = List{};
        g.advancementPool(&advancement);
        var nice = List{};
        nicePool(&nice);
        var trash = List{};
        junkPool(&trash);

        if (w.cfg.mode != .standard) w.pre_collected.add(.rescue_zelda);

        // Misery Mire and Turtle Rock open with their own medallions (VT
        // picks each at random).
        w.placed[@backingInt(Loc.misery_mire_medallion)] = .ether;
        w.placed[@backingInt(Loc.turtle_rock_medallion)] = .quake;

        try g.fillPrizes();

        // Fountains: what an empty bottle's filled with.
        w.placed[@backingInt(Loc.waterfall_bottle)] = g.bottle(true);
        w.placed[@backingInt(Loc.pyramid_bottle)] = g.bottle(true);
        w.placed[@backingInt(Loc.pyramid_fairy_bow)] = .bow_and_arrows;

        // The swords, bottles and health come out of the pools, to be put
        // back as the logic and the placement wants.
        var swords = List{};
        var bottles = List{};
        var health = List{};
        var armors = List{};
        var keep = List{};
        for (advancement.slice()) |it| {
            switch (items_mod.kind(it)) {
                .sword => swords.add(it),
                .bottle => bottles.add(it),
                else => if (it == .silver_arrow_upgrade) nice.add(it) else keep.add(it),
            }
        }
        advancement = keep;
        keep = .{};
        for (nice.slice()) |it| {
            switch (items_mod.kind(it)) {
                .sword => swords.add(it),
                .health => health.add(it),
                .armor => armors.add(it),
                else => keep.add(it),
            }
        }
        nice = keep;
        keep = .{};
        for (trash.slice()) |it| {
            if (items_mod.kind(it) == .health) health.add(it) else keep.add(it);
        }
        trash = keep;
        if (w.cfg.item_placement == .basic) {
            advancement.appendAll(health.slice());
            advancement.appendAll(armors.slice());
        } else {
            nice.appendAll(health.slice());
            nice.appendAll(armors.slice());
        }
        // The uncle's sword and the Master Sword are needed; the other two
        // are nice to have.
        if (swords.pop()) |_| advancement.add(.uncle_sword);
        if (swords.pop()) |s| advancement.add(s);
        nice.appendAll(swords.slice());
        // One bottle's needed.
        if (bottles.pop()) |b| advancement.add(b);
        nice.appendAll(bottles.slice());

        g.shuffle(advancement.slice());
        g.shuffle(nice.slice());
        g.shuffle(trash.slice());
        try g.assumedFill(dungeon.slice(), advancement.slice(), nice.slice(), &trash);
    }
};

/// A seed's placement: everything in its place, and the game winnable.
/// Tries a few times over if the fill paints itself into a corner, as VT
/// does, the same way each time for a seed.
pub fn generate(seed: u64, cfg: Config) Error!World {
    var last_err: Error = Error.NoAvailableLocation;
    var attempt: u64 = 0;
    while (attempt < 20) : (attempt += 1) {
        var g = Gen{
            .rng = std.Random.DefaultPrng.init(seed *% 0x9E3779B97F4A7C15 +% attempt),
            .w = World.init(cfg),
        };
        g.run() catch |err| {
            last_err = err;
            continue;
        };
        return g.w;
    }
    return last_err;
}

/// Whether everything needed to beat Ganon can be had, in some order, from
/// nothing: the check every seed has to pass.
pub fn beatable(w: *World) bool {
    w.resetCollected();
    return w.won(.{});
}

// ------------------------------------------------------------------- tests

const rules = @import("rules.zig");

test "seeds fill, every one can be finished, and the same seed fills the same" {
    var seed: u64 = 1;
    while (seed <= 40) : (seed += 1) {
        var w = try generate(seed, .{});
        try std.testing.expect(beatable(&w));
        var again = try generate(seed, .{});
        try std.testing.expectEqualSlices(?Item, &w.placed, &again.placed);
    }
}

test "a seed places VT's whole pool, every dungeon item at home" {
    const w = try generate(7, .{});
    var counts = Items{};
    for (w.placed, 0..) |maybe, i| {
        const kind = locs.kLocs[i].kind;
        const item = maybe orelse {
            // Only what says how things open is ever left out of a fill.
            return error.EmptyLocation;
        };
        switch (kind) {
            .prize_crystal, .prize_pendant, .prize_event, .medallion, .fountain, .trade => continue,
            else => {},
        }
        counts.add(item);
        if (items_mod.isDungeonItem(item)) {
            var home = false;
            for (rules.kRegionItems[@backingInt(locs.kLocs[i].region)]) |ri| home = home or ri == item;
            try std.testing.expect(home);
        }
    }
    try std.testing.expectEqual(@as(u8, 3), counts.count(.progressive_sword));
    try std.testing.expectEqual(@as(u8, 1), counts.count(.uncle_sword));
    try std.testing.expectEqual(@as(u8, 24), counts.count(.piece_of_heart));
    try std.testing.expectEqual(@as(u8, 6), counts.count(.key_d1));
    try std.testing.expectEqual(@as(u8, 3), counts.count(.progressive_shield));
    var total: usize = 0;
    for (counts.n) |c| total += c;
    try std.testing.expectEqual(@as(usize, 216), total);
}
