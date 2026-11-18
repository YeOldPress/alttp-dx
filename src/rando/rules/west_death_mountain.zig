//! West Death Mountain's rules: a port of VT's
//! app/Region/Standard/LightWorld/DeathMountain/West.php (MIT).
// VT's glitched routes are left out throughout: no glitches.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .west_death_mountain,
    .enter = enter,
    .rules = &.{
        .{ .loc = .old_man, .req = oldMan },
        .{ .loc = .ether_tablet, .req = etherTablet },
        .{ .loc = .spectacle_rock, .req = spectacleRock },
    },
};

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.has(.rescue_zelda) and
        (it.canFly() or (it.canLiftRocks() and w.lamp(it)));
}

fn oldMan(w: *const r.World, it: *const r.Items) bool {
    return w.lamp(it);
}

fn etherTablet(w: *const r.World, it: *const r.Items) bool {
    return it.has(.book_of_mudora) and
        (it.hasSword(2) or (w.cfg.swordless() and it.has(.hammer))) and
        w.canEnter(.tower_of_hera, it);
}

fn spectacleRock(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.magic_mirror);
}
