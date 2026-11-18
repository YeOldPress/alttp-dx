//! Desert Palace: a port of VT's app/Region/Standard/DesertPalace.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .desert_palace,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_p2, .compass_p2, .key_p2, .map_p2 },
    .rules = &.{
        .{ .loc = .desert_palace_big_chest, .req = bigChest },
        .{ .loc = .desert_palace_big_key_chest, .req = bigKeyChest },
        .{ .loc = .desert_palace_compass_chest, .req = compassChest },
        .{ .loc = .desert_palace_torch, .req = torch },
        .{ .loc = .desert_palace_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .desert_palace_prize, .req = complete },
    },
};

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.big_key_p2);
}

fn bigKeyChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.key_p2) and it.canKillMostThings(5);
}

fn compassChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.key_p2);
}

fn torch(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.pegasus_boots);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.desert_palace_boss, it);
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return enter(w, it) and
        (it.canLiftRocks() or (it.has(.magic_mirror) and w.canEnter(.mire, it))) and
        it.canLightTorches() and
        it.has(.big_key_p2) and it.has(.key_p2) and
        r.canBeat(.lanmolas, w, it) and
        (!w.cfg.wild_compasses or it.has(.compass_p2) or w.hasItemAt(.desert_palace_boss, .compass_p2)) and
        (!w.cfg.wild_maps or it.has(.map_p2) or w.hasItemAt(.desert_palace_boss, .map_p2));
}

fn bossFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    if (!w.cfg.boss_normal_location) switch (r.itemKind(item)) {
        .key, .big_key, .map, .compass => return false,
        else => {},
    };
    return item != .key_p2 and item != .big_key_p2;
}

fn bossAlways(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.boss_normal_location and (item == .compass_p2 or item == .map_p2);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return it.has(.rescue_zelda) and
        (it.has(.book_of_mudora) or (it.has(.magic_mirror) and w.canEnter(.mire, it)));
}
