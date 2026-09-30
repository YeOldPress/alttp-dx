//! Port of src/load_gfx.c: graphics decompression and the VRAM/WRAM uploads
//! built on top of it, the whole Palette_Load_* / PaletteFilter_* family, and
//! the iris-spotlight and water HDMA window tables.
//!
//! The 3-to-4 bitplane expanders and the LZ decompressor read unaligned 16-bit
//! words out of the asset blobs on purpose, so every such access goes through
//! align(1) pointers here rather than relying on the C build's disabled UBSan.
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl.zig");
const rtl_types = @import("zelda_rtl_types.zig");
const util = @import("util.zig");
const main_mod = @import("main.zig");
const features = @import("features.zig");
const tables = @import("load_gfx_tables.zig");

const MemBlk = util.MemBlk;
const g_ram = &vars.g_ram;
const g_zenv = &rtl_types.g_zenv;

// snes/snes_regs.h
const WH0 = 0x2126;
const HDMAEN = 0x420c;

// load_gfx.h
pub const kSrmOffs_Gloves = 0x354;
pub const kSrmOffs_Sword = 0x359;
pub const kSrmOffs_Shield = 0x35a;
pub const kSrmOffs_Armor = 0x35b;
pub const kSrmOffs_DiedCounter = 0x405;
pub const kSrmOffs_Name = 0x3d9;
pub const kSrmOffs_Health = 0x36c;

// Palette destinations, from the enum near the bottom of load_gfx.c.
const kPal_sp0l = 0x102;
const kPal_sp0r = 0x112;
/// Used for 64 colors, colors switched if in darkworld mode.
const kPal_sp1to4 = 0x122;
const kPal_sp5l = 0x1a2;
const kPal_Sword = 0x1b2;
const kPal_Shield = 0x1b8;
const kPal_sp6l = 0x1c2;
const kPal_sp6r = 0x1d2;
const kPal_sp7l = 0x1e2;
const kPal_sp7r = 0x1f2;
const kPal_ArmorGloves = 0x1e2;
const kPal_PalaceMap = 0x182;

// overworld.c
extern const kVariousPacks: [16]u8;
extern fn SetTargetOverworldWarpToPyramid() void;
extern fn PreOverworld_LoadOverlays() void;
extern fn Overworld_DrawScreenAtCurrentMirrorPosition() void;
extern fn MirrorWarp_LoadSpritesAndColors() void;
extern fn HandleFollowersAfterMirroring() void;
// sprite.c
extern fn Sprite_ResetAll() void;

/// Allow this to be overwritten; main.zig patches it from the link graphics.
pub export var kGlovesColor: [2]u16 = .{ 0x52f6, 0x376 };

// ---------------------------------------------------------------------------
// Small helpers for the C macros this file leans on.
// ---------------------------------------------------------------------------

/// types.h WORD() over a byte pointer: an unaligned little-endian 16-bit read.
inline fn rdWord(p: [*]const u8) u16 {
    return std.mem.readInt(u16, p[0..2], .little);
}

inline fn wrWord(p: [*]u8, v: u16) void {
    std.mem.writeInt(u16, p[0..2], v, .little);
}

/// types.h BYTE(): the low byte of a 16-bit work-ram variable.
inline fn loPtr(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

/// types.h WORD() applied to a variable declared as a byte.
inline fn wordPtr(p: *u8) *align(1) u16 {
    return @ptrCast(p);
}

inline fn sign16(v: u16) bool {
    return v & 0x8000 != 0;
}

inline fn ram(off: usize) [*]u8 {
    return g_ram[off..].ptr;
}

/// assets.h: the palette blobs are plain uint16 arrays hanging off the asset
/// table. They are not guaranteed aligned inside the blob, hence align(1).
inline fn assetU16(comptime idx: usize) [*]align(1) const u16 {
    return @ptrCast(main_mod.g_asset_ptrs[idx].?);
}

inline fn kPalette_DungBgMain() [*]align(1) const u16 {
    return assetU16(79);
}
inline fn kPalette_MainSpr() [*]align(1) const u16 {
    return assetU16(80);
}
inline fn kPalette_ArmorAndGloves() [*]align(1) const u16 {
    return assetU16(81);
}
inline fn kPalette_Sword() [*]align(1) const u16 {
    return assetU16(82);
}
inline fn kPalette_Shield() [*]align(1) const u16 {
    return assetU16(83);
}
inline fn kPalette_SpriteAux3() [*]align(1) const u16 {
    return assetU16(84);
}
/// load_gfx.c #defines kPalette_MiscSprite to this, to avoid renaming in assets.dat.
inline fn kPalette_MiscSprite() [*]align(1) const u16 {
    return assetU16(85);
}
inline fn kPalette_SpriteAux1() [*]align(1) const u16 {
    return assetU16(86);
}
inline fn kPalette_OverworldBgMain() [*]align(1) const u16 {
    return assetU16(87);
}
inline fn kPalette_OverworldBgAux12() [*]align(1) const u16 {
    return assetU16(88);
}
inline fn kPalette_OverworldBgAux3() [*]align(1) const u16 {
    return assetU16(89);
}
inline fn kPalette_PalaceMapBg() [*]align(1) const u16 {
    return assetU16(90);
}
inline fn kPalette_PalaceMapSpr() [*]align(1) const u16 {
    return assetU16(91);
}
inline fn kHudPalData() [*]align(1) const u16 {
    return assetU16(92);
}
inline fn kOverworldMapPaletteData() [*]align(1) const u16 {
    return assetU16(93);
}

inline fn kSprGfx(idx: c_int) MemBlk {
    return main_mod.FindInAssetArray(64, idx);
}
inline fn kBgGfx(idx: c_int) MemBlk {
    return main_mod.FindInAssetArray(65, idx);
}
inline fn kDialogueFont(idx: c_int) MemBlk {
    return main_mod.FindInAssetArray(95, idx);
}

fn GetCompSpritePtr(i: c_int) [*]const u8 {
    return kSprGfx(i).ptr.?;
}

// ---------------------------------------------------------------------------
// Palette filtering
// ---------------------------------------------------------------------------

/// The shared body of the two bounce filters: nudge each channel of
/// main_palette_buffer[j] one step toward (or away from) the aux buffer.
inline fn filterOne(load_ptr: [*]const u16, mask: u16, dt: u16, j: usize) void {
    var c = vars.main_palette_buffer[j];
    const a = vars.aux_palette_buffer[j];
    if (load_ptr[(a & 0x1f) * 2] & mask == 0) c +%= dt;
    if (load_ptr[(a & 0x3e0) >> 4] & mask == 0) c +%= dt << 5;
    if (load_ptr[(a & 0x7c00) >> 9] & mask == 0) c +%= dt << 10;
    vars.main_palette_buffer[j] = c;
}

pub export fn ApplyPaletteFilter_bounce() callconv(.c) void {
    const countdown = vars.palette_filter_countdown.*;
    const load_ptr = tables.kPaletteFilteringBits[@intFromBool(countdown >= 0x10)..].ptr;
    const mask = rtl.kUpperBitmasks[countdown & 0xf];
    const dt: u16 = if (vars.darkening_or_lightening_screen.* != 0) 1 else 0xffff;

    var j: usize = 0;
    while (true) {
        filterOne(load_ptr, mask, dt, j);
        j += 1;
        if (j == 1) {
            j = 0x20;
        } else if (j == 0xd8) {
            j = 0xe0;
        } else if (j == 0xf0) {
            break;
        }
    }
    vars.flag_update_cgram_in_nmi.* +%= 1;
    if (vars.darkening_or_lightening_screen.* == 0) {
        vars.palette_filter_countdown.* +%= 1;
        if (vars.palette_filter_countdown.* != vars.mosaic_target_level.*) return;
    } else {
        const old = vars.palette_filter_countdown.*;
        vars.palette_filter_countdown.* = old -% 1;
        if (old != vars.mosaic_target_level.*) return;
    }
    vars.darkening_or_lightening_screen.* ^= 2;
    vars.palette_filter_countdown.* = 0;
    vars.subsubmodule_index.* +%= 1;
}

pub export fn PaletteFilter_Range(from: c_int, to: c_int) callconv(.c) void {
    const countdown = vars.palette_filter_countdown.*;
    const load_ptr = tables.kPaletteFilteringBits[@intFromBool(countdown >= 0x10)..].ptr;
    const mask = rtl.kUpperBitmasks[countdown & 0xf];
    const dt: u16 = if (vars.darkening_or_lightening_screen.* != 0) 1 else 0xffff;

    var j = from;
    while (j != to) : (j += 1)
        filterOne(load_ptr, mask, dt, @intCast(j));
}

pub export fn PaletteFilter_IncrCountdown() callconv(.c) void {
    vars.palette_filter_countdown.* +%= 1;
    if (vars.palette_filter_countdown.* == 0x1f) {
        vars.palette_filter_countdown.* = 0;
        vars.darkening_or_lightening_screen.* ^= 2;
        if (vars.darkening_or_lightening_screen.* != 0) {
            // wtf? -- upstream comment; this bumps the 16-bit view of a byte var.
            const p = wordPtr(vars.link_actual_vel_y);
            p.* +%= 1;
        }
    }
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

// ---------------------------------------------------------------------------
// Graphics loading
// ---------------------------------------------------------------------------

pub export fn LoadItemAnimationGfxOne(dst: [*]u8, num: c_int, r12: c_int, from_temp: bool) callconv(.c) [*]u8 {
    const base_src: [*]const u8 = if (from_temp) ram(0x14000) else GetCompSpritePtr(0);
    const src = base_src + @as(usize, tables.kIntro_LoadGfx_Tab[@intCast(r12)]) * 24;
    Expand3To4High(dst, src, base_src, num);
    Expand3To4High(dst + 0x20 * @as(usize, @intCast(num)), src + 0x180, base_src, num);
    return dst + 0x40 * @as(usize, @intCast(num));
}

pub export fn snes_divide(dividend: u16, divisor: u8) callconv(.c) u16 {
    return if (divisor != 0) dividend / divisor else 0xffff;
}

pub export fn EraseTileMaps_normal() callconv(.c) void {
    EraseTileMaps(0x7f, 0x1ec);
}

fn DecompAndUpload2bpp(vram_ptr: [*]u16, pack: c_int) void {
    _ = Decomp_spr(ram(0x14000), pack);
    const src = ram(0x14000);
    @memcpy(@as([*]u8, @ptrCast(vram_ptr))[0 .. 1024 * 2], src[0 .. 1024 * 2]);
}

pub export fn RecoverPegGFXFromMapping() callconv(.c) void {
    if (loPtr(vars.orange_blue_barrier_state).* != 0) {
        Dungeon_UpdatePegGFXBuffer(0x180, 0x0);
    } else {
        Dungeon_UpdatePegGFXBuffer(0x0, 0x180);
    }
}

pub export fn LoadOverworldMapPalette() callconv(.c) void {
    const offs: usize = if (vars.overworld_screen_index.* & 0x40 != 0) 0x80 else 0;
    const src: [*]const u8 = @ptrCast(kOverworldMapPaletteData() + offs);
    const dst: [*]u8 = @ptrCast(vars.main_palette_buffer);
    @memcpy(dst[0..256], src[0..256]);
}

pub export fn EraseTileMaps_triforce() callconv(.c) void {
    EraseTileMaps(0xa9, 0x7f);
}

pub export fn EraseTileMaps_dungeonmap() callconv(.c) void {
    EraseTileMaps(0x7f, 0x300);
}

pub export fn EraseTileMaps(r2: u16, r0: u16) callconv(.c) void {
    const vram = g_zenv.vram.?;
    @memset(vram[0..0x2000], r0);
    @memset(vram[0x6000 .. 0x6000 + 0x800], r2);
}

pub export fn EnableForceBlank() callconv(.c) void {
    vars.INIDISP_copy.* = 0x80;
    vars.HDMAEN_copy.* = 0;
}

pub export fn LoadItemGFXIntoWRAM4BPPBuffer() callconv(.c) void {
    var dst = ram(0x9000 + 0x480);
    dst = LoadItemAnimationGfxOne(dst, 7, 0, false); // rod
    dst = LoadItemAnimationGfxOne(dst, 7, 1, false); // hammer
    dst = LoadItemAnimationGfxOne(dst, 3, 2, false); // bow

    _ = Decomp_spr(ram(0x14000), 95);
    dst = LoadItemAnimationGfxOne(dst, 4, 3, true); // shovel
    dst = LoadItemAnimationGfxOne(dst, 3, 4, true); // sleeping zzz
    dst = LoadItemAnimationGfxOne(dst, 1, 5, true); // misc #2
    dst = LoadItemAnimationGfxOne(dst, 4, 6, false); // hookshot

    _ = Decomp_spr(ram(0x14000), 96);
    dst = LoadItemAnimationGfxOne(dst, 14, 7, true); // bugnet
    dst = LoadItemAnimationGfxOne(dst, 7, 8, true); // cane

    _ = Decomp_spr(ram(0x14000), 95);
    dst = LoadItemAnimationGfxOne(dst, 2, 9, true); // book of mudora
    _ = Decomp_spr(ram(0x14000), 84);

    dst = ram(0xa480);
    Expand3To4High(dst, ram(0x14000), ram(0), 8);
    Expand3To4High(dst + 8 * 0x20, ram(0x14180), ram(0), 8);

    // rupees
    _ = Decomp_spr(ram(0x14000), 96);
    dst = ram(0xb280);
    Expand3To4High(dst, ram(0x14000), ram(0), 3);
    Expand3To4High(dst + 3 * 0x20, ram(0x14180), ram(0), 3);

    LoadItemGFX_Auxiliary();
}

pub export fn DecompressSwordGraphics() callconv(.c) void {
    _ = Decomp_spr(ram(0x14600), 0x5f);
    _ = Decomp_spr(ram(0x14000), 0x5e);
    const src = ram(0x14000) + tables.kSwordTypeToGfxOffs[vars.link_sword_type.*];
    Expand3To4High(ram(0x9000 + 0), src, ram(0), 12);
    Expand3To4High(ram(0x9000 + 0x180), src + 0x180, ram(0), 12);
}

pub export fn DecompressShieldGraphics() callconv(.c) void {
    _ = Decomp_spr(ram(0x14600), 0x5f);
    _ = Decomp_spr(ram(0x14000), 0x5e);
    const src = ram(0x14000) + tables.kShieldTypeToGfxOffs[vars.link_shield_type.*];
    Expand3To4High(ram(0x9000 + 0x300), src, ram(0), 6);
    Expand3To4High(ram(0x9000 + 0x3c0), src + 0x180, ram(0), 6);
}

pub export fn DecompressAnimatedDungeonTiles(a: u8) callconv(.c) void {
    _ = Decomp_bg(ram(0x14000), a);
    Do3To4Low16Bit(ram(0x9000 + 0x1680), ram(0x14000), 48);
    _ = Decomp_bg(ram(0x14000), 0x5c);
    Do3To4Low16Bit(ram(0x9000 + 0x1C80), ram(0x14000), 48);

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const p = ram(0x9000 + i * 2);
        const x = rdWord(p + 0x1880);
        wrWord(p + 0x1880, rdWord(p + 0x1C80));
        wrWord(p + 0x1C80, rdWord(p + 0x1E80));
        wrWord(p + 0x1E80, rdWord(p + 0x1A80));
        wrWord(p + 0x1A80, x);
    }
    vars.animated_tile_vram_addr.* = 0x3b00;
}

pub export fn DecompressAnimatedOverworldTiles(a: u8) callconv(.c) void {
    _ = Decomp_bg(ram(0x14000), a);
    Do3To4Low16Bit(ram(0x9000 + 0x1680), ram(0x14000), 64);
    _ = Decomp_bg(ram(0x14000), @as(c_int, a) + 1);
    Do3To4Low16Bit(ram(0x9000 + 0x1E80), ram(0x14000), 32);
    vars.animated_tile_vram_addr.* = 0x3c00;
}

pub export fn LoadItemGFX_Auxiliary() callconv(.c) void {
    _ = Decomp_bg(ram(0x14000), 0xf);
    Do3To4Low16Bit(ram(0x9000 + 0x2340), ram(0x14000), 16);

    _ = Decomp_spr(ram(0x14000), 0x58);
    Do3To4Low16Bit(ram(0x9000 + 0x2540), ram(0x14000), 32);

    _ = Decomp_bg(ram(0x14000), 0x5);
    Do3To4Low16Bit(ram(0x9000 + 0x2dc0), ram(0x14480), 2);
}

pub export fn LoadFollowerGraphics() callconv(.c) void {
    var yv: c_int = 0x64;
    const fi = vars.follower_indicator.*;
    if (fi != 1) {
        yv = 0x66;
        if (fi >= 9) {
            yv = 0x59;
            if (fi >= 12) yv = 0x58;
        }
    }
    _ = Decomp_spr(ram(0x14600), yv);
    _ = Decomp_spr(ram(0x14000), 0x65);
    Do3To4Low16Bit(ram(0x9000) + 0x2940, ram(0x14000 + @as(usize, tables.kTagalongWhich[fi])), 0x20);
}

pub export fn WriteTo4BPPBuffer_at_7F4000(a: u8) callconv(.c) void {
    const src = ram(0x14000) + tables.kDecodeAnimatedSpriteTile_Tab[a];
    Expand3To4High(ram(0x9000) + 0x2d40, src, ram(0), 2);
    Expand3To4High(ram(0x9000) + 0x2d40 + 0x40, src + 0x180, ram(0), 2);
}

pub export fn DecodeAnimatedSpriteTile_variable(a: u8) callconv(.c) void {
    const y: c_int = if (a == 0x23 or a >= 0x37)
        0x5d
    else if (a == 0xc or a >= 0x24)
        0x5c
    else
        0x5b;
    _ = Decomp_spr(ram(0x14600), y);
    _ = Decomp_spr(ram(0x14000), 0x5a);
    WriteTo4BPPBuffer_at_7F4000(a);
}

pub export fn Expand3To4High(dst_in: [*]u8, src_in: [*]const u8, base: [*]const u8, num_in: c_int) callconv(.c) void {
    var dst = dst_in;
    var src = src_in;
    var num = num_in;
    while (true) {
        var src2 = src + 0x10;
        var n: u32 = 8;
        while (true) {
            const t = rdWord(src);
            const u = src2[0];
            wrWord(dst, t);
            const v = (@as(u32, t) | (@as(u32, t) >> 8) | u) << 8;
            wrWord(dst + 0x10, @as(u16, @truncate(v)) | u);
            src += 2;
            src2 += 1;
            dst += 2;
            n -= 1;
            if (n == 0) break;
        }
        dst += 16;
        src = src2;
        if ((@intFromPtr(src) - @intFromPtr(base)) & 0x78 == 0) src += 0x180;
        num -= 1;
        if (num == 0) break;
    }
}

pub export fn LoadTransAuxGFX() callconv(.c) void {
    const dst = ram(0x6000);
    const p = &tables.kAuxTilesets[vars.aux_tile_theme_index.*];

    if (p[0] != 0) {
        vars.aux_bg_subset_0.* = p[0];
        std.debug.assert(Decomp_bg(dst, vars.aux_bg_subset_0.*) == 0x600);
    }
    if (p[1] != 0) {
        vars.aux_bg_subset_1.* = p[1];
        std.debug.assert(Decomp_bg(dst + 0x600, vars.aux_bg_subset_1.*) == 0x600);
    }
    if (p[2] != 0) {
        vars.aux_bg_subset_2.* = p[2];
        std.debug.assert(Decomp_bg(dst + 0x600 * 2, vars.aux_bg_subset_2.*) == 0x600);
    }
    if (p[3] != 0) {
        vars.aux_bg_subset_3.* = p[3];
        std.debug.assert(Decomp_bg(dst + 0x600 * 3, vars.aux_bg_subset_3.*) == 0x600);
    }
    Gfx_LoadSpritesInner(dst + 0x600 * 4);
}

pub export fn LoadTransAuxGFX_sprite() callconv(.c) void {
    Gfx_LoadSpritesInner(ram(0x7800));
}

pub export fn Gfx_LoadSpritesInner(dst: [*]u8) callconv(.c) void {
    const p = &tables.kSpriteTilesets[vars.sprite_graphics_index.*];

    if (p[0] != 0) vars.sprite_gfx_subset_0.* = p[0];
    std.debug.assert(Decomp_spr(dst, vars.sprite_gfx_subset_0.*) == 0x600);
    if (p[1] != 0) vars.sprite_gfx_subset_1.* = p[1];
    std.debug.assert(Decomp_spr(dst + 0x600, vars.sprite_gfx_subset_1.*) == 0x600);
    if (p[2] != 0) vars.sprite_gfx_subset_2.* = p[2];
    std.debug.assert(Decomp_spr(dst + 0x600 * 2, vars.sprite_gfx_subset_2.*) == 0x600);
    if (p[3] != 0) vars.sprite_gfx_subset_3.* = p[3];
    std.debug.assert(Decomp_spr(dst + 0x600 * 3, vars.sprite_gfx_subset_3.*) == 0x600);
    vars.incremental_counter_for_vram.* = 0;
}

pub export fn ReloadPreviouslyLoadedSheets() callconv(.c) void {
    _ = Decomp_bg(ram(0x6000), vars.aux_bg_subset_0.*);
    _ = Decomp_bg(ram(0x6600), vars.aux_bg_subset_1.*);
    _ = Decomp_bg(ram(0x6c00), vars.aux_bg_subset_2.*);
    _ = Decomp_bg(ram(0x7200), vars.aux_bg_subset_3.*);
    _ = Decomp_spr(ram(0x7800), vars.sprite_gfx_subset_0.*);
    _ = Decomp_spr(ram(0x7e00), vars.sprite_gfx_subset_1.*);
    _ = Decomp_spr(ram(0x8400), vars.sprite_gfx_subset_2.*);
    _ = Decomp_spr(ram(0x8a00), vars.sprite_gfx_subset_3.*);
    vars.incremental_counter_for_vram.* = 0;
}

pub export fn Attract_DecompressStoryGFX() callconv(.c) void {
    _ = Decomp_spr(ram(0x14000), 0x67);
    _ = Decomp_spr(ram(0x14800), 0x68);
}

pub export fn AnimateMirrorWarp() callconv(.c) void {
    const st = vars.overworld_map_state.*;
    vars.overworld_map_state.* = st +% 1;
    vars.nmi_disable_core_updates.* = tables.kMirrorWarp_LoadNext_NmiLoad[st];
    vars.nmi_subroutine_index.* = vars.nmi_disable_core_updates.*;
    const xt: usize = if (vars.overworld_screen_index.* & 0x40 != 0) 8 else 0;

    switch (st) {
        0 => {
            vars.mirror_vars.ctr2 +%= 1;
            if (vars.mirror_vars.ctr2 != 32) {
                vars.overworld_map_state.* = 0;
            } else {
                SetTargetOverworldWarpToPyramid();
            }
        },
        1 => {
            AnimateMirrorWarp_DecompressNewTileSets();
            _ = Decomp_bg(ram(0x14000), kVariousPacks[xt]);
            _ = Decomp_bg(ram(0x14600), kVariousPacks[xt + 1]);
            Do3To4High16Bit(ram(0x10000), ram(0x14000), 64);
            Do3To4Low16Bit(ram(0x10800), ram(0x14600), 64);
        },
        2 => {
            _ = Decomp_bg(ram(0x14000), kVariousPacks[xt + 2]);
            _ = Decomp_bg(ram(0x14600), kVariousPacks[xt + 3]);
            Do3To4Low16Bit(ram(0x10000), ram(0x14000), 64);
            Do3To4High16Bit(ram(0x10800), ram(0x14600), 64);
        },
        3 => {
            _ = Decomp_bg(ram(0x14000), vars.aux_bg_subset_1.*);
            _ = Decomp_bg(ram(0x14600), vars.aux_bg_subset_2.*);
            Do3To4High16Bit(ram(0x10000), ram(0x14000), 128);
        },
        4 => {
            _ = Decomp_bg(ram(0x14000), kVariousPacks[xt + 4]);
            _ = Decomp_bg(ram(0x14600), kVariousPacks[xt + 5]);
            Do3To4Low16Bit(ram(0x10000), ram(0x14000), 128);
        },
        5 => {
            PreOverworld_LoadOverlays();
            const os = loPtr(vars.overworld_screen_index).*;
            if (os == 27 or os == 91) vars.TS_copy.* = 1;
            vars.submodule_index.* -%= 1;
            vars.nmi_disable_core_updates.* = 12;
            vars.nmi_subroutine_index.* = 12;
        },
        6, 9 => {
            vars.nmi_disable_core_updates.* = 13;
            vars.nmi_subroutine_index.* = 13;
        },
        7 => {
            Overworld_DrawScreenAtCurrentMirrorPosition();
            vars.nmi_disable_core_updates.* +%= 1;
        },
        8 => {
            MirrorWarp_LoadSpritesAndColors();
            vars.nmi_disable_core_updates.* = 12;
            vars.nmi_subroutine_index.* = 12;
        },
        10 => {
            const t: u8 = @truncate(vars.overworld_screen_index.* & 0xbf);
            DecompressAnimatedOverworldTiles(if (t == 3 or t == 5 or t == 7) 0x58 else 0x5a);
        },
        11 => {
            const t: u8 = @truncate(vars.overworld_screen_index.*);
            vars.TS_copy.* = @intFromBool(t == 0 or t == 0x70 or t == 0x40 or t == 0x5b or
                t == 3 or t == 5 or t == 7 or t == 0x43 or t == 0x45 or t == 0x47);
            Do3To4High16Bit(ram(0x10000), GetCompSpritePtr(kVariousPacks[xt + 6]), 64);
        },
        12 => {
            _ = Decomp_spr(ram(0x14000), vars.sprite_gfx_subset_0.*);
            _ = Decomp_spr(ram(0x14600), vars.sprite_gfx_subset_1.*);
            const tt = wordPtr(vars.sprite_gfx_subset_0).*;
            if (tt == 0x52 or tt == 0x53 or tt == 0x5a or tt == 0x5b) {
                Do3To4High16Bit(ram(0x10000), ram(0x14000), 64);
            } else {
                Do3To4Low16Bit(ram(0x10000), ram(0x14000), 64);
            }
            Do3To4Low16Bit(ram(0x10800), ram(0x14600), 64);
        },
        13 => {
            _ = Decomp_spr(ram(0x14000), vars.sprite_gfx_subset_2.*);
            _ = Decomp_spr(ram(0x14600), vars.sprite_gfx_subset_3.*);
            Do3To4Low16Bit(ram(0x10000), ram(0x14000), 128);
            HandleFollowersAfterMirroring();
        },
        14 => vars.overworld_map_state.* = 14,
        else => {},
    }
}

pub export fn AnimateMirrorWarp_DecompressNewTileSets() callconv(.c) void {
    const mt = &tables.kMainTilesets[vars.main_tile_theme_index.*];
    const at = &tables.kAuxTilesets[vars.aux_tile_theme_index.*];

    vars.aux_bg_subset_0.* = if (at[0] != 0) at[0] else mt[3];
    vars.aux_bg_subset_1.* = if (at[1] != 0) at[1] else mt[4];
    vars.aux_bg_subset_2.* = if (at[2] != 0) at[2] else mt[5];
    vars.aux_bg_subset_3.* = if (at[3] != 0) at[3] else mt[6];

    const p = &tables.kSpriteTilesets[vars.sprite_graphics_index.*];
    if (p[0] != 0) vars.sprite_gfx_subset_0.* = p[0];
    if (p[1] != 0) vars.sprite_gfx_subset_1.* = p[1];
    if (p[2] != 0) vars.sprite_gfx_subset_2.* = p[2];
    if (p[3] != 0) vars.sprite_gfx_subset_3.* = p[3];
}

pub export fn Graphics_IncrementalVRAMUpload() callconv(.c) void {
    const i = vars.incremental_counter_for_vram.*;
    if (i == 16) return;

    vars.nmi_update_tilemap_dst.* = tables.kGraphics_IncrementalVramUpload_Dst[i];
    vars.nmi_update_tilemap_src.* = @as(u16, tables.kGraphics_IncrementalVramUpload_Src[i]) << 8;
    vars.incremental_counter_for_vram.* = i +% 1;
}

pub export fn PrepTransAuxGfx() callconv(.c) void {
    Do3To4High16Bit(ram(0x10000), ram(0x6000), 0x40);
    if (vars.aux_tile_theme_index.* >= 32) {
        Do3To4High16Bit(ram(0x10800), ram(0x6600), 0x80);
        Do3To4Low16Bit(ram(0x11800), ram(0x7200), 0x40);
    } else {
        Do3To4Low16Bit(ram(0x10800), ram(0x6600), 0xC0);
    }
}

pub export fn Do3To4High16Bit(dst_in: [*]u8, src_in: [*]const u8, num_in: c_int) callconv(.c) void {
    var dst = dst_in;
    var src = src_in;
    var num = num_in;
    while (true) {
        var src2 = src + 0x10;
        var n: u32 = 8;
        while (true) {
            const t = rdWord(src);
            const u = src2[0];
            wrWord(dst, t);
            const v = (@as(u32, t) | (@as(u32, t) >> 8) | u) << 8;
            wrWord(dst + 0x10, @as(u16, @truncate(v)) | u);
            src += 2;
            src2 += 1;
            dst += 2;
            n -= 1;
            if (n == 0) break;
        }
        dst += 16;
        src = src2;
        num -= 1;
        if (num == 0) break;
    }
}

pub export fn Do3To4Low16Bit(dst_in: [*]u8, src_in: [*]const u8, num_in: c_int) callconv(.c) void {
    var dst = dst_in;
    var src = src_in;
    var num = num_in;
    while (true) {
        var src2 = src + 0x10;
        var n: u32 = 8;
        while (true) {
            wrWord(dst, rdWord(src));
            wrWord(dst + 0x10, src2[0]);
            src += 2;
            src2 += 1;
            dst += 2;
            n -= 1;
            if (n == 0) break;
        }
        dst += 16;
        src = src2;
        num -= 1;
        if (num == 0) break;
    }
}

pub export fn LoadNewSpriteGFXSet() callconv(.c) void {
    Do3To4Low16Bit(ram(0x10000), ram(0x7800), 0xC0);
    const s3 = vars.sprite_gfx_subset_3.*;
    if (s3 == 0x52 or s3 == 0x53 or s3 == 0x5a or s3 == 0x5b) {
        Do3To4High16Bit(ram(0x11800), ram(0x8a00), 0x40);
    } else {
        Do3To4Low16Bit(ram(0x11800), ram(0x8a00), 0x40);
    }
}

pub export fn InitializeTilesets() callconv(.c) void {
    LoadCommonSprites();

    const p = &tables.kSpriteTilesets[vars.sprite_graphics_index.*];
    if (p[0] != 0) vars.sprite_gfx_subset_0.* = p[0];
    if (p[1] != 0) vars.sprite_gfx_subset_1.* = p[1];
    if (p[2] != 0) vars.sprite_gfx_subset_2.* = p[2];
    if (p[3] != 0) vars.sprite_gfx_subset_3.* = p[3];

    const vram = g_zenv.vram.?;
    LoadSpriteGraphics(vram + 0x5000, vars.sprite_gfx_subset_0.*, ram(0x7800));
    LoadSpriteGraphics(vram + 0x5400, vars.sprite_gfx_subset_1.*, ram(0x7e00));
    LoadSpriteGraphics(vram + 0x5800, vars.sprite_gfx_subset_2.*, ram(0x8400));
    LoadSpriteGraphics(vram + 0x5c00, vars.sprite_gfx_subset_3.*, ram(0x8a00));

    const mt = &tables.kMainTilesets[vars.main_tile_theme_index.*];
    const at = &tables.kAuxTilesets[vars.aux_tile_theme_index.*];

    vars.aux_bg_subset_0.* = if (at[0] != 0) at[0] else mt[3];
    vars.aux_bg_subset_1.* = if (at[1] != 0) at[1] else mt[4];
    vars.aux_bg_subset_2.* = if (at[2] != 0) at[2] else mt[5];
    vars.aux_bg_subset_3.* = if (at[3] != 0) at[3] else mt[6];

    LoadBackgroundGraphics(vram + 0x2000, mt[0], 7, ram(0x14000));
    LoadBackgroundGraphics(vram + 0x2400, mt[1], 6, ram(0x14000));
    LoadBackgroundGraphics(vram + 0x2800, mt[2], 5, ram(0x14000));
    LoadBackgroundGraphics(vram + 0x2c00, vars.aux_bg_subset_0.*, 4, ram(0x6000));
    LoadBackgroundGraphics(vram + 0x3000, vars.aux_bg_subset_1.*, 3, ram(0x6600));
    LoadBackgroundGraphics(vram + 0x3400, vars.aux_bg_subset_2.*, 2, ram(0x6c00));
    LoadBackgroundGraphics(vram + 0x3800, vars.aux_bg_subset_3.*, 1, ram(0x7200));
    LoadBackgroundGraphics(vram + 0x3c00, mt[7], 0, ram(0x14000));
}

pub export fn LoadDefaultGraphics() callconv(.c) void {
    var src = GetCompSpritePtr(0);

    var vram_ptr = g_zenv.vram.? + 0x4000;
    const tmp: [*]align(1) u16 = @ptrCast(ram(0xbf));
    var num: u32 = 64;
    while (true) {
        var i: i32 = 7;
        while (i >= 0) : (i -= 1) {
            vram_ptr[0] = rdWord(src);
            vram_ptr += 1;
            tmp[@intCast(i)] = src[0] | src[1];
            src += 2;
        }
        i = 7;
        while (i >= 0) : (i -= 1) {
            const d = src[0];
            vram_ptr[0] = @as(u16, d) | (@as(u16, d | @as(u8, @truncate(tmp[@intCast(i)]))) << 8);
            vram_ptr += 1;
            src += 1;
        }
        num -= 1;
        if (num == 0) break;
    }

    // Load 2bpp graphics used for hud
    DecompAndUpload2bpp(g_zenv.vram.? + 0x7000, 0x6a);
    DecompAndUpload2bpp(g_zenv.vram.? + 0x7400, 0x6b);
    DecompAndUpload2bpp(g_zenv.vram.? + 0x7800, 0x69);
}

pub export fn Attract_LoadBG3GFX() callconv(.c) void {
    // load 2bpp gfx for attract images
    DecompAndUpload2bpp(g_zenv.vram.? + 0x7800, 0x67);
}

pub export fn Graphics_LoadChrHalfSlot() callconv(.c) void {
    var k: c_int = vars.load_chr_halfslot_even_odd.*;
    if (k == 0) return;

    const sp6 = tables.kGraphicsLoadSp6[@intCast(k - 1)];
    if (sp6 >= 0) {
        vars.palette_sp6r_indoors.* = @intCast(sp6);
        if (k == 1) {
            vars.palette_sp6r_indoors.* = 10;
            vars.overworld_palette_aux_or_main.* = 0x200;
            Palette_Load_SpriteEnvironment();
            vars.flag_update_cgram_in_nmi.* +%= 1;
        } else {
            vars.overworld_palette_aux_or_main.* = 0x200;
            Palette_Load_SpriteEnvironment_Dungeon();
            vars.flag_update_cgram_in_nmi.* +%= 1;
        }
    }
    var tilebytes: u8 = 0x44;
    var bank_offs: usize = 0;
    vars.load_chr_halfslot_even_odd.* +%= 1;

    if (vars.load_chr_halfslot_even_odd.* & 1 != 0) {
        vars.load_chr_halfslot_even_odd.* = 0;
        if (k != 18) {
            bank_offs = 0x300;
            tilebytes = 0x46;
            if (k == 2) vars.flag_custom_spell_anim_active.* = 0;
        }
    }
    loPtr(vars.nmi_load_target_addr).* = tilebytes;
    vars.nmi_subroutine_index.* = 11;

    k = tables.kGraphicsHalfSlotPacks[@intCast(k - 1)];
    if (k == 1) k = vars.misc_sprites_graphics_index.*;

    var srcp = GetCompSpritePtr(k) + bank_offs;
    var sprdata: [24]u8 = undefined;
    var num: u32 = 32;
    var dst = ram(0x11000);

    while (true) {
        for (&sprdata) |*b| {
            b.* = srcp[0];
            srcp += 1;
        }

        var src: [*]const u8 = &sprdata;
        var src2: [*]const u8 = sprdata[16..].ptr;
        var n: u32 = 8;
        while (true) {
            const t = rdWord(src);
            const u = src2[0];
            wrWord(dst, t);
            const v = (@as(u32, t) | (@as(u32, t) >> 8) | u) << 8;
            wrWord(dst + 16, @as(u16, @truncate(v)) | u);
            src += 2;
            src2 += 1;
            dst += 2;
            n -= 1;
            if (n == 0) break;
        }
        dst += 16;
        num -= 1;
        if (num == 0) break;
    }
}

pub export fn TransferFontToVRAM() callconv(.c) void {
    const blk = util.FindIndexInMemblk(kDialogueFont(0), 0);
    const dst: [*]u8 = @ptrCast(g_zenv.vram.? + 0x7000);
    @memcpy(dst[0 .. 0x800 * 2], blk.ptr.?[0 .. 0x800 * 2]);
}

pub export fn Do3To4High(vram_ptr_in: [*]u16, decomp_addr_in: [*]const u8) callconv(.c) void {
    var vram_ptr = vram_ptr_in;
    var decomp_addr = decomp_addr_in;
    const t: [*]align(1) u16 = @ptrCast(vars.dung_line_ptrs_row0);
    var j: u32 = 0;
    while (j < 64) : (j += 1) {
        var i: i32 = 7;
        while (i >= 0) : (i -= 1) {
            const d = rdWord(decomp_addr);
            t[@intCast(i)] = (d | (d >> 8)) & 0xff;
            vram_ptr[0] = d;
            vram_ptr += 1;
            decomp_addr += 2;
        }
        i = 7;
        while (i >= 0) : (i -= 1) {
            const d = decomp_addr[0];
            const hi: u16 = (t[@intCast(i)] | d) << 8;
            vram_ptr[0] = @as(u16, d) | hi;
            vram_ptr += 1;
            decomp_addr += 1;
        }
    }
}

pub export fn Do3To4Low(vram_ptr_in: [*]u16, decomp_addr_in: [*]const u8) callconv(.c) void {
    var vram_ptr = vram_ptr_in;
    var decomp_addr = decomp_addr_in;
    var j: u32 = 0;
    while (j < 64) : (j += 1) {
        var i: u32 = 0;
        while (i < 8) : (i += 1) {
            vram_ptr[0] = rdWord(decomp_addr);
            vram_ptr += 1;
            decomp_addr += 2;
        }
        i = 0;
        while (i < 8) : (i += 1) {
            vram_ptr[0] = decomp_addr[0];
            vram_ptr += 1;
            decomp_addr += 1;
        }
    }
}

pub export fn LoadSpriteGraphics(vram_ptr: [*]u16, gfx_pack: c_int, decomp_addr: [*]u8) callconv(.c) void {
    _ = Decomp_spr(decomp_addr, gfx_pack);
    if (gfx_pack == 0x52 or gfx_pack == 0x53 or gfx_pack == 0x5a or gfx_pack == 0x5b or
        gfx_pack == 0x5c or gfx_pack == 0x5e or gfx_pack == 0x5f)
    {
        Do3To4High(vram_ptr, decomp_addr);
    } else {
        Do3To4Low(vram_ptr, decomp_addr);
    }
}

pub export fn LoadBackgroundGraphics(vram_ptr: [*]u16, gfx_pack: c_int, slot: c_int, decomp_addr: [*]u8) callconv(.c) void {
    _ = Decomp_bg(decomp_addr, gfx_pack);
    const high = if (vars.main_tile_theme_index.* >= 0x20)
        (slot == 7 or slot == 2 or slot == 3 or slot == 4)
    else
        (slot >= 4);
    if (high) {
        Do3To4High(vram_ptr, decomp_addr);
    } else {
        Do3To4Low(vram_ptr, decomp_addr);
    }
}

pub export fn LoadCommonSprites() callconv(.c) void {
    const vram = g_zenv.vram.?;
    Do3To4High(vram + 0x4400, GetCompSpritePtr(vars.misc_sprites_graphics_index.*));
    if (vars.main_module_index.* != 1) {
        Do3To4Low(vram + 0x4800, GetCompSpritePtr(6));
        Do3To4Low(vram + 0x4c00, GetCompSpritePtr(7));
    } else {
        // select file
        LoadSpriteGraphics(vram + 0x4800, 94, ram(0x14000));
        LoadSpriteGraphics(vram + 0x4c00, 95, ram(0x14000));
    }
}

pub export fn Decomp_spr(dst: [*]u8, gfx_in: c_int) callconv(.c) c_int {
    var gfx = gfx_in;
    if (gfx < 12) gfx = 12; // ensure it wont decode bad sheets.
    const blk = kSprGfx(gfx);
    // If the size is not 0x600 then it's compressed
    if (gfx >= 103 or blk.size != 0x600)
        return Decompress(dst, blk.ptr.?);
    @memcpy(dst[0..0x600], blk.ptr.?[0..0x600]);
    return 0x600;
}

pub export fn Decomp_bg(dst: [*]u8, gfx: c_int) callconv(.c) c_int {
    return Decompress(dst, kBgGfx(gfx).ptr.?);
}

pub export fn Decompress(dst_org: [*]u8, src_in: [*]const u8) callconv(.c) c_int {
    var dst = dst_org;
    var src = src_in;
    while (true) {
        var cmd: u8 = src[0];
        src += 1;
        if (cmd == 0xff)
            return @intCast(@intFromPtr(dst) - @intFromPtr(dst_org));
        var len: c_int = undefined;
        if ((cmd & 0xe0) != 0xe0) {
            len = @as(c_int, cmd & 0x1f) + 1;
            cmd &= 0xe0;
        } else {
            len = src[0];
            src += 1;
            len += (@as(c_int, cmd & 3) << 8) + 1;
            cmd = @as(u8, @truncate(@as(u16, cmd) << 3)) & 0xe0;
        }
        if (cmd == 0) {
            while (true) {
                dst[0] = src[0];
                dst += 1;
                src += 1;
                len -= 1;
                if (len == 0) break;
            }
        } else if (cmd & 0x80 != 0) {
            var offs: u32 = src[0];
            src += 1;
            offs |= @as(u32, src[0]) << 8;
            src += 1;
            while (true) {
                dst[0] = dst_org[offs];
                offs +%= 1;
                dst += 1;
                len -= 1;
                if (len == 0) break;
            }
        } else if (cmd & 0x40 == 0) {
            const v = src[0];
            src += 1;
            while (true) {
                dst[0] = v;
                dst += 1;
                len -= 1;
                if (len == 0) break;
            }
        } else if (cmd & 0x20 == 0) {
            const lo = src[0];
            src += 1;
            const hi = src[0];
            src += 1;
            while (true) {
                dst[0] = lo;
                dst += 1;
                len -= 1;
                if (len == 0) break;
                dst[0] = hi;
                dst += 1;
                len -= 1;
                if (len == 0) break;
            }
        } else {
            // copy bytes with the byte incrementing by 1 in between
            var v = src[0];
            src += 1;
            while (true) {
                dst[0] = v;
                dst += 1;
                v +%= 1;
                len -= 1;
                if (len == 0) break;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Palette filters
// ---------------------------------------------------------------------------

pub export fn ResetHUDPalettes4and5() callconv(.c) void {
    var i: usize = 0;
    while (i < 8) : (i += 1)
        vars.main_palette_buffer[16 + i] = 0;
    vars.palette_filter_countdown.* = 0;
    vars.darkening_or_lightening_screen.* = 2;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilterHistory() callconv(.c) void {
    PaletteFilter_Range(0x10, 0x18);
    PaletteFilter_IncrCountdown();
}

pub export fn PaletteFilter_WishPonds() callconv(.c) void {
    vars.TS_copy.* = 2;
    vars.CGADSUB_copy.* = 0x30;
    PaletteFilter_WishPonds_Inner();
}

pub export fn PaletteFilter_Crystal() callconv(.c) void {
    vars.TS_copy.* = 1;
    PaletteFilter_WishPonds_Inner();
}

pub export fn PaletteFilter_WishPonds_Inner() callconv(.c) void {
    var i: usize = 0;
    while (i < 8) : (i += 1)
        vars.main_palette_buffer[0xd0 + i] = 0;
    vars.palette_filter_countdown.* = 0;
    vars.darkening_or_lightening_screen.* = 2;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilter_RestoreSP5F() callconv(.c) void {
    var i: i32 = 7;
    while (i >= 0) : (i -= 1)
        vars.main_palette_buffer[208 + @as(usize, @intCast(i))] = vars.aux_palette_buffer[208 + @as(usize, @intCast(i))];
    vars.TS_copy.* = 0;
    vars.CGADSUB_copy.* = 32;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilter_SP5F() callconv(.c) void {
    var i: u32 = 0;
    while (i != 2) : (i += 1) {
        PaletteFilter_Range(208, 216);
        PaletteFilter_IncrCountdown();
        if (vars.palette_filter_countdown.* == 0) break;
    }
}

pub export fn KholdstareShell_PaletteFiltering() callconv(.c) void {
    const t: c_int = if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0) 0x50 else 0x40;
    if (vars.subsubmodule_index.* == 0) {
        const ti: usize = @intCast(t);
        @memcpy(vars.main_palette_buffer[ti .. ti + 8], vars.aux_palette_buffer[ti .. ti + 8]);
        vars.palette_filter_countdown.* = 0;
        vars.darkening_or_lightening_screen.* = 0;
        vars.flag_update_cgram_in_nmi.* +%= 1;
        vars.subsubmodule_index.* = 1;
        return;
    }
    var i: u32 = 0;
    while (i != 2) : (i += 1) {
        PaletteFilter_Range(t, t + 8);
        PaletteFilter_IncrCountdown();
        if (vars.palette_filter_countdown.* == 0) {
            vars.TS_copy.* = 0;
            break;
        }
    }
}

pub export fn AgahnimWarpShadowFilter(k: c_int) callconv(.c) void {
    const ki: usize = @intCast(k);
    vars.palette_filter_countdown.* = vars.agahnim_pal_setting[ki];
    vars.darkening_or_lightening_screen.* = vars.agahnim_pal_setting[ki + 3];
    const t: c_int = tables.kPaletteFilter_Agahnim_Tab[ki] >> 1;
    var i: u32 = 0;
    while (i < 2) : (i += 1) {
        PaletteFilter_Range(t, t + 8);
        vars.palette_filter_countdown.* +%= 1;
        if (vars.palette_filter_countdown.* == 0x1f) {
            vars.palette_filter_countdown.* = 0;
            vars.darkening_or_lightening_screen.* ^= 2;
            break;
        }
    }
    vars.agahnim_pal_setting[ki] = vars.palette_filter_countdown.*;
    vars.agahnim_pal_setting[ki + 3] = vars.darkening_or_lightening_screen.*;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Palette_FadeIntroOneStep() callconv(.c) void {
    PaletteFilter_RestoreAdditive(0x100, 0x1a0);
    PaletteFilter_RestoreAdditive(0xc0, 0x100);
    loPtr(vars.palette_filter_countdown).* -%= 1;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Palette_FadeIntro2() callconv(.c) void {
    PaletteFilter_RestoreAdditive(0x40, 0xc0);
    PaletteFilter_RestoreAdditive(0x40, 0xc0);
    loPtr(vars.palette_filter_countdown).* -%= 1;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilter_RestoreAdditive(from_in: c_int, to_in: c_int) callconv(.c) void {
    var from = from_in >> 1;
    const to = to_in >> 1;
    while (true) {
        const i: usize = @intCast(from);
        const c = vars.main_palette_buffer[i];
        var cx = c;
        const d = vars.aux_palette_buffer[i];
        if ((c & 0x1f) != (d & 0x1f)) cx +%= 1;
        if ((c & 0x3e0) != (d & 0x3e0)) cx +%= 0x20;
        if ((c & 0x7c00) != (d & 0x7c00)) cx +%= 0x400;
        vars.main_palette_buffer[i] = cx;
        from += 1;
        if (from == to) break;
    }
}

pub export fn PaletteFilter_RestoreSubtractive(from_in: u16, to_in: u16) callconv(.c) void {
    var from = from_in >> 1;
    const to = to_in >> 1;
    while (true) {
        const c = vars.main_palette_buffer[from];
        var cx = c;
        const d = vars.aux_palette_buffer[from];
        if ((c & 0x1f) != (d & 0x1f)) cx -%= 1;
        if ((c & 0x3e0) != (d & 0x3e0)) cx -%= 0x20;
        if ((c & 0x7c00) != (d & 0x7c00)) cx -%= 0x400;
        vars.main_palette_buffer[from] = cx;
        from +%= 1;
        if (from == to) break;
    }
}

pub export fn PaletteFilter_InitializeWhiteFilter() callconv(.c) void {
    var i: usize = 0;
    while (i < 256) : (i += 1)
        vars.aux_palette_buffer[i] = 0x7fff;
    vars.main_palette_buffer[32] = vars.main_palette_buffer[0];
    vars.palette_filter_countdown.* = 0;
    vars.darkening_or_lightening_screen.* = 2;
    if (vars.overworld_screen_index.* == 27) {
        vars.aux_palette_buffer[0] = 0;
        vars.aux_palette_buffer[32] = 0;
        vars.main_palette_buffer[0] = 0;
        vars.main_palette_buffer[32] = 0;
    }
    vars.mirror_vars.ctr = 8;
    vars.mirror_vars.ctr2 = 0;
}

pub export fn MirrorWarp_RunAnimationSubmodules() callconv(.c) void {
    vars.mirror_vars.ctr -%= 1;
    if (vars.mirror_vars.ctr != 0) {
        AnimateMirrorWarp();
        return;
    }
    vars.mirror_vars.ctr = 2;
    PaletteFilter_BlindingWhite();
}

pub export fn PaletteFilter_BlindingWhite() callconv(.c) void {
    if (vars.darkening_or_lightening_screen.* == 0xff) return;

    if (vars.darkening_or_lightening_screen.* == 2) {
        PaletteFilter_RestoreAdditive(0x40, 0x1b0);
        PaletteFilter_RestoreAdditive(0x1c0, 0x1e0);
    } else {
        PaletteFilter_RestoreSubtractive(0x40, 0x1b0);
        PaletteFilter_RestoreSubtractive(0x1c0, 0x1e0);
    }
    PaletteFilter_StartBlindingWhite();
}

pub export fn PaletteFilter_StartBlindingWhite() callconv(.c) void {
    vars.main_palette_buffer[0] = vars.main_palette_buffer[32];
    if (vars.darkening_or_lightening_screen.* == 0) {
        vars.palette_filter_countdown.* +%= 1;
        if (vars.palette_filter_countdown.* == 66) {
            vars.darkening_or_lightening_screen.* = 0xff;
            vars.mirror_vars.ctr = 32;
        }
    } else {
        vars.palette_filter_countdown.* +%= 1;
        if (vars.palette_filter_countdown.* == 31) {
            vars.darkening_or_lightening_screen.* ^= 2;
            if (vars.main_module_index.* != 21) return;
            // zelda_snes_dummy_write(HDMAEN, 0) is a no-op inline.
            vars.HDMAEN_copy.* = 0;
            var i: usize = 0;
            while (i < 240) : (i += 1)
                vars.hdma_table_dynamic[i] = 0x778;
            vars.HDMAEN_copy.* = 0xc0;
        }
    }
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilter_BlindingWhiteTriforce() callconv(.c) void {
    PaletteFilter_RestoreAdditive(0x40, 0x200);
    PaletteFilter_StartBlindingWhite();
}

pub export fn PaletteFilter_WhirlpoolBlue() callconv(.c) void {
    if (vars.frame_counter.* & 1 != 0) {
        var i: usize = 0x20;
        while (i != 0x100) : (i += 1) {
            var t = vars.main_palette_buffer[i];
            if ((t & 0x7C00) != 0x7C00) t +%= 0x400;
            vars.main_palette_buffer[i] = t;
        }
        vars.main_palette_buffer[0] = vars.main_palette_buffer[32];
        if (vars.palette_filter_countdown.* & 1 == 0)
            vars.mosaic_level.* +%= 16;
        vars.palette_filter_countdown.* +%= 1;
        if (vars.palette_filter_countdown.* == 31) {
            vars.palette_filter_countdown.* = 0;
            vars.subsubmodule_index.* +%= 1;
            vars.mosaic_level.* = 0xf0;
        }
    }
    vars.BGMODE_copy.* = 9;
    vars.MOSAIC_copy.* = vars.mosaic_level.* | 3;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilter_IsolateWhirlpoolBlue() callconv(.c) void {
    var i: usize = 0x20;
    while (i != 0x100) : (i += 1) {
        var t = vars.main_palette_buffer[i];
        if (t & 0x3e0 != 0) t -%= 0x20;
        if (t & 0x1f != 0) t -%= 1;
        vars.main_palette_buffer[i] = t;
    }
    vars.main_palette_buffer[0] = vars.main_palette_buffer[32];
    vars.palette_filter_countdown.* +%= 1;
    if (vars.palette_filter_countdown.* == 31) {
        vars.palette_filter_countdown.* = 0;
        vars.subsubmodule_index.* +%= 1;
        vars.mosaic_level.* = 0xf0;
    }
    vars.BGMODE_copy.* = 9;
    vars.MOSAIC_copy.* = vars.mosaic_level.* | 3;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilter_WhirlpoolRestoreBlue() callconv(.c) void {
    if (vars.frame_counter.* & 1 != 0) {
        var i: usize = 0x20;
        while (i != 0x100) : (i += 1) {
            const u = vars.aux_palette_buffer[i] & 0x7c00;
            var t = vars.main_palette_buffer[i];
            if ((t & 0x7C00) != u) t -%= 0x400;
            vars.main_palette_buffer[i] = t;
        }
        vars.main_palette_buffer[0] = vars.main_palette_buffer[32];
        if (vars.palette_filter_countdown.* & 1 == 0)
            vars.mosaic_level.* -%= 16;
        vars.palette_filter_countdown.* +%= 1;
        if (vars.palette_filter_countdown.* == 31) {
            vars.palette_filter_countdown.* = 0;
            vars.subsubmodule_index.* +%= 1;
            vars.mosaic_level.* = 0;
        }
    }
    vars.BGMODE_copy.* = 9;
    vars.MOSAIC_copy.* = vars.mosaic_level.* | 3;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilter_WhirlpoolRestoreRedGreen() callconv(.c) void {
    var i: usize = 0x20;
    while (i != 0x100) : (i += 1) {
        const ug = vars.aux_palette_buffer[i] & 0x3e0;
        const ur = vars.aux_palette_buffer[i] & 0x1f;
        var t = vars.main_palette_buffer[i];
        if ((t & 0x3e0) != ug) t +%= 0x20;
        if ((t & 0x1f) != ur) t +%= 1;
        vars.main_palette_buffer[i] = t;
    }
    vars.main_palette_buffer[0] = vars.main_palette_buffer[32];
    vars.palette_filter_countdown.* +%= 1;
    if (vars.palette_filter_countdown.* == 31) {
        vars.palette_filter_countdown.* = 0;
        vars.subsubmodule_index.* +%= 1;
    }
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilter_RestoreBGSubstractiveStrict() callconv(.c) void {
    if (vars.darkening_or_lightening_screen.* == 255) return;
    PaletteFilter_RestoreSubtractive(0x40, 0x100);
    vars.palette_filter_countdown.* +%= 1;
    if (vars.palette_filter_countdown.* == 0x20) {
        vars.darkening_or_lightening_screen.* = 255;
        wordPtr(vars.TS_copy).* = 0;
    }
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn PaletteFilter_RestoreBGAdditiveStrict() callconv(.c) void {
    PaletteFilter_RestoreAdditive(0x40, 0x100);
    vars.palette_filter_countdown.* +%= 1;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Trinexx_FlashShellPalette_Red() callconv(.c) void {
    if (vars.byte_7E04BE.* == 0) {
        var i: usize = 0;
        while (i < 7) : (i += 1) {
            const v = vars.main_palette_buffer[0x41 + i];
            const lo = (@as(u32, v & 0x1f) +% @intFromBool((v & 0x1f) != 0x1f));
            vars.main_palette_buffer[0x41 + i] = @truncate(@as(u32, v & 0xffe0) | lo);
        }
        vars.flag_update_cgram_in_nmi.* +%= 1;
        vars.byte_7E04C0.* +%= 1;
        if (vars.byte_7E04C0.* >= 12) {
            vars.byte_7E04C0.* = 0;
            vars.byte_7E04BE.* = 0;
            return;
        }
        vars.byte_7E04BE.* = 3;
    }
    vars.byte_7E04BE.* -%= 1;
}

pub export fn Trinexx_UnflashShellPalette_Red() callconv(.c) void {
    if (vars.byte_7E04BE.* == 0) {
        var i: usize = 0;
        while (i < 7) : (i += 1) {
            const u = vars.aux_palette_buffer[0x41 + i];
            const v = vars.main_palette_buffer[0x41 + i];
            const lo = (@as(u32, v & 0x1f) -% @intFromBool((v & 0x1f) != (u & 0x1f)));
            vars.main_palette_buffer[0x41 + i] = @truncate(@as(u32, v & 0xffe0) | lo);
        }
        vars.flag_update_cgram_in_nmi.* +%= 1;
        vars.byte_7E04C0.* +%= 1;
        if (vars.byte_7E04C0.* >= 12) {
            vars.byte_7E04C0.* = 0;
            vars.byte_7E04BE.* = 0;
            return;
        }
        vars.byte_7E04BE.* = 3;
    }
    vars.byte_7E04BE.* -%= 1;
}

pub export fn Trinexx_FlashShellPalette_Blue() callconv(.c) void {
    if (vars.byte_7E04BF.* == 0) {
        var i: usize = 0;
        while (i < 7) : (i += 1) {
            const v = vars.main_palette_buffer[0x41 + i];
            const hi = @as(u32, v & 0x7c00) +% (@as(u32, @intFromBool((v & 0x7c00) != 0x7c00)) << 10);
            vars.main_palette_buffer[0x41 + i] = @truncate(@as(u32, v & 0x83ff) | hi);
        }
        vars.flag_update_cgram_in_nmi.* +%= 1;
        vars.byte_7E04C1.* +%= 1;
        if (vars.byte_7E04C1.* >= 12) {
            vars.byte_7E04C1.* = 0;
            vars.byte_7E04BF.* = 0;
            return;
        }
        vars.byte_7E04BF.* = 3;
    }
    vars.byte_7E04BF.* -%= 1;
}

pub export fn Trinexx_UnflashShellPalette_Blue() callconv(.c) void {
    if (vars.byte_7E04BF.* == 0) {
        var i: usize = 0;
        while (i < 7) : (i += 1) {
            const u = vars.aux_palette_buffer[0x41 + i];
            const v = vars.main_palette_buffer[0x41 + i];
            const hi = @as(u32, v & 0x7c00) -% (@as(u32, @intFromBool((v & 0x7c00) != (u & 0x7c00))) << 10);
            vars.main_palette_buffer[0x41 + i] = @truncate(@as(u32, v & 0x83ff) | hi);
        }
        vars.flag_update_cgram_in_nmi.* +%= 1;
        vars.byte_7E04C1.* +%= 1;
        if (vars.byte_7E04C1.* >= 12) {
            vars.byte_7E04C1.* = 0;
            vars.byte_7E04BF.* = 0;
            return;
        }
        vars.byte_7E04BF.* = 3;
    }
    vars.byte_7E04BF.* -%= 1;
}

// ---------------------------------------------------------------------------
// Spotlight / HDMA windows
// ---------------------------------------------------------------------------

pub export fn IrisSpotlight_close() callconv(.c) void {
    SpotlightInternal(0x7e, 0);
}

pub export fn Spotlight_open() callconv(.c) void {
    SpotlightInternal(0, 2);
}

pub export fn SpotlightInternal(x: u8, y: u8) callconv(.c) void {
    vars.spotlight_var1.* = x;
    vars.spotlight_var2.* = y;

    // zelda_snes_dummy_write(HDMAEN, 0) is a no-op inline.
    rtl.HdmaSetup(0xF2FB, 0xF2FB, 0x41, @truncate(WH0), @truncate(WH0), 0);

    vars.W12SEL_copy.* = 0x33;
    vars.W34SEL_copy.* = 3;
    vars.WOBJSEL_copy.* = 0x33;
    vars.TMW_copy.* = vars.TM_copy.*;
    vars.TSW_copy.* = vars.TS_copy.*;
    if (vars.player_is_indoors.* == 0) {
        vars.COLDATA_copy0.* = 0x20;
        vars.COLDATA_copy1.* = 0x40;
        vars.COLDATA_copy2.* = 0x80;
    }
    IrisSpotlight_ConfigureTable();
    vars.HDMAEN_copy.* = 0x80;
    vars.INIDISP_copy.* = 0xf;
}

pub export fn IrisSpotlight_ConfigureTable() callconv(.c) void {
    const r14 = vars.link_y_coord.* -% vars.BG2VOFS_copy2.* +% 12;
    vars.spotlight_y_lower.* = r14 -% vars.spotlight_var1.*;
    vars.spotlight_y_upper.* = r14 +% vars.spotlight_var1.*;
    vars.spotlight_var3.* = vars.link_x_coord.* -% vars.BG2HOFS_copy2.* +% 8;
    vars.spotlight_var4.* = vars.spotlight_var1.*;
    var r6 = r14 *% 2;
    if (r6 < 224) r6 = 224;
    var r4 = r14 *% 2 -% r6;
    while (true) {
        var r8: u16 = 0xff;
        var wide: SpotlightWide = .{ .narrow = 0xff, .left = 255, .right = 0 };
        if (r6 < vars.spotlight_y_upper.*) {
            const t: u8 = @truncate(vars.spotlight_var4.*);
            if (vars.spotlight_var4.* != 0) vars.spotlight_var4.* -%= 1;
            r8 = IrisSpotlight_CalculateCircleValue(t);
            wide = spotlightWideValue(t, r8);
        }
        if (r4 < 240) {
            vars.hdma_table_dynamic[r4] = r8;
            g_spotlight_wide[r4] = wide;
        }
        if (r6 < 240) {
            vars.hdma_table_dynamic[r6] = r8;
            g_spotlight_wide[r6] = wide;
        }
        if (r4 == r14) break;
        r4 +%= 1;
        r6 -%= 1;
    }

    var i: usize = 224;
    while (i < 240) : (i += 1)
        vars.hdma_table_dynamic[i] = 0;

    @memcpy(vars.hdma_table_unused[0..224], vars.hdma_table_dynamic[0..224]);

    const sel = vars.spotlight_var2.* >> 1;
    vars.spotlight_var1.* +%= @bitCast(@as(i16, tables.kSpotlight_delta_size[sel]));

    if (vars.spotlight_var1.* != tables.kSpotlight_goal[sel]) return;

    if (vars.spotlight_var2.* == 0) {
        vars.INIDISP_copy.* = 0x80;
    } else {
        IrisSpotlight_ResetTable();
    }
    vars.subsubmodule_index.* = 0;
    vars.submodule_index.* = 0;

    if (vars.main_module_index.* == 7 or vars.main_module_index.* == 16) {
        if (vars.player_is_indoors.* == 0)
            vars.sound_effect_ambient.* = vars.overworld_music[loPtr(vars.overworld_screen_index).*] >> 4;
        if (vars.queued_music_control.* != 0xff)
            vars.music_control.* = vars.queued_music_control.*;
    }
    vars.main_module_index.* = vars.saved_module_for_menu.*;
    if (vars.main_module_index.* == 6)
        Sprite_ResetAll();
}

pub export fn IrisSpotlight_ResetTable() callconv(.c) void {
    var i: usize = 0;
    while (i < 240) : (i += 1) {
        vars.hdma_table_dynamic[i] = 0xff00;
        g_spotlight_wide[i] = .{ .narrow = 0xff00, .left = -1000, .right = 1000 };
    }
}

/// The circle's edges on one line without the byte clamp, next to the table
/// entry they were worked out with, for a widescreen screen: its margins are
/// past 0 and 255, and the circle can reach them. `narrow` is the table entry,
/// so a line the table's since been rewritten for (by the water, say) isn't
/// taken for the circle's.
pub const SpotlightWide = struct { narrow: u16, left: i16, right: i16 };
pub var g_spotlight_wide = [_]SpotlightWide{.{ .narrow = 0xff, .left = 255, .right = 0 }} ** 240;

/// The circle's half-width on one line, or null for a line it misses.
fn spotlightHalfWidth(a: u8) ?u16 {
    const t: u8 = @truncate(snes_divide(@as(u16, a) << 8, @truncate(vars.spotlight_var1.*)) >> 1);
    const r10 = tables.kConfigureSpotlightTable_Helper_Tab[t];
    if (r10 == 0) return null;
    const prod: u8 = @truncate((@as(u32, r10) * @as(u8, @truncate(vars.spotlight_var1.*))) >> 8);
    return 2 * @as(u16, prod);
}

fn spotlightWideValue(a: u8, narrow: u16) SpotlightWide {
    const p = spotlightHalfWidth(a) orelse return .{ .narrow = narrow, .left = 255, .right = 0 };
    const cx: i16 = @bitCast(vars.spotlight_var3.*);
    return .{ .narrow = narrow, .left = cx -| @as(i16, @intCast(p)), .right = cx +| @as(i16, @intCast(p)) };
}

pub export fn IrisSpotlight_CalculateCircleValue(a: u8) callconv(.c) u16 {
    const p = spotlightHalfWidth(a) orelse return 0xff;
    var r2 = vars.spotlight_var3.* +% p;
    var r0 = vars.spotlight_var3.* -% p;
    r0 = if (sign16(r0)) 0 else if (r0 < 255) r0 else 255;
    r2 = if (r2 < 255) r2 else 255;
    r0 |= r2 << 8;
    return if (r0 == 0xffff) 0xff else r0;
}

pub export fn AdjustWaterHDMAWindow() callconv(.c) void {
    const r10 = vars.water_hdma_var1.* -% vars.BG2VOFS_copy2.*;
    vars.spotlight_y_lower.* = r10 -% vars.water_hdma_var2.*;
    vars.spotlight_y_upper.* = r10 +% vars.water_hdma_var2.*;
    AdjustWaterHDMAWindow_X(r10);
}

pub export fn AdjustWaterHDMAWindow_X(r10: u16) callconv(.c) void {
    vars.spotlight_var3.* = vars.water_hdma_var0.* -% vars.BG2HOFS_copy2.*;
    var r12: u16 = if (vars.water_hdma_var3.* != 0) vars.water_hdma_var3.* -% 1 else 0;
    var r2 = vars.spotlight_var3.* +% r12;
    var r0 = vars.spotlight_var3.* -% r12;

    r0 = if (r0 < 255) r0 else 255;
    r2 = if (r2 < 255) r2 else 255;
    r12 = r0 | (r2 << 8);

    var r6 = r10 *% 2;
    if (r6 < 0xe0) r6 = 0xe0;
    var r4 = 2 *% r10 -% r6;
    var a: u16 = undefined;

    while (true) {
        if (!sign16(r4)) {
            if (!sign16(vars.spotlight_y_lower.*) and r4 < vars.spotlight_y_lower.*) {
                a = 0xff;
            } else {
                a = r12;
            }
            if (r4 < 240) vars.hdma_table_dynamic[r4] = if (a != 0xffff) a else 0xff;
        }
        if (r6 >= vars.spotlight_y_upper.*) {
            a = 0xff;
        } else {
            if (r6 >= 225 and vars.word_7E0678.* != 0) vars.word_7E0678.* -%= 1;
            a = r12;
        }
        if (r6 < 240) vars.hdma_table_dynamic[r6] = if (a != 0xffff) a else 0xff;

        r6 -%= 1;
        const old_r4 = r4;
        r4 +%= 1;
        if (r10 == old_r4) break;
    }
}

pub export fn FloodDam_PrepFloodHDMA() callconv(.c) void {
    vars.spotlight_y_lower.* = vars.water_hdma_var1.* -% vars.BG2VOFS_copy2.*;
    vars.spotlight_var3.* = vars.water_hdma_var0.* -% vars.BG2HOFS_copy2.*;
    const r14 = vars.water_hdma_var3.* ^ 1;
    // The first r12 is dead; the loop below recomputes it before any use.
    var r12: u16 = ((vars.spotlight_var3.* +% r14) << 8) | @as(u8, @truncate(vars.spotlight_var3.* -% r14));

    var r4: c_int = 0;
    while (true) {
        vars.hdma_table_dynamic[@intCast(r4)] = 0xff00;
        r4 += 1;
        if (r4 == vars.spotlight_y_upper.*) break;
    }

    r12 = r14 -% 7 +% 8;
    r12 = ((vars.spotlight_var3.* +% r12) << 8) | @as(u8, @truncate(vars.spotlight_var3.* -% r12));
    const r10 = (vars.spotlight_y_upper.* +% vars.water_hdma_var2.*) ^ 1;

    while (true) {
        if (r4 >= r10) {
            vars.hdma_table_dynamic[@intCast(r4)] = 0xff;
        } else {
            var a: u16 = @intCast(r4);
            while (true) {
                a *%= 2;
                if (a < 480) break;
            }
            vars.hdma_table_dynamic[a >> 1] = if (r12 == 0xffff) 0xff else r12;
        }
        r4 += 1;
        if (r4 >= 225) break;
    }
}

pub export fn ResetStarTileGraphics() callconv(.c) void {
    vars.byte_7E04BC.* = 0;
    Dungeon_RestoreStarTileChr();
}

pub export fn Dungeon_RestoreStarTileChr() callconv(.c) void {
    var xx: usize = 0;
    var yy: usize = 32;
    if (vars.byte_7E04BC.* != 0) {
        xx = 32;
        yy = 0;
    }
    const p: [*]u8 = @ptrCast(vars.messaging_buf);
    @memcpy(p[0..32], ram(0xbdc0 + xx)[0..32]);
    @memcpy((p + 32)[0..32], ram(0xbdc0 + yy)[0..32]);
    vars.nmi_subroutine_index.* = 0x18;
}

pub export fn LinkZap_HandleMosaic() callconv(.c) void {
    var level: c_int = vars.mosaic_level.*;
    if (vars.mosaic_inc_or_dec.* == 0) {
        level += 0x10;
        if (level == 0xc0) vars.mosaic_inc_or_dec.* = 1;
    } else {
        level -= 0x10;
        if (level == 0) vars.mosaic_inc_or_dec.* = 0;
    }
    vars.mosaic_level.* = @truncate(@as(u32, @bitCast(level)));
    vars.MOSAIC_copy.* = (vars.mosaic_level.* >> 1) | 3;
    vars.BGMODE_copy.* = 9;
}

pub export fn Player_SetCustomMosaicLevel(a: u8) callconv(.c) void {
    vars.mosaic_inc_or_dec.* = 0;
    vars.mosaic_level.* = a;
    vars.MOSAIC_copy.* = (vars.mosaic_level.* >> 1) | 3;
    vars.BGMODE_copy.* = 9;
}

pub export fn Module07_16_UpdatePegs_Step1() callconv(.c) void {
    if (loPtr(vars.orange_blue_barrier_state).* != 0) {
        Dungeon_UpdatePegGFXBuffer(0x80, 0x100);
    } else {
        Dungeon_UpdatePegGFXBuffer(0x100, 0x80);
    }
}

pub export fn Module07_16_UpdatePegs_Step2() callconv(.c) void {
    if (loPtr(vars.orange_blue_barrier_state).* != 0) {
        Dungeon_UpdatePegGFXBuffer(0x100, 0x80);
    } else {
        Dungeon_UpdatePegGFXBuffer(0x80, 0x100);
    }
}

pub export fn Dungeon_UpdatePegGFXBuffer(x: c_int, y: c_int) callconv(.c) void {
    const src: [*]align(1) const u16 = @ptrCast(ram(0xb340));
    var i: usize = 0;
    while (i < 64) : (i += 1)
        vars.messaging_buf[i] = src[@as(usize, @intCast(x >> 1)) + i];
    i = 0;
    while (i < 64) : (i += 1)
        vars.messaging_buf[64 + i] = src[@as(usize, @intCast(y >> 1)) + i];
    vars.nmi_subroutine_index.* = 23;
}

pub export fn Dungeon_HandleTranslucencyAndPalette() callconv(.c) void {
    if (vars.palette_swap_flag.* != 0)
        Palette_RevertTranslucencySwap();

    vars.CGWSEL_copy.* = 2;
    vars.CGADSUB_copy.* = 0xb3;

    var torch = vars.dung_num_lit_torches.*;
    if (vars.dung_want_lights_out.* == 0) {
        // The C writes `a` through a chain of comma expressions, so each
        // assignment only happens if the previous test short-circuited through.
        var a: u8 = 0x20;
        const props = vars.dung_hdr_bg2_properties.*;
        chain: {
            a = 0x20;
            if (props == 0) break :chain;
            a = 0x32;
            if (props == 7) break :chain;
            a = 0x62;
            if (props == 4) break :chain;
            a = 0x20;
            if (props != 2) break :chain;

            Palette_AssertTranslucencySwap();
            if (loPtr(vars.dungeon_room_index).* == 13) {
                vars.agahnim_pal_setting[0] = 0;
                vars.agahnim_pal_setting[1] = 0;
                vars.agahnim_pal_setting[2] = 0;
                vars.agahnim_pal_setting[3] = 0;
                vars.agahnim_pal_setting[4] = 0;
                vars.agahnim_pal_setting[5] = 0;
                Palette_LoadAgahnim();
            }
            a = 0x70;
        }
        vars.CGADSUB_copy.* = a;
        torch = 3;
    }
    vars.overworld_fixed_color_plusminus.* = rtl.kLitTorchesColorPlus[torch];
    vars.palette_filter_countdown.* = 31;
    vars.mosaic_target_level.* = 0;
    vars.darkening_or_lightening_screen.* = 2;
    vars.overworld_palette_aux_or_main.* = 0;
    Palette_Load_DungeonSet();
    Palette_Load_Sp0L();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
    vars.subsubmodule_index.* +%= 1;
}

// ---------------------------------------------------------------------------
// Palette loading
// ---------------------------------------------------------------------------

pub export fn Overworld_LoadAllPalettes() callconv(.c) void {
    @memset(vars.aux_palette_buffer[0x180 / 2 .. 0x180 / 2 + 64], 0);
    @memset(vars.main_palette_buffer[0..256], 0);

    vars.overworld_palette_mode.* = 5;
    vars.overworld_palette_aux1_bp2to4_hi.* = 3;
    vars.overworld_palette_aux2_bp5to7_hi.* = 3;
    vars.overworld_palette_aux3_bp7_lo.* = 0;
    vars.palette_sp6r_indoors.* = 5;
    vars.palette_sp0l.* = 11;
    vars.palette_swap_flag.* = 0;
    vars.overworld_palette_aux_or_main.* = 0;
    Palette_BgAndFixedColor_Black();
    Palette_Load_Sp0L();
    Palette_Load_SpriteMain();
    Palette_Load_OWBGMain();
    Palette_Load_OWBG1();
    Palette_Load_OWBG2();
    Palette_Load_OWBG3();
    Palette_Load_SpriteEnvironment_Dungeon();
    Palette_Load_HUD();

    var i: usize = 0;
    while (i < 8) : (i += 1)
        vars.main_palette_buffer[0x1b0 / 2 + i] = vars.aux_palette_buffer[0x1d0 / 2 + i];
}

pub export fn Dungeon_LoadPalettes() callconv(.c) void {
    vars.overworld_palette_aux_or_main.* = 0;
    Palette_BgAndFixedColor_Black();
    Palette_Load_Sp0L();
    Palette_Load_SpriteMain();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
    Palette_Load_Sword();
    Palette_Load_Shield();
    Palette_Load_SpriteEnvironment();
    Palette_Load_LinkArmorAndGloves();
    Palette_Load_HUD();
    Palette_Load_DungeonSet();
    Overworld_LoadPalettesInner();
}

pub export fn Overworld_LoadPalettesInner() callconv(.c) void {
    vars.overworld_pal_unk1.* = vars.palette_main_indoors.*;
    vars.overworld_pal_unk2.* = vars.overworld_palette_aux3_bp7_lo.*;
    vars.overworld_pal_unk3.* = vars.byte_7E0AB7.*;
    vars.darkening_or_lightening_screen.* = 2;
    vars.palette_filter_countdown.* = 0;
    wordPtr(vars.mosaic_target_level).* = 0;
    Overworld_CopyPalettesToCache();
}

pub export fn OverworldLoadScreensPaletteSet() callconv(.c) void {
    const sc: u8 = @truncate(vars.overworld_screen_index.* & 0x3f);
    var x: u8 = if (sc == 3 or sc == 5 or sc == 7) 2 else 0;
    x += @intFromBool(vars.overworld_screen_index.* & 0x40 != 0);
    Overworld_LoadAreaPalettesEx(x);
}

pub export fn Overworld_LoadAreaPalettesEx(x: u8) callconv(.c) void {
    vars.overworld_palette_mode.* = x;
    vars.overworld_palette_aux_or_main.* &= 0xff;
    Palette_Load_SpriteMain();
    Palette_Load_SpriteEnvironment();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
    Palette_Load_Sword();
    Palette_Load_Shield();
    Palette_Load_LinkArmorAndGloves();
    vars.palette_sp0l.* = if (vars.savegame_is_darkworld.* & 0x40 != 0) 3 else 1;
    Palette_Load_Sp0L();
    Palette_Load_HUD();
    Palette_Load_OWBGMain();
}

pub export fn SpecialOverworld_CopyPalettesToCache() callconv(.c) void {
    var i: usize = 32;
    while (i < 32 * 8) : (i += 1)
        vars.main_palette_buffer[i] = 0;
    i = 0;
    while (i < 8) : (i += 1) {
        vars.main_palette_buffer[i] = vars.aux_palette_buffer[i];
        vars.main_palette_buffer[i + 0x8] = vars.aux_palette_buffer[i + 0x8];
        vars.main_palette_buffer[i + 0x10] = vars.aux_palette_buffer[i + 0x10];
        vars.main_palette_buffer[i + 0x18] = vars.aux_palette_buffer[i + 0x18];
        vars.main_palette_buffer[i + 0xd8] = vars.aux_palette_buffer[i + 0xd8];
        vars.main_palette_buffer[i + 0xe8] = vars.aux_palette_buffer[i + 0xe8];
        vars.main_palette_buffer[i + 0xf0] = vars.aux_palette_buffer[i + 0xf0];
        vars.main_palette_buffer[i + 0xf8] = vars.aux_palette_buffer[i + 0xf8];
    }
    vars.MOSAIC_copy.* = 0xf7;
    vars.mosaic_level.* = 0xf7;
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Overworld_CopyPalettesToCache() callconv(.c) void {
    @memcpy(vars.main_palette_buffer[0..256], vars.aux_palette_buffer[0..256]);
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Overworld_LoadPalettes(bg: u8, spr: u8) callconv(.c) void {
    vars.overworld_palette_aux_or_main.* = 0;

    const d = tables.kOwBgPalInfo[@as(usize, bg) * 3 ..];
    if (d[0] >= 0) vars.overworld_palette_aux1_bp2to4_hi.* = @intCast(d[0]);
    if (d[1] >= 0) vars.overworld_palette_aux2_bp5to7_hi.* = @intCast(d[1]);
    if (d[2] >= 0) vars.overworld_palette_aux3_bp7_lo.* = @intCast(d[2]);

    const e = tables.kOwSprPalInfo[@as(usize, spr) * 2 ..];
    if (e[0] >= 0) vars.palette_sp5l.* = @intCast(e[0]);
    if (e[1] >= 0) vars.palette_sp6l.* = @intCast(e[1]);
    Palette_Load_OWBG1();
    Palette_Load_OWBG2();
    Palette_Load_OWBG3();
    Palette_Load_Sp5L();
    Palette_Load_Sp6L();
}

pub export fn Palette_BgAndFixedColor_Black() callconv(.c) void {
    Palette_SetBgAndFixedColor(0);
}

pub export fn Palette_SetBgAndFixedColor(color: u16) callconv(.c) void {
    vars.main_palette_buffer[0] = color;
    vars.main_palette_buffer[32] = color;
    vars.aux_palette_buffer[0] = color;
    vars.aux_palette_buffer[32] = color;
    SetBackdropcolorBlack();
}

pub export fn SetBackdropcolorBlack() callconv(.c) void {
    vars.COLDATA_copy0.* = 0x20;
    vars.COLDATA_copy1.* = 0x40;
    vars.COLDATA_copy2.* = 0x80;
}

pub export fn Palette_SetOwBgColor() callconv(.c) void {
    Palette_SetBgAndFixedColor(Palette_GetOwBgColor());
}

pub export fn Palette_SpecialOw() callconv(.c) void {
    const c = Palette_GetOwBgColor();
    vars.aux_palette_buffer[0] = c;
    vars.aux_palette_buffer[32] = c;
    SetBackdropcolorBlack();
}

pub export fn Palette_GetOwBgColor() callconv(.c) u16 {
    if (vars.overworld_screen_index.* < 0x80)
        return if (vars.overworld_screen_index.* & 0x40 != 0) 0x2A32 else 0x2669;
    const r = vars.dungeon_room_index.*;
    if (r == 0x180 or r == 0x182 or r == 0x183)
        return 0x19C6;
    return 0x2669;
}

pub export fn Palette_AssertTranslucencySwap() callconv(.c) void {
    Palette_SetTranslucencySwap(true);
}

pub export fn Palette_SetTranslucencySwap(v: bool) callconv(.c) void {
    vars.palette_swap_flag.* = @intFromBool(v);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        var a = vars.aux_palette_buffer[i + 0x80];
        var b = vars.aux_palette_buffer[i + 0xf0];
        vars.aux_palette_buffer[i + 0xf0] = a;
        vars.main_palette_buffer[i + 0xf0] = a;
        vars.aux_palette_buffer[i + 0x80] = b;
        vars.main_palette_buffer[i + 0x80] = b;

        a = vars.aux_palette_buffer[i + 0x88];
        b = vars.aux_palette_buffer[i + 0xf8];
        vars.aux_palette_buffer[i + 0xf8] = a;
        vars.main_palette_buffer[i + 0xf8] = a;
        vars.aux_palette_buffer[i + 0x88] = b;
        vars.main_palette_buffer[i + 0x88] = b;

        a = vars.aux_palette_buffer[i + 0xb8];
        b = vars.aux_palette_buffer[i + 0xd8];
        vars.aux_palette_buffer[i + 0xd8] = a;
        vars.main_palette_buffer[i + 0xd8] = a;
        vars.aux_palette_buffer[i + 0xb8] = b;
        vars.main_palette_buffer[i + 0xb8] = b;
    }
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Palette_RevertTranslucencySwap() callconv(.c) void {
    Palette_SetTranslucencySwap(false);
}

pub export fn LoadActualGearPalettes() callconv(.c) void {
    LoadGearPalettes(vars.link_sword_type.*, vars.link_shield_type.*, vars.link_armor.*);
    if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
        Palette_UpdateGlovesColor();
}

pub export fn Palette_ElectroThemedGear() callconv(.c) void {
    LoadGearPalettes(2, 2, 4);
}

pub export fn LoadGearPalettes_bunny() callconv(.c) void {
    LoadGearPalettes(vars.link_sword_type.*, vars.link_shield_type.*, 3);
}

pub export fn LoadGearPalettes(sword: u8, shield: u8, armor: u8) callconv(.c) void {
    var src = kPalette_Sword() + @as(usize, if (sword != 0 and sword != 255) sword - 1 else 0) * 3;
    Palette_LoadMultiple_Arbitrary(src, 0x1b2, 2);

    src = kPalette_Shield() + @as(usize, if (shield != 0) shield - 1 else 0) * 4;
    Palette_LoadMultiple_Arbitrary(src, 0x1b8, 3);

    src = kPalette_ArmorAndGloves() + @as(usize, armor) * 15;
    Palette_LoadMultiple_Arbitrary(src, 0x1e2, 14);
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn LoadGearPalette(dst: c_int, src: [*]align(1) const u16, n: c_int) callconv(.c) void {
    const d: usize = @intCast(dst >> 1);
    const cnt: usize = @intCast(n);
    @memcpy(vars.aux_palette_buffer[d .. d + cnt], src[0..cnt]);
    @memcpy(vars.main_palette_buffer[d .. d + cnt], src[0..cnt]);
}

pub export fn Filter_Majorly_Whiten_Bg() callconv(.c) void {
    var i: usize = 32;
    while (i < 128) : (i += 1)
        vars.main_palette_buffer[i] = Filter_Majorly_Whiten_Color(vars.aux_palette_buffer[i]);
    vars.main_palette_buffer[0] = if (vars.aux_palette_buffer[0] != 0) vars.main_palette_buffer[32] else 0;
}

pub export fn Filter_Majorly_Whiten_Color(c: u16) callconv(.c) u16 {
    const amt: u32 = if (features.enhanced_features0.* & features.kFeatures0_DimFlashes != 0) 3 else 14;
    var r: u32 = (c & 0x1f) + amt;
    var g: u32 = (c & 0x3e0) + (amt << 5);
    var b: u32 = (c & 0x7c00) + (amt << 10);
    if (r > 0x1f) r = 0x1f;
    if (g > 0x3e0) g = 0x3e0;
    if (b > 0x7c00) b = 0x7c00;
    return @truncate(r | g | b);
}

pub export fn Palette_Restore_BG_From_Flash() callconv(.c) void {
    var i: usize = 32;
    while (i < 128) : (i += 1)
        vars.main_palette_buffer[i] = vars.aux_palette_buffer[i];
    vars.main_palette_buffer[0] = vars.main_palette_buffer[32];
    Palette_Restore_Coldata();
}

pub export fn Palette_Restore_Coldata() callconv(.c) void {
    if (vars.player_is_indoors.* == 0) {
        const rgb: u32 = switch (loPtr(vars.overworld_screen_index).*) {
            3, 5, 7 => 0x8c4c26,
            0x43, 0x45, 0x47 => 0x874a26,
            0x5b => 0x894f33,
            else => 0x804020,
        };
        vars.COLDATA_copy0.* = @truncate(rgb);
        vars.COLDATA_copy1.* = @truncate(rgb >> 8);
        vars.COLDATA_copy2.* = @truncate(rgb >> 16);
    }
}

pub export fn Palette_Restore_BG_And_HUD() callconv(.c) void {
    @memcpy(vars.main_palette_buffer[0..128], vars.aux_palette_buffer[0..128]);
    vars.flag_update_cgram_in_nmi.* +%= 1;
    Palette_Restore_Coldata();
}

pub export fn Palette_Load_Sp0L() callconv(.c) void {
    const src = kPalette_SpriteAux3() + @as(usize, vars.palette_sp0l.*) * 7;
    Palette_LoadSingle(src, if (vars.palette_swap_flag.* != 0) kPal_sp7l else kPal_sp0l, 6);
}

pub export fn Palette_Load_SpriteMain() callconv(.c) void {
    const src = kPalette_MainSpr() + @as(usize, if (vars.overworld_screen_index.* & 0x40 != 0) 60 else 0);
    Palette_LoadMultiple(src, kPal_sp1to4, 14, 3);
}

pub export fn Palette_Load_Sp5L() callconv(.c) void {
    const src = kPalette_SpriteAux1() + @as(usize, vars.palette_sp5l.*) * 7;
    Palette_LoadSingle(src, kPal_sp5l, 6);
}

pub export fn Palette_Load_Sp6L() callconv(.c) void {
    const src = kPalette_SpriteAux1() + @as(usize, vars.palette_sp6l.*) * 7;
    Palette_LoadSingle(src, kPal_sp6l, 6);
}

pub export fn Palette_Load_Sword() callconv(.c) void {
    // wtf: zelda reads offset 0xff
    const st = vars.link_sword_type.*;
    const idx: usize = if (@as(i8, @bitCast(st)) > 0) st - 1 else 0;
    const src = kPalette_Sword() + idx * 3;
    Palette_LoadMultiple_Arbitrary(src, kPal_Sword, 2);
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Palette_Load_Shield() callconv(.c) void {
    const st = vars.link_shield_type.*;
    const src = kPalette_Shield() + @as(usize, if (st != 0) st - 1 else 0) * 4;
    Palette_LoadMultiple_Arbitrary(src, kPal_Shield, 3);
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Palette_Load_SpriteEnvironment() callconv(.c) void {
    if (vars.player_is_indoors.* != 0) {
        Palette_Load_SpriteEnvironment_Dungeon();
    } else {
        Palette_MiscSprite_Outdoors();
    }
}

pub export fn Palette_Load_SpriteEnvironment_Dungeon() callconv(.c) void {
    const src = kPalette_MiscSprite() + @as(usize, vars.palette_sp6r_indoors.*) * 7;
    Palette_LoadSingle(src, kPal_sp6r, 6);
}

pub export fn Palette_MiscSprite_Outdoors() callconv(.c) void {
    const t: usize = if (vars.overworld_screen_index.* & 0x40 != 0) 9 else 7;
    const src = kPalette_MiscSprite() + t * 7;
    Palette_LoadSingle(src, if (vars.palette_swap_flag.* != 0) kPal_sp7r else kPal_sp0r, 6);
    Palette_LoadSingle(src - 7, kPal_sp6r, 6);
}

pub export fn Palette_Load_DungeonMapSprite() callconv(.c) void {
    Palette_LoadMultiple(kPalette_PalaceMapSpr(), kPal_PalaceMap, 6, 2);
}

pub export fn Palette_Load_LinkArmorAndGloves() callconv(.c) void {
    const src = kPalette_ArmorAndGloves() + @as(usize, vars.link_armor.*) * 15;
    Palette_LoadMultiple_Arbitrary(src, kPal_ArmorGloves, 14);
    Palette_UpdateGlovesColor();
}

pub export fn Palette_UpdateGlovesColor() callconv(.c) void {
    if (vars.link_item_gloves.* != 0) {
        const c = kGlovesColor[vars.link_item_gloves.* - 1];
        vars.aux_palette_buffer[0xfd] = c;
        vars.main_palette_buffer[0xfd] = c;
    }
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn Palette_Load_DungeonMapBG() callconv(.c) void {
    Palette_LoadMultiple(kPalette_PalaceMapBg(), 0x40, 15, 5);
}

pub export fn Palette_Load_HUD() callconv(.c) void {
    const src = kHudPalData() + @as(usize, vars.hud_palette.*) * 32;
    Palette_LoadMultiple(src, 0x0, 15, 1);
}

pub export fn Palette_Load_DungeonSet() callconv(.c) void {
    const src = kPalette_DungBgMain() + @as(usize, vars.palette_main_indoors.* >> 1) * 90;
    Palette_LoadMultiple(src, 0x42, 14, 5);
    Palette_LoadSingle(src, if (vars.palette_swap_flag.* != 0) kPal_sp7r else kPal_sp0r, 6);
}

pub export fn Palette_Load_OWBG3() callconv(.c) void {
    const src = kPalette_OverworldBgAux3() + @as(usize, vars.overworld_palette_aux3_bp7_lo.*) * 7;
    Palette_LoadSingle(src, 0xE2, 6);
}

pub export fn Palette_Load_OWBGMain() callconv(.c) void {
    const src = kPalette_OverworldBgMain() + @as(usize, vars.overworld_palette_mode.*) * 35;
    Palette_LoadMultiple(src, 0x42, 6, 4);
}

pub export fn Palette_Load_OWBG1() callconv(.c) void {
    const src = kPalette_OverworldBgAux12() + @as(usize, vars.overworld_palette_aux1_bp2to4_hi.*) * 21;
    Palette_LoadMultiple(src, 0x52, 6, 2);
}

pub export fn Palette_Load_OWBG2() callconv(.c) void {
    const src = kPalette_OverworldBgAux12() + @as(usize, vars.overworld_palette_aux2_bp5to7_hi.*) * 21;
    Palette_LoadMultiple(src, 0xB2, 6, 2);
}

pub export fn Palette_LoadSingle(src: [*]align(1) const u16, dst: c_int, x_ents: c_int) callconv(.c) void {
    const d: usize = @intCast((dst + @as(c_int, vars.overworld_palette_aux_or_main.*)) >> 1);
    const n: usize = @intCast(x_ents + 1);
    @memcpy(vars.aux_palette_buffer[d .. d + n], src[0..n]);
}

pub export fn Palette_LoadMultiple(src_in: [*]align(1) const u16, dst_in: c_int, x_ents_in: c_int, y_pals_in: c_int) callconv(.c) void {
    var src = src_in;
    var dst = dst_in;
    var y_pals = y_pals_in;
    const x_ents: usize = @intCast(x_ents_in + 1);
    while (true) {
        const d: usize = @intCast((dst + @as(c_int, vars.overworld_palette_aux_or_main.*)) >> 1);
        @memcpy(vars.aux_palette_buffer[d .. d + x_ents], src[0..x_ents]);
        src += x_ents;
        dst += 32;
        y_pals -= 1;
        if (!(y_pals >= 0)) break;
    }
}

pub export fn Palette_LoadMultiple_Arbitrary(src: [*]align(1) const u16, dst: c_int, x_ents: c_int) callconv(.c) void {
    const d: usize = @intCast(dst >> 1);
    const n: usize = @intCast(x_ents + 1);
    @memcpy(vars.aux_palette_buffer[d .. d + n], src[0..n]);
    @memcpy(vars.main_palette_buffer[d .. d + n], src[0..n]);
}

pub export fn Palette_LoadForFileSelect() callconv(.c) void {
    var src = g_zenv.sram.?;
    var i: c_int = 0;
    while (i < 3) : (i += 1) {
        Palette_LoadForFileSelect_Armor(i * 0x20, src[kSrmOffs_Armor], src[kSrmOffs_Gloves]);
        Palette_LoadForFileSelect_Sword(i * 0x20, src[kSrmOffs_Sword]);
        Palette_LoadForFileSelect_Shield(i * 0x20, src[kSrmOffs_Shield]);
        src += 0x500;
    }
    var j: usize = 0;
    while (j < 7) : (j += 1) {
        vars.aux_palette_buffer[0xe8 + j] = kPalette_MainSpr()[7 + j];
        vars.main_palette_buffer[0xe8 + j] = kPalette_MainSpr()[7 + j];
        vars.aux_palette_buffer[0xf8 + j] = kPalette_MainSpr()[15 + 7 + j];
        vars.main_palette_buffer[0xf8 + j] = kPalette_MainSpr()[15 + 7 + j];
    }
}

pub export fn Palette_LoadForFileSelect_Armor(k: c_int, armor: u8, gloves: u8) callconv(.c) void {
    const pal = kPalette_ArmorAndGloves() + @as(usize, armor) * 15;
    const base: usize = @intCast(k);
    var i: usize = 0;
    while (i != 15) : (i += 1) {
        vars.aux_palette_buffer[base + 0x81 + i] = pal[i];
        vars.main_palette_buffer[base + 0x81 + i] = pal[i];
    }
    if (gloves != 0) {
        const c = kGlovesColor[gloves - 1];
        vars.aux_palette_buffer[base + 0x8d] = c;
        vars.main_palette_buffer[base + 0x8d] = c;
    }
}

pub export fn Palette_LoadForFileSelect_Sword(k: c_int, sword: u8) callconv(.c) void {
    const src = kPalette_Sword() + @as(usize, if (sword != 0) sword - 1 else 0) * 3;
    const base: usize = @intCast(k);
    var i: usize = 0;
    while (i != 3) : (i += 1) {
        vars.aux_palette_buffer[base + 0x99 + i] = src[i];
        vars.main_palette_buffer[base + 0x99 + i] = src[i];
    }
}

pub export fn Palette_LoadForFileSelect_Shield(k: c_int, shield: u8) callconv(.c) void {
    const src = kPalette_Shield() + @as(usize, if (shield != 0) shield - 1 else 0) * 4;
    const base: usize = @intCast(k);
    var i: usize = 0;
    while (i != 4) : (i += 1) {
        vars.aux_palette_buffer[base + 0x9c + i] = src[i];
        vars.main_palette_buffer[base + 0x9c + i] = src[i];
    }
}

pub export fn Palette_LoadAgahnim() callconv(.c) void {
    var src = kPalette_SpriteAux1() + 14 * 7;
    Palette_LoadMultiple_Arbitrary(src, 0x162, 6);
    Palette_LoadMultiple_Arbitrary(src, 0x182, 6);
    Palette_LoadMultiple_Arbitrary(src, 0x1a2, 6);
    src = kPalette_SpriteAux1() + 21 * 7;
    Palette_LoadMultiple_Arbitrary(src, 0x1c2, 6);
    vars.flag_update_cgram_in_nmi.* +%= 1;
}

pub export fn HandleScreenFlash() callconv(.c) void {
    const j = vars.intro_times_pal_flash.*;
    if (j == 0 or vars.submodule_index.* != 0) return;
    vars.intro_times_pal_flash.* -%= 1;
    if (vars.intro_times_pal_flash.* == 0) {
        Palette_Restore_BG_And_HUD();
        return;
    }

    if (j & 1 != 0) {
        Filter_Majorly_Whiten_Bg();
    } else {
        Palette_Restore_BG_From_Flash();
    }

    vars.flag_update_cgram_in_nmi.* +%= 1;
}

// ---------------------------------------------------------------------------

const testing = std.testing;

test "snes_divide returns 0xffff on a zero divisor" {
    try testing.expectEqual(@as(u16, 0x100), snes_divide(0x200, 2));
    try testing.expectEqual(@as(u16, 0xffff), snes_divide(0x200, 0));
    // Integer division truncates toward zero.
    try testing.expectEqual(@as(u16, 3), snes_divide(7, 2));
}

test "Decompress handles each of the five command forms" {
    const src = [_]u8{
        0x02, 'A',  'B',  'C', // literal run of 3
        0x21, 0x55, // fill 2 with 0x55
        0x41, 0x10, 0x20, // alternating lo/hi, 2 bytes
        0x61, 0x07, // incrementing run of 2
        0x81, 0x00, 0x00, // copy 2 from output offset 0
        0xff,
    };
    var dst: [32]u8 = @splat(0);
    const n = Decompress(&dst, &src);
    try testing.expectEqual(@as(c_int, 11), n);
    try testing.expectEqualSlices(u8, &.{ 'A', 'B', 'C', 0x55, 0x55, 0x10, 0x20, 0x07, 0x08, 'A', 'B' }, dst[0..11]);
}

test "Decompress reads the long-length form" {
    // 0xe0 | 0: cmd becomes (0xe0 << 3) & 0xe0 == 0, so a literal run whose
    // length comes from the following byte plus one.
    const src = [_]u8{ 0xe0, 0x03, 1, 2, 3, 4, 0xff };
    var dst: [16]u8 = @splat(0);
    try testing.expectEqual(@as(c_int, 4), Decompress(&dst, &src));
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, dst[0..4]);
}

test "Filter_Majorly_Whiten_Color brightens all three channels and clamps each" {
    features.enhanced_features0.* = 0;
    // amt is added to red, green and blue alike -- that is what makes this a
    // whitening filter. With amt = 14, red saturates at 0x1f while green
    // (14 << 5) and blue (14 << 10) still have headroom.
    try testing.expectEqual(@as(u16, 0x39df), Filter_Majorly_Whiten_Color(0x1f));
    try testing.expectEqual(@as(u16, 0x39ce), Filter_Majorly_Whiten_Color(0));
    // Every channel already at max stays at max.
    try testing.expectEqual(@as(u16, 0x7fff), Filter_Majorly_Whiten_Color(0x7fff));

    // The dim-flashes feature drops the step from 14 to 3.
    features.enhanced_features0.* = features.kFeatures0_DimFlashes;
    try testing.expectEqual(@as(u16, 0x0c63), Filter_Majorly_Whiten_Color(0));
    features.enhanced_features0.* = 0;
}

test "Palette_GetOwBgColor distinguishes light world, dark world and the room cases" {
    vars.overworld_screen_index.* = 0x10;
    try testing.expectEqual(@as(u16, 0x2669), Palette_GetOwBgColor());
    vars.overworld_screen_index.* = 0x50; // dark world bit
    try testing.expectEqual(@as(u16, 0x2A32), Palette_GetOwBgColor());

    vars.overworld_screen_index.* = 0x80; // not < 0x80, so the room index decides
    vars.dungeon_room_index.* = 0x182;
    try testing.expectEqual(@as(u16, 0x19C6), Palette_GetOwBgColor());
    vars.dungeon_room_index.* = 0x181;
    try testing.expectEqual(@as(u16, 0x2669), Palette_GetOwBgColor());
}

test "Do3To4Low16Bit splits a 24-byte tile into two bitplane pairs" {
    var src: [24]u8 = undefined;
    for (&src, 0..) |*b, i| b.* = @intCast(i + 1);
    var dst: [32]u8 = @splat(0xaa);
    Do3To4Low16Bit(&dst, &src, 1);
    // First 16 bytes are the low two planes copied verbatim.
    try testing.expectEqualSlices(u8, src[0..16], dst[0..16]);
    // The third plane lands in the even bytes of the second half, zero between.
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        try testing.expectEqual(src[16 + i], dst[16 + i * 2]);
        try testing.expectEqual(@as(u8, 0), dst[16 + i * 2 + 1]);
    }
}

test "IrisSpotlight_CalculateCircleValue clamps the window to a byte each side" {
    vars.spotlight_var1.* = 0x40;
    vars.spotlight_var3.* = 0x80;
    // a == spotlight_var1 puts the divide at 0x100, so the table index is 0x80,
    // the last entry, which is zero -- a fully closed row.
    try testing.expectEqual(@as(u16, 0xff), IrisSpotlight_CalculateCircleValue(0x40));
    // At the center the table is 0xff, giving the widest span.
    const mid = IrisSpotlight_CalculateCircleValue(0);
    try testing.expect(mid != 0xff);
    try testing.expect(mid & 0xff <= 255 and mid >> 8 <= 255);
}

test "the signed overworld palette tables keep their negative sentinels" {
    // -1 means 'leave this palette slot alone', so the sign must survive the
    // table generator; a u8 table would turn these into 255.
    try testing.expectEqual(@as(i8, -1), tables.kOwBgPalInfo[1]);
    try testing.expectEqual(@as(i8, -1), tables.kOwSprPalInfo[0]);
    try testing.expectEqual(@as(i8, -7), tables.kSpotlight_delta_size[0]);
    try testing.expectEqual(@as(i8, -1), tables.kGraphicsLoadSp6[1]);
    try testing.expectEqual(93, tables.kOwBgPalInfo.len);
    try testing.expectEqual(40, tables.kOwSprPalInfo.len);
}

test "the tileset tables have the shapes load_gfx indexes them with" {
    try testing.expectEqual(37, tables.kMainTilesets.len);
    try testing.expectEqual(8, tables.kMainTilesets[0].len);
    try testing.expectEqual(144, tables.kSpriteTilesets.len);
    try testing.expectEqual(4, tables.kSpriteTilesets[0].len);
    try testing.expectEqual(82, tables.kAuxTilesets.len);
    try testing.expectEqual(4, tables.kAuxTilesets[0].len);
    try testing.expectEqual(64, tables.kPaletteFilteringBits.len);
    try testing.expectEqual(129, tables.kConfigureSpotlightTable_Helper_Tab.len);
    // The helper table runs from fully open to fully closed.
    try testing.expectEqual(@as(u8, 0xff), tables.kConfigureSpotlightTable_Helper_Tab[0]);
    try testing.expectEqual(@as(u8, 0), tables.kConfigureSpotlightTable_Helper_Tab[128]);
}
