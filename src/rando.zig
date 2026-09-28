//! Randomizer mode: a seed from alttpr.com, played in the emulator exactly as
//! the ROM plays it, with the item tracker beside the game, over it, or in a
//! window of its own. The port's own game is never involved, though a few of
//! its extras are lent to it: rumble and widescreen read the same variables
//! from the emulated game's ram that they read from the port's.
const std = @import("std");
const c = @import("sdl.zig").c;
const snes_pkg = @import("snes");
const emu = @import("emu.zig");
const tracker = @import("tracker.zig");
const config = @import("config.zig");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl.zig");
const Msu1 = @import("msu1.zig").Msu1;

pub var g_active: bool = false;
var g_console: emu.Console = undefined;
var g_gfx: *tracker.Gfx = undefined;
pub var g_mode: tracker.Mode = .panel;
var g_toast: []const u8 = "";
var g_toast_frames: u32 = 0;
var g_frames: u32 = 0;

/// The game is drawn at twice its size, so the tracker's small text stays
/// sharp beside it.
pub const kScale = 2;
pub const kGameH = emu.kHeight * kScale;
pub const kPanelW = tracker.kWidth * kScale;
/// The widest the game gets: 18:9 adds 96 pixels a side.
pub const kMaxMargin = 96;
pub const kMaxGameW = (emu.kWidth + 2 * kMaxMargin) * kScale;

var g_frame: [(emu.kWidth + 2 * kMaxMargin) * emu.kHeight]u32 = @splat(0);
/// Widescreen pixels a side, from ExtendedAspectRatio.
var g_margin: u8 = 0;

var g_msu: Msu1 = .{};
var g_have_msu = false;

/// Powers the seed on, with its save if it has one beside it.
pub fn start(alloc: std.mem.Allocator, path: [:0]const u8, mode: tracker.Mode) !void {
    g_console = try emu.Console.open(alloc, path);
    errdefer g_console.deinit();
    g_gfx = try alloc.create(tracker.Gfx);
    tracker.loadGfx(g_gfx, g_console.rom());
    g_mode = mode;
    g_margin = @min(config.g_config.extended_aspect_ratio, kMaxMargin);
    startMsu(path);
    g_active = true;
    toast(mode.label());
}

/// Finds an MSU-1 pack: seed-1.pcm and so on beside the seed, which is how
/// packs for randomizer seeds are usually named, or MSUPath from the ini.
fn startMsu(rom_path: []const u8) void {
    const ext = std.fs.path.extension(rom_path);
    var buf: [1024]u8 = undefined;
    const beside = std.fmt.bufPrint(&buf, "{s}-", .{rom_path[0 .. rom_path.len - ext.len]}) catch return;
    g_msu.setPrefix(beside);
    if (!g_msu.hasTracks()) {
        const p = config.g_config.msu_path orelse return;
        if (config.g_config.enable_msu == 0) return;
        g_msu.setPrefix(std.mem.span(p));
        if (!g_msu.hasTracks()) return;
    }
    g_have_msu = true;
    snes_pkg.snes.g_io_hooks = .{ .ctx = &g_msu, .read = msuRead, .write = msuWrite };
    std.debug.print("MSU-1: playing tracks from {s}N.pcm\n", .{g_msu.prefix[0..g_msu.prefix_len]});
}

fn msuRead(ctx: *anyopaque, adr: u16) ?u8 {
    const m: *Msu1 = @ptrCast(@alignCast(ctx));
    return m.read(adr);
}

fn msuWrite(ctx: *anyopaque, adr: u16, val: u8) bool {
    const m: *Msu1 = @ptrCast(@alignCast(ctx));
    return m.write(adr, val);
}

pub fn stop() void {
    if (!g_active) return;
    closeWindow();
    snes_pkg.snes.g_io_hooks = null;
    g_msu.deinit();
    g_console.deinit();
    g_active = false;
}

fn gameW() usize {
    return (emu.kWidth + 2 * @as(usize, g_margin)) * kScale;
}

/// The size the game's window draws: the game, plus the panel when it's on.
pub fn canvasWidth() c_int {
    const w: c_int = @intCast(gameW());
    return if (g_mode == .panel) w + kPanelW else w;
}

pub fn canvasHeight() c_int {
    return kGameH;
}

/// Mirrors the emulated game's ram where the port keeps its own, so the
/// port's rumble and widescreen rules can read it. The port isn't running,
/// so nothing else is using it.
fn mirrorRam() void {
    @memcpy(&vars.g_ram, g_console.workRam());
}

pub fn runFrame(buttons: u16) void {
    mirrorRam();
    var left: c_int = 0;
    var right: c_int = 0;
    if (g_margin != 0) {
        const s = rtl.widescreenSideSpace(g_margin);
        left = std.math.clamp(s.left, 0, g_margin);
        right = std.math.clamp(s.right, 0, g_margin);
    }
    const width = emu.kWidth + 2 * @as(usize, g_margin);
    g_console.runFrame(buttons, @ptrCast(&g_frame), width * 4, g_margin, left, right);
    mirrorRam();
    g_frames +%= 1;
    // Saving is the game's job; this just gets it onto the disk now and then.
    if (g_frames % 300 == 0) g_console.flushSave();
}

/// The sound effects the game asked for this frame, for the rumble: what it
/// last wrote to the two sound effect ports.
pub fn soundEffects() [2]u8 {
    const apu: *snes_pkg.apu.Apu = @ptrCast(@alignCast(g_console.snes.apu.?));
    return .{ apu.inPorts[2], apu.inPorts[3] };
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
    if (g_have_msu) g_msu.mix(buf[0..n], n / channels, channels, @intCast(config.g_config.audio_freq));
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
    const gw = gameW();
    const src_w = gw / kScale;
    for (0..kGameH) |y| {
        const src = g_frame[(y / kScale) * src_w ..][0..src_w];
        const dst = px[y * pitch ..];
        for (0..gw) |x| dst[x] = src[x / kScale];
    }
    switch (g_mode) {
        .panel => tracker.draw(.{ .px = px + gw, .pitch = pitch, .w = kPanelW, .h = kGameH, .scale = kScale }, g_gfx, state(), true),
        .overlay => {
            // Bottom right, at the game's own pixel size, mostly opaque.
            const w = tracker.kWidth;
            const h = tracker.kOverlayHeight;
            const x = gw - w - 4;
            const y = kGameH - h - 4;
            tracker.draw(.{ .px = px + y * pitch + x, .pitch = pitch, .w = w, .h = h, .scale = 1, .alpha = 200 }, g_gfx, state(), false);
        },
        .off, .window => {},
    }
    if (g_toast_frames > 0) {
        g_toast_frames -= 1;
        const cv = tracker.Canvas{ .px = px, .pitch = pitch, .w = gw, .h = kGameH, .scale = kScale, .alpha = 220 };
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
