//! Renders game frames to an image without a window, for looking at screens
//! while working on them: `zelda3 --render <ref> <script> <out.bmp>`.
//!
//! <ref> picks one of the chapter snapshots in saves/ref (0 to 12). <script>
//! is a comma separated list of steps, each a number of frames and optionally
//! the buttons held for them: `60,1:start,20,1:select,30` waits a second, taps
//! Start, waits, taps Select and waits again. Buttons are a, b, x, y, l, r,
//! up, down, left, right, start and select, joined with +. The last frame is
//! written as a 24-bit BMP.
const std = @import("std");
const fileio = @import("fileio.zig");

/// Joypad bits in the order ZeldaRunFrame takes them.
const kButtons = [_]struct { name: []const u8, bit: u5 }{
    .{ .name = "b", .bit = 0 },     .{ .name = "y", .bit = 1 },
    .{ .name = "select", .bit = 2 }, .{ .name = "start", .bit = 3 },
    .{ .name = "up", .bit = 4 },    .{ .name = "down", .bit = 5 },
    .{ .name = "left", .bit = 6 },  .{ .name = "right", .bit = 7 },
    .{ .name = "a", .bit = 8 },     .{ .name = "x", .bit = 9 },
    .{ .name = "l", .bit = 10 },    .{ .name = "r", .bit = 11 },
};

pub const Step = struct { frames: u32, buttons: c_int };

/// Parses one step of a script, such as `20` or `1:start+a`.
pub fn parseStep(text: []const u8) !Step {
    const colon = std.mem.indexOfScalar(u8, text, ':');
    const frames = try std.fmt.parseInt(u32, if (colon) |p| text[0..p] else text, 10);
    var buttons: c_int = 0;
    if (colon) |p| {
        var it = std.mem.tokenizeScalar(u8, text[p + 1 ..], '+');
        while (it.next()) |name| {
            const b = for (kButtons) |k| {
                if (std.mem.eql(u8, k.name, name)) break k;
            } else return error.UnknownButton;
            buttons |= @as(c_int, 1) << b.bit;
        }
    }
    return .{ .frames = frames, .buttons = buttons };
}

/// Writes 0x00RRGGBB pixels as a bottom-up 24-bit BMP.
pub fn writeBmp(path: [*:0]const u8, pixels: []const u32, width: usize, height: usize) !void {
    const row = (width * 3 + 3) & ~@as(usize, 3);
    const size = 54 + row * height;
    const alloc = std.heap.c_allocator;
    const out = try alloc.alloc(u8, size);
    defer alloc.free(out);
    @memset(out, 0);
    out[0] = 'B';
    out[1] = 'M';
    std.mem.writeInt(u32, out[2..6], @intCast(size), .little);
    std.mem.writeInt(u32, out[10..14], 54, .little);
    std.mem.writeInt(u32, out[14..18], 40, .little);
    std.mem.writeInt(i32, out[18..22], @intCast(width), .little);
    std.mem.writeInt(i32, out[22..26], @intCast(height), .little);
    std.mem.writeInt(u16, out[26..28], 1, .little);
    std.mem.writeInt(u16, out[28..30], 24, .little);
    for (0..height) |y| {
        const dst = out[54 + (height - 1 - y) * row ..];
        for (0..width) |x| {
            const p = pixels[y * width + x];
            dst[x * 3 + 0] = @truncate(p);
            dst[x * 3 + 1] = @truncate(p >> 8);
            dst[x * 3 + 2] = @truncate(p >> 16);
        }
    }
    try fileio.writeWholeFile(path, out);
}

test "script steps parse into frame counts and joypad bits" {
    try std.testing.expectEqual(Step{ .frames = 20, .buttons = 0 }, try parseStep("20"));
    try std.testing.expectEqual(Step{ .frames = 1, .buttons = 1 << 3 | 1 << 8 }, try parseStep("1:start+a"));
    try std.testing.expectError(error.UnknownButton, parseStep("1:turbo"));
}
