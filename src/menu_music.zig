//! The start menu's Music screen: the game's own soundtrack and every
//! installed MSU-1 pack, to listen to and to look after.
//!
//! On the left, the sources: the original soundtrack (played by the game's
//! own sound driver, out of the assets), each pack, and a way to import
//! another. On the right, the one picked: what it is, what can be done with
//! it, and its tracks, each to play.
//!
//! The screen keeps its own state here; anything that touches the ini or
//! needs a question asked (using a pack, renaming, deleting, importing,
//! shrinking) goes back to the menu as an Action.
const std = @import("std");
const c = @import("sdl.zig").c;
const start_page = @import("start_page.zig");
const P = start_page;
const kit = @import("menu_kit.zig");
const Rect = kit.Rect;
const msu_import = @import("msu_import.zig");
const msu_preview = @import("msu_preview.zig");
const tools_music = @import("tools_music.zig");
const tools_ops = @import("tools_ops.zig");
const tools_gui = @import("tools_gui.zig");
const draw_mod = @import("tools_draw.zig");

const kAssets = "zelda3_assets.dat";

const kLeft = Rect{ .x = 40, .y = 100, .w = 296, .h = 332 };
const kRight = Rect{ .x = 352, .y = 100, .w = 568, .h = 332 };
/// The player, along the foot of both.
const kPlayer = Rect{ .x = 40, .y = 440, .w = 880, .h = 52 };
const kSourceH: f32 = 48;
const kSourceRows = 6;
const kTrackH: f32 = 26;
const kTrackRows = 7;
const kActionsY: f32 = kRight.y + 68;
const kTracksY: f32 = kRight.y + 124;

const Zone = enum { sources, actions, tracks, player };

/// The player's buttons, left to right.
const kPlayerButtons = [_]P.Transport{ .prev, .play, .next, .stop };

var g_arena: ?std.heap.ArenaAllocator = null;
var g_packs: []msu_import.Pack = &.{};
/// 0 is the original soundtrack, then the packs, then Import.
var g_source: usize = 0;
var g_source_top: usize = 0;
var g_zone: Zone = .sources;
var g_action: usize = 0;
var g_track: usize = 0;
var g_track_top: usize = 0;
/// The tracks of the pack picked, and which source they're for.
var g_tracks: []u16 = &.{};
var g_tracks_for: usize = std.math.maxInt(usize);
var g_tracks_arena: ?std.heap.ArenaAllocator = null;

var g_preview: msu_preview.Preview = .{};
/// Whether this screen turned SDL's audio on, to turn off again.
var g_audio = false;
var g_spc: ?*tools_music.Player = null;
var g_spc_tried = false;
/// What the pointer's over, so moving it doesn't fight the keys.
var g_hover: ?Hover = null;

const Hover = union(enum) { source: usize, action: usize, track: usize, player: usize };

/// What's playing, wherever the pick has wandered off to since: which
/// source (0 for the soundtrack, or the pack at `path`), which track, and
/// for how long.
const Now = struct {
    source: usize,
    number: u16,
    path: [1024]u8 = undefined,
    path_len: usize = 0,
    name: [96]u8 = undefined,
    name_len: usize = 0,

    fn packPath(self: *const Now) []const u8 {
        return self.path[0..self.path_len];
    }
};
var g_now: ?Now = null;
var g_paused = false;

/// The game's own songs loop for ever, so the player gives each this long
/// and then fades it out over kSpcFade, as players of game music do.
const kSpcLength: f64 = 150;
const kSpcFade: f64 = 5;
var g_player_button: usize = 1;

/// What the menu is asked to do.
pub const Action = union(enum) {
    none,
    leave,
    import_pack,
    /// Play this pack in the game (its MSUPath).
    use: msu_import.Pack,
    rename: msu_import.Pack,
    delete: msu_import.Pack,
    shrink: msu_import.Pack,
    /// Something to say in the footer.
    status: []const u8,
};

pub const Input = struct {
    move: i32 = 0,
    adjust: i32 = 0,
    confirm: bool = false,
    back: bool = false,
    clicked: bool = false,
    hovered: bool = false,
    /// The player's own keys: play or pause, and the track before or after.
    pause: bool = false,
    prev: bool = false,
    next: bool = false,
    x: f32 = 0,
    y: f32 = 0,
    wheel: i32 = 0,
};

/// Looks at what's installed again, keeping the pick on the pack at
/// `select` (an MSUPath) when there's one.
pub fn refresh(alloc: std.mem.Allocator, select: ?[]const u8) void {
    var picked_path: [1024]u8 = undefined;
    var picked_len: usize = 0;
    if (select) |s| {
        picked_len = @min(s.len, picked_path.len);
        @memcpy(picked_path[0..picked_len], s[0..picked_len]);
    } else if (pickedPack()) |p| {
        picked_len = @min(p.path.len, picked_path.len);
        @memcpy(picked_path[0..picked_len], p.path[0..picked_len]);
    }
    if (g_arena) |*a| a.deinit();
    g_arena = std.heap.ArenaAllocator.init(alloc);
    g_packs = msu_import.listPacks(g_arena.?.allocator(), msu_import.kLibrary) catch &.{};
    g_tracks_for = std.math.maxInt(usize);
    if (picked_len != 0) {
        for (g_packs, 0..) |p, i| {
            if (tools_ops.samePath(p.path, picked_path[0..picked_len])) g_source = i + 1;
        }
    }
    g_source = @min(g_source, g_packs.len + 1);
    // What's playing follows its pack to wherever the list put it, or stops
    // when it's gone.
    if (g_now) |*now| if (now.source != 0) {
        var found = false;
        for (g_packs, 0..) |p, i| {
            if (std.mem.eql(u8, p.path, now.packPath())) {
                now.source = i + 1;
                found = true;
            }
        }
        if (!found) stopAll();
    };
    loadTracks(alloc);
}

/// Opening the screen: the packs as they are, the pick on the one playing.
pub fn open(alloc: std.mem.Allocator, current: []const u8) void {
    // The start menu makes no sound of its own until now.
    if (!g_audio) g_audio = c.SDL_InitSubSystem(c.SDL_INIT_AUDIO);
    g_zone = .sources;
    g_source = 0;
    g_track = 0;
    g_track_top = 0;
    refresh(alloc, current);
    // The original soundtrack, out of the assets, if they're there.
    if (g_spc == null and !g_spc_tried) {
        g_spc_tried = true;
        g_spc = tools_music.Player.init(alloc, kAssets) catch null;
    }
}

/// Leaving it: everything stops.
pub fn close() void {
    stopAll();
}

/// Lets go of everything, when the menu does.
pub fn deinit() void {
    stopAll();
    g_preview.deinit();
    if (g_spc) |p| p.deinit();
    g_spc = null;
    g_spc_tried = false;
    if (g_arena) |*a| a.deinit();
    g_arena = null;
    if (g_tracks_arena) |*a| a.deinit();
    g_tracks_arena = null;
    g_packs = &.{};
    g_tracks = &.{};
    if (g_audio) c.SDL_QuitSubSystem(c.SDL_INIT_AUDIO);
    g_audio = false;
}

fn stopAll() void {
    g_preview.stop();
    if (g_spc) |p| p.stop();
    g_now = null;
    g_paused = false;
}

/// Starts track `number` of source `source` (0, or a pack by index + 1).
fn startPlaying(source: usize, number: u16) ?[]const u8 {
    stopAll();
    var now = Now{ .source = source, .number = number };
    if (source == 0) {
        const player = g_spc orelse return "BUILD THE ASSETS FIRST";
        const song = for (player.songs) |sg| {
            if (sg.number == number) break sg;
        } else return null;
        if (!player.play(song)) return "NO SOUND DEVICE TO PLAY IT ON";
        const name = "Original Soundtrack";
        @memcpy(now.name[0..name.len], name);
        now.name_len = name.len;
    } else {
        if (source > g_packs.len) return null;
        const pk = g_packs[source - 1];
        // Once through, then on to the next.
        if (!g_preview.play(pk.path, number, false)) return "THAT TRACK WOULD NOT PLAY";
        now.path_len = @min(pk.path.len, now.path.len);
        @memcpy(now.path[0..now.path_len], pk.path[0..now.path_len]);
        now.name_len = @min(pk.name.len, now.name.len);
        @memcpy(now.name[0..now.name_len], pk.name[0..now.name_len]);
    }
    g_now = now;
    g_paused = false;
    return null;
}

fn togglePause() ?[]const u8 {
    const now = g_now orelse {
        // Nothing playing: the track picked, or the first there is.
        var rows_buf: [512]Row = undefined;
        const rows = trackRows(&rows_buf);
        if (g_zone == .tracks and g_track < rows.len and rows[g_track].have) return startPlaying(g_source, rows[g_track].number);
        for (rows) |r| if (r.have) return startPlaying(g_source, r.number);
        return "PICK A TRACK TO PLAY";
    };
    if (g_paused) {
        if (now.source == 0) {
            if (g_spc) |p| p.@"resume"();
        } else g_preview.@"resume"();
        g_paused = false;
    } else {
        if (now.source == 0) {
            if (g_spc) |p| p.pause();
        } else g_preview.pause();
        g_paused = true;
    }
    return null;
}

/// Where what's playing is, and how long it'll play, in seconds: read off
/// the audio itself, so a pause or a slow machine doesn't throw it out.
fn clock() struct { at: f64, len: ?f64 } {
    const now = g_now orelse return .{ .at = 0, .len = null };
    if (now.source == 0) {
        const player = g_spc orelse return .{ .at = 0, .len = null };
        return .{ .at = player.seconds(), .len = kSpcLength + kSpcFade };
    }
    const cl = g_preview.clock();
    return .{ .at = cl.at, .len = cl.len };
}

/// Once a frame: on to the next track when this one's over, and the game's
/// songs faded out at the end of their time.
fn tick(alloc: std.mem.Allocator) ?[]const u8 {
    const now = g_now orelse return null;
    if (g_paused) return null;
    var over = false;
    if (now.source == 0) {
        const player = g_spc orelse return null;
        const at = player.seconds();
        if (player.ended() or at >= kSpcLength + kSpcFade) {
            over = true;
        } else if (at > kSpcLength) {
            player.setGain(@floatCast(1 - (at - kSpcLength) / kSpcFade));
        }
    } else {
        over = g_preview.playingIn(now.packPath()) == null;
    }
    if (!over) return null;
    const said = stepTrack(alloc, 1);
    // One that won't play stops the lot, rather than trying every frame.
    if (said != null) stopAll();
    return said;
}

/// The track before or after what's playing (or what's picked), among the
/// ones its source has.
fn stepTrack(alloc: std.mem.Allocator, dir: i32) ?[]const u8 {
    var numbers_buf: [512]u16 = undefined;
    var numbers: []u16 = numbers_buf[0..0];
    var source = g_source;
    var from: ?u16 = null;
    if (g_now) |now| {
        source = now.source;
        from = now.number;
    }
    if (source == 0) {
        const player = g_spc orelse return "BUILD THE ASSETS FIRST";
        for (player.songs, 0..) |sg, i| {
            if (i == numbers_buf.len) break;
            numbers_buf[i] = sg.number;
            numbers = numbers_buf[0 .. i + 1];
        }
    } else {
        if (source > g_packs.len) return null;
        var arena_state = std.heap.ArenaAllocator.init(alloc);
        defer arena_state.deinit();
        const got = msu_import.trackNumbers(arena_state.allocator(), g_packs[source - 1].path);
        const n = @min(got.len, numbers_buf.len);
        @memcpy(numbers_buf[0..n], got[0..n]);
        numbers = numbers_buf[0..n];
    }
    if (numbers.len == 0) return null;
    var at: i64 = if (dir > 0) -1 else @intCast(numbers.len);
    if (from) |f| {
        for (numbers, 0..) |n, i| {
            if (n == f) at = @intCast(i);
        }
    }
    const next = @mod(at + dir, @as(i64, @intCast(numbers.len)));
    return startPlaying(source, numbers[@intCast(next)]);
}

fn pickedPack() ?msu_import.Pack {
    if (g_source == 0 or g_source > g_packs.len) return null;
    return g_packs[g_source - 1];
}

fn importPicked() bool {
    return g_source == g_packs.len + 1;
}

fn loadTracks(alloc: std.mem.Allocator) void {
    if (g_tracks_for == g_source) return;
    if (g_tracks_arena) |*a| a.deinit();
    g_tracks_arena = null;
    g_tracks = &.{};
    g_tracks_for = g_source;
    const p = pickedPack() orelse return;
    g_tracks_arena = std.heap.ArenaAllocator.init(alloc);
    g_tracks = msu_import.trackNumbers(g_tracks_arena.?.allocator(), p.path);
}

// ---------------------------------------------------------------- tracks

const Row = struct { number: u16, have: bool };

/// The picked source's track list: the soundtrack's songs, or a pack's 34
/// (the ones it hasn't got dim) and then its extras.
fn trackRows(buf: []Row) []Row {
    var n: usize = 0;
    if (g_source == 0) {
        const player = g_spc orelse return buf[0..0];
        for (player.songs) |song| {
            if (n == buf.len) break;
            buf[n] = .{ .number = song.number, .have = true };
            n += 1;
        }
        return buf[0..n];
    }
    if (pickedPack() == null) return buf[0..0];
    for (1..msu_import.kGameTracks + 1) |t| {
        buf[n] = .{ .number = @intCast(t), .have = std.mem.indexOfScalar(u16, g_tracks, @intCast(t)) != null };
        n += 1;
    }
    for (g_tracks) |t| {
        if (t <= msu_import.kGameTracks or n == buf.len) continue;
        buf[n] = .{ .number = t, .have = true };
        n += 1;
    }
    return buf[0..n];
}

/// The track playing from the picked source, if one is.
fn playingTrack() ?u16 {
    const now = g_now orelse return null;
    return if (now.source == g_source) now.number else null;
}

/// A's on a track: plays it, or pauses and goes on with it when it's the
/// one playing.
fn play(row: Row) ?[]const u8 {
    if (!row.have) return "THE PACK HAS NO TRACK THERE";
    if (playingTrack() == row.number) return togglePause();
    return startPlaying(g_source, row.number);
}

// --------------------------------------------------------------- actions

const ActionKind = enum { use, deluxe, shrink, rename, show, delete };

fn actionList(buf: *[6]ActionKind, current: []const u8) []const ActionKind {
    const p = pickedPack() orelse return buf[0..0];
    var n: usize = 0;
    if (!tools_ops.samePath(p.path, current)) {
        buf[n] = .use;
        n += 1;
    }
    buf[n] = .deluxe;
    n += 1;
    if (p.pcm != 0) {
        buf[n] = .shrink;
        n += 1;
    }
    for ([_]ActionKind{ .rename, .show, .delete }) |k| {
        buf[n] = k;
        n += 1;
    }
    return buf[0..n];
}

fn actionLabel(k: ActionKind, p: msu_import.Pack) []const u8 {
    return switch (k) {
        .use => "Use This Pack",
        .deluxe => if (p.deluxe) "\u{2713} Deluxe" else "Deluxe",
        .shrink => "Shrink to FLAC",
        .rename => "Rename",
        .show => "Show",
        .delete => "Delete",
    };
}

fn actionRects(page: *const P.Page, list: []const ActionKind, p: msu_import.Pack, out: *[6]Rect) []Rect {
    var x = kRight.x + 22;
    for (list, 0..) |k, i| {
        const w = page.paint.textWidth(.small, actionLabel(k, p)) + 28;
        out[i] = .{ .x = x, .y = kActionsY, .w = w, .h = 28 };
        x += w + 8;
    }
    return out[0..list.len];
}

fn doAction(alloc: std.mem.Allocator, k: ActionKind, p: msu_import.Pack) Action {
    switch (k) {
        .use => return .{ .use = p },
        .deluxe => {
            if (!msu_import.setPackDeluxe(p.path, !p.deluxe)) return .{ .status = "COULD NOT WRITE ITS PACK.INI" };
            refresh(alloc, p.path);
            return .{ .status = if (p.deluxe) "NOT A DELUXE PACK NOW" else "A DELUXE PACK NOW" };
        },
        .shrink => return .{ .shrink = p },
        .rename => return .{ .rename = p },
        .show => {
            tools_gui.reveal(msu_import.splitPath(p.path));
            return .none;
        },
        .delete => return .{ .delete = p },
    }
}

// ----------------------------------------------------------------- input

fn sourceRect(slot: usize) Rect {
    return .{ .x = kLeft.x + 8, .y = kLeft.y + 10 + kSourceH * @as(f32, @floatFromInt(slot)), .w = kLeft.w - 16, .h = kSourceH - 4 };
}

fn trackRect(slot: usize) Rect {
    return .{ .x = kRight.x + 14, .y = kTracksY + kTrackH * @as(f32, @floatFromInt(slot)), .w = kRight.w - 40, .h = kTrackH - 2 };
}

fn keepSourceInView() void {
    if (g_source < g_source_top) g_source_top = g_source;
    if (g_source >= g_source_top + kSourceRows) g_source_top = g_source + 1 - kSourceRows;
}

fn keepTrackInView(count: usize) void {
    if (count == 0) {
        g_track = 0;
        g_track_top = 0;
        return;
    }
    g_track = @min(g_track, count - 1);
    if (g_track < g_track_top) g_track_top = g_track;
    if (g_track >= g_track_top + kTrackRows) g_track_top = g_track + 1 - kTrackRows;
    g_track_top = @min(g_track_top, count -| kTrackRows);
}

fn pickSource(alloc: std.mem.Allocator, i: usize) void {
    if (i == g_source) return;
    g_source = i;
    g_track = 0;
    g_track_top = 0;
    g_action = 0;
    keepSourceInView();
    loadTracks(alloc);
}

fn playerRect(i: usize) Rect {
    const big = kPlayerButtons[i] == .play;
    const size: f32 = if (big) 40 else 32;
    var x = kPlayer.x + 22;
    for (kPlayerButtons[0..i]) |k| x += (if (k == .play) @as(f32, 40) else 32) + 10;
    return .{ .x = x, .y = kPlayer.y + (kPlayer.h - size) / 2, .w = size, .h = size };
}

fn pressPlayer(alloc: std.mem.Allocator, i: usize) ?[]const u8 {
    return switch (kPlayerButtons[i]) {
        .prev => stepTrack(alloc, -1),
        .next => stepTrack(alloc, 1),
        .play, .pause => togglePause(),
        .stop => blk: {
            stopAll();
            break :blk null;
        },
    };
}

pub fn input(alloc: std.mem.Allocator, page: *const P.Page, in: Input, current: []const u8) Action {
    const sources = g_packs.len + 2;
    var rows_buf: [512]Row = undefined;
    const rows = trackRows(&rows_buf);
    var kinds_buf: [6]ActionKind = undefined;
    const kinds = actionList(&kinds_buf, current);
    var rects_buf: [6]Rect = undefined;
    const p_opt = pickedPack();
    const rects: []Rect = if (p_opt) |p| actionRects(page, kinds, p, &rects_buf) else rects_buf[0..0];

    // What the pointer's over. Hovering only lights it; a click picks it.
    var under: ?Hover = null;
    for (0..kSourceRows) |slot| {
        if (g_source_top + slot >= sources) break;
        if (sourceRect(slot).contains(in.x, in.y)) under = .{ .source = g_source_top + slot };
    }
    for (rects, 0..) |r, i| {
        if (r.contains(in.x, in.y)) under = .{ .action = i };
    }
    for (0..kTrackRows) |slot| {
        if (g_track_top + slot >= rows.len) break;
        if (trackRect(slot).contains(in.x, in.y)) under = .{ .track = g_track_top + slot };
    }
    for (0..kPlayerButtons.len) |i| {
        if (playerRect(i).contains(in.x, in.y)) under = .{ .player = i };
    }
    if (in.hovered) g_hover = under;
    if (tick(alloc)) |said| return .{ .status = said };

    // The player's own keys work wherever the focus is.
    if (in.pause) if (togglePause()) |said| return .{ .status = said };
    if (in.prev) if (stepTrack(alloc, -1)) |said| return .{ .status = said };
    if (in.next) if (stepTrack(alloc, 1)) |said| return .{ .status = said };

    var confirm = in.confirm;
    if (in.clicked) if (under) |h| {
        switch (h) {
            .source => |i| {
                // A click picks it; a second, on Import, imports.
                const again = g_zone == .sources and g_source == i;
                g_zone = .sources;
                pickSource(alloc, i);
                if (!(again and importPicked())) return .none;
                confirm = true;
            },
            .action => |i| {
                g_zone = .actions;
                g_action = i;
                confirm = true;
            },
            .track => |i| {
                // A click picks it; a second plays it (or pauses it).
                const again = g_zone == .tracks and g_track == i;
                g_zone = .tracks;
                g_track = i;
                if (!again) return .none;
                confirm = true;
            },
            .player => |i| {
                g_zone = .player;
                g_player_button = i;
                if (pressPlayer(alloc, i)) |said| return .{ .status = said };
                return .none;
            },
        }
    };
    if (in.wheel != 0) {
        if (kLeft.contains(in.x, in.y)) {
            g_source_top = @intCast(std.math.clamp(@as(i64, @intCast(g_source_top)) - in.wheel, 0, @as(i64, @intCast(sources -| kSourceRows))));
        } else if (rows.len != 0) {
            g_track_top = @intCast(std.math.clamp(@as(i64, @intCast(g_track_top)) - in.wheel * 2, 0, @as(i64, @intCast(rows.len -| kTrackRows))));
            // The pick comes along, so the list doesn't snap back to it.
            g_track = std.math.clamp(g_track, g_track_top, @min(g_track_top + kTrackRows, rows.len) - 1);
        }
    }

    if (in.back) {
        if (g_zone != .sources) {
            g_zone = .sources;
            return .none;
        }
        stopAll();
        return .leave;
    }

    switch (g_zone) {
        .sources => {
            if (in.move != 0) {
                const next = @mod(@as(i64, @intCast(g_source)) + in.move, @as(i64, @intCast(sources)));
                pickSource(alloc, @intCast(next));
            }
            if (confirm and importPicked()) return .import_pack;
            if (confirm or in.adjust > 0) {
                if (importPicked()) return .none;
                if (rows.len != 0) {
                    g_zone = .tracks;
                } else if (kinds.len != 0) {
                    g_zone = .actions;
                }
            }
        },
        .actions => {
            if (kinds.len == 0) {
                g_zone = .sources;
                return .none;
            }
            g_action = @min(g_action, kinds.len - 1);
            if (in.adjust < 0 and g_action == 0) {
                g_zone = .sources;
            } else if (in.adjust != 0) {
                g_action = @intCast(std.math.clamp(@as(i64, @intCast(g_action)) + in.adjust, 0, @as(i64, @intCast(kinds.len - 1))));
            }
            if (in.move > 0 and rows.len != 0) g_zone = .tracks;
            if (confirm) return doAction(alloc, kinds[g_action], p_opt.?);
        },
        .tracks => {
            if (rows.len == 0) {
                g_zone = .sources;
                return .none;
            }
            if (in.move < 0 and g_track == 0 and kinds.len != 0) {
                g_zone = .actions;
            } else if (in.move > 0 and g_track == rows.len - 1) {
                g_zone = .player;
            } else if (in.move != 0) {
                g_track = @intCast(std.math.clamp(@as(i64, @intCast(g_track)) + in.move, 0, @as(i64, @intCast(rows.len - 1))));
            }
            if (in.adjust < 0) g_zone = .sources;
            keepTrackInView(rows.len);
            if (confirm) if (play(rows[g_track])) |said| return .{ .status = said };
        },
        .player => {
            if (in.adjust != 0) g_player_button = @intCast(std.math.clamp(@as(i64, @intCast(g_player_button)) + in.adjust, 0, kPlayerButtons.len - 1));
            if (in.move < 0) g_zone = if (rows.len != 0) .tracks else .sources;
            if (confirm) if (pressPlayer(alloc, g_player_button)) |said| return .{ .status = said };
        },
    }
    return .none;
}

// ------------------------------------------------------------------ draw

pub fn draw(page: *const P.Page, t: f32, current: []const u8) void {
    const p = &page.paint;
    page.panel(kLeft);
    page.panel(kRight);
    drawPlayer(page);

    // The sources.
    const sources = g_packs.len + 2;
    for (0..kSourceRows) |slot| {
        const i = g_source_top + slot;
        if (i >= sources) break;
        const r = sourceRect(slot);
        const picked = i == g_source;
        page.band(r, picked and g_zone == .sources, t);
        if (picked and g_zone != .sources) p.fillRound(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, 6, P.kTeal.alpha(22));
        if (!picked and hovering(.{ .source = i })) p.fillRound(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, 6, P.kCream.alpha(10));
        const x = r.x + 26;
        var name_buf: [96]u8 = undefined;
        var sub_buf: [96]u8 = undefined;
        var name: []const u8 = undefined;
        var sub: []const u8 = undefined;
        var playing_here = false;
        if (i == 0) {
            name = "Original Soundtrack";
            sub = if (g_spc != null) "The SNES music, out of the assets" else "Comes out of the assets: build them first";
        } else if (i == sources - 1) {
            name = "Import a Pack\u{2026}";
            sub = "A folder, .zip or .7z";
        } else {
            const pk = g_packs[i - 1];
            name = p.fit(.item, pk.name, r.w - 100, &name_buf);
            var kinds_buf: [48]u8 = undefined;
            sub = std.fmt.bufPrint(&sub_buf, "{d} tracks  \u{00b7}  {s}{s}", .{ pk.tracks, msu_import.kindsLabel(&kinds_buf, pk), if (pk.deluxe) "  \u{00b7}  Deluxe" else "" }) catch "";
            playing_here = tools_ops.samePath(pk.path, current);
        }
        p.text(.item, x, r.y + 5, if (picked) P.kCream else P.kMuted, name);
        p.text(.small, x, r.y + 26, P.kDim, sub);
        if (playing_here) {
            const label = "In game";
            const w = p.textWidth(.small, label) + 14;
            const chip = ui_rect(r.x + r.w - w - 10, r.y + 6, w, 18);
            p.fillRound(chip, 9, P.kTeal.alpha(40));
            p.textCentered(.small, chip.x + w / 2, chip.y + (18 - p.lineHeight(.small)) / 2, P.kTeal, label);
        }
    }
    if (sources > kSourceRows) {
        const nf: f32 = @floatFromInt(sources);
        page.scrollbar(kLeft.x + kLeft.w - 8, kLeft.y + 12, kLeft.h - 24, @as(f32, @floatFromInt(g_source_top)) / nf, @as(f32, kSourceRows) / nf);
    }

    // The one picked.
    const x = kRight.x + 22;
    var rows_buf: [512]Row = undefined;
    const rows = trackRows(&rows_buf);
    if (importPicked()) {
        p.text(.subtitle, x, kRight.y + 18, P.kGoldHi, "Import a Pack");
        _ = page.wrap(.body, x, kRight.y + 60, kRight.w - 44, 22, P.kMuted, "Drop a pack's folder, .zip or .7z on this window, or press A to browse for one. It's kept beside your other packs, in a folder of its own, and plays from then on.", 5);
        return;
    }
    const pk_opt = pickedPack();
    if (pk_opt) |pk| {
        var name_buf: [96]u8 = undefined;
        p.text(.subtitle, x, kRight.y + 16, P.kGoldHi, p.fit(.subtitle, pk.name, kRight.w - 44, &name_buf));
        var line_buf: [200]u8 = undefined;
        var w = std.Io.Writer.fixed(&line_buf);
        const missing = pk.missing();
        var kinds_buf: [48]u8 = undefined;
        w.print("{d} tracks, {s}, {d} MB", .{ pk.tracks, msu_import.kindsLabel(&kinds_buf, pk), pk.bytes / (1024 * 1024) }) catch {};
        if (missing == 0) {
            w.print(". All of the game's tracks are here", .{}) catch {};
        } else {
            w.print(". {d} of the game's {d} {s} missing: the SNES music plays there", .{ missing, msu_import.kGameTracks, if (missing == 1) "is" else "are" }) catch {};
        }
        var fit_buf: [220]u8 = undefined;
        p.text(.small, x, kRight.y + 46, if (missing == 0) P.kMuted else P.kWarn, p.fit(.small, w.buffered(), kRight.w - 44, &fit_buf));
        // What can be done with it.
        var kinds_list_buf: [6]ActionKind = undefined;
        const kinds = actionList(&kinds_list_buf, current);
        var rects_buf: [6]Rect = undefined;
        const rects = actionRects(page, kinds, pk, &rects_buf);
        for (kinds, rects, 0..) |k, r, i| {
            const focused = (g_zone == .actions and g_action == i) or hovering(.{ .action = i });
            const lit = (k == .deluxe and pk.deluxe) or k == .use;
            const rr = ui_rect(r.x, r.y, r.w, r.h);
            if (focused) {
                p.box(rr, r.h / 2, 1.5, P.kGoldHi, if (k == .delete) P.kWarn else draw_mod.Color.hex(0xe9c46c));
                p.textCentered(.small, r.x + r.w / 2, r.y + (r.h - p.lineHeight(.small)) / 2, draw_mod.Color.hex(0x2a1a04), actionLabel(k, pk));
            } else {
                p.box(rr, r.h / 2, 1, if (lit) P.kGold else P.kChipLine, P.kChip);
                p.textCentered(.small, r.x + r.w / 2, r.y + (r.h - p.lineHeight(.small)) / 2, if (lit) P.kGoldHi else P.kMuted, actionLabel(k, pk));
            }
        }
    } else {
        p.text(.subtitle, x, kRight.y + 16, P.kGoldHi, "Original Soundtrack");
        p.text(.small, x, kRight.y + 46, P.kMuted, if (g_spc != null) "The game's own music, played by its own sound driver." else "It plays out of the assets. Build Assets on the front page makes them.");
    }

    // The tracks.
    const playing = playingTrack();
    page.heading(x, kTracksY - 24, kRight.w - 44, 20, "Tracks");
    for (0..kTrackRows) |slot| {
        const i = g_track_top + slot;
        if (i >= rows.len) break;
        const row = rows[i];
        const r = trackRect(slot);
        const picked = g_zone == .tracks and g_track == i;
        page.band(r, picked, t);
        if (!picked and hovering(.{ .track = i })) p.fillRound(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, 4, P.kCream.alpha(10));
        const is_playing = playing != null and playing.? == row.number;
        const ty = r.y + (r.h - p.lineHeight(.body)) / 2;
        var num_buf: [8]u8 = undefined;
        const num = std.fmt.bufPrint(&num_buf, "{d}", .{row.number}) catch "";
        const col = if (!row.have) P.kDim else if (is_playing) P.kTeal else if (picked) P.kCream else P.kMuted;
        if (is_playing) p.text(.body, r.x + 24, ty, P.kTeal, "\u{25b6}");
        p.text(.body, r.x + 44, ty, col, num);
        const name = msu_preview.trackName(row.number) orelse (if (g_source == 0) "" else if (pk_opt != null and pk_opt.?.deluxe) "Deluxe track" else "Extra track");
        p.text(.body, r.x + 84, ty, col, name);
        const right_label: []const u8 = if (!row.have) "Missing, the SNES music plays" else if (is_playing) "Playing" else "";
        if (right_label.len != 0) p.text(.small, r.x + r.w - 12 - p.textWidth(.small, right_label), r.y + (r.h - p.lineHeight(.small)) / 2, if (row.have) P.kTeal else P.kDim, right_label);
    }
    if (rows.len > kTrackRows) {
        const nf: f32 = @floatFromInt(rows.len);
        page.scrollbar(kRight.x + kRight.w - 12, kTracksY, kTrackH * kTrackRows, @as(f32, @floatFromInt(g_track_top)) / nf, @as(f32, kTrackRows) / nf);
    }
    if (rows.len == 0) p.text(.body, x, kTracksY + 8, P.kDim, if (g_source == 0) "Nothing to play until the assets are built." else "No tracks.");
}

fn hovering(h: Hover) bool {
    return if (g_hover) |cur| std.meta.eql(cur, h) else false;
}

/// The player: back, play or pause, on, stop, then what's playing and for
/// how long.
fn drawPlayer(page: *const P.Page) void {
    const p = &page.paint;
    page.panel(kPlayer);
    for (kPlayerButtons, 0..) |k, i| {
        const r = playerRect(i);
        const focused = g_zone == .player and g_player_button == i;
        const lit = focused or hovering(.{ .player = i });
        const main = k == .play;
        const rr = ui_rect(r.x, r.y, r.w, r.h);
        // The keys' ring first, so the button sits in it.
        if (focused) p.box(ui_rect(r.x - 4, r.y - 4, r.w + 8, r.h + 8), (r.w + 8) / 2, 2, P.kTeal, draw_mod.Color.hex(0x0a141a));
        if (main) {
            p.box(rr, r.w / 2, 1.5, if (lit) P.kGoldHi else P.kGold, draw_mod.Color.hex(if (lit) 0xf0cd72 else 0xe2bb60));
        } else {
            p.box(rr, r.w / 2, 1, if (lit) P.kGold else P.kChipLine, P.kChip);
        }
        const face: P.Transport = if (main) (if (g_now != null and !g_paused) .pause else .play) else k;
        const col = if (main) draw_mod.Color.hex(0x2a1a04) else if (lit) P.kGoldHi else P.kMuted;
        page.transport(face, r.x + r.w / 2, r.y + r.h / 2, if (main) 14 else 11, col);
    }
    const x = playerRect(kPlayerButtons.len - 1).x + 32 + 24;
    if (g_now) |now| {
        var line_buf: [128]u8 = undefined;
        const title = if (msu_preview.trackName(now.number)) |n|
            std.fmt.bufPrint(&line_buf, "{d}  {s}", .{ now.number, n }) catch ""
        else
            std.fmt.bufPrint(&line_buf, "Track {d}", .{now.number}) catch "";
        p.text(.item, x, kPlayer.y + 7, P.kCream, title);
        var from_buf: [128]u8 = undefined;
        const from = std.fmt.bufPrint(&from_buf, "{s}{s}", .{ now.name[0..now.name_len], if (g_paused) "  \u{00b7}  Paused" else "" }) catch "";
        p.text(.small, x, kPlayer.y + 29, if (g_paused) P.kWarn else P.kMuted, from);
        const cl = clock();
        const at: u64 = @intFromFloat(@max(cl.at, 0));
        var time_buf: [24]u8 = undefined;
        const time = if (cl.len) |l| blk: {
            const len: u64 = @intFromFloat(@max(l, 0));
            break :blk std.fmt.bufPrint(&time_buf, "{d}:{d:0>2} / {d}:{d:0>2}", .{ at / 60, at % 60, len / 60, len % 60 }) catch "";
        } else std.fmt.bufPrint(&time_buf, "{d}:{d:0>2}", .{ at / 60, at % 60 }) catch "";
        // How far along, as a line under it all.
        if (cl.len) |l| if (l > 0) {
            const frac: f32 = @floatCast(@min(cl.at / l, 1));
            const bar_x = x;
            const bar_w = kPlayer.x + kPlayer.w - 24 - bar_x;
            p.fillRound(ui_rect(bar_x, kPlayer.y + kPlayer.h - 7, bar_w, 3), 1.5, P.kChipLine.alpha(150));
            if (frac > 0) p.fillRound(ui_rect(bar_x, kPlayer.y + kPlayer.h - 7, @max(bar_w * frac, 3), 3), 1.5, P.kTeal);
        };
        p.text(.strong, kPlayer.x + kPlayer.w - 24 - p.textWidth(.strong, time), kPlayer.y + (kPlayer.h - p.lineHeight(.strong)) / 2, P.kTeal, time);
    } else {
        p.text(.body, x, kPlayer.y + (kPlayer.h - p.lineHeight(.body)) / 2, P.kDim, "Nothing playing. Pick a track and press A, or click it twice.");
    }
}

fn ui_rect(x: f32, y: f32, w: f32, h: f32) draw_mod.Rect {
    return .{ .x = x, .y = y, .w = w, .h = h };
}

/// The footer's keys, for where the focus is.
pub fn hints(out: *[5]P.Hint) []const P.Hint {
    const back = P.Hint{ .key = "B / Esc", .action = "Back" };
    const pause = P.Hint{ .key = "Y / P", .action = "Play / Pause" };
    const skip = P.Hint{ .key = "L R / [ ]", .action = "Skip" };
    const list: []const P.Hint = switch (g_zone) {
        .sources => if (importPicked())
            &.{ .{ .key = "\xe2\x86\x91 \xe2\x86\x93", .action = "Choose" }, .{ .key = "A / Enter", .action = "Browse" }, pause, back }
        else
            &.{ .{ .key = "\xe2\x86\x91 \xe2\x86\x93", .action = "Choose" }, .{ .key = "A / \xe2\x86\x92", .action = "Open" }, pause, skip, back },
        .actions => &.{ .{ .key = "\xe2\x86\x90 \xe2\x86\x92", .action = "Choose" }, .{ .key = "A / Enter", .action = "Do it" }, pause, skip, back },
        .tracks => &.{ .{ .key = "\xe2\x86\x91 \xe2\x86\x93", .action = "Choose" }, .{ .key = "A / Enter", .action = "Play" }, pause, skip, back },
        .player => &.{ .{ .key = "\xe2\x86\x90 \xe2\x86\x92", .action = "Choose" }, .{ .key = "A / Enter", .action = "Press" }, pause, skip, back },
    };
    @memcpy(out[0..list.len], list);
    return out[0..list.len];
}

/// For screenshots: the pack at `name` picked, its tracks focused.
/// For screenshots: something shown as playing (and paused, if asked).
pub fn nowForShot(number: u16, paused: bool) void {
    var now = Now{ .source = g_source, .number = number };
    const name = if (pickedPack()) |pk| pk.name else "Original Soundtrack";
    now.name_len = @min(name.len, now.name.len);
    @memcpy(now.name[0..now.name_len], name[0..now.name_len]);
    if (pickedPack()) |pk| {
        now.path_len = @min(pk.path.len, now.path.len);
        @memcpy(now.path[0..now.path_len], pk.path[0..now.path_len]);
    }
    g_now = now;
    g_paused = paused;
}

pub fn pickForShot(alloc: std.mem.Allocator, name: []const u8, zone: []const u8) void {
    if (std.mem.eql(u8, name, "Original")) pickSource(alloc, 0);
    for (g_packs, 0..) |pk, i| {
        if (std.mem.eql(u8, pk.name, name)) pickSource(alloc, i + 1);
    }
    g_zone = std.meta.stringToEnum(Zone, zone) orelse .sources;
}
