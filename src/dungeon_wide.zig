//! Widescreen dungeon transitions: two rooms side by side.
//!
//! A dungeon room is 512 pixels square, and so is the SNES's tilemap. Walking
//! from one room to the next, the game loads the new room over the old one a
//! quarter at a time, the quarters coming in where the scroll needs them, so
//! the tilemap only ever holds the half of each room either side of the door.
//! A 4:3 screen never shows more; a wider one shows whatever's left over past
//! them. So while a transition runs, the PPU gets its tiles for the two rooms
//! from here instead: the new room's straight from the room buffers, which the
//! game fills in full before the first quarter goes up, and the old room's
//! from a copy of those buffers taken just before the new room is decoded
//! over them. VRAM goes back to being the source once the transition's over
//! and it holds the whole room again.
//!
//! The margins get the same treatment: during a transition they're what they
//! were in the room being left at the start, what they'll be in the room
//! being entered at the end, and in between they change as fast as the scroll
//! goes, as far as the two rooms reach. No pops at either end.

const std = @import("std");
const vars = @import("variables.zig");
const overworld = @import("overworld.zig");
const snes_pkg = @import("snes");
const Ppu = snes_pkg.ppu_types.Ppu;
const ppu_mod = snes_pkg.ppu;

const kRoomTiles = 64 * 64;
/// The side of a room in pixels, and of the tilemap.
const kRoomSize = 512;

const Origin = struct { x: i32, y: i32 };

/// The room left behind, as the room buffers had it when it was, and where
/// it is.
var g_prev_bg1: [kRoomTiles]u16 = undefined;
var g_prev_bg2: [kRoomTiles]u16 = undefined;
var g_prev: ?Origin = null;

/// Where the room the room buffers hold is, in the scroll's coordinates.
/// From the camera, which is always inside the room it's showing: a room's
/// number says where it is in the dungeon, but not where the scroll has it,
/// and a teleport door moves the scroll to make the next room seem next
/// door when it isn't.
var g_shown: ?Origin = null;
/// The room number the buffers hold, to tell a fall's room is loaded.
var g_shown_room: ?u16 = null;

/// Where the camera was and what the margins were, by the room's own rules,
/// in the room being left as the transition started, and which way it goes.
var g_start: ?struct { dir: u8, cam_x: i32, cam_y: i32, left: i32, right: i32 } = null;

/// Whether this runs at all: widescreen, with the widescreen camera on.
pub fn enabled() bool {
    return overworld.wideCameraOn();
}

/// The room the camera's in.
fn cameraRoom() Origin {
    const x: i32 = vars.BG2HOFS_copy2.*;
    const y: i32 = vars.BG2VOFS_copy2.*;
    return .{ .x = x & ~@as(i32, kRoomSize - 1), .y = y & ~@as(i32, kRoomSize - 1) };
}

/// The buffers hold the room the camera's in: coming in from outside or
/// falling in, and every frame the player walks around one (a snapshot can
/// start anywhere).
pub fn noteRoomShown() void {
    g_shown = cameraRoom();
    g_shown_room = vars.dungeon_room_index.*;
}

/// A frame of play in the room.
pub fn notePlayFrame() void {
    noteRoomShown();
    if (vars.hdr_dungeon_dark_with_lantern.* == 0) g_lantern_up = false;
    if (g_fall_frames != 0) g_fall_frames -= 1;
}

/// Keeps the room about to be loaded over, just before it is. The camera's
/// still in it.
pub fn keepRoomBeingLeft() void {
    @memcpy(&g_prev_bg1, vars.dung_bg1[0..kRoomTiles]);
    @memcpy(&g_prev_bg2, vars.dung_bg2[0..kRoomTiles]);
    g_prev = cameraRoom();
}

/// The next room's in the buffers: next to the one left, the way the
/// transition goes.
pub fn noteNextRoomLoaded() void {
    g_shown_room = vars.dungeon_room_index.*;
    const prev = g_prev orelse {
        g_shown = null;
        return;
    };
    const s = g_start orelse {
        g_shown = null;
        return;
    };
    g_shown = switch (s.dir) {
        0 => .{ .x = prev.x, .y = prev.y + kRoomSize },
        1 => .{ .x = prev.x, .y = prev.y - kRoomSize },
        2 => .{ .x = prev.x + kRoomSize, .y = prev.y },
        else => .{ .x = prev.x - kRoomSize, .y = prev.y },
    };
}

/// Where the room being entered is, for the camera's end of a scroll.
pub fn shownOrigin() ?Origin {
    return g_shown;
}

/// A room-to-room scroll, once the new room's in the buffers.
fn inTransition() bool {
    return vars.main_module_index.* == 7 and vars.submodule_index.* == 2 and
        vars.subsubmodule_index.* >= 2;
}

fn prevOrigin() ?Origin {
    return g_prev;
}

/// Falling into a dungeon through a hole, once the room's loaded: the game
/// uploads the part of it a 4:3 camera would see first, and the rest while
/// Link lands, and the widescreen camera sees past that part.
fn fallingIn() bool {
    return vars.main_module_index.* == 17 and vars.subsubmodule_index.* >= 3 and
        g_shown_room != null and g_shown_room.? == vars.dungeon_room_index.*;
}

/// Frames after the fall is over that the rest of the room might still be
/// on its way up: the frame the player gets control is one.
var g_fall_frames: u8 = 0;
const kFallFrames = 2;

/// The fall's over and the room's the player's.
pub fn noteFellIn() void {
    g_fall_frames = kFallFrames;
}

/// A dark room with the lantern's light up. The light is background layer 1
/// on the subscreen: a 512 pixel map of four 256 pixel pictures of it, one
/// for each way Link can face, scrolled to put the one he's facing on him. A
/// 4:3 screen sees only that one; a wider one sees the neighbors at its
/// edges, other lights all round him. Past the picture he's in, it's dark.
fn lanternLit() bool {
    if (!g_lantern_up or vars.TS_copy.* & 1 == 0) return false;
    // Out of a dark room into a lit one, the light's on the screen until it
    // fades out, before the scroll; from the scroll on, layer 1's the rooms'.
    if (vars.submodule_index.* == 2 and vars.subsubmodule_index.* >= 8 and vars.dung_want_lights_out.* == 0)
        return false;
    return true;
}

/// Whether the light's up: the game places it each frame Link walks around a
/// dark room, and it stays up through stairs and the like, which clear the
/// dark room flag as they start. Lighting the torches takes it down, and the
/// layer goes back to being the room's.
var g_lantern_up = false;

/// Whether the lantern's light is drawn from here, so the margins can show
/// a dark room the same as a lit one.
pub fn drawsLanternLight() bool {
    return enabled() and vars.main_module_index.* == 7 and lanternLit();
}

/// Which of the four pictures of the light the game put on Link, by its
/// corner on the light's map: OrientLampLightCone says each frame.
var g_lantern_picture: struct { x: u32, y: u32 } = .{ .x = 0, .y = 0 };

pub fn noteLanternPicture(x: u16, y: u16) void {
    g_lantern_picture = .{ .x = x, .y = y };
    g_lantern_up = true;
}

/// The game went to place the light and found a lit room, so there's no cone
/// and layer 1 is the room's own again. Stairs and the like run for a good
/// while with no play frame to notice that for us. A room-to-room scroll is
/// the exception: the new room's header is read while the dark room being
/// left is still on the screen, light and all, and `lanternLit` has its own
/// say on when that goes.
pub fn noteNoLanternPicture() void {
    if (vars.main_module_index.* == 7 and vars.submodule_index.* == 2) return;
    g_lantern_up = false;
}

/// How far past the 4:3 screen the lantern's light may reach on each side:
/// as far as the margins go into the room. A scroll has already moved the
/// bounds on to the room being entered while the light still belongs to the
/// one being left, so there it's what they were when it started.
pub fn lanternMargins() Margins {
    if (vars.main_module_index.* == 7 and vars.submodule_index.* == 2) {
        if (g_start) |s| return .{ .left = @intCast(s.left), .right = @intCast(s.right) };
    }
    const qm: usize = vars.quadrant_fullsize_x.* >> 1;
    const cam: i32 = vars.BG2HOFS_copy2.*;
    return .{
        .left = @max(cam - @as(i32, vars.room_bounds_x.v[qm]), 0),
        .right = @max(@as(i32, vars.room_bounds_x.v[qm + 2]) - cam, 0),
    };
}

/// Layer 1 in a dark room: the picture of the light Link's facing comes from
/// VRAM, and anything past it is the dark from that picture's corner.
fn lanternTile(ppu: *const Ppu, x: u32, y: u32) ?u16 {
    const qx = g_lantern_picture.x;
    const qy = g_lantern_picture.y;
    if ((x & 0x100) == qx and (y & 0x100) == qy) return null;
    return ppu_mod.bgTilemapWord(ppu, 0, qx, qy);
}

/// Which background layers the PPU should ask `tileSource` for this frame.
pub fn sourceLayers() u8 {
    if (!enabled()) return 0;
    if (drawsLanternLight()) return 0b01;
    if (fallingIn()) return 0b11;
    if (g_fall_frames != 0 and g_shown_room != null and g_shown_room.? == vars.dungeon_room_index.*)
        return 0b11;
    if (!inTransition()) return 0;
    if (g_shown == null or g_prev == null) return 0;
    return 0b11;
}

/// The PPU's question: which tile is at (x, y) of this layer's scrolled
/// tilemap space. The answer comes from the room there, the one being
/// entered or the one left, or from VRAM (null) past both.
pub fn tileSource(ppu: *const Ppu, layer: u32, x: u32, y: u32) ?u16 {
    if (layer > 1) return null;
    if (layer == 0 and drawsLanternLight()) return lanternTile(ppu, x, y);
    const bg = &ppu.bgLayer[layer];
    // The PPU's scroll is the game's cut to 10 bits; its x and y are that
    // plus where on the line it is, so the game's scroll plus the same.
    const full_x: i32 = if (layer == 0) vars.BG1HOFS_copy2.* else vars.BG2HOFS_copy2.*;
    const full_y: i32 = if (layer == 0) vars.BG1VOFS_copy2.* else vars.BG2VOFS_copy2.*;
    const wx = full_x + @as(i32, @as(i16, @bitCast(@as(u16, @truncate(x -% bg.hScroll)))));
    const wy = full_y + @as(i32, @as(i16, @bitCast(@as(u16, @truncate(y -% bg.vScroll)))));
    if (g_shown) |so| {
        if (tileIn(so, wx, wy)) |i|
            return (if (layer == 0) vars.dung_bg1 else vars.dung_bg2)[i];
    }
    if (prevOrigin()) |po| {
        if (tileIn(po, wx, wy)) |i|
            return (if (layer == 0) &g_prev_bg1 else &g_prev_bg2)[i];
    }
    return null;
}

/// The tile index of (wx, wy) in the room at `o`, if it's in the room.
fn tileIn(o: Origin, wx: i32, wy: i32) ?usize {
    const lx = wx - o.x;
    const ly = wy - o.y;
    if (lx < 0 or ly < 0 or lx >= kRoomSize or ly >= kRoomSize) return null;
    return @intCast((ly >> 3) * 64 + (lx >> 3));
}

pub const Margins = struct { left: c_int, right: c_int };

/// Which way the transition under way goes, as overworld_screen_transition
/// has it as it starts (0 down, 1 up, 2 right, 3 left); the game sets that
/// back to 0 before the transition's over.
pub fn transitionDir() ?u8 {
    const s = g_start orelse return null;
    return s.dir;
}

/// Notes the room, camera and margins as a transition starts, and which way
/// it goes, before it changes the room bounds to the next room's. The margins are the room's
/// rules: as far as the camera's range lets the screen reach past it.
pub fn noteTransitionStart(dir: u8) void {
    const qm: usize = vars.quadrant_fullsize_x.* >> 1;
    const cam: i32 = vars.BG2HOFS_copy2.*;
    const dark = vars.hdr_dungeon_dark_with_lantern.* != 0 and vars.TS_copy.* != 0;
    g_start = .{
        .dir = dir,
        .cam_x = cam,
        .cam_y = vars.BG2VOFS_copy2.*,
        .left = if (dark) 0 else @max(cam - @as(i32, vars.room_bounds_x.v[qm]), 0),
        .right = if (dark) 0 else @max(@as(i32, vars.room_bounds_x.v[qm + 2]) - cam, 0),
    };
}

/// The margins during a transition, given the room being entered's rules at
/// where the camera will stop: see the top of the file.
pub fn transitionMargins(max: c_int, end_left: c_int, end_right: c_int, end_cam_x: i32, end_cam_y: i32) ?Margins {
    if (vars.main_module_index.* != 7) return null;
    // Between two parts of one room too (submodule 1): the whole room's in
    // VRAM then, so there's nothing to draw from here, but the margins still
    // go from what they were to what they'll be a step at a time.
    const within_room = vars.submodule_index.* == 1;
    if (!within_room and vars.submodule_index.* != 2) return null;
    const s = g_start orelse return null;
    const cap = struct {
        fn f(v: i32, m: c_int) c_int {
            return @intCast(@min(@max(v, 0), m));
        }
    }.f;
    // Until the next room's in its buffers, the room being left is all
    // there is, and its margins stay as they were.
    if (!within_room and sourceLayers() == 0) {
        // Not yet: the room being left is still the one in the buffers.
        if (vars.subsubmodule_index.* >= 2) return null;
        return .{ .left = cap(s.left, max), .right = cap(s.right, max) };
    }
    const po = if (within_room) cameraRoom() else prevOrigin() orelse return null;
    const co = if (within_room) cameraRoom() else g_shown orelse return null;
    const cam_x: i32 = vars.BG2HOFS_copy2.*;
    const cam_y: i32 = vars.BG2VOFS_copy2.*;
    // How far along the scroll is, along its own axis only: a teleport door
    // moves the camera a long way on the other one as it starts.
    const horizontal = s.dir >= 2;
    const done: i32 = @intCast(if (horizontal) @abs(cam_x - s.cam_x) else @abs(cam_y - s.cam_y));
    const to_go: i32 = @intCast(if (horizontal) @abs(end_cam_x - cam_x) else @abs(end_cam_y - cam_y));
    // As far as the two rooms reach.
    const lo = @min(po.x, co.x);
    const hi = @max(po.x, co.x) + kRoomSize;
    // Never wider than at either end: between two 4:3 rooms, say, the
    // margins stay shut all the way rather than opening in the middle.
    const left = @min(@min(s.left + done, end_left + to_go), @max(@min(s.left, max), end_left));
    const right = @min(@min(s.right + done, end_right + to_go), @max(@min(s.right, max), end_right));
    return .{
        .left = cap(@min(cam_x - lo, left), max),
        .right = cap(@min(hi - (cam_x + 256), right), max),
    };
}
