//! Port of src/spc_player.c: a direct reimplementation of the game's SPC700
//! music/sfx driver, driving the DSP without emulating the SPC cpu.
//!
//! The SpcPlayer/Channel layouts live in audio.zig and the ram memory maps in
//! spc_player_tables.zig.
const std = @import("std");
const audio = @import("audio.zig");
const dsp_mod = @import("../snes/dsp.zig");
const maps = @import("spc_player_tables.zig");

const SpcPlayer = audio.SpcPlayer;
const Channel = audio.Channel;

extern fn malloc(size: usize) ?*anyopaque;

// snes/dsp_regs.h
const V0VOLL: u8 = 0x00;
const V0VOLR: u8 = 0x01;
const V0PITCHL: u8 = 0x02;
const V0PITCHH: u8 = 0x03;
const V0SRCN: u8 = 0x04;
const V0ADSR1: u8 = 0x05;
const V0ADSR2: u8 = 0x06;
const V0GAIN: u8 = 0x07;
const MVOLL: u8 = 0x0C;
const EFB: u8 = 0x0D;
const FIR0: u8 = 0x0F;
const MVOLR: u8 = 0x1C;
const EVOLL: u8 = 0x2C;
const PMON: u8 = 0x2D;
const EVOLR: u8 = 0x3C;
const NON: u8 = 0x3D;
const KON: u8 = 0x4C;
const EON: u8 = 0x4D;
const KOF: u8 = 0x5C;
const DIR: u8 = 0x5D;
const V6VOLL: u8 = 0x60;
const V6VOLR: u8 = 0x61;
const FLG: u8 = 0x6C;
const ESA: u8 = 0x6D;
const V7VOLL: u8 = 0x70;
const V7VOLR: u8 = 0x71;
const EDL: u8 = 0x7D;

/// snes/dsp.h
const DspRegWriteHistory = extern struct {
    count: u32,
    addr: [256]u8,
    val: [256]u8,
};

/// The C shifts an 8-bit mask off the end of the register; Zig's `<<` would
/// rather not lose the bit silently, so make the truncation explicit.
fn shl1(v: u8) u8 {
    return @truncate(@as(u16, v) << 1);
}

fn hiByte(v: u16) u8 {
    return @truncate(v >> 8);
}

fn setHiByte(p: *u16, v: u8) void {
    p.* = (p.* & 0x00ff) | (@as(u16, v) << 8);
}

fn ramWord(p: *SpcPlayer, addr: u16) u16 {
    return std.mem.readInt(u16, p.ram[addr..][0..2], .little);
}

fn sign8(v: u8) bool {
    return v & 0x80 != 0;
}

fn Dsp_Write(p: *SpcPlayer, reg: u8, value: u8) void {
    if (p.reg_write_history) |h| {
        const hist: *DspRegWriteHistory = @ptrCast(@alignCast(h));
        if (hist.count < 256) {
            hist.addr[hist.count] = reg;
            hist.val[hist.count] = value;
            hist.count += 1;
        }
    }
    if (p.dsp) |d|
        dsp_mod.dsp_write(d, reg, value);
}

fn Not_Implemented() void {
    unreachable; // assert(0)
}

fn SpcDivHelper(a_in: i32, b: u8) u16 {
    const org_a = a_in;
    var a = a_in;
    if (a & 0x100 != 0)
        a = -a;
    const q: i32 = if (b != 0) @divTrunc(a & 0xff, b) else 0xff;
    const r: i32 = if (b != 0) @rem(a & 0xff, b) else (a & 0xff);
    const t: i32 = (q << 8) + (if (b != 0) @divTrunc(r << 8, @as(i32, b)) & 0xff else 0xff);
    return @truncate(@as(u32, @bitCast(if (org_a & 0x100 != 0) -t else t)));
}

fn Chan_DoAnyFade(p: *align(1) u16, add: u16, target: u8, cont: bool) void {
    if (!cont) {
        p.* = @as(u16, target) << 8;
    } else {
        p.* +%= add;
    }
}

fn SetupEchoParameter_EDL(p: *SpcPlayer, a_in: u8) void {
    var a = a_in;
    p.echo_parameter_EDL = a;
    if (a != p.last_written_edl) {
        a = (p.last_written_edl & 0xf) ^ 0xff;
        if (p.echo_stored_time & 0x80 != 0)
            a +%= p.echo_stored_time;
        p.echo_stored_time = a;

        Dsp_Write(p, EON, 0);
        Dsp_Write(p, EFB, 0);
        Dsp_Write(p, EVOLR, 0);
        Dsp_Write(p, EVOLL, 0);
        Dsp_Write(p, FLG, p.reg_FLG | 0x20);

        p.last_written_edl = p.echo_parameter_EDL;
        Dsp_Write(p, EDL, p.echo_parameter_EDL);
    }
    Dsp_Write(p, ESA, (p.echo_parameter_EDL *% 8 ^ 0xff) +% 0xd1);
}

const kVolumeTable = [22]u8{
    0, 1, 3, 7, 13, 21, 30, 41, 52, 66, 81, 94, 103, 110, 115, 119, 122, 124, 125, 126, 127, 127,
};

fn WriteVolumeToDsp(p: *SpcPlayer, c: *Channel, volume_in: u16) void {
    if (p.is_chan_on & p.cur_chan_bit != 0)
        return;
    var volume = volume_in;
    for (0..2) |i| {
        const j: usize = volume >> 8;
        var t: u8 = undefined;
        if (j >= 21) {
            const lo = p.ram[j + 0x1178];
            const hi = p.ram[j + 0x1179];
            t = lo +% @as(u8, @truncate((@as(u32, hi -% lo) *% @as(u8, @truncate(volume))) >> 8));
        } else {
            const lo = kVolumeTable[j];
            const hi = kVolumeTable[j + 1];
            t = lo +% @as(u8, @truncate((@as(u32, hi -% lo) *% @as(u8, @truncate(volume))) >> 8));
        }

        t = @truncate((@as(u16, t) *% c.final_volume) >> 8);
        if ((@as(u16, c.pan_flag_with_phase_invert) << @intCast(i)) & 0x80 != 0)
            t = 0 -% t;
        Dsp_Write(p, V0VOLL +% @as(u8, @intCast(i)) +% c.index *% 16, t);
        volume = 0x1400 -% volume;
    }
}

const kBaseNoteFreqs = [13]u16{ 2143, 2270, 2405, 2548, 2700, 2860, 3030, 3211, 3402, 3604, 3818, 4045, 4286 };

fn WritePitch(p: *SpcPlayer, c: *Channel, pitch_in: u16) void {
    var pitch = pitch_in;
    if ((pitch >> 8) >= 0x34) {
        pitch +%= (pitch >> 8) - 0x34;
    } else if ((pitch >> 8) < 0x13) {
        // The C narrows to uint8, then subtracts 256 in int arithmetic, so the
        // adjustment is negative before it wraps into the uint16 pitch.
        const adj: i32 = @as(i32, @as(u8, @truncate(((pitch >> 8) -% 0x13) *% 2))) - 256;
        pitch +%= @truncate(@as(u32, @bitCast(adj)));
    }

    const pp: u8 = @as(u8, @truncate(pitch >> 8)) & 0x7f;
    var q: u8 = pp / 12;
    const r: usize = pp % 12;
    var t: u16 = kBaseNoteFreqs[r] +%
        @as(u16, @truncate((@as(u32, @as(u8, @truncate(kBaseNoteFreqs[r + 1] -% kBaseNoteFreqs[r]))) *
            @as(u8, @truncate(pitch))) >> 8));
    t *%= 2;
    while (q != 6) {
        t >>= 1;
        q +%= 1;
    }

    t = @truncate((@as(u32, c.instrument_pitch_base) *% t) >> 8);
    if (p.cur_chan_bit & p.is_chan_on == 0) {
        const reg = c.index *% 16;
        Dsp_Write(p, reg +% V0PITCHL, @truncate(t & 0xff));
        Dsp_Write(p, reg +% V0PITCHH, @truncate(t >> 8));
    }
}

fn Music_ResetChan(p: *SpcPlayer) void {
    var ci: usize = 7;
    p.cur_chan_bit = 0x80;
    while (true) {
        const c = &p.channel[ci];
        setHiByte(&c.channel_volume, 0xff);
        c.pan_flag_with_phase_invert = 10;
        c.pan_value = 10 << 8;
        c.instrument_id = 0;
        c.fine_tune = 0;
        c.channel_transposition = 0;
        c.pitch_envelope_num_ticks = 0;
        c.vib_depth = 0;
        c.tremolo_depth = 0;
        p.cur_chan_bit >>= 1;
        if (p.cur_chan_bit == 0) break;
        ci -= 1;
    }
    p.master_volume_fade_ticks = 0;
    p.echo_volume_fade_ticks = 0;
    p.tempo_fade_num_ticks = 0;
    p.global_transposition = 0;
    p.block_count = 0;
    p.percussion_base_id = 0;
    setHiByte(&p.master_volume, 0xc0);
    setHiByte(&p.tempo, 0x20);
}

fn Channel_SetInstrument(p: *SpcPlayer, c: *Channel, instrument_in: u8) void {
    var instrument = instrument_in;
    c.instrument_id = instrument;
    if (instrument & 0x80 != 0)
        instrument = instrument +% 54 +% p.percussion_base_id;
    const ip = p.ram[@as(usize, instrument) * 6 + 0x3d00 ..];
    if (p.is_chan_on & p.cur_chan_bit != 0)
        return;
    const reg = c.index *% 16;
    if (ip[0] & 0x80 != 0) {
        // noise
        p.reg_FLG = (p.reg_FLG & 0x20) | (ip[0] & 0x1f);
        p.reg_NON |= p.cur_chan_bit;
        Dsp_Write(p, reg +% V0SRCN, 0);
    } else {
        Dsp_Write(p, reg +% V0SRCN, ip[0]);
    }
    Dsp_Write(p, reg +% V0ADSR1, ip[1]);
    Dsp_Write(p, reg +% V0ADSR2, ip[2]);
    Dsp_Write(p, reg +% V0GAIN, ip[3]);
    c.instrument_pitch_base = @as(u16, ip[4]) << 8 | ip[5];
}

fn ComputePitchAdd(c: *Channel, pitch: u8) void {
    c.pitch_target = pitch & 0x7f;
    c.pitch_add_per_tick = SpcDivHelper(@as(i32, c.pitch_target) - @as(i32, c.pitch >> 8), c.pitch_slide_length);
}

fn PitchSlideToNote_Check(p: *SpcPlayer, c: *Channel) void {
    if (c.pitch_slide_length != 0 or p.ram[c.pattern_order_ptr_for_chan] != 0xf9)
        return;

    if (p.cur_chan_bit & p.is_chan_on != 0) {
        c.pattern_order_ptr_for_chan +%= 4;
        return;
    }
    c.pattern_order_ptr_for_chan +%= 1;
    c.pitch_slide_delay_left = p.ram[c.pattern_order_ptr_for_chan];
    c.pattern_order_ptr_for_chan +%= 1;
    c.pitch_slide_length = p.ram[c.pattern_order_ptr_for_chan];
    c.pattern_order_ptr_for_chan +%= 1;
    const v = p.ram[c.pattern_order_ptr_for_chan] +% p.global_transposition +% c.channel_transposition;
    c.pattern_order_ptr_for_chan +%= 1;
    ComputePitchAdd(c, v);
}

const kEffectByteLength = [27]u8{ 1, 1, 2, 3, 0, 1, 2, 1, 2, 1, 1, 3, 0, 1, 2, 3, 1, 3, 3, 0, 1, 3, 0, 3, 3, 3, 1 };

const kEchoFirParameters = [32]i8{
    127, 0,   0,   0,   0,  0,  0,   0,
    88,  -65, -37, -16, -2, 7,  12,  12,
    12,  33,  43,  43,  19, -2, -13, -7,
    52,  51,  0,   -39, -27, 1, -4,  -21,
};

/// Reads the next byte of the channel's pattern stream.
fn nextByte(p: *SpcPlayer, c: *Channel) u8 {
    const v = p.ram[c.pattern_order_ptr_for_chan];
    c.pattern_order_ptr_for_chan +%= 1;
    return v;
}

fn HandleEffect(p: *SpcPlayer, c: *Channel, effect: u8) void {
    const arg: u8 = if (kEffectByteLength[effect - 0xe0] != 0) nextByte(p, c) else 0;

    switch (effect) {
        0xe0 => Channel_SetInstrument(p, c, arg),
        0xe1 => {
            c.pan_flag_with_phase_invert = arg;
            c.pan_value = @as(u16, arg & 0x1f) << 8;
        },
        0xe2 => {
            c.pan_num_ticks = arg;
            c.pan_target_value = nextByte(p, c);
            c.pan_add_per_tick = SpcDivHelper(@as(i32, c.pan_target_value) - @as(i32, c.pan_value >> 8), arg);
        },
        0xe3 => { // vibrato on
            c.vibrato_delay_ticks = arg;
            c.vibrato_rate = nextByte(p, c);
            c.vib_depth = nextByte(p, c);
            c.vibrato_depth_target = c.vib_depth;
            c.vibrato_fade_num_ticks = 0;
        },
        0xe4 => { // vibrato off
            c.vib_depth = 0;
            c.vibrato_depth_target = 0;
            c.vibrato_fade_num_ticks = 0;
        },
        0xe5 => {
            if (p.pause_music_ctr == 0 and p.byte_3E1 == 0)
                p.master_volume = @as(u16, arg) << 8;
        },
        0xe6 => {
            p.master_volume_fade_ticks = arg;
            p.master_volume_fade_target = nextByte(p, c);
            p.master_volume_fade_add_per_tick =
                SpcDivHelper(@as(i32, p.master_volume_fade_target) - @as(i32, p.master_volume >> 8), arg);
        },
        0xe7 => p.tempo = @as(u16, arg) << 8,
        0xe8 => {
            p.tempo_fade_num_ticks = arg;
            p.tempo_fade_final = nextByte(p, c);
            p.tempo_fade_add = SpcDivHelper(@as(i32, p.tempo_fade_final) - @as(i32, p.tempo >> 8), arg);
        },
        0xe9 => p.global_transposition = arg,
        0xea => c.channel_transposition = arg,
        0xeb => {
            c.tremolo_delay_ticks = arg;
            c.tremolo_rate = nextByte(p, c);
            c.tremolo_depth = nextByte(p, c);
        },
        0xec => c.tremolo_depth = 0,
        0xed => c.channel_volume = @as(u16, arg) << 8,
        0xee => {
            c.volume_fade_ticks = arg;
            c.volume_fade_target = nextByte(p, c);
            c.volume_fade_addpertick =
                SpcDivHelper(@as(i32, c.volume_fade_target) - @as(i32, c.channel_volume >> 8), arg);
        },
        0xef => {
            c.pattern_start_ptr = @as(u16, nextByte(p, c)) << 8 | arg;
            c.subroutine_num_loops = nextByte(p, c);
            c.saved_pattern_ptr = c.pattern_order_ptr_for_chan;
            c.pattern_order_ptr_for_chan = c.pattern_start_ptr;
        },
        0xf0 => {
            c.vibrato_fade_num_ticks = arg;
            c.vibrato_fade_add_per_tick = if (arg != 0) c.vib_depth / arg else 0xff;
        },
        0xf4 => c.fine_tune = arg,
        0xf5 => {
            p.echo_channels = arg;
            p.reg_EON = arg;
            p.echo_volume_left = @as(u16, nextByte(p, c)) << 8;
            p.echo_volume_right = @as(u16, nextByte(p, c)) << 8;
            p.reg_FLG &= ~@as(u8, 0x20);
        },
        0xf6 => { // echo off
            p.echo_volume_left = 0;
            p.echo_volume_right = 0;
            p.reg_FLG |= 0x20;
        },
        0xf7 => {
            SetupEchoParameter_EDL(p, arg);
            p.reg_EFB = nextByte(p, c);
            const base: usize = @as(usize, nextByte(p, c)) * 8;
            for (0..8) |i|
                Dsp_Write(p, FIR0 +% @as(u8, @intCast(i * 16)), @bitCast(kEchoFirParameters[base + i]));
        },
        0xf8 => {
            p.echo_volume_fade_ticks = arg;
            p.echo_volume_fade_target_left = nextByte(p, c);
            p.echo_volume_fade_target_right = nextByte(p, c);
            p.echo_volume_fade_add_left =
                SpcDivHelper(@as(i32, p.echo_volume_fade_target_left) - @as(i32, p.echo_volume_left >> 8), arg);
            p.echo_volume_fade_add_right =
                SpcDivHelper(@as(i32, p.echo_volume_fade_target_right) - @as(i32, p.echo_volume_right >> 8), arg);
        },
        0xf9 => {
            c.pitch_slide_delay_left = arg;
            c.pitch_slide_length = nextByte(p, c);
            const v = nextByte(p, c) +% p.global_transposition +% c.channel_transposition;
            ComputePitchAdd(c, v);
        },
        0xfa => p.percussion_base_id = arg,
        else => Not_Implemented(),
    }
}

fn WantWriteKof(p: *SpcPlayer, c: *Channel) bool {
    var loops: i32 = c.subroutine_num_loops;
    var ptr: u16 = c.pattern_order_ptr_for_chan;

    while (true) {
        var cmd = p.ram[ptr];
        ptr +%= 1;
        if (cmd == 0) {
            if (loops == 0)
                return true;
            loops -= 1;
            ptr = if (loops == 0) c.saved_pattern_ptr else c.pattern_start_ptr;
        } else {
            while (cmd & 0x80 == 0) {
                cmd = p.ram[ptr];
                ptr +%= 1;
            }
            if (cmd == 0xc8)
                return false;
            if (cmd == 0xef) {
                ptr = @as(u16, p.ram[ptr]) | @as(u16, p.ram[ptr +% 1]) << 8;
            } else if (cmd >= 0xe0) {
                ptr +%= kEffectByteLength[cmd - 0xe0];
            } else {
                return true;
            }
        }
    }
}

fn HandleTremolo(p: *SpcPlayer, c: *Channel) void {
    _ = .{ p, c };
    Not_Implemented();
}

fn CalcVibratoAddPitch(p: *SpcPlayer, c: *Channel, pitch: u16, value: u8) void {
    var t: i32 = @as(i32, value) << 2;
    t ^= if (t & 0x100 != 0) 0xff else 0;
    const tb: u8 = @truncate(@as(u32, @bitCast(t)));
    const r: u16 = if (c.vib_depth >= 0xf1)
        @as(u16, tb) *% (c.vib_depth & 0xf)
    else
        @truncate((@as(u32, tb) *% c.vib_depth) >> 8);
    WritePitch(p, c, if (value & 0x80 != 0) pitch -% r else pitch +% r);
}

fn HandlePanAndSweep(p: *SpcPlayer, c: *Channel) void {
    p.did_affect_volumepitch_flag = 0;
    if (c.tremolo_depth != 0) {
        c.tremolo_hold_count = c.tremolo_delay_ticks;
        HandleTremolo(p, c);
    }

    var volume = c.pan_value;

    if (c.pan_num_ticks != 0) {
        p.did_affect_volumepitch_flag = 0x80;
        const add: i32 = @divTrunc(@as(i32, p.main_tempo_accum) * @as(i16, @bitCast(c.pan_add_per_tick)), 256);
        volume +%= @truncate(@as(u32, @bitCast(add)));
    }

    if (p.did_affect_volumepitch_flag != 0)
        WriteVolumeToDsp(p, c, volume);

    p.did_affect_volumepitch_flag = 0;
    var pitch = c.pitch;
    if (c.pitch_slide_length != 0 and c.pitch_slide_delay_left == 0) {
        p.did_affect_volumepitch_flag |= 0x80;
        const add: i32 = @divTrunc(@as(i32, p.main_tempo_accum) * @as(i16, @bitCast(c.pitch_add_per_tick)), 256);
        pitch +%= @truncate(@as(u32, @bitCast(add)));
    }

    if (c.vib_depth != 0 and c.vibrato_delay_ticks == c.vibrato_hold_count) {
        const v: u8 = @truncate(((@as(u32, p.main_tempo_accum) *% c.vibrato_rate) >> 8) +% c.vibrato_count);
        CalcVibratoAddPitch(p, c, pitch, v);
        return;
    }

    if (p.did_affect_volumepitch_flag != 0)
        WritePitch(p, c, pitch);
}

fn HandleNoteTick(p: *SpcPlayer, c: *Channel) void {
    if (c.note_keyoff_ticks_left != 0) {
        c.note_keyoff_ticks_left -%= 1;
        if (c.note_keyoff_ticks_left == 0 or c.note_ticks_left == 2) {
            if (WantWriteKof(p, c) and (p.cur_chan_bit & p.is_chan_on) == 0)
                Dsp_Write(p, KOF, p.cur_chan_bit);
        }
    }

    p.did_affect_volumepitch_flag = 0;
    if (c.pitch_slide_length != 0) {
        if (c.pitch_slide_delay_left != 0) {
            c.pitch_slide_delay_left -%= 1;
        } else if ((p.is_chan_on & p.cur_chan_bit) == 0) {
            p.did_affect_volumepitch_flag = 0x80;
            c.pitch_slide_length -%= 1;
            Chan_DoAnyFade(&c.pitch, c.pitch_add_per_tick, c.pitch_target, c.pitch_slide_length != 0);
        }
    }

    const pitch = c.pitch;

    if (c.vib_depth != 0) {
        if (c.vibrato_delay_ticks == c.vibrato_hold_count) {
            if (c.vibrato_change_count == c.vibrato_fade_num_ticks) {
                c.vib_depth = c.vibrato_depth_target;
            } else {
                const was_zero = c.vibrato_change_count == 0;
                c.vibrato_change_count +%= 1;
                c.vib_depth = (if (was_zero) @as(u8, 0) else c.vib_depth) +% c.vibrato_fade_add_per_tick;
            }
            c.vibrato_count +%= c.vibrato_rate;
            CalcVibratoAddPitch(p, c, pitch, c.vibrato_count);
            return;
        }
        c.vibrato_hold_count +%= 1;
    }

    if (p.did_affect_volumepitch_flag != 0)
        WritePitch(p, c, pitch);
}

pub export fn CalcFinalVolume(p: *SpcPlayer, c: *Channel, vol: u8) callconv(.c) void {
    var t: u32 = ((@as(u32, p.master_volume >> 8) * vol) >> 8);
    t = (t * c.channel_volume_master) >> 8;
    t = (t * (c.channel_volume >> 8)) >> 8;
    c.final_volume = @truncate((t * t) >> 8);
}

pub export fn CalcTremolo(p: *SpcPlayer, c: *Channel) callconv(.c) void {
    _ = .{ p, c };
    Not_Implemented();
}

fn Chan_HandleTick(p: *SpcPlayer, c: *Channel) void {
    if (c.volume_fade_ticks != 0) {
        c.volume_fade_ticks -%= 1;
        p.vol_dirty |= p.cur_chan_bit;
        Chan_DoAnyFade(&c.channel_volume, c.volume_fade_addpertick, c.volume_fade_target, true);
    }
    if (c.tremolo_depth != 0) {
        if (c.tremolo_delay_ticks == c.tremolo_hold_count) {
            p.vol_dirty |= p.cur_chan_bit;
            if (c.tremolo_count & 0x80 != 0 and c.tremolo_depth == 0xff) {
                c.tremolo_count = 0x80;
            } else {
                c.tremolo_count +%= c.tremolo_rate;
            }
            CalcTremolo(p, c);
        } else {
            c.tremolo_hold_count +%= 1;
            CalcFinalVolume(p, c, 0xff);
        }
    } else {
        CalcFinalVolume(p, c, 0xff);
    }

    if (c.pan_num_ticks != 0) {
        c.pan_num_ticks -%= 1;
        p.vol_dirty |= p.cur_chan_bit;
        Chan_DoAnyFade(&c.pan_value, c.pan_add_per_tick, c.pan_target_value, true);
    }

    if (p.vol_dirty & p.cur_chan_bit != 0)
        WriteVolumeToDsp(p, c, c.pan_value);
}

const kNoteVol = [16]u8{ 25, 50, 76, 101, 114, 127, 140, 152, 165, 178, 191, 203, 216, 229, 242, 252 };
const kNoteGateOffPct = [8]u8{ 50, 101, 127, 152, 178, 203, 229, 252 };

fn HandleCmd_PauseMusic(p: *SpcPlayer) void {
    p.key_OFF = p.is_chan_on ^ 0xff;
    p.port_to_snes[0] = 0;
    p.cur_chan_bit = 0;
}

fn Port0_HandleMusic(p: *SpcPlayer) void {
    const a = p.new_value_from_snes[0];

    // The C falls into `handle_cmd_00` from a == 0 and from the 0xf1/f2/f3
    // commands; every other command returns on its own.
    if (a != 0) {
        if (a == 0xff) {
            // Load new music
            Not_Implemented();
            return;
        } else if (a == 0xf1) { // continue music
            p.master_volume_fade_ticks = 0x80;
            p.pause_music_ctr = 0x80;
            p.master_volume_fade_target = 0;
            p.master_volume_fade_add_per_tick = SpcDivHelper(0 - @as(i32, p.master_volume >> 8), 0x80);
        } else if (a == 0xf2) {
            if (p.byte_3E1 != 0)
                return;
            p.byte_3E1 = hiByte(p.master_volume);
            setHiByte(&p.master_volume, 0x70);
        } else if (a == 0xf3) {
            if (p.byte_3E1 == 0)
                return;
            setHiByte(&p.master_volume, p.byte_3E1);
            p.byte_3E1 = 0;
        } else if (a == 0xf0) {
            HandleCmd_PauseMusic(p);
            return;
        } else {
            p.pause_music_ctr = 0;
            p.byte_3E1 = 0;
            p.port_to_snes[0] = a;
            p.music_ptr_toplevel = ramWord(p, 0xD000 +% (@as(u16, a) -% 1) *% 2);
            p.counter_sf0c = 2;
            p.key_OFF |= p.is_chan_on ^ 0xff;
            return;
        }
    }

    // handle_cmd_00:
    if (p.port_to_snes[0] == 0)
        return;
    if (p.pause_music_ctr != 0) {
        p.pause_music_ctr -%= 1;
        if (p.pause_music_ctr == 0) {
            HandleCmd_PauseMusic(p);
            return;
        }
    }
    var at_label_a = false;
    if (p.counter_sf0c == 0) {
        at_label_a = true;
    } else {
        p.counter_sf0c -%= 1;
        if (p.counter_sf0c != 0) {
            Music_ResetChan(p);
            return;
        }
    }

    // `goto next_phrase` from inside the per-channel loop re-enters here.
    phrase: while (true) {
        if (!at_label_a) {
            // next_phrase:
            var t: u16 = undefined;
            while (true) {
                t = ramWord(p, p.music_ptr_toplevel);
                p.music_ptr_toplevel +%= 2;
                if ((t >> 8) != 0)
                    break;
                if (t == 0) {
                    HandleCmd_PauseMusic(p);
                    return;
                }
                if (t == 0x80) {
                    p.fast_forward = 0x80;
                } else if (t == 0x81) {
                    p.fast_forward = 0;
                } else {
                    p.block_count -%= 1;
                    if (sign8(p.block_count))
                        p.block_count = @truncate(t);
                    t = ramWord(p, p.music_ptr_toplevel);
                    p.music_ptr_toplevel +%= 2;
                    if (p.block_count != 0)
                        p.music_ptr_toplevel = t;
                }
            }
            for (0..8) |i| {
                p.channel[i].pattern_order_ptr_for_chan = ramWord(p, t);
                t +%= 2;
            }

            var ci: usize = 0;
            p.cur_chan_bit = 1;
            while (true) {
                const c = &p.channel[ci];
                if (hiByte(c.pattern_order_ptr_for_chan) != 0 and c.instrument_id == 0)
                    Channel_SetInstrument(p, c, 0);
                c.subroutine_num_loops = 0;
                c.volume_fade_ticks = 0;
                c.pan_num_ticks = 0;
                c.note_ticks_left = 1;
                ci += 1;
                p.cur_chan_bit = shl1(p.cur_chan_bit);
                if (p.cur_chan_bit == 0) break;
            }
        }
        at_label_a = false;

        // label_a:
        p.vol_dirty = 0;
        var ci: usize = 0;
        p.cur_chan_bit = 1;
        while (true) {
            const c = &p.channel[ci];
            if (hiByte(c.pattern_order_ptr_for_chan) != 0) {
                c.note_ticks_left -%= 1;
                if (c.note_ticks_left == 0) {
                    while (true) {
                        var cmd = nextByte(p, c);
                        if (cmd == 0) {
                            if (c.subroutine_num_loops == 0)
                                continue :phrase;
                            c.subroutine_num_loops -%= 1;
                            c.pattern_order_ptr_for_chan = if (c.subroutine_num_loops == 0)
                                c.saved_pattern_ptr
                            else
                                c.pattern_start_ptr;
                            continue;
                        }
                        if (cmd & 0x80 == 0) {
                            c.note_length = cmd;
                            cmd = nextByte(p, c);
                            if (cmd & 0x80 == 0) {
                                c.note_gate_off_fixedpt = kNoteGateOffPct[(cmd >> 4) & 7];
                                c.channel_volume_master = kNoteVol[cmd & 0xf];
                                cmd = nextByte(p, c);
                            }
                        }
                        if (cmd >= 0xe0) {
                            HandleEffect(p, c, cmd);
                            continue;
                        }
                        if (p.fast_forward == 0 and (p.is_chan_on & p.cur_chan_bit) == 0)
                            PlayNote(p, c, cmd);
                        c.note_ticks_left = c.note_length;
                        const tt: u16 = (@as(u16, c.note_ticks_left) *% c.note_gate_off_fixedpt) >> 8;
                        c.note_keyoff_ticks_left = if (tt != 0) @truncate(tt) else 1;
                        PitchSlideToNote_Check(p, c);
                        break;
                    }
                } else if (p.fast_forward == 0) {
                    HandleNoteTick(p, c);
                    PitchSlideToNote_Check(p, c);
                }
            }
            ci += 1;
            p.cur_chan_bit = shl1(p.cur_chan_bit);
            if (p.cur_chan_bit == 0) break;
        }
        break;
    }

    if (p.tempo_fade_num_ticks != 0) {
        p.tempo_fade_num_ticks -%= 1;
        p.tempo = if (p.tempo_fade_num_ticks == 0)
            @as(u16, p.tempo_fade_final) << 8
        else
            p.tempo +% p.tempo_fade_add;
    }
    if (p.echo_volume_fade_ticks != 0) {
        p.echo_volume_left +%= p.echo_volume_fade_add_left;
        p.echo_volume_right +%= p.echo_volume_fade_add_right;
        p.echo_volume_fade_ticks -%= 1;
        if (p.echo_volume_fade_ticks == 0) {
            p.echo_volume_left = @as(u16, p.echo_volume_fade_target_left) << 8;
            p.echo_volume_right = @as(u16, p.echo_volume_fade_target_right) << 8;
        }
    }
    if (p.master_volume_fade_ticks != 0) {
        p.master_volume_fade_ticks -%= 1;
        p.master_volume = if (p.master_volume_fade_ticks == 0)
            @as(u16, p.master_volume_fade_target) << 8
        else
            p.master_volume +% p.master_volume_fade_add_per_tick;
        p.vol_dirty = 0xff;
    }
    var ci: usize = 0;
    p.cur_chan_bit = 1;
    while (true) {
        const c = &p.channel[ci];
        if (hiByte(c.pattern_order_ptr_for_chan) != 0)
            Chan_HandleTick(p, c);
        ci += 1;
        p.cur_chan_bit = shl1(p.cur_chan_bit);
        if (p.cur_chan_bit == 0) break;
    }
}

fn Asl(p: *u8) bool {
    const old = p.*;
    p.* = shl1(p.*);
    return old >> 7 != 0;
}

fn Sfx_TurnOffChannel(p: *SpcPlayer, c: *Channel) void {
    c.sfx_which_sound = 0;
    p.is_chan_on &= ~p.current_bit;
    p.port1_active &= ~p.current_bit;
    p.port2_active &= ~p.current_bit;
    p.port3_active &= ~p.current_bit;
    Channel_SetInstrument(p, c, c.instrument_id);
    if (p.echo_channels & p.current_bit != 0 and (p.reg_EON & p.current_bit) == 0) {
        p.reg_EON |= p.current_bit;
        Dsp_Write(p, EON, p.reg_EON);
        p.sfx_channels_echo_mask2 &= ~p.current_bit;
    }
}

fn Write_KeyOn(p: *SpcPlayer, bit: u8) void {
    Dsp_Write(p, KOF, 0);
    Dsp_Write(p, KON, bit);
}

fn PlayNote(p: *SpcPlayer, c: *Channel, note_in: u8) void {
    var note = note_in;
    if (note >= 0xca) {
        Channel_SetInstrument(p, c, note);
        note = 0xa4;
    }

    if (note >= 0xc8 or p.is_chan_on & p.cur_chan_bit != 0)
        return;

    c.pitch = @as(u16, (note & 0x7f) +% p.global_transposition +% c.channel_transposition) << 8 | c.fine_tune;
    c.vibrato_count = shl1(c.vibrato_fade_num_ticks) << 6;
    c.vibrato_hold_count = 0;
    c.vibrato_change_count = 0;
    c.tremolo_count = 0;
    c.tremolo_hold_count = 0;
    p.vol_dirty |= p.cur_chan_bit;
    p.key_ON |= p.cur_chan_bit;
    c.pitch_slide_length = c.pitch_envelope_num_ticks;
    if (c.pitch_slide_length != 0) {
        c.pitch_slide_delay_left = c.pitch_envelope_delay;
        if (c.pitch_envelope_direction == 0)
            c.pitch -%= @as(u16, c.pitch_envelope_slide_value) << 8;
        ComputePitchAdd(c, @as(u8, @truncate(c.pitch >> 8)) +% c.pitch_envelope_slide_value);
    }
    WritePitch(p, c, c.pitch);
}

fn Sfx_MaybeDisableEcho(p: *SpcPlayer) void {
    if ((p.port_to_snes[0] & 0x10) == 0 or p.current_bit & p.sfx_channels_echo_mask2 != 0) {
        if (p.current_bit & p.reg_EON != 0) {
            p.reg_EON ^= p.current_bit;
            Dsp_Write(p, EON, p.reg_EON);
        }
    }
}

fn Sfx_ChannelTick(p: *SpcPlayer, c: *Channel, is_continue: bool) void {
    var cmd: u8 = undefined;

    // The C jumps into the tail of the command loop with `goto note_continue`.
    var go_note_continue = false;

    if (is_continue) {
        Sfx_MaybeDisableEcho(p);
        p.sfx_channel_index = c.index *% 2;
        p.sfx_sound_ptr_cur = c.sfx_sound_ptr;
        c.sfx_note_length_left -%= 1;
        if (c.sfx_note_length_left != 0) {
            go_note_continue = true;
        } else {
            p.sfx_sound_ptr_cur +%= 1;
        }
    }

    if (!go_note_continue) {
        loop: while (true) {
            p.dsp_register_index = p.sfx_channel_index *% 8;

            cmd = p.ram[p.sfx_sound_ptr_cur];
            if (cmd == 0) {
                Sfx_TurnOffChannel(p, c);
                return;
            }

            if (cmd & 0x80 == 0) {
                c.sfx_note_length = cmd;
                p.sfx_sound_ptr_cur +%= 1;
                cmd = p.ram[p.sfx_sound_ptr_cur];
                if (cmd & 0x80 == 0) {
                    if (p.port1_active & p.current_bit != 0) {
                        if (cmd == 0 or p.channel_67_volume == 0) {
                            const volume = cmd;
                            Dsp_Write(p, p.dsp_register_index +% V0VOLL, cmd);
                            p.sfx_sound_ptr_cur +%= 1;
                            cmd = p.ram[p.sfx_sound_ptr_cur];
                            if (cmd & 0x80 != 0) {
                                Dsp_Write(p, p.dsp_register_index +% V0VOLR, volume);
                            } else {
                                Dsp_Write(p, p.dsp_register_index +% V0VOLR, cmd);
                                p.sfx_sound_ptr_cur +%= 1;
                                cmd = p.ram[p.sfx_sound_ptr_cur];
                            }
                        } else {
                            p.sfx_sound_ptr_cur +%= 1;
                            cmd = p.ram[p.sfx_sound_ptr_cur];
                        }
                    } else {
                        c.final_volume = cmd *% 2;
                        c.pan_flag_with_phase_invert = 10;
                        const pan: u16 = if (p.sfx_start_arg_pan & 0x80 != 0)
                            16
                        else if (p.sfx_start_arg_pan & 0x40 != 0)
                            4
                        else
                            10;
                        WriteVolumeToDsp(p, c, pan << 8);
                        p.sfx_sound_ptr_cur +%= 1;
                        cmd = p.ram[p.sfx_sound_ptr_cur];
                    }
                }
            }
            // cmd_parsed
            if (cmd == 0xe0) {
                p.sfx_sound_ptr_cur +%= 1;
                const ip = p.ram[0x3E00 + @as(usize, p.ram[p.sfx_sound_ptr_cur]) * 9 ..];
                const reg = c.index *% 16;
                Dsp_Write(p, reg +% V0VOLL, ip[0]);
                Dsp_Write(p, reg +% V0VOLR, ip[1]);
                Dsp_Write(p, reg +% V0PITCHL, ip[2]);
                Dsp_Write(p, reg +% V0PITCHH, ip[3]);
                Dsp_Write(p, reg +% V0SRCN, ip[4]);
                Dsp_Write(p, reg +% V0ADSR1, ip[5]);
                Dsp_Write(p, reg +% V0ADSR2, ip[6]);
                Dsp_Write(p, reg +% V0GAIN, ip[7]);
                c.instrument_pitch_base = @as(u16, ip[8]) << 8;
                p.sfx_sound_ptr_cur +%= 1;
            } else if (cmd == 0xf9 or cmd == 0xf1) {
                if (cmd == 0xf9) {
                    p.sfx_sound_ptr_cur +%= 1;
                    PlayNote(p, c, p.ram[p.sfx_sound_ptr_cur]);
                    Write_KeyOn(p, p.current_bit);
                }
                p.sfx_sound_ptr_cur +%= 1;
                c.pitch_slide_delay_left = p.ram[p.sfx_sound_ptr_cur];
                p.sfx_sound_ptr_cur +%= 1;
                c.pitch_slide_length = p.ram[p.sfx_sound_ptr_cur];
                p.sfx_sound_ptr_cur +%= 1;
                ComputePitchAdd(c, p.ram[p.sfx_sound_ptr_cur]);
                c.sfx_note_length_left = c.sfx_note_length;
                break :loop;
            } else if (cmd == 0xff) {
                p.sfx_sound_ptr_cur = ramWord(p, 0x17C0 +% (@as(u16, c.sfx_which_sound) -% 1) *% 2);
                c.sfx_sound_ptr = p.sfx_sound_ptr_cur;
            } else {
                PlayNote(p, c, cmd);
                Write_KeyOn(p, p.current_bit);
                c.sfx_note_length_left = c.sfx_note_length;
                break :loop;
            }
        }
    }

    // note_continue:
    p.did_affect_volumepitch_flag = 0;
    if (c.pitch_slide_length != 0) {
        p.did_affect_volumepitch_flag = 0x80;
        c.pitch_slide_length -%= 1;
        Chan_DoAnyFade(&c.pitch, c.pitch_add_per_tick, c.pitch_target, c.pitch_slide_length != 0);
        p.cur_chan_bit = 0; // force change through
        WritePitch(p, c, c.pitch);
    } else if (c.sfx_note_length_left == 2) {
        Dsp_Write(p, KOF, p.current_bit);
    }

    c.sfx_sound_ptr = p.sfx_sound_ptr_cur;
}

fn Port1_Play_Inner(p: *SpcPlayer) void {
    p.port1_counter = 0;
    var ci: usize = 7;
    p.channel[ci].sfx_which_sound = p.new_value_from_snes[1];
    p.channel[ci].sfx_arr_countdown = 3;
    p.channel[ci].pitch_envelope_num_ticks = 0;
    p.port1_active = 0x80;
    p.is_chan_on |= 0x80;
    Dsp_Write(p, KOF, 0x80);
    p.new_value_from_snes[1] = p.ram[0x1800 + @as(usize, p.new_value_from_snes[1]) - 1];
    if (p.new_value_from_snes[1] == 0)
        return;
    ci -= 1;
    p.channel[ci].sfx_which_sound = p.new_value_from_snes[1];
    p.channel[ci].sfx_arr_countdown = 3;
    p.channel[ci].pitch_envelope_num_ticks = 0;
    p.port1_active = 0x40;
    p.is_chan_on |= 0x40;
    Dsp_Write(p, KOF, 0x40);
    p.port1_active = 0xc0;
    p.sfx_channels_echo_mask2 |= 0xc0;
    p.port2_active &= 0x3f;
    p.port3_active &= 0x3f;
}

/// The three sfx ports share this per-channel walk; only the sound table
/// address and the loop's stop condition differ.
fn Sfx_StartNewSound(p: *SpcPlayer, active: u8, cur_bit: *u8, table: u16, stop_at_10: bool) void {
    cur_bit.* = active;
    if (cur_bit.* == 0)
        return;
    var ci: usize = 7;
    p.current_bit = 0x80;
    while (true) {
        if (Asl(cur_bit)) {
            const c = &p.channel[ci];
            p.sfx_channel_index = c.index *% 2;
            p.dsp_register_index = c.index *% 16;
            p.sfx_start_arg_pan = c.sfx_pan;
            if (c.sfx_arr_countdown == 0) {
                if (c.sfx_which_sound != 0)
                    Sfx_ChannelTick(p, c, true);
            } else {
                p.sfx_channel_index = c.index *% 2;
                c.sfx_arr_countdown -%= 1;
                if (c.sfx_arr_countdown == 0) {
                    p.sfx_sound_ptr_cur = ramWord(p, table +% (@as(u16, c.sfx_which_sound) -% 1) *% 2);
                    c.sfx_sound_ptr = p.sfx_sound_ptr_cur;
                    Sfx_ChannelTick(p, c, false);
                }
            }
        }
        if (ci == 0) {
            p.current_bit >>= 1;
            break;
        }
        ci -= 1;
        p.current_bit >>= 1;
        if (stop_at_10) {
            if (p.current_bit == 0x10) break;
        } else {
            if (p.current_bit == 0) break;
        }
    }
}

fn Port1_StartNewSound(p: *SpcPlayer) void {
    if (p.port1_counter != 0) {
        p.port1_counter -%= 1;
        if (p.port1_counter == 0) {
            p.new_value_from_snes[1] = 5;
            Port1_Play_Inner(p);
            p.new_value_from_snes[1] = 0;
            return;
        }
        p.channel_67_volume = p.port1_counter >> 1;
        Dsp_Write(p, V7VOLL, p.channel_67_volume);
        Dsp_Write(p, V7VOLR, p.channel_67_volume);
        Dsp_Write(p, V6VOLL, p.channel_67_volume);
        Dsp_Write(p, V6VOLR, p.channel_67_volume);
    }
    Sfx_StartNewSound(p, p.port1_active, &p.port1_current_bit, 0x17C0, true);
}

fn Port1_HandleCmd(p: *SpcPlayer) void {
    const a = p.new_value_from_snes[1];
    if (a & 0x80 == 0) {
        if (a != 0) {
            p.port_to_snes[1] = a;
            if (a != 5 or p.port1_active != 0)
                Port1_Play_Inner(p);
        }
    } else {
        p.port_to_snes[1] = a;
        if (p.port1_active != 0)
            p.port1_counter = 0x78;
    }
}

fn Port2_StartNewSound(p: *SpcPlayer) void {
    Sfx_StartNewSound(p, p.port2_active, &p.port2_current_bit, 0x1820, false);
}

fn Port3_StartNewSound(p: *SpcPlayer) void {
    Sfx_StartNewSound(p, p.port3_active, &p.port3_current_bit, 0x191C, false);
}

/// Shared by ports 2 and 3; the C duplicates it with a different echo table.
fn Sfx_AllocateChan(p: *SpcPlayer, port: usize, active: u8, echo_table: u16, echo_bias: u16) *Channel {
    p.sfx_play_echo_flag = p.ram[echo_table + (p.new_value_from_snes[port] & 0x3f) - echo_bias];
    var ci: usize = 7;
    p.current_bit = 0x80;
    const found: usize = blk: {
        while (true) {
            const c = &p.channel[ci];
            if (active & p.current_bit != 0 and
                c.sfx_which_sound +% c.sfx_pan == p.new_value_from_snes[port])
                break :blk ci;
            if (ci == 0) break;
            ci -= 1;
            p.current_bit >>= 1;
        }
        ci = 7;
        p.current_bit = 0x80;
        while (true) {
            if ((p.is_chan_on & p.current_bit) == 0)
                break :blk ci;
            if (ci == 0) break;
            ci -= 1;
            p.current_bit >>= 1;
        }
        unreachable; // assert(0)
    };
    const c = &p.channel[found];
    p.sfx_channel_index = c.index *% 2;
    p.sfx_channel_index2 = p.sfx_channel_index;
    p.sfx_channel_bit = p.current_bit;
    p.is_chan_on |= p.current_bit;
    if (p.sfx_play_echo_flag != 0)
        p.sfx_channels_echo_mask2 |= p.current_bit;
    Sfx_MaybeDisableEcho(p);
    return c;
}

fn Port2_HandleCmd(p: *SpcPlayer) void {
    while (p.new_value_from_snes[2] != 0 and p.is_chan_on != 0xff) {
        const c = Sfx_AllocateChan(p, 2, p.port2_active, 0x18dd, 1);
        c.sfx_pan = p.new_value_from_snes[2] & 0xc0;
        c.sfx_which_sound = p.new_value_from_snes[2] & 0x3f;
        c.sfx_arr_countdown = 3;
        c.pitch_envelope_num_ticks = 0;
        p.port2_active |= p.current_bit;
        Dsp_Write(p, KOF, p.current_bit);
        p.new_value_from_snes[2] = p.ram[0x189e + @as(usize, c.sfx_which_sound) - 1];
    }
}

fn Port3_HandleCmd(p: *SpcPlayer) void {
    while (p.new_value_from_snes[3] != 0 and p.is_chan_on != 0xff) {
        const c = Sfx_AllocateChan(p, 3, p.port3_active, 0x19d8, 0);
        c.sfx_pan = p.new_value_from_snes[3] & 0xc0;
        c.sfx_which_sound = p.new_value_from_snes[3] & 0x3f;
        c.sfx_arr_countdown = 3;
        c.pitch_envelope_num_ticks = 0;
        p.port3_active |= p.current_bit;
        Dsp_Write(p, KOF, p.current_bit);
        p.new_value_from_snes[3] = p.ram[0x199a + @as(usize, c.sfx_which_sound) - 1];
    }
}

fn ReadPortFromSnes(p: *SpcPlayer, port: usize) void {
    const old = p.last_value_from_snes[port];
    p.last_value_from_snes[port] = p.input_ports[port];
    if (p.input_ports[port] != old) {
        p.new_value_from_snes[port] = p.input_ports[port];
    } else {
        p.new_value_from_snes[port] = 0;
    }
}

fn Spc_Loop_Part1(p: *SpcPlayer) void {
    Dsp_Write(p, KOF, p.key_OFF);
    Dsp_Write(p, PMON, p.reg_PMON);
    Dsp_Write(p, NON, p.reg_NON);
    Dsp_Write(p, KOF, 0);
    Dsp_Write(p, KON, p.key_ON);
    if (p.echo_stored_time & 0x80 == 0) {
        Dsp_Write(p, FLG, p.reg_FLG);
        if (p.echo_stored_time == p.echo_parameter_EDL) {
            Dsp_Write(p, EON, p.reg_EON);
            Dsp_Write(p, EFB, p.reg_EFB);
            Dsp_Write(p, EVOLR, hiByte(p.echo_volume_right));
            Dsp_Write(p, EVOLL, hiByte(p.echo_volume_left));
        }
    }
    p.key_OFF = 0;
    p.key_ON = 0;
}

fn Spc_Loop_Part2(p: *SpcPlayer, ticks: u8) void {
    var t: u32 = @as(u32, p.sfx_timer_accum) + @as(u8, @truncate(@as(u16, ticks) *% 0x38));
    p.sfx_timer_accum = @truncate(t);
    if (t >= 256) {
        Port1_StartNewSound(p);
        Port1_HandleCmd(p);
        ReadPortFromSnes(p, 1);

        Port2_StartNewSound(p);
        Port2_HandleCmd(p);
        ReadPortFromSnes(p, 2);

        Port3_StartNewSound(p);
        Port3_HandleCmd(p);
        ReadPortFromSnes(p, 3);

        if (p.echo_stored_time != p.echo_parameter_EDL) {
            p.echo_fract_incr +%= 1;
            if (p.echo_fract_incr & 1 == 0)
                p.echo_stored_time +%= 1;
        }
    }

    t = @as(u32, p.main_tempo_accum) + @as(u8, @truncate(@as(u16, ticks) *% hiByte(p.tempo)));
    p.main_tempo_accum = @truncate(t);
    if (t >= 256) {
        Port0_HandleMusic(p);
        ReadPortFromSnes(p, 0);
    } else if (p.port_to_snes[0] != 0) {
        var ci: usize = 0;
        p.cur_chan_bit = 1;
        while (p.cur_chan_bit != 0) {
            const c = &p.channel[ci];
            if (hiByte(c.pattern_order_ptr_for_chan) != 0)
                HandlePanAndSweep(p, c);
            p.cur_chan_bit = shl1(p.cur_chan_bit);
            ci += 1;
        }
    }
}

fn Interrupt_Reset(p: *SpcPlayer) void {
    dsp_mod.dsp_reset(p.dsp.?);

    // Clears everything from new_value_from_snes to the end of the struct,
    // which includes the channels and the whole 64k of spc ram.
    const base = @offsetOf(SpcPlayer, "new_value_from_snes");
    const bytes: [*]u8 = @ptrCast(p);
    @memset(bytes[base..@sizeOf(SpcPlayer)], 0);

    for (0..8) |i|
        p.channel[i].index = @intCast(i);
    SetupEchoParameter_EDL(p, 1);
    p.reg_FLG |= 0x20;
    Dsp_Write(p, MVOLL, 0x60);
    Dsp_Write(p, MVOLR, 0x60);
    Dsp_Write(p, DIR, 0x3c);
    setHiByte(&p.tempo, 16);
    p.timer_cycles = 0;
}

pub export fn SpcPlayer_Create() callconv(.c) *SpcPlayer {
    const p: *SpcPlayer = @ptrCast(@alignCast(malloc(@sizeOf(SpcPlayer)).?));
    p.dsp = dsp_mod.dsp_init(&p.ram);
    p.reg_write_history = null;
    return p;
}

pub export fn SpcPlayer_Initialize(p: *SpcPlayer) callconv(.c) void {
    Interrupt_Reset(p);
    Spc_Loop_Part1(p);
}

pub export fn SpcPlayer_CopyVariablesToRam(p: *SpcPlayer) callconv(.c) void {
    const pbytes: [*]const u8 = @ptrCast(p);
    for (0..8) |i| {
        const cbytes: [*]const u8 = @ptrCast(&p.channel[i]);
        for (maps.kChannel_Maps) |m| {
            const n: usize = if (m.org_off & 0x8000 != 0) 2 else 1;
            const dst: usize = (m.org_off & 0x7fff) + i * 2;
            @memcpy(p.ram[dst..][0..n], cbytes[m.off..][0..n]);
        }
    }
    for (maps.kSpcPlayer_Maps) |m|
        @memcpy(p.ram[m.org_off..][0..m.size], pbytes[m.off..][0..m.size]);
}

pub export fn SpcPlayer_CopyVariablesFromRam(p: *SpcPlayer) callconv(.c) void {
    const pbytes: [*]u8 = @ptrCast(p);
    for (0..8) |i| {
        const cbytes: [*]u8 = @ptrCast(&p.channel[i]);
        for (maps.kChannel_Maps) |m| {
            const n: usize = if (m.org_off & 0x8000 != 0) 2 else 1;
            const src: usize = (m.org_off & 0x7fff) + i * 2;
            @memcpy(cbytes[m.off..][0..n], p.ram[src..][0..n]);
        }
    }
    for (maps.kSpcPlayer_Maps) |m|
        @memcpy(pbytes[m.off..][0..m.size], p.ram[m.org_off..][0..m.size]);
}

pub export fn SpcPlayer_GenerateSamples(p: *SpcPlayer) callconv(.c) void {
    std.debug.assert(p.timer_cycles <= 64);
    const dsp = p.dsp.?;
    std.debug.assert(dsp.sampleOffset <= 534);

    while (true) {
        if (p.timer_cycles >= 64) {
            Spc_Loop_Part2(p, p.timer_cycles >> 6);
            Spc_Loop_Part1(p);
            p.timer_cycles &= 63;
        }

        // sample rate 32000
        var n: i32 = 534 - @as(i32, dsp.sampleOffset);
        if (n > (64 - @as(i32, p.timer_cycles)))
            n = 64 - @as(i32, p.timer_cycles);

        p.timer_cycles +%= @truncate(@as(u32, @bitCast(n)));

        var i: i32 = 0;
        while (i < n) : (i += 1)
            dsp_mod.dsp_cycle(dsp);

        if (dsp.sampleOffset == 534)
            break;
    }
}

pub export fn SpcPlayer_Upload(p: *SpcPlayer, data_in: [*]const u8) callconv(.c) void {
    Dsp_Write(p, EVOLL, 0);
    Dsp_Write(p, EVOLR, 0);
    Dsp_Write(p, KOF, 0xff);

    var data = data_in;
    while (true) {
        // The asset stream is packed, so these words are deliberately unaligned.
        var numbytes = std.mem.readInt(u16, data[0..2], .little);
        if (numbytes == 0)
            break;
        var target = std.mem.readInt(u16, data[2..4], .little);
        data += 4;
        while (true) {
            p.ram[target] = data[0];
            target +%= 1;
            data += 1;
            numbytes -%= 1;
            if (numbytes == 0) break;
        }
    }
    p.pause_music_ctr = 0;
    p.port_to_snes[0] = 0;
    p.port1_active = 0;
    p.port2_active = 0;
    p.port3_active = 0;
    p.is_chan_on = 0;
    p.input_ports[0] = 0;
    p.input_ports[1] = 0;
    p.input_ports[2] = 0;
    p.input_ports[3] = 0;
}

const testing = std.testing;

test "the memory maps cover every field the C listed" {
    try testing.expectEqual(52, maps.kChannel_Maps.len);
    try testing.expectEqual(70, maps.kSpcPlayer_Maps.len);
    // The 0x8000 bit marks a two-byte field.
    try testing.expectEqual(0x8030, maps.kChannel_Maps[0].org_off);
    try testing.expect(maps.kChannel_Maps[0].org_off & 0x8000 != 0);
    try testing.expectEqual(0x70, maps.kChannel_Maps[1].org_off);
    try testing.expect(maps.kChannel_Maps[1].org_off & 0x8000 == 0);
    // Every channel offset lands inside a Channel and every player offset
    // inside an SpcPlayer.
    for (maps.kChannel_Maps) |m|
        try testing.expect(m.off < @sizeOf(Channel));
    for (maps.kSpcPlayer_Maps) |m|
        try testing.expect(m.off + m.size <= @sizeOf(SpcPlayer));
}

test "the spc divide helper matches the C's fixed point form" {
    // A plain division: 0x40 / 2 == 0x20, shifted into the high byte.
    try testing.expectEqual(@as(u16, 0x2000), SpcDivHelper(0x40, 2));
    // A zero divisor yields the 0xffff saturation the C spells out.
    try testing.expectEqual(@as(u16, 0xffff), SpcDivHelper(0x10, 0));
    // Bit 8 marks the input negative, but the sign flip happens before the low
    // byte is masked off, so this is NOT simply the negation of the positive
    // case: -0x140 & 0xff is 0xc0, so the quotient is 0xc0/4 == 0x30 and only
    // then gets negated.
    try testing.expectEqual(@as(u16, 0x1000), SpcDivHelper(0x40, 4));
    try testing.expectEqual(@as(u16, 0xd000), SpcDivHelper(0x140, 4));
    // The remainder lands in the low byte: 3/2 == 1.5.
    try testing.expectEqual(@as(u16, 0x0180), SpcDivHelper(3, 2));
}

test "fades either jump to the target or accumulate" {
    var v: u16 = 0x1000;
    // cont == false snaps to target << 8.
    Chan_DoAnyFade(&v, 0x100, 0x20, false);
    try testing.expectEqual(@as(u16, 0x2000), v);
    // cont == true just adds, and wraps like the C's uint16.
    Chan_DoAnyFade(&v, 0x100, 0x20, true);
    try testing.expectEqual(@as(u16, 0x2100), v);
    v = 0xffff;
    Chan_DoAnyFade(&v, 2, 0, true);
    try testing.expectEqual(@as(u16, 1), v);
}

test "the effect length table drives the argument reader" {
    try testing.expectEqual(27, kEffectByteLength.len);
    // 0xe4 (vibrato off) and 0xec (tremolo off) take no argument byte.
    try testing.expectEqual(@as(u8, 0), kEffectByteLength[0xe4 - 0xe0]);
    try testing.expectEqual(@as(u8, 0), kEffectByteLength[0xec - 0xe0]);
    // 0xe0 (set instrument) takes one.
    try testing.expectEqual(@as(u8, 1), kEffectByteLength[0xe0 - 0xe0]);
    // 0xe2 (pan sweep) takes two.
    try testing.expectEqual(@as(u8, 2), kEffectByteLength[0xe2 - 0xe0]);
}

test "the note tables are the sizes the driver indexes" {
    try testing.expectEqual(22, kVolumeTable.len);
    try testing.expectEqual(13, kBaseNoteFreqs.len);
    try testing.expectEqual(16, kNoteVol.len);
    try testing.expectEqual(8, kNoteGateOffPct.len);
    try testing.expectEqual(32, kEchoFirParameters.len);
    // WritePitch reads r and r+1, so the table needs the extra entry.
    try testing.expectEqual(@as(u16, 2143), kBaseNoteFreqs[0]);
    try testing.expectEqual(@as(u16, 4286), kBaseNoteFreqs[12]);
    // Volume ramps monotonically and saturates at 127.
    try testing.expectEqual(@as(u8, 127), kVolumeTable[21]);
    for (1..22) |i|
        try testing.expect(kVolumeTable[i] >= kVolumeTable[i - 1]);
}

test "the channel mask walks all eight voices and stops" {
    var bit: u8 = 1;
    var n: usize = 0;
    while (bit != 0) {
        n += 1;
        bit = shl1(bit);
    }
    try testing.expectEqual(8, n);
    // shl1 drops the top bit rather than trapping.
    try testing.expectEqual(@as(u8, 0), shl1(0x80));
    try testing.expectEqual(@as(u8, 2), shl1(1));
}

test "Asl reports the bit it shifted out" {
    var v: u8 = 0x80;
    try testing.expect(Asl(&v));
    try testing.expectEqual(@as(u8, 0), v);
    v = 0x40;
    try testing.expect(!Asl(&v));
    try testing.expectEqual(@as(u8, 0x80), v);
}

test "the high byte helpers address the packed fixed point fields" {
    var v: u16 = 0x1234;
    try testing.expectEqual(@as(u8, 0x12), hiByte(v));
    setHiByte(&v, 0xab);
    try testing.expectEqual(@as(u16, 0xab34), v);
    // The low byte is preserved.
    try testing.expectEqual(@as(u8, 0x34), @as(u8, @truncate(v)));
}
