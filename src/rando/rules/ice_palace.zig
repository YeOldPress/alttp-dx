//! Ice Palace: a port of VT's app/Region/Standard/IcePalace.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .ice_palace,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_d5, .compass_d5, .key_d5, .map_d5 },
    .rules = &.{
        .{ .loc = .ice_palace_big_key_chest, .req = pastSpikeRoom },
        .{ .loc = .ice_palace_map_chest, .req = pastSpikeRoom },
        .{ .loc = .ice_palace_spike_room, .req = spikeRoom },
        .{ .loc = .ice_palace_freezor_chest, .req = freezorChest },
        .{ .loc = .ice_palace_big_chest, .req = bigChest },
        .{ .loc = .ice_palace_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .ice_palace_prize, .req = complete },
    },
};

// VT's region.cantTakeDamage is off (its default), so the Cane of Byrna,
// Cape or Hookshot it would want for the spikes is never needed.

/// The Big Key Chest and the Map Chest.
fn pastSpikeRoom(w: *const r.World, it: *const r.Items) bool {
    return it.has(.hammer) and it.canLiftRocks() and w.canAccess(.ice_palace_spike_room, it);
}

fn spikeRoom(w: *const r.World, it: *const r.Items) bool {
    // VT also lets a ShopKey (retro mode's shop keys) through; there are
    // none here.
    return it.has(.hookshot) or
        (it.hasN(.key_d5, 1) and
            (w.hasItemAt(.ice_palace_spike_room, .big_key_d5) or
                w.hasItemAt(.ice_palace_big_key_chest, .big_key_d5) or
                w.hasItemAt(.ice_palace_map_chest, .big_key_d5)));
}

fn freezorChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.canMeltThings();
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.big_key_d5);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.ice_palace_boss, it);
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    const basic = w.cfg.item_placement == .basic;
    return enter(w, it) and
        it.has(.hammer) and it.canLiftRocks() and
        r.canBeat(.kholdstare, w, it) and
        it.has(.big_key_d5) and
        ((!basic and ((it.has(.cane_of_somaria) and it.has(.key_d5)) or it.hasN(.key_d5, 2))) or
            (basic and it.hasN(.key_d5, 2))) and
        (!w.cfg.wild_compasses or it.has(.compass_d5) or w.hasItemAt(.ice_palace_boss, .compass_d5)) and
        (!w.cfg.wild_maps or it.has(.map_d5) or w.hasItemAt(.ice_palace_boss, .map_d5));
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
    return w.cfg.boss_normal_location and (item == .compass_d5 or item == .map_d5);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches. (Its whole South Dark
    // World route needs a mirror wrap, a transition wrap or a clip.)
    return it.has(.rescue_zelda) and
        (w.cfg.item_placement != .basic or
            ((w.cfg.swordless() or it.hasSword(2)) and it.hasHealth(12) and
                (it.hasBottle(2) or it.hasArmor(1)))) and
        it.canMeltThings() and
        it.has(.moon_pearl) and it.has(.flippers) and it.canLiftDarkRocks();
}
