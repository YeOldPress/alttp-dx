//! A settings front end for zelda3.
//!
//! Reads zelda3.ini, lets the options be changed with a keyboard or a gamepad,
//! writes the file back and starts the game. The ini is edited a line at a time
//! rather than reparsed and regenerated, so the comments that document each
//! option survive a round trip.
//!
//! Drawing uses SDL3's built in 8x8 font (SDL_RenderDebugText), so the launcher
//! needs no font file and no toolkit - just the SDL the game already links.
const std = @import("std");
const fileio = @import("fileio.zig");
const rom_mod = @import("rom.zig");
const asset_all = @import("asset_all.zig");

const c = @cImport({
    // translate-c cannot parse arm_neon.h, which SDL pulls in on ARM targets.
    @cDefine("SDL_DISABLE_NEON", "1");
    @cInclude("SDL3/SDL.h");
});

/// The game binary, expected next to the launcher.
const kGameExe = "./zelda3";
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
const kColorSection = Rgb{ .r = 0x78, .g = 0xd8, .b = 0x98 };

// ---------------------------------------------------------------- settings

/// How a setting's value is presented and cycled.
const Kind = union(enum) {
    /// 0 or 1, shown as OFF / ON.
    toggle,
    /// One of a fixed set of spellings, cycled in order.
    choice: []const []const u8,
    /// A whole number, nudged by `step` and clamped to the range. `suffix` is
    /// kept on the value when written back, for entries like "100%".
    number: struct { min: i32, max: i32, step: i32, suffix: []const u8 = "" },
    /// Shown but not editable here: free text that wants a keyboard, or a
    /// binding list that wants a capture UI.
    text,
};

const Setting = struct {
    section: []const u8,
    key: []const u8,
    label: []const u8,
    kind: Kind,
};

/// A heading row in the list. Not a setting; drawn differently and skipped
/// when the cursor moves.
const kSectionMark = "\x00SECTION";

const kSettings = [_]Setting{
    .{ .section = kSectionMark, .key = "", .label = "GENERAL", .kind = .text },
    .{ .section = "General", .key = "Autosave", .label = "Autosave", .kind = .toggle },
    .{ .section = "General", .key = "DisplayPerfInTitle", .label = "Show FPS In Title", .kind = .toggle },
    .{ .section = "General", .key = "ExtendedAspectRatio", .label = "Aspect Ratio", .kind = .{ .choice = &.{ "4:3", "16:9", "16:10", "18:9" } } },
    .{ .section = "General", .key = "DisableFrameDelay", .label = "Disable Frame Delay", .kind = .toggle },

    .{ .section = kSectionMark, .key = "", .label = "GRAPHICS", .kind = .text },
    .{ .section = "Graphics", .key = "Fullscreen", .label = "Fullscreen", .kind = .{ .choice = &.{ "0", "1", "2" } } },
    .{ .section = "Graphics", .key = "WindowScale", .label = "Window Scale", .kind = .{ .number = .{ .min = 1, .max = 10, .step = 1 } } },
    .{ .section = "Graphics", .key = "OutputMethod", .label = "Output Method", .kind = .{ .choice = &.{ "SDL", "SDL-Software", "OpenGL", "OpenGL ES" } } },
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
    .{ .section = "Sound", .key = "AudioFreq", .label = "Audio Frequency", .kind = .{ .choice = &.{ "11025", "22050", "32000", "44100", "48000" } } },
    .{ .section = "Sound", .key = "AudioChannels", .label = "Audio Channels", .kind = .{ .choice = &.{ "1", "2" } } },
    .{ .section = "Sound", .key = "AudioSamples", .label = "Audio Buffer", .kind = .{ .choice = &.{ "512", "1024", "2048", "4096" } } },
    .{ .section = "Sound", .key = "EnableMSU", .label = "MSU Audio", .kind = .{ .choice = &.{ "false", "true", "deluxe", "opuz", "deluxe-opuz" } } },
    .{ .section = "Sound", .key = "MSUVolume", .label = "MSU Volume", .kind = .{ .number = .{ .min = 0, .max = 100, .step = 5, .suffix = "%" } } },
    .{ .section = "Sound", .key = "ResumeMSU", .label = "Resume MSU", .kind = .toggle },
    .{ .section = "Sound", .key = "MSUPath", .label = "MSU Path", .kind = .text },

    .{ .section = kSectionMark, .key = "", .label = "FEATURES", .kind = .text },
    .{ .section = "Features", .key = "ItemSwitchLR", .label = "Switch Items With L/R", .kind = .toggle },
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
};

// ------------------------------------------------------------- ini editing

/// The ini kept as its original lines, with each setting bound to the line it
/// came from. Values are rewritten in place so comments, blank lines, ordering
/// and line endings all survive.
const Ini = struct {
    alloc: std.mem.Allocator,
    text: []u8,
    lines: std.ArrayList([]const u8),
    /// Owned replacement values, indexed alongside kSettings. Null means the
    /// setting was not found in the file.
    values: [kSettings.len]?[]u8,
    line_of: [kSettings.len]?usize,
    crlf: bool,

    fn load(alloc: std.mem.Allocator, path: [*:0]const u8) !Ini {
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
        // the line that carries it.
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
        return self;
    }

    fn deinit(self: *Ini) void {
        for (self.values) |v| if (v) |owned| self.alloc.free(owned);
        self.lines.deinit(self.alloc);
        self.alloc.free(self.text);
    }

    fn set(self: *Ini, si: usize, value: []const u8) !void {
        const owned = try self.alloc.dupe(u8, value);
        if (self.values[si]) |old| self.alloc.free(old);
        self.values[si] = owned;
    }

    fn save(self: *Ini, path: [*:0]const u8) !void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.alloc);
        const eol: []const u8 = if (self.crlf) "\r\n" else "\n";

        for (self.lines.items, 0..) |line, idx| {
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
        try fileio.writeWholeFile(path, out.items);
    }
};

// ------------------------------------------------------------------- value

fn splitSuffix(value: []const u8, suffix: []const u8) []const u8 {
    if (suffix.len != 0 and std.mem.endsWith(u8, value, suffix))
        return value[0 .. value.len - suffix.len];
    return value;
}

/// Steps a setting's value. `dir` is +1 or -1.
fn cycle(alloc: std.mem.Allocator, buf: []u8, s: Setting, current: []const u8, dir: i32) ?[]const u8 {
    switch (s.kind) {
        .toggle => return if (std.mem.eql(u8, std.mem.trim(u8, current, " \t"), "1")) "0" else "1",
        .choice => |opts| {
            var at: usize = 0;
            for (opts, 0..) |o, i| {
                if (std.ascii.eqlIgnoreCase(o, current)) {
                    at = i;
                    break;
                }
            }
            const n: i32 = @intCast(opts.len);
            var next: i32 = @as(i32, @intCast(at)) + dir;
            if (next < 0) next = n - 1;
            if (next >= n) next = 0;
            return opts[@intCast(next)];
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
fn displayValue(buf: []u8, s: Setting, value: []const u8) []const u8 {
    const v = std.mem.trim(u8, value, " \t");
    switch (s.kind) {
        .toggle => return if (std.mem.eql(u8, v, "1")) "ON" else "OFF",
        .text => return if (v.len == 0) "(none)" else v,
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

fn isSection(s: Setting) bool {
    return std.mem.eql(u8, s.section, kSectionMark);
}

fn firstSelectable(from: usize, to: usize) usize {
    var i = from;
    while (i < to) : (i += 1) if (!isSection(kSettings[i])) return i;
    return from;
}

/// The launcher is a short menu and the two lists it opens.
const Screen = enum { main, settings, features };

/// Where the FEATURES heading sits, so the two lists are slices of the one
/// schema instead of separate tables that could drift out of step with it.
const kFeaturesStart = blk: {
    for (kSettings, 0..) |s, i| {
        if (isSection(s) and std.mem.eql(u8, s.label, "FEATURES")) break :blk i;
    }
    @compileError("the settings schema has no FEATURES section");
};

fn screenRange(screen: Screen) struct { from: usize, to: usize } {
    return switch (screen) {
        .settings => .{ .from = 0, .to = kFeaturesStart },
        .features => .{ .from = kFeaturesStart, .to = kSettings.len },
        .main => .{ .from = 0, .to = 0 },
    };
}

const kMainItems = [_][]const u8{ "Settings", "Features", "Launch" };
const kMainLaunch = 2;

/// State the drawing needs. Passed as one value because the slow paths -
/// building assets - draw a frame before they block, and threading eight
/// arguments through those calls was its own small mess.
const View = struct {
    screen: Screen,
    cursor: usize,
    top: usize,
    status: []const u8,
    dirty: bool,
    have_assets: bool,
};

fn drawScreen(renderer: *c.SDL_Renderer, ini: *const Ini, v: View) void {
    fillRect(renderer, 0, 0, kWindowW, kWindowH, kColorBg);
    drawFrame(renderer, 16, 16, kWindowW - 32, kWindowH - 32);

    drawHeader(renderer, v.screen);

    switch (v.screen) {
        .main => drawMain(renderer, v),
        .settings, .features => drawList(renderer, ini, v),
    }

    drawFooter(renderer, v);
    _ = c.SDL_RenderPresent(renderer);
}

/// Title and the rule under it. The lists need the space, so the title stays
/// on one line and the rule doubles as the top of the list.
fn drawHeader(renderer: *c.SDL_Renderer, screen: Screen) void {
    const cx: f32 = kWindowW / 2;
    if (screen == .main) {
        drawTextCentered(renderer, cx, 44, kColorSelect, "THE LEGEND OF ZELDA", kScale);
        drawTextCentered(renderer, cx, 44 + kRowH, kColorTextDim, "LAUNCHER", kScale);
        fillRect(renderer, 60, 44 + kRowH * 2 + 6, kWindowW - 120, 2, kColorFrame);
        return;
    }

    const name = if (screen == .settings) "SETTINGS" else "FEATURES";
    drawText(renderer, 40, 36, kColorSelect, name);
    drawTextScaled(renderer, kWindowW - 40 - textWidth("ESC BACK", kScale), 36, kColorTextDim, "ESC BACK", kScale);
    fillRect(renderer, 40, 36 + kRowH, kWindowW - 80, 2, kColorFrame);
}

fn drawMain(renderer: *c.SDL_Renderer, v: View) void {
    const cx: f32 = kWindowW / 2;

    // The two list entries sit as a pair, with Launch set apart below them -
    // it leaves the launcher rather than moving within it.
    const kEntryY: f32 = 150;
    const kEntryGap: f32 = 44;

    for (kMainItems[0..kMainLaunch], 0..) |label, i| {
        const y = kEntryY + kEntryGap * @as(f32, @floatFromInt(i));
        const selected = i == v.cursor;
        const w = textWidth(label, kScale);

        if (selected) {
            // Sized to the word rather than the window, so the highlight
            // reads as a selection and not as a banner.
            fillRect(renderer, cx - w / 2 - 20, y - 8, w + 40, kRowH + 10, kColorRowHi);
            drawTextScaled(renderer, cx - w / 2 - 36, y, kColorSelect, ">", kScale);
        }
        drawTextCentered(renderer, cx, y, if (selected) kColorSelect else kColorText, label, kScale);
    }

    // Launch: a button, centred, big enough to be the obvious thing to press.
    const scale: f32 = kScale * 2;
    const label = kMainItems[kMainLaunch];
    const w = textWidth(label, scale);
    const box_w = w + 72;
    const box_h = 8 * scale + 28;
    const box_x = cx - box_w / 2;
    const box_y: f32 = 268;
    const selected = v.cursor == kMainLaunch;

    // Green whether or not it is selected - it is the one action the window
    // exists for. Selection is the ring, which has to be an outline: a frame
    // would paint its own interior over the button.
    fillRect(renderer, box_x, box_y, box_w, box_h, kColorLaunchBg);
    if (selected) drawOutline(renderer, box_x - 8, box_y - 8, box_w + 16, box_h + 16, 4, kColorFrameHi);
    drawTextCentered(renderer, cx, box_y + 14, kColorLaunchText, label, scale);

    // The game cannot start without its assets, and a ROM dropped on the
    // window is the shortest way to get them.
    if (!v.have_assets) {
        const hint_y: f32 = box_y + box_h + 16;
        drawTextCentered(renderer, cx, hint_y, kColorSelect, "NO ASSETS YET", kScale);
        drawTextCentered(renderer, cx, hint_y + kRowH, kColorTextDim, "DRAG A .SFC ROM ONTO THIS WINDOW", kScale);
    }
}

fn drawList(renderer: *c.SDL_Renderer, ini: *const Ini, v: View) void {
    const range = screenRange(v.screen);
    var y: f32 = 36 + kRowH + 14;
    var i = v.top;
    while (i < range.to and i < v.top + kVisibleRows) : (i += 1) {
        const s = kSettings[i];
        if (isSection(s)) {
            drawText(renderer, 40, y, kColorSection, s.label);
        } else {
            if (i == v.cursor) {
                fillRect(renderer, 32, y - 3, kWindowW - 64, kRowH, kColorRowHi);
                drawText(renderer, 36, y, kColorSelect, ">");
            }
            drawText(renderer, 56, y, if (i == v.cursor) kColorSelect else kColorText, s.label);
            var vbuf: [64]u8 = undefined;
            const shown = displayValue(&vbuf, s, ini.values[i] orelse "(missing)");
            const dim = s.kind == .text;
            drawText(renderer, 400, y, if (dim) kColorTextDim else kColorValue, shown);
        }
        y += kRowH;
    }
}

fn drawFooter(renderer: *c.SDL_Renderer, v: View) void {
    const footer_y: f32 = kWindowH - 32 - kRowH * 2 - 6;
    switch (v.screen) {
        .main => {
            drawText(renderer, 40, footer_y, kColorTextDim, "UP/DOWN MOVE   ENTER SELECT");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "B BUILD ASSETS   ESC QUIT");
        },
        .settings, .features => {
            drawText(renderer, 40, footer_y, kColorTextDim, "UP/DOWN MOVE   LEFT/RIGHT CHANGE");
            drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "S SAVE   ESC BACK");
        },
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

    const lang = rom.language orelse return "UNRECOGNISED ROM";
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

/// Builds zelda3_assets.dat from the ROM, replacing what the Python resource
/// tool did. Returns a message for the status line either way.
fn buildAssets(alloc: std.mem.Allocator) []const u8 {
    const path = g_rom_path orelse return "NEED " ++ kRomPath ++ " TO BUILD ASSETS";

    var rom = rom_mod.Rom.load(alloc, path.ptr) catch return "COULD NOT READ ROM";
    defer rom.deinit();
    if (rom.language != .us) return "ROM IS NOT THE US RELEASE";

    const data = asset_all.buildFile(alloc, rom) catch return "COULD NOT BUILD ASSETS";
    defer alloc.free(data);

    fileio.writeWholeFile(kAssetsPath, data) catch return "COULD NOT WRITE ASSETS";
    return "ASSETS BUILT";
}

pub fn main(init: std.process.Init.Minimal) !void {
    const alloc = std.heap.c_allocator;

    // The game reads zelda3.ini and zelda3_assets.dat from the working
    // directory, and inherits ours when we start it. Moving into the
    // directory the binaries were installed to makes the launcher edit the
    // same files the game will read, whatever directory it was started from.
    var start_dir_buf: [4096]u8 = undefined;
    const start_dir = fileio.workingDirectory(&start_dir_buf) catch ".";

    if (c.SDL_GetBasePath()) |base| {
        fileio.setWorkingDirectory(base) catch {};
    }

    g_rom_path = findRom(start_dir, &g_rom_buf);

    // Building the assets without opening a window, for scripts and for
    // checking the result against the Python tool's output.
    var args = init.args.iterate();
    _ = args.next();
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--build-assets")) {
            const msg = buildAssets(alloc);
            std.debug.print("{s}\n", .{msg});
            if (!fileio.exists(kAssetsPath)) return error.BuildFailed;
            return;
        }
        std.debug.print("unknown option: {s}\n", .{a});
        return error.BadUsage;
    }

    var ini = Ini.load(alloc, "zelda3.ini") catch |err| {
        std.debug.print("Could not read zelda3.ini: {s}\n", .{@errorName(err)});
        return err;
    };
    defer ini.deinit();

    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD)) {
        std.debug.print("Failed to init SDL: {s}\n", .{c.SDL_GetError()});
        return error.SdlInit;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("The Legend of Zelda - Launcher", kWindowW, kWindowH, 0) orelse {
        std.debug.print("Failed to create window: {s}\n", .{c.SDL_GetError()});
        return error.SdlWindow;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, null) orelse {
        std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
        return error.SdlRenderer;
    };
    defer c.SDL_DestroyRenderer(renderer);

    // Any pad plugged in can drive the list, same as in the game.
    var pad_count: c_int = 0;
    if (c.SDL_GetGamepads(&pad_count)) |pads| {
        for (pads[0..@intCast(pad_count)]) |id| _ = c.SDL_OpenGamepad(id);
        c.SDL_free(pads);
    }

    var screen: Screen = .main;
    var main_cursor: usize = 0;
    // Each list keeps its own place, so stepping out and back in does not
    // dump the cursor at the top again.
    var list_cursor = [_]usize{ firstSelectable(0, kFeaturesStart), firstSelectable(kFeaturesStart, kSettings.len) };
    var list_top = [_]usize{ 0, kFeaturesStart };
    var dirty = false;
    var launch = false;
    var status: []const u8 = "";
    var have_assets = fileio.exists(kAssetsPath);
    var running = true;
    var event: c.SDL_Event = undefined;

    const listIndex = struct {
        fn f(sc: Screen) usize {
            return if (sc == .features) 1 else 0;
        }
    }.f;

    while (running) {
        const li = listIndex(screen);
        const view = View{
            .screen = screen,
            .cursor = if (screen == .main) main_cursor else list_cursor[li],
            .top = list_top[li],
            .status = status,
            .dirty = dirty,
            .have_assets = have_assets,
        };

        while (c.SDL_PollEvent(&event)) {
            var move: i32 = 0;
            var adjust: i32 = 0;
            var confirm = false;
            var back = false;

            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,

                // A ROM dropped on the window is the quickest path from a
                // fresh checkout to a playable game.
                c.SDL_EVENT_DROP_FILE => {
                    if (event.drop.data) |path| {
                        status = "CHECKING ROM...";
                        drawScreen(renderer, &ini, view);
                        status = buildAssetsFromDrop(alloc, path);
                        have_assets = fileio.exists(kAssetsPath);
                    }
                },

                c.SDL_EVENT_KEY_DOWN => switch (event.key.key) {
                    c.SDLK_ESCAPE => back = true,
                    c.SDLK_UP => move = -1,
                    c.SDLK_DOWN => move = 1,
                    c.SDLK_LEFT => adjust = -1,
                    c.SDLK_RIGHT, c.SDLK_SPACE => adjust = 1,
                    c.SDLK_RETURN => confirm = true,
                    c.SDLK_B => {
                        // Drawing a frame first, so the window does not just
                        // freeze for the second or two this takes.
                        status = "BUILDING ASSETS...";
                        drawScreen(renderer, &ini, view);
                        status = buildAssets(alloc);
                        have_assets = fileio.exists(kAssetsPath);
                    },
                    c.SDLK_S => {
                        ini.save("zelda3.ini") catch |err| {
                            std.debug.print("Could not write zelda3.ini: {s}\n", .{@errorName(err)});
                            status = "COULD NOT SAVE";
                            continue;
                        };
                        dirty = false;
                        status = "SAVED";
                    },
                    else => {},
                },
                c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => switch (event.gbutton.button) {
                    c.SDL_GAMEPAD_BUTTON_DPAD_UP => move = -1,
                    c.SDL_GAMEPAD_BUTTON_DPAD_DOWN => move = 1,
                    c.SDL_GAMEPAD_BUTTON_DPAD_LEFT => adjust = -1,
                    c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT => adjust = 1,
                    c.SDL_GAMEPAD_BUTTON_SOUTH => confirm = true,
                    c.SDL_GAMEPAD_BUTTON_START => confirm = true,
                    c.SDL_GAMEPAD_BUTTON_EAST => back = true,
                    else => {},
                },
                else => {},
            }

            if (back) {
                // Escape steps out of a list, and quits from the menu.
                if (screen == .main) running = false else screen = .main;
                status = "";
                continue;
            }

            if (screen == .main) {
                if (move != 0) {
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
                        else => {
                            ini.save("zelda3.ini") catch |err| {
                                std.debug.print("Could not write zelda3.ini: {s}\n", .{@errorName(err)});
                                status = "COULD NOT SAVE";
                                continue;
                            };
                            dirty = false;

                            // The game cannot start without its assets, so
                            // build them rather than letting it fail.
                            if (!have_assets) {
                                if (g_rom_path == null) {
                                    status = "DRAG A .SFC ROM HERE FIRST";
                                    continue;
                                }
                                status = "BUILDING ASSETS...";
                                drawScreen(renderer, &ini, view);
                                status = buildAssets(alloc);
                                have_assets = fileio.exists(kAssetsPath);
                                if (!have_assets) continue;
                            }

                            launch = true;
                            running = false;
                        },
                    }
                }
                continue;
            }

            // The two lists behave the same; only their range differs.
            // Enter changes a value here, the same as right.
            if (confirm) adjust = 1;
            const range = screenRange(screen);
            if (move != 0) {
                // Step over the section headings.
                var at: i32 = @intCast(list_cursor[li]);
                const from: i32 = @intCast(range.from);
                const to: i32 = @intCast(range.to);
                while (true) {
                    at += move;
                    if (at < from) at = to - 1;
                    if (at >= to) at = from;
                    if (!isSection(kSettings[@intCast(at)])) break;
                }
                list_cursor[li] = @intCast(at);
                status = "";
            }

            if (adjust != 0) {
                var buf: [64]u8 = undefined;
                const at = list_cursor[li];
                const cur = ini.values[at] orelse "";
                if (cycle(alloc, &buf, kSettings[at], cur, adjust)) |next| {
                    try ini.set(at, next);
                    dirty = true;
                    status = "";
                }
            }
        }

        // Keep the cursor inside the visible window.
        if (screen != .main) {
            const li2 = listIndex(screen);
            const range = screenRange(screen);
            if (list_cursor[li2] < list_top[li2]) list_top[li2] = list_cursor[li2];
            if (list_cursor[li2] >= list_top[li2] + kVisibleRows)
                list_top[li2] = list_cursor[li2] - kVisibleRows + 1;
            if (list_top[li2] < range.from) list_top[li2] = range.from;
        }

        drawScreen(renderer, &ini, .{
            .screen = screen,
            .cursor = if (screen == .main) main_cursor else list_cursor[listIndex(screen)],
            .top = list_top[listIndex(screen)],
            .status = status,
            .dirty = dirty,
            .have_assets = have_assets,
        });
        c.SDL_Delay(16);
    }

    if (launch) {
        const argv = [_:null]?[*:0]const u8{ kGameExe, null };
        const proc = c.SDL_CreateProcess(@ptrCast(&argv), false) orelse {
            std.debug.print("Could not start {s}: {s}\n", .{ kGameExe, c.SDL_GetError() });
            return error.LaunchFailed;
        };
        // Wait so the launcher's window is gone but the shell still blocks on
        // the game, which is what someone running this from a terminal expects.
        var exitcode: c_int = 0;
        _ = c.SDL_WaitProcess(proc, true, &exitcode);
        c.SDL_DestroyProcess(proc);
    }
}

// ------------------------------------------------------------------- tests

const testing = std.testing;

test "an untouched ini round trips byte for byte" {
    const src =
        "# a comment\r\n[Graphics]\r\n# another\r\nWindowScale = 3\r\n\r\nLinearFiltering = 0\r\n";
    const path = "zig-cache-roundtrip.ini";
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
    const path = "zig-cache-edit.ini";
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
        .kind = .{ .choice = &.{ "a", "b", "c" } },
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

    const scratch = "zig-cache-shipped.ini";
    defer _ = fileio.remove(scratch);
    try ini.save(scratch);

    const back = try fileio.readWholeFile(testing.allocator, scratch);
    defer testing.allocator.free(back);
    try testing.expectEqualStrings(original, back);
}

test "the schema splits cleanly into the two menus" {
    // Everything before the FEATURES heading belongs to Settings, and
    // everything from it belongs to Features. If a section is ever added
    // after Features this silently puts it on the wrong screen, so check it.
    const settings = screenRange(.settings);
    const features = screenRange(.features);

    try testing.expect(settings.to > settings.from);
    try testing.expect(features.to > features.from);
    try testing.expectEqual(settings.to, features.from);
    try testing.expectEqual(kSettings.len, features.to);

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
        "UP/DOWN MOVE   ENTER SELECT",
        "B BUILD ASSETS   ESC QUIT",
        "UP/DOWN MOVE   LEFT/RIGHT CHANGE",
        "S SAVE   ESC BACK",
        "SETTINGS",
        "FEATURES",
        "NO ASSETS YET",
        "DRAG A .SFC ROM ONTO THIS WINDOW",
        "DRAG A .SFC ROM HERE FIRST",
        "US ROM VERIFIED - ASSETS BUILT",
        "WRONG REGION - NEEDS THE US ROM",
        "COULD NOT READ THAT FILE",
        "UNRECOGNISED ROM",
        "NOT A .SFC FILE",
        "BUILDING ASSETS...",
        "CHECKING ROM...",
        "UNSAVED CHANGES",
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
