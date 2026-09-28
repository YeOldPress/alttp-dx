//! What zelda3-tools can do, independent of how it was asked: the GUI and the
//! command line both come here. Each operation reports progress and results
//! through a Log rather than printing, so the GUI can show them in its panel
//! and the command line can pass them straight to the terminal.
const std = @import("std");
const fileio = @import("fileio.zig");
const rom_mod = @import("rom.zig");
const asset_all = @import("asset_all.zig");
const asset_export = @import("asset_export.zig");
const pack = @import("asset_pack.zig");

pub const Log = struct {
    ctx: *anyopaque,
    writeFn: *const fn (ctx: *anyopaque, level: Level, text: []const u8) void,

    pub const Level = enum { info, ok, err };

    pub fn print(self: Log, level: Level, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, fmt, args) catch fmt;
        self.writeFn(self.ctx, level, text);
    }

    pub fn info(self: Log, comptime fmt: []const u8, args: anytype) void {
        self.print(.info, fmt, args);
    }
    pub fn ok(self: Log, comptime fmt: []const u8, args: anytype) void {
        self.print(.ok, fmt, args);
    }
    pub fn err(self: Log, comptime fmt: []const u8, args: anytype) void {
        self.print(.err, fmt, args);
    }
};

/// Human names for the languages a ROM can be, as the ROM table knows them.
pub fn languageName(lang: rom_mod.Language) []const u8 {
    return switch (lang) {
        .us => "English (USA)",
        .de => "German",
        .fr => "French",
        .fr_c => "French (Canada)",
        .en => "English (Europe)",
        .es => "Spanish",
        .pl => "Polish",
        .pt => "Portuguese",
        .redux => "English Redux",
        .nl => "Dutch",
        .sv => "Swedish",
    };
}

/// Loads a ROM and says what it is. Null, with the reason logged, when it
/// can't be read.
pub fn loadRom(alloc: std.mem.Allocator, log: Log, path: [:0]const u8) ?rom_mod.Rom {
    const rom = rom_mod.Rom.load(alloc, path.ptr) catch |e| {
        log.err("Could not read {s}: {s}", .{ path, @errorName(e) });
        return null;
    };
    if (rom.language) |lang| {
        log.info("{s}: {s} ROM", .{ std.fs.path.basename(path), languageName(lang) });
    } else {
        log.info("{s}: not a ROM this tool recognizes", .{std.fs.path.basename(path)});
    }
    return rom;
}

pub fn romInfo(alloc: std.mem.Allocator, log: Log, path: [:0]const u8) bool {
    var rom = loadRom(alloc, log, path) orelse return false;
    defer rom.deinit();
    log.info("Size: {d} bytes", .{rom.bytes.len});
    if (rom.language) |lang| {
        for (rom_mod.kKnownRoms) |k| {
            if (k.lang == lang) log.info("Identified as: {s}", .{k.name});
        }
        if (lang == .us) {
            log.ok("This ROM can build zelda3_assets.dat.", .{});
        } else {
            log.ok("This ROM can supply its dialogue as an extra language.", .{});
        }
        return true;
    }
    log.err("Unknown ROM. The US release of A Link to the Past is needed to build the assets.", .{});
    return false;
}

/// Builds zelda3_assets.dat from the US ROM and writes it to `out`.
pub fn buildAssets(alloc: std.mem.Allocator, log: Log, rom_path: [:0]const u8, out: [:0]const u8) bool {
    var rom = loadRom(alloc, log, rom_path) orelse return false;
    defer rom.deinit();
    if (rom.language != .us) {
        log.err("Building the assets needs the US ROM.", .{});
        return false;
    }
    const data = asset_all.buildFile(alloc, rom) catch |e| {
        log.err("Building the assets failed: {s}", .{@errorName(e)});
        return false;
    };
    defer alloc.free(data);
    fileio.writeWholeFile(out.ptr, data) catch |e| {
        log.err("Could not write {s}: {s}", .{ out, @errorName(e) });
        return false;
    };
    log.ok("Wrote {s} ({d} bytes).", .{ out, data.len });
    return verifyData(log, data);
}

fn loadUsRom(alloc: std.mem.Allocator, log: Log, rom_path: [:0]const u8) ?rom_mod.Rom {
    var rom = loadRom(alloc, log, rom_path) orelse return null;
    if (rom.language != .us) {
        log.err("This needs the US ROM.", .{});
        rom.deinit();
        return null;
    }
    return rom;
}

var g_export_count: usize = 0;
fn countExported(name: []const u8) void {
    _ = name;
    g_export_count += 1;
}

/// Writes the ROM's areas, rooms, map table and dialogue into `dir` as files
/// to edit, in the formats the old Python tool used.
pub fn exportFiles(alloc: std.mem.Allocator, log: Log, rom_path: [:0]const u8, dir: [:0]const u8) bool {
    var rom = loadUsRom(alloc, log, rom_path) orelse return false;
    defer rom.deinit();
    fileio.makeDir(dir.ptr) catch {
        log.err("Could not make the folder {s}", .{dir});
        return false;
    };
    g_export_count = 0;
    asset_export.exportText(alloc, rom, dir, countExported) catch |e| {
        log.err("Export failed after {d} files: {s}", .{ g_export_count, @errorName(e) });
        return false;
    };
    log.ok("Exported {d} files to {s}.", .{ g_export_count, dir });
    log.info("Edit them, then build from the folder to turn them into zelda3_assets.dat.", .{});
    return true;
}

/// Builds zelda3_assets.dat from edited files in `dir`, taking everything
/// the files don't cover from the US ROM.
pub fn buildFromFiles(alloc: std.mem.Allocator, log: Log, rom_path: [:0]const u8, dir: [:0]const u8, out: [:0]const u8) bool {
    var rom = loadUsRom(alloc, log, rom_path) orelse return false;
    defer rom.deinit();
    var problem = asset_all.import_mod.Problem{};
    var files = asset_all.import_mod.Files.load(alloc, rom, dir, &problem) catch |e| {
        log.err("{s}", .{if (e == error.BadInput) problem.text() else @errorName(e)});
        return false;
    };
    defer files.deinit();
    log.info("Read the files in {s}.", .{dir});
    var assets = asset_all.buildFrom(alloc, rom, &files, &problem) catch |e| {
        log.err("{s}", .{if (e == error.BadInput) problem.text() else @errorName(e)});
        return false;
    };
    defer assets.deinit();
    const data = pack.write(alloc, assets.items) catch |e| {
        log.err("Packing the assets failed: {s}", .{@errorName(e)});
        return false;
    };
    defer alloc.free(data);
    fileio.writeWholeFile(out.ptr, data) catch |e| {
        log.err("Could not write {s}: {s}", .{ out, @errorName(e) });
        return false;
    };
    log.ok("Wrote {s} ({d} bytes).", .{ out, data.len });
    _ = verifyData(log, data);
    return true;
}

/// Checks an asset file against the digest this build of the game expects.
pub fn verifyAssets(alloc: std.mem.Allocator, log: Log, path: [:0]const u8) bool {
    const data = fileio.readWholeFile(alloc, path.ptr) catch |e| {
        log.err("Could not read {s}: {s}", .{ path, @errorName(e) });
        return false;
    };
    defer alloc.free(data);
    return verifyData(log, data);
}

fn verifyData(log: Log, data: []const u8) bool {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    if (std.mem.eql(u8, &hex, asset_all.kReferenceDigest)) {
        log.ok("Verified: matches the assets this version of the game expects.", .{});
        return true;
    }
    log.info("SHA-256 {s}", .{&hex});
    log.info("Doesn't match the standard assets. That's expected for a mod or extra languages, and wrong otherwise.", .{});
    return false;
}

test "an unreadable asset file is reported, not crashed on" {
    var sink = TestLog{};
    try std.testing.expect(!verifyAssets(std.testing.allocator, sink.log(), "no-such-file.dat"));
    try std.testing.expect(sink.errors == 1);
}

/// A Log for tests that just counts what it's told.
pub const TestLog = struct {
    errors: usize = 0,
    lines: usize = 0,

    pub fn log(self: *TestLog) Log {
        return .{ .ctx = self, .writeFn = write };
    }

    fn write(ctx: *anyopaque, level: Log.Level, text: []const u8) void {
        _ = text;
        const self: *TestLog = @ptrCast(@alignCast(ctx));
        self.lines += 1;
        if (level == .err) self.errors += 1;
    }
};
