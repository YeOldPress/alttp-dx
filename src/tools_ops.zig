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
const dialogue = @import("asset_dialogue.zig");
const graphics = @import("asset_graphics.zig");
const langs = @import("asset_languages.zig");
const import_mod = asset_all.import_mod;

/// Translations to build in beside the US text, and the folder their
/// dialogue_xx.txt and font_xx.png are in.
pub const Extra = struct {
    languages: []const rom_mod.Language = &.{},
    dir: []const u8 = "",
};

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
            log.ok("This ROM can supply its dialogue as an extra language: extract it on the Languages page, or with extract-dialogue.", .{});
        }
        return true;
    }
    log.err("Unknown ROM. The US release of A Link to the Past is needed to build the assets.", .{});
    return false;
}

/// Builds zelda3_assets.dat from the US ROM and writes it to `out`.
pub fn buildAssets(alloc: std.mem.Allocator, log: Log, rom_path: [:0]const u8, out: [:0]const u8, extra: Extra) bool {
    var rom = loadUsRom(alloc, log, rom_path) orelse return false;
    defer rom.deinit();
    return buildAndWrite(alloc, log, rom, null, extra, out);
}

/// The build both ways share: load the languages, build, pack, write, check.
fn buildAndWrite(alloc: std.mem.Allocator, log: Log, rom: rom_mod.Rom, files: ?*const import_mod.Files, extra: Extra, out: [:0]const u8) bool {
    var problem = import_mod.Problem{};
    var languages = import_mod.Languages.load(alloc, extra.dir, extra.languages, &problem) catch |e| {
        log.err("{s}", .{if (e == error.BadInput) problem.text() else @errorName(e)});
        return false;
    };
    defer languages.deinit();
    if (extra.languages.len != 0) {
        var buf: [128]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        for (extra.languages, 0..) |l, i| w.print("{s}{s}", .{ if (i != 0) ", " else "", languageName(l) }) catch {};
        log.info("Adding {s}.", .{w.buffered()});
    }
    var assets = asset_all.buildFrom(alloc, rom, files, languages.list, &problem) catch |e| {
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
    // A mod or extra languages can't match the standard file, and that's
    // not a failure.
    const standard = verifyData(log, data);
    if (extra.languages.len != 0) {
        log.info("To play in one, set Language = {s} under [General] in zelda3.ini.", .{langs.get(extra.languages[0]).code});
    }
    return standard or files != null or extra.languages.len != 0;
}

/// Writes a ROM's dialogue and font as dialogue_xx.txt and font_xx.png into
/// `dir`, ready to build in as an extra language. `as` reads a ROM this tool
/// doesn't recognize, such as a patched translation, as that language.
pub fn extractDialogue(alloc: std.mem.Allocator, log: Log, rom_path: [:0]const u8, dir: [:0]const u8, as: ?rom_mod.Language) bool {
    var rom = loadRom(alloc, log, rom_path) orelse return false;
    defer rom.deinit();
    const lang = as orelse rom.language orelse {
        log.err("This isn't a translation this knows. From a terminal, extract-dialogue --as LANG reads it as that language anyway.", .{});
        return false;
    };
    fileio.makeDir(dir.ptr) catch {
        log.err("Could not make the folder {s}", .{dir});
        return false;
    };
    const text = dialogue.dialogueText(alloc, rom, lang) catch |e| {
        log.err("Couldn't read the {s} dialogue out of this ROM ({s}). Is it really that language?", .{ languageName(lang), @errorName(e) });
        return false;
    };
    defer alloc.free(text);
    const font = graphics.exportFont(alloc, rom, lang) catch |e| {
        log.err("Couldn't read the font: {s}", .{@errorName(e)});
        return false;
    };
    defer alloc.free(font);
    var name_buf: [32]u8 = undefined;
    for ([_]struct { []const u8, []const u8 }{ .{ dialogue.fileName(&name_buf, lang), text }, .{ graphics.fontType(lang).file, font } }) |f| {
        var path_buf: [1024]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{ dir, f[0] }) catch return false;
        fileio.writeWholeFile(path.ptr, f[1]) catch |e| {
            log.err("Could not write {s}: {s}", .{ path, @errorName(e) });
            return false;
        };
        log.info("Wrote {s}", .{path});
    }
    log.ok("{s} is ready to build in: pick it as an extra language.", .{languageName(lang)});
    return true;
}

/// The translations whose files are in `dir`.
pub fn availableLanguages(dir: []const u8, buf: []rom_mod.Language) []rom_mod.Language {
    var n: usize = 0;
    for (std.enums.values(rom_mod.Language)) |l| {
        if (l == .us or n == buf.len) continue;
        if (import_mod.Languages.available(dir, l)) {
            buf[n] = l;
            n += 1;
        }
    }
    return buf[0..n];
}

/// Reads "de,fr-c" into languages, or says what it didn't understand.
pub fn parseLanguages(log: Log, text: []const u8, buf: []rom_mod.Language) ?[]rom_mod.Language {
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, text, ", ");
    while (it.next()) |code| {
        const lang = langs.fromCode(code) orelse {
            log.err("'{s}' isn't a language this knows. Try de, fr, fr-c, en, es, pl, pt, redux, nl or sv.", .{code});
            return null;
        };
        if (lang == .us) continue;
        if (std.mem.indexOfScalar(rom_mod.Language, buf[0..n], lang) != null) continue;
        if (n == buf.len) break;
        buf[n] = lang;
        n += 1;
    }
    return buf[0..n];
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
    asset_export.exportFiles(alloc, rom, dir, countExported) catch |e| {
        log.err("Export failed after {d} files: {s}", .{ g_export_count, @errorName(e) });
        return false;
    };
    log.ok("Exported {d} files to {s}.", .{ g_export_count, dir });
    log.info("Edit them, then build from the folder to turn them into zelda3_assets.dat.", .{});
    return true;
}

/// Builds zelda3_assets.dat from edited files in `dir`, taking everything
/// the files don't cover from the US ROM.
pub fn buildFromFiles(alloc: std.mem.Allocator, log: Log, rom_path: [:0]const u8, dir: [:0]const u8, out: [:0]const u8, options: import_mod.Files.Options, extra: Extra) bool {
    var rom = loadUsRom(alloc, log, rom_path) orelse return false;
    defer rom.deinit();
    var problem = import_mod.Problem{};
    var files = import_mod.Files.load(alloc, rom, dir, options, &problem) catch |e| {
        log.err("{s}", .{if (e == error.BadInput) problem.text() else @errorName(e)});
        return false;
    };
    defer files.deinit();
    log.info("Read the files in {s}{s}.", .{ dir, if (options.sprites_from_png) ", sprite sheets included" else "" });
    return buildAndWrite(alloc, log, rom, &files, extra, out);
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
