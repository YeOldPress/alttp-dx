//! The overworld tables, built straight from the ROM.
//!
//! This is compile_resources.print_overworld_tables together with the parts
//! of extract_resources that feed it. The old Python routes the data through YAML
//! so areas can be edited by hand; nothing is transformed on the way, so the
//! two halves are fused here and the intermediate disappears.
//!
//! Two things genuinely reshape the data rather than copy it, and both are
//! why this cannot simply be a list of addresses:
//!
//!  - values for a big area are replicated across the four screens it covers
//!  - whirlpool travel entries are renumbered into area order
//!
//! Everything else survives the trip unchanged.

const std = @import("std");
const rom_mod = @import("rom.zig");
const pack = @import("asset_pack.zig");

const Rom = rom_mod.Rom;

/// An area is a "head" if it is the top left screen of its area, or is one of
/// the special areas from 128 up. Only heads carry data.
fn isAreaHead(rom: Rom, i: u32) bool {
    return i >= 128 or rom.getByte(0x82a5ec + (i & 63)) == (i & 63);
}

fn getInt8(rom: Rom, ea: u32) i8 {
    return @bitCast(rom.getByte(ea));
}

fn getInt16(rom: Rom, ea: u32) i16 {
    return @bitCast(rom.getWord(ea));
}

/// Recomputes the map16 load offset from the scroll and load coordinates.
/// extract_resources asserts this reproduces the value stored in the ROM.
fn loadOffs(scroll: [2]i32, load: [2]i32) u16 {
    const x = (scroll[0] >> 4) + load[0];
    const y = (scroll[1] >> 4) + load[1];
    return @intCast(((y & 0x3f) << 7) | ((x & 0x3f) << 1));
}

/// A table being filled, with the big-area replication built in.
fn Arr(comptime T: type, comptime n: usize) type {
    return struct {
        v: [n]T = @splat(0),

        const Self = @This();

        /// Writes `value` at `key`, and for a big area also at the three
        /// screens to the right, below and below-right. This is `awrite`.
        fn write(self: *Self, is_small: []const u8, area: u32, key: usize, value: T) void {
            self.v[key] = value;
            if (area < 128 and is_small[area] == 0) {
                self.v[key + 1] = value;
                self.v[key + 8] = value;
                self.v[key + 9] = value;
            }
        }

        fn bytes(self: *const Self, alloc: std.mem.Allocator) ![]u8 {
            return alloc.dupe(u8, std.mem.sliceAsBytes(self.v[0..]));
        }
    };
}

/// One entry of the bird travel and whirlpool table.
const Travel = struct {
    area: u32,
    screen_index: u16,
    load_offs: u16,
    load_xy: [2]i32,
    scroll: [2]i32,
    pos: [2]i32,
    camera: [2]i32,
    unk: [2]i8,
    bird_travel_id: ?u32,
    whirlpool_src_area: u16,
};

fn readTravel(rom: Rom, i: u32) Travel {
    const screen_index = rom.getWord(0x82eae5 + i * 2);
    const base_x: i32 = @as(i32, screen_index & 7) << 9;
    const base_y: i32 = @as(i32, screen_index & 56) << 6;
    const load = rom.getWord(0x82eb07 + i * 2);
    const scroll = [2]i32{
        @as(i32, rom.getWord(0x82eb4b + i * 2)) - base_x,
        @as(i32, rom.getWord(0x82eb29 + i * 2)) - base_y,
    };
    return .{
        .area = screen_index,
        .screen_index = screen_index,
        .load_offs = load,
        .load_xy = .{
            (@as(i32, load >> 1) - (scroll[0] >> 4)) & 0x3f,
            (@as(i32, load >> 7) - (scroll[1] >> 4)) & 0x3f,
        },
        .scroll = scroll,
        .pos = .{ @as(i32, rom.getWord(0x82eb8f + i * 2)) - base_x, @as(i32, rom.getWord(0x82eb6d + i * 2)) - base_y },
        .camera = .{ @as(i32, rom.getWord(0x82ebd3 + i * 2)) - base_x, @as(i32, rom.getWord(0x82ebb1 + i * 2)) - base_y },
        .unk = .{ getInt8(rom, 0x82ebf5 + i * 2), getInt8(rom, 0x82ec17 + i * 2) },
        .bird_travel_id = if (i < 9) i else null,
        .whirlpool_src_area = if (i < 9) 0 else rom.getWord(0x82ecf8 + (i - 9) * 2),
    };
}

const Exit = struct {
    index: u32,
    screen_index: u32,
    room: u16,
    scroll: [2]i32,
    pos: [2]i32,
    camera: [2]i32,
    load_xy: [2]i32,
    unk: [2]i8,
    ndoor: u16,
    fdoor: u16,
};

fn readExit(rom: Rom, i: u32) Exit {
    const screen_index = rom.getByte(0x82de28 + i);
    const base_x: i32 = @as(i32, screen_index & 7) << 9;
    const base_y: i32 = @as(i32, screen_index & 56) << 6;
    const load = rom.getWord(0x82de77 + i * 2);
    const scroll = [2]i32{
        @as(i32, rom.getWord(0x82dfb3 + i * 2)) - base_x,
        @as(i32, rom.getWord(0x82df15 + i * 2)) - base_y,
    };
    return .{
        .index = i,
        .screen_index = screen_index,
        .room = rom.getWord(0x82dd8a + i * 2),
        .scroll = scroll,
        .pos = .{ @as(i32, rom.getWord(0x82e0ef + i * 2)) - base_x, @as(i32, rom.getWord(0x82e051 + i * 2)) - base_y },
        .camera = .{ @as(i32, rom.getWord(0x82e22b + i * 2)) - base_x, @as(i32, rom.getWord(0x82e18d + i * 2)) - base_y },
        .load_xy = .{
            (@as(i32, load >> 1) - (scroll[0] >> 4)) & 0x3f,
            (@as(i32, load >> 7) - (scroll[1] >> 4)) & 0x3f,
        },
        .unk = .{ getInt8(rom, 0x82e2c9 + i), getInt8(rom, 0x82e318 + i) },
        .ndoor = rom.getWord(0x82e367 + i * 2),
        .fdoor = rom.getWord(0x82e405 + i * 2),
    };
}

pub const Built = struct {
    assets: []pack.Asset,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *Built) void {
        for (self.assets) |a| self.alloc.free(a.data);
        self.alloc.free(self.assets);
        self.* = undefined;
    }
};

/// Builds every overworld table, in the order compile_resources emits them.
pub fn build(alloc: std.mem.Allocator, rom: Rom) !Built {
    const is_small = try rom.getBytes(alloc, 0x82f88d, 192);
    defer alloc.free(is_small);

    var heads: [160]bool = @splat(false);
    for (0..160) |i| heads[i] = isAreaHead(rom, @intCast(i));

    var map_is_small = Arr(u8, 192){};
    var aux_tile = Arr(u8, 128){};
    var bg_palettes = Arr(u8, 136){};
    var sign_text = Arr(u16, 128){};
    var music_sets = Arr(u8, 256){};
    var music_sets2 = Arr(u8, 96){};

    for (0..160) |ai| {
        const i: u32 = @intCast(ai);
        if (!heads[ai]) continue;

        map_is_small.v[ai] = if (is_small[ai] != 0) 1 else 0;
        if (i < 128) aux_tile.write(is_small, i, ai, rom.getByte(0x80fc9c + i));
        if (i < 136) bg_palettes.write(is_small, i, ai, rom.getByte(0x80fd1c + i));
        if (i < 128) sign_text.write(is_small, i, ai, rom.getWord(0x87f51d + i * 2));

        // The music byte holds the track in the low nibble and the ambient
        // sound in the high one; the old Python splits it into names and joins
        // them again, which puts the byte back exactly as it was.
        if (i < 64) {
            music_sets.write(is_small, i, ai, rom.getByte(0x82c303 + i));
            music_sets.write(is_small, i, ai + 64, rom.getByte(0x82c303 + i + 64));
            music_sets.write(is_small, i, ai + 128, rom.getByte(0x82c303 + i + 128));
            music_sets.write(is_small, i, ai + 192, rom.getByte(0x82c303 + i + 192));
        } else if (i < 64 + 96) {
            music_sets2.write(is_small, i, ai - 64, rom.getByte(0x82c403 + i - 64));
        }
    }

    // Travel entries are filed under their screen index, then walked in area
    // order - which renumbers the whirlpools, since the ROM stores them in a
    // different order from the areas they belong to.
    var bird_screen = Arr(u16, 17){};
    var bird_load = Arr(u16, 17){};
    var bird_scroll_x = Arr(u16, 17){};
    var bird_scroll_y = Arr(u16, 17){};
    var bird_link_x = Arr(u16, 17){};
    var bird_link_y = Arr(u16, 17){};
    var bird_cam_x = Arr(u16, 17){};
    var bird_cam_y = Arr(u16, 17){};
    var bird_unk1 = Arr(i8, 17){};
    var bird_unk3 = Arr(i8, 17){};
    var whirlpool_areas = Arr(u16, 8){};

    var next_whirlpool: u32 = 0;
    for (0..160) |ai| {
        if (!heads[ai]) continue;
        for (0..17) |ti| {
            const t = readTravel(rom, @intCast(ti));
            if (t.area != ai) continue;

            const j: usize = if (t.bird_travel_id) |b| b else blk: {
                whirlpool_areas.v[next_whirlpool] = t.whirlpool_src_area;
                const k = next_whirlpool + 9;
                next_whirlpool += 1;
                break :blk k;
            };

            const base_x: i32 = @as(i32, @intCast(ai & 7)) << 9;
            const base_y: i32 = @as(i32, @intCast(ai & 56)) << 6;
            bird_screen.v[j] = @intCast(ai);
            bird_load.v[j] = loadOffs(t.scroll, t.load_xy);
            bird_scroll_x.v[j] = @intCast(t.scroll[0] + base_x);
            bird_scroll_y.v[j] = @intCast(t.scroll[1] + base_y);
            bird_link_x.v[j] = @intCast(t.pos[0] + base_x);
            bird_link_y.v[j] = @intCast(t.pos[1] + base_y);
            bird_cam_x.v[j] = @intCast(t.camera[0] + base_x);
            bird_cam_y.v[j] = @intCast(t.camera[1] + base_y);
            bird_unk1.v[j] = t.unk[0];
            bird_unk3.v[j] = t.unk[1];
        }
    }

    // Entrances and holes are keyed by area but numbered by their own index,
    // so no reordering happens - only the coordinate packing.
    var ent_area = Arr(u16, 129){};
    var ent_pos = Arr(u16, 129){};
    var ent_id = Arr(u8, 129){};
    for (0..129) |ei| {
        const i: u32 = @intCast(ei);
        const area = rom.getWord(0x9bb96f + i * 2);
        const pos = rom.getWord(0x9bba71 + i * 2);
        const x: u16 = (pos >> 1) & 0x3f;
        const y: u16 = (pos >> 7) & 0x3f;
        ent_area.v[ei] = area;
        ent_pos.v[ei] = (x << 1) | (y << 7);
        ent_id.v[ei] = rom.getByte(0x9bbb73 + i);
    }

    const Hole = struct { entrance: u8, pos: u16, area: u16 };
    var holes: [19]Hole = undefined;
    for (0..19) |hi| {
        const i: u32 = @intCast(hi);
        const pos = rom.getWord(0x9bb800 + i * 2) +% 0x400;
        const x: u16 = (pos >> 1) & 0x3f;
        const y: u16 = (pos >> 7) & 0x3f;
        holes[hi] = .{
            .entrance = rom.getByte(0x9bb84c + i),
            .pos = (x << 1) | ((y -% 8) & 0x3f) << 7,
            .area = rom.getWord(0x9bb826 + i * 2),
        };
    }
    // Python sorts the (entrance, pos, area) tuples before laying them out.
    std.mem.sort(Hole, &holes, {}, struct {
        fn lt(_: void, a: Hole, b: Hole) bool {
            if (a.entrance != b.entrance) return a.entrance < b.entrance;
            if (a.pos != b.pos) return a.pos < b.pos;
            return a.area < b.area;
        }
    }.lt);

    var hole_area = Arr(u16, 19){};
    var hole_pos = Arr(u16, 19){};
    var hole_ent = Arr(u8, 19){};
    for (holes, 0..) |h, i| {
        hole_area.v[i] = h.area;
        hole_pos.v[i] = h.pos;
        hole_ent.v[i] = h.entrance;
    }

    var exit_screen = Arr(u8, 79){};
    var exit_rooms = Arr(u16, 79){};
    var exit_load = Arr(u16, 79){};
    var exit_scroll_x = Arr(u16, 79){};
    var exit_scroll_y = Arr(u16, 79){};
    var exit_x = Arr(u16, 79){};
    var exit_y = Arr(u16, 79){};
    var exit_cam_x = Arr(u16, 79){};
    var exit_cam_y = Arr(u16, 79){};
    var exit_ndoor = Arr(u16, 79){};
    var exit_fdoor = Arr(u16, 79){};
    var exit_unk1 = Arr(i8, 79){};
    var exit_unk3 = Arr(i8, 79){};

    var sp_top = Arr(u16, 16){};
    var sp_bottom = Arr(u16, 16){};
    var sp_left = Arr(u16, 16){};
    var sp_right = Arr(u16, 16){};
    var sp_tab4 = Arr(i16, 16){};
    var sp_tab5 = Arr(i16, 16){};
    var sp_tab6 = Arr(i16, 16){};
    var sp_tab7 = Arr(i16, 16){};
    var sp_edge = Arr(u16, 16){};
    var sp_dir = Arr(u8, 16){};
    var sp_sprgfx = Arr(u8, 16){};
    var sp_auxgfx = Arr(u8, 16){};
    var sp_palbg = Arr(u8, 16){};
    var sp_palspr = Arr(u8, 16){};

    for (0..160) |ai| {
        if (!heads[ai]) continue;
        for (0..79) |xi| {
            const e = readExit(rom, @intCast(xi));
            if (e.screen_index != ai) continue;

            const j = e.index;
            const base_x: i32 = @as(i32, @intCast(ai & 7)) << 9;
            const base_y: i32 = @as(i32, @intCast(ai & 56)) << 6;
            exit_screen.v[j] = @intCast(ai);
            exit_rooms.v[j] = e.room;
            exit_load.v[j] = loadOffs(e.scroll, e.load_xy);
            exit_scroll_x.v[j] = @intCast(e.scroll[0] + base_x);
            exit_scroll_y.v[j] = @intCast(e.scroll[1] + base_y);
            exit_x.v[j] = @intCast(e.pos[0] + base_x);
            exit_y.v[j] = @intCast(e.pos[1] + base_y);
            exit_cam_x.v[j] = @intCast(e.camera[0] + base_x);
            exit_cam_y.v[j] = @intCast(e.camera[1] + base_y);
            exit_unk1.v[j] = e.unk[0];
            exit_unk3.v[j] = e.unk[1];

            // A door is split into a kind and a position and put back, which
            // drops the bits the kind does not carry.
            if (e.ndoor != 0) {
                const dx: u16 = (e.ndoor & 0x7e) >> 1;
                const dy: u16 = (e.ndoor & 0x3f80) >> 7;
                exit_ndoor.v[j] = (dx << 1) | (dy << 7) | (e.ndoor & 0x8000);
            }
            if (e.fdoor != 0) {
                const dx: u16 = (e.fdoor & 0x7e) >> 1;
                const dy: u16 = (e.fdoor & 0x3f80) >> 7;
                exit_fdoor.v[j] = (dx << 1) | (dy << 7) | (e.fdoor & 0x8000);
            }

            if (e.room >= 0x180 and e.room < 0x190) {
                const k: u32 = e.room - 0x180;
                const s = k;
                sp_dir.v[s] = (rom.getByte(0x82e801 + k) >> 1) * 2;
                sp_sprgfx.v[s] = rom.getByte(0x82e811 + k);
                sp_auxgfx.v[s] = rom.getByte(0x82e821 + k);
                sp_palbg.v[s] = rom.getByte(0x82e831 + k);
                sp_palspr.v[s] = rom.getByte(0x82e841 + k);
                sp_top.v[s] = rom.getWord(0x82e6e1 + k * 2);
                sp_bottom.v[s] = rom.getWord(0x82e701 + k * 2);
                sp_left.v[s] = rom.getWord(0x82e721 + k * 2);
                sp_right.v[s] = rom.getWord(0x82e741 + k * 2);
                sp_edge.v[s] = rom.getWord(0x82e7e1 + k * 2);
                sp_tab4.v[s] = getInt16(rom, 0x82e761 + k * 2);
                sp_tab5.v[s] = getInt16(rom, 0x82e7a1 + k * 2);
                sp_tab6.v[s] = getInt16(rom, 0x82e781 + k * 2);
                sp_tab7.v[s] = getInt16(rom, 0x82e7c1 + k * 2);
            }
        }
    }

    // Secrets are concatenated in area order with a terminator after each
    // area's run, and every area without any points at the last terminator.
    var secrets: std.ArrayList(u8) = .empty;
    errdefer secrets.deinit(alloc);
    var secrets_offs = Arr(u16, 128){};
    var have_secrets: [128]bool = @splat(false);

    for (0..160) |ai| {
        if (!heads[ai] or ai >= 128) continue;
        const i: u32 = @intCast(ai);
        var ea: u32 = 0x9b0000 | @as(u32, rom.getWord(0x9bc2f9 + i * 2));
        if (rom.getWord(ea) == 0xffff) continue;

        secrets_offs.write(is_small, i, ai, @intCast(secrets.items.len));
        have_secrets[ai] = true;
        if (i < 128 and is_small[ai] == 0) {
            have_secrets[ai + 1] = true;
            have_secrets[ai + 8] = true;
            have_secrets[ai + 9] = true;
        }
        while (rom.getWord(ea) != 0xffff) {
            const p = rom.getWord(ea);
            const x: u16 = (p / 2) % 64;
            const y: u16 = (p / 2) / 64;
            const pos = (x << 1) | (y << 7);
            try secrets.append(alloc, @intCast(pos & 0xff));
            try secrets.append(alloc, @intCast(pos >> 8));
            try secrets.append(alloc, rom.getByte(ea + 2));
            ea += 3;
        }
        try secrets.appendSlice(alloc, &.{ 0xff, 0xff });
    }
    for (0..128) |i| {
        if (!have_secrets[i]) secrets_offs.v[i] = @intCast(secrets.items.len - 2);
    }

    // Sprites are laid out in four passes - three stages for the light world
    // areas and one shared pass for the rest - each appending to a single run
    // of packets. The list opens with a lone terminator so that offset zero
    // means "no sprites".
    var sprites: std.ArrayList(u8) = .empty;
    errdefer sprites.deinit(alloc);
    try sprites.append(alloc, 0xff);

    var sprite_offs = Arr(u16, 144 * 3){};
    var sprite_gfx = Arr(u8, 256){};
    var sprite_pals = Arr(u8, 256){};

    const kSpritePasses = [_]struct {
        start: u32,
        end: u32,
        base: u32,
        stages: []const u32,
        info_stage: u32,
    }{
        .{ .start = 0, .end = 64, .base = 0x89c881, .stages = &.{0}, .info_stage = 0 },
        .{ .start = 0, .end = 64, .base = 0x89c901, .stages = &.{1}, .info_stage = 1 },
        .{ .start = 0, .end = 64, .base = 0x89ca21, .stages = &.{2}, .info_stage = 2 },
        .{ .start = 64, .end = 144, .base = 0x89ca21, .stages = &.{ 1, 2 }, .info_stage = 3 },
    };

    for (kSpritePasses) |pass| {
        for (0..160) |ai| {
            const i: u32 = @intCast(ai);
            if (!heads[ai] or i < pass.start or i >= pass.end) continue;

            if (i < 128) {
                const key = (i & 63) + pass.info_stage * 64;
                sprite_gfx.write(is_small, i, key, rom.getByte(0x80fa41 + key));
                sprite_pals.write(is_small, i, key, rom.getByte(0x80fb41 + key));
            }

            var ea: u32 = 0x890000 + @as(u32, rom.getWord(pass.base + i * 2));
            if (rom.getByte(ea) == 0xff) continue;

            for (pass.stages) |st| sprite_offs.v[st * 144 + i] = @intCast(sprites.items.len);
            while (rom.getByte(ea) != 0xff) {
                const sy = rom.getByte(ea);
                const sx = rom.getByte(ea + 1);
                const sw = rom.getByte(ea + 2);
                try sprites.appendSlice(alloc, &.{ sy, sx, sw });
                ea += 3;
            }
            try sprites.append(alloc, 0xff);
        }
    }

    var assets: std.ArrayList(pack.Asset) = .empty;
    errdefer {
        for (assets.items) |a| alloc.free(a.data);
        assets.deinit(alloc);
    }

    const add = struct {
        fn f(al: std.mem.Allocator, list: *std.ArrayList(pack.Asset), name: []const u8, kind: pack.Kind, data: []u8) !void {
            try list.append(al, .{ .name = name, .kind = kind, .data = data });
        }
    }.f;

    try add(alloc, &assets, "kOverworldMapIsSmall", .uint8, try map_is_small.bytes(alloc));
    try add(alloc, &assets, "kOverworldAuxTileThemeIndexes", .uint8, try aux_tile.bytes(alloc));
    try add(alloc, &assets, "kOverworldBgPalettes", .uint8, try bg_palettes.bytes(alloc));
    try add(alloc, &assets, "kOverworld_SignText", .uint16, try sign_text.bytes(alloc));
    try add(alloc, &assets, "kOwMusicSets", .uint8, try music_sets.bytes(alloc));
    try add(alloc, &assets, "kOwMusicSets2", .uint8, try music_sets2.bytes(alloc));

    try add(alloc, &assets, "kBirdTravel_ScreenIndex", .uint16, try bird_screen.bytes(alloc));
    try add(alloc, &assets, "kBirdTravel_Map16LoadSrcOff", .uint16, try bird_load.bytes(alloc));
    try add(alloc, &assets, "kBirdTravel_ScrollX", .uint16, try bird_scroll_x.bytes(alloc));
    try add(alloc, &assets, "kBirdTravel_ScrollY", .uint16, try bird_scroll_y.bytes(alloc));
    try add(alloc, &assets, "kBirdTravel_LinkXCoord", .uint16, try bird_link_x.bytes(alloc));
    try add(alloc, &assets, "kBirdTravel_LinkYCoord", .uint16, try bird_link_y.bytes(alloc));
    try add(alloc, &assets, "kBirdTravel_CameraXScroll", .uint16, try bird_cam_x.bytes(alloc));
    try add(alloc, &assets, "kBirdTravel_CameraYScroll", .uint16, try bird_cam_y.bytes(alloc));
    try add(alloc, &assets, "kBirdTravel_Unk1", .int8, try bird_unk1.bytes(alloc));
    try add(alloc, &assets, "kBirdTravel_Unk3", .int8, try bird_unk3.bytes(alloc));
    try add(alloc, &assets, "kWhirlpoolAreas", .uint16, try whirlpool_areas.bytes(alloc));

    try add(alloc, &assets, "kOverworld_Entrance_Area", .uint16, try ent_area.bytes(alloc));
    try add(alloc, &assets, "kOverworld_Entrance_Pos", .uint16, try ent_pos.bytes(alloc));
    try add(alloc, &assets, "kOverworld_Entrance_Id", .uint8, try ent_id.bytes(alloc));

    try add(alloc, &assets, "kFallHole_Area", .uint16, try hole_area.bytes(alloc));
    try add(alloc, &assets, "kFallHole_Pos", .uint16, try hole_pos.bytes(alloc));
    try add(alloc, &assets, "kFallHole_Entrances", .uint8, try hole_ent.bytes(alloc));

    try add(alloc, &assets, "kExitData_ScreenIndex", .uint8, try exit_screen.bytes(alloc));
    try add(alloc, &assets, "kExitDataRooms", .uint16, try exit_rooms.bytes(alloc));
    try add(alloc, &assets, "kExitData_Map16LoadSrcOff", .uint16, try exit_load.bytes(alloc));
    try add(alloc, &assets, "kExitData_ScrollX", .uint16, try exit_scroll_x.bytes(alloc));
    try add(alloc, &assets, "kExitData_ScrollY", .uint16, try exit_scroll_y.bytes(alloc));
    try add(alloc, &assets, "kExitData_XCoord", .uint16, try exit_x.bytes(alloc));
    try add(alloc, &assets, "kExitData_YCoord", .uint16, try exit_y.bytes(alloc));
    try add(alloc, &assets, "kExitData_CameraXScroll", .uint16, try exit_cam_x.bytes(alloc));
    try add(alloc, &assets, "kExitData_CameraYScroll", .uint16, try exit_cam_y.bytes(alloc));
    try add(alloc, &assets, "kExitData_NormalDoor", .uint16, try exit_ndoor.bytes(alloc));
    try add(alloc, &assets, "kExitData_FancyDoor", .uint16, try exit_fdoor.bytes(alloc));
    try add(alloc, &assets, "kExitData_Unk1", .int8, try exit_unk1.bytes(alloc));
    try add(alloc, &assets, "kExitData_Unk3", .int8, try exit_unk3.bytes(alloc));

    try add(alloc, &assets, "kSpExit_Top", .uint16, try sp_top.bytes(alloc));
    try add(alloc, &assets, "kSpExit_Bottom", .uint16, try sp_bottom.bytes(alloc));
    try add(alloc, &assets, "kSpExit_Left", .uint16, try sp_left.bytes(alloc));
    try add(alloc, &assets, "kSpExit_Right", .uint16, try sp_right.bytes(alloc));
    try add(alloc, &assets, "kSpExit_Tab4", .int16, try sp_tab4.bytes(alloc));
    try add(alloc, &assets, "kSpExit_Tab5", .int16, try sp_tab5.bytes(alloc));
    try add(alloc, &assets, "kSpExit_Tab6", .int16, try sp_tab6.bytes(alloc));
    try add(alloc, &assets, "kSpExit_Tab7", .int16, try sp_tab7.bytes(alloc));
    try add(alloc, &assets, "kSpExit_LeftEdgeOfMap", .uint16, try sp_edge.bytes(alloc));
    try add(alloc, &assets, "kSpExit_Dir", .uint8, try sp_dir.bytes(alloc));
    try add(alloc, &assets, "kSpExit_SprGfx", .uint8, try sp_sprgfx.bytes(alloc));
    try add(alloc, &assets, "kSpExit_AuxGfx", .uint8, try sp_auxgfx.bytes(alloc));
    try add(alloc, &assets, "kSpExit_PalBg", .uint8, try sp_palbg.bytes(alloc));
    try add(alloc, &assets, "kSpExit_PalSpr", .uint8, try sp_palspr.bytes(alloc));

    try add(alloc, &assets, "kOverworldSecrets_Offs", .uint16, try secrets_offs.bytes(alloc));
    try add(alloc, &assets, "kOverworldSecrets", .uint8, try secrets.toOwnedSlice(alloc));

    try add(alloc, &assets, "kOverworldSpriteOffs", .uint16, try sprite_offs.bytes(alloc));
    try add(alloc, &assets, "kOverworldSprites", .uint8, try sprites.toOwnedSlice(alloc));
    try add(alloc, &assets, "kOverworldSpriteGfx", .uint8, try sprite_gfx.bytes(alloc));
    try add(alloc, &assets, "kOverworldSpritePalettes", .uint8, try sprite_pals.bytes(alloc));

    return .{ .assets = try assets.toOwnedSlice(alloc), .alloc = alloc };
}

const testing = std.testing;
const fileio = @import("fileio.zig");

test "the overworld tables match the reference asset file" {
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc") or !fileio.exists("zig-out/bin/zelda3_assets.dat"))
        return error.SkipZigTest;

    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();
    const dat = try fileio.readWholeFile(alloc, "zig-out/bin/zelda3_assets.dat");
    defer alloc.free(dat);
    var contents = try pack.read(alloc, dat);
    defer contents.deinit(alloc);

    var built = try build(alloc, rom);
    defer built.deinit();

    var failures: usize = 0;
    for (built.assets) |a| {
        const want = contents.find(a.name) orelse {
            std.debug.print("{s}: not in the reference file\n", .{a.name});
            failures += 1;
            continue;
        };
        if (!std.mem.eql(u8, want, a.data)) {
            std.debug.print("{s}: differs ({d} bytes vs {d})\n", .{ a.name, want.len, a.data.len });
            failures += 1;
        }
    }
    try testing.expectEqual(@as(usize, 0), failures);
}
