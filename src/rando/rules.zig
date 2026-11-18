//! The logic's rules, one file a region in rando/rules/, ported from the VT
//! randomizer's app/Region files (github.com/sporchia/alttp_vt_randomizer,
//! MIT), gathered into tables indexed by region and by location.
//!
//! A region file says how the region's entered (and finished, for a
//! dungeon), which dungeon items may go in it, any items placed in it from
//! the start, and each location's rules:
//!
//! - `req`: VT's setRequirements, what it takes to get the item there, on top
//!   of entering the region.
//! - `fill`: setFillRules, whether an item may be placed there at all.
//! - `always`: setAlwaysAllow, an item that may go there whatever else holds.
const std = @import("std");
const world = @import("world.zig");
const locs = @import("locations.zig");

pub const World = world.World;
pub const Items = world.Items;
pub const Item = world.Item;
pub const Loc = locs.Loc;
pub const Region = locs.Region;
pub const Boss = world.Boss;
pub const canBeat = world.canBeat;
/// What kind of item it is: VT's `instanceof Item\Key` and the like.
pub const itemKind = @import("items.zig").kind;

pub const ReqFn = *const fn (w: *const World, it: *const Items) bool;
pub const FillFn = *const fn (w: *const World, item: Item, it: *const Items) bool;

pub const Rule = struct {
    loc: Loc,
    req: ?ReqFn = null,
    fill: ?FillFn = null,
    always: ?FillFn = null,
};

pub const Preplaced = struct { loc: Loc, item: Item };

pub const RegionRules = struct {
    region: Region,
    enter: ?ReqFn = null,
    complete: ?ReqFn = null,
    /// The dungeon items that may be placed in it (VT's region_items, the
    /// keys, big keys, maps and compasses only).
    region_items: []const Item = &.{},
    rules: []const Rule = &.{},
    /// Items in it before the fill, as VT's region constructors set them.
    preplaced: []const Preplaced = &.{},
};

const kModules = .{
    @import("rules/north_east_light_world.zig"),
    @import("rules/north_west_light_world.zig"),
    @import("rules/south_light_world.zig"),
    @import("rules/escape.zig"),
    @import("rules/eastern_palace.zig"),
    @import("rules/desert_palace.zig"),
    @import("rules/west_death_mountain.zig"),
    @import("rules/east_death_mountain.zig"),
    @import("rules/tower_of_hera.zig"),
    @import("rules/hyrule_castle_tower.zig"),
    @import("rules/east_dark_world_death_mountain.zig"),
    @import("rules/west_dark_world_death_mountain.zig"),
    @import("rules/north_east_dark_world.zig"),
    @import("rules/north_west_dark_world.zig"),
    @import("rules/south_dark_world.zig"),
    @import("rules/mire.zig"),
    @import("rules/palace_of_darkness.zig"),
    @import("rules/swamp_palace.zig"),
    @import("rules/skull_woods.zig"),
    @import("rules/thieves_town.zig"),
    @import("rules/ice_palace.zig"),
    @import("rules/misery_mire.zig"),
    @import("rules/turtle_rock.zig"),
    @import("rules/ganons_tower.zig"),
    @import("rules/medallions.zig"),
    @import("rules/fountains.zig"),
};

const kRegionCount = locs.kRegionNames.len;
const kLocCount = locs.kLocs.len;

pub const kEnter: [kRegionCount]?ReqFn = blk: {
    var t: [kRegionCount]?ReqFn = @splat(null);
    for (kModules) |m| t[@backingInt(m.region.region)] = m.region.enter;
    break :blk t;
};

pub const kComplete: [kRegionCount]?ReqFn = blk: {
    var t: [kRegionCount]?ReqFn = @splat(null);
    for (kModules) |m| t[@backingInt(m.region.region)] = m.region.complete;
    break :blk t;
};

pub const kRegionItems: [kRegionCount][]const Item = blk: {
    var t: [kRegionCount][]const Item = @splat(&.{});
    for (kModules) |m| t[@backingInt(m.region.region)] = m.region.region_items;
    break :blk t;
};

pub const kReq: [kLocCount]?ReqFn = blk: {
    @setEvalBranchQuota(100000);
    var t: [kLocCount]?ReqFn = @splat(null);
    for (kModules) |m| for (m.region.rules) |r| {
        t[@backingInt(r.loc)] = r.req;
    };
    break :blk t;
};

pub const kFill: [kLocCount]?FillFn = blk: {
    @setEvalBranchQuota(100000);
    var t: [kLocCount]?FillFn = @splat(null);
    for (kModules) |m| for (m.region.rules) |r| {
        t[@backingInt(r.loc)] = r.fill;
    };
    break :blk t;
};

pub const kAlways: [kLocCount]?FillFn = blk: {
    @setEvalBranchQuota(100000);
    var t: [kLocCount]?FillFn = @splat(null);
    for (kModules) |m| for (m.region.rules) |r| {
        t[@backingInt(r.loc)] = r.always;
    };
    break :blk t;
};

pub const kPreplaced: []const Preplaced = blk: {
    var all: []const Preplaced = &.{};
    for (kModules) |m| all = all ++ m.region.preplaced;
    break :blk all;
};

comptime {
    // Every region has its file, and every rule's location is in its
    // region.
    @setEvalBranchQuota(100000);
    var seen: [kRegionCount]bool = @splat(false);
    for (kModules) |m| {
        if (seen[@backingInt(m.region.region)]) @compileError("two files for one region");
        seen[@backingInt(m.region.region)] = true;
        for (m.region.rules) |r| {
            if (locs.kLocs[@backingInt(r.loc)].region != m.region.region)
                @compileError("a rule for " ++ locs.kLocs[@backingInt(r.loc)].name ++ " outside its region");
        }
    }
    for (seen) |s| if (!s) @compileError("a region without its file");
}
