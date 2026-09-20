//! Dungeon assets built straight from the ROM.
//!
//! compile_resources reads these out of per-room YAML, where sprites and
//! secrets are written as names and coordinates. Both are re-encoded to the
//! same bytes they were decoded from, so with extraction and compilation
//! fused the packets can be copied across and the name tables are not needed.
//!
//! The room object data is the same story: the Python decodes every object
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
