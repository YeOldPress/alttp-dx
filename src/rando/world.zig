//! The randomizer's world: where every item's been placed, and what can be
//! reached with a set of items. A port of the VT randomizer's app/World.php,
//! app/Region.php and app/Location.php (github.com/sporchia/
//! alttp_vt_randomizer, MIT), with the rules themselves in rando/rules/.
const std = @import("std");
const items_mod = @import("items.zig");
const locs = @import("locations.zig");
const rules = @import("rules.zig");

pub const Item = items_mod.Item;
pub const Items = items_mod.Items;
pub const Loc = locs.Loc;
pub const Region = locs.Region;
pub const kLocCount = locs.kLocs.len;
pub const kRegionCount = locs.kRegionNames.len;

/// The settings the logic reads. v1 runs VT's defaults: Open mode, no
/// glitches, advanced item placement, every item reachable, dungeon items
/// in their own dungeons.
pub const Config = struct {
    mode: enum { open, standard, inverted } = .open,
    accessibility: enum { items, locations, none } = .items,
    item_placement: enum { basic, advanced } = .advanced,
    weapons: enum { randomized, assured, vanilla, swordless } = .randomized,
    /// How many lamps the logic wants before going through the dark.
    lamp_required: u8 = 1,
    wild_keys: bool = false,
    wild_big_keys: bool = false,
    wild_maps: bool = false,
    wild_compasses: bool = false,
    /// A boss may hold its dungeon's map or compass.
    boss_normal_location: bool = true,
    crystals_ganon: u8 = 7,
    crystals_tower: u8 = 7,

    pub fn swordless(self: Config) bool {
        return self.weapons == .swordless;
    }
};

pub const Boss = enum {
    armos_knights,
    lanmolas,
    moldorm,
    agahnim,
    helmasaur_king,
    arrghus,
    mothula,
    blind,
    kholdstare,
    vitreous,
    trinexx,
    agahnim2,
};

/// Whether `it` is enough to beat `boss`: VT's app/Boss.php.
pub fn canBeat(boss: Boss, w: *const World, it: *const Items) bool {
    const basic = w.cfg.item_placement == .basic;
    const swordless = w.cfg.swordless();
    return switch (boss) {
        .armos_knights => it.hasSword(1) or it.has(.hammer) or it.canShootArrows(1) or
            it.has(.boomerang) or it.has(.red_boomerang) or
            (it.canExtendMagic(4) and (it.has(.fire_rod) or it.has(.ice_rod))) or
            (it.canExtendMagic(2) and (it.has(.cane_of_byrna) or it.has(.cane_of_somaria))),
        .lanmolas => it.hasSword(1) or it.has(.hammer) or it.canShootArrows(1) or it.has(.fire_rod) or
            it.has(.ice_rod) or it.has(.cane_of_byrna) or it.has(.cane_of_somaria),
        .moldorm => it.hasSword(1) or it.has(.hammer),
        .agahnim, .agahnim2 => it.hasSword(1) or it.has(.hammer) or it.has(.bug_catching_net),
        .helmasaur_king => (it.canBombThings() or it.has(.hammer)) and
            (it.hasSword(2) or it.canShootArrows(1) or (!basic and it.hasSword(1))),
        .arrghus => (!basic or swordless or it.hasSword(2)) and it.has(.hookshot) and
            (it.has(.hammer) or it.hasSword(1) or
                ((it.canExtendMagic(2) or it.canShootArrows(1)) and (it.has(.fire_rod) or it.has(.ice_rod)))),
        .mothula => (!basic or it.hasSword(2) or (it.canExtendMagic(2) and it.has(.fire_rod))) and
            (it.hasSword(1) or it.has(.hammer) or
                (it.canExtendMagic(2) and (it.has(.fire_rod) or it.has(.cane_of_somaria) or it.has(.cane_of_byrna))) or
                it.canGetGoodBee()),
        .blind => (!basic or swordless or (it.hasSword(1) and (it.has(.cape) or it.has(.cane_of_byrna)))) and
            (it.hasSword(1) or it.has(.hammer) or it.has(.cane_of_somaria) or it.has(.cane_of_byrna)),
        .kholdstare => (!basic or it.hasSword(2) or (it.canExtendMagic(3) and it.has(.fire_rod)) or
            (it.has(.bombos) and (swordless or it.hasSword(1)) and it.canExtendMagic(2) and it.has(.fire_rod))) and
            it.canMeltThings() and
            (it.has(.hammer) or it.hasSword(1) or (it.canExtendMagic(3) and it.has(.fire_rod)) or
                (it.canExtendMagic(2) and it.has(.fire_rod) and it.has(.bombos) and swordless)),
        .vitreous => (!basic or it.hasSword(2) or it.canShootArrows(1)) and
            (it.has(.hammer) or it.hasSword(1) or it.canShootArrows(1)),
        .trinexx => it.has(.fire_rod) and it.has(.ice_rod) and
            (!basic or swordless or it.hasSword(3) or (it.canExtendMagic(2) and it.hasSword(2))) and
            (it.hasSword(3) or it.has(.hammer) or (it.canExtendMagic(2) and it.hasSword(2)) or
                (it.canExtendMagic(4) and it.hasSword(1))),
    };
}

pub const World = struct {
    cfg: Config = .{},
    /// What's in each location, once placed.
    placed: [kLocCount]?Item = @splat(null),
    /// Locations already searched by the current sweep (VT's
    /// collected_locations).
    collected: [kLocCount]bool = @splat(false),
    /// Items Link starts with: in Open mode, Zelda's already rescued.
    pre_collected: Items = .{},

    pub fn init(cfg: Config) World {
        var w = World{ .cfg = cfg };
        for (rules.kPreplaced) |pp| w.placed[@backingInt(pp.loc)] = pp.item;
        return w;
    }

    pub fn info(loc: Loc) locs.LocInfo {
        return locs.kLocs[@backingInt(loc)];
    }

    pub fn canEnter(w: *const World, reg: Region, it: *const Items) bool {
        const f = rules.kEnter[@backingInt(reg)] orelse return true;
        return f(w, it);
    }

    pub fn canComplete(w: *const World, reg: Region, it: *const Items) bool {
        const f = rules.kComplete[@backingInt(reg)] orelse return true;
        return f(w, it);
    }

    /// Location.canAccess: its region can be entered, and its own rule's
    /// met.
    pub fn canAccess(w: *const World, loc: Loc, it: *const Items) bool {
        if (!w.canEnter(info(loc).region, it)) return false;
        const f = rules.kReq[@backingInt(loc)] orelse return true;
        return f(w, it);
    }

    pub fn hasItemAt(w: *const World, loc: Loc, item: Item) bool {
        return w.placed[@backingInt(loc)] == item;
    }

    pub fn itemAt(w: *const World, loc: Loc) ?Item {
        return w.placed[@backingInt(loc)];
    }

    /// The lamp, as many as the logic wants.
    pub fn lamp(w: *const World, it: *const Items) bool {
        return it.hasN(.lamp, w.cfg.lamp_required);
    }

    /// Region.canFill: a dungeon's own items only go in that dungeon,
    /// unless they're let loose.
    pub fn regionCanFill(w: *const World, reg: Region, item: Item) bool {
        const loose = switch (items_mod.kind(item)) {
            .key => w.cfg.wild_keys,
            .big_key => w.cfg.wild_big_keys,
            .map => w.cfg.wild_maps,
            .compass => w.cfg.wild_compasses,
            else => return true,
        };
        if (loose) return true;
        for (rules.kRegionItems[@backingInt(reg)]) |ri| {
            if (ri == item) return true;
        }
        return false;
    }

    /// Location.canFill: whether `item` may go in `loc`, with `it` assumed
    /// collected. The rules see the item in place while they're asked, as
    /// VT's do, which is how a key behind its own door is worked out.
    pub fn canFill(w: *World, loc: Loc, item: Item, it: *const Items, check_access: bool) bool {
        const i = @backingInt(loc);
        const old = w.placed[i];
        w.placed[i] = item;
        defer w.placed[i] = old;
        if (rules.kAlways[i]) |a| {
            if (a(w, item, it)) return true;
        }
        if (!w.regionCanFill(info(loc).region, item)) return false;
        if (rules.kFill[i]) |f| {
            if (!f(w, item, it)) return false;
        }
        return !check_access or w.canAccess(loc, it);
    }

    /// Medallions and fountains say how things open, not what's found.
    fn collectable(loc: Loc) bool {
        return switch (info(loc).kind) {
            .medallion, .fountain => false,
            else => true,
        };
    }

    pub fn resetCollected(w: *World) void {
        w.collected = @splat(false);
    }

    /// World.collectItems: `start`, what Link starts with, and everything
    /// more that turns up, sweeping until nothing new does. Locations an
    /// earlier sweep already collected are passed over, items and all, as in
    /// VT; reset first for a fresh look.
    pub fn collectItems(w: *World, start: Items) Items {
        var mine = start;
        mine.merge(&w.pre_collected);
        const more = w.collectOtherItems(&mine);
        mine.merge(&more);
        return mine;
    }

    /// World.collectOtherItems: what more turns up from `have`, not counting
    /// what's already been collected this sweep.
    pub fn collectOtherItems(w: *World, have: *const Items) Items {
        var mine = have.*;
        var found_items = Items{};
        while (true) {
            var batch = Items{};
            var any = false;
            for (0..kLocCount) |i| {
                const loc: Loc = @fromBackingInt(@intCast(i));
                if (w.collected[i] or !collectable(loc)) continue;
                const item = w.placed[i] orelse continue;
                if (!w.canAccess(loc, &mine)) continue;
                w.collected[i] = true;
                batch.add(item);
                any = true;
            }
            if (!any) break;
            mine.merge(&batch);
            found_items.merge(&batch);
        }
        return found_items;
    }

    pub fn collectedCount(w: *const World) usize {
        var n: usize = 0;
        for (w.collected) |b| n += @intFromBool(b);
        return n;
    }

    /// World.checkWinCondition, for the goal Ganon: the Triforce in hand
    /// once everything reachable from `have` is.
    pub fn won(w: *World, have: Items) bool {
        const got = w.collectItems(have);
        return got.has(.triforce);
    }
};
