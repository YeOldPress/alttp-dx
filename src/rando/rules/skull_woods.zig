//! Skull Woods: a port of VT's app/Region/Standard/SkullWoods.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

// VT's glitched routes are left out throughout: no glitches.

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.has(.rescue_zelda) and
        (w.cfg.item_placement != .basic or
            ((w.cfg.swordless() or it.hasSword(1)) and it.hasHealth(7) and it.hasABottle())) and
        it.has(.moon_pearl) and
        w.canEnter(.north_west_dark_world, it);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.skull_woods_boss, it);
}

/// VT's region.forceSkullWoodsKey, which its World turns on for basic
/// placement: the Pinball Room holds a key then.
fn pinballRoomFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    const force_skull_woods_key = w.cfg.item_placement == .basic;
    return !force_skull_woods_key or item == .key_d3;
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.big_key_d3);
}

fn bigChestAlways(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations and item == .big_key_d3;
}

fn bigChestFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations or item != .big_key_d3;
}

fn bridgeRoom(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.fire_rod) and it.has(.moon_pearl);
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    return enter(w, it) and
        it.has(.fire_rod) and it.has(.moon_pearl) and
        (w.cfg.swordless() or it.hasSword(1)) and
        it.hasN(.key_d3, 3) and
        r.canBeat(.mothula, w, it) and
        (!w.cfg.wild_compasses or it.has(.compass_d3) or w.hasItemAt(.skull_woods_boss, .compass_d3)) and
        (!w.cfg.wild_maps or it.has(.map_d3) or w.hasItemAt(.skull_woods_boss, .map_d3));
}

fn bossFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    if (!w.cfg.boss_normal_location) {
        switch (r.itemKind(item)) {
            .key, .big_key, .map, .compass => return false,
            else => {},
        }
    }
    return true;
}

fn bossAlways(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.boss_normal_location and (item == .compass_d3 or item == .map_d3);
}

pub const region = r.RegionRules{
    .region = .skull_woods,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_d3, .compass_d3, .key_d3, .map_d3 },
    .rules = &.{
        .{ .loc = .skull_woods_pinball_room, .fill = pinballRoomFill },
        .{ .loc = .skull_woods_big_chest, .req = bigChest, .fill = bigChestFill, .always = bigChestAlways },
        .{ .loc = .skull_woods_bridge_room, .req = bridgeRoom },
        .{ .loc = .skull_woods_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .skull_woods_prize, .req = complete },
    },
};
