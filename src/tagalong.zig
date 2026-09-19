//! Port of src/tagalong.c: the follower that walks behind Link -- the old man,
//! the maiden, Kiki, the super bomb -- including its trail buffer, its message
//! triggers and its sprite drawing.
const std = @import("std");
const vars = @import("variables.zig");
const features = @import("features.zig");

const OamEnt = vars.OamEnt;
const g_ram = &vars.g_ram;
const enhanced_features0 = features.enhanced_features0;
const kFeatures0_TurnWhileDashing = features.kFeatures0_TurnWhileDashing;
const kFeatures0_MiscBugFixes = features.kFeatures0_MiscBugFixes;

/// tagalong.h
pub const TagalongMessageInfo = extern struct {
    y: u16,
    x: u16,
    bit: u16,
    msg: u16,
    tagalong: u16,
};

/// types.h
const ProjectSpeedRet = extern struct {
    x: u8,
    y: u8,
    xdiff: u8,
    ydiff: u8,
};

// player.h
const kPlayerState_Ground = 0;
const kPlayerState_Swimming = 4;
const kPlayerState_RecoilOther = 6;
const kPlayerState_Ether = 8;
const kPlayerState_Bombos = 9;
const kPlayerState_Quake = 10;
const kPlayerState_StartDash = 17;
const kPlayerState_Hookshot = 19;

// Still in C: ancilla.c, sprite.c, sprite_main.c and misc.c.
extern fn Ancilla_ProjectSpeedTowardsPlayer(k: c_int, vel: u8) ProjectSpeedRet;
extern fn Ancilla_MoveX(k: c_int) void;
extern fn Ancilla_MoveY(k: c_int) void;
extern fn Ancilla_GetX(k: c_int) u16;
extern fn Ancilla_GetY(k: c_int) u16;
extern fn AncillaAdd_SuperBombExplosion(a: u8, y: u8) c_int;
extern fn Sprite_GetX(k: c_int) u16;
extern fn Sprite_GetY(k: c_int) u16;
extern fn Sprite_SetX(k: c_int, x: u16) void;
extern fn Sprite_SetY(k: c_int, y: u16) void;
extern fn Sprite_SpawnDynamically(k: c_int, what: u8, info: *SpriteSpawnInfo) c_int;
extern fn SpritePrep_LoadProperties(k: c_int) void;
extern fn OldMan_RevertToSprite(k: c_int) void;
extern fn Main_ShowTextMessage() void;

/// sprite.h
const SpriteSpawnInfo = extern struct {
    r0_x: u16,
    r2_y: u16,
    r4_z: u8,
    r5_overlord_x: u16,
    r7_overlord_y: u16,
};

const main_module_index = vars.main_module_index;
const submodule_index = vars.submodule_index;
const frame_counter = vars.frame_counter;
const player_is_indoors = vars.player_is_indoors;
const link_x_coord = vars.link_x_coord;
const link_y_coord = vars.link_y_coord;
const link_z_coord = vars.link_z_coord;
const link_x_vel = vars.link_x_vel;
const link_y_vel = vars.link_y_vel;
const link_direction_facing = vars.link_direction_facing;
const link_is_on_lower_level = vars.link_is_on_lower_level;
const link_player_handler_state = vars.link_player_handler_state;
const link_is_running = vars.link_is_running;
const link_speed_setting = vars.link_speed_setting;
const link_auxiliary_state = vars.link_auxiliary_state;
const link_state_bits = vars.link_state_bits;
const link_grabbing_wall = vars.link_grabbing_wall;
const link_item_in_hand = vars.link_item_in_hand;
const link_position_mode = vars.link_position_mode;
const link_unk_master_sword = vars.link_unk_master_sword;
const button_mask_b_y = vars.button_mask_b_y;
const filtered_joypad_L = vars.filtered_joypad_L;
const flag_is_link_immobilized = vars.flag_is_link_immobilized;
const flag_is_ancilla_to_pick_up = vars.flag_is_ancilla_to_pick_up;
const flag_is_sprite_to_pick_up = vars.flag_is_sprite_to_pick_up;
const player_near_pit_state = vars.player_near_pit_state;
const related_to_hookshot = vars.related_to_hookshot;
const draw_water_ripples_or_grass = vars.draw_water_ripples_or_grass;
const countdown_for_blink = vars.countdown_for_blink;
const palette_swap_flag = vars.palette_swap_flag;
const sort_sprites_setting = vars.sort_sprites_setting;
const swimcoll_var7 = vars.swimcoll_var7;

const tagalong_y_lo = vars.tagalong_y_lo;
const tagalong_y_hi = vars.tagalong_y_hi;
const tagalong_x_lo = vars.tagalong_x_lo;
const tagalong_x_hi = vars.tagalong_x_hi;
const tagalong_z = vars.tagalong_z;
const tagalong_layerbits = vars.tagalong_layerbits;
const tagalong_var1 = vars.tagalong_var1;
const tagalong_var2 = vars.tagalong_var2;
const tagalong_var3 = vars.tagalong_var3;
const tagalong_var4 = vars.tagalong_var4;
const tagalong_var5 = vars.tagalong_var5;
const tagalong_var7 = vars.tagalong_var7;
const tagalong_event_flags = vars.tagalong_event_flags;
const timer_tagalong_reacquire = vars.timer_tagalong_reacquire;
const follower_indicator = vars.follower_indicator;
const follower_dropped = vars.follower_dropped;
const saved_tagalong_x = vars.saved_tagalong_x;
const saved_tagalong_y = vars.saved_tagalong_y;
const saved_tagalong_floor = vars.saved_tagalong_floor;
const saved_tagalong_indoors = vars.saved_tagalong_indoors;

const ancilla_x_lo = vars.ancilla_x_lo;
const ancilla_x_hi = vars.ancilla_x_hi;
const ancilla_y_lo = vars.ancilla_y_lo;
const ancilla_y_hi = vars.ancilla_y_hi;
const ancilla_x_vel = vars.ancilla_x_vel;
const ancilla_y_vel = vars.ancilla_y_vel;

const sprite_state = vars.sprite_state;
const sprite_type = vars.sprite_type;
const sprite_D = vars.sprite_D;
const sprite_z = vars.sprite_z;
const sprite_z_vel = vars.sprite_z_vel;
const sprite_floor = vars.sprite_floor;
const sprite_graphics = vars.sprite_graphics;
const sprite_subtype2 = vars.sprite_subtype2;
const sprite_head_dir = vars.sprite_head_dir;
const sprite_delay_aux2 = vars.sprite_delay_aux2;
const sprite_ignore_projectile = vars.sprite_ignore_projectile;

const word_7E02CD = vars.word_7E02CD;
const byte_7E02D7 = vars.byte_7E02D7;
const byte_7E0B69 = vars.byte_7E0B69;
const dialogue_message_index = vars.dialogue_message_index;
const overworld_screen_index = vars.overworld_screen_index;
const dungeon_room_index = vars.dungeon_room_index;
const super_bomb_indicator_unk1 = vars.super_bomb_indicator_unk1;
const super_bomb_indicator_unk2 = vars.super_bomb_indicator_unk2;
const save_dung_info = vars.save_dung_info;
const save_ow_event_info = vars.save_ow_event_info;
const dung_savegame_state_bits = vars.dung_savegame_state_bits;
const dung_flag_trapdoors_down = vars.dung_flag_trapdoors_down;
const dung_cur_door_pos = vars.dung_cur_door_pos;
const door_animation_step_indicator = vars.door_animation_step_indicator;
const music_control = vars.music_control;
const oam_priority_value = vars.oam_priority_value;
const oam_cur_ptr = vars.oam_cur_ptr;
const oam_ext_cur_ptr = vars.oam_ext_cur_ptr;
const oam_buf = vars.oam_buf;
const bytewise_extended_oam = vars.bytewise_extended_oam;
const dma_var6 = vars.dma_var6;
const dma_var7 = vars.dma_var7;
const BG2HOFS_copy2 = vars.BG2HOFS_copy2;
const BG2VOFS_copy2 = vars.BG2VOFS_copy2;

/// types.h BYTE(x): the low byte of a 16-bit work-ram word.
fn loByte(p: *align(1) u16) *u8 {
    return @ptrCast(p);
}

fn sign8(v: u8) bool {
    return v & 0x80 != 0;
}

fn sign16(v: u16) bool {
    return v & 0x8000 != 0;
}

fn abs16(t: u16) u16 {
    return if (sign16(t)) 0 -% t else t;
}

/// misc.h, a static inline with no linkable symbol: searches backwards.
fn FindInByteArray(data: []const u8, lookfor: u8) i32 {
    var i = data.len;
    while (i > 0) {
        i -= 1;
        if (data[i] == lookfor) return @intCast(i);
    }
    return -1;
}

/// misc.h, likewise.
fn FindInWordArray(data: []const u16, lookfor: u16) i32 {
    var i = data.len;
    while (i > 0) {
        i -= 1;
        if (data[i] == lookfor) return @intCast(i);
    }
    return -1;
}

/// misc.h: the current oam write cursor, as a pointer into work ram.
fn GetOamCurPtr() [*]align(1) OamEnt {
    return @ptrCast(&g_ram[oam_cur_ptr.*]);
}

const kTagalongFlags = [4]u8{ 0x20, 0x10, 0x30, 0x20 };
const kTagalong_Tab5 = [15]u8{ 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
const kTagalong_Tab4 = [15]u8{ 0, 0, 3, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
const kTagalong_Tab0 = [3]u8{ 5, 9, 0xa };
const kTagalong_Tab1 = [3]u16{ 0xdf3, 0x6f9, 0xdf3 };
const kTagalong_Msg = [3]u16{ 0x20, 0x108, 0x11d };

const kTagalong_IndoorInfos = [12]TagalongMessageInfo{
    .{ .y = 0x1ef0, .x = 0x288, .bit = 1, .msg = 0x99, .tagalong = 4 },
    .{ .y = 0x1e58, .x = 0x2f0, .bit = 2, .msg = 0x9a, .tagalong = 4 },
    .{ .y = 0x1ea8, .x = 0x3b8, .bit = 4, .msg = 0x9b, .tagalong = 4 },
    .{ .y = 0xcf8, .x = 0x25b, .bit = 1, .msg = 0x21, .tagalong = 1 },
    .{ .y = 0xcf8, .x = 0x39d, .bit = 2, .msg = 0x21, .tagalong = 1 },
    .{ .y = 0xc78, .x = 0x238, .bit = 4, .msg = 0x21, .tagalong = 1 },
    .{ .y = 0xa30, .x = 0x2f8, .bit = 1, .msg = 0x22, .tagalong = 1 },
    .{ .y = 0x178, .x = 0x550, .bit = 1, .msg = 0x23, .tagalong = 1 },
    .{ .y = 0x168, .x = 0x4f8, .bit = 2, .msg = 0x2a, .tagalong = 1 },
    .{ .y = 0x1bd8, .x = 0x16fc, .bit = 1, .msg = 0x124, .tagalong = 6 },
    .{ .y = 0x1520, .x = 0x167c, .bit = 1, .msg = 0x124, .tagalong = 6 },
    .{ .y = 0x5ac, .x = 0x4fc, .bit = 1, .msg = 0x29, .tagalong = 1 },
};

const kTagalong_OutdoorInfos = [5]TagalongMessageInfo{
    .{ .y = 0x3c0, .x = 0x730, .bit = 1, .msg = 0x9d, .tagalong = 4 },
    .{ .y = 0x648, .x = 0xf50, .bit = 0, .msg = 0xffff, .tagalong = 0xa },
    .{ .y = 0x6c8, .x = 0xd78, .bit = 1, .msg = 0xffff, .tagalong = 0xa },
    .{ .y = 0x688, .x = 0xc78, .bit = 2, .msg = 0xffff, .tagalong = 0xa },
    .{ .y = 0xe8, .x = 0x90, .bit = 0, .msg = 0x28, .tagalong = 0xe },
};

const kTagalong_IndoorOffsets = [8]u8{ 0, 3, 6, 7, 9, 10, 11, 12 };
const kTagalong_OutdoorOffsets = [4]u8{ 0, 1, 4, 5 };
const kTagalong_IndoorRooms = [7]u16{ 0xf1, 0x61, 0x51, 2, 0xdb, 0xab, 0x22 };
const kTagalong_OutdoorRooms = [3]u16{ 3, 0x5e, 0 };

const TagalongSprXY = extern struct {
    y1: i8,
    x1: i8,
    y2: i8,
    x2: i8,
};

const TagalongDmaFlags = extern struct {
    dma6: u8,
    dma7: u8,
    flags: u8,
};

const kTagalongDraw_SprXY = [56]TagalongSprXY{
    .{ .y1 = -2, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = -2, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = -2, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = -2, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = -1, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = -1, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = -1, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = -1, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = -3, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 3, .y2 = 0, .x2 = 0 },
    .{ .y1 = 1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 1, .x1 = -3, .y2 = 1, .x2 = 0 },
    .{ .y1 = 1, .x1 = 3, .y2 = 1, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = -1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = -1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = -1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = -1, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 0, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 2, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 2, .x1 = 0, .y2 = 0, .x2 = 0 },
    .{ .y1 = 2, .x1 = -1, .y2 = 0, .x2 = 0 },
    .{ .y1 = 2, .x1 = 1, .y2 = 0, .x2 = 0 },
    .{ .y1 = 3, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 3, .x1 = 0, .y2 = 1, .x2 = 0 },
    .{ .y1 = 3, .x1 = -1, .y2 = 1, .x2 = 0 },
    .{ .y1 = 3, .x1 = 1, .y2 = 1, .x2 = 0 },
};

const kTagalongDmaAndFlags = [16]TagalongDmaFlags{
    .{ .dma6 = 0x20, .dma7 = 0xc0, .flags = 0x00 },
    .{ .dma6 = 0x00, .dma7 = 0xa0, .flags = 0x00 },
    .{ .dma6 = 0x40, .dma7 = 0x60, .flags = 0x00 },
    .{ .dma6 = 0x40, .dma7 = 0x60, .flags = 0x44 },
    .{ .dma6 = 0x20, .dma7 = 0xc0, .flags = 0x04 },
    .{ .dma6 = 0x00, .dma7 = 0xa0, .flags = 0x04 },
    .{ .dma6 = 0x40, .dma7 = 0x80, .flags = 0x00 },
    .{ .dma6 = 0x40, .dma7 = 0x80, .flags = 0x44 },
    .{ .dma6 = 0x20, .dma7 = 0xe0, .flags = 0x00 },
    .{ .dma6 = 0x00, .dma7 = 0xe0, .flags = 0x00 },
    .{ .dma6 = 0x40, .dma7 = 0xe0, .flags = 0x00 },
    .{ .dma6 = 0x40, .dma7 = 0xe0, .flags = 0x44 },
    .{ .dma6 = 0x20, .dma7 = 0xe0, .flags = 0x04 },
    .{ .dma6 = 0x00, .dma7 = 0xe0, .flags = 0x04 },
    .{ .dma6 = 0x40, .dma7 = 0xe0, .flags = 0x04 },
    .{ .dma6 = 0x40, .dma7 = 0xe0, .flags = 0x40 },
};

const kTagalongDraw_Pals = [14]u8{ 0, 4, 4, 4, 4, 0, 7, 4, 4, 3, 4, 4, 4, 4 };
const kTagalongDraw_Offs = [14]u16{ 0, 0, 0x80, 0x80, 0x80, 0, 0, 0xc0, 0xc0, 0x100, 0x180, 0x180, 0x140, 0x140 };
const kTagalongDraw_SprInfo0 = [24]u8{
    0xd8, 0x24, 0xd8, 0x64, 0xd9, 0x24, 0xd9, 0x64, 0xda, 0x24, 0xda, 0x64, 0xc8, 0x22, 0xc8, 0x62,
    0xc9, 0x22, 0xc9, 0x62, 0xca, 0x22, 0xca, 0x62,
};
const kTagalongDraw_SprOffs0 = [2]u16{ 0x170, 0xc0 };
const kTagalongDraw_SprOffs1 = [2]u16{ 0x1c0, 0x110 };

pub export fn Tagalong_IsFollowing() callconv(.c) bool {
    const main = main_module_index.*;
    const sub = submodule_index.*;
    return flag_is_link_immobilized.* == 0 and sub != 10 and
        !(main == 9 and sub == 0x23) and !(main == 14 and (sub == 1 or sub == 2));
}

pub export fn Follower_ValidateMessageFreedom() callconv(.c) bool { // 87f46f
    const ps = link_player_handler_state.*;
    if (ps != kPlayerState_Ground and ps != kPlayerState_Swimming and ps != kPlayerState_StartDash)
        return false;
    const t = (button_mask_b_y.* & 0x80) | link_unk_master_sword.* | link_item_in_hand.* |
        link_position_mode.* | flag_is_ancilla_to_pick_up.* | flag_is_sprite_to_pick_up.* |
        link_state_bits.* | link_grabbing_wall.*;
    return t == 0;
}

pub export fn Follower_MoveTowardsLink() callconv(.c) void { // 88f91a
    while (true) {
        const k = 9;
        const j: usize = tagalong_var1.*;
        ancilla_y_lo[k] = tagalong_y_lo[j];
        ancilla_y_hi[k] = tagalong_y_hi[j];
        ancilla_x_lo[k] = tagalong_x_lo[j];
        ancilla_x_hi[k] = tagalong_x_hi[j];

        const pt = Ancilla_ProjectSpeedTowardsPlayer(k, 24);
        ancilla_x_vel[k] = pt.x;
        ancilla_y_vel[k] = pt.y;
        Ancilla_MoveY(k);
        Ancilla_MoveX(k);

        const x = Ancilla_GetX(k);
        const y = Ancilla_GetY(k);
        if (abs16(x -% link_x_coord.*) < 2 and abs16(y -% link_y_coord.*) < 2)
            return;
        tagalong_var1.* +%= 1;
        const nk: usize = tagalong_var1.*;
        if (nk == 18)
            return;
        tagalong_y_lo[nk] = @truncate(y);
        tagalong_y_hi[nk] = @truncate(y >> 8);
        tagalong_x_lo[nk] = @truncate(x);
        tagalong_x_hi[nk] = @truncate(x >> 8);
        const kTagalongLayerBits = [4]u8{ 0x20, 0x10, 0x30, 0x20 };
        tagalong_layerbits[nk] = (kTagalongLayerBits[link_is_on_lower_level.*] >> 2) | 1;
    }
}

pub export fn Follower_CheckBlindTrigger() callconv(.c) bool { // 899e90
    const k: usize = tagalong_var2.*;
    var x = (@as(u16, tagalong_x_hi[k]) << 8) | tagalong_x_lo[k];
    var y = (@as(u16, tagalong_y_hi[k]) << 8) | tagalong_y_lo[k];
    const z: u16 = @bitCast(@as(i16, @as(i8, @bitCast(tagalong_z[k]))));
    y +%= z +% 12;
    x +%= 8;
    return abs16(0x1568 -% y) < 24 and abs16(0x1980 -% x) < 24;
}

pub export fn Follower_Initialize() callconv(.c) void { // 899efc
    tagalong_y_lo[0] = @truncate(link_y_coord.*);
    tagalong_y_hi[0] = @truncate(link_y_coord.* >> 8);

    tagalong_x_lo[0] = @truncate(link_x_coord.*);
    tagalong_x_hi[0] = @truncate(link_x_coord.* >> 8);

    tagalong_layerbits[0] = (kTagalongFlags[link_is_on_lower_level.*] >> 2) | (link_direction_facing.* >> 1);
    timer_tagalong_reacquire.* = 64;
    tagalong_var2.* = 0;
    tagalong_var1.* = 0;
    tagalong_var3.* = 0;
    tagalong_var4.* = 0;
    link_speed_setting.* = 0;

    if (enhanced_features0.* & kFeatures0_TurnWhileDashing != 0) {
        link_player_handler_state.* = kPlayerState_Ground;
        link_is_running.* = 0;
    }
}

pub export fn Sprite_BecomeFollower(k: c_int) callconv(.c) void { // 899f39
    tagalong_var5.* = 0;
    const y = Sprite_GetY(k) -% 6;
    tagalong_y_lo[0] = @truncate(y);
    tagalong_y_hi[0] = @truncate(y >> 8);
    const x = Sprite_GetX(k) +% 1;
    tagalong_x_lo[0] = @truncate(x);
    tagalong_x_hi[0] = @truncate(x >> 8);
    tagalong_layerbits[0] = (kTagalongFlags[link_is_on_lower_level.*] >> 2) | 1;
    timer_tagalong_reacquire.* = 64;
    tagalong_var1.* = 0;
    tagalong_var2.* = 0;
    tagalong_var3.* = 0;
    tagalong_var4.* = 0;
    link_speed_setting.* = 0;
    tagalong_var5.* = 0;
    follower_dropped.* = 0;
    Follower_MoveTowardsLink();
}

pub export fn Follower_Main() callconv(.c) void { // 899fc4
    if (follower_indicator.* == 0)
        return;
    if (follower_indicator.* == 0xe) {
        Follower_HandleTrigger();
        return;
    }
    const j = FindInByteArray(&kTagalong_Tab0, follower_indicator.*);
    word_7E02CD.* -%= 1;
    if (j >= 0 and submodule_index.* == 0 and
        !(j == 2 and overworld_screen_index.* & 0x40 != 0) and sign16(word_7E02CD.*))
    {
        if (!Follower_ValidateMessageFreedom()) {
            word_7E02CD.* = 0;
        } else {
            word_7E02CD.* = kTagalong_Tab1[@intCast(j)];
            dialogue_message_index.* = kTagalong_Msg[@intCast(j)];
            Main_ShowTextMessage();
        }
    }
    if (j != 0)
        Follower_NoTimedMessage();
}

pub export fn Follower_NoTimedMessage() callconv(.c) void { // 89a02b
    check_game_mode: {
        if (follower_dropped.* != 0) {
            Follower_NotFollowing();
            return;
        }

        var drop_now = false;
        if (follower_indicator.* == 12) {
            if (link_auxiliary_state.* != 0) break :check_game_mode;
        } else if (follower_indicator.* == 13) {
            if (link_auxiliary_state.* == 2 or player_near_pit_state.* == 2) drop_now = true;
        } else {
            break :check_game_mode;
        }

        if (!drop_now) {
            if (submodule_index.* != 0 or link_auxiliary_state.* == 1 or
                (link_state_bits.* & 0x80) != 0 or tagalong_var5.* != 0 or tagalong_var3.* != 0 or
                @as(i8, @bitCast(tagalong_z[tagalong_var2.*])) > 0 or
                !(filtered_joypad_L.* & 0x80 != 0))
                break :check_game_mode;
        }

        if (follower_indicator.* == 13 and player_is_indoors.* == 0) {
            const ps = link_player_handler_state.*;
            if (ps == kPlayerState_Ether or ps == kPlayerState_Bombos or ps == kPlayerState_Quake)
                break :check_game_mode;
            super_bomb_indicator_unk2.* = 3;
            super_bomb_indicator_unk1.* = 0xbb;
        }

        follower_dropped.* = 128;
        timer_tagalong_reacquire.* = 64;

        const k: usize = tagalong_var2.*;
        saved_tagalong_y.* = @as(u16, tagalong_y_lo[k]) | (@as(u16, tagalong_y_hi[k]) << 8);
        saved_tagalong_x.* = @as(u16, tagalong_x_lo[k]) | (@as(u16, tagalong_x_hi[k]) << 8);
        saved_tagalong_floor.* = link_is_on_lower_level.*;
        saved_tagalong_indoors.* = player_is_indoors.*;
        Follower_NotFollowing();
        return;
    }
    Follower_CheckGameMode();
}

pub export fn Follower_CheckGameMode() callconv(.c) void { // 89a0e1
    if (Tagalong_IsFollowing() and (link_x_vel.* | link_y_vel.*) != 0) {
        var k: usize = @as(usize, tagalong_var1.*) + 1;
        if (k == 20)
            k = 0;
        tagalong_var1.* = @intCast(k);
        var z: u8 = @truncate(link_z_coord.*);
        if (z >= 0xf0)
            z = 0;
        tagalong_z[k] = z;
        const y = link_y_coord.* -% z;
        tagalong_y_lo[k] = @truncate(y);
        tagalong_y_hi[k] = @truncate(y >> 8);
        const x = link_x_coord.*;
        tagalong_x_lo[k] = @truncate(x);
        tagalong_x_hi[k] = @truncate(x >> 8);
        var layerbits = (link_direction_facing.* >> 1) | (kTagalongFlags[link_is_on_lower_level.*] >> 2);
        if (link_player_handler_state.* == kPlayerState_Swimming) {
            layerbits |= 0x20;
        } else {
            if (link_player_handler_state.* == kPlayerState_Hookshot and related_to_hookshot.* != 0)
                layerbits |= 0x10;
            if (draw_water_ripples_or_grass.* != 0)
                layerbits |= if (draw_water_ripples_or_grass.* == 1) @as(u8, 0x80) else 0x40;
        }
        tagalong_layerbits[k] = layerbits;
    }

    switch (follower_indicator.*) {
        2, 4 => Follower_OldMan(),
        3, 11 => Follower_OldManUnused(),
        5, 14 => unreachable, // Y is unknown here...
        else => Follower_BasicMover(),
    }
}

pub export fn Follower_BasicMover() callconv(.c) void { // 89a197
    if (!Tagalong_IsFollowing()) {
        Tagalong_Draw();
        return;
    }

    Follower_HandleTrigger();

    if (follower_indicator.* == 10 and link_auxiliary_state.* != 0 and countdown_for_blink.* != 0) {
        const k: c_int = if (@as(u32, tagalong_var2.*) + 1 == 20) 0 else @as(c_int, tagalong_var2.*) + 1;
        Kiki_SpawnHandler_B(k);
        follower_indicator.* = 0;
        return;
    }

    if (follower_indicator.* == 6 and dungeon_room_index.* == 0xac and
        (save_dung_info[101] & 0x100) != 0 and Follower_CheckBlindTrigger())
    {
        const k: usize = tagalong_var2.*;
        const x = @as(u16, tagalong_x_lo[k]) | (@as(u16, tagalong_x_hi[k]) << 8);
        const y = @as(u16, tagalong_y_lo[k]) | (@as(u16, tagalong_y_hi[k]) << 8);
        follower_indicator.* = 0;
        Blind_SpawnFromMaiden(x, y);
        loByte(dung_flag_trapdoors_down).* +%= 1;
        loByte(dung_cur_door_pos).* = 0;
        loByte(door_animation_step_indicator).* = 0;
        submodule_index.* = 5;
        music_control.* = 21;
        return;
    }

    // The C reaches the two tails of this routine by goto; these flags stand in
    // for those jumps.
    var to_e = false;
    var to_d = false;

    if (tagalong_var3.* == 0) {
        if (link_player_handler_state.* == kPlayerState_Hookshot and related_to_hookshot.* != 0) {
            tagalong_var3.* = 1;
            to_e = true;
        }
    } else {
        if (link_player_handler_state.* == kPlayerState_Hookshot) {
            to_e = true;
        } else if (tagalong_var7.* != tagalong_var2.*) {
            to_d = true;
        } else {
            tagalong_var3.* = 0;
        }
    }

    if (!to_e and !to_d) {
        const k: usize = tagalong_var2.*;
        if (@as(i8, @bitCast(tagalong_z[k])) > 0) {
            if (tagalong_var1.* != tagalong_var2.*) {
                to_d = true;
            } else {
                tagalong_z[k] = 0;
                const y = link_y_coord.*;
                const x = link_x_coord.*;
                tagalong_y_lo[k] = @truncate(y);
                tagalong_y_hi[k] = @truncate(y >> 8);
                tagalong_x_lo[k] = @truncate(x);
                tagalong_x_hi[k] = @truncate(x >> 8);
            }
        }
    }

    if (!to_d and (to_e or (link_x_vel.* | link_y_vel.*) != 0)) {
        var t = tagalong_var1.* -% 15;
        if (sign8(t))
            t +%= 20;
        if (t == tagalong_var2.*)
            to_d = true;
    }

    if (to_d)
        tagalong_var2.* = if (@as(u32, tagalong_var2.*) + 1 == 20) 0 else tagalong_var2.* + 1;

    Tagalong_Draw();
}

pub export fn Follower_NotFollowing() callconv(.c) void { // 89a2b2
    if (saved_tagalong_indoors.* != player_is_indoors.*)
        return;
    if (link_is_running.* == 0 and !Follower_CheckProximityToLink()) {
        Follower_Initialize();
        saved_tagalong_indoors.* = player_is_indoors.*;
        if (follower_indicator.* == 13) {
            super_bomb_indicator_unk2.* = 254;
            super_bomb_indicator_unk1.* = 0;
        }
        follower_dropped.* = 0;
        Tagalong_Draw();
    } else {
        if (follower_indicator.* == 13 and player_is_indoors.* == 0 and super_bomb_indicator_unk2.* == 0) {
            // Fixed so we wait a little bit if we can't spawn the ancilla
            if (AncillaAdd_SuperBombExplosion(0x3a, 0) >= 0) {
                follower_dropped.* = 0;

                // A ticking super bomb will cancel and teleport back to you as a
                // follower if you do any of these at count 0: (1) change screen via
                // walking, mirror, or bird travel (2) fill all ancillary slots
                // (3) die with a bottled faerie.
                // Fixed this by clearing the follower indicator here, instead of in
                // the ancilla bomb code.
                if (enhanced_features0.* & kFeatures0_MiscBugFixes != 0) {
                    follower_indicator.* = 0;
                    return;
                }
            } else {
                super_bomb_indicator_unk1.* = 1;
            }
        }
        Follower_DoLayers();
    }
}

pub export fn Follower_OldMan() callconv(.c) void { // 89a318
    if (!Tagalong_IsFollowing()) {
        Tagalong_Draw();
        return;
    }

    if (link_speed_setting.* != 4)
        link_speed_setting.* = 12;

    Follower_HandleTrigger();

    var transform = false;
    if (follower_indicator.* == 0) {
        return;
    } else if (follower_indicator.* == 4) {
        if (@as(i8, @bitCast(tagalong_z[tagalong_var2.*])) > 0 and tagalong_var1.* != tagalong_var2.*) {
            tagalong_var2.* = if (@as(u32, tagalong_var2.*) + 1 >= 20) 0 else tagalong_var2.* + 1;
            Tagalong_Draw();
            return;
        }
    } else {
        // tagalong type 2
        if ((link_auxiliary_state.* & 1) != 0 and link_player_handler_state.* == kPlayerState_RecoilOther) {
            if (tagalong_var1.* != tagalong_var2.*) {
                transform = true;
            } else {
                unreachable; // X is undefined here
            }
        }
        if (!transform and (link_auxiliary_state.* & 2) != 0)
            transform = true;
    }

    if (transform) {
        follower_indicator.* = kTagalong_Tab4[follower_indicator.*];
        timer_tagalong_reacquire.* = 64;
        const k: usize = tagalong_var2.*;
        saved_tagalong_y.* = @as(u16, tagalong_y_lo[k]) | (@as(u16, tagalong_y_hi[k]) << 8);
        saved_tagalong_x.* = @as(u16, tagalong_x_lo[k]) | (@as(u16, tagalong_x_hi[k]) << 8);
        saved_tagalong_floor.* = link_is_on_lower_level.*;
        Follower_OldManUnused();
        return;
    }

    if ((link_x_vel.* | link_y_vel.*) != 0) {
        var t = tagalong_var1.* -% 20;
        if (sign8(t))
            t +%= 20;
        if (t == tagalong_var2.*)
            tagalong_var2.* = if (@as(u32, tagalong_var2.*) + 1 >= 20) 0 else tagalong_var2.* + 1;
    } else if ((frame_counter.* & 3) == 0 and tagalong_var1.* != tagalong_var2.*) {
        var t = tagalong_var1.* -% 9;
        if (sign8(t))
            t +%= 20;
        if (t != tagalong_var2.*)
            tagalong_var2.* = if (@as(u32, tagalong_var2.*) + 1 >= 20) 0 else tagalong_var2.* + 1;
    }
    Tagalong_Draw();
}

pub export fn Follower_OldManUnused() callconv(.c) void { // 89a41f
    link_speed_setting.* = 16;
    if (link_is_running.* == 0 and link_auxiliary_state.* == 0 and
        link_player_handler_state.* != kPlayerState_Swimming)
    {
        link_speed_setting.* = 0;
        if (link_player_handler_state.* != kPlayerState_Hookshot and !Follower_CheckProximityToLink()) {
            Follower_Initialize();
            follower_indicator.* = kTagalong_Tab5[follower_indicator.*];
            return;
        }
    }
    Follower_DoLayers();
}

pub export fn Follower_DoLayers() callconv(.c) void { // 89a450
    oam_priority_value.* = @as(u16, kTagalongFlags[saved_tagalong_floor.*]) << 8;
    const a: u8 = if (follower_indicator.* == 12 or follower_indicator.* == 13) 2 else 1;
    Follower_AnimateMovement_preserved(a, saved_tagalong_x.*, saved_tagalong_y.*);
}

pub export fn Follower_CheckProximityToLink() callconv(.c) bool { // 89a48e
    timer_tagalong_reacquire.* -%= 1;
    if (!sign8(timer_tagalong_reacquire.*))
        return true;
    timer_tagalong_reacquire.* = 0;
    if ((saved_tagalong_y.* -% 1) >= link_y_coord.* or
        (saved_tagalong_y.* +% 19) < link_y_coord.* or
        (saved_tagalong_x.* -% 1) >= link_x_coord.* or
        (saved_tagalong_x.* +% 19) < link_x_coord.*)
        return true;
    return false;
}

pub export fn Follower_HandleTrigger() callconv(.c) void { // 89a59e
    if (submodule_index.* != 0)
        return;

    var tmi: []const TagalongMessageInfo = undefined;
    if (player_is_indoors.* != 0) {
        const j = FindInWordArray(&kTagalong_IndoorRooms, dungeon_room_index.*);
        if (j < 0)
            return;
        const lo = kTagalong_IndoorOffsets[@intCast(j)];
        const hi = kTagalong_IndoorOffsets[@intCast(j + 1)];
        tmi = kTagalong_IndoorInfos[lo..hi];
    } else {
        const j = FindInWordArray(&kTagalong_OutdoorRooms, overworld_screen_index.*);
        if (j < 0)
            return;
        const lo = kTagalong_OutdoorOffsets[@intCast(j)];
        const hi = kTagalong_OutdoorOffsets[@intCast(j + 1)];
        tmi = kTagalong_OutdoorInfos[lo..hi];
    }
    const st: c_int = if (@as(u32, tagalong_var2.*) + 1 >= 20) 0 else @as(c_int, tagalong_var2.*) + 1;
    for (tmi) |*info| {
        if (info.tagalong == follower_indicator.* and Follower_CheckForTrigger(info)) {
            if (info.bit & tagalong_event_flags.* != 0)
                return;
            tagalong_event_flags.* |= @truncate(info.bit);
            dialogue_message_index.* = info.msg;
            if (info.msg == 0xffff) {
                if (!(info.bit & 3 != 0))
                    Kiki_RevertToSprite(st)
                else if (!(save_ow_event_info[loByte(overworld_screen_index).*] & 1 != 0))
                    Kiki_SpawnHandler_A(st);
                return;
            }
            if (info.msg == 0x9d) {
                OldMan_RevertToSprite(st);
            } else if (info.msg == 0x28) {
                follower_indicator.* = 0;
            }
            Main_ShowTextMessage();
            return;
        }
    }
}

pub export fn Tagalong_Draw() callconv(.c) void { // 89a907
    if (tagalong_var5.* != 0)
        return;
    const prio: u16 = if (tagalong_z[tagalong_var2.*] != 0 and player_is_indoors.* == 0)
        0x20
    else if (submodule_index.* == 14)
        kTagalongFlags[link_is_on_lower_level.*]
    else
        (@as(u16, tagalong_layerbits[tagalong_var2.*] & 0xc) << 2);
    oam_priority_value.* = prio << 8;
    var k: usize = tagalong_var2.*;
    if (sign8(tagalong_var2.*))
        k = 0;
    const x = @as(u16, tagalong_x_lo[k]) | (@as(u16, tagalong_x_hi[k]) << 8);
    const y = @as(u16, tagalong_y_lo[k]) | (@as(u16, tagalong_y_hi[k]) << 8);
    const a = tagalong_layerbits[k];
    Follower_AnimateMovement_preserved(a, x, y);
}

fn SetOam_Follower(oam: [*]align(1) OamEnt, x: u16, y: u16, charnum: u8, flags: u8, big_in: u8) void {
    var big = big_in;
    oam[0].x = @truncate(x);
    // The C folds the `big` update into the condition with a comma operator, so
    // it only happens when the x test passes.
    oam[0].y = blk: {
        if ((x +% 0x80) < 0x180) {
            big |= @truncate((x >> 8) & 1);
            if ((y +% 0x10) < 0x100) break :blk @as(u8, @truncate(y));
        }
        break :blk 0xf0;
    };
    oam[0].charnum = charnum;
    oam[0].flags = flags;
    const index = (@intFromPtr(oam) - @intFromPtr(oam_buf)) / @sizeOf(OamEnt);
    bytewise_extended_oam[index] = big;
}

pub export fn Follower_AnimateMovement_preserved(ain: u8, xin: u16, yin: u16) callconv(.c) void { // 89a959
    var yt: u8 = 0;
    var av: u8 = 0;
    var sc: u8 = 0;

    if ((ain >> 2 & 8) != 0 and (follower_indicator.* == 6 or follower_indicator.* == 1)) {
        yt = 8;
        if ((swimcoll_var7[0] | swimcoll_var7[1]) != 0)
            av = (frame_counter.* >> 1) & 4
        else
            av = (frame_counter.* >> 2) & 4;
    } else if (submodule_index.* == 8 or submodule_index.* == 14 or submodule_index.* == 16) {
        av = if (link_is_running.* != 0) (frame_counter.* & 4) else ((frame_counter.* >> 1) & 4);
    } else if (follower_indicator.* == 11) {
        av = (frame_counter.* >> 1) & 4;
    } else if (((follower_indicator.* == 12 or follower_indicator.* == 13) and follower_dropped.* != 0) or
        flag_is_link_immobilized.* != 0 or
        submodule_index.* == 10 or (main_module_index.* == 9 and submodule_index.* == 0x23) or
        (main_module_index.* == 14 and (submodule_index.* == 1 or submodule_index.* == 2)) or
        (link_y_vel.* | link_x_vel.*) == 0)
    {
        av = 4;
        sc = 4;
    } else {
        av = if (link_is_running.* != 0) (frame_counter.* & 4) else ((frame_counter.* >> 1) & 4);
    }
    const frame: usize = (ain & 3) + av + yt;

    const spr_offs: u16 = if ((link_y_coord.* == yin and (ain & 3) == 0) or link_y_coord.* < yin)
        kTagalongDraw_SprOffs0[sort_sprites_setting.*] >> 2
    else
        kTagalongDraw_SprOffs1[sort_sprites_setting.*] >> 2;
    oam_ext_cur_ptr.* = 0xa20 +% spr_offs;
    oam_cur_ptr.* = 0x800 +% spr_offs *% 4;

    var oam = GetOamCurPtr();
    const scrolly = yin -% BG2VOFS_copy2.*;
    const scrollx = xin -% BG2HOFS_copy2.*;

    var sk: [*]const u8 = &kTagalongDraw_SprInfo0;
    var skip_first_sprites = false;
    if (follower_indicator.* == 1 or follower_indicator.* == 6 or (ain & 0x20) == 0) {
        if ((ain & 0xc0) == 0) {
            skip_first_sprites = true;
        } else {
            // `(ain & 0x80) || (sk += 12, sc == 0)` -- the advance only happens
            // when the first test fails.
            var do_incr = false;
            if (ain & 0x80 != 0) {
                do_incr = true;
            } else {
                sk += 12;
                if (sc == 0) do_incr = true;
            }
            if (do_incr) {
                advanceWalkFrame();
            } else {
                byte_7E02D7.* = 0;
            }
        }
    } else {
        advanceWalkFrame();
    }

    if (!skip_first_sprites) {
        sk += @as(usize, byte_7E02D7.*) * 4;
        SetOam_Follower(oam + 0, scrollx, scrolly +% 16, sk[0], sk[1], 0);
        SetOam_Follower(oam + 1, scrollx +% 8, scrolly +% 16, sk[2], sk[3], 0);
        oam += 2;
    }

    var pal = kTagalongDraw_Pals[follower_indicator.*];
    if (pal == 7 and palette_swap_flag.* != 0)
        pal = 0;

    if (follower_indicator.* == 13) {
        // Display colorful superbomb palette also on frame 0.
        const on = if (enhanced_features0.* & kFeatures0_MiscBugFixes != 0)
            (super_bomb_indicator_unk2.* <= 1)
        else
            (super_bomb_indicator_unk2.* == 1);
        if (on)
            pal = frame_counter.* & 7;
    }

    const sprd = &kTagalongDraw_SprXY[frame + (kTagalongDraw_Offs[follower_indicator.*] >> 3)];
    const sprf = &kTagalongDmaAndFlags[frame];

    if (follower_indicator.* != 12 and follower_indicator.* != 13) {
        SetOam_Follower(
            oam,
            scrollx +% signExtend(sprd.x1),
            scrolly +% signExtend(sprd.y1),
            0x20,
            (sprf.flags & 0xf0) | (pal << 1) | @as(u8, @truncate(oam_priority_value.* >> 8)),
            2,
        );
        oam += 1;
        loByte(dma_var6).* = sprf.dma6;
    }
    {
        SetOam_Follower(
            oam,
            scrollx +% signExtend(sprd.x2),
            scrolly +% signExtend(sprd.y2) +% 8,
            0x22,
            ((sprf.flags & 0xf) << 4) | (pal << 1) | @as(u8, @truncate(oam_priority_value.* >> 8)),
            2,
        );
        loByte(dma_var7).* = sprf.dma7;
    }
}

fn advanceWalkFrame() void {
    if ((frame_counter.* & 7) == 0) {
        byte_7E02D7.* +%= 1;
        if (byte_7E02D7.* == 3)
            byte_7E02D7.* = 0;
    }
}

fn signExtend(v: i8) u16 {
    return @bitCast(@as(i16, v));
}

pub export fn Follower_CheckForTrigger(info: *const TagalongMessageInfo) callconv(.c) bool { // 89ac26
    var x = link_x_coord.* +% 12 -% (info.x +% 8);
    var y = link_y_coord.* +% 12 -% (info.y +% 8);
    if (sign16(x))
        x = 0 -% x;
    if (sign16(y))
        y = 0 -% y;
    return x < 24 and y < 28;
}

pub export fn Follower_Disable() callconv(.c) void { // 89acf3
    if (follower_indicator.* == 9 or follower_indicator.* == 10)
        follower_indicator.* = 0;
}

pub export fn Blind_SpawnFromMaiden(x: u16, y: u16) callconv(.c) void { // 9da03c
    const k = 0;
    sprite_state[k] = 9;
    sprite_type[k] = 206;
    Sprite_SetX(k, x);
    Sprite_SetY(k, y -% 16);
    SpritePrep_LoadProperties(k);
    sprite_delay_aux2[k] = 192;
    sprite_graphics[k] = 21;
    sprite_D[k] = 2;
    sprite_ignore_projectile[k] = 2;
    dung_savegame_state_bits.* |= 0x2000;
    byte_7E0B69.* = 0;
}

pub export fn Kiki_RevertToSprite(k: c_int) callconv(.c) void { // 9ee66b
    const j = Kiki_SpawnHandlerMonke(k);
    sprite_subtype2[@intCast(j)] = 1;
    follower_indicator.* = 0;
}

pub export fn Kiki_SpawnHandlerMonke(k: c_int) callconv(.c) c_int { // 9ee67a
    var info: SpriteSpawnInfo = undefined;
    const j = Sprite_SpawnDynamically(k, 0xb6, &info);
    if (j >= 0) {
        const s: usize = @intCast(j);
        const i: usize = @intCast(k);
        sprite_head_dir[s] = tagalong_layerbits[i] & 3;
        sprite_D[s] = tagalong_layerbits[i] & 3;
        const x = (@as(u16, tagalong_x_hi[i]) << 8) | tagalong_x_lo[i];
        const y = (@as(u16, tagalong_y_hi[i]) << 8) | tagalong_y_lo[i];
        Sprite_SetX(j, x +% 2);
        Sprite_SetY(j, y +% 2);
        sprite_floor[s] = link_is_on_lower_level.*;
        sprite_ignore_projectile[s] = 1;
        sprite_floor[s] = 2;
        link_speed_setting.* = 0;
    }
    return j;
}

pub export fn Kiki_SpawnHandler_A(k: c_int) callconv(.c) void { // 9ee6c7
    const j = Kiki_SpawnHandlerMonke(k);
    sprite_subtype2[@intCast(j)] = 2;
}

pub export fn Kiki_SpawnHandler_B(k: c_int) callconv(.c) void { // 9ee6d0
    const j = Kiki_SpawnHandlerMonke(k);
    const s: usize = @intCast(j);
    sprite_z[s] = 1;
    sprite_z_vel[s] = 16;
    sprite_subtype2[s] = 3;
    follower_indicator.* = 0;
}

const testing = std.testing;

fn resetRam() void {
    @memset(g_ram[0..0x2000], 0);
    @memset(g_ram[0xF000..0xF400], 0);
    @memset(g_ram[0x1A00..0x1A80], 0);
}

test "Tagalong_IsFollowing blocks in the modes that freeze the follower" {
    resetRam();
    try testing.expect(Tagalong_IsFollowing());

    flag_is_link_immobilized.* = 1;
    try testing.expect(!Tagalong_IsFollowing());
    flag_is_link_immobilized.* = 0;

    submodule_index.* = 10;
    try testing.expect(!Tagalong_IsFollowing());
    submodule_index.* = 0;

    main_module_index.* = 9;
    submodule_index.* = 0x23;
    try testing.expect(!Tagalong_IsFollowing());

    main_module_index.* = 14;
    submodule_index.* = 1;
    try testing.expect(!Tagalong_IsFollowing());
    submodule_index.* = 3; // not 1 or 2
    try testing.expect(Tagalong_IsFollowing());
}

test "a message needs Link idle and empty handed" {
    resetRam();
    link_player_handler_state.* = kPlayerState_Ground;
    try testing.expect(Follower_ValidateMessageFreedom());

    link_player_handler_state.* = kPlayerState_Hookshot;
    try testing.expect(!Follower_ValidateMessageFreedom());

    // Swimming and dashing are allowed too.
    link_player_handler_state.* = kPlayerState_Swimming;
    try testing.expect(Follower_ValidateMessageFreedom());
    link_player_handler_state.* = kPlayerState_StartDash;
    try testing.expect(Follower_ValidateMessageFreedom());

    // Any of the busy flags blocks it.
    link_item_in_hand.* = 1;
    try testing.expect(!Follower_ValidateMessageFreedom());
    link_item_in_hand.* = 0;
    link_grabbing_wall.* = 1;
    try testing.expect(!Follower_ValidateMessageFreedom());
}

test "Follower_Initialize seeds the trail from Link's position" {
    resetRam();
    link_x_coord.* = 0x1234;
    link_y_coord.* = 0x5678;
    link_direction_facing.* = 4;
    link_is_on_lower_level.* = 0;
    Follower_Initialize();

    try testing.expectEqual(@as(u8, 0x78), tagalong_y_lo[0]);
    try testing.expectEqual(@as(u8, 0x56), tagalong_y_hi[0]);
    try testing.expectEqual(@as(u8, 0x34), tagalong_x_lo[0]);
    try testing.expectEqual(@as(u8, 0x12), tagalong_x_hi[0]);
    // kTagalongFlags[0] >> 2 is 8, plus the facing direction shifted down.
    try testing.expectEqual(@as(u8, 8 | 2), tagalong_layerbits[0]);
    try testing.expectEqual(@as(u8, 64), timer_tagalong_reacquire.*);
    try testing.expectEqual(@as(u8, 0), tagalong_var1.*);
}

test "the turn-while-dashing feature also clears the dash on re-init" {
    resetRam();
    link_player_handler_state.* = kPlayerState_StartDash;
    link_is_running.* = 1;
    enhanced_features0.* = 0;
    Follower_Initialize();
    try testing.expectEqual(@as(u8, 1), link_is_running.*); // untouched

    enhanced_features0.* = kFeatures0_TurnWhileDashing;
    Follower_Initialize();
    try testing.expectEqual(@as(u8, 0), link_is_running.*);
    try testing.expectEqual(@as(u8, kPlayerState_Ground), link_player_handler_state.*);
    enhanced_features0.* = 0;
}

test "the blind trigger is a box around one fixed spot" {
    resetRam();
    tagalong_var2.* = 0;
    // The check adds z + 12 to y and 8 to x, then compares against $1568/$1980.
    tagalong_y_lo[0] = @truncate(0x1568 - 12);
    tagalong_y_hi[0] = @truncate((0x1568 - 12) >> 8);
    tagalong_x_lo[0] = @truncate(0x1980 - 8);
    tagalong_x_hi[0] = @truncate((0x1980 - 8) >> 8);
    tagalong_z[0] = 0;
    try testing.expect(Follower_CheckBlindTrigger());

    // Far away in x.
    tagalong_x_lo[0] = 0;
    tagalong_x_hi[0] = 0;
    try testing.expect(!Follower_CheckBlindTrigger());
}

test "a message trigger fires inside a 24x28 box around Link" {
    resetRam();
    const info = TagalongMessageInfo{ .y = 0x100, .x = 0x200, .bit = 1, .msg = 0x20, .tagalong = 1 };
    // Centre the probe: link + 12 == info + 8.
    link_x_coord.* = 0x200 + 8 - 12;
    link_y_coord.* = 0x100 + 8 - 12;
    try testing.expect(Follower_CheckForTrigger(&info));

    link_x_coord.* += 23;
    try testing.expect(Follower_CheckForTrigger(&info));
    link_x_coord.* += 1; // 24 is outside
    try testing.expect(!Follower_CheckForTrigger(&info));

    link_x_coord.* = 0x200 + 8 - 12;
    link_y_coord.* += 27;
    try testing.expect(Follower_CheckForTrigger(&info));
    link_y_coord.* += 1; // 28 is outside
    try testing.expect(!Follower_CheckForTrigger(&info));
}

test "proximity gives the follower a grace period before it re-attaches" {
    resetRam();
    link_x_coord.* = 100;
    link_y_coord.* = 100;
    saved_tagalong_x.* = 100;
    saved_tagalong_y.* = 100;

    // While the timer is still running it always reports far away.
    timer_tagalong_reacquire.* = 5;
    try testing.expect(Follower_CheckProximityToLink());
    try testing.expectEqual(@as(u8, 4), timer_tagalong_reacquire.*);

    // Once it wraps past zero the box test applies, and this is inside it.
    timer_tagalong_reacquire.* = 0;
    try testing.expect(!Follower_CheckProximityToLink());
    try testing.expectEqual(@as(u8, 0), timer_tagalong_reacquire.*);

    // Move Link away and it reports far again.
    link_x_coord.* = 1000;
    timer_tagalong_reacquire.* = 0;
    try testing.expect(Follower_CheckProximityToLink());
}

test "Follower_Disable only clears the two Kiki indicators" {
    resetRam();
    follower_indicator.* = 9;
    Follower_Disable();
    try testing.expectEqual(@as(u8, 0), follower_indicator.*);

    follower_indicator.* = 10;
    Follower_Disable();
    try testing.expectEqual(@as(u8, 0), follower_indicator.*);

    follower_indicator.* = 4;
    Follower_Disable();
    try testing.expectEqual(@as(u8, 4), follower_indicator.*); // left alone
}

test "the backwards array searches match the C helpers" {
    try testing.expectEqual(@as(i32, 0), FindInByteArray(&kTagalong_Tab0, 5));
    try testing.expectEqual(@as(i32, 2), FindInByteArray(&kTagalong_Tab0, 0xa));
    try testing.expectEqual(@as(i32, -1), FindInByteArray(&kTagalong_Tab0, 0xff));
    try testing.expectEqual(@as(i32, 3), FindInWordArray(&kTagalong_IndoorRooms, 2));
    try testing.expectEqual(@as(i32, -1), FindInWordArray(&kTagalong_IndoorRooms, 0x1234));
    // A duplicate resolves to the last entry, because the search runs backwards.
    const dup = [_]u8{ 7, 7, 7 };
    try testing.expectEqual(@as(i32, 2), FindInByteArray(&dup, 7));
}

test "Tagalong_Draw picks the priority from the layer bits" {
    resetRam();
    tagalong_var5.* = 1; // disabled: returns without touching anything
    oam_priority_value.* = 0xeeee;
    Tagalong_Draw();
    try testing.expectEqual(@as(u16, 0xeeee), oam_priority_value.*);

    tagalong_var5.* = 0;
    tagalong_var2.* = 0;
    tagalong_z[0] = 1;
    player_is_indoors.* = 0;
    follower_indicator.* = 1;
    sort_sprites_setting.* = 0;
    Tagalong_Draw();
    // A raised follower outdoors uses priority 0x20.
    try testing.expectEqual(@as(u16, 0x2000), oam_priority_value.*);
}

test "the message tables came over intact" {
    try testing.expectEqual(12, kTagalong_IndoorInfos.len);
    try testing.expectEqual(5, kTagalong_OutdoorInfos.len);
    try testing.expectEqual(@as(u16, 0x1ef0), kTagalong_IndoorInfos[0].y);
    try testing.expectEqual(@as(u16, 0x99), kTagalong_IndoorInfos[0].msg);
    try testing.expectEqual(@as(u16, 0xffff), kTagalong_OutdoorInfos[1].msg);
    // The offset tables bracket the info arrays exactly.
    try testing.expectEqual(kTagalong_IndoorInfos.len, kTagalong_IndoorOffsets[7]);
    try testing.expectEqual(kTagalong_OutdoorInfos.len, kTagalong_OutdoorOffsets[3]);
    try testing.expectEqual(kTagalong_IndoorRooms.len, kTagalong_IndoorOffsets.len - 1);
    try testing.expectEqual(kTagalong_OutdoorRooms.len, kTagalong_OutdoorOffsets.len - 1);
}

test "the drawing tables came over intact" {
    try testing.expectEqual(56, kTagalongDraw_SprXY.len);
    try testing.expectEqual(16, kTagalongDmaAndFlags.len);
    try testing.expectEqual(4, @sizeOf(TagalongSprXY));
    try testing.expectEqual(3, @sizeOf(TagalongDmaFlags));
    try testing.expectEqual(@as(i8, -2), kTagalongDraw_SprXY[0].y1);
    try testing.expectEqual(@as(i8, 1), kTagalongDraw_SprXY[55].x1);
    try testing.expectEqual(@as(u8, 0x40), kTagalongDmaAndFlags[15].flags);
    try testing.expectEqual(14, kTagalongDraw_Pals.len);
    try testing.expectEqual(14, kTagalongDraw_Offs.len);
    try testing.expectEqual(24, kTagalongDraw_SprInfo0.len);
}
