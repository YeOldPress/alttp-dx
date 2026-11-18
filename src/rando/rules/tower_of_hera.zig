//! Tower of Hera: a port of VT's app/Region/Standard/TowerOfHera.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

// VT's glitched routes are left out throughout: no glitches. That takes
// the Misery Mire clip ($mire) with it, which is all glitch.

/// The way up: VT's $main.
fn main(w: *const r.World, it: *const r.Items) bool {
    return (it.has(.magic_mirror) or (it.has(.hookshot) and it.has(.hammer))) and
        w.canEnter(.west_death_mountain, it);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.has(.rescue_zelda) and main(w, it);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.tower_of_hera_boss, it);
}

fn bigKeyChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.canLightTorches() and it.has(.key_p3);
}

fn bigKeyChestAlways(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations and item == .key_p3;
}

fn bigKeyChestFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations or item != .key_p3;
}

fn compassChest(w: *const r.World, it: *const r.Items) bool {
    return main(w, it) and it.has(.big_key_p3);
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    return main(w, it) and it.has(.big_key_p3);
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    return main(w, it) and
        r.canBeat(.moldorm, w, it) and
        it.has(.big_key_p3) and
        (!w.cfg.wild_compasses or it.has(.compass_p3) or w.hasItemAt(.tower_of_hera_boss, .compass_p3)) and
        (!w.cfg.wild_maps or it.has(.map_p3) or w.hasItemAt(.tower_of_hera_boss, .map_p3));
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
    return w.cfg.boss_normal_location and (item == .compass_p3 or item == .map_p3);
}

pub const region = r.RegionRules{
    .region = .tower_of_hera,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_p3, .compass_p3, .key_p3, .map_p3 },
    .rules = &.{
        .{ .loc = .tower_of_hera_big_key_chest, .req = bigKeyChest, .fill = bigKeyChestFill, .always = bigKeyChestAlways },
        .{ .loc = .tower_of_hera_compass_chest, .req = compassChest },
        .{ .loc = .tower_of_hera_big_chest, .req = bigChest },
        .{ .loc = .tower_of_hera_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .tower_of_hera_prize, .req = complete },
    },
};
