#version 450
// Dynamic lighting, second pass: the frame drawn at the screen's size with
// the light laid over it.
//
// Pixels the room's darkness covers (red in the mask) are darkened the way
// the SNES does it, a fixed amount taken off each channel, and then lit
// again from the light map (light_map.frag), read with smooth filtering so
// the light's edges are soft however big the pixels are. Close to a flame,
// where the light is more than the art's own, surfaces brighten a little
// past it. Every light glows, a soft halo over whatever's near it, except
// the HUD (0 in the mask). A touch of noise keeps the gradients from
// banding.
//
// Compiled to SPIR-V and MSL by `zig build shaders`; the results are
// committed, so building the game needs neither tool.

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;
layout(location = 0) out vec4 o_color;

layout(set = 2, binding = 0) uniform sampler2D u_frame;
layout(set = 2, binding = 1) uniform sampler2D u_mask;
layout(set = 2, binding = 2) uniform sampler2D u_light;

const int kMaxLights = 24;

layout(set = 3, binding = 0) uniform Params {
    // The frame and mask textures' width and height in SNES pixels, and one
    // over each.
    vec4 tex;
    // The light map's width and height, and one over each.
    vec4 map;
    // What the darkness takes off red, green and blue (0 to 1), and the
    // number of lights.
    vec4 dark;
    // How far surfaces may brighten past the art near a flame, how strong
    // the glows are, the frame number for the noise, and the output's
    // pixels to an SNES pixel.
    vec4 look;
    // As in light_map.frag.
    vec4 lights[kMaxLights * 2];
};

float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233)) + look.z * 0.618) * 43758.5453);
}

void main() {
    vec2 p = v_uv * tex.xy;
    vec3 c = texture(u_frame, v_uv).rgb;
    float m = texture(u_mask, v_uv).r * 255.0;

    if (m > 0.5 && m < 1.5) {
        // The light map's texels sit on SNES pixel centers.
        vec3 light = texture(u_light, p * map.zw).rgb;
        vec3 base = max(c - dark.rgb, vec3(0.0));
        vec3 lit = base + c * min(light, vec3(1.0));
        vec3 over = c * max(light - vec3(1.0), vec3(0.0)) * look.x;
        c = min(lit, c) + over;
    }

    if (m > 0.5 && look.y > 0.0) {
        vec3 glow = vec3(0.0);
        int n = int(dark.w);
        for (int i = 0; i < kMaxLights; i++) {
            if (i >= n) break;
            vec4 a = lights[i * 2];
            vec4 b = lights[i * 2 + 1];
            if (a.w <= 0.0 || b.w <= 0.0) continue;
            vec2 d = p - a.xy;
            float g = exp(-dot(d, d) / (2.0 * a.w * a.w));
            glow += normalize(b.rgb + 0.001) * b.w * g;
        }
        // Screen-blended, so it lifts the dark and never blows out white.
        glow *= look.y;
        c = c + glow * (1.0 - c);
    }

    c += (noise(floor(gl_FragCoord.xy)) - 0.5) / 255.0;
    o_color = vec4(clamp(c, 0.0, 1.0), 1.0);
}
