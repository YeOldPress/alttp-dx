//! Nintendo's own logo on the start page, for whoever wants it: the banner
//! they made for the series' 40th anniversary, fetched from their site the
//! first time StartBanner asks for it and kept beside the ini after that. It's
//! theirs, so it never ships with the game; it's off by default.
//!
//! The download runs on a thread of its own and only ever writes a file
//! that decoded as a PNG. Everything else - the texture, the checks - is
//! the menu thread's, once a frame.
const std = @import("std");
const c = @import("sdl.zig").c;
const fileio = @import("fileio.zig");
const png = @import("png.zig");

/// Where the banner comes from: the header of Nintendo's anniversary page.
pub const kUrl = "https://assets.nintendo.com/image/upload/f_auto/q_auto/dpr_1.5/c_scale,w_300/Marketing2/OPeWtPL8TttzJh7wdmHysyOZ7FtfFyHvTDpoos1RsrJrgWCHYS40Sswcm8RBawZA/01-home/0-header/header-logo";
/// Where it's kept, beside zelda3.ini. Delete it and it's fetched again.
pub const kPath = "start_logo.png";
const kPartPath = kPath ++ ".part";

const kUserAgent = "alttp-dx";
/// The real one is about 400 KB; anything past this isn't it.
const kMaxBytes = 8 * 1024 * 1024;
/// Nor is anything bigger than this, whatever it compresses to.
const kMaxSide = 4096;

pub const Phase = enum(u8) { idle, fetching, failed };

var g_phase = std.atomic.Value(Phase).init(.idle);
/// Bumped each time a new file lands, so the texture knows to follow.
var g_landed = std.atomic.Value(u32).init(0);

/// The texture, and which renderer and which file it was made from.
var g_tex: ?*c.SDL_Texture = null;
var g_tex_for: ?*c.SDL_Renderer = null;
var g_tex_landed: u32 = 0;
/// Whether the file was looked for since it last changed, so a missing or
/// broken one isn't read again every frame.
var g_looked = false;
var g_aspect: f32 = 1;

pub fn phase() Phase {
    return g_phase.load(.acquire);
}

/// Each frame, with whether StartBanner wants the banner: fetches it once if
/// it isn't here yet. A failure stays failed until `retry`, so a machine
/// with no network isn't asked again sixty times a second.
pub fn want(on: bool) void {
    if (!on or phase() != .idle or g_tex != null or fileio.exists(kPath)) return;
    g_phase.store(.fetching, .release);
    const t = std.Thread.spawn(.{}, fetchThread, .{}) catch {
        g_phase.store(.failed, .release);
        return;
    };
    t.detach();
}

/// The setting was picked again: try again if the last try failed.
pub fn retry() void {
    if (phase() == .failed) g_phase.store(.idle, .release);
    g_looked = false;
}

/// What the setting says beside its value while there's news.
pub fn note() []const u8 {
    return switch (phase()) {
        .idle => "",
        .fetching => "Downloading...",
        .failed => "Couldn't download",
    };
}

/// The banner, ready to draw with `r`, or null while there isn't one. Its
/// width over its height is `aspect()`.
pub fn texture(r: *c.SDL_Renderer) ?*c.SDL_Texture {
    const landed = g_landed.load(.acquire);
    if (g_tex_for != r or g_tex_landed != landed) {
        release();
        g_looked = false;
    }
    if (g_tex == null and !g_looked) {
        g_looked = true;
        g_tex_landed = landed;
        g_tex = load(r);
        if (g_tex != null) g_tex_for = r;
    }
    return g_tex;
}

pub fn aspect() f32 {
    return g_aspect;
}

/// Lets go of the texture. Called before its renderer goes.
pub fn release() void {
    if (g_tex) |t| c.SDL_DestroyTexture(t);
    g_tex = null;
    g_tex_for = null;
}

fn load(r: *c.SDL_Renderer) ?*c.SDL_Texture {
    const alloc = std.heap.c_allocator;
    const bytes = fileio.readWholeFile(alloc, kPath) catch return null;
    defer alloc.free(bytes);
    var img = decode(alloc, bytes) catch {
        // Not a picture any more: out of the way, so it's fetched afresh.
        _ = fileio.remove(kPath);
        return null;
    };
    defer img.deinit(alloc);
    const rgba = toRgba(alloc, img) catch return null;
    defer alloc.free(rgba);
    const w: c_int = @intCast(img.width);
    const h: c_int = @intCast(img.height);
    const tex = c.SDL_CreateTexture(r, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_STATIC, w, h) orelse return null;
    if (!c.SDL_UpdateTexture(tex, null, rgba.ptr, w * 4)) {
        c.SDL_DestroyTexture(tex);
        return null;
    }
    _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
    _ = c.SDL_SetTextureScaleMode(tex, c.SDL_SCALEMODE_LINEAR);
    g_aspect = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(img.height));
    return tex;
}

/// A PNG no bigger than the banner could sensibly be, checked from its
/// header before anything is inflated.
fn decode(alloc: std.mem.Allocator, bytes: []const u8) !png.Image {
    if (bytes.len < 24 or bytes.len > kMaxBytes) return error.NotPng;
    if (!std.mem.eql(u8, bytes[12..16], "IHDR")) return error.NotPng;
    const w = std.mem.readInt(u32, bytes[16..20], .big);
    const h = std.mem.readInt(u32, bytes[20..24], .big);
    if (w == 0 or h == 0 or w > kMaxSide or h > kMaxSide) return error.NotPng;
    return png.decode(alloc, bytes);
}

/// Four bytes a pixel, red first, whatever kind of PNG it was.
fn toRgba(alloc: std.mem.Allocator, img: png.Image) ![]u8 {
    const out = try alloc.alloc(u8, @as(usize, img.width) * img.height * 4);
    for (0..img.height) |y| for (0..img.width) |x| {
        const rgb = img.rgbAt(x, y);
        out[(y * img.width + x) * 4 ..][0..4].* = .{ @truncate(rgb >> 16), @truncate(rgb >> 8), @truncate(rgb), img.alphaAt(x, y) };
    };
    return out;
}

fn fetchThread() void {
    if (fetch()) {
        _ = g_landed.fetchAdd(1, .acq_rel);
        g_phase.store(.idle, .release);
    } else |_| {
        g_phase.store(.failed, .release);
    }
}

fn fetch() !void {
    const alloc = std.heap.c_allocator;
    var threaded: std.Io.Threaded = .init(alloc, .{});
    defer threaded.deinit();
    var client: std.http.Client = .{ .allocator = alloc, .io = threaded.io() };
    defer client.deinit();

    // A fixed buffer, so a server that never stops can't fill memory.
    const buf = try alloc.alloc(u8, kMaxBytes);
    defer alloc.free(buf);
    var body = std.Io.Writer.fixed(buf);
    const res = try client.fetch(.{
        .location = .{ .url = kUrl },
        .response_writer = &body,
        .headers = .{ .user_agent = .{ .override = kUserAgent } },
        // The address says f_auto: asked plainly it may pick WebP or AVIF.
        .extra_headers = &.{.{ .name = "Accept", .value = "image/png" }},
    });
    if (res.status != .ok) return error.Network;
    const bytes = body.buffered();

    // Only a picture that reads is kept.
    var img = try decode(alloc, bytes);
    img.deinit(alloc);
    try fileio.writeWholeFile(kPartPath, bytes);
    _ = fileio.remove(kPath);
    if (fileio.rename(kPartPath, kPath) != 0) {
        _ = fileio.remove(kPartPath);
        return error.WriteFailed;
    }
}

test "a PNG too big to be the banner is turned away before it's inflated" {
    var bytes: [33]u8 = @splat(0);
    @memcpy(bytes[0..8], "\x89PNG\r\n\x1a\n");
    @memcpy(bytes[12..16], "IHDR");
    std.mem.writeInt(u32, bytes[16..20], 100_000, .big);
    std.mem.writeInt(u32, bytes[20..24], 10, .big);
    try std.testing.expectError(error.NotPng, decode(std.testing.allocator, &bytes));
}
