//! Randomizer mode: a seed from alttpr.com, played in the emulator exactly as
//! the ROM plays it, with the item tracker beside the game, over it, or in a
//! window of its own. The port's own game is never involved.
const std = @import("std");
const c = @import("sdl.zig").c;
const emu = @import("emu.zig");
const tracker = @import("tracker.zig");

pub var g_active: bool = false;
var g_console: emu.Console = undefined;
var g_gfx: *tracker.Gfx = undefined;
var g_frame: [emu.kWidth * emu.kHeight]u32 = @splat(0);
pub var g_mode: tracker.Mode = .panel;
var g_toast: []const u8 = "";
var g_toast_frames: u32 = 0;
var g_frames: u32 = 0;

/// The game is drawn at twice its size, so the tracker's small text stays
/// sharp beside it.
pub const kScale = 2;
pub const kGameW = emu.kWidth * kScale;
pub const kGameH = emu.kHeight * kScale;
pub const kPanelW = tracker.kWidth * kScale;

/// Powers the seed on, with its save if it has one beside it.
pub fn start(alloc: std.mem.Allocator, path: [:0]const u8, mode: tracker.Mode) !void {
    g_console = try emu.Console.open(alloc, path);
    errdefer g_console.deinit();
    g_gfx = try alloc.create(tracker.Gfx);
    tracker.loadGfx(g_gfx, g_console.rom());
    g_mode = mode;
    g_active = true;
    toast(mode.label());
}

pub fn stop() void {
    if (!g_active) return;
    closeWindow();
    g_console.deinit();
    g_active = false;
}

/// The size the game's window draws: the game, plus the panel when it's on.
pub fn canvasWidth() c_int {
    return if (g_mode == .panel) kGameW + kPanelW else kGameW;
}

pub fn canvasHeight() c_int {
    return kGameH;
}

pub fn runFrame(buttons: u16) void {
    g_console.runFrame(buttons, @ptrCast(&g_frame), emu.kWidth * 4);
    g_frames +%= 1;
    // Saving is the game's job; this just gets it onto the disk now and then.
    if (g_frames % 300 == 0) g_console.flushSave();
}

pub fn audio(out: [*]i16, samples: c_int, channels: c_int) void {
    g_console.audio(out, samples, channels);
}

// The console makes a frame's sound at a time and the audio device takes it
// on its own schedule, so it waits in a ring in between. A late frame repeats
// nothing and a spare one waits its turn, instead of either being stretched.
var g_ring: [16384]i16 = undefined;
var g_ring_read: usize = 0;
var g_ring_len: usize = 0;

/// Called with the audio lock held, after each frame.
pub fn makeAudio(samples: usize, channels: usize) void {
    var buf: [4096]i16 = undefined;
    const n = @min(samples * channels, buf.len);
    g_console.audio(&buf, @intCast(n / channels), @intCast(channels));
    // Keep no more than a few frames' worth, so sound doesn't lag the game.
    const limit = n * 4;
    for (buf[0..n]) |v| {
        if (g_ring_len >= limit or g_ring_len == g_ring.len) {
            g_ring_read = (g_ring_read + 1) % g_ring.len;
            g_ring_len -= 1;
        }
        g_ring[(g_ring_read + g_ring_len) % g_ring.len] = v;
        g_ring_len += 1;
    }
}

/// Called from the audio device with the lock held.
pub fn takeAudio(out: [*]i16, samples: usize, channels: usize) void {
    for (0..samples * channels) |i| {
        if (g_ring_len == 0) {
            out[i] = 0;
            continue;
        }
        out[i] = g_ring[g_ring_read];
        g_ring_read = (g_ring_read + 1) % g_ring.len;
        g_ring_len -= 1;
    }
}

pub fn reset() void {
    g_console.flushSave();
    g_console.reset();
}

pub fn cycleMode() void {
    setMode(g_mode.next());
}

pub fn setMode(mode: tracker.Mode) void {
    if (g_mode == .window and mode != .window) closeWindow();
    g_mode = mode;
    toast(mode.label());
}

fn toast(msg: []const u8) void {
    g_toast = msg;
    g_toast_frames = 120;
}

fn state() tracker.State {
    return tracker.stateFrom(g_console.workRam());
}

/// Draws the frame: the game at double size, and the tracker as the mode
/// has it. `pitch` is in bytes.
pub fn draw(pixels: [*]u8, pitch_bytes: usize) void {
    const pitch = pitch_bytes / 4;
    const px: [*]u32 = @ptrCast(@alignCast(pixels));
    for (0..kGameH) |y| {
        const src = g_frame[(y / kScale) * emu.kWidth ..][0..emu.kWidth];
        const dst = px[y * pitch ..];
        for (0..kGameW) |x| dst[x] = src[x / kScale];
    }
    switch (g_mode) {
        .panel => tracker.draw(.{ .px = px + kGameW, .pitch = pitch, .w = kPanelW, .h = kGameH, .scale = kScale }, g_gfx, state(), true),
        .overlay => {
            // Bottom right, at the game's own pixel size, mostly opaque.
            const w = tracker.kWidth;
            const h = tracker.kOverlayHeight;
            const x = kGameW - w - 4;
            const y = kGameH - h - 4;
            tracker.draw(.{ .px = px + y * pitch + x, .pitch = pitch, .w = w, .h = h, .scale = 1, .alpha = 200 }, g_gfx, state(), false);
        },
        .off, .window => {},
    }
    if (g_toast_frames > 0) {
        g_toast_frames -= 1;
        const cv = tracker.Canvas{ .px = px, .pitch = pitch, .w = kGameW, .h = kGameH, .scale = kScale, .alpha = 220 };
        const w = g_toast.len * 4 + 4;
        for (2..9) |yy| {
            for (2..2 + w) |xx| cv.put2(xx, yy, 0x000000);
        }
        tracker.text(cv, 4, 3, g_toast, 0xffffff);
    }
}

// ------------------------------------------------------ its own window

var g_window: ?*c.SDL_Window = null;
var g_renderer: ?*c.SDL_Renderer = null;
var g_texture: ?*c.SDL_Texture = null;
var g_window_px: [kPanelW * kGameH]u32 = @splat(0);

fn closeWindow() void {
    if (g_texture) |t| c.SDL_DestroyTexture(t);
    if (g_renderer) |r| c.SDL_DestroyRenderer(r);
    if (g_window) |w| c.SDL_DestroyWindow(w);
    g_texture = null;
    g_renderer = null;
    g_window = null;
}

fn openWindow() bool {
    if (g_window != null) return true;
    const w = c.SDL_CreateWindow("alttp-zig tracker", kPanelW, kGameH, c.SDL_WINDOW_RESIZABLE) orelse return false;
    const r = c.SDL_CreateRenderer(w, null) orelse {
        c.SDL_DestroyWindow(w);
        return false;
    };
    _ = c.SDL_SetRenderLogicalPresentation(r, kPanelW, kGameH, c.SDL_LOGICAL_PRESENTATION_LETTERBOX);
    g_texture = c.SDL_CreateTexture(r, c.SDL_PIXELFORMAT_XRGB8888, c.SDL_TEXTUREACCESS_STREAMING, kPanelW, kGameH);
    _ = c.SDL_SetTextureScaleMode(g_texture, c.SDL_SCALEMODE_NEAREST);
    g_window = w;
    g_renderer = r;
    return true;
}

/// Draws the tracker window, when that's the mode. Call once a frame.
pub fn presentWindow() void {
    if (g_mode != .window) return;
    if (!openWindow()) {
        setMode(.panel);
        return;
    }
    tracker.draw(.{ .px = &g_window_px, .pitch = kPanelW, .w = kPanelW, .h = kGameH, .scale = kScale }, g_gfx, state(), true);
    _ = c.SDL_UpdateTexture(g_texture, null, &g_window_px, kPanelW * 4);
    _ = c.SDL_RenderClear(g_renderer);
    _ = c.SDL_RenderTexture(g_renderer, g_texture, null, null);
    _ = c.SDL_RenderPresent(g_renderer);
}

/// Handles events meant for the tracker window. True when it took the event.
pub fn handleEvent(ev: *const c.SDL_Event) bool {
    const win = g_window orelse return false;
    if (ev.type == c.SDL_EVENT_WINDOW_CLOSE_REQUESTED and ev.window.windowID == c.SDL_GetWindowID(win)) {
        // Closing the window puts the tracker back beside the game.
        setMode(.panel);
        return true;
    }
    return false;
}

/// Renders a frame of the game with the tracker panel into memory, for
/// looking at without a window (--emu-render).
pub fn renderToMemory(pixels: []u32) void {
    draw(@ptrCast(pixels.ptr), @as(usize, @intCast(canvasWidth())) * 4);
}

pub fn console() *emu.Console {
    return &g_console;
}
