//! North East Dark World: a port of VT's app/Region/Standard/DarkWorld/
//! NorthEast.php (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

// VT's glitched routes are left out throughout: no glitches.

fn enter(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.rescue_zelda) and
        (it.has(.defeat_agahnim) or
            (it.has(.hammer) and it.canLiftRocks() and it.has(.moon_pearl)) or
            (it.canLiftDarkRocks() and it.has(.moon_pearl) and
                (it.has(.hammer) or it.has(.flippers))));
}

fn catfish(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.moon_pearl) and it.canLiftRocks();
}

/// Into the Pyramid Fairy's cave: both crystals, and the cracked wall.
fn pyramidFairy(w: *const r.World, it: *const r.Items) bool {
    return it.has(.crystal5) and it.has(.crystal6) and
        w.canEnter(.south_dark_world, it) and
        ((it.has(.moon_pearl) and it.has(.hammer)) or
            (it.has(.magic_mirror) and it.has(.defeat_agahnim)));
}

fn pyramidFairySword(w: *const r.World, it: *const r.Items) bool {
    return it.hasSword(1) and pyramidFairy(w, it);
}

fn pyramidFairyBow(w: *const r.World, it: *const r.Items) bool {
    return it.canShootArrows(1) and pyramidFairy(w, it);
}

/// VT's goal is 'ganon' here: the Ganon crystals, and Agahnim's second
/// round, are wanted.
fn ganon(w: *const r.World, it: *const r.Items) bool {
    if (it.crystalCount() < w.cfg.crystals_ganon) return false;

    // As VT's World sets them: basic placement wants the better bow and
    // sword, and swordless wants the silvers.
    const require_better_bow = w.cfg.item_placement == .basic or w.cfg.swordless();
    const require_better_sword = w.cfg.item_placement == .basic;
    return it.has(.moon_pearl) and
        it.has(.defeat_agahnim2) and
        (!require_better_bow or it.canShootArrows(2)) and
        ((w.cfg.swordless() and it.has(.hammer) and
            (w.lamp(it) or (it.has(.fire_rod) and it.canExtendMagic(1)))) or
            (!require_better_sword and (it.hasSword(2) and
                (w.lamp(it) or (it.has(.fire_rod) and it.canExtendMagic(3))))) or
            (it.hasSword(3) and (w.lamp(it) or (it.has(.fire_rod) and it.canExtendMagic(2)))));
}

pub const region = r.RegionRules{
    .region = .north_east_dark_world,
    .enter = enter,
    .rules = &.{
        .{ .loc = .catfish, .req = catfish },
        .{ .loc = .pyramid_fairy_sword, .req = pyramidFairySword },
        .{ .loc = .pyramid_fairy_bow, .req = pyramidFairyBow },
        .{ .loc = .pyramid_fairy_left, .req = pyramidFairy },
        .{ .loc = .pyramid_fairy_right, .req = pyramidFairy },
        .{ .loc = .ganon, .req = ganon },
    },
    .preplaced = &.{
        .{ .loc = .pyramid_fairy_sword, .item = .l1_sword },
        .{ .loc = .pyramid_fairy_bow, .item = .bow },
        .{ .loc = .ganon, .item = .defeat_ganon },
    },
};
