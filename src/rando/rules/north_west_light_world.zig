//! North West Light World: a port of VT's
//! app/Region/Standard/LightWorld/NorthWest.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT). Its shops are left out.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .north_west_light_world,
    .enter = enter,
    .rules = &.{
        .{ .loc = .master_sword_pedestal, .req = masterSwordPedestal },
        .{ .loc = .kings_tomb, .req = kingsTomb },
        .{ .loc = .pegasus_rocks, .req = pegasusRocks },
        .{ .loc = .magic_bat, .req = magicBat },
        .{ .loc = .sick_kid, .req = sickKid },
        .{ .loc = .lumberjack_tree, .req = lumberjackTree },
        .{ .loc = .graveyard_ledge, .req = graveyardLedge },
    },
};

fn masterSwordPedestal(w: *const r.World, it: *const r.Items) bool {
    return (w.cfg.item_placement != .basic or it.has(.book_of_mudora)) and
        it.has(.pendant_of_power) and
        it.has(.pendant_of_wisdom) and
        it.has(.pendant_of_courage);
}

fn kingsTomb(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return it.has(.pegasus_boots) and
        (it.canLiftDarkRocks() or
            (it.has(.magic_mirror) and w.canEnter(.north_west_dark_world, it) and it.has(.moon_pearl)));
}

fn pegasusRocks(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.pegasus_boots);
}

fn magicBat(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return it.has(.powder) and
        (it.has(.hammer) or
            (it.has(.magic_mirror) and it.has(.moon_pearl) and
                it.canLiftDarkRocks() and w.canEnter(.north_west_dark_world, it)));
}

fn sickKid(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.hasABottle();
}

fn lumberjackTree(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.defeat_agahnim) and it.has(.pegasus_boots);
}

fn graveyardLedge(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return it.has(.magic_mirror) and w.canEnter(.north_west_dark_world, it) and it.has(.moon_pearl);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.rescue_zelda);
}
