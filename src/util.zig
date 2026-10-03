//! Port of util.c. Everything here keeps the C ABI and the C allocator, since
//! the still-unported C code frees these pointers itself.
const std = @import("std");

pub const ByteArray = extern struct {
    data: ?[*]u8,
    size: usize,
    capacity: usize,
};

pub const MemBlk = extern struct {
    ptr: ?[*]const u8,
    size: usize,
};

const empty_blk = MemBlk{ .ptr = null, .size = 0 };

extern fn malloc(size: usize) ?*anyopaque;
extern fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern fn strlen(s: [*:0]const u8) usize;
extern fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]u8;
extern fn memchr(s: [*]const u8, ch: c_int, n: usize) ?[*]u8;
extern fn memcpy(dst: [*]u8, src: [*]const u8, n: usize) [*]u8;
extern fn memcmp(a: [*]const u8, b: [*]const u8, n: usize) c_int;
extern fn Die(err: [*:0]const u8) noreturn;

const FILE = opaque {};
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern fn fseek(f: *FILE, off: c_long, whence: c_int) c_int;
extern fn ftell(f: *FILE) c_long;
extern fn rewind(f: *FILE) void;
extern fn fread(buf: [*]u8, size: usize, n: usize, f: *FILE) usize;
extern fn fclose(f: *FILE) c_int;
const SEEK_END = 2;

/// The BPS format and every target this game runs on are little endian.
fn read16(p: [*]const u8) u16 {
    return std.mem.readInt(u16, p[0..2], .little);
}

fn read32(p: [*]const u8) u32 {
    return std.mem.readInt(u32, p[0..4], .little);
}

pub export fn NextDelim(s: *?[*:0]u8, sep: c_int) callconv(.c) ?[*:0]u8 {
    var r = s.* orelse return null;
    while (r[0] == ' ' or r[0] == '\t') r += 1;
    if (strchr(r, sep)) |t| {
        t[0] = 0;
        s.* = t + 1;
    } else {
        s.* = null;
    }
    return r;
}

fn toLower(a: c_int) c_int {
    return a + @as(c_int, if (a >= 'A' and a <= 'Z') 32 else 0);
}

pub export fn StringEqualsNoCase(a_in: [*:0]const u8, b_in: [*:0]const u8) callconv(.c) bool {
    var a = a_in;
    var b = b_in;
    while (true) {
        const aa = toLower(a[0]);
        const bb = toLower(b[0]);
        a += 1;
        b += 1;
        if (aa != bb) return false;
        if (aa == 0) return true;
    }
}

pub export fn StringStartsWithNoCase(a_in: [*:0]const u8, b_in: [*:0]const u8) callconv(.c) ?[*:0]const u8 {
    var a = a_in;
    var b = b_in;
    while (true) : ({
        a += 1;
        b += 1;
    }) {
        const aa = toLower(a[0]);
        const bb = toLower(b[0]);
        if (bb == 0) return a;
        if (aa != bb) return null;
    }
}

pub export fn ReadWholeFile(name: [*:0]const u8, length: ?*usize) callconv(.c) ?[*]u8 {
    const f = fopen(name, "rb") orelse return null;
    _ = fseek(f, 0, SEEK_END);
    const size: usize = @intCast(ftell(f));
    rewind(f);
    const buffer: [*]u8 = @ptrCast(malloc(size + 1) orelse Die("malloc failed"));
    // Always zero terminate so this function can be used also for strings.
    buffer[size] = 0;
    if (fread(buffer, 1, size, f) != size) Die("fread failed");
    _ = fclose(f);
    if (length) |l| l.* = size;
    return buffer;
}

pub export fn NextLineStripComments(s: *?[*:0]u8) callconv(.c) ?[*:0]u8 {
    var p = s.* orelse return null;
    // find end of line
    var eol = if (strchr(p, '\n')) |nl| blk: {
        s.* = nl + 1;
        break :blk nl;
    } else blk: {
        s.* = null;
        break :blk p + strlen(p);
    };
    // strip comments
    if (memchr(p, '#', @intFromPtr(eol) - @intFromPtr(p))) |comment| {
        eol = @ptrCast(comment);
    }
    // strip trailing whitespace
    while (@intFromPtr(eol) > @intFromPtr(p) and
        ((eol - 1)[0] == '\r' or (eol - 1)[0] == ' ' or (eol - 1)[0] == '\t')) eol -= 1;
    eol[0] = 0;
    // strip leading whitespace
    while (p[0] == ' ' or p[0] == '\t') p += 1;
    return p;
}

/// Return the next possibly quoted string, space separated, or the empty string
pub export fn NextPossiblyQuotedString(s: *[*:0]u8) callconv(.c) [*:0]u8 {
    var r = s.*;
    while (r[0] == ' ' or r[0] == '\t') r += 1;
    var t = r;
    if (r[0] == '"') {
        r += 1;
        t = r;
        while (t[0] != 0 and t[0] != '"') t += 1;
    } else {
        while (t[0] != 0 and t[0] != ' ' and t[0] != '\t') t += 1;
    }
    if (t[0] != 0) {
        t[0] = 0;
        t += 1;
    }
    while (t[0] == ' ' or t[0] == '\t') t += 1;
    s.* = t;
    return r;
}

pub export fn ReplaceFilenameWithNewPath(old_path: [*:0]const u8, new_path: [*:0]const u8) callconv(.c) ?[*]u8 {
    var olen = strlen(old_path);
    const nlen = strlen(new_path) + 1;
    while (olen != 0 and old_path[olen - 1] != '/' and old_path[olen - 1] != '\\') olen -= 1;
    const result: [*]u8 = @ptrCast(malloc(olen + nlen) orelse return null);
    _ = memcpy(result, old_path, olen);
    _ = memcpy(result + olen, new_path, nlen);
    return result;
}

pub export fn SplitKeyValue(p: [*:0]u8) callconv(.c) ?[*:0]u8 {
    const equals = strchr(p, '=') orelse return null;
    var kr = equals;
    while (@intFromPtr(kr) > @intFromPtr(p) and ((kr - 1)[0] == ' ' or (kr - 1)[0] == '\t')) kr -= 1;
    kr[0] = 0;
    var v = equals + 1;
    while (v[0] == ' ' or v[0] == '\t') v += 1;
    return v;
}

pub export fn SkipPrefix(big_in: [*:0]const u8, little_in: [*:0]const u8) callconv(.c) ?[*:0]const u8 {
    var big = big_in;
    var little = little_in;
    while (little[0] != 0) : ({
        big += 1;
        little += 1;
    }) {
        if (little[0] != big[0]) return null;
    }
    return big;
}

pub export fn StrSet(rv: *?[*:0]u8, s: [*:0]const u8) callconv(.c) void {
    const news = strdup(s);
    const old = rv.*;
    rv.* = news;
    free(old);
}

pub export fn ByteArray_Resize(arr: *ByteArray, new_size: usize) callconv(.c) void {
    arr.size = new_size;
    if (new_size > arr.capacity) {
        const minsize = arr.capacity + (arr.capacity >> 1) + 8;
        arr.capacity = if (new_size < minsize) minsize else new_size;
        const data = realloc(arr.data, arr.capacity) orelse Die("memory allocation failed");
        arr.data = @ptrCast(data);
    }
}

pub export fn ByteArray_Destroy(arr: *ByteArray) callconv(.c) void {
    const data = arr.data;
    arr.data = null;
    free(data);
}

pub export fn ByteArray_AppendData(arr: *ByteArray, data: [*]const u8, data_size: usize) callconv(.c) void {
    ByteArray_Resize(arr, arr.size + data_size);
    // Appending nothing to an array that never allocated leaves data null, and
    // the C memcpys 0 bytes through it without caring. Unwrapping would panic.
    if (data_size == 0) return;
    _ = memcpy(arr.data.? + arr.size - data_size, data, data_size);
}

pub export fn ByteArray_AppendByte(arr: *ByteArray, v: u8) callconv(.c) void {
    ByteArray_Resize(arr, arr.size + 1);
    arr.data.?[arr.size - 1] = v;
}

/// Automatically selects between 16 or 32 bit indexes. Can hold up to 8192 elements in 16-bit mode.
pub export fn FindIndexInMemblk(data: MemBlk, i: usize) callconv(.c) MemBlk {
    if (data.size < 2) return empty_blk;
    const ptr = data.ptr.?;
    const end = data.size - 2;
    var left_off: usize = undefined;
    var right_off: usize = undefined;
    var mx: usize = read16(ptr + end);
    if (mx < 8192) {
        if (i > mx or mx * 2 > end) return empty_blk;
        left_off = if (i == 0) mx * 2 else mx * 2 + read16(ptr + i * 2 - 2);
        right_off = if (i == mx) end else mx * 2 + read16(ptr + i * 2);
    } else {
        mx -= 8192;
        if (i > mx or mx * 4 > end) return empty_blk;
        left_off = if (i == 0) mx * 4 else mx * 4 + read32(ptr + i * 4 - 4);
        right_off = if (i == mx) end else mx * 4 + read32(ptr + i * 4);
    }
    if (left_off > right_off or right_off > end) return empty_blk;
    return .{ .ptr = ptr + left_off, .size = right_off - left_off };
}

fn bpsDecodeInt(src: *[*]const u8) u64 {
    var data: u64 = 0;
    var shift: u64 = 1;
    while (true) {
        const x = src.*[0];
        src.* += 1;
        data +%= @as(u64, x & 0x7f) *% shift;
        if (x & 0x80 != 0) break;
        shift *%= 128;
        data +%= shift;
    }
    return data;
}

const crc32_polynomial: u32 = 0xEDB88320;

fn crc32(data: [*]const u8, length: usize) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data[0..length]) |byte| {
        crc ^= byte;
        for (0..8) |_| {
            crc = (crc >> 1) ^ ((crc & 1) *% crc32_polynomial);
        }
    }
    return crc ^ 0xFFFFFFFF;
}

pub export fn ApplyBps(
    src: [*]const u8,
    src_size_in: usize,
    bps_in: [*]const u8,
    bps_size: usize,
    length_out: *usize,
) callconv(.c) ?[*]u8 {
    var bps = bps_in;
    const bps_end = bps + bps_size - 12;

    if (memcmp(bps, "BPS1", 4) != 0) return null;
    if (crc32(src, src_size_in) != read32(bps_end)) return null;
    if (crc32(bps, bps_size - 4) != read32(bps_end + 8)) return null;

    bps += 4;
    const src_size = bpsDecodeInt(&bps);
    const dst_size: u32 = @truncate(bpsDecodeInt(&bps));
    _ = bpsDecodeInt(&bps); // meta_size
    var output_offset: u32 = 0;
    var source_relative_offset: u32 = 0;
    var target_relative_offset: u32 = 0;
    if (src_size != src_size_in) return null;
    length_out.* = dst_size;
    const dst: [*]u8 = @ptrCast(malloc(dst_size) orelse return null);
    while (@intFromPtr(bps) < @intFromPtr(bps_end)) {
        var cmd: u32 = @truncate(bpsDecodeInt(&bps));
        var length = (cmd >> 2) + 1;
        switch (cmd & 3) {
            0 => while (length != 0) : (length -= 1) {
                dst[output_offset] = src[output_offset];
                output_offset += 1;
            },
            1 => while (length != 0) : (length -= 1) {
                dst[output_offset] = bps[0];
                bps += 1;
                output_offset += 1;
            },
            2 => {
                cmd = @truncate(bpsDecodeInt(&bps));
                source_relative_offset = applyRelativeOffset(source_relative_offset, cmd);
                while (length != 0) : (length -= 1) {
                    dst[output_offset] = src[source_relative_offset];
                    source_relative_offset += 1;
                    output_offset += 1;
                }
            },
            else => {
                cmd = @truncate(bpsDecodeInt(&bps));
                target_relative_offset = applyRelativeOffset(target_relative_offset, cmd);
                while (length != 0) : (length -= 1) {
                    dst[output_offset] = dst[target_relative_offset];
                    target_relative_offset += 1;
                    output_offset += 1;
                }
            },
        }
    }
    if (dst_size != output_offset) return null;
    if (crc32(dst, dst_size) != read32(bps_end + 4)) return null;
    return dst;
}

fn applyRelativeOffset(offset: u32, cmd: u32) u32 {
    return if (cmd & 1 != 0) offset -% (cmd >> 1) else offset +% (cmd >> 1);
}

const testing = std.testing;

test "NextDelim trims leading blanks and consumes the separator" {
    var buf = "  ab, cd".*;
    var p: ?[*:0]u8 = &buf;
    try testing.expectEqualStrings("ab", std.mem.span(NextDelim(&p, ',').?));
    try testing.expectEqualStrings("cd", std.mem.span(NextDelim(&p, ',').?));
    try testing.expect(p == null);
    try testing.expect(NextDelim(&p, ',') == null);
}

test "case insensitive compares" {
    try testing.expect(StringEqualsNoCase("Fullscreen", "fullSCREEN"));
    try testing.expect(!StringEqualsNoCase("Full", "Fully"));
    try testing.expectEqualStrings("e", std.mem.span(StringStartsWithNoCase("Ctrl+e", "CTRL+").?));
    try testing.expect(StringStartsWithNoCase("Ctrl+e", "Shift+") == null);
}

test "SkipPrefix" {
    try testing.expectEqualStrings("file.ini", std.mem.span(SkipPrefix("include file.ini", "include ").?));
    try testing.expect(SkipPrefix("include", "exclude") == null);
}

test "NextLineStripComments strips comments and surrounding blanks" {
    var buf = "  Key = Value \t # a comment\nsecond\r\n".*;
    var p: ?[*:0]u8 = &buf;
    try testing.expectEqualStrings("Key = Value", std.mem.span(NextLineStripComments(&p).?));
    try testing.expectEqualStrings("second", std.mem.span(NextLineStripComments(&p).?));
    try testing.expectEqualStrings("", std.mem.span(NextLineStripComments(&p).?));
    try testing.expect(NextLineStripComments(&p) == null);
}

test "SplitKeyValue" {
    var buf = "WindowScale \t = 3".*;
    const v = SplitKeyValue(&buf).?;
    try testing.expectEqualStrings("3", std.mem.span(v));
    try testing.expectEqualStrings("WindowScale", std.mem.span(@as([*:0]u8, &buf)));

    var no_equals = "WindowScale".*;
    try testing.expect(SplitKeyValue(&no_equals) == null);
}

test "NextPossiblyQuotedString handles quotes and spacing" {
    var buf = "\"my file.ini\"  rest".*;
    var p: [*:0]u8 = &buf;
    try testing.expectEqualStrings("my file.ini", std.mem.span(NextPossiblyQuotedString(&p)));
    try testing.expectEqualStrings("rest", std.mem.span(NextPossiblyQuotedString(&p)));
    try testing.expectEqualStrings("", std.mem.span(NextPossiblyQuotedString(&p)));
}

test "ReplaceFilenameWithNewPath keeps the directory part" {
    const r = ReplaceFilenameWithNewPath("cfg/sub/zelda3.ini", "other.ini").?;
    defer free(r);
    try testing.expectEqualStrings("cfg/sub/other.ini", std.mem.span(@as([*:0]u8, @ptrCast(r))));

    const bare = ReplaceFilenameWithNewPath("zelda3.ini", "other.ini").?;
    defer free(bare);
    try testing.expectEqualStrings("other.ini", std.mem.span(@as([*:0]u8, @ptrCast(bare))));
}

test "ByteArray grows and keeps its contents" {
    var arr = ByteArray{ .data = null, .size = 0, .capacity = 0 };
    defer ByteArray_Destroy(&arr);
    ByteArray_AppendData(&arr, "hello", 5);
    ByteArray_AppendByte(&arr, ' ');
    for (0..100) |i| ByteArray_AppendByte(&arr, @intCast('a' + i % 26));
    try testing.expectEqual(@as(usize, 106), arr.size);
    try testing.expect(arr.capacity >= arr.size);
    try testing.expectEqualStrings("hello a", arr.data.?[0..7]);
    try testing.expectEqual(@as(u8, 'a' + 99 % 26), arr.data.?[105]);
}

test "FindIndexInMemblk reads a 16-bit index" {
    // Two-entry offset table, then the payloads, then the entry count.
    const blob = [_]u8{ 3, 0, 5, 0, 'a', 'b', 'c', 'd', 'e', 'f', 'g', 2, 0 };
    const data = MemBlk{ .ptr = &blob, .size = blob.len };
    const first = FindIndexInMemblk(data, 0);
    try testing.expectEqualStrings("abc", first.ptr.?[0..first.size]);
    const second = FindIndexInMemblk(data, 1);
    try testing.expectEqualStrings("de", second.ptr.?[0..second.size]);
    const last = FindIndexInMemblk(data, 2);
    try testing.expectEqualStrings("fg", last.ptr.?[0..last.size]);
    // Out of range and degenerate inputs give an empty block rather than garbage.
    try testing.expectEqual(@as(usize, 0), FindIndexInMemblk(data, 3).size);
    try testing.expectEqual(@as(usize, 0), FindIndexInMemblk(.{ .ptr = &blob, .size = 1 }, 0).size);
}

test "crc32 matches the standard check value" {
    try testing.expectEqual(@as(u32, 0xCBF43926), crc32("123456789", 9));
}

test "bpsDecodeInt" {
    const one = [_]u8{0x81};
    var p: [*]const u8 = &one;
    try testing.expectEqual(@as(u64, 1), bpsDecodeInt(&p));

    const onetwentyeight = [_]u8{ 0x00, 0x80 };
    p = &onetwentyeight;
    try testing.expectEqual(@as(u64, 128), bpsDecodeInt(&p));
}

test "ApplyBps applies source read, target read and source copy" {
    const src = "ABCDEFGH";
    var patch = [_]u8{
        'B', 'P', 'S', '1',
        0x88, // source size 8
        0x88, // target size 8
        0x80, // metadata size 0
        0x8C, // SourceRead, length 4 -> "ABCD"
        0x85, 'X', 'Y', // TargetRead, length 2 -> "XY"
        0x86, 0x8C, // SourceCopy, length 2, offset +6 -> "GH"
        0, 0, 0, 0, // source crc
        0, 0, 0, 0, // target crc
        0, 0, 0, 0, // patch crc
    };
    const footer = patch.len - 12;
    std.mem.writeInt(u32, patch[footer..][0..4], crc32(src, 8), .little);
    std.mem.writeInt(u32, patch[footer + 4 ..][0..4], crc32("ABCDXYGH", 8), .little);
    std.mem.writeInt(u32, patch[footer + 8 ..][0..4], crc32(&patch, patch.len - 4), .little);

    var out_len: usize = 0;
    const out = ApplyBps(src, 8, &patch, patch.len, &out_len).?;
    defer free(out);
    try testing.expectEqual(@as(usize, 8), out_len);
    try testing.expectEqualStrings("ABCDXYGH", out[0..out_len]);
}

test "ApplyBps rejects a patch whose source does not match" {
    var patch = [_]u8{ 'N', 'O', 'P', 'E' } ++ @as([12]u8, @splat(0));
    var out_len: usize = 0;
    try testing.expect(ApplyBps("ABCDEFGH", 8, &patch, patch.len, &out_len) == null);
}
