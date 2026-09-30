//! The second item's box: what X holds, when there's a second item on X.
//!
//! The game's HUD has no room for it and never had a second item to show,
//! so this doesn't touch the HUD's tilemap in ram. It hands the PPU a few
//! extra BG3 tiles each frame - the item box's own frame pieces and the
//! item's own icon - placed to the pixel against the item box. The PPU draws
//! them as part of BG3, so they fade, vanish in the closing circle and hide
//! behind windows exactly when the rest of the HUD does, and the game can't
//! tell they're there, so it plays and compares against the original as
//! before.
//!
//! The item box's frame, measured off a frame: a dark pixel, a white line and
//! a yellow line around its 16x16 icon, which sits at x 40 to 55 and BG3
//! lines 24 to 39. The second box shares one of its yellow lines and mirrors
//! the rest: under it at 4:3, beside it when the HUD is spread out for
//! widescreen.
const std = @import("std");
const features = @import("features.zig");
const hud = @import("hud.zig");
const zelda_rtl = @import("zelda_rtl.zig");
const ppu_mod = @import("snes").ppu;
const ppu_types = @import("snes").ppu_types;

/// Pixels the counters move over for the box beside the item box.
pub const kBesideGap: i32 = 24;

// The item box's frame pieces. Each hugs the icon: an edge is a dark, a white
// and a yellow line from the icon outward, and the rest of its tile is
// see-through. Flipped, they make the other sides.
const kTop: u16 = 0x285b;
const kBottom: u16 = 0xa85b; // kTop upside down
const kRight: u16 = 0x285d;
const kLeft: u16 = 0x685d; // kRight mirrored
const kTopRight: u16 = 0x285c;
const kTopLeft: u16 = 0x685c;
const kBottomRight: u16 = 0xa85c;
const kBottomLeft: u16 = 0xe85c;

/// Whether the box should be drawn this frame.
pub fn shown() bool {
    if (features.enhanced_features0.* & features.kFeatures0_ItemOnX == 0) return false;
    return zelda_rtl.hudOnScreen();
}

/// Hands the PPU this frame's tiles, or none. `split` says the HUD is spread
/// out, which puts the box beside the item box.
pub fn configure(ppu: *const ppu_types.Ppu, split: bool) void {
    const e = &ppu_mod.g_hud_extra;
    e.* = .{ .ppu = ppu };
    if (!shown()) return;
    const icon = hud.iconForItem(features.hud_cur_item_x.*);
    if (split) addBeside(e, icon) else addUnder(e, icon);
}

fn add(e: *ppu_mod.HudExtra, x: i32, y: i32, word: u16, beside: bool) void {
    e.add(.{ .x = @intCast(x), .y = @intCast(y), .word = word, .beside = beside });
}

fn addIcon(e: *ppu_mod.HudExtra, x: i32, y: i32, icon: [4]u16, beside: bool) void {
    add(e, x, y, icon[0], beside);
    add(e, x + 8, y, icon[1], beside);
    add(e, x, y + 8, icon[2], beside);
    add(e, x + 8, y + 8, icon[3], beside);
}

/// Under the item box. Its bottom yellow line, on BG3 line 42, is the new
/// box's top; then a white line, a dark one, the icon (lines 45 to 60), a dark
/// line, a white one and a yellow one, at x 37 to 58 like the item box. That
/// ends on line 63, before a text box at the top of the screen starts.
fn addUnder(e: *ppu_mod.HudExtra, icon: [4]u16) void {
    const top = 37; // its edge pieces' last three lines are 42, 43, 44
    add(e, 32, top, kTopLeft, false);
    add(e, 40, top, kTop, false);
    add(e, 48, top, kTop, false);
    add(e, 56, top, kTopRight, false);
    for ([_]i32{ 45, 53 }) |y| {
        add(e, 32, y, kLeft, false);
        add(e, 56, y, kRight, false);
    }
    addIcon(e, 40, 45, icon, false);
    const bottom = 61; // dark, white and yellow on 61, 62 and 63
    add(e, 32, bottom, kBottomLeft, false);
    add(e, 40, bottom, kBottom, false);
    add(e, 48, bottom, kBottom, false);
    add(e, 56, bottom, kBottomRight, false);
}

/// Beside the item box, in a split HUD's frame. Its right yellow line, at
/// x 58, is the new box's left; then white, dark, the icon at x 61 to 76,
/// dark, white and yellow to x 79, on the item box's own lines. The counters
/// start at 88.
fn addBeside(e: *ppu_mod.HudExtra, icon: [4]u16) void {
    const top = 16; // BG3 line 16 is the HUD's first
    add(e, 53, top, kTopLeft, true); // its lines land on x 58, 59, 60
    add(e, 61, top, kTop, true);
    add(e, 69, top, kTop, true);
    add(e, 77, top, kTopRight, true);
    for ([_]i32{ 24, 32 }) |y| {
        add(e, 53, y, kLeft, true);
        add(e, 77, y, kRight, true);
    }
    addIcon(e, 61, 24, icon, true);
    const bottom = 40;
    add(e, 53, bottom, kBottomLeft, true);
    add(e, 61, bottom, kBottom, true);
    add(e, 69, bottom, kBottom, true);
    add(e, 77, bottom, kBottomRight, true);
}

test "both boxes fit in the tile list and stay clear of what's around them" {
    var e = ppu_mod.HudExtra{};
    addUnder(&e, .{ 1, 2, 3, 4 });
    try std.testing.expect(e.n <= e.tiles.len);
    // Under: nothing past BG3 line 64, where a top text box can start.
    for (e.tiles[0..e.n]) |t| try std.testing.expect(t.y + 8 <= 69 and !t.beside);
    e = .{};
    addBeside(&e, .{ 1, 2, 3, 4 });
    try std.testing.expect(e.n <= e.tiles.len);
    // Beside: inside the gap the counters leave, which starts at x 64.
    for (e.tiles[0..e.n]) |t| try std.testing.expect(t.beside and t.x + 8 <= 64 + kBesideGap);
}
