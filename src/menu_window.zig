//! What the start menu remembers for next time, in zelda3_menu.ini beside
//! zelda3.ini (as the tools keep theirs in zelda3_tools.ini), so the
//! settings file is left to the settings: where its window was, its place
//! and size, and whether it was maximized or fullscreen; and which version's
//! notes it's shown, so What's New comes up once after an update.
//!
//! The size is the window's ordinary one, from before it was maximized or
//! made fullscreen, so coming back out of either goes back to it. It's only
//! used for the style it was made in, the two styles being different shapes,
//! and a place that's no longer on any screen (one unplugged since) isn't
//! used at all.
const std = @import("std");
const c = @import("sdl.zig").c;
const fileio = @import("fileio.zig");

pub const kPath = "zelda3_menu.ini";

pub const Place = struct {
    modern: bool = true,
    x: c_int = 0,
    y: c_int = 0,
    w: c_int = 0,
    h: c_int = 0,
    maximized: bool = false,
    fullscreen: bool = false,
    /// The version whose What's New has been seen, such as v1.9.
    seen_buf: [24]u8 = undefined,
    seen_len: usize = 0,

    pub fn seen(self: *const Place) []const u8 {
        return self.seen_buf[0..self.seen_len];
    }

    pub fn setSeen(self: *Place, v: []const u8) void {
        self.seen_len = @min(v.len, self.seen_buf.len);
        @memcpy(self.seen_buf[0..self.seen_len], v[0..self.seen_len]);
    }

    /// From the file's `key = value` lines; null when it has no size.
    pub fn parse(text: []const u8) ?Place {
        var p = Place{};
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..eq], " \t");
            const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
            const n = std.fmt.parseInt(c_int, value, 10) catch 0;
            if (std.mem.eql(u8, key, "style")) {
                p.modern = !std.ascii.eqlIgnoreCase(value, "retro");
            } else if (std.mem.eql(u8, key, "x")) {
                p.x = n;
            } else if (std.mem.eql(u8, key, "y")) {
                p.y = n;
            } else if (std.mem.eql(u8, key, "width")) {
                p.w = n;
            } else if (std.mem.eql(u8, key, "height")) {
                p.h = n;
            } else if (std.mem.eql(u8, key, "maximized")) {
                p.maximized = n != 0;
            } else if (std.mem.eql(u8, key, "fullscreen")) {
                p.fullscreen = n != 0;
            } else if (std.mem.eql(u8, key, "seen")) {
                p.setSeen(value);
            }
        }
        if (p.w <= 0 or p.h <= 0) return null;
        return p;
    }

    pub fn write(self: Place, w: *std.Io.Writer) !void {
        try w.writeAll("# Where the start menu's window was when it was last closed.\n# Delete this file to start afresh.\n");
        try w.print("style = {s}\nx = {d}\ny = {d}\nwidth = {d}\nheight = {d}\nmaximized = {d}\nfullscreen = {d}\n", .{
            if (self.modern) "modern" else "retro", self.x,                       self.y,                        self.w,
            self.h,                                 @intFromBool(self.maximized), @intFromBool(self.fullscreen),
        });
        if (self.seen_len != 0) try w.print("seen = {s}\n", .{self.seen()});
    }

    /// Whether enough of a window here would be on `screen` to grab and
    /// move: some of its top edge, where the title bar is.
    pub fn onScreen(self: Place, screen: c.SDL_Rect) bool {
        const left = @max(self.x, screen.x);
        const right = @min(self.x + self.w, screen.x + screen.w);
        const top_ok = self.y >= screen.y - 8 and self.y < screen.y + screen.h - 40;
        return right - left >= 120 and top_ok;
    }
};

pub fn load(alloc: std.mem.Allocator) ?Place {
    const text = fileio.readWholeFile(alloc, kPath) catch return null;
    defer alloc.free(text);
    return Place.parse(text);
}

pub fn save(p: Place) void {
    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    p.write(&w) catch return;
    fileio.writeWholeFile(kPath, w.buffered()) catch {};
}

/// The usable part of whichever screen `p` is on, if it's on one.
pub fn screenFor(p: Place) ?c.SDL_Rect {
    var count: c_int = 0;
    const ids = c.SDL_GetDisplays(&count) orelse return null;
    defer c.SDL_free(ids);
    for (ids[0..@intCast(count)]) |id| {
        var r: c.SDL_Rect = undefined;
        if (!c.SDL_GetDisplayUsableBounds(id, &r)) continue;
        if (p.onScreen(r)) return r;
    }
    return null;
}

const testing = std.testing;

test "a place written out reads back the same" {
    var p = Place{ .modern = false, .x = -1600, .y = 40, .w = 960, .h = 720, .maximized = true };
    p.setSeen("v1.9");
    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try p.write(&w);
    const back = Place.parse(w.buffered()).?;
    try testing.expectEqual(p.x, back.x);
    try testing.expectEqual(p.y, back.y);
    try testing.expectEqual(p.w, back.w);
    try testing.expectEqual(p.h, back.h);
    try testing.expectEqual(p.modern, back.modern);
    try testing.expectEqual(p.maximized, back.maximized);
    try testing.expectEqual(p.fullscreen, back.fullscreen);
    try testing.expectEqualStrings("v1.9", back.seen());
    // No size, nothing to go on.
    try testing.expect(Place.parse("# nothing\nx = 4\n") == null);
}

test "a window is on a screen only while its title bar is" {
    const screen = c.SDL_Rect{ .x = 0, .y = 25, .w = 1920, .h = 1050 };
    try testing.expect((Place{ .x = 100, .y = 100, .w = 1280, .h = 720 }).onScreen(screen));
    // Mostly off the right edge, but a good piece still on it.
    try testing.expect((Place{ .x = 1700, .y = 100, .w = 1280, .h = 720 }).onScreen(screen));
    // On a second screen that's gone now.
    try testing.expect(!(Place{ .x = 2200, .y = 100, .w = 1280, .h = 720 }).onScreen(screen));
    // Title bar above the top of the screen.
    try testing.expect(!(Place{ .x = 100, .y = -300, .w = 1280, .h = 720 }).onScreen(screen));
}
