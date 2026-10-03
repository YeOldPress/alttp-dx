/* The one SDL/GL translation unit. build.zig runs translate-c over this file
 * and hands the result to sdl.zig as the "sdl_c" module. */

/* translate-c cannot parse arm_neon.h, which SDL pulls in on ARM targets.
 * SDL2 spelled this guard SDL_DISABLE_ARM_NEON_H. */
#define SDL_DISABLE_NEON 1
/* Optimized builds define _FORTIFY_SOURCE, which makes mingw's headers
 * inline checked wrappers that translate-c turns into unused locals. */
#undef _FORTIFY_SOURCE
#include <SDL3/SDL.h>
#include "third_party/gl_core/gl_core_3_1.h"
