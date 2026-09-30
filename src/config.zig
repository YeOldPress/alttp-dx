//! Port of config.c: the .ini parser plus the keyboard and gamepad bindings.
const std = @import("std");
const util = @import("util.zig");

const c = @cImport({
    // translate-c cannot parse arm_neon.h, which SDL pulls in on ARM targets.
    // SDL2 spelled this guard SDL_DISABLE_ARM_NEON_H.
    @cDefine("SDL_DISABLE_NEON", "1");
    // Optimized builds define _FORTIFY_SOURCE, which makes mingw's headers
    // inline checked wrappers that translate-c turns into unused locals.
    @cUndef("_FORTIFY_SOURCE");
    @cInclude("SDL3/SDL.h");
});

extern fn atoi(s: [*:0]const u8) c_int;
extern fn strtol(s: [*:0]const u8, end: ?*?[*:0]u8, base: c_int) c_long;
extern fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn Die(err: [*:0]const u8) noreturn;

const kKeyMod_ScanCode: u16 = 0x200;
const kKeyMod_Alt: u16 = 0x400;
const kKeyMod_Shift: u16 = 0x800;
const kKeyMod_Ctrl: u16 = 0x1000;

/// Command ids, laid out exactly like the kKeys_ enum in config.h.
const kKeys = struct {
    const Null = 0;
    const Controls = Null + 1;
    const Controls_Last = Controls + 11;
    const Load = Controls_Last + 1;
    const Load_Last = Load + 19;
    const Save = Load_Last + 1;
    const Save_Last = Save + 19;
    const Replay = Save_Last + 1;
    const Replay_Last = Replay + 19;
    const LoadRef = Replay_Last + 1;
    const LoadRef_Last = LoadRef + 19;
    const ReplayRef = LoadRef_Last + 1;
    const ReplayRef_Last = ReplayRef + 19;
    const CheatLife = ReplayRef_Last + 1;
    const CheatKeys = CheatLife + 1;
    const CheatEquipment = CheatKeys + 1;
    const CheatWalkThroughWalls = CheatEquipment + 1;
    const ClearKeyLog = CheatWalkThroughWalls + 1;
    const StopReplay = ClearKeyLog + 1;
    const Fullscreen = StopReplay + 1;
    const Reset = Fullscreen + 1;
    const Pause = Reset + 1;
    const PauseDimmed = Pause + 1;
    const Turbo = PauseDimmed + 1;
    const ReplayTurbo = Turbo + 1;
    const WindowBigger = ReplayTurbo + 1;
    const WindowSmaller = WindowBigger + 1;
    const DisplayPerf = WindowSmaller + 1;
    const ToggleRenderer = DisplayPerf + 1;
    const VolumeUp = ToggleRenderer + 1;
    const VolumeDown = VolumeUp + 1;
    const Total = VolumeDown + 1;
};

const kOutputMethod_SDL: u8 = 0;
const kOutputMethod_SDLSoftware: u8 = 1;
const kOutputMethod_OpenGL: u8 = 2;
const kOutputMethod_OpenGL_ES: u8 = 3;

const kMsuEnabled_Msu: u8 = 1;
const kMsuEnabled_MsuDeluxe: u8 = 2;
const kMsuEnabled_Opuz: u8 = 4;

const kGamepadBtn_Invalid: c_int = -1;
const kGamepadBtn = struct {
    const A = 0;
    const B = 1;
    const X = 2;
    const Y = 3;
    const Back = 4;
    const Guide = 5;
    const Start = 6;
    const L3 = 7;
    const R3 = 8;
    const L1 = 9;
    const R1 = 10;
    const DpadUp = 11;
    const DpadDown = 12;
    const DpadLeft = 13;
    const DpadRight = 14;
    const L2 = 15;
    const R2 = 16;
    const Count = 17;
};

// Feature bits from features.h that the parser sets.
const kFeatures0_ExtendScreen64: u32 = 1;
const kFeatures0_SwitchLR: u32 = 2;
const kFeatures0_TurnWhileDashing: u32 = 4;
const kFeatures0_MirrorToDarkworld: u32 = 8;
const kFeatures0_CollectItemsWithSword: u32 = 16;
const kFeatures0_BreakPotsWithSword: u32 = 32;
const kFeatures0_DisableLowHealthBeep: u32 = 64;
const kFeatures0_SkipIntroOnKeypress: u32 = 128;
const kFeatures0_ShowMaxItemsInYellow: u32 = 256;
const kFeatures0_MoreActiveBombs: u32 = 512;
const kFeatures0_WidescreenVisualFixes: u32 = 1024;
const kFeatures0_CarryMoreRupees: u32 = 2048;
const kFeatures0_MiscBugFixes: u32 = 4096;
const kFeatures0_CancelBirdTravel: u32 = 8192;
const kFeatures0_GameChangingBugFixes: u32 = 16384;
const kFeatures0_SwitchLRLimit: u32 = 32768;
const kFeatures0_DimFlashes: u32 = 65536;

/// Must match `typedef struct Config` in config.h field for field.
pub const Config = extern struct {
    window_width: c_int,
    window_height: c_int,
    enhanced_mode7: bool,
    new_renderer: bool,
    ignore_aspect_ratio: bool,
    fullscreen: u8,
    window_scale: u8,
    enable_audio: bool,
    linear_filtering: bool,
    output_method: u8,
    audio_freq: u16,
    audio_channels: u8,
    audio_samples: u16,
    autosave: bool,
    extended_aspect_ratio: u8,
    extend_y: bool,
    no_sprite_limits: bool,
    display_perf_title: bool,
    enable_msu: u8,
    resume_msu: bool,
    msu_finish_cues: bool,
    disable_frame_delay: bool,
    msuvolume: u8,
    /// Controller rumble strength as a percentage; 0 turns it off.
    rumble: u8,
    features0: u32,

    link_graphics: ?[*:0]const u8,
    memory_buffer: ?[*:0]u8,
    shader: ?[*:0]const u8,
    msu_path: ?[*:0]const u8,
    language: ?[*:0]const u8,
};

pub export var g_config: Config = std.mem.zeroes(Config);

/// Squeeze an SDL keycode into 10 bits: the low 9 plus a flag for the
/// scancode-derived range.
fn remapSdlKeycode(key: c.SDL_Keycode) u16 {
    const scancode_bit: u16 = if (key & c.SDLK_SCANCODE_MASK != 0) kKeyMod_ScanCode else 0;
    return scancode_bit | @as(u16, @intCast(key & (kKeyMod_ScanCode - 1)));
}

fn k(key: c.SDL_Keycode) u16 {
    return remapSdlKeycode(key);
}

fn shift(key: c.SDL_Keycode) u16 {
    return remapSdlKeycode(key) | kKeyMod_Shift;
}

fn alt(key: c.SDL_Keycode) u16 {
    return remapSdlKeycode(key) | kKeyMod_Alt;
}

fn ctrl(key: c.SDL_Keycode) u16 {
    return remapSdlKeycode(key) | kKeyMod_Ctrl;
}

/// Commands past the end of this list default to unbound, as in the C
/// initializer, which stops short of kKeys_Total.
const kDefaultKbdControls: [kKeys.Total]u16 = blk: {
    var t = [_]u16{0} ** kKeys.Total;
    const listed = [_]u16{
        0,
        // Controls
        k(c.SDLK_UP),
        k(c.SDLK_DOWN),
        k(c.SDLK_LEFT),
        k(c.SDLK_RIGHT),
        k(c.SDLK_RSHIFT),
        k(c.SDLK_RETURN),
        k(c.SDLK_X),
        k(c.SDLK_Z),
        k(c.SDLK_S),
        k(c.SDLK_A),
        k(c.SDLK_C),
        k(c.SDLK_V),
        // LoadState
        k(c.SDLK_F1),
        k(c.SDLK_F2),
        k(c.SDLK_F3),
        k(c.SDLK_F4),
        k(c.SDLK_F5),
        k(c.SDLK_F6),
        k(c.SDLK_F7),
        k(c.SDLK_F8),
        k(c.SDLK_F9),
        k(c.SDLK_F10),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        // SaveState
        shift(c.SDLK_F1),
        shift(c.SDLK_F2),
        shift(c.SDLK_F3),
        shift(c.SDLK_F4),
        shift(c.SDLK_F5),
        shift(c.SDLK_F6),
        shift(c.SDLK_F7),
        shift(c.SDLK_F8),
        shift(c.SDLK_F9),
        shift(c.SDLK_F10),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        // Replay State
        ctrl(c.SDLK_F1),
        ctrl(c.SDLK_F2),
        ctrl(c.SDLK_F3),
        ctrl(c.SDLK_F4),
        ctrl(c.SDLK_F5),
        ctrl(c.SDLK_F6),
        ctrl(c.SDLK_F7),
        ctrl(c.SDLK_F8),
        ctrl(c.SDLK_F9),
        ctrl(c.SDLK_F10),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        // Load Ref State
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        // Replay Ref State
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        // CheatLife, CheatKeys, CheatEquipment, CheatWalkThroughWalls
        k(c.SDLK_W),
        k(c.SDLK_O),
        shift(c.SDLK_W),
        ctrl(c.SDLK_E),
        // ClearKeyLog, StopReplay, Fullscreen, Reset, Pause, PauseDimmed,
        // Turbo, ReplayTurbo, WindowBigger, WindowSmaller, DisplayPerf, ToggleRenderer
        k(c.SDLK_K),
        k(c.SDLK_L),
        alt(c.SDLK_RETURN),
        ctrl(c.SDLK_R),
        shift(c.SDLK_P),
        k(c.SDLK_P),
        k(c.SDLK_TAB),
        k(c.SDLK_T),
        0,
        0,
        k(c.SDLK_F),
        k(c.SDLK_R),
    };
    for (listed, 0..) |v, i| t[i] = v;
    break :blk t;
};

const KeyNameId = struct {
    name: [:0]const u8,
    id: u16,
    size: u16,
};

/// A whole range of commands (Load, Save, ...) shares one .ini key.
fn m(name: [:0]const u8, id: u16, last: u16) KeyNameId {
    return .{ .name = name, .id = id, .size = last - id + 1 };
}

fn s(name: [:0]const u8, id: u16) KeyNameId {
    return .{ .name = name, .id = id, .size = 1 };
}

const kKeyNameId = [_]KeyNameId{
    .{ .name = "Null", .id = kKeys.Null, .size = 65535 },
    m("Controls", kKeys.Controls, kKeys.Controls_Last),
    m("Load", kKeys.Load, kKeys.Load_Last),
    m("Save", kKeys.Save, kKeys.Save_Last),
    m("Replay", kKeys.Replay, kKeys.Replay_Last),
    m("LoadRef", kKeys.LoadRef, kKeys.LoadRef_Last),
    m("ReplayRef", kKeys.ReplayRef, kKeys.ReplayRef_Last),
    s("CheatLife", kKeys.CheatLife),
    s("CheatKeys", kKeys.CheatKeys),
    s("CheatEquipment", kKeys.CheatEquipment),
    s("CheatWalkThroughWalls", kKeys.CheatWalkThroughWalls),
    s("ClearKeyLog", kKeys.ClearKeyLog),
    s("StopReplay", kKeys.StopReplay),
    s("Fullscreen", kKeys.Fullscreen),
    s("Reset", kKeys.Reset),
    s("Pause", kKeys.Pause),
    s("PauseDimmed", kKeys.PauseDimmed),
    s("Turbo", kKeys.Turbo),
    s("ReplayTurbo", kKeys.ReplayTurbo),
    s("WindowBigger", kKeys.WindowBigger),
    s("WindowSmaller", kKeys.WindowSmaller),
    s("VolumeUp", kKeys.VolumeUp),
    s("VolumeDown", kKeys.VolumeDown),
    s("DisplayPerf", kKeys.DisplayPerf),
    s("ToggleRenderer", kKeys.ToggleRenderer),
};

const KeyMapHashEnt = extern struct {
    key: u16,
    cmd: u16,
    next: u16,
};

var keymap_hash_first = [_]u16{0} ** 255;
var keymap_hash: ?[*]KeyMapHashEnt = null;
var keymap_hash_size: c_int = 0;
var has_keynameid = [_]bool{false} ** kKeyNameId.len;

fn keyMapHashAdd(key: u16, cmd: u16) bool {
    if (keymap_hash_size & 0xff == 0) {
        if (keymap_hash_size > 10000) Die("Too many keys");
        const bytes = @sizeOf(KeyMapHashEnt) * @as(usize, @intCast(keymap_hash_size + 256));
        keymap_hash = @ptrCast(@alignCast(realloc(@ptrCast(keymap_hash), bytes)));
    }
    const i = keymap_hash_size;
    keymap_hash_size += 1;
    const table = keymap_hash.?;
    table[@intCast(i)] = .{ .key = key, .cmd = cmd, .next = 0 };
    const j = key % 255;

    var cur = &keymap_hash_first[j];
    while (cur.* != 0) {
        const ent = &table[cur.* - 1];
        if (ent.key == key) return false;
        cur = &ent.next;
    }
    cur.* = @intCast(i + 1);
    return true;
}

fn keyMapHashFind(key: u16) c_int {
    var i = keymap_hash_first[key % 255];
    while (i != 0) {
        const ent = &keymap_hash.?[i - 1];
        if (ent.key == key) return ent.cmd;
        i = ent.next;
    }
    return 0;
}

export fn FindCmdForSdlKey(code: c.SDL_Keycode, mod: c.SDL_Keymod) callconv(.c) c_int {
    if (code & ~@as(c.SDL_Keycode, c.SDLK_SCANCODE_MASK | 0x1ff) != 0) return 0;
    var key: u16 = 0;
    if (code != c.SDLK_LALT and code != c.SDLK_RALT)
        key |= if (mod & c.SDL_KMOD_ALT != 0) kKeyMod_Alt else 0;
    if (code != c.SDLK_LCTRL and code != c.SDLK_RCTRL)
        key |= if (mod & c.SDL_KMOD_CTRL != 0) kKeyMod_Ctrl else 0;
    if (code != c.SDLK_LSHIFT and code != c.SDLK_RSHIFT)
        key |= if (mod & c.SDL_KMOD_SHIFT != 0) kKeyMod_Shift else 0;
    key |= remapSdlKeycode(code);
    return keyMapHashFind(key);
}

fn parseKeyArray(value_in: [*:0]u8, cmd_in: c_int, size: c_int) void {
    var value: ?[*:0]u8 = value_in;
    var cmd = cmd_in;
    var i: c_int = 0;
    while (i < size) : ({
        i += 1;
        cmd += @intFromBool(cmd != 0);
    }) {
        var str = util.NextDelim(&value, ',') orelse break;
        if (str[0] == 0) continue;
        var key_with_mod: u16 = 0;
        while (true) {
            if (util.StringStartsWithNoCase(str, "Shift+") != null) {
                key_with_mod |= kKeyMod_Shift;
                str += 6;
            } else if (util.StringStartsWithNoCase(str, "Ctrl+") != null) {
                key_with_mod |= kKeyMod_Ctrl;
                str += 5;
            } else if (util.StringStartsWithNoCase(str, "Alt+") != null) {
                key_with_mod |= kKeyMod_Alt;
                str += 4;
            } else break;
        }
        const key = c.SDL_GetKeyFromName(str);
        if (key == c.SDLK_UNKNOWN) {
            std.debug.print("Unknown key: '{s}'\n", .{std.mem.span(str)});
            continue;
        }
        if (!keyMapHashAdd(key_with_mod | remapSdlKeycode(key), @intCast(cmd)))
            std.debug.print("Duplicate key: '{s}'\n", .{std.mem.span(str)});
    }
}

const GamepadMapEnt = extern struct {
    modifiers: u32,
    cmd: u16,
    next: u16,
};

var joymap_first = [_]u16{0} ** kGamepadBtn.Count;
var joymap_ents: ?[*]GamepadMapEnt = null;
var joymap_size: c_int = 0;
var has_joypad_controls = false;

fn gamepadMapAdd(button: c_int, modifiers: u32, cmd: u16) void {
    if (joymap_size & 0xff == 0) {
        if (joymap_size > 1000) Die("Too many joypad keys");
        const bytes = @sizeOf(GamepadMapEnt) * @as(usize, @intCast(joymap_size + 64));
        joymap_ents = @ptrCast(@alignCast(realloc(@ptrCast(joymap_ents), bytes) orelse Die("realloc failure")));
    }
    const ents = joymap_ents.?;
    var p = &joymap_first[@intCast(button)];
    // Insert it as early as possible but after any entry with more modifiers.
    const cb = @popCount(modifiers);
    while (p.* != 0 and cb < @popCount(ents[p.* - 1].modifiers))
        p = &ents[p.* - 1].next;
    const i = joymap_size;
    joymap_size += 1;
    ents[@intCast(i)] = .{ .modifiers = modifiers, .cmd = cmd, .next = p.* };
    p.* = @intCast(i + 1);
}

export fn FindCmdForGamepadButton(button: c_int, modifiers: u32) callconv(.c) c_int {
    var e = joymap_first[@intCast(button)];
    while (e != 0) {
        const ent = &joymap_ents.?[e - 1];
        if (modifiers & ent.modifiers == ent.modifiers) return ent.cmd;
        e = ent.next;
    }
    return 0;
}

// Longest substring first, so that "L1" does not shadow "L3" and friends.
const kGamepadKeyNames = [_][:0]const u8{
    "Back",      "Guide", "Start",  "L3",       "R3",
    "L1",        "R1",    "DpadUp", "DpadDown", "DpadLeft",
    "DpadRight", "L2",    "R2",     "Lb",       "Rb",
    "A",         "B",     "X",      "Y",
};

const kGamepadKeyIds = [_]u8{
    kGamepadBtn.Back,      kGamepadBtn.Guide, kGamepadBtn.Start,  kGamepadBtn.L3,       kGamepadBtn.R3,
    kGamepadBtn.L1,        kGamepadBtn.R1,    kGamepadBtn.DpadUp, kGamepadBtn.DpadDown, kGamepadBtn.DpadLeft,
    kGamepadBtn.DpadRight, kGamepadBtn.L2,    kGamepadBtn.R2,     kGamepadBtn.L1,       kGamepadBtn.R1,
    kGamepadBtn.A,         kGamepadBtn.B,     kGamepadBtn.X,      kGamepadBtn.Y,
};

fn parseGamepadButtonName(value: *[*:0]const u8) c_int {
    const str = value.*;
    for (kGamepadKeyNames, kGamepadKeyIds) |name, id| {
        if (util.StringStartsWithNoCase(str, name.ptr)) |r| {
            value.* = r;
            return id;
        }
    }
    return kGamepadBtn_Invalid;
}

const kDefaultGamepadCmds = [_]u8{
    kGamepadBtn.DpadUp, kGamepadBtn.DpadDown, kGamepadBtn.DpadLeft, kGamepadBtn.DpadRight,
    kGamepadBtn.Back,   kGamepadBtn.Start,    kGamepadBtn.B,        kGamepadBtn.A,
    kGamepadBtn.Y,      kGamepadBtn.X,        kGamepadBtn.L1,       kGamepadBtn.R1,
};

fn parseGamepadArray(value_in: [*:0]u8, cmd_in: c_int, size: c_int) void {
    var value: ?[*:0]u8 = value_in;
    var cmd = cmd_in;
    var i: c_int = 0;
    while (i < size) : ({
        i += 1;
        cmd += @intFromBool(cmd != 0);
    }) {
        const str = util.NextDelim(&value, ',') orelse break;
        if (str[0] == 0) continue;
        var modifiers: u32 = 0;
        var ss: [*:0]const u8 = str;
        while (true) {
            const button = parseGamepadButtonName(&ss);
            var bad = button == kGamepadBtn_Invalid;
            if (!bad) {
                while (ss[0] == ' ' or ss[0] == '\t') ss += 1;
                if (ss[0] == '+') {
                    ss += 1;
                    modifiers |= @as(u32, 1) << @intCast(button);
                    continue;
                } else if (ss[0] == 0) {
                    gamepadMapAdd(button, modifiers, @intCast(cmd));
                    break;
                } else bad = true;
            }
            std.debug.print("Unknown gamepad button: '{s}'\n", .{std.mem.span(str)});
            break;
        }
    }
}

// ------------------------------------------------------ rebinding in the game

/// The key a [KeyMap] name stands for, modifiers included, as the table keys
/// it. Null when SDL doesn't know the name.
fn keyFromName(name: []const u8) ?u16 {
    var buf: [64:0]u8 = undefined;
    if (name.len >= buf.len) return null;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    var str: [*:0]const u8 = &buf;
    var key_with_mod: u16 = 0;
    while (true) {
        if (util.StringStartsWithNoCase(str, "Shift+") != null) {
            key_with_mod |= kKeyMod_Shift;
            str += 6;
        } else if (util.StringStartsWithNoCase(str, "Ctrl+") != null) {
            key_with_mod |= kKeyMod_Ctrl;
            str += 5;
        } else if (util.StringStartsWithNoCase(str, "Alt+") != null) {
            key_with_mod |= kKeyMod_Alt;
            str += 4;
        } else break;
    }
    const key = c.SDL_GetKeyFromName(str);
    if (key == c.SDLK_UNKNOWN) return null;
    return key_with_mod | remapSdlKeycode(key);
}

/// The one gamepad button a [GamepadMap] name stands for. Combinations
/// ("L1+A") aren't a single button, so they come back invalid.
fn gamepadButtonFromName(name: []const u8) c_int {
    var buf: [32:0]u8 = undefined;
    if (name.len >= buf.len) return kGamepadBtn_Invalid;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    var p: [*:0]const u8 = &buf;
    const button = parseGamepadButtonName(&p);
    return if (p[0] == 0) button else kGamepadBtn_Invalid;
}

/// The name [GamepadMap] uses for a button, the spelling the stock file has.
pub fn gamepadButtonName(button: c_int) []const u8 {
    return switch (button) {
        kGamepadBtn.A => "A",
        kGamepadBtn.B => "B",
        kGamepadBtn.X => "X",
        kGamepadBtn.Y => "Y",
        kGamepadBtn.Back => "Back",
        kGamepadBtn.Guide => "Guide",
        kGamepadBtn.Start => "Start",
        kGamepadBtn.L3 => "L3",
        kGamepadBtn.R3 => "R3",
        kGamepadBtn.L1 => "Lb",
        kGamepadBtn.R1 => "Rb",
        kGamepadBtn.DpadUp => "DpadUp",
        kGamepadBtn.DpadDown => "DpadDown",
        kGamepadBtn.DpadLeft => "DpadLeft",
        kGamepadBtn.DpadRight => "DpadRight",
        kGamepadBtn.L2 => "L2",
        kGamepadBtn.R2 => "R2",
        else => "",
    };
}

/// SDL's gamepad button, as the bindings number it. SDL3 names the face
/// buttons by position - south, east, west, north - and the bindings' A, B,
/// X and Y mean those positions, Xbox style. -1 for anything else.
pub fn gamepadButtonFromSdl(button: u8) c_int {
    return switch (button) {
        c.SDL_GAMEPAD_BUTTON_SOUTH => kGamepadBtn.A,
        c.SDL_GAMEPAD_BUTTON_EAST => kGamepadBtn.B,
        c.SDL_GAMEPAD_BUTTON_WEST => kGamepadBtn.X,
        c.SDL_GAMEPAD_BUTTON_NORTH => kGamepadBtn.Y,
        c.SDL_GAMEPAD_BUTTON_BACK => kGamepadBtn.Back,
        c.SDL_GAMEPAD_BUTTON_GUIDE => kGamepadBtn.Guide,
        c.SDL_GAMEPAD_BUTTON_START => kGamepadBtn.Start,
        c.SDL_GAMEPAD_BUTTON_LEFT_STICK => kGamepadBtn.L3,
        c.SDL_GAMEPAD_BUTTON_RIGHT_STICK => kGamepadBtn.R3,
        c.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER => kGamepadBtn.L1,
        c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER => kGamepadBtn.R1,
        c.SDL_GAMEPAD_BUTTON_DPAD_UP => kGamepadBtn.DpadUp,
        c.SDL_GAMEPAD_BUTTON_DPAD_DOWN => kGamepadBtn.DpadDown,
        c.SDL_GAMEPAD_BUTTON_DPAD_LEFT => kGamepadBtn.DpadLeft,
        c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT => kGamepadBtn.DpadRight,
        else => -1,
    };
}

/// The triggers are axes to SDL; pressed most of the way, they're L2 and R2.
pub fn gamepadTriggerFromSdl(axis: u8, value: i16) c_int {
    if (value < 16000) return -1;
    return switch (axis) {
        c.SDL_GAMEPAD_AXIS_LEFT_TRIGGER => kGamepadBtn.L2,
        c.SDL_GAMEPAD_AXIS_RIGHT_TRIGGER => kGamepadBtn.R2,
        else => -1,
    };
}

/// Whether two [KeyMap] names mean the same key, however they're spelled.
pub fn sameKey(a: []const u8, b: []const u8) bool {
    const ka = keyFromName(a) orelse return false;
    const kb = keyFromName(b) orelse return false;
    return ka == kb;
}

/// Whether two [GamepadMap] names mean the same button ("Lb" and "L1" do).
pub fn sameGamepadButton(a: []const u8, b: []const u8) bool {
    const ba = gamepadButtonFromName(a);
    return ba != kGamepadBtn_Invalid and ba == gamepadButtonFromName(b);
}

fn isControl(cmd: c_int) bool {
    return cmd >= kKeys.Controls and cmd <= kKeys.Controls_Last;
}

/// Whether a key already does something other than one of the twelve SNES
/// buttons: fullscreen, a snapshot, a cheat. Taking it would quietly break
/// that, so the settings screen refuses it.
pub fn keyTakenByOther(name: []const u8) bool {
    const key = keyFromName(name) orelse return false;
    const cmd = keyMapHashFind(key);
    return cmd != 0 and !isControl(cmd);
}

/// Binds SNES button `control` (0 to 11, in Controls order: Up, Down, Left,
/// Right, Select, Start, A, B, X, Y, L, R) to a keyboard key while the game
/// runs. Whatever key it had stops doing anything, and the new key stops
/// doing whatever it did. False when the name isn't a key.
pub fn bindKey(control: usize, name: []const u8) bool {
    const key = keyFromName(name) orelse return false;
    const cmd: u16 = @intCast(kKeys.Controls + control);
    const table = keymap_hash orelse {
        _ = keyMapHashAdd(key, cmd);
        return true;
    };
    for (table[0..@intCast(keymap_hash_size)]) |*ent| {
        if (ent.cmd == cmd) ent.cmd = 0;
    }
    for (table[0..@intCast(keymap_hash_size)]) |*ent| {
        if (ent.key == key) {
            ent.cmd = cmd;
            return true;
        }
    }
    _ = keyMapHashAdd(key, cmd);
    return true;
}

/// The same for a gamepad button. Combinations with other buttons held are
/// left alone; only the plain press is rebound.
pub fn bindGamepadButton(control: usize, name: []const u8) bool {
    const button = gamepadButtonFromName(name);
    if (button == kGamepadBtn_Invalid) return false;
    const cmd: u16 = @intCast(kKeys.Controls + control);
    if (joymap_ents) |ents| {
        for (ents[0..@intCast(joymap_size)]) |*ent| {
            if (ent.cmd == cmd and ent.modifiers == 0) ent.cmd = 0;
        }
        var e = joymap_first[@intCast(button)];
        while (e != 0) {
            const ent = &ents[e - 1];
            if (ent.modifiers == 0) {
                ent.cmd = cmd;
                return true;
            }
            e = ent.next;
        }
    }
    gamepadMapAdd(button, 0, cmd);
    return true;
}

fn registerDefaultKeys() void {
    for (kKeyNameId[1..], 1..) |ent, i| {
        if (!has_keynameid[i]) {
            var key = ent.id;
            for (0..ent.size) |_| {
                _ = keyMapHashAdd(kDefaultKbdControls[key], key);
                key += 1;
            }
        }
    }
    if (!has_joypad_controls) {
        for (kDefaultGamepadCmds, 0..) |btn, i|
            gamepadMapAdd(btn, 0, @intCast(kKeys.Controls + i));
    }
}

fn getIniSection(str: [*:0]const u8) c_int {
    if (util.StringEqualsNoCase(str, "[KeyMap]")) return 0;
    if (util.StringEqualsNoCase(str, "[Graphics]")) return 1;
    if (util.StringEqualsNoCase(str, "[Sound]")) return 2;
    if (util.StringEqualsNoCase(str, "[General]")) return 3;
    if (util.StringEqualsNoCase(str, "[Features]")) return 4;
    if (util.StringEqualsNoCase(str, "[GamepadMap]")) return 5;
    if (util.StringEqualsNoCase(str, "[Randomizer]")) return 6;
    return -1;
}

pub export fn ParseBool(value_in: [*:0]const u8, result: ?*bool) callconv(.c) bool {
    var value = value_in;
    const first = value[0] | 32;
    value += 1;
    var rv = false;
    switch (first) {
        '0' => if (value[0] != 0) return false,
        'f' => if (!util.StringEqualsNoCase(value, "alse")) return false,
        'n' => if (!util.StringEqualsNoCase(value, "o")) return false,
        'o' => {
            rv = (value[0] | 32) == 'n';
            if (!util.StringEqualsNoCase(value, if (rv) "n" else "ff")) return false;
        },
        '1' => {
            rv = true;
            if (value[0] != 0) return false;
        },
        'y' => {
            rv = true;
            if (!util.StringEqualsNoCase(value, "es")) return false;
        },
        't' => {
            rv = true;
            if (!util.StringEqualsNoCase(value, "rue")) return false;
        },
        else => return false,
    }
    if (result) |r| {
        r.* = rv;
        return true;
    }
    return rv;
}

fn parseBoolBit(value: [*:0]const u8, data: *u32, mask: u32) bool {
    var tmp: bool = undefined;
    if (!ParseBool(value, &tmp)) return false;
    data.* = data.* & ~mask | (if (tmp) mask else 0);
    return true;
}

/// Applies one setting to g_config the way reading it from zelda3.ini would,
/// for the in-game settings menu. Only the plain sections are handled; key
/// bindings stay with the file. False when the section, key or value isn't
/// understood.
/// The choices a randomizer seed starts with, from [Randomizer]: where the
/// item tracker goes, widescreen pixels a side, rumble strength and whether
/// to look for MSU-1 tracks. Separate from the normal game's settings.
pub var g_tracker: []const u8 = "panel";
pub var g_rando_margin: u8 = 0;
pub var g_rando_rumble: u8 = 100;
/// Whether a seed plays the game's own MSU-1 pack, from MSUPath.
pub var g_rando_msu: bool = true;
/// Everything else about the tracker: TrackerSize, TrackerMaps and the rest.
pub var g_tracker_opts: @import("tracker.zig").Options = .{};

fn handleRandomizer(key: [*:0]const u8, value: [*:0]u8) bool {
    if (util.StringEqualsNoCase(key, "Tracker")) {
        g_tracker = std.mem.span(value);
        return true;
    } else if (util.StringEqualsNoCase(key, "Widescreen")) {
        const v = std.mem.span(value);
        const h: c_int = 224;
        g_rando_margin = if (std.mem.eql(u8, v, "16:9"))
            @intCast(@divTrunc(@divTrunc(h * 16, 9) - 256, 2))
        else if (std.mem.eql(u8, v, "16:10"))
            @intCast(@divTrunc(@divTrunc(h * 16, 10) - 256, 2))
        else if (std.mem.eql(u8, v, "18:9"))
            @intCast(@divTrunc(@divTrunc(h * 18, 9) - 256, 2))
        else
            0;
        return true;
    } else if (util.StringEqualsNoCase(key, "Rumble")) {
        g_rando_rumble = @intCast(std.math.clamp(atoi(value), 0, 100));
        return true;
    } else if (util.StringEqualsNoCase(key, "MSU")) {
        // An earlier switch, replaced by MSUGamePath; read and left alone.
        return true;
    } else if (util.StringEqualsNoCase(key, "MSUSeedTracks")) {
        return true; // gone: seeds play the game's pack
    } else if (util.StringEqualsNoCase(key, "MSUGamePath")) {
        return ParseBool(value, &g_rando_msu);
    }
    return g_tracker_opts.set(std.mem.span(key), std.mem.span(value));
}

pub fn applySetting(section: []const u8, key: []const u8, value: []const u8) bool {
    const id: c_int = if (std.mem.eql(u8, section, "Graphics"))
        1
    else if (std.mem.eql(u8, section, "Sound"))
        2
    else if (std.mem.eql(u8, section, "General"))
        3
    else if (std.mem.eql(u8, section, "Features"))
        4
    else if (std.mem.eql(u8, section, "Randomizer"))
        6
    else
        return false;
    var key_buf: [64]u8 = undefined;
    var value_buf: [64]u8 = undefined;
    const key_z = std.fmt.bufPrintZ(&key_buf, "{s}", .{key}) catch return false;
    const value_z = std.fmt.bufPrintZ(&value_buf, "{s}", .{value}) catch return false;
    return handleIniConfig(id, key_z.ptr, value_z.ptr);
}

fn handleIniConfig(section: c_int, key: [*:0]const u8, value: [*:0]u8) bool {
    switch (section) {
        0 => {
            for (kKeyNameId, 0..) |ent, i| {
                if (util.StringEqualsNoCase(key, ent.name.ptr)) {
                    has_keynameid[i] = true;
                    parseKeyArray(value, ent.id, ent.size);
                    return true;
                }
            }
        },
        5 => {
            for (kKeyNameId, 0..) |ent, i| {
                if (util.StringEqualsNoCase(key, ent.name.ptr)) {
                    if (i == 1) has_joypad_controls = true;
                    parseGamepadArray(value, ent.id, ent.size);
                    return true;
                }
            }
        },
        1 => return handleGraphics(key, value),
        2 => return handleSound(key, value),
        3 => return handleGeneral(key, value),
        4 => return handleFeatures(key, value),
        6 => return handleRandomizer(key, value),
        else => {},
    }
    return false;
}

fn handleGraphics(key: [*:0]const u8, value: [*:0]u8) bool {
    if (util.StringEqualsNoCase(key, "WindowSize")) {
        if (util.StringEqualsNoCase(value, "Auto")) {
            g_config.window_width = 0;
            g_config.window_height = 0;
            return true;
        }
        var rest: ?[*:0]u8 = value;
        while (util.NextDelim(&rest, 'x')) |str| {
            if (g_config.window_width == 0) {
                g_config.window_width = atoi(str);
            } else {
                g_config.window_height = atoi(str);
                return true;
            }
        }
    } else if (util.StringEqualsNoCase(key, "EnhancedMode7")) {
        return ParseBool(value, &g_config.enhanced_mode7);
    } else if (util.StringEqualsNoCase(key, "NewRenderer")) {
        return ParseBool(value, &g_config.new_renderer);
    } else if (util.StringEqualsNoCase(key, "IgnoreAspectRatio")) {
        return ParseBool(value, &g_config.ignore_aspect_ratio);
    } else if (util.StringEqualsNoCase(key, "Fullscreen")) {
        g_config.fullscreen = @truncate(@as(c_ulong, @bitCast(strtol(value, null, 10))));
        return true;
    } else if (util.StringEqualsNoCase(key, "WindowScale")) {
        g_config.window_scale = @truncate(@as(c_ulong, @bitCast(strtol(value, null, 10))));
        return true;
    } else if (util.StringEqualsNoCase(key, "OutputMethod")) {
        g_config.output_method = if (util.StringEqualsNoCase(value, "SDL-Software"))
            kOutputMethod_SDLSoftware
        else if (util.StringEqualsNoCase(value, "OpenGL"))
            kOutputMethod_OpenGL
        else if (util.StringEqualsNoCase(value, "OpenGL ES"))
            kOutputMethod_OpenGL_ES
        else
            kOutputMethod_SDL;
        return true;
    } else if (util.StringEqualsNoCase(key, "LinearFiltering")) {
        return ParseBool(value, &g_config.linear_filtering);
    } else if (util.StringEqualsNoCase(key, "NoSpriteLimits")) {
        return ParseBool(value, &g_config.no_sprite_limits);
    } else if (util.StringEqualsNoCase(key, "LinkGraphics")) {
        g_config.link_graphics = value;
        return true;
    } else if (util.StringEqualsNoCase(key, "Shader")) {
        g_config.shader = if (value[0] != 0) value else null;
        return true;
    } else if (util.StringEqualsNoCase(key, "DimFlashes")) {
        return parseBoolBit(value, &g_config.features0, kFeatures0_DimFlashes);
    }
    return false;
}

fn handleSound(key: [*:0]const u8, value: [*:0]u8) bool {
    if (util.StringEqualsNoCase(key, "EnableAudio")) {
        return ParseBool(value, &g_config.enable_audio);
    } else if (util.StringEqualsNoCase(key, "AudioFreq")) {
        g_config.audio_freq = @truncate(@as(c_ulong, @bitCast(strtol(value, null, 10))));
        return true;
    } else if (util.StringEqualsNoCase(key, "AudioChannels")) {
        g_config.audio_channels = @truncate(@as(c_ulong, @bitCast(strtol(value, null, 10))));
        return true;
    } else if (util.StringEqualsNoCase(key, "AudioSamples")) {
        g_config.audio_samples = @truncate(@as(c_ulong, @bitCast(strtol(value, null, 10))));
        return true;
    } else if (util.StringEqualsNoCase(key, "EnableMSU")) {
        if (util.StringEqualsNoCase(value, "opuz"))
            g_config.enable_msu = kMsuEnabled_Opuz
        else if (util.StringEqualsNoCase(value, "deluxe"))
            g_config.enable_msu = kMsuEnabled_MsuDeluxe
        else if (util.StringEqualsNoCase(value, "deluxe-opuz"))
            g_config.enable_msu = kMsuEnabled_MsuDeluxe | kMsuEnabled_Opuz
        else
            return ParseBool(value, @ptrCast(&g_config.enable_msu));
        return true;
    } else if (util.StringEqualsNoCase(key, "MSUPath")) {
        g_config.msu_path = value;
        return true;
    } else if (util.StringEqualsNoCase(key, "MSUVolume")) {
        g_config.msuvolume = @truncate(@as(c_uint, @bitCast(atoi(value))));
        return true;
    } else if (util.StringEqualsNoCase(key, "ResumeMSU")) {
        return ParseBool(value, &g_config.resume_msu);
    } else if (util.StringEqualsNoCase(key, "MSUFinishCues")) {
        return ParseBool(value, &g_config.msu_finish_cues);
    }
    return false;
}

/// The HUD spread to the edges of a widescreen frame. Kept apart from
/// g_config, whose layout follows the old C struct.
pub var g_widescreen_hud: bool = true;

fn handleGeneral(key: [*:0]const u8, value: [*:0]u8) bool {
    if (util.StringEqualsNoCase(key, "WidescreenHud")) {
        return ParseBool(value, &g_widescreen_hud);
    } else if (util.StringEqualsNoCase(key, "Autosave")) {
        g_config.autosave = strtol(value, null, 10) != 0;
        return true;
    } else if (util.StringEqualsNoCase(key, "ExtendedAspectRatio")) {
        var h: c_int = 224;
        var nospr = false;
        var novis = false;
        var rest: ?[*:0]u8 = value;
        // todo: make it not depend on the order
        while (util.NextDelim(&rest, ',')) |str| {
            if (strcmp(str, "extend_y") == 0) {
                h = 240;
                g_config.extend_y = true;
            } else if (strcmp(str, "16:9") == 0) {
                g_config.extended_aspect_ratio = @intCast(@divTrunc(@divTrunc(h * 16, 9) - 256, 2));
            } else if (strcmp(str, "16:10") == 0) {
                g_config.extended_aspect_ratio = @intCast(@divTrunc(@divTrunc(h * 16, 10) - 256, 2));
            } else if (strcmp(str, "18:9") == 0) {
                g_config.extended_aspect_ratio = @intCast(@divTrunc(@divTrunc(h * 18, 9) - 256, 2));
            } else if (strcmp(str, "4:3") == 0) {
                g_config.extended_aspect_ratio = 0;
            } else if (strcmp(str, "unchanged_sprites") == 0) {
                nospr = true;
            } else if (strcmp(str, "no_visual_fixes") == 0) {
                novis = true;
            } else return false;
        }
        if (g_config.extended_aspect_ratio != 0 and !nospr)
            g_config.features0 |= kFeatures0_ExtendScreen64;
        if (g_config.extended_aspect_ratio != 0 and !novis)
            g_config.features0 |= kFeatures0_WidescreenVisualFixes;
        return true;
    } else if (util.StringEqualsNoCase(key, "DisplayPerfInTitle")) {
        return ParseBool(value, &g_config.display_perf_title);
    } else if (util.StringEqualsNoCase(key, "DisableFrameDelay")) {
        return ParseBool(value, &g_config.disable_frame_delay);
    } else if (util.StringEqualsNoCase(key, "StartMenu")) {
        // Read by the start menu itself, before the game parses anything.
        return true;
    } else if (util.StringEqualsNoCase(key, "Rumble")) {
        g_config.rumble = @intCast(std.math.clamp(atoi(value), 0, 100));
        return true;
    } else if (util.StringEqualsNoCase(key, "Language")) {
        g_config.language = value;
        return true;
    } else if (util.StringEqualsNoCase(key, "Tracker")) {
        g_tracker = std.mem.span(value);
        return true;
    }
    return false;
}

fn handleFeatures(key: [*:0]const u8, value: [*:0]u8) bool {
    const bits = .{
        .{ "ItemSwitchLR", kFeatures0_SwitchLR },
        .{ "ItemSwitchLRLimit", kFeatures0_SwitchLRLimit },
        .{ "TurnWhileDashing", kFeatures0_TurnWhileDashing },
        .{ "MirrorToDarkworld", kFeatures0_MirrorToDarkworld },
        .{ "CollectItemsWithSword", kFeatures0_CollectItemsWithSword },
        .{ "BreakPotsWithSword", kFeatures0_BreakPotsWithSword },
        .{ "DisableLowHealthBeep", kFeatures0_DisableLowHealthBeep },
        .{ "SkipIntroOnKeypress", kFeatures0_SkipIntroOnKeypress },
        .{ "ShowMaxItemsInYellow", kFeatures0_ShowMaxItemsInYellow },
        .{ "MoreActiveBombs", kFeatures0_MoreActiveBombs },
        .{ "CarryMoreRupees", kFeatures0_CarryMoreRupees },
        .{ "MiscBugFixes", kFeatures0_MiscBugFixes },
        .{ "GameChangingBugFixes", kFeatures0_GameChangingBugFixes },
        .{ "CancelBirdTravel", kFeatures0_CancelBirdTravel },
    };
    inline for (bits) |bit| {
        if (util.StringEqualsNoCase(key, bit[0]))
            return parseBoolBit(value, &g_config.features0, bit[1]);
    }
    return false;
}

fn parseOneConfigFile(filename: [*:0]const u8, depth: c_int) bool {
    const contents = util.ReadWholeFile(filename, null) orelse return false;
    var filedata: ?[*:0]u8 = @ptrCast(contents);

    var section: c_int = -2;
    g_config.memory_buffer = @ptrCast(contents);

    var lineno: c_int = 1;
    while (util.NextLineStripComments(&filedata)) |p| : (lineno += 1) {
        if (p[0] == 0) continue; // empty line
        if (p[0] == '[') {
            section = getIniSection(p);
            if (section < 0)
                std.debug.print("{s}:{d}: Invalid .ini section {s}\n", .{ std.mem.span(filename), lineno, std.mem.span(p) });
        } else if (p[0] == '!' and util.SkipPrefix(p + 1, "include ") != null) {
            var tt: [*:0]u8 = p + 8;
            const new_filename = util.ReplaceFilenameWithNewPath(filename, util.NextPossiblyQuotedString(&tt)).?;
            const new_filename_z: [*:0]u8 = @ptrCast(new_filename);
            if (depth > 10 or !parseOneConfigFile(new_filename_z, depth + 1))
                std.debug.print("Warning: Unable to read {s}\n", .{std.mem.span(new_filename_z)});
            free(new_filename);
        } else if (section == -2) {
            std.debug.print("{s}:{d}: Expecting [section]\n", .{ std.mem.span(filename), lineno });
        } else {
            const v = util.SplitKeyValue(p) orelse {
                std.debug.print("{s}:{d}: Expecting 'key=value'\n", .{ std.mem.span(filename), lineno });
                continue;
            };
            if (section >= 0 and !handleIniConfig(section, p, v))
                std.debug.print("{s}:{d}: Can't parse '{s}'\n", .{ std.mem.span(filename), lineno, std.mem.span(p) });
        }
    }
    return true;
}

export fn ParseConfigFile(filename_in: ?[*:0]const u8) callconv(.c) void {
    g_config.msuvolume = 100; // default msu volume, 100%
    g_config.rumble = 100;
    g_config.msu_finish_cues = true;

    var filename = filename_in;
    if (filename != null or !parseOneConfigFile("zelda3.user.ini", 0)) {
        if (filename == null) filename = "zelda3.ini";
        if (!parseOneConfigFile(filename.?, 0))
            std.debug.print("Warning: Unable to read config file {s}\n", .{std.mem.span(filename.?)});
    }
    registerDefaultKeys();
}

const testing = std.testing;

test "ParseBool accepts the documented spellings" {
    var out: bool = undefined;
    for ([_][:0]const u8{ "1", "yes", "YES", "true", "True", "on", "ON" }) |v| {
        try testing.expect(ParseBool(v.ptr, &out));
        try testing.expect(out);
    }
    for ([_][:0]const u8{ "0", "no", "NO", "false", "False", "off", "OFF" }) |v| {
        try testing.expect(ParseBool(v.ptr, &out));
        try testing.expect(!out);
    }
    for ([_][:0]const u8{ "", "2", "truthy", "onn", "offf", "nope", "y" }) |v|
        try testing.expect(!ParseBool(v.ptr, &out));
}

test "ParseBool without a result returns the value itself" {
    try testing.expect(ParseBool("true", null));
    try testing.expect(!ParseBool("false", null));
}

test "parseBoolBit sets and clears just its own bit" {
    var features: u32 = kFeatures0_MiscBugFixes;
    try testing.expect(parseBoolBit("1", &features, kFeatures0_SwitchLR));
    try testing.expectEqual(kFeatures0_MiscBugFixes | kFeatures0_SwitchLR, features);
    try testing.expect(parseBoolBit("0", &features, kFeatures0_SwitchLR));
    try testing.expectEqual(kFeatures0_MiscBugFixes, features);
    try testing.expect(!parseBoolBit("bogus", &features, kFeatures0_SwitchLR));
}

test "remapSdlKeycode packs scancode keys into 10 bits" {
    // Character keys keep their low bits and carry no scancode flag.
    try testing.expectEqual(@as(u16, 'x'), remapSdlKeycode(c.SDLK_X));
    try testing.expectEqual(@as(u16, '\r'), remapSdlKeycode(c.SDLK_RETURN));
    // Scancode keys get the flag plus the low 9 bits of the scancode.
    const up = remapSdlKeycode(c.SDLK_UP);
    try testing.expect(up & kKeyMod_ScanCode != 0);
    try testing.expectEqual(@as(u16, c.SDL_SCANCODE_UP & 0x1ff | kKeyMod_ScanCode), up);
    // Distinct keys stay distinct after packing.
    try testing.expect(remapSdlKeycode(c.SDLK_UP) != remapSdlKeycode(c.SDLK_DOWN));
}

test "the default keyboard table matches the documented bindings" {
    try testing.expectEqual(kDefaultKbdControls[kKeys.Controls], remapSdlKeycode(c.SDLK_UP));
    try testing.expectEqual(kDefaultKbdControls[kKeys.Fullscreen], remapSdlKeycode(c.SDLK_RETURN) | kKeyMod_Alt);
    try testing.expectEqual(kDefaultKbdControls[kKeys.Save], remapSdlKeycode(c.SDLK_F1) | kKeyMod_Shift);
    try testing.expectEqual(kDefaultKbdControls[kKeys.Replay], remapSdlKeycode(c.SDLK_F1) | kKeyMod_Ctrl);
    // VolumeUp/VolumeDown are past the end of the C initializer, so unbound.
    try testing.expectEqual(@as(u16, 0), kDefaultKbdControls[kKeys.VolumeUp]);
    try testing.expectEqual(@as(u16, 0), kDefaultKbdControls[kKeys.VolumeDown]);
}

test "command id layout matches config.h" {
    try testing.expectEqual(1, kKeys.Controls);
    try testing.expectEqual(12, kKeys.Controls_Last);
    try testing.expectEqual(13, kKeys.Load);
    try testing.expectEqual(113, kKeys.CheatLife);
    try testing.expectEqual(131, kKeys.Total);
    try testing.expectEqual(25, kKeyNameId.len);
    try testing.expectEqual(20, kKeyNameId[2].size);
}

test "parseGamepadButtonName prefers the longest match" {
    var p: [*:0]const u8 = "L3";
    try testing.expectEqual(@as(c_int, kGamepadBtn.L3), parseGamepadButtonName(&p));
    try testing.expectEqual(@as(u8, 0), p[0]);

    p = "Lb+A";
    try testing.expectEqual(@as(c_int, kGamepadBtn.L1), parseGamepadButtonName(&p));
    try testing.expectEqualStrings("+A", std.mem.span(p));

    p = "Nope";
    try testing.expectEqual(kGamepadBtn_Invalid, parseGamepadButtonName(&p));
}

test "Config layout is what the C headers expect" {
    // Pointers follow the scalars, so the struct is pointer-aligned and the
    // first pointer field lands on its natural offset.
    try testing.expectEqual(@alignOf(*anyopaque), @alignOf(Config));
    try testing.expectEqual(0, @offsetOf(Config, "window_width"));
    try testing.expectEqual(0, @offsetOf(Config, "link_graphics") % @sizeOf(*anyopaque));
    try testing.expectEqual(@sizeOf(Config), @offsetOf(Config, "language") + @sizeOf(*anyopaque));
}

test "a gamepad button rebinds while the game runs, and gives up its old job" {
    // A of the SNES pad (control 6) moves from gamepad B to gamepad Y.
    try testing.expect(bindGamepadButton(6, "B"));
    try testing.expectEqual(@as(c_int, kKeys.Controls + 6), FindCmdForGamepadButton(kGamepadBtn.B, 0));
    try testing.expect(bindGamepadButton(6, "Y"));
    try testing.expectEqual(@as(c_int, kKeys.Controls + 6), FindCmdForGamepadButton(kGamepadBtn.Y, 0));
    try testing.expectEqual(@as(c_int, 0), FindCmdForGamepadButton(kGamepadBtn.B, 0));
    // Names that mean the same button are the same button.
    try testing.expect(sameGamepadButton("Lb", "L1"));
    try testing.expect(!sameGamepadButton("L1", "L2"));
    try testing.expect(!bindGamepadButton(0, "L1+A"));
    try testing.expectEqualStrings("Lb", gamepadButtonName(kGamepadBtn.L1));
}

test "a key rebinds while the game runs, and gives up its old job" {
    try testing.expect(bindKey(7, "z"));
    try testing.expectEqual(@as(c_int, kKeys.Controls + 7), keyMapHashFind(keyFromName("z").?));
    try testing.expect(bindKey(7, "k"));
    try testing.expectEqual(@as(c_int, kKeys.Controls + 7), keyMapHashFind(keyFromName("k").?));
    try testing.expectEqual(@as(c_int, 0), keyMapHashFind(keyFromName("z").?));
    try testing.expect(sameKey("x", "X"));
    try testing.expect(!bindKey(0, "NotAKeyAtAll"));
}
