//! West Dark World Death Mountain's rules: a port of VT's
//! app/Region/Standard/DarkWorld/DeathMountain/West.php (MIT).
// VT's glitched routes are left out throughout: no glitches.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .west_dark_world_death_mountain,
    .enter = enter,
    .rules = &.{
        .{ .loc = .spike_cave, .req = spikeCave },
    },
};

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.has(.rescue_zelda) and w.canEnter(.west_death_mountain, it);
}

/// VT's region.cantTakeDamage is off by default, which leaves the Cane of
/// Byrna enough without the magic to spare.
fn spikeCave(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.moon_pearl) and it.has(.hammer) and it.canLiftRocks() and
        ((it.canExtendMagic(2) and it.has(.cape)) or it.has(.cane_of_byrna));
}
