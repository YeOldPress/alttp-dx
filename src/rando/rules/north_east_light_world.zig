//! North East Light World's rules: a port of VT's
//! app/Region/Standard/LightWorld/NorthEast.php (MIT).
// VT's glitched routes are left out throughout: no glitches.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .north_east_light_world,
    .enter = enter,
    .rules = &.{
        .{ .loc = .sahasrahla, .req = sahasrahla },
        .{ .loc = .king_zora, .req = kingZora },
        .{ .loc = .potion_shop, .req = potionShop },
        .{ .loc = .zoras_ledge, .req = flippers },
        .{ .loc = .waterfall_fairy_left, .req = flippers },
        .{ .loc = .waterfall_fairy_right, .req = flippers },
    },
};

fn enter(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.rescue_zelda);
}

fn sahasrahla(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.pendant_of_courage);
}

fn kingZora(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.canLiftRocks() or it.has(.flippers);
}

fn potionShop(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.mushroom);
}

/// Zora's Ledge and both Waterfall Fairy chests.
fn flippers(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.flippers);
}
