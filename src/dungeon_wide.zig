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

const kRoomTiles = 64 * 64;
/// The side of a room in pixels, and of the tilemap.
const kRoomSize = 512;

/// The room left behind, as the room buffers had it when it was.
var g_prev_bg1: [kRoomTiles]u16 = undefined;
var g_prev_bg2: [kRoomTiles]u16 = undefined;
var g_prev_room: ?u16 = null;

/// The room the room buffers hold.
var g_shown_room: ?u16 = null;

/// Where the camera was and what the margins were, by the room's own rules,
/// in the room being left as the transition started.
var g_start: ?struct { room: u16, dir: u8, cam_x: i32, cam_y: i32, left: i32, right: i32 } = null;

/// Whether this runs at all: widescreen, with the widescreen camera on.
pub fn enabled() bool {
    return overworld.wideCameraOn();
}

/// The room the buffers hold, told by the room loader and, since a snapshot
/// can start anywhere, by the camera while the player walks around one.
pub fn noteRoomShown() void {
    g_shown_room = vars.dungeon_room_index.*;
}

/// Keeps the room about to be loaded over, just before it is.
pub fn keepRoomBeingLeft() void {
    const room = g_shown_room orelse {
        g_prev_room = null;
        return;
    };
    @memcpy(&g_prev_bg1, vars.dung_bg1[0..kRoomTiles]);
    @memcpy(&g_prev_bg2, vars.dung_bg2[0..kRoomTiles]);
    g_prev_room = room;
}

const Origin = struct { x: i32, y: i32 };

/// Where a room's top left corner is, in the scroll's coordinates: the rooms
/// are laid out 16 to a row.
fn roomOrigin(room: u16) Origin {
    return .{ .x = @as(i32, room & 15) * kRoomSize, .y = @as(i32, room >> 4) * kRoomSize };
}

/// Whether the two rooms of a transition are next to each other, which they
/// are unless something left the copy behind stale.
fn neighbors(a: Origin, b: Origin) bool {
    const dx = @abs(a.x - b.x);
    const dy = @abs(a.y - b.y);
    return (dx == kRoomSize and dy == 0) or (dx == 0 and dy == kRoomSize);
}

/// A room-to-room scroll, once the new room's in the buffers.
fn inTransition() bool {
    return vars.main_module_index.* == 7 and vars.submodule_index.* == 2 and
        vars.subsubmodule_index.* >= 2;
}

fn prevOrigin() ?Origin {
    const prev = g_prev_room orelse return null;
    const cur = g_shown_room orelse return null;
    const po = roomOrigin(prev);
    if (!neighbors(po, roomOrigin(cur))) return null;
    return po;
}

/// Which background layers the PPU should ask `tileSource` for this frame.
pub fn sourceLayers() u8 {
    if (!enabled() or !inTransition()) return 0;
    _ = prevOrigin() orelse return 0;
    return 0b11;
}

/// The PPU's question: which tile is at (x, y) of this layer's scrolled
/// tilemap space. The answer comes from the room there, the one being
/// entered or the one left, or from VRAM (null) past both.
pub fn tileSource(ppu: *const Ppu, layer: u32, x: u32, y: u32) ?u16 {
    if (layer > 1) return null;
    const bg = &ppu.bgLayer[layer];
    // The PPU's scroll is the game's cut to 10 bits; its x and y are that
    // plus where on the line it is, so the game's scroll plus the same.
    const full_x: i32 = if (layer == 0) vars.BG1HOFS_copy2.* else vars.BG2HOFS_copy2.*;
    const full_y: i32 = if (layer == 0) vars.BG1VOFS_copy2.* else vars.BG2VOFS_copy2.*;
    const wx = full_x + @as(i32, @as(i16, @bitCast(@as(u16, @truncate(x -% bg.hScroll)))));
    const wy = full_y + @as(i32, @as(i16, @bitCast(@as(u16, @truncate(y -% bg.vScroll)))));
    if (g_shown_room) |room| {
        if (tileIn(roomOrigin(room), wx, wy)) |i|
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
        .room = vars.dungeon_room_index.*,
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
    if (!(vars.main_module_index.* == 7 and vars.submodule_index.* == 2)) return null;
    const s = g_start orelse return null;
    const cap = struct {
        fn f(v: i32, m: c_int) c_int {
            return @intCast(@min(@max(v, 0), m));
        }
    }.f;
    // Until the next room's in its buffers, the room being left is all
    // there is, and its margins stay as they were.
    if (sourceLayers() == 0) {
        if (g_shown_room == null or g_shown_room.? != s.room) return null;
        return .{ .left = cap(s.left, max), .right = cap(s.right, max) };
    }
    const po = prevOrigin() orelse return null;
    if (g_prev_room.? != s.room) return null;
    const co = roomOrigin(g_shown_room.?);
    const cam_x: i32 = vars.BG2HOFS_copy2.*;
    const cam_y: i32 = vars.BG2VOFS_copy2.*;
    const done: i32 = @intCast(@abs(cam_x - s.cam_x) + @abs(cam_y - s.cam_y));
    const to_go: i32 = @intCast(@abs(end_cam_x - cam_x) + @abs(end_cam_y - cam_y));
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
