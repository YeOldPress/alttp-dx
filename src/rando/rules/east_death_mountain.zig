//! East Death Mountain's rules: a port of VT's
//! app/Region/Standard/LightWorld/DeathMountain/East.php (MIT).
// VT's glitched routes are left out throughout: no glitches.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .east_death_mountain,
    .enter = enter,
    .rules = &.{
        .{ .loc = .mimic_cave, .req = mimicCave },
        .{ .loc = .floating_island, .req = floatingIsland },
    },
};

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.has(.rescue_zelda) and
        ((it.has(.hookshot) and w.canEnter(.west_death_mountain, it)) or
            (it.has(.hammer) and w.canEnter(.tower_of_hera, it)));
}

fn mimicCave(w: *const r.World, it: *const r.Items) bool {
    return it.has(.hammer) and it.has(.magic_mirror) and
        it.hasN(.key_d7, 2) and w.canEnter(.turtle_rock, it);
}

fn floatingIsland(w: *const r.World, it: *const r.Items) bool {
    return it.has(.magic_mirror) and
        it.has(.moon_pearl) and it.canBombThings() and it.canLiftRocks() and
        w.canEnter(.east_dark_world_death_mountain, it);
}
