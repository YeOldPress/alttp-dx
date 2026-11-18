//! The Hyrule Castle escape's rules, Open mode: a port of VT's
//! app/Region/Open/HyruleCastleEscape.php over its Standard parent (MIT).
//!
//! The Open class's initalize doesn't call its parent's, so none of the
//! Standard rules carry over: no can_enter or can_complete, and Sanctuary,
//! the Map Chest and Zelda have no requirements. Only the constructor's
//! Zelda prize does.
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .escape,
    // VT also lists BigKeyH2 and CompassH2, which items.zig has no Item
    // for.
    .region_items = &.{ .key_h2, .map_h2 },
    .rules = &.{
        .{ .loc = .sewers_secret_room_left, .req = secretRoom },
        .{ .loc = .sewers_secret_room_middle, .req = secretRoom },
        .{ .loc = .sewers_secret_room_right, .req = secretRoom },
        .{ .loc = .sewers_dark_cross, .req = darkCross },
        .{ .loc = .hyrule_castle_boomerang_chest, .req = keyAndKill },
        .{ .loc = .hyrule_castle_zeldas_cell, .req = keyAndKill },
        .{ .loc = .secret_passage, .fill = notDungeonItem },
        .{ .loc = .links_uncle, .fill = uncleFill },
    },
    .preplaced = &.{.{ .loc = .zelda, .item = .rescue_zelda }},
};

/// Through the dark: the lamp, or the fire rod's light under advanced
/// placement.
fn lightTheWay(w: *const r.World, it: *const r.Items) bool {
    return w.lamp(it) or (w.cfg.item_placement == .advanced and it.has(.fire_rod));
}

/// Over the rocks by Sanctuary, or the long way through the sewers.
fn secretRoom(w: *const r.World, it: *const r.Items) bool {
    return it.canLiftRocks() or
        (lightTheWay(w, it) and it.has(.key_h2) and it.canKillMostThings(5));
}

fn darkCross(w: *const r.World, it: *const r.Items) bool {
    return lightTheWay(w, it);
}

/// The Boomerang Chest and Zelda's Cell.
fn keyAndKill(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.key_h2) and it.canKillMostThings(5);
}

/// No dungeon item kept to its dungeon goes here.
fn notDungeonItem(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return !((!w.cfg.wild_keys and r.itemKind(item) == .key) or
        (!w.cfg.wild_big_keys and r.itemKind(item) == .big_key) or
        (!w.cfg.wild_maps and r.itemKind(item) == .map) or
        (!w.cfg.wild_compasses and r.itemKind(item) == .compass));
}

/// VT asks Sanctuary of `$this->world->collectItems()`, the world's items
/// as they stand; Sanctuary has no requirements in Open mode and the escape
/// none to enter, so any items answer the same and `it` stands in.
fn uncleFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    return w.canAccess(.sanctuary, it) and notDungeonItem(w, item, it);
}
