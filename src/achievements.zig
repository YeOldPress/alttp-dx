//! Achievements, watched for while the game plays.
//!
//! Nearly all of them are read straight out of the save data the game keeps
//! in work RAM: what's in the inventory, how far the story has got, which
//! bosses' rooms are marked beaten, and the flags the tracker reads for who
//! has given Link what. The few that are about how something was done, a boss
//! without being hit, Ganon with three hearts, are watched for a frame at a
//! time. None of it changes anything the game does.
//!
//! Unlocking one shows a banner at the top of the screen, in the inventory's
//! style with the item's own icon, and saves the list straight away. A pile
//! at once, from loading a file that was already far along, gets one banner
//! that says how many.
//!
//! Cheats stop achievements until the game is back at the title or the file
//! select. Snapshots don't: they're how a game is picked up again as often
//! as how it's worked on. The attract mode's demos, which play with a save of
//! their own, never count.
const std = @import("std");
const vars = @import("variables.zig");
const gfx = @import("game_gfx.zig");
const list = @import("achievement_list.zig");

const Id = list.Id;

/// Off for --render and the comparison against the original, which shouldn't
/// be writing anyone's achievements file.
pub var enabled = false;

var g_unlocked: list.Unlocked = .{};
/// A cheat was used since the last title or file select.
var g_assisted = false;

pub fn init(alloc: std.mem.Allocator) void {
    g_unlocked = list.Unlocked.load(alloc);
    enabled = true;
}

pub fn unlocked() list.Unlocked {
    return g_unlocked;
}

/// A cheat used: walking through walls, filling health, and so on.
pub fn noteAssist() void {
    g_assisted = true;
}

// ------------------------------------------------------------- the checks

fn saveByte(off: u16) u8 {
    return vars.g_ram[0xF000 + @as(usize, off)];
}

fn flag(off: u16, mask: u8) bool {
    return saveByte(off) & mask == mask;
}

/// The boss rooms of the ten dungeons with a pendant or crystal, as the
/// room numbers their beaten flags are kept under.
const BossRoom = struct { id: Id, room: u16 };
const kBossRooms = [_]BossRoom{
    .{ .id = .eastern, .room = 0xc8 },
    .{ .id = .desert, .room = 0x33 },
    .{ .id = .hera, .room = 0x07 },
    .{ .id = .darkness, .room = 0x5a },
    .{ .id = .swamp, .room = 0x06 },
    .{ .id = .skull, .room = 0x29 },
    .{ .id = .thieves, .room = 0xac },
    .{ .id = .ice, .room = 0xde },
    .{ .id = .mire, .room = 0x90 },
    .{ .id = .turtle, .room = 0xa4 },
};

/// Set once the boss is gone and its prize taken: the room's 0x8000 state
/// bit, which the save keeps four bits down.
fn bossBeaten(room: u16) bool {
    return vars.save_dung_info[room] & 0x0800 != 0;
}

fn hasEveryItem() bool {
    const items = [_]u8{
        vars.link_item_bow.*,          vars.link_item_boomerang.*,      vars.link_item_hookshot.*,
        vars.link_item_mushroom.*,     vars.link_item_fire_rod.*,       vars.link_item_ice_rod.*,
        vars.link_item_bombos_medallion.*, vars.link_item_ether_medallion.*, vars.link_item_quake_medallion.*,
        vars.link_item_torch.*,        vars.link_item_hammer.*,         vars.link_item_flute.*,
        vars.link_item_bug_net.*,      vars.link_item_book_of_mudora.*, vars.link_item_bottle_index.*,
        vars.link_item_cane_somaria.*, vars.link_item_cane_byrna.*,     vars.link_item_cape.*,
        vars.link_item_mirror.*,
    };
    for (items) |item| if (item == 0) return false;
    return true;
}

/// A bottle holding this: 7 a bee, 8 a good bee.
fn hasBottled(what: u8) bool {
    for (0..4) |i| if (vars.link_bottle_info[i] == what) return true;
    return false;
}

fn bottleCount() usize {
    var n: usize = 0;
    for (0..4) |i| n += @intFromBool(vars.link_bottle_info[i] != 0);
    return n;
}

/// Whether what's in the save already says it's done.
fn inSave(id: Id) bool {
    for (kBossRooms) |b| if (b.id == id) return bossBeaten(b.room);
    return switch (id) {
        .uncle => vars.link_sword_type.* >= 1 and vars.link_sword_type.* <= 4,
        .zelda => vars.sram_progress_indicator.* >= 2,
        .master_sword => vars.link_sword_type.* >= 2 and vars.link_sword_type.* <= 4,
        .agahnim => vars.sram_progress_indicator.* >= 3,
        // The ending sets it too, on its way to the credits.
        .dark_world => vars.savegame_is_darkworld.* != 0 and vars.main_module_index.* < 25,

        .heart_piece => vars.link_heart_pieces.* != 0,
        .twenty_hearts => vars.link_health_capacity.* >= 160,
        .bottles => bottleCount() == 4,
        .medallions => vars.link_item_bombos_medallion.* != 0 and vars.link_item_ether_medallion.* != 0 and
            vars.link_item_quake_medallion.* != 0,
        .all_items => hasEveryItem(),
        .silver_arrows => vars.link_item_bow.* >= 3,
        .golden_sword => vars.link_sword_type.* == 4,
        .mirror_shield => vars.link_shield_type.* == 3,
        .red_mail => vars.link_armor.* == 2,
        .titans_mitt => vars.link_item_gloves.* == 2,
        .max_capacity => vars.link_bomb_upgrades.* >= 7 and vars.link_arrow_upgrades.* >= 7,
        .rupees => vars.link_rupees_actual.* >= 999,

        .witch => vars.link_item_mushroom.* == 2,
        .mad_batter => vars.link_magic_consumption.* >= 1,
        .flute => vars.link_item_flute.* == 3,
        .smiths => vars.link_sword_type.* >= 3 and vars.link_sword_type.* <= 4,
        .fairy_boomerang => vars.link_item_boomerang.* == 2,
        // What the people who hand these out set once they have. Only seeds
        // keep a flag for most of them, so the rest go by what they give:
        // the tablets their medallions, the sick boy the net, Stumpy the
        // shovel (or the flute it digs up), Sahasrahla the boots.
        .purple_chest => flag(0x3c9, 0x10),
        .tablets => vars.link_item_ether_medallion.* != 0 and vars.link_item_bombos_medallion.* != 0,
        .hobo => flag(0x3c9, 0x01),
        .sick_kid => vars.link_item_bug_net.* != 0,
        .stumpy => vars.link_item_flute.* != 0,
        .zora => vars.link_item_flippers.* != 0,
        .sahasrahla => vars.link_item_boots.* != 0,
        .bee => hasBottled(7) or hasBottled(8),

        else => false,
    };
}

/// Modules where a save file is loaded and being played: past the file
/// select, and not the attract mode's demos.
fn inPlay(module: u8) bool {
    return module >= 6 and module != 20 and module <= 27;
}

// ------------------------------------------------------------- watching

const kGanonRoom = 0x00;

/// The boss room Link is in, and whether he's been hit since coming in.
var g_room: ?u16 = null;
var g_room_boss_was_beaten = false;
var g_hit = false;
var g_last_health: u8 = 0;
var g_last_module: u8 = 0;

/// Runs after each frame of the port's own game.
pub fn afterFrame() void {
    if (!enabled) return;
    const module = vars.main_module_index.*;
    defer g_last_module = module;
    if (!inPlay(module)) {
        // The title or the file select: a fresh start.
        if (module <= 5) g_assisted = false;
        g_room = null;
        return;
    }
    if (g_assisted) return;

    watchBossRoom(module);

    // Ganon down: the game falls into the Triforce's room.
    if (module == 25 and g_last_module != 25) {
        unlock(.ganon);
        if (g_room == kGanonRoom and !g_hit) unlock(.flawless_ganon);
        if (vars.link_health_capacity.* <= 24) unlock(.three_hearts);
        if (vars.link_armor.* == 0) unlock(.green_tunic);
    }
    // Agahnim's second fall, when Ganon comes out of him.
    if (module == 24) unlock(.agahnim2);
    // The credits add up the deaths as they start, all of them, in every
    // dungeon and out of them; until then it's 0xffff.
    if (module == 26 and vars.death_var2.* == 0) unlock(.deathless);

    for (list.kList) |ach| {
        if (!g_unlocked.has(ach.id) and inSave(ach.id)) unlock(ach.id);
    }
}

fn watchBossRoom(module: u8) void {
    const health = vars.link_health_current.*;
    defer g_last_health = health;
    const indoors = module == 7 or module == 25;
    const room = vars.dungeon_room_index.*;
    if (!indoors or !isBossRoom(room)) {
        if (module != 25) g_room = null;
        return;
    }
    if (g_room != room) {
        g_room = room;
        g_hit = false;
        g_room_boss_was_beaten = room != kGanonRoom and bossBeaten(room);
        return;
    }
    if (health < g_last_health) g_hit = true;
    if (room != kGanonRoom and !g_room_boss_was_beaten and bossBeaten(room)) {
        g_room_boss_was_beaten = true;
        if (!g_hit) unlock(.untouchable);
    }
}

fn isBossRoom(room: u16) bool {
    if (room == kGanonRoom) return true;
    for (kBossRooms) |b| if (b.room == room) return true;
    return false;
}

fn unlock(id: Id) void {
    if (g_unlocked.has(id)) return;
    g_unlocked.set.insert(id);
    g_unlocked.save() catch |err| std.debug.print("Could not write {s}: {s}\n", .{ list.kPath, @errorName(err) });
    announce(id);
}

// ------------------------------------------------------------- the banner

const Banner = struct {
    id: Id,
    /// More than one arrived together: say how many instead.
    count: usize = 1,
};

var g_queue: [8]Banner = undefined;
var g_queue_len: usize = 0;
var g_frame: u32 = 0;
/// Frames into the banner on show.
var g_shown_for: u32 = 0;
/// When the last one was queued, so a pile unlocked in the same few frames
/// becomes one banner.
var g_last_queued: u32 = 0;

const kSlide = 12;
const kHold = 210;
const kBoxH = 40;
/// A pile that arrives within this many frames of each other is one banner.
const kTogether = 30;

fn announce(id: Id) void {
    // Joined onto the last banner when it's still waiting and recent.
    if (g_queue_len > 0 and g_frame -% g_last_queued < kTogether) {
        const last = &g_queue[g_queue_len - 1];
        if (g_queue_len > 1 or g_shown_for < kSlide) {
            last.count += 1;
            g_last_queued = g_frame;
            return;
        }
    }
    if (g_queue_len == g_queue.len) {
        g_queue[g_queue_len - 1].count += 1;
        return;
    }
    g_queue[g_queue_len] = .{ .id = id };
    g_queue_len += 1;
    g_last_queued = g_frame;
    if (g_queue_len == 1) {
        g_shown_for = 0;
        vars.sound_effect_2.* = 0x1b;
    }
}

/// Whether something is in the way of the banner, the Select menu say,
/// which it waits for.
pub var hidden = false;

/// Draws the banner, if one's showing, over a finished frame. Called every
/// frame; it's what keeps the banner's time.
pub fn drawOver(pixels: [*]u8, pitch: usize, width: usize, height: usize, scale: usize) void {
    g_frame +%= 1;
    if (g_queue_len == 0 or hidden) return;
    const total = kSlide * 2 + kHold;
    if (g_shown_for >= total) {
        std.mem.copyForwards(Banner, g_queue[0 .. g_queue_len - 1], g_queue[1..g_queue_len]);
        g_queue_len -= 1;
        g_shown_for = 0;
        if (g_queue_len == 0) return;
        vars.sound_effect_2.* = 0x1b;
    }
    const t = g_shown_for;
    g_shown_for += 1;
    const offset: i32 = if (t < kSlide)
        @divTrunc(@as(i32, @intCast(kSlide - t)) * (kBoxH + 4), kSlide)
    else if (t >= kSlide + kHold)
        @divTrunc(@as(i32, @intCast(t - kSlide - kHold)) * (kBoxH + 4), kSlide)
    else
        0;
    gfx.loadHudTiles();
    const cv = gfx.Canvas{ .pixels = pixels, .pitch = pitch, .width = width, .height = height, .scale = scale, .oy = -offset };
    drawBanner(cv, g_queue[0]);
}

fn textColors(body: u32) [3]u32 {
    return .{ gfx.cgramColor(25), body, gfx.cgramColor(27) };
}

fn drawBanner(cv: gfx.Canvas, b: Banner) void {
    const ach = list.get(b.id);
    cv.box(16, 4, 28, 5, 3);
    cv.icon(30, 16, ach.icon);
    if (b.count > 1) {
        var buf: [40]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "{d} Achievements Unlocked", .{b.count}) catch "";
        _ = cv.text(56, 10, line, textColors(0xf8d830));
        _ = cv.text(56, 24, "See them all in the menu.", textColors(gfx.cgramColor(26)));
    } else {
        _ = cv.text(56, 10, "Achievement Unlocked", textColors(0xf8d830));
        _ = cv.text(56, 24, ach.name, textColors(gfx.cgramColor(26)));
    }
}
