//! Reading .zip files: the central directory for where each file is, stored
//! or deflated data, Zip64 for archives past 4 GB, and every file checked
//! against its CRC on the way out.
//!
//! MSU-1 packs and the Windows update both come as zips, so they share this
//! rather than each carrying a reader or handing the job to a library.

const std = @import("std");
const builtin = @import("builtin");
const fileio = @import("fileio.zig");
const flate = std.compress.flate;

pub const Error = error{
    /// The zip is broken, or uses something this doesn't read.
    BadZip,
    /// A file's data didn't come out as the zip says it should.
    Corrupt,
    /// Writing a file out went wrong, likely a full disk.
    WriteFailed,
    OutOfMemory,
};

/// One file in the zip, as its central directory describes it.
pub const Entry = struct {
    /// The name as stored, folders and all, with forward slashes.
    name: []const u8,
    offset: u64,
    method: u16,
    compressed: u64,
    size: u64,
    crc: u32,

    pub fn isDir(self: Entry) bool {
        return self.name.len > 0 and self.name[self.name.len - 1] == '/';
    }
};

extern fn fseeko(f: *anyopaque, off: i64, whence: c_int) c_int;
extern fn ftello(f: *anyopaque) i64;
extern fn _fseeki64(f: *anyopaque, off: i64, whence: c_int) c_int;
extern fn _ftelli64(f: *anyopaque) i64;

/// Seeking past 2 GB, which plain fseek can't do on Windows.
fn seek(f: *anyopaque, off: u64, whence: c_int) bool {
    const o: i64 = @intCast(off);
    return (if (builtin.os.tag == .windows) _fseeki64(f, o, whence) else fseeko(f, o, whence)) == 0;
}

fn tell(f: *anyopaque) i64 {
    return if (builtin.os.tag == .windows) _ftelli64(f) else ftello(f);
}

fn readAt(f: *anyopaque, off: u64, buf: []u8) Error!void {
    if (!seek(f, off, 0)) return error.BadZip;
    if (buf.len != 0 and fileio.fread(buf.ptr, 1, buf.len, f) != buf.len) return error.BadZip;
}

fn le16(b: []const u8) u16 {
    return std.mem.readInt(u16, b[0..2], .little);
}
fn le32(b: []const u8) u32 {
    return std.mem.readInt(u32, b[0..4], .little);
}
fn le64(b: []const u8) u64 {
    return std.mem.readInt(u64, b[0..8], .little);
}

/// Every file and folder in the open zip `f`. Names point into `arena`.
pub fn readDirectory(arena: std.mem.Allocator, f: *anyopaque) Error![]Entry {
    if (!seek(f, 0, 2)) return error.BadZip;
    const size: u64 = @intCast(@max(tell(f), 0));
    if (size < 22) return error.BadZip;

    // The end-of-directory record is the last thing in the file, after a
    // comment of up to 64K.
    const tail_len: usize = @intCast(@min(size, 22 + 0xffff));
    const tail = arena.alloc(u8, tail_len) catch return error.OutOfMemory;
    try readAt(f, size - tail_len, tail);
    var eocd: usize = tail_len - 22;
    while (le32(tail[eocd..]) != 0x06054b50) {
        if (eocd == 0) return error.BadZip;
        eocd -= 1;
    }
    var count: u64 = le16(tail[eocd + 10 ..]);
    var dir_size: u64 = le32(tail[eocd + 12 ..]);
    var dir_offset: u64 = le32(tail[eocd + 16 ..]);

    // Zip64: the real numbers are in a record the locator just before points to.
    if (count == 0xffff or dir_size == 0xffffffff or dir_offset == 0xffffffff) {
        const eocd_at = size - tail_len + eocd;
        if (eocd_at < 20) return error.BadZip;
        var locator: [20]u8 = undefined;
        try readAt(f, eocd_at - 20, &locator);
        if (le32(&locator) != 0x07064b50) return error.BadZip;
        var rec: [56]u8 = undefined;
        try readAt(f, le64(locator[8..]), &rec);
        if (le32(&rec) != 0x06064b50) return error.BadZip;
        count = le64(rec[32..]);
        dir_size = le64(rec[40..]);
        dir_offset = le64(rec[48..]);
    }
    if (dir_offset + dir_size > size) return error.BadZip;

    const dir = arena.alloc(u8, @intCast(dir_size)) catch return error.OutOfMemory;
    try readAt(f, dir_offset, dir);
    var entries: std.ArrayList(Entry) = .empty;
    var at: usize = 0;
    var n: u64 = 0;
    while (n < count) : (n += 1) {
        if (at + 46 > dir.len or le32(dir[at..]) != 0x02014b50) return error.BadZip;
        const h = dir[at..];
        const name_len = le16(h[28..]);
        const extra_len = le16(h[30..]);
        const comment_len = le16(h[32..]);
        if (at + 46 + name_len + extra_len > dir.len) return error.BadZip;
        var e = Entry{
            .name = h[46..][0..name_len],
            .method = le16(h[10..]),
            .crc = le32(h[16..]),
            .compressed = le32(h[20..]),
            .size = le32(h[24..]),
            .offset = le32(h[42..]),
        };
        zip64Sizes(&e, h[46 + name_len ..][0..extra_len]);
        at += 46 + name_len + extra_len + comment_len;
        entries.append(arena, e) catch return error.OutOfMemory;
    }
    return entries.items;
}

/// Zip64's extra field carries whichever of the sizes and offset didn't fit
/// in 32 bits, in that order.
fn zip64Sizes(e: *Entry, extra: []const u8) void {
    var at: usize = 0;
    while (at + 4 <= extra.len) {
        const id = le16(extra[at..]);
        const len = le16(extra[at + 2 ..]);
        if (at + 4 + len > extra.len) return;
        if (id == 0x0001) {
            var p = extra[at + 4 ..][0..len];
            if (e.size == 0xffffffff and p.len >= 8) {
                e.size = le64(p);
                p = p[8..];
            }
            if (e.compressed == 0xffffffff and p.len >= 8) {
                e.compressed = le64(p);
                p = p[8..];
            }
            if (e.offset == 0xffffffff and p.len >= 8) e.offset = le64(p);
            return;
        }
        at += 4 + len;
    }
}

/// Writes one entry of the open zip `f` out to `dest`, checking its size and
/// CRC.
/// The first bytes of a stored (uncompressed) entry, into `buf`. False for
/// a compressed one, whose start can't be had without inflating it.
pub fn readStart(f: *anyopaque, e: Entry, buf: []u8) Error!bool {
    if (e.method != 0) return false;
    if (e.size < buf.len) return error.Corrupt;
    var local: [30]u8 = undefined;
    try readAt(f, e.offset, &local);
    if (le32(&local) != 0x04034b50) return error.BadZip;
    try readAt(f, e.offset + 30 + le16(local[26..]) + le16(local[28..]), buf);
    return true;
}

pub fn extract(alloc: std.mem.Allocator, f: *anyopaque, e: Entry, dest: [:0]const u8) Error!void {
    var local: [30]u8 = undefined;
    try readAt(f, e.offset, &local);
    if (le32(&local) != 0x04034b50) return error.BadZip;
    const data_at = e.offset + 30 + le16(local[26..]) + le16(local[28..]);
    if (!seek(f, data_at, 0)) return error.BadZip;

    const out = fileio.fopen(dest.ptr, "wb") orelse return error.WriteFailed;
    defer _ = fileio.fclose(out);
    var crc = std.hash.Crc32.init();
    var written: u64 = 0;
    var chunk: [64 * 1024]u8 = undefined;

    switch (e.method) {
        // Stored: the file as it is.
        0 => {
            var left = e.compressed;
            while (left > 0) {
                const n: usize = @intCast(@min(left, chunk.len));
                if (fileio.fread(&chunk, 1, n, f) != n) return error.BadZip;
                crc.update(chunk[0..n]);
                if (fileio.fwrite(&chunk, 1, n, out) != n) return error.WriteFailed;
                written += n;
                left -= n;
            }
        },
        // Deflated: read whole, which for an MSU track is tens of megabytes,
        // and inflated a chunk at a time on the way out.
        8 => {
            const packed_data = alloc.alloc(u8, @intCast(e.compressed)) catch return error.OutOfMemory;
            defer alloc.free(packed_data);
            if (packed_data.len != 0 and fileio.fread(packed_data.ptr, 1, packed_data.len, f) != packed_data.len) return error.BadZip;
            var input = std.Io.Reader.fixed(packed_data);
            var window: [flate.max_window_len]u8 = undefined;
            var inflater = flate.Decompress.init(&input, .raw, &window);
            while (true) {
                const n = inflater.reader.readSliceShort(&chunk) catch return error.Corrupt;
                if (n == 0) break;
                crc.update(chunk[0..n]);
                if (fileio.fwrite(&chunk, 1, n, out) != n) return error.WriteFailed;
                written += n;
                if (n < chunk.len) break;
            }
        },
        else => return error.BadZip,
    }
    if (written != e.size or crc.final() != e.crc) return error.Corrupt;
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

/// A zip of `files`, name and contents, written to `path`: the first stored
/// and the rest deflated. For tests here and in the modules that read zips.
pub fn writeTestZip(path: [:0]const u8, files: []const [2][]const u8) !void {
    const alloc = testing.allocator;
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    var dir: std.Io.Writer.Allocating = .init(alloc);
    defer dir.deinit();
    for (files, 0..) |file, i| {
        const name = file[0];
        const data = file[1];
        // The compressor wants room in its output before it starts.
        var packed_data = try std.Io.Writer.Allocating.initCapacity(alloc, 4096);
        defer packed_data.deinit();
        const method: u16 = if (i == 0) 0 else 8;
        if (method == 0) {
            try packed_data.writer.writeAll(data);
        } else {
            var window: [flate.max_window_len]u8 = undefined;
            var deflater = try flate.Compress.init(&packed_data.writer, &window, .raw, .default);
            try deflater.writer.writeAll(data);
            try deflater.finish();
        }
        const crc = std.hash.Crc32.hash(data);
        const offset: u32 = @intCast(out.written().len);
        const w = &out.writer;
        try w.writeInt(u32, 0x04034b50, .little);
        try w.writeInt(u16, 20, .little);
        try w.writeInt(u16, 0, .little);
        try w.writeInt(u16, method, .little);
        try w.writeInt(u32, 0, .little);
        try w.writeInt(u32, crc, .little);
        try w.writeInt(u32, @intCast(packed_data.written().len), .little);
        try w.writeInt(u32, @intCast(data.len), .little);
        try w.writeInt(u16, @intCast(name.len), .little);
        try w.writeInt(u16, 0, .little);
        try w.writeAll(name);
        try w.writeAll(packed_data.written());

        const d = &dir.writer;
        try d.writeInt(u32, 0x02014b50, .little);
        try d.writeInt(u16, 20, .little);
        try d.writeInt(u16, 20, .little);
        try d.writeInt(u16, 0, .little);
        try d.writeInt(u16, method, .little);
        try d.writeInt(u32, 0, .little);
        try d.writeInt(u32, crc, .little);
        try d.writeInt(u32, @intCast(packed_data.written().len), .little);
        try d.writeInt(u32, @intCast(data.len), .little);
        try d.writeInt(u16, @intCast(name.len), .little);
        try d.writeInt(u16, 0, .little);
        try d.writeInt(u16, 0, .little);
        try d.writeInt(u16, 0, .little);
        try d.writeInt(u16, 0, .little);
        try d.writeInt(u32, 0, .little);
        try d.writeInt(u32, offset, .little);
        try d.writeAll(name);
    }
    const dir_offset: u32 = @intCast(out.written().len);
    try out.writer.writeAll(dir.written());
    const w = &out.writer;
    try w.writeInt(u32, 0x06054b50, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, @intCast(files.len), .little);
    try w.writeInt(u16, @intCast(files.len), .little);
    try w.writeInt(u32, @intCast(dir.written().len), .little);
    try w.writeInt(u32, dir_offset, .little);
    try w.writeInt(u16, 0, .little);
    try fileio.writeWholeFile(path.ptr, out.written());
}

test "a zip lists its files and gives them back byte for byte" {
    const path = ".zig-cache/zip-test.zip";
    const out_path = ".zig-cache/zip-test-out.txt";
    defer {
        _ = fileio.remove(path);
        _ = fileio.remove(out_path);
    }
    const big = comptime blk: {
        const word = "deflate me ";
        var out: [word.len * 50]u8 = undefined;
        for (0..50) |i| @memcpy(out[i * word.len ..][0..word.len], word);
        const final = out;
        break :blk &final;
    };
    try writeTestZip(path, &.{ .{ "top/stored.txt", "as it is" }, .{ "top/inner/deflated.txt", big } });

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const f = fileio.fopen(path, "rb").?;
    defer _ = fileio.fclose(f);
    const entries = try readDirectory(arena_state.allocator(), f);
    try testing.expectEqual(@as(usize, 2), entries.len);
    try testing.expectEqualStrings("top/stored.txt", entries[0].name);
    try testing.expectEqualStrings("top/inner/deflated.txt", entries[1].name);

    try extract(testing.allocator, f, entries[1], out_path);
    const got = try fileio.readWholeFile(testing.allocator, out_path);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings(big, got);
}

test "a file that isn't a zip says so" {
    const path = ".zig-cache/zip-test-not.zip";
    defer _ = fileio.remove(path);
    try fileio.writeWholeFile(path, "this is not a zip, it just wants to be one when it grows up");
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const f = fileio.fopen(path, "rb").?;
    defer _ = fileio.fclose(f);
    try testing.expectError(error.BadZip, readDirectory(arena_state.allocator(), f));
}
