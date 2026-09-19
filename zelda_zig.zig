//! Root of the Zig half of the port. Every module that has been translated from
//! C is referenced here so that its `export` symbols get linked into the
//! executable, replacing the C file of the same name.
//!
//! This lives at the repo root so that both src/ and snes/ fall inside the
//! module path.
const builtin = @import("builtin");

comptime {
    _ = @import("src/util.zig");
    _ = @import("src/config.zig");
    _ = @import("snes/input.zig");
    _ = @import("snes/cart.zig");
    _ = @import("snes/dma.zig");
    _ = @import("snes/apu.zig");
    _ = @import("snes/snes_other.zig");
    _ = @import("snes/dsp.zig");
    _ = @import("snes/cpu_types.zig");
    _ = @import("snes/ppu_types.zig");
    _ = @import("snes/snes.zig");
    _ = @import("snes/spc.zig");
    _ = @import("snes/cpu.zig");
    _ = @import("snes/ppu.zig");
    _ = @import("src/variables.zig");
    _ = @import("src/poly.zig");
    _ = @import("src/tile_detect.zig");
    _ = @import("src/overlord.zig");
    _ = @import("src/zelda_rtl_types.zig");
    _ = @import("src/nmi.zig");
    _ = @import("src/features.zig");
    _ = @import("src/tagalong.zig");
    _ = @import("snes/tracing.zig");
    _ = @import("src/select_file.zig");
    _ = @import("src/opengl.zig");
    _ = @import("src/audio.zig");
    _ = @import("src/zelda_cpu_infra.zig");
    _ = @import("src/glsl_shader.zig");
    _ = @import("src/main.zig");
    _ = @import("src/zelda_rtl.zig");
    _ = @import("src/misc.zig");
    _ = @import("src/attract.zig");
    _ = @import("src/player_oam.zig");
    _ = @import("src/spc_player.zig");
    _ = @import("src/hud.zig");
    _ = @import("src/load_gfx.zig");
    _ = @import("src/ending.zig");
    _ = @import("src/messaging.zig");
    _ = @import("src/overworld.zig");
    _ = @import("src/sprite.zig");
    _ = @import("src/player.zig");
    _ = @import("src/ancilla.zig");
    _ = @import("src/dungeon.zig");

    _ = @import("src/sprite_main.zig");

    if (builtin.is_test) {
        if (@import("build_options").ancilla_parity) _ = @import("tests/ancilla_parity.zig");
    }
}
