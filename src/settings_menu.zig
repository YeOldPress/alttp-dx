//! Settings inside the game, behind Select.
//!
//! Select normally offers Continue Game or Save and Quit. This adds Settings
//! as a third choice, and the file select screen gets a SETTINGS option too;
//! either opens a full settings screen in the style of the
//! inventory: the same framed boxes, item icons for tabs, hearts for switches,
//! the dialogue font for the words. L and R change tab, Up and Down pick a
//! setting, Left, Right and A change it, and B saves zelda3.ini and goes back
//! to the game.
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
const text_tables = @import("asset_text_tables.zig");
const rtl = @import("zelda_rtl_types.zig");
const zelda_rtl = @import("zelda_rtl.zig");
const main = @import("main.zig");
const gfx = @import("game_gfx.zig");

/// Off while the game is being compared against the original, which never had
/// a third choice on the Select menu.
pub var enabled = true;

/// The message number the text engine is given for the Select menu's text.
/// Real messages stop a little past 0x180, so nothing in the game lands on it.
pub const kMsgCustom: u16 = 0xf000;

/// The first byte of a command in the US dialogue encoding.
const kCommandStart = 0x67;

/// The choice Choose3 leaves for the Settings line of the Select menu.
const kSelectSettings = 2;

const kJoypadH_B: u8 = 0x80;
const kJoypadH_Y: u8 = 0x40;
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

const kIndex = blk: {
    var n: usize = 0;
    for (menu.kSettings) |s| {
        if (editable(s)) n += 1;
    }
    var list: [n]u16 = undefined;
    var i: usize = 0;
    for (menu.kSettings, 0..) |s, si| {
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

const kTabs = blk: {
    var tabs: [kTabIcons.len]Tab = undefined;
    var t: usize = 0;
    var at: usize = 0;
    for (menu.kSettings, 0..) |s, si| {
        if (!menu.isSection(s)) continue;
        var count: usize = 0;
        for (menu.kSettings[si + 1 ..]) |next| {
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
        .{ "Graphics", "Fullscreen" },
        .{ "Graphics", "NewRenderer" },
        .{ "Graphics", "NoSpriteLimits" },
        .{ "Graphics", "LinearFiltering" },
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
    }
}

// ------------------------------------------------------------ the Select menu

var g_msg_buf: [128]u8 = undefined;
var g_msg_len: usize = 0;
var g_offered = false;

/// Encodes text spelled the way the dialogue dump spells it, commands and
/// pictures in brackets, into the bytes the text engine reads. No dictionary,
/// so it means the same whichever language's dictionary is loaded.
fn encode(out: []u8, s: []const u8) error{ UnknownCharacter, UnknownCommand, NoSpace }![]const u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '[') {
            const end = std.mem.indexOfScalarPos(u8, s, i, ']') orelse return error.UnknownCommand;
            const token = s[i .. end + 1];
            i = end + 1;
            if (gfx.glyphIndex(token)) |a| {
                if (n == out.len) return error.NoSpace;
                out[n] = a;
                n += 1;
                continue;
            }
            const inner = token[1 .. token.len - 1];
            const sp = std.mem.indexOfScalar(u8, inner, ' ');
            const name = if (sp) |p| inner[0..p] else inner;
            const idx = for (text_tables.kCommandNames, 0..) |cmd, ci| {
                if (std.mem.eql(u8, cmd, name)) break ci;
            } else return error.UnknownCommand;
            if (n + 2 > out.len) return error.NoSpace;
            out[n] = @intCast(idx + kCommandStart);
            n += 1;
            if (sp) |p| {
                out[n] = std.fmt.parseInt(u8, inner[p + 1 ..], 10) catch return error.UnknownCommand;
                n += 1;
            }
        } else {
            const a = gfx.glyphIndex(s[i .. i + 1]) orelse return error.UnknownCharacter;
            if (n == out.len) return error.NoSpace;
            out[n] = a;
            n += 1;
            i += 1;
        }
    }
    return out[0..n];
}

const kSelectText = "[Speed 00]>Continue Game[2]  Save and Quit[3]  Settings[Choose3]";

/// The Select menu's text with Settings added, when that can be offered.
/// False leaves the game's own two-choice message alone. The text is in the
/// US encoding, the only one written here.
pub fn offerSelectMenu() bool {
    g_offered = enabled and rtl.g_zenv.dialogue_flags & 1 == 0;
    if (!g_offered) return false;
    const bytes = encode(&g_msg_buf, kSelectText) catch return false;
    g_msg_len = bytes.len;
    return true;
}

/// The bytes for kMsgCustom, or null for any other message number.
pub fn customMessage(index: u16) ?[]const u8 {
    if (index != kMsgCustom) return null;
    return g_msg_buf[0..g_msg_len];
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

const kVisibleRows = 7;

pub fn isOpen() bool {
    return g_open;
}

/// Called when the Select menu's box closes. True when Settings was picked
/// and the screen is now open; false hands the choice back to the game's own
/// Continue and Save and Quit.
pub fn afterBoxClosed() bool {
    const picked = g_offered and vars.choice_in_multiselect_box.* == kSelectSettings;
    g_offered = false;
    if (!picked) return false;

    if (!open(.game)) {
        vars.choice_in_multiselect_box.* = vars.choice_in_multiselect_box_bak.*;
        return true;
    }
    // Back into the save menu's module, which runs update() for as long as
    // the screen is up. The box has already closed and put the game's own
    // display back.
    vars.main_module_index.* = 14;
    vars.submodule_index.* = 11;
    vars.subsubmodule_index.* = 0;
    return true;
}

/// Opens the screen over the file select screen, which keeps running under it
/// and hands update() the pad while it's up.
pub fn openFromFileSelect() void {
    _ = open(.file_select);
}

fn open(origin: @TypeOf(g_origin)) bool {
    g_ini = menu.Ini.load(alloc, "zelda3.ini") catch |err| {
        std.debug.print("Could not read zelda3.ini: {s}\n", .{@errorName(err)});
        return false;
    };
    gfx.loadHudTiles();
    g_origin = origin;
    g_open = true;
    g_details = false;
    g_dirty = false;
    g_row = 0;
    g_top = 0;
    g_held = 0;
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
    const pressed_h = vars.filtered_joypad_H.*;
    const pressed_l = vars.filtered_joypad_L.*;
    const held_h = vars.joypad1H_last.*;

    // The details box takes any button to put away, B included, so B there
    // means back to the list rather than out of the menu.
    if (g_details) {
        if (pressed_h & (kJoypadH_B | kJoypadH_Y | kJoypadH_Start) != 0 or pressed_l & kJoypadL_A != 0) {
            g_details = false;
            vars.sound_effect_2.* = 32;
        }
        return;
    }
    if (pressed_h & kJoypadH_Y != 0) {
        g_details = true;
        vars.sound_effect_2.* = 32;
        return;
    }

    if (pressed_h & (kJoypadH_B | kJoypadH_Start) != 0) return close();

    if (pressed_l & (kJoypadL_L | kJoypadL_R) != 0) {
        g_tab = if (pressed_l & kJoypadL_R != 0) (g_tab + 1) % kTabs.len else (g_tab + kTabs.len - 1) % kTabs.len;
        g_row = 0;
        g_top = 0;
        vars.sound_effect_2.* = 32;
        return;
    }

    const dirs = held_h & (kJoypadH_Up | kJoypadH_Down | kJoypadH_Left | kJoypadH_Right);
    const step = repeatStep(dirs != 0);
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

/// Saves what changed and goes back where the screen was opened from: the
/// game, as Continue would, or the file select screen, which never left.
fn close() void {
    if (g_ini) |*ini| {
        if (g_dirty) {
            ini.save("zelda3.ini") catch |err| std.debug.print("Could not write zelda3.ini: {s}\n", .{@errorName(err)});
        }
        ini.deinit();
    }
    g_ini = null;
    g_open = false;
    vars.sound_effect_2.* = 18;
    if (g_origin == .game) {
        vars.choice_in_multiselect_box.* = vars.choice_in_multiselect_box_bak.*;
        vars.main_module_index.* = vars.saved_module_for_menu.*;
        vars.submodule_index.* = 0;
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
    const cv = gfx.Canvas{ .pixels = pixels, .pitch = pitch, .width = width, .height = height, .scale = scale };
    loadTextColors();
    cv.dim();
    drawTabs(cv);
    if (g_details) drawDetails(cv) else drawList(cv);
    drawFooter(cv);
}

fn drawTabs(cv: gfx.Canvas) void {
    cv.box(8, 4, 30, 5, kFramePalette);
    for (kTabs, 0..) |tab, i| {
        const x: i32 = 32 + @as(i32, @intCast(i)) * 56;
        cv.icon(x, 16, tab.icon);
        if (i == g_tab and g_frame & 0x10 != 0) drawRing(cv, x, 16);
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

fn drawFooter(cv: gfx.Canvas) void {
    const hint = if (g_details)
        "[B] Back"
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
    var lines = WordWrap{ .text = describe(s), .width = 208 };
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

/// What each setting does, in words the font can draw: no colons, slashes or
/// percent signs.
fn describe(s: menu.Setting) []const u8 {
    const kDescriptions = [_][2][]const u8{
        .{ "StartMenu", "Show the start menu, with settings and the ROM and assets, before the game begins. When off, the game starts straight away unless its assets need building." },
        .{ "Autosave", "Save a snapshot of the game when you quit and pick up from it next time you start." },
        .{ "DisplayPerfInTitle", "Show the frames per second in the window's title bar." },
        .{ "ExtendedAspectRatio", "Widen the view past the original 4 by 3 screen, showing more of the world at the sides. 16 by 9 suits most modern screens." },
        .{ "DisableFrameDelay", "Skip the wait the game does between frames. Only worth it on a display running at exactly 60 hertz." },
        .{ "Rumble", "How hard the controller shakes when Link is hurt, bombs go off, bosses fall and the screen shakes. 0 turns it off." },
        .{ "Tracker", "Where the item tracker goes when playing a randomizer seed. Beside the game, over it, in its own window, or nowhere. T switches while playing." },
        .{ "Fullscreen", "Windowed, fullscreen at the desktop's resolution, or fullscreen with a change of display mode." },
        .{ "WindowScale", "How many times bigger than the SNES screen the window opens." },
        .{ "OutputMethod", "How frames reach the screen. SDL suits most machines, SDL-Software can help on a Raspberry Pi, and OpenGL is needed for shaders." },
        .{ "NewRenderer", "Draw the screen with a faster rewrite of the SNES graphics chip. Turn it off if something looks wrong." },
        .{ "EnhancedMode7", "Draw the world map and other rotating backgrounds at a higher resolution." },
        .{ "NoSpriteLimits", "Stop sprites flickering or vanishing when too many share a line of the screen, a limit of the original hardware." },
        .{ "IgnoreAspectRatio", "Stretch the picture to fill the window instead of keeping its shape." },
        .{ "LinearFiltering", "Smooth the pixels when the picture is scaled up. Softer, less crisp." },
        .{ "DimFlashes", "Tone down flashing effects, as the Virtual Console releases did." },
        .{ "EnableAudio", "Play sound and music at all." },
        .{ "AudioFreq", "The rate the game mixes its sound at. Higher is clearer. MSU audio sets its own." },
        .{ "AudioChannels", "Mono or stereo sound." },
        .{ "AudioSamples", "The sound buffer's size. Smaller means less delay before you hear things, larger helps if the sound crackles." },
        .{ "EnableMSU", "Play an MSU music pack instead of the SNES music. Deluxe packs give each area its own track, and Opuz packs are compressed." },
        .{ "MSUVolume", "How loud MSU music plays." },
        .{ "ResumeMSU", "Pick an overworld area's MSU track up where it left off when you come back to it." },
        .{ "MSUFinishCues", "Let short MSU music cues, like the mirror warp, play to their end before the next track starts." },
        .{ "ItemSwitchLR", "Switch items with L and R, and reorder the inventory with Y and a direction. Hold X, L or R on an item to put it on that button." },
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
    };
    for (kDescriptions) |d| {
        if (std.mem.eql(u8, d[0], s.key)) return d[1];
    }
    return "";
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

test "the Select menu text encodes" {
    var out: [128]u8 = undefined;
    const bytes = try encode(&out, kSelectText);
    try testing.expectEqual(@as(u8, 0), bytes[1]); // [Speed 00]'s parameter
    try testing.expectEqual(gfx.glyphIndex(">").?, bytes[2]);
    try testing.expectError(error.UnknownCharacter, encode(&out, "100%"));
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
        const d = describe(s);
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
