//! Building assets out of the ROM.
//!
//! The Zig side of assets/compile_resources.py. Each builder produces one
//! entry for zelda3_assets.dat; the tests check them against a .dat the
//! Python tool produced, which is the only real measure of a faithful port.

const std = @import("std");
const rom_mod = @import("rom.zig");
const pack = @import("asset_pack.zig");
const tables = @import("asset_tables.zig");

const Rom = rom_mod.Rom;

/// Concatenates arrays with a lookup table in front, matching pack_arrays.
///
/// The layout is the end offset of every array but the last, then the array
/// bodies, then a trailing count. Small enough sets use 16 bit offsets; wider
/// ones switch to 32 bit and flag it by setting 8192 in the trailing count,
/// which is how the game's FindInAssetArray tells the two apart.
pub fn packArrays(alloc: std.mem.Allocator, arrays: []const []const u8) ![]u8 {
    if (arrays.len == 0) return alloc.alloc(u8, 0);

    var total: usize = 0;
    for (arrays[0 .. arrays.len - 1]) |a| total += a.len;

    const wide = total >= 65536 or arrays.len > 8192;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    var offs: usize = 0;
    for (arrays[0 .. arrays.len - 1]) |a| {
        offs += a.len;
        if (wide) {
            try out.appendSlice(alloc, std.mem.asBytes(&@as(u32, @intCast(offs))));
        } else {
            try out.appendSlice(alloc, std.mem.asBytes(&@as(u16, @intCast(offs))));
        }
    }
    for (arrays) |a| try out.appendSlice(alloc, a);

    const tail: u16 = @intCast((if (wide) @as(usize, 8192) else 0) + arrays.len - 1);
    try out.appendSlice(alloc, std.mem.asBytes(&tail));

    return out.toOwnedSlice(alloc);
}

/// Frees a list of owned slices and the list itself.
fn freeAll(alloc: std.mem.Allocator, arrays: [][]u8) void {
    for (arrays) |a| alloc.free(a);
    alloc.free(arrays);
}

/// Sprite and background graphics are copied out still compressed - the game
/// decompresses them itself at load time. The decompressor runs here only to
/// measure how many bytes each block occupies, since the tables record where
/// blocks start but not how long they are.
fn compressedBlocks(alloc: std.mem.Allocator, rom: Rom, ptrs: []const u32, fixed_count: usize) ![][]u8 {
    const out = try alloc.alloc([]u8, ptrs.len);
    var done: usize = 0;
    errdefer {
        for (out[0..done]) |a| alloc.free(a);
        alloc.free(out);
    }

    for (ptrs, 0..) |addr, i| {
        if (i < fixed_count) {
            // The first blocks are stored raw at a fixed size.
            out[i] = try rom.getBytes(alloc, addr, 0x600);
        } else {
            const d = try rom_mod.decomp(alloc, rom, addr, false);
            defer alloc.free(d.data);
            out[i] = try rom.getBytes(alloc, addr, d.comp_len);
        }
        done += 1;
    }
    return out;
}

pub fn buildSprGfx(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    const blocks = try compressedBlocks(alloc, rom, &tables.kCompSpritePtrs, 12);
    defer freeAll(alloc, blocks);
    return packArrays(alloc, blocks);
}

pub fn buildBgGfx(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    const blocks = try compressedBlocks(alloc, rom, &tables.kCompBgPtrs, 0);
    defer freeAll(alloc, blocks);
    return packArrays(alloc, blocks);
}

const testing = std.testing;
const fileio = @import("fileio.zig");

test "packArrays uses narrow offsets for small sets" {
    const alloc = testing.allocator;
    const arrays = [_][]const u8{ &.{ 1, 2 }, &.{3}, &.{ 4, 5, 6 } };
    const got = try packArrays(alloc, &arrays);
    defer alloc.free(got);

    // Two 16 bit offsets, six body bytes, then the count.
    try testing.expectEqualSlices(u8, &.{ 2, 0, 3, 0, 1, 2, 3, 4, 5, 6, 2, 0 }, got);
}

test "packArrays of nothing is empty" {
    const alloc = testing.allocator;
    const got = try packArrays(alloc, &.{});
    defer alloc.free(got);
    try testing.expectEqual(@as(usize, 0), got.len);
}

test "packArrays switches to wide offsets past 64k" {
    const alloc = testing.allocator;
    const big = try alloc.alloc(u8, 70000);
    defer alloc.free(big);
    @memset(big, 0xab);

    const arrays = [_][]const u8{ big, &.{7} };
    const got = try packArrays(alloc, &arrays);
    defer alloc.free(got);

    try testing.expectEqualSlices(u8, &.{ 0x70, 0x11, 1, 0 }, got[0..4]); // 70000 as u32
    const tail = std.mem.bytesToValue(u16, got[got.len - 2 ..][0..2]);
    try testing.expectEqual(@as(u16, 8192 + 1), tail);
}

/// Opens the ROM and a reference .dat. Neither is in the repository, so these
/// tests only run on a machine set up to build assets.
const Fixture = struct {
    rom: Rom,
    dat: []u8,
    contents: pack.Contents,

    fn open() !Fixture {
        if (!fileio.exists("zelda3.sfc") or !fileio.exists("zig-out/bin/zelda3_assets.dat"))
            return error.SkipZigTest;
        var rom = try Rom.load(testing.allocator, "zelda3.sfc");
        errdefer rom.deinit();
        const dat = try fileio.readWholeFile(testing.allocator, "zig-out/bin/zelda3_assets.dat");
        errdefer testing.allocator.free(dat);
        const contents = try pack.read(testing.allocator, dat);
        return .{ .rom = rom, .dat = dat, .contents = contents };
    }

    fn close(self: *Fixture) void {
        self.contents.deinit(testing.allocator);
        testing.allocator.free(self.dat);
        self.rom.deinit();
    }
};

test "kSprGfx matches the reference asset file" {
    var f = try Fixture.open();
    defer f.close();

    const got = try buildSprGfx(testing.allocator, f.rom);
    defer testing.allocator.free(got);

    const want = f.contents.find("kSprGfx").?;
    try testing.expectEqual(want.len, got.len);
    try testing.expectEqualSlices(u8, want, got);
}

test "kBgGfx matches the reference asset file" {
    var f = try Fixture.open();
    defer f.close();

    const got = try buildBgGfx(testing.allocator, f.rom);
    defer testing.allocator.free(got);

    const want = f.contents.find("kBgGfx").?;
    try testing.expectEqual(want.len, got.len);
    try testing.expectEqualSlices(u8, want, got);
}
