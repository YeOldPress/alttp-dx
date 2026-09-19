//! Port of src/glsl_shader.c: the libretro-style GLSL shader preset loader and
//! multi-pass renderer. This file is heavily influenced by Snes9x.
//!
//! The C instantiated stb_image here via STB_IMAGE_IMPLEMENTATION; that now
//! lives in third_party/stb/stb_image_impl.c so the PNG loader stays in the
//! build.
const std = @import("std");
const util = @import("util.zig");
const config = @import("config.zig");

const c = @import("sdl.zig").c;

const ByteArray = util.ByteArray;

extern fn calloc(n: usize, size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern fn strtoul(s: [*:0]const u8, end: ?*?[*:0]u8, base: c_int) c_ulong;
extern fn atof(s: [*:0]const u8) f64;
extern fn atoi(s: [*:0]const u8) c_int;
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;

/// third_party/stb/stb_image.h
extern fn stbi_load(filename: [*:0]const u8, x: *c_int, y: *c_int, comp: *c_int, req_comp: c_int) ?[*]u8;

// glsl_shader.h
const kGlslMaxPasses = 20;
const kGlslMaxTextures = 10;

const GLSL_NONE: u8 = 0;
const GLSL_SOURCE: u8 = 1;
const GLSL_VIEWPORT: u8 = 2;
const GLSL_ABSOLUTE: u8 = 3;

pub const GlslTextureUniform = extern struct {
    Texture: c_int,
    InputSize: c_int,
    TextureSize: c_int,
    TexCoord: c_int,
};

pub const GlslUniforms = extern struct {
    Top: GlslTextureUniform,
    OutputSize: c_int,
    FrameCount: c_int,
    FrameDirection: c_int,
    LUTTexCoord: c_int,
    VertexCoord: c_int,
    Orig: GlslTextureUniform,
    Prev: [7]GlslTextureUniform,
    Pass: [kGlslMaxPasses]GlslTextureUniform,
    PassPrev: [kGlslMaxPasses]GlslTextureUniform,
    Texture: [kGlslMaxTextures]c_int,
};

pub const GlslPass = extern struct {
    filename: ?[*:0]u8,
    scale_type_x: u8,
    scale_type_y: u8,
    float_framebuffer: bool,
    srgb_framebuffer: bool,
    mipmap_input: bool,
    scale_x: f32,
    scale_y: f32,
    wrap_mode: c_uint,
    frame_count_mod: c_uint,
    frame_count: c_uint,
    gl_program: c_uint,
    gl_fbo: c_uint,
    filter: c_uint,
    gl_texture: c_uint,
    width: u16,
    height: u16,
    unif: GlslUniforms,
};

pub const GlTextureWithSize = extern struct {
    gl_texture: c_uint,
    width: u16,
    height: u16,
};

pub const GlslTexture = extern struct {
    next: ?*GlslTexture,
    id: ?[*:0]u8,
    filename: ?[*:0]u8,
    filter: c_uint,
    gl_texture: c_uint,
    wrap_mode: c_uint,
    mipmap: bool,
    width: c_int,
    height: c_int,
};

pub const GlslParam = extern struct {
    next: ?*GlslParam,
    id: ?[*:0]u8,
    has_value: bool,
    value: f32,
    min: f32,
    max: f32,
    uniform: [kGlslMaxPasses]c_uint,
};

pub const GlslShader = extern struct {
    n_pass: c_int,
    pass: ?[*]GlslPass,
    first_param: ?*GlslParam,
    first_texture: ?*GlslTexture,
    gl_vao: ?*c_uint,
    gl_vbo: c_uint,
    frame_count: c_uint,
    max_prev_frame: c_int,
    prev_frame: [8]GlTextureWithSize,
};

fn ParseConfigKeyPass(gs: *GlslShader, key_in: [*:0]const u8, match_in: [*:0]const u8) ?*GlslPass {
    var key = key_in;
    var match = match_in;
    while (match[0] != 0) : ({
        key += 1;
        match += 1;
    }) {
        if (key[0] != match[0])
            return null;
    }
    if (key[0] -% '0' >= 10)
        return null;
    var endp: ?[*:0]u8 = null;
    const pass = strtoul(key, &endp, 10);
    if (pass >= gs.n_pass or endp.?[0] != 0)
        return null;
    return &gs.pass.?[pass + 1];
}

fn ParseScaleType(s: [*:0]const u8) u8 {
    return if (util.StringEqualsNoCase(s, "source"))
        GLSL_SOURCE
    else if (util.StringEqualsNoCase(s, "viewport"))
        GLSL_VIEWPORT
    else if (util.StringEqualsNoCase(s, "absolute"))
        GLSL_ABSOLUTE
    else
        GLSL_NONE;
}

fn ParseWrapMode(s: [*:0]const u8) c_uint {
    return if (util.StringEqualsNoCase(s, "repeat"))
        c.GL_REPEAT
    else if (util.StringEqualsNoCase(s, "clamp_to_edge"))
        c.GL_CLAMP_TO_EDGE
    else if (util.StringEqualsNoCase(s, "clamp"))
        c.GL_CLAMP
    else
        c.GL_CLAMP_TO_BORDER;
}

fn GlslPass_Initialize(pass: *GlslPass) void {
    pass.scale_x = 1.0;
    pass.scale_y = 1.0;
    pass.wrap_mode = c.GL_CLAMP_TO_BORDER;
}

fn ParseTextures(gs: *GlslShader, value_in: [*:0]u8) void {
    var value: ?[*:0]u8 = value_in;
    var nextp: *?*GlslTexture = &gs.first_texture;
    var num: c_int = 0;
    while (num < kGlslMaxTextures) : (num += 1) {
        const id = util.NextDelim(&value, ';') orelse break;
        const t: *GlslTexture = @ptrCast(@alignCast(calloc(@sizeOf(GlslTexture), 1).?));
        t.id = strdup(id);
        t.wrap_mode = c.GL_CLAMP_TO_BORDER;
        t.filter = c.GL_NEAREST;
        nextp.* = t;
        nextp = &t.next;
    }
}

fn ParseTextureKeyValue(gs: *GlslShader, key: [*:0]const u8, value: [*:0]const u8) bool {
    var it = gs.first_texture;
    while (it) |t| : (it = t.next) {
        const key2 = util.SkipPrefix(key, t.id.?) orelse continue;
        if (key2[0] == 0) {
            util.StrSet(@ptrCast(&t.filename), value);
            return true;
        } else if (strcmp(key2, "_wrap_mode") == 0) {
            t.wrap_mode = ParseWrapMode(value);
            return true;
        } else if (strcmp(key2, "_mipmap") == 0) {
            t.mipmap = config.ParseBool(value, null);
            return true;
        } else if (strcmp(key2, "_linear") == 0) {
            t.filter = if (config.ParseBool(value, null)) c.GL_LINEAR else c.GL_NEAREST;
            return true;
        }
    }
    return false;
}

fn GlslShader_GetParam(gs: *GlslShader, id: [*:0]const u8) *GlslParam {
    var pp: *?*GlslParam = &gs.first_param;
    while (pp.*) |cur| : (pp = &cur.next) {
        if (strcmp(cur.id.?, id) == 0)
            return cur;
    }
    const p: *GlslParam = @ptrCast(@alignCast(calloc(1, @sizeOf(GlslParam)).?));
    pp.* = p;
    p.id = strdup(id);
    return p;
}

fn ParseParameters(gs: *GlslShader, value_in: [*:0]u8) void {
    var value: ?[*:0]u8 = value_in;
    while (util.NextDelim(&value, ';')) |id|
        _ = GlslShader_GetParam(gs, id);
}

fn ParseParameterKeyValue(gs: *GlslShader, key: [*:0]const u8, value: [*:0]const u8) bool {
    var it = gs.first_param;
    while (it) |p| : (it = p.next) {
        if (strcmp(p.id.?, key) == 0) {
            p.value = @floatCast(atof(value));
            p.has_value = true;
            return true;
        }
    }
    return false;
}

fn GlslShader_InitializePasses(gs: *GlslShader, passes: c_int) void {
    gs.n_pass = passes;
    gs.pass = @ptrCast(@alignCast(calloc(@intCast(gs.n_pass + 1), @sizeOf(GlslPass)).?));
    var i: c_int = 0;
    while (i < gs.n_pass) : (i += 1)
        GlslPass_Initialize(&gs.pass.?[@intCast(i + 1)]);
}

fn GlslShader_ReadPresetFile(gs: *GlslShader, filename: [*:0]const u8) bool {
    const data_org = util.ReadWholeFile(filename, null) orelse return false;
    var data: ?[*:0]u8 = @ptrCast(data_org);
    var lineno: c_int = 1;
    while (util.NextLineStripComments(&data)) |line| : (lineno += 1) {
        var value = util.SplitKeyValue(line) orelse {
            if (line[0] != 0)
                std.debug.print("{s}:{d}: Expecting key=value\n", .{ filename, lineno });
            continue;
        };
        if (value[0] == '"') {
            value += 1;
            var t = value;
            while (t[0] != 0 and t[0] != '"') t += 1;
            if (t[0] != 0) t[0] = 0;
        }

        if (gs.n_pass == 0) {
            if (strcmp(line, "shaders") != 0) {
                std.debug.print("{s}:{d}: Expecting 'shaders'\n", .{ filename, lineno });
                break;
            }
            const passes: c_int = @intCast(strtoul(value, null, 10));
            if (passes < 1 or passes > kGlslMaxPasses)
                break;
            GlslShader_InitializePasses(gs, passes);
            continue;
        }
        if (ParseConfigKeyPass(gs, line, "filter_linear")) |pass| {
            pass.filter = if (config.ParseBool(value, null)) c.GL_LINEAR else c.GL_NEAREST;
        } else if (ParseConfigKeyPass(gs, line, "scale_type")) |pass| {
            pass.scale_type_x = ParseScaleType(value);
            pass.scale_type_y = pass.scale_type_x;
        } else if (ParseConfigKeyPass(gs, line, "scale_type_x")) |pass| {
            pass.scale_type_x = ParseScaleType(value);
        } else if (ParseConfigKeyPass(gs, line, "scale_type_y")) |pass| {
            pass.scale_type_y = ParseScaleType(value);
        } else if (ParseConfigKeyPass(gs, line, "scale")) |pass| {
            pass.scale_x = @floatCast(atof(value));
            pass.scale_y = pass.scale_x;
        } else if (ParseConfigKeyPass(gs, line, "scale_x")) |pass| {
            pass.scale_x = @floatCast(atof(value));
        } else if (ParseConfigKeyPass(gs, line, "scale_y")) |pass| {
            pass.scale_y = @floatCast(atof(value));
        } else if (ParseConfigKeyPass(gs, line, "shader")) |pass| {
            util.StrSet(@ptrCast(&pass.filename), value);
        } else if (ParseConfigKeyPass(gs, line, "wrap_mode")) |pass| {
            pass.wrap_mode = ParseWrapMode(value);
        } else if (ParseConfigKeyPass(gs, line, "mipmap_input")) |pass| {
            pass.mipmap_input = config.ParseBool(value, null);
        } else if (ParseConfigKeyPass(gs, line, "frame_count_mod")) |pass| {
            pass.frame_count_mod = @bitCast(atoi(value));
        } else if (ParseConfigKeyPass(gs, line, "float_framebuffer")) |pass| {
            pass.float_framebuffer = config.ParseBool(value, null);
        } else if (ParseConfigKeyPass(gs, line, "srgb_framebuffer")) |pass| {
            pass.srgb_framebuffer = config.ParseBool(value, null);
        } else if (ParseConfigKeyPass(gs, line, "alias") != null) {
            // ignored
        } else if (strcmp(line, "textures") == 0 and gs.first_texture == null) {
            ParseTextures(gs, value);
        } else if (strcmp(line, "parameters") == 0) {
            ParseParameters(gs, value);
        } else if (!ParseTextureKeyValue(gs, line, value) and !ParseParameterKeyValue(gs, line, value)) {
            std.debug.print("{s}:{d}: Unknown key '{s}'\n", .{ filename, lineno, line });
        }
    }
    free(data_org);
    return gs.n_pass != 0;
}

pub export fn GlslShader_ReadShaderFile(
    gs: *GlslShader,
    filename: [*:0]const u8,
    result: *ByteArray,
) callconv(.c) void {
    const data_org = util.ReadWholeFile(filename, null) orelse {
        std.debug.print("Unable to read file '{s}'\n", .{filename});
        return;
    };
    var data: ?[*:0]u8 = @ptrCast(data_org);
    while (util.NextDelim(&data, '\n')) |line| {
        const linelen = std.mem.len(line);
        if (linelen >= 8 and std.mem.eql(u8, line[0..8], "#include")) {
            var tt = line + 8;
            const new_filename = util.ReplaceFilenameWithNewPath(filename, util.NextPossiblyQuotedString(&tt)).?;
            GlslShader_ReadShaderFile(gs, @ptrCast(new_filename), result);
            free(new_filename);
        } else if (linelen >= 17 and std.mem.eql(u8, line[0..17], "#pragma parameter")) {
            var tt = line + 17;
            const param = GlslShader_GetParam(gs, util.NextPossiblyQuotedString(&tt));
            _ = util.NextPossiblyQuotedString(&tt); // skip name
            const value: f32 = @floatCast(atof(util.NextPossiblyQuotedString(&tt)));
            if (!param.has_value)
                param.value = value;
            param.min = @floatCast(atof(util.NextPossiblyQuotedString(&tt)));
            param.max = @floatCast(atof(util.NextPossiblyQuotedString(&tt)));
            // skip step
        } else {
            line[linelen] = '\n';
            util.ByteArray_AppendData(result, line, linelen + 1);
        }
    }
    free(data_org);
}

pub export fn LengthOfInitialComments(data: [*]const u8, size: usize) callconv(.c) usize {
    var i: usize = 0;
    while (i != size) {
        const ch = data[i];
        i += 1;
        if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n')
            continue;
        if (ch != '/' or i == size) {
            i -= 1;
            break;
        }
        const ch2 = data[i];
        i += 1;
        if (ch2 == '/') {
            while (i != size) {
                const cc = data[i];
                i += 1;
                if (cc == '\n') break;
            }
        } else if (ch2 == '*') {
            while (true) {
                if (size - i < 2)
                    return 0;
                const cc = data[i];
                i += 1;
                if (cc == '*' and data[i] == '/') break;
            }
            i += 1;
        } else {
            // Only the second character is given back; the '/' stays consumed.
            i -= 1;
            break;
        }
    }
    return i;
}

const kVertexPrefix = "#define VERTEX\n#define PARAMETER_UNIFORM\n";
const kFragmentPrefixCore = "#define FRAGMENT\n#define PARAMETER_UNIFORM\n";
const kFragmentPrefixEs = "#define FRAGMENT\n#define PARAMETER_UNIFORM\nprecision mediump float;";

fn GlslPass_Compile(p: *GlslPass, kind: c_uint, data_in: [*]const u8, size_in: usize, use_opengl_es: bool) bool {
    var strings: [3][*c]const u8 = undefined;
    var lengths: [3]c.GLint = undefined;
    var buffer: [256]u8 = undefined;
    var compile_status: c.GLint = 0;
    var skip: usize = 0;

    const commsize = LengthOfInitialComments(data_in, size_in);
    const data = data_in + commsize;
    const size = size_in - commsize;

    if (size < 8 or !std.mem.eql(u8, data[0..8], "#version")) {
        if (!use_opengl_es) {
            strings[0] = "#version 330\n";
            lengths[0] = "#version 330\n".len;
        } else {
            strings[0] = "#version 300 es\n";
            lengths[0] = "#version 300 es\n".len;
        }
    } else {
        while (skip < size) {
            const ch = data[skip];
            skip += 1;
            if (ch == '\n') break;
        }
        strings[0] = data;
        lengths[0] = @intCast(skip);
    }
    if (kind == c.GL_VERTEX_SHADER) {
        strings[1] = kVertexPrefix;
        lengths[1] = kVertexPrefix.len;
    } else {
        strings[1] = if (use_opengl_es) kFragmentPrefixEs else kFragmentPrefixCore;
        lengths[1] = if (use_opengl_es) kFragmentPrefixEs.len else kFragmentPrefixCore.len;
    }
    strings[2] = data + skip;
    lengths[2] = @intCast(size - skip);

    const shader = c.glCreateShader(kind);
    c.glShaderSource(shader, 3, &strings, &lengths);
    c.glCompileShader(shader);
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &compile_status);
    buffer[0] = 0;
    c.glGetShaderInfoLog(shader, buffer.len, null, &buffer);
    if (compile_status != c.GL_TRUE or buffer[0] != 0) {
        std.debug.print("{s} compiling {s} shader in file '{s}':\n{s}\n", .{
            if (compile_status != c.GL_TRUE) "Error" else "While",
            if (kind == c.GL_VERTEX_SHADER) "vertex" else "fragment",
            p.filename orelse "",
            std.mem.sliceTo(&buffer, 0),
        });
    }
    if (compile_status == c.GL_TRUE)
        c.glAttachShader(p.gl_program, shader);
    c.glDeleteShader(shader);
    return compile_status == c.GL_TRUE;
}

fn GlslTextureUniform_Read(program: c_uint, prefix: [*:0]const u8, i: c_int, result: *GlslTextureUniform) void {
    var buf: [40]u8 = undefined;
    const n = snprintf(&buf, buf.len, if (i >= 0) "%s%u" else "%s", prefix, i);
    const e = buf[@intCast(n)..];
    @memcpy(e[0..8], "Texture\x00");
    result.Texture = c.glGetUniformLocation(program, @ptrCast(&buf));
    @memcpy(e[0..10], "InputSize\x00");
    result.InputSize = c.glGetUniformLocation(program, @ptrCast(&buf));
    @memcpy(e[0..12], "TextureSize\x00");
    result.TextureSize = c.glGetUniformLocation(program, @ptrCast(&buf));
    @memcpy(e[0..9], "TexCoord\x00");
    result.TexCoord = c.glGetAttribLocation(program, @ptrCast(&buf));
}

const kMvpMatrixOrtho = [16]f32{
    2.0,  0.0,  0.0,  0.0,
    0.0,  2.0,  0.0,  0.0,
    0.0,  0.0,  -1.0, 0.0,
    -1.0, -1.0, 0.0,  1.0,
};

fn GlslShader_GetUniforms(gs: *GlslShader) void {
    var pass_idx: usize = 1;
    gs.max_prev_frame = 0;
    while (pass_idx <= @as(usize, @intCast(gs.n_pass))) : (pass_idx += 1) {
        const p = &gs.pass.?[pass_idx];
        const program = p.gl_program;
        c.glUseProgram(program);

        const MVPMatrix = c.glGetUniformLocation(program, "MVPMatrix");
        if (MVPMatrix >= 0)
            c.glUniformMatrix4fv(MVPMatrix, 1, c.GL_FALSE, &kMvpMatrixOrtho);

        GlslTextureUniform_Read(program, "", -1, &p.unif.Top);
        p.unif.OutputSize = c.glGetUniformLocation(program, "OutputSize");
        p.unif.FrameCount = c.glGetUniformLocation(program, "FrameCount");
        p.unif.FrameDirection = c.glGetUniformLocation(program, "FrameDirection");
        p.unif.LUTTexCoord = c.glGetAttribLocation(program, "LUTTexCoord");
        p.unif.VertexCoord = c.glGetAttribLocation(program, "VertexCoord");
        GlslTextureUniform_Read(program, "Orig", -1, &p.unif.Orig);
        for (0..7) |j| {
            GlslTextureUniform_Read(program, "Prev", if (j != 0) @intCast(j) else -1, &p.unif.Prev[j]);
            if (p.unif.Prev[j].Texture >= 0)
                gs.max_prev_frame = @intCast(j + 1);
        }
        for (0..@intCast(gs.n_pass)) |j| {
            GlslTextureUniform_Read(program, "Pass", @intCast(j), &p.unif.Pass[j]);
            GlslTextureUniform_Read(program, "PassPrev", @intCast(j), &p.unif.PassPrev[j]);
        }
        var t = gs.first_texture;
        var j: usize = 0;
        while (t) |tex| : ({
            t = tex.next;
            j += 1;
        }) {
            p.unif.Texture[j] = c.glGetUniformLocation(program, tex.id.?);
        }
        var pa = gs.first_param;
        while (pa) |param| : (pa = param.next)
            param.uniform[pass_idx] = @bitCast(c.glGetUniformLocation(program, param.id.?));
    }
    c.glUseProgram(0);
}

fn IsGlslFilename(filename: [*:0]const u8) bool {
    const len = std.mem.len(filename);
    return len >= 5 and std.mem.eql(u8, filename[len - 5 ..][0..5], ".glsl");
}

pub export fn GlslShader_CreateFromFile(filename_in: [*:0]const u8, opengl_es: bool) callconv(.c) ?*GlslShader {
    var shader_code = ByteArray{ .data = null, .size = 0, .capacity = 0 };
    const gs: *GlslShader = @ptrCast(@alignCast(calloc(@sizeOf(GlslShader), 1) orelse return null));

    const success = buildShader(gs, filename_in, opengl_es, &shader_code);

    util.ByteArray_Destroy(&shader_code);
    if (!success) {
        GlslShader_Destroy(gs);
        return null;
    }
    return gs;
}

/// Everything the C reached by `goto FAIL`; returning false means fail.
fn buildShader(gs: *GlslShader, filename_in: [*:0]const u8, opengl_es: bool, shader_code: *ByteArray) bool {
    var buffer: [256]u8 = undefined;
    var link_status: c.GLint = 0;
    var filename = filename_in;

    if (IsGlslFilename(filename)) {
        GlslShader_InitializePasses(gs, 1);
        gs.pass.?[1].filename = strdup(filename);
        filename = "";
    } else {
        if (!GlslShader_ReadPresetFile(gs, filename)) {
            std.debug.print("Unable to read file '{s}'\n", .{filename});
            return false;
        }
    }
    var i: c_int = 1;
    while (i <= gs.n_pass) : (i += 1) {
        const p = &gs.pass.?[@intCast(i)];
        shader_code.size = 0;

        if (p.filename == null) {
            std.debug.print("shader{d} attribute missing\n", .{i - 1});
            return false;
        }

        const new_filename = util.ReplaceFilenameWithNewPath(filename, p.filename.?).?;
        GlslShader_ReadShaderFile(gs, @ptrCast(new_filename), shader_code);
        free(new_filename);

        if (shader_code.size == 0) {
            std.debug.print("Couldn't read shader in file '{s}'\n", .{p.filename.?});
            return false;
        }
        p.gl_program = c.glCreateProgram();
        if (!GlslPass_Compile(p, c.GL_VERTEX_SHADER, shader_code.data.?, shader_code.size, opengl_es) or
            !GlslPass_Compile(p, c.GL_FRAGMENT_SHADER, shader_code.data.?, shader_code.size, opengl_es))
        {
            return false;
        }
        c.glLinkProgram(p.gl_program);
        c.glGetProgramiv(p.gl_program, c.GL_LINK_STATUS, &link_status);
        buffer[0] = 0;
        c.glGetProgramInfoLog(p.gl_program, buffer.len, null, &buffer);
        if (link_status != c.GL_TRUE or buffer[0] != 0) {
            std.debug.print("{s} linking shader in file '{s}':\n{s}\n", .{
                if (link_status != c.GL_TRUE) "Error" else "While",
                p.filename.?,
                std.mem.sliceTo(&buffer, 0),
            });
        }
        if (link_status != c.GL_TRUE)
            return false;
        c.glGenFramebuffers(1, &p.gl_fbo);
        c.glGenTextures(1, &p.gl_texture);
    }

    var it = gs.first_texture;
    while (it) |t| : (it = t.next) {
        c.glGenTextures(1, &t.gl_texture);
        c.glBindTexture(c.GL_TEXTURE_2D, t.gl_texture);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, @bitCast(t.wrap_mode));
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, @bitCast(t.wrap_mode));
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, @bitCast(t.filter));
        const min_filter: c_uint = if (t.mipmap)
            (if (t.filter == c.GL_LINEAR) c.GL_LINEAR_MIPMAP_LINEAR else c.GL_NEAREST_MIPMAP_NEAREST)
        else
            t.filter;
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, @bitCast(min_filter));
        if (t.filename) |tfn| {
            const new_filename = util.ReplaceFilenameWithNewPath(filename, tfn).?;
            var imw: c_int = 0;
            var imh: c_int = 0;
            var imn: c_int = 0;
            const data = stbi_load(@ptrCast(new_filename), &imw, &imh, &imn, 0);
            if (data == null) {
                std.debug.print("Unable to read PNG '{s}'\n", .{@as([*:0]const u8, @ptrCast(new_filename))});
            } else {
                const fmt: c_uint = if (imn == 4) c.GL_RGBA else if (imn == 3) c.GL_RGB else c.GL_LUMINANCE;
                c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, imw, imh, 0, fmt, c.GL_UNSIGNED_BYTE, data);
            }
            free(data);
            free(new_filename);
        }
        if (t.mipmap)
            c.glGenerateMipmap(c.GL_TEXTURE_2D);
    }

    var pit = gs.first_param;
    while (pit) |p| : (pit = p.next)
        p.value = if (p.value < p.min) p.min else if (p.value > p.max) p.max else p.value;

    GlslShader_GetUniforms(gs);

    var k: c_int = 0;
    while (k < gs.max_prev_frame) : (k += 1) {
        // (-i - 1) & 7 walks the ring backwards from slot 7.
        const idx: usize = @intCast((-k - 1) & 7);
        c.glGenTextures(1, &gs.prev_frame[idx].gl_texture);
    }

    const kTexCoords = [16]c.GLfloat{
        0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0,
        0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0,
    };
    c.glGenBuffers(1, &gs.gl_vbo);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, gs.gl_vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(kTexCoords)), &kTexCoords, c.GL_STATIC_DRAW);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    return true;
}

pub export fn GlslShader_Destroy(gs: *GlslShader) callconv(.c) void {
    if (gs.pass) |passes| {
        var i: usize = 1;
        while (i <= @as(usize, @intCast(gs.n_pass))) : (i += 1) {
            const p = &passes[i];
            c.glDeleteProgram(p.gl_program);
            c.glDeleteTextures(1, &p.gl_texture);
            c.glDeleteFramebuffers(1, &p.gl_fbo);
            free(p.filename);
        }
    }
    free(gs.pass);

    while (gs.first_texture) |t| {
        gs.first_texture = t.next;
        c.glDeleteTextures(1, &t.gl_texture);
        free(t.id);
        free(t.filename);
        free(t);
    }
    while (gs.first_param) |pp| {
        gs.first_param = pp.next;
        free(pp.id);
        free(pp);
    }
    for (0..8) |i|
        c.glDeleteTextures(1, &gs.prev_frame[i].gl_texture);
    c.glDeleteBuffers(1, &gs.gl_vbo);
    free(gs);
}

const kMaxVaosInRenderCtx = 11 + kGlslMaxPasses * 2;

const RenderCtx = struct {
    texture_unit: c_uint,
    offset: c_uint,
    num_vaos: c_uint,
    vaos: [kMaxVaosInRenderCtx]c_uint,
};

fn RenderCtx_SetTexture(ctx: *RenderCtx, textureu: c_int, texture_id: c_uint) void {
    if (textureu >= 0) {
        c.glActiveTexture(@as(c_uint, c.GL_TEXTURE0) + ctx.texture_unit);
        c.glBindTexture(c.GL_TEXTURE_2D, texture_id);
        c.glUniform1i(textureu, @bitCast(ctx.texture_unit));
        ctx.texture_unit += 1;
    }
}

fn RenderCtx_SetTexCoords(ctx: *RenderCtx, tex_coord: c_int, offset: usize) void {
    if (tex_coord >= 0) {
        std.debug.assert(ctx.num_vaos < kMaxVaosInRenderCtx);
        ctx.vaos[ctx.num_vaos] = @bitCast(tex_coord);
        ctx.num_vaos += 1;
        c.glVertexAttribPointer(@bitCast(tex_coord), 2, c.GL_FLOAT, c.GL_FALSE, 0, @ptrFromInt(offset));
        c.glEnableVertexAttribArray(@bitCast(tex_coord));
    }
}

fn RenderCtx_SetGlslTextureUniform(
    ctx: *RenderCtx,
    u: *GlslTextureUniform,
    width: c_int,
    height: c_int,
    texture: c_uint,
) void {
    const size = [2]f32{ @floatFromInt(width), @floatFromInt(height) };
    RenderCtx_SetTexture(ctx, u.Texture, texture);
    if (u.InputSize >= 0)
        c.glUniform2fv(u.InputSize, 1, &size);
    if (u.TextureSize >= 0)
        c.glUniform2fv(u.TextureSize, 1, &size);
    RenderCtx_SetTexCoords(ctx, u.TexCoord, ctx.offset);
}

fn GlslShader_SetShaderVars(gs: *GlslShader, ctx: *RenderCtx, pass: usize) void {
    const passes = gs.pass.?;
    const p = &passes[pass];
    const prev = &passes[pass - 1];

    RenderCtx_SetGlslTextureUniform(ctx, &p.unif.Top, prev.width, prev.height, prev.gl_texture);
    if (p.unif.OutputSize >= 0) {
        const output_size = [2]f32{ @floatFromInt(p.width), @floatFromInt(p.height) };
        c.glUniform2fv(p.unif.OutputSize, 1, &output_size);
    }
    if (p.unif.FrameCount >= 0) {
        const fc: c_int = @bitCast(if (p.frame_count_mod != 0)
            gs.frame_count % p.frame_count_mod
        else
            gs.frame_count);
        c.glUniform1i(p.unif.FrameCount, fc);
    }
    if (p.unif.FrameDirection >= 0)
        c.glUniform1i(p.unif.FrameDirection, 1);
    RenderCtx_SetTexCoords(ctx, p.unif.LUTTexCoord, ctx.offset);
    RenderCtx_SetTexCoords(ctx, p.unif.VertexCoord, 0);
    RenderCtx_SetGlslTextureUniform(ctx, &p.unif.Orig, passes[0].width, passes[0].height, passes[0].gl_texture);

    // Prev, Prev1-Prev6 uniforms
    var i: usize = 0;
    while (i < @as(usize, @intCast(gs.max_prev_frame))) : (i += 1) {
        const t = &gs.prev_frame[(gs.frame_count -% 1 -% @as(c_uint, @intCast(i))) & 7];
        std.debug.assert(t.gl_texture != 0);
        if (t.width != 0)
            RenderCtx_SetGlslTextureUniform(ctx, &p.unif.Prev[i], t.width, t.height, t.gl_texture);
    }
    // Texture uniforms
    var tctr: usize = 0;
    var t = gs.first_texture;
    while (t) |tex| : ({
        t = tex.next;
        tctr += 1;
    }) {
        RenderCtx_SetTexture(ctx, p.unif.Texture[tctr], tex.gl_texture);
    }
    // PassX uniforms
    var j: usize = 1;
    while (j < pass) : (j += 1)
        RenderCtx_SetGlslTextureUniform(ctx, &p.unif.Pass[j], passes[j].width, passes[j].height, passes[j].gl_texture);
    // PassPrevX uniforms
    j = 1;
    while (j < pass) : (j += 1)
        RenderCtx_SetGlslTextureUniform(ctx, &p.unif.PassPrev[pass - j], passes[j].width, passes[j].height, passes[j].gl_texture);
    // #parameter uniforms
    var pa = gs.first_param;
    while (pa) |param| : (pa = param.next) {
        const loc: c_int = @bitCast(param.uniform[pass]);
        if (loc >= 0)
            c.glUniform1f(loc, param.value);
    }

    c.glActiveTexture(c.GL_TEXTURE0);
}

/// The C casts a float straight to uint16; clamp so an absurd preset scale
/// cannot trap instead of silently truncating.
fn scaleToU16(v: f32) u16 {
    if (!(v > 0)) return 0;
    if (v >= 65535) return 65535;
    return @intFromFloat(v);
}

pub export fn GlslShader_Render(
    gs: *GlslShader,
    tex: *GlTextureWithSize,
    viewport_x: c_int,
    viewport_y: c_int,
    viewport_width: c_int,
    viewport_height: c_int,
) callconv(.c) void {
    const passes = gs.pass.?;
    passes[0].gl_texture = tex.gl_texture;
    passes[0].width = tex.width;
    passes[0].height = tex.height;

    var previous_framebuffer: c.GLint = 0;
    c.glGetIntegerv(c.GL_FRAMEBUFFER_BINDING, &previous_framebuffer);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, gs.gl_vbo);

    var pass: usize = 1;
    while (pass <= @as(usize, @intCast(gs.n_pass))) : (pass += 1) {
        const last_pass = pass == @as(usize, @intCast(gs.n_pass));
        const p = &passes[pass];
        const prev = &passes[pass - 1];

        p.width = switch (p.scale_type_x) {
            GLSL_ABSOLUTE => scaleToU16(p.scale_x),
            GLSL_SOURCE => scaleToU16(@as(f32, @floatFromInt(prev.width)) * p.scale_x),
            GLSL_VIEWPORT => scaleToU16(@as(f32, @floatFromInt(viewport_width)) * p.scale_x),
            else => if (last_pass)
                scaleToU16(@floatFromInt(viewport_width))
            else
                scaleToU16(@as(f32, @floatFromInt(prev.width)) * p.scale_x),
        };

        p.height = switch (p.scale_type_y) {
            GLSL_ABSOLUTE => scaleToU16(p.scale_y),
            GLSL_SOURCE => scaleToU16(@as(f32, @floatFromInt(prev.height)) * p.scale_y),
            GLSL_VIEWPORT => scaleToU16(@as(f32, @floatFromInt(viewport_height)) * p.scale_y),
            else => if (last_pass)
                scaleToU16(@floatFromInt(viewport_height))
            else
                scaleToU16(@as(f32, @floatFromInt(prev.height)) * p.scale_y),
        };

        if (!last_pass) {
            // output to a texture
            c.glBindTexture(c.GL_TEXTURE_2D, p.gl_texture);
            if (p.srgb_framebuffer) {
                c.glEnable(c.GL_FRAMEBUFFER_SRGB);
                c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_SRGB8_ALPHA8, p.width, p.height, 0, c.GL_RGBA, c.GL_UNSIGNED_INT_8_8_8_8, null);
            } else {
                c.glTexImage2D(
                    c.GL_TEXTURE_2D,
                    0,
                    if (p.float_framebuffer) c.GL_RGBA32F else c.GL_RGBA,
                    p.width,
                    p.height,
                    0,
                    c.GL_RGBA,
                    if (p.float_framebuffer) c.GL_FLOAT else c.GL_UNSIGNED_INT_8_8_8_8,
                    null,
                );
            }
            c.glViewport(0, 0, p.width, p.height);
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, p.gl_fbo);
            c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, p.gl_texture, 0);
        } else {
            // output to screen
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, @bitCast(previous_framebuffer));
            c.glViewport(viewport_x, viewport_y, viewport_width, viewport_height);
        }

        c.glBindTexture(c.GL_TEXTURE_2D, prev.gl_texture);

        const filter: c_uint = if (p.filter != 0)
            p.filter
        else if (last_pass and config.g_config.linear_filtering)
            c.GL_LINEAR
        else
            c.GL_NEAREST;
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, @bitCast(filter));
        const min_filter: c_uint = if (p.mipmap_input)
            (if (filter == c.GL_LINEAR) c.GL_LINEAR_MIPMAP_LINEAR else c.GL_NEAREST_MIPMAP_NEAREST)
        else
            filter;
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, @bitCast(min_filter));
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, @bitCast(p.wrap_mode));
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, @bitCast(p.wrap_mode));
        if (p.mipmap_input)
            c.glGenerateMipmap(c.GL_TEXTURE_2D);
        c.glUseProgram(p.gl_program);

        var ctx: RenderCtx = undefined;
        ctx.texture_unit = 0;
        ctx.num_vaos = 0;
        ctx.offset = if (last_pass) @sizeOf(f32) * 8 else 0;
        GlslShader_SetShaderVars(gs, &ctx, pass);
        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
        for (0..ctx.num_vaos) |i|
            c.glDisableVertexAttribArray(ctx.vaos[i]);
        if (p.srgb_framebuffer)
            c.glDisable(c.GL_FRAMEBUFFER_SRGB);
    }

    c.glBindFramebuffer(c.GL_FRAMEBUFFER, @bitCast(previous_framebuffer));
    c.glUseProgram(0);
    c.glBindTexture(c.GL_TEXTURE_2D, 0);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

    // Store the input frame in the prev array, and extract the next one.
    if (gs.max_prev_frame != 0) {
        // 01234567
        //    43210
        // ^-- store pos
        //    ^-- load pos
        const store_pos = &gs.prev_frame[gs.frame_count & 7];
        const load_pos = &gs.prev_frame[(gs.frame_count -% @as(c_uint, @intCast(gs.max_prev_frame))) & 7];
        std.debug.assert(store_pos.gl_texture == 0);
        store_pos.* = tex.*;
        tex.* = load_pos.*;
        load_pos.* = std.mem.zeroes(GlTextureWithSize);
    }

    gs.frame_count +%= 1;
}

const testing = std.testing;

test "the shader structs match the C layout" {
    try testing.expectEqual(16, @sizeOf(GlslTextureUniform));
    try testing.expectEqual(844, @sizeOf(GlslUniforms));
    try testing.expectEqual(904, @sizeOf(GlslPass));
    try testing.expectEqual(8, @sizeOf(GlTextureWithSize));
    try testing.expectEqual(48, @sizeOf(GlslTexture));
    try testing.expectEqual(112, @sizeOf(GlslParam));
    try testing.expectEqual(120, @sizeOf(GlslShader));

    try testing.expectEqual(16, @offsetOf(GlslPass, "scale_x"));
    try testing.expectEqual(24, @offsetOf(GlslPass, "wrap_mode"));
    try testing.expectEqual(52, @offsetOf(GlslPass, "width"));
    try testing.expectEqual(56, @offsetOf(GlslPass, "unif"));
    try testing.expectEqual(32, @offsetOf(GlslParam, "uniform"));
    try testing.expectEqual(52, @offsetOf(GlslShader, "prev_frame"));
}

test "leading whitespace and line comments are skipped" {
    const s = "  \t\n// a comment\nreal";
    try testing.expectEqual(std.mem.indexOf(u8, s, "real").?, LengthOfInitialComments(s, s.len));
}

test "block comments are skipped" {
    const s = "/* hello */\nX";
    try testing.expectEqual(std.mem.indexOf(u8, s, "X").?, LengthOfInitialComments(s, s.len));
    const two = "/*a*//*b*/Y";
    try testing.expectEqual(std.mem.indexOf(u8, two, "Y").?, LengthOfInitialComments(two, two.len));
}

test "an unterminated block comment consumes nothing" {
    const s = "/* never closed";
    try testing.expectEqual(0, LengthOfInitialComments(s, s.len));
}

test "content with no leading comment is left alone" {
    const s = "#version 330\n";
    try testing.expectEqual(0, LengthOfInitialComments(s, s.len));
    try testing.expectEqual(0, LengthOfInitialComments("", 0));
}

test "a lone slash still counts as consumed, as in the C" {
    // The C gives back only the second character, so the '/' stays eaten.
    const s = "/x";
    try testing.expectEqual(1, LengthOfInitialComments(s, s.len));
    // A trailing slash at the very end backs up instead.
    const t = "/";
    try testing.expectEqual(0, LengthOfInitialComments(t, t.len));
}

test "scale types parse case-insensitively and fall back to none" {
    try testing.expectEqual(GLSL_SOURCE, ParseScaleType("source"));
    try testing.expectEqual(GLSL_SOURCE, ParseScaleType("SOURCE"));
    try testing.expectEqual(GLSL_VIEWPORT, ParseScaleType("viewport"));
    try testing.expectEqual(GLSL_ABSOLUTE, ParseScaleType("absolute"));
    try testing.expectEqual(GLSL_NONE, ParseScaleType("nonsense"));
}

test "wrap modes map onto the GL enums and default to clamp-to-border" {
    try testing.expectEqual(@as(c_uint, c.GL_REPEAT), ParseWrapMode("repeat"));
    try testing.expectEqual(@as(c_uint, c.GL_CLAMP_TO_EDGE), ParseWrapMode("clamp_to_edge"));
    try testing.expectEqual(@as(c_uint, c.GL_CLAMP), ParseWrapMode("clamp"));
    try testing.expectEqual(@as(c_uint, c.GL_CLAMP_TO_BORDER), ParseWrapMode("anything else"));
}

test "a glsl filename is recognised only by its extension" {
    try testing.expect(IsGlslFilename("shader.glsl"));
    try testing.expect(IsGlslFilename("a/b/c.glsl"));
    try testing.expect(!IsGlslFilename("shader.glslp"));
    try testing.expect(!IsGlslFilename("preset.cgp"));
    try testing.expect(!IsGlslFilename(".gls"));
}

test "float scales truncate toward zero and cannot trap" {
    try testing.expectEqual(0, scaleToU16(0.0));
    try testing.expectEqual(0, scaleToU16(-5.0));
    try testing.expectEqual(512, scaleToU16(512.0));
    try testing.expectEqual(768, scaleToU16(768.9));
    try testing.expectEqual(65535, scaleToU16(1.0e9));
}

test "the ortho matrix is the one the passes upload" {
    try testing.expectEqual(16, kMvpMatrixOrtho.len);
    try testing.expectEqual(2.0, kMvpMatrixOrtho[0]);
    try testing.expectEqual(2.0, kMvpMatrixOrtho[5]);
    try testing.expectEqual(-1.0, kMvpMatrixOrtho[10]);
    try testing.expectEqual(-1.0, kMvpMatrixOrtho[12]);
    try testing.expectEqual(-1.0, kMvpMatrixOrtho[13]);
    try testing.expectEqual(1.0, kMvpMatrixOrtho[15]);
}

test "the vao budget covers every pass" {
    try testing.expectEqual(51, kMaxVaosInRenderCtx);
    try testing.expectEqual(kMaxVaosInRenderCtx, @typeInfo(@FieldType(RenderCtx, "vaos")).array.len);
}
