//! Stand-ins for symbols that the real build gets from the C side. Only linked
//! into the test binary, which has no C objects at all.
//!
//! None of these should ever run: the tests exercise the ported logic directly
//! rather than driving a whole emulator, so a call here means a test reached
//! further than intended. They panic rather than return a plausible value.
//!
//! As each C file is ported its entry disappears from here, because the real
//! Zig implementation then provides the symbol.
const std = @import("std");

fn stub(comptime name: []const u8) noreturn {
    std.debug.panic("{s} is a C function that is not linked into the test binary", .{name});
}

// dungeon.c
export fn Module_PreDungeon() void {
    stub("Module_PreDungeon");
}
export fn Module07_Dungeon() void {
    stub("Module07_Dungeon");
}
export fn Module11_DungeonFallingEntrance() void {
    stub("Module11_DungeonFallingEntrance");
}
export fn Dungeon_ResetTorchBackgroundAndPlayerInner() void {
    stub("Dungeon_ResetTorchBackgroundAndPlayerInner");
}
export fn Dungeon_FlagRoomData_Quadrants() void {
    stub("Dungeon_FlagRoomData_Quadrants");
}
export fn SaveDungeonKeys() void {
    stub("SaveDungeonKeys");
}
export fn HandleItemTileAction_Dungeon(x: u16, y: u16) u8 {
    _ = .{ x, y };
    stub("HandleItemTileAction_Dungeon");
}

// misc.c
export fn LoadOWMusicIfNeeded() void {
    stub("LoadOWMusicIfNeeded");
}

// ancilla.c
export fn Ancilla_AddAncilla(a: u8, y: u8) c_int {
    _ = .{ a, y };
    stub("Ancilla_AddAncilla");
}
export fn Ancilla_TerminateSelectInteractives(y: u8) u8 {
    _ = y;
    stub("Ancilla_TerminateSelectInteractives");
}
export fn Ancilla_SetXY(k: c_int, x: u16, y: u16) void {
    _ = .{ k, x, y };
    stub("Ancilla_SetXY");
}
export fn AncillaAdd_VictorySpin() void {
    stub("AncillaAdd_VictorySpin");
}
export fn AncillaAdd_CapePoof(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_CapePoof");
}
export fn AncillaAdd_MSCutscene(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_MSCutscene");
}

// dungeon.c
export fn Dungeon_LoadEntrance() void {
    stub("Dungeon_LoadEntrance");
}
export fn Dungeon_LoadAndDrawRoom() void {
    stub("Dungeon_LoadAndDrawRoom");
}
export fn Dungeon_ResetTorchBackgroundAndPlayer() void {
    stub("Dungeon_ResetTorchBackgroundAndPlayer");
}

// sprite_main.c
export fn Guard_HandleAllAnimation(k: c_int) void {
    _ = k;
    stub("Guard_HandleAllAnimation");
}

// ancilla.c
export fn Ancilla_GetX(k: c_int) u16 {
    _ = k;
    stub("Ancilla_GetX");
}
export fn Ancilla_GetY(k: c_int) u16 {
    _ = k;
    stub("Ancilla_GetY");
}
const ProjectSpeedRet = extern struct { x: u8, y: u8, xdiff: u8, ydiff: u8 };
export fn Ancilla_ProjectSpeedTowardsPlayer(k: c_int, vel: u8) ProjectSpeedRet {
    _ = .{ k, vel };
    stub("Ancilla_ProjectSpeedTowardsPlayer");
}
export fn Ancilla_MoveX(k: c_int) void {
    _ = k;
    stub("Ancilla_MoveX");
}
export fn Ancilla_MoveY(k: c_int) void {
    _ = k;
    stub("Ancilla_MoveY");
}
export fn AncillaAdd_SuperBombExplosion(a: u8, y: u8) c_int {
    _ = .{ a, y };
    stub("AncillaAdd_SuperBombExplosion");
}

// sprite_main.c / misc.c
export const kSinusLookupTable: [256]u16 = @splat(0);
export fn Sprite_TransmuteToBomb(k: c_int) void {
    _ = k;
    stub("Sprite_TransmuteToBomb");
}
export fn GarnishAlloc() c_int {
    stub("GarnishAlloc");
}
export fn OldMan_RevertToSprite(k: c_int) void {
    _ = k;
    stub("OldMan_RevertToSprite");
}

// Referenced by messaging.zig. ancilla.c.
export fn AddBirdTravelSomething(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AddBirdTravelSomething");
}
export fn ConfigureRevivalAncillae() void {
    stub("ConfigureRevivalAncillae");
}
export fn GameOverText_Draw() void {
    stub("GameOverText_Draw");
}
export fn RevivalFairy_Main() void {
    stub("RevivalFairy_Main");
}

// dungeon.c
export fn Dungeon_ApproachFixedColor_variable(a: u8) void {
    _ = a;
    stub("Dungeon_ApproachFixedColor_variable");
}
export fn Dungeon_PrepareNextRoomQuadrantUpload() void {
    stub("Dungeon_PrepareNextRoomQuadrantUpload");
}
export fn Dungeon_PushBlock_Handler() void {
    stub("Dungeon_PushBlock_Handler");
}
export fn OrientLampLightCone() void {
    stub("OrientLampLightCone");
}
export fn WaterFlood_BuildOneQuadrantForVRAM() void {
    stub("WaterFlood_BuildOneQuadrantForVRAM");
}

// dungeon.c
const DungPalInfo = extern struct { pal0: u8, pal1: u8, pal2: u8, pal3: u8 };
export fn Dungeon_HandleLayerEffect() void {
    stub("Dungeon_HandleLayerEffect");
}
export fn ResetTransitionPropsAndAdvance_ResetInterface() void {
    stub("ResetTransitionPropsAndAdvance_ResetInterface");
}
export fn GetDungPalInfo(idx: c_int) *const DungPalInfo {
    _ = idx;
    stub("GetDungPalInfo");
}
export const kDungAnimatedTiles: [24]u8 = .{
    0x5d, 0x5d, 0x5d, 0x5d, 0x5d, 0x5d, 0x5d, 0x5f, 0x5d, 0x5f, 0x5f, 0x5e,
    0x5f, 0x5e, 0x5e, 0x5d, 0x5d, 0x5e, 0x5d, 0x5d, 0x5d, 0x5d, 0x5d, 0x5d,
};

// ancilla.c
export fn CallForDuckIndoors() void {
    stub("CallForDuckIndoors");
}

// sprite_main.c
export fn SpriteActive_Main(k: c_int) void {
    _ = k;
    stub("SpriteActive_Main");
}
export fn Sprite_SpawnBatCrashCutscene() void {
    stub("Sprite_SpawnBatCrashCutscene");
}

// Referenced by overworld.zig. ancilla.c.
export fn AncillaAdd_BushPoof(x: u16, y: u16) void {
    _ = .{ x, y };
    stub("AncillaAdd_BushPoof");
}

// Referenced by overworld.zig. dungeon.c.
export fn Dungeon_PlayBlipAndCacheQuadrantVisits() void {
    stub("Dungeon_PlayBlipAndCacheQuadrantVisits");
}

// Referenced by sprite.zig. ancilla.c.
export fn AncillaAdd_FallingPrize(a: u8, item_idx: u8, yv: u8) c_int {
    _ = .{ a, item_idx, yv };
    stub("AncillaAdd_FallingPrize");
}
export fn Ancilla_Main() void {
    stub("Ancilla_Main");
}

// Referenced by sprite.zig. dungeon.c.
export fn Dungeon_UpdateTileMapWithCommonTile(x: c_int, y: c_int, v: u8) void {
    _ = .{ x, y, v };
    stub("Dungeon_UpdateTileMapWithCommonTile");
}
export fn PrepareDungeonExitFromBossFight() void {
    stub("PrepareDungeonExitFromBossFight");
}

// Referenced by sprite.zig. sprite_main.c.
export fn Flame_Draw(k: c_int) void {
    _ = k;
    stub("Flame_Draw");
}
export fn GarnishAllocLimit(k: c_int) c_int {
    _ = k;
    stub("GarnishAllocLimit");
}
export fn Garnish_SetX(k: c_int, x: u16) void {
    _ = .{ k, x };
    stub("Garnish_SetX");
}
export fn Garnish_SetY(k: c_int, y: u16) void {
    _ = .{ k, y };
    stub("Garnish_SetY");
}
export fn SpriteDraw_WaterRipple(k: c_int) void {
    _ = k;
    stub("SpriteDraw_WaterRipple");
}
export fn SpriteModule_Initialize(k: c_int) void {
    _ = k;
    stub("SpriteModule_Initialize");
}
export fn SpritePrep_BigKey_load_graphics(k: c_int) void {
    _ = k;
    stub("SpritePrep_BigKey_load_graphics");
}
export fn SpritePrep_KeySetItemDrop(k: c_int) void {
    _ = k;
    stub("SpritePrep_KeySetItemDrop");
}
export fn SpritePrep_SmallKey(k: c_int) void {
    _ = k;
    stub("SpritePrep_SmallKey");
}
export fn Sprite_SpawnPoofGarnish(j: c_int) void {
    _ = j;
    stub("Sprite_SpawnPoofGarnish");
}
export fn ThrowableScenery_ScatterIntoDebris(k: c_int) void {
    _ = k;
    stub("ThrowableScenery_ScatterIntoDebris");
}
// Tables that live in sprite_main.c.
export const kThrowableScenery_Flags: [9]u8 = @splat(0);
export const kWishPond2_OamFlags: [76]u8 = @splat(0);

// Called by the newly ported player.zig, which now lives in the test binary.
// These are defined in ancilla.c, dungeon.c and sprite_main.c, none of which the
// test binary compiles. Signatures mirror player.zig's own extern declarations.
const Point16U = extern struct { x: u16, y: u16 };
const CheckPlayerCollOut = extern struct { r4: u16, r6: u16, r8: u16, r10: u16 };

export fn AddSwordBeam(y: u8) void {
    _ = y;
    stub("AddSwordBeam");
}
export fn AdjustQuadrantAndCamera_down() void {
    stub("AdjustQuadrantAndCamera_down");
}
export fn AdjustQuadrantAndCamera_left() void {
    stub("AdjustQuadrantAndCamera_left");
}
export fn AdjustQuadrantAndCamera_right() void {
    stub("AdjustQuadrantAndCamera_right");
}
export fn AdjustQuadrantAndCamera_up() void {
    stub("AdjustQuadrantAndCamera_up");
}
export fn AncillaAdd_Arrow(a: u8, ax: u8, ay: u8, xcoord: u16, ycoord: u16) c_int {
    _ = .{ a, ax, ay, xcoord, ycoord };
    stub("AncillaAdd_Arrow");
}
export fn AncillaAdd_Blanket(a: u8) void {
    _ = a;
    stub("AncillaAdd_Blanket");
}
export fn AncillaAdd_Bomb(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_Bomb");
}
export fn AncillaAdd_BombosSpell(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_BombosSpell");
}
export fn AncillaAdd_Boomerang(a: u8, y: u8) u8 {
    _ = .{ a, y };
    stub("AncillaAdd_Boomerang");
}
export fn AncillaAdd_BunnyPoof(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_BunnyPoof");
}
export fn AncillaAdd_ChargedSpinAttackSparkle() void {
    stub("AncillaAdd_ChargedSpinAttackSparkle");
}
export fn AncillaAdd_DashDust(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_DashDust");
}
export fn AncillaAdd_DashDust_charging(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_DashDust_charging");
}
export fn AncillaAdd_DashTremor(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_DashTremor");
}
export fn AncillaAdd_Duck_take_off(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_Duck_take_off");
}
export fn AncillaAdd_DwarfPoof(ain: u8, yin: u8) void {
    _ = .{ ain, yin };
    stub("AncillaAdd_DwarfPoof");
}
export fn AncillaAdd_EtherSpell(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_EtherSpell");
}
export fn AncillaAdd_ExplodingWeatherVane(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_ExplodingWeatherVane");
}
export fn AncillaAdd_FireRodShot(stype: u8, y: u8) void {
    _ = .{ stype, y };
    stub("AncillaAdd_FireRodShot");
}
export fn AncillaAdd_GraveStone(ain: u8, yin: u8) void {
    _ = .{ ain, yin };
    stub("AncillaAdd_GraveStone");
}
export fn AncillaAdd_IceRodShot(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_IceRodShot");
}
export fn AncillaAdd_LampFlame(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_LampFlame");
}
export fn AncillaAdd_MagicPowder(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_MagicPowder");
}
export fn AncillaAdd_QuakeSpell(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_QuakeSpell");
}
export fn AncillaAdd_Snoring(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_Snoring");
}
export fn AncillaAdd_SomariaBlock(stype: u8, y: u8) c_int {
    _ = .{ stype, y };
    stub("AncillaAdd_SomariaBlock");
}
export fn AncillaAdd_SpinAttackInitSpark(a: u8, x: u8, y: u8) void {
    _ = .{ a, x, y };
    stub("AncillaAdd_SpinAttackInitSpark");
}
export fn AncillaAdd_Splash(a: u8, y: u8) bool {
    _ = .{ a, y };
    stub("AncillaAdd_Splash");
}
export fn AncillaAdd_SwordSwingSparkle(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_SwordSwingSparkle");
}
export fn AncillaAdd_WallTapSpark(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("AncillaAdd_WallTapSpark");
}
export fn AncillaSpawn_SwordChargeSparkle() void {
    stub("AncillaSpawn_SwordChargeSparkle");
}
export fn Ancilla_AddHitStars(a: u8, y: u8) void {
    _ = .{ a, y };
    stub("Ancilla_AddHitStars");
}
export fn Ancilla_CheckLinkCollision(k: c_int, j: c_int, out: *CheckPlayerCollOut) bool {
    _ = .{ k, j, out };
    stub("Ancilla_CheckLinkCollision");
}
export fn Ancilla_CheckTileCollision_Class2(k: c_int) bool {
    _ = k;
    stub("Ancilla_CheckTileCollision_Class2");
}
export fn Ancilla_MoveZ(k: c_int) void {
    _ = k;
    stub("Ancilla_MoveZ");
}
export fn Ancilla_Sfx2_Pan(k: c_int, v: u8) void {
    _ = .{ k, v };
    stub("Ancilla_Sfx2_Pan");
}
export fn Ancilla_Sfx3_Pan(k: c_int, v: u8) void {
    _ = .{ k, v };
    stub("Ancilla_Sfx3_Pan");
}
export fn Dung_StartInterRoomTrans_Left_Plus() void {
    stub("Dung_StartInterRoomTrans_Left_Plus");
}
export fn Dungeon_CheckForAndIDLiftableTile() u16 {
    stub("Dungeon_CheckForAndIDLiftableTile");
}
export fn Dungeon_DeleteRupeeTile(x: u16, y: u16) void {
    _ = .{ x, y };
    stub("Dungeon_DeleteRupeeTile");
}
export fn Dungeon_GetTeleMsg(room: c_int) u16 {
    _ = room;
    stub("Dungeon_GetTeleMsg");
}
export fn Dungeon_IsPitThatHurtsPlayer() bool {
    stub("Dungeon_IsPitThatHurtsPlayer");
}
export fn Dungeon_LiftAndReplaceLiftable(pt: *Point16U) u8 {
    _ = pt;
    stub("Dungeon_LiftAndReplaceLiftable");
}
export fn Dungeon_StartInterRoomTrans_Up() void {
    stub("Dungeon_StartInterRoomTrans_Up");
}
export fn HandleEdgeTransitionMovementEast_RightBy8() void {
    stub("HandleEdgeTransitionMovementEast_RightBy8");
}
export fn HandleEdgeTransitionMovementSouth_DownBy16() void {
    stub("HandleEdgeTransitionMovementSouth_DownBy16");
}
export fn Mirror_SaveRoomData() void {
    stub("Mirror_SaveRoomData");
}
export fn OpenChestForItem(tile: u8, chest_position: *c_int) u8 {
    _ = .{ tile, chest_position };
    stub("OpenChestForItem");
}
export fn ReleaseBeeFromBottle(x_value: c_int) c_int {
    _ = x_value;
    stub("ReleaseBeeFromBottle");
}
export fn SetAndSaveVisitedQuadrantFlags() void {
    stub("SetAndSaveVisitedQuadrantFlags");
}
export fn Sprite_SpawnSmallSplash(k: c_int) c_int {
    _ = k;
    stub("Sprite_SpawnSmallSplash");
}

// third_party/opus, which the test binary does not compile.
export fn opus_decoder_create(Fs: i32, channels: c_int, err: ?*c_int) ?*anyopaque {
    _ = .{ Fs, channels, err };
    stub("opus_decoder_create");
}
export fn opus_decoder_destroy(st: ?*anyopaque) void {
    _ = st;
    stub("opus_decoder_destroy");
}
export fn opus_decode(
    st: *anyopaque,
    data: [*]const u8,
    len: i32,
    pcm: [*]i16,
    frame_size: c_int,
    decode_fec: c_int,
) c_int {
    _ = .{ st, data, len, pcm, frame_size, decode_fec };
    stub("opus_decode");
}
export fn opus_decoder_ctl(st: *anyopaque, request: c_int) c_int {
    _ = .{ st, request };
    stub("opus_decoder_ctl");
}

// third_party/stb, whose implementation unit the test binary does not compile.
export fn stbi_load(
    filename: [*:0]const u8,
    x: *c_int,
    y: *c_int,
    comp: *c_int,
    req_comp: c_int,
) ?[*]u8 {
    _ = .{ filename, x, y, comp, req_comp };
    stub("stbi_load");
}
