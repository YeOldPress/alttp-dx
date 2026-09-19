//! Port of src/audio.c: the MSU-1 / Opuz music player and the APU write queue
//! that bridges the emulated SNES and the audio callback thread.
const std = @import("std");
const vars = @import("variables.zig");
const rtl = @import("zelda_rtl_types.zig");
const features = @import("features.zig");
const config = @import("config.zig");
const dsp_mod = @import("../snes/dsp.zig");

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

/// spc_player.h. Mirrored because spc_player.c still owns the object.
pub const Channel = extern struct {
    pattern_order_ptr_for_chan: u16,
    note_ticks_left: u8,
    note_keyoff_ticks_left: u8,
    subroutine_num_loops: u8,
    volume_fade_ticks: u8,
    pan_num_ticks: u8,
    pitch_slide_length: u8,
    pitch_slide_delay_left: u8,
    vibrato_hold_count: u8,
    vib_depth: u8,
    tremolo_hold_count: u8,
    tremolo_depth: u8,
    vibrato_change_count: u8,
    note_length: u8,
    note_gate_off_fixedpt: u8,
    channel_volume_master: u8,
    instrument_id: u8,
    instrument_pitch_base: u16,
    saved_pattern_ptr: u16,
    pattern_start_ptr: u16,
    pitch_envelope_num_ticks: u8,
    pitch_envelope_delay: u8,
    pitch_envelope_direction: u8,
    pitch_envelope_slide_value: u8,
    vibrato_count: u8,
    vibrato_rate: u8,
    vibrato_delay_ticks: u8,
    vibrato_fade_num_ticks: u8,
    vibrato_fade_add_per_tick: u8,
    vibrato_depth_target: u8,
    tremolo_count: u8,
    tremolo_rate: u8,
    tremolo_delay_ticks: u8,
    channel_transposition: u8,
    channel_volume: u16,
    volume_fade_addpertick: u16,
    volume_fade_target: u8,
    final_volume: u8,
    pan_value: u16,
    pan_add_per_tick: u16,
    pan_target_value: u8,
    pan_flag_with_phase_invert: u8,
    pitch: u16,
    pitch_add_per_tick: u16,
    pitch_target: u8,
    fine_tune: u8,
    sfx_sound_ptr: u16,
    sfx_which_sound: u8,
    sfx_arr_countdown: u8,
    sfx_note_length_left: u8,
    sfx_note_length: u8,
    sfx_pan: u8,
    index: u8,
};

pub const SpcPlayer = extern struct {
    reg_write_history: ?*anyopaque,
    timer_cycles: u8,
    dsp: ?*dsp_mod.Dsp,
    new_value_from_snes: [4]u8,
    port_to_snes: [4]u8,
    last_value_from_snes: [4]u8,
    counter_sf0c: u8,
    _always_zero: u16,
    temp_accum: u16,
    ttt: u8,
    did_affect_volumepitch_flag: u8,
    addr0: u16,
    addr1: u16,
    lfsr_value: u16,
    is_chan_on: u8,
    fast_forward: u8,
    sfx_start_arg_pan: u8,
    sfx_sound_ptr_cur: u16,
    music_ptr_toplevel: u16,
    block_count: u8,
    sfx_timer_accum: u8,
    chn: u8,
    key_ON: u8,
    key_OFF: u8,
    cur_chan_bit: u8,
    reg_FLG: u8,
    reg_NON: u8,
    reg_EON: u8,
    reg_PMON: u8,
    echo_stored_time: u8,
    echo_parameter_EDL: u8,
    reg_EFB: u8,
    global_transposition: u8,
    main_tempo_accum: u8,
    tempo: u16,
    tempo_fade_num_ticks: u8,
    tempo_fade_final: u8,
    tempo_fade_add: u16,
    master_volume: u16,
    master_volume_fade_ticks: u8,
    master_volume_fade_target: u8,
    master_volume_fade_add_per_tick: u16,
    vol_dirty: u8,
    percussion_base_id: u8,
    echo_volume_left: u16,
    echo_volume_right: u16,
    echo_volume_fade_add_left: u16,
    echo_volume_fade_add_right: u16,
    echo_volume_fade_ticks: u8,
    echo_volume_fade_target_left: u8,
    echo_volume_fade_target_right: u8,
    sfx_channel_index: u8,
    current_bit: u8,
    dsp_register_index: u8,
    echo_channels: u8,
    byte_3C4: u8,
    byte_3C5: u8,
    echo_fract_incr: u8,
    sfx_channel_index2: u8,
    sfx_channel_bit: u8,
    pause_music_ctr: u8,
    port2_active: u8,
    port2_current_bit: u8,
    port3_active: u8,
    port3_current_bit: u8,
    port1_active: u8,
    port1_current_bit: u8,
    byte_3E1: u8,
    sfx_play_echo_flag: u8,
    sfx_channels_echo_mask2: u8,
    port1_counter: u8,
    channel_67_volume: u8,
    cutk_always_zero: u8,
    last_written_edl: u8,
    input_ports: [4]u8,
    channel: [8]Channel,
    ram: [65536]u8,
};

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
};

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
    37, 37, 42, 38, 38, 38,  38,  39, 37, 37, 42, 38, 38, 38, 38, 41, // lw
    42, 42, 42, 42, 42, 42,  40,  40, 43, 43, 42, 47, 47, 42, 45, 45,
    43, 43, 43, 47, 47, 42,  45,  45, 112, 112, 48, 42, 42, 42, 42, 45,
    44, 44, 48, 48, 48, 46,  46,  46, 44, 44, 44, 48, 48, 46, 46, 46,
    49, 49, 51, 50, 50, 50,  50,  50, 49, 49, 51, 50, 50, 50, 50, 51, // dw
    51, 51, 51, 51, 51, 51,  51,  51, 52, 52, 51, 56, 56, 51, 54, 54,
    52, 52, 52, 56, 56, 51,  54,  54, 58, 52, 57, 51, 51, 51, 51, 54,
    53, 53, 57, 57, 57, 55,  55,  110, 53, 53, 57, 57, 57, 55, 55, 110,
    37, 41, 41, 42, 42, 42,  42,  42, 42, 41, 41, 42, 42, 42, 42, 42, // special
    42, 42, 42, 42, 42, 42,  42,  42, 42, 42, 42, 42, 42, 42, 42, 42,
};

const kMsuDeluxe_Entrance_Songs = [133]u8{
    59, 59, 60,  61,  61,  61,  62, 62, 63, 64, 64,  64,  105, 65,  65,  66,
    66, 62, 67,  62,  62,  68,  62, 62, 68, 68, 62,  62,  62,  62,  62,  62,
    62, 62, 62,  62,  69,  70,  71, 72, 73, 73, 73,  106, 102, 74,  62,  62,
    75, 75, 76,  77,  78,  68,  79, 80, 81, 62, 62,  62,  82,  75,  242, 59,
    59, 76, 242, 242, 242, 96,  83, 99, 59, 242, 242, 242, 84, 95,  104, 62,
    85, 62, 62,  86,  242, 67,  103, 83, 83, 87, 76,  88,  81,  98,  81,  88,
    83, 89, 75,  97,  90,  91,  91, 100, 92, 93, 92,  242, 93,  107, 62,  75,
    62, 67, 62,  242, 242, 242, 73, 73, 73, 73, 102, 114, 81,  76,  62,  67,
    62, 61, 94,  62,  103,
};

const kVolumeTransitionTarget = [4]u8{ 0, 64, 255, 255 };
const kVolumeTransitionStep = [4]u8{ 7, 3, 3, 24 };
// These are precomputed in the config parse
var kVolumeTransitionStepFloat: [4]f32 = @splat(0);
var kVolumeTransitionTargetFloat: [4]f32 = @splat(0);

/// Remap an track number into a potentially different track number (used for msu deluxe)
fn RemapMsuDeluxeTrack(mp: *MsuPlayer, track: u8) u8 {
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
    ZeldaApuLock();
    if ((music_ctrl & 0xf0) != 0xf0) {
        MsuPlayer_Open(mp, music_ctrl, false);
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
    if (mp.state != kMsuState_FinishedPlaying)
        mp.state = kMsuState_Idle;
    mp.resume_info = std.mem.zeroes(MsuPlayerResumeInfo);
}

fn MsuPlayer_Open(mp: *MsuPlayer, orig_track: c_int, resume_from_snapshot: bool) void {
    var resume_info: MsuPlayerResumeInfo = undefined;
    const actual_track = RemapMsuDeluxeTrack(mp, @truncate(@as(c_uint, @bitCast(orig_track))));

    if (!resume_from_snapshot) {
        resume_info.tag = 0;
        // Attempt to resume MSU playback when exiting back to the overworld.
        const alt: *align(1) const MsuPlayerResumeInfo = @ptrCast(vars.msu_resume_info_alt);
        if (vars.main_module_index.* == 9 and actual_track == alt.actual_track and config.g_config.resume_msu) {
            resume_info = alt.*;
        }
        if (mp.state >= kMsuState_Resuming) {
            const alt_dst: *align(1) MsuPlayerResumeInfo = @ptrCast(vars.msu_resume_info_alt);
            alt_dst.* = mp.resume_info;
        }
    } else {
        const snap: *align(1) const MsuPlayerResumeInfo = @ptrCast(vars.msu_resume_info);
        resume_info = snap.*;
    }

    mp.volume_target = kVolumeTransitionTargetFloat[3];
    mp.volume_step = kVolumeTransitionStepFloat[3];

    mp.state = kMsuState_Idle;
    MsuPlayer_CloseFile(mp);
    if (actual_track == 0)
        return;

    var fname: [256]u8 = undefined;
    var buf: [8]u8 = undefined;
    _ = snprintf(
        &fname,
        fname.len,
        "%s%d.%s",
        if (config.g_config.msu_path) |p| p else @as([*:0]const u8, ""),
        @as(c_int, actual_track),
        if (mp.enabled & kMsuEnabled_Opuz != 0) @as([*:0]const u8, "opuz") else @as([*:0]const u8, "pcm"),
    );
    _ = printf("Loading MSU %s\n", &fname);
    mp.f = fopen(@ptrCast(&fname), "rb");
    if (mp.f == null)
        return openReadError(mp, &fname);
    _ = setvbuf(mp.f.?, null, _IOFBF, 16384);
    if (fread(&buf, 1, 8, mp.f.?) != 8)
        return openReadError(mp, &fname);

    const file_tag = std.mem.readInt(u32, buf[0..4], .little);
    mp.repeat_position = std.mem.readInt(u32, buf[4..8], .little);
    mp.state = if (resume_info.actual_track == actual_track and resume_info.tag == file_tag)
        kMsuState_Resuming
    else
        kMsuState_Playing;
    if (mp.state == kMsuState_Resuming) {
        mp.resume_info = resume_info;
    } else {
        mp.resume_info.orig_track = @truncate(@as(c_uint, @bitCast(orig_track)));
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
            return openReadError(mp, &fname);
        if (mp.state == kMsuState_Resuming)
            _ = fseek(mp.f.?, @intCast(mp.cur_file_offs), SEEK_SET);
    } else if (file_tag == kTagMsu1) {
        _ = fseek(mp.f.?, 0, SEEK_END);
        mp.total_samples_in_file = @intCast(@divTrunc(ftell(mp.f.?) - 8, 4));
        mp.samples_until_repeat = mp.total_samples_in_file -% mp.cur_file_offs;
        _ = fseek(mp.f.?, @as(c_long, mp.cur_file_offs) * 4 + 8, SEEK_SET);
    } else {
        return openReadError(mp, &fname);
    }
}

/// The C reaches this through `goto READ_ERROR` into a labelled block.
fn openReadError(mp: *MsuPlayer, fname: *const [256]u8) void {
    std.debug.print("Unable to read MSU file {s}\n", .{std.mem.sliceTo(fname, 0)});
    MsuPlayer_CloseFile(mp);
}

fn MixToBufferWithVolume(dst: [*]i16, src: [*]const i16, n: usize, volume: f32) void {
    if (volume == 1.0) {
        for (0..n) |i| {
            dst[i * 2 + 0] +%= src[i * 2 + 0];
            dst[i * 2 + 1] +%= src[i * 2 + 1];
        }
    } else {
        // The C multiplies a promoted int16 by an unsigned volume, so the whole
        // product is computed in unsigned arithmetic before being truncated back.
        const vol: u32 = @bitCast(@as(i32, @intFromFloat(65536 * volume)));
        for (0..n) |i| {
            dst[i * 2 + 0] +%= scaleSample(src[i * 2 + 0], vol);
            dst[i * 2 + 1] +%= scaleSample(src[i * 2 + 1], vol);
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
        dst[i * 2 + 0] +%= scaleSample(src[i * 2 + 0], v);
        dst[i * 2 + 1] +%= scaleSample(src[i * 2 + 1], v);
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

/// The C reaches these through `goto` into labelled blocks inside the loop.
fn mixFinishedPlaying(mp: *MsuPlayer) void {
    mp.state = kMsuState_FinishedPlaying;
    MsuPlayer_CloseFile(mp);
}

fn mixReadError(mp: *MsuPlayer) void {
    std.debug.print("MSU read/decode error!\n", .{});
    zelda_apu_write(APUI00, mp.resume_info.orig_track);
    MsuPlayer_CloseFile(mp);
}

pub export fn MsuPlayer_Mix(mp: *MsuPlayer, audio_buffer_in: [*]i16, audio_samples_in: c_int) callconv(.c) void {
    var audio_buffer = audio_buffer_in;
    var audio_samples = audio_samples_in;
    var r: c_int = undefined;

    while (true) {
        if (mp.buffer_size -% mp.buffer_pos == 0) {
            if (mp.opus != null) {
                if (mp.samples_until_repeat == 0) {
                    if (mp.range_cur == 0) {
                        mixFinishedPlaying(mp);
                        return;
                    }
                    _ = opus_decoder_ctl(mp.opus.?, OPUS_RESET_STATE);
                    _ = fseek(mp.f.?, mp.range_cur, SEEK_SET);
                    const file_data: [*]u8 = @ptrCast(&mp.buffer);
                    if (fread(file_data, 1, 10, mp.f.?) != 10) {
                        mixReadError(mp);
                        return;
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
                        return;
                    }
                    const header = std.mem.readInt(u16, file_data[0..2], .little);
                    const size: usize = header & 0x7fff;
                    if (size > 1275) {
                        mixReadError(mp);
                        return;
                    }
                    const n: usize = header >> 15;
                    if (fread(file_data + 2, 1, size, mp.f.?) != size) {
                        mixReadError(mp);
                        return;
                    }
                    // Verify if the snapshot matches the file on disk.
                    const initial_file_data = std.mem.readInt(u64, file_data[0..8], .little);
                    if (mp.state == kMsuState_Resuming) {
                        mp.state = kMsuState_Playing;
                        if (mp.resume_info.initial_packet_bytes != initial_file_data) {
                            mixReadError(mp);
                            return;
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
                        return;
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
                        return;
                    }
                    mp.samples_until_repeat = mp.total_samples_in_file -% mp.repeat_position;
                    if (mp.samples_until_repeat == 0) {
                        mixReadError(mp); // impossible to make progress
                        return;
                    }
                    mp.cur_file_offs = mp.repeat_position;
                    _ = fseek(mp.f.?, @as(c_long, mp.cur_file_offs) * 4 + 8, SEEK_SET);
                }
                r = @intCast(@min(@as(u32, 960), mp.samples_until_repeat));
                if (fread(&mp.buffer, 4, @intCast(r), mp.f.?) != @as(usize, @intCast(r))) {
                    mixReadError(mp);
                    return;
                }
                mp.resume_info.offset = mp.cur_file_offs;
                mp.cur_file_offs +%= @intCast(r);
            }
            const n = @min(@as(u32, @intCast(r)) -% mp.preskip, mp.samples_until_repeat);
            mp.samples_until_repeat -= n;
            mp.buffer_pos = mp.preskip;
            mp.buffer_size = mp.buffer_pos + n;
            mp.preskip = 0;
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
    if (g_msu_player.f != null and channels == 2)
        MsuPlayer_Mix(&g_msu_player, audio_buffer, samples);
    ZeldaApuUnlock();
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

/// The output rate the MSU mixer has to run at, or null when MSU is off.
///
/// MsuPlayer_Mix copies decoded frames into the output buffer one for one, with
/// no rate conversion of its own, so the mix only comes out at the right pitch
/// when the buffer it writes into runs at the rate the decoder produces: 48000
/// for Opuz (see the opus_decoder_create call) and 44100 for plain PCM. The SNES
/// DSP has no such constraint — dsp_getSamples resamples its 32kHz output to
/// whatever length it is handed.
///
/// This used to be the user's problem, with a warning telling them to go and set
/// AudioFreq themselves. The caller picks the rate from this instead; SDL3's
/// audio stream converts the finished mix to whatever the device wants, so the
/// rate the mixer needs no longer has to be a rate the hardware supports.
pub fn MsuRequiredAudioFreq(enable: u8) ?u16 {
    if (enable == 0) return null;
    return if (enable & kMsuEnabled_Opuz != 0) 48000 else 44100;
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

test "mixing at full volume is a plain saturating-free add" {
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

test "the msu mixer asks for the rate its decoder produces" {
    // Off means no constraint; the DSP resamples to any rate on its own.
    try testing.expectEqual(@as(?u16, null), MsuRequiredAudioFreq(0));
    // Opuz decodes at 48000, every other MSU flavour is 44100 PCM.
    try testing.expectEqual(@as(?u16, 48000), MsuRequiredAudioFreq(kMsuEnabled_Opuz));
    try testing.expectEqual(@as(?u16, 48000), MsuRequiredAudioFreq(kMsuEnabled_Msu | kMsuEnabled_Opuz));
    try testing.expectEqual(@as(?u16, 44100), MsuRequiredAudioFreq(kMsuEnabled_Msu));
    try testing.expectEqual(@as(?u16, 44100), MsuRequiredAudioFreq(kMsuEnabled_MsuDeluxe));
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
