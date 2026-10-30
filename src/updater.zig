//! Keeping the game up to date from its GitHub releases.
//!
//! When the start menu opens it asks GitHub, on a thread of its own so the
//! window never waits on the network, whether there's something newer than
//! this build: the latest release, or the rolling nightly for anyone who
//! picked that channel. If there is, the menu shows an Update button, and
//! nothing is downloaded until it's pressed.
//!
//! An update replaces the game the way it was installed, then starts the new
//! one: the whole .app on a Mac, the AppImage on Linux, and the files beside
//! zelda3.exe on Windows (all but zelda3.ini, which is the player's). Saves
//! and settings live elsewhere or are left alone, so they come through it.
//! Downloads are checked against the size and SHA-256 GitHub gives for them.
//!
//! The tools are released beside the game as downloads of their own, and
//! update themselves the same way: `product` says which one this is.
//!
//! A build without a version, which is any build nobody ran through the
//! release workflow, never offers to replace itself.

const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const c = @import("sdl.zig").c;
const fileio = @import("fileio.zig");
const zip = @import("zip.zig");

/// The release tag this was built as, "nightly", or "dev".
pub const version = build_info.version;
/// The commit this was built from, when the build was told.
pub const commit = build_info.commit;

const kApi = "https://api.github.com/repos/YeOldPress/alttp-dx";
const kUserAgent = "alttp-dx-updater";

/// What's being kept up to date: the game, or the tools. Each only ever
/// replaces itself.
pub const Product = struct {
    /// What every file of its download starts with.
    prefix: []const u8,
    /// Its Mac bundle.
    bundle: []const u8,
    /// Its executable, inside the bundle, or beside it with .exe on Windows.
    exe: []const u8,
};

pub const game = Product{ .prefix = "alttp-dx-", .bundle = "ALTTP-DX.app", .exe = "zelda3" };
pub const tools = Product{ .prefix = "zelda3-tools-", .bundle = "zelda3-tools.app", .exe = "zelda3-tools" };

/// Which one this is: the game, unless the tools say so before anything
/// else here runs.
pub var product: *const Product = &game;

pub const Channel = enum {
    releases,
    nightly,

    pub fn fromName(name: []const u8) Channel {
        return if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, name, " \t"), "nightly")) .nightly else .releases;
    }
};

// ----------------------------------------------------------------- versions

/// A release's number, from a tag like "v1.7.1". Missing parts are 0, and
/// anything after the numbers ("-beta") is ignored.
pub const Version = struct {
    parts: [3]u32 = .{ 0, 0, 0 },

    pub fn parse(tag: []const u8) ?Version {
        var rest = tag;
        if (rest.len != 0 and (rest[0] == 'v' or rest[0] == 'V')) rest = rest[1..];
        if (rest.len == 0 or !std.ascii.isDigit(rest[0])) return null;
        var v = Version{};
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            var end: usize = 0;
            while (end < rest.len and std.ascii.isDigit(rest[end])) end += 1;
            if (end == 0) break;
            v.parts[i] = std.fmt.parseInt(u32, rest[0..end], 10) catch return null;
            rest = rest[end..];
            if (rest.len < 2 or rest[0] != '.' or !std.ascii.isDigit(rest[1])) break;
            rest = rest[1..];
        }
        return v;
    }

    pub fn newerThan(self: Version, other: Version) bool {
        return std.mem.order(u32, &self.parts, &other.parts) == .gt;
    }
};

/// What this build is, as far as updating goes.
pub const Installed = union(enum) {
    release: Version,
    nightly,
    /// Built by hand: never updated from GitHub.
    dev,

    pub fn of(v: []const u8) Installed {
        if (std.mem.eql(u8, v, "nightly")) return .nightly;
        if (std.mem.startsWith(u8, v, "v")) if (Version.parse(v)) |r| return .{ .release = r };
        return .dev;
    }
};

pub const installed = Installed.of(version);

// ------------------------------------------------------------------- GitHub

const AssetJson = struct {
    name: []const u8,
    browser_download_url: []const u8,
    size: u64,
    /// "sha256:<hex>", on releases made since GitHub started keeping them.
    digest: ?[]const u8 = null,
};

const ReleaseJson = struct {
    tag_name: []const u8,
    html_url: []const u8,
    assets: []const AssetJson = &.{},
};

const RefJson = struct { object: struct { sha: []const u8 } };
const CompareJson = struct { status: []const u8 };

/// The end of the game's download's name for this system.
const kAssetSuffix: ?[]const u8 = switch (builtin.os.tag) {
    .macos => "-macos-arm64.zip",
    .windows => "-windows-x86_64.zip",
    .linux => "-x86_64.AppImage",
    else => null,
};

/// One product's download for this system, out of a release's files.
fn pickAsset(assets: []const AssetJson, prefix: []const u8, suffix: []const u8) ?AssetJson {
    for (assets) |a| {
        if (std.mem.startsWith(u8, a.name, prefix) and std.mem.endsWith(u8, a.name, suffix)) return a;
    }
    return null;
}

/// The SHA-256 out of GitHub's "sha256:<hex>", or null for anything else.
fn parseDigest(digest: ?[]const u8) ?[32]u8 {
    const d = digest orelse return null;
    if (!std.mem.startsWith(u8, d, "sha256:")) return null;
    var out: [32]u8 = undefined;
    const got = std.fmt.hexToBytes(&out, d["sha256:".len..]) catch return null;
    if (got.len != out.len) return null;
    return out;
}

/// Whether `status`, from comparing what's installed with what's out, means
/// what's out has something this build doesn't.
fn compareMeansNewer(status: []const u8) bool {
    return std.mem.eql(u8, status, "ahead") or std.mem.eql(u8, status, "diverged");
}

// -------------------------------------------------------------------- state

/// Where things stand. The worker thread moves it along; the menu reads it
/// every frame and moves it itself only when no worker is running.
pub const Phase = enum(u8) {
    /// Not asked, or update checks are off.
    idle,
    checking,
    up_to_date,
    /// The check failed. Nobody asked for it, so nobody's told.
    check_failed,
    /// Something newer is out: the offer is filled in.
    available,
    downloading,
    installing,
    /// Installed. Starting it again finishes the job.
    ready,
    /// The update was asked for and didn't happen; `message` says why.
    failed,
};

fn Fixed(comptime n: usize) type {
    return struct {
        buf: [n]u8 = @splat(0),
        len: usize = 0,

        fn set(self: *@This(), text: []const u8) void {
            self.len = @min(text.len, n - 1);
            @memcpy(self.buf[0..self.len], text[0..self.len]);
            self.buf[self.len] = 0;
        }
        fn get(self: *const @This()) [:0]const u8 {
            return self.buf[0..self.len :0];
        }
    };
}

/// What's on offer. Written by the check before it says .available, and
/// left alone after.
const Offer = struct {
    /// What the menu calls it: "V1.8", "NIGHTLY 1A2B3C4".
    label: Fixed(40) = .{},
    url: Fixed(1024) = .{},
    page: Fixed(256) = .{},
    size: u64 = 0,
    sha256: ?[32]u8 = null,
};

var g_phase = std.atomic.Value(Phase).init(.idle);
var g_offer: Offer = .{};
var g_message: []const u8 = "";
var g_done = std.atomic.Value(u64).init(0);
var g_total = std.atomic.Value(u64).init(0);
var g_cancel = std.atomic.Value(bool).init(false);

pub fn phase() Phase {
    return g_phase.load(.acquire);
}

/// The offer's name, for the menu, while there is one.
pub fn offerLabel() []const u8 {
    return g_offer.label.get();
}

/// The release's page, for when an update can't be done in place.
pub fn pageUrl() [:0]const u8 {
    return if (g_offer.page.len != 0) g_offer.page.get() else "https://github.com/YeOldPress/alttp-dx/releases";
}

/// Why the update didn't happen.
pub fn message() []const u8 {
    return g_message;
}

/// Bytes downloaded so far, and of how many.
pub fn progress() struct { done: u64, total: u64 } {
    return .{ .done = g_done.load(.monotonic), .total = g_total.load(.monotonic) };
}

/// What this build calls itself, for the menu: "V1.7.1", "NIGHTLY 1A2B3C4".
pub fn installedLabel(buf: []u8) []const u8 {
    return switch (installed) {
        .nightly => nightlyLabel(buf, commit),
        else => std.ascii.upperString(buf[0..@min(buf.len, version.len)], version[0..@min(buf.len, version.len)]),
    };
}

fn nightlyLabel(buf: []u8, sha: []const u8) []const u8 {
    var short: [7]u8 = undefined;
    const n = @min(sha.len, short.len);
    _ = std.ascii.upperString(short[0..n], sha[0..n]);
    return std.fmt.bufPrint(buf, "NIGHTLY {s}", .{short[0..n]}) catch "NIGHTLY";
}

/// Whether anything is going on that the menu shouldn't start over.
fn busy(p: Phase) bool {
    return switch (p) {
        .checking, .downloading, .installing, .ready => true,
        else => false,
    };
}

// -------------------------------------------------------------- the install

/// Where the game is and how it was installed, which is what an update has
/// to replace.
const Target = struct {
    kind: enum { mac_bundle, appimage, windows_folder },
    /// The .app, the AppImage, or the folder holding the .exe, with a
    /// separator on the end for a folder.
    path: Fixed(4096) = .{},
};

var g_target: ?Target = null;
var g_target_found = false;

fn target() ?Target {
    if (g_target_found) return g_target;
    g_target_found = true;
    g_target = locate();
    return g_target;
}

fn locate() ?Target {
    switch (builtin.os.tag) {
        .macos => {
            const base = std.mem.span(c.SDL_GetBasePath() orelse return null);
            const tail = "/Contents/Resources/";
            if (!std.mem.endsWith(u8, base, ".app" ++ tail)) return null;
            var t = Target{ .kind = .mac_bundle };
            t.path.set(base[0 .. base.len - tail.len]);
            return t;
        },
        .linux => {
            const image = c.SDL_getenv("APPIMAGE") orelse return null;
            var t = Target{ .kind = .appimage };
            t.path.set(std.mem.span(image));
            return t;
        },
        .windows => {
            // The game works in its own folder, and the tools' window moves
            // into theirs, so the files are named relative to it, which keeps
            // the C runtime's narrow paths away from whatever it's called.
            var exe_buf: [64]u8 = undefined;
            const exe = std.fmt.bufPrintSentinel(&exe_buf, "{s}.exe", .{product.exe}, 0) catch return null;
            if (!fileio.exists(exe.ptr)) return null;
            const base = c.SDL_GetBasePath() orelse return null;
            var t = Target{ .kind = .windows_folder };
            t.path.set(std.mem.span(base));
            return t;
        },
        else => return null,
    }
}

/// Whether this build can update itself where it is: it has a version to
/// compare, and it was installed the way a release installs.
pub fn supported() bool {
    if (installed == .dev or kAssetSuffix == null) return false;
    return target() != null;
}

const Failure = error{
    Network,
    NoAsset,
    WriteFailed,
    Corrupt,
    Unpack,
    Cancelled,
    OutOfMemory,
};

fn describe(err: Failure) []const u8 {
    return switch (err) {
        error.Network => "COULD NOT REACH GITHUB",
        error.NoAsset => "NO DOWNLOAD FOR THIS SYSTEM",
        error.WriteFailed => if (product == &tools) "CAN'T REPLACE THE TOOLS HERE" else "CAN'T REPLACE THE GAME HERE",
        error.Corrupt => "DOWNLOAD CAME OUT DAMAGED",
        error.Unpack => "COULD NOT UNPACK THE UPDATE",
        error.Cancelled => "CANCELLED",
        error.OutOfMemory => "OUT OF MEMORY",
    };
}

/// An HTTP client and the I/O it runs on, for the length of one job on the
/// worker thread.
const Http = struct {
    threaded: std.Io.Threaded,
    client: std.http.Client,

    fn init(self: *Http) void {
        self.threaded = .init(std.heap.c_allocator, .{});
        self.client = .{ .allocator = std.heap.c_allocator, .io = self.threaded.io() };
    }

    fn deinit(self: *Http) void {
        self.client.deinit();
        self.threaded.deinit();
    }

    /// The body of a GitHub API answer, parsed as `T`.
    fn api(self: *Http, comptime T: type, arena: std.mem.Allocator, url: []const u8) Failure!T {
        var body: std.Io.Writer.Allocating = .init(arena);
        const res = self.client.fetch(.{
            .location = .{ .url = url },
            .response_writer = &body.writer,
            .headers = .{ .user_agent = .{ .override = kUserAgent } },
            .extra_headers = &.{
                .{ .name = "Accept", .value = "application/vnd.github+json" },
                .{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" },
            },
        }) catch return error.Network;
        if (res.status != .ok) return error.Network;
        return std.json.parseFromSliceLeaky(T, arena, body.written(), .{ .ignore_unknown_fields = true }) catch error.Network;
    }

    /// Downloads `url` into `dest`, counting as it goes, and checks it
    /// against the size and digest GitHub gave.
    fn download(self: *Http, url: []const u8, dest: [:0]const u8, size: u64, sha256: ?[32]u8) Failure!void {
        const uri = std.Uri.parse(url) catch return error.Network;
        var req = self.client.request(.GET, uri, .{
            // As it is on the server, so the size and digest match.
            .headers = .{ .user_agent = .{ .override = kUserAgent }, .accept_encoding = .omit },
        }) catch return error.Network;
        defer req.deinit();
        req.sendBodiless() catch return error.Network;
        // Release files live on another host, which GitHub redirects to.
        var redirect_buf: [8 * 1024]u8 = undefined;
        var response = req.receiveHead(&redirect_buf) catch return error.Network;
        if (response.head.status != .ok) return error.Network;
        g_total.store(response.head.content_length orelse size, .monotonic);

        const out = fileio.fopen(dest.ptr, "wb") orelse return error.WriteFailed;
        var closed = false;
        defer if (!closed) {
            _ = fileio.fclose(out);
        };
        var transfer: [16 * 1024]u8 = undefined;
        const body = response.reader(&transfer);
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        var chunk: [64 * 1024]u8 = undefined;
        var done: u64 = 0;
        while (true) {
            if (g_cancel.load(.acquire)) return error.Cancelled;
            const n = body.readSliceShort(&chunk) catch return error.Network;
            hash.update(chunk[0..n]);
            if (n != 0 and fileio.fwrite(&chunk, 1, n, out) != n) return error.WriteFailed;
            done += n;
            g_done.store(done, .monotonic);
            if (n < chunk.len) break;
        }
        closed = true;
        if (fileio.fclose(out) != 0) return error.WriteFailed;
        if (done != size) return error.Corrupt;
        if (sha256) |want| if (!std.mem.eql(u8, &hash.finalResult(), &want)) return error.Corrupt;
    }
};

// --------------------------------------------------------------- the check

/// Asks GitHub about `channel` in the background, unless something's
/// already under way.
pub fn check(channel: Channel) void {
    if (!supported() or busy(phase())) return;
    g_phase.store(.checking, .release);
    const t = std.Thread.spawn(.{}, checkThread, .{channel}) catch {
        g_phase.store(.check_failed, .release);
        return;
    };
    t.detach();
}

/// Update checks turned off: whatever was found goes away.
pub fn forget() void {
    if (!busy(phase())) g_phase.store(.idle, .release);
}

fn checkThread(channel: Channel) void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    var http: Http = undefined;
    http.init();
    defer http.deinit();
    const newer = findNewer(&http, arena_state.allocator(), channel) catch {
        g_phase.store(.check_failed, .release);
        return;
    };
    g_phase.store(if (newer) .available else .up_to_date, .release);
}

/// Fills in g_offer and says true when `channel` has something newer than
/// this build.
fn findNewer(http: *Http, arena: std.mem.Allocator, channel: Channel) Failure!bool {
    const rel = try http.api(ReleaseJson, arena, switch (channel) {
        .releases => kApi ++ "/releases/latest",
        .nightly => kApi ++ "/releases/tags/nightly",
    });
    var label_buf: [40]u8 = undefined;
    var label: []const u8 = undefined;

    switch (channel) {
        .releases => {
            const newer = switch (installed) {
                .release => |mine| if (Version.parse(rel.tag_name)) |theirs| theirs.newerThan(mine) else false,
                // A nightly is usually ahead of the last release; the next
                // release is the one that has something it doesn't.
                .nightly => try ahead(http, arena, rel.tag_name),
                .dev => false,
            };
            if (!newer) return false;
            label = std.ascii.upperString(label_buf[0..@min(label_buf.len, rel.tag_name.len)], rel.tag_name[0..@min(label_buf.len, rel.tag_name.len)]);
        },
        .nightly => {
            // Every nightly is tagged "nightly", so the commit under the tag
            // is what tells them apart.
            const ref = try http.api(RefJson, arena, kApi ++ "/git/ref/tags/nightly");
            const sha = ref.object.sha;
            if (commit.len >= 7 and std.ascii.startsWithIgnoreCase(sha, commit)) return false;
            if (!try ahead(http, arena, sha)) return false;
            label = nightlyLabel(&label_buf, sha);
        },
    }

    const suffix = kAssetSuffix orelse return error.NoAsset;
    const asset = pickAsset(rel.assets, product.prefix, suffix) orelse return error.NoAsset;
    g_offer.label.set(label);
    g_offer.url.set(asset.browser_download_url);
    g_offer.page.set(rel.html_url);
    g_offer.size = asset.size;
    g_offer.sha256 = parseDigest(asset.digest);
    return true;
}

/// Whether `theirs`, a tag or commit, has anything this build's commit
/// doesn't. A build that doesn't know its commit takes their word for it.
fn ahead(http: *Http, arena: std.mem.Allocator, theirs: []const u8) Failure!bool {
    if (commit.len == 0) return true;
    const url = std.fmt.allocPrint(arena, kApi ++ "/compare/{s}...{s}?per_page=1", .{ commit, theirs }) catch return error.OutOfMemory;
    const cmp = try http.api(CompareJson, arena, url);
    return compareMeansNewer(cmp.status);
}

// ------------------------------------------------------------- the update

/// Downloads and installs what's on offer, in the background.
pub fn install() void {
    if (phase() != .available and phase() != .failed) return;
    g_cancel.store(false, .release);
    g_done.store(0, .monotonic);
    g_total.store(g_offer.size, .monotonic);
    g_phase.store(.downloading, .release);
    const t = std.Thread.spawn(.{}, installThread, .{}) catch {
        fail(error.OutOfMemory);
        return;
    };
    t.detach();
}

/// Stops a download. Once it's installing, it finishes.
pub fn cancel() void {
    g_cancel.store(true, .release);
}

/// A failure put away: the offer still stands, to try again.
pub fn dismiss() void {
    if (phase() == .failed) g_phase.store(.available, .release);
}

fn fail(err: Failure) void {
    if (err == error.Cancelled) {
        g_phase.store(.available, .release);
        return;
    }
    g_message = describe(err);
    g_phase.store(.failed, .release);
}

fn installThread() void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    var http: Http = undefined;
    http.init();
    defer http.deinit();
    installOffer(&http, arena_state.allocator()) catch |err| return fail(err);
    g_phase.store(.ready, .release);
}

/// Puts what's on offer in place of this install.
fn installOffer(http: *Http, arena: std.mem.Allocator) Failure!void {
    const t = target() orelse return error.WriteFailed;
    return switch (t.kind) {
        .mac_bundle => installMac(http, arena, t.path.get()),
        .appimage => installAppImage(http, arena, t.path.get()),
        .windows_folder => installWindows(http, arena),
    };
}

fn downloadOffer(http: *Http, dest: [:0]const u8) Failure!void {
    http.download(g_offer.url.get(), dest, g_offer.size, g_offer.sha256) catch |err| {
        _ = c.SDL_RemovePath(dest.ptr);
        return err;
    };
    g_phase.store(.installing, .release);
}

/// Beside the bundle, so the swap is a rename on the one disk.
fn macStaging(arena: std.mem.Allocator, bundle: []const u8) Failure![:0]u8 {
    const parent = std.fs.path.dirname(bundle) orelse return error.WriteFailed;
    return std.fmt.allocPrintSentinel(arena, "{s}/.{s}update", .{ parent, product.prefix }, 0) catch error.OutOfMemory;
}

/// The whole .app goes: unpacked beside the old one by ditto, which knows
/// what a bundle needs kept, then swapped in.
fn installMac(http: *Http, arena: std.mem.Allocator, bundle: [:0]const u8) Failure!void {
    const staging = try macStaging(arena, bundle);
    removeTree(arena, staging);
    if (!c.SDL_CreateDirectory(staging.ptr)) return error.WriteFailed;
    const zip_path = try join(arena, staging, "update.zip");
    try downloadOffer(http, zip_path);

    const unpacked = try join(arena, staging, "unpacked");
    const args = [_:null]?[*:0]const u8{ "/usr/bin/ditto", "-x", "-k", zip_path.ptr, unpacked.ptr };
    if (!runAndWait(&args)) return error.Unpack;
    const fresh = try join(arena, unpacked, product.bundle);
    const fresh_exe = std.fmt.allocPrintSentinel(arena, "{s}/Contents/MacOS/{s}", .{ fresh, product.exe }, 0) catch return error.OutOfMemory;
    if (!fileio.exists(fresh_exe.ptr)) return error.Unpack;

    // The old one steps aside, and comes back if the new one won't go in.
    const old = try join(arena, staging, "old.app");
    if (!c.SDL_RenamePath(bundle.ptr, old.ptr)) return error.WriteFailed;
    if (!c.SDL_RenamePath(fresh.ptr, bundle.ptr)) {
        _ = c.SDL_RenamePath(old.ptr, bundle.ptr);
        return error.WriteFailed;
    }
    // The old copy is still what's running; macOS doesn't mind it going.
    removeTree(arena, staging);
}

extern fn chmod(path: [*:0]const u8, mode: c_uint) c_int;

/// One file, downloaded beside itself and renamed over itself. The running
/// copy keeps its mount until it exits.
fn installAppImage(http: *Http, arena: std.mem.Allocator, image: [:0]const u8) Failure!void {
    const tmp = std.fmt.allocPrintSentinel(arena, "{s}.update", .{image}, 0) catch return error.OutOfMemory;
    try downloadOffer(http, tmp);
    if (builtin.os.tag == .linux) {
        if (chmod(tmp.ptr, 0o755) != 0) return error.WriteFailed;
    }
    if (!c.SDL_RenamePath(tmp.ptr, image.ptr)) {
        _ = c.SDL_RemovePath(tmp.ptr);
        return error.WriteFailed;
    }
}

/// The download, in the folder it's going into.
fn windowsZip(arena: std.mem.Allocator) Failure![:0]u8 {
    return std.fmt.allocPrintSentinel(arena, "{s}update.zip", .{product.prefix}, 0) catch error.OutOfMemory;
}
const kNewSuffix = ".update-new";
const kOldSuffix = ".update-old";

/// Each file comes out of the zip beside the one it replaces, and only once
/// they all have do they swap in. Windows won't overwrite a running exe or
/// a loaded DLL, but it will rename them, so the old ones step aside and go
/// the next time the game starts.
fn installWindows(http: *Http, arena: std.mem.Allocator) Failure!void {
    const zip_path = try windowsZip(arena);
    try downloadOffer(http, zip_path);
    defer _ = fileio.remove(zip_path.ptr);

    const f = fileio.fopen(zip_path.ptr, "rb") orelse return error.Unpack;
    var names: std.ArrayList([]const u8) = .empty;
    {
        defer _ = fileio.fclose(f);
        const entries = zip.readDirectory(arena, f) catch return error.Unpack;
        for (entries) |e| {
            const name = windowsFileOf(e) orelse continue;
            const dest = std.fmt.allocPrintSentinel(arena, "{s}" ++ kNewSuffix, .{name}, 0) catch return error.OutOfMemory;
            zip.extract(arena, f, e, dest) catch |err| {
                for (names.items) |n| removeSuffixed(arena, n, kNewSuffix);
                _ = fileio.remove(dest.ptr);
                return if (err == error.WriteFailed) error.WriteFailed else error.Unpack;
            };
            names.append(arena, name) catch return error.OutOfMemory;
        }
    }
    if (names.items.len == 0) return error.Unpack;

    for (names.items, 0..) |name, i| {
        swapIn(arena, name) catch {
            for (names.items[0..i]) |n| swapBack(arena, n);
            for (names.items[i..]) |n| removeSuffixed(arena, n, kNewSuffix);
            return error.WriteFailed;
        };
    }
}

/// Which of the zip's files the update puts in place, by the name it has in
/// the install's folder: the files in the zip's top folder, all but the
/// game's ini, which is the player's.
fn windowsFileOf(e: zip.Entry) ?[]const u8 {
    if (e.isDir()) return null;
    const slash = std.mem.indexOfScalar(u8, e.name, '/') orelse return null;
    const name = e.name[slash + 1 ..];
    if (name.len == 0 or std.mem.indexOfAny(u8, name, "/\\:") != null) return null;
    if (std.mem.eql(u8, name, "..") or std.mem.eql(u8, name, ".")) return null;
    if (std.ascii.eqlIgnoreCase(name, "zelda3.ini")) return null;
    return name;
}

fn suffixed(arena: std.mem.Allocator, name: []const u8, suffix: []const u8) Failure![:0]u8 {
    return std.fmt.allocPrintSentinel(arena, "{s}{s}", .{ name, suffix }, 0) catch error.OutOfMemory;
}

fn removeSuffixed(arena: std.mem.Allocator, name: []const u8, suffix: []const u8) void {
    const p = suffixed(arena, name, suffix) catch return;
    _ = c.SDL_RemovePath(p.ptr);
}

fn swapIn(arena: std.mem.Allocator, name: []const u8) Failure!void {
    const cur = arena.dupeSentinel(u8, name, 0) catch return error.OutOfMemory;
    const new = try suffixed(arena, name, kNewSuffix);
    const old = try suffixed(arena, name, kOldSuffix);
    if (fileio.exists(cur.ptr)) {
        _ = c.SDL_RemovePath(old.ptr);
        if (!c.SDL_RenamePath(cur.ptr, old.ptr)) return error.WriteFailed;
    }
    if (!c.SDL_RenamePath(new.ptr, cur.ptr)) {
        _ = c.SDL_RenamePath(old.ptr, cur.ptr);
        return error.WriteFailed;
    }
}

fn swapBack(arena: std.mem.Allocator, name: []const u8) void {
    const cur = arena.dupeSentinel(u8, name, 0) catch return;
    const old = suffixed(arena, name, kOldSuffix) catch return;
    if (fileio.exists(old.ptr)) _ = c.SDL_RenamePath(old.ptr, cur.ptr) else _ = c.SDL_RemovePath(cur.ptr);
}

/// Starts the version that was just installed. The caller quits straight
/// after.
pub fn restart() bool {
    const t = target() orelse return false;
    var exe_buf: [4200]u8 = undefined;
    const process = switch (t.kind) {
        .mac_bundle => blk: {
            const args = [_:null]?[*:0]const u8{ "/usr/bin/open", "-n", t.path.get().ptr };
            break :blk c.SDL_CreateProcess(@ptrCast(&args), false);
        },
        .appimage => blk: {
            const args = [_:null]?[*:0]const u8{t.path.get().ptr};
            break :blk c.SDL_CreateProcess(@ptrCast(&args), false);
        },
        .windows_folder => blk: {
            const exe = std.fmt.bufPrintSentinel(&exe_buf, "{s}{s}.exe", .{ t.path.get(), product.exe }, 0) catch return false;
            const args = [_:null]?[*:0]const u8{exe.ptr};
            break :blk c.SDL_CreateProcess(@ptrCast(&args), false);
        },
    };
    // Letting go of it leaves it running.
    c.SDL_DestroyProcess(process orelse return false);
    return true;
}

/// Clears away what an update leaves behind: the files it replaced, which
/// the old game was still running from, and anything a cut-off download
/// left half done. Run at startup.
pub fn cleanUp() void {
    if (installed == .dev) return;
    const t = target() orelse return;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    switch (t.kind) {
        .mac_bundle => {
            const staging = macStaging(arena, t.path.get()) catch return;
            removeTree(arena, staging);
        },
        .appimage => {
            const tmp = std.fmt.allocPrintSentinel(arena, "{s}.update", .{t.path.get()}, 0) catch return;
            _ = c.SDL_RemovePath(tmp.ptr);
        },
        .windows_folder => {
            const zip_path = windowsZip(arena) catch return;
            _ = fileio.remove(zip_path.ptr);
            _ = c.SDL_EnumerateDirectory(".", cleanUpCallback, null);
        },
    }
}

fn cleanUpCallback(userdata: ?*anyopaque, dirname: [*c]const u8, fname: [*c]const u8) callconv(.c) c.SDL_EnumerationResult {
    _ = userdata;
    const name = std.mem.span(fname);
    if (std.mem.endsWith(u8, name, kOldSuffix) or std.mem.endsWith(u8, name, kNewSuffix)) {
        var buf: [4096]u8 = undefined;
        const path = std.fmt.bufPrintSentinel(&buf, "{s}{s}", .{ std.mem.span(dirname), name }, 0) catch return c.SDL_ENUM_CONTINUE;
        _ = c.SDL_RemovePath(path.ptr);
    }
    return c.SDL_ENUM_CONTINUE;
}

// ---------------------------------------------------------------- helpers

fn join(arena: std.mem.Allocator, dir: []const u8, name: []const u8) Failure![:0]u8 {
    return std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ dir, name }, 0) catch error.OutOfMemory;
}

/// Runs a program and says whether it exited happily.
fn runAndWait(args: [*:null]const ?[*:0]const u8) bool {
    const p = c.SDL_CreateProcess(@ptrCast(args), false) orelse return false;
    defer c.SDL_DestroyProcess(p);
    var code: c_int = -1;
    if (!c.SDL_WaitProcess(p, true, &code)) return false;
    return code == 0;
}

const TreeCtx = struct { arena: std.mem.Allocator };

/// Deletes a folder the updater made, and everything in it.
fn removeTree(arena: std.mem.Allocator, path: [:0]const u8) void {
    var info: c.SDL_PathInfo = undefined;
    if (!c.SDL_GetPathInfo(path.ptr, &info)) return;
    if (info.type == c.SDL_PATHTYPE_DIRECTORY) {
        var ctx = TreeCtx{ .arena = arena };
        _ = c.SDL_EnumerateDirectory(path.ptr, removeTreeCallback, &ctx);
    }
    _ = c.SDL_RemovePath(path.ptr);
}

fn removeTreeCallback(userdata: ?*anyopaque, dirname: [*c]const u8, fname: [*c]const u8) callconv(.c) c.SDL_EnumerationResult {
    const ctx: *TreeCtx = @ptrCast(@alignCast(userdata));
    const path = std.fmt.allocPrintSentinel(ctx.arena, "{s}{s}", .{ std.mem.span(dirname), std.mem.span(fname) }, 0) catch return c.SDL_ENUM_FAILURE;
    removeTree(ctx.arena, path);
    return c.SDL_ENUM_CONTINUE;
}

/// For `zelda3 --check-update <releases|nightly> [file]`: the start menu's
/// check, on this thread and said out loud, and with a file, the download
/// too. It needs no install to replace, so the updater can be tried from
/// any build that's been given a version.
pub fn checkFromCommandLine(channel: Channel, download_to: ?[:0]const u8) bool {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    var http: Http = undefined;
    http.init();
    defer http.deinit();
    std.debug.print("This is {s} {s}, asking about {s}.\n", .{ version, commit, @tagName(channel) });
    const newer = findNewer(&http, arena_state.allocator(), channel) catch |err| {
        std.debug.print("The check failed: {s}\n", .{describe(err)});
        return false;
    };
    if (!newer) {
        std.debug.print("Up to date.\n", .{});
        return true;
    }
    std.debug.print("{s} is out: {s}\n  {d} bytes, {s}\n", .{ g_offer.label.get(), g_offer.url.get(), g_offer.size, if (g_offer.sha256 != null) "with a SHA-256" else "no digest" });
    const dest = download_to orelse return true;
    http.download(g_offer.url.get(), dest, g_offer.size, g_offer.sha256) catch |err| {
        std.debug.print("The download failed: {s}\n", .{describe(err)});
        return false;
    };
    std.debug.print("Downloaded to {s}, and it checks out.\n", .{dest});
    return true;
}

/// For `zelda3 --update <releases|nightly>`: what the Update button does,
/// without the button, and without starting the new version after.
pub fn updateFromCommandLine(channel: Channel) bool {
    // The Windows install is named from the game's folder, which the game
    // otherwise only moves into once it's starting properly.
    if (builtin.os.tag == .windows) {
        if (c.SDL_GetBasePath()) |base| fileio.setWorkingDirectory(base) catch {};
    }
    if (installed == .dev) {
        std.debug.print("This build has no version, so there's nothing to compare. Only release builds update.\n", .{});
        return false;
    }
    if (!supported()) {
        std.debug.print("This copy isn't installed the way a release is (an .app, an AppImage, or the folder its .exe came in), so it can't replace itself.\n", .{});
        return false;
    }
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    var http: Http = undefined;
    http.init();
    defer http.deinit();
    const newer = findNewer(&http, arena_state.allocator(), channel) catch |err| {
        std.debug.print("The check failed: {s}\n", .{describe(err)});
        return false;
    };
    if (!newer) {
        std.debug.print("Up to date.\n", .{});
        return true;
    }
    std.debug.print("Updating to {s} at {s}...\n", .{ g_offer.label.get(), target().?.path.get() });
    installOffer(&http, arena_state.allocator()) catch |err| {
        std.debug.print("The update failed: {s}\n", .{describe(err)});
        return false;
    };
    std.debug.print("Updated. It starts the new version next time.\n", .{});
    return true;
}

/// For `--menu-shot`: shows the menu as if `p` had happened, with `label`
/// on offer.
pub fn pretend(p: Phase, label: []const u8) void {
    g_offer.label.set(label);
    g_message = describe(error.Network);
    g_total.store(12 * 1024 * 1024, .monotonic);
    g_done.store(5 * 1024 * 1024, .monotonic);
    g_phase.store(p, .release);
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

test "release tags read as numbers, and compare as numbers" {
    try testing.expectEqual([3]u32{ 1, 7, 1 }, Version.parse("v1.7.1").?.parts);
    try testing.expectEqual([3]u32{ 1, 7, 0 }, Version.parse("v1.7").?.parts);
    try testing.expectEqual([3]u32{ 0, 2, 0 }, Version.parse("v0.2-beta").?.parts);
    try testing.expectEqual(@as(?Version, null), Version.parse("nightly"));
    try testing.expectEqual(@as(?Version, null), Version.parse("v"));
    try testing.expect(Version.parse("v1.10").?.newerThan(Version.parse("v1.9.9").?));
    try testing.expect(Version.parse("v1.7.1").?.newerThan(Version.parse("v1.7").?));
    try testing.expect(!Version.parse("v1.7").?.newerThan(Version.parse("v1.7.0").?));
}

test "a build knows whether it's a release, a nightly or homemade" {
    try testing.expectEqual(Installed{ .release = .{ .parts = .{ 1, 7, 1 } } }, Installed.of("v1.7.1"));
    try testing.expectEqual(Installed.nightly, Installed.of("nightly"));
    try testing.expectEqual(Installed.dev, Installed.of("dev"));
    // The workflow names a branch build after the branch; that isn't a release.
    try testing.expectEqual(Installed.dev, Installed.of("main"));
}

test "the game's own download is picked out of a release's files" {
    const assets = [_]AssetJson{
        .{ .name = "zelda3-tools-v1.8-macos-arm64.zip", .browser_download_url = "tools-mac", .size = 1 },
        .{ .name = "alttp-dx-v1.8-macos-arm64.zip", .browser_download_url = "game-mac", .size = 2 },
        .{ .name = "alttp-dx-v1.8-windows-x86_64.zip", .browser_download_url = "game-win", .size = 3 },
        .{ .name = "alttp-dx-v1.8-x86_64.AppImage", .browser_download_url = "game-linux", .size = 4 },
    };
    try testing.expectEqualStrings("game-mac", pickAsset(&assets, game.prefix, "-macos-arm64.zip").?.browser_download_url);
    try testing.expectEqualStrings("game-win", pickAsset(&assets, game.prefix, "-windows-x86_64.zip").?.browser_download_url);
    try testing.expectEqualStrings("game-linux", pickAsset(&assets, game.prefix, "-x86_64.AppImage").?.browser_download_url);
    try testing.expectEqual(@as(?AssetJson, null), pickAsset(assets[0..1], game.prefix, "-macos-arm64.zip"));
    // And the tools take theirs, and only theirs.
    try testing.expectEqualStrings("tools-mac", pickAsset(&assets, tools.prefix, "-macos-arm64.zip").?.browser_download_url);
    try testing.expectEqual(@as(?AssetJson, null), pickAsset(&assets, tools.prefix, "-x86_64.AppImage"));
}

test "a release reads out of GitHub's answer, digest and all" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const json =
        \\{"url":"x","tag_name":"v1.8","name":"v1.8","draft":false,"html_url":"https://github.com/YeOldPress/alttp-dx/releases/tag/v1.8",
        \\ "assets":[{"name":"alttp-dx-v1.8-x86_64.AppImage","size":1234,"content_type":"application/octet-stream",
        \\   "digest":"sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
        \\   "browser_download_url":"https://github.com/YeOldPress/alttp-dx/releases/download/v1.8/alttp-dx-v1.8-x86_64.AppImage"}],
        \\ "body":"notes"}
    ;
    const rel = try std.json.parseFromSliceLeaky(ReleaseJson, arena_state.allocator(), json, .{ .ignore_unknown_fields = true });
    try testing.expectEqualStrings("v1.8", rel.tag_name);
    const a = pickAsset(rel.assets, game.prefix, "-x86_64.AppImage").?;
    try testing.expectEqual(@as(u64, 1234), a.size);
    // sha256("test")
    const d = parseDigest(a.digest).?;
    try testing.expectEqual(@as(u8, 0x9f), d[0]);
    try testing.expectEqual(@as(u8, 0x08), d[31]);
    try testing.expectEqual(@as(?[32]u8, null), parseDigest("md5:abc"));
    try testing.expectEqual(@as(?[32]u8, null), parseDigest(null));
}

test "only a comparison that finds new commits counts as newer" {
    try testing.expect(compareMeansNewer("ahead"));
    try testing.expect(compareMeansNewer("diverged"));
    try testing.expect(!compareMeansNewer("behind"));
    try testing.expect(!compareMeansNewer("identical"));
}

test "a nightly is called by its commit" {
    var buf: [40]u8 = undefined;
    try testing.expectEqualStrings("NIGHTLY 604238C", nightlyLabel(&buf, "604238c0ffee"));
    try testing.expectEqualStrings("NIGHTLY AB", nightlyLabel(&buf, "ab"));
}

test "the Windows update takes the top folder's files and leaves the ini" {
    const e = struct {
        fn of(name: []const u8) zip.Entry {
            return .{ .name = name, .offset = 0, .method = 0, .compressed = 0, .size = 0, .crc = 0 };
        }
    }.of;
    try testing.expectEqualStrings("zelda3.exe", windowsFileOf(e("alttp-dx/zelda3.exe")).?);
    try testing.expectEqualStrings("SDL3.dll", windowsFileOf(e("alttp-dx/SDL3.dll")).?);
    try testing.expectEqual(@as(?[]const u8, null), windowsFileOf(e("alttp-dx/zelda3.ini")));
    try testing.expectEqual(@as(?[]const u8, null), windowsFileOf(e("alttp-dx/")));
    try testing.expectEqual(@as(?[]const u8, null), windowsFileOf(e("alttp-dx/sub/thing.txt")));
    try testing.expectEqual(@as(?[]const u8, null), windowsFileOf(e("loose.txt")));
    try testing.expectEqual(@as(?[]const u8, null), windowsFileOf(e("alttp-dx/..")));
}

test "a Windows-style swap puts new files in, keeps the old aside, and can undo it" {
    const dir = ".zig-cache/updater-swap";
    _ = c.SDL_CreateDirectory(dir);
    defer {
        for ([_][*:0]const u8{ dir ++ "/game.exe", dir ++ "/game.exe" ++ kOldSuffix, dir ++ "/game.exe" ++ kNewSuffix, dir }) |p| _ = c.SDL_RemovePath(p);
    }
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try fileio.writeWholeFile(dir ++ "/game.exe", "old");
    try fileio.writeWholeFile(dir ++ "/game.exe" ++ kNewSuffix, "new");

    try swapIn(arena, dir ++ "/game.exe");
    const now = try fileio.readWholeFile(testing.allocator, dir ++ "/game.exe");
    defer testing.allocator.free(now);
    try testing.expectEqualStrings("new", now);
    try testing.expect(fileio.exists(dir ++ "/game.exe" ++ kOldSuffix));
    try testing.expect(!fileio.exists(dir ++ "/game.exe" ++ kNewSuffix));

    swapBack(arena, dir ++ "/game.exe");
    const back = try fileio.readWholeFile(testing.allocator, dir ++ "/game.exe");
    defer testing.allocator.free(back);
    try testing.expectEqualStrings("old", back);
}

test "removing a tree takes everything in it" {
    const dir = ".zig-cache/updater-tree";
    _ = c.SDL_CreateDirectory(dir ++ "/a/b");
    try fileio.writeWholeFile(dir ++ "/a/b/file.txt", "x");
    try fileio.writeWholeFile(dir ++ "/top.txt", "y");
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    removeTree(arena_state.allocator(), dir);
    try testing.expect(!fileio.isDir(dir));
}
