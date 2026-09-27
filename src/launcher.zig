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
const builtin = @import("builtin");
const fileio = @import("fileio.zig");
const rom_mod = @import("rom.zig");
const asset_all = @import("asset_all.zig");

const c = @cImport({
    // translate-c cannot parse arm_neon.h, which SDL pulls in on ARM targets.
    @cDefine("SDL_DISABLE_NEON", "1");
    // Optimized builds define _FORTIFY_SOURCE, which makes mingw's headers
    // inline checked wrappers that translate-c turns into unused locals.
    @cUndef("_FORTIFY_SOURCE");
    @cInclude("SDL3/SDL.h");
});

/// The game binary, expected next to the launcher. Spelled relative on
/// purpose: the launcher has already moved into its own directory, and a
/// bare name would let PATH answer instead.
const kGameExe = if (builtin.os.tag == .windows) ".\\zelda3.exe" else "./zelda3";
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

// ---------------------------------------------------------------- settings

/// How a setting's value is presented and cycled.
/// A fixed set of values, and optionally what to call them.
///
/// The file's spelling is not always meant for people to read - Fullscreen is
/// stored as 0, 1 or 2 - so `labels` gives each value a name to show instead.
/// Leave it empty and the value is shown as written.
const Choice = struct {
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

const Kind = union(enum) {
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
    .{ .section = "General", .key = "ExtendedAspectRatio", .label = "Aspect Ratio", .kind = .{ .choice = .{ .values = &.{ "4:3", "16:9", "16:10", "18:9" } } } },
    .{ .section = "General", .key = "DisableFrameDelay", .label = "Disable Frame Delay", .kind = .toggle },

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
fn displayValue(buf: []u8, s: Setting, value: []const u8) []const u8 {
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

fn isSection(s: Setting) bool {
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

const kMainItems = [_][]const u8{ "Settings", "Features", "Save Settings", "Build Assets", "Launch" };
const kMainSave = 2;
const kMainBuild = 3;
const kMainLaunch = 4;

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
    /// Present and matching the file the Python tool builds from a US ROM.
    verified,
    /// Present, but not a file this build of the tool produces. Usually an
    /// older .dat; the game may or may not accept it.
    unrecognised,

    fn line(self: AssetState) []const u8 {
        return switch (self) {
            .missing => "ASSETS MISSING",
            .verified => "ASSETS VERIFIED",
            .unrecognised => "ASSETS PRESENT - CHECKSUM DIFFERS",
        };
    }

    fn colour(self: AssetState) Rgb {
        return switch (self) {
            .missing => kColorWarn,
            .verified => kColorOk,
            .unrecognised => kColorWarn,
        };
    }
};

/// Hashes zelda3_assets.dat and compares it with the digest the asset
/// builder is known to produce. Reading 668K costs about a millisecond, so
/// this runs at startup and after every build rather than being cached and
/// going stale.
fn checkAssets(alloc: std.mem.Allocator) AssetState {
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
    return if (std.mem.eql(u8, &hex, asset_all.kReferenceDigest)) .verified else .unrecognised;
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
};

fn listIndex(sc: Screen) usize {
    return if (sc == .features) 1 else 0;
}

/// Gathers the loop's scattered state into what drawing needs.
fn viewOf(
    screen: Screen,
    main_cursor: usize,
    list_cursor: [2]usize,
    list_top: [2]usize,
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
        .cursor = if (screen == .main) main_cursor else list_cursor[li],
        .top = list_top[li],
        .status = status,
        .dirty = dirty,
        .assets = assets,
    };
}

fn drawScreen(renderer: *c.SDL_Renderer, ini: *const Ini, v: View) void {
    fillRect(renderer, 0, 0, kWindowW, kWindowH, kColorBg);
    drawFrame(renderer, 16, 16, kWindowW - 32, kWindowH - 32);

    drawHeader(renderer, v.screen);

    switch (v.screen) {
        .main => drawMain(renderer, v),
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
        drawTextCentered(renderer, cx, 36 + kRowH * 2, kColorTextDim, "LAUNCHER", kScale);
        fillRect(renderer, 60, 36 + kRowH * 3 + 6, kWindowW - 120, 2, kColorFrame);
        return;
    }

    const name = if (screen == .settings) "SETTINGS" else "FEATURES";
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

// The menu's group of entries, then the Launch button below them.
const kEntryY: f32 = 124;
const kEntryGap: f32 = 32;
const kLaunchY: f32 = 250;
const kLaunchScale: f32 = kScale * 2;
const kListStartY: f32 = 36 + kRowH + 14;

fn mainEntryRect(i: usize) Rect {
    if (i == kMainLaunch) return launchRect();
    // Wider than the highlight, so aiming at a short word still lands.
    const y = kEntryY + kEntryGap * @as(f32, @floatFromInt(i));
    return .{ .x = kWindowW / 2 - 150, .y = y - 8, .w = 300, .h = kRowH + 10 };
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

/// Which row of a list sits under a point, as an index into kSettings.
fn listRowAt(v: View, py: f32) ?usize {
    const range = screenRange(v.screen);
    var i = v.top;
    var y: f32 = kListStartY;
    while (i < range.to and i < v.top + kVisibleRows) : (i += 1) {
        if (py >= y - 3 and py < y - 3 + kRowH and !isSection(kSettings[i])) return i;
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
            fillRect(renderer, cx - w / 2 - 20, y - 8, w + 40, kRowH + 10, kColorRowHi);
            drawTextScaled(renderer, cx - w / 2 - 36, y, kColorSelect, ">", kScale);
        }
        drawTextCentered(renderer, cx, y, if (selected) kColorSelect else kColorText, label, kScale);
    }

    // Launch: a button, centred, big enough to be the obvious thing to press.
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
    const state_y = box_y + box_h + 18;

    drawTextCentered(renderer, cx, state_y, v.assets.colour(), v.assets.line(), kScale);

    if (v.assets == .missing) {
        drawTextCentered(renderer, cx, state_y + kRowH, kColorTextDim, "DRAG A .SFC ROM ONTO THIS WINDOW", kScale);
    }
}

fn drawList(renderer: *c.SDL_Renderer, ini: *const Ini, v: View) void {
    const range = screenRange(v.screen);
    var y: f32 = kListStartY;
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
            drawTextCentered(renderer, cx, box.y + 34, kColorSelect, "LEAVE THE LAUNCHER?", kScale);
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

/// Prints what SDL makes of every pad plugged in: its name, and which label
/// is printed on each face button. Face buttons are routed by label, so this
/// is the thing to look at when a button does the wrong job.
fn reportPads() void {
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
            std.debug.print("  {s:<6} labelled {s:<8} does {s}\n", .{ b.pos, printed, does });
        }
    }
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
    // iterateAllocator rather than iterate: on Windows the command line
    // arrives as one string that has to be split and decoded, so the
    // plain iterator is a compile error there. Elsewhere the allocator
    // goes unused.
    var args = try init.args.iterateAllocator(alloc);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--build-assets")) {
            const msg = buildAssets(alloc);
            std.debug.print("{s}\n", .{msg});
            if (!fileio.exists(kAssetsPath)) return error.BuildFailed;
            return;
        }
        if (std.mem.eql(u8, a, "--pad-info")) {
            reportPads();
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

    configureJoysticks();
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD)) {
        std.debug.print("Failed to init SDL: {s}\n", .{c.SDL_GetError()});
        return error.SdlInit;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("The Legend of Zelda: A Link to the Past - Launcher", kWindowW, kWindowH, 0) orelse {
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
    var list_cursor = [_]usize{ firstSelectable(0, kFeaturesStart), firstSelectable(kFeaturesStart, kSettings.len) };
    var list_top = [_]usize{ 0, kFeaturesStart };
    var dirty = false;
    var launch = false;
    var status: []const u8 = "";
    var assets = checkAssets(alloc);
    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        const now = c.SDL_GetTicks();
        var confirm = false;
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
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_GAMEPAD_ADDED => pads.open(event.gdevice.which),
                c.SDL_EVENT_GAMEPAD_REMOVED => pads.close(event.gdevice.which),

                // A ROM dropped on the window is the quickest path from a
                // fresh checkout to a playable game.
                c.SDL_EVENT_DROP_FILE => {
                    if (event.drop.data) |path| {
                        status = "CHECKING ROM...";
                        drawScreen(renderer, &ini, viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice));
                        status = buildAssetsFromDrop(alloc, path);
                        assets = checkAssets(alloc);
                        // A drop that worked answers the question; one that
                        // did not leaves it up so another can be tried.
                        if (assets == .verified) modal = .none;
                    }
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
                        c.SDLK_B => build = true,
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
                        c.SDL_GAMEPAD_BUTTON_START => confirm = true,
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
                    kMainSave => save = true,
                    kMainBuild => {
                        modal = .rom;
                        status = "";
                    },
                    else => {
                        ini.save("zelda3.ini") catch |err| {
                            std.debug.print("Could not write zelda3.ini: {s}\n", .{@errorName(err)});
                            status = "COULD NOT SAVE";
                            continue;
                        };
                        dirty = false;

                        // The game cannot start without its assets, so ask
                        // for a ROM rather than letting it fail.
                        if (assets == .missing) {
                            modal = .rom;
                        } else {
                            launch = true;
                            running = false;
                        }
                    },
                }
            }
        } else {
            if (back) {
                screen = .main;
                status = "";
            }

            // The two lists behave the same; only their range differs.
            const li = listIndex(screen);
            const range = screenRange(screen);

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

            // Keep the cursor inside the visible window.
            if (list_cursor[li] < list_top[li]) list_top[li] = list_cursor[li];
            if (list_cursor[li] >= list_top[li] + kVisibleRows)
                list_top[li] = list_cursor[li] - kVisibleRows + 1;
            if (list_top[li] < range.from) list_top[li] = range.from;
        }

        if (build) {
            // Draw a frame first, so the window does not simply freeze for
            // the second or two this takes.
            status = "BUILDING ASSETS...";
            drawScreen(renderer, &ini, viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice));
            status = buildAssets(alloc);
            assets = checkAssets(alloc);

            // Enter on Launch with no assets builds them and then goes.
            if (main_cursor == kMainLaunch and screen == .main and assets != .missing) {
                launch = true;
                running = false;
            }
        }

        drawScreen(renderer, &ini, viewOf(screen, main_cursor, list_cursor, list_top, status, dirty, assets, modal, quit_choice));
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
        // Footers.
        "SELECT A/ENTER   SAVE X/S",
        "QUIT B/ESC",
        "CHANGE  LEFT/RIGHT OR A",
        "SAVE X/S   BACK B/ESC",
        // Headers.
        "THE LEGEND OF ZELDA",
        "A LINK TO THE PAST",
        "LAUNCHER",
        "LEFT/RIGHT CHOOSE",
        "A/ENTER CONFIRM   B/ESC CANCEL",
        "DROP A FILE ON THE WINDOW",
        "B/ESC CANCEL",
        "LEAVE THE LAUNCHER?",
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
        "UNRECOGNISED ROM",
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
    // present but unrecognised rather than waved through - a stale .dat loads
    // and then misbehaves in ways that look like game bugs.
    const scratch = "zelda3_assets_checktest.dat";
    try fileio.writeWholeFile(scratch, "not an asset file");
    defer _ = fileio.remove(scratch);
    try testing.expectEqual(AssetState.unrecognised, checkAssetsAt(alloc, scratch));

    // An empty file is not a crash.
    const empty = "zelda3_assets_emptytest.dat";
    try fileio.writeWholeFile(empty, "");
    defer _ = fileio.remove(empty);
    try testing.expectEqual(AssetState.unrecognised, checkAssetsAt(alloc, empty));

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

    const scratch = "zelda3_assets_corrupttest.dat";
    try fileio.writeWholeFile(scratch, copy);
    defer _ = fileio.remove(scratch);
    try testing.expectEqual(AssetState.unrecognised, checkAssetsAt(alloc, scratch));
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
