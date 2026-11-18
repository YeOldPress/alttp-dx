//! Palace of Darkness: a port of the VT randomizer's
//! app/Region/Standard/PalaceOfDarkness.php (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .palace_of_darkness,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_d1, .compass_d1, .key_d1, .map_d1 },
    .rules = &.{
        .{ .loc = .palace_of_darkness_the_arena_ledge, .req = arrows },
        .{ .loc = .palace_of_darkness_big_key_chest, .req = bigKeyChest, .always = keyIfFive, .fill = keyOnlyIfNotLocations },
        .{ .loc = .palace_of_darkness_the_arena_bridge, .req = keyOrArrowsAndHammer },
        .{ .loc = .palace_of_darkness_big_chest, .req = bigChest, .fill = notKey },
        .{ .loc = .palace_of_darkness_compass_chest, .req = compassChest },
        .{ .loc = .palace_of_darkness_harmless_hellway, .req = harmlessHellway, .always = keyIfFive, .fill = keyOnlyIfNotLocations },
        .{ .loc = .palace_of_darkness_stalfos_basement, .req = keyOrArrowsAndHammer },
        .{ .loc = .palace_of_darkness_dark_basement_left, .req = darkBasement },
        .{ .loc = .palace_of_darkness_dark_basement_right, .req = darkBasement },
        .{ .loc = .palace_of_darkness_map_chest, .req = arrows },
        .{ .loc = .palace_of_darkness_dark_maze_top, .req = darkMaze, .fill = notKey },
        .{ .loc = .palace_of_darkness_dark_maze_bottom, .req = darkMaze, .fill = notKey },
        .{ .loc = .palace_of_darkness_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .palace_of_darkness_prize, .req = complete },
    },
};

/// VT's `(($items->has('Hammer') && canShootArrows [&& Lamp]) || wildKeys)
/// ? has('KeyD1', more) : has('KeyD1', fewer)`: with the hammer and bow in
/// hand the keys may go elsewhere first, so one more is wanted.
fn keysFor(w: *const r.World, it: *const r.Items, comptime with_lamp: bool, more: u8, fewer: u8) bool {
    const elsewhere = it.has(.hammer) and it.canShootArrows(1) and (!with_lamp or w.lamp(it));
    return if (elsewhere or w.cfg.wild_keys) it.hasN(.key_d1, more) else it.hasN(.key_d1, fewer);
}

fn arrows(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.canShootArrows(1);
}

fn bigKeyChest(w: *const r.World, it: *const r.Items) bool {
    if (w.hasItemAt(.palace_of_darkness_big_key_chest, .key_d1)) return it.has(.key_d1);
    return keysFor(w, it, true, 6, 5);
}

fn keyIfFive(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    return w.cfg.accessibility != .locations and item == .key_d1 and it.hasN(.key_d1, 5);
}

fn keyOnlyIfNotLocations(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations or item != .key_d1;
}

fn keyOrArrowsAndHammer(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.key_d1) or (it.canShootArrows(1) and it.has(.hammer));
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    return w.lamp(it) and it.has(.big_key_d1) and keysFor(w, it, false, 6, 5);
}

fn notKey(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = w;
    _ = it;
    return item != .key_d1;
}

fn compassChest(w: *const r.World, it: *const r.Items) bool {
    return keysFor(w, it, true, 4, 3);
}

fn harmlessHellway(w: *const r.World, it: *const r.Items) bool {
    if (w.hasItemAt(.palace_of_darkness_harmless_hellway, .key_d1)) return keysFor(w, it, true, 4, 3);
    return keysFor(w, it, true, 6, 5);
}

fn darkBasement(w: *const r.World, it: *const r.Items) bool {
    return (w.lamp(it) or (w.cfg.item_placement == .advanced and it.has(.fire_rod))) and
        keysFor(w, it, true, 4, 3);
}

fn darkMaze(w: *const r.World, it: *const r.Items) bool {
    return w.lamp(it) and keysFor(w, it, false, 6, 5);
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    return enter(w, it) and
        r.canBeat(.helmasaur_king, w, it) and
        it.has(.hammer) and w.lamp(it) and it.canShootArrows(1) and
        it.has(.big_key_d1) and it.hasN(.key_d1, 6) and
        (!w.cfg.wild_compasses or it.has(.compass_d1) or w.hasItemAt(.palace_of_darkness_boss, .compass_d1)) and
        (!w.cfg.wild_maps or it.has(.map_d1) or w.hasItemAt(.palace_of_darkness_boss, .map_d1));
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
    return w.cfg.boss_normal_location and (item == .compass_d1 or item == .map_d1);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.palace_of_darkness_boss, it);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return it.has(.rescue_zelda) and
        (w.cfg.item_placement != .basic or
            ((w.cfg.swordless() or it.hasSword(1)) and it.hasHealth(7) and it.hasABottle())) and
        it.has(.moon_pearl) and w.canEnter(.north_east_dark_world, it);
}
