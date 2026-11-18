//! Ganon's Tower: a port of the VT randomizer's
//! app/Region/Standard/GanonsTower.php (github.com/sporchia/alttp_vt_randomizer, MIT).
const r = @import("../rules.zig");

pub const region = r.RegionRules{
    .region = .ganons_tower,
    .enter = enter,
    .complete = complete,
    .region_items = &.{ .big_key_a2, .compass_a2, .key_a2, .map_a2 },
    .rules = &.{
        .{ .loc = .ganons_tower_bobs_torch, .req = bobsTorch },
        .{ .loc = .ganons_tower_dms_room_top_left, .req = hammerAndHookshot },
        .{ .loc = .ganons_tower_dms_room_top_right, .req = hammerAndHookshot },
        .{ .loc = .ganons_tower_dms_room_bottom_left, .req = hammerAndHookshot },
        .{ .loc = .ganons_tower_dms_room_bottom_right, .req = hammerAndHookshot },
        .{ .loc = .ganons_tower_randomizer_room_top_left, .req = randomizerTopLeft },
        .{ .loc = .ganons_tower_randomizer_room_top_right, .req = randomizerTopRight },
        .{ .loc = .ganons_tower_randomizer_room_bottom_left, .req = randomizerBottomLeft },
        .{ .loc = .ganons_tower_randomizer_room_bottom_right, .req = randomizerBottomRight },
        .{ .loc = .ganons_tower_firesnake_room, .req = firesnakeRoom },
        .{ .loc = .ganons_tower_map_chest, .req = mapChest, .always = mapChestAlways, .fill = mapChestFill },
        .{ .loc = .ganons_tower_big_chest, .req = bigChest, .fill = notBigKey },
        .{ .loc = .ganons_tower_bobs_chest, .req = bobsChest },
        .{ .loc = .ganons_tower_tile_room, .req = tileRoom },
        .{ .loc = .ganons_tower_compass_room_top_left, .req = compassTopLeft },
        .{ .loc = .ganons_tower_compass_room_top_right, .req = compassTopRight },
        .{ .loc = .ganons_tower_compass_room_bottom_left, .req = compassBottomLeft },
        .{ .loc = .ganons_tower_compass_room_bottom_right, .req = compassBottomRight },
        .{ .loc = .ganons_tower_big_key_chest, .req = bigKeyRoom },
        .{ .loc = .ganons_tower_big_key_room_left, .req = bigKeyRoom },
        .{ .loc = .ganons_tower_big_key_room_right, .req = bigKeyRoom },
        .{ .loc = .ganons_tower_mini_helmasaur_room_left, .req = upstairs, .fill = notBigKey },
        .{ .loc = .ganons_tower_mini_helmasaur_room_right, .req = upstairs, .fill = notBigKey },
        .{ .loc = .ganons_tower_pre_moldorm_chest, .req = upstairs, .fill = notBigKey },
        .{ .loc = .ganons_tower_moldorm_chest, .req = moldormChest, .fill = moldormChestFill },
        .{ .loc = .agahnim_2, .req = complete },
    },
    .preplaced = &.{.{ .loc = .agahnim_2, .item = .defeat_agahnim2 }},
};

/// VT's `$locations->itemInLocations(Item::get('BigKeyA2'), [...])`: the big
/// key's in one of them.
fn bigKeyIn(w: *const r.World, comptime where: []const r.Loc) bool {
    inline for (where) |loc| {
        if (w.hasItemAt(loc, .big_key_a2)) return true;
    }
    return false;
}

fn bobsTorch(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.pegasus_boots);
}

fn hammerAndHookshot(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.hammer) and it.has(.hookshot);
}

/// The randomizer room's chests: three keys if the big key's in one of the
/// `others`, four if not.
fn randomizerRoom(w: *const r.World, it: *const r.Items, comptime others: []const r.Loc) bool {
    return it.has(.hammer) and it.has(.hookshot) and
        ((bigKeyIn(w, others) and it.hasN(.key_a2, 3)) or it.hasN(.key_a2, 4));
}

fn randomizerTopLeft(w: *const r.World, it: *const r.Items) bool {
    return randomizerRoom(w, it, &.{
        .ganons_tower_randomizer_room_top_right,
        .ganons_tower_randomizer_room_bottom_left,
        .ganons_tower_randomizer_room_bottom_right,
    });
}

fn randomizerTopRight(w: *const r.World, it: *const r.Items) bool {
    return randomizerRoom(w, it, &.{
        .ganons_tower_randomizer_room_top_left,
        .ganons_tower_randomizer_room_bottom_left,
        .ganons_tower_randomizer_room_bottom_right,
    });
}

fn randomizerBottomLeft(w: *const r.World, it: *const r.Items) bool {
    return randomizerRoom(w, it, &.{
        .ganons_tower_randomizer_room_top_right,
        .ganons_tower_randomizer_room_top_left,
        .ganons_tower_randomizer_room_bottom_right,
    });
}

fn randomizerBottomRight(w: *const r.World, it: *const r.Items) bool {
    return randomizerRoom(w, it, &.{
        .ganons_tower_randomizer_room_top_right,
        .ganons_tower_randomizer_room_top_left,
        .ganons_tower_randomizer_room_bottom_left,
    });
}

fn firesnakeRoom(w: *const r.World, it: *const r.Items) bool {
    return it.has(.hammer) and it.has(.hookshot) and
        (((bigKeyIn(w, &.{
            .ganons_tower_randomizer_room_top_right,
            .ganons_tower_randomizer_room_top_left,
            .ganons_tower_randomizer_room_bottom_left,
            .ganons_tower_randomizer_room_bottom_right,
        }) or w.hasItemAt(.ganons_tower_firesnake_room, .key_a2)) and it.hasN(.key_a2, 2)) or
            it.hasN(.key_a2, 3));
}

fn mapChest(w: *const r.World, it: *const r.Items) bool {
    const own_key = if (w.itemAt(.ganons_tower_map_chest)) |i| i == .big_key_a2 or i == .key_a2 else false;
    return it.has(.hammer) and
        (it.has(.hookshot) or (w.cfg.item_placement != .basic and it.has(.pegasus_boots))) and
        (if (own_key) it.hasN(.key_a2, 3) else it.hasN(.key_a2, 4));
}

fn mapChestAlways(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    return w.cfg.accessibility != .locations and item == .key_a2 and it.hasN(.key_a2, 3);
}

fn mapChestFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = it;
    return w.cfg.accessibility != .locations or item != .key_a2;
}

/// Past the bottom floor's split: the hammer and hookshot side, or the fire
/// rod and somaria side.
fn eitherSide(it: *const r.Items) bool {
    return (it.has(.hammer) and it.has(.hookshot)) or (it.has(.fire_rod) and it.has(.cane_of_somaria));
}

fn bigChest(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.big_key_a2) and it.hasN(.key_a2, 3) and eitherSide(it);
}

fn notBigKey(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = w;
    _ = it;
    return item != .big_key_a2;
}

fn bobsChest(w: *const r.World, it: *const r.Items) bool {
    return eitherSide(it) and
        it.hasN(.key_a2, 3) and
        (w.cfg.item_placement != .basic or (it.has(.fire_rod) or (it.has(.ether) and it.hasSword(1))));
}

fn tileRoom(w: *const r.World, it: *const r.Items) bool {
    _ = w;
    return it.has(.cane_of_somaria);
}

/// The compass room's chests: three keys if the big key's in one of the
/// `others`, four if not.
fn compassRoom(w: *const r.World, it: *const r.Items, comptime others: []const r.Loc) bool {
    return it.has(.fire_rod) and it.has(.cane_of_somaria) and
        ((bigKeyIn(w, others) and it.hasN(.key_a2, 3)) or it.hasN(.key_a2, 4));
}

fn compassTopLeft(w: *const r.World, it: *const r.Items) bool {
    return compassRoom(w, it, &.{
        .ganons_tower_compass_room_top_right,
        .ganons_tower_compass_room_bottom_left,
        .ganons_tower_compass_room_bottom_right,
    });
}

fn compassTopRight(w: *const r.World, it: *const r.Items) bool {
    return compassRoom(w, it, &.{
        .ganons_tower_compass_room_top_left,
        .ganons_tower_compass_room_bottom_left,
        .ganons_tower_compass_room_bottom_right,
    });
}

fn compassBottomLeft(w: *const r.World, it: *const r.Items) bool {
    return compassRoom(w, it, &.{
        .ganons_tower_compass_room_top_right,
        .ganons_tower_compass_room_top_left,
        .ganons_tower_compass_room_bottom_right,
    });
}

fn compassBottomRight(w: *const r.World, it: *const r.Items) bool {
    return compassRoom(w, it, &.{
        .ganons_tower_compass_room_top_right,
        .ganons_tower_compass_room_top_left,
        .ganons_tower_compass_room_bottom_left,
    });
}

/// The big key chest and the room beside it, past the bottom boss.
fn bigKeyRoom(w: *const r.World, it: *const r.Items) bool {
    return eitherSide(it) and
        it.hasN(.key_a2, 3) and
        r.canBeat(.armos_knights, w, it);
}

/// Up the stairs past the middle boss: the mini helmasaur room and the
/// chest before Moldorm.
fn upstairs(w: *const r.World, it: *const r.Items) bool {
    return it.canShootArrows(1) and it.canLightTorches() and
        it.has(.big_key_a2) and it.hasN(.key_a2, 3) and
        r.canBeat(.lanmolas, w, it);
}

fn moldormChest(w: *const r.World, it: *const r.Items) bool {
    return it.has(.hookshot) and
        it.canShootArrows(1) and it.canLightTorches() and
        it.has(.big_key_a2) and it.hasN(.key_a2, 4) and
        r.canBeat(.lanmolas, w, it) and
        r.canBeat(.moldorm, w, it);
}

fn moldormChestFill(w: *const r.World, item: r.Item, it: *const r.Items) bool {
    _ = w;
    _ = it;
    return item != .key_a2 and item != .big_key_a2;
}

fn complete(w: *const r.World, it: *const r.Items) bool {
    return enter(w, it) and
        w.canAccess(.ganons_tower_moldorm_chest, it) and
        r.canBeat(.agahnim2, w, it);
}

fn enter(w: *const r.World, it: *const r.Items) bool {
    // VT's glitched routes are left out: no glitches.
    return it.has(.rescue_zelda) and
        (w.cfg.item_placement != .basic or
            ((w.cfg.swordless() or it.hasSword(2)) and it.hasHealth(12) and (it.hasBottle(2) or it.hasArmor(1)))) and
        it.has(.moon_pearl) and
        it.crystalCount() >= w.cfg.crystals_tower and
        w.canEnter(.east_dark_world_death_mountain, it);
}
