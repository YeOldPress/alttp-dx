//! The one SDL/GL translation unit.
//!
//! Every @cImport block produces its own distinct set of types, so two modules
//! that each imported SDL separately could not pass an SDL_Window between them.
//! Everything that needs SDL or OpenGL imports `c` from here instead.
pub const c = @cImport({
    // translate-c cannot parse arm_neon.h, which SDL pulls in on ARM targets.
    // SDL2 spelled this guard SDL_DISABLE_ARM_NEON_H.
    @cDefine("SDL_DISABLE_NEON", "1");
    @cInclude("SDL3/SDL.h");
    @cInclude("third_party/gl_core/gl_core_3_1.h");
});
