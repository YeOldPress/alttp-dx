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
const msu_import = @import("msu_import.zig");
const dev = @import("tools_dev.zig");

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

/// What went wrong, in words, for the failures people actually run into.
/// Anything rarer keeps its name, which is at least searchable.
pub fn plainError(e: anyerror) []const u8 {
    return switch (e) {
        error.FileNotFound => "it isn't there",
        error.AccessDenied, error.PermissionDenied => "permission was denied",
        error.IsDir => "that's a folder, not a file",
        error.NotDir => "part of that path isn't a folder",
        error.NoSpaceLeft => "the disk is full",
        error.OutOfMemory => "ran out of memory",
        else => @errorName(e),
    };
}

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
        log.err("Could not read {s}: {s}.", .{ path, plainError(e) });
        return null;
    };
    if (rom.language) |lang| {
        log.info("{s}: {s} ROM", .{ std.fs.path.basename(path), languageName(lang) });
    } else {
        log.info("{s}: not a ROM these tools recognize.", .{std.fs.path.basename(path)});
    }
    return rom;
}

pub fn romInfo(alloc: std.mem.Allocator, log: Log, path: [:0]const u8) bool {
    var rom = loadRom(alloc, log, path) orelse return false;
    defer rom.deinit();
    log.info("Size: {d} KB", .{rom.bytes.len / 1024});
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
        log.err("{s}", .{if (e == error.BadInput) problem.text() else plainError(e)});
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
        log.err("{s}", .{if (e == error.BadInput) problem.text() else plainError(e)});
        return false;
    };
    defer assets.deinit();
    const data = pack.write(alloc, assets.items) catch |e| {
        log.err("Packing the assets failed: {s}.", .{plainError(e)});
        return false;
    };
    defer alloc.free(data);
    fileio.writeWholeFile(out.ptr, data) catch |e| {
        log.err("Could not save {s}: {s}.", .{ out, plainError(e) });
        return false;
    };
    log.ok("Saved {s} ({d} KB).", .{ std.fs.path.basename(out), data.len / 1024 });
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
        log.err("Couldn't read the font: {s}.", .{plainError(e)});
        return false;
    };
    defer alloc.free(font);
    var name_buf: [32]u8 = undefined;
    for ([_]struct { []const u8, []const u8 }{ .{ dialogue.fileName(&name_buf, lang), text }, .{ graphics.fontType(lang).file, font } }) |f| {
        var path_buf: [1024]u8 = undefined;
        const path = std.fmt.bufPrintSentinel(&path_buf, "{s}/{s}", .{ dir, f[0] }, 0) catch return false;
        fileio.writeWholeFile(path.ptr, f[1]) catch |e| {
            log.err("Could not save {s}: {s}.", .{ path, plainError(e) });
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
        log.err("Export stopped after {d} files: {s}.", .{ g_export_count, plainError(e) });
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
        log.err("{s}", .{if (e == error.BadInput) problem.text() else plainError(e)});
        return false;
    };
    defer files.deinit();
    log.info("Read the files in {s}{s}.", .{ dir, if (options.sprites_from_png) ", sprite sheets included" else "" });
    return buildAndWrite(alloc, log, rom, &files, extra, out);
}

/// Checks an asset file against the digest this build of the game expects.
pub fn verifyAssets(alloc: std.mem.Allocator, log: Log, path: [:0]const u8) bool {
    const data = fileio.readWholeFile(alloc, path.ptr) catch |e| {
        log.err("Could not read {s}: {s}.", .{ path, plainError(e) });
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
    if (pack.loadsInGame(data)) {
        log.ok("Custom assets, from a mod or extra languages. The game plays them.", .{});
    } else {
        log.err("These are from another version of the game. Build them again.", .{});
    }
    log.info("Its SHA-256 is {s}.", .{&hex});
    return false;
}

// ------------------------------------------------------------ MSU-1 packs

/// Looks over an MSU-1 pack, a folder or a .zip, without installing it: which
/// of the game's tracks it has, which it leaves to the game's own music, and
/// any file that won't play. True when nothing's wrong with it.
pub fn checkMsuPack(alloc: std.mem.Allocator, log: Log, path: [:0]const u8) bool {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const found = msu_import.inspectPack(arena_state.allocator(), path) catch |e| {
        log.err("{s}", .{switch (e) {
            error.NotFound => "Couldn't open that pack.",
            error.NoTracks => "There are no MSU-1 tracks in that. Their names end in a number and .pcm or .opuz.",
            error.BadZip => "That zip is damaged, or packed in a way these tools can't read.",
            else => plainError(e),
        }});
        return false;
    };
    if (found.len == 0) {
        log.err("There are no MSU-1 tracks in that. Their names end in a number and .pcm or .opuz.", .{});
        return false;
    }

    var pcm: usize = 0;
    var opuz: usize = 0;
    var extra: usize = 0;
    var have: [msu_import.kGameTracks + 1]bool = @splat(false);
    for (found) |f| {
        if (f.name.ext == .pcm) pcm += 1 else opuz += 1;
        if (f.name.number <= msu_import.kGameTracks) have[f.name.number] = true else extra += 1;
    }
    const kinds = if (pcm != 0 and opuz != 0) ".pcm and .opuz" else if (pcm != 0) ".pcm" else ".opuz";
    log.info("{s}: {d} tracks, as {s}.", .{ std.fs.path.basename(path), found.len, kinds });

    var bad: usize = 0;
    for (found) |f| {
        const problem = f.problem orelse continue;
        log.err("Track {d} ({s}) {s}.", .{ f.name.number, f.file, problem });
        bad += 1;
    }

    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    var missing: usize = 0;
    for (1..have.len) |n| {
        if (have[n]) continue;
        w.print("{s}{d}", .{ if (missing != 0) ", " else "", n }) catch {};
        missing += 1;
    }
    if (missing == 0) {
        log.ok("All {d} of the game's tracks are there.", .{msu_import.kGameTracks});
    } else if (missing == msu_import.kGameTracks) {
        log.info("None of the game's {d} tracks are there, so the game plays its own music throughout.", .{msu_import.kGameTracks});
    } else {
        log.info("Missing track{s} {s}; the game plays its own music there.", .{ if (missing == 1) "" else "s", w.buffered() });
    }
    if (extra != 0) log.info("Plus {d} extra track{s} past {d}, which randomizer seeds play in dungeons.", .{ extra, if (extra == 1) "" else "s", msu_import.kGameTracks });

    if (bad != 0) {
        log.err("{d} track{s} won't play. Fix or replace {s} before importing.", .{ bad, if (bad == 1) "" else "s", if (bad == 1) "it" else "them" });
        return false;
    }
    log.ok("Looks good. Import it from the game's start menu.", .{});
    return true;
}

// ----------------------------------------------------- for working on the game

/// `path` with its extension swapped for `suffix`: "run.sav" and
/// "-inputs.txt" make "run-inputs.txt", beside it.
fn besidePath(alloc: std.mem.Allocator, path: []const u8, suffix: []const u8) ![:0]u8 {
    const base = std.fs.path.basename(path);
    const stem_len = path.len - base.len + (std.mem.lastIndexOfScalar(u8, base, '.') orelse base.len);
    return std.fmt.allocPrintSentinel(alloc, "{s}{s}", .{ path[0..stem_len], suffix }, 0);
}

/// Writes a snapshot's input log out as text beside it, for reading: the
/// frame each change happened on, and the buttons held from then.
pub fn saveInputLog(alloc: std.mem.Allocator, log: Log, path: [:0]const u8) bool {
    const data = fileio.readWholeFile(alloc, path.ptr) catch |e| {
        log.err("Could not read {s}: {s}.", .{ path, plainError(e) });
        return false;
    };
    defer alloc.free(data);
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    dev.inputLog(data, &out.writer) catch |e| {
        log.err("{s} {s}", .{ std.fs.path.basename(path), switch (e) {
            error.NotASnapshot => "is too short to be a snapshot.",
            error.BadLog => "has an input log that doesn't make sense. Is it a snapshot from this game?",
            else => "couldn't be read.",
        } });
        return false;
    };
    const dest = besidePath(alloc, path, "-inputs.txt") catch return false;
    defer alloc.free(dest);
    fileio.writeWholeFile(dest.ptr, out.written()) catch |e| {
        log.err("Could not save {s}: {s}.", .{ dest, plainError(e) });
        return false;
    };
    const changes = std.mem.count(u8, out.written(), "\n");
    log.ok("Saved {s}: {d} changes of input.", .{ std.fs.path.basename(dest), changes });
    return true;
}

/// Passes each pick to the log as the search makes it, and keeps everything
/// for the file.
const PickLog = struct {
    w: std.Io.Writer,
    alloc: std.mem.Allocator,
    log: Log,
    all: std.ArrayList(u8) = .empty,
    line_start: usize = 0,
    picks: usize = 0,

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *PickLog = @fieldParentPtr("w", w);
        self.take(w.buffer[0..w.end]) catch return error.WriteFailed;
        w.end = 0;
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |d| {
            self.take(d) catch return error.WriteFailed;
            n += d.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| {
            self.take(last) catch return error.WriteFailed;
            n += last.len;
        }
        return n;
    }

    fn take(self: *PickLog, bytes: []const u8) !void {
        try self.all.appendSlice(self.alloc, bytes);
        while (std.mem.indexOfScalarPos(u8, self.all.items, self.line_start, '\n')) |nl| {
            const line = self.all.items[self.line_start..nl];
            self.line_start = nl + 1;
            if (!std.mem.startsWith(u8, line, "Removed best")) continue;
            self.picks += 1;
            self.log.info("{d}. {s}", .{ self.picks, line["Removed best ".len..] });
        }
    }
};

/// Searches a dialogue.txt for the dictionary that would compress it best,
/// showing each pick as it's made, and saves the whole result beside it as
/// dictionary.txt. Takes minutes.
pub fn saveTextDict(alloc: std.mem.Allocator, log: Log, path: [:0]const u8) bool {
    const data = fileio.readWholeFile(alloc, path.ptr) catch |e| {
        log.err("Could not read {s}: {s}.", .{ path, plainError(e) });
        return false;
    };
    defer alloc.free(data);
    log.info("Searching. This takes a few minutes, and each pick shows up here.", .{});
    var buf: [1024]u8 = undefined;
    var picks = PickLog{ .w = .{ .vtable = &.{ .drain = PickLog.drain }, .buffer = &buf }, .alloc = alloc, .log = log };
    defer picks.all.deinit(alloc);
    dev.textDict(alloc, data, &picks.w) catch |e| {
        log.err("{s}", .{if (e == error.BadDialogue) "That doesn't look like a dialogue.txt: every line should be a number, a colon, then the text." else plainError(e)});
        return false;
    };
    picks.w.flush() catch return false;
    const dir = std.fs.path.dirname(path) orelse ".";
    const dest = std.fmt.allocPrintSentinel(alloc, "{s}/dictionary.txt", .{dir}, 0) catch return false;
    defer alloc.free(dest);
    fileio.writeWholeFile(dest.ptr, picks.all.items) catch |e| {
        log.err("Could not save {s}: {s}.", .{ dest, plainError(e) });
        return false;
    };
    log.ok("Saved dictionary.txt beside it: {d} picks, and every message with them marked.", .{picks.picks});
    return true;
}

test "files written beside another take its name" {
    const a = std.testing.allocator;
    const one = try besidePath(a, "saves/run.sav", "-inputs.txt");
    defer a.free(one);
    try std.testing.expectEqualStrings("saves/run-inputs.txt", one);
    const two = try besidePath(a, "dir.v2/noext", "-inputs.txt");
    defer a.free(two);
    try std.testing.expectEqualStrings("dir.v2/noext-inputs.txt", two);
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
