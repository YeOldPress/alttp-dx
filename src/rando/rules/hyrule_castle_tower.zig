//! Hyrule Castle Tower: a port of VT's app/Region/Standard/
//! HyruleCastleTower.php (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.canKillMostThings(8) and
        it.has(.rescue_zelda) and
        (it.has(.cape) or
            it.hasSword(2) or
            (w.cfg.swordless() and it.has(.hammer)));
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return enter(w, it) and it.hasN(.key_a1, 2) and
        w.lamp(it) and (it.hasSword(1) or
        (w.cfg.swordless() and (it.has(.hammer) or it.has(.bug_catching_net))));
}

fn darkMaze(w: *const r.World, it: *const r.Items) bool {
    return w.lamp(it) and it.has(.key_a1);
}

pub const region = r.RegionRules{
    .region = .hyrule_castle_tower,
    .enter = enter,
    .complete = complete,
    // VT's BigKeyA1, MapA1 and CompassA1 aren't in the item pool, nor in
    // Item; the key's the only one there is.
    .region_items = &.{.key_a1},
    .rules = &.{
        .{ .loc = .castle_tower_dark_maze, .req = darkMaze },
        .{ .loc = .agahnim, .req = complete },
    },
    .preplaced = &.{
        .{ .loc = .agahnim, .item = .defeat_agahnim },
    },
};
