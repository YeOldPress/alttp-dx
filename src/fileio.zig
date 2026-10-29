//! Whole-file reads and writes over C stdio.
//!
//! The rest of this port talks to stdio directly rather than through std.Io,
//! and the tools around it do the same so there is one story about file access.

const std = @import("std");

pub extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
pub extern fn fclose(f: *anyopaque) c_int;
pub extern fn fread(ptr: *anyopaque, size: usize, n: usize, f: *anyopaque) usize;
pub extern fn fwrite(ptr: *const anyopaque, size: usize, n: usize, f: *anyopaque) usize;
pub extern fn fseek(f: *anyopaque, off: c_long, whence: c_int) c_int;
pub extern fn ftell(f: *anyopaque) c_long;
pub extern fn remove(path: [*:0]const u8) c_int;
pub extern fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;

const SEEK_SET = 0;
const SEEK_END = 2;

pub fn readWholeFile(alloc: std.mem.Allocator, path: [*:0]const u8) ![]u8 {
    const f = fopen(path, "rb") orelse return error.FileNotFound;
    defer _ = fclose(f);
    if (fseek(f, 0, SEEK_END) != 0) return error.SeekFailed;
    const len = ftell(f);
    if (len < 0) return error.SeekFailed;
    if (fseek(f, 0, SEEK_SET) != 0) return error.SeekFailed;
    const buf = try alloc.alloc(u8, @intCast(len));
    errdefer alloc.free(buf);
    if (buf.len != 0 and fread(buf.ptr, 1, buf.len, f) != buf.len) return error.ReadFailed;
    return buf;
}

pub fn writeWholeFile(path: [*:0]const u8, data: []const u8) !void {
    const f = fopen(path, "wb") orelse return error.OpenFailed;
    defer _ = fclose(f);
    if (data.len != 0 and fwrite(data.ptr, 1, data.len, f) != data.len) return error.WriteFailed;
}

pub extern fn chdir(path: [*:0]const u8) c_int;
pub extern fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;

/// Moves the process into `path`. The game resolves its config and assets
/// against the working directory, so anything that launches it has to agree
/// about what that directory is.
pub fn setWorkingDirectory(path: [*:0]const u8) !void {
    if (chdir(path) != 0) return error.ChdirFailed;
}

/// The working directory, into `buf`.
pub fn workingDirectory(buf: []u8) ![:0]const u8 {
    const p = getcwd(buf.ptr, buf.len) orelse return error.GetCwdFailed;
    return std.mem.span(p);
}

extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
/// The Windows CRT spells it _mkdir, and it takes no mode.
extern fn _mkdir(path: [*:0]const u8) c_int;

/// Makes a directory. Succeeds if it's already there.
pub fn makeDir(path: [*:0]const u8) !void {
    const rc = if (@import("builtin").os.tag == .windows) _mkdir(path) else mkdir(path, 0o755);
    if (rc != 0 and !isDir(path)) return error.MakeDirFailed;
}

extern fn rmdir(path: [*:0]const u8) c_int;
extern fn _rmdir(path: [*:0]const u8) c_int;

/// Removes an empty directory. Best effort.
pub fn removeDir(path: [*:0]const u8) void {
    _ = if (@import("builtin").os.tag == .windows) _rmdir(path) else rmdir(path);
}

extern fn opendir(path: [*:0]const u8) ?*anyopaque;
extern fn closedir(d: *anyopaque) c_int;
/// Windows' CRT has no opendir, so Windows gets asked directly.
extern "kernel32" fn GetFileAttributesW(path: [*:0]const u16) callconv(.winapi) u32;
const FILE_ATTRIBUTE_DIRECTORY = 0x10;

/// Whether a directory exists at `path`.
pub fn isDir(path: [*:0]const u8) bool {
    if (@import("builtin").os.tag == .windows) {
        // Not by fopening "path/.": Windows drops a trailing "\." before
        // looking, so that opened files and refused folders.
        // UTF-16 never takes more units than UTF-8 takes bytes.
        var buf: [4096:0]u16 = undefined;
        const utf8 = std.mem.span(path);
        if (utf8.len >= buf.len) return false;
        const len = std.unicode.utf8ToUtf16Le(&buf, utf8) catch return false;
        buf[len] = 0;
        const attrs = GetFileAttributesW(buf[0..len :0]);
        return attrs != std.os.windows.INVALID_FILE_ATTRIBUTES and attrs & FILE_ATTRIBUTE_DIRECTORY != 0;
    }
    const d = opendir(path) orelse return false;
    _ = closedir(d);
    return true;
}

/// True if the file can be opened for reading. Used by tests that need a file
/// the repository does not ship.
pub fn exists(path: [*:0]const u8) bool {
    const f = fopen(path, "rb") orelse return false;
    _ = fclose(f);
    return true;
}
