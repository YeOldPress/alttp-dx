// glsl_shader.c used to instantiate stb_image here via STB_IMAGE_IMPLEMENTATION.
// That file is now Zig, so this translation unit carries the implementation
// instead. The defines must stay identical to the ones it used.
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_THREAD_LOCALS
#define STBI_ONLY_PNG
#define STBI_MAX_DIMENSIONS 4096
#define STBI_NO_FAILURE_STRINGS
#include "third_party/stb/stb_image.h"
