//! `zelda3 tools`: everything to do with the game's assets that isn't
//! playing it, from the terminal. With no command it opens the tools window,
//! which main.zig sees to, since that goes through the start menu.
const std = @import("std");
const ops = @import("tools_ops.zig");
const gui = @import("tools_gui.zig");
const dev = @import("tools_dev.zig");
const fileio = @import("fileio.zig");
const updater = @import("updater.zig");

const kUsage =
    \\zelda3 tools: build and check the assets for zelda3.
    \\
    \\Run with no command to open the window, as the start menu's Tools
    \\entry does. Commands:
    \\
    \\  build [--rom ROM] [--out FILE] [--from DIR [--sprites-from-png]]
    \\        [--languages L1,L2 [--lang-dir DIR]]
    \\                    Build zelda3_assets.dat from the US ROM, or with
    \\                    --from, from files exported and edited in DIR.
    \\                    --sprites-from-png also takes the sprite sheets
    \\                    from DIR/sprites. --languages builds in
    \\                    translations extracted into --lang-dir (or the
    \\                    --from folder): de, fr, fr-c, en, es, pl, pt,
    \\                    redux, nl, sv (defaults: zelda3.sfc,
    \\                    zelda3_assets.dat)
    \\  export [--rom ROM] --out DIR
    \\                    Write the overworld, dungeon rooms, map table and
    \\                    dialogue into DIR as YAML and text; Link, the
    \\                    font, the HUD icons and the sprite sheets as PNGs;
    \\                    and the music, sound effects and samples to look
    \\                    at (music builds from the ROM, as it always did)
    \\  extract-dialogue --rom ROM --out DIR [--as LANG]
    \\                    Write a translated ROM's dialogue and font into
    \\                    DIR, to build in with --languages. --as reads a
    \\                    ROM this doesn't recognize as that language
    \\  verify [FILE]     Check an asset file against this version
    \\  rom-info ROM      Say which release a ROM is
    \\  check-msu PACK    Look over an MSU-1 pack, a folder or a .zip, for
    \\                    missing tracks and files that won't play
    \\  version           Say which version this is
    \\  gui               Open the window
    \\  help              This
    \\
    \\Updates are the game's: zelda3 --check-update and zelda3 --update.
    \\
    \\For working on the game itself:
    \\
    \\  input-log FILE    Print the input log in a snapshot (.sav)
    \\  text-dict [FILE]  Search a dialogue.txt for the dictionary that
    \\                    would compress it best (slow; prints as it goes)
    \\
    \\The ancilla parity check is zig run other/check_ancilla_parity.zig.
    \\
;

/// Runs `zelda3 tools <args>`, and says what to exit with.
pub fn command(alloc: std.mem.Allocator, args: []const [:0]const u8) u8 {
    // Asking for help isn't a mistake, so it isn't an error either.
    if (args.len == 0 or std.mem.eql(u8, args[0], "help") or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        std.debug.print("{s}", .{kUsage});
        return 0;
    }
    const ok = runCommand(alloc, args) catch |e| switch (e) {
        error.Usage => {
            std.debug.print("{s}", .{kUsage});
            return 2;
        },
        else => {
            std.debug.print("error: {s}\n", .{@errorName(e)});
            return 1;
        },
    };
    return if (ok) 0 else 1;
}

/// Whether `zelda3 tools <args>` means the window rather than a command.
pub fn wantsWindow(args: []const [:0]const u8) bool {
    return args.len == 0 or (args.len == 1 and std.mem.eql(u8, args[0], "gui"));
}

/// Runs `f` with a writer to stdout, flushed after.
fn toStdout(f: anytype, args: anytype) !void {
    var threaded: std.Io.Threaded = .init(std.heap.c_allocator, .{});
    defer threaded.deinit();
    var buf: [4096]u8 = undefined;
    var w = std.Io.File.stdout().writerStreaming(threaded.io(), &buf);
    try @call(.auto, f, args ++ .{&w.interface});
    try w.interface.flush();
}

/// Prints a Log to the terminal, marking errors so they stand out.
fn terminalLog() ops.Log {
    const S = struct {
        var dummy: u8 = 0;
        fn write(ctx: *anyopaque, level: ops.Log.Level, text: []const u8) void {
            _ = ctx;
            const mark = switch (level) {
                .info => "",
                .ok => "",
                .err => "error: ",
            };
            std.debug.print("{s}{s}\n", .{ mark, text });
        }
    };
    return .{ .ctx = &S.dummy, .writeFn = S.write };
}

/// Pulls `--name value` out of an argument list.
fn option(args: []const [:0]const u8, name: []const u8) error{Usage}!?[:0]const u8 {
    for (args, 0..) |a, i| {
        if (!std.mem.eql(u8, a, name)) continue;
        if (i + 1 >= args.len) return error.Usage;
        return args[i + 1];
    }
    return null;
}

/// Whether a bare `--name` flag is present.
fn flag(args: []const [:0]const u8, name: []const u8) bool {
    for (args) |a| if (std.mem.eql(u8, a, name)) return true;
    return false;
}

/// Arguments that aren't options or their values.
fn positional(args: []const [:0]const u8, i: usize) ?[:0]const u8 {
    var n: usize = 0;
    var skip = false;
    for (args) |a| {
        if (skip) {
            skip = false;
            continue;
        }
        if (std.mem.startsWith(u8, a, "--")) {
            skip = !std.mem.eql(u8, a, "--sprites-from-png");
            continue;
        }
        if (n == i) return a;
        n += 1;
    }
    return null;
}

fn runCommand(alloc: std.mem.Allocator, args: []const [:0]const u8) !bool {
    const cmd = args[0];
    const rest = args[1..];
    const log = terminalLog();
    for (rest) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) return error.Usage;
    }

    if (std.mem.eql(u8, cmd, "build")) {
        const rom = try option(rest, "--rom") orelse "zelda3.sfc";
        const out = try option(rest, "--out") orelse "zelda3_assets.dat";
        const from = try option(rest, "--from");
        var extra = ops.Extra{};
        var lang_buf: [16]@import("rom.zig").Language = undefined;
        if (try option(rest, "--languages")) |list| {
            extra.languages = ops.parseLanguages(log, list, &lang_buf) orelse return false;
            extra.dir = try option(rest, "--lang-dir") orelse from orelse {
                log.err("Say where the extracted languages are with --lang-dir.", .{});
                return false;
            };
        }
        if (from) |dir| {
            const sprites = flag(rest, "--sprites-from-png");
            return ops.buildFromFiles(alloc, log, rom, dir, out, .{ .sprites_from_png = sprites }, extra);
        }
        return ops.buildAssets(alloc, log, rom, out, extra);
    }
    if (std.mem.eql(u8, cmd, "extract-dialogue")) {
        const rom = try option(rest, "--rom") orelse return error.Usage;
        const out = try option(rest, "--out") orelse return error.Usage;
        var as: ?@import("rom.zig").Language = null;
        if (try option(rest, "--as")) |code| {
            as = @import("asset_languages.zig").fromCode(code) orelse {
                log.err("'{s}' isn't a language this knows. Try de, fr, fr-c, en, es, pl, pt, redux, nl or sv.", .{code});
                return false;
            };
        }
        return ops.extractDialogue(alloc, log, rom, out, as);
    }
    if (std.mem.eql(u8, cmd, "export")) {
        const rom = try option(rest, "--rom") orelse "zelda3.sfc";
        const out = try option(rest, "--out") orelse return error.Usage;
        return ops.exportFiles(alloc, log, rom, out);
    }
    if (std.mem.eql(u8, cmd, "verify")) {
        return ops.verifyAssets(alloc, log, positional(rest, 0) orelse "zelda3_assets.dat");
    }
    if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version")) {
        std.debug.print("ALTTP-DX {s} {s}\n", .{ updater.version, updater.commit });
        return true;
    }
    if (std.mem.eql(u8, cmd, "check-msu")) {
        return ops.checkMsuPack(alloc, log, positional(rest, 0) orelse return error.Usage);
    }
    if (std.mem.eql(u8, cmd, "rom-info")) {
        return ops.romInfo(alloc, log, positional(rest, 0) orelse return error.Usage);
    }
    if (std.mem.eql(u8, cmd, "input-log")) {
        const path = positional(rest, 0) orelse return error.Usage;
        const data = fileio.readWholeFile(alloc, path.ptr) catch |e| {
            log.err("Could not read {s}: {s}.", .{ path, ops.plainError(e) });
            return false;
        };
        defer alloc.free(data);
        toStdout(dev.inputLog, .{data}) catch |e| {
            log.err("{s}: {s}", .{ path, if (e == error.NotASnapshot) "too short to be a snapshot" else @errorName(e) });
            return false;
        };
        return true;
    }
    if (std.mem.eql(u8, cmd, "text-dict")) {
        const path = positional(rest, 0) orelse "dialogue.txt";
        const data = fileio.readWholeFile(alloc, path.ptr) catch |e| {
            log.err("Could not read {s}: {s}.", .{ path, ops.plainError(e) });
            return false;
        };
        defer alloc.free(data);
        toStdout(dev.textDict, .{ alloc, data }) catch |e| {
            log.err("{s}: {s}", .{ path, @errorName(e) });
            return false;
        };
        return true;
    }
    // Undocumented: what the music page plays, as a file, for hearing it
    // without the window.
    if (std.mem.eql(u8, cmd, "music-wav")) {
        const assets = positional(rest, 0) orelse return error.Usage;
        const number = std.fmt.parseInt(u8, positional(rest, 1) orelse return error.Usage, 10) catch return error.Usage;
        const out = positional(rest, 2) orelse return error.Usage;
        const music = @import("tools_music.zig");
        const p = try music.Player.init(alloc, assets);
        defer p.deinit();
        for (p.songs) |s| std.debug.print("{d}:{s} ", .{ s.number, @tagName(s.bank) });
        std.debug.print("\n", .{});
        try music.writeWav(alloc, assets, number, out, 8);
        return true;
    }
    // Undocumented: a frame of the window as a picture, for working on it.
    if (std.mem.eql(u8, cmd, "gui-screenshot")) {
        const path = positional(rest, 0) orelse return error.Usage;
        const page = positional(rest, 1);
        const lines = if (rest.len > 2) rest[2..] else &[_][:0]const u8{};
        try gui.screenshot(alloc, path, page, lines);
        return true;
    }
    return error.Usage;
}

test "options and positionals are told apart" {
    const args = [_][:0]const u8{ "--rom", "a.sfc", "file.dat", "--out", "b.dat" };
    try std.testing.expectEqualStrings("a.sfc", (try option(&args, "--rom")).?);
    try std.testing.expectEqualStrings("b.dat", (try option(&args, "--out")).?);
    try std.testing.expectEqualStrings("file.dat", positional(&args, 0).?);
    try std.testing.expect(positional(&args, 1) == null);
    try std.testing.expectError(error.Usage, option(&[_][:0]const u8{"--rom"}, "--rom"));
}

test {
    _ = ops;
    _ = @import("yaml.zig");
    _ = @import("asset_import.zig");
    _ = @import("asset_export.zig");
    _ = @import("png.zig");
    _ = @import("asset_dialogue.zig");
    _ = dev;
    _ = @import("tools_music.zig");
    _ = @import("tools_pictures.zig");
    _ = @import("tools_game.zig");
    _ = @import("tools_draw.zig");
}
