//! The game, from the tools' side: finding it to start it, and noticing when
//! the files being modded for it change.
const std = @import("std");
const builtin = @import("builtin");
const c = @import("sdl.zig").c;
const fileio = @import("fileio.zig");

/// The game's Mac bundle, which Launch Services can find wherever it was put.
const kMacBundleId = "io.github.yeoldpress.alttp-dx";

/// Where the game is, as something to start: the .app on a Mac, the AppImage
/// or executable elsewhere. Looked for beside the tools, which is where the
/// downloads put them, and in a dev build's output folder. Null when it
/// isn't anywhere obvious; on a Mac it can still be started by its bundle ID.
pub fn find(buf: []u8) ?[:0]const u8 {
    const base = std.mem.span(c.SDL_GetBasePath() orelse return null);
    switch (builtin.os.tag) {
        .macos => {
            const tail = "/Contents/Resources/";
            if (std.mem.endsWith(u8, base, ".app" ++ tail)) {
                const bundle = base[0 .. base.len - tail.len];
                const parent = std.fs.path.dirname(bundle) orelse return null;
                return existing(buf, "{s}/ALTTP-DX.app", .{parent});
            }
            return existing(buf, "{s}zelda3", .{base});
        },
        .linux => {
            if (c.SDL_getenv("APPIMAGE")) |image| {
                const dir = std.fs.path.dirname(std.mem.span(image)) orelse return null;
                return gameAppImage(buf, dir);
            }
            return existing(buf, "{s}zelda3", .{base});
        },
        .windows => {
            // Unzipped side by side, the game and the tools each have a
            // folder; unzipped into one, they share it.
            return existing(buf, "{s}zelda3.exe", .{base}) orelse existing(buf, "{s}..\\alttp-dx\\zelda3.exe", .{base});
        },
        else => return null,
    }
}

/// The folder the game keeps its files in when it isn't packaged: the one it
/// runs from. Null for a packaged game, which keeps them in its data
/// directory instead, as the tools already know.
pub fn folderOf(game: []const u8) ?[]const u8 {
    if (std.mem.endsWith(u8, game, ".app") or std.mem.endsWith(u8, game, ".AppImage")) return null;
    return std.fs.path.dirname(game);
}

fn existing(buf: []u8, comptime fmt: []const u8, args: anytype) ?[:0]const u8 {
    const path = std.fmt.bufPrintSentinel(buf, fmt, args, 0) catch return null;
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(path.ptr, &info)) return null;
    return path;
}

/// The newest alttp-dx-*.AppImage in `dir`, by name, which sorts by version.
fn gameAppImage(buf: []u8, dir: []const u8) ?[:0]const u8 {
    var dir_buf: [4096]u8 = undefined;
    const dir_z = std.fmt.bufPrintSentinel(&dir_buf, "{s}", .{dir}, 0) catch return null;
    var pick = AppImagePick{};
    _ = c.SDL_EnumerateDirectory(dir_z.ptr, AppImagePick.consider, &pick);
    if (pick.len == 0) return null;
    return std.fmt.bufPrintSentinel(buf, "{s}/{s}", .{ dir, pick.name[0..pick.len] }, 0) catch null;
}

const AppImagePick = struct {
    name: [256]u8 = undefined,
    len: usize = 0,

    fn consider(userdata: ?*anyopaque, dirname: [*c]const u8, fname: [*c]const u8) callconv(.c) c.SDL_EnumerationResult {
        _ = dirname;
        const self: *AppImagePick = @ptrCast(@alignCast(userdata));
        const name = std.mem.span(fname);
        if (!std.mem.startsWith(u8, name, "alttp-dx") or !std.mem.endsWith(u8, name, ".AppImage")) return c.SDL_ENUM_CONTINUE;
        if (name.len > self.name.len) return c.SDL_ENUM_CONTINUE;
        if (self.len == 0 or std.mem.order(u8, name, self.name[0..self.len]) == .gt) {
            @memcpy(self.name[0..name.len], name);
            self.len = name.len;
        }
        return c.SDL_ENUM_CONTINUE;
    }
};

/// Starts the game at `path`, or on a Mac where Launch Services knows it,
/// when `path` is null. It goes its own way after; the tools don't wait.
pub fn start(path: ?[:0]const u8) bool {
    const process = if (builtin.os.tag == .macos) blk: {
        if (path) |p| {
            if (std.mem.endsWith(u8, p, ".app")) {
                const args = [_:null]?[*:0]const u8{ "/usr/bin/open", "-n", p.ptr };
                break :blk c.SDL_CreateProcess(@ptrCast(&args), false);
            }
            const args = [_:null]?[*:0]const u8{p.ptr};
            break :blk c.SDL_CreateProcess(@ptrCast(&args), false);
        }
        const args = [_:null]?[*:0]const u8{ "/usr/bin/open", "-n", "-b", kMacBundleId };
        break :blk c.SDL_CreateProcess(@ptrCast(&args), false);
    } else blk: {
        const p = path orelse return false;
        const args = [_:null]?[*:0]const u8{p.ptr};
        break :blk c.SDL_CreateProcess(@ptrCast(&args), false);
    };
    // Letting go of it leaves it running.
    c.SDL_DestroyProcess(process orelse return false);
    return true;
}

// ------------------------------------------------------------------ watching

/// A fingerprint of every file under `dir`, a few folders deep: their
/// count, sizes and times. It changes when anything is saved, added or
/// taken away. Asset files are left out, so building into the folder
/// doesn't count as a change to it.
pub fn stamp(dir: [:0]const u8) u64 {
    var s = Stamp{};
    if (!c.SDL_EnumerateDirectory(dir.ptr, Stamp.visit, &s)) return 0;
    return s.hash.final();
}

const Stamp = struct {
    hash: std.hash.Wyhash = .init(0),
    depth: u8 = 0,

    fn visit(userdata: ?*anyopaque, dirname: [*c]const u8, fname: [*c]const u8) callconv(.c) c.SDL_EnumerationResult {
        const self: *Stamp = @ptrCast(@alignCast(userdata));
        const name = std.mem.span(fname);
        if (std.mem.endsWith(u8, name, ".dat")) return c.SDL_ENUM_CONTINUE;
        var buf: [4096]u8 = undefined;
        const path = std.fmt.bufPrintSentinel(&buf, "{s}{s}", .{ std.mem.span(dirname), name }, 0) catch return c.SDL_ENUM_CONTINUE;
        var info: c.SDL_PathInfo = undefined;
        if (!c.SDL_GetPathInfo(path.ptr, &info)) return c.SDL_ENUM_CONTINUE;
        if (info.type == c.SDL_PATHTYPE_DIRECTORY) {
            if (self.depth < 3) {
                self.depth += 1;
                _ = c.SDL_EnumerateDirectory(path.ptr, visit, self);
                self.depth -= 1;
            }
            return c.SDL_ENUM_CONTINUE;
        }
        self.hash.update(path);
        self.hash.update(std.mem.asBytes(&info.size));
        self.hash.update(std.mem.asBytes(&info.modify_time));
        return c.SDL_ENUM_CONTINUE;
    }
};

test "a folder's stamp changes when a file in it does" {
    const dir = ".zig-cache/tools-watch-test";
    defer {
        _ = c.SDL_RemovePath(dir ++ "/sub/a.yaml");
        _ = c.SDL_RemovePath(dir ++ "/b.dat");
        _ = c.SDL_RemovePath(dir ++ "/sub");
        _ = c.SDL_RemovePath(dir);
    }
    try std.testing.expect(c.SDL_CreateDirectory(dir ++ "/sub"));
    try fileio.writeWholeFile(dir ++ "/sub/a.yaml", "one");
    const before = stamp(dir);
    try std.testing.expectEqual(before, stamp(dir));
    // Building into the folder isn't a change to it.
    try fileio.writeWholeFile(dir ++ "/b.dat", "assets");
    try std.testing.expectEqual(before, stamp(dir));
    try fileio.writeWholeFile(dir ++ "/sub/a.yaml", "one, edited");
    try std.testing.expect(stamp(dir) != before);
}

test "a packaged game keeps its files elsewhere" {
    try std.testing.expectEqual(@as(?[]const u8, null), folderOf("/Applications/ALTTP-DX.app"));
    try std.testing.expectEqualStrings("/games/alttp-dx", folderOf("/games/alttp-dx/zelda3").?);
}
