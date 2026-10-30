//! Pictures for the Graphics page: the PNGs an export writes, and Link
//! sprites in the .zspr format the game loads, turned into plain RGBA to
//! draw, with a line saying what each one is.
const std = @import("std");
const c = @import("sdl.zig").c;
const png = @import("png.zig");
const fileio = @import("fileio.zig");

pub const Picture = struct {
    width: u32,
    height: u32,
    /// Red, green, blue, alpha, a byte each, rows top to bottom.
    rgba: []u8,
    /// What it is, to show under it.
    about_buf: [96]u8 = undefined,
    about_len: usize = 0,

    pub fn deinit(self: *Picture, alloc: std.mem.Allocator) void {
        alloc.free(self.rgba);
        self.* = undefined;
    }

    pub fn about(self: *const Picture) []const u8 {
        return self.about_buf[0..self.about_len];
    }

    fn setAbout(self: *Picture, comptime fmt: []const u8, args: anytype) void {
        // Too long to fit is cut short rather than lost.
        self.about_len = if (std.fmt.bufPrint(&self.about_buf, fmt, args)) |t| t.len else |_| self.about_buf.len;
    }
};

pub fn loadPng(alloc: std.mem.Allocator, path: [:0]const u8) !Picture {
    const bytes = try fileio.readWholeFile(alloc, path.ptr);
    defer alloc.free(bytes);
    var img = try png.decode(alloc, bytes);
    defer img.deinit(alloc);
    const rgba = try alloc.alloc(u8, @as(usize, img.width) * img.height * 4);
    for (0..img.height) |y| {
        for (0..img.width) |x| {
            const i = y * img.width + x;
            const rgb = img.rgbAt(x, y);
            rgba[i * 4 ..][0..4].* = .{ @truncate(rgb >> 16), @truncate(rgb >> 8), @truncate(rgb), if (img.kind == .rgba) img.pixels[i * 4 + 3] else 255 };
        }
    }
    var p = Picture{ .width = img.width, .height = img.height, .rgba = rgba };
    p.setAbout("{s}, {d} by {d}", .{ std.fs.path.basename(path), img.width, img.height });
    return p;
}

// --------------------------------------------------------------------- .zspr

/// Link's whole sheet: what the game copies out of a .zspr, and the only
/// size it takes.
const kSheetBytes = 0x7000;
/// Laid out sixteen tiles across, as sprite editors show it.
const kSheetW = 128;
const kSheetH = kSheetBytes / 32 / 16 * 8;

pub const ZsprError = error{ NotZspr, Truncated, WrongSize };

/// Why a .zspr won't load, in words, following its name.
pub fn zsprProblem(e: anyerror) []const u8 {
    return switch (e) {
        error.NotZspr => "isn't a Link sprite: a .zspr starts with ZSPR.",
        error.Truncated => "is cut short: its picture or colors run past the end.",
        error.WrongSize => "holds the wrong amount of picture. The game needs a full sheet of Link.",
        error.FileNotFound => "isn't there.",
        else => "couldn't be read.",
    };
}

/// Reads a .zspr as the game does, refusing what the game would, and draws
/// its sheet in its green-mail colors.
pub fn loadZspr(alloc: std.mem.Allocator, path: [:0]const u8) !Picture {
    const file = try fileio.readWholeFile(alloc, path.ptr);
    defer alloc.free(file);
    var p = try decodeZspr(alloc, file);
    const name = utf16Field(file, 29);
    const author = utf16Field(file, 29 + name.bytes);
    if (name.len == 0) {
        p.setAbout("{s}: looks good", .{std.fs.path.basename(path)});
    } else if (author.len == 0) {
        p.setAbout("{s}: looks good", .{name.text()});
    } else {
        p.setAbout("{s} by {s}: looks good", .{ name.text(), author.text() });
    }
    return p;
}

fn decodeZspr(alloc: std.mem.Allocator, file: []const u8) !Picture {
    // The same checks the game makes before it takes a sprite.
    if (file.len < 27 or !std.mem.eql(u8, file[0..4], "ZSPR")) return error.NotZspr;
    const pixel_offs = std.mem.readInt(u32, file[9..13], .little);
    const pixel_len = std.mem.readInt(u16, file[13..15], .little);
    const palette_offs = std.mem.readInt(u32, file[15..19], .little);
    const palette_len = std.mem.readInt(u16, file[19..21], .little);
    if (@as(u64, pixel_offs) + pixel_len > file.len or @as(u64, palette_offs) + palette_len > file.len) return error.Truncated;
    if (pixel_len != kSheetBytes) return error.WrongSize;

    // Fifteen colors to a mail; green comes first. A sprite without colors
    // keeps Link's in the game, and shows in grays here.
    var colors: [16][4]u8 = undefined;
    colors[0] = .{ 0, 0, 0, 0 };
    for (1..16) |i| {
        if (palette_len >= 30) {
            const v = std.mem.readInt(u16, file[palette_offs + (i - 1) * 2 ..][0..2], .little);
            colors[i] = .{ scale5(v), scale5(v >> 5), scale5(v >> 10), 255 };
        } else {
            const g: u8 = @intCast(i * 16);
            colors[i] = .{ g, g, g, 255 };
        }
    }

    const rgba = try alloc.alloc(u8, kSheetW * kSheetH * 4);
    const tiles = file[pixel_offs..][0..kSheetBytes];
    for (0..kSheetBytes / 32) |t| {
        const tile = tiles[t * 32 ..][0..32];
        const tx = (t % 16) * 8;
        const ty = (t / 16) * 8;
        for (0..8) |row| {
            const planes = [4]u8{ tile[row * 2], tile[row * 2 + 1], tile[16 + row * 2], tile[16 + row * 2 + 1] };
            for (0..8) |x| {
                const bit: u3 = @intCast(7 - x);
                var idx: usize = 0;
                for (planes, 0..) |plane, k| idx |= @as(usize, (plane >> bit) & 1) << @intCast(k);
                const at = ((ty + row) * kSheetW + tx + x) * 4;
                rgba[at..][0..4].* = colors[idx];
            }
        }
    }
    return .{ .width = kSheetW, .height = kSheetH, .rgba = rgba };
}

fn scale5(v: u16) u8 {
    const five: u16 = v & 31;
    return @intCast(five * 255 / 31);
}

/// A name in a .zspr: UTF-16, ending in a zero. Kept to plain letters, which
/// is all the window's font has.
const Utf16Field = struct {
    buf: [40]u8 = undefined,
    len: usize = 0,
    /// How many bytes it took in the file, the zero included.
    bytes: usize = 0,

    fn text(self: *const Utf16Field) []const u8 {
        return self.buf[0..self.len];
    }
};

fn utf16Field(file: []const u8, at: usize) Utf16Field {
    var f = Utf16Field{};
    var i = at;
    while (i + 2 <= file.len) : (i += 2) {
        const ch = std.mem.readInt(u16, file[i..][0..2], .little);
        if (ch == 0) {
            f.bytes = i + 2 - at;
            return f;
        }
        if (f.len < f.buf.len) {
            f.buf[f.len] = if (ch >= 0x20 and ch < 0x7f) @intCast(ch) else '?';
            f.len += 1;
        }
    }
    f.bytes = file.len -| at;
    return f;
}

// ------------------------------------------------------------------- listing

/// The pictures an export leaves in `folder`: Link, the font and the HUD
/// first, then whatever else is there, then the sprite sheets.
pub fn listPictures(alloc: std.mem.Allocator, folder: []const u8) ![][:0]u8 {
    var out: std.ArrayList([:0]u8) = .empty;
    errdefer {
        for (out.items) |p| alloc.free(p);
        out.deinit(alloc);
    }
    for ([_][]const u8{ "", "sprites" }) |sub| {
        const dir = if (sub.len == 0)
            try alloc.dupeSentinel(u8, folder, 0)
        else
            try std.fmt.allocPrintSentinel(alloc, "{s}/{s}", .{ folder, sub }, 0);
        defer alloc.free(dir);
        var names = Names{ .alloc = alloc };
        defer names.deinit();
        _ = c.SDL_EnumerateDirectory(dir.ptr, Names.add, &names);
        std.mem.sort([]u8, names.list.items, {}, firstThenByName);
        for (names.list.items) |n| try out.append(alloc, try std.fmt.allocPrintSentinel(alloc, "{s}/{s}", .{ dir, n }, 0));
    }
    return out.toOwnedSlice(alloc);
}

pub fn freeList(alloc: std.mem.Allocator, list: [][:0]u8) void {
    for (list) |p| alloc.free(p);
    alloc.free(list);
}

const Names = struct {
    alloc: std.mem.Allocator,
    list: std.ArrayList([]u8) = .empty,

    fn deinit(self: *Names) void {
        for (self.list.items) |n| self.alloc.free(n);
        self.list.deinit(self.alloc);
    }

    fn add(userdata: ?*anyopaque, dirname: [*c]const u8, fname: [*c]const u8) callconv(.c) c.SDL_EnumerationResult {
        _ = dirname;
        const self: *Names = @ptrCast(@alignCast(userdata));
        const name = std.mem.span(fname);
        if (name.len < 5 or !std.ascii.eqlIgnoreCase(name[name.len - 4 ..], ".png")) return c.SDL_ENUM_CONTINUE;
        const copy = self.alloc.dupe(u8, name) catch return c.SDL_ENUM_FAILURE;
        self.list.append(self.alloc, copy) catch {
            self.alloc.free(copy);
            return c.SDL_ENUM_FAILURE;
        };
        return c.SDL_ENUM_CONTINUE;
    }
};

const kFirst = [_][]const u8{ "linksprite.png", "font.png", "hud_icons.png" };

fn rank(name: []const u8) usize {
    for (kFirst, 0..) |f, i| {
        if (std.ascii.eqlIgnoreCase(name, f)) return i;
    }
    return kFirst.len;
}

fn firstThenByName(_: void, a: []u8, b: []u8) bool {
    const ra = rank(a);
    const rb = rank(b);
    if (ra != rb) return ra < rb;
    return std.mem.lessThan(u8, a, b);
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

fn testZspr(alloc: std.mem.Allocator, pixel_len: u16) ![]u8 {
    const header = 29 + 4 + 4;
    const file = try alloc.alloc(u8, header + kSheetBytes + 120);
    @memset(file, 0);
    @memcpy(file[0..4], "ZSPR");
    std.mem.writeInt(u32, file[9..13], header, .little);
    std.mem.writeInt(u16, file[13..15], pixel_len, .little);
    std.mem.writeInt(u32, file[15..19], header + kSheetBytes, .little);
    std.mem.writeInt(u16, file[19..21], 120, .little);
    // "Hi", then no author.
    file[29] = 'H';
    file[31] = 'i';
    // The first tile's top-left pixel is color 1, which is pure red.
    file[header] = 0x80;
    std.mem.writeInt(u16, file[header + kSheetBytes ..][0..2], 0x001f, .little);
    return file;
}

test "a .zspr's sheet comes out in its own colors" {
    const file = try testZspr(testing.allocator, kSheetBytes);
    defer testing.allocator.free(file);
    var p = try decodeZspr(testing.allocator, file);
    defer p.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, 128), p.width);
    try testing.expectEqual(@as(u32, 448), p.height);
    try testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, p.rgba[0..4]);
    // Color 0 is see-through.
    try testing.expectEqual(@as(u8, 0), p.rgba[7]);
    try testing.expectEqualStrings("Hi", utf16Field(file, 29).text());
}

test "a .zspr the game would refuse is refused" {
    const short = try testZspr(testing.allocator, 0x6000);
    defer testing.allocator.free(short);
    try testing.expectError(error.WrongSize, decodeZspr(testing.allocator, short));
    try testing.expectError(error.NotZspr, decodeZspr(testing.allocator, "PNG not a sprite at all, but long enough"));
    const cut = try testZspr(testing.allocator, kSheetBytes);
    defer testing.allocator.free(cut);
    try testing.expectError(error.Truncated, decodeZspr(testing.allocator, cut[0 .. cut.len - 200]));
}

test "Link, the font and the HUD list first" {
    var names = [_][]u8{ @constCast("zz.png"), @constCast("font.png"), @constCast("abc.png"), @constCast("linksprite.png") };
    std.mem.sort([]u8, &names, {}, firstThenByName);
    try testing.expectEqualStrings("linksprite.png", names[0]);
    try testing.expectEqualStrings("font.png", names[1]);
    try testing.expectEqualStrings("abc.png", names[2]);
}
