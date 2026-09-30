//! Port of src/hud.c: the item menu, equipment/progress boxes, the magic and
//! heart meters, and the per-frame refill logic.
//!
//! Data tables live in hud_tables.zig, generated from the C.
const std = @import("std");
const vars = @import("variables.zig");
const features = @import("features.zig");
const rtl = @import("zelda_rtl_types.zig");
const t = @import("hud_tables.zig");

const ItemBoxGfx = t.ItemBoxGfx;
const g_ram = &vars.g_ram;
const g_zenv = &rtl.g_zenv;

// messaging.c
extern fn DisplaySelectMenu() void;

const kNewStyleInventory = false;
const kHudItemCount: u8 = if (kNewStyleInventory) 24 else 20;

// hud.h
const kHudItem_Bombs: u8 = 4;
const kHudItem_Mushroom: u8 = 5;
const kHudItem_Hammer: u8 = 12;
const kHudItem_Flute: u8 = 13;
const kHudItem_BookMudora: u8 = 15;
const kHudItem_BottleOld: u8 = 16;
const kHudItem_Shovel: u8 = 16;
const kHudItem_Bottle1: u8 = 21;
const kHudItem_Bottle4: u8 = 24;

// zelda_rtl.h
const kJoypadL_X: u8 = 0x40;
const kJoypadL_L: u8 = 0x20;
const kJoypadL_R: u8 = 0x10;
const kJoypadH_Y: u8 = 0x40;
const kJoypadH_Select: u8 = 0x20;
const kJoypadH_Start: u8 = 0x10;
const kJoypadH_Up: u8 = 0x8;
const kJoypadH_Down: u8 = 0x4;
const kJoypadH_Left: u8 = 0x2;
const kJoypadH_Right: u8 = 0x1;

pub export const kMaxBombsForLevel = t.kMaxBombsForLevel;
pub export const kMaxArrowsForLevel = t.kMaxArrowsForLevel;

const kHudItemInVramPtr = if (kNewStyleInventory) &t.kHudItemInVramPtr_New else &t.kHudItemInVramPtr_Old;

const kHudItemBoxGfxPtrs = [32][]const ItemBoxGfx{
    &t.kHudItemBow,        &t.kHudItemBoomerang,  &t.kHudItemHookshot,
    &t.kHudItemBombs,      &t.kHudItemMushroom,   &t.kHudItemFireRod,
    &t.kHudItemIceRod,     &t.kHudItemBombos,     &t.kHudItemEther,
    &t.kHudItemQuake,      &t.kHudItemTorch,      &t.kHudItemHammer,
    &t.kHudItemFlute,      &t.kHudItemBugNet,     &t.kHudItemBookMudora,
    &t.kHudItemBottles,    &t.kHudItemCaneSomaria, &t.kHudItemCaneByrna,
    &t.kHudItemCape,       &t.kHudItemMirror,     &t.kHudItemGloves,
    &t.kHudItemBoots,      &t.kHudItemFlippers,   &t.kHudItemMoonPearl,
    &t.kHudItemEmpty,      &t.kHudItemSword,      &t.kHudItemShield,
    &t.kHudItemArmor,      &t.kHudItemBottles,    &t.kHudItemBottles,
    &t.kHudItemBottles,    &t.kHudItemBottles,
};

/// The hud tilemaps are addressed as (x + y * 32), and a few call sites use
/// negative offsets, so keep it signed.
inline fn HUDXY(x: i32, y: i32) i32 {
    return x + y * 32;
}

/// Indexes a tilemap pointer by a signed word offset.
inline fn at(p: [*]align(1) u16, o: i32) *align(1) u16 {
    return @ptrFromInt(@intFromPtr(p) +% @as(usize, @bitCast(@as(isize, o) * 2)));
}

/// uvram_screen viewed as the flat 1024-word tilemap the C walks.
fn uvram() [*]align(1) u16 {
    return @ptrCast(&vars.uvram_screen.row[0].col);
}

fn hudbuf() [*]align(1) u16 {
    return vars.hud_tile_indices_buffer;
}

/// The 20 save-game item bytes starting at link_item_bow, which the C reaches
/// as (&link_item_bow)[i].
fn linkItems() [*]u8 {
    return @ptrCast(vars.link_item_bow);
}

fn sign8(v: u8) bool {
    return v & 0x80 != 0;
}

fn loPtr(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

pub export fn Hud_RefreshIcon() callconv(.c) void {
    Hud_SearchForEquippedItem();
    Hud_UpdateHud();
    Hud_Rebuild();
    vars.overworld_map_state.* = 0;
}

pub export fn CheckPalaceItemPosession() callconv(.c) u8 {
    return switch (vars.cur_palace_index_x2.* >> 1) {
        2 => @intFromBool(vars.link_item_bow.* != 0),
        3 => @intFromBool(vars.link_item_gloves.* != 0),
        5 => @intFromBool(vars.link_item_hookshot.* != 0),
        6 => @intFromBool(vars.link_item_hammer.* != 0),
        7 => @intFromBool(vars.link_item_cane_somaria.* != 0),
        8 => @intFromBool(vars.link_item_fire_rod.* != 0),
        9 => @intFromBool(vars.link_armor.* != 0),
        10 => @intFromBool(vars.link_item_moon_pearl.* != 0),
        11 => @intFromBool(vars.link_item_gloves.* != 1),
        12 => @intFromBool(vars.link_shield_type.* == 3),
        13 => @intFromBool(vars.link_armor.* == 2),
        else => 0,
    };
}

/// Returns the zero based index of the currently selected hud item,
/// or -1 if the item is item 0.
fn Hud_GetItemPosition(item: i32) i32 {
    if (item <= 0)
        return -1;
    if (features.hud_inventory_order[0] != 0) {
        var i: i32 = 0;
        while (i < kHudItemCount - 1 and features.hud_inventory_order[@intCast(i)] != item) : (i += 1) {}
        return i;
    } else {
        return if (item != 0) item - 1 else item;
    }
}

fn Hud_GotoPrevItem(item: *u8, first_item_index: u8) void {
    if (features.hud_inventory_order[0] != 0) {
        const pos = Hud_GetItemPosition(item.*);
        item.* = if (pos == 0 and first_item_index == 0)
            0
        else
            features.hud_inventory_order[@intCast((if (pos <= 0) @as(i32, kHudItemCount) else pos) - 1)];
    } else {
        item.* = if (item.* > first_item_index) item.* - 1 else kHudItemCount;
    }
}

fn Hud_GotoNextItem(item: *u8, first_item_index: u8) void {
    if (features.hud_inventory_order[0] != 0) {
        const i = Hud_GetItemPosition(item.*);
        item.* = features.hud_inventory_order[
            if (@as(u32, @bitCast(i)) >= kHudItemCount - 1) 0 else @intCast(i + 1)
        ];
    } else {
        item.* = if (item.* < kHudItemCount) item.* + 1 else first_item_index;
    }
}

pub export fn Hud_FloorIndicator() callconv(.c) void { // 8afd0c
    var a: u16 = vars.hud_floor_changed_timer.*;
    if (a == 0) {
        Hud_RemoveSuperBombIndicator();
        return;
    }
    a += 1;
    if (a == 0xc0)
        a = 0;
    // The C writes the full word through WORD(hud_floor_changed_timer).
    std.mem.writeInt(u16, @as([*]u8, @ptrCast(vars.hud_floor_changed_timer))[0..2], a, .little);

    hudbuf()[0xf2 / 2] = 0x251e;
    hudbuf()[0x134 / 2] = 0x251f;
    hudbuf()[0x132 / 2] = 0x2520;
    hudbuf()[0xf4 / 2] = 0x250f;

    var k: usize = 0;
    var j: usize = undefined;

    if (!sign8(vars.dung_cur_floor.*)) {
        const w = std.mem.readInt(u16, @as([*]const u8, @ptrCast(vars.dung_cur_floor))[0..2], .little);
        if (w == 0 and vars.dungeon_room_index.* != 2 and vars.sram_progress_indicator.* < 2)
            vars.sound_effect_ambient.* = 3;
        j = vars.dung_cur_floor.*;
    } else {
        vars.sound_effect_ambient.* = 5;
        k += 1;
        j = vars.dung_cur_floor.* ^ 0xff;
    }
    hudbuf()[k + 0xf2 / 2] = t.kDungFloorIndicator_Gfx0[j];
    hudbuf()[k + 0x132 / 2] = t.kDungFloorIndicator_Gfx1[j];
    vars.flag_update_hud_in_nmi.* +%= 1;
}

pub export fn Hud_RemoveSuperBombIndicator() callconv(.c) void { // 8afd90
    hudbuf()[0xf2 / 2] = 0x7f;
    hudbuf()[0x132 / 2] = 0x7f;
    hudbuf()[0xf4 / 2] = 0x7f;
    hudbuf()[0x134 / 2] = 0x7f;
}

pub export fn Hud_SuperBombIndicator() callconv(.c) void { // 8afda8
    remove: {
        if (vars.super_bomb_indicator_unk1.* == 0) {
            if (sign8(vars.super_bomb_indicator_unk2.*))
                break :remove;
            vars.super_bomb_indicator_unk2.* -%= 1;
            vars.super_bomb_indicator_unk1.* = 62;
        }
        vars.super_bomb_indicator_unk1.* -%= 1;
        if (sign8(vars.super_bomb_indicator_unk2.*))
            break :remove;

        const r: i32 = vars.super_bomb_indicator_unk2.* % 10;
        const q: i32 = vars.super_bomb_indicator_unk2.* / 10;

        var j: usize = if (sign8(@truncate(@as(u32, @bitCast(r - 1))))) 9 else @intCast(r - 1);
        hudbuf()[0xf4 / 2] = t.kDungFloorIndicator_Gfx0[j];
        hudbuf()[0x134 / 2] = t.kDungFloorIndicator_Gfx1[j];

        j = if (sign8(@truncate(@as(u32, @bitCast(q - 1))))) 10 else @intCast(q - 1);
        hudbuf()[0xf2 / 2] = t.kDungFloorIndicator_Gfx0[j];
        hudbuf()[0x132 / 2] = t.kDungFloorIndicator_Gfx1[j];
        return;
    }
    vars.super_bomb_indicator_unk2.* = 0xff;
    Hud_RemoveSuperBombIndicator();
}

fn MaxRupees() u16 {
    return if (features.enhanced_features0.* & features.kFeatures0_CarryMoreRupees != 0) 9999 else 999;
}

pub export fn Hud_RefillLogic() callconv(.c) void { // 8ddb92
    if (vars.overworld_map_state.* != 0)
        return;
    if (vars.link_magic_filler.* != 0) {
        if (vars.link_magic_power.* >= 128) {
            vars.link_magic_power.* = 128;
            vars.link_magic_filler.* = 0;
        } else {
            vars.link_magic_filler.* -%= 1;
            vars.link_magic_power.* +%= 1;
            if ((vars.frame_counter.* & 3) == 0 and vars.sound_effect_1.* == 0)
                vars.sound_effect_1.* = 45;
        }
    }

    var a = vars.link_rupees_actual.*;
    if (a != vars.link_rupees_goal.*) {
        if (a >= vars.link_rupees_goal.*) {
            a -%= 1;
            if (@as(i16, @bitCast(a)) < 0) {
                a = 0;
                vars.link_rupees_goal.* = 0;
            }
        } else {
            const m = MaxRupees();
            a +%= 1;
            if (a > m) {
                a = m;
                vars.link_rupees_goal.* = m;
            }
        }
        vars.link_rupees_actual.* = a;
        if (vars.sound_effect_1.* == 0) {
            const d = vars.rupee_sfx_sound_delay.*;
            vars.rupee_sfx_sound_delay.* +%= 1;
            if ((d & 7) == 0)
                vars.sound_effect_1.* = 41;
        } else {
            vars.rupee_sfx_sound_delay.* = 0;
        }
    } else {
        vars.rupee_sfx_sound_delay.* = 0;
    }

    if (vars.link_bomb_filler.* != 0) {
        vars.link_bomb_filler.* -%= 1;
        if (vars.link_item_bombs.* != t.kMaxBombsForLevel[vars.link_bomb_upgrades.*])
            vars.link_item_bombs.* +%= 1;
    }

    if (vars.link_arrow_filler.* != 0) {
        vars.link_arrow_filler.* -%= 1;
        if (vars.link_num_arrows.* != t.kMaxArrowsForLevel[vars.link_arrow_upgrades.*])
            vars.link_num_arrows.* +%= 1;
        if (vars.link_item_bow.* != 0 and (vars.link_item_bow.* & 1) == 1) {
            vars.link_item_bow.* +%= 1;
            Hud_RefreshIcon();
        }
    }

    if (vars.flag_is_link_immobilized.* == 0 and vars.link_hearts_filler.* == 0 and
        vars.link_health_current.* < t.kMaxHealthForLevel[vars.link_health_capacity.* >> 3])
    {
        if (vars.link_lowlife_countdown_timer_beep.* != 0) {
            vars.link_lowlife_countdown_timer_beep.* -%= 1;
        } else if (vars.sound_effect_1.* == 0) {
            if (features.enhanced_features0.* & features.kFeatures0_DisableLowHealthBeep == 0)
                vars.sound_effect_1.* = 43;
            vars.link_lowlife_countdown_timer_beep.* = 32 - 1;
        }
    }

    // The C reaches the animation tail either by falling into it or by
    // `goto doing_animation` when an animation is already running.
    var doing_animation = vars.is_doing_heart_animation.* != 0;
    if (!doing_animation and vars.link_hearts_filler.* != 0) {
        if (vars.link_health_current.* < vars.link_health_capacity.*) {
            vars.link_health_current.* +%= 8;
            if (vars.link_health_current.* >= vars.link_health_capacity.*)
                vars.link_health_current.* = vars.link_health_capacity.*;

            if (vars.sound_effect_2.* == 0)
                vars.sound_effect_2.* = 13;

            vars.link_hearts_filler.* -%= 8;
            vars.is_doing_heart_animation.* +%= 1;
            vars.animate_heart_refill_countdown.* = 7;
            doing_animation = true;
        } else {
            vars.link_health_current.* = vars.link_health_capacity.*;
            vars.link_hearts_filler.* = 0;
        }
    }
    if (doing_animation) {
        Hud_Update_Magic();
        Hud_Update_Inventory();
        Hud_AnimateHeartRefill();
        vars.flag_update_hud_in_nmi.* +%= 1;
        return;
    }
    Hud_Update_Hearts();
    Hud_Update_Magic();
    Hud_Update_Inventory();
    vars.flag_update_hud_in_nmi.* +%= 1;
}

pub export fn Hud_Module_Run() callconv(.c) void { // 8ddd36
    vars.byte_7E0206.* +%= 1;
    switch (vars.overworld_map_state.*) {
        0 => Hud_ClearTileMap(),
        1 => Hud_Init(),
        2 => Hud_BringMenuDown(),
        3 => Hud_ChooseNextMode(),
        4 => Hud_NormalMenu(),
        5 => Hud_UpdateHud(),
        6 => Hud_CloseMenu(),
        7 => Hud_GotoBottleMenu(),
        8 => Hud_InitBottleMenu(),
        9 => Hud_ExpandBottleMenu(),
        10 => Hud_BottleMenu(),
        11 => Hud_EraseBottleMenu(),
        12 => Hud_RestoreNormalMenu(),
        else => unreachable, // assert(0)
    }
}

pub export fn Hud_ClearTileMap() callconv(.c) void { // 8ddd5a
    const target: [*]align(1) u16 = @ptrCast(&g_ram[0x1000]);
    for (0..1024) |i|
        target[i] = 0x207f;
    vars.sound_effect_2.* = 17;
    vars.nmi_subroutine_index.* = 1;
    loPtr(vars.nmi_load_target_addr).* = 0x22;
    vars.overworld_map_state.* +%= 1;
}

pub export fn Hud_HaveAnyItems() callconv(.c) bool { // new
    for (0..20) |i|
        if (linkItems()[i] != 0)
            return true;
    return false;
}

pub export fn Hud_Init() callconv(.c) void { // 8dddab
    Hud_SearchForEquippedItem();
    Hud_DrawYButtonItems();
    Hud_DrawAbilityBox();
    Hud_DrawProgressIcons();
    Hud_DrawEquipmentBox();
    Hud_DrawSelectedYButtonItem();

    if (Hud_HaveAnyItems()) {
        // This causes bottle flicker because it's not early enough
        var first_bottle: usize = 0;
        while (first_bottle < 4 and vars.link_bottle_info[first_bottle] == 0)
            first_bottle += 1;
        if (first_bottle == 4) {
            vars.link_item_bottle_index.* = 0;
        } else if (vars.link_item_bottle_index.* == 0) {
            vars.link_item_bottle_index.* = @intCast(first_bottle + 1);
        }

        if (vars.hud_cur_item.* == kHudItem_BottleOld and !kNewStyleInventory) {
            vars.timer_for_flashing_circle.* = 16;
            Hud_DrawBottleMenu();
        }
    }

    vars.timer_for_flashing_circle.* = 16;
    vars.nmi_subroutine_index.* = 1;
    loPtr(vars.nmi_load_target_addr).* = 0x22;
    vars.overworld_map_state.* +%= 1;
}

pub export fn Hud_BringMenuDown() callconv(.c) void { // 8dde59
    vars.BG3VOFS_copy2.* -%= 8;
    if (vars.BG3VOFS_copy2.* == 0xff18)
        vars.overworld_map_state.* +%= 1;
}

pub export fn Hud_ChooseNextMode() callconv(.c) void { // 8dde6e
    if (Hud_HaveAnyItems()) {
        vars.nmi_subroutine_index.* = 1;
        loPtr(vars.nmi_load_target_addr).* = 0x22;

        Hud_DrawSelectedYButtonItem();

        // Pick either the bottle state or normal one
        vars.overworld_map_state.* =
            if (vars.hud_cur_item.* == kHudItem_BottleOld and !kNewStyleInventory) 10 else 4;
    } else {
        if (vars.filtered_joypad_H.* != 0)
            vars.overworld_map_state.* = 5;
    }
}

fn Hud_DoWeHaveThisItem(item: u8) bool { // 8ddeb0
    if (item == 0)
        return true; // for the x item, 0 is valid

    if (item == kHudItem_Flute and kNewStyleInventory)
        return vars.link_item_flute.* >= 2;

    if (item == kHudItem_Shovel and kNewStyleInventory)
        return vars.link_item_flute.* >= 1;

    if (item >= kHudItem_Bottle1)
        return vars.link_bottle_info[item - kHudItem_Bottle1] != 0;

    return linkItems()[item - 1] != 0;
}

fn Hud_EquipPrevItem(item: *u8) void { // 8dded9
    while (true) {
        Hud_GotoPrevItem(item, @intFromBool(item == vars.hud_cur_item));
        if (Hud_DoWeHaveThisItem(item.*)) break;
    }
}

fn Hud_EquipNextItem(item: *u8) void { // 8ddee2
    while (true) {
        Hud_GotoNextItem(item, @intFromBool(item == vars.hud_cur_item));
        if (Hud_DoWeHaveThisItem(item.*)) break;
    }
}

fn Hud_EquipItemAbove(item: *u8) void { // 8ddeeb
    while (true) {
        for (0..(if (kNewStyleInventory) 6 else 5)) |_|
            Hud_GotoPrevItem(item, 1);
        if (Hud_DoWeHaveThisItem(item.*)) break;
    }
}

fn Hud_EquipItemBelow(item: *u8) void { // 8ddf00
    const num: usize = if (item.* == 0) 1 else (if (kNewStyleInventory) 6 else 5);
    while (true) {
        for (0..num) |_|
            Hud_GotoNextItem(item, 1);
        if (Hud_DoWeHaveThisItem(item.*)) break;
    }
}

/// Which item button is held: 1 for X when the second item is on, 2 and 3
/// for L and R when item switching is. 0 for none, meaning Y.
pub export fn GetCurrentItemButtonIndex() callconv(.c) c_int {
    const f = features.enhanced_features0.*;
    if (f & features.kFeatures0_ItemOnX != 0 and vars.joypad1L_last.* & kJoypadL_X != 0) return 1;
    if (f & features.kFeatures0_SwitchLR != 0) {
        // L and R together are the map, not whichever item L has.
        if (hasItemOnX() and holdingLAndR()) return 0;
        if (vars.joypad1L_last.* & kJoypadL_L != 0) return 2;
        if (vars.joypad1L_last.* & kJoypadL_R != 0) return 3;
    }
    return 0;
}

fn holdingLAndR() bool {
    return vars.joypad1L_last.* & (kJoypadL_L | kJoypadL_R) == kJoypadL_L | kJoypadL_R;
}

/// L and R together, the map's button while X holds a second item: both
/// held, with one of them pressed just now, so holding them opens it once.
pub fn pressedLAndR() bool {
    return holdingLAndR() and vars.filtered_joypad_L.* & (kJoypadL_L | kJoypadL_R) != 0;
}

/// Whether X holds a second item right now: the feature is on and something
/// is assigned. The map moves to L and R together while it does.
pub fn hasItemOnX() bool {
    return features.enhanced_features0.* & features.kFeatures0_ItemOnX != 0 and features.hud_cur_item_x.* != 0;
}

pub export fn GetCurrentItemButtonPtr(i: c_int) callconv(.c) *u8 {
    return switch (i) {
        0 => vars.hud_cur_item,
        1 => features.hud_cur_item_x,
        2 => features.hud_cur_item_l,
        else => features.hud_cur_item_r,
    };
}

pub export fn Hud_NormalMenu() callconv(.c) void { // 8ddf15
    vars.timer_for_flashing_circle.* +%= 1;
    if (vars.joypad1H_last.* == 0)
        loPtr(vars.hud_tmp1).* = 0;

    if (vars.filtered_joypad_H.* & kJoypadH_Start != 0) {
        vars.overworld_map_state.* = 5;
        vars.sound_effect_2.* = 18;
        return;
    }

    // Allow select to open the save/exit thing
    if (vars.joypad1H_last.* & kJoypadH_Select != 0 and vars.sram_progress_indicator.* != 0) {
        vars.BG3VOFS_copy2.* = @bitCast(@as(i16, -8));
        Hud_CloseMenu();
        DisplaySelectMenu();
        return;
    }

    if (vars.joypad1H_last.* & kJoypadH_Y != 0 and (vars.joypad1L_last.* & kJoypadL_X) == 0 and
        features.enhanced_features0.* & features.kFeatures0_SwitchLR != 0)
    {
        if (vars.filtered_joypad_H.* & kJoypadH_Up != 0) {
            Hud_ReorderItem(if (kNewStyleInventory) -6 else -5);
        } else if (vars.filtered_joypad_H.* & kJoypadH_Down != 0) {
            Hud_ReorderItem(if (kNewStyleInventory) 6 else 5);
        } else if (vars.filtered_joypad_H.* & kJoypadH_Left != 0) {
            Hud_ReorderItem(-1);
        } else if (vars.filtered_joypad_H.* & kJoypadH_Right != 0) {
            Hud_ReorderItem(1);
        }
    } else if (loPtr(vars.hud_tmp1).* == 0) {
        // If Special Key button is down, then move their circle
        const btn_index = GetCurrentItemButtonIndex();
        const item_p = GetCurrentItemButtonPtr(btn_index);
        const old_item = item_p.*;
        if (vars.filtered_joypad_H.* & kJoypadH_Up != 0) {
            Hud_EquipItemAbove(item_p);
        } else if (vars.filtered_joypad_H.* & kJoypadH_Down != 0) {
            Hud_EquipItemBelow(item_p);
        } else if (vars.filtered_joypad_H.* & kJoypadH_Left != 0) {
            Hud_EquipPrevItem(item_p);
        } else if (vars.filtered_joypad_H.* & kJoypadH_Right != 0) {
            Hud_EquipNextItem(item_p);
        }
        loPtr(vars.hud_tmp1).* = vars.filtered_joypad_H.*;
        if (item_p.* != old_item) {
            vars.timer_for_flashing_circle.* = 16;
            vars.sound_effect_2.* = 32;
        }
    }
    Hud_DrawYButtonItems();
    Hud_DrawSelectedYButtonItem();
    if (vars.hud_cur_item.* == kHudItem_BottleOld and !kNewStyleInventory)
        vars.overworld_map_state.* = 7;

    vars.nmi_subroutine_index.* = 1;
    loPtr(vars.nmi_load_target_addr).* = 0x22;
}

pub export fn Hud_UpdateHud() callconv(.c) void { // 8ddfa9
    vars.overworld_map_state.* +%= 1;
    Hud_Rebuild();
    Hud_UpdateEquippedItem();
}

pub export fn Hud_LookupInventoryItem(item: u8) callconv(.c) u8 {
    return if (kNewStyleInventory) t.kHudItemToItemNew[item] else t.kHudItemToItemOrg[item];
}

pub export fn Hud_UpdateEquippedItem() callconv(.c) void { // 8ddfaf
    if (vars.hud_cur_item.* >= kHudItem_Bottle1)
        vars.link_item_bottle_index.* = vars.hud_cur_item.* - kHudItem_Bottle1 + 1;

    std.debug.assert(vars.hud_cur_item.* < 25);
    vars.current_item_y.* = Hud_LookupInventoryItem(vars.hud_cur_item.*);
}

pub export fn Hud_CloseMenu() callconv(.c) void { // 8ddfba
    vars.BG3VOFS_copy2.* +%= 8;
    if (vars.BG3VOFS_copy2.* != 0)
        return;
    Hud_Rebuild();
    vars.overworld_map_state.* = 0;
    vars.submodule_index.* = 0;
    vars.main_module_index.* = vars.saved_module_for_menu.*;
    if (vars.submodule_index.* != 0)
        Hud_RestoreTorchBackground();
    if (vars.current_item_y.* != 5 and vars.current_item_y.* != 6) {
        vars.eq_debug_variable.* = 2;
        vars.link_debug_value_1.* = 0;
    } else {
        std.debug.assert(vars.link_debug_value_1.* == 0);
        vars.eq_debug_variable.* = 0;
    }
}

pub export fn Hud_GotoBottleMenu() callconv(.c) void { // 8ddffb
    vars.bottle_menu_expand_row.* = 0;
    vars.overworld_map_state.* +%= 1;
}

pub export fn Hud_InitBottleMenu() callconv(.c) void { // 8de002
    const r: i32 = vars.bottle_menu_expand_row.*;
    const dst = uvram() + (if (kNewStyleInventory) @as(usize, 1) else 0);
    var i: i32 = 21;
    while (i <= 30) : (i += 1)
        at(dst, HUDXY(i, 11 + r)).* = 0x207f;

    vars.bottle_menu_expand_row.* +%= 1;
    if (vars.bottle_menu_expand_row.* == 19) {
        vars.overworld_map_state.* +%= 1;
        vars.bottle_menu_expand_row.* = 17;
    }
    vars.nmi_subroutine_index.* = 1;
    loPtr(vars.nmi_load_target_addr).* = 0x22;
}

pub export fn Hud_ExpandBottleMenu() callconv(.c) void { // 8de08c
    const r: i32 = vars.bottle_menu_expand_row.*;
    const dst = uvram() + (if (kNewStyleInventory) @as(usize, 1) else 0);
    for (0..10) |i| {
        at(dst, HUDXY(21 + @as(i32, @intCast(i)), 11 + r)).* = t.kBottleMenuTop[i];
        at(dst, HUDXY(21 + @as(i32, @intCast(i)), 12 + r)).* = t.kBottleMenuTop2[i];
        at(dst, HUDXY(21 + @as(i32, @intCast(i)), 29)).* = t.kBottleMenuBottom[i];
    }

    vars.bottle_menu_expand_row.* -%= 1;
    if (sign8(vars.bottle_menu_expand_row.*))
        vars.overworld_map_state.* +%= 1;
    vars.nmi_subroutine_index.* = 1;
    loPtr(vars.nmi_load_target_addr).* = 0x22;
}

pub export fn Hud_BottleMenu() callconv(.c) void { // 8de0df
    vars.timer_for_flashing_circle.* +%= 1;
    if (vars.filtered_joypad_H.* & kJoypadH_Start != 0) {
        vars.sound_effect_2.* = 18;
        vars.overworld_map_state.* = 5;
    } else if (vars.filtered_joypad_H.* & (kJoypadH_Left | kJoypadH_Right) != 0) {
        if (vars.filtered_joypad_H.* & kJoypadH_Left != 0) {
            Hud_EquipPrevItem(vars.hud_cur_item);
        } else {
            Hud_EquipNextItem(vars.hud_cur_item);
        }
        vars.timer_for_flashing_circle.* = 16;
        vars.sound_effect_2.* = 32;
        Hud_DrawYButtonItems();
        Hud_DrawSelectedYButtonItem();
        vars.overworld_map_state.* +%= 1;
        vars.bottle_menu_expand_row.* = 0;
        return;
    }
    Hud_DrawBottleMenu_Update();
    if (vars.filtered_joypad_H.* & (kJoypadH_Down | kJoypadH_Up) != 0) {
        const old_val = vars.link_item_bottle_index.* -% 1;
        var val = old_val;

        if (vars.filtered_joypad_H.* & kJoypadH_Up != 0) {
            while (true) {
                val = (val -% 1) & 3;
                if (vars.link_bottle_info[val] != 0) break;
            }
        } else {
            while (true) {
                val = (val +% 1) & 3;
                if (vars.link_bottle_info[val] != 0) break;
            }
        }
        if (old_val != val) {
            vars.link_item_bottle_index.* = val + 1;
            vars.timer_for_flashing_circle.* = 16;
            vars.sound_effect_2.* = 32;
        }
    }
}

fn Hud_DrawItem(dst: *align(1) u16, src: *const ItemBoxGfx) void { // new
    const p: [*]align(1) u16 = @ptrCast(dst);
    p[0] = src.v[0];
    p[1] = src.v[1];
    p[32] = src.v[2];
    p[33] = src.v[3];
}

fn Hud_DrawNxN(dst: *align(1) u16, src: []const u16, w: usize, h: usize) void { // new
    var p: [*]align(1) u16 = @ptrCast(dst);
    var s: usize = 0;
    for (0..h) |_| {
        @memcpy(p[0..w], src[s..][0..w]);
        p += 32;
        s += w;
    }
}

fn Hud_Copy2x2(dst: *align(1) u16, src: *align(1) u16) void { // new
    const d: [*]align(1) u16 = @ptrCast(dst);
    const s: [*]align(1) u16 = @ptrCast(src);
    d[0] = s[0];
    d[1] = s[1];
    d[32] = s[32];
    d[33] = s[33];
}

fn Hud_DrawBox(dst: [*]align(1) u16, x1: i32, y1: i32, x2: i32, y2: i32, palette: u8) void { // new
    var tv: u16 = 0x20fb | (@as(u16, palette) << 10);
    at(dst, HUDXY(x1, y1)).* = tv;
    at(dst, HUDXY(x2, y1)).* = tv +% 0x4000;
    at(dst, HUDXY(x1, y2)).* = tv +% 0x8000;
    at(dst, HUDXY(x2, y2)).* = tv +% 0xc000;

    tv = 0x20fc | (@as(u16, palette) << 10);
    var y = y1 + 1;
    while (y < y2) : (y += 1) {
        at(dst, HUDXY(x1, y)).* = tv;
        at(dst, HUDXY(x2, y)).* = tv +% 0x4000;
    }

    tv = 0x20f9 | (@as(u16, palette) << 10);
    var x = x1 + 1;
    while (x < x2) : (x += 1) {
        at(dst, HUDXY(x, y1)).* = tv;
        at(dst, HUDXY(x, y2)).* = tv +% 0x8000;
    }

    y = y1 + 1;
    while (y < y2) : (y += 1) {
        x = x1 + 1;
        while (x < x2) : (x += 1)
            at(dst, HUDXY(x, y)).* = 0x24F5;
    }
}

fn Hud_DrawFlashingCircle(p: [*]align(1) u16, palette: u8) void { // new
    const pp: u16 = @as(u16, palette) << 10;
    at(p, HUDXY(0, -1)).* = pp | 0x2061;
    at(p, HUDXY(1, -1)).* = pp | 0x2061 | 0x4000;
    at(p, HUDXY(-1, 0)).* = pp | 0x2070;
    at(p, HUDXY(2, 0)).* = pp | 0x2070 | 0x4000;
    at(p, HUDXY(-1, 1)).* = pp | 0xa070;
    at(p, HUDXY(2, 1)).* = pp | 0xa070 | 0x4000;
    at(p, HUDXY(0, 2)).* = pp | 0xa061;
    at(p, HUDXY(1, 2)).* = pp | 0xa061 | 0x4000;
    at(p, HUDXY(-1, -1)).* = pp | 0x2060;
    at(p, HUDXY(2, -1)).* = pp | 0x2060 | 0x4000;
    at(p, HUDXY(2, 2)).* = pp | 0x2060 | 0xC000;
    at(p, HUDXY(-1, 2)).* = pp | 0x2060 | 0x8000;
}

pub export fn Hud_DrawBottleMenu() callconv(.c) void { // 8def67
    const dst = uvram() + (if (kNewStyleInventory) @as(usize, 1) else 0);
    Hud_DrawBox(dst, 21, 11, 30, 29, 2);
    for (0..4) |i|
        Hud_DrawItem(at(dst, HUDXY(25, 13 + @as(i32, @intCast(i)) * 4)),
            &t.kHudItemBottles[vars.link_bottle_info[i]]);
    const p = &t.kHudItemBottles[vars.link_bottle_info[vars.link_item_bottle_index.* - 1]];
    Hud_DrawItem(at(uvram(), kHudItemInVramPtr[15]), p);
    if (vars.timer_for_flashing_circle.* & 0x10 != 0)
        Hud_DrawFlashingCircle(
            @ptrCast(at(dst, HUDXY(25, 13 + (@as(i32, vars.link_item_bottle_index.*) - 1) * 4))),
            7,
        );
}

pub export fn Hud_DrawBottleMenu_Update() callconv(.c) void { // 8de17f
    Hud_DrawBottleMenu();
    Hud_DrawSelectedYButtonItem();

    vars.nmi_subroutine_index.* = 1;
    loPtr(vars.nmi_load_target_addr).* = 0x22;
}

pub export fn Hud_EraseBottleMenu() callconv(.c) void { // 8de2fd
    const dst = uvram() + (if (kNewStyleInventory) @as(usize, 1) else 0);
    const r: i32 = vars.bottle_menu_expand_row.*;
    for (0..10) |i|
        at(dst, HUDXY(21 + @as(i32, @intCast(i)), 11 + r)).* = 0x207f;
    vars.bottle_menu_expand_row.* +%= 1;
    if (vars.bottle_menu_expand_row.* == 19)
        vars.overworld_map_state.* +%= 1;
    vars.nmi_subroutine_index.* = 1;
    loPtr(vars.nmi_load_target_addr).* = 0x22;
}

pub export fn Hud_RestoreNormalMenu() callconv(.c) void { // 8de346
    Hud_DrawProgressIcons();
    Hud_DrawEquipmentBox();
    vars.overworld_map_state.* = 4;
    vars.nmi_subroutine_index.* = 1;
    loPtr(vars.nmi_load_target_addr).* = 0x22;
}

pub export fn Hud_SearchForEquippedItem() callconv(.c) void { // 8de399
    if (!Hud_HaveAnyItems()) {
        vars.hud_cur_item.* = 0;
        vars.hud_var1.* = 0;
    } else {
        if (vars.hud_cur_item.* == 0)
            vars.hud_cur_item.* = 1;
        if (!Hud_DoWeHaveThisItem(vars.hud_cur_item.*))
            Hud_EquipNextItem(vars.hud_cur_item);
    }
}

/// The four tile words of an item's icon, as the item box shows it - bottle
/// contents, flute or shovel and all. For the second item's box.
pub fn iconForItem(i: i32) [4]u16 {
    return Hud_GetIconForItem(i).v;
}

fn Hud_GetIconForItem(i: i32) *const ItemBoxGfx {
    if (i <= 0)
        return &t.kHudItemEmpty[0];

    if (i >= kHudItem_Bottle1)
        return &t.kHudItemBottles[vars.link_bottle_info[@intCast(i - kHudItem_Bottle1)]];
    if (i == kHudItem_Shovel and kNewStyleInventory)
        return &t.kHudItemFlute[@intFromBool(vars.link_item_flute.* >= 1)];

    var item_val = linkItems()[@intCast(i - 1)];
    if (i == kHudItem_Bombs) { // bombs
        item_val = @intFromBool(item_val != 0);
    } else if (i == kHudItem_BottleOld and !kNewStyleInventory) {
        item_val = if (vars.link_item_bottle_index.* != 0)
            vars.link_bottle_info[vars.link_item_bottle_index.* - 1]
        else
            0;
    }
    return &kHudItemBoxGfxPtrs[@intCast(i - 1)][item_val];
}

/// The C builds these tiles with a PV() bit-interleaving macro.
fn PV(a: [8]u8) u16 {
    var v: u16 = 0;
    for (a, 0..) |x, i| {
        const sh: u4 = @intCast(7 - i);
        v |= @as(u16, x & 1) << sh;
        v |= @as(u16, (x >> 1) & 1) << (sh + 8);
    }
    return v;
}

const kBytesForNewTile0xC_TopOfR = [8]u16{
    PV(.{ 1, 1, 1, 1, 1, 1, 3, 3 }),
    PV(.{ 1, 1, 1, 1, 1, 1, 1, 3 }),
    PV(.{ 1, 1, 1, 1, 1, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 1, 1, 1, 1, 3 }),
};
const kBytesForNewTile0xD_BottomofR = [8]u16{
    PV(.{ 1, 1, 1, 1, 1, 1, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 1, 1, 1, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 3, 3, 1, 1, 1 }),
};
const kBytesForNewTile0xE_TopOfL = [8]u16{
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
};
const kBytesForNewTile0xF_BottomofL = [8]u16{
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 3, 3, 3, 3, 3 }),
    PV(.{ 1, 1, 1, 1, 1, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 1, 1, 1, 1, 1 }),
    PV(.{ 1, 1, 1, 1, 1, 1, 1, 1 }),
};

fn CopyTilesForSwitchLR(switch_lr: c_int) void {
    const vram = g_zenv.vram.?;
    if (switch_lr == 3) {
        @memcpy(vram[0x7000 + 0xc * 8 ..][0..8], &kBytesForNewTile0xC_TopOfR);
        @memcpy(vram[0x7000 + 0xd * 8 ..][0..8], &kBytesForNewTile0xD_BottomofR);
    } else if (switch_lr == 2) {
        @memcpy(vram[0x7000 + 0xe * 8 ..][0..8], &kBytesForNewTile0xE_TopOfL);
        @memcpy(vram[0x7000 + 0xf * 8 ..][0..8], &kBytesForNewTile0xF_BottomofL);
    }
}

pub export fn Hud_DrawYButtonItems() callconv(.c) void { // 8de3d9
    const dst = uvram();
    const x: i32 = if (kNewStyleInventory) 0 else 1;

    const btn_index = GetCurrentItemButtonIndex();
    CopyTilesForSwitchLR(btn_index);
    Hud_DrawBox(dst, x, 5, 20 - x, 19, t.kSwitchLR_palettes[@intCast(btn_index)]);

    if (!kNewStyleInventory) {
        at(dst, HUDXY(2, 6)).* = t.kEquipmentLetterTiles[@intCast(btn_index)][0];
        at(dst, HUDXY(2, 7)).* = t.kEquipmentLetterTiles[@intCast(btn_index)][1];
    }
    at(dst, HUDXY(x + 2, 5)).* = 0x246E;
    at(dst, HUDXY(x + 3, 5)).* = 0x246F;

    for (0..kHudItemCount) |i| {
        const j = features.hud_inventory_order[i];
        Hud_DrawItem(
            at(dst, @intCast(kHudItemInVramPtr[i])),
            Hud_GetIconForItem(if (j == 0) @as(i32, @intCast(i + 1)) else j),
        );
    }
}

pub export fn Hud_DrawAbilityBox() callconv(.c) void { // 8de6b6
    const dst = uvram();
    const x: i32 = if (kNewStyleInventory) 0 else 1;

    Hud_DrawBox(dst, x, 21, 19, 29, 1);

    var flags = vars.link_ability_flags.*;
    for (0..2) |i| {
        for (0..3) |j| {
            if (flags & 0x80 != 0)
                Hud_DrawNxN(
                    at(dst, HUDXY(4 + @as(i32, @intCast(j)) * 5, 22 + @as(i32, @intCast(i)) * 2)),
                    t.kHudAbilityText[i * 40 + j * 10 ..],
                    5,
                    2,
                );
            flags = flags << 1;
        }
        flags = flags << 1;
    }
    // A
    if (!kNewStyleInventory) {
        at(dst, HUDXY(2, 22)).* = 0xA4F0;
        at(dst, HUDXY(2, 23)).* = 0x24F2;
    }
    // DO text
    at(dst, HUDXY(x + 2, 21)).* = 0x2482;
    at(dst, HUDXY(x + 3, 21)).* = 0x2483;

    Hud_DrawItem(at(dst, HUDXY(8, 27)), &t.kHudItemGloves[vars.link_item_gloves.*]);
    Hud_DrawItem(at(dst, HUDXY(4, 27)), &t.kHudItemBoots[vars.link_item_boots.*]);
    Hud_DrawItem(at(dst, HUDXY(12, 27)), &t.kHudItemFlippers[vars.link_item_flippers.*]);
    Hud_DrawItem(at(dst, HUDXY(16, 27)), &t.kHudItemMoonPearl[vars.link_item_moon_pearl.*]);
    if (vars.link_item_gloves.* != 0)
        Hud_DrawNxN(
            at(dst, HUDXY(4, 22)),
            t.kHudGlovesText[@as(usize, @intFromBool(vars.link_item_gloves.* != 1)) * 10 ..],
            5,
            2,
        );
}

pub export fn Hud_DrawProgressIcons() callconv(.c) void { // 8de9c8
    if (vars.sram_progress_indicator.* < 3) {
        Hud_DrawProgressIcons_Pendants();
    } else {
        Hud_DrawProgressIcons_Crystals();
    }
}

pub export fn Hud_DrawProgressIcons_Pendants() callconv(.c) void { // 8de9d3
    const dst = at(uvram(), if (kNewStyleInventory) HUDXY(22, 11) else HUDXY(21, 11));
    Hud_DrawNxN(dst, &t.kProgressIconPendantsBg, 10, 9);
    const p: [*]align(1) u16 = @ptrCast(dst);
    Hud_DrawItem(at(p, HUDXY(4, 3)), &t.kHudPendants0[(vars.link_which_pendants.* >> 0) & 1]);
    Hud_DrawItem(at(p, HUDXY(2, 6)), &t.kHudPendants1[(vars.link_which_pendants.* >> 1) & 1]);
    Hud_DrawItem(at(p, HUDXY(6, 6)), &t.kHudPendants2[(vars.link_which_pendants.* >> 2) & 1]);
}

pub export fn Hud_DrawProgressIcons_Crystals() callconv(.c) void { // 8dea62
    const dst = at(uvram(), if (kNewStyleInventory) HUDXY(22, 11) else HUDXY(21, 11));
    Hud_DrawNxN(dst, &t.kProgressIconCrystalsBg, 10, 9);
    const p: [*]align(1) u16 = @ptrCast(dst);

    const f = vars.link_has_crystals.*;
    const spots = [7][2]i32{
        .{ 3, 3 }, .{ 5, 3 }, .{ 2, 5 }, .{ 4, 5 }, .{ 6, 5 }, .{ 3, 7 }, .{ 5, 7 },
    };
    for (spots, 0..) |s, i| {
        if (f & (@as(u8, 1) << @intCast(i)) != 0) {
            at(p, HUDXY(s[0], s[1])).* = 0x2D44;
            at(p, HUDXY(s[0] + 1, s[1])).* = 0x2D45;
        }
    }
}

pub export fn Hud_DrawSelectedYButtonItem() callconv(.c) void { // 8deb3a
    const dst_org = uvram();
    const dst_box = dst_org + (if (kNewStyleInventory) @as(usize, 1) else 0);

    const btn_index = GetCurrentItemButtonIndex();
    const item: i32 = GetCurrentItemButtonPtr(btn_index).*;
    Hud_DrawBox(dst_box, 21, 5, 21 + 9, 10, t.kSwitchLR_palettes[@intCast(btn_index)]);

    // Display either the current item or the item assigned
    // to the x, l, or r key.
    if (item != 0) {
        const p = at(dst_org, @intCast(kHudItemInVramPtr[@intCast(Hud_GetItemPosition(item))]));
        Hud_Copy2x2(at(dst_box, HUDXY(25, 6)), p);
        if (vars.timer_for_flashing_circle.* & 0x10 != 0)
            Hud_DrawFlashingCircle(@ptrCast(p), t.kSwitchLR_palettes[@intCast(btn_index)]);
    }

    const src_p: []const u16 = blk: {
        if (item == kHudItem_BottleOld and !kNewStyleInventory and vars.link_item_bottle_index.* != 0)
            break :blk t.kHudBottlesItemText[
                @as(usize, vars.link_bottle_info[vars.link_item_bottle_index.* - 1] - 1) * 16 ..
            ];
        if (item == 5 and vars.link_item_mushroom.* != 1)
            break :blk t.kHudMushroomItemText[@as(usize, vars.link_item_mushroom.* - 2) * 16 ..];
        if (item == 20 and vars.link_item_mirror.* != 1)
            break :blk t.kHudMirrorItemText[@as(usize, vars.link_item_mirror.* - 2) * 16 ..];
        if (item == 13 and vars.link_item_flute.* != 1)
            break :blk t.kHudFluteItemText[@as(usize, vars.link_item_flute.* - 2) * 16 ..];
        if (item == 1 and vars.link_item_bow.* != 1)
            break :blk t.kHudBowItemText[@as(usize, vars.link_item_bow.* - 2) * 16 ..];
        if (item >= kHudItem_Bottle1 and item <= kHudItem_Bottle4)
            break :blk t.kHudBottlesItemText[
                @as(usize, vars.link_bottle_info[@intCast(item - kHudItem_Bottle1)] - 1) * 16 ..
            ];
        if (item == kHudItem_Shovel)
            break :blk t.kHudItemText[(13 - 1) * 16 ..];
        if (item == 0)
            break :blk if (btn_index != 0) t.kNotAssignedItemText[0..] else t.kHudItemText[(20 - 1) * 16 ..];
        break :blk t.kHudItemText[@as(usize, @intCast(item - 1)) * 16 ..];
    };
    Hud_DrawNxN(at(dst_box, HUDXY(22, 8)), src_p, 8, 2);
}

pub export fn Hud_DrawEquipmentBox() callconv(.c) void { // 8ded29
    const dst = uvram() + (if (kNewStyleInventory) @as(usize, 1) else 0);

    Hud_DrawBox(dst, 21, 21, 30, 29, 2);

    // Draw dotted lines
    for (0..8) |i|
        at(dst, HUDXY(22 + @as(i32, @intCast(i)), 25)).* = 0x28D7;

    for (0..8) |i| {
        at(dst, HUDXY(22 + @as(i32, @intCast(i)), 22)).* = t.kHudEquipmentDungeonItemText[i];
        at(dst, HUDXY(22 + @as(i32, @intCast(i)), 26)).* = t.kHudEquipmentDungeonItemText[8 + i];
    }

    if (vars.cur_palace_index_x2.* == 0xff) {
        for (0..8) |i|
            at(dst, HUDXY(22 + @as(i32, @intCast(i)), 26)).* = 0x24F5;
        Hud_DrawItem(at(dst, HUDXY(25, 27)), &t.kHudItemHeartPieces[vars.link_heart_pieces.*]);
    }
    Hud_DrawItem(at(dst, HUDXY(22, 23)), &t.kHudItemSword[
        if (vars.link_sword_type.* == 0xff) 0 else vars.link_sword_type.*
    ]);
    Hud_DrawItem(at(dst, HUDXY(25, 23)), &t.kHudItemShield[vars.link_shield_type.*]);
    Hud_DrawItem(at(dst, HUDXY(28, 23)), &t.kHudItemArmor[vars.link_armor.*]);

    // The C tests `cur_palace_index_x2 != 0xff` first and `&&` short-circuits,
    // so the shift is only evaluated inside a palace. Hoisting it out of the
    // condition made the overworld value (0xff >> 1 == 127) overflow the u4
    // shift amount and trap when the menu opened.
    if (vars.cur_palace_index_x2.* != 0xff) {
        const sh: u4 = @intCast(vars.cur_palace_index_x2.* >> 1);
        if ((vars.link_bigkey.* << sh) & 0x8000 != 0)
            Hud_DrawItem(at(dst, HUDXY(28, 27)), &t.kHudItemPalaceItem[CheckPalaceItemPosession()]);
        if ((vars.link_dungeon_map.* << sh) & 0x8000 != 0)
            Hud_DrawItem(at(dst, HUDXY(22, 27)), &t.kHudItemDungeonMap[0]);
        if ((vars.link_compass.* << sh) & 0x8000 != 0)
            Hud_DrawItem(at(dst, HUDXY(25, 27)), &t.kHudItemDungeonCompass[0]);
    }
}

fn Hud_IntToDecimal(number: u32, out: *[4]u8) void { // 8df0f7
    out[0] = @intCast(number / 1000 + 0x90);
    var n = number % 1000;
    out[1] = @intCast(n / 100 + 0x90);
    n %= 100;
    out[2] = @intCast(n / 10 + 0x90);
    out[3] = @intCast(n % 10 + 0x90);
}

pub export fn Hud_RefillHealth() callconv(.c) bool { // 8df128
    if (vars.link_health_current.* >= vars.link_health_capacity.*) {
        vars.link_health_current.* = vars.link_health_capacity.*;
        vars.link_hearts_filler.* = 0;
        return vars.is_doing_heart_animation.* == 0;
    }
    vars.link_hearts_filler.* = 160;
    return false;
}

pub export fn Hud_AnimateHeartRefill() callconv(.c) void { // 8df14f
    vars.animate_heart_refill_countdown.* -%= 1;
    if (vars.animate_heart_refill_countdown.* != 0)
        return;
    var n: u16 = ((@as(u16, vars.link_health_current.* & ~@as(u8, 7)) -% 1) >> 3) << 1;
    var p = at(hudbuf(), HUDXY(20, 1));
    if (n >= 20) {
        n -= 20;
        p = at(@as([*]align(1) u16, @ptrCast(p)), 0x20);
    }
    n &= 0xff;
    vars.animate_heart_refill_countdown.* = 1;

    @as([*]align(1) u16, @ptrCast(p))[n >> 1] =
        t.kAnimHeartPartial[vars.animate_heart_refill_countdown_subpos.*];

    vars.animate_heart_refill_countdown_subpos.* =
        (vars.animate_heart_refill_countdown_subpos.* +% 1) & 3;
    if (vars.animate_heart_refill_countdown_subpos.* == 0) {
        Hud_Rebuild();
        vars.is_doing_heart_animation.* = 0;
    }
}

pub export fn Hud_RefillMagicPower() callconv(.c) bool { // 8df1b3
    if (vars.link_magic_power.* >= 0x80)
        return true;
    vars.link_magic_filler.* = 0x80;
    return false;
}

pub export fn Hud_RestoreTorchBackground() callconv(.c) void { // 8dfa33
    if (vars.link_item_torch.* == 0 or vars.dung_want_lights_out.* == 0 or
        vars.hdr_dungeon_dark_with_lantern.* != 0 or vars.dung_num_lit_torches.* != 0)
        return;
    vars.hdr_dungeon_dark_with_lantern.* = 1;
    if (vars.dung_hdr_bg2_properties.* != 2)
        vars.TS_copy.* = 1;
}

pub export fn Hud_RebuildIndoor() callconv(.c) void { // 8dfa60
    vars.overworld_fixed_color_plusminus.* = 0;
    vars.link_num_keys.* = 0xff;
    Hud_Rebuild();
}

fn Hud_UpdateItemBox() void { // 8dfafd
    // Update r
    if (vars.hud_cur_item.* != 0)
        Hud_DrawItem(at(hudbuf(), HUDXY(5, 1)), Hud_GetIconForItem(vars.hud_cur_item.*));
}

fn Hud_UpdateHearts_Inner(dst: *align(1) u16, src: []const u16, n_in: i32) void { // 8dfdab
    var p: [*]align(1) u16 = @ptrCast(dst);
    var x: usize = 0;
    var n = n_in;
    while (n > 0) {
        if (x >= 10) {
            p += 0x20;
            x = 0;
        }
        p[x] = src[if (n >= 5) 2 else 1];
        x += 1;
        n -= 8;
    }
}

fn DrawHudComponents(dst: *align(1) u16, src: []const u16, w: usize, h: usize) void {
    var p: [*]align(1) u16 = @ptrCast(dst);
    var s: usize = 0;
    var i = h;
    while (i != 0) : (i -= 1) {
        @memcpy(p[0..w], src[s..][0..w]);
        s += w;
        p += 32;
    }
}

fn Hud_Update_Hearts() void { // 8dfb94
    // The life meter
    Hud_UpdateHearts_Inner(at(hudbuf(), HUDXY(20, 1)), &t.kHudItemBoxTab1, vars.link_health_capacity.*);
    Hud_UpdateHearts_Inner(at(hudbuf(), HUDXY(20, 1)), &t.kHudItemBoxTab2, (@as(i32, vars.link_health_current.*) + 3) & ~@as(i32, 3));
}

fn Hud_Update_Magic() void { // 8dfc09
    const dst: [*]align(1) u16 = @ptrCast(at(hudbuf(), HUDXY(2, 0)));
    if (vars.link_magic_consumption.* >= 1) {
        at(dst, HUDXY(0, 0)).* = 0x28F7;
        at(dst, HUDXY(1, 0)).* = 0x2851;
        at(dst, HUDXY(2, 0)).* = 0x28FA;
    }
    const src = t.kUpdateMagicPowerTilemap[(@as(usize, vars.link_magic_power.*) + 7) >> 3];
    at(dst, HUDXY(1, 1)).* = src[0];
    at(dst, HUDXY(1, 2)).* = src[1];
    at(dst, HUDXY(1, 3)).* = src[2];
    at(dst, HUDXY(1, 4)).* = src[3];
}

fn Hud_Update_Inventory() void { // 8dfc09
    var d: [4]u8 = undefined;
    Hud_IntToDecimal(vars.link_rupees_actual.*, &d);

    const base_tiles = [2]u16{
        0x2400,
        if (features.enhanced_features0.* & features.kFeatures0_ShowMaxItemsInYellow != 0) 0x3400 else 0x2400,
    };

    const inv_offs: usize = if (d[0] == 0x90) 1 else 0;

    var dst: [*]align(1) u16 = @ptrCast(at(hudbuf(), HUDXY(8, 0)));
    @memcpy(@as([*]align(1) u16, @ptrCast(at(dst, HUDXY(0, 0))))[0..12], t.kHudInventoryBg[0 + inv_offs ..][0..12]);
    @memcpy(@as([*]align(1) u16, @ptrCast(at(dst, HUDXY(0, 1))))[0..12], t.kHudInventoryBg[13 + inv_offs ..][0..12]);

    if (vars.link_item_bow.* != 0) {
        if (vars.link_item_bow.* >= 3) {
            // Silver arrows swap the arrow icon for their own. It has to
            // move with the row: with four rupee digits (Carry More Rupees
            // and 1000 or more) everything above shifts a tile right, and a
            // silver arrow left where the row used to be landed a tile short,
            // with the plain arrow's tip still showing beside it.
            const col: i32 = 16 - @as(i32, @intCast(inv_offs));
            at(hudbuf(), HUDXY(col, 0)).* = 0x2486;
            at(hudbuf(), HUDXY(col + 1, 0)).* = 0x2487;
            vars.link_item_bow.* = if (vars.link_num_arrows.* != 0) 4 else 3;
        } else {
            vars.link_item_bow.* = if (vars.link_num_arrows.* != 0) 2 else 1;
        }
    }

    // Offset everything if we have many coins?
    var base_tile = base_tiles[@intFromBool(vars.link_rupees_actual.* == MaxRupees())];
    if (inv_offs == 0) {
        dst += 1;
        at(dst, HUDXY(-1, 1)).* = base_tile | d[0];
    }
    at(dst, HUDXY(0, 1)).* = base_tile | d[1];
    at(dst, HUDXY(1, 1)).* = base_tile | d[2];
    at(dst, HUDXY(2, 1)).* = base_tile | d[3];

    Hud_IntToDecimal(vars.link_item_bombs.*, &d);
    base_tile = base_tiles[@intFromBool(vars.link_item_bombs.* == t.kMaxBombsForLevel[vars.link_bomb_upgrades.*])];
    at(dst, HUDXY(4, 1)).* = base_tile | d[2];
    at(dst, HUDXY(5, 1)).* = base_tile | d[3];

    Hud_IntToDecimal(vars.link_num_arrows.*, &d);
    base_tile = base_tiles[@intFromBool(vars.link_num_arrows.* == t.kMaxArrowsForLevel[vars.link_arrow_upgrades.*])];
    at(dst, HUDXY(7, 1)).* = base_tile | d[2];
    at(dst, HUDXY(8, 1)).* = base_tile | d[3];

    // Show keys
    d[3] = 0x7f;
    if (vars.link_num_keys.* != 0xff)
        Hud_IntToDecimal(vars.link_num_keys.*, &d);
    at(dst, HUDXY(10, 1)).* = 0x2400 | @as(u16, d[3]);
    if (at(dst, HUDXY(10, 1)).* == 0x247f)
        at(dst, HUDXY(10, 0)).* = 0x247f;
}

pub export fn Hud_Rebuild() callconv(.c) void { // 8dfa70
    // Ensure all of the 165 hud words are initialized.
    // This was broken by my previous reorg... quick fix for now.
    if (at(hudbuf(), HUDXY(8, 2)).* == 0) {
        for (0..165) |i|
            hudbuf()[i] = 0x207f;
    }

    // The magic meter and item box
    DrawHudComponents(@ptrCast(hudbuf()), &t.kHudTilemapLeftPart, 8, 6);
    DrawHudComponents(at(hudbuf(), HUDXY(20, 0)), &t.kHudTilemapRightPart, 12, 5);

    Hud_Update_Hearts();
    Hud_Update_Magic();
    Hud_Update_Inventory();
    Hud_UpdateItemBox();
    vars.flag_update_hud_in_nmi.* +%= 1;
}

pub export fn Hud_GetItemBoxPtr(item: c_int) callconv(.c) [*]const u16 {
    return &kHudItemBoxGfxPtrs[@intCast(item)][0].v;
}

pub export fn Hud_HandleItemSwitchInputs() callconv(.c) void {
    if (features.enhanced_features0.* & features.kFeatures0_SwitchLR == 0)
        return;
    // L and R together open the map; they don't also switch items.
    if (hasItemOnX() and holdingLAndR())
        return;

    var direction: bool = undefined;

    if (vars.filtered_joypad_L.* & kJoypadL_L != 0 and features.hud_cur_item_l.* == 0) {
        direction = features.hud_cur_item_r.* != 0;
    } else if (vars.filtered_joypad_L.* & kJoypadL_R != 0 and features.hud_cur_item_r.* == 0) {
        direction = true;
    } else {
        return;
    }

    var item = vars.hud_cur_item.*;
    for (0..kHudItemCount) |_| {
        if (!direction) {
            Hud_GotoPrevItem(&item, 1);
        } else {
            Hud_GotoNextItem(&item, 1);
        }
        if (Hud_DoWeHaveThisItem(item) and
            (features.enhanced_features0.* & features.kFeatures0_SwitchLRLimit == 0 or
                Hud_GetItemPosition(item) <= 3))
        {
            if (item != vars.hud_cur_item.*) {
                vars.hud_cur_item.* = item;
                vars.sound_effect_2.* = 32;
                Hud_UpdateEquippedItem();
                Hud_UpdateItemBox();
                vars.flag_update_hud_in_nmi.* +%= 1;
            }
            break;
        }
    }
}

fn Hud_ReorderItem(direction: i32) void {
    // Initialize inventory order on first use
    if (features.hud_inventory_order[0] == 0) {
        for (0..24) |i|
            features.hud_inventory_order[i] = @intCast(i + 1);
    }
    const old_pos = Hud_GetItemPosition(vars.hud_cur_item.*);
    var new_pos = old_pos + direction;
    if (new_pos < 0) {
        new_pos += kHudItemCount;
    } else if (new_pos >= kHudItemCount) {
        new_pos -= kHudItemCount;
    }
    const tmp = features.hud_inventory_order[@intCast(old_pos)];
    features.hud_inventory_order[@intCast(old_pos)] = features.hud_inventory_order[@intCast(new_pos)];
    features.hud_inventory_order[@intCast(new_pos)] = tmp;
    Hud_DrawYButtonItems();
    vars.sound_effect_2.* = 32;
}

const testing = std.testing;

test "the generated tables kept their declared sizes" {
    try testing.expectEqual(20, t.kHudItemInVramPtr_Old.len);
    try testing.expectEqual(24, t.kHudItemInVramPtr_New.len);
    try testing.expectEqual(48, t.kHudTilemapLeftPart.len); // zero padded from 45
    try testing.expectEqual(60, t.kHudTilemapRightPart.len);
    try testing.expectEqual(16, t.kNotAssignedItemText.len);
    try testing.expectEqual(320, t.kHudItemText.len);
    try testing.expectEqual(128, t.kHudBottlesItemText.len);
    try testing.expectEqual(90, t.kProgressIconPendantsBg.len);
    try testing.expectEqual(90, t.kProgressIconCrystalsBg.len);
    try testing.expectEqual(17, t.kUpdateMagicPowerTilemap.len);
    try testing.expectEqual(5, t.kHudItemArmor.len); // zero padded from 3
    try testing.expectEqual(4, t.kEquipmentLetterTiles.len);
    try testing.expectEqual(32, kHudItemBoxGfxPtrs.len);
}

test "HUDXY addresses the 32 word wide tilemap" {
    try testing.expectEqual(0, HUDXY(0, 0));
    try testing.expectEqual(32, HUDXY(0, 1));
    try testing.expectEqual(33, HUDXY(1, 1));
    // The generated vram pointers agree with the macro.
    try testing.expectEqual(@as(u16, @intCast(HUDXY(4, 7))), t.kHudItemInVramPtr_Old[0]);
    try testing.expectEqual(@as(u16, @intCast(HUDXY(16, 16))), t.kHudItemInVramPtr_Old[19]);
    // Negative offsets are used by the flashing circle.
    try testing.expectEqual(-32, HUDXY(0, -1));
    try testing.expectEqual(-33, HUDXY(-1, -1));
}

test "the equipment letter tiles evaluate their C expressions" {
    // {0x3CF0, 0x3CF1}, then 0x2CF0 | 0x8000, then 0x200E | 4 << 10.
    try testing.expectEqual(@as(u16, 0x3CF0), t.kEquipmentLetterTiles[0][0]);
    try testing.expectEqual(@as(u16, 0x3CF1), t.kEquipmentLetterTiles[0][1]);
    try testing.expectEqual(@as(u16, 0xACF0), t.kEquipmentLetterTiles[1][1]);
    try testing.expectEqual(@as(u16, 0x300E), t.kEquipmentLetterTiles[2][0]);
    try testing.expectEqual(@as(u16, 0x300D), t.kEquipmentLetterTiles[3][1]);
}

test "the not-assigned text spells NOT ASSIGNED" {
    // L(x) maps 'A'..'Z' onto 0x2550.. and space onto 0x24f5.
    const L = struct {
        fn f(comptime ch: u8) u16 {
            return if (ch == ' ') 0x24f5 else 0x2550 + @as(u16, ch) - 'A';
        }
    }.f;
    const want = [16]u16{
        L('N'), L('O'), L('T'), L(' '), L(' '), L(' '), L(' '), L(' '),
        L('A'), L('S'), L('S'), L('I'), L('G'), L('N'), L('E'), L('D'),
    };
    try testing.expectEqualSlices(u16, &want, &t.kNotAssignedItemText);
}

test "the item count follows the inventory style" {
    try testing.expectEqual(false, kNewStyleInventory);
    try testing.expectEqual(20, kHudItemCount);
    try testing.expectEqual(20, kHudItemInVramPtr.len);
}

test "decimal conversion offsets each digit by 0x90" {
    var d: [4]u8 = undefined;
    Hud_IntToDecimal(0, &d);
    try testing.expectEqualSlices(u8, &.{ 0x90, 0x90, 0x90, 0x90 }, &d);
    Hud_IntToDecimal(1234, &d);
    try testing.expectEqualSlices(u8, &.{ 0x91, 0x92, 0x93, 0x94 }, &d);
    Hud_IntToDecimal(999, &d);
    try testing.expectEqualSlices(u8, &.{ 0x90, 0x99, 0x99, 0x99 }, &d);
    Hud_IntToDecimal(305, &d);
    try testing.expectEqualSlices(u8, &.{ 0x90, 0x93, 0x90, 0x95 }, &d);
}

test "palace item possession keys off the dungeon index" {
    @memset(g_ram[0..0x20000], 0);
    // Index 2 (>>1 of 4) asks about the bow.
    vars.cur_palace_index_x2.* = 4;
    try testing.expectEqual(@as(u8, 0), CheckPalaceItemPosession());
    vars.link_item_bow.* = 1;
    try testing.expectEqual(@as(u8, 1), CheckPalaceItemPosession());
    // Index 11 inverts: it wants gloves != 1.
    vars.cur_palace_index_x2.* = 22;
    vars.link_item_gloves.* = 1;
    try testing.expectEqual(@as(u8, 0), CheckPalaceItemPosession());
    vars.link_item_gloves.* = 2;
    try testing.expectEqual(@as(u8, 1), CheckPalaceItemPosession());
    // Anything unmapped is 0.
    vars.cur_palace_index_x2.* = 0;
    try testing.expectEqual(@as(u8, 0), CheckPalaceItemPosession());
}

test "having any item scans the twenty save-game bytes" {
    @memset(g_ram[0..0x20000], 0);
    try testing.expect(!Hud_HaveAnyItems());
    // The last of the twenty still counts.
    linkItems()[19] = 1;
    try testing.expect(Hud_HaveAnyItems());
    linkItems()[19] = 0;
    linkItems()[0] = 1;
    try testing.expect(Hud_HaveAnyItems());
}

test "the max tables bound the refill logic" {
    try testing.expectEqual(8, t.kMaxBombsForLevel.len);
    try testing.expectEqual(8, t.kMaxArrowsForLevel.len);
    try testing.expectEqual(21, t.kMaxHealthForLevel.len);
    try testing.expectEqual(@as(u8, 10), t.kMaxBombsForLevel[0]);
    try testing.expectEqual(@as(u8, 50), t.kMaxBombsForLevel[7]);
    try testing.expectEqual(@as(u8, 30), t.kMaxArrowsForLevel[0]);
    try testing.expectEqual(@as(u8, 70), t.kMaxArrowsForLevel[7]);
    // Health capacity indexes by >>3, so 21 entries covers the 0xa0 max.
    try testing.expectEqual(@as(u8, 25), t.kMaxHealthForLevel[20]);
}

test "the rupee cap follows the carry-more feature bit" {
    @memset(g_ram[0..0x20000], 0);
    features.enhanced_features0.* = 0;
    try testing.expectEqual(@as(u16, 999), MaxRupees());
    features.enhanced_features0.* = features.kFeatures0_CarryMoreRupees;
    try testing.expectEqual(@as(u16, 9999), MaxRupees());
    features.enhanced_features0.* = 0;
}

test "the PV macro interleaves the two bitplanes" {
    // All ones sets only the low plane, across all eight columns.
    try testing.expectEqual(@as(u16, 0x00ff), PV(.{ 1, 1, 1, 1, 1, 1, 1, 1 }));
    // A 3 sets both planes for that column; column 0 is the high bit.
    try testing.expectEqual(@as(u16, 0x80ff), PV(.{ 3, 1, 1, 1, 1, 1, 1, 1 }));
    try testing.expectEqual(@as(u16, 0x01ff), PV(.{ 1, 1, 1, 1, 1, 1, 1, 3 }));
    try testing.expectEqual(8, kBytesForNewTile0xC_TopOfR.len);
    try testing.expectEqual(8, kBytesForNewTile0xF_BottomofL.len);
}

test "the silver arrow sits where the arrow is, three rupee digits or four" {
    defer @memset(g_ram[0..0x20000], 0);
    for ([_]struct { rupees: u16, col: i32 }{
        .{ .rupees = 500, .col = 15 }, // the original game's layout
        .{ .rupees = 1500, .col = 16 }, // four digits shift the row a tile
    }) |case| {
        @memset(g_ram[0..0x20000], 0);
        vars.link_rupees_actual.* = case.rupees;
        vars.link_item_bow.* = 3;
        vars.link_num_arrows.* = 10;
        Hud_Update_Inventory();
        try testing.expectEqual(@as(u16, 0x2486), at(hudbuf(), HUDXY(case.col, 0)).*);
        try testing.expectEqual(@as(u16, 0x2487), at(hudbuf(), HUDXY(case.col + 1, 0)).*);
        // Nothing of the plain arrow is left beside it.
        const after = at(hudbuf(), HUDXY(case.col + 2, 0)).*;
        try testing.expect(after != 0x20a7 and after != 0x20a9);
    }
}

test "with a second item on X, the map is L and R together" {
    defer @memset(g_ram[0..0x20000], 0);
    @memset(g_ram[0..0x20000], 0);
    features.enhanced_features0.* = features.kFeatures0_ItemOnX | features.kFeatures0_SwitchLR;
    defer features.enhanced_features0.* = 0;

    // Nothing on X yet: X stays the map.
    try testing.expect(!hasItemOnX());
    features.hud_cur_item_x.* = 3;
    try testing.expect(hasItemOnX());

    // Both held, one just pressed: the map, once.
    vars.joypad1L_last.* = kJoypadL_L | kJoypadL_R;
    vars.filtered_joypad_L.* = kJoypadL_R;
    try testing.expect(pressedLAndR());
    vars.filtered_joypad_L.* = 0;
    try testing.expect(!pressedLAndR());
    // One alone isn't it.
    vars.joypad1L_last.* = kJoypadL_L;
    vars.filtered_joypad_L.* = kJoypadL_L;
    try testing.expect(!pressedLAndR());

    // Holding both doesn't reach for whatever item L has.
    vars.joypad1L_last.* = kJoypadL_L | kJoypadL_R;
    try testing.expectEqual(@as(c_int, 0), GetCurrentItemButtonIndex());
    // X still means X's item.
    vars.joypad1L_last.* = kJoypadL_X;
    try testing.expectEqual(@as(c_int, 1), GetCurrentItemButtonIndex());
    // With the feature off, X isn't an item button at all.
    features.enhanced_features0.* = features.kFeatures0_SwitchLR;
    try testing.expectEqual(@as(c_int, 0), GetCurrentItemButtonIndex());
    try testing.expect(!hasItemOnX());
}
