//! Installing an MSU-1 pack from a folder or a .zip.
//!
//! The game plays track n from MSUPath ++ n ++ ".pcm" (or ".flac", ".ogg",
//! or ".opuz"), so a pack is installed by finding its numbered tracks and
//! copying each one to that name. Packs name their tracks after themselves,
//! "pack-12.pcm", and often sit in a folder inside the zip, so tracks are
//! found by the number at the end of the name wherever they are.
//!
//! Each pack gets a folder of its own in msu/, named after it, so several
//! can be installed and MSUPath picks one. A pack already in the folder it's
//! going to (the same pack, imported again) is removed first, so two copies'
//! tracks never mix, but only once the new one has been read and turned out
//! to have tracks in it; only files named the way the game names its tracks
//! are touched.
//!
//! Zips are read by zip.zig, which checks every track against its CRC on the
//! way out.
//!
//! A .pcm track can be stored as FLAC instead, on the way in or afterwards:
//! the same sound in about half the space. The .pcm only goes once the FLAC
//! has been decoded again and matched it sample for sample.

const std = @import("std");
const c = @import("sdl.zig").c;
const fileio = @import("fileio.zig");
const zip = @import("zip.zig");
const flac_enc = @import("flac_enc.zig");
const msu_codec = @import("msu_codec.zig");

pub const Ext = enum {
    pcm,
    flac,
    ogg,
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
    const ext: Ext = for (std.enums.values(Ext)) |e| {
        if (std.ascii.eqlIgnoreCase(ext_text, e.name())) break e;
    } else return null;
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
    /// Stopped partway, as asked.
    Canceled,
    OutOfMemory,
};

pub const ImportOptions = struct {
    /// Store .pcm tracks as FLAC.
    flac: bool = false,
    /// Where it tells how it's going, and is told to stop.
    status: ?*Status = null,
};

pub const Phase = enum(u8) { reading, copying, shrinking, finishing };

/// How an import is going, for another thread to show, and its way of being
/// stopped. `done` and `total` are in bytes of work: a track's size to copy
/// it, and twice that again to turn it into FLAC, which is the slow part.
pub const Status = struct {
    phase: std.atomic.Value(Phase) = .init(.reading),
    /// The track being worked on, counting from 1, and how many there are.
    track: std.atomic.Value(usize) = .init(0),
    tracks: std.atomic.Value(usize) = .init(0),
    done: std.atomic.Value(u64) = .init(0),
    total: std.atomic.Value(u64) = .init(0),
    cancel: std.atomic.Value(bool) = .init(false),

    fn canceled(self: ?*Status) bool {
        const st = self orelse return false;
        return st.cancel.load(.acquire);
    }

    fn set(self: ?*Status, phase: Phase, track: usize) void {
        const st = self orelse return;
        st.track.store(track, .release);
        st.phase.store(phase, .release);
    }

    fn add(self: ?*Status, bytes: u64) void {
        const st = self orelse return;
        _ = st.done.fetchAdd(bytes, .acq_rel);
    }
};

pub const Imported = struct {
    tracks: usize,
    /// How many of them went in as FLAC.
    flac: usize = 0,
};

/// Words for the start menu's status line.
pub fn describe(err: Error) []const u8 {
    return switch (err) {
        error.NotFound => "COULD NOT OPEN THAT",
        error.NoTracks => "NO MSU-1 TRACKS IN THAT",
        error.BadZip => "COULD NOT READ THAT ZIP",
        error.Corrupt => "A TRACK IN THE ZIP IS DAMAGED",
        error.WriteFailed => "COULD NOT WRITE THE TRACKS",
        error.Canceled => "IMPORT CANCELED",
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
/// `msu_path` names.
pub fn importPack(alloc: std.mem.Allocator, source: [:0]const u8, msu_path: []const u8, progress: ?Progress, opts: ImportOptions) Error!Imported {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const status = opts.status;
    Status.set(status, .reading, 0);

    var tracks: std.ArrayList(Track) = .empty;
    const is_zip = !fileio.isDir(source.ptr);
    if (is_zip) {
        try readZip(arena, source, &tracks);
    } else {
        try readFolder(arena, source, &tracks);
    }
    dedupe(&tracks);
    if (tracks.items.len == 0) return error.NoTracks;

    // How much work there is, so the bar moves by it rather than by track:
    // the tracks run from a few seconds to several minutes.
    const sizes = arena.alloc(u64, tracks.items.len) catch return error.OutOfMemory;
    var total: u64 = 0;
    for (tracks.items, sizes) |t, *size| {
        size.* = switch (t.source) {
            .file => |path| fileSize(path),
            .zip => |e| e.size,
        };
        total += size.* * @as(u64, if (opts.flac and t.name.ext == .pcm) 3 else 1);
    }
    if (status) |st| {
        st.tracks.store(tracks.items.len, .release);
        st.total.store(total, .release);
    }

    const split = splitMsuPath(msu_path);
    const dir_z = arena.dupeSentinel(u8, split.dir, 0) catch return error.OutOfMemory;
    if (!c.SDL_CreateDirectory(dir_z.ptr)) return error.WriteFailed;
    removeOldPack(arena, dir_z, split.prefix);

    var zip_file: ?*anyopaque = null;
    if (is_zip) zip_file = fileio.fopen(source.ptr, "rb") orelse return error.NotFound;
    defer if (zip_file) |f| {
        _ = fileio.fclose(f);
    };

    var flac: usize = 0;
    for (tracks.items, sizes, 0..) |t, size, i| {
        if (Status.canceled(status)) return error.Canceled;
        Progress.report(progress, i, tracks.items.len);
        Status.set(status, .copying, i + 1);
        const dest = std.fmt.allocPrintSentinel(arena, "{s}{d}.{s}", .{ msu_path, t.name.number, t.name.ext.name() }, 0) catch return error.OutOfMemory;
        switch (t.source) {
            .file => |path| if (!c.SDL_CopyFile(path.ptr, dest.ptr)) return error.WriteFailed,
            .zip => |e| zip.extract(alloc, zip_file.?, e, dest) catch |err| {
                _ = fileio.remove(dest.ptr);
                return err;
            },
        }
        Status.add(status, size);
        if (opts.flac and t.name.ext == .pcm) {
            if (Status.canceled(status)) return error.Canceled;
            Status.set(status, .shrinking, i + 1);
            const flac_dest = std.fmt.allocPrintSentinel(arena, "{s}{d}.flac", .{ msu_path, t.name.number }, 0) catch return error.OutOfMemory;
            // One that won't convert stays the .pcm it came as.
            if (pcmToFlac(alloc, dest, flac_dest)) |_| {
                flac += 1;
            } else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
            Status.add(status, size * 2);
        }
    }
    Progress.report(progress, tracks.items.len, tracks.items.len);
    Status.set(status, .finishing, tracks.items.len);
    return .{ .tracks = tracks.items.len, .flac = flac };
}

/// Installs the pack at `source` in the library as a pack called `name`,
/// and returns its MSUPath (`alloc`'s). It goes into a hidden folder first
/// and only takes the place of a pack already called that once it's all
/// in, so stopping it or a full disk leaves that pack as it was.
pub fn importNamed(alloc: std.mem.Allocator, source: [:0]const u8, library: []const u8, name: []const u8, opts: ImportOptions) Error!struct { imported: Imported, msu_path: []u8 } {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var name_buf: [64]u8 = undefined;
    const clean = cleanName(&name_buf, name);
    const final_dir = std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ library, clean }, 0) catch return error.OutOfMemory;
    const temp_dir = std.fmt.allocPrintSentinel(arena, "{s}/.importing-{s}", .{ library, clean }, 0) catch return error.OutOfMemory;
    const temp_path = std.fmt.allocPrint(arena, "{s}/{s}", .{ temp_dir, kTrackPrefix }) catch return error.OutOfMemory;

    // Whatever an import that never finished left behind.
    clearDir(arena, temp_dir);
    const got = importPack(alloc, source, temp_path, null, opts) catch |err| {
        clearDir(arena, temp_dir);
        return err;
    };

    // In it goes: the old pack's tracks out, the new one's in beside
    // anything else the folder holds.
    if (!c.SDL_CreateDirectory(final_dir.ptr)) {
        clearDir(arena, temp_dir);
        return error.WriteFailed;
    }
    removeOldPack(arena, final_dir, kTrackPrefix);
    var entries: std.ArrayList(Entry) = .empty;
    var ctx = EntryCtx{ .arena = arena, .entries = &entries };
    _ = c.SDL_EnumerateDirectory(temp_dir.ptr, entryCallback, &ctx);
    for (entries.items) |e| {
        if (e.dir) continue;
        const from = std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ temp_dir, e.name }, 0) catch return error.OutOfMemory;
        const to = std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ final_dir, e.name }, 0) catch return error.OutOfMemory;
        if (!c.SDL_RenamePath(from.ptr, to.ptr)) {
            clearDir(arena, temp_dir);
            return error.WriteFailed;
        }
    }
    _ = c.SDL_RemovePath(temp_dir.ptr);
    const msu_path = std.fmt.allocPrint(alloc, "{s}/{s}", .{ final_dir, kTrackPrefix }) catch return error.OutOfMemory;
    return .{ .imported = got, .msu_path = msu_path };
}

/// Empties the folder at `dir` (files only, which is all an import puts in
/// one) and removes it.
fn clearDir(arena: std.mem.Allocator, dir: [:0]const u8) void {
    var entries: std.ArrayList(Entry) = .empty;
    var ctx = EntryCtx{ .arena = arena, .entries = &entries, .hidden = true };
    if (c.SDL_EnumerateDirectory(dir.ptr, entryCallback, &ctx)) {
        for (entries.items) |e| {
            const path = std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ dir, e.name }, 0) catch continue;
            _ = c.SDL_RemovePath(path.ptr);
        }
    }
    _ = c.SDL_RemovePath(dir.ptr);
}

// ------------------------------------------------------------------- FLAC

pub const FlacError = error{
    /// It isn't an MSU-1 .pcm track, or it has no sound in it.
    NotPcm,
    ReadFailed,
    WriteFailed,
    /// The FLAC didn't decode back to what went in. It's thrown away and the
    /// .pcm kept.
    Mismatch,
    OutOfMemory,
};

/// Turns the .pcm track at `pcm_path` into a FLAC one at `flac_path`, with its
/// loop point as a LOOPSTART tag, and removes the .pcm once the FLAC has been
/// decoded again and matched it sample for sample. Anything short of that
/// leaves the .pcm where it was.
pub fn pcmToFlac(alloc: std.mem.Allocator, pcm_path: [:0]const u8, flac_path: [:0]const u8) FlacError!void {
    const bytes = fileio.readWholeFile(alloc, pcm_path.ptr) catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else error.ReadFailed;
    defer alloc.free(bytes);
    if (bytes.len < 8 + 4 or !std.mem.eql(u8, bytes[0..4], "MSU1")) return error.NotPcm;
    const loop = std.mem.readInt(u32, bytes[4..8], .little);
    const samples = std.mem.bytesAsSlice(i16, bytes[8..][0 .. (bytes.len - 8) / 4 * 4]);

    const encoded = flac_enc.encode(alloc, samples, .{ .loop_start = if (loop != 0) loop else null }) catch return error.OutOfMemory;
    defer alloc.free(encoded);

    var part_buf: [1100]u8 = undefined;
    const part = std.fmt.bufPrintSentinel(&part_buf, "{s}.part", .{flac_path}, 0) catch return error.WriteFailed;
    fileio.writeWholeFile(part.ptr, encoded) catch {
        _ = fileio.remove(part.ptr);
        return error.WriteFailed;
    };
    errdefer _ = fileio.remove(part.ptr);
    const frames = samples.len / 2;
    try sameAs(part, samples, if (loop < frames) loop else 0);
    _ = fileio.remove(flac_path.ptr);
    if (fileio.rename(part.ptr, flac_path.ptr) != 0) return error.WriteFailed;
    _ = fileio.remove(pcm_path.ptr);
}

/// Whether the FLAC at `path` plays back as exactly `samples`, looping at
/// `loop`.
fn sameAs(path: [:0]const u8, samples: []align(1) const i16, loop: u64) FlacError!void {
    const t = msu_codec.Track.open(path.ptr, .flac) orelse return error.Mismatch;
    defer t.close();
    const frames = samples.len / 2;
    if (t.frames != frames or t.rate != 44100 or t.channels != 2 or t.loop_start != loop) return error.Mismatch;
    var buf: [4096][2]i16 = undefined;
    var at: usize = 0;
    while (at < frames) {
        const want: usize = @min(buf.len, frames - at);
        if (t.read(buf[0..want]) != want) return error.Mismatch;
        for (buf[0..want], 0..) |f, i| {
            if (f[0] != samples[(at + i) * 2] or f[1] != samples[(at + i) * 2 + 1]) return error.Mismatch;
        }
        at += want;
    }
}

pub const Shrunk = struct {
    /// Tracks now FLAC.
    tracks: usize = 0,
    /// Tracks left as .pcm because they wouldn't convert.
    kept: usize = 0,
    /// The converted tracks' size before and after.
    before: u64 = 0,
    after: u64 = 0,
};

/// Turns every .pcm track of the packs installed at `msu_paths` (MSUPath
/// values) into FLAC.
pub fn shrinkInstalled(alloc: std.mem.Allocator, msu_paths: []const []const u8, progress: ?Progress) Error!Shrunk {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const Pcm = struct { path: [:0]u8, flac: [:0]u8, number: u16 };
    var pcms: std.ArrayList(Pcm) = .empty;
    var found_any = false;
    for (msu_paths) |msu_path| {
        const split = splitMsuPath(msu_path);
        const dir_z = arena.dupeSentinel(u8, split.dir, 0) catch return error.OutOfMemory;
        var paths: std.ArrayList([:0]u8) = .empty;
        var ctx = ListCtx{ .arena = arena, .paths = &paths, .depth = 3 };
        if (!c.SDL_EnumerateDirectory(dir_z.ptr, listCallback, &ctx)) continue;
        if (ctx.failed) return error.OutOfMemory;
        found_any = true;
        const first = pcms.items.len;
        for (paths.items) |path| {
            if (!isInstalledTrack(basename(path), split.prefix)) continue;
            const t = trackOf(path).?;
            if (t.ext != .pcm) continue;
            const flac = std.fmt.allocPrintSentinel(arena, "{s}{d}.flac", .{ msu_path, t.number }, 0) catch return error.OutOfMemory;
            pcms.append(arena, .{ .path = path, .flac = flac, .number = t.number }) catch return error.OutOfMemory;
        }
        std.mem.sort(Pcm, pcms.items[first..], {}, struct {
            fn lt(_: void, a: Pcm, b: Pcm) bool {
                return a.number < b.number;
            }
        }.lt);
    }
    if (!found_any) return error.NotFound;
    if (pcms.items.len == 0) return error.NoTracks;

    var out = Shrunk{};
    for (pcms.items, 0..) |p, i| {
        Progress.report(progress, i, pcms.items.len);
        const before = fileSize(p.path);
        pcmToFlac(alloc, p.path, p.flac) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            out.kept += 1;
            continue;
        };
        out.tracks += 1;
        out.before += before;
        out.after += fileSize(p.flac);
    }
    Progress.report(progress, pcms.items.len, pcms.items.len);
    return out;
}

// ------------------------------------------------------------------- packs

/// Where imported packs go, each in a folder of its own, beside the ini.
pub const kLibrary = "msu";
/// What tracks are called inside a pack's folder: "alttp_msu-12.pcm".
pub const kTrackPrefix = "alttp_msu-";

/// An installed pack.
pub const Pack = struct {
    /// What to call it: its folder's name.
    name: []const u8,
    /// Its MSUPath: where its tracks are and how their names begin.
    path: []const u8,
    tracks: usize = 0,
    /// How many of them are still .pcm.
    pcm: usize = 0,
    /// How many are of each kind, by Ext.
    kinds: [std.enums.values(Ext).len]usize = @splat(0),
    /// The tracks' size together.
    bytes: u64 = 0,
    /// Whether it's the tracks loose in the library, the way packs were
    /// installed before they had folders.
    loose: bool = false,
};

/// Every pack in `library`: one in each folder in it, and the tracks
/// sitting loose in it, the way packs were installed before there could be
/// more than one. By name, with the loose ones first.
pub fn listPacks(arena: std.mem.Allocator, library: []const u8) Error![]Pack {
    var packs: std.ArrayList(Pack) = .empty;
    const lib_z = arena.dupeSentinel(u8, library, 0) catch return error.OutOfMemory;
    var entries: std.ArrayList(Entry) = .empty;
    var ctx = EntryCtx{ .arena = arena, .entries = &entries };
    if (!c.SDL_EnumerateDirectory(lib_z.ptr, entryCallback, &ctx)) return packs.items;
    if (ctx.failed) return error.OutOfMemory;
    sortEntries(entries.items);

    if (try bestGroup(arena, entries.items)) |g| {
        var pack = g;
        pack.name = looseName(g.path);
        pack.path = std.fmt.allocPrint(arena, "{s}/{s}", .{ library, g.path }) catch return error.OutOfMemory;
        pack.loose = true;
        try packs.append(arena, pack);
    }

    for (entries.items) |e| {
        if (!e.dir) continue;
        const dir_z = std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ library, e.name }, 0) catch return error.OutOfMemory;
        var inner: std.ArrayList(Entry) = .empty;
        var inner_ctx = EntryCtx{ .arena = arena, .entries = &inner };
        if (!c.SDL_EnumerateDirectory(dir_z.ptr, entryCallback, &inner_ctx)) continue;
        if (inner_ctx.failed) return error.OutOfMemory;
        var pack = try bestGroup(arena, inner.items) orelse continue;
        pack.name = e.name;
        pack.path = std.fmt.allocPrint(arena, "{s}/{s}", .{ dir_z, pack.path }) catch return error.OutOfMemory;
        try packs.append(arena, pack);
    }
    return packs.items;
}

/// The loose tracks' name in the list. They're whatever was imported before
/// packs got folders of their own (and are moved into one at startup).
fn looseName(prefix: []const u8) []const u8 {
    if (std.mem.eql(u8, prefix, kTrackPrefix)) return kLooseFolder;
    const trimmed = std.mem.trimEnd(u8, prefix, "-_ .");
    return if (trimmed.len == 0) kLooseFolder else trimmed;
}

/// What the start menu shows for an MSUPath: its pack's name.
pub fn packLabel(msu_path: []const u8) []const u8 {
    const split = splitMsuPath(msu_path);
    if (std.mem.eql(u8, split.dir, kLibrary) or std.mem.eql(u8, split.dir, "./" ++ kLibrary)) return looseName(split.prefix);
    const parent = splitMsuPath(split.dir);
    if (std.mem.eql(u8, parent.dir, kLibrary) or std.mem.eql(u8, parent.dir, "./" ++ kLibrary)) return parent.prefix;
    return msu_path;
}

/// A pack's folder or zip's name, as a folder name any system takes: what
/// the start menu offers to call it.
pub fn packName(buf: *[64]u8, source: []const u8) []const u8 {
    var base = basename(std.mem.trimEnd(u8, source, "/\\"));
    if (std.ascii.endsWithIgnoreCase(base, ".zip")) base = base[0 .. base.len - 4];
    return cleanName(buf, base);
}

/// Whether a pack is already installed as `name`, which importing one
/// called that would replace.
pub fn packExists(name: []const u8) bool {
    var name_buf: [64]u8 = undefined;
    var path_buf: [128]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&path_buf, "{s}/{s}", .{ kLibrary, cleanName(&name_buf, name) }, 0) catch return false;
    return fileio.isDir(path.ptr);
}

/// `name` as a folder name any system takes: no slashes or the characters
/// Windows refuses, no dot first (that would hide it) or last.
pub fn cleanName(buf: *[64]u8, name: []const u8) []const u8 {
    var n: usize = 0;
    for (name) |ch| {
        if (n == buf.len) break;
        buf[n] = if (ch < 0x20 or std.mem.indexOfScalar(u8, "<>:\"/\\|?*", ch) != null) '_' else ch;
        n += 1;
    }
    // Cut short in the middle of a character: drop what's left of it.
    if (n == buf.len and n < name.len and name[n] & 0xc0 == 0x80) {
        while (n > 0 and buf[n - 1] & 0xc0 == 0x80) n -= 1;
        if (n > 0 and buf[n - 1] >= 0xc0) n -= 1;
    }
    // Windows won't have a folder end in a dot or a space.
    const clean = std.mem.trim(u8, buf[0..n], " .");
    return if (clean.len == 0) "Pack" else clean;
}

/// The biggest set of tracks among a folder's `entries` that share a
/// prefix: a pack's tracks, as opposed to a readme or a stray copy. Its
/// `path` is that prefix, and its name is left for the caller.
fn bestGroup(arena: std.mem.Allocator, entries: []const Entry) Error!?Pack {
    var groups: std.ArrayList(Pack) = .empty;
    for (entries) |e| {
        if (e.dir) continue;
        const t = trackOf(e.name) orelse continue;
        const prefix = prefixOf(e.name) orelse continue;
        const g = for (groups.items) |*g| {
            if (std.mem.eql(u8, g.path, prefix)) break g;
        } else blk: {
            groups.append(arena, .{ .name = "", .path = prefix }) catch return error.OutOfMemory;
            break :blk &groups.items[groups.items.len - 1];
        };
        g.tracks += 1;
        g.kinds[@backingInt(t.ext)] += 1;
        g.bytes += e.size;
        if (t.ext == .pcm) g.pcm += 1;
    }
    var best: ?Pack = null;
    for (groups.items) |g| {
        if (best == null or g.tracks > best.?.tracks) best = g;
    }
    return best;
}

/// What kind of tracks a pack has, for the tools' list: "FLAC", or "FLAC
/// and PCM".
pub fn kindsLabel(buf: []u8, p: Pack) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    var left: usize = 0;
    for (p.kinds) |n| left += @intFromBool(n != 0);
    for (p.kinds, 0..) |n, i| {
        if (n == 0) continue;
        left -= 1;
        const name = switch (@as(Ext, @fromBackingInt(@intCast(i)))) {
            .pcm => "PCM",
            .flac => "FLAC",
            .ogg => "Ogg",
            .opuz => "Opuz",
        };
        w.print("{s}{s}", .{ name, if (left > 1) ", " else if (left == 1) " and " else "" }) catch {};
    }
    return w.buffered();
}

// --------------------------------------------------------- tidying, deleting

/// The folder the tracks loose in the library move to.
pub const kLooseFolder = "Earlier import";

/// Packs used to be installed loose in the library. This moves such a pack
/// into a folder of its own, so it sits in the list like any other, and
/// says where it was and where it is now (both `alloc`'s), so MSUPath can
/// follow. Null when there was nothing to move, or it couldn't be moved, in
/// which case it's left loose and still plays.
/// Where a moved pack was, and where it is now, as MSUPaths.
pub const Moved = struct { from: []u8, to: []u8 };

pub fn moveLoosePack(alloc: std.mem.Allocator, library: []const u8) ?Moved {
    return moveLooseTo(alloc, library, null);
}

/// The same, into a folder called `name` (which mustn't be there yet), or
/// the first free "Earlier import" when that's null.
fn moveLooseTo(alloc: std.mem.Allocator, library: []const u8, name: ?[]const u8) ?Moved {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib_z = arena.dupeSentinel(u8, library, 0) catch return null;
    var entries: std.ArrayList(Entry) = .empty;
    var ctx = EntryCtx{ .arena = arena, .entries = &entries };
    if (!c.SDL_EnumerateDirectory(lib_z.ptr, entryCallback, &ctx) or ctx.failed) return null;
    const g = (bestGroup(arena, entries.items) catch return null) orelse return null;

    // A folder of its own, not one that's already somebody's.
    var dir: [:0]u8 = undefined;
    var n: usize = 1;
    if (name) |want| {
        dir = std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ library, want }, 0) catch return null;
        if (fileio.isDir(dir.ptr) or fileio.exists(dir.ptr)) return null;
    } else while (true) : (n += 1) {
        dir = (if (n == 1)
            std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ library, kLooseFolder }, 0)
        else
            std.fmt.allocPrintSentinel(arena, "{s}/{s} {d}", .{ library, kLooseFolder, n }, 0)) catch return null;
        if (!fileio.isDir(dir.ptr) and !fileio.exists(dir.ptr)) break;
        if (n > 50) return null;
    }
    if (!c.SDL_CreateDirectory(dir.ptr)) return null;

    var moved: std.ArrayList(struct { from: [:0]u8, to: [:0]u8 }) = .empty;
    for (entries.items) |e| {
        if (e.dir) continue;
        const t = trackOf(e.name) orelse continue;
        const prefix = prefixOf(e.name) orelse continue;
        if (!std.mem.eql(u8, prefix, g.path)) continue;
        const from = std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ library, e.name }, 0) catch return null;
        const to = std.fmt.allocPrintSentinel(arena, "{s}/{s}{d}.{s}", .{ dir, kTrackPrefix, t.number, t.ext.name() }, 0) catch return null;
        if (!c.SDL_RenamePath(from.ptr, to.ptr)) {
            // Put back what went, so the pack isn't left in two halves.
            for (moved.items) |m| _ = c.SDL_RenamePath(m.to.ptr, m.from.ptr);
            _ = c.SDL_RemovePath(dir.ptr);
            return null;
        }
        moved.append(arena, .{ .from = from, .to = to }) catch {};
    }
    const from_path = std.fmt.allocPrint(alloc, "{s}/{s}", .{ library, g.path }) catch return null;
    const to_path = std.fmt.allocPrint(alloc, "{s}/{s}", .{ dir, kTrackPrefix }) catch {
        alloc.free(from_path);
        return null;
    };
    return .{ .from = from_path, .to = to_path };
}

pub const RenameError = error{
    /// Another pack already has that name.
    NameTaken,
    /// Moving its folder didn't work: the disk, or something holding a
    /// file in it open.
    WriteFailed,
    OutOfMemory,
};

/// Renames the pack at `msu_path` (its folder in the library) to `name`,
/// and returns its new MSUPath (`alloc`'s). Tracks still loose in the
/// library get a folder of that name instead.
pub fn renamePack(alloc: std.mem.Allocator, library: []const u8, msu_path: []const u8, name: []const u8) RenameError![]u8 {
    var name_buf: [64]u8 = undefined;
    const clean = cleanName(&name_buf, name);
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const split = splitMsuPath(msu_path);
    const parent = splitMsuPath(split.dir);
    const to = std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ library, clean }, 0) catch return error.OutOfMemory;

    if (!std.mem.eql(u8, parent.dir, library)) {
        // Loose: into a folder of that name.
        if (fileio.isDir(to.ptr) or fileio.exists(to.ptr)) return error.NameTaken;
        const moved = moveLooseTo(alloc, library, clean) orelse return error.WriteFailed;
        alloc.free(moved.from);
        return moved.to;
    }

    const old = parent.prefix;
    if (std.mem.eql(u8, old, clean)) return alloc.dupe(u8, msu_path) catch error.OutOfMemory;
    const from = arena.dupeSentinel(u8, split.dir, 0) catch return error.OutOfMemory;
    if (std.ascii.eqlIgnoreCase(old, clean)) {
        // Only the capitals change. A Mac or Windows disk sees that as the
        // same name, so it goes by way of another.
        const step = std.fmt.allocPrintSentinel(arena, "{s}/.renaming-{s}", .{ library, clean }, 0) catch return error.OutOfMemory;
        if (!c.SDL_RenamePath(from.ptr, step.ptr)) return error.WriteFailed;
        if (!c.SDL_RenamePath(step.ptr, to.ptr)) {
            _ = c.SDL_RenamePath(step.ptr, from.ptr);
            return error.WriteFailed;
        }
    } else {
        if (fileio.isDir(to.ptr) or fileio.exists(to.ptr)) return error.NameTaken;
        if (!c.SDL_RenamePath(from.ptr, to.ptr)) return error.WriteFailed;
    }
    return std.fmt.allocPrint(alloc, "{s}/{s}", .{ to, split.prefix }) catch error.OutOfMemory;
}

/// Whether renaming the pack called `old` to `name` would take another
/// pack's name. The same name in other capitals is its own.
pub fn nameTaken(library: []const u8, old: []const u8, name: []const u8) bool {
    var name_buf: [64]u8 = undefined;
    const clean = cleanName(&name_buf, name);
    if (std.ascii.eqlIgnoreCase(old, clean)) return false;
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&path_buf, "{s}/{s}", .{ library, clean }, 0) catch return true;
    return fileio.isDir(path.ptr) or fileio.exists(path.ptr);
}

/// Deletes the pack at `msu_path`: its whole folder when it has one of its
/// own in the library, or only its tracks when they're loose. False when
/// something of it couldn't go.
pub fn deletePack(alloc: std.mem.Allocator, library: []const u8, msu_path: []const u8) bool {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const split = splitMsuPath(msu_path);
    const dir_z = arena.dupeSentinel(u8, split.dir, 0) catch return false;
    const own_folder = std.mem.eql(u8, splitMsuPath(split.dir).dir, library);
    if (own_folder) {
        clearDir(arena, dir_z);
        return !fileio.isDir(dir_z.ptr);
    }
    removeOldPack(arena, dir_z, split.prefix);
    return installedPcm(alloc, msu_path) == 0;
}

/// A track's name less its number and extension: "alttp_msu-" from
/// "alttp_msu-12.pcm".
fn prefixOf(name: []const u8) ?[]const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return null;
    var i = dot;
    while (i > 0 and std.ascii.isDigit(name[i - 1])) i -= 1;
    if (i == dot) return null;
    return name[0..i];
}

const Entry = struct { name: []const u8, dir: bool, size: u64 = 0 };

const EntryCtx = struct {
    arena: std.mem.Allocator,
    entries: *std.ArrayList(Entry),
    failed: bool = false,
    /// Dot files too, for emptying a folder (a Mac leaves .DS_Store about).
    hidden: bool = false,
};

/// One folder's files and folders, not what's in them.
fn entryCallback(userdata: ?*anyopaque, dirname: [*c]const u8, fname: [*c]const u8) callconv(.c) c.SDL_EnumerationResult {
    const ctx: *EntryCtx = @ptrCast(@alignCast(userdata));
    const name = std.mem.span(fname);
    if (name.len == 0 or (name[0] == '.' and !ctx.hidden)) return c.SDL_ENUM_CONTINUE;
    const full = std.fmt.allocPrintSentinel(ctx.arena, "{s}{s}", .{ std.mem.span(dirname), name }, 0) catch {
        ctx.failed = true;
        return c.SDL_ENUM_FAILURE;
    };
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(full.ptr, &info)) return c.SDL_ENUM_CONTINUE;
    const dir = info.type == c.SDL_PATHTYPE_DIRECTORY;
    if (!dir and info.type != c.SDL_PATHTYPE_FILE) return c.SDL_ENUM_CONTINUE;
    const copy = ctx.arena.dupe(u8, name) catch {
        ctx.failed = true;
        return c.SDL_ENUM_FAILURE;
    };
    ctx.entries.append(ctx.arena, .{ .name = copy, .dir = dir, .size = if (dir) 0 else info.size }) catch {
        ctx.failed = true;
        return c.SDL_ENUM_FAILURE;
    };
    return c.SDL_ENUM_CONTINUE;
}

fn sortEntries(entries: []Entry) void {
    std.mem.sort(Entry, entries, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
    }.lt);
}

/// How many of the tracks at `msu_path` are still .pcm.
pub fn installedPcm(alloc: std.mem.Allocator, msu_path: []const u8) usize {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const split = splitMsuPath(msu_path);
    const dir_z = arena.dupeSentinel(u8, split.dir, 0) catch return 0;
    var paths: std.ArrayList([:0]u8) = .empty;
    var ctx = ListCtx{ .arena = arena, .paths = &paths, .depth = 3 };
    if (!c.SDL_EnumerateDirectory(dir_z.ptr, listCallback, &ctx)) return 0;
    var n: usize = 0;
    for (paths.items) |path| {
        if (isInstalledTrack(basename(path), split.prefix) and trackOf(path).?.ext == .pcm) n += 1;
    }
    return n;
}

fn fileSize(path: [:0]const u8) u64 {
    var info: c.SDL_PathInfo = undefined;
    return if (c.SDL_GetPathInfo(path.ptr, &info)) info.size else 0;
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

/// The folder an MSUPath's tracks are in.
pub fn splitPath(msu_path: []const u8) []const u8 {
    return splitMsuPath(msu_path).dir;
}

/// MSUPath as a folder and the start of each track's name in it:
/// "msu/alttp_msu-" is "msu" and "alttp_msu-".
fn splitMsuPath(msu_path: []const u8) struct { dir: []const u8, prefix: []const u8 } {
    const cut = std.mem.lastIndexOfAny(u8, msu_path, "/\\") orelse return .{ .dir = ".", .prefix = msu_path };
    return .{ .dir = if (cut == 0) "/" else msu_path[0..cut], .prefix = msu_path[cut + 1 ..] };
}

/// Whether `name` is one of the game's own tracks: the prefix, a number, and
/// a track's extension, nothing else.
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

/// How many of the tracks in the pack at `source` are .pcm, the ones FLAC
/// would make smaller. Reads only the folder or the zip's directory.
pub fn pcmTracksIn(alloc: std.mem.Allocator, source: [:0]const u8) usize {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tracks: std.ArrayList(Track) = .empty;
    if (fileio.isDir(source.ptr)) {
        readFolder(arena, source, &tracks) catch return 0;
    } else {
        readZip(arena, source, &tracks) catch return 0;
    }
    dedupe(&tracks);
    var n: usize = 0;
    for (tracks.items) |t| n += @intFromBool(t.name.ext == .pcm);
    return n;
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
        // Enough to reach an Ogg file's sample rate, past its page header.
        var head: [64]u8 = undefined;
        var head_len: usize = 0;
        var size: u64 = 0;
        switch (t.source) {
            .file => |path| {
                var info: c.SDL_PathInfo = undefined;
                if (c.SDL_GetPathInfo(path.ptr, &info)) size = info.size;
                if (fileio.fopen(path.ptr, "rb")) |f| {
                    head_len = fileio.fread(&head, 1, head.len, f);
                    _ = fileio.fclose(f);
                }
            },
            .zip => |e| {
                size = e.size;
                const want: usize = @intCast(@min(size, head.len));
                if (zip.readStart(zip_file.?, e, head[0..want]) catch false) head_len = want;
            },
        }
        const file = switch (t.source) {
            .file => |path| basename(path),
            .zip => |e| basename(e.name),
        };
        out.* = .{ .name = t.name, .file = file, .size = size, .problem = trackProblem(t.name.ext, size, if (head_len >= 8) head[0..head_len] else null) };
    }
    return found;
}

/// What's wrong with a track of `size` bytes starting with `head` (at least
/// 8 bytes of it), which is null when it couldn't be read without unpacking
/// it.
fn trackProblem(ext: Ext, size: u64, head: ?[]const u8) ?[]const u8 {
    if (size < 8) return "too short to be a track";
    const h = head orelse return null;
    switch (ext) {
        .pcm => return if (std.mem.eql(u8, h[0..4], "MSU1")) null else "doesn't start with MSU1, so it isn't an MSU-1 track",
        .opuz => return if (std.mem.eql(u8, h[0..4], "OPUZ")) null else "doesn't start with OPUZ, so it isn't an Opuz track",
        .flac => {
            if (!std.mem.eql(u8, h[0..4], "fLaC")) return "isn't really a FLAC file";
            // STREAMINFO comes first: 20 bits of rate, 3 of channels - 1.
            if (h.len < 21) return null;
            const rate = @as(u32, h[18]) << 12 | @as(u32, h[19]) << 4 | h[20] >> 4;
            const channels = ((h[20] >> 1) & 7) + 1;
            if (channels > 2) return "has more than two channels; tracks are mono or stereo";
            return rateProblem(rate);
        },
        .ogg => {
            if (!std.mem.eql(u8, h[0..4], "OggS")) return "isn't really an Ogg file";
            // The first page's first packet: 1, "vorbis", a version, the
            // channels and the rate.
            if (h.len < 27) return null;
            const p = 27 + @as(usize, h[26]);
            if (h.len < p + 16) return null;
            if (h[p] != 1 or !std.mem.eql(u8, h[p + 1 .. p + 7], "vorbis")) return "isn't Ogg Vorbis (Opus and others won't play)";
            return rateProblem(std.mem.readInt(u32, h[p + 12 ..][0..4], .little));
        },
    }
}

/// The normal game mixes tracks at 44.1kHz with no resampling of its own.
fn rateProblem(rate: u32) ?[]const u8 {
    if (rate == 44100) return null;
    return switch (rate) {
        48000 => "is 48000 Hz; tracks need to be 44100 Hz, the same as a .pcm",
        else => "isn't 44100 Hz; tracks need to be 44100 Hz, the same as a .pcm",
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
    try testing.expectEqual(@as(?[]const u8, null), trackProblem(.pcm, 100, "MSU1\x00\x00\x00\x00"));
    try testing.expectEqual(@as(?[]const u8, null), trackProblem(.opuz, 100, null));
    try testing.expectEqualStrings("too short to be a track", trackProblem(.pcm, 4, null).?);
    try testing.expect(trackProblem(.pcm, 100, "RIFF\x00\x00\x00\x00") != null);
    try testing.expect(trackProblem(.opuz, 100, "MSU1\x00\x00\x00\x00") != null);
    try testing.expect(trackProblem(.flac, 100, "OggS\x00\x00\x00\x00") != null);
}

test "a FLAC or Ogg track at the wrong rate is caught from its header" {
    // fLaC, a STREAMINFO header, then block sizes, frame sizes, and the
    // packed rate/channels/bits.
    var flac: [42]u8 = @splat(0);
    @memcpy(flac[0..4], "fLaC");
    const at = 18;
    const stereo_16 = (1 << 1) | 0; // channels - 1 = 1, top bit of bits - 1
    flac[at] = 44100 >> 12;
    flac[at + 1] = (44100 >> 4) & 0xff;
    flac[at + 2] = ((44100 & 0xf) << 4) | stereo_16;
    try testing.expectEqual(@as(?[]const u8, null), trackProblem(.flac, 1000, &flac));
    flac[at] = 48000 >> 12;
    flac[at + 1] = (48000 >> 4) & 0xff;
    flac[at + 2] = ((48000 & 0xf) << 4) | stereo_16;
    try testing.expect(trackProblem(.flac, 1000, &flac) != null);

    // OggS page with one segment, then the Vorbis identification packet.
    var ogg: [64]u8 = @splat(0);
    @memcpy(ogg[0..4], "OggS");
    ogg[26] = 1;
    ogg[28] = 1;
    @memcpy(ogg[29..35], "vorbis");
    ogg[39] = 2;
    std.mem.writeInt(u32, ogg[40..44], 44100, .little);
    try testing.expectEqual(@as(?[]const u8, null), trackProblem(.ogg, 1000, &ogg));
    std.mem.writeInt(u32, ogg[40..44], 22050, .little);
    try testing.expect(trackProblem(.ogg, 1000, &ogg) != null);
}

test "a .pcm track becomes a FLAC that plays back the same, loop point and all" {
    const root = ".zig-cache/msu-flac-test";
    const pcm = root ++ "/alttp_msu-5.pcm";
    const flac = root ++ "/alttp_msu-5.flac";
    defer for ([_][*:0]const u8{ pcm, flac, flac ++ ".part", root }) |p| {
        _ = c.SDL_RemovePath(p);
    };
    try testing.expect(c.SDL_CreateDirectory(root));

    // Music-ish: two tones, a little noise, a silent patch, and a block
    // that isn't whole, so constant, LPC and the odd-sized last frame all
    // get used.
    const frames = 4096 * 3 + 1000;
    const bytes = try testing.allocator.alloc(u8, 8 + frames * 4);
    defer testing.allocator.free(bytes);
    @memcpy(bytes[0..4], "MSU1");
    std.mem.writeInt(u32, bytes[4..8], 777, .little);
    var rng = std.Random.DefaultPrng.init(3);
    for (0..frames) |i| {
        const t: f64 = @floatFromInt(i);
        const quiet = i >= 4096 and i < 8192;
        const l: i16 = if (quiet) 0 else @intFromFloat(9000 * @sin(t * 0.031) + 3000 * @sin(t * 0.17) + @as(f64, @floatFromInt(rng.random().intRangeAtMost(i16, -40, 40))));
        const r: i16 = if (quiet) 0 else @intFromFloat(8000 * @sin(t * 0.029 + 1) + 2500 * @sin(t * 0.21));
        std.mem.writeInt(i16, bytes[8 + i * 4 ..][0..2], l, .little);
        std.mem.writeInt(i16, bytes[8 + i * 4 + 2 ..][0..2], r, .little);
    }
    try fileio.writeWholeFile(pcm, bytes);

    try pcmToFlac(testing.allocator, pcm, flac);
    try testing.expect(!fileio.exists(pcm));
    try testing.expect(!fileio.exists(flac ++ ".part"));
    const t = msu_codec.Track.open(flac, .flac).?;
    defer t.close();
    try testing.expectEqual(@as(u64, frames), t.frames);
    try testing.expectEqual(@as(u64, 777), t.loop_start);

    // And it seeks, which is how it loops.
    try testing.expect(t.seek(777));
    var got: [4][2]i16 = undefined;
    try testing.expectEqual(@as(usize, 4), t.read(&got));
    for (got, 0..) |f, i| {
        try testing.expectEqual(std.mem.readInt(i16, bytes[8 + (777 + i) * 4 ..][0..2], .little), f[0]);
        try testing.expectEqual(std.mem.readInt(i16, bytes[8 + (777 + i) * 4 + 2 ..][0..2], .little), f[1]);
    }
    const size = (try fileio.readWholeFile(testing.allocator, flac));
    defer testing.allocator.free(size);
    try testing.expect(size.len < bytes.len / 2);
}

test "something that isn't a .pcm track stays as it was" {
    const root = ".zig-cache/msu-flac-bad";
    const pcm = root ++ "/alttp_msu-6.pcm";
    defer for ([_][*:0]const u8{ pcm, root ++ "/alttp_msu-6.flac", root }) |p| {
        _ = c.SDL_RemovePath(p);
    };
    try testing.expect(c.SDL_CreateDirectory(root));
    try fileio.writeWholeFile(pcm, "RIFF this is a wav file really");
    try testing.expectError(error.NotPcm, pcmToFlac(testing.allocator, pcm, root ++ "/alttp_msu-6.flac"));
    try testing.expect(fileio.exists(pcm));
    try testing.expect(!fileio.exists(root ++ "/alttp_msu-6.flac"));
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
    try testing.expectEqual(TrackName{ .number = 3, .ext = .flac }, trackOf("pack-3.FLAC").?);
    try testing.expectEqual(TrackName{ .number = 4, .ext = .ogg }, trackOf("pack-4.ogg").?);
}

test "only the game's own track names count as the installed pack" {
    try testing.expect(isInstalledTrack("alttp_msu-1.pcm", "alttp_msu-"));
    try testing.expect(isInstalledTrack("alttp_msu-34.opuz", "alttp_msu-"));
    try testing.expect(isInstalledTrack("alttp_msu-2.flac", "alttp_msu-"));
    try testing.expect(isInstalledTrack("alttp_msu-3.ogg", "alttp_msu-"));
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

    try testing.expectEqual(@as(usize, 2), (try importPack(alloc, zip_path, msu_dir ++ "/alttp_msu-", null, .{})).tracks);
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
    try testing.expectError(error.NoTracks, importPack(testing.allocator, src, msu_dir ++ "/alttp_msu-", null, .{}));
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
    try testing.expectEqual(@as(usize, 1), (try importPack(testing.allocator, src, msu_dir ++ "/alttp_msu-", null, .{})).tracks);
    const got = try fileio.readWholeFile(testing.allocator, msu_dir ++ "/alttp_msu-3.opuz");
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("OPUZ three", got);
}

test "stored as FLAC, a pack's .pcm tracks go in as FLAC and the rest as they are" {
    const root = ".zig-cache/msu-import-flac";
    const msu_dir = root ++ "/msu";
    const src = root ++ "/pack";
    defer {
        for ([_][*:0]const u8{ msu_dir ++ "/alttp_msu-1.flac", msu_dir ++ "/alttp_msu-1.pcm", msu_dir ++ "/alttp_msu-2.ogg", src ++ "/p-1.pcm", src ++ "/p-2.ogg", src, msu_dir, root }) |p| _ = c.SDL_RemovePath(p);
    }
    try testing.expect(c.SDL_CreateDirectory(src));
    var pcm: [8 + 500 * 4]u8 = @splat(0);
    @memcpy(pcm[0..4], "MSU1");
    for (0..500) |i| std.mem.writeInt(i16, pcm[8 + i * 4 ..][0..2], @intCast(i * 7), .little);
    try fileio.writeWholeFile(src ++ "/p-1.pcm", &pcm);
    try fileio.writeWholeFile(src ++ "/p-2.ogg", "OggS not checked here");

    const got = try importPack(testing.allocator, src, msu_dir ++ "/alttp_msu-", null, .{ .flac = true });
    try testing.expectEqual(@as(usize, 2), got.tracks);
    try testing.expectEqual(@as(usize, 1), got.flac);
    try testing.expect(fileio.exists(msu_dir ++ "/alttp_msu-1.flac"));
    try testing.expect(!fileio.exists(msu_dir ++ "/alttp_msu-1.pcm"));
    try testing.expect(fileio.exists(msu_dir ++ "/alttp_msu-2.ogg"));
    // The pack it came from is left alone.
    try testing.expect(fileio.exists(src ++ "/p-1.pcm"));
}

test "packs are named after their folder or zip" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("Super Metroid Orchestral", packName(&buf, "/Users/me/Downloads/Super Metroid Orchestral.zip"));
    try testing.expectEqualStrings("Zelda Remix", packName(&buf, "C:\\packs\\Zelda Remix\\"));
    try testing.expectEqualStrings("a_b", packName(&buf, "/x/a:b.ZIP"));
    try testing.expectEqualStrings("Pack", packName(&buf, "/x/...zip"));
}

test "the menu names a pack by its folder" {
    try testing.expectEqualStrings("Zelda Remix", packLabel("msu/Zelda Remix/alttp_msu-"));
    try testing.expectEqualStrings("Earlier import", packLabel("msu/alttp_msu-"));
    try testing.expectEqualStrings("cool", packLabel("msu/cool-"));
    try testing.expectEqualStrings("/somewhere/else/x-", packLabel("/somewhere/else/x-"));
}

test "installed packs are found in their folders, and the loose one too" {
    const lib = ".zig-cache/msu-packs-test";
    const files = [_][*:0]const u8{
        lib ++ "/alttp_msu-1.pcm",
        lib ++ "/alttp_msu-2.pcm",
        lib ++ "/Remix/alttp_msu-1.flac",
        lib ++ "/Remix/alttp_msu-2.pcm",
        lib ++ "/Remix/readme.txt",
        lib ++ "/Orchestral/orch_1.ogg",
        lib ++ "/Empty/notes.txt",
    };
    defer {
        for (files) |f| _ = c.SDL_RemovePath(f);
        for ([_][*:0]const u8{ lib ++ "/Remix", lib ++ "/Orchestral", lib ++ "/Empty", lib }) |d| _ = c.SDL_RemovePath(d);
    }
    for ([_][*:0]const u8{ lib ++ "/Remix", lib ++ "/Orchestral", lib ++ "/Empty" }) |d| try testing.expect(c.SDL_CreateDirectory(d));
    for (files) |f| try fileio.writeWholeFile(f, "x");

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const packs = try listPacks(arena_state.allocator(), lib);
    try testing.expectEqual(@as(usize, 3), packs.len);
    try testing.expectEqualStrings("Earlier import", packs[0].name);
    try testing.expectEqualStrings(lib ++ "/alttp_msu-", packs[0].path);
    try testing.expectEqual(@as(usize, 2), packs[0].pcm);
    try testing.expectEqualStrings("Orchestral", packs[1].name);
    try testing.expectEqualStrings(lib ++ "/Orchestral/orch_", packs[1].path);
    try testing.expectEqualStrings("Remix", packs[2].name);
    try testing.expectEqual(@as(usize, 2), packs[2].tracks);
    try testing.expectEqual(@as(usize, 1), packs[2].pcm);
}

test "a named import goes in whole, beside what's there, or not at all" {
    const root = ".zig-cache/msu-named-test";
    const lib = root ++ "/msu";
    const src = root ++ "/Cool Pack";
    const all = [_][*:0]const u8{
        src ++ "/cool-1.pcm",            src ++ "/cool-2.pcm",
        lib ++ "/Mine/alttp_msu-1.pcm",  lib ++ "/Mine/alttp_msu-2.pcm",
        lib ++ "/Mine/alttp_msu-9.pcm",  lib ++ "/Mine/cover.png",
        lib ++ "/Other/alttp_msu-1.pcm",
    };
    defer {
        for (all) |f| _ = c.SDL_RemovePath(f);
        for ([_][*:0]const u8{ lib ++ "/Mine", lib ++ "/Other", lib ++ "/.importing-Mine", lib, src, root }) |d| _ = c.SDL_RemovePath(d);
    }
    for ([_][*:0]const u8{ src, lib ++ "/Mine", lib ++ "/Other" }) |d| try testing.expect(c.SDL_CreateDirectory(d));
    try fileio.writeWholeFile(src ++ "/cool-1.pcm", "MSU1 new one");
    try fileio.writeWholeFile(src ++ "/cool-2.pcm", "MSU1 new two");
    try fileio.writeWholeFile(lib ++ "/Mine/alttp_msu-9.pcm", "MSU1 old nine");
    try fileio.writeWholeFile(lib ++ "/Mine/cover.png", "art");
    try fileio.writeWholeFile(lib ++ "/Other/alttp_msu-1.pcm", "MSU1 other");

    // Stopped before it starts: the pack called that is as it was.
    var status = Status{};
    status.cancel.store(true, .release);
    try testing.expectError(error.Canceled, importNamed(testing.allocator, src, lib, "Mine", .{ .status = &status }));
    try testing.expect(fileio.exists(lib ++ "/Mine/alttp_msu-9.pcm"));
    try testing.expect(!fileio.isDir(lib ++ "/.importing-Mine"));

    // Let through: it replaces that pack's tracks, keeps its other files,
    // and leaves every other pack alone.
    var going = Status{};
    const got = try importNamed(testing.allocator, src, lib, "Mine", .{ .status = &going });
    defer testing.allocator.free(got.msu_path);
    try testing.expectEqualStrings(lib ++ "/Mine/alttp_msu-", got.msu_path);
    try testing.expectEqual(@as(usize, 2), got.imported.tracks);
    try testing.expect(fileio.exists(lib ++ "/Mine/alttp_msu-1.pcm"));
    try testing.expect(fileio.exists(lib ++ "/Mine/alttp_msu-2.pcm"));
    try testing.expect(!fileio.exists(lib ++ "/Mine/alttp_msu-9.pcm"));
    try testing.expect(fileio.exists(lib ++ "/Mine/cover.png"));
    try testing.expect(fileio.exists(lib ++ "/Other/alttp_msu-1.pcm"));
    try testing.expect(!fileio.isDir(lib ++ "/.importing-Mine"));
    try testing.expectEqual(going.total.load(.acquire), going.done.load(.acquire));
    try testing.expectEqual(@as(usize, 2), going.tracks.load(.acquire));
}

test "names are cut short on a character, not in the middle of one" {
    var buf: [64]u8 = undefined;
    var long: [65]u8 = @splat('a');
    long[63] = 0xc3; // the first half of an e with an accent
    long[64] = 0xa9;
    const got = cleanName(&buf, &long);
    try testing.expectEqual(@as(usize, 63), got.len);
    try testing.expect(std.unicode.utf8ValidateSlice(got));
}

test "a pack loose in the library moves into a folder of its own" {
    const lib = ".zig-cache/msu-tidy-test";
    defer {
        for ([_][*:0]const u8{ lib ++ "/Earlier import/alttp_msu-1.pcm", lib ++ "/Earlier import/alttp_msu-2.flac", lib ++ "/Earlier import 2/alttp_msu-1.pcm", lib ++ "/Earlier import 2/alttp_msu-2.flac", lib ++ "/readme.txt", lib ++ "/Earlier import/keep.txt" }) |f| _ = c.SDL_RemovePath(f);
        for ([_][*:0]const u8{ lib ++ "/Earlier import 2", lib ++ "/Earlier import", lib }) |d| _ = c.SDL_RemovePath(d);
    }
    // A folder already called that, which isn't touched.
    try testing.expect(c.SDL_CreateDirectory(lib ++ "/Earlier import"));
    try fileio.writeWholeFile(lib ++ "/Earlier import/keep.txt", "mine");
    try fileio.writeWholeFile(lib ++ "/alttp_msu-1.pcm", "MSU1 one");
    try fileio.writeWholeFile(lib ++ "/alttp_msu-2.flac", "fLaC two");
    try fileio.writeWholeFile(lib ++ "/readme.txt", "not a track");

    const moved = moveLoosePack(testing.allocator, lib).?;
    defer testing.allocator.free(moved.from);
    defer testing.allocator.free(moved.to);
    try testing.expectEqualStrings(lib ++ "/alttp_msu-", moved.from);
    try testing.expectEqualStrings(lib ++ "/Earlier import 2/alttp_msu-", moved.to);
    try testing.expect(fileio.exists(lib ++ "/Earlier import 2/alttp_msu-1.pcm"));
    try testing.expect(fileio.exists(lib ++ "/Earlier import 2/alttp_msu-2.flac"));
    try testing.expect(!fileio.exists(lib ++ "/alttp_msu-1.pcm"));
    try testing.expect(fileio.exists(lib ++ "/readme.txt"));
    // And once it's moved there's nothing loose left to move.
    try testing.expect(moveLoosePack(testing.allocator, lib) == null);

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const packs = try listPacks(arena_state.allocator(), lib);
    try testing.expectEqual(@as(usize, 1), packs.len);
    try testing.expectEqualStrings("Earlier import 2", packs[0].name);
    try testing.expectEqual(@as(u64, 16), packs[0].bytes);
    var kb: [32]u8 = undefined;
    try testing.expectEqualStrings("PCM and FLAC", kindsLabel(&kb, packs[0]));
}

test "deleting a pack takes its folder, and nothing else" {
    const lib = ".zig-cache/msu-delete-test";
    defer {
        for ([_][*:0]const u8{ lib ++ "/Gone/alttp_msu-1.pcm", lib ++ "/Gone/.DS_Store", lib ++ "/Gone/cover.png", lib ++ "/Stays/alttp_msu-1.pcm" }) |f| _ = c.SDL_RemovePath(f);
        for ([_][*:0]const u8{ lib ++ "/Gone", lib ++ "/Stays", lib }) |d| _ = c.SDL_RemovePath(d);
    }
    for ([_][*:0]const u8{ lib ++ "/Gone", lib ++ "/Stays" }) |d| try testing.expect(c.SDL_CreateDirectory(d));
    try fileio.writeWholeFile(lib ++ "/Gone/alttp_msu-1.pcm", "MSU1");
    try fileio.writeWholeFile(lib ++ "/Gone/.DS_Store", "mac");
    try fileio.writeWholeFile(lib ++ "/Gone/cover.png", "art");
    try fileio.writeWholeFile(lib ++ "/Stays/alttp_msu-1.pcm", "MSU1");
    try testing.expect(deletePack(testing.allocator, lib, lib ++ "/Gone/alttp_msu-"));
    try testing.expect(!fileio.isDir(lib ++ "/Gone"));
    try testing.expect(fileio.exists(lib ++ "/Stays/alttp_msu-1.pcm"));
}

test "a pack is renamed by its folder, capitals and all, but not onto another" {
    const lib = ".zig-cache/msu-rename-test";
    defer {
        for ([_][*:0]const u8{ lib ++ "/Big Band/alttp_msu-1.flac", lib ++ "/big band/alttp_msu-1.flac", lib ++ "/Remix/alttp_msu-1.flac", lib ++ "/Orchestra/alttp_msu-1.flac", lib ++ "/Other/alttp_msu-1.pcm" }) |f| _ = c.SDL_RemovePath(f);
        for ([_][*:0]const u8{ lib ++ "/Big Band", lib ++ "/big band", lib ++ "/Remix", lib ++ "/Orchestra", lib ++ "/Other", lib }) |d| _ = c.SDL_RemovePath(d);
    }
    for ([_][*:0]const u8{ lib ++ "/Remix", lib ++ "/Other" }) |d| try testing.expect(c.SDL_CreateDirectory(d));
    try fileio.writeWholeFile(lib ++ "/Remix/alttp_msu-1.flac", "fLaC");
    try fileio.writeWholeFile(lib ++ "/Other/alttp_msu-1.pcm", "MSU1");

    try testing.expect(nameTaken(lib, "Remix", "Other"));
    try testing.expect(!nameTaken(lib, "Remix", "remix"));
    try testing.expectError(error.NameTaken, renamePack(testing.allocator, lib, lib ++ "/Remix/alttp_msu-", "Other"));

    const a = try renamePack(testing.allocator, lib, lib ++ "/Remix/alttp_msu-", "big band");
    defer testing.allocator.free(a);
    try testing.expectEqualStrings(lib ++ "/big band/alttp_msu-", a);
    // Only the capitals: through another name and back.
    const b = try renamePack(testing.allocator, lib, a, "Big Band");
    defer testing.allocator.free(b);
    try testing.expectEqualStrings(lib ++ "/Big Band/alttp_msu-", b);

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const packs = try listPacks(arena_state.allocator(), lib);
    try testing.expectEqual(@as(usize, 2), packs.len);
    try testing.expectEqualStrings("Big Band", packs[0].name);
    try testing.expectEqualStrings("Other", packs[1].name);
}
