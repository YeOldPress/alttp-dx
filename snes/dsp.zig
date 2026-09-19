//! Port of snes/dsp.c: the S-DSP's eight voices, envelopes, echo and mixing.
//!
//! The arithmetic here is deliberately literal. The C code leans on `int`
//! (32-bit) intermediates with truncating assignments back into narrow fields,
//! and the exact points where it clips to 16 or 15 bits are audible, so those
//! steps are spelled out rather than tidied up.
const std = @import("std");
const snes_types = @import("snes_types.zig");

const SaveLoadFunc = snes_types.SaveLoadFunc;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

/// The C file sets MY_CHANGES to 1, which moves key on/off handling out of the
/// per-cycle path and into the KON/KOF register writes.
const my_changes = true;

// dsp_regs.h
const MVOLL = 0x0c;
const MVOLR = 0x1c;
const EVOLL = 0x2c;
const EVOLR = 0x3c;
const KON = 0x4c;
const KOF = 0x5c;
const FLG = 0x6c;
const ENDX = 0x7c;
const EFB = 0x0d;
const PMON = 0x2d;
const NON = 0x3d;
const EON = 0x4d;
const DIR = 0x5d;
const ESA = 0x6d;
const EDL = 0x7d;

const rateValues = [32]i32{
    0,  2048, 1536, 1280, 1024, 768, 640, 512,
    384, 320, 256,  192,  160,  128, 96,  80,
    64,  48,  40,   32,   24,   20,  16,  12,
    10,  8,   6,    5,    4,    3,   2,   1,
};

const gaussValues = [512]i32{
    0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000,
    0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x002, 0x002, 0x002, 0x002, 0x002,
    0x002, 0x002, 0x003, 0x003, 0x003, 0x003, 0x003, 0x004, 0x004, 0x004, 0x004, 0x004, 0x005, 0x005, 0x005, 0x005,
    0x006, 0x006, 0x006, 0x006, 0x007, 0x007, 0x007, 0x008, 0x008, 0x008, 0x009, 0x009, 0x009, 0x00A, 0x00A, 0x00A,
    0x00B, 0x00B, 0x00B, 0x00C, 0x00C, 0x00D, 0x00D, 0x00E, 0x00E, 0x00F, 0x00F, 0x00F, 0x010, 0x010, 0x011, 0x011,
    0x012, 0x013, 0x013, 0x014, 0x014, 0x015, 0x015, 0x016, 0x017, 0x017, 0x018, 0x018, 0x019, 0x01A, 0x01B, 0x01B,
    0x01C, 0x01D, 0x01D, 0x01E, 0x01F, 0x020, 0x020, 0x021, 0x022, 0x023, 0x024, 0x024, 0x025, 0x026, 0x027, 0x028,
    0x029, 0x02A, 0x02B, 0x02C, 0x02D, 0x02E, 0x02F, 0x030, 0x031, 0x032, 0x033, 0x034, 0x035, 0x036, 0x037, 0x038,
    0x03A, 0x03B, 0x03C, 0x03D, 0x03E, 0x040, 0x041, 0x042, 0x043, 0x045, 0x046, 0x047, 0x049, 0x04A, 0x04C, 0x04D,
    0x04E, 0x050, 0x051, 0x053, 0x054, 0x056, 0x057, 0x059, 0x05A, 0x05C, 0x05E, 0x05F, 0x061, 0x063, 0x064, 0x066,
    0x068, 0x06A, 0x06B, 0x06D, 0x06F, 0x071, 0x073, 0x075, 0x076, 0x078, 0x07A, 0x07C, 0x07E, 0x080, 0x082, 0x084,
    0x086, 0x089, 0x08B, 0x08D, 0x08F, 0x091, 0x093, 0x096, 0x098, 0x09A, 0x09C, 0x09F, 0x0A1, 0x0A3, 0x0A6, 0x0A8,
    0x0AB, 0x0AD, 0x0AF, 0x0B2, 0x0B4, 0x0B7, 0x0BA, 0x0BC, 0x0BF, 0x0C1, 0x0C4, 0x0C7, 0x0C9, 0x0CC, 0x0CF, 0x0D2,
    0x0D4, 0x0D7, 0x0DA, 0x0DD, 0x0E0, 0x0E3, 0x0E6, 0x0E9, 0x0EC, 0x0EF, 0x0F2, 0x0F5, 0x0F8, 0x0FB, 0x0FE, 0x101,
    0x104, 0x107, 0x10B, 0x10E, 0x111, 0x114, 0x118, 0x11B, 0x11E, 0x122, 0x125, 0x129, 0x12C, 0x130, 0x133, 0x137,
    0x13A, 0x13E, 0x141, 0x145, 0x148, 0x14C, 0x150, 0x153, 0x157, 0x15B, 0x15F, 0x162, 0x166, 0x16A, 0x16E, 0x172,
    0x176, 0x17A, 0x17D, 0x181, 0x185, 0x189, 0x18D, 0x191, 0x195, 0x19A, 0x19E, 0x1A2, 0x1A6, 0x1AA, 0x1AE, 0x1B2,
    0x1B7, 0x1BB, 0x1BF, 0x1C3, 0x1C8, 0x1CC, 0x1D0, 0x1D5, 0x1D9, 0x1DD, 0x1E2, 0x1E6, 0x1EB, 0x1EF, 0x1F3, 0x1F8,
    0x1FC, 0x201, 0x205, 0x20A, 0x20F, 0x213, 0x218, 0x21C, 0x221, 0x226, 0x22A, 0x22F, 0x233, 0x238, 0x23D, 0x241,
    0x246, 0x24B, 0x250, 0x254, 0x259, 0x25E, 0x263, 0x267, 0x26C, 0x271, 0x276, 0x27B, 0x280, 0x284, 0x289, 0x28E,
    0x293, 0x298, 0x29D, 0x2A2, 0x2A6, 0x2AB, 0x2B0, 0x2B5, 0x2BA, 0x2BF, 0x2C4, 0x2C9, 0x2CE, 0x2D3, 0x2D8, 0x2DC,
    0x2E1, 0x2E6, 0x2EB, 0x2F0, 0x2F5, 0x2FA, 0x2FF, 0x304, 0x309, 0x30E, 0x313, 0x318, 0x31D, 0x322, 0x326, 0x32B,
    0x330, 0x335, 0x33A, 0x33F, 0x344, 0x349, 0x34E, 0x353, 0x357, 0x35C, 0x361, 0x366, 0x36B, 0x370, 0x374, 0x379,
    0x37E, 0x383, 0x388, 0x38C, 0x391, 0x396, 0x39B, 0x39F, 0x3A4, 0x3A9, 0x3AD, 0x3B2, 0x3B7, 0x3BB, 0x3C0, 0x3C5,
    0x3C9, 0x3CE, 0x3D2, 0x3D7, 0x3DC, 0x3E0, 0x3E5, 0x3E9, 0x3ED, 0x3F2, 0x3F6, 0x3FB, 0x3FF, 0x403, 0x408, 0x40C,
    0x410, 0x415, 0x419, 0x41D, 0x421, 0x425, 0x42A, 0x42E, 0x432, 0x436, 0x43A, 0x43E, 0x442, 0x446, 0x44A, 0x44E,
    0x452, 0x455, 0x459, 0x45D, 0x461, 0x465, 0x468, 0x46C, 0x470, 0x473, 0x477, 0x47A, 0x47E, 0x481, 0x485, 0x488,
    0x48C, 0x48F, 0x492, 0x496, 0x499, 0x49C, 0x49F, 0x4A2, 0x4A6, 0x4A9, 0x4AC, 0x4AF, 0x4B2, 0x4B5, 0x4B7, 0x4BA,
    0x4BD, 0x4C0, 0x4C3, 0x4C5, 0x4C8, 0x4CB, 0x4CD, 0x4D0, 0x4D2, 0x4D5, 0x4D7, 0x4D9, 0x4DC, 0x4DE, 0x4E0, 0x4E3,
    0x4E5, 0x4E7, 0x4E9, 0x4EB, 0x4ED, 0x4EF, 0x4F1, 0x4F3, 0x4F5, 0x4F6, 0x4F8, 0x4FA, 0x4FB, 0x4FD, 0x4FF, 0x500,
    0x502, 0x503, 0x504, 0x506, 0x507, 0x508, 0x50A, 0x50B, 0x50C, 0x50D, 0x50E, 0x50F, 0x510, 0x511, 0x511, 0x512,
    0x513, 0x514, 0x514, 0x515, 0x516, 0x516, 0x517, 0x517, 0x517, 0x518, 0x518, 0x518, 0x518, 0x518, 0x519, 0x519,
};

/// Must match `struct DspChannel` in dsp.h.
pub const DspChannel = extern struct {
    // pitch
    pitch: u16,
    pitchCounter: u16,
    pitchModulation: bool,
    // brr decoding
    decodeBuffer: [19]i16, // 16 samples per brr-block, +3 for interpolation
    srcn: u8,
    decodeOffset: u16,
    previousFlags: u8, // from last sample
    old: i16,
    older: i16,
    useNoise: bool,
    // adsr, envelope, gain
    adsrRates: [4]u16, // attack, decay, sustain, gain
    rateCounter: u16,
    adsrState: u8, // 0: attack, 1: decay, 2: sustain, 3: gain, 4: release
    sustainLevel: u16,
    useGain: bool,
    gainMode: u8,
    directGain: bool,
    gainValue: u16, // for direct gain
    gain: u16,
    // keyon/off
    keyOn: bool,
    keyOff: bool,
    // output
    sampleOut: i16, // final sample, to be multiplied by channel volume
    volumeL: i8,
    volumeR: i8,
    echoEnable: bool,
};

/// Must match `struct Dsp` in dsp.h.
pub const Dsp = extern struct {
    apu_ram: ?[*]u8,
    // mirror ram
    ram: [0x80]u8,
    // 8 channels
    channel: [8]DspChannel,
    // overarching
    dirPage: u16,
    evenCycle: bool,
    mute: bool,
    reset: bool,
    masterVolumeL: i8,
    masterVolumeR: i8,
    // noise
    noiseSample: i16,
    noiseRate: u16,
    noiseCounter: u16,
    // echo
    echoWrites: bool,
    echoVolumeL: i8,
    echoVolumeR: i8,
    feedbackVolume: i8,
    echoBufferAdr: u16,
    echoDelay: u16,
    echoRemain: u16,
    echoBufferIndex: u16,
    firBufferIndex: u8,
    firValues: [8]i8,
    firBufferL: [8]i16,
    firBufferR: [8]i16,
    // sample buffer (1 frame at 32040 Hz: 534 samples, *2 for stereo)
    sampleBuffer: [534 * 2]i16,
    sampleOffset: u16, // current offset in samplebuffer
};

fn clamp16(v: i32) i32 {
    return if (v < -0x8000) -0x8000 else if (v > 0x7fff) 0x7fff else v;
}

/// `(int16_t)(v & 0xffff)`: keep the low 16 bits and read them back as signed.
fn clip16(v: i32) i32 {
    return @as(i16, @bitCast(@as(u16, @truncate(@as(u32, @bitCast(v))))));
}

/// `((int16_t)((v & 0x7fff) << 1)) >> 1`: sign-extend from bit 14.
fn clip15(v: i32) i32 {
    const low: u16 = @truncate(@as(u32, @bitCast(v)) & 0x7fff);
    const shifted: i16 = @bitCast(low << 1);
    return @as(i32, shifted) >> 1;
}

fn toU16(v: i32) u16 {
    return @truncate(@as(u32, @bitCast(v)));
}

fn toI16(v: i32) i16 {
    return @bitCast(toU16(v));
}

pub export fn dsp_init(apu_ram: [*]u8) callconv(.c) *Dsp {
    const dsp: *Dsp = @ptrCast(@alignCast(malloc(@sizeOf(Dsp)).?));
    dsp.apu_ram = apu_ram;
    return dsp;
}

pub export fn dsp_free(dsp: *Dsp) callconv(.c) void {
    free(dsp);
}

pub export fn dsp_reset(dsp: *Dsp) callconv(.c) void {
    @memset(&dsp.ram, 0);
    dsp.ram[ENDX] = 0xff; // set ENDX bit for all channels
    for (&dsp.channel) |*ch| {
        ch.pitch = 0;
        ch.pitchCounter = 0;
        ch.pitchModulation = false;
        @memset(&ch.decodeBuffer, 0);
        ch.srcn = 0;
        ch.decodeOffset = 0;
        ch.previousFlags = 0;
        ch.old = 0;
        ch.older = 0;
        ch.useNoise = false;
        @memset(&ch.adsrRates, 0);
        ch.rateCounter = 0;
        ch.adsrState = 0;
        ch.sustainLevel = 0;
        ch.useGain = false;
        ch.gainMode = 0;
        ch.directGain = false;
        ch.gainValue = 0;
        ch.gain = 0;
        ch.keyOn = false;
        ch.keyOff = false;
        ch.sampleOut = 0;
        ch.volumeL = 0;
        ch.volumeR = 0;
        ch.echoEnable = false;
    }
    dsp.dirPage = 0;
    dsp.evenCycle = false;
    dsp.mute = true;
    dsp.reset = true;
    dsp.masterVolumeL = 0;
    dsp.masterVolumeR = 0;
    dsp.noiseSample = -0x4000;
    dsp.noiseRate = 0;
    dsp.noiseCounter = 0;
    dsp.echoWrites = false;
    dsp.echoVolumeL = 0;
    dsp.echoVolumeR = 0;
    dsp.feedbackVolume = 0;
    dsp.echoBufferAdr = 0;
    dsp.echoDelay = 1;
    dsp.echoRemain = 1;
    dsp.echoBufferIndex = 0;
    dsp.firBufferIndex = 0;
    @memset(&dsp.firValues, 0);
    @memset(&dsp.firBufferL, 0);
    @memset(&dsp.firBufferR, 0);
    @memset(&dsp.sampleBuffer, 0);
    dsp.sampleOffset = 0;
}

pub export fn dsp_saveload(dsp: *Dsp, func: *const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    func(ctx, &dsp.ram, @sizeOf(Dsp) - @offsetOf(Dsp, "ram"));
}

pub export fn dsp_cycle(dsp: *Dsp) callconv(.c) void {
    var totalL: i32 = 0;
    var totalR: i32 = 0;
    for (0..8) |i| {
        dsp_cycleChannel(dsp, i);
        const ch = &dsp.channel[i];
        totalL += (@as(i32, ch.sampleOut) * ch.volumeL) >> 6;
        totalR += (@as(i32, ch.sampleOut) * ch.volumeR) >> 6;
        totalL = clamp16(totalL);
        totalR = clamp16(totalR);
    }
    totalL = clamp16((totalL * dsp.masterVolumeL) >> 7);
    totalR = clamp16((totalR * dsp.masterVolumeR) >> 7);
    dsp_handleEcho(dsp, &totalL, &totalR);
    if (dsp.mute) {
        totalL = 0;
        totalR = 0;
    }
    dsp_handleNoise(dsp);
    // put it in the samplebuffer, if space
    if (dsp.sampleOffset < 534) {
        dsp.sampleBuffer[dsp.sampleOffset * 2] = toI16(totalL);
        dsp.sampleBuffer[dsp.sampleOffset * 2 + 1] = toI16(totalR);
        dsp.sampleOffset += 1;
    }
    dsp.evenCycle = !dsp.evenCycle;
}

fn dsp_handleEcho(dsp: *Dsp, outputL: *i32, outputR: *i32) void {
    const ram = dsp.apu_ram.?;
    // get value out of ram
    const adr = toU16(@as(i32, dsp.echoBufferAdr) + @as(i32, dsp.echoBufferIndex) * 4);
    const fbi = dsp.firBufferIndex;
    dsp.firBufferL[fbi] = toI16(@as(i32, ram[adr]) + (@as(i32, ram[adr +% 1]) << 8));
    dsp.firBufferL[fbi] >>= 1;
    dsp.firBufferR[fbi] = toI16(@as(i32, ram[adr +% 2]) + (@as(i32, ram[adr +% 3]) << 8));
    dsp.firBufferR[fbi] >>= 1;
    // calculate FIR-sum
    var sumL: i32 = 0;
    var sumR: i32 = 0;
    for (0..8) |i| {
        const idx = (@as(usize, fbi) + i + 1) & 0x7;
        sumL += (@as(i32, dsp.firBufferL[idx]) * dsp.firValues[i]) >> 6;
        sumR += (@as(i32, dsp.firBufferR[idx]) * dsp.firValues[i]) >> 6;
        if (i == 6) {
            // clip to 16-bit before last addition
            sumL = clip16(sumL);
            sumR = clip16(sumR);
        }
    }
    sumL = clamp16(sumL);
    sumR = clamp16(sumR);
    // modify output with sum
    outputL.* = clamp16(outputL.* + ((sumL * dsp.echoVolumeL) >> 7));
    outputR.* = clamp16(outputR.* + ((sumR * dsp.echoVolumeR) >> 7));
    // get echo input
    var inL: i32 = 0;
    var inR: i32 = 0;
    for (dsp.channel) |ch| {
        if (ch.echoEnable) {
            inL = clamp16(inL + ((@as(i32, ch.sampleOut) * ch.volumeL) >> 6));
            inR = clamp16(inR + ((@as(i32, ch.sampleOut) * ch.volumeR) >> 6));
        }
    }
    // write this to ram
    inL = clamp16(inL + ((sumL * dsp.feedbackVolume) >> 7));
    inR = clamp16(inR + ((sumR * dsp.feedbackVolume) >> 7));
    // The mask drops the sign bits along with bit 0, exactly as the C does.
    const outL: u32 = @as(u32, @bitCast(inL)) & 0xfffe;
    const outR: u32 = @as(u32, @bitCast(inR)) & 0xfffe;
    if (dsp.echoWrites) {
        ram[adr] = @truncate(outL);
        ram[adr +% 1] = @truncate(outL >> 8);
        ram[adr +% 2] = @truncate(outR);
        ram[adr +% 3] = @truncate(outR >> 8);
    }
    // handle indexes
    dsp.firBufferIndex +%= 1;
    dsp.firBufferIndex &= 7;
    dsp.echoBufferIndex +%= 1;
    dsp.echoRemain -%= 1;
    if (dsp.echoRemain == 0) {
        dsp.echoRemain = dsp.echoDelay;
        dsp.echoBufferIndex = 0;
    }
}

fn dsp_cycleChannel(dsp: *Dsp, ch_i: usize) void {
    const ch = &dsp.channel[ch_i];
    // handle pitch counter
    var pitch = ch.pitch;
    if (ch_i > 0 and ch.pitchModulation) {
        const factor = (@as(i32, dsp.channel[ch_i - 1].sampleOut) >> 4) + 0x400;
        pitch = toU16((@as(i32, pitch) * factor) >> 10);
        if (pitch > 0x3fff) pitch = 0x3fff;
    }
    const newCounter = @as(i32, ch.pitchCounter) + pitch;
    if (newCounter > 0xffff) {
        // next sample
        dsp_decodeBrr(dsp, ch_i);
    }
    ch.pitchCounter = toU16(newCounter);
    var sample: i32 = if (ch.useNoise)
        dsp.noiseSample
    else
        dsp_getSample(dsp, ch_i, ch.pitchCounter >> 12, (ch.pitchCounter >> 4) & 0xff);

    // With MY_CHANGES the key on/off edges are handled in dsp_write instead of
    // here on every other cycle.
    comptime std.debug.assert(my_changes);

    // handle reset
    if (dsp.reset) {
        ch.adsrState = 4;
        ch.gain = 0;
    }
    // handle envelope/adsr
    const doingDirectGain = ch.adsrState != 4 and ch.useGain and ch.directGain;
    const rate: u16 = if (ch.adsrState == 4) 0 else ch.adsrRates[ch.adsrState];
    if (ch.adsrState != 4 and !doingDirectGain and rate != 0) {
        ch.rateCounter +%= 1;
    }
    if (ch.adsrState == 4 or (!doingDirectGain and ch.rateCounter >= rate and rate != 0)) {
        if (ch.adsrState != 4) ch.rateCounter = 0;
        dsp_handleGain(dsp, ch_i);
    }
    if (doingDirectGain) ch.gain = ch.gainValue;
    // set outputs
    dsp.ram[(ch_i << 4) | 8] = @truncate(ch.gain >> 4);
    sample = toI16((sample * ch.gain) >> 11);
    dsp.ram[(ch_i << 4) | 9] = @truncate(@as(u32, @bitCast(sample >> 7)));
    ch.sampleOut = toI16(sample);
}

/// `gain -= ((gain - 1) >> 8) + 1` with C's int intermediates.
fn expDecay(gain: u16) u16 {
    const g: i32 = gain;
    return toU16(g - (((g - 1) >> 8) + 1));
}

fn dsp_handleGain(dsp: *Dsp, ch_i: usize) void {
    const ch = &dsp.channel[ch_i];
    switch (ch.adsrState) {
        0 => { // attack
            const rate = ch.adsrRates[ch.adsrState];
            ch.gain +%= if (rate == 1) 1024 else 32;
            if (ch.gain >= 0x7e0) ch.adsrState = 1;
            if (ch.gain > 0x7ff) ch.gain = 0x7ff;
        },
        1 => { // decay
            ch.gain = expDecay(ch.gain);
            if (ch.gain < ch.sustainLevel) ch.adsrState = 2;
        },
        2 => { // sustain
            ch.gain = expDecay(ch.gain);
        },
        3 => { // gain
            switch (ch.gainMode) {
                0 => { // linear decrease
                    ch.gain -%= 32;
                    // decreasing below 0 will underflow to above 0x7ff
                    if (ch.gain > 0x7ff) ch.gain = 0;
                },
                1 => { // exponential decrease
                    ch.gain = expDecay(ch.gain);
                },
                2 => { // linear increase
                    ch.gain +%= 32;
                    if (ch.gain > 0x7ff) ch.gain = 0;
                },
                else => { // bent increase
                    ch.gain +%= if (ch.gain < 0x600) 32 else 8;
                    if (ch.gain > 0x7ff) ch.gain = 0;
                },
            }
        },
        else => { // release
            ch.gain -%= 8;
            // decreasing below 0 will underflow to above 0x7ff
            if (ch.gain > 0x7ff) ch.gain = 0;
        },
    }
}

fn dsp_getSample(dsp: *Dsp, ch_i: usize, sampleNum: u16, offset: u16) i32 {
    const buf = &dsp.channel[ch_i].decodeBuffer;
    const news: i32 = buf[sampleNum + 3];
    const olds: i32 = buf[sampleNum + 2];
    const olders: i32 = buf[sampleNum + 1];
    const oldests: i32 = buf[sampleNum];
    var out = (gaussValues[0xff - offset] * oldests) >> 10;
    out += (gaussValues[0x1ff - offset] * olders) >> 10;
    out += (gaussValues[0x100 + offset] * olds) >> 10;
    out = clip16(out);
    out += (gaussValues[offset] * news) >> 10;
    out = clamp16(out);
    return out >> 1;
}

fn dsp_decodeBrr(dsp: *Dsp, ch_i: usize) void {
    const ch = &dsp.channel[ch_i];
    const ram = dsp.apu_ram.?;
    // copy last 3 samples (16-18) to first 3 for interpolation
    ch.decodeBuffer[0] = ch.decodeBuffer[16];
    ch.decodeBuffer[1] = ch.decodeBuffer[17];
    ch.decodeBuffer[2] = ch.decodeBuffer[18];
    // handle flags from previous block
    if (ch.previousFlags == 1 or ch.previousFlags == 3) {
        // loop sample
        const samplePointer = toU16(@as(i32, dsp.dirPage) + 4 * @as(i32, ch.srcn));
        ch.decodeOffset = ram[samplePointer +% 2];
        ch.decodeOffset |= @as(u16, ram[samplePointer +% 3]) << 8;
        if (ch.previousFlags == 1) {
            // also release and clear gain
            ch.adsrState = 4;
            ch.gain = 0;
        }
        dsp.ram[ENDX] |= @as(u8, 1) << @intCast(ch_i); // set ENDX bit for channel
    }
    const header = ram[ch.decodeOffset];
    ch.decodeOffset +%= 1;
    const shift = header >> 4;
    const filter = (header & 0xc) >> 2;
    ch.previousFlags = header & 0x3;
    var curByte: u8 = 0;
    var old: i32 = ch.old;
    var older: i32 = ch.older;
    for (0..16) |i| {
        var s: i32 = 0;
        if (i & 1 != 0) {
            s = curByte & 0xf;
        } else {
            curByte = ram[ch.decodeOffset];
            ch.decodeOffset +%= 1;
            s = curByte >> 4;
        }
        if (s > 7) s -= 16;
        if (shift <= 0xc) {
            s = (s << @intCast(shift)) >> 1;
        } else {
            s = (s >> 3) << 12;
        }
        switch (filter) {
            1 => s += old + (-old >> 4),
            2 => s += 2 * old + ((3 * -old) >> 5) - older + (older >> 4),
            3 => s += 2 * old + ((13 * -old) >> 6) - older + ((3 * older) >> 4),
            else => {},
        }
        s = clamp16(s);
        s = clip15(s);
        older = old;
        old = s;
        ch.decodeBuffer[i + 3] = @intCast(s);
    }
    ch.older = @intCast(older);
    ch.old = @intCast(old);
}

fn dsp_handleNoise(dsp: *Dsp) void {
    if (dsp.noiseRate != 0) {
        dsp.noiseCounter +%= 1;
    }
    if (dsp.noiseCounter >= dsp.noiseRate and dsp.noiseRate != 0) {
        const sample: i32 = dsp.noiseSample;
        const bit = (sample & 1) ^ ((sample >> 1) & 1);
        const next = ((sample >> 1) & 0x3fff) | (bit << 14);
        dsp.noiseSample = @intCast(clip15(next));
        dsp.noiseCounter = 0;
    }
}

/// Callers mask the address to 7 bits before getting here (see apu.c), so the
/// mirror ram index cannot leave the array.
pub export fn dsp_read(dsp: *Dsp, adr: u8) callconv(.c) u8 {
    return dsp.ram[adr & 0x7f];
}

pub export fn dsp_write(dsp: *Dsp, adr: u8, val_in: u8) callconv(.c) void {
    var val = val_in;
    const c = adr >> 4;
    const ch = &dsp.channel[c & 7];
    switch (adr & 0xf) {
        0x0 => ch.volumeL = @bitCast(val),
        0x1 => ch.volumeR = @bitCast(val),
        0x2 => ch.pitch = (ch.pitch & 0x3f00) | val,
        0x3 => ch.pitch = ((ch.pitch & 0x00ff) | (@as(u16, val) << 8)) & 0x3fff,
        0x4 => ch.srcn = val,
        0x5 => {
            ch.adsrRates[0] = @intCast(rateValues[(val & 0xf) * 2 + 1]);
            ch.adsrRates[1] = @intCast(rateValues[((val & 0x70) >> 4) * 2 + 16]);
            ch.useGain = (val & 0x80) == 0;
        },
        0x6 => {
            ch.adsrRates[2] = @intCast(rateValues[val & 0x1f]);
            ch.sustainLevel = (@as(u16, (val & 0xe0) >> 5) + 1) * 0x100;
        },
        0x7 => {
            ch.directGain = (val & 0x80) == 0;
            if (val & 0x80 != 0) {
                ch.gainMode = (val & 0x60) >> 5;
                ch.adsrRates[3] = @intCast(rateValues[val & 0x1f]);
            } else {
                ch.gainValue = @as(u16, val & 0x7f) * 16;
            }
        },
        0xf => dsp.firValues[c & 7] = @bitCast(val),
        0xc => switch (adr) {
            MVOLL => dsp.masterVolumeL = @bitCast(val),
            MVOLR => dsp.masterVolumeR = @bitCast(val),
            EVOLL => dsp.echoVolumeL = @bitCast(val),
            EVOLR => dsp.echoVolumeR = @bitCast(val),
            KON => for (&dsp.channel, 0..) |*c2, i| {
                c2.keyOn = val & (@as(u8, 1) << @intCast(i)) != 0;
                if (c2.keyOn) {
                    c2.keyOn = false;
                    // restart current sample
                    c2.previousFlags = 0;
                    const samplePointer = toU16(@as(i32, dsp.dirPage) + 4 * @as(i32, c2.srcn));
                    const ram = dsp.apu_ram.?;
                    c2.decodeOffset = ram[samplePointer];
                    c2.decodeOffset |= @as(u16, ram[samplePointer +% 1]) << 8;
                    @memset(&c2.decodeBuffer, 0);
                    c2.gain = 0;
                    c2.adsrState = if (c2.useGain) 3 else 0;
                }
            },
            KOF => for (&dsp.channel, 0..) |*c2, i| {
                c2.keyOff = val & (@as(u8, 1) << @intCast(i)) != 0;
                if (c2.keyOff) {
                    // go to release
                    c2.adsrState = 4;
                }
            },
            FLG => {
                dsp.reset = val & 0x80 != 0;
                dsp.mute = val & 0x40 != 0;
                dsp.echoWrites = (val & 0x20) == 0;
                dsp.noiseRate = @intCast(rateValues[val & 0x1f]);
            },
            ENDX => val = 0, // any write clears ENDx
            else => {},
        },
        0xd => switch (adr) {
            EFB => dsp.feedbackVolume = @bitCast(val),
            PMON => for (&dsp.channel, 0..) |*c2, i| {
                c2.pitchModulation = val & (@as(u8, 1) << @intCast(i)) != 0;
            },
            NON => for (&dsp.channel, 0..) |*c2, i| {
                c2.useNoise = val & (@as(u8, 1) << @intCast(i)) != 0;
            },
            EON => for (&dsp.channel, 0..) |*c2, i| {
                c2.echoEnable = val & (@as(u8, 1) << @intCast(i)) != 0;
            },
            DIR => dsp.dirPage = @as(u16, val) << 8,
            ESA => dsp.echoBufferAdr = @as(u16, val) << 8,
            EDL => {
                // 2048-byte steps, stereo sample is 4 bytes
                dsp.echoDelay = @as(u16, val & 0xf) * 512;
                if (dsp.echoDelay == 0) dsp.echoDelay = 1;
            },
            else => {},
        },
        else => {},
    }
    dsp.ram[adr & 0x7f] = val;
}

pub export fn dsp_getSamples(dsp: *Dsp, sampleData: [*]i16, samplesPerFrame: c_int, numChannels: c_int) callconv(.c) void {
    // resample from 534 samples per frame to wanted value
    const adder: f32 = 534.0 / @as(f32, @floatFromInt(samplesPerFrame));
    var location: f32 = 0.0;

    var i: c_int = 0;
    if (numChannels == 1) {
        while (i < samplesPerFrame) : (i += 1) {
            const at = @as(usize, @intFromFloat(location)) * 2;
            const sampleL: i32 = dsp.sampleBuffer[at];
            const sampleR: i32 = dsp.sampleBuffer[at + 1];
            sampleData[@intCast(i)] = toI16((sampleL + sampleR) >> 1);
            location += adder;
        }
    } else {
        while (i < samplesPerFrame) : (i += 1) {
            const at = @as(usize, @intFromFloat(location)) * 2;
            sampleData[@intCast(i * 2)] = dsp.sampleBuffer[at];
            sampleData[@intCast(i * 2 + 1)] = dsp.sampleBuffer[at + 1];
            location += adder;
        }
    }
    dsp.sampleOffset = 0;
}

const testing = std.testing;

const TestDsp = struct {
    dsp: *Dsp,
    ram: *[0x10000]u8,

    fn init() !TestDsp {
        const ram = try testing.allocator.create([0x10000]u8);
        @memset(ram, 0);
        const dsp = try testing.allocator.create(Dsp);
        dsp.* = std.mem.zeroes(Dsp);
        dsp.apu_ram = ram;
        dsp_reset(dsp);
        return .{ .dsp = dsp, .ram = ram };
    }

    fn deinit(self: TestDsp) void {
        testing.allocator.destroy(self.dsp);
        testing.allocator.destroy(self.ram);
    }
};

test "dsp_reset leaves the chip muted with every voice ended" {
    const t = try TestDsp.init();
    defer t.deinit();
    try testing.expectEqual(@as(u8, 0xff), t.dsp.ram[ENDX]);
    try testing.expect(t.dsp.mute);
    try testing.expect(t.dsp.reset);
    try testing.expectEqual(@as(i16, -0x4000), t.dsp.noiseSample);
    try testing.expectEqual(@as(u16, 1), t.dsp.echoDelay);
}

test "voice registers decode by channel and index" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;

    dsp_write(dsp, 0x30, 0x80); // V3VOLL, negative volume
    try testing.expectEqual(@as(i8, -128), dsp.channel[3].volumeL);
    dsp_write(dsp, 0x31, 0x7f); // V3VOLR
    try testing.expectEqual(@as(i8, 127), dsp.channel[3].volumeR);

    // Pitch is 14 bits split across two registers.
    dsp_write(dsp, 0x52, 0x34); // V5PL
    dsp_write(dsp, 0x53, 0xff); // V5PH, top two bits dropped
    try testing.expectEqual(@as(u16, 0x3f34), dsp.channel[5].pitch);

    dsp_write(dsp, 0x74, 0x12); // V7SRCN
    try testing.expectEqual(@as(u8, 0x12), dsp.channel[7].srcn);

    // Every write also lands in the register mirror.
    try testing.expectEqual(@as(u8, 0x12), dsp_read(dsp, 0x74));
}

test "ADSR and GAIN registers pick rates out of the table" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;

    dsp_write(dsp, 0x05, 0x8f); // V0ADSR1: attack 15, decay 0, adsr enabled
    try testing.expectEqual(@as(u16, @intCast(rateValues[31])), dsp.channel[0].adsrRates[0]);
    try testing.expectEqual(@as(u16, @intCast(rateValues[16])), dsp.channel[0].adsrRates[1]);
    try testing.expect(!dsp.channel[0].useGain);

    dsp_write(dsp, 0x05, 0x00); // clearing bit 7 switches the voice to gain
    try testing.expect(dsp.channel[0].useGain);

    dsp_write(dsp, 0x06, 0xe0); // V0ADSR2: sustain level 7
    try testing.expectEqual(@as(u16, 8 * 0x100), dsp.channel[0].sustainLevel);

    dsp_write(dsp, 0x07, 0x7f); // V0GAIN: direct gain
    try testing.expect(dsp.channel[0].directGain);
    try testing.expectEqual(@as(u16, 0x7f * 16), dsp.channel[0].gainValue);

    dsp_write(dsp, 0x07, 0xa5); // V0GAIN: mode 1, rate 5
    try testing.expect(!dsp.channel[0].directGain);
    try testing.expectEqual(@as(u8, 1), dsp.channel[0].gainMode);
}

test "global registers are routed by their full address" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;

    dsp_write(dsp, MVOLL, 0x60);
    dsp_write(dsp, MVOLR, 0x40);
    try testing.expectEqual(@as(i8, 0x60), dsp.masterVolumeL);
    try testing.expectEqual(@as(i8, 0x40), dsp.masterVolumeR);

    dsp_write(dsp, DIR, 0x20);
    try testing.expectEqual(@as(u16, 0x2000), dsp.dirPage);
    dsp_write(dsp, ESA, 0x30);
    try testing.expectEqual(@as(u16, 0x3000), dsp.echoBufferAdr);

    dsp_write(dsp, EDL, 0x03);
    try testing.expectEqual(@as(u16, 3 * 512), dsp.echoDelay);
    dsp_write(dsp, EDL, 0x00); // a zero delay still has to advance
    try testing.expectEqual(@as(u16, 1), dsp.echoDelay);

    dsp_write(dsp, FLG, 0xe0); // reset, mute, echo writes disabled
    try testing.expect(dsp.reset and dsp.mute and !dsp.echoWrites);
    dsp_write(dsp, FLG, 0x00);
    try testing.expect(!dsp.reset and !dsp.mute and dsp.echoWrites);

    // FIR taps are one per channel row.
    dsp_write(dsp, 0x2f, 0xff); // FIR2
    try testing.expectEqual(@as(i8, -1), dsp.firValues[2]);

    // Any write to ENDX clears it.
    dsp_write(dsp, ENDX, 0xff);
    try testing.expectEqual(@as(u8, 0), dsp.ram[ENDX]);
}

test "per-voice bitmask registers fan out to all eight channels" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;

    dsp_write(dsp, PMON, 0b0000_0110);
    try testing.expect(!dsp.channel[0].pitchModulation);
    try testing.expect(dsp.channel[1].pitchModulation);
    try testing.expect(dsp.channel[2].pitchModulation);

    dsp_write(dsp, NON, 0b1000_0000);
    try testing.expect(dsp.channel[7].useNoise);
    dsp_write(dsp, EON, 0b0000_0001);
    try testing.expect(dsp.channel[0].echoEnable);
}

test "KON restarts a voice from its directory entry" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;

    // Directory at $0200, voice 1 uses source 2 -> entry at $0200 + 8.
    dsp_write(dsp, DIR, 0x02);
    dsp_write(dsp, 0x14, 2); // V1SRCN
    t.ram[0x0208] = 0x34; // start address low
    t.ram[0x0209] = 0x12; // start address high

    dsp.channel[1].gain = 0x500;
    dsp.channel[1].decodeBuffer[5] = 999;
    dsp_write(dsp, KON, 0b0000_0010);

    try testing.expectEqual(@as(u16, 0x1234), dsp.channel[1].decodeOffset);
    try testing.expectEqual(@as(u16, 0), dsp.channel[1].gain);
    try testing.expectEqual(@as(i16, 0), dsp.channel[1].decodeBuffer[5]);
    try testing.expectEqual(@as(u8, 0), dsp.channel[1].adsrState); // attack
    try testing.expect(!dsp.channel[1].keyOn); // consumed immediately

    // With gain selected the voice starts in the gain state instead.
    dsp.channel[1].useGain = true;
    dsp_write(dsp, KON, 0b0000_0010);
    try testing.expectEqual(@as(u8, 3), dsp.channel[1].adsrState);
}

test "KOF puts the named voices into release" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;
    dsp.channel[2].adsrState = 1;
    dsp.channel[3].adsrState = 1;
    dsp_write(dsp, KOF, 0b0000_0100);
    try testing.expectEqual(@as(u8, 4), dsp.channel[2].adsrState);
    try testing.expectEqual(@as(u8, 1), dsp.channel[3].adsrState);
}

test "the envelope walks attack, decay, sustain and release" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;
    const ch = &dsp.channel[0];

    // attack: +32 per step until 0x7e0 hands over to decay
    ch.adsrState = 0;
    ch.adsrRates[0] = 5;
    ch.gain = 0x7c0;
    dsp_handleGain(dsp, 0);
    try testing.expectEqual(@as(u16, 0x7e0), ch.gain);
    try testing.expectEqual(@as(u8, 1), ch.adsrState);

    // decay drops exponentially, and stays in decay while it is still above
    // the sustain level
    ch.sustainLevel = 0x700;
    dsp_handleGain(dsp, 0);
    try testing.expectEqual(@as(u16, 0x7e0 - ((0x7df >> 8) + 1)), ch.gain);
    try testing.expectEqual(@as(u8, 1), ch.adsrState);

    // once it falls under the sustain level the voice moves to sustain
    ch.sustainLevel = 0x7d8;
    dsp_handleGain(dsp, 0);
    try testing.expect(ch.gain < ch.sustainLevel);
    try testing.expectEqual(@as(u8, 2), ch.adsrState);

    // release subtracts 8 and clamps at zero rather than wrapping
    ch.adsrState = 4;
    ch.gain = 4;
    dsp_handleGain(dsp, 0);
    try testing.expectEqual(@as(u16, 0), ch.gain);
}

test "the noise generator runs its LFSR and stays 15-bit" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;
    dsp.noiseRate = 1;
    dsp.noiseSample = -0x4000;
    dsp_handleNoise(dsp);
    // -0x4000 is 0x4000 in 15-bit terms: bit0 ^ bit1 = 0, so the new top bit
    // is 0 and the value shifts down.
    try testing.expectEqual(@as(i16, 0x2000), dsp.noiseSample);
    for (0..64) |_| {
        dsp_handleNoise(dsp);
        try testing.expect(dsp.noiseSample >= -0x4000 and dsp.noiseSample <= 0x3fff);
    }
}

test "BRR decoding expands a block of sixteen nibbles" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;
    const ch = &dsp.channel[0];

    // shift 4, filter 0, no flags; then eight bytes of nibble pairs.
    ch.decodeOffset = 0x100;
    t.ram[0x100] = 0x40;
    for (0..8) |i| t.ram[0x101 + i] = 0x11;
    dsp_decodeBrr(dsp, 0);

    // each nibble is 1: (1 << 4) >> 1 = 8
    for (3..19) |i| try testing.expectEqual(@as(i16, 8), ch.decodeBuffer[i]);
    try testing.expectEqual(@as(u16, 0x109), ch.decodeOffset);
    try testing.expectEqual(@as(i16, 8), ch.old);

    // Negative nibbles sign extend from four bits.
    ch.decodeOffset = 0x200;
    t.ram[0x200] = 0x40;
    for (0..8) |i| t.ram[0x201 + i] = 0xff; // nibble 15 -> -1
    ch.old = 0;
    ch.older = 0;
    dsp_decodeBrr(dsp, 0);
    try testing.expectEqual(@as(i16, -8), ch.decodeBuffer[3]);
}

test "an end flag on the previous block loops and sets ENDX" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;
    const ch = &dsp.channel[2];

    dsp.ram[ENDX] = 0;
    dsp.dirPage = 0x0200;
    ch.srcn = 1; // entry at $0204, loop address at $0206
    t.ram[0x0206] = 0x00;
    t.ram[0x0207] = 0x30;
    ch.previousFlags = 1; // end + release
    ch.decodeOffset = 0x100;
    t.ram[0x3000] = 0x00; // header at the loop point

    dsp_decodeBrr(dsp, 2);
    try testing.expectEqual(@as(u8, 0b100), dsp.ram[ENDX]);
    try testing.expectEqual(@as(u8, 4), ch.adsrState); // released
    try testing.expectEqual(@as(u16, 0), ch.gain);
}

test "gauss interpolation of a flat buffer returns that level" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;
    // At offset 0x80 the four taps are 0x038, 0x3c5, 0x3c9 and 0x03a. Each
    // term is (tap * sample) >> 10, so a flat 0x400 input sums to 0x800 and
    // the final halving gives the input level back.
    for (&dsp.channel[0].decodeBuffer) |*s| s.* = 0x400;
    try testing.expectEqual(@as(i32, 0x400), dsp_getSample(dsp, 0, 0, 0x80));
    // A silent buffer stays silent.
    @memset(&dsp.channel[0].decodeBuffer, 0);
    try testing.expectEqual(@as(i32, 0), dsp_getSample(dsp, 0, 0, 0x80));
}

test "dsp_getSamples resamples a frame down to the requested count" {
    const t = try TestDsp.init();
    defer t.deinit();
    const dsp = t.dsp;
    for (0..534) |i| {
        dsp.sampleBuffer[i * 2] = @intCast(i);
        dsp.sampleBuffer[i * 2 + 1] = @intCast(i);
    }
    dsp.sampleOffset = 534;

    var stereo: [2 * 267]i16 = undefined;
    dsp_getSamples(dsp, &stereo, 267, 2);
    try testing.expectEqual(@as(i16, 0), stereo[0]);
    try testing.expectEqual(@as(i16, 2), stereo[2]); // 534/267 = 2 per step
    try testing.expectEqual(@as(u16, 0), dsp.sampleOffset);

    var mono: [267]i16 = undefined;
    dsp.sampleOffset = 534;
    dsp_getSamples(dsp, &mono, 267, 1);
    try testing.expectEqual(@as(i16, 2), mono[1]); // (2 + 2) >> 1
}

test "the lookup tables came over intact" {
    try testing.expectEqual(32, rateValues.len);
    try testing.expectEqual(2048, rateValues[1]);
    try testing.expectEqual(1, rateValues[31]);
    try testing.expectEqual(512, gaussValues.len);
    try testing.expectEqual(0x000, gaussValues[0]);
    try testing.expectEqual(0x011, gaussValues[79]);
    try testing.expectEqual(0x0A8, gaussValues[191]);
    try testing.expectEqual(0x379, gaussValues[367]);
    try testing.expectEqual(0x519, gaussValues[511]);
    // The four taps of any interpolation position sum to roughly unity in
    // 11-bit terms (0x800), which is what keeps the filter from changing the
    // volume of a steady signal.
    for (0..256) |off| {
        const sum = gaussValues[0xff - off] + gaussValues[0x1ff - off] +
            gaussValues[0x100 + off] + gaussValues[off];
        try testing.expect(sum >= 0x7f8 and sum <= 0x808);
    }
}

test "Dsp layout matches dsp.h" {
    // Offsets taken from the C compiler on this target. spc.c and apu.c share
    // this struct, and dsp_saveload writes it straight into save files.
    if (@sizeOf(*anyopaque) != 8) return error.SkipZigTest;
    try testing.expectEqual(86, @sizeOf(DspChannel));
    try testing.expectEqual(3032, @sizeOf(Dsp));
    try testing.expectEqual(0, @offsetOf(Dsp, "apu_ram"));
    try testing.expectEqual(8, @offsetOf(Dsp, "ram"));
    try testing.expectEqual(136, @offsetOf(Dsp, "channel"));
    try testing.expectEqual(824, @offsetOf(Dsp, "dirPage"));
    try testing.expectEqual(832, @offsetOf(Dsp, "noiseSample"));
    try testing.expectEqual(851, @offsetOf(Dsp, "firValues"));
    try testing.expectEqual(892, @offsetOf(Dsp, "sampleBuffer"));
    try testing.expectEqual(3028, @offsetOf(Dsp, "sampleOffset"));
    // The block dsp_saveload hands to the save file.
    try testing.expectEqual(3024, @sizeOf(Dsp) - @offsetOf(Dsp, "ram"));
}
