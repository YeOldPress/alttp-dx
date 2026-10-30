//! What the start menu is made of, shared with the tools window so the two
//! look and handle alike: the colors, the rounded cards and buttons, the text,
//! and how pads and keys turn into moves.
const std = @import("std");
const builtin = @import("builtin");
const c = @import("sdl.zig").c;

/// The debug font is 8x8; everything is laid out in these scaled cells.
pub const kScale = 2;
pub const kCell = 8 * kScale;
pub const kRowH = kCell + 4;

// A dark blue ground that deepens toward the top, one rounded card on it with
// a hairline border and a soft shadow, and a warm gold for whatever's picked.
pub const Rgb = struct { r: u8, g: u8, b: u8 };
pub const kColorBgTop = Rgb{ .r = 0x0c, .g = 0x10, .b = 0x1a };
pub const kColorBgBottom = Rgb{ .r = 0x1c, .g = 0x26, .b = 0x3a };
pub const kColorShadow = Rgb{ .r = 0x05, .g = 0x07, .b = 0x0c };
pub const kColorPanel = Rgb{ .r = 0x14, .g = 0x1a, .b = 0x27 };
/// The card's border, the rules under titles, scrollbar tracks.
pub const kColorLine = Rgb{ .r = 0x2c, .g = 0x37, .b = 0x4e };
pub const kColorText = Rgb{ .r = 0xe8, .g = 0xec, .b = 0xf3 };
pub const kColorTextDim = Rgb{ .r = 0x7d, .g = 0x88, .b = 0x9c };
pub const kColorValue = Rgb{ .r = 0x8c, .g = 0xb8, .b = 0xff };
pub const kColorSelect = Rgb{ .r = 0xf5, .g = 0xc4, .b = 0x51 };
pub const kColorRowHi = Rgb{ .r = 0x22, .g = 0x2d, .b = 0x44 };
pub const kColorLaunchBg = Rgb{ .r = 0x34, .g = 0xc7, .b = 0x6c };
pub const kColorLaunchText = Rgb{ .r = 0x05, .g = 0x24, .b = 0x10 };
pub const kColorOk = Rgb{ .r = 0x6c, .g = 0xe0, .b = 0x98 };
pub const kColorWarn = Rgb{ .r = 0xf5, .g = 0xb4, .b = 0x5b };
pub const kColorSection = Rgb{ .r = 0x5f, .g = 0xd4, .b = 0xa6 };
pub const kColorRandoBg = Rgb{ .r = 0x6c, .g = 0x4f, .b = 0xd8 };
pub const kColorDisabledBg = Rgb{ .r = 0x2a, .g = 0x30, .b = 0x3d };

/// A rectangle on screen. Drawing and hit testing share these so the two
/// cannot drift apart: a button that moves but stays clickable where it used
/// to be is the kind of fault nobody notices until a click misses.
pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h;
    }
};

// ------------------------------------------------------------------ drawing

pub fn setColor(r: *c.SDL_Renderer, col: Rgb) void {
    _ = c.SDL_SetRenderDrawColor(r, col.r, col.g, col.b, 255);
}

pub fn fillRect(r: *c.SDL_Renderer, x: f32, y: f32, w: f32, h: f32, col: Rgb) void {
    setColor(r, col);
    const rect = c.SDL_FRect{ .x = x, .y = y, .w = w, .h = h };
    _ = c.SDL_RenderFillRect(r, &rect);
}

/// How far in from the side a rounded rectangle's edge is on row `row` of a
/// corner `radius` tall, row 0 being the top. A quarter circle, a pixel row at
/// a time.
pub fn cornerInset(radius: f32, row: f32) f32 {
    const dy = radius - row - 0.5;
    return radius - @sqrt(@max(0, radius * radius - dy * dy));
}

/// A filled rectangle with rounded corners, drawn a row at a time through the
/// corners and as one rectangle between them.
pub fn fillRound(r: *c.SDL_Renderer, x: f32, y: f32, w: f32, h: f32, radius: f32, col: Rgb) void {
    const rad = @min(radius, @min(w, h) / 2);
    const rows: usize = @intFromFloat(@ceil(rad));
    for (0..rows) |i| {
        const row: f32 = @floatFromInt(i);
        const in = @round(cornerInset(rad, row));
        fillRect(r, x + in, y + row, w - in * 2, 1, col);
        fillRect(r, x + in, y + h - 1 - row, w - in * 2, 1, col);
    }
    fillRect(r, x, y + @as(f32, @floatFromInt(rows)), w, h - @as(f32, @floatFromInt(rows)) * 2, col);
}

/// A rounded ring `t` thick, for focus rings and borders around content that
/// is already drawn.
pub fn outlineRound(r: *c.SDL_Renderer, x: f32, y: f32, w: f32, h: f32, radius: f32, t: f32, col: Rgb) void {
    const rad = @min(radius, @min(w, h) / 2);
    const inner = @max(0, rad - t);
    var row: f32 = 0;
    while (row < h) : (row += 1) {
        const from_edge = @min(row, h - 1 - row);
        const out = if (from_edge < rad) @round(cornerInset(rad, from_edge)) else 0;
        if (from_edge < t) {
            fillRect(r, x + out, y + row, w - out * 2, 1, col);
            continue;
        }
        const ir = from_edge - t;
        const in = if (ir < inner) @round(cornerInset(inner, ir)) + t else t;
        fillRect(r, x + out, y + row, in - out, 1, col);
        fillRect(r, x + w - in, y + row, in - out, 1, col);
    }
}

/// The background: a gradient from top to bottom, in 4-pixel bands, for a
/// window `w` by `h`.
pub fn fillBackground(r: *c.SDL_Renderer, w: f32, h: f32) void {
    const bands: usize = @intFromFloat(h / 4);
    for (0..bands) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(bands - 1));
        fillRect(r, 0, @as(f32, @floatFromInt(i * 4)), w, 4, mix(kColorBgTop, kColorBgBottom, t));
    }
}

pub fn mix(a: Rgb, b: Rgb, t: f32) Rgb {
    const ch = struct {
        fn f(x: u8, y: u8, k: f32) u8 {
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(y);
            return @intFromFloat(@round(fx + (fy - fx) * k));
        }
    }.f;
    return .{ .r = ch(a.r, b.r, t), .g = ch(a.g, b.g, t), .b = ch(a.b, b.b, t) };
}

/// A card: a rounded panel with a hairline border and a soft shadow under it.
/// It paints its own interior, which is what blanks the menu behind a modal.
pub fn drawFrame(r: *c.SDL_Renderer, x: f32, y: f32, w: f32, h: f32) void {
    fillRound(r, x + 2, y + 6, w, h, 14, kColorShadow);
    fillRound(r, x, y, w, h, 14, kColorLine);
    fillRound(r, x + 1, y + 1, w - 2, h - 2, 13, kColorPanel);
}

/// The selected row of a list: a rounded highlight with a gold bar down its
/// left side, where the old ">" cursor sat.
pub fn drawRowHighlight(r: *c.SDL_Renderer, x: f32, y: f32, w: f32, h: f32) void {
    fillRound(r, x, y, w, h, 6, kColorRowHi);
    fillRound(r, x + 4, y + 4, 3, h - 8, 1.5, kColorSelect);
}

/// How far a button's ring reaches past it: above and at the sides, and
/// below, where it also takes in the darker band.
pub const kRingAbove: f32 = 6;
pub const kRingBelow: f32 = 9;

/// A button: rounded, with a darker band along its bottom for depth, and a
/// gold ring around it when it's the one picked.
pub fn drawButton(r: *c.SDL_Renderer, box: Rect, col: Rgb, selected: bool) void {
    fillRound(r, box.x, box.y + 3, box.w, box.h, 10, mix(col, kColorShadow, 0.55));
    fillRound(r, box.x, box.y, box.w, box.h, 10, col);
    if (selected) outlineRound(r, box.x - kRingAbove, box.y - kRingAbove, box.w + kRingAbove * 2, box.h + kRingAbove + kRingBelow, 15, 3, kColorSelect);
}

pub fn drawText(r: *c.SDL_Renderer, x: f32, y: f32, col: Rgb, text: []const u8) void {
    drawTextScaled(r, x, y, col, text, kScale);
}

/// Width of a run of text once drawn. The debug font is a fixed 8x8 cell.
pub fn textWidth(text: []const u8, scale: f32) f32 {
    return @as(f32, @floatFromInt(text.len)) * 8 * scale;
}

pub fn drawTextCentered(r: *c.SDL_Renderer, cx: f32, y: f32, col: Rgb, text: []const u8, scale: f32) void {
    drawTextScaled(r, cx - textWidth(text, scale) / 2, y, col, text, scale);
}

/// SDL's debug font is a fixed 8x8, so size comes from the render scale.
pub fn drawTextScaled(r: *c.SDL_Renderer, x: f32, y: f32, col: Rgb, text: []const u8, scale: f32) void {
    var buf: [256]u8 = undefined;
    const n = @min(text.len, buf.len - 1);
    @memcpy(buf[0..n], text[0..n]);
    buf[n] = 0;
    setColor(r, col);
    _ = c.SDL_SetRenderScale(r, scale, scale);
    _ = c.SDL_RenderDebugText(r, x / scale, y / scale, @ptrCast(&buf));
    _ = c.SDL_SetRenderScale(r, 1, 1);
}

// -------------------------------------------------------------------- input

/// Every gamepad currently plugged in. Held open so their sticks and pads
/// can be polled each frame, which is what gives held-direction repeat.
pub const Pads = struct {
    items: [8]?*c.SDL_Gamepad = @splat(null),

    pub fn open(self: *Pads, id: c.SDL_JoystickID) void {
        for (&self.items) |*slot| {
            if (slot.* != null) continue;
            slot.* = c.SDL_OpenGamepad(id);
            return;
        }
    }

    pub fn close(self: *Pads, id: c.SDL_JoystickID) void {
        for (&self.items) |*slot| {
            const pad = slot.* orelse continue;
            if (c.SDL_GetGamepadID(pad) != id) continue;
            c.SDL_CloseGamepad(pad);
            slot.* = null;
        }
    }

    pub fn closeAll(self: *Pads) void {
        for (&self.items) |*slot| {
            if (slot.*) |pad| c.SDL_CloseGamepad(pad);
            slot.* = null;
        }
    }

    pub fn count(self: *const Pads) usize {
        var n: usize = 0;
        for (self.items) |slot| {
            if (slot != null) n += 1;
        }
        return n;
    }

    /// Where the left sticks are pushed. Only the sticks: buttons and keys
    /// arrive as events, because a genuinely analog input is the one thing
    /// that has to be read as state rather than as presses.
    pub fn stickDirection(self: *const Pads, comptime axis: enum { vertical, horizontal }) i32 {
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
pub fn configureJoysticks() void {
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
pub fn faceAction(which: c.SDL_JoystickID, button: u8) enum { confirm, back, save, info, none } {
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
            c.SDL_GAMEPAD_BUTTON_NORTH => .info,
            else => .none,
        };
    }

    return switch (label) {
        c.SDL_GAMEPAD_BUTTON_LABEL_A, c.SDL_GAMEPAD_BUTTON_LABEL_CROSS => .confirm,
        c.SDL_GAMEPAD_BUTTON_LABEL_B, c.SDL_GAMEPAD_BUTTON_LABEL_CIRCLE => .back,
        c.SDL_GAMEPAD_BUTTON_LABEL_X, c.SDL_GAMEPAD_BUTTON_LABEL_SQUARE => .save,
        // Y for info, as in the game's own settings.
        c.SDL_GAMEPAD_BUTTON_LABEL_Y, c.SDL_GAMEPAD_BUTTON_LABEL_TRIANGLE => .info,
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
pub const Held = struct {
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,

    pub fn vertical(self: Held) i32 {
        return @as(i32, if (self.down) 1 else 0) - @as(i32, if (self.up) 1 else 0);
    }

    pub fn horizontal(self: Held) i32 {
        return @as(i32, if (self.right) 1 else 0) - @as(i32, if (self.left) 1 else 0);
    }

    pub fn set(self: *Held, key: c.SDL_Keycode, down: bool) bool {
        switch (key) {
            c.SDLK_UP => self.up = down,
            c.SDLK_DOWN => self.down = down,
            c.SDLK_LEFT => self.left = down,
            c.SDLK_RIGHT => self.right = down,
            else => return false,
        }
        return true;
    }

    pub fn setButton(self: *Held, button: u8, down: bool) bool {
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
pub const Repeat = struct {
    dir: i32 = 0,
    next_at: u64 = 0,

    const kDelayMs = 380;
    const kRateMs = 80;

    /// Records a press that arrived as an event, so the frame poll that
    /// follows does not count it a second time.
    pub fn arm(self: *Repeat, dir: i32, now: u64) void {
        self.dir = dir;
        self.next_at = now + kDelayMs;
    }

    pub fn step(self: *Repeat, dir: i32, now: u64) i32 {
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
