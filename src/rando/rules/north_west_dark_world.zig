//! North West Dark World: a port of VT's app/Region/Standard/DarkWorld/
//! NorthWest.php (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

// VT's glitched routes are left out throughout: no glitches.

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.has(.rescue_zelda) and
        it.has(.moon_pearl) and
        ((w.canEnter(.north_east_dark_world, it) and
            (it.has(.hookshot) and
                (it.canLiftRocks() or it.has(.hammer) or it.has(.flippers)))) or
            (it.has(.hammer) and it.canLiftRocks()) or
            it.canLiftDarkRocks());
}

fn brewery(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.canBombThings() and it.has(.moon_pearl);
}

fn moonPearl(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.moon_pearl);
}

fn hammerPegs(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.hammer) and it.has(.moon_pearl) and it.canLiftDarkRocks();
}

fn bumperCave(w: *const r.World, it: *const r.Items) bool {
    return it.has(.moon_pearl) and
        ((w.cfg.item_placement != .basic or it.has(.hookshot)) and
            it.canLiftRocks() and it.has(.cape));
}

fn blacksmith(w: *const r.World, it: *const r.Items) bool {
    return (w.cfg.item_placement != .basic or it.has(.magic_mirror)) and
        (it.has(.moon_pearl) and it.canLiftDarkRocks());
}

fn purpleChest(w: *const r.World, it: *const r.Items) bool {
    return w.canAccess(.blacksmith, it) and
        (it.has(.moon_pearl) and it.canLiftDarkRocks());
}

pub const region = r.RegionRules{
    .region = .north_west_dark_world,
    .enter = enter,
    .rules = &.{
        .{ .loc = .brewery, .req = brewery },
        .{ .loc = .c_shaped_house, .req = moonPearl },
        .{ .loc = .chest_game, .req = moonPearl },
        .{ .loc = .hammer_pegs, .req = hammerPegs },
        .{ .loc = .bumper_cave, .req = bumperCave },
        .{ .loc = .blacksmith, .req = blacksmith },
        .{ .loc = .purple_chest, .req = purpleChest },
    },
};
