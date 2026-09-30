//! Port of src/player_oam.c: builds Link's OAM every frame: body, sword,
//! shield, shadow and the foot ripple/grass object.
//!
//! The data tables live in player_oam_tables.zig, generated from the C.
const std = @import("std");
const config = @import("config.zig");
const vars = @import("variables.zig");
const features = @import("features.zig");
const t = @import("player_oam_tables.zig");

const OamEnt = vars.OamEnt;
const g_ram = &vars.g_ram;
const oam_buf = vars.oam_buf;
const bytewise_extended_oam = vars.bytewise_extended_oam;

// player.h
const kPlayerState_SpinAttacking: u8 = 3;
const kPlayerState_Swimming: u8 = 4;
const kPlayerState_TurtleRock: u8 = 5;
const kPlayerState_Ether: u8 = 8;
const kPlayerState_Bombos: u8 = 9;
const kPlayerState_Quake: u8 = 10;
const kPlayerState_Hookshot: u8 = 19;
const kPlayerState_AsleepInBed: u8 = 22;
const kPlayerState_SpinAttackMotion: u8 = 30;

// player.c
extern const kSwimmingTab1: [4]u8;

pub const SwordResult = extern struct {
    r6: u8,
    r12: u8,
};

/// misc.h's FindInByteArray, which searches backwards.
fn findInByteArray(data: []const u8, lookfor: u8) c_int {
    var i = data.len;
    while (i != 0) {
        i -= 1;
        if (data[i] == lookfor)
            return @intCast(i);
    }
    return -1;
}

/// OamEnt is {x, y, charnum, flags}; the C writes pairs of them as a word.
fn oamXY(oam: *align(1) OamEnt, v: u16) void {
    std.mem.writeInt(u16, @as([*]u8, @ptrCast(oam))[0..2], v, .little);
}

fn oamCharFlags(oam: *align(1) OamEnt, v: u16) void {
    std.mem.writeInt(u16, @as([*]u8, @ptrCast(oam))[2..4], v, .little);
}

/// The C repeats this z-coordinate clamp at every draw site.
fn linkZOffset() u8 {
    const z = vars.link_z_coord.*;
    const lo: u8 = @truncate(z);
    return if (@as(i16, @bitCast(z)) >= 0 or lo < 0xf0) lo else 0;
}

fn i8at(tab: anytype, i: usize) u8 {
    return @bitCast(tab[i]);
}

pub export fn PlayerOam_WantInvokeSword() callconv(.c) bool {
    const st = vars.link_player_handler_state.*;
    if (st != kPlayerState_Ether and
        st != kPlayerState_Bombos and
        st != kPlayerState_Quake and
        st != kPlayerState_SpinAttacking and
        st != kPlayerState_SpinAttackMotion and
        vars.link_state_bits.* == 0 and
        vars.link_force_hold_sword_up.* == 0 and
        vars.link_electrocute_on_touch.* == 0)
    {
        if (vars.link_item_in_hand.* & 0x40 != 0)
            return false;
        if (vars.link_position_mode.* & 0x3d != 0 or vars.link_item_in_hand.* & 0x93 != 0)
            return true;
        if (vars.button_mask_b_y.* & 0x80 == 0)
            return false;
    }
    return ((vars.link_sword_type.* +% 1) & 0xfe) != 0;
}

pub export fn CalculateSwordHitBox() callconv(.c) void { // 879e63
    if (vars.link_sword_type.* == 0 or vars.link_sword_type.* == 0xff)
        return;
    if (vars.link_sword_type.* >= 2 and vars.button_b_frames.* < 9) {
        const i: usize = vars.button_b_frames.* + (@as(usize, vars.link_direction_facing.* >> 1) * 9);
        if (@as(u8, @truncate(t.kSwordTipSomething[i])) != 0xff) {
            vars.player_oam_y_offset.* = i8at(t.kSwordOamYOffs_Good, i);
            vars.player_oam_x_offset.* = i8at(t.kSwordOamXOffs_Good, i);
            return;
        }
    }
    var offs = vars.button_b_frames.*;
    if (offs == 9)
        return;
    var y: u8 = 39;
    if (offs >= 10) {
        offs -= 10;
        y = 3;
    }
    const i: usize = t.kPlayerOamOtherOffs[@as(usize, vars.link_direction_facing.* >> 1) * 40 + y] + offs;
    vars.player_oam_y_offset.* = i8at(t.kSwordOamYOffs, i);
    vars.player_oam_x_offset.* = i8at(t.kSwordOamXOffs, i);
}

/// Link's sprites past the edges of the original 256-pixel screen.
///
/// The drawing below keeps Link's screen position in eight bits and works out
/// each piece's ninth bit - which side of the screen it's on - from that,
/// which only works while Link's on the original screen: the body guesses
/// from its eight bits, the legs don't set it at all. It never mattered, since
/// the camera always kept Link on it. The widescreen camera lets him walk into
/// the margins at an area's edge, and there his body and legs wrapped round
/// to the far side while his shield (which works it out properly) stayed put.
/// So afterwards, each of his pieces gets the ninth bit that puts it nearest
/// Link. Only with the widescreen camera on: the original screen never needs
/// it, and the bits there stay the original's.
fn widescreenLinkOam() void {
    if (!config.g_widescreen_camera or config.g_config.extended_aspect_ratio == 0) return;
    // Hidden pieces are marked by their y then, not these bits.
    if (features.enhanced_features0.* & features.kFeatures0_WidescreenVisualFixes == 0) return;
    const center: i32 = @as(i32, @as(i16, @bitCast(vars.link_x_coord.* -% vars.BG2HOFS_copy2.*))) + 8;
    const base: usize = vars.sort_sprites_offset_into_oam_buffer.* >> 2;
    for (0..12) |i| {
        const e = &oam_buf[base + i];
        if (e.y == 0xf0) continue;
        const x8: i32 = e.x;
        var best = x8;
        for ([_]i32{ x8 - 256, x8 + 256 }) |c| {
            if (@abs(c - center) < @abs(best - center)) best = c;
        }
        const hi: u8 = @intCast((best >> 8) & 1);
        bytewise_extended_oam[base + i] = (bytewise_extended_oam[base + i] & ~@as(u8, 1)) | hi;
    }
}

/// In a doorway, Link's hidden once he's within 4 pixels of the screen's
/// left or right edge, so he doesn't wrap round to the other side as the
/// doorway takes him off it. The widescreen camera stops short of a room's
/// edge, so a side doorway is past the 4:3 screen's edge and in the margin
/// beyond, where he'd have gone before reaching it; with the pieces put on
/// the right side of the wrap (widescreenLinkOam), it's the wide screen's
/// edges that count.
fn doorwayOffScreenX(tv: u16) bool {
    if (!config.g_widescreen_camera or config.g_config.extended_aspect_ratio == 0 or
        features.enhanced_features0.* & features.kFeatures0_WidescreenVisualFixes == 0)
        return tv < 4 or tv >= 252;
    const x: i32 = @as(i16, @bitCast(tv));
    const extra: i32 = config.g_config.extended_aspect_ratio;
    return x < 4 - extra or x >= 252 + extra;
}

pub export fn LinkOam_Main() callconv(.c) void { // 8da18e
    defer widescreenLinkOam();
    const y_coord_backup = vars.link_y_coord.*;

    if (vars.submodule_index.* == 18 or vars.submodule_index.* == 19) {
        var idx: usize = if (vars.submodule_index.* == 18) 0 else 12;
        idx += if (vars.which_staircase_index.* & 4 != 0) 6 else 0;
        idx += if (vars.link_animation_steps.* < 6) vars.link_animation_steps.* else 0;
        vars.link_y_coord.* +%= @as(u16, @bitCast(@as(i16, t.kPlayerOam_StairsOffsY[idx])));
    }

    const xcoord: u8 = @truncate(vars.link_x_coord.* -% vars.BG2HOFS_copy2.*);
    const ycoord: u8 = @truncate(vars.link_y_coord.* -% vars.BG2VOFS_copy2.*);
    vars.player_oam_x_offset.* = 0x80;
    vars.player_oam_y_offset.* = 0x80;
    const scratch_0_var = vars.draw_water_ripples_or_grass.* != 0;
    vars.oam_priority_value.* = t.kPlayerOam_FloorOamPrio[vars.link_is_on_lower_level.*];
    vars.sort_sprites_offset_into_oam_buffer.* = t.kPlayerOam_SortSpritesOffs[vars.sort_sprites_setting.*];

    var yt: u8 = undefined;
    var rt: u8 = undefined;

    // The C threads several `goto continue_after_set` jumps plus one
    // `goto link_state_is_empty` through this; `done` is the former and
    // falling out of `state_empty` is the latter.
    done: {
        state_empty: {
            if (vars.link_player_handler_state.* == kPlayerState_AsleepInBed and
                vars.link_pose_during_opening.* != 2)
            {
                yt = 0x1f;
                rt = vars.link_pose_during_opening.*;
                break :done;
            }
            if (vars.link_force_hold_sword_up.* != 0) {
                yt = 0x24;
                rt = 0;
                vars.link_direction_facing_mirror.* = vars.link_direction_facing.*;
                break :done;
            }
            if (vars.link_is_bunny_mirror.* != 0) {
                yt = 0x21;
                rt = vars.link_animation_steps.* & 3;
                vars.link_direction_facing_mirror.* = vars.link_direction_facing.*;
                break :done;
            }
            yt = if (vars.draw_water_ripples_or_grass.* != 0) 10 else 0;

            // The comma operator sets yt only once the first two tests pass.
            var moving = false;
            if (vars.submodule_index.* == 14 and vars.main_module_index.* != 18) {
                yt = 10;
                moving = vars.link_actual_vel_x.* != 0;
            }
            if (moving) {
                if (vars.link_direction_facing.* != 4 and vars.link_direction_facing.* != 6) {
                    rt = @bitCast(t.kPlayerOam_Tab1[vars.link_animation_steps.*]);
                    yt = if (vars.which_staircase_index.* & 4 != 0) 0x1a else 0x19;
                } else {
                    rt = vars.link_animation_steps.*;
                }
            } else {
                if (vars.link_grabbing_wall.* & 3 != 0) {
                    yt = 0x18;
                    rt = vars.some_animation_timer_steps.*;
                } else {
                    if (vars.bitmask_of_dragstate.* & 0xd != 0) {
                        yt = 0x16;
                        if (vars.link_animation_steps.* >= 5)
                            vars.link_animation_steps.* = 0;
                    }
                    rt = vars.link_animation_steps.*;
                }
            }
            vars.link_direction_facing_mirror.* = vars.link_direction_facing.*;
            if (vars.link_is_in_deep_water.* != 0)
                vars.oam_priority_value.* = 0x2000;

            if (vars.link_player_handler_state.* == kPlayerState_Swimming) {
                yt = 0x11;
                rt &= 1;
                if ((vars.submodule_index.* == 0 and (vars.joypad1H_last.* & 0xf) != 0) or
                    (vars.swimcoll_var7[0] | vars.swimcoll_var7[1]) != 0)
                {
                    yt = 0x13;
                    rt = vars.byte_7E02CC.*;
                }
                if (vars.link_maybe_swim_faster.* != 0) {
                    yt = 0x12;
                    rt = vars.link_maybe_swim_faster.* -% 1;
                }
                break :done;
            }
            if (vars.link_pose_for_item.* != 0) {
                rt = 0;
                yt = if (vars.link_pose_for_item.* != 2) 0x1d else 0x1e;
                break :done;
            }
            if (vars.player_unk1.* & 1 != 0) {
                yt = 0x1b;
                rt = vars.some_animation_timer_steps.*;
                break :done;
            }

            if (vars.link_auxiliary_state.* != 0) {
                if (vars.link_auxiliary_state.* == 4) {
                    yt = 0x13;
                    rt = kSwimmingTab1[(vars.frame_counter.* & 0x18) >> 3];
                    break :done;
                } else if (vars.link_auxiliary_state.* == 1) {
                    if (vars.link_player_handler_state.* == kPlayerState_TurtleRock) {
                        if (vars.byte_7E034E.* == 0)
                            vars.oam_priority_value.* = 0x3000;
                        break :state_empty;
                    } else if (vars.link_player_handler_state.* != kPlayerState_Hookshot and
                        vars.link_cape_mode.* == 0)
                    {
                        if (vars.link_electrocute_on_touch.* != 0) {
                            yt = 0x14;
                            rt = vars.player_handler_timer.* & 3;
                        } else {
                            yt = 5;
                            rt = 0;
                        }
                        break :done;
                    }
                }
            }

            if (vars.player_near_pit_state.* != 0 and vars.player_near_pit_state.* != 1) {
                if (vars.player_near_pit_state.* == 3)
                    vars.sort_sprites_offset_into_oam_buffer.* = 0;
                yt = 4;
                rt = vars.link_this_controls_sprite_oam.*;
                if (rt >= 6)
                    vars.oam_priority_value.* |= 0x3000;
                break :done;
            }

            if (vars.link_state_bits.* != 0) {
                const bit = FindMostSignificantBit(vars.link_state_bits.*);
                if (bit < 6)
                    vars.link_direction_facing_mirror.* = 2;
                yt = @bitCast(t.kPlayerOam_Tab4[bit]);
                if (yt >= 0xd) {
                    if (vars.link_picking_throw_state.* & 2 != 0)
                        yt +%= 1;

                    if (vars.link_picking_throw_state.* & 1 != 0) {
                        yt = 0x10;
                    } else if (vars.link_state_bits.* & 0x80 != 0) {
                        break :done;
                    }
                }
                rt = vars.some_animation_timer_steps.*;
                break :done;
            }
        }
        // link_state_is_empty:
        if (vars.link_unk_master_sword.* != 0) {
            yt = 0x17;
            rt = vars.link_unk_master_sword.* -% 1;
            break :done;
        }

        if (vars.link_item_in_hand.* != 0) {
            yt = @bitCast(t.kPlayerOam_Tab2[FindMostSignificantBit(vars.link_item_in_hand.*)]);
            rt = vars.player_handler_timer.*;
            break :done;
        } else if (vars.link_position_mode.* != 0) {
            yt = @bitCast(t.kPlayerOam_Tab3[FindMostSignificantBit(vars.link_position_mode.*)]);
            rt = vars.player_handler_timer.*;
            break :done;
        }

        const st = vars.link_player_handler_state.*;
        if (st == kPlayerState_Quake or st == kPlayerState_Ether or st == kPlayerState_Bombos) {
            yt = 0x15;
            rt = vars.state_for_spin_attack.*;
            break :done;
        } else if (st == kPlayerState_SpinAttackMotion or st == kPlayerState_SpinAttacking) {
            yt = 0xf;
            rt = vars.state_for_spin_attack.*;
            break :done;
        }

        if (vars.button_mask_b_y.* & 0x80 != 0) {
            if (vars.button_b_frames.* == 9) {
                yt = 2;
            } else {
                yt = 0x27;
                rt = vars.button_b_frames.*;
                if (rt >= 9) {
                    yt = 3;
                    rt -%= 10;
                }
            }
        }
    }
    // continue_after_set:
    vars.value_computed_for_player_oam.* = yt;
    if (yt != 5)
        vars.oam_priority_value_2.* = vars.oam_priority_value.*;

    @as([*]u8, @ptrCast(vars.index_of_interacting_tile))[0] = rt;

    const dir: usize = vars.link_direction_facing.* >> 1;

    const r2: usize = t.kPlayerOamOtherOffs[dir * 40 + yt] + rt;
    var r4loc: usize = t.kPlayerOamSpriteLocs[r2];

    vars.link_palette_bits_of_oam.* = if (vars.palette_swap_flag.* != 0) 0 else 0xe00;
    vars.link_dma_var1.* = 0;
    vars.link_dma_var2.* = 0;

    const xt = findInByteArray(&t.kPlayerOam_Tab5, yt);
    if (xt >= 0) {
        const j: usize = t.kPlayerOam_Tab6[@as(usize, @intCast(xt)) + dir * 7] + rt;
        vars.scratch_1.* = @intCast(j);
        {
            const bank1: u8 = @bitCast(t.kPlayerOam_Spr1Bank[j]);
            if (bank1 != 0xff) {
                vars.link_dma_var1.* = @as(u16, bank1) * 2;
                const tab = if (scratch_0_var) &t.kPlayerOam_Tab19B else &t.kPlayerOam_Tab19A;
                const oam_pos: usize = (@as(usize, tab[r4loc]) + vars.sort_sprites_offset_into_oam_buffer.*) >> 2;
                const zt = linkZOffset();
                oam_buf[oam_pos].y = i8at(t.kPlayerOam_Spr1Y, j) +% ycoord -% zt;
                oam_buf[oam_pos].x = i8at(t.kPlayerOam_Spr1X, j) +% xcoord;
                var q = std.mem.readInt(u16, t.kPlayerOam_Prio[bank1 >> 1 ..][0..2], .little);
                q = if (bank1 & 1 != 0) q << 4 else q;
                oamCharFlags(&oam_buf[oam_pos], (q & 0xc000) | vars.oam_priority_value.* |
                    vars.link_palette_bits_of_oam.* | 4);
                bytewise_extended_oam[oam_pos] = 0;
            }
        }

        const bank2: u8 = @bitCast(t.kPlayerOam_Spr2Bank[j]);
        if (bank2 != 0xff) {
            vars.link_dma_var2.* = @as(u16, bank2) * 2;
            const tab = if (scratch_0_var) &t.kPlayerOam_Tab20B else &t.kPlayerOam_Tab20A;
            const oam_pos: usize = (@as(usize, tab[r4loc]) + vars.sort_sprites_offset_into_oam_buffer.*) >> 2;
            const zt = linkZOffset();
            oam_buf[oam_pos].y = i8at(t.kPlayerOam_Spr2Y, j) +% ycoord -% zt;
            oam_buf[oam_pos].x = i8at(t.kPlayerOam_Spr2X, j) +% xcoord;
            var q = std.mem.readInt(u16, t.kPlayerOam_Prio[bank2 >> 1 ..][0..2], .little);
            q = if (bank2 & 1 != 0) q << 4 else q;
            oamCharFlags(&oam_buf[oam_pos], (q & 0xc000) | vars.oam_priority_value.* |
                vars.link_palette_bits_of_oam.* | 0x14);
            bytewise_extended_oam[oam_pos] = 0;
        }
    }

    var sr: SwordResult = undefined;

    if (vars.link_picking_throw_state.* & 4 != 0) {
        LinkOam_UnusedWeaponSettings(@intCast(r4loc), xcoord, ycoord);
    } else if (PlayerOam_WantInvokeSword() and !LinkOam_SetWeaponVRAMOffsets(@intCast(r2), &sr)) {
        const zcoord = linkZOffset();
        var oam_y = i8at(t.kDrawSword_y, r2) +% ycoord -% zcoord;
        var oam_x = i8at(t.kDrawSword_x, r2) +% xcoord;

        const use_offsets = if (vars.link_item_in_hand.* & 2 != 0)
            (vars.player_handler_timer.* == 2 and vars.link_delay_timer_spin_attack.* == 15)
        else
            (vars.link_item_in_hand.* & 5) == 0;
        if (use_offsets) {
            vars.player_oam_y_offset.* = i8at(t.kSwordOamYOffs, r2);
            vars.player_oam_x_offset.* = i8at(t.kSwordOamXOffs, r2);
        }
        var oam_pal: u16 = 0;
        if (vars.link_item_in_hand.* & 5 != 0) {
            std.debug.assert(vars.link_state_bits.* == 0);
            oam_pal = @as(u16, @bitCast(@as(i16, t.kPlayerOam_Rod[vars.eq_selected_rod.* - 1]))) << 8;
        }
        // The cane of byrna is blue, whichever button swung it. The original
        // asked what Y held, which was the same thing when Y was the only
        // item button.
        if (vars.link_position_mode.* & 8 != 0 and vars.current_item_active.* == 13)
            oam_pal = 0x400; // cane of byrna

        const tab = if (scratch_0_var) &t.kSwordStuff_oam_index_ptrs_1 else &t.kSwordStuff_oam_index_ptrs_0;
        var oam_pos: usize = (@as(usize, tab[r4loc]) + vars.sort_sprites_offset_into_oam_buffer.*) >> 2;
        oam_pos = @intCast(LinkOam_CalculateSwordSparklePosition(@intCast(oam_pos), xcoord, ycoord));

        var j: usize = @as(usize, sr.r6) * 3;
        for (0..3) |i| {
            var td = t.kSwordTiledata[j];
            if (td != 0xffff) {
                td = (td & ~@as(u16, 0x3000)) | vars.oam_priority_value.*;
                if ((td & 0xe00) != 0x200 and vars.link_palette_bits_of_oam.* == 0)
                    td = (td & ~@as(u16, 0xe00)) | 0x600;
                if (oam_pal != 0)
                    td = (td & ~@as(u16, 0xe00)) | oam_pal;
                oamCharFlags(&oam_buf[oam_pos], td);
                oam_buf[oam_pos].x = oam_x;
                oam_buf[oam_pos].y = oam_y;
                var xd: u16 = @as(u16, xcoord) -% oam_x;
                if (@as(i16, @bitCast(xd)) < 0) xd = 0 -% xd;
                bytewise_extended_oam[oam_pos] = sr.r12 | @intFromBool(xd >= 0x80);
                oam_pos += 1;
            }
            oam_x +%= 8;
            if (i == 1) {
                oam_x -%= 16;
                oam_y +%= 8;
            }
            j += 1;
        }
    }

    // SwordStuff_fail
    if (vars.link_shield_type.* != 0 and vars.sram_progress_indicator.* != 0 and
        !LinkOam_SetEquipmentVRAMOffsets(@intCast(r2), &sr))
    {
        const zcoord = linkZOffset();
        var oam_y = i8at(t.kShieldStuff_y, r2) +% ycoord -% 1 -% zcoord;
        var oam_x = i8at(t.kShieldStuff_x, r2) +% xcoord;

        LinkOam_CalculateXOffsetRelativeLink(i8at(t.kShieldStuff_x, r2));

        const oam_pal: u16 = if ((vars.link_palette_bits_of_oam.* >> 8) != 0) 0xa00 else 0x600;

        const tab = if (scratch_0_var) &t.kShieldStuff_oam_index_ptrs_1 else &t.kShieldStuff_oam_index_ptrs_0;
        const oam_pos: usize = (@as(usize, tab[r4loc]) + vars.sort_sprites_offset_into_oam_buffer.*) >> 2;

        var j: usize = @as(usize, sr.r6) * 3;
        for (0..3) |i| {
            const td = t.kShieldStuff_OamData[j];
            j += 1;
            if (td == 0xffff) {
                // The C `continue`s without advancing oam_x/oam_y.
                continue;
            }
            oamCharFlags(&oam_buf[oam_pos], (td & 0xc1ff) | oam_pal | vars.oam_priority_value.*);
            oamXY(&oam_buf[oam_pos], @as(u16, oam_x) | @as(u16, oam_y) << 8);
            bytewise_extended_oam[oam_pos] = sr.r12 | @as(u8, @truncate(vars.bit9_of_xcoord.*));
            oam_x +%= 8;
            if (i == 1) {
                oam_x -%= 16;
                oam_y +%= 8;
            }
        }
    }

    if (vars.link_visibility_status.* != 12 and
        vars.link_player_handler_state.* != kPlayerState_AsleepInBed)
    {
        if (vars.value_computed_for_player_oam.* != 5 and vars.draw_water_ripples_or_grass.* != 0) {
            LinkOam_DrawFootObject(@intCast(r4loc), xcoord, ycoord);
        } else if (vars.link_auxiliary_state.* != 4 and
            vars.link_player_handler_state.* != kPlayerState_Swimming)
        {
            if (vars.player_near_pit_state.* != 0 and vars.player_near_pit_state.* != 1) {
                if (vars.link_this_controls_sprite_oam.* >= 6) {
                    LinkOam_DrawDungeonFallShadow(@intCast(r4loc), xcoord);
                    r4loc = 2; // wtf
                }
            } else {
                // draw shadow
                const shadow_idx: usize = @intFromBool(vars.link_auxiliary_state.* != 0 and
                    (vars.link_auxiliary_state.* != 1 or vars.link_cape_mode.* == 0));
                const mdir: usize = vars.link_direction_facing_mirror.* >> 1;
                const oam_y = vars.link_y_coord.* -% vars.BG2VOFS_copy2.* +%
                    @as(u16, @bitCast(@as(i16, t.kOffsToShadowGivenDir_Y[mdir])));
                if (oam_y < 256) {
                    const oam_x = xcoord +% i8at(t.kOffsToShadowGivenDir_X, mdir);
                    const tab = if (scratch_0_var) &t.kShadow_oam_indexes_1 else &t.kShadow_oam_indexes_0;
                    const oam_pos: usize = (@as(usize, tab[r4loc]) + vars.sort_sprites_offset_into_oam_buffer.*) >> 2;

                    var td = (t.kLinkShadows_Chardata[shadow_idx * 2] & ~@as(u16, 0x3000)) |
                        vars.oam_priority_value_2.*;
                    if (vars.link_palette_bits_of_oam.* == 0)
                        td = (td & ~@as(u16, 0xe00)) | 0x600;
                    oamCharFlags(&oam_buf[oam_pos + 0], td);
                    oamCharFlags(&oam_buf[oam_pos + 1], (td & ~@as(u16, 0xC000)) | 0x4000);
                    oamXY(&oam_buf[oam_pos + 0], @as(u16, oam_x) | oam_y << 8);
                    oamXY(&oam_buf[oam_pos + 1], @as(u16, oam_x +% 8) | oam_y << 8);
                    bytewise_extended_oam[oam_pos + 0] = 0;
                    bytewise_extended_oam[oam_pos + 1] = 0;
                }
            }
        }
    }

    {
        const tab = if (scratch_0_var) &t.kLinkBody_oam_index_1 else &t.kLinkBody_oam_index_0;
        const oam_pos: usize = (@as(usize, tab[r4loc]) + vars.sort_sprites_offset_into_oam_buffer.*) >> 2;

        const j: usize = t.kLinkDmaGraphicsIndices[r2];
        vars.link_dma_graphics_index.* = @intCast(j * 2);

        if (vars.link_visibility_status.* != 12) {
            const zcoord = linkZOffset();
            const sp = &t.kLinkSpriteBodys[j];

            const oam_y = ycoord +% @as(u8, @bitCast(sp.y)) -% zcoord;
            const oam_x = xcoord +% @as(u8, @bitCast(sp.x));
            const td: u16 = @as(u16, sp.tile) << 8;

            if ((td & 0xf000) != 0xf000) {
                oamCharFlags(&oam_buf[oam_pos], (td & 0xf000) | vars.oam_priority_value.* |
                    vars.link_palette_bits_of_oam.*);
                oamXY(&oam_buf[oam_pos], @as(u16, oam_x) | @as(u16, oam_y) << 8);
                bytewise_extended_oam[oam_pos] = 2 + @as(u8, @intFromBool(oam_x >= 0xf8));
            }

            if ((td << 4 & 0xf000) != 0xf000) {
                oamCharFlags(&oam_buf[oam_pos + 1], (td << 4 & 0xf000) | vars.oam_priority_value.* |
                    vars.link_palette_bits_of_oam.* | 2);
                oamXY(&oam_buf[oam_pos + 1], @as(u16, xcoord) | @as(u16, ycoord -% zcoord +% 8) << 8);
                bytewise_extended_oam[oam_pos + 1] = 2;
            }
        }
    }

    var hide_shadow = true;
    var want_hide = false;
    if (vars.is_standing_in_doorway.* != 0) {
        var tv = vars.link_x_coord.* -% vars.BG2HOFS_copy2.*;
        if (doorwayOffScreenX(tv)) {
            want_hide = true;
        } else {
            tv = vars.link_y_coord.* -% vars.BG2VOFS_copy2.*;
            if (tv < 4 or tv >= 224)
                want_hide = true;
        }
    }
    if (!want_hide) {
        hide_shadow = false;
        var blink = false;
        if (vars.submodule_index.* == 0 and vars.countdown_for_blink.* != 0) {
            vars.countdown_for_blink.* -%= 1;
            if (vars.countdown_for_blink.* >= 4 and (vars.countdown_for_blink.* & 1) == 0)
                blink = true;
        }
        if (blink or vars.link_visibility_status.* == 12 or vars.link_cape_mode.* != 0)
            want_hide = true;
    }
    if (want_hide) {
        const tab = if (scratch_0_var) &t.kShadow_oam_indexes_1 else &t.kShadow_oam_indexes_0;
        const shadow_oam_pos: i32 = if (!hide_shadow and vars.link_visibility_status.* != 12)
            @as(i32, tab[r4loc]) >> 2
        else
            -10;

        // This appears to hide link by setting the extended bits of the oam to
        // hide them from the screen. It doesn't really play well with the
        // widescreen modes, so change how it's done.
        if (features.enhanced_features0.* & features.kFeatures0_WidescreenVisualFixes != 0) {
            const oam = oam_buf + (vars.sort_sprites_offset_into_oam_buffer.* >> 2);
            var i: i32 = 0;
            while (i < 12) : (i += 1) {
                if (i < shadow_oam_pos or i > shadow_oam_pos + 1)
                    oam[@intCast(i)].y = 0xf0;
            }
        } else {
            const p = bytewise_extended_oam + (vars.sort_sprites_offset_into_oam_buffer.* >> 2);
            var i: usize = 0;
            while (i < 12) : (i += 2)
                std.mem.writeInt(u16, p[i..][0..2], 0x101, .little);
            // Clear the bit again for the shadow oam so it's not hidden?
            if (shadow_oam_pos >= 0)
                std.mem.writeInt(u16, p[@intCast(shadow_oam_pos)..][0..2], 0, .little);
        }
    }

    if (vars.submodule_index.* == 18 or vars.submodule_index.* == 19)
        vars.link_y_coord.* = y_coord_backup;
}

pub export fn FindMostSignificantBit(v_in: u8) callconv(.c) u8 { // 8daac3
    var v = v_in;
    var i: i32 = 7;
    while (v & 0x80 == 0) {
        i -= 1;
        if (i < 0) break;
        v <<= 1;
    }
    return @truncate(@as(u32, @bitCast(i)));
}

pub export fn LinkOam_SetWeaponVRAMOffsets(r2: c_int, sr: *SwordResult) callconv(.c) bool { // 8dab6e
    const j: u8 = @bitCast(t.kPlayerOam_Main_SwordStuff_array1[@intCast(r2)]);
    sr.r6 = j;
    if (j == 0xff)
        return true;
    sr.r12 = t.kPlayerOam_Main_SwordStuff_array2[j];
    var y = t.kPlayerOam_Main_SwordStuff_array3[j];
    if (j < 29) {
        vars.link_dma_var3.* = y;
    } else {
        if (vars.link_item_in_hand.* & 5 != 0)
            y = t.kPlayerOam_Main_SwordStuff_array4[j - 29];
        vars.link_dma_var5.* = y;
    }
    return false;
}

pub export fn LinkOam_SetEquipmentVRAMOffsets(r2: c_int, sr: *SwordResult) callconv(.c) bool { // 8dabe6
    const j: u8 = @bitCast(t.kPlayerOam_ShieldStuff_array1[@intCast(r2)]);
    sr.r6 = j;
    if (j == 0xff)
        return true;

    var y = t.kPlayerOam_ShieldStuff_array2[j];
    if (j >= 8) {
        if (vars.link_item_in_hand.* & 5 != 0)
            y = t.kPlayerOam_ShieldStuff_array3[j - 8];
        vars.link_dma_var5.* = y;
        sr.r12 = if (y & 7 != 0) 0 else 2;
    } else {
        vars.link_dma_var4.* = y;
        sr.r12 = 2;
    }
    return false;
}

pub export fn LinkOam_CalculateSwordSparklePosition(oam_pos: c_int, oam_x_in: u8, oam_y_in: u8) callconv(.c) c_int { // 8dacd5
    if ((vars.link_player_handler_state.* | vars.link_speed_setting.*) != 0)
        return oam_pos;
    if (vars.link_sword_type.* == 0 or vars.link_sword_type.* == 1 or vars.link_sword_type.* == 0xff or
        (vars.button_mask_b_y.* & 0x80) == 0 or vars.button_b_frames.* >= 9)
        return oam_pos;

    const i: usize = @as(usize, vars.link_direction_facing.* >> 1) * 9 + vars.button_b_frames.*;
    var td = t.kSwordTipSomething[i];
    if (td == 0xffff)
        return oam_pos;
    td = (td & ~@as(u16, 0x3000)) | vars.oam_priority_value.*;
    if (vars.link_palette_bits_of_oam.* == 0)
        td = (td & ~@as(u16, 0xe00)) | 0x600;
    const pos: usize = @intCast(oam_pos);
    oamCharFlags(&oam_buf[pos], td);
    vars.player_oam_x_offset.* = i8at(t.kSwordOamXOffs_Good, i);
    vars.player_oam_y_offset.* = i8at(t.kSwordOamYOffs_Good, i);
    const oam_x = oam_x_in +% vars.player_oam_x_offset.*;
    const oam_y = oam_y_in +% vars.player_oam_y_offset.*;
    oam_buf[pos].x = oam_x;
    oam_buf[pos].y = oam_y;
    LinkOam_CalculateXOffsetRelativeLink(vars.player_oam_x_offset.*);
    bytewise_extended_oam[pos] = @truncate(vars.bit9_of_xcoord.*);
    return oam_pos + 1;
}

pub export fn LinkOam_UnusedWeaponSettings(r4loc: c_int, oam_x: u8, oam_y: u8) callconv(.c) void { // 8dadb6
    var j: usize = @as(usize, vars.link_var30e.*) * 4;
    const tab = if (vars.draw_water_ripples_or_grass.* != 0)
        &t.kSwordStuff_oam_index_ptrs_1
    else
        &t.kSwordStuff_oam_index_ptrs_0;
    var oam_pos: usize = (@as(usize, tab[@intCast(r4loc)]) + vars.sort_sprites_offset_into_oam_buffer.*) >> 2;
    var oam = oam_buf + oam_pos;
    for (0..4) |_| {
        const st: u8 = @bitCast(t.kPlayerOam_DrawOam_Throwing_State[j]);
        if (st != 0xff) {
            oamCharFlags(&oam[0], (0x2609 & ~@as(u16, 0x3000)) | vars.oam_priority_value.*);
            oam[0].x = oam_x +% i8at(t.kPlayerOam_DrawOam_Throwing_X, j);
            oam[0].y = oam_y +% i8at(t.kPlayerOam_DrawOam_Throwing_Y, j);
            bytewise_extended_oam[oam_pos] = 0;
            oam += 1;
            oam_pos += 1;
        }
        j += 1;
    }
}

pub export fn LinkOam_DrawDungeonFallShadow(r4loc: c_int, xcoord_in: u8) callconv(.c) void { // 8dae3b
    var xcoord = xcoord_in;
    const yd: u8 = @truncate(vars.tiledetect_which_y_pos[0] -% 12 -% vars.link_y_coord.*);
    var yv: usize = if (yd >= 240) 0 else if (yd >= 96) 2 else if (yd >= 48) 1 else 0;

    xcoord +%= t.kPlayerOam_DrawOam_2X[yv];
    const ycoord: u8 = @truncate(vars.tiledetect_which_y_pos[0] -% 12 -% vars.BG2VOFS_copy2.* +% 29);
    const tab = if (vars.draw_water_ripples_or_grass.* != 0)
        &t.kShadow_oam_indexes_1
    else
        &t.kShadow_oam_indexes_0;
    var oam_pos: usize = (@as(usize, tab[@intCast(r4loc)]) + vars.sort_sprites_offset_into_oam_buffer.*) >> 2;

    yv *= 2;
    for (0..2) |_| {
        const td = t.kLinkShadows_Chardata[yv];
        if (td != 0xffff) {
            oamCharFlags(&oam_buf[oam_pos], (td & ~@as(u16, 0x3000)) | vars.oam_priority_value_2.*);
            oamXY(&oam_buf[oam_pos], @as(u16, xcoord) | @as(u16, ycoord) << 8);
        }
        bytewise_extended_oam[oam_pos] = 0;
        xcoord +%= 8;
        oam_pos += 1;
        yv += 1;
    }
}

pub export fn LinkOam_DrawFootObject(r4loc: c_int, oam_x_in: u8, oam_y_in: u8) callconv(.c) void { // 8daed1
    var oam_x = oam_x_in;
    var oam_y = oam_y_in;
    vars.primary_water_grass_timer.* = (vars.primary_water_grass_timer.* +% 1) & 0xf;
    if (vars.primary_water_grass_timer.* >= 9) {
        vars.primary_water_grass_timer.* = 0;
        vars.secondary_water_grass_timer.* = (vars.secondary_water_grass_timer.* +% 1) & 3;
        if (vars.secondary_water_grass_timer.* == 3)
            vars.secondary_water_grass_timer.* = 0;
    }

    const i: usize = (vars.link_direction_facing_mirror.* >> 1) +
        t.kShieldTypeToOffs[vars.link_shield_type.*];

    oam_x +%= i8at(t.kOffsToShadowGivenDir_X, i);
    oam_y +%= i8at(t.kOffsToShadowGivenDir_Y, i);

    const oam_pos: usize = (@as(usize, t.kShadow_oam_indexes_1[@intCast(r4loc)]) +
        vars.sort_sprites_offset_into_oam_buffer.*) >> 2;

    var yv: u8 = undefined;
    if (vars.draw_water_ripples_or_grass.* == 2) {
        yv = if (vars.link_animation_steps.* >= 3) vars.link_animation_steps.* - 3 else vars.link_animation_steps.*;
        @as([*]u8, @ptrCast(vars.overlay_index))[1] = yv *% 4;
        yv = 8 +% yv;
    } else {
        @as([*]u8, @ptrCast(vars.overlay_index))[1] = vars.secondary_water_grass_timer.* *% 4;
        yv = 5 +% vars.secondary_water_grass_timer.*;
    }

    const oam = oam_buf + oam_pos;

    if (yv >= 11) {
        // OOB read
        oamCharFlags(&oam[0], (0x00 & ~@as(u16, 0x3000)) | vars.oam_priority_value_2.*);
        oamCharFlags(&oam[1], 0xAE | vars.oam_priority_value_2.*);
    } else {
        oamCharFlags(&oam[0], (t.kLinkShadows_Chardata[@as(usize, yv) * 2 + 0] & ~@as(u16, 0x3000)) |
            vars.oam_priority_value_2.*);
        oamCharFlags(&oam[1], t.kLinkShadows_Chardata[@as(usize, yv) * 2 + 1] | vars.oam_priority_value_2.*);
    }

    oam[0].x = oam_x;
    oam[1].x = oam_x +% 8;

    oam[0].y = oam_y;
    oam[1].y = oam_y;

    std.mem.writeInt(u16, bytewise_extended_oam[oam_pos..][0..2], 0, .little);
}

pub export fn LinkOam_CalculateXOffsetRelativeLink(x: u8) callconv(.c) void { // 8dafc0
    const sx: i32 = @as(i8, @bitCast(x));
    const v = (@as(i32, vars.link_x_coord.*) + sx - @as(i32, vars.BG2HOFS_copy2.*));
    vars.bit9_of_xcoord.* = @intCast((@as(u32, @bitCast(v)) >> 8) & 1);
}

const testing = std.testing;

test "the generated tables are the sizes the C declared" {
    try testing.expectEqual(511, t.kSwordOamYOffs.len);
    try testing.expectEqual(511, t.kSwordOamXOffs.len);
    try testing.expectEqual(511, t.kPlayerOam_Main_SwordStuff_array1.len);
    try testing.expectEqual(511, t.kPlayerOam_ShieldStuff_array1.len);
    try testing.expectEqual(511, t.kPlayerOamSpriteLocs.len);
    try testing.expectEqual(511, t.kDrawSword_y.len);
    try testing.expectEqual(511, t.kDrawSword_x.len);
    try testing.expectEqual(511, t.kShieldStuff_x.len);
    try testing.expectEqual(511, t.kShieldStuff_y.len);
    try testing.expectEqual(511, t.kLinkDmaGraphicsIndices.len);
    try testing.expectEqual(303, t.kLinkSpriteBodys.len);
    try testing.expectEqual(228, t.kSwordTiledata.len);
    try testing.expectEqual(160, t.kPlayerOamOtherOffs.len);
    try testing.expectEqual(124, t.kPlayerOam_Spr1Bank.len);
    try testing.expectEqual(3, @sizeOf(t.LinkSpriteBody));
}

test "the most significant bit search matches the C" {
    // Bit 7 set returns 7 immediately.
    try testing.expectEqual(@as(u8, 7), FindMostSignificantBit(0x80));
    try testing.expectEqual(@as(u8, 7), FindMostSignificantBit(0xff));
    try testing.expectEqual(@as(u8, 6), FindMostSignificantBit(0x40));
    try testing.expectEqual(@as(u8, 6), FindMostSignificantBit(0x7f));
    try testing.expectEqual(@as(u8, 0), FindMostSignificantBit(1));
    try testing.expectEqual(@as(u8, 3), FindMostSignificantBit(0x08));
    // Zero runs the counter off the end and wraps to 255, as the C's
    // (uint8)i does with i == -1.
    try testing.expectEqual(@as(u8, 255), FindMostSignificantBit(0));
}

test "the backwards byte search matches the C helper" {
    const data = [_]u8{ 4, 16, 18, 21, 23, 24, 39 };
    try testing.expectEqual(0, findInByteArray(&data, 4));
    try testing.expectEqual(6, findInByteArray(&data, 39));
    try testing.expectEqual(3, findInByteArray(&data, 21));
    try testing.expectEqual(-1, findInByteArray(&data, 99));
    // On a duplicate the LAST index wins, because the scan runs backwards.
    const dup = [_]u8{ 7, 2, 7 };
    try testing.expectEqual(2, findInByteArray(&dup, 7));
}

test "the sword is invoked only with a real sword and a free hand" {
    @memset(g_ram[0..0x20000], 0);
    // A sword alone is not enough: with nothing in hand and B released the
    // guard block returns false before ever reaching the sword-type test.
    vars.link_sword_type.* = 2;
    try testing.expect(!PlayerOam_WantInvokeSword());

    // Holding B gets past that and falls through to the type test.
    vars.button_mask_b_y.* = 0x80;
    try testing.expect(PlayerOam_WantInvokeSword());

    // Holding something with bit 0x40 refuses outright.
    vars.link_item_in_hand.* = 0x40;
    try testing.expect(!PlayerOam_WantInvokeSword());
    vars.link_item_in_hand.* = 0;

    // A position mode bit forces a yes even with B released.
    vars.button_mask_b_y.* = 0;
    vars.link_position_mode.* = 1;
    try testing.expect(PlayerOam_WantInvokeSword());
    vars.link_position_mode.* = 0;

    // No sword: (0 + 1) & 0xfe == 0, and 0xff wraps to exactly the same.
    vars.button_mask_b_y.* = 0x80;
    vars.link_sword_type.* = 0;
    try testing.expect(!PlayerOam_WantInvokeSword());
    vars.link_sword_type.* = 0xff;
    try testing.expect(!PlayerOam_WantInvokeSword());

    // A blocking state bit skips the guard entirely, landing on the type test.
    vars.link_sword_type.* = 2;
    vars.link_state_bits.* = 1;
    try testing.expect(PlayerOam_WantInvokeSword());
}

test "the x offset helper extracts bit 9 of the screen position" {
    @memset(g_ram[0..0x20000], 0);
    vars.BG2HOFS_copy2.* = 0;
    vars.link_x_coord.* = 0;
    LinkOam_CalculateXOffsetRelativeLink(0);
    try testing.expectEqual(@as(u16, 0), vars.bit9_of_xcoord.*);

    // 0x100 sets bit 8, which is bit 0 after the >> 8.
    vars.link_x_coord.* = 0x100;
    LinkOam_CalculateXOffsetRelativeLink(0);
    try testing.expectEqual(@as(u16, 1), vars.bit9_of_xcoord.*);

    vars.link_x_coord.* = 0x200;
    LinkOam_CalculateXOffsetRelativeLink(0);
    try testing.expectEqual(@as(u16, 0), vars.bit9_of_xcoord.*);

    // The offset is signed, so it can pull the result back under 0x100.
    vars.link_x_coord.* = 0x102;
    LinkOam_CalculateXOffsetRelativeLink(0xfc); // -4
    try testing.expectEqual(@as(u16, 0), vars.bit9_of_xcoord.*);
}

test "weapon vram offsets report the sentinel and pick a dma slot" {
    @memset(g_ram[0..0x20000], 0);
    var sr: SwordResult = undefined;
    // Index 0 of the sword array is -1 (0xff), the "no sword drawn" sentinel.
    try testing.expectEqual(@as(i8, -1), t.kPlayerOam_Main_SwordStuff_array1[0]);
    try testing.expect(LinkOam_SetWeaponVRAMOffsets(0, &sr));
    try testing.expectEqual(@as(u8, 0xff), sr.r6);

    // Find a real entry and check it routes to link_dma_var3 when j < 29.
    var idx: usize = 0;
    while (idx < t.kPlayerOam_Main_SwordStuff_array1.len) : (idx += 1) {
        const j = t.kPlayerOam_Main_SwordStuff_array1[idx];
        if (j >= 0 and j < 29) break;
    }
    try testing.expect(idx < t.kPlayerOam_Main_SwordStuff_array1.len);
    try testing.expect(!LinkOam_SetWeaponVRAMOffsets(@intCast(idx), &sr));
    const j: usize = @intCast(t.kPlayerOam_Main_SwordStuff_array1[idx]);
    try testing.expectEqual(t.kPlayerOam_Main_SwordStuff_array3[j], vars.link_dma_var3.*);
    try testing.expectEqual(t.kPlayerOam_Main_SwordStuff_array2[j], sr.r12);
}

test "equipment vram offsets split on the shield index" {
    @memset(g_ram[0..0x20000], 0);
    var sr: SwordResult = undefined;
    // Entry 0 is a real shield index (1), below 8, so it uses link_dma_var4.
    try testing.expectEqual(@as(i8, 1), t.kPlayerOam_ShieldStuff_array1[0]);
    try testing.expect(!LinkOam_SetEquipmentVRAMOffsets(0, &sr));
    try testing.expectEqual(t.kPlayerOam_ShieldStuff_array2[1], vars.link_dma_var4.*);
    try testing.expectEqual(@as(u8, 2), sr.r12);
}
