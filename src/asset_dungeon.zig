//! Dungeon assets built straight from the ROM.
//!
//! compile_resources reads these out of per-room YAML, where sprites and
//! secrets are written as names and coordinates. Both are re-encoded to the
//! same bytes they were decoded from, so with extraction and compilation
//! fused the packets can be copied across and the name tables are not needed.
//!
//! The room object data is the same story: the old Python decodes every object
//! into a name, a position and a size and encodes it again, and the bytes
//! come back identical, so the rooms are copied and walked for their lengths.

const std = @import("std");
const rom_mod = @import("rom.zig");
const pack = @import("asset_pack.zig");

const Rom = rom_mod.Rom;

pub const kRoomCount = 320;

/// Sprites for every room, as one run of packets.
///
/// A room's entry is its sort flag followed by three bytes per sprite and a
/// terminator. Rooms with no sprites and no sorting share the empty entry the
/// list opens with, so their offset stays zero.
pub fn buildSprites(alloc: std.mem.Allocator, rom: Rom, offsets_out: *[kRoomCount]u16) ![]u8 {
    var data: std.ArrayList(u8) = .empty;
    errdefer data.deinit(alloc);
    try data.appendSlice(alloc, &.{ 0, 0xff });
    offsets_out.* = @splat(0);

    for (0..kRoomCount) |i| {
        const base: u32 = 0x890000 + @as(u32, rom.getWord(0x89d62e + @as(u32, @intCast(i)) * 2));
        const sort_mode = rom.getByte(base);

        const ea = base + 1;
        var len: u32 = 0;
        while (rom.getByte(ea + len) != 0xff) len += 3;

        if (len == 0 and sort_mode == 0) continue;

        offsets_out[i] = @intCast(data.items.len);
        try data.append(alloc, sort_mode);
        for (0..len) |k| try data.append(alloc, rom.getByte(ea + @as(u32, @intCast(k))));
        try data.append(alloc, 0xff);
    }
    return data.toOwnedSlice(alloc);
}

/// Secrets for every room. The first 640 bytes are a per-room offset table
/// pointing into the packets that follow, and rooms with no secrets all point
/// at the final terminator.
pub fn buildSecrets(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    var res: std.ArrayList(u8) = .empty;
    errdefer res.deinit(alloc);
    try res.appendNTimes(alloc, 0, kRoomCount * 2);

    var has: [kRoomCount]bool = @splat(false);

    for (0..kRoomCount) |i| {
        var ea: u32 = 0x810000 | @as(u32, rom.getWord(0x81db69 + @as(u32, @intCast(i)) * 2));
        if (rom.getWord(ea) == 0xffff) continue;

        const at = res.items.len;
        res.items[i * 2 + 0] = @intCast(at & 0xff);
        res.items[i * 2 + 1] = @intCast(at >> 8);
        has[i] = true;

        while (rom.getWord(ea) != 0xffff) {
            const pos = rom.getWord(ea);
            try res.append(alloc, @intCast(pos & 0xff));
            try res.append(alloc, @intCast(pos >> 8));
            try res.append(alloc, rom.getByte(ea + 2));
            ea += 3;
        }
        try res.appendSlice(alloc, &.{ 0xff, 0xff });
    }

    const tail = res.items.len - 2;
    for (0..kRoomCount) |i| {
        if (has[i]) continue;
        res.items[i * 2 + 0] = @intCast(tail & 0xff);
        res.items[i * 2 + 1] = @intCast(tail >> 8);
    }
    return res.toOwnedSlice(alloc);
}

/// Result of laying every room's object data end to end.
pub const Rooms = struct {
    data: []u8,
    offsets: [kRoomCount]u16,
    door_offsets: [kRoomCount]u16,

    pub fn deinit(self: *Rooms, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
        self.* = undefined;
    }
};

/// Concatenates the rooms and records where each one - and each one's door
/// list - starts.
///
/// A room is two header bytes and then three layers. A layer is a run of
/// three byte objects, ended by 0xffff, except that 0xfff0 opens a list of
/// two byte doors which the layer's own terminator then closes. The markers
/// have to be read as words rather than bytes: an object's first byte can be
/// 0xff on its own, so only the pair is unambiguous.
pub fn buildRooms(alloc: std.mem.Allocator, rom: Rom) !Rooms {
    var data: std.ArrayList(u8) = .empty;
    errdefer data.deinit(alloc);

    var offsets: [kRoomCount]u16 = @splat(0);
    var door_offsets: [kRoomCount]u16 = @splat(0);

    for (0..kRoomCount) |i| {
        const ptr: u32 = 0x1f8000 + @as(u32, @intCast(i)) * 3;
        const room_addr = @as(u32, rom.getByte(ptr)) |
            (@as(u32, rom.getByte(ptr + 1)) << 8) |
            (@as(u32, rom.getByte(ptr + 2)) << 16);

        offsets[i] = @intCast(data.items.len);
        try data.append(alloc, rom.getByte(room_addr));
        try data.append(alloc, rom.getByte(room_addr + 1));

        var q = room_addr + 2;
        for (0..3) |layer| {
            while (true) {
                const w = @as(u16, rom.getByte(q)) | (@as(u16, rom.getByte(q + 1)) << 8);
                if (w == 0xffff) {
                    try data.appendSlice(alloc, &.{ rom.getByte(q), rom.getByte(q + 1) });
                    q += 2;
                    break;
                }
                if (w == 0xfff0) {
                    try data.appendSlice(alloc, &.{ rom.getByte(q), rom.getByte(q + 1) });
                    q += 2;
                    if (layer == 2) door_offsets[i] = @intCast(data.items.len);
                    // Doors run two bytes at a time until the layer's own
                    // terminator, which closes both at once.
                    while (true) {
                        const w2 = @as(u16, rom.getByte(q)) | (@as(u16, rom.getByte(q + 1)) << 8);
                        try data.appendSlice(alloc, &.{ rom.getByte(q), rom.getByte(q + 1) });
                        q += 2;
                        if (w2 == 0xffff) break;
                    }
                    break;
                }
                try data.appendSlice(alloc, &.{ rom.getByte(q), rom.getByte(q + 1), rom.getByte(q + 2) });
                q += 3;
            }
        }
    }

    return .{
        .data = try data.toOwnedSlice(alloc),
        .offsets = offsets,
        .door_offsets = door_offsets,
    };
}

/// Appends `little` to `big`, reusing any overlap: if `big` already ends
/// with a prefix of `little`, only the remainder is added. Returns where
/// `little` starts. This is append_scan_bytes, and it is what lets the room
/// header table be smaller than 320 times fourteen bytes.
fn appendScanBytes(alloc: std.mem.Allocator, big: *std.ArrayList(u8), little: []const u8) !u16 {
    var n: usize = @min(little.len, big.items.len);
    while (true) : (n -= 1) {
        if (n == 0 or std.mem.eql(u8, big.items[big.items.len - n ..], little[0..n])) {
            const offset = big.items.len - n;
            try big.appendSlice(alloc, little[n..]);
            return @intCast(offset);
        }
    }
}

pub const Headers = struct {
    data: []u8,
    offsets: [kRoomCount]u16,

    pub fn deinit(self: *Headers, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
        self.* = undefined;
    }
};

/// Every room's fourteen byte header, overlapped so that rooms sharing a
/// tail share the bytes.
///
/// The header is copied out of the ROM except for two bytes that the old Python
/// takes apart into fields and reassembles, narrowing them on the way.
pub fn buildHeaders(alloc: std.mem.Allocator, rom: Rom) !Headers {
    var data: std.ArrayList(u8) = .empty;
    errdefer data.deinit(alloc);
    var offsets: [kRoomCount]u16 = @splat(0);

    for (0..kRoomCount) |i| {
        var hp: u32 = 0x40000 | @as(u32, rom.getWord(0x04f502 + @as(u32, @intCast(i)) * 2));
        // One room points at a slot that is not a header; the old Python sends it
        // somewhere harmlessly full of zeros instead.
        if (hp == 0x4ffef) hp = 0x82edc5;

        var h: [14]u8 = undefined;
        for (&h, 0..) |*b, k| b.* = rom.getByte(hp + @as(u32, @intCast(k)));
        // Byte 0 splits into a background mode, a collision type and a
        // lights-out flag, which between them miss bit 1. Byte 8 carries
        // only the last staircase's destination plane in its low two bits;
        // the rest of it is not part of the header the game reads.
        h[0] &= 0xfd;
        h[8] &= 0x03;

        offsets[i] = try appendScanBytes(alloc, &data, &h);
    }
    return .{ .data = try data.toOwnedSlice(alloc), .offsets = offsets };
}

/// Chest contents, regrouped from the ROM's order into room order. The top
/// bit of the room word marks a big chest and is carried through.
pub fn buildChests(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    for (0..kRoomCount) |room| {
        for (0..504 / 3) |k| {
            const ea = 0x81e96e + @as(u32, @intCast(k)) * 3;
            const w = rom.getWord(ea);
            if ((w & 0x7fff) != room) continue;
            const big = (w & 0x8000) != 0;
            try out.append(alloc, @intCast(room & 0xff));
            try out.append(alloc, @as(u8, @intCast(room >> 8)) | (if (big) @as(u8, 0x80) else 0));
            try out.append(alloc, rom.getByte(ea + 2));
        }
    }
    return out.toOwnedSlice(alloc);
}

/// Rooms whose pits hurt the player, as a sorted list of room numbers.
pub fn buildPitsHurtPlayer(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    var out: std.ArrayList(u16) = .empty;
    defer out.deinit(alloc);

    for (0..kRoomCount) |room| {
        for (0..57) |k| {
            if (rom.getWord(0x80990c + @as(u32, @intCast(k)) * 2) == room) {
                try out.append(alloc, @intCast(room));
                break;
            }
        }
    }
    return alloc.dupe(u8, std.mem.sliceAsBytes(out.items));
}

pub const Layers = struct {
    data: []u8,
    offsets: []u16,

    pub fn deinit(self: *Layers, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
        alloc.free(self.offsets);
        self.* = undefined;
    }
};

/// The default and overlay rooms: a single layer of objects each, with no
/// door list, reached through a table of 24 bit pointers.
pub fn buildLayerSet(alloc: std.mem.Allocator, rom: Rom, ptr_table: u32, count: usize) !Layers {
    var data: std.ArrayList(u8) = .empty;
    errdefer data.deinit(alloc);
    const offsets = try alloc.alloc(u16, count);
    errdefer alloc.free(offsets);

    for (0..count) |i| {
        const ptr = ptr_table + @as(u32, @intCast(i)) * 3;
        var q = @as(u32, rom.getByte(ptr)) |
            (@as(u32, rom.getByte(ptr + 1)) << 8) |
            (@as(u32, rom.getByte(ptr + 2)) << 16);

        offsets[i] = @intCast(data.items.len);
        while (true) {
            const w = @as(u16, rom.getByte(q)) | (@as(u16, rom.getByte(q + 1)) << 8);
            if (w == 0xffff) {
                try data.appendSlice(alloc, &.{ rom.getByte(q), rom.getByte(q + 1) });
                break;
            }
            try data.appendSlice(alloc, &.{ rom.getByte(q), rom.getByte(q + 1), rom.getByte(q + 2) });
            q += 3;
        }
    }
    return .{ .data = try data.toOwnedSlice(alloc), .offsets = offsets };
}

pub fn buildDefaultRooms(alloc: std.mem.Allocator, rom: Rom) !Layers {
    return buildLayerSet(alloc, rom, 0x84ef2f, 8);
}

pub fn buildOverlayRooms(alloc: std.mem.Allocator, rom: Rom) !Layers {
    return buildLayerSet(alloc, rom, 0x84ecc0, 19);
}

const testing = std.testing;
const fileio = @import("fileio.zig");

test "the dungeon sprites and secrets match the reference asset file" {
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc") or !fileio.exists("zig-out/bin/zelda3_assets.dat"))
        return error.SkipZigTest;

    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();
    const dat = try fileio.readWholeFile(alloc, "zig-out/bin/zelda3_assets.dat");
    defer alloc.free(dat);
    var contents = try pack.read(alloc, dat);
    defer contents.deinit(alloc);

    var offsets: [kRoomCount]u16 = undefined;
    const sprites = try buildSprites(alloc, rom, &offsets);
    defer alloc.free(sprites);
    try testing.expectEqualSlices(u8, contents.find("kDungeonSprites").?, sprites);
    try testing.expectEqualSlices(u8, contents.find("kDungeonSpriteOffs").?, std.mem.sliceAsBytes(offsets[0..]));

    const secrets = try buildSecrets(alloc, rom);
    defer alloc.free(secrets);
    try testing.expectEqualSlices(u8, contents.find("kDungeonSecrets").?, secrets);
}

test "the dungeon rooms match the reference asset file" {
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc") or !fileio.exists("zig-out/bin/zelda3_assets.dat"))
        return error.SkipZigTest;

    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();
    const dat = try fileio.readWholeFile(alloc, "zig-out/bin/zelda3_assets.dat");
    defer alloc.free(dat);
    var contents = try pack.read(alloc, dat);
    defer contents.deinit(alloc);

    var rooms = try buildRooms(alloc, rom);
    defer rooms.deinit(alloc);

    try testing.expectEqualSlices(u8, contents.find("kDungeonRoom").?, rooms.data);
    try testing.expectEqualSlices(u8, contents.find("kDungeonRoomOffs").?, std.mem.sliceAsBytes(rooms.offsets[0..]));
    try testing.expectEqualSlices(u8, contents.find("kDungeonRoomDoorOffs").?, std.mem.sliceAsBytes(rooms.door_offsets[0..]));
}

test "the dungeon headers, chests and pit rooms match the reference" {
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc") or !fileio.exists("zig-out/bin/zelda3_assets.dat"))
        return error.SkipZigTest;

    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();
    const dat = try fileio.readWholeFile(alloc, "zig-out/bin/zelda3_assets.dat");
    defer alloc.free(dat);
    var contents = try pack.read(alloc, dat);
    defer contents.deinit(alloc);

    var headers = try buildHeaders(alloc, rom);
    defer headers.deinit(alloc);
    try testing.expectEqualSlices(u8, contents.find("kDungeonRoomHeaders").?, headers.data);
    try testing.expectEqualSlices(u8, contents.find("kDungeonRoomHeadersOffs").?, std.mem.sliceAsBytes(headers.offsets[0..]));

    const chests = try buildChests(alloc, rom);
    defer alloc.free(chests);
    try testing.expectEqualSlices(u8, contents.find("kDungeonRoomChests").?, chests);

    const pits = try buildPitsHurtPlayer(alloc, rom);
    defer alloc.free(pits);
    try testing.expectEqualSlices(u8, contents.find("kDungeonPitsHurtPlayer").?, pits);
}

test "the default and overlay rooms match the reference asset file" {
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc") or !fileio.exists("zig-out/bin/zelda3_assets.dat"))
        return error.SkipZigTest;

    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();
    const dat = try fileio.readWholeFile(alloc, "zig-out/bin/zelda3_assets.dat");
    defer alloc.free(dat);
    var contents = try pack.read(alloc, dat);
    defer contents.deinit(alloc);

    var def = try buildDefaultRooms(alloc, rom);
    defer def.deinit(alloc);
    try testing.expectEqualSlices(u8, contents.find("kDungeonRoomDefault").?, def.data);
    try testing.expectEqualSlices(u8, contents.find("kDungeonRoomDefaultOffs").?, std.mem.sliceAsBytes(def.offsets));

    var ov = try buildOverlayRooms(alloc, rom);
    defer ov.deinit(alloc);
    try testing.expectEqualSlices(u8, contents.find("kDungeonRoomOverlay").?, ov.data);
    try testing.expectEqualSlices(u8, contents.find("kDungeonRoomOverlayOffs").?, std.mem.sliceAsBytes(ov.offsets));
}
