//! The sound chip on its own, for the tools' music player, which has no use
//! for the rest of the console. Stands in for the whole module there, so the
//! sound driver's `@import("snes").dsp` finds the same file either way.
pub const dsp = @import("dsp.zig");
