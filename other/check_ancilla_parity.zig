//! Compares the handwritten ancilla port with the original C, without keeping
//! a C copy in the tree.
//!
//!     zig run other/check_ancilla_parity.zig [-- extra zig build test args]
//!
//! Pulls ancilla.c and the headers it includes out of the baseline commit,
//! renames every function it defines to Ref_<name> so the original can link
//! beside the port, and runs the tests with it as the oracle. Needs Git, and
//! the baseline commit in the local repository. Anything after `--` goes to
//! `zig build test`, e.g. -Doptimize=ReleaseSafe.
const std = @import("std");

const kBaseline = "fbbb3f967a51fafe642e6140d0753979e73b4090";

/// The headers ancilla.c includes, directly or not. They come from the
/// baseline commit alongside it, since the working tree has no C headers.
const kHeaders = [_][]const u8{
    "ancilla.h",     "assets.h",    "dungeon.h",   "features.h",  "hud.h",         "load_gfx.h",
    "misc.h",        "overworld.h", "player.h",    "sprite.h",    "sprite_main.h", "tagalong.h",
    "tile_detect.h", "types.h",     "variables.h", "zelda_rtl.h",
};

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const root = std.mem.trimEnd(u8, try git(arena, io, ".", &.{ "rev-parse", "--show-toplevel" }), "\n");
    const source = try git(arena, io, root, &.{ "show", kBaseline ++ ":src/ancilla.c" });

    // Rename the definitions and the calls between them, keeping the original
    // control flow and expressions intact. Other subsystems use the game's
    // own symbols.
    var oracle: std.ArrayList(u8) = .empty;
    try oracle.appendSlice(arena, "#define kBomb_Tab0 Ref_kBomb_Tab0\n");
    for (try functionNames(arena, source)) |name| try oracle.print(arena, "#define {s} Ref_{s}\n", .{ name, name });
    try oracle.appendSlice(arena, source);

    // Quoted includes resolve next to the including file, so a flat copy of
    // the headers beside the .c is enough.
    const dir_path = try std.fs.path.join(arena, &.{ root, ".zig-cache", "ancilla-parity" });
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, dir_path);
    for (kHeaders) |h| {
        const text = try git(arena, io, root, &.{ "show", try std.fmt.allocPrint(arena, "{s}:src/{s}", .{ kBaseline, h }) });
        try cwd.writeFile(io, .{ .sub_path = try std.fs.path.join(arena, &.{ dir_path, h }), .data = text });
    }
    const oracle_path = try std.fs.path.join(arena, &.{ dir_path, "ancilla_reference.c" });
    try cwd.writeFile(io, .{ .sub_path = oracle_path, .data = oracle.items });

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ "zig", "build", "test", try std.fmt.allocPrint(arena, "-Dancilla-reference={s}", .{oracle_path}), "--summary", "all" });
    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 1) try argv.appendSlice(arena, args[1..]);

    var child = try std.process.spawn(io, .{ .argv = argv.items, .cwd = .{ .path = root } });
    const term = try child.wait(io);
    _ = gpa;
    return switch (term) {
        .exited => |code| code,
        else => 1,
    };
}

/// Runs git and returns what it printed, with Windows line endings made
/// plain (the baseline's C has them); a failure is fatal.
fn git(arena: std.mem.Allocator, io: std.Io, cwd: []const u8, args: []const []const u8) ![]u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, "git");
    try argv.appendSlice(arena, args);
    const r = try std.process.run(arena, io, .{ .argv = argv.items, .cwd = .{ .path = cwd } });
    if (r.term != .exited or r.term.exited != 0) {
        std.debug.print("git {s} failed:\n{s}", .{ args[0], r.stderr });
        return error.GitFailed;
    }
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < r.stdout.len) : (i += 1) {
        const ch = r.stdout[i];
        if (ch == '\r') {
            try out.append(arena, '\n');
            if (i + 1 < r.stdout.len and r.stdout[i + 1] == '\n') i += 1;
        } else try out.append(arena, ch);
    }
    return out.items;
}

fn isWord(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0b or ch == 0x0c;
}

/// The names of the functions a C file defines: at the start of a line, one
/// or more words each followed by whitespace, any stars, the name, and a
/// parameter list on one line with no semicolon, then an opening brace. It
/// is the regex the Python used, ^(?:\w+\s+)+\**(\w+)\([^;\n]*\)\s*\{, by
/// hand, matches taken in order and never overlapping.
fn functionNames(arena: std.mem.Allocator, src: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var p: usize = 0;
    while (p < src.len) {
        const at_line_start = p == 0 or src[p - 1] == '\n';
        if (at_line_start) {
            if (matchDefinition(src, p)) |m| {
                try out.append(arena, m.name);
                p = m.end;
                continue;
            }
        }
        p += 1;
    }
    return out.items;
}

fn matchDefinition(src: []const u8, start: usize) ?struct { name: []const u8, end: usize } {
    // (?:\w+\s+)+ : whole words followed by whitespace, as many as there are.
    var q = start;
    var groups: usize = 0;
    while (true) {
        var w = q;
        while (w < src.len and isWord(src[w])) w += 1;
        if (w == q or w >= src.len or !isSpace(src[w])) break;
        while (w < src.len and isSpace(src[w])) w += 1;
        q = w;
        groups += 1;
    }
    if (groups == 0) return null;
    // \**(\w+)\(
    while (q < src.len and src[q] == '*') q += 1;
    const name_start = q;
    while (q < src.len and isWord(src[q])) q += 1;
    if (q == name_start or q >= src.len or src[q] != '(') return null;
    const name = src[name_start..q];
    // [^;\n]*\)\s*\{ : the parameters run to a ')' on the same line with no
    // ';' before it; the regex tries the last such ')' first.
    var limit = q + 1;
    while (limit < src.len and src[limit] != ';' and src[limit] != '\n') limit += 1;
    var close = limit;
    while (close > q + 1) {
        close -= 1;
        if (src[close] != ')') continue;
        var b = close + 1;
        while (b < src.len and isSpace(src[b])) b += 1;
        if (b < src.len and src[b] == '{') return .{ .name = name, .end = b + 1 };
    }
    return null;
}
