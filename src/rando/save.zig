//! The seed travels with the save file. A randomized file says so in its own
//! save block, so copying a file copies its seed and erasing it erases the
//! seed, and loading a file is all it takes to switch randomized play on or
//! off (game.zig makes the placement again from the seed).
//!
//! Where it goes: the 13 bytes at 0x4f1 to 0x4fd, just short of the checksum
//! word at 0x4fe. The game never touches them: its last save bytes before the
//! checksum are the death counters, which end at 0x406, and it only ever
//! zeroes, copies and checksums the rest of the block whole. The randomizer
//! ROMs (z3randomizer's sram.asm) leave these 13 bytes unused too, so the
//! item tracker, which reads their layout from 0x400 on, never sees them.
//!
//!   0x4f1 'R'
//!   0x4f2 'X'   the marker: this file is randomized
//!   0x4f3       the format version, kVersion
//!   0x4f4       the seed, a u64, little-endian (8 bytes)
//!   0x4fc       settings, two bytes, zero for now
//!
//! The seed is a u64 because that's what the generator takes, so every seed
//! there is fits, and one typed in is the one played. There's room for it.
//! The version says which placement a seed makes: when the fill changes in a
//! way that puts things elsewhere for the same seed, the version goes up and
//! an older file can be told apart instead of quietly getting a different
//! world.
const std = @import("std");
const game = @import("game.zig");
const open_mode = @import("open_mode.zig");

pub const kOffset = 0x4f1;
pub const kMagic = [2]u8{ 'R', 'X' };
pub const kVersion: u8 = 1;
const kVersionAt = kOffset + 2;
const kSeedAt = kOffset + 3;
const kSettingsAt = kOffset + 11;
/// One past the last byte this uses, which is where the checksum starts.
pub const kEnd = kOffset + 13;

comptime {
    std.debug.assert(kEnd == 0x4fe);
}

/// What a randomized file's block says about it.
pub const Info = struct {
    version: u8 = kVersion,
    seed: u64,
    settings: [2]u8 = .{ 0, 0 },
};

/// The seed for the next new file made at the file select, when a
/// randomized game has been asked for. Taken by the first new file.
pub var pending_seed: ?u64 = null;

/// What `block` (a save block, 0x500 bytes from $7EF000) says, or null when
/// it isn't a randomized file.
pub fn read(block: []const u8) ?Info {
    if (block[kOffset] != kMagic[0] or block[kOffset + 1] != kMagic[1]) return null;
    return .{
        .version = block[kVersionAt],
        .seed = std.mem.readInt(u64, block[kSeedAt..][0..8], .little),
        .settings = block[kSettingsAt..][0..2].*,
    };
}

/// Marks `block` as a randomized file of `info`'s seed. The checksum is the
/// caller's to fix.
pub fn write(block: []u8, info: Info) void {
    block[kOffset] = kMagic[0];
    block[kOffset + 1] = kMagic[1];
    block[kVersionAt] = info.version;
    std.mem.writeInt(u64, block[kSeedAt..][0..8], info.seed, .little);
    block[kSettingsAt..][0..2].* = info.settings;
}

/// Makes `block` an ordinary file again.
pub fn clear(block: []u8) void {
    @memset(block[kOffset..kEnd], 0);
}

/// A seed as typed: a number, or "random" for one picked now.
pub fn parseSeed(text: []const u8) ?u64 {
    if (std.ascii.eqlIgnoreCase(text, "random")) {
        var b: [8]u8 = undefined;
        std.Io.Threaded.global_single_threaded.io().random(&b);
        return std.mem.readInt(u64, &b, .little);
    }
    return std.fmt.parseInt(u64, text, 10) catch null;
}

/// For a new file just named, in `block`: when a randomized game was asked
/// for, marks the file with the pending seed (which is used up), sets it up
/// for Open mode and makes that seed the one being played. The caller fixes
/// the checksum after. False, and the file left as the game made it, when
/// nothing was pending or the seed won't fill.
pub fn setUpNewFile(block: []u8) bool {
    const s = pending_seed orelse return false;
    pending_seed = null;
    if (!startSeed(s)) {
        std.debug.print("Randomizer: seed {d} would not fill; this file is an ordinary one\n", .{s});
        return false;
    }
    write(block, .{ .seed = s });
    open_mode.applyNewFile(block);
    return true;
}

/// What loading a file did to randomized play.
pub const Sync = enum {
    /// An ordinary file, and none was being played.
    ordinary,
    /// An ordinary file after a randomized one: randomized play is off.
    stopped,
    /// The seed already being played.
    same_seed,
    /// A randomized file, whose seed is now the one being played.
    started,
    /// A randomized file this can't play (another format, or a seed that
    /// won't fill): it plays as the ordinary game.
    unplayable,
};

/// Switches randomized play to match the file in `block`, just loaded:
/// on with its seed if it's a randomized file, off if it isn't.
pub fn syncWithFile(block: []const u8) Sync {
    const info = read(block) orelse {
        const was = game.active();
        game.stop();
        return if (was) .stopped else .ordinary;
    };
    if (info.version != kVersion) {
        game.stop();
        return .unplayable;
    }
    if (game.active() and game.seed() == info.seed) return .same_seed;
    return if (startSeed(info.seed)) .started else blk: {
        game.stop();
        break :blk .unplayable;
    };
}

fn startSeed(s: u64) bool {
    if (game.active() and game.seed() == s) return true;
    return game.start(s, .{});
}

const testing = std.testing;

test "a block reads back what was written, and an ordinary one reads as none" {
    var block: [0x500]u8 = @splat(0);
    try testing.expectEqual(@as(?Info, null), read(&block));

    write(&block, .{ .seed = 0x0123_4567_89ab_cdef, .settings = .{ 5, 6 } });
    const info = read(&block).?;
    try testing.expectEqual(kVersion, info.version);
    try testing.expectEqual(@as(u64, 0x0123_4567_89ab_cdef), info.seed);
    try testing.expectEqual([2]u8{ 5, 6 }, info.settings);
    // Little-endian, at the documented place.
    try testing.expectEqual(@as(u8, 'R'), block[0x4f1]);
    try testing.expectEqual(@as(u8, 0xef), block[0x4f4]);
    try testing.expectEqual(@as(u8, 0x01), block[0x4fb]);

    clear(&block);
    try testing.expectEqual(@as(?Info, null), read(&block));
}

test "the marker stays out of the game's bytes and the checksum" {
    var block: [0x500]u8 = @splat(0xcc);
    write(&block, .{ .seed = std.math.maxInt(u64), .settings = .{ 0xff, 0xff } });
    for (block[0..kOffset]) |b| try testing.expectEqual(@as(u8, 0xcc), b);
    for (block[kEnd..]) |b| try testing.expectEqual(@as(u8, 0xcc), b);
    clear(&block);
    for (block[kOffset..kEnd]) |b| try testing.expectEqual(@as(u8, 0), b);
}

test "seeds parse as numbers or random" {
    try testing.expectEqual(@as(?u64, 42), parseSeed("42"));
    try testing.expectEqual(@as(?u64, std.math.maxInt(u64)), parseSeed("18446744073709551615"));
    try testing.expectEqual(@as(?u64, null), parseSeed("-1"));
    try testing.expectEqual(@as(?u64, null), parseSeed("seed"));
    try testing.expect(parseSeed("random") != null);
    try testing.expect(parseSeed("Random") != null);
}

test "a new file takes the pending seed once, and loading switches play on and off" {
    defer game.stop();
    var rando_file: [0x500]u8 = @splat(0);
    var plain_file: [0x500]u8 = @splat(0);

    // Nothing pending: the new file stays ordinary.
    pending_seed = null;
    try testing.expect(!setUpNewFile(&plain_file));
    try testing.expectEqual(@as(?Info, null), read(&plain_file));

    pending_seed = 7;
    try testing.expect(setUpNewFile(&rando_file));
    try testing.expectEqual(@as(?u64, null), pending_seed);
    try testing.expectEqual(@as(u64, 7), read(&rando_file).?.seed);
    try testing.expect(game.active());
    try testing.expectEqual(@as(u64, 7), game.seed());

    // The next new file isn't randomized: the seed was used up.
    var next_file: [0x500]u8 = @splat(0);
    try testing.expect(!setUpNewFile(&next_file));

    try testing.expectEqual(Sync.same_seed, syncWithFile(&rando_file));
    try testing.expectEqual(Sync.stopped, syncWithFile(&plain_file));
    try testing.expect(!game.active());
    try testing.expectEqual(Sync.ordinary, syncWithFile(&plain_file));
    try testing.expectEqual(Sync.started, syncWithFile(&rando_file));
    try testing.expect(game.active());
    try testing.expectEqual(@as(u64, 7), game.seed());

    // A copy of the file is the same seed.
    var copy = rando_file;
    try testing.expectEqual(Sync.same_seed, syncWithFile(&copy));

    // A file from a format this doesn't know plays as nothing at all.
    var future = rando_file;
    future[kVersionAt] = kVersion + 1;
    try testing.expectEqual(Sync.unplayable, syncWithFile(&future));
    try testing.expect(!game.active());
}
