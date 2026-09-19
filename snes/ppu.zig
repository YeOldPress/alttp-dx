//! Port of snes/ppu.c: the picture processing unit, both the original
//! per-pixel renderer and the faster whole-line one.
//!
//! The renderer leans hard on pointer arithmetic and macro-unrolled bit
//! twiddling. The structure is kept as-is, with the macros turned into inline
//! functions, because the exact ordering of the priority comparisons is what
//! decides which layer wins a pixel.
const std = @import("std");
const snes_types = @import("snes_types.zig");
const ppu_types = @import("ppu_types.zig");

const SaveLoadFunc = snes_types.SaveLoadFunc;
const Ppu = ppu_types.Ppu;
const BgLayer = ppu_types.BgLayer;
const PpuZbufType = ppu_types.PpuZbufType;
const PpuPixelPrioBufs = ppu_types.PpuPixelPrioBufs;
const kPpuExtraLeftRight = ppu_types.kPpuExtraLeftRight;
const kPpuRenderFlags_NewRenderer = ppu_types.kPpuRenderFlags_NewRenderer;
const kPpuRenderFlags_4x4Mode7 = ppu_types.kPpuRenderFlags_4x4Mode7;
const kPpuRenderFlags_NoSpriteLimits = ppu_types.kPpuRenderFlags_NoSpriteLimits;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

const kSpriteSizes = [8][2]u8{
    .{ 8, 16 }, .{ 8, 32 }, .{ 8, 64 }, .{ 16, 32 },
    .{ 16, 64 }, .{ 32, 64 }, .{ 16, 32 }, .{ 16, 32 },
};

const kWindow1Inversed: u32 = 1;
const kWindow1Enabled: u32 = 2;
const kWindow2Inversed: u32 = 4;
const kWindow2Enabled: u32 = 8;

fn isScreenEnabled(ppu: *Ppu, sub: u1, layer: u32) bool {
    return ppu.screenEnabled[sub] & (@as(u32, 1) << @intCast(layer)) != 0;
}

fn isScreenWindowed(ppu: *Ppu, sub: u1, layer: u32) bool {
    return ppu.screenWindowed[sub] & (@as(u32, 1) << @intCast(layer)) != 0;
}

fn isMosaicEnabled(ppu: *Ppu, layer: u32) bool {
    return ppu.mosaicEnabled & (@as(u32, 1) << @intCast(layer)) != 0;
}

fn getWindowFlags(ppu: *Ppu, layer: u32) u32 {
    return ppu.windowsel >> @intCast(layer * 4);
}

/// level6 should be set if it's from palette 0xc0 which means color math is not applied
fn spritePrioToPrio(prio: u32, level6: bool) u32 {
    return ((prio * 4 + 2) * 16 + 4 + (if (level6) @as(u32, 2) else 0));
}

fn spritePrioToPrioHi(prio: u32) u32 {
    return prio * 4 + 2;
}

fn intMin(a: i32, b: i32) i32 {
    return if (a < b) a else b;
}

fn intMax(a: i32, b: i32) i32 {
    return if (a > b) a else b;
}

fn uintMin(a: u32, b: u32) u32 {
    return if (a < b) a else b;
}

pub export fn ppu_init() callconv(.c) *Ppu {
    const ppu: *Ppu = @ptrCast(@alignCast(malloc(@sizeOf(Ppu)).?));
    ppu.extraLeftRight = kPpuExtraLeftRight;
    return ppu;
}

pub export fn ppu_free(ppu: *Ppu) callconv(.c) void {
    free(ppu);
}

pub export fn ppu_reset(ppu: *Ppu) callconv(.c) void {
    @memset(&ppu.vram, 0);
    ppu.lastBrightnessMult = 0xff;
    ppu.lastMosaicModulo = 0xff;
    ppu.extraLeftCur = 0;
    ppu.extraRightCur = 0;
    ppu.extraBottomCur = 0;
    ppu.vramPointer = 0;
    ppu.vramIncrementOnHigh = false;
    ppu.vramIncrement = 1;
    @memset(&ppu.cgram, 0);
    ppu.cgramPointer = 0;
    ppu.cgramSecondWrite = false;
    ppu.cgramBuffer = 0;
    @memset(&ppu.oam, 0);
    ppu.oamAdr = 0;
    ppu.oamSecondWrite = false;
    ppu.oamBuffer = 0;
    ppu.objTileAdr1 = 0x4000;
    ppu.objTileAdr2 = 0x5000;
    ppu.objSize = 0;
    @memset(&ppu.objBuffer.data, 0);
    for (&ppu.bgLayer) |*bg| {
        bg.hScroll = 0;
        bg.vScroll = 0;
        bg.tilemapWider = false;
        bg.tilemapHigher = false;
        bg.tilemapAdr = 0;
        bg.tileAdr = 0;
    }
    ppu.scrollPrev = 0;
    ppu.scrollPrev2 = 0;
    ppu.mosaicSize = 1;
    ppu.screenEnabled[0] = 0;
    ppu.screenEnabled[1] = 0;
    ppu.screenWindowed[0] = 0;
    ppu.screenWindowed[1] = 0;
    @memset(&ppu.m7matrix, 0);
    ppu.m7prev = 0;
    ppu.m7largeField = true;
    ppu.m7charFill = false;
    ppu.m7xFlip = false;
    ppu.m7yFlip = false;
    ppu.m7extBg_always_zero = false;
    ppu.m7startX = 0;
    ppu.m7startY = 0;
    ppu.windowsel = 0;
    ppu.window1left = 0;
    ppu.window1right = 0;
    ppu.window2left = 0;
    ppu.window2right = 0;
    ppu.clipMode = 0;
    ppu.preventMathMode = 0;
    ppu.addSubscreen = false;
    ppu.subtractColor = false;
    ppu.halfColor = false;
    ppu.mathEnabled = 0;
    ppu.fixedColorR = 0;
    ppu.fixedColorG = 0;
    ppu.fixedColorB = 0;
    ppu.forcedBlank = true;
    ppu.brightness = 0;
    ppu.mode = 0;
}

pub export fn ppu_saveload(ppu: *Ppu, func: *const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    var tmp = [_]u8{0} ** 556;

    func(ctx, &ppu.vram, 0x8000 * 2);
    func(ctx, &tmp, 10);
    func(ctx, &ppu.cgram, 512);
    func(ctx, &tmp, 556);
    func(ctx, &tmp, 520);
    for (&ppu.bgLayer) |*bg| {
        func(ctx, &tmp, 4);
        func(ctx, &bg.tilemapWider, 4);
        func(ctx, &tmp, 4);
    }
    func(ctx, &tmp, 123);
}

pub export fn PpuGetCurrentRenderScale(ppu: *Ppu, render_flags: u32) callconv(.c) c_int {
    const both = kPpuRenderFlags_4x4Mode7 | kPpuRenderFlags_NewRenderer;
    const hq = ppu.mode == 7 and !ppu.forcedBlank and (render_flags & both) == both;
    return if (hq) 4 else 1;
}

pub export fn PpuBeginDrawing(ppu: *Ppu, pixels: [*]u8, pitch: usize, render_flags: u32) callconv(.c) void {
    ppu.renderFlags = @truncate(render_flags);
    ppu.renderPitch = @truncate(pitch);
    ppu.renderBuffer = pixels;

    // Cache the brightness computation
    if (ppu.brightness != ppu.lastBrightnessMult) {
        const ppu_brightness: u32 = ppu.brightness;
        ppu.lastBrightnessMult = ppu.brightness;
        for (0..32) |i| {
            const v: u8 = @intCast(((i << 3) | (i >> 2)) * ppu_brightness / 15);
            ppu.brightnessMult[i] = v;
            ppu.brightnessMultHalf[i * 2] = v;
            ppu.brightnessMultHalf[i * 2 + 1] = v;
        }
        // Store 31 extra entries to remove the need for clamping to 31.
        @memset(ppu.brightnessMult[32..63], ppu.brightnessMult[31]);
    }

    if (PpuGetCurrentRenderScale(ppu, ppu.renderFlags) == 4) {
        for (0..256) |i| {
            const color: u32 = ppu.cgram[i];
            ppu.colorMapRgb[i] = @as(u32, ppu.brightnessMult[color & 0x1f]) << 16 |
                @as(u32, ppu.brightnessMult[(color >> 5) & 0x1f]) << 8 |
                ppu.brightnessMult[(color >> 10) & 0x1f];
        }
    }
}

/// The C writes four entries at a time through a uint64; every entry ends up
/// as 0x0500 either way.
fn clearBackdrop(buf: *PpuPixelPrioBufs) void {
    @memset(&buf.data, 0x0500);
}

pub export fn ppu_runLine(ppu: *Ppu, line: c_int) callconv(.c) void {
    if (line != 0) {
        if (ppu.mosaicSize != ppu.lastMosaicModulo) {
            const mod = ppu.mosaicSize;
            ppu.lastMosaicModulo = mod;
            var j: u8 = 0;
            for (&ppu.mosaicModulo, 0..) |*m, i| {
                m.* = @truncate(i -% j);
                j = if (j + 1 == mod) 0 else j + 1;
            }
        }
        // evaluate sprites
        clearBackdrop(&ppu.objBuffer);
        ppu.lineHasSprites = !ppu.forcedBlank and ppu_evaluateSprites(ppu, line - 1);

        const row: usize = @intCast(line - 1);
        const width = 256 + @as(usize, ppu.extraLeftRight) * 2;

        // outside of visible range?
        if (line >= 225 + @as(c_int, ppu.extraBottomCur)) {
            @memset(ppu.renderBuffer.?[row * ppu.renderPitch ..][0 .. 4 * width], 0);
            return;
        }

        if (ppu.renderFlags & kPpuRenderFlags_NewRenderer != 0) {
            PpuDrawWholeLine(ppu, @intCast(line));
        } else {
            if (ppu.mode == 7)
                ppu_calculateMode7Starts(ppu, line);
            var x: c_int = 0;
            while (x < 256) : (x += 1)
                ppu_handlePixel(ppu, x, line);

            const dst = ppu.renderBuffer.? + row * ppu.renderPitch;
            if (ppu.extraLeftRight != 0) {
                const n = 4 * @as(usize, ppu.extraLeftRight);
                @memset(dst[0..n], 0);
                @memset((dst + 4 * (256 + @as(usize, ppu.extraLeftRight)))[0..n], 0);
            }
        }
    }
}

const PpuWindows = struct {
    edges: [6]i16,
    nr: u32,
    bits: u8,
};

fn PpuWindows_Clear(win: *PpuWindows, ppu: *Ppu, layer: u32) void {
    win.edges[0] = -@as(i16, if (layer != 2) ppu.extraLeftCur else 0);
    win.edges[1] = 256 + @as(i16, if (layer != 2) ppu.extraRightCur else 0);
    win.nr = 1;
    win.bits = 0;
}

/// Evaluate which spans to render based on the window settings.
/// There are at most 5 windows. Algorithm from Snes9x.
fn PpuWindows_Calc(win: *PpuWindows, ppu: *Ppu, layer: u32) void {
    const winflags = getWindowFlags(ppu, layer);
    var nr: u32 = 1;
    const window_right: i16 = 256 + @as(i16, if (layer != 2) ppu.extraRightCur else 0);
    win.edges[0] = -@as(i16, if (layer != 2) ppu.extraLeftCur else 0);
    win.edges[1] = window_right;

    const w1_ena = (winflags & kWindow1Enabled) != 0 and ppu.window1left <= ppu.window1right;
    if (w1_ena) {
        if (@as(i16, ppu.window1left) > win.edges[0]) {
            win.edges[nr] = ppu.window1left;
            nr += 1;
            win.edges[nr] = window_right;
        }
        if (@as(i16, ppu.window1right) + 1 < window_right) {
            win.edges[nr] = @as(i16, ppu.window1right) + 1;
            nr += 1;
            win.edges[nr] = window_right;
        }
    }
    const w2_ena = (winflags & kWindow2Enabled) != 0 and ppu.window2left <= ppu.window2right;
    var i: u32 = 0;
    if (w2_ena) {
        var t: i16 = ppu.window2left;
        while (i <= nr and t != win.edges[i]) : (i += 1) {
            if (t < win.edges[i]) {
                var j: u32 = nr;
                nr += 1;
                while (true) : (j -= 1) {
                    win.edges[j + 1] = win.edges[j];
                    if (j == i) break;
                }
                win.edges[i] = t;
                break;
            }
        }
        t = @as(i16, ppu.window2right) + 1;
        while (i <= nr and t != win.edges[i]) : (i += 1) {
            if (t < win.edges[i]) {
                var j: u32 = nr;
                nr += 1;
                while (true) : (j -= 1) {
                    win.edges[j + 1] = win.edges[j];
                    if (j == i) break;
                }
                win.edges[i] = t;
                break;
            }
        }
    }
    win.nr = nr;
    // get a bitmap of how regions map to windows
    var w1_bits: u8 = 0;
    var w2_bits: u8 = 0;
    if (w1_ena) {
        var a: u32 = 0;
        while (win.edges[a] != ppu.window1left) a += 1;
        var b: u32 = a;
        while (win.edges[b] != @as(i16, ppu.window1right) + 1) b += 1;
        w1_bits = @truncate(((@as(u32, 1) << @intCast(b - a)) - 1) << @intCast(a));
    }
    if ((winflags & (kWindow1Enabled | kWindow1Inversed)) == (kWindow1Enabled | kWindow1Inversed))
        w1_bits = ~w1_bits;
    if (w2_ena) {
        var a: u32 = 0;
        while (win.edges[a] != ppu.window2left) a += 1;
        var b: u32 = a;
        while (win.edges[b] != @as(i16, ppu.window2right) + 1) b += 1;
        w2_bits = @truncate(((@as(u32, 1) << @intCast(b - a)) - 1) << @intCast(a));
    }
    if ((winflags & (kWindow2Enabled | kWindow2Inversed)) == (kWindow2Enabled | kWindow2Inversed))
        w2_bits = ~w2_bits;
    win.bits = w1_bits | w2_bits;
}

/// vram is 0x8000 words; the C masks only the base of a tile fetch and lets
/// the +8 ride along, which never leaves the array for real tile addresses.
fn vramAt(ppu: *Ppu, index: u32) u16 {
    return ppu.vram[index & 0x7fff];
}

fn read4bppBits(ppu: *Ppu, ta: i32, tile: u32) u32 {
    const base: u32 = @bitCast(ta +% @as(i32, @bitCast(tile *% 16)));
    return vramAt(ppu, base) | @as(u32, vramAt(ppu, base +% 8)) << 16;
}

fn read2bppBits(ppu: *Ppu, ta: i32, tile: u32) u32 {
    const base: u32 = @bitCast(ta +% @as(i32, @bitCast(tile *% 8)));
    return vramAt(ppu, base);
}

inline fn doPixel4bpp(comptime i: u5, bits: u32, z: PpuZbufType, dstz: [*]PpuZbufType) void {
    const pixel = ((bits >> i) & 1) | ((bits >> (7 + i)) & 2) | ((bits >> (14 + i)) & 4) | ((bits >> (21 + i)) & 8);
    if ((bits & (@as(u32, 0x01010101) << i)) != 0 and z > dstz[i])
        dstz[i] = z +% @as(PpuZbufType, @truncate(pixel));
}

inline fn doPixel4bppHflip(comptime i: u5, bits: u32, z: PpuZbufType, dstz: [*]PpuZbufType) void {
    const pixel = ((bits >> (7 - i)) & 1) | ((bits >> (14 - i)) & 2) | ((bits >> (21 - i)) & 4) | ((bits >> (28 - i)) & 8);
    if ((bits & (@as(u32, 0x80808080) >> i)) != 0 and z > dstz[i])
        dstz[i] = z +% @as(PpuZbufType, @truncate(pixel));
}

inline fn doPixel2bpp(comptime i: u5, bits: u32, z: PpuZbufType, dstz: [*]PpuZbufType) void {
    const pixel = ((bits >> i) & 1) | ((bits >> (7 + i)) & 2);
    if (pixel != 0 and z > dstz[i])
        dstz[i] = z +% @as(PpuZbufType, @truncate(pixel));
}

inline fn doPixel2bppHflip(comptime i: u5, bits: u32, z: PpuZbufType, dstz: [*]PpuZbufType) void {
    const pixel = ((bits >> (7 - i)) & 1) | ((bits >> (14 - i)) & 2);
    if (pixel != 0 and z > dstz[i])
        dstz[i] = z +% @as(PpuZbufType, @truncate(pixel));
}

/// Where a window span starts inside a z-buffer, which is offset by the extra
/// widescreen columns.
fn bufIndex(edge: i16) usize {
    return @intCast(@as(i32, edge) + kPpuExtraLeftRight);
}

/// The tilemap cursor walks 32 entries then flips to the other screen half.
const TileCursor = struct {
    tp: [*]const u16,
    tp_last: [*]const u16,
    tp_next: [*]const u16,

    fn init(tps: [2][*]const u16, x: u32) TileCursor {
        const half = (x >> 8) & 1;
        return .{
            .tp = tps[half] + ((x >> 3) & 0x1f),
            .tp_last = tps[half] + 31,
            .tp_next = tps[half ^ 1],
        };
    }

    fn cur(self: TileCursor) u32 {
        return self.tp[0];
    }

    fn next(self: *TileCursor) void {
        if (self.tp != self.tp_last) {
            self.tp += 1;
        } else {
            self.tp = self.tp_next;
            self.tp_next = self.tp_last - 31;
            self.tp_last = self.tp + 31;
        }
    }
};

fn tilemapPointers(ppu: *Ppu, bglayer: *BgLayer, y: u32) [2][*]const u16 {
    var sc_offs: u32 = @as(u32, bglayer.tilemapAdr) +% (((y >> 3) & 0x1f) << 5);
    if ((y & 0x100) != 0 and bglayer.tilemapHigher)
        sc_offs +%= if (bglayer.tilemapWider) 0x800 else 0x400;
    const wide: u32 = if (bglayer.tilemapWider) 0x400 else 0;
    return .{
        @ptrCast(&ppu.vram[sc_offs & 0x7fff]),
        @ptrCast(&ppu.vram[(sc_offs +% wide) & 0x7fff]),
    };
}

/// Draw a whole line of a 4bpp background layer into bgBuffers
fn PpuDrawBackground_4bpp(ppu: *Ppu, y_in: u32, sub: u1, layer: u32, zhi: PpuZbufType, zlo: PpuZbufType) void {
    const kPaletteShift = 6;
    if (!isScreenEnabled(ppu, sub, layer))
        return; // layer is completely hidden
    var win: PpuWindows = undefined;
    if (isScreenWindowed(ppu, sub, layer)) PpuWindows_Calc(&win, ppu, layer) else PpuWindows_Clear(&win, ppu, layer);
    const bglayer = &ppu.bgLayer[layer];
    const y = y_in +% bglayer.vScroll;
    const tps = tilemapPointers(ppu, bglayer, y);
    const tileadr: i32 = bglayer.tileAdr;
    const tileadr1: i32 = tileadr + 7 - @as(i32, @intCast(y & 0x7));
    const tileadr0: i32 = tileadr + @as(i32, @intCast(y & 0x7));

    var windex: u32 = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u32, 1) << @intCast(windex)) != 0)
            continue; // layer is disabled for this window part
        var x: u32 = @bitCast(@as(i32, win.edges[windex]) +% @as(i32, bglayer.hScroll));
        var w: u32 = @bitCast(@as(i32, win.edges[windex + 1]) - @as(i32, win.edges[windex]));
        var dstz: [*]PpuZbufType = ppu.bgBuffers[sub].data[bufIndex(win.edges[windex])..].ptr;
        var cursor = TileCursor.init(tps, x);

        // Handle clipped pixels on left side
        if (x & 7 != 0) {
            var curw: u32 = @intCast(intMin(@as(i32, @intCast(8 - (x & 7))), @bitCast(w)));
            w -= curw;
            const tile = cursor.cur();
            cursor.next();
            const ta = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            var z = if (tile & 0x2000 != 0) zhi else zlo;
            var bits = read4bppBits(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                z +%= @truncate((tile & 0x1c00) >> kPaletteShift);
                if (tile & 0x4000 != 0) {
                    bits >>= @intCast(x & 7);
                    x +%= curw;
                    while (true) {
                        doPixel4bpp(0, bits, z, dstz);
                        bits >>= 1;
                        dstz += 1;
                        curw -= 1;
                        if (curw == 0) break;
                    }
                } else {
                    bits <<= @intCast(x & 7);
                    x +%= curw;
                    while (true) {
                        doPixel4bppHflip(0, bits, z, dstz);
                        bits <<= 1;
                        dstz += 1;
                        curw -= 1;
                        if (curw == 0) break;
                    }
                }
            } else {
                dstz += curw;
            }
        }
        // Handle full tiles in the middle
        while (w >= 8) {
            const tile = cursor.cur();
            cursor.next();
            const ta = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            var z = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = read4bppBits(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                z +%= @truncate((tile & 0x1c00) >> kPaletteShift);
                if (tile & 0x4000 != 0) {
                    inline for (0..8) |i| doPixel4bpp(i, bits, z, dstz);
                } else {
                    inline for (0..8) |i| doPixel4bppHflip(i, bits, z, dstz);
                }
            }
            dstz += 8;
            w -= 8;
        }
        // Handle remaining clipped part
        if (w != 0) {
            const tile = cursor.cur();
            const ta = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            var z = if (tile & 0x2000 != 0) zhi else zlo;
            var bits = read4bppBits(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                z +%= @truncate((tile & 0x1c00) >> kPaletteShift);
                if (tile & 0x4000 != 0) {
                    while (true) {
                        doPixel4bpp(0, bits, z, dstz);
                        bits >>= 1;
                        dstz += 1;
                        w -= 1;
                        if (w == 0) break;
                    }
                } else {
                    while (true) {
                        doPixel4bppHflip(0, bits, z, dstz);
                        bits <<= 1;
                        dstz += 1;
                        w -= 1;
                        if (w == 0) break;
                    }
                }
            }
        }
    }
}

/// Draw a whole line of a 2bpp background layer into bgBuffers
fn PpuDrawBackground_2bpp(ppu: *Ppu, y_in: u32, sub: u1, layer: u32, zhi: PpuZbufType, zlo: PpuZbufType) void {
    const kPaletteShift = 8;
    if (!isScreenEnabled(ppu, sub, layer))
        return; // layer is completely hidden
    var win: PpuWindows = undefined;
    if (isScreenWindowed(ppu, sub, layer)) PpuWindows_Calc(&win, ppu, layer) else PpuWindows_Clear(&win, ppu, layer);
    const bglayer = &ppu.bgLayer[layer];
    const y = y_in +% bglayer.vScroll;
    const tps = tilemapPointers(ppu, bglayer, y);
    const tileadr: i32 = bglayer.tileAdr;
    const tileadr1: i32 = tileadr + 7 - @as(i32, @intCast(y & 0x7));
    const tileadr0: i32 = tileadr + @as(i32, @intCast(y & 0x7));

    var windex: u32 = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u32, 1) << @intCast(windex)) != 0)
            continue; // layer is disabled for this window part
        var x: u32 = @bitCast(@as(i32, win.edges[windex]) +% @as(i32, bglayer.hScroll));
        var w: u32 = @bitCast(@as(i32, win.edges[windex + 1]) - @as(i32, win.edges[windex]));
        var dstz: [*]PpuZbufType = ppu.bgBuffers[sub].data[bufIndex(win.edges[windex])..].ptr;
        var cursor = TileCursor.init(tps, x);

        // Handle clipped pixels on left side
        if (x & 7 != 0) {
            var curw: u32 = @intCast(intMin(@as(i32, @intCast(8 - (x & 7))), @bitCast(w)));
            w -= curw;
            const tile = cursor.cur();
            cursor.next();
            const ta = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            var z = if (tile & 0x2000 != 0) zhi else zlo;
            var bits = read2bppBits(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                z +%= @truncate((tile & 0x1c00) >> kPaletteShift);
                if (tile & 0x4000 != 0) {
                    bits >>= @intCast(x & 7);
                    x +%= curw;
                    while (true) {
                        doPixel2bpp(0, bits, z, dstz);
                        bits >>= 1;
                        dstz += 1;
                        curw -= 1;
                        if (curw == 0) break;
                    }
                } else {
                    bits <<= @intCast(x & 7);
                    x +%= curw;
                    while (true) {
                        doPixel2bppHflip(0, bits, z, dstz);
                        bits <<= 1;
                        dstz += 1;
                        curw -= 1;
                        if (curw == 0) break;
                    }
                }
            } else {
                dstz += curw;
            }
        }
        // Handle full tiles in the middle
        while (w >= 8) {
            const tile = cursor.cur();
            cursor.next();
            const ta = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            var z = if (tile & 0x2000 != 0) zhi else zlo;
            const bits = read2bppBits(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                z +%= @truncate((tile & 0x1c00) >> kPaletteShift);
                if (tile & 0x4000 != 0) {
                    inline for (0..8) |i| doPixel2bpp(i, bits, z, dstz);
                } else {
                    inline for (0..8) |i| doPixel2bppHflip(i, bits, z, dstz);
                }
            }
            dstz += 8;
            w -= 8;
        }
        // Handle remaining clipped part
        if (w != 0) {
            const tile = cursor.cur();
            const ta = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            var z = if (tile & 0x2000 != 0) zhi else zlo;
            var bits = read2bppBits(ppu, ta, tile & 0x3ff);
            if (bits != 0) {
                z +%= @truncate((tile & 0x1c00) >> kPaletteShift);
                if (tile & 0x4000 != 0) {
                    while (true) {
                        doPixel2bpp(0, bits, z, dstz);
                        bits >>= 1;
                        dstz += 1;
                        w -= 1;
                        if (w == 0) break;
                    }
                } else {
                    while (true) {
                        doPixel2bppHflip(0, bits, z, dstz);
                        bits <<= 1;
                        dstz += 1;
                        w -= 1;
                        if (w == 0) break;
                    }
                }
            }
        }
    }
}

/// Draw a whole line of a background layer into bgBuffers, with mosaic applied.
/// bpp picks the tile format; the two share everything but the bit extraction.
fn drawBackgroundMosaic(
    ppu: *Ppu,
    comptime bpp: u3,
    y_in: u32,
    sub: u1,
    layer: u32,
    zhi: PpuZbufType,
    zlo: PpuZbufType,
) void {
    const kPaletteShift = if (bpp == 4) 6 else 8;
    if (!isScreenEnabled(ppu, sub, layer))
        return; // layer is completely hidden
    var win: PpuWindows = undefined;
    if (isScreenWindowed(ppu, sub, layer)) PpuWindows_Calc(&win, ppu, layer) else PpuWindows_Clear(&win, ppu, layer);
    const bglayer = &ppu.bgLayer[layer];
    const y = @as(u32, ppu.mosaicModulo[y_in & 0x1ff]) +% bglayer.vScroll;
    const tps = tilemapPointers(ppu, bglayer, y);
    const tileadr: i32 = bglayer.tileAdr;
    const tileadr1: i32 = tileadr + 7 - @as(i32, @intCast(y & 0x7));
    const tileadr0: i32 = tileadr + @as(i32, @intCast(y & 0x7));

    var windex: u32 = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u32, 1) << @intCast(windex)) != 0)
            continue; // layer is disabled for this window part
        const sx = win.edges[windex];
        var dstz: [*]PpuZbufType = ppu.bgBuffers[sub].data[bufIndex(sx)..].ptr;
        const dstz_end: [*]PpuZbufType = ppu.bgBuffers[sub].data[bufIndex(win.edges[windex + 1])..].ptr;
        var x: u32 = @bitCast(@as(i32, sx) +% @as(i32, bglayer.hScroll));
        var cursor = TileCursor.init(tps, x);
        x &= 7;
        const mosaic_index: usize = @intCast(@as(i32, sx) & 0x1ff);
        var w: i32 = @as(i32, ppu.mosaicSize) - (@as(i32, sx) - @as(i32, ppu.mosaicModulo[mosaic_index]));
        while (true) {
            const remaining: i32 = @intCast((@intFromPtr(dstz_end) - @intFromPtr(dstz)) / 2);
            w = intMin(w, remaining);
            const tile = cursor.cur();
            const ta = if (tile & 0x8000 != 0) tileadr1 else tileadr0;
            const z = if (tile & 0x2000 != 0) zhi else zlo;
            var bits = if (bpp == 4) read4bppBits(ppu, ta, tile & 0x3ff) else read2bppBits(ppu, ta, tile & 0x3ff);
            var pixel: u32 = undefined;
            if (tile & 0x4000 != 0) {
                bits >>= @intCast(x);
                pixel = if (bpp == 4)
                    ((bits & 1) | ((bits >> 7) & 2) | ((bits >> 14) & 4) | ((bits >> 21) & 8))
                else
                    ((bits & 1) | ((bits >> 7) & 2));
            } else {
                bits <<= @intCast(x);
                pixel = if (bpp == 4)
                    (((bits >> 7) & 1) | ((bits >> 14) & 2) | ((bits >> 21) & 4) | ((bits >> 28) & 8))
                else
                    (((bits >> 7) & 1) | ((bits >> 14) & 2));
            }
            if (pixel != 0) {
                pixel += (tile & 0x1c00) >> kPaletteShift;
                var i: i32 = 0;
                while (i != w) : (i += 1) {
                    const at: usize = @intCast(i);
                    if (z > dstz[at])
                        dstz[at] = @as(PpuZbufType, @truncate(pixel)) +% z;
                }
            }
            dstz += @intCast(w);
            x +%= @intCast(w);
            while (x >= 8) : (x -= 8)
                cursor.next();
            w = ppu.mosaicSize;
            if (dstz == dstz_end) break;
        }
    }
}

fn PpuDrawSprites(ppu: *Ppu, y: u32, sub: u1, clear_backdrop: bool) void {
    _ = y;
    const layer = 4;
    if (!isScreenEnabled(ppu, sub, layer))
        return; // layer is completely hidden
    var win: PpuWindows = undefined;
    if (isScreenWindowed(ppu, sub, layer)) PpuWindows_Calc(&win, ppu, layer) else PpuWindows_Clear(&win, ppu, layer);
    var windex: u32 = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u32, 1) << @intCast(windex)) != 0)
            continue; // layer is disabled for this window part
        const left = win.edges[windex];
        const width: usize = @intCast(@as(i32, win.edges[windex + 1]) - @as(i32, left));
        const src = ppu.objBuffer.data[bufIndex(left)..];
        const dst = ppu.bgBuffers[sub].data[bufIndex(left)..];
        if (clear_backdrop) {
            @memcpy(dst[0..width], src[0..width]);
        } else {
            for (0..width) |i| {
                if (src[i] > dst[i])
                    dst[i] = src[i];
            }
        }
    }
}

/// expand 13-bit values to signed values
fn expand13(v: i16) i32 {
    return @as(i32, @as(i16, @bitCast(@as(u16, @bitCast(v)) << 3))) >> 3;
}

/// Assumes it's drawn on an empty backdrop
fn PpuDrawBackground_mode7(ppu: *Ppu, y_in: u32, sub: u1, z: PpuZbufType) void {
    const layer = 0;
    if (!isScreenEnabled(ppu, sub, layer))
        return; // layer is completely hidden
    var win: PpuWindows = undefined;
    if (isScreenWindowed(ppu, sub, layer)) PpuWindows_Calc(&win, ppu, layer) else PpuWindows_Clear(&win, ppu, layer);

    const hScroll = expand13(ppu.m7matrix[6]);
    const vScroll = expand13(ppu.m7matrix[7]);
    const xCenter = expand13(ppu.m7matrix[4]);
    const yCenter = expand13(ppu.m7matrix[5]);
    var clippedH = hScroll - xCenter;
    var clippedV = vScroll - yCenter;
    clippedH = if (clippedH & 0x2000 != 0) (clippedH | ~@as(i32, 1023)) else (clippedH & 1023);
    clippedV = if (clippedV & 0x2000 != 0) (clippedV | ~@as(i32, 1023)) else (clippedV & 1023);
    const mosaic_enabled = isMosaicEnabled(ppu, 0);
    const y: u32 = if (mosaic_enabled) ppu.mosaicModulo[y_in & 0x1ff] else y_in;
    const ry: i32 = if (ppu.m7yFlip) 255 - @as(i32, @intCast(y)) else @intCast(y);
    const m7startX: u32 = @bitCast((@as(i32, ppu.m7matrix[0]) * clippedH & ~@as(i32, 63)) +
        (@as(i32, ppu.m7matrix[1]) * ry & ~@as(i32, 63)) +
        (@as(i32, ppu.m7matrix[1]) * clippedV & ~@as(i32, 63)) + (xCenter << 8));
    const m7startY: u32 = @bitCast((@as(i32, ppu.m7matrix[2]) * clippedH & ~@as(i32, 63)) +
        (@as(i32, ppu.m7matrix[3]) * ry & ~@as(i32, 63)) +
        (@as(i32, ppu.m7matrix[3]) * clippedV & ~@as(i32, 63)) + (yCenter << 8));

    var windex: u32 = 0;
    while (windex < win.nr) : (windex += 1) {
        if (win.bits & (@as(u32, 1) << @intCast(windex)) != 0)
            continue; // layer is disabled for this window part
        const x = win.edges[windex];
        var dstz: [*]PpuZbufType = ppu.bgBuffers[sub].data[bufIndex(x)..].ptr;
        const dstz_end: [*]PpuZbufType = ppu.bgBuffers[sub].data[bufIndex(win.edges[windex + 1])..].ptr;
        const rx: i32 = if (ppu.m7xFlip) 255 - @as(i32, x) else @as(i32, x);
        var xpos: u32 = m7startX +% @as(u32, @bitCast(@as(i32, ppu.m7matrix[0]) * rx));
        var ypos: u32 = m7startY +% @as(u32, @bitCast(@as(i32, ppu.m7matrix[2]) * rx));
        const dx: u32 = if (ppu.m7xFlip)
            @bitCast(-@as(i32, ppu.m7matrix[0]))
        else
            @bitCast(@as(i32, ppu.m7matrix[0]));
        const dy: u32 = if (ppu.m7xFlip)
            @bitCast(-@as(i32, ppu.m7matrix[2]))
        else
            @bitCast(@as(i32, ppu.m7matrix[2]));
        const outside_value: u32 = if (ppu.m7largeField) 0x3ffff else 0xffffffff;
        const char_fill = ppu.m7charFill;
        if (mosaic_enabled) {
            const mosaic_index: usize = @intCast(@as(i32, x) & 0x1ff);
            var w: i32 = @as(i32, ppu.mosaicSize) - (@as(i32, x) - @as(i32, ppu.mosaicModulo[mosaic_index]));
            while (true) {
                const remaining: i32 = @intCast((@intFromPtr(dstz_end) - @intFromPtr(dstz)) / 2);
                w = intMin(w, remaining);
                skip: {
                    var tile: u32 = 0;
                    if ((xpos | ypos) > outside_value) {
                        if (!char_fill) break :skip;
                    } else {
                        tile = vramAt(ppu, (ypos >> 11 & 0x7f) * 128 + (xpos >> 11 & 0x7f)) & 0xff;
                    }
                    const pixel: u8 = @truncate(vramAt(ppu, tile * 64 + (ypos >> 8 & 7) * 8 + (xpos >> 8 & 7)) >> 8);
                    if (pixel != 0) {
                        var i: i32 = 0;
                        while (i != w) : (i += 1)
                            dstz[@intCast(i)] = @as(PpuZbufType, pixel) +% z;
                    }
                }
                xpos +%= dx *% @as(u32, @bitCast(w));
                ypos +%= dy *% @as(u32, @bitCast(w));
                dstz += @intCast(w);
                w = ppu.mosaicSize;
                if (dstz == dstz_end) break;
            }
        } else {
            while (true) {
                skip: {
                    var tile: u32 = 0;
                    if ((xpos | ypos) > outside_value) {
                        if (!char_fill) break :skip;
                    } else {
                        tile = vramAt(ppu, (ypos >> 11 & 0x7f) * 128 + (xpos >> 11 & 0x7f)) & 0xff;
                    }
                    const pixel: u8 = @truncate(vramAt(ppu, tile * 64 + (ypos >> 8 & 7) * 8 + (xpos >> 8 & 7)) >> 8);
                    if (pixel != 0)
                        dstz[0] = @as(PpuZbufType, pixel) +% z;
                }
                xpos +%= dx;
                ypos +%= dy;
                dstz += 1;
                if (dstz == dstz_end) break;
            }
        }
    }
}

pub export fn PpuSetMode7PerspectiveCorrection(ppu: *Ppu, low: c_int, high: c_int) callconv(.c) void {
    ppu.mode7PerspectiveLow = if (low != 0) 1.0 / @as(f32, @floatFromInt(low)) else 0.0;
    ppu.mode7PerspectiveHigh = 1.0 / @as(f32, @floatFromInt(high));
}

pub export fn PpuSetExtraSideSpace(ppu: *Ppu, left: c_int, right: c_int, bottom: c_int) callconv(.c) void {
    ppu.extraLeftCur = @truncate(uintMin(@bitCast(left), ppu.extraLeftRight));
    ppu.extraRightCur = @truncate(uintMin(@bitCast(right), ppu.extraLeftRight));
    ppu.extraBottomCur = @truncate(uintMin(@bitCast(bottom), 16));
}

fn floatInterpolate(x: f32, xmin: f32, xmax: f32, ymin: f32, ymax: f32) f32 {
    return ymin + (ymax - ymin) * (x - xmin) * (1.0 / (xmax - xmin));
}

fn writePixel32(dst: [*]u8, value: u32) void {
    @as(*align(1) u32, @ptrCast(dst)).* = value;
}

/// Upsampled version of mode7 rendering. Draws everything in 4x the normal
/// resolution. Draws directly to the pixel buffer and bypasses any math, and
/// supports only a subset of the normal features (all that zelda needs)
fn PpuDrawMode7Upsampled(ppu: *Ppu, y: u32) void {
    const xCenter: u32 = @bitCast(expand13(ppu.m7matrix[4]));
    const yCenter: u32 = @bitCast(expand13(ppu.m7matrix[5]));
    const clippedH: u32 = @bitCast(expand13(ppu.m7matrix[6]) - @as(i32, @bitCast(xCenter)));
    const clippedV: u32 = @bitCast(expand13(ppu.m7matrix[7]) - @as(i32, @bitCast(yCenter)));
    var m0v: [4]i32 = undefined;
    if (@as(u32, @bitCast(ppu.mode7PerspectiveLow)) == 0) {
        m0v = @splat(@as(i32, ppu.m7matrix[0]) << 12);
    } else {
        const kInterpolateOffsets = [4]f32{ -1, -1 + 0.25, -1 + 0.5, -1 + 0.75 };
        for (0..4) |i| {
            const at = @as(f32, @floatFromInt(y)) + kInterpolateOffsets[i];
            m0v[i] = @intFromFloat(4096.0 / floatInterpolate(at, 0, 223, ppu.mode7PerspectiveLow, ppu.mode7PerspectiveHigh));
        }
    }
    const pitch = ppu.renderPitch;
    const render_buffer_ptr = ppu.renderBuffer.? + (y - 1) * 4 * pitch;
    const dst_start = render_buffer_ptr + @as(usize, ppu.extraLeftRight - ppu.extraLeftCur) * 16;
    const draw_width: usize = 256 + @as(usize, ppu.extraLeftCur) + @as(usize, ppu.extraRightCur);
    var dst_curline = dst_start;
    const m1: u32 = @bitCast(@as(i32, ppu.m7matrix[1]) << 12); // xpos increment per vert movement
    const m2: u32 = @bitCast(@as(i32, ppu.m7matrix[2]) << 12); // ypos increment per horiz movement
    for (0..4) |j| {
        const m0: u32 = @bitCast(m0v[j]);
        const m3: u32 = m0;
        var xpos: u32 = m0 *% clippedH +% m1 *% (clippedV +% y) +% (xCenter << 20);
        var ypos: u32 = m2 *% clippedH +% m3 *% (clippedV +% y) +% (yCenter << 20);

        xpos -%= (m0 +% m1) >> 1;
        ypos -%= (m2 +% m3) >> 1;
        var xcur: u32 = (xpos << 2) +% @as(u32, @intCast(j)) *% m1;
        var ycur: u32 = (ypos << 2) +% @as(u32, @intCast(j)) *% m3;

        xcur -%= @as(u32, ppu.extraLeftCur) *% 4 *% m0;
        ycur -%= @as(u32, ppu.extraLeftCur) *% 4 *% m2;

        var dst = dst_curline;
        const dst_end = dst_curline + draw_width * 16;

        while (dst != dst_end) {
            inline for (0..4) |_| {
                const tile: u32 = vramAt(ppu, (ycur >> 25 & 0x7f) * 128 + (xcur >> 25 & 0x7f)) & 0xff;
                var pixel: u32 = vramAt(ppu, tile * 64 + (ycur >> 22 & 7) * 8 + (xcur >> 22 & 7)) >> 8;
                pixel = if (xcur & 0x80000000 != 0) 0 else pixel;
                const color = ppu.colorMapRgb[pixel];
                writePixel32(dst, if (ppu.halfColor) (color & 0xfefefe) >> 1 else color);
                xcur +%= m0;
                ycur +%= m2;
                dst += 4;
            }
        }

        dst_curline += pitch;
    }

    if (ppu.lineHasSprites) {
        var dst = dst_start;
        const pixels = ppu.objBuffer.data[kPpuExtraLeftRight - @as(usize, ppu.extraLeftCur) ..];
        for (0..draw_width) |i| {
            const pixel: u32 = pixels[i] & 0xff;
            if (pixel != 0) {
                const color = ppu.colorMapRgb[pixel];
                inline for (0..4) |row| {
                    const line_dst = dst + pitch * row;
                    inline for (0..4) |col|
                        writePixel32(line_dst + col * 4, color);
                }
            }
            dst += 16;
        }
    }

    if (ppu.extraLeftRight - ppu.extraLeftCur != 0) {
        const n = 4 * 4 * @as(usize, ppu.extraLeftRight - ppu.extraLeftCur);
        for (0..4) |i|
            @memset((render_buffer_ptr + pitch * i)[0..n], 0);
    }
    if (ppu.extraLeftRight - ppu.extraRightCur != 0) {
        const n = 4 * 4 * @as(usize, ppu.extraLeftRight - ppu.extraRightCur);
        const off = (256 + @as(usize, ppu.extraLeftRight) * 2 - @as(usize, ppu.extraLeftRight - ppu.extraRightCur)) * 4 * 4;
        for (0..4) |i|
            @memset((render_buffer_ptr + pitch * i + off)[0..n], 0);
    }
}

// Top 4 bits contain the prio level, and bottom 4 bits the layer type.
// spritePrioToPrio can be used to convert from obj prio to this prio.
//  15: BG3 tiles with priority 1 if bit 3 of $2105 is set
//  14: Sprites with priority 3 (4 * sprite_prio + 2)
//  12: BG1 tiles with priority 1
//  11: BG2 tiles with priority 1
//  10: Sprites with priority 2 (4 * sprite_prio + 2)
//  8: BG1 tiles with priority 0
//  7: BG2 tiles with priority 0
//  6: Sprites with priority 1 (4 * sprite_prio + 2)
//  3: BG3 tiles with priority 1 if bit 3 of $2105 is clear
//  2: Sprites with priority 0 (4 * sprite_prio + 2)
//  1: BG3 tiles with priority 0
//  0: backdrop
fn PpuDrawBackgrounds(ppu: *Ppu, y: u32, sub: u1) void {
    if (ppu.mode == 1) {
        if (ppu.lineHasSprites)
            PpuDrawSprites(ppu, y, sub, true);

        if (isMosaicEnabled(ppu, 0))
            drawBackgroundMosaic(ppu, 4, y, sub, 0, 0xc000, 0x8000)
        else
            PpuDrawBackground_4bpp(ppu, y, sub, 0, 0xc000, 0x8000);

        if (isMosaicEnabled(ppu, 1))
            drawBackgroundMosaic(ppu, 4, y, sub, 1, 0xb100, 0x7100)
        else
            PpuDrawBackground_4bpp(ppu, y, sub, 1, 0xb100, 0x7100);

        if (isMosaicEnabled(ppu, 2))
            drawBackgroundMosaic(ppu, 2, y, sub, 2, 0xf200, 0x1200)
        else
            PpuDrawBackground_2bpp(ppu, y, sub, 2, 0xf200, 0x1200);
    } else {
        // mode 7
        PpuDrawBackground_mode7(ppu, y, sub, 0xc000);
        if (ppu.lineHasSprites)
            PpuDrawSprites(ppu, y, sub, false);
    }
}

const kCwBitsMod = [8]u8{
    0x00, 0xff, 0xff, 0x00,
    0xff, 0x00, 0xff, 0x00,
};

fn PpuDrawWholeLine(ppu: *Ppu, y: u32) void {
    const row: usize = y - 1;
    if (ppu.forcedBlank) {
        const n = 4 * (256 + @as(usize, ppu.extraLeftRight) * 2);
        @memset(ppu.renderBuffer.?[row * ppu.renderPitch ..][0..n], 0);
        return;
    }

    if (ppu.mode == 7 and (ppu.renderFlags & kPpuRenderFlags_4x4Mode7) != 0) {
        PpuDrawMode7Upsampled(ppu, y);
        return;
    }

    // Default background is backdrop
    clearBackdrop(&ppu.bgBuffers[0]);

    // Render main screen
    PpuDrawBackgrounds(ppu, y, 0);

    // The 6:th bit is automatically zero, math is never applied to the first half of the sprites.
    const math_enabled: u32 = ppu.mathEnabled;

    // Render also the subscreen?
    var rendered_subscreen = false;
    if (ppu.preventMathMode != 3 and ppu.addSubscreen and math_enabled != 0) {
        clearBackdrop(&ppu.bgBuffers[1]);
        if (ppu.screenEnabled[1] != 0) {
            PpuDrawBackgrounds(ppu, y, 1);
            rendered_subscreen = true;
        }
    }

    // Color window affects the drawing mode in each region
    var cwin: PpuWindows = undefined;
    PpuWindows_Calc(&cwin, ppu, 5);
    var cw_clip_math: u32 = ((cwin.bits & kCwBitsMod[ppu.clipMode]) ^ kCwBitsMod[ppu.clipMode + 4]) |
        @as(u32, (cwin.bits & kCwBitsMod[ppu.preventMathMode]) ^ kCwBitsMod[ppu.preventMathMode + 4]) << 8;

    const dst_org: [*]u8 = ppu.renderBuffer.? + row * ppu.renderPitch;
    var dst: [*]u8 = dst_org + @as(usize, ppu.extraLeftRight - ppu.extraLeftCur) * 4;

    var windex: u32 = 0;
    while (true) {
        const left: usize = bufIndex(cwin.edges[windex]);
        const right: usize = bufIndex(cwin.edges[windex + 1]);
        // If clip is set, then zero out the rgb values from the main screen.
        const clip_color_mask: u32 = if (cw_clip_math & 1 != 0) 0x1f else 0;
        const math_enabled_cur: u32 = if (cw_clip_math & 0x100 != 0) math_enabled else 0;
        const fixed_color: u32 = ppu.fixedColorR | @as(u32, ppu.fixedColorG) << 5 | @as(u32, ppu.fixedColorB) << 10;
        if (math_enabled_cur == 0 or (fixed_color == 0 and !ppu.halfColor and !rendered_subscreen)) {
            // Math is disabled (or has no effect), so can avoid the per-pixel maths check
            for (left..right) |i| {
                const color: u32 = ppu.cgram[ppu.bgBuffers[0].data[i] & 0xff];
                writePixel32(dst, @as(u32, ppu.brightnessMult[color & clip_color_mask]) << 16 |
                    @as(u32, ppu.brightnessMult[(color >> 5) & clip_color_mask]) << 8 |
                    ppu.brightnessMult[(color >> 10) & clip_color_mask]);
                dst += 4;
            }
        } else {
            const half_color_map: []const u8 = if (ppu.halfColor) &ppu.brightnessMultHalf else &ppu.brightnessMult;
            // Store this in locals
            const flags = math_enabled_cur | @as(u32, @intFromBool(ppu.addSubscreen)) << 8 |
                @as(u32, @intFromBool(ppu.subtractColor)) << 9;
            // Need to check for each pixel whether to use math or not based on the main screen layer.
            for (left..right) |i| {
                const color: u32 = ppu.cgram[ppu.bgBuffers[0].data[i] & 0xff];
                const main_layer: u5 = @truncate((ppu.bgBuffers[0].data[i] >> 8) & 0xf);
                var r = color & clip_color_mask;
                var g = (color >> 5) & clip_color_mask;
                var b = (color >> 10) & clip_color_mask;
                var color_map: []const u8 = &ppu.brightnessMult;
                if (flags & (@as(u32, 1) << main_layer) != 0) {
                    var color2: u32 = undefined;
                    if (flags & 0x100 != 0) { // addSubscreen ?
                        if ((ppu.bgBuffers[1].data[i] & 0xff) != 0) {
                            color2 = ppu.cgram[ppu.bgBuffers[1].data[i] & 0xff];
                            color_map = half_color_map;
                        } else { // Don't halve if ppu->addSubscreen && backdrop
                            color2 = fixed_color;
                        }
                    } else {
                        color2 = fixed_color;
                        color_map = half_color_map;
                    }
                    const r2 = color2 & 0x1f;
                    const g2 = (color2 >> 5) & 0x1f;
                    const b2 = (color2 >> 10) & 0x1f;
                    if (flags & 0x200 != 0) { // subtractColor?
                        r = if (r >= r2) r - r2 else 0;
                        g = if (g >= g2) g - g2 else 0;
                        b = if (b >= b2) b - b2 else 0;
                    } else {
                        r += r2;
                        g += g2;
                        b += b2;
                    }
                }
                writePixel32(dst, color_map[b] | @as(u32, color_map[g]) << 8 | @as(u32, color_map[r]) << 16);
                dst += 4;
            }
        }
        cw_clip_math >>= 1;
        windex += 1;
        if (windex >= cwin.nr) break;
    }

    // Clear out stuff on the sides.
    if (ppu.extraLeftRight - ppu.extraLeftCur != 0)
        @memset(dst_org[0 .. 4 * @as(usize, ppu.extraLeftRight - ppu.extraLeftCur)], 0);
    if (ppu.extraLeftRight - ppu.extraRightCur != 0) {
        const off = (256 + @as(usize, ppu.extraLeftRight) * 2 - @as(usize, ppu.extraLeftRight - ppu.extraRightCur)) * 4;
        @memset((dst_org + off)[0 .. 4 * @as(usize, ppu.extraLeftRight - ppu.extraRightCur)], 0);
    }
}

fn ppu_handlePixel(ppu: *Ppu, x: c_int, y: c_int) void {
    var r: i32 = 0;
    var r2: i32 = 0;
    var g: i32 = 0;
    var g2: i32 = 0;
    var b: i32 = 0;
    var b2: i32 = 0;
    if (!ppu.forcedBlank) {
        const mainLayer = ppu_getPixel(ppu, x, y, false, &r, &g, &b);

        const colorWindowState = ppu_getWindowState(ppu, 5, x);
        if (ppu.clipMode == 3 or
            (ppu.clipMode == 2 and colorWindowState) or
            (ppu.clipMode == 1 and !colorWindowState))
        {
            r = 0;
            g = 0;
            b = 0;
        }
        var secondLayer: i32 = 5; // backdrop
        const mathEnabled = mainLayer < 6 and (ppu.mathEnabled & (@as(u32, 1) << @intCast(mainLayer))) != 0 and
            !(ppu.preventMathMode == 3 or
                (ppu.preventMathMode == 2 and colorWindowState) or
                (ppu.preventMathMode == 1 and !colorWindowState));
        if ((mathEnabled and ppu.addSubscreen) or ppu.mode == 5 or ppu.mode == 6) {
            secondLayer = ppu_getPixel(ppu, x, y, true, &r2, &g2, &b2);
        }
        // TODO: subscreen pixels can be clipped to black as well
        // TODO: math for subscreen pixels (add/sub sub to main)
        if (mathEnabled) {
            const use_sub = ppu.addSubscreen and secondLayer != 5;
            if (ppu.subtractColor) {
                r -= if (use_sub) r2 else ppu.fixedColorR;
                g -= if (use_sub) g2 else ppu.fixedColorG;
                b -= if (use_sub) b2 else ppu.fixedColorB;
            } else {
                r += if (use_sub) r2 else ppu.fixedColorR;
                g += if (use_sub) g2 else ppu.fixedColorG;
                b += if (use_sub) b2 else ppu.fixedColorB;
            }
            if (ppu.halfColor and (secondLayer != 5 or !ppu.addSubscreen)) {
                r >>= 1;
                g >>= 1;
                b >>= 1;
            }
            r = intMin(intMax(r, 0), 31);
            g = intMin(intMax(g, 0), 31);
            b = intMin(intMax(b, 0), 31);
        }
        if (!(ppu.mode == 5 or ppu.mode == 6)) {
            r2 = r;
            g2 = g;
            b2 = b;
        }
    }
    const row: usize = @intCast(y - 1);
    const col: usize = @intCast(x + @as(c_int, ppu.extraLeftRight));
    const pixelBuffer = ppu.renderBuffer.? + row * ppu.renderPitch + col * 4;
    const brightness: i32 = ppu.brightness;
    pixelBuffer[0] = @intCast(@divTrunc(((b << 3) | (b >> 2)) * brightness, 15));
    pixelBuffer[1] = @intCast(@divTrunc(((g << 3) | (g >> 2)) * brightness, 15));
    pixelBuffer[2] = @intCast(@divTrunc(((r << 3) | (r >> 2)) * brightness, 15));
    pixelBuffer[3] = 0;
}

const bitDepthsPerMode = [10][4]u8{
    .{ 2, 2, 2, 2 },
    .{ 4, 4, 2, 5 },
    .{ 4, 4, 5, 5 },
    .{ 8, 4, 5, 5 },
    .{ 8, 2, 5, 5 },
    .{ 4, 2, 5, 5 },
    .{ 4, 5, 5, 5 },
    .{ 8, 5, 5, 5 },
    .{ 4, 4, 2, 5 },
    .{ 8, 7, 5, 5 },
};

// array for layer definitions per mode:
//   0-7: mode 0-7; 8: mode 1 + l3prio; 9: mode 7 + extbg
//   0-3; layers 1-4; 4: sprites; 5: nonexistent
const layersPerMode = [10][12]u8{
    .{ 4, 0, 1, 4, 0, 1, 4, 2, 3, 4, 2, 3 },
    .{ 4, 0, 1, 4, 0, 1, 4, 2, 4, 2, 5, 5 },
    .{ 4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5 },
    .{ 4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5 },
    .{ 4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5 },
    .{ 4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5 },
    .{ 4, 0, 4, 4, 0, 4, 5, 5, 5, 5, 5, 5 },
    .{ 4, 4, 4, 0, 4, 5, 5, 5, 5, 5, 5, 5 },
    .{ 2, 4, 0, 1, 4, 0, 1, 4, 4, 2, 5, 5 },
    .{ 4, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5, 5 },
};

const prioritysPerMode = [10][12]u8{
    .{ 3, 1, 1, 2, 0, 0, 1, 1, 1, 0, 0, 0 },
    .{ 3, 1, 1, 2, 0, 0, 1, 1, 0, 0, 5, 5 },
    .{ 3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5 },
    .{ 3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5 },
    .{ 3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5 },
    .{ 3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5 },
    .{ 3, 1, 2, 1, 0, 0, 5, 5, 5, 5, 5, 5 },
    .{ 3, 2, 1, 0, 0, 5, 5, 5, 5, 5, 5, 5 },
    .{ 1, 3, 1, 1, 2, 0, 0, 1, 0, 0, 5, 5 },
    .{ 3, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5, 5 },
};

const layerCountPerMode = [10]u8{ 12, 10, 8, 8, 8, 8, 6, 5, 10, 7 };

/// figure out which color is on this location on main- or subscreen, sets it
/// in r, g, b. Returns which layer it is: 0-3 for bg layer, 4 or 6 for sprites
/// (depending on palette), 5 for backdrop
fn ppu_getPixel(ppu: *Ppu, x: c_int, y: c_int, sub: bool, r: *i32, g: *i32, b: *i32) i32 {
    var actMode: u32 = if (ppu.mode == 1) 8 else ppu.mode;
    actMode = if (ppu.mode == 7 and ppu.m7extBg_always_zero) 9 else actMode;
    var layer: i32 = 5;
    var pixel: i32 = 0;
    const screen: u1 = if (sub) 1 else 0;
    for (0..layerCountPerMode[actMode]) |i| {
        const curLayer: u32 = layersPerMode[actMode][i];
        const curPriority: u32 = prioritysPerMode[actMode][i];
        const layerActive = isScreenEnabled(ppu, screen, curLayer) and
            (!isScreenWindowed(ppu, screen, curLayer) or !ppu_getWindowState(ppu, @intCast(curLayer), x));
        if (layerActive) {
            if (curLayer < 4) {
                // bg layer
                var lx = x;
                var ly = y;
                if (isMosaicEnabled(ppu, curLayer)) {
                    lx -= @rem(lx, ppu.mosaicSize);
                    ly -= @rem(ly - 1, ppu.mosaicSize);
                }
                if (ppu.mode == 7) {
                    pixel = ppu_getPixelForMode7(ppu, lx, @intCast(curLayer), curPriority != 0);
                } else {
                    lx += ppu.bgLayer[curLayer].hScroll;
                    ly += ppu.bgLayer[curLayer].vScroll;
                    pixel = ppu_getPixelForBgLayer(ppu, lx & 0x3ff, ly & 0x3ff, @intCast(curLayer), curPriority != 0);
                }
            } else {
                // get a pixel from the sprite buffer
                pixel = 0;
                const at: usize = @intCast(x + kPpuExtraLeftRight);
                if ((ppu.objBuffer.data[at] >> 12) == spritePrioToPrioHi(curPriority))
                    pixel = ppu.objBuffer.data[at] & 0xff;
            }
        }
        if (pixel > 0) {
            layer = @intCast(curLayer);
            break;
        }
    }
    const color: u16 = ppu.cgram[@as(usize, @intCast(pixel)) & 0xff];
    r.* = color & 0x1f;
    g.* = (color >> 5) & 0x1f;
    b.* = (color >> 10) & 0x1f;
    if (layer == 4 and pixel < 0xc0) layer = 6; // sprites with palette color < 0xc0
    return layer;
}

fn ppu_getPixelForBgLayer(ppu: *Ppu, x: c_int, y: c_int, layer: u32, priority: bool) i32 {
    const layerp = &ppu.bgLayer[layer];
    // figure out address of tilemap word and read it
    const wideTiles = ppu.mode == 5 or ppu.mode == 6;
    const tileBitsX: u5 = if (wideTiles) 4 else 3;
    const tileHighBitX: c_int = if (wideTiles) 0x200 else 0x100;
    const tileBitsY: u5 = 3;
    const tileHighBitY: c_int = 0x100;
    var tilemapAdr: u16 = layerp.tilemapAdr +%
        @as(u16, @intCast((((y >> tileBitsY) & 0x1f) << 5) | ((x >> tileBitsX) & 0x1f)));
    if ((x & tileHighBitX) != 0 and layerp.tilemapWider) tilemapAdr +%= 0x400;
    if ((y & tileHighBitY) != 0 and layerp.tilemapHigher)
        tilemapAdr +%= if (layerp.tilemapWider) 0x800 else 0x400;
    const tile = ppu.vram[tilemapAdr & 0x7fff];
    // check priority, get palette
    if (((tile & 0x2000) != 0) != priority) return 0; // wrong priority
    var paletteNum: i32 = (tile & 0x1c00) >> 10;
    // figure out position within tile
    // row indexes into vram, col shifts a 16-bit plane, so it has to be a u4.
    const row: u32 = if (tile & 0x8000 != 0) @intCast(7 - (y & 0x7)) else @intCast(y & 0x7);
    const col: u4 = if (tile & 0x4000 != 0) @intCast(x & 0x7) else @intCast(7 - (x & 0x7));
    var tileNum: u32 = tile & 0x3ff;
    if (wideTiles) {
        // if unflipped right half of tile, or flipped left half of tile
        if (((x & 8) != 0) != ((tile & 0x4000) != 0)) tileNum += 1;
    }
    // read tiledata, ajust palette for mode 0
    const bitDepth: u32 = bitDepthsPerMode[ppu.mode][layer];
    if (ppu.mode == 0) paletteNum += @intCast(8 * layer);
    // plane 1 (always)
    var paletteSize: i32 = 4;
    const tile_base: u32 = @as(u32, layerp.tileAdr) +% ((tileNum & 0x3ff) *% 4 *% bitDepth) +% row;
    const plane1 = ppu.vram[tile_base & 0x7fff];
    var pixel: i32 = (plane1 >> col) & 1;
    pixel |= @as(i32, (plane1 >> (8 + col)) & 1) << 1;
    // plane 2 (for 4bpp, 8bpp)
    if (bitDepth > 2) {
        paletteSize = 16;
        const plane2 = ppu.vram[(tile_base +% 8) & 0x7fff];
        pixel |= @as(i32, (plane2 >> col) & 1) << 2;
        pixel |= @as(i32, (plane2 >> (8 + col)) & 1) << 3;
    }
    // plane 3 & 4 (for 8bpp)
    if (bitDepth > 4) {
        paletteSize = 256;
        const plane3 = ppu.vram[(tile_base +% 16) & 0x7fff];
        pixel |= @as(i32, (plane3 >> col) & 1) << 4;
        pixel |= @as(i32, (plane3 >> (8 + col)) & 1) << 5;
        const plane4 = ppu.vram[(tile_base +% 24) & 0x7fff];
        pixel |= @as(i32, (plane4 >> col) & 1) << 6;
        pixel |= @as(i32, (plane4 >> (8 + col)) & 1) << 7;
    }
    // return cgram index, or 0 if transparent, palette number in bits 10-8 for 8-color layers
    return if (pixel == 0) 0 else paletteSize * paletteNum + pixel;
}

fn ppu_calculateMode7Starts(ppu: *Ppu, y_in: c_int) void {
    const hScroll = expand13(ppu.m7matrix[6]);
    const vScroll = expand13(ppu.m7matrix[7]);
    const xCenter = expand13(ppu.m7matrix[4]);
    const yCenter = expand13(ppu.m7matrix[5]);
    // do calculation
    var clippedH = hScroll - xCenter;
    var clippedV = vScroll - yCenter;
    clippedH = if (clippedH & 0x2000 != 0) (clippedH | ~@as(i32, 1023)) else (clippedH & 1023);
    clippedV = if (clippedV & 0x2000 != 0) (clippedV | ~@as(i32, 1023)) else (clippedV & 1023);
    var y = y_in;
    if (isMosaicEnabled(ppu, 0)) {
        y -= @rem(y - 1, ppu.mosaicSize);
    }
    const ry: i32 = if (ppu.m7yFlip) 255 - @as(u8, @truncate(@as(u32, @bitCast(y)))) else @as(u8, @truncate(@as(u32, @bitCast(y))));
    ppu.m7startX = (@as(i32, ppu.m7matrix[0]) * clippedH & ~@as(i32, 63)) +
        (@as(i32, ppu.m7matrix[1]) * ry & ~@as(i32, 63)) +
        (@as(i32, ppu.m7matrix[1]) * clippedV & ~@as(i32, 63)) +
        (xCenter << 8);
    ppu.m7startY = (@as(i32, ppu.m7matrix[2]) * clippedH & ~@as(i32, 63)) +
        (@as(i32, ppu.m7matrix[3]) * ry & ~@as(i32, 63)) +
        (@as(i32, ppu.m7matrix[3]) * clippedV & ~@as(i32, 63)) +
        (yCenter << 8);
}

fn ppu_getPixelForMode7(ppu: *Ppu, x_in: c_int, layer: u32, priority: bool) i32 {
    var x = x_in;
    if (isMosaicEnabled(ppu, layer))
        x -= @rem(x, ppu.mosaicSize);
    const rx: i32 = if (ppu.m7xFlip) 255 - @as(u8, @truncate(@as(u32, @bitCast(x)))) else @as(u8, @truncate(@as(u32, @bitCast(x))));
    var xPos = (ppu.m7startX + @as(i32, ppu.m7matrix[0]) * rx) >> 8;
    var yPos = (ppu.m7startY + @as(i32, ppu.m7matrix[2]) * rx) >> 8;
    var outsideMap = xPos < 0 or xPos >= 1024 or yPos < 0 or yPos >= 1024;
    xPos &= 0x3ff;
    yPos &= 0x3ff;
    if (!ppu.m7largeField) outsideMap = false;
    const tile: u32 = if (outsideMap) 0 else vramAt(ppu, @intCast((yPos >> 3) * 128 + (xPos >> 3))) & 0xff;
    const pixel: u8 = if (outsideMap and !ppu.m7charFill)
        0
    else
        @truncate(vramAt(ppu, @intCast(@as(i32, @intCast(tile)) * 64 + (yPos & 7) * 8 + (xPos & 7))) >> 8);
    if (layer == 1) {
        if (((pixel & 0x80) != 0) != priority) return 0;
        return pixel & 0x7f;
    }
    return pixel;
}

fn ppu_getWindowState(ppu: *Ppu, layer: c_int, x: c_int) bool {
    const winflags = getWindowFlags(ppu, @intCast(layer));
    if ((winflags & kWindow1Enabled) == 0 and (winflags & kWindow2Enabled) == 0) {
        return false;
    }
    if ((winflags & kWindow1Enabled) != 0 and (winflags & kWindow2Enabled) == 0) {
        const t = x >= ppu.window1left and x <= ppu.window1right;
        return if (winflags & kWindow1Inversed != 0) !t else t;
    }
    if ((winflags & kWindow1Enabled) == 0 and (winflags & kWindow2Enabled) != 0) {
        const t = x >= ppu.window2left and x <= ppu.window2right;
        return if (winflags & kWindow2Inversed != 0) !t else t;
    }
    var test1 = x >= ppu.window1left and x <= ppu.window1right;
    var test2 = x >= ppu.window2left and x <= ppu.window2right;
    if (winflags & kWindow1Inversed != 0) test1 = !test1;
    if (winflags & kWindow2Inversed != 0) test2 = !test2;
    return test1 or test2;
}

// TODO: iterate over oam normally to determine in-range sprites,
//   then iterate those in-range sprites in reverse for tile-fetching
// TODO: rectangular sprites, wierdness with sprites at -256
fn ppu_evaluateSprites(ppu: *Ppu, line: c_int) bool {
    var index: u32 = 0;
    const index_end: u32 = 0;
    var spritesLeft: i32 = 32 + 1;
    var tilesLeft: i32 = 34 + 1;
    const spriteSizes = [2]u8{ kSpriteSizes[ppu.objSize][0], kSpriteSizes[ppu.objSize][1] };
    const extra_left_right: i32 = ppu.extraLeftRight;
    if (ppu.renderFlags & kPpuRenderFlags_NoSpriteLimits != 0) {
        spritesLeft = 1024;
        tilesLeft = 1024;
    }
    const tilesLeftOrg = tilesLeft;

    while (true) {
        sprite: {
            const yy: i32 = ppu.oam[index] >> 8;
            if (yy == 0xf0)
                break :sprite; // this works for zelda because sprites are always 8 or 16.
            // check if the sprite is on this line and get the sprite size
            var row: i32 = (line - yy) & 0xff;
            const highOam: u32 = ppu.oam[0x100 + (index >> 4)] >> @intCast(index & 15);
            const spriteSize: i32 = spriteSizes[(highOam >> 1) & 1];
            if (row >= spriteSize)
                break :sprite;
            // in y-range, get the x location, using the high bit as well
            var x: i32 = @as(i32, ppu.oam[index] & 0xff) + @as(i32, @intCast(highOam & 1)) * 256;
            x -= @intFromBool(x >= 256 + extra_left_right) * @as(i32, 512);
            // if in x-range
            if (x <= -(spriteSize + extra_left_right))
                break :sprite;
            // break if we found 32 sprites already
            spritesLeft -= 1;
            if (spritesLeft == 0) {
                return tilesLeft != tilesLeftOrg;
            }
            // get some data for the sprite and y-flip row if needed
            const oam1: u32 = ppu.oam[index + 1];
            const objAdr: u32 = if (oam1 & 0x100 != 0) ppu.objTileAdr2 else ppu.objTileAdr1;
            if (oam1 & 0x8000 != 0)
                row = spriteSize - 1 - row;
            // fetch all tiles in x-range
            const paletteBase: u32 = 0x80 + 16 * ((oam1 & 0xe00) >> 9);
            const prio = spritePrioToPrio((oam1 & 0x3000) >> 12, (oam1 & 0x800) == 0);
            const z: PpuZbufType = @truncate(paletteBase + (prio << 8));

            var col: i32 = 0;
            while (col < spriteSize) : (col += 8) {
                if (col + x > -8 - extra_left_right and col + x < 256 + extra_left_right) {
                    // break if we found 34 8*1 slivers already
                    tilesLeft -= 1;
                    if (tilesLeft == 0) {
                        return true;
                    }
                    // figure out which tile this uses, looping within 16x16 pages, and get it's data
                    const usedCol: i32 = if (oam1 & 0x4000 != 0) spriteSize - 1 - col else col;
                    const usedTile: u32 = ((((oam1 & 0xff) >> 4) +% @as(u32, @bitCast(row >> 3))) << 4) |
                        (((oam1 & 0xf) +% @as(u32, @bitCast(usedCol >> 3))) & 0xf);
                    const base: u32 = objAdr +% usedTile *% 16 +% @as(u32, @bitCast(row & 0x7));
                    const plane: u32 = vramAt(ppu, base) | @as(u32, vramAt(ppu, base +% 8)) << 16;
                    // go over each pixel
                    const px_left = intMax(-(col + x + kPpuExtraLeftRight), 0);
                    const px_right = intMin(256 + kPpuExtraLeftRight - (col + x), 8);
                    var dst: [*]PpuZbufType = ppu.objBuffer.data[@intCast(col + x + px_left + kPpuExtraLeftRight)..].ptr;

                    var px = px_left;
                    while (px < px_right) : ({
                        px += 1;
                        dst += 1;
                    }) {
                        const shift: u5 = if (oam1 & 0x4000 != 0) @intCast(px) else @intCast(7 - px);
                        const bits = plane >> shift;
                        const pixel: u32 = ((bits >> 0) & 1) | ((bits >> 7) & 2) | ((bits >> 14) & 4) | ((bits >> 21) & 8);
                        // draw it in the buffer if there is a pixel here, and the buffer there is still empty
                        if (pixel != 0 and (dst[0] & 0xff) == 0)
                            dst[0] = z +% @as(PpuZbufType, @truncate(pixel));
                    }
                }
            }
        }
        index = (index + 2) & 0xff;
        if (index == index_end) break;
    }
    return tilesLeft != tilesLeftOrg;
}

pub export fn ppu_read(ppu: *Ppu, adr: u8) callconv(.c) u8 {
    switch (adr) {
        0x34, 0x35, 0x36 => {
            const result: i32 = @as(i32, ppu.m7matrix[0]) * (@as(i32, ppu.m7matrix[1]) >> 8);
            const shift: u5 = @intCast(8 * (adr - 0x34));
            return @truncate(@as(u32, @bitCast(result >> shift)) & 0xff);
        },
        else => return 0xff,
    }
}

pub export fn ppu_write(ppu: *Ppu, adr: u8, val: u8) callconv(.c) void {
    switch (adr) {
        0x00 => { // INIDISP
            ppu.brightness = val & 0xf;
            ppu.forcedBlank = val & 0x80 != 0;
        },
        0x01 => std.debug.assert(val == 2),
        0x02 => {
            ppu.oamAdr = (ppu.oamAdr & ~@as(u16, 0xff)) | val;
            ppu.oamSecondWrite = false;
        },
        0x03 => {
            std.debug.assert((val & 0x80) == 0);
            ppu.oamAdr = (ppu.oamAdr & ~@as(u16, 0xff00)) | (@as(u16, val & 1) << 8);
            ppu.oamSecondWrite = false;
        },
        0x04 => {
            if (!ppu.oamSecondWrite) {
                ppu.oamBuffer = val;
            } else {
                if (ppu.oamAdr < 0x110) {
                    ppu.oam[ppu.oamAdr] = (@as(u16, val) << 8) | ppu.oamBuffer;
                    ppu.oamAdr +%= 1;
                }
            }
            ppu.oamSecondWrite = !ppu.oamSecondWrite;
        },
        0x05 => { // BGMODE
            ppu.mode = val & 0x7;
            std.debug.assert(val == 7 or val == 9);
            std.debug.assert(ppu.mode == 1 or ppu.mode == 7);
            std.debug.assert((val & 0xf0) == 0);
        },
        0x06 => { // MOSAIC
            ppu.mosaicSize = (val >> 4) + 1;
            ppu.mosaicEnabled = if (ppu.mosaicSize > 1) val else 0;
        },
        // BG1SC..BG4SC; small tilemaps are used in attract intro
        0x07, 0x08, 0x09, 0x0a => {
            const bg = &ppu.bgLayer[adr - 7];
            bg.tilemapWider = val & 0x1 != 0;
            bg.tilemapHigher = val & 0x2 != 0;
            bg.tilemapAdr = @as(u16, val & 0xfc) << 8;
        },
        0x0b => { // BG12NBA
            ppu.bgLayer[0].tileAdr = @as(u16, val & 0xf) << 12;
            ppu.bgLayer[1].tileAdr = @as(u16, val & 0xf0) << 8;
        },
        0x0c => { // BG34NBA
            ppu.bgLayer[2].tileAdr = @as(u16, val & 0xf) << 12;
            ppu.bgLayer[3].tileAdr = @as(u16, val & 0xf0) << 8;
        },
        // BG1HOFS, then the plain BG-HOFS registers it falls through to
        0x0d, 0x0f, 0x11, 0x13 => {
            if (adr == 0x0d) {
                ppu.m7matrix[6] = @bitCast(@as(u16, (@as(u16, val) << 8) | ppu.m7prev) & 0x1fff);
                ppu.m7prev = val;
            }
            ppu.bgLayer[(adr - 0xd) / 2].hScroll =
                ((@as(u16, val) << 8) | (ppu.scrollPrev & 0xf8) | (ppu.scrollPrev2 & 0x7)) & 0x3ff;
            ppu.scrollPrev = val;
            ppu.scrollPrev2 = val;
        },
        // BG1VOFS, then the plain BG-VOFS registers it falls through to
        0x0e, 0x10, 0x12, 0x14 => {
            if (adr == 0x0e) {
                ppu.m7matrix[7] = @bitCast(@as(u16, (@as(u16, val) << 8) | ppu.m7prev) & 0x1fff);
                ppu.m7prev = val;
            }
            ppu.bgLayer[(adr - 0xe) / 2].vScroll = ((@as(u16, val) << 8) | ppu.scrollPrev) & 0x3ff;
            ppu.scrollPrev = val;
        },
        0x15 => { // VMAIN
            if ((val & 3) == 0) {
                ppu.vramIncrement = 1;
            } else if ((val & 3) == 1) {
                ppu.vramIncrement = 32;
            } else {
                ppu.vramIncrement = 128;
            }
            std.debug.assert(((val & 0xc) >> 2) == 0);
            ppu.vramIncrementOnHigh = val & 0x80 != 0;
        },
        0x16 => ppu.vramPointer = (ppu.vramPointer & 0xff00) | val, // VMADDL
        0x17 => ppu.vramPointer = (ppu.vramPointer & 0x00ff) | (@as(u16, val) << 8), // VMADDH
        0x18 => { // VMDATAL
            const vramAdr = ppu.vramPointer;
            ppu.vram[vramAdr & 0x7fff] = (ppu.vram[vramAdr & 0x7fff] & 0xff00) | val;
            if (!ppu.vramIncrementOnHigh) ppu.vramPointer +%= ppu.vramIncrement;
        },
        0x19 => { // VMDATAH
            const vramAdr = ppu.vramPointer;
            ppu.vram[vramAdr & 0x7fff] = (ppu.vram[vramAdr & 0x7fff] & 0x00ff) | (@as(u16, val) << 8);
            if (ppu.vramIncrementOnHigh) ppu.vramPointer +%= ppu.vramIncrement;
        },
        0x1a => { // M7SEL
            std.debug.assert(val == 0x80);
            ppu.m7largeField = val & 0x80 != 0;
            ppu.m7charFill = val & 0x40 != 0;
            ppu.m7yFlip = val & 0x2 != 0;
            ppu.m7xFlip = val & 0x1 != 0;
        },
        0x1b, 0x1c, 0x1d, 0x1e => { // M7A etc
            ppu.m7matrix[adr - 0x1b] = @bitCast((@as(u16, val) << 8) | ppu.m7prev);
            ppu.m7prev = val;
        },
        0x1f, 0x20 => {
            ppu.m7matrix[adr - 0x1b] = @bitCast(((@as(u16, val) << 8) | ppu.m7prev) & 0x1fff);
            ppu.m7prev = val;
        },
        0x21 => {
            ppu.cgramPointer = val;
            ppu.cgramSecondWrite = false;
        },
        0x22 => {
            if (!ppu.cgramSecondWrite) {
                ppu.cgramBuffer = val;
            } else {
                ppu.cgram[ppu.cgramPointer] = (@as(u16, val) << 8) | ppu.cgramBuffer;
                ppu.cgramPointer +%= 1;
            }
            ppu.cgramSecondWrite = !ppu.cgramSecondWrite;
        },
        0x23 => ppu.windowsel = (ppu.windowsel & ~@as(u32, 0xff)) | val, // W12SEL
        0x24 => ppu.windowsel = (ppu.windowsel & ~@as(u32, 0xff00)) | (@as(u32, val) << 8), // W34SEL
        0x25 => ppu.windowsel = (ppu.windowsel & ~@as(u32, 0xff0000)) | (@as(u32, val) << 16), // WOBJSEL
        0x26 => ppu.window1left = val,
        0x27 => ppu.window1right = val,
        0x28 => ppu.window2left = val,
        0x29 => ppu.window2right = val,
        0x2a => std.debug.assert(val == 0), // WBGLOG
        0x2b => std.debug.assert(val == 0), // WOBJLOG
        0x2c => ppu.screenEnabled[0] = val, // TM
        0x2d => ppu.screenEnabled[1] = val, // TS
        0x2e => ppu.screenWindowed[0] = val, // TMW
        0x2f => ppu.screenWindowed[1] = val, // TSW
        0x30 => { // CGWSEL
            std.debug.assert((val & 1) == 0); // directColor always zero
            ppu.addSubscreen = val & 0x2 != 0;
            ppu.preventMathMode = (val & 0x30) >> 4;
            ppu.clipMode = (val & 0xc0) >> 6;
        },
        0x31 => { // CGADSUB
            ppu.subtractColor = val & 0x80 != 0;
            ppu.halfColor = val & 0x40 != 0;
            ppu.mathEnabled = val & 0x3f;
        },
        0x32 => { // COLDATA
            if (val & 0x80 != 0) ppu.fixedColorB = val & 0x1f;
            if (val & 0x40 != 0) ppu.fixedColorG = val & 0x1f;
            if (val & 0x20 != 0) ppu.fixedColorR = val & 0x1f;
        },
        0x33 => {
            std.debug.assert(val == 0);
            ppu.m7extBg_always_zero = val & 0x40 != 0;
        },
        else => {},
    }
}

const testing = std.testing;

fn testPpu() !*Ppu {
    const ppu = try testing.allocator.create(Ppu);
    ppu.* = std.mem.zeroes(Ppu);
    ppu.extraLeftRight = kPpuExtraLeftRight;
    ppu_reset(ppu);
    return ppu;
}

test "ppu_reset puts the chip in forced blank with the object tables set" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    try testing.expect(ppu.forcedBlank);
    try testing.expectEqual(@as(u16, 0x4000), ppu.objTileAdr1);
    try testing.expectEqual(@as(u16, 0x5000), ppu.objTileAdr2);
    try testing.expectEqual(@as(u8, 1), ppu.mosaicSize);
    try testing.expect(ppu.m7largeField);
}

test "vram writes honour the increment mode" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);

    ppu_write(ppu, 0x15, 0x00); // VMAIN: increment by 1 on low write
    ppu_write(ppu, 0x16, 0x10); // VMADDL
    ppu_write(ppu, 0x17, 0x00); // VMADDH
    ppu_write(ppu, 0x18, 0x34); // VMDATAL
    try testing.expectEqual(@as(u16, 0x0034), ppu.vram[0x10]);
    try testing.expectEqual(@as(u16, 0x11), ppu.vramPointer);

    // With increment on high, the low write does not advance.
    ppu_write(ppu, 0x15, 0x80);
    ppu_write(ppu, 0x16, 0x20);
    ppu_write(ppu, 0x18, 0x78);
    try testing.expectEqual(@as(u16, 0x20), ppu.vramPointer);
    ppu_write(ppu, 0x19, 0x56);
    try testing.expectEqual(@as(u16, 0x5678), ppu.vram[0x20]);
    try testing.expectEqual(@as(u16, 0x21), ppu.vramPointer);
}

test "cgram takes two writes per colour" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    ppu_write(ppu, 0x21, 0x05); // CGADD
    ppu_write(ppu, 0x22, 0xff); // low byte, buffered
    try testing.expectEqual(@as(u16, 0), ppu.cgram[5]);
    ppu_write(ppu, 0x22, 0x7f); // high byte commits
    try testing.expectEqual(@as(u16, 0x7fff), ppu.cgram[5]);
    try testing.expectEqual(@as(u8, 6), ppu.cgramPointer);
}

test "oam takes two writes per entry and stops at $110" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    ppu_write(ppu, 0x02, 0x00);
    ppu_write(ppu, 0x03, 0x00);
    ppu_write(ppu, 0x04, 0x34);
    ppu_write(ppu, 0x04, 0x12);
    try testing.expectEqual(@as(u16, 0x1234), ppu.oam[0]);
    try testing.expectEqual(@as(u16, 1), ppu.oamAdr);

    ppu.oamAdr = 0x110; // past the end: writes are dropped
    ppu_write(ppu, 0x04, 0xaa);
    ppu_write(ppu, 0x04, 0xbb);
    try testing.expectEqual(@as(u16, 0x110), ppu.oamAdr);
}

test "background registers unpack into the layer state" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);

    ppu_write(ppu, 0x07, 0xfc | 0x3); // BG1SC: address plus both size bits
    try testing.expect(ppu.bgLayer[0].tilemapWider);
    try testing.expect(ppu.bgLayer[0].tilemapHigher);
    try testing.expectEqual(@as(u16, 0xfc00), ppu.bgLayer[0].tilemapAdr);

    ppu_write(ppu, 0x0b, 0x21); // BG12NBA
    try testing.expectEqual(@as(u16, 0x1000), ppu.bgLayer[0].tileAdr);
    try testing.expectEqual(@as(u16, 0x2000), ppu.bgLayer[1].tileAdr);
}

test "scroll registers latch the previous write" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    // BG2HOFS is 10 bits, built from the new byte and the two latches.
    ppu_write(ppu, 0x0f, 0x12);
    ppu_write(ppu, 0x0f, 0x03);
    try testing.expectEqual(@as(u16, (0x0300 | 0x12) & 0x3ff), ppu.bgLayer[1].hScroll);

    ppu_write(ppu, 0x10, 0x34); // BG2VOFS
    ppu_write(ppu, 0x10, 0x01);
    try testing.expectEqual(@as(u16, (0x0100 | 0x34) & 0x3ff), ppu.bgLayer[1].vScroll);
}

test "mosaic size and the layer mask" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    ppu_write(ppu, 0x06, 0x30 | 0x3); // size 4, layers 0 and 1
    try testing.expectEqual(@as(u8, 4), ppu.mosaicSize);
    try testing.expect(isMosaicEnabled(ppu, 0));
    try testing.expect(isMosaicEnabled(ppu, 1));
    try testing.expect(!isMosaicEnabled(ppu, 2));
    // A size of 1 disables mosaic entirely, whatever the layer bits say.
    ppu_write(ppu, 0x06, 0x0f);
    try testing.expectEqual(@as(u8, 1), ppu.mosaicSize);
    try testing.expectEqual(@as(u8, 0), ppu.mosaicEnabled);
}

test "window position and selection registers" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    ppu_write(ppu, 0x26, 10); // W1 left
    ppu_write(ppu, 0x27, 20); // W1 right
    try testing.expectEqual(@as(u8, 10), ppu.window1left);
    try testing.expectEqual(@as(u8, 20), ppu.window1right);

    ppu_write(ppu, 0x23, 0x12);
    ppu_write(ppu, 0x24, 0x34);
    ppu_write(ppu, 0x25, 0x56);
    try testing.expectEqual(@as(u32, 0x563412), ppu.windowsel);
}

test "window state follows the enable and invert bits" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    ppu.window1left = 10;
    ppu.window1right = 20;

    ppu.windowsel = 0; // no windows for layer 0
    try testing.expect(!ppu_getWindowState(ppu, 0, 15));

    ppu.windowsel = kWindow1Enabled;
    try testing.expect(ppu_getWindowState(ppu, 0, 15));
    try testing.expect(!ppu_getWindowState(ppu, 0, 25));

    ppu.windowsel = kWindow1Enabled | kWindow1Inversed;
    try testing.expect(!ppu_getWindowState(ppu, 0, 15));
    try testing.expect(ppu_getWindowState(ppu, 0, 25));
}

test "an unwindowed span covers the whole line plus the extra columns" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    ppu.extraLeftCur = 16;
    ppu.extraRightCur = 8;
    var win: PpuWindows = undefined;
    PpuWindows_Clear(&win, ppu, 0);
    try testing.expectEqual(@as(u32, 1), win.nr);
    try testing.expectEqual(@as(i16, -16), win.edges[0]);
    try testing.expectEqual(@as(i16, 264), win.edges[1]);
    try testing.expectEqual(@as(u8, 0), win.bits);

    // Layer 2 never gets the extra space.
    PpuWindows_Clear(&win, ppu, 2);
    try testing.expectEqual(@as(i16, 0), win.edges[0]);
    try testing.expectEqual(@as(i16, 256), win.edges[1]);
}

test "one window splits the line into spans" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    ppu.window1left = 64;
    ppu.window1right = 127;
    ppu.windowsel = kWindow1Enabled;

    var win: PpuWindows = undefined;
    PpuWindows_Calc(&win, ppu, 0);
    try testing.expectEqual(@as(u32, 3), win.nr);
    try testing.expectEqual(@as(i16, 0), win.edges[0]);
    try testing.expectEqual(@as(i16, 64), win.edges[1]);
    try testing.expectEqual(@as(i16, 128), win.edges[2]);
    try testing.expectEqual(@as(i16, 256), win.edges[3]);
    // The middle span is the one inside the window.
    try testing.expectEqual(@as(u8, 0b010), win.bits);
}

test "brightness tables are built once per brightness level" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    var buffer: [16]u8 = undefined;

    ppu.brightness = 15;
    PpuBeginDrawing(ppu, &buffer, 4, 0);
    try testing.expectEqual(@as(u8, 0), ppu.brightnessMult[0]);
    try testing.expectEqual(@as(u8, 255), ppu.brightnessMult[31]);
    // The 31 spare entries past the end all clamp to the last value.
    try testing.expectEqual(@as(u8, 255), ppu.brightnessMult[62]);
    // Half brightness is the same table, doubled up.
    try testing.expectEqual(ppu.brightnessMult[5], ppu.brightnessMultHalf[10]);
    try testing.expectEqual(ppu.brightnessMult[5], ppu.brightnessMultHalf[11]);

    ppu.brightness = 0;
    PpuBeginDrawing(ppu, &buffer, 4, 0);
    try testing.expectEqual(@as(u8, 0), ppu.brightnessMult[31]);
}

test "the render scale is 4x only for upsampled mode 7" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    const both = kPpuRenderFlags_4x4Mode7 | kPpuRenderFlags_NewRenderer;

    ppu.mode = 7;
    ppu.forcedBlank = false;
    try testing.expectEqual(@as(c_int, 4), PpuGetCurrentRenderScale(ppu, both));
    try testing.expectEqual(@as(c_int, 1), PpuGetCurrentRenderScale(ppu, kPpuRenderFlags_NewRenderer));
    ppu.forcedBlank = true;
    try testing.expectEqual(@as(c_int, 1), PpuGetCurrentRenderScale(ppu, both));
    ppu.forcedBlank = false;
    ppu.mode = 1;
    try testing.expectEqual(@as(c_int, 1), PpuGetCurrentRenderScale(ppu, both));
}

test "the extra side space is clamped to what the build allows" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    PpuSetExtraSideSpace(ppu, 1000, 1000, 1000);
    try testing.expectEqual(@as(u8, kPpuExtraLeftRight), ppu.extraLeftCur);
    try testing.expectEqual(@as(u8, kPpuExtraLeftRight), ppu.extraRightCur);
    try testing.expectEqual(@as(u8, 16), ppu.extraBottomCur);
    PpuSetExtraSideSpace(ppu, 8, 4, 2);
    try testing.expectEqual(@as(u8, 8), ppu.extraLeftCur);
    try testing.expectEqual(@as(u8, 4), ppu.extraRightCur);
    try testing.expectEqual(@as(u8, 2), ppu.extraBottomCur);
}

test "ppu_read only answers the multiplication result registers" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    ppu.m7matrix[0] = 0x0002;
    ppu.m7matrix[1] = 0x0300; // >> 8 = 3
    try testing.expectEqual(@as(u8, 6), ppu_read(ppu, 0x34));
    try testing.expectEqual(@as(u8, 0), ppu_read(ppu, 0x35));
    try testing.expectEqual(@as(u8, 0xff), ppu_read(ppu, 0x00));
}

test "clearBackdrop fills the buffer with the backdrop marker" {
    const ppu = try testPpu();
    defer testing.allocator.destroy(ppu);
    clearBackdrop(&ppu.bgBuffers[0]);
    for (ppu.bgBuffers[0].data) |v|
        try testing.expectEqual(@as(PpuZbufType, 0x0500), v);
}

test "sprite priority packing matches the layer ordering comment" {
    // Sprites with priority 3 land above BG1 priority 1, and priority 0
    // sprites land below BG1 priority 0.
    try testing.expectEqual(@as(u32, 14), spritePrioToPrioHi(3));
    try testing.expectEqual(@as(u32, 2), spritePrioToPrioHi(0));
    // The low bits carry the palette-derived color math flag.
    try testing.expectEqual(spritePrioToPrio(3, false) + 2, spritePrioToPrio(3, true));
}

test "the mode tables came over intact" {
    try testing.expectEqual(10, layersPerMode.len);
    try testing.expectEqual(10, prioritysPerMode.len);
    try testing.expectEqual(10, bitDepthsPerMode.len);
    try testing.expectEqual(12, layerCountPerMode[0]);
    try testing.expectEqual(7, layerCountPerMode[9]);
    // Mode 1 with the l3 priority bit is entry 8.
    try testing.expectEqual(@as(u8, 2), layersPerMode[8][0]);
    try testing.expectEqual(@as(u8, 1), prioritysPerMode[8][0]);
    try testing.expectEqual(@as(u8, 4), bitDepthsPerMode[1][0]);
    try testing.expectEqual(8, kSpriteSizes.len);
    try testing.expectEqual(@as(u8, 16), kSpriteSizes[0][1]);
}
