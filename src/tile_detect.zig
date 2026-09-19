//! Port of src/tile_detect.c: works out which tile behaviours Link (or a
//! hookshot) is touching, and records them as bitmasks in work ram.
//!
//! `TileDetect_ExecuteInner` is one big switch over the 256 tile behaviour
//! types; the original aborts on anything it does not know, so the default
//! prong panics rather than silently ignoring a tile.
const std = @import("std");
const vars = @import("variables.zig");

// Still in C: overworld.c and ancilla.c.
extern fn GetMap8toTileAttr() [*]const u8;
extern fn GetMap16toMap8Table() [*]const u16;
extern fn Ancilla_GetX(k: c_int) u16;
extern fn Ancilla_GetY(k: c_int) u16;

const R12 = vars.R12;
const R14 = vars.R14;
const scratch_1 = vars.scratch_1;
const link_x_coord = vars.link_x_coord;
const link_y_coord = vars.link_y_coord;
const link_is_on_lower_level = vars.link_is_on_lower_level;
const link_last_direction_moved_towards = vars.link_last_direction_moved_towards;
const link_tile_below = vars.link_tile_below;
const player_is_indoors = vars.player_is_indoors;
const player_on_somaria_platform = vars.player_on_somaria_platform;
const tilemap_location_calc_mask = vars.tilemap_location_calc_mask;
const force_move_any_direction = vars.force_move_any_direction;
const cheatWalkThroughWalls = vars.cheatWalkThroughWalls;
const index_of_interacting_tile = vars.index_of_interacting_tile;
const interacting_with_liftable_tile_x2 = vars.interacting_with_liftable_tile_x2;
const room_transitioning_flags = vars.room_transitioning_flags;
const flag_block_link_menu = vars.flag_block_link_menu;

const overworld_offset_base_x = vars.overworld_offset_base_x;
const overworld_offset_base_y = vars.overworld_offset_base_y;
const overworld_offset_mask_x = vars.overworld_offset_mask_x;
const overworld_offset_mask_y = vars.overworld_offset_mask_y;
const overworld_tileattr = vars.overworld_tileattr;

const dungeon_room_index = vars.dungeon_room_index;
const dung_bg2_attr_table = vars.dung_bg2_attr_table;
const dung_chest_locations = vars.dung_chest_locations;
const dung_hdr_collision = vars.dung_hdr_collision;
const dung_savegame_state_bits = vars.dung_savegame_state_bits;
const kind_of_in_room_staircase = vars.kind_of_in_room_staircase;

const ancilla_arr1 = vars.ancilla_arr1;
const ancilla_dir = vars.ancilla_dir;
const BG1HOFS_copy2 = vars.BG1HOFS_copy2;
const BG2HOFS_copy2 = vars.BG2HOFS_copy2;
const BG1VOFS_copy2 = vars.BG1VOFS_copy2;
const BG2VOFS_copy2 = vars.BG2VOFS_copy2;

const tiledetect_which_y_pos = vars.tiledetect_which_y_pos;
const tiledetect_pit_tile = vars.tiledetect_pit_tile;
const tiledetect_diagonal_tile = vars.tiledetect_diagonal_tile;
const tiledetect_stair_tile = vars.tiledetect_stair_tile;
const tiledetect_inroom_staircase = vars.tiledetect_inroom_staircase;
const tiledetect_var1 = vars.tiledetect_var1;
const tiledetect_var2 = vars.tiledetect_var2;
const tiledetect_var4 = vars.tiledetect_var4;
const tiledetect_moving_floor_tiles = vars.tiledetect_moving_floor_tiles;
const tiledetect_deepwater = vars.tiledetect_deepwater;
const tiledetect_normal_tiles = vars.tiledetect_normal_tiles;
const tiledetect_icy_floor = vars.tiledetect_icy_floor;
const tiledetect_water_staircase = vars.tiledetect_water_staircase;
const tiledetect_thick_grass = vars.tiledetect_thick_grass;
const tiledetect_shallow_water = vars.tiledetect_shallow_water;
const tiledetect_destruction_aftermath = vars.tiledetect_destruction_aftermath;
const tiledetect_read_something = vars.tiledetect_read_something;
const tiledetect_vertical_ledge = vars.tiledetect_vertical_ledge;
const tiledetect_ledges_down_leftright = vars.tiledetect_ledges_down_leftright;
const tiledetect_chest = vars.tiledetect_chest;
const tiledetect_key_lock_gravestones = vars.tiledetect_key_lock_gravestones;
const tiledetect_spike_floor_and_tile_triggers = vars.tiledetect_spike_floor_and_tile_triggers;
const tiledetect_misc_tiles = vars.tiledetect_misc_tiles;
const tiledetect_diag_state = vars.tiledetect_diag_state;
const tiledetect_tile_type = vars.tiledetect_tile_type;
const detection_of_ledge_tiles_horiz_uphoriz = vars.detection_of_ledge_tiles_horiz_uphoriz;
const detection_of_unknown_tile_types = vars.detection_of_unknown_tile_types;
const bitfield_spike_cactus_tiles = vars.bitfield_spike_cactus_tiles;
const bitmask_for_dashable_tiles = vars.bitmask_for_dashable_tiles;

/// types.h BYTE(x): the low byte of a 16-bit work-ram word.
fn loByte(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

/// Sign extend an int8 offset the way C does before adding it to a coordinate.
fn rel(v: i8) u16 {
    return @bitCast(@as(i16, v));
}

const kDetectTiles_tab0 = [4]u8{ 8, 24, 0, 15 };
const kDetectTiles_tab1 = [4]u8{ 0, 0, 8, 8 };
const kDetectTiles_tab2 = [4]u8{ 8, 8, 16, 16 };
const kDetectTiles_tab3 = [4]u8{ 15, 15, 23, 23 };
const kDetectTiles_tab4 = [4]i8{ 7, 24, -1, 16 };
const kDetectTiles_tab5 = [4]u8{ 0, 0, 8, 8 };
const kDetectTiles_tab6 = [4]u8{ 15, 15, 23, 23 };

pub export fn Overworld_GetTileAttributeAtLocation(x: u16, y: u16) callconv(.c) u8 { // 80882e
    var t: u16 = ((y -% overworld_offset_base_y.*) & overworld_offset_mask_y.*) *% 8;
    t |= ((x -% overworld_offset_base_x.*) & overworld_offset_mask_x.*);
    t = overworld_tileattr[t >> 1] *% 4;
    t |= (y & 8) >> 2;
    t |= (x & 1);
    t = GetMap16toMap8Table()[t];

    var rv = GetMap8toTileAttr()[t & 0x1ff];
    if (rv >= 0x10 and rv < 0x1C) {
        rv |= @truncate((t >> 14) & 1);
    }
    return rv;
}

pub export fn TileDetect_Movement_Y(direction: u16) callconv(.c) void { // 87cdcb
    std.debug.assert(direction < 4);
    TileDetect_ResetState();
    tiledetect_pit_tile.* = 0;

    tiledetect_which_y_pos[0] = link_y_coord.* +% kDetectTiles_tab0[direction];
    const y = tiledetect_which_y_pos[0] & tilemap_location_calc_mask.*;
    const x0 = ((link_x_coord.* +% kDetectTiles_tab1[direction]) & tilemap_location_calc_mask.*) >> 3;
    const x1 = ((link_x_coord.* +% kDetectTiles_tab2[direction]) & tilemap_location_calc_mask.*) >> 3;
    const x2 = ((link_x_coord.* +% kDetectTiles_tab3[direction]) & tilemap_location_calc_mask.*) >> 3;
    scratch_1.* = x2;
    TileDetection_Execute(x0, y, 1);
    TileDetection_Execute(x1, y, 2);
    TileDetection_Execute(x2, y, 4);
}

pub export fn TileDetect_Movement_X(direction: u16) callconv(.c) void { // 87ce2a
    std.debug.assert(direction < 4);
    TileDetect_ResetState();
    tiledetect_pit_tile.* = 0;

    const x = ((link_x_coord.* +% kDetectTiles_tab0[direction]) & tilemap_location_calc_mask.*) >> 3;
    const y0 = ((link_y_coord.* +% kDetectTiles_tab1[direction]) & tilemap_location_calc_mask.*);
    tiledetect_which_y_pos[0] = link_y_coord.* +% kDetectTiles_tab2[direction];
    const y1 = tiledetect_which_y_pos[0] & tilemap_location_calc_mask.*;
    tiledetect_which_y_pos[1] = link_y_coord.* +% kDetectTiles_tab3[direction];
    const y2 = tiledetect_which_y_pos[1] & tilemap_location_calc_mask.*;
    TileDetection_Execute(x, y0, 1);
    TileDetection_Execute(x, y1, 2);
    TileDetection_Execute(x, y2, 4);
}

pub export fn TileDetect_Movement_VerticalSlopes(direction: u16) callconv(.c) void { // 87ce85
    std.debug.assert(direction < 4);
    TileDetect_ResetState();
    tiledetect_pit_tile.* = 0;

    const y = (link_y_coord.* +% rel(kDetectTiles_tab4[direction])) & tilemap_location_calc_mask.*;
    const x0 = ((link_x_coord.* +% kDetectTiles_tab5[direction]) & tilemap_location_calc_mask.*) >> 3;
    const x1 = ((link_x_coord.* +% kDetectTiles_tab6[direction]) & tilemap_location_calc_mask.*) >> 3;
    TileDetection_Execute(x0, y, 1);
    TileDetection_Execute(x1, y, 2);
}

pub export fn TileDetect_Movement_HorizontalSlopes(direction: u16) callconv(.c) void { // 87cec9
    std.debug.assert(direction < 4);
    TileDetect_ResetState();
    tiledetect_pit_tile.* = 0;

    const x = ((link_x_coord.* +% rel(kDetectTiles_tab4[direction])) & tilemap_location_calc_mask.*) >> 3;
    const y0 = ((link_y_coord.* +% kDetectTiles_tab5[direction]) & tilemap_location_calc_mask.*);
    const y1 = ((link_y_coord.* +% kDetectTiles_tab6[direction]) & tilemap_location_calc_mask.*);
    TileDetection_Execute(x, y0, 1);
    TileDetection_Execute(x, y1, 2);
}

pub export fn Player_TileDetectNearby() callconv(.c) void { // 87cf12
    TileDetect_ResetState();
    tiledetect_pit_tile.* = 0;

    const x0 = ((link_x_coord.* +% kDetectTiles_tab1[0]) & tilemap_location_calc_mask.*) >> 3;
    const x1 = ((link_x_coord.* +% kDetectTiles_tab3[0]) & tilemap_location_calc_mask.*) >> 3;

    const y0 = ((link_y_coord.* +% kDetectTiles_tab1[2]) & tilemap_location_calc_mask.*);
    const y1 = ((link_y_coord.* +% kDetectTiles_tab3[2]) & tilemap_location_calc_mask.*);

    scratch_1.* = y0;

    TileDetection_Execute(x0, y0, 8);
    TileDetection_Execute(x0, y1, 2);
    TileDetection_Execute(x1, y0, 4);
    TileDetection_Execute(x1, y1, 1);
}

pub export fn Hookshot_CheckTileCollision(k: c_int) callconv(.c) void { // 87d576
    const bak0 = loByte(dungeon_room_index).*;
    const bak1 = link_is_on_lower_level.*;

    if (ancilla_arr1[@intCast(k)] != 0) {
        if (loByte(kind_of_in_room_staircase).* == 0)
            loByte(dungeon_room_index).* +%= 0x10;
        link_is_on_lower_level.* ^= 1;
    }

    const x = Ancilla_GetX(k);
    const y = Ancilla_GetY(k);
    const dir: c_int = ancilla_dir[@intCast(k)];

    tiledetect_pit_tile.* = 0;
    TileDetect_ResetState();
    if (dung_hdr_collision.* == 2) {
        link_is_on_lower_level.* = 1;
        Hookshot_CheckSingleLayerTileCollision(
            x +% BG1HOFS_copy2.* -% BG2HOFS_copy2.*,
            y +% BG1VOFS_copy2.* -% BG2VOFS_copy2.*,
            dir,
        );
        link_is_on_lower_level.* = 0;
    }
    Hookshot_CheckSingleLayerTileCollision(x, y, dir);

    link_is_on_lower_level.* = bak1;
    loByte(dungeon_room_index).* = bak0;
}

pub export fn Hookshot_CheckSingleLayerTileCollision(x: u16, y: u16, dir: c_int) callconv(.c) void { // 87d607
    const kHookShot_CheckColl_X = [8]u8{ 0, 15, 0, 15, 0, 0, 8, 8 };
    const kHookShot_CheckColl_Y = [8]u8{ 0, 0, 7, 7, 0, 15, 0, 15 };
    const d: usize = @intCast(dir);
    const y0 = (y +% kHookShot_CheckColl_Y[d * 2 + 0]) & tilemap_location_calc_mask.*;
    const y1 = (y +% kHookShot_CheckColl_Y[d * 2 + 1]) & tilemap_location_calc_mask.*;
    const x0 = ((x +% kHookShot_CheckColl_X[d * 2 + 0]) & tilemap_location_calc_mask.*) >> 3;
    const x1 = ((x +% kHookShot_CheckColl_X[d * 2 + 1]) & tilemap_location_calc_mask.*) >> 3;
    TileDetection_Execute(x0, y0, 1);
    TileDetection_Execute(x1, y1, 2);
}

pub export fn HandleNudgingInADoor(speed: i8) callconv(.c) void { // 87d667
    const y: usize = if (link_last_direction_moved_towards.* & 2 != 0)
        (if (@as(u8, @truncate(link_y_coord.*)) < 0x80) @as(usize, 1) else 0)
    else
        (if (@as(u8, @truncate(link_x_coord.*)) < 0x80) @as(usize, 3) else 2);
    tiledetect_pit_tile.* = 0;
    TileDetect_ResetState();

    const kDetectTiles_7_Y = [4]i8{ 8, 23, 16, 16 };
    const kDetectTiles_7_X = [4]i8{ 8, 8, 0, 15 };

    const x0 = ((link_x_coord.* +% rel(kDetectTiles_7_X[y])) & tilemap_location_calc_mask.*) >> 3;
    const y0 = ((link_y_coord.* +% rel(kDetectTiles_7_Y[y])) & tilemap_location_calc_mask.*);

    TileDetection_Execute(x0, y0, 1);

    if (((R14.* | detection_of_ledge_tiles_horiz_uphoriz.*) & 3) == 0) {
        if (((@as(u16, tiledetect_vertical_ledge.*) | detection_of_unknown_tile_types.*) & 0x33) == 0)
            return;
    }

    if (link_last_direction_moved_towards.* & 2 != 0) {
        link_y_coord.* -%= rel(speed);
    } else {
        link_x_coord.* -%= rel(speed);
    }
}

pub export fn TileCheckForMirrorBonk() callconv(.c) void { // 87d6f4
    tiledetect_pit_tile.* = 0;
    TileDetect_ResetState();

    const x0 = ((link_x_coord.* +% 2) & tilemap_location_calc_mask.*) >> 3;
    const x1 = ((link_x_coord.* +% 13) & tilemap_location_calc_mask.*) >> 3;

    const y0 = ((link_y_coord.* +% 10) & tilemap_location_calc_mask.*);
    const y1 = ((link_y_coord.* +% 21) & tilemap_location_calc_mask.*);

    scratch_1.* = y0;

    TileDetection_Execute(x0, y0, 8);
    TileDetection_Execute(x0, y1, 2);
    TileDetection_Execute(x1, y0, 4);
    TileDetection_Execute(x1, y1, 1);
}

/// Used when holding sword in doorway
pub export fn TileDetect_SwordSwingDeepInDoor(dw: u8) callconv(.c) void { // 87d73e
    tiledetect_pit_tile.* = 0;
    TileDetect_ResetState();

    const kDoorwayDetectX = [4]i8{ 8, 8, -1, 16 };
    const kDoorwayDetectY = [4]i8{ -1, 24, 16, 16 };
    const o: usize = @intCast((@as(i32, dw) - 1) * 2);
    const x0 = ((link_x_coord.* +% rel(kDoorwayDetectX[o + 0])) & tilemap_location_calc_mask.*) >> 3;
    const x1 = ((link_x_coord.* +% rel(kDoorwayDetectX[o + 1])) & tilemap_location_calc_mask.*) >> 3;

    const y0 = ((link_y_coord.* +% rel(kDoorwayDetectY[o + 0])) & tilemap_location_calc_mask.*);
    const y1 = ((link_y_coord.* +% rel(kDoorwayDetectY[o + 1])) & tilemap_location_calc_mask.*);

    TileDetection_Execute(x0, y0, 1);
    TileDetection_Execute(x1, y1, 2);
}

pub export fn TileDetect_ResetState() callconv(.c) void { // 87d798
    R12.* = 0;
    R14.* = 0;
    tiledetect_diagonal_tile.* = 0;
    tiledetect_stair_tile.* = 0;
    tiledetect_pit_tile.* = 0;
    tiledetect_inroom_staircase.* = 0;
    tiledetect_var2.* = 0;
    tiledetect_var1.* = 0;
    tiledetect_moving_floor_tiles.* = 0;
    tiledetect_deepwater.* = 0;
    tiledetect_normal_tiles.* = 0;
    tiledetect_icy_floor.* = 0;
    tiledetect_water_staircase.* = 0;
    tiledetect_thick_grass.* = 0;
    tiledetect_shallow_water.* = 0;
    tiledetect_destruction_aftermath.* = 0;
    tiledetect_read_something.* = 0;
    tiledetect_vertical_ledge.* = 0;
    detection_of_ledge_tiles_horiz_uphoriz.* = 0;
    tiledetect_ledges_down_leftright.* = 0;
    detection_of_unknown_tile_types.* = 0;
    tiledetect_chest.* = 0;
    tiledetect_key_lock_gravestones.* = 0;
    bitfield_spike_cactus_tiles.* = 0;
    tiledetect_spike_floor_and_tile_triggers.* = 0;
    bitmask_for_dashable_tiles.* = 0;
    tiledetect_misc_tiles.* = 0;
    tiledetect_var4.* = 0;
}

pub export fn TileDetection_Execute(x: u16, y: u16, bits: u16) callconv(.c) void { // 87d9d8
    var tile: u8 = undefined;
    var offs: u16 = 0;
    if (player_is_indoors.* != 0) {
        force_move_any_direction.* = force_move_any_direction.* & 0xff;
        offs = @truncate((@as(u32, y & ~@as(u16, 7)) * 8) +
            (x & 63) +
            (if (link_is_on_lower_level.* != 0) @as(u32, 0x1000) else 0));
        tile = dung_bg2_attr_table[offs];
        if (cheatWalkThroughWalls.* != 0)
            tile = 0;
        link_tile_below.* = tile;
    } else {
        tile = Overworld_GetTileAttributeAtLocation(x, y);
    }
    TileDetect_ExecuteInner(tile, offs, bits, player_is_indoors.* != 0);
}

/// OR a widened value into a 16-bit work-ram word, truncating the way the C
/// does on assignment.
fn or16(p: *align(1) u16, v: u32) void {
    p.* |= @truncate(v);
}

/// Same, for the byte-wide masks.
fn or8(p: *u8, v: u32) void {
    p.* |= @truncate(v);
}

pub export fn TileDetect_ExecuteInner(tile_in: u8, offs: u16, bits: u16, is_indoors: bool) callconv(.c) void { // 87dc2e
    const word_87DC55 = [4]u8{ 4, 0, 6, 2 };
    var tile = tile_in;
    if (cheatWalkThroughWalls.* != 0)
        tile = 0;

    const b: u32 = bits;
    switch (tile) {
        // TileBehavior_NothingOW
        0x00, 0x05, 0x06, 0x07, 0x14, 0x15, 0x16, 0x17, 0x21, 0x23, 0x24, 0x25,
        0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x41, 0x45, 0x47, 0x49, 0x5e, 0x5f, 0x61,
        0x62, 0x64, 0x65, 0x66, 0xa6, 0xa7, 0xbe, 0xbf, 0xd0...0xef,
        => {
            if (!is_indoors)
                or16(tiledetect_normal_tiles, b);
        },
        // TileBehavior_StandardCollision
        0x01, 0x02, 0x03, 0x26, 0x43 => or16(R14, b),
        0x6c, 0x6d, 0x6e, 0x6f => {
            if (is_indoors)
                or16(R14, b)
            else
                or16(tiledetect_normal_tiles, b);
        },
        0x04 => {
            if (is_indoors) {
                or16(R14, b);
            } else {
                or16(tiledetect_thick_grass, b);
            }
        },
        0x0b => {
            if (is_indoors) {
                or16(R14, b);
            } else {
                index_of_interacting_tile.* = tile;
                or16(tiledetect_deepwater, b << 4);
            }
        },
        0x08 => or16(tiledetect_deepwater, b), // TileBehavior_DeepWater
        0x09 => or16(tiledetect_shallow_water, b), // TileBehavior_ShallowWater
        0x0a => or16(tiledetect_normal_tiles, b), // TileBehavior_ShortWaterLadder
        0x0c => or16(tiledetect_moving_floor_tiles, b), // TileBehavior_OverlayMask_0C
        0x0d => { // TileBehavior_SpikeFloor
            if (flag_block_link_menu.* == 0 and (dung_savegame_state_bits.* & 0x8000) == 0)
                or8(tiledetect_spike_floor_and_tile_triggers, b << 4);
        },
        0x0e => or16(tiledetect_icy_floor, b), // TileBehavior_GanonIce
        0x0f => or16(tiledetect_icy_floor, b << 4), // TileBehavior_PalaceIce
        0x10, 0x11, 0x12, 0x13 => { // TileBehavior_Slope
            or16(R12, b);
            tiledetect_diag_state.* = word_87DC55[tile & 3];
        },
        0x18, 0x19, 0x1a, 0x1b => { // TileBehavior_SlopeOuter
            or16(tiledetect_diagonal_tile, b);
            or16(R12, b);
            tiledetect_diag_state.* = word_87DC55[tile & 3];
        },
        0x1c => or16(tiledetect_water_staircase, b), // TileBehavior_OverlayMask_1C
        0x1d => { // TileBehavior_NorthSingleLayerStairs
            index_of_interacting_tile.* = tile;
            or16(tiledetect_inroom_staircase, b);
            or8(tiledetect_stair_tile, b);
        },
        0x1e, 0x1f => { // TileBehavior_NorthSwapLayerStairs
            index_of_interacting_tile.* = tile;
            or16(tiledetect_inroom_staircase, b);
            or8(tiledetect_stair_tile, b);
        },
        // TileBehavior_Pit
        0x20, 0xb0...0xbd => {
            if (player_on_somaria_platform.* == 0)
                or8(tiledetect_pit_tile, b);
        },
        // TileHandlerIndoor_22
        0x22, 0x30...0x37 => or8(tiledetect_stair_tile, b),
        0x27 => { // TileBehavior_Hookshottables
            or16(R14, b);
            or16(tiledetect_misc_tiles, b);
        },
        0x28 => { // TileBehavior_Ledge_North
            index_of_interacting_tile.* = tile;
            or8(tiledetect_vertical_ledge, b);
        },
        0x29 => { // TileBehavior_Ledge_South
            index_of_interacting_tile.* = tile;
            or8(tiledetect_vertical_ledge, b << 4);
        },
        0x2a, 0x2b => { // TileBehavior_Ledge_EastWest
            index_of_interacting_tile.* = tile;
            or8(detection_of_ledge_tiles_horiz_uphoriz, b);
        },
        0x2c, 0x2e => { // TileBehavior_Ledge_NorthDiagonal
            index_of_interacting_tile.* = tile;
            or8(detection_of_ledge_tiles_horiz_uphoriz, b << 4);
        },
        0x2d, 0x2f => { // TileBehavior_Ledge_SouthDiagonal
            index_of_interacting_tile.* = tile;
            or8(tiledetect_ledges_down_leftright, b);
        },
        0x3d, 0x3e, 0x3f => { // TileHandlerIndoor_3E
            index_of_interacting_tile.* = tile;
            or16(tiledetect_inroom_staircase, b << 4);
            or8(tiledetect_stair_tile, b);
        },
        0x40 => or16(tiledetect_thick_grass, b), // TileBehavior_ThickGrass
        0x44 => { // TileBehavior_Spike
            if (flag_block_link_menu.* == 0 and (dung_savegame_state_bits.* & 0x8000) == 0)
                or8(bitfield_spike_cactus_tiles, b)
            else
                or16(R14, b);
        },
        0x46 => { // TileBehavior_HylianPlaque
            or8(tiledetect_spike_floor_and_tile_triggers, b);
            or16(R14, b);
        },
        0x48, 0x4a => { // TileBehavior_DiggableGround
            or16(tiledetect_destruction_aftermath, b);
            or16(tiledetect_normal_tiles, b);
        },
        0x4b => or16(tiledetect_thick_grass, b << 4), // TileBehavior_Warp
        0x50...0x56 => { // TileBehavior_Liftable
            const kTile50data = [7]u8{ 0x54, 0x52, 0x50, 0x51, 0x53, 0x55, 0x56 };
            var i: i32 = 6;
            while (i >= 0) : (i -= 1) {
                if (kTile50data[@intCast(i)] == tile) {
                    if (tile == 0x50 or tile == 0x51)
                        or8(bitmask_for_dashable_tiles, b << 4);
                    or16(tiledetect_read_something, b);
                    interacting_with_liftable_tile_x2.* = @intCast(i * 2);
                    or16(R14, b);
                    or16(tiledetect_misc_tiles, b);
                    break;
                }
            }
        },
        0x57 => { // TileBehavior_BonkRocks
            or16(R14, b);
            or8(bitmask_for_dashable_tiles, b << 4);
        },
        0x58...0x5d => { // TileBehavior_Chest
            or16(tiledetect_misc_tiles, b);
            index_of_interacting_tile.* = tile;
            if (dung_chest_locations[tile - 0x58] >= 0x8000) {
                or16(R14, b);
                or8(tiledetect_key_lock_gravestones, b << 4);
                if (bits & 2 != 0)
                    tiledetect_tile_type.* = tile;
            } else {
                or16(tiledetect_chest, b); // small key lock
                or16(R14, b);
            }
        },
        0x60 => { // TileBehavior_RupeeTile
            if (is_indoors) {
                if (dung_bg2_attr_table[offs +% 64] == 0x60) {
                    or16(tiledetect_misc_tiles, b << 8);
                } else {
                    or16(tiledetect_misc_tiles, b << 12);
                }
            } else {
                or16(tiledetect_normal_tiles, b);
            }
        },
        0x63 => { // TileBehavior_MinigameChest
            or16(tiledetect_misc_tiles, b);
            index_of_interacting_tile.* = tile;
            or16(tiledetect_chest, b); // small key lock
            or16(R14, b);
        },
        0x67 => { // TileBehavior_CrystalPeg_Up
            or16(R14, b);
            or16(tiledetect_misc_tiles, b);
            or8(bitfield_spike_cactus_tiles, b << 4);
        },
        0x68 => or16(tiledetect_var4, b), // TileBehavior_Conveyor_Upwards
        0x69 => or16(tiledetect_var4, b << 4), // TileBehavior_Conveyor_Downwards
        0x6a => or16(tiledetect_var4, b << 8), // TileBehavior_Conveyor_Leftwards
        0x6b => or16(tiledetect_var4, b << 12), // TileBehavior_Conveyor_Rightwards
        0x70...0x7f => { // TileBehavior_ManipulablyReplaced
            if (bits & 2 != 0)
                or16(tiledetect_var2, @as(u32, 1) << @intCast(tile & 0xf));
            or16(R14, b);
            or16(tiledetect_misc_tiles, b);
        },
        // TileHandlerIndoor_80
        0x80, 0x81, 0x84...0x8d => {
            or16(R14, b << 4);
            tiledetect_var1.* = 2 * @as(u16, tile & 1);
        },
        0x82, 0x83 => { // TileHandlerIndoor_82
            or16(R14, (b << 4) | (b << 8));
            tiledetect_var1.* = 2 * @as(u16, tile & 1);
        },
        0x8e, 0x8f => { // TileBehavior_Entrance
            or16(R14, b << 4);
            or8(bitmask_for_dashable_tiles, b);
            tiledetect_var1.* = 0;
        },
        0x90...0x97 => { // TileBehavior_LayerToggleShutterDoor
            room_transitioning_flags.* = 1;
            or16(R14, (b << 4) | (b << 8));
            tiledetect_var1.* = 2 * @as(u16, tile & 1);
        },
        // TileBehavior_LayerAndDungeonToggleShutterDoor
        0x98...0x9f, 0xa8...0xaf => {
            room_transitioning_flags.* = 3;
            or16(R14, (b << 4) | (b << 8));
            tiledetect_var1.* = 2 * @as(u16, tile & 1);
        },
        0xa0, 0xa1, 0xa4, 0xa5 => { // TileBehavior_DungeonToggleManualDoor
            room_transitioning_flags.* = 2;
            or16(R14, b << 4);
            tiledetect_var1.* = 2 * @as(u16, tile & 1);
        },
        0xa2, 0xa3 => { // TileBehavior_DungeonToggleShutterDoor
            room_transitioning_flags.* = 2;
            or16(R14, (b << 4) | (b << 8));
            tiledetect_var1.* = 2 * @as(u16, tile & 1);
        },
        0xc0...0xcf => { // TileBehavior_LightableTorch
            or16(R14, b);
            or16(tiledetect_misc_tiles, b);
        },
        0xf0...0xff => { // TileBehavior_FlaggableDoor
            or16(R14, b);
            or16(tiledetect_misc_tiles, b << 4);
        },
        0x42 => { // TileBehavior_GraveStone
            if (!is_indoors) {
                or8(tiledetect_key_lock_gravestones, b);
                or16(R14, b);
            }
        },
        0x4c, 0x4d => { // TileBehavior_UnusedCornerType
            if (!is_indoors) {
                index_of_interacting_tile.* = tile;
                or8(detection_of_unknown_tile_types, b);
            }
        },
        0x4e, 0x4f => { // TileBehavior_EasternRuinsCorner
            if (!is_indoors) {
                index_of_interacting_tile.* = tile;
                or8(detection_of_unknown_tile_types, b << 4);
            }
        },
        // The C ends with `default: assert(0)`, but every one of the 256
        // behaviour values is handled above, so that assert can never fire --
        // and Zig proves the switch exhaustive without an else prong.
    }
}

const testing = std.testing;

/// The detection routines read and write flat work ram, so a test just has to
/// clear the region it cares about first.
fn resetRam() void {
    @memset(vars.g_ram[0..0x1000], 0);
    cheatWalkThroughWalls.* = 0;
    player_is_indoors.* = 0;
    flag_block_link_menu.* = 0;
    dung_savegame_state_bits.* = 0;
    player_on_somaria_platform.* = 0;
}

test "TileDetect_ResetState clears every detection mask" {
    resetRam();
    R12.* = 0xffff;
    R14.* = 0xffff;
    tiledetect_misc_tiles.* = 0xffff;
    tiledetect_vertical_ledge.* = 0xff;
    bitmask_for_dashable_tiles.* = 0xff;
    tiledetect_var4.* = 0xffff;

    TileDetect_ResetState();

    try testing.expectEqual(@as(u16, 0), R12.*);
    try testing.expectEqual(@as(u16, 0), R14.*);
    try testing.expectEqual(@as(u16, 0), tiledetect_misc_tiles.*);
    try testing.expectEqual(@as(u8, 0), tiledetect_vertical_ledge.*);
    try testing.expectEqual(@as(u8, 0), bitmask_for_dashable_tiles.*);
    try testing.expectEqual(@as(u16, 0), tiledetect_var4.*);
}

test "solid tiles set the collision mask" {
    resetRam();
    TileDetect_ExecuteInner(0x01, 0, 4, true);
    try testing.expectEqual(@as(u16, 4), R14.*);
    // The bits accumulate across the several probe points of one step.
    TileDetect_ExecuteInner(0x02, 0, 1, true);
    try testing.expectEqual(@as(u16, 5), R14.*);
}

test "walkable overworld tiles only register outdoors" {
    resetRam();
    TileDetect_ExecuteInner(0x00, 0, 1, false);
    try testing.expectEqual(@as(u16, 1), tiledetect_normal_tiles.*);

    TileDetect_ResetState();
    TileDetect_ExecuteInner(0x00, 0, 1, true);
    try testing.expectEqual(@as(u16, 0), tiledetect_normal_tiles.*);
}

test "tile 0x04 is grass outdoors but a wall indoors" {
    resetRam();
    TileDetect_ExecuteInner(0x04, 0, 1, false);
    try testing.expectEqual(@as(u16, 1), tiledetect_thick_grass.*);
    try testing.expectEqual(@as(u16, 0), R14.*);

    TileDetect_ResetState();
    TileDetect_ExecuteInner(0x04, 0, 1, true);
    try testing.expectEqual(@as(u16, 1), R14.*);
    try testing.expectEqual(@as(u16, 0), tiledetect_thick_grass.*);
}

test "water, ice and pits land in their own masks" {
    resetRam();
    TileDetect_ExecuteInner(0x08, 0, 1, false); // deep water
    try testing.expectEqual(@as(u16, 1), tiledetect_deepwater.*);
    TileDetect_ExecuteInner(0x09, 0, 2, false); // shallow water
    try testing.expectEqual(@as(u16, 2), tiledetect_shallow_water.*);
    TileDetect_ExecuteInner(0x0e, 0, 1, true); // ganon ice
    try testing.expectEqual(@as(u16, 1), tiledetect_icy_floor.*);
    TileDetect_ExecuteInner(0x0f, 0, 1, true); // palace ice, shifted up a nibble
    try testing.expectEqual(@as(u16, 0x11), tiledetect_icy_floor.*);
    TileDetect_ExecuteInner(0x20, 0, 4, true); // pit
    try testing.expectEqual(@as(u8, 4), tiledetect_pit_tile.*);
}

test "a somaria platform suppresses pit detection" {
    resetRam();
    player_on_somaria_platform.* = 1;
    TileDetect_ExecuteInner(0x20, 0, 4, true);
    try testing.expectEqual(@as(u8, 0), tiledetect_pit_tile.*);
}

test "slopes record which diagonal they are" {
    resetRam();
    TileDetect_ExecuteInner(0x10, 0, 1, true);
    try testing.expectEqual(@as(u16, 1), R12.*);
    try testing.expectEqual(@as(u16, 4), tiledetect_diag_state.*); // word_87DC55[0]
    TileDetect_ExecuteInner(0x13, 0, 1, true);
    try testing.expectEqual(@as(u16, 2), tiledetect_diag_state.*); // word_87DC55[3]

    // The outer variants also flag the diagonal tile itself.
    TileDetect_ResetState();
    TileDetect_ExecuteInner(0x18, 0, 2, true);
    try testing.expectEqual(@as(u16, 2), tiledetect_diagonal_tile.*);
    try testing.expectEqual(@as(u16, 2), R12.*);
}

test "ledges split by direction" {
    resetRam();
    TileDetect_ExecuteInner(0x28, 0, 1, true); // north
    try testing.expectEqual(@as(u8, 1), tiledetect_vertical_ledge.*);
    try testing.expectEqual(@as(u16, 0x28), index_of_interacting_tile.*);

    TileDetect_ResetState();
    TileDetect_ExecuteInner(0x29, 0, 1, true); // south, shifted up a nibble
    try testing.expectEqual(@as(u8, 0x10), tiledetect_vertical_ledge.*);

    TileDetect_ResetState();
    TileDetect_ExecuteInner(0x2a, 0, 1, true); // east/west
    try testing.expectEqual(@as(u8, 1), detection_of_ledge_tiles_horiz_uphoriz.*);
}

test "spikes are harmless while the menu is blocked" {
    resetRam();
    TileDetect_ExecuteInner(0x44, 0, 1, true);
    try testing.expectEqual(@as(u8, 1), bitfield_spike_cactus_tiles.*);
    try testing.expectEqual(@as(u16, 0), R14.*);

    TileDetect_ResetState();
    flag_block_link_menu.* = 1;
    TileDetect_ExecuteInner(0x44, 0, 1, true);
    try testing.expectEqual(@as(u8, 0), bitfield_spike_cactus_tiles.*);
    try testing.expectEqual(@as(u16, 1), R14.*); // becomes solid instead
}

test "liftable tiles report their index into the lift table" {
    resetRam();
    TileDetect_ExecuteInner(0x50, 0, 1, true);
    // kTile50data[2] == 0x50, so the index is 2 and the doubled value is 4.
    try testing.expectEqual(@as(u8, 4), interacting_with_liftable_tile_x2.*);
    try testing.expectEqual(@as(u16, 1), tiledetect_read_something.*);
    try testing.expectEqual(@as(u16, 1), R14.*);
    // 0x50 and 0x51 are also dashable.
    try testing.expectEqual(@as(u8, 0x10), bitmask_for_dashable_tiles.*);

    TileDetect_ResetState();
    TileDetect_ExecuteInner(0x56, 0, 1, true);
    try testing.expectEqual(@as(u8, 12), interacting_with_liftable_tile_x2.*); // index 6
    try testing.expectEqual(@as(u8, 0), bitmask_for_dashable_tiles.*);
}

test "a chest is a lock when its location word has the high bit set" {
    resetRam();
    dung_chest_locations[0] = 0x8000;
    TileDetect_ExecuteInner(0x58, 0, 2, true);
    try testing.expectEqual(@as(u8, 0x20), tiledetect_key_lock_gravestones.*);
    try testing.expectEqual(@as(u16, 0x58), tiledetect_tile_type.*);
    try testing.expectEqual(@as(u16, 0), tiledetect_chest.*);

    TileDetect_ResetState();
    dung_chest_locations[1] = 0x0001;
    TileDetect_ExecuteInner(0x59, 0, 2, true);
    try testing.expectEqual(@as(u16, 2), tiledetect_chest.*);
}

test "conveyors pick a nibble per direction" {
    resetRam();
    TileDetect_ExecuteInner(0x68, 0, 1, true);
    try testing.expectEqual(@as(u16, 0x0001), tiledetect_var4.*);
    TileDetect_ExecuteInner(0x69, 0, 1, true);
    try testing.expectEqual(@as(u16, 0x0011), tiledetect_var4.*);
    TileDetect_ExecuteInner(0x6a, 0, 1, true);
    try testing.expectEqual(@as(u16, 0x0111), tiledetect_var4.*);
    TileDetect_ExecuteInner(0x6b, 0, 1, true);
    try testing.expectEqual(@as(u16, 0x1111), tiledetect_var4.*);
}

test "shutter doors set the transition flags" {
    resetRam();
    TileDetect_ExecuteInner(0x90, 0, 1, true);
    try testing.expectEqual(@as(u8, 1), room_transitioning_flags.*);
    try testing.expectEqual(@as(u16, 0x110), R14.*); // bits << 4 | bits << 8

    TileDetect_ResetState();
    TileDetect_ExecuteInner(0x98, 0, 1, true);
    try testing.expectEqual(@as(u8, 3), room_transitioning_flags.*);

    TileDetect_ResetState();
    TileDetect_ExecuteInner(0xa2, 0, 1, true);
    try testing.expectEqual(@as(u8, 2), room_transitioning_flags.*);
}

test "the rupee tile checks the tile below it" {
    resetRam();
    // Two rupee tiles stacked: the upper one reports in bits 8-11.
    dung_bg2_attr_table[64] = 0x60;
    TileDetect_ExecuteInner(0x60, 0, 1, true);
    try testing.expectEqual(@as(u16, 0x100), tiledetect_misc_tiles.*);

    TileDetect_ResetState();
    dung_bg2_attr_table[64] = 0x00;
    TileDetect_ExecuteInner(0x60, 0, 1, true);
    try testing.expectEqual(@as(u16, 0x1000), tiledetect_misc_tiles.*);
}

test "walking through walls turns every tile into open floor" {
    resetRam();
    cheatWalkThroughWalls.* = 1;
    TileDetect_ExecuteInner(0x01, 0, 1, true); // normally solid
    try testing.expectEqual(@as(u16, 0), R14.*);
}

test "indoor detection reads the dungeon attribute table" {
    resetRam();
    player_is_indoors.* = 1;
    link_is_on_lower_level.* = 0;
    tilemap_location_calc_mask.* = 0x1ff;
    // offs = (y & ~7) * 8 + (x & 63)
    dung_bg2_attr_table[8 * 8 + 3] = 0x01; // a solid tile
    TileDetection_Execute(3, 8, 1);
    try testing.expectEqual(@as(u16, 1), R14.*);
    try testing.expectEqual(@as(u8, 0x01), link_tile_below.*);

    // The upper level is offset by 0x1000 in the same table.
    TileDetect_ResetState();
    link_is_on_lower_level.* = 1;
    dung_bg2_attr_table[0x1000 + 8 * 8 + 3] = 0x08; // deep water
    TileDetection_Execute(3, 8, 1);
    try testing.expectEqual(@as(u16, 1), tiledetect_deepwater.*);
}

test "the probe offset tables came over intact" {
    try testing.expectEqualSlices(u8, &.{ 8, 24, 0, 15 }, &kDetectTiles_tab0);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 8, 8 }, &kDetectTiles_tab1);
    try testing.expectEqualSlices(u8, &.{ 8, 8, 16, 16 }, &kDetectTiles_tab2);
    try testing.expectEqualSlices(u8, &.{ 15, 15, 23, 23 }, &kDetectTiles_tab3);
    try testing.expectEqualSlices(i8, &.{ 7, 24, -1, 16 }, &kDetectTiles_tab4);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 8, 8 }, &kDetectTiles_tab5);
    try testing.expectEqualSlices(u8, &.{ 15, 15, 23, 23 }, &kDetectTiles_tab6);
}
