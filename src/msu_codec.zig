//! MSU tracks as FLAC or Ogg Vorbis, for both MSU players: the normal game's
//! (audio.zig) and the randomizer's MSU-1 chip (msu1.zig). The decoding is
//! dr_flac's and stb_vorbis's, in msu_codecs.c.
//!
//! A .pcm track carries its loop point in its header; these carry it as a
//! LOOPSTART tag, in samples. Without one a track loops from its start, the
//! same as a .pcm whose loop point is 0.
const std = @import("std");

/// The formats the game looks for when MSU is set to plain tracks, best
/// first: a pack with a track as .pcm and as .flac plays the .pcm. Opuz
/// packs have a setting of their own.
pub const kTrackExts = [_][]const u8{ "pcm", "flac", "ogg" };

pub const Kind = enum { flac, ogg };

const Info = extern struct {
    rate: c_uint,
    channels: c_uint,
    frames: c_ulonglong,
    loop_start: c_longlong,
};

extern fn msu_flac_open(path: [*:0]const u8, info: *Info) ?*anyopaque;
extern fn msu_flac_seek(h: *anyopaque, frame: c_ulonglong) c_int;
extern fn msu_flac_read(h: *anyopaque, out: [*]i16, frames: c_ulonglong) c_ulonglong;
extern fn msu_flac_close(h: *anyopaque) void;
extern fn msu_ogg_open(path: [*:0]const u8, info: *Info) ?*anyopaque;
extern fn msu_ogg_seek(h: *anyopaque, frame: c_ulonglong) c_int;
extern fn msu_ogg_read(h: *anyopaque, out: [*]i16, frames: c_ulonglong) c_ulonglong;
extern fn msu_ogg_close(h: *anyopaque) void;

/// Which of the two `path` is, from its first four bytes.
pub fn kindOf(head: []const u8) ?Kind {
    if (head.len < 4) return null;
    if (std.mem.eql(u8, head[0..4], "fLaC")) return .flac;
    if (std.mem.eql(u8, head[0..4], "OggS")) return .ogg;
    return null;
}

/// The first four bytes of each, as the little-endian number the normal
/// game's player keeps to know a resumed track is the same kind of file.
pub fn tag(kind: Kind) u32 {
    return std.mem.readInt(u32, switch (kind) {
        .flac => "fLaC",
        .ogg => "OggS",
    }, .little);
}

/// An open track, read as 16-bit stereo whatever it was made as.
pub const Track = struct {
    kind: Kind,
    h: *anyopaque,
    rate: u32,
    channels: u32,
    /// How long it is, in frames.
    frames: u64,
    /// Where a repeat goes back to, in frames.
    loop_start: u64,
    /// For mono FLAC, which comes out one sample a frame.
    mono: [1024]i16 = undefined,

    /// Opens `path` as `kind`, or null when it won't decode, is more than
    /// stereo, or doesn't say how long it is (needed to loop it).
    pub fn open(path: [*:0]const u8, kind: Kind) ?*Track {
        var info: Info = undefined;
        const h = switch (kind) {
            .flac => msu_flac_open(path, &info),
            .ogg => msu_ogg_open(path, &info),
        } orelse return null;
        // Ogg is mixed to stereo on the way out; FLAC comes out as it is.
        const ok = info.frames != 0 and info.rate != 0 and info.channels != 0 and
            (kind == .ogg or info.channels <= 2);
        const self = if (ok) std.heap.c_allocator.create(Track) catch null else null;
        const t = self orelse {
            closeHandle(kind, h);
            return null;
        };
        const loop: u64 = if (info.loop_start < 0) 0 else @intCast(info.loop_start);
        t.* = .{
            .kind = kind,
            .h = h,
            .rate = info.rate,
            .channels = info.channels,
            .frames = info.frames,
            .loop_start = if (loop < info.frames) loop else 0,
        };
        return t;
    }

    pub fn close(self: *Track) void {
        closeHandle(self.kind, self.h);
        std.heap.c_allocator.destroy(self);
    }

    pub fn seek(self: *Track, frame: u64) bool {
        return switch (self.kind) {
            .flac => msu_flac_seek(self.h, frame),
            .ogg => msu_ogg_seek(self.h, frame),
        } != 0;
    }

    /// Fills as much of `out` as there's track left for. Short only at the
    /// end (or on a read error, which looks the same).
    pub fn read(self: *Track, out: [][2]i16) usize {
        if (self.kind == .ogg) return @intCast(msu_ogg_read(self.h, @ptrCast(out.ptr), out.len));
        if (self.channels == 2) return @intCast(msu_flac_read(self.h, @ptrCast(out.ptr), out.len));
        var got: usize = 0;
        while (got < out.len) {
            const want: usize = @min(out.len - got, self.mono.len);
            const n: usize = @intCast(msu_flac_read(self.h, &self.mono, want));
            for (self.mono[0..n], out[got..][0..n]) |s, *o| o.* = .{ s, s };
            got += n;
            if (n < want) break;
        }
        return got;
    }
};

fn closeHandle(kind: Kind, h: *anyopaque) void {
    switch (kind) {
        .flac => msu_flac_close(h),
        .ogg => msu_ogg_close(h),
    }
}
