//! Building assets from edited files: the YAML areas and rooms, the map32
//! table and the dialogue that asset_export writes.
//!
//! This is the file-reading half of compile_resources.py, ported one for one
//! so that files nobody has touched build exactly the assets the ROM does.
//! What isn't read from files still comes from the ROM, as it did there.
//!
//! Problems in the files are reported by name, file and line where there is
//! one, because the person reading them is the one who just edited the file.
const std = @import("std");
const rom_mod = @import("rom.zig");
const yaml = @import("yaml.zig");
const names = @import("asset_names.zig");
const pack = @import("asset_pack.zig");
const fileio = @import("fileio.zig");
const png = @import("png.zig");
const graphics = @import("asset_graphics.zig");
const sheets_mod = @import("asset_sprite_sheets.zig");
const dialogue = @import("asset_dialogue.zig");

const Rom = rom_mod.Rom;
const Value = yaml.Value;

/// What went wrong, for the person who has to fix it.
pub const Problem = struct {
    buf: [512]u8 = undefined,
    len: usize = 0,

    pub fn text(self: *const Problem) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn set(self: *Problem, comptime fmt: []const u8, args: anytype) error{BadInput} {
        const written: []const u8 = std.fmt.bufPrint(&self.buf, fmt, args) catch &self.buf;
        self.len = written.len;
        return error.BadInput;
    }
};

pub const Error = error{ BadInput, OutOfMemory };

/// The edited files, read and parsed. Everything lives in `arena`.
pub const Files = struct {
    arena_state: std.heap.ArenaAllocator,
    dungeon: [320]Value = undefined,
    default_rooms: Value = .null_,
    overlay_rooms: Value = .null_,
    overworld: [160]?Value = @splat(null),
    map32: []const [4]u16 = &.{},
    dialogue: []const []const u8 = &.{},
    /// kLinkGraphics from linksprite.png, when the folder has one.
    link_graphics: ?[]const u8 = null,
    /// The font's tiles and widths from font.png, when the folder has one.
    font: ?struct { tiles: []const u8, widths: []const u8 } = null,
    /// The sprite sheets rebuilt from sprites/*.png, when asked for.
    sprite_sheets: ?[]const ?[0x600]u8 = null,

    pub const Options = struct {
        /// Build the sprite sheets from sprites/sprites_*.png. Off by default,
        /// as in the Python: the sheets go in uncompressed, so even unedited
        /// they make a different, larger, file.
        sprites_from_png: bool = false,
    };

    pub fn deinit(self: *Files) void {
        self.arena_state.deinit();
    }

    /// Reads every file from `dir`. On failure `problem` says which file and
    /// what's wrong with it.
    pub fn load(alloc: std.mem.Allocator, rom: Rom, dir: []const u8, options: Options, problem: *Problem) Error!Files {
        var self = Files{ .arena_state = std.heap.ArenaAllocator.init(alloc) };
        errdefer self.deinit();
        const a = self.arena_state.allocator();

        for (0..320) |i| {
            self.dungeon[i] = try loadYaml(a, dir, try std.fmt.allocPrint(a, "dungeon/dungeon-{d}.yaml", .{i}), problem);
        }
        self.default_rooms = try loadYaml(a, dir, "dungeon/default_rooms.yaml", problem);
        self.overlay_rooms = try loadYaml(a, dir, "dungeon/overlay_rooms.yaml", problem);
        for (0..160) |i| {
            if (!isAreaHead(rom, i)) continue;
            self.overworld[i] = try loadYaml(a, dir, try std.fmt.allocPrint(a, "overworld/overworld-{d}.yaml", .{i}), problem);
        }
        self.map32 = try loadMap32(a, dir, problem);
        self.dialogue = try loadDialogue(a, dir, "dialogue.txt", problem);
        if (try loadPng(a, dir, "linksprite.png", problem)) |img| {
            self.link_graphics = graphics.importLink(a, img) catch |e| return problem.set("linksprite.png: {s}", .{pngProblem(e)});
        }
        if (try loadPng(a, dir, "font.png", problem)) |img| {
            const f = graphics.importFont(a, img, .us) catch |e| return problem.set("font.png: {s}", .{pngProblem(e)});
            self.font = .{ .tiles = f.tiles, .widths = f.widths };
        }
        if (options.sprites_from_png) {
            var images: [sheets_mod.kGroups.len]?png.Image = @splat(null);
            for (sheets_mod.kGroups, 0..) |g, k| {
                const name = try std.fmt.allocPrint(a, "sprites/sprites_{c}.png", .{g});
                images[k] = try loadPng(a, dir, name, problem) orelse return problem.set("{s} is missing; export again to get it back", .{name});
            }
            var why: [256]u8 = undefined;
            var why_len: usize = 0;
            const imported = sheets_mod.importSheets(a, &images, &why, &why_len) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.BadSheet => return problem.set("{s}", .{why[0..why_len]}),
            };
            const list = try a.alloc(?[0x600]u8, 103);
            for (list, 0..) |*s, t| s.* = imported.sheets[t];
            self.sprite_sheets = list;
        }
        return self;
    }
};

fn isAreaHead(rom: Rom, i: usize) bool {
    return i >= 128 or rom.getByte(0x82A5EC + @as(u32, @intCast(i & 63))) == (i & 63);
}

fn readFile(a: std.mem.Allocator, dir: []const u8, name: []const u8, problem: *Problem) Error![]u8 {
    const path = try std.fmt.allocPrintSentinel(a, "{s}/{s}", .{ dir, name }, 0);
    return fileio.readWholeFile(a, path.ptr) catch problem.set("{s}: can't read it", .{name});
}

fn loadYaml(a: std.mem.Allocator, dir: []const u8, name: []const u8, problem: *Problem) Error!Value {
    const text = try readFile(a, dir, name, problem);
    var diag = yaml.Diagnostic{};
    return yaml.parse(a, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        error.Syntax => problem.set("{s}, line {d}: {s}", .{ name, diag.line, diag.message }),
    };
}

/// Extra languages to build in: each one's dialogue_xx.txt and font_xx.png,
/// as extracting them from that language's ROM writes them.
pub const Languages = struct {
    arena_state: std.heap.ArenaAllocator,
    list: []const dialogue.Input = &.{},

    pub fn deinit(self: *Languages) void {
        self.arena_state.deinit();
    }

    pub fn load(alloc: std.mem.Allocator, dir: []const u8, which: []const rom_mod.Language, problem: *Problem) Error!Languages {
        var self = Languages{ .arena_state = std.heap.ArenaAllocator.init(alloc) };
        errdefer self.deinit();
        const a = self.arena_state.allocator();
        const list = try a.alloc(dialogue.Input, which.len);
        for (which, list) |lang, *entry| {
            var name_buf: [32]u8 = undefined;
            const name = try a.dupe(u8, dialogue.fileName(&name_buf, lang));
            const font_name = graphics.fontType(lang).file;
            if (!has(a, dir, name) or !has(a, dir, font_name)) {
                return problem.set("{s} and {s} aren't both in {s}; extract them from that language's ROM first", .{ name, font_name, dir });
            }
            const img = (try loadPng(a, dir, font_name, problem)).?;
            const font = graphics.importFont(a, img, lang) catch |e| return problem.set("{s}: {s}", .{ font_name, pngProblem(e) });
            entry.* = .{ .lang = lang, .texts = try loadDialogue(a, dir, name, problem), .font_tiles = font.tiles, .font_widths = font.widths };
        }
        self.list = list;
        return self;
    }

    /// Whether `dir` has what building `lang` in needs.
    pub fn available(dir: []const u8, lang: rom_mod.Language) bool {
        var buf: [1024]u8 = undefined;
        var name_buf: [32]u8 = undefined;
        for ([_][]const u8{ dialogue.fileName(&name_buf, lang), graphics.fontType(lang).file }) |name| {
            const path = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ dir, name }) catch return false;
            if (!fileio.exists(path.ptr)) return false;
        }
        return true;
    }
};

fn has(a: std.mem.Allocator, dir: []const u8, name: []const u8) bool {
    const path = std.fmt.allocPrintSentinel(a, "{s}/{s}", .{ dir, name }, 0) catch return false;
    return fileio.exists(path.ptr);
}

/// A PNG if the folder has it; null if it doesn't, which means use the ROM's.
fn loadPng(a: std.mem.Allocator, dir: []const u8, name: []const u8, problem: *Problem) Error!?png.Image {
    const path = try std.fmt.allocPrintSentinel(a, "{s}/{s}", .{ dir, name }, 0);
    if (!fileio.exists(path.ptr)) return null;
    const bytes = try readFile(a, dir, name, problem);
    return png.decode(a, bytes) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => problem.set("{s}: {s}", .{ name, pngProblem(e) }),
    };
}

/// What a graphics error means for the person editing the image.
fn pngProblem(e: anyerror) []const u8 {
    return switch (e) {
        error.NotPng => "isn't a PNG",
        error.Corrupt => "is damaged",
        error.Unsupported => "is interlaced or 16 bits a channel; save it as a plain 8-bit PNG",
        error.WrongSize => "is a different size from the one exported; keep the size the same",
        error.FontNotIndexed => "has to stay an indexed-color (palette) image",
        error.ColorNotInPalette => "uses a color that isn't in the exported palette",
        else => @errorName(e),
    };
}

fn loadMap32(a: std.mem.Allocator, dir: []const u8, problem: *Problem) Error![]const [4]u16 {
    const text = try readFile(a, dir, "map32_to_map16.txt", problem);
    var rows: std.ArrayList([4]u16) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return problem.set("map32_to_map16.txt, line {d}: expected 'index: a, b, c, d'", .{line_no});
        const index = std.fmt.parseInt(usize, std.mem.trim(u8, line[0..colon], " "), 10) catch return problem.set("map32_to_map16.txt, line {d}: bad index", .{line_no});
        if (index != rows.items.len) return problem.set("map32_to_map16.txt, line {d}: expected index {d}", .{ line_no, rows.items.len });
        var row: [4]u16 = undefined;
        var fields = std.mem.splitScalar(u8, line[colon + 1 ..], ',');
        for (&row) |*v| {
            const f = std.mem.trim(u8, fields.next() orelse return problem.set("map32_to_map16.txt, line {d}: needs four numbers", .{line_no}), " ");
            v.* = std.fmt.parseInt(u16, f, 10) catch return problem.set("map32_to_map16.txt, line {d}: bad number '{s}'", .{ line_no, f });
            if (v.* > 0xfff) return problem.set("map32_to_map16.txt, line {d}: {d} is more than 12 bits", .{ line_no, v.* });
        }
        try rows.append(a, row);
    }
    if (rows.items.len % 4 != 0) return problem.set("map32_to_map16.txt: the number of rows must be a multiple of 4", .{});
    return rows.items;
}

/// Dialogue files are one message per line, "number: text".
pub fn loadDialogue(a: std.mem.Allocator, dir: []const u8, name: []const u8, problem: *Problem) Error![]const []const u8 {
    const text = try readFile(a, dir, name, problem);
    var out: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw| {
        line_no += 1;
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0 and lines.peek() == null) break;
        const sep = std.mem.indexOf(u8, line, ": ") orelse return problem.set("{s}, line {d}: expected 'number: text'", .{ name, line_no });
        try out.append(a, line[sep + 2 ..]);
    }
    return out.items;
}

// --------------------------------------------------------- reading values

/// Where in the files a value came from, for messages.
const Ctx = struct {
    file: []const u8,
    what: []const u8 = "",
    problem: *Problem,

    fn fail(self: Ctx, comptime fmt: []const u8, args: anytype) error{BadInput} {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch fmt;
        return self.problem.set("{s}: {s}{s}{s}", .{ self.file, self.what, if (self.what.len != 0) ": " else "", msg });
    }

    fn get(self: Ctx, v: Value, key: []const u8) Error!Value {
        return v.get(key) orelse self.fail("missing '{s}'", .{key});
    }

    fn int(self: Ctx, v: Value, key: []const u8) Error!i64 {
        return (try self.get(v, key)).asInt() orelse self.fail("'{s}' should be a number", .{key});
    }

    fn str(self: Ctx, v: Value, key: []const u8) Error![]const u8 {
        return (try self.get(v, key)).asStr() orelse self.fail("'{s}' should be text", .{key});
    }

    fn list(self: Ctx, v: Value, key: []const u8) Error![]const Value {
        const got = try self.get(v, key);
        return got.asList() orelse self.fail("'{s}' should be a list", .{key});
    }

    fn at(self: Ctx, items: []const Value, i: usize) Error!i64 {
        if (i >= items.len) return self.fail("list is too short", .{});
        return items[i].asInt() orelse self.fail("expected a number", .{});
    }

    fn atStr(self: Ctx, items: []const Value, i: usize) Error![]const u8 {
        if (i >= items.len) return self.fail("list is too short", .{});
        return items[i].asStr() orelse self.fail("expected text", .{});
    }

    fn index(self: Ctx, table: []const []const u8, name: []const u8) Error!usize {
        for (table, 0..) |t, i| if (std.mem.eql(u8, t, name)) return i;
        return self.fail("unknown name '{s}'", .{name});
    }

    /// The last entry with this name, which is what inverting a dict does.
    fn named(self: Ctx, table: []const names.Named, name: []const u8) Error!u16 {
        var found: ?u16 = null;
        for (table) |t| if (std.mem.eql(u8, t.name, name)) {
            found = t.id;
        };
        return found orelse self.fail("unknown name '{s}'", .{name});
    }
};

fn toU8(ctx: Ctx, v: i64) Error!u8 {
    if (v < 0 or v > 255) return ctx.fail("{d} doesn't fit in a byte", .{v});
    return @intCast(v);
}

fn toI8(ctx: Ctx, v: i64) Error!u8 {
    if (v < -128 or v > 127) return ctx.fail("{d} doesn't fit in a signed byte", .{v});
    return @bitCast(@as(i8, @intCast(v)));
}

fn toU16(ctx: Ctx, v: i64) Error!u16 {
    if (v < 0 or v > 0xffff) return ctx.fail("{d} doesn't fit in 16 bits", .{v});
    return @intCast(v);
}

fn toI16(ctx: Ctx, v: i64) Error!u16 {
    if (v < -0x8000 or v > 0x7fff) return ctx.fail("{d} doesn't fit in a signed 16 bits", .{v});
    return @bitCast(@as(i16, @intCast(v)));
}

// ------------------------------------------------------------- output list

/// Appends assets in order, owning each one's data.
pub const Out = struct {
    alloc: std.mem.Allocator,
    list: *std.ArrayList(pack.Asset),

    fn bytes(self: Out, name: []const u8, kind: pack.Kind, data: []const u8) !void {
        try self.list.append(self.alloc, .{ .name = name, .kind = kind, .data = try self.alloc.dupe(u8, data) });
    }

    fn words(self: Out, name: []const u8, kind: pack.Kind, data: []const u16) !void {
        try self.bytes(name, kind, std.mem.sliceAsBytes(data));
    }
};

// ---------------------------------------------------------------- dungeons

fn putLayer(ctx: Ctx, data: *std.ArrayList(u8), a: std.mem.Allocator, objs: []const Value, doors: ?[]const Value) Error!?usize {
    for (objs) |o| {
        const n = try ctx.str(o, "n");
        const x = try ctx.int(o, "x");
        const y = try ctx.int(o, "y");
        var p: [3]u8 = undefined;
        if (indexOf(&names.kType0Names, n)) |index| {
            const s = try ctx.str(o, "s");
            if (s.len < 3 or s[1] != '*' or s[0] < '0' or s[0] > '3' or s[2] < '0' or s[2] > '3') return ctx.fail("size '{s}' should look like 2*1, each 0 to 3", .{s});
            p = .{ try toU8(ctx, x * 4 + (s[0] - '0')), try toU8(ctx, y * 4 + (s[2] - '0')), @intCast(index) };
        } else if (indexOf(&names.kType1Names, n)) |index| {
            p = .{ try toU8(ctx, x * 4 + @as(i64, @intCast(index & 3))), try toU8(ctx, y * 4 + @as(i64, @intCast((index >> 2) & 3))), @intCast((index >> 4) + 0xf8) };
        } else if (indexOf(&names.kType2Names, n)) |index| {
            // 111111xx xxxxyyyy yyiiiiii
            p = .{
                @intCast(0xfc + ((x >> 4) & 3)),
                @intCast(((x << 4) & 0xf0) | ((y >> 2) & 0x0f)),
                @intCast(@as(i64, @intCast(index)) | ((y << 6) & 0xc0)),
            };
        } else return ctx.fail("unknown object '{s}'", .{n});
        try data.appendSlice(a, &p);
    }
    var door_offset: ?usize = null;
    if (doors) |ds| {
        try data.appendSlice(a, &.{ 0xf0, 0xff });
        door_offset = data.items.len;
        for (ds) |d| {
            try data.append(a, try toU8(ctx, try ctx.int(d, "dir") | (try ctx.int(d, "pos")) << 4));
            try data.append(a, try toU8(ctx, try ctx.int(d, "type")));
        }
    }
    try data.appendSlice(a, &.{ 0xff, 0xff });
    return door_offset;
}

fn indexOf(table: []const []const u8, name: []const u8) ?usize {
    for (table, 0..) |t, i| if (std.mem.eql(u8, t, name)) return i;
    return null;
}

fn optionalList(v: Value, key: []const u8) ?[]const Value {
    const got = v.get(key) orelse return null;
    return got.asList();
}

/// Appends `little` to `big`, reusing any tail of `big` it starts with, and
/// returns where it begins. append_scan_bytes.
fn appendScanBytes(a: std.mem.Allocator, big: *std.ArrayList(u8), little: []const u8) !usize {
    var n: usize = little.len;
    while (true) : (n -= 1) {
        if (n == 0 or (big.items.len >= n and std.mem.eql(u8, big.items[big.items.len - n ..], little[0..n]))) {
            const offset = big.items.len - n;
            try big.appendSlice(a, little[n..]);
            return offset;
        }
    }
}

fn roomHeader(ctx: Ctx, y: Value) Error![14]u8 {
    const h = try ctx.get(y, "Header");
    var dest: [5][2]i64 = undefined;
    for ([_][]const u8{ "hole0_dest", "stair0_dest", "stair1_dest", "stair2_dest", "stair3_dest" }, 0..) |k, i| {
        const l = try ctx.list(h, k);
        dest[i] = .{ try ctx.at(l, 0), try ctx.at(l, 1) };
    }
    const p7 = dest[0][1] | dest[1][1] << 2 | dest[2][1] << 4 | dest[3][1] << 6;
    return .{
        try toU8(ctx, @as(i64, @intCast(try ctx.index(&names.kBg2Names, try ctx.str(h, "bg2")))) << 5 |
            @as(i64, @intCast(try ctx.index(&names.kCollisionNames, try ctx.str(h, "collision")))) << 2 |
            try ctx.int(h, "lights_out")),
        try toU8(ctx, try ctx.int(h, "palette")),
        try toU8(ctx, try ctx.int(h, "blockset")),
        try toU8(ctx, try ctx.int(h, "enemyblk")),
        @intCast(try ctx.index(&names.kEffectNames, try ctx.str(h, "effect"))),
        @intCast(try ctx.index(&names.kTagNames, try ctx.str(h, "tag0"))),
        @intCast(try ctx.index(&names.kTagNames, try ctx.str(h, "tag1"))),
        try toU8(ctx, p7),
        try toU8(ctx, dest[4][1]),
        try toU8(ctx, dest[0][0]),
        try toU8(ctx, dest[1][0]),
        try toU8(ctx, dest[2][0]),
        try toU8(ctx, dest[3][0]),
        try toU8(ctx, dest[4][0]),
    };
}

const Entrance = struct { v: Value, room: i64, ctx: Ctx };

/// The dungeon rooms and everything print_dungeon_rooms emits, in its order.
pub fn addDungeonRooms(files: *const Files, rom: Rom, out: Out, problem: *Problem) !void {
    var arena = std.heap.ArenaAllocator.init(out.alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var data: std.ArrayList(u8) = .empty;
    var offsets: [320]u16 = @splat(0);
    var door_offsets: [320]u16 = @splat(0);
    var headers: std.ArrayList(u8) = .empty;
    var header_offsets: [320]u16 = @splat(0);
    var chests: std.ArrayList(u8) = .empty;
    var tele: [320]u16 = @splat(0);
    var pits: std.ArrayList(u16) = .empty;
    var entrances: [133]?Entrance = @splat(null);
    var starts: [7]?Entrance = @splat(null);

    for (files.dungeon, 0..) |y, i| {
        const file = try std.fmt.allocPrint(a, "dungeon/dungeon-{d}.yaml", .{i});
        const ctx = Ctx{ .file = file, .problem = problem };
        const h = try ctx.get(y, "Header");
        const pit = try ctx.get(h, "pits_hurt_player");
        if (pit == .boolean and pit.boolean) try pits.append(a, @intCast(i));
        offsets[i] = @intCast(data.items.len);
        try data.append(a, try toU8(ctx, try ctx.int(h, "floor1") + try ctx.int(h, "floor2") * 16));
        try data.append(a, try toU8(ctx, try ctx.int(h, "layout") * 4 + try ctx.int(h, "start_quadrant")));
        _ = try putLayer(.{ .file = file, .what = "Layer1", .problem = problem }, &data, a, try ctx.list(y, "Layer1"), optionalList(y, "Layer1.doors"));
        _ = try putLayer(.{ .file = file, .what = "Layer2", .problem = problem }, &data, a, try ctx.list(y, "Layer2"), optionalList(y, "Layer2.doors"));
        const d = try putLayer(.{ .file = file, .what = "Layer3", .problem = problem }, &data, a, try ctx.list(y, "Layer3"), optionalList(y, "Layer3.doors") orelse &.{});
        door_offsets[i] = @intCast(d.?);
        header_offsets[i] = @intCast(try appendScanBytes(a, &headers, &try roomHeader(ctx, y)));
        tele[i] = try toU16(ctx, try ctx.int(h, "tele_msg"));
        for (try ctx.list(y, "Chests")) |c| {
            switch (c) {
                .int => |v| try chests.appendSlice(a, &.{ @truncate(i), @intCast(i >> 8), try toU8(ctx, v) }),
                .str => |s| {
                    if (!std.mem.endsWith(u8, s, "!")) return ctx.fail("chest '{s}' should be a number, or a number and ! for a big chest", .{s});
                    const v = std.fmt.parseInt(u8, s[0 .. s.len - 1], 10) catch return ctx.fail("chest '{s}' isn't a number", .{s});
                    try chests.appendSlice(a, &.{ @truncate(i), @intCast((i >> 8) | 0x80), v });
                },
                else => return ctx.fail("chests should be numbers", .{}),
            }
        }
        for (try ctx.list(y, "Entrances")) |e| {
            const idx = try ctx.int(e, "entrance_index");
            if (idx < 0 or idx >= 133) return ctx.fail("entrance_index {d} is out of range", .{idx});
            if (entrances[@intCast(idx)] != null) return ctx.fail("entrance {d} is defined twice", .{idx});
            entrances[@intCast(idx)] = .{ .v = e, .room = @intCast(i), .ctx = ctx };
        }
        if (optionalList(y, "StartingPoints")) |sps| for (sps) |e| {
            const idx = try ctx.int(e, "starting_point_index");
            if (idx < 0 or idx >= 7) return ctx.fail("starting_point_index {d} is out of range", .{idx});
            if (starts[@intCast(idx)] != null) return ctx.fail("starting point {d} is defined twice", .{idx});
            starts[@intCast(idx)] = .{ .v = e, .room = @intCast(i), .ctx = ctx };
        };
    }
    for (entrances, 0..) |e, i| if (e == null) return problem.set("Entrance {d} isn't defined in any dungeon room", .{i});
    for (starts, 0..) |e, i| if (e == null) return problem.set("Starting point {d} isn't defined in any dungeon room", .{i});

    try out.bytes("kDungeonRoom", .uint8, data.items);
    try out.words("kDungeonRoomOffs", .uint16, &offsets);
    try out.words("kDungeonRoomDoorOffs", .uint16, &door_offsets);
    try out.bytes("kDungeonRoomHeaders", .uint8, headers.items);
    try out.words("kDungeonRoomHeadersOffs", .uint16, &header_offsets);
    try out.bytes("kDungeonRoomChests", .uint8, chests.items);
    try out.words("kDungeonRoomTeleMsg", .uint16, &tele);
    try out.words("kDungeonPitsHurtPlayer", .uint16, pits.items);

    var all: [133]Entrance = undefined;
    for (entrances, 0..) |e, i| all[i] = e.?;
    try entranceInfo(a, out, &all, "kEntranceData_");
    var all_starts: [7]Entrance = undefined;
    for (starts, 0..) |e, i| all_starts[i] = e.?;
    try entranceInfo(a, out, &all_starts, "kStartingPoint_");

    inline for (.{ .{ "kDungeonRoomDefault", "kDungeonRoomDefaultOffs", "Default", 8, "dungeon/default_rooms.yaml" }, .{ "kDungeonRoomOverlay", "kDungeonRoomOverlayOffs", "Overlay", 19, "dungeon/overlay_rooms.yaml" } }) |f| {
        const src = if (f[3] == 8) files.default_rooms else files.overlay_rooms;
        const ctx = Ctx{ .file = f[4], .problem = problem };
        var d2: std.ArrayList(u8) = .empty;
        var offs: [f[3]]u16 = undefined;
        for (0..f[3]) |i| {
            offs[i] = @intCast(d2.items.len);
            const key = try std.fmt.allocPrint(a, "{s}{d}", .{ f[2], i });
            _ = try putLayer(ctx, &d2, a, try ctx.list(src, key), null);
        }
        try out.bytes(f[0], .uint8, d2.items);
        try out.words(f[1], .uint16, &offs);
    }

    try addDungeonSecrets(a, files, out, problem);

    const build_mod = @import("asset_build.zig");
    for ([_][]const u8{ "kDungAttrsForTile_Offs", "kDungAttrsForTile", "kMovableBlockDataInit", "kTorchDataInit", "kTorchDataJunk" }) |name| {
        for (build_mod.kMiscAssets) |m| {
            if (!std.mem.eql(u8, m.name, name)) continue;
            const d = try build_mod.buildMisc(out.alloc, rom, m);
            defer out.alloc.free(d);
            try out.bytes(m.name, m.kind, d);
        }
    }
}

fn addDungeonSecrets(a: std.mem.Allocator, files: *const Files, out: Out, problem: *Problem) !void {
    var result: std.ArrayList(u8) = .empty;
    try result.appendNTimes(a, 0, 640);
    var set: [320]bool = @splat(false);
    for (files.dungeon, 0..) |y, i| {
        const ctx = Ctx{ .file = try std.fmt.allocPrint(a, "dungeon/dungeon-{d}.yaml", .{i}), .what = "Secrets", .problem = problem };
        const secrets = try ctx.list(y, "Secrets");
        if (secrets.len == 0) continue;
        result.items[i * 2 + 0] = @truncate(result.items.len);
        result.items[i * 2 + 1] = @intCast(result.items.len >> 8);
        set[i] = true;
        for (secrets) |s| {
            const l = s.asList() orelse return ctx.fail("each secret should be [x, y, name]", .{});
            const pos = (try ctx.at(l, 0) + try ctx.at(l, 1) * 64) * 2;
            try result.appendSlice(a, &.{ @truncate(@as(u64, @intCast(pos))), @intCast(pos >> 8), @intCast(try ctx.named(&names.kSecretNames, try ctx.atStr(l, 2))) });
        }
        try result.appendSlice(a, &.{ 0xff, 0xff });
    }
    for (0..320) |i| {
        if (set[i]) continue;
        const l = result.items.len - 2;
        result.items[i * 2 + 0] = @truncate(l);
        result.items[i * 2 + 1] = @intCast(l >> 8);
    }
    try out.bytes("kDungeonSecrets", .uint8, result.items);
}

fn entranceInfo(a: std.mem.Allocator, out: Out, entrances: []const Entrance, comptime prefix: []const u8) !void {
    const n = entrances.len;
    var rooms = try a.alloc(u16, n);
    var rc = try a.alloc(u8, n * 8);
    var scroll_x = try a.alloc(u16, n);
    var scroll_y = try a.alloc(u16, n);
    var player_x = try a.alloc(u16, n);
    var player_y = try a.alloc(u16, n);
    var camera_x = try a.alloc(u16, n);
    var camera_y = try a.alloc(u16, n);
    var blockset = try a.alloc(u8, n);
    var floor = try a.alloc(u8, n);
    var palace = try a.alloc(u8, n);
    var doorway = try a.alloc(u8, n);
    var starting_bg = try a.alloc(u8, n);
    var quad1 = try a.alloc(u8, n);
    var quad2 = try a.alloc(u8, n);
    var door_settings = try a.alloc(u16, n);
    var entrance = try a.alloc(u8, n);
    var music = try a.alloc(u8, n);

    for (entrances, 0..) |e, i| {
        const ctx = e.ctx;
        const v = e.v;
        const room = e.room;
        rooms[i] = @intCast(room);
        const player = try ctx.list(v, "player_xy");
        const scroll = try ctx.list(v, "scroll_xy");
        const camera = try ctx.list(v, "camera_xy");
        const quads = try ctx.list(v, "quadrants");
        const q0 = try ctx.atStr(quads, 0);

        // relativeCoords: the scroll edges, put back on the room's grid.
        var rep: [8]i64 = @splat(0);
        if (optionalList(v, "repair_scroll_bounds")) |r| {
            for (&rep, 0..) |*x, k| x.* = try ctx.at(r, k);
        }
        const base_x = (room & 0xf) * 2;
        const base_y = (room >> 4) * 2;
        const ym = (try ctx.at(player, 1) & 0x100) >> 8;
        const xm = (try ctx.at(player, 0) & 0x100) >> 8;
        const qqq: i64 = if (room >= 242 and std.mem.eql(u8, q0, "single_x")) xm else 0;
        const l = [8]i64{ base_y + ym, base_y, base_y + ym, base_y + 1, base_x + xm, base_x + qqq, base_x + xm, base_x + qqq + 1 };
        for (0..8) |k| rc[i * 8 + k] = try toU8(ctx, l[k] + rep[k]);

        const room_x = (room & 0x00f) << 9;
        const room_y = (room & 0x1f0) << 5;
        scroll_x[i] = try toU16(ctx, try ctx.at(scroll, 0) + room_x);
        scroll_y[i] = try toU16(ctx, try ctx.at(scroll, 1) + room_y);
        player_x[i] = try toU16(ctx, try ctx.at(player, 0) + room_x);
        player_y[i] = try toU16(ctx, try ctx.at(player, 1) + room_y);
        camera_x[i] = try toU16(ctx, try ctx.at(camera, 0));
        camera_y[i] = try toU16(ctx, try ctx.at(camera, 1));
        blockset[i] = try toU8(ctx, try ctx.int(v, "blockset"));
        floor[i] = try toI8(ctx, try ctx.int(v, "floor"));
        const pal = try ctx.index(&names.kPalaceNames, try ctx.str(v, "palace"));
        palace[i] = if (pal == 0) 0xff else @intCast((pal - 1) * 2);
        doorway[i] = @bitCast(@as(i8, @intCast(try ctx.int(v, "doorway_orientation"))));
        starting_bg[i] = try toU8(ctx, try ctx.int(v, "plane") + try ctx.int(v, "ladder_level") * 16);
        const q1: u8 = if (std.mem.eql(u8, q0, "double_x")) 0x20 else if (std.mem.eql(u8, q0, "single_x")) 0 else return ctx.fail("quadrants[0] should be single_x or double_x", .{});
        const q1y = try ctx.atStr(quads, 1);
        quad1[i] = q1 + @as(u8, if (std.mem.eql(u8, q1y, "double_y")) 2 else if (std.mem.eql(u8, q1y, "single_y")) 0 else return ctx.fail("quadrants[1] should be single_y or double_y", .{}));
        const q2 = try ctx.atStr(quads, 2);
        quad2[i] = if (std.mem.eql(u8, q2, "upper_left")) 0 else if (std.mem.eql(u8, q2, "lower_left")) 2 else if (std.mem.eql(u8, q2, "upper_right")) 16 else if (std.mem.eql(u8, q2, "lower_right")) 18 else return ctx.fail("quadrants[2] '{s}' isn't a quadrant", .{q2});
        const door = try ctx.list(v, "house_exit_door");
        const kind = try ctx.atStr(door, 0);
        door_settings[i] = if (std.mem.eql(u8, kind, "none"))
            0
        else if (std.mem.eql(u8, kind, "none_0xffff"))
            0xffff
        else blk: {
            const top: u16 = if (std.mem.eql(u8, kind, "bombable")) 0x8000 else if (std.mem.eql(u8, kind, "wooden")) 0 else return ctx.fail("house_exit_door '{s}' isn't a door type", .{kind});
            break :blk top | @as(u16, @intCast(try ctx.at(door, 1))) << 1 | @as(u16, @intCast(try ctx.at(door, 2))) << 7;
        };
        if (comptime std.mem.eql(u8, prefix, "kStartingPoint_")) entrance[i] = try toU8(ctx, try ctx.int(v, "associated_entrance_index"));
        music[i] = @intCast(try ctx.named(&names.kMusicNames, try ctx.str(v, "music")));
    }
    try out.words(prefix ++ "rooms", .uint16, rooms);
    try out.bytes(prefix ++ "relativeCoords", .uint8, rc);
    try out.words(prefix ++ "scrollX", .uint16, scroll_x);
    try out.words(prefix ++ "scrollY", .uint16, scroll_y);
    try out.words(prefix ++ "playerX", .uint16, player_x);
    try out.words(prefix ++ "playerY", .uint16, player_y);
    try out.words(prefix ++ "cameraX", .uint16, camera_x);
    try out.words(prefix ++ "cameraY", .uint16, camera_y);
    try out.bytes(prefix ++ "blockset", .uint8, blockset);
    try out.bytes(prefix ++ "floor", .int8, floor);
    try out.bytes(prefix ++ "palace", .int8, palace);
    try out.bytes(prefix ++ "doorwayOrientation", .uint8, doorway);
    try out.bytes(prefix ++ "startingBg", .uint8, starting_bg);
    try out.bytes(prefix ++ "quadrant1", .uint8, quad1);
    try out.bytes(prefix ++ "quadrant2", .uint8, quad2);
    try out.words(prefix ++ "doorSettings", .uint16, door_settings);
    if (comptime std.mem.eql(u8, prefix, "kStartingPoint_")) try out.bytes(prefix ++ "entrance", .uint8, entrance);
    try out.bytes(prefix ++ "musicTrack", .uint8, music);
}

/// print_dungeon_sprites: kDungeonSprites and kDungeonSpriteOffs.
pub fn addDungeonSprites(files: *const Files, out: Out, problem: *Problem) !void {
    var arena = std.heap.ArenaAllocator.init(out.alloc);
    defer arena.deinit();
    const a = arena.allocator();
    var offsets: [320]u16 = @splat(0);
    var data: std.ArrayList(u8) = .empty;
    try data.appendSlice(a, &.{ 0, 0xff });
    for (files.dungeon, 0..) |y, i| {
        const ctx = Ctx{ .file = try std.fmt.allocPrint(a, "dungeon/dungeon-{d}.yaml", .{i}), .what = "Sprites", .problem = problem };
        const sort = try toU8(ctx, try ctx.int(try ctx.get(y, "Header"), "sort_sprites"));
        const sprites = try ctx.list(y, "Sprites");
        if (sprites.len == 0 and sort == 0) continue;
        offsets[i] = @intCast(data.items.len);
        try data.append(a, sort);
        for (sprites) |s| {
            const l = s.asList() orelse return ctx.fail("each sprite should be [x, y, upper or lower, name]", .{});
            const xx = try ctx.at(l, 0);
            const yy = try ctx.at(l, 1);
            if (xx < 0 or xx > 0x1f or yy < 0 or yy > 0x1f) return ctx.fail("sprite position {d}, {d} is outside 0 to 31", .{ xx, yy });
            const fl = try ctx.atStr(l, 2);
            const f: i64 = if (std.mem.eql(u8, fl, "upper")) 0 else if (std.mem.eql(u8, fl, "lower")) 1 else return ctx.fail("'{s}' should be upper or lower", .{fl});
            var name = try ctx.atStr(l, 3);
            // A subtype rides in the name, as in 6D.3-Rat.
            var ss: i64 = 0;
            if (name.len > 2 and name[2] == '.') {
                const j = std.mem.indexOfScalar(u8, name, '-') orelse return ctx.fail("sprite '{s}' has a subtype but no name", .{name});
                ss = std.fmt.parseInt(i64, name[3..j], 10) catch return ctx.fail("sprite '{s}' has a bad subtype", .{name});
                name = try std.fmt.allocPrint(a, "{s}{s}", .{ name[0..2], name[j..] });
            }
            const idx: i64 = @intCast(try ctx.index(&names.kSpriteNames, name));
            if (idx >= 0x100) {
                try data.appendSlice(a, &.{ @intCast(f << 7 | yy), @intCast(xx | 7 << 5), @intCast(idx & 0xff) });
            } else {
                try data.appendSlice(a, &.{ try toU8(ctx, f << 7 | (ss >> 3) << 5 | yy), try toU8(ctx, xx | (ss & 7) << 5), @intCast(idx) });
            }
            if (l.len == 5) {
                const drop = try ctx.atStr(l, 4);
                if (std.mem.eql(u8, drop, "drop_key")) {
                    try data.appendSlice(a, &.{ 0xfe, 0, 0xe4 });
                } else if (std.mem.eql(u8, drop, "drop_big_key")) {
                    try data.appendSlice(a, &.{ 0xfd, 0, 0xe4 });
                } else return ctx.fail("'{s}' should be drop_key or drop_big_key", .{drop});
            }
        }
        try data.append(a, 0xff);
    }
    try out.bytes("kDungeonSprites", .uint8, data.items);
    try out.words("kDungeonSpriteOffs", .uint16, &offsets);
}

/// print_map32_to_map16: the four packed quarters.
pub fn addMap32(files: *const Files, out: Out) !void {
    var arena = std.heap.ArenaAllocator.init(out.alloc);
    defer arena.deinit();
    const a = arena.allocator();
    var res: [4]std.ArrayList(u8) = @splat(.empty);
    var i: usize = 0;
    while (i < files.map32.len) : (i += 4) {
        for (0..4) |j| {
            const v = [4]u16{ files.map32[i][j], files.map32[i + 1][j], files.map32[i + 2][j], files.map32[i + 3][j] };
            try res[j].appendSlice(a, &.{
                @truncate(v[0]),                                    @truncate(v[1]), @truncate(v[2]), @truncate(v[3]),
                @intCast((v[0] >> 8) << 4 | (v[1] >> 8)), @intCast((v[2] >> 8) << 4 | (v[3] >> 8)),
            });
        }
    }
    try out.bytes("kMap32ToMap16_0", .uint8, res[0].items);
    try out.bytes("kMap32ToMap16_1", .uint8, res[1].items);
    try out.bytes("kMap32ToMap16_2", .uint8, res[2].items);
    try out.bytes("kMap32ToMap16_3", .uint8, res[3].items);
}

// --------------------------------------------------------------- overworld

/// A table being filled, where every entry must end up set. `awrite`
/// replicates a big area's value onto the three screens it also covers.
fn Table(comptime T: type) type {
    return struct {
        v: []T,
        set: []bool,
        name: []const u8,

        const Self = @This();

        fn init(a: std.mem.Allocator, name: []const u8, n: usize, fill: ?T) !Self {
            const self = Self{ .v = try a.alloc(T, n), .set = try a.alloc(bool, n), .name = name };
            @memset(self.v, fill orelse 0);
            @memset(self.set, fill != null);
            return self;
        }

        fn put(self: Self, key: usize, value: T) void {
            self.v[key] = value;
            self.set[key] = true;
        }

        fn awrite(self: Self, small: []const bool, area: usize, key: usize, value: T) void {
            self.put(key, value);
            if (area < 128 and !small[area]) {
                self.put(key + 1, value);
                self.put(key + 8, value);
                self.put(key + 9, value);
            }
        }

        fn check(self: Self, problem: *Problem) Error!void {
            for (self.set, 0..) |s, i| if (!s) return problem.set("The overworld files leave {s}[{d}] unset", .{ self.name, i });
        }
    };
}

fn loadOffs(ctx: Ctx, scroll: []const Value, load: []const Value) Error!u16 {
    const x = (try ctx.at(scroll, 0) >> 4) + try ctx.at(load, 0);
    const y = (try ctx.at(scroll, 1) >> 4) + try ctx.at(load, 1);
    return @intCast(((y & 0x3f) << 7) | ((x & 0x3f) << 1));
}

/// print_overworld_tables.
pub fn addOverworldTables(files: *const Files, rom: Rom, out: Out, problem: *Problem) !void {
    var arena = std.heap.ArenaAllocator.init(out.alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var ctxs: [160]Ctx = undefined;
    for (0..160) |i| ctxs[i] = .{ .file = try std.fmt.allocPrint(a, "overworld/overworld-{d}.yaml", .{i}), .problem = problem };

    var small: [192]bool = @splat(false);
    const is_small = try Table(u8).init(a, "kOverworldMapIsSmall", 192, 0);
    const aux = try Table(u8).init(a, "kOverworldAuxTileThemeIndexes", 128, null);
    const bgpal = try Table(u8).init(a, "kOverworldBgPalettes", 136, null);
    const sign = try Table(u16).init(a, "kOverworld_SignText", 128, null);
    const music = try Table(u8).init(a, "kOwMusicSets", 256, null);
    const music2 = try Table(u8).init(a, "kOwMusicSets2", 96, null);

    for (files.overworld, 0..) |yo, i| {
        const y = yo orelse continue;
        const ctx = ctxs[i];
        const h = try ctx.get(y, "Header");
        const size = try ctx.str(h, "size");
        small[i] = if (std.mem.eql(u8, size, "small")) true else if (std.mem.eql(u8, size, "big")) false else return ctx.fail("size should be small or big", .{});
        is_small.put(i, @intFromBool(small[i]));
    }
    for (files.overworld, 0..) |yo, i| {
        const y = yo orelse continue;
        const ctx = ctxs[i];
        const h = try ctx.get(y, "Header");
        if (i < 128) aux.awrite(&small, i, i, try toU8(ctx, try ctx.int(h, "gfx")));
        if (i < 136) bgpal.awrite(&small, i, i, try toU8(ctx, try ctx.int(h, "palette")));
        if (i < 128) sign.awrite(&small, i, i, try toU16(ctx, try ctx.int(h, "sign_text")));
        const m = try ctx.get(h, "music");
        const amb = try ctx.get(h, "ambient");
        const musicByte = struct {
            fn f(c: Ctx, mm: Value, aa: Value, tag: []const u8) Error!u8 {
                const track = try c.named(&names.kMusicNames, try c.str(mm, tag));
                const ambient = try c.named(&names.kAmbientSoundNames, try c.str(aa, tag));
                return @intCast(track | ambient << 4);
            }
        }.f;
        if (i < 64) {
            music.awrite(&small, i, i, try musicByte(ctx, m, amb, "beginning"));
            music.awrite(&small, i, i + 64, try musicByte(ctx, m, amb, "zelda"));
            music.awrite(&small, i, i + 128, try musicByte(ctx, m, amb, "sword"));
            music.awrite(&small, i, i + 192, try musicByte(ctx, m, amb, "agahnim"));
        } else if (i < 64 + 96) {
            music2.awrite(&small, i, i - 64, try musicByte(ctx, m, amb, "agahnim"));
        }
    }
    // The first loop only reaches big areas' quarters through awrite, so a
    // table that isn't small-checked for them is only complete afterwards.
    for (0..192) |i| is_small.set[i] = true;

    const bird_names = [_][]const u8{ "kBirdTravel_ScreenIndex", "kBirdTravel_Map16LoadSrcOff", "kBirdTravel_ScrollX", "kBirdTravel_ScrollY", "kBirdTravel_LinkXCoord", "kBirdTravel_LinkYCoord", "kBirdTravel_CameraXScroll", "kBirdTravel_CameraYScroll" };
    var bird: [8]Table(u16) = undefined;
    for (bird_names, 0..) |n, k| bird[k] = try Table(u16).init(a, n, 17, null);
    const bird_unk1 = try Table(u8).init(a, "kBirdTravel_Unk1", 17, null);
    const bird_unk3 = try Table(u8).init(a, "kBirdTravel_Unk3", 17, null);
    const whirl = try Table(u16).init(a, "kWhirlpoolAreas", 8, null);

    var next_whirlpool: usize = 0;
    for (files.overworld, 0..) |yo, i| {
        const y = yo orelse continue;
        const ctx = ctxs[i];
        for (try ctx.list(y, "Travel")) |t| {
            var j: usize = undefined;
            if (t.get("bird_travel_id")) |id| {
                j = @intCast(id.asInt() orelse return ctx.fail("bird_travel_id should be a number", .{}));
                if (j >= 9) return ctx.fail("bird_travel_id {d} should be 0 to 8", .{j});
            } else {
                if (next_whirlpool >= 8) return ctx.fail("more than 8 whirlpools", .{});
                whirl.put(next_whirlpool, try toU16(ctx, try ctx.int(t, "whirlpool_src_area")));
                j = next_whirlpool + 9;
                next_whirlpool += 1;
            }
            const base_x: i64 = @intCast((i & 7) << 9);
            const base_y: i64 = @intCast((i & 56) << 6);
            const scroll = try ctx.list(t, "scroll_xy");
            const xy = try ctx.list(t, "xy");
            const cam = try ctx.list(t, "camera_xy");
            const unk = try ctx.list(t, "unk");
            bird[0].put(j, @intCast(i));
            bird[1].put(j, try loadOffs(ctx, scroll, try ctx.list(t, "load_xy")));
            bird[2].put(j, try toU16(ctx, try ctx.at(scroll, 0) + base_x));
            bird[3].put(j, try toU16(ctx, try ctx.at(scroll, 1) + base_y));
            bird[4].put(j, try toU16(ctx, try ctx.at(xy, 0) + base_x));
            bird[5].put(j, try toU16(ctx, try ctx.at(xy, 1) + base_y));
            bird[6].put(j, try toU16(ctx, try ctx.at(cam, 0) + base_x));
            bird[7].put(j, try toU16(ctx, try ctx.at(cam, 1) + base_y));
            bird_unk1.put(j, try toI8(ctx, try ctx.at(unk, 0)));
            bird_unk3.put(j, try toI8(ctx, try ctx.at(unk, 1)));
        }
    }

    const ent_area = try Table(u16).init(a, "kOverworld_Entrance_Area", 129, null);
    const ent_pos = try Table(u16).init(a, "kOverworld_Entrance_Pos", 129, null);
    const ent_id = try Table(u8).init(a, "kOverworld_Entrance_Id", 129, null);
    for (files.overworld, 0..) |yo, i| {
        const y = yo orelse continue;
        const ctx = ctxs[i];
        for (try ctx.list(y, "Entrances")) |e| {
            const j: usize = @intCast(try ctx.int(e, "index"));
            if (j >= 129) return ctx.fail("entrance index {d} should be 0 to 128", .{j});
            if (ent_id.set[j]) return ctx.fail("entrance index {d} is used twice", .{j});
            ent_area.put(j, @intCast(i));
            ent_id.put(j, try toU8(ctx, try ctx.int(e, "entrance_id")));
            ent_pos.put(j, try toU16(ctx, try ctx.int(e, "x") << 1 | try ctx.int(e, "y") << 7));
        }
    }

    const hole_area = try Table(u16).init(a, "kFallHole_Area", 19, null);
    const hole_pos = try Table(u16).init(a, "kFallHole_Pos", 19, null);
    const hole_ent = try Table(u8).init(a, "kFallHole_Entrances", 19, null);
    const Hole = struct { entrance: i64, pos: i64, area: usize };
    var holes: std.ArrayList(Hole) = .empty;
    for (files.overworld, 0..) |yo, i| {
        const y = yo orelse continue;
        const ctx = ctxs[i];
        const hs = optionalList(y, "Holes") orelse continue;
        for (hs) |e| {
            try holes.append(a, .{
                .entrance = try ctx.int(e, "entrance_id"),
                .pos = try ctx.int(e, "x") << 1 | ((try ctx.int(e, "y") - 8) & 0x3f) << 7,
                .area = i,
            });
        }
    }
    // The Python sorts the (entrance, pos, area) tuples.
    std.mem.sort(Hole, holes.items, {}, struct {
        fn lt(_: void, x: Hole, y: Hole) bool {
            if (x.entrance != y.entrance) return x.entrance < y.entrance;
            if (x.pos != y.pos) return x.pos < y.pos;
            return x.area < y.area;
        }
    }.lt);
    if (holes.items.len > 19) return problem.set("The overworld files have more than 19 holes", .{});
    for (holes.items, 0..) |h, k| {
        hole_area.put(k, @intCast(h.area));
        hole_pos.put(k, @intCast(h.pos));
        hole_ent.put(k, @intCast(h.entrance));
    }

    const exit_screen = try Table(u8).init(a, "kExitData_ScreenIndex", 79, null);
    const exit_names = [_][]const u8{ "kExitDataRooms", "kExitData_Map16LoadSrcOff", "kExitData_ScrollX", "kExitData_ScrollY", "kExitData_XCoord", "kExitData_YCoord", "kExitData_CameraXScroll", "kExitData_CameraYScroll" };
    var exits: [8]Table(u16) = undefined;
    for (exit_names, 0..) |n, k| exits[k] = try Table(u16).init(a, n, 79, null);
    const normal_door = try Table(u16).init(a, "kExitData_NormalDoor", 79, 0);
    const fancy_door = try Table(u16).init(a, "kExitData_FancyDoor", 79, 0);
    const exit_unk1 = try Table(u8).init(a, "kExitData_Unk1", 79, null);
    const exit_unk3 = try Table(u8).init(a, "kExitData_Unk3", 79, null);

    const sp_u16 = [_][]const u8{ "kSpExit_Top", "kSpExit_Bottom", "kSpExit_Left", "kSpExit_Right" };
    const sp_i16 = [_][]const u8{ "kSpExit_Tab4", "kSpExit_Tab5", "kSpExit_Tab6", "kSpExit_Tab7" };
    const sp_u8 = [_][]const u8{ "kSpExit_Dir", "kSpExit_SprGfx", "kSpExit_AuxGfx", "kSpExit_PalBg", "kSpExit_PalSpr" };
    var sp_w: [4]Table(u16) = undefined;
    for (sp_u16, 0..) |n, k| sp_w[k] = try Table(u16).init(a, n, 16, 0);
    var sp_s: [4]Table(u16) = undefined;
    for (sp_i16, 0..) |n, k| sp_s[k] = try Table(u16).init(a, n, 16, 0);
    const sp_edge = try Table(u16).init(a, "kSpExit_LeftEdgeOfMap", 16, 0);
    var sp_b: [5]Table(u8) = undefined;
    for (sp_u8, 0..) |n, k| sp_b[k] = try Table(u8).init(a, n, 16, 0);

    for (files.overworld, 0..) |yo, i| {
        const y = yo orelse continue;
        const ctx = ctxs[i];
        for (try ctx.list(y, "Exits")) |e| {
            const j: usize = @intCast(try ctx.int(e, "index"));
            if (j >= 79) return ctx.fail("exit index {d} should be 0 to 78", .{j});
            if (exit_screen.set[j]) return ctx.fail("exit index {d} is used twice", .{j});
            const base_x: i64 = @intCast((i & 7) << 9);
            const base_y: i64 = @intCast((i & 56) << 6);
            const scroll = try ctx.list(e, "scroll_xy");
            const xy = try ctx.list(e, "xy");
            const cam = try ctx.list(e, "camera_xy");
            const unk = try ctx.list(e, "unk");
            const room = try ctx.int(e, "room");
            exit_screen.put(j, @intCast(i));
            exits[0].put(j, try toU16(ctx, room));
            exits[1].put(j, try loadOffs(ctx, scroll, try ctx.list(e, "load_xy")));
            exits[2].put(j, try toU16(ctx, try ctx.at(scroll, 0) + base_x));
            exits[3].put(j, try toU16(ctx, try ctx.at(scroll, 1) + base_y));
            exits[4].put(j, try toU16(ctx, try ctx.at(xy, 0) + base_x));
            exits[5].put(j, try toU16(ctx, try ctx.at(xy, 1) + base_y));
            exits[6].put(j, try toU16(ctx, try ctx.at(cam, 0) + base_x));
            exits[7].put(j, try toU16(ctx, try ctx.at(cam, 1) + base_y));
            exit_unk1.put(j, try toI8(ctx, try ctx.at(unk, 0)));
            exit_unk3.put(j, try toI8(ctx, try ctx.at(unk, 1)));
            if (optionalList(e, "door")) |door| {
                const kind = try ctx.atStr(door, 0);
                const bits = @as(u16, @intCast(try ctx.at(door, 1))) << 1 | @as(u16, @intCast(try ctx.at(door, 2))) << 7;
                if (std.mem.eql(u8, kind, "bombable") or std.mem.eql(u8, kind, "wooden")) {
                    normal_door.put(j, bits | (if (std.mem.eql(u8, kind, "bombable")) @as(u16, 0x8000) else 0));
                } else if (std.mem.eql(u8, kind, "palace") or std.mem.eql(u8, kind, "sanctuary")) {
                    fancy_door.put(j, bits | (if (std.mem.eql(u8, kind, "palace")) @as(u16, 0x8000) else 0));
                } else return ctx.fail("door type '{s}' isn't bombable, wooden, palace or sanctuary", .{kind});
            }
            if (e.get("special_exit")) |se| {
                if (room < 0x180 or room >= 0x190) return ctx.fail("a special exit needs a room from 0x180 to 0x18f", .{});
                const k: usize = @intCast(room - 0x180);
                sp_b[0].put(k, try toU8(ctx, try ctx.int(se, "dir") * 2));
                sp_b[1].put(k, try toU8(ctx, try ctx.int(se, "spr_gfx")));
                sp_b[2].put(k, try toU8(ctx, try ctx.int(se, "aux_gfx")));
                sp_b[3].put(k, try toU8(ctx, try ctx.int(se, "pal_bg")));
                sp_b[4].put(k, try toU8(ctx, try ctx.int(se, "pal_spr")));
                sp_w[0].put(k, try toU16(ctx, try ctx.int(se, "top")));
                sp_w[1].put(k, try toU16(ctx, try ctx.int(se, "bottom")));
                sp_w[2].put(k, try toU16(ctx, try ctx.int(se, "left")));
                sp_w[3].put(k, try toU16(ctx, try ctx.int(se, "right")));
                sp_edge.put(k, try toU16(ctx, try ctx.int(se, "left_edge_of_map")));
                sp_s[0].put(k, try toI16(ctx, try ctx.int(se, "unk4")));
                sp_s[1].put(k, try toI16(ctx, try ctx.int(se, "unk5")));
                sp_s[2].put(k, try toI16(ctx, try ctx.int(se, "unk6")));
                sp_s[3].put(k, try toI16(ctx, try ctx.int(se, "unk7")));
            }
        }
    }

    const secrets_offs = try Table(u16).init(a, "kOverworldSecrets_Offs", 128, null);
    var secrets: std.ArrayList(u8) = .empty;
    for (files.overworld, 0..) |yo, i| {
        const y = yo orelse continue;
        const ctx = ctxs[i];
        const items = try ctx.list(y, "Items");
        if (items.len == 0) continue;
        if (i >= 128) return ctx.fail("only areas below 128 can have items", .{});
        secrets_offs.awrite(&small, i, i, @intCast(secrets.items.len));
        for (items) |it| {
            const l = it.asList() orelse return ctx.fail("each item should be [x, y, name]", .{});
            const pos: u16 = @intCast(try ctx.at(l, 0) << 1 | try ctx.at(l, 1) << 7);
            try secrets.appendSlice(a, &.{ @truncate(pos), @intCast(pos >> 8), @intCast(try ctx.named(&names.kSecretNames, try ctx.atStr(l, 2))) });
        }
        try secrets.appendSlice(a, &.{ 0xff, 0xff });
    }
    for (0..128) |i| if (!secrets_offs.set[i]) secrets_offs.put(i, @intCast(secrets.items.len - 2));

    const spr_offs = try Table(u16).init(a, "kOverworldSpriteOffs", 144 * 3, 0);
    var sprites: std.ArrayList(u8) = .empty;
    const spr_gfx = try Table(u8).init(a, "kOverworldSpriteGfx", 256, null);
    const spr_pal = try Table(u8).init(a, "kOverworldSpritePalettes", 256, null);
    try sprites.append(a, 0xff);
    const Range = struct { start: usize, end: usize, key: []const u8, stages: []const usize, info_stage: usize };
    for ([_]Range{
        .{ .start = 0, .end = 64, .key = "Sprites.Beginning", .stages = &.{0}, .info_stage = 0 },
        .{ .start = 0, .end = 64, .key = "Sprites.FirstPart", .stages = &.{1}, .info_stage = 1 },
        .{ .start = 0, .end = 64, .key = "Sprites.SecondPart", .stages = &.{2}, .info_stage = 2 },
        .{ .start = 64, .end = 144, .key = "Sprites", .stages = &.{ 1, 2 }, .info_stage = 3 },
    }) |r| {
        for (files.overworld, 0..) |yo, i| {
            const y = yo orelse continue;
            if (i < r.start or i >= r.end) continue;
            const ctx = ctxs[i];
            const stage = try ctx.get(y, r.key);
            if (i < 128) {
                const info = try ctx.get(stage, "info");
                spr_gfx.awrite(&small, i, (i & 63) + r.info_stage * 64, try toU8(ctx, try ctx.int(info, "gfx")));
                spr_pal.awrite(&small, i, (i & 63) + r.info_stage * 64, try toU8(ctx, try ctx.int(info, "palette")));
            }
            const list = try ctx.list(stage, "sprites");
            if (list.len == 0) continue;
            for (r.stages) |s| spr_offs.put(s * 144 + i, @intCast(sprites.items.len));
            for (list) |e| {
                const l = e.asList() orelse return ctx.fail("each sprite should be [x, y, name]", .{});
                try sprites.appendSlice(a, &.{ try toU8(ctx, try ctx.at(l, 1)), try toU8(ctx, try ctx.at(l, 0)), @intCast(try ctx.index(&names.kSpriteNames, try ctx.atStr(l, 2))) });
            }
            try sprites.append(a, 0xff);
        }
    }

    // A.write(), in the order the tables were added.
    try emitU8(out, problem, is_small);
    try emitU8(out, problem, aux);
    try emitU8(out, problem, bgpal);
    try emitU16(out, problem, sign);
    try emitU8(out, problem, music);
    try emitU8(out, problem, music2);
    for (bird) |t| try emitU16(out, problem, t);
    try emitKind(out, problem, bird_unk1, .int8);
    try emitKind(out, problem, bird_unk3, .int8);
    try emitU16(out, problem, whirl);
    try emitU16(out, problem, ent_area);
    try emitU16(out, problem, ent_pos);
    try emitU8(out, problem, ent_id);
    try emitU16(out, problem, hole_area);
    try emitU16(out, problem, hole_pos);
    try emitU8(out, problem, hole_ent);
    try emitU8(out, problem, exit_screen);
    for (exits) |t| try emitU16(out, problem, t);
    try emitU16(out, problem, normal_door);
    try emitU16(out, problem, fancy_door);
    try emitKind(out, problem, exit_unk1, .int8);
    try emitKind(out, problem, exit_unk3, .int8);
    for (sp_w) |t| try emitU16(out, problem, t);
    for (sp_s) |t| try emitKindW(out, problem, t, .int16);
    try emitU16(out, problem, sp_edge);
    for (sp_b) |t| try emitU8(out, problem, t);
    try emitU16(out, problem, secrets_offs);
    try out.bytes("kOverworldSecrets", .uint8, secrets.items);
    try emitU16(out, problem, spr_offs);
    try out.bytes("kOverworldSprites", .uint8, sprites.items);
    try emitU8(out, problem, spr_gfx);
    try emitU8(out, problem, spr_pal);

    const build_mod = @import("asset_build.zig");
    for ([_][]const u8{ "kMap8DataToTileAttr", "kSomeTileAttr" }) |name| {
        for (build_mod.kMiscAssets) |m| {
            if (!std.mem.eql(u8, m.name, name)) continue;
            const d = try build_mod.buildMisc(out.alloc, rom, m);
            defer out.alloc.free(d);
            try out.bytes(m.name, m.kind, d);
        }
    }
}

fn emitU8(out: Out, problem: *Problem, t: Table(u8)) !void {
    try emitKind(out, problem, t, .uint8);
}
fn emitU16(out: Out, problem: *Problem, t: Table(u16)) !void {
    try emitKindW(out, problem, t, .uint16);
}
fn emitKind(out: Out, problem: *Problem, t: Table(u8), kind: pack.Kind) !void {
    try t.check(problem);
    try out.bytes(t.name, kind, t.v);
}
fn emitKindW(out: Out, problem: *Problem, t: Table(u16), kind: pack.Kind) !void {
    try t.check(problem);
    try out.words(t.name, kind, t.v);
}

// ------------------------------------------------------------------- tests

test "exporting the ROM and building from the files gives the standard assets" {
    const testing = std.testing;
    const alloc = testing.allocator;
    if (!fileio.exists("zelda3.sfc")) return error.SkipZigTest;
    var rom = try Rom.load(alloc, "zelda3.sfc");
    defer rom.deinit();
    if (rom.language != .us) return error.SkipZigTest;

    // A folder of our own, since more than one test binary can run at once.
    const pid: u64 = if (@import("builtin").os.tag == .windows) std.os.windows.GetCurrentProcessId() else @intCast(std.c.getpid());
    var dir_buf: [64]u8 = undefined;
    const dir = try std.fmt.bufPrintZ(&dir_buf, "zig-cache-export-{d}", .{pid});
    try fileio.makeDir(dir.ptr);
    try @import("asset_export.zig").exportFiles(alloc, rom, dir, null);

    var problem = Problem{};
    var files = Files.load(alloc, rom, dir, .{}, &problem) catch |e| {
        std.debug.print("{s}\n", .{problem.text()});
        return e;
    };
    defer files.deinit();
    const asset_all = @import("asset_all.zig");
    var assets = try asset_all.buildFrom(alloc, rom, &files, &.{}, &problem);
    defer assets.deinit();
    const data = try pack.write(alloc, assets.items);
    defer alloc.free(data);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    try testing.expectEqualStrings(asset_all.kReferenceDigest, &std.fmt.bytesToHex(digest, .lower));

    // The sprite sheets read back from their PNGs are the ROM's own sheets.
    var with_sheets = try Files.load(alloc, rom, dir, .{ .sprites_from_png = true }, &problem);
    defer with_sheets.deinit();
    for (with_sheets.sprite_sheets.?, 0..) |sheet, t| {
        const want = try sheets_mod.unpackedSheet(alloc, rom, t);
        defer alloc.free(want);
        try testing.expectEqualSlices(u8, want, &(sheet orelse return error.SheetMissing));
    }
    removeTree(dir);
}

/// Tidies up the test's folder. Best effort: a leftover folder is harmless.
fn removeTree(dir: []const u8) void {
    var buf: [256]u8 = undefined;
    for (0..320) |i| {
        const p = std.fmt.bufPrintZ(&buf, "{s}/dungeon/dungeon-{d}.yaml", .{ dir, i }) catch return;
        _ = fileio.remove(p.ptr);
    }
    for (0..160) |i| {
        const p = std.fmt.bufPrintZ(&buf, "{s}/overworld/overworld-{d}.yaml", .{ dir, i }) catch return;
        _ = fileio.remove(p.ptr);
    }
    for ([_][]const u8{ "dungeon/default_rooms.yaml", "dungeon/overlay_rooms.yaml", "dialogue.txt", "map32_to_map16.txt", "linksprite.png", "font.png", "hud_icons.png" }) |f| {
        const p = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ dir, f }) catch return;
        _ = fileio.remove(p.ptr);
    }
    for (sheets_mod.kGroups) |g| {
        const p = std.fmt.bufPrintZ(&buf, "{s}/sprites/sprites_{c}.png", .{ dir, g }) catch return;
        _ = fileio.remove(p.ptr);
    }
    {
        const p = std.fmt.bufPrintZ(&buf, "{s}/sprites/all_sheets.png", .{dir}) catch return;
        _ = fileio.remove(p.ptr);
    }
    for ([_][]const u8{ "/dungeon", "/overworld", "/sprites", "" }) |sub| {
        const p = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ dir, sub }) catch return;
        fileio.removeDir(p.ptr);
    }
}
