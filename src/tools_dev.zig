//! Two tools for working on the game rather than playing it, formerly
//! Python scripts in other/: reading the input log out of a snapshot, and
//! searching the dialogue for a better compression dictionary.
const std = @import("std");

// -------------------------------------------------------------- input log

/// Prints a snapshot's input log, one line per change: the frame, then the
/// buttons held from then on, or the address of a RAM patch.
///
/// The log sits after a 32-byte header. Each record is a command byte whose
/// low bits count frames since the last one (all ones means more counts
/// follow, 255 meaning keep going), then either a button toggled or a patch.
pub fn inputLog(data: []const u8, out: *std.Io.Writer) !void {
    if (data.len < 32) return error.NotASnapshot;
    const log_size = std.mem.readInt(u32, data[8..12], .little);
    var inputs = std.mem.readInt(u32, data[12..16], .little);
    const log = data[32..@min(data.len, 32 + @as(usize, log_size))];

    const keys = "AXsSUDLRBY";
    var frame: u64 = 0;
    var i: usize = 0;
    // Running out part way through a record just ends the listing.
    while (i < log.len) {
        const cmd = log[i];
        i += 1;
        const mask: u8 = if (cmd < 0xc0) 0xf else 1;
        var frames: u64 = cmd & mask;
        if (frames == mask) {
            while (true) {
                if (i >= log.len) return;
                const t = log[i];
                i += 1;
                frames += t;
                if (t != 255) break;
            }
        }
        frame += frames;
        if (cmd < 0xc0) {
            inputs ^= @as(u32, 1) << @intCast(cmd >> 4);
            try out.print("{d}: ", .{frame});
            for (keys, 0..) |k, j| {
                if (inputs & (@as(u32, 1) << @intCast(j)) != 0) try out.writeByte(k);
            }
            try out.writeByte('\n');
        } else if (cmd < 0xd0) {
            const count = 1 + ((cmd >> 2) & 3);
            if (i + 2 > log.len) return;
            const addr = @as(u32, (cmd >> 1) & 1) << 16 | @as(u32, log[i]) << 8 | log[i + 1];
            i += 2;
            if (i + count > log.len) return;
            i += count;
            try out.print("{d}: patchbytes(0x{x})\n", .{ frame, addr });
        } else return error.BadLog;
    }
}

// ------------------------------------------------------ dictionary search

/// Looks for the dictionary that would compress `dialogue` (dialogue.txt)
/// best: over and over, the repeated run of characters and commands whose
/// replacement saves the most bytes is replaced by one symbol and reported.
/// The first 111 picks cost one byte each and the rest two. Then prints
/// every message with the picks marked {like this}.
pub fn textDict(alloc: std.mem.Allocator, dialogue: []const u8, out: *std.Io.Writer) !void {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    var t = Tokens{ .a = a };
    var lines: std.ArrayList(std.ArrayList(u16)) = .empty;
    var it = std.mem.splitScalar(u8, dialogue, '\n');
    while (it.next()) |raw| {
        const whole = std.mem.trimEnd(u8, raw, "\r");
        if (whole.len == 0 and it.peek() == null) break;
        // The text is what's after the first ": " and before any second one.
        var parts = std.mem.splitSequence(u8, whole, ": ");
        _ = parts.next();
        const line = parts.next() orelse return error.BadDialogue;
        var ids: std.ArrayList(u16) = .empty;
        var i: usize = 0;
        while (i < line.len) {
            var n: usize = undefined;
            if (line[i] == '[') {
                const close = std.mem.indexOfScalarPos(u8, line, i + 1, ']') orelse return error.BadDialogue;
                n = close + 1 - i;
            } else {
                n = std.unicode.utf8ByteSequenceLength(line[i]) catch 1;
                n = @min(n, line.len - i);
            }
            try ids.append(a, try t.id(line[i .. i + n]));
            i += n;
        }
        try lines.append(a, ids);
    }

    var original: usize = 0;
    for (lines.items) |l| original += l.items.len;

    var total: i64 = 0;
    for (0..111 + 256) |round| {
        const cost: i64 = if (round < 111) 1 else 2;
        const best = try bestNgram(a, lines.items, cost) orelse break;
        total += best.score;
        const text = try t.join(best.ngram);
        try out.print("Removed best bigram \"{s}\" with gain {d}, total gain {d} / {d}\n", .{ text, best.score, total, original });
        const symbol = try t.id(try std.fmt.allocPrint(a, "{{{s}}}", .{text}));
        replaceAll(lines.items, best.ngram, symbol);
    }

    for (lines.items, 0..) |l, i| try out.print("{d} {s}\n", .{ i, try t.join(l.items) });
}

/// Each distinct token gets a number, in the order they turn up.
const Tokens = struct {
    a: std.mem.Allocator,
    ids: std.StringHashMapUnmanaged(u16) = .empty,
    list: std.ArrayList([]const u8) = .empty,

    fn id(self: *Tokens, s: []const u8) !u16 {
        if (self.ids.get(s)) |v| return v;
        const v: u16 = @intCast(self.list.items.len);
        try self.list.append(self.a, s);
        try self.ids.put(self.a, s, v);
        return v;
    }

    fn join(self: *Tokens, ids: []const u16) ![]u8 {
        var s: std.ArrayList(u8) = .empty;
        for (ids) |i| try s.appendSlice(self.a, self.list.items[i]);
        return s.items;
    }
};

const Best = struct { ngram: []const u16, score: i64 };

/// The best run of each length from 2 to 31 is the most repeated one (ties
/// going to the higher token numbers), scored by the bytes replacing it
/// saves; the best of those wins, the shorter on a tie. Runs starting with a
/// token repeated are skipped. Null when nothing saves anything.
fn bestNgram(a: std.mem.Allocator, lines: []const std.ArrayList(u16), cost: i64) !?Best {
    var best: ?Best = null;
    for (2..32) |n| {
        var counts: std.HashMapUnmanaged([]const u16, u32, SliceContext, 80) = .empty;
        defer counts.deinit(a);
        for (lines) |l| {
            const items = l.items;
            if (items.len < n) continue;
            for (0..items.len - n + 1) |i| {
                if (items[i] == items[i + 1]) continue;
                const gop = try counts.getOrPut(a, items[i .. i + n]);
                if (!gop.found_existing) gop.value_ptr.* = 0;
                gop.value_ptr.* += 1;
            }
        }
        var top: ?[]const u16 = null;
        var top_count: u32 = 0;
        var cit = counts.iterator();
        while (cit.next()) |e| {
            const c = e.value_ptr.*;
            if (c < 2) continue;
            if (top == null or c > top_count or (c == top_count and std.mem.order(u16, e.key_ptr.*, top.?) == .gt)) {
                top = e.key_ptr.*;
                top_count = c;
            }
        }
        const ngram = top orelse continue;
        const len: i64 = @intCast(n);
        const score = (len - cost) * top_count - len - 2; // 2 for the dictionary entry
        if (score > (if (best) |b| b.score else 0)) best = .{ .ngram = try a.dupe(u16, ngram), .score = score };
    }
    return best;
}

const SliceContext = struct {
    pub fn hash(_: SliceContext, k: []const u16) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(k));
    }
    pub fn eql(_: SliceContext, x: []const u16, y: []const u16) bool {
        return std.mem.eql(u16, x, y);
    }
};

/// Replaces every run of `from` with `to`, left to right. Like the old Python
/// it came from, it walks as many positions as the line had before any
/// replacing, so a match that shifts in from past that point stays.
fn replaceAll(lines: []std.ArrayList(u16), from: []const u16, to: u16) void {
    for (lines) |*l| {
        if (l.items.len < from.len) continue;
        const positions = l.items.len - from.len + 1;
        for (0..positions) |i| {
            if (i + from.len > l.items.len) continue;
            if (!std.mem.eql(u16, l.items[i .. i + from.len], from)) continue;
            l.items[i] = to;
            std.mem.copyForwards(u16, l.items[i + 1 ..], l.items[i + from.len ..]);
            l.shrinkRetainingCapacity(l.items.len - (from.len - 1));
        }
    }
}

test "an input log lists button changes and patches" {
    var data: [40]u8 = @splat(0);
    std.mem.writeInt(u32, data[8..12], 6, .little);
    // Press A (bit 0) 3 frames in, B (bit 8) 2 later, then a patch at
    // 0x1234 of one byte.
    data[32..40].* = .{ 0x03, 0x82, 0xc0, 0x12, 0x34, 0xaa, 0, 0 };
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try inputLog(&data, &w);
    try std.testing.expectEqualStrings("3: A\n5: AB\n5: patchbytes(0x1234)\n", w.buffered());
}
