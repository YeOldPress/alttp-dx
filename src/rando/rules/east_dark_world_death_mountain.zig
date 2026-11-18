//! East Dark World Death Mountain's rules: a port of VT's
//! app/Region/Standard/DarkWorld/DeathMountain/East.php (MIT).
// VT's glitched routes are left out throughout: no glitches.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .east_dark_world_death_mountain,
    .enter = enter,
    .rules = &.{
        .{ .loc = .superbunny_cave_top, .req = superbunnyCave },
        .{ .loc = .superbunny_cave_bottom, .req = superbunnyCave },
        .{ .loc = .hookshot_cave_top_right, .req = hookshotCave },
        .{ .loc = .hookshot_cave_top_left, .req = hookshotCave },
        .{ .loc = .hookshot_cave_bottom_left, .req = hookshotCave },
        .{ .loc = .hookshot_cave_bottom_right, .req = hookshotCaveBottomRight },
    },
};

fn enter(w: *const r.World, it: *const r.Items) bool {
    return it.has(.rescue_zelda) and
        it.canLiftDarkRocks() and w.canEnter(.east_death_mountain, it);
}

fn superbunnyCave(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.moon_pearl);
}

/// Hookshot Cave's top two and bottom left.
fn hookshotCave(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.hookshot) and it.has(.moon_pearl) and it.canLiftRocks();
}

/// The bottom right's reached with a boots dash too, outside basic placement.
fn hookshotCaveBottomRight(w: *const r.World, it: *const r.Items) bool {
    return (it.has(.hookshot) or (w.cfg.item_placement != .basic and it.has(.pegasus_boots))) and
        it.has(.moon_pearl) and it.canLiftRocks();
}
