//! Handwritten dungeon room rendering, transitions, room interactions, object
//! drawing, door construction and the dungeon submodule state machine.
//!
//! Merged from the dungeon_partN modules the port was written in. Those files
//! reached each other's exports through extern declarations; sharing a file now,
//! those calls resolve directly. File-local helpers that had incompatible
//! signatures across parts, shadowed an exported name, or collided with a
//! parameter name keep suffixed names rather than being unified.

extern fn SrcPtr(src: u16) Tiles;
extern fn printf(fmt: [*:0]const u8, ...) c_int;
const std = @import("std");
const v = @import("variables.zig");
const t = @import("dungeon_tables.zig");
const main = @import("main.zig");
const c = @import("dungeon_abi.zig");
const overworld = @import("overworld.zig");
const dungeon_wide = @import("dungeon_wide.zig");
const Words = [*]align(1) u16;
const Tiles = [*]align(1) const u16;
const RoomBounds = v.RoomBounds;
const DungPalInfo = t.DungPalInfo;
fn xy(x: usize, y: usize) usize {
    return y * 64 + x;
}
fn low(p: anytype) *u8 {
    return @ptrCast(p);
}
fn high(p: anytype) *u8 {
    return @ptrCast(@as([*]u8, @ptrCast(p)) + 1);
}
fn word(p: anytype) *align(1) u16 {
    return @ptrCast(p);
}
fn u8w(a: anytype) u8 {
    return @truncate(@as(u64, @bitCast(@as(i64, a))));
}
fn u16w(a: anytype) u16 {
    return @truncate(@as(u64, @bitCast(@as(i64, a))));
}
fn index(a: anytype) usize {
    return @intCast(a);
}
fn asset8(comptime n: usize) [*]const u8 {
    return main.g_asset_ptrs[n].?;
}
fn asset16(comptime n: usize) Tiles {
    return @ptrCast(asset8(n));
}
fn both(at: usize, tile: u16) void {
    v.dung_bg1[at] = tile;
    v.dung_bg2[at] = tile;
}
fn drawRows(src: Tiles, dst: Words, width: usize, height: usize) void {
    for (0..height) |y| for (0..width) |x| {
        dst[xy(x, y)] = src[y * width + x];
    };
}
fn drawColumns(src: Tiles, dst: Words, width: usize, height: usize) void {
    for (0..width) |x| for (0..height) |y| {
        dst[xy(x, y)] = src[x * height + y];
    };
}
fn priority(dsto: u16, width: usize, height: usize) void {
    for (0..height) |y| for (0..width) |x| {
        v.dung_bg2[dsto + xy(x, y)] |= 0x2000;
    };
}
fn saveReplacement(i: usize, src: Tiles) void {
    v.replacement_tilemap_UL[i] = src[0];
    v.replacement_tilemap_LL[i] = src[1];
    v.replacement_tilemap_UR[i] = src[2];
    v.replacement_tilemap_LR[i] = src[3];
}
fn addReplacement(state: u16, dsto: u16) usize {
    const i: usize = v.dung_misc_objs_index.* >> 1;
    v.dung_misc_objs_index.* +%= 2;
    v.dung_replacement_tile_state[i] = state;
    v.dung_object_pos_in_objdata[i] = v.dung_load_ptr_offs.*;
    v.dung_object_tilemap_pos[i] = dsto *% 2 | @as(u16, if (v.dung_line_ptrs_row0.* == 0x4000) 0x2000 else 0);
    return i;
}
fn WriteAttr1_d0(j: usize, attr: u16) void {
    v.dung_bg1_attr_table[j] = @truncate(attr);
    v.dung_bg1_attr_table[j + 1] = @truncate(attr >> 8);
}
fn WriteAttr2_d0(j: usize, attr: u16) void {
    v.dung_bg2_attr_table[j] = @truncate(attr);
    v.dung_bg2_attr_table[j + 1] = @truncate(attr >> 8);
}
fn prepareQuadrant(bg: Words, extra: u8) void {
    const ofs = (v.overworld_screen_transition.* & 15) + v.dung_cur_quadrant_upload.*;
    const src = bg + t.kUploadBgSrcs[ofs] / 2;
    const dst: Words = @ptrCast(&v.g_ram[0x1000]);
    for (0..32) |y| for (0..32) |x| {
        dst[y * 32 + x] = src[y * 64 + x];
    };
    low(v.nmi_load_target_addr).* = t.kUploadBgDsts[ofs] + extra;
    v.nmi_subroutine_index.* = 1;
    v.nmi_disable_core_updates.* = 1;
}
fn litObjects() u8 {
    var count: u8 = 0;
    for (v.dung_object_tilemap_pos[0..16]) |p| {
        count += @intFromBool(p & 0x8000 != 0);
    }
    return count;
}
fn shiftRoomAxis(comptime horizontal: bool, delta: u16) void {
    const pos = if (horizontal) v.link_x_coord else v.link_y_coord;
    const bg = if (horizontal) v.BG2HOFS_copy2 else v.BG2VOFS_copy2;
    const bounds = if (horizontal) v.room_bounds_x else v.room_bounds_y;
    pos.* +%= delta;
    bg.* +%= delta;
    for (&bounds.v) |*b| b.* +%= delta;
}
fn fullSizeX() u8 {
    return if (v.dung_blastwall_flag_x.* != 0 or t.kLayoutQuadrantFlags[v.composite_of_layout_and_quadrant.*] & @as(u8, if (v.link_quadrant_x.* != 0) 2 else 1) == 0) 2 else 0;
}
fn fullSizeY() u8 {
    return if (v.dung_blastwall_flag_y.* != 0 or t.kLayoutQuadrantFlags[v.composite_of_layout_and_quadrant.*] & @as(u8, if (v.link_quadrant_y.* != 0) 8 else 4) == 0) 2 else 0;
}
fn transitionLayer() void {
    v.submodule_index.* = 2;
    if (v.room_transitioning_flags.* & 1 != 0) {
        v.link_is_on_lower_level.* ^= 1;
        v.link_is_on_lower_level_mirror.* = v.link_is_on_lower_level.*;
    }
    if (v.room_transitioning_flags.* & 2 != 0) v.cur_palace_index_x2.* ^= 2;
}
fn startHorizontal(comptime right: bool) void {
    std.debug.assert(v.submodule_index.* == 0);
    dungeon_wide.noteTransitionStart(if (right) 2 else 3);
    v.link_quadrant_x.* ^= 1;
    Dungeon_AdjustQuadrant();
    if (right) RoomBounds_AddA(v.room_bounds_x) else RoomBounds_SubA(v.room_bounds_x);
    Dung_SaveDataForCurrentRoom();
    DungeonTransition_AdjustCamera_X(v.link_quadrant_x.* ^ @as(u8, if (right) 0 else 1));
    HandleEdgeTransition_AdjustCameraBoundaries(if (right) 2 else 3);
    v.submodule_index.* = 1;
    if ((v.link_quadrant_x.* == 0) == right) {
        if (right) RoomBounds_AddB(v.room_bounds_x) else RoomBounds_SubB(v.room_bounds_x);
        low(v.dungeon_room_index_prev).* = u8w(v.dungeon_room_index.*);
        if (v.link_tile_below.* & 0xcf == 0x89) {
            v.dungeon_room_index.* = v.dung_hdr_travel_destinations[if (right) 4 else 3];
            Dungeon_AdjustForTeleportDoors(u8w(v.dungeon_room_index.* +% @as(u16, if (right) 0xffff else 1)), if (right) 1 else 0xff);
        } else {
            if (u8w(v.dungeon_room_index.*) != u8w(v.dungeon_room_index2.*)) {
                low(v.dungeon_room_index_prev).* = u8w(v.dungeon_room_index2.*);
                Dungeon_AdjustAfterSpiralStairs();
            }
            v.dungeon_room_index.* +%= if (right) 1 else 0xffff;
        }
        transitionLayer();
    }
    v.room_transitioning_flags.* = 0;
    v.quadrant_fullsize_y.* = fullSizeY();
}
fn startVertical(comptime down: bool) void {
    std.debug.assert(v.submodule_index.* == 0);
    dungeon_wide.noteTransitionStart(if (down) 0 else 1);
    v.link_quadrant_y.* ^= 2;
    Dungeon_AdjustQuadrant();
    if (down) RoomBounds_AddA(v.room_bounds_y) else RoomBounds_SubA(v.room_bounds_y);
    Dung_SaveDataForCurrentRoom();
    DungeonTransition_AdjustCamera_Y(v.link_quadrant_y.* ^ @as(u8, if (down) 0 else 2));
    HandleEdgeTransition_AdjustCameraBoundaries(if (down) 0 else 1);
    v.submodule_index.* = 1;
    if ((v.link_quadrant_y.* == 0) == down) {
        if (down) RoomBounds_AddB(v.room_bounds_y) else RoomBounds_SubB(v.room_bounds_y);
        low(v.dungeon_room_index_prev).* = u8w(v.dungeon_room_index.*);
        if (v.link_tile_below.* == 0x8e) {
            Dung_HandleExitToOverworld();
            return;
        }
        if (!down and v.dungeon_room_index.* == 0) {
            SaveDungeonKeys();
            v.main_module_index.* = 25;
            v.submodule_index.* = 0;
            v.subsubmodule_index.* = 0;
            return;
        }
        // The northward source compares for equality; preserve that behavior.
        if ((u8w(v.dungeon_room_index.*) != u8w(v.dungeon_room_index2.*)) == down) {
            low(v.dungeon_room_index_prev).* = u8w(v.dungeon_room_index2.*);
            Dungeon_AdjustAfterSpiralStairs();
        }
        low(v.dungeon_room_index).* +%= if (down) 16 else 0xf0;
        transitionLayer();
    }
    v.room_transitioning_flags.* = 0;
    v.quadrant_fullsize_x.* = fullSizeX();
}
fn markQuadrant() void {
    v.dung_quadrants_visited.* |= t.kQuadrantVisitingFlags[(v.quadrant_fullsize_y.* << 2) + (v.quadrant_fullsize_x.* << 1) + v.link_quadrant_y.* + v.link_quadrant_x.*];
}
fn scrollCameraAxis(comptime horizontal: bool) void {
    const velocity = if (horizontal) v.link_x_vel.* else v.link_y_vel.*;
    if (velocity == 0) return;
    const negative = velocity & 0x80 != 0;
    const iterations: usize = if (negative) 256 - @as(usize, velocity) else velocity;
    const z: u16 = if (!horizontal and v.allow_scroll_z.* != 0 and v.link_z_coord.* != 0xffff) v.link_z_coord.* else 0;
    const pos = (((if (horizontal) v.link_x_coord.* else v.link_y_coord.*) -% z) & 0x1ff) + @as(u16, if (horizontal) 8 else 12);
    const full = if (horizontal) v.quadrant_fullsize_x else v.quadrant_fullsize_y;
    const low_bound = if (horizontal) v.camera_x_coord_scroll_low else v.camera_y_coord_scroll_low;
    const hi_bound = if (horizontal) v.camera_x_coord_scroll_hi else v.camera_y_coord_scroll_hi;
    const bg2 = if (horizontal) v.BG2HOFS_copy2 else v.BG2VOFS_copy2;
    const bounds = if (horizontal) v.room_bounds_x else v.room_bounds_y;
    for (0..iterations) |_| {
        if (if (negative) pos > low_bound.* else pos < hi_bound.*) continue;
        const q = (full.* >> 1) + @as(u8, if (negative) 0 else 2);
        const stop = if (horizontal and overworld.wideCameraOn())
            (if (negative) bg2.* <= bounds.v[q] +% wideRoomMargin() else bg2.* >= bounds.v[q] -% wideRoomMargin())
        else
            bg2.* == bounds.v[q];
        if (stop) continue;
        stepCameraAxis(horizontal, negative);
    }
}
/// Moves the camera a pixel along one axis, and with it where Link has to be
/// for it to follow him.
fn stepCameraAxis(comptime horizontal: bool, negative: bool) void {
    const amount: u16 = if (negative) 0xffff else 1;
    const low_bound = if (horizontal) v.camera_x_coord_scroll_low else v.camera_y_coord_scroll_low;
    const hi_bound = if (horizontal) v.camera_x_coord_scroll_hi else v.camera_y_coord_scroll_hi;
    const bg2 = if (horizontal) v.BG2HOFS_copy2 else v.BG2VOFS_copy2;
    const bg1 = if (horizontal) v.BG1HOFS_copy2 else v.BG1VOFS_copy2;
    const subpixel = if (horizontal) v.BG1HOFS_subpixel else v.BG1VOFS_subpixel;
    bg2.* +%= amount;
    if (v.dungeon_room_index.* == 0xffff) return;
    subpixel.* +%= 0x8000;
    bg1.* +%= @as(u16, if (negative) 0xffff else 0) +% @intFromBool(subpixel.* & 0x8000 == 0);
    low_bound.* +%= amount;
    hi_bound.* = low_bound.* +% 2;
}
/// Widescreen: how far in from a room's left and right edges the camera
/// stops, so the room fills the wider screen out to its walls instead of
/// ending where a 4:3 screen does. Only a room the camera can scroll across
/// has one; one a 4:3 screen wide has nothing beside it to show.
fn wideRoomMargin() u16 {
    if (!overworld.wideCameraOn()) return 0;
    const qm: usize = v.quadrant_fullsize_x.* >> 1;
    return overworld.wideCameraMargin(v.room_bounds_x.v[qm + 2] -% v.room_bounds_x.v[qm]);
}
/// Widescreen: brings the camera into its range when it's outside it, as it
/// is when a room's just been entered, at the speed a room's scroll goes.
/// Off (kGlideIntoWideRooms): gliding by itself after a scroll into a wide
/// room felt janky, so the camera stays where the 4:3 one leaves it and
/// comes into range only as it follows Link.
fn settleRoomCameraX() void {
    if (!kGlideIntoWideRooms) return;
    const m = wideRoomMargin();
    if (m == 0) return;
    const qm: usize = v.quadrant_fullsize_x.* >> 1;
    const lo = v.room_bounds_x.v[qm] +% m;
    const hi = v.room_bounds_x.v[qm + 2] -% m;
    for (0..kRoomSettleSpeed) |_| {
        const cam = v.BG2HOFS_copy2.*;
        if (cam < lo) stepCameraAxis(true, false) else if (cam > hi) stepCameraAxis(true, true) else return;
    }
}
const kRoomSettleSpeed = 4;
/// Out of (or into) a dark room, the screen fades out before the scroll and
/// back in after it, the scroll itself in the dark. Widescreen: the fade
/// back in starts over the scroll's second half instead, a step every other
/// frame, so the room's coming up as it slides in. It stops short, at
/// kFadeInLeftAfterScroll steps to go: the steps after the scroll take a few
/// more on the way, and the last of them, finishing the fade, has to come at
/// the fade the game saved it for, which moves on to the next step.
fn fadeInDuringScroll(at: u16, target: u16, delta: u16) void {
    if (!dungeon_wide.enabled()) return;
    if (v.dung_want_lights_out.* | v.dung_want_lights_out_copy.* == 0) return;
    if (v.darkening_or_lightening_screen.* != 2) return; // fading in is next
    const countdown = low(v.palette_filter_countdown).*;
    if (countdown <= kFadeInLeftAfterScroll) return;
    const negative = delta & 0x8000 != 0;
    const step: u16 = if (negative) 0 -% delta else delta;
    const frames_left = ((if (negative) at -% target else target -% at) & 0x1ff) / step;
    // A step every other frame, so it's done as the scroll lands.
    const steps_left = countdown - kFadeInLeftAfterScroll;
    if (frames_left <= steps_left * 2 and frames_left & 1 == 0) c.ApplyPaletteFilter_bounce();
}
const kFadeInLeftAfterScroll = 0x0c;

/// Widescreen: the camera where a sideways scroll stops, a margin in from the
/// room's edge if the room's wide, or the 4:3 one's place if not. The scroll
/// has that place as an x within the 512 pixels of a room; this is the first
/// x the scroll gets to that has it, give or take the few pixels its steps
/// can leave it off by. From the scroll's own target, since the same scroll
/// also takes the camera between two parts of one room.
fn wideScrollEndX(leftward: bool, cam: u16) u16 {
    const targets: Tiles = @ptrCast(v.up_down_scroll_target);
    const t43 = targets[if (leftward) 3 else 2];
    const m = wideRoomMargin();
    const want = (if (leftward) t43 -% m else t43 +% m) & 0x1ff;
    return if (leftward)
        (cam +% 4) -% (((cam +% 4) -% want) & 0x1ff)
    else
        (cam -% 4) +% ((want -% (cam -% 4)) & 0x1ff);
}
/// Puts the camera exactly where a sideways scroll into the room stops, the
/// few pixels its steps fall short, and moves where Link has to be for it to
/// follow him on by the margin it's gone past the 4:3 one's place, so it
/// doesn't hold him that far off center.
fn landWideCamera(leftward: bool) void {
    if (!overworld.wideCameraOn()) return;
    const m = wideRoomMargin();
    // Even into a 4:3 room: a wide room's camera can start the scroll at an
    // odd x, and the steps keep it odd, 2 pixels off the room's edge.
    const to = wideScrollEndX(leftward, v.BG2HOFS_copy2.*);
    v.BG2HOFS_copy2.* = to;
    v.BG1HOFS_copy2.* = to;
    const shift: u16 = if (leftward) 0 -% m else m;
    v.camera_x_coord_scroll_low.* +%= shift;
    v.camera_x_coord_scroll_hi.* = v.camera_x_coord_scroll_low.* +% 2;
}
/// Widescreen: where the room's camera range puts the camera's x from here:
/// the nearest x in its range, which for a 4:3 room is the only one.
fn roomCameraX(cam: u16) u16 {
    const m = wideRoomMargin();
    const qm: usize = v.quadrant_fullsize_x.* >> 1;
    const lo = v.room_bounds_x.v[qm] +% m;
    const hi = v.room_bounds_x.v[qm + 2] -% m;
    return if (cam < lo) lo else if (cam > hi) hi else cam;
}
/// Puts the camera's x straight into the room's range, and where Link has
/// to be for it to follow him with it, for rooms reached behind a fade:
/// stairs, falling, warp tiles, and coming in from outside. The camera keeps the x it had in the room
/// before, which the widescreen one can have up to a margin off where the
/// 4:3 one would, and this room's range may not include it.
fn snapRoomCameraX() void {
    if (!overworld.wideCameraOn()) return;
    const cam = v.BG2HOFS_copy2.*;
    const d = roomCameraX(cam) -% cam;
    v.BG2HOFS_copy2.* +%= d;
    v.BG1HOFS_copy2.* +%= d;
    v.camera_x_coord_scroll_low.* +%= d;
    v.camera_x_coord_scroll_hi.* = v.camera_x_coord_scroll_low.* +% 2;
}
/// Moves the camera's x a share of the way to the room's range, to get
/// there in `steps` more, and where Link has to be for it to follow him with
/// it.
fn slideCameraXToRoom(steps: u16) void {
    const cam = v.BG2HOFS_copy2.*;
    const to = roomCameraX(cam);
    if (to == cam) return;
    const gap: u16 = if (to > cam) to - cam else cam - to;
    const n: u16 = (gap + steps - 1) / steps;
    const d: u16 = if (to > cam) n else 0 -% n;
    v.BG2HOFS_copy2.* +%= d;
    v.BG1HOFS_copy2.* +%= d;
    v.camera_x_coord_scroll_low.* +%= d;
    v.camera_x_coord_scroll_hi.* = v.camera_x_coord_scroll_low.* +% 2;
}
/// Widescreen: the margins while a room-to-room scroll runs, for
/// widescreenSideSpace; null when there isn't one to do this for.
pub fn wideTransitionMargins(max: c_int) ?dungeon_wide.Margins {
    const i = dungeon_wide.transitionDir() orelse return null;
    const cam_x: i32 = v.BG2HOFS_copy2.*;
    const cam_y: i32 = v.BG2VOFS_copy2.*;
    var end_x = cam_x;
    var end_y = cam_y;
    if (i >= 2) {
        end_x = wideScrollEndX(i == 3, v.BG2HOFS_copy2.*);
    } else {
        const targets: Tiles = @ptrCast(v.up_down_scroll_target);
        const origin = dungeon_wide.shownOrigin() orelse return null;
        end_y = origin.y + (targets[i] & 0x1fc);
        end_x = roomCameraX(v.BG2HOFS_copy2.*);
    }
    const qm: usize = v.quadrant_fullsize_x.* >> 1;
    const end_left: c_int = @max(end_x - @as(i32, v.room_bounds_x.v[qm]), 0);
    const end_right: c_int = @max(@as(i32, v.room_bounds_x.v[qm + 2]) - end_x, 0);
    return dungeon_wide.transitionMargins(max, @min(end_left, max), @min(end_right, max), end_x, end_y);
}
const kGlideIntoWideRooms = false;
/// Widescreen: brings the camera to where the 4:3 one would be leaving a
/// room sideways, at the scroll's speed, before the next room starts loading;
/// true once it's there. A wide room's camera is up to a margin short of it,
/// and the next room loads over the far half of this one, which would be on
/// screen from there: the scroll would start with a strip of the next room
/// where this one's far half was.
fn cameraToScrollStart() bool {
    const dir = v.overworld_screen_transition.*;
    if (dir < 2 or !overworld.wideCameraOn()) return true;
    // Drawn from the room buffers instead, the far half's still there.
    if (dungeon_wide.enabled()) return true;
    const cam = v.BG2HOFS_copy2.*;
    // Leaving to the right, the 4:3 camera's a screen short of the room's
    // right edge, the next 512 on; to the left, at the room's left edge.
    const start = if (dir == 2) ((cam +% 256 +% kPpuExtraMax) & ~@as(u16, 511)) -% 256 else cam & ~@as(u16, 511);
    if (cam == start) return true;
    const gap: u16 = if (dir == 2) start -% cam else cam -% start;
    const n: u16 = @min(gap, kRoomSettleSpeed);
    const d: u16 = if (dir == 2) n else 0 -% n;
    v.BG2HOFS_copy2.* +%= d;
    v.BG1HOFS_copy2.* +%= d;
    return false;
}
/// More than any margin: the most the camera can be short of the 4:3 one's.
const kPpuExtraMax = 128;
fn xyw(x: u16, y: u16) u16 {
    return y *% 64 +% x;
}
fn adv(p: anytype, delta: isize) @TypeOf(p) {
    return if (delta >= 0) p + @as(usize, @intCast(delta)) else p - @as(usize, @intCast(-delta));
}
fn both_p1(at: usize, tile: u16) void {
    v.dung_bg2[at] = tile;
    v.dung_bg1[at] = tile;
}
fn width_p1() u16 {
    return v.dung_draw_width_indicator.*;
}
fn decWidth() bool {
    v.dung_draw_width_indicator.* -%= 1;
    return v.dung_draw_width_indicator.* != 0;
}
fn decHeight() bool {
    v.dung_draw_height_indicator.* -%= 1;
    return v.dung_draw_height_indicator.* != 0;
}
fn FindInByteArray(data: []const u8, lookfor: u8, size: usize) c_int {
    var i = size;
    while (i != 0) {
        i -= 1;
        if (data[i] == lookfor) return @intCast(i);
    }
    return -1;
}
fn layerBit(mask: u16) u16 {
    return if (v.dung_line_ptrs_row0.* != 0x4000) 0 else mask;
}
fn xy_p2(x: u16, y: u16) u16 {
    return y *% 64 +% x;
}
fn ci(a: anytype) c_int {
    return @intCast(a);
}
inline fn FindInByteArray_p2(data: []const u8, lookfor: u8, size: usize) c_int {
    var i = size;
    while (i > 0) {
        i -= 1;
        if (data[i] == lookfor)
            return @intCast(i);
    }
    return -1;
}
fn setLinePtrs(src: *const [33]u8) void {
    @memcpy(@as([*]u8, @ptrCast(v.dung_line_ptrs_row0))[0..33], src);
}
fn wordAt(p: [*]const u8, offs: usize) u16 {
    return @as(*align(1) const u16, @ptrCast(p + offs)).*;
}
const rtl = @import("zelda_rtl.zig");
const features = @import("features.zig");
const adjacent_doors_flags: *align(1) u16 = @ptrCast(&v.g_ram[0x1100]);
const adjacent_doors: [*]align(1) u16 = @ptrCast(&v.g_ram[0x1110]);
fn xy_p3(x: c_int, y: c_int) c_int {
    return y * 64 + x;
}
fn writeAttr1(j: c_int, attr: u16) void {
    const i = index(j);
    v.dung_bg1_attr_table[i] = @truncate(attr);
    v.dung_bg1_attr_table[i + 1] = @truncate(attr >> 8);
}
fn writeAttr2(j: c_int, attr: u16) void {
    const i = index(j);
    v.dung_bg2_attr_table[i] = @truncate(attr);
    v.dung_bg2_attr_table[i + 1] = @truncate(attr >> 8);
}
fn attr2w(i: c_int) *align(1) u16 {
    return @ptrCast(&v.dung_bg2_attr_table[index(i)]);
}
const Point16U = extern struct { x: u16, y: u16 };
const kDoorType_ShuttersTwoWay: u8 = 24; // dungeon.h
const kDoorType_BreakableWall: u8 = 0x28; // dungeon.h
const kDoorType_Shutter: u8 = 68; // dungeon.h
fn xy_p4(x: c_int, y: c_int) c_int {
    return y * 64 + x;
}
fn sign16(a: u16) bool {
    return (a & 0x8000) != 0;
}
fn swap16(a: u16) u16 {
    return (a << 8) | (a >> 8);
}
fn attr1w(i: c_int) *align(1) u16 {
    return @ptrCast(&v.dung_bg1_attr_table[index(i)]);
}
fn attr2at(k: c_int) u8 {
    const p: [*]u8 = @ptrFromInt(@intFromPtr(v.dung_bg2_attr_table) +% @as(usize, @bitCast(@as(isize, k))));
    return p[0];
}
fn readWord(p: [*]const u8) u16 {
    return @as(*align(1) const u16, @ptrCast(p)).*;
}
fn vramDst() Words {
    return v.vram_upload_data + index(v.vram_upload_offset.* >> 1);
}
fn sign8(a: u8) bool {
    return (a & 0x80) != 0;
}
fn swap16_p5(a: u16) u16 {
    return (a >> 8) | (a << 8);
}
fn kDungeonRoomOverlay() [*]const u8 {
    return asset8(48);
}
fn kDungeonRoomOverlayOffs() Tiles {
    return asset16(49);
}
fn FindInWordArray(data: [*]align(1) const u16, lookfor: u16, size: usize) c_int {
    var i: usize = 0;
    while (i != size) : (i += 1) {
        if (data[i] == lookfor) return @intCast(i);
    }
    return -1;
}
fn asset8_p6(n: usize) [*]const u8 {
    return main.g_asset_ptrs[n].?;
}
fn asset16_p6(n: usize) Tiles {
    return @ptrCast(asset8_p6(n));
}
fn assetSize(n: usize) usize {
    return main.g_asset_sizes[n];
}
fn FindInWordArray_p6(data: [*]const u16, lookfor: u16, size: usize) i32 {
    for (0..size) |i| {
        if (data[i] == lookfor)
            return @intCast(i);
    }
    return -1;
}
fn writeAttr2_p6(j: usize, attr: u16) void {
    v.dung_bg2_attr_table[j + 0] = @truncate(attr);
    v.dung_bg2_attr_table[j + 1] = @truncate(attr >> 8);
}
const kTurnOffWater_Tab0 = [16]i8{ -1, -1, -1, 1, -1, -1, -1, 1, -1, -1, -1, 1, -1, -1, -1, 1 };
const kTurnOnWater_Tab2 = [4]i8{ 1, 1, 1, -1 };
const kTurnOnWater_Tab1 = [4]i8{ 1, 2, 1, -1 };
const kTurnOnWater_Tab0 = [4]i8{ 1, -1, 1, -1 };
const kCrystal_Tab0 = [7]u16{ 0x1618, 0x1658, 0x1658, 0x1618, 0x658, 0x1618, 0x1658 };
const kOpenGanonDoor_Tab = [4]u16{ 0x2556, 0x2596, 0x25d6, 0x2616 };
const kPushedBlockDirMask = [4]u8{ 0x8, 0x4, 0x2, 0x1 };
const kPushBlockTab1 = [4]u8{ 0x0, 0x0, 0xe0, 0x20 };
const kPushBlockTab2 = [4]u8{ 0xe0, 0x20, 0x0, 0x0 };
const kPushBlock_A = [4]u8{ 0, 0, 8, 8 };
const kPushBlock_B = [4]u8{ 15, 15, 23, 23 };
const kPushBlock_D = [4]u8{ 15, 15, 15, 15 };
const kPushBlock_C = [4]u8{ 0x0, 0x0, 0x0, 0x0 };
const kPushBlock_E = [4]u8{ 8, 24, 0, 16 };
const kPushBlock_F = [4]u8{ 15, 0, 15, 0 };

// ---------------------------------------------------------------------------
// from dungeon.zig
// ---------------------------------------------------------------------------
pub export const kLayoutQuadrantFlags = t.kLayoutQuadrantFlags;
pub export const kDungAnimatedTiles = t.kDungAnimatedTiles;

pub export fn DstoPtr(d: u16) Words {
    return @ptrCast(&v.g_ram[@as(usize, v.dung_line_ptrs_row0.*) + @as(usize, d) * 2]);
}
pub export fn Object_Fill_Nx1(n: c_int, src: Tiles, dst: Words) void {
    @memset(dst[0..index(n)], src[0]);
}
pub export fn Object_Draw_5x4(src: Tiles, dst: Words) void {
    drawRows(src, dst, 4, 5);
}
pub export fn Object_Draw_4x2_BothBgs(src: Tiles, dsto: u16) void {
    for (0..2) |y| for (0..4) |x| {
        both(dsto + xy(x, y), src[y * 4 + x]);
    };
}
pub export fn Object_ChestPlatform_Helper(src: Tiles, dsto_: c_int) void {
    var d = index(dsto_);
    v.dung_bg2[d] = src[0];
    for (0..v.dung_draw_width_indicator.*) |_| {
        v.dung_bg2[d + 1] = src[3];
        d += 1;
    }
    v.dung_bg2[d + 1] = src[6];
    @memset(v.dung_bg2[d + 2 ..][0..4], src[9]);
    v.dung_bg2[d + 6] = src[12];
    for (0..v.dung_draw_width_indicator.*) |_| {
        v.dung_bg2[d + 7] = src[15];
        d += 1;
    }
    v.dung_bg2[d + 7] = src[18];
}
pub export fn Object_Hole(src: Tiles, dst: Words) void {
    Object_SizeAtoAplus15(4);
    const w: usize = v.dung_draw_width_indicator.*;
    for (0..w) |y| @memset(dst[xy(0, y)..][0..w], src[0]);
    const edge = SrcPtr(0x63c);
    dst[0] = edge[0];
    @memset(dst[1..][0 .. w - 2], edge[1]);
    dst[w - 1] = edge[2];
    dst[xy(0, w - 1)] = edge[3];
    @memset(dst[xy(1, w - 1)..][0 .. w - 2], edge[4]);
    dst[xy(w - 1, w - 1)] = edge[5];
    const sides = SrcPtr(0x648);
    for (1..w - 1) |y| {
        dst[xy(0, y)] = sides[0];
        dst[xy(w - 1, y)] = sides[1];
    }
}
pub export fn Object_DrawNx3_BothBgs(n: c_int, src: Tiles, dsto: c_int) void {
    for (0..index(n)) |x| for (0..3) |y| {
        both(index(dsto) + xy(x, y), src[x * 3 + y]);
    };
}
pub export fn RoomBounds_AddA(r: *align(1) RoomBounds) void {
    r.named.a0 +%= 0x100;
    r.named.a1 +%= 0x100;
}
pub export fn RoomBounds_AddB(r: *align(1) RoomBounds) void {
    r.named.b0 +%= 0x200;
    r.named.b1 +%= 0x200;
}
pub export fn RoomBounds_SubA(r: *align(1) RoomBounds) void {
    r.named.a0 -%= 0x100;
    r.named.a1 -%= 0x100;
}
pub export fn RoomBounds_SubB(r: *align(1) RoomBounds) void {
    r.named.b0 -%= 0x200;
    r.named.b1 -%= 0x200;
}
pub export fn GetRoomDoorInfo(room: c_int) Tiles {
    return @ptrCast(asset8(3) + asset16(5)[index(room)]);
}
pub export fn GetRoomHeaderPtr(room: c_int) [*]const u8 {
    return asset8(6) + asset16(7)[index(room)];
}
pub export fn GetDefaultRoomLayout(i: c_int) [*]const u8 {
    return asset8(46) + asset16(47)[index(i)];
}
pub export fn GetDungeonRoomLayout(i: c_int) [*]const u8 {
    return asset8(3) + asset16(4)[index(i)];
}
pub export fn GetDungPalInfo(i: c_int) *const DungPalInfo {
    return &t.kDungPalinfos[index(i)];
}
pub export fn Dungeon_GetTeleMsg(room: c_int) u16 {
    return asset16(9)[index(room)];
}
pub export fn RoomDraw_FloorChunks(src: Tiles) void {
    for ([_]u16{ 0, 0x20, 0x800, 0x820 }) |offset| {
        const dst = DstoPtr(offset);
        for (0..8) |y| RoomDraw_A_Many32x32Blocks(8, src, dst + xy(0, y * 4));
    }
}
pub export fn RoomDraw_A_Many32x32Blocks(n: c_int, src: Tiles, dst: Words) void {
    for (0..index(n)) |x| for (0..2) |y| {
        drawRows(src, dst + xy(x * 4, y * 2), 4, 2);
    };
}
pub export fn RoomDraw_1x3_rightwards(n: c_int, src: Tiles, dst: Words) void {
    drawColumns(src, dst, index(n), 3);
}
pub export fn RoomDraw_CheckIfWallIsMoved() bool {
    v.dung_some_subpixel[0] = 0;
    v.dung_some_subpixel[1] = 0;
    v.dung_floor_move_flags.* = 0;
    for (0..2) |i| {
        if (v.dung_hdr_tag[i] >= 0x1c and v.dung_hdr_tag[i] < 0x20) {
            if (v.dung_savegame_state_bits.* & (@as(u16, 0x1000) >> @intCast(i)) != 0) {
                v.dung_hdr_collision.* = 0;
                v.dung_hdr_tag[i] = 0;
                v.dung_hdr_bg2_properties.* = 0;
                return false;
            }
            break;
        }
    }
    return true;
}
pub export fn MovingWall_FillReplacementBuffer(dsto: c_int) void {
    @memset(v.moving_wall_arr1[0..64], 0x1ec);
    v.moving_wall_var1.* = u16w((dsto & 0x1f) | @as(c_int, if (dsto & 0x20 != 0) 0x400 else 0) | 0x1000);
}
pub export fn Object_Table_Helper(src: Tiles, dst: Words) void {
    dst[0] = src[0];
    const n: usize = v.dung_draw_width_indicator.*;
    for (0..n) |i| {
        dst[1 + i * 2] = src[1];
        dst[2 + i * 2] = src[2];
    }
    dst[1 + n * 2] = src[3];
}
pub export fn DrawWaterThing(dst: Words, src: Tiles) void {
    drawRows(src, dst, 4, 4);
}
pub export fn RoomDraw_4x4(src: Tiles, dst: Words) void {
    drawColumns(src, dst, 4, 4);
}
pub export fn RoomDraw_Object_Nx4(n: c_int, src: Tiles, dst: Words) void {
    drawColumns(src, dst, index(n), 4);
}
pub export fn Object_DrawNx4_BothBgs(n: c_int, src: Tiles, dsto: c_int) void {
    for (0..index(n)) |x| for (0..4) |y| {
        both(index(dsto) + xy(x, y), src[x * 4 + y]);
    };
}
pub export fn RoomDraw_Rightwards2x2(src: Tiles, dst: Words) void {
    drawColumns(src, dst, 2, 2);
}
pub export fn Object_Draw_3x2(src: Tiles, dst: Words) void {
    drawRows(src, dst, 3, 2);
}
pub export fn RoomDraw_WaterHoldingObject(n: c_int, src: Tiles, dst: Words) void {
    drawRows(src, dst, 4, index(n));
}
pub export fn RoomDraw_SomeBigDecors(n: c_int, src: Tiles, dsto: u16) void {
    drawRows(src, v.dung_bg2 + (dsto | @as(u16, if (v.dung_line_ptrs_row0.* == 0x4000) 0x1000 else 0)), index(n), 8);
}
pub export fn RoomDraw_SingleLampCone(a: u16, y: u16) void {
    drawRows(SrcPtr(y), v.dung_bg1 + a / 2, 12, 12);
}
pub export fn Object_Draw8x8(src: Tiles, dst: Words) void {
    RoomDraw_4x4(src, dst);
    RoomDraw_4x4(src + 16, dst + 4);
    RoomDraw_4x4(src + 32, dst + 256);
    RoomDraw_4x4(src + 48, dst + 260);
}
pub export fn RoomDraw_GetObjectSize_1to16() void {
    Object_SizeAtoAplus15(1);
}
pub export fn Object_SizeAtoAplus15(a: u8) void {
    v.dung_draw_width_indicator.* = (v.dung_draw_width_indicator.* << 2 | v.dung_draw_height_indicator.*) +% a;
    v.dung_draw_height_indicator.* = 0;
}
pub export fn RoomDraw_GetObjectSize_1to15or26() void {
    const n = v.dung_draw_width_indicator.* << 2 | v.dung_draw_height_indicator.*;
    v.dung_draw_width_indicator.* = if (n == 0) 26 else n;
}
pub export fn RoomDraw_GetObjectSize_1to15or32() void {
    const n = v.dung_draw_width_indicator.* << 2 | v.dung_draw_height_indicator.*;
    v.dung_draw_width_indicator.* = if (n == 0) 32 else n;
}
pub export fn RoomDraw_MakeDoorPartsHighPriority_Y(dsto: u16) void {
    priority(dsto, 4, 7);
}
pub export fn RoomDraw_MakeDoorPartsHighPriority_X(dsto: u16) void {
    priority(dsto, 5, 4);
}
pub export fn RoomDraw_Downwards4x2VariableSpacing(increment: c_int, src: Tiles, dst: Words) void {
    var d = dst;
    while (true) {
        drawRows(src, d, 4, 2);
        d += index(increment);
        v.dung_draw_width_indicator.* -%= 1;
        if (v.dung_draw_width_indicator.* == 0) break;
    }
}
pub export fn RoomDraw_DrawObject2x2and1(src: Tiles, dst: Words) Words {
    drawColumns(src, dst, 1, 5);
    return dst;
}
pub export fn RoomDraw_RightwardShelfEnd(src: Tiles, dst: Words) Words {
    drawColumns(src, dst, 1, 4);
    return dst;
}
pub export fn RoomDraw_RightwardBarSegment(src: Tiles, dst: Words) Words {
    drawColumns(src, dst, 1, 3);
    return dst;
}
pub export fn Object_BombableFloorHelper(a: u16, src: Tiles, src_below: Tiles, dst: Words, dsto: u16) void {
    saveReplacement(addReplacement(a, dsto), src_below);
    RoomDraw_Rightwards2x2(src, dst);
}
pub export fn DrawBigGraySegment(a: u16, src: Tiles, dst: Words, dsto: u16) void {
    const previous = [_]u16{ dst[0], dst[64], dst[1], dst[65] };
    saveReplacement(addReplacement(a, dsto), &previous);
    RoomDraw_Rightwards2x2(src, dst);
}
pub export fn RoomDraw_SinglePot(src: Tiles, dst: Words, dsto: u16) void {
    saveReplacement(addReplacement(0x1111, dsto), &.{ 0x0d0e, 0x0d1e, 0x4d0e, 0x4d1e });
    RoomDraw_Rightwards2x2(if (v.savegame_is_darkworld.* != 0) SrcPtr(0xe92) else src, dst);
}
pub export fn RoomDraw_HammerPegSingle(src: Tiles, dst: Words, dsto: u16) void {
    saveReplacement(addReplacement(0x4040, dsto), &.{ 0x19d8, 0x19d9, 0x59d8, 0x59d9 });
    RoomDraw_Rightwards2x2(src, dst);
}
pub export fn RoomDraw_BombableFloor(src_: Tiles, dst: Words, dsto: u16) void {
    _ = src_;
    if (v.dungeon_room_index.* == 101 and v.dung_savegame_state_bits.* & 0x1000 != 0) {
        v.dung_draw_width_indicator.* = 0;
        v.dung_draw_height_indicator.* = 0;
        Object_Hole(SrcPtr(0x5aa), dst);
        return;
    }
    const src = SrcPtr(0x220);
    const below = SrcPtr(0x5ba);
    for ([_]u16{ 0, 2, 128, 130 }, 0..) |delta, i| Object_BombableFloorHelper(0x3030 + @as(u16, @intCast(i)) * 0x101, src + i * 4, below + i * 4, dst + delta, dsto +% delta);
}
pub export fn DrawObjects_PushableBlock(dsto_x2: u16, slot: u16) void {
    const i = v.dung_misc_objs_index.* >> 1;
    v.dung_misc_objs_index.* +%= 2;
    v.dung_replacement_tile_state[i] = 0;
    v.dung_object_pos_in_objdata[i] = slot;
    v.dung_object_tilemap_pos[i] = dsto_x2;
    const dst = DstoPtr((dsto_x2 >> 1) & 0x1fff);
    saveReplacement(i, &.{ dst[0], dst[64], dst[1], dst[65] });
    RoomDraw_Rightwards2x2(SrcPtr(0xe52), dst);
}
pub export fn DrawObjects_LightableTorch(dsto_x2: u16, slot: u16) void {
    const i = v.dung_index_of_torches.* >> 1;
    v.dung_index_of_torches.* +%= 2;
    v.dung_object_tilemap_pos[i] = dsto_x2;
    v.dung_object_pos_in_objdata[i] = slot;
    var tile: u16 = 0xec2;
    if (dsto_x2 & 0x8000 != 0) {
        tile = 0xeca;
        if (v.dung_num_lit_torches.* < 3) v.dung_num_lit_torches.* += 1;
    }
    RoomDraw_Rightwards2x2(SrcPtr(tile), DstoPtr((dsto_x2 >> 1) & 0x1fff));
}

pub export fn Dungeon_Store2x2(pos: u16, t0: u16, t1: u16, t2: u16, t3: u16, attr: u8) void {
    const dst = v.vram_upload_data + (v.vram_upload_offset.* >> 1);
    for ([_]u16{ 0, 64, 1, 65 }, [_]u16{ t0, t1, t2, t3 }, 0..) |delta, tile, i| {
        const at = pos +% delta;
        dst[i * 3] = Dungeon_MapVramAddr(at);
        dst[i * 3 + 1] = 0x100;
        dst[i * 3 + 2] = tile;
        v.overworld_tileattr[at] = tile;
        v.dung_bg2_attr_table[at] = attr;
    }
    dst[12] = 0xffff;
    v.vram_upload_offset.* +%= 24;
    v.nmi_load_bg_from_vram.* = 1;
}
pub export fn Dungeon_MapVramAddr(pos: u16) u16 {
    return @byteSwap(Dungeon_MapVramAddrNoSwap(pos));
}
pub export fn Dungeon_MapVramAddrNoSwap(pos: u16) u16 {
    const p = pos *% 2;
    return (p & 0x40) << 4 | (p & 0x303f) >> 1 | (p & 0xf80) >> 2;
}
// These four entry points assert unconditionally in the source game engine.
pub export fn Door_Up_EntranceDoor(dsto: u16) void {
    _ = dsto;
    unreachable;
}
pub export fn Door_Down_EntranceDoor(dsto: u16) void {
    _ = dsto;
    unreachable;
}
pub export fn Door_Left_EntranceDoor(dsto: u16) void {
    _ = dsto;
    unreachable;
}
pub export fn Door_Right_EntranceDoor(dsto: u16) void {
    _ = dsto;
    unreachable;
}
pub export fn Dung_TagRoutine_0x22_0x3B(k: c_int, j: u8) void {
    if (v.dung_savegame_state_bits.* & 0x100 != 0) {
        v.dung_hdr_tag[index(k)] = 0;
        v.dung_overlay_to_load.* = j;
        v.dung_load_ptr_offs.* = 0;
        v.subsubmodule_index.* = 0;
        v.sound_effect_2.* = 0x1b;
        v.submodule_index.* = 3;
    }
}
pub export fn Sprite_HandlePushedBlocks_One(i_: c_int) void {
    _ = c.Oam_AllocateFromRegionB(4);
    const i = index(i_);
    const y = @as(u16, v.pushedblocks_y_lo[i]) | @as(u16, v.pushedblocks_y_hi[i]) << 8;
    const x = @as(u16, v.pushedblocks_x_lo[i]) | @as(u16, v.pushedblocks_x_hi[i]) << 8;
    if (v.pushedblocks_some_index.* < 3) {
        const oam = v.g_ram[v.oam_cur_ptr.*..];
        oam[0] = @truncate(x -% v.BG2HOFS_copy2.*);
        oam[1] = @truncate(y -% v.BG2VOFS_copy2.* -% 1);
        oam[2] = 12;
        oam[3] = 0x20;
        v.g_ram[v.oam_ext_cur_ptr.*] = 2;
    }
}
pub export fn Object_Draw_DoorLeft_3x4(src: u16, door: c_int) void {
    drawColumns(SrcPtr(src), v.dung_bg2 + (v.dung_door_tilemap_address[index(door)] >> 1), 3, 4);
}
pub export fn Object_Draw_DoorRight_3x4(src: u16, door: c_int) void {
    drawColumns(SrcPtr(src), v.dung_bg2 + (v.dung_door_tilemap_address[index(door)] >> 1) + 1, 3, 4);
}
pub export fn Dungeon_IsPitThatHurtsPlayer() bool {
    for (asset16(10)[0 .. main.g_asset_sizes[10] / 2]) |room| if (room == v.dungeon_room_index.*) {
        return true;
    };
    return false;
}
pub export fn Dungeon_PrepareNextRoomQuadrantUpload() void {
    prepareQuadrant(v.dung_bg2, 0);
    v.dung_cur_quadrant_upload.* +%= 4;
}
pub export fn TileMapPrep_NotWaterOnTag() void {
    prepareQuadrant(v.dung_bg1, 0x10);
}
pub export fn WaterFlood_BuildOneQuadrantForVRAM() void {
    std.debug.assert(v.dung_hdr_tag[0] != 25);
    TileMapPrep_NotWaterOnTag();
}
pub export fn OrientLampLightCone() void {
    if (v.hdr_dungeon_dark_with_lantern.* == 0 or v.submodule_index.* == 20) return;
    const a = v.link_direction_facing.* >> 1;
    var i = a;
    if (v.is_standing_in_doorway.* != 0) {
        i = v.is_standing_in_doorway.* & 0xfe;
        if (i != 0) {
            if (a < 2) i +%= @intFromBool(u8w(v.link_x_coord.* +% 8) >= 0x80) else i = a;
        } else {
            if (a >= 2) i +%= @intFromBool(u8w(v.link_y_coord.*) >= 0x80) else i = a;
        }
    }
    const x = [_]u16{ 0, 256, 0, 256 };
    const y = [_]u16{ 0, 0, 256, 256 };
    const offset = [_]i16{ 52, -2, 56, 6 };
    const margin = [_]i16{ 64, 64, 82, -176 };
    const limit = [_]u16{ 128, 384, 160, 160 };
    var p: u16 = undefined;
    if (i < 2) {
        v.BG1HOFS_copy2.* = v.BG2HOFS_copy2.* -% v.link_x_coord.* +% 0x77 +% x[i];
        p = v.BG2VOFS_copy2.* -% v.link_y_coord.* +% 0x58 +% y[i] +% u16w(offset[i]) +% u16w(margin[i]);
    } else {
        v.BG1VOFS_copy2.* = v.BG2VOFS_copy2.* -% v.link_y_coord.* +% 0x72 +% y[i];
        p = v.BG2HOFS_copy2.* -% v.link_x_coord.* +% 0x58 +% x[i] +% u16w(offset[i]) +% u16w(margin[i]);
    }
    if (i >= 2 and dungeon_wide.drawsLanternLight()) {
        // Widescreen: facing left or right, the light's kept from running
        // off a 4:3 screen's sides; past them are the margins now, with the
        // dark drawn round it (dungeon_wide.zig).
        const ext: i32 = overworld.wideCameraMargin(0xffff);
        const ps: i32 = std.math.clamp(@as(i32, @as(i16, @bitCast(p))), -ext, @as(i32, limit[i]) + ext);
        p = @bitCast(@as(i16, @intCast(ps)));
    } else {
        if (p & 0x8000 != 0) p = 0;
        p = @min(p, limit[i]);
    }
    if (i < 2) v.BG1VOFS_copy2.* = p -% u16w(margin[i]) else v.BG1HOFS_copy2.* = p -% u16w(margin[i]);
    dungeon_wide.noteLanternPicture(x[i], y[i]);
}
pub export fn SavePalaceDeaths() void {
    const j = low(v.cur_palace_index_x2).*;
    v.deaths_per_palace[j >> 1] = v.death_save_counter.*;
    if (j != 8) v.death_save_counter.* = 0;
}
pub export fn Dungeon_HandleLayerEffect() void {
    t.kDungeon_Effect_Handler[v.dung_hdr_collision_2.*].?();
}
pub export fn LayerEffect_Nothing() void {}
pub export fn LayerEffect_Scroll() void {
    if (v.dung_savegame_state_bits.* & 0x8000 != 0) {
        v.dung_hdr_collision_2.* = 0;
        return;
    }
    v.dung_floor_x_vel.* = 0;
    v.dung_floor_y_vel.* = 0;
    if (v.dung_floor_move_flags.* & 1 != 0) return;
    const sum = @as(u16, v.dung_some_subpixel[1]) + 0x80;
    v.dung_some_subpixel[1] = @truncate(sum);
    var delta: i16 = @intCast(sum >> 8);
    if (v.dung_floor_move_flags.* & 2 != 0) delta = -delta;
    if (v.dung_floor_move_flags.* < 4) {
        v.dung_floor_x_vel.* = @bitCast(u16w(delta));
        v.dung_floor_x_offs.* -%= u16w(delta);
        v.BG1HOFS_copy2.* = v.BG2HOFS_copy2.* +% v.dung_floor_x_offs.*;
    } else {
        v.dung_floor_y_vel.* = @bitCast(u16w(delta));
        v.dung_floor_y_offs.* -%= u16w(delta);
        v.BG1VOFS_copy2.* = v.BG2VOFS_copy2.* +% v.dung_floor_y_offs.*;
    }
}
pub export fn LayerEffect_Trinexx() void {
    v.dung_floor_x_offs.* +%= u16w(v.dung_floor_x_vel.*);
    v.dung_floor_y_offs.* +%= u16w(v.dung_floor_y_vel.*);
    v.dung_floor_x_vel.* = 0;
    v.dung_floor_y_vel.* = 0;
}
pub export fn LayerEffect_Agahnim2() void {
    const j = v.frame_counter.* & 0x7f;
    if (j == 3 or j == 36) {
        v.main_palette_buffer[0x6d] = 0x1d59;
        v.main_palette_buffer[0x6e] = 0x25ff;
        v.main_palette_buffer[0x77] = 0x1a;
        v.main_palette_buffer[0x6f] = 0x1a;
        v.flag_update_cgram_in_nmi.* +%= 1;
    } else if (j == 5 or j == 38) {
        for ([_]usize{ 0x6d, 0x6e, 0x6f }) |k| v.main_palette_buffer[k] = v.aux_palette_buffer[k];
        v.main_palette_buffer[0x77] = v.aux_palette_buffer[0x6f];
        v.flag_update_cgram_in_nmi.* +%= 1;
    }
    v.TS_copy.* = 2;
}
pub export fn LayerEffect_InvisibleFloor() void {
    const lit = litObjects() != 0;
    const x: u16 = if (lit) 0x2940 else 0;
    const y: u16 = if (lit) 0x4e60 else 0;
    if (v.aux_palette_buffer[0x7b] != x) {
        v.main_palette_buffer[0x7b] = x;
        v.aux_palette_buffer[0x7b] = x;
        v.main_palette_buffer[0x7c] = y;
        v.aux_palette_buffer[0x7c] = y;
        v.flag_update_cgram_in_nmi.* +%= 1;
    }
    v.TS_copy.* = 2;
}
pub export fn LayerEffect_Ganon() void {
    const count = litObjects();
    v.byte_7E04C5.* = count;
    v.TS_copy.* = if (count == 1) 2 else 0;
    v.CGADSUB_copy.* = if (count == 0) 0xb3 else 0x70;
}
pub export fn LayerEffect_WaterRapids() void {
    const sum = @as(u16, v.dung_some_subpixel[1]) + 0x80;
    v.dung_some_subpixel[1] = @truncate(sum);
    v.dung_floor_x_vel.* = @bitCast(@as(u16, 0) -% (sum >> 8));
}
pub export fn Dungeon_LoadCustomTileAttr() void {
    @memcpy(v.attributes_for_tile[0x140..][0..0x80], asset8(52)[asset16(51)[v.aux_tile_theme_index.*]..][0..0x80]);
}
pub export fn Link_CheckBunnyStatus() void {
    if (v.link_player_handler_state.* == c.kPlayerState_RecoilWall) v.link_player_handler_state.* = if (v.link_is_bunny_mirror.* == 0) c.kPlayerState_Ground else if (v.link_item_moon_pearl.* != 0) c.kPlayerState_TempBunny else c.kPlayerState_PermaBunny;
}
pub export fn CrystalCutscene_Initialize() void {
    v.CGADSUB_copy.* = 0x33;
    low(v.palette_filter_countdown).* = 0;
    low(v.darkening_or_lightening_screen).* = 0;
    c.Palette_AssertTranslucencySwap();
    c.PaletteFilter_Crystal();
    @memcpy(v.main_palette_buffer[112..][0..8], &[_]u16{ 0, 0x3821, 0x4463, 0x54a5, 0x5ce7, 0x6d29, 0x79ad, 0x7e10 });
    v.flag_update_cgram_in_nmi.* +%= 1;
    CrystalCutscene_SpawnMaiden();
    c.CrystalCutscene_InitializePolyhedral();
}
pub export fn CrystalCutscene_SpawnMaiden() void {
    @memset(v.sprite_state[0..16], 0);
    var info: c.SpriteSpawnInfo = undefined;
    const j = index(c.Sprite_SpawnDynamically(0, 0xab, &info));
    v.sprite_x_hi[j] = @truncate(v.link_x_coord.* >> 8);
    v.sprite_y_hi[j] = @truncate(v.link_y_coord.* >> 8);
    v.sprite_x_lo[j] = 0x78;
    v.sprite_y_lo[j] = 0x7c;
    v.sprite_D[j] = 1;
    v.sprite_oam_flags[j] = 0xb;
    v.sprite_subtype2[j] = 0;
    v.sprite_floor[j] = 0;
    v.sprite_A[j] = c.Ancilla_TerminateSelectInteractives(@intCast(j));
    v.item_receipt_method.* = 0;
    if (low(v.cur_palace_index_x2).* == 24) {
        v.sprite_oam_flags[j] = 9;
        v.follower_indicator.* = 1;
    } else v.follower_indicator.* = 6;
    c.LoadFollowerGraphics();
    v.follower_indicator.* = 0;
    v.dung_floor_x_offs.* = v.BG2HOFS_copy2.* -% v.link_x_coord.* +% 0x79;
    v.dung_floor_y_offs.* = @as(u16, 0x30) -% u8w(v.BG1VOFS_copy2.*);
    v.dung_hdr_collision_2_mirror.* = 1;
}

pub export fn Mirror_SaveRoomData() void {
    if (v.cur_palace_index_x2.* == 0xff) {
        v.sound_effect_1.* = 60;
        return;
    }
    v.submodule_index.* = 25;
    v.subsubmodule_index.* = 0;
    v.sound_effect_1.* = 51;
    Dungeon_FlagRoomData_Quadrants();
    SaveDungeonKeys();
}
pub export fn SaveDungeonKeys() void {
    var i = u8w(v.cur_palace_index_x2.*);
    if (i == 0xff) return;
    if (i == 2) i = 0;
    v.link_keys_earned_per_dungeon[i >> 1] = v.link_num_keys.*;
}
pub export fn Dungeon_AdjustAfterSpiralStairs() void {
    const room = v.dungeon_room_index.*;
    const prev = v.dungeon_room_index_prev.*;
    shiftRoomAxis(true, ((room & 15) -% (prev & 15)) *% 0x200);
    shiftRoomAxis(false, (((room >> 4) & 15) -% ((prev >> 4) & 15)) *% 0x200);
}
pub export fn Dungeon_AdjustForTeleportDoors(room: u8, flag: u8) void {
    v.dungeon_room_index2.* = room;
    v.dungeon_room_index_prev.* = room;
    shiftRoomAxis(true, (@as(u16, room & 15) * 2 -% (v.link_x_coord.* >> 8) +% flag) << 8);
    shiftRoomAxis(false, (@as(u16, (room & 0xf0) >> 3) -% (v.link_y_coord.* >> 8)) << 8);
    @memset(v.tagalong_y_hi[0..20], @truncate(v.link_y_coord.* >> 8));
}
pub export fn Dungeon_AdjustForRoomLayout() void {
    Dungeon_AdjustQuadrant();
    v.quadrant_fullsize_x.* = fullSizeX();
    v.quadrant_fullsize_y.* = fullSizeY();
    if (u8w(v.dung_unk2.*) != 0) v.quadrant_fullsize_x.* = u8w(v.dung_unk2.*);
    if (u8w(v.dung_unk2.* >> 8) != 0) v.quadrant_fullsize_y.* = u8w(v.dung_unk2.* >> 8);
}
pub export fn Dungeon_StartInterRoomTrans_Left() void {
    startHorizontal(false);
}
pub export fn Dungeon_StartInterRoomTrans_Right() void {
    startHorizontal(true);
}
pub export fn Dungeon_StartInterRoomTrans_Up() void {
    startVertical(false);
}
pub export fn Dungeon_StartInterRoomTrans_Down() void {
    startVertical(true);
}
pub export fn Dung_StartInterRoomTrans_Left_Plus() void {
    v.link_x_coord.* -%= 8;
    startHorizontal(false);
}
pub export fn HandleEdgeTransitionMovementEast_RightBy8() void {
    v.link_x_coord.* +%= 8;
    startHorizontal(true);
}
pub export fn HandleEdgeTransitionMovementSouth_DownBy16() void {
    v.link_y_coord.* +%= 16;
    startVertical(true);
}
pub export fn Dung_HandleExitToOverworld() void {
    SaveDungeonKeys();
    SaveQuadrantsToSram();
    v.saved_module_for_menu.* = 8;
    v.main_module_index.* = 15;
    v.submodule_index.* = 0;
    v.subsubmodule_index.* = 0;
    c.Dungeon_ResetTorchBackgroundAndPlayerInner();
}
pub export fn AdjustQuadrantAndCamera_right() void {
    v.link_quadrant_x.* ^= 1;
    Dungeon_AdjustQuadrant();
    RoomBounds_AddA(v.room_bounds_x);
    SetAndSaveVisitedQuadrantFlags();
}
pub export fn AdjustQuadrantAndCamera_left() void {
    v.link_quadrant_x.* ^= 1;
    Dungeon_AdjustQuadrant();
    RoomBounds_SubA(v.room_bounds_x);
    SetAndSaveVisitedQuadrantFlags();
}
pub export fn AdjustQuadrantAndCamera_down() void {
    v.link_quadrant_y.* ^= 2;
    Dungeon_AdjustQuadrant();
    RoomBounds_AddA(v.room_bounds_y);
    SetAndSaveVisitedQuadrantFlags();
}
pub export fn AdjustQuadrantAndCamera_up() void {
    v.link_quadrant_y.* ^= 2;
    Dungeon_AdjustQuadrant();
    RoomBounds_SubA(v.room_bounds_y);
    SetAndSaveVisitedQuadrantFlags();
}
pub export fn SetAndSaveVisitedQuadrantFlags() void {
    markQuadrant();
    SaveQuadrantsToSram();
}
pub export fn SaveQuadrantsToSram() void {
    v.save_dung_info[v.dungeon_room_index.*] |= v.dung_quadrants_visited.*;
}
pub export fn Dungeon_FlagRoomData_Quadrants() void {
    markQuadrant();
    Dung_SaveDataForCurrentRoom();
}
pub export fn Dung_SaveDataForCurrentRoom() void {
    v.save_dung_info[v.dungeon_room_index.*] = (v.dung_savegame_state_bits.* >> 4) | (v.dung_door_opened.* & 0xf000) | v.dung_quadrants_visited.*;
}
pub export fn HandleEdgeTransition_AdjustCameraBoundaries(arg: u8) void {
    v.overworld_screen_transition.* = arg;
    if (v.link_direction.* & 3 != 0) {
        const i: usize = @as(usize, if (v.link_direction.* & 1 != 0) 0 else 2) + @intFromBool(v.link_quadrant_x.* != 0);
        v.camera_x_coord_scroll_low.* = ([_]u16{ 127, 383, 127, 383 })[i];
        v.camera_x_coord_scroll_hi.* = v.camera_x_coord_scroll_low.* +% 2;
    } else {
        const i: usize = @as(usize, if (v.link_direction.* & 4 != 0) 0 else 2) + @intFromBool(v.link_quadrant_y.* != 0);
        v.camera_y_coord_scroll_low.* = ([_]u16{ 120, 376, 136, 392 })[i];
        v.camera_y_coord_scroll_hi.* = v.camera_y_coord_scroll_low.* +% 2;
    }
}
pub export fn Dungeon_AdjustQuadrant() void {
    v.composite_of_layout_and_quadrant.* = @as(u8, @truncate(v.dung_layout_and_starting_quadrant.*)) | v.link_quadrant_y.* | v.link_quadrant_x.*;
}
pub export fn Dungeon_HandleCamera() void {
    dungeon_wide.notePlayFrame();
    scrollCameraAxis(false);
    settleRoomCameraX();
    scrollCameraAxis(true);
    if (v.dungeon_room_index.* != 0xffff and v.dung_hdr_bg2_properties.* != 1 and v.dung_hdr_bg2_properties.* != 5) MirrorBg1Bg2Offs();
}
pub export fn MirrorBg1Bg2Offs() void {
    v.BG1HOFS_copy2.* = v.BG2HOFS_copy2.*;
    v.BG1VOFS_copy2.* = v.BG2VOFS_copy2.*;
}
pub export fn DungeonTransition_AdjustCamera_X(arg: u8) void {
    const values = [_]u16{ 0, 256, 256, 0 };
    v.left_right_scroll_target.* = values[arg * 2];
    v.left_right_scroll_target_end.* = values[arg * 2 + 1];
}
pub export fn DungeonTransition_AdjustCamera_Y(arg: u8) void {
    const values = [_]u16{ 0, 272, 256, 16 };
    v.up_down_scroll_target.* = values[arg];
    v.up_down_scroll_target_end.* = values[arg + 1];
}
pub export fn DungeonTransition_ScrollRoom() void {
    v.transition_counter.* +%= 1;
    const i = v.overworld_screen_transition.*;
    v.bg1_y_offset.* = 0;
    v.bg1_x_offset.* = 0;
    const bg2 = if (i >= 2) v.BG2HOFS_copy2 else v.BG2VOFS_copy2;
    const bg1 = if (i >= 2) v.BG1HOFS_copy2 else v.BG1VOFS_copy2;
    const coord = if (i >= 2) v.link_x_coord else v.link_y_coord;
    const delta = u16w(t.kStaircaseTab3[i]);
    bg2.* = (bg2.* +% delta) & 0xfffe;
    bg1.* = bg2.*;
    const targets: Tiles = @ptrCast(v.up_down_scroll_target);
    var target = targets[i];
    if (i >= 2 and overworld.wideCameraOn()) {
        // Widescreen: into a wide room, the scroll carries on to where its
        // camera stops, a margin in from the room's edge; dungeon_wide.zig
        // has the room's far half drawn from its buffers meanwhile. The
        // steps are 4 pixels, so it stops as close as they get and snaps
        // the last few. Link walks in over the scroll's last stretch, as far
        // as he does in the original's, however long the scroll turned out.
        const negative = delta & 0x8000 != 0;
        const on = wideRoomMargin() & ~@as(u16, 3);
        target = (if (negative) target -% on else target +% on) & 0x1fc;
        const step: u16 = if (negative) 0 -% delta else delta;
        const at = bg2.* & 0x1fc;
        const left = (if (negative) at -% target else target -% at) & 0x1ff;
        if (left <= 256 - @as(u16, @intCast(t.kStaircaseTab4[i])) * step) coord.* +%= delta;
    } else if (v.transition_counter.* >= t.kStaircaseTab4[i]) coord.* +%= delta;
    if (i < 2 and overworld.wideCameraOn()) {
        // Widescreen: a wide room's camera stops short of where the 4:3 one
        // would be, and a scroll up or down leaves it there; the next room
        // may want it elsewhere, so it goes over as the scroll goes down.
        const negative = delta & 0x8000 != 0;
        const at = bg2.* & 0x1fc;
        const left = (if (negative) at -% target else target -% at) & 0x1ff;
        slideCameraXToRoom(left / 4 + 1);
    }
    fadeInDuringScroll(bg2.* & 0x1fc, target, delta);
    if (bg2.* & 0x1fc == target) {
        if (i >= 2) landWideCamera(i == 3);
        SetAndSaveVisitedQuadrantFlags();
        v.subsubmodule_index.* +%= 1;
        v.transition_counter.* = 0;
        if (v.submodule_index.* == 2) WaterFlood_BuildOneQuadrantForVRAM();
    }
}
pub export fn Module07_11_0A_ScrollCamera() void {
    v.link_visibility_status.* = 12;
    v.tagalong_var5.* = 12;
    var i = v.overworld_screen_transition.*;
    v.BG2VOFS_copy2.* = (v.BG2VOFS_copy2.* +% u16w(t.kStaircaseTab3[i])) & 0xfffc;
    v.BG1VOFS_copy2.* = v.BG2VOFS_copy2.*;
    const targets: Tiles = @ptrCast(v.up_down_scroll_target);
    if (overworld.wideCameraOn()) {
        // Widescreen: over to the next room's range as the stairs scroll,
        // as a scroll up or down between rooms does.
        const negative = u16w(t.kStaircaseTab3[i]) & 0x8000 != 0;
        const at = v.BG1VOFS_copy2.* & 0x1fc;
        const left = (if (negative) at -% targets[i] else targets[i] -% at) & 0x1ff;
        slideCameraXToRoom(left / 4 + 1);
    }
    if (v.BG1VOFS_copy2.* & 0x1fc == targets[i]) {
        if (v.submodule_index.* >= 18) i += 2;
        v.link_y_coord.* +%= u16w(t.kStaircaseTab5[i]);
        v.link_visibility_status.* = 0;
        v.tagalong_var5.* = 0;
        v.subsubmodule_index.* +%= 1;
    }
}
pub export fn DungeonTransition_FindSubtileLanding() void {
    c.Dungeon_ResetTorchBackgroundAndPlayerInner();
    SubtileTransitionCalculateLanding();
    v.subsubmodule_index.* +%= 1;
    SaveQuadrantsToSram();
}
pub export fn SubtileTransitionCalculateLanding() void {
    var a = CalculateTransitionLanding();
    if (a == 2) a = 1 else if (a == 4) a = 2;
    a += v.overworld_screen_transition.* * 5;
    const initial = t.kStaircaseTab2[a];
    const landing: u8 = @bitCast(initial -% @as(i8, if (initial < 0) -8 else 8));
    if (v.overworld_screen_transition.* & 2 != 0) low(v.link_x_coord).* = landing else low(v.link_y_coord).* = landing;
    v.link_visibility_status.* = 0;
}
pub export fn Dungeon_InterRoomTrans_State13() void {
    // Widescreen: the scroll stops where the 4:3 camera does, and only the
    // half of the room it brings on screen is loaded by then; the rest is by
    // now, so the camera carries on into a wide room's range while Link
    // walks in from the door, at the scroll's speed.
    settleRoomCameraX();
    if (v.dung_want_lights_out.* | v.dung_want_lights_out_copy.* != 0) c.ApplyPaletteFilter_bounce();
    Dungeon_IntraRoomTrans_State5();
}
pub export fn Dungeon_IntraRoomTrans_State5() void {
    c.Link_HandleMovingAnimation_FullLongEntry();
    if (!DungeonTransition_MoveLinkOutDoor()) return;
    if (v.byte_7E004E.* == 2 or v.byte_7E004E.* == 4) v.is_standing_in_doorway.* = 0;
    low(v.force_move_any_direction).* = 0;
    v.byte_7E004E.* = 0;
    v.overworld_screen_transition.* = 0;
    v.subsubmodule_index.* +%= 1;
}
pub export fn DungeonTransition_MoveLinkOutDoor() bool {
    const landing: u8 = @bitCast(t.kStaircaseTab2[v.byte_7E004E.* + v.overworld_screen_transition.* * 5]);
    const coord = if (v.overworld_screen_transition.* & 2 != 0) v.link_x_coord else v.link_y_coord;
    coord.* +%= if (v.overworld_screen_transition.* & 1 != 0) @as(u16, 0xfffe) else 2;
    return low(coord).* & 0xfe == landing;
}
pub export fn CalculateTransitionLanding() u8 {
    const pos = (((v.link_y_coord.* +% 12) & 0x1f8) << 3) | (((v.link_x_coord.* +% 8) & 0x1f8) >> 3) | @as(u16, if (v.link_is_on_lower_level.* != 0) 0x1000 else 0);
    const a = v.dung_bg2_attr_table[pos];
    const result: u8 = if (a == 0 or a == 9) 0 else switch (a & 0x8e) {
        0x80 => 1,
        0x82 => 2,
        0x84, 0x88 => 3,
        0x86 => 4,
        else => 2,
    };
    v.byte_7E004E.* = result;
    return result;
}

// ---------------------------------------------------------------------------
// from dungeon_part1.zig
// ---------------------------------------------------------------------------
// Declared with the exact Zig pointer types used by dungeon.zig; the @cImport
// prototypes use naturally-aligned [*c]u16 which our align(1) globals cannot coerce to.

/// XY() applied to a u16 tilemap offset.
/// Advance a many-pointer by a possibly negative element delta.
/// C's `dung_bg1[at] = dung_bg2[at] = tile` (bg2 stored first).
/// `--dung_draw_width_indicator` as a loop condition.
/// misc.h's FindInByteArray, which searches backwards.

// dsto is half the value of Y
pub export fn LoadType1ObjectSubtype1(idx: u8, dst_: Words, dsto_: u16) callconv(.c) void {
    const param1 = t.kObjectSubtype1Params[idx];
    var src = SrcPtr(param1);
    var dst = dst_;
    var dsto = dsto_;

    switch (idx) {
        // RoomDraw_Rightwards2x2_1to15or32 - Ceiling
        // B8 -  Blue Switch Block [L-R]
        0x0, 0xb8, 0xb9 => {
            c.RoomDraw_GetObjectSize_1to15or32();
            while (true) {
                RoomDraw_Rightwards2x2(src, dst);
                dst += 2;
                if (!decWidth()) break;
            }
        },
        // RoomDraw_Rightwards2x4_1to15or26 - [N]Wall Horz: [L-R]
        // B6 -  [N]Wall Decor: 1/2 [L-R]
        0x1, 0x2, 0xb6, 0xb7 => {
            c.RoomDraw_GetObjectSize_1to15or26();
            while (true) {
                RoomDraw_Object_Nx4(2, src, dst);
                dst += 2;
                if (!decWidth()) break;
            }
        },
        // RoomDraw_Rightwards2x4spaced4_1to16 - 03 -  [N]Wall Horz: (LOW) [L-R]
        0x3, 0x4 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                both_p1(index(dsto) + xy(0, 0), src[0]);
                both_p1(index(dsto) + xy(0, 1), src[1]);
                both_p1(index(dsto) + xy(0, 2), src[2]);
                both_p1(index(dsto) + xy(0, 3), src[3]);
                both_p1(index(dsto) + xy(1, 0), src[4]);
                both_p1(index(dsto) + xy(1, 1), src[5]);
                both_p1(index(dsto) + xy(1, 2), src[6]);
                both_p1(index(dsto) + xy(1, 3), src[7]);
                dsto +%= 2;
                if (!decWidth()) break;
            }
        },
        // RoomDraw_Rightwards2x4spaced4_1to16_BothBG - 05 -  [N]Wall Column [L-R]
        0x5, 0x6 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Object_Nx4(2, src, dst);
                dst += 6;
                if (!decWidth()) break;
            }
        },
        // RoomDraw_Rightwards2x2_1to16 - 07 -  [N]Wall Pit [L-R]
        0x7, 0x8, 0x53 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Rightwards2x2(src, dst);
                dst += 2;
                if (!decWidth()) break;
            }
        },
        // 09 -  / Wall Wood Bot (HIGH) [NW]
        0x9, 0x0c, 0x0d, 0x10, 0x11, 0x14 => {
            c.Object_SizeAtoAplus15(6);
            while (true) {
                _ = RoomDraw_DrawObject2x2and1(src, dst);
                dst = adv(dst, -63);
                if (!decWidth()) break;
            }
        },
        // 12 -  \ Wall Tile2 Bot (HIGH) [SW]
        0x0a, 0x0b, 0x0e, 0x0f, 0x12, 0x13 => {
            c.Object_SizeAtoAplus15(6);
            while (true) {
                _ = RoomDraw_DrawObject2x2and1(src, dst);
                dst += 65;
                if (!decWidth()) break;
            }
        },
        // 15 -  / Wall Tile Top (LOW)[NW]
        0x15, 0x18, 0x19, 0x1C, 0x1D, 0x20 => {
            c.Object_SizeAtoAplus15(6);
            while (true) {
                both_p1(index(dsto) + xy(0, 0), src[0]);
                both_p1(index(dsto) + xy(0, 1), src[1]);
                both_p1(index(dsto) + xy(0, 2), src[2]);
                both_p1(index(dsto) + xy(0, 3), src[3]);
                both_p1(index(dsto) + xy(0, 4), src[4]);
                dsto -%= 63;
                if (!decWidth()) break;
            }
        },
        // 16 -  \ Wall Tile Top (LOW)[SW]
        0x16, 0x17, 0x1A, 0x1B, 0x1E, 0x1F => {
            c.Object_SizeAtoAplus15(6);
            while (true) {
                both_p1(index(dsto) + xy(0, 0), src[0]);
                both_p1(index(dsto) + xy(0, 1), src[1]);
                both_p1(index(dsto) + xy(0, 2), src[2]);
                both_p1(index(dsto) + xy(0, 3), src[3]);
                both_p1(index(dsto) + xy(0, 4), src[4]);
                dsto +%= 65;
                if (!decWidth()) break;
            }
        },
        // 21 -  Mini Stairs [L-R]
        0x21 => {
            v.dung_draw_width_indicator.* = (v.dung_draw_width_indicator.* << 2 | v.dung_draw_height_indicator.*) *% 2 +% 1;
            RoomDraw_1x3_rightwards(2, src, dst);
            dst += 2;
            while (true) {
                RoomDraw_1x3_rightwards(1, src + 3, dst);
                dst += 1;
                if (!decWidth()) break;
            }
            RoomDraw_1x3_rightwards(1, src + 6, dst);
        },
        // 22 -  Horz: Rail Thin [L-R]
        0x22 => {
            c.Object_SizeAtoAplus15(2);
            if ((dst[0] & 0x3ff) != 0xe2)
                dst[0] = src[0];
            const n = src[1];
            while (true) {
                dst += 1;
                dst[0] = n;
                if (!decWidth()) break;
            }
            dst[1] = src[2];
        },
        // 23 -  Pit [N]Edge [L-R] / 3F -  Water Edge [L-R]
        0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e,
        0x3f, 0x40, 0x41, 0x42, 0x43, 0x44,
        0x45, 0x46, 0xb3, 0xb4 => {
            c.RoomDraw_GetObjectSize_1to16();
            const m = dst[0] & 0x3ff;
            if (m != 0x1db and m != 0x1a6 and m != 0x1dd and m != 0x1fc)
                dst[0] = src[0];
            const n = src[1];
            while (true) {
                dst += 1;
                dst[0] = n;
                if (!decWidth()) break;
            }
            dst[1] = src[2];
        },
        // 2F -  Rail Wall [L-R]
        0x2f => {
            c.Object_SizeAtoAplus15(10);
            const n = src[0];
            src += 1;
            if ((dst[0] & 0x3ff) != 0xe2) {
                dst[xy(0, 0)] = src[0];
                dst[xy(1, 0)] = src[1];
                dst[xy(0, 1)] = n;
                dst[xy(1, 1)] = n;
                dst += 2;
            }
            src += 2;
            while (true) {
                dst[xy(0, 0)] = src[0];
                dst[xy(0, 1)] = n;
                dst += 1;
                if (!decWidth()) break;
            }
            src += 1;
            dst[xy(0, 0)] = src[0];
            dst[xy(1, 0)] = src[1];
            dst[xy(0, 1)] = n;
            dst[xy(1, 1)] = n;
        },
        // 30 -  Rail Wall [L-R]
        0x30 => {
            c.Object_SizeAtoAplus15(10);
            const n = src[0];
            src += 1;
            if ((dst[xy(0, 1)] & 0x3ff) != 0xe2) {
                dst[xy(1, 0)] = n;
                dst[xy(0, 0)] = n;
                dst[xy(0, 1)] = src[0];
                dst[xy(1, 1)] = src[1];
                dst += 2;
            }
            src += 2;
            while (true) {
                dst[xy(0, 0)] = n;
                dst[xy(0, 1)] = src[0];
                dst += 1;
                if (!decWidth()) break;
            }
            src += 1;
            dst[xy(1, 0)] = n;
            dst[xy(0, 0)] = n;
            dst[xy(0, 1)] = src[0];
            dst[xy(1, 1)] = src[1];
        },
        // 31 -  Unused -empty
        0x31, 0x32, 0x35, 0x54, 0x57, 0x58, 0x59, 0x5A => {},
        // 33 -  Red Carpet Floor [L-R] / B2 -  Floor? [L-R]
        0x33, 0xb2, 0xba => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_4x4(src, dst);
                dst += 4;
                if (!decWidth()) break;
            }
        },
        // 34 -  Red Carpet Floor Trim [L-R]
        0x34 => {
            c.Object_SizeAtoAplus15(4);
            const n = src[0];
            while (true) {
                dst[0] = n;
                dst += 1;
                if (!decWidth()) break;
            }
        },
        // 36 -  [N]Curtain [L-R]
        0x36, 0x37 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_4x4(src, dst);
                dst += 6;
                if (!decWidth()) break;
            }
        },
        // 38 -  Statue [L-R]
        0x38 => {
            src = @ptrCast(adv(@as([*]const u8, @ptrCast(src)), 0xe26 - @as(isize, param1)));
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_1x3_rightwards(2, src, dst);
                dst += 4;
                if (!decWidth()) break;
            }
        },
        // 39 -  Column [L-R]
        0x39, 0x3d => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Object_Nx4(2, src, dst);
                dst += 6;
                if (!decWidth()) break;
            }
        },
        // 3A -  [N]Wall Decor: [L-R]
        0x3a, 0x3b => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_1x3_rightwards(4, src, dst);
                dst += 8;
                if (!decWidth()) break;
            }
        },
        // 3C -  Double Chair [L-R]
        0x3c => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                const s = SrcPtr(0x8ca);
                RoomDraw_Rightwards2x2(s + 0, dst);
                RoomDraw_Rightwards2x2(s + 4, dst + xy(0, 6));
                dst += 4;
                if (!decWidth()) break;
            }
        },
        // 3E -  [N]Wall Column [L-R]
        0x3e, 0x4b => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Rightwards2x2(src, dst);
                dst += 14;
                if (!decWidth()) break;
            }
        },
        // 47 -  Unused Waterfall [L-R]
        0x47 => {
            c.RoomDraw_GetObjectSize_1to16();
            v.dung_draw_width_indicator.* <<= 1;
            dst = RoomDraw_DrawObject2x2and1(src, dst) + 1;
            while (true) {
                _ = RoomDraw_DrawObject2x2and1(src + 5, dst);
                dst += 1;
                if (!decWidth()) break;
            }
            _ = RoomDraw_DrawObject2x2and1(src + 10, dst);
        },
        0x48 => {
            c.RoomDraw_GetObjectSize_1to16();
            v.dung_draw_width_indicator.* <<= 1;
            RoomDraw_1x3_rightwards(1, src, dst);
            dst += 1;
            while (true) {
                dst[xy(0, 0)] = src[3];
                dst[xy(0, 1)] = src[4];
                dst[xy(0, 2)] = src[5];
                dst += 1;
                if (!decWidth()) break;
            }
            RoomDraw_1x3_rightwards(1, src + 6, dst);
        },
        // RoomDraw_RightwardsFloorTile4x2_1to16      ; 49 -  N/A
        0x49, 0x4A => {
            c.RoomDraw_GetObjectSize_1to16();
            RoomDraw_Downwards4x2VariableSpacing(4, src, dst);
        },
        // 4C -  Bar [L-R]
        0x4c => {
            c.RoomDraw_GetObjectSize_1to16();
            v.dung_draw_width_indicator.* <<= 1;
            dst = RoomDraw_RightwardBarSegment(src, dst) + 1;
            while (true) {
                dst = RoomDraw_RightwardBarSegment(src + 3, dst) + 1;
                if (!decWidth()) break;
            }
            dst = RoomDraw_RightwardBarSegment(src + 6, dst) + 1;
        },
        // 4C -  Bar [L-R]
        0x4d, 0x4e, 0x4f => {
            c.RoomDraw_GetObjectSize_1to16();
            RoomDraw_Object_Nx4(1, src, dst);
            dst += 1;
            while (true) {
                RoomDraw_Object_Nx4(2, src + 4, dst);
                dst += 2;
                if (!decWidth()) break;
            }
            _ = RoomDraw_RightwardShelfEnd(src + 12, dst);
        },
        // 50 -  Cane Ride [L-R]
        0x50 => {
            c.Object_SizeAtoAplus15(2);
            const n = src[0];
            while (true) {
                dst[0] = n;
                dst += 1;
                if (!decWidth()) break;
            }
        },
        // 51 -  [N]Canon Hole [L-R]
        0x51, 0x52, 0x5B, 0x5C => {
            c.RoomDraw_GetObjectSize_1to16();
            RoomDraw_1x3_rightwards(2, src, dst);
            dst += 2;
            while (decWidth()) {
                RoomDraw_1x3_rightwards(2, src + 6, dst);
                dst += 2;
            }
            RoomDraw_1x3_rightwards(2, src + 12, dst);
        },
        // 55 -  [N]Wall Torches [L-R]
        0x55, 0x56 => {
            c.RoomDraw_GetObjectSize_1to16();
            RoomDraw_Downwards4x2VariableSpacing(12, src, dst);
        },
        // 5D -  Large Horz: Rail [L-R]
        0x5D => {
            c.RoomDraw_GetObjectSize_1to16();
            v.dung_draw_width_indicator.* +%= 1;
            RoomDraw_1x3_rightwards(2, src, dst);
            dst += 2;
            while (true) {
                _ = RoomDraw_RightwardBarSegment(src + 6, dst);
                dst += 1;
                if (!decWidth()) break;
            }
            RoomDraw_1x3_rightwards(2, src + 9, dst);
        },
        // 5E -  Block [L-R] / BB -  N/A
        0x5E, 0xbb => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Rightwards2x2(src, dst);
                dst += 4;
                if (!decWidth()) break;
            }
        },
        // 5F -  Long Horz: Rail [L-R]
        0x5f => {
            c.Object_SizeAtoAplus15(21);
            if ((dst[0] & 0x3ff) != 0xe2)
                dst[0] = src[0];
            const n = src[1];
            while (true) {
                dst += 1;
                dst[0] = n;
                if (!decWidth()) break;
            }
            dst[1] = src[2];
        },
        // 60 -  Ceiling [U-D] / 92 -  Blue Peg Block [U-D]
        0x60, 0x92, 0x93 => {
            c.RoomDraw_GetObjectSize_1to15or32();
            while (true) {
                RoomDraw_Rightwards2x2(src, dst);
                dst += xy(0, 2);
                if (!decWidth()) break;
            }
        },
        // 61 -  [W]Wall Vert: [U-D]
        0x61, 0x62, 0x90, 0x91 => {
            c.RoomDraw_GetObjectSize_1to15or26();
            RoomDraw_Downwards4x2VariableSpacing(2 * 64, src, dst);
        },
        // RoomDraw_Downwards4x2_1to16_BothBG - 63 -  [W]Wall Vert: (LOW) [U-D]
        0x63, 0x64 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                both_p1(index(dsto) + xy(0, 0), src[0]);
                both_p1(index(dsto) + xy(1, 0), src[1]);
                both_p1(index(dsto) + xy(2, 0), src[2]);
                both_p1(index(dsto) + xy(3, 0), src[3]);
                both_p1(index(dsto) + xy(0, 1), src[4]);
                both_p1(index(dsto) + xy(1, 1), src[5]);
                both_p1(index(dsto) + xy(2, 1), src[6]);
                both_p1(index(dsto) + xy(3, 1), src[7]);
                dsto +%= xyw(0, 2);
                if (!decWidth()) break;
            }
        },
        // 65 -  [W]Wall Column [U-D]
        0x65, 0x66 => {
            c.RoomDraw_GetObjectSize_1to16();
            RoomDraw_Downwards4x2VariableSpacing(6 * 64, src, dst);
        },
        // 67 -  [W]Wall Pit [U-D] / 7D -  Pipe Ride [U-D]
        0x67, 0x68, 0x7d => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Rightwards2x2(src, dst);
                dst += xy(0, 2);
                if (!decWidth()) break;
            }
        },
        // 69 -  Vert: Rail Thin [U-D]
        0x69 => {
            c.Object_SizeAtoAplus15(2);
            if ((dst[0] & 0x3ff) != 0xe3)
                dst[0] = src[0];
            const n = src[1];
            while (true) {
                dst += 64;
                dst[0] = n;
                if (!decWidth()) break;
            }
            dst[64] = src[2];
        },
        // 6A -  [W]Pit Edge [U-D] / 79 -  Water Edge [U-D] / 8D -  [W]Edge [U-D]
        0x6a, 0x6b, 0x79, 0x7a, 0x8d, 0x8e => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                dst[0] = src[0];
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
        },
        // 6C -  [W]Rail Wall [U-D]
        0x6c => {
            c.Object_SizeAtoAplus15(10);
            const n = src[0];
            src += 1;
            if ((dst[0] & 0x3ff) != 0xe3) {
                dst[xy(0, 0)] = src[0];
                dst[xy(0, 1)] = src[1];
                dst[xy(1, 1)] = n;
                dst[xy(1, 0)] = n;
                dst += xy(0, 2);
            }
            src += 2;
            while (true) {
                dst[xy(0, 0)] = src[0];
                dst[xy(1, 0)] = n;
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
            src += 1;
            dst[xy(0, 0)] = src[0];
            dst[xy(0, 1)] = src[1];
            dst[xy(1, 1)] = n;
            dst[xy(1, 0)] = n;
        },
        // 6D -  [E]Rail Wall [U-D]
        0x6d => {
            c.Object_SizeAtoAplus15(10);
            const n = src[0];
            src += 1;
            if ((dst[xy(1, 0)] & 0x3ff) != 0xe3) {
                dst[xy(0, 1)] = n;
                dst[xy(0, 0)] = n;
                dst[xy(1, 0)] = src[0];
                dst[xy(1, 1)] = src[1];
                dst += xy(0, 2);
            }
            src += 2;
            while (true) {
                dst[xy(0, 0)] = n;
                dst[xy(1, 0)] = src[0];
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
            src += 1;
            dst[xy(0, 1)] = n;
            dst[xy(0, 0)] = n;
            dst[xy(1, 0)] = src[0];
            dst[xy(1, 1)] = src[1];
        },
        // unused
        0x6e, 0x6f, 0x72, 0x7e => {},
        // 70 -  Red Floor/Wire Floor [U-D]
        0x70, 0x94 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_4x4(src, dst);
                dst += xy(0, 4);
                if (!decWidth()) break;
            }
        },
        // 71 -  Red Carpet Floor Trim [U-D]
        0x71 => {
            c.Object_SizeAtoAplus15(4);
            while (true) {
                dst[0] = src[0];
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
        },
        // 73 -  [W]Curtain [U-D]
        0x73, 0x74 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_4x4(src, dst);
                dst += xy(0, 6);
                if (!decWidth()) break;
            }
        },
        // 75 -  Column [U-D]
        0x75, 0x87 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Object_Nx4(2, src, dst);
                dst += xy(0, 6);
                if (!decWidth()) break;
            }
        },
        // 76 -  [W]Wall Decor: [U-D]
        0x76, 0x77 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Object_Nx4(3, src, dst);
                dst += xy(0, 8);
                if (!decWidth()) break;
            }
        },
        // 78 -  [W]Wall Top Column [U-D]
        0x78, 0x7b => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Rightwards2x2(src, dst);
                dst += xy(0, 14);
                if (!decWidth()) break;
            }
        },
        // 7C -  Cane Ride [U-D]
        0x7c => {
            c.RoomDraw_GetObjectSize_1to16();
            v.dung_draw_width_indicator.* +%= 1;
            while (true) {
                dst[0] = src[0];
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
        },
        // 7F -  [W]Wall Torches [U-D]
        0x7f, 0x80 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Object_Nx4(2, src, dst);
                dst += xy(0, 12);
                if (!decWidth()) break;
            }
        },
        // 81 -  [W]Wall Decor: [U-D]
        0x81, 0x82, 0x83, 0x84 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Object_Nx4(3, src, dst);
                dst += xy(0, 6);
                if (!decWidth()) break;
            }
        },
        // 85 -  [W]Wall Canon Hole [U-D]
        0x85, 0x86 => {
            c.RoomDraw_GetObjectSize_1to16();
            Object_Draw_3x2(src, dst);
            dst += xy(0, 2);
            while (decWidth()) {
                Object_Draw_3x2(src + 6, dst);
                dst += xy(0, 2);
            }
            Object_Draw_3x2(src + 12, dst);
        },
        // 88 -  Large Vert: Rail [U-D]
        0x88 => {
            c.RoomDraw_GetObjectSize_1to16();
            RoomDraw_Rightwards2x2(src, dst);
            dst += xy(0, 2);
            src += 4;
            while (true) {
                dst[xy(0, 0)] = src[0];
                dst[xy(1, 0)] = src[1];
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
            RoomDraw_1x3_rightwards(2, src + 2, dst);
        },
        // 89 -  Block Vert: [U-D]
        0x89 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_Rightwards2x2(src, dst);
                dst += xy(0, 4);
                if (!decWidth()) break;
            }
        },
        // 8A -  Long Vert: Rail [U-D]
        0x8a => {
            c.Object_SizeAtoAplus15(21);
            if ((dst[0] & 0x3ff) != 0xe3)
                dst[0] = src[0];
            const n = src[1];
            while (true) {
                dst += xy(0, 1);
                dst[0] = n;
                if (!decWidth()) break;
            }
            dst[xy(0, 1)] = src[2];
        },
        // 8B -  [W]Vert: Jump Edge [U-D]
        0x8b, 0x8c => {
            c.Object_SizeAtoAplus15(8);
            while (true) {
                dst[0] = src[0];
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
        },
        // 8F -  N/A
        0x8f => {
            c.Object_SizeAtoAplus15(2);
            v.dung_draw_width_indicator.* <<= 1;
            dst[xy(0, 0)] = src[0];
            dst[xy(1, 0)] = src[1];
            while (true) {
                dst[xy(0, 1)] = src[2];
                dst[xy(1, 1)] = src[3];
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
        },
        // 95 -  Fake Pot [U-D]
        0x95 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_SinglePot(src, dst, dsto);
                dst += xy(0, 2);
                dsto +%= xyw(0, 2);
                if (!decWidth()) break;
            }
        },
        // 96 -  Hammer Peg Block [U-D]
        0x96 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_HammerPegSingle(src, dst, dsto);
                dst += xy(0, 2);
                dsto +%= xyw(0, 2);
                if (!decWidth()) break;
            }
        },
        0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f,
        0xad, 0xae, 0xaf, 0xbe, 0xbf => {},
        // A0 -  / Ceiling [NW] / A5 -  / Ceiling [Trans][NW]
        0xa0, 0xa5, 0xa9 => {
            c.Object_SizeAtoAplus15(4);
            while (true) {
                Object_Fill_Nx1(@intCast(width_p1()), src, dst);
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
        },
        // A1 -  \ Ceiling [SW] / A6 -  \ Ceiling [Trans][SW]
        0xa1, 0xa6, 0xaa => {
            c.Object_SizeAtoAplus15(4);
            var n: c_int = 1;
            while (true) {
                Object_Fill_Nx1(n, src, dst);
                n += 1;
                dst += xy(0, 1);
                if (!decWidth()) break;
            }
        },
        // A2 -  \ Ceiling [NE] / A7 -  \ Ceiling [Trans][NE]
        0xa2, 0xa7, 0xab => {
            c.Object_SizeAtoAplus15(4);
            while (true) {
                Object_Fill_Nx1(@intCast(width_p1()), src, dst);
                dst += xy(1, 1);
                if (!decWidth()) break;
            }
        },
        // A3 -  / Ceiling [SE] / A8 -  / Ceiling [Trans][SE]
        0xa3, 0xa8, 0xac => {
            c.Object_SizeAtoAplus15(4);
            while (true) {
                Object_Fill_Nx1(@intCast(width_p1()), src, dst);
                dst = adv(dst, -63);
                if (!decWidth()) break;
            }
        },
        // A4 -  Hole [4-way]
        0xa4 => Object_Hole(src, dst),
        // B0 -  [S]Horz: Jump Edge [L-R]
        0xb0, 0xb1 => {
            c.Object_SizeAtoAplus15(8);
            Object_Fill_Nx1(@intCast(width_p1()), src, dst);
        },
        // B5 -  N/A
        0xb5 => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                src = SrcPtr(0xb16);
                RoomDraw_Object_Nx4(2, src, dst);
                dst += 2;
                if (!decWidth()) break;
            }
        },
        // BC -  fake pots [L-R]
        0xbc => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_SinglePot(src, dst, dsto);
                dst += 2;
                dsto +%= 2;
                if (!decWidth()) break;
            }
        },
        // BD -  Hammer Pegs [L-R]
        0xbd => {
            c.RoomDraw_GetObjectSize_1to16();
            while (true) {
                RoomDraw_HammerPegSingle(src, dst, dsto);
                dst += 2;
                dsto +%= 2;
                if (!decWidth()) break;
            }
        },
        // C0 -  Ceiling Large [4-way]
        0xc0, 0xc2 => {
            const n = src[0];
            var y: c_int = @intCast(v.dung_draw_height_indicator.*);
            while (true) {
                const cont = y >= 0;
                y -= 1;
                if (!cont) break;
                const dst_org = dst;
                var x: c_int = @intCast(v.dung_draw_width_indicator.*);
                while (true) {
                    const cont2 = x >= 0;
                    x -= 1;
                    if (!cont2) break;
                    dst[xy(0, 0)] = n;
                    dst[xy(1, 0)] = n;
                    dst[xy(2, 0)] = n;
                    dst[xy(3, 0)] = n;
                    dst[xy(0, 1)] = n;
                    dst[xy(1, 1)] = n;
                    dst[xy(2, 1)] = n;
                    dst[xy(3, 1)] = n;
                    dst[xy(0, 2)] = n;
                    dst[xy(1, 2)] = n;
                    dst[xy(2, 2)] = n;
                    dst[xy(3, 2)] = n;
                    dst[xy(0, 3)] = n;
                    dst[xy(1, 3)] = n;
                    dst[xy(2, 3)] = n;
                    dst[xy(3, 3)] = n;
                    dst += 4;
                }
                dst = dst_org + xy(0, 4);
            }
        },
        // C1 -  Chest Pedastal [4-way]
        0xc1 => {
            v.dung_draw_width_indicator.* +%= 4;
            v.dung_draw_height_indicator.* +%= 1;
            // draw upper part
            var dsto_p = dst;
            RoomDraw_1x3_rightwards(3, src, dst);
            src += 9;
            dst += 3;
            var i: c_int = @intCast(v.dung_draw_width_indicator.*);
            while (i != 0) : (i -= 1) {
                RoomDraw_1x3_rightwards(2, src, dst);
                dst += 2;
            }
            RoomDraw_1x3_rightwards(3, src + 6, dst);
            src += 6 + 9;
            // draw center part
            dst = dsto_p + xy(0, 3);
            var h: c_int = @intCast(v.dung_draw_height_indicator.*);
            while (h != 0) : (h -= 1) {
                var dt = dst;
                Object_Draw_3x2(src, dt);
                dt += 3;
                var j: c_int = @intCast(v.dung_draw_width_indicator.*);
                while (j != 0) : (j -= 1) {
                    RoomDraw_Rightwards2x2(src + 6, dt);
                    dt += 2;
                }
                Object_Draw_3x2(src + 10, dt);
                dst += xy(0, 2);
            }
            dsto_p = dst;
            src += 6 + 4 + 6;
            RoomDraw_1x3_rightwards(3, src, dst);
            src += 9;
            dst += 3;
            var k: c_int = @intCast(v.dung_draw_width_indicator.*);
            while (k != 0) : (k -= 1) {
                RoomDraw_1x3_rightwards(2, src, dst);
                dst += 2;
            }
            RoomDraw_1x3_rightwards(3, src + 6, dst);
            src += 6 + 9;

            src = SrcPtr(0x590);
            const delta = @as(isize, v.dung_draw_width_indicator.*) + 2 -
                (@as(isize, v.dung_draw_height_indicator.*) + 1) * 64;
            RoomDraw_Rightwards2x2(src, adv(dsto_p, delta));
        },
        // C3 -  Falling Edge Mask [4-way] / D7 -  overlay tile? [4-way]
        0xc3, 0xd7 => {
            v.dung_draw_width_indicator.* +%= 1;
            v.dung_draw_height_indicator.* +%= 1;
            const n = src[0];
            while (true) {
                var d = dst;
                var i: c_int = @intCast(v.dung_draw_width_indicator.*);
                while (i != 0) : (i -= 1) {
                    d[xy(0, 0)] = n;
                    d[xy(1, 0)] = n;
                    d[xy(2, 0)] = n;
                    d[xy(0, 1)] = n;
                    d[xy(1, 1)] = n;
                    d[xy(2, 1)] = n;
                    d[xy(0, 2)] = n;
                    d[xy(1, 2)] = n;
                    d[xy(2, 2)] = n;
                    d += 3;
                }
                dst += xy(0, 3);
                if (!decHeight()) break;
            }
        },
        // C4 -  Doorless Room Transition / DB -  Floor2 [4-way] and plain floors
        0xc4, 0xdb,
        0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca,
        0xd1, 0xd2, 0xd9,
        0xdf, 0xe0, 0xe1, 0xe2, 0xe3, 0xe4,
        0xe5, 0xe6, 0xe7, 0xe8 => {
            if (idx == 0xc4) {
                src = SrcPtr(v.dung_floor_2_filler_tiles.*);
            } else if (idx == 0xdb) {
                src = SrcPtr(v.dung_floor_1_filler_tiles.*);
            }
            // fill_floor:
            v.dung_draw_width_indicator.* +%= 1;
            v.dung_draw_height_indicator.* +%= 1;
            while (true) {
                RoomDraw_A_Many32x32Blocks(@intCast(width_p1()), src, dst);
                dst += xy(0, 4);
                if (!decHeight()) break;
            }
        },
        // CD -  Moving Wall Right [4-way]
        0xcd => {
            if (!c.RoomDraw_CheckIfWallIsMoved())
                return;
            v.dung_hdr_collision_2_mirror.* +%= 1;
            var size0: c_int = t.kMovingWall_Sizes0[v.dung_draw_width_indicator.*];
            var size1: c_int = t.kMovingWall_Sizes1[v.dung_draw_height_indicator.*];
            c.MovingWall_FillReplacementBuffer(@as(c_int, dsto) - size1 - 1);
            v.moving_wall_var2.* = @truncate(v.dung_draw_height_indicator.* *% 2);
            src = SrcPtr(0x3d8);
            var dst1 = dst - index(size1);
            while (true) {
                var dst2 = dst1;
                dst2[xy(0, 0)] = src[0];
                var n1 = size0 * 2 + 4;
                while (true) {
                    dst2[xy(0, 1)] = src[1];
                    dst2 += xy(0, 1);
                    n1 -= 1;
                    if (n1 == 0) break;
                }
                dst2[xy(0, 1)] = src[2];
                dst1 += 1;
                size1 -= 1;
                if (size1 == 0) break;
            }
            src = SrcPtr(0x72a);
            RoomDraw_1x3_rightwards(3, src, dst);
            dst += xy(0, 3);
            while (true) {
                Object_Draw_3x2(src + 9, dst);
                dst += xy(0, 2);
                size0 -= 1;
                if (size0 == 0) break;
            }
            RoomDraw_1x3_rightwards(3, src + 9 + 6, dst);
        },
        // CE -  Moving Wall Left [4-way]
        0xce => {
            if (!c.RoomDraw_CheckIfWallIsMoved())
                return;
            v.dung_hdr_collision_2_mirror.* +%= 1;
            src = SrcPtr(0x75a);
            var size1: c_int = t.kMovingWall_Sizes1[v.dung_draw_height_indicator.*];
            const size0: c_int = t.kMovingWall_Sizes0[v.dung_draw_width_indicator.*];
            v.moving_wall_var2.* = @truncate(v.dung_draw_height_indicator.* *% 2);
            c.MovingWall_FillReplacementBuffer(@as(c_int, dsto) + 3 + size1);
            var dst1 = dst;
            RoomDraw_1x3_rightwards(3, src, dst1);
            dst1 += xy(0, 3);
            var n = size0;
            while (true) {
                Object_Draw_3x2(src + 9, dst1);
                dst1 += xy(0, 2);
                n -= 1;
                if (n == 0) break;
            }
            RoomDraw_1x3_rightwards(3, src + 15, dst1);
            src = SrcPtr(0x3d8);
            dst1 = dst + 3;
            while (true) {
                var dst2 = dst1;
                dst2[xy(0, 0)] = src[0];
                var n1 = size0 * 2 + 4;
                while (true) {
                    dst2[xy(0, 1)] = src[1];
                    dst2 += xy(0, 1);
                    n1 -= 1;
                    if (n1 == 0) break;
                }
                dst2[xy(0, 1)] = src[2];
                dst1 += 1;
                size1 -= 1;
                if (size1 == 0) break;
            }
        },
        0xd8 => {
            // loads of lava/water hdma stuff
            v.dung_draw_width_indicator.* +%= 2;
            v.water_hdma_var3.* = v.dung_draw_width_indicator.* << 4;
            v.dung_draw_height_indicator.* +%= 2;
            v.water_hdma_var2.* = v.dung_draw_height_indicator.* << 4;
            v.water_hdma_var4.* = v.water_hdma_var2.* -% 24;
            v.water_hdma_var0.* = (dsto & 0x3f) << 3;
            v.water_hdma_var0.* +%= (v.dung_draw_width_indicator.* << 4) +% v.dung_loade_bgoffs_h_copy.*;
            v.water_hdma_var1.* = (dsto & 0xfc0) >> 3;
            v.water_hdma_var1.* +%= (v.dung_draw_height_indicator.* << 4) +% v.dung_loade_bgoffs_v_copy.*;
            if (v.dung_savegame_state_bits.* & 0x800 != 0) {
                v.dung_hdr_tag[1] = 0;
                v.dung_hdr_bg2_properties.* = 0;
                v.dung_num_interpseudo_upnorth_stairs.* = v.dung_num_inroom_upnorth_stairs_water.*;
                v.dung_some_stairs_unk4.* = v.dung_num_activated_water_ladders.*;
                v.dung_num_activated_water_ladders.* = 0;
                v.dung_num_inroom_upnorth_stairs_water.* = 0;
                v.dung_num_stairs_wet.* = v.dung_num_inroom_upsouth_stairs_water.*;
                v.dung_num_inroom_upsouth_stairs_water.* = 0;
                dsto +%= (v.dung_draw_width_indicator.* -% 1) << 1;
                dsto +%= (v.dung_draw_height_indicator.* -% 1) << 7;
                DrawWaterThing(v.dung_bg2 + index(dsto), SrcPtr(0x1438));
            } else {
                src = SrcPtr(0x110);
                while (true) {
                    RoomDraw_A_Many32x32Blocks(@intCast(width_p1()), src, dst);
                    dst += xy(0, 4);
                    if (!decHeight()) break;
                }
            }
        },
        // water hdma stuff
        0xda => {
            v.dung_draw_width_indicator.* +%= 2;
            v.water_hdma_var3.* = (v.dung_draw_width_indicator.* << 4) -% 24;

            v.dung_draw_height_indicator.* +%= 2;
            v.water_hdma_var4.* = (v.dung_draw_height_indicator.* << 4) -% 8;

            v.water_hdma_var2.* = v.water_hdma_var4.* -% 24;
            v.water_hdma_var5.* = 0;
            v.water_hdma_var0.* = (dsto & 0x3f) << 3;
            v.water_hdma_var0.* +%= (v.dung_draw_width_indicator.* << 4) +% v.dung_loade_bgoffs_h_copy.*;
            v.water_hdma_var1.* = (dsto & 0xfc0) >> 3;
            v.water_hdma_var1.* +%= (v.dung_draw_height_indicator.* << 4) +% v.dung_loade_bgoffs_v_copy.* -% 8;
            if (v.dung_savegame_state_bits.* & 0x800 != 0) {
                v.dung_hdr_tag[1] = 0;
            } else {
                v.dung_hdr_bg2_properties.* = 0;
                v.dung_num_interpseudo_upnorth_stairs.* = v.dung_num_inroom_upnorth_stairs_water.*;
                v.dung_some_stairs_unk4.* = v.dung_num_activated_water_ladders.*;
                v.dung_num_activated_water_ladders.* = 0;
                v.dung_num_inroom_upnorth_stairs_water.* = 0;
                v.dung_num_stairs_wet.* = v.dung_num_inroom_upsouth_stairs_water.*;
                v.dung_num_inroom_upsouth_stairs_water.* = 0;
            }
            var n: c_int = @as(c_int, v.dung_draw_height_indicator.*) * 2 - 1;
            src = SrcPtr(0x110);
            while (true) {
                const dst2 = dst;
                var j: c_int = @intCast(v.dung_draw_width_indicator.*);
                while (true) {
                    dst[xy(0, 0)] = src[0];
                    dst[xy(1, 0)] = src[1];
                    dst[xy(2, 0)] = src[2];
                    dst[xy(3, 0)] = src[3];
                    dst[xy(0, 1)] = src[4];
                    dst[xy(1, 1)] = src[5];
                    dst[xy(2, 1)] = src[6];
                    dst[xy(3, 1)] = src[7];
                    dst += 4;
                    j -= 1;
                    if (j == 0) break;
                }
                dst = dst2 + xy(0, 2);
                n -= 1;
                if (n == 0) break;
            }
        },
        // DC -  Chest Platform? [4-way]
        0xdc => {
            dsto |= layerBit(0x1000);
            v.dung_draw_width_indicator.* +%= 1;
            v.dung_draw_height_indicator.* = v.dung_draw_height_indicator.* *% 2 +% 5;
            src = SrcPtr(0xAB4);
            while (true) {
                Object_ChestPlatform_Helper(src, @as(c_int, dsto));
                dsto +%= xyw(0, 1);
                if (!decHeight()) break;
            }
            Object_ChestPlatform_Helper(src + 1, @as(c_int, dsto));
            dsto +%= xyw(0, 1);
            Object_ChestPlatform_Helper(src + 2, @as(c_int, dsto));
            dsto +%= xyw(0, 1);
        },
        // DD -  Table / Rock [4-way]
        0xdd => {
            v.dung_draw_width_indicator.* +%= 1;
            v.dung_draw_height_indicator.* = v.dung_draw_height_indicator.* *% 2 +% 1;
            Object_Table_Helper(src, dst);
            dst += xy(0, 1);
            while (true) {
                Object_Table_Helper(src + 4, dst);
                dst += xy(0, 1);
                if (!decHeight()) break;
            }
            Object_Table_Helper(src + 8, dst);
            dst += xy(0, 1);
            Object_Table_Helper(src + 12, dst);
            dst += xy(0, 1);
        },
        // DE -  Spike Block [4-way]
        0xde => {
            v.dung_draw_width_indicator.* +%= 1;
            v.dung_draw_height_indicator.* +%= 1;
            while (true) {
                var n: c_int = @intCast(v.dung_draw_width_indicator.*);
                var dst1 = dst;
                while (true) {
                    RoomDraw_Rightwards2x2(src, dst1);
                    dst1 += 2;
                    n -= 1;
                    if (n == 0) break;
                }
                dst += xy(0, 2);
                if (!decHeight()) break;
            }
        },
        else => unreachable,
    }
}

pub export fn LoadType1ObjectSubtype2(idx: u8, dst_: Words, dsto_: u16) callconv(.c) void {
    const params = t.kObjectSubtype2Params[idx];
    var src = SrcPtr(params);
    var dst = dst_;
    var dsto = dsto_;

    switch (idx) {
        // 00 -  Wall Outer Corner (HIGH) [NW]
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x1c, 0x24, 0x25, 0x29 => RoomDraw_Object_Nx4(4, src, dst),
        // 08 -  Wall Outer Corner (LOW) [NW]
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f => Object_DrawNx4_BothBgs(4, src, @as(c_int, dsto)),
        // 10 -  Wall S-Bend (LOW) [N1]
        0x10, 0x11, 0x12, 0x13 => Object_DrawNx4_BothBgs(3, src, @as(c_int, dsto)),
        // 14 -  Wall S-Bend (LOW) [W1]
        0x14, 0x15, 0x16, 0x17 => Object_DrawNx3_BothBgs(4, src, @as(c_int, dsto)),
        // 18 -  Wall Pit Corner (Lower) [NW]
        0x18, 0x19, 0x1a, 0x1b, 0x27, 0x2b, 0x34 => RoomDraw_Rightwards2x2(src, dst),
        // 1D -  Statue
        0x1d, 0x21, 0x26 => RoomDraw_1x3_rightwards(2, src, dst),
        // 1E -  Star Tile Off
        0x1e => RoomDraw_Rightwards2x2(src, dst),
        // 1F -  Star Tile On
        0x1f => {
            const i = v.dung_num_star_shaped_switches.* >> 1;
            v.dung_num_star_shaped_switches.* +%= 2;
            v.star_shaped_switches_tile[i] = dsto | layerBit(0x1000);
            RoomDraw_Rightwards2x2(src, dst);
        },
        // 20 -  Torch Lit
        0x20 => {
            v.dung_num_lit_torches.* +%= 1;
            RoomDraw_Rightwards2x2(src, dst);
        },
        // 22 -  Weird Bed
        0x22, 0x28 => Object_Draw_5x4(src, dst),
        // 23 -  Table
        0x23 => RoomDraw_1x3_rightwards(4, src, dst),
        // 2A -  Wall Painting
        0x2a => {
            v.dung_draw_width_indicator.* = 1;
            RoomDraw_Downwards4x2VariableSpacing(1, src, dst);
        },
        // 2C -  ???
        0x2c => RoomDraw_1x3_rightwards(6, src, dst),
        // 2D -  Floor Stairs Up (room)
        0x2d => {
            const i = v.dung_num_inter_room_upnorth_stairs.* >> 1;
            v.dung_inter_starcases[i] = dsto | layerBit(0x1000);
            const nv = v.dung_num_inter_room_upnorth_stairs.* +% 2;
            v.dung_num_inter_room_upnorth_stairs.* = nv;
            v.dung_num_wall_upnorth_spiral_stairs.* = nv;
            v.dung_num_wall_upnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_upnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_upsouth_straight_stairs.* = nv;
            v.dung_num_inter_room_southdown_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
            RoomDraw_4x4(SrcPtr(0x1088), dst);
        },
        // 2E -  Floor Stairs Down (room) / 2F -  Floor Stairs Down2 (room)
        0x2e, 0x2f => {
            const i = v.dung_num_inter_room_southdown_stairs.* >> 1;
            v.dung_inter_starcases[i] = dsto | layerBit(0x1000);
            const nv = v.dung_num_inter_room_southdown_stairs.* +% 2;
            v.dung_num_inter_room_southdown_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
            RoomDraw_4x4(SrcPtr(0x10A8), dst);
        },
        // 30 -  Stairs [N](unused)
        0x30 => unreachable,
        // 31 -  Stairs [N](layer)
        0x31 => {
            const i = v.dung_num_inroom_southdown_stairs.* >> 1;
            v.dung_stairs_table_1[i] = dsto;
            const nv = v.dung_num_inroom_southdown_stairs.* +% 2;
            v.dung_num_inroom_southdown_stairs.* = nv;
            v.dung_num_water_ladders.* = nv;
            v.dung_some_stairs_unk4.* = nv;
            Object_DrawNx4_BothBgs(4, src, @as(c_int, dsto));
        },
        // 32 -  Stairs [N](layer) / 33 -  Stairs Submerged [N](layer)
        0x32, 0x33 => {
            if (idx == 0x33) {
                if (v.dung_hdr_tag[1] == 27 and (v.save_dung_info[index(v.dungeon_room_index.*)] & 0x100) == 0) {
                    v.dung_hdr_bg2_properties.* = 0;
                    src = SrcPtr(0x10C8);
                } else {
                    const i = v.dung_num_inroom_upnorth_stairs_water.* >> 1;
                    v.dung_stairs_table_1[i] = dsto;
                    const nv = v.dung_num_inroom_upnorth_stairs_water.* +% 2;
                    v.dung_num_inroom_upnorth_stairs_water.* = nv;
                    v.dung_num_activated_water_ladders.* = nv;
                    RoomDraw_4x4(SrcPtr(0x10C8), dst);
                    return;
                }
            }
            // non_submerged:
            const i = v.dung_num_interpseudo_upnorth_stairs.* >> 1;
            v.dung_stairs_table_1[i] = dsto;
            const nv = v.dung_num_interpseudo_upnorth_stairs.* +% 2;
            v.dung_num_interpseudo_upnorth_stairs.* = nv;
            v.dung_num_water_ladders.* = nv;
            v.dung_some_stairs_unk4.* = nv;
            RoomDraw_4x4(src, dst);
        },
        // 35 -  Water Ladder / 36 -  Water Ladder Inactive
        0x35, 0x36 => {
            if (idx == 0x35) {
                if (!(v.dung_hdr_tag[1] == 27 and (v.save_dung_info[index(v.dungeon_room_index.*)] & 0x100) == 0)) {
                    v.dung_stairs_table_1[v.dung_num_activated_water_ladders.* >> 1] = dsto;
                    v.dung_num_activated_water_ladders.* +%= 2;
                    v.dung_draw_width_indicator.* = 1;
                    RoomDraw_Downwards4x2VariableSpacing(1, SrcPtr(0x1108), dst);
                    return;
                }
            }
            // inactive_water_ladder:
            v.dung_stairs_table_1[v.dung_num_water_ladders.* >> 1] = dsto;
            v.dung_num_water_ladders.* +%= 2;
            v.dung_some_stairs_unk4.* = v.dung_num_water_ladders.*;
            Object_Draw_4x2_BothBgs(SrcPtr(0x1108), dsto);
        },
        // 37 -  Water Gate Large
        0x37 => {
            if (v.dung_savegame_state_bits.* & 0x800 == 0) {
                RoomDraw_Object_Nx4(10, src, dst);
                v.watergate_var1.* = 0xf;
                v.watergate_pos.* = dsto *% 2;
            } else {
                RoomDraw_Object_Nx4(10, SrcPtr(0x13e8), dst);
                const bak0 = v.dung_load_ptr.*;
                const bak1 = v.dung_load_ptr_offs.*;
                const bak2 = v.dung_load_ptr_bank.*;
                c.RoomTag_OperateWaterFlooring();
                v.dung_load_ptr_bank.* = bak2;
                v.dung_load_ptr_offs.* = bak1;
                v.dung_load_ptr.* = bak0;
            }
        },
        // 38 -  Door Staircase Up R
        0x38 => {
            const i = v.dung_num_wall_upnorth_spiral_stairs.* >> 1;
            v.dung_inter_starcases[i] = (dsto -% 0x40) | layerBit(0x1000);
            const nv = v.dung_num_wall_upnorth_spiral_stairs.* +% 2;
            v.dung_num_wall_upnorth_spiral_stairs.* = nv;
            v.dung_num_wall_upnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_upnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_upsouth_straight_stairs.* = nv;
            v.dung_num_inter_room_southdown_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
            RoomDraw_1x3_rightwards(4, SrcPtr(0x1148), dst);
            v.dung_bg2[index(dsto) - 1] |= 0x2000;
            v.dung_bg2[index(dsto) + 4] |= 0x2000;
        },
        // 39 -  Door Staircase Down L
        0x39 => {
            const i = v.dung_num_wall_downnorth_spiral_stairs.* >> 1;
            v.dung_inter_starcases[i] = (dsto -% 0x40) | layerBit(0x1000);
            const nv = v.dung_num_wall_downnorth_spiral_stairs.* +% 2;
            v.dung_num_wall_downnorth_spiral_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
            RoomDraw_1x3_rightwards(4, SrcPtr(0x1160), dst);
            v.dung_bg2[index(dsto) - 1] |= 0x2000;
            v.dung_bg2[index(dsto) + 4] |= 0x2000;
        },
        // 3A -  Door Staircase Up R (Lower)
        0x3a => {
            const i = v.dung_num_wall_upnorth_spiral_stairs_2.* >> 1;
            v.dung_inter_starcases[i] = (dsto -% 0x40) | layerBit(0x1000);
            const nv = v.dung_num_wall_upnorth_spiral_stairs_2.* +% 2;
            v.dung_num_wall_upnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_upnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_upsouth_straight_stairs.* = nv;
            v.dung_num_inter_room_southdown_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
            RoomDraw_1x3_rightwards(4, SrcPtr(0x1178), dst);
            v.dung_bg1[index(dsto) - 1] |= 0x2000;
            v.dung_bg1[index(dsto) + 4] |= 0x2000;
        },
        // 3B -  Door Staircase Down L (Lower)
        0x3b => {
            const i = v.dung_num_wall_downnorth_spiral_stairs_2.* >> 1;
            v.dung_inter_starcases[i] = (dsto -% 0x40) | layerBit(0x1000);
            const nv = v.dung_num_wall_downnorth_spiral_stairs_2.* +% 2;
            v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
            RoomDraw_1x3_rightwards(4, SrcPtr(0x1190), dst);
            v.dung_bg1[index(dsto) - 1] |= 0x2000;
            v.dung_bg1[index(dsto) + 4] |= 0x2000;
        },
        // 3C -  Sanctuary Wall
        0x3c => {
            for (0..6) |_| {
                const d = index(dsto);
                v.dung_bg2[d + 0] = src[0];
                v.dung_bg2[d + 4] = src[0];
                v.dung_bg2[d + 8] = src[0];
                v.dung_bg2[d + 14] = src[0];
                v.dung_bg2[d + 18] = src[0];
                v.dung_bg2[d + 22] = src[0];
                v.dung_bg2[d + 1] = src[0] | 0x4000;
                v.dung_bg2[d + 5] = src[0] | 0x4000;
                v.dung_bg2[d + 9] = src[0] | 0x4000;
                v.dung_bg2[d + 15] = src[0] | 0x4000;
                v.dung_bg2[d + 19] = src[0] | 0x4000;
                v.dung_bg2[d + 23] = src[0] | 0x4000;
                v.dung_bg2[d + 2] = src[6];
                v.dung_bg2[d + 6] = src[6];
                v.dung_bg2[d + 16] = src[6];
                v.dung_bg2[d + 20] = src[6];
                v.dung_bg2[d + 3] = src[6] | 0x4000;
                v.dung_bg2[d + 7] = src[6] | 0x4000;
                v.dung_bg2[d + 17] = src[6] | 0x4000;
                v.dung_bg2[d + 21] = src[6] | 0x4000;
                dsto +%= xyw(0, 1);
                src += 1;
            }
            RoomDraw_1x3_rightwards(4, src + 6, dst + 10);
        },
        // 3E -  Church Pew
        0x3e => RoomDraw_1x3_rightwards(6, src, dst),
        // 3F - used in hole at the smithy dwarves
        0x3f => {
            dsto |= layerBit(0x1000);
            dst = v.dung_bg2 + index(dsto);
            for (0..8) |_| {
                dst[xy(0, 0)] = src[0];
                dst[xy(0, 1)] = src[1];
                dst[xy(0, 2)] = src[2];
                dst[xy(0, 3)] = src[3];
                dst[xy(0, 4)] = src[4];
                dst[xy(0, 5)] = src[5];
                dst[xy(0, 6)] = src[6];
                dst += 1;
                src += 7;
            }
        },
        else => unreachable,
    }
}

pub export fn LoadType1ObjectSubtype3(idx: u8, dst_: Words, dsto_: u16) callconv(.c) void {
    const params = t.kObjectSubtype3Params[idx];
    var src = SrcPtr(params);
    var dst = dst_;
    var dsto = dsto_;

    switch (idx) {
        // 00 -  Water Face Closed / 01 -  Waterfall Face
        0x00, 0x01 => {
            if (idx == 0x00) open: {
                if (v.dung_hdr_tag[1] == 27) {
                    if (v.save_dung_info[index(v.dungeon_room_index.*)] & 0x100 != 0)
                        break :open;
                } else if (v.dung_hdr_tag[1] == 25) {
                    if (v.dung_savegame_state_bits.* & 0x800 != 0)
                        break :open;
                }
                v.word_7E047C.* = dsto *% 2;
                RoomDraw_WaterHoldingObject(3, src, dst);
                return;
            }
            // water_face_open:
            RoomDraw_WaterHoldingObject(5, SrcPtr(0x162c), dst);
        },
        // 02 -  Waterfall Face Longer
        0x02 => RoomDraw_WaterHoldingObject(7, src, dst),
        // 03 -  Cane Ride Spawn [?]Block
        0x03, 0x0e => {
            v.dung_unk6.* +%= 1;
            dst[0] = src[0];
        },
        // 04 -  Cane Ride Node [4-way]
        0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0f => dst[0] = src[0],
        // 0D -  Prison Cell
        0x0d, 0x17 => {
            src = SrcPtr(0x1488);
            dsto |= layerBit(0x1000);
            var d = v.dung_bg2 + index(dsto);
            const dd = d;
            for (0..5) |_| {
                d[xy(2, 0)] = src[1];
                d[xy(9, 0)] = src[1];
                d[xy(2, 1)] = src[2];
                d[xy(9, 1)] = src[2] | 0x4000;
                d[xy(2, 2)] = src[4];
                d[xy(9, 2)] = src[4] | 0x4000;
                d[xy(2, 3)] = src[5];
                d[xy(9, 3)] = src[5] | 0x4000;
                d += 1;
            }
            dd[xy(0, 0)] = src[0];
            dd[xy(15, 0)] = src[0] | 0x4000;
            dd[xy(1, 0)] = src[1];
            dd[xy(7, 0)] = src[1];
            dd[xy(8, 0)] = src[1];
            dd[xy(14, 0)] = src[1];
            dd[xy(1, 2)] = src[3];
            dd[xy(14, 2)] = src[3] | 0x4000;
        },
        0x10, 0x11, 0x13, 0x1a, 0x22, 0x23, 0x24, 0x25,
        0x3e, 0x3f, 0x40, 0x41, 0x42,
        0x43, 0x44, 0x45, 0x46, 0x49, 0x4a, 0x4f,
        0x50, 0x51, 0x52, 0x53, 0x56, 0x57, 0x58, 0x59,
        0x5e, 0x5f, 0x63, 0x64, 0x65,
        0x75, 0x7c, 0x7d, 0x7e => RoomDraw_Rightwards2x2(src, dst),
        // 12 -  Rupee Floor
        0x12 => {
            if (v.dung_savegame_state_bits.* & 0x1000 != 0)
                return;
            src = SrcPtr(0x1dd6);
            dst = v.dung_bg2 + index(dsto | layerBit(0x1000));
            for (0..3) |_| {
                dst[xy(0, 0)] = src[0];
                dst[xy(0, 3)] = src[0];
                dst[xy(0, 6)] = src[0];
                dst[xy(0, 1)] = src[1];
                dst[xy(0, 4)] = src[1];
                dst[xy(0, 7)] = src[1];
                dst += 2;
            }
        },
        // 14 -  Down Warp Door
        0x14, 0x4E, 0x67, 0x68, 0x6c, 0x6d, 0x79 => RoomDraw_1x3_rightwards(4, src, dst),
        // 15 -  Kholdstare Shell - BG2
        0x15 => {
            if (v.dung_savegame_state_bits.* & 0x8000 != 0)
                return;
            src = SrcPtr(0x1dfa);
            RoomDraw_SomeBigDecors(10, src, dsto);
        },
        // 16 -  Single Hammer Peg
        0x16 => RoomDraw_HammerPegSingle(src, dst, dsto),
        // 18 -  Cell Lock
        0x18 => {
            const i = v.dung_num_bigkey_locks_x2.* >> 1;
            v.dung_num_bigkey_locks_x2.* +%= 2;
            if (v.dung_savegame_state_bits.* & t.kChestOpenMasks[i] == 0) {
                v.dung_chest_locations[i] = dsto *% 2;
                RoomDraw_Rightwards2x2(SrcPtr(0x1494), dst);
            } else {
                v.dung_chest_locations[i] = 0;
            }
        },
        // 19 -  Chest
        0x19 => {
            if (v.main_module_index.* == 26)
                return;
            const i = v.dung_num_chests_x2.* >> 1;
            v.dung_num_chests_x2.* +%= 2;
            v.dung_num_bigkey_locks_x2.* = v.dung_num_chests_x2.*;

            var h: c_int = -1;
            if (v.dung_hdr_tag[0] == 0x27 or v.dung_hdr_tag[0] == 0x3c or
                v.dung_hdr_tag[0] == 0x3e or (v.dung_hdr_tag[0] >= 0x29 and v.dung_hdr_tag[0] < 0x33))
            {
                h = 0;
            } else if (v.dung_hdr_tag[1] == 0x27 or v.dung_hdr_tag[1] == 0x3c or
                v.dung_hdr_tag[1] == 0x3e or (v.dung_hdr_tag[1] >= 0x29 and v.dung_hdr_tag[1] < 0x33))
            {
                h = 1;
            }

            v.dung_chest_locations[i] = (dsto | layerBit(0x1000)) *% 2;
            if (v.dung_savegame_state_bits.* & t.kChestOpenMasks[i] == 0) {
                if (h >= 0) {
                    if (v.dung_savegame_state_bits.* & t.kChestOpenMasks[index(h)] == 0)
                        return;
                    v.dung_hdr_tag[index(h)] = 0;
                }
                RoomDraw_Rightwards2x2(SrcPtr(0x149c), dst);
            } else {
                v.dung_chest_locations[i] = 0;
                if (h >= 0)
                    v.dung_hdr_tag[index(h)] = 0;
                RoomDraw_Rightwards2x2(SrcPtr(0x14a4), dst);
            }
        },
        // 1B -  Stair / 1C -  Stair [S](Layer)
        0x1b, 0x1c => {
            if (idx == 0x1b) {
                v.dung_stairs_table_1[v.dung_num_stairs_1.* >> 1] = dsto;
                v.dung_num_stairs_1.* +%= 2;
            } else {
                v.dung_stairs_table_2[v.dung_num_stairs_2.* >> 1] = dsto;
                v.dung_num_stairs_2.* +%= 2;
            }
            // stair1b:
            for (0..4) |_| {
                both_p1(index(dsto) + xy(0, 0), src[0]);
                both_p1(index(dsto) + xy(0, 1), src[1]);
                both_p1(index(dsto) + xy(0, 2), src[2]);
                both_p1(index(dsto) + xy(0, 3), src[3]);
                src += 4;
                dsto +%= 1;
            }
        },
        // 1D -  Stair Wet [S](Layer) / 33 -  Stairs Submerged [S](layer)
        0x1d, 0x33 => {
            if (idx == 0x33) wet: {
                if (v.dung_hdr_tag[1] == 27) {
                    if (v.save_dung_info[index(v.dungeon_room_index.*)] & 0x100 == 0) {
                        v.dung_hdr_bg2_properties.* = 0;
                        break :wet;
                    }
                    v.CGWSEL_copy.* = 2;
                    v.CGADSUB_copy.* = 0x62;
                }
                v.dung_stairs_table_2[v.dung_num_inroom_upsouth_stairs_water.* >> 1] = dsto;
                v.dung_num_inroom_upsouth_stairs_water.* +%= 2;
                RoomDraw_4x4(src, dst);
                return;
            }
            // stairs_wet:
            v.dung_stairs_table_2[v.dung_num_stairs_wet.* >> 1] = dsto;
            v.dung_num_stairs_wet.* +%= 2;
            RoomDraw_4x4(src, dst);
        },
        // 1E -  Staircase going Up(Up)
        0x1e => {
            v.dung_inter_starcases[v.dung_num_inter_room_upnorth_straight_stairs.* >> 1] = dsto;
            const nv = v.dung_num_inter_room_upnorth_straight_stairs.* +% 2;
            v.dung_num_inter_room_upnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_upsouth_straight_stairs.* = nv;
            v.dung_num_inter_room_southdown_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
            RoomDraw_Object_Nx4(4, src, dst);
        },
        // 1F -  Staircase Going Down (Up)
        0x1f => {
            v.dung_inter_starcases[v.dung_num_inter_room_downnorth_straight_stairs.* >> 1] = dsto;
            const nv = v.dung_num_inter_room_downnorth_straight_stairs.* +% 2;
            v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
            RoomDraw_Object_Nx4(4, src, dst);
        },
        // 20 -  Staircase Going Up (Down)
        0x20 => {
            v.dung_inter_starcases[v.dung_num_inter_room_upsouth_straight_stairs.* >> 1] = dsto;
            const nv = v.dung_num_inter_room_upsouth_straight_stairs.* +% 2;
            v.dung_num_inter_room_upsouth_straight_stairs.* = nv;
            v.dung_num_inter_room_southdown_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs.* = nv;
            v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
            v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
            v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
            RoomDraw_Object_Nx4(4, src, dst);
        },
        // 21 -  Staircase Going Down (Down)
        0x21 => {
            v.dung_inter_starcases[v.dung_num_inter_room_downsouth_straight_stairs.* >> 1] = dsto;
            v.dung_num_inter_room_downsouth_straight_stairs.* = v.dung_num_inter_room_downsouth_straight_stairs.* +% 2;
            RoomDraw_Object_Nx4(4, src, dst);
        },
        // 26 -  Staircase Going Up (Lower) .. 29 -  Staircase Going Down (Lower)
        0x26, 0x27, 0x28, 0x29 => {
            switch (idx) {
                0x26 => {
                    const i = v.dung_num_inter_room_upnorth_straight_stairs.* >> 1;
                    v.dung_inter_starcases[i] = dsto | layerBit(0x1000);
                    const nv = v.dung_num_inter_room_upnorth_straight_stairs.* +% 2;
                    v.dung_num_inter_room_upnorth_straight_stairs.* = nv;
                    v.dung_num_inter_room_upsouth_straight_stairs.* = nv;
                    v.dung_num_inter_room_southdown_stairs.* = nv;
                    v.dung_num_wall_downnorth_spiral_stairs.* = nv;
                    v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
                    v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
                    v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
                },
                0x27 => {
                    const i = v.dung_num_inter_room_downnorth_straight_stairs.* >> 1;
                    v.dung_inter_starcases[i] = dsto | layerBit(0x1000);
                    const nv = v.dung_num_inter_room_downnorth_straight_stairs.* +% 2;
                    v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
                    v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
                },
                0x28 => {
                    const i = v.dung_num_inter_room_upsouth_straight_stairs.* >> 1;
                    v.dung_inter_starcases[i] = dsto | layerBit(0x1000);
                    const nv = v.dung_num_inter_room_upsouth_straight_stairs.* +% 2;
                    v.dung_num_inter_room_upsouth_straight_stairs.* = nv;
                    v.dung_num_inter_room_southdown_stairs.* = nv;
                    v.dung_num_wall_downnorth_spiral_stairs.* = nv;
                    v.dung_num_wall_downnorth_spiral_stairs_2.* = nv;
                    v.dung_num_inter_room_downnorth_straight_stairs.* = nv;
                    v.dung_num_inter_room_downsouth_straight_stairs.* = nv;
                },
                else => {
                    const i = v.dung_num_inter_room_downsouth_straight_stairs.* >> 1;
                    v.dung_inter_starcases[i] = dsto | layerBit(0x1000);
                    v.dung_num_inter_room_downsouth_straight_stairs.* = v.dung_num_inter_room_downsouth_straight_stairs.* +% 2;
                },
            }
            if (idx == 0x26 or idx == 0x27) {
                // door26:
                for (0..4) |_| {
                    both_p1(index(dsto), src[0]);
                    v.dung_bg1[index(dsto) + xy(0, 1)] = src[1];
                    v.dung_bg1[index(dsto) + xy(0, 2)] = src[2];
                    v.dung_bg1[index(dsto) + xy(0, 3)] = src[3];
                    src += 4;
                    dsto +%= 1;
                }
                dsto -%= 4 + 4 * 64;
            } else {
                // door28:
                for (0..4) |_| {
                    v.dung_bg1[index(dsto) + xy(0, 0)] = src[0];
                    v.dung_bg1[index(dsto) + xy(0, 1)] = src[1];
                    v.dung_bg1[index(dsto) + xy(0, 2)] = src[2];
                    both_p1(index(dsto) + xy(0, 3), src[3]);
                    src += 4;
                    dsto +%= 1;
                }
                dsto = dsto -% 4 +% 4 * 64;
            }
            // copy_door_bg2:
            v.dung_bg2[index(dsto) + xy(0, 0)] |= 0x2000;
            v.dung_bg2[index(dsto) + xy(0, 1)] |= 0x2000;
            v.dung_bg2[index(dsto) + xy(0, 2)] |= 0x2000;
            v.dung_bg2[index(dsto) + xy(0, 3)] |= 0x2000;
        },
        // 2A -  Dark Room BG2 Mask
        0x2a => {
            c.RoomDraw_SingleLampCone(0x514, 0x16dc);
            c.RoomDraw_SingleLampCone(0x554, 0x17f6);
            c.RoomDraw_SingleLampCone(0x1514, 0x1914);
            c.RoomDraw_SingleLampCone(0x1554, 0x1a2a);
        },
        // 2B -  Staircase Going Down (Lower) not really
        0x2b => DrawBigGraySegment(0x1010, src, dst, dsto),
        // 2C -  Large Pick Up Block
        0x2c => {
            DrawBigGraySegment(0x2020, SrcPtr(0xe62), dst, dsto);
            DrawBigGraySegment(0x2121, SrcPtr(0xe6a), dst + 2, dsto +% 2);
            DrawBigGraySegment(0x2222, SrcPtr(0xe72), dst + xy(0, 2), dsto +% xyw(0, 2));
            DrawBigGraySegment(0x2323, SrcPtr(0xe7a), dst + xy(2, 2), dsto +% xyw(2, 2));
        },
        // 2D -  Agahnim Altar
        0x2d => {
            src = SrcPtr(0x1b4a);
            var d = v.dung_bg2 + index(dsto);
            for (0..14) |_| {
                var q = src[0];
                d[0] = q;
                d[13] = q | 0x4000;
                q = src[14];
                d[2] = q;
                d[1] = q;
                d[12] = q ^ 0x4000;
                d[11] = q ^ 0x4000;
                q = src[28];
                d[3] = q;
                d[10] = q ^ 0x4000;
                q = src[42];
                d[4] = q;
                d[9] = q ^ 0x4000;
                q = src[56];
                d[5] = q;
                d[8] = q ^ 0x4000;
                q = src[70];
                d[6] = q;
                d[7] = q ^ 0x4000;
                src += 1;
                d += 64;
            }
        },
        // 2E -  Agahnim Room
        0x2e => c.RoomDraw_AgahnimsWindows(dsto),
        // 2F -  Pot
        0x2f => RoomDraw_SinglePot(src, dst, dsto),
        // 30 -  ??
        0x30 => DrawBigGraySegment(0x1212, src, dst, dsto),
        // 31 -  Big Chest
        0x31 => {
            const i = v.dung_num_chests_x2.*;
            v.dung_chest_locations[i >> 1] = dsto *% 2 | 0x8000 | layerBit(0x2000);
            if (v.dung_savegame_state_bits.* & t.kChestOpenMasks[i >> 1] != 0) {
                v.dung_chest_locations[i >> 1] = 0;
                v.dung_num_chests_x2.* = i +% 2;
                v.dung_num_bigkey_locks_x2.* = i +% 2;
                RoomDraw_1x3_rightwards(4, SrcPtr(0x14c4), dst);
            } else {
                v.dung_num_chests_x2.* = i +% 2;
                v.dung_num_bigkey_locks_x2.* = i +% 2;
                RoomDraw_1x3_rightwards(4, SrcPtr(0x14ac), dst);
            }
        },
        // 32 -  Big Chest Open
        0x32 => RoomDraw_1x3_rightwards(4, src, dst),
        0x34, 0x35, 0x36, 0x37, 0x38, 0x39 => unreachable,
        // 3A -  Pipe Ride Mouth [S]
        0x3a, 0x3b => {
            RoomDraw_1x3_rightwards(4, src, dst);
            RoomDraw_1x3_rightwards(4, src + 12, dst + xy(0, 3));
        },
        // 3C -  Pipe Ride Mouth [E]
        0x3c, 0x3d, 0x5c => RoomDraw_Object_Nx4(6, src, dst),
        // 47 -  Bomb Floor
        0x47 => RoomDraw_BombableFloor(src, dst, dsto),
        // 48 -  Fake Bomb Floor
        0x48, 0x66, 0x6b, 0x7a => RoomDraw_4x4(src, dst),
        0x4b, 0x76, 0x77 => RoomDraw_1x3_rightwards(8, src, dst),
        0x4c => RoomDraw_SomeBigDecors(6, SrcPtr(0x1f92), dsto),
        // 5D -  Forge
        0x4d, 0x5d => RoomDraw_1x3_rightwards(6, src, dst),
        0x54 => c.RoomDraw_FortuneTellerRoom(dsto),
        // 5B -  Water Troof
        0x55, 0x5b => {
            dst[xy(0, 0)] = src[0];
            dst[xy(1, 0)] = src[1];
            dst[xy(2, 0)] = src[2];
            for (0..3) |_| {
                dst[xy(0, 1)] = src[3];
                dst[xy(1, 1)] = src[4];
                dst[xy(2, 1)] = src[5];
                dst += xy(0, 1);
            }
            dst[xy(0, 1)] = src[6];
            dst[xy(1, 1)] = src[7];
            dst[xy(2, 1)] = src[8];
        },
        // 5A -  Plate on Table
        0x5a => RoomDraw_WaterHoldingObject(2, src, dst),
        // 60 -  Left/Right Warp Door
        0x60, 0x61 => {
            RoomDraw_1x3_rightwards(3, src, dst);
            RoomDraw_1x3_rightwards(3, src + 9, dst + xy(0, 3));
        },
        // 62 ??
        0x62 => {
            src = SrcPtr(0x20f6);
            var d = v.dung_bg1 + index(dsto);
            for (0..22) |_| {
                d[xy(0, 0)] = src[0];
                d[xy(0, 1)] = src[1];
                d[xy(0, 2)] = src[2];
                d[xy(0, 3)] = src[3];
                d[xy(0, 4)] = src[4];
                d[xy(0, 5)] = src[5];
                d[xy(0, 6)] = src[6];
                d[xy(0, 7)] = src[7];
                d[xy(0, 8)] = src[8];
                d[xy(0, 9)] = src[9];
                d[xy(0, 10)] = src[10];
                d += 1;
                src += 11;
            }
            d -= 22;
            src = SrcPtr(0x22da);
            for (0..3) |_| {
                d[xy(9, 11)] = src[0];
                d[xy(9, 12)] = src[3];
                d += 1;
                src += 1;
            }
        },
        // 69 -  Left Crack Wall
        0x69, 0x6a, 0x6e, 0x6f => RoomDraw_Object_Nx4(3, src, dst),
        // 70 -  Window Light
        0x70 => {
            RoomDraw_4x4(src, dst + xy(0, 0));
            RoomDraw_4x4(SrcPtr(0x2376), dst + xy(0, 2));
            RoomDraw_4x4(SrcPtr(0x2396), dst + xy(0, 6));
        },
        // 71 -  Floor Light Blind BG2
        0x71 => {
            if (v.save_dung_info[101] & 0x100 == 0)
                return;
            Object_Draw8x8(src, dst);
        },
        // 72 -  TrinexxShell  Boss Goo/Shell BG2
        0x72 => {
            if (v.dung_savegame_state_bits.* & 0x8000 != 0)
                return;
            RoomDraw_SomeBigDecors(10, src, dsto);
        },
        // 73 -  Entire floor is pit, Bg2 Full Mask
        0x73 => RoomDraw_FloorChunks(SrcPtr(0xe0)),
        // 74 -  Boss Entrance
        0x74 => Object_Draw8x8(src, dst),
        // Triforce
        0x78 => {
            RoomDraw_4x4(src, dst);
            RoomDraw_4x4(src + 16, adv(dst, 4 * 64 - 2));
            RoomDraw_4x4(src + 16, dst + xy(2, 4));
        },
        // 7B -  Vitreous Boss?
        0x7b => {
            RoomDraw_A_Many32x32Blocks(5, src, dst);
            RoomDraw_A_Many32x32Blocks(5, src, dst + xy(0, 4));
        },
        else => unreachable,
    }
}

pub export fn Door_Draw_Helper4(door_type: u8, dsto: u16) callconv(.c) void {
    var tt = c.RoomDraw_FlagDoorsAndGetFinalType(1, door_type, dsto);
    if (tt & 0x100 != 0)
        return;

    var new_type: c_int = undefined;
    remap: {
        new_type = c.kDoorType_Regular;
        if (!(tt == c.kDoorType_1E or tt == c.kDoorType_36)) {
            new_type = c.kDoorType_ShuttersTwoWay;
            if (tt != c.kDoorType_38) break :remap;
        }
        const i: c_int = @as(c_int, @intCast(v.dung_cur_door_idx.* >> 1)) - 1;
        v.door_type_and_slot[index(i)] = u16w((i << 8) | new_type);
        tt = new_type;
    }

    var src = SrcPtr(t.kDoorTypeSrcData2[index(@divTrunc(tt, 2))]);
    var dst = DstoPtr(dsto);
    for (0..4) |_| {
        dst[xy(0, 1)] = src[0];
        dst[xy(0, 2)] = src[1];
        dst[xy(0, 3)] = src[2];
        dst += 1;
        src += 3;
    }
}

pub export fn WriteAttr1(j: c_int, attr: u16) callconv(.c) void {
    v.dung_bg1_attr_table[index(j) + 0] = @truncate(attr);
    v.dung_bg1_attr_table[index(j) + 1] = @truncate(attr >> 8);
}

pub export fn WriteAttr2(j: c_int, attr: u16) callconv(.c) void {
    v.dung_bg2_attr_table[index(j) + 0] = @truncate(attr);
    v.dung_bg2_attr_table[index(j) + 1] = @truncate(attr >> 8);
}

pub export fn Dungeon_OpeningLockedDoor_Combined(skip_anim: bool) callconv(.c) void {
    var ctr: u8 = 2;

    middle: {
        var do_step12 = false;
        if (skip_anim) {
            v.door_animation_step_indicator.* = 16;
            do_step12 = true;
        } else {
            v.door_animation_step_indicator.* +%= 1;
            if (v.door_animation_step_indicator.* != 4) {
                if (v.door_animation_step_indicator.* != 12)
                    break :middle;
                do_step12 = true;
            }
        }
        if (do_step12) {
            // step12:
            const m = c.kUpperBitmasks[v.dung_bg2_attr_table[index(v.dung_cur_door_pos.*)] & 7];
            v.dung_door_opened_incl_adjacent.* |= m;
            v.dung_door_opened.* |= m;
            ctr = 4;
        }
        v.door_open_closed_counter.* = ctr;

        const k: c_int = v.dung_bg2_attr_table[index(v.dung_cur_door_pos.*)] & 0xf;
        const dma_ptr = c.DrawDoorOpening_Step1(k, 0);
        _ = c.Dungeon_PrepOverlayDma_nextPrep(dma_ptr, v.dung_door_tilemap_address[index(k)]);
        v.sound_effect_2.* = 21;
        v.nmi_copy_packets_flag.* = 1;
    }

    // middle:
    if (v.door_animation_step_indicator.* == 16) {
        c.Dungeon_LoadToggleDoorAttr_OtherEntry(v.dung_bg2_attr_table[index(v.dung_cur_door_pos.*)] & 0xf);
        if (v.dung_bg2_attr_table[index(v.dung_cur_door_pos.*)] >= 0xf0) {
            const k = v.dung_bg2_attr_table[index(v.dung_cur_door_pos.*)] & 0xf;
            const door_type: c_int = @as(u8, @truncate(v.door_type_and_slot[k]));
            if (door_type >= c.kDoorType_StairMaskLocked0 and door_type <= c.kDoorType_StairMaskLocked3)
                c.DrawCompletelyOpenDoor();
        }
        v.submodule_index.* = 0;
    }
}

// ---------------------------------------------------------------------------
// from dungeon_part2.zig
// ---------------------------------------------------------------------------
/// misc.h keeps this as a `static inline` with no linkable symbol, and it
/// searches *backwards*.
/// `memcpy(&dung_line_ptrs_row0, tab, 33)`: the 33 bytes starting at 0x7E00BF.
/// `WORD(level_data[offs])`: unaligned little-endian 16-bit read.

pub export fn PrepareDungeonExitFromBossFight() callconv(.c) void { // 80f945
    c.SavePalaceDeaths();
    c.SaveDungeonKeys();
    v.dung_savegame_state_bits.* |= 0x8000;
    c.Dungeon_FlagRoomData_Quadrants();

    const j = FindInByteArray_p2(&t.kDungeonExit_From, low(v.dungeon_room_index).*, t.kDungeonExit_From.len);
    std.debug.assert(j >= 0);
    low(v.dungeon_room_index).* = t.kDungeonExit_To[index(j)];
    if (low(v.dungeon_room_index).* == 0x20) {
        v.sram_progress_indicator.* = 3;
        v.save_ow_event_info[2] |= 0x20;
        v.savegame_is_darkworld.* ^= 0x40;
        c.Sprite_LoadGraphicsProperties_light_world_only();
        _ = c.Ancilla_TerminateSelectInteractives(0);
        v.link_disable_sprite_damage.* = 0;
        v.button_b_frames.* = 0;
        v.button_mask_b_y.* = 0;
        v.link_force_hold_sword_up.* = 0;
        v.flag_is_link_immobilized.* = 1;
        v.saved_module_for_menu.* = 8;
        v.main_module_index.* = 21;
        v.submodule_index.* = 0;
        v.subsubmodule_index.* = 0;
    } else if (low(v.dungeon_room_index).* == 0xd) {
        v.main_module_index.* = 24;
        v.submodule_index.* = 0;
        v.overworld_map_state.* = 0;
        v.CGADSUB_copy.* = 0x20;
    } else {
        if (j >= 3) {
            v.music_control.* = 0xf1;
            v.music_unk1.* = 0xf1;
            v.main_module_index.* = 22;
        } else {
            v.main_module_index.* = 19;
        }
        v.saved_module_for_menu.* = 8;
        v.submodule_index.* = 0;
        v.subsubmodule_index.* = 0;
    }
}

pub export fn Dungeon_LoadRoom() callconv(.c) void { // 81873a
    c.Dungeon_LoadHeader();
    v.dung_unk6.* = 0;

    v.dung_hdr_collision_2_mirror.* = v.dung_hdr_collision_2.*;
    v.dung_hdr_collision_2_mirror_PADDING.* = v.dung_hdr_tag[0];
    v.dung_some_subpixel[0] = 0x30;
    v.dung_some_subpixel[1] = 0xff;
    v.dung_floor_move_flags.* = 0;
    v.word_7E0420.* = 0;
    v.dung_floor_y_vel.* = 0;
    v.dung_floor_x_vel.* = 0;
    v.dung_floor_y_offs.* = 0;
    v.dung_floor_x_offs.* = 0;
    v.invisible_door_dir_and_index_x2.* = 0xffff;
    v.dung_blastwall_flag_y.* = 0;
    v.dung_blastwall_flag_x.* = 0;
    v.dung_unk_blast_walls_3.* = 0;
    v.dung_unk_blast_walls_2.* = 0;
    v.water_hdma_var5.* = 0;
    v.dung_num_toggle_floor.* = 0;
    v.dung_num_toggle_palace.* = 0;
    v.dung_unk2.* = 0;
    v.dung_cur_quadrant_upload.* = 0;
    v.dung_num_inter_room_upnorth_stairs.* = 0;
    v.dung_num_inter_room_southdown_stairs.* = 0;
    v.dung_num_inroom_upnorth_stairs.* = 0;
    v.dung_num_inroom_southdown_stairs.* = 0;
    v.dung_num_interpseudo_upnorth_stairs.* = 0;
    v.dung_num_inroom_upnorth_stairs_water.* = 0;
    v.dung_num_activated_water_ladders.* = 0;
    v.dung_num_water_ladders.* = 0;
    v.dung_some_stairs_unk4.* = 0;
    v.dung_num_stairs_1.* = 0;
    v.dung_num_stairs_2.* = 0;
    v.dung_num_stairs_wet.* = 0;
    v.dung_num_inroom_upsouth_stairs_water.* = 0;
    v.dung_num_wall_upnorth_spiral_stairs.* = 0;
    v.dung_num_wall_downnorth_spiral_stairs.* = 0;
    v.dung_num_wall_upnorth_spiral_stairs_2.* = 0;
    v.dung_num_wall_downnorth_spiral_stairs_2.* = 0;
    v.dung_num_inter_room_upnorth_straight_stairs.* = 0;
    v.dung_num_inter_room_upsouth_straight_stairs.* = 0;
    v.dung_num_inter_room_downnorth_straight_stairs.* = 0;
    v.dung_num_inter_room_downsouth_straight_stairs.* = 0;
    v.dung_exit_door_addresses[0] = 0;
    v.dung_exit_door_addresses[1] = 0;
    v.dung_exit_door_addresses[2] = 0;
    v.dung_exit_door_addresses[3] = 0;
    v.dung_exit_door_count.* = 0;
    v.dung_door_switch_triggered.* = 0;
    v.dung_num_star_shaped_switches.* = 0;
    v.dung_misc_objs_index.* = 0;
    v.dung_index_of_torches.* = 0;
    v.dung_num_chests_x2.* = 0;
    v.dung_num_bigkey_locks_x2.* = 0;
    v.dung_unk5.* = 0;
    v.dung_cur_door_idx.* = 0;

    for (0..16) |i| {
        v.dung_door_tilemap_address[i] = 0;
        v.door_type_and_slot[i] = 0;
        v.dung_door_direction[i] = 0;
        v.dung_torch_timers[i] = 0;
        v.dung_replacement_tile_state[i] = 0;
        v.dung_object_pos_in_objdata[i] = 0;
        v.dung_object_tilemap_pos[i] = 0;
    }

    const cur_p0: [*]const u8 = c.GetDungeonRoomLayout(v.dungeon_room_index.*);
    v.dung_load_ptr_offs.* = 0;
    RoomDraw_DrawFloors(cur_p0);

    const old_offs = v.dung_load_ptr_offs.*;
    v.dung_layout_and_starting_quadrant.* = cur_p0[v.dung_load_ptr_offs.*];

    const cur_p1: [*]const u8 = c.GetDefaultRoomLayout(v.dung_layout_and_starting_quadrant.* >> 2);

    v.dung_load_ptr_offs.* = 0;
    RoomDraw_DrawAllObjects(cur_p1);

    v.dung_load_ptr_offs.* = old_offs +% 1;

    RoomDraw_DrawAllObjects(cur_p0); // Draw Layer 1 objects to BG2
    v.dung_load_ptr_offs.* +%= 2;

    setLinePtrs(&t.kDungeon_DrawObjectOffsets_BG2);
    RoomDraw_DrawAllObjects(cur_p0); // Draw Layer 2 objects to BG2
    v.dung_load_ptr_offs.* +%= 2;

    setLinePtrs(&t.kDungeon_DrawObjectOffsets_BG1);
    RoomDraw_DrawAllObjects(cur_p0); // Draw Layer 3 objects to BG2

    v.dung_load_ptr_offs.* = 0;
    while (v.dung_load_ptr_offs.* != 0x18C) : (v.dung_load_ptr_offs.* +%= 4) {
        const m = v.movable_block_datas[v.dung_load_ptr_offs.* >> 2];
        if (m.room == v.dungeon_room_index.*)
            c.DrawObjects_PushableBlock(m.tilemap, v.dung_load_ptr_offs.*);
    }

    var tile: u16 = undefined;

    v.dung_index_of_torches_start.* = v.dung_misc_objs_index.*;
    v.dung_index_of_torches.* = v.dung_index_of_torches_start.*;
    var i: c_int = 0;
    while (true) {
        if (v.dung_torch_data[index(i >> 1)] == v.dungeon_room_index.*) {
            i += 2;

            while (true) {
                tile = v.dung_torch_data[index(i >> 1)];
                i += 2;
                c.DrawObjects_LightableTorch(tile, u16w(i - 2));
                if (v.dung_torch_data[index(i >> 1)] == 0xffff)
                    break;
            }
            break;
        }
        i += 2;
        while (true) {
            tile = v.dung_torch_data[index(i >> 1)];
            i += 2;
            if (tile == 0xffff)
                break;
        }
        if (i == 0x120)
            break;
    }

    v.dung_load_ptr_offs.* = 0x120;
}

pub export fn RoomDraw_DrawAllObjects(level_data: [*]const u8) callconv(.c) void { // 8188e4
    while (true) {
        v.dung_draw_height_indicator.* = 0;
        v.dung_draw_width_indicator.* = 0;
        const d = wordAt(level_data, v.dung_load_ptr_offs.*);
        if (d == 0xffff)
            return;
        if (d == 0xfff0)
            break;
        RoomData_DrawObject(d, level_data);
    }
    while (true) {
        v.dung_load_ptr_offs.* +%= 2;
        const d = wordAt(level_data, v.dung_load_ptr_offs.*);
        if (d == 0xffff)
            return;
        RoomData_DrawObject_Door(d);
    }
}

pub export fn RoomData_DrawObject_Door(a: u16) callconv(.c) void { // 818916
    const door_type: c_int = ci(a >> 8);
    const position: c_int = ci(a >> 4 & 0xf);

    switch (a & 3) {
        0 => RoomDraw_Door_North(door_type, position),
        1 => RoomDraw_Door_South(door_type, position),
        2 => RoomDraw_Door_West(door_type, position),
        3 => RoomDraw_Door_East(door_type, position),
        else => {},
    }
}

pub export fn RoomData_DrawObject(r0: u16, level_data: [*]const u8) callconv(.c) void { // 81893c
    const offs = v.dung_load_ptr_offs.*;
    var idx: u8 = level_data[@as(usize, offs) + 2];
    v.dung_load_ptr_offs.* = offs +% 3;

    if ((r0 & 0xfc) != 0xfc) {
        v.dung_draw_width_indicator.* = (r0 & 3);
        v.dung_draw_height_indicator.* = (r0 >> 8) & 3;
        const x: u8 = @as(u8, @truncate(r0)) >> 2;
        const y: u8 = @truncate(r0 >> 10);
        const dst: u16 = @as(u16, y) *% 64 +% @as(u16, x);
        if (idx < 0xf8) {
            LoadType1ObjectSubtype1(idx, DstoPtr(dst), dst);
        } else {
            idx = @truncate((@as(u16, idx & 7) << 4) | (((r0 >> 8) & 3) << 2) | (r0 & 3));
            LoadType1ObjectSubtype3(idx, DstoPtr(dst), dst);
        }
    } else {
        const x: u8 = @truncate(((r0 & 3) << 4) | ((r0 >> 12) & 0xf));
        const y: u8 = @truncate((((r0 >> 8) & 0xf) << 2) | (@as(u16, idx) >> 6));
        const dst: u16 = @as(u16, y) *% 64 +% @as(u16, x);
        LoadType1ObjectSubtype2(idx & 0x3f, DstoPtr(dst), dst);
    }
}

pub export fn RoomDraw_DrawFloors(level_data: [*]const u8) callconv(.c) void { // 8189dc
    setLinePtrs(&t.kDungeon_DrawObjectOffsets_BG2);
    const ft = level_data[v.dung_load_ptr_offs.*];
    v.dung_load_ptr_offs.* +%= 1;
    v.dung_floor_1_filler_tiles.* = ft & 0xf0;
    RoomDraw_FloorChunks(SrcPtr(v.dung_floor_1_filler_tiles.*));
    setLinePtrs(&t.kDungeon_DrawObjectOffsets_BG1);
    v.dung_floor_2_filler_tiles.* = @as(u16, ft & 0xf) << 4;
    RoomDraw_FloorChunks(SrcPtr(v.dung_floor_2_filler_tiles.*));
}

pub export fn RoomDraw_AgahnimsWindows(dsto: u16) callconv(.c) void { // 819ea3
    var src: Tiles = undefined;

    var d: Words = v.dung_bg2 + dsto;
    src = SrcPtr(0x1BF2);
    for (0..6) |_| {
        d[xy_p2(19, 4)] = src[0];
        d[xy_p2(13, 4)] = src[0];
        d[xy_p2(7, 4)] = src[0];
        d[xy_p2(19, 5)] = src[1];
        d[xy_p2(13, 5)] = src[1];
        d[xy_p2(7, 5)] = src[1];
        d[xy_p2(19, 6)] = src[2];
        d[xy_p2(13, 6)] = src[2];
        d[xy_p2(7, 6)] = src[2];
        d[xy_p2(19, 7)] = src[3];
        d[xy_p2(13, 7)] = src[3];
        d[xy_p2(7, 7)] = src[3];
        src += 4;
        d += xy_p2(1, 0);
    }
    d -= 6;

    src = SrcPtr(0x1c22);
    for (0..5) |_| {
        const j: u16 = src[0];
        d[xy_p2(8, 4)] = j;
        d[xy_p2(7, 5)] = j;
        d[xy_p2(6, 6)] = j;
        d[xy_p2(5, 7)] = j;
        d[xy_p2(4, 8)] = j;
        d[xy_p2(3, 9)] = j;
        d[xy_p2(2, 10)] = j;
        d[xy_p2(29, 10)] = j | 0x4000;
        d[xy_p2(28, 9)] = j | 0x4000;
        d[xy_p2(27, 8)] = j | 0x4000;
        d[xy_p2(26, 7)] = j | 0x4000;
        d[xy_p2(25, 6)] = j | 0x4000;
        d[xy_p2(24, 5)] = j | 0x4000;
        d[xy_p2(23, 4)] = j | 0x4000;
        src += 1;
        d += xy_p2(0, 1);
    }
    d -= xy_p2(0, 1) * 5;

    src = SrcPtr(0x1c2c);
    for (0..6) |_| {
        var j: u16 = src[0];
        d[xy_p2(2, 23)] = j;
        d[xy_p2(2, 17)] = j;
        d[xy_p2(2, 11)] = j;
        d[xy_p2(29, 23)] = j | 0x4000;
        d[xy_p2(29, 17)] = j | 0x4000;
        d[xy_p2(29, 11)] = j | 0x4000;
        j = src[1];
        d[xy_p2(3, 23)] = j;
        d[xy_p2(3, 17)] = j;
        d[xy_p2(3, 11)] = j;
        d[xy_p2(28, 23)] = j | 0x4000;
        d[xy_p2(28, 17)] = j | 0x4000;
        d[xy_p2(28, 11)] = j | 0x4000;
        j = src[2];
        d[xy_p2(4, 23)] = j;
        d[xy_p2(4, 17)] = j;
        d[xy_p2(4, 11)] = j;
        d[xy_p2(27, 23)] = j | 0x4000;
        d[xy_p2(27, 17)] = j | 0x4000;
        d[xy_p2(27, 11)] = j | 0x4000;
        j = src[3];
        d[xy_p2(5, 23)] = j;
        d[xy_p2(5, 17)] = j;
        d[xy_p2(5, 11)] = j;
        d[xy_p2(26, 23)] = j | 0x4000;
        d[xy_p2(26, 17)] = j | 0x4000;
        d[xy_p2(26, 11)] = j | 0x4000;
        src += 4;
        d += xy_p2(0, 1);
    }
    d -= xy_p2(0, 1) * 6;

    src = SrcPtr(0x1c5c);
    for (0..6) |_| {
        d[xy_p2(18, 9)] = src[0];
        d[xy_p2(12, 9)] = src[0];
        d[xy_p2(18, 10)] = src[6];
        d[xy_p2(12, 10)] = src[6];
        src += 1;
        d += xy_p2(1, 0);
    }
    d -= xy_p2(1, 0) * 6;

    src = SrcPtr(0x1c74);
    for (0..6) |_| {
        d[xy_p2(7, 20)] = src[0];
        d[xy_p2(7, 14)] = src[0];
        d[xy_p2(8, 20)] = src[1];
        d[xy_p2(8, 14)] = src[1];
        src += 2;
        d += xy_p2(0, 1);
    }
    d -= xy_p2(0, 1) * 6;

    src = SrcPtr(0x1c8c);
    for (0..5) |_| {
        d[xy_p2(7, 9)] = src[0];
        d[xy_p2(7, 10)] = src[1];
        d[xy_p2(7, 11)] = src[2];
        d[xy_p2(7, 12)] = src[3];
        d[xy_p2(7, 13)] = src[4];
        src += 5;
        d += xy_p2(1, 0);
    }
    d -= xy_p2(1, 0) * 5;

    for (0..4) |_| {
        d[xy_p2(14, 28)] |= 0x2000;
        d[xy_p2(14, 29)] |= 0x2000;
        d += xy_p2(1, 0);
    }
}

pub export fn RoomDraw_FortuneTellerRoom(dsto: u16) callconv(.c) void { // 81a095
    var src: Tiles = SrcPtr(0x202e);
    const src_org: Tiles = src;
    var d: Words = v.dung_bg2 + dsto;
    var j: u16 = undefined;

    for (0..6) |_| {
        d[xy_p2(2, 1)] = src[0];
        d[xy_p2(1, 1)] = src[0];
        d[xy_p2(2, 0)] = src[0];
        d[xy_p2(1, 0)] = src[0];
        j = src[1];
        d[xy_p2(1, 2)] = j;
        d[xy_p2(2, 2)] = j | 0x4000;
        d += xy_p2(2, 0);
    }
    d -= xy_p2(2, 0) * 6;

    for (0..3) |_| {
        j = src[2];
        d[xy_p2(12, 3)] = j;
        d[xy_p2(10, 3)] = j;
        d[xy_p2(2, 3)] = j;
        d[xy_p2(0, 3)] = j;
        d[xy_p2(13, 3)] = j | 0x4000;
        d[xy_p2(11, 3)] = j | 0x4000;
        d[xy_p2(3, 3)] = j | 0x4000;
        d[xy_p2(1, 3)] = j | 0x4000;
        j = src[5];
        d[xy_p2(8, 3)] = j;
        d[xy_p2(6, 3)] = j;
        d[xy_p2(4, 3)] = j;
        d[xy_p2(9, 3)] = j | 0x4000;
        d[xy_p2(7, 3)] = j | 0x4000;
        d[xy_p2(5, 3)] = j | 0x4000;
        src += 1;
        d += xy_p2(0, 1);
    }
    d -= xy_p2(0, 1) * 3;

    j = src[5];
    d[xy_p2(0, 1)] = j;
    d[xy_p2(0, 0)] = j;
    d[xy_p2(13, 1)] = j | 0x4000;
    d[xy_p2(13, 0)] = j | 0x4000;
    j = src[6];
    d[xy_p2(0, 2)] = j;
    d[xy_p2(13, 2)] = j | 0x4000;

    src = src_org;
    for (0..4) |_| {
        j = src[10];
        d[xy_p2(3, 10)] = j;
        d[xy_p2(10, 10)] = j ^ 0x4000;
        j = src[14];
        d[xy_p2(4, 10)] = j;
        d[xy_p2(9, 10)] = j ^ 0x4000;
        j = src[18];
        d[xy_p2(5, 10)] = j;
        d[xy_p2(8, 10)] = j ^ 0x4000;
        j = src[22];
        d[xy_p2(6, 10)] = j;
        d[xy_p2(7, 10)] = j ^ 0x4000;
        src += 1;
        d += xy_p2(0, 1);
    }
}

pub export fn RoomDraw_Door_North(type_: c_int, pos_enum: c_int) callconv(.c) void { // 81a81c
    const dsto: u16 = t.kDoorPositionToTilemapOffs_Up[index(pos_enum)] / 2;
    if (type_ == c.kDoorType_LgExplosion) {
        RoomDraw_Door_ExplodingWall(pos_enum);
    } else if (type_ == c.kDoorType_PlayerBgChange) {
        RoomDraw_MarkLayerToggleDoor(dsto -% 0xfe / 2);
    } else if (type_ == c.kDoorType_Slashable) {
        RoomDraw_NorthCurtainDoor(dsto);
    } else if (type_ == c.kDoorType_EntranceDoor) {
        c.Door_Up_EntranceDoor(dsto);
    } else if (type_ == c.kDoorType_ThroneRoom) {
        RoomDraw_MarkDungeonToggleDoor(dsto -% 0xfe / 2);
    } else if (type_ == c.kDoorType_Regular2) {
        c.RoomDraw_MakeDoorPartsHighPriority_Y(dsto & (0xF07F / 2));
        RoomDraw_NormalRangedDoors_North(u8w(type_), dsto, pos_enum);
    } else if (type_ == c.kDoorType_ExitToOw) {
        v.dung_exit_door_addresses[index(v.dung_exit_door_count.* >> 1)] = dsto *% 2;
        v.dung_exit_door_count.* +%= 2;
    } else if (type_ == c.kDoorType_WaterfallTunnel) {
        RoomDraw_NormalRangedDoors_North(u8w(type_), dsto, pos_enum);
        Door_PrioritizeCurDoor();
    } else if (type_ >= c.kDoorType_StairMaskLocked0 and type_ <= c.kDoorType_StairMaskLocked3) {
        Door_Up_StairMaskLocked(u8w(type_), dsto);
    } else if (type_ >= c.kDoorType_RegularDoor33) {
        RoomDraw_HighRangeDoor_North(u8w(type_), dsto, pos_enum);
    } else {
        RoomDraw_NormalRangedDoors_North(u8w(type_), dsto, pos_enum);
    }
}

pub export fn Door_Up_StairMaskLocked(door_type: u8, dsto_: u16) callconv(.c) void { // 81a892
    var dsto = dsto_;
    const i: c_int = ci(v.dung_cur_door_idx.* >> 1);
    v.dung_door_direction[index(i)] = 0;
    v.dung_door_tilemap_address[index(i)] = dsto *% 2;
    v.door_type_and_slot[index(i)] = u16w(i << 8 | ci(door_type));
    if (v.dung_door_opened_incl_adjacent.* & c.kUpperBitmasks[index(i & 7)] != 0) {
        v.dung_cur_door_idx.* +%= 2;
        return;
    }

    if (ci(door_type) < c.kDoorType_StairMaskLocked2) {
        RoomDraw_OneSidedShutters_North(door_type, dsto);
        return;
    }

    const tp: u8 = u8w(RoomDraw_FlagDoorsAndGetFinalType(0, door_type, dsto));
    var src: Tiles = SrcPtr(t.kDoorTypeSrcData[index(tp >> 1)]);
    for (0..4) |_| {
        v.dung_bg1[dsto + xy_p2(0, 0)] = src[0];
        v.dung_bg1[dsto + xy_p2(0, 1)] = src[1];
        v.dung_bg1[dsto + xy_p2(0, 2)] = src[2];
        dsto +%= 1;
        src += 3;
    }
    Door_PrioritizeCurDoor();
}

pub export fn Door_PrioritizeCurDoor() callconv(.c) void { // 81a8fa
    v.dung_door_tilemap_address[index(ci(v.dung_cur_door_idx.* >> 1) - 1)] |= 0x2000;
}

pub export fn RoomDraw_NormalRangedDoors_North(door_type: u8, dsto: u16, pos_enum: c_int) callconv(.c) void { // 81a90f
    if (pos_enum >= 6) {
        const bak = v.dung_cur_door_idx.*;
        v.dung_cur_door_idx.* |= 0x10;
        RoomDraw_CheckIfLowerLayerDoors_Y(door_type, t.kDoorPositionToTilemapOffs_Down[index(pos_enum - 6)] / 2);
        v.dung_cur_door_idx.* = bak;
    }
    RoomDraw_OneSidedShutters_North(door_type, dsto);
}

pub export fn RoomDraw_OneSidedShutters_North(door_type: u8, dsto: u16) callconv(.c) void { // 81a932
    var tp: c_int = RoomDraw_FlagDoorsAndGetFinalType(0, door_type, dsto);
    if (tp & 0x100 != 0)
        return;
    // Remap type
    if (tp == 54 or tp == 56) {
        const new_type: c_int = if (tp == 54) c.kDoorType_ShuttersTwoWay else c.kDoorType_Regular;
        const i: c_int = ci(v.dung_cur_door_idx.* >> 1) - 1;
        v.door_type_and_slot[index(i)] = u16w((i << 8) | new_type);
        tp = new_type;
    }
    var src: Tiles = SrcPtr(t.kDoorTypeSrcData[index(tp >> 1)]);
    var dst: Words = DstoPtr(dsto);
    for (0..4) |_| {
        dst[xy_p2(0, 0)] = src[0];
        dst[xy_p2(0, 1)] = src[1];
        dst[xy_p2(0, 2)] = src[2];
        dst += 1;
        src += 3;
    }
}

pub export fn RoomDraw_Door_South(type_: c_int, pos_enum: c_int) callconv(.c) void { // 81a984
    var dsto: u16 = t.kDoorPositionToTilemapOffs_Down[index(pos_enum)] / 2;
    if (type_ == c.kDoorType_PlayerBgChange) {
        RoomDraw_MarkLayerToggleDoor(dsto +% xy_p2(1, 4));
    } else if (type_ == c.kDoorType_EntranceDoor) {
        c.Door_Down_EntranceDoor(dsto);
    } else if (type_ == c.kDoorType_ThroneRoom) {
        RoomDraw_MarkDungeonToggleDoor(dsto +% xy_p2(1, 4));
    } else if (type_ == c.kDoorType_ExitToOw) {
        v.dung_exit_door_addresses[index(v.dung_exit_door_count.* >> 1)] = dsto *% 2;
        v.dung_exit_door_count.* +%= 2;
    } else if (type_ >= c.kDoorType_RegularDoor33) {
        RoomDraw_OneSidedLowerShutters_South(u8w(type_), dsto);
    } else if (type_ == c.kDoorType_EntranceLarge) {
        _ = RoomDraw_FlagDoorsAndGetFinalType(1, u8w(type_), dsto);
        RoomDraw_SomeBigDecors(10, SrcPtr(0x2656), dsto -% 259);
    } else if (type_ == c.kDoorType_EntranceLarge2) {
        dsto |= 0x1000;
        _ = RoomDraw_FlagDoorsAndGetFinalType(1, u8w(type_), dsto);
        dsto -%= 259;
        RoomDraw_SomeBigDecors(10, SrcPtr(0x2656), dsto);
        dsto -%= 3648;
        for (0..10) |_| {
            v.dung_bg2[dsto] = v.dung_bg1[dsto] | 0x2000;
            dsto +%= 1;
        }
    } else if (type_ == c.kDoorType_EntranceCave or type_ == c.kDoorType_EntranceCave2) {
        if (type_ == c.kDoorType_EntranceCave2)
            c.RoomDraw_MakeDoorPartsHighPriority_Y(dsto +% xy_p2(0, 4));
        _ = RoomDraw_FlagDoorsAndGetFinalType(1, u8w(type_), dsto);
        RoomDraw_4x4(SrcPtr(0x26f6), DstoPtr(dsto));
    } else if (type_ == c.kDoorType_4) {
        var dsto_org = dsto;
        dsto |= 0x1000;
        c.RoomDraw_MakeDoorPartsHighPriority_Y(dsto +% xy_p2(0, 4));
        _ = RoomDraw_FlagDoorsAndGetFinalType(1, u8w(type_), dsto);
        RoomDraw_4x4(SrcPtr(0x26f6), DstoPtr(dsto));
        for (0..4) |_| {
            v.dung_bg2[dsto_org + xy_p2(0, 3)] = v.dung_bg1[dsto_org + xy_p2(0, 3)] | 0x2000;
            dsto_org +%= 1;
        }
    } else {
        RoomDraw_CheckIfLowerLayerDoors_Y(u8w(type_), dsto);
    }
}

pub export fn RoomDraw_CheckIfLowerLayerDoors_Y(door_type: u8, dsto: u16) callconv(.c) void { // 81aa66
    if (ci(door_type) == c.kDoorType_Regular2) {
        c.RoomDraw_MakeDoorPartsHighPriority_Y(dsto +% xy_p2(0, 4));
        c.Door_Draw_Helper4(door_type, dsto);
    } else if (ci(door_type) == c.kDoorType_WaterfallTunnel) {
        c.Door_Draw_Helper4(door_type, dsto);
        Door_PrioritizeCurDoor();
    } else {
        c.Door_Draw_Helper4(door_type, dsto);
    }
}

pub export fn RoomDraw_Door_West(type_: c_int, pos_enum: c_int) callconv(.c) void { // 81aad7
    const dsto: u16 = t.kDoorPositionToTilemapOffs_Left[index(pos_enum)] / 2;
    if (type_ == c.kDoorType_PlayerBgChange) {
        RoomDraw_MarkLayerToggleDoor(dsto +% 62);
    } else if (type_ == c.kDoorType_EntranceDoor) {
        c.Door_Left_EntranceDoor(dsto);
    } else if (type_ == c.kDoorType_ThroneRoom) {
        RoomDraw_MarkDungeonToggleDoor(dsto +% 62);
    } else if (type_ == c.kDoorType_Regular2) {
        c.RoomDraw_MakeDoorPartsHighPriority_X(dsto & 0xffe0);
        RoomDraw_NormalRangedDoors_West(u8w(type_), dsto, pos_enum);
    } else if (type_ == c.kDoorType_WaterfallTunnel) {
        RoomDraw_NormalRangedDoors_West(u8w(type_), dsto, pos_enum);
        Door_PrioritizeCurDoor();
    } else if (type_ < c.kDoorType_RegularDoor33) {
        RoomDraw_NormalRangedDoors_West(u8w(type_), dsto, pos_enum);
    } else {
        RoomDraw_HighRangeDoor_West(u8w(type_), dsto, pos_enum);
    }
}

pub export fn RoomDraw_NormalRangedDoors_West(door_type: u8, dsto: u16, pos_enum: c_int) callconv(.c) void { // 81ab1f
    if (pos_enum >= 6) {
        const bak = v.dung_cur_door_idx.*;
        v.dung_cur_door_idx.* |= 0x10;
        RoomDraw_NormalRangedDoors_East(door_type, t.kDoorPositionToTilemapOffs_Right[index(pos_enum - 6)] / 2);
        v.dung_cur_door_idx.* = bak;
    }

    var tp: c_int = RoomDraw_FlagDoorsAndGetFinalType(2, door_type, dsto);
    var new_type: c_int = undefined;
    if (tp & 0x100 != 0)
        return;

    new_type = c.kDoorType_ShuttersTwoWay;
    var matched = (tp == c.kDoorType_36);
    if (!matched) {
        new_type = c.kDoorType_Regular;
        matched = (tp == c.kDoorType_38);
    }
    if (matched) {
        const i: c_int = ci(v.dung_cur_door_idx.* >> 1) - 1;
        v.door_type_and_slot[index(i)] = u16w((i << 8) | new_type);
        tp = new_type;
    }

    var src: Tiles = SrcPtr(t.kDoorTypeSrcData3[index(tp >> 1)]);
    var dst: Words = DstoPtr(dsto);
    for (0..3) |_| {
        dst[xy_p2(0, 0)] = src[0];
        dst[xy_p2(0, 1)] = src[1];
        dst[xy_p2(0, 2)] = src[2];
        dst[xy_p2(0, 3)] = src[3];
        dst += 1;
        src += 4;
    }
}

pub export fn RoomDraw_Door_East(type_: c_int, pos_enum: c_int) callconv(.c) void { // 81ab99
    const dsto: u16 = t.kDoorPositionToTilemapOffs_Right[index(pos_enum)] / 2;
    if (type_ == c.kDoorType_PlayerBgChange) {
        RoomDraw_MarkLayerToggleDoor(dsto +% 68);
    } else if (type_ == c.kDoorType_EntranceDoor) {
        c.Door_Right_EntranceDoor(dsto);
    } else if (type_ == c.kDoorType_ThroneRoom) {
        RoomDraw_MarkDungeonToggleDoor(dsto +% 68);
    } else if (type_ < c.kDoorType_RegularDoor33) {
        RoomDraw_NormalRangedDoors_East(u8w(type_), dsto);
    } else {
        RoomDraw_OneSidedLowerShutters_East(u8w(type_), dsto);
    }
}

pub export fn RoomDraw_NormalRangedDoors_East(door_type: u8, dsto: u16) callconv(.c) void { // 81abc8
    if (ci(door_type) == c.kDoorType_Regular2)
        c.RoomDraw_MakeDoorPartsHighPriority_X(dsto +% xy_p2(4, 0));
    if (ci(door_type) == c.kDoorType_WaterfallTunnel) {
        RoomDraw_OneSidedShutters_East(door_type, dsto);
        Door_PrioritizeCurDoor();
    } else {
        RoomDraw_OneSidedShutters_East(door_type, dsto);
    }
}

pub export fn RoomDraw_OneSidedShutters_East(door_type: u8, dsto: u16) callconv(.c) void { // 81abe2
    var tp: c_int = RoomDraw_FlagDoorsAndGetFinalType(3, door_type, dsto);
    var new_type: c_int = undefined;
    if (tp & 0x100 != 0)
        return;
    new_type = c.kDoorType_Regular;
    var matched = (tp == c.kDoorType_36);
    if (!matched) {
        new_type = c.kDoorType_ShuttersTwoWay;
        matched = (tp == c.kDoorType_38);
    }
    if (matched) {
        const i: c_int = ci(v.dung_cur_door_idx.* >> 1) - 1;
        v.door_type_and_slot[index(i)] = u16w((i << 8) | new_type);
        tp = new_type;
    }
    var src: Tiles = SrcPtr(t.kDoorTypeSrcData4[index(tp >> 1)]);
    var dst: Words = DstoPtr(dsto) + 1;
    for (0..3) |_| {
        dst[xy_p2(0, 0)] = src[0];
        dst[xy_p2(0, 1)] = src[1];
        dst[xy_p2(0, 2)] = src[2];
        dst[xy_p2(0, 3)] = src[3];
        dst += 1;
        src += 4;
    }
}

pub export fn RoomDraw_NorthCurtainDoor(dsto: u16) callconv(.c) void { // 81ac3b
    const rv: c_int = RoomDraw_FlagDoorsAndGetFinalType(0, c.kDoorType_Slashable, dsto);
    if (rv & 0x100 != 0) {
        RoomDraw_4x4(SrcPtr(0x78a), DstoPtr(dsto));
    } else {
        RoomDraw_4x4(SrcPtr(t.kDoorTypeSrcData[index(rv >> 1)]), DstoPtr(dsto));
    }
}

pub export fn RoomDraw_Door_ExplodingWall(pos_enum: c_int) callconv(.c) void { // 81ac70
    const dsto: u16 = t.kDoor_BlastWallUp_Dsts[index(pos_enum)] / 2;
    const i: c_int = ci(v.dung_cur_door_idx.* >> 1);
    v.dung_door_tilemap_address[index(i)] = (dsto +% 10) *% 2;
    v.door_type_and_slot[index(i)] = u16w(i << 8 | c.kDoorType_LgExplosion);
    if (v.dung_door_opened_incl_adjacent.* & c.kUpperBitmasks[index(i & 7)] == 0) {
        v.dung_door_direction[index(i)] = 0;
        v.dung_cur_door_idx.* +%= 2;
        return;
    }
    const slot: usize = @intFromBool(v.dung_hdr_tag[0] != 0x20 and v.dung_hdr_tag[0] != 0x25 and v.dung_hdr_tag[0] != 0x28);
    v.dung_hdr_tag[slot] = 0;
    v.quadrant_fullsize_y.* = 2;
    v.dung_blastwall_flag_y.* = 1;
    RoomDraw_ExplodingWallSegment(SrcPtr(t.kDoorTypeSrcData2[42]), dsto);
    v.dung_cur_door_idx.* +%= 2;
    v.dung_unk2.* |= 0x200;
    RoomDraw_ExplodingWallSegment(SrcPtr(t.kDoorTypeSrcData[42]), dsto +% xy_p2(0, 6));
}

pub export fn RoomDraw_ExplodingWallSegment(src_: Tiles, dsto_: u16) callconv(.c) void { // 81ace4
    var src = src_;
    var dsto = dsto_;
    RoomDraw_ExplodingWallColumn(src, DstoPtr(dsto));
    src += 12;
    dsto +%= 2;
    const n: u16 = src[0];
    var d: Words = v.dung_bg2 + dsto;
    v.dung_draw_width_indicator.* = 18;
    while (true) {
        d[xy_p2(0, 2)] = n;
        d[xy_p2(0, 1)] = n;
        d[xy_p2(0, 0)] = n;
        d[xy_p2(0, 5)] = n;
        d[xy_p2(0, 4)] = n;
        d[xy_p2(0, 3)] = n;
        d += 1;
        v.dung_draw_width_indicator.* -%= 1;
        if (v.dung_draw_width_indicator.* == 0)
            break;
    }
    RoomDraw_ExplodingWallColumn(src + 1, DstoPtr(dsto +% 18));
}

pub export fn RoomDraw_ExplodingWallColumn(src_: Tiles, dst_: Words) callconv(.c) void { // 81ad25
    var src = src_;
    var dst = dst_;
    for (0..6) |_| {
        dst[0] = src[0];
        dst[1] = src[6];
        dst += xy_p2(0, 1);
        src += 1;
    }
}

pub export fn RoomDraw_HighRangeDoor_North(door_type: u8, dsto_: u16, pos_enum: c_int) callconv(.c) void { // 81ad41
    var dsto = dsto_;
    if (pos_enum >= 6 and ci(door_type) != c.kDoorType_WarpRoomDoor) {
        const bak = v.dung_cur_door_idx.*;
        v.dung_cur_door_idx.* |= 0x10;
        RoomDraw_OneSidedLowerShutters_South(door_type, t.kDoorPositionToTilemapOffs_Down[index(pos_enum - 6)] / 2);
        v.dung_cur_door_idx.* = bak;
    }
    var tp: u8 = u8w(RoomDraw_FlagDoorsAndGetFinalType(0, door_type, dsto));
    if (ci(tp) == c.kDoorType_ShutterTrapUR or ci(tp) == c.kDoorType_ShutterTrapDL) {
        const new_type: c_int = if (ci(tp) == c.kDoorType_ShutterTrapUR) c.kDoorType_RegularDoor33 else c.kDoorType_Shutter;
        const i: c_int = ci(v.dung_cur_door_idx.* >> 1) - 1;
        v.door_type_and_slot[index(i)] = u16w((i << 8) | new_type);
        tp = u8w(new_type);
    }
    const dsto_org = dsto;
    var src: Tiles = SrcPtr(t.kDoorTypeSrcData[index(tp >> 1)]);
    for (0..4) |_| {
        v.dung_bg2[dsto + xy_p2(0, 0)] = src[0];
        v.dung_bg1[dsto + xy_p2(0, 1)] = src[1];
        v.dung_bg1[dsto + xy_p2(0, 2)] = src[2];
        dsto +%= 1;
        src += 3;
    }
    if (ci(door_type) != c.kDoorType_WarpRoomDoor)
        RoomDraw_MakeDoorHighPriority_North(dsto_org);
    Door_PrioritizeCurDoor();
}

pub export fn RoomDraw_OneSidedLowerShutters_South(door_type: u8, dsto_: u16) callconv(.c) void { // 81add4
    var dsto = dsto_;
    var tp: u8 = u8w(RoomDraw_FlagDoorsAndGetFinalType(1, door_type, dsto));
    if (ci(tp) == c.kDoorType_ShutterTrapUR or ci(tp) == c.kDoorType_ShutterTrapDL) {
        const new_type: c_int = if (ci(tp) == c.kDoorType_ShutterTrapUR) c.kDoorType_Shutter else c.kDoorType_RegularDoor33;
        const i: c_int = ci(v.dung_cur_door_idx.* >> 1) - 1;
        v.door_type_and_slot[index(i)] = u16w((i << 8) | new_type);
        tp = u8w(new_type);
    }
    const dsto_org = dsto;
    var src: Tiles = SrcPtr(t.kDoorTypeSrcData2[index(tp >> 1)]);
    for (0..4) |_| {
        v.dung_bg1[dsto + xy_p2(0, 1)] = src[0];
        v.dung_bg1[dsto + xy_p2(0, 2)] = src[1];
        v.dung_bg2[dsto + xy_p2(0, 3)] = src[2];
        dsto +%= 1;
        src += 3;
    }
    RoomDraw_MakeDoorHighPriority_South(dsto_org +% xy_p2(0, 4));
    Door_PrioritizeCurDoor();
}

pub export fn RoomDraw_HighRangeDoor_West(door_type: u8, dsto_: u16, pos_enum: c_int) callconv(.c) void { // 81ae40
    var dsto = dsto_;
    if (pos_enum >= 6) {
        const bak = v.dung_cur_door_idx.*;
        v.dung_cur_door_idx.* |= 0x10;
        RoomDraw_OneSidedLowerShutters_East(door_type, t.kDoorPositionToTilemapOffs_Right[index(pos_enum - 6)] / 2);
        v.dung_cur_door_idx.* = bak;
    }

    var tp: u8 = u8w(RoomDraw_FlagDoorsAndGetFinalType(2, door_type, dsto));
    var new_type: c_int = undefined;
    new_type = c.kDoorType_Shutter;
    var matched = (ci(tp) == c.kDoorType_ShutterTrapUR);
    if (!matched) {
        new_type = c.kDoorType_RegularDoor33;
        matched = (ci(tp) == c.kDoorType_ShutterTrapDL);
    }
    if (matched) {
        const i: c_int = ci(v.dung_cur_door_idx.* >> 1) - 1;
        v.door_type_and_slot[index(i)] = u16w((i << 8) | new_type);
        tp = u8w(new_type);
    }

    var src: Tiles = SrcPtr(t.kDoorTypeSrcData3[index(tp >> 1)]);
    const dsto_org = dsto;
    v.dung_bg2[dsto + xy_p2(0, 0)] = src[0];
    v.dung_bg2[dsto + xy_p2(0, 1)] = src[1];
    v.dung_bg2[dsto + xy_p2(0, 2)] = src[2];
    v.dung_bg2[dsto + xy_p2(0, 3)] = src[3];
    dsto +%= 1;
    src += 4;
    for (0..2) |_| {
        v.dung_bg1[dsto + xy_p2(0, 0)] = src[0];
        v.dung_bg1[dsto + xy_p2(0, 1)] = src[1];
        v.dung_bg1[dsto + xy_p2(0, 2)] = src[2];
        v.dung_bg1[dsto + xy_p2(0, 3)] = src[3];
        dsto +%= 1;
        src += 4;
    }
    RoomDraw_MakeDoorHighPriority_West(dsto_org);
    Door_PrioritizeCurDoor();
}

pub export fn RoomDraw_OneSidedLowerShutters_East(door_type: u8, dsto_: u16) callconv(.c) void { // 81aef0
    var dsto = dsto_;
    var tp: u8 = u8w(RoomDraw_FlagDoorsAndGetFinalType(3, door_type, dsto));
    var new_type: c_int = undefined;
    new_type = c.kDoorType_RegularDoor33;
    var matched = (ci(tp) == c.kDoorType_ShutterTrapUR);
    if (!matched) {
        new_type = c.kDoorType_Shutter;
        matched = (ci(tp) == c.kDoorType_ShutterTrapDL);
    }
    if (matched) {
        const i: c_int = ci(v.dung_cur_door_idx.* >> 1) - 1;
        v.door_type_and_slot[index(i)] = u16w((i << 8) | new_type);
        tp = u8w(new_type);
    }

    const dst_org = dsto;
    var src: Tiles = SrcPtr(t.kDoorTypeSrcData4[index(tp >> 1)]);
    for (0..2) |_| {
        v.dung_bg1[dsto + xy_p2(1, 0)] = src[0];
        v.dung_bg1[dsto + xy_p2(1, 1)] = src[1];
        v.dung_bg1[dsto + xy_p2(1, 2)] = src[2];
        v.dung_bg1[dsto + xy_p2(1, 3)] = src[3];
        dsto +%= 1;
        src += 4;
    }
    v.dung_bg2[dsto + xy_p2(1, 0)] = src[0];
    v.dung_bg2[dsto + xy_p2(1, 1)] = src[1];
    v.dung_bg2[dsto + xy_p2(1, 2)] = src[2];
    v.dung_bg2[dsto + xy_p2(1, 3)] = src[3];
    RoomDraw_MakeDoorHighPriority_East(dst_org +% xy_p2(4, 0));
    Door_PrioritizeCurDoor();
}

pub export fn RoomDraw_MakeDoorHighPriority_North(dsto_: u16) callconv(.c) void { // 81af8b
    const dsto_org = dsto_;
    var dsto = dsto_ & (0xF07F >> 1);
    while (true) {
        v.dung_bg2[dsto + 0] |= 0x2000;
        v.dung_bg2[dsto + 1] |= 0x2000;
        v.dung_bg2[dsto + 2] |= 0x2000;
        v.dung_bg2[dsto + 3] |= 0x2000;
        dsto +%= xy_p2(0, 1);
        if (dsto == dsto_org)
            break;
    }
}

pub export fn RoomDraw_MakeDoorHighPriority_South(dsto_: u16) callconv(.c) void { // 81afd4
    var dsto = dsto_;
    while (true) {
        v.dung_bg2[dsto + 0] |= 0x2000;
        v.dung_bg2[dsto + 1] |= 0x2000;
        v.dung_bg2[dsto + 2] |= 0x2000;
        v.dung_bg2[dsto + 3] |= 0x2000;
        dsto +%= xy_p2(0, 1);
        if (dsto & 0x7c0 == 0)
            break;
    }
}

pub export fn RoomDraw_MakeDoorHighPriority_West(dsto_: u16) callconv(.c) void { // 81b017
    const dsto_org = dsto_;
    var dsto = dsto_ & 0xffe0;
    while (true) {
        v.dung_bg2[dsto + xy_p2(0, 0)] |= 0x2000;
        v.dung_bg2[dsto + xy_p2(0, 1)] |= 0x2000;
        v.dung_bg2[dsto + xy_p2(0, 2)] |= 0x2000;
        v.dung_bg2[dsto + xy_p2(0, 3)] |= 0x2000;
        dsto +%= xy_p2(1, 0);
        if (dsto == dsto_org)
            break;
    }
}

pub export fn RoomDraw_MakeDoorHighPriority_East(dsto_: u16) callconv(.c) void { // 81b05c
    var dsto = dsto_;
    var d: Words = v.dung_bg2 + dsto;
    while (true) {
        d[xy_p2(0, 0)] |= 0x2000;
        d[xy_p2(0, 1)] |= 0x2000;
        d[xy_p2(0, 2)] |= 0x2000;
        d[xy_p2(0, 3)] |= 0x2000;
        d += xy_p2(1, 0);
        dsto +%= 1;
        if (dsto & 0x1f == 0)
            break;
    }
}

pub export fn RoomDraw_MarkDungeonToggleDoor(dsto: u16) callconv(.c) void { // 81b092
    v.dung_toggle_palace_pos[index(v.dung_num_toggle_palace.* >> 1)] = dsto;
    v.dung_num_toggle_palace.* +%= 2;
}

pub export fn RoomDraw_MarkLayerToggleDoor(dsto: u16) callconv(.c) void { // 81b09f
    v.dung_toggle_floor_pos[index(v.dung_num_toggle_floor.* >> 1)] = dsto;
    v.dung_num_toggle_floor.* +%= 2;
}

// returns 0x100 on inverse carry
pub export fn RoomDraw_FlagDoorsAndGetFinalType(direction: u8, door_type: u8, dsto: u16) callconv(.c) c_int { // 81b0da
    const slot: c_int = ci(v.dung_cur_door_idx.* >> 1);
    v.dung_door_direction[index(slot)] = direction;
    v.dung_door_tilemap_address[index(slot)] = dsto *% 2;
    v.door_type_and_slot[index(slot)] = u16w(slot << 8 | ci(door_type));

    var door_type_remapped: u8 = door_type;

    dont_mark_opened: {
        if ((slot & 7) < 4 and (v.dung_door_opened_incl_adjacent.* & c.kUpperBitmasks[index(slot & 7)]) != 0) {
            if ((ci(door_type) == c.kDoorType_ShuttersTwoWay or ci(door_type) == c.kDoorType_Shutter) and v.dung_flag_trapdoors_down.* != 0)
                break :dont_mark_opened;
            door_type_remapped = t.kDoorTypeRemap[index(door_type >> 1)];

            if (ci(door_type) != c.kDoorType_ShuttersTwoWay and ci(door_type) != c.kDoorType_Shutter and
                ci(door_type) >= c.kDoorType_InvisibleDoor and ci(door_type) != c.kDoorType_RegularDoor33 and ci(door_type) != c.kDoorType_WarpRoomDoor)
                v.dung_door_opened.* |= c.kUpperBitmasks[index(slot)];
        }
    }
    v.dung_cur_door_idx.* = u16w(slot * 2 + 2);

    if (ci(door_type_remapped) == c.kDoorType_Slashable or ci(door_type_remapped) == c.kDoorType_WaterfallTunnel)
        return 0x100 | ci(door_type_remapped);

    if (ci(door_type) != c.kDoorType_InvisibleDoor)
        return ci(door_type_remapped);

    v.invisible_door_dir_and_index_x2.* = u16w((slot << 8 | ci(direction)) * 2);
    //  if (direction * 2 == link_direction_facing || ((direction * 2) ^ 2) == link_direction_facing)
    //    return door_type_remapped;
    v.dung_door_opened_incl_adjacent.* |= c.kUpperBitmasks[index(slot)];
    return c.kDoorType_Regular;
}

// ---------------------------------------------------------------------------
// from dungeon_part3.zig
// ---------------------------------------------------------------------------
// dungeon.c: #define adjacent_doors_flags (*(uint16*)(g_ram+0x1100))
// dungeon.c: #define adjacent_doors ((uint16*)(g_ram+0x1110))

/// WORD(dung_bg2_attr_table[i]) - unaligned 16-bit view into the attribute table.

pub export fn Dungeon_LoadHeader() callconv(.c) void { // 81b564
    v.dung_flag_statechange_waterpuzzle.* = 0;
    v.dung_flag_somaria_block_switch.* = 0;
    v.dung_flag_movable_block_was_pushed.* = 0;

    const kAdjustment = [_]i16{ 256, -256 };

    if (v.submodule_index.* == 0) {
        v.dung_loade_bgoffs_h_copy.* = v.BG2HOFS_copy2.* & ~@as(u16, 0x1FF);
        v.dung_loade_bgoffs_v_copy.* = v.BG2VOFS_copy2.* & ~@as(u16, 0x1FF);
    } else if (v.submodule_index.* == 21 or v.submodule_index.* < 18 and v.submodule_index.* >= 6) {
        v.dung_loade_bgoffs_h_copy.* = (v.BG2HOFS_copy2.* +% 0x20) & ~@as(u16, 0x1FF);
        v.dung_loade_bgoffs_v_copy.* = (v.BG2VOFS_copy2.* +% 0x20) & ~@as(u16, 0x1FF);
    } else {
        if (((v.link_direction.* & 0xf) >> 1) < 2) {
            v.dung_loade_bgoffs_h_copy.* = (v.BG2HOFS_copy2.* +% @as(u16, @bitCast(kAdjustment[(v.link_direction.* & 0xf) >> 1]))) & ~@as(u16, 0x1FF);
            v.dung_loade_bgoffs_v_copy.* = (v.BG2VOFS_copy2.* +% 0x20) & ~@as(u16, 0x1FF);
        } else {
            v.dung_loade_bgoffs_h_copy.* = (v.BG2HOFS_copy2.* +% 0x20) & ~@as(u16, 0x1FF);
            v.dung_loade_bgoffs_v_copy.* = (v.BG2VOFS_copy2.* +% @as(u16, @bitCast(kAdjustment[(v.link_direction.* & 0xf) >> 3]))) & ~@as(u16, 0x1FF);
        }
    }

    const hdr_ptr = GetRoomHeaderPtr(@intCast(v.dungeon_room_index.*));

    v.dung_bg2_properties_backup.* = v.dung_hdr_bg2_properties.*;
    v.dung_hdr_bg2_properties.* = hdr_ptr[0] >> 5;
    v.dung_hdr_collision.* = (hdr_ptr[0] >> 2) & 7;
    v.dung_want_lights_out_copy.* = v.dung_want_lights_out.*;
    v.dung_want_lights_out.* = hdr_ptr[0] & 1;
    const dpi = &t.kDungPalinfos[hdr_ptr[1]];
    v.palette_main_indoors.* = dpi.pal0;
    v.palette_sp0l.* = dpi.pal1;
    v.palette_sp5l.* = dpi.pal2;
    v.palette_sp6l.* = dpi.pal3;
    v.aux_tile_theme_index.* = hdr_ptr[2];
    v.sprite_graphics_index.* = hdr_ptr[3] +% 0x40;
    v.dung_hdr_collision_2.* = hdr_ptr[4];
    v.dung_hdr_tag[0] = hdr_ptr[5];
    v.dung_hdr_tag[1] = hdr_ptr[6];
    v.dung_hdr_hole_teleporter_plane.* = hdr_ptr[7] & 3;
    v.dung_hdr_staircase_plane[0] = (hdr_ptr[7] >> 2) & 3;
    v.dung_hdr_staircase_plane[1] = (hdr_ptr[7] >> 4) & 3;
    v.dung_hdr_staircase_plane[2] = (hdr_ptr[7] >> 6) & 3;
    v.dung_hdr_staircase_plane[3] = hdr_ptr[8] & 3;
    v.dung_hdr_travel_destinations[0] = hdr_ptr[9];
    v.dung_hdr_travel_destinations[1] = hdr_ptr[10];
    v.dung_hdr_travel_destinations[2] = hdr_ptr[11];
    v.dung_hdr_travel_destinations[3] = hdr_ptr[12];
    v.dung_hdr_travel_destinations[4] = hdr_ptr[13];
    v.dung_flag_trapdoors_down.* = 1;
    v.dung_overlay_to_load.* = 0;
    v.dung_index_x3.* = v.dungeon_room_index.* *% 3;

    const x = v.save_dung_info[index(v.dungeon_room_index.*)];
    v.dung_door_opened.* = x & 0xf000;
    v.dung_door_opened_incl_adjacent.* = v.dung_door_opened.* | 0xf00;
    v.dung_savegame_state_bits.* = (x & 0xff0) << 4;
    v.dung_quadrants_visited.* = x & 0xf;

    const dp = GetRoomDoorInfo(@intCast(v.dungeon_room_index.*));
    var i: usize = 0;
    while (dp[i] != 0xffff) : (i += 1)
        v.dung_door_tilemap_address[i] = dp[i];
    v.dung_door_tilemap_address[i] = 0;

    const room: c_int = @intCast(v.dungeon_room_index.*);
    if (((room - 1) & 0xf) != 0xf)
        Dungeon_CheckAdjacentRoomsForOpenDoors(18, room - 1);
    if (((room + 1) & 0xf) != 0)
        Dungeon_CheckAdjacentRoomsForOpenDoors(12, room + 1);
    if (room - 16 >= 0)
        Dungeon_CheckAdjacentRoomsForOpenDoors(6, room - 16);
    if (room + 16 < 0x140)
        Dungeon_CheckAdjacentRoomsForOpenDoors(0, room + 16);
}

pub export fn Dungeon_CheckAdjacentRoomsForOpenDoors(idx: c_int, room: c_int) callconv(.c) void { // 81b759
    const kLookup = [_]u16{
        0x00, 0x10, 0x20, 0x30, 0x40, 0x50,
        0x61, 0x71, 0x81, 0x91, 0xa1, 0xb1,
        0x02, 0x12, 0x22, 0x32, 0x42, 0x52,
        0x63, 0x73, 0x83, 0x93, 0xa3, 0xb3,
    };
    const kLookup2 = [_]u16{
        0x61, 0x71, 0x81, 0x91, 0xa1, 0xb1,
        0x0,  0x10, 0x20, 0x30, 0x40, 0x50,
        0x63, 0x73, 0x83, 0x93, 0xa3, 0xb3,
        0x02, 0x12, 0x22, 0x32, 0x42, 0x52,
    };
    Dungeon_LoadAdjacentRoomDoors(room);
    var i: usize = 0;
    var a: u16 = undefined;
    while (i != 8) : (i += 1) {
        a = adjacent_doors[i];
        if (a == 0xffff) break;
        a &= 0xff;
        var j: c_int = idx;
        const hit = hitblk: {
            if (a == kLookup[index(j)]) break :hitblk true;
            j += 1;
            if (a == kLookup[index(j)]) break :hitblk true;
            j += 1;
            if (a == kLookup[index(j)]) break :hitblk true;
            j += 1;
            if (a == kLookup[index(j)]) break :hitblk true;
            j += 1;
            if (a == kLookup[index(j)]) break :hitblk true;
            j += 1;
            if (a == kLookup[index(j)]) break :hitblk true;
            break :hitblk false;
        };
        if (hit) {
            const rev = u8w(kLookup2[index(j)]);
            var n: usize = 0;
            while (n != 8) : (n += 1) {
                if (@as(u8, @truncate(v.dung_door_tilemap_address[n])) == rev) {
                    const k = @as(u8, @truncate(v.dung_door_tilemap_address[n] >> 8));
                    if (k == 0x30)
                        break;
                    if (k == 0x44 or k == 0x18) {
                        // trapdoor
                        if (room != @as(c_int, @intCast(v.dungeon_room_index_prev.*)))
                            break;
                        v.dung_flag_trapdoors_down.* = 0;
                    } else {
                        // not trapdoor
                        if ((adjacent_doors_flags.* & rtl.kUpperBitmasks[i]) == 0)
                            break;
                    }
                    v.dung_door_opened_incl_adjacent.* |= rtl.kUpperBitmasks[n];
                    break;
                }
            }
        }
    }
}

pub export fn Dungeon_LoadAdjacentRoomDoors(room: c_int) callconv(.c) void { // 81b7ef
    const dp = GetRoomDoorInfo(room);
    adjacent_doors_flags.* = (v.save_dung_info[index(room)] & 0xf000) | 0xf00;
    var i: usize = 0;
    while (true) : (i += 1) {
        const a = dp[i];
        adjacent_doors[i] = a;
        if (a == 0xffff)
            break;
        if ((a & 0xff00) == 0x4000 or (a & 0xff00) < 0x200)
            adjacent_doors_flags.* |= rtl.kUpperBitmasks[i];
    }
}

pub export fn Dungeon_LoadAttribute_Selectable() callconv(.c) void { // 81b8b4
    switch (v.overworld_map_state.*) {
        // case 0 falls through into case 1
        0, 1 => {
            if (v.overworld_map_state.* == 0) { // Dungeon_LoadBasicAttribute
                v.overworld_map_state.* = 1;
                v.dung_draw_height_indicator.* = 0;
                v.dung_draw_width_indicator.* = 0;
            }
            Dungeon_LoadBasicAttribute_full(0x40);
        },
        2 => Dungeon_LoadObjectAttribute(),
        3 => Dungeon_LoadDoorAttribute(),
        4 => {
            v.overworld_map_state.* = 5;
            if (v.orange_blue_barrier_state.* != 0)
                Dungeon_FlipCrystalPegAttribute();
        },
        5 => {},
        else => unreachable,
    }
}

pub export fn Dungeon_LoadAttributeTable() callconv(.c) void { // 81b8bf
    v.dung_draw_height_indicator.* = 0;
    v.dung_draw_width_indicator.* = 0;
    Dungeon_LoadBasicAttribute_full(0x1000);
    Dungeon_LoadObjectAttribute();
    Dungeon_LoadDoorAttribute();
    if (v.orange_blue_barrier_state.* != 0)
        Dungeon_FlipCrystalPegAttribute();
    v.overworld_map_state.* = 0;
}

pub export fn Dungeon_LoadBasicAttribute_full(loops_: u16) callconv(.c) void { // 81b8f3
    var loops = loops_;
    while (true) {
        const i = index(v.dung_draw_width_indicator.* / 2);
        var a0 = v.attributes_for_tile[v.dung_bg2[i] & 0x3ff];
        if (a0 >= 0x10 and a0 < 0x1c)
            a0 |= @truncate(v.dung_bg2[i] >> 14); // vflip/hflip
        var a1 = v.attributes_for_tile[v.dung_bg2[i + 1] & 0x3ff];
        if (a1 >= 0x10 and a1 < 0x1c)
            a1 |= @truncate(v.dung_bg2[i + 1] >> 14); // vflip/hflip
        const j = v.dung_draw_height_indicator.*;
        v.dung_bg2_attr_table[index(j)] = a0;
        v.dung_bg2_attr_table[index(j) + 1] = a1;
        v.dung_draw_height_indicator.* = j +% 2;
        v.dung_draw_width_indicator.* +%= 4;
        loops -%= 1;
        if (loops == 0) break;
    }
    if (v.dung_draw_height_indicator.* == 0x2000)
        v.overworld_map_state.* +%= 1;
}

pub export fn Dungeon_LoadObjectAttribute() callconv(.c) void { // 81b967
    {
        var i: c_int = 0;
        while (i != v.dung_num_star_shaped_switches.*) : (i += 2) {
            const j: c_int = @intCast(v.star_shaped_switches_tile[index(i >> 1)]);
            writeAttr2(j + xy_p3(0, 0), 0x3b3b);
            writeAttr2(j + xy_p3(0, 1), 0x3b3b);
        }
    }

    var i: c_int = 0;
    var tv: c_int = 0x3030;
    while (i != v.dung_num_inter_room_upnorth_stairs.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 2), 0);
        writeAttr2(j + xy_p3(1, 0), 0x2626);
        writeAttr2(j + xy_p3(1, 1), u16w(tv));
    }
    while (i != v.dung_num_wall_upnorth_spiral_stairs.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 0), 0x5e5e);
        writeAttr2(j + xy_p3(1, 2), 0x5e5e);
        writeAttr2(j + xy_p3(1, 3), 0x5e5e);
        writeAttr2(j + xy_p3(1, 1), u16w(tv));
    }
    while (i != v.dung_num_wall_upnorth_spiral_stairs_2.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 0), 0x5f5f);
        writeAttr2(j + xy_p3(1, 2), 0x5f5f);
        writeAttr2(j + xy_p3(1, 3), 0x5f5f);
        writeAttr2(j + xy_p3(1, 1), u16w(tv));
    }
    while (i != v.dung_num_inter_room_upnorth_straight_stairs.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 0), 0x3838);
        writeAttr2(j + xy_p3(1, 2), 0);
        writeAttr2(j + xy_p3(1, 3), 0);
        writeAttr2(j + xy_p3(1, 1), u16w(tv));
    }
    while (i != v.dung_num_inter_room_upsouth_straight_stairs.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 0), 0);
        writeAttr2(j + xy_p3(1, 1), 0);
        writeAttr2(j + xy_p3(1, 2), u16w(tv));
        writeAttr2(j + xy_p3(1, 3), 0x3939);
    }
    tv = (tv & 0x707) | 0x3434;
    while (i != v.dung_num_inter_room_southdown_stairs.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 2), u16w(tv));
        writeAttr2(j + xy_p3(1, 3), 0x2626);
    }
    while (i != v.dung_num_wall_downnorth_spiral_stairs.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 0), 0x5e5e);
        writeAttr2(j + xy_p3(1, 1), u16w(tv));
        writeAttr2(j + xy_p3(1, 2), 0x5e5e);
        writeAttr2(j + xy_p3(1, 3), 0x5e5e);
    }
    while (i != v.dung_num_wall_downnorth_spiral_stairs_2.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 0), 0x5f5f);
        writeAttr2(j + xy_p3(1, 1), u16w(tv));
        writeAttr2(j + xy_p3(1, 2), 0x5f5f);
        writeAttr2(j + xy_p3(1, 3), 0x5f5f);
    }
    while (i != v.dung_num_inter_room_downnorth_straight_stairs.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 0), 0x3838);
        writeAttr2(j + xy_p3(1, 1), u16w(tv));
        writeAttr2(j + xy_p3(1, 2), 0);
        writeAttr2(j + xy_p3(1, 3), 0);
    }
    while (i != v.dung_num_inter_room_downsouth_straight_stairs.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const j: c_int = @intCast(v.dung_inter_starcases[index(i >> 1)]);
        writeAttr2(j + xy_p3(1, 0), 0);
        writeAttr2(j + xy_p3(1, 1), 0);
        writeAttr2(j + xy_p3(1, 2), u16w(tv));
        writeAttr2(j + xy_p3(1, 3), 0x3939);
    }

    i = 0;
    skip3: {
        var typ: c_int = 0;
        var iend: c_int = @intCast(v.dung_num_inroom_upnorth_stairs.*);
        var attr: u16 = 0x1f1f;
        if (iend == 0) {
            typ = 1;
            attr = 0x1e1e;
            iend = @intCast(v.dung_num_inroom_southdown_stairs.*);
            if (iend == 0) {
                typ = 2;
                attr = 0x1d1d;
                iend = @intCast(v.dung_num_interpseudo_upnorth_stairs.*);
                if (iend == 0)
                    break :skip3;
            }
        }
        v.kind_of_in_room_staircase.* = u16w(typ);
        while (i != iend) : (i += 2) {
            const j: c_int = @intCast(v.dung_stairs_table_1[index(i >> 1)]);
            writeAttr2(j + xy_p3(0, 0), 0x02);
            writeAttr1(j + xy_p3(0, 3), 0x02);
            writeAttr2(j + xy_p3(2, 0), 0x0200);
            writeAttr1(j + xy_p3(2, 3), 0x0200);
            writeAttr2(j + xy_p3(0, 1), 0x01);
            writeAttr1(j + xy_p3(0, 2), 0x01);
            writeAttr2(j + xy_p3(2, 1), 0x0100); // todo: use 8-bit write?
            writeAttr1(j + xy_p3(2, 2), 0x0100);
            writeAttr2(j + xy_p3(1, 1), attr);
            writeAttr1(j + xy_p3(1, 1), attr);
            writeAttr2(j + xy_p3(1, 2), attr);
            writeAttr1(j + xy_p3(1, 2), attr);
        }
    }
    // skip3:
    if (i != v.dung_some_stairs_unk4.*) {
        v.kind_of_in_room_staircase.* = 2;
        while (i != v.dung_some_stairs_unk4.*) : (i += 2) {
            const j: c_int = @intCast(v.dung_stairs_table_1[index(i >> 1)]);
            writeAttr2(j + xy_p3(0, 0), 0xa03);
            writeAttr1(j + xy_p3(0, 0), 0xa03);
            writeAttr2(j + xy_p3(2, 0), 0x30a);
            writeAttr1(j + xy_p3(2, 0), 0x30a);
            writeAttr2(j + xy_p3(0, 1), 0x803);
            writeAttr2(j + xy_p3(2, 1), 0x308);
        }
    }
    i = 0;
    if (i != v.dung_num_inroom_upnorth_stairs_water.*) {
        v.kind_of_in_room_staircase.* = 2;
        while (i != v.dung_num_inroom_upnorth_stairs_water.*) : (i += 2) {
            const j: c_int = @intCast(v.dung_stairs_table_1[index(i >> 1)]);
            writeAttr2(j + xy_p3(0, 0), 0x003);
            writeAttr2(j + xy_p3(2, 0), 0x300);
            writeAttr1(j + xy_p3(0, 0), 0xa03);
            writeAttr1(j + xy_p3(2, 0), 0x30a);
            writeAttr2(j + xy_p3(0, 1), 0x808);
            writeAttr2(j + xy_p3(2, 1), 0x808);
        }
    }
    if (i != v.dung_num_activated_water_ladders.*) {
        v.kind_of_in_room_staircase.* = 2;
        while (i != v.dung_num_activated_water_ladders.*) : (i += 2) {
            const j: c_int = @intCast(v.dung_stairs_table_1[index(i >> 1)]);
            writeAttr2(j + xy_p3(0, 0), 0x003);
            writeAttr2(j + xy_p3(2, 0), 0x300);
            writeAttr1(j + xy_p3(0, 0), 0xa03);
            writeAttr1(j + xy_p3(2, 0), 0x30a);
        }
    }

    i = 0;
    tv = 0x7070;
    while (i != v.dung_misc_objs_index.*) : ({
        i += 2;
        tv += 0x101;
    }) {
        const k = v.dung_replacement_tile_state[index(i >> 1)];
        if ((k & 0xf0) != 0x30) {
            const j: c_int = @intCast((v.dung_object_tilemap_pos[index(i >> 1)] & 0x3fff) >> 1);
            writeAttr2(j + xy_p3(0, 0), u16w(tv));
            writeAttr2(j + xy_p3(0, 1), u16w(tv));
        }
    }

    if (i != v.dung_index_of_torches.*) {
        tv = 0xc0c0;
        while (i != v.dung_index_of_torches.*) : ({
            i += 2;
            tv = (tv & 0xefef) + 0x101;
        }) {
            const j: c_int = @intCast((v.dung_object_tilemap_pos[index(i >> 1)] & 0x3fff) >> 1);
            writeAttr2(j + xy_p3(0, 0), u16w(tv));
            writeAttr2(j + xy_p3(0, 1), u16w(tv));
        }
        v.dung_index_of_torches.* = 0;
    }

    tv = 0x5858;
    i = 0;
    no_big_key_locks: {
        if (v.dung_num_chests_x2.* != 0) {
            if (v.dung_hdr_tag[0] == 0x27 or v.dung_hdr_tag[0] == 0x3c or v.dung_hdr_tag[0] == 0x3e or v.dung_hdr_tag[0] >= 0x29 and v.dung_hdr_tag[0] < 0x33)
                break :no_big_key_locks;
            if (v.dung_hdr_tag[1] == 0x27 or v.dung_hdr_tag[1] == 0x3c or v.dung_hdr_tag[1] == 0x3e or v.dung_hdr_tag[1] >= 0x29 and v.dung_hdr_tag[1] < 0x33)
                break :no_big_key_locks;

            while (i != v.dung_num_chests_x2.*) : ({
                i += 2;
                tv += 0x101;
            }) {
                const k: c_int = @intCast(v.dung_chest_locations[index(i >> 1)]);
                if (k != 0) {
                    const j: c_int = (k & 0x7fff) >> 1;
                    writeAttr2(j + xy_p3(0, 0), u16w(tv));
                    writeAttr2(j + xy_p3(0, 1), u16w(tv));
                    if (k & 0x8000 != 0) {
                        v.dung_chest_locations[index(i >> 1)] = u16w(k & 0x7fff);
                        writeAttr2(j + xy_p3(2, 1), u16w(tv));
                        writeAttr2(j + xy_p3(0, 2), u16w(tv));
                        writeAttr2(j + xy_p3(2, 2), u16w(tv));
                    }
                }
            }
        }
        while (i != v.dung_num_bigkey_locks_x2.*) : ({
            i += 2;
            tv += 0x101;
        }) {
            const k: c_int = @intCast(v.dung_chest_locations[index(i >> 1)]);
            v.dung_chest_locations[index(i >> 1)] = u16w(k | 0x8000);
            const j: c_int = (k & 0x7fff) >> 1;
            writeAttr2(j + xy_p3(0, 0), u16w(tv));
            writeAttr2(j + xy_p3(0, 1), u16w(tv));
        }
    }
    // no_big_key_locks:

    i = 0;
    skip7: {
        var typ: c_int = 0;
        var iend: c_int = @intCast(v.dung_num_stairs_1.*);
        var attr: u16 = 0x3f3f;
        if (iend == 0) {
            typ = 1;
            attr = 0x3e3e;
            iend = @intCast(v.dung_num_stairs_2.*);
            if (iend == 0) {
                typ = 2;
                attr = 0x3d3d;
                iend = @intCast(v.dung_num_stairs_wet.*);
                if (iend == 0)
                    break :skip7;
            }
        }
        v.kind_of_in_room_staircase.* = u16w(typ);
        i = 0;
        while (i != iend) : (i += 2) {
            const j: c_int = @intCast(v.dung_stairs_table_2[index(i >> 1)]);
            writeAttr1(j + xy_p3(0, 0), 0x02);
            writeAttr2(j + xy_p3(0, 3), 0x02);
            writeAttr1(j + xy_p3(0, 1), 0x01);
            writeAttr2(j + xy_p3(0, 2), 0x01);
            writeAttr1(j + xy_p3(2, 0), 0x0200);
            writeAttr2(j + xy_p3(2, 3), 0x0200);
            writeAttr1(j + xy_p3(2, 1), 0x0100); // todo: use 8-bit write?
            writeAttr2(j + xy_p3(2, 2), 0x0100);
            writeAttr1(j + xy_p3(1, 1), attr);
            writeAttr2(j + xy_p3(1, 1), attr);
            writeAttr1(j + xy_p3(1, 2), attr);
            writeAttr2(j + xy_p3(1, 2), attr);
        }
    }
    // skip7:

    if (v.dung_num_inroom_upsouth_stairs_water.* != 0) {
        v.kind_of_in_room_staircase.* = 2;
        i = 0;
        while (i != v.dung_num_inroom_upsouth_stairs_water.*) : (i += 2) {
            const j: c_int = @intCast(v.dung_stairs_table_2[index(i >> 1)]);
            writeAttr1(j + xy_p3(0, 3), 0xa03);
            writeAttr1(j + xy_p3(2, 3), 0x30a);
            writeAttr2(j + xy_p3(0, 3), 0x003);
            writeAttr2(j + xy_p3(2, 3), 0x300);
            writeAttr2(j + xy_p3(0, 2), 0x808);
            writeAttr2(j + xy_p3(2, 2), 0x808);
        }
    }
    v.overworld_map_state.* +%= 1;
}

pub export fn Dungeon_LoadDoorAttribute() callconv(.c) void { // 81be17
    for (0..16) |i| {
        if (v.dung_door_tilemap_address[i] != 0)
            Dungeon_LoadSingleDoorAttribute(@intCast(i));
    }
    c.Dungeon_LoadSingleDoorTileAttribute();
    ChangeDoorToSwitch();
    v.overworld_map_state.* +%= 1;
}

pub export fn Dungeon_LoadSingleDoorAttribute(k: c_int) callconv(.c) void { // 81be35
    std.debug.assert(k >= 0 and k < 16);
    const ki = index(k);
    const ty: u8 = @truncate(v.door_type_and_slot[ki] & 0xfe);
    var dir: u8 = undefined;
    var attr: u16 = undefined;
    var i: c_int = undefined;
    var j: c_int = undefined;

    beta: {
        alpha: {
            if (ty == c.kDoorType_Regular or ty == c.kDoorType_EntranceDoor or ty == c.kDoorType_ExitToOw or ty == c.kDoorType_EntranceLarge or ty == c.kDoorType_EntranceCave)
                break :alpha;

            if (ty == c.kDoorType_EntranceLarge2 or ty == c.kDoorType_EntranceCave2 or ty == c.kDoorType_4 or ty == c.kDoorType_Regular2 or ty == c.kDoorType_WaterfallTunnel)
                break :beta;

            if (ty == c.kDoorType_LgExplosion)
                return;

            if (ty >= c.kDoorType_RegularDoor33) {
                if (ty == c.kDoorType_RegularDoor33 or ty == c.kDoorType_WarpRoomDoor)
                    break :beta;
                if (v.dung_door_opened_incl_adjacent.* & rtl.kUpperBitmasks[ki] != 0)
                    break :beta;

                j = @intCast(v.dung_door_tilemap_address[ki] >> 1);
                attr = u16w((0xf0 + k) * 0x101);
                writeAttr2(j + xy_p3(1, 1), attr);
                writeAttr2(j + xy_p3(1, 2), attr);
                return;
            }

            i = if (ty == c.kDoorType_ShuttersTwoWay or ty == c.kDoorType_Shutter) k else k & 7;
            if (v.dung_door_opened_incl_adjacent.* & rtl.kUpperBitmasks[index(i)] == 0) {
                j = @intCast(v.dung_door_tilemap_address[ki] >> 1);
                attr = u16w((0xf0 + k) * 0x101);
                writeAttr2(j + xy_p3(1, 1), attr);
                writeAttr2(j + xy_p3(1, 2), attr);
                return;
            }
        }
        // alpha:
        if (ty >= c.kDoorType_StairMaskLocked0 and ty <= c.kDoorType_StairMaskLocked3)
            return;
        attr = t.kTileAttrsByDoor[ty >> 1];
        dir = @truncate(v.dung_door_direction[ki] & 3);
        if (dir == 0) {
            const a = v.dung_door_tilemap_address[ki];
            if (a == v.dung_exit_door_addresses[0] or a == v.dung_exit_door_addresses[1] or a == v.dung_exit_door_addresses[2] or a == v.dung_exit_door_addresses[3])
                attr = 0x8e8e;
            j = @as(c_int, @intCast(a >> 1)) & ~@as(c_int, 0x7c0);
            writeAttr2(j + xy_p3(1, 0), attr);
            writeAttr2(j + xy_p3(1, 1), attr);
            writeAttr2(j + xy_p3(1, 2), attr);
            writeAttr2(j + xy_p3(1, 3), attr);
            writeAttr2(j + xy_p3(1, 4), attr);
            writeAttr2(j + xy_p3(1, 5), attr);
            writeAttr2(j + xy_p3(1, 6), attr);
            writeAttr2(j + xy_p3(1, 7), 0);
        } else if (dir == 1) {
            const a = v.dung_door_tilemap_address[ki];
            if (ty == c.kDoorType_EntranceLarge or ty == c.kDoorType_EntranceCave or
                a == v.dung_exit_door_addresses[0] or a == v.dung_exit_door_addresses[1] or a == v.dung_exit_door_addresses[2] or a == v.dung_exit_door_addresses[3])
                attr = 0x8e8e;
            j = @intCast(a >> 1);
            writeAttr2(j + xy_p3(1, 1), attr);
            writeAttr2(j + xy_p3(1, 2), attr);
            writeAttr2(j + xy_p3(1, 3), attr);
            writeAttr2(j + xy_p3(1, 4), attr);
            writeAttr2(j + xy_p3(1, 5), attr);
        } else if (dir == 2) {
            j = @as(c_int, @intCast(v.dung_door_tilemap_address[ki] >> 1)) & ~@as(c_int, 0x1f);
            writeAttr2(j + xy_p3(0, 1), attr +% 0x101);
            writeAttr2(j + xy_p3(2, 1), attr +% 0x101);
            writeAttr2(j + xy_p3(0, 2), attr +% 0x101);
            writeAttr2(j + xy_p3(2, 2), attr +% 0x101);
            writeAttr2(j + xy_p3(4, 1), (attr +% 0x101) & 0xff);
            writeAttr2(j + xy_p3(4, 2), (attr +% 0x101) & 0xff);
        } else {
            j = @intCast(v.dung_door_tilemap_address[ki] >> 1);
            writeAttr2(j + xy_p3(2, 1), attr +% 0x101);
            writeAttr2(j + xy_p3(4, 1), attr +% 0x101);
            writeAttr2(j + xy_p3(2, 2), attr +% 0x101);
            writeAttr2(j + xy_p3(4, 2), attr +% 0x101);
            writeAttr2(j + xy_p3(0, 1), (attr +% 0x101) & 0xff00);
            writeAttr2(j + xy_p3(0, 2), (attr +% 0x101) & 0xff00);
        }
        return;
    }
    // beta:
    attr = t.kTileAttrsByDoor[ty >> 1];
    dir = @truncate(v.dung_door_direction[ki] & 3);
    if (dir == 0) {
        j = @as(c_int, @intCast(v.dung_door_tilemap_address[ki] >> 1)) & ~@as(c_int, 0x7c0);
        writeAttr2(j + xy_p3(1, 0), attr);
        writeAttr2(j + xy_p3(1, 1), attr);
        writeAttr2(j + xy_p3(1, 2), attr);
        writeAttr2(j + xy_p3(1, 3), attr);
        writeAttr2(j + xy_p3(1, 4), attr);
        writeAttr2(j + xy_p3(1, 5), attr);
        writeAttr2(j + xy_p3(1, 6), attr);
        writeAttr2(j + xy_p3(1, 7), attr);
        writeAttr2(j + xy_p3(1, 8), attr);
        writeAttr2(j + xy_p3(1, 9), attr);
    } else if (dir == 1) {
        const a = v.dung_door_tilemap_address[ki] & 0x1fff;
        if (ty == c.kDoorType_EntranceLarge2 or ty == c.kDoorType_EntranceCave2 or ty == c.kDoorType_4 or
            a == v.dung_exit_door_addresses[0] or a == v.dung_exit_door_addresses[1] or a == v.dung_exit_door_addresses[2] or a == v.dung_exit_door_addresses[3])
            attr = 0x8e8e;
        j = @intCast(v.dung_door_tilemap_address[ki] >> 1);
        writeAttr2(j + xy_p3(1, 1), attr);
        writeAttr2(j + xy_p3(1, 2), attr);
        writeAttr2(j + xy_p3(1, 3), attr);
        writeAttr2(j + xy_p3(1, 4), attr);
        writeAttr2(j + xy_p3(1, 5), attr);
        writeAttr2(j + xy_p3(1, 6), attr);
        writeAttr2(j + xy_p3(1, 7), attr);
        writeAttr2(j + xy_p3(1, 8), attr);
    } else if (dir == 2) {
        j = @as(c_int, @intCast(v.dung_door_tilemap_address[ki] >> 1)) & ~@as(c_int, 0x1f);
        writeAttr2(j + xy_p3(0, 1), attr +% 0x101);
        writeAttr2(j + xy_p3(2, 1), attr +% 0x101);
        writeAttr2(j + xy_p3(4, 1), attr +% 0x101);
        writeAttr2(j + xy_p3(6, 1), attr +% 0x101);
        writeAttr2(j + xy_p3(0, 2), attr +% 0x101);
        writeAttr2(j + xy_p3(2, 2), attr +% 0x101);
        writeAttr2(j + xy_p3(4, 2), attr +% 0x101);
        writeAttr2(j + xy_p3(6, 2), attr +% 0x101);
    } else {
        j = @as(c_int, @intCast(v.dung_door_tilemap_address[ki] >> 1)) + 1;
        writeAttr2(j + xy_p3(0, 1), attr +% 0x101);
        writeAttr2(j + xy_p3(2, 1), attr +% 0x101);
        writeAttr2(j + xy_p3(4, 1), attr +% 0x101);
        writeAttr2(j + xy_p3(6, 1), attr +% 0x101);
        writeAttr2(j + xy_p3(0, 2), attr +% 0x101);
        writeAttr2(j + xy_p3(2, 2), attr +% 0x101);
        writeAttr2(j + xy_p3(4, 2), attr +% 0x101);
        writeAttr2(j + xy_p3(6, 2), attr +% 0x101);
    }
}

pub export fn Door_LoadBlastWallAttr(k: c_int) callconv(.c) void { // 81bfc1
    var j: c_int = @intCast(v.dung_door_tilemap_address[index(k)] >> 1);
    if (v.dung_door_direction[index(k)] & 2 == 0) {
        var n: c_int = 12;
        while (n != 0) : (n -= 1) {
            writeAttr2(j + xy_p3(0, 0), 0x102);
            var i: c_int = 2;
            while (i < 20) : (i += 2)
                writeAttr2(j + xy_p3(i, 0), 0x0);
            writeAttr2(j + xy_p3(20, 0), 0x201);
            j += xy_p3(0, 1);
        }
    } else {
        var n: c_int = 5;
        while (n != 0) : (n -= 1) {
            writeAttr2(j + xy_p3(0, 0), 0x101);
            writeAttr2(j + xy_p3(0, 21), 0x101);
            writeAttr2(j + xy_p3(0, 1), 0x202);
            writeAttr2(j + xy_p3(0, 20), 0x202);
            var i: c_int = 2;
            while (i < 20) : (i += 1)
                writeAttr2(j + xy_p3(0, i), 0x0);
            j += xy_p3(2, 0);
        }
    }
}

pub export fn ChangeDoorToSwitch() callconv(.c) void { // 81c1ba
    std.debug.assert(v.dung_unk5.* == 0);
}

pub export fn Dungeon_FlipCrystalPegAttribute() callconv(.c) void { // 81c22a
    var i: c_int = 0xfff;
    while (i >= 0) : (i -= 1) {
        if ((v.dung_bg2_attr_table[index(i)] & ~@as(u8, 1)) == 0x66)
            v.dung_bg2_attr_table[index(i)] ^= 1;
        if ((v.dung_bg1_attr_table[index(i)] & ~@as(u8, 1)) == 0x66)
            v.dung_bg1_attr_table[index(i)] ^= 1;
    }
}

pub export fn Dungeon_HandleRoomTags() callconv(.c) void { // 81c2fd
    if (v.flag_skip_call_tag_routines.* == 0) {
        Dungeon_DetectStaircase();

        // Dungeon_DetectStaircase might change the submodule, so avoid
        // calling the tag routines cause they could also change the submodule,
        // causing items to spawn in incorrect locations cause link_x/y_coord gets
        // out of sync if you enter a staircase exactly when a room tag triggers.
        if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0 and v.submodule_index.* != 0)
            return;

        v.g_ram[14] = 0;
        t.kDungTagroutines[v.dung_hdr_tag[0]].?(0);
        v.g_ram[14] = 1;
        t.kDungTagroutines[v.dung_hdr_tag[1]].?(1);
    }
    v.flag_skip_call_tag_routines.* = 0;
}

pub export fn Dung_TagRoutine_0x00(k: c_int) callconv(.c) void { // 81c328
    _ = k;
}

pub export fn Dungeon_DetectStaircase() callconv(.c) void { // 81c329
    const k: c_int = v.link_direction.* & 12;
    if (k == 0)
        return;

    const kBuggyLookup = [_]i8{ 7, 24, 8, 8, 0, 0, -1, 17 };
    var pos: c_int = ((@as(c_int, v.link_y_coord.*) + kBuggyLookup[index(k >> 1)]) & 0x1f8) << 3;
    pos |= (@as(c_int, v.link_x_coord.*) & 0x1f8) >> 3;
    pos |= if (v.link_is_on_lower_level.* != 0) @as(c_int, 0x1000) else 0;

    const at = v.dung_bg2_attr_table[index(pos + @as(c_int, if (k == 4) 0x80 else 0))];
    if (!(at == 0x26 or at == 0x38 or at == 0x39 or at == 0x5e or at == 0x5f))
        return;

    const attr2 = v.dung_bg2_attr_table[index(pos + xy_p3(0, 1))];
    if ((attr2 & 0xf8) != 0x30)
        return;

    if (v.link_state_bits.* & 0x80 != 0) {
        v.link_y_coord.* = v.link_y_coord_prev.*;
        return;
    }

    v.which_staircase_index.* = attr2;
    v.which_staircase_index_PADDING.* = u8w(pos >> 8); // residual
    v.dungeon_room_index_prev.* = v.dungeon_room_index.*;
    c.Dungeon_FlagRoomData_Quadrants();

    if (at == 0x38 or at == 0x39) {
        v.staircase_var1.* = 0x20;
        if (at == 0x38)
            c.Dungeon_StartInterRoomTrans_Up()
        else
            c.Dungeon_StartInterRoomTrans_Down();
    }

    const j = v.which_staircase_index.* & 3;
    low(v.dungeon_room_index).* = v.dung_hdr_travel_destinations[index(j) + 1];
    v.cur_staircase_plane.* = v.dung_hdr_staircase_plane[index(j)];
    v.byte_7E0492.* = if (v.link_is_on_lower_level.* != 0 or v.link_is_on_lower_level_mirror.* != 0) 2 else 0;
    v.subsubmodule_index.* = 0;
    v.bitmask_of_dragstate.* = 0;
    v.link_delay_timer_spin_attack.* = 0;
    v.button_mask_b_y.* = 0;
    v.button_b_frames.* = 0;
    v.link_cant_change_direction.* &= ~@as(u8, 1);
    if (at == 0x26) {
        v.submodule_index.* = 6;
        v.sound_effect_1.* = if (v.cur_staircase_plane.* < 0x34) 22 else 24; // wtf?
    } else if (at == 0x38 or at == 0x39) {
        v.submodule_index.* = if (at == 0x38) 18 else 19;
        v.link_timer_push_get_tired.* = 7;
    } else {
        c.UsedForStraightInterRoomStaircase();
        v.submodule_index.* = 14;
    }
}

pub export fn RoomTag_NorthWestTrigger(k: c_int) callconv(.c) void { // 81c432
    if (v.link_x_coord.* & 0x100 == 0 and v.link_y_coord.* & 0x100 == 0)
        RoomTag_QuadrantTrigger(k);
}

pub export fn Dung_TagRoutine_0x2A(k: c_int) callconv(.c) void { // 81c438
    if (v.link_x_coord.* & 0x100 != 0 and v.link_y_coord.* & 0x100 == 0)
        RoomTag_QuadrantTrigger(k);
}

pub export fn Dung_TagRoutine_0x2B(k: c_int) callconv(.c) void { // 81c43e
    if (v.link_x_coord.* & 0x100 == 0 and v.link_y_coord.* & 0x100 != 0)
        RoomTag_QuadrantTrigger(k);
}

pub export fn Dung_TagRoutine_0x2C(k: c_int) callconv(.c) void { // 81c444
    if (v.link_x_coord.* & 0x100 != 0 and v.link_y_coord.* & 0x100 != 0)
        RoomTag_QuadrantTrigger(k);
}

pub export fn Dung_TagRoutine_0x2D(k: c_int) callconv(.c) void { // 81c44a
    if (v.link_x_coord.* & 0x100 == 0)
        RoomTag_QuadrantTrigger(k);
}

pub export fn Dung_TagRoutine_0x2E(k: c_int) callconv(.c) void { // 81c450
    if (v.link_x_coord.* & 0x100 != 0)
        RoomTag_QuadrantTrigger(k);
}

pub export fn Dung_TagRoutine_0x2F(k: c_int) callconv(.c) void { // 81c456
    if (v.link_y_coord.* & 0x100 == 0)
        RoomTag_QuadrantTrigger(k);
}

pub export fn Dung_TagRoutine_0x30(k: c_int) callconv(.c) void { // 81c45c
    if (v.link_y_coord.* & 0x100 != 0)
        RoomTag_QuadrantTrigger(k);
}

pub export fn RoomTag_QuadrantTrigger(k: c_int) callconv(.c) void { // 81c461
    const tag = v.dung_hdr_tag[index(k)];
    if (tag >= 0xb) {
        if (tag >= 0x29) {
            if (c.Sprite_CheckIfScreenIsClear())
                RoomTag_OperateChestReveal(k);
        } else {
            const a = v.dung_flag_movable_block_was_pushed.* ^ 1;
            if (a != low(v.dung_flag_trapdoors_down).*) {
                low(v.dung_flag_trapdoors_down).* = a;
                v.sound_effect_2.* = 37;
                v.submodule_index.* = 5;
                v.dung_cur_door_pos.* = 0;
                v.door_animation_step_indicator.* = 0;
            }
        }
    } else {
        if (c.Sprite_CheckIfScreenIsClear())
            Dung_TagRoutine_TrapdoorsUp();
    }
}

pub export fn Dung_TagRoutine_TrapdoorsUp() callconv(.c) void { // 81c49e
    if (v.dung_flag_trapdoors_down.* != 0) {
        v.dung_flag_trapdoors_down.* = 0;
        v.dung_cur_door_pos.* = 0;
        v.door_animation_step_indicator.* = 0;
        v.sound_effect_2.* = 0x1b;
        v.submodule_index.* = 5;
    }
}

pub export fn RoomTag_RoomTrigger(k: c_int) callconv(.c) void { // 81c4bf
    if (v.dung_hdr_tag[index(k)] == 10) {
        if (c.Sprite_CheckIfRoomIsClear())
            Dung_TagRoutine_TrapdoorsUp();
    } else {
        if (c.Sprite_CheckIfRoomIsClear())
            RoomTag_OperateChestReveal(k);
    }
}

pub export fn RoomTag_RekillableBoss(k: c_int) callconv(.c) void { // 81c4db
    _ = k;
    if (c.Sprite_CheckIfRoomIsClear()) {
        v.flag_block_link_menu.* = 0;
        v.dung_hdr_tag[1] = 0;
    }
}

pub export fn RoomTag_RoomTrigger_BlockDoor(k: c_int) callconv(.c) void { // 81c4e7
    _ = k;
    if (v.dung_flag_statechange_waterpuzzle.* != 0 and v.dung_flag_trapdoors_down.* != 0) {
        v.dung_flag_trapdoors_down.* = 0;
        v.dung_cur_door_pos.* = 0;
        v.door_animation_step_indicator.* = 0;
        v.submodule_index.* = 5;
    }
}

// Used for bosses
pub export fn RoomTag_PrizeTriggerDoorDoor(k: c_int) callconv(.c) void { // 81c508
    const tt: u8 = if (v.savegame_is_darkworld.* != 0) v.link_has_crystals.* else v.link_which_pendants.*;
    if (tt & rtl.kDungeonCrystalPendantBit[@as(u8, @truncate(v.cur_palace_index_x2.*)) >> 1] != 0) {
        v.dung_flag_trapdoors_down.* = 0;
        v.dung_cur_door_pos.* = 0;
        v.door_animation_step_indicator.* = 0;
        v.submodule_index.* = 5;
        v.dung_hdr_tag[index(k)] = 0;
    }
}

pub export fn RoomTag_SwitchTrigger_HoldDoor(k: c_int) callconv(.c) void { // 81c541
    _ = k;
    var vv: u16 = undefined;
    var tmp: u8 = undefined;
    shortcut: {
        var i: u16 = 0xfffe;
        while (true) {
            i +%= 2;
            if (i == v.dung_index_of_torches_start.*)
                break;
            if (v.dung_replacement_tile_state[i >> 1] == 5) {
                vv = v.related_to_trapdoors_somehow.*;
                if (vv != 0xffff)
                    break :shortcut;
                break;
            }
        }
        vv = @intFromBool(v.dung_flag_somaria_block_switch.* == 0 and v.dung_flag_statechange_waterpuzzle.* == 0 and !RoomTag_CheckForPressedSwitch(&tmp));
    }
    // shortcut:
    if (vv != v.dung_flag_trapdoors_down.*) {
        v.dung_flag_trapdoors_down.* = vv;
        v.dung_cur_door_pos.* = 0;
        v.door_animation_step_indicator.* = 0;
        if (vv == 0)
            v.sound_effect_2.* = 0x25;
        v.submodule_index.* = 5;
    }
}

pub export fn RoomTag_SwitchTrigger_ToggleDoor(k: c_int) callconv(.c) void { // 81c599
    _ = k;
    var attr: u8 = undefined;
    if (v.dung_door_switch_triggered.* == 0) {
        if (RoomTag_MaybeCheckShutters(&attr)) {
            v.dung_cur_door_pos.* = 0;
            v.door_animation_step_indicator.* = 0;
            v.sound_effect_2.* = 0x25;
            PushPressurePlate(attr);
            v.dung_flag_trapdoors_down.* ^= 1;
            v.dung_door_switch_triggered.* = 1;
        }
    } else {
        if (!RoomTag_MaybeCheckShutters(&attr))
            v.dung_door_switch_triggered.* = 0;
    }
}

pub export fn PushPressurePlate(attr: u8) callconv(.c) void { // 81c5cf
    v.submodule_index.* = 5;
    if (attr == 0x23 or v.word_7E04B6.* == 0)
        return;
    v.saved_module_for_menu.* = v.submodule_index.*;
    v.submodule_index.* = 23;
    v.subsubmodule_index.* = 32;
    v.link_y_coord.* +%= 2;
    if ((attr2w(@intCast(v.word_7E04B6.*)).* & 0xfe00) != 0x2400)
        v.word_7E04B6.* +%= 1;
    c.Dungeon_UpdateTileMapWithCommonTile((v.word_7E04B6.* & 0x3f) << 3, (v.word_7E04B6.* >> 3) & 0x1f8, 0x10);
}

pub export fn RoomTag_TorchPuzzleDoor(k: c_int) callconv(.c) void { // 81c629
    _ = k;
    var j: c_int = 0;
    for (0..16) |i| {
        if (v.dung_object_tilemap_pos[i] & 0x8000 != 0)
            j += 1;
    }
    const down: u16 = @intFromBool(j < 4);
    if (down != v.dung_flag_trapdoors_down.*) {
        v.dung_flag_trapdoors_down.* = down;
        v.dung_cur_door_pos.* = 0;
        v.door_animation_step_indicator.* = 0;
        v.sound_effect_2.* = 0x1b;
        v.submodule_index.* = 5;
    }
}

pub export fn RoomTag_Switch_ExplodingWall(k: c_int) callconv(.c) void { // 81c67a
    var yv: u8 = undefined;
    if (!RoomTag_MaybeCheckShutters(&yv))
        return;

    Dung_TagRoutine_BlastWallStuff(k);
}

pub export fn RoomTag_PullSwitchExplodingWall(k: c_int) callconv(.c) void { // 81c685
    if (v.dung_flag_statechange_waterpuzzle.* == 0)
        return;
    Dung_TagRoutine_BlastWallStuff(k);
}

pub export fn Dung_TagRoutine_BlastWallStuff(k: c_int) callconv(.c) void { // 81c68c
    const kBlastWall_Tab0 = [5]u8{ 4, 6, 0, 0, 2 };
    const kBlastWall_Tab1 = [5]u16{ 0, 0xa, 0, 0, 0x280 };

    v.dung_hdr_tag[index(k)] = 0;

    var j: c_int = -1;
    while (true) {
        j += 1;
        if ((v.door_type_and_slot[index(j)] & ~@as(u16, 1)) == 0x30) break;
    }
    v.dung_unk_blast_walls_3.* = u16w(j * 2);

    var i: c_int = ((@as(c_int, v.link_y_coord.*) >> 8 & 1) + 1) * 2;
    if (v.dung_door_direction[index(j)] & 2 != 0)
        i = @as(c_int, v.link_x_coord.*) >> 8 & 1;

    v.messaging_buf[0x1c / 2] = kBlastWall_Tab0[index(i)];
    j = @as(c_int, v.dung_door_tilemap_address[index(j)]) + kBlastWall_Tab1[index(i)];

    v.messaging_buf[0x1a / 2] = u16w((j & 0x7e) * 4) +% v.dung_loade_bgoffs_h_copy.*;
    v.messaging_buf[0x18 / 2] = u16w((j & 0x1f80) >> 4) +% v.dung_loade_bgoffs_v_copy.*;
    v.sound_effect_2.* = 27;
    low(v.dung_unk_blast_walls_2).* = 1;
    c.AncillaAdd_BlastWall();
}

// Used for bosses
pub export fn RoomTag_GetHeartForPrize(k: c_int) callconv(.c) void { // 81c709
    const kBossFinishedFallingItem = [13]u8{ 0, 0, 1, 2, 0, 6, 6, 6, 6, 6, 3, 6, 6 };
    if (v.dung_savegame_state_bits.* & 0x8000 == 0)
        return;
    const tt: u8 = if (v.savegame_is_darkworld.* != 0) v.link_has_crystals.* else v.link_which_pendants.*;
    if (tt & rtl.kDungeonCrystalPendantBit[@as(u8, @truncate(v.cur_palace_index_x2.*)) >> 1] == 0) {
        v.byte_7E04C2.* = 128;
        if (c.Ancilla_SpawnFallingPrize(kBossFinishedFallingItem[@as(u8, @truncate(v.cur_palace_index_x2.*)) >> 1]) < 0)
            return; // Zelda bugfix. Price won't spawn if we're out of ancillas
    }
    v.dung_hdr_tag[index(k)] = 0;
}

pub export fn RoomTag_Agahnim(k: c_int) callconv(.c) void { // 81c74e
    _ = k;
    if (v.save_ow_event_info[0x5b] & 0x20 == 0 and v.dung_savegame_state_bits.* & 0x8000 != 0) {
        c.Palette_RevertTranslucencySwap();
        v.dung_hdr_tag[0] = 0;
        c.PrepareDungeonExitFromBossFight();
    }
}

pub export fn RoomTag_GanonDoor(tagidx: c_int) callconv(.c) void { // 81c767
    _ = tagidx;
    var k: c_int = 15;
    while (k >= 0) : (k -= 1) {
        if (v.sprite_state[index(k)] == 4 or v.sprite_flags4[index(k)] & 64 == 0 and v.sprite_state[index(k)] != 0)
            return;
    }
    if (v.link_player_handler_state.* != c.kPlayerState_FallingIntoHole) {
        v.flag_is_link_immobilized.* = 26;
        v.submodule_index.* = 26;
        v.subsubmodule_index.* = 0;
        v.dung_hdr_tag[0] = 0;
        v.link_force_hold_sword_up.* = 1;
        v.button_mask_b_y.* = 0;
        v.button_b_frames.* = 0;
        v.R16.* = 0x364;
    }
}

pub export fn RoomTag_KillRoomBlock(k: c_int) callconv(.c) void { // 81c7a2
    if (v.link_x_coord.* & 0x100 != 0 and v.link_y_coord.* & 0x100 != 0) {
        if (c.Sprite_CheckIfScreenIsClear()) {
            v.sound_effect_2.* = 0x1b;
            v.dung_hdr_tag[index(k)] = 0;
        }
    }
}

pub export fn RoomTag_PushBlockForChest(k: c_int) callconv(.c) void { // 81c7c2
    if (v.nmi_load_bg_from_vram.* == 0 and v.dung_flag_movable_block_was_pushed.* != 0)
        RoomTag_OperateChestReveal(k);
}

pub export fn RoomTag_TriggerChest(k: c_int) callconv(.c) void { // 81c7cc
    var attr: u8 = undefined;
    if (v.countdown_for_blink.* == 0 and RoomTag_MaybeCheckShutters(&attr))
        RoomTag_OperateChestReveal(k);
}

pub export fn RoomTag_OperateChestReveal(k: c_int) callconv(.c) void { // 81c7d8
    v.dung_hdr_tag[index(k)] = 0;
    v.vram_upload_offset.* = 0;
    const oms = word(v.overworld_map_state);
    oms.* = 0;
    var attr: u16 = 0x5858;
    while (true) {
        const pos: c_int = @intCast(v.dung_chest_locations[index(oms.* >> 1)] >> 1 & 0x1fff);

        attr2w(pos + xy_p3(0, 0)).* = attr;
        attr2w(pos + xy_p3(0, 1)).* = attr;
        attr +%= 0x101;

        const src = SrcPtr(0x149c);
        v.dung_bg2[index(pos + xy_p3(0, 0))] = src[0];
        v.dung_bg2[index(pos + xy_p3(0, 1))] = src[1];
        v.dung_bg2[index(pos + xy_p3(1, 0))] = src[2];
        v.dung_bg2[index(pos + xy_p3(1, 1))] = src[3];

        const yy = oms.*;

        const dst = v.vram_upload_data + index(v.vram_upload_offset.* >> 1);
        dst[0] = c.RoomTag_BuildChestStripes(u16w(xy_p3(0, 0) * 2), yy);
        dst[3] = c.RoomTag_BuildChestStripes(u16w(xy_p3(0, 1) * 2), yy);
        dst[6] = c.RoomTag_BuildChestStripes(u16w(xy_p3(1, 0) * 2), yy);
        dst[9] = c.RoomTag_BuildChestStripes(u16w(xy_p3(1, 1) * 2), yy);

        dst[2] = src[0];
        dst[5] = src[1];
        dst[8] = src[2];
        dst[11] = src[3];

        dst[1] = 0x100;
        dst[4] = 0x100;
        dst[7] = 0x100;
        dst[10] = 0x100;

        dst[12] = 0xffff;

        v.vram_upload_offset.* +%= 24;
        oms.* +%= 2;
        if (oms.* == v.dung_num_chests_x2.*) break;
    }
    oms.* = 0;
    v.sound_effect_2.* = 26;
    v.nmi_load_bg_from_vram.* = 1;
}

pub export fn RoomTag_TorchPuzzleChest(k: c_int) callconv(.c) void { // 81c8ae
    var j: c_int = 0;
    for (0..16) |i| {
        if (v.dung_object_tilemap_pos[i] & 0x8000 != 0)
            j += 1;
    }
    if (j >= 4)
        RoomTag_OperateChestReveal(k);
}

pub export fn RoomTag_MovingWall_East(k: c_int) callconv(.c) void { // 81c8d4
    const kMovingWall_Tab1 = [8]i16{ -63, -127, -191, -255, -71, -135, -199, -263 };

    if (v.dung_floor_move_flags.* == 0) {
        RoomTag_MovingWallTorchesCheck(k);
        v.dung_floor_x_vel.* = 0;
    } else {
        v.flag_unk1.* = 1;
        RoomTag_MovingWallShakeItUp(k);
        v.dung_floor_x_vel.* = u16w(MovingWall_MoveALittle());
    }
    v.dung_floor_x_offs.* -%= v.dung_floor_x_vel.*;
    v.BG1HOFS_copy2.* = v.BG2HOFS_copy2.* +% v.dung_floor_x_offs.*;

    if (v.dung_floor_x_vel.* != 0) {
        if (v.dung_floor_x_offs.* < @as(u16, @bitCast(kMovingWall_Tab1[index(v.moving_wall_var2.* >> 1)])) and
            v.dung_floor_x_offs.* < @as(u16, @bitCast(kMovingWall_Tab1[index(RoomTag_AdvanceGiganticWall(k) >> 1)])))
        {
            v.sound_effect_2.* = 0x1b;
            v.sound_effect_ambient.* = 5;
            v.dung_hdr_tag[index(k)] = 0;
            v.flag_is_link_immobilized.* = 0;
            v.flag_unk1.* = 0;
            v.bg1_y_offset.* = 0;
            v.bg1_x_offset.* = 0;
        }
        v.nmi_subroutine_index.* = 5;
        const neg: c_int = -@as(c_int, v.dung_floor_x_offs.*);
        v.nmi_load_target_addr.* = u16w((@as(c_int, v.moving_wall_var1.*) - ((neg & 0x1f8) >> 3)) & 0x141f);
    }
}

pub export fn RoomTag_MovingWallShakeItUp(k: c_int) callconv(.c) void { // 81c969
    const i = v.frame_counter.* & 1;
    v.bg1_x_offset.* = if (i != 0) 0xffff else 1;
    v.bg1_y_offset.* = 0 -% v.bg1_x_offset.*;
    if (v.dung_hdr_tag[index(k)] == 0) {
        v.bg1_y_offset.* = 0;
        v.bg1_x_offset.* = 0;
    }
}

pub export fn RoomTag_MovingWall_West(k: c_int) callconv(.c) void { // 81c98b
    const kMovingWall_Tab0 = [8]u16{ 0x42, 0x82, 0xc2, 0x102, 0x4a, 0x8a, 0xca, 0x10a };

    if (v.dung_floor_move_flags.* == 0) {
        RoomTag_MovingWallTorchesCheck(k);
        v.dung_floor_x_vel.* = 0;
    } else {
        v.flag_unk1.* = 1;
        RoomTag_MovingWallShakeItUp(k);
        v.dung_floor_x_vel.* = u16w(MovingWall_MoveALittle());
    }
    v.dung_floor_x_offs.* +%= v.dung_floor_x_vel.*;
    v.BG1HOFS_copy2.* = v.BG2HOFS_copy2.* +% v.dung_floor_x_offs.*;
    if (v.dung_floor_x_vel.* != 0) {
        if (v.dung_floor_x_offs.* >= kMovingWall_Tab0[index(v.moving_wall_var2.* >> 1)] and
            v.dung_floor_x_offs.* >= kMovingWall_Tab0[index(RoomTag_AdvanceGiganticWall(k) >> 1)])
        {
            v.sound_effect_2.* = 0x1b;
            v.sound_effect_ambient.* = 5;
            v.dung_hdr_tag[index(k)] = 0;
            v.flag_is_link_immobilized.* = 0;
            v.flag_unk1.* = 0;
            v.bg1_y_offset.* = 0;
            v.bg1_x_offset.* = 0;
        }
        v.nmi_subroutine_index.* = 5;
        v.nmi_load_target_addr.* = v.moving_wall_var1.* +% ((v.dung_floor_x_offs.* & 0x1f8) >> 3);
        if (v.nmi_load_target_addr.* & 0x1020 != 0)
            v.nmi_load_target_addr.* = (v.nmi_load_target_addr.* & 0x1020) ^ 0x420;
    }
}

pub export fn RoomTag_MovingWallTorchesCheck(k: c_int) callconv(.c) void { // 81ca17
    if (v.dung_flag_statechange_waterpuzzle.* == 0) {
        var count: c_int = 0;
        for (0..16) |i|
            count += @intFromBool(v.dung_object_tilemap_pos[i] & 0x8000 != 0);
        if (count < 4)
            return;
    }
    v.dung_floor_move_flags.* +%= 1;
    word(v.dung_flag_statechange_waterpuzzle).* = 0;
    v.dung_savegame_state_bits.* |= u16w(@as(c_int, 0x1000) >> @intCast(k));
    v.sound_effect_ambient.* = 7;
    v.flag_is_link_immobilized.* = 1;
    v.flag_unk1.* = 1;
}

pub export fn MovingWall_MoveALittle() callconv(.c) c_int { // 81ca66
    const tt: c_int = @as(c_int, v.dung_some_subpixel[1]) + 0x22;
    v.dung_some_subpixel[1] = u8w(tt);
    return tt >> 8;
}

pub export fn RoomTag_AdvanceGiganticWall(k: c_int) callconv(.c) c_int { // 81ca75
    var i: c_int = v.moving_wall_var2.*;
    if (v.dung_hdr_tag[index(k)] < 0x20) {
        v.dung_hdr_collision.* = 0;
        v.TM_copy.* = 0x16;
        i += 8;
    }
    return i;
}

pub export fn RoomTag_WaterOff(k: c_int) callconv(.c) void { // 81ca94
    _ = k;
    if (v.dung_flag_statechange_waterpuzzle.* != 0) {
        v.W12SEL_copy.* = 3;
        v.W34SEL_copy.* = 0;
        v.WOBJSEL_copy.* = 0;
        v.TMW_copy.* = 22;
        v.TSW_copy.* = 1;
        v.turn_on_off_water_ctr.* = 1;
        c.AdjustWaterHDMAWindow();
        v.submodule_index.* = 11;
        v.palette_filter_countdown.* = 0;
        v.darkening_or_lightening_screen.* = 0;
        v.mosaic_target_level.* = 31;
        v.flag_update_cgram_in_nmi.* +%= 1;
        v.dung_hdr_tag[1] = 0;
        v.dung_savegame_state_bits.* |= 0x800;
        v.dung_flag_statechange_waterpuzzle.* = 0;
        const dsto: c_int = ((@as(c_int, v.water_hdma_var1.*) & 0x1ff) - 0x10) << 3 | ((@as(c_int, v.water_hdma_var0.*) & 0x1ff) - 0x10) >> 3;
        DrawWaterThing(v.dung_bg2 + index(dsto), SrcPtr(0x1438));
        _ = c.Dungeon_PrepOverlayDma_nextPrep(0, u16w(dsto * 2));
        v.sound_effect_2.* = 0x1b;
        v.sound_effect_1.* = 0x2e;
        v.nmi_copy_packets_flag.* = 1;
    }
}

pub export fn RoomTag_WaterOn(k: c_int) callconv(.c) void { // 81cb1a
    _ = k;
    if (v.dung_flag_statechange_waterpuzzle.* != 0) {
        v.sound_effect_2.* = 0x1b;
        v.sound_effect_1.* = 0x2f;
        v.submodule_index.* = 12;
        v.subsubmodule_index.* = 0;
        low(v.dung_floor_y_offs).* = 1;
        v.dung_hdr_tag[1] = 0;
        v.dung_savegame_state_bits.* |= 0x800;
        v.dung_flag_statechange_waterpuzzle.* = 0;
        v.dung_cur_quadrant_upload.* = 0;
    }
}

pub export fn RoomTag_WaterGate(k: c_int) callconv(.c) void { // 81cb49
    _ = k;
    if (v.dung_savegame_state_bits.* & 0x800 != 0 or v.dung_flag_statechange_waterpuzzle.* == 0)
        return;
    v.submodule_index.* = 13;
    v.subsubmodule_index.* = 0;
    v.dung_hdr_tag[1] = 0;
    v.dung_savegame_state_bits.* |= 0x800;
    v.dung_flag_statechange_waterpuzzle.* = 0;
    low(v.water_hdma_var2).* = 0;
    low(v.spotlight_var4).* = 0;
    v.W12SEL_copy.* = 3;
    v.W34SEL_copy.* = 0;
    v.WOBJSEL_copy.* = 0;
    v.TMW_copy.* = 0x16;
    v.TSW_copy.* = 1;
    v.CGWSEL_copy.* = 2;
    v.CGADSUB_copy.* = 0x62;
    v.save_ow_event_info[0x3b] |= 32;
    v.save_ow_event_info[0x7b] |= 32;
    v.save_dung_info[0x28] |= 0x100;
    RoomTag_OperateWaterFlooring();
    v.water_hdma_var0.* = ((v.watergate_pos.* & 0x7e) << 2) +% (v.dung_draw_width_indicator.* *% 16 +% v.dung_loade_bgoffs_h_copy.* +% 40);
    v.spotlight_y_upper.* = (v.watergate_pos.* & 0x1f80) >> 4;
    v.word_7E0678.* = v.spotlight_y_upper.*;
    v.water_hdma_var1.* = v.word_7E0678.* +% v.dung_loade_bgoffs_v_copy.*;
    v.water_hdma_var3.* = 0;
    v.sound_effect_2.* = 0x1b;
    v.sound_effect_1.* = 0x2f;
}

pub export fn Dung_TagRoutine_0x1B(k: c_int) callconv(.c) void { // 81cbff
    _ = k;
    // empty
}

pub export fn RoomTag_Holes0(k: c_int) callconv(.c) void { // 81cc00
    _ = k;
    Dung_TagRoutine_Func2(1);
}

pub export fn Dung_TagRoutine_0x23(k: c_int) callconv(.c) void { // 81cc04
    _ = k;
    Dung_TagRoutine_Func2(3);
}

pub export fn Dung_TagRoutine_0x34(k: c_int) callconv(.c) void { // 81cc08
    _ = k;
    Dung_TagRoutine_Func2(6);
}

pub export fn Dung_TagRoutine_0x35(k: c_int) callconv(.c) void { // 81cc0c
    _ = k;
    Dung_TagRoutine_Func2(8);
}

pub export fn Dung_TagRoutine_0x36(k: c_int) callconv(.c) void { // 81cc10
    _ = k;
    Dung_TagRoutine_Func2(10);
}

pub export fn Dung_TagRoutine_0x37(k: c_int) callconv(.c) void { // 81cc14
    _ = k;
    Dung_TagRoutine_Func2(12);
}

pub export fn Dung_TagRoutine_0x39(k: c_int) callconv(.c) void { // 81cc18
    _ = k;
    Dung_TagRoutine_Func2(14);
}

pub export fn Dung_TagRoutine_0x3A(k: c_int) callconv(.c) void { // 81cc1c
    _ = k;
    Dung_TagRoutine_Func2(16);
}

pub export fn Dung_TagRoutine_Func2(av_: u8) callconv(.c) void { // 81cc1e
    var av = av_;
    var yv: u8 = undefined;
    if (v.dung_overlay_to_load.* == 0)
        v.dung_overlay_to_load.* = av;

    if (RoomTag_CheckForPressedSwitch(&yv) and blk: {
        av +%= yv;
        break :blk av != v.dung_overlay_to_load.*;
    }) {
        v.dung_overlay_to_load.* = av;
        v.dung_load_ptr_offs.* = 0;
        v.subsubmodule_index.* = 0;
        v.sound_effect_2.* = 27;
        v.submodule_index.* = 3;
        v.byte_7E04BC.* ^= 1;
        c.Dungeon_RestoreStarTileChr();
    }
}

pub export fn RoomTag_ChestHoles0(k: c_int) callconv(.c) void { // 81cc5b
    c.Dung_TagRoutine_0x22_0x3B(k, 0x0);
}

pub export fn Dung_TagRoutine_0x3B(k: c_int) callconv(.c) void { // 81cc62
    c.Dung_TagRoutine_0x22_0x3B(k, 0x12);
}

pub export fn RoomTag_Holes2(k: c_int) callconv(.c) void { // 81cc89
    var yv: u8 = undefined;

    if (!RoomTag_CheckForPressedSwitch(&yv))
        return;

    v.dung_hdr_tag[index(k)] = 0;
    v.dung_overlay_to_load.* = 5;
    v.dung_load_ptr_offs.* = 0;
    v.subsubmodule_index.* = 0;
    v.sound_effect_2.* = 0x1b;
    v.submodule_index.* = 3;
}

pub export fn RoomTag_OperateWaterFlooring() callconv(.c) void { // 81cc95
    v.dung_load_ptr_offs.* = 0;
    var layoutsrc: [*]const u8 = &t.kWatergateLayout;
    while (true) {
        v.dung_draw_width_indicator.* = 0;
        v.dung_draw_height_indicator.* = 0;
        const tw: u16 = @as(*align(1) const u16, @ptrCast(layoutsrc)).*;
        if (tw == 0xffff)
            break;
        v.dung_draw_width_indicator.* = (tw & 3) + 1;
        v.dung_draw_height_indicator.* = (tw >> 8 & 3) + 1;
        v.dung_load_ptr_offs.* +%= 3;
        layoutsrc += 3;
        const src = SrcPtr(0x110);
        var dsto2: c_int = @intCast((tw & 0xfc) >> 2 | (tw >> 10) << 6);
        while (true) {
            var dsto: c_int = dsto2;
            var n: c_int = @intCast(v.dung_draw_width_indicator.*);
            while (true) {
                var nn: c_int = 2;
                while (true) {
                    v.dung_bg1[index(dsto + xy_p3(0, 0))] = src[0];
                    v.dung_bg1[index(dsto + xy_p3(1, 0))] = src[1];
                    v.dung_bg1[index(dsto + xy_p3(2, 0))] = src[2];
                    v.dung_bg1[index(dsto + xy_p3(3, 0))] = src[3];
                    v.dung_bg1[index(dsto + xy_p3(0, 1))] = src[4];
                    v.dung_bg1[index(dsto + xy_p3(1, 1))] = src[5];
                    v.dung_bg1[index(dsto + xy_p3(2, 1))] = src[6];
                    v.dung_bg1[index(dsto + xy_p3(3, 1))] = src[7];
                    dsto += xy_p3(0, 2);
                    nn -= 1;
                    if (nn == 0) break;
                }
                dsto += xy_p3(4, -4);
                n -= 1;
                if (n == 0) break;
            }
            dsto2 += xy_p3(0, 4);
            v.dung_draw_height_indicator.* -%= 1;
            if (v.dung_draw_height_indicator.* == 0) break;
        }
    }
}

pub export fn RoomTag_MaybeCheckShutters(attr_out: *u8) callconv(.c) bool { // 81cd39
    var p: c_int = undefined;
    var tt: c_int = undefined;
    v.word_7E04B6.* = 0;
    if (v.flag_is_link_immobilized.* != 0 or v.link_auxiliary_state.* != 0)
        return false;
    p = RoomTag_GetTilemapCoords();
    done: {
        tt = attr2w(p).*;
        if (tt == 0x2323 or tt == 0x2424) break :done;
        p += 64;
        tt = attr2w(p).*;
        if (tt == 0x2323 or tt == 0x2424) break :done;
        p -= 63;
        tt = attr2w(p).*;
        if (tt == 0x2323 or tt == 0x2424) break :done;
        p += 64;
        tt = attr2w(p).*;
        if (tt == 0x2323 or tt == 0x2424) break :done;
        return false;
    }
    // done:
    if (tt != attr2w(p + 64).*)
        return false;
    attr_out.* = u8w(tt);
    v.word_7E04B6.* = u16w(p);
    return true;
}

pub export fn RoomTag_GetTilemapCoords() callconv(.c) c_int { // 81cda5
    return ((@as(c_int, v.link_x_coord.*) - 1) & 0x1f8) >> 3 | ((@as(c_int, v.link_y_coord.*) + 14) & 0x1f8) << 3 | (if (v.link_is_on_lower_level.* != 0) @as(c_int, 0x1000) else 0);
}

pub export fn RoomTag_CheckForPressedSwitch(y_out: *u8) callconv(.c) bool { // 81cdcc
    var p: c_int = undefined;
    var tt: c_int = undefined;
    v.word_7E04B6.* = 0;
    if (v.flag_is_link_immobilized.* != 0 or v.link_auxiliary_state.* != 0)
        return false;
    p = RoomTag_GetTilemapCoords();
    done: {
        tt = attr2w(p).*;
        if (tt == 0x2323 or tt == 0x3a3a or tt == 0x3b3b) break :done;
        p += 64;
        tt = attr2w(p).*;
        if (tt == 0x2323 or tt == 0x3a3a or tt == 0x3b3b) break :done;
        p -= 63;
        tt = attr2w(p).*;
        if (tt == 0x2323 or tt == 0x3a3a or tt == 0x3b3b) break :done;
        p += 64;
        tt = attr2w(p).*;
        if (tt == 0x2323 or tt == 0x3a3a or tt == 0x3b3b) break :done;
        return false;
    }
    // done:
    if (tt != attr2w(p + 64).*)
        return false;
    y_out.* = @intFromBool(tt == 0x3b3b);
    v.word_7E04B6.* = u16w(p);
    return true;
}

pub export fn Dungeon_ProcessTorchesAndDoors() callconv(.c) void { // 81ce70
    const kDungLinkOffs1X = [_]i16{ 0, 0, -1, 17 };
    const kDungLinkOffs1Y = [_]i16{ 7, 24, 8, 8 };
    const kDungLinkOffs1Pos = [_]u16{ 0x2, 0x2, 0x80, 0x80 };

    if ((v.frame_counter.* & 3) == 0 and v.flag_custom_spell_anim_active.* == 0) {
        for (0..16) |i| {
            if (v.dung_torch_timers[i] != 0) {
                v.dung_torch_timers[i] -%= 1;
                if (v.dung_torch_timers[i] == 0) {
                    v.byte_7E0333.* = @intCast(0xc0 + i);
                    c.Dungeon_ExtinguishTorch();
                }
            }
        }
    }

    if (v.flag_is_link_immobilized.* == 0) {
        const dir: c_int = v.link_direction_facing.* >> 1;
        var pos: c_int = ((@as(c_int, v.link_y_coord.*) + kDungLinkOffs1Y[index(dir)]) & 0x1f8) << 3;
        pos |= ((@as(c_int, v.link_x_coord.*) + kDungLinkOffs1X[index(dir)]) & 0x1f8) >> 3;
        pos |= if (v.link_is_on_lower_level.* != 0) @as(c_int, 0x1000) else 0;

        openblk: {
            notopen: {
                var hit = (v.dung_bg2_attr_table[index(pos)] & 0xf0) == 0xf0;
                if (!hit) {
                    pos += kDungLinkOffs1Pos[index(dir)];
                    hit = (v.dung_bg2_attr_table[index(pos)] & 0xf0) == 0xf0;
                }
                if (!hit) break :notopen;

                const k: c_int = v.dung_bg2_attr_table[index(pos)] & 0xf;
                v.dung_which_key_x2.* = u16w(2 * k);

                if ((v.dung_door_direction[index(k)] & 3) != dir)
                    break :notopen;

                const door_type: u8 = @truncate(v.door_type_and_slot[index(k)] & 0xfe);
                has_key_for_door: {
                    if (door_type == c.kDoorType_BreakableWall) {
                        if (v.link_is_running.* != 0 and v.link_dash_ctr.* < 63) {
                            v.dung_cur_door_pos.* = u16w(pos);

                            const db = c.AncillaAdd_DoorDebris();
                            if (db >= 0) {
                                v.door_debris_direction[index(db)] = @truncate(v.dung_door_direction[index(k)] & 3);
                                v.door_debris_x[index(db)] = v.dung_loade_bgoffs_h_copy.* +% (v.dung_door_tilemap_address[index(k)] & 0x7e) *% 4;
                                v.door_debris_y[index(db)] = v.dung_loade_bgoffs_v_copy.* +% ((v.dung_door_tilemap_address[index(k)] & 0x1f80) >> 4);
                            }
                            v.sound_effect_2.* = 27;
                            v.submodule_index.* = 9;
                            c.Sprite_RepelDash();
                            return;
                        }
                    } else if (door_type == c.kDoorType_1E) {
                        v.door_animation_step_indicator.* = 0;
                        v.dung_cur_door_pos.* = u16w(pos);
                        if (v.link_bigkey.* & rtl.kUpperBitmasks[index(v.cur_palace_index_x2.* >> 1)] != 0)
                            break :has_key_for_door;
                        if (v.big_key_door_message_triggered.* == 0) {
                            v.big_key_door_message_triggered.* = 1;
                            v.dialogue_message_index.* = 0x7a;
                            c.Main_ShowTextMessage();
                        }
                    } else if (door_type >= c.kDoorType_SmallKeyDoor and door_type < 0x2c and door_type != 0x2a and v.link_num_keys.* != 0) {
                        v.link_num_keys.* -%= 1;
                        break :has_key_for_door;
                    }
                    break :openblk;
                }
                // has_key_for_door:
                v.door_animation_step_indicator.* = 0;
                v.dung_cur_door_pos.* = u16w(pos);
                v.submodule_index.* = 4;
                const kOpenDoorPanning = [_]u8{ 0x0, 0x0, 0x80, 0x40 };
                v.sound_effect_2.* = 20 | kOpenDoorPanning[index(v.dung_door_direction[index(k)] & 3)];
                return;
            }
            // not_openable:
            v.big_key_door_message_triggered.* = 0;
        }
    }

    if (v.invisible_door_dir_and_index_x2.* & 0x80 == 0 and v.is_standing_in_doorway.* == 0 and (v.link_x_coord.* >> 8) == 0xc) {
        const dir: u8 = @truncate(v.invisible_door_dir_and_index_x2.*);
        const j: c_int = @intCast((v.invisible_door_dir_and_index_x2.* >> 8) >> 1);
        var m = v.dung_door_opened_incl_adjacent.*;
        if (dir != v.link_direction_facing.* and (dir ^ 2) == v.link_direction_facing.*)
            m |= rtl.kUpperBitmasks[index(j)]
        else
            m &= ~rtl.kUpperBitmasks[index(j)];
        if (m != v.dung_door_opened_incl_adjacent.*) {
            v.dung_door_opened_incl_adjacent.* = m;
            c.DrawEyeWatchDoor(j);
            _ = c.Dungeon_PrepOverlayDma_nextPrep(0, v.dung_door_tilemap_address[index(j)]);
            c.Dungeon_LoadToggleDoorAttr_OtherEntry(j);
            v.nmi_copy_packets_flag.* = 1;
            v.sound_effect_2.* = 21;
            return;
        }
    }

    if (v.button_mask_b_y.* & 0x80 == 0 or v.button_b_frames.* != 4)
        return;

    var pos: c_int = ((@as(c_int, v.link_y_coord.*) + @as(i8, @bitCast(v.player_oam_y_offset.*))) & 0x1f8) << 3;
    pos |= ((@as(c_int, v.link_x_coord.*) + @as(i8, @bitCast(v.player_oam_x_offset.*))) & 0x1f8) >> 3;
    var attr: u8 = undefined;
    var y: u8 = undefined;

    // #define is_6c_fx(yv,x) (y=yv, ((attr = (dung_bg2_attr_table[x] & 0xfc)) == 0x6c || (attr & 0xf0) == 0xf0))
    const is6cfx = struct {
        fn f(yv: u8, x: c_int, yp: *u8, ap: *u8) bool {
            yp.* = yv;
            ap.* = v.dung_bg2_attr_table[index(x)] & 0xfc;
            return ap.* == 0x6c or (ap.* & 0xf0) == 0xf0;
        }
    }.f;

    var ok = is6cfx(0x41, pos, &y, &attr);
    if (!ok) {
        pos += 1;
        ok = is6cfx(0x40, pos, &y, &attr);
    }
    if (!ok) {
        pos += 63;
        ok = is6cfx(1, pos, &y, &attr);
    }
    if (!ok) {
        pos += 1;
        ok = is6cfx(0, pos, &y, &attr);
    }
    if (!ok)
        return;

    var addr: c_int = undefined;

    if (attr == 0x6c) {
        if (y & 0x40 != 0) {
            pos -= 64;
            if ((v.dung_bg2_attr_table[index(pos)] & 0xfc) != 0x6c)
                pos += 64;
        }
        if (y & 1 != 0) {
            pos -= 1;
            if ((v.dung_bg2_attr_table[index(pos)] & 0xfc) != 0x6c)
                pos += 1;
        }
        attr = v.dung_bg2_attr_table[index(pos)];
        writeAttr2(pos + xy_p3(0, 0), 0x202);
        writeAttr2(pos + xy_p3(0, 1), 0x202);
        const kSrcTiles1 = [_]u16{ 0x7ea, 0x80a, 0x80a, 0x82a };
        addr = (pos - xy_p3(1, 1)) * 2;
        RoomDraw_Object_Nx4(4, SrcPtr(kSrcTiles1[attr & 3]), v.dung_bg2 + index(addr >> 1));
    } else {
        v.dung_cur_door_pos.* = u16w(pos);
        const k: c_int = attr & 0xf;

        const door_type = v.door_type_and_slot[index(k)];
        if (door_type != c.kDoorType_Slashable)
            return;
        v.sound_effect_2.* = 27;
        addr = @intCast(v.dung_door_tilemap_address[index(k)]);
        v.dung_door_opened_incl_adjacent.* |= rtl.kUpperBitmasks[index(k)];
        v.dung_door_opened.* |= rtl.kUpperBitmasks[index(k)];
        v.door_open_closed_counter.* = 0;
        v.dung_cur_door_idx.* = u16w(k * 2);
        v.dung_which_key_x2.* = u16w(k * 2);
        RoomDraw_Object_Nx4(4, SrcPtr(t.kDoorTypeSrcData[0x56 / 2]), v.dung_bg2 + index(addr >> 1));
        c.Dungeon_LoadToggleDoorAttr_OtherEntry(k);
    }

    _ = c.Dungeon_PrepOverlayDma_nextPrep(0, u16w(addr));
    v.sound_effect_1.* = 30 | c.CalculateSfxPan_Arbitrary(u8w((addr & 0x7f) * 2));
    v.nmi_copy_packets_flag.* = 1;
}

comptime {
    _ = main;
}

// ---------------------------------------------------------------------------
// from dungeon_part4.zig
// ---------------------------------------------------------------------------
/// WORD(dung_bg1_attr_table[i]) - unaligned 16-bit view into the attribute table.
/// WORD(dung_bg2_attr_table[i]) - unaligned 16-bit view into the attribute table.
/// The C indexes dung_bg2_attr_table with a possibly negative offset.

pub export fn Bomb_CheckForDestructibles(x: u16, y: u16, r14: u8) callconv(.c) void { // 81d1f4
    if (v.main_module_index.* != 7) {
        c.Overworld_BombTiles32x32(x, y);
        return;
    }
    var k: c_int = (@as(c_int, y & 0x1f8) << 3 | @as(c_int, x & 0x1f8) >> 3) - 0x82;
    var a: u8 = undefined;
    handle_62: {
        handle_f0: {
            var i: c_int = 2;
            while (i >= 0) : (i -= 1) {
                a = attr2at(k);
                if (a == 0x62) break :handle_62;
                if ((a & 0xf0) == 0xf0) break :handle_f0;

                k += 2;
                a = attr2at(k);
                if (a == 0x62) break :handle_62;
                if ((a & 0xf0) == 0xf0) break :handle_f0;

                k += 2;
                a = attr2at(k);
                if (a == 0x62) break :handle_62;
                if ((a & 0xf0) == 0xf0) break :handle_f0;

                k += 0x7c;
            }
            return;
        }
        // handle_f0:
        const j: c_int = a & 0xf;
        a = u8w(v.door_type_and_slot[index(j)] & 0xfe);
        if (a != kDoorType_BreakableWall and a != 0x2A and a != 0x2E)
            return;
        v.dung_cur_door_pos.* = u16w(k);
        v.door_debris_x[r14] = ((v.dung_door_tilemap_address[index(j)] & 0x7e) << 2) +% v.dung_loade_bgoffs_h_copy.*;
        v.door_debris_y[r14] = ((v.dung_door_tilemap_address[index(j)] & 0x1f80) >> 4) +% v.dung_loade_bgoffs_v_copy.*;
        v.door_debris_direction[r14] = u8w(v.dung_door_direction[index(j)] & 3);
        v.sound_effect_2.* = 0x1b;
        v.submodule_index.* = 9;
        return;
    }
    // handle_62:
    if (v.dungeon_room_index.* == 0x65)
        v.dung_savegame_state_bits.* |= 0x1000;
    var pt: Point16U = undefined;
    _ = printf("Wtf is R6\n");
    _ = ThievesAttic_DrawLightenedHole(0, 0, &pt);
    v.sound_effect_2.* = 0x1b;
    return;
}

pub export fn DrawDoorOpening_Step1(door: c_int, dma_ptr: c_int) callconv(.c) c_int { // 81d2e8
    v.dung_cur_door_idx.* = u16w(door * 2);
    v.dung_which_key_x2.* = u16w(door * 2);
    switch (v.dung_door_direction[index(door)] & 3) {
        0 => return c.DoorDoorStep1_North(door, dma_ptr),
        1 => return c.DoorDoorStep1_South(door, dma_ptr),
        2 => return c.DoorDoorStep1_West(door, dma_ptr),
        3 => return c.DoorDoorStep1_East(door, dma_ptr),
        else => {},
    }
    return 0;
}

pub export fn DrawShutterDoorSteps(door: c_int) callconv(.c) void { // 81d311
    v.dung_cur_door_idx.* = u16w(door * 2);
    v.dung_which_key_x2.* = u16w(door * 2);
    switch (v.dung_door_direction[index(door)] & 3) {
        0 => c.GetDoorDrawDataIndex_North_clean_door_index(door),
        1 => c.GetDoorDrawDataIndex_South_clean_door_index(door),
        2 => c.GetDoorDrawDataIndex_West_clean_door_index(door),
        3 => c.GetDoorDrawDataIndex_East_clean_door_index(door),
        else => {},
    }
}

pub export fn DrawEyeWatchDoor(door: c_int) callconv(.c) void { // 81d33a
    v.dung_cur_door_idx.* = u16w(door * 2);
    v.dung_which_key_x2.* = u16w(door * 2);
    switch (v.dung_door_direction[index(door)] & 3) {
        0 => c.DrawDoorToTileMap_North(door, door),
        1 => c.DrawDoorToTileMap_South(door, door),
        2 => c.DrawDoorToTileMap_West(door, door),
        3 => c.DrawDoorToTileMap_East(door, door),
        else => {},
    }
}

pub export fn Door_BlastWallExploding_Draw(dsto: c_int) callconv(.c) void { // 81d373
    var dst: Words = v.dung_bg2 + index(dsto);
    const src = SrcPtr(0x31ea);
    ClearExplodingWallFromTileMap_ClearOnePair(dst, src);
    dst += 2;
    const val = src[24];
    var n: c_int = @as(c_int, v.dung_unk_blast_walls_2.*) - 1;
    while (n != 0) : (n -= 1) {
        var j: c_int = 0;
        while (j < 12) : (j += 1)
            dst[index(xy_p4(0, j))] = val;
        dst += 1;
    }
    ClearExplodingWallFromTileMap_ClearOnePair(dst, src + 25);
}

pub export fn OperateShutterDoors() callconv(.c) void { // 81d38f
    var anim_dst: c_int = 0;
    var y: u8 = 2;

    getout: {
        v.door_animation_step_indicator.* +%= 1;
        if (v.door_animation_step_indicator.* != 4) {
            y = if (v.dung_flag_trapdoors_down.* != 0) 0 else 4;
            if (v.door_animation_step_indicator.* != 8)
                break :getout;
        }
        v.door_open_closed_counter.* = y;

        v.dung_cur_door_pos.* = 0;
        while (v.dung_cur_door_pos.* != 0x18) : (v.dung_cur_door_pos.* +%= 2) {
            const j: c_int = v.dung_cur_door_pos.* >> 1;
            const door_type = u8w(v.door_type_and_slot[index(j)] & 0xfe);
            if (door_type != kDoorType_Shutter and door_type != kDoorType_ShuttersTwoWay)
                continue;

            const mask: c_int = rtl.kUpperBitmasks[index(j)];
            if (v.dung_flag_trapdoors_down.* == 0) {
                if ((v.dung_door_opened_incl_adjacent.* & u16w(mask)) != 0)
                    continue;
                if (v.door_animation_step_indicator.* == 8) {
                    v.sound_effect_2.* = 21;
                    v.dung_door_opened_incl_adjacent.* ^= u16w(mask);
                }
            } else {
                if (!((v.dung_door_opened_incl_adjacent.* & u16w(mask)) != 0))
                    continue;
                if (v.door_animation_step_indicator.* == 8) {
                    v.sound_effect_2.* = 22;
                    v.dung_door_opened_incl_adjacent.* ^= u16w(mask);
                }
            }
            DrawShutterDoorSteps(j);
            anim_dst = c.Dungeon_PrepOverlayDma_nextPrep(anim_dst, v.dung_door_tilemap_address[index(j)]);
            if (v.door_animation_step_indicator.* == 8)
                Dungeon_LoadToggleDoorAttr_OtherEntry(j);
        }
        v.dung_cur_door_pos.* -%= 2;

        if (anim_dst != 0) {
            v.nmi_copy_packets_flag.* = 1;
            v.nmi_disable_core_updates.* = 1;
            break :getout;
        }
        v.submodule_index.* = 0;
        v.nmi_copy_packets_flag.* = 0;
        return;
    }
    // getout:
    if (low(v.door_animation_step_indicator).* != 0x10)
        return;
    v.submodule_index.* = 0;
    v.nmi_copy_packets_flag.* = 0;
}

pub export fn OpenCrackedDoor() callconv(.c) void { // 81d469
    c.Dungeon_OpeningLockedDoor_Combined(true);
}

pub export fn Dungeon_LoadToggleDoorAttr_OtherEntry(door: c_int) callconv(.c) void { // 81d51c
    c.Dungeon_LoadSingleDoorAttribute(door);
    Dungeon_LoadSingleDoorTileAttribute();
}

pub export fn Dungeon_LoadSingleDoorTileAttribute() callconv(.c) void { // 81d51f
    var i: c_int = 0;
    while (i != v.dung_num_toggle_floor.*) : (i += 2) {
        const j: c_int = v.dung_toggle_floor_pos[index(i >> 1)];
        if ((v.dung_bg2_attr_table[index(j)] & 0xf0) == 0x80) {
            const attr = attr2w(j).*;
            writeAttr2(j + xy_p4(0, 0), attr | 0x1010);
            writeAttr2(j + xy_p4(0, 1), attr | 0x1010);
        } else {
            const attr = attr1w(j).*;
            writeAttr1(j + xy_p4(0, 0), attr | 0x1010);
            writeAttr1(j + xy_p4(0, 1), attr | 0x1010);
        }
    }
    i = 0;
    while (i != v.dung_num_toggle_palace.*) : (i += 2) {
        const j: c_int = v.dung_toggle_palace_pos[index(i >> 1)];
        if ((v.dung_bg2_attr_table[index(j)] & 0xf0) == 0x80) {
            const attr = attr2w(j).*;
            writeAttr2(j + xy_p4(0, 0), attr | 0x2020);
            writeAttr2(j + xy_p4(0, 1), attr | 0x2020);
        } else {
            const attr = attr1w(j).*;
            writeAttr1(j + xy_p4(0, 0), attr | 0x2020);
            writeAttr1(j + xy_p4(0, 1), attr | 0x2020);
        }
    }
}

pub export fn DrawCompletelyOpenDoor() callconv(.c) void { // 81d5aa
    var tt: u16 = undefined;
    var i: c_int = undefined;

    i = 0;
    tt = 0x3030;
    while (i != v.dung_num_inter_room_upnorth_stairs.*) : ({
        i += 2;
        tt +%= 0x101;
    }) {}

    while (i != v.dung_num_wall_upnorth_spiral_stairs.*) : ({
        i += 2;
        tt +%= 0x101;
    }) {
        const pos: c_int = v.dung_inter_starcases[index(i >> 1)];
        writeAttr2(pos + xy_p4(1, 0), 0x5e5e);
        writeAttr2(pos + xy_p4(1, 1), tt);
        writeAttr2(pos + xy_p4(1, 2), 0);
        writeAttr2(pos + xy_p4(1, 3), 0);
    }

    while (i != v.dung_num_wall_upnorth_spiral_stairs_2.*) : ({
        i += 2;
        tt +%= 0x101;
    }) {
        const pos: c_int = v.dung_inter_starcases[index(i >> 1)];
        writeAttr2(pos + xy_p4(1, 0), 0x5f5f);
        writeAttr2(pos + xy_p4(1, 1), tt);
        writeAttr2(pos + xy_p4(1, 2), 0);
        writeAttr2(pos + xy_p4(1, 3), 0);
    }

    while (i != v.dung_num_inter_room_upnorth_straight_stairs.*) : ({
        i += 2;
        tt +%= 0x101;
    }) {}
    while (i != v.dung_num_inter_room_upsouth_straight_stairs.*) : ({
        i += 2;
        tt +%= 0x101;
    }) {}

    tt = (tt & 0x707) | 0x3434;

    while (i != v.dung_num_inter_room_southdown_stairs.*) : ({
        i += 2;
        tt +%= 0x101;
    }) {}

    while (i != v.dung_num_wall_downnorth_spiral_stairs.*) : ({
        i += 2;
        tt +%= 0x101;
    }) {
        const pos: c_int = v.dung_inter_starcases[index(i >> 1)];
        writeAttr2(pos + xy_p4(1, 0), 0x5e5e);
        writeAttr2(pos + xy_p4(1, 1), tt);
        writeAttr2(pos + xy_p4(1, 2), 0);
        writeAttr2(pos + xy_p4(1, 3), 0);
    }

    while (i != v.dung_num_wall_downnorth_spiral_stairs_2.*) : ({
        i += 2;
        tt +%= 0x101;
    }) {
        const pos: c_int = v.dung_inter_starcases[index(i >> 1)];
        writeAttr2(pos + xy_p4(1, 0), 0x5f5f);
        writeAttr2(pos + xy_p4(1, 1), tt);
        writeAttr2(pos + xy_p4(1, 2), 0);
        writeAttr2(pos + xy_p4(1, 3), 0);
    }
}

pub export fn Dungeon_ClearAwayExplodingWall() callconv(.c) void { // 81d6c1
    v.flag_is_link_immobilized.* = 6;
    v.flag_unk1.* = 6;
    if (low(&v.messaging_buf[0]).* != 6)
        return;

    v.word_7E045E.* = 0;
    v.g_ram[12] = 0;
    v.door_animation_step_indicator.* = 0;
    v.dung_cur_door_idx.* = v.dung_unk_blast_walls_3.*;
    v.dung_door_tilemap_address[index(v.dung_unk_blast_walls_3.* >> 1)] -%= 2;
    const dsto: c_int = v.dung_door_tilemap_address[index(v.dung_unk_blast_walls_3.* >> 1)] >> 1;

    Door_BlastWallExploding_Draw(dsto);
    ClearAndStripeExplodingWall(u16w(dsto));

    word(v.nmi_disable_core_updates).* = 0xffff;
    v.dung_unk_blast_walls_2.* +%= 2;

    if (v.dung_unk_blast_walls_2.* == 21) {
        const m = rtl.kUpperBitmasks[index(v.dung_unk_blast_walls_3.* >> 1)];
        v.dung_door_opened_incl_adjacent.* |= m;
        v.dung_door_opened.* |= m;

        if ((v.dung_door_direction[index(v.dung_unk_blast_walls_3.* >> 1)] & 2) != 0) {
            v.dung_blastwall_flag_x.* = 1;
            v.quadrant_fullsize_x.* = 2;
        } else {
            v.dung_blastwall_flag_y.* = 1;
            v.quadrant_fullsize_y.* = 2;
        }
        word(v.quadrant_fullsize_x_cached).* = word(v.quadrant_fullsize_x).*;
        c.Door_LoadBlastWallAttr(v.dung_unk_blast_walls_3.* >> 1);
        v.dung_unk_blast_walls_2.* = 0;
        v.dung_unk_blast_walls_3.* = 0;
        c.Dungeon_FlagRoomData_Quadrants();
        v.flag_is_link_immobilized.* = 0;
        v.flag_unk1.* = 0;
    }
    v.nmi_copy_packets_flag.* = 3;
}

pub export fn Dungeon_CheckForAndIDLiftableTile() callconv(.c) u16 { // 81d748
    const x = (v.link_x_coord.* +% u16w(t.kDungeon_QueryIfTileLiftable_x[index(v.link_direction_facing.* >> 1)])) & 0x1f8;
    const y = (v.link_y_coord.* +% u16w(t.kDungeon_QueryIfTileLiftable_y[index(v.link_direction_facing.* >> 1)])) & 0x1f8;
    const pos = (y << 3) | (x >> 3) | @as(u16, if (v.link_is_on_lower_level.* != 0) 0x1000 else 0x0);

    const attr = v.dung_bg2_attr_table[index(pos)];
    if ((attr & 0xf0) != 0x70)
        return 0xffff; // clc

    const rt = v.dung_replacement_tile_state[index(attr & 0xf)];
    if (rt == 0)
        return 0xffff;
    if ((rt & 0xf0f0) == 0x2020)
        return 0x55;
    return t.kDungeon_QueryIfTileLiftable_rv[index(rt & 0xf)];
}

pub export fn Dungeon_PushBlock_Handler() callconv(.c) void { // 81d81b
    while (v.dung_misc_objs_index.* != v.dung_index_of_torches_start.*) {
        const k: c_int = v.dung_misc_objs_index.* >> 1;
        const st: c_int = v.dung_replacement_tile_state[index(k)];
        if (st == 1) {
            RoomDraw_16x16Single(u8w(k * 2));
            v.dung_object_tilemap_pos[index(k)] +%= u16w(t.kPushBlockMoveDistances[index(v.push_block_direction.* >> 1)]);
            v.dung_replacement_tile_state[index(k)] = 2;
        } else if (st == 2) {
            c.PushBlock_Slide(u8w(k * 2));

            if (v.dung_replacement_tile_state[index(v.dung_misc_objs_index.* >> 1)] == 3) {
                PushBlock_CheckForPit(u8w(v.dung_misc_objs_index.*));
                v.dung_replacement_tile_state[index(v.dung_misc_objs_index.* >> 1)] +%= 1;
            }
        } else if (st == 4) {
            c.PushBlock_HandleFalling(u8w(k * 2));
        }

        v.dung_misc_objs_index.* +%= 2;
    }
}

pub export fn RoomDraw_16x16Single(index_: u8) callconv(.c) void { // 81d828
    const i = index_ >> 1;
    const pos = (v.dung_object_tilemap_pos[i] & 0x3fff) >> 1;
    c.Dungeon_Store2x2(
        pos,
        v.replacement_tilemap_UL[i],
        v.replacement_tilemap_LL[i],
        v.replacement_tilemap_UR[i],
        v.replacement_tilemap_LR[i],
        v.attributes_for_tile[index(v.replacement_tilemap_LR[i] & 0x3ff)],
    );
}

pub export fn PushBlock_CheckForPit(y_: u8) callconv(.c) void { // 81d8d4
    const y = y_ >> 1;
    if (!((v.dung_object_tilemap_pos[y] & 0x4000) != 0))
        v.dung_flag_movable_block_was_pushed.* ^= 1;

    const p: c_int = (v.dung_object_tilemap_pos[y] & 0x3fff) >> 1;
    const attr = v.dung_bg2_attr_table[index(p)];
    if (attr == 0x20) { // fall into pit
        v.sound_effect_1.* = 0x20;
        const k: c_int = v.dung_object_pos_in_objdata[y] >> 2;
        v.movable_block_datas[index(k)].room = v.dung_hdr_travel_destinations[0];
        v.movable_block_datas[index(k)].tilemap = v.dung_object_tilemap_pos[y];
        return;
    }

    const i: c_int = @intFromBool((@as(c_int, v.index_of_changable_dungeon_objs[1]) - 1) == @as(c_int, y));
    v.index_of_changable_dungeon_objs[index(i)] = 0;

    if (attr == 0x23) {
        v.related_to_trapdoors_somehow.* = v.dung_flag_trapdoors_down.* ^ 1;
        v.dung_replacement_tile_state[y] = 4;
    } else {
        v.dung_replacement_tile_state[y] = 0xffff;
    }
    c.Dungeon_Store2x2(u16w(p), 0x922, 0x932, 0x923, 0x933, 0x27);
}

pub export fn Dungeon_LiftAndReplaceLiftable(pt: *Point16U) callconv(.c) u8 { // 81d9ec
    var x = v.link_x_coord.* +% u16w(t.kDungeon_QueryIfTileLiftable_x[index(v.link_direction_facing.* >> 1)]);
    var y = v.link_y_coord.* +% u16w(t.kDungeon_QueryIfTileLiftable_y[index(v.link_direction_facing.* >> 1)]);
    pt.x = x;
    pt.y = y;

    v.R16.* = y;
    v.R18.* = x;

    x &= 0x1f8;
    y &= 0x1f8;
    const pos = (y << 3) | (x >> 3) | @as(u16, if (v.link_is_on_lower_level.* != 0) 0x1000 else 0x0);

    const attr0 = v.dung_bg2_attr_table[index(pos)];

    std.debug.assert((attr0 & 0x70) == 0x70);

    const attr = attr0 & 0xf;
    const rt = v.dung_replacement_tile_state[attr];

    if ((rt & 0xf0f0) == 0x1010) {
        v.dung_misc_objs_index.* = @as(u16, attr) *% 2;
        RevealPotItem(pos, v.dung_object_tilemap_pos[attr]);
        RoomDraw_16x16Single(u8w(v.dung_misc_objs_index.*));
        ManipBlock_Something(pt);
        return u8w(t.kDungeon_QueryIfTileLiftable_rv[index(rt & 0xf)]);
    } else if ((rt & 0xf0f0) == 0x2020) {
        return ThievesAttic_DrawLightenedHole(pos, (@as(u16, attr) -% (rt & 0xf)) *% 2, pt);
    } else {
        return 0;
    }
    return 0;
}

pub export fn ThievesAttic_DrawLightenedHole(pos6: u16, a: u16, pt: *Point16U) callconv(.c) u8 { // 81da71
    v.dung_misc_objs_index.* = a;
    RevealPotItem(pos6, v.dung_object_tilemap_pos[index(a >> 1)]);
    RoomDraw_16x16Single(u8w(a));
    RoomDraw_16x16Single(u8w(a +% 2));
    RoomDraw_16x16Single(u8w(a +% 4));
    RoomDraw_16x16Single(u8w(a +% 6));
    ManipBlock_Something(pt);
    return 0x55;
}

pub export fn HandleItemTileAction_Dungeon(x: u16, y: u16) callconv(.c) u8 { // 81dabb
    if (!((v.link_item_in_hand.* & 2) != 0)) {
        if (!((features.enhanced_features0.* & features.kFeatures0_BreakPotsWithSword) != 0) or
            v.button_b_frames.* == 0 or v.link_sword_type.* == 1)
            return 0;
    }
    const pos = (y & 0x1f8) *% 8 +% x +% @as(u16, if (v.link_is_on_lower_level.* != 0) 0x1000 else 0);
    const tile: u16 = v.dung_bg2_attr_table[index(pos)];
    if ((tile & 0xf0) == 0x70) {
        const tile2 = v.dung_replacement_tile_state[index(tile & 0xf)];
        if ((tile2 & 0xf0f0) == 0x4040) { // Hammer peg
            if (!((v.link_item_in_hand.* & 2) != 0))
                return 0; // only hammers on pegs
            v.dung_misc_objs_index.* = (tile & 0xf) *% 2;
            RoomDraw_16x16Single(u8w(v.dung_misc_objs_index.*));
            v.sound_effect_1.* = 0x11;
        } else if ((tile2 & 0xf0f0) == 0x1010) { // Pot
            v.dung_misc_objs_index.* = (tile & 0xf) *% 2;
            RevealPotItem(pos, v.dung_object_tilemap_pos[index(tile & 0xf)]);
            RoomDraw_16x16Single(u8w(v.dung_misc_objs_index.*));
            var pt: Point16U = undefined;
            ManipBlock_Something(&pt);
            low(v.dung_secrets_unk1).* |= 0x80;
            c.Sprite_SpawnImmediatelySmashedTerrain(1, pt.x, pt.y);
            c.AncillaAdd_BushPoof(pt.x, pt.y); // return value wtf?
        }
    }
    return 0;
}

pub export fn ManipBlock_Something(pt: *Point16U) callconv(.c) void { // 81db41
    const pos = v.dung_object_tilemap_pos[index(v.dung_misc_objs_index.* >> 1)];
    pt.x = (v.link_x_coord.* & 0xfe00) | ((pos & 0x007e) << 2);
    pt.y = (v.link_y_coord.* & 0xfe00) | ((pos & 0x1f80) >> 4);
}

pub export fn RevealPotItem(pos6: u16, pos4: u16) callconv(.c) void { // 81e6b2
    low(v.dung_secrets_unk1).* = 0;

    const kDungeonSecrets = asset8(50);
    var src_ptr: [*]const u8 = kDungeonSecrets + readWord(kDungeonSecrets + index(@as(c_int, v.dungeon_room_index.*) * 2));

    var idx: c_int = 0;
    while (true) {
        const test_pos = readWord(src_ptr);
        if (test_pos == 0xffff)
            return;
        std.debug.assert(!((test_pos & 0x8000) != 0));
        if (test_pos == pos4)
            break;
        src_ptr += 3;
        idx += 1;
    }

    const data = src_ptr[2];
    if (data == 0)
        return;

    if (data < 0x80) {
        if (data != 8) {
            const mask: u16 = @truncate(@as(u32, 1) << @truncate(@as(u32, @bitCast(idx)) & 31));
            const pr = &v.pots_revealed_in_room[index(v.dungeon_room_index.*)];
            if ((pr.* & mask) != 0)
                return;
            pr.* |= mask;
        }
        low(v.dung_secrets_unk1).* |= data;
    } else if (data != 0x88) {
        const j: c_int = v.dung_bg2_attr_table[index(pos6)] & 0xf;
        var k: c_int = j - @as(c_int, v.dung_replacement_tile_state[index(j)] & 0xf);
        v.dung_misc_objs_index.* = u16w(2 * k);
        v.sound_effect_2.* = 0x1b;
        var src = SrcPtr(0x5ba);
        var i: c_int = 0;
        while (i < 4) : ({
            i += 1;
            k += 1;
            src += 4;
        }) {
            v.replacement_tilemap_UL[index(k)] = src[0];
            v.replacement_tilemap_LL[index(k)] = src[1];
            v.replacement_tilemap_UR[index(k)] = src[2];
            v.replacement_tilemap_LR[index(k)] = src[3];
        }
    } else {
        const k: c_int = v.dung_misc_objs_index.* >> 1;
        v.replacement_tilemap_UL[index(k)] = 0xD0B;
        v.replacement_tilemap_LL[index(k)] = 0xD1B;
        v.replacement_tilemap_UR[index(k)] = 0x4D0B;
        v.replacement_tilemap_LR[index(k)] = 0x4D1B;
    }
}

pub export fn Dungeon_UpdateTileMapWithCommonTile(x: c_int, y: c_int, val: u8) callconv(.c) void { // 81e7a9
    if (val == 8)
        Dungeon_PrepSpriteInducedDma(x + 16, y, val +% 2);
    Dungeon_PrepSpriteInducedDma(x, y, val);
    v.nmi_load_bg_from_vram.* = 1;
}

pub export fn Dungeon_PrepSpriteInducedDma(x: c_int, y: c_int, val: u8) callconv(.c) void { // 81e7df
    const kPrepSpriteInducedDma_Srcs = [10]u16{ 0xe0, 0xade, 0x5aa, 0x198, 0x210, 0x218, 0x1f3a, 0xeaa, 0xeb2, 0x140 };
    const pos: c_int = ((y + 1) & 0x1f8) << 3 | (x & 0x1f8) >> 3;
    const src = SrcPtr(kPrepSpriteInducedDma_Srcs[index(val >> 1)]);
    const dst = vramDst();
    dst[0] = c.Dungeon_MapVramAddr(u16w(pos + 0));
    dst[3] = c.Dungeon_MapVramAddr(u16w(pos + 64));
    dst[6] = c.Dungeon_MapVramAddr(u16w(pos + 1));
    dst[9] = c.Dungeon_MapVramAddr(u16w(pos + 65));
    const attr = v.attributes_for_tile[index(src[3] & 0x3ff)];
    v.dung_bg2_attr_table[index(pos + xy_p4(0, 0))] = attr;
    v.dung_bg2_attr_table[index(pos + xy_p4(0, 1))] = attr;
    v.dung_bg2_attr_table[index(pos + xy_p4(1, 0))] = attr;
    v.dung_bg2_attr_table[index(pos + xy_p4(1, 1))] = attr;
    dst[2] = src[0];
    v.dung_bg2[index(pos + xy_p4(0, 0))] = dst[2];
    dst[5] = src[1];
    v.dung_bg2[index(pos + xy_p4(0, 1))] = dst[5];
    dst[8] = src[2];
    v.dung_bg2[index(pos + xy_p4(1, 0))] = dst[8];
    dst[11] = src[3];
    v.dung_bg2[index(pos + xy_p4(1, 1))] = dst[11];
    dst[1] = 0x100;
    dst[4] = 0x100;
    dst[7] = 0x100;
    dst[10] = 0x100;
    dst[12] = 0xffff;
    v.vram_upload_offset.* +%= 24;
}

pub export fn Dungeon_DeleteRupeeTile(x: u16, y: u16) callconv(.c) void { // 81e8bd
    const pos: c_int = @as(c_int, y & 0x1f8) * 8 | @as(c_int, x & 0x1f8) >> 3;
    const dst = vramDst();
    dst[2] = 0x190f;
    dst[5] = 0x190f;
    v.dung_bg2[index(pos + xy_p4(0, 0))] = 0x190f;
    v.dung_bg2[index(pos + xy_p4(0, 1))] = 0x190f;
    const attr = @as(u16, v.attributes_for_tile[0x190f & 0x3ff]) *% 0x101;
    attr2w(pos + xy_p4(0, 0)).* = attr;
    attr2w(pos + xy_p4(0, 1)).* = attr;
    dst[0] = c.Dungeon_MapVramAddr(u16w(pos + xy_p4(0, 0)));
    dst[3] = c.Dungeon_MapVramAddr(u16w(pos + xy_p4(0, 1)));
    dst[1] = 0x100;
    dst[4] = 0x100;
    dst[6] = 0xffff;
    v.vram_upload_offset.* +%= 24;
    v.dung_savegame_state_bits.* |= 0x1000;
    v.nmi_load_bg_from_vram.* = 1;
}

// This doesn't return exactly like the original
// Also returns in scratch_0
pub export fn OpenChestForItem(tile: u8, chest_position: *c_int) callconv(.c) u8 { // 81eb66
    const kChestOpenMasks = [_]u16{ 0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000 };
    if (tile == 0x63)
        return OpenMiniGameChest(chest_position);

    var chest_idx: c_int = @as(c_int, tile) - 0x58;
    const chest_idx_org: c_int = chest_idx;

    const loc = v.dung_chest_locations[index(chest_idx)];
    var pos: u16 = undefined;
    var chest_room: u16 = undefined;
    var data: u8 = 0xff;
    var ptr: Tiles = undefined;

    afterStoreCrap: {
        if (loc >= 0x8000) {
            // big key lock
            if (!((v.link_bigkey.* & rtl.kUpperBitmasks[index(v.cur_palace_index_x2.* >> 1)]) != 0)) {
                v.dialogue_message_index.* = 0x7a;
                c.Main_ShowTextMessage();
                return 0xff;
            } else {
                v.dung_savegame_state_bits.* |= kChestOpenMasks[index(chest_idx)];
                v.sound_effect_1.* = 0x29;
                v.sound_effect_2.* = 0x15;
                pos = (loc & 0x7fff) >> 1;

                ptr = SrcPtr(v.dung_floor_2_filler_tiles.*);
                v.overworld_tileattr[index(pos) + 0] = ptr[0];
                v.overworld_tileattr[index(pos) + 64] = ptr[1];
                v.overworld_tileattr[index(pos) + 1] = ptr[2];
                v.overworld_tileattr[index(pos) + 65] = ptr[3];
                break :afterStoreCrap;
            }
        } else {
            var chest_data: [*]const u8 = asset8(8);
            var i: c_int = 0;
            while (i < @as(c_int, @intCast(main.g_asset_sizes[8]))) : ({
                i += 3;
                chest_data += 3;
            }) {
                chest_room = readWord(chest_data);
                if ((chest_room & 0x7fff) == v.dungeon_room_index.* and blk: {
                    chest_idx -= 1;
                    break :blk chest_idx < 0;
                }) {
                    data = chest_data[2];
                    if ((chest_room & 0x8000) != 0) {
                        if (!((v.link_bigkey.* & rtl.kUpperBitmasks[index(v.cur_palace_index_x2.* >> 1)]) != 0)) {
                            v.dialogue_message_index.* = 0x7a;
                            c.Main_ShowTextMessage();
                            return 0xff;
                        }
                        v.dung_savegame_state_bits.* |= kChestOpenMasks[index(chest_idx_org)];
                        OpenBigChest(loc, chest_position);
                        return data;
                    } else {
                        v.dung_savegame_state_bits.* |= kChestOpenMasks[index(chest_idx_org)];
                        ptr = SrcPtr(0x14A4);
                        pos = loc >> 1;

                        v.overworld_tileattr[index(pos) + 0] = ptr[0];
                        v.overworld_tileattr[index(pos) + 64] = ptr[1];
                        v.overworld_tileattr[index(pos) + 1] = ptr[2];
                        v.overworld_tileattr[index(pos) + 65] = ptr[3];

                        break :afterStoreCrap;
                    }
                }
            }
            return 0xff;
        }
    }
    // afterStoreCrap:
    const attr: u8 = if (loc < 0x8000) 0x27 else 0x00;

    v.dung_bg2_attr_table[index(pos) + 0] = attr;
    v.dung_bg2_attr_table[index(pos) + 64] = attr;
    v.dung_bg2_attr_table[index(pos) + 1] = attr;
    v.dung_bg2_attr_table[index(pos) + 65] = attr;

    const dst = vramDst();
    dst[0] = c.Dungeon_MapVramAddr(pos +% 0);
    dst[3] = c.Dungeon_MapVramAddr(pos +% 64);
    dst[6] = c.Dungeon_MapVramAddr(pos +% 1);
    dst[9] = c.Dungeon_MapVramAddr(pos +% 65);

    dst[2] = ptr[0];
    dst[5] = ptr[1];
    dst[8] = ptr[2];
    dst[11] = ptr[3];

    dst[1] = 0x100;
    dst[4] = 0x100;
    dst[7] = 0x100;
    dst[10] = 0x100;

    dst[12] = 0xffff;

    v.vram_upload_offset.* +%= 24;
    v.nmi_load_bg_from_vram.* = 1;
    c.Dungeon_FlagRoomData_Quadrants();
    if (v.sound_effect_2.* == 0)
        v.sound_effect_2.* = 14;

    chest_position.* = loc & 0x7fff;
    return data;
}

pub export fn OpenBigChest(loc: u16, chest_position: *c_int) callconv(.c) void { // 81ed05
    const pos: u16 = loc >> 1;
    var src = SrcPtr(0x14C4);

    var i: c_int = 0;
    while (i < 4) : (i += 1) {
        v.dung_bg2[index(pos) + index(xy_p4(i, 0))] = src[0];
        v.dung_bg2[index(pos) + index(xy_p4(i, 1))] = src[1];
        v.dung_bg2[index(pos) + index(xy_p4(i, 2))] = src[2];
        src += 3;
    }

    _ = c.Dungeon_PrepOverlayDma_nextPrep(0, loc);
    chest_position.* = @as(c_int, loc) + 2;
    attr2w(@as(c_int, pos) + xy_p4(0, 0)).* = 0x2727;
    attr2w(@as(c_int, pos) + xy_p4(2, 0)).* = 0x2727;
    attr2w(@as(c_int, pos) + xy_p4(0, 1)).* = 0x2727;
    attr2w(@as(c_int, pos) + xy_p4(2, 1)).* = 0x2727;
    attr2w(@as(c_int, pos) + xy_p4(0, 2)).* = 0x2727;
    attr2w(@as(c_int, pos) + xy_p4(2, 2)).* = 0x2727;
    c.Dungeon_FlagRoomData_Quadrants();
    v.sound_effect_2.* = 14;
    v.nmi_copy_packets_flag.* = 1;
    v.byte_7E0B9E.* = 1;
}

pub export fn OpenMiniGameChest(chest_position: *c_int) callconv(.c) u8 { // 81edab
    var tv: c_int = undefined;
    if (v.minigame_credits.* == 0) {
        v.dialogue_message_index.* = 0x163;
        c.Main_ShowTextMessage();
        return 0xff;
    }
    if (v.minigame_credits.* == 255) {
        v.dialogue_message_index.* = 0x162;
        c.Main_ShowTextMessage();
        return 0xff;
    }
    v.minigame_credits.* -%= 1;

    var pos: c_int = @as(c_int, (v.link_y_coord.* -% 4) & 0x1f8) * 8;
    pos |= @as(c_int, (v.link_x_coord.* +% 7) & 0x1f8) >> 3;

    if (attr2w(pos).* != 0x6363) {
        pos -= 1;
        if (attr2w(pos).* != 0x6363)
            pos += 2;
    }

    chest_position.* = pos * 2;

    attr2w(pos + xy_p4(0, 0)).* = 0x202;
    attr2w(pos + xy_p4(0, 1)).* = 0x202;

    const src = SrcPtr(0x14A4);

    const pos_wrong: c_int = pos + xy_p4(0, 2); // zelda bug?
    v.dung_bg2[index(pos_wrong + xy_p4(0, 0))] = src[0];
    v.dung_bg2[index(pos_wrong + xy_p4(0, 1))] = src[1];
    v.dung_bg2[index(pos_wrong + xy_p4(1, 0))] = src[2];
    v.dung_bg2[index(pos_wrong + xy_p4(1, 1))] = src[3];

    // The orig asm code seems to access invalid vram here because it indexes by 0x14a4
    const dst = vramDst();
    dst[0] = c.Dungeon_MapVramAddr(u16w(pos + 0));
    dst[3] = c.Dungeon_MapVramAddr(u16w(pos + 64));
    dst[6] = c.Dungeon_MapVramAddr(u16w(pos + 1));
    dst[9] = c.Dungeon_MapVramAddr(u16w(pos + 65));

    dst[2] = src[0];
    dst[5] = src[1];
    dst[8] = src[2];
    dst[11] = src[3];

    dst[1] = 0x100;
    dst[4] = 0x100;
    dst[7] = 0x100;
    dst[10] = 0x100;

    dst[12] = 0xffff;

    v.vram_upload_offset.* +%= 24;

    var rv: u8 = undefined;

    const r16: u16 = v.some_menu_ctr.*;

    tv = c.GetRandomNumber();
    if (low(v.dungeon_room_index).* == 0) {
        tv = tv & 0xf;
        rv = t.kDungeon_RupeeChestMinigamePrizes[index(tv & 0xf)];
    } else if (low(v.dungeon_room_index).* == 0x18) {
        tv = 0x10 + (tv & 0xf);
        rv = t.kDungeon_RupeeChestMinigamePrizes[index(0x10 + (tv & 0xf))];
    } else {
        tv &= 7;
        if (tv >= 2 and tv == @as(c_int, r16)) {
            tv = (tv + 1) & 7;
        }
        if (tv == 7) {
            if ((v.dung_savegame_state_bits.* & 0x4000) != 0) {
                tv = 0;
            } else {
                v.dung_savegame_state_bits.* |= 0x4000;
            }
        }
        rv = t.kDungeon_MinigameChestPrizes1[index(tv)];
    }
    v.some_menu_ctr.* = u8w(tv);
    v.nmi_load_bg_from_vram.* = 1;
    v.sound_effect_2.* = 14;
    return rv;
}

pub export fn RoomTag_BuildChestStripes(pos_: u16, y: u16) callconv(.c) u16 { // 81ef0f
    const pos = pos_ +% v.dung_chest_locations[index(y >> 1)];
    return swap16(((pos & 0x40) << 4) | ((pos & 0x303f) >> 1) | ((pos & 0xf80) >> 2));
}

pub export fn Dungeon_SetAttrForActivatedWaterOff() callconv(.c) void { // 81ef93
    v.CGWSEL_copy.* = 2;
    v.CGADSUB_copy.* = 0x32;
    v.TS_copy.* = 0;
    v.W12SEL_copy.* = 0;
    v.dung_hdr_collision.* = 0;
    word(v.TMW_copy).* = 0;
    var j: c_int = 0;
    while (j != v.dung_num_inroom_upnorth_stairs_water.*) : (j += 2) {
        const dsto: c_int = v.dung_stairs_table_1[index(j >> 1)];
        writeAttr2(dsto + xy_p4(1, 1), 0x1d1d);
        writeAttr2(dsto + xy_p4(1, 2), 0x1d1d);
    }
    j = 0;
    while (j != v.dung_num_inroom_upsouth_stairs_water.*) : (j += 2) {
        const dsto: c_int = v.dung_stairs_table_2[index(j >> 1)];
        writeAttr2(dsto + xy_p4(1, 1), 0x1d1d);
        writeAttr2(dsto + xy_p4(1, 2), 0x1d1d);
    }
    v.flag_update_cgram_in_nmi.* +%= 1;
    v.subsubmodule_index.* +%= 1;
}

pub export fn Dungeon_FloodSwampWater_PrepTileMap() callconv(.c) void { // 81f046
    c.WaterFlood_BuildOneQuadrantForVRAM();
    v.dung_cur_quadrant_upload.* +%= 4;
    v.subsubmodule_index.* +%= 1;
    if (v.subsubmodule_index.* == 6) {
        v.dung_cur_quadrant_upload.* = 0;
        v.subsubmodule_index.* = 0;
        v.submodule_index.* = 0;
    }
}

pub export fn Dungeon_AdjustWaterVomit(src_: Tiles, depth_: c_int) callconv(.c) void { // 81f0c9
    var src = src_;
    var depth = depth_;
    var dsto: c_int = (v.word_7E047C.* >> 1) + xy_p4(0, 2);
    var dst: Words = v.dung_bg2 + index(dsto);
    while (true) {
        dst[0] = src[0];
        dst[1] = src[1];
        dst[2] = src[2];
        dst[3] = src[3];
        dst += index(xy_p4(0, 1));
        src += 4;
        depth -= 1;
        if (depth == 0) break;
    }
    var vram: Words = v.vram_upload_data;
    var i: c_int = 0;
    while (i < 4) : (i += 1) {
        const d: Words = v.dung_bg2 + index(dsto);
        vram[0] = c.Dungeon_MapVramAddr(u16w(dsto));
        vram[1] = 0x980;
        vram[2] = d[index(xy_p4(0, 0))];
        vram[3] = d[index(xy_p4(0, 1))];
        vram[4] = d[index(xy_p4(0, 2))];
        vram[5] = d[index(xy_p4(0, 3))];
        vram[6] = d[index(xy_p4(0, 4))];
        vram += 7;
        dsto += 1;
    }
    vram[0] = 0xffff;
    v.nmi_load_bg_from_vram.* = 1;
}

pub export fn Dungeon_SetAttrForActivatedWater() callconv(.c) void { // 81f237
    word(v.TMW_copy).* = 0;
    var j: c_int = 0;
    while (j != v.dung_num_interpseudo_upnorth_stairs.*) : (j += 2) {
        const dsto: c_int = v.dung_stairs_table_1[index(j >> 1)];
        writeAttr2(dsto + 0, 0x003);
        writeAttr2(dsto + 2, 0x300);
        writeAttr1(dsto + 0, 0xa03);
        writeAttr1(dsto + 2, 0x30a);
        writeAttr2(dsto + xy_p4(0, 1), 0x808);
        writeAttr2(dsto + xy_p4(2, 1), 0x808);
        writeAttr1(dsto + xy_p4(0, 1), 0x808);
        writeAttr1(dsto + xy_p4(2, 1), 0x808);
        writeAttr1(dsto + xy_p4(0, 2), 0x808);
        writeAttr1(dsto + xy_p4(2, 2), 0x808);
        writeAttr1(dsto + xy_p4(0, 3), 0x808);
        writeAttr1(dsto + xy_p4(2, 3), 0x808);
    }

    j = 0;
    while (j != v.dung_num_stairs_wet.*) : (j += 2) {
        const dsto: c_int = v.dung_stairs_table_2[index(j >> 1)];
        writeAttr2(dsto + xy_p4(0, 3), 0x003);
        writeAttr2(dsto + xy_p4(2, 3), 0x300);
        writeAttr1(dsto + xy_p4(0, 3), 0xa03);
        writeAttr1(dsto + xy_p4(2, 3), 0x30a);
        writeAttr2(dsto + xy_p4(0, 2), 0x808);
        writeAttr2(dsto + xy_p4(2, 2), 0x808);
        writeAttr1(dsto + xy_p4(0, 0), 0x808);
        writeAttr1(dsto + xy_p4(2, 0), 0x808);
        writeAttr1(dsto + xy_p4(0, 1), 0x808);
        writeAttr1(dsto + xy_p4(2, 1), 0x808);
        writeAttr1(dsto + xy_p4(0, 2), 0x808);
        writeAttr1(dsto + xy_p4(2, 2), 0x808);
    }
    v.submodule_index.* = 0;
    v.nmi_boolean.* = 0; // wtf
    v.subsubmodule_index.* = 0;
}

pub export fn FloodDam_Expand() callconv(.c) void { // 81f30c
    v.watergate_var1.* +%= 1;
    v.water_hdma_var3.* = v.watergate_var1.* >> 1;
    const r0: u8 = u8w(@as(c_int, v.water_hdma_var3.*) - 8);
    low(v.spotlight_y_upper).* = u8w(v.word_7E0678.*);
    low(v.spotlight_var4).* +%= 1;
    low(v.water_hdma_var2).* = u8w(@as(c_int, v.spotlight_var4.*) + @as(c_int, r0));

    if ((v.watergate_var1.* & 0xf) != 0)
        return;

    if (v.watergate_var1.* == 64)
        v.subsubmodule_index.* +%= 1;

    const kWatergateSrcs1 = [_]u16{ 0x12f8, 0x1348, 0x1398, 0x13e8 };
    RoomDraw_Object_Nx4(10, SrcPtr(kWatergateSrcs1[index(@as(c_int, v.watergate_var1.* >> 4) - 1)]), v.dung_bg2 + index(v.watergate_pos.* >> 1));
    var pos: c_int = v.watergate_pos.*;
    var n: c_int = 3;
    var dma_ptr: c_int = 0;
    while (true) {
        dma_ptr = c.Dungeon_PrepOverlayDma_watergate(dma_ptr, u16w(pos), 0x881, 4);
        pos += 6;
        n -= 1;
        if (n == 0) break;
    }
    v.nmi_copy_packets_flag.* = 1;
}

pub export fn FloodDam_PrepTiles_init() callconv(.c) void { // 81f3a7
    v.dung_cur_quadrant_upload.* = 0;
    v.overworld_screen_transition.* = 0;
    c.WaterFlood_BuildOneQuadrantForVRAM();
    v.dung_cur_quadrant_upload.* +%= 4;
    v.subsubmodule_index.* +%= 1;
}

pub export fn Watergate_Main_State1() callconv(.c) void { // 81f3aa
    v.overworld_screen_transition.* = 0;
    c.WaterFlood_BuildOneQuadrantForVRAM();
    v.dung_cur_quadrant_upload.* +%= 4;
    v.subsubmodule_index.* +%= 1;
}

pub export fn FloodDam_Fill() callconv(.c) void { // 81f3bd
    low(v.water_hdma_var2).* +%= 1;
    const tv: u8 = u8w(@as(c_int, v.water_hdma_var2.*) + @as(c_int, v.spotlight_y_upper.*));
    if (tv >= 225) {
        v.dung_cur_quadrant_upload.* = 0;
        v.submodule_index.* = 0;
        v.subsubmodule_index.* = 0;
        v.TMW_copy.* = 0;
        v.TSW_copy.* = 0;
        c.IrisSpotlight_ResetTable();
    }
}

pub export fn Ganon_ExtinguishTorch_adjust_translucency() callconv(.c) void { // 81f496
    c.Palette_AssertTranslucencySwap();
    v.byte_7E0333.* = 0xc0;
    Dungeon_ExtinguishTorch();
}

pub export fn Ganon_ExtinguishTorch() callconv(.c) void { // 81f4a1
    v.byte_7E0333.* = 193;
    Dungeon_ExtinguishTorch();
}

pub export fn Dungeon_ExtinguishTorch() callconv(.c) void { // 81f4a6
    const y: c_int = @as(c_int, v.byte_7E0333.* & 0xf) * 2 + @as(c_int, v.dung_index_of_torches_start.*);

    v.dung_object_tilemap_pos[index(y >> 1)] &= 0x7fff;
    var r8: u16 = v.dung_object_tilemap_pos[index(y >> 1)];

    v.dung_torch_data[index((v.dung_object_pos_in_objdata[index(y >> 1)] & 0xff) >> 1)] = r8;

    r8 &= 0x3fff;
    c.RoomDraw_AdjustTorchLightingChange(r8, 0xec2, r8);
    v.nmi_copy_packets_flag.* = 1;

    if (v.dung_want_lights_out.* != 0 and v.dung_num_lit_torches.* != 0 and blk: {
        v.dung_num_lit_torches.* -%= 1;
        break :blk v.dung_num_lit_torches.* < 3;
    }) {
        if (v.dung_num_lit_torches.* == 0)
            v.TS_copy.* = 1;
        v.overworld_fixed_color_plusminus.* = rtl.kLitTorchesColorPlus[v.dung_num_lit_torches.*];
        v.submodule_index.* = 10;
        v.subsubmodule_index.* = 0;
    }

    v.dung_torch_timers[index(v.byte_7E0333.* & 0xf)] = 0;
    v.byte_7E0333.* = 0;
}

pub export fn SpiralStairs_MakeNearbyWallsHighPriority_Entering() callconv(.c) void { // 81f528
    const pos: c_int = @as(c_int, v.dung_inter_starcases[index(v.which_staircase_index.* & 3)]) - 4;
    v.word_7E048C.* = u16w(pos * 2);
    var dst: Words = v.dung_bg2 + index(pos);
    var i: c_int = 0;
    while (i < 5) : (i += 1) {
        dst[index(xy_p4(0, 0))] |= 0x2000;
        dst[index(xy_p4(0, 1))] |= 0x2000;
        dst[index(xy_p4(0, 2))] |= 0x2000;
        dst[index(xy_p4(0, 3))] |= 0x2000;
        dst += 1;
    }
    const dp = c.Dungeon_PrepOverlayDma_nextPrep(0, u16w(pos * 2));
    _ = c.Dungeon_PrepOverlayDma_nextPrep(dp, u16w(pos * 2 + 8));
    v.nmi_copy_packets_flag.* = 1;
}

pub export fn SpiralStairs_MakeNearbyWallsLowPriority() callconv(.c) void { // 81f585
    const pos: c_int = v.word_7E048C.* >> 1;
    var dst: Words = v.dung_bg2 + index(pos);
    var i: c_int = 0;
    while (i < 5) : (i += 1) {
        dst[index(xy_p4(0, 0))] &= ~@as(u16, 0x2000);
        dst[index(xy_p4(0, 1))] &= ~@as(u16, 0x2000);
        dst[index(xy_p4(0, 2))] &= ~@as(u16, 0x2000);
        dst[index(xy_p4(0, 3))] &= ~@as(u16, 0x2000);
        dst += 1;
    }
    const dp = c.Dungeon_PrepOverlayDma_nextPrep(0, u16w(pos * 2));
    _ = c.Dungeon_PrepOverlayDma_nextPrep(dp, u16w(pos * 2 + 8));
    v.nmi_copy_packets_flag.* = 1;
}

pub export fn ClearAndStripeExplodingWall(dsto_: u16) callconv(.c) void { // 81f811
    const kBlastWall_Tab2 = [16]u16{ 4, 8, 0xc, 0x10, 0x14, 0x18, 0x1c, 0x20, 0x100, 0x200, 0x300, 0x400, 0x500, 0x600, 0x700, 0x800 };

    var dsto = dsto_;
    var r6: u16 = 0x80;
    var r14: u16 = 0;
    var r10: u16 = v.dung_unk_blast_walls_2.* +% 3;
    var r2: u16 = 0;

    if (!sign16(r10 -% 8)) {
        r2 = r10 -% 6;
        r14 = 1;
        r10 = 3;
    }
    if (!((v.dung_door_direction[index(v.dung_cur_door_idx.* >> 1)] & 2) != 0))
        r6 +%= 1;

    var uvdata: Words = @ptrCast(&v.uvram.data[0]);
    while (true) {
        var bg2: Words = v.dung_bg2 + index(dsto);
        while (true) {
            const vram_addr = c.Dungeon_MapVramAddrNoSwap(dsto);
            uvdata[0] = vram_addr;
            uvdata[1] = r6 | 0xa00;
            uvdata[2] = bg2[index(xy_p4(0, 0))];
            uvdata[3] = bg2[index(xy_p4(0, 1))];
            uvdata[4] = bg2[index(xy_p4(0, 2))];
            uvdata[5] = bg2[index(xy_p4(0, 3))];
            uvdata[6] = bg2[index(xy_p4(0, 4))];
            uvdata[7] = vram_addr +% 0x4a0;
            uvdata[8] = r6 | 0xe00;
            uvdata[9] = bg2[index(xy_p4(0, 5))];
            uvdata[10] = bg2[index(xy_p4(0, 6))];
            uvdata[11] = bg2[index(xy_p4(0, 7))];
            uvdata[12] = bg2[index(xy_p4(0, 8))];
            uvdata[13] = bg2[index(xy_p4(0, 9))];
            uvdata[14] = bg2[index(xy_p4(0, 10))];
            uvdata[15] = bg2[index(xy_p4(0, 11))];
            dsto +%= 1;
            bg2 += 1;
            uvdata += 16;
            r10 -%= 1;
            if (r10 == 0) break;
        }
        if (!(r14 != 0))
            break;
        r14 -%= 1;
        dsto +%= kBlastWall_Tab2[index(@as(c_int, r2 >> 1) + @as(c_int, if ((r6 & 1) != 0) 0 else 8) - 1)] >> 1;
        r10 = 3;
    }
    uvdata[0] = 0xffff;
}

pub export fn Dungeon_DrawRoomOverlay(src_: [*]const u8) callconv(.c) void { // 81f967
    var src = src_;
    while (true) {
        v.dung_draw_width_indicator.* = 0;
        v.dung_draw_height_indicator.* = 0;
        const a = readWord(src);
        if (a == 0xffff)
            break;
        const p: Words = v.dung_bg2 + index(@as(c_int, src[0] >> 2) | @as(c_int, src[1] >> 2) << 6);
        const kind = src[2];
        if (kind == 0xa4) {
            const tile = SrcPtr(0x5aa)[0];
            p[index(xy_p4(0, 1))] = tile;
            p[index(xy_p4(1, 1))] = tile;
            p[index(xy_p4(2, 1))] = tile;
            p[index(xy_p4(3, 1))] = tile;
            p[index(xy_p4(0, 2))] = tile;
            p[index(xy_p4(1, 2))] = tile;
            p[index(xy_p4(2, 2))] = tile;
            p[index(xy_p4(3, 2))] = tile;
            const top = SrcPtr(0x63c)[1];
            p[index(xy_p4(0, 0))] = top;
            p[index(xy_p4(1, 0))] = top;
            p[index(xy_p4(2, 0))] = top;
            p[index(xy_p4(3, 0))] = top;
            const bot = SrcPtr(0x642)[1];
            p[index(xy_p4(0, 3))] = bot;
            p[index(xy_p4(1, 3))] = bot;
            p[index(xy_p4(2, 3))] = bot;
            p[index(xy_p4(3, 3))] = bot;
        } else {
            const sp = SrcPtr(v.dung_floor_2_filler_tiles.*);
            p[index(xy_p4(0, 0))] = sp[0];
            p[index(xy_p4(2, 0))] = sp[0];
            p[index(xy_p4(0, 2))] = sp[0];
            p[index(xy_p4(2, 2))] = sp[0];
            p[index(xy_p4(1, 0))] = sp[1];
            p[index(xy_p4(3, 0))] = sp[1];
            p[index(xy_p4(1, 2))] = sp[1];
            p[index(xy_p4(3, 2))] = sp[1];
            p[index(xy_p4(0, 1))] = sp[4];
            p[index(xy_p4(2, 1))] = sp[4];
            p[index(xy_p4(0, 3))] = sp[4];
            p[index(xy_p4(2, 3))] = sp[4];
            p[index(xy_p4(1, 1))] = sp[5];
            p[index(xy_p4(3, 1))] = sp[5];
            p[index(xy_p4(1, 3))] = sp[5];
            p[index(xy_p4(3, 3))] = sp[5];
        }
        src += 3;
    }
}

// ---------------------------------------------------------------------------
// from dungeon_part5.zig
// ---------------------------------------------------------------------------
/// assets.h: #define kDungeonRoomOverlay ((uint8*)g_asset_ptrs[48])
/// assets.h: #define kDungeonRoomOverlayOffs ((uint16*)g_asset_ptrs[49])
/// misc.h: static inline int FindInWordArray(const uint16 *data, uint16 lookfor, size_t size)

pub export fn GetDoorDrawDataIndex_North_clean_door_index(door: c_int) callconv(.c) void { // 81fa4a
    GetDoorDrawDataIndex_North(door, door);
}

pub export fn DoorDoorStep1_North(door: c_int, dma_ptr_: c_int) callconv(.c) c_int { // 81fa54
    var dma_ptr = dma_ptr_;
    var pos: c_int = v.dung_door_tilemap_address[index(door)];
    if ((pos & 0x1fff) >= ci(t.kDoorPositionToTilemapOffs_Up[6])) {
        pos -= 0x500;
        if ((v.door_type_and_slot[index(door)] & 0xfe) >= 0x42)
            pos -= 0x300;
        GetDoorDrawDataIndex_South(door ^ 8, door & 7);
        dma_ptr = c.Dungeon_PrepOverlayDma_nextPrep(dma_ptr, u16w(pos));
        c.Dungeon_LoadSingleDoorAttribute(door ^ 8);
    }
    GetDoorDrawDataIndex_North(door, door & 7);
    return dma_ptr;
}

pub export fn GetDoorDrawDataIndex_North(door: c_int, r4_door: c_int) callconv(.c) void { // 81faa0
    const door_type: u8 = @truncate(v.door_type_and_slot[index(door)] & 0xfe);
    var x: c_int = v.door_open_closed_counter.*;
    if (x == 0 or x == 4) {
        DrawDoorToTileMap_North(door, r4_door);
        return;
    }
    x += if (ci(door_type) == c.kDoorType_StairMaskLocked2 or ci(door_type) == c.kDoorType_StairMaskLocked3 or door_type >= 0x42) @as(c_int, 4) else 0;
    x += if (ci(door_type) == c.kDoorType_ShuttersTwoWay or ci(door_type) == c.kDoorType_Shutter) @as(c_int, 2) else 0;
    //  assert(x < 8);
    Object_Draw_DoorUp_4x3(t.kDoorAnimUpSrc[index(x >> 1)], door);
}

pub export fn DrawDoorToTileMap_North(door: c_int, r4_door: c_int) callconv(.c) void { // 81fad7
    Object_Draw_DoorUp_4x3(t.kDoorTypeSrcData[index(GetDoorGraphicsIndex(door, r4_door) >> 1)], door);
}

pub export fn Object_Draw_DoorUp_4x3(src: u16, door: c_int) callconv(.c) void { // 81fae3
    var s: Tiles = SrcPtr(src);
    var dst: Words = v.dung_bg2 + index(v.dung_door_tilemap_address[index(door)] >> 1);
    for (0..4) |_| {
        dst[xy(0, 0)] = s[0];
        dst[xy(0, 1)] = s[1];
        dst[xy(0, 2)] = s[2];
        dst += 1;
        s += 3;
    }
}

pub export fn GetDoorDrawDataIndex_South_clean_door_index(door: c_int) callconv(.c) void { // 81fb0b
    GetDoorDrawDataIndex_South(door, door);
}

pub export fn DoorDoorStep1_South(door: c_int, dma_ptr_: c_int) callconv(.c) c_int { // 81fb15
    var dma_ptr = dma_ptr_;
    var pos: c_int = v.dung_door_tilemap_address[index(door)];
    if ((pos & 0x1fff) < ci(t.kDoorPositionToTilemapOffs_Down[9])) {
        pos += 0x500;
        if ((v.door_type_and_slot[index(door)] & 0xfe) >= 0x42)
            pos += 0x300;
        GetDoorDrawDataIndex_North(door ^ 8, door & 7);
        dma_ptr = c.Dungeon_PrepOverlayDma_nextPrep(dma_ptr, u16w(pos));
        c.Dungeon_LoadSingleDoorAttribute(door ^ 8);
    }
    GetDoorDrawDataIndex_South(door, door & 7);
    return dma_ptr;
}

pub export fn GetDoorDrawDataIndex_South(door: c_int, r4_door: c_int) callconv(.c) void { // 81fb61
    const door_type: u8 = @truncate(v.door_type_and_slot[index(door)] & 0xfe);
    var x: c_int = v.door_open_closed_counter.*;
    if (x == 0 or x == 4) {
        DrawDoorToTileMap_South(door, r4_door);
        return;
    }
    x += if (door_type >= 0x42) @as(c_int, 4) else 0;
    x += if (ci(door_type) == c.kDoorType_ShuttersTwoWay or ci(door_type) == c.kDoorType_Shutter) @as(c_int, 2) else 0;
    //  assert(x < 8);
    Object_Draw_DoorDown_4x3(t.kDoorAnimDownSrc[index(x >> 1)], door);
}

pub export fn DrawDoorToTileMap_South(door: c_int, r4_door: c_int) callconv(.c) void { // 81fb8e
    Object_Draw_DoorDown_4x3(t.kDoorTypeSrcData2[index(GetDoorGraphicsIndex(door, r4_door) >> 1)], door);
}

pub export fn Object_Draw_DoorDown_4x3(src: u16, door: c_int) callconv(.c) void { // 81fb9b
    var s: Tiles = SrcPtr(src);
    var dst: Words = v.dung_bg2 + index(v.dung_door_tilemap_address[index(door)] >> 1);
    for (0..4) |_| {
        dst[xy(0, 1)] = s[0];
        dst[xy(0, 2)] = s[1];
        dst[xy(0, 3)] = s[2];
        dst += 1;
        s += 3;
    }
}

pub export fn GetDoorDrawDataIndex_West_clean_door_index(door: c_int) callconv(.c) void { // 81fbc2
    GetDoorDrawDataIndex_West(door, door);
}

pub export fn DoorDoorStep1_West(door: c_int, dma_ptr_: c_int) callconv(.c) c_int { // 81fbcc
    var dma_ptr = dma_ptr_;
    var pos: c_int = v.dung_door_tilemap_address[index(door)];
    if ((pos & 0x7ff) >= ci(t.kDoorPositionToTilemapOffs_Left[6])) {
        pos -= 16;
        if ((v.door_type_and_slot[index(door)] & 0xfe) >= 0x42)
            pos -= 12;
        GetDoorDrawDataIndex_East(door ^ 8, door & 7);
        dma_ptr = c.Dungeon_PrepOverlayDma_nextPrep(dma_ptr, u16w(pos));
        c.Dungeon_LoadSingleDoorAttribute(door ^ 8);
    }
    GetDoorDrawDataIndex_West(door, door & 7);
    return dma_ptr;
}

pub export fn GetDoorDrawDataIndex_West(door: c_int, r4_door: c_int) callconv(.c) void { // 81fc18
    const door_type: u8 = @truncate(v.door_type_and_slot[index(door)] & 0xfe);
    var x: c_int = v.door_open_closed_counter.*;
    if (x == 0 or x == 4) {
        DrawDoorToTileMap_West(door, r4_door);
        return;
    }
    x += if (door_type >= 0x42) @as(c_int, 4) else 0;
    x += if (ci(door_type) == c.kDoorType_ShuttersTwoWay or ci(door_type) == c.kDoorType_Shutter) @as(c_int, 2) else 0;
    c.Object_Draw_DoorLeft_3x4(t.kDoorAnimLeftSrc[index(x >> 1)], door);
}

pub export fn DrawDoorToTileMap_West(door: c_int, r4_door: c_int) callconv(.c) void { // 81fc45
    c.Object_Draw_DoorLeft_3x4(t.kDoorTypeSrcData3[index(GetDoorGraphicsIndex(door, r4_door) >> 1)], door);
}

pub export fn GetDoorDrawDataIndex_East_clean_door_index(door: c_int) callconv(.c) void { // 81fc80
    GetDoorDrawDataIndex_East(door, door);
}

pub export fn DoorDoorStep1_East(door: c_int, dma_ptr_: c_int) callconv(.c) c_int { // 81fc8a
    var dma_ptr = dma_ptr_;
    var pos: c_int = v.dung_door_tilemap_address[index(door)];
    if ((pos & 0x7ff) < ci(t.kDoorPositionToTilemapOffs_Right[6])) {
        pos += 16;
        if ((v.door_type_and_slot[index(door)] & 0xfe) >= 0x42)
            pos += 12;
        GetDoorDrawDataIndex_West(door ^ 8, door & 7);
        dma_ptr = c.Dungeon_PrepOverlayDma_nextPrep(dma_ptr, u16w(pos));
        c.Dungeon_LoadSingleDoorAttribute(door ^ 8);
    }
    GetDoorDrawDataIndex_East(door, door & 7);
    return dma_ptr;
}

pub export fn GetDoorDrawDataIndex_East(door: c_int, r4_door: c_int) callconv(.c) void { // 81fcd6
    const door_type: u8 = @truncate(v.door_type_and_slot[index(door)] & 0xfe);
    var x: c_int = v.door_open_closed_counter.*;
    if (x == 0 or x == 4) {
        DrawDoorToTileMap_East(door, r4_door);
        return;
    }
    x += if (door_type >= 0x42) @as(c_int, 4) else 0;
    x += if (ci(door_type) == c.kDoorType_ShuttersTwoWay or ci(door_type) == c.kDoorType_Shutter) @as(c_int, 2) else 0;
    c.Object_Draw_DoorRight_3x4(t.kDoorAnimRightSrc[index(x >> 1)], door);
}

pub export fn DrawDoorToTileMap_East(door: c_int, r4_door: c_int) callconv(.c) void { // 81fd03
    c.Object_Draw_DoorRight_3x4(t.kDoorTypeSrcData4[index(GetDoorGraphicsIndex(door, r4_door) >> 1)], door);
}

pub export fn GetDoorGraphicsIndex(door: c_int, r4_door: c_int) callconv(.c) u8 { // 81fd79
    var door_type: u8 = @truncate(v.door_type_and_slot[index(door)] & 0xfe);
    if (v.dung_door_opened_incl_adjacent.* & rtl.kUpperBitmasks[index(r4_door)] != 0)
        door_type = t.kDoorTypeRemap[index(door_type >> 1)];
    return door_type;
}

pub export fn ClearExplodingWallFromTileMap_ClearOnePair(dst_: Words, src_: Tiles) callconv(.c) void { // 81fddb
    var dst = dst_;
    var src = src_;
    var i: c_int = 2;
    while (i != 0) : (i -= 1) {
        for (0..12) |j|
            dst[xy(0, j)] = src[j];
        dst += 1;
        src += 12;
    }
}

pub export fn Dungeon_DrawRoomOverlay_Apply(p_: c_int) callconv(.c) void { // 81fe41
    var p = p_;
    var j: c_int = 0;
    while (j < 4) : ({
        j += 1;
        p += 64;
    }) {
        for (0..4) |i| {
            const tt: u16 = v.dung_bg2[index(p) + i] & 0x3fe;
            v.dung_bg2_attr_table[index(p) + i] = if (tt == 0xee or tt == 0xfe) 0 else 0x20;
        }
    }
}

pub export fn ApplyGrayscaleFixed_Incremental() callconv(.c) void { // 81feb0
    var a: u8 = v.COLDATA_copy0.* & 0x1f;
    if (a == v.overworld_fixed_color_plusminus.*)
        return;
    a +%= if (a < v.overworld_fixed_color_plusminus.*) @as(u8, 1) else 0xff;
    Dungeon_ApproachFixedColor_variable(a);
}

pub export fn Dungeon_ApproachFixedColor_variable(a: u8) callconv(.c) void { // 81fec1
    v.COLDATA_copy0.* = a | 0x20;
    v.COLDATA_copy1.* = a | 0x40;
    v.COLDATA_copy2.* = a | 0x80;
}

pub export fn Module_PreDungeon() callconv(.c) void { // 82821e
    v.sound_effect_ambient.* = 5;
    v.sound_effect_1.* = 0;
    v.dungeon_room_index.* = 0;
    v.dungeon_room_index_prev.* = 0;
    v.dung_savegame_state_bits.* = 0;

    v.agahnim_pal_setting[2] = 0;
    v.agahnim_pal_setting[1] = v.agahnim_pal_setting[2];
    v.agahnim_pal_setting[0] = v.agahnim_pal_setting[1];
    v.agahnim_pal_setting[5] = 0;
    v.agahnim_pal_setting[4] = v.agahnim_pal_setting[5];
    v.agahnim_pal_setting[3] = v.agahnim_pal_setting[4];

    c.Dungeon_LoadEntrance();
    const d: u8 = @truncate(v.cur_palace_index_x2.*);
    v.link_num_keys.* = if (d != 0xff) v.link_keys_earned_per_dungeon[index(if (d == 2) @as(u8, 0) else d >> 1)] else 0xff;
    c.Hud_Rebuild();
    v.dung_num_lit_torches.* = 0;
    v.hdr_dungeon_dark_with_lantern.* = 0;
    c.Dungeon_LoadAndDrawRoom();
    snapRoomCameraX();
    c.Dungeon_LoadCustomTileAttr();

    c.DecompressAnimatedDungeonTiles(t.kDungAnimatedTiles[index(v.main_tile_theme_index.*)]);
    c.Dungeon_LoadAttributeTable();
    v.misc_sprites_graphics_index.* = 10;
    c.InitializeTilesets();
    v.palette_sp6r_indoors.* = 10;
    c.Dungeon_LoadPalettes();
    if (v.link_is_bunny_mirror.* | v.link_is_bunny.* != 0)
        c.LoadGearPalettes_bunny();

    v.dung_loade_bgoffs_h_copy.* = (v.dungeon_room_index.* & 0xf) << 9;
    v.dung_loade_bgoffs_v_copy.* = swap16_p5((v.dungeon_room_index.* & 0xff0) >> 3);

    if (v.dungeon_room_index.* == 0x104 and v.sram_progress_flags.* & 0x10 != 0)
        word(v.dung_want_lights_out).* = 0;

    c.SetAndSaveVisitedQuadrantFlags();
    v.CGWSEL_copy.* = 2;
    v.CGADSUB_copy.* = 0xb3;

    var x: u8 = v.dung_num_lit_torches.*;
    if (v.dung_want_lights_out.* == 0) {
        x = 3;
        v.CGADSUB_copy.* = if (v.dung_hdr_bg2_properties.* == 7) 0x32 else if (v.dung_hdr_bg2_properties.* == 4) 0x62 else 0x20;
    }
    v.overworld_fixed_color_plusminus.* = rtl.kLitTorchesColorPlus[index(x)];
    Dungeon_ApproachFixedColor_variable(v.overworld_fixed_color_plusminus.*);
    low(v.palette_filter_countdown).* = 0x1f;
    v.mosaic_target_level.* = 0;
    low(v.darkening_or_lightening_screen).* = 2;
    v.overworld_palette_aux_or_main.* = 0;
    v.link_speed_modifier.* = 0;
    v.button_mask_b_y.* = 0;
    v.button_b_frames.* = 0;
    Dungeon_ResetTorchBackgroundAndPlayer();
    c.Link_CheckBunnyStatus();
    ResetThenCacheRoomEntryProperties();
    if (v.follower_indicator.* == 13) {
        v.follower_indicator.* = 0;
        v.super_bomb_indicator_unk2.* = 0;
        c.Hud_RemoveSuperBombIndicator();
    }
    v.BGMODE_copy.* = 9;
    c.Follower_Initialize();
    c.Sprite_ResetAll();
    c.Dungeon_ResetSprites();
    v.byte_7E02F0.* = 0;
    v.flag_skip_call_tag_routines.* +%= 1;
    if (v.sram_progress_indicator.* == 0 and !(v.sram_progress_flags.* & 0x10 != 0)) {
        v.COLDATA_copy0.* = 0x30;
        v.COLDATA_copy1.* = 0x50;
        v.COLDATA_copy2.* = 0x80;
        v.dung_want_lights_out_copy.* = 0;
        v.dung_want_lights_out.* = v.dung_want_lights_out_copy.*;
        c.Link_TuckIntoBed();
    }
    v.saved_module_for_menu.* = 7;
    v.main_module_index.* = 7;
    v.submodule_index.* = 15;
    c.Dungeon_LoadSongBankIfNeeded();
    Module_PreDungeon_setAmbientSfx();
}

pub export fn Module_PreDungeon_setAmbientSfx() callconv(.c) void { // 82838c
    if (v.sram_progress_indicator.* < 2) {
        v.sound_effect_ambient.* = 5;
        if (!sign8(v.dung_cur_floor.*) and v.dungeon_room_index.* != 2 and v.dungeon_room_index.* != 18)
            v.sound_effect_ambient.* = 3;
    }
}

pub export fn LoadOWMusicIfNeeded() callconv(.c) void { // 82854c
    if (v.flag_which_music_type.* == 0)
        return;
    v.flag_which_music_type.* = 0;
    c.LoadOverworldSongs();
}

pub export fn Module07_Dungeon() callconv(.c) void { // 8287a2
    c.Dungeon_HandleLayerEffect();
    t.kDungeonSubmodules[index(v.submodule_index.*)].?();

    // When having the somaria on door button and exiting in skull woods,
    // don't overwrite submodule_index
    skip: {
        if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0 and v.main_module_index.* != 7)
            break :skip;

        v.dung_misc_objs_index.* = 0;
        c.Dungeon_PushBlock_Handler();
        if (v.submodule_index.* != 0) break :skip;
        c.Graphics_LoadChrHalfSlot();
        c.Dungeon_HandleCamera();
        if (v.submodule_index.* != 0) break :skip;
        c.Dungeon_HandleRoomTags();
        if (v.submodule_index.* != 0) break :skip;
        c.Dungeon_ProcessTorchesAndDoors();
        if (v.dung_unk_blast_walls_2.* != 0)
            c.Dungeon_ClearAwayExplodingWall();
        if (v.is_standing_in_doorway.* == 0)
            Dungeon_TryScreenEdgeTransition();
    }
    c.OrientLampLightCone();

    const bg2x: c_int = v.BG2HOFS_copy2.*;
    const bg2y: c_int = v.BG2VOFS_copy2.*;
    var bg1x: c_int = v.BG1HOFS_copy2.*;
    var bg1y: c_int = v.BG1VOFS_copy2.*;

    v.BG2HOFS_copy.* = u16w(bg2x + ci(v.bg1_x_offset.*));
    v.BG2HOFS_copy2.* = v.BG2HOFS_copy.*;
    v.BG2VOFS_copy.* = u16w(bg2y + ci(v.bg1_y_offset.*));
    v.BG2VOFS_copy2.* = v.BG2VOFS_copy.*;
    v.BG1HOFS_copy.* = u16w(bg1x + ci(v.bg1_x_offset.*));
    v.BG1HOFS_copy2.* = v.BG1HOFS_copy.*;
    v.BG1VOFS_copy.* = u16w(bg1y + ci(v.bg1_y_offset.*));
    v.BG1VOFS_copy2.* = v.BG1VOFS_copy.*;

    if (v.dung_hdr_collision_2_mirror.* != 0) {
        bg1x = ci(v.BG2HOFS_copy2.*) + ci(v.dung_floor_x_offs.*);
        v.BG1HOFS_copy.* = u16w(bg1x);
        v.BG1HOFS_copy2.* = v.BG1HOFS_copy.*;
        bg1y = ci(v.BG2VOFS_copy2.*) + ci(v.dung_floor_y_offs.*);
        v.BG1VOFS_copy.* = u16w(bg1y);
        v.BG1VOFS_copy2.* = v.BG1VOFS_copy.*;
    }

    c.Sprite_Dungeon_DrawAllPushBlocks();
    c.Sprite_Main();

    v.BG2HOFS_copy2.* = u16w(bg2x);
    v.BG2VOFS_copy2.* = u16w(bg2y);
    v.BG1HOFS_copy2.* = u16w(bg1x);
    v.BG1VOFS_copy2.* = u16w(bg1y);

    c.LinkOam_Main();
    c.Hud_RefillLogic();
    c.Hud_FloorIndicator();
}

pub export fn Dungeon_TryScreenEdgeTransition() callconv(.c) void { // 82885e
    var dir: c_int = undefined;

    trigger_trans: {
        if (v.link_y_vel.* != 0) {
            const y: c_int = (ci(v.link_y_coord.*) & 0x1ff);
            dir = 3;
            if (y < 4) break :trigger_trans;
            dir = 2;
            if (y >= 476) break :trigger_trans;
        }

        if (v.link_x_vel.* != 0) {
            const y: c_int = (ci(v.link_x_coord.*) & 0x1ff);
            dir = 1;
            if (y < 8) break :trigger_trans;
            dir = 0;
            if (y >= 489) break :trigger_trans;
        }
        return;
    }

    if (!c.Link_CheckForEdgeScreenTransition() and v.main_module_index.* == 7) {
        Dungeon_HandleEdgeTransitionMovement(dir);
        if (v.main_module_index.* == 7)
            v.submodule_index.* = 2;
    }
}

pub export fn Dungeon_HandleEdgeTransitionMovement(dir: c_int) callconv(.c) void { // 8288c5
    const kLimitDirectionOnOneAxis = [_]u8{ 0x3, 0x3, 0xc, 0xc };
    v.link_direction.* &= kLimitDirectionOnOneAxis[index(dir)];
    switch (dir) {
        0 => c.Dungeon_StartInterRoomTrans_Right(),
        1 => c.Dungeon_StartInterRoomTrans_Left(),
        2 => c.Dungeon_StartInterRoomTrans_Down(),
        3 => c.Dungeon_StartInterRoomTrans_Up(),
        else => unreachable,
    }
}

pub export fn Module07_00_PlayerControl() callconv(.c) void { // 8288de
    if (!(v.flag_custom_spell_anim_active.* | v.flag_is_link_immobilized.* | v.flag_block_link_menu.* != 0)) {
        if (v.filtered_joypad_H.* & 0x10 != 0) { // start
            v.overworld_map_state.* = 0;
            v.submodule_index.* = 1;
            v.saved_module_for_menu.* = v.main_module_index.*;
            v.main_module_index.* = 14;
            return;
        } else if (c.DidPressButtonForMap()) { // x
            if (@as(u8, @truncate(v.cur_palace_index_x2.*)) != 0xff and @as(u8, @truncate(v.dungeon_room_index.*)) != 0) {
                v.overworld_map_state.* = 0;
                v.submodule_index.* = 3;
                v.saved_module_for_menu.* = v.main_module_index.*;
                v.main_module_index.* = 14;
                return;
            }
        } else if (v.joypad1H_last.* & 0x20 != 0) { // select
            if (v.sram_progress_indicator.* != 0) {
                v.overworld_map_state.* = 0;
                c.DisplaySelectMenu();
                return;
            }
        }
        c.Hud_HandleItemSwitchInputs();
    }
    c.Link_Main();
}

pub export fn Module07_01_SubtileTransition() callconv(.c) void { // 82897c
    v.link_y_coord_prev.* = v.link_y_coord.*;
    v.link_x_coord_prev.* = v.link_x_coord.*;
    c.Link_HandleMovingAnimation_FullLongEntry();
    t.kDungeon_IntraRoomTrans[index(v.subsubmodule_index.*)].?();
}

pub export fn DungeonTransition_Subtile_ResetShutters() callconv(.c) void { // 828995
    low(v.dung_flag_trapdoors_down).* = 0;
    low(v.door_animation_step_indicator).* = 7;
    const bak: u8 = v.submodule_index.*;
    c.OperateShutterDoors();
    v.submodule_index.* = bak;
    low(v.palette_filter_countdown).* = 31;
    v.mosaic_target_level.* = 0;
    v.subsubmodule_index.* +%= 1;
}

pub export fn DungeonTransition_Subtile_PrepTransition() callconv(.c) void { // 8289b6
    v.darkening_or_lightening_screen.* = 0;
    v.palette_filter_countdown.* = 0;
    v.mosaic_target_level.* = 31;
    v.unused_config_gfx.* = 0;
    v.dung_flag_somaria_block_switch.* = 0;
    v.dung_flag_statechange_waterpuzzle.* = 0;
    v.subsubmodule_index.* +%= 1;
}

pub export fn DungeonTransition_Subtile_ApplyFilter() callconv(.c) void { // 8289d8
    if (v.dung_want_lights_out.* == 0) {
        v.subsubmodule_index.* +%= 1;
        return;
    }
    c.ApplyPaletteFilter_bounce();
    if (low(v.palette_filter_countdown).* != 0)
        c.ApplyPaletteFilter_bounce();
}

pub export fn DungeonTransition_Subtile_TriggerShutters() callconv(.c) void { // 8289f0
    ResetThenCacheRoomEntryProperties();
    if (low(v.dung_flag_trapdoors_down).* == 0) {
        low(v.dung_flag_trapdoors_down).* +%= 1;
        low(v.dung_cur_door_pos).* = 0;
        low(v.door_animation_step_indicator).* = 0;
        v.submodule_index.* = 5;
    }
}

pub export fn Module07_02_SupertileTransition() callconv(.c) void { // 828a26
    v.link_y_coord_prev.* = v.link_y_coord.*;
    v.link_x_coord_prev.* = v.link_x_coord.*;
    if (v.subsubmodule_index.* != 0) {
        if (v.subsubmodule_index.* >= 7)
            c.Graphics_IncrementalVRAMUpload();
        c.Dungeon_LoadAttribute_Selectable();
    }
    c.Link_HandleMovingAnimation_FullLongEntry();
    t.kDungeon_InterRoomTrans[index(v.subsubmodule_index.*)].?();
}

pub export fn Module07_02_00_InitializeTransition() callconv(.c) void { // 828a4f
    if (!cameraToScrollStart()) return;
    const bak: u8 = v.hdr_dungeon_dark_with_lantern.*;
    ResetTransitionPropsAndAdvanceSubmodule();
    v.hdr_dungeon_dark_with_lantern.* = bak;
}

pub export fn Module07_02_01_LoadNextRoom() callconv(.c) void { // 828a5b
    dungeon_wide.keepRoomBeingLeft();
    c.Dungeon_LoadRoom();
    dungeon_wide.noteNextRoomLoaded();
    c.ResetStarTileGraphics();
    c.LoadTransAuxGFX_sprite();
    v.subsubmodule_index.* +%= 1;
    v.overworld_map_state.* = 0;
    low(v.dungeon_room_index2).* = low(v.dungeon_room_index).*;
    c.Dungeon_ResetSprites();
    if (v.hdr_dungeon_dark_with_lantern.* == 0)
        c.MirrorBg1Bg2Offs();
    v.hdr_dungeon_dark_with_lantern.* = 0;
}

pub export fn Dungeon_InterRoomTrans_State3() callconv(.c) void { // 828a87
    if (v.dung_want_lights_out.* | v.dung_want_lights_out_copy.* != 0)
        v.TS_copy.* = 0;
    c.Dungeon_AdjustForRoomLayout();
    c.LoadNewSpriteGFXSet();
    c.MirrorBg1Bg2Offs();
    c.WaterFlood_BuildOneQuadrantForVRAM();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Dungeon_InterRoomTrans_State10() callconv(.c) void { // 828aa5
    if (v.dung_want_lights_out.* | v.dung_want_lights_out_copy.* != 0)
        c.ApplyPaletteFilter_bounce();
    Dungeon_InterRoomTrans_notDarkRoom();
}

pub export fn Dungeon_SpiralStaircase11() callconv(.c) void { // 828aaf
    c.ApplyPaletteFilter_bounce();
    c.WaterFlood_BuildOneQuadrantForVRAM();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Dungeon_InterRoomTrans_notDarkRoom() callconv(.c) void { // 828ab3
    c.WaterFlood_BuildOneQuadrantForVRAM();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Dungeon_InterRoomTrans_State9() callconv(.c) void { // 828aba
    if (v.dung_want_lights_out.* | v.dung_want_lights_out_copy.* != 0)
        c.ApplyPaletteFilter_bounce();
    Dungeon_InterRoomTrans_State4();
}

pub export fn Dungeon_SpiralStaircase12() callconv(.c) void { // 828ac4
    c.ApplyPaletteFilter_bounce();
    c.Dungeon_PrepareNextRoomQuadrantUpload();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Dungeon_InterRoomTrans_State4() callconv(.c) void { // 828ac8
    c.Dungeon_PrepareNextRoomQuadrantUpload();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Dungeon_InterRoomTrans_State12() callconv(.c) void { // 828acf
    if (v.submodule_index.* == 2) {
        if (v.overworld_map_state.* != 5)
            return;
        c.SubtileTransitionCalculateLanding();
        if (v.dung_want_lights_out.* | v.dung_want_lights_out_copy.* != 0)
            c.ApplyPaletteFilter_bounce();
    }
    v.subsubmodule_index.* +%= 1;
    Dungeon_ResetTorchBackgroundAndPlayer();
}

pub export fn Dungeon_Staircase14() callconv(.c) void { // 828aed
    v.subsubmodule_index.* +%= 1;
    Dungeon_ResetTorchBackgroundAndPlayer();
}

pub export fn Dungeon_ResetTorchBackgroundAndPlayer() callconv(.c) void { // 828aef
    var ts: u8 = @bitCast(t.kSpiralTab1[index(v.dung_hdr_bg2_properties.*)]);
    var tm: u8 = 0x16;
    if (sign8(ts)) {
        tm = 0x17;
        ts = 0;
    }
    if (v.dung_hdr_bg2_properties.* == 2)
        ts = 3;
    v.TM_copy.* = tm;
    v.TS_copy.* = ts;
    c.Hud_RestoreTorchBackground();
    Dungeon_ResetTorchBackgroundAndPlayerInner();
}

pub export fn Dungeon_ResetTorchBackgroundAndPlayerInner() callconv(.c) void { // 828b0c
    _ = c.Ancilla_TerminateSelectInteractives(0);
    if (v.link_is_running.* != 0 and !(features.enhanced_features0.* & features.kFeatures0_TurnWhileDashing != 0)) {
        v.link_auxiliary_state.* = 0;
        v.link_incapacitated_timer.* = 0;
        v.link_actual_vel_z.* = 0xff;
        v.g_ram[0xc7] = 0xff;
        v.link_delay_timer_spin_attack.* = 0;
        v.link_speed_setting.* = 0;
        v.swimcoll_var5[0] &= 0xff00;
        v.link_is_running.* = 0;
        v.link_player_handler_state.* = 0;
    }
}

pub export fn Dungeon_InterRoomTrans_State7() callconv(.c) void { // 828b2e
    v.BG1HOFS_copy2.* = v.BG2HOFS_copy2.*;
    v.BG1VOFS_copy2.* = v.BG2VOFS_copy2.*;

    if (v.dungeon_room_index.* != 54 and v.dungeon_room_index.* != 56) {
        const y: u16 = if (t.kSpiralTab1[index(v.dung_hdr_bg2_properties.*)] != 0) 0x116 else 0x16;
        if (ci(y) != (ci(v.TM_copy.*) | ci(v.TS_copy.*) << 8) and (v.TM_copy.* == 0x17 or (v.TM_copy.* | v.TS_copy.*) != 0x17)) {
            v.TM_copy.* = @truncate(y);
            v.TS_copy.* = @truncate(y >> 8);
        }
    }
    DungeonTransition_RunFiltering();
}

pub export fn DungeonTransition_RunFiltering() callconv(.c) void { // 828b67
    if (v.dung_want_lights_out.* | v.dung_want_lights_out_copy.* != 0) {
        v.overworld_fixed_color_plusminus.* = rtl.kLitTorchesColorPlus[index(if (v.dung_want_lights_out.* != 0) v.dung_num_lit_torches.* else 3)];
        Dungeon_ApproachFixedColor_variable(v.overworld_fixed_color_plusminus.*);
        v.mosaic_target_level.* = 0;
    }
    c.Dungeon_HandleTranslucencyAndPalette();
}

pub export fn Module07_02_FadedFilter() callconv(.c) void { // 828b92
    if (v.dung_want_lights_out.* | v.dung_want_lights_out_copy.* != 0) {
        c.ApplyPaletteFilter_bounce();
        if (low(v.palette_filter_countdown).* != 0)
            c.ApplyPaletteFilter_bounce();
    } else {
        v.subsubmodule_index.* +%= 1;
    }
}

pub export fn Dungeon_InterRoomTrans_State15() callconv(.c) void { // 828bae
    ResetThenCacheRoomEntryProperties();
    if (low(v.dung_flag_trapdoors_down).* == 0 and (low(v.dungeon_room_index).* != 172 or v.dung_savegame_state_bits.* & 0x3000 != 0)) {
        low(v.dung_flag_trapdoors_down).* = 1;
        low(v.dung_cur_door_pos).* = 0;
        low(v.door_animation_step_indicator).* = 0;
        v.submodule_index.* = 5;
    }
    Dungeon_PlayMusicIfDefeated();
}

pub export fn Dungeon_PlayMusicIfDefeated() callconv(.c) void { // 828bd7
    var x: u8 = 0x14;
    if (v.dungeon_room_index.* != 18) {
        x = 0x10;
        if (v.dungeon_room_index.* != 2) {
            if (FindInWordArray(&t.kBossRooms, v.dungeon_room_index.*, t.kBossRooms.len) < 0)
                return;
            if (c.Sprite_CheckIfScreenIsClear())
                return;
            x = 0x15;
        }
    }
    v.music_control.* = x;
}

pub export fn Module07_03_OverlayChange() callconv(.c) void { // 828c05
    var overlay_p: [*]const u8 = kDungeonRoomOverlay() + index(kDungeonRoomOverlayOffs()[index(v.dung_overlay_to_load.*)]);
    c.Dungeon_DrawRoomOverlay(overlay_p);
    var dst_pos: c_int = 0;
    while (true) {
        const a: u16 = @as(*align(1) const u16, @ptrCast(overlay_p)).*;
        if (a == 0xffff)
            break;
        const p: c_int = (ci(overlay_p[0] >> 2)) | (ci(overlay_p[1] >> 2)) << 6;
        dst_pos = c.Dungeon_PrepOverlayDma_nextPrep(dst_pos, u16w(p * 2));
        Dungeon_DrawRoomOverlay_Apply(p);
        overlay_p += 3;
    }
    v.nmi_copy_packets_flag.* = 1;
    v.submodule_index.* = 0;
}

pub export fn Module07_04_UnlockDoor() callconv(.c) void { // 828c0a
    c.Dungeon_OpeningLockedDoor_Combined(false);
}

pub export fn Module07_05_ControlShutters() callconv(.c) void { // 828c0f
    // Widescreen: the doors can shut behind Link as he comes in, and the
    // camera's glide into a wide room's range carries on meanwhile.
    settleRoomCameraX();
    c.OperateShutterDoors();
}

pub export fn Module07_06_FatInterRoomStairs() callconv(.c) void { // 828c14
    table: {
        if (v.subsubmodule_index.* >= 3)
            c.Dungeon_LoadAttribute_Selectable();

        if (v.subsubmodule_index.* >= 13) {
            c.Graphics_IncrementalVRAMUpload();
            if (v.staircase_var1.* == 0)
                break :table;
            const sv: u8 = v.staircase_var1.*;
            v.staircase_var1.* = sv -% 1;
            if (sv == 0x10)
                v.link_speed_modifier.* = 2;
            v.link_direction.* = if (v.which_staircase_index.* & 4 != 0) 4 else 8;
            c.Link_HandleVelocity();
            c.Dungeon_HandleCamera();
        }
        c.Link_HandleMovingAnimation_FullLongEntry();
    }
    switch (v.subsubmodule_index.*) {
        0 => ResetTransitionPropsAndAdvance_ResetInterface(),
        1 => {
            c.ApplyPaletteFilter_bounce();
            if (low(v.palette_filter_countdown).* != 0)
                c.ApplyPaletteFilter_bounce();
        },
        2 => Dungeon_InitializeRoomFromSpecial(),
        3 => DungeonTransition_TriggerBGC34UpdateAndAdvance(),
        4 => DungeonTransition_TriggerBGC56UpdateAndAdvance(),
        5 => DungeonTransition_LoadSpriteGFX(),
        6 => DungeonTransition_AdjustForFatStairScroll(),
        7 => Dungeon_InterRoomTrans_State4(),
        8 => Dungeon_InterRoomTrans_notDarkRoom(),
        9 => Dungeon_InterRoomTrans_State4(),
        10 => Dungeon_SpiralStaircase11(),
        11 => Dungeon_SpiralStaircase12(),
        12 => Dungeon_SpiralStaircase11(),
        13 => Dungeon_SpiralStaircase12(),
        14 => c.Dungeon_DoubleApplyAndIncrementGrayscale(),
        15 => Dungeon_Staircase14(),
        16 => {
            if ((low(v.darkening_or_lightening_screen).* | low(v.palette_filter_countdown).*) == 0 and v.overworld_map_state.* == 5)
                ResetThenCacheRoomEntryProperties();
        },
        else => {},
    }
}

pub export fn Module07_0E_01_HandleMusicAndResetProps() callconv(.c) void { // 828c78
    if ((v.dungeon_room_index.* == 7 or v.dungeon_room_index.* == 23 and !c.ZeldaIsPlayingMusicTrack(17)) and !(v.link_which_pendants.* & 1 != 0))
        v.music_control.* = 0xf1;
    v.staircase_var1.* = if (v.which_staircase_index.* & 4 != 0) 106 else 88;
    v.overworld_map_state.* = 0;
    ResetTransitionPropsAndAdvanceSubmodule();
}

pub export fn ResetTransitionPropsAndAdvance_ResetInterface() callconv(.c) void { // 828ca9
    v.overworld_map_state.* = 0;
    ResetTransitionPropsAndAdvanceSubmodule();
}

pub export fn ResetTransitionPropsAndAdvanceSubmodule() callconv(.c) void { // 828cac
    word(v.mosaic_level).* = 0;
    v.darkening_or_lightening_screen.* = 0;
    v.palette_filter_countdown.* = 0;
    v.mosaic_target_level.* = 31;
    v.unused_config_gfx.* = 0;
    v.dung_num_lit_torches.* = 0;
    if (v.hdr_dungeon_dark_with_lantern.* != 0) {
        v.CGWSEL_copy.* = 0x02;
        v.CGADSUB_copy.* = 0xB3;
    }
    v.hdr_dungeon_dark_with_lantern.* = 0;
    Dungeon_ResetTorchBackgroundAndPlayerInner();
    c.Overworld_CopyPalettesToCache();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Dungeon_InitializeRoomFromSpecial() callconv(.c) void { // 828ce2
    c.Dungeon_AdjustAfterSpiralStairs();
    c.Dungeon_LoadRoom();
    c.ResetStarTileGraphics();
    c.LoadTransAuxGFX();
    c.Dungeon_LoadCustomTileAttr();
    low(v.dungeon_room_index2).* = low(v.dungeon_room_index).*;
    c.Follower_Initialize();
    v.subsubmodule_index.* +%= 1;
}

pub export fn DungeonTransition_LoadSpriteGFX() callconv(.c) void { // 828d10
    c.LoadNewSpriteGFXSet();
    c.Dungeon_ResetSprites();
    DungeonTransition_RunFiltering();
}

pub export fn DungeonTransition_AdjustForFatStairScroll() callconv(.c) void { // 828d1b
    c.MirrorBg1Bg2Offs();
    c.Dungeon_AdjustForRoomLayout();
    snapRoomCameraX();
    var ts: u8 = @bitCast(t.kSpiralTab1[index(v.dung_hdr_bg2_properties.*)]);
    var tm: u8 = 0x16;
    if (sign8(ts)) {
        tm = 0x17;
        ts = 0;
    }
    v.TM_copy.* = tm;
    v.TS_copy.* = ts;

    v.link_speed_modifier.* = 1;
    if (v.which_staircase_index.* & 4 != 0) {
        v.dung_cur_floor.* -%= 1;
        v.staircase_var1.* = 32;
        v.sound_effect_1.* = 0x19;
    } else {
        v.dung_cur_floor.* +%= 1;
        v.staircase_var1.* = 48;
        v.sound_effect_1.* = 0x17;
    }
    v.sound_effect_2.* = 0x24;
    Dungeon_PlayBlipAndCacheQuadrantVisits();
    Dungeon_InterRoomTrans_notDarkRoom();
}

pub export fn ResetThenCacheRoomEntryProperties() callconv(.c) void { // 828d71
    v.overworld_map_state.* = 0;
    v.subsubmodule_index.* = 0;
    v.overworld_screen_transition.* = 0;
    v.submodule_index.* = 0;
    v.dung_flag_statechange_waterpuzzle.* = 0;
    v.dung_flag_movable_block_was_pushed.* = 0;
    c.CacheCameraProperties();
}

pub export fn DungeonTransition_TriggerBGC34UpdateAndAdvance() callconv(.c) void { // 828e0f
    c.PrepTransAuxGfx();
    v.nmi_disable_core_updates.* = 9;
    v.nmi_subroutine_index.* = v.nmi_disable_core_updates.*;
    v.subsubmodule_index.* +%= 1;
}

pub export fn DungeonTransition_TriggerBGC56UpdateAndAdvance() callconv(.c) void { // 828e1d
    v.nmi_disable_core_updates.* = 10;
    v.nmi_subroutine_index.* = v.nmi_disable_core_updates.*;
    v.subsubmodule_index.* +%= 1;
}

pub export fn Module07_07_FallingTransition() callconv(.c) void { // 828e27
    if (v.subsubmodule_index.* >= 6) {
        c.Graphics_IncrementalVRAMUpload();
        c.Dungeon_LoadAttribute_Selectable();
        ApplyGrayscaleFixed_Incremental();
    }
    t.kDungeon_Submodule_7_DownFloorTrans[index(v.subsubmodule_index.*)].?();
}

pub export fn Module07_07_00_HandleMusicAndResetRoom() callconv(.c) void { // 828e63
    if (v.dungeon_room_index.* == 0x10 or v.dungeon_room_index.* == 7 or v.dungeon_room_index.* == 0x17)
        v.music_control.* = 0xf1;
    ResetTransitionPropsAndAdvance_ResetInterface();
}

pub export fn Module07_07_06_SyncBG1and2() callconv(.c) void { // 828e80
    c.MirrorBg1Bg2Offs();
    c.Dungeon_AdjustForRoomLayout();
    snapRoomCameraX();
    var ts: u8 = @bitCast(t.kSpiralTab1[index(v.dung_hdr_bg2_properties.*)]);
    var tm: u8 = 0x16;
    if (sign8(ts)) {
        tm = 0x17;
        ts = 0;
    }
    v.TM_copy.* = tm;
    v.TS_copy.* = ts;
    c.WaterFlood_BuildOneQuadrantForVRAM();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Module07_07_0F_FallingFadeIn() callconv(.c) void { // 828ea1
    c.ApplyPaletteFilter_bounce();
    if (low(v.darkening_or_lightening_screen).* != 0)
        return;
    const yp = &v.tiledetect_which_y_pos[0];
    high(yp).* = high(v.link_y_coord).* +% @as(u8, @intFromBool(low(v.link_y_coord).* >= low(yp).*));
    c.Dungeon_SetBossMusicUnorthodox();
    if (low(v.dungeon_room_index).* == 0x89 or low(v.dungeon_room_index).* == 0x4f)
        return;
    if (low(v.dungeon_room_index).* == 0xA7) {
        v.hud_floor_changed_timer.* = 0;
        v.dung_cur_floor.* = 1;
        return;
    }
    v.dung_cur_floor.* -%= 1;
    Dungeon_PlayBlipAndCacheQuadrantVisits();
}

pub export fn Dungeon_PlayBlipAndCacheQuadrantVisits() callconv(.c) void { // 828ec9
    v.hud_floor_changed_timer.* = 1;
    v.sound_effect_2.* = 36;
    c.SetAndSaveVisitedQuadrantFlags();
}

pub export fn Module07_07_10_LandLinkFromFalling() callconv(.c) void { // 828ee0
    c.HandleDungeonLandingFromPit();
    if (v.submodule_index.* != 0)
        return;
    v.submodule_index.* = 7;
    v.subsubmodule_index.* = 17;
    v.load_chr_halfslot_even_odd.* = 1;
    c.Graphics_LoadChrHalfSlot();
}

pub export fn Module07_07_11_CacheRoomAndSetMusic() callconv(.c) void { // 828efa
    if (v.overworld_map_state.* == 5) {
        ResetThenCacheRoomEntryProperties();
        Dungeon_PlayMusicIfDefeated();
        c.Graphics_LoadChrHalfSlot();
    }
}

// straight staircase going down when walking south
pub export fn Module07_08_NorthIntraRoomStairs() callconv(.c) void { // 828f0c
    const tv: u8 = v.staircase_var1.*;
    if (tv != 0) {
        v.staircase_var1.* -%= 1;
        if (tv == 20)
            v.link_speed_modifier.* = 2;
        c.Link_HandleVelocity();
        c.ApplyLinksMovementToCamera();
        c.Dungeon_HandleCamera();
        c.Link_HandleMovingAnimation_FullLongEntry();
    }
    t.kDungeon_StraightStaircaseDown[index(v.subsubmodule_index.*)].?();
}

pub export fn Module07_08_00_InitStairs() callconv(.c) void { // 828f35
    v.draw_water_ripples_or_grass.* = 0;

    var v1: u8 = 0x3c;
    var sfx: u8 = 25;
    if (v.link_direction.* & 8 != 0) {
        v1 = 0x38;
        sfx = 23;
        v.link_is_on_lower_level_mirror.* = 0;
        if (@as(u8, @truncate(v.kind_of_in_room_staircase.*)) != 2)
            v.link_is_on_lower_level.* = 0;
    }
    v.staircase_var1.* = v1;
    v.sound_effect_1.* = sfx;
    v.link_speed_modifier.* = 1;
    v.subsubmodule_index.* +%= 1;
}

// ---------------------------------------------------------------------------
// from dungeon_part6.zig
// ---------------------------------------------------------------------------
pub export fn Module07_08_01_ClimbStairs() callconv(.c) void { // 828f5f
    if (v.staircase_var1.* != 0)
        return;
    if (v.link_direction.* & 4 != 0) {
        v.link_is_on_lower_level_mirror.* = 1;
        if (@as(u8, @truncate(v.kind_of_in_room_staircase.*)) != 2)
            v.link_is_on_lower_level.* = 1;
    }
    v.subsubmodule_index.* = 0;
    v.overworld_screen_transition.* = 0;
    v.submodule_index.* = 0;
    c.SetAndSaveVisitedQuadrantFlags();
}

// straight staircase going up when walking south
pub export fn Module07_10_SouthIntraRoomStairs() callconv(.c) void { // 828f88
    const tv = v.staircase_var1.*;
    if (tv != 0) {
        v.staircase_var1.* -%= 1;
        if (tv == 20)
            v.link_speed_modifier.* = 2;
        c.Link_HandleVelocity();
        c.ApplyLinksMovementToCamera();
        c.Dungeon_HandleCamera();
        c.Link_HandleMovingAnimation_FullLongEntry();
    }
    t.kDungeon_StraightStaircase[v.subsubmodule_index.*].?();
}

pub export fn Module07_10_00_InitStairs() callconv(.c) void { // 828fb1
    var v1: u8 = 0x3c;
    var sfx: u8 = 25;
    if (v.link_direction.* & 4 != 0) {
        v1 = 0x38;
        sfx = 23;
        v.link_is_on_lower_level_mirror.* ^= 1;
        if (@as(u8, @truncate(v.kind_of_in_room_staircase.*)) != 2)
            v.link_is_on_lower_level.* ^= 1;
    }
    v.staircase_var1.* = v1;
    v.sound_effect_1.* = sfx;
    v.link_speed_modifier.* = 1;
    v.subsubmodule_index.* +%= 1;
}

pub export fn Module07_10_01_ClimbStairs() callconv(.c) void { // 828fe1
    if (v.staircase_var1.* != 0)
        return;
    if (v.link_direction.* & 8 != 0) {
        v.link_is_on_lower_level_mirror.* ^= 1;
        if (@as(u8, @truncate(v.kind_of_in_room_staircase.*)) != 2)
            v.link_is_on_lower_level.* ^= 1;
    }
    v.subsubmodule_index.* = 0;
    v.overworld_screen_transition.* = 0;
    v.submodule_index.* = 0;
    c.SetAndSaveVisitedQuadrantFlags();
}

pub export fn Module07_09_OpenCrackedDoor() callconv(.c) void { // 82900f
    c.OpenCrackedDoor();
}

// Used when lighting a lamp
pub export fn Module07_0A_ChangeBrightness() callconv(.c) void { // 829014
    c.OrientLampLightCone();
    c.ApplyGrayscaleFixed_Incremental();
    if ((v.COLDATA_copy0.* & 0x1f) != v.overworld_fixed_color_plusminus.*)
        return;
    v.submodule_index.* = 0;
    v.subsubmodule_index.* = 0;
}

pub export fn Module07_0B_DrainSwampPool() callconv(.c) void { // 82902d
    switch (v.subsubmodule_index.*) {
        0 => {
            if (v.turn_on_off_water_ctr.* & 7 == 0) {
                const k: usize = (v.turn_on_off_water_ctr.* >> 2) & 3;
                if (v.water_hdma_var2.* == v.water_hdma_var4.*) {
                    c.Dungeon_SetAttrForActivatedWaterOff();
                    return;
                }
                v.water_hdma_var2.* +%= u16w(kTurnOffWater_Tab0[k]);
                v.water_hdma_var3.* +%= u16w(kTurnOffWater_Tab0[k]);
            }
            v.turn_on_off_water_ctr.* +%= 1;
            c.AdjustWaterHDMAWindow();
        },
        1 => {
            const val = SrcPtr(0x1e0)[0];
            for (0..0x1000) |i|
                v.dung_bg1[i] = val;
            v.dung_cur_quadrant_upload.* = 0;
            v.subsubmodule_index.* +%= 1;
        },
        2, 3, 4, 5 => c.Dungeon_FloodSwampWater_PrepTileMap(),
        else => {},
    }
}

pub export fn Module07_0C_FloodSwampWater() callconv(.c) void { // 82904a
    var k: usize = undefined;

    const ssi = v.subsubmodule_index.*;
    switch (ssi) {
        0, 1, 2, 3 => c.Dungeon_FloodSwampWater_PrepTileMap(),
        4, 5, 6, 7, 8 => {
            v.turn_on_off_water_ctr.* -%= 1;
            if (v.turn_on_off_water_ctr.* == 0) {
                v.turn_on_off_water_ctr.* = 4;
                v.subsubmodule_index.* +%= 1;
                const depth: c_int = @as(c_int, v.subsubmodule_index.*) - 4;
                v.water_hdma_var3.* = 8;
                v.water_hdma_var5.* = 0;
                v.water_hdma_var2.* = 0x30;
                Dungeon_AdjustWaterVomit(SrcPtr(0x1654 + 0x10), depth);
            }
        },
        9, 10 => {
            if (ssi == 9) {
                v.W12SEL_copy.* = 3;
                v.W34SEL_copy.* = 0;
                v.WOBJSEL_copy.* = 0;
                v.TMW_copy.* = 22;
                v.TSW_copy.* = 1;
                v.TS_copy.* = 1;
                v.CGWSEL_copy.* = 2;
                v.CGADSUB_copy.* = 98;
                v.turn_on_off_water_ctr.* = 0;
                v.subsubmodule_index.* +%= 1;
                // fall through
            }
            k = v.turn_on_off_water_ctr.* & 3;
            const r0: u16 = 0x688 -% v.BG2VOFS_copy2.* -% 0x24;
            v.water_hdma_var3.* +%= u16w(kTurnOnWater_Tab0[k]);
            v.water_hdma_var5.* +%= u16w(kTurnOnWater_Tab1[k]);
            if (v.water_hdma_var5.* >= r0) {
                v.dung_hdr_bg2_properties.* = 7;
                v.subsubmodule_index.* +%= 1;
            }
            v.turn_on_off_water_ctr.* +%= 1;
            v.spotlight_y_lower.* = 0x688 -% v.BG2VOFS_copy2.* -% v.water_hdma_var2.*;
            v.spotlight_y_upper.* = v.spotlight_y_lower.* +% v.water_hdma_var5.*;
            c.AdjustWaterHDMAWindow_X(v.spotlight_y_upper.*);
        },
        11 => {
            if (v.turn_on_off_water_ctr.* & 7 == 0) {
                k = (v.turn_on_off_water_ctr.* >> 2) & 3;
                if (v.water_hdma_var2.* == v.water_hdma_var4.*) {
                    c.Dungeon_SetAttrForActivatedWater();
                    return;
                }
                v.water_hdma_var2.* +%= u16w(kTurnOnWater_Tab2[k]);
                v.water_hdma_var3.* +%= u16w(kTurnOnWater_Tab2[k]);

                const a: u16 = v.water_hdma_var4.* -% v.water_hdma_var2.*;
                if (a == 0 or a == 8)
                    Dungeon_AdjustWaterVomit(SrcPtr(if (a == 0) 0x16b4 else 0x168c), 5);
            }
            v.turn_on_off_water_ctr.* +%= 1;
            c.AdjustWaterHDMAWindow();
        },
        else => {},
    }
}

pub export fn Module07_0D_FloodDam() callconv(.c) void { // 82904f
    c.FloodDam_PrepFloodHDMA();
    t.kWatergateFuncs[v.subsubmodule_index.*].?();
}

pub export fn Module07_0E_SpiralStairs() callconv(.c) void { // 829054
    if (v.subsubmodule_index.* >= 7) {
        c.Graphics_IncrementalVRAMUpload();
        c.Dungeon_LoadAttribute_Selectable();
    }
    HandleLinkOnSpiralStairs();
    t.kDungeon_SpiralStaircase[v.subsubmodule_index.*].?();
}

pub export fn Dungeon_DoubleApplyAndIncrementGrayscale() callconv(.c) void { // 829094
    c.ApplyPaletteFilter_bounce();
    c.ApplyPaletteFilter_bounce();
    c.ApplyGrayscaleFixed_Incremental();
}

pub export fn Module07_0E_02_ApplyFilterIf() callconv(.c) void { // 8290a1
    if (v.staircase_var1.* < 9) {
        c.ApplyPaletteFilter_bounce();
        if (v.palette_filter_countdown.* != 0)
            c.ApplyPaletteFilter_bounce();
    }
    if (v.staircase_var1.* != 0) {
        v.staircase_var1.* -%= 1;
        return;
    }
    v.link_visibility_status.* = 12;
    v.tagalong_var5.* = 12;
}

pub export fn Dungeon_SyncBackgroundsFromSpiralStairs() callconv(.c) void { // 8290c7
    if (v.follower_indicator.* == 6 and low(v.dungeon_room_index).* == 100)
        v.follower_indicator.* = 0;
    const bak = v.link_is_on_lower_level.*;
    v.link_y_coord.* +%= @bitCast(@as(i16, if (v.which_staircase_index.* & 4 != 0) 48 else -48));
    v.link_is_on_lower_level.* = @bitCast(t.kTeleportPitLevel2[v.cur_staircase_plane.*]);
    SpiralStairs_MakeNearbyWallsHighPriority_Exiting();
    v.link_is_on_lower_level.* = bak;
    v.link_y_coord.* +%= @bitCast(@as(i16, if (v.which_staircase_index.* & 4 != 0) -48 else 48));
    v.BG1HOFS_copy2.* = v.BG2HOFS_copy2.*;
    v.BG1VOFS_copy2.* = v.BG2VOFS_copy2.*;
    c.Dungeon_AdjustForRoomLayout();
    snapRoomCameraX();
    var ts: u8 = @bitCast(t.kSpiralTab1[v.dung_hdr_bg2_properties.*]);
    var tm: u8 = 0x16;
    if (sign8(ts)) {
        tm = 0x17;
        ts = 0;
    }
    if (v.dung_hdr_bg2_properties.* == 2)
        ts = 3;
    v.TM_copy.* = tm;
    v.TS_copy.* = ts;
    v.dung_cur_floor.* +%= if (v.which_staircase_index.* & 4 != 0) 0xff else 1;
    v.staircase_var1.* = 24;
    c.Dungeon_PlayBlipAndCacheQuadrantVisits();
    c.Hud_RestoreTorchBackground();
    c.Dungeon_InterRoomTrans_notDarkRoom();
}

pub export fn Dungeon_AdvanceThenSetBossMusicUnorthodox() callconv(.c) void { // 82915b
    c.Dungeon_ResetTorchBackgroundAndPlayerInner();
    v.staircase_var1.* = 0x38;
    v.subsubmodule_index.* +%= 1;
    Dungeon_SetBossMusicUnorthodox();
}

pub export fn Dungeon_SetBossMusicUnorthodox() callconv(.c) void { // 829165
    var x: u8 = 0x1c;
    if (v.dungeon_room_index.* != 16) {
        x = 0x15;
        if (v.dungeon_room_index.* != 7) {
            x = 0x11;
            if (v.dungeon_room_index.* != 23 or c.ZeldaIsPlayingMusicTrack(17))
                return;
        }
        if (v.music_unk1.* != 0xf1 and (v.link_which_pendants.* & 1) != 0)
            return;
    }
    v.music_control.* = x;
}

pub export fn Dungeon_SpiralStaircase17() callconv(.c) void { // 82919b
    SpiralStairs_FindLandingSpot();
    v.staircase_var1.* -%= 1;
    if (v.staircase_var1.* == 0) {
        v.staircase_var1.* = if (v.which_staircase_index.* & 4 != 0) 10 else 24;
        v.subsubmodule_index.* +%= 1;
    }
}

pub export fn Dungeon_SpiralStaircase18() callconv(.c) void { // 8291b5
    SpiralStairs_FindLandingSpot();
    v.staircase_var1.* -%= 1;
    if (v.staircase_var1.* == 0) {
        v.subsubmodule_index.* +%= 1;
        v.overworld_map_state.* = 0;
    }
}

pub export fn Module07_0E_00_InitPriorityAndScreens() callconv(.c) void { // 8291c4
    c.SpiralStairs_MakeNearbyWallsHighPriority_Entering();
    if (v.link_is_on_lower_level.* != 0) {
        v.TM_copy.* &= 0xf;
        v.TS_copy.* |= 0x10;
        v.link_is_on_lower_level.* = 3;
    }
    v.subsubmodule_index.* +%= 1;
}

pub export fn Module07_0E_13_SetRoomAndLayerAndCache() callconv(.c) void { // 8291dd
    v.link_is_on_lower_level_mirror.* = @bitCast(t.kTeleportPitLevel1[v.cur_staircase_plane.*]);
    v.link_is_on_lower_level.* = @bitCast(t.kTeleportPitLevel2[v.cur_staircase_plane.*]);
    v.TM_copy.* |= 0x10;
    v.TS_copy.* &= 0xf;
    if (v.which_staircase_index.* & 4 == 0)
        c.SpiralStairs_MakeNearbyWallsLowPriority();
    low(v.dungeon_room_index2).* = low(v.dungeon_room_index).*;
    c.ResetThenCacheRoomEntryProperties();
}

pub export fn RepositionLinkAfterSpiralStairs() callconv(.c) void { // 82921a
    v.link_visibility_status.* = 0;
    v.tagalong_var5.* = 0;

    var i: usize = if (v.cur_staircase_plane.* == 0 and v.byte_7E0492.* != 0) 1 else 0;
    i += if (v.which_staircase_index.* & 4 != 0) @as(usize, 2) else 0;

    v.link_x_coord.* +%= u16w(t.kSpiralStaircaseX[i]);
    v.link_y_coord.* +%= u16w(t.kSpiralStaircaseY[i]);

    if (v.TM_copy.* & 0x10 != 0) {
        if (v.cur_staircase_plane.* == 2) {
            v.link_is_on_lower_level.* = 3;
            v.TM_copy.* &= 0xf;
            v.TS_copy.* |= 0x10;
            if (v.byte_7E0492.* != 2)
                v.link_y_coord.* +%= 24;
        }
        c.Follower_Initialize();
    } else {
        if (v.cur_staircase_plane.* != 2) {
            v.TM_copy.* |= 0x10;
            v.TS_copy.* &= 0xf;
            if (v.byte_7E0492.* != 2)
                v.link_y_coord.* -%= 24;
        }
        c.Follower_Initialize();
    }
}

pub export fn SpiralStairs_MakeNearbyWallsHighPriority_Exiting() callconv(.c) void { // 8292b1
    if (v.which_staircase_index.* & 4 != 0)
        return;
    const lf: c_int = (@as(c_int, v.word_7E048C.*) + 8) & 0x7f;
    var x: usize = 0;
    var p: c_int = 0;
    while (true) {
        p = v.dung_inter_starcases[x];
        if (((p * 2) & 0x7f) == lf)
            break;
        x += 1;
    }
    p -= 4;
    v.word_7E048C.* = u16w(p * 2);
    var dst: usize = index(p);
    for (0..5) |_| {
        v.dung_bg2[dst + xy(0, 0)] |= 0x2000;
        v.dung_bg2[dst + xy(0, 1)] |= 0x2000;
        v.dung_bg2[dst + xy(0, 2)] |= 0x2000;
        v.dung_bg2[dst + xy(0, 3)] |= 0x2000;
        dst += 1;
    }
}

pub export fn Module07_0F_LandingWipe() callconv(.c) void { // 82931d
    t.kDungeon_Submodule_F[v.subsubmodule_index.*].?();
    c.Link_HandleMovingAnimation_FullLongEntry();
    c.LinkOam_Main();
}

pub export fn Module07_0F_00_InitSpotlight() callconv(.c) void { // 82932d
    c.Spotlight_open();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Module07_0F_01_OperateSpotlight() callconv(.c) void { // 829334
    c.Sprite_Main();
    c.IrisSpotlight_ConfigureTable();
    if (v.submodule_index.* == 0) {
        v.W12SEL_copy.* = 0;
        v.W34SEL_copy.* = 0;
        v.WOBJSEL_copy.* = 0;
        v.TMW_copy.* = 0;
        v.TSW_copy.* = 0;
        v.subsubmodule_index.* = 0;
        if (v.queued_music_control.* != 0xff)
            v.music_control.* = v.queued_music_control.*;
    }
}

// This is used for straight inter room stairs for example stairs to throne room in first dung
pub export fn Module07_11_StraightInterroomStairs() callconv(.c) void { // 829357
    if (v.subsubmodule_index.* >= 3)
        c.Dungeon_LoadAttribute_Selectable();
    if (v.subsubmodule_index.* >= 13)
        c.Graphics_IncrementalVRAMUpload();
    if (v.staircase_var1.* != 0) {
        const old = v.staircase_var1.*;
        v.staircase_var1.* = old -% 1;
        if (old == 16)
            v.link_speed_modifier.* = 2;
        v.link_direction.* = if (v.submodule_index.* == 18) 8 else 4;
        c.Link_HandleVelocity();
    }
    c.Link_HandleMovingAnimation_FullLongEntry();
    t.kDungeon_StraightStairs[v.subsubmodule_index.*].?();
}

pub export fn Module07_11_00_PrepAndReset() callconv(.c) void { // 8293bb
    if (v.link_is_running.* != 0) {
        v.link_is_running.* = 0;
        v.link_speed_setting.* = 2;
    }
    v.sound_effect_1.* = if (v.which_staircase_index.* & 4 != 0) 24 else 22;
    if (v.dungeon_room_index.* == 48 or v.dungeon_room_index.* == 64)
        v.music_control.* = 0xf1;
    c.ResetTransitionPropsAndAdvance_ResetInterface();
}

pub export fn Module07_11_01_FadeOut() callconv(.c) void { // 8293ed
    if (v.staircase_var1.* < 9) {
        c.ApplyPaletteFilter_bounce();
        if (low(v.palette_filter_countdown).* == 23)
            v.subsubmodule_index.* +%= 1;
    }
}

pub export fn Module07_11_02_LoadAndPrepRoom() callconv(.c) void { // 829403
    c.ApplyPaletteFilter_bounce();
    c.Dungeon_LoadRoom();
    c.Dungeon_RestoreStarTileChr();
    c.LoadTransAuxGFX();
    c.Dungeon_LoadCustomTileAttr();
    c.Dungeon_AdjustForRoomLayout();
    c.Follower_Initialize();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Module07_11_03_FilterAndLoadBGChars() callconv(.c) void { // 829422
    c.ApplyPaletteFilter_bounce();
    c.DungeonTransition_TriggerBGC34UpdateAndAdvance();
}

pub export fn Module07_11_04_FilterDoBGAndResetSprites() callconv(.c) void { // 82942a
    c.ApplyPaletteFilter_bounce();
    c.DungeonTransition_TriggerBGC56UpdateAndAdvance();
    low(v.dungeon_room_index2).* = low(v.dungeon_room_index).*;
    c.Dungeon_ResetSprites();
}

pub export fn Module07_11_0B_PrepDestination() callconv(.c) void { // 82943b
    var ts: u8 = @bitCast(t.kSpiralTab1[v.dung_hdr_bg2_properties.*]);
    var tm: u8 = 0x16;
    if (sign8(ts)) {
        tm = 0x17;
        ts = 0;
    }
    v.TM_copy.* = tm;
    v.TS_copy.* = ts;

    v.link_speed_modifier.* = 1;
    v.dung_cur_floor.* +%= if (v.which_staircase_index.* & 4 != 0) 0xff else 1;
    v.staircase_var1.* = if (v.which_staircase_index.* & 4 != 0) 0x32 else 0x3c;
    v.sound_effect_1.* = if (v.which_staircase_index.* & 4 != 0) 25 else 23;

    var r0: u8 = 0;
    if (v.link_is_on_lower_level.* != 0) {
        v.link_y_coord.* +%= @bitCast(@as(i16, if (v.submodule_index.* == 18) -32 else 32));
        r0 +%= 1;
    }
    v.link_is_on_lower_level_mirror.* = @bitCast(t.kTeleportPitLevel1[v.cur_staircase_plane.*]);
    v.link_is_on_lower_level.* = @bitCast(t.kTeleportPitLevel2[v.cur_staircase_plane.*]);
    if (v.link_is_on_lower_level.* != 0) {
        v.link_y_coord.* +%= @bitCast(@as(i16, if (v.submodule_index.* == 18) -32 else 32));
        r0 +%= 1;
    }

    if (r0 == 0) {
        if (v.submodule_index.* == 18) {
            v.link_y_coord.* +%= @bitCast(@as(i16, if (v.which_staircase_index.* & 4 != 0) -24 else -8));
        } else {
            v.link_y_coord.* +%= 12;
        }
    }

    c.Dungeon_PlayBlipAndCacheQuadrantVisits();
    c.Hud_RestoreTorchBackground();
    c.Dungeon_InterRoomTrans_notDarkRoom();
}

pub export fn Module07_11_09_LoadSpriteGraphics() callconv(.c) void { // 8294e0
    c.ApplyPaletteFilter_bounce();
    v.subsubmodule_index.* -%= 1;
    c.LoadNewSpriteGFXSet();
    c.Dungeon_HandleTranslucencyAndPalette();
}

pub export fn Module07_11_19_SetSongAndFilter() callconv(.c) void { // 8294ed
    if (v.overworld_map_state.* == 5 and low(v.darkening_or_lightening_screen).* == 0) {
        v.subsubmodule_index.* +%= 1;
        if (v.dungeon_room_index.* == 48) {
            v.music_control.* = 0x1c;
        } else if (v.dungeon_room_index.* == 64) {
            v.music_control.* = 0x10;
        }
    }
    c.ApplyGrayscaleFixed_Incremental();
}

pub export fn Module07_11_11_KeepSliding() callconv(.c) void { // 829518
    if (v.staircase_var1.* == 0) {
        v.subsubmodule_index.* +%= 1;
    } else {
        c.ApplyGrayscaleFixed_Incremental();
    }
}

pub export fn Module07_14_RecoverFromFall() callconv(.c) void { // 829520
    switch (v.subsubmodule_index.*) {
        0 => Module07_14_00_ScrollCamera(),
        1 => c.RecoverPositionAfterDrowning(),
        else => {},
    }
}

pub export fn Module07_14_00_ScrollCamera() callconv(.c) void { // 82952a
    for (0..2) |_| {
        if (v.BG2HOFS_copy2.* != v.BG2HOFS_copy2_cached.*)
            v.BG2HOFS_copy2.* +%= if (v.BG2HOFS_copy2.* < v.BG2HOFS_copy2_cached.*) 1 else 0xffff;
        if (v.BG2VOFS_copy2.* != v.BG2VOFS_copy2_cached.*)
            v.BG2VOFS_copy2.* +%= if (v.BG2VOFS_copy2.* < v.BG2VOFS_copy2_cached.*) 1 else 0xffff;
    }
    if (v.BG2HOFS_copy2.* == v.BG2HOFS_copy2_cached.* and v.BG2VOFS_copy2.* == v.BG2VOFS_copy2_cached.*)
        v.subsubmodule_index.* +%= 1;
    if (v.hdr_dungeon_dark_with_lantern.* == 0)
        c.MirrorBg1Bg2Offs();
}

pub export fn Module07_15_WarpPad() callconv(.c) void { // 82967a
    if (v.subsubmodule_index.* >= 3) {
        c.Graphics_IncrementalVRAMUpload();
        c.Dungeon_LoadAttribute_Selectable();
    }
    t.kDungeon_Teleport[v.subsubmodule_index.*].?();
}

pub export fn Module07_15_01_ApplyMosaicAndFilter() callconv(.c) void { // 8296ac
    c.ConditionalMosaicControl();
    v.MOSAIC_copy.* = v.mosaic_level.* | 3;
    c.ApplyPaletteFilter_bounce();
}

pub export fn Module07_15_04_SyncRoomPropsAndBuildOverlay() callconv(.c) void { // 8296ba
    c.ApplyGrayscaleFixed_Incremental();
    if (v.dungeon_room_index.* == 0x17)
        v.dung_cur_floor.* = 4;
    c.MirrorBg1Bg2Offs();
    c.Dungeon_AdjustForRoomLayout();
    snapRoomCameraX();
    var ts: u8 = @bitCast(t.kSpiralTab1[v.dung_hdr_bg2_properties.*]);
    var tm: u8 = 0x16;
    if (sign8(ts)) {
        tm = 0x17;
        ts = 0;
    }
    v.TM_copy.* = tm;
    v.TS_copy.* = ts;
    c.WaterFlood_BuildOneQuadrantForVRAM();
    v.subsubmodule_index.* +%= 1;
}

pub export fn Module07_15_0E_FadeInFromWarp() callconv(.c) void { // 8296ec
    if (v.palette_filter_countdown.* & 1 != 0 and v.mosaic_level.* != 0)
        v.mosaic_level.* -%= 0x10;
    v.BGMODE_copy.* = 9;
    v.MOSAIC_copy.* = v.mosaic_level.* | 3;
    c.ApplyPaletteFilter_bounce();
}

pub export fn Module07_15_0F_FinalizeAndCacheEntry() callconv(.c) void { // 82970f
    if (v.overworld_map_state.* == 5) {
        c.SetAndSaveVisitedQuadrantFlags();
        v.submodule_index.* = 0;
        c.ResetThenCacheRoomEntryProperties();
    }
}

pub export fn Module07_16_UpdatePegs() callconv(.c) void { // 82972a
    v.subsubmodule_index.* +%= 1;
    if (v.subsubmodule_index.* & 3 != 0)
        return;
    switch (v.subsubmodule_index.* >> 2) {
        0, 1 => c.Module07_16_UpdatePegs_Step1(),
        2 => c.Module07_16_UpdatePegs_Step2(),
        3 => c.RecoverPegGFXFromMapping(),
        4 => {
            c.Dungeon_FlipCrystalPegAttribute();
            v.subsubmodule_index.* = 0;
            v.submodule_index.* = 0;
        },
        else => {},
    }
}

pub export fn Module07_17_PressurePlate() callconv(.c) void { // 8297c8
    v.subsubmodule_index.* -%= 1;
    if (v.subsubmodule_index.* != 0)
        return;
    v.link_y_coord.* -%= 2;
    c.Dungeon_UpdateTileMapWithCommonTile(@as(c_int, v.word_7E04B6.* & 0x3f) << 3, (@as(c_int, v.word_7E04B6.*) >> 3) & 0x1f8, 0xe);
    v.submodule_index.* = v.saved_module_for_menu.*;
}

pub export fn Module07_18_RescuedMaiden() callconv(.c) void { // 82980a
    switch (v.subsubmodule_index.*) {
        0 => {
            c.PaletteFilter_RestoreBGSubstractiveStrict();
            v.main_palette_buffer[0] = v.main_palette_buffer[32];
            if (low(v.darkening_or_lightening_screen).* != 255)
                return;
            for (0..0x1000) |i| {
                v.dung_bg1[i] = 0x1ec;
                v.dung_bg2[i] = 0x1ec;
            }
            v.bg1_y_offset.* = 0;
            v.bg1_x_offset.* = 0;
            v.dung_floor_x_offs.* = 0;
            v.dung_floor_y_offs.* = 0;
            v.overworld_screen_transition.* = 0;
            v.dung_cur_quadrant_upload.* = 0;
            v.subsubmodule_index.* +%= 1;
        },
        1 => {
            c.PaletteFilter_Crystal();
            v.TS_copy.* = 1;
            v.flag_is_link_immobilized.* = 2;
            const j = FindInWordArray_p6(&t.kBossRooms, v.dungeon_room_index.*, t.kBossRooms.len) - 4;
            var dst: usize = kCrystal_Tab0[index(j)] >> 1;
            var tt: u16 = 0;
            for (0..4) |_| {
                for (0..8) |i| {
                    v.dung_bg1[dst + i + xy(0, 0)] = 0x1f80 | tt;
                    v.dung_bg1[dst + i + xy(0, 4)] = 0x1f88 | tt;
                    tt +%= 1;
                }
                tt +%= 8;
                dst += xy(0, 1);
            }
            v.subsubmodule_index.* +%= 1;
        },
        2, 4, 6, 8 => c.Dungeon_InterRoomTrans_notDarkRoom(),
        3, 5, 7, 9 => c.Dungeon_InterRoomTrans_State4(),
        10 => {
            v.is_nmi_thread_active.* +%= 1;
            c.Polyhedral_InitializeThread();
            c.CrystalCutscene_Initialize();
            v.submodule_index.* = 0;
            v.subsubmodule_index.* = 0;
        },
        else => {},
    }
}

pub export fn Module07_19_MirrorFade() callconv(.c) void { // 8298f7
    // When using mirror
    c.Overworld_ResetMosaic_alwaysIncrease();
    v.INIDISP_copy.* -%= 1;
    if (v.INIDISP_copy.* == 0) {
        v.main_module_index.* = 5;
        v.submodule_index.* = 0;
        v.nmi_load_bg_from_vram.* = 0;
        v.last_music_control.* = v.music_unk1.*;
        if (v.palette_swap_flag.* != 0)
            c.Palette_RevertTranslucencySwap();
    }
}

pub export fn Module07_1A_RoomDraw_OpenTriforceDoor_bounce() callconv(.c) void { // 829916
    v.flag_is_link_immobilized.* = 1;
    if (v.R16.* != 0) {
        low(v.R16).* -%= 1;
        if (low(v.R16).* != 0)
            return;
        high(v.R16).* -%= 1;
        if (high(v.R16).* != 0)
            return;
        v.sound_effect_ambient.* = 21;
        v.link_force_hold_sword_up.* = 0;
        v.link_cant_change_direction.* = 0;
    }
    v.flag_is_link_immobilized.* = 0;
    v.subsubmodule_index.* +%= 1;
    if (v.subsubmodule_index.* & 3 != 0)
        return;

    var src = SrcPtr(kOpenGanonDoor_Tab[index((v.subsubmodule_index.* -% 4) >> 2)]);
    var dst: usize = 0;
    for (0..8) |_| {
        v.dung_bg2[dst + xy(44, 3)] = src[0];
        v.dung_bg2[dst + xy(44, 4)] = src[1];
        v.dung_bg2[dst + xy(44, 5)] = src[2];
        v.dung_bg2[dst + xy(44, 6)] = src[3];
        dst += xy(1, 0);
        src += 4;
    }

    _ = c.Dungeon_PrepOverlayDma_watergate(0, 0x1d8, 0x881, 8);
    if (v.subsubmodule_index.* == 16) {
        writeAttr2_p6(xy(44, 5), 0x202);
        writeAttr2_p6(xy(44, 6), 0x202);
        writeAttr2_p6(xy(50, 5), 0x200);
        writeAttr2_p6(xy(50, 6), 0x200);
        var i: usize = 0;
        while (i != 6) : (i += 2) {
            writeAttr2_p6(xy(45 + i, 0), 0x0);
            writeAttr2_p6(xy(45 + i, 1), 0x0);
            writeAttr2_p6(xy(45 + i, 2), 0x0);
            writeAttr2_p6(xy(45 + i, 3), 0x0);
            writeAttr2_p6(xy(45 + i, 4), 0x0);
            writeAttr2_p6(xy(45 + i, 5), 0x0);
            writeAttr2_p6(xy(45 + i, 6), 0x0);
        }
        v.room_bounds_y.named.a0 = @bitCast(@as(i16, -64));
        v.submodule_index.* = 0;
        v.subsubmodule_index.* = 0;
    }
    v.nmi_copy_packets_flag.* = 1;
}

pub export fn Module11_DungeonFallingEntrance() callconv(.c) void { // 829af9
    const ssi = v.subsubmodule_index.*;
    switch (ssi) {
        0 => { // Module_11_00_SetSongAndInit
            if (asset8_p6(27)[v.which_entrance.*] != 3 or v.sram_progress_indicator.* >= 2)
                v.music_control.* = 0xf1;
            c.ResetTransitionPropsAndAdvance_ResetInterface();
        },
        1 => {
            if (v.frame_counter.* & 1 == 0)
                c.ApplyPaletteFilter_bounce();
        },
        2 => Module11_02_LoadEntrance(),
        3 => c.DungeonTransition_LoadSpriteGFX(),
        4, 5 => {
            if (ssi == 4) {
                v.INIDISP_copy.* = (v.INIDISP_copy.* +% 1) & 0xf;
                if (v.INIDISP_copy.* == 15)
                    v.subsubmodule_index.* +%= 1;
                // fall through
            }
            c.HandleDungeonLandingFromPit();
            if (v.submodule_index.* != 0)
                return;
            v.main_module_index.* = 7;
            dungeon_wide.noteFellIn();
            v.flag_skip_call_tag_routines.* +%= 1;
            c.Dungeon_PlayBlipAndCacheQuadrantVisits();
            c.ResetThenCacheRoomEntryProperties();
            v.music_control.* = v.queued_music_control.*;
            v.last_music_control.* = v.music_unk1.*;
        },
        else => {},
    }
}

pub export fn Module11_02_LoadEntrance() callconv(.c) void { // 829b1c
    c.EnableForceBlank();
    v.CGWSEL_copy.* = 2;
    Dungeon_LoadEntrance();

    const dung = low(v.cur_palace_index_x2).*;
    v.link_num_keys.* = if (dung != 255) v.link_keys_earned_per_dungeon[index(@as(u8, if (dung == 2) 0 else dung) >> 1)] else 255;
    c.Hud_Rebuild();
    v.link_this_controls_sprite_oam.* = 4;
    v.player_near_pit_state.* = 3;
    v.link_visibility_status.* = 12;
    v.link_speed_modifier.* = 16;

    const y: u8 = @truncate(v.link_y_coord.* -% v.BG2VOFS_copy2.*);
    v.link_state_bits.* = 0;
    v.link_picking_throw_state.* = 0;
    v.some_animation_timer.* = 0;
    v.dungeon_room_index_prev.* = v.dungeon_room_index.*;
    v.tiledetect_which_y_pos[0] = v.link_y_coord.*;
    v.link_y_coord.* -%= @as(u16, y) +% 16;

    const bak = v.subsubmodule_index.*;
    v.dung_num_lit_torches.* = 0;
    v.hdr_dungeon_dark_with_lantern.* = 0;
    Dungeon_LoadAndDrawRoom();
    dungeon_wide.noteRoomShown();
    snapRoomCameraX();
    c.Dungeon_LoadCustomTileAttr();
    c.DecompressAnimatedDungeonTiles(t.kDungAnimatedTiles[v.main_tile_theme_index.*]);
    c.Dungeon_LoadAttributeTable();
    v.subsubmodule_index.* = bak +% 1;
    v.misc_sprites_graphics_index.* = 10;
    c.InitializeTilesets();
    v.palette_sp6r_indoors.* = 10;
    c.Dungeon_LoadPalettes();
    c.Hud_RestoreTorchBackground();
    v.button_mask_b_y.* = 0;
    v.button_b_frames.* = 0;
    c.Dungeon_ResetTorchBackgroundAndPlayer();
    if (v.link_is_bunny_mirror.* != 0)
        c.LoadGearPalettes_bunny();
    v.HDMAEN_copy.* = 0x80;
    c.Hud_RefillLogic();
    c.Module_PreDungeon_setAmbientSfx();
    v.submodule_index.* = 7;
    Dungeon_LoadSongBankIfNeeded();
}

pub export fn Dungeon_LoadSongBankIfNeeded() callconv(.c) void { // 829bd7
    if (v.queued_music_control.* == 0xff or v.queued_music_control.* == 0xf2)
        return;

    if (v.queued_music_control.* == 3 or v.queued_music_control.* == 7 or v.queued_music_control.* == 14) {
        c.LoadOWMusicIfNeeded();
    } else {
        if (v.flag_which_music_type.* != 0)
            return;
        v.flag_which_music_type.* = 1;
        c.LoadDungeonSongs();
    }
}

// This gets called when entering a dungeon from ow.
pub export fn Dungeon_LoadAndDrawRoom() callconv(.c) void { // 82c57b
    const bak: c_int = v.HDMAEN_copy.*;
    v.HDMAEN_copy.* = 0;
    c.Dungeon_LoadRoom();
    v.overworld_screen_transition.* = 0;
    v.overworld_map_state.* = 0;
    v.dung_cur_quadrant_upload.* = 0;
    while (v.dung_cur_quadrant_upload.* != 16) {
        c.TileMapPrep_NotWaterOnTag();
        c.NMI_UploadTilemap();
        c.Dungeon_PrepareNextRoomQuadrantUpload();
        c.NMI_UploadTilemap();
    }
    v.HDMAEN_copy.* = @truncate(@as(u32, @bitCast(bak)));
    v.nmi_subroutine_index.* = 0;
    v.overworld_map_state.* = 0;
    v.subsubmodule_index.* = 0;
}

pub export fn Dungeon_LoadEntrance() callconv(.c) void { // 82d8b3
    v.player_is_indoors.* = 1;

    if (v.death_var5.* != 0) {
        v.death_var5.* = 0;
    } else {
        v.overworld_area_index_exit.* = v.overworld_area_index.*;
        v.TM_copy_exit.* = word(v.TM_copy).*;
        v.BG2VOFS_copy2_exit.* = v.BG2VOFS_copy2.*;
        v.BG2HOFS_copy2_exit.* = v.BG2HOFS_copy2.*;
        v.link_y_coord_exit.* = v.link_y_coord.*;
        v.link_x_coord_exit.* = v.link_x_coord.*;
        v.camera_y_coord_scroll_low_exit.* = v.camera_y_coord_scroll_low.*;
        v.camera_x_coord_scroll_low_exit.* = v.camera_x_coord_scroll_low.*;
        v.overworld_screen_index_exit.* = v.overworld_screen_index.*;
        v.map16_load_src_off_exit.* = v.map16_load_src_off.*;
        v.overworld_screen_index.* = 0;
        v.overlay_index.* = 0;
        v.ow_scroll_vars0_exit.* = v.ow_scroll_vars0.*;
        v.up_down_scroll_target_exit.* = v.up_down_scroll_target.*;
        v.up_down_scroll_target_end_exit.* = v.up_down_scroll_target_end.*;
        v.left_right_scroll_target_exit.* = v.left_right_scroll_target.*;
        v.left_right_scroll_target_end_exit.* = v.left_right_scroll_target_end.*;
        v.overworld_unk1_exit.* = v.overworld_unk1.*;
        v.overworld_unk1_neg_exit.* = v.overworld_unk1_neg.*;
        v.overworld_unk3_exit.* = v.overworld_unk3.*;
        v.overworld_unk3_neg_exit.* = v.overworld_unk3_neg.*;
        v.byte_7EC164.* = v.byte_7E0AA0.*;
        v.main_tile_theme_index_exit.* = v.main_tile_theme_index.*;
        v.aux_tile_theme_index_exit.* = v.aux_tile_theme_index.*;
        v.sprite_graphics_index_exit.* = v.sprite_graphics_index.*;
    }
    v.bg1_y_offset.* = 0;
    v.bg1_x_offset.* = 0;
    word(v.death_var5).* = 0;
    if (word(v.follower_indicator).* == 4 or word(v.death_var4).* != 0) {
        const i = index(v.which_starting_point.*);
        word(v.which_entrance).* = asset8_p6(44)[i];
        v.dungeon_room_index.* = asset16_p6(28)[i];
        v.dungeon_room_index2.* = v.dungeon_room_index.*;
        v.BG2VOFS_copy2.* = asset16_p6(31)[i];
        v.BG1VOFS_copy2.* = v.BG2VOFS_copy2.*;
        v.BG2VOFS_copy.* = v.BG2VOFS_copy2.*;
        v.BG1VOFS_copy.* = v.BG2VOFS_copy2.*;
        v.BG2HOFS_copy2.* = asset16_p6(30)[i];
        v.BG1HOFS_copy2.* = v.BG2HOFS_copy2.*;
        v.BG2HOFS_copy.* = v.BG2HOFS_copy2.*;
        v.BG1HOFS_copy.* = v.BG2HOFS_copy2.*;
        if (word(v.sram_progress_indicator).* != 0) {
            v.link_y_coord.* = asset16_p6(33)[i];
            v.link_x_coord.* = asset16_p6(32)[i];
        }
        v.camera_y_coord_scroll_low.* = asset16_p6(35)[i];
        v.camera_y_coord_scroll_hi.* = v.camera_y_coord_scroll_low.* +% 2;
        v.camera_x_coord_scroll_low.* = asset16_p6(34)[i];
        v.camera_x_coord_scroll_hi.* = v.camera_x_coord_scroll_low.* +% 2;
        v.tilemap_location_calc_mask.* = 0x1f8;
        v.ow_entrance_value.* = asset16_p6(43)[i];
        v.up_down_scroll_target.* = 0;
        v.up_down_scroll_target_end.* = 0x110;
        v.left_right_scroll_target.* = 0;
        v.left_right_scroll_target_end.* = 0x100;
        const rc = asset8_p6(29);
        v.room_bounds_y.named.a0 = @as(u16, rc[i * 8 + 0]) << 8;
        v.room_bounds_y.named.b0 = @as(u16, rc[i * 8 + 1]) << 8;
        v.room_bounds_y.named.a1 = @as(u16, rc[i * 8 + 2]) << 8 | 0x10;
        v.room_bounds_y.named.b1 = @as(u16, rc[i * 8 + 3]) << 8 | 0x10;
        v.room_bounds_x.named.a0 = @as(u16, rc[i * 8 + 4]) << 8;
        v.room_bounds_x.named.b0 = @as(u16, rc[i * 8 + 5]) << 8;
        v.room_bounds_x.named.a1 = @as(u16, rc[i * 8 + 6]) << 8;
        v.room_bounds_x.named.b1 = @as(u16, rc[i * 8 + 7]) << 8;

        v.link_direction_facing.* = 2;
        v.main_tile_theme_index.* = asset8_p6(36)[i];
        v.dung_cur_floor.* = asset8_p6(37)[i];
        low(v.cur_palace_index_x2).* = asset8_p6(38)[i];
        v.is_standing_in_doorway.* = 0;
        v.link_is_on_lower_level.* = asset8_p6(40)[i] >> 4;
        v.link_is_on_lower_level_mirror.* = asset8_p6(40)[i] & 0xf;
        v.quadrant_fullsize_x.* = asset8_p6(41)[i] >> 4;
        v.quadrant_fullsize_y.* = asset8_p6(41)[i] & 0xf;
        v.link_quadrant_x.* = asset8_p6(42)[i] >> 4;
        v.link_quadrant_y.* = asset8_p6(42)[i] & 0xf;

        v.queued_music_control.* = asset8_p6(45)[i];
        if (i == 0 and v.sram_progress_indicator.* == 0)
            v.queued_music_control.* = 0xff;
        v.death_var4.* = 0;
    } else {
        const i = index(v.which_entrance.*);
        v.dungeon_room_index.* = asset16_p6(11)[i];
        v.dungeon_room_index2.* = v.dungeon_room_index.*;
        v.BG2VOFS_copy2.* = asset16_p6(14)[i];
        v.BG1VOFS_copy2.* = v.BG2VOFS_copy2.*;
        v.BG2VOFS_copy.* = v.BG2VOFS_copy2.*;
        v.BG1VOFS_copy.* = v.BG2VOFS_copy2.*;
        v.BG2HOFS_copy2.* = asset16_p6(13)[i];
        v.BG1HOFS_copy2.* = v.BG2HOFS_copy2.*;
        v.BG2HOFS_copy.* = v.BG2HOFS_copy2.*;
        v.BG1HOFS_copy.* = v.BG2HOFS_copy2.*;
        if (word(v.sram_progress_indicator).* != 0) {
            v.link_y_coord.* = asset16_p6(16)[i];
            v.link_x_coord.* = asset16_p6(15)[i];
        }
        v.camera_y_coord_scroll_low.* = asset16_p6(18)[i];
        v.camera_y_coord_scroll_hi.* = v.camera_y_coord_scroll_low.* +% 2;
        v.camera_x_coord_scroll_low.* = asset16_p6(17)[i];
        v.camera_x_coord_scroll_hi.* = v.camera_x_coord_scroll_low.* +% 2;
        v.tilemap_location_calc_mask.* = 0x1f8;
        v.ow_entrance_value.* = asset16_p6(26)[i];
        v.big_rock_starting_address.* = 0;
        v.up_down_scroll_target.* = 0;
        v.up_down_scroll_target_end.* = 0x110;
        v.left_right_scroll_target.* = 0;
        v.left_right_scroll_target_end.* = 0x100;

        const rc = asset8_p6(12);
        v.room_bounds_y.named.a0 = @as(u16, rc[i * 8 + 0]) << 8;
        v.room_bounds_y.named.b0 = @as(u16, rc[i * 8 + 1]) << 8;
        v.room_bounds_y.named.a1 = @as(u16, rc[i * 8 + 2]) << 8 | 0x10;
        v.room_bounds_y.named.b1 = @as(u16, rc[i * 8 + 3]) << 8 | 0x10;

        v.room_bounds_x.named.a0 = @as(u16, rc[i * 8 + 4]) << 8;
        v.room_bounds_x.named.b0 = @as(u16, rc[i * 8 + 5]) << 8;
        v.room_bounds_x.named.a1 = @as(u16, rc[i * 8 + 6]) << 8;
        v.room_bounds_x.named.b1 = @as(u16, rc[i * 8 + 7]) << 8;

        v.link_direction_facing.* = if (i == 0 or i == 0x43) 2 else 0;
        v.main_tile_theme_index.* = asset8_p6(19)[i];
        v.queued_music_control.* = c.ZeldaGetEntranceMusicTrack(@intCast(i));
        if (v.queued_music_control.* == 3 and v.sram_progress_indicator.* >= 2)
            v.queued_music_control.* = 18;

        v.dung_cur_floor.* = asset8_p6(20)[i];
        low(v.cur_palace_index_x2).* = asset8_p6(21)[i];
        v.is_standing_in_doorway.* = asset8_p6(22)[i];
        v.link_is_on_lower_level.* = asset8_p6(23)[i] >> 4;
        v.link_is_on_lower_level_mirror.* = asset8_p6(23)[i] & 0xf;
        v.quadrant_fullsize_x.* = asset8_p6(24)[i] >> 4;
        v.quadrant_fullsize_y.* = asset8_p6(24)[i] & 0xf;
        v.link_quadrant_x.* = asset8_p6(25)[i] >> 4;
        v.link_quadrant_y.* = asset8_p6(25)[i] & 0xf;

        if (v.dungeon_room_index.* >= 0x100)
            v.dung_cur_floor.* = 0;
    }
    v.player_oam_x_offset.* = 0x80;
    v.player_oam_y_offset.* = 0x80;
    v.link_direction_mask_a.* = 0xf;
    v.link_direction_mask_b.* = 0xf;
    v.link_actual_vel_z.* = 0xff;
    low(v.link_z_coord).* = 0xff;
    const blocks: [*]u8 = @ptrCast(v.movable_block_datas);
    @memcpy(blocks[0..assetSize(53)], asset8_p6(53)[0..assetSize(53)]);
    @memcpy((blocks + 99 * 4)[0..116], asset8_p6(54)[0..116]); // junk
    const torches: [*]u8 = @ptrCast(v.dung_torch_data);
    @memcpy(torches[0..assetSize(54)], asset8_p6(54)[0..assetSize(54)]);
    @memcpy((torches + 144 * 2)[0..assetSize(55)], asset8_p6(55)[0..assetSize(55)]);

    @memset(@as([*]u8, @ptrCast(v.memorized_tile_addr))[0..0x100], 0);
    @memset(@as([*]u8, @ptrCast(v.pots_revealed_in_room))[0..0x280], 0);
    v.orange_blue_barrier_state.* = 0;
    v.byte_7E04BC.* = 0;
}

pub export fn PushBlock_Slide(j: u8) callconv(.c) void { // 87edb5
    if (v.submodule_index.* != 0)
        return;
    const i: usize = if ((@as(c_int, v.index_of_changable_dungeon_objs[1]) - 1) * 2 == @as(c_int, j)) 1 else 0;
    v.pushedblocks_maybe_timeout.* = 9;
    v.pushedblocks_some_index.* = 0;
    PushBlock_ApplyVelocity(@intCast(i));
    const y: u16 = @as(u16, @as(u8, @truncate(v.pushedblocks_y_lo[i]))) | @as(u16, @as(u8, @truncate(v.pushedblocks_y_hi[i]))) << 8;
    const x: u16 = @as(u16, @as(u8, @truncate(v.pushedblocks_x_lo[i]))) | @as(u16, @as(u8, @truncate(v.pushedblocks_x_hi[i]))) << 8;
    PushBlock_HandleCollision(@intCast(i), x, y);
}

pub export fn PushBlock_HandleFalling(y_: u8) callconv(.c) void { // 87edf9
    const y = y_ >> 1;

    v.pushedblocks_maybe_timeout.* -%= 1;
    if (!sign8(v.pushedblocks_maybe_timeout.*))
        return;

    v.pushedblocks_maybe_timeout.* = 9;

    v.pushedblocks_some_index.* +%= 1;
    if (v.pushedblocks_some_index.* == 4) {
        low(&v.dung_replacement_tile_state[y]).* = 0;
        v.pushedblocks_some_index.* = 0;
        const i: usize = if (@as(c_int, v.index_of_changable_dungeon_objs[1]) - 1 == @as(c_int, y)) 1 else 0;
        v.index_of_changable_dungeon_objs[i] = 0;
    }
}

pub export fn PushBlock_ApplyVelocity(i_: u8) callconv(.c) void { // 87ee35
    const i = index(i_);
    const m: u8 = kPushedBlockDirMask[index(@as(u8, @truncate(v.pushedblock_facing[i])) >> 1)];
    var o: u32 = undefined;
    v.link_actual_vel_x.* = 0;
    v.link_actual_vel_y.* = 0;
    if (m & 3 != 0) {
        const vel: i8 = if (m & 2 != 0) -12 else 12;
        v.link_actual_vel_x.* = @bitCast(vel);
        o = (@as(u32, v.pushedblocks_subpixel[i]) | @as(u32, v.pushedblocks_x_lo[i]) << 8 | @as(u32, v.pushedblocks_x_hi[i]) << 16) +% @as(u32, @bitCast(@as(i32, vel) * 16));
        v.pushedblocks_subpixel[i] = @as(u8, @truncate(o));
        v.pushedblocks_x_lo[i] = @as(u8, @truncate(o >> 8));
        v.pushedblocks_x_hi[i] = @as(u8, @truncate(o >> 16));
    } else {
        const vel: i8 = if (m & 8 != 0) -12 else 12;
        v.link_actual_vel_y.* = @bitCast(vel);
        o = (@as(u32, v.pushedblocks_subpixel[i]) | @as(u32, v.pushedblocks_y_lo[i]) << 8 | @as(u32, v.pushedblocks_y_hi[i]) << 16);
        o +%= @as(u32, @bitCast(@as(i32, vel) * 16));
        v.pushedblocks_subpixel[i] = @as(u8, @truncate(o));
        v.pushedblocks_y_lo[i] = @as(u8, @truncate(o >> 8));
        v.pushedblocks_y_hi[i] = @as(u8, @truncate(o >> 16));
    }
    if (((o >> 8) & 0xf) == @as(u8, @truncate(v.pushedblocks_target[i]))) {
        const j: usize = index(@as(c_int, v.index_of_changable_dungeon_objs[i]) - 1);
        v.dung_replacement_tile_state[j] +%= 1;
        v.link_cant_change_direction.* &= ~@as(u8, 0x4);
        v.bitmask_of_dragstate.* &= ~@as(u8, 0x4);
    }
    const x: u16 = @truncate(@as(u32, v.pushedblocks_x_lo[i]) | @as(u32, v.pushedblocks_x_hi[i]) << 8);
    const y: u16 = @truncate(@as(u32, v.pushedblocks_y_lo[i]) | @as(u32, v.pushedblocks_y_hi[i]) << 8);
    var j: isize = 15;
    while (j >= 0) : (j -= 1) {
        const ji = index(j);
        if (v.sprite_state[ji] >= 9) {
            const sx: u16 = @as(u16, v.sprite_x_lo[ji]) | @as(u16, v.sprite_x_hi[ji]) << 8;
            const sy: u16 = @as(u16, v.sprite_y_lo[ji]) | @as(u16, v.sprite_y_hi[ji]) << 8;
            if (x -% sx +% 0x10 < 0x20 and y -% sy +% 0x10 < 0x20) {
                v.sprite_F[ji] = 8;
                const k = index(@as(u8, @truncate(v.pushedblock_facing[i])) >> 1);
                v.sprite_x_recoil[ji] = kPushBlockTab1[k];
                v.sprite_y_recoil[ji] = kPushBlockTab2[k];
            }
        }
    }
}

pub export fn PushBlock_HandleCollision(i_: u8, x: u16, y: u16) callconv(.c) void { // 87efb9
    const i = index(i_);

    v.link_y_coord_safe_return_hi.* = @truncate(v.link_y_coord.* >> 8);
    v.link_x_coord_safe_return_hi.* = @truncate(v.link_x_coord.* >> 8);

    var dir: c_int = 3;
    var m: u8 = v.link_direction.* & 0xf;
    while (m & 1 == 0) {
        m >>= 1;
        dir -= 1;
        if (dir < 0)
            return;
    }
    const d = index(dir);
    const l: u16 = if (dir < 2) v.link_x_coord.* else v.link_y_coord.*;
    const o: u16 = if (dir < 2) x else y;

    const r0: u16 = l +% kPushBlock_A[d];
    const r2: u16 = l +% kPushBlock_B[d];
    const r4: u16 = o +% kPushBlock_C[d];
    const r6: u16 = o +% kPushBlock_D[d];

    const coord_p: *align(1) u16 = if (dir < 2) v.link_y_coord else v.link_x_coord;
    const r8: u16 = coord_p.* +% kPushBlock_E[d];
    const r10: u16 = (if (dir < 2) y else x) +% kPushBlock_F[d];

    v.bitmask_of_dragstate.* &= ~@as(u8, 4);

    if (r0 >= r4 and r0 < r6 or r2 >= r4 and r2 < r6) {
        if (@as(u16, v.link_direction_facing.*) == v.pushedblock_facing[i])
            v.bitmask_of_dragstate.* |= if (v.index_of_changable_dungeon_objs[i] != 0) @as(u8, 4) else 1;
        if (if (dir & 1 != 0) (r8 >= r10 and r8 -% r10 < 8) else (r8 -% r10 >= 0xfff8)) {
            coord_p.* -%= r8 -% r10;
            const vel_p: *u8 = if (dir & 2 != 0) v.link_x_vel else v.link_y_vel;
            vel_p.* -%= @truncate(r8 -% r10);
        }
    }
    c.HandleIndoorCameraAndDoors();
}

pub export fn Sprite_Dungeon_DrawAllPushBlocks() callconv(.c) void { // 87f0ac
    var i: isize = 1;
    while (i >= 0) : (i -= 1) {
        if (v.index_of_changable_dungeon_objs[index(i)] != 0)
            c.Sprite_HandlePushedBlocks_One(@intCast(i));
    }
}

pub export fn UsedForStraightInterRoomStaircase() callconv(.c) void { // 87f25a
    var i: isize = 9;
    while (true) {
        if (v.ancilla_type[index(i)] == 13)
            v.ancilla_type[index(i)] = 0;
        i -= 1;
        if (!(i >= 0))
            break;
    }
    if (v.link_animation_steps.* >= 5)
        v.link_animation_steps.* = 0;
    v.link_subpixel_x.* = 0;
    v.link_subpixel_y.* = 0;
    v.some_animation_timer_steps.* = 0;
    v.link_timer_push_get_tired.* = 28;
    v.countdown_timer_for_staircases.* = 32;
    v.link_disable_sprite_damage.* = 1;
    _ = c.Ancilla_Sfx2_Near(if (v.which_staircase_index.* & 4 != 0) 0x18 else 0x16);

    v.tiledetect_which_y_pos[1] = v.link_x_coord.* +% @as(u16, @bitCast(@as(i16, if (v.which_staircase_index.* & 4 != 0) -15 else 16)));
    v.tiledetect_which_y_pos[0] = v.link_y_coord.*;
}

pub export fn HandleLinkOnSpiralStairs() callconv(.c) void { // 87f2c1
    v.link_x_coord_prev.* = v.link_x_coord.*;
    v.link_y_coord_prev.* = v.link_y_coord.*;
    if (v.some_animation_timer_steps.* != 0)
        return;

    v.link_give_damage.* = 0;
    v.link_incapacitated_timer.* = 0;
    v.link_auxiliary_state.* = 0;

    if (v.which_staircase_index.* & 4 != 0) {
        v.link_actual_vel_y.* = @bitCast(@as(i8, -2));
        v.link_timer_push_get_tired.* -%= 1;
        if (sign8(v.link_timer_push_get_tired.*)) {
            v.link_timer_push_get_tired.* = 0;
            v.link_actual_vel_y.* = 0;
            v.link_actual_vel_x.* = @bitCast(@as(i8, -2));
        }
    } else {
        v.link_actual_vel_y.* = @bitCast(@as(i8, -2));
        v.link_timer_push_get_tired.* -%= 1;
        if (sign8(v.link_timer_push_get_tired.*)) {
            v.link_timer_push_get_tired.* = 0;
            v.link_actual_vel_y.* = @bitCast(@as(i8, -2));
            v.link_actual_vel_x.* = 2;
        }
    }
    c.Link_MovePosition();
    c.Link_HandleMovingAnimation_StartWithDash();
    if (v.link_timer_push_get_tired.* == 0) {
        v.countdown_timer_for_staircases.* -%= 1;
        if (sign8(v.countdown_timer_for_staircases.*)) {
            v.countdown_timer_for_staircases.* = 0;
            v.link_direction_facing.* = if (v.which_staircase_index.* & 4 != 0) 4 else 6;
        }
    }

    var xd: i8 = @bitCast(@as(u8, @truncate(v.link_x_coord.* -% v.tiledetect_which_y_pos[1])));
    if (xd < 0)
        xd = @bitCast(0 -% @as(u8, @bitCast(xd)));
    if (xd != 0)
        return;

    RepositionLinkAfterSpiralStairs();
    if (v.follower_indicator.* != 0)
        c.Follower_Initialize();

    v.tiledetect_which_y_pos[1] = v.link_x_coord.* +% @as(u16, @bitCast(@as(i16, if (v.which_staircase_index.* & 4 != 0) -8 else 12)));
    v.some_animation_timer_steps.* = 1;
    v.countdown_timer_for_staircases.* = 6;
    _ = c.Ancilla_Sfx2_Near(if (v.which_staircase_index.* & 4 != 0) 25 else 23);
}

pub export fn SpiralStairs_FindLandingSpot() callconv(.c) void { // 87f391
    v.link_give_damage.* = 0;
    v.link_incapacitated_timer.* = 0;
    v.link_auxiliary_state.* = 0;
    v.link_disable_sprite_damage.* = 0;
    v.link_x_coord_prev.* = v.link_x_coord.*;
    v.link_y_coord_prev.* = v.link_y_coord.*;
    v.countdown_timer_for_staircases.* -%= 1;
    if (sign8(v.countdown_timer_for_staircases.*)) {
        v.countdown_timer_for_staircases.* = 0;
        v.link_direction_facing.* = 2;
    }
    v.link_actual_vel_x.* = 4;
    v.link_actual_vel_y.* = 0;
    if (v.which_staircase_index.* & 4 != 0) {
        v.link_actual_vel_x.* = @bitCast(@as(i8, -4));
        v.link_actual_vel_y.* = 2;
    }
    if (v.some_animation_timer_steps.* == 2) {
        v.link_actual_vel_x.* = 0;
        v.link_actual_vel_y.* = 16;
    }
    c.Link_MovePosition();
    c.Link_HandleMovingAnimation_StartWithDash();
    if (@as(u8, @truncate(v.link_x_coord.*)) == @as(u8, @truncate(v.tiledetect_which_y_pos[1])))
        v.some_animation_timer_steps.* = 2;
}

