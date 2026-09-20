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

/// True if the file can be opened for reading. Used by tests that need a file
/// the repository does not ship.
pub fn exists(path: [*:0]const u8) bool {
    const f = fopen(path, "rb") orelse return false;
    _ = fclose(f);
    return true;
}
