//! Port of src/main.c: the SDL entry point, event loop, software renderer
//! backend, input dispatch and asset loading.
const std = @import("std");
const builtin = @import("builtin");
const c = @import("sdl.zig").c;
const config = @import("config.zig");
const util = @import("util.zig");
const opengl = @import("opengl.zig");
const audio = @import("audio.zig");
const rumble = @import("rumble.zig");
const rtl = @import("zelda_rtl_types.zig");
const emu = @import("zelda_cpu_infra.zig");
const snes_pkg = @import("snes");
const ppu_mod = snes_pkg.ppu;
const ppu_types = snes_pkg.ppu_types;

const RendererFuncs = opengl.RendererFuncs;
const MemBlk = util.MemBlk;
const Ppu = ppu_types.Ppu;
const g_zenv = &rtl.g_zenv;

const kPpuExtraLeftRight = ppu_types.kPpuExtraLeftRight;
const kPpuRenderFlags_NewRenderer = ppu_types.kPpuRenderFlags_NewRenderer;
const kPpuRenderFlags_4x4Mode7 = ppu_types.kPpuRenderFlags_4x4Mode7;
const kPpuRenderFlags_Height240 = ppu_types.kPpuRenderFlags_Height240;
const kPpuRenderFlags_NoSpriteLimits = ppu_types.kPpuRenderFlags_NoSpriteLimits;

// config.zig exports these without `pub`, so they are reached by symbol.
extern fn ParseConfigFile(filename: ?[*:0]const u8) void;
extern fn FindCmdForSdlKey(code: u32, mod: u16) c_int;
extern fn FindCmdForGamepadButton(button: c_int, modifiers: u32) c_int;

// Still in C: zelda_rtl.c
extern fn ZeldaInitialize() void;
extern fn ZeldaReset(preserve_sram: bool) void;
extern fn ZeldaDrawPpuFrame(pixel_buffer: [*]u8, pitch: usize, render_flags: u32) void;
extern fn ZeldaRunFrame(input_state: c_int) bool;
extern fn ZeldaSetLanguage(language: ?[*:0]const u8) void;
extern fn PatchCommand(cmd: u8) void;
extern fn SaveLoadSlot(cmd: c_int, which: c_int) void;
extern fn ZeldaReadSram() void;
extern var g_wanted_zelda_features: u32;

// Still in C: load_gfx.c
extern var kGlovesColor: [2]u16;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn exit(code: c_int) noreturn;
extern fn printf(fmt: [*:0]const u8, ...) c_int;
extern fn sprintf(buf: [*]u8, fmt: [*:0]const u8, ...) c_int;
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
extern fn chdir(path: [*:0]const u8) c_int;
extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
/// The Windows CRT spells it _mkdir, and it takes no mode.
extern fn _mkdir(path: [*:0]const u8) c_int;
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(f: *anyopaque) c_int;

/// Creates the save directory if it is not already there. The condition is
/// comptime, so only the call that exists on this platform is analysed.
fn makeSaveDir() void {
    if (builtin.os.tag == .windows) {
        _ = _mkdir("saves");
    } else {
        _ = mkdir("saves", 0o755);
    }
}

// config.h
const kKeys_Null = 0;
const kKeys_Controls = 1;
const kKeys_Controls_Last = kKeys_Controls + 11;
const kKeys_Load = kKeys_Controls_Last + 1;
const kKeys_Load_Last = kKeys_Load + 19;
const kKeys_Save = kKeys_Load_Last + 1;
const kKeys_Save_Last = kKeys_Save + 19;
const kKeys_Replay = kKeys_Save_Last + 1;
const kKeys_Replay_Last = kKeys_Replay + 19;
const kKeys_LoadRef = kKeys_Replay_Last + 1;
const kKeys_LoadRef_Last = kKeys_LoadRef + 19;
const kKeys_ReplayRef = kKeys_LoadRef_Last + 1;
const kKeys_ReplayRef_Last = kKeys_ReplayRef + 19;
const kKeys_CheatLife = kKeys_ReplayRef_Last + 1;
const kKeys_CheatKeys = kKeys_CheatLife + 1;
const kKeys_CheatEquipment = kKeys_CheatKeys + 1;
const kKeys_CheatWalkThroughWalls = kKeys_CheatEquipment + 1;
const kKeys_ClearKeyLog = kKeys_CheatWalkThroughWalls + 1;
const kKeys_StopReplay = kKeys_ClearKeyLog + 1;
const kKeys_Fullscreen = kKeys_StopReplay + 1;
const kKeys_Reset = kKeys_Fullscreen + 1;
const kKeys_Pause = kKeys_Reset + 1;
const kKeys_PauseDimmed = kKeys_Pause + 1;
const kKeys_Turbo = kKeys_PauseDimmed + 1;
const kKeys_ReplayTurbo = kKeys_Turbo + 1;
const kKeys_WindowBigger = kKeys_ReplayTurbo + 1;
const kKeys_WindowSmaller = kKeys_WindowBigger + 1;
const kKeys_DisplayPerf = kKeys_WindowSmaller + 1;
const kKeys_ToggleRenderer = kKeys_DisplayPerf + 1;
const kKeys_VolumeUp = kKeys_ToggleRenderer + 1;
const kKeys_VolumeDown = kKeys_VolumeUp + 1;
const kKeys_Total = kKeys_VolumeDown + 1;

const kGamepadBtn_Invalid: c_int = -1;
const kGamepadBtn_A: c_int = 0;
const kGamepadBtn_B: c_int = 1;
const kGamepadBtn_X: c_int = 2;
const kGamepadBtn_Y: c_int = 3;
const kGamepadBtn_Back: c_int = 4;
const kGamepadBtn_Guide: c_int = 5;
const kGamepadBtn_Start: c_int = 6;
const kGamepadBtn_L3: c_int = 7;
const kGamepadBtn_R3: c_int = 8;
const kGamepadBtn_L1: c_int = 9;
const kGamepadBtn_R1: c_int = 10;
const kGamepadBtn_DpadUp: c_int = 11;
const kGamepadBtn_DpadDown: c_int = 12;
const kGamepadBtn_DpadLeft: c_int = 13;
const kGamepadBtn_DpadRight: c_int = 14;
const kGamepadBtn_L2: c_int = 15;
const kGamepadBtn_R2: c_int = 16;
const kGamepadBtn_Count: usize = 17;

const kOutputMethod_SDL: u8 = 0;
const kOutputMethod_SDLSoftware: u8 = 1;
const kOutputMethod_OpenGL: u8 = 2;
const kOutputMethod_OpenGL_ES: u8 = 3;

const kSaveLoad_Save: c_int = 0;
const kSaveLoad_Load: c_int = 1;
const kSaveLoad_Replay: c_int = 2;

const kFeatures0_DimFlashes: u32 = 65536;

/// assets.h
const kNumberOfAssets = 165;
pub export var g_asset_ptrs: [kNumberOfAssets]?[*]const u8 = @splat(null);
pub export var g_asset_sizes: [kNumberOfAssets]u32 = @splat(0);

fn assetPtr(i: usize) [*]u8 {
    return @constCast(g_asset_ptrs[i].?);
}

/// types.h only sets this when _DEBUG is defined, which this build never does.
const kDebugFlag = false;

const g_run_without_emu: bool = false;

const kDefaultFullscreen = 0;
const kMaxWindowScale = 10;
const kDefaultFreq = 44100;
const kDefaultChannels = 2;
const kDefaultSamples = 2048;

/// SDL3 dropped SDL_MIX_MAXVOLUME along with SDL_MixAudioFormat; the volume is
/// a stream gain now. The old scale is kept so the printed value reads as it did.
const kMixMaxVolume: c_int = 128;

const kWindowTitle = "The Legend of Zelda: A Link to the Past";

var g_win_flags: c.SDL_WindowFlags = c.SDL_WINDOW_RESIZABLE;
var g_window: ?*c.SDL_Window = null;

/// Set by the QUIT option on the file select screen; the loop below ends when
/// the game asks to exit from inside a menu rather than through a window close.
pub export var g_quit_requested: bool = false;

var g_paused: bool = false;
var g_turbo: bool = false;
var g_replay_turbo: bool = true;
var g_cursor: bool = true;
var g_current_window_scale: u8 = 0;
var g_gamepad_buttons: u8 = 0;
var g_input1_state: c_int = 0;
var g_display_perf: bool = false;
var g_curr_fps: c_int = 0;
var g_ppu_render_flags: u32 = 0;
var g_snes_width: c_int = 0;
var g_snes_height: c_int = 0;
var g_sdl_audio_mixer_volume: c_int = kMixMaxVolume;
var g_renderer_funcs: RendererFuncs = std.mem.zeroes(RendererFuncs);
var g_gamepad_modifiers: u32 = 0;
var g_gamepad_last_cmd: [kGamepadBtn_Count]u16 = @splat(0);

fn intMin(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

fn intMax(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

pub export fn Die(err: [*:0]const u8) callconv(.c) noreturn {
    std.debug.print("Error: {s}\n", .{err});
    exit(1);
}

pub export fn ChangeWindowScale(scale_step: c_int) callconv(.c) void {
    const masked = c.SDL_GetWindowFlags(g_window) &
        (c.SDL_WINDOW_FULLSCREEN | c.SDL_WINDOW_MINIMIZED | c.SDL_WINDOW_MAXIMIZED);
    if (masked != 0)
        return;
    // SDL3 hands out display ids instead of indices, and 0 means "unknown".
    var screen = c.SDL_GetDisplayForWindow(g_window);
    if (screen == 0) screen = c.SDL_GetPrimaryDisplay();
    var max_scale: c_int = kMaxWindowScale;
    var bounds: c.SDL_Rect = undefined;
    var bt: c_int = -1;
    var bl: c_int = 0;
    var bb: c_int = 0;
    var br: c_int = 0;
    // note this takes into effect Windows display scaling, i.e., resolution is divided by scale factor
    if (c.SDL_GetDisplayUsableBounds(screen, &bounds)) {
        // this call may take a while before it is reported by Windows (or not at all in my testing)
        if (!c.SDL_GetWindowBordersSize(g_window, &bt, &bl, &bb, &br)) {
            // guess based on Windows 10/11 defaults
            bl = 1;
            br = 1;
            bb = 1;
            bt = 31;
        }
        // Allow a scale level slightly above the max that fits on screen
        const mw = @divTrunc(bounds.w - bl - br + @divTrunc(g_snes_width, 4), g_snes_width);
        const mh = @divTrunc(bounds.h - bt - bb + @divTrunc(g_snes_height, 4), g_snes_height);
        max_scale = intMin(mw, mh);
    }
    const new_scale = intMax(intMin(@as(c_int, g_current_window_scale) + scale_step, max_scale), 1);
    g_current_window_scale = @intCast(new_scale);
    const w = new_scale * g_snes_width;
    const h = new_scale * g_snes_height;

    _ = c.SDL_SetWindowSize(g_window, w, h);
    if (bt >= 0) {
        // Center the window on top of the mouse. SDL3 reports the pointer in
        // floats.
        var mxf: f32 = 0;
        var myf: f32 = 0;
        _ = c.SDL_GetGlobalMouseState(&mxf, &myf);
        const mx: c_int = @intFromFloat(mxf);
        const my: c_int = @intFromFloat(myf);
        const wx = intMax(intMin(mx - @divTrunc(w, 2), bounds.x + bounds.w - bl - br - w), bounds.x + bl);
        const wy = intMax(intMin(my - @divTrunc(h, 2), bounds.y + bounds.h - bt - bb - h), bounds.y + bt);
        _ = c.SDL_SetWindowPosition(g_window, wx, wy);
    } else {
        _ = c.SDL_SetWindowPosition(g_window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED);
    }
}

const RESIZE_BORDER = 20;

fn HitTestCallback(win: ?*c.SDL_Window, pt: [*c]const c.SDL_Point, data: ?*anyopaque) callconv(.c) c.SDL_HitTestResult {
    _ = data;
    const flags = c.SDL_GetWindowFlags(win);
    if ((flags & c.SDL_WINDOW_FULLSCREEN) != 0)
        return c.SDL_HITTEST_NORMAL;

    if ((c.SDL_GetModState() & c.SDL_KMOD_CTRL) != 0)
        return c.SDL_HITTEST_DRAGGABLE;

    var w: c_int = 0;
    var h: c_int = 0;
    _ = c.SDL_GetWindowSize(win, &w, &h);

    if (pt[0].y < RESIZE_BORDER) {
        return if (pt[0].x < RESIZE_BORDER)
            c.SDL_HITTEST_RESIZE_TOPLEFT
        else if (pt[0].x >= w - RESIZE_BORDER)
            c.SDL_HITTEST_RESIZE_TOPRIGHT
        else
            c.SDL_HITTEST_RESIZE_TOP;
    } else if (pt[0].y >= h - RESIZE_BORDER) {
        return if (pt[0].x < RESIZE_BORDER)
            c.SDL_HITTEST_RESIZE_BOTTOMLEFT
        else if (pt[0].x >= w - RESIZE_BORDER)
            c.SDL_HITTEST_RESIZE_BOTTOMRIGHT
        else
            c.SDL_HITTEST_RESIZE_BOTTOM;
    } else {
        if (pt[0].x < RESIZE_BORDER) {
            return c.SDL_HITTEST_RESIZE_LEFT;
        } else if (pt[0].x >= w - RESIZE_BORDER) {
            return c.SDL_HITTEST_RESIZE_RIGHT;
        }
    }
    return c.SDL_HITTEST_NORMAL;
}

var perf_history: [64]f32 = @splat(0);
var perf_average: f32 = 0;
var perf_history_pos: usize = 0;

fn DrawPpuFrameWithPerf() void {
    const ppu: *Ppu = @ptrCast(@alignCast(g_zenv.ppu.?));
    const render_scale = ppu_mod.PpuGetCurrentRenderScale(ppu, g_ppu_render_flags);
    var pixel_buffer: [*c]u8 = null;
    var pitch: c_int = 0;

    g_renderer_funcs.BeginDraw.?(
        g_snes_width * render_scale,
        g_snes_height * render_scale,
        &pixel_buffer,
        &pitch,
    );
    if (g_display_perf or config.g_config.display_perf_title) {
        const before = c.SDL_GetPerformanceCounter();
        ZeldaDrawPpuFrame(pixel_buffer, @intCast(pitch), g_ppu_render_flags);
        const after = c.SDL_GetPerformanceCounter();
        const v: f32 = @floatCast(@as(f64, @floatFromInt(c.SDL_GetPerformanceFrequency())) /
            @as(f64, @floatFromInt(after - before)));
        perf_average += v - perf_history[perf_history_pos];
        perf_history[perf_history_pos] = v;
        perf_history_pos = (perf_history_pos + 1) & 63;
        g_curr_fps = @intFromFloat(perf_average * (1.0 / 64.0));
    } else {
        ZeldaDrawPpuFrame(pixel_buffer, @intCast(pitch), g_ppu_render_flags);
    }
    if (g_display_perf)
        RenderNumber(pixel_buffer + @as(usize, @intCast(pitch * render_scale)), @intCast(pitch), g_curr_fps, render_scale == 4);
    g_renderer_funcs.EndDraw.?();
}

var g_audio_mutex: ?*c.SDL_Mutex = null;
var g_audio_stream: ?*c.SDL_AudioStream = null;
var g_audiobuffer: ?[*]u8 = null;
var g_audiobuffer_cur: ?[*]u8 = null;
var g_audiobuffer_end: ?[*]u8 = null;
var g_frames_per_block: c_int = 0;
var g_audio_channels: u8 = 0;

/// SDL3 asks the app to push into the stream rather than handing it a buffer to
/// fill, and scales the samples itself, so the SDL_MixAudioFormat step the C
/// used for the volume is gone (see ApplyAudioVolume).
fn AudioCallback(
    userdata: ?*anyopaque,
    stream: ?*c.SDL_AudioStream,
    additional_amount: c_int,
    total_amount: c_int,
) callconv(.c) void {
    _ = .{ userdata, total_amount };
    var len = additional_amount;
    c.SDL_LockMutex(g_audio_mutex);
    while (len > 0) {
        if (@intFromPtr(g_audiobuffer_end.?) - @intFromPtr(g_audiobuffer_cur.?) == 0) {
            audio.ZeldaRenderAudio(@ptrCast(@alignCast(g_audiobuffer.?)), g_frames_per_block, g_audio_channels);
            g_audiobuffer_cur = g_audiobuffer;
            g_audiobuffer_end = g_audiobuffer.? +
                @as(usize, @intCast(g_frames_per_block)) * g_audio_channels * @sizeOf(i16);
        }
        const avail: c_int = @intCast(@intFromPtr(g_audiobuffer_end.?) - @intFromPtr(g_audiobuffer_cur.?));
        const n = intMin(len, avail);
        _ = c.SDL_PutAudioStreamData(stream, g_audiobuffer_cur.?, n);
        g_audiobuffer_cur = g_audiobuffer_cur.? + @as(usize, @intCast(n));
        len -= n;
    }

    audio.ZeldaDiscardUnusedAudioFrames();
    c.SDL_UnlockMutex(g_audio_mutex);
}

// State for sdl renderer
var g_renderer: ?*c.SDL_Renderer = null;
var g_texture: ?*c.SDL_Texture = null;
var g_sdl_renderer_rect: c.SDL_Rect = std.mem.zeroes(c.SDL_Rect);

fn SdlRenderer_Init(window: ?*c.SDL_Window) callconv(.c) bool {
    _ = window;
    if (config.g_config.shader != null)
        std.debug.print("Warning: Shaders are supported only with the OpenGL backend\n", .{});

    // SDL3 picks the backend by name and sets vsync separately; the old
    // SDL_RENDERER_* creation flags are gone.
    const software = config.g_config.output_method == kOutputMethod_SDLSoftware;
    const renderer = c.SDL_CreateRenderer(g_window, if (software) c.SDL_SOFTWARE_RENDERER else null);
    if (renderer == null) {
        _ = printf("Failed to create renderer: %s\n", c.SDL_GetError());
        return false;
    }
    if (!software)
        _ = c.SDL_SetRenderVSync(renderer, 1);
    if (kDebugFlag) {
        // SDL_GetRendererInfo is gone; the formats come from a renderer
        // property holding a SDL_PIXELFORMAT_UNKNOWN-terminated list.
        _ = printf("Supported texture formats:");
        const formats: ?[*]const c.SDL_PixelFormat = @ptrCast(@alignCast(c.SDL_GetPointerProperty(
            c.SDL_GetRendererProperties(renderer),
            c.SDL_PROP_RENDERER_TEXTURE_FORMATS_POINTER,
            null,
        )));
        if (formats) |list| {
            var i: usize = 0;
            while (list[i] != c.SDL_PIXELFORMAT_UNKNOWN) : (i += 1)
                _ = printf(" %s", c.SDL_GetPixelFormatName(list[i]));
        }
        _ = printf("\n");
    }
    g_renderer = renderer;
    if (!config.g_config.ignore_aspect_ratio)
        _ = c.SDL_SetRenderLogicalPresentation(renderer, g_snes_width, g_snes_height, c.SDL_LOGICAL_PRESENTATION_LETTERBOX);

    const tex_mult: c_int = if (g_ppu_render_flags & kPpuRenderFlags_4x4Mode7 != 0) 4 else 1;
    g_texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STREAMING, g_snes_width * tex_mult, g_snes_height * tex_mult);
    if (g_texture == null) {
        _ = printf("Failed to create texture: %s\n", c.SDL_GetError());
        return false;
    }
    // SDL_HINT_RENDER_SCALE_QUALITY was replaced by a per-texture scale mode,
    // which defaults to linear, so nearest has to be asked for explicitly.
    _ = c.SDL_SetTextureScaleMode(g_texture, if (config.g_config.linear_filtering)
        c.SDL_SCALEMODE_LINEAR
    else
        c.SDL_SCALEMODE_NEAREST);
    // SDL3 gives a texture in an alpha-carrying format SDL_BLENDMODE_BLEND by
    // default, where SDL2 used SDL_BLENDMODE_NONE. The PPU leaves the alpha
    // byte at zero, so blending would make every frame invisible.
    _ = c.SDL_SetTextureBlendMode(g_texture, c.SDL_BLENDMODE_NONE);
    return true;
}

fn SdlRenderer_Destroy() callconv(.c) void {
    c.SDL_DestroyTexture(g_texture);
    c.SDL_DestroyRenderer(g_renderer);
}

fn SdlRenderer_BeginDraw(width: c_int, height: c_int, pixels: *[*c]u8, pitch: *c_int) callconv(.c) void {
    g_sdl_renderer_rect.w = width;
    g_sdl_renderer_rect.h = height;
    if (!c.SDL_LockTexture(g_texture, &g_sdl_renderer_rect, @ptrCast(pixels), pitch)) {
        _ = printf("Failed to lock texture: %s\n", c.SDL_GetError());
        return;
    }
}

fn SdlRenderer_EndDraw() callconv(.c) void {
    c.SDL_UnlockTexture(g_texture);
    _ = c.SDL_RenderClear(g_renderer);
    // SDL_RenderCopy became SDL_RenderTexture, which takes float rects.
    const src = c.SDL_FRect{
        .x = @floatFromInt(g_sdl_renderer_rect.x),
        .y = @floatFromInt(g_sdl_renderer_rect.y),
        .w = @floatFromInt(g_sdl_renderer_rect.w),
        .h = @floatFromInt(g_sdl_renderer_rect.h),
    };
    _ = c.SDL_RenderTexture(g_renderer, g_texture, &src, null);
    _ = c.SDL_RenderPresent(g_renderer); // vsyncs to 60 FPS?
}

const kSdlRendererFuncs = RendererFuncs{
    .Initialize = &SdlRenderer_Init,
    .Destroy = &SdlRenderer_Destroy,
    .BeginDraw = &SdlRenderer_BeginDraw,
    .EndDraw = &SdlRenderer_EndDraw,
};

// The process entry point. Zig's test runner brings its own `main`, so this is
// only exported when building the game itself.
comptime {
    if (!builtin.is_test) @export(&zeldaMain, .{ .name = "main" });
}

fn zeldaMain(argc_in: c_int, argv_in: [*][*:0]u8) callconv(.c) c_int {
    var argc = argc_in - 1;
    var argv = argv_in + 1;
    var config_file: ?[*:0]const u8 = null;
    if (argc >= 2 and strcmp(argv[0], "--config") == 0) {
        config_file = argv[1];
        argc -= 2;
        argv += 2;
    } else {
        SwitchDirectory();
    }
    ParseConfigFile(config_file);
    LoadAssets();
    LoadLinkGraphics();

    ZeldaInitialize();
    const ppu: *Ppu = @ptrCast(@alignCast(g_zenv.ppu.?));
    ppu.extraLeftRight = @min(config.g_config.extended_aspect_ratio, kPpuExtraLeftRight);
    g_snes_width = @as(c_int, config.g_config.extended_aspect_ratio) * 2 + 256;
    g_snes_height = if (config.g_config.extend_y) 240 else 224;

    // Delay actually setting those features in ram until any snapshots finish playing.
    g_wanted_zelda_features = config.g_config.features0;

    g_ppu_render_flags = @as(u32, @intFromBool(config.g_config.new_renderer)) * kPpuRenderFlags_NewRenderer |
        @as(u32, @intFromBool(config.g_config.enhanced_mode7)) * kPpuRenderFlags_4x4Mode7 |
        @as(u32, @intFromBool(config.g_config.extend_y)) * kPpuRenderFlags_Height240 |
        @as(u32, @intFromBool(config.g_config.no_sprite_limits)) * kPpuRenderFlags_NoSpriteLimits;
    // audio_freq: Use common sampling rates (see user config file. values higher than 48000 are not supported.)
    if (config.g_config.audio_freq < 11025 or config.g_config.audio_freq > 48000)
        config.g_config.audio_freq = kDefaultFreq;

    // The MSU mixer only plays at the right pitch when the output runs at the
    // rate its decoder produces, so take that rate rather than asking the user
    // to match it by hand. Nothing is lost by overriding them: SDL3's stream
    // resamples the finished mix to whatever the device is actually running at,
    // so AudioFreq no longer has to name a rate the hardware supports.
    if (audio.MsuRequiredAudioFreq(config.g_config.enable_msu)) |msu_freq| {
        if (config.g_config.audio_freq != msu_freq) {
            _ = printf("MSU: using AudioFreq = %d, the rate its audio decodes at\n", @as(c_int, msu_freq));
            config.g_config.audio_freq = msu_freq;
        }
    }

    // ZeldaEnableMsu scales the volume ramp by audio_freq, so it has to run
    // after the rate above is settled.
    audio.ZeldaEnableMsu(config.g_config.enable_msu);
    ZeldaSetLanguage(config.g_config.language);

    // SDL3 folded SDL_WINDOW_FULLSCREEN_DESKTOP into SDL_WINDOW_FULLSCREEN: a
    // fullscreen window stays at the desktop resolution unless a display mode
    // is pinned on it, which is what fullscreen=2 does once the window exists.
    if (config.g_config.fullscreen != 0)
        g_win_flags |= c.SDL_WINDOW_FULLSCREEN;

    // Window scale (1=100%, 2=200%, 3=300%, etc.)
    g_current_window_scale = if (config.g_config.window_scale == 0)
        2
    else
        @intCast(intMin(config.g_config.window_scale, kMaxWindowScale));

    // Currently, the SPC/DSP implementation only supports up to stereo.
    if (config.g_config.audio_channels < 1 or config.g_config.audio_channels > 2)
        config.g_config.audio_channels = kDefaultChannels;

    // audio_samples: power of 2
    if (config.g_config.audio_samples <= 0 or
        (config.g_config.audio_samples & (config.g_config.audio_samples -% 1)) != 0)
        config.g_config.audio_samples = kDefaultSamples;

    // set up SDL
    if (builtin.os.tag == .macos) {
        // macOS's GameController framework and SDL's own HIDAPI driver both
        // claim some USB pads, so one controller enumerates twice under two
        // different mappings. Both then deliver an event per press, and where
        // the two mappings disagree about which button sits where, one press
        // fires two different bindings - a SNES pad ends up with B and A doing
        // the same thing. HIDAPI is the one that maps these correctly, so leave
        // GameController out of it. SDL_SetHint yields to the environment, so
        // SDL_JOYSTICK_MFI=1 still turns it back on.
        _ = c.SDL_SetHint(c.SDL_HINT_JOYSTICK_MFI, "0");
    }
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_GAMEPAD)) {
        _ = printf("Failed to init SDL: %s\n", c.SDL_GetError());
        return 1;
    }

    const custom_size = config.g_config.window_width != 0 and config.g_config.window_height != 0;
    const window_width = if (custom_size) config.g_config.window_width else @as(c_int, g_current_window_scale) * g_snes_width;
    const window_height = if (custom_size) config.g_config.window_height else @as(c_int, g_current_window_scale) * g_snes_height;

    if (config.g_config.output_method == kOutputMethod_OpenGL or
        config.g_config.output_method == kOutputMethod_OpenGL_ES)
    {
        g_win_flags |= c.SDL_WINDOW_OPENGL;
        opengl.OpenGLRenderer_Create(&g_renderer_funcs, config.g_config.output_method == kOutputMethod_OpenGL_ES);
    } else {
        g_renderer_funcs = kSdlRendererFuncs;
    }

    // SDL3 drops the x/y arguments; an unpositioned window is the default.
    const window = c.SDL_CreateWindow(kWindowTitle, window_width, window_height, g_win_flags);
    if (window == null) {
        _ = printf("Failed to create window: %s\n", c.SDL_GetError());
        return 1;
    }
    g_window = window;
    if (config.g_config.fullscreen == 2) {
        // Exclusive fullscreen: pin the closest real mode to the wanted size.
        var mode: c.SDL_DisplayMode = undefined;
        const display = c.SDL_GetDisplayForWindow(window);
        if (c.SDL_GetClosestFullscreenDisplayMode(display, window_width, window_height, 0.0, false, &mode))
            _ = c.SDL_SetWindowFullscreenMode(window, &mode);
    }
    _ = c.SDL_SetWindowHitTest(window, HitTestCallback, null);

    if (!g_renderer_funcs.Initialize.?(window))
        return 1;

    // SDL3's SDL_AudioSpec carries only the format; the buffer size moved to a
    // hint and the callback is passed to SDL_OpenAudioDeviceStream. The spec
    // describes what the app produces and the stream converts to the device,
    // so there is no "have" to read back.
    var spec: c.SDL_AudioSpec = std.mem.zeroes(c.SDL_AudioSpec);
    g_audio_mutex = c.SDL_CreateMutex();
    if (g_audio_mutex == null) Die("No mutex");

    if (config.g_config.enable_audio) {
        spec.freq = config.g_config.audio_freq;
        spec.format = c.SDL_AUDIO_S16;
        spec.channels = config.g_config.audio_channels;
        var samples_str: [16]u8 = undefined;
        _ = snprintf(&samples_str, samples_str.len, "%d", @as(c_int, config.g_config.audio_samples));
        _ = c.SDL_SetHint(c.SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, @ptrCast(&samples_str));
        g_audio_stream = c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, &AudioCallback, null);
        if (g_audio_stream == null) {
            _ = printf("Failed to open audio device: %s\n", c.SDL_GetError());
            return 1;
        }
        g_audio_channels = @intCast(spec.channels);
        g_frames_per_block = @divTrunc(534 * spec.freq, 32000);
        g_audiobuffer = @ptrCast(malloc(@as(usize, @intCast(g_frames_per_block)) * g_audio_channels * @sizeOf(i16)));
        g_audiobuffer_cur = g_audiobuffer;
        g_audiobuffer_end = g_audiobuffer;
        ApplyAudioVolume();
        // SDL_OpenAudioDeviceStream hands back a paused device.
        _ = c.SDL_ResumeAudioStreamDevice(g_audio_stream);
    }

    if (argc >= 1 and !g_run_without_emu)
        _ = LoadRom(argv[0]);

    makeSaveDir();

    ZeldaReadSram();

    // SDL3 enumerates joysticks by instance id instead of by index.
    var joystick_count: c_int = 0;
    if (c.SDL_GetJoysticks(&joystick_count)) |joysticks| {
        for (joysticks[0..@intCast(joystick_count)]) |id|
            OpenOneGamepad(id);
        c.SDL_free(joysticks);
    }

    var running = true;
    var event: c.SDL_Event = undefined;
    // SDL_GetTicks is 64-bit in SDL3.
    var lastTick = c.SDL_GetTicks();
    var curTick: u64 = 0;
    var frameCtr: u32 = 0;
    var audiopaused = true;

    if (config.g_config.autosave)
        HandleCommand(kKeys_Load + 0, true);

    while (running) {
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_GAMEPAD_ADDED => OpenOneGamepad(event.gdevice.which),
                c.SDL_EVENT_GAMEPAD_AXIS_MOTION => HandleGamepadAxisInput(event.gaxis.which, event.gaxis.axis, event.gaxis.value),
                c.SDL_EVENT_GAMEPAD_BUTTON_DOWN, c.SDL_EVENT_GAMEPAD_BUTTON_UP => {
                    const b = RemapSdlButton(event.gbutton.button);
                    if (b >= 0)
                        HandleGamepadInput(b, event.type == c.SDL_EVENT_GAMEPAD_BUTTON_DOWN);
                },
                c.SDL_EVENT_MOUSE_WHEEL => {
                    // SDL3 reports wheel deltas as floats.
                    if ((c.SDL_GetModState() & c.SDL_KMOD_CTRL) != 0 and event.wheel.y != 0)
                        ChangeWindowScale(if (event.wheel.y > 0) 1 else -1);
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    if (event.button.button == c.SDL_BUTTON_LEFT and event.button.down and event.button.clicks == 2) {
                        if ((g_win_flags & c.SDL_WINDOW_FULLSCREEN) == 0 and
                            (c.SDL_GetModState() & c.SDL_KMOD_SHIFT) != 0)
                        {
                            g_win_flags ^= c.SDL_WINDOW_BORDERLESS;
                            _ = c.SDL_SetWindowBordered(g_window, (g_win_flags & c.SDL_WINDOW_BORDERLESS) == 0);
                        }
                    }
                },
                c.SDL_EVENT_KEY_DOWN => HandleInput(event.key.key, event.key.mod, true),
                c.SDL_EVENT_KEY_UP => HandleInput(event.key.key, event.key.mod, false),
                c.SDL_EVENT_QUIT => running = false,
                else => {},
            }
        }

        if (g_quit_requested)
            running = false;

        if (g_paused != audiopaused) {
            audiopaused = g_paused;
            if (g_audio_stream) |stream|
                _ = if (audiopaused) c.SDL_PauseAudioStreamDevice(stream) else c.SDL_ResumeAudioStreamDevice(stream);
        }

        if (g_paused) {
            c.SDL_Delay(16);
            continue;
        }

        // Clear gamepad inputs when joypad directional inputs to avoid wonkiness
        var inputs = g_input1_state;
        if (g_input1_state & 0xf0 != 0)
            g_gamepad_buttons = 0;
        inputs |= g_gamepad_buttons;

        c.SDL_LockMutex(g_audio_mutex);
        const is_replay = ZeldaRunFrame(inputs);
        c.SDL_UnlockMutex(g_audio_mutex);

        // A replay is someone else's playthrough, so it doesn't shake the pad.
        if (is_replay) rumble.reset() else rumble.afterFrame(audio.lastSoundEffect1());

        frameCtr +%= 1;

        if ((g_turbo != (is_replay and g_replay_turbo)) and
            (frameCtr & (if (g_turbo) @as(u32, 0xf) else 0x7f)) != 0)
        {
            continue;
        }

        DrawPpuFrameWithPerf();

        if (config.g_config.display_perf_title) {
            var title: [60]u8 = undefined;
            _ = snprintf(&title, title.len, "%s | FPS: %d", kWindowTitle.ptr, g_curr_fps);
            _ = c.SDL_SetWindowTitle(g_window, @ptrCast(&title));
        }

        // if vsync isn't working, delay manually
        curTick = c.SDL_GetTicks();

        if (!config.g_config.disable_frame_delay) {
            const delays = [3]u8{ 17, 17, 16 }; // 60 fps
            lastTick +%= delays[frameCtr % 3];

            if (lastTick > curTick) {
                var delta = lastTick - curTick;
                if (delta > 500) {
                    lastTick = curTick -% 500;
                    delta = 500;
                }
                c.SDL_Delay(@intCast(delta));
            } else if (curTick -% lastTick > 500) {
                lastTick = curTick;
            }
        }
    }
    if (config.g_config.autosave)
        HandleCommand(kKeys_Save + 0, true);

    // clean sdl
    if (g_audio_stream) |stream| {
        _ = c.SDL_PauseAudioStreamDevice(stream);
        // Destroying a stream from SDL_OpenAudioDeviceStream closes its device.
        c.SDL_DestroyAudioStream(stream);
        g_audio_stream = null;
    }

    c.SDL_DestroyMutex(g_audio_mutex);
    free(g_audiobuffer);

    g_renderer_funcs.Destroy.?();

    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
    return 0;
}

const kFont = [100]u8{
    0x1c, 0x36, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x36, 0x1c,
    0x18, 0x1c, 0x1e, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7e,
    0x3e, 0x63, 0x60, 0x30, 0x18, 0x0c, 0x06, 0x03, 0x63, 0x7f,
    0x3e, 0x63, 0x60, 0x60, 0x3c, 0x60, 0x60, 0x60, 0x63, 0x3e,
    0x30, 0x38, 0x3c, 0x36, 0x33, 0x7f, 0x30, 0x30, 0x30, 0x78,
    0x7f, 0x03, 0x03, 0x03, 0x3f, 0x60, 0x60, 0x60, 0x63, 0x3e,
    0x1c, 0x06, 0x03, 0x03, 0x3f, 0x63, 0x63, 0x63, 0x63, 0x3e,
    0x7f, 0x63, 0x60, 0x60, 0x30, 0x18, 0x0c, 0x0c, 0x0c, 0x0c,
    0x3e, 0x63, 0x63, 0x63, 0x3e, 0x63, 0x63, 0x63, 0x63, 0x3e,
    0x3e, 0x63, 0x63, 0x63, 0x7e, 0x60, 0x60, 0x60, 0x30, 0x1e,
};

fn RenderDigit(dst_in: [*]u8, pitch: usize, digit: usize, color: u32, big: bool) void {
    const p = kFont[digit * 10 ..];
    var dst = dst_in;
    if (!big) {
        for (0..10) |y| {
            var v: u32 = p[y];
            var x: usize = 0;
            while (v != 0) : ({
                x += 1;
                v >>= 1;
            }) {
                if (v & 1 != 0) {
                    const row: [*]align(1) u32 = @ptrCast(dst);
                    row[x] = color;
                }
            }
            dst += pitch;
        }
    } else {
        for (0..10) |y| {
            var v: u32 = p[y];
            var x: usize = 0;
            while (v != 0) : ({
                x += 1;
                v >>= 1;
            }) {
                if (v & 1 != 0) {
                    const row: [*]align(1) u32 = @ptrCast(dst);
                    const row2: [*]align(1) u32 = @ptrCast(dst + pitch);
                    row[x * 2 + 1] = color;
                    row[x * 2] = color;
                    row2[x * 2 + 1] = color;
                    row2[x * 2] = color;
                }
            }
            dst += pitch * 2;
        }
    }
}

fn RenderNumber(dst: [*]u8, pitch: usize, n: c_int, big: bool) void {
    var buf: [32]u8 = undefined;
    _ = sprintf(&buf, "%d", n);
    const shift: u1 = @intFromBool(big);

    var s: usize = 0;
    var i: usize = 2 * 4;
    while (buf[s] != 0) : ({
        s += 1;
        i += 8 * 4;
    }) {
        RenderDigit(dst + ((pitch + i + 4) << shift), pitch, buf[s] - '0', 0x404040, big);
    }
    s = 0;
    i = 2 * 4;
    while (buf[s] != 0) : ({
        s += 1;
        i += 8 * 4;
    }) {
        RenderDigit(dst + (i << shift), pitch, buf[s] - '0', 0xffffff, big);
    }
}

const kKbdRemap = [13]u8{ 0, 4, 5, 6, 7, 2, 3, 8, 0, 9, 1, 10, 11 };

fn HandleCommand(j: u32, pressed: bool) void {
    if (j <= kKeys_Controls_Last) {
        if (pressed)
            g_input1_state |= @as(c_int, 1) << @intCast(kKbdRemap[j])
        else
            g_input1_state &= ~(@as(c_int, 1) << @intCast(kKbdRemap[j]));
        return;
    }

    if (j == kKeys_Turbo) {
        g_turbo = pressed;
        return;
    }

    // Everything that might access audio state
    // (like SaveLoad and Reset) must have the lock.
    c.SDL_LockMutex(g_audio_mutex);
    HandleCommand_Locked(j, pressed);
    c.SDL_UnlockMutex(g_audio_mutex);
}

pub export fn ZeldaApuLock() callconv(.c) void {
    c.SDL_LockMutex(g_audio_mutex);
}

pub export fn ZeldaApuUnlock() callconv(.c) void {
    c.SDL_UnlockMutex(g_audio_mutex);
}

fn HandleCommand_Locked(j: u32, pressed: bool) void {
    if (!pressed)
        return;
    // Loading, replaying or resetting changes health in one step, which the
    // rumble would otherwise take for a hit.
    if (j <= kKeys_ReplayRef_Last or j == kKeys_Reset)
        rumble.reset();
    if (j <= kKeys_Load_Last) {
        SaveLoadSlot(kSaveLoad_Load, @intCast(j - kKeys_Load));
    } else if (j <= kKeys_Save_Last) {
        SaveLoadSlot(kSaveLoad_Save, @intCast(j - kKeys_Save));
    } else if (j <= kKeys_Replay_Last) {
        SaveLoadSlot(kSaveLoad_Replay, @intCast(j - kKeys_Replay));
    } else if (j <= kKeys_LoadRef_Last) {
        SaveLoadSlot(kSaveLoad_Load, @intCast(256 + j - kKeys_LoadRef));
    } else if (j <= kKeys_ReplayRef_Last) {
        SaveLoadSlot(kSaveLoad_Replay, @intCast(256 + j - kKeys_ReplayRef));
    } else {
        switch (j) {
            kKeys_CheatLife => PatchCommand('w'),
            kKeys_CheatEquipment => PatchCommand('W'),
            kKeys_CheatKeys => PatchCommand('o'),
            kKeys_CheatWalkThroughWalls => PatchCommand('E'),
            kKeys_ClearKeyLog => PatchCommand('k'),
            kKeys_StopReplay => PatchCommand('l'),
            kKeys_Fullscreen => {
                g_win_flags ^= c.SDL_WINDOW_FULLSCREEN;
                _ = c.SDL_SetWindowFullscreen(g_window, (g_win_flags & c.SDL_WINDOW_FULLSCREEN) != 0);
                g_cursor = !g_cursor;
                // SDL3 split SDL_ShowCursor(toggle) into two argument-less calls.
                _ = if (g_cursor) c.SDL_ShowCursor() else c.SDL_HideCursor();
            },
            kKeys_Reset => ZeldaReset(true),
            kKeys_Pause => g_paused = !g_paused,
            // The C dims the screen here only on Windows.
            kKeys_PauseDimmed => g_paused = !g_paused,
            kKeys_ReplayTurbo => g_replay_turbo = !g_replay_turbo,
            kKeys_WindowBigger => ChangeWindowScale(1),
            kKeys_WindowSmaller => ChangeWindowScale(-1),
            kKeys_DisplayPerf => g_display_perf = !g_display_perf,
            kKeys_ToggleRenderer => g_ppu_render_flags ^= kPpuRenderFlags_NewRenderer,
            kKeys_VolumeUp, kKeys_VolumeDown => HandleVolumeAdjustment(if (j == kKeys_VolumeUp) 1 else -1),
            else => unreachable, // assert(0)
        }
    }
}

fn HandleInput(keyCode: c.SDL_Keycode, keyMod: c.SDL_Keymod, pressed: bool) void {
    const j = FindCmdForSdlKey(keyCode, keyMod);
    if (j != 0)
        HandleCommand(@intCast(j), pressed);
}

fn OpenOneGamepad(id: c.SDL_JoystickID) void {
    if (!c.SDL_IsGamepad(id)) return;
    // SDL queues an "added" event for pads that were already plugged in, so the
    // startup sweep and that event both reach here for the same id. Opening
    // twice is harmless - SDL hands back the same gamepad - but reporting it
    // twice is just noise.
    if (c.SDL_GetGamepadFromID(id) != null) return;
    const gamepad = c.SDL_OpenGamepad(id);
    if (gamepad == null) {
        std.debug.print("Could not open gamepad {d}: {s}\n", .{ id, c.SDL_GetError() });
        return;
    }
    // The bindings go by position, so print the letter SDL says sits at each
    // one. A pad whose printed faces disagree with this line is the usual cause
    // of "my buttons are swapped", and it says whether the fault is SDL's
    // mapping for the device or the [GamepadMap] section.
    // Whether it can rumble goes on the end, since plenty of pads, the
    // SNES-style ones included, have no motor to drive.
    const can_rumble = c.SDL_GetBooleanProperty(c.SDL_GetGamepadProperties(gamepad), c.SDL_PROP_GAMEPAD_CAP_RUMBLE_BOOLEAN, false);
    std.debug.print("Gamepad {d}: {s} [south={s} east={s} west={s} north={s}] rumble={s}\n", .{
        id,
        gamepadName(gamepad),
        buttonLabelName(gamepad, c.SDL_GAMEPAD_BUTTON_SOUTH),
        buttonLabelName(gamepad, c.SDL_GAMEPAD_BUTTON_EAST),
        buttonLabelName(gamepad, c.SDL_GAMEPAD_BUTTON_WEST),
        buttonLabelName(gamepad, c.SDL_GAMEPAD_BUTTON_NORTH),
        if (can_rumble) "yes" else "no",
    });
}

/// SDL_GetGamepadName returns a C string that may be null.
fn gamepadName(gamepad: ?*c.SDL_Gamepad) [*:0]const u8 {
    return c.SDL_GetGamepadName(gamepad) orelse "unknown";
}

/// The letter or shape printed on a face button, for the diagnostic above.
fn buttonLabelName(gamepad: ?*c.SDL_Gamepad, button: c_int) []const u8 {
    return switch (c.SDL_GetGamepadButtonLabel(gamepad, button)) {
        c.SDL_GAMEPAD_BUTTON_LABEL_A => "A",
        c.SDL_GAMEPAD_BUTTON_LABEL_B => "B",
        c.SDL_GAMEPAD_BUTTON_LABEL_X => "X",
        c.SDL_GAMEPAD_BUTTON_LABEL_Y => "Y",
        c.SDL_GAMEPAD_BUTTON_LABEL_CROSS => "Cross",
        c.SDL_GAMEPAD_BUTTON_LABEL_CIRCLE => "Circle",
        c.SDL_GAMEPAD_BUTTON_LABEL_SQUARE => "Square",
        c.SDL_GAMEPAD_BUTTON_LABEL_TRIANGLE => "Triangle",
        else => "?",
    };
}

/// SDL3 names the face buttons by position rather than by Xbox letter:
/// south is A, east is B, west is X and north is Y.
///
/// Position is what the bindings want, not the letter printed on the pad. The
/// stock [GamepadMap] line maps gamepad B to SNES A, A to SNES B, Y to SNES X
/// and X to SNES Y - a cross-map that lines up only if those names mean Xbox
/// labels, which sit at south/east/west/north. So a gamepad's south button has
/// to arrive here as kGamepadBtn_A whatever its face says, and the SNES pad
/// whose south button reads "B" still ends up driving SNES B.
fn RemapSdlButton(button: u8) c_int {
    return switch (button) {
        c.SDL_GAMEPAD_BUTTON_SOUTH => kGamepadBtn_A,
        c.SDL_GAMEPAD_BUTTON_EAST => kGamepadBtn_B,
        c.SDL_GAMEPAD_BUTTON_WEST => kGamepadBtn_X,
        c.SDL_GAMEPAD_BUTTON_NORTH => kGamepadBtn_Y,
        c.SDL_GAMEPAD_BUTTON_BACK => kGamepadBtn_Back,
        c.SDL_GAMEPAD_BUTTON_GUIDE => kGamepadBtn_Guide,
        c.SDL_GAMEPAD_BUTTON_START => kGamepadBtn_Start,
        c.SDL_GAMEPAD_BUTTON_LEFT_STICK => kGamepadBtn_L3,
        c.SDL_GAMEPAD_BUTTON_RIGHT_STICK => kGamepadBtn_R3,
        c.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER => kGamepadBtn_L1,
        c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER => kGamepadBtn_R1,
        c.SDL_GAMEPAD_BUTTON_DPAD_UP => kGamepadBtn_DpadUp,
        c.SDL_GAMEPAD_BUTTON_DPAD_DOWN => kGamepadBtn_DpadDown,
        c.SDL_GAMEPAD_BUTTON_DPAD_LEFT => kGamepadBtn_DpadLeft,
        c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT => kGamepadBtn_DpadRight,
        else => -1,
    };
}

fn HandleGamepadInput(button: c_int, pressed: bool) void {
    const bit = @as(u32, 1) << @intCast(button);
    if ((g_gamepad_modifiers & bit != 0) == pressed)
        return;
    g_gamepad_modifiers ^= bit;
    if (pressed)
        g_gamepad_last_cmd[@intCast(button)] = @intCast(FindCmdForGamepadButton(button, g_gamepad_modifiers));
    if (g_gamepad_last_cmd[@intCast(button)] != 0)
        HandleCommand(g_gamepad_last_cmd[@intCast(button)], pressed);
}

fn HandleVolumeAdjustment(volume_adjustment: c_int) void {
    // Upstream can drive the Windows system volume mixer from here
    // instead. This port always adjusts its own mix, on every platform.
    g_sdl_audio_mixer_volume = intMin(intMax(0, g_sdl_audio_mixer_volume +
        volume_adjustment * (kMixMaxVolume >> 4)), kMixMaxVolume);
    ApplyAudioVolume();
    _ = printf("[SDL mixer volume]=%i\n", g_sdl_audio_mixer_volume);
}

/// The volume used to be folded into each callback by SDL_MixAudioFormat. SDL3
/// scales the stream itself, with 1.0 meaning untouched samples.
fn ApplyAudioVolume() void {
    if (g_audio_stream) |stream|
        _ = c.SDL_SetAudioStreamGain(stream, @as(f32, @floatFromInt(g_sdl_audio_mixer_volume)) /
            @as(f32, @floatFromInt(kMixMaxVolume)));
}

/// Approximates atan2(y, x) normalized to the [0,4) range
/// with a maximum error of 0.1620 degrees
/// normalized_atan(x) ~ (b x + x^2) / (1 + 2 b x + x^2)
fn ApproximateAtan2(y: f32, x: f32) f32 {
    const sign_mask: u32 = 0x80000000;
    const b: f32 = 0.596227;
    // Extract the sign bits
    const ux_s = sign_mask & @as(u32, @bitCast(x));
    const uy_s = sign_mask & @as(u32, @bitCast(y));
    // Determine the quadrant offset
    const q: f32 = @floatFromInt((~ux_s & uy_s) >> 29 | ux_s >> 30);
    // Calculate the arctangent in the first quadrant
    var bxy_a = b * x * y;
    if (bxy_a < 0.0) bxy_a = -bxy_a; // avoid fabs
    const num = bxy_a + y * y;
    const atan_1q = num / (x * x + bxy_a + num + 0.000001);
    // Translate it to the proper quadrant
    const uatan_2q = (ux_s ^ uy_s) | @as(u32, @bitCast(atan_1q));
    return q + @as(f32, @bitCast(uatan_2q));
}

const kSegmentToButtons = [8]u8{
    1 << 4, // 0 = up
    1 << 4 | 1 << 7, // 1 = up, right
    1 << 7, // 2 = right
    1 << 7 | 1 << 5, // 3 = right, down
    1 << 5, // 4 = down
    1 << 5 | 1 << 6, // 5 = down, left
    1 << 6, // 6 = left
    1 << 6 | 1 << 4, // 7 = left, up
};

var last_gamepad_id: c.SDL_JoystickID = 0;
var last_x: c_int = 0;
var last_y: c_int = 0;

fn HandleGamepadAxisInput(gamepad_id: c.SDL_JoystickID, axis: u8, value: i16) void {
    if (axis == c.SDL_GAMEPAD_AXIS_LEFTX or axis == c.SDL_GAMEPAD_AXIS_LEFTY) {
        // ignore other gamepads unless they have a big input
        if (last_gamepad_id != gamepad_id) {
            if (value > -16000 and value < 16000)
                return;
            last_gamepad_id = gamepad_id;
            last_x = 0;
            last_y = 0;
        }
        if (axis == c.SDL_GAMEPAD_AXIS_LEFTX) last_x = value else last_y = value;
        var buttons: u8 = 0;
        if (last_x * last_x + last_y * last_y >= 10000 * 10000) {
            // in the non deadzone part, divide the circle into eight 45 degree
            // segments rotated by 22.5 degrees that control which direction to move.
            const angle = segmentAngle(@floatFromInt(last_y), @floatFromInt(last_x));
            buttons = kSegmentToButtons[(angle +% 16 +% 64) >> 5];
        }
        g_gamepad_buttons = buttons;
    } else if (axis == c.SDL_GAMEPAD_AXIS_LEFT_TRIGGER or axis == c.SDL_GAMEPAD_AXIS_RIGHT_TRIGGER) {
        if (value < 12000 or value >= 16000) // hysteresis
            HandleGamepadInput(if (axis == c.SDL_GAMEPAD_AXIS_LEFT_TRIGGER) kGamepadBtn_L2 else kGamepadBtn_R2, value >= 12000);
    }
}

/// The C rounds the [0,4) angle into a byte; 4.0 wraps to 0 exactly as the
/// (uint8)(int) cast pair does.
fn segmentAngle(y: f32, x: f32) u8 {
    const v = ApproximateAtan2(y, x) * 64.0 + 0.5;
    const i: i32 = @intFromFloat(v);
    return @truncate(@as(u32, @bitCast(i)));
}

fn LoadRom(filename: [*:0]const u8) bool {
    var length: usize = 0;
    const file = util.ReadWholeFile(filename, &length) orelse Die("Failed to read file");
    const result = emu.EmuInitialize(file, length);
    free(file);
    return result;
}

fn ParseLinkGraphics(file: [*]const u8, length: usize) bool {
    if (length < 27 or !std.mem.eql(u8, file[0..4], "ZSPR"))
        return false;
    const pixel_offs = std.mem.readInt(u32, file[9..13], .little);
    const pixel_length = std.mem.readInt(u16, file[13..15], .little);
    const palette_offs = std.mem.readInt(u32, file[15..19], .little);
    const palette_length = std.mem.readInt(u16, file[19..21], .little);
    if (@as(u64, pixel_offs) + pixel_length > length or
        @as(u64, palette_offs) + palette_length > length or
        pixel_length != 0x7000)
        return false;
    if (g_asset_sizes[81] != 150 or g_asset_sizes[57] != 0x7000)
        Die("ParseLinkGraphics: Invalid asset sizes");
    @memcpy(assetPtr(57)[0..0x7000], (file + pixel_offs)[0..0x7000]);
    if (palette_length >= 120)
        @memcpy(assetPtr(81)[0..120], (file + palette_offs)[0..120]);
    if (palette_length >= 124)
        @memcpy(@as([*]u8, @ptrCast(&kGlovesColor))[0..4], (file + palette_offs + 120)[0..4]);
    return true;
}

fn LoadLinkGraphics() void {
    if (config.g_config.link_graphics) |lg| {
        std.debug.print("Loading Link Graphics: {s}\n", .{lg});
        var length: usize = 0;
        const file = util.ReadWholeFile(lg, &length);
        if (file == null or !ParseLinkGraphics(file.?, length))
            Die("Unable to load file");
        free(file);
    }
}

const kAssetsSig = [48]u8{
    90, 101, 108, 100, 97,  51,  95,  118, 48,  32,  32,  32,
    32, 32,  10,  0,   27,  174, 233, 45,  74,  174, 252, 50,
    49, 27,  153, 197, 27,  43,  216, 197, 132, 101, 173, 169,
    36, 108, 15,  155, 176, 169, 57,  131, 174, 101, 51,  207,
};

fn LoadAssets() void {
    var length: usize = 0;
    var data = util.ReadWholeFile("zelda3_assets.dat", &length);
    if (data == null) {
        var bps_length: usize = 0;
        var bps_src_length: usize = 0;
        const bps = util.ReadWholeFile("zelda3_assets.bps", &bps_length) orelse
            Die("Failed to read zelda3_assets.dat. Please see the README for information about how you get this file.");
        const bps_src = util.ReadWholeFile("zelda3.sfc", &bps_src_length) orelse
            Die("Missing file: zelda3.sfc");
        data = util.ApplyBps(bps_src, bps_src_length, bps, bps_length, &length);
        if (data == null)
            Die("Unable to apply zelda3_assets.bps. Please make sure you got the right version of 'zelda3.sfc'");
    }
    const d = data.?;

    if (length < 16 + 32 + 32 + 8 + kNumberOfAssets * 4 or
        !std.mem.eql(u8, d[0..48], &kAssetsSig) or
        std.mem.readInt(u32, d[80..84], .little) != kNumberOfAssets)
        Die("Invalid assets file");

    var offset: u32 = 88 + kNumberOfAssets * 4 + std.mem.readInt(u32, d[84..88], .little);

    for (0..kNumberOfAssets) |i| {
        const size = std.mem.readInt(u32, d[88 + i * 4 ..][0..4], .little);
        offset = (offset + 3) & ~@as(u32, 3);
        if (@as(u64, offset) + size > length)
            Die("Assets file corruption");
        g_asset_sizes[i] = size;
        g_asset_ptrs[i] = d + offset;
        offset += size;
    }

    if (config.g_config.features0 & kFeatures0_DimFlashes != 0) { // patch dungeon floor palettes
        const pal: [*]align(1) u16 = @ptrCast(assetPtr(79));
        pal[0x484] = 0x70;
        pal[0x485] = 0x95;
        pal[0x486] = 0x57;
    }
}

/// Go some steps up and find zelda3.ini
fn SwitchDirectory() void {
    var buf: [4096]u8 = undefined;
    if (getcwd(&buf, buf.len - 32) == null)
        return;
    var pos = std.mem.len(@as([*:0]const u8, @ptrCast(&buf)));

    var step: c_int = 0;
    while (pos != 0 and step < 3) : (step += 1) {
        @memcpy(buf[pos..][0..12], "/zelda3.ini\x00");
        const f = fopen(@ptrCast(&buf), "rb");
        if (f) |file| {
            _ = fclose(file);
            buf[pos] = 0;
            if (step != 0) {
                _ = printf("Found zelda3.ini in %s\n", &buf);
                const err = chdir(@ptrCast(&buf));
                _ = err;
            }
            return;
        }
        pos -= 1;
        while (pos != 0 and buf[pos] != '/' and buf[pos] != '\\')
            pos -= 1;
    }
}

pub export fn FindInAssetArray(asset: c_int, idx: c_int) callconv(.c) MemBlk {
    return util.FindIndexInMemblk(MemBlk{
        .ptr = g_asset_ptrs[@intCast(asset)],
        .size = g_asset_sizes[@intCast(asset)],
    }, @intCast(idx));
}

const testing = std.testing;

test "the key command enum matches the C numbering" {
    try testing.expectEqual(0, kKeys_Null);
    try testing.expectEqual(1, kKeys_Controls);
    try testing.expectEqual(12, kKeys_Controls_Last);
    try testing.expectEqual(13, kKeys_Load);
    try testing.expectEqual(32, kKeys_Load_Last);
    try testing.expectEqual(33, kKeys_Save);
    try testing.expectEqual(53, kKeys_Replay);
    try testing.expectEqual(73, kKeys_LoadRef);
    try testing.expectEqual(93, kKeys_ReplayRef);
    try testing.expectEqual(113, kKeys_CheatLife);
    try testing.expectEqual(123, kKeys_Turbo);
    try testing.expectEqual(130, kKeys_VolumeDown);
    try testing.expectEqual(131, kKeys_Total);
}

test "gamepad buttons map onto the SDL gamepad enum" {
    try testing.expectEqual(kGamepadBtn_A, RemapSdlButton(c.SDL_GAMEPAD_BUTTON_SOUTH));
    try testing.expectEqual(kGamepadBtn_DpadRight, RemapSdlButton(c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT));
    try testing.expectEqual(kGamepadBtn_R1, RemapSdlButton(c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER));
    // Anything unknown is rejected rather than mapped.
    try testing.expectEqual(-1, RemapSdlButton(200));
    try testing.expectEqual(17, kGamepadBtn_Count);
}

test "the approximate atan2 tracks the real one" {
    // Normalized to [0,4) instead of radians, so scale before comparing.
    const cases = [_][2]f32{
        .{ 1, 0 },  .{ 1, 1 },   .{ 0, 1 },   .{ -1, 1 },
        .{ -1, 0 }, .{ -1, -1 }, .{ 0, -1 },  .{ 1, -1 },
        .{ 3, 4 },  .{ -7, 2 },  .{ 100, 5 }, .{ -3, -9 },
    };
    for (cases) |yx| {
        const y = yx[0];
        const x = yx[1];
        const got = ApproximateAtan2(y, x);
        var want = std.math.atan2(y, x) / (std.math.pi / 2.0);
        if (want < 0) want += 4.0;
        const diff = @abs(got - want);
        // The comment promises 0.1620 degrees; 4 units == 360 degrees.
        try testing.expect(@min(diff, 4.0 - diff) < 0.0025);
    }
}

test "stick angles fall into the eight movement segments" {
    // Up on a gamepad is negative y, and the table's entry 0 is up.
    try testing.expectEqual(@as(u8, 1 << 4), kSegmentToButtons[0]);
    try testing.expectEqual(@as(u8, 1 << 7), kSegmentToButtons[2]);
    try testing.expectEqual(@as(u8, 1 << 5), kSegmentToButtons[4]);
    try testing.expectEqual(@as(u8, 1 << 6), kSegmentToButtons[6]);
    // Every segment sets one or two direction bits and nothing else.
    for (kSegmentToButtons) |b| {
        try testing.expect(b & 0x0f == 0);
        const n = @popCount(b);
        try testing.expect(n == 1 or n == 2);
    }
    // The rotation puts a pure axis reading in the middle of its segment.
    const idx = (segmentAngle(0, 32000) +% 16 +% 64) >> 5;
    try testing.expectEqual(@as(u8, 1 << 7), kSegmentToButtons[idx]); // right
}

test "the keyboard remap covers every control key" {
    try testing.expectEqual(13, kKbdRemap.len);
    // Entries index joypad bits, so none may exceed 11.
    for (kKbdRemap) |v|
        try testing.expect(v <= 11);
}

test "the digit font holds ten 10-row glyphs" {
    try testing.expectEqual(100, kFont.len);
    // '1' is a narrow glyph and '0' is a ring; spot-check both.
    try testing.expectEqual(@as(u8, 0x1c), kFont[0]);
    try testing.expectEqual(@as(u8, 0x7e), kFont[19]);
}

test "rendering a digit lights the pixels its glyph names" {
    const pitch = 64 * @sizeOf(u32);
    var fb = [_]u8{0} ** (pitch * 16);
    RenderDigit(&fb, pitch, 1, 0xffffff, false);
    // Row 0 of '1' is 0x18 == bits 3 and 4.
    const row0: [*]align(1) u32 = @ptrCast(&fb);
    try testing.expectEqual(@as(u32, 0), row0[2]);
    try testing.expectEqual(@as(u32, 0xffffff), row0[3]);
    try testing.expectEqual(@as(u32, 0xffffff), row0[4]);
    try testing.expectEqual(@as(u32, 0), row0[5]);
    // Last row is 0x7e == bits 1..6.
    const row9: [*]align(1) u32 = @ptrCast(fb[pitch * 9 ..]);
    try testing.expectEqual(@as(u32, 0), row9[0]);
    try testing.expectEqual(@as(u32, 0xffffff), row9[1]);
    try testing.expectEqual(@as(u32, 0xffffff), row9[6]);
    try testing.expectEqual(@as(u32, 0), row9[7]);
}

test "the assets signature is the 48 bytes the loader checks" {
    try testing.expectEqual(48, kAssetsSig.len);
    try testing.expectEqualSlices(u8, "Zelda3_v0     \n", kAssetsSig[0..15]);
    try testing.expectEqual(@as(u8, 0), kAssetsSig[15]);
    try testing.expectEqual(@as(u8, 207), kAssetsSig[47]);
}

test "the frame delay pattern averages to 60 fps" {
    const delays = [3]u8{ 17, 17, 16 };
    var total: u32 = 0;
    for (delays) |d| total += d;
    try testing.expectEqual(50, total); // 3 frames per 50ms == 60fps
}
