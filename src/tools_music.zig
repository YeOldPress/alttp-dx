//! The music page's player: the game's own sound driver, fed the song banks
//! out of zelda3_assets.dat, exactly as the game feeds it, and played through
//! SDL.
//!
//! The music is three banks, each a chain of blocks to copy into the sound
//! chip's memory. The overworld bank is the base and always goes in first;
//! the dungeon and ending banks are laid over it when the game goes there. A
//! song belongs to whichever bank holds its data, and only plays right with
//! that bank in.
const std = @import("std");
const c = @import("sdl.zig").c;
const fileio = @import("fileio.zig");
const pack = @import("asset_pack.zig");
const spc = @import("spc_player.zig");
const SpcPlayer = @import("spc_types.zig").SpcPlayer;
const dsp_mod = @import("snes").dsp;

pub const Bank = enum {
    overworld,
    dungeon,
    ending,

    fn assetName(self: Bank) []const u8 {
        return switch (self) {
            .overworld => "kSoundBank_intro",
            .dungeon => "kSoundBank_indoor",
            .ending => "kSoundBank_ending",
        };
    }
};

pub const Song = struct { number: u8, bank: Bank };

/// One bank: the stream the driver uploads, and which of the chip's addresses
/// it fills.
const Upload = struct {
    stream: []u8,
    fills: *[0x10000]bool,
};

/// The driver makes a 60th of a second at a time, at 32 kHz.
pub const kFrameSamples = 534;
pub const kRate = kFrameSamples * 60;

pub const Player = struct {
    alloc: std.mem.Allocator,
    uploads: [3]Upload,
    songs: []Song,
    sp: *SpcPlayer,
    stream: ?*c.SDL_AudioStream = null,
    playing: ?Song = null,

    /// Reads the banks out of the asset file at `assets_path`.
    pub fn init(alloc: std.mem.Allocator, assets_path: [:0]const u8) !*Player {
        const bytes = try fileio.readWholeFile(alloc, assets_path.ptr);
        defer alloc.free(bytes);
        var contents = try pack.read(alloc, bytes);
        defer contents.deinit(alloc);

        const self = try alloc.create(Player);
        errdefer alloc.destroy(self);
        var uploads: [3]Upload = undefined;
        var made: usize = 0;
        errdefer for (uploads[0..made]) |u| {
            alloc.free(u.stream);
            alloc.destroy(u.fills);
        };
        for (std.enums.values(Bank), 0..) |bank, i| {
            uploads[i] = try bankUpload(alloc, contents.find(bank.assetName()) orelse return error.NoMusic);
            made += 1;
        }
        const songs = try listSongs(alloc, &uploads);
        self.* = .{ .alloc = alloc, .uploads = uploads, .songs = songs, .sp = spc.SpcPlayer_Create() };
        return self;
    }

    pub fn deinit(self: *Player) void {
        if (self.stream) |s| c.SDL_DestroyAudioStream(s);
        for (self.uploads) |u| {
            self.alloc.free(u.stream);
            self.alloc.destroy(u.fills);
        }
        self.alloc.free(self.songs);
        if (self.sp.dsp) |d| dsp_mod.dsp_free(d);
        std.c.free(self.sp);
        self.alloc.destroy(self);
    }

    /// Starts `song` from the top. False when there's no sound to play it on.
    pub fn play(self: *Player, song: Song) bool {
        if (self.stream == null) {
            const spec = c.SDL_AudioSpec{ .format = c.SDL_AUDIO_S16, .channels = 2, .freq = kRate };
            self.stream = c.SDL_OpenAudioDeviceStream(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, feed, self) orelse return false;
        }
        const s = self.stream.?;
        _ = c.SDL_LockAudioStream(s);
        self.start(song);
        _ = c.SDL_ClearAudioStream(s);
        _ = c.SDL_UnlockAudioStream(s);
        return c.SDL_ResumeAudioStreamDevice(s);
    }

    /// Resets the driver, loads the song's banks, and asks for the song, as
    /// the game does when it changes the music.
    pub fn start(self: *Player, song: Song) void {
        spc.SpcPlayer_Initialize(self.sp);
        spc.SpcPlayer_Upload(self.sp, self.uploads[@backingInt(Bank.overworld)].stream.ptr);
        if (song.bank != .overworld) spc.SpcPlayer_Upload(self.sp, self.uploads[@backingInt(song.bank)].stream.ptr);
        self.sp.input_ports[0] = song.number;
        self.playing = song;
    }

    /// The next 60th of a second, as stereo samples at `kRate`.
    pub fn render(self: *Player, buf: *[kFrameSamples * 2]i16) void {
        spc.SpcPlayer_GenerateSamples(self.sp);
        dsp_mod.dsp_getSamples(self.sp.dsp.?, buf, kFrameSamples, 2);
    }

    pub fn stop(self: *Player) void {
        self.playing = null;
        const s = self.stream orelse return;
        _ = c.SDL_PauseAudioStreamDevice(s);
        _ = c.SDL_ClearAudioStream(s);
    }

    /// Runs on SDL's audio thread, with the stream locked: as many frames of
    /// the driver as the device has asked for.
    fn feed(userdata: ?*anyopaque, stream: ?*c.SDL_AudioStream, additional: c_int, total: c_int) callconv(.c) void {
        _ = total;
        const self: *Player = @ptrCast(@alignCast(userdata));
        var buf: [kFrameSamples * 2]i16 = undefined;
        var left = additional;
        while (left > 0) {
            self.render(&buf);
            _ = c.SDL_PutAudioStreamData(stream, &buf, @sizeOf(@TypeOf(buf)));
            left -= @sizeOf(@TypeOf(buf));
        }
    }
};

/// A copy of a bank's stream, which the driver reads straight through, and
/// the addresses its blocks fill.
fn bankUpload(alloc: std.mem.Allocator, data: []const u8) !Upload {
    // The end marker is a zero length; one more is cheap insurance against
    // an asset that stops short of it.
    const stream = try alloc.alloc(u8, data.len + 2);
    errdefer alloc.free(stream);
    @memcpy(stream[0..data.len], data);
    stream[data.len] = 0;
    stream[data.len + 1] = 0;
    const fills = try alloc.create([0x10000]bool);
    fills.* = @splat(false);
    var i: usize = 0;
    while (i + 4 <= stream.len) {
        const num = std.mem.readInt(u16, stream[i..][0..2], .little);
        if (num == 0) break;
        const target = std.mem.readInt(u16, stream[i + 2 ..][0..2], .little);
        for (0..num) |k| fills[(target + k) & 0xffff] = true;
        i += 4 + num;
    }
    return .{ .stream = stream, .fills = fills };
}

/// Copies a stream's blocks into the chip's memory, as the driver would.
fn apply(mem: *[0x10000]u8, stream: []const u8) void {
    var i: usize = 0;
    while (i + 2 <= stream.len) {
        const num = std.mem.readInt(u16, stream[i..][0..2], .little);
        if (num == 0) return;
        const target = std.mem.readInt(u16, stream[i + 2 ..][0..2], .little);
        i += 4;
        for (0..num) |k| mem[(target + k) & 0xffff] = stream[i + k];
        i += num;
    }
}

/// Every song, with the bank that holds it. Song n's address is entry n-1 of
/// the list at 0xD000, and it's a bank's song when that bank wrote what's
/// there.
fn listSongs(alloc: std.mem.Allocator, uploads: *const [3]Upload) ![]Song {
    const mem = try alloc.create([0x10000]u8);
    defer alloc.destroy(mem);
    var songs: std.ArrayList(Song) = .empty;
    errdefer songs.deinit(alloc);
    for (std.enums.values(Bank), 0..) |bank, b| {
        mem.* = @splat(0);
        apply(mem, uploads[0].stream);
        if (bank != .overworld) apply(mem, uploads[b].stream);
        const word = struct {
            fn at(m: *const [0x10000]u8, ea: usize) u16 {
                return @as(u16, m[ea]) | @as(u16, m[ea + 1]) << 8;
            }
        }.at;
        const first = word(mem, 0xd000);
        const count: usize = if (bank == .overworld) (first -% 0xd000) / 2 else (0xd046 - 0xd000) / 2;
        for (0..@min(count, 64)) |i| {
            const ptr = word(mem, 0xd000 + i * 2);
            if (ptr < 0x100 or !uploads[b].fills[ptr]) continue;
            try songs.append(alloc, .{ .number = @intCast(i + 1), .bank = bank });
        }
    }
    return songs.toOwnedSlice(alloc);
}

test "a bank's stream is copied into memory block by block" {
    var mem: [0x10000]u8 = @splat(0);
    const stream = [_]u8{ 2, 0, 0x00, 0xd0, 0xaa, 0xbb, 1, 0, 0xff, 0xff, 0xcc, 0, 0 };
    apply(&mem, &stream);
    try std.testing.expectEqual(@as(u8, 0xaa), mem[0xd000]);
    try std.testing.expectEqual(@as(u8, 0xbb), mem[0xd001]);
    try std.testing.expectEqual(@as(u8, 0xcc), mem[0xffff]);
}

/// For `zelda3-tools music-wav ASSETS SONG OUT.wav`, undocumented: `seconds`
/// of a song as a WAV, to hear the player without a window.
pub fn writeWav(alloc: std.mem.Allocator, assets_path: [:0]const u8, number: u8, out: [:0]const u8, seconds: u32) !void {
    const p = try Player.init(alloc, assets_path);
    defer p.deinit();
    const song = for (p.songs) |s| {
        if (s.number == number) break s;
    } else return error.NoSuchSong;
    p.start(song);
    const frames = seconds * 60;
    const data_len: u32 = frames * kFrameSamples * 4;
    var wav: std.ArrayList(u8) = .empty;
    defer wav.deinit(alloc);
    const header = [_]u32{ 0x46464952, 36 + data_len, 0x45564157, 0x20746d66, 16, 0x00020001, kRate, kRate * 4, 0x00100004, 0x61746164, data_len };
    for (header) |w| try wav.appendSlice(alloc, &std.mem.toBytes(std.mem.nativeToLittle(u32, w)));
    var buf: [kFrameSamples * 2]i16 = undefined;
    for (0..frames) |_| {
        p.render(&buf);
        for (buf) |sample| try wav.appendSlice(alloc, &std.mem.toBytes(std.mem.nativeToLittle(i16, sample)));
    }
    try fileio.writeWholeFile(out.ptr, wav.items);
}
