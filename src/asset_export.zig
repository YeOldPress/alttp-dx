//! Writing the ROM's data out as files people can edit: the overworld areas
//! and dungeon rooms as YAML, the map32 table and the dialogue as text.
//!
//! Each file is exactly what assets/extract_resources.py wrote, byte for
//! byte, so mods made against those files keep working and asset_import can
//! read either. The functions here follow the Python's one for one, down to
//! the order keys appear in, because that order is what's in the files.
const std = @import("std");
const rom_mod = @import("rom.zig");
const yaml = @import("yaml.zig");
const names = @import("asset_names.zig");
const dialogue = @import("asset_dialogue.zig");
const music_export = @import("asset_music_export.zig");
const fileio = @import("fileio.zig");
const graphics = @import("asset_graphics.zig");
const sheets = @import("asset_sprite_sheets.zig");

const Rom = rom_mod.Rom;
const Value = yaml.Value;
const Pair = yaml.Pair;

/// Builds Values in an arena. Every export works in one and throws it away.
const B = struct {
    a: std.mem.Allocator,

    fn int(_: B, v: anytype) Value {
        return .{ .int = @intCast(v) };
    }
    fn str(_: B, s: []const u8) Value {
        return .{ .str = s };
    }
    fn list(self: B, items: []const Value) Value {
        return .{ .list = self.a.dupe(Value, items) catch @panic("out of memory") };
    }
    fn ints(self: B, vs: anytype) Value {
        var out = self.a.alloc(Value, vs.len) catch @panic("out of memory");
        inline for (0..vs.len) |i| out[i] = .{ .int = @intCast(vs[i]) };
        return .{ .list = out };
    }
    fn fmt(self: B, comptime f: []const u8, args: anytype) Value {
        return .{ .str = std.fmt.allocPrint(self.a, f, args) catch @panic("out of memory") };
    }
};

/// An ordered map under construction.
const M = struct {
    b: B,
    pairs: std.ArrayList(Pair) = .empty,

    fn put(self: *M, key: []const u8, v: Value) void {
        self.pairs.append(self.b.a, .{ .key = key, .value = v }) catch @panic("out of memory");
    }
    fn done(self: *M) Value {
        return .{ .map = self.pairs.items };
    }
};

/// A growing list under construction.
const L = struct {
    b: B,
    items: std.ArrayList(Value) = .empty,

    fn add(self: *L, v: Value) void {
        self.items.append(self.b.a, v) catch @panic("out of memory");
    }
    fn done(self: *L) Value {
        return .{ .list = self.items.items };
    }
};

fn int8(v: u8) i64 {
    return @as(i8, @bitCast(v));
}
fn int16(v: u16) i64 {
    return @as(i16, @bitCast(v));
}

fn namedLookup(table: []const names.Named, id: u16) []const u8 {
    for (table) |n| if (n.id == id) return n.name;
    return "?";
}

// ------------------------------------------------------------- overworld

/// Areas that start their own screen: every area from 128 up, and below
/// that the ones that aren't the other quarters of a big area.
pub fn isAreaHead(rom: Rom, i: usize) bool {
    return i >= 128 or rom.getByte(0x82A5EC + @as(u32, @intCast(i & 63))) == (i & 63);
}

fn exitsFor(b: B, rom: Rom, area: usize) Value {
    var out = L{ .b = b };
    for (0..79) |i_| {
        const i: u32 = @intCast(i_);
        const screen_index = rom.getByte(0x82DE28 + i);
        if (screen_index != area) continue;
        const room = rom.getWord(0x82dd8a + i * 2);
        const load_offs: i64 = rom.getWord(0x82DE77 + i * 2);
        const base_x: i64 = @as(i64, screen_index & 7) << 9;
        const base_y: i64 = @as(i64, screen_index & 56) << 6;
        const scroll = [2]i64{ @as(i64, rom.getWord(0x82DFB3 + i * 2)) - base_x, @as(i64, rom.getWord(0x82DF15 + i * 2)) - base_y };
        var y = M{ .b = b };
        y.put("index", b.int(i));
        y.put("room", b.int(room));
        y.put("xy", b.ints(.{ @as(i64, rom.getWord(0x82E0EF + i * 2)) - base_x, @as(i64, rom.getWord(0x82E051 + i * 2)) - base_y }));
        y.put("scroll_xy", b.ints(scroll));
        y.put("camera_xy", b.ints(.{ @as(i64, rom.getWord(0x82E22B + i * 2)) - base_x, @as(i64, rom.getWord(0x82E18D + i * 2)) - base_y }));
        y.put("load_xy", b.ints(.{ ((load_offs >> 1) - (scroll[0] >> 4)) & 0x3f, ((load_offs >> 7) - (scroll[1] >> 4)) & 0x3f }));
        y.put("unk", b.ints(.{ int8(rom.getByte(0x82E2C9 + i)), int8(rom.getByte(0x82E318 + i)) }));
        if (room >= 0x180 and room < 0x190) {
            const r: u32 = room - 0x180;
            var se = M{ .b = b };
            se.put("dir", b.int(rom.getByte(0x82E801 + r) >> 1));
            se.put("spr_gfx", b.int(rom.getByte(0x82E811 + r)));
            se.put("aux_gfx", b.int(rom.getByte(0x82E821 + r)));
            se.put("pal_bg", b.int(rom.getByte(0x82E831 + r)));
            se.put("pal_spr", b.int(rom.getByte(0x82E841 + r)));
            se.put("top", b.int(rom.getWord(0x82e6e1 + r * 2)));
            se.put("bottom", b.int(rom.getWord(0x82e701 + r * 2)));
            se.put("left", b.int(rom.getWord(0x82e721 + r * 2)));
            se.put("right", b.int(rom.getWord(0x82e741 + r * 2)));
            se.put("left_edge_of_map", b.int(rom.getWord(0x82E7E1 + r * 2)));
            se.put("unk4", b.int(int16(rom.getWord(0x82e761 + r * 2))));
            se.put("unk6", b.int(int16(rom.getWord(0x82e781 + r * 2))));
            se.put("unk5", b.int(int16(rom.getWord(0x82e7a1 + r * 2))));
            se.put("unk7", b.int(int16(rom.getWord(0x82e7c1 + r * 2))));
            y.put("special_exit", se.done());
        }
        const ndoor = rom.getWord(0x82E367 + i * 2);
        const fdoor = rom.getWord(0x82E405 + i * 2);
        if (ndoor != 0) y.put("door", doorValue(b, if (ndoor & 0x8000 != 0) "bombable" else "wooden", ndoor));
        if (fdoor != 0) y.put("door", doorValue(b, if (fdoor & 0x8000 != 0) "palace" else "sanctuary", fdoor));
        out.add(y.done());
    }
    return out.done();
}

fn doorValue(b: B, kind: []const u8, v: u16) Value {
    return b.list(&.{ b.str(kind), b.int((v & 0x7e) >> 1), b.int((v & 0x3f80) >> 7) });
}

fn travelFor(b: B, rom: Rom, area: usize) Value {
    var out = L{ .b = b };
    for (0..17) |i_| {
        const i: u32 = @intCast(i_);
        const screen_index = rom.getWord(0x82EAE5 + i * 2);
        if (screen_index != area) continue;
        const load_offs: i64 = rom.getWord(0x82EB07 + i * 2);
        const base_x: i64 = @as(i64, screen_index & 7) << 9;
        const base_y: i64 = @as(i64, screen_index & 56) << 6;
        const scroll = [2]i64{ @as(i64, rom.getWord(0x82EB4B + i * 2)) - base_x, @as(i64, rom.getWord(0x82EB29 + i * 2)) - base_y };
        var y = M{ .b = b };
        if (i < 9) {
            y.put("bird_travel_id", b.int(i));
        } else {
            y.put("whirlpool_src_area", b.int(rom.getWord(0x82ECF8 + (i - 9) * 2)));
        }
        y.put("xy", b.ints(.{ @as(i64, rom.getWord(0x82EB8F + i * 2)) - base_x, @as(i64, rom.getWord(0x82EB6D + i * 2)) - base_y }));
        y.put("scroll_xy", b.ints(scroll));
        y.put("camera_xy", b.ints(.{ @as(i64, rom.getWord(0x82EBD3 + i * 2)) - base_x, @as(i64, rom.getWord(0x82EBB1 + i * 2)) - base_y }));
        y.put("load_xy", b.ints(.{ ((load_offs >> 1) - (scroll[0] >> 4)) & 0x3f, ((load_offs >> 7) - (scroll[1] >> 4)) & 0x3f }));
        y.put("unk", b.ints(.{ int8(rom.getByte(0x82EBF5 + i * 2)), int8(rom.getByte(0x82EC17 + i * 2)) }));
        out.add(y.done());
    }
    return out.done();
}

fn overworldArea(b: B, rom: Rom, area: usize) Value {
    const a: u32 = @intCast(area);
    var y = M{ .b = b };

    var header = M{ .b = b };
    header.put("name", b.str(names.kAreaNames[area]));
    header.put("size", b.str(if (rom.getByte(0x82F88D + a) != 0) "small" else "big"));
    header.put("gfx", b.int(if (area < 128) @as(i64, rom.getByte(0x80FC9C + a)) else -1));
    header.put("palette", b.int(if (area < 136) @as(i64, rom.getByte(0x80FD1C + a)) else -1));
    header.put("sign_text", b.int(if (area < 128) @as(i64, rom.getWord(0x87F51D + a * 2)) else -1));
    inline for (.{ "music", "ambient" }) |which| {
        const ambient = comptime std.mem.eql(u8, which, "ambient");
        var m = M{ .b = b };
        const tags = [_][]const u8{ "beginning", "zelda", "sword", "agahnim" };
        if (area < 64) {
            for (tags, 0..) |tag, k| m.put(tag, musicName(b, rom.getByte(0x82C303 + a + @as(u32, @intCast(k)) * 64), ambient));
        } else {
            m.put("agahnim", musicName(b, rom.getByte(0x82C403 + a - 64), ambient));
        }
        header.put(which, m.done());
    }
    y.put("Header", header.done());
    y.put("Travel", travelFor(b, rom, area));

    var entrances = L{ .b = b };
    for (0..129) |i_| {
        const i: u32 = @intCast(i_);
        if (rom.getWord(0x9BB96F + i * 2) != area) continue;
        const pos = rom.getWord(0x9BBA71 + i * 2);
        var e = M{ .b = b };
        e.put("index", b.int(i));
        e.put("x", b.int((pos >> 1) & 0x3f));
        e.put("y", b.int((pos >> 7) & 0x3f));
        e.put("entrance_id", b.int(rom.getByte(0x9BBB73 + i)));
        entrances.add(e.done());
    }
    y.put("Entrances", entrances.done());

    var holes = L{ .b = b };
    for (0..19) |i_| {
        const i: u32 = @intCast(i_);
        if (rom.getWord(0x9BB826 + i * 2) != area) continue;
        const pos = rom.getWord(0x9BB800 + i * 2) +% 0x400;
        var e = M{ .b = b };
        e.put("x", b.int((pos >> 1) & 0x3f));
        e.put("y", b.int((pos >> 7) & 0x3f));
        e.put("entrance_id", b.int(rom.getByte(0x9BB84C + i)));
        holes.add(e.done());
    }
    if (holes.items.items.len != 0) y.put("Holes", holes.done());

    y.put("Exits", exitsFor(b, rom, area));

    var items = L{ .b = b };
    if (area < 128) {
        var ea: u32 = 0x9b0000 | @as(u32, rom.getWord(0x9BC2F9 + a * 2));
        while (rom.getWord(ea) != 0xffff) : (ea += 3) {
            const pos = rom.getWord(ea) / 2;
            items.add(b.list(&.{ b.int(pos % 64), b.int(pos / 64), b.str(namedLookup(&names.kSecretNames, rom.getByte(ea + 2))) }));
        }
    }
    y.put("Items", items.done());

    if (area < 64) {
        y.put("Sprites.Beginning", spriteStage(b, rom, area, 0, 0x89C881));
        y.put("Sprites.FirstPart", spriteStage(b, rom, area, 1, 0x89C901));
        y.put("Sprites.SecondPart", spriteStage(b, rom, area, 2, 0x89CA21));
    } else if (area < 144) {
        y.put("Sprites", spriteStage(b, rom, area, 2, 0x89CA21));
    }
    return y.done();
}

fn musicName(b: B, x: u8, ambient: bool) Value {
    return b.str(if (ambient) namedLookup(&names.kAmbientSoundNames, x >> 4) else namedLookup(&names.kMusicNames, x & 0xf));
}

fn spriteStage(b: B, rom: Rom, area: usize, stage_in: u32, base: u32) Value {
    const a: u32 = @intCast(area);
    var m = M{ .b = b };
    var info = M{ .b = b };
    if (area < 128) {
        const stage: u32 = if (area >= 64) 3 else stage_in;
        info.put("gfx", b.int(rom.getByte(0x80FA41 + (a & 63) + stage * 64)));
        info.put("palette", b.int(rom.getByte(0x80FB41 + (a & 63) + stage * 64)));
    }
    m.put("info", info.done());
    var sprites = L{ .b = b };
    var ea: u32 = 0x890000 + @as(u32, rom.getWord(base + a * 2));
    while (rom.getByte(ea) != 0xff) : (ea += 3) {
        sprites.add(b.list(&.{ b.int(rom.getByte(ea + 1)), b.int(rom.getByte(ea)), b.str(names.kSpriteNames[rom.getByte(ea + 2)]) }));
    }
    m.put("sprites", sprites.done());
    return m.done();
}

// --------------------------------------------------------------- dungeons

const RoomObjects = struct { next: u32, objs: Value, doors: ?Value };

fn decodeRoomObjects(b: B, rom: Rom, start: u32) RoomObjects {
    var p = start;
    var objs = L{ .b = b };
    while (true) {
        const p0 = rom.getByte(p);
        const p1 = rom.getByte(p + 1);
        const p2 = rom.getByte(p + 2);
        const A = @as(u16, p0) | @as(u16, p1) << 8;
        if (A == 0xffff) return .{ .next = p + 2, .objs = objs.done(), .doors = null };
        if (A == 0xfff0) {
            p += 2;
            break;
        }
        var o = M{ .b = b };
        if (A & 0xfc != 0xfc) {
            const dst = (@as(u16, p1 >> 2) << 7) | ((p0 & 0xfc) >> 1);
            const w = p0 & 3;
            const h = p1 & 3;
            o.put("x", b.int((dst >> 1) & 0x3f));
            o.put("y", b.int((dst >> 7) & 0x3f));
            if (p2 < 0xf8) {
                o.put("s", b.fmt("{d}*{d}", .{ w, h }));
                o.put("n", b.str(names.kType0Names[p2]));
            } else {
                o.put("n", b.str(names.kType1Names[(@as(usize, p2 & 7) << 4) | (@as(usize, h) << 2) | w]));
            }
        } else {
            // Subtype 2: 111111xx xxxxyyyy yyiiiiii
            o.put("x", b.int(((@as(u16, p0) << 4) | (p1 >> 4)) & 0x3f));
            o.put("y", b.int(((@as(u16, p1) << 2) | (p2 >> 6)) & 0x3f));
            o.put("n", b.str(names.kType2Names[p2 & 0x3f]));
        }
        objs.add(o.done());
        p += 3;
    }
    var doors = L{ .b = b };
    while (true) : (p += 2) {
        const A = rom.getWord(p);
        if (A == 0xffff) return .{ .next = p + 2, .objs = objs.done(), .doors = doors.done() };
        var d = M{ .b = b };
        d.put("type", b.int(rom.getByte(p + 1)));
        d.put("pos", b.int(rom.getByte(p) >> 4));
        d.put("dir", b.int(A & 3));
        doors.add(d.done());
    }
}

fn entranceInfo(b: B, rom: Rom, i_: usize, set: u1) struct { room: u16, value: Value } {
    const i: u32 = @intCast(i_);
    const pick = struct {
        fn f(set_: u1, a: u32, c: u32) u32 {
            return if (set_ == 0) a else c;
        }
    }.f;
    const room = rom.getWord(pick(set, 0x82C813, 0x82DB6E) + i * 2);
    const room_x: i64 = @as(i64, room & 0x00f) << 9;
    const room_y: i64 = @as(i64, room & 0x1f0) << 5;
    const player = [2]i64{
        @as(i64, rom.getWord(pick(set, 0x82D063, 0x82DBDE) + i * 2)) - room_x,
        @as(i64, rom.getWord(pick(set, 0x82CF59, 0x82DBD0) + i * 2)) - room_y,
    };
    var y = M{ .b = b };
    if (set == 0) {
        y.put("entrance_index", b.int(i));
        y.put("name", b.str(names.kEntranceNames[i]));
    } else {
        y.put("starting_point_index", b.int(i));
        y.put("name", b.fmt("Starting Location {d}", .{i}));
    }
    y.put("scroll_xy", b.ints(.{
        @as(i64, rom.getWord(pick(set, 0x82CD45, 0x82DBB4) + i * 2)) - room_x,
        @as(i64, rom.getWord(pick(set, 0x82CE4F, 0x82DBC2) + i * 2)) - room_y,
    }));
    y.put("player_xy", b.ints(player));
    y.put("camera_xy", b.ints(.{ rom.getWord(pick(set, 0x82D277, 0x82DBFA) + i * 2), rom.getWord(pick(set, 0x82D16D, 0x82DBEC) + i * 2) }));
    y.put("blockset", b.int(rom.getByte(pick(set, 0x82D381, 0x82DC08) + i)));
    y.put("music", b.str(namedLookup(&names.kMusicNames, rom.getByte(pick(set, 0x82D82E, 0x82DC4E) + i))));
    // Python's (x + 2) >> 1 floors, so -1 lands on 0, the "None" palace.
    y.put("palace", b.str(names.kPalaceNames[@intCast((int8(rom.getByte(pick(set, 0x82D48B, 0x82DC16) + i)) + 2) >> 1)]));
    y.put("doorway_orientation", b.int(if (set == 0) int8(rom.getByte(0x82D510 + i)) else 0));
    const plane = rom.getByte(pick(set, 0x82D595, 0x82DC1D) + i);
    y.put("plane", b.int(plane & 0xf));
    y.put("ladder_level", b.int(plane >> 4));
    const q1 = rom.getByte(pick(set, 0x82D61a, 0x82DC24) + i);
    const q2 = rom.getByte(pick(set, 0x82D69F, 0x82DC2B) + i);
    const quad_x = if (q1 & 0x20 != 0) "double_x" else "single_x";
    y.put("quadrants", b.list(&.{
        b.str(quad_x),
        b.str(if (q1 & 0x2 != 0) "double_y" else "single_y"),
        b.str(switch (q2) {
            0 => "upper_left",
            2 => "lower_left",
            16 => "upper_right",
            18 => "lower_right",
            else => "?",
        }),
    }));
    y.put("floor", b.int(int8(rom.getByte(pick(set, 0x82D406, 0x82DC0F) + i))));

    // Scroll edges, relative to where the room itself would put them.
    const se_base = pick(set, 0x82C91D, 0x82DB7C) + i * 8;
    const base_x: i64 = @as(i64, room & 0xf) * 2;
    const base_y: i64 = @as(i64, room >> 4) * 2;
    const ym: i64 = (player[1] & 0x100) >> 8;
    const xm: i64 = (player[0] & 0x100) >> 8;
    const qqq: i64 = if (room >= 242 and std.mem.eql(u8, quad_x, "single_x")) xm else 0;
    const se = [8]i64{
        @as(i64, rom.getByte(se_base + 0)) - base_y - ym,
        @as(i64, rom.getByte(se_base + 1)) - base_y,
        @as(i64, rom.getByte(se_base + 2)) - base_y - ym,
        @as(i64, rom.getByte(se_base + 3)) - base_y - 1,
        @as(i64, rom.getByte(se_base + 4)) - base_x - xm,
        @as(i64, rom.getByte(se_base + 5)) - base_x - qqq,
        @as(i64, rom.getByte(se_base + 6)) - base_x - xm,
        @as(i64, rom.getByte(se_base + 7)) - base_x - 1 - qqq,
    };
    if (!std.mem.allEqual(i64, &se, 0)) y.put("repair_scroll_bounds", b.ints(se));

    const door = rom.getWord(pick(set, 0x82D724, 0x82DC32) + i * 2);
    y.put("house_exit_door", switch (door) {
        0 => b.list(&.{b.str("none")}),
        0xffff => b.list(&.{b.str("none_0xffff")}),
        else => doorValue(b, if (door & 0x8000 != 0) "bombable" else "wooden", door),
    });
    if (set == 1) y.put("associated_entrance_index", b.int(rom.getWord(0x82DC40 + i * 2)));
    return .{ .room = room, .value = y.done() };
}

fn dungeonRoom(b: B, rom: Rom, room: usize) Value {
    const r: u32 = @intCast(room);
    const room_addr = rom.get24(0x1f8000 + r * 3);
    var p: u32 = 0x40000 | @as(u32, rom.getWord(0x4f502 + r * 2));
    if (p == 0x4FFEF) p = 0x82EDC5; // just some place with zeros, as the Python says
    const floor = rom.getByte(room_addr);
    const layout = rom.getByte(room_addr + 1);
    const flags = rom.getByte(p);
    const p7 = rom.getByte(p + 7);
    const p8 = rom.getByte(p + 8);
    const sprites_ea: u32 = 0x890000 + @as(u32, rom.getWord(0x89D62E + r * 2));

    var h = M{ .b = b };
    h.put("floor1", b.int(floor & 0xf));
    h.put("floor2", b.int(floor >> 4));
    h.put("layout", b.int(layout >> 2));
    h.put("start_quadrant", b.int(layout & 3));
    h.put("bg2", b.str(names.kBg2Names[flags >> 5]));
    h.put("collision", b.str(names.kCollisionNames[(flags >> 2) & 7]));
    h.put("lights_out", b.int(flags & 1));
    h.put("palette", b.int(rom.getByte(p + 1)));
    h.put("blockset", b.int(rom.getByte(p + 2)));
    h.put("enemyblk", b.int(rom.getByte(p + 3)));
    h.put("effect", b.str(names.kEffectNames[rom.getByte(p + 4)]));
    h.put("tag0", b.str(names.kTagNames[rom.getByte(p + 5)]));
    h.put("tag1", b.str(names.kTagNames[rom.getByte(p + 6)]));
    h.put("hole0_dest", b.ints(.{ rom.getByte(p + 9), p7 & 3 }));
    h.put("stair0_dest", b.ints(.{ rom.getByte(p + 10), (p7 >> 2) & 3 }));
    h.put("stair1_dest", b.ints(.{ rom.getByte(p + 11), (p7 >> 4) & 3 }));
    h.put("stair2_dest", b.ints(.{ rom.getByte(p + 12), (p7 >> 6) & 3 }));
    h.put("stair3_dest", b.ints(.{ rom.getByte(p + 13), p8 & 3 }));
    h.put("tele_msg", b.int(rom.getWord(0x87F61D + r * 2)));
    h.put("sort_sprites", b.int(rom.getByte(sprites_ea)));
    var pits = false;
    for (0..57) |k| {
        if (rom.getWord(0x80990C + @as(u32, @intCast(k)) * 2) == room) pits = true;
    }
    h.put("pits_hurt_player", .{ .boolean = pits });

    var y = M{ .b = b };
    y.put("Header", h.done());

    // Sprites. A key drop rides on the sprite before it as a fifth field.
    var sprites: std.ArrayList(std.ArrayList(Value)) = .empty;
    var ea = sprites_ea + 1;
    while (rom.getByte(ea) != 0xff) : (ea += 3) {
        const sy = rom.getByte(ea);
        const sx = rom.getByte(ea + 1);
        const kind = rom.getByte(ea + 2);
        const floor_name = b.str(if (sy >> 7 != 0) "lower" else "upper");
        var entry: std.ArrayList(Value) = .empty;
        if (kind == 0xe4 and (sy == 0xfe or sy == 0xfd)) {
            sprites.items[sprites.items.len - 1].append(b.a, b.str(if (sy == 0xfe) "drop_key" else "drop_big_key")) catch @panic("oom");
            continue;
        } else if (kind != 0xe4 and sx >= 0xe0) {
            // An overlord, named from the second half of the table.
            entry.appendSlice(b.a, &.{ b.int(sx & 0x1f), b.int(sy & 0x1f), floor_name, b.str(names.kSpriteNames[@as(usize, kind) + 0x100]) }) catch @panic("oom");
        } else {
            const subtype = (sx >> 5) | (((sy >> 5) & 3) << 3);
            var name: []const u8 = names.kSpriteNames[kind];
            if (subtype != 0) {
                const dash = std.mem.indexOfScalar(u8, name, '-').?;
                name = std.fmt.allocPrint(b.a, "{s}.{d}{s}", .{ name[0..dash], subtype, name[dash..] }) catch @panic("oom");
            }
            entry.appendSlice(b.a, &.{ b.int(sx & 0x1f), b.int(sy & 0x1f), floor_name, b.str(name) }) catch @panic("oom");
        }
        sprites.append(b.a, entry) catch @panic("oom");
    }
    var sprite_list = L{ .b = b };
    for (sprites.items) |s| sprite_list.add(.{ .list = s.items });
    y.put("Sprites", sprite_list.done());

    var secrets = L{ .b = b };
    var sea: u32 = 0x810000 | @as(u32, rom.getWord(0x81db69 + r * 2));
    while (rom.getWord(sea) != 0xffff) : (sea += 3) {
        const pos = rom.getWord(sea) / 2;
        secrets.add(b.list(&.{ b.int(pos % 64), b.int(pos / 64), b.str(namedLookup(&names.kSecretNames, rom.getByte(sea + 2))) }));
    }
    y.put("Secrets", secrets.done());

    var chests = L{ .b = b };
    for (0..504 / 3) |k| {
        const cea: u32 = 0x81e96e + @as(u32, @intCast(k)) * 3;
        const w = rom.getWord(cea);
        if (w & 0x7fff != room) continue;
        const data = rom.getByte(cea + 2);
        chests.add(if (w & 0x8000 != 0) b.fmt("{d}!", .{data}) else b.int(data));
    }
    y.put("Chests", chests.done());

    inline for (.{ 0, 1 }) |set| {
        var list = L{ .b = b };
        for (0..if (set == 0) 133 else 7) |i| {
            const e = entranceInfo(b, rom, i, set);
            if (e.room == room) list.add(e.value);
        }
        if (set == 0) {
            y.put("Entrances", list.done());
        } else if (list.items.items.len != 0) {
            y.put("StartingPoints", list.done());
        }
    }

    var at = room_addr + 2;
    inline for (.{ "Layer1", "Layer2", "Layer3" }, .{ "Layer1.doors", "Layer2.doors", "Layer3.doors" }) |layer, doors_key| {
        const o = decodeRoomObjects(b, rom, at);
        y.put(layer, o.objs);
        if (o.doors) |d| {
            if (d.list.len != 0) y.put(doors_key, d);
        }
        at = o.next;
    }
    return y.done();
}

fn fixedRooms(b: B, rom: Rom, table: u32, count: usize, prefix: []const u8) Value {
    var m = M{ .b = b };
    for (0..count) |i| {
        const room_addr = rom.get24(table + @as(u32, @intCast(i)) * 3);
        const o = decodeRoomObjects(b, rom, room_addr);
        m.put(std.fmt.allocPrint(b.a, "{s}{d}", .{ prefix, i }) catch @panic("oom"), o.objs);
    }
    return m.done();
}

// ------------------------------------------------------------ text files

fn map32ToMap16(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    for (0..2218) |i_| {
        const i: u32 = @intCast(i_);
        var t: [4][4]u16 = undefined;
        for ([_]u32{ 0x838000, 0x83b400, 0x848000, 0x84b400 }, 0..) |base, k| {
            var ov: [6]u16 = undefined;
            for (0..6) |j| ov[j] = rom.getByte(base + i * 6 + @as(u32, @intCast(j)));
            t[k] = .{ ov[0] | (ov[4] >> 4) << 8, ov[1] | (ov[4] & 0xf) << 8, ov[2] | (ov[5] >> 4) << 8, ov[3] | (ov[5] & 0xf) << 8 };
        }
        for (0..4) |j| {
            var buf: [64]u8 = undefined;
            try out.appendSlice(alloc, try std.fmt.bufPrint(&buf, "{d:>5}: {d:>4}, {d:>4}, {d:>4}, {d:>4}\n", .{ i * 4 + @as(u32, @intCast(j)), t[0][j], t[1][j], t[2][j], t[3][j] }));
        }
    }
    return out.toOwnedSlice(alloc);
}

// ----------------------------------------------------------------- export

/// Writes every file the Python's extract step did into `dir`, which must
/// exist; the overworld and dungeon folders are made as needed. Calls
/// `progress` with each file name as it goes.
pub fn exportFiles(alloc: std.mem.Allocator, rom: Rom, dir: []const u8, progress: ?*const fn ([]const u8) void) !void {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const b = B{ .a = arena };

    try makeDir(arena, dir, "overworld");
    try makeDir(arena, dir, "dungeon");

    for (0..160) |area| {
        if (!isAreaHead(rom, area)) continue;
        _ = arena_state.reset(.retain_capacity);
        const name = try std.fmt.allocPrint(arena, "overworld/overworld-{d}.yaml", .{area});
        try writeYaml(arena, dir, name, overworldArea(b, rom, area), progress);
    }
    for (0..320) |room| {
        _ = arena_state.reset(.retain_capacity);
        const name = try std.fmt.allocPrint(arena, "dungeon/dungeon-{d}.yaml", .{room});
        try writeYaml(arena, dir, name, dungeonRoom(b, rom, room), progress);
    }
    _ = arena_state.reset(.retain_capacity);
    try writeYaml(arena, dir, "dungeon/default_rooms.yaml", fixedRooms(b, rom, 0x84EF2F, 8, "Default"), progress);
    try writeYaml(arena, dir, "dungeon/overlay_rooms.yaml", fixedRooms(b, rom, 0x84ECC0, 19, "Overlay"), progress);
    try writeFile(arena, dir, "dialogue.txt", try dialogue.dialogueText(arena, rom, .us), progress);
    try writeFile(arena, dir, "map32_to_map16.txt", try map32ToMap16(arena, rom), progress);
    try writeFile(arena, dir, "linksprite.png", try graphics.exportLink(arena, rom), progress);
    try writeFile(arena, dir, "font.png", try graphics.exportFont(arena, rom, .us), progress);
    try writeFile(arena, dir, "hud_icons.png", try graphics.exportHudIcons(arena, rom), progress);
    try makeDir(arena, dir, "sound");
    const MusicCtx = struct { arena: std.mem.Allocator, dir: []const u8, progress: ?*const fn ([]const u8) void };
    try music_export.exportMusic(arena, rom, MusicCtx{ .arena = arena, .dir = dir, .progress = progress }, struct {
        fn f(c: MusicCtx, name: []const u8, bytes: []const u8) anyerror!void {
            try writeFile(c.arena, c.dir, name, bytes, c.progress);
        }
    }.f);
    try makeDir(arena, dir, "sprites");
    const Ctx = struct { arena: std.mem.Allocator, dir: []const u8, progress: ?*const fn ([]const u8) void };
    try sheets.exportSheets(alloc, rom, Ctx{ .arena = arena, .dir = dir, .progress = progress }, struct {
        fn f(c: Ctx, name: []const u8, bytes: []const u8) anyerror!void {
            try writeFile(c.arena, c.dir, name, bytes, c.progress);
        }
    }.f);
}

fn makeDir(arena: std.mem.Allocator, dir: []const u8, sub: []const u8) !void {
    const path = try std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ dir, sub }, 0);
    fileio.makeDir(path) catch {};
}

fn writeYaml(arena: std.mem.Allocator, dir: []const u8, name: []const u8, v: Value, progress: ?*const fn ([]const u8) void) !void {
    try writeFile(arena, dir, name, try yaml.emit(arena, v), progress);
}

fn writeFile(arena: std.mem.Allocator, dir: []const u8, name: []const u8, data: []const u8, progress: ?*const fn ([]const u8) void) !void {
    const path = try std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ dir, name }, 0);
    try fileio.writeWholeFile(path.ptr, data);
    if (progress) |p| p(name);
}
