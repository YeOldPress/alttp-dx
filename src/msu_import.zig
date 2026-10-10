//! Installing an MSU-1 pack from a folder or a .zip.
//!
//! The game plays track n from MSUPath ++ n ++ ".pcm" (or ".opuz"), so a pack
//! is installed by finding its numbered tracks and copying each one to that
//! name. Packs name their tracks after themselves, "pack-12.pcm", and often
//! sit in a folder inside the zip, so tracks are found by the number at the
//! end of the name wherever they are. The pack already installed is removed
//! first, so two packs' tracks never mix, but only once the new one has been
//! read and turned out to have tracks in it; only files named the way the
//! game names its tracks are touched.
//!
//! Zips are read here rather than handed to a library: the central directory
//! for where each file is, stored or deflated data, Zip64 for packs past 4 GB,
//! and every file checked against its CRC.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("sdl.zig").c;
const fileio = @import("fileio.zig");
const flate = std.compress.flate;

pub const Ext = enum {
    pcm,
    opuz,

    fn name(self: Ext) []const u8 {
        return @tagName(self);
    }
};

/// A track number and format, from a file's name.
pub const TrackName = struct { number: u16, ext: Ext };

/// What a file in a pack is, by its name: track `number`, or null for
/// anything else (the .msu file, readme, cover art, a Mac's ._ resource
/// files).
pub fn trackOf(path: []const u8) ?TrackName {
    if (std.mem.indexOf(u8, path, "__MACOSX") != null) return null;
    const base = basename(path);
    if (std.mem.startsWith(u8, base, "._")) return null;
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return null;
    const ext_text = base[dot + 1 ..];
    const ext: Ext = if (std.ascii.eqlIgnoreCase(ext_text, "pcm"))
        .pcm
    else if (std.ascii.eqlIgnoreCase(ext_text, "opuz"))
        .opuz
    else
        return null;
    const stem = base[0..dot];
    var i = stem.len;
    while (i > 0 and std.ascii.isDigit(stem[i - 1])) i -= 1;
    const digits = stem[i..];
    if (digits.len == 0 or digits.len > 3) return null;
    const number = std.fmt.parseInt(u16, digits, 10) catch return null;
    if (number == 0) return null;
    return .{ .number = number, .ext = ext };
}

fn basename(path: []const u8) []const u8 {
    const cut = std.mem.lastIndexOfAny(u8, path, "/\\") orelse return path;
    return path[cut + 1 ..];
}

pub const Error = error{
    /// The folder or zip isn't there, or can't be read.
    NotFound,
    /// Nothing in it is named like an MSU-1 track.
    NoTracks,
    /// The zip is broken, or uses something this doesn't read.
    BadZip,
    /// A track's data didn't come out as the zip says it should.
    Corrupt,
    /// Writing a track went wrong, likely a full disk.
    WriteFailed,
    OutOfMemory,
};

/// Words for the start menu's status line.
pub fn describe(err: Error) []const u8 {
    return switch (err) {
        error.NotFound => "COULD NOT OPEN THAT",
        error.NoTracks => "NO MSU-1 TRACKS IN THAT",
        error.BadZip => "COULD NOT READ THAT ZIP",
        error.Corrupt => "A TRACK IN THE ZIP IS DAMAGED",
        error.WriteFailed => "COULD NOT WRITE THE TRACKS",
        error.OutOfMemory => "OUT OF MEMORY",
    };
}

/// Told how far the copying has got, for a status line.
pub const Progress = struct {
    ctx: *anyopaque,
    f: *const fn (ctx: *anyopaque, done: usize, total: usize) void,

    fn report(self: ?Progress, done: usize, total: usize) void {
        if (self) |p| p.f(p.ctx, done, total);
    }
};

const ZipEntry = struct {
    offset: u64,
    method: u16,
    compressed: u64,
    size: u64,
    crc: u32,
};

const Track = struct {
    name: TrackName,
    source: union(enum) {
        file: [:0]u8,
        zip: ZipEntry,
    },
};

/// Installs the pack at `source`, a folder or a .zip, as the tracks
/// `msu_path` names. Returns how many tracks it installed.
pub fn importPack(alloc: std.mem.Allocator, source: [:0]const u8, msu_path: []const u8, progress: ?Progress) Error!usize {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tracks: std.ArrayList(Track) = .empty;
    const is_zip = !fileio.isDir(source.ptr);
    if (is_zip) {
        try readZip(arena, source, &tracks);
    } else {
        try readFolder(arena, source, &tracks);
    }
    dedupe(&tracks);
    if (tracks.items.len == 0) return error.NoTracks;

    const split = splitMsuPath(msu_path);
    const dir_z = arena.dupeSentinel(u8, split.dir, 0) catch return error.OutOfMemory;
    if (!c.SDL_CreateDirectory(dir_z.ptr)) return error.WriteFailed;
    removeOldPack(arena, dir_z, split.prefix);

    var zip: ?*anyopaque = null;
    if (is_zip) zip = fileio.fopen(source.ptr, "rb") orelse return error.NotFound;
    defer if (zip) |f| {
        _ = fileio.fclose(f);
    };

    for (tracks.items, 0..) |t, i| {
        Progress.report(progress, i, tracks.items.len);
        const dest = std.fmt.allocPrintSentinel(arena, "{s}{d}.{s}", .{ msu_path, t.name.number, t.name.ext.name() }, 0) catch return error.OutOfMemory;
        switch (t.source) {
            .file => |path| if (!c.SDL_CopyFile(path.ptr, dest.ptr)) return error.WriteFailed,
            .zip => |e| extract(alloc, zip.?, e, dest) catch |err| {
                _ = fileio.remove(dest.ptr);
                return err;
            },
        }
    }
    Progress.report(progress, tracks.items.len, tracks.items.len);
    return tracks.items.len;
}

/// The same track twice (two packs in one zip, say) keeps the first.
fn dedupe(tracks: *std.ArrayList(Track)) void {
    var kept: usize = 0;
    outer: for (tracks.items) |t| {
        for (tracks.items[0..kept]) |k| {
            if (k.name.number == t.name.number and k.name.ext == t.name.ext) continue :outer;
        }
        tracks.items[kept] = t;
        kept += 1;
    }
    tracks.shrinkRetainingCapacity(kept);
}

/// MSUPath as a folder and the start of each track's name in it:
/// "msu/alttp_msu-" is "msu" and "alttp_msu-".
fn splitMsuPath(msu_path: []const u8) struct { dir: []const u8, prefix: []const u8 } {
    const cut = std.mem.lastIndexOfAny(u8, msu_path, "/\\") orelse return .{ .dir = ".", .prefix = msu_path };
    return .{ .dir = if (cut == 0) "/" else msu_path[0..cut], .prefix = msu_path[cut + 1 ..] };
}

/// Whether `name` is one of the game's own tracks: the prefix, a number, and
/// .pcm or .opuz, nothing else.
fn isInstalledTrack(name: []const u8, prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, name, prefix)) return false;
    const t = trackOf(name) orelse return false;
    var buf: [32]u8 = undefined;
    const want = std.fmt.bufPrint(&buf, "{d}.{s}", .{ t.number, t.ext.name() }) catch return false;
    return std.ascii.eqlIgnoreCase(name[prefix.len..], want);
}

// ------------------------------------------------------------------ folders

const ListCtx = struct {
    arena: std.mem.Allocator,
    paths: *std.ArrayList([:0]u8),
    depth: u8,
    failed: bool = false,
};

fn listCallback(userdata: ?*anyopaque, dirname: [*c]const u8, fname: [*c]const u8) callconv(.c) c.SDL_EnumerationResult {
    const ctx: *ListCtx = @ptrCast(@alignCast(userdata));
    const path = std.fmt.allocPrintSentinel(ctx.arena, "{s}{s}", .{ std.mem.span(dirname), std.mem.span(fname) }, 0) catch {
        ctx.failed = true;
        return c.SDL_ENUM_FAILURE;
    };
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(path.ptr, &info)) return c.SDL_ENUM_CONTINUE;
    if (info.type == c.SDL_PATHTYPE_DIRECTORY) {
        // Packs come in a folder or two of their own, not a whole disk.
        if (ctx.depth < 3) {
            var sub = ListCtx{ .arena = ctx.arena, .paths = ctx.paths, .depth = ctx.depth + 1 };
            _ = c.SDL_EnumerateDirectory(path.ptr, listCallback, &sub);
            if (sub.failed) ctx.failed = true;
        }
    } else if (info.type == c.SDL_PATHTYPE_FILE) {
        ctx.paths.append(ctx.arena, path) catch {
            ctx.failed = true;
            return c.SDL_ENUM_FAILURE;
        };
    }
    return c.SDL_ENUM_CONTINUE;
}

/// Every file under `dir`, a few folders deep.
fn listFiles(arena: std.mem.Allocator, dir: [:0]const u8) Error![][:0]u8 {
    var paths: std.ArrayList([:0]u8) = .empty;
    var ctx = ListCtx{ .arena = arena, .paths = &paths, .depth = 0 };
    if (!c.SDL_EnumerateDirectory(dir.ptr, listCallback, &ctx)) return error.NotFound;
    if (ctx.failed) return error.OutOfMemory;
    // Folders list in whatever order the disk has them; this keeps "the
    // first" of two copies of a track the same every time.
    std.mem.sort([:0]u8, paths.items, {}, struct {
        fn lt(_: void, a: [:0]u8, b: [:0]u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return paths.items;
}

fn readFolder(arena: std.mem.Allocator, dir: [:0]const u8, tracks: *std.ArrayList(Track)) Error!void {
    for (try listFiles(arena, dir)) |path| {
        const name = trackOf(path) orelse continue;
        try tracks.append(arena, .{ .name = name, .source = .{ .file = path } });
    }
}

/// Takes out the pack that's there now: every file in its folder named the
/// way the game names a track, and nothing else.
fn removeOldPack(arena: std.mem.Allocator, dir: [:0]const u8, prefix: []const u8) void {
    var paths: std.ArrayList([:0]u8) = .empty;
    var ctx = ListCtx{ .arena = arena, .paths = &paths, .depth = 3 };
    _ = c.SDL_EnumerateDirectory(dir.ptr, listCallback, &ctx);
    for (paths.items) |path| {
        if (isInstalledTrack(basename(path), prefix)) _ = c.SDL_RemovePath(path.ptr);
    }
}

// --------------------------------------------------------------------- zips

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

fn readZip(arena: std.mem.Allocator, path: [:0]const u8, tracks: *std.ArrayList(Track)) Error!void {
    const f = fileio.fopen(path.ptr, "rb") orelse return error.NotFound;
    defer _ = fileio.fclose(f);
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
    var at: usize = 0;
    var n: u64 = 0;
    while (n < count) : (n += 1) {
        if (at + 46 > dir.len or le32(dir[at..]) != 0x02014b50) return error.BadZip;
        const h = dir[at..];
        var e = ZipEntry{
            .method = le16(h[10..]),
            .crc = le32(h[16..]),
            .compressed = le32(h[20..]),
            .size = le32(h[24..]),
            .offset = le32(h[42..]),
        };
        const name_len = le16(h[28..]);
        const extra_len = le16(h[30..]);
        const comment_len = le16(h[32..]);
        if (at + 46 + name_len + extra_len > dir.len) return error.BadZip;
        const name = h[46..][0..name_len];
        zip64Sizes(&e, h[46 + name_len ..][0..extra_len]);
        at += 46 + name_len + extra_len + comment_len;

        const t = trackOf(name) orelse continue;
        if (name.len > 0 and name[name.len - 1] == '/') continue;
        try tracks.append(arena, .{ .name = t, .source = .{ .zip = e } });
    }
}

/// Zip64's extra field carries whichever of the sizes and offset didn't fit
/// in 32 bits, in that order.
fn zip64Sizes(e: *ZipEntry, extra: []const u8) void {
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

/// Writes one entry of the zip out to `dest`, checking its size and CRC.
fn extract(alloc: std.mem.Allocator, f: *anyopaque, e: ZipEntry, dest: [:0]const u8) Error!void {
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
        // Stored: the track as it is.
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
        // Deflated: read whole, which for a track is tens of megabytes, and
        // inflated a chunk at a time on the way out.
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

test "tracks are known by the number at the end of their name" {
    try testing.expectEqual(TrackName{ .number = 12, .ext = .pcm }, trackOf("Some Pack/pack-12.pcm").?);
    try testing.expectEqual(TrackName{ .number = 1, .ext = .opuz }, trackOf("alttp_msu-1.OPUZ").?);
    try testing.expectEqual(TrackName{ .number = 7, .ext = .pcm }, trackOf("C:\\packs\\remix_07.pcm").?);
    try testing.expectEqual(@as(?TrackName, null), trackOf("pack.msu"));
    try testing.expectEqual(@as(?TrackName, null), trackOf("readme.txt"));
    try testing.expectEqual(@as(?TrackName, null), trackOf("pack-.pcm"));
    try testing.expectEqual(@as(?TrackName, null), trackOf("pack-0.pcm"));
    try testing.expectEqual(@as(?TrackName, null), trackOf("__MACOSX/pack/._pack-1.pcm"));
    try testing.expectEqual(@as(?TrackName, null), trackOf("pack/._pack-1.pcm"));
}

test "only the game's own track names count as the installed pack" {
    try testing.expect(isInstalledTrack("alttp_msu-1.pcm", "alttp_msu-"));
    try testing.expect(isInstalledTrack("alttp_msu-34.opuz", "alttp_msu-"));
    try testing.expect(!isInstalledTrack("alttp_msu-1.pcm.bak", "alttp_msu-"));
    try testing.expect(!isInstalledTrack("alttp_msu-01.pcm", "alttp_msu-"));
    try testing.expect(!isInstalledTrack("other-1.pcm", "alttp_msu-"));
    try testing.expect(!isInstalledTrack("alttp_msu-.msu", "alttp_msu-"));
}

test "MSUPath splits into its folder and the start of the names" {
    const s = splitMsuPath("msu/alttp_msu-");
    try testing.expectEqualStrings("msu", s.dir);
    try testing.expectEqualStrings("alttp_msu-", s.prefix);
    try testing.expectEqualStrings(".", splitMsuPath("alttp_msu-").dir);
}

/// `text` `n` times over, for test data that compresses.
fn repeat(comptime text: []const u8, comptime n: usize) *const [text.len * n]u8 {
    var out: [text.len * n]u8 = undefined;
    for (0..n) |i| @memcpy(out[i * text.len ..][0..text.len], text);
    const final = out;
    return &final;
}

/// A zip of `files` written to `path`, the first stored and the rest deflated.
fn writeTestZip(path: [:0]const u8, files: []const [2][]const u8) !void {
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

test "a zipped pack replaces the installed one, track for track" {
    const root = ".zig-cache/msu-import-test";
    const msu_dir = root ++ "/msu";
    const zip_path = root ++ "/pack.zip";
    const alloc = testing.allocator;
    _ = c.SDL_RemovePath(msu_dir ++ "/alttp_msu-1.pcm");
    _ = c.SDL_RemovePath(msu_dir ++ "/alttp_msu-2.pcm");
    _ = c.SDL_RemovePath(msu_dir ++ "/alttp_msu-9.pcm");
    _ = c.SDL_RemovePath(msu_dir ++ "/notes.txt");
    try testing.expect(c.SDL_CreateDirectory(msu_dir));
    defer {
        for ([_][*:0]const u8{ msu_dir ++ "/alttp_msu-1.pcm", msu_dir ++ "/alttp_msu-2.pcm", msu_dir ++ "/alttp_msu-9.pcm", msu_dir ++ "/notes.txt", zip_path }) |p| _ = c.SDL_RemovePath(p);
        _ = c.SDL_RemovePath(msu_dir);
        _ = c.SDL_RemovePath(root);
    }

    // An old pack with a track the new one hasn't got, and a file that isn't
    // a track at all.
    try fileio.writeWholeFile(msu_dir ++ "/alttp_msu-9.pcm", "old nine");
    try fileio.writeWholeFile(msu_dir ++ "/notes.txt", "mine");

    const one = "MSU1" ++ "first track, stored";
    const two = "MSU1" ++ comptime repeat("second track, deflated ", 40);
    try writeTestZip(zip_path, &.{
        .{ "Cool Pack/cool-1.pcm", one },
        .{ "Cool Pack/cool-2.pcm", two },
        .{ "Cool Pack/cool.msu", "" },
        .{ "__MACOSX/Cool Pack/._cool-1.pcm", "junk" },
    });

    try testing.expectEqual(@as(usize, 2), try importPack(alloc, zip_path, msu_dir ++ "/alttp_msu-", null));
    const got1 = try fileio.readWholeFile(alloc, msu_dir ++ "/alttp_msu-1.pcm");
    defer alloc.free(got1);
    try testing.expectEqualStrings(one, got1);
    const got2 = try fileio.readWholeFile(alloc, msu_dir ++ "/alttp_msu-2.pcm");
    defer alloc.free(got2);
    try testing.expectEqualStrings(two, got2);
    // The old pack's ninth track is gone; the file that wasn't a track isn't.
    try testing.expect(!fileio.exists(msu_dir ++ "/alttp_msu-9.pcm"));
    try testing.expect(fileio.exists(msu_dir ++ "/notes.txt"));
}

test "a folder with no tracks in it leaves the installed pack alone" {
    const root = ".zig-cache/msu-import-empty";
    const msu_dir = root ++ "/msu";
    const src = root ++ "/not-a-pack";
    defer {
        for ([_][*:0]const u8{ msu_dir ++ "/alttp_msu-1.pcm", src ++ "/readme.txt", src, msu_dir, root }) |p| _ = c.SDL_RemovePath(p);
    }
    try testing.expect(c.SDL_CreateDirectory(msu_dir));
    try testing.expect(c.SDL_CreateDirectory(src));
    try fileio.writeWholeFile(msu_dir ++ "/alttp_msu-1.pcm", "keep me");
    try fileio.writeWholeFile(src ++ "/readme.txt", "hello");
    try testing.expectError(error.NoTracks, importPack(testing.allocator, src, msu_dir ++ "/alttp_msu-", null));
    try testing.expect(fileio.exists(msu_dir ++ "/alttp_msu-1.pcm"));
}

test "a folder pack is copied in by its track numbers" {
    const root = ".zig-cache/msu-import-folder";
    const msu_dir = root ++ "/msu";
    const src = root ++ "/pack";
    defer {
        for ([_][*:0]const u8{ msu_dir ++ "/alttp_msu-3.opuz", src ++ "/inner/song_03.opuz", src ++ "/inner", src, msu_dir, root }) |p| _ = c.SDL_RemovePath(p);
    }
    try testing.expect(c.SDL_CreateDirectory(src ++ "/inner"));
    try fileio.writeWholeFile(src ++ "/inner/song_03.opuz", "OPUZ three");
    try testing.expectEqual(@as(usize, 1), try importPack(testing.allocator, src, msu_dir ++ "/alttp_msu-", null));
    const got = try fileio.readWholeFile(testing.allocator, msu_dir ++ "/alttp_msu-3.opuz");
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("OPUZ three", got);
}
