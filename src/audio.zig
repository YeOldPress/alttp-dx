//! Port of src/audio.c: the MSU-1 / Opuz music player and the APU write queue
//! that bridges the emulated SNES and the audio callback thread.
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl_types.zig");
const features = @import("features.zig");
const config = @import("config.zig");
const snes_pkg = @import("snes");
const dsp_mod = snes_pkg.dsp;
const msu_codec = @import("msu_codec.zig");

const g_ram = &vars.g_ram;
const g_zenv = &rtl.g_zenv;

const APUI00 = 0x2140; // snes/snes_regs.h
const kRam_APUI00 = features.kRam_APUI00;

// config.h
const kMsuEnabled_Msu: u8 = 1;
const kMsuEnabled_MsuDeluxe: u8 = 2;
const kMsuEnabled_Opuz: u8 = 4;

// Still in C: main.c owns the audio lock and the asset table.
extern fn ZeldaApuLock() void;
extern fn ZeldaApuUnlock() void;
extern const g_asset_ptrs: [165]?[*]const u8;

// Still in C: spc_player.c.
extern fn SpcPlayer_GenerateSamples(p: *SpcPlayer) void;
extern fn SpcPlayer_Initialize(p: *SpcPlayer) void;
extern fn SpcPlayer_Upload(p: *SpcPlayer, data: [*]const u8) void;
extern fn SpcPlayer_CopyVariablesFromRam(p: *SpcPlayer) void;
extern fn SpcPlayer_CopyVariablesToRam(p: *SpcPlayer) void;

const FILE = anyopaque;
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern fn fclose(f: *FILE) c_int;
extern fn fread(ptr: *anyopaque, size: usize, n: usize, f: *FILE) usize;
extern fn fseek(f: *FILE, off: c_long, whence: c_int) c_int;
extern fn ftell(f: *FILE) c_long;
extern fn setvbuf(f: *FILE, buf: ?[*]u8, mode: c_int, size: usize) c_int;
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern fn printf(fmt: [*:0]const u8, ...) c_int;

const SEEK_SET: c_int = 0;
const SEEK_END: c_int = 2;
const _IOFBF: c_int = 0;

const OpusDecoder = anyopaque;
const OPUS_RESET_STATE: c_int = 4028;
extern fn opus_decoder_create(Fs: i32, channels: c_int, err: ?*c_int) ?*OpusDecoder;
extern fn opus_decoder_destroy(st: ?*OpusDecoder) void;
extern fn opus_decode(
    st: *OpusDecoder,
    data: [*]const u8,
    len: i32,
    pcm: [*]i16,
    frame_size: c_int,
    decode_fec: c_int,
) c_int;
extern fn opus_decoder_ctl(st: *OpusDecoder, request: c_int, ...) c_int;

const spc_types = @import("spc_types.zig");
pub const Channel = spc_types.Channel;
pub const SpcPlayer = spc_types.SpcPlayer;

fn player() *SpcPlayer {
    return @ptrCast(@alignCast(g_zenv.player.?));
}

/// This needs to hold a lot more things than with just PCM
const MsuPlayerResumeInfo = extern struct {
    tag: u32,
    offset: u32,
    samples_until_repeat: u32,
    range_cur: u16,
    range_repeat: u16,
    initial_packet_bytes: u64, // To verify we seeked right
    orig_track: u8, // Using the old zelda track numbers
    actual_track: u8, // The MSU track index we're playing (Different if using msu deluxe)
};

const kMsuState_Idle: u8 = 0;
const kMsuState_FinishedPlaying: u8 = 1;
const kMsuState_Resuming: u8 = 2;
const kMsuState_Playing: u8 = 3;

const MsuPlayer = extern struct {
    f: ?*FILE,
    buffer_size: u32,
    buffer_pos: u32,
    preskip: u32,
    samples_until_repeat: u32,
    total_samples_in_file: u32,
    repeat_position: u32,
    cur_file_offs: u32,
    resume_info: MsuPlayerResumeInfo,
    enabled: u8,
    state: u8,
    volume: f32,
    volume_step: f32,
    volume_target: f32,
    range_cur: u16,
    range_repeat: u16,
    opus: ?*OpusDecoder,
    buffer: [960 * 2]i16,
    /// A FLAC or Ogg track, read through its decoder instead of `f`. Its
    /// positions are in samples, the same as a .pcm's.
    track: ?*msu_codec.Track,
    /// The track number of the file that's open. Not always the one asked
    /// for: a deluxe area track the pack hasn't got plays the song's own.
    file_track: u8,
    /// The open track's own rate. When the output runs at another, it's
    /// resampled on the way out: `rs_frac` is how far between the two
    /// source frames `rs_a` and `rs_b` the next output sample falls.
    rate: u32,
    rs_frac: f64,
    rs_a: [2]i16,
    rs_b: [2]i16,
    rs_primed: bool,
};

fn isOpen(mp: *const MsuPlayer) bool {
    return mp.f != null or mp.track != null;
}

var g_msu_player: MsuPlayer = std.mem.zeroes(MsuPlayer);

const kMsuTracksWithRepeat = [48]u8{
    1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 0,
    1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1,
    1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};

// 1 = ow songs : 2 = lw, 5 = forest, 7 = town, 9 = dark world, 13 = mountain
// 2 = indoor songs : 16, 17, 18, 22, 23, 27
const kIsMusicOwOrDungeon = [32]u8{
    0, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0,
    2, 2, 2, 0, 0, 0, 2, 2, 0, 0, 0, 2, 0, 0, 0, 0,
};

const kMsuDeluxe_OW_Songs = [160]u8{
    37, 37, 42, 38, 38, 38, 38, 39, 37,  37,  42, 38, 38, 38, 38, 41, // lw
    42, 42, 42, 42, 42, 42, 40, 40, 43,  43,  42, 47, 47, 42, 45, 45,
    43, 43, 43, 47, 47, 42, 45, 45, 112, 112, 48, 42, 42, 42, 42, 45,
    44, 44, 48, 48, 48, 46, 46, 46, 44,  44,  44, 48, 48, 46, 46, 46,
    49, 49, 51, 50, 50, 50, 50, 50,  49, 49, 51, 50, 50, 50, 50, 51, // dw
    51, 51, 51, 51, 51, 51, 51, 51,  52, 52, 51, 56, 56, 51, 54, 54,
    52, 52, 52, 56, 56, 51, 54, 54,  58, 52, 57, 51, 51, 51, 51, 54,
    53, 53, 57, 57, 57, 55, 55, 110, 53, 53, 57, 57, 57, 55, 55, 110,
    37, 41, 41, 42, 42, 42, 42, 42, 42, 41, 41, 42, 42, 42, 42, 42, // special
    42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42,
};

const kMsuDeluxe_Entrance_Songs = [133]u8{
    59, 59, 60,  61,  61,  61,  62,  62,  63, 64,  64,  64,  105, 65,  65,  66,
    66, 62, 67,  62,  62,  68,  62,  62,  68, 68,  62,  62,  62,  62,  62,  62,
    62, 62, 62,  62,  69,  70,  71,  72,  73, 73,  73,  106, 102, 74,  62,  62,
    75, 75, 76,  77,  78,  68,  79,  80,  81, 62,  62,  62,  82,  75,  242, 59,
    59, 76, 242, 242, 242, 96,  83,  99,  59, 242, 242, 242, 84,  95,  104, 62,
    85, 62, 62,  86,  242, 67,  103, 83,  83, 87,  76,  88,  81,  98,  81,  88,
    83, 89, 75,  97,  90,  91,  91,  100, 92, 93,  92,  242, 93,  107, 62,  75,
    62, 67, 62,  242, 242, 242, 73,  73,  73, 73,  102, 114, 81,  76,  62,  67,
    62, 61, 94,  62,  103,
};

const kVolumeTransitionTarget = [4]u8{ 0, 64, 255, 255 };
const kVolumeTransitionStep = [4]u8{ 7, 3, 3, 24 };
// These are precomputed in the config parse
var kVolumeTransitionStepFloat: [4]f32 = @splat(0);
var kVolumeTransitionTargetFloat: [4]f32 = @splat(0);

/// Remap an track number into a potentially different track number (used for msu deluxe)
fn RemapMsuDeluxeTrack(mp: *const MsuPlayer, track: u8) u8 {
    if ((mp.enabled & kMsuEnabled_MsuDeluxe) == 0 or track >= kIsMusicOwOrDungeon.len)
        return track;
    switch (kIsMusicOwOrDungeon[track]) {
        1 => {
            const area: u8 = @truncate(vars.overworld_area_index.*);
            return if (area < kMsuDeluxe_OW_Songs.len) kMsuDeluxe_OW_Songs[area] else track;
        },
        2 => {
            const entrance = vars.which_entrance.*;
            if (entrance >= kMsuDeluxe_Entrance_Songs.len or kMsuDeluxe_Entrance_Songs[entrance] == 242)
                return track;
            return kMsuDeluxe_Entrance_Songs[entrance];
        },
        else => return track,
    }
}

pub export fn ZeldaIsPlayingMusicTrack(track: u8) callconv(.c) bool {
    const mp = &g_msu_player;
    if (mp.state != kMsuState_Idle and (mp.enabled & kMsuEnabled_MsuDeluxe) != 0) {
        return RemapMsuDeluxeTrack(mp, track) == mp.resume_info.actual_track;
    } else {
        return track == vars.music_unk1.*;
    }
}

pub export fn ZeldaIsPlayingMusicTrackWithBug(track: u8) callconv(.c) bool {
    const mp = &g_msu_player;
    if (mp.state != kMsuState_Idle and (mp.enabled & kMsuEnabled_MsuDeluxe) != 0) {
        return RemapMsuDeluxeTrack(mp, track) == mp.resume_info.actual_track;
    } else {
        const cur = if (features.enhanced_features0.* & features.kFeatures0_MiscBugFixes != 0)
            vars.music_unk1.*
        else
            vars.last_music_control.*;
        return track == cur;
    }
}

/// Tracks worth waiting for, by the number the game asks for rather than the
/// one deluxe remaps it to.
///
/// Only the mirror warp needs this. The game replaces that cue on a fixed
/// animation timer, about a second and a half in, which suits the short SPC
/// version and cuts a longer MSU one off mid-phrase every time.
///
/// The pack marks other tracks as one-shots as well - the intro among them -
/// and waiting for those would hold back the music that is meant to follow,
/// which is how it is supposed to work rather than a fault. So this is a list
/// of cues, not every non-looping track.
const kMsuCueTracks = [_]u8{8};

/// True while one of those cues is still playing. The caller leaves its
/// pending music request alone and comes back to it next frame.
pub export fn ZeldaMsuCueStillPlaying() callconv(.c) bool {
    const mp = &g_msu_player;
    if (!config.g_config.msu_finish_cues or !isOpen(mp))
        return false;
    if (mp.state != kMsuState_Playing and mp.state != kMsuState_Resuming)
        return false;
    const playing = mp.resume_info.orig_track;
    for (kMsuCueTracks) |cue| {
        if (playing == cue) return true;
    }
    return false;
}

pub export fn ZeldaGetEntranceMusicTrack(i: c_int) callconv(.c) u8 {
    const mp = &g_msu_player;
    const kEntranceData_musicTrack = g_asset_ptrs[27].?;
    var rv = kEntranceData_musicTrack[@intCast(i)];

    // For some entrances the original performs a fade out, while msu deluxe has new tracks.
    if (mp.state != kMsuState_Idle and (mp.enabled & kMsuEnabled_MsuDeluxe) != 0) {
        if (rv == 242 and kMsuDeluxe_Entrance_Songs[vars.which_entrance.*] != 242)
            rv = 16;
    }

    return rv;
}

pub export fn ZeldaPlayMsuAudioTrack(music_ctrl: u8) callconv(.c) void {
    const mp = &g_msu_player;
    if (mp.enabled == 0) {
        mp.resume_info.tag = 0;
        zelda_apu_write(APUI00, music_ctrl);
        return;
    }
    // Finding the file and setting up its decoder happen before the lock,
    // which the sound card waits on: an Ogg file is read to its end to learn
    // how long it is, and that's no time to hold the audio up.
    var prep: ?Prepared = if ((music_ctrl & 0xf0) != 0xf0) prepareTrack(mp, music_ctrl) else null;
    defer if (prep) |*p| p.discard();
    ZeldaApuLock();
    if (prep) |*p| {
        MsuPlayer_OpenPrepared(mp, p, false);
    } else if (music_ctrl >= 0xf1 and music_ctrl <= 0xf3) {
        mp.volume_target = kVolumeTransitionTargetFloat[music_ctrl - 0xf1];
        mp.volume_step = kVolumeTransitionStepFloat[music_ctrl - 0xf1];
    }

    if (mp.state == 0) {
        zelda_apu_write(APUI00, music_ctrl);
    } else {
        zelda_apu_write(APUI00, 0xf0); // pause spc player
    }
    ZeldaApuUnlock();
}

fn MsuPlayer_CloseFile(mp: *MsuPlayer) void {
    if (mp.f) |f|
        _ = fclose(f);
    opus_decoder_destroy(mp.opus);
    mp.opus = null;
    mp.f = null;
    if (mp.track) |t| t.close();
    mp.track = null;
    if (mp.state != kMsuState_FinishedPlaying)
        mp.state = kMsuState_Idle;
    mp.resume_info = std.mem.zeroes(MsuPlayerResumeInfo);
}

/// A track found and opened, ready to swap in: what the slow part of
/// starting a track leaves for the quick part, under the lock.
const Prepared = struct {
    orig: u8,
    actual_track: u8,
    file_track: u8,
    f: ?*FILE = null,
    track: ?*msu_codec.Track = null,
    header: [8]u8 = @splat(0),
    have_header: bool = false,
    fname: [256]u8 = @splat(0),

    /// Closes whatever wasn't taken.
    fn discard(self: *Prepared) void {
        if (self.f) |f| _ = fclose(f);
        if (self.track) |t| t.close();
        self.f = null;
        self.track = null;
    }
};

/// Finds track `orig_track` (as deluxe remaps it) in the pack and opens it,
/// touching nothing the audio thread uses.
fn prepareTrack(mp: *const MsuPlayer, orig_track: c_int) Prepared {
    const orig: u8 = @truncate(@as(c_uint, @bitCast(orig_track)));
    const actual_track = RemapMsuDeluxeTrack(mp, orig);
    var p = Prepared{ .orig = orig, .actual_track = actual_track, .file_track = actual_track };
    if (actual_track == 0) return p;
    // Deluxe packs often leave some areas' tracks out. Those areas play the
    // pack's ordinary track for the song rather than the SNES's.
    if (actual_track != orig) {
        if (openTrackFile(mp, &p.fname, actual_track)) |f| {
            p.f = f;
        } else p.file_track = orig;
    }
    if (p.f == null) p.f = openTrackFile(mp, &p.fname, p.file_track);
    _ = printf("Loading MSU %s\n", &p.fname);
    const f = p.f orelse return p;
    _ = setvbuf(f, null, _IOFBF, 16384);
    p.have_header = fread(&p.header, 1, 8, f) == 8;
    if (p.have_header) if (msu_codec.kindOf(&p.header)) |kind| {
        // The decoder opens it again itself.
        _ = fclose(f);
        p.f = null;
        p.track = msu_codec.Track.open(@ptrCast(&p.fname), kind);
    };
    return p;
}

/// Opens and swaps in a track in one go, for callers already holding the
/// lock (a snapshot's music coming back) and for tests.
fn MsuPlayer_Open(mp: *MsuPlayer, orig_track: c_int, resume_from_snapshot: bool) void {
    var p = prepareTrack(mp, orig_track);
    defer p.discard();
    MsuPlayer_OpenPrepared(mp, &p, resume_from_snapshot);
}

/// Starts the prepared track, taking its file or decoder. With the lock
/// held.
fn MsuPlayer_OpenPrepared(mp: *MsuPlayer, p: *Prepared, resume_from_snapshot: bool) void {
    var resume_info: MsuPlayerResumeInfo = undefined;
    const actual_track = p.actual_track;
    const orig = p.orig;
    const file_track = p.file_track;

    if (!resume_from_snapshot) {
        resume_info.tag = 0;
        // Attempt to resume MSU playback when exiting back to the overworld.
        const alt: *align(1) const MsuPlayerResumeInfo = @ptrCast(vars.msu_resume_info_alt);
        if (vars.main_module_index.* == 9 and actual_track == alt.actual_track and config.g_config.resume_msu) {
            resume_info = alt.*;
        }
    } else {
        const snap: *align(1) const MsuPlayerResumeInfo = @ptrCast(vars.msu_resume_info);
        resume_info = snap.*;
    }

    // Two deluxe areas side by side that both play the song's own track:
    // walking from one to the other carries on with it rather than
    // starting it over.
    if (!resume_from_snapshot and file_track != actual_track and isOpen(mp) and
        mp.state >= kMsuState_Resuming and mp.file_track == file_track)
    {
        mp.resume_info.actual_track = actual_track;
        mp.resume_info.orig_track = orig;
        mp.volume_target = kVolumeTransitionTargetFloat[3];
        mp.volume_step = kVolumeTransitionStepFloat[3];
        return;
    }
    if (!resume_from_snapshot and mp.state >= kMsuState_Resuming) {
        const alt_dst: *align(1) MsuPlayerResumeInfo = @ptrCast(vars.msu_resume_info_alt);
        alt_dst.* = mp.resume_info;
    }

    mp.volume_target = kVolumeTransitionTargetFloat[3];
    mp.volume_step = kVolumeTransitionStepFloat[3];

    mp.state = kMsuState_Idle;
    MsuPlayer_CloseFile(mp);
    if (actual_track == 0)
        return;

    const fname = &p.fname;
    mp.file_track = file_track;
    mp.rs_primed = false;
    mp.rs_frac = 0;
    if (p.f == null and p.track == null) return openReadError(mp, fname);
    if (!p.have_header) return openReadError(mp, fname);
    mp.f = p.f;
    p.f = null;

    var file_tag = std.mem.readInt(u32, p.header[0..4], .little);
    mp.repeat_position = std.mem.readInt(u32, p.header[4..8], .little);
    if (msu_codec.kindOf(&p.header)) |kind| {
        const t = p.track orelse return openReadError(mp, fname);
        mp.track = t;
        p.track = null;
        if (t.frames > std.math.maxInt(u32)) return openReadError(mp, fname);
        file_tag = msu_codec.tag(kind);
        mp.repeat_position = @intCast(t.loop_start);
    }
    mp.state = if (resume_info.actual_track == actual_track and resume_info.tag == file_tag)
        kMsuState_Resuming
    else
        kMsuState_Playing;
    if (mp.state == kMsuState_Resuming) {
        mp.resume_info = resume_info;
    } else {
        mp.resume_info.orig_track = orig;
        mp.resume_info.actual_track = actual_track;
        mp.resume_info.tag = file_tag;
        mp.resume_info.range_cur = 8;
    }
    mp.cur_file_offs = mp.resume_info.offset;
    mp.samples_until_repeat = mp.resume_info.samples_until_repeat;
    mp.range_cur = mp.resume_info.range_cur;
    mp.range_repeat = mp.resume_info.range_repeat;
    mp.buffer_size = 0;
    mp.buffer_pos = 0;
    mp.preskip = 0;

    const kTagOpuz: u32 = ('Z' << 24) | ('U' << 16) | ('P' << 8) | 'O';
    const kTagMsu1: u32 = ('1' << 24) | ('U' << 16) | ('S' << 8) | 'M';
    if (file_tag == kTagOpuz) {
        mp.opus = opus_decoder_create(48000, 2, null);
        if (mp.opus == null)
            return openReadError(mp, fname);
        mp.rate = 48000;
        if (mp.state == kMsuState_Resuming)
            _ = fseek(mp.f.?, @intCast(mp.cur_file_offs), SEEK_SET);
    } else if (file_tag == kTagMsu1) {
        _ = fseek(mp.f.?, 0, SEEK_END);
        mp.total_samples_in_file = @intCast(@divTrunc(ftell(mp.f.?) - 8, 4));
        mp.rate = 44100;
        // A loop point past the end (a badly made track) loops from the
        // start, rather than failing at the end and dropping to the SNES
        // music; a resume past it (another file by the same name) starts over.
        if (mp.repeat_position >= mp.total_samples_in_file) mp.repeat_position = 0;
        if (mp.cur_file_offs > mp.total_samples_in_file) mp.cur_file_offs = 0;
        mp.samples_until_repeat = mp.total_samples_in_file -% mp.cur_file_offs;
        _ = fseek(mp.f.?, msuSeekOffset(mp.cur_file_offs), SEEK_SET);
    } else if (mp.track) |t| {
        mp.total_samples_in_file = @intCast(t.frames);
        mp.rate = t.rate;
        // A resume past the end (a different file under the same name) starts over.
        if (mp.cur_file_offs >= mp.total_samples_in_file) mp.cur_file_offs = 0;
        mp.samples_until_repeat = mp.total_samples_in_file - mp.cur_file_offs;
        if (!t.seek(mp.cur_file_offs)) return openReadError(mp, fname);
    } else {
        return openReadError(mp, fname);
    }
}

/// Opens track `n` of the pack: the first of .pcm, .flac, .ogg and .opuz
/// that's there. `fname` is left naming it, or
/// the .pcm (the one most packs use) when there's none, for messages.
fn openTrackFile(mp: *const MsuPlayer, fname: *[256]u8, n: u8) ?*FILE {
    _ = mp;
    const exts = &msu_codec.kTrackExts;
    const prefix = if (config.g_config.msu_path) |p| p else @as([*:0]const u8, "");
    for (exts) |ext| {
        _ = snprintf(fname, fname.len, "%s%d.%.*s", prefix, @as(c_int, n), @as(c_int, @intCast(ext.len)), ext.ptr);
        if (fopen(@ptrCast(fname), "rb")) |f| return f;
    }
    _ = snprintf(fname, fname.len, "%s%d.%.*s", prefix, @as(c_int, n), @as(c_int, @intCast(exts[0].len)), exts[0].ptr);
    return null;
}

/// Byte offset of a sample index in an MSU file, past the 8 byte header.
///
/// fseek takes a c_long, which is 64-bit on Linux and macOS but 32-bit on
/// Windows, so the multiply has to happen in a type that holds it either way.
fn msuSeekOffset(sample: u32) c_long {
    return @intCast(@as(i64, sample) * 4 + 8);
}

fn openReadError(mp: *MsuPlayer, fname: *const [256]u8) void {
    std.debug.print("Unable to read MSU file {s}\n", .{std.mem.sliceTo(fname, 0)});
    MsuPlayer_CloseFile(mp);
}

fn MixToBufferWithVolume(dst: [*]i16, src: [*]const i16, n: usize, volume: f32) void {
    if (volume == 1.0) {
        for (0..n) |i| {
            dst[i * 2 + 0] +|= src[i * 2 + 0];
            dst[i * 2 + 1] +|= src[i * 2 + 1];
        }
    } else {
        // The C multiplies a promoted int16 by an unsigned volume, so the whole
        // product is computed in unsigned arithmetic before being truncated back.
        const vol: u32 = @bitCast(@as(i32, @intFromFloat(65536 * volume)));
        for (0..n) |i| {
            dst[i * 2 + 0] +|= scaleSample(src[i * 2 + 0], vol);
            dst[i * 2 + 1] +|= scaleSample(src[i * 2 + 1], vol);
        }
    }
}

fn scaleSample(sample: i16, vol: u32) i16 {
    const widened: u32 = @bitCast(@as(i32, sample));
    return @bitCast(@as(u16, @truncate((widened *% vol) >> 16)));
}

fn MixToBufferWithVolumeRamp(
    dst: [*]i16,
    src: [*]const i16,
    n: usize,
    volume: f32,
    volume_step: f32,
    ideal_target: f32,
) void {
    _ = ideal_target; // the C accepts but never reads this
    var vol: i64 = @intFromFloat(volume * 281474976710656.0);
    const step: i64 = @intFromFloat(volume_step * 281474976710656.0);
    for (0..n) |i| {
        const v: u32 = @truncate(@as(u64, @bitCast(vol >> 32)));
        dst[i * 2 + 0] +|= scaleSample(src[i * 2 + 0], v);
        dst[i * 2 + 1] +|= scaleSample(src[i * 2 + 1], v);
        vol +%= step;
    }
}

fn MixToBuffer(mp: *MsuPlayer, dst_in: [*]i16, src_in: [*]const i16, n_in: u32) void {
    var dst = dst_in;
    var src = src_in;
    var n = n_in;
    if (mp.volume != mp.volume_target) {
        const step = if (mp.volume < mp.volume_target) mp.volume_step else -mp.volume_step;
        var new_vol = mp.volume + step * @as(f32, @floatFromInt(n));
        var curn = n;
        const overshot = if (step >= 0) new_vol >= mp.volume_target else new_vol < mp.volume_target;
        if (overshot) {
            const maxn: u32 = @intFromFloat((mp.volume_target - mp.volume) / step);
            curn = @min(maxn, curn);
            new_vol = mp.volume_target;
        }
        const vol = mp.volume;
        mp.volume = new_vol;
        MixToBufferWithVolumeRamp(dst, src, curn, vol, step, new_vol);
        dst += curn * 2;
        src += curn * 2;
        n -= curn;
    }
    MixToBufferWithVolume(dst, src, n, mp.volume);
}

/// The C reaches these through `goto` into labeled blocks inside the loop.
fn mixFinishedPlaying(mp: *MsuPlayer) void {
    mp.state = kMsuState_FinishedPlaying;
    MsuPlayer_CloseFile(mp);
}

fn mixReadError(mp: *MsuPlayer) void {
    std.debug.print("MSU read/decode error!\n", .{});
    zelda_apu_write(APUI00, mp.resume_info.orig_track);
    MsuPlayer_CloseFile(mp);
}

/// Decodes the track's next stretch into `mp.buffer`, looping where it
/// loops. False when there's no more: it finished, or failed, and the
/// player has closed it.
fn refill(mp: *MsuPlayer) bool {
    var r: c_int = undefined;
    if (mp.opus != null) {
        if (mp.samples_until_repeat == 0) {
            if (mp.range_cur == 0) {
                mixFinishedPlaying(mp);
                return false;
            }
            _ = opus_decoder_ctl(mp.opus.?, OPUS_RESET_STATE);
            _ = fseek(mp.f.?, mp.range_cur, SEEK_SET);
            const file_data: [*]u8 = @ptrCast(&mp.buffer);
            if (fread(file_data, 1, 10, mp.f.?) != 10) {
                mixReadError(mp);
                return false;
            }
            const file_offs = std.mem.readInt(u32, file_data[0..4], .little);
            std.debug.assert((file_offs & 0xF0000000) == 0);
            const samples_until_repeat = std.mem.readInt(u32, file_data[4..8], .little);
            const preskip: u16 = @truncate(std.mem.readInt(u32, file_data[8..12], .little));
            mp.samples_until_repeat = samples_until_repeat;
            mp.preskip = preskip & 0x3fff;
            if (preskip & 0x4000 != 0)
                mp.range_repeat = mp.range_cur;
            mp.range_cur = if (preskip & 0x8000 != 0) mp.range_repeat else mp.range_cur +% 10;
            mp.cur_file_offs = file_offs;
            mp.resume_info.range_repeat = mp.range_repeat;
            mp.resume_info.range_cur = mp.range_cur;
            _ = fseek(mp.f.?, @intCast(file_offs), SEEK_SET);
        }
        std.debug.assert(mp.samples_until_repeat != 0);
        while (true) {
            const file_data: [*]u8 = @ptrCast(&mp.buffer);
            @memset(file_data[0..8], 0);
            if (fread(file_data, 1, 2, mp.f.?) != 2) {
                mixReadError(mp);
                return false;
            }
            const header = std.mem.readInt(u16, file_data[0..2], .little);
            const size: usize = header & 0x7fff;
            if (size > 1275) {
                mixReadError(mp);
                return false;
            }
            const n: usize = header >> 15;
            if (fread(file_data + 2, 1, size, mp.f.?) != size) {
                mixReadError(mp);
                return false;
            }
            // Verify if the snapshot matches the file on disk.
            const initial_file_data = std.mem.readInt(u64, file_data[0..8], .little);
            if (mp.state == kMsuState_Resuming) {
                mp.state = kMsuState_Playing;
                if (mp.resume_info.initial_packet_bytes != initial_file_data) {
                    mixReadError(mp);
                    return false;
                }
            }
            mp.resume_info.initial_packet_bytes = initial_file_data;
            mp.resume_info.samples_until_repeat = mp.samples_until_repeat +% mp.preskip;
            mp.resume_info.offset = mp.cur_file_offs;
            mp.cur_file_offs +%= @intCast(2 + size);
            file_data[1] = 0xfc;
            r = opus_decode(mp.opus.?, file_data + (2 - n), @intCast(size + n), &mp.buffer, 960, 0);
            if (r <= 0) {
                mixReadError(mp);
                return false;
            }
            if (@as(u32, @intCast(r)) > mp.preskip)
                break;
            mp.preskip -= @intCast(r);
        }
    } else {
        if (mp.samples_until_repeat == 0) {
            if (mp.resume_info.actual_track < kMsuTracksWithRepeat.len and
                kMsuTracksWithRepeat[mp.resume_info.actual_track] == 0)
            {
                mixFinishedPlaying(mp);
                return false;
            }
            mp.samples_until_repeat = mp.total_samples_in_file -% mp.repeat_position;
            if (mp.samples_until_repeat == 0) {
                mixReadError(mp); // impossible to make progress
                return false;
            }
            mp.cur_file_offs = mp.repeat_position;
            if (mp.track) |t| {
                if (!t.seek(mp.cur_file_offs)) {
                    mixReadError(mp);
                    return false;
                }
            } else {
                _ = fseek(mp.f.?, msuSeekOffset(mp.cur_file_offs), SEEK_SET);
            }
        }
        r = @intCast(@min(@as(u32, 960), mp.samples_until_repeat));
        const want: usize = @intCast(r);
        const got = if (mp.track) |t|
            t.read(@as(*[960][2]i16, @ptrCast(&mp.buffer))[0..want])
        else
            fread(&mp.buffer, 4, want, mp.f.?);
        if (got != want) {
            mixReadError(mp);
            return false;
        }
        mp.resume_info.offset = mp.cur_file_offs;
        mp.cur_file_offs +%= @intCast(r);
    }
    const n = @min(@as(u32, @intCast(r)) -% mp.preskip, mp.samples_until_repeat);
    mp.samples_until_repeat -= n;
    mp.buffer_pos = mp.preskip;
    mp.buffer_size = mp.buffer_pos + n;
    mp.preskip = 0;
    return true;
}

pub export fn MsuPlayer_Mix(mp: *MsuPlayer, audio_buffer: [*]i16, audio_samples: c_int) callconv(.c) void {
    const out_rate = config.g_config.audio_freq;
    if (mp.rate == 0 or mp.rate == out_rate) {
        mixDirect(mp, audio_buffer, audio_samples);
    } else {
        mixResampled(mp, audio_buffer, @intCast(audio_samples), out_rate);
    }
}

/// The track's own rate is the output's: its frames go straight in.
fn mixDirect(mp: *MsuPlayer, audio_buffer_in: [*]i16, audio_samples_in: c_int) void {
    var audio_buffer = audio_buffer_in;
    var audio_samples = audio_samples_in;
    while (true) {
        if (mp.buffer_size -% mp.buffer_pos == 0) {
            if (!refill(mp)) return;
        }
        const nr: c_int = @min(audio_samples, @as(c_int, @intCast(mp.buffer_size - mp.buffer_pos)));
        const buf: [*]i16 = @as([*]i16, @ptrCast(&mp.buffer)) + mp.buffer_pos * 2;
        mp.buffer_pos += @intCast(nr);

        MixToBuffer(mp, audio_buffer, buf, @intCast(nr));

        audio_samples -= nr;
        audio_buffer += @as(usize, @intCast(nr)) * 2;
        if (audio_samples == 0) break;
    }
}

/// The track's next frame, or null once it's over.
fn nextFrame(mp: *MsuPlayer) ?[2]i16 {
    if (mp.buffer_size -% mp.buffer_pos == 0) {
        if (!refill(mp)) return null;
    }
    const frames: *const [960][2]i16 = @ptrCast(&mp.buffer);
    defer mp.buffer_pos += 1;
    return frames[mp.buffer_pos];
}

/// The track at another rate than the output: each output sample is read
/// between the two source frames it falls between. Linear, as the
/// randomizer's MSU-1 has always done it; for music already at CD quality
/// that's as good as the ear can tell at these rates.
fn mixResampled(mp: *MsuPlayer, out_in: [*]i16, samples: usize, out_rate: u32) void {
    const step = @as(f64, @floatFromInt(mp.rate)) / @as(f64, @floatFromInt(out_rate));
    var out = out_in;
    var left = samples;
    var tmp: [256][2]i16 = undefined;
    if (!mp.rs_primed) {
        mp.rs_a = nextFrame(mp) orelse return;
        mp.rs_b = nextFrame(mp) orelse mp.rs_a;
        mp.rs_frac = 0;
        mp.rs_primed = true;
    }
    var ended = false;
    while (left != 0 and !ended) {
        const want = @min(left, tmp.len);
        var n: usize = 0;
        while (n < want) {
            const t: f32 = @floatCast(mp.rs_frac);
            for (0..2) |ch| {
                const a: f32 = @floatFromInt(mp.rs_a[ch]);
                const b: f32 = @floatFromInt(mp.rs_b[ch]);
                tmp[n][ch] = @intFromFloat(a + (b - a) * t);
            }
            n += 1;
            mp.rs_frac += step;
            while (mp.rs_frac >= 1.0) {
                mp.rs_frac -= 1.0;
                mp.rs_a = mp.rs_b;
                mp.rs_b = nextFrame(mp) orelse {
                    ended = true;
                    break;
                };
            }
            if (ended) break;
        }
        MixToBuffer(mp, out, @ptrCast(&tmp), @intCast(n));
        out += n * 2;
        left -= n;
    }
}

// Maintain a queue cause the snes and audio callback are not in sync.
const ApuWriteEnt = extern struct { ports: [4]u8 };
var g_apu_write_ents: [16]ApuWriteEnt = @splat(.{ .ports = @splat(0) });
var g_apu_write: ApuWriteEnt = .{ .ports = @splat(0) };
var g_apu_write_ent_pos: u8 = 0;
var g_apu_write_count: u8 = 0;
var g_apu_total_write: u8 = 0;

pub export fn zelda_apu_write(adr: u32, val: u8) callconv(.c) void {
    g_apu_write.ports[adr & 0x3] = val;
}

/// What the last frame sent to the first sound effect port. The NMI writes it
/// every frame, zero when nothing played.
pub fn lastSoundEffect1() u8 {
    return g_apu_write.ports[2];
}

/// The same for the second sound effect port.
pub fn lastSoundEffect2() u8 {
    return g_apu_write.ports[3];
}

pub export fn ZeldaPushApuState() callconv(.c) void {
    ZeldaApuLock();
    g_apu_write_ents[g_apu_write_ent_pos & 0xf] = g_apu_write;
    g_apu_write_ent_pos +%= 1;
    if (g_apu_write_count < 16)
        g_apu_write_count += 1;
    g_apu_total_write +%= 1;
    ZeldaApuUnlock();
}

fn ZeldaPopApuState() void {
    if (g_apu_write_count != 0) {
        const idx = (g_apu_write_ent_pos -% g_apu_write_count) & 0xf;
        g_apu_write_count -%= 1;
        player().input_ports = g_apu_write_ents[idx].ports;
    }
}

pub export fn ZeldaDiscardUnusedAudioFrames() callconv(.c) void {
    const idx = (g_apu_write_ent_pos -% g_apu_write_count) & 0xf;
    if (g_apu_write_count != 0 and
        std.mem.eql(u8, &player().input_ports, &g_apu_write_ents[idx].ports))
    {
        if (g_apu_total_write >= 16) {
            g_apu_total_write = 14;
            g_apu_write_count -= 1;
        }
    } else {
        g_apu_total_write = 0;
    }
}

fn ZeldaResetApuQueue() void {
    g_apu_write_ent_pos = 0;
    g_apu_total_write = 0;
    g_apu_write_count = 0;
}

pub export fn zelda_read_apui00() callconv(.c) u8 {
    // This needs to be here because the ancilla code reads
    // from the apu and we don't want to make the core code
    // dependent on the apu timings, so relocated this value
    // to 0x648.
    return g_ram[kRam_APUI00];
}

pub export fn zelda_apu_read(adr: u32) callconv(.c) u8 {
    return player().port_to_snes[adr & 0x3];
}

pub export fn ZeldaRenderAudio(audio_buffer: [*]i16, samples: c_int, channels: c_int) callconv(.c) void {
    ZeldaApuLock();
    ZeldaPopApuState();
    SpcPlayer_GenerateSamples(player());
    dsp_mod.dsp_getSamples(player().dsp.?, audio_buffer, samples, channels);
    if (isOpen(&g_msu_player)) {
        if (channels == 2) {
            MsuPlayer_Mix(&g_msu_player, audio_buffer, samples);
        } else if (channels == 1) {
            mixMono(&g_msu_player, audio_buffer, @intCast(samples));
        }
    }
    ZeldaApuUnlock();
}

/// MSU tracks are stereo: mixed into a stereo scratch buffer first, then
/// both sides, halved, into the mono output.
fn mixMono(mp: *MsuPlayer, out: [*]i16, samples: usize) void {
    var tmp: [1024 * 2]i16 = undefined;
    var done: usize = 0;
    while (done < samples and isOpen(mp)) {
        const n: usize = @min(1024, samples - done);
        @memset(tmp[0 .. n * 2], 0);
        MsuPlayer_Mix(mp, &tmp, @intCast(n));
        for (0..n) |i| {
            const m: i16 = @intCast((@as(i32, tmp[i * 2]) + tmp[i * 2 + 1]) >> 1);
            out[done + i] +|= m;
        }
        done += n;
    }
}

pub export fn ZeldaIsMusicPlaying() callconv(.c) bool {
    if (g_msu_player.state != kMsuState_Idle) {
        return g_msu_player.state != kMsuState_FinishedPlaying;
    } else {
        return player().port_to_snes[0] != 0;
    }
}

pub export fn ZeldaRestoreMusicAfterLoad_Locked(is_reset: bool) callconv(.c) void {
    // Restore spc variables from the ram dump.
    SpcPlayer_CopyVariablesFromRam(player());
    // This is not stored in the snapshot
    player().timer_cycles = 0;

    // Restore input ports state
    const spc_player = player();
    spc_player.input_ports = spc_player.ram[0x410..0x414].*;
    g_apu_write.ports = spc_player.input_ports;

    if (is_reset)
        SpcPlayer_Initialize(player());

    const mp = &g_msu_player;
    if (mp.enabled != 0) {
        mp.volume = 0.0;
        const snap: *align(1) const MsuPlayerResumeInfo = @ptrCast(vars.msu_resume_info);
        const track: c_int = if (vars.music_unk1.* == 0xf1) snap.orig_track else vars.music_unk1.*;
        MsuPlayer_Open(mp, track, true);

        // If resuming in the middle of a transition, then override
        // the volume with that of the transition.
        const last = vars.last_music_control.*;
        if (last >= 0xf1 and last <= 0xf3) {
            const target = kVolumeTransitionTarget[last - 0xf1];
            if (target != features.msu_volume.*) {
                const f = kVolumeTransitionTargetFloat[3] * (1.0 / 255.0);
                mp.volume = @as(f32, @floatFromInt(features.msu_volume.*)) * f;
                mp.volume_target = @as(f32, @floatFromInt(target)) * f;
                mp.volume_step = kVolumeTransitionStepFloat[last - 0xf1];
            }
        }

        if (g_msu_player.state != 0)
            zelda_apu_write(APUI00, 0xf0); // pause spc player
    }
    ZeldaResetApuQueue();
}

pub export fn ZeldaSaveMusicStateToRam_Locked() callconv(.c) void {
    SpcPlayer_CopyVariablesToRam(player());
    // SpcPlayer.input_ports is not saved to the SpcPlayer ram by SpcPlayer_CopyVariablesToRam,
    // in any case, we want to save the most recently written data, and that might still
    // be in the queue. 0x410 is a free memory location in the SPC ram, so store it there.
    const spc_player = player();
    spc_player.ram[0x410..0x414].* = g_apu_write.ports;

    features.msu_volume.* = @intFromFloat(g_msu_player.volume * 255);
    const dst: *align(1) MsuPlayerResumeInfo = @ptrCast(vars.msu_resume_info);
    dst.* = g_msu_player.resume_info;
}

pub export fn ZeldaEnableMsu(enable: u8) callconv(.c) void {
    g_msu_player.volume = 1.0;
    g_msu_player.enabled = enable;

    const msuvolume: f32 = @floatFromInt(config.g_config.msuvolume);
    const freq: f32 = @floatFromInt(config.g_config.audio_freq);
    const volscale = msuvolume * (1.0 / 255.0 / 100.0);
    const stepscale = msuvolume * (60.0 / 256.0 / 100.0) / freq;
    for (0..kVolumeTransitionStepFloat.len) |i| {
        kVolumeTransitionStepFloat[i] = @as(f32, @floatFromInt(kVolumeTransitionStep[i])) * stepscale;
        kVolumeTransitionTargetFloat[i] = @as(f32, @floatFromInt(kVolumeTransitionTarget[i])) * volscale;
    }
}

pub export fn LoadSongBank(p: [*]const u8) callconv(.c) void { // 808888
    ZeldaApuLock();
    SpcPlayer_Upload(player(), p);
    ZeldaApuUnlock();
}

const testing = std.testing;

test "the SpcPlayer mirror matches the C layout" {
    try testing.expectEqual(64, @sizeOf(Channel));
    try testing.expectEqual(66176, @sizeOf(SpcPlayer));
    try testing.expectEqual(0, @offsetOf(SpcPlayer, "reg_write_history"));
    try testing.expectEqual(8, @offsetOf(SpcPlayer, "timer_cycles"));
    try testing.expectEqual(16, @offsetOf(SpcPlayer, "dsp"));
    try testing.expectEqual(24, @offsetOf(SpcPlayer, "new_value_from_snes"));
    try testing.expectEqual(28, @offsetOf(SpcPlayer, "port_to_snes"));
    try testing.expectEqual(32, @offsetOf(SpcPlayer, "last_value_from_snes"));
    try testing.expectEqual(36, @offsetOf(SpcPlayer, "counter_sf0c"));
    try testing.expectEqual(38, @offsetOf(SpcPlayer, "_always_zero"));
    try testing.expectEqual(108, @offsetOf(SpcPlayer, "pause_music_ctr"));
    try testing.expectEqual(109, @offsetOf(SpcPlayer, "port2_active"));
    try testing.expectEqual(111, @offsetOf(SpcPlayer, "port3_active"));
    try testing.expectEqual(113, @offsetOf(SpcPlayer, "port1_active"));
    try testing.expectEqual(122, @offsetOf(SpcPlayer, "input_ports"));
    try testing.expectEqual(126, @offsetOf(SpcPlayer, "channel"));
    try testing.expectEqual(638, @offsetOf(SpcPlayer, "ram"));
}

test "the resume info matches the layout it is memcpy'd into work ram as" {
    try testing.expectEqual(32, @sizeOf(MsuPlayerResumeInfo));
    try testing.expectEqual(0, @offsetOf(MsuPlayerResumeInfo, "tag"));
    try testing.expectEqual(4, @offsetOf(MsuPlayerResumeInfo, "offset"));
    try testing.expectEqual(8, @offsetOf(MsuPlayerResumeInfo, "samples_until_repeat"));
    try testing.expectEqual(12, @offsetOf(MsuPlayerResumeInfo, "range_cur"));
    try testing.expectEqual(14, @offsetOf(MsuPlayerResumeInfo, "range_repeat"));
    // The uint64 forces 8-byte alignment, leaving the two track bytes at the end.
    try testing.expectEqual(16, @offsetOf(MsuPlayerResumeInfo, "initial_packet_bytes"));
    try testing.expectEqual(24, @offsetOf(MsuPlayerResumeInfo, "orig_track"));
    try testing.expectEqual(25, @offsetOf(MsuPlayerResumeInfo, "actual_track"));
}

test "msu deluxe remaps only overworld and indoor songs" {
    var mp = std.mem.zeroes(MsuPlayer);
    @memset(g_ram[0..0x1000], 0);

    // With deluxe off nothing is remapped at all.
    mp.enabled = 0;
    try testing.expectEqual(2, RemapMsuDeluxeTrack(&mp, 2));

    mp.enabled = kMsuEnabled_MsuDeluxe;
    // Track 2 is an overworld song, so the area index picks the track.
    vars.overworld_area_index.* = 0;
    try testing.expectEqual(37, RemapMsuDeluxeTrack(&mp, 2));
    vars.overworld_area_index.* = 2;
    try testing.expectEqual(42, RemapMsuDeluxeTrack(&mp, 2));

    // Track 16 is an indoor song, keyed off the entrance instead.
    vars.which_entrance.* = 0;
    try testing.expectEqual(59, RemapMsuDeluxeTrack(&mp, 16));
    vars.which_entrance.* = 3;
    try testing.expectEqual(61, RemapMsuDeluxeTrack(&mp, 16));

    // 242 in the entrance table means "leave it alone".
    vars.which_entrance.* = 62;
    try testing.expectEqual(16, RemapMsuDeluxeTrack(&mp, 16));

    // Track 0 is neither, and anything past the table is returned as-is.
    try testing.expectEqual(0, RemapMsuDeluxeTrack(&mp, 0));
    try testing.expectEqual(200, RemapMsuDeluxeTrack(&mp, 200));
}

test "mixing at full volume is a plain add" {
    var dst = [_]i16{ 100, -100, 0, 0 };
    const src = [_]i16{ 20, 30, -40, -50 };
    MixToBufferWithVolume(&dst, &src, 2, 1.0);
    try testing.expectEqual(@as(i16, 120), dst[0]);
    try testing.expectEqual(@as(i16, -70), dst[1]);
    try testing.expectEqual(@as(i16, -40), dst[2]);
    try testing.expectEqual(@as(i16, -50), dst[3]);
}

test "mixing at half volume halves positive samples" {
    var dst = [_]i16{ 0, 0 };
    const src = [_]i16{ 1000, 2000 };
    MixToBufferWithVolume(&dst, &src, 1, 0.5);
    try testing.expectEqual(@as(i16, 500), dst[0]);
    try testing.expectEqual(@as(i16, 1000), dst[1]);
}

test "negative samples survive the C's unsigned-product truncation" {
    // The C promotes int16 to int, multiplies by an unsigned volume and shifts
    // logically, so the product is formed mod 2^32 rather than arithmetically.
    // Only the low 16 bits are kept, and for in-range samples those still come
    // out as ordinary scaling: half volume takes -1000 to -500.
    var dst = [_]i16{ 0, 0 };
    const src = [_]i16{ -1000, -32768 };
    MixToBufferWithVolume(&dst, &src, 1, 0.5);
    try testing.expectEqual(@as(i16, -500), dst[0]);
    try testing.expectEqual(@as(i16, -16384), dst[1]);

    // Pin the helper against the C expression across the range.
    for ([_]i16{ -32768, -1000, -1, 0, 1, 1000, 32767 }) |s| {
        const expected: i16 = @bitCast(@as(u16, @truncate((@as(u32, @bitCast(@as(i32, s))) *% 32768) >> 16)));
        try testing.expectEqual(expected, scaleSample(s, 32768));
    }
    // Halving rounds toward negative infinity, so -1 stays -1 rather than 0.
    try testing.expectEqual(@as(i16, -1), scaleSample(-1, 32768));
    try testing.expectEqual(@as(i16, 16383), scaleSample(32767, 32768));
}

test "the volume transition tables scale with the configured msu volume" {
    config.g_config.msuvolume = 100;
    config.g_config.audio_freq = 44100;
    ZeldaEnableMsu(kMsuEnabled_Msu);
    try testing.expectEqual(@as(u8, kMsuEnabled_Msu), g_msu_player.enabled);
    try testing.expectEqual(@as(f32, 1.0), g_msu_player.volume);
    // Target 255 at full volume maps to 1.0, and target 0 stays 0.
    try testing.expectApproxEqAbs(@as(f32, 1.0), kVolumeTransitionTargetFloat[2], 0.0001);
    try testing.expectEqual(@as(f32, 0.0), kVolumeTransitionTargetFloat[0]);
    try testing.expect(kVolumeTransitionStepFloat[3] > kVolumeTransitionStepFloat[1]);

    // Half volume halves the targets.
    config.g_config.msuvolume = 50;
    ZeldaEnableMsu(kMsuEnabled_Msu);
    try testing.expectApproxEqAbs(@as(f32, 0.5), kVolumeTransitionTargetFloat[2], 0.0001);
    g_msu_player.enabled = 0;
}

test "the apu write queue keeps the most recent four ports" {
    ZeldaResetApuQueue();
    g_apu_write = .{ .ports = @splat(0) };

    zelda_apu_write(0x2140, 0xf1);
    zelda_apu_write(0x2141, 0x22);
    // Only the low two bits of the address select a port.
    zelda_apu_write(0x2146, 0x33);
    try testing.expectEqual(@as(u8, 0xf1), g_apu_write.ports[0]);
    try testing.expectEqual(@as(u8, 0x22), g_apu_write.ports[1]);
    try testing.expectEqual(@as(u8, 0x33), g_apu_write.ports[2]);

    // Writing the same port again overwrites rather than queueing.
    zelda_apu_write(0x2140, 0x99);
    try testing.expectEqual(@as(u8, 0x99), g_apu_write.ports[0]);
    ZeldaResetApuQueue();
}

test "the music tables came over at the right sizes" {
    try testing.expectEqual(48, kMsuTracksWithRepeat.len);
    try testing.expectEqual(32, kIsMusicOwOrDungeon.len);
    try testing.expectEqual(160, kMsuDeluxe_OW_Songs.len);
    try testing.expectEqual(133, kMsuDeluxe_Entrance_Songs.len);
    try testing.expectEqual(4, kVolumeTransitionTarget.len);
    try testing.expectEqual(4, kVolumeTransitionStep.len);
    // The dark world block starts halfway through the overworld table.
    try testing.expectEqual(49, kMsuDeluxe_OW_Songs[64]);
    try testing.expectEqual(37, kMsuDeluxe_OW_Songs[0]);
}

test "a FLAC track plays sample for sample and loops at its LOOPSTART" {
    const flac_enc = @import("flac_enc.zig");
    const fileio = @import("fileio.zig");
    const path = ".zig-cache/audio-msu-test-2.flac";
    defer _ = fileio.remove(path);
    var samples: [3000 * 2]i16 = undefined;
    for (0..3000) |i| {
        samples[i * 2] = @intCast(i);
        samples[i * 2 + 1] = -@as(i16, @intCast(i));
    }
    const bytes = try flac_enc.encode(testing.allocator, &samples, .{ .loop_start = 1000 });
    defer testing.allocator.free(bytes);
    try fileio.writeWholeFile(path, bytes);

    @memset(g_ram[0..0x2000], 0);
    config.g_config.msuvolume = 100;
    config.g_config.audio_freq = 44100;
    config.g_config.msu_path = ".zig-cache/audio-msu-test-";
    config.g_config.resume_msu = false;
    defer config.g_config.msu_path = null;
    ZeldaEnableMsu(kMsuEnabled_Msu);
    defer g_msu_player.enabled = 0;
    const mp = &g_msu_player;
    MsuPlayer_Open(mp, 2, false);
    defer MsuPlayer_CloseFile(mp);
    try testing.expect(mp.track != null);
    try testing.expectEqual(kMsuState_Playing, mp.state);
    try testing.expectEqual(@as(u32, 1000), mp.repeat_position);
    mp.volume = 1.0;

    // Track 2 repeats: past the end it picks up again at sample 1000.
    var out: [3500 * 2]i16 = @splat(0);
    MsuPlayer_Mix(mp, &out, 3500);
    for (0..3000) |i| {
        try testing.expectEqual(@as(i16, @intCast(i)), out[i * 2]);
        try testing.expectEqual(-@as(i16, @intCast(i)), out[i * 2 + 1]);
    }
    try testing.expectEqual(@as(i16, 1000), out[3000 * 2]);
    try testing.expectEqual(@as(i16, 1499), out[3499 * 2]);
}

test "loud music and loud sound effects clip instead of wrapping around" {
    var dst = [_]i16{ 30000, -30000, 20000, -20000 };
    const src = [_]i16{ 10000, -10000, 10000, -10000 };
    MixToBufferWithVolume(&dst, &src, 2, 1.0);
    try testing.expectEqual(@as(i16, 32767), dst[0]);
    try testing.expectEqual(@as(i16, -32768), dst[1]);
    try testing.expectEqual(@as(i16, 30000), dst[2]);
    try testing.expectEqual(@as(i16, -30000), dst[3]);
}

/// A track counting up, so where the player is shows in every sample.
fn writeCountingTrack(path: [*:0]const u8, frames: usize, loop: ?u32) !void {
    return writeCountingTrackAt(path, frames, loop, 44100);
}

fn writeCountingTrackAt(path: [*:0]const u8, frames: usize, loop: ?u32, rate: u32) !void {
    const flac_enc = @import("flac_enc.zig");
    const fileio = @import("fileio.zig");
    const samples = try testing.allocator.alloc(i16, frames * 2);
    defer testing.allocator.free(samples);
    for (0..frames) |i| {
        samples[i * 2] = @intCast(i);
        samples[i * 2 + 1] = -@as(i16, @intCast(i));
    }
    const bytes = try flac_enc.encode(testing.allocator, samples, .{ .loop_start = loop, .rate = rate });
    defer testing.allocator.free(bytes);
    try fileio.writeWholeFile(path, bytes);
}

fn setUpMsuTest(prefix: [*:0]const u8, enable: u8) void {
    @memset(g_ram[0..0x2000], 0);
    config.g_config.msuvolume = 100;
    config.g_config.audio_freq = 44100;
    config.g_config.msu_path = prefix;
    config.g_config.resume_msu = false;
    ZeldaEnableMsu(enable);
}

test "a deluxe area track the pack hasn't got plays the song's own, and carries on across areas" {
    const fileio = @import("fileio.zig");
    const path = ".zig-cache/audio-deluxe-test-2.flac";
    defer _ = fileio.remove(path);
    try writeCountingTrack(path, 3000, null);
    setUpMsuTest(".zig-cache/audio-deluxe-test-", kMsuEnabled_Msu | kMsuEnabled_MsuDeluxe);
    defer {
        g_msu_player.enabled = 0;
        config.g_config.msu_path = null;
    }
    const mp = &g_msu_player;
    defer MsuPlayer_CloseFile(mp);

    // Area 0's deluxe track is 37, which this pack hasn't got: track 2 plays.
    vars.overworld_area_index.* = 0;
    MsuPlayer_Open(mp, 2, false);
    try testing.expect(isOpen(mp));
    try testing.expectEqual(@as(u8, 2), mp.file_track);
    try testing.expectEqual(@as(u8, 37), mp.resume_info.actual_track);
    mp.volume = 1.0;
    var out: [500 * 2]i16 = @splat(0);
    MsuPlayer_Mix(mp, &out, 500);
    try testing.expectEqual(@as(i16, 499), out[499 * 2]);

    // Area 3's is 38, missing too: the same track goes on where it was.
    const open_track = mp.track;
    vars.overworld_area_index.* = 3;
    MsuPlayer_Open(mp, 2, false);
    try testing.expectEqual(open_track, mp.track);
    try testing.expectEqual(@as(u8, 38), mp.resume_info.actual_track);
    @memset(&out, 0);
    MsuPlayer_Mix(mp, &out, 1);
    try testing.expectEqual(@as(i16, 500), out[0]);
}

test "MSU music comes through in mono, both sides together" {
    const fileio = @import("fileio.zig");
    const path = ".zig-cache/audio-mono-test-2.flac";
    defer _ = fileio.remove(path);
    // Left counts up, right is 100 more: the mono mix is halfway between.
    {
        const flac_enc = @import("flac_enc.zig");
        var samples: [2000 * 2]i16 = undefined;
        for (0..2000) |i| {
            samples[i * 2] = @intCast(i);
            samples[i * 2 + 1] = @intCast(i + 100);
        }
        const bytes = try flac_enc.encode(testing.allocator, &samples, .{});
        defer testing.allocator.free(bytes);
        try fileio.writeWholeFile(path, bytes);
    }
    setUpMsuTest(".zig-cache/audio-mono-test-", kMsuEnabled_Msu);
    defer {
        g_msu_player.enabled = 0;
        config.g_config.msu_path = null;
    }
    const mp = &g_msu_player;
    MsuPlayer_Open(mp, 2, false);
    defer MsuPlayer_CloseFile(mp);
    mp.volume = 1.0;
    var out: [1500]i16 = @splat(0);
    mixMono(mp, &out, out.len);
    try testing.expectEqual(@as(i16, 50), out[0]);
    try testing.expectEqual(@as(i16, 1149), out[1099]);
}

test "a .pcm whose loop point is past its end loops from the start" {
    const fileio = @import("fileio.zig");
    const path = ".zig-cache/audio-badloop-test-2.pcm";
    defer _ = fileio.remove(path);
    var bytes: [8 + 100 * 4]u8 = undefined;
    @memcpy(bytes[0..4], "MSU1");
    std.mem.writeInt(u32, bytes[4..8], 5000, .little);
    for (0..100) |i| {
        std.mem.writeInt(i16, bytes[8 + i * 4 ..][0..2], @intCast(i + 1), .little);
        std.mem.writeInt(i16, bytes[8 + i * 4 + 2 ..][0..2], @intCast(i + 1), .little);
    }
    try fileio.writeWholeFile(path, &bytes);
    setUpMsuTest(".zig-cache/audio-badloop-test-", kMsuEnabled_Msu);
    defer {
        g_msu_player.enabled = 0;
        config.g_config.msu_path = null;
    }
    const mp = &g_msu_player;
    MsuPlayer_Open(mp, 2, false);
    defer MsuPlayer_CloseFile(mp);
    mp.volume = 1.0;
    var out: [150 * 2]i16 = @splat(0);
    MsuPlayer_Mix(mp, &out, 150);
    try testing.expect(isOpen(mp));
    try testing.expectEqual(@as(i16, 100), out[99 * 2]);
    // Track 2 repeats, from the start since its loop point made no sense.
    try testing.expectEqual(@as(i16, 1), out[100 * 2]);
}

test "a track is resampled to whatever rate the game mixes at" {
    const fileio = @import("fileio.zig");
    const path = ".zig-cache/audio-resample-test-2.flac";
    defer _ = fileio.remove(path);
    try writeCountingTrack(path, 4000, null);
    setUpMsuTest(".zig-cache/audio-resample-test-", kMsuEnabled_Msu);
    config.g_config.audio_freq = 48000;
    defer {
        g_msu_player.enabled = 0;
        config.g_config.msu_path = null;
        config.g_config.audio_freq = 44100;
    }
    const mp = &g_msu_player;
    MsuPlayer_Open(mp, 2, false);
    defer MsuPlayer_CloseFile(mp);
    try testing.expectEqual(@as(u32, 44100), mp.rate);
    mp.volume = 1.0;
    // 44.1 kHz into 48 kHz: each output sample is 0.91875 of a frame on.
    var out: [3000 * 2]i16 = @splat(0);
    MsuPlayer_Mix(mp, &out, 3000);
    for ([_]usize{ 0, 1, 100, 1234, 2999 }) |k| {
        const want: f64 = @as(f64, @floatFromInt(k)) * 44100.0 / 48000.0;
        const got: f64 = @floatFromInt(out[k * 2]);
        try testing.expect(@abs(got - want) <= 1.0);
        try testing.expectEqual(-out[k * 2], out[k * 2 + 1]);
    }
}

test "a 48 kHz track plays, looping at its LOOPSTART through the resampling" {
    const fileio = @import("fileio.zig");
    const path = ".zig-cache/audio-48k-test-2.flac";
    defer _ = fileio.remove(path);
    try writeCountingTrackAt(path, 3000, 1000, 48000);
    setUpMsuTest(".zig-cache/audio-48k-test-", kMsuEnabled_Msu);
    config.g_config.audio_freq = 24000;
    defer {
        g_msu_player.enabled = 0;
        config.g_config.msu_path = null;
        config.g_config.audio_freq = 44100;
    }
    const mp = &g_msu_player;
    MsuPlayer_Open(mp, 2, false);
    defer MsuPlayer_CloseFile(mp);
    try testing.expect(isOpen(mp));
    try testing.expectEqual(@as(u32, 48000), mp.rate);
    mp.volume = 1.0;
    // Half the rate: every other frame, then from 1000 again at the end.
    var out: [1800 * 2]i16 = @splat(0);
    MsuPlayer_Mix(mp, &out, 1800);
    try testing.expectEqual(@as(i16, 0), out[0]);
    try testing.expectEqual(@as(i16, 2998), out[1499 * 2]);
    try testing.expectEqual(@as(i16, 1000), out[1500 * 2]);
    try testing.expectEqual(@as(i16, 1598), out[1799 * 2]);
}
