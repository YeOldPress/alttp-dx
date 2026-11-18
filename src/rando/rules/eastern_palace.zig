//! Eastern Palace's rules: a port of VT's app/Region/Standard/EasternPalace.php
//! (MIT).
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .eastern_palace,
    .enter = enter,
    .complete = complete,
    // VT also lists KeyP1, which items.zig has no Item for.
    .region_items = &.{ .big_key_p1, .compass_p1, .map_p1 },
    .rules = &.{
        .{ .loc = .eastern_palace_big_chest, .req = bigChest },
        .{ .loc = .eastern_palace_big_key_chest, .req = bigKeyChest },
        .{ .loc = .eastern_palace_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .eastern_palace_prize, .req = complete },
    },
};

fn enter(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.rescue_zelda);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.eastern_palace_boss, it);
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.big_key_p1);
}

fn bigKeyChest(w: *const r.World, it: *const r.Items) bool {
    return w.lamp(it);
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    return it.canShootArrows(1) and
        (w.lamp(it) or (w.cfg.item_placement == .advanced and it.has(.fire_rod))) and
        it.has(.big_key_p1) and
        r.canBeat(.armos_knights, w, it) and
        (!w.cfg.wild_compasses or it.has(.compass_p1) or w.hasItemAt(.eastern_palace_boss, .compass_p1)) and
        (!w.cfg.wild_maps or it.has(.map_p1) or w.hasItemAt(.eastern_palace_boss, .map_p1));
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
    return w.cfg.boss_normal_location and (item == .compass_p1 or item == .map_p1);
}
