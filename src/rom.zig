//! Reading the SNES ROM, and the decompressor the game's data is stored under.
//!
//! This is the Zig side of assets/util.py. Addresses are SNES addresses in
//! LoROM form: bank in the high byte, offset 0x8000..0xffff in the low word.

const std = @import("std");
const fileio = @import("fileio.zig");

pub const Language = enum { us, de, fr, fr_c, en, es, pl, pt, redux, nl, sv };

const KnownRom = struct { sha1: *const [40]u8, lang: Language, name: []const u8 };

/// The ROMs the resource tool knows how to read. Only `us` is supported on
/// the default path; the rest matter when building extra languages.
pub const kKnownRoms = [_]KnownRom{
    .{ .sha1 = "6D4F10A8B10E10DBE624CB23CF03B88BB8252973", .lang = .us, .name = "Legend of Zelda, The - A Link to the Past (USA)" },
    .{ .sha1 = "2E62494967FB0AFDF5DA1635607F9641DF7C6559", .lang = .de, .name = "Legend of Zelda, The - A Link to the Past (Germany)" },
    .{ .sha1 = "229364A1B92A05167CD38609B1AA98F7041987CC", .lang = .fr, .name = "Legend of Zelda, The - A Link to the Past (France)" },
};

pub const Rom = struct {
    bytes: []u8,
    language: ?Language,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *Rom) void {
        self.alloc.free(self.bytes);
        self.* = undefined;
    }

    pub fn load(alloc: std.mem.Allocator, path: [*:0]const u8) !Rom {
        var bytes = try fileio.readWholeFile(alloc, path);
        errdefer alloc.free(bytes);

        // A copier header is 0x200 bytes on top of a power-of-two image.
        if (bytes.len & 0xfffff == 0x200) {
            const stripped = try alloc.dupe(u8, bytes[0x200..]);
            alloc.free(bytes);
            bytes = stripped;
        }

        var digest: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(bytes, &digest, .{});
        var hex: [40]u8 = undefined;
        const kHexDigits = "0123456789ABCDEF";
        for (digest, 0..) |byte, i| {
            hex[i * 2] = kHexDigits[byte >> 4];
            hex[i * 2 + 1] = kHexDigits[byte & 0xf];
        }

        var language: ?Language = null;
        for (kKnownRoms) |k| {
            if (std.mem.eql(u8, &hex, k.sha1)) language = k.lang;
        }

        return .{ .bytes = bytes, .language = language, .alloc = alloc };
    }

    /// SNES address to file offset. LoROM maps each bank's 0x8000..0xffff to
    /// a 32k slice, so the bank number scales by 0x8000 rather than 0x10000.
    fn offsetOf(ea: u32) usize {
        std.debug.assert(ea & 0x8000 != 0);
        return (((ea >> 16) & 0x7f) * 0x8000) + (ea & 0x7fff);
    }

    pub fn getByte(self: Rom, ea: u32) u8 {
        return self.bytes[offsetOf(ea)];
    }

    pub fn getWord(self: Rom, ea: u32) u16 {
        return @as(u16, self.getByte(ea)) | (@as(u16, self.getByte(ea + 1)) << 8);
    }

    pub fn get24(self: Rom, ea: u32) u32 {
        return @as(u32, self.getWord(ea)) | (@as(u32, self.getByte(ea + 2)) << 16);
    }

    pub fn getBytes(self: Rom, alloc: std.mem.Allocator, addr: u32, n: usize) ![]u8 {
        const r = try alloc.alloc(u8, n);
        errdefer alloc.free(r);
        var ea = addr;
        for (r) |*b| {
            b.* = self.getByte(ea);
            ea = advance(ea, 1);
        }
        return r;
    }

    pub fn getWords(self: Rom, alloc: std.mem.Allocator, addr: u32, n: usize) ![]u16 {
        const r = try alloc.alloc(u16, n);
        errdefer alloc.free(r);
        var ea = addr;
        for (r) |*w| {
            w.* = self.getWord(ea);
            ea = advance(ea, 2);
        }
        return r;
    }
};

/// Steps an address forward, hopping over the unmapped low half of a bank.
fn advance(ea: u32, n: u32) u32 {
    const next = ea + n;
    return if (next & 0x8000 == 0) next + 0x8000 else next;
}

pub const Decompressed = struct {
    data: []u8,
    /// Bytes consumed from the ROM, which callers need to walk a run of
    /// back-to-back compressed blocks.
    comp_len: u32,
};

/// The game's LZ variant. A command byte carries a 3 bit op and a 5 bit
/// length; the escape 111 borrows three bits from the next byte for lengths
/// over 32. 0xff ends the stream.
///
/// `offset_is_be` is a real difference between callers: the background and
/// sprite graphics store copy offsets little-endian, everything else big.
pub fn decomp(alloc: std.mem.Allocator, rom: Rom, ea: u32, offset_is_be: bool) !Decompressed {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(alloc);

    var pos = ea;
    const next = struct {
        fn f(r: Rom, p: *u32) u8 {
            const b = r.getByte(p.*);
            p.* += 1;
            // Compressed streams wrap at the bank boundary, not at 0x8000.
            if (p.* & 0xffff == 0) p.* += 0x8000;
            return b;
        }
    }.f;

    while (true) {
        const b = next(rom, &pos);
        if (b == 0xff) return .{
            .data = try result.toOwnedSlice(alloc),
            .comp_len = (pos -% ea) & 0x7fff,
        };

        var cmd: u8 = undefined;
        var lx: u32 = undefined;
        if (b & 0xe0 != 0xe0) {
            lx = b & 0x1f;
            cmd = b & 0xe0;
        } else {
            cmd = (b << 3) & 0xe0;
            lx = (@as(u32, b & 3) << 8) | next(rom, &pos);
        }
        lx += 1;

        if (cmd == 0x00) { // literal
            for (0..lx) |_| try result.append(alloc, next(rom, &pos));
        } else if (cmd & 0x80 != 0) { // copy from earlier in the output
            var offs: u32 = @as(u32, next(rom, &pos)) << 8;
            offs |= next(rom, &pos);
            if (!offset_is_be) offs = ((offs >> 8) | (offs << 8)) & 0xffff;
            // Reads trail writes, so an overlapping copy repeats a pattern.
            for (0..lx) |_| {
                try result.append(alloc, result.items[offs]);
                offs += 1;
            }
        } else if (cmd & 0x40 == 0) { // memset
            const v = next(rom, &pos);
            try result.appendNTimes(alloc, v, lx);
        } else if (cmd & 0x20 == 0) { // memset, two alternating bytes
            const b1 = next(rom, &pos);
            const b2 = next(rom, &pos);
            var left = lx;
            while (left != 0) {
                try result.append(alloc, b1);
                if (left == 1) break;
                try result.append(alloc, b2);
                left -= 2;
            }
        } else { // incrementing run
            var v = next(rom, &pos);
            for (0..lx) |_| {
                try result.append(alloc, v);
                v +%= 1;
            }
        }
    }
}

const testing = std.testing;

// The ROM is not in the repository, so everything that needs one is skipped
// when it is absent.
fn openTestRom() !Rom {
    if (!fileio.exists("zelda3.sfc")) return error.SkipZigTest;
    return Rom.load(testing.allocator, "zelda3.sfc");
}

test "the shipped ROM is identified as the US release" {
    var rom = try openTestRom();
    defer rom.deinit();
    try testing.expectEqual(Language.us, rom.language.?);
    try testing.expectEqual(@as(usize, 0x100000), rom.bytes.len);
}

test "LoROM addresses map to the right file offsets" {
    var rom = try openTestRom();
    defer rom.deinit();

    // Bank 0 starts at the beginning of the file, and each later bank adds
    // 32k rather than 64k.
    try testing.expectEqual(rom.bytes[0], rom.getByte(0x008000));
    try testing.expectEqual(rom.bytes[0x7fff], rom.getByte(0x00ffff));
    try testing.expectEqual(rom.bytes[0x8000], rom.getByte(0x018000));
    try testing.expectEqual(rom.bytes[0xf8000], rom.getByte(0x1f8000));
}

test "the internal header names the game" {
    var rom = try openTestRom();
    defer rom.deinit();
    const title = try rom.getBytes(testing.allocator, 0x00ffc0, 21);
    defer testing.allocator.free(title);
    try testing.expectEqualStrings("THE LEGEND OF ZELDA  ", title);
}

test "getBytes steps over the unmapped half of each bank" {
    var rom = try openTestRom();
    defer rom.deinit();
    // Four bytes straddling the end of bank 0.
    const got = try rom.getBytes(testing.allocator, 0x00fffe, 4);
    defer testing.allocator.free(got);
    try testing.expectEqual(rom.bytes[0x7ffe], got[0]);
    try testing.expectEqual(rom.bytes[0x7fff], got[1]);
    try testing.expectEqual(rom.bytes[0x8000], got[2]);
    try testing.expectEqual(rom.bytes[0x8001], got[3]);
}
