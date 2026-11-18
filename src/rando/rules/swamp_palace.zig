//! Swamp Palace: a port of the VT randomizer's
//! app/Region/Standard/SwampPalace.php (github.com/sporchia/alttp_vt_randomizer, MIT).
//! VT's `$mire` and `$hera` routes both need canOneFrameClipUW, so they're
//! left out here: no glitches.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .swamp_palace,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_d2, .compass_d2, .key_d2, .map_d2 },
    .rules = &.{
        .{ .loc = .swamp_palace_entrance, .fill = entranceFill },
        .{ .loc = .swamp_palace_big_chest, .req = bigChest, .always = bigKeyIfNotLocations, .fill = bigKeyOnlyIfNotLocations },
        .{ .loc = .swamp_palace_big_key_chest, .req = keyAndHammer },
        .{ .loc = .swamp_palace_map_chest, .req = mapChest },
        .{ .loc = .swamp_palace_west_chest, .req = keyAndHammer },
        .{ .loc = .swamp_palace_compass_chest, .req = keyAndHammer },
        .{ .loc = .swamp_palace_flooded_room_left, .req = pastTheFlood },
        .{ .loc = .swamp_palace_flooded_room_right, .req = pastTheFlood },
        .{ .loc = .swamp_palace_waterfall_room, .req = pastTheFlood },
        .{ .loc = .swamp_palace_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .swamp_palace_prize, .req = complete },
    },
};

fn entranceFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    // VT's glitched routes are left out: no glitches.
    return w.cfg.wild_keys or item == .key_d2;
}

fn keyAndHammer(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.key_d2) and it.has(.hammer);
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    return keyAndHammer(w, it) and it.has(.big_key_d2);
}

fn bigKeyIfNotLocations(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations and item == .big_key_d2;
}

fn bigKeyOnlyIfNotLocations(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations or item != .big_key_d2;
}

fn mapChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.canBombThings() and it.has(.key_d2);
}

fn pastTheFlood(w: *const r.World, it: *const r.Items) bool {
    return it.has(.hookshot) and keyAndHammer(w, it);
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    return pastTheFlood(w, it) and
        r.canBeat(.arrghus, w, it) and
        (!w.cfg.wild_compasses or it.has(.compass_d2) or w.hasItemAt(.swamp_palace_boss, .compass_d2)) and
        (!w.cfg.wild_maps or it.has(.map_d2) or w.hasItemAt(.swamp_palace_boss, .map_d2));
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
    return w.cfg.boss_normal_location and (item == .compass_d2 or item == .map_d2);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.swamp_palace_boss, it);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return it.has(.rescue_zelda) and
        (w.cfg.item_placement != .basic or
            ((w.cfg.swordless() or it.hasSword(1)) and it.hasHealth(7) and it.hasABottle())) and
        it.has(.flippers) and
        w.canEnter(.south_dark_world, it) and
        it.has(.moon_pearl) and it.has(.magic_mirror);
}
