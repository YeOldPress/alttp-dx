//! The start menu's names for a pad's buttons, in the pad's own words: ✕ ○
//! □ △ on a PlayStation pad, L1 and Options rather than LB and Start, and
//! the letters a Nintendo pad has printed where they're printed. With no pad
//! plugged in, the hints name only the keys.
//!
//! The menu's own hints name a button by what it does there, which the menu
//! routes by the label printed on it (menu_kit.faceAction): the A in
//! "A / Enter" is whichever button says A, or ✕. The game's controls name
//! one by where it sits, Xbox letters for the four places (config.zig): its
//! "A" is the bottom button, which says B on a Nintendo pad. So there are
//! two ways in, one for each.
//!
//! The four PlayStation shapes travel inside the strings as the bytes 1 to
//! 4, for start_page to draw, the fonts having no such glyphs.
const std = @import("std");
const c = @import("sdl.zig").c;

pub const kCross = "\x01";
pub const kCircle = "\x02";
pub const kSquare = "\x03";
pub const kTriangle = "\x04";

/// What a face button has printed on it.
pub const Face = enum { a, b, x, y, cross, circle, square, triangle, unknown };

pub const Style = enum { keyboard, xbox, playstation, nintendo, generic };

/// The pad the menu's hints are for, set by the menu as pads come, go and
/// are pressed.
pub var current: Names = .{};

/// The pad the hints are for.
pub const Names = struct {
    style: Style = .keyboard,
    /// The labels at the bottom, right, left and top, in that order.
    faces: [4]Face = .{ .a, .b, .x, .y },

    /// The pad as SDL sees it.
    pub fn of(pad: ?*c.SDL_Gamepad) Names {
        const p = pad orelse return .{};
        var n = Names{};
        const places = [4]c_int{ c.SDL_GAMEPAD_BUTTON_SOUTH, c.SDL_GAMEPAD_BUTTON_EAST, c.SDL_GAMEPAD_BUTTON_WEST, c.SDL_GAMEPAD_BUTTON_NORTH };
        for (places, 0..) |b, i| {
            n.faces[i] = switch (c.SDL_GetGamepadButtonLabel(p, @intCast(b))) {
                c.SDL_GAMEPAD_BUTTON_LABEL_A => .a,
                c.SDL_GAMEPAD_BUTTON_LABEL_B => .b,
                c.SDL_GAMEPAD_BUTTON_LABEL_X => .x,
                c.SDL_GAMEPAD_BUTTON_LABEL_Y => .y,
                c.SDL_GAMEPAD_BUTTON_LABEL_CROSS => .cross,
                c.SDL_GAMEPAD_BUTTON_LABEL_CIRCLE => .circle,
                c.SDL_GAMEPAD_BUTTON_LABEL_SQUARE => .square,
                c.SDL_GAMEPAD_BUTTON_LABEL_TRIANGLE => .triangle,
                else => .unknown,
            };
        }
        // Where a label couldn't be had, the Xbox letter for the place.
        const fallback = [4]Face{ .a, .b, .x, .y };
        for (&n.faces, fallback) |*f, d| {
            if (f.* == .unknown) f.* = d;
        }
        n.style = switch (c.SDL_GetGamepadType(p)) {
            c.SDL_GAMEPAD_TYPE_XBOX360, c.SDL_GAMEPAD_TYPE_XBOXONE => .xbox,
            c.SDL_GAMEPAD_TYPE_PS3, c.SDL_GAMEPAD_TYPE_PS4, c.SDL_GAMEPAD_TYPE_PS5 => .playstation,
            c.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO,
            c.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT,
            c.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT,
            c.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR,
            => .nintendo,
            else => if (n.faces[0] == .cross) .playstation else .generic,
        };
        return n;
    }

    /// A hint's key, "A / Enter" or "L R / [ ]": the pad's half in the
    /// pad's own names, or only the keyboard's with no pad. A key that's
    /// only the pad's ("Start") is renamed; anything else is left alone.
    pub fn hint(self: Names, key: []const u8, buf: []u8) []const u8 {
        const sep = " / ";
        const at = std.mem.indexOf(u8, key, sep);
        const pad_part = if (at) |i| key[0..i] else key;
        if (at == null and !self.isPadWord(pad_part)) return key;
        if (self.style == .keyboard) return if (at) |i| key[i + sep.len ..] else key;
        var w = std.Io.Writer.fixed(buf);
        var it = std.mem.tokenizeScalar(u8, pad_part, ' ');
        var first = true;
        while (it.next()) |tok| {
            if (!first) w.writeAll(" ") catch return key;
            first = false;
            w.writeAll(self.hintWord(tok)) catch return key;
        }
        if (at) |i| w.writeAll(key[i..]) catch return key;
        return w.buffered();
    }

    fn isPadWord(self: Names, word: []const u8) bool {
        _ = self;
        return std.mem.eql(u8, word, "Start");
    }

    /// One button of a hint, by what it does: A confirms, B goes back, X
    /// saves and Y tells more, whatever's printed on the pad.
    fn hintWord(self: Names, word: []const u8) []const u8 {
        const ps = self.style == .playstation;
        if (word.len == 1) switch (word[0]) {
            'A' => return if (ps) kCross else "A",
            'B' => return if (ps) kCircle else "B",
            'X' => return if (ps) kSquare else "X",
            'Y' => return if (ps) kTriangle else "Y",
            'L' => return self.shoulder(false),
            'R' => return self.shoulder(true),
            else => {},
        };
        if (std.mem.eql(u8, word, "Start")) return self.start();
        return word;
    }

    fn shoulder(self: Names, right: bool) []const u8 {
        return switch (self.style) {
            .xbox => if (right) "RB" else "LB",
            .playstation => if (right) "R1" else "L1",
            .keyboard, .nintendo, .generic => if (right) "R" else "L",
        };
    }

    fn start(self: Names) []const u8 {
        return switch (self.style) {
            .playstation => "Options",
            .nintendo => "+",
            .keyboard, .xbox, .generic => "Start",
        };
    }

    /// The button that picks things, for a sentence: "press A", "press ✕",
    /// or with no pad, "press Enter".
    pub fn confirm(self: Names) []const u8 {
        return switch (self.style) {
            .keyboard => "Enter",
            .playstation => kCross,
            else => "A",
        };
    }

    /// The retro menu's footer, all capitals in the 8x8 font: "A/ENTER"
    /// becomes "✕/ENTER" on a PlayStation pad (menu_kit draws the shapes in
    /// pixels to match), and "ENTER" with no pad; START becomes OPTIONS, or
    /// +. A lone pad letter ("BACK B") is renamed, or with no pad becomes
    /// its key.
    pub fn retro(self: Names, text: []const u8, buf: []u8) []const u8 {
        var w = std.Io.Writer.fixed(buf);
        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == ' ') {
                w.writeByte(' ') catch return text;
                i += 1;
                continue;
            }
            const end = std.mem.indexOfScalarPos(u8, text, i, ' ') orelse text.len;
            w.writeAll(self.retroWord(text[i..end])) catch return text;
            if (std.mem.indexOfScalar(u8, text[i..end], '/')) |slash| {
                const pad = text[i .. i + slash];
                if (retroLetter(pad) != null) {
                    if (self.style != .keyboard) w.writeByte('/') catch return text;
                    w.writeAll(text[i + slash + 1 .. end]) catch return text;
                }
            }
            i = end;
        }
        return w.buffered();
    }

    fn retroWord(self: Names, word: []const u8) []const u8 {
        const slash = std.mem.indexOfScalar(u8, word, '/');
        const pad = if (slash) |sl| word[0..sl] else word;
        if (retroLetter(pad)) |k| {
            const lone = slash == null;
            if (self.style == .keyboard) return if (lone) switch (k) {
                0 => "ENTER",
                1 => "ESC",
                2 => "S",
                else => "I",
            } else "";
            if (self.style == .playstation) return ([_][]const u8{ kCross, kCircle, kSquare, kTriangle })[k];
            return pad;
        }
        if (slash != null) return word;
        if (std.mem.eql(u8, word, "START")) return switch (self.style) {
            .playstation => "OPTIONS",
            .nintendo => "+",
            else => word,
        };
        return word;
    }

    /// A button of the game's controls, as controls.padLabel names it (by
    /// place: "A" is the bottom one), in what the pad has printed there.
    pub fn place(self: Names, label: []const u8) []const u8 {
        if (self.style == .keyboard) return label;
        const places = [_][]const u8{ "A", "B", "X", "Y" };
        for (places, 0..) |pl, i| {
            if (std.mem.eql(u8, label, pl)) return faceName(self.faces[i]);
        }
        const Rename = struct { from: []const u8, ps: []const u8, nin: []const u8, gen: []const u8 };
        const kRenames = [_]Rename{
            .{ .from = "LB", .ps = "L1", .nin = "L", .gen = "L" },
            .{ .from = "RB", .ps = "R1", .nin = "R", .gen = "R" },
            .{ .from = "LT", .ps = "L2", .nin = "ZL", .gen = "LT" },
            .{ .from = "RT", .ps = "R2", .nin = "ZR", .gen = "RT" },
            .{ .from = "LS", .ps = "L3", .nin = "LS", .gen = "LS" },
            .{ .from = "RS", .ps = "R3", .nin = "RS", .gen = "RS" },
            .{ .from = "Back", .ps = "Share", .nin = "-", .gen = "Select" },
            .{ .from = "Start", .ps = "Options", .nin = "+", .gen = "Start" },
            .{ .from = "Guide", .ps = "PS", .nin = "Home", .gen = "Guide" },
        };
        for (kRenames) |r| {
            if (!std.mem.eql(u8, label, r.from)) continue;
            return switch (self.style) {
                .playstation => r.ps,
                .nintendo => r.nin,
                .generic => r.gen,
                .keyboard, .xbox => label,
            };
        }
        return label;
    }
};

/// Which of A, B, X and Y a retro footer's word is, if it's one.
fn retroLetter(word: []const u8) ?usize {
    if (word.len != 1) return null;
    return switch (word[0]) {
        'A' => 0,
        'B' => 1,
        'X' => 2,
        'Y' => 3,
        else => null,
    };
}

fn faceName(f: Face) []const u8 {
    return switch (f) {
        .a, .unknown => "A",
        .b => "B",
        .x => "X",
        .y => "Y",
        .cross => kCross,
        .circle => kCircle,
        .square => kSquare,
        .triangle => kTriangle,
    };
}

/// Whether `ch` is one of the shapes standing in a string.
pub fn isShape(ch: u8) bool {
    return ch >= 1 and ch <= 4;
}

const testing = std.testing;

test "with no pad, the hints name only the keys" {
    const n = Names{};
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("Enter", n.hint("A / Enter", &buf));
    try testing.expectEqualStrings("[ ]", n.hint("L R / [ ]", &buf));
    try testing.expectEqualStrings("Wheel", n.hint("Wheel", &buf));
    try testing.expectEqualStrings("Start", n.hint("Start", &buf));
    try testing.expectEqualStrings("A", n.place("A"));
}

test "a PlayStation pad gets its shapes and its own names" {
    const n = Names{ .style = .playstation, .faces = .{ .cross, .circle, .square, .triangle } };
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings(kCross ++ " / Enter", n.hint("A / Enter", &buf));
    try testing.expectEqualStrings("L1 R1 / [ ]", n.hint("L R / [ ]", &buf));
    try testing.expectEqualStrings("Options", n.hint("Start", &buf));
    try testing.expectEqualStrings(kTriangle, n.place("Y"));
    try testing.expectEqualStrings("L2", n.place("LT"));
    try testing.expectEqualStrings("\xe2\x86\x91 \xe2\x86\x93", n.hint("\xe2\x86\x91 \xe2\x86\x93", &buf));
}

test "a Nintendo pad keeps its letters for the hints and swaps them by place" {
    const n = Names{ .style = .nintendo, .faces = .{ .b, .a, .y, .x } };
    var buf: [32]u8 = undefined;
    // A confirms in the menu whichever side it's on.
    try testing.expectEqualStrings("A / Enter", n.hint("A / Enter", &buf));
    try testing.expectEqualStrings("+", n.hint("Start", &buf));
    // The game's "A" is the bottom button, which says B.
    try testing.expectEqualStrings("B", n.place("A"));
    try testing.expectEqualStrings("A", n.place("B"));
    try testing.expectEqualStrings("ZR", n.place("RT"));
}

test "an Xbox pad reads as the hints are written" {
    const n = Names{ .style = .xbox };
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("X / S", n.hint("X / S", &buf));
    try testing.expectEqualStrings("LB RB / [ ]", n.hint("L R / [ ]", &buf));
    try testing.expectEqualStrings("RB", n.place("RB"));
}

test "the retro footer is renamed word by word" {
    var buf: [64]u8 = undefined;
    const ps = Names{ .style = .playstation, .faces = .{ .cross, .circle, .square, .triangle } };
    try testing.expectEqualStrings("SELECT " ++ kCross ++ "/ENTER   SAVE " ++ kSquare ++ "/S", ps.retro("SELECT A/ENTER   SAVE X/S", &buf));
    try testing.expectEqualStrings("PLAY OPTIONS  SAVE " ++ kSquare ++ "/S  BACK " ++ kCircle, ps.retro("PLAY START  SAVE X/S  BACK B", &buf));
    const none = Names{};
    try testing.expectEqualStrings("SELECT ENTER   SAVE S", none.retro("SELECT A/ENTER   SAVE X/S", &buf));
    try testing.expectEqualStrings("PLAY START  SAVE S  BACK ESC", none.retro("PLAY START  SAVE X/S  BACK B", &buf));
    try testing.expectEqualStrings("PRESS ANY KEY OR PAD BUTTON", none.retro("PRESS ANY KEY OR PAD BUTTON", &buf));
    const nin = Names{ .style = .nintendo, .faces = .{ .b, .a, .y, .x } };
    try testing.expectEqualStrings("INFO Y/I   BACK B/ESC", nin.retro("INFO Y/I   BACK B/ESC", &buf));
    try testing.expectEqualStrings("PLAY +", nin.retro("PLAY START", &buf));
}
