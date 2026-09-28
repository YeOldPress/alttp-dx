//! zelda3-tools: everything to do with the game's assets that isn't playing
//! it. Run with no arguments for the GUI, or with a command for the terminal.
const std = @import("std");
const ops = @import("tools_ops.zig");
const gui = @import("tools_gui.zig");

const kUsage =
    \\zelda3-tools: build and check the assets for zelda3.
    \\
    \\Run with no arguments to open the window. Commands:
    \\
    \\  build [--rom ROM] [--out FILE] [--from DIR]
    \\                    Build zelda3_assets.dat from the US ROM, or with
    \\                    --from, from files exported and edited in DIR
    \\                    (defaults: zelda3.sfc, zelda3_assets.dat)
    \\  export [--rom ROM] --out DIR
    \\                    Write the overworld, dungeon rooms, map table and
    \\                    dialogue into DIR as YAML and text to edit
    \\  verify [FILE]     Check an asset file against this version
    \\  rom-info ROM      Say which release a ROM is
    \\  gui               Open the window
    \\  help              This
    \\
;

pub fn main(init: std.process.Init.Minimal) !void {
    const alloc = std.heap.c_allocator;
    var it = try init.args.iterateAllocator(alloc);
    defer it.deinit();
    _ = it.next();

    var args: std.ArrayList([:0]const u8) = .empty;
    defer args.deinit(alloc);
    while (it.next()) |a| try args.append(alloc, try alloc.dupeZ(u8, a));

    if (args.items.len == 0) return gui.run(alloc);
    const ok = runCommand(alloc, args.items) catch |e| switch (e) {
        error.Usage => {
            std.debug.print("{s}", .{kUsage});
            std.process.exit(2);
        },
        else => return e,
    };
    if (!ok) std.process.exit(1);
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
            skip = true;
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
        if (try option(rest, "--from")) |dir| return ops.buildFromFiles(alloc, log, rom, dir, out);
        return ops.buildAssets(alloc, log, rom, out);
    }
    if (std.mem.eql(u8, cmd, "export")) {
        const rom = try option(rest, "--rom") orelse "zelda3.sfc";
        const out = try option(rest, "--out") orelse return error.Usage;
        return ops.exportFiles(alloc, log, rom, out);
    }
    if (std.mem.eql(u8, cmd, "verify")) {
        return ops.verifyAssets(alloc, log, positional(rest, 0) orelse "zelda3_assets.dat");
    }
    if (std.mem.eql(u8, cmd, "rom-info")) {
        return ops.romInfo(alloc, log, positional(rest, 0) orelse return error.Usage);
    }
    // Undocumented: a frame of the window as a picture, for working on it.
    if (std.mem.eql(u8, cmd, "gui-screenshot")) {
        const path = positional(rest, 0) orelse return error.Usage;
        const page = positional(rest, 1);
        const lines = if (rest.len > 2) rest[2..] else &[_][:0]const u8{};
        try gui.screenshot(alloc, path, page, lines);
        return true;
    }
    if (std.mem.eql(u8, cmd, "gui")) {
        try gui.run(alloc);
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
}
