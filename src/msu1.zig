//! MSU-1, the SD2SNES's streaming audio chip, as randomizer seeds use it: the
//! seed's own code checks for the chip, picks the tracks and fades them, and
//! this plays the .pcm files it asks for. The data port (for video) isn't
//! here; nothing the randomizer does uses it.
//!
//! Registers, in banks $00-$3f and $80-$bf:
//!   $2000 read: status. $2001 read: data (always 0 here).
//!   $2002-$2007 read: "S-MSU1".
//!   $2004/$2005 write: track number; writing $2005 loads it.
//!   $2006 write: volume. $2007 write: bit 0 plays, bit 1 repeats.
//!
//! Tracks are standard MSU-1 .pcm: "MSU1", a loop point in samples, then
//! 44.1kHz 16-bit stereo.
const std = @import("std");

const FILE = opaque {};
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern fn fclose(f: *FILE) c_int;
extern fn fread(ptr: *anyopaque, size: usize, n: usize, f: *FILE) usize;
extern fn fseek(f: *FILE, off: c_long, whence: c_int) c_int;
const SEEK_SET = 0;

const kRate = 44100;

pub const Msu1 = struct {
    /// Track n is at prefix ++ n ++ ".pcm".
    prefix: [1024]u8 = undefined,
    prefix_len: usize = 0,

    track: u16 = 0,
    file: ?*FILE = null,
    loop_point: u32 = 0,
    missing: bool = false,
    playing: bool = false,
    repeat: bool = false,
    volume: u8 = 0,

    /// Where the file is read up to, in samples, and a buffer of what's been
    /// read and not yet played, as stereo frames.
    buf: [4096][2]i16 = undefined,
    buf_len: usize = 0,
    buf_pos: usize = 0,
    /// Output position between two source frames, for resampling, and the
    /// source frame it's at.
    frac: f64 = 0,
    cur: [2]i16 = .{ 0, 0 },

    pub fn setPrefix(self: *Msu1, prefix: []const u8) void {
        self.prefix_len = @min(prefix.len, self.prefix.len - 16);
        @memcpy(self.prefix[0..self.prefix_len], prefix[0..self.prefix_len]);
    }

    /// Whether any of the first few tracks is there, which is what decides
    /// whether to show the chip to the game at all.
    pub fn hasTracks(self: *Msu1) bool {
        for (1..10) |n| {
            var path: [1100]u8 = undefined;
            const p = self.trackPath(&path, @intCast(n)) orelse continue;
            if (fopen(p, "rb")) |f| {
                _ = fclose(f);
                return true;
            }
        }
        return false;
    }

    fn trackPath(self: *Msu1, out: []u8, n: u16) ?[*:0]const u8 {
        const s = std.fmt.bufPrintZ(out, "{s}{d}.pcm", .{ self.prefix[0..self.prefix_len], n }) catch return null;
        return s.ptr;
    }

    pub fn deinit(self: *Msu1) void {
        self.close();
    }

    fn close(self: *Msu1) void {
        if (self.file) |f| _ = fclose(f);
        self.file = null;
        self.buf_len = 0;
        self.buf_pos = 0;
    }

    fn load(self: *Msu1) void {
        self.close();
        self.playing = false;
        self.missing = true;
        var path: [1100]u8 = undefined;
        const p = self.trackPath(&path, self.track) orelse return;
        const f = fopen(p, "rb") orelse return;
        var header: [8]u8 = undefined;
        if (fread(&header, 1, 8, f) != 8 or !std.mem.eql(u8, header[0..4], "MSU1")) {
            _ = fclose(f);
            return;
        }
        self.loop_point = std.mem.readInt(u32, header[4..8], .little);
        self.file = f;
        self.missing = false;
    }

    pub fn read(self: *Msu1, adr: u16) ?u8 {
        return switch (adr) {
            0x2000 => @as(u8, @intFromBool(self.repeat)) << 5 |
                @as(u8, @intFromBool(self.playing)) << 4 |
                @as(u8, @intFromBool(self.missing)) << 3 | 1,
            0x2001 => 0,
            0x2002...0x2007 => "S-MSU1"[adr - 0x2002],
            else => null,
        };
    }

    pub fn write(self: *Msu1, adr: u16, val: u8) bool {
        switch (adr) {
            0x2000...0x2003 => {}, // data seek: not used
            0x2004 => self.track = (self.track & 0xff00) | val,
            0x2005 => {
                self.track = (self.track & 0x00ff) | @as(u16, val) << 8;
                self.load();
            },
            0x2006 => self.volume = val,
            0x2007 => {
                if (self.missing) return true;
                self.playing = val & 1 != 0;
                self.repeat = val & 2 != 0;
            },
            else => return false,
        }
        return true;
    }

    /// The next source frame, reading ahead from the file and looping or
    /// stopping at its end.
    fn nextFrame(self: *Msu1) ?[2]i16 {
        if (self.buf_pos == self.buf_len) {
            const f = self.file orelse return null;
            var raw: [4096 * 4]u8 = undefined;
            var n = fread(&raw, 4, self.buf.len, f);
            if (n == 0) {
                if (!self.repeat) {
                    self.playing = false;
                    return null;
                }
                _ = fseek(f, @intCast(8 + @as(u64, self.loop_point) * 4), SEEK_SET);
                n = fread(&raw, 4, self.buf.len, f);
                if (n == 0) {
                    self.playing = false;
                    return null;
                }
            }
            for (0..n) |i| {
                self.buf[i][0] = std.mem.readInt(i16, raw[i * 4 ..][0..2], .little);
                self.buf[i][1] = std.mem.readInt(i16, raw[i * 4 + 2 ..][0..2], .little);
            }
            self.buf_len = n;
            self.buf_pos = 0;
        }
        defer self.buf_pos += 1;
        return self.buf[self.buf_pos];
    }

    /// Mixes `samples` frames at `rate` Hz into `out` (interleaved, 1 or 2
    /// channels).
    pub fn mix(self: *Msu1, out: []i16, samples: usize, channels: usize, rate: u32) void {
        if (!self.playing or self.file == null) return;
        const step = @as(f64, kRate) / @as(f64, @floatFromInt(rate));
        const vol: i32 = self.volume;
        for (0..samples) |i| {
            self.frac += step;
            while (self.frac >= 1.0) : (self.frac -= 1.0) {
                self.cur = self.nextFrame() orelse return;
            }
            const cur = self.cur;
            if (channels == 2) {
                for (0..2) |ch| {
                    const v = @as(i32, out[i * 2 + ch]) + @divTrunc(@as(i32, cur[ch]) * vol, 255);
                    out[i * 2 + ch] = @intCast(std.math.clamp(v, -32768, 32767));
                }
            } else {
                const m = @divTrunc((@as(i32, cur[0]) + cur[1]) * vol, 510);
                out[i] = @intCast(std.math.clamp(@as(i32, out[i]) + m, -32768, 32767));
            }
        }
    }
};

test "the chip identifies itself and reports a missing track" {
    var m = Msu1{};
    m.setPrefix("/nonexistent/track-");
    try std.testing.expectEqual(@as(?u8, 'S'), m.read(0x2002));
    try std.testing.expectEqual(@as(?u8, '1'), m.read(0x2007));
    _ = m.write(0x2004, 5);
    _ = m.write(0x2005, 0);
    try std.testing.expect(m.read(0x2000).? & 0x08 != 0);
    _ = m.write(0x2007, 1);
    try std.testing.expect(m.read(0x2000).? & 0x10 == 0);
}
