//! The one SDL/GL translation unit.
//!
//! Every translate-c run produces its own distinct set of types, so two modules
//! that each imported SDL separately could not pass an SDL_Window between them.
//! Everything that needs SDL or OpenGL imports `c` from here instead. The
//! headers it covers live in sdl_c.h.
pub const c = @import("sdl_c");
