//! Open mode, the randomizer's only game state for now: the world as it is
//! once Zelda's in the Sanctuary, with the escape undone. No rainy night, no
//! uncle at home, no bed: Link wakes up in daylight free to go anywhere, and
//! Hyrule Castle, its sewers and the uncle in the secret passage are places
//! with items like any other. VT's logic counts Zelda as rescued from the
//! start in Open mode (escape.zig's preplaced RescueZelda), and this is the
//! save that agrees with it.
//!
//! It's what VT's app/Rom.php setOpenMode puts in z3randomizer's initial
//! SRAM table (initsramtable.asm, copied into each new file by events.asm's
//! OnFileCreation), with the field meanings from z3randomizer's sram.asm.
//! Both MIT. The bytes, as offsets into the save block ($7EF000 on):
//!
//!   0x3c5 = 0x02  sram_progress_indicator: Zelda rescued. This is what
//!                 turns the rain off: the overworld's daytime palettes,
//!                 music and sprites, no bed scene or uncle at the start, no
//!                 telepathy, and the start-location menu (Link's House or
//!                 the Sanctuary) every time the file's started.
//!   0x3c6 |= 0x14 sram_progress_flags: 0x10 says the uncle's left the house
//!                 (the house's uncle deletes himself, as after the opening),
//!                 0x04 that Zelda was brought to the Sanctuary (she waits
//!                 there, she's gone from her cell, and the throne room's
//!                 mantle stands pushed aside, see below). 0x01, the uncle's
//!                 item taken, stays clear: he's still in the secret passage
//!                 with his item.
//!   0x3c8 = 0x01  which_starting_point: z3randomizer's "menu" start. Once
//!                 Zelda's rescued the menu comes up whatever this is (only
//!                 the old man's start, 5, skips it), so this just matches
//!                 the ROM's files.
//!   0x29b |= 0x20 save_ow_event_info[0x1b]: the castle's front gate open,
//!                 as the priest opens it when Zelda reaches him.
//!
//! VT's setOpenMode also turns z3randomizer's free light cone in the sewers
//! off (LampConeSewers, 0x180038), which is the game's own way already: no
//! lamp, no light. Its other initial-SRAM bytes aren't Open mode's: the
//! game's new file already pre-opens the Kakariko bomb hut and brewery walls
//! (0x20c to 0x20f) and sets the death counter, and the rest (ability flags
//! without Lift, the ROM's statistics) belong to the ROM's own tracking.
//!
//! What Open mode changes in the running game, each gated on
//! game.active(), after z3randomizer's hooks.asm ("Open Mode Fixes" and
//! "Lamp Mantle & Light Cone Fix"):
//!   - sprite_main.zig Uncle_InPassage: taking the uncle's item doesn't set
//!     the progress indicator back to 1, the rainy escape, unless the game
//!     was still before it (z3randomizer's OnUncleItemGet).
//!   - sprite_main.zig SpritePrep_Mantle: with Zelda rescued (flag 0x04) the
//!     mantle behind the castle's throne starts pushed aside, so the passage
//!     behind it down to the sewers is open (Mantle_CorrectPosition). In the
//!     game it only moves for Zelda in tow (and the lamp), so after the
//!     escape it stays shut, and VT's logic has the way through: the
//!     Sewers' Secret Room with the lamp, the key and something to fight.
const std = @import("std");

pub const kProgressIndicator = 0x3c5;
pub const kProgressFlags = 0x3c6;
pub const kStartingPoint = 0x3c8;
/// save_ow_event_info[0x1b], Hyrule Castle's overworld area.
pub const kCastleGate = 0x280 + 0x1b;

/// Called with a new randomized file's save block (0x500 bytes, $7EF000
/// on), after the game's made it and before its checksum's fixed: sets it
/// up for Open mode. The flags are or'ed in, as VT's InitialSram does, and
/// nothing else in the block is touched.
pub fn applyNewFile(block: []u8) void {
    block[kProgressIndicator] = 0x02;
    block[kProgressFlags] |= 0x14;
    block[kStartingPoint] = 0x01;
    block[kCastleGate] |= 0x20;
}

test "an Open mode file: Zelda rescued, the uncle out, the gate open, nothing else" {
    var block: [0x500]u8 = @splat(0);
    block[0x36c] = 0x18;
    applyNewFile(&block);
    try std.testing.expectEqual(@as(u8, 0x02), block[0x3c5]);
    try std.testing.expectEqual(@as(u8, 0x14), block[0x3c6]);
    try std.testing.expectEqual(@as(u8, 0x01), block[0x3c8]);
    try std.testing.expectEqual(@as(u8, 0x20), block[0x29b]);
    var changed: usize = 0;
    for (block, 0..) |b, i| {
        if (b != 0 and i != 0x36c) changed += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), changed);
}
