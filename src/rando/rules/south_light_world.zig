//! South Light World: a port of VT's app/Region/Standard/LightWorld/
//! South.php (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

// VT's glitched routes are left out throughout: no glitches.

fn enter(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.rescue_zelda);
}

fn aginahsCave(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.canBombThings();
}

fn miniMoldormCave(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.canBombThings() and it.canKillMostThings(5);
}

fn hobo(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.flippers);
}

fn bombosTablet(w: *const r.World, it: *const r.Items) bool {
    return it.has(.book_of_mudora) and
        (it.hasSword(2) or (w.cfg.swordless() and it.has(.hammer))) and
        (it.has(.magic_mirror) and w.canEnter(.south_dark_world, it));
}

fn cave45(w: *const r.World, it: *const r.Items) bool {
    return it.has(.magic_mirror) and w.canEnter(.south_dark_world, it);
}

fn checkerboardCave(w: *const r.World, it: *const r.Items) bool {
    return it.canLiftRocks() and
        (it.has(.magic_mirror) and w.canEnter(.mire, it));
}

fn library(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.pegasus_boots);
}

fn desertLedge(w: *const r.World, it: *const r.Items) bool {
    return w.canEnter(.desert_palace, it);
}

fn lakeHyliaIsland(w: *const r.World, it: *const r.Items) bool {
    return it.has(.flippers) and it.has(.magic_mirror) and
        it.has(.moon_pearl) and
        w.canEnter(.north_east_dark_world, it);
}

fn fluteSpot(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.shovel);
}

pub const region = r.RegionRules{
    .region = .south_light_world,
    .enter = enter,
    .rules = &.{
        .{ .loc = .aginahs_cave, .req = aginahsCave },
        .{ .loc = .mini_moldorm_cave_far_left, .req = miniMoldormCave },
        .{ .loc = .mini_moldorm_cave_left, .req = miniMoldormCave },
        .{ .loc = .mini_moldorm_cave_right, .req = miniMoldormCave },
        .{ .loc = .mini_moldorm_cave_far_right, .req = miniMoldormCave },
        .{ .loc = .mini_moldorm_cave_npc, .req = miniMoldormCave },
        .{ .loc = .hobo, .req = hobo },
        .{ .loc = .bombos_tablet, .req = bombosTablet },
        .{ .loc = .cave_45, .req = cave45 },
        .{ .loc = .checkerboard_cave, .req = checkerboardCave },
        .{ .loc = .library, .req = library },
        .{ .loc = .desert_ledge, .req = desertLedge },
        .{ .loc = .lake_hylia_island, .req = lakeHyliaIsland },
        .{ .loc = .flute_spot, .req = fluteSpot },
    },
};
