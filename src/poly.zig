//! Port of src/poly.c: the polyhedron renderer used for the triforce and
//! crystal cutscenes. It is a direct transcription of the original 65816
//! routines, so it keeps their habit of passing state through fixed work-ram
//! locations rather than arguments.
const std = @import("std");
const vars = @import("variables.zig");

const g_ram = &vars.g_ram;

// The work-ram globals this file uses, aliased so the code below reads the way
// the C did.
const poly_config1 = vars.poly_config1;
const poly_which_model = vars.poly_which_model;
const poly_a = vars.poly_a;
const poly_b = vars.poly_b;
const poly_base_x = vars.poly_base_x;
const poly_base_y = vars.poly_base_y;
const poly_var1 = vars.poly_var1;
const poly_config_num_vertex = vars.poly_config_num_vertex;
const poly_config_num_polys = vars.poly_config_num_polys;
const poly_fromlut_ptr2 = vars.poly_fromlut_ptr2;
const poly_fromlut_ptr4 = vars.poly_fromlut_ptr4;
const poly_fromlut_x = vars.poly_fromlut_x;
const poly_fromlut_y = vars.poly_fromlut_y;
const poly_fromlut_z = vars.poly_fromlut_z;
const poly_f0 = vars.poly_f0;
const poly_f1 = vars.poly_f1;
const poly_f2 = vars.poly_f2;
const poly_num_vertex_in_poly = vars.poly_num_vertex_in_poly;
const poly_raster_color_config = vars.poly_raster_color_config;
const poly_sin_a = vars.poly_sin_a;
const poly_cos_a = vars.poly_cos_a;
const poly_sin_b = vars.poly_sin_b;
const poly_cos_b = vars.poly_cos_b;
const poly_e0 = vars.poly_e0;
const poly_e1 = vars.poly_e1;
const poly_e2 = vars.poly_e2;
const poly_e3 = vars.poly_e3;
const poly_arr_x = vars.poly_arr_x;
const poly_arr_y = vars.poly_arr_y;
const poly_tmp0 = vars.poly_tmp0;
const poly_tmp1 = vars.poly_tmp1;
const poly_tmp2 = vars.poly_tmp2;
const poly_raster_color0 = vars.poly_raster_color0;
const poly_raster_color1 = vars.poly_raster_color1;
const poly_raster_dst_ptr = vars.poly_raster_dst_ptr;
const poly_xy_coords = vars.poly_xy_coords;
const poly_total_num_steps = vars.poly_total_num_steps;
const poly_x0_cur = vars.poly_x0_cur;
const poly_y0_cur = vars.poly_y0_cur;
const poly_x0_target = vars.poly_x0_target;
const poly_y0_trig = vars.poly_y0_trig;
const poly_x0_frac = vars.poly_x0_frac;
const poly_x0_step = vars.poly_x0_step;
const poly_cur_vertex_idx0 = vars.poly_cur_vertex_idx0;
const poly_x1_cur = vars.poly_x1_cur;
const poly_y1_cur = vars.poly_y1_cur;
const poly_x1_target = vars.poly_x1_target;
const poly_y1_trig = vars.poly_y1_trig;
const poly_x1_frac = vars.poly_x1_frac;
const poly_x1_step = vars.poly_x1_step;
const poly_cur_vertex_idx1 = vars.poly_cur_vertex_idx1;
const poly_raster_numfull = vars.poly_raster_numfull;
const polyhedral_buffer = vars.polyhedral_buffer;

/// types.h BYTE(x): the low byte of a 16-bit work-ram word.
fn loByte(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

/// types.h HIBYTE(x).
fn hiByte(p: *align(1) u16) *u8 {
    return &@as([*]u8, @ptrCast(p))[1];
}

fn signed(v: u16) i16 {
    return @bitCast(v);
}

const kPolySinCos = [320]i8{
    0,   2,   3,   5,   6,   8,   9,   11,  12,  14,  16,  17,  19,  20,  22,  23,
    24,  26,  27,  29,  30,  32,  33,  34,  36,  37,  38,  39,  41,  42,  43,  44,
    45,  46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  56,  57,  58,  59,
    59,  60,  60,  61,  61,  62,  62,  62,  63,  63,  63,  64,  64,  64,  64,  64,
    64,  64,  64,  64,  64,  64,  63,  63,  63,  62,  62,  62,  61,  61,  60,  60,
    59,  59,  58,  57,  56,  56,  55,  54,  53,  52,  51,  50,  49,  48,  47,  46,
    45,  44,  43,  42,  41,  39,  38,  37,  36,  34,  33,  32,  30,  29,  27,  26,
    24,  23,  22,  20,  19,  17,  16,  14,  12,  11,  9,   8,   6,   5,   3,   2,
    0,   -2,  -3,  -5,  -6,  -8,  -9,  -11, -12, -14, -16, -17, -19, -20, -22, -23,
    -24, -26, -27, -29, -30, -32, -33, -34, -36, -37, -38, -39, -41, -42, -43, -44,
    -45, -46, -47, -48, -49, -50, -51, -52, -53, -54, -55, -56, -56, -57, -58, -59,
    -59, -60, -60, -61, -61, -62, -62, -62, -63, -63, -63, -64, -64, -64, -64, -64,
    -64, -64, -64, -64, -64, -64, -63, -63, -63, -62, -62, -62, -61, -61, -60, -60,
    -59, -59, -58, -57, -56, -56, -55, -54, -53, -52, -51, -50, -49, -48, -47, -46,
    -45, -44, -43, -42, -41, -39, -38, -37, -36, -34, -33, -32, -30, -29, -27, -26,
    -24, -23, -22, -20, -19, -17, -16, -14, -12, -11, -9,  -8,  -6,  -5,  -3,  -2,
    0,   2,   3,   5,   6,   8,   9,   11,  12,  14,  16,  17,  19,  20,  22,  23,
    24,  26,  27,  29,  30,  32,  33,  34,  36,  37,  38,  39,  41,  42,  43,  44,
    45,  46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  56,  57,  58,  59,
    59,  60,  60,  61,  61,  62,  62,  62,  63,  63,  63,  64,  64,  64,  64,  64,
};

/// Three signed bytes with no padding: the code walks these as a flat byte run.
const Vertex3 = extern struct {
    x: i8,
    y: i8,
    z: i8,
};

const kPoly0_Vtx = [6]Vertex3{
    .{ .x = 0, .y = 65, .z = 0 },
    .{ .x = 0, .y = -65, .z = 0 },
    .{ .x = 0, .y = 0, .z = -40 },
    .{ .x = -40, .y = 0, .z = 0 },
    .{ .x = 0, .y = 0, .z = 40 },
    .{ .x = 40, .y = 0, .z = 0 },
};

const kPoly0_Polys = [40]u8{
    3, 0, 5, 2, 4,
    3, 0, 2, 3, 1,
    3, 0, 3, 4, 2,
    3, 0, 4, 5, 3,
    3, 1, 2, 5, 4,
    3, 1, 3, 2, 1,
    3, 1, 4, 3, 2,
    3, 1, 5, 4, 3,
};

const kPoly1_Vtx = [6]Vertex3{
    .{ .x = 0, .y = 40, .z = 10 },
    .{ .x = 40, .y = -40, .z = 10 },
    .{ .x = -40, .y = -40, .z = 10 },
    .{ .x = 0, .y = 40, .z = -10 },
    .{ .x = -40, .y = -40, .z = -10 },
    .{ .x = 40, .y = -40, .z = -10 },
};

const kPoly1_Polys = [28]u8{
    3, 0, 1, 2, 7,
    3, 3, 4, 5, 6,
    4, 0, 3, 5, 1, 5,
    4, 1, 5, 4, 2, 4,
    4, 3, 0, 2, 4, 3,
};

const PolyConfig = struct {
    num_vtx: u8,
    num_poly: u8,
    vtx_val: u16,
    polys_val: u16,
    vertex: []const Vertex3,
    poly: []const u8,
};

const kPolyConfigs = [2]PolyConfig{
    .{ .num_vtx = 6, .num_poly = 8, .vtx_val = 0xff98, .polys_val = 0xffaa, .vertex = &kPoly0_Vtx, .poly = &kPoly0_Polys },
    .{ .num_vtx = 6, .num_poly = 5, .vtx_val = 0xffd2, .polys_val = 0xffe4, .vertex = &kPoly1_Vtx, .poly = &kPoly1_Polys },
};

const kPoly_RasterColors = [16]u32{
    0x00,       0xff,       0xff00,     0xffff,
    0xff0000,   0xff00ff,   0xffff00,   0xffffff,
    0xff000000, 0xff0000ff, 0xff00ff00, 0xff00ffff,
    0xffff0000, 0xffff00ff, 0xffffff00, 0xffffffff,
};

const kPoly_LeftSideMask = [8]u16{ 0xffff, 0x7f7f, 0x3f3f, 0x1f1f, 0xf0f, 0x707, 0x303, 0x101 };
const kPoly_RightSideMask = [8]u16{ 0x8080, 0xc0c0, 0xe0e0, 0xf0f0, 0xf8f8, 0xfcfc, 0xfefe, 0xffff };

pub export fn Poly_Divide(a: u16, b: u16) callconv(.c) u16 {
    poly_tmp1.* = if (a & 0x8000 != 0) 0 -% a else a;
    poly_tmp0.* = b;
    while (poly_tmp0.* >= 256) {
        poly_tmp0.* >>= 1;
        poly_tmp1.* >>= 1;
    }
    const q: u32 = @as(u32, poly_tmp1.*) / poly_tmp0.*;
    return if (a & 0x8000 != 0) @truncate(0 -% q) else @truncate(q);
}

pub export fn Poly_RunFrame() callconv(.c) void {
    Polyhedral_EmptyBitMapBuffer();
    Polyhedral_SetShapePointer();
    Polyhedral_SetRotationMatrix();
    Polyhedral_OperateRotation();
    Polyhedral_DrawPolyhedron();
}

pub export fn Polyhedral_SetShapePointer() callconv(.c) void { // 89f83d
    poly_var1.* = @as(u16, poly_config1.*) *% 2 +% 0x80;
    poly_tmp0.* = @as(u16, poly_which_model.*) *% 2;

    const cfg = &kPolyConfigs[poly_which_model.*];
    poly_config_num_vertex.* = cfg.num_vtx;
    poly_config_num_polys.* = cfg.num_poly;
    poly_fromlut_ptr2.* = cfg.vtx_val;
    poly_fromlut_ptr4.* = cfg.polys_val;
}

pub export fn Polyhedral_SetRotationMatrix() callconv(.c) void { // 89f864
    poly_sin_a.* = @bitCast(@as(i16, kPolySinCos[poly_a.*]));
    poly_cos_a.* = @bitCast(@as(i16, kPolySinCos[@as(usize, poly_a.*) + 64]));
    poly_sin_b.* = @bitCast(@as(i16, kPolySinCos[poly_b.*]));
    poly_cos_b.* = @bitCast(@as(i16, kPolySinCos[@as(usize, poly_b.*) + 64]));
    poly_e0.* = rotTerm(poly_sin_b.*, poly_sin_a.*);
    poly_e1.* = rotTerm(poly_cos_b.*, poly_cos_a.*);
    poly_e2.* = rotTerm(poly_cos_b.*, poly_sin_a.*);
    poly_e3.* = rotTerm(poly_sin_b.*, poly_cos_a.*);
}

/// (int16)hi * (int8)lo >> 8 << 2
fn rotTerm(hi: u16, lo: u16) u16 {
    const a: i32 = signed(hi);
    const b: i32 = @as(i8, @bitCast(@as(u8, @truncate(lo))));
    return @truncate(@as(u32, @bitCast((a * b >> 8) << 2)));
}

pub export fn Polyhedral_OperateRotation() callconv(.c) void { // 89f8fb
    const cfg = &kPolyConfigs[poly_which_model.*];
    var src: [*]const i8 = @ptrCast(cfg.vertex.ptr);
    var i: i32 = poly_config_num_vertex.*;
    src += @intCast(i * 3);
    while (true) {
        src -= 3;
        i -= 1;
        poly_fromlut_x.* = @bitCast(src[2]);
        poly_fromlut_y.* = @bitCast(src[1]);
        poly_fromlut_z.* = @bitCast(src[0]);
        Polyhedral_RotatePoint();
        Polyhedral_ProjectPoint();
        poly_arr_x[@intCast(i)] = poly_base_x.* +% @as(u8, @truncate(poly_f0.*));
        poly_arr_y[@intCast(i)] = poly_base_y.* -% @as(u8, @truncate(poly_f1.*));
        if (i == 0) break;
    }
}

pub export fn Polyhedral_RotatePoint() callconv(.c) void { // 89f931
    const x: i32 = @as(i8, @bitCast(poly_fromlut_x.*));
    const y: i32 = @as(i8, @bitCast(poly_fromlut_y.*));
    const z: i32 = @as(i8, @bitCast(poly_fromlut_z.*));

    poly_f0.* = trunc16(@as(i32, signed(poly_cos_b.*)) * z - @as(i32, signed(poly_sin_b.*)) * x);
    poly_f1.* = trunc16(@as(i32, signed(poly_e0.*)) * z +
        @as(i32, signed(poly_cos_a.*)) * y +
        @as(i32, signed(poly_e2.*)) * x);
    poly_f2.* = trunc16((@as(i32, signed(poly_e3.*)) * z >> 8) -
        (@as(i32, signed(poly_sin_a.*)) * y >> 8) +
        (@as(i32, signed(poly_e1.*)) * x >> 8) +
        @as(i32, poly_var1.*));
}

fn trunc16(v: i32) u16 {
    return @truncate(@as(u32, @bitCast(v)));
}

pub export fn Polyhedral_ProjectPoint() callconv(.c) void { // 89f9d6
    poly_f0.* = Poly_Divide(poly_f0.*, poly_f2.*);
    poly_f1.* = Poly_Divide(poly_f1.*, poly_f2.*);
}

pub export fn Polyhedral_DrawPolyhedron() callconv(.c) void { // 89fa4f
    const cfg = &kPolyConfigs[poly_which_model.*];
    var src: [*]const u8 = cfg.poly.ptr;
    while (true) {
        poly_num_vertex_in_poly.* = src[0];
        src += 1;
        loByte(poly_tmp0).* = poly_num_vertex_in_poly.*;
        poly_xy_coords[0] = poly_num_vertex_in_poly.* *% 2;

        var i: usize = 1;
        while (true) {
            const j = src[0];
            src += 1;
            poly_xy_coords[i + 0] = poly_arr_x[j];
            poly_xy_coords[i + 1] = poly_arr_y[j];
            i += 2;
            loByte(poly_tmp0).* -%= 1;
            if (loByte(poly_tmp0).* == 0) break;
        }

        poly_raster_color_config.* = src[0];
        src += 1;
        const order = Polyhedral_CalculateCrossProduct();
        if (order > 0) {
            Polyhedral_SetForegroundColor();
            Polyhedral_DrawFace();
        }
        poly_config_num_polys.* -%= 1;
        if (poly_config_num_polys.* == 0) break;
    }
}

pub export fn Polyhedral_SetForegroundColor() callconv(.c) void { // 89faca
    const t: u8 = if (poly_which_model.* != 0) (poly_config1.* >> 5) else 0;
    const shifted: u32 = @as(u32, poly_tmp0.*) << @intCast(t + 1);
    const a: u8 = @truncate(shifted >> 8);
    Polyhedral_SetColorMask(if (a <= 1) 1 else if (a >= 7) 7 else a);
}

pub export fn Polyhedral_CalculateCrossProduct() callconv(.c) i16 { // 89fb24
    var a: i16 = @truncate(@as(i32, poly_xy_coords[3]) - @as(i32, poly_xy_coords[1]));
    poly_tmp0.* = trunc16(@as(i32, a) * @as(i8, @bitCast(poly_xy_coords[6] -% poly_xy_coords[4])));
    a = @truncate(@as(i32, poly_xy_coords[5]) - @as(i32, poly_xy_coords[3]));
    poly_tmp0.* = trunc16(@as(i32, signed(poly_tmp0.*)) -
        @as(i32, a) * @as(i8, @bitCast(poly_xy_coords[4] -% poly_xy_coords[2])));
    return signed(poly_tmp0.*);
}

pub export fn Polyhedral_SetColorMask(c: c_int) callconv(.c) void { // 89fcae
    const v = kPoly_RasterColors[@intCast(c)];
    poly_raster_color0.* = @truncate(v);
    poly_raster_color1.* = @truncate(v >> 16);
}

pub export fn Polyhedral_EmptyBitMapBuffer() callconv(.c) void { // 89fd04
    @memset(polyhedral_buffer[0..0x800], 0);
}

pub export fn Polyhedral_DrawFace() callconv(.c) void { // 89fd1e
    var n: i32 = poly_xy_coords[0];
    var min_y: u8 = poly_xy_coords[@intCast(n)];
    var min_idx: i32 = n;
    while (true) {
        n -= 2;
        if (n == 0) break;
        if (poly_xy_coords[@intCast(n)] < min_y) {
            min_y = poly_xy_coords[@intCast(n)];
            min_idx = n;
        }
    }
    const banked: i32 = (@as(i32, min_y & 0x38) ^ (if (min_y & 0x20 != 0) @as(i32, 0x24) else 0)) << 6;
    poly_raster_dst_ptr.* = trunc16(0xe800 + banked + @as(i32, min_y & 7) * 2);
    poly_cur_vertex_idx0.* = @intCast(min_idx);
    poly_cur_vertex_idx1.* = @intCast(min_idx);
    poly_total_num_steps.* = poly_xy_coords[0] >> 1;
    poly_y0_cur.* = poly_xy_coords[@intCast(min_idx)];
    poly_y1_cur.* = poly_y0_cur.*;
    poly_x0_cur.* = poly_xy_coords[@intCast(min_idx - 1)];
    poly_x1_cur.* = poly_x0_cur.*;
    if (Polyhedral_SetLeft() or Polyhedral_SetRight())
        return;
    while (true) {
        Polyhedral_FillLine();
        if (loByte(poly_raster_dst_ptr).* != 0xe) {
            poly_raster_dst_ptr.* +%= 2;
        } else {
            const a: u8 = hiByte(poly_raster_dst_ptr).* +% 2;
            poly_raster_dst_ptr.* = @as(u16, a ^ (if (a & 8 != 0) @as(u8, 0) else 0x19)) << 8;
        }
        if (poly_y0_cur.* == poly_y0_trig.*) {
            poly_x0_cur.* = poly_x0_target.*;
            if (Polyhedral_SetLeft())
                return;
        }
        poly_y0_cur.* +%= 1;
        if (poly_y1_cur.* == poly_y1_trig.*) {
            poly_x1_cur.* = poly_x1_target.*;
            if (Polyhedral_SetRight())
                return;
        }
        poly_y1_cur.* +%= 1;
        poly_x0_frac.* +%= poly_x0_step.*;
        poly_x1_frac.* +%= poly_x1_step.*;
    }
}

pub export fn Polyhedral_FillLine() callconv(.c) void { // 89fdcf
    const left = kPoly_LeftSideMask[(poly_x0_frac.* >> 8) & 7];
    const right = kPoly_RightSideMask[(poly_x1_frac.* >> 8) & 7];
    poly_tmp2.* = @truncate((poly_x0_frac.* >> 8) & 0x38);
    var d0: i32 = (poly_x1_frac.* >> 8) & 0x38;
    var ptr: [*]align(1) u16 = @ptrCast(&g_ram[@intCast(@as(i32, poly_raster_dst_ptr.*) + d0 * 4)]);
    d0 -= poly_tmp2.*;
    if (d0 == 0) {
        poly_tmp1.* = left & right;
        ptr[0] ^= (ptr[0] ^ poly_raster_color0.*) & poly_tmp1.*;
        ptr[8] ^= (ptr[8] ^ poly_raster_color1.*) & poly_tmp1.*;
        return;
    }
    if (d0 < 0)
        return;
    var n: i32 = d0 >> 3;
    ptr[0] ^= (ptr[0] ^ poly_raster_color0.*) & right;
    ptr[8] ^= (ptr[8] ^ poly_raster_color1.*) & right;
    ptr -= 0x10;
    while (true) {
        n -= 1;
        if (n == 0) break;
        ptr[0] = poly_raster_color0.*;
        ptr[8] = poly_raster_color1.*;
        ptr -= 0x10;
    }
    ptr[0] ^= (ptr[0] ^ poly_raster_color0.*) & left;
    ptr[8] ^= (ptr[8] ^ poly_raster_color1.*) & left;
    poly_tmp1.* = left;
    poly_raster_numfull.* = 0;
}

pub export fn Polyhedral_SetLeft() callconv(.c) bool { // 89feb4
    var i: i32 = undefined;
    while (true) {
        poly_total_num_steps.* -%= 1;
        if (poly_total_num_steps.* & 0x80 != 0)
            return true;
        i = @as(i32, poly_cur_vertex_idx0.*) - 2;
        if (i == 0)
            i = poly_xy_coords[0];
        if (poly_xy_coords[@intCast(i)] < poly_y0_cur.*)
            return true;
        if (poly_xy_coords[@intCast(i)] != poly_y0_cur.*)
            break;
        poly_x0_cur.* = poly_xy_coords[@intCast(i - 1)];
        poly_cur_vertex_idx0.* = @intCast(i);
    }
    poly_y0_trig.* = poly_xy_coords[@intCast(i)];
    poly_x0_target.* = poly_xy_coords[@intCast(i - 1)];
    poly_cur_vertex_idx0.* = @intCast(i);
    const u: i32 = @as(i32, poly_x0_target.*) - @as(i32, poly_x0_cur.*);
    var t: i32 = if (u < 0) -u else u;
    t = @divTrunc((t & 0xff) << 8, poly_y0_trig.* -% poly_y0_cur.*);
    poly_x0_frac.* = trunc16((@as(i32, poly_x0_cur.*) << 8) | 0x80);
    poly_x0_step.* = trunc16(if (u < 0) -t else t);
    return false;
}

pub export fn Polyhedral_SetRight() callconv(.c) bool { // 89ff1e
    var i: i32 = undefined;
    while (true) {
        poly_total_num_steps.* -%= 1;
        if (poly_total_num_steps.* & 0x80 != 0)
            return true;
        i = poly_cur_vertex_idx1.*;
        if (i == poly_xy_coords[0])
            i = 0;
        i += 2;
        if (poly_xy_coords[@intCast(i)] < poly_y1_cur.*)
            return true;
        if (poly_xy_coords[@intCast(i)] != poly_y1_cur.*)
            break;
        poly_x1_cur.* = poly_xy_coords[@intCast(i - 1)];
        poly_cur_vertex_idx1.* = @intCast(i);
    }
    poly_y1_trig.* = poly_xy_coords[@intCast(i)];
    poly_x1_target.* = poly_xy_coords[@intCast(i - 1)];
    poly_cur_vertex_idx1.* = @intCast(i);
    const u: i32 = @as(i32, poly_x1_target.*) - @as(i32, poly_x1_cur.*);
    var t: i32 = if (u < 0) -u else u;
    t = @divTrunc((t & 0xff) << 8, poly_y1_trig.* -% poly_y1_cur.*);
    poly_x1_frac.* = trunc16((@as(i32, poly_x1_cur.*) << 8) | 0x80);
    poly_x1_step.* = trunc16(if (u < 0) -t else t);
    return false;
}

const testing = std.testing;

test "Poly_Divide scales both operands down until the divisor is a byte" {
    // 1000 / 8: the divisor is already under 256, so it divides straight.
    try testing.expectEqual(@as(u16, 125), Poly_Divide(1000, 8));
    // A divisor of 512 gets halved once, and so does the dividend.
    try testing.expectEqual(@as(u16, 1), Poly_Divide(512, 512));
    try testing.expectEqual(@as(u16, 0), Poly_Divide(0, 1));
}

test "Poly_Divide keeps the sign of the dividend" {
    const neg: u16 = @bitCast(@as(i16, -1000));
    try testing.expectEqual(@as(i16, -125), @as(i16, @bitCast(Poly_Divide(neg, 8))));
    // The scratch words hold the magnitudes, not the signed values.
    try testing.expectEqual(@as(u16, 1000 >> 0), poly_tmp1.* * 1);
}

test "the rotation matrix comes out of the sin/cos table" {
    poly_a.* = 0; // sin 0 = 0, cos 0 = 64
    poly_b.* = 0;
    Polyhedral_SetRotationMatrix();
    try testing.expectEqual(@as(i16, 0), signed(poly_sin_a.*));
    try testing.expectEqual(@as(i16, 64), signed(poly_cos_a.*));
    try testing.expectEqual(@as(i16, 0), signed(poly_sin_b.*));
    try testing.expectEqual(@as(i16, 64), signed(poly_cos_b.*));
    // e1 = cos_b * cos_a >> 8 << 2 = 64 * 64 >> 8 << 2 = 64
    try testing.expectEqual(@as(i16, 64), signed(poly_e1.*));
    // e0 = sin_b * sin_a >> 8 << 2 = 0
    try testing.expectEqual(@as(i16, 0), signed(poly_e0.*));

    // A quarter turn: index 64 is the peak of the table.
    poly_a.* = 64;
    Polyhedral_SetRotationMatrix();
    try testing.expectEqual(@as(i16, 64), signed(poly_sin_a.*));
    try testing.expectEqual(@as(i16, 0), signed(poly_cos_a.*));
}

test "SetShapePointer picks up the model's vertex and poly counts" {
    poly_which_model.* = 0;
    poly_config1.* = 3;
    Polyhedral_SetShapePointer();
    try testing.expectEqual(@as(u16, 3 * 2 + 0x80), poly_var1.*);
    try testing.expectEqual(@as(u8, 6), poly_config_num_vertex.*);
    try testing.expectEqual(@as(u8, 8), poly_config_num_polys.*);
    try testing.expectEqual(@as(u16, 0xff98), poly_fromlut_ptr2.*);

    poly_which_model.* = 1;
    Polyhedral_SetShapePointer();
    try testing.expectEqual(@as(u8, 5), poly_config_num_polys.*);
    try testing.expectEqual(@as(u16, 0xffe4), poly_fromlut_ptr4.*);
}

test "SetColorMask splits a 32-bit colour across the two raster words" {
    Polyhedral_SetColorMask(15);
    try testing.expectEqual(@as(u16, 0xffff), poly_raster_color0.*);
    try testing.expectEqual(@as(u16, 0xffff), poly_raster_color1.*);
    Polyhedral_SetColorMask(1);
    try testing.expectEqual(@as(u16, 0x00ff), poly_raster_color0.*);
    try testing.expectEqual(@as(u16, 0x0000), poly_raster_color1.*);
    Polyhedral_SetColorMask(8);
    try testing.expectEqual(@as(u16, 0x0000), poly_raster_color0.*);
    try testing.expectEqual(@as(u16, 0xff00), poly_raster_color1.*);
}

test "EmptyBitMapBuffer clears exactly the 2k drawing buffer" {
    @memset(g_ram[0xE800 - 4 .. 0xE800 + 0x804], 0xcd);
    Polyhedral_EmptyBitMapBuffer();
    try testing.expectEqual(@as(u8, 0xcd), g_ram[0xE800 - 1]); // just before
    try testing.expectEqual(@as(u8, 0), g_ram[0xE800]);
    try testing.expectEqual(@as(u8, 0), g_ram[0xE800 + 0x7ff]);
    try testing.expectEqual(@as(u8, 0xcd), g_ram[0xE800 + 0x800]); // just after
}

test "the cross product picks out the winding of the first three points" {
    // Coordinates are stored as x,y pairs starting at index 1.
    poly_xy_coords[0] = 6;
    poly_xy_coords[1] = 0; // x0
    poly_xy_coords[2] = 0; // y0
    poly_xy_coords[3] = 10; // x1
    poly_xy_coords[4] = 0; // y1
    poly_xy_coords[5] = 10; // x2
    poly_xy_coords[6] = 10; // y2
    const cw = Polyhedral_CalculateCrossProduct();

    // Mirror the shape and the sign flips.
    poly_xy_coords[5] = 10;
    poly_xy_coords[6] = 0;
    poly_xy_coords[3] = 10;
    poly_xy_coords[4] = 10;
    const ccw = Polyhedral_CalculateCrossProduct();
    try testing.expect((cw > 0) != (ccw > 0));
}

test "the sin/cos table is a quarter-wave, peaking at 64" {
    try testing.expectEqual(320, kPolySinCos.len);
    try testing.expectEqual(@as(i8, 0), kPolySinCos[0]);
    try testing.expectEqual(@as(i8, 64), kPolySinCos[64]); // quarter turn
    try testing.expectEqual(@as(i8, 0), kPolySinCos[128]); // half turn
    try testing.expectEqual(@as(i8, -64), kPolySinCos[192]);
    // The last 64 entries repeat the start so that index+64 never runs off.
    for (0..64) |i|
        try testing.expectEqual(kPolySinCos[i], kPolySinCos[256 + i]);
}

test "the shape tables came over intact" {
    try testing.expectEqual(3, @sizeOf(Vertex3)); // walked as a flat byte run
    try testing.expectEqual(6, kPoly0_Vtx.len);
    try testing.expectEqual(40, kPoly0_Polys.len);
    try testing.expectEqual(28, kPoly1_Polys.len);
    try testing.expectEqual(@as(i8, 65), kPoly0_Vtx[0].y);
    try testing.expectEqual(@as(i8, -40), kPoly1_Vtx[2].x);
    try testing.expectEqual(16, kPoly_RasterColors.len);
    try testing.expectEqual(@as(u32, 0xffffffff), kPoly_RasterColors[15]);
    try testing.expectEqual(@as(u16, 0xffff), kPoly_LeftSideMask[0]);
    try testing.expectEqual(@as(u16, 0xffff), kPoly_RightSideMask[7]);
}
