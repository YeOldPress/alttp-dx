//! The dialogue asset.
//!
//! This is the one place where the Python's intermediate file is not a
//! lossless view of the ROM. Extraction expands every dictionary reference
//! into the text it stands for, and compilation matches the dictionary again
//! from scratch - greedily, first entry in table order that fits. The result
//! is a valid but different encoding from the one in the ROM, which is why
//! kDialogue cannot be copied and this has to be a real port.
//!
//! The text form is still skipped. Strings go from the decoder to the
//! compressor in memory; only the characters matter, and writing them to a
//! file and reading them back changes nothing.

const std = @import("std");
const rom_mod = @import("rom.zig");
const pack = @import("asset_pack.zig");
const tables = @import("asset_text_tables.zig");
const build_mod = @import("asset_build.zig");

const Rom = rom_mod.Rom;

const kCommandStart = 0x67;
const kSwitchBank = 0x80;
const kFinish = 0xff;
const kDictBase = 0x88;
const kEndMessage = 0x7f;

/// The dialogue is split across two places in the ROM; a switch-bank byte in
/// the stream moves the reader to the next one.
const kRomAddrs = [_]u32{ 0x9c8000, 0x8edf40 };

/// print_strings inserts this string when the ROM yields 396 messages, so the
/// text file - and therefore the compiled asset - has 397.
pub const kExtraString = "[Speed 00]0- [Number 00]. 1- [Number 01][2]2- [Number 02]. 3- [Number 03]";

pub const Strings = struct {
    items: [][]u8,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *Strings) void {
        for (self.items) |s| self.alloc.free(s);
        self.alloc.free(self.items);
        self.* = undefined;
    }
};

/// Walks the packed dialogue and expands it into readable strings, the way
/// extract_resources does. Commands become bracketed names, dictionary
/// references become the text they stand for.
pub fn decodeStrings(alloc: std.mem.Allocator, rom: Rom) !Strings {
    var out: std.ArrayList([]u8) = .empty;
    errdefer {
        for (out.items) |s| alloc.free(s);
        out.deinit(alloc);
    }

    var p: u32 = kRomAddrs[0];
    var rom_idx: usize = 1;

    var s: std.ArrayList(u8) = .empty;
    defer s.deinit(alloc);

    while (true) {
        const c = rom.getByte(p);
        const l: u32 = if (c >= kCommandStart and c < kSwitchBank)
            tables.kCommandLengths[c - kCommandStart]
        else
            1;
        p += l;

        if (c == kEndMessage) {
            try out.append(alloc, try alloc.dupe(u8, s.items));
            s.clearRetainingCapacity();
            continue;
        }
        if (c < kCommandStart) {
            try s.appendSlice(alloc, tables.kAlphabet[c]);
        } else if (c < kSwitchBank) {
            const name = tables.kCommandNames[c - kCommandStart];
            try s.append(alloc, '[');
            try s.appendSlice(alloc, name);
            if (l == 2) {
                // The parameter is always printed as two decimal digits.
                const v = rom.getByte(p - 1);
                try s.append(alloc, ' ');
                try s.append(alloc, '0' + (v / 10) % 10);
                try s.append(alloc, '0' + v % 10);
            }
            try s.append(alloc, ']');
        } else if (c == kFinish) {
            break;
        } else if (c == kSwitchBank) {
            p = kRomAddrs[rom_idx];
            rom_idx += 1;
            s.clearRetainingCapacity();
        } else {
            try s.appendSlice(alloc, tables.kDictionary[c - kDictBase]);
        }
    }

    return .{ .items = try out.toOwnedSlice(alloc), .alloc = alloc };
}

fn alphabetIndex(token: []const u8) ?u8 {
    for (tables.kAlphabet, 0..) |a, i| {
        if (std.mem.eql(u8, a, token)) return @intCast(i);
    }
    return null;
}

/// Encodes one command back to its bytes. The US dialogue uses the original
/// scheme, where a command is its position in the name table offset by 0x67
/// and optionally one parameter byte.
fn encodeCommand(out: *std.ArrayList(u8), alloc: std.mem.Allocator, name: []const u8, param: ?u8) !void {
    for (tables.kCommandNames, 0..) |n, i| {
        if (!std.mem.eql(u8, n, name)) continue;
        const want: u8 = if (param == null) 1 else 2;
        if (tables.kCommandLengths[i] != want) return error.BadCommandParams;
        try out.append(alloc, @intCast(i + kCommandStart));
        if (param) |v| try out.append(alloc, v);
        return;
    }
    return error.UnknownCommand;
}

/// Compresses one string. At each position the dictionary is scanned in table
/// order and the first entry that fits wins - not the longest, which is why
/// the table's order cannot be rearranged.
fn compressString(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    var i: usize = 0;
    outer: while (i < s.len) {
        for (tables.kDictionary, 0..) |entry, idx| {
            if (entry.len == 0 or entry[0] != s[i]) continue;
            if (std.mem.startsWith(u8, s[i..], entry)) {
                try out.append(alloc, @intCast(idx + kDictBase));
                i += entry.len;
                continue :outer;
            }
        }

        if (s[i] == '[') {
            const close = std.mem.indexOfScalarPos(u8, s, i, ']') orelse return error.UnterminatedCommand;
            const inner = s[i + 1 .. close];
            const token = s[i .. i + inner.len + 2];

            // Some glyphs are spelled with brackets but are alphabet entries,
            // not commands, so those are checked first.
            if (alphabetIndex(token)) |idx| {
                try out.append(alloc, idx);
            } else if (std.mem.indexOfScalar(u8, inner, ' ')) |sp| {
                const param = try std.fmt.parseInt(u8, inner[sp + 1 ..], 10);
                try encodeCommand(&out, alloc, inner[0..sp], param);
            } else {
                try encodeCommand(&out, alloc, inner, null);
            }
            i += inner.len + 2;
        } else {
            const idx = alphabetIndex(s[i .. i + 1]) orelse return error.UnknownCharacter;
            try out.append(alloc, idx);
            i += 1;
        }
    }
    return out.toOwnedSlice(alloc);
}

fn freeSlices(alloc: std.mem.Allocator, xs: [][]u8) void {
    for (xs) |x| alloc.free(x);
    alloc.free(xs);
}

/// The dictionary as the game stores it: each entry spelled in alphabet
/// indices rather than characters.
fn encodeDictionary(alloc: std.mem.Allocator) ![][]u8 {
    const out = try alloc.alloc([]u8, tables.kDictionary.len);
    var done: usize = 0;
    errdefer {
        for (out[0..done]) |x| alloc.free(x);
        alloc.free(out);
    }
    for (tables.kDictionary, 0..) |entry, i| {
        const buf = try alloc.alloc(u8, entry.len);
        for (entry, 0..) |ch, k| buf[k] = alphabetIndex(entry[k .. k + 1]) orelse {
            alloc.free(buf);
            _ = ch;
            return error.UnknownCharacter;
        };
        out[i] = buf;
        done += 1;
    }
    return out;
}

/// Builds kDialogue: one entry per language, each holding the packed
/// dictionary and the packed messages.
pub fn buildDialogue(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    var strings = try decodeStrings(alloc, rom);
    defer strings.deinit();

    // Lay the messages out, inserting the synthetic one the Python adds.
    var texts: std.ArrayList([]const u8) = .empty;
    defer texts.deinit(alloc);
    try texts.appendSlice(alloc, strings.items);
    if (texts.items.len == 396) try texts.insert(alloc, 4, kExtraString);
    return buildDialogueFromTexts(alloc, texts.items);
}

/// kDialogue from messages already written out, as dialogue.txt holds them.
pub fn buildDialogueFromTexts(alloc: std.mem.Allocator, texts: []const []const u8) ![]u8 {
    const compressed = try alloc.alloc([]u8, texts.len);
    var done: usize = 0;
    defer {
        for (compressed[0..done]) |x| alloc.free(x);
        alloc.free(compressed);
    }
    for (texts, 0..) |t, i| {
        compressed[i] = try compressString(alloc, t);
        done += 1;
    }

    const dict = try encodeDictionary(alloc);
    defer freeSlices(alloc, dict);

    const dict_packed = try build_mod.packArrays(alloc, @ptrCast(dict));
    defer alloc.free(dict_packed);
    const msgs_packed = try build_mod.packArrays(alloc, @ptrCast(compressed));
    defer alloc.free(msgs_packed);

    const lang_entry = try build_mod.packArrays(alloc, &.{ dict_packed, msgs_packed });
    defer alloc.free(lang_entry);

    return build_mod.packArrays(alloc, &.{lang_entry});
}

/// kDialogueFont: the 256 glyph tiles and the width of each character.
///
/// The Python decodes the tiles into a PNG, reads it back and re-encodes
/// them, and measures each glyph's width from its pixels. Both come back as
/// what the ROM already holds, so this is the tiles and the width table
/// straight out of it.
pub fn buildDialogueFont(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    const tiles = try rom.getBytes(alloc, 0x8e8000, 256 * 16);
    defer alloc.free(tiles);
    const widths = try rom.getBytes(alloc, 0x8ecadf, 99);
    defer alloc.free(widths);

    const entry = try build_mod.packArrays(alloc, &.{ tiles, widths });
    defer alloc.free(entry);
    return build_mod.packArrays(alloc, &.{entry});
}

/// kDialogueMap: which language each dialogue and font entry belongs to. The
/// US build has one, with no flags - it uses the original command encoding
/// and is the language the ROM was read from.
pub fn buildDialogueMap(alloc: std.mem.Allocator) ![]u8 {
    const entry = try build_mod.packArrays(alloc, &.{ "us", &.{ 0, 0, 0 } });
    defer alloc.free(entry);
    return build_mod.packArrays(alloc, &.{entry});
}

const testing = std.testing;
const fileio = @import("fileio.zig");

test "the dialogue matches the reference asset file" {
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc") or !fileio.exists("zig-out/bin/zelda3_assets.dat"))
        return error.SkipZigTest;

    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();
    const dat = try fileio.readWholeFile(alloc, "zig-out/bin/zelda3_assets.dat");
    defer alloc.free(dat);
    var contents = try pack.read(alloc, dat);
    defer contents.deinit(alloc);

    const got = try buildDialogue(alloc, rom);
    defer alloc.free(got);
    try testing.expectEqualSlices(u8, contents.find("kDialogue").?, got);

    const font = try buildDialogueFont(alloc, rom);
    defer alloc.free(font);
    try testing.expectEqualSlices(u8, contents.find("kDialogueFont").?, font);

    const map = try buildDialogueMap(alloc);
    defer alloc.free(map);
    try testing.expectEqualSlices(u8, contents.find("kDialogueMap").?, map);
}
