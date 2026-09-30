//! The start menu: settings, the ROM and the asset file, before the game.
//!
//! Reads zelda3.ini, lets the options be changed with a keyboard, a gamepad or
//! a mouse, and writes the file back. The ini is edited a line at a time rather
//! than reparsed and regenerated, so the comments that document each option
//! survive a round trip. It runs in its own window before the game sets up its
//! renderer, then gets out of the way, all in the one process.
//!
//! Drawing uses SDL3's built in 8x8 font (SDL_RenderDebugText), so the menu
//! needs no font file and no toolkit - just the SDL the game already links.
const std = @import("std");
const builtin = @import("builtin");
const fileio = @import("fileio.zig");
const rom_mod = @import("rom.zig");
const asset_all = @import("asset_all.zig");
const c = @import("sdl.zig").c;
const seed_info = @import("seed_info.zig");
const config = @import("config.zig");
const controls = @import("controls.zig");
const pad_art = @import("pad_art.zig");

/// The zelda3.ini this build shipped with, written out whenever there is no
/// ini to be found, so a fresh folder or data directory still starts.
const kDefaultIni = @import("default_ini").text;

const kRomPath = "zelda3.sfc";
const kAssetsPath = "zelda3_assets.dat";

const kWindowW = 640;
const kWindowH = 480;
/// The debug font is 8x8; everything is laid out in these scaled cells.
const kScale = 2;
const kCell = 8 * kScale;
const kRowH = kCell + 4;
/// Rows of the settings list on screen at once.
const kVisibleRows = 14;

// A Link to the Past's menu palette: a dark green ground, a gold frame with a
// lighter top edge and a darker underside, and off-white text.
const Rgb = struct { r: u8, g: u8, b: u8 };
const kColorBg = Rgb{ .r = 0x18, .g = 0x38, .b = 0x20 };
const kColorPanel = Rgb{ .r = 0x00, .g = 0x00, .b = 0x00 };
const kColorFrame = Rgb{ .r = 0xb8, .g = 0x78, .b = 0x38 };
const kColorFrameHi = Rgb{ .r = 0xf8, .g = 0xd8, .b = 0x78 };
const kColorFrameLo = Rgb{ .r = 0x68, .g = 0x48, .b = 0x18 };
const kColorText = Rgb{ .r = 0xf8, .g = 0xf8, .b = 0xf8 };
const kColorTextDim = Rgb{ .r = 0x88, .g = 0x98, .b = 0x88 };
const kColorValue = Rgb{ .r = 0x90, .g = 0xc0, .b = 0xf8 };
const kColorSelect = Rgb{ .r = 0xf8, .g = 0xd8, .b = 0x78 };
const kColorRowHi = Rgb{ .r = 0x28, .g = 0x28, .b = 0x50 };
const kColorLaunchBg = Rgb{ .r = 0x00, .g = 0xe0, .b = 0x18 };
const kColorLaunchText = Rgb{ .r = 0x00, .g = 0x18, .b = 0x00 };
const kColorOk = Rgb{ .r = 0x78, .g = 0xe0, .b = 0x88 };
const kColorWarn = Rgb{ .r = 0xf8, .g = 0xc0, .b = 0x58 };
const kColorSection = Rgb{ .r = 0x78, .g = 0xd8, .b = 0x98 };
const kColorRandoBg = Rgb{ .r = 0x58, .g = 0x38, .b = 0xb0 };
const kColorDisabledBg = Rgb{ .r = 0x30, .g = 0x34, .b = 0x3c };

// ---------------------------------------------------------------- settings

/// How a setting's value is presented and cycled.
/// A fixed set of values, and optionally what to call them.
///
/// The file's spelling is not always meant for people to read - Fullscreen is
/// stored as 0, 1 or 2 - so `labels` gives each value a name to show instead.
/// Leave it empty and the value is shown as written.
pub const Choice = struct {
    values: []const []const u8,
    labels: []const []const u8 = &.{},

    fn labelFor(self: Choice, value: []const u8) []const u8 {
        if (self.labels.len == 0) return value;
        for (self.values, 0..) |v, i| {
            if (std.ascii.eqlIgnoreCase(v, value) and i < self.labels.len) return self.labels[i];
        }
        return value;
    }
};

pub const Kind = union(enum) {
    /// 0 or 1, shown as OFF / ON.
    toggle,
    /// One of a fixed set of spellings, cycled in order.
    choice: Choice,
    /// A whole number, nudged by `step` and clamped to the range. `suffix` is
    /// kept on the value when written back, for entries like "100%".
    number: struct { min: i32, max: i32, step: i32, suffix: []const u8 = "" },
    /// Shown but not editable here: free text that wants a keyboard, or a
    /// binding list that wants a capture UI.
    text,
};

pub const Setting = struct {
    section: []const u8,
    key: []const u8,
    label: []const u8,
    kind: Kind,
    /// A line shown under the list while the setting is selected, for what
    /// the label can't say: that something is experimental, or a spoiler.
    note: []const u8 = "",
};

/// A heading row in the list. Not a setting; drawn differently and skipped
/// when the cursor moves.
const kSectionMark = "\x00SECTION";

pub const kSettings = [_]Setting{
    .{ .section = kSectionMark, .key = "", .label = "GENERAL", .kind = .text },
    .{ .section = "General", .key = "StartMenu", .label = "Start Menu", .kind = .toggle },
    .{ .section = "General", .key = "Autosave", .label = "Autosave", .kind = .toggle },
    .{ .section = "General", .key = "DisplayPerfInTitle", .label = "Show FPS In Title", .kind = .toggle },
    .{ .section = "General", .key = "ExtendedAspectRatio", .label = "Aspect Ratio", .kind = .{ .choice = .{ .values = &.{ "4:3", "16:9", "16:10", "18:9" } } } },
    .{ .section = "General", .key = "WidescreenHud", .label = "Widescreen HUD", .kind = .toggle },
    .{ .section = "General", .key = "WidescreenCamera", .label = "Widescreen Camera", .kind = .toggle },
    .{ .section = "General", .key = "DisableFrameDelay", .label = "Disable Frame Delay", .kind = .toggle },
    .{ .section = "General", .key = "Rumble", .label = "Rumble", .kind = .{ .number = .{ .min = 0, .max = 100, .step = 10, .suffix = "%" } } },

    .{ .section = kSectionMark, .key = "", .label = "GRAPHICS", .kind = .text },
    .{ .section = "Graphics", .key = "Fullscreen", .label = "Fullscreen", .kind = .{ .choice = .{
        .values = &.{ "0", "1", "2" },
        .labels = &.{ "Windowed", "Borderless", "Exclusive" },
    } } },
    .{ .section = "Graphics", .key = "WindowScale", .label = "Window Scale", .kind = .{ .number = .{ .min = 1, .max = 10, .step = 1 } } },
    .{ .section = "Graphics", .key = "OutputMethod", .label = "Output Method", .kind = .{ .choice = .{ .values = &.{ "SDL", "SDL-Software", "OpenGL", "OpenGL ES" } } } },
    .{ .section = "Graphics", .key = "NewRenderer", .label = "New Renderer", .kind = .toggle },
    .{ .section = "Graphics", .key = "EnhancedMode7", .label = "Enhanced Mode 7", .kind = .toggle },
    .{ .section = "Graphics", .key = "NoSpriteLimits", .label = "No Sprite Limits", .kind = .toggle },
    .{ .section = "Graphics", .key = "IgnoreAspectRatio", .label = "Stretch To Window", .kind = .toggle },
    .{ .section = "Graphics", .key = "LinearFiltering", .label = "Linear Filtering", .kind = .toggle },
    .{ .section = "Graphics", .key = "DimFlashes", .label = "Dim Flashes", .kind = .toggle },
    .{ .section = "Graphics", .key = "WindowSize", .label = "Window Size", .kind = .text },
    .{ .section = "Graphics", .key = "Shader", .label = "Shader", .kind = .text },

    .{ .section = kSectionMark, .key = "", .label = "SOUND", .kind = .text },
    .{ .section = "Sound", .key = "EnableAudio", .label = "Enable Audio", .kind = .toggle },
    .{ .section = "Sound", .key = "AudioFreq", .label = "Audio Frequency", .kind = .{ .choice = .{
        .values = &.{ "11025", "22050", "32000", "44100", "48000" },
        .labels = &.{ "11 kHz", "22 kHz", "32 kHz", "44 kHz", "48 kHz" },
    } } },
    .{ .section = "Sound", .key = "AudioChannels", .label = "Audio Channels", .kind = .{ .choice = .{
        .values = &.{ "1", "2" },
        .labels = &.{ "Mono", "Stereo" },
    } } },
    .{ .section = "Sound", .key = "AudioSamples", .label = "Audio Buffer", .kind = .{ .choice = .{ .values = &.{ "512", "1024", "2048", "4096" } } } },
    .{ .section = "Sound", .key = "EnableMSU", .label = "MSU Audio", .kind = .{ .choice = .{
        .values = &.{ "false", "true", "deluxe", "opuz", "deluxe-opuz" },
        .labels = &.{ "Off", "On", "Deluxe", "Opuz", "Deluxe Opuz" },
    } } },
    .{ .section = "Sound", .key = "MSUVolume", .label = "MSU Volume", .kind = .{ .number = .{ .min = 0, .max = 100, .step = 5, .suffix = "%" } } },
    .{ .section = "Sound", .key = "ResumeMSU", .label = "Resume MSU", .kind = .toggle },
    .{ .section = "Sound", .key = "MSUFinishCues", .label = "Finish MSU Cues", .kind = .toggle },
    .{ .section = "Sound", .key = "MSUPath", .label = "MSU Path", .kind = .text },

    .{ .section = kSectionMark, .key = "", .label = "FEATURES", .kind = .text },
    .{ .section = "Features", .key = "ItemSwitchLR", .label = "Switch Items With L/R", .kind = .toggle },
    .{ .section = "Features", .key = "ItemOnX", .label = "Second Item On X", .kind = .toggle },
    .{ .section = "Features", .key = "TurnWhileDashing", .label = "Turn While Dashing", .kind = .toggle },
    .{ .section = "Features", .key = "MirrorToDarkworld", .label = "Mirror To Dark World", .kind = .toggle },
    .{ .section = "Features", .key = "CollectItemsWithSword", .label = "Collect With Sword", .kind = .toggle },
    .{ .section = "Features", .key = "BreakPotsWithSword", .label = "Break Pots With Sword", .kind = .toggle },
    .{ .section = "Features", .key = "DisableLowHealthBeep", .label = "No Low Health Beep", .kind = .toggle },
    .{ .section = "Features", .key = "SkipIntroOnKeypress", .label = "Skip Intro", .kind = .toggle },
    .{ .section = "Features", .key = "ShowMaxItemsInYellow", .label = "Max Items In Yellow", .kind = .toggle },
    .{ .section = "Features", .key = "MoreActiveBombs", .label = "More Active Bombs", .kind = .toggle },
    .{ .section = "Features", .key = "CarryMoreRupees", .label = "Carry More Rupees", .kind = .toggle },
    .{ .section = "Features", .key = "MiscBugFixes", .label = "Misc Bug Fixes", .kind = .toggle },
    .{ .section = "Features", .key = "GameChangingBugFixes", .label = "Game Changing Fixes", .kind = .toggle },
    .{ .section = "Features", .key = "CancelBirdTravel", .label = "Cancel Bird Travel", .kind = .toggle },

    // The ALTTPR.COM page, not the lists above: a seed gets its own
    // choices, so trying widescreen on one leaves the normal game alone.
    .{ .section = kSectionMark, .key = "", .label = "RANDOMIZER", .kind = .text },
    .{ .section = "Randomizer", .key = "Widescreen", .label = "Widescreen", .note = "EXPERIMENTAL - CAN CAUSE ISSUES", .kind = .{ .choice = .{
        .values = &.{ "4:3", "16:9", "16:10", "18:9" },
        .labels = &.{ "Off", "16:9", "16:10", "18:9" },
    } } },
    .{ .section = "Randomizer", .key = "Rumble", .label = "Rumble", .kind = .{ .number = .{ .min = 0, .max = 100, .step = 10, .suffix = "%" } } },
    .{ .section = "Randomizer", .key = "MSUGamePath", .label = "MSU-1 Audio", .note = "PLAYS THE GAME'S MSU PACK (MSUPATH)", .kind = .toggle },

    .{ .section = kSectionMark, .key = "", .label = "TRACKER", .kind = .text },
    .{ .section = "Randomizer", .key = "Tracker", .label = "Placement", .note = "T SWITCHES THIS WHILE PLAYING", .kind = .{ .choice = .{
        .values = &.{ "panel", "overlay", "window", "off" },
        .labels = &.{ "Beside Game", "Over Game", "Own Window", "Off" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerSize", .label = "Layout", .note = "LARGE HAS BIGGER MAPS AND A TABLE", .kind = .{ .choice = .{
        .values = &.{ "large", "compact" },
        .labels = &.{ "Large", "Compact" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerSide", .label = "Panel Side", .kind = .{ .choice = .{
        .values = &.{ "right", "left" },
        .labels = &.{ "Right", "Left" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerItems", .label = "Show Items", .kind = .toggle },
    .{ .section = "Randomizer", .key = "TrackerDungeons", .label = "Show Dungeons", .kind = .toggle },
    .{ .section = "Randomizer", .key = "TrackerMaps", .label = "Show Maps", .kind = .{ .choice = .{
        .values = &.{ "both", "current", "off" },
        .labels = &.{ "Both Worlds", "Current World", "Off" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerNames", .label = "Dungeon Names", .note = "SHORT IS EP, DP, TOH AND SO ON", .kind = .{ .choice = .{
        .values = &.{ "full", "short" },
        .labels = &.{ "Full", "Short" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerKeys", .label = "Small Keys", .kind = .toggle },
    .{ .section = "Randomizer", .key = "TrackerDungeonItems", .label = "Big Key/Map/Compass", .kind = .toggle },
    .{ .section = "Randomizer", .key = "TrackerBosses", .label = "Bosses", .kind = .toggle },
    .{ .section = "Randomizer", .key = "TrackerPrizes", .label = "Dungeon Prizes", .note = "ALWAYS IS A SPOILER", .kind = .{ .choice = .{
        .values = &.{ "map", "always", "off" },
        .labels = &.{ "With Map", "Always", "Off" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerMedallions", .label = "MM/TR Medallions", .note = "SPOILER - SHOWN UNDER THE MEDALLIONS", .kind = .toggle },
    .{ .section = "Randomizer", .key = "TrackerCounter", .label = "Item Counter", .note = "ITEMS FOUND, HEARTS, GT AND GANON", .kind = .toggle },
    .{ .section = "Randomizer", .key = "TrackerMissing", .label = "Missing Items", .kind = .{ .choice = .{
        .values = &.{ "dim", "hide" },
        .labels = &.{ "Dimmed", "Hidden" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerCleared", .label = "Cleared Checks", .kind = .{ .choice = .{
        .values = &.{ "grey", "hide" },
        .labels = &.{ "Greyed", "Hidden" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerMarkers", .label = "Map Markers", .kind = .{ .choice = .{
        .values = &.{ "large", "small" },
        .labels = &.{ "Large", "Small" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerBackground", .label = "Background", .note = "GREEN AND MAGENTA KEY OUT ON STREAM", .kind = .{ .choice = .{
        .values = &.{ "dark", "black", "green", "magenta" },
        .labels = &.{ "Dark", "Black", "Green Screen", "Magenta" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerOpacity", .label = "Overlay Opacity", .kind = .{ .number = .{ .min = 10, .max = 100, .step = 10, .suffix = "%" } } },
    .{ .section = "Randomizer", .key = "TrackerCorner", .label = "Overlay Corner", .kind = .{ .choice = .{
        .values = &.{ "bottom-right", "bottom-left", "top-right", "top-left" },
        .labels = &.{ "Bottom Right", "Bottom Left", "Top Right", "Top Left" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerOverlaySize", .label = "Overlay Size", .note = "LARGE COVERS MORE OF THE GAME", .kind = .{ .choice = .{
        .values = &.{ "small", "large" },
        .labels = &.{ "Small", "Large" },
    } } },
    .{ .section = "Randomizer", .key = "TrackerLegend", .label = "Map Legend", .kind = .toggle },

    // The button mapping, edited on the in-game settings' Controls tab: each
    // is the twelve SNES buttons' keys in one line, Up, Down, Left, Right,
    // Select, Start, A, B, X, Y, L, R.
    .{ .section = kSectionMark, .key = "", .label = "CONTROLS", .kind = .text },
    .{ .section = "KeyMap", .key = "Controls", .label = "Keyboard", .kind = .text },
    .{ .section = "GamepadMap", .key = "Controls", .label = "Controller", .kind = .text },
};

// ------------------------------------------------------------- ini editing

/// Where one setting sits in the zelda3.ini built into the game: its value,
/// and the comment block above it, as line numbers into kDefaultIni.
const DefaultEntry = struct { value: []const u8, comment_from: usize, key_line: usize };

fn defaultEntry(section: []const u8, key: []const u8) ?DefaultEntry {
    var cur: []const u8 = "";
    var comment_from: ?usize = null;
    var idx: usize = 0;
    var it = std.mem.splitScalar(u8, kDefaultIni, '\n');
    while (it.next()) |raw| : (idx += 1) {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) {
            comment_from = null;
        } else if (line[0] == '#' or line[0] == ';') {
            if (comment_from == null) comment_from = idx;
        } else if (line[0] == '[') {
            cur = std.mem.trim(u8, line[1..], "]");
            comment_from = null;
        } else if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
            const k = std.mem.trim(u8, line[0..eq], " \t");
            if (std.mem.eql(u8, cur, section) and std.mem.eql(u8, k, key)) {
                return .{
                    .value = std.mem.trim(u8, line[eq + 1 ..], " \t"),
                    .comment_from = comment_from orelse idx,
                    .key_line = idx,
                };
            }
            comment_from = null;
        }
    }
    return null;
}

/// A setting's value in the zelda3.ini built into the game, for putting
/// things back the way they came.
pub fn defaultValue(section: []const u8, key: []const u8) ?[]const u8 {
    return if (defaultEntry(section, key)) |d| d.value else null;
}

fn defaultIniLine(n: usize) []const u8 {
    var it = std.mem.splitScalar(u8, kDefaultIni, '\n');
    var i: usize = 0;
    while (it.next()) |raw| : (i += 1) {
        if (i == n) return std.mem.trimEnd(u8, raw, "\r");
    }
    return "";
}

/// The ini kept as its original lines, with each setting bound to the line it
/// came from. Values are rewritten in place so comments, blank lines, ordering
/// and line endings all survive.
///
/// A file written before a setting existed simply doesn't have it. Such a
/// setting shows the built-in default, which is what the game uses when the
/// key is missing, and if it's changed, saving adds it to the end of its
/// section along with the comment that explains it.
pub const Ini = struct {
    alloc: std.mem.Allocator,
    text: []u8,
    lines: std.ArrayList([]const u8),
    /// Owned replacement values, indexed alongside kSettings. Null means the
    /// setting was not found in the file.
    values: [kSettings.len]?[]u8,
    line_of: [kSettings.len]?usize,
    crlf: bool,

    pub fn load(alloc: std.mem.Allocator, path: [*:0]const u8) !Ini {
        const text = try fileio.readWholeFile(alloc, path);
        var self = Ini{
            .alloc = alloc,
            .text = text,
            .lines = .empty,
            .values = @splat(null),
            .line_of = @splat(null),
            .crlf = std.mem.indexOf(u8, text, "\r\n") != null,
        };
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |raw|
            try self.lines.append(alloc, std.mem.trimEnd(u8, raw, "\r"));

        // Walk the file once, tracking the section, and bind each setting to
        // the line that carries it. Anything the file lacks falls back to the
        // built-in default afterwards.
        var section: []const u8 = "";
        for (self.lines.items, 0..) |line, idx| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == ';') continue;
            if (trimmed[0] == '[') {
                section = std.mem.trim(u8, trimmed[1..], "]");
                continue;
            }
            const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const key = std.mem.trim(u8, trimmed[0..eq], " \t");
            const value = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
            for (kSettings, 0..) |s, si| {
                if (self.line_of[si] != null) continue;
                if (std.mem.eql(u8, s.section, section) and std.mem.eql(u8, s.key, key)) {
                    self.line_of[si] = idx;
                    self.values[si] = try alloc.dupe(u8, value);
                    break;
                }
            }
        }
        for (kSettings, 0..) |s, si| {
            if (self.line_of[si] != null or isSection(s)) continue;
            if (defaultEntry(s.section, s.key)) |d| self.values[si] = try alloc.dupe(u8, d.value);
        }
        // A file from before ItemOnX had the second item as part of
        // ItemSwitchLR, and the game still reads it that way, so show that.
        const x = settingIndex("Features", "ItemOnX").?;
        const lr = settingIndex("Features", "ItemSwitchLR").?;
        if (self.line_of[x] == null and self.values[lr] != null) {
            if (self.values[x]) |old| alloc.free(old);
            self.values[x] = try alloc.dupe(u8, self.values[lr].?);
        }
        return self;
    }

    /// A setting the file doesn't carry, set to something other than the
    /// built-in default, so saving has to add it.
    fn needsAdding(self: *const Ini, si: usize) bool {
        if (self.line_of[si] != null or isSection(kSettings[si])) return false;
        const v = self.values[si] orelse return false;
        const d = defaultEntry(kSettings[si].section, kSettings[si].key) orelse return true;
        return !std.mem.eql(u8, std.mem.trim(u8, v, " \t"), d.value);
    }

    /// The line the section's additions go in front of: after its last
    /// setting or comment, ahead of the blank lines that lead to the next
    /// section. Null when the file has no such section.
    fn sectionEnd(self: *const Ini, section: []const u8) ?usize {
        var in_section = false;
        var last_content: ?usize = null;
        for (self.lines.items, 0..) |line, idx| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len != 0 and trimmed[0] == '[') {
                if (in_section) break;
                in_section = std.mem.eql(u8, std.mem.trim(u8, trimmed[1..], "]"), section);
                if (in_section) last_content = idx;
                continue;
            }
            if (in_section and trimmed.len != 0) last_content = idx;
        }
        return if (last_content) |l| l + 1 else null;
    }

    fn appendAddition(self: *const Ini, out: *std.ArrayList(u8), si: usize, eol: []const u8) !void {
        const s = kSettings[si];
        try out.appendSlice(self.alloc, eol);
        if (defaultEntry(s.section, s.key)) |d| {
            var n = d.comment_from;
            while (n < d.key_line) : (n += 1) {
                try out.appendSlice(self.alloc, defaultIniLine(n));
                try out.appendSlice(self.alloc, eol);
            }
        }
        try out.appendSlice(self.alloc, s.key);
        try out.appendSlice(self.alloc, " = ");
        try out.appendSlice(self.alloc, self.values[si].?);
        try out.appendSlice(self.alloc, eol);
    }

    pub fn deinit(self: *Ini) void {
        for (self.values) |v| if (v) |owned| self.alloc.free(owned);
        self.lines.deinit(self.alloc);
        self.alloc.free(self.text);
    }

    pub fn set(self: *Ini, si: usize, value: []const u8) !void {
        const owned = try self.alloc.dupe(u8, value);
        if (self.values[si]) |old| self.alloc.free(old);
        self.values[si] = owned;
    }

    pub fn save(self: *Ini, path: [*:0]const u8) !void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.alloc);
        const eol: []const u8 = if (self.crlf) "\r\n" else "\n";

        // Where each missing setting goes, if its section is in the file.
        var insert_before: [kSettings.len]?usize = @splat(null);
        for (0..kSettings.len) |si| {
            if (self.needsAdding(si)) insert_before[si] = self.sectionEnd(kSettings[si].section);
        }

        for (self.lines.items, 0..) |line, idx| {
            for (0..kSettings.len) |si| {
                if (self.needsAdding(si) and insert_before[si] == idx)
                    try self.appendAddition(&out, si, eol);
            }
            var written = false;
            for (0..kSettings.len) |si| {
                if (self.line_of[si] != idx) continue;
                const v = self.values[si] orelse continue;
                // Keep the key exactly as the file spells it, including any
                // indentation, and replace only what follows the '='.
                const eq = std.mem.indexOfScalar(u8, line, '=').?;
                try out.appendSlice(self.alloc, line[0 .. eq + 1]);
                // An empty value keeps the bare "Key =" the file already has,
                // rather than gaining a trailing space.
                if (v.len != 0) {
                    try out.append(self.alloc, ' ');
                    try out.appendSlice(self.alloc, v);
                }
                written = true;
                break;
            }
            if (!written) try out.appendSlice(self.alloc, line);
            if (idx + 1 < self.lines.items.len) try out.appendSlice(self.alloc, eol);
        }

        // Settings whose section ends the file, or isn't in it at all.
        var last_section: []const u8 = "";
        for (0..kSettings.len) |si| {
            if (!self.needsAdding(si)) continue;
            if (insert_before[si]) |at| if (at < self.lines.items.len) continue;
            const section = kSettings[si].section;
            if (insert_before[si] == null and !std.mem.eql(u8, section, last_section)) {
                try out.appendSlice(self.alloc, eol);
                try out.append(self.alloc, '[');
                try out.appendSlice(self.alloc, section);
                try out.append(self.alloc, ']');
                last_section = section;
            }
            try self.appendAddition(&out, si, eol);
        }
        try fileio.writeWholeFile(path, out.items);

        // Read it back, so the added lines are bound to their settings and a
        // second save changes them in place rather than adding them again.
        const reread = try Ini.load(self.alloc, path);
        self.deinit();
        self.* = reread;
    }
};

// ------------------------------------------------------------------- value

pub fn splitSuffix(value: []const u8, suffix: []const u8) []const u8 {
    if (suffix.len != 0 and std.mem.endsWith(u8, value, suffix))
        return value[0 .. value.len - suffix.len];
    return value;
}

/// Steps a setting's value. `dir` is +1 or -1.
pub fn cycle(alloc: std.mem.Allocator, buf: []u8, s: Setting, current: []const u8, dir: i32) ?[]const u8 {
    switch (s.kind) {
        .toggle => return if (std.mem.eql(u8, std.mem.trim(u8, current, " \t"), "1")) "0" else "1",
        .choice => |opts| {
            var at: usize = 0;
            for (opts.values, 0..) |o, i| {
                if (std.ascii.eqlIgnoreCase(o, current)) {
                    at = i;
                    break;
                }
            }
            const n: i32 = @intCast(opts.values.len);
            var next: i32 = @as(i32, @intCast(at)) + dir;
            if (next < 0) next = n - 1;
            if (next >= n) next = 0;
            return opts.values[@intCast(next)];
        },
        .number => |num| {
            const body = splitSuffix(std.mem.trim(u8, current, " \t"), num.suffix);
            const cur = std.fmt.parseInt(i32, body, 10) catch num.min;
            var next = cur + num.step * dir;
            if (next < num.min) next = num.min;
            if (next > num.max) next = num.max;
            return std.fmt.bufPrint(buf, "{d}{s}", .{ next, num.suffix }) catch null;
        },
        .text => return null,
    }
    _ = alloc;
}

/// What the list shows for a value: toggles read as words, everything else as
/// written, with empty text made visible.
pub fn displayValue(buf: []u8, s: Setting, value: []const u8) []const u8 {
    const v = std.mem.trim(u8, value, " \t");
    switch (s.kind) {
        .toggle => return if (std.mem.eql(u8, v, "1")) "ON" else "OFF",
        .text => return if (v.len == 0) "(none)" else v,
        .choice => |opts| return opts.labelFor(v),
        else => {},
    }
    return std.fmt.bufPrint(buf, "{s}", .{v}) catch v;
}

// ------------------------------------------------------------------ drawing

fn setColor(r: *c.SDL_Renderer, col: Rgb) void {
    _ = c.SDL_SetRenderDrawColor(r, col.r, col.g, col.b, 255);
}

fn fillRect(r: *c.SDL_Renderer, x: f32, y: f32, w: f32, h: f32, col: Rgb) void {
    setColor(r, col);
    const rect = c.SDL_FRect{ .x = x, .y = y, .w = w, .h = h };
    _ = c.SDL_RenderFillRect(r, &rect);
}

/// A recessed gold frame: light along the top and left, dark along the bottom
/// and right, the way the game's own menu boxes are shaded.
/// A hollow rectangle. drawFrame paints its interior, so anything drawn
/// around existing content needs this instead.
fn drawOutline(r: *c.SDL_Renderer, x: f32, y: f32, w: f32, h: f32, t: f32, col: Rgb) void {
    fillRect(r, x, y, w, t, col);
    fillRect(r, x, y + h - t, w, t, col);
    fillRect(r, x, y, t, h, col);
    fillRect(r, x + w - t, y, t, h, col);
}

fn drawFrame(r: *c.SDL_Renderer, x: f32, y: f32, w: f32, h: f32) void {
    const t = 4.0;
    fillRect(r, x, y, w, h, kColorFrame);
    fillRect(r, x, y, w, t, kColorFrameHi);
    fillRect(r, x, y, t, h, kColorFrameHi);
    fillRect(r, x, y + h - t, w, t, kColorFrameLo);
    fillRect(r, x + w - t, y, t, h, kColorFrameLo);
    fillRect(r, x + t * 2, y + t * 2, w - t * 4, h - t * 4, kColorPanel);
}

fn drawText(r: *c.SDL_Renderer, x: f32, y: f32, col: Rgb, text: []const u8) void {
    drawTextScaled(r, x, y, col, text, kScale);
}

/// Width of a run of text once drawn. The debug font is a fixed 8x8 cell.
fn textWidth(text: []const u8, scale: f32) f32 {
    return @as(f32, @floatFromInt(text.len)) * 8 * scale;
}

fn drawTextCentered(r: *c.SDL_Renderer, cx: f32, y: f32, col: Rgb, text: []const u8, scale: f32) void {
    drawTextScaled(r, cx - textWidth(text, scale) / 2, y, col, text, scale);
}

/// SDL's debug font is a fixed 8x8, so size comes from the render scale.
fn drawTextScaled(r: *c.SDL_Renderer, x: f32, y: f32, col: Rgb, text: []const u8, scale: f32) void {
    var buf: [256]u8 = undefined;
    const n = @min(text.len, buf.len - 1);
    @memcpy(buf[0..n], text[0..n]);
    buf[n] = 0;
    setColor(r, col);
    _ = c.SDL_SetRenderScale(r, scale, scale);
    _ = c.SDL_RenderDebugText(r, x / scale, y / scale, @ptrCast(&buf));
    _ = c.SDL_SetRenderScale(r, 1, 1);
}

// --------------------------------------------------------------------- main

pub fn isSection(s: Setting) bool {
    return std.mem.eql(u8, s.section, kSectionMark);
}

fn firstSelectable(from: usize, to: usize) usize {
    var i = from;
    while (i < to) : (i += 1) if (!isSection(kSettings[i])) return i;
    return from;
}

/// A question laid over whatever screen is showing.
const Modal = enum {
    none,
    /// Asked before leaving, so a stray B does not close the window.
    quit,
    /// Asked when Build Assets is chosen, since the ROM arrives by drag.
    rom,
};

const kQuitChoices = [_][]const u8{ "Quit", "Stay" };
/// Stay is the default, so pressing the button again backs out rather than
/// confirming what the first press only meant to ask about.
const kQuitStay = 1;

/// The launcher is a short menu and the screens it opens: the two lists of
/// settings, and the randomizer's pages (a choice of randomizer, then the
/// ALTTPR.COM page seeds are dropped on, and what a seed says about itself).
const Screen = enum { main, settings, features, controls, hub, alttpr, details };

/// Where the FEATURES heading sits, so the two lists are slices of the one
/// schema instead of separate tables that could drift out of step with it.
const kFeaturesStart = blk: {
    for (kSettings, 0..) |s, i| {
        if (isSection(s) and std.mem.eql(u8, s.label, "FEATURES")) break :blk i;
    }
    @compileError("the settings schema has no FEATURES section");
};

/// Where the RANDOMIZER heading sits; everything from there on is on the
/// ALTTPR.COM page, and the in-game settings stop short of it.
pub const kRandomizerStart = blk: {
    for (kSettings, 0..) |s, i| {
        if (isSection(s) and std.mem.eql(u8, s.label, "RANDOMIZER")) break :blk i;
    }
    @compileError("the settings schema has no RANDOMIZER section");
};

/// Where the CONTROLS heading sits: the button mapping, which only the
/// in-game settings' Controls tab edits, row by row.
pub const kControlsStart = blk: {
    for (kSettings, 0..) |s, i| {
        if (isSection(s) and std.mem.eql(u8, s.label, "CONTROLS")) break :blk i;
    }
    @compileError("the settings schema has no CONTROLS section");
};

/// The ALTTPR.COM page's first two rows aren't settings: one starts the
/// seed, the other shows what it says about itself.
const kPlayRow = kSettings.len;
const kDetailsRow = kSettings.len + 1;
const kVirtualRows = [_]usize{ kPlayRow, kDetailsRow };

fn screenRange(screen: Screen) struct { from: usize, to: usize } {
    return switch (screen) {
        .settings => .{ .from = 0, .to = kFeaturesStart },
        .features => .{ .from = kFeaturesStart, .to = kRandomizerStart },
        .alttpr => .{ .from = kRandomizerStart, .to = kControlsStart },
        .main, .controls, .hub, .details => .{ .from = 0, .to = 0 },
    };
}

/// How many rows a list has, counting headings and the ALTTPR.COM page's
/// two buttons. Cursors and scroll positions count rows, not settings.
fn rowCount(screen: Screen) usize {
    const r = screenRange(screen);
    return r.to - r.from + if (screen == .alttpr) kVirtualRows.len else 0;
}

/// What sits at a row: an index into kSettings, or kPlayRow/kDetailsRow.
fn rowAt(screen: Screen, pos: usize) usize {
    if (screen == .alttpr and pos < kVirtualRows.len) return kVirtualRows[pos];
    const extra: usize = if (screen == .alttpr) kVirtualRows.len else 0;
    return screenRange(screen).from + pos - extra;
}

fn rowSelectable(screen: Screen, pos: usize) bool {
    const at = rowAt(screen, pos);
    return at >= kSettings.len or !isSection(kSettings[at]);
}

fn firstRow(screen: Screen) usize {
    var p: usize = 0;
    while (p < rowCount(screen) and !rowSelectable(screen, p)) p += 1;
    return p;
}

/// Where a list starts and how many rows show. The ALTTPR.COM page gives
/// the top of the screen to the seed.
fn listStartY(screen: Screen) f32 {
    return if (screen == .alttpr) kEmuNoteY + kEmuNoteH + 10 else kListStartY;
}

fn visibleRows(screen: Screen) usize {
    return if (screen == .alttpr) 9 else kVisibleRows;
}

const kMainItems = [_][]const u8{ "Settings", "Features", "Controls", "Save Settings", "Build Assets", "Play", "Randomizer" };
const kMainControls = 2;
const kMainSave = 3;
const kMainBuild = 4;
const kMainLaunch = 5;
const kMainRandomizer = 6;

/// The randomizer page's two choices. Only one exists yet.
const kHubItems = [_][]const u8{ "BUILT-IN RANDOMIZER", "ALTTPR.COM RANDOMIZER" };
const kHubBuiltIn = 0;
const kHubAlttpr = 1;

/// Every gamepad currently plugged in. Held open so their sticks and pads
/// can be polled each frame, which is what gives held-direction repeat.
const Pads = struct {
    items: [8]?*c.SDL_Gamepad = @splat(null),

    fn open(self: *Pads, id: c.SDL_JoystickID) void {
        for (&self.items) |*slot| {
            if (slot.* != null) continue;
            slot.* = c.SDL_OpenGamepad(id);
            return;
        }
    }

    fn close(self: *Pads, id: c.SDL_JoystickID) void {
        for (&self.items) |*slot| {
            const pad = slot.* orelse continue;
            if (c.SDL_GetGamepadID(pad) != id) continue;
            c.SDL_CloseGamepad(pad);
            slot.* = null;
        }
    }

    fn closeAll(self: *Pads) void {
        for (&self.items) |*slot| {
            if (slot.*) |pad| c.SDL_CloseGamepad(pad);
            slot.* = null;
        }
    }

    fn count(self: *const Pads) usize {
        var n: usize = 0;
        for (self.items) |slot| {
            if (slot != null) n += 1;
        }
        return n;
    }

    /// Where the left sticks are pushed. Only the sticks: buttons and keys
    /// arrive as events, because a genuinely analog input is the one thing
    /// that has to be read as state rather than as presses.
    fn stickDirection(self: *const Pads, comptime axis: enum { vertical, horizontal }) i32 {
        const kDeadzone = 16000;
        var dir: i32 = 0;
        for (self.items) |slot| {
            const pad = slot orelse continue;
            const stick = if (axis == .vertical) c.SDL_GAMEPAD_AXIS_LEFTY else c.SDL_GAMEPAD_AXIS_LEFTX;
            if (!c.SDL_GamepadHasAxis(pad, stick)) continue;
            const v = c.SDL_GetGamepadAxis(pad, stick);
            if (v < -kDeadzone) dir -= 1;
            if (v > kDeadzone) dir += 1;
        }
        return std.math.sign(dir);
    }
};

/// Configures the joystick layer the same way the game does, so a pad
/// behaves identically in both.
///
/// On macOS a pad can arrive through GameController and through HIDAPI at
/// once, and the two disagree about which button sits where - which is how a
/// SNES pad ends up with A and B doing the same job. HIDAPI maps these
/// correctly, so GameController is left out of it. It also decides which
/// letters SDL reports on the faces, so the launcher has to match the game or
/// the two read the same pad differently.
fn configureJoysticks() void {
    if (builtin.os.tag == .macos) {
        _ = c.SDL_SetHint(c.SDL_HINT_JOYSTICK_MFI, "0");
    }
}

/// What a face button means, worked out from the label printed on it rather
/// than where it sits.
///
/// SDL reports face buttons by position, and the layouts disagree: the button
/// marked A is on the bottom of an Xbox pad and on the right of a Nintendo
/// one, which is the same place B sits on the Xbox. Routing by position
/// therefore turns A into cancel on Nintendo hardware - on the main menu,
/// pressing A closed the launcher.
fn faceAction(which: c.SDL_JoystickID, button: u8) enum { confirm, back, save, none } {
    const pad = c.SDL_GetGamepadFromID(which);
    const label = if (pad != null)
        c.SDL_GetGamepadButtonLabel(pad, button)
    else
        c.SDL_GAMEPAD_BUTTON_LABEL_UNKNOWN;

    // Position is the fallback only when there is no label to go on. Letting
    // an unhandled label fall through to it put both Y and X on save.
    if (label == c.SDL_GAMEPAD_BUTTON_LABEL_UNKNOWN) {
        return switch (button) {
            c.SDL_GAMEPAD_BUTTON_SOUTH => .confirm,
            c.SDL_GAMEPAD_BUTTON_EAST => .back,
            c.SDL_GAMEPAD_BUTTON_WEST => .save,
            else => .none,
        };
    }

    return switch (label) {
        c.SDL_GAMEPAD_BUTTON_LABEL_A, c.SDL_GAMEPAD_BUTTON_LABEL_CROSS => .confirm,
        c.SDL_GAMEPAD_BUTTON_LABEL_B, c.SDL_GAMEPAD_BUTTON_LABEL_CIRCLE => .back,
        c.SDL_GAMEPAD_BUTTON_LABEL_X, c.SDL_GAMEPAD_BUTTON_LABEL_SQUARE => .save,
        else => .none,
    };
}

/// Which direction keys and pad buttons are down, tracked from presses and
/// releases rather than read back as state.
///
/// Reading the keyboard state each frame looked equivalent and is not: if a
/// release goes missing - the window loses focus mid-press, or the events are
/// synthetic - the direction stays down forever and the repeat below runs
/// away, walking the list and changing every setting it passes. Pairs of
/// events cannot get stuck, and focus loss clears the lot anyway.
const Held = struct {
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,

    fn vertical(self: Held) i32 {
        return @as(i32, if (self.down) 1 else 0) - @as(i32, if (self.up) 1 else 0);
    }

    fn horizontal(self: Held) i32 {
        return @as(i32, if (self.right) 1 else 0) - @as(i32, if (self.left) 1 else 0);
    }

    fn set(self: *Held, key: c.SDL_Keycode, down: bool) bool {
        switch (key) {
            c.SDLK_UP => self.up = down,
            c.SDLK_DOWN => self.down = down,
            c.SDLK_LEFT => self.left = down,
            c.SDLK_RIGHT => self.right = down,
            else => return false,
        }
        return true;
    }

    fn setButton(self: *Held, button: u8, down: bool) bool {
        switch (button) {
            c.SDL_GAMEPAD_BUTTON_DPAD_UP => self.up = down,
            c.SDL_GAMEPAD_BUTTON_DPAD_DOWN => self.down = down,
            c.SDL_GAMEPAD_BUTTON_DPAD_LEFT => self.left = down,
            c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT => self.right = down,
            else => return false,
        }
        return true;
    }
};

/// Turns a held direction into one step immediately and then a steady stream,
/// so a list of forty settings can be crossed without forty presses.
const Repeat = struct {
    dir: i32 = 0,
    next_at: u64 = 0,

    const kDelayMs = 380;
    const kRateMs = 80;

    /// Records a press that arrived as an event, so the frame poll that
    /// follows does not count it a second time.
    fn arm(self: *Repeat, dir: i32, now: u64) void {
        self.dir = dir;
        self.next_at = now + kDelayMs;
    }

    fn step(self: *Repeat, dir: i32, now: u64) i32 {
        if (dir == 0) {
            self.dir = 0;
            return 0;
        }
        if (dir != self.dir) {
            self.dir = dir;
            self.next_at = now + kDelayMs;
            return dir;
        }
        if (now >= self.next_at) {
            self.next_at = now + kRateMs;
            return dir;
        }
        return 0;
    }
};

/// What is sitting in zelda3_assets.dat.
pub const AssetState = enum {
    missing,
    /// Present and matching the file the old Python tool builds from a US ROM.
    verified,
    /// Present, but not a file this build of the tool produces. Usually an
    /// older .dat; the game may or may not accept it.
    unrecognized,

    fn line(self: AssetState) []const u8 {
        return switch (self) {
            .missing => "ASSETS MISSING",
            .verified => "ASSETS VERIFIED",
            .unrecognized => "ASSETS PRESENT - CHECKSUM DIFFERS",
        };
    }

    fn color(self: AssetState) Rgb {
        return switch (self) {
            .missing => kColorWarn,
            .verified => kColorOk,
            .unrecognized => kColorWarn,
        };
    }
};

/// Hashes zelda3_assets.dat and compares it with the digest the asset
/// builder is known to produce. Reading 668K costs about a millisecond, so
/// this runs at startup and after every build rather than being cached and
/// going stale.
pub fn checkAssets(alloc: std.mem.Allocator) AssetState {
    return checkAssetsAt(alloc, kAssetsPath);
}

fn checkAssetsAt(alloc: std.mem.Allocator, path: [*:0]const u8) AssetState {
    const data = fileio.readWholeFile(alloc, path) catch return .missing;
    defer alloc.free(data);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});

    var hex: [64]u8 = undefined;
    const kHexDigits = "0123456789abcdef";
    for (digest, 0..) |byte, i| {
        hex[i * 2] = kHexDigits[byte >> 4];
        hex[i * 2 + 1] = kHexDigits[byte & 0xf];
    }
    return if (std.mem.eql(u8, &hex, asset_all.kReferenceDigest)) .verified else .unrecognized;
}

/// State the drawing needs. Passed as one value because the slow paths -
/// building assets - draw a frame before they block, and threading eight
/// arguments through those calls was its own small mess.
const View = struct {
    screen: Screen,
    modal: Modal = .none,
    quit_choice: usize = kQuitStay,
    cursor: usize,
    top: usize,
    status: []const u8,
    dirty: bool,
    assets: AssetState,
    /// The seed details' scroll position.
    details_top: usize = 0,
};

fn listIndex(sc: Screen) usize {
    return switch (sc) {
        .main, .settings, .controls, .hub, .details => 0,
        .features => 1,
        .alttpr => 2,
    };
}

/// Gathers the loop's scattered state into what drawing needs.
fn viewOf(
    screen: Screen,
    main_cursor: usize,
    list_cursor: [3]usize,
    list_top: [3]usize,
    status: []const u8,
    dirty: bool,
    assets: AssetState,
    modal: Modal,
    quit_choice: usize,
) View {
    const li = listIndex(screen);
    return .{
        .screen = screen,
        .modal = modal,
        .quit_choice = quit_choice,
        .cursor = switch (screen) {
            .main => main_cursor,
            .hub => g_hub_cursor,
            .controls => g_ctl_row,
            else => list_cursor[li],
        },
        .details_top = g_details_top,
        .top = list_top[li],
        .status = status,
        .dirty = dirty,
        .assets = assets,
    };
}

/// Draws a screen into a BMP with no window, for working on the menu:
/// `zelda3 --menu-shot <main|hub|alttpr|details> out.bmp [seed.sfc]`.
pub fn screenshot(alloc: std.mem.Allocator, which: []const u8, path: [*:0]const u8, seed: ?[]const u8) !void {
    var ini = try Ini.load(alloc, "zelda3.ini");
    defer ini.deinit();
    const surface = c.SDL_CreateSurface(kWindowW, kWindowH, c.SDL_PIXELFORMAT_XRGB8888) orelse return error.SdlSurface;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    if (seed) |sp| _ = loadSeed(sp);
    const screen = std.meta.stringToEnum(Screen, which) orelse .alttpr;
    g_spoilers = std.c.getenv("SPOILERS") != null;
    if (std.c.getenv("DETAILS_TOP")) |t| g_details_top = std.fmt.parseInt(usize, std.mem.span(t), 10) catch 0;
    // CTL_ROW=n picks a row on the Controls screen; CAPTURE=1 has it waiting.
    if (std.c.getenv("CTL_ROW")) |t| g_ctl_row = std.fmt.parseInt(usize, std.mem.span(t), 10) catch 0;
    if (g_ctl_row >= kCtlVisible) g_ctl_top = g_ctl_row + 1 - kCtlVisible;
    if (std.c.getenv("CAPTURE") != null) g_ctl_capture = g_ctl_row;
    const cursor = [_]usize{ 0, 0, 0 };
    const top = [_]usize{ 0, 0, 0 };
    drawScreen(renderer, &ini, viewOf(screen, if (screen == .main) kMainControls else kMainRandomizer, cursor, top, "", false, .verified, .none, kQuitStay));
    if (!c.SDL_SaveBMP(surface, path)) return error.SaveFailed;
}

fn drawScreen(renderer: *c.SDL_Renderer, ini: *const Ini, v: View) void {
    fillRect(renderer, 0, 0, kWindowW, kWindowH, kColorBg);
    drawFrame(renderer, 16, 16, kWindowW - 32, kWindowH - 32);

    drawHeader(renderer, v.screen);

    switch (v.screen) {
        .main => drawMain(renderer, v),
        .hub => drawHub(renderer, v),
        .controls => drawControls(renderer, ini, v),
        .details => {
            setMsuGamePath(ini);
            drawDetails(renderer, v);
        },
        .alttpr => {
            drawSeedBox(renderer);
            drawList(renderer, ini, v);
        },
        .settings, .features => drawList(renderer, ini, v),
    }

    drawFooter(renderer, v);
    if (v.modal != .none) drawModal(renderer, v);
    _ = c.SDL_RenderPresent(renderer);
}

/// Title and the rule under it. The lists need the space, so the title stays
/// on one line and the rule doubles as the top of the list.
fn drawHeader(renderer: *c.SDL_Renderer, screen: Screen) void {
    const cx: f32 = kWindowW / 2;
    if (screen == .main) {
        // The game's own title, then what this program is. Three lines, so
        // everything below starts lower than it used to.
        drawTextCentered(renderer, cx, 36, kColorSelect, "THE LEGEND OF ZELDA", kScale);
        drawTextCentered(renderer, cx, 36 + kRowH, kColorSelect, "A LINK TO THE PAST", kScale);
        drawTextCentered(renderer, cx, 36 + kRowH * 2, kColorTextDim, "START MENU", kScale);
        fillRect(renderer, 60, 36 + kRowH * 3 + 6, kWindowW - 120, 2, kColorFrame);
        return;
    }

    const name = switch (screen) {
        .settings => "SETTINGS",
        .features => "FEATURES",
        .hub => "RANDOMIZER",
        .controls => "CONTROLS",
        .alttpr => "ALTTPR.COM",
        .details => "SEED DETAILS",
        .main => unreachable,
    };
    drawText(renderer, 40, 36, kColorSelect, name);
    drawTextScaled(renderer, kWindowW - 40 - textWidth("ESC BACK", kScale), 36, kColorTextDim, "ESC BACK", kScale);
    fillRect(renderer, 40, 36 + kRowH, kWindowW - 80, 2, kColorFrame);
}

/// A rectangle on screen. Drawing and hit testing share these so the two
/// cannot drift apart: a button that moves but stays clickable where it used
/// to be is the kind of fault nobody notices until a click misses.
const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h;
    }
};

// The menu's group of entries, then the Launch button below them, and the
// Randomizer button under that.
const kEntryY: f32 = 114;
const kEntryGap: f32 = 26;
const kLaunchY: f32 = 242;
const kLaunchScale: f32 = kScale * 2;
const kRandoY: f32 = 346;
const kListStartY: f32 = 36 + kRowH + 14;
const kSeedBoxY: f32 = kListStartY - 4;
const kSeedBoxH: f32 = kRowH * 4 + 12;
// Under the seed: why this page plays in an emulator and the rest doesn't.
const kEmuNoteY: f32 = kSeedBoxY + kSeedBoxH + 8;
const kEmuNoteH: f32 = 20;
const kEmuNote = [_][]const u8{
    "SEEDS RUN IN A SNES EMULATOR, NOT THE PC PORT. ALTTPR.COM REWRITES",
    "TOO MUCH OF THE GAME'S CODE - ONLY THE ROM ITSELF PLAYS IT EXACTLY.",
};

fn mainEntryRect(i: usize) Rect {
    if (i == kMainLaunch) return launchRect();
    if (i == kMainRandomizer) return randoRect();
    // Wider than the highlight, so aiming at a short word still lands.
    const y = kEntryY + kEntryGap * @as(f32, @floatFromInt(i));
    return .{ .x = kWindowW / 2 - 150, .y = y - 6, .w = 300, .h = kEntryGap };
}

fn launchRect() Rect {
    const w = textWidth(kMainItems[kMainLaunch], kLaunchScale) + 72;
    return .{
        .x = kWindowW / 2 - w / 2,
        .y = kLaunchY,
        .w = w,
        .h = 8 * kLaunchScale + 28,
    };
}

fn randoRect() Rect {
    const w = textWidth(kMainItems[kMainRandomizer], kScale) + 72;
    return .{ .x = kWindowW / 2 - w / 2, .y = kRandoY, .w = w, .h = 8 * kScale + 20 };
}

/// The randomizer page's two big buttons.
fn hubRect(i: usize) Rect {
    return .{ .x = 100, .y = 120 + 120 * @as(f32, @floatFromInt(i)), .w = kWindowW - 200, .h = 84 };
}

/// Which row of a list sits under a point, as a row position.
fn listRowAt(v: View, py: f32) ?usize {
    const n = rowCount(v.screen);
    var p = v.top;
    var y: f32 = listStartY(v.screen);
    while (p < n and p < v.top + visibleRows(v.screen)) : (p += 1) {
        if (py >= y - 3 and py < y - 3 + kRowH and rowSelectable(v.screen, p)) return p;
        y += kRowH;
    }
    return null;
}

fn drawMain(renderer: *c.SDL_Renderer, v: View) void {
    const cx: f32 = kWindowW / 2;

    for (kMainItems[0..kMainLaunch], 0..) |label, i| {
        const y = kEntryY + kEntryGap * @as(f32, @floatFromInt(i));
        const selected = i == v.cursor;
        const w = textWidth(label, kScale);

        if (selected) {
            // Sized to the word rather than the window, so the highlight
            // reads as a selection and not as a banner.
            fillRect(renderer, cx - w / 2 - 20, y - 6, w + 40, kEntryGap - 2, kColorRowHi);
            drawTextScaled(renderer, cx - w / 2 - 36, y, kColorSelect, ">", kScale);
        }
        drawTextCentered(renderer, cx, y, if (selected) kColorSelect else kColorText, label, kScale);
    }

    // Launch: a button, centered, big enough to be the obvious thing to press.
    const scale = kLaunchScale;
    const label = kMainItems[kMainLaunch];
    const box = launchRect();
    const box_w = box.w;
    const box_h = box.h;
    const box_x = box.x;
    const box_y = box.y;
    const selected = v.cursor == kMainLaunch;

    // Green whether or not it is selected - it is the one action the window
    // exists for. Selection is the ring, which has to be an outline: a frame
    // would paint its own interior over the button.
    fillRect(renderer, box_x, box_y, box_w, box_h, kColorLaunchBg);
    if (selected) drawOutline(renderer, box_x - 8, box_y - 8, box_w + 16, box_h + 16, 4, kColorFrameHi);
    drawTextCentered(renderer, cx, box_y + 14, kColorLaunchText, label, scale);

    // Whether the game can actually start, said plainly. Presence is not
    // enough - a .dat left over from another build loads and then misbehaves
    // in ways that look like game bugs, so it is checked against the digest
    // the asset builder produces and reported as its own state.
    const state_y = box_y + box_h + 6;

    drawTextCentered(renderer, cx, state_y, v.assets.color(), v.assets.line(), kScale);
    if (v.assets == .missing)
        drawTextCentered(renderer, cx, state_y + kRowH, kColorTextDim, "DRAG A .SFC ROM ONTO THIS WINDOW", kScale);

    // The randomizer: smaller, and a color of its own, since it plays
    // something other than the port.
    const r = randoRect();
    fillRect(renderer, r.x, r.y, r.w, r.h, kColorRandoBg);
    if (v.cursor == kMainRandomizer) drawOutline(renderer, r.x - 6, r.y - 6, r.w + 12, r.h + 12, 3, kColorFrameHi);
    drawTextCentered(renderer, cx, r.y + 10, kColorText, "RANDOMIZER", kScale);
}

// ---------------------------------------------------------------- controls

/// The Controls screen's row, its scroll, and the row waiting for a key or
/// button when one is.
var g_ctl_row: usize = 0;
var g_ctl_top: usize = 0;
var g_ctl_capture: ?usize = null;
var g_ctl_capture_at: u64 = 0;

const kCtlResetRow = controls.kButtonNames.len;
const kCtlRows = kCtlResetRow + 1;
const kCtlVisible = 6;
/// The pad drawn three times the size it is in the game's own menu.
const kCtlArtScale = 3;
const kCtlArtX: f32 = (kWindowW - pad_art.kWidth * kCtlArtScale) / 2;
const kCtlArtY: f32 = kListStartY + pad_art.kShoulderRise * kCtlArtScale;
const kCtlHeadY: f32 = kCtlArtY + pad_art.kHeight * kCtlArtScale + 8;
const kCtlRowsY: f32 = kCtlHeadY + kRowH + 4;
const kCtlColKey: f32 = 250;
const kCtlColPad: f32 = 430;
/// Five seconds to press something before the question goes away.
const kCtlCaptureMs = 5000;

fn ctlRowRect(slot: usize) Rect {
    return .{ .x = 32, .y = kCtlRowsY + kRowH * @as(f32, @floatFromInt(slot)) - 3, .w = kWindowW - 64, .h = kRowH };
}

/// Draws the pad a pixel at a time into a small image, then fills the
/// renderer a run of same-colored pixels at a time, which is a few hundred
/// rectangles rather than thousands.
fn drawPadArt(renderer: *c.SDL_Renderer, lit: ?usize) void {
    const kW = pad_art.kWidth;
    const kH = pad_art.kHeight + pad_art.kShoulderRise;
    const kClear: u32 = 0xff000000;
    const Img = struct {
        px: [kW * kH]u32 = @splat(kClear),
        fn put(p: *const anyopaque, x: i32, y: i32, rgb: u32) void {
            const self: *@This() = @ptrCast(@alignCast(@constCast(p)));
            const yy = y + pad_art.kShoulderRise;
            if (x < 0 or yy < 0 or x >= kW or yy >= kH) return;
            self.px[@as(usize, @intCast(yy)) * kW + @as(usize, @intCast(x))] = rgb;
        }
    };
    var img = Img{};
    const lit_color = @as(u32, kColorSelect.r) << 16 | @as(u32, kColorSelect.g) << 8 | kColorSelect.b;
    pad_art.draw(.{ .ctx = &img, .putFn = Img.put }, lit, lit_color);
    const s: f32 = kCtlArtScale;
    const top = kCtlArtY - pad_art.kShoulderRise * s;
    for (0..kH) |y| {
        var x: usize = 0;
        while (x < kW) {
            const col = img.px[y * kW + x];
            var end = x + 1;
            while (end < kW and img.px[y * kW + end] == col) end += 1;
            if (col != kClear) {
                const rgb = Rgb{ .r = @truncate(col >> 16), .g = @truncate(col >> 8), .b = @truncate(col) };
                fillRect(renderer, kCtlArtX + @as(f32, @floatFromInt(x)) * s, top + @as(f32, @floatFromInt(y)) * s, @as(f32, @floatFromInt(end - x)) * s, s, rgb);
            }
            x = end;
        }
    }
}

/// The SNES pad's twelve buttons with their keys and gamepad buttons, under
/// a drawing of the pad that lights up the one picked.
fn drawControls(renderer: *c.SDL_Renderer, ini: *const Ini, v: View) void {
    const blink = (c.SDL_GetTicks() / 267) % 2 == 0;
    const lit: ?usize = if (v.cursor < 12 and (blink or g_ctl_capture != null)) v.cursor else null;
    drawPadArt(renderer, lit);

    drawText(renderer, kCtlColKey, kCtlHeadY, kColorSection, "KEYBOARD");
    drawText(renderer, kCtlColPad, kCtlHeadY, kColorSection, "CONTROLLER");

    const keys = controls.current(ini, .keyboard);
    const pads = controls.current(ini, .gamepad);
    var row = g_ctl_top;
    while (row < @min(kCtlRows, g_ctl_top + kCtlVisible)) : (row += 1) {
        const r = ctlRowRect(row - g_ctl_top);
        const y = r.y + 3;
        const selected = row == v.cursor;
        if (selected) {
            fillRect(renderer, r.x, r.y, r.w, r.h, kColorRowHi);
            drawText(renderer, 36, y, kColorSelect, ">");
        }
        const col = if (selected) kColorSelect else kColorText;
        if (row == kCtlResetRow) {
            drawTextCentered(renderer, kWindowW / 2, y, col, "RESET ALL TO DEFAULTS", kScale);
            continue;
        }
        drawText(renderer, 56, y, col, controls.kButtonNames[row]);
        if (selected and g_ctl_capture != null) {
            drawText(renderer, kCtlColKey, y, kColorSelect, "PRESS KEY OR BUTTON");
            continue;
        }
        var kb: [8]u8 = undefined;
        drawFit(renderer, kCtlColKey, y, kColorValue, controls.keyLabel(&kb, keys.get(row)), kCtlColPad - kCtlColKey - 12);
        drawFit(renderer, kCtlColPad, y, kColorValue, controls.padLabel(pads.get(row)), kWindowW - 32 - kCtlColPad);
    }

    // A scrollbar, since there are more rows than fit.
    const track_y = kCtlRowsY - 3;
    const track_h = kRowH * kCtlVisible;
    const bar_h = track_h * kCtlVisible / @as(f32, kCtlRows);
    const bar_y = track_y + track_h * @as(f32, @floatFromInt(g_ctl_top)) / @as(f32, kCtlRows);
    fillRect(renderer, kWindowW - 30, track_y, 4, track_h, kColorFrameLo);
    fillRect(renderer, kWindowW - 30, bar_y, 4, bar_h, kColorFrameHi);
}

/// Takes the key or button pressed while a row waits. Returns the status
/// line, and says whether the ini changed.
fn ctlFinish(ini: *Ini, device: controls.Device, name: []const u8, dirty: *bool) []const u8 {
    const row = g_ctl_capture orelse return "";
    g_ctl_capture = null;
    if (device == .keyboard and controls.keyTaken(ini, name, false)) return "THAT KEY DOES SOMETHING ELSE";
    controls.assign(ini, device, row, name, false) catch return "COULD NOT CHANGE IT";
    dirty.* = true;
    return "";
}

/// The choice of randomizer: the built-in one, still to come, and seeds
/// from alttpr.com.
fn drawHub(renderer: *c.SDL_Renderer, v: View) void {
    const cx: f32 = kWindowW / 2;
    for (kHubItems, 0..) |label, i| {
        const r = hubRect(i);
        const selected = v.cursor == i;
        const soon = i == kHubBuiltIn;
        fillRect(renderer, r.x, r.y, r.w, r.h, if (soon) kColorDisabledBg else kColorRandoBg);
        if (selected) drawOutline(renderer, r.x - 8, r.y - 8, r.w + 16, r.h + 16, 4, kColorFrameHi);
        drawTextCentered(renderer, cx, r.y + 18, if (soon) kColorTextDim else kColorText, label, kScale);
        const sub = if (soon) "COMING SOON" else "PLAY A SEED FROM ALTTPR.COM";
        drawTextCentered(renderer, cx, r.y + 18 + kRowH + 8, if (soon) kColorWarn else kColorValue, sub, kScale);
    }
}

/// Text that fits: at the menu's size when there's room, half that when not.
fn drawFit(renderer: *c.SDL_Renderer, x: f32, y: f32, col: Rgb, text: []const u8, max_w: f32) void {
    if (textWidth(text, kScale) <= max_w) {
        drawText(renderer, x, y, col, text);
    } else {
        drawTextScaled(renderer, x, y + 4, col, text[0..@min(text.len, @as(usize, @intFromFloat(max_w / 8)))], 1);
    }
}

/// The seed at the top of the ALTTPR.COM page, or where to drop one.
fn drawSeedBox(renderer: *c.SDL_Renderer) void {
    for (kEmuNote, 0..) |line, i|
        drawTextCentered(renderer, kWindowW / 2, kEmuNoteY + 10 * @as(f32, @floatFromInt(i)), kColorWarn, line, 1);
    const x: f32 = 32;
    const w: f32 = kWindowW - 64;
    const y = kSeedBoxY;
    drawOutline(renderer, x, y, w, kSeedBoxH, 2, kColorFrameLo);
    const tx = x + 12;
    const max_w = w - 24;
    const line0 = y + 8;
    if (!g_seed_loaded) {
        drawTextCentered(renderer, kWindowW / 2, line0, kColorSelect, "DROP AN ALTTPR.COM SEED HERE", kScale);
        drawTextCentered(renderer, kWindowW / 2, line0 + kRowH, kColorTextDim, "GENERATE ONE AT ALTTPR.COM FROM", kScale);
        drawTextCentered(renderer, kWindowW / 2, line0 + kRowH * 2, kColorTextDim, "THE JAPANESE 1.0 ROM, THEN DRAG", kScale);
        drawTextCentered(renderer, kWindowW / 2, line0 + kRowH * 3, kColorTextDim, "THE .SFC ONTO THIS WINDOW", kScale);
        return;
    }
    const info = &g_seed_info;
    var buf: [128]u8 = undefined;
    if (!g_seed_is_seed) {
        drawFit(renderer, tx, line0, kColorSelect, g_seed_name, max_w);
        drawText(renderer, tx, line0 + kRowH, kColorWarn, "JAPANESE 1.0 ROM - NOT A SEED");
        drawText(renderer, tx, line0 + kRowH * 2, kColorTextDim, "IT PLAYS, BUT UNRANDOMIZED");
        return;
    }
    // The seed's name, which is its alttpr.com address, and its hash.
    drawFit(renderer, tx, line0, kColorSelect, info.titleText(), max_w);
    var link_buf: [64]u8 = undefined;
    const link = seedLink(&link_buf, info);
    drawTextScaled(renderer, tx + max_w - textWidth(link, 1), line0 + 4, kColorTextDim, link, 1);
    drawFit(renderer, tx, line0 + kRowH, kColorValue, hashLine(&buf, info), max_w);
    var buf2: [128]u8 = undefined;
    const summary = std.fmt.bufPrint(&buf2, "{s} - {s} - {s}", .{ info.logic, info.mode, info.goal }) catch "";
    drawFit(renderer, tx, line0 + kRowH * 2, kColorText, upper(&buf, summary), max_w);
    var buf3: [128]u8 = undefined;
    const counts = std.fmt.bufPrint(&buf3, "GT {d}  GANON {d}  {d} ITEMS{s}", .{
        info.tower_crystals,
        info.ganon_crystals,
        info.total_items,
        if (g_seed_has_save) "  SAVE FOUND" else "",
    }) catch "";
    drawFit(renderer, tx, line0 + kRowH * 3, kColorTextDim, counts, max_w);
}

/// Where the seed lives on alttpr.com: its title is "VT " and its hash.
fn seedLink(buf: []u8, info: *const seed_info.Info) []const u8 {
    const title = info.titleText();
    const hash = if (std.mem.startsWith(u8, title, "VT ")) title[3..] else title;
    return std.fmt.bufPrint(buf, "alttpr.com/h/{s}", .{hash}) catch "";
}

/// The seed's five hash icons by name, the way alttpr.com shows them.
fn hashLine(buf: []u8, info: *const seed_info.Info) []const u8 {
    var n: usize = 0;
    for (info.hash, 0..) |h, i| {
        const name = seed_info.kHashIcons[h];
        if (n + name.len + 1 > buf.len) break;
        if (i != 0) {
            buf[n] = ' ';
            n += 1;
        }
        for (name) |ch| {
            buf[n] = std.ascii.toUpper(ch);
            n += 1;
        }
    }
    return buf[0..n];
}

fn upper(buf: []u8, text: []const u8) []const u8 {
    const n = @min(buf.len, text.len);
    for (text[0..n], 0..) |ch, i| buf[i] = std.ascii.toUpper(ch);
    return buf[0..n];
}

/// One line of the seed details: a label and its value, or a heading when
/// there's no value.
const DetailLine = struct { label: []const u8, value: []const u8 = "", color: Rgb = kColorValue, heading: bool = false };

fn yesNo(b: bool) []const u8 {
    return if (b) "YES" else "NO";
}

/// Everything the seed says about itself, as lines; the spoilers only when
/// they've been asked for.
fn detailLines(out: []DetailLine, bufs: [][40]u8) []DetailLine {
    const info = &g_seed_info;
    var n: usize = 0;
    var b: usize = 0;
    const add = struct {
        fn f(o: []DetailLine, k: *usize, l: DetailLine) void {
            if (k.* < o.len) {
                o[k.*] = l;
                k.* += 1;
            }
        }
    }.f;
    const up = struct {
        fn f(bs: [][40]u8, k: *usize, text: []const u8) []const u8 {
            if (k.* >= bs.len) return text;
            const r = upper(&bs[k.*], text);
            k.* += 1;
            return r;
        }
    }.f;
    const num = struct {
        fn f(bs: [][40]u8, k: *usize, v: u32) []const u8 {
            if (k.* >= bs.len) return "?";
            const r = std.fmt.bufPrint(&bs[k.*], "{d}", .{v}) catch "?";
            k.* += 1;
            return r;
        }
    }.f;

    add(out, &n, .{ .label = "SEED", .color = kColorSection, .heading = true });
    add(out, &n, .{ .label = "Title", .value = info.titleText() });
    var link_buf: [64]u8 = undefined;
    add(out, &n, .{ .label = "Plays In", .value = "SNES EMULATOR" });
    add(out, &n, .{ .label = "Link", .value = if (b < bufs.len) blk: {
        const l = seedLink(&link_buf, info);
        const m = @min(l.len, bufs[b].len);
        @memcpy(bufs[b][0..m], l[0..m]);
        b += 1;
        break :blk bufs[b - 1][0..m];
    } else "?" });
    add(out, &n, .{ .label = "File", .value = g_seed_name });
    add(out, &n, .{ .label = "Size", .value = if (b < bufs.len) blk: {
        const r = std.fmt.bufPrint(&bufs[b], "{d} KB", .{g_seed_size / 1024}) catch "?";
        b += 1;
        break :blk r;
    } else "?" });
    add(out, &n, .{ .label = "Save File", .value = if (g_seed_has_save) "FOUND BESIDE THE SEED" else "NONE YET" });
    add(out, &n, .{ .label = "MSU-1 Pack", .value = g_msu_game_path });
    add(out, &n, .{ .label = "HASH", .color = kColorSection, .heading = true });
    for (info.hash, 0..) |h, i| {
        const labels = [_][]const u8{ "Icon 1", "Icon 2", "Icon 3", "Icon 4", "Icon 5" };
        add(out, &n, .{ .label = labels[i], .value = up(bufs, &b, seed_info.kHashIcons[h]) });
    }
    add(out, &n, .{ .label = "SETTINGS", .color = kColorSection, .heading = true });
    add(out, &n, .{ .label = "Logic", .value = up(bufs, &b, info.logic) });
    add(out, &n, .{ .label = "Game", .value = up(bufs, &b, info.game_type) });
    add(out, &n, .{ .label = "Mode", .value = up(bufs, &b, info.mode) });
    add(out, &n, .{ .label = "Goal", .value = up(bufs, &b, info.goal) });
    if (info.goal_count != 0) add(out, &n, .{ .label = "Pieces Needed", .value = num(bufs, &b, info.goal_count) });
    add(out, &n, .{ .label = "GT Crystals", .value = num(bufs, &b, info.tower_crystals) });
    add(out, &n, .{ .label = "Ganon Crystals", .value = num(bufs, &b, info.ganon_crystals) });
    add(out, &n, .{ .label = "Item Locations", .value = num(bufs, &b, info.total_items) });
    add(out, &n, .{ .label = "Swords", .value = if (info.swordless) "SWORDLESS" else "RANDOMIZED" });
    add(out, &n, .{ .label = "Maps/Compasses", .value = if (info.shuffled_maps_compasses) "SHUFFLED" else "IN DUNGEON" });
    add(out, &n, .{ .label = "Small Keys", .value = if (info.retro_keys) "RETRO" else if (info.shuffled_keys) "SHUFFLED" else "IN DUNGEON" });
    add(out, &n, .{ .label = "Big Keys", .value = if (info.shuffled_big_keys) "SHUFFLED" else "IN DUNGEON" });
    add(out, &n, .{ .label = "Tournament", .value = yesNo(info.tournament) });
    add(out, &n, .{ .label = "GAMEPLAY", .color = kColorSection, .heading = true });
    add(out, &n, .{ .label = "Item Quickswap", .value = yesNo(info.quickswap) });
    add(out, &n, .{ .label = "Pseudo Boots", .value = yesNo(info.pseudo_boots) });
    add(out, &n, .{ .label = "Silver Arrows", .value = up(bufs, &b, info.silvers) });
    add(out, &n, .{ .label = "Menu Speed", .value = up(bufs, &b, info.menu_speed) });
    add(out, &n, .{ .label = "Heart Beep", .value = up(bufs, &b, info.heart_beep) });
    add(out, &n, .{ .label = "Heart Color", .value = up(bufs, &b, info.heart_color) });
    add(out, &n, .{ .label = "Clock", .value = up(bufs, &b, info.timer) });
    add(out, &n, .{ .label = "STARTING ITEMS", .color = kColorSection, .heading = true });
    var names: [32][]const u8 = undefined;
    const start = seed_info.startingItems(info, &names);
    if (start.len == 0) add(out, &n, .{ .label = "None" });
    for (start) |name| add(out, &n, .{ .label = name });

    add(out, &n, .{ .label = "SPOILERS", .color = kColorWarn, .heading = true });
    if (!g_spoilers) {
        add(out, &n, .{ .label = "Hidden - A/ENTER shows them", .color = kColorTextDim });
        return out[0..n];
    }
    add(out, &n, .{ .label = "Misery Mire", .value = up(bufs, &b, seed_info.medallionName(info.misery_mire)) });
    add(out, &n, .{ .label = "Turtle Rock", .value = up(bufs, &b, seed_info.medallionName(info.turtle_rock)) });
    for (seed_info.kPrizeDungeons, 0..) |d, i| {
        add(out, &n, .{ .label = d.name, .value = up(bufs, &b, seed_info.prizeName(info.prizes[i])) });
    }
    return out[0..n];
}

const kDetailsRows = 15;

fn detailCount() usize {
    var lines: [96]DetailLine = undefined;
    var bufs: [64][40]u8 = undefined;
    return detailLines(&lines, &bufs).len;
}

/// The game's MSUPath as the details show it, from the ini being edited.
var g_msu_game_path: []const u8 = "NOT SET";
var g_msu_game_path_buf: [40]u8 = undefined;

fn setMsuGamePath(ini: *const Ini) void {
    const i = settingIndex("Sound", "MSUPath") orelse return;
    const path = std.mem.trim(u8, ini.values[i] orelse "", " ");
    g_msu_game_path = if (path.len == 0) "NOT SET" else blk: {
        // The end of a long path says more than its start.
        const tail = path[path.len -| g_msu_game_path_buf.len..];
        @memcpy(g_msu_game_path_buf[0..tail.len], tail);
        break :blk g_msu_game_path_buf[0..tail.len];
    };
}

fn drawDetails(renderer: *c.SDL_Renderer, v: View) void {
    var lines: [96]DetailLine = undefined;
    var bufs: [64][40]u8 = undefined;
    const all = detailLines(&lines, &bufs);
    var y: f32 = kListStartY;
    const top = @min(v.details_top, all.len);
    for (all[top..@min(all.len, top + kDetailsRows)]) |l| {
        if (l.heading) {
            var ub: [64]u8 = undefined;
            drawText(renderer, 40, y, l.color, upper(&ub, l.label));
        } else if (l.value.len == 0) {
            var ub: [64]u8 = undefined;
            drawText(renderer, 56, y, l.color, upper(&ub, l.label));
        } else {
            var ub: [64]u8 = undefined;
            drawText(renderer, 56, y, kColorText, upper(&ub, l.label));
            drawFit(renderer, 300, y, l.color, l.value, kWindowW - 300 - 32);
        }
        y += kRowH;
    }
    // Say there's more, when there is.
    if (top + kDetailsRows < all.len) drawTextScaled(renderer, kWindowW - 64, y - kRowH, kColorTextDim, "V", kScale);
    if (top > 0) drawTextScaled(renderer, kWindowW - 64, kListStartY, kColorTextDim, "^", kScale);
}

fn drawList(renderer: *c.SDL_Renderer, ini: *const Ini, v: View) void {
    const n = rowCount(v.screen);
    var y: f32 = listStartY(v.screen);
    var p = v.top;
    while (p < n and p < v.top + visibleRows(v.screen)) : (p += 1) {
        const at = rowAt(v.screen, p);
        const selected = p == v.cursor;
        if (at >= kSettings.len) {
            // The page's two buttons, which only work with a seed.
            if (selected) fillRect(renderer, 32, y - 3, kWindowW - 64, kRowH, kColorRowHi);
            const label = if (at == kPlayRow) "PLAY THIS SEED" else "SEED DETAILS";
            const col = if (!g_seed_loaded) kColorTextDim else if (selected) kColorSelect else if (at == kPlayRow) kColorOk else kColorText;
            drawTextCentered(renderer, kWindowW / 2, y, col, label, kScale);
        } else if (isSection(kSettings[at])) {
            drawText(renderer, 40, y, kColorSection, kSettings[at].label);
        } else {
            const s = kSettings[at];
            if (selected) {
                fillRect(renderer, 32, y - 3, kWindowW - 64, kRowH, kColorRowHi);
                drawText(renderer, 36, y, kColorSelect, ">");
            }
            drawText(renderer, 56, y, if (selected) kColorSelect else kColorText, s.label);
            var vbuf: [64]u8 = undefined;
            const shown = displayValue(&vbuf, s, ini.values[at] orelse "(missing)");
            const dim = s.kind == .text;
            drawText(renderer, 400, y, if (dim) kColorTextDim else kColorValue, shown);
        }
        y += kRowH;
    }
    // A scrollbar, since the ALTTPR.COM page runs past the bottom.
    const shown = visibleRows(v.screen);
    if (n > shown) {
        const track_y = listStartY(v.screen) - 3;
        const track_h = kRowH * @as(f32, @floatFromInt(shown));
        const nf: f32 = @floatFromInt(n);
        const bar_h = track_h * @as(f32, @floatFromInt(shown)) / nf;
        const bar_y = track_y + track_h * @as(f32, @floatFromInt(v.top)) / nf;
        fillRect(renderer, kWindowW - 30, track_y, 4, track_h, kColorFrameLo);
        fillRect(renderer, kWindowW - 30, bar_y, 4, bar_h, kColorFrameHi);
    }
}

/// Where the modal's panel sits, and where its two answers sit inside it.
fn modalRect() Rect {
    return .{ .x = 70, .y = 150, .w = kWindowW - 140, .h = 190 };
}

fn modalChoiceRect(i: usize) Rect {
    const box = modalRect();
    const w: f32 = 150;
    const gap: f32 = 30;
    const total = w * 2 + gap;
    const x = box.x + (box.w - total) / 2 + (w + gap) * @as(f32, @floatFromInt(i));
    return .{ .x = x, .y = box.y + box.h - 66, .w = w, .h = kRowH + 16 };
}

fn drawModal(renderer: *c.SDL_Renderer, v: View) void {
    const box = modalRect();
    const cx = box.x + box.w / 2;

    // A frame paints its own interior, which is what blanks the menu behind.
    drawFrame(renderer, box.x, box.y, box.w, box.h);

    switch (v.modal) {
        .quit => {
            drawTextCentered(renderer, cx, box.y + 34, kColorSelect, "QUIT THE GAME?", kScale);
            if (v.dirty)
                drawTextCentered(renderer, cx, box.y + 34 + kRowH, kColorWarn, "UNSAVED CHANGES WILL BE LOST", kScale);

            for (kQuitChoices, 0..) |label, i| {
                const r = modalChoiceRect(i);
                const selected = i == v.quit_choice;
                if (selected) fillRect(renderer, r.x, r.y, r.w, r.h, kColorRowHi);
                drawOutline(renderer, r.x, r.y, r.w, r.h, 2, if (selected) kColorFrameHi else kColorFrameLo);
                drawTextCentered(renderer, r.x + r.w / 2, r.y + 8, if (selected) kColorSelect else kColorText, label, kScale);
            }
        },
        .rom => {
            drawTextCentered(renderer, cx, box.y + 26, kColorSelect, "DROP A ROM ON THIS WINDOW", kScale);
            drawTextCentered(renderer, cx, box.y + 26 + kRowH, kColorTextDim, "ANY .SFC FILE - THE NAME DOES", kScale);
            drawTextCentered(renderer, cx, box.y + 26 + kRowH * 2, kColorTextDim, "NOT MATTER, IT IS CHECKED", kScale);

            // Offer the one already sitting beside the game, if there is one.
            if (g_rom_path != null) {
                drawTextCentered(renderer, cx, box.y + 120, kColorText, "OR PRESS A/ENTER TO USE", kScale);
                drawTextCentered(renderer, cx, box.y + 120 + kRowH, kColorValue, kRomPath, kScale);
            } else {
                drawTextCentered(renderer, cx, box.y + 130, kColorTextDim, "B/ESC TO CANCEL", kScale);
            }
        },
        .none => {},
    }
}

fn drawFooter(renderer: *c.SDL_Renderer, v: View) void {
    const footer_y: f32 = kWindowH - 32 - kRowH * 2 - 6;

    // While a question is up the keys mean something else, so say that
    // instead of the screen underneath's hints.
    if (v.modal != .none) {
        switch (v.modal) {
            .quit => {
                drawText(renderer, 40, footer_y, kColorTextDim, "LEFT/RIGHT CHOOSE");
                drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "A/ENTER CONFIRM   B/ESC CANCEL");
            },
            .rom => {
                drawText(renderer, 40, footer_y, kColorTextDim, "DROP A FILE ON THE WINDOW");
                drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "B/ESC CANCEL");
            },
            .none => {},
        }
        if (v.status.len != 0)
            drawText(renderer, 40, footer_y - kRowH, kColorSection, v.status);
        return;
    }

    switch (v.screen) {
        .main => {
            drawText(renderer, 40, footer_y, kColorTextDim, "SELECT A/ENTER   SAVE X/S");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "QUIT B/ESC");
        },
        .settings, .features => {
            drawText(renderer, 40, footer_y, kColorTextDim, "CHANGE  LEFT/RIGHT OR A");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "SAVE X/S   BACK B/ESC");
        },
        .hub => {
            drawText(renderer, 40, footer_y, kColorTextDim, "SELECT A/ENTER");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "BACK B/ESC");
        },
        .controls => if (g_ctl_capture != null) {
            drawText(renderer, 40, footer_y, kColorTextDim, "PRESS ANY KEY OR PAD BUTTON");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "ESC OR WAIT TO CANCEL");
        } else {
            drawText(renderer, 40, footer_y, kColorTextDim, "CHANGE A/ENTER");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "SAVE X/S   BACK B/ESC");
        },
        .alttpr => {
            drawText(renderer, 40, footer_y, kColorTextDim, "CHANGE  LEFT/RIGHT OR A");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "PLAY START  SAVE X/S  BACK B");
        },
        .details => {
            drawText(renderer, 40, footer_y, kColorTextDim, "SCROLL UP/DOWN");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "SPOILERS A/ENTER   BACK B/ESC");
        },
    }

    // What the selected setting can't say in its label.
    if (v.status.len == 0 and v.screen == .alttpr) {
        const at = rowAt(.alttpr, v.cursor);
        const note = if (at < kSettings.len) kSettings[at].note else if (!g_seed_loaded) "DROP A SEED ON THIS WINDOW FIRST" else "";
        if (note.len != 0) {
            drawText(renderer, 40, footer_y - kRowH, kColorWarn, note);
            return;
        }
    }

    // One line above the footer, in order of what the player most needs to
    // know: what just happened, then that there are edits worth saving.
    if (v.status.len != 0)
        drawText(renderer, 40, footer_y - kRowH, kColorSection, v.status)
    else if (v.dirty)
        drawText(renderer, 40, footer_y - kRowH, kColorSelect, "UNSAVED CHANGES");
}

/// Where the ROM was found: beside the game, or in the directory the
/// launcher was started from. Null when there is none to be had. The path
/// points into g_rom_buf, which is why that is not a local.
var g_rom_path: ?[:0]const u8 = null;
var g_rom_buf: [4096]u8 = undefined;

/// Looks for the ROM beside the game first, then where the launcher was
/// started. Building assets is a one-off, and making someone move a file to
/// do it is a poor greeting.
fn findRom(start_dir: []const u8, buf: []u8) ?[:0]const u8 {
    if (fileio.exists(kRomPath)) return kRomPath;

    const joined = std.fmt.bufPrintZ(buf, "{s}/{s}", .{ start_dir, kRomPath }) catch return null;
    if (fileio.exists(joined.ptr)) return joined;
    return null;
}

/// True for a path ending in a SNES ROM extension, whatever it is called.
/// .smc is accepted alongside .sfc because it is the same image with a copier
/// header, which the loader strips; the hash check below is the real gate.
fn looksLikeRom(path: []const u8) bool {
    if (path.len < 4) return false;
    const ext = path[path.len - 4 ..];
    return std.ascii.eqlIgnoreCase(ext, ".sfc") or std.ascii.eqlIgnoreCase(ext, ".smc");
}

fn regionName(lang: rom_mod.Language) []const u8 {
    return switch (lang) {
        .us => "US",
        .de => "GERMAN",
        .fr, .fr_c => "FRENCH",
        .en => "ENGLISH",
        .es => "SPANISH",
        .pl => "POLISH",
        .pt => "PORTUGUESE",
        .redux => "REDUX",
        .nl => "DUTCH",
        .sv => "SWEDISH",
    };
}

/// Builds the assets from a ROM the user dropped on the window. The name is
/// not trusted: the file is identified by hashing it, the same way the
/// Python tool does, and only the US release can be built from.
fn buildAssetsFromDrop(alloc: std.mem.Allocator, path: [*:0]const u8) []const u8 {
    if (!looksLikeRom(std.mem.span(path))) return "NOT A .SFC FILE";

    var rom = rom_mod.Rom.load(alloc, path) catch return "COULD NOT READ THAT FILE";
    defer rom.deinit();

    const lang = rom.language orelse return "UNRECOGNIZED ROM";
    if (lang != .us) {
        // Naming the region makes it obvious this is the wrong dump rather
        // than a corrupt one.
        g_status_buf = undefined;
        return std.fmt.bufPrint(&g_status_buf, "{s} ROM - NEEDS THE US ONE", .{regionName(lang)}) catch
            "WRONG REGION - NEEDS THE US ROM";
    }

    const data = asset_all.buildFile(alloc, rom) catch return "COULD NOT BUILD ASSETS";
    defer alloc.free(data);
    fileio.writeWholeFile(kAssetsPath, data) catch return "COULD NOT WRITE ASSETS";

    // Remember it, so B works later without another drop.
    const span = std.mem.span(path);
    if (span.len < g_rom_buf.len) {
        @memcpy(g_rom_buf[0..span.len], span);
        g_rom_buf[span.len] = 0;
        g_rom_path = g_rom_buf[0..span.len :0];
    }
    return "US ROM VERIFIED - ASSETS BUILT";
}

/// Backing store for status lines that are built at runtime.
var g_status_buf: [64]u8 = undefined;

/// Builds zelda3_assets.dat from the ROM, replacing what the old Python resource
/// tool did. Returns a message for the status line either way.
fn buildAssets(alloc: std.mem.Allocator) []const u8 {
    const path = g_rom_path orelse return "NEED " ++ kRomPath ++ " TO BUILD ASSETS";

    var rom = rom_mod.Rom.load(alloc, path.ptr) catch return "COULD NOT READ ROM";
    defer rom.deinit();
    if (rom.language != .us) return "ROM IS NOT THE US RELEASE";

    const data = asset_all.buildFile(alloc, rom) catch return "COULD NOT BUILD ASSETS";
    defer alloc.free(data);

    fileio.writeWholeFile(kAssetsPath, data) catch return "COULD NOT WRITE ASSETS";
    return kAssetsBuilt;
}

const kAssetsBuilt = "ASSETS BUILT";

/// Prints what SDL makes of every pad plugged in: its name, and which label
/// is printed on each face button. Face buttons are routed by label, so this
/// is the thing to look at when a button does the wrong job.
pub fn reportPads() void {
    configureJoysticks();
    if (!c.SDL_Init(c.SDL_INIT_GAMEPAD)) {
        std.debug.print("could not start SDL: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_Quit();

    var count: c_int = 0;
    const ids = c.SDL_GetGamepads(&count) orelse {
        std.debug.print("no gamepads\n", .{});
        return;
    };
    defer c.SDL_free(ids);

    if (count == 0) std.debug.print("no gamepads\n", .{});

    for (ids[0..@intCast(count)]) |id| {
        const pad = c.SDL_OpenGamepad(id) orelse continue;
        defer c.SDL_CloseGamepad(pad);

        const name: []const u8 = if (c.SDL_GetGamepadName(pad)) |n| std.mem.span(n) else "(unnamed)";
        const kind = c.SDL_GetGamepadType(pad);
        const real = c.SDL_GetRealGamepadType(pad);
        std.debug.print("{s}  (type {d}, real type {d})\n", .{ name, kind, real });
        std.debug.print("  axes: LEFTX={d} LEFTY={d} RIGHTX={d} RIGHTY={d}\n", .{
            c.SDL_GetGamepadAxis(pad, c.SDL_GAMEPAD_AXIS_LEFTX),
            c.SDL_GetGamepadAxis(pad, c.SDL_GAMEPAD_AXIS_LEFTY),
            c.SDL_GetGamepadAxis(pad, c.SDL_GAMEPAD_AXIS_RIGHTX),
            c.SDL_GetGamepadAxis(pad, c.SDL_GAMEPAD_AXIS_RIGHTY),
        });
        std.debug.print("  has LEFTX={} LEFTY={}\n", .{
            c.SDL_GamepadHasAxis(pad, c.SDL_GAMEPAD_AXIS_LEFTX),
            c.SDL_GamepadHasAxis(pad, c.SDL_GAMEPAD_AXIS_LEFTY),
        });

        for ([_]struct { pos: []const u8, button: c_int }{
            .{ .pos = "south", .button = c.SDL_GAMEPAD_BUTTON_SOUTH },
            .{ .pos = "east", .button = c.SDL_GAMEPAD_BUTTON_EAST },
            .{ .pos = "west", .button = c.SDL_GAMEPAD_BUTTON_WEST },
            .{ .pos = "north", .button = c.SDL_GAMEPAD_BUTTON_NORTH },
        }) |b| {
            const label = c.SDL_GetGamepadButtonLabel(pad, @intCast(b.button));
            const printed: []const u8 = switch (label) {
                c.SDL_GAMEPAD_BUTTON_LABEL_A => "A",
                c.SDL_GAMEPAD_BUTTON_LABEL_B => "B",
                c.SDL_GAMEPAD_BUTTON_LABEL_X => "X",
                c.SDL_GAMEPAD_BUTTON_LABEL_Y => "Y",
                c.SDL_GAMEPAD_BUTTON_LABEL_CROSS => "cross",
                c.SDL_GAMEPAD_BUTTON_LABEL_CIRCLE => "circle",
                c.SDL_GAMEPAD_BUTTON_LABEL_SQUARE => "square",
                c.SDL_GAMEPAD_BUTTON_LABEL_TRIANGLE => "triangle",
                else => "unknown",
            };
            const does: []const u8 = switch (faceAction(c.SDL_GetGamepadID(pad), @intCast(b.button))) {
                .confirm => "select",
                .back => "back",
                .save => "save",
                .none => "-",
            };
            std.debug.print("  {s:<6} labeled {s:<8} does {s}\n", .{ b.pos, printed, does });
        }
    }
}

/// A macOS .app bundle and a mounted AppImage are read-only, so the ini, the
/// assets and the saves cannot sit beside the executable there. True when
/// running from either. Inside a bundle SDL reports Contents/Resources as the
/// base path; an AppImage's runtime sets APPIMAGE.
pub fn isPackaged(base: []const u8) bool {
    if (builtin.os.tag == .macos) return std.mem.endsWith(u8, base, ".app/Contents/Resources/");
    if (std.mem.startsWith(u8, base, "/nix/store/")) return true;
    if (builtin.os.tag == .linux) return c.SDL_getenv("APPIMAGE") != null;
    return false;
}

/// Moves into the directory the game keeps its files in, whatever directory it
/// was started from, and remembers where to look for a ROM. That is the
/// executable's own directory for a plain install, or the per-user data
/// directory (~/Library/Application Support/alttp-zig on macOS,
/// ~/.local/share/alttp-zig on Linux) for an app bundle or AppImage. A missing
/// zelda3.ini is written out from the copy built into the game.
pub fn enterDataDirectory() void {
    var start_dir_buf: [4096]u8 = undefined;
    const start_dir = fileio.workingDirectory(&start_dir_buf) catch ".";

    if (c.SDL_GetBasePath()) |base_z| {
        const base = std.mem.span(base_z);
        if (isPackaged(base)) {
            // SDL creates the directory if it is not there yet.
            if (c.SDL_GetPrefPath("", "alttp-zig")) |pref| {
                defer c.SDL_free(pref);
                fileio.setWorkingDirectory(pref) catch {};
            } else {
                std.debug.print("No data directory: {s}\n", .{c.SDL_GetError()});
            }
        } else {
            fileio.setWorkingDirectory(base_z) catch {};
        }
    }

    if (!fileio.exists("zelda3.ini")) {
        fileio.writeWholeFile("zelda3.ini", kDefaultIni) catch |err| {
            std.debug.print("Could not write zelda3.ini: {s}\n", .{@errorName(err)});
        };
    }

    g_rom_path = findRom(start_dir, &g_rom_buf);
}

extern fn puts(s: [*:0]const u8) c_int;

/// The directory enterDataDirectory settled on, for --data-dir. On stdout,
/// so a script can capture it.
pub fn printDataDirectory() void {
    var buf: [4096]u8 = undefined;
    const dir = fileio.workingDirectory(&buf) catch ".";
    _ = puts(dir.ptr);
}

/// Builds the asset file without opening a window, for scripts and for
/// checking the result against the old Python tool's output. False when nothing
/// was built, even if an older asset file is sitting there.
pub fn buildAssetsFromCommandLine(alloc: std.mem.Allocator) bool {
    const msg = buildAssets(alloc);
    std.debug.print("{s}\n", .{msg});
    return msg.ptr == kAssetsBuilt.ptr;
}

/// Whether zelda3.ini asks for the start menu. Missing or unreadable counts as
/// yes, since the menu is the way back to a working setup.
pub fn wantsStartMenu(alloc: std.mem.Allocator) bool {
    var ini = Ini.load(alloc, "zelda3.ini") catch return true;
    defer ini.deinit();
    const at = settingIndex("General", "StartMenu") orelse return true;
    const value = ini.values[at] orelse return true;
    return !std.mem.eql(u8, std.mem.trim(u8, value, " \t"), "0");
}

pub fn settingIndex(section: []const u8, key: []const u8) ?usize {
    for (kSettings, 0..) |st, i| {
        if (std.mem.eql(u8, st.section, section) and std.mem.eql(u8, st.key, key)) return i;
    }
    return null;
}

pub const Outcome = enum { play, quit, randomizer };

/// The seed dropped on the menu, when the outcome is .randomizer.
pub var g_randomizer_rom: [:0]const u8 = "";
var g_randomizer_buf: [4096]u8 = undefined;

fn setRandomizerRom(span: []const u8) void {
    const n = @min(span.len, g_randomizer_buf.len - 1);
    @memcpy(g_randomizer_buf[0..n], span[0..n]);
    g_randomizer_buf[n] = 0;
    g_randomizer_rom = g_randomizer_buf[0..n :0];
}

/// Whether a dropped file is a randomizer seed (or the Japanese ROM they
/// start from), which plays in the emulator instead of building assets.
pub fn isRandomizerRom(path: []const u8) bool {
    if (!looksLikeRom(path) or path.len >= g_randomizer_buf.len) return false;
    var z: [4096:0]u8 = undefined;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    const data = fileio.readWholeFile(std.heap.c_allocator, &z) catch return false;
    defer std.heap.c_allocator.free(data);
    return @import("emu.zig").romKind(data) != .other;
}

// The seed on the ALTTPR.COM page, once one has been dropped there.
var g_seed_loaded = false;
/// A real seed, rather than the Japanese ROM seeds are made from.
var g_seed_is_seed = false;
var g_seed_info: seed_info.Info = .{};
var g_seed_name: []const u8 = "";
var g_seed_size: usize = 0;
var g_seed_has_save = false;
var g_spoilers = false;
var g_details_top: usize = 0;
var g_hub_cursor: usize = kHubAlttpr;

fn fileExists(path: []const u8) bool {
    var z: [4200:0]u8 = undefined;
    if (path.len >= z.len) return false;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    const f = std.c.fopen(&z, "rb") orelse return false;
    _ = std.c.fclose(f);
    return true;
}

/// Reads a seed for the ALTTPR.COM page. False, and nothing changed, when the
/// file isn't one.
fn loadSeed(path: []const u8) bool {
    if (!looksLikeRom(path) or path.len >= g_randomizer_buf.len) return false;
    var z: [4096:0]u8 = undefined;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    const data = fileio.readWholeFile(std.heap.c_allocator, &z) catch return false;
    defer std.heap.c_allocator.free(data);
    const kind = @import("emu.zig").romKind(data);
    if (kind == .other) return false;

    setRandomizerRom(path);
    g_seed_loaded = true;
    g_seed_is_seed = kind == .randomizer;
    g_seed_info = seed_info.read(data);
    g_seed_name = std.fs.path.basename(g_randomizer_rom);
    g_seed_size = data.len;
    g_spoilers = false;
    g_details_top = 0;
    // Whether it has been played before.
    const ext = std.fs.path.extension(g_randomizer_rom);
    const stem = g_randomizer_rom[0 .. g_randomizer_rom.len - ext.len];
    var buf: [4200]u8 = undefined;
    g_seed_has_save = fileExists(std.fmt.bufPrint(&buf, "{s}.srm", .{stem}) catch "");
    return true;
}

/// Runs the start menu until the player picks Play or leaves. SDL is started
/// and shut down in here, so the game sets it up afresh for its own window.
/// With assets that are missing or don't match, it opens on the ROM question,
/// and Play won't hand over to the game until the asset file checks out.
pub fn run(alloc: std.mem.Allocator, seed: ?[]const u8) !Outcome {
    var ini = Ini.load(alloc, "zelda3.ini") catch |err| {
        std.debug.print("Could not read zelda3.ini: {s}\n", .{@errorName(err)});
        return err;
    };
    defer ini.deinit();

    configureJoysticks();
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD)) {
        std.debug.print("Failed to init SDL: {s}\n", .{c.SDL_GetError()});
        return error.SdlInit;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("The Legend of Zelda: A Link to the Past", kWindowW, kWindowH, 0) orelse {
        std.debug.print("Failed to create window: {s}\n", .{c.SDL_GetError()});
        return error.SdlWindow;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, null) orelse {
        std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
        return error.SdlRenderer;
    };
    defer c.SDL_DestroyRenderer(renderer);

    // Any pad can drive the menu, and one plugged in later works too.
    var pads = Pads{};
    defer pads.closeAll();
    var pad_count: c_int = 0;
    if (c.SDL_GetGamepads(&pad_count)) |ids| {
        for (ids[0..@intCast(pad_count)]) |id| pads.open(id);
        c.SDL_free(ids);
    }

    var vrepeat = Repeat{};
    var hrepeat = Repeat{};
    var modal: Modal = .none;
    var quit_choice: usize = kQuitStay;
    var held = Held{};

    var screen: Screen = .main;
    var main_cursor: usize = 0;
    // Each list keeps its own place, so stepping out and back in does not
    // dump the cursor at the top again.
    var list_cursor = [_]usize{ firstRow(.settings), firstRow(.features), firstRow(.alttpr) };
    var list_top = [_]usize{ 0, 0, 0 };
    var dirty = false;
    var launch = false;
    var randomizer = false;
    var status: []const u8 = "";
    var assets = checkAssets(alloc);
    if (seed != null and loadSeed(seed.?)) {
        // Started with a seed: its page comes first, on Play, and assets
        // don't matter to it.
        screen = .alttpr;
    } else if (assets != .verified) {
        modal = .rom;
        main_cursor = kMainLaunch;
    }
    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        const now = c.SDL_GetTicks();
        var confirm = false;
        var start = false;
        var back = false;
        var save = false;
        var build = false;
        // Presses arrive as events so that a tap shorter than a frame still
        // counts; the poll below only decides when a held direction repeats.
        var tap_v: i32 = 0;
        var tap_h: i32 = 0;
        var hover_x: f32 = 0;
        var hover_y: f32 = 0;
        var hovered = false;
        var clicked = false;
        var wheel: f32 = 0;

        while (c.SDL_PollEvent(&event)) {
            // The Controls screen waiting for a key or button takes the next
            // press whole, before it can move the cursor or back out.
            if (g_ctl_capture != null and screen == .controls and modal == .none) {
                switch (event.type) {
                    c.SDL_EVENT_KEY_DOWN => {
                        if (event.key.repeat) continue;
                        if (event.key.key == c.SDLK_ESCAPE) {
                            g_ctl_capture = null;
                            status = "NOTHING CHANGED";
                        } else {
                            status = ctlFinish(&ini, .keyboard, std.mem.span(c.SDL_GetKeyName(event.key.key)), &dirty);
                        }
                        continue;
                    },
                    c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => {
                        _ = held.setButton(event.gbutton.button, true);
                        const b = config.gamepadButtonFromSdl(event.gbutton.button);
                        if (b >= 0) status = ctlFinish(&ini, .gamepad, config.gamepadButtonName(b), &dirty);
                        continue;
                    },
                    c.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
                        const b = config.gamepadTriggerFromSdl(event.gaxis.axis, event.gaxis.value);
                        if (b >= 0) status = ctlFinish(&ini, .gamepad, config.gamepadButtonName(b), &dirty);
                        continue;
                    },
                    else => {},
                }
            }
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_GAMEPAD_ADDED => pads.open(event.gdevice.which),
                c.SDL_EVENT_GAMEPAD_REMOVED => pads.close(event.gdevice.which),

                // A ROM dropped on the window is the quickest path from a
                // fresh checkout to a playable game.
                c.SDL_EVENT_DROP_FILE => {
                    var handled = false;
                    if (event.drop.data) |path| {
                        const span = std.mem.span(path);
                        const rando_page = screen == .hub or screen == .alttpr or screen == .details;
                        if (rando_page) {
                            // Seeds go here, and only seeds.
                            handled = true;
                            if (loadSeed(span)) {
                                screen = .alttpr;
                                list_cursor[listIndex(.alttpr)] = 0;
                                list_top[listIndex(.alttpr)] = 0;
                                status = if (g_seed_is_seed) "SEED LOADED" else "JAPANESE ROM LOADED";
                            } else {
                                status = if (looksLikeRom(span)) "NOT AN ALTTPR.COM SEED" else "NOT A .SFC FILE";
                            }
                            modal = .none;
                        } else if (isRandomizerRom(span)) {
                            // The main menu's drops are for the port's assets.
                            handled = true;
                            status = "SEEDS GO ON THE RANDOMIZER PAGE";
                        }
                    }
                    if (!handled) if (event.drop.data) |path| {
                        status = "CHECKING ROM...";
                        drawScreen(renderer, &ini, viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice));
                        status = buildAssetsFromDrop(alloc, path);
                        assets = checkAssets(alloc);
                        // A drop that worked answers the question; one that
                        // did not leaves it up so another can be tried.
                        if (assets == .verified) modal = .none;
                    };
                },

                // The mouse drives the same cursor the keys do, so nothing
                // needs its own notion of what is selected.
                c.SDL_EVENT_MOUSE_MOTION => {
                    hover_x = event.motion.x;
                    hover_y = event.motion.y;
                    hovered = true;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    hover_x = event.button.x;
                    hover_y = event.button.y;
                    hovered = true;
                    if (event.button.button == c.SDL_BUTTON_LEFT) clicked = true;
                    if (event.button.button == c.SDL_BUTTON_RIGHT) back = true;
                },
                c.SDL_EVENT_MOUSE_WHEEL => wheel += event.wheel.y,

                // Anything that stops the window seeing releases has to
                // clear what it thinks is held, or a direction sticks on.
                c.SDL_EVENT_WINDOW_FOCUS_LOST => held = .{},

                c.SDL_EVENT_KEY_DOWN => {
                    if (held.set(event.key.key, true)) {
                        switch (event.key.key) {
                            c.SDLK_UP => tap_v -= 1,
                            c.SDLK_DOWN => tap_v += 1,
                            c.SDLK_LEFT => tap_h -= 1,
                            c.SDLK_RIGHT => tap_h += 1,
                            else => {},
                        }
                    } else switch (event.key.key) {
                        c.SDLK_ESCAPE => back = true,
                        c.SDLK_RETURN, c.SDLK_SPACE => confirm = true,
                        c.SDLK_S => save = true,
                        c.SDLK_B => if (screen == .main) {
                            build = true;
                        },
                        else => {},
                    }
                },
                c.SDL_EVENT_KEY_UP => _ = held.set(event.key.key, false),
                c.SDL_EVENT_GAMEPAD_BUTTON_UP => _ = held.setButton(event.gbutton.button, false),

                // A is select, B is back, X saves. Directions are polled
                // rather than taken from events, so holding one repeats.
                c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => {
                    // The d-pad and Start mean the same thing everywhere, so
                    // they go by position; the face buttons go by label.
                    _ = held.setButton(event.gbutton.button, true);
                    switch (event.gbutton.button) {
                        c.SDL_GAMEPAD_BUTTON_START => {
                            confirm = true;
                            start = true;
                        },
                        c.SDL_GAMEPAD_BUTTON_DPAD_UP => tap_v -= 1,
                        c.SDL_GAMEPAD_BUTTON_DPAD_DOWN => tap_v += 1,
                        c.SDL_GAMEPAD_BUTTON_DPAD_LEFT => tap_h -= 1,
                        c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT => tap_h += 1,
                        else => switch (faceAction(event.gbutton.which, event.gbutton.button)) {
                            .confirm => confirm = true,
                            .back => back = true,
                            .save => save = true,
                            .none => {},
                        },
                    }
                },
                else => {},
            }
        }

        // Directions come from the current state of every input rather than
        // from key events, so the keyboard and the pads behave alike and a
        // held direction repeats.
        const vdir = std.math.sign(held.vertical() + pads.stickDirection(.vertical));
        const hdir = std.math.sign(held.horizontal() + pads.stickDirection(.horizontal));

        var move: i32 = 0;
        var adjust: i32 = 0;
        if (tap_v != 0) {
            move = std.math.sign(tap_v);
            vrepeat.arm(move, now);
        } else {
            move = vrepeat.step(vdir, now);
        }
        if (tap_h != 0) {
            adjust = std.math.sign(tap_h);
            hrepeat.arm(adjust, now);
        } else {
            adjust = hrepeat.step(hdir, now);
        }

        // Saving works from any screen, which is the whole point of it being
        // on the menu as well as on a key.
        if (save) {
            if (!dirty) {
                status = "NO CHANGES TO SAVE";
            } else {
                ini.save("zelda3.ini") catch |err| {
                    std.debug.print("Could not write zelda3.ini: {s}\n", .{@errorName(err)});
                    status = "COULD NOT SAVE";
                    continue;
                };
                dirty = false;
                status = "SAVED";
            }
        }

        // A question on top of the screen takes the input until answered.
        if (modal != .none) {
            switch (modal) {
                .quit => {
                    if (hovered) {
                        for (0..kQuitChoices.len) |i| {
                            if (modalChoiceRect(i).contains(hover_x, hover_y)) quit_choice = i;
                        }
                    }
                    const step = if (adjust != 0) adjust else move;
                    if (step != 0) quit_choice = 1 - quit_choice;

                    var over_choice = false;
                    if (clicked) {
                        for (0..kQuitChoices.len) |i| {
                            if (modalChoiceRect(i).contains(hover_x, hover_y)) {
                                quit_choice = i;
                                over_choice = true;
                            }
                        }
                    }
                    if (confirm or over_choice) {
                        if (quit_choice == kQuitStay) modal = .none else running = false;
                    }
                    if (back) modal = .none;
                },
                .rom => {
                    // Enter takes the ROM already sitting beside the game,
                    // when there is one; otherwise only a drop will do.
                    if (confirm or (clicked and modalRect().contains(hover_x, hover_y))) {
                        if (g_rom_path != null) {
                            build = true;
                            modal = .none;
                        } else {
                            status = "DRAG A .SFC ROM HERE FIRST";
                        }
                    }
                    if (back) modal = .none;
                },
                .none => {},
            }
        } else if (screen == .main) {
            if (back) {
                // Ask rather than closing: B sits next to A on a pad, and
                // this window is one press from gone.
                modal = .quit;
                quit_choice = kQuitStay;
                status = "";
            }

            // The pointer drives the same cursor the keys do.
            if (hovered) {
                for (0..kMainItems.len) |i| {
                    if (mainEntryRect(i).contains(hover_x, hover_y)) main_cursor = i;
                }
            }
            if (clicked) {
                var over = false;
                for (0..kMainItems.len) |i| {
                    if (mainEntryRect(i).contains(hover_x, hover_y)) {
                        main_cursor = i;
                        over = true;
                    }
                }
                if (over) confirm = true;
            }

            if (move != 0) {
                // Down from Play reaches Randomizer, the last one.
                const n: i32 = @intCast(kMainItems.len);
                var at: i32 = @intCast(main_cursor);
                at = @mod(at + move + n, n);
                main_cursor = @intCast(at);
                status = "";
            }
            if (confirm) {
                switch (main_cursor) {
                    0 => {
                        screen = .settings;
                        status = "";
                    },
                    1 => {
                        screen = .features;
                        status = "";
                    },
                    kMainControls => {
                        screen = .controls;
                        status = "";
                    },
                    kMainSave => save = true,
                    kMainBuild => {
                        modal = .rom;
                        status = "";
                    },
                    kMainRandomizer => {
                        screen = .hub;
                        status = "";
                    },
                    else => {
                        ini.save("zelda3.ini") catch |err| {
                            std.debug.print("Could not write zelda3.ini: {s}\n", .{@errorName(err)});
                            status = "COULD NOT SAVE";
                            continue;
                        };
                        dirty = false;

                        // The game cannot start without its assets, and stale
                        // ones misbehave in ways that look like game bugs, so
                        // ask for a ROM rather than letting either through.
                        if (assets != .verified) {
                            modal = .rom;
                        } else {
                            launch = true;
                            running = false;
                        }
                    },
                }
            }
        } else if (screen == .controls) {
            if (g_ctl_capture != null) {
                // Waiting: only time passes here; the press is taken above.
                if (now - g_ctl_capture_at > kCtlCaptureMs) {
                    g_ctl_capture = null;
                    status = "NOTHING CHANGED";
                }
            } else {
                if (back) {
                    screen = .main;
                    status = "";
                }
                for (0..kCtlVisible) |slot| {
                    const row = g_ctl_top + slot;
                    if (row >= kCtlRows) break;
                    if ((hovered or clicked) and ctlRowRect(slot).contains(hover_x, hover_y)) {
                        g_ctl_row = row;
                        if (clicked) confirm = true;
                    }
                }
                if (wheel != 0) move = if (wheel > 0) -1 else 1;
                if (move != 0) {
                    g_ctl_row = @intCast(@mod(@as(i32, @intCast(g_ctl_row)) + move, @as(i32, kCtlRows)));
                    status = "";
                }
                if (confirm and !back) {
                    if (g_ctl_row == kCtlResetRow) {
                        controls.reset(&ini, false) catch {};
                        dirty = true;
                        status = "BACK TO THE DEFAULTS";
                    } else {
                        g_ctl_capture = g_ctl_row;
                        g_ctl_capture_at = now;
                        status = "";
                    }
                }
                if (g_ctl_row < g_ctl_top) g_ctl_top = g_ctl_row;
                if (g_ctl_row >= g_ctl_top + kCtlVisible) g_ctl_top = g_ctl_row + 1 - kCtlVisible;
            }
        } else if (screen == .hub) {
            if (back) {
                screen = .main;
                status = "";
            }
            for (0..kHubItems.len) |i| {
                if ((hovered or clicked) and hubRect(i).contains(hover_x, hover_y)) {
                    g_hub_cursor = i;
                    if (clicked) confirm = true;
                }
            }
            const step = if (move != 0) move else adjust;
            if (step != 0) {
                g_hub_cursor = 1 - g_hub_cursor;
                status = "";
            }
            if (confirm) {
                if (g_hub_cursor == kHubBuiltIn) {
                    status = "COMING SOON";
                } else {
                    screen = .alttpr;
                    status = "";
                }
            }
        } else if (screen == .details) {
            if (back) {
                screen = .alttpr;
                status = "";
            }
            if (wheel != 0) move = if (wheel > 0) -1 else 1;
            const count = detailCount();
            const max_top = count -| kDetailsRows;
            if (move < 0) g_details_top -|= 1;
            if (move > 0) g_details_top = @min(g_details_top + 1, max_top);
            if (confirm or clicked) {
                g_spoilers = !g_spoilers;
                status = if (g_spoilers) "SPOILERS SHOWN" else "SPOILERS HIDDEN";
                // Jump to them, since they're at the end.
                if (g_spoilers) g_details_top = detailCount() -| kDetailsRows;
            }
            g_details_top = @min(g_details_top, detailCount() -| kDetailsRows);
        } else {
            if (back) {
                screen = if (screen == .alttpr) .hub else .main;
                status = "";
            }

            // The lists behave the same; only their rows differ.
            const li = listIndex(screen);
            const n = rowCount(screen);
            const shown = visibleRows(screen);

            if (hovered) {
                const v = viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice);
                if (listRowAt(v, hover_y)) |row| list_cursor[li] = row;
            }
            if (clicked) {
                const v = viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice);
                if (listRowAt(v, hover_y)) |row| {
                    list_cursor[li] = row;
                    confirm = true;
                }
            }
            // The wheel scrolls the selection, which drags the window with it.
            if (wheel != 0) move = if (wheel > 0) -1 else 1;

            if (confirm) adjust = 1;

            if (move != 0) {
                // Step over the section headings, wrapping at either end.
                var at: i32 = @intCast(list_cursor[li]);
                const count: i32 = @intCast(n);
                while (true) {
                    at += move;
                    if (at < 0) at = count - 1;
                    if (at >= count) at = 0;
                    if (rowSelectable(screen, @intCast(at))) break;
                }
                list_cursor[li] = @intCast(at);
                status = "";
            }

            const at = rowAt(screen, list_cursor[li]);
            if (screen == .alttpr and (start or (confirm and at == kPlayRow))) {
                if (!g_seed_loaded) {
                    status = "DROP A SEED ON THIS WINDOW FIRST";
                } else {
                    // Keep the choices for next time, then go.
                    if (dirty) ini.save("zelda3.ini") catch {};
                    randomizer = true;
                    running = false;
                }
            } else if (confirm and at == kDetailsRow) {
                if (!g_seed_loaded) {
                    status = "DROP A SEED ON THIS WINDOW FIRST";
                } else {
                    screen = .details;
                    status = "";
                }
            } else if (adjust != 0 and at < kSettings.len) {
                var buf: [64]u8 = undefined;
                const cur = ini.values[at] orelse "";
                if (cycle(alloc, &buf, kSettings[at], cur, adjust)) |next| {
                    try ini.set(at, next);
                    dirty = true;
                    status = "";
                }
            }

            // Keep the cursor inside the visible window.
            if (list_cursor[li] < list_top[li]) list_top[li] = list_cursor[li];
            if (list_cursor[li] >= list_top[li] + shown)
                list_top[li] = list_cursor[li] - shown + 1;
        }

        if (build) {
            // Draw a frame first, so the window does not simply freeze for
            // the second or two this takes.
            status = "BUILDING ASSETS...";
            drawScreen(renderer, &ini, viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice));
            status = buildAssets(alloc);
            assets = checkAssets(alloc);

            // Enter on Play with no assets builds them and then goes.
            if (main_cursor == kMainLaunch and screen == .main and assets == .verified) {
                launch = true;
                running = false;
            }
        }

        drawScreen(renderer, &ini, viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice));
        c.SDL_Delay(16);
    }

    if (randomizer) return .randomizer;
    return if (launch) .play else .quit;
}

// ------------------------------------------------------------------- tests

const testing = std.testing;

/// A scratch file name of this process's own. The menu's tests run in two test
/// binaries at once, and a shared name lets one delete the other's file.
fn scratchName(buf: []u8, base: []const u8, ext: []const u8) ![:0]const u8 {
    const pid: u64 = if (builtin.os.tag == .windows) std.os.windows.GetCurrentProcessId() else @intCast(std.c.getpid());
    return std.fmt.bufPrintZ(buf, "zig-cache-{s}-{d}.{s}", .{ base, pid, ext });
}

test "an untouched ini round trips byte for byte" {
    const src =
        "# a comment\r\n[Graphics]\r\n# another\r\nWindowScale = 3\r\n\r\nLinearFiltering = 0\r\n";
    var path_buf: [64]u8 = undefined;
    const path = try scratchName(&path_buf, "roundtrip", "ini");
    try fileio.writeWholeFile(path, src);
    defer _ = fileio.remove(path);

    var ini = try Ini.load(testing.allocator, path);
    defer ini.deinit();
    try ini.save(path);

    const back = try fileio.readWholeFile(testing.allocator, path);
    defer testing.allocator.free(back);
    try testing.expectEqualStrings(src, back);
}

test "changing a value leaves every other line alone" {
    const src =
        "# keep me\n[Graphics]\n# and me\nWindowScale = 3\nLinearFiltering = 0\n";
    var path_buf: [64]u8 = undefined;
    const path = try scratchName(&path_buf, "edit", "ini");
    try fileio.writeWholeFile(path, src);
    defer _ = fileio.remove(path);

    var ini = try Ini.load(testing.allocator, path);
    defer ini.deinit();

    // Find WindowScale in the schema and bump it.
    var si: usize = 0;
    for (kSettings, 0..) |s, i| {
        if (std.mem.eql(u8, s.key, "WindowScale")) si = i;
    }
    try testing.expectEqualStrings("3", ini.values[si].?);
    var buf: [64]u8 = undefined;
    const next = cycle(testing.allocator, &buf, kSettings[si], ini.values[si].?, 1).?;
    try ini.set(si, next);
    try ini.save(path);

    const back = try fileio.readWholeFile(testing.allocator, path);
    defer testing.allocator.free(back);
    try testing.expectEqualStrings(
        "# keep me\n[Graphics]\n# and me\nWindowScale = 4\nLinearFiltering = 0\n",
        back,
    );
}

test "toggles flip and choices wrap in both directions" {
    var buf: [64]u8 = undefined;
    const toggle = Setting{ .section = "x", .key = "k", .label = "l", .kind = .toggle };
    try testing.expectEqualStrings("1", cycle(testing.allocator, &buf, toggle, "0", 1).?);
    try testing.expectEqualStrings("0", cycle(testing.allocator, &buf, toggle, "1", 1).?);

    const choice = Setting{
        .section = "x",
        .key = "k",
        .label = "l",
        .kind = .{ .choice = .{ .values = &.{ "a", "b", "c" } } },
    };
    try testing.expectEqualStrings("b", cycle(testing.allocator, &buf, choice, "a", 1).?);
    try testing.expectEqualStrings("a", cycle(testing.allocator, &buf, choice, "c", 1).?);
    try testing.expectEqualStrings("c", cycle(testing.allocator, &buf, choice, "a", -1).?);

    // Numbers clamp at both ends and keep their suffix.
    const num = Setting{
        .section = "x",
        .key = "k",
        .label = "l",
        .kind = .{ .number = .{ .min = 0, .max = 100, .step = 5, .suffix = "%" } },
    };
    try testing.expectEqualStrings("100%", cycle(testing.allocator, &buf, num, "100%", 1).?);
    try testing.expectEqualStrings("0%", cycle(testing.allocator, &buf, num, "0%", -1).?);
    try testing.expectEqualStrings("55%", cycle(testing.allocator, &buf, num, "50%", 1).?);

    // Free text is not cycled.
    const text = Setting{ .section = "x", .key = "k", .label = "l", .kind = .text };
    try testing.expect(cycle(testing.allocator, &buf, text, "whatever", 1) == null);
}

test "every schema entry names a real key in the shipped ini" {
    var ini = try Ini.load(testing.allocator, "zelda3.ini");
    defer ini.deinit();
    for (kSettings, 0..) |s, i| {
        if (std.mem.eql(u8, s.section, kSectionMark)) continue;
        if (ini.line_of[i] == null) {
            std.debug.print("schema entry not found in zelda3.ini: [{s}] {s}\n", .{ s.section, s.key });
            return error.SettingNotFound;
        }
    }
}

test "the shipped ini survives a save unchanged" {
    // The real file, with its CRLF endings and every comment, is what a player
    // stands to lose if the writer is wrong. Save it to a scratch path and
    // compare rather than writing over the original.
    const original = try fileio.readWholeFile(testing.allocator, "zelda3.ini");
    defer testing.allocator.free(original);

    var ini = try Ini.load(testing.allocator, "zelda3.ini");
    defer ini.deinit();

    var scratch_buf: [64]u8 = undefined;
    const scratch = try scratchName(&scratch_buf, "shipped", "ini");
    defer _ = fileio.remove(scratch);
    try ini.save(scratch);

    const back = try fileio.readWholeFile(testing.allocator, scratch);
    defer testing.allocator.free(back);
    try testing.expectEqualStrings(original, back);
}

test "the schema splits cleanly into the three menus" {
    // Everything before the FEATURES heading belongs to Settings, Features
    // runs to the RANDOMIZER heading, and the rest is what a seed opens on.
    // A section added in the wrong place would land on the wrong screen.
    const settings = screenRange(.settings);
    const features = screenRange(.features);
    const randomizer = screenRange(.alttpr);

    try testing.expect(settings.to > settings.from);
    try testing.expect(features.to > features.from);
    try testing.expect(randomizer.to > randomizer.from);
    try testing.expectEqual(settings.to, features.from);
    try testing.expectEqual(features.to, randomizer.from);
    try testing.expectEqual(kControlsStart, randomizer.to);
    for (kSettings[randomizer.from..randomizer.to]) |s| {
        if (isSection(s)) continue;
        try testing.expectEqualStrings("Randomizer", s.section);
    }

    for (kSettings[settings.from..settings.to]) |s| {
        if (isSection(s)) continue;
        try testing.expect(!std.mem.eql(u8, s.section, "Features"));
    }
    for (kSettings[features.from..features.to]) |s| {
        if (isSection(s)) continue;
        try testing.expectEqualStrings("Features", s.section);
    }
}

test "each menu opens on a real setting rather than a heading" {
    const settings = screenRange(.settings);
    const features = screenRange(.features);

    const a = firstSelectable(settings.from, settings.to);
    try testing.expect(a >= settings.from and a < settings.to);
    try testing.expect(!isSection(kSettings[a]));

    const b = firstSelectable(features.from, features.to);
    try testing.expect(b >= features.from and b < features.to);
    try testing.expect(!isSection(kSettings[b]));
}

test "a dropped file is judged by its extension, not its name" {
    // The name carries no meaning - people rename their dumps - so anything
    // ending in a SNES ROM extension is worth hashing, and nothing else is.
    for ([_][]const u8{
        "zelda3.sfc", "Zelda3.SFC",        "/tmp/some rom.sfc",
        "alttp.smc",  "/a/b/HEADERED.SmC", "x.sfc",
    }) |path| try testing.expect(looksLikeRom(path));

    for ([_][]const u8{
        "zelda3.dat", "rom.zip", "sfc", ".sfc2", "", "a.sf", "zelda3.sfc.txt",
    }) |path| try testing.expect(!looksLikeRom(path));
}

test "the on-screen strings fit the window" {
    // The debug font is 8 pixels wide before scaling, and the text starts 40
    // pixels in with the frame 16 pixels from the right edge. Anything longer
    // runs off the side, which is how the first version of the footer shipped.
    const usable = kWindowW - 40 - 16;
    const max_chars = usable / kCell;

    for ([_][]const u8{
        // Footers.
        "SELECT A/ENTER   SAVE X/S",
        "QUIT B/ESC",
        "CHANGE  LEFT/RIGHT OR A",
        "SAVE X/S   BACK B/ESC",
        // Headers.
        "THE LEGEND OF ZELDA",
        "A LINK TO THE PAST",
        "START MENU",
        "LEFT/RIGHT CHOOSE",
        "A/ENTER CONFIRM   B/ESC CANCEL",
        "DROP A FILE ON THE WINDOW",
        "B/ESC CANCEL",
        "QUIT THE GAME?",
        "UNSAVED CHANGES WILL BE LOST",
        "DROP A ROM ON THIS WINDOW",
        "ANY .SFC FILE - THE NAME DOES",
        "NOT MATTER, IT IS CHECKED",
        "OR PRESS A/ENTER TO USE",
        "SETTINGS",
        "FEATURES",
        "ESC BACK",
        // Asset states and the hint under them.
        "ASSETS MISSING",
        "ASSETS VERIFIED",
        "ASSETS PRESENT - CHECKSUM DIFFERS",
        "DRAG A .SFC ROM ONTO THIS WINDOW",
        // The Controls screen.
        "KEYBOARD",
        "CONTROLLER",
        "RESET ALL TO DEFAULTS",
        "PRESS ANY KEY OR PAD BUTTON",
        "ESC OR WAIT TO CANCEL",
        "CHANGE A/ENTER",
        "NOTHING CHANGED",
        "THAT KEY DOES SOMETHING ELSE",
        "COULD NOT CHANGE IT",
        "BACK TO THE DEFAULTS",
        // The randomizer's pages.
        "DROP AN ALTTPR.COM SEED HERE",
        "GENERATE ONE AT ALTTPR.COM FROM",
        "THE JAPANESE 1.0 ROM, THEN DRAG",
        "THE .SFC ONTO THIS WINDOW",
        "JAPANESE 1.0 ROM - NOT A SEED",
        "IT PLAYS, BUT UNRANDOMIZED",
        "PLAY A SEED FROM ALTTPR.COM",
        "ALTTPR.COM RANDOMIZER",
        "BUILT-IN RANDOMIZER",
        "SEED DETAILS",
        "PLAY THIS SEED",
        "SELECT A/ENTER",
        "PLAY START  SAVE X/S  BACK B",
        "SCROLL UP/DOWN",
        "SPOILERS A/ENTER   BACK B/ESC",
        "DROP A SEED ON THIS WINDOW FIRST",
        "SEEDS GO ON THE RANDOMIZER PAGE",
        "NOT AN ALTTPR.COM SEED",
        "JAPANESE ROM LOADED",
        // Every status line the loop can put up.
        "ASSETS BUILT",
        "BUILDING ASSETS...",
        "CHECKING ROM...",
        "COULD NOT BUILD ASSETS",
        "COULD NOT READ ROM",
        "COULD NOT READ THAT FILE",
        "COULD NOT SAVE",
        "COULD NOT WRITE ASSETS",
        "DRAG A .SFC ROM HERE FIRST",
        "NEED zelda3.sfc TO BUILD ASSETS",
        "NOT A .SFC FILE",
        "ROM IS NOT THE US RELEASE",
        "SAVED",
        "NO CHANGES TO SAVE",
        // The longest value label, which shares the row with its name.
        "Deluxe Opuz",
        "Borderless",
        "Windowed",
        "Exclusive",
        "UNRECOGNIZED ROM",
        "UNSAVED CHANGES",
        "US ROM VERIFIED - ASSETS BUILT",
    }) |line| {
        testing.expect(line.len <= max_chars) catch |err| {
            std.debug.print("too wide ({d} > {d}): {s}\n", .{ line.len, max_chars, line });
            return err;
        };
    }

    // The longest region name has to fit the sentence it goes into.
    for (std.enums.values(rom_mod.Language)) |lang| {
        var buf: [64]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s} ROM - NEEDS THE US ONE", .{regionName(lang)});
        try testing.expect(line.len <= max_chars);
    }
}

test "the asset check tells the three states apart" {
    const alloc = testing.allocator;

    try testing.expectEqual(AssetState.missing, checkAssetsAt(alloc, "no-such-file.dat"));

    // Anything that is not the file the builder produces is reported as
    // present but unrecognized rather than waved through - a stale .dat loads
    // and then misbehaves in ways that look like game bugs.
    var scratch_buf: [64]u8 = undefined;
    const scratch = try scratchName(&scratch_buf, "checktest", "dat");
    try fileio.writeWholeFile(scratch, "not an asset file");
    defer _ = fileio.remove(scratch);
    try testing.expectEqual(AssetState.unrecognized, checkAssetsAt(alloc, scratch));

    // An empty file is not a crash.
    const empty = "zelda3_assets_emptytest.dat";
    try fileio.writeWholeFile(empty, "");
    defer _ = fileio.remove(empty);
    try testing.expectEqual(AssetState.unrecognized, checkAssetsAt(alloc, empty));

    // And the real thing, when this machine has one.
    if (fileio.exists("zig-out/bin/zelda3_assets.dat"))
        try testing.expectEqual(AssetState.verified, checkAssetsAt(alloc, "zig-out/bin/zelda3_assets.dat"));
}

test "a corrupted asset file is not reported as verified" {
    const alloc = testing.allocator;
    if (!fileio.exists("zig-out/bin/zelda3_assets.dat")) return error.SkipZigTest;

    const good = try fileio.readWholeFile(alloc, "zig-out/bin/zelda3_assets.dat");
    defer alloc.free(good);
    try testing.expect(good.len > 500_000);

    const copy = try alloc.dupe(u8, good);
    defer alloc.free(copy);
    copy[500_000] ^= 0xff; // one bit, deep inside the payload

    var scratch_buf: [64]u8 = undefined;
    const scratch = try scratchName(&scratch_buf, "corrupttest", "dat");
    try fileio.writeWholeFile(scratch, copy);
    defer _ = fileio.remove(scratch);
    try testing.expectEqual(AssetState.unrecognized, checkAssetsAt(alloc, scratch));
}

test "every named choice names all of its values" {
    // A labels array shorter than its values array shows the raw value for
    // the ones past the end, which looks like a missing translation rather
    // than a bug. A longer one names something that cannot be selected.
    for (kSettings) |setting| {
        const opts = switch (setting.kind) {
            .choice => |ch| ch,
            else => continue,
        };
        if (opts.labels.len == 0) continue;
        testing.expectEqual(opts.values.len, opts.labels.len) catch |err| {
            std.debug.print("{s}: {d} values but {d} labels\n", .{ setting.key, opts.values.len, opts.labels.len });
            return err;
        };
    }
}

test "the emulator note fits inside the frame" {
    for (kEmuNote) |line| try testing.expect(textWidth(line, 1) <= kWindowW - 64);
}

test "a value's name fits the column it is drawn in" {
    // Names are drawn at x=400 with the frame 16 pixels from the right edge.
    const max_chars = (kWindowW - 400 - 16) / kCell;
    for (kSettings) |setting| {
        const opts = switch (setting.kind) {
            .choice => |ch| ch,
            else => continue,
        };
        for (opts.labels) |label| {
            testing.expect(label.len <= max_chars) catch |err| {
                std.debug.print("{s}: \"{s}\" is {d} wide, column fits {d}\n", .{ setting.key, label, label.len, max_chars });
                return err;
            };
        }
    }
}

test "cycling a named choice writes the value, not the name" {
    // The file has to keep getting 0, 1, 2 - the names are only for reading.
    const alloc = testing.allocator;
    var buf: [64]u8 = undefined;
    for (kSettings) |setting| {
        const opts = switch (setting.kind) {
            .choice => |ch| ch,
            else => continue,
        };
        if (opts.labels.len == 0) continue;

        const next = cycle(alloc, &buf, setting, opts.values[0], 1).?;
        try testing.expectEqualStrings(opts.values[1], next);
    }
}

test "clickable areas line up with what is drawn" {
    // Hit testing and drawing share their geometry, but they can still be
    // wrong together, so check the shape of it: rows in order, no overlaps,
    // and the launch button below the entries rather than on top of one.
    var prev = mainEntryRect(0);
    try testing.expect(prev.w > 0 and prev.h > 0);

    for (1..kMainItems.len) |i| {
        const r = mainEntryRect(i);
        testing.expect(r.y >= prev.y + prev.h) catch |err| {
            std.debug.print("entry {d} at y={d} overlaps the one above ending at {d}\n", .{ i, r.y, prev.y + prev.h });
            return err;
        };
        prev = r;
    }

    // Everything stays inside the frame.
    for (0..kMainItems.len) |i| {
        const r = mainEntryRect(i);
        try testing.expect(r.x >= 16 and r.x + r.w <= kWindowW - 16);
        try testing.expect(r.y >= 16 and r.y + r.h <= kWindowH - 16);
    }
}

test "the modal's answers sit inside it and apart from each other" {
    const box = modalRect();
    const a = modalChoiceRect(0);
    const b = modalChoiceRect(1);

    for ([_]Rect{ a, b }) |r| {
        try testing.expect(r.x >= box.x and r.x + r.w <= box.x + box.w);
        try testing.expect(r.y >= box.y and r.y + r.h <= box.y + box.h);
    }
    // Apart, and in the order they are drawn.
    try testing.expect(a.x + a.w < b.x);

    // A click on one is not a click on the other.
    try testing.expect(a.contains(a.x + a.w / 2, a.y + a.h / 2));
    try testing.expect(!b.contains(a.x + a.w / 2, a.y + a.h / 2));
}

test "a click on a list row picks that row" {
    const v = View{
        .screen = .settings,
        .cursor = 0,
        .top = 0,
        .status = "",
        .dirty = false,
        .assets = .verified,
    };

    // Walk down the drawn rows and check each y maps back to its own entry,
    // skipping the headings, which are not selectable.
    var y: f32 = kListStartY;
    var i: usize = 0;
    while (i < kVisibleRows and i < screenRange(.settings).to) : (i += 1) {
        const hit = listRowAt(v, y + 2);
        if (isSection(kSettings[i])) {
            try testing.expect(hit == null);
        } else {
            try testing.expectEqual(@as(?usize, i), hit);
        }
        y += kRowH;
    }

    // Above and below the list is nothing at all.
    try testing.expect(listRowAt(v, kListStartY - 20) == null);
    try testing.expect(listRowAt(v, kListStartY + kRowH * kVisibleRows + 40) == null);
}

test "a setting the file lacks shows its default and is added when changed" {
    // The menu's tests run in two test binaries at once, so the scratch file
    // is named per process.
    var path_buf: [64]u8 = undefined;
    // getpid() is a handle rather than a number on Windows, which has its own.
    const pid: u64 = if (builtin.os.tag == .windows) std.os.windows.GetCurrentProcessId() else @intCast(std.c.getpid());
    const path = try std.fmt.bufPrintZ(&path_buf, "zig-cache-missing-key-{d}.ini", .{pid});
    defer _ = fileio.remove(path);
    // An ini from before StartMenu and Rumble existed.
    try fileio.writeWholeFile(path, "[General]\n# Automatically save state\nAutosave = 0\n\n[Graphics]\nWindowScale = 3\n");

    var ini = try Ini.load(testing.allocator, path);
    defer ini.deinit();
    const start_menu = settingIndex("General", "StartMenu").?;
    const rumble = settingIndex("General", "Rumble").?;
    try testing.expectEqualStrings("1", ini.values[start_menu].?);
    try testing.expectEqualStrings("100%", ini.values[rumble].?);

    // Unchanged defaults stay out of the file; a change goes into its section.
    try ini.set(start_menu, "0");
    try ini.save(path);
    try ini.save(path); // a second save must not add it again
    const text = try fileio.readWholeFile(testing.allocator, path);
    defer testing.allocator.free(text);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "StartMenu = 0"));
    try testing.expect(std.mem.indexOf(u8, text, "Rumble") == null);
    try testing.expect(std.mem.indexOf(u8, text, "StartMenu = 0").? < std.mem.indexOf(u8, text, "[Graphics]").?);

    // And it reads back as set, bound to its new line.
    var again = try Ini.load(testing.allocator, path);
    defer again.deinit();
    try testing.expectEqualStrings("0", again.values[start_menu].?);
    try testing.expect(again.line_of[start_menu] != null);
}

test "the Controls screen fits between the header and the footer" {
    try testing.expect(kCtlArtX >= 32 and kCtlArtX + pad_art.kWidth * kCtlArtScale <= kWindowW - 32);
    try testing.expect(kCtlArtY - pad_art.kShoulderRise * kCtlArtScale >= kListStartY - 4);
    // The last row ends above the status line over the footer.
    const footer_y: f32 = kWindowH - 32 - kRowH * 2 - 6;
    const last = ctlRowRect(kCtlVisible - 1);
    try testing.expect(last.y + last.h <= footer_y - kRowH);
    // "PRESS KEY OR BUTTON" fits from the key column to the frame.
    try testing.expect(kCtlColKey + textWidth("PRESS KEY OR BUTTON", kScale) <= kWindowW - 16);
}

test "the Randomizer button clears the missing-assets hint and the status line" {
    // Mirrors drawMain: the asset state under Play, then the hint under it.
    const hint_bottom = launchRect().y + launchRect().h + 6 + kRowH + kCell;
    try testing.expect(randoRect().y >= hint_bottom);
    const footer_y: f32 = kWindowH - 32 - kRowH * 2 - 6;
    try testing.expect(randoRect().y + randoRect().h <= footer_y - kRowH);
}
