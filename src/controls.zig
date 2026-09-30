//! The SNES pad's button mapping, as the settings' Controls tab and the start
//! menu's Controls screen both edit it: the Controls lines in [KeyMap] and
//! [GamepadMap], twelve names each, in the order Up, Down, Left, Right,
//! Select, Start, A, B, X, Y, L, R.
const std = @import("std");
const menu = @import("menu.zig");
const config = @import("config.zig");

pub const kButtonNames = [12][]const u8{ "Up", "Down", "Left", "Right", "Select", "Start", "A", "B", "X", "Y", "L", "R" };

pub const Device = enum { keyboard, gamepad };

pub fn setting(device: Device) usize {
    return if (device == .keyboard) kKeySetting else kPadSetting;
}

const kKeySetting = menu.settingIndex("KeyMap", "Controls").?;
const kPadSetting = menu.settingIndex("GamepadMap", "Controls").?;

/// The twelve names in one Controls line, copied out so the line can change
/// under them.
pub const Names = struct {
    buf: [12][40]u8 = undefined,
    len: [12]usize = @splat(0),

    pub fn get(self: *const Names, i: usize) []const u8 {
        return self.buf[i][0..self.len[i]];
    }

    pub fn set(self: *Names, i: usize, name: []const u8) void {
        const n = @min(name.len, self.buf[i].len);
        @memcpy(self.buf[i][0..n], name[0..n]);
        self.len[i] = n;
    }

    pub fn parse(line: []const u8) Names {
        var self = Names{};
        var it = std.mem.splitScalar(u8, line, ',');
        var i: usize = 0;
        while (it.next()) |part| : (i += 1) {
            if (i == 12) break;
            self.set(i, std.mem.trim(u8, part, " \t"));
        }
        return self;
    }

    pub fn join(self: *const Names, out: []u8) []const u8 {
        var n: usize = 0;
        for (0..12) |i| {
            if (i != 0 and n + 2 <= out.len) {
                @memcpy(out[n..][0..2], ", ");
                n += 2;
            }
            const part = self.get(i);
            const m = @min(part.len, out.len - n);
            @memcpy(out[n..][0..m], part[0..m]);
            n += m;
        }
        return out[0..n];
    }
};

pub fn current(ini: *const menu.Ini, device: Device) Names {
    return Names.parse(ini.values[setting(device)] orelse "");
}

fn same(device: Device, a: []const u8, b: []const u8) bool {
    return if (device == .keyboard) config.sameKey(a, b) else config.sameGamepadButton(a, b);
}

fn bind(device: Device, control: usize, name: []const u8) void {
    if (name.len == 0) return;
    _ = if (device == .keyboard) config.bindKey(control, name) else config.bindGamepadButton(control, name);
}

fn store(ini: *menu.Ini, device: Device, names: *const Names) !void {
    var buf: [512]u8 = undefined;
    try ini.set(setting(device), names.join(&buf));
}

/// Gives SNES button `row` a new key or gamepad button. Another SNES button
/// that had it gets this one's old one, so nothing is left without. `live`
/// rebinds the running game too; the start menu, before the game has read
/// its bindings, only edits the file.
pub fn assign(ini: *menu.Ini, device: Device, row: usize, name: []const u8, live: bool) !void {
    var names = current(ini, device);
    for (0..12) |j| {
        if (j != row and same(device, names.get(j), name)) {
            var old: [40]u8 = undefined;
            const was = names.get(row);
            @memcpy(old[0..was.len], was);
            names.set(j, old[0..was.len]);
            if (live) bind(device, j, names.get(j));
        }
    }
    names.set(row, name);
    if (live) bind(device, row, name);
    try store(ini, device, &names);
}

/// Both lines back to the ones the game ships with.
pub fn reset(ini: *menu.Ini, live: bool) !void {
    for ([_]Device{ .keyboard, .gamepad }) |device| {
        const s = menu.kSettings[setting(device)];
        const names = Names.parse(menu.defaultValue(s.section, s.key) orelse continue);
        if (live) {
            for (0..12) |i| bind(device, i, names.get(i));
        }
        try store(ini, device, &names);
    }
}

/// Whether a key already does something besides the twelve buttons -
/// fullscreen, a snapshot, a cheat - and taking it would quietly break that.
/// `live` asks the running game; otherwise the rest of [KeyMap] in the file
/// is read, since the game hasn't loaded it yet.
pub fn keyTaken(ini: *const menu.Ini, name: []const u8, live: bool) bool {
    if (live) return config.keyTakenByOther(name);
    var section: []const u8 = "";
    for (ini.lines.items) |line| {
        const t = std.mem.trim(u8, line, " \t");
        if (t.len == 0 or t[0] == '#' or t[0] == ';') continue;
        if (t[0] == '[') {
            section = std.mem.trim(u8, t[1..], "]");
            continue;
        }
        if (!std.mem.eql(u8, section, "KeyMap")) continue;
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        if (std.mem.eql(u8, std.mem.trim(u8, t[0..eq], " \t"), "Controls")) continue;
        var it = std.mem.splitScalar(u8, t[eq + 1 ..], ',');
        while (it.next()) |part| {
            if (config.sameKey(std.mem.trim(u8, part, " \t"), name)) return true;
        }
    }
    return false;
}

/// A key's name as short as it can be told: X, not x; RShift, not Right
/// Shift.
pub fn keyLabel(out: []u8, name: []const u8) []const u8 {
    const kShort = [_][2][]const u8{
        .{ "Right Shift", "RShift" }, .{ "Left Shift", "LShift" },
        .{ "Right Ctrl", "RCtrl" },   .{ "Left Ctrl", "LCtrl" },
        .{ "Right Alt", "RAlt" },     .{ "Left Alt", "LAlt" },
        .{ "Return", "Enter" },       .{ "Backspace", "Bksp" },
    };
    for (kShort) |k| {
        if (std.ascii.eqlIgnoreCase(name, k[0])) return k[1];
    }
    if (name.len == 1 and out.len != 0) {
        out[0] = std.ascii.toUpper(name[0]);
        return out[0..1];
    }
    return name;
}

/// A gamepad button's name, going by where it sits: Xbox letters for the
/// face buttons, as zelda3.ini names them.
pub fn padLabel(name: []const u8) []const u8 {
    const kShort = [_][2][]const u8{
        .{ "DpadUp", "Up" }, .{ "DpadDown", "Down" }, .{ "DpadLeft", "Left" }, .{ "DpadRight", "Right" },
        .{ "Lb", "LB" },     .{ "L1", "LB" },         .{ "Rb", "RB" },         .{ "R1", "RB" },
        .{ "L2", "LT" },     .{ "R2", "RT" },         .{ "L3", "LS" },         .{ "R3", "RS" },
    };
    for (kShort) |k| {
        if (std.ascii.eqlIgnoreCase(name, k[0])) return k[1];
    }
    return name;
}

const testing = std.testing;

test "a Controls line splits into twelve names and joins back the same" {
    const line = "Up, Down, Left, Right, Right Shift, Return, x, z, s, a, c, v";
    const names = Names.parse(line);
    try testing.expectEqualStrings("Right Shift", names.get(4));
    try testing.expectEqualStrings("v", names.get(11));
    var buf: [512]u8 = undefined;
    try testing.expectEqualStrings(line, names.join(&buf));
    for ([_]Device{ .keyboard, .gamepad }) |device| {
        const s = menu.kSettings[setting(device)];
        const d = Names.parse(menu.defaultValue(s.section, s.key).?);
        for (0..12) |i| try testing.expect(d.get(i).len != 0);
    }
}

test "taking another button's key swaps the two" {
    var ini = try menu.Ini.load(testing.allocator, "zelda3.ini");
    defer ini.deinit();
    const before = current(&ini, .keyboard);
    try assign(&ini, .keyboard, 6, before.get(7), false);
    const after = current(&ini, .keyboard);
    try testing.expectEqualStrings(before.get(7), after.get(6));
    try testing.expectEqualStrings(before.get(6), after.get(7));
    for (0..12) |i| {
        if (i == 6 or i == 7) continue;
        try testing.expectEqualStrings(before.get(i), after.get(i));
    }
    // Rb and R1 are one button.
    const pads = current(&ini, .gamepad);
    try assign(&ini, .gamepad, 10, "R1", false);
    const pads_after = current(&ini, .gamepad);
    try testing.expectEqualStrings("R1", pads_after.get(10));
    try testing.expectEqualStrings(pads.get(10), pads_after.get(11));
    // And reset puts it all back.
    try reset(&ini, false);
    const back = current(&ini, .keyboard);
    const s = menu.kSettings[setting(.keyboard)];
    const d = Names.parse(menu.defaultValue(s.section, s.key).?);
    for (0..12) |i| try testing.expectEqualStrings(d.get(i), back.get(i));
}

test "keys the rest of [KeyMap] uses are taken, from the file alone" {
    var ini = try menu.Ini.load(testing.allocator, "zelda3.ini");
    defer ini.deinit();
    // CheatLife is w and ClearKeyLog is k in the file the game ships with;
    // j is nothing.
    try testing.expect(keyTaken(&ini, "w", false));
    try testing.expect(keyTaken(&ini, "k", false));
    try testing.expect(!keyTaken(&ini, "j", false));
}

test "short names for keys and pad buttons" {
    var buf: [8]u8 = undefined;
    try testing.expectEqualStrings("X", keyLabel(&buf, "x"));
    try testing.expectEqualStrings("RShift", keyLabel(&buf, "Right Shift"));
    try testing.expectEqualStrings("Enter", keyLabel(&buf, "Return"));
    try testing.expectEqualStrings("LB", padLabel("Lb"));
    try testing.expectEqualStrings("Up", padLabel("DpadUp"));
}
