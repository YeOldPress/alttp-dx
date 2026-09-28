//! The dialogue assets, for the US text and any translations built in beside
//! it.
//!
//! This is the one place where the old Python's intermediate file is not a
//! lossless view of the ROM. Extraction expands every dictionary reference
//! into the text it stands for, and compilation matches the dictionary again
//! from scratch - greedily, first entry in table order that fits. The result
//! is a valid but different encoding from the one in the ROM, which is why
//! kDialogue cannot be copied and this has to be a real port, quirks and all.
//!
//! Every language goes through the same code; asset_languages.zig says how
//! each one's ROM stores its text and which way commands get encoded again.

const std = @import("std");
const rom_mod = @import("rom.zig");
const pack = @import("asset_pack.zig");
const langs = @import("asset_languages.zig");
const build_mod = @import("asset_build.zig");

const Rom = rom_mod.Rom;
const Language = rom_mod.Language;
const Lang = langs.Lang;

const kEndMessage = 0x7f;

/// print_strings inserts this string when the ROM yields 396 messages, so the
/// text file - and therefore the compiled asset - has 397.
pub const kExtraString = "[Speed 00]0- [Number 00]. 1- [Number 01][2]2- [Number 02]. 3- [Number 03]";

/// The Portuguese translation has no end marker the decoder can find; it
/// stops after this many messages.
const kPortugueseMessages = 397;

pub const Strings = struct {
    items: [][]u8,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *Strings) void {
        for (self.items) |s| self.alloc.free(s);
        self.alloc.free(self.items);
        self.* = undefined;
    }
};

/// The file a language's dialogue is kept in: dialogue.txt for the US text,
/// dialogue_xx.txt for the rest.
pub fn fileName(buf: []u8, lang: Language) []const u8 {
    if (lang == .us) return "dialogue.txt";
    return std.fmt.bufPrint(buf, "dialogue_{s}.txt", .{@tagName(lang)}) catch unreachable;
}

/// Walks the packed dialogue and expands it into readable strings, the way
/// extract_resources does. Commands become bracketed names, dictionary
/// references become the text they stand for.
pub fn decodeStrings(alloc: std.mem.Allocator, rom: Rom, lang: Language) !Strings {
    const info = langs.get(lang);
    var out: std.ArrayList([]u8) = .empty;
    errdefer {
        for (out.items) |s| alloc.free(s);
        out.deinit(alloc);
    }

    var p: u32 = info.rom_addrs[0];
    var rom_idx: usize = 1;

    var s: std.ArrayList(u8) = .empty;
    defer s.deinit(alloc);

    while (true) {
        const c = rom.getByte(p);
        const l: u32 = if (c >= info.command_start and c < info.switch_bank)
            info.command_lengths[c - info.command_start]
        else
            1;
        p += l;

        if (c == kEndMessage) {
            try out.append(alloc, try alloc.dupe(u8, s.items));
            s.clearRetainingCapacity();
            if (lang == .pt and out.items.len >= kPortugueseMessages) break;
            continue;
        }
        if (c < info.command_start) {
            var ch = c;
            if (info.escape != null and c == info.escape.?) {
                ch = rom.getByte(p);
                p += 1;
            }
            if (ch >= info.alphabet.len) return error.BadDialogue;
            try s.appendSlice(alloc, info.alphabet[ch]);
        } else if (c < info.switch_bank) {
            const name = info.command_names[c - info.command_start];
            if (l == 2) {
                // The parameter is printed with at least two digits.
                var buf: [24]u8 = undefined;
                try s.appendSlice(alloc, try std.fmt.bufPrint(&buf, "[{s} {d:0>2}]", .{ name, rom.getByte(p - 1) }));
            } else {
                try s.append(alloc, '[');
                try s.appendSlice(alloc, name);
                try s.append(alloc, ']');
            }
        } else if (c == info.finish) {
            break;
        } else if (c == info.switch_bank) {
            if (rom_idx >= info.rom_addrs.len) return error.BadDialogue;
            p = info.rom_addrs[rom_idx];
            rom_idx += 1;
            s.clearRetainingCapacity();
        } else if (c < info.switch_bank + 8) {
            // Only the Portuguese translation has these, and they print
            // nothing.
            if (lang != .pt) return error.BadDialogue;
        } else {
            const idx = c - info.dict_base_dec;
            if (idx >= info.dictionary.len) return error.BadDialogue;
            try s.appendSlice(alloc, info.dictionary[idx]);
        }
    }

    return .{ .items = try out.toOwnedSlice(alloc), .alloc = alloc };
}

/// The dialogue file for a language, "number: text" a line, as
/// extract_resources wrote it.
pub fn dialogueText(alloc: std.mem.Allocator, rom: Rom, lang: Language) ![]u8 {
    var strings = try decodeStrings(alloc, rom, lang);
    defer strings.deinit();
    var texts: std.ArrayList([]const u8) = .empty;
    defer texts.deinit(alloc);
    try texts.appendSlice(alloc, strings.items);
    if (texts.items.len == 396) try texts.insert(alloc, 4, kExtraString);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    for (texts.items, 1..) |t, n| {
        var buf: [16]u8 = undefined;
        try out.appendSlice(alloc, try std.fmt.bufPrint(&buf, "{d}: ", .{n}));
        try out.appendSlice(alloc, t);
        try out.append(alloc, '\n');
    }
    return out.toOwnedSlice(alloc);
}

// ------------------------------------------------------------ compression

/// Why a message couldn't be compressed, for the person who wrote it.
pub const Diag = struct {
    lang: Language = .us,
    /// 1-based, as the file numbers them.
    message: usize = 0,
    buf: [160]u8 = undefined,
    len: usize = 0,

    pub fn text(self: *const Diag) []const u8 {
        return self.buf[0..self.len];
    }

    fn set(self: *Diag, comptime fmt: []const u8, args: anytype) error{BadDialogue} {
        const written: []const u8 = std.fmt.bufPrint(&self.buf, fmt, args) catch &self.buf;
        self.len = written.len;
        return error.BadDialogue;
    }
};

/// The alphabet entry a token prints as. When a token is in the alphabet
/// twice the later one wins, as it did in the old Python's lookup table.
fn alphabetIndex(info: *const Lang, token: []const u8) ?u8 {
    var i = info.alphabet.len;
    while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, info.alphabet[i], token)) return @intCast(i);
    }
    return null;
}

/// The dictionary reference the compressor emits at the start of `rest`, if
/// any. The old Python kept the dictionary in a dict, which gives two quirks
/// worth keeping: entries are tried in table order, first fit winning, and
/// an entry listed twice is tried where it first appears but encoded as the
/// later index.
fn dictionaryMatch(info: *const Lang, rest: []const u8) ?struct { byte: u8, len: usize } {
    for (info.dictionary, 0..) |entry, i| {
        if (!std.mem.startsWith(u8, rest, entry)) continue;
        var first = true;
        for (info.dictionary[0..i]) |earlier| {
            if (std.mem.eql(u8, earlier, entry)) first = false;
        }
        if (!first) continue;
        var last = i;
        for (info.dictionary[i + 1 ..], i + 1..) |later, j| {
            if (std.mem.eql(u8, later, entry)) last = j;
        }
        return .{ .byte = @intCast(last + info.dict_base_enc), .len = entry.len };
    }
    return null;
}

/// The original encoding: a command is its place in the US name table plus
/// 0x67, and one parameter byte if it takes one.
fn encodeOrg(out: *std.ArrayList(u8), alloc: std.mem.Allocator, diag: *Diag, name: []const u8, param: ?u8) !void {
    const us = langs.get(.us);
    for (us.command_names, 0..) |n, i| {
        if (!std.mem.eql(u8, n, name)) continue;
        const want: u8 = if (param == null) 1 else 2;
        if (us.command_lengths[i] != want) {
            return diag.set("[{s}] {s}", .{ name, if (param == null) "needs a number" else "doesn't take a number" });
        }
        try out.append(alloc, @intCast(i + us.command_start));
        if (param) |v| try out.append(alloc, v);
        return;
    }
    return diag.set("unknown command [{s}]", .{name});
}

/// The newer encoding German, French and Portuguese use: a handful of
/// one-byte commands, and the rest as 0x87 and a byte saying which.
fn encodeNew(out: *std.ArrayList(u8), alloc: std.mem.Allocator, diag: *Diag, name: []const u8, param: ?u8) !void {
    const Simple = struct { name: []const u8, bytes: []const u8 };
    const simple = [_]Simple{
        .{ .name = "Scroll", .bytes = &.{0x80} },          .{ .name = "Waitkey", .bytes = &.{0x81} },
        .{ .name = "1", .bytes = &.{0x82} },               .{ .name = "2", .bytes = &.{0x83} },
        .{ .name = "3", .bytes = &.{0x84} },               .{ .name = "Name", .bytes = &.{0x85} },
        .{ .name = "Choose", .bytes = &.{ 0x87, 0x80 } },  .{ .name = "Choose2", .bytes = &.{ 0x87, 0x81 } },
        .{ .name = "Choose3", .bytes = &.{ 0x87, 0x82 } }, .{ .name = "Selchg", .bytes = &.{ 0x87, 0x83 } },
        .{ .name = "Item", .bytes = &.{ 0x87, 0x84 } },    .{ .name = "NextPic", .bytes = &.{ 0x87, 0x85 } },
    };
    for (simple) |s| {
        if (!std.mem.eql(u8, s.name, name)) continue;
        if (param != null) return diag.set("[{s}] doesn't take a number", .{name});
        return out.appendSlice(alloc, s.bytes);
    }

    // Commands with a number: a 0-15 range, or a few values each.
    const Ranged = struct { name: []const u8, base: u8 };
    const ranged = [_]Ranged{ .{ .name = "Wait", .base = 0x00 }, .{ .name = "Color", .base = 0x10 }, .{ .name = "Number", .base = 0x20 }, .{ .name = "Speed", .base = 0x30 } };
    for (ranged) |r| {
        if (!std.mem.eql(u8, r.name, name)) continue;
        const v = param orelse return diag.set("[{s}] needs a number", .{name});
        if (v > 15) return diag.set("[{s} {d}]: the number has to be 0 to 15", .{ name, v });
        return out.appendSlice(alloc, &.{ 0x87, r.base + v });
    }
    // null means the command is dropped: this encoding has no room for it.
    const Choice = struct { param: u8, byte: ?u8 };
    const Listed = struct { name: []const u8, choices: []const Choice };
    const listed = [_]Listed{
        .{ .name = "Sound", .choices = &.{ .{ .param = 45, .byte = 0x40 }, .{ .param = 64, .byte = null } } },
        .{ .name = "Window", .choices = &.{ .{ .param = 0, .byte = null }, .{ .param = 2, .byte = 0x86 } } },
        .{ .name = "Position", .choices = &.{ .{ .param = 0, .byte = 0x87 }, .{ .param = 1, .byte = 0x88 } } },
        .{ .name = "ScrollSpd", .choices = &.{.{ .param = 0, .byte = null }} },
    };
    for (listed) |l| {
        if (!std.mem.eql(u8, l.name, name)) continue;
        const v = param orelse return diag.set("[{s}] needs a number", .{name});
        for (l.choices) |ch| {
            if (ch.param != v) continue;
            if (ch.byte) |b| try out.appendSlice(alloc, &.{ 0x87, b });
            return;
        }
        return diag.set("[{s} {d}] isn't a value this language can use", .{ name, v });
    }
    return diag.set("unknown command [{s}]", .{name});
}

/// Compresses one message.
fn compressString(alloc: std.mem.Allocator, info: *const Lang, s: []const u8, diag: *Diag) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    var i: usize = 0;
    while (i < s.len) {
        const rest = s[i..];
        if (dictionaryMatch(info, rest)) |m| {
            try out.append(alloc, m.byte);
            i += m.len;
            continue;
        }

        if (rest[0] == '[') {
            const close = std.mem.indexOfScalar(u8, rest, ']') orelse return diag.set("a '[' with no ']' after it", .{});
            const inner = rest[1..close];
            const token = rest[0 .. close + 1];

            // Some glyphs are spelled with brackets but are alphabet entries,
            // not commands, so those are checked first.
            if (alphabetIndex(info, token)) |idx| {
                try out.append(alloc, idx);
            } else {
                var name = inner;
                var param: ?u8 = null;
                if (std.mem.indexOfScalar(u8, inner, ' ')) |sp| {
                    name = inner[0..sp];
                    const digits = std.mem.trim(u8, inner[sp + 1 ..], " ");
                    param = std.fmt.parseInt(u8, digits, 10) catch return diag.set("[{s}]: '{s}' isn't a number from 0 to 255", .{ inner, digits });
                }
                switch (info.encoder) {
                    .org => try encodeOrg(&out, alloc, diag, name, param),
                    .new => try encodeNew(&out, alloc, diag, name, param),
                }
            }
            i += token.len;
        } else {
            const n = std.unicode.utf8ByteSequenceLength(rest[0]) catch 1;
            const ch = rest[0..@min(n, rest.len)];
            const idx = alphabetIndex(info, ch) orelse return diag.set("'{s}' isn't in this language's font", .{ch});
            try out.append(alloc, idx);
            i += ch.len;
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
fn encodeDictionary(alloc: std.mem.Allocator, info: *const Lang) ![][]u8 {
    const out = try alloc.alloc([]u8, info.dictionary.len);
    var done: usize = 0;
    errdefer {
        for (out[0..done]) |x| alloc.free(x);
        alloc.free(out);
    }
    for (info.dictionary, 0..) |entry, i| {
        var bytes: std.ArrayList(u8) = .empty;
        errdefer bytes.deinit(alloc);
        var it = std.unicode.Utf8View.initUnchecked(entry).iterator();
        while (it.nextCodepointSlice()) |ch| {
            try bytes.append(alloc, alphabetIndex(info, ch) orelse return error.UnknownCharacter);
        }
        out[i] = try bytes.toOwnedSlice(alloc);
        done += 1;
    }
    return out;
}

/// One language's entry in kDialogue: its packed dictionary and its packed
/// messages.
fn languageEntry(alloc: std.mem.Allocator, lang: Language, texts: []const []const u8, diag: *Diag) ![]u8 {
    const info = langs.get(lang);
    const compressed = try alloc.alloc([]u8, texts.len);
    var done: usize = 0;
    defer {
        for (compressed[0..done]) |x| alloc.free(x);
        alloc.free(compressed);
    }
    for (texts, 0..) |t, i| {
        diag.lang = lang;
        diag.message = i + 1;
        compressed[i] = try compressString(alloc, info, t, diag);
        done += 1;
    }

    const dict = try encodeDictionary(alloc, info);
    defer freeSlices(alloc, dict);

    const dict_packed = try build_mod.packArrays(alloc, @ptrCast(dict));
    defer alloc.free(dict_packed);
    const msgs_packed = try build_mod.packArrays(alloc, @ptrCast(compressed));
    defer alloc.free(msgs_packed);
    return build_mod.packArrays(alloc, &.{ dict_packed, msgs_packed });
}

/// One language's text and font, ready to build.
pub const Input = struct {
    lang: Language,
    texts: []const []const u8,
    font_tiles: []const u8,
    font_widths: []const u8,
};

pub const Built = struct {
    dialogue: []u8,
    font: []u8,
    map: []u8,

    pub fn deinit(self: *Built, alloc: std.mem.Allocator) void {
        alloc.free(self.dialogue);
        alloc.free(self.font);
        alloc.free(self.map);
        self.* = undefined;
    }
};

/// kDialogue, kDialogueFont and kDialogueMap for a set of languages, US
/// first. The map tells the game each language's name, which dialogue and
/// font entry is its, and two flags: 1 for the newer command encoding, 2 for
/// text that didn't come from the ROM the game runs.
pub fn buildLanguages(alloc: std.mem.Allocator, list: []const Input, diag: *Diag) !Built {
    var dialogue: std.ArrayList([]u8) = .empty;
    var fonts: std.ArrayList([]u8) = .empty;
    var maps: std.ArrayList([]u8) = .empty;
    defer {
        for ([_]*std.ArrayList([]u8){ &dialogue, &fonts, &maps }) |l| {
            for (l.items) |x| alloc.free(x);
            l.deinit(alloc);
        }
    }
    for (list, 0..) |l, i| {
        try dialogue.append(alloc, try languageEntry(alloc, l.lang, l.texts, diag));
        try fonts.append(alloc, try build_mod.packArrays(alloc, &.{ l.font_tiles, l.font_widths }));
        var flags: u8 = if (langs.get(l.lang).encoder == .new) 1 else 0;
        if (i != 0) flags |= 2;
        const idx: u8 = @intCast(i);
        try maps.append(alloc, try build_mod.packArrays(alloc, &.{ langs.get(l.lang).code, &.{ idx, idx, flags } }));
    }
    const d = try build_mod.packArrays(alloc, @ptrCast(dialogue.items));
    errdefer alloc.free(d);
    const f = try build_mod.packArrays(alloc, @ptrCast(fonts.items));
    errdefer alloc.free(f);
    return .{ .dialogue = d, .font = f, .map = try build_mod.packArrays(alloc, @ptrCast(maps.items)) };
}

/// The US font straight out of the ROM. The old Python decodes the tiles into a
/// PNG, reads it back and re-encodes them, and measures each glyph's width
/// from its pixels; both come back as what the ROM already holds.
pub fn romFont(alloc: std.mem.Allocator, rom: Rom) !struct { tiles: []u8, widths: []u8 } {
    const tiles = try rom.getBytes(alloc, 0x8e8000, 256 * 16);
    errdefer alloc.free(tiles);
    return .{ .tiles = tiles, .widths = try rom.getBytes(alloc, 0x8ecadf, 99) };
}

/// The US messages in the ROM, laid out as dialogue.txt has them.
pub fn romTexts(alloc: std.mem.Allocator, rom: Rom) !Strings {
    var strings = try decodeStrings(alloc, rom, .us);
    errdefer strings.deinit();
    if (strings.items.len == 396) {
        var list = std.ArrayList([]u8).fromOwnedSlice(strings.items);
        try list.insert(alloc, 4, try alloc.dupe(u8, kExtraString));
        strings.items = try list.toOwnedSlice(alloc);
    }
    return strings;
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

    var texts = try romTexts(alloc, rom);
    defer texts.deinit();
    const font = try romFont(alloc, rom);
    defer alloc.free(font.tiles);
    defer alloc.free(font.widths);
    var diag = Diag{};
    var built = try buildLanguages(alloc, &.{.{ .lang = .us, .texts = @ptrCast(texts.items), .font_tiles = font.tiles, .font_widths = font.widths }}, &diag);
    defer built.deinit(alloc);
    try testing.expectEqualSlices(u8, contents.find("kDialogue").?, built.dialogue);
    try testing.expectEqualSlices(u8, contents.find("kDialogueFont").?, built.font);
    try testing.expectEqualSlices(u8, contents.find("kDialogueMap").?, built.map);
}

test "a duplicated dictionary entry is tried first but encoded last" {
    // Swedish lists "en " twice; the old Python's dict kept the first slot in
    // the lookup order and the second index.
    const m = dictionaryMatch(langs.get(.sv), "en tur").?;
    const info = langs.get(.sv);
    try testing.expectEqualStrings("en ", info.dictionary[m.byte - info.dict_base_enc]);
    try testing.expect(m.byte - info.dict_base_enc > 10);
}

test "a bad command says what's wrong with it" {
    var diag = Diag{};
    try testing.expectError(error.BadDialogue, compressString(testing.allocator, langs.get(.de), "Hallo [Sound 3]", &diag));
    try testing.expectEqualStrings("[Sound 3] isn't a value this language can use", diag.text());
}
