//! The Mire's rules: a port of VT's app/Region/Standard/DarkWorld/Mire.php
//! (MIT).
// VT's glitched routes are left out throughout: no glitches.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .mire,
    .enter = enter,
    .rules = &.{
        .{ .loc = .mire_shed_left, .req = moonPearl },
        .{ .loc = .mire_shed_right, .req = moonPearl },
    },
};

fn enter(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.rescue_zelda) and it.canLiftDarkRocks() and it.canFly();
}

/// Both Mire Shed chests.
fn moonPearl(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.moon_pearl);
}
