//! Dynamic lighting on the GPU: lighting.zig's light laid over the frame by
//! two shaders, through SDL's GPU renderer, the same way the CRT shaders go.
//!
//! 1. The light map (shaders/light_map.frag): the light on every SNES pixel,
//!    walls' shadows and all, into a floating-point texture the frame's size.
//! 2. The frame drawn at the screen's size (shaders/light_apply.frag), the
//!    light map read back smoothly over it, so the light's soft edges are as
//!    fine as the screen, and the flames' glow on top.
//!
//! The result is a texture the size of the screen's picture, which goes on
//! to the CRT filter or straight to the window in the frame's place.
//! Without SDL's GPU renderer, lighting.zig lights the frame itself.
const std = @import("std");
const c = @import("sdl.zig").c;
const lighting = @import("lighting.zig");
const config = @import("config.zig");
const particles = @import("particles.zig");

const kMaxLights = lighting.kMaxGpuLights;

/// light_map.frag's settings, as it lays out its Params block.
const MapParams = extern struct {
    tex: [4]f32,
    look: [4]f32,
    lights: [kMaxLights * 2][4]f32,
};

/// light_apply.frag's.
const ApplyParams = extern struct {
    tex: [4]f32,
    map: [4]f32,
    dark: [4]f32,
    look: [4]f32,
    weather: [4]f32,
    lights: [kMaxLights * 2][4]f32,
};

/// How dark walls' shadows are, 0 to 1.
pub var g_shadows: f32 = 0.85;
/// How far surfaces near a flame brighten past the art's own colors.
pub var g_overbright: f32 = 0.35;
/// How strong the flames' glow is.
pub var g_glow: f32 = 1.0;

/// Lighting Quality set to Simple: the light, without walls' shadows or the
/// flames' glow.
fn simple() bool {
    return config.g_config.lighting_quality == 1;
}

var g_device: ?*c.SDL_GPUDevice = null;
var g_formats: c.SDL_GPUShaderFormat = 0;
var g_map_shader: ?*c.SDL_GPUShader = null;
var g_apply_shader: ?*c.SDL_GPUShader = null;
var g_map_state: ?*c.SDL_GPURenderState = null;
var g_apply_state: ?*c.SDL_GPURenderState = null;
var g_nearest: ?*c.SDL_GPUSampler = null;
var g_linear: ?*c.SDL_GPUSampler = null;

/// The mask, as the frame's own texture is laid out, so the two share
/// their coordinates.
var g_mask: ?*c.SDL_Texture = null;
var g_mask_w: c_int = 0;
var g_mask_h: c_int = 0;
/// The light map, and the lit frame at the screen's size.
var g_map: ?*c.SDL_Texture = null;
var g_map_w: c_int = 0;
var g_map_h: c_int = 0;
var g_out: ?*c.SDL_Texture = null;
var g_out_w: c_int = 0;
var g_out_h: c_int = 0;
/// The mask and light map the apply state was made with: its extra
/// textures are fixed when it's made.
var g_bound: [2]?*c.SDL_Texture = .{ null, null };
var g_frame_count: u32 = 0;

fn makeShader(spirv: []const u8, msl: []const u8, samplers: u32) ?*c.SDL_GPUShader {
    const dev = g_device orelse return null;
    var info = std.mem.zeroes(c.SDL_GPUShaderCreateInfo);
    if (g_formats & c.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
        info.code = spirv.ptr;
        info.code_size = spirv.len;
        info.entrypoint = "main";
        info.format = c.SDL_GPU_SHADERFORMAT_SPIRV;
    } else if (g_formats & c.SDL_GPU_SHADERFORMAT_MSL != 0) {
        info.code = msl.ptr;
        info.code_size = msl.len;
        info.entrypoint = "main0";
        info.format = c.SDL_GPU_SHADERFORMAT_MSL;
    } else return null;
    info.stage = c.SDL_GPU_SHADERSTAGE_FRAGMENT;
    info.num_samplers = samplers;
    info.num_uniform_buffers = 1;
    return c.SDL_CreateGPUShader(dev, &info) orelse {
        std.debug.print("Lighting shader: {s}\n", .{c.SDL_GetError()});
        return null;
    };
}

fn makeSampler(filter: c.SDL_GPUFilter) ?*c.SDL_GPUSampler {
    var info = std.mem.zeroes(c.SDL_GPUSamplerCreateInfo);
    info.min_filter = filter;
    info.mag_filter = filter;
    info.mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST;
    info.address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
    info.address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
    info.address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
    return c.SDL_CreateGPUSampler(g_device, &info);
}

/// Sets the shaders up on a renderer that's SDL's GPU one. Anything else
/// leaves lighting to the CPU.
pub fn init(r: *c.SDL_Renderer) void {
    const dev: *c.SDL_GPUDevice = @ptrCast(c.SDL_GetPointerProperty(c.SDL_GetRendererProperties(r), c.SDL_PROP_RENDERER_GPU_DEVICE_POINTER, null) orelse return);
    g_device = dev;
    g_formats = c.SDL_GetGPUShaderFormats(dev);
    g_map_shader = makeShader(@embedFile("shaders/light_map.frag.spv"), @embedFile("shaders/light_map.frag.msl"), 1);
    g_apply_shader = makeShader(@embedFile("shaders/light_apply.frag.spv"), @embedFile("shaders/light_apply.frag.msl"), 3);
    g_nearest = makeSampler(c.SDL_GPU_FILTER_NEAREST);
    g_linear = makeSampler(c.SDL_GPU_FILTER_LINEAR);
    if (g_map_shader == null or g_apply_shader == null or g_nearest == null or g_linear == null) {
        destroy();
        return;
    }
    var info = std.mem.zeroes(c.SDL_GPURenderStateCreateInfo);
    info.fragment_shader = g_map_shader;
    g_map_state = c.SDL_CreateGPURenderState(r, &info) orelse {
        std.debug.print("Lighting shader: {s}\n", .{c.SDL_GetError()});
        destroy();
        return;
    };
}

/// Whether the GPU can light frames.
pub fn ready() bool {
    return g_map_state != null;
}

pub fn destroy() void {
    particles.destroyGpu();
    if (g_apply_state) |s| c.SDL_DestroyGPURenderState(s);
    if (g_map_state) |s| c.SDL_DestroyGPURenderState(s);
    g_apply_state = null;
    g_map_state = null;
    g_bound = .{ null, null };
    for ([_]*?*c.SDL_Texture{ &g_mask, &g_map, &g_out }) |t| {
        if (t.*) |tex| c.SDL_DestroyTexture(tex);
        t.* = null;
    }
    g_mask_w = 0;
    g_mask_h = 0;
    g_map_w = 0;
    g_map_h = 0;
    g_out_w = 0;
    g_out_h = 0;
    if (g_device) |dev| {
        if (g_map_shader) |s| c.SDL_ReleaseGPUShader(dev, s);
        if (g_apply_shader) |s| c.SDL_ReleaseGPUShader(dev, s);
        if (g_nearest) |s| c.SDL_ReleaseGPUSampler(dev, s);
        if (g_linear) |s| c.SDL_ReleaseGPUSampler(dev, s);
    }
    g_map_shader = null;
    g_apply_shader = null;
    g_nearest = null;
    g_linear = null;
    g_device = null;
}

/// A texture this size and kind, made afresh when it changes.
fn ensure(r: *c.SDL_Renderer, tex: *?*c.SDL_Texture, tw: *c_int, th: *c_int, w: c_int, h: c_int, format: c.SDL_PixelFormat, access: c.SDL_TextureAccess) ?*c.SDL_Texture {
    if (tex.* == null or tw.* != w or th.* != h) {
        if (tex.*) |t| c.SDL_DestroyTexture(t);
        tex.* = c.SDL_CreateTexture(r, format, access, w, h);
        tw.* = w;
        th.* = h;
        if (tex.*) |t| {
            _ = c.SDL_SetTextureBlendMode(t, c.SDL_BLENDMODE_NONE);
            _ = c.SDL_SetTextureScaleMode(t, c.SDL_SCALEMODE_NEAREST);
        }
    }
    return tex.*;
}

fn gpuTexture(t: *c.SDL_Texture) ?*c.SDL_GPUTexture {
    return @ptrCast(c.SDL_GetPointerProperty(c.SDL_GetTextureProperties(t), c.SDL_PROP_TEXTURE_GPU_TEXTURE_POINTER, null));
}

/// The apply state, made again when the mask or light map it reads has
/// been made afresh.
fn applyState(r: *c.SDL_Renderer, mask: *c.SDL_Texture, map: *c.SDL_Texture) ?*c.SDL_GPURenderState {
    if (g_apply_state != null and g_bound[0] == mask and g_bound[1] == map) return g_apply_state;
    if (g_apply_state) |s| c.SDL_DestroyGPURenderState(s);
    g_apply_state = null;
    const bindings = [2]c.SDL_GPUTextureSamplerBinding{
        .{ .texture = gpuTexture(mask) orelse return null, .sampler = g_nearest },
        .{ .texture = gpuTexture(map) orelse return null, .sampler = g_linear },
    };
    var info = std.mem.zeroes(c.SDL_GPURenderStateCreateInfo);
    info.fragment_shader = g_apply_shader;
    info.num_sampler_bindings = bindings.len;
    info.sampler_bindings = &bindings;
    g_apply_state = c.SDL_CreateGPURenderState(r, &info) orelse {
        std.debug.print("Lighting shader: {s}\n", .{c.SDL_GetError()});
        return null;
    };
    g_bound = .{ mask, map };
    return g_apply_state;
}

fn packLights(f: *const lighting.GpuFrame) [kMaxLights * 2][4]f32 {
    var out = std.mem.zeroes([kMaxLights * 2][4]f32);
    for (f.lights[0..f.n], 0..) |l, i| {
        out[i * 2] = .{ l.x, l.y, l.radius, l.glow_radius };
        out[i * 2 + 1] = .{ l.color[0], l.color[1], l.color[2], l.glow };
    }
    return out;
}

/// Lights the frame in `frame` (its texture `tex_w` by `tex_h`, the frame
/// itself at its top left), drawn `scale` screen pixels to a SNES pixel.
/// Returns the lit picture, the frame's size times `scale`, or null when
/// there's no light this frame or the GPU can't.
pub fn apply(r: *c.SDL_Renderer, frame: *c.SDL_Texture, tex_w: c_int, tex_h: c_int, f: *const lighting.GpuFrame, scale: c_int) ?*c.SDL_Texture {
    if (!ready()) return null;
    const w: c_int = @intCast(f.width);
    const h: c_int = @intCast(f.height);
    const s = @max(scale, 1);
    const mask = ensure(r, &g_mask, &g_mask_w, &g_mask_h, tex_w, tex_h, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STREAMING) orelse return null;
    const map = ensure(r, &g_map, &g_map_w, &g_map_h, w, h, c.SDL_PIXELFORMAT_RGBA64_FLOAT, c.SDL_TEXTUREACCESS_TARGET) orelse return null;
    const out = ensure(r, &g_out, &g_out_w, &g_out_h, w * s, h * s, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_TARGET) orelse return null;
    const state = applyState(r, mask, map) orelse return null;

    const area = c.SDL_Rect{ .x = 0, .y = 0, .w = w, .h = h };
    if (!c.SDL_UpdateTexture(mask, &area, f.mask.ptr, w * 4)) return null;

    const before = c.SDL_GetRenderTarget(r);
    defer _ = c.SDL_SetRenderTarget(r, before);
    const src = c.SDL_FRect{ .x = 0, .y = 0, .w = @floatFromInt(w), .h = @floatFromInt(h) };
    const fw: f32 = @floatFromInt(tex_w);
    const fh: f32 = @floatFromInt(tex_h);
    const mw: f32 = @floatFromInt(w);
    const mh: f32 = @floatFromInt(h);
    const lights = packLights(f);
    g_frame_count +%= 1;

    // 1. The light map.
    _ = c.SDL_SetRenderTarget(r, map);
    const mp = MapParams{
        .tex = .{ fw, fh, 1 / fw, 1 / fh },
        .look = .{ if (simple()) 0 else g_shadows, @floatFromInt(f.n), 0, 0 },
        .lights = lights,
    };
    _ = c.SDL_SetGPURenderStateFragmentUniforms(g_map_state, 0, &mp, @sizeOf(MapParams));
    // Walls read smoothly here, for softer shadows; the second pass reads
    // the mask through a sampler of its own.
    _ = c.SDL_SetTextureScaleMode(mask, c.SDL_SCALEMODE_LINEAR);
    _ = c.SDL_SetGPURenderState(r, g_map_state);
    _ = c.SDL_RenderTexture(r, mask, &src, null);
    _ = c.SDL_SetGPURenderState(r, null);

    // 2. The frame, lit, at the screen's size.
    _ = c.SDL_SetRenderTarget(r, out);
    const ap = ApplyParams{
        .tex = .{ fw, fh, 1 / fw, 1 / fh },
        .map = .{ mw, mh, 1 / mw, 1 / mh },
        .dark = .{
            @as(f32, @floatFromInt(f.dark[0])) / 255,
            @as(f32, @floatFromInt(f.dark[1])) / 255,
            @as(f32, @floatFromInt(f.dark[2])) / 255,
            @floatFromInt(f.n),
        },
        .look = .{ g_overbright, if (simple()) 0 else g_glow, @floatFromInt(g_frame_count % 4096), f.ambient },
        .weather = .{ f.flash * lighting.kFlashStrength, 0, 0, 0 },
        .lights = lights,
    };
    _ = c.SDL_SetTextureBlendMode(frame, c.SDL_BLENDMODE_NONE);
    _ = c.SDL_SetTextureScaleMode(frame, c.SDL_SCALEMODE_NEAREST);
    _ = c.SDL_SetGPURenderStateFragmentUniforms(state, 0, &ap, @sizeOf(ApplyParams));
    _ = c.SDL_SetGPURenderState(r, state);
    _ = c.SDL_RenderTexture(r, frame, &src, null);
    _ = c.SDL_SetGPURenderState(r, null);

    // 3. The particles, over the lit frame.
    particles.drawGpu(r, .{
        .left = f.left,
        .cam_x = f.cam_x,
        .cam_y = f.cam_y,
        .width = f.width,
        .height = f.height,
        .dark = .{ ap.dark[0], ap.dark[1], ap.dark[2] },
        .ambient = f.ambient,
        .lights = f.lights[0..f.n],
        .flash = f.flash,
    }, f.mask, @floatFromInt(s));
    return out;
}
