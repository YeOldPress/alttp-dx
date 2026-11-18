//! A FLAC encoder, as much of one as MSU tracks need: 16-bit samples, one or
//! two channels, blocks of 4096 frames. Each block's channels get the best of
//! constant, verbatim, the fixed predictors and an LPC one, and the best of
//! the four ways FLAC can lay out stereo. That lands within a few percent of
//! `flac -8`.
//!
//! Nothing it writes is trusted until it's been decoded again and matched
//! against what went in; msu_import does that before a .pcm is let go of.
const std = @import("std");

const kBlock = 4096;
const kMaxLpcOrder = 12;
/// Bits a quantized LPC coefficient gets: what libFLAC picks for 16-bit
/// audio in blocks this size.
const kPrecision = 12;
const kMaxPartitionOrder = 8;
/// A seek point every ten seconds or so, so a loop or a resume lands at once
/// instead of searching the file from the audio thread.
const kSeekEvery = 441000;
const kVendor = "alttp-dx";

pub const Options = struct {
    channels: u8 = 2,
    rate: u32 = 44100,
    /// Kept as a LOOPSTART tag, the frame a repeat goes back to.
    loop_start: ?u32 = null,
};

/// `samples` (interleaved, `opts.channels` to a frame) as a whole FLAC file.
pub fn encode(alloc: std.mem.Allocator, samples: []align(1) const i16, opts: Options) ![]u8 {
    std.debug.assert(opts.channels == 1 or opts.channels == 2);
    const nch: usize = opts.channels;
    const total: usize = samples.len / nch;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.ensureTotalCapacity(alloc, total * nch + 4096);

    // ---- metadata: STREAMINFO, SEEKTABLE, VORBIS_COMMENT
    try out.appendSlice(alloc, "fLaC");
    try blockHeader(alloc, &out, false, 0, 34);
    const streaminfo_at = out.items.len;
    try out.appendNTimes(alloc, 0, 34);

    const frame_count = (total + kBlock - 1) / kBlock;
    const seek_count = if (total == 0) 0 else (total + kSeekEvery - 1) / kSeekEvery;
    try blockHeader(alloc, &out, false, 3, @intCast(seek_count * 18));
    const seektable_at = out.items.len;
    try out.appendNTimes(alloc, 0, seek_count * 18);

    var tag_buf: [32]u8 = undefined;
    const loop_tag: ?[]const u8 = if (opts.loop_start) |l| try std.fmt.bufPrint(&tag_buf, "LOOPSTART={d}", .{l}) else null;
    const comment_len = 4 + kVendor.len + 4 + if (loop_tag) |t| 4 + t.len else 0;
    try blockHeader(alloc, &out, true, 4, @intCast(comment_len));
    try le32(alloc, &out, kVendor.len);
    try out.appendSlice(alloc, kVendor);
    try le32(alloc, &out, if (loop_tag != null) 1 else 0);
    if (loop_tag) |t| {
        try le32(alloc, &out, @intCast(t.len));
        try out.appendSlice(alloc, t);
    }

    // ---- frames
    const first_frame = out.items.len;
    const frame_offsets = try alloc.alloc(u64, frame_count);
    defer alloc.free(frame_offsets);
    var enc = try Encoder.init(alloc);
    defer enc.deinit(alloc);
    var min_frame: u32 = std.math.maxInt(u32);
    var max_frame: u32 = 0;
    var md5 = std.crypto.hash.Md5.init(.{});
    for (0..frame_count) |fi| {
        const start = fi * kBlock;
        const n: usize = @min(kBlock, total - start);
        const block = samples[start * nch ..][0 .. n * nch];
        md5Update(&md5, block);
        frame_offsets[fi] = out.items.len - first_frame;
        const at = out.items.len;
        try enc.frame(alloc, &out, block, nch, @intCast(fi), opts.rate);
        const size: u32 = @intCast(out.items.len - at);
        min_frame = @min(min_frame, size);
        max_frame = @max(max_frame, size);
    }
    if (frame_count == 0) min_frame = 0;

    // ---- back to fill in what's only known now
    var si: [34]u8 = undefined;
    const block_size: u16 = @intCast(if (total >= kBlock) kBlock else @max(total, 16));
    std.mem.writeInt(u16, si[0..2], block_size, .big);
    std.mem.writeInt(u16, si[2..4], block_size, .big);
    std.mem.writeInt(u24, si[4..7], @intCast(min_frame), .big);
    std.mem.writeInt(u24, si[7..10], @intCast(max_frame), .big);
    // 20 bits of rate, 3 of channels - 1, 5 of bits - 1, 36 of frames.
    const packed_info: u64 = @as(u64, opts.rate) << 44 | @as(u64, nch - 1) << 41 | @as(u64, 15) << 36 | @as(u64, total);
    std.mem.writeInt(u64, si[10..18], packed_info, .big);
    md5.final(si[18..34]);
    @memcpy(out.items[streaminfo_at..][0..34], &si);

    for (0..seek_count) |i| {
        const fi = @min(i * kSeekEvery / kBlock, frame_count - 1);
        const p = out.items[seektable_at + i * 18 ..][0..18];
        std.mem.writeInt(u64, p[0..8], fi * kBlock, .big);
        std.mem.writeInt(u64, p[8..16], frame_offsets[fi], .big);
        std.mem.writeInt(u16, p[16..18], @intCast(@min(kBlock, total - fi * kBlock)), .big);
    }
    return out.toOwnedSlice(alloc);
}

fn blockHeader(alloc: std.mem.Allocator, out: *std.ArrayList(u8), last: bool, kind: u7, len: u24) !void {
    try out.append(alloc, @as(u8, @intFromBool(last)) << 7 | kind);
    var b: [3]u8 = undefined;
    std.mem.writeInt(u24, &b, len, .big);
    try out.appendSlice(alloc, &b);
}

fn le32(alloc: std.mem.Allocator, out: *std.ArrayList(u8), v: u32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, v, .little);
    try out.appendSlice(alloc, &b);
}

/// FLAC's MD5 is of the samples as little-endian bytes.
fn md5Update(md5: *std.crypto.hash.Md5, block: []align(1) const i16) void {
    var buf: [512]u8 = undefined;
    var i: usize = 0;
    while (i < block.len) {
        const n: usize = @min(block.len - i, buf.len / 2);
        for (0..n) |j| std.mem.writeInt(i16, buf[j * 2 ..][0..2], block[i + j], .little);
        md5.update(buf[0 .. n * 2]);
        i += n;
    }
}

// ------------------------------------------------------------------- bits

const Bits = struct {
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    acc: u64 = 0,
    n: u7 = 0,

    /// The low `bits` bits of `v`, `bits` at most 32.
    fn put(self: *Bits, v: u64, bits: u7) !void {
        if (bits == 0) return;
        const mask = (@as(u64, 1) << @intCast(bits)) - 1;
        self.acc = (self.acc << @intCast(bits)) | (v & mask);
        self.n += bits;
        while (self.n >= 8) {
            self.n -= 8;
            try self.out.append(self.alloc, @truncate(self.acc >> @intCast(self.n)));
        }
    }

    fn signed(self: *Bits, v: i64, bits: u7) !void {
        try self.put(@bitCast(v), bits);
    }

    fn zeros(self: *Bits, count: u64) !void {
        var left = count;
        while (left >= 32) : (left -= 32) try self.put(0, 32);
        try self.put(0, @intCast(left));
    }

    fn rice(self: *Bits, r: i64, k: u5) !void {
        const u = fold(r);
        try self.zeros(u >> k);
        try self.put(1, 1);
        try self.put(u, k);
    }

    fn alignByte(self: *Bits) !void {
        if (self.n != 0) try self.put(0, 8 - self.n);
    }
};

fn fold(r: i64) u64 {
    return if (r >= 0) @as(u64, @intCast(r)) << 1 else (@as(u64, @intCast(-(r + 1))) << 1) | 1;
}

// ---------------------------------------------------------------- encoder

const Kind = enum { constant, verbatim, fixed, lpc };

/// How one channel of one block is coded, and roughly what it costs.
const Plan = struct {
    kind: Kind = .verbatim,
    order: u8 = 0,
    coefs: [kMaxLpcOrder]i32 = @splat(0),
    shift: u5 = 0,
    bits: u64 = std.math.maxInt(u64),
};

const Encoder = struct {
    /// The four channel candidates: left, right, mid, side.
    chan: [4][kBlock]i32 = undefined,
    res: [kBlock]i64 = undefined,
    win: [kBlock]f64 = undefined,
    win_n: usize = 0,
    wdata: [kBlock]f64 = undefined,

    fn init(alloc: std.mem.Allocator) !*Encoder {
        const e = try alloc.create(Encoder);
        e.* = .{};
        return e;
    }

    fn deinit(self: *Encoder, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn frame(self: *Encoder, alloc: std.mem.Allocator, out: *std.ArrayList(u8), block: []align(1) const i16, nch: usize, number: u32, rate: u32) !void {
        const n = block.len / nch;
        var plans: [4]Plan = undefined;
        const bps: [4]u5 = .{ 16, 16, 16, 17 };
        var assign: u4 = undefined;
        var which: [2]usize = undefined;
        if (nch == 1) {
            for (0..n) |i| self.chan[0][i] = block[i];
            plans[0] = self.plan(self.chan[0][0..n], 16);
            assign = 0;
            which = .{ 0, 0 };
        } else {
            for (0..n) |i| {
                const l: i32 = block[i * 2];
                const r: i32 = block[i * 2 + 1];
                self.chan[0][i] = l;
                self.chan[1][i] = r;
                self.chan[2][i] = (l + r) >> 1;
                self.chan[3][i] = l - r;
            }
            for (0..4) |c| plans[c] = self.plan(self.chan[c][0..n], bps[c]);
            // Left/right, left/side, side/right, mid/side: the cheapest pair.
            const layouts = [_]struct { a: u4, ch: [2]usize }{
                .{ .a = 1, .ch = .{ 0, 1 } },
                .{ .a = 8, .ch = .{ 0, 3 } },
                .{ .a = 9, .ch = .{ 3, 1 } },
                .{ .a = 10, .ch = .{ 2, 3 } },
            };
            var best: u64 = std.math.maxInt(u64);
            for (layouts) |lay| {
                const cost = plans[lay.ch[0]].bits + plans[lay.ch[1]].bits;
                if (cost < best) {
                    best = cost;
                    assign = lay.a;
                    which = lay.ch;
                }
            }
        }

        const start = out.items.len;
        var w = Bits{ .out = out, .alloc = alloc };
        try w.put(0x3ffe, 14);
        try w.put(0, 2); // reserved, fixed block size
        const size_code: u4 = if (n == kBlock) 12 else if (n <= 256) 6 else 7;
        try w.put(size_code, 4);
        try w.put(rateCode(rate), 4);
        try w.put(assign, 4);
        try w.put(4, 3); // 16 bits a sample
        try w.put(0, 1);
        try utf8(&w, number);
        if (size_code == 6) try w.put(n - 1, 8);
        if (size_code == 7) try w.put(n - 1, 16);
        try w.put(crc8(out.items[start..]), 8);

        for (which[0..nch]) |c| try self.subframe(&w, self.chan[c][0..n], bps[c], plans[c]);
        try w.alignByte();
        try w.put(crc16(out.items[start..]), 16);
    }

    /// The cheapest way to code `x`, a channel of `bits`-bit samples.
    fn plan(self: *Encoder, x: []const i32, bits: u5) Plan {
        const n = x.len;
        var best = Plan{ .kind = .verbatim, .bits = @as(u64, n) * bits };
        if (std.mem.allEqual(i32, x, x[0])) return .{ .kind = .constant, .bits = bits };

        for (0..5) |order| {
            if (order >= n) break;
            const p = Plan{ .kind = .fixed, .order = @intCast(order) };
            residual(x, p, &self.res);
            const rb = riceBits(self.res[order..n], n, order) orelse continue;
            const cost = 8 + @as(u64, order) * bits + rb;
            if (cost < best.bits) best = .{ .kind = .fixed, .order = @intCast(order), .bits = cost };
        }

        if (n > kMaxLpcOrder * 2) {
            if (self.lpc(x, bits)) |p| {
                residual(x, p, &self.res);
                if (riceBits(self.res[p.order..n], n, p.order)) |rb| {
                    const cost = 8 + @as(u64, p.order) * (bits + kPrecision) + 9 + rb;
                    if (cost < best.bits) {
                        best = p;
                        best.bits = cost;
                    }
                }
            }
        }
        return best;
    }

    /// An LPC predictor for `x`, at the order its error says is cheapest.
    fn lpc(self: *Encoder, x: []const i32, bits: u5) ?Plan {
        const n = x.len;
        if (self.win_n != n) {
            tukey(self.win[0..n]);
            self.win_n = n;
        }
        for (0..n) |i| self.wdata[i] = @as(f64, @floatFromInt(x[i])) * self.win[i];
        var autoc: [kMaxLpcOrder + 1]f64 = undefined;
        for (0..kMaxLpcOrder + 1) |lag| {
            var s: f64 = 0;
            for (lag..n) |i| s += self.wdata[i] * self.wdata[i - lag];
            autoc[lag] = s;
        }
        if (autoc[0] == 0) return null;

        var coefs: [kMaxLpcOrder][kMaxLpcOrder]f64 = undefined;
        var err: [kMaxLpcOrder]f64 = undefined;
        const max_order = levinson(&autoc, &coefs, &err);
        if (max_order == 0) return null;

        // Bits a residual costs at each order's error, plus what the
        // order's own warm-up and coefficients cost.
        var best_order: usize = 1;
        var best_cost: f64 = std.math.inf(f64);
        const scale = 0.5 / @as(f64, @floatFromInt(n));
        for (0..max_order) |i| {
            const order = i + 1;
            const per = if (err[i] > 0) @max(0.5 * std.math.log2(scale * err[i]), 0) else 0;
            const cost = per * @as(f64, @floatFromInt(n - order)) + @as(f64, @floatFromInt(order * (bits + kPrecision)));
            if (cost < best_cost) {
                best_cost = cost;
                best_order = order;
            }
        }
        var p = Plan{ .kind = .lpc, .order = @intCast(best_order) };
        if (!quantize(coefs[best_order - 1][0..best_order], &p)) return null;
        return p;
    }

    fn subframe(self: *Encoder, w: *Bits, x: []const i32, bits: u5, p: Plan) !void {
        const n = x.len;
        try w.put(0, 1);
        switch (p.kind) {
            .constant => {
                try w.put(0, 6);
                try w.put(0, 1);
                try w.signed(x[0], bits);
            },
            .verbatim => {
                try w.put(1, 6);
                try w.put(0, 1);
                for (x) |s| try w.signed(s, bits);
            },
            .fixed, .lpc => {
                try w.put(if (p.kind == .fixed) 8 + @as(u64, p.order) else 32 + @as(u64, p.order) - 1, 6);
                try w.put(0, 1);
                for (x[0..p.order]) |s| try w.signed(s, bits);
                if (p.kind == .lpc) {
                    try w.put(kPrecision - 1, 4);
                    try w.put(p.shift, 5);
                    for (p.coefs[0..p.order]) |cf| try w.signed(cf, kPrecision);
                }
                residual(x, p, &self.res);
                try writeResidual(w, self.res[p.order..n], n, p.order);
            },
        }
    }
};

fn rateCode(rate: u32) u4 {
    return switch (rate) {
        88200 => 1,
        176400 => 2,
        192000 => 3,
        8000 => 4,
        16000 => 5,
        22050 => 6,
        24000 => 7,
        32000 => 8,
        44100 => 9,
        48000 => 10,
        96000 => 11,
        else => 0, // from STREAMINFO
    };
}

fn utf8(w: *Bits, v: u32) !void {
    if (v < 0x80) return w.put(v, 8);
    const len: u5 = if (v < 0x800) 2 else if (v < 0x10000) 3 else if (v < 0x200000) 4 else if (v < 0x4000000) 5 else 6;
    const lead_mask: u8 = @truncate(@as(u16, 0xff00) >> @intCast(len));
    try w.put(lead_mask | @as(u8, @truncate(v >> (6 * (len - 1)))), 8);
    var i: u5 = len - 1;
    while (i > 0) {
        i -= 1;
        try w.put(0x80 | ((v >> (6 * i)) & 0x3f), 8);
    }
}

/// What's left of `x` after `p` predicts it, from sample `p.order` on.
fn residual(x: []const i32, p: Plan, res: *[kBlock]i64) void {
    const n = x.len;
    const o = p.order;
    switch (p.kind) {
        .fixed => switch (o) {
            0 => for (0..n) |i| {
                res[i] = x[i];
            },
            1 => for (1..n) |i| {
                res[i] = @as(i64, x[i]) - x[i - 1];
            },
            2 => for (2..n) |i| {
                res[i] = @as(i64, x[i]) - 2 * @as(i64, x[i - 1]) + x[i - 2];
            },
            3 => for (3..n) |i| {
                res[i] = @as(i64, x[i]) - 3 * @as(i64, x[i - 1]) + 3 * @as(i64, x[i - 2]) - x[i - 3];
            },
            else => for (4..n) |i| {
                res[i] = @as(i64, x[i]) - 4 * @as(i64, x[i - 1]) + 6 * @as(i64, x[i - 2]) - 4 * @as(i64, x[i - 3]) + x[i - 4];
            },
        },
        .lpc => for (o..n) |i| {
            var sum: i64 = 0;
            for (0..o) |j| sum += @as(i64, p.coefs[j]) * x[i - j - 1];
            res[i] = @as(i64, x[i]) - (sum >> p.shift);
        },
        else => unreachable,
    }
}

/// The Rice partitioning `res` (a block of `n` less its first `order`
/// samples) codes smallest at, as a partition order and a parameter each.
const Partitioning = struct {
    order: u4 = 0,
    wide: bool = false,
    params: [1 << kMaxPartitionOrder]u5 = undefined,
    bits: u64 = std.math.maxInt(u64),
};

fn partition(res: []const i64, n: usize, order: usize) ?Partitioning {
    // The deepest the block divides into, then each shallower level made by
    // adding pairs, so the samples are only summed once.
    var top: u4 = 0;
    while (top < kMaxPartitionOrder and n % (@as(usize, 2) << top) == 0 and (n >> (top + 1)) > order) top += 1;
    var sums: [1 << kMaxPartitionOrder]u64 = undefined;
    const parts_top = @as(usize, 1) << top;
    const len_top = n >> top;
    var i: usize = 0;
    for (0..parts_top) |p| {
        const end = (p + 1) * len_top - order;
        var s: u64 = 0;
        while (i < end) : (i += 1) {
            const r = res[i];
            if (r >= 1 << 30 or r <= -(1 << 30)) return null;
            s += fold(r);
        }
        sums[p] = s;
    }

    var best = Partitioning{};
    var po: i8 = top;
    while (po >= 0) : (po -= 1) {
        const parts = @as(usize, 1) << @intCast(po);
        const len = n >> @intCast(po);
        var cur = Partitioning{ .order = @intCast(po), .bits = 6 };
        var wide = false;
        for (0..parts) |p| {
            const cnt: u64 = if (p == 0) len - order else len;
            const k = bestK(sums[p], cnt);
            if (k > 14) wide = true;
            cur.params[p] = k;
            cur.bits += cnt * (@as(u64, k) + 1) + (sums[p] >> k);
        }
        cur.wide = wide;
        cur.bits += parts * @as(u64, if (wide) 5 else 4);
        if (cur.bits < best.bits) best = cur;
        // One level up: each partition is two of this one's.
        if (po > 0) {
            for (0..parts / 2) |p| sums[p] = sums[2 * p] + sums[2 * p + 1];
        }
    }
    return best;
}

fn bestK(sum: u64, cnt: u64) u5 {
    if (cnt == 0) return 0;
    var best: u5 = 0;
    var best_bits: u64 = std.math.maxInt(u64);
    var k: u5 = 0;
    while (k <= 30) : (k += 1) {
        const b = cnt * (@as(u64, k) + 1) + (sum >> k);
        if (b < best_bits) {
            best_bits = b;
            best = k;
        } else break;
    }
    return best;
}

fn riceBits(res: []const i64, n: usize, order: usize) ?u64 {
    const p = partition(res, n, order) orelse return null;
    return p.bits;
}

fn writeResidual(w: *Bits, res: []const i64, n: usize, order: usize) !void {
    const p = partition(res, n, order).?;
    try w.put(@intFromBool(p.wide), 2);
    try w.put(p.order, 4);
    const parts = @as(usize, 1) << p.order;
    const len = n >> p.order;
    var i: usize = 0;
    for (0..parts) |part| {
        const k = p.params[part];
        try w.put(k, if (p.wide) 5 else 4);
        const end = (part + 1) * len - order;
        while (i < end) : (i += 1) try w.rice(res[i], k);
    }
}

fn tukey(win: []f64) void {
    const n = win.len;
    const alpha = 0.5;
    const nm1: f64 = @floatFromInt(n - 1);
    const edge = alpha * nm1 / 2;
    for (win, 0..) |*v, i| {
        const fi: f64 = @floatFromInt(i);
        v.* = if (fi < edge)
            0.5 * (1 - @cos(std.math.pi * fi / edge))
        else if (fi > nm1 - edge)
            0.5 * (1 - @cos(std.math.pi * (nm1 - fi) / edge))
        else
            1;
    }
}

/// Levinson-Durbin, as libFLAC does it: the predictor at every order up to
/// kMaxLpcOrder, and its error. Returns how many orders it got to.
fn levinson(autoc: *const [kMaxLpcOrder + 1]f64, out: *[kMaxLpcOrder][kMaxLpcOrder]f64, err_out: *[kMaxLpcOrder]f64) usize {
    var lpc: [kMaxLpcOrder]f64 = @splat(0);
    var err = autoc[0];
    for (0..kMaxLpcOrder) |i| {
        var r = -autoc[i + 1];
        for (0..i) |j| r -= lpc[j] * autoc[i - j];
        r /= err;
        lpc[i] = r;
        var j: usize = 0;
        while (j < i / 2) : (j += 1) {
            const tmp = lpc[j];
            lpc[j] += r * lpc[i - 1 - j];
            lpc[i - 1 - j] += r * tmp;
        }
        if (i & 1 != 0) lpc[j] += lpc[j] * r;
        err *= 1.0 - r * r;
        for (0..i + 1) |k| out[i][k] = -lpc[k];
        err_out[i] = err;
        if (!(err > 0)) return i + 1;
    }
    return kMaxLpcOrder;
}

/// `coefs` as kPrecision-bit integers and a shift, carrying each one's
/// rounding into the next. False when they're too big to fit.
fn quantize(coefs: []const f64, p: *Plan) bool {
    var cmax: f64 = 0;
    for (coefs) |cf| {
        if (!std.math.isFinite(cf)) return false;
        cmax = @max(cmax, @abs(cf));
    }
    if (cmax <= 0) return false;
    const log2cmax = std.math.frexp(cmax).exponent;
    const shift = (kPrecision - 1) - log2cmax;
    if (shift < 0) return false;
    p.shift = @intCast(@min(shift, 15));
    const qmax: f64 = (1 << (kPrecision - 1)) - 1;
    const qmin: f64 = -(1 << (kPrecision - 1));
    const mult: f64 = @floatFromInt(@as(u32, 1) << p.shift);
    var carry: f64 = 0;
    for (coefs, 0..) |cf, i| {
        carry += cf * mult;
        const q = std.math.clamp(@round(carry), qmin, qmax);
        p.coefs[i] = @intFromFloat(q);
        carry -= q;
    }
    return true;
}

fn crc8(data: []const u8) u8 {
    var crc: u8 = 0;
    for (data) |b| {
        crc ^= b;
        for (0..8) |_| crc = if (crc & 0x80 != 0) (crc << 1) ^ 0x07 else crc << 1;
    }
    return crc;
}

fn crc16(data: []const u8) u16 {
    var crc: u16 = 0;
    for (data) |b| {
        crc ^= @as(u16, b) << 8;
        for (0..8) |_| crc = if (crc & 0x8000 != 0) (crc << 1) ^ 0x8005 else crc << 1;
    }
    return crc;
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

test "frame numbers are written the way FLAC spells them" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    var w = Bits{ .out = &out, .alloc = testing.allocator };
    try utf8(&w, 0x7f);
    try utf8(&w, 0x80);
    try utf8(&w, 0x1234);
    try testing.expectEqualSlices(u8, &.{ 0x7f, 0xc2, 0x80, 0xe1, 0x88, 0xb4 }, out.items);
}

test "the header checks are FLAC's" {
    // The CRC-8 and CRC-16 check values for "123456789".
    try testing.expectEqual(@as(u8, 0xf4), crc8("123456789"));
    try testing.expectEqual(@as(u16, 0xfee8), crc16("123456789"));
}

test "Rice folding interleaves signs" {
    try testing.expectEqual(@as(u64, 0), fold(0));
    try testing.expectEqual(@as(u64, 1), fold(-1));
    try testing.expectEqual(@as(u64, 2), fold(1));
    try testing.expectEqual(@as(u64, 3), fold(-2));
}
