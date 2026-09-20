//! Root of the SNES emulation module.
//!
//! The game code reaches this through `@import("snes")` rather than by
//! reaching across the directory with a relative path. That keeps every
//! import inside its own module, which is what the compiler and the editor
//! tooling both expect, and it makes the dependency one-way by construction:
//! nothing under snes/ can import the game.
//!
//! Referencing every file here also keeps their `export` symbols linked and
//! their tests discovered, which is what zelda_zig.zig used to do by listing
//! them one by one.

pub const apu = @import("apu.zig");
pub const cart = @import("cart.zig");
pub const cpu = @import("cpu.zig");
pub const cpu_types = @import("cpu_types.zig");
pub const dma = @import("dma.zig");
pub const dsp = @import("dsp.zig");
pub const input = @import("input.zig");
pub const ppu = @import("ppu.zig");
pub const ppu_types = @import("ppu_types.zig");
pub const snes = @import("snes.zig");
pub const snes_other = @import("snes_other.zig");
pub const snes_types = @import("snes_types.zig");
pub const spc = @import("spc.zig");
pub const tracing = @import("tracing.zig");
pub const tracing_tables = @import("tracing_tables.zig");

comptime {
    _ = apu;
    _ = cart;
    _ = cpu;
    _ = cpu_types;
    _ = dma;
    _ = dsp;
    _ = input;
    _ = ppu;
    _ = ppu_types;
    _ = snes;
    _ = snes_other;
    _ = snes_types;
    _ = spc;
    _ = tracing;
    _ = tracing_tables;
}

test {
    // Pull every file's tests into a run rooted here.
    _ = @import("std").testing.refAllDecls(@This());
}
