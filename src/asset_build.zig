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

/// An asset that is a straight copy of a ROM region.
///
/// Most of compile_resources' print_misc is this: a name, an address someone
/// found by hand, and a count. `words` picks between reading bytes and
/// reading 16 bit words, which differ near a bank boundary because each steps
/// the address a different amount before checking for the wrap.
pub const MiscAsset = struct {
    name: []const u8,
    kind: pack.Kind,
    addr: u32,
    count: usize,
    words: bool = false,
};

pub const kMiscAssets = [_]MiscAsset{
    .{ .name = "kOverworldMapGfx", .kind = .uint8, .addr = 0x18c000, .count = 0x4000 },
    .{ .name = "kLightOverworldTilemap", .kind = .uint8, .addr = 0x00ac727, .count = 4096 },
    .{ .name = "kDarkOverworldTilemap", .kind = .uint8, .addr = 0x00ad727, .count = 1024 },

    .{ .name = "kPredefinedTileData", .kind = .uint16, .addr = 0x009b52, .count = 6438, .words = true },
    .{ .name = "kMap16ToMap8", .kind = .uint16, .addr = 0x8f8000, .count = 3752 * 4, .words = true },

    .{ .name = "kGeneratedWishPondItem", .kind = .uint8, .addr = 0x888450, .count = 256 },
    .{ .name = "kGeneratedBombosArr", .kind = .uint8, .addr = 0x8890fc, .count = 256 },

    .{ .name = "kGeneratedEndSequence15", .kind = .uint8, .addr = 0x8ead25, .count = 256 },
    .{ .name = "kEnding_Credits_Text", .kind = .uint8, .addr = 0x8eb178, .count = 1989 },
    .{ .name = "kEnding_Credits_Offs", .kind = .uint16, .addr = 0x8eb93d, .count = 394, .words = true },
    .{ .name = "kEnding_MapData", .kind = .uint16, .addr = 0x8eb038, .count = 160, .words = true },
    .{ .name = "kEnding0_Offs", .kind = .uint16, .addr = 0x8ec2e1, .count = 17, .words = true },
    .{ .name = "kEnding0_Data", .kind = .uint8, .addr = 0x8ebf4c, .count = 917 },

    .{ .name = "kPalette_DungBgMain", .kind = .uint16, .addr = 0x9bd734, .count = 1800, .words = true },
    .{ .name = "kPalette_MainSpr", .kind = .uint16, .addr = 0x9bd218, .count = 120, .words = true },

    .{ .name = "kPalette_ArmorAndGloves", .kind = .uint16, .addr = 0x9bd308, .count = 75, .words = true },
    .{ .name = "kPalette_Sword", .kind = .uint16, .addr = 0x9bd630, .count = 12, .words = true },
    .{ .name = "kPalette_Shield", .kind = .uint16, .addr = 0x9bd648, .count = 12, .words = true },

    .{ .name = "kPalette_SpriteAux3", .kind = .uint16, .addr = 0x9bd39e, .count = 84, .words = true },
    .{ .name = "kPalette_MiscSprite_Indoors", .kind = .uint16, .addr = 0x9bd446, .count = 77, .words = true },
    .{ .name = "kPalette_SpriteAux1", .kind = .uint16, .addr = 0x9bd4e0, .count = 168, .words = true },

    .{ .name = "kPalette_OverworldBgMain", .kind = .uint16, .addr = 0x9be6c8, .count = 210, .words = true },
    .{ .name = "kPalette_OverworldBgAux12", .kind = .uint16, .addr = 0x9be86c, .count = 420, .words = true },
    .{ .name = "kPalette_OverworldBgAux3", .kind = .uint16, .addr = 0x9be604, .count = 98, .words = true },
    .{ .name = "kPalette_PalaceMapBg", .kind = .uint16, .addr = 0x9be544, .count = 96, .words = true },
    .{ .name = "kPalette_PalaceMapSpr", .kind = .uint16, .addr = 0x9bd70a, .count = 21, .words = true },
    .{ .name = "kHudPalData", .kind = .uint16, .addr = 0x9bd660, .count = 64, .words = true },

    .{ .name = "kOverworldMapPaletteData", .kind = .uint16, .addr = 0x8adb27, .count = 256, .words = true },

    // Link's sprite sheet. The Python decodes the ROM's 4bpp tiles into a
    // paletted PNG and compile_resources reads that back and re-encodes it,
    // which is the identity - see the round-trip test below - so the port
    // copies the bytes and skips the image entirely.
    .{ .name = "kLinkGraphics", .kind = .uint8, .addr = 0x108000, .count = 0x800 * 448 / 32 },

    // The map32 to map16 lookup, one table per quadrant. The Python writes
    // these out as a text file of unpacked values and reads them back, which
    // is another identity - see the round-trip test below.
    .{ .name = "kMap32ToMap16_0", .kind = .uint8, .addr = 0x838000, .count = 2218 * 6 },
    .{ .name = "kMap32ToMap16_1", .kind = .uint8, .addr = 0x83b400, .count = 2218 * 6 },
    .{ .name = "kMap32ToMap16_2", .kind = .uint8, .addr = 0x848000, .count = 2218 * 6 },
    .{ .name = "kMap32ToMap16_3", .kind = .uint8, .addr = 0x84b400, .count = 2218 * 6 },

    // Dungeon tile attributes and the movable block and torch tables, which
    // print_dungeon_map emits alongside the data it builds from YAML.
    .{ .name = "kDungAttrsForTile_Offs", .kind = .uint16, .addr = 0x8e9000, .count = 21, .words = true },
    .{ .name = "kDungAttrsForTile", .kind = .uint8, .addr = 0x8e902a, .count = 1024 },
    .{ .name = "kMovableBlockDataInit", .kind = .uint16, .addr = 0x84f1de, .count = 198, .words = true },
    .{ .name = "kTorchDataInit", .kind = .uint16, .addr = 0x84f36a, .count = 144, .words = true },
    .{ .name = "kTorchDataJunk", .kind = .uint16, .addr = 0x84f48a, .count = 48, .words = true },

    .{ .name = "kDungeonRoomTeleMsg", .kind = .uint16, .addr = 0x87f61d, .count = 320, .words = true },

    // These two come from print_dungeon_map's neighbourhood rather than
    // print_misc, but they are the same shape.
    .{ .name = "kMap8DataToTileAttr", .kind = .uint8, .addr = 0x8e9459, .count = 512 },
    .{ .name = "kSomeTileAttr", .kind = .uint8, .addr = 0x9bf110, .count = 3824 },
};

pub fn buildMisc(alloc: std.mem.Allocator, rom: Rom, a: MiscAsset) ![]u8 {
    if (!a.words) return rom.getBytes(alloc, a.addr, a.count);
    const w = try rom.getWords(alloc, a.addr, a.count);
    defer alloc.free(w);
    return alloc.dupe(u8, std.mem.sliceAsBytes(w));
}

/// The overworld map is stored as 160 compressed blocks in two halves, with
/// the addresses themselves held in a table of 24 bit pointers. As with the
/// graphics, what lands in the asset file is the compressed bytes.
fn overworldBlocks(alloc: std.mem.Allocator, rom: Rom, ptr_table: u32) ![]u8 {
    var blocks: [160][]u8 = undefined;
    var done: usize = 0;
    defer for (blocks[0..done]) |b| alloc.free(b);

    while (done < blocks.len) : (done += 1) {
        const addr = rom.get24(ptr_table + @as(u32, @intCast(done)) * 3);
        const d = try rom_mod.decomp(alloc, rom, addr, true);
        defer alloc.free(d.data);
        blocks[done] = try rom.getBytes(alloc, addr, d.comp_len);
    }

    var as_const: [160][]const u8 = undefined;
    for (&as_const, blocks) |*dst, src| dst.* = src;
    return packArrays(alloc, &as_const);
}

pub fn buildOverworldHibytes(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    return overworldBlocks(alloc, rom, 0x82f94d);
}

pub fn buildOverworldLobytes(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    return overworldBlocks(alloc, rom, 0x82fb2d);
}

/// Enemy damage tables. Unlike the graphics, this one is stored decompressed
/// in the asset file - the game reads it directly.
pub fn buildEnemyDamageData(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    const d = try rom_mod.decomp(alloc, rom, 0x83e800, true);
    return d.data;
}

/// Where each background tilemap's packet stream begins. The lengths are not
/// recorded anywhere, so they have to be walked.
pub const kBgTilemapPtrs = [_]u32{ 0x0cdd6d, 0x0ce7bf, 0x0ce2a8, 0x0ce63c, 0x0ce456, 0x0eda9c };

/// Measures a stripe upload stream. Each packet has a four byte header - a
/// VRAM address, then a flag byte and a length - and the stream ends at a
/// header whose first byte has bit 7 set. A memset packet carries two bytes
/// of payload however long it expands to; everything else carries `len`.
///
/// The walk steps the address straight through rather than hopping the bank
/// boundary the way reads do. That matches the Python, and these streams do
/// not reach a boundary.
fn bgTilemapLength(rom: Rom, start: u32) u32 {
    var p = start;
    while (rom.getByte(p) & 0x80 == 0) {
        const is_memset = rom.getByte(p + 2) & 0x40 != 0;
        const len = ((@as(u32, rom.getByte(p + 2)) * 256 + rom.getByte(p + 3)) & 0x3fff) + 1;
        p += 4;
        p += if (is_memset) 2 else len;
    }
    return p - start + 1;
}

pub fn buildBgTilemap(alloc: std.mem.Allocator, rom: Rom, index: usize) ![]u8 {
    const start = kBgTilemapPtrs[index];
    return rom.getBytes(alloc, start, bgTilemapLength(rom, start));
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

test "the straight ROM copies match the reference asset file" {
    var f = try Fixture.open();
    defer f.close();

    for (kMiscAssets) |a| {
        const got = try buildMisc(testing.allocator, f.rom, a);
        defer testing.allocator.free(got);

        const want = f.contents.find(a.name) orelse {
            std.debug.print("{s} is not in the reference file\n", .{a.name});
            return error.MissingAsset;
        };
        testing.expectEqualSlices(u8, want, got) catch |err| {
            std.debug.print("{s} differs\n", .{a.name});
            return err;
        };
    }
}

test "the overworld map blocks match the reference asset file" {
    var f = try Fixture.open();
    defer f.close();

    const hi = try buildOverworldHibytes(testing.allocator, f.rom);
    defer testing.allocator.free(hi);
    try testing.expectEqualSlices(u8, f.contents.find("kOverworld_Hibytes_Comp").?, hi);

    const lo = try buildOverworldLobytes(testing.allocator, f.rom);
    defer testing.allocator.free(lo);
    try testing.expectEqualSlices(u8, f.contents.find("kOverworld_Lobytes_Comp").?, lo);
}

/// Unpacks SNES 4bpp tiles into one byte per pixel, laid out as a 128 pixel
/// wide sheet. This is sprite_sheets.decode_4bit_tileset_link.
fn decodeLinkSheet(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    const height = 448;
    const data = try rom.getBytes(alloc, 0x108000, 0x800 * height / 32);
    defer alloc.free(data);

    const dst = try alloc.alloc(u8, 128 * height);
    errdefer alloc.free(dst);
    @memset(dst, 0);

    for (0..16 * height / 8) |i| {
        const offs = i * 32;
        const toffs = (i % 16) * 8 + (i / 16) * 8 * 128;
        for (0..8) |y| {
            const d0 = data[offs + y * 2 + 0];
            const d1 = data[offs + y * 2 + 1];
            const d2 = data[offs + y * 2 + 16];
            const d3 = data[offs + y * 2 + 17];
            for (0..8) |x| {
                const xs: u3 = @intCast(x);
                const t = ((d0 >> xs) & 1) * 1 + ((d1 >> xs) & 1) * 2 +
                    ((d2 >> xs) & 1) * 4 + ((d3 >> xs) & 1) * 8;
                dst[toffs + y * 128 + (7 - x)] = t;
            }
        }
    }
    return dst;
}

/// Packs a 128 pixel wide sheet back into SNES 4bpp tiles. This is
/// print_link_graphics' encode_4bit_sprite over the whole sheet.
fn encodeLinkSheet(alloc: std.mem.Allocator, sheet: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    for (0..56) |ty| {
        for (0..16) |tx| {
            const offset = ty * 128 * 8 + tx * 8;
            var b = [_]u8{0} ** 32;
            for (0..8) |y| {
                for (0..8) |x| {
                    const v = sheet[offset + y * 128 + x];
                    const sh: u3 = @intCast(7 - x);
                    b[y * 2 + 0] |= (v & 1) << sh;
                    b[y * 2 + 1] |= (v >> 1 & 1) << sh;
                    b[y * 2 + 16] |= (v >> 2 & 1) << sh;
                    b[y * 2 + 17] |= (v >> 3 & 1) << sh;
                }
            }
            try out.appendSlice(alloc, &b);
        }
    }
    return out.toOwnedSlice(alloc);
}

// kLinkGraphics is emitted as a straight copy of the ROM. That is only valid
// because unpacking the tiles and packing them again gives back what went in,
// which is what the Python does the long way through a PNG. If that were ever
// untrue the copy would be silently wrong, so it is checked rather than
// assumed.
test "unpacking and repacking Link's tiles is the identity" {
    var f = try Fixture.open();
    defer f.close();

    const sheet = try decodeLinkSheet(testing.allocator, f.rom);
    defer testing.allocator.free(sheet);

    const repacked = try encodeLinkSheet(testing.allocator, sheet);
    defer testing.allocator.free(repacked);

    const raw = try f.rom.getBytes(testing.allocator, 0x108000, 0x800 * 448 / 32);
    defer testing.allocator.free(raw);

    try testing.expectEqualSlices(u8, raw, repacked);
    try testing.expectEqualSlices(u8, f.contents.find("kLinkGraphics").?, repacked);
}

/// Six packed bytes to four 12 bit tile numbers, as extract_resources does.
/// The low byte of each entry is stored first, then the four high nibbles
/// share the last two bytes.
fn unpackMap32(b: *const [6]u8) [4]u16 {
    return .{
        @as(u16, b[0]) | (@as(u16, b[4] >> 4) << 8),
        @as(u16, b[1]) | (@as(u16, b[4] & 0xf) << 8),
        @as(u16, b[2]) | (@as(u16, b[5] >> 4) << 8),
        @as(u16, b[3]) | (@as(u16, b[5] & 0xf) << 8),
    };
}

/// The inverse, as compile_resources does it.
fn packMap32(v: [4]u16) [6]u8 {
    return .{
        @intCast(v[0] & 0xff),
        @intCast(v[1] & 0xff),
        @intCast(v[2] & 0xff),
        @intCast(v[3] & 0xff),
        @intCast((v[0] >> 8) << 4 | (v[1] >> 8)),
        @intCast((v[2] >> 8) << 4 | (v[3] >> 8)),
    };
}

// Same reasoning as the Link tiles: these four assets are emitted as straight
// copies, which only holds because unpacking and repacking round-trips.
test "unpacking and repacking the map32 tables is the identity" {
    var f = try Fixture.open();
    defer f.close();

    for ([_]u32{ 0x838000, 0x83b400, 0x848000, 0x84b400 }, 0..) |addr, k| {
        const raw = try f.rom.getBytes(testing.allocator, addr, 2218 * 6);
        defer testing.allocator.free(raw);

        for (0..2218) |i| {
            const entry = raw[i * 6 ..][0..6];
            const repacked = packMap32(unpackMap32(entry));
            try testing.expectEqualSlices(u8, entry, &repacked);
        }

        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "kMap32ToMap16_{d}", .{k});
        try testing.expectEqualSlices(u8, f.contents.find(name).?, raw);
    }
}

test "kEnemyDamageData matches the reference asset file" {
    var f = try Fixture.open();
    defer f.close();

    const got = try buildEnemyDamageData(testing.allocator, f.rom);
    defer testing.allocator.free(got);
    try testing.expectEqualSlices(u8, f.contents.find("kEnemyDamageData").?, got);
}

test "the background tilemaps match the reference asset file" {
    var f = try Fixture.open();
    defer f.close();

    for (0..kBgTilemapPtrs.len) |i| {
        const got = try buildBgTilemap(testing.allocator, f.rom, i);
        defer testing.allocator.free(got);

        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "kBgTilemap_{d}", .{i});
        testing.expectEqualSlices(u8, f.contents.find(name).?, got) catch |err| {
            std.debug.print("{s} differs\n", .{name});
            return err;
        };
    }
}

test {
    // Pull the overworld tables' tests into this root as well.
    _ = @import("asset_overworld.zig");
    _ = @import("asset_dungeon.zig");
    _ = @import("asset_dialogue.zig");
}
