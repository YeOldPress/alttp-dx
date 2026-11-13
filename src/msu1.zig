//! MSU-1, the SD2SNES's streaming audio chip, as randomizer seeds use it: the
//! seed's own code checks for the chip, picks the tracks and fades them, and
//! this plays the files it asks for, from the same MSUPath and in the same
//! format (.pcm, .flac or .ogg, or .opuz) as the MSU settings say for the normal game. The
//! data port (for video) isn't here; nothing the randomizer does uses it.
//!
//! Registers, in banks $00-$3f and $80-$bf:
//!   $2000 read: status. $2001 read: data (always 0 here).
//!   $2002-$2007 read: "S-MSU1".
//!   $2004/$2005 write: track number; writing $2005 loads it.
//!   $2006 write: volume. $2007 write: bit 0 plays, bit 1 repeats.
//!
//! A .pcm track is "MSU1", a loop point in samples, then 44.1kHz 16-bit
//! stereo. A .opuz track is upstream's Opus container: a table of ranges
//! (where the audio is, how long it runs, where it loops back to) and then
//! Opus packets at 48kHz, which carry their own looping. FLAC and Ogg
//! Vorbis tracks go through msu_codec.zig, at whatever rate they were made.
const std = @import("std");
const msu_codec = @import("msu_codec.zig");

const FILE = opaque {};
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern fn fclose(f: *FILE) c_int;
extern fn fread(ptr: *anyopaque, size: usize, n: usize, f: *FILE) usize;
extern fn fseek(f: *FILE, off: c_long, whence: c_int) c_int;
const SEEK_SET = 0;

const OpusDecoder = anyopaque;
const OPUS_RESET_STATE: c_int = 4028;
extern fn opus_decoder_create(Fs: i32, channels: c_int, err: ?*c_int) ?*OpusDecoder;
extern fn opus_decoder_destroy(st: ?*OpusDecoder) void;
extern fn opus_decode(st: *OpusDecoder, data: [*]const u8, len: i32, pcm: [*]i16, frame_size: c_int, decode_fec: c_int) c_int;
extern fn opus_decoder_ctl(st: *OpusDecoder, request: c_int, ...) c_int;

pub const Msu1 = struct {
    /// Track n is at prefix ++ n ++ ".pcm" (or ".opuz").
    prefix: [1024]u8 = undefined,
    prefix_len: usize = 0,
    /// Tracks above this are reported missing even when a file is there.
    /// A pack made for the normal game numbers its extras its own way, and a
    /// seed would take them for its extended tracks (35 on, one per
    /// dungeon); reported missing, the seed falls back to its normal music.
    max_track: u16 = 0xffff,

    track: u16 = 0,
    file: ?*FILE = null,
    missing: bool = false,
    playing: bool = false,
    repeat: bool = false,
    volume: u8 = 0,

    /// .pcm, FLAC and Ogg: where the loop starts, in samples.
    loop_point: u32 = 0,
    /// A FLAC or Ogg track, read through its decoder instead of `file`.
    decoder: ?*msu_codec.Track = null,
    /// The rate the open track plays at.
    rate: u32 = 44100,

    /// .opuz: the decoder, the next range record, the one a loop jumps back
    /// to, and how much of the current range is left to play.
    opus: ?*OpusDecoder = null,
    range_cur: u32 = 0,
    range_repeat: u32 = 0,
    samples_left: u32 = 0,
    preskip: u32 = 0,

    /// Decoded frames not yet played.
    buf: [1024][2]i16 = undefined,
    buf_len: usize = 0,
    buf_pos: usize = 0,
    /// Output position between two source frames, for resampling, and the
    /// source frame it's at.
    frac: f64 = 0,
    cur: [2]i16 = .{ 0, 0 },

    pub fn configure(self: *Msu1, prefix: []const u8) void {
        self.prefix_len = @min(prefix.len, self.prefix.len - 16);
        @memcpy(self.prefix[0..self.prefix_len], prefix[0..self.prefix_len]);
    }

    /// Whether any of the first few tracks is there, to warn when MSUPath
    /// points at nothing.
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

    /// Where track `n` is: the first of .pcm, .flac, .ogg and .opuz that's
    /// there (or the .pcm, when none is).
    pub fn trackPath(self: *Msu1, out: []u8, n: u16) ?[*:0]const u8 {
        for (msu_codec.kTrackExts) |ext| {
            const p = self.pathWith(out, n, ext) orelse return null;
            if (fopen(p, "rb")) |f| {
                _ = fclose(f);
                return p;
            }
        }
        return self.pathWith(out, n, msu_codec.kTrackExts[0]);
    }

    fn pathWith(self: *Msu1, out: []u8, n: u16, ext: []const u8) ?[*:0]const u8 {
        const s = std.fmt.bufPrintSentinel(out, "{s}{d}.{s}", .{ self.prefix[0..self.prefix_len], n, ext }, 0) catch return null;
        return s.ptr;
    }

    pub fn deinit(self: *Msu1) void {
        self.close();
    }

    fn close(self: *Msu1) void {
        if (self.file) |f| _ = fclose(f);
        if (self.opus) |o| opus_decoder_destroy(o);
        if (self.decoder) |t| t.close();
        self.file = null;
        self.opus = null;
        self.decoder = null;
        self.buf_len = 0;
        self.buf_pos = 0;
    }

    fn load(self: *Msu1) void {
        self.close();
        self.playing = false;
        self.missing = true;
        if (self.track > self.max_track) return;
        var path: [1100]u8 = undefined;
        const p = self.trackPath(&path, self.track) orelse return;
        const f = fopen(p, "rb") orelse return;
        var header: [8]u8 = undefined;
        if (fread(&header, 1, 8, f) != 8) {
            _ = fclose(f);
            return;
        }
        if (msu_codec.kindOf(&header)) |kind| {
            _ = fclose(f);
            const t = msu_codec.Track.open(p, kind) orelse return;
            self.decoder = t;
            self.rate = t.rate;
            self.loop_point = @intCast(@min(t.loop_start, std.math.maxInt(u32)));
            self.missing = false;
            return;
        }
        if (std.mem.eql(u8, header[0..4], "MSU1")) {
            self.loop_point = std.mem.readInt(u32, header[4..8], .little);
            self.rate = 44100;
        } else if (std.mem.eql(u8, header[0..4], "OPUZ")) {
            self.rate = 48000;
            self.opus = opus_decoder_create(48000, 2, null) orelse {
                _ = fclose(f);
                return;
            };
            self.range_cur = 8;
            self.range_repeat = 0;
            self.samples_left = 0;
            self.preskip = 0;
        } else {
            _ = fclose(f);
            return;
        }
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

    /// Refills the buffer from a .pcm file, looping to the loop point when
    /// the game asked for repeat. False at the end.
    fn fillPcm(self: *Msu1, f: *FILE) bool {
        var raw: [1024 * 4]u8 = undefined;
        var n = fread(&raw, 4, self.buf.len, f);
        if (n == 0) {
            if (!self.repeat) return false;
            _ = fseek(f, @intCast(8 + @as(i64, self.loop_point) * 4), SEEK_SET);
            n = fread(&raw, 4, self.buf.len, f);
            if (n == 0) return false;
        }
        for (0..n) |i| {
            self.buf[i][0] = std.mem.readInt(i16, raw[i * 4 ..][0..2], .little);
            self.buf[i][1] = std.mem.readInt(i16, raw[i * 4 + 2 ..][0..2], .little);
        }
        self.buf_len = n;
        self.buf_pos = 0;
        return true;
    }

    /// Refills the buffer from a FLAC or Ogg track, the same way.
    fn fillTrack(self: *Msu1, t: *msu_codec.Track) bool {
        var n = t.read(&self.buf);
        if (n == 0) {
            if (!self.repeat or !t.seek(self.loop_point)) return false;
            n = t.read(&self.buf);
            if (n == 0) return false;
        }
        self.buf_len = n;
        self.buf_pos = 0;
        return true;
    }

    /// Refills the buffer with the next Opus packet of a .opuz file, moving
    /// through its ranges (which is how it loops). False at the end.
    fn fillOpuz(self: *Msu1, f: *FILE, dec: *OpusDecoder) bool {
        while (true) {
            if (self.samples_left == 0) {
                if (self.range_cur == 0) return false;
                _ = opus_decoder_ctl(dec, OPUS_RESET_STATE);
                _ = fseek(f, @intCast(self.range_cur), SEEK_SET);
                var rec: [10]u8 = undefined;
                if (fread(&rec, 1, 10, f) != 10) return false;
                const file_offs = std.mem.readInt(u32, rec[0..4], .little) & 0x0fffffff;
                self.samples_left = std.mem.readInt(u32, rec[4..8], .little);
                const skip = std.mem.readInt(u16, rec[8..10], .little);
                self.preskip = skip & 0x3fff;
                if (skip & 0x4000 != 0) self.range_repeat = self.range_cur;
                self.range_cur = if (skip & 0x8000 != 0) self.range_repeat else self.range_cur + 10;
                _ = fseek(f, @intCast(file_offs), SEEK_SET);
                if (self.samples_left == 0) continue;
            }
            // A packet: 15 bits of size, and a flag for whether its first
            // byte (the table of contents, always 0xfc here) was left out.
            var data: [2 + 1275]u8 = undefined;
            if (fread(&data, 1, 2, f) != 2) return false;
            const header = std.mem.readInt(u16, data[0..2], .little);
            const size: usize = header & 0x7fff;
            if (size > 1275) return false;
            const has_toc: usize = header >> 15;
            if (fread(data[2..].ptr, 1, size, f) != size) return false;
            data[1] = 0xfc;
            var pcm: [960][2]i16 = undefined;
            const r = opus_decode(dec, data[2 - has_toc ..].ptr, @intCast(size + has_toc), @ptrCast(&pcm), 960, 0);
            if (r <= 0) return false;
            const got: u32 = @intCast(r);
            if (got <= self.preskip) {
                self.preskip -= got;
                continue;
            }
            const n = @min(got - self.preskip, self.samples_left);
            @memcpy(self.buf[0..n], pcm[@intCast(self.preskip)..][0..n]);
            self.samples_left -= n;
            self.preskip = 0;
            self.buf_len = n;
            self.buf_pos = 0;
            return true;
        }
    }

    /// The next source frame, or null when the track has ended.
    fn nextFrame(self: *Msu1) ?[2]i16 {
        if (self.buf_pos == self.buf_len) {
            const ok = if (self.decoder) |t|
                self.fillTrack(t)
            else if (self.file) |f|
                (if (self.opus) |dec| self.fillOpuz(f, dec) else self.fillPcm(f))
            else
                return null;
            if (!ok) {
                self.playing = false;
                return null;
            }
        }
        defer self.buf_pos += 1;
        return self.buf[self.buf_pos];
    }

    /// Mixes `samples` frames at `rate` Hz into `out` (interleaved, 1 or 2
    /// channels).
    pub fn mix(self: *Msu1, out: []i16, samples: usize, channels: usize, rate: u32) void {
        if (!self.playing or (self.file == null and self.decoder == null)) return;
        const step = @as(f64, @floatFromInt(self.rate)) / @as(f64, @floatFromInt(rate));
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

test "tracks past the limit are missing even when their file is there" {
    var m = Msu1{};
    defer m.deinit();
    m.configure("/nonexistent/should-not-be-opened-");
    m.max_track = 34;
    m.track = 35;
    m.load();
    try std.testing.expect(m.missing);
}

test "the chip identifies itself and reports a missing track" {
    var m = Msu1{};
    m.configure("/nonexistent/track-");
    try std.testing.expectEqual(@as(?u8, 'S'), m.read(0x2002));
    try std.testing.expectEqual(@as(?u8, '1'), m.read(0x2007));
    _ = m.write(0x2004, 5);
    _ = m.write(0x2005, 0);
    try std.testing.expect(m.read(0x2000).? & 0x08 != 0);
    _ = m.write(0x2007, 1);
    try std.testing.expect(m.read(0x2000).? & 0x10 == 0);
}

test "a track is whichever kind of file is there" {
    const fileio = @import("fileio.zig");
    const path = ".zig-cache/msu1-kinds-test-12.opuz";
    defer _ = fileio.remove(path);
    try fileio.writeWholeFile(path, "OPUZ");
    var m = Msu1{};
    var buf: [64]u8 = undefined;
    m.configure(".zig-cache/msu1-kinds-test-");
    try std.testing.expectEqualStrings(path, std.mem.span(m.trackPath(&buf, 12).?));
    // Nothing there: the .pcm, the name most packs use, for saying so.
    try std.testing.expectEqualStrings(".zig-cache/msu1-kinds-test-3.pcm", std.mem.span(m.trackPath(&buf, 3).?));
}

test "a FLAC track plays, and repeats from its loop point" {
    const flac_enc = @import("flac_enc.zig");
    const fileio = @import("fileio.zig");
    const path = ".zig-cache/msu1-flac-test-7.flac";
    defer _ = fileio.remove(path);
    // 3000 frames counting up, so where it is shows in every sample.
    var samples: [3000 * 2]i16 = undefined;
    for (0..3000) |i| samples[i * 2] = @intCast(i);
    for (0..3000) |i| samples[i * 2 + 1] = -@as(i16, @intCast(i));
    const bytes = try flac_enc.encode(std.testing.allocator, &samples, .{ .loop_start = 2500 });
    defer std.testing.allocator.free(bytes);
    try fileio.writeWholeFile(path, bytes);

    var m = Msu1{};
    defer m.deinit();
    m.configure(".zig-cache/msu1-flac-test-");
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings(path, std.mem.span(m.trackPath(&buf, 7).?));
    _ = m.write(0x2004, 7);
    _ = m.write(0x2005, 0);
    try std.testing.expect(!m.missing);
    try std.testing.expectEqual(@as(u32, 2500), m.loop_point);
    _ = m.write(0x2006, 255);
    _ = m.write(0x2007, 3); // play, repeat

    // At its own rate, one frame in is one frame out.
    var out: [3600 * 2]i16 = @splat(0);
    m.mix(&out, 3600, 2, 44100);
    try std.testing.expectEqual(@as(i16, 0), out[0]);
    try std.testing.expectEqual(@as(i16, 2999), out[2999 * 2]);
    try std.testing.expectEqual(@as(i16, -2999), out[2999 * 2 + 1]);
    // Then back to 2500, not the start.
    try std.testing.expectEqual(@as(i16, 2500), out[3000 * 2]);
    try std.testing.expectEqual(@as(i16, 2599), out[3099 * 2]);
}
