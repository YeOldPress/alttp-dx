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
//! Zips are read by zip.zig, which checks every track against its CRC on the
//! way out.

const std = @import("std");
const c = @import("sdl.zig").c;
const fileio = @import("fileio.zig");
const zip = @import("zip.zig");

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

const Track = struct {
    name: TrackName,
    source: union(enum) {
        file: [:0]u8,
        zip: zip.Entry,
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

    var zip_file: ?*anyopaque = null;
    if (is_zip) zip_file = fileio.fopen(source.ptr, "rb") orelse return error.NotFound;
    defer if (zip_file) |f| {
        _ = fileio.fclose(f);
    };

    for (tracks.items, 0..) |t, i| {
        Progress.report(progress, i, tracks.items.len);
        const dest = std.fmt.allocPrintSentinel(arena, "{s}{d}.{s}", .{ msu_path, t.name.number, t.name.ext.name() }, 0) catch return error.OutOfMemory;
        switch (t.source) {
            .file => |path| if (!c.SDL_CopyFile(path.ptr, dest.ptr)) return error.WriteFailed,
            .zip => |e| zip.extract(alloc, zip_file.?, e, dest) catch |err| {
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

// ----------------------------------------------------------------- checking

/// The game plays its own music for any of these a pack leaves out. Seeds
/// from the randomizer use more, from 35 on, one per dungeon.
pub const kGameTracks = 34;

/// A track in a pack, and what would stop the game playing it.
pub const Found = struct {
    name: TrackName,
    /// The file's own name, for saying which one.
    file: []const u8,
    size: u64,
    /// Why the game won't play it, or null when it looks right.
    problem: ?[]const u8 = null,
};

/// Every track in the pack at `source`, a folder or a .zip, by number, with
/// anything that would stop the game playing it. Nothing is copied.
pub fn inspectPack(arena: std.mem.Allocator, source: [:0]const u8) Error![]Found {
    var tracks: std.ArrayList(Track) = .empty;
    const is_zip = !fileio.isDir(source.ptr);
    if (is_zip) try readZip(arena, source, &tracks) else try readFolder(arena, source, &tracks);
    dedupe(&tracks);
    std.mem.sort(Track, tracks.items, {}, struct {
        fn lt(_: void, a: Track, b: Track) bool {
            if (a.name.number != b.name.number) return a.name.number < b.name.number;
            return @backingInt(a.name.ext) < @backingInt(b.name.ext);
        }
    }.lt);

    const zip_file: ?*anyopaque = if (is_zip) fileio.fopen(source.ptr, "rb") orelse return error.NotFound else null;
    defer if (zip_file) |f| {
        _ = fileio.fclose(f);
    };

    const found = arena.alloc(Found, tracks.items.len) catch return error.OutOfMemory;
    for (tracks.items, found) |t, *out| {
        var head: [8]u8 = undefined;
        var have_head = false;
        var size: u64 = 0;
        switch (t.source) {
            .file => |path| {
                var info: c.SDL_PathInfo = undefined;
                if (c.SDL_GetPathInfo(path.ptr, &info)) size = info.size;
                if (fileio.fopen(path.ptr, "rb")) |f| {
                    have_head = fileio.fread(&head, 1, head.len, f) == head.len;
                    _ = fileio.fclose(f);
                }
            },
            .zip => |e| {
                size = e.size;
                have_head = zip.readStart(zip_file.?, e, &head) catch false;
            },
        }
        const file = switch (t.source) {
            .file => |path| basename(path),
            .zip => |e| basename(e.name),
        };
        out.* = .{ .name = t.name, .file = file, .size = size, .problem = trackProblem(t.name.ext, size, if (have_head) head else null) };
    }
    return found;
}

/// What's wrong with a track of `size` bytes starting with `head`, which is
/// null when it couldn't be read without unpacking it.
fn trackProblem(ext: Ext, size: u64, head: ?[8]u8) ?[]const u8 {
    if (size < 8) return "too short to be a track";
    const h = head orelse return null;
    return switch (ext) {
        .pcm => if (std.mem.eql(u8, h[0..4], "MSU1")) null else "doesn't start with MSU1, so it isn't an MSU-1 track",
        .opuz => if (std.mem.eql(u8, h[0..4], "OPUZ")) null else "doesn't start with OPUZ, so it isn't an Opuz track",
    };
}

// --------------------------------------------------------------------- zips

fn readZip(arena: std.mem.Allocator, path: [:0]const u8, tracks: *std.ArrayList(Track)) Error!void {
    const f = fileio.fopen(path.ptr, "rb") orelse return error.NotFound;
    defer _ = fileio.fclose(f);
    for (try zip.readDirectory(arena, f)) |e| {
        if (e.isDir()) continue;
        const t = trackOf(e.name) orelse continue;
        try tracks.append(arena, .{ .name = t, .source = .{ .zip = e } });
    }
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

test "a track's problems are put plainly" {
    try testing.expectEqual(@as(?[]const u8, null), trackProblem(.pcm, 100, "MSU1\x00\x00\x00\x00".*));
    try testing.expectEqual(@as(?[]const u8, null), trackProblem(.opuz, 100, null));
    try testing.expectEqualStrings("too short to be a track", trackProblem(.pcm, 4, null).?);
    try testing.expect(trackProblem(.pcm, 100, "RIFF\x00\x00\x00\x00".*) != null);
    try testing.expect(trackProblem(.opuz, 100, "MSU1\x00\x00\x00\x00".*) != null);
}

test "a pack is inspected without copying anything" {
    const root = ".zig-cache/msu-inspect-test";
    const zip_path = root ++ "/pack.zip";
    defer {
        _ = c.SDL_RemovePath(zip_path);
        _ = c.SDL_RemovePath(root);
    }
    try testing.expect(c.SDL_CreateDirectory(root));
    // The first is stored, so its start can be checked; the rest are
    // deflated, so only their sizes can.
    try zip.writeTestZip(zip_path, &.{
        .{ "Pack/pack-2.pcm", "RIFF not a track" },
        .{ "Pack/pack-1.pcm", "MSU1" ++ comptime repeat("one ", 20) },
        .{ "Pack/pack-3.pcm", "MSU" },
        .{ "Pack/readme.txt", "hello" },
    });
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const found = try inspectPack(arena_state.allocator(), zip_path);
    try testing.expectEqual(@as(usize, 3), found.len);
    try testing.expectEqual(@as(u16, 1), found[0].name.number);
    try testing.expectEqual(@as(?[]const u8, null), found[0].problem);
    try testing.expectEqualStrings("pack-2.pcm", found[1].file);
    try testing.expect(found[1].problem != null);
    try testing.expectEqualStrings("too short to be a track", found[2].problem.?);
}

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
    try zip.writeTestZip(zip_path, &.{
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
