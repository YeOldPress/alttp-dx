//! Turtle Rock: a port of the VT randomizer's
//! app/Region/Standard/TurtleRock.php (github.com/sporchia/alttp_vt_randomizer, MIT).
//! VT's `$middle` and `$lower` ways in both need glitches (mirror clips,
//! boots clips, mirror wraps), so only `$upper`, the front door, is left:
//! every `|| $middle(...)` and `|| ($lower(...) && ...)` is dropped below.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .turtle_rock,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_d7, .compass_d7, .key_d7, .map_d7 },
    .rules = &.{
        .{ .loc = .turtle_rock_chain_chomps, .req = chainChomps },
        .{ .loc = .turtle_rock_roller_room_left, .req = rollerRoom },
        .{ .loc = .turtle_rock_roller_room_right, .req = rollerRoom },
        .{ .loc = .turtle_rock_compass_chest, .req = compassChest },
        .{ .loc = .turtle_rock_big_chest, .req = bigChest, .fill = notBigKey },
        .{ .loc = .turtle_rock_big_key_chest, .req = bigKeyChest, .always = keyIfThree, .fill = keyOnlyIfNotLocations },
        .{ .loc = .turtle_rock_crystaroller_room, .req = crystaroller },
        .{ .loc = .turtle_rock_eye_bridge_bottom_left, .req = eyeBridge },
        .{ .loc = .turtle_rock_eye_bridge_bottom_right, .req = eyeBridge },
        .{ .loc = .turtle_rock_eye_bridge_top_left, .req = eyeBridge },
        .{ .loc = .turtle_rock_eye_bridge_top_right, .req = eyeBridge },
        .{ .loc = .turtle_rock_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .turtle_rock_prize, .req = complete },
    },
};

/// VT's `$upper`: the medallion, a sword to wave it, and up past the dark
/// rocks on East Death Mountain with the hammer.
fn upper(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return ((w.hasItemAt(.turtle_rock_medallion, .bombos) and it.has(.bombos)) or
        (w.hasItemAt(.turtle_rock_medallion, .ether) and it.has(.ether)) or
        (w.hasItemAt(.turtle_rock_medallion, .quake) and it.has(.quake))) and
        (w.cfg.swordless() or it.hasSword(1)) and
        it.has(.moon_pearl) and
        it.has(.cane_of_somaria) and
        it.has(.hammer) and it.canLiftDarkRocks() and w.canEnter(.east_death_mountain, it);
}

fn chainChomps(w: *const r.World, it: *const r.Items) bool {
    return upper(w, it) and it.has(.key_d7);
}

fn rollerRoom(w: *const r.World, it: *const r.Items) bool {
    return it.has(.fire_rod) and it.has(.cane_of_somaria) and upper(w, it);
}

fn compassChest(w: *const r.World, it: *const r.Items) bool {
    return it.has(.cane_of_somaria) and upper(w, it);
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    return it.has(.big_key_d7) and upper(w, it) and it.hasN(.key_d7, 2);
}

fn notBigKey(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = w;
    _ = it;
    return item != .big_key_d7;
}

fn bigKeyChest(w: *const r.World, it: *const r.Items) bool {
    if (!w.hasItemAt(.turtle_rock_big_key_chest, .big_key_d7) and w.cfg.wild_keys) {
        return if (w.hasItemAt(.turtle_rock_big_key_chest, .key_d7)) it.hasN(.key_d7, 3) else it.hasN(.key_d7, 4);
    }
    return it.hasN(.key_d7, 2);
}

fn keyIfThree(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    return w.cfg.accessibility != .locations and item == .key_d7 and it.hasN(.key_d7, 3);
}

fn keyOnlyIfNotLocations(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations or item != .key_d7;
}

fn crystaroller(w: *const r.World, it: *const r.Items) bool {
    return it.has(.big_key_d7) and upper(w, it) and it.hasN(.key_d7, 2);
}

fn eyeBridge(w: *const r.World, it: *const r.Items) bool {
    // VT also asks `config('item.overflow.count.Shield', 3) >= 3` before
    // canBlockLasers; at its default of 3 that always holds.
    return upper(w, it) and
        w.lamp(it) and it.has(.cane_of_somaria) and it.has(.big_key_d7) and it.hasN(.key_d7, 3) and
        (w.cfg.item_placement != .basic or it.has(.cape) or it.has(.cane_of_byrna) or it.canBlockLasers());
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return enter(w, it) and
        it.hasN(.key_d7, 4) and
        w.lamp(it) and
        it.has(.big_key_d7) and it.has(.cane_of_somaria) and
        r.canBeat(.trinexx, w, it) and
        (!w.cfg.wild_compasses or it.has(.compass_d7) or w.hasItemAt(.turtle_rock_boss, .compass_d7)) and
        (!w.cfg.wild_maps or it.has(.map_d7) or w.hasItemAt(.turtle_rock_boss, .map_d7));
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
    return w.cfg.boss_normal_location and (item == .compass_d7 or item == .map_d7);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.turtle_rock_boss, it);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.has(.rescue_zelda) and
        (w.cfg.item_placement != .basic or
            ((w.cfg.swordless() or it.hasSword(2)) and it.hasHealth(12) and (it.hasBottle(2) or it.hasArmor(1)))) and
        upper(w, it);
}
