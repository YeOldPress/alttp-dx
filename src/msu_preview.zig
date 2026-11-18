//! Playing an installed MSU pack's tracks in the tools, to hear what's in
//! it. It's the randomizer's MSU-1 chip (msu1.zig) on a stream of its own:
//! that already reads every kind of track, loops them where they loop, and
//! resamples them to whatever rate it's asked for.
const std = @import("std");
const c = @import("sdl.zig").c;
const Msu1 = @import("msu1.zig").Msu1;

/// The rate the stream asks for. SDL converts to the device's own.
const kRate = 44100;

/// What the game's 34 tracks are, in the order every MSU-1 pack numbers
/// them.
pub const kTrackNames = [_][]const u8{
    "Title",               "Light World",        "Rainy intro",    "Bunny Link",
    "Lost Woods",          "Legend",             "Kakariko",       "Mirror warp",
    "Dark World",          "Master Sword",       "File select",    "Soldiers",
    "Dark Death Mountain", "Minigame",           "Skull Woods",    "Hyrule Castle",
    "Light World dungeon", "Cave",               "Boss victory",   "Sanctuary",
    "Boss",                "Dark World dungeon", "Fortune teller", "Cave 2",
    "Zelda rescued",       "Crystal",            "Fairy fountain", "Agahnim",
    "Ganon appears",       "Ganon's message",    "Ganon battle",   "Triforce room",
    "Epilogue",            "Credits",
};

/// Track `n`'s name, or null past the game's own 34.
pub fn trackName(n: u16) ?[]const u8 {
    if (n == 0 or n > kTrackNames.len) return null;
    return kTrackNames[n - 1];
}

pub const Preview = struct {
    msu: Msu1 = .{},
    stream: ?*c.SDL_AudioStream = null,
    /// The pack and track playing, while one is.
    track: ?u16 = null,
    path_buf: [1024]u8 = undefined,
    path_len: usize = 0,

    /// Plays track `n` of the pack at `msu_path` (an MSUPath), once through
    /// or looping as the game would. False when it isn't there or there's
    /// nothing to play it on.
    pub fn play(self: *Preview, msu_path: []const u8, n: u16, repeat: bool) bool {
        if (self.stream == null) {
            const spec = c.SDL_AudioSpec{ .format = c.SDL_AUDIO_S16, .channels = 2, .freq = kRate };
            self.stream = c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, feed, self) orelse return false;
        }
        const s = self.stream.?;
        _ = c.SDL_LockAudioStream(s);
        self.msu.deinit();
        self.msu = .{};
        self.msu.configure(msu_path);
        _ = self.msu.write(0x2004, @truncate(n));
        _ = self.msu.write(0x2005, @truncate(n >> 8));
        const ok = !self.msu.missing;
        if (ok) {
            _ = self.msu.write(0x2006, 255);
            // Play, and repeat if asked.
            _ = self.msu.write(0x2007, if (repeat) 3 else 1);
            const len = @min(msu_path.len, self.path_buf.len);
            @memcpy(self.path_buf[0..len], msu_path[0..len]);
            self.path_len = len;
            self.track = n;
        } else self.track = null;
        _ = c.SDL_ClearAudioStream(s);
        _ = c.SDL_UnlockAudioStream(s);
        return ok and c.SDL_ResumeAudioStreamDevice(s);
    }

    /// Holds the track where it is, and lets it go on.
    pub fn pause(self: *Preview) void {
        if (self.stream) |s| _ = c.SDL_PauseAudioStreamDevice(s);
    }

    pub fn @"resume"(self: *Preview) void {
        if (self.stream) |s| _ = c.SDL_ResumeAudioStreamDevice(s);
    }

    /// Turns it down, 0 to 1.
    pub fn setGain(self: *Preview, gain: f32) void {
        if (self.stream) |s| _ = c.SDL_SetAudioStreamGain(s, gain);
    }

    pub fn stop(self: *Preview) void {
        const s = self.stream orelse return;
        _ = c.SDL_PauseAudioStreamDevice(s);
        _ = c.SDL_LockAudioStream(s);
        self.msu.deinit();
        self.track = null;
        _ = c.SDL_ClearAudioStream(s);
        _ = c.SDL_UnlockAudioStream(s);
    }

    /// The track playing from the pack at `msu_path`, if one is. A track
    /// that's run to its end (one that doesn't loop) isn't.
    pub fn playingIn(self: *Preview, msu_path: []const u8) ?u16 {
        const s = self.stream orelse return null;
        _ = c.SDL_LockAudioStream(s);
        defer _ = c.SDL_UnlockAudioStream(s);
        if (!self.msu.playing) return null;
        if (!std.mem.eql(u8, self.path_buf[0..self.path_len], msu_path)) return null;
        return self.track;
    }

    /// How far into the track it is, and how long the track is when that's
    /// known, in seconds.
    pub fn clock(self: *Preview) struct { at: f64, len: ?f64 } {
        const s = self.stream orelse return .{ .at = 0, .len = null };
        _ = c.SDL_LockAudioStream(s);
        defer _ = c.SDL_UnlockAudioStream(s);
        const rate: f64 = @floatFromInt(@max(self.msu.rate, 1));
        return .{
            .at = @as(f64, @floatFromInt(self.msu.frame)) / rate,
            .len = if (self.msu.length) |l| @as(f64, @floatFromInt(l)) / rate else null,
        };
    }

    pub fn deinit(self: *Preview) void {
        if (self.stream) |s| c.SDL_DestroyAudioStream(s);
        self.stream = null;
        self.msu.deinit();
    }

    /// Runs on SDL's audio thread, with the stream locked.
    fn feed(userdata: ?*anyopaque, stream: ?*c.SDL_AudioStream, additional: c_int, total: c_int) callconv(.c) void {
        _ = total;
        const self: *Preview = @ptrCast(@alignCast(userdata));
        var buf: [1024 * 2]i16 = undefined;
        var left = additional;
        while (left > 0) {
            @memset(&buf, 0);
            self.msu.mix(&buf, 1024, 2, kRate);
            _ = c.SDL_PutAudioStreamData(stream, &buf, @sizeOf(@TypeOf(buf)));
            left -= @sizeOf(@TypeOf(buf));
        }
    }
};

test "the game's tracks have names, and the extras don't" {
    try std.testing.expectEqual(@as(usize, 34), kTrackNames.len);
    try std.testing.expectEqualStrings("Light World", trackName(2).?);
    try std.testing.expectEqualStrings("Credits", trackName(34).?);
    try std.testing.expectEqual(@as(?[]const u8, null), trackName(0));
    try std.testing.expectEqual(@as(?[]const u8, null), trackName(35));
}
