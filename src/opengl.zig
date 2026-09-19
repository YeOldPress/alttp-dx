//! Port of src/opengl.c: the OpenGL renderer backend, one of the implementations
//! behind the RendererFuncs table that main.c drives.
const std = @import("std");
const config = @import("config.zig");

const c = @import("sdl.zig").c;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn printf(fmt: [*:0]const u8, ...) c_int;
extern fn Die(err: [*:0]const u8) noreturn;

/// types.h only sets this when _DEBUG is defined, which this build never does.
const kDebugFlag = false;

/// util.h
pub const RendererFuncs = extern struct {
    Initialize: ?*const fn (window: ?*c.SDL_Window) callconv(.c) bool,
    Destroy: ?*const fn () callconv(.c) void,
    BeginDraw: ?*const fn (width: c_int, height: c_int, pixels: *[*c]u8, pitch: *c_int) callconv(.c) void,
    EndDraw: ?*const fn () callconv(.c) void,
};

/// glsl_shader.h
pub const GlTextureWithSize = extern struct {
    gl_texture: c_uint,
    width: u16,
    height: u16,
};

/// Still in C: glsl_shader.c. Only ever held by pointer here.
const GlslShader = opaque {};
extern fn GlslShader_CreateFromFile(filename: [*:0]const u8, opengl_es: bool) ?*GlslShader;
extern fn GlslShader_Render(
    gs: *GlslShader,
    tex: *GlTextureWithSize,
    viewport_x: c_int,
    viewport_y: c_int,
    viewport_width: c_int,
    viewport_height: c_int,
) void;

var g_window: ?*c.SDL_Window = null;
var g_screen_buffer: ?[*]u8 = null;
var g_screen_buffer_size: usize = 0;
var g_draw_width: c_int = 0;
var g_draw_height: c_int = 0;
var g_program: c_uint = 0;
var g_VAO: c_uint = 0;
var g_texture: GlTextureWithSize = .{ .gl_texture = 0, .width = 0, .height = 0 };
var g_glsl_shader: ?*GlslShader = null;
var g_opengl_es: bool = false;

fn MessageCallback(
    source: c.GLenum,
    msg_type: c.GLenum,
    id: c.GLuint,
    severity: c.GLenum,
    length: c.GLsizei,
    message: [*c]const c.GLchar,
    userParam: ?*const anyopaque,
) callconv(.c) void {
    _ = .{ source, id, length, userParam };
    if (msg_type == c.GL_DEBUG_TYPE_OTHER)
        return;

    std.debug.print("GL CALLBACK: {s} type = 0x{x}, severity = 0x{x}, message = {s}\n", .{
        if (msg_type == c.GL_DEBUG_TYPE_ERROR) "** GL ERROR **" else "",
        msg_type,
        severity,
        message,
    });
    if (msg_type == c.GL_DEBUG_TYPE_ERROR)
        Die("OpenGL error!\n");
}

const kVertices = [20]f32{
    // positions        // texture coords
    -1.0, 1.0,  0.0, 0.0, 0.0, // top left
    -1.0, -1.0, 0.0, 0.0, 1.0, // bottom left
    1.0,  1.0,  0.0, 1.0, 0.0, // top right
    1.0,  -1.0, 0.0, 1.0, 1.0, // bottom right
};

// The C keeps these inline through a stringifying CODE() macro; the
// preprocessor strips the comments before stringifying, so they are dropped.
const vs_code_core =
    \\#version 330 core
    \\layout(location = 0) in vec3 aPos;
    \\layout(location = 1) in vec2 aTexCoord;
    \\out vec2 TexCoord;
    \\void main() {
    \\  gl_Position = vec4(aPos, 1.0);
    \\  TexCoord = vec2(aTexCoord.x, aTexCoord.y);
    \\}
;

const vs_code_es =
    \\#version 300 es
    \\layout(location = 0) in vec3 aPos;
    \\layout(location = 1) in vec2 aTexCoord;
    \\out vec2 TexCoord;
    \\void main() {
    \\  gl_Position = vec4(aPos, 1.0);
    \\  TexCoord = vec2(aTexCoord.x, aTexCoord.y);
    \\}
;

const fs_code_core =
    \\#version 330 core
    \\out vec4 FragColor;
    \\in vec2 TexCoord;
    \\uniform sampler2D texture1;
    \\void main() {
    \\  FragColor = texture(texture1, TexCoord);
    \\}
;

const fs_code_es =
    \\#version 300 es
    \\precision mediump float;
    \\out vec4 FragColor;
    \\in vec2 TexCoord;
    \\uniform sampler2D texture1;
    \\void main() {
    \\  FragColor = texture(texture1, TexCoord);
    \\}
;

fn compileShader(kind: c.GLenum, code: [*:0]const u8) c_uint {
    var src: [*c]const u8 = code;
    const shader = c.glCreateShader(kind);
    c.glShaderSource(shader, 1, &src, null);
    c.glCompileShader(shader);

    var success: c_int = 0;
    var infolog: [512]u8 = undefined;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        c.glGetShaderInfoLog(shader, 512, null, &infolog);
        _ = printf("%s\n", &infolog);
    }
    return shader;
}

fn OpenGLRenderer_Init(window: ?*c.SDL_Window) callconv(.c) bool {
    g_window = window;
    const context = c.SDL_GL_CreateContext(window);
    _ = context;

    _ = c.SDL_GL_SetSwapInterval(1);
    _ = c.ogl_LoadFunctions();

    if (!g_opengl_es) {
        if (c.ogl_IsVersionGEQ(3, 3) == 0)
            Die("You need OpenGL 3.3");
    } else {
        var majorVersion: c_int = 0;
        var minorVersion: c_int = 0;
        _ = c.SDL_GL_GetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, &majorVersion);
        _ = c.SDL_GL_GetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, &minorVersion);
        if (majorVersion < 3)
            Die("You need OpenGL ES 3.0");
    }

    if (kDebugFlag) {
        c.glEnable(c.GL_DEBUG_OUTPUT);
        c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
        c.glDebugMessageCallback(MessageCallback, null);
    }

    c.glGenTextures(1, &g_texture.gl_texture);

    // create a vertex buffer object
    var vbo: c_uint = 0;
    c.glGenBuffers(1, &vbo);

    // vertex array object
    c.glGenVertexArrays(1, &g_VAO);
    // 1. bind Vertex Array Object
    c.glBindVertexArray(g_VAO);
    // 2. copy our vertices array in a buffer for OpenGL to use
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(kVertices)), &kVertices, c.GL_STATIC_DRAW);
    // position attribute
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(0);
    // texture coord attribute
    c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    c.glEnableVertexAttribArray(1);

    const vs = compileShader(c.GL_VERTEX_SHADER, if (g_opengl_es) vs_code_es else vs_code_core);
    const fs = compileShader(c.GL_FRAGMENT_SHADER, if (g_opengl_es) fs_code_es else fs_code_core);

    // create program
    const program = c.glCreateProgram();
    g_program = program;
    c.glAttachShader(program, vs);
    c.glAttachShader(program, fs);
    c.glLinkProgram(program);

    var success: c_int = 0;
    var infolog: [512]u8 = undefined;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &success);
    if (success == 0) {
        c.glGetProgramInfoLog(program, 512, null, &infolog);
        _ = printf("%s\n", &infolog);
    }

    if (config.g_config.shader) |shader|
        g_glsl_shader = GlslShader_CreateFromFile(shader, g_opengl_es);

    return true;
}

fn OpenGLRenderer_Destroy() callconv(.c) void {}

fn OpenGLRenderer_BeginDraw(width: c_int, height: c_int, pixels: *[*c]u8, pitch: *c_int) callconv(.c) void {
    const size: usize = @intCast(width * height);

    if (size > g_screen_buffer_size) {
        g_screen_buffer_size = size;
        free(g_screen_buffer);
        g_screen_buffer = @ptrCast(malloc(size * 4));
    }

    g_draw_width = width;
    g_draw_height = height;
    pixels.* = g_screen_buffer;
    pitch.* = width * 4;
}

const Viewport = struct { x: c_int, y: c_int, width: c_int, height: c_int };

/// Fits the drawn frame into the window, letterboxing unless the config asks
/// for a stretch.
fn computeViewport(
    drawable_width: c_int,
    drawable_height: c_int,
    draw_width: c_int,
    draw_height: c_int,
    ignore_aspect_ratio: bool,
) Viewport {
    var viewport_width = drawable_width;
    var viewport_height = drawable_height;

    if (!ignore_aspect_ratio) {
        if (viewport_width * draw_height < viewport_height * draw_width) {
            viewport_height = @divTrunc(viewport_width * draw_height, draw_width); // limit height
        } else {
            viewport_width = @divTrunc(viewport_height * draw_width, draw_height); // limit width
        }
    }

    return .{
        .x = (drawable_width - viewport_width) >> 1,
        // Faithful to the C, which subtracts viewport_height from itself and so
        // always centers vertically at 0. Fixing it here would change how every
        // letterboxed window renders, so the bug is preserved.
        .y = (viewport_height - viewport_height) >> 1,
        .width = viewport_width,
        .height = viewport_height,
    };
}

fn OpenGLRenderer_EndDraw() callconv(.c) void {
    var drawable_width: c_int = 0;
    var drawable_height: c_int = 0;
    // SDL3 dropped SDL_GL_GetDrawableSize; the generic window call reports the
    // same pixel (not logical) size.
    _ = c.SDL_GetWindowSizeInPixels(g_window, &drawable_width, &drawable_height);

    const vp = computeViewport(
        drawable_width,
        drawable_height,
        g_draw_width,
        g_draw_height,
        config.g_config.ignore_aspect_ratio,
    );

    c.glBindTexture(c.GL_TEXTURE_2D, g_texture.gl_texture);
    const pixel_type: c.GLenum = if (!g_opengl_es) c.GL_UNSIGNED_INT_8_8_8_8_REV else c.GL_UNSIGNED_BYTE;
    if (g_draw_width == @as(c_int, g_texture.width) and g_draw_height == @as(c_int, g_texture.height)) {
        c.glTexSubImage2D(c.GL_TEXTURE_2D, 0, 0, 0, g_draw_width, g_draw_height, c.GL_BGRA, pixel_type, g_screen_buffer);
    } else {
        g_texture.width = @truncate(@as(c_uint, @bitCast(g_draw_width)));
        g_texture.height = @truncate(@as(c_uint, @bitCast(g_draw_height)));
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, g_draw_width, g_draw_height, 0, c.GL_BGRA, pixel_type, g_screen_buffer);
    }

    c.glClearColor(0.0, 0.0, 0.0, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    if (g_glsl_shader) |shader| {
        GlslShader_Render(shader, &g_texture, vp.x, vp.y, vp.width, vp.height);
    } else {
        c.glViewport(vp.x, vp.y, vp.width, vp.height);
        c.glUseProgram(g_program);
        const filter: c_int = if (config.g_config.linear_filtering) c.GL_LINEAR else c.GL_NEAREST;
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, filter);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, filter);
        c.glBindVertexArray(g_VAO);
        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    }

    _ = c.SDL_GL_SwapWindow(g_window);
}

const kOpenGLRendererFuncs = RendererFuncs{
    .Initialize = &OpenGLRenderer_Init,
    .Destroy = &OpenGLRenderer_Destroy,
    .BeginDraw = &OpenGLRenderer_BeginDraw,
    .EndDraw = &OpenGLRenderer_EndDraw,
};

pub export fn OpenGLRenderer_Create(funcs: *RendererFuncs, use_opengl_es: bool) callconv(.c) void {
    g_opengl_es = use_opengl_es;
    if (!g_opengl_es) {
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 3);
    } else {
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_ES);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 0);
    }
    funcs.* = kOpenGLRendererFuncs;
}

const testing = std.testing;

test "the renderer function table matches the C struct layout" {
    try testing.expectEqual(@sizeOf(*anyopaque) * 4, @sizeOf(RendererFuncs));
    try testing.expectEqual(0, @offsetOf(RendererFuncs, "Initialize"));
    try testing.expectEqual(@sizeOf(*anyopaque) * 3, @offsetOf(RendererFuncs, "EndDraw"));
    // uint + two uint16 packs into 8 bytes.
    try testing.expectEqual(8, @sizeOf(GlTextureWithSize));
    try testing.expectEqual(4, @offsetOf(GlTextureWithSize, "width"));
    try testing.expectEqual(6, @offsetOf(GlTextureWithSize, "height"));
}

test "a wider window letterboxes on the sides" {
    // 512x448 content in a 1600x896 window: height is the binding constraint.
    const vp = computeViewport(1600, 896, 512, 448, false);
    try testing.expectEqual(1024, vp.width);
    try testing.expectEqual(896, vp.height);
    try testing.expectEqual(288, vp.x); // (1600 - 1024) / 2
}

test "a taller window limits height instead" {
    const vp = computeViewport(512, 896, 512, 448, false);
    try testing.expectEqual(512, vp.width);
    try testing.expectEqual(448, vp.height);
    try testing.expectEqual(0, vp.x);
}

test "ignoring the aspect ratio fills the whole window" {
    const vp = computeViewport(1600, 896, 512, 448, true);
    try testing.expectEqual(1600, vp.width);
    try testing.expectEqual(896, vp.height);
    try testing.expectEqual(0, vp.x);
}

test "the vertical offset is always zero, as in the C" {
    // (viewport_height - viewport_height) >> 1 can only ever be 0. This pins
    // the upstream bug so a future fix has to be deliberate.
    for ([_]c_int{ 400, 896, 1080 }) |h| {
        try testing.expectEqual(0, computeViewport(1600, h, 512, 448, false).y);
        try testing.expectEqual(0, computeViewport(1600, h, 512, 448, true).y);
    }
}

test "the vertex buffer holds four position/texcoord pairs" {
    try testing.expectEqual(20, kVertices.len);
    // Each vertex is 3 position floats then 2 texture coords.
    try testing.expectEqual(-1.0, kVertices[0]);
    try testing.expectEqual(1.0, kVertices[1]);
    try testing.expectEqual(0.0, kVertices[3]);
    try testing.expectEqual(1.0, kVertices[19]);
}

test "each shader source declares the version its context needs" {
    try testing.expect(std.mem.startsWith(u8, vs_code_core, "#version 330 core\n"));
    try testing.expect(std.mem.startsWith(u8, fs_code_core, "#version 330 core\n"));
    try testing.expect(std.mem.startsWith(u8, vs_code_es, "#version 300 es\n"));
    try testing.expect(std.mem.startsWith(u8, fs_code_es, "#version 300 es\n"));
    // The ES fragment shader is the only one that must set a float precision.
    try testing.expect(std.mem.indexOf(u8, fs_code_es, "precision mediump float;") != null);
    try testing.expect(std.mem.indexOf(u8, fs_code_core, "precision") == null);
}
