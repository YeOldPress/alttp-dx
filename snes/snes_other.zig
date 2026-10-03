//! Port of snes/snes_other.c: cartridge header detection and ROM loading.
const std = @import("std");
const snes_types = @import("snes_types.zig");
const cart = @import("cart.zig");

const Snes = snes_types.Snes;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn memcpy(dst: [*]u8, src: [*]const u8, n: usize) [*]u8;
extern fn printf(fmt: [*:0]const u8, ...) c_int;
extern fn snes_reset(snes: *Snes, hard: bool) void;

/// Internal to this file in C too, so the layout is ours to choose.
const CartHeader = struct {
    // normal header
    headerVersion: u8 = 0, // 1, 2, 3
    name: [22]u8 = @splat(0), // $ffc0-$ffd4 (max 21 bytes + \0), $ffd4=$00: header V2
    speed: u8 = 0, // $ffd5.7-4 (always 2 or 3)
    @"type": u8 = 0, // $ffd5.3-0
    coprocessor: u8 = 0, // $ffd6.7-4
    chips: u8 = 0, // $ffd6.3-0
    romSize: u32 = 0, // $ffd7 (0x400 << x)
    ramSize: u32 = 0, // $ffd8 (0x400 << x)
    region: u8 = 0, // $ffd9 (also NTSC/PAL)
    maker: u8 = 0, // $ffda ($33: header V3)
    version: u8 = 0, // $ffdb
    checksumComplement: u16 = 0, // $ffdc,$ffdd
    checksum: u16 = 0, // $ffde,$ffdf
    // v2/v3 (v2 only exCoprocessor)
    makerCode: [3]u8 = @splat(0), // $ffb0,$ffb1: (2 chars + \0)
    gameCode: [5]u8 = @splat(0), // $ffb2-$ffb5: (4 chars + \0)
    flashSize: u32 = 0, // $ffbc (0x400 << x)
    exRamSize: u32 = 0, // $ffbd (0x400 << x) (used for GSU?)
    specialVersion: u8 = 0, // $ffbe
    exCoprocessor: u8 = 0, // $ffbf (if coprocessor = $f)
    // calculated stuff
    score: i16 = 0, // score for header, to see which mapping is most likely
    pal: bool = false, // if this is a rom for PAL regions instead of NTSC
    cartType: u8 = 0, // calculated type
};

/// `0x400 << x` with x straight out of the ROM. C leaves an oversized shift
/// undefined; every target this runs on masks the count, so do that explicitly.
fn sizeShift(x: u8) u32 {
    return @as(u32, 0x400) << @truncate(x);
}

pub export fn snes_loadRom(snes: *Snes, data_in: [*]u8, length_in: c_int) callconv(.c) bool {
    var data = data_in;
    var length = length_in;
    // if smaller than smallest possible, don't load
    if (length < 0x8000) {
        _ = printf("Failed to load rom: rom to small (%d bytes)\n", length);
        return false;
    }
    // check headers
    var headers: [4]CartHeader = @splat(.{ .score = -50 });
    if (length >= 0x8000) readHeader(data, 0x7fc0, &headers[0]);
    if (length >= 0x8200) readHeader(data, 0x81c0, &headers[1]);
    if (length >= 0x10000) readHeader(data, 0xffc0, &headers[2]);
    if (length >= 0x10200) readHeader(data, 0x101c0, &headers[3]);
    // see which it is
    var max: i16 = 0;
    var used: usize = 0;
    for (headers, 0..) |h, i| {
        if (h.score > max) {
            max = h.score;
            used = i;
        }
    }
    if (used & 1 != 0) {
        // odd-numbered ones are for headered roms
        data += 0x200; // move pointer past header
        length -= 0x200; // and subtract from size
    }
    // check if we can load it
    if (headers[used].cartType > 2) {
        _ = printf("Failed to load rom: unsupported type (%d)\n", @as(c_int, headers[used].cartType));
        return false;
    }
    // expand to a power of 2
    var newLength: c_int = 0x8000;
    while (length > newLength) newLength *= 2;
    const newData: [*]u8 = @ptrCast(malloc(@intCast(newLength)).?);
    _ = memcpy(newData, data, @intCast(length));
    // mirror the tail of the rom up into the unused space
    var testbit: c_int = 1;
    while (length != newLength) {
        if (length & testbit != 0) {
            _ = memcpy(newData + @as(usize, @intCast(length)), newData + @as(usize, @intCast(length - testbit)), @intCast(testbit));
            length += testbit;
        }
        testbit *= 2;
    }
    // load it
    _ = printf(
        "Loaded %s rom\n\"%s\"\n",
        @as([*:0]const u8, if (headers[used].cartType == 2) "HiROM" else "LoROM"),
        @as([*:0]const u8, @ptrCast(&headers[used].name)),
    );
    cart.cart_load(
        @ptrCast(@alignCast(snes.cart.?)),
        headers[used].cartType,
        newData,
        newLength,
        if (headers[used].chips > 0) @intCast(headers[used].ramSize) else 0,
    );
    snes_reset(snes, true); // reset after loading
    free(newData);
    return true;
}

fn printable(ch: u8) u8 {
    return if (ch >= 0x20 and ch < 0x7f) ch else '.';
}

fn readHeader(data: [*]const u8, location: usize, header: *CartHeader) void {
    // read name, TODO: non-ASCII names?
    for (0..21) |i| header.name[i] = printable(data[location + i]);
    header.name[21] = 0;
    // read rest
    header.speed = data[location + 0x15] >> 4;
    header.@"type" = data[location + 0x15] & 0xf;
    header.coprocessor = data[location + 0x16] >> 4;
    header.chips = data[location + 0x16] & 0xf;
    header.romSize = sizeShift(data[location + 0x17]);
    header.ramSize = sizeShift(data[location + 0x18]);
    header.region = data[location + 0x19];
    header.maker = data[location + 0x1a];
    header.version = data[location + 0x1b];
    header.checksumComplement = @as(u16, data[location + 0x1d]) << 8 | data[location + 0x1c];
    header.checksum = @as(u16, data[location + 0x1f]) << 8 | data[location + 0x1e];
    // read v3 and/or v2
    header.headerVersion = 1;
    if (header.maker == 0x33) {
        header.headerVersion = 3;
        // maker code
        for (0..2) |i| header.makerCode[i] = printable(data[location - 0x10 + i]);
        header.makerCode[2] = 0;
        // game code
        for (0..4) |i| header.gameCode[i] = printable(data[location - 0xe + i]);
        header.gameCode[4] = 0;
        header.flashSize = sizeShift(data[location - 4]);
        header.exRamSize = sizeShift(data[location - 3]);
        header.specialVersion = data[location - 2];
        header.exCoprocessor = data[location - 1];
    } else if (data[location + 0x14] == 0) {
        header.headerVersion = 2;
        header.exCoprocessor = data[location - 1];
    }
    // get region
    header.pal = (header.region >= 0x2 and header.region <= 0xc) or header.region == 0x11;
    header.cartType = if (location < 0x9000) 1 else 2;
    // get score
    // TODO: check name, maker/game-codes (if V3) for ASCII, more vectors,
    //   more first opcode, rom-sizes (matches?), type (matches header location?)
    var score: i16 = 0;
    score += if (header.speed == 2 or header.speed == 3) 5 else -4;
    score += if (header.@"type" <= 3 or header.@"type" == 5) 5 else -2;
    score += if (header.coprocessor <= 5 or header.coprocessor >= 0xe) 5 else -2;
    score += if (header.chips <= 6 or header.chips == 9 or header.chips == 0xa) 5 else -2;
    score += if (header.region <= 0x14) 5 else -2;
    score += if (@as(u32, header.checksum) + header.checksumComplement == 0xffff) 8 else -6;
    const resetVector = @as(u16, data[location + 0x3d]) << 8 | data[location + 0x3c];
    score += if (resetVector >= 0x8000) 8 else -20;
    // check first opcode after reset
    const opcode = data[location + 0x40 - 0x8000 + (resetVector & 0x7fff)];
    if (opcode == 0x78 or opcode == 0x18) {
        // sei, clc (for clc:xce)
        score += 6;
    }
    if (opcode == 0x4c or opcode == 0x5c or opcode == 0x9c) {
        // jmp abs, jml abl, stz abs
        score += 3;
    }
    if (opcode == 0x00 or opcode == 0xff or opcode == 0xdb) {
        // brk, sbc alx, stp
        score -= 6;
    }
    header.score = score;
}

const testing = std.testing;

/// Lays down a plausible LoROM header so the scoring can be exercised.
fn writeTestHeader(rom: []u8, loc: usize) void {
    @memcpy(rom[loc..][0..21], "ZELDANODENSETSU      ");
    rom[loc + 0x15] = 0x20; // speed 2, type 0
    rom[loc + 0x16] = 0x02; // coprocessor 0, chips 2
    rom[loc + 0x17] = 0x0a; // 1 MB rom
    rom[loc + 0x18] = 0x03; // 8 KB ram
    rom[loc + 0x19] = 0x01; // region: NTSC
    rom[loc + 0x1a] = 0x01; // maker (not 0x33, so header version 1)
    rom[loc + 0x1c] = 0x00; // checksum complement
    rom[loc + 0x1d] = 0x00;
    rom[loc + 0x1e] = 0xff; // checksum, sums with the complement to 0xffff
    rom[loc + 0x1f] = 0xff;
    rom[loc + 0x3c] = 0x00; // reset vector -> $8000
    rom[loc + 0x3d] = 0x80;
    rom[loc + 0x40 - 0x8000] = 0x78; // first opcode after reset: sei
}

test "a well formed LoROM header scores every point available" {
    var rom: [0x10000]u8 = @splat(0);
    writeTestHeader(&rom, 0x7fc0);
    var header = CartHeader{ .score = -50 };
    readHeader(&rom, 0x7fc0, &header);

    // 5 each for speed, type, coprocessor, chips and region, 8 for the
    // checksum pair, 8 for the reset vector and 6 for the sei.
    try testing.expectEqual(@as(i16, 47), header.score);
    try testing.expectEqual(@as(u8, 1), header.cartType);
    try testing.expectEqual(@as(u8, 1), header.headerVersion);
    try testing.expect(!header.pal);
    try testing.expectEqual(@as(u32, 0x400 << 0xa), header.romSize);
    try testing.expectEqual(@as(u32, 0x400 << 3), header.ramSize);
    try testing.expectEqualStrings("ZELDANODENSETSU      ", header.name[0..21]);
}

test "garbage scores below a real header" {
    var rom: [0x10000]u8 = @splat(0xaa);
    var header = CartHeader{ .score = -50 };
    readHeader(&rom, 0x7fc0, &header);
    try testing.expect(header.score < 0);

    var good: [0x10000]u8 = @splat(0);
    writeTestHeader(&good, 0x7fc0);
    var good_header = CartHeader{ .score = -50 };
    readHeader(&good, 0x7fc0, &good_header);
    try testing.expect(good_header.score > header.score);
}

test "unprintable bytes in the name become dots" {
    var rom: [0x10000]u8 = @splat(0);
    writeTestHeader(&rom, 0x7fc0);
    rom[0x7fc0] = 0x01;
    rom[0x7fc1] = 0xff;
    var header = CartHeader{ .score = -50 };
    readHeader(&rom, 0x7fc0, &header);
    try testing.expectEqualStrings("..LDA", header.name[0..5]);
    try testing.expectEqual(@as(u8, 0), header.name[21]);
}

test "a HiROM location is typed as HiROM" {
    var rom: [0x20000]u8 = @splat(0);
    writeTestHeader(&rom, 0xffc0);
    rom[0xffc0 + 0x40 - 0x8000] = 0x78;
    var header = CartHeader{ .score = -50 };
    readHeader(&rom, 0xffc0, &header);
    try testing.expectEqual(@as(u8, 2), header.cartType);
}

test "version 3 headers pick up the maker and game codes" {
    var rom: [0x10000]u8 = @splat(0);
    writeTestHeader(&rom, 0x7fc0);
    rom[0x7fc0 + 0x1a] = 0x33; // maker 0x33 marks a v3 header
    @memcpy(rom[0x7fc0 - 0x10 ..][0..2], "01");
    @memcpy(rom[0x7fc0 - 0xe ..][0..4], "AZLE");
    var header = CartHeader{ .score = -50 };
    readHeader(&rom, 0x7fc0, &header);
    try testing.expectEqual(@as(u8, 3), header.headerVersion);
    try testing.expectEqualStrings("01", header.makerCode[0..2]);
    try testing.expectEqualStrings("AZLE", header.gameCode[0..4]);
}

test "sizeShift masks the shift count the way the hardware does" {
    try testing.expectEqual(@as(u32, 0x400), sizeShift(0));
    try testing.expectEqual(@as(u32, 0x400 << 10), sizeShift(10));
    // A junk byte must not crash the loader.
    try testing.expectEqual(@as(u32, 0x400), sizeShift(32));
}
