//! Port of snes/dma.c: the eight general purpose DMA / HDMA channels.
const std = @import("std");
const snes_types = @import("snes_types.zig");

const Snes = snes_types.Snes;
const SaveLoadFunc = snes_types.SaveLoadFunc;
const snes_read = snes_types.snes_read;
const snes_write = snes_types.snes_write;
const snes_readBBus = snes_types.snes_readBBus;
const snes_writeBBus = snes_types.snes_writeBBus;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

const bAdrOffsets = [8][4]u8{
    .{ 0, 0, 0, 0 },
    .{ 0, 1, 0, 1 },
    .{ 0, 0, 0, 0 },
    .{ 0, 0, 1, 1 },
    .{ 0, 1, 2, 3 },
    .{ 0, 1, 0, 1 },
    .{ 0, 0, 0, 0 },
    .{ 0, 0, 1, 1 },
};

const transferLength = [8]u8{ 1, 2, 2, 4, 4, 4, 2, 4 };

/// Must match `struct DmaChannel` in dma.h.
pub const DmaChannel = extern struct {
    bAdr: u8,
    aBank: u8,
    indBank: u8, // hdma
    repCount: u8, // hdma
    aAdr: u16,
    size: u16, // also indirect hdma adr
    tableAdr: u16, // hdma
    unusedByte: u8,
    dmaActive: bool,
    hdmaActive: bool,
    mode: u8,
    fixed: bool,
    decrement: bool,
    indirect: bool, // hdma
    fromB: bool,
    unusedBit: bool,
    doTransfer: bool, // hdma
    terminated: bool, // hdma
    offIndex: u8,
};

/// Must match `struct Dma` in dma.h.
pub const Dma = extern struct {
    snes: ?*Snes,
    channel: [8]DmaChannel,
    hdmaTimer: u16,
    dmaTimer: u32,
    dmaBusy: bool,
};

pub export fn dma_init(snes: ?*Snes) callconv(.c) *Dma {
    const dma: *Dma = @ptrCast(@alignCast(malloc(@sizeOf(Dma)).?));
    dma.snes = snes;
    return dma;
}

pub export fn dma_free(dma: *Dma) callconv(.c) void {
    free(dma);
}

pub export fn dma_reset(dma: *Dma) callconv(.c) void {
    for (&dma.channel) |*ch| {
        ch.bAdr = 0xff;
        ch.aAdr = 0xffff;
        ch.aBank = 0xff;
        ch.size = 0xffff;
        ch.indBank = 0xff;
        ch.tableAdr = 0xffff;
        ch.repCount = 0xff;
        ch.unusedByte = 0xff;
        ch.dmaActive = false;
        ch.hdmaActive = false;
        ch.mode = 7;
        ch.fixed = true;
        ch.decrement = true;
        ch.indirect = true;
        ch.fromB = true;
        ch.unusedBit = true;
        ch.doTransfer = false;
        ch.terminated = false;
        ch.offIndex = 0;
    }
    dma.hdmaTimer = 0;
    dma.dmaTimer = 0;
    dma.dmaBusy = false;
}

pub export fn dma_saveload(dma: *Dma, func: *const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    func(ctx, @ptrCast(&dma.channel), @sizeOf(Dma) - @offsetOf(Dma, "channel"));
}

pub export fn dma_read(dma: *Dma, adr: u16) callconv(.c) u8 {
    const ch = &dma.channel[(adr & 0x70) >> 4];
    return switch (adr & 0xf) {
        0x0 => ch.mode |
            @as(u8, @intFromBool(ch.fixed)) << 3 |
            @as(u8, @intFromBool(ch.decrement)) << 4 |
            @as(u8, @intFromBool(ch.unusedBit)) << 5 |
            @as(u8, @intFromBool(ch.indirect)) << 6 |
            @as(u8, @intFromBool(ch.fromB)) << 7,
        0x1 => ch.bAdr,
        0x2 => @truncate(ch.aAdr),
        0x3 => @truncate(ch.aAdr >> 8),
        0x4 => ch.aBank,
        0x5 => @truncate(ch.size),
        0x6 => @truncate(ch.size >> 8),
        0x7 => ch.indBank,
        0x8 => @truncate(ch.tableAdr),
        0x9 => @truncate(ch.tableAdr >> 8),
        0xa => ch.repCount,
        0xb, 0xf => ch.unusedByte,
        else => dma.snes.?.openBus,
    };
}

pub export fn dma_write(dma: *Dma, adr: u16, val: u8) callconv(.c) void {
    const ch = &dma.channel[(adr & 0x70) >> 4];
    switch (adr & 0xf) {
        0x0 => {
            ch.mode = val & 0x7;
            ch.fixed = val & 0x8 != 0;
            ch.decrement = val & 0x10 != 0;
            ch.unusedBit = val & 0x20 != 0;
            ch.indirect = val & 0x40 != 0;
            ch.fromB = val & 0x80 != 0;
        },
        0x1 => ch.bAdr = val,
        0x2 => ch.aAdr = (ch.aAdr & 0xff00) | val,
        0x3 => ch.aAdr = (ch.aAdr & 0xff) | (@as(u16, val) << 8),
        0x4 => ch.aBank = val,
        0x5 => ch.size = (ch.size & 0xff00) | val,
        0x6 => ch.size = (ch.size & 0xff) | (@as(u16, val) << 8),
        0x7 => ch.indBank = val,
        0x8 => ch.tableAdr = (ch.tableAdr & 0xff00) | val,
        0x9 => ch.tableAdr = (ch.tableAdr & 0xff) | (@as(u16, val) << 8),
        0xa => ch.repCount = val,
        0xb, 0xf => ch.unusedByte = val,
        else => {},
    }
}

pub export fn dma_doDma(dma: *Dma) callconv(.c) void {
    // figure out first channel that is active
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (dma.channel[i].dmaActive) break;
    }
    if (i == 8) {
        // no active channels
        dma.dmaBusy = false;
        return;
    }
    // do channel i
    const ch = &dma.channel[i];
    const off = bAdrOffsets[ch.mode][ch.offIndex];
    ch.offIndex +%= 1;
    dma_transferByte(dma, ch.aAdr, ch.aBank, ch.bAdr +% off, ch.fromB);
    ch.offIndex &= 3;
    dma.dmaTimer +%= 6; // 8 cycles for each byte taken, -2 for this cycle
    if (!ch.fixed) {
        ch.aAdr = if (ch.decrement) ch.aAdr -% 1 else ch.aAdr +% 1;
    }
    ch.size -%= 1;
    if (ch.size == 0) {
        ch.offIndex = 0; // reset offset index
        ch.dmaActive = false;
        dma.dmaTimer +%= 8; // 8 cycle overhead per channel
    }
}

pub export fn dma_initHdma(dma: *Dma) callconv(.c) void {
    dma.hdmaTimer = 0;
    var hdmaHappened = false;
    for (&dma.channel) |*ch| {
        if (ch.hdmaActive) {
            hdmaHappened = true;
            // terminate any dma
            ch.dmaActive = false;
            ch.offIndex = 0;
            // load address, repCount, and indirect address if needed
            ch.tableAdr = ch.aAdr;
            ch.repCount = snes_read(dma.snes.?, tableRead(ch));
            dma.hdmaTimer +%= 8; // 8 cycle overhead for each active channel
            if (ch.indirect) {
                ch.size = snes_read(dma.snes.?, tableRead(ch));
                ch.size |= @as(u16, snes_read(dma.snes.?, tableRead(ch))) << 8;
                dma.hdmaTimer +%= 16; // another 16 cycles for indirect (total 24)
            }
            ch.doTransfer = true;
        } else {
            ch.doTransfer = false;
        }
        ch.terminated = false;
    }
    if (hdmaHappened) dma.hdmaTimer +%= 16; // 18 cycles overhead, -2 for this cycle
}

/// The C code reads through `tableAdr++` in the middle of an expression; this
/// keeps the read and the post-increment together.
fn tableRead(ch: *DmaChannel) u32 {
    const adr = @as(u32, ch.aBank) << 16 | ch.tableAdr;
    ch.tableAdr +%= 1;
    return adr;
}

pub export fn dma_doHdma(dma: *Dma) callconv(.c) void {
    dma.hdmaTimer = 0;
    var hdmaHappened = false;
    for (&dma.channel) |*ch| {
        if (ch.hdmaActive and !ch.terminated) {
            hdmaHappened = true;
            // terminate any dma
            ch.dmaActive = false;
            ch.offIndex = 0;
            // do the hdma
            dma.hdmaTimer +%= 8; // 8 cycles overhead for each active channel
            if (ch.doTransfer) {
                for (0..transferLength[ch.mode]) |j| {
                    dma.hdmaTimer +%= 8; // 8 cycles for each byte transferred
                    const bAdr = ch.bAdr +% bAdrOffsets[ch.mode][j];
                    if (ch.indirect) {
                        const aAdr = ch.size;
                        ch.size +%= 1;
                        dma_transferByte(dma, aAdr, ch.indBank, bAdr, ch.fromB);
                    } else {
                        const aAdr = ch.tableAdr;
                        ch.tableAdr +%= 1;
                        dma_transferByte(dma, aAdr, ch.aBank, bAdr, ch.fromB);
                    }
                }
            }
            ch.repCount -%= 1;
            ch.doTransfer = ch.repCount & 0x80 != 0;
            if (ch.repCount & 0x7f == 0) {
                ch.repCount = snes_read(dma.snes.?, tableRead(ch));
                if (ch.indirect) {
                    // TODO: oddness with not fetching high byte if last active channel and reCount is 0
                    ch.size = snes_read(dma.snes.?, tableRead(ch));
                    ch.size |= @as(u16, snes_read(dma.snes.?, tableRead(ch))) << 8;
                    dma.hdmaTimer +%= 16; // 16 cycles for new indirect address
                }
                if (ch.repCount == 0) ch.terminated = true;
                ch.doTransfer = true;
            }
        }
    }
    if (hdmaHappened) dma.hdmaTimer +%= 16; // 18 cycles overhead, -2 for this cycle
}

// TODO: invalid writes:
//   accesing b-bus via a-bus gives open bus,
//   $2180-$2183 while accessing ram via a-bus open busses $2180-$2183
//   cannot access $4300-$437f (dma regs), or $420b / $420c
fn dma_transferByte(dma: *Dma, aAdr: u16, aBank: u8, bAdr: u8, fromB: bool) void {
    const snes = dma.snes.?;
    if (fromB) {
        snes_write(snes, @as(u32, aBank) << 16 | aAdr, snes_readBBus(snes, bAdr));
    } else {
        const data = snes_read(snes, @as(u32, aBank) << 16 | aAdr);
        snes_writeBBus(snes, bAdr, data);
    }
}

pub export fn dma_cycle(dma: *Dma) callconv(.c) bool {
    if (dma.hdmaTimer > 0) {
        dma.hdmaTimer -%= 2;
        return true;
    } else if (dma.dmaBusy) {
        dma_doDma(dma);
        return true;
    }
    return false;
}

pub export fn dma_startDma(dma: *Dma, val: u8, hdma: bool) callconv(.c) void {
    for (&dma.channel, 0..) |*ch, i| {
        if (hdma) {
            ch.hdmaActive = val & (@as(u8, 1) << @intCast(i)) != 0;
        } else {
            ch.dmaActive = val & (@as(u8, 1) << @intCast(i)) != 0;
        }
    }
    if (!hdma) {
        dma.dmaBusy = val != 0;
        dma.dmaTimer +%= if (dma.dmaBusy) 16 else 0; // 12-24 cycle overhead for entire dma transfer
    }
}

const testing = std.testing;

fn emptyDma() Dma {
    var dma = std.mem.zeroes(Dma);
    dma_reset(&dma);
    return dma;
}

test "dma_reset puts every channel in its power-on state" {
    const dma = emptyDma();
    for (dma.channel) |ch| {
        try testing.expectEqual(@as(u8, 0xff), ch.bAdr);
        try testing.expectEqual(@as(u16, 0xffff), ch.aAdr);
        try testing.expectEqual(@as(u8, 7), ch.mode);
        try testing.expect(ch.fixed and ch.decrement and ch.indirect and ch.fromB);
        try testing.expect(!ch.dmaActive and !ch.hdmaActive);
    }
    try testing.expect(!dma.dmaBusy);
}

test "channel registers round-trip through dma_read and dma_write" {
    var dma = emptyDma();
    // Channel 3 lives at 43x0, so bits 4-6 of the address pick the channel.
    dma_write(&dma, 0x30, 0b1010_1101);
    dma_write(&dma, 0x31, 0x18);
    dma_write(&dma, 0x32, 0x34);
    dma_write(&dma, 0x33, 0x12);
    dma_write(&dma, 0x34, 0x7e);
    dma_write(&dma, 0x35, 0xcd);
    dma_write(&dma, 0x36, 0xab);

    const ch = dma.channel[3];
    try testing.expectEqual(@as(u8, 5), ch.mode);
    // 0xad = fromB | unusedBit | fixed | mode 5; bits 4 and 6 are clear.
    try testing.expect(ch.fixed);
    try testing.expect(!ch.decrement);
    try testing.expect(ch.unusedBit);
    try testing.expect(!ch.indirect);
    try testing.expect(ch.fromB);
    try testing.expectEqual(@as(u16, 0x1234), ch.aAdr);
    try testing.expectEqual(@as(u16, 0xabcd), ch.size);

    try testing.expectEqual(@as(u8, 0b1010_1101), dma_read(&dma, 0x30));
    try testing.expectEqual(@as(u8, 0x18), dma_read(&dma, 0x31));
    try testing.expectEqual(@as(u8, 0x34), dma_read(&dma, 0x32));
    try testing.expectEqual(@as(u8, 0x12), dma_read(&dma, 0x33));
    try testing.expectEqual(@as(u8, 0x7e), dma_read(&dma, 0x34));
    try testing.expectEqual(@as(u8, 0xcd), dma_read(&dma, 0x35));
    try testing.expectEqual(@as(u8, 0xab), dma_read(&dma, 0x36));
}

test "dma_startDma arms the channels named in the bitmask" {
    var dma = emptyDma();
    dma_startDma(&dma, 0b0000_0101, false);
    try testing.expect(dma.channel[0].dmaActive);
    try testing.expect(!dma.channel[1].dmaActive);
    try testing.expect(dma.channel[2].dmaActive);
    try testing.expect(dma.dmaBusy);

    dma_startDma(&dma, 0x80, true);
    try testing.expect(dma.channel[7].hdmaActive);
    try testing.expect(!dma.channel[6].hdmaActive);
    // An hdma start must not disturb dmaBusy.
    try testing.expect(dma.dmaBusy);

    dma_startDma(&dma, 0, false);
    try testing.expect(!dma.dmaBusy);
    try testing.expect(!dma.channel[0].dmaActive);
}

test "dma_cycle drains the hdma timer before running dma" {
    var dma = emptyDma();
    dma.hdmaTimer = 4;
    dma.dmaBusy = true;
    try testing.expect(dma_cycle(&dma));
    try testing.expectEqual(@as(u16, 2), dma.hdmaTimer);
    try testing.expect(dma_cycle(&dma));
    try testing.expectEqual(@as(u16, 0), dma.hdmaTimer);
    // With the timer drained and no channel armed, the dma finishes.
    try testing.expect(dma_cycle(&dma));
    try testing.expect(!dma.dmaBusy);
    try testing.expect(!dma_cycle(&dma));
}

test "Dma layout matches dma.h" {
    // Offsets taken from the C compiler on this target.
    if (@sizeOf(*anyopaque) != 8) return error.SkipZigTest;
    try testing.expectEqual(22, @sizeOf(DmaChannel));
    try testing.expectEqual(200, @sizeOf(Dma));
    try testing.expectEqual(0, @offsetOf(Dma, "snes"));
    try testing.expectEqual(8, @offsetOf(Dma, "channel"));
    try testing.expectEqual(184, @offsetOf(Dma, "hdmaTimer"));
    // dma_saveload hands the C side everything from `channel` onwards.
    try testing.expectEqual(192, @sizeOf(Dma) - @offsetOf(Dma, "channel"));
}
