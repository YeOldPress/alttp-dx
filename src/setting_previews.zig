//! Pictures of what the graphics settings do, beside them in the start
//! menu's Settings: the castle's torchlit hall with Dynamic Lighting off on
//! the left half and on on the right, and so on.
//!
//! They're of the game, so they can't ship with it; the game takes them
//! itself, from the player's own assets, the first time Settings opens. Each
//! is `zelda3 --preview`, run in the background one after another (the one
//! the cursor's on first): the game booted from power-on into a room, with
//! the setting each way, written to previews/ beside zelda3.ini. They're
//! taken again when the game or the assets change, which a stamp file
//! there keeps track of.
//!
//! Every picture forces the settings around the one it shows to the same
//! values, so they show that setting and not whatever else is set. A
//! setting can have more than one scene, which take turns: HD Water/Lava
//! shows Lake Hylia and then Turtle Rock's lava.
const std = @import("std");
const builtin = @import("builtin");
const c = @import("sdl.zig").c;
const start_page = @import("start_page.zig");
const P = start_page;
const kit = @import("menu_kit.zig");
const Rect = kit.Rect;
const draw_mod = @import("tools_draw.zig");
const Color = draw_mod.Color;
const fileio = @import("fileio.zig");

const kDir = "previews";
const kStamp = "previews/stamp.txt";
/// Bumped when the pictures themselves change, to take them again.
const kFormat = "4";
const kAssets = "zelda3_assets.dat";
/// Frames from power-on to a room's picture: through the intro's setup,
/// the room's loading and its fade in, with the torches well alight.
const kFrames = "240";

/// What every picture shares, before its own settings.
const kBase = "General.ExtendedAspectRatio=16:9;Graphics.NewRenderer=1;Graphics.DynamicLighting=1;Graphics.LightingQuality=full;Graphics.RoomDimming=20%;Graphics.Particles=1;Graphics.HdWater=1";
/// Hyrule Castle's great hall, its eight torches lit.
const kHall = "ROOM=4|CRT=off";
/// Out in Lake Hylia by the island and its whirlpool, and a stroke or two
/// up to set Link swimming (the made-up file has the Flippers). The game
/// runs the same from power-on every time, so it's the same swim.
const kLake = "SPOT=lake|CRT=off";
const kLakeWalk = "240,8:up,40";
/// Turtle Rock's pipe room, over its lake of lava: in through the dungeon's
/// front door and moved over to the room, on a Dark World file.
const kLava = "ROOM=53|DARK=1|ROOMID=0x14|CRT=off";

const Shot = struct { file: [:0]const u8, spec: []const u8, frames: [:0]const u8 = kFrames };

const kShots = [_]Shot{
    .{ .file = "lighting-off", .spec = kHall ++ "|SCALE=2|SET=" ++ kBase ++ ";Graphics.DynamicLighting=0" },
    .{ .file = "lighting-on", .spec = kHall ++ "|SCALE=2|SET=" ++ kBase },
    .{ .file = "quality-simple", .spec = kHall ++ "|SCALE=3|SET=" ++ kBase ++ ";Graphics.LightingQuality=simple" },
    .{ .file = "quality-full", .spec = kHall ++ "|SCALE=3|SET=" ++ kBase },
    .{ .file = "dimming-0", .spec = kHall ++ "|SCALE=2|SET=" ++ kBase ++ ";Graphics.RoomDimming=0%" },
    .{ .file = "dimming-40", .spec = kHall ++ "|SCALE=2|SET=" ++ kBase ++ ";Graphics.RoomDimming=40%" },
    .{ .file = "particles-off", .spec = kHall ++ "|SCALE=3|SET=" ++ kBase ++ ";Graphics.Particles=0" },
    .{ .file = "lake-off", .spec = kLake ++ "|SCALE=2|SET=" ++ kBase ++ ";Graphics.HdWater=0", .frames = kLakeWalk },
    .{ .file = "lake-on", .spec = kLake ++ "|SCALE=2|SET=" ++ kBase, .frames = kLakeWalk },
    .{ .file = "lava-off", .spec = kLava ++ "|SCALE=2|SET=" ++ kBase ++ ";Graphics.HdWater=0" },
    .{ .file = "lava-on", .spec = kLava ++ "|SCALE=2|SET=" ++ kBase },
    .{ .file = "crt-scanlines", .spec = "ROOM=4|CRT=scanlines|SCALE=3|SET=" ++ kBase },
    .{ .file = "crt-arcade", .spec = "ROOM=4|CRT=arcade|SCALE=3|SET=" ++ kBase },
    .{ .file = "crt-soft", .spec = "ROOM=4|CRT=soft|SCALE=3|SET=" ++ kBase },
    .{ .file = "crt-tv", .spec = "ROOM=4|CRT=tv|SCALE=3|SET=" ++ kBase },
    .{ .file = "crt-composite", .spec = "ROOM=4|CRT=composite|SCALE=3|SET=" ++ kBase },
    .{ .file = "crt-lcd", .spec = "ROOM=4|CRT=lcd|SCALE=3|SET=" ++ kBase },
};

fn shot(comptime name: []const u8) usize {
    inline for (kShots, 0..) |s, i| {
        if (comptime std.mem.eql(u8, s.file, name)) return i;
    }
    @compileError("no shot " ++ name);
}

/// Part of a picture, as fractions of it.
const Crop = struct { x: f32 = 0, y: f32 = 0, w: f32 = 1, h: f32 = 1 };

/// One way the setting can be, and its picture.
const Side = struct { value: []const u8, label: []const u8, shot: usize };

/// One scene of a preview: its pictures, the part of them shown, and what
/// it's of when there's more than one.
const View = struct {
    crop: Crop = .{},
    sides: []const Side,
    caption: []const u8 = "",
};

const Preview = struct {
    key: []const u8,
    /// Two halves, before and after, or else the picture of the value
    /// that's picked.
    split: bool,
    /// Its scenes, which take turns when there's more than one.
    views: []const View,
};

/// How long each scene stays before the next, and how long they take to
/// cross, in seconds.
const kViewSeconds: f32 = 4;
const kFadeSeconds: f32 = 0.6;

fn onOff(comptime off: []const u8, comptime on: []const u8) []const Side {
    return &.{
        .{ .value = "0", .label = "Off", .shot = shot(off) },
        .{ .value = "1", .label = "On", .shot = shot(on) },
    };
}

const kPreviews = [_]Preview{
    .{ .key = "DynamicLighting", .split = true, .views = &.{.{ .sides = onOff("lighting-off", "lighting-on") }} },
    .{ .key = "LightingQuality", .split = true, .views = &.{.{ .crop = .{ .x = 0.3, .y = 0.12, .w = 0.4, .h = 0.4 }, .sides = &.{
        .{ .value = "simple", .label = "Simple", .shot = shot("quality-simple") },
        .{ .value = "full", .label = "Full", .shot = shot("quality-full") },
    } }} },
    .{ .key = "RoomDimming", .split = true, .views = &.{.{ .sides = &.{
        .{ .value = "0%", .label = "0%", .shot = shot("dimming-0") },
        .{ .value = "40%", .label = "40%", .shot = shot("dimming-40") },
    } }} },
    .{ .key = "Particles", .split = true, .views = &.{.{ .crop = .{ .x = 0.35, .y = 0.1, .w = 0.3, .h = 0.3 }, .sides = onOff("particles-off", "quality-full") }} },
    .{ .key = "HdWater", .split = true, .views = &.{
        .{ .caption = "Lake Hylia", .crop = .{ .x = 0.215, .y = 0.2, .w = 0.6, .h = 0.6 }, .sides = onOff("lake-off", "lake-on") },
        .{ .caption = "Turtle Rock", .crop = .{ .x = 0.19, .y = 0.26, .w = 0.5, .h = 0.5 }, .sides = onOff("lava-off", "lava-on") },
    } },
    .{
        .key = "CrtFilter",
        .split = false,
        .views = &.{.{
            .crop = .{ .x = 0.25, .y = 0.2, .w = 0.5, .h = 0.5 },
            .sides = &.{
                // The same picture as Full lighting, CRT off being how that's taken.
                .{ .value = "off", .label = "Off", .shot = shot("quality-full") },
                .{ .value = "scanlines", .label = "Scanlines", .shot = shot("crt-scanlines") },
                .{ .value = "arcade", .label = "Arcade", .shot = shot("crt-arcade") },
                .{ .value = "soft", .label = "Soft", .shot = shot("crt-soft") },
                .{ .value = "tv", .label = "Consumer TV", .shot = shot("crt-tv") },
                .{ .value = "composite", .label = "Composite", .shot = shot("crt-composite") },
                .{ .value = "lcd", .label = "LCD", .shot = shot("crt-lcd") },
            },
        }},
    },
};

fn previewFor(key: []const u8) ?*const Preview {
    for (&kPreviews) |*pv| {
        if (std.mem.eql(u8, pv.key, key)) return pv;
    }
    return null;
}

/// Whether the setting `key` has a picture to show.
pub fn has(key: []const u8) bool {
    return g_started and !g_unavailable and previewFor(key) != null;
}

// ------------------------------------------------------------- the maker

const State = enum(u8) { missing, making, ready, failed };

var g_state: [kShots.len]std.atomic.Value(State) = @splat(.init(.missing));
var g_textures: [kShots.len]?*c.SDL_Texture = @splat(null);
/// The picture the cursor's on wants made first, as a bit for each shot.
var g_wanted: std.atomic.Value(u32) = .init(0);
var g_stop: std.atomic.Value(bool) = .init(false);
var g_process: std.atomic.Value(usize) = .init(0);
var g_thread: ?std.Thread = null;
var g_started = false;
/// No assets, or nowhere to keep the pictures: none to show.
var g_unavailable = false;
var g_exe_buf: [4096]u8 = undefined;
var g_exe: [:0]const u8 = "";

/// Starts taking the pictures that aren't taken yet, once, when Settings
/// first opens.
pub fn start() void {
    if (g_started) return;
    g_started = true;
    if (!fileio.exists(kAssets)) {
        g_unavailable = true;
        return;
    }
    {
        var threaded: std.Io.Threaded = .init(std.heap.c_allocator, .{});
        defer threaded.deinit();
        const n = std.process.executablePath(threaded.io(), g_exe_buf[0 .. g_exe_buf.len - 1]) catch {
            g_unavailable = true;
            return;
        };
        g_exe_buf[n] = 0;
        g_exe = g_exe_buf[0..n :0];
    }
    // Inside an AppImage, the game runs again through the AppImage itself,
    // which is what finds the libraries it brings.
    if (builtin.os.tag == .linux) if (c.SDL_getenv("APPIMAGE")) |image| {
        const img = std.mem.span(image);
        if (img.len < g_exe_buf.len) {
            @memcpy(g_exe_buf[0..img.len], img);
            g_exe_buf[img.len] = 0;
            g_exe = g_exe_buf[0..img.len :0];
        }
    };
    if (!fileio.isDir(kDir)) fileio.makeDir(kDir) catch {
        g_unavailable = true;
        return;
    };
    // Taken by another build, or from other assets: taken again.
    var stamp_buf: [256]u8 = undefined;
    const stamp = makeStamp(&stamp_buf);
    const had = fileio.readWholeFile(std.heap.c_allocator, kStamp) catch null;
    defer if (had) |h| std.heap.c_allocator.free(h);
    const fresh = had != null and std.mem.eql(u8, had.?, stamp);
    for (kShots, 0..) |s, i| {
        var path_buf: [128]u8 = undefined;
        const path = shotPath(&path_buf, s.file, "");
        if (fresh and fileio.exists(path)) {
            g_state[i].store(.ready, .release);
        } else {
            _ = fileio.remove(path);
        }
    }
    if (!fresh) {
        // Pictures an older build took that this one no longer does go too.
        _ = c.SDL_EnumerateDirectory(kDir, clearOld, null);
        fileio.writeWholeFile(kStamp, stamp) catch {};
    }
    g_stop.store(false, .release);
    g_thread = std.Thread.spawn(.{}, run, .{}) catch null;
}

/// For a screenshot: takes whatever isn't taken, and waits.
pub fn startAndWait() void {
    start();
    if (g_thread) |t| t.join();
    g_thread = null;
}

/// Stops taking them, when the menu closes: the one being taken is
/// abandoned, to be taken next time.
pub fn stop() void {
    g_stop.store(true, .release);
    const p = g_process.load(.acquire);
    if (p != 0) _ = c.SDL_KillProcess(@ptrFromInt(p), true);
    if (g_thread) |t| t.join();
    g_thread = null;
    for (&g_textures) |*t| {
        if (t.*) |tex| c.SDL_DestroyTexture(tex);
        t.* = null;
    }
    g_started = false;
    g_unavailable = false;
    for (&g_state) |*s| s.store(.missing, .release);
}

/// The setting the cursor's on, so its pictures are taken next.
pub fn want(key: []const u8) void {
    const pv = previewFor(key) orelse return;
    var bits: u32 = 0;
    for (pv.views) |vw| {
        for (vw.sides) |sd| bits |= @as(u32, 1) << @intCast(sd.shot);
    }
    g_wanted.store(bits, .release);
}

/// What the pictures were taken with: this build and these assets.
fn makeStamp(buf: []u8) []const u8 {
    var exe: c.SDL_PathInfo = std.mem.zeroes(c.SDL_PathInfo);
    var assets: c.SDL_PathInfo = std.mem.zeroes(c.SDL_PathInfo);
    _ = c.SDL_GetPathInfo(g_exe.ptr, &exe);
    _ = c.SDL_GetPathInfo(kAssets, &assets);
    return std.fmt.bufPrint(buf, "{s} {d} {d} {d} {d}\n", .{ kFormat, exe.size, exe.modify_time, assets.size, assets.modify_time }) catch "";
}

fn clearOld(userdata: ?*anyopaque, dirname: [*c]const u8, fname: [*c]const u8) callconv(.c) c.SDL_EnumerationResult {
    _ = userdata;
    const name = std.mem.span(fname);
    if (!std.mem.endsWith(u8, name, ".bmp") and !std.mem.endsWith(u8, name, ".part")) return c.SDL_ENUM_CONTINUE;
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&buf, "{s}{s}", .{ std.mem.span(dirname), name }, 0) catch return c.SDL_ENUM_CONTINUE;
    _ = c.SDL_RemovePath(path.ptr);
    return c.SDL_ENUM_CONTINUE;
}

fn shotPath(buf: []u8, file: []const u8, suffix: []const u8) [:0]const u8 {
    return std.fmt.bufPrintSentinel(buf, kDir ++ "/{s}.bmp{s}", .{ file, suffix }, 0) catch "";
}

fn run() void {
    while (!g_stop.load(.acquire)) {
        const i = nextShot() orelse return;
        g_state[i].store(.making, .release);
        g_state[i].store(if (take(i)) .ready else .failed, .release);
    }
}

/// The next picture to take: one that's wanted, or else the first not yet
/// taken.
fn nextShot() ?usize {
    const wanted = g_wanted.load(.acquire);
    var first: ?usize = null;
    for (0..kShots.len) |i| {
        if (g_state[i].load(.acquire) != .missing) continue;
        if (wanted & (@as(u32, 1) << @intCast(i)) != 0) return i;
        if (first == null) first = i;
    }
    return first;
}

/// Runs the game to take picture `i`, into a file of its own that's only
/// given its name once it's whole.
fn take(i: usize) bool {
    var tmp_buf: [128]u8 = undefined;
    var out_buf: [128]u8 = undefined;
    var spec_buf: [512]u8 = undefined;
    const tmp = shotPath(&tmp_buf, kShots[i].file, ".part");
    const out = shotPath(&out_buf, kShots[i].file, "");
    const spec = std.fmt.bufPrintSentinel(&spec_buf, "{s}", .{kShots[i].spec}, 0) catch return false;
    const args = [_:null]?[*:0]const u8{ g_exe.ptr, "--preview", spec.ptr, kShots[i].frames.ptr, tmp.ptr };
    const props = c.SDL_CreateProperties();
    defer c.SDL_DestroyProperties(props);
    _ = c.SDL_SetPointerProperty(props, c.SDL_PROP_PROCESS_CREATE_ARGS_POINTER, @ptrCast(@constCast(&args)));
    _ = c.SDL_SetNumberProperty(props, c.SDL_PROP_PROCESS_CREATE_STDOUT_NUMBER, c.SDL_PROCESS_STDIO_NULL);
    _ = c.SDL_SetNumberProperty(props, c.SDL_PROP_PROCESS_CREATE_STDERR_NUMBER, c.SDL_PROCESS_STDIO_NULL);
    const p = c.SDL_CreateProcessWithProperties(props) orelse return false;
    g_process.store(@intFromPtr(p), .release);
    var code: c_int = -1;
    const waited = c.SDL_WaitProcess(p, true, &code);
    g_process.store(0, .release);
    c.SDL_DestroyProcess(p);
    if (!waited or code != 0 or g_stop.load(.acquire)) {
        _ = fileio.remove(tmp);
        return false;
    }
    return c.SDL_RenamePath(tmp.ptr, out.ptr);
}

/// Picture `i`, once it's taken.
fn texture(r: *c.SDL_Renderer, i: usize) ?*c.SDL_Texture {
    if (g_textures[i]) |t| return t;
    if (g_state[i].load(.acquire) != .ready) return null;
    var path_buf: [128]u8 = undefined;
    const surface = c.SDL_LoadBMP(shotPath(&path_buf, kShots[i].file, "").ptr) orelse {
        g_state[i].store(.failed, .release);
        return null;
    };
    defer c.SDL_DestroySurface(surface);
    const tex = c.SDL_CreateTextureFromSurface(r, surface) orelse return null;
    _ = c.SDL_SetTextureScaleMode(tex, c.SDL_SCALEMODE_LINEAR);
    // Whatever the file says its alpha is, the picture's solid.
    _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_NONE);
    g_textures[i] = tex;
    return tex;
}

// ------------------------------------------------------------- the panel

/// How tall the picture for `key` is when `w` wide.
pub fn height(w: f32) f32 {
    return @round(w * 9 / 16);
}

/// Draws the picture for setting `key`, which is at `value`, in `box`: the
/// two halves split where the pointer is over it (or down the middle), or
/// the picture of the value picked. A setting with more than one scene
/// shows each in turn, crossing from one to the next. While a picture's
/// being taken, a placeholder says so.
pub fn draw(page: *const P.Page, box: Rect, key: []const u8, value: []const u8, pointer_x: f32, pointer_y: f32, t: f32) void {
    const pv = previewFor(key) orelse return;
    const p = &page.paint;
    // A thin gold frame, the picture inside it.
    const rr = draw_mod.Rect{ .x = box.x - 1, .y = box.y - 1, .w = box.w + 2, .h = box.h + 2 };
    p.box(rr, 6, 1, P.kGold.alpha(120), Color.hex(0x060c10));
    // Every scene's pictures before any: they show once all are taken.
    var shots_buf: [16]usize = undefined;
    var n: usize = 0;
    for (pv.views) |vw| for (vw.sides) |sd| {
        if (n < shots_buf.len) shots_buf[n] = sd.shot;
        n += 1;
    };
    for (shots_buf[0..@min(n, shots_buf.len)]) |sh| {
        if (texture(p.r, sh) == null) return waiting(page, box, shots_buf[0..@min(n, shots_buf.len)], t);
    }
    const split = std.math.clamp((pointer_x - box.x) / box.w, 0.04, 0.96);
    const s = if (box.contains(pointer_x, pointer_y)) split else 0.5;
    // Which scene, and how far into crossing to the next.
    const views = pv.views;
    const turn = if (views.len > 1) @mod(t, kViewSeconds * @as(f32, @floatFromInt(views.len))) else 0;
    const at: usize = @intFromFloat(turn / kViewSeconds);
    const into = turn - @as(f32, @floatFromInt(at)) * kViewSeconds;
    const fade = if (views.len > 1) std.math.clamp((into - (kViewSeconds - kFadeSeconds)) / kFadeSeconds, 0, 1) else 0;
    drawView(p, pv, views[at], box, value, s, 255);
    if (fade > 0) drawView(p, pv, views[(at + 1) % views.len], box, value, s, @intFromFloat(255 * fade));
    if (pv.split) {
        const sx = box.x + box.w * s;
        p.fill(.{ .x = sx - 1, .y = box.y, .w = 2, .h = box.h }, P.kGoldHi.alpha(220));
        start_page.diamond(p.r, sx, box.y + box.h / 2, 6, P.kGoldHi);
    }
    const sides = views[at].sides;
    if (pv.split) {
        chip(p, box.x + 8, box.y + 8, sides[0].label, matches(value, sides[0].value), false);
        chip(p, box.x + box.w - 8, box.y + 8, sides[1].label, matches(value, sides[1].value), true);
    } else {
        chip(p, box.x + 8, box.y + 8, pickedSide(sides, value).label, true, false);
    }
    // What the scene is of, when there's more than one, and dots for which.
    if (views.len > 1) {
        const cap = if (fade > 0.5) views[(at + 1) % views.len].caption else views[at].caption;
        const cw = p.textWidth(.small, cap) + 16;
        const cr = draw_mod.Rect{ .x = box.x + 8, .y = box.y + box.h - 28, .w = cw, .h = 20 };
        p.fillRound(cr, 10, Color.hex(0x0a141a).alpha(210));
        p.textCentered(.small, cr.x + cw / 2, cr.y + (cr.h - p.lineHeight(.small)) / 2, P.kCream, cap);
        const shown = if (fade > 0.5) (at + 1) % views.len else at;
        for (0..views.len) |k| {
            const dx = box.x + box.w - 14 - @as(f32, @floatFromInt(views.len - 1 - k)) * 12;
            start_page.diamond(p.r, dx, cr.y + 10, 3.5, if (k == shown) P.kGoldHi else P.kCream.alpha(90));
        }
    }
}

/// One scene of a preview, `alpha` opaque: its two halves split at `s`, or
/// the picture of the value picked.
fn drawView(p: *const draw_mod.Paint, pv: *const Preview, vw: View, box: Rect, value: []const u8, s: f32, alpha: u8) void {
    if (pv.split) {
        const ta = texture(p.r, vw.sides[0].shot) orelse return;
        const tb = texture(p.r, vw.sides[1].shot) orelse return;
        blit(p.r, ta, vw.crop, box, 0, s, alpha);
        blit(p.r, tb, vw.crop, box, s, 1, alpha);
    } else {
        const tx = texture(p.r, pickedSide(vw.sides, value).shot) orelse return;
        blit(p.r, tx, vw.crop, box, 0, 1, alpha);
    }
}

fn pickedSide(sides: []const Side, value: []const u8) Side {
    for (sides) |sd| {
        if (matches(value, sd.value)) return sd;
    }
    return sides[0];
}

/// The part of `tex` from `from` to `to` across `crop` (fractions), into the
/// same part across `box`.
fn blit(r: *c.SDL_Renderer, tex: *c.SDL_Texture, crop: Crop, box: Rect, from: f32, to: f32, alpha: u8) void {
    var tw: f32 = 0;
    var th: f32 = 0;
    _ = c.SDL_GetTextureSize(tex, &tw, &th);
    const src = c.SDL_FRect{
        .x = (crop.x + crop.w * from) * tw,
        .y = crop.y * th,
        .w = crop.w * (to - from) * tw,
        .h = crop.h * th,
    };
    const dst = c.SDL_FRect{ .x = box.x + box.w * from, .y = box.y, .w = box.w * (to - from), .h = box.h };
    // Solid, or blended over the scene before while crossing to it.
    _ = c.SDL_SetTextureBlendMode(tex, if (alpha == 255) c.SDL_BLENDMODE_NONE else c.SDL_BLENDMODE_BLEND);
    _ = c.SDL_SetTextureAlphaMod(tex, alpha);
    _ = c.SDL_RenderTexture(r, tex, &src, &dst);
}

/// A label in a corner of the picture: gold for the way it's set now.
fn chip(p: *const draw_mod.Paint, x: f32, y: f32, label: []const u8, lit: bool, right: bool) void {
    const w = p.textWidth(.small, label) + 16;
    const r = draw_mod.Rect{ .x = if (right) x - w else x, .y = y, .w = w, .h = 20 };
    p.fillRound(r, 10, if (lit) Color.hex(0xe9c46c) else Color.hex(0x0a141a).alpha(210));
    p.textCentered(.small, r.x + w / 2, r.y + (r.h - p.lineHeight(.small)) / 2, if (lit) Color.hex(0x2a1a04) else P.kCream, label);
}

/// While a picture's being taken: what's happening, with dots that move.
fn waiting(page: *const P.Page, box: Rect, shots: []const usize, t: f32) void {
    const p = &page.paint;
    var failed = false;
    for (shots) |s| failed = failed or g_state[s].load(.acquire) == .failed;
    const say = if (failed) "No picture: this needs a graphics card it can draw with" else "Taking a picture of it\u{2026}";
    p.textCentered(.small, box.x + box.w / 2, box.y + box.h / 2 - 16, P.kDim, say);
    if (failed) return;
    for (0..3) |k| {
        const phase = @mod(t * 2 - @as(f32, @floatFromInt(k)) * 0.3, 2);
        const a: u8 = if (phase < 1) @intFromFloat(80 + 175 * (1 - phase)) else 80;
        start_page.diamond(p.r, box.x + box.w / 2 - 14 + @as(f32, @floatFromInt(k)) * 14, box.y + box.h / 2 + 10, 3, P.kGold.alpha(a));
    }
}

/// Whether a value in the ini is the side's: "1" and "true" are one, and
/// "40%" and "40" are.
fn matches(value: []const u8, side: []const u8) bool {
    const v = std.mem.trim(u8, value, " \t%");
    const s = std.mem.trim(u8, side, " \t%");
    if (std.ascii.eqlIgnoreCase(v, s)) return true;
    const on = std.ascii.eqlIgnoreCase(v, "true") or std.mem.eql(u8, v, "1");
    const off = std.ascii.eqlIgnoreCase(v, "false") or std.mem.eql(u8, v, "0");
    return (on and std.mem.eql(u8, s, "1")) or (off and std.mem.eql(u8, s, "0"));
}

test "a setting's value finds its side however the ini spells it" {
    try std.testing.expect(matches("true", "1"));
    try std.testing.expect(matches(" 0", "0"));
    try std.testing.expect(matches("40%", "40%"));
    try std.testing.expect(matches("40", "40%"));
    try std.testing.expect(matches("Scanlines", "scanlines"));
    try std.testing.expect(!matches("20%", "40%"));
}

test "every preview's pictures are in the list, and few enough for the bits" {
    try std.testing.expect(kShots.len <= 32);
    for (kPreviews) |pv| {
        try std.testing.expect(pv.views.len >= 1);
        for (pv.views) |vw| {
            try std.testing.expect(vw.sides.len >= 1);
            if (pv.split) try std.testing.expectEqual(@as(usize, 2), vw.sides.len);
            for (vw.sides) |sd| try std.testing.expect(sd.shot < kShots.len);
        }
    }
}
