//! Booting the game straight into a dungeon room from power-on, for the
//! start menu's pictures of the graphics settings: `ROOM=n zelda3 --render -`
//! (main.zig).
//!
//! It goes the way the game itself goes into a file saved in a dungeon: the
//! intro sets up memory and hands over to the file select at once, which
//! loads a made-up save (in memory only; saves/sram.dat is never read or
//! written) and goes on into entrance n, as continuing a dungeon save does
//! (messaging.dungeonContinueEntrance). Graphics, the HUD and Link are all
//! loaded the game's own way, so the room looks as it does in play.
const std = @import("std");

/// The dungeon entrance to go into, while booting for a picture.
pub var entrance: ?u8 = null;
/// Whether the made-up file is in the Dark World, for its dungeons.
pub var dark_world = false;
/// A room of the entrance's dungeon to be in instead of the entrance's own,
/// for one no entrance leads straight into (dungeon.zig moves everything
/// over by the rooms between them).
pub var room: ?u16 = null;
/// Outdoors instead: on the overworld where room n's exit leads, as leaving
/// it would put Link, for the overworld's pictures. Rooms from 0x100 up
/// (caves and houses) don't say where they lead, only dungeons' do.
pub var outside: ?u16 = null;
/// Outdoors where the flute's bird would drop Link (0 to 7) instead: these
/// can be anywhere, Lake Hylia among them.
pub var bird: ?c_int = null;

/// A place on the overworld and the view of it, as the flute's spots are
/// given (overworld.zig loads it the same way), for a spot the bird doesn't
/// go.
pub const Spot = struct {
    screen: u16,
    link_x: u16,
    link_y: u16,
    scroll_x: u16,
    scroll_y: u16,
    camera_x: u16,
    camera_y: u16,
    map16: u16,
    unk1: i16,
    unk3: i16,
};

/// Out in Lake Hylia, south of the island, by the whirlpool: read off a
/// quick save taken there.
pub const kLakeHylia = Spot{
    .screen = 53,
    .link_x = 3216,
    .link_y = 3682,
    .scroll_x = 3090,
    .scroll_y = 3584,
    .camera_x = 3223,
    .camera_y = 3693,
    .map16 = 4036,
    .unk1 = -2,
    .unk3 = 7,
};

/// Outdoors at one of the spots above instead.
pub var spot: ?Spot = null;

pub fn spotNamed(name: []const u8) ?Spot {
    if (std.mem.eql(u8, name, "lake")) return kLakeHylia;
    return null;
}

/// Whether the game's booting for a picture.
pub fn active() bool {
    return entrance != null or outside != null or bird != null or spot != null;
}

/// Ten hearts, the Master Sword and a shield, full magic, partway through
/// the story: a file that looks lived in, for the HUD.
pub fn fillSave(block: []u8) void {
    @memset(block[0..0x500], 0);
    block[0x359] = 2; // Master Sword
    block[0x35a] = 2; // Fire Shield
    block[0x36c] = 10 * 8;
    block[0x36d] = 10 * 8;
    block[0x36e] = 0x80; // magic
    block[0x343] = 10; // bombs
    block[0x356] = 1; // Flippers, to swim out into a lake
    block[0x362] = 0x2c; // rupees, 300
    block[0x363] = 0x01;
    block[0x360] = 0x2c;
    block[0x361] = 0x01;
    block[0x3c5] = if (dark_world) 3 else 2; // Zelda rescued, or Agahnim beaten
    if (dark_world) {
        block[0x3ca] = 0x40;
        block[0x357] = 1; // the Moon Pearl, to be Link there and not a bunny
    }
    std.mem.writeInt(u16, block[0x3e5..][0..2], 0x55aa, .little);
}
