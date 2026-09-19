//! Layout mirror for `struct Ppu` (ppu.h). ppu.c has not been ported yet, so
//! this only describes the struct for the modules that read it.
const std = @import("std");

// src/types.h build-time options. kPpuXPixels widens every per-scanline buffer
// in the struct, so it has to agree with the C build exactly.
pub const kEnableLargeScreen = 1;
pub const kPpuExtraLeftRight = if (kEnableLargeScreen != 0) 96 else 0;
pub const kPpuXPixels = 256 + kPpuExtraLeftRight * 2;

/// Must match `struct BgLayer` in ppu.h.
pub const BgLayer = extern struct {
    hScroll: u16,
    vScroll: u16,
    // -- snapshot starts here
    tilemapWider: bool,
    tilemapHigher: bool,
    tilemapAdr: u16,
    // -- snapshot ends here
    tileAdr: u16,
};

pub const PpuZbufType = u16;

/// This holds the prio in the upper 8 bits and the color in the lower 8 bits.
pub const PpuPixelPrioBufs = extern struct {
    data: [kPpuXPixels]PpuZbufType,
};

pub const kPpuRenderFlags_NewRenderer: u32 = 1;
/// Render mode7 upsampled by 4x4
pub const kPpuRenderFlags_4x4Mode7: u32 = 2;
/// Use 240 height instead of 224
pub const kPpuRenderFlags_Height240: u32 = 4;
/// Disable sprite render limits
pub const kPpuRenderFlags_NoSpriteLimits: u32 = 8;

/// Must match `struct Ppu` in ppu.h.
pub const Ppu = extern struct {
    lineHasSprites: bool,
    lastBrightnessMult: u8,
    lastMosaicModulo: u8,
    renderFlags: u8,
    renderPitch: u32,
    renderBuffer: ?[*]u8,
    extraLeftCur: u8,
    extraRightCur: u8,
    extraLeftRight: u8,
    extraBottomCur: u8,
    mode7PerspectiveLow: f32,
    mode7PerspectiveHigh: f32,

    // TMW / TSW etc
    screenEnabled: [2]u8,
    screenWindowed: [2]u8,
    mosaicEnabled: u8,
    mosaicSize: u8,
    // object/sprites
    objTileAdr1: u16,
    objTileAdr2: u16,
    objSize: u8,
    // Window
    window1left: u8,
    window1right: u8,
    window2left: u8,
    window2right: u8,
    windowsel: u32,

    // color math
    clipMode: u8,
    preventMathMode: u8,
    addSubscreen: bool,
    subtractColor: bool,
    halfColor: bool,
    mathEnabled: u8,
    fixedColorR: u8,
    fixedColorG: u8,
    fixedColorB: u8,
    // settings
    forcedBlank: bool,
    brightness: u8,
    mode: u8,

    // vram access
    vramPointer: u16,
    vramIncrement: u16,
    vramIncrementOnHigh: bool,
    // cgram access
    cgramPointer: u8,
    cgramSecondWrite: bool,
    cgramBuffer: u8,
    // oam access
    oamAdr: u16,
    oamSecondWrite: bool,
    oamBuffer: u8,

    // background layers
    bgLayer: [4]BgLayer,
    scrollPrev: u8,
    scrollPrev2: u8,

    // mode 7
    m7matrix: [8]i16, // a, b, c, d, x, y, h, v
    m7prev: u8,
    m7largeField: bool,
    m7charFill: bool,
    m7xFlip: bool,
    m7yFlip: bool,
    m7extBg_always_zero: bool,
    // mode 7 internal
    m7startX: i32,
    m7startY: i32,

    oam: [0x110]u16,

    // store 31 extra entries to remove the need for clamp
    brightnessMult: [32 + 31]u8,
    brightnessMultHalf: [32 * 2]u8,
    cgram: [0x100]u16,
    mosaicModulo: [kPpuXPixels]u8,
    colorMapRgb: [256]u32,
    bgBuffers: [2]PpuPixelPrioBufs,
    objBuffer: PpuPixelPrioBufs,
    vram: [0x8000]u16,
};

const testing = std.testing;

test "Ppu layout matches ppu.h" {
    // Offsets taken from the C compiler on this target, with the large screen
    // option on (kPpuXPixels = 448).
    if (@sizeOf(*anyopaque) != 8) return error.SkipZigTest;
    try testing.expectEqual(448, kPpuXPixels);
    try testing.expectEqual(10, @sizeOf(BgLayer));
    try testing.expectEqual(896, @sizeOf(PpuPixelPrioBufs));
    try testing.expectEqual(71024, @sizeOf(Ppu));
    try testing.expectEqual(8, @offsetOf(Ppu, "renderBuffer"));
    try testing.expectEqual(20, @offsetOf(Ppu, "mode7PerspectiveLow"));
    try testing.expectEqual(28, @offsetOf(Ppu, "screenEnabled"));
    try testing.expectEqual(34, @offsetOf(Ppu, "objTileAdr1"));
    try testing.expectEqual(44, @offsetOf(Ppu, "windowsel"));
    try testing.expectEqual(48, @offsetOf(Ppu, "clipMode"));
    try testing.expectEqual(60, @offsetOf(Ppu, "vramPointer"));
    try testing.expectEqual(72, @offsetOf(Ppu, "bgLayer"));
    try testing.expectEqual(114, @offsetOf(Ppu, "m7matrix"));
    try testing.expectEqual(136, @offsetOf(Ppu, "m7startX"));
    try testing.expectEqual(144, @offsetOf(Ppu, "oam"));
    try testing.expectEqual(688, @offsetOf(Ppu, "brightnessMult"));
    try testing.expectEqual(816, @offsetOf(Ppu, "cgram"));
    try testing.expectEqual(1328, @offsetOf(Ppu, "mosaicModulo"));
    try testing.expectEqual(1776, @offsetOf(Ppu, "colorMapRgb"));
    try testing.expectEqual(2800, @offsetOf(Ppu, "bgBuffers"));
    try testing.expectEqual(4592, @offsetOf(Ppu, "objBuffer"));
    try testing.expectEqual(5488, @offsetOf(Ppu, "vram"));
}
