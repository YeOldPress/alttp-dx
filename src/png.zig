//! PNG, enough for the exported sprite sheets, fonts and Link's graphics.
//!
//! Reading takes what image editors save: indexed, grayscale, RGB and RGBA,
//! at 1, 2, 4 or 8 bits a sample, with every row filter. Interlaced and 16
//! bit images are refused with a message saying so. Writing produces indexed,
//! RGB or grayscale images, compressed with the standard library's deflate.
const std = @import("std");
const flate = std.compress.flate;

pub const Kind = enum { indexed, gray, rgb, rgba };

pub const Image = struct {
    width: u32,
    height: u32,
    kind: Kind,
    /// Rows of `width` samples, one byte each channel: an index for indexed
    /// images, a level for gray, three or four bytes for RGB and RGBA.
    pixels: []u8,
    /// The palette of an indexed image, empty otherwise.
    palette: [][3]u8,

    pub fn deinit(self: *Image, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
        alloc.free(self.palette);
        self.* = undefined;
    }

    pub fn channels(self: Image) usize {
        return switch (self.kind) {
            .indexed, .gray => 1,
            .rgb => 3,
            .rgba => 4,
        };
    }

    /// The pixel at x, y as 0x00RRGGBB, whatever kind of image it is.
    pub fn rgbAt(self: Image, x: usize, y: usize) u32 {
        const i = y * self.width + x;
        return switch (self.kind) {
            .indexed => blk: {
                const idx = self.pixels[i];
                if (idx >= self.palette.len) break :blk 0;
                const p = self.palette[idx];
                break :blk @as(u32, p[0]) << 16 | @as(u32, p[1]) << 8 | p[2];
            },
            .gray => @as(u32, self.pixels[i]) * 0x010101,
            .rgb, .rgba => blk: {
                const c = self.channels();
                const p = self.pixels[i * c ..];
                break :blk @as(u32, p[0]) << 16 | @as(u32, p[1]) << 8 | p[2];
            },
        };
    }
};

pub const DecodeError = error{ NotPng, Corrupt, Unsupported, OutOfMemory };

const kSignature = "\x89PNG\r\n\x1a\n";

pub fn decode(alloc: std.mem.Allocator, bytes: []const u8) DecodeError!Image {
    if (!std.mem.startsWith(u8, bytes, kSignature)) return error.NotPng;
    var pos: usize = kSignature.len;
    var width: u32 = 0;
    var height: u32 = 0;
    var depth: u8 = 0;
    var color: u8 = 0;
    var palette: std.ArrayList([3]u8) = .empty;
    errdefer palette.deinit(alloc);
    var idat: std.ArrayList(u8) = .empty;
    defer idat.deinit(alloc);

    while (pos + 12 <= bytes.len) {
        const len = std.mem.readInt(u32, bytes[pos..][0..4], .big);
        const kind = bytes[pos + 4 ..][0..4];
        if (pos + 12 + len > bytes.len) return error.Corrupt;
        const data = bytes[pos + 8 ..][0..len];
        pos += 12 + len;
        if (std.mem.eql(u8, kind, "IHDR")) {
            if (len < 13) return error.Corrupt;
            width = std.mem.readInt(u32, data[0..4], .big);
            height = std.mem.readInt(u32, data[4..8], .big);
            depth = data[8];
            color = data[9];
            if (data[12] != 0) return error.Unsupported; // interlaced
        } else if (std.mem.eql(u8, kind, "PLTE")) {
            var i: usize = 0;
            while (i + 3 <= data.len) : (i += 3) try palette.append(alloc, .{ data[i], data[i + 1], data[i + 2] });
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            try idat.appendSlice(alloc, data);
        } else if (std.mem.eql(u8, kind, "IEND")) break;
    }
    if (width == 0 or height == 0) return error.Corrupt;
    if (depth == 16) return error.Unsupported;
    const out_kind: Kind, const samples: usize = switch (color) {
        0 => .{ .gray, 1 },
        2 => .{ .rgb, 3 },
        3 => .{ .indexed, 1 },
        4 => .{ .rgba, 2 }, // gray + alpha, widened below
        6 => .{ .rgba, 4 },
        else => return error.Unsupported,
    };
    if (depth != 8 and !(depth < 8 and (color == 0 or color == 3))) return error.Unsupported;

    // Inflate the image data.
    var input = std.Io.Reader.fixed(idat.items);
    var window: [flate.max_window_len]u8 = undefined;
    var inflater = flate.Decompress.init(&input, .zlib, &window);
    const bits_per_pixel = samples * depth;
    const stride = (width * bits_per_pixel + 7) / 8;
    const raw_len = (stride + 1) * height;
    const raw = try alloc.alloc(u8, raw_len);
    defer alloc.free(raw);
    inflater.reader.readSliceAll(raw) catch return error.Corrupt;

    // Undo the row filters in place.
    const bpp = @max(1, bits_per_pixel / 8);
    var prev: ?[]u8 = null;
    for (0..height) |y| {
        const row = raw[y * (stride + 1) + 1 ..][0..stride];
        const filter = raw[y * (stride + 1)];
        for (row, 0..) |*b, i| {
            const left: u8 = if (i >= bpp) row[i - bpp] else 0;
            const up: u8 = if (prev) |p| p[i] else 0;
            const up_left: u8 = if (prev != null and i >= bpp) prev.?[i - bpp] else 0;
            b.* +%= switch (filter) {
                0 => 0,
                1 => left,
                2 => up,
                3 => @intCast((@as(u16, left) + up) / 2),
                4 => paeth(left, up, up_left),
                else => return error.Corrupt,
            };
        }
        prev = row;
    }

    // Widen to one byte a sample.
    const out_channels: usize = switch (out_kind) {
        .indexed, .gray => 1,
        .rgb => 3,
        .rgba => 4,
    };
    const pixels = try alloc.alloc(u8, @as(usize, width) * height * out_channels);
    errdefer alloc.free(pixels);
    for (0..height) |y| {
        const row = raw[y * (stride + 1) + 1 ..][0..stride];
        for (0..width) |x| {
            const o = (y * width + x) * out_channels;
            if (depth < 8) {
                const bit = x * depth;
                const shift: u3 = @intCast(8 - depth - (bit % 8));
                const v = (row[bit / 8] >> shift) & ((@as(u8, 1) << @intCast(depth)) - 1);
                // Gray scales up to 0..255; an index stays an index.
                pixels[o] = if (color == 0) @intCast(@as(u16, v) * 255 / ((@as(u16, 1) << @intCast(depth)) - 1)) else v;
            } else if (color == 4) {
                const g = row[x * 2];
                pixels[o..][0..4].* = .{ g, g, g, row[x * 2 + 1] };
            } else {
                @memcpy(pixels[o..][0..out_channels], row[x * out_channels ..][0..out_channels]);
            }
        }
    }
    return .{ .width = width, .height = height, .kind = out_kind, .pixels = pixels, .palette = try palette.toOwnedSlice(alloc) };
}

fn paeth(a: u8, b: u8, c: u8) u8 {
    const p: i16 = @as(i16, a) + b - c;
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

/// Encodes an image. For indexed images `palette` is written as PLTE.
pub fn encode(alloc: std.mem.Allocator, width: u32, height: u32, kind: Kind, pixels: []const u8, palette: []const [3]u8) ![]u8 {
    const channels: usize = switch (kind) {
        .indexed, .gray => 1,
        .rgb => 3,
        .rgba => 4,
    };
    std.debug.assert(pixels.len == @as(usize, width) * height * channels);

    // Filter type 0 on every row: the deflate after it does the real work.
    const stride = width * channels;
    const raw = try alloc.alloc(u8, (stride + 1) * height);
    defer alloc.free(raw);
    for (0..height) |y| {
        raw[y * (stride + 1)] = 0;
        @memcpy(raw[y * (stride + 1) + 1 ..][0..stride], pixels[y * stride ..][0..stride]);
    }

    // The compressor wants some room in its output from the start.
    var compressed = try std.Io.Writer.Allocating.initCapacity(alloc, 4096);
    defer compressed.deinit();
    {
        var window: [flate.max_window_len]u8 = undefined;
        var deflater = try flate.Compress.init(&compressed.writer, &window, .zlib, .default);
        try deflater.writer.writeAll(raw);
        try deflater.finish();
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, kSignature);
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);
    std.mem.writeInt(u32, ihdr[4..8], height, .big);
    ihdr[8] = 8;
    ihdr[9] = switch (kind) {
        .gray => 0,
        .rgb => 2,
        .indexed => 3,
        .rgba => 6,
    };
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try chunk(alloc, &out, "IHDR", &ihdr);
    if (kind == .indexed) try chunk(alloc, &out, "PLTE", std.mem.sliceAsBytes(palette));
    try chunk(alloc, &out, "IDAT", compressed.written());
    try chunk(alloc, &out, "IEND", "");
    return out.toOwnedSlice(alloc);
}

fn chunk(alloc: std.mem.Allocator, out: *std.ArrayList(u8), kind: *const [4]u8, data: []const u8) !void {
    var len: [4]u8 = undefined;
    std.mem.writeInt(u32, &len, @intCast(data.len), .big);
    try out.appendSlice(alloc, &len);
    try out.appendSlice(alloc, kind);
    try out.appendSlice(alloc, data);
    var crc = std.hash.Crc32.init();
    crc.update(kind);
    crc.update(data);
    var crc_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_bytes, crc.final(), .big);
    try out.appendSlice(alloc, &crc_bytes);
}

test "an indexed image survives a round trip" {
    const alloc = std.testing.allocator;
    const pixels = [_]u8{ 0, 1, 2, 3, 3, 2, 1, 0, 1, 1, 2, 2 };
    const pal = [_][3]u8{ .{ 0, 0, 0 }, .{ 255, 0, 0 }, .{ 0, 255, 0 }, .{ 0, 0, 255 } };
    const bytes = try encode(alloc, 4, 3, .indexed, &pixels, &pal);
    defer alloc.free(bytes);
    var img = try decode(alloc, bytes);
    defer img.deinit(alloc);
    try std.testing.expectEqual(Kind.indexed, img.kind);
    try std.testing.expectEqualSlices(u8, &pixels, img.pixels);
    try std.testing.expectEqual(@as(u32, 0xff0000), img.rgbAt(1, 0));
}

test "an RGB image survives a round trip" {
    const alloc = std.testing.allocator;
    var pixels: [5 * 4 * 3]u8 = undefined;
    for (&pixels, 0..) |*p, i| p.* = @truncate(i * 37);
    const bytes = try encode(alloc, 5, 4, .rgb, &pixels, &.{});
    defer alloc.free(bytes);
    var img = try decode(alloc, bytes);
    defer img.deinit(alloc);
    try std.testing.expectEqualSlices(u8, &pixels, img.pixels);
}
