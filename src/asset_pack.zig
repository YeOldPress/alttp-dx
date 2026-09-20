//! The zelda3_assets.dat container.
//!
//! This is the file the game memory-maps at startup and indexes by asset
//! number. The Python resource tool writes it at the end of compile_resources;
//! this module is the same writer in Zig, plus a reader so a freshly built
//! file can be checked against one the tool produced.
//!
//! Layout, all integers native-endian because the game casts straight into the
//! mapped bytes:
//!
//!     0   16  "Zelda3_v0     \n\0"
//!     16  32  sha256 of the name table
//!     48  32  zero
//!     80  4   asset count
//!     84  4   name table length in bytes
//!     88  4*n payload sizes
//!     ..      name table: each name NUL terminated
//!     ..      payloads, each starting on a 4 byte boundary
//!
//! The hash covers only the names, so it changes when assets are added,
//! removed or renamed - it is how the game notices a stale .dat.

const std = @import("std");
const fileio = @import("fileio.zig");

pub const kSignature = "Zelda3_v0     \n\x00";

/// How the game casts a payload. Carried so the writer can emit the C header
/// the Python tool prints with --print-assets-header.
pub const Kind = enum {
    uint8,
    uint16,
    int8,
    int16,
    /// A length-prefixed array of arrays, reached through FindInAssetArray.
    packed_arrays,

    pub fn cType(self: Kind) []const u8 {
        return switch (self) {
            .uint8 => "uint8",
            .uint16 => "uint16",
            .int8 => "int8",
            .int16 => "int16",
            .packed_arrays => "uint8",
        };
    }
};

pub const Asset = struct {
    name: []const u8,
    kind: Kind,
    data: []const u8,
};

const kHeaderSize = 88;

/// Serialises assets in the order given. Order is part of the format: the
/// game refers to assets by index, so it has to match what the headers say.
pub fn write(alloc: std.mem.Allocator, assets: []const Asset) ![]u8 {
    var names: std.ArrayList(u8) = .empty;
    defer names.deinit(alloc);
    for (assets) |a| {
        try names.appendSlice(alloc, a.name);
        try names.append(alloc, 0);
    }

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(names.items, &digest, .{});

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    try out.appendSlice(alloc, kSignature);
    try out.appendSlice(alloc, &digest);
    try out.appendNTimes(alloc, 0, 32);
    try appendU32(alloc, &out, @intCast(assets.len));
    try appendU32(alloc, &out, @intCast(names.items.len));
    std.debug.assert(out.items.len == kHeaderSize);

    for (assets) |a| try appendU32(alloc, &out, @intCast(a.data.len));
    try out.appendSlice(alloc, names.items);

    for (assets) |a| {
        while (out.items.len & 3 != 0) try out.append(alloc, 0);
        try out.appendSlice(alloc, a.data);
    }

    return out.toOwnedSlice(alloc);
}

fn appendU32(alloc: std.mem.Allocator, out: *std.ArrayList(u8), v: u32) !void {
    try out.appendSlice(alloc, std.mem.asBytes(&v));
}

fn readU32(bytes: []const u8, off: usize) u32 {
    return std.mem.bytesToValue(u32, bytes[off..][0..4]);
}

/// One asset as it appears in an existing file. `data` points into `bytes`.
pub const Entry = struct {
    name: []const u8,
    data: []const u8,
};

pub const Contents = struct {
    entries: []Entry,

    pub fn deinit(self: *Contents, alloc: std.mem.Allocator) void {
        alloc.free(self.entries);
        self.* = undefined;
    }

    pub fn find(self: Contents, name: []const u8) ?[]const u8 {
        for (self.entries) |e| {
            if (std.mem.eql(u8, e.name, name)) return e.data;
        }
        return null;
    }
};

/// Parses a container. The kinds are not stored in the file, so they do not
/// come back - only names and payloads, which is what a comparison needs.
pub fn read(alloc: std.mem.Allocator, bytes: []const u8) !Contents {
    if (bytes.len < kHeaderSize) return error.TooShort;
    if (!std.mem.eql(u8, bytes[0..kSignature.len], kSignature)) return error.BadSignature;

    const count = readU32(bytes, 80);
    const names_len = readU32(bytes, 84);

    const sizes_end = kHeaderSize + @as(usize, count) * 4;
    const names_end = sizes_end + names_len;
    if (names_end > bytes.len) return error.Truncated;

    const names = bytes[sizes_end..names_end];
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(names, &digest, .{});
    if (!std.mem.eql(u8, bytes[16..48], &digest)) return error.NameHashMismatch;

    const entries = try alloc.alloc(Entry, count);
    errdefer alloc.free(entries);

    var name_pos: usize = 0;
    var pos = names_end;
    for (entries, 0..) |*e, i| {
        const end = std.mem.indexOfScalarPos(u8, names, name_pos, 0) orelse return error.BadNameTable;
        e.name = names[name_pos..end];
        name_pos = end + 1;

        const size = readU32(bytes, kHeaderSize + i * 4);
        pos = std.mem.alignForward(usize, pos, 4);
        if (pos + size > bytes.len) return error.Truncated;
        e.data = bytes[pos..][0..size];
        pos += size;
    }
    if (name_pos != names.len) return error.BadNameTable;

    return .{ .entries = entries };
}

const testing = std.testing;

test "a container round-trips through write and read" {
    const alloc = testing.allocator;
    const assets = [_]Asset{
        .{ .name = "kFirst", .kind = .uint8, .data = &.{ 1, 2, 3 } },
        .{ .name = "kSecond", .kind = .uint16, .data = &.{ 4, 5 } },
        .{ .name = "kEmpty", .kind = .uint8, .data = &.{} },
    };

    const bytes = try write(alloc, &assets);
    defer alloc.free(bytes);

    var contents = try read(alloc, bytes);
    defer contents.deinit(alloc);

    try testing.expectEqual(@as(usize, 3), contents.entries.len);
    try testing.expectEqualStrings("kFirst", contents.entries[0].name);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, contents.entries[0].data);
    try testing.expectEqualSlices(u8, &.{ 4, 5 }, contents.entries[1].data);
    try testing.expectEqual(@as(usize, 0), contents.entries[2].data.len);
}

test "payloads start on four byte boundaries" {
    const alloc = testing.allocator;
    // Three bytes, so the next payload only lands right if it is padded.
    const assets = [_]Asset{
        .{ .name = "a", .kind = .uint8, .data = &.{ 1, 2, 3 } },
        .{ .name = "b", .kind = .uint8, .data = &.{9} },
    };
    const bytes = try write(alloc, &assets);
    defer alloc.free(bytes);

    var contents = try read(alloc, bytes);
    defer contents.deinit(alloc);
    try testing.expectEqualSlices(u8, &.{9}, contents.entries[1].data);

    const base = @intFromPtr(bytes.ptr);
    try testing.expectEqual(@as(usize, 0), (@intFromPtr(contents.entries[1].data.ptr) - base) & 3);
}

test "a corrupted name table is rejected" {
    const alloc = testing.allocator;
    const assets = [_]Asset{.{ .name = "kOnly", .kind = .uint8, .data = &.{7} }};
    const bytes = try write(alloc, &assets);
    defer alloc.free(bytes);

    bytes[16] ^= 0xff; // flip a bit in the stored hash
    try testing.expectError(error.NameHashMismatch, read(alloc, bytes));
}

// The built file is not in the repository - it is made from a ROM the user
// supplies - so this only runs when one happens to be lying around.
test "a built zelda3_assets.dat re-serialises to the same bytes" {
    const alloc = testing.allocator;
    const path = "zig-out/bin/zelda3_assets.dat";
    if (!fileio.exists(path)) return error.SkipZigTest;

    const original = try fileio.readWholeFile(alloc, path);
    defer alloc.free(original);

    var contents = try read(alloc, original);
    defer contents.deinit(alloc);

    const assets = try alloc.alloc(Asset, contents.entries.len);
    defer alloc.free(assets);
    for (assets, contents.entries) |*a, e|
        a.* = .{ .name = e.name, .kind = .uint8, .data = e.data };

    const rebuilt = try write(alloc, assets);
    defer alloc.free(rebuilt);

    try testing.expectEqual(original.len, rebuilt.len);
    try testing.expectEqualSlices(u8, original, rebuilt);
}
