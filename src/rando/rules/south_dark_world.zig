//! South Dark World: a port of VT's app/Region/Standard/DarkWorld/South.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT). Its shops are left out.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .south_dark_world,
    .enter = enter,
    .rules = &.{
        .{ .loc = .hype_cave_top, .req = moonPearl },
        .{ .loc = .hype_cave_middle_right, .req = moonPearl },
        .{ .loc = .hype_cave_middle_left, .req = moonPearl },
        .{ .loc = .hype_cave_bottom, .req = moonPearl },
        .{ .loc = .hype_cave_npc, .req = moonPearl },
        .{ .loc = .stumpy, .req = moonPearl },
        .{ .loc = .digging_game, .req = moonPearl },
    },
};

// VT's glitched routes are left out: no glitches. (Each of these also
// allowed a bottle YBA or a bunny revive, and Stumpy a mirror wrap.)
fn moonPearl(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.moon_pearl);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return it.has(.rescue_zelda) and
        ((it.has(.moon_pearl) and w.canEnter(.north_east_dark_world, it) and it.has(.hammer)) or
            w.canEnter(.north_west_dark_world, it));
}
