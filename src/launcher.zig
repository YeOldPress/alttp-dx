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
    var buf: [256]u8 = undefined;
    const n = @min(text.len, buf.len - 1);
    @memcpy(buf[0..n], text[0..n]);
    buf[n] = 0;
    setColor(r, col);
    _ = c.SDL_SetRenderScale(r, kScale, kScale);
    _ = c.SDL_RenderDebugText(r, x / kScale, y / kScale, @ptrCast(&buf));
    _ = c.SDL_SetRenderScale(r, 1, 1);
}

// --------------------------------------------------------------------- main

fn isSection(s: Setting) bool {
    return std.mem.eql(u8, s.section, kSectionMark);
}

fn firstSelectable() usize {
    for (kSettings, 0..) |s, i| if (!isSection(s)) return i;
    return 0;
}

/// Draws the whole screen. Split out of the loop so that the slow paths -
/// building assets - can put a frame up before they block.
fn drawScreen(
    renderer: *c.SDL_Renderer,
    ini: *const Ini,
    cursor: usize,
    top: usize,
    status: []const u8,
    dirty: bool,
    have_assets: bool,
) void {
    fillRect(renderer, 0, 0, kWindowW, kWindowH, kColorBg);
    drawFrame(renderer, 16, 16, kWindowW - 32, kWindowH - 32);

    drawText(renderer, 40, 36, kColorSelect, "THE LEGEND OF ZELDA");
    drawText(renderer, 40 + kCell * 20, 36, kColorTextDim, "LAUNCHER");

    var y: f32 = 36 + kRowH + 8;
    var i = top;
    while (i < kSettings.len and i < top + kVisibleRows) : (i += 1) {
        const s = kSettings[i];
        if (isSection(s)) {
            drawText(renderer, 40, y, kColorSection, s.label);
        } else {
            if (i == cursor) {
                fillRect(renderer, 32, y - 3, kWindowW - 64, kRowH, kColorRowHi);
                drawText(renderer, 36, y, kColorSelect, ">");
            }
            drawText(renderer, 56, y, if (i == cursor) kColorSelect else kColorText, s.label);
            var vbuf: [64]u8 = undefined;
            const shown = displayValue(&vbuf, s, ini.values[i] orelse "(missing)");
            const dim = s.kind == .text;
            drawText(renderer, 400, y, if (dim) kColorTextDim else kColorValue, shown);
        }
        y += kRowH;
    }

    const footer_y: f32 = kWindowH - 32 - kRowH * 2 - 6;
    drawText(renderer, 40, footer_y, kColorTextDim, "ARROWS MOVE/CHANGE   S SAVE");
    drawText(renderer, 40, footer_y + kRowH, kColorTextDim, "ENTER PLAY   B ASSETS   ESC QUIT");

    // One line above the footer, in order of what the player most needs to
    // know: what just happened, then that the game cannot start yet, then
    // that there are edits worth saving.
    if (status.len != 0)
        drawText(renderer, 40, footer_y - kRowH, kColorSection, status)
    else if (!have_assets)
        drawText(renderer, 40, footer_y - kRowH, kColorSelect, "NO ASSETS - PRESS B TO BUILD")
    else if (dirty)
        drawText(renderer, 40, footer_y - kRowH, kColorSelect, "UNSAVED CHANGES");

    _ = c.SDL_RenderPresent(renderer);
}

/// Builds zelda3_assets.dat from the ROM, replacing what the Python resource
/// tool did. Returns a message for the status line either way.
fn buildAssets(alloc: std.mem.Allocator) []const u8 {
    if (!fileio.exists(kRomPath)) return "NEED " ++ kRomPath ++ " TO BUILD ASSETS";

    var rom = rom_mod.Rom.load(alloc, kRomPath) catch return "COULD NOT READ ROM";
    defer rom.deinit();
    if (rom.language != .us) return "ROM IS NOT THE US RELEASE";

    const data = asset_all.buildFile(alloc, rom) catch return "COULD NOT BUILD ASSETS";
    defer alloc.free(data);

    fileio.writeWholeFile(kAssetsPath, data) catch return "COULD NOT WRITE ASSETS";
    return "ASSETS BUILT";
}

pub fn main(init: std.process.Init.Minimal) !void {
    const alloc = std.heap.c_allocator;

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

    var cursor: usize = firstSelectable();
    var top: usize = 0;
    var dirty = false;
    var launch = false;
    var status: []const u8 = "";
    var have_assets = fileio.exists(kAssetsPath);
    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        while (c.SDL_PollEvent(&event)) {
            var move: i32 = 0;
            var adjust: i32 = 0;
            var confirm = false;

            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_KEY_DOWN => switch (event.key.key) {
                    c.SDLK_ESCAPE => running = false,
                    c.SDLK_UP => move = -1,
                    c.SDLK_DOWN => move = 1,
                    c.SDLK_LEFT => adjust = -1,
                    c.SDLK_RIGHT, c.SDLK_SPACE => adjust = 1,
                    c.SDLK_RETURN => confirm = true,
                    c.SDLK_B => {
                        // Drawing a frame first, so the window does not just
                        // freeze for the second or two this takes.
                        status = "BUILDING ASSETS...";
                        drawScreen(renderer, &ini, cursor, top, status, dirty, have_assets);
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
                    c.SDL_GAMEPAD_BUTTON_SOUTH => adjust = 1,
                    c.SDL_GAMEPAD_BUTTON_START => confirm = true,
                    c.SDL_GAMEPAD_BUTTON_EAST => running = false,
                    else => {},
                },
                else => {},
            }

            if (move != 0) {
                // Step over the section headings.
                var at: i32 = @intCast(cursor);
                while (true) {
                    at += move;
                    if (at < 0) at = @as(i32, @intCast(kSettings.len)) - 1;
                    if (at >= @as(i32, @intCast(kSettings.len))) at = 0;
                    if (!isSection(kSettings[@intCast(at)])) break;
                }
                cursor = @intCast(at);
                status = "";
            }

            if (adjust != 0) {
                var buf: [64]u8 = undefined;
                const cur = ini.values[cursor] orelse "";
                if (cycle(alloc, &buf, kSettings[cursor], cur, adjust)) |next| {
                    try ini.set(cursor, next);
                    dirty = true;
                    status = "";
                }
            }

            if (confirm) {
                ini.save("zelda3.ini") catch |err| {
                    std.debug.print("Could not write zelda3.ini: {s}\n", .{@errorName(err)});
                    status = "COULD NOT SAVE";
                    continue;
                };
                dirty = false;

                // The game cannot start without its assets, so build them
                // rather than making the player find out by watching it fail.
                if (!have_assets) {
                    status = "BUILDING ASSETS...";
                    drawScreen(renderer, &ini, cursor, top, status, dirty, have_assets);
                    status = buildAssets(alloc);
                    have_assets = fileio.exists(kAssetsPath);
                    if (!have_assets) continue;
                }

                launch = true;
                running = false;
            }
        }

        // Keep the cursor inside the visible window.
        if (cursor < top) top = cursor;
        if (cursor >= top + kVisibleRows) top = cursor - kVisibleRows + 1;

        drawScreen(renderer, &ini, cursor, top, status, dirty, have_assets);
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
