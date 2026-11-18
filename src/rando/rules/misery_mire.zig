//! Misery Mire: a port of VT's app/Region/Standard/MiseryMire.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

// VT's glitched routes are left out throughout: no glitches.

/// VT's region.cantTakeDamage, off unless a preset turns it on; Config
/// doesn't carry it.
const cant_take_damage = false;

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.has(.rescue_zelda) and
        (w.cfg.item_placement != .basic or
            ((w.cfg.swordless() or it.hasSword(2)) and it.hasHealth(12) and
                (it.hasBottle(2) or it.hasArmor(1)))) and
        (((w.hasItemAt(.misery_mire_medallion, .bombos) and it.has(.bombos)) or
            (w.hasItemAt(.misery_mire_medallion, .ether) and it.has(.ether)) or
            (w.hasItemAt(.misery_mire_medallion, .quake) and it.has(.quake))) and
            (w.cfg.swordless() or it.hasSword(1))) and
        it.has(.moon_pearl) and
        ((w.cfg.item_placement != .basic and it.has(.pegasus_boots)) or it.has(.hookshot)) and
        it.canKillMostThings(8) and
        w.canEnter(.mire, it);
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.misery_mire_boss, it);
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.big_key_d6);
}

fn spikeChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return !cant_take_damage or it.has(.cane_of_byrna) or it.has(.cape);
}

fn keyOrBigKey(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.key_d6) or it.has(.big_key_d6);
}

fn bigKeyChest(w: *const r.World, it: *const r.Items) bool {
    return it.canLightTorches() and
        (((w.hasItemAt(.misery_mire_compass_chest, .big_key_d6) or
            w.hasItemAt(.misery_mire_big_key_chest, .big_key_d6)) and it.hasN(.key_d6, 2)) or
            it.hasN(.key_d6, 3));
}

fn compassChest(w: *const r.World, it: *const r.Items) bool {
    return it.canLightTorches() and
        (((w.hasItemAt(.misery_mire_big_key_chest, .big_key_d6) or
            w.hasItemAt(.misery_mire_compass_chest, .big_key_d6)) and it.hasN(.key_d6, 2)) or
            it.hasN(.key_d6, 3));
}

fn boss(w: *const r.World, it: *const r.Items) bool {
    return enter(w, it) and
        it.has(.cane_of_somaria) and w.lamp(it) and
        it.has(.big_key_d6) and
        r.canBeat(.vitreous, w, it) and
        (!w.cfg.wild_compasses or it.has(.compass_d6) or w.hasItemAt(.misery_mire_boss, .compass_d6)) and
        (!w.cfg.wild_maps or it.has(.map_d6) or w.hasItemAt(.misery_mire_boss, .map_d6));
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
    return w.cfg.boss_normal_location and (item == .compass_d6 or item == .map_d6);
}

pub const region = r.RegionRules{
    .region = .misery_mire,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_d6, .compass_d6, .key_d6, .map_d6 },
    .rules = &.{
        .{ .loc = .misery_mire_big_chest, .req = bigChest },
        .{ .loc = .misery_mire_spike_chest, .req = spikeChest },
        .{ .loc = .misery_mire_main_lobby, .req = keyOrBigKey },
        .{ .loc = .misery_mire_map_chest, .req = keyOrBigKey },
        .{ .loc = .misery_mire_big_key_chest, .req = bigKeyChest },
        .{ .loc = .misery_mire_compass_chest, .req = compassChest },
        .{ .loc = .misery_mire_boss, .req = boss, .fill = bossFill, .always = bossAlways },
        .{ .loc = .misery_mire_prize, .req = complete },
    },
};
