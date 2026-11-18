//! Thieves' Town: a port of VT's app/Region/Standard/ThievesTown.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .thieves_town,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_d4, .compass_d4, .key_d4, .map_d4 },
    .rules = &.{
        .{ .loc = .thieves_town_attic, .req = attic },
        .{ .loc = .thieves_town_big_chest, .req = bigChest, .fill = bigChestFill, .always = bigChestAlways },
        .{ .loc = .thieves_town_blinds_cell, .req = blindsCell },
        .{ .loc = .thieves_town_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .thieves_town_prize, .req = complete },
    },
};

fn attic(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.key_d4) and it.has(.big_key_d4);
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    if (w.hasItemAt(.thieves_town_big_chest, .key_d4)) {
        return it.has(.hammer) and it.has(.big_key_d4);
    }
    return it.has(.hammer) and it.has(.key_d4) and it.has(.big_key_d4);
}

fn bigChestAlways(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    return w.cfg.accessibility != .locations and item == .key_d4 and it.has(.hammer);
}

fn bigChestFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations or item != .key_d4;
}

fn blindsCell(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.big_key_d4);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.thieves_town_boss, it);
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    return enter(w, it) and
        it.has(.key_d4) and it.has(.big_key_d4) and
        r.canBeat(.blind, w, it) and
        (!w.cfg.wild_compasses or it.has(.compass_d4) or w.hasItemAt(.thieves_town_boss, .compass_d4)) and
        (!w.cfg.wild_maps or it.has(.map_d4) or w.hasItemAt(.thieves_town_boss, .map_d4));
}

fn bossFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    if (!w.cfg.boss_normal_location) switch (r.itemKind(item)) {
        .key, .big_key, .map, .compass => return false,
        else => {},
    };
    return true;
}

fn bossAlways(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.boss_normal_location and (item == .compass_d4 or item == .map_d4);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return it.has(.rescue_zelda) and
        (w.cfg.item_placement != .basic or
            ((w.cfg.swordless() or it.hasSword(1)) and it.hasHealth(7) and it.hasABottle())) and
        it.has(.moon_pearl) and
        w.canEnter(.north_west_dark_world, it);
}
