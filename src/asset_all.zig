//! Assembling the whole zelda3_assets.dat from a ROM.
//!
//! The order here is part of the format: the game refers to assets by index,
//! so it has to match what compile_resources emits, which is the order its
//! print_ functions run in rather than anything alphabetical.

const std = @import("std");
const rom_mod = @import("rom.zig");
const pack = @import("asset_pack.zig");
const build_mod = @import("asset_build.zig");
const overworld = @import("asset_overworld.zig");
const dungeon = @import("asset_dungeon.zig");
const dialogue = @import("asset_dialogue.zig");
const music = @import("asset_music.zig");
pub const import_mod = @import("asset_import.zig");

const Rom = rom_mod.Rom;

pub const Assets = struct {
    items: []pack.Asset,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *Assets) void {
        for (self.items) |a| self.alloc.free(a.data);
        self.alloc.free(self.items);
        self.* = undefined;
    }

    pub fn find(self: Assets, name: []const u8) ?[]const u8 {
        for (self.items) |a| {
            if (std.mem.eql(u8, a.name, name)) return a.data;
        }
        return null;
    }
};

const Builder = struct {
    alloc: std.mem.Allocator,
    rom: Rom,
    list: std.ArrayList(pack.Asset),

    fn add(self: *Builder, name: []const u8, kind: pack.Kind, data: []u8) !void {
        try self.list.append(self.alloc, .{ .name = name, .kind = kind, .data = data });
    }

    /// Emits one of the assets that is a plain ROM region, by name, so the
    /// call sites read in the order the file wants rather than the order the
    /// table happens to list them.
    fn addMisc(self: *Builder, name: []const u8) !void {
        for (build_mod.kMiscAssets) |m| {
            if (!std.mem.eql(u8, m.name, name)) continue;
            try self.add(m.name, m.kind, try build_mod.buildMisc(self.alloc, self.rom, m));
            return;
        }
        return error.UnknownAsset;
    }

    fn addMany(self: *Builder, prefix: []const u8, names: []const []const u8) !void {
        var buf: [64]u8 = undefined;
        for (names) |n| {
            const full = try std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, n });
            try self.addMisc(full);
        }
    }
};

/// The fields of an entrance, in the order print_entrance_info emits them.
const kEntranceFields = [_][]const u8{
    "rooms",      "relativeCoords", "scrollX",   "scrollY",
    "playerX",    "playerY",        "cameraX",   "cameraY",
    "blockset",   "floor",          "palace",    "doorwayOrientation",
    "startingBg", "quadrant1",      "quadrant2",
};

pub fn buildAll(alloc: std.mem.Allocator, rom: Rom) !Assets {
    var problem = import_mod.Problem{};
    return buildFrom(alloc, rom, null, &.{}, &problem);
}

/// Builds every asset, taking the editable ones from `files` when given and
/// from the ROM otherwise, with `languages` built in after the US dialogue.
/// The order below is the file format.
pub fn buildFrom(alloc: std.mem.Allocator, rom: Rom, files: ?*const import_mod.Files, languages: []const dialogue.Input, problem: *import_mod.Problem) !Assets {
    var b = Builder{ .alloc = alloc, .rom = rom, .list = .empty };
    const out = import_mod.Out{ .alloc = alloc, .list = &b.list };
    errdefer {
        for (b.list.items) |a| alloc.free(a.data);
        b.list.deinit(alloc);
    }

    // print_sound_banks
    for (music.kSongs) |song|
        try b.add(song.assetName(), .uint8, try music.build(alloc, rom, song));

    // print_dungeon_rooms
    if (files) |f| {
        try import_mod.addDungeonRooms(f, rom, out, problem);
    } else try addDungeonRoomsFromRom(&b, alloc, rom);

    // print_enemy_damage_data, print_link_graphics, print_dungeon_sprites
    try b.add("kEnemyDamageData", .uint8, try build_mod.buildEnemyDamageData(alloc, rom));
    if (files != null and files.?.link_graphics != null) {
        try b.add("kLinkGraphics", .uint8, try alloc.dupe(u8, files.?.link_graphics.?));
    } else try b.addMisc("kLinkGraphics");

    if (files) |f| {
        try import_mod.addDungeonSprites(f, out, problem);
    } else {
        var sprite_offsets: [dungeon.kRoomCount]u16 = undefined;
        try b.add("kDungeonSprites", .uint8, try dungeon.buildSprites(alloc, rom, &sprite_offsets));
        try b.add("kDungeonSpriteOffs", .uint16, try alloc.dupe(u8, std.mem.sliceAsBytes(sprite_offsets[0..])));
    }

    // print_map32_to_map16, print_images
    if (files) |f| {
        try import_mod.addMap32(f, out);
    } else try b.addMany("kMap32ToMap16_", &.{ "0", "1", "2", "3" });
    if (files != null and files.?.sprite_sheets != null) {
        try b.add("kSprGfx", .packed_arrays, try build_mod.buildSprGfxWith(alloc, rom, files.?.sprite_sheets.?));
    } else try b.add("kSprGfx", .packed_arrays, try build_mod.buildSprGfx(alloc, rom));
    try b.add("kBgGfx", .packed_arrays, try build_mod.buildBgGfx(alloc, rom));

    try addMiscAndOverworld(&b, alloc, rom, files, languages, out, problem);
    return .{ .items = try b.list.toOwnedSlice(alloc), .alloc = alloc };
}

fn addDungeonRoomsFromRom(b: *Builder, alloc: std.mem.Allocator, rom: Rom) !void {
    var rooms = try dungeon.buildRooms(alloc, rom);
    defer rooms.deinit(alloc);
    try b.add("kDungeonRoom", .uint8, try alloc.dupe(u8, rooms.data));
    try b.add("kDungeonRoomOffs", .uint16, try alloc.dupe(u8, std.mem.sliceAsBytes(rooms.offsets[0..])));
    try b.add("kDungeonRoomDoorOffs", .uint16, try alloc.dupe(u8, std.mem.sliceAsBytes(rooms.door_offsets[0..])));

    var headers = try dungeon.buildHeaders(alloc, rom);
    defer headers.deinit(alloc);
    try b.add("kDungeonRoomHeaders", .uint8, try alloc.dupe(u8, headers.data));
    try b.add("kDungeonRoomHeadersOffs", .uint16, try alloc.dupe(u8, std.mem.sliceAsBytes(headers.offsets[0..])));

    try b.add("kDungeonRoomChests", .uint8, try dungeon.buildChests(alloc, rom));
    try b.addMisc("kDungeonRoomTeleMsg");
    try b.add("kDungeonPitsHurtPlayer", .uint16, try dungeon.buildPitsHurtPlayer(alloc, rom));

    try b.addMany("kEntranceData_", &kEntranceFields);
    try b.add("kEntranceData_doorSettings", .uint16, try build_mod.buildDoorSettings(alloc, rom, 0x82d724, 133));
    try b.addMisc("kEntranceData_musicTrack");

    try b.addMany("kStartingPoint_", kEntranceFields[0..11]);
    // Starting points have no doorway orientation table; the old Python writes
    // zeros in its place.
    try b.add("kStartingPoint_doorwayOrientation", .uint8, try alloc.dupe(u8, &[_]u8{0} ** 7));
    try b.addMany("kStartingPoint_", kEntranceFields[12..]);
    try b.add("kStartingPoint_doorSettings", .uint16, try build_mod.buildDoorSettings(alloc, rom, 0x82dc32, 7));
    try b.add("kStartingPoint_entrance", .uint8, try build_mod.buildStartingPointEntrance(alloc, rom));
    try b.addMisc("kStartingPoint_musicTrack");

    var defaults = try dungeon.buildDefaultRooms(alloc, rom);
    defer defaults.deinit(alloc);
    try b.add("kDungeonRoomDefault", .uint8, try alloc.dupe(u8, defaults.data));
    try b.add("kDungeonRoomDefaultOffs", .uint16, try alloc.dupe(u8, std.mem.sliceAsBytes(defaults.offsets)));

    var overlays = try dungeon.buildOverlayRooms(alloc, rom);
    defer overlays.deinit(alloc);
    try b.add("kDungeonRoomOverlay", .uint8, try alloc.dupe(u8, overlays.data));
    try b.add("kDungeonRoomOverlayOffs", .uint16, try alloc.dupe(u8, std.mem.sliceAsBytes(overlays.offsets)));

    try b.add("kDungeonSecrets", .uint8, try dungeon.buildSecrets(alloc, rom));
    try b.addMany("", &.{ "kDungAttrsForTile_Offs", "kDungAttrsForTile", "kMovableBlockDataInit", "kTorchDataInit", "kTorchDataJunk" });
}

fn addMiscAndOverworld(b: *Builder, alloc: std.mem.Allocator, rom: Rom, files: ?*const import_mod.Files, languages: []const dialogue.Input, out: import_mod.Out, problem: *import_mod.Problem) !void {
    // print_misc
    try b.addMany("", &.{
        "kOverworldMapGfx",         "kLightOverworldTilemap",      "kDarkOverworldTilemap",
        "kPredefinedTileData",      "kMap16ToMap8",                "kGeneratedWishPondItem",
        "kGeneratedBombosArr",      "kGeneratedEndSequence15",     "kEnding_Credits_Text",
        "kEnding_Credits_Offs",     "kEnding_MapData",             "kEnding0_Offs",
        "kEnding0_Data",            "kPalette_DungBgMain",         "kPalette_MainSpr",
        "kPalette_ArmorAndGloves",  "kPalette_Sword",              "kPalette_Shield",
        "kPalette_SpriteAux3",      "kPalette_MiscSprite_Indoors", "kPalette_SpriteAux1",
        "kPalette_OverworldBgMain", "kPalette_OverworldBgAux12",   "kPalette_OverworldBgAux3",
        "kPalette_PalaceMapBg",     "kPalette_PalaceMapSpr",       "kHudPalData",
        "kOverworldMapPaletteData",
    });

    // print_dialogue
    {
        var rom_texts = try dialogue.romTexts(alloc, rom);
        defer rom_texts.deinit();
        const rom_font = try dialogue.romFont(alloc, rom);
        defer alloc.free(rom_font.tiles);
        defer alloc.free(rom_font.widths);
        var us = dialogue.Input{ .lang = .us, .texts = @ptrCast(rom_texts.items), .font_tiles = rom_font.tiles, .font_widths = rom_font.widths };
        if (files) |f| {
            us.texts = f.dialogue;
            if (f.font) |font| {
                us.font_tiles = font.tiles;
                us.font_widths = font.widths;
            }
        }
        const list = try alloc.alloc(dialogue.Input, 1 + languages.len);
        defer alloc.free(list);
        list[0] = us;
        @memcpy(list[1..], languages);
        var diag = dialogue.Diag{};
        var built = dialogue.buildLanguages(alloc, list, &diag) catch |e| switch (e) {
            error.BadDialogue => {
                var name_buf: [32]u8 = undefined;
                return problem.set("{s}, message {d}: {s}", .{ dialogue.fileName(&name_buf, diag.lang), diag.message, diag.text() });
            },
            else => return e,
        };
        errdefer built.deinit(alloc);
        try b.add("kDialogue", .packed_arrays, built.dialogue);
        try b.add("kDialogueFont", .packed_arrays, built.font);
        try b.add("kDialogueMap", .packed_arrays, built.map);
    }

    // print_dungeon_map
    try b.add("kDungMap_FloorLayout", .packed_arrays, try build_mod.buildDungeonMap(alloc, rom, false));
    try b.add("kDungMap_Tiles", .packed_arrays, try build_mod.buildDungeonMap(alloc, rom, true));

    // print_tilemaps. The names are spelled out so that every asset name in
    // the file is a literal and nothing has to own them.
    const kTilemapNames = [_][]const u8{
        "kBgTilemap_0", "kBgTilemap_1", "kBgTilemap_2",
        "kBgTilemap_3", "kBgTilemap_4", "kBgTilemap_5",
    };
    comptime std.debug.assert(kTilemapNames.len == build_mod.kBgTilemapPtrs.len);
    for (kTilemapNames, 0..) |name, i|
        try b.add(name, .uint8, try build_mod.buildBgTilemap(alloc, rom, i));

    // print_overworld
    try b.add("kOverworld_Hibytes_Comp", .packed_arrays, try build_mod.buildOverworldHibytes(alloc, rom));
    try b.add("kOverworld_Lobytes_Comp", .packed_arrays, try build_mod.buildOverworldLobytes(alloc, rom));

    // print_overworld_tables
    if (files) |f| {
        try import_mod.addOverworldTables(f, rom, out, problem);
    } else {
        var ow = try overworld.build(alloc, rom);
        defer ow.deinit();
        for (ow.assets) |a| try b.add(a.name, a.kind, try alloc.dupe(u8, a.data));
        try b.addMany("", &.{ "kMap8DataToTileAttr", "kSomeTileAttr" });
    }
}

/// Builds every asset and serializes the container.
pub fn buildFile(alloc: std.mem.Allocator, rom: Rom) ![]u8 {
    var assets = try buildAll(alloc, rom);
    defer assets.deinit();
    return pack.write(alloc, assets.items);
}

const testing = std.testing;
const fileio = @import("fileio.zig");

/// SHA-256 of zelda3_assets.dat as the old assets/restool.py built it from the US
/// ROM. Pinned here because the test below otherwise compares against a file
/// on disk that this very program can overwrite - once the launcher has built
/// the assets once, comparing to that file proves nothing. This digest came
/// from the old Python tool's output and does not change.
pub const kReferenceDigest = "0fe2e4bd75d70f06fb9a74cd3a9cb336c838149b831b56e8792114a89292c793";

test "the whole asset file matches the digest of the Python tool's output" {
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc")) return error.SkipZigTest;

    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();
    if (rom.language != .us) return error.SkipZigTest;

    const got = try buildFile(alloc, rom);
    defer alloc.free(got);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(got, &digest, .{});

    var hex: [64]u8 = undefined;
    for (digest, 0..) |byte, i| {
        _ = std.fmt.bufPrint(hex[i * 2 ..][0..2], "{x:0>2}", .{byte}) catch unreachable;
    }
    try testing.expectEqualStrings(kReferenceDigest, &hex);
}

test "the whole asset file is rebuilt byte for byte" {
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc") or !fileio.exists("zig-out/bin/zelda3_assets.dat"))
        return error.SkipZigTest;

    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();

    const want = try fileio.readWholeFile(alloc, "zig-out/bin/zelda3_assets.dat");
    defer alloc.free(want);

    const got = try buildFile(alloc, rom);
    defer alloc.free(got);

    // Name and order first: a mismatch there is far easier to read than a
    // difference thousands of bytes into the payload.
    var ref = try pack.read(alloc, want);
    defer ref.deinit(alloc);
    var mine = try pack.read(alloc, got);
    defer mine.deinit(alloc);

    try testing.expectEqual(ref.entries.len, mine.entries.len);
    for (ref.entries, mine.entries, 0..) |r, m, i| {
        testing.expectEqualStrings(r.name, m.name) catch |err| {
            std.debug.print("asset {d} is named differently\n", .{i});
            return err;
        };
        testing.expectEqualSlices(u8, r.data, m.data) catch |err| {
            std.debug.print("asset {d} ({s}) differs\n", .{ i, r.name });
            return err;
        };
    }

    try testing.expectEqualSlices(u8, want, got);
}
