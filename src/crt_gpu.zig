//! The CRT looks (crt.zig), drawn on the GPU through SDL's renderer.
//!
//! No shaders: just textures drawn into textures with SDL's blend modes, and
//! a mesh of triangles for the curve, which every backend it has does on the
//! GPU, Metal, Direct3D, Vulkan or OpenGL alike. Each frame:
//!
//! 1. The composite smear, at the SNES's size: the frame drawn half a pixel
//!    to the left and half to the right with smooth filtering, each of which
//!    averages a pixel with its neighbor, and the two averaged, which comes to
//!    a quarter of each neighbor and half the pixel. The slight smear is half
//!    that and half the frame as it was.
//! 2. The afterglow: the last frame's picture blended in, a share of it, so
//!    what moves fades rather than vanishing. A still picture settles on
//!    itself exactly, no brighter and no hazier.
//! 3. The frame drawn `scale` times the size, square pixels, into a texture
//!    the size it'll be shown.
//! 4. The gain: the same drawn again on top, added, at the part of the gain
//!    over one.
//! 5. The pattern of lines and phosphors (crt.pattern), made once, multiplied
//!    in.
//! 6. The glow and the halation: the frame shrunk to a quarter, an eighth and
//!    a sixteenth with smooth filtering, which blurs it more each time,
//!    stretched back over the top and added, the widest tinted red.
//!
//! With SDL's GPU renderer, steps 1, 3, 4 and 5 are one fragment shader
//! instead (shaders/crt.frag): beams whose width follows their brightness,
//! the mask in linear light, a composite signal that blurs color apart from
//! brightness, and the red and blue beams a little off the green. Without it
//! (the software renderer, or a GPU SDL can't use that way) the steps above
//! stand in.
//!
//! Then the result goes to the window, flat or on a curved mesh, under a
//! bezel or with just its corners rounded.
const std = @import("std");
const c = @import("sdl.zig").c;
const crt = @import("crt.zig");

// ------------------------------------------------------------ the shaders

/// A fragment shader of ours, in the forms SDL's GPU renderer can take, and
/// the render state it's drawn with once it's made.
const Shader = struct {
    spirv: []const u8,
    msl: []const u8,
    shader: ?*c.SDL_GPUShader = null,
    state: ?*c.SDL_GPURenderState = null,

    fn make(self: *Shader, r: *c.SDL_Renderer, dev: *c.SDL_GPUDevice, formats: c.SDL_GPUShaderFormat) void {
        var info = std.mem.zeroes(c.SDL_GPUShaderCreateInfo);
        if (formats & c.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
            info.code = self.spirv.ptr;
            info.code_size = self.spirv.len;
            info.entrypoint = "main";
            info.format = c.SDL_GPU_SHADERFORMAT_SPIRV;
        } else if (formats & c.SDL_GPU_SHADERFORMAT_MSL != 0) {
            info.code = self.msl.ptr;
            info.code_size = self.msl.len;
            info.entrypoint = "main0";
            info.format = c.SDL_GPU_SHADERFORMAT_MSL;
        } else return;
        info.stage = c.SDL_GPU_SHADERSTAGE_FRAGMENT;
        info.num_samplers = 1;
        info.num_uniform_buffers = 1;
        const shader = c.SDL_CreateGPUShader(dev, &info) orelse {
            std.debug.print("CRT shader: {s}\n", .{c.SDL_GetError()});
            return;
        };
        var state_info = std.mem.zeroes(c.SDL_GPURenderStateCreateInfo);
        state_info.fragment_shader = shader;
        const state = c.SDL_CreateGPURenderState(r, &state_info) orelse {
            std.debug.print("CRT shader: {s}\n", .{c.SDL_GetError()});
            c.SDL_ReleaseGPUShader(dev, shader);
            return;
        };
        self.shader = shader;
        self.state = state;
    }

    fn destroy(self: *Shader, dev: ?*c.SDL_GPUDevice) void {
        if (self.state) |st| c.SDL_DestroyGPURenderState(st);
        if (self.shader) |sh| c.SDL_ReleaseGPUShader(dev, sh);
        self.state = null;
        self.shader = null;
    }

    /// Draws `tex` over the current target through this shader, with these
    /// settings.
    fn draw(self: *Shader, r: *c.SDL_Renderer, tex: *c.SDL_Texture, params: anytype) void {
        _ = c.SDL_SetGPURenderStateFragmentUniforms(self.state, 0, params, @sizeOf(@TypeOf(params.*)));
        _ = c.SDL_SetGPURenderState(r, self.state);
        drawAll(r, tex, null, NONE, NEAREST, gray(1), 1, null);
        _ = c.SDL_SetGPURenderState(r, null);
    }
};

var g_device: ?*c.SDL_GPUDevice = null;
var g_crt: Shader = .{ .spirv = @embedFile("shaders/crt.frag.spv"), .msl = @embedFile("shaders/crt.frag.msl") };
var g_ntsc: Shader = .{ .spirv = @embedFile("shaders/ntsc.frag.spv"), .msl = @embedFile("shaders/ntsc.frag.msl") };
var g_xbr: Shader = .{ .spirv = @embedFile("shaders/xbr.frag.spv"), .msl = @embedFile("shaders/xbr.frag.msl") };
/// Frames drawn, for the NTSC carrier's phase, which turns every frame.
var g_frame_count: u32 = 0;

/// crt.frag's settings, as it lays out its Params block.
const Params = extern struct {
    src: [4]f32,
    dst: [4]f32,
    beam: [4]f32,
    signal: [4]f32,
};

/// ntsc.frag's.
const NtscParams = extern struct {
    src: [4]f32,
    signal: [4]f32,
    extra: [4]f32,
};

/// xbr.frag's.
const XbrParams = extern struct {
    src: [4]f32,
    out_scale: [4]f32,
};

/// Sets the shaders up on a renderer that's SDL's GPU one. Anything else, or
/// shaders the device won't take, leaves the steps without them.
pub fn init(r: *c.SDL_Renderer) void {
    const dev: *c.SDL_GPUDevice = @ptrCast(c.SDL_GetPointerProperty(c.SDL_GetRendererProperties(r), c.SDL_PROP_RENDERER_GPU_DEVICE_POINTER, null) orelse return);
    const formats = c.SDL_GetGPUShaderFormats(dev);
    g_device = dev;
    g_crt.make(r, dev, formats);
    if (g_crt.state != null) {
        g_ntsc.make(r, dev, formats);
        g_xbr.make(r, dev, formats);
    }
}

/// HDR, when the renderer's drawing in linear light to a display that has
/// light to spare past white: what white is, and how far past it can go.
pub const Hdr = struct { white: f32, headroom: f32 };

/// The renderer's HDR, if it's on: only with the HDR setting, which asks for
/// linear light, and on a display in HDR mode. Read every frame, as moving
/// the window to another display can change it.
pub fn hdrOf(r: *c.SDL_Renderer) ?Hdr {
    const props = c.SDL_GetRendererProperties(r);
    if (!c.SDL_GetBooleanProperty(props, c.SDL_PROP_RENDERER_HDR_ENABLED_BOOLEAN, false)) return null;
    const white = c.SDL_GetFloatProperty(props, c.SDL_PROP_RENDERER_SDR_WHITE_POINT_FLOAT, 1);
    const headroom = c.SDL_GetFloatProperty(props, c.SDL_PROP_RENDERER_HDR_HEADROOM_FLOAT, 1);
    if (headroom <= 1) return null;
    return .{ .white = white, .headroom = headroom };
}

/// How much of the light a mask lets through, on average across it.
fn maskAverage(l: crt.Look, scale: f32) f32 {
    const d = l.mask_through;
    return switch (l.mask) {
        .none => 1,
        .aperture, .shadow, .slot => (1 + 2 * d) / 3,
        .lcd => 1 - (1 - d) * (2 * scale - 1) / (scale * scale),
    };
}

/// Says once, at the start, what the CRT looks will be drawn with: the GPU
/// shaders, on which of SDL's GPU backends, or the simpler steps without
/// them, and why.
pub fn report(r: *c.SDL_Renderer) void {
    const raw_name = c.SDL_GetRendererName(r);
    const name: []const u8 = if (raw_name != null) std.mem.span(raw_name) else "?";
    if (g_crt.state != null) {
        const raw = c.SDL_GetGPUDeviceDriver(g_device);
        const backend: []const u8 = if (raw != null) std.mem.span(raw) else "?";
        std.debug.print("Graphics: SDL's GPU renderer on {s}, with the CRT shaders\n", .{backend});
    } else if (g_device != null) {
        std.debug.print("Graphics: SDL's GPU renderer, but the CRT shaders wouldn't load; the CRT filters draw without them\n", .{});
    } else {
        std.debug.print("Graphics: the {s} renderer, without SDL's GPU one; the CRT filters draw without their shaders\n", .{name});
    }
}

/// Whether the shader's there to draw with.
pub fn shaderReady() bool {
    return g_crt.state != null;
}

fn maskNumber(m: crt.Mask) f32 {
    return switch (m) {
        .none => 0,
        .aperture => 1,
        .slot => 2,
        .shadow => 3,
        .lcd => 4,
    };
}

const Target = struct {
    tex: ?*c.SDL_Texture = null,
    w: c_int = 0,
    h: c_int = 0,
    format: c.SDL_PixelFormat = c.SDL_PIXELFORMAT_ARGB8888,

    /// A texture to draw into, this size, made afresh when the size changes.
    fn get(self: *Target, r: *c.SDL_Renderer, w: c_int, h: c_int) ?*c.SDL_Texture {
        return self.getAs(r, w, h, c.SDL_PIXELFORMAT_ARGB8888);
    }

    /// The same, in a format of its own: floats, for light past white.
    fn getAs(self: *Target, r: *c.SDL_Renderer, w: c_int, h: c_int, format: c.SDL_PixelFormat) ?*c.SDL_Texture {
        const ww = @max(w, 1);
        const hh = @max(h, 1);
        if (self.tex == null or self.w != ww or self.h != hh or self.format != format) {
            if (self.tex) |t| c.SDL_DestroyTexture(t);
            self.tex = c.SDL_CreateTexture(r, format, c.SDL_TEXTUREACCESS_TARGET, ww, hh);
            self.w = ww;
            self.h = hh;
            self.format = format;
        }
        return self.tex;
    }

    fn destroy(self: *Target) void {
        if (self.tex) |t| c.SDL_DestroyTexture(t);
        self.* = .{};
    }
};

var g_smear: Target = .{};
/// The NTSC signal, decoded, four samples to a SNES pixel across.
var g_signal: Target = .{};
/// The afterglow's two pictures, this frame's and last, which swap.
var g_trail: [2]Target = .{ .{}, .{} };
var g_trail_at: usize = 0;
var g_trail_fresh = true;
var g_big: Target = .{};
var g_glow1: Target = .{};
var g_glow2: Target = .{};
var g_glow3: Target = .{};
/// The bezel with the screen's light reflected in it, made each frame.
var g_frame: Target = .{};

/// A texture made on the CPU, and what it was made for.
const Made = struct {
    tex: ?*c.SDL_Texture = null,
    key: [5]usize = .{ 0, 0, 0, 0, 0 },

    fn destroy(self: *Made) void {
        if (self.tex) |t| c.SDL_DestroyTexture(t);
        self.* = .{};
    }
};

var g_pattern: Made = .{};
var g_bezel: Made = .{};

fn upload(r: *c.SDL_Renderer, slot: *Made, key: [5]usize, w: usize, h: usize, format: c.SDL_PixelFormat, pixels: []const u32) ?*c.SDL_Texture {
    if (slot.tex) |t| c.SDL_DestroyTexture(t);
    slot.* = .{};
    const t = c.SDL_CreateTexture(r, format, c.SDL_TEXTUREACCESS_STATIC, @intCast(w), @intCast(h)) orelse return null;
    _ = c.SDL_UpdateTexture(t, null, pixels.ptr, @intCast(w * 4));
    slot.* = .{ .tex = t, .key = key };
    return t;
}

fn patternTexture(r: *c.SDL_Renderer, l: crt.Look, w: usize, h: usize, scale: usize) ?*c.SDL_Texture {
    const key = [5]usize{ @truncate(std.hash.Wyhash.hash(0, std.mem.asBytes(&l))), w, h, scale, 1 };
    if (g_pattern.tex != null and std.mem.eql(usize, &g_pattern.key, &key)) return g_pattern.tex;
    const pixels = std.heap.c_allocator.alloc(u32, w * scale * h * scale) catch return null;
    defer std.heap.c_allocator.free(pixels);
    crt.pattern(l, w, h, scale, pixels);
    const t = upload(r, &g_pattern, key, w * scale, h * scale, c.SDL_PIXELFORMAT_XRGB8888, pixels) orelse return null;
    _ = c.SDL_SetTextureScaleMode(t, c.SDL_SCALEMODE_NEAREST);
    _ = c.SDL_SetTextureBlendMode(t, c.SDL_BLENDMODE_MOD);
    return t;
}

fn bezelTexture(r: *c.SDL_Renderer, w: usize, h: usize, inset: f32, radius: f32, frame: bool) ?*c.SDL_Texture {
    const key = [5]usize{ w, h, @intFromFloat(inset * 16), @intFromFloat(radius * 16), @as(usize, @intFromBool(frame)) + 1 };
    if (g_bezel.tex != null and std.mem.eql(usize, &g_bezel.key, &key)) return g_bezel.tex;
    const pixels = std.heap.c_allocator.alloc(u32, w * h) catch return null;
    defer std.heap.c_allocator.free(pixels);
    crt.bezel(w, h, inset, radius, frame, pixels);
    const t = upload(r, &g_bezel, key, w, h, c.SDL_PIXELFORMAT_ARGB8888, pixels) orelse return null;
    _ = c.SDL_SetTextureScaleMode(t, c.SDL_SCALEMODE_LINEAR);
    return t;
}

fn rect(x: f32, y: f32, w: anytype, h: anytype) c.SDL_FRect {
    return .{ .x = x, .y = y, .w = @floatFromInt(w), .h = @floatFromInt(h) };
}

/// Draws `tex` (its `src` part) over `dst`, or the whole of the current
/// target.
fn drawAll(r: *c.SDL_Renderer, tex: *c.SDL_Texture, src: ?*const c.SDL_FRect, blend: c.SDL_BlendMode, scale_mode: c.SDL_ScaleMode, mod: [3]f32, alpha: f32, dst: ?*const c.SDL_FRect) void {
    _ = c.SDL_SetTextureBlendMode(tex, blend);
    _ = c.SDL_SetTextureScaleMode(tex, scale_mode);
    _ = c.SDL_SetTextureColorModFloat(tex, mod[0], mod[1], mod[2]);
    _ = c.SDL_SetTextureAlphaModFloat(tex, alpha);
    _ = c.SDL_RenderTexture(r, tex, src, dst);
}

fn gray(v: f32) [3]f32 {
    return .{ v, v, v };
}

const NEAREST = c.SDL_SCALEMODE_NEAREST;
const LINEAR = c.SDL_SCALEMODE_LINEAR;
const NONE = c.SDL_BLENDMODE_NONE;
const BLEND = c.SDL_BLENDMODE_BLEND;
const ADD = c.SDL_BLENDMODE_ADD;

/// The look made at the SNES's size and the widest of the blurs, to show.
pub const Frame = struct {
    picture: *c.SDL_Texture,
    /// The most blurred copy, for the bezel's reflection, when there is one.
    haze: ?*c.SDL_Texture,
};

/// Draws the frame, `game`'s `src` part, `snes_w` by `snes_h` SNES pixels,
/// with the look, into a texture `scale` times the size, and hands that
/// back for showing. Null if a texture couldn't be had; the plain frame is
/// shown instead.
/// With `pixel_art` and no look, the picture's drawn with xbr.frag instead.
/// With `hdr`, the shader draws in linear light past white, so the mask's
/// lost light comes back as brightness the display really has.
pub fn draw(r: *c.SDL_Renderer, game: *c.SDL_Texture, src: c.SDL_FRect, snes_w: c_int, snes_h: c_int, preset: crt.Preset, tuning: crt.Tuning, scale: u8, want_haze: bool, pixel_art: bool, hdr: ?Hdr) ?Frame {
    const l = crt.tuned(preset, tuning);
    const s: c_int = scale;
    const before = c.SDL_GetRenderTarget(r);
    defer _ = c.SDL_SetRenderTarget(r, before);
    // The game's texture goes back to drawing as itself afterwards.
    defer {
        _ = c.SDL_SetTextureBlendMode(game, NONE);
        _ = c.SDL_SetTextureColorModFloat(game, 1, 1, 1);
        _ = c.SDL_SetTextureAlphaModFloat(game, 1);
    }
    const full = rect(0, 0, snes_w, snes_h);

    const shaded = g_crt.state != null and preset != .off;
    const smoothed = !shaded and pixel_art and g_xbr.state != null;
    g_frame_count +%= 1;

    // 1. The smear, or for the shader, which does its own, the frame copied
    // to a texture of its own size, which the shader takes whole.
    var source = game;
    var source_rect: ?*const c.SDL_FRect = &src;
    if (shaded or smoothed) {
        const copy = g_smear.get(r, snes_w, snes_h) orelse return null;
        _ = c.SDL_SetRenderTarget(r, copy);
        drawAll(r, game, &src, NONE, NEAREST, gray(1), 1, &full);
        source = copy;
        source_rect = null;
    } else if (l.blur != 0) {
        const smear = g_smear.get(r, snes_w, snes_h) orelse return null;
        _ = c.SDL_SetRenderTarget(r, smear);
        _ = c.SDL_SetRenderDrawColor(r, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(r);
        const left = rect(-0.5, 0, snes_w, snes_h);
        const right = rect(0.5, 0, snes_w, snes_h);
        drawAll(r, game, &src, NONE, LINEAR, gray(1), 1, &left);
        drawAll(r, game, &src, BLEND, LINEAR, gray(1), 0.5, &right);
        if (l.blur == 1) drawAll(r, game, &src, BLEND, NEAREST, gray(1), 0.5, &full);
        source = smear;
        source_rect = null;
    }

    // 2. The afterglow.
    if (l.afterglow > 0) {
        const now = g_trail[g_trail_at].get(r, snes_w, snes_h) orelse return null;
        const last = g_trail[1 - g_trail_at].get(r, snes_w, snes_h) orelse return null;
        _ = c.SDL_SetRenderTarget(r, now);
        drawAll(r, source, source_rect, NONE, NEAREST, gray(1), 1, &full);
        if (!g_trail_fresh) drawAll(r, last, null, BLEND, NEAREST, gray(1), l.afterglow, null);
        g_trail_fresh = false;
        g_trail_at = 1 - g_trail_at;
        source = now;
        source_rect = null;
    } else {
        g_trail_fresh = true;
    }

    // 3. The frame at its new size.
    const hdr_on = shaded and hdr != null;
    const big = g_big.getAs(r, snes_w * s, snes_h * s, if (hdr_on) c.SDL_PIXELFORMAT_RGBA64_FLOAT else c.SDL_PIXELFORMAT_ARGB8888) orelse return null;
    _ = c.SDL_SetRenderTarget(r, big);
    _ = c.SDL_SetRenderDrawColor(r, 0, 0, 0, 255);
    _ = c.SDL_RenderClear(r);
    if (shaded) {
        const fw: f32 = @floatFromInt(snes_w);
        const fh: f32 = @floatFromInt(snes_h);
        // The composite signal, made and decoded, when the look has one and
        // the shader for it's there; the CRT shader then reads that, four
        // samples to a pixel, instead of the frame and its own simple blur.
        var picture = source;
        var across: f32 = 1;
        var luma_blur = l.luma_blur;
        var chroma_blur = l.chroma_blur;
        if (l.ntsc > 0 and g_ntsc.state != null) ntsc: {
            const signal = g_signal.get(r, snes_w * 4, snes_h) orelse break :ntsc;
            _ = c.SDL_SetRenderTarget(r, signal);
            const np = NtscParams{
                .src = .{ fw, fh, 1 / fw, 1 / fh },
                .signal = .{ @floatFromInt(g_frame_count & 1), l.ntsc, l.ntsc_chroma, l.ntsc_luma },
                .extra = .{ l.ntsc_ring, l.ntsc_ghost, l.ntsc_noise, @floatFromInt(g_frame_count % 4096) },
            };
            g_ntsc.draw(r, source, &np);
            _ = c.SDL_SetRenderTarget(r, big);
            picture = signal;
            across = 4;
            luma_blur = 0;
            chroma_blur = 0;
        }
        // In HDR, the gain makes up for the mask exactly, as far as the
        // display can go; the shader then gives out linear light, scaled to
        // its white.
        var gain = l.shader_gain;
        var linear_white: f32 = 0;
        if (hdr_on) {
            const h = hdr.?;
            gain = std.math.clamp(@max(l.shader_gain, 1 / maskAverage(l, @floatFromInt(s))), 1, h.headroom);
            linear_white = h.white;
        }
        const params = Params{
            .src = .{ fw * across, fh, 1 / (fw * across), 1 / fh },
            .dst = .{ fw * @as(f32, @floatFromInt(s)), fh * @as(f32, @floatFromInt(s)), maskNumber(l.mask), l.mask_through },
            .beam = .{ l.beam_min, l.beam_max, gain, l.vignette },
            .signal = .{ luma_blur, chroma_blur * across, l.deconverge * across, linear_white },
        };
        g_crt.draw(r, picture, &params);
    } else if (smoothed) {
        const fw: f32 = @floatFromInt(snes_w);
        const fh: f32 = @floatFromInt(snes_h);
        const xp = XbrParams{
            .src = .{ fw, fh, 1 / fw, 1 / fh },
            .out_scale = .{ @floatFromInt(s), 0, 0, 0 },
        };
        g_xbr.draw(r, source, &xp);
    } else {
        drawAll(r, source, source_rect, NONE, NEAREST, gray(1), 1, null);

        // 4. The gain, over one, added on.
        if (l.gain > 1) drawAll(r, source, source_rect, ADD, NEAREST, gray(@min(l.gain - 1, 1)), 1, null);

        // 5. The lines, the phosphors and the corners.
        if (preset != .off) {
            if (patternTexture(r, l, @intCast(snes_w), @intCast(snes_h), scale)) |p|
                _ = c.SDL_RenderTexture(r, p, null, null);
        }
    }

    // 6. The glow and the halation, and the haze the bezel reflects: none
    // of it drawn when none of it's wanted.
    if (l.glow <= 0 and l.halation <= 0 and !want_haze) return finish(big, null);
    const g1 = g_glow1.get(r, @divTrunc(snes_w, 4), @divTrunc(snes_h, 4)) orelse return finish(big, null);
    _ = c.SDL_SetRenderTarget(r, g1);
    drawAll(r, source, source_rect, NONE, LINEAR, gray(1), 1, null);
    const g2 = g_glow2.get(r, @divTrunc(snes_w, 8), @divTrunc(snes_h, 8)) orelse return finish(big, null);
    _ = c.SDL_SetRenderTarget(r, g2);
    drawAll(r, g1, null, NONE, LINEAR, gray(1), 1, null);
    const g3 = g_glow3.get(r, @divTrunc(snes_w, 16), @divTrunc(snes_h, 16)) orelse return finish(big, null);
    _ = c.SDL_SetRenderTarget(r, g3);
    drawAll(r, g2, null, NONE, LINEAR, gray(1), 1, null);
    _ = c.SDL_SetRenderTarget(r, big);
    if (l.glow > 0) drawAll(r, g2, null, ADD, LINEAR, gray(l.glow), 1, null);
    if (l.halation > 0) drawAll(r, g3, null, ADD, LINEAR, .{ l.halation, l.halation * 0.55, l.halation * 0.45 }, 1, null);

    return finish(big, g3);
}

fn finish(big: *c.SDL_Texture, haze: ?*c.SDL_Texture) Frame {
    _ = c.SDL_SetTextureBlendMode(big, NONE);
    _ = c.SDL_SetTextureScaleMode(big, LINEAR);
    _ = c.SDL_SetTextureColorModFloat(big, 1, 1, 1);
    _ = c.SDL_SetTextureAlphaModFloat(big, 1);
    return .{ .picture = big, .haze = haze };
}

// ------------------------------------------------------------ to the window

/// How much the curve pulls the corners in at its most; half of it is a
/// TV's face.
const kMaxCurve: f32 = 0.11;
/// The mesh the curve's drawn on, in squares across and down.
const kMeshX = 32;
const kMeshY = 24;

/// Where a point of the picture goes on the curved screen, both in -1 to 1:
/// each edge bows out at its middle, so the corners come in.
fn curve(k: f32, x: f32, y: f32) [2]f32 {
    return .{ x / (1 + k * y * y), y / (1 + k * x * x) };
}

/// Shows the frame in the window's picture area, `area` in the renderer's
/// coordinates, `pixels` the size it comes to on the screen: flat or curved,
/// under the bezel or with the corners rounded. `curvature` is 0 for flat to
/// 1 for the most.
pub fn present(r: *c.SDL_Renderer, frame: Frame, area: c.SDL_FRect, pixels: c.SDL_FRect, curvature: f32, with_bezel: bool) void {
    const curved = curvature > 0;
    const k = curvature * kMaxCurve;
    _ = c.SDL_SetRenderDrawColor(r, 0, 0, 0, 255);
    // The picture's place: the whole area, or inside the bezel.
    const inset_share: f32 = if (with_bezel) crt.kBezelInset else 0;
    const inset = area.h * inset_share;
    const pic = c.SDL_FRect{ .x = area.x + inset, .y = area.y + inset, .w = area.w - 2 * inset, .h = area.h - 2 * inset };

    if (curved) {
        var verts: [(kMeshX + 1) * (kMeshY + 1)]c.SDL_Vertex = undefined;
        for (0..kMeshY + 1) |j| {
            for (0..kMeshX + 1) |i| {
                const u = @as(f32, @floatFromInt(i)) / kMeshX;
                const v = @as(f32, @floatFromInt(j)) / kMeshY;
                const p = curve(k, u * 2 - 1, v * 2 - 1);
                verts[j * (kMeshX + 1) + i] = .{
                    .position = .{ .x = pic.x + (p[0] + 1) / 2 * pic.w, .y = pic.y + (p[1] + 1) / 2 * pic.h },
                    .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
                    .tex_coord = .{ .x = u, .y = v },
                };
            }
        }
        var indices: [kMeshX * kMeshY * 6]c_int = undefined;
        var n: usize = 0;
        for (0..kMeshY) |j| {
            for (0..kMeshX) |i| {
                const a: c_int = @intCast(j * (kMeshX + 1) + i);
                const b = a + 1;
                const cc = a + kMeshX + 1;
                const d = cc + 1;
                for ([_]c_int{ a, b, cc, b, d, cc }) |idx| {
                    indices[n] = idx;
                    n += 1;
                }
            }
        }
        _ = c.SDL_RenderGeometry(r, frame.picture, &verts, verts.len, &indices, @intCast(n));
    } else {
        _ = c.SDL_RenderTexture(r, frame.picture, null, &pic);
    }

    // The bezel, or with the curve the corners rounded, at the screen's own
    // pixels. A flat picture with no bezel keeps its square corners.
    if (!curved and !with_bezel) return;
    const pw: usize = @intFromFloat(@max(pixels.w, 1));
    const ph: usize = @intFromFloat(@max(pixels.h, 1));
    const scale_px = pixels.h / @max(area.h, 1);
    const radius = pixels.h * crt.kCornerRadius;
    const art = bezelTexture(r, pw, ph, inset * scale_px, radius, with_bezel) orelse return;
    if (!with_bezel) {
        drawAll(r, art, null, BLEND, LINEAR, gray(1), 1, &area);
        return;
    }
    // The screen's light caught in the plastic: the haze, a little bigger
    // than the picture, added onto the bezel only, where it's opaque.
    const layer = g_frame.get(r, @intCast(pw), @intCast(ph)) orelse {
        drawAll(r, art, null, BLEND, LINEAR, gray(1), 1, &area);
        return;
    };
    const before = c.SDL_GetRenderTarget(r);
    _ = c.SDL_SetRenderTarget(r, layer);
    drawAll(r, art, null, NONE, LINEAR, gray(1), 1, null);
    if (frame.haze) |haze| {
        const grow = pixels.h * 0.06;
        const glow_rect = c.SDL_FRect{
            .x = inset * scale_px - grow,
            .y = inset * scale_px - grow,
            .w = pixels.w - 2 * inset * scale_px + 2 * grow,
            .h = pixels.h - 2 * inset * scale_px + 2 * grow,
        };
        drawAll(r, haze, null, ADD, LINEAR, gray(0.22), 1, &glow_rect);
    }
    _ = c.SDL_SetRenderTarget(r, before);
    drawAll(r, layer, null, BLEND, LINEAR, gray(1), 1, &area);
}

/// Lets go of every texture, for when the renderer goes.
pub fn destroy() void {
    g_smear.destroy();
    g_trail[0].destroy();
    g_trail[1].destroy();
    g_trail_fresh = true;
    g_big.destroy();
    g_glow1.destroy();
    g_glow2.destroy();
    g_glow3.destroy();
    g_frame.destroy();
    g_pattern.destroy();
    g_bezel.destroy();
    g_signal.destroy();
    g_crt.destroy(g_device);
    g_ntsc.destroy(g_device);
    g_xbr.destroy(g_device);
    g_device = null;
}
