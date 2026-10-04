//! Settings inside the game, behind Select.
//!
//! Select normally brings up a text box offering Continue Game or Save and
//! Quit. Here it slides this whole screen down instead, the way Start brings
//! the inventory down, with a first page of Continue, Save and Continue, and
//! Save and Quit, and the settings on the pages after it. The file select
//! screen's SETTINGS option opens the same screen without that first page
//! and without the slide.
//!
//! It's drawn in the style of the inventory: the same framed boxes, item
//! icons for tabs, hearts for switches, the dialogue font for the words. L
//! and R change page, Up and Down pick a setting, Left, Right and A change
//! it, and B saves zelda3.ini and goes back to the game.
//!
//! The last tab, Controls, maps the SNES pad's twelve buttons to keys and
//! gamepad buttons, with a line drawing of the pad to show which is which.
//!
//! The screen is drawn over each finished frame with game_gfx rather than
//! built in VRAM, and the game sits in its save menu underneath the whole time,
//! so nothing about the game's own display needs putting back afterwards.
//!
//! Settings that can change under a running game do so straight away. The rest
//! are saved and marked as taking effect next time.
const std = @import("std");
const vars = @import("variables.zig");
const config = @import("config.zig");
const menu = @import("menu.zig");
const rtl = @import("zelda_rtl_types.zig");
const zelda_rtl = @import("zelda_rtl.zig");
const messaging = @import("messaging.zig");
const main = @import("main.zig");
const gfx = @import("game_gfx.zig");
const hud = @import("hud_tables.zig");
const pad_art = @import("pad_art.zig");
const controls = @import("controls.zig");
const c = @import("sdl.zig").c;

/// Off while the game is being compared against the original, whose Select
/// button brings up its own text box.
pub var enabled = true;

const kJoypadH_B: u8 = 0x80;
const kJoypadH_Y: u8 = 0x40;
const kJoypadH_Select: u8 = 0x20;
const kJoypadH_Start: u8 = 0x10;
const kJoypadH_Up: u8 = 0x08;
const kJoypadH_Down: u8 = 0x04;
const kJoypadH_Left: u8 = 0x02;
const kJoypadH_Right: u8 = 0x01;
const kJoypadL_A: u8 = 0x80;
const kJoypadL_L: u8 = 0x20;
const kJoypadL_R: u8 = 0x10;

const alloc = std.heap.c_allocator;

// ------------------------------------------------------------- the settings

const Tab = struct {
    title: []const u8,
    /// The inventory icon on the tab, as ItemBoxGfx tiles.
    icon: [4]u16,
    first: usize,
    count: usize,
};

/// Every setting the start menu can change, grouped by its headings. Free
/// text such as the shader path has no business being cycled, so it stays
/// out.
fn editable(s: menu.Setting) bool {
    return !menu.isSection(s) and s.kind != .text;
}

/// The settings this screen shows: everything but the randomizer's, which
/// are chosen before a seed starts and mean nothing to the normal game.
const kShown = menu.kSettings[0..menu.kRandomizerStart];

const kIndex = blk: {
    var n: usize = 0;
    for (kShown) |s| {
        if (editable(s)) n += 1;
    }
    var list: [n]u16 = undefined;
    var i: usize = 0;
    for (kShown, 0..) |s, si| {
        if (editable(s)) {
            list[i] = si;
            i += 1;
        }
    }
    break :blk list;
};

/// Book of Mudora, Magic Mirror, Flute, Pegasus Boots.
const kTabIcons = [_][4]u16{
    .{ 0x3ca5, 0x3ca6, 0x3cd8, 0x3cd9 },
    .{ 0x2c62, 0x2c63, 0x2c72, 0x2c73 },
    .{ 0x2cd4, 0x2cd5, 0x2ce4, 0x2ce5 },
    .{ 0x3429, 0x342a, 0x342b, 0x342c },
};

/// The settings' own tabs, then Controls, which isn't a list of settings.
const kTabCount = kTabs.len + 1;
const kControlsTab = kTabs.len;
/// The Power Glove.
const kControlsIcon = hud.kHudItemGloves[1].v;

const kTabs = blk: {
    var tabs: [kTabIcons.len]Tab = undefined;
    var t: usize = 0;
    var at: usize = 0;
    for (kShown, 0..) |s, si| {
        if (!menu.isSection(s)) continue;
        var count: usize = 0;
        for (kShown[si + 1 ..]) |next| {
            if (menu.isSection(next)) break;
            if (editable(next)) count += 1;
        }
        tabs[t] = .{ .title = s.label, .icon = kTabIcons[t], .first = at, .count = count };
        at += count;
        t += 1;
    }
    if (t != tabs.len) @compileError("one icon per settings heading");
    break :blk tabs;
};

/// Settings that take hold in a running game once g_config has them. Anything
/// not here is read once at startup: the renderer, the audio device, the
/// window's aspect, and so on.
fn appliesLive(s: menu.Setting) bool {
    if (std.mem.eql(u8, s.section, "Features")) return true;
    const live = [_][2][]const u8{
        .{ "General", "Autosave" },
        .{ "General", "DisplayPerfInTitle" },
        .{ "General", "DisableFrameDelay" },
        .{ "General", "Rumble" },
        .{ "General", "WidescreenHud" },
        .{ "General", "WidescreenCamera" },
        .{ "Graphics", "Fullscreen" },
        .{ "Graphics", "NewRenderer" },
        .{ "Graphics", "NoSpriteLimits" },
        .{ "Graphics", "LinearFiltering" },
        .{ "Sound", "Volume" },
        .{ "Sound", "ResumeMSU" },
        .{ "Sound", "MSUFinishCues" },
    };
    for (live) |l| {
        if (std.mem.eql(u8, s.section, l[0]) and std.mem.eql(u8, s.key, l[1])) return true;
    }
    return false;
}

/// Puts a new value into the running game where it can go.
fn applyLive(s: menu.Setting, value: []const u8) void {
    if (!appliesLive(s)) return;
    if (!config.applySetting(s.section, s.key, value)) return;
    if (std.mem.eql(u8, s.section, "Features")) {
        // The game copies this into its RAM on the next frame it isn't
        // replaying, the same way the ini's features reach it at startup.
        zelda_rtl.g_wanted_zelda_features = config.g_config.features0;
    } else if (std.mem.eql(u8, s.section, "Graphics")) {
        main.applyDisplaySettings();
    } else if (std.mem.eql(u8, s.section, "Sound")) {
        main.applyVolume();
    }
}

// ------------------------------------------------------------------ the screen

var g_open = false;
/// Where the screen was opened from, which decides what closing it means.
var g_origin: enum { game, file_select } = .game;
var g_ini: ?menu.Ini = null;
var g_dirty = false;
var g_tab: usize = 0;
var g_row: usize = 0;
var g_top: usize = 0;
var g_frame: u32 = 0;
/// How long a direction has been held, for the key repeat.
var g_held: u32 = 0;
/// The details box for the selected setting is up.
var g_details = false;

/// Which page is showing. Opened from Select, page 0 is the pause page and
/// the settings tabs follow it; from the file select screen there is no pause
/// page and page 0 is the first tab.
var g_page: usize = 0;
/// The picked line on the pause page.
var g_pause_row: usize = 0;

/// Opened from Select, the screen comes down from the top of the screen and
/// goes back up, 8 pixels a frame like the inventory does.
var g_slide: enum { none, in, out } = .none;
var g_slide_y: i32 = 0;
const kSlideHeight = 224;
const kSlideStep = 8;
/// What to do once the screen has gone back up.
var g_after_slide: PauseChoice = .continue_game;

const PauseChoice = enum { continue_game, save_and_continue, save_and_quit };
const kPauseLabels = [_][]const u8{ "Continue", "Save and Continue", "Save and Quit" };

/// The Lamp, for the pause page's tab.
const kPauseIcon = hud.kHudItemTorch[1].v;

fn hasPausePage() bool {
    return g_origin == .game;
}

fn pageCount() usize {
    return kTabCount + @intFromBool(hasPausePage());
}

fn onPausePage() bool {
    return hasPausePage() and g_page == 0;
}

/// The settings tab on show, or the Controls tab, numbered as kTabs does.
/// Meaningless on the pause page.
fn currentTab() usize {
    return g_page - @intFromBool(hasPausePage());
}

const kVisibleRows = 7;

pub fn isOpen() bool {
    return g_open;
}

/// Select pressed in the game. True when the screen is opening, in which
/// case the caller puts the game in its save menu module, which runs
/// update() for as long as the screen is up; false leaves Select to the
/// game's own text box.
pub fn openFromSelect() bool {
    if (!enabled or !open(.game)) return false;
    g_page = 0;
    g_slide_y = -kSlideHeight;
    g_slide = .in;
    vars.sound_effect_2.* = 17;
    return true;
}

/// Opens the screen over the file select screen, which keeps running under it
/// and hands update() the pad while it's up.
pub fn openFromFileSelect() void {
    if (open(.file_select)) g_page = g_tab;
}

fn open(origin: @TypeOf(g_origin)) bool {
    releaseIni();
    g_ini = menu.Ini.load(alloc, "zelda3.ini") catch |err| {
        std.debug.print("Could not read zelda3.ini: {s}\n", .{@errorName(err)});
        return false;
    };
    gfx.loadHudTiles();
    g_origin = origin;
    g_open = true;
    g_details = false;
    g_dirty = false;
    g_slide = .none;
    g_slide_y = 0;
    g_pause_row = 0;
    g_row = 0;
    g_top = 0;
    g_held = 0;
    g_capture = null;
    g_note = "";
    return true;
}

fn settingAt(tab: usize, row: usize) u16 {
    return kIndex[kTabs[tab].first + row];
}

/// A direction held down steps once, waits, then repeats.
fn repeatStep(held: bool) bool {
    if (!held) {
        g_held = 0;
        return false;
    }
    g_held += 1;
    return g_held == 1 or (g_held > 16 and g_held % 4 == 0);
}

/// Runs in place of the save menu each frame the screen is up.
pub fn update() void {
    g_frame +%= 1;
    switch (g_slide) {
        .none => {},
        .in => {
            g_slide_y = @min(0, g_slide_y + kSlideStep);
            if (g_slide_y == 0) g_slide = .none;
            return;
        },
        .out => {
            g_slide_y -= kSlideStep;
            if (g_slide_y <= -kSlideHeight) finishClose();
            return;
        },
    }
    const pressed_h = vars.filtered_joypad_H.*;
    const pressed_l = vars.filtered_joypad_L.*;
    const held_h = vars.joypad1H_last.*;

    // The details box takes any button to put away, B included, so B there
    // means back to the list rather than out of the menu.
    if (g_note_frames > 0) {
        g_note_frames -= 1;
        if (g_note_frames == 0) g_note = "";
    }
    // Waiting for a key or button: the pad's presses are the answer, taken
    // by main before they got here, so none of them mean anything else.
    if (g_capture != null) {
        g_capture_frames += 1;
        if (g_capture_frames > kCaptureFrames) cancelCapture();
        return;
    }
    // Select put it up, so Select takes it down again, from any page.
    if (g_origin == .game and pressed_h & kJoypadH_Select != 0) return close(.continue_game);

    if (g_details) {
        if (pressed_h & (kJoypadH_B | kJoypadH_Y | kJoypadH_Start) != 0 or pressed_l & kJoypadL_A != 0) {
            g_details = false;
            vars.sound_effect_2.* = 32;
        }
        return;
    }
    if (pressed_h & kJoypadH_Y != 0 and !onPausePage() and currentTab() != kControlsTab) {
        g_details = true;
        vars.sound_effect_2.* = 32;
        return;
    }

    if (pressed_h & (kJoypadH_B | kJoypadH_Start) != 0) return close(.continue_game);

    if (pressed_l & (kJoypadL_L | kJoypadL_R) != 0) {
        const n = pageCount();
        g_page = if (pressed_l & kJoypadL_R != 0) (g_page + 1) % n else (g_page + n - 1) % n;
        g_row = 0;
        g_top = 0;
        vars.sound_effect_2.* = 32;
        return;
    }

    const dirs = held_h & (kJoypadH_Up | kJoypadH_Down | kJoypadH_Left | kJoypadH_Right);
    const step = repeatStep(dirs != 0);
    if (onPausePage()) return pauseUpdate(step, dirs, pressed_l);
    g_tab = currentTab();
    if (g_tab == kControlsTab) return controlsUpdate(step, dirs, pressed_l);
    const count = kTabs[g_tab].count;
    if (step and dirs & kJoypadH_Up != 0) {
        g_row = (g_row + count - 1) % count;
        vars.sound_effect_2.* = 32;
    } else if (step and dirs & kJoypadH_Down != 0) {
        g_row = (g_row + 1) % count;
        vars.sound_effect_2.* = 32;
    } else if (step and dirs & (kJoypadH_Left | kJoypadH_Right) != 0) {
        change(if (dirs & kJoypadH_Right != 0) 1 else -1);
    } else if (pressed_l & kJoypadL_A != 0) {
        change(1);
    }

    if (g_row < g_top) g_top = g_row;
    if (g_row >= g_top + kVisibleRows) g_top = g_row + 1 - kVisibleRows;
}

fn change(dir: i32) void {
    const ini = &g_ini.?;
    const si = settingAt(g_tab, g_row);
    const s = menu.kSettings[si];
    var buf: [64]u8 = undefined;
    const next = menu.cycle(alloc, &buf, s, ini.values[si] orelse "", dir) orelse return;
    ini.set(si, next) catch return;
    g_dirty = true;
    applyLive(s, ini.values[si].?);
    vars.sound_effect_1.* = 43;
}

fn pauseUpdate(step: bool, dirs: u8, pressed_l: u8) void {
    if (step and dirs & kJoypadH_Up != 0) {
        g_pause_row = (g_pause_row + kPauseLabels.len - 1) % kPauseLabels.len;
        vars.sound_effect_2.* = 32;
    } else if (step and dirs & kJoypadH_Down != 0) {
        g_pause_row = (g_pause_row + 1) % kPauseLabels.len;
        vars.sound_effect_2.* = 32;
    } else if (pressed_l & kJoypadL_A != 0) {
        // The chime the game's own Continue / Save and Quit box makes.
        vars.sound_effect_1.* = 43;
        const choice: PauseChoice = @fromBackingInt(@intCast(g_pause_row));
        if (choice == .save_and_continue) messaging.SaveGameInPlace();
        close(choice);
    }
}

/// Saves what changed and goes back where the screen was opened from: the
/// game, once the screen has gone back up, or the file select screen, which
/// never left.
fn close(choice: PauseChoice) void {
    if (g_ini) |*ini| {
        if (g_dirty) {
            ini.save("zelda3.ini") catch |err| std.debug.print("Could not write zelda3.ini: {s}\n", .{@errorName(err)});
            g_dirty = false;
        }
    }
    g_details = false;
    vars.sound_effect_2.* = 18;
    if (g_origin == .game) {
        // The page it was on is still drawn as it slides away, settings and
        // all, so they're kept until it's gone.
        g_after_slide = choice;
        g_slide = .out;
    } else {
        g_open = false;
        releaseIni();
    }
}

fn releaseIni() void {
    if (g_ini) |*ini| ini.deinit();
    g_ini = null;
}

/// The screen is all the way back up: do what was picked.
fn finishClose() void {
    g_open = false;
    g_slide = .none;
    releaseIni();
    switch (g_after_slide) {
        .continue_game, .save_and_continue => {
            vars.choice_in_multiselect_box.* = vars.choice_in_multiselect_box_bak.*;
            vars.main_module_index.* = vars.saved_module_for_menu.*;
            vars.submodule_index.* = 0;
        },
        // What the game's own box does on its second line.
        .save_and_quit => {
            vars.choice_in_multiselect_box.* = 1;
            vars.sound_effect_ambient.* = 15;
            vars.main_module_index.* = 23;
            vars.submodule_index.* = 1;
            vars.index_of_changable_dungeon_objs[0] = 0;
            vars.index_of_changable_dungeon_objs[1] = 0;
        },
    }
}

// ------------------------------------------------------------------- drawing

/// The HUD palette the boxes' frames are drawn in.
const kFramePalette: u16 = 3;

const kYellow = 0xf8d830;
const kDim = 0x9098a8;
const kRowHighlight = 0x182c58;
const kMeterOn = 0x48c848;
const kMeterOff = 0x303848;

/// The text box's own colors, from BG3 palette 6: the dark outline, the
/// white body, and a third the dialogue rarely uses. Read from CGRAM each
/// frame so the words match the Select menu's exactly. Selected and dimmed
/// text keep the outline and swap only the body.
var kTextNormal = [3]u32{ 0x000073, 0xffffff, 0xc60000 };
var kTextSelected = [3]u32{ 0x000073, kYellow, 0xc60000 };
var kTextDim = [3]u32{ 0x000073, kDim, 0xc60000 };

fn loadTextColors() void {
    const outline = gfx.cgramColor(25);
    const body = gfx.cgramColor(26);
    const third = gfx.cgramColor(27);
    kTextNormal = .{ outline, body, third };
    kTextSelected = .{ outline, kYellow, third };
    kTextDim = .{ outline, kDim, third };
}

/// Title case for the tab names, which the start menu keeps in capitals.
fn titleCase(out: []u8, s: []const u8) []const u8 {
    for (s, 0..) |ch, i| out[i] = if (i == 0) ch else std.ascii.toLower(ch);
    return out[0..s.len];
}

/// The font has no slash, colon or percent sign, so labels and values are
/// spelled with what it does have.
fn fontSafe(out: []u8, s: []const u8) []const u8 {
    var n: usize = 0;
    for (s) |ch| {
        const mapped: ?u8 = switch (ch) {
            '/', '_' => '-',
            ':' => 'x',
            '%' => null,
            else => ch,
        };
        if (mapped) |m| {
            if (n == out.len) break;
            out[n] = m;
            n += 1;
        }
    }
    return out[0..n];
}

/// Draws the screen over a finished frame, when it's open.
pub fn drawOver(pixels: [*]u8, pitch: usize, width: usize, height: usize, scale: usize) void {
    if (!g_open) return;
    const cv = gfx.Canvas{ .pixels = pixels, .pitch = pitch, .width = width, .height = height, .scale = scale, .oy = g_slide_y };
    loadTextColors();
    // In the game the menu sits straight over the world, the way the
    // inventory does. The file select screen keeps its darkened backdrop.
    if (g_origin == .file_select) cv.dim();
    drawTabs(cv);
    if (onPausePage()) {
        drawPause(cv);
    } else {
        g_tab = currentTab();
        if (g_details) drawDetails(cv) else if (g_tab == kControlsTab) drawControls(cv) else drawList(cv);
    }
    drawFooter(cv);
}

fn drawTabs(cv: gfx.Canvas) void {
    cv.box(8, 4, 30, 5, kFramePalette);
    // Spread across the same span however many there are, which keeps the
    // file select screen's five where they always were.
    const n = pageCount();
    const spacing: i32 = @intCast(176 / (n - 1));
    for (0..n) |page| {
        const x: i32 = 30 + @as(i32, @intCast(page)) * spacing;
        const offset = @intFromBool(hasPausePage());
        const icon = if (page < offset) kPauseIcon else if (page - offset < kTabs.len) kTabs[page - offset].icon else kControlsIcon;
        cv.icon(x, 16, icon);
        if (page == g_page and g_frame & 0x10 != 0) drawRing(cv, x, 16);
    }
    // Which button moves between them.
    _ = cv.text(14, 16, "L", kTextDim);
    _ = cv.text(236, 16, "R", kTextDim);
}

/// The inventory's cursor ring around a 16x16 icon, as Hud_DrawFlashingCircle
/// lays it out.
fn drawRing(cv: gfx.Canvas, x: i32, y: i32) void {
    const p: u16 = 7 << 10;
    const t = [_]struct { dx: i32, dy: i32, w: u16 }{
        .{ .dx = 0, .dy = -1, .w = p | 0x2061 },         .{ .dx = 1, .dy = -1, .w = p | 0x2061 | 0x4000 },
        .{ .dx = -1, .dy = 0, .w = p | 0x2070 },         .{ .dx = 2, .dy = 0, .w = p | 0x2070 | 0x4000 },
        .{ .dx = -1, .dy = 1, .w = p | 0xa070 },         .{ .dx = 2, .dy = 1, .w = p | 0xa070 | 0x4000 },
        .{ .dx = 0, .dy = 2, .w = p | 0xa061 },          .{ .dx = 1, .dy = 2, .w = p | 0xa061 | 0x4000 },
        .{ .dx = -1, .dy = -1, .w = p | 0x2060 },        .{ .dx = 2, .dy = -1, .w = p | 0x2060 | 0x4000 },
        .{ .dx = 2, .dy = 2, .w = p | 0x2060 | 0xc000 }, .{ .dx = -1, .dy = 2, .w = p | 0x2060 | 0x8000 },
    };
    for (t) |e| cv.tile(x + e.dx * 8, y + e.dy * 8, e.w);
}

fn drawList(cv: gfx.Canvas) void {
    const tab = kTabs[g_tab];
    cv.box(8, 46, 30, 18, kFramePalette);

    var title_buf: [16]u8 = undefined;
    _ = cv.text(24, 52, titleCase(&title_buf, tab.title), kTextSelected);
    if (!appliesLive(menu.kSettings[settingAt(g_tab, g_row)])) {
        const note = "Applies next start";
        _ = cv.text(222 - gfx.textWidth(note), 52, note, kTextDim);
    }

    const ini = &g_ini.?;
    const top: i32 = 70;
    var row: usize = g_top;
    while (row < @min(tab.count, g_top + kVisibleRows)) : (row += 1) {
        const y = top + @as(i32, @intCast(row - g_top)) * 16;
        const selected = row == g_row;
        if (selected) cv.fill(18, y - 1, 212, 16, kRowHighlight);
        const si = settingAt(g_tab, row);
        const s = menu.kSettings[si];
        var label_buf: [48]u8 = undefined;
        _ = cv.text(24, y, fontSafe(&label_buf, s.label), if (selected) kTextSelected else kTextNormal);
        drawValue(cv, 222, y, s, ini.values[si] orelse "", selected);
    }

    // More above or below, pointed out with the font's own arrows in a column
    // of their own at the right.
    if (g_top > 0) _ = cv.text(232, 70, "[Up]", kTextDim);
    if (g_top + kVisibleRows < tab.count) _ = cv.text(232, 166, "[Down]", kTextDim);
}

/// The value at the right of a row, right-aligned on `right`.
fn drawValue(cv: gfx.Canvas, right: i32, y: i32, s: menu.Setting, value: []const u8, selected: bool) void {
    const colors = if (selected) kTextSelected else kTextNormal;
    const v = std.mem.trim(u8, value, " \t");
    switch (s.kind) {
        .toggle => {
            // A full heart for on, an empty one for off.
            const on = std.mem.eql(u8, v, "1");
            const word: u16 = if (on) 0x24a0 else 0x24a2;
            const label = if (on) "On" else "Off";
            cv.tile(right - 8, y + 4, word);
            _ = cv.text(right - 12 - gfx.textWidth(label), y, label, colors);
        },
        .number => |n| {
            // A meter like the magic bar, then the number.
            const num = std.fmt.parseInt(i32, menu.splitSuffix(v, n.suffix), 10) catch n.min;
            var digits_buf: [8]u8 = undefined;
            const digits = std.fmt.bufPrint(&digits_buf, "{d}", .{num}) catch "";
            _ = cv.text(right - gfx.textWidth(digits), y, digits, colors);
            const segments: i32 = 10;
            const range = @max(1, n.max - n.min);
            const filled = @divTrunc((num - n.min) * segments + @divTrunc(range, 2), range);
            const meter_right = right - 24;
            var i: i32 = 0;
            while (i < segments) : (i += 1) {
                const x = meter_right - (segments - i) * 5;
                cv.fill(x, y + 4, 4, 8, if (i < filled) kMeterOn else kMeterOff);
            }
        },
        else => {
            var shown_buf: [48]u8 = undefined;
            var safe_buf: [48]u8 = undefined;
            const shown = fontSafe(&safe_buf, menu.displayValue(&shown_buf, s, v));
            const w = gfx.textWidth(shown);
            if (selected) {
                _ = cv.text(right - w - 10, y, "[Left]", kTextDim);
                _ = cv.text(right - w - 2, y, shown, colors);
                _ = cv.text(right, y, "[Right]", kTextDim);
            } else {
                _ = cv.text(right - w, y, shown, colors);
            }
        },
    }
}

fn drawPause(cv: gfx.Canvas) void {
    cv.box(8, 46, 30, 18, kFramePalette);
    _ = cv.text(24, 52, "Paused", kTextSelected);
    for (kPauseLabels, 0..) |label, i| {
        const y: i32 = 86 + @as(i32, @intCast(i)) * 24;
        const selected = i == g_pause_row;
        if (selected) cv.fill(18, y - 1, 212, 16, kRowHighlight);
        _ = cv.text(124 - @divTrunc(gfx.textWidth(label), 2), y, label, if (selected) kTextSelected else kTextNormal);
    }
}

fn drawFooter(cv: gfx.Canvas) void {
    const hint = if (g_note.len != 0)
        g_note
    else if (onPausePage())
        "[Up][Down] Choose  [A] OK  L R Settings"
    else if (g_capture != null)
        "Press a key or a button, or Esc to cancel"
    else if (g_details)
        "[B] Back"
    else if (currentTab() == kControlsTab)
        "[Up][Down] Choose  [A] Change  [B] Done"
    else
        "[Up][Down] Choose  [Left][Right] Change  [Y] Info  [B] Done";
    cv.band(192, 24, 0x000000);
    _ = cv.text(128 - @divTrunc(gfx.textWidth(hint), 2), 198, hint, kTextDim);
}

/// The selected setting explained: what it does, whether it changes the game
/// now or at the next start, and what it's set to.
fn drawDetails(cv: gfx.Canvas) void {
    cv.box(8, 46, 30, 18, kFramePalette);
    const si = settingAt(g_tab, g_row);
    const s = menu.kSettings[si];
    var label_buf: [48]u8 = undefined;
    _ = cv.text(24, 52, fontSafe(&label_buf, s.label), kTextSelected);

    var y: i32 = 72;
    var lines = WordWrap{ .text = menu.describe(s), .width = 208 };
    while (lines.next()) |line| : (y += 16) {
        if (y > 150) break;
        _ = cv.text(24, y, line, kTextNormal);
    }

    const when = if (appliesLive(s)) "Changes right away." else "Takes effect the next time you start.";
    _ = cv.text(24, 168, when, kTextDim);
}

/// Splits text into lines no wider than `width` in the dialogue font.
const WordWrap = struct {
    text: []const u8,
    width: i32,
    at: usize = 0,

    fn next(self: *WordWrap) ?[]const u8 {
        while (self.at < self.text.len and self.text[self.at] == ' ') self.at += 1;
        if (self.at >= self.text.len) return null;
        const start = self.at;
        var end = start;
        var i = start;
        while (i <= self.text.len) : (i += 1) {
            if (i == self.text.len or self.text[i] == ' ') {
                if (gfx.textWidth(self.text[start..i]) > self.width and end > start) break;
                end = i;
                if (i == self.text.len) break;
            }
        }
        if (end == start) end = self.text.len;
        self.at = end;
        return self.text[start..end];
    }
};

// ---------------------------------------------------------------- controls

/// The SNES pad's buttons, in the order the Controls lines list them. The
/// font has pictures for most; L and R get letters.
const kControlLabels = [12][]const u8{ "[Up]", "[Down]", "[Left]", "[Right]", "Select", "Start", "[A]", "[B]", "[X]", "[Y]", "L", "R" };
const kResetRow = kControlLabels.len;
const kControlRows = kControlLabels.len + 1;
const kControlsVisible = 4;
/// Five seconds to press something before the question goes away.
const kCaptureFrames = 300;

/// The row waiting for a key or button, when one is.
var g_capture: ?usize = null;
var g_capture_frames: u32 = 0;
/// A line for the footer in place of the hints, for a moment.
var g_note: []const u8 = "";
var g_note_frames: u32 = 0;

fn showNote(msg: []const u8) void {
    g_note = msg;
    g_note_frames = 120;
}

/// Whether main should hand this screen the next key or button press.
pub fn capturing() bool {
    return g_open and g_capture != null;
}

fn cancelCapture() void {
    g_capture = null;
    showNote("Nothing changed");
    vars.sound_effect_2.* = 60;
}

/// A key pressed while waiting. Escape backs out.
pub fn captureKey(code: u32) void {
    if (g_capture == null) return;
    if (code == c.SDLK_ESCAPE) return cancelCapture();
    const name = std.mem.span(c.SDL_GetKeyName(code));
    if (name.len == 0) return;
    finishCapture(.keyboard, name);
}

/// A gamepad button pressed while waiting, as main numbers them.
pub fn captureButton(button: c_int) void {
    if (g_capture == null) return;
    const name = config.gamepadButtonName(button);
    if (name.len == 0) return;
    finishCapture(.gamepad, name);
}

fn finishCapture(device: controls.Device, name: []const u8) void {
    const row = g_capture.?;
    g_capture = null;
    if (device == .keyboard and controls.keyTaken(&g_ini.?, name, true)) {
        showNote("That key already does something else");
        vars.sound_effect_2.* = 60;
        return;
    }
    controls.assign(&g_ini.?, device, row, name, true) catch return;
    g_dirty = true;
    vars.sound_effect_1.* = 43;
}

fn controlsUpdate(step: bool, dirs: u8, pressed_l: u8) void {
    if (step and dirs & kJoypadH_Up != 0) {
        g_row = (g_row + kControlRows - 1) % kControlRows;
        vars.sound_effect_2.* = 32;
    } else if (step and dirs & kJoypadH_Down != 0) {
        g_row = (g_row + 1) % kControlRows;
        vars.sound_effect_2.* = 32;
    } else if (pressed_l & kJoypadL_A != 0) {
        if (g_row == kResetRow) {
            controls.reset(&g_ini.?, true) catch return;
            g_dirty = true;
            showNote("Back to the defaults");
            vars.sound_effect_1.* = 43;
        } else {
            g_capture = g_row;
            g_capture_frames = 0;
            g_note = "";
            vars.sound_effect_2.* = 32;
        }
    }
    if (g_row < g_top) g_top = g_row;
    if (g_row >= g_top + kControlsVisible) g_top = g_row + 1 - kControlsVisible;
}

const kColKey: i32 = 80;
const kColPad: i32 = 160;
const kRowsTop: i32 = 118;

fn drawControls(cv: gfx.Canvas) void {
    cv.box(8, 46, 30, 18, kFramePalette);
    _ = cv.text(24, 52, "Controls", kTextSelected);

    const blink = g_frame & 0x10 != 0;
    const lit: ?usize = if (g_row < 12 and (blink or g_capture != null)) g_row else null;
    drawPad(cv, kPadArtX, kPadArtY, lit);

    _ = cv.text(kColKey, 102, "Keyboard", kTextDim);
    _ = cv.text(kColPad, 102, "Controller", kTextDim);

    const keys = controls.current(&g_ini.?, .keyboard);
    const pads = controls.current(&g_ini.?, .gamepad);
    var row = g_top;
    while (row < @min(kControlRows, g_top + kControlsVisible)) : (row += 1) {
        const y = kRowsTop + @as(i32, @intCast(row - g_top)) * 16;
        const selected = row == g_row;
        const colors = if (selected) kTextSelected else kTextNormal;
        if (selected) cv.fill(18, y - 1, 212, 16, kRowHighlight);
        if (row == kResetRow) {
            const label = "Reset all to defaults";
            _ = cv.text(124 - @divTrunc(gfx.textWidth(label), 2), y, label, colors);
            continue;
        }
        _ = cv.text(24, y, kControlLabels[row], colors);
        if (selected and g_capture != null) {
            _ = cv.text(kColKey, y, "Press a key or a button", kTextSelected);
            continue;
        }
        var kb: [48]u8 = undefined;
        var ks: [48]u8 = undefined;
        _ = cv.text(kColKey, y, fontSafe(&ks, controls.keyLabel(&kb, keys.get(row))), colors);
        var pb: [48]u8 = undefined;
        _ = cv.text(kColPad, y, fontSafe(&pb, controls.padLabel(pads.get(row))), colors);
    }
    if (g_top > 0) _ = cv.text(232, kRowsTop, "[Up]", kTextDim);
    if (g_top + kControlsVisible < kControlRows) _ = cv.text(232, kRowsTop + 48, "[Down]", kTextDim);
}

// The pad drawing, in game pixels just under the tab's title.
const kPadArtW = pad_art.kWidth;
const kPadArtH = pad_art.kHeight;
const kPadArtX: i32 = 128 - kPadArtW / 2;
const kPadArtY: i32 = 57;

fn drawPad(cv: gfx.Canvas, ox: i32, oy: i32, lit: ?usize) void {
    const Ctx = struct {
        cv: gfx.Canvas,
        ox: i32,
        oy: i32,
        fn put(p: *const anyopaque, x: i32, y: i32, rgb: u32) void {
            const self: *const @This() = @ptrCast(@alignCast(p));
            self.cv.fill(self.ox + x, self.oy + y, 1, 1, rgb);
        }
    };
    const ctx = Ctx{ .cv = cv, .ox = ox, .oy = oy };
    pad_art.draw(.{ .ctx = &ctx, .putFn = Ctx.put }, lit, kYellow);
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

test "the pause page's words are all in the font" {
    for (kPauseLabels ++ [_][]const u8{ "Paused", "OK", "Settings" }) |text| {
        for (text) |ch| try testing.expect(gfx.glyphIndex(&.{ch}) != null);
    }
}

test "the tabs fit the box with and without the pause page" {
    for ([_]usize{ kTabCount, kTabCount + 1 }) |n| {
        const spacing = 176 / (n - 1);
        try testing.expect(30 + (n - 1) * spacing + 16 <= 232);
    }
    // The file select screen's tabs stay where they were.
    try testing.expectEqual(@as(usize, 44), 176 / (kTabCount - 1));
}

test "every editable setting sits on exactly one tab" {
    var total: usize = 0;
    for (kTabs) |t| total += t.count;
    try testing.expectEqual(kIndex.len, total);
    for (kTabs, 0..) |t, ti| {
        for (0..t.count) |r| try testing.expect(editable(menu.kSettings[settingAt(ti, r)]));
    }
}

test "every setting has a description the font can draw" {
    for (kIndex) |si| {
        const s = menu.kSettings[si];
        const d = menu.describe(s);
        if (d.len == 0) {
            std.debug.print("no description for {s}\n", .{s.key});
            return error.MissingDescription;
        }
        for (d) |ch| try testing.expect(gfx.glyphIndex(&.{ch}) != null);
    }
}

test "labels and values only use what the font can draw" {
    for (kIndex) |si| {
        const s = menu.kSettings[si];
        var buf: [48]u8 = undefined;
        for (fontSafe(&buf, s.label)) |ch| try testing.expect(gfx.glyphIndex(&.{ch}) != null);
        if (s.kind == .choice) {
            for (s.kind.choice.values) |v| {
                var shown: [48]u8 = undefined;
                for (fontSafe(&buf, menu.displayValue(&shown, s, v))) |ch|
                    try testing.expect(gfx.glyphIndex(&.{ch}) != null);
            }
        }
    }
}

test "the Controls tab's words are all in the font" {
    for (kControlLabels) |label| {
        var it = std.mem.tokenizeScalar(u8, label, ' ');
        while (it.next()) |_| {}
        try testing.expect(gfx.glyphIndex(label) != null or for (label) |ch| {
            if (gfx.glyphIndex(&.{ch}) == null) break false;
        } else true);
    }
    for ([_][]const u8{ "Controls", "Keyboard", "Controller", "Reset all to defaults", "Press a key or a button", "Press a key or a button, or Esc to cancel", "Nothing changed", "That key already does something else", "Back to the defaults" }) |text| {
        for (text) |ch| try testing.expect(gfx.glyphIndex(&.{ch}) != null);
    }
}

test "the pad drawing fits between the title and the list" {
    try testing.expect(kPadArtX >= 16 and kPadArtX + kPadArtW <= 240);
    // L and R stick up a few pixels past the drawing's top, and the column
    // headings sit under its bottom.
    try testing.expect(kPadArtY - pad_art.kShoulderRise >= 52);
    try testing.expect(kPadArtY + kPadArtH <= 102);
    try testing.expect(kRowsTop + 16 * kControlsVisible <= 46 + 18 * 8 - 8);
}
