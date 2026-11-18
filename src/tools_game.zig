//! Noticing when the files being modded for the game change, so the tools
//! can build them in again.
const std = @import("std");
const c = @import("sdl.zig").c;
const fileio = @import("fileio.zig");

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
