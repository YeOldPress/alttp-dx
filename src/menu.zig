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
//! The front page is the exception: unless the ini asks for the retro one,
//! it's start_page.zig's, in real type.
const std = @import("std");
const builtin = @import("builtin");
const fileio = @import("fileio.zig");
const msu_import = @import("msu_import.zig");
const tools_ops = @import("tools_ops.zig");
const updater = @import("updater.zig");
const start_logo = @import("start_logo.zig");
const langs = @import("asset_languages.zig");
const rom_mod = @import("rom.zig");
const asset_all = @import("asset_all.zig");
const c = @import("sdl.zig").c;
const kit = @import("menu_kit.zig");
const ui = @import("tools_draw.zig");
const seed_info = @import("seed_info.zig");
const config = @import("config.zig");
const controls = @import("controls.zig");
const pad_art = @import("pad_art.zig");
const crt = @import("crt.zig");
const achievement_list = @import("achievement_list.zig");
const start_page = @import("start_page.zig");
const tools_gui = @import("tools_gui.zig");

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

// The look is the kit's, shared with the tools window.
const Rgb = kit.Rgb;
const kColorBgTop = kit.kColorBgTop;
const kColorBgBottom = kit.kColorBgBottom;
const kColorShadow = kit.kColorShadow;
const kColorPanel = kit.kColorPanel;
const kColorLine = kit.kColorLine;
const kColorText = kit.kColorText;
const kColorTextDim = kit.kColorTextDim;
const kColorValue = kit.kColorValue;
const kColorSelect = kit.kColorSelect;
const kColorRowHi = kit.kColorRowHi;
const kColorLaunchBg = kit.kColorLaunchBg;
const kColorLaunchText = kit.kColorLaunchText;
const kColorOk = kit.kColorOk;
const kColorWarn = kit.kColorWarn;
const kColorSection = kit.kColorSection;
const kColorRandoBg = kit.kColorRandoBg;
const kColorDisabledBg = kit.kColorDisabledBg;

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
    /// A button, not a value: A does it. Nothing of it goes in the ini.
    action,
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
    .{ .section = "General", .key = "StartMenuStyle", .label = "Start Menu Style", .kind = .{ .choice = .{
        .values = &.{ "modern", "retro" },
        .labels = &.{ "Modern", "Retro" },
    } } },
    .{ .section = "General", .key = "StartBanner", .label = "40th Banner", .kind = .toggle },
    .{ .section = "General", .key = "CheckForUpdates", .label = "Check For Updates", .kind = .toggle },
    .{ .section = "General", .key = "UpdateChannel", .label = "Update Channel", .kind = .{ .choice = .{
        .values = &.{ "releases", "nightly" },
        .labels = &.{ "Releases", "Nightly" },
    } } },
    .{ .section = "General", .key = "Autosave", .label = "Autosave", .kind = .toggle },
    .{ .section = "General", .key = "DisplayPerfInTitle", .label = "Show FPS In Title", .kind = .toggle },
    .{ .section = "General", .key = "ExtendedAspectRatio", .label = "Aspect Ratio", .kind = .{ .choice = .{ .values = &.{ "4:3", "16:9", "16:10", "18:9" } } } },
    .{ .section = "General", .key = "WidescreenHud", .label = "Widescreen HUD", .kind = .toggle },
    .{ .section = "General", .key = "WidescreenCamera", .label = "Widescreen Camera", .kind = .toggle },
    .{ .section = "General", .key = "DisableFrameDelay", .label = "Disable Frame Delay", .kind = .toggle },
    .{ .section = "General", .key = "Rumble", .label = "Rumble", .kind = .{ .number = .{ .min = 0, .max = 100, .step = 10, .suffix = "%" } } },
    .{ .section = "General", .key = "Language", .label = "Language", .kind = .{ .choice = .{
        .values = &.{ "us", "de", "fr", "fr-c", "en", "es", "pl", "pt", "redux", "nl", "sv" },
        .labels = &.{ "English", "German", "French", "French (CA)", "English (EU)", "Spanish", "Polish", "Portuguese", "Redux", "Dutch", "Swedish" },
    } } },

    .{ .section = kSectionMark, .key = "", .label = "GRAPHICS", .kind = .text },
    .{ .section = "Graphics", .key = "Fullscreen", .label = "Fullscreen", .kind = .{ .choice = .{
        .values = &.{ "0", "1", "2" },
        .labels = &.{ "Windowed", "Borderless", "Exclusive" },
    } } },
    .{ .section = "Graphics", .key = "WindowScale", .label = "Window Scale", .kind = .{ .number = .{ .min = 1, .max = 10, .step = 1 } } },
    .{ .section = "Graphics", .key = "OutputMethod", .label = "Output Method", .kind = .{ .choice = .{ .values = &.{ "SDL", "SDL-Software" } } } },
    .{ .section = "Graphics", .key = "NewRenderer", .label = "New Renderer", .kind = .toggle },
    .{ .section = "Graphics", .key = "EnhancedMode7", .label = "Enhanced Mode 7", .kind = .toggle },
    .{ .section = "Graphics", .key = "NoSpriteLimits", .label = "No Sprite Limits", .kind = .toggle },
    .{ .section = "Graphics", .key = "IgnoreAspectRatio", .label = "Stretch To Window", .kind = .toggle },
    .{ .section = "Graphics", .key = "PixelScaling", .label = "Pixel Scaling", .kind = .{ .choice = .{
        .values = &.{ "sharp", "nearest", "smooth", "xbr" },
        .labels = &.{ "Sharp", "Nearest", "Smooth", "xBR" },
    } } },
    .{ .section = "Graphics", .key = "CrtFilter", .label = "CRT Filter", .kind = .{ .choice = .{
        .values = &.{ "off", "scanlines", "arcade", "soft", "tv", "composite", "lcd" },
        .labels = &.{ "Off", "Scanlines", "Arcade", "Soft", "Consumer TV", "Composite", "LCD" },
    } } },
    .{ .section = "Graphics", .key = "CrtScanlines", .label = "CRT Scanlines", .kind = .{ .number = .{ .min = 0, .max = 200, .step = 10, .suffix = "%" } } },
    .{ .section = "Graphics", .key = "CrtMask", .label = "CRT Mask", .kind = .{ .number = .{ .min = 0, .max = 200, .step = 10, .suffix = "%" } } },
    .{ .section = "Graphics", .key = "CrtGlow", .label = "CRT Glow", .kind = .{ .number = .{ .min = 0, .max = 200, .step = 10, .suffix = "%" } } },
    .{ .section = "Graphics", .key = "CrtAfterglow", .label = "CRT Afterglow", .kind = .{ .number = .{ .min = 0, .max = 200, .step = 10, .suffix = "%" } } },
    .{ .section = "Graphics", .key = "CrtCurvature", .label = "CRT Curvature", .kind = .{ .number = .{ .min = 0, .max = 100, .step = 10, .suffix = "%" } } },
    .{ .section = "Graphics", .key = "CrtBezel", .label = "TV Bezel", .kind = .toggle },
    .{ .section = "Graphics", .key = "HDR", .label = "HDR", .kind = .toggle },
    .{ .section = "Graphics", .key = "CrtReset", .label = "Reset CRT Settings", .kind = .action },
    .{ .section = "Graphics", .key = "DynamicLighting", .label = "Dynamic Lighting", .kind = .toggle },
    .{ .section = "Graphics", .key = "LightingQuality", .label = "Lighting Quality", .kind = .{ .choice = .{
        .values = &.{ "full", "simple" },
        .labels = &.{ "Full", "Simple" },
    } } },
    .{ .section = "Graphics", .key = "RoomDimming", .label = "Room Dimming", .kind = .{ .number = .{ .min = 0, .max = 40, .step = 5, .suffix = "%" } } },
    .{ .section = "Graphics", .key = "Particles", .label = "Particles", .kind = .toggle },
    .{ .section = "Graphics", .key = "HdWater", .label = "HD Water/Lava", .kind = .toggle },
    .{ .section = "Graphics", .key = "DimFlashes", .label = "Dim Flashes", .kind = .toggle },
    .{ .section = "Graphics", .key = "WindowSize", .label = "Window Size", .kind = .text },

    .{ .section = kSectionMark, .key = "", .label = "SOUND", .kind = .text },
    .{ .section = "Sound", .key = "EnableAudio", .label = "Enable Audio", .kind = .toggle },
    .{ .section = "Sound", .key = "Volume", .label = "Volume", .kind = .{ .number = .{ .min = 0, .max = 100, .step = 5, .suffix = "%" } } },
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
    .{ .section = "Sound", .key = "MSUPath", .label = "MSU Pack", .kind = .text },

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
    .{ .section = "Features", .key = "DiggingGamePity", .label = "Digging Game Pity", .note = "HEART PIECE GUARANTEED AFTER 250 DIGS", .kind = .toggle },
    .{ .section = "Features", .key = "ContinueFromDungeon", .label = "Continue From Dungeon", .kind = .toggle },

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
        .text, .action => return null,
    }
    _ = alloc;
}

/// The settings each CRT Filter sets for itself when it's picked, and Reset
/// CRT Settings puts back: the sliders, the curve and the bezel.
pub const kCrtDefaultKeys = [_][]const u8{ "CrtScanlines", "CrtMask", "CrtGlow", "CrtAfterglow", "CrtCurvature", "CrtBezel" };

/// Sets those to the chosen filter's own defaults.
pub fn applyCrtDefaults(ini: *Ini) !void {
    const filter_at = settingIndex("Graphics", "CrtFilter") orelse return;
    const name = std.mem.trim(u8, ini.values[filter_at] orelse "off", " \t");
    const d = crt.defaultsFor(crt.Preset.fromName(name) orelse .off);
    var buf: [16]u8 = undefined;
    for (kCrtDefaultKeys) |key| {
        const at = settingIndex("Graphics", key) orelse continue;
        const value: []const u8 = if (std.mem.eql(u8, key, "CrtCurvature"))
            try std.fmt.bufPrint(&buf, "{d}%", .{d.curvature})
        else if (std.mem.eql(u8, key, "CrtBezel"))
            (if (d.bezel) "1" else "0")
        else
            "100%";
        try ini.set(at, value);
    }
}

fn isUpdateSetting(s: Setting) bool {
    return std.mem.eql(u8, s.section, "General") and
        (std.mem.eql(u8, s.key, "CheckForUpdates") or std.mem.eql(u8, s.key, "UpdateChannel"));
}

/// MSUPath: text in the ini, but the start menu steps it through the packs
/// that are installed.
pub fn isMsuPack(s: Setting) bool {
    return std.mem.eql(u8, s.section, "Sound") and std.mem.eql(u8, s.key, "MSUPath");
}

/// A setting with nothing to step through here: text that's edited in the
/// ini, and buttons.
fn isFixed(s: Setting) bool {
    return (s.kind == .text and !isMsuPack(s)) or s.kind == .action;
}

/// The installed pack after (or before) the one `current` names, by MSUPath.
fn nextPack(arena: std.mem.Allocator, current: []const u8, dir: i32) ?[]const u8 {
    const packs = msu_import.listPacks(arena, msu_import.kLibrary) catch return null;
    if (packs.len == 0) return null;
    const cur = std.mem.trim(u8, current, " \t");
    var at: ?usize = null;
    for (packs, 0..) |p, i| {
        if (tools_ops.samePath(p.path, cur)) at = i;
    }
    const n: i32 = @intCast(packs.len);
    const next: i32 = if (at) |i| @mod(@as(i32, @intCast(i)) + dir, n) else if (dir > 0) 0 else n - 1;
    return packs[@intCast(next)].path;
}

fn isLogoSetting(s: Setting) bool {
    return std.mem.eql(u8, s.section, "General") and std.mem.eql(u8, s.key, "StartBanner");
}

pub fn isCrtFilter(s: Setting) bool {
    return std.mem.eql(u8, s.section, "Graphics") and std.mem.eql(u8, s.key, "CrtFilter");
}

/// What the list shows for a value: toggles read as words, everything else as
/// written, with empty text made visible.
pub fn displayValue(buf: []u8, s: Setting, value: []const u8) []const u8 {
    const v = std.mem.trim(u8, value, " \t");
    switch (s.kind) {
        .toggle => {
            const on = std.mem.eql(u8, v, "1");
            // The banner says how its download's going, while it is.
            if (on and isLogoSetting(s) and start_logo.note().len != 0)
                return std.fmt.bufPrint(buf, "ON - {s}", .{start_logo.note()}) catch "ON";
            return if (on) "ON" else "OFF";
        },
        .text => {
            if (v.len == 0) return "(none)";
            return if (isMsuPack(s)) msu_import.packLabel(v) else v;
        },
        .action => return "",
        .choice => |opts| return opts.labelFor(v),
        else => {},
    }
    return std.fmt.bufPrint(buf, "{s}", .{v}) catch v;
}

// ------------------------------------------------------------------ drawing

const setColor = kit.setColor;
const fillRect = kit.fillRect;
const cornerInset = kit.cornerInset;
const fillRound = kit.fillRound;
const outlineRound = kit.outlineRound;
const mix = kit.mix;
const drawFrame = kit.drawFrame;
const drawRowHighlight = kit.drawRowHighlight;
const kRingAbove = kit.kRingAbove;
const kRingBelow = kit.kRingBelow;
const drawButton = kit.drawButton;
const drawText = kit.drawText;
const textWidth = kit.textWidth;
const drawTextCentered = kit.drawTextCentered;
const drawTextScaled = kit.drawTextScaled;

/// The background, the size of this window.
fn fillBackground(r: *c.SDL_Renderer) void {
    kit.fillBackground(r, kWindowW, kWindowH);
}

/// A thin scrollbar: a track, and a rounded thumb over the part showing.
fn drawScrollbar(r: *c.SDL_Renderer, track_y: f32, track_h: f32, bar_y: f32, bar_h: f32) void {
    fillRound(r, kWindowW - 31, track_y, 4, track_h, 2, kColorLine);
    fillRound(r, kWindowW - 31, bar_y, 4, bar_h, 2, kColorTextDim);
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

/// What each setting does, for the info boxes in the start menu and in the
/// game's own settings. In words both fonts can draw: no colons, slashes or
/// percent signs, which the game's dialogue font hasn't got.
pub fn describe(s: Setting) []const u8 {
    const kDescriptions = [_][2][]const u8{
        .{ "StartMenu", "Show the start menu, with settings and the ROM and assets, before the game begins. When off, the game starts straight away unless its assets need building." },
        .{ "StartBanner", "Hangs Nintendo's own 40th anniversary banner small in the front page's corner. It's theirs, so it isn't shipped. Turning this on downloads it from their site once and keeps it beside the ini. Modern style only." },
        .{ "StartMenuStyle", "Modern is the front page made for the series' 40th anniversary, in real type with the Triforce and drifting light. Retro is the old one, all in the 8x8 debug font. Everything does the same either way." },
        .{ "CheckForUpdates", "When the start menu opens, ask GitHub whether there's a newer version. If there is, an Update button shows under the title. Nothing downloads until you press it. A game you built yourself never updates." },
        .{ "UpdateChannel", "Releases offers each numbered release. Nightly offers the rolling test build of the newest changes, rebuilt most nights, and sometimes broken. Back on Releases, the next release is the next update." },
        .{ "Autosave", "Save a snapshot of the game when you quit and pick up from it next time you start." },
        .{ "DisplayPerfInTitle", "Show the frames per second in the window's title bar." },
        .{ "ExtendedAspectRatio", "Widen the view past the original 4 by 3 screen, showing more of the world at the sides. 16 by 9 suits most modern screens." },
        .{ "WidescreenHud", "In widescreen, move the magic meter, item and counters to the left edge and the hearts to the right, instead of leaving them in the middle. Does nothing at 4 by 3." },
        .{ "WidescreenCamera", "In widescreen, keep the camera far enough from an area's edge that the whole wide picture shows the area, instead of stopping where a 4 by 3 screen would and showing black past it. Does nothing at 4 by 3." },
        .{ "DisableFrameDelay", "Skip the wait the game does between frames. Only worth it on a display running at exactly 60 hertz." },
        .{ "Language", "The language the game's text is in. Anything but English has to be built into the assets first, on the Languages page in Tools. One that isn't there plays in English. Takes effect the next time the game starts." },
        .{ "Rumble", "How hard the controller shakes when Link is hurt, bombs go off, bosses fall and the screen shakes. 0 turns it off." },
        .{ "Tracker", "Where the item tracker goes when playing a randomizer seed. Beside the game, over it, in its own window, or nowhere. T switches while playing." },
        .{ "Fullscreen", "Windowed, fullscreen at the desktop's resolution, or fullscreen with a change of display mode." },
        .{ "WindowScale", "How many times bigger than the SNES screen the window opens." },
        .{ "OutputMethod", "How frames reach the screen. SDL suits most machines. SDL-Software can help on a Raspberry Pi." },
        .{ "NewRenderer", "Draw the screen with a faster rewrite of the SNES graphics chip. Turn it off if something looks wrong." },
        .{ "EnhancedMode7", "Draw the world map and other rotating backgrounds at a higher resolution." },
        .{ "NoSpriteLimits", "Stop sprites flickering or vanishing when too many share a line of the screen, a limit of the original hardware." },
        .{ "IgnoreAspectRatio", "Stretch the picture to fill the window instead of keeping its shape." },
        .{ "PixelScaling", "How the picture fills the window. Sharp keeps pixels square and even, with soft edges. Nearest is crispest, but some rows come out bigger. Smooth blurs it. xBR rounds off diagonals and curves. A CRT Filter does its own." },
        .{ "WindowSize", "The window's size when the game opens, as a width and height in pixels such as 1280x720, or Auto to size it from Window Scale. Set it in zelda3.ini." },
        .{ "CrtScanlines", "How strong the CRT Filter's scanlines are. 100 percent is the filter as it comes, 0 none at all, 200 twice as strong." },
        .{ "CrtMask", "How strong the colored stripes, dots or grid of the CRT Filter are. 100 percent is the filter as it comes, 0 none." },
        .{ "CrtGlow", "How much bright things glow and haze on the CRT Filters that have it. 100 percent is the filter as it comes, 0 none." },
        .{ "CrtAfterglow", "How long moving things leave a fading trail on the CRT Filters that have it. 100 percent is the filter as it comes, 0 none." },
        .{ "CrtCurvature", "Bows the picture like the face of an old TV's tube, with rounded corners. 0 is flat, 50 a TV's. Works with any CRT Filter, or none." },
        .{ "CrtReset", "Puts the CRT sliders, the curvature and the bezel back to the chosen CRT Filter's own defaults. Picking a filter does this too." },
        .{ "HDR", "On an HDR display, lets the CRT Filter shine past normal white, the way a real tube's phosphors do, so its dark stripes don't dim the picture. Does nothing on other displays." },
        .{ "CrtBezel", "Puts the picture in a TV's dark plastic frame, which catches a little of the screen's light. Works with any CRT Filter, or none." },
        .{ "CrtFilter", "Draws the picture like an old screen. Scanlines adds dark lines between the rows. Arcade is a monitor up close, Soft a gentler one. Consumer TV is a home TV, with a glow and soft edges. Composite blends the dithering the way a TV cable did. LCD is a handheld's grid." },
        .{ "DynamicLighting", "Light dark dungeon rooms with flickering light from the lantern, torches and fire, instead of the original's flat darkness. On a GPU, walls cast soft shadows and flames glow. Outdoors, warp pads glow, and in the storm lightning flashes and the lantern lights the night. Needs New Renderer." },
        .{ "LightingQuality", "Full casts soft shadows from walls, gives flames a glow, and blooms magic, crystals and the Master Sword. Simple keeps the light and its flicker without them, for slower graphics cards. Without a GPU it's always simple." },
        .{ "RoomDimming", "How much rooms that aren't dark are dimmed so their torches, braziers and candles have something to light. Rooms without any are left as the original draws them. 0 leaves every room that way, with just the flames' glow." },
        .{ "Particles", "Embers, sparks, leaves, splashes, heavier rain, fireflies in the Lost Woods, dust in window light, and on a GPU, heat shimmering over the desert and lava and shockwaves from bombs. Needs New Renderer." },
        .{ "HdWater", "Redraws water and lava at your screen's resolution instead of in big pixels. Water gets waves, drifting light, foam, reflections and a wake behind Link as he swims. Lava churns under a cooling crust with glowing cracks and slow bubbles. Needs a GPU and New Renderer." },
        .{ "DimFlashes", "Tone down flashing effects, as the Virtual Console releases did." },
        .{ "Volume", "How loud the whole game plays, music and sound effects together, MSU music included. Changes as you move it. Shift and plus or minus on the keyboard change it too." },
        .{ "EnableAudio", "Play sound and music at all." },
        .{ "AudioFreq", "The rate the game mixes its sound at. Higher is clearer. MSU audio sets its own." },
        .{ "AudioChannels", "Mono or stereo sound." },
        .{ "AudioSamples", "The sound buffer's size. Smaller means less delay before you hear things, larger helps if the sound crackles." },
        .{ "EnableMSU", "Play an MSU music pack instead of the SNES music. Tracks can be .pcm, FLAC or Ogg Vorbis. Deluxe packs give each area its own track, and Opuz packs are their own compressed kind." },
        .{ "MSUVolume", "How loud MSU music plays." },
        .{ "MSUPath", "Which MSU pack plays. Import MSU-1 puts each pack in a folder of its own under msu, and left or right here switches between them." },
        .{ "ResumeMSU", "Pick an overworld area's MSU track up where it left off when you come back to it." },
        .{ "MSUFinishCues", "Let short MSU music cues, like the mirror warp, play to their end before the next track starts." },
        .{ "ItemSwitchLR", "Switch items with L and R, and reorder the inventory with Y and a direction. Hold L or R on an item to put it on that button." },
        .{ "ItemOnX", "A second item on X. Hold X on an item in the item menu to put it there, then press X to use it. A box under your item shows it, and the map moves to L and R pressed together." },
        .{ "TurnWhileDashing", "Steer while running with the Pegasus Boots." },
        .{ "MirrorToDarkworld", "Let the Magic Mirror take you to the Dark World as well as back from it." },
        .{ "CollectItemsWithSword", "Pick up hearts, rupees and other drops by hitting them with the sword." },
        .{ "BreakPotsWithSword", "Smash pots with a level 2 sword or better." },
        .{ "DisableLowHealthBeep", "Silence the beeping when Link is low on hearts." },
        .{ "SkipIntroOnKeypress", "Let a button press skip the opening." },
        .{ "ShowMaxItemsInYellow", "Show rupees, bombs and arrows in yellow when they're full." },
        .{ "MoreActiveBombs", "Allow four bombs out at once instead of two." },
        .{ "CarryMoreRupees", "Hold up to 9999 rupees instead of 999." },
        .{ "MiscBugFixes", "Fix a number of the original game's bugs that don't change how it plays." },
        .{ "GameChangingBugFixes", "Fix bugs whose fixes do change how the game plays." },
        .{ "CancelBirdTravel", "Let X cancel the bird's flight before it takes off." },
        .{ "ContinueFromDungeon", "Save inside a dungeon and the file starts at that dungeon's entrance when you continue it, the way it does when you fall in battle, instead of asking for Link's House, the Sanctuary or the mountain cave." },
        .{ "DiggingGamePity", "Have the digging game hand over its heart piece after 250 digs without one, instead of leaving it to a 1 in 32 chance a dig. The count is never saved." },
    };
    for (kDescriptions) |d| {
        if (std.mem.eql(u8, d[0], s.key)) return d[1];
    }
    return "";
}

/// A question laid over whatever screen is showing.
const Modal = enum {
    none,
    /// Asked before leaving, so a stray B does not close the window.
    quit,
    /// Asked when Build Assets is chosen, since the ROM arrives by drag.
    rom,
    /// What the selected setting does, asked for with Y or I.
    info,
    /// Where an MSU-1 pack comes from: dropped on the window, or picked.
    msu,
    /// What to call the pack just dropped or picked, before it goes in.
    msu_name,
    /// The pack going in: which track, how far, and a way to stop.
    msu_progress,
    /// A newer version: whether to install it, then how that's going.
    update,
};

const kMsuChoices = [_][]const u8{ "Folder", "Zip File" };

const kQuitChoices = [_][]const u8{ "Quit", "Stay" };
/// Stay is the default, so pressing the button again backs out rather than
/// confirming what the first press only meant to ask about.
const kQuitStay = 1;

/// The launcher is a short menu and the screens it opens: the two lists of
/// settings, and the randomizer's pages (a choice of randomizer, then the
/// ALTTPR.COM page seeds are dropped on, and what a seed says about itself).
const Screen = enum { main, settings, features, controls, achievements, hub, alttpr, details };

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
        .main, .controls, .achievements, .hub, .details => .{ .from = 0, .to = 0 },
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
    if (g_modern) return kModernListY;
    return if (screen == .alttpr) kEmuNoteY + kEmuNoteH + 10 else kListStartY;
}

fn visibleRows(screen: Screen) usize {
    if (g_modern) return kModernVisible;
    return if (screen == .alttpr) 9 else kVisibleRows;
}

// The modern sub-screens are widescreen: a list down the left, and beside it
// a panel saying more about what's picked.
const kModernRowH: f32 = 28;
const kModernListX: f32 = 40;
const kModernListW: f32 = 520;
const kModernListY: f32 = start_page.kBodyTop + 6;
const kModernVisible = 13;
const kModernPanel = Rect{ .x = 592, .y = start_page.kBodyTop, .w = start_page.kW - 40 - 592, .h = start_page.kBodyBottom - start_page.kBodyTop };
/// The seed's details, across the whole body.
const kModernDetailsBox = Rect{ .x = 40, .y = start_page.kBodyTop, .w = start_page.kW - 80, .h = start_page.kBodyBottom - start_page.kBodyTop };

/// Row `slot` of a modern list, as drawn and clicked.
fn modernRowRect(slot: usize) Rect {
    return .{ .x = kModernListX, .y = kModernListY + kModernRowH * @as(f32, @floatFromInt(slot)), .w = kModernListW, .h = kModernRowH - 2 };
}

/// The window's size: widescreen for the modern menu, 4:3 for the retro.
fn windowW() f32 {
    return if (g_modern) start_page.kW else kWindowW;
}

fn windowH() f32 {
    return if (g_modern) start_page.kH else kWindowH;
}

/// Whether the pointer is over the modern sub-screens' Back button.
var g_back_hover = false;

/// The pointer, between frames. It picks a row by moving onto one, not by
/// being over one: a nudge that stays on the same row leaves the keys'
/// choice alone, so a hand on the mouse doesn't fight the one on the arrows.
const Pointer = struct {
    x: f32 = -1,
    y: f32 = -1,
    /// What it last moved onto, as a place on the screen (a slot, not a
    /// row), so a list scrolling under a still pointer isn't a move.
    over: ?usize = null,
    /// Wheel travel short of a whole row, for trackpads that send slivers.
    wheel: f32 = 0,
    /// Holding a scrollbar.
    dragging: bool = false,

    /// Whether `target` is somewhere new, remembering it either way.
    fn enters(self: *Pointer, target: ?usize) bool {
        defer self.over = target;
        return target != null and !std.meta.eql(target, self.over);
    }

    fn addWheel(self: *Pointer, dy: f32) void {
        // Turning back throws away what was going the other way.
        if (dy * self.wheel < 0) self.wheel = 0;
        self.wheel += dy;
    }

    /// Whole rows of wheel travel, up positive, keeping the rest.
    fn takeWheel(self: *Pointer) i32 {
        const steps: i32 = @intFromFloat(@trunc(self.wheel));
        self.wheel -= @floatFromInt(steps);
        return steps;
    }

    /// A new screen or question: what it was over there means nothing here.
    fn forget(self: *Pointer) void {
        self.over = null;
        self.wheel = 0;
        self.dragging = false;
    }
};
var g_pointer = Pointer{};

/// `top` moved by `by` rows, kept between the first and `max_top`.
fn scrolled(top: usize, by: i32, max_top: usize) usize {
    const want = @as(i64, @intCast(top)) + by;
    return @intCast(std.math.clamp(want, 0, @as(i64, @intCast(max_top))));
}

/// The cursor brought into rows `top` to `top + shown`, onto the nearest row
/// that can be picked, when the list has scrolled out from under it.
fn keepInView(screen: Screen, cursor: usize, top: usize, shown: usize) usize {
    const end = @min(rowCount(screen), top + shown);
    if (cursor >= top and cursor < end) return cursor;
    if (cursor < top) {
        var p = top;
        while (p < end) : (p += 1) if (rowSelectable(screen, p)) return p;
    } else {
        var p = end;
        while (p > top) {
            p -= 1;
            if (rowSelectable(screen, p)) return p;
        }
    }
    return cursor;
}

/// A scrollbar the pointer can take hold of: where it's drawn, widened to
/// something a hand can hit, and what it scrolls.
const Scroll = struct {
    track: Rect,
    len: usize,
    shown: usize,

    /// The top that puts the thumb's middle under `py`.
    fn topAt(self: Scroll, py: f32) usize {
        const frac = std.math.clamp((py - self.track.y) / self.track.h, 0, 1);
        const want = frac * @as(f32, @floatFromInt(self.len)) - @as(f32, @floatFromInt(self.shown)) / 2;
        return @min(self.len -| self.shown, @as(usize, @intFromFloat(@max(0, @round(want)))));
    }
};

/// The modern screen's scrollbar, when it has one with somewhere to go.
fn scrollOf(screen: Screen) ?Scroll {
    if (!g_modern) return null;
    const list_track = struct {
        fn of(shown: usize) Rect {
            return .{ .x = kModernListX + kModernListW + 4, .y = kModernListY, .w = 20, .h = @as(f32, @floatFromInt(shown)) * kModernRowH - 2 };
        }
    }.of;
    const s: Scroll = switch (screen) {
        .settings, .features, .alttpr => .{ .track = list_track(visibleRows(screen)), .len = rowCount(screen), .shown = visibleRows(screen) },
        .achievements => .{ .track = list_track(achVisible()), .len = kAchRows, .shown = achVisible() },
        .details => .{ .track = .{ .x = kModernDetailsBox.x + kModernDetailsBox.w - 24, .y = kModernDetailsBox.y + 14, .w = 20, .h = kModernDetailsBox.h - 28 }, .len = detailCount(), .shown = kDetailsRows },
        else => return null,
    };
    return if (s.len > s.shown) s else null;
}

/// Which of a question's buttons is under a point.
fn choiceUnder(n: usize, px: f32, py: f32) ?usize {
    for (0..n) |i| if (modalChoiceRect(i).contains(px, py)) return i;
    return null;
}

/// A modern list's value, as drawn beside a setting.
const ValueBufs = struct { v: [64]u8 = undefined, s: [64]u8 = undefined, f: [80]u8 = undefined };

fn modernValue(p: *const ui.Paint, st: Setting, raw: []const u8, b: *ValueBufs) []const u8 {
    return p.fit(.strong, soft(&b.s, displayValue(&b.v, st, raw)), 220, &b.f);
}

/// Whether a click on row `slot` of a modern list landed on the arrow left
/// of its value, which steps it back rather than on.
fn onLeftArrow(ini: *const Ini, screen: Screen, pos: usize, slot: usize, px: f32, py: f32) bool {
    if (!g_modern) return false;
    const page = modernPage() orelse return false;
    const at = rowAt(screen, pos);
    if (at >= kSettings.len) return false;
    const st = kSettings[at];
    if (isSection(st) or isFixed(st)) return false;
    var b = ValueBufs{};
    const vw = page.paint.textWidth(.strong, modernValue(&page.paint, st, ini.values[at] orelse "(missing)", &b));
    const r = modernRowRect(slot);
    const right = r.x + r.w - 20;
    return (Rect{ .x = right - vw - 30, .y = r.y, .w = 28, .h = r.h }).contains(px, py);
}

const kMainItems = [_][]const u8{ "Settings", "Features", "Controls", "Achievements", "Save Settings", "Build Assets", "Tools", "Import MSU-1", "Play", "Randomizer", "Update" };
const kMainControls = 2;
const kMainAchievements = 3;
const kMainSave = 4;
const kMainBuild = 5;
/// The asset tools' window: modding, translations, the music and pictures.
pub const kMainTools = 6;
/// Only there while MSU audio is on: there's no pack to want otherwise.
const kMainImport = 7;
const kMainLaunch = 8;
const kMainRandomizer = 9;
/// Only there when there's a newer version, in the title's third line. Last,
/// so down from Randomizer wraps through it to the top.
const kMainUpdate = 10;

/// Whether MSU audio is on in the ini, which brings Import MSU-1 onto the
/// main page. Set from the ini every frame, so it follows the setting.
var g_msu_on = false;

fn msuOnIn(ini: *const Ini) bool {
    const i = settingIndex("Sound", "EnableMSU") orelse return false;
    const v = std.mem.trim(u8, ini.values[i] orelse "", " \t");
    return v.len != 0 and !std.mem.eql(u8, v, "0") and !std.ascii.eqlIgnoreCase(v, "false");
}

/// Packs used to be installed loose in msu/, before there could be more
/// than one. Once at startup, a pack still loose there moves into a folder
/// of its own, and MSUPath follows it if that's what it pointed at. Runs
/// whether or not the start menu shows, since the game reads MSUPath too.
pub fn tidyMsu(alloc: std.mem.Allocator) void {
    const moved = msu_import.moveLoosePack(alloc, msu_import.kLibrary) orelse return;
    defer {
        alloc.free(moved.from);
        alloc.free(moved.to);
    }
    std.debug.print("Moved the MSU pack in {s} to {s}\n", .{ moved.from, moved.to });
    var ini = Ini.load(alloc, "zelda3.ini") catch return;
    defer ini.deinit();
    const i = settingIndex("Sound", "MSUPath") orelse return;
    const cur = std.mem.trim(u8, ini.values[i] orelse "", " \t");
    if (cur.len != 0 and !tools_ops.samePath(cur, moved.from)) return;
    ini.set(i, moved.to) catch return;
    ini.save("zelda3.ini") catch {};
}

/// Where MSU tracks go, as the ini has it.
fn msuPathIn(ini: *const Ini) []const u8 {
    const i = settingIndex("Sound", "MSUPath") orelse return "msu/alttp_msu-";
    const v = std.mem.trim(u8, ini.values[i] orelse "", " \t");
    return if (v.len == 0) "msu/alttp_msu-" else v;
}

/// Whether the front page is the modern one, from the ini every frame like
/// g_msu_on, so it changes as soon as the setting does.
var g_modern = false;

fn modernIn(ini: *const Ini) bool {
    const i = settingIndex("General", "StartMenuStyle") orelse return true;
    const v = std.mem.trim(u8, ini.values[i] orelse "modern", " \t");
    return !std.ascii.eqlIgnoreCase(v, "retro");
}

/// Whether StartBanner wants Nintendo's banner in the modern page's corner,
/// from the ini every frame like g_modern.
var g_logo = false;

fn logoIn(ini: *const Ini) bool {
    const i = settingIndex("General", "StartBanner") orelse return false;
    return std.mem.eql(u8, std.mem.trim(u8, ini.values[i] orelse "", " \t"), "1");
}

/// The modern page's text and glow, made once there's a renderer.
var g_page: ?start_page.Page = null;

fn modernPage() ?*const start_page.Page {
    if (!g_modern) return null;
    return if (g_page) |*p| p else null;
}

/// The front page's entries as the modern page draws them.
const PageItems = struct {
    items: [kMainItems.len]start_page.Item = undefined,
    update_buf: [64]u8 = undefined,
};

fn pageItems(out: *PageItems) []const start_page.Item {
    for (kMainItems, 0..) |label, i| {
        out.items[i] = .{
            .label = label,
            .shown = mainShown(i),
            .role = switch (i) {
                kMainLaunch => .play,
                kMainRandomizer => .randomizer,
                kMainUpdate => .update,
                else => .entry,
            },
        };
    }
    // "Update to v1.9", not the retro page's shouting.
    var ver = updater.offerLabel();
    var lower_v: [32]u8 = undefined;
    if (ver.len > 1 and ver.len <= lower_v.len and ver[0] == 'V' and std.ascii.isDigit(ver[1])) {
        @memcpy(lower_v[0..ver.len], ver);
        lower_v[0] = 'v';
        ver = lower_v[0..ver.len];
    }
    out.items[kMainUpdate].label = std.fmt.bufPrint(&out.update_buf, "Update to {s}", .{ver}) catch "Update";
    return &out.items;
}

fn mainShown(i: usize) bool {
    if (i == kMainUpdate) return updateShown();
    return i != kMainImport or g_msu_on;
}

// ------------------------------------------------------------------ updates

/// Whether the ini wants update checks, which it does unless told not to.
pub fn updatesOnIn(ini: *const Ini) bool {
    const i = settingIndex("General", "CheckForUpdates") orelse return false;
    const v = std.mem.trim(u8, ini.values[i] orelse "1", " \t");
    return !std.mem.eql(u8, v, "0") and !std.ascii.eqlIgnoreCase(v, "false");
}

pub fn updateChannelIn(ini: *const Ini) updater.Channel {
    const i = settingIndex("General", "UpdateChannel") orelse return .releases;
    return updater.Channel.fromName(ini.values[i] orelse "");
}

/// Asks again after the update settings change, or forgets what was found
/// once they're off.
fn recheckUpdates(ini: *const Ini) void {
    if (updatesOnIn(ini)) updater.check(updateChannelIn(ini)) else updater.forget();
}

/// The Update button shows from when something newer turns up until the
/// game restarts into it.
fn updateShown() bool {
    return switch (updater.phase()) {
        .available, .downloading, .installing, .ready, .failed => true,
        else => false,
    };
}

fn updateButtonLabel(buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "UPDATE TO {s}", .{updater.offerLabel()}) catch "UPDATE";
}

fn updateRect() Rect {
    var buf: [64]u8 = undefined;
    const w = textWidth(updateButtonLabel(&buf), kScale) + 40;
    // Clear of the title above and the rule below.
    return .{ .x = kWindowW / 2 - w / 2, .y = 36 + kRowH * 2 - 2, .w = w, .h = kRowH + 2 };
}

/// Which of the update dialog's two buttons is picked.
var g_update_choice: usize = 0;
const kUpdateChoices = [_][]const u8{ "Update", "Not Now" };
const kUpdateFailedChoices = [_][]const u8{ "Open Page", "Close" };

/// Which of the MSU dialog's two buttons is picked: a folder, or a zip.
var g_msu_choice: usize = 0;

/// The system picker answers on a thread of its own; the answer waits here,
/// under a lock, for the menu's loop to pick it up.
var g_msu_pick_lock: ?*c.SDL_Mutex = null;
var g_msu_pick: ?[:0]u8 = null;

fn msuPickCallback(userdata: ?*anyopaque, filelist: [*c]const [*c]const u8, filter: c_int) callconv(.c) void {
    _ = .{ userdata, filter };
    if (filelist == null or filelist[0] == null) return; // failed, or cancelled
    const copy = std.heap.c_allocator.dupeSentinel(u8, std.mem.span(filelist[0]), 0) catch return;
    c.SDL_LockMutex(g_msu_pick_lock);
    defer c.SDL_UnlockMutex(g_msu_pick_lock);
    if (g_msu_pick) |old| std.heap.c_allocator.free(old);
    g_msu_pick = copy;
}

const kZipFilters = [_]c.SDL_DialogFileFilter{.{ .name = "MSU-1 pack", .pattern = "zip" }};

fn openMsuPicker(window: *c.SDL_Window, zip: bool) void {
    if (g_msu_pick_lock == null) g_msu_pick_lock = c.SDL_CreateMutex();
    if (zip) {
        c.SDL_ShowOpenFileDialog(msuPickCallback, null, window, &kZipFilters, kZipFilters.len, null, false);
    } else {
        c.SDL_ShowOpenFolderDialog(msuPickCallback, null, window, null, false);
    }
}

/// The picker's answer, once it's come. The caller frees it.
fn takeMsuPick() ?[:0]u8 {
    if (g_msu_pick_lock == null) return null;
    c.SDL_LockMutex(g_msu_pick_lock);
    defer c.SDL_UnlockMutex(g_msu_pick_lock);
    const p = g_msu_pick;
    g_msu_pick = null;
    return p;
}

/// Whether a dropped path looks like an MSU-1 pack: a folder, or a zip.
fn looksLikeMsuPack(path: [:0]const u8) bool {
    return fileio.isDir(path.ptr) or std.ascii.endsWithIgnoreCase(path, ".zip");
}

/// What the status line says while a pack goes in and once it has.
var g_msu_status_buf: [64]u8 = undefined;

/// The pack waiting to be named before it goes in, and the name so far.
var g_msu_src: ?[:0]u8 = null;
var g_msu_name: [64]u8 = undefined;
var g_msu_name_len: usize = 0;
/// Which of the naming dialog's buttons is picked: Import, or Cancel.
var g_msu_name_choice: usize = 0;
const kMsuNameChoices = [_][]const u8{ "Import", "Cancel" };
/// Whether the pack's .pcm tracks go in as FLAC (ticked unless unticked),
/// how many .pcm tracks it has (none, and there's no box to tick), and
/// whether the keys or a pad have the box picked rather than the name.
var g_msu_flac = true;
var g_msu_pcm: usize = 0;
var g_msu_on_check = false;

/// The question up as of the last frame drawn, for the boxes that change
/// size with it.
var g_modal_now: Modal = .none;

/// The naming dialog's FLAC box.
fn msuCheckRect() Rect {
    const box = modalRect();
    if (g_modern) return .{ .x = box.x + 70, .y = box.y + 98, .w = box.w - 140, .h = 28 };
    return .{ .x = box.x + 60, .y = box.y + 22 + kRowH * 3, .w = box.w - 120, .h = kRowH + 4 };
}

fn toggleMsuFlac() void {
    g_msu_flac = !g_msu_flac;
}
const kMsuStopChoices = [_][]const u8{"Stop"};

/// The progress dialog's one button, in the middle.
fn msuStopRect() Rect {
    const r = modalChoiceRect(0);
    const box = modalRect();
    return .{ .x = box.x + (box.w - r.w) / 2, .y = r.y, .w = r.w, .h = r.h };
}

fn msuName() []const u8 {
    return g_msu_name[0..g_msu_name_len];
}

/// Puts the naming question up for the pack at `source`, with the name of
/// its folder or zip to start from.
fn askMsuName(window: *c.SDL_Window, source: []const u8) void {
    const copy = std.heap.c_allocator.dupeSentinel(u8, source, 0) catch return;
    if (g_msu_src) |old| std.heap.c_allocator.free(old);
    g_msu_src = copy;
    var buf: [64]u8 = undefined;
    const name = msu_import.packName(&buf, source);
    @memcpy(g_msu_name[0..name.len], name);
    g_msu_name_len = name.len;
    g_msu_name_choice = 0;
    g_msu_flac = true;
    g_msu_on_check = false;
    g_msu_pcm = msu_import.pcmTracksIn(std.heap.c_allocator, copy);
    _ = c.SDL_StartTextInput(window);
}

fn dropMsuName(window: *c.SDL_Window) void {
    if (g_msu_src) |src| std.heap.c_allocator.free(src);
    g_msu_src = null;
    _ = c.SDL_StopTextInput(window);
}

/// Typed (or pasted) text onto the end of the name, as much as fits whole.
fn msuNameType(text: []const u8) void {
    var i: usize = 0;
    while (i < text.len) {
        const n = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        if (i + n > text.len) break;
        const ch = text[i..][0..n];
        i += n;
        if (n == 1 and (ch[0] < 0x20 or ch[0] == 0x7f)) continue;
        if (g_msu_name_len + n > g_msu_name.len) break;
        @memcpy(g_msu_name[g_msu_name_len..][0..n], ch);
        g_msu_name_len += n;
    }
}

/// Takes the last character off the name, however many bytes it is.
fn msuNameBackspace() void {
    while (g_msu_name_len > 0) {
        g_msu_name_len -= 1;
        if (g_msu_name[g_msu_name_len] & 0xc0 != 0x80) break;
    }
}

/// A pack going in, on a thread of its own so the window keeps drawing and
/// can say how far it's got.
const MsuJob = struct {
    source: [:0]u8,
    name: []u8,
    flac: bool,
    status: msu_import.Status = .{},
    finished: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    // Set by the thread before `finished`.
    err: ?msu_import.Error = null,
    imported: msu_import.Imported = .{ .tracks = 0 },
    msu_path: ?[]u8 = null,

    fn run(self: *MsuJob) void {
        if (msu_import.importNamed(std.heap.c_allocator, self.source, msu_import.kLibrary, self.name, .{ .flac = self.flac, .status = &self.status })) |got| {
            self.imported = got.imported;
            self.msu_path = got.msu_path;
        } else |err| {
            self.err = err;
        }
        self.finished.store(true, .release);
    }

    fn destroy(self: *MsuJob) void {
        const a = std.heap.c_allocator;
        a.free(self.source);
        a.free(self.name);
        if (self.msu_path) |p| a.free(p);
        a.destroy(self);
    }
};
var g_msu_job: ?*MsuJob = null;
/// Whether the pointer's over Stop, which lights it up.
var g_msu_stop_hover = false;

/// Starts the named pack going in. False when it couldn't.
fn startMsuImport() bool {
    const a = std.heap.c_allocator;
    const src = g_msu_src orelse return false;
    const job = a.create(MsuJob) catch return false;
    const name = a.dupe(u8, if (std.mem.trim(u8, msuName(), " ").len == 0) "Pack" else msuName()) catch {
        a.destroy(job);
        return false;
    };
    job.* = .{ .source = src, .name = name, .flac = g_msu_flac and g_msu_pcm != 0 };
    g_msu_src = null;
    job.thread = std.Thread.spawn(.{}, MsuJob.run, .{job}) catch {
        job.destroy();
        return false;
    };
    g_msu_job = job;
    return true;
}

/// Once the pack's in (or isn't): makes it the one that plays, and says
/// how it went. Null while it's still going.
fn finishMsuImport(ini: *Ini, dirty: *bool) ?[]const u8 {
    const job = g_msu_job orelse return null;
    if (!job.finished.load(.acquire)) return null;
    if (job.thread) |t| t.join();
    g_msu_job = null;
    defer job.destroy();
    if (job.err) |err| return msu_import.describe(err);
    // The pack just brought in is the one to hear, from now on.
    if (settingIndex("Sound", "MSUPath")) |mi| {
        if (ini.set(mi, job.msu_path.?)) |_| {
            if (ini.save("zelda3.ini")) |_| {
                dirty.* = false;
            } else |_| {
                dirty.* = true;
            }
        } else |_| {}
    }
    const got = job.imported;
    if (got.flac != 0)
        return std.fmt.bufPrint(&g_msu_status_buf, "IMPORTED {d} MSU-1 TRACKS AS FLAC", .{got.tracks}) catch "IMPORTED";
    return std.fmt.bufPrint(&g_msu_status_buf, "IMPORTED {d} MSU-1 TRACKS", .{got.tracks}) catch "IMPORTED";
}

/// Leaving the menu with a pack half in: stop it, and wait for it to.
fn stopMsuImport() void {
    const job = g_msu_job orelse return;
    job.status.cancel.store(true, .release);
    if (job.thread) |t| t.join();
    g_msu_job = null;
    job.destroy();
}

/// What the progress dialog says it's doing, and how far along it is.
fn msuProgressText(buf: []u8) struct { doing: []const u8, frac: f32 } {
    const job = g_msu_job orelse return .{ .doing = "", .frac = 1 };
    const st = &job.status;
    const track = st.track.load(.acquire);
    const tracks = st.tracks.load(.acquire);
    const total = st.total.load(.acquire);
    const frac: f32 = if (total == 0) 0 else @min(1, @as(f32, @floatFromInt(st.done.load(.acquire))) / @as(f32, @floatFromInt(total)));
    const pct: u32 = @intFromFloat(frac * 100);
    const doing = if (st.cancel.load(.acquire))
        "Stopping after this track..."
    else switch (st.phase.load(.acquire)) {
        .reading => "Reading the pack...",
        .copying => std.fmt.bufPrint(buf, "Copying track {d} of {d}  \u{00b7}  {d}%", .{ track, tracks, pct }) catch "",
        .shrinking => std.fmt.bufPrint(buf, "Turning track {d} of {d} into FLAC  \u{00b7}  {d}%", .{ track, tracks, pct }) catch "",
        .finishing => "Putting it in place...",
    };
    return .{ .doing = doing, .frac = frac };
}

/// The randomizer page's two choices. Only one exists yet.
const kHubItems = [_][]const u8{ "BUILT-IN RANDOMIZER", "ALTTPR.COM RANDOMIZER" };
const kHubBuiltIn = 0;
const kHubAlttpr = 1;

const Pads = kit.Pads;
const configureJoysticks = kit.configureJoysticks;
const faceAction = kit.faceAction;
const Held = kit.Held;
const Repeat = kit.Repeat;

/// What is sitting in zelda3_assets.dat.
pub const AssetState = enum {
    missing,
    /// Present and matching the file the old Python tool builds from a US ROM.
    verified,
    /// Built for this version, but not from the plain US ROM alone: a mod,
    /// or extra languages. The game loads it, so it plays.
    custom,
    /// Present, but not a file this version loads. Usually an older .dat.
    unrecognized,

    fn line(self: AssetState) []const u8 {
        return switch (self) {
            .missing => "ASSETS MISSING",
            .verified => "ASSETS VERIFIED",
            .custom => "CUSTOM ASSETS - MOD OR LANGUAGES",
            .unrecognized => "ASSETS OUT OF DATE - BUILD AGAIN",
        };
    }

    fn color(self: AssetState) Rgb {
        return switch (self) {
            .missing => kColorWarn,
            .verified, .custom => kColorOk,
            .unrecognized => kColorWarn,
        };
    }

    /// Whether Play can go ahead. Only "the standard file" used to count,
    /// which kept every mod and translation from starting at all.
    pub fn playable(self: AssetState) bool {
        return self == .verified or self == .custom;
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
    if (std.mem.eql(u8, &hex, asset_all.kReferenceDigest)) return .verified;
    return if (@import("asset_pack.zig").loadsInGame(data)) .custom else .unrecognized;
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
        .main, .settings, .controls, .achievements, .hub, .details => 0,
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
            .achievements => g_ach_row,
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
    g_modern = modernIn(&ini);
    defer g_modern = false;
    const surface = c.SDL_CreateSurface(@intFromFloat(windowW()), @intFromFloat(windowH()), c.SDL_PIXELFORMAT_XRGB8888) orelse return error.SdlSurface;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    g_page = start_page.Page.init(renderer);
    defer {
        g_page.?.deinit();
        g_page = null;
    }
    g_logo = logoIn(&ini);
    defer start_logo.release();
    if (seed) |sp| _ = loadSeed(sp);
    const screen = std.meta.stringToEnum(Screen, which) orelse .alttpr;
    g_spoilers = std.c.getenv("SPOILERS") != null;
    if (std.c.getenv("DETAILS_TOP")) |t| g_details_top = std.fmt.parseInt(usize, std.mem.span(t), 10) catch 0;
    // CTL_ROW=n picks a row on the Controls screen; CAPTURE=1 has it waiting.
    if (std.c.getenv("CTL_ROW")) |t| g_ctl_row = std.fmt.parseInt(usize, std.mem.span(t), 10) catch 0;
    if (g_ctl_row >= ctlVisible()) g_ctl_top = g_ctl_row + 1 - ctlVisible();
    if (std.c.getenv("CAPTURE") != null) g_ctl_capture = g_ctl_row;
    // LIST_ROW=n picks a row on the lists; INFO=1 has its info box open.
    const row: usize = if (std.c.getenv("LIST_ROW")) |t| std.fmt.parseInt(usize, std.mem.span(t), 10) catch 0 else 0;
    const row_top: usize = if (row >= visibleRows(screen)) row + 1 - visibleRows(screen) else 0;
    const cursor = [_]usize{ row, row, row };
    const top = [_]usize{ row_top, row_top, row_top };
    // UPDATE=available|downloading|failed pretends there's a newer version;
    // UPDATE_MODAL=1 has its dialog up, UPDATE_PICKED=1 its button picked.
    if (std.c.getenv("UPDATE")) |u| {
        updater.pretend(std.meta.stringToEnum(updater.Phase, std.mem.span(u)) orelse .available, "V1.8");
    }
    var modal: Modal = if (std.c.getenv("INFO") != null) .info else if (std.c.getenv("MSU_IMPORT") != null) .msu else if (std.c.getenv("UPDATE_MODAL") != null) .update else .none;
    // MSU_NAME="Some Pack" has the naming question up; MSU_PROGRESS=n has a
    // pack n percent of the way in, at track 12 of 34.
    if (std.c.getenv("MSU_NAME")) |n| {
        const name = std.mem.span(n);
        const len = @min(name.len, g_msu_name.len);
        @memcpy(g_msu_name[0..len], name[0..len]);
        g_msu_name_len = len;
        modal = .msu_name;
        // MSU_PCM=n says the pack has n .pcm tracks, MSU_FLAC=0 unticks the
        // box, MSU_CHECK=1 has it picked.
        g_msu_pcm = if (std.c.getenv("MSU_PCM")) |t| std.fmt.parseInt(usize, std.mem.span(t), 10) catch 34 else 34;
        g_msu_flac = std.c.getenv("MSU_FLAC") == null;
        g_msu_on_check = std.c.getenv("MSU_CHECK") != null;
    }
    var fake_job: MsuJob = undefined;
    if (std.c.getenv("MSU_PROGRESS")) |t| {
        const pct = std.fmt.parseInt(u64, std.mem.span(t), 10) catch 40;
        fake_job = .{ .source = undefined, .name = @constCast("Zelda Remix"), .flac = true };
        fake_job.status.phase.store(.shrinking, .release);
        fake_job.status.track.store(12, .release);
        fake_job.status.tracks.store(34, .release);
        fake_job.status.total.store(100, .release);
        fake_job.status.done.store(pct, .release);
        g_msu_job = &fake_job;
        modal = .msu_progress;
    }
    defer g_msu_job = null;
    g_msu_on = msuOnIn(&ini);
    if (screen == .achievements) {
        g_ach_unlocked = achievement_list.Unlocked.load(alloc);
        g_ach_row = row;
        if (row >= achVisible()) g_ach_top = row + 1 - achVisible();
    }
    // MAIN_ROW=n picks an entry on the front page.
    const main_pick: usize = if (std.c.getenv("UPDATE_PICKED") != null) kMainUpdate else if (std.c.getenv("MAIN_ROW")) |t| std.fmt.parseInt(usize, std.mem.span(t), 10) catch kMainControls else kMainControls;
    // ASSETS=check shows what's really there, rather than the verified file
    // every other shot assumes.
    const assets: AssetState = if (std.c.getenv("ASSETS") != null) checkAssets(alloc) else .verified;
    drawScreen(renderer, &ini, viewOf(screen, if (screen == .main) main_pick else kMainRandomizer, cursor, top, "", false, assets, modal, kQuitStay));
    if (!c.SDL_SaveBMP(surface, path)) return error.SaveFailed;
}

fn drawScreen(renderer: *c.SDL_Renderer, ini: *const Ini, v: View) void {
    g_modal_now = v.modal;
    if (modernPage()) |page| {
        drawModern(page, ini, v);
        _ = c.SDL_RenderPresent(renderer);
        return;
    }
    fillBackground(renderer);
    drawFrame(renderer, 16, 16, kWindowW - 32, kWindowH - 32);

    drawHeader(renderer, v.screen);

    switch (v.screen) {
        .main => drawMain(renderer, v),
        .hub => drawHub(renderer, v),
        .controls => drawControls(renderer, ini, v),
        .achievements => drawAchievements(renderer, v),
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

/// The seconds the modern page's motes and glows go by; a menu shot can
/// pin it with TIME=.
fn pageTime() f32 {
    if (std.c.getenv("TIME")) |t| return std.fmt.parseFloat(f32, std.mem.span(t)) catch 2;
    return @as(f32, @floatFromInt(c.SDL_GetTicks())) / 1000;
}

fn drawModernMain(page: *const start_page.Page, v: View) void {
    var pi = PageItems{};
    var vbuf: [40]u8 = undefined;
    var hints: [5]start_page.Hint = undefined;
    const status = if (v.status.len != 0) v.status else if (v.dirty) "UNSAVED CHANGES" else "";
    page.draw(.{
        .items = pageItems(&pi),
        .cursor = v.cursor,
        .assets_line = v.assets.line(),
        .assets_ok = v.assets.playable(),
        .assets_note = if (v.assets == .missing) "Drag a .sfc ROM onto this window" else "",
        .status = status,
        .status_warn = v.status.len == 0 and v.dirty,
        .version = if (updater.installed == .dev) "Dev build" else updater.installedLabel(&vbuf),
        .hints = pageHints(v, &hints),
        .time = pageTime(),
        .dimmed = v.modal != .none,
        .logo = if (g_logo) start_logo.texture(page.paint.r) else null,
        .logo_aspect = start_logo.aspect(),
    });
}

/// The modern page's questions: the retro ones' words in its own dress, in
/// the same places, so the same clicks answer them.
fn drawModernModal(page: *const start_page.Page, v: View) void {
    const L = start_page.Line;
    var rects: [2]Rect = .{ modalChoiceRect(0), modalChoiceRect(1) };
    var buf: [64]u8 = undefined;
    var buf2: [64]u8 = undefined;
    var mine: [40]u8 = undefined;
    // Lines made as it runs live here, for as long as the dialog does.
    var lines: [3]L = undefined;
    var d = start_page.Dialog{ .box = modalRect(), .title = "" };
    switch (v.modal) {
        .quit => {
            d.title = "Quit the game?";
            d.lines = if (v.dirty) &.{L{ .text = "Unsaved changes will be lost", .tone = .warn }} else &.{L{ .text = "Hyrule will be here when you get back" }};
            d.choices = &kQuitChoices;
            d.choice_rects = &rects;
            d.picked = v.quit_choice;
        },
        .rom => {
            d.title = "Drop a ROM on this window";
            if (g_rom_path != null) {
                d.lines = &.{
                    L{ .text = "Any .sfc file. The name doesn't matter, it's checked." },
                    L{ .text = "" },
                    L{ .text = "Or press A / Enter to use", .tone = .plain },
                    L{ .text = kRomPath, .tone = .accent },
                };
            } else {
                d.lines = &.{
                    L{ .text = "Any .sfc file. The name doesn't matter, it's checked." },
                    L{ .text = "" },
                    L{ .text = "B / Esc to cancel" },
                };
            }
        },
        .msu_name => {
            d.title = "Name this pack";
            d.field = msuName();
            d.caret = !g_msu_on_check and @mod(c.SDL_GetTicks(), 1000) < 600;
            if (g_msu_pcm != 0) d.check = .{
                .rect = msuCheckRect(),
                .label = "Store as FLAC: the same sound in half the space",
                .on = g_msu_flac,
                .focused = g_msu_on_check,
            };
            lines[0] = if (msu_import.packExists(msuName()))
                .{ .text = "You have a pack called that. This replaces it.", .tone = .warn }
            else if (g_msu_pcm == 0)
                .{ .text = "Its tracks are already compressed, so they go in as they are." }
            else
                .{ .text = "Type to change the name. It goes beside your other packs." };
            d.lines = lines[0..1];
            d.choices = &kMsuNameChoices;
            d.choice_rects = &rects;
            d.picked = g_msu_name_choice;
        },
        .msu_progress => {
            d.title = "Importing";
            const pr = msuProgressText(&buf2);
            const name = if (g_msu_job) |j| j.name else "";
            lines[0] = .{ .text = name, .tone = .accent };
            lines[1] = .{ .text = pr.doing };
            d.lines = lines[0..2];
            d.progress = pr.frac;
            d.progress_y = 108;
            rects[0] = msuStopRect();
            d.choices = &kMsuStopChoices;
            d.choice_rects = rects[0..1];
            d.picked = if (g_msu_stop_hover) 0 else 1;
        },
        .msu => {
            d.title = "Import an MSU-1 pack";
            d.lines = &.{
                L{ .text = "Drop a folder or .zip here, or browse for one" },
                L{ .text = "Kept beside your other packs, and played from now on" },
            };
            d.choices = &kMsuChoices;
            d.choice_rects = &rects;
            d.picked = g_msu_choice;
        },
        .update => switch (updater.phase()) {
            .downloading, .installing, .ready => |ph| {
                d.title = switch (ph) {
                    .downloading => std.fmt.bufPrint(&buf, "Downloading {s}", .{updater.offerLabel()}) catch "Downloading",
                    .installing => "Installing...",
                    else => "Restarting...",
                };
                const pr = updater.progress();
                d.progress = if (ph != .downloading) 1 else if (pr.total == 0) 0 else @min(1, @as(f32, @floatFromInt(pr.done)) / @as(f32, @floatFromInt(pr.total)));
                if (ph == .downloading) {
                    const mb = 1024.0 * 1024.0;
                    const size = std.fmt.bufPrint(&buf2, "{d:.1} of {d:.1} MB", .{ @as(f32, @floatFromInt(pr.done)) / mb, @as(f32, @floatFromInt(pr.total)) / mb }) catch "";
                    lines = .{ L{ .text = "" }, L{ .text = "" }, L{ .text = size } };
                    d.lines = &lines;
                }
            },
            .failed => {
                d.title = "Couldn't update";
                lines[0] = .{ .text = updater.message(), .tone = .warn };
                lines[1] = .{ .text = "The release page has it to download by hand" };
                d.lines = lines[0..2];
                d.choices = &kUpdateFailedChoices;
                d.choice_rects = &rects;
                d.picked = g_update_choice;
            },
            else => {
                d.title = std.fmt.bufPrint(&buf, "Update to {s}?", .{updater.offerLabel()}) catch "Update?";
                lines[0] = .{ .text = std.fmt.bufPrint(&buf2, "You have {s}", .{updater.installedLabel(&mine)}) catch "", .tone = .plain };
                lines[1] = .{ .text = "Downloads from GitHub, then restarts. Saves stay put." };
                d.lines = lines[0..2];
                d.choices = &kUpdateChoices;
                d.choice_rects = &rects;
                d.picked = g_update_choice;
            },
        },
        // Only the lists have info; the front page has nothing to explain.
        .info, .none => return,
    }
    page.dialog(d);
}

/// What the buttons do, for the modern page's footer: the front page's, or
/// a question's while one is up.
fn pageHints(v: View, out: *[5]start_page.Hint) []const start_page.Hint {
    const choose = start_page.Hint{ .key = "\xe2\x86\x90 \xe2\x86\x92", .action = "Choose" };
    const cancel = start_page.Hint{ .key = "B / Esc", .action = "Cancel" };
    const list: []const start_page.Hint = switch (v.modal) {
        .none => &.{ .{ .key = "A / Enter", .action = "Select" }, .{ .key = "X / S", .action = "Save" }, .{ .key = "B / Esc", .action = "Quit" } },
        .quit => &.{ choose, .{ .key = "A / Enter", .action = "Confirm" }, cancel },
        .rom => &.{ .{ .key = "Drop", .action = "A file on the window" }, cancel },
        .info => &.{.{ .key = "A / B", .action = "Close" }},
        .msu => &.{ choose, .{ .key = "A / Enter", .action = "Browse" }, cancel },
        .msu_name => if (g_msu_pcm != 0)
            &.{ .{ .key = "Type", .action = "Name it" }, .{ .key = "\xe2\x86\x93 Space", .action = "FLAC on/off" }, .{ .key = "Enter / A", .action = "Import" }, cancel }
        else
            &.{ .{ .key = "Type", .action = "Name it" }, .{ .key = "Enter / A", .action = "Import" }, cancel },
        .msu_progress => &.{.{ .key = "B / Esc", .action = "Stop" }},
        .update => switch (updater.phase()) {
            .downloading => &.{cancel},
            .installing, .ready => &.{},
            else => &.{ choose, .{ .key = "A / Enter", .action = "Confirm" }, cancel },
        },
    };
    @memcpy(out[0..list.len], list);
    return out[0..list.len];
}

// ------------------------------------------------------------ modern menu

const P = start_page;

/// Every screen in the modern dress: the front page, or a sub-screen's
/// header, what it shows, and the footer, with any question over the top.
fn drawModern(page: *const start_page.Page, ini: *const Ini, v: View) void {
    if (v.screen == .main) {
        drawModernMain(page, v);
        if (v.modal != .none) drawModernModal(page, v);
        return;
    }
    const t = pageTime();
    page.backdrop(t, switch (v.screen) {
        .settings => "Settings",
        .features => "Features",
        .hub => "Randomizer",
        .controls => "Controls",
        .achievements => "Achievements",
        .alttpr => "ALTTPR.com",
        .details => "Seed Details",
        .main => unreachable,
    }, g_back_hover);
    switch (v.screen) {
        .settings, .features => {
            drawModernList(page, ini, v);
            const at = rowAt(v.screen, v.cursor);
            page.panel(kModernPanel);
            if (at < kSettings.len and !isSection(kSettings[at])) drawModernAbout(page, kModernPanel.inset(22), at, ini, true);
        },
        .alttpr => {
            drawModernList(page, ini, v);
            drawModernSeed(page, v);
        },
        .achievements => drawModernAchievements(page, v),
        .controls => drawModernControls(page, ini, v),
        .hub => drawModernHub(page, v),
        .details => {
            setMsuGamePath(ini);
            drawModernDetails(page, v);
        },
        .main => unreachable,
    }

    var hints: [5]start_page.Hint = undefined;
    const note = modernNote(v);
    page.footerBar(if (v.modal != .none) pageHints(v, &hints) else subHints(v, &hints), note.text, note.col);
    if (v.modal != .none) {
        page.dim();
        if (v.modal == .info) drawModernInfo(page, ini, v) else drawModernModal(page, v);
    }
}

/// The few words at the right of a sub-screen's footer: what just happened,
/// a warning about what's picked, or that there's something to save.
fn modernNote(v: View) struct { text: []const u8, col: ui.Color } {
    if (v.status.len != 0) return .{ .text = v.status, .col = P.kTeal };
    if (v.screen == .alttpr and v.modal == .none) {
        const at = rowAt(.alttpr, v.cursor);
        const note = if (at < kSettings.len) kSettings[at].note else if (!g_seed_loaded) "DROP A SEED ON THIS WINDOW FIRST" else "";
        if (note.len != 0) return .{ .text = note, .col = P.kWarn };
    }
    if (v.dirty) return .{ .text = "UNSAVED CHANGES", .col = P.kGold };
    return .{ .text = "", .col = P.kDim };
}

/// What the buttons do on each sub-screen.
fn subHints(v: View, out: *[5]start_page.Hint) []const start_page.Hint {
    const H = start_page.Hint;
    const change = H{ .key = "\xe2\x86\x90 \xe2\x86\x92", .action = "Change" };
    const save = H{ .key = "X / S", .action = "Save" };
    const back = H{ .key = "B / Esc", .action = "Back" };
    const list: []const H = switch (v.screen) {
        .settings, .features => &.{ change, .{ .key = "Y / I", .action = "More info" }, save, back },
        .alttpr => &.{ change, .{ .key = "Start", .action = "Play" }, save, back },
        .achievements => &.{ .{ .key = "\xe2\x86\x91 \xe2\x86\x93", .action = "Browse" }, back },
        .hub => &.{ .{ .key = "A / Enter", .action = "Select" }, back },
        .controls => if (g_ctl_capture != null)
            &.{ .{ .key = "Any key or button", .action = "Assign" }, .{ .key = "Esc", .action = "Cancel" } }
        else
            &.{ .{ .key = "A / Enter", .action = "Change" }, save, back },
        .details => &.{ .{ .key = "\xe2\x86\x91 \xe2\x86\x93", .action = "Scroll" }, .{ .key = "A / Enter", .action = if (g_spoilers) "Hide spoilers" else "Show spoilers" }, back },
        .main => &.{},
    };
    @memcpy(out[0..list.len], list);
    return out[0..list.len];
}

/// The retro menu's capitals in sentence case, for the modern one's real
/// type: "IN DUNGEON" reads "In dungeon". Anything with a small letter in
/// it is already written to be read, and is left alone, and so are the
/// handful of words that are capitals anyway.
fn soft(buf: []u8, text: []const u8) []const u8 {
    for (text) |ch| if (std.ascii.isLower(ch)) return text;
    const kAcronyms = [_][]const u8{ "SNES", "MSU", "MSU-1", "KB", "MB", "GT", "ROM", "CRT", "PC", "HD", "MSUPATH", "SFC", "OK", "DX" };
    const kNames = [_][]const u8{ "JAPANESE", "GANON", "GITHUB", "ALTTPR.COM", "HYRULE", "LINK" };
    const n = @min(buf.len, text.len);
    @memcpy(buf[0..n], text[0..n]);
    var i: usize = 0;
    var first = true;
    while (i < n) {
        while (i < n and buf[i] == ' ') i += 1;
        const start = i;
        while (i < n and buf[i] != ' ') i += 1;
        const word = buf[start..i];
        if (word.len == 0) break;
        // The word without what's around it, to look up.
        var a: usize = 0;
        var b: usize = word.len;
        while (a < b and !std.ascii.isAlphanumeric(word[a])) a += 1;
        while (b > a and !std.ascii.isAlphanumeric(word[b - 1])) b -= 1;
        const bare = word[a..b];
        var keep = false;
        for (kAcronyms) |k| keep = keep or std.mem.eql(u8, bare, k);
        var name = false;
        for (kNames) |k| name = name or std.mem.eql(u8, bare, k);
        if (!keep) {
            for (word, 0..) |*ch, j| {
                ch.* = if ((first or name) and j == a) ch.* else std.ascii.toLower(ch.*);
            }
            if (std.mem.eql(u8, bare, "ALTTPR.COM")) @memcpy(word[a..b], "ALTTPR.com");
        }
        if (bare.len != 0) first = false;
    }
    return buf[0..n];
}

/// A settings list: headings in gold, each setting's name, and its value
/// at the right, with arrows round it once it's picked.
fn drawModernList(page: *const start_page.Page, ini: *const Ini, v: View) void {
    const p = &page.paint;
    const t = pageTime();
    const n = rowCount(v.screen);
    const shown = visibleRows(v.screen);
    var pos = v.top;
    var slot: usize = 0;
    while (pos < n and slot < shown) : ({
        pos += 1;
        slot += 1;
    }) {
        const r = modernRowRect(slot);
        const at = rowAt(v.screen, pos);
        const picked = pos == v.cursor;
        const text_y = r.y + (r.h - p.lineHeight(.item)) / 2;
        if (at >= kSettings.len) {
            // The ALTTPR.COM page's two buttons, which want a seed.
            page.band(r, picked, t);
            const play = at == kPlayRow;
            const col = if (!g_seed_loaded) P.kDim else if (play) (if (picked) P.kGoldHi else P.kGold) else if (picked) P.kCream else P.kMuted;
            p.text(.item, r.x + 26, text_y, col, if (play) "Play this seed" else "Seed details");
            if (play and g_seed_loaded) p.text(.small, r.x + r.w - 18 - p.textWidth(.small, "Start"), r.y + (r.h - p.lineHeight(.small)) / 2, P.kDim, "Start");
        } else if (isSection(kSettings[at])) {
            page.heading(r.x + 6, r.y, r.w - 6, r.h, kSettings[at].label);
        } else {
            const st = kSettings[at];
            page.band(r, picked, t);
            p.text(.item, r.x + 26, text_y, if (picked) P.kCream else P.kMuted, st.label);
            var vb = ValueBufs{};
            const value = modernValue(p, st, ini.values[at] orelse "(missing)", &vb);
            const right = r.x + r.w - 20;
            const vw = p.textWidth(.strong, value);
            const fixed = isFixed(st);
            const col = if (fixed) P.kDim else if (picked) P.kGoldHi else P.kTeal;
            p.text(.strong, right - vw, r.y + (r.h - p.lineHeight(.strong)) / 2, col, value);
            if (picked and !fixed) page.chevrons(right - vw - 14, right + 12, r.y + r.h / 2, P.kGold);
            if (st.kind == .action) p.text(.small, right - p.textWidth(.small, "A / Enter"), r.y + (r.h - p.lineHeight(.small)) / 2, if (picked) P.kGold else P.kDim, "A / Enter");
        }
    }
    if (n > shown) {
        const nf: f32 = @floatFromInt(n);
        const sf: f32 = @floatFromInt(shown);
        page.scrollbar(kModernListX + kModernListW + 12, kModernListY, sf * kModernRowH - 2, @as(f32, @floatFromInt(v.top)) / nf, sf / nf);
    }
}

/// The section a setting is under, for the line over its name.
fn sectionOf(at: usize) []const u8 {
    var i = at;
    while (i > 0) {
        i -= 1;
        if (isSection(kSettings[i])) return kSettings[i].label;
    }
    return "";
}

/// What a setting does: its section, its name, the description, what its
/// note warns of, and what it was to start with.
fn drawModernAbout(page: *const start_page.Page, box: Rect, at: usize, ini: *const Ini, show_default: bool) void {
    _ = ini;
    const p = &page.paint;
    const st = kSettings[at];
    const x = box.x;
    const w = box.w;
    var y = box.y;
    var sec_buf: [32]u8 = undefined;
    const sec = upper(&sec_buf, sectionOf(at));
    p.textEx(.eyebrow, x, y, P.kGold, P.kGold, 3, sec);
    y += 22;
    y = page.wrap(.subtitle, x, y, w, 24, P.kCream, st.label, 2) + 8;
    const bottom = box.y + box.h - if (show_default) @as(f32, 46) else 0;
    var note_buf: [80]u8 = undefined;
    const note = if (st.note.len != 0) soft(&note_buf, st.note) else "";
    const note_lines: f32 = if (note.len != 0) 2 else 0;
    const room = bottom - y - note_lines * 20 - 8;
    const lines: usize = if (room > 0) @intFromFloat(room / 20) else 0;
    y = page.wrap(.body, x, y, w, 20, P.kMuted, describe(st), lines);
    if (note.len != 0) _ = page.wrap(.body, x, y + 8, w, 20, P.kWarn, note, 2);

    if (show_default) {
        if (defaultValue(st.section, st.key)) |d| {
            const ry = box.y + box.h - 34;
            p.fill(.{ .x = x, .y = ry, .w = w, .h = 1 }, P.kChipLine);
            p.textEx(.eyebrow, x, ry + 14, P.kDim, P.kDim, 3, "DEFAULT");
            var vbuf: [64]u8 = undefined;
            var sbuf: [64]u8 = undefined;
            var fbuf: [80]u8 = undefined;
            const value = p.fit(.strong, soft(&sbuf, displayValue(&vbuf, st, d)), w - 90, &fbuf);
            p.text(.strong, x + w - p.textWidth(.strong, value), ry + 11, P.kCream, value);
        }
    }
}

/// The info box, Y on a setting: the panel's words, in a card of their own
/// over the list.
fn drawModernInfo(page: *const start_page.Page, ini: *const Ini, v: View) void {
    const at = rowAt(v.screen, v.cursor);
    if (at >= kSettings.len or isSection(kSettings[at])) return;
    const p = &page.paint;
    const box = modernInfoRect();
    const r = ui.Rect{ .x = box.x, .y = box.y, .w = box.w, .h = box.h };
    p.shadow(r, 14);
    p.box(r, 14, 1, P.kGold.alpha(110), ui.Color.hex(0x0c161c));
    start_page.diamond(p.r, r.x + r.w / 2, r.y, 5, P.kGold);
    drawModernAbout(page, box.inset(28), at, ini, true);
}

fn modernInfoRect() Rect {
    return .{ .x = (start_page.kW - 600) / 2, .y = 110, .w = 600, .h = 330 };
}

/// The seed beside the ALTTPR.COM page's list: what it is, or where to get
/// one, and why it plays in an emulator.
fn drawModernSeed(page: *const start_page.Page, v: View) void {
    const p = &page.paint;
    const box = kModernPanel;
    page.panel(box);
    const in = box.inset(22);
    const x = in.x;
    const w = in.w;
    var y = in.y;
    p.textEx(.eyebrow, x, y, P.kGold, P.kGold, 3, "SEED");
    y += 22;
    var buf: [128]u8 = undefined;
    if (!g_seed_loaded) {
        y = page.wrap(.subtitle, x, y, w, 24, P.kCream, "Drop a seed here", 1) + 6;
        y = page.wrap(.body, x, y, w, 20, P.kMuted, "Generate one at alttpr.com from the Japanese 1.0 ROM, then drag the .sfc onto this window.", 4);
    } else if (!g_seed_is_seed) {
        y = page.wrap(.subtitle, x, y, w, 24, P.kCream, p.fit(.subtitle, g_seed_name, w, &buf), 1) + 6;
        p.text(.body, x, y, P.kWarn, "Japanese 1.0 ROM, not a seed");
        y += 20;
        p.text(.body, x, y, P.kMuted, "It plays, but unrandomized");
        y += 20;
    } else {
        const info = &g_seed_info;
        // In Inter, not the title's type: a hash's capitals matter.
        p.text(.item, x, y, P.kGoldHi, p.fit(.item, info.titleText(), w, &buf));
        y += 24;
        var link_buf: [64]u8 = undefined;
        p.text(.small, x, y, P.kDim, seedLink(&link_buf, info));
        y += 24;
        // The hash, the five pictures the game shows on its file select.
        var hash_buf: [128]u8 = undefined;
        var hn: usize = 0;
        for (info.hash, 0..) |h, i| {
            const name = seed_info.kHashIcons[h];
            const sep: []const u8 = if (i == 0) "" else "  \xc2\xb7  ";
            if (hn + sep.len + name.len > hash_buf.len) break;
            @memcpy(hash_buf[hn..][0..sep.len], sep);
            hn += sep.len;
            @memcpy(hash_buf[hn..][0..name.len], name);
            hn += name.len;
        }
        y = page.wrap(.strong, x, y, w, 20, P.kTeal, hash_buf[0..hn], 2) + 6;
        var sum_buf: [128]u8 = undefined;
        const summary = std.fmt.bufPrint(&sum_buf, "{s}  \xc2\xb7  {s}  \xc2\xb7  {s}", .{ info.logic, info.mode, info.goal }) catch "";
        y = page.wrap(.body, x, y, w, 20, P.kCream, summary, 2);
        var cnt_buf: [96]u8 = undefined;
        const counts = std.fmt.bufPrint(&cnt_buf, "GT {d}  \xc2\xb7  Ganon {d}  \xc2\xb7  {d} items", .{ info.tower_crystals, info.ganon_crystals, info.total_items }) catch "";
        p.text(.body, x, y, P.kMuted, counts);
        y += 20;
        if (g_seed_has_save) {
            p.text(.body, x, y, P.kOk, "Save found beside the seed");
            y += 20;
        }
    }

    // What's picked in the list, under the seed.
    const at = rowAt(.alttpr, v.cursor);
    const bottom = in.y + in.h - 64;
    if (at < kSettings.len and describe(kSettings[at]).len != 0 and y + 60 < bottom) {
        y += 12;
        p.fill(.{ .x = x, .y = y, .w = w, .h = 1 }, P.kChipLine);
        y += 12;
        p.text(.strong, x, y, P.kCream, kSettings[at].label);
        y += 22;
        const room = bottom - y;
        _ = page.wrap(.small, x, y, w, 17, P.kMuted, describe(kSettings[at]), if (room > 0) @intFromFloat(room / 17) else 0);
    }

    // Why this page plays in an emulator and the rest doesn't.
    _ = page.wrap(.small, x, in.y + in.h - 52, w, 17, P.kWarn.alpha(210), "Seeds run in a SNES emulator, not the PC port: alttpr.com rewrites too much of the game for anything but the ROM to play it exactly.", 3);
}

fn drawModernAchievements(page: *const start_page.Page, v: View) void {
    const p = &page.paint;
    const t = pageTime();
    const all = achievement_list.kList;
    const shown = achVisible();
    for (0..shown) |slot| {
        const row = g_ach_top + slot;
        if (row >= all.len) break;
        const ach = all[row];
        const r = achRowRect(slot);
        const picked = row == v.cursor;
        const has = g_ach_unlocked.has(ach.id);
        page.band(r, picked, t);
        page.mark(r.x + 40, r.y + r.h / 2, has);
        p.text(.item, r.x + 58, r.y + (r.h - p.lineHeight(.item)) / 2, if (picked) P.kCream else if (has) ui.Color.hex(0xd9cfb6) else P.kMuted, ach.name);
        const cat = ach.category.label();
        p.text(.small, r.x + r.w - 20 - p.textWidth(.small, cat), r.y + (r.h - p.lineHeight(.small)) / 2, P.kDim, cat);
    }
    if (all.len > shown) {
        const nf: f32 = @floatFromInt(all.len);
        const sf: f32 = @floatFromInt(shown);
        page.scrollbar(kModernListX + kModernListW + 12, kModernListY, sf * kModernRowH - 2, @as(f32, @floatFromInt(g_ach_top)) / nf, sf / nf);
    }

    // The picked one, and how far along the whole lot is.
    const box = kModernPanel;
    page.panel(box);
    const in = box.inset(22);
    const picked = all[@min(v.cursor, all.len - 1)];
    const has = g_ach_unlocked.has(picked.id);
    var cat_buf: [16]u8 = undefined;
    p.textEx(.eyebrow, in.x, in.y, P.kGold, P.kGold, 3, upper(&cat_buf, picked.category.label()));
    var y = page.wrap(.subtitle, in.x, in.y + 22, in.w, 24, if (has) P.kGoldHi else P.kCream, picked.name, 2) + 8;
    y = page.wrap(.body, in.x, y, in.w, 20, P.kMuted, picked.about, 6) + 10;
    page.mark(in.x + 7, y + 9, has);
    p.text(.strong, in.x + 22, y + 1, if (has) P.kGold else P.kDim, if (has) "Unlocked" else "Not yet");

    const got = g_ach_unlocked.count();
    var count_buf: [32]u8 = undefined;
    const count = std.fmt.bufPrint(&count_buf, "{d} of {d} unlocked", .{ got, all.len }) catch "";
    const by = in.y + in.h - 22;
    p.fill(.{ .x = in.x, .y = by - 30, .w = in.w, .h = 1 }, P.kChipLine);
    p.text(.body, in.x, by - 18, P.kCream, count);
    const bar = ui.Rect{ .x = in.x, .y = by + 6, .w = in.w, .h = 8 };
    p.fillRound(bar, 4, ui.Color.hex(0x1a2a32));
    const frac = @as(f32, @floatFromInt(got)) / @as(f32, @floatFromInt(all.len));
    if (frac > 0) p.fillRound(.{ .x = bar.x, .y = bar.y, .w = @max(bar.w * frac, 8), .h = bar.h }, 4, P.kGold);
}

fn drawModernControls(page: *const start_page.Page, ini: *const Ini, v: View) void {
    const p = &page.paint;
    const t = pageTime();
    // The pad on the left, lighting up the button picked.
    const art = Rect{ .x = 40, .y = start_page.kBodyTop, .w = kModernCtlX - 40 - 28, .h = start_page.kBodyBottom - start_page.kBodyTop };
    page.panel(art);
    const scale: f32 = 3;
    const art_x = art.x + (art.w - pad_art.kWidth * scale) / 2;
    const art_y = art.y + 40 + pad_art.kShoulderRise * scale;
    const blink = (c.SDL_GetTicks() / 267) % 2 == 0;
    const lit: ?usize = if (v.cursor < 12 and (blink or g_ctl_capture != null)) v.cursor else null;
    drawPadArt(page.paint.r, lit, art_x, art_y, scale, .{ .r = 0xff, .g = 0xd9, .b = 0x6a });

    const keys = controls.current(ini, .keyboard);
    const pads = controls.current(ini, .gamepad);
    const in = art.inset(26);
    var y = art_y + pad_art.kHeight * scale + 30;
    if (v.cursor < 12) {
        p.textEx(.eyebrow, in.x, y, P.kGold, P.kGold, 3, "BUTTON");
        y += 20;
        p.textEx(.headline, in.x, y, P.kGoldHi, P.kGoldDeep, 2, controls.kButtonNames[v.cursor]);
        y += 46;
        if (g_ctl_capture != null) {
            const left = kCtlCaptureMs -| (c.SDL_GetTicks() - g_ctl_capture_at);
            const pulse = 0.6 + 0.4 * @sin(t * 6);
            p.text(.item, in.x, y, P.kGold.alpha(@intFromFloat(255 * pulse)), "Press a key or button\xe2\x80\xa6");
            var sec_buf: [24]u8 = undefined;
            p.text(.small, in.x, y + 24, P.kDim, std.fmt.bufPrint(&sec_buf, "{d} seconds, or Esc", .{left / 1000 + 1}) catch "");
        } else {
            var kb: [8]u8 = undefined;
            p.text(.body, in.x, y, P.kMuted, "Keyboard");
            p.text(.strong, in.x + 110, y, P.kCream, controls.keyLabel(&kb, keys.get(v.cursor)));
            p.text(.body, in.x, y + 22, P.kMuted, "Controller");
            p.text(.strong, in.x + 110, y + 22, P.kCream, controls.padLabel(pads.get(v.cursor)));
        }
    } else {
        p.textEx(.eyebrow, in.x, y, P.kGold, P.kGold, 3, "RESET");
        _ = page.wrap(.body, in.x, y + 22, in.w, 20, P.kMuted, "Puts every key and button back the way the game came. Nothing is written until you save.", 4);
    }

    // Every button, with its key and its pad button, on the right.
    const head_y = start_page.kBodyTop + 8;
    const name_x = kModernCtlX + 26;
    const key_x = kModernCtlX + 150;
    const pad_x = kModernCtlX + 300;
    p.textEx(.eyebrow, name_x, head_y, P.kDim, P.kDim, 3, "BUTTON");
    p.textEx(.eyebrow, key_x, head_y, P.kDim, P.kDim, 3, "KEYBOARD");
    p.textEx(.eyebrow, pad_x, head_y, P.kDim, P.kDim, 3, "CONTROLLER");
    var row = g_ctl_top;
    while (row < @min(kCtlRows, g_ctl_top + ctlVisible())) : (row += 1) {
        const r = ctlRowRect(row - g_ctl_top);
        const picked = row == v.cursor;
        page.band(r, picked, t);
        const ty = r.y + (r.h - p.lineHeight(.item)) / 2;
        if (row == kCtlResetRow) {
            p.text(.item, name_x, ty, if (picked) P.kGoldHi else P.kGold, "Reset all to defaults");
            continue;
        }
        p.text(.item, name_x, ty, if (picked) P.kCream else P.kMuted, controls.kButtonNames[row]);
        const vy = r.y + (r.h - p.lineHeight(.strong)) / 2;
        if (picked and g_ctl_capture != null) {
            p.text(.strong, key_x, vy, P.kGold, "Waiting\xe2\x80\xa6");
            continue;
        }
        var kb: [8]u8 = undefined;
        var fbuf: [48]u8 = undefined;
        p.text(.strong, key_x, vy, if (picked) P.kGoldHi else P.kTeal, p.fit(.strong, controls.keyLabel(&kb, keys.get(row)), pad_x - key_x - 12, &fbuf));
        var fbuf2: [48]u8 = undefined;
        p.text(.strong, pad_x, vy, if (picked) P.kGoldHi else P.kTeal, p.fit(.strong, controls.padLabel(pads.get(row)), r.x + r.w - 12 - pad_x, &fbuf2));
    }
}

fn drawModernHub(page: *const start_page.Page, v: View) void {
    const t = pageTime();
    const names = [_][]const u8{ "Built-in", "ALTTPR.com" };
    const subs = [_][]const u8{ "Coming soon", "Play a seed from alttpr.com" };
    for (names, 0..) |name, i| page.card(hubRect(i), name, subs[i], v.cursor == i, i == kHubBuiltIn, t);
    const p = &page.paint;
    const line = "Seeds are made on alttpr.com and played here in a SNES emulator.";
    p.textCentered(.body, start_page.kW / 2, 418, P.kDim, line);
}

fn modernDetailColor(col: Rgb) ui.Color {
    if (std.meta.eql(col, kColorSection)) return P.kGold;
    if (std.meta.eql(col, kColorWarn)) return P.kWarn;
    if (std.meta.eql(col, kColorTextDim)) return P.kDim;
    if (std.meta.eql(col, kColorOk)) return P.kOk;
    if (std.meta.eql(col, kColorValue)) return P.kTeal;
    return P.kCream;
}

fn drawModernDetails(page: *const start_page.Page, v: View) void {
    const p = &page.paint;
    g_detail_caps = false;
    defer g_detail_caps = true;
    var lines: [96]DetailLine = undefined;
    var bufs: [64][40]u8 = undefined;
    const all = detailLines(&lines, &bufs);
    const box = kModernDetailsBox;
    page.panel(box);
    const x = box.x + 28;
    var y = box.y + 12;
    const top = @min(v.details_top, all.len);
    const label_x = x + 24;
    const value_x = x + 300;
    for (all[top..@min(all.len, top + kDetailsRows)]) |l| {
        if (l.heading) {
            page.heading(x, y, box.w - 80, kModernDetailH, l.label);
        } else {
            const ty = y + (kModernDetailH - p.lineHeight(.body)) / 2;
            if (l.value.len == 0) {
                p.text(.body, label_x, ty, if (std.meta.eql(l.color, kColorValue)) P.kCream else modernDetailColor(l.color), l.label);
            } else {
                p.text(.body, label_x, ty, P.kMuted, l.label);
                var sbuf: [64]u8 = undefined;
                var fbuf: [80]u8 = undefined;
                p.text(.strong, value_x, y + (kModernDetailH - p.lineHeight(.strong)) / 2, modernDetailColor(l.color), p.fit(.strong, soft(&sbuf, l.value), box.x + box.w - 40 - value_x, &fbuf));
            }
        }
        y += kModernDetailH;
    }
    if (all.len > kDetailsRows) {
        const nf: f32 = @floatFromInt(all.len);
        page.scrollbar(box.x + box.w - 16, box.y + 14, box.h - 28, @as(f32, @floatFromInt(top)) / nf, @as(f32, kDetailsRows) / nf);
    }
}

/// Title and the rule under it. The lists need the space, so the title stays
/// on one line and the rule doubles as the top of the list.
fn drawHeader(renderer: *c.SDL_Renderer, screen: Screen) void {
    const cx: f32 = kWindowW / 2;
    if (screen == .main) {
        // The game's own title with this port's DX on the end, then what
        // this screen is. Three lines, so everything below starts lower than
        // it used to.
        drawTextCentered(renderer, cx, 36, kColorSelect, "THE LEGEND OF ZELDA", kScale);
        drawTextCentered(renderer, cx, 36 + kRowH, kColorSelect, "A LINK TO THE PAST DX", kScale);
        if (!updateShown()) drawTextCentered(renderer, cx, 36 + kRowH * 2, kColorTextDim, "START MENU", kScale);
        fillRect(renderer, 60, 36 + kRowH * 3 + 7, kWindowW - 120, 1, kColorLine);
        return;
    }

    const name = switch (screen) {
        .settings => "SETTINGS",
        .features => "FEATURES",
        .hub => "RANDOMIZER",
        .controls => "CONTROLS",
        .achievements => "ACHIEVEMENTS",
        .alttpr => "ALTTPR.COM",
        .details => "SEED DETAILS",
        .main => unreachable,
    };
    drawText(renderer, 40, 36, kColorSelect, name);
    drawTextScaled(renderer, kWindowW - 40 - textWidth("ESC BACK", kScale), 36, kColorTextDim, "ESC BACK", kScale);
    fillRect(renderer, 40, 36 + kRowH + 1, kWindowW - 80, 1, kColorLine);
}

const Rect = kit.Rect;

// The menu's group of entries, then the Launch button below them, and the
// Randomizer button under that.
const kLaunchY: f32 = 242;

/// Where the entries above Play go: seven of them, or eight a little closer
/// together when Import MSU-1 is there, ending in the same place.
const EntryLayout = struct { y: f32, gap: f32, pad: f32 };
fn entryLayout() EntryLayout {
    return if (g_msu_on) .{ .y = 106, .gap = 16, .pad = 0 } else .{ .y = 106, .gap = 18, .pad = 1 };
}

/// An entry's place among the ones showing.
fn entrySlot(i: usize) f32 {
    var slot: usize = 0;
    for (0..i) |j| {
        if (mainShown(j)) slot += 1;
    }
    return @floatFromInt(slot);
}
const kLaunchScale: f32 = kScale * 2;
const kRandoY: f32 = 352;
/// From the bottom of Play to the asset state line under it: past the ring
/// Play gets when it's picked, and a little more.
const kStateGap: f32 = kRingBelow + 5;
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
    if (modernPage()) |page| {
        var pi = PageItems{};
        return start_page.entryRect(&page.paint, pageItems(&pi), i);
    }
    if (i == kMainUpdate) return if (updateShown()) updateRect() else .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    if (i == kMainLaunch) return launchRect();
    if (i == kMainRandomizer) return randoRect();
    // A hidden entry takes no room and catches no clicks.
    if (!mainShown(i)) return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    // Wider than the highlight, so aiming at a short word still lands.
    const l = entryLayout();
    const y = l.y + l.gap * entrySlot(i);
    return .{ .x = kWindowW / 2 - 150, .y = y - l.pad, .w = 300, .h = l.gap };
}

fn launchRect() Rect {
    const w = textWidth(kMainItems[kMainLaunch], kLaunchScale) + 72;
    return .{
        .x = kWindowW / 2 - w / 2,
        .y = kLaunchY,
        .w = w,
        .h = 8 * kLaunchScale + 22,
    };
}

fn randoRect() Rect {
    const w = textWidth(kMainItems[kMainRandomizer], kScale) + 72;
    return .{ .x = kWindowW / 2 - w / 2, .y = kRandoY, .w = w, .h = 8 * kScale + 14 };
}

/// The randomizer page's two big buttons.
fn hubRect(i: usize) Rect {
    // Side by side, modern; one over the other, retro.
    if (g_modern) return .{ .x = 100 + 400 * @as(f32, @floatFromInt(i)), .y = 168, .w = 360, .h = 210 };
    return .{ .x = 100, .y = 120 + 120 * @as(f32, @floatFromInt(i)), .w = kWindowW - 200, .h = 84 };
}

/// Which row of a list sits under a point, as a row position.
fn listRowAt(v: View, px: f32, py: f32) ?usize {
    const n = rowCount(v.screen);
    if (g_modern) {
        var slot: usize = 0;
        var pos = v.top;
        while (pos < n and slot < visibleRows(v.screen)) : ({
            pos += 1;
            slot += 1;
        }) {
            if (modernRowRect(slot).contains(px, py) and rowSelectable(v.screen, pos)) return pos;
        }
        return null;
    }
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

    const l = entryLayout();
    for (kMainItems[0..kMainLaunch], 0..) |label, i| {
        if (!mainShown(i)) continue;
        const y = l.y + l.gap * entrySlot(i);
        const selected = i == v.cursor;
        const w = textWidth(label, kScale);

        if (selected) {
            // Sized to the word rather than the window, so the highlight
            // reads as a selection and not as a banner.
            drawRowHighlight(renderer, cx - w / 2 - 28, y - l.pad, w + 56, l.gap - 2);
        }
        drawTextCentered(renderer, cx, y, if (selected) kColorSelect else kColorText, label, kScale);
    }

    // Launch: a button, centered, big enough to be the obvious thing to press.
    const scale = kLaunchScale;
    const label = kMainItems[kMainLaunch];
    const box = launchRect();
    const box_h = box.h;
    const box_y = box.y;
    const selected = v.cursor == kMainLaunch;

    // Green whether or not it is selected - it is the one action the window
    // exists for. Selection is the ring, which has to be an outline: a frame
    // would paint its own interior over the button.
    drawButton(renderer, box, kColorLaunchBg, selected);
    drawTextCentered(renderer, cx, box_y + 11, kColorLaunchText, label, scale);

    // Whether the game can actually start, said plainly. Presence is not
    // enough - a .dat left over from another build loads and then misbehaves
    // in ways that look like game bugs, so it is checked against the digest
    // the asset builder produces and reported as its own state.
    // Clear of the ring round the button when it's picked.
    const state_y = box_y + box_h + kStateGap;

    drawTextCentered(renderer, cx, state_y, v.assets.color(), v.assets.line(), kScale);
    if (v.assets == .missing)
        drawTextCentered(renderer, cx, state_y + kRowH, kColorTextDim, "DRAG A .SFC ROM ONTO THIS WINDOW", kScale);

    // The randomizer: smaller, and a color of its own, since it plays
    // something other than the port.
    const r = randoRect();
    drawButton(renderer, r, kColorRandoBg, v.cursor == kMainRandomizer);
    drawTextCentered(renderer, cx, r.y + 7, kColorText, "RANDOMIZER", kScale);

    // A newer version: an outlined button where "START MENU" was, in the
    // green that means good news here.
    if (updateShown()) {
        var buf: [64]u8 = undefined;
        const u = updateRect();
        const picked = v.cursor == kMainUpdate;
        fillRound(renderer, u.x, u.y, u.w, u.h, 8, if (picked) kColorRowHi else kColorPanel);
        outlineRound(renderer, u.x, u.y, u.w, u.h, 8, if (picked) 2 else 1, if (picked) kColorSelect else kColorOk);
        drawTextCentered(renderer, cx, u.y + 3, if (picked) kColorSelect else kColorOk, updateButtonLabel(&buf), kScale);
    }
}

// ------------------------------------------------------------ achievements

/// What's been unlocked, read from the file each time the screen opens.
var g_ach_unlocked: achievement_list.Unlocked = .{};
var g_ach_row: usize = 0;
var g_ach_top: usize = 0;

const kAchRows = achievement_list.kList.len;
const kAchVisible = 11;

fn achVisible() usize {
    return if (g_modern) kModernVisible else kAchVisible;
}
/// Under the list, what the picked one asks for.
const kAchAboutY: f32 = kListStartY + kRowH * kAchVisible + 10;

fn achRowRect(slot: usize) Rect {
    if (g_modern) return modernRowRect(slot);
    return .{ .x = 32, .y = kListStartY + kRowH * @as(f32, @floatFromInt(slot)) - 3, .w = kWindowW - 64, .h = kRowH };
}

/// One line per achievement, its category beside it, ticked off once it's
/// got; under them, what the picked one asks for.
fn drawAchievements(renderer: *c.SDL_Renderer, v: View) void {
    const all = achievement_list.kList;

    for (0..kAchVisible) |slot| {
        const row = g_ach_top + slot;
        if (row >= all.len) break;
        const ach = all[row];
        const r = achRowRect(slot);
        const y = r.y + 3;
        const selected = row == v.cursor;
        const has = g_ach_unlocked.has(ach.id);
        if (selected) drawRowHighlight(renderer, r.x, r.y, r.w, r.h);
        // A filled box for got, an empty one for not yet.
        if (has) fillRect(renderer, 44, y + 2, 12, 12, kColorOk) else outlineRound(renderer, 44, y + 2, 12, 12, 0, 1, kColorTextDim);
        var name_buf: [48]u8 = undefined;
        const name = upper(&name_buf, ach.name);
        drawText(renderer, 68, y, if (selected) kColorSelect else if (has) kColorText else kColorTextDim, name);
    }
    if (all.len > kAchVisible) {
        const track_y = kListStartY - 3;
        const track_h = kRowH * @as(f32, kAchVisible);
        const nf: f32 = @floatFromInt(all.len);
        drawScrollbar(renderer, track_y, track_h, track_y + track_h * @as(f32, @floatFromInt(g_ach_top)) / nf, track_h * kAchVisible / nf);
    }

    const picked = all[@min(v.cursor, all.len - 1)];
    fillRect(renderer, 40, kAchAboutY - 4, kWindowW - 80, 1, kColorLine);
    // Its category, and how many are got, on the rule's line.
    var cat_buf: [16]u8 = undefined;
    drawText(renderer, 40, kAchAboutY + 4, kColorSection, upper(&cat_buf, picked.category.label()));
    var count_buf: [24]u8 = undefined;
    const count = std.fmt.bufPrint(&count_buf, "{d} OF {d} UNLOCKED", .{ g_ach_unlocked.count(), all.len }) catch "";
    drawText(renderer, kWindowW - 40 - textWidth(count, kScale), kAchAboutY + 4, kColorTextDim, count);
    var about_buf: [96]u8 = undefined;
    var lines = LineWrap{ .text = upper(&about_buf, picked.about), .width = (kWindowW - 80) / kCell };
    var y = kAchAboutY + 4 + kRowH;
    while (lines.next()) |line| : (y += kRowH) drawText(renderer, 40, y, if (g_ach_unlocked.has(picked.id)) kColorOk else kColorText, line);
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

/// The modern Controls screen has the room for every row.
fn ctlVisible() usize {
    return if (g_modern) kCtlRows else kCtlVisible;
}

const kModernCtlRowsY: f32 = start_page.kBodyTop + 32;
const kModernCtlRowH: f32 = 26;
const kModernCtlX: f32 = 440;
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
    if (g_modern) return .{ .x = kModernCtlX, .y = kModernCtlRowsY + kModernCtlRowH * @as(f32, @floatFromInt(slot)), .w = start_page.kW - 40 - kModernCtlX, .h = kModernCtlRowH - 2 };
    return .{ .x = 32, .y = kCtlRowsY + kRowH * @as(f32, @floatFromInt(slot)) - 3, .w = kWindowW - 64, .h = kRowH };
}

/// Draws the pad a pixel at a time into a small image, then fills the
/// renderer a run of same-colored pixels at a time, which is a few hundred
/// rectangles rather than thousands.
fn drawPadArt(renderer: *c.SDL_Renderer, lit: ?usize, art_x: f32, art_y: f32, scale: f32, lit_rgb: Rgb) void {
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
    const lit_color = @as(u32, lit_rgb.r) << 16 | @as(u32, lit_rgb.g) << 8 | lit_rgb.b;
    pad_art.draw(.{ .ctx = &img, .putFn = Img.put }, lit, lit_color);
    const s = scale;
    const top = art_y - pad_art.kShoulderRise * s;
    for (0..kH) |y| {
        var x: usize = 0;
        while (x < kW) {
            const col = img.px[y * kW + x];
            var end = x + 1;
            while (end < kW and img.px[y * kW + end] == col) end += 1;
            if (col != kClear) {
                const rgb = Rgb{ .r = @truncate(col >> 16), .g = @truncate(col >> 8), .b = @truncate(col) };
                fillRect(renderer, art_x + @as(f32, @floatFromInt(x)) * s, top + @as(f32, @floatFromInt(y)) * s, @as(f32, @floatFromInt(end - x)) * s, s, rgb);
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
    drawPadArt(renderer, lit, kCtlArtX, kCtlArtY, kCtlArtScale, kColorSelect);

    drawText(renderer, kCtlColKey, kCtlHeadY, kColorSection, "KEYBOARD");
    drawText(renderer, kCtlColPad, kCtlHeadY, kColorSection, "CONTROLLER");

    const keys = controls.current(ini, .keyboard);
    const pads = controls.current(ini, .gamepad);
    var row = g_ctl_top;
    while (row < @min(kCtlRows, g_ctl_top + kCtlVisible)) : (row += 1) {
        const r = ctlRowRect(row - g_ctl_top);
        const y = r.y + 3;
        const selected = row == v.cursor;
        if (selected) drawRowHighlight(renderer, r.x, r.y, r.w, r.h);
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
    drawScrollbar(renderer, track_y, track_h, bar_y, bar_h);
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
        drawButton(renderer, r, if (soon) kColorDisabledBg else kColorRandoBg, selected);
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
    outlineRound(renderer, x, y, w, kSeedBoxH, 10, 1, kColorLine);
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

/// Whether the seed details come out in capitals, the retro menu's way, or
/// as the seed has them for the modern one's real type.
var g_detail_caps = true;

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
            if (!g_detail_caps or k.* >= bs.len) return text;
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
const kModernDetailH: f32 = 24;

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
            if (selected) drawRowHighlight(renderer, 32, y - 3, kWindowW - 64, kRowH);
            const label = if (at == kPlayRow) "PLAY THIS SEED" else "SEED DETAILS";
            const col = if (!g_seed_loaded) kColorTextDim else if (selected) kColorSelect else if (at == kPlayRow) kColorOk else kColorText;
            drawTextCentered(renderer, kWindowW / 2, y, col, label, kScale);
        } else if (isSection(kSettings[at])) {
            drawText(renderer, 40, y, kColorSection, kSettings[at].label);
        } else {
            const s = kSettings[at];
            if (selected) drawRowHighlight(renderer, 32, y - 3, kWindowW - 64, kRowH);
            drawText(renderer, 56, y, if (selected) kColorSelect else kColorText, s.label);
            var vbuf: [64]u8 = undefined;
            const shown = displayValue(&vbuf, s, ini.values[at] orelse "(missing)");
            const dim = isFixed(s);
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
        drawScrollbar(renderer, track_y, track_h, bar_y, bar_h);
    }
}

/// The info box: wide, so a description takes few lines.
const kInfoRect = Rect{ .x = 24, .y = 84, .w = kWindowW - 48, .h = 280 };
const kInfoPad: f32 = 24;
/// Characters to a line of the description, in the menu's fixed-width font.
const kInfoChars: usize = @intFromFloat((kInfoRect.w - kInfoPad * 2) / kCell);
const kInfoLines = 9;

/// The selected setting's name and what it does.
fn drawInfo(renderer: *c.SDL_Renderer, v: View) void {
    const at = rowAt(v.screen, v.cursor);
    if (at >= kSettings.len or isSection(kSettings[at])) return;
    const s = kSettings[at];
    const box = kInfoRect;
    drawFrame(renderer, box.x, box.y, box.w, box.h);
    const x = box.x + kInfoPad;
    drawText(renderer, x, box.y + kInfoPad, kColorSelect, s.label);
    fillRect(renderer, x, box.y + kInfoPad + kRowH + 2, box.w - kInfoPad * 2, 1, kColorLine);

    var y = box.y + kInfoPad + kRowH + 14;
    var lines = LineWrap{ .text = describe(s), .width = kInfoChars };
    var n: usize = 0;
    while (lines.next()) |line| : (n += 1) {
        if (n == kInfoLines) break;
        drawText(renderer, x, y, kColorText, line);
        y += kRowH;
    }
}

/// Splits text into lines of at most `width` characters, at spaces.
const LineWrap = struct {
    text: []const u8,
    width: usize,
    at: usize = 0,

    fn next(self: *LineWrap) ?[]const u8 {
        while (self.at < self.text.len and self.text[self.at] == ' ') self.at += 1;
        if (self.at >= self.text.len) return null;
        const start = self.at;
        const rest = self.text[start..];
        if (rest.len <= self.width) {
            self.at = self.text.len;
            return rest;
        }
        // The last space that leaves the line short enough, or a hard break
        // for a word longer than a whole line.
        const cut = std.mem.lastIndexOfScalar(u8, rest[0 .. self.width + 1], ' ') orelse self.width;
        self.at = start + cut;
        return rest[0..cut];
    }
};

/// Where the modal's panel sits, and where its two answers sit inside it.
fn modalRect() Rect {
    // Naming a pack has its FLAC box too.
    const tall = g_modal_now == .msu_name;
    if (g_modern) {
        const h: f32 = if (tall) 226 else 190;
        return .{ .x = (start_page.kW - 500) / 2, .y = (start_page.kH - h) / 2 - 10, .w = 500, .h = h };
    }
    return if (tall) .{ .x = 70, .y = 130, .w = kWindowW - 140, .h = 230 } else .{ .x = 70, .y = 150, .w = kWindowW - 140, .h = 190 };
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
    if (v.modal == .info) return drawInfo(renderer, v);
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
                fillRound(renderer, r.x, r.y, r.w, r.h, 8, if (selected) kColorRowHi else kColorPanel);
                outlineRound(renderer, r.x, r.y, r.w, r.h, 8, if (selected) 2 else 1, if (selected) kColorSelect else kColorLine);
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
        .msu => {
            drawTextCentered(renderer, cx, box.y + 22, kColorSelect, "IMPORT AN MSU-1 PACK", kScale);
            drawTextCentered(renderer, cx, box.y + 22 + kRowH, kColorTextDim, "DROP A FOLDER OR .ZIP HERE,", kScale);
            drawTextCentered(renderer, cx, box.y + 22 + kRowH * 2, kColorTextDim, "OR BROWSE FOR ONE", kScale);
            drawTextCentered(renderer, cx, box.y + 22 + kRowH * 3, kColorTextDim, "KEPT BESIDE YOUR OTHER PACKS", 1);
            for (kMsuChoices, 0..) |label, i| {
                const r = modalChoiceRect(i);
                const selected = i == g_msu_choice;
                fillRound(renderer, r.x, r.y, r.w, r.h, 8, if (selected) kColorRowHi else kColorPanel);
                outlineRound(renderer, r.x, r.y, r.w, r.h, 8, if (selected) 2 else 1, if (selected) kColorSelect else kColorLine);
                drawTextCentered(renderer, r.x + r.w / 2, r.y + 8, if (selected) kColorSelect else kColorText, label, kScale);
            }
        },
        .msu_name => {
            drawTextCentered(renderer, cx, box.y + 22, kColorSelect, "NAME THIS PACK", kScale);
            var nb: [80]u8 = undefined;
            const blink = !g_msu_on_check and @mod(c.SDL_GetTicks(), 1000) < 600;
            const shown = std.fmt.bufPrint(&nb, "{s}{s}", .{ msuName(), if (blink) "_" else " " }) catch msuName();
            drawTextCentered(renderer, cx, box.y + 22 + kRowH * 1.5, kColorValue, shown, kScale);
            if (g_msu_pcm != 0) {
                const r = msuCheckRect();
                if (g_msu_on_check) drawRowHighlight(renderer, r.x, r.y - 2, r.w, r.h);
                const label = if (g_msu_flac) "[X] STORE AS FLAC" else "[ ] STORE AS FLAC";
                drawTextCentered(renderer, cx, r.y + 2, if (g_msu_on_check) kColorSelect else kColorText, label, kScale);
            }
            if (msu_import.packExists(msuName()))
                drawTextCentered(renderer, cx, box.y + 30 + kRowH * 4, kColorWarn, "REPLACES THE PACK CALLED THAT", 1);
            for (kMsuNameChoices, 0..) |label, i| {
                const r = modalChoiceRect(i);
                const selected = i == g_msu_name_choice;
                fillRound(renderer, r.x, r.y, r.w, r.h, 8, if (selected) kColorRowHi else kColorPanel);
                outlineRound(renderer, r.x, r.y, r.w, r.h, 8, if (selected) 2 else 1, if (selected) kColorSelect else kColorLine);
                drawTextCentered(renderer, r.x + r.w / 2, r.y + 8, if (selected) kColorSelect else kColorText, label, kScale);
            }
        },
        .msu_progress => {
            drawTextCentered(renderer, cx, box.y + 22, kColorSelect, "IMPORTING", kScale);
            var pb: [96]u8 = undefined;
            const pr = msuProgressText(&pb);
            drawTextCentered(renderer, cx, box.y + 22 + kRowH * 1.5, kColorValue, if (g_msu_job) |j| j.name else "", kScale);
            drawTextCentered(renderer, cx, box.y + 22 + kRowH * 3, kColorTextDim, pr.doing, 1);
            const bar_x = box.x + 40;
            const bar_w = box.w - 80;
            const bar_y = box.y + 22 + kRowH * 4.5;
            outlineRound(renderer, bar_x - 2, bar_y - 2, bar_w + 4, 14, 5, 1, kColorLine);
            if (pr.frac > 0) fillRound(renderer, bar_x, bar_y, @max(bar_w * pr.frac, 8), 10, 4, kColorSelect);
        },
        .update => drawUpdateModal(renderer),
        .info, .none => {},
    }
}

/// Two answers side by side, the way the other questions have them.
fn drawChoices(renderer: *c.SDL_Renderer, labels: []const []const u8, picked: usize) void {
    for (labels, 0..) |label, i| {
        const r = modalChoiceRect(i);
        const selected = i == picked;
        fillRound(renderer, r.x, r.y, r.w, r.h, 8, if (selected) kColorRowHi else kColorPanel);
        outlineRound(renderer, r.x, r.y, r.w, r.h, 8, if (selected) 2 else 1, if (selected) kColorSelect else kColorLine);
        drawTextCentered(renderer, r.x + r.w / 2, r.y + 8, if (selected) kColorSelect else kColorText, label, kScale);
    }
}

fn drawUpdateModal(renderer: *c.SDL_Renderer) void {
    const box = modalRect();
    const cx = box.x + box.w / 2;
    var buf: [64]u8 = undefined;
    switch (updater.phase()) {
        .downloading, .installing, .ready => |p| {
            const title = switch (p) {
                .downloading => std.fmt.bufPrint(&buf, "DOWNLOADING {s}", .{updater.offerLabel()}) catch "DOWNLOADING",
                .installing => "INSTALLING...",
                else => "RESTARTING...",
            };
            drawTextCentered(renderer, cx, box.y + 34, kColorSelect, title, kScale);

            const pr = updater.progress();
            const frac: f32 = if (p != .downloading) 1 else if (pr.total == 0) 0 else @min(1, @as(f32, @floatFromInt(pr.done)) / @as(f32, @floatFromInt(pr.total)));
            const bar = Rect{ .x = box.x + 50, .y = box.y + 84, .w = box.w - 100, .h = 14 };
            fillRound(renderer, bar.x, bar.y, bar.w, bar.h, 6, kColorRowHi);
            if (frac > 0) fillRound(renderer, bar.x, bar.y, @max(bar.w * frac, 12), bar.h, 6, kColorOk);

            const mb = 1024.0 * 1024.0;
            const size = std.fmt.bufPrint(&buf, "{d:.1} OF {d:.1} MB", .{ @as(f32, @floatFromInt(pr.done)) / mb, @as(f32, @floatFromInt(pr.total)) / mb }) catch "";
            if (p == .downloading) drawTextCentered(renderer, cx, bar.y + 30, kColorTextDim, size, kScale);
        },
        .failed => {
            drawTextCentered(renderer, cx, box.y + 22, kColorWarn, "COULD NOT UPDATE", kScale);
            drawTextCentered(renderer, cx, box.y + 22 + kRowH, kColorText, updater.message(), kScale);
            drawTextCentered(renderer, cx, box.y + 22 + kRowH * 2 + 4, kColorTextDim, "THE RELEASE PAGE HAS IT TO DOWNLOAD BY HAND", 1);
            drawChoices(renderer, &kUpdateFailedChoices, g_update_choice);
        },
        else => {
            drawTextCentered(renderer, cx, box.y + 22, kColorSelect, std.fmt.bufPrint(&buf, "UPDATE TO {s}?", .{updater.offerLabel()}) catch "UPDATE?", kScale);
            var mine: [40]u8 = undefined;
            drawTextCentered(renderer, cx, box.y + 22 + kRowH, kColorTextDim, std.fmt.bufPrint(&buf, "YOU HAVE {s}", .{updater.installedLabel(&mine)}) catch "", kScale);
            drawTextCentered(renderer, cx, box.y + 22 + kRowH * 2 + 4, kColorTextDim, "DOWNLOADS FROM GITHUB, THEN RESTARTS. SAVES STAY PUT.", 1);
            drawChoices(renderer, &kUpdateChoices, g_update_choice);
        },
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
            .info => drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "A OR B TO CLOSE"),
            .msu => {
                drawText(renderer, 40, footer_y, kColorTextDim, "LEFT/RIGHT CHOOSE");
                drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "A/ENTER BROWSE   B/ESC CANCEL");
            },
            .msu_name => {
                drawText(renderer, 40, footer_y, kColorTextDim, if (g_msu_pcm != 0) "TYPE A NAME   DOWN+SPACE FLAC" else "TYPE A NAME FOR IT");
                drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "ENTER IMPORT   ESC CANCEL");
            },
            .msu_progress => drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "B/ESC STOP"),
            .update => switch (updater.phase()) {
                .downloading => drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "B/ESC CANCEL"),
                .installing, .ready => {},
                else => {
                    drawText(renderer, 40, footer_y, kColorTextDim, "LEFT/RIGHT CHOOSE");
                    drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "A/ENTER CONFIRM   B/ESC CANCEL");
                },
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
            // Which version this is, out of the way in the corner.
            var buf: [40]u8 = undefined;
            const ver = if (updater.installed == .dev) "DEV BUILD" else updater.installedLabel(&buf);
            drawTextScaled(renderer, kWindowW - 40 - textWidth(ver, kScale), footer_y + kRowH, kColorTextDim, ver, kScale);
        },
        .settings, .features => {
            drawText(renderer, 40, footer_y, kColorTextDim, "CHANGE  LEFT/RIGHT OR A");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "INFO Y/I   SAVE X/S   BACK B/ESC");
        },
        .achievements => {
            drawText(renderer, 40, footer_y, kColorTextDim, "CHOOSE UP/DOWN");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "BACK B/ESC");
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

    const joined = std.fmt.bufPrintSentinel(buf, "{s}/{s}", .{ start_dir, kRomPath }, 0) catch return null;
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
                .info => "info",
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

/// The per-user data directory's name. The project was alttp-zig before it
/// was ALTTP-DX, and so was its directory.
const kDataDirName = "alttp-dx";
const kOldDataDirName = "alttp-zig";

/// The per-user data directory, with a separator on the end, made if it isn't
/// there yet. Free it with SDL_free. The first time, an alttp-zig directory
/// from before the rename is moved over to be it, saves and all.
pub fn dataDirectory() ?[*:0]u8 {
    // SDL creates the directory if it is not there yet.
    const pref = c.SDL_GetPrefPath("", kDataDirName) orelse return null;
    var buf: [4096]u8 = undefined;
    if (oldDataDirectory(&buf, std.mem.span(pref))) |old| moveDataDirectory(old, pref);
    return pref;
}

/// Moves `old` to be `new`, if `old` is there and `new` is empty. One that
/// has anything in it stays as it is, and so does `old`: an empty `new`
/// comes out, and `old` is renamed into its place.
fn moveDataDirectory(old: [*:0]const u8, new: [*:0]const u8) void {
    if (!fileio.isDir(old)) return;
    fileio.removeDir(new);
    if (fileio.isDir(new)) return;
    if (fileio.rename(old, new) != 0) {
        std.debug.print("Could not move {s} to {s}\n", .{ old, new });
        fileio.makeDir(new) catch {};
    }
}

/// The old data directory beside `new`, which SDL gave as ending in the new
/// name and a separator. Null for anything else.
fn oldDataDirectory(buf: []u8, new: []const u8) ?[:0]const u8 {
    const trimmed = std.mem.trimEnd(u8, new, "/\\");
    if (!std.mem.endsWith(u8, trimmed, kDataDirName)) return null;
    const parent = trimmed[0 .. trimmed.len - kDataDirName.len];
    return std.fmt.bufPrintSentinel(buf, "{s}{s}", .{ parent, kOldDataDirName }, 0) catch null;
}

/// Moves into the directory the game keeps its files in, whatever directory it
/// was started from, and remembers where to look for a ROM. That is the
/// executable's own directory for a plain install, or the per-user data
/// directory (~/Library/Application Support/alttp-dx on macOS,
/// ~/.local/share/alttp-dx on Linux) for an app bundle or AppImage. A missing
/// zelda3.ini is written out from the copy built into the game.
pub fn enterDataDirectory() void {
    var start_dir_buf: [4096]u8 = undefined;
    const start_dir = fileio.workingDirectory(&start_dir_buf) catch ".";

    if (c.SDL_GetBasePath()) |base_z| {
        const base = std.mem.span(base_z);
        if (isPackaged(base)) {
            if (dataDirectory()) |pref| {
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

/// Opens the menu straight into the tools, for `zelda3 tools`.
pub var g_open_tools = false;

const kWindowTitle = "The Legend of Zelda: A Link to the Past DX";

/// How many pixels a point is in `window`: 2 on a Retina screen.
fn pixelDensity(window: *c.SDL_Window) f32 {
    const d = c.SDL_GetWindowPixelDensity(window);
    return if (d > 0) d else 1;
}

/// Resizes `window`, keeping its middle where it was.
fn resizeCentered(window: *c.SDL_Window, w: c_int, h: c_int) void {
    var wx: c_int = 0;
    var wy: c_int = 0;
    var ow: c_int = 0;
    var oh: c_int = 0;
    _ = c.SDL_GetWindowPosition(window, &wx, &wy);
    _ = c.SDL_GetWindowSize(window, &ow, &oh);
    _ = c.SDL_SetWindowSize(window, w, h);
    _ = c.SDL_SetWindowPosition(window, @max(0, wx + @divTrunc(ow - w, 2)), @max(0, wy + @divTrunc(oh - h, 2)));
}

/// The tools, in this window rather than one of their own: it grows to
/// their size and can be resized while they're up, then goes back to the
/// menu's, as it was.
fn runTools(alloc: std.mem.Allocator, window: *c.SDL_Window, renderer: *c.SDL_Renderer, msu_path: []const u8) tools_gui.Exit {
    // Windows sizes a window in pixels and says how big its points are on
    // the side; a Mac or Wayland sizes it in points already, and says 1.
    const content = c.SDL_GetDisplayContentScale(c.SDL_GetDisplayForWindow(window));
    const k: f32 = if (content > 0) content else 1;
    _ = c.SDL_SetWindowTitle(window, "A Link to the Past DX Tools");
    resizeCentered(window, @intFromFloat(tools_gui.kWindowW * k), @intFromFloat(tools_gui.kWindowH * k));
    _ = c.SDL_SetWindowMinimumSize(window, @intFromFloat(tools_gui.kMinW * k), @intFromFloat(tools_gui.kMinH * k));
    _ = c.SDL_SetWindowResizable(window, true);

    // They start from the ROM the menu has, found or dropped on it.
    const outcome = tools_gui.runIn(alloc, window, renderer, .{ .rom = if (g_rom_path) |p| p else null, .msu_path = msu_path });

    // Out of fullscreen or maximized first, or the size won't take.
    _ = c.SDL_RestoreWindow(window);
    _ = c.SDL_SetWindowResizable(window, false);
    _ = c.SDL_SetWindowMinimumSize(window, 0, 0);
    resizeCentered(window, @intFromFloat(windowW()), @intFromFloat(windowH()));
    _ = c.SDL_SetWindowTitle(window, kWindowTitle);
    // The tools drew at their own scale; the menu's comes back.
    const d = pixelDensity(window);
    _ = c.SDL_SetRenderScale(renderer, d, d);
    return outcome;
}

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

    g_modern = modernIn(&ini);
    // Drawn at the screen's own density, so the start page's type and the
    // tools', which open in this same window, come out sharp on Retina.
    const window = c.SDL_CreateWindow(kWindowTitle, @intFromFloat(windowW()), @intFromFloat(windowH()), c.SDL_WINDOW_HIGH_PIXEL_DENSITY) orelse {
        std.debug.print("Failed to create window: {s}\n", .{c.SDL_GetError()});
        return error.SdlWindow;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, null) orelse {
        std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
        return error.SdlRenderer;
    };
    defer c.SDL_DestroyRenderer(renderer);
    g_page = start_page.Page.initScaled(renderer, pixelDensity(window));
    defer {
        g_page.?.deinit();
        g_page = null;
    }
    defer start_logo.release();
    g_modern = modernIn(&ini);

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
    } else if (!assets.playable()) {
        modal = .rom;
        main_cursor = kMainLaunch;
    } else if (g_modern) {
        // The modern page opens on Play, the thing it's for.
        main_cursor = kMainLaunch;
    }
    // `zelda3 tools` opens on them, missing assets or not: they're how to
    // make some.
    var open_tools = g_open_tools;
    g_open_tools = false;
    if (open_tools) {
        screen = .main;
        modal = .none;
        main_cursor = kMainTools;
    }
    var running = true;
    var event: c.SDL_Event = undefined;
    if (updatesOnIn(&ini)) updater.check(updateChannelIn(&ini));

    // Save Settings on the front page is confirmed after this frame's save
    // has already been and gone, so it's kept for the next one; a flag
    // made fresh each frame forgot it, and the entry never saved.
    var save_queued = false;
    // A pack still going in when the menu closes is stopped first.
    defer stopMsuImport();
    while (running) {
        const now = c.SDL_GetTicks();
        var confirm = false;
        // Enter while naming a pack, which imports whatever's picked; A on a
        // pad ticks the FLAC box when that's picked.
        var name_enter = false;
        var start = false;
        var back = false;
        var save = save_queued;
        save_queued = false;
        var info = false;
        var build = false;
        // Presses arrive as events so that a tap shorter than a frame still
        // counts; the poll below only decides when a held direction repeats.
        var tap_v: i32 = 0;
        var tap_h: i32 = 0;
        var hover_x: f32 = 0;
        var hover_y: f32 = 0;
        var hovered = false;
        var clicked = false;
        // Where things stood before this frame's input, so a change of
        // screen or question can be noticed at the end of it.
        const screen_was = screen;
        const modal_was = modal;

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
            // Naming a pack takes the keyboard for typing. Enter and Esc
            // still answer, and a pad or the mouse work as ever.
            if (modal == .msu_name) switch (event.type) {
                c.SDL_EVENT_TEXT_INPUT => {
                    // With the FLAC box picked, Space ticks it rather than
                    // typing.
                    if (!g_msu_on_check) msuNameType(std.mem.span(event.text.text));
                    continue;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    const mods = event.key.mod;
                    switch (event.key.key) {
                        c.SDLK_BACKSPACE => if (!g_msu_on_check) msuNameBackspace(),
                        c.SDLK_RETURN, c.SDLK_KP_ENTER => name_enter = true,
                        c.SDLK_UP, c.SDLK_DOWN => if (g_msu_pcm != 0) {
                            g_msu_on_check = !g_msu_on_check;
                        },
                        c.SDLK_SPACE => if (g_msu_on_check) toggleMsuFlac(),
                        c.SDLK_ESCAPE => back = true,
                        c.SDLK_TAB => g_msu_name_choice = 1 - g_msu_name_choice,
                        c.SDLK_V => if (mods & (c.SDL_KMOD_CTRL | c.SDL_KMOD_GUI) != 0) {
                            if (c.SDL_GetClipboardText()) |clip| {
                                defer c.SDL_free(clip);
                                msuNameType(std.mem.span(clip));
                            }
                        },
                        else => {},
                    }
                    continue;
                },
                else => {},
            };
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
                        } else if (modal == .msu or modal == .msu_name or modal == .msu_progress or looksLikeMsuPack(span)) {
                            // A folder or a zip is an MSU-1 pack, not a ROM.
                            handled = true;
                            if (!g_msu_on) {
                                status = "TURN ON MSU AUDIO TO IMPORT A PACK";
                            } else if (g_msu_job != null) {
                                status = "ONE PACK AT A TIME";
                            } else {
                                askMsuName(window, span);
                                modal = .msu_name;
                                status = "";
                            }
                        }
                    }
                    if (!handled) if (event.drop.data) |path| {
                        status = "CHECKING ROM...";
                        drawScreen(renderer, &ini, viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice));
                        status = buildAssetsFromDrop(alloc, path);
                        assets = checkAssets(alloc);
                        // A drop that worked answers the question; one that
                        // did not leaves it up so another can be tried.
                        if (assets.playable()) modal = .none;
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
                c.SDL_EVENT_MOUSE_BUTTON_UP => if (event.button.button == c.SDL_BUTTON_LEFT) {
                    g_pointer.dragging = false;
                },
                c.SDL_EVENT_MOUSE_WHEEL => {
                    g_pointer.addWheel(event.wheel.y);
                    g_pointer.x = event.wheel.mouse_x;
                    g_pointer.y = event.wheel.mouse_y;
                },
                c.SDL_EVENT_WINDOW_MOUSE_LEAVE => g_pointer.over = null,

                // Anything that stops the window seeing releases has to
                // clear what it thinks is held, or a direction sticks on.
                c.SDL_EVENT_WINDOW_FOCUS_LOST => {
                    held = .{};
                    g_pointer.dragging = false;
                },

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
                        c.SDLK_I => info = true,
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
                            .info => info = true,
                            .none => {},
                        },
                    }
                },
                else => {},
            }
        }

        if (hovered) {
            g_pointer.x = hover_x;
            g_pointer.y = hover_y;
        }
        // Whole rows of wheel; trackpads get there a sliver at a time.
        const wheel = g_pointer.takeWheel();
        // Asked for the tools on the command line: as if Tools was picked.
        if (open_tools) {
            open_tools = false;
            confirm = true;
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

        // Import MSU-1 comes and goes with the setting; the cursor can't be
        // left on it once it's gone.
        g_msu_on = msuOnIn(&ini);
        const was_modern = g_modern;
        g_modern = modernIn(&ini);
        // Picking the banner fetches it if it isn't here, and picking it
        // again after a failed try tries again.
        const was_logo = g_logo;
        g_logo = logoIn(&ini);
        if (g_logo and !was_logo) start_logo.retry();
        start_logo.want(g_logo and g_modern);
        if (g_modern != was_modern) {
            // Widescreen one way, 4:3 the other, kept where it was centered.
            resizeCentered(window, @intFromFloat(windowW()), @intFromFloat(windowH()));
            g_back_hover = false;
            g_pointer.forget();
        }
        // The window may have moved to a screen with other pixels.
        if (g_page) |*pg| pg.paint.setScale(pixelDensity(window));
        if (!mainShown(main_cursor)) main_cursor = kMainLaunch;
        if (modal == .msu and !g_msu_on) modal = .none;
        // The pack going in, once it's in.
        if (finishMsuImport(&ini, &dirty)) |said| {
            status = said;
            if (modal == .msu_progress) modal = .none;
        }
        if (modal == .update and !updateShown()) modal = .none;

        // A folder or zip picked in the system's own dialog.
        if (takeMsuPick()) |path| {
            defer std.heap.c_allocator.free(path);
            if (g_msu_on and g_msu_job == null) {
                askMsuName(window, path);
                modal = .msu_name;
                status = "";
            }
        }

        // The modern sub-screens' Back button, at the top right.
        if (g_modern and modal == .none and screen != .main and g_ctl_capture == null) {
            const b = start_page.backRect();
            if (hovered) g_back_hover = b.contains(hover_x, hover_y);
            if (clicked and b.contains(hover_x, hover_y)) {
                back = true;
                clicked = false;
            }
        } else g_back_hover = false;

        // A scrollbar taken hold of follows the pointer until let go, and
        // the cursor comes along to stay in sight.
        if (modal == .none and g_ctl_capture == null) {
            if (scrollOf(screen)) |s| {
                if (clicked and s.track.contains(hover_x, hover_y)) {
                    g_pointer.dragging = true;
                    clicked = false;
                }
                if (g_pointer.dragging) {
                    const top = s.topAt(g_pointer.y);
                    switch (screen) {
                        .settings, .features, .alttpr => {
                            const li = listIndex(screen);
                            list_top[li] = top;
                            list_cursor[li] = keepInView(screen, list_cursor[li], top, s.shown);
                        },
                        .achievements => {
                            g_ach_top = top;
                            g_ach_row = std.math.clamp(g_ach_row, top, top + s.shown - 1);
                        },
                        .details => g_details_top = top,
                        else => {},
                    }
                    // Dragging isn't pointing at rows.
                    hovered = false;
                }
            } else g_pointer.dragging = false;
        }

        // A question on top of the screen takes the input until answered.
        if (modal != .none) {
            switch (modal) {
                .quit => {
                    if (hovered) {
                        const under = choiceUnder(kQuitChoices.len, hover_x, hover_y);
                        if (g_pointer.enters(under)) quit_choice = under.?;
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
                // Anything that means "done" puts it away.
                .info => if (confirm or back or info or clicked) {
                    modal = .none;
                },
                // A name for the pack, then in it goes.
                .msu_name => {
                    if (hovered) {
                        const under = choiceUnder(kMsuNameChoices.len, hover_x, hover_y);
                        if (g_pointer.enters(under)) g_msu_name_choice = under.?;
                    }
                    if (adjust != 0) g_msu_name_choice = 1 - g_msu_name_choice;
                    if (move != 0 and g_msu_pcm != 0) g_msu_on_check = !g_msu_on_check;
                    if (clicked and g_msu_pcm != 0 and msuCheckRect().contains(hover_x, hover_y)) {
                        toggleMsuFlac();
                        clicked = false;
                    }
                    if (confirm and g_msu_on_check) {
                        toggleMsuFlac();
                        confirm = false;
                    }
                    if (name_enter) confirm = true;
                    var over_choice = false;
                    if (clicked) {
                        for (0..kMsuNameChoices.len) |i| {
                            if (modalChoiceRect(i).contains(hover_x, hover_y)) {
                                g_msu_name_choice = i;
                                over_choice = true;
                            }
                        }
                    }
                    if (back or ((confirm or over_choice) and g_msu_name_choice == 1)) {
                        dropMsuName(window);
                        modal = .none;
                    } else if (confirm or over_choice) {
                        _ = c.SDL_StopTextInput(window);
                        if (startMsuImport()) {
                            modal = .msu_progress;
                        } else {
                            dropMsuName(window);
                            modal = .none;
                            status = "COULD NOT START THE IMPORT";
                        }
                    }
                },
                // Nothing to do but watch, or stop it.
                .msu_progress => {
                    if (hovered) g_msu_stop_hover = msuStopRect().contains(hover_x, hover_y);
                    const stop = back or (clicked and msuStopRect().contains(hover_x, hover_y));
                    if (stop) if (g_msu_job) |job| job.status.cancel.store(true, .release);
                },
                // Folder or Zip File opens the system's picker for one; a
                // drop on the window (above) works without it.
                .msu => {
                    if (hovered) {
                        const under = choiceUnder(kMsuChoices.len, hover_x, hover_y);
                        if (g_pointer.enters(under)) g_msu_choice = under.?;
                    }
                    const step = if (adjust != 0) adjust else move;
                    if (step != 0) g_msu_choice = 1 - g_msu_choice;
                    var over_choice = false;
                    if (clicked) {
                        for (0..kMsuChoices.len) |i| {
                            if (modalChoiceRect(i).contains(hover_x, hover_y)) {
                                g_msu_choice = i;
                                over_choice = true;
                            }
                        }
                    }
                    if (confirm or over_choice) openMsuPicker(window, g_msu_choice == 1);
                    if (back) modal = .none;
                },
                .update => switch (updater.phase()) {
                    .available, .failed => |p| {
                        if (hovered) {
                            const under = choiceUnder(kUpdateChoices.len, hover_x, hover_y);
                            if (g_pointer.enters(under)) g_update_choice = under.?;
                        }
                        const step = if (adjust != 0) adjust else move;
                        if (step != 0) g_update_choice = 1 - g_update_choice;
                        var over_choice = false;
                        if (clicked) {
                            for (0..kUpdateChoices.len) |i| {
                                if (modalChoiceRect(i).contains(hover_x, hover_y)) {
                                    g_update_choice = i;
                                    over_choice = true;
                                }
                            }
                        }
                        if (confirm or over_choice) {
                            if (g_update_choice == 0 and p == .available) {
                                updater.install();
                            } else {
                                if (g_update_choice == 0) _ = c.SDL_OpenURL(updater.pageUrl().ptr);
                                // Closing a failure leaves the button there
                                // to try again with.
                                updater.dismiss();
                                modal = .none;
                            }
                        }
                        if (back) {
                            updater.dismiss();
                            modal = .none;
                        }
                    },
                    // Only the download can stop; once the files are going
                    // in, they finish.
                    .downloading => if (back) updater.cancel(),
                    else => {},
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
                var under: ?usize = null;
                for (0..kMainItems.len) |i| {
                    if (mainShown(i) and mainEntryRect(i).contains(hover_x, hover_y)) under = i;
                }
                if (g_pointer.enters(under)) main_cursor = under.?;
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
                // Down from Play reaches Randomizer, the last one. Import
                // MSU-1 is stepped over while it isn't showing.
                const n: i32 = @intCast(kMainItems.len);
                var at: i32 = @intCast(main_cursor);
                while (true) {
                    at = @mod(at + move + n, n);
                    if (mainShown(@intCast(at))) break;
                }
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
                    kMainAchievements => {
                        g_ach_unlocked = achievement_list.Unlocked.load(alloc);
                        screen = .achievements;
                        status = "";
                    },
                    kMainSave => save_queued = true,
                    kMainBuild => {
                        modal = .rom;
                        status = "";
                    },
                    kMainImport => {
                        modal = .msu;
                        g_msu_choice = 0;
                        status = "";
                    },
                    kMainRandomizer => {
                        screen = .hub;
                        status = "";
                    },
                    kMainUpdate => {
                        modal = .update;
                        g_update_choice = 0;
                        status = "";
                    },
                    kMainTools => {
                        const exit = runTools(alloc, window, renderer, msuPathIn(&ini));
                        // What was held when they opened was let go in them.
                        held = .{};
                        vrepeat = .{};
                        hrepeat = .{};
                        g_pointer.forget();
                        // They may well have built some.
                        assets = checkAssets(alloc);
                        status = "";
                        // Play in the language a build just put in.
                        if (exit.language) |lang| {
                            if (settingIndex("General", "Language")) |li| {
                                ini.set(li, langs.get(lang).code) catch {};
                                dirty = true;
                            }
                        }
                        // The installed pack Use picked in the tools (or the
                        // one left playing after a delete).
                        if (exit.msu_path) |path| {
                            defer std.heap.c_allocator.free(path);
                            if (settingIndex("Sound", "MSUPath")) |mi| {
                                if (ini.set(mi, path)) |_| {
                                    if (ini.save("zelda3.ini")) |_| {
                                        dirty = false;
                                    } else |_| {
                                        dirty = true;
                                    }
                                } else |_| {}
                            }
                        }
                        // The pack the tools just checked: MSU on if it
                        // wasn't, kept, and the pack brought in.
                        if (exit.msu_pack) |pack| import: {
                            defer std.heap.c_allocator.free(pack);
                            // Quitting outright isn't the time for it.
                            if (exit.to == .quit) break :import;
                            if (!msuOnIn(&ini)) {
                                if (settingIndex("Sound", "EnableMSU")) |mi| {
                                    ini.set(mi, "true") catch {};
                                    dirty = true;
                                }
                            }
                            g_msu_on = msuOnIn(&ini);
                            if (dirty) {
                                if (ini.save("zelda3.ini")) |_| {
                                    dirty = false;
                                } else |_| {}
                            }
                            if (exit.to == .menu and g_msu_job == null) {
                                askMsuName(window, pack);
                                modal = .msu_name;
                            }
                        }
                        switch (exit.to) {
                            .menu => {},
                            .quit => running = false,
                            // As Play here does: keep the settings, and go
                            // if there's something to play.
                            .play => {
                                if (dirty) ini.save("zelda3.ini") catch {};
                                dirty = false;
                                if (assets.playable()) {
                                    launch = true;
                                    running = false;
                                } else modal = .rom;
                            },
                        }
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
                        if (!assets.playable()) {
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
                var under: ?usize = null;
                for (0..ctlVisible()) |slot| {
                    if (g_ctl_top + slot >= kCtlRows) break;
                    if (ctlRowRect(slot).contains(hover_x, hover_y)) under = slot;
                }
                if (hovered and g_pointer.enters(under)) g_ctl_row = g_ctl_top + under.?;
                if (clicked) if (under) |slot| {
                    g_ctl_row = g_ctl_top + slot;
                    confirm = true;
                };
                if (wheel != 0) {
                    if (kCtlRows > ctlVisible()) {
                        g_ctl_top = scrolled(g_ctl_top, -wheel, kCtlRows - ctlVisible());
                        g_ctl_row = std.math.clamp(g_ctl_row, g_ctl_top, g_ctl_top + ctlVisible() - 1);
                    } else move = -std.math.sign(wheel);
                }
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
                if (g_ctl_row >= g_ctl_top + ctlVisible()) g_ctl_top = g_ctl_row + 1 - ctlVisible();
                g_ctl_top = @min(g_ctl_top, kCtlRows - ctlVisible());
            }
        } else if (screen == .achievements) {
            if (back) {
                screen = .main;
                status = "";
            }
            var under: ?usize = null;
            for (0..achVisible()) |slot| {
                if (g_ach_top + slot >= kAchRows) break;
                if (achRowRect(slot).contains(hover_x, hover_y)) under = slot;
            }
            if (hovered and g_pointer.enters(under)) g_ach_row = g_ach_top + under.?;
            if (clicked) if (under) |slot| {
                g_ach_row = g_ach_top + slot;
            };
            if (wheel != 0) {
                // The wheel moves the page; the pointer, if it's on the
                // list, picks whatever lands under it.
                g_ach_top = scrolled(g_ach_top, -wheel, kAchRows -| achVisible());
                g_ach_row = std.math.clamp(g_ach_row, g_ach_top, g_ach_top + achVisible() - 1);
                for (0..achVisible()) |slot| {
                    if (achRowRect(slot).contains(g_pointer.x, g_pointer.y)) {
                        g_ach_row = g_ach_top + slot;
                        g_pointer.over = slot;
                    }
                }
            }
            if (move != 0) g_ach_row = @intCast(@mod(@as(i32, @intCast(g_ach_row)) + move, @as(i32, kAchRows)));
            if (g_ach_row < g_ach_top) g_ach_top = g_ach_row;
            if (g_ach_row >= g_ach_top + achVisible()) g_ach_top = g_ach_row + 1 - achVisible();
            g_ach_top = @min(g_ach_top, kAchRows -| achVisible());
        } else if (screen == .hub) {
            if (back) {
                screen = .main;
                status = "";
            }
            var under: ?usize = null;
            for (0..kHubItems.len) |i| {
                if (hubRect(i).contains(hover_x, hover_y)) under = i;
            }
            if (hovered and g_pointer.enters(under)) g_hub_cursor = under.?;
            if (clicked) if (under) |i| {
                g_hub_cursor = i;
                confirm = true;
            };
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
            const count = detailCount();
            const max_top = count -| kDetailsRows;
            if (wheel != 0) g_details_top = scrolled(g_details_top, -wheel, max_top);
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

            const v = viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice);
            const under = listRowAt(v, hover_x, hover_y);
            // Slots rather than rows, so the list moving isn't the pointer.
            if (hovered and g_pointer.enters(if (under) |row| row - list_top[li] else null)) list_cursor[li] = under.?;
            var step_back = false;
            if (clicked) if (under) |row| {
                list_cursor[li] = row;
                confirm = true;
                // The arrow left of a value steps it back.
                step_back = onLeftArrow(&ini, screen, row, row - list_top[li], hover_x, hover_y);
            };

            // The wheel moves the page, not the cursor; the pointer, if it's
            // on the list, picks whatever lands under it. A list that fits
            // has nowhere to scroll, so there it steps the cursor.
            if (wheel != 0) {
                if (n > shown) {
                    list_top[li] = scrolled(list_top[li], -wheel, n - shown);
                    const after = viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice);
                    if (listRowAt(after, g_pointer.x, g_pointer.y)) |row| {
                        list_cursor[li] = row;
                        g_pointer.over = row - list_top[li];
                    } else list_cursor[li] = keepInView(screen, list_cursor[li], list_top[li], shown);
                } else move = -std.math.sign(wheel);
            }

            if (confirm) adjust = if (step_back) -1 else 1;

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
            if (info and (screen == .settings or screen == .features) and at < kSettings.len) {
                modal = .info;
                status = "";
            } else if (screen == .alttpr and (start or (confirm and at == kPlayRow))) {
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
            } else if ((adjust != 0 or confirm) and at < kSettings.len and kSettings[at].kind == .action) {
                try applyCrtDefaults(&ini);
                dirty = true;
                status = "CRT SETTINGS RESET";
            } else if (adjust != 0 and at < kSettings.len and isMsuPack(kSettings[at])) {
                var arena_state = std.heap.ArenaAllocator.init(alloc);
                defer arena_state.deinit();
                if (nextPack(arena_state.allocator(), ini.values[at] orelse "", adjust)) |next| {
                    try ini.set(at, next);
                    dirty = true;
                    status = "";
                } else {
                    status = "IMPORT MSU-1 ADDS PACKS TO PICK FROM";
                }
            } else if (adjust != 0 and at < kSettings.len) {
                var buf: [64]u8 = undefined;
                const cur = ini.values[at] orelse "";
                if (cycle(alloc, &buf, kSettings[at], cur, adjust)) |next| {
                    try ini.set(at, next);
                    // A filter brings its own sliders, curve and bezel.
                    if (isCrtFilter(kSettings[at])) try applyCrtDefaults(&ini);
                    if (isUpdateSetting(kSettings[at])) recheckUpdates(&ini);
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
            if (main_cursor == kMainLaunch and screen == .main and assets.playable()) {
                launch = true;
                running = false;
            }
        }

        // Installed: keep the settings, start the new game, and go. If it
        // won't start, it's still installed, and opening it again does it.
        if (updater.phase() == .ready and running) {
            if (dirty) ini.save("zelda3.ini") catch {};
            if (!updater.restart()) std.debug.print("Updated, but could not start the new version: {s}\n", .{c.SDL_GetError()});
            running = false;
        }

        if (screen != screen_was or modal != modal_was) g_pointer.forget();

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
    return std.fmt.bufPrintSentinel(buf, "zig-cache-{s}-{d}.{s}", .{ base, pid, ext }, 0);
}

test {
    // The MSU-1 importer's own tests, with the start menu that uses it, and
    // the modern front page's, and the banner it can show.
    _ = msu_import;
    _ = start_page;
    _ = start_logo;
    _ = tools_gui;
}

test "every setting on the Settings and Features pages has a description that fits its box" {
    for (kSettings[0..kRandomizerStart]) |s| {
        if (isSection(s)) continue;
        const d = describe(s);
        if (d.len == 0) {
            std.debug.print("no description for {s}\n", .{s.key});
            return error.MissingDescription;
        }
        var lines = LineWrap{ .text = d, .width = kInfoChars };
        var n: usize = 0;
        while (lines.next()) |line| : (n += 1) try testing.expect(line.len <= kInfoChars);
        if (n > kInfoLines) {
            std.debug.print("{s}'s description runs to {d} lines\n", .{ s.key, n });
            return error.DescriptionTooLong;
        }
    }
    // The box itself stays clear of the footer.
    const footer_y: f32 = kWindowH - 32 - kRowH * 2 - 6;
    try testing.expect(kInfoRect.y + kInfoRect.h <= footer_y);
}

test "lines wrap at spaces and never run long" {
    var lines = LineWrap{ .text = "one two three four", .width = 9 };
    try testing.expectEqualStrings("one two", lines.next().?);
    try testing.expectEqualStrings("three", lines.next().?);
    try testing.expectEqualStrings("four", lines.next().?);
    try testing.expectEqual(@as(?[]const u8, null), lines.next());
}

test "the old data directory moves into an empty new one, and only then" {
    const t = std.testing;
    const root = ".zig-cache/data-dir-test";
    const old = root ++ "/alttp-zig";
    const new = root ++ "/alttp-dx";
    defer {
        for ([_][*:0]const u8{ old ++ "/sram.dat", new ++ "/sram.dat", new ++ "/zelda3.ini" }) |f| _ = fileio.remove(f);
        fileio.removeDir(old);
        fileio.removeDir(new);
        fileio.removeDir(root);
    }
    try fileio.makeDir(root);

    // Old saves, and the empty new directory SDL makes: they move over.
    try fileio.makeDir(old);
    try fileio.writeWholeFile(old ++ "/sram.dat", "save");
    try fileio.makeDir(new);
    moveDataDirectory(old, new);
    try t.expect(!fileio.isDir(old));
    try t.expect(fileio.exists(new ++ "/sram.dat"));

    // A new directory that's been used already is left alone, old one too.
    try fileio.makeDir(old);
    try fileio.writeWholeFile(new ++ "/zelda3.ini", "ini");
    moveDataDirectory(old, new);
    try t.expect(fileio.isDir(old));
    try t.expect(fileio.exists(new ++ "/zelda3.ini"));
}

test "the old data directory sits beside the new one" {
    var buf: [256]u8 = undefined;
    const t = std.testing;
    try t.expectEqualStrings("/Users/me/Library/Application Support/alttp-zig", oldDataDirectory(&buf, "/Users/me/Library/Application Support/alttp-dx/").?);
    try t.expectEqualStrings("C:\\Users\\me\\AppData\\Roaming\\alttp-zig", oldDataDirectory(&buf, "C:\\Users\\me\\AppData\\Roaming\\alttp-dx\\").?);
    try t.expectEqual(@as(?[:0]const u8, null), oldDataDirectory(&buf, "/somewhere/else/"));
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

test "picking a filter brings its own CRT settings, and the reset puts them back" {
    var path_buf: [64]u8 = undefined;
    const path = try scratchName(&path_buf, "crt", "ini");
    try fileio.writeWholeFile(path, "[Graphics]\nCrtFilter = tv\nCrtScanlines = 40%\nCrtCurvature = 0%\nCrtBezel = 0\n");
    defer _ = fileio.remove(path);
    var ini = try Ini.load(testing.allocator, path);
    defer ini.deinit();
    try applyCrtDefaults(&ini);
    try testing.expectEqualStrings("100%", ini.values[settingIndex("Graphics", "CrtScanlines").?].?);
    try testing.expectEqualStrings("50%", ini.values[settingIndex("Graphics", "CrtCurvature").?].?);
    try testing.expectEqualStrings("1", ini.values[settingIndex("Graphics", "CrtBezel").?].?);
}

test "every schema entry names a real key in the shipped ini" {
    var ini = try Ini.load(testing.allocator, "zelda3.ini");
    defer ini.deinit();
    for (kSettings, 0..) |s, i| {
        if (std.mem.eql(u8, s.section, kSectionMark)) continue;
        // A button keeps nothing in the ini.
        if (s.kind == .action) continue;
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
        "INFO Y/I   SAVE X/S   BACK B/ESC",
        "A OR B TO CLOSE",
        "A/ENTER BROWSE   B/ESC CANCEL",
        "IMPORT AN MSU-1 PACK",
        "DROP A FOLDER OR .ZIP HERE,",
        "TURN ON MSU AUDIO TO IMPORT A PACK",
        // Headers.
        "THE LEGEND OF ZELDA",
        "A LINK TO THE PAST DX",
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

test "a mod or a translation plays, and an old asset file doesn't" {
    const alloc = testing.allocator;
    var scratch_buf: [64]u8 = undefined;
    const scratch = try scratchName(&scratch_buf, "customtest", "dat");
    defer _ = fileio.remove(scratch);

    // This version's header and asset count, and anything at all after.
    const pack = @import("asset_pack.zig");
    var data: [88 + pack.kGameAssetCount * 4 + 16]u8 = @splat(0);
    @memcpy(data[0..48], &pack.kGameHeader);
    std.mem.writeInt(u32, data[80..84], pack.kGameAssetCount, .little);
    try fileio.writeWholeFile(scratch, &data);
    const custom = checkAssetsAt(alloc, scratch);
    try testing.expectEqual(AssetState.custom, custom);
    try testing.expect(custom.playable());

    // Another version's names hash to something else.
    data[20] ^= 0xff;
    try fileio.writeWholeFile(scratch, &data);
    const old = checkAssetsAt(alloc, scratch);
    try testing.expectEqual(AssetState.unrecognized, old);
    try testing.expect(!old.playable());
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
    // A changed payload can't be told from a mod's, but it isn't passed off
    // as the standard file either.
    try testing.expectEqual(AssetState.custom, checkAssetsAt(alloc, scratch));
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
    // With MSU audio off and on: Import MSU-1 shows only with it on, and
    // the entries close up to make room for it.
    defer g_msu_on = false;
    for ([_]bool{ false, true }) |msu| {
        g_msu_on = msu;
        try testing.expectEqual(msu, mainShown(kMainImport));
        var prev = mainEntryRect(0);
        try testing.expect(prev.w > 0 and prev.h > 0);

        for (1..kMainItems.len) |i| {
            if (!mainShown(i)) continue;
            const r = mainEntryRect(i);
            testing.expect(r.y >= prev.y + prev.h) catch |err| {
                std.debug.print("msu {}: entry {d} at y={d} overlaps the one above ending at {d}\n", .{ msu, i, r.y, prev.y + prev.h });
                return err;
            };
            prev = r;
        }

        // Everything stays inside the frame, and below the title's rule.
        for (0..kMainItems.len) |i| {
            if (!mainShown(i)) continue;
            const r = mainEntryRect(i);
            try testing.expect(r.x >= 16 and r.x + r.w <= kWindowW - 16);
            try testing.expect(r.y >= 36 + kRowH * 3 + 8 and r.y + r.h <= kWindowH - 16);
        }
        // And the last entry's highlight clears Play's ring.
        const last: usize = if (msu) kMainImport else kMainTools;
        try testing.expect(mainEntryRect(last).y + entryLayout().gap - 2 <= kLaunchY - kRingAbove);
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
        const hit = listRowAt(v, 100, y + 2);
        if (isSection(kSettings[i])) {
            try testing.expect(hit == null);
        } else {
            try testing.expectEqual(@as(?usize, i), hit);
        }
        y += kRowH;
    }

    // Above and below the list is nothing at all.
    try testing.expect(listRowAt(v, 100, kListStartY - 20) == null);
    try testing.expect(listRowAt(v, 100, kListStartY + kRowH * kVisibleRows + 40) == null);
}

test "a setting the file lacks shows its default and is added when changed" {
    // The menu's tests run in two test binaries at once, so the scratch file
    // is named per process.
    var path_buf: [64]u8 = undefined;
    // getpid() is a handle rather than a number on Windows, which has its own.
    const pid: u64 = if (builtin.os.tag == .windows) std.os.windows.GetCurrentProcessId() else @intCast(std.c.getpid());
    const path = try std.fmt.bufPrintSentinel(&path_buf, "zig-cache-missing-key-{d}.ini", .{pid}, 0);
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
    const state_y = launchRect().y + launchRect().h + kStateGap;
    const hint_bottom = state_y + kRowH + kCell;
    try testing.expect(randoRect().y >= hint_bottom);
    const footer_y: f32 = kWindowH - 32 - kRowH * 2 - 6;
    try testing.expect(randoRect().y + randoRect().h <= footer_y - kRowH);
    // And the rings the buttons get when picked: Play's clears the state
    // line, and Randomizer's clears the hint and the footer.
    try testing.expect(launchRect().y + launchRect().h + kRingBelow < state_y);
    try testing.expect(randoRect().y - kRingAbove >= hint_bottom);
    try testing.expect(randoRect().y + randoRect().h + kRingBelow <= footer_y);
}

test "the modern sub-screens fit their widescreen window" {
    g_modern = true;
    defer g_modern = false;
    const W = start_page.kW;
    // Lists, achievements and controls stop above the footer.
    const last = modernRowRect(kModernVisible - 1);
    try testing.expect(last.y + last.h <= start_page.kBodyBottom);
    try testing.expect(kModernListX + kModernListW + 16 <= kModernPanel.x);
    try testing.expect(kModernPanel.x + kModernPanel.w <= W - 16);
    // All thirteen rows, the twelve buttons and Reset. (Not kCtlRows, which
    // would drag the controls code and its C into this test binary.)
    const ctl = ctlRowRect(12);
    try testing.expect(ctl.y + ctl.h <= start_page.kBodyBottom);
    try testing.expect(start_page.kBodyTop + 12 + kModernDetailH * kDetailsRows <= start_page.kBodyBottom);
    // The pad fits beside the rows.
    try testing.expect(40 + 26 + pad_art.kWidth * 3 <= kModernCtlX - 28);
    // The two big choices sit side by side, apart.
    const a = hubRect(0);
    const b = hubRect(1);
    try testing.expect(a.x + a.w < b.x and b.x + b.w <= W - 16);
    try testing.expect(a.y > start_page.kHeaderRule and a.y + a.h < start_page.kFooterY);
    // Questions sit inside the window, with their answers inside them.
    const box = modalRect();
    try testing.expect(box.x >= 0 and box.x + box.w <= W and box.y + box.h <= start_page.kFooterY);
    try testing.expect(modalChoiceRect(1).x + modalChoiceRect(1).w <= box.x + box.w);
    // A click on a list row finds it, and one on the panel beside it doesn't.
    const v = View{ .screen = .settings, .modal = .none, .quit_choice = 0, .cursor = 1, .details_top = 0, .top = 0, .status = "", .dirty = false, .assets = .verified };
    const r = modernRowRect(1);
    try testing.expect(listRowAt(v, r.x + 10, r.y + 5) == 1);
    try testing.expect(listRowAt(v, kModernPanel.x + 10, r.y + 5) == null);
}

test "the pointer picks a row by moving onto it, not by sitting on it" {
    var ptr = Pointer{};
    // Onto row 3: picked. Wiggling on it: the keys keep their choice.
    try testing.expect(ptr.enters(3));
    try testing.expect(!ptr.enters(3));
    try testing.expect(!ptr.enters(3));
    // Off the list and back on: picked again.
    try testing.expect(!ptr.enters(null));
    try testing.expect(ptr.enters(3));
    try testing.expect(ptr.enters(4));
    ptr.forget();
    try testing.expect(ptr.enters(4));
}

test "the wheel scrolls whole rows and saves the slivers" {
    var ptr = Pointer{};
    // A trackpad's little pushes add up to a row.
    for (0..4) |_| ptr.addWheel(0.3);
    try testing.expectEqual(@as(i32, 1), ptr.takeWheel());
    try testing.expectEqual(@as(i32, 0), ptr.takeWheel());
    // Turning back doesn't have to undo what was left over first.
    ptr.addWheel(-1.0);
    try testing.expectEqual(@as(i32, -1), ptr.takeWheel());
    ptr.addWheel(3.5);
    try testing.expectEqual(@as(i32, 3), ptr.takeWheel());

    try testing.expectEqual(@as(usize, 0), scrolled(2, -5, 10));
    try testing.expectEqual(@as(usize, 10), scrolled(8, 5, 10));
    try testing.expectEqual(@as(usize, 6), scrolled(4, 2, 10));
}

test "a dragged scrollbar puts the thumb under the pointer" {
    const s = Scroll{ .track = .{ .x = 0, .y = 100, .w = 20, .h = 200 }, .len = 40, .shown = 10 };
    try testing.expectEqual(@as(usize, 0), s.topAt(0));
    try testing.expectEqual(@as(usize, 0), s.topAt(110));
    try testing.expectEqual(@as(usize, 15), s.topAt(200));
    try testing.expectEqual(@as(usize, 30), s.topAt(300));
    try testing.expectEqual(@as(usize, 30), s.topAt(900));
}

test "capitals soften into sentence case and leave the rest alone" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("In dungeon", soft(&buf, "IN DUNGEON"));
    try testing.expectEqualStrings("On", soft(&buf, "ON"));
    try testing.expectEqualStrings("SNES emulator", soft(&buf, "SNES EMULATOR"));
    try testing.expectEqualStrings("Japanese 1.0 ROM", soft(&buf, "JAPANESE 1.0 ROM"));
    try testing.expectEqualStrings("Plays the game's MSU pack (MSUPATH)", soft(&buf, "PLAYS THE GAME'S MSU PACK (MSUPATH)"));
    try testing.expectEqualStrings("Releases", soft(&buf, "Releases"));
}
