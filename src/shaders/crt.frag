#version 450
// The CRT looks, done properly: one fragment shader for SDL's GPU renderer.
//
// It draws the SNES-sized frame at screen size, a screen pixel at a time:
// across, a sharp step between SNES pixels, or a composite cable's signal,
// brightness and color blurred apart; down, each SNES line a beam of light,
// the two nearest ones as Gaussians in linear light, narrow when dark and
// wide when bright, colour by colour, so lines show deep in shadow and all
// but vanish on white; the red and blue beams a fraction off the green; then
// a TV's phosphors, the darker corners, and back to the screen's gamma.
//
// Compiled to SPIR-V and MSL by `zig build shaders`; the results are
// committed, so building the game needs neither tool.

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;
layout(location = 0) out vec4 o_color;

layout(set = 2, binding = 0) uniform sampler2D u_texture;

layout(set = 3, binding = 0) uniform Params {
    // The frame: width and height in SNES pixels, and one over each.
    vec4 src;
    // The target: width and height in screen pixels; the mask, 0 none,
    // 1 aperture grille, 2 slot mask, 3 shadow mask, 4 LCD grid; and how
    // much light its dark parts let through.
    vec4 dst;
    // The beam's width, as a share of the line spacing, at black and at
    // full brightness (0 for none: the pixels flat, as an LCD's); the gain;
    // and how much darker the corners are.
    vec4 beam;
    // The composite signal: how much brightness blurs into its neighbors,
    // how far color spreads, in SNES pixels (0 for an RGB cable); how far
    // the red and blue beams sit off the green, in SNES pixels; and for HDR,
    // the display's white in linear light, the output then linear and free
    // to go past it (0 for the usual, gamma-encoded and up to white).
    vec4 signal;
};

vec3 fetch(float x, float y) {
    vec2 uv = (vec2(x, y) + 0.5) * src.zw;
    return texture(u_texture, uv).rgb;
}

const mat3 kToYiq = mat3(
    0.299, 0.596, 0.211,
    0.587, -0.274, -0.523,
    0.114, -0.322, 0.312);
const mat3 kFromYiq = mat3(
    1.0, 1.0, 1.0,
    0.956, -0.272, -1.106,
    0.621, -0.647, 1.703);

// The color along line y at x, in SNES pixels, as the cable carries it.
vec3 lineColor(float x, float y) {
    float px = x - 0.5;
    float x0 = floor(px);
    float f = px - x0;
    // A sharp step from one pixel to the next, with a sliver of blend.
    float k = clamp((f - 0.5) * 4.0 + 0.5, 0.0, 1.0);
    vec3 sharp = mix(fetch(x0, y), fetch(x0 + 1.0, y), k);
    if (signal.x <= 0.0 && signal.y <= 0.0) return sharp;

    // Composite: brightness from the pixel and its two neighbors, color
    // from a wider spread around it.
    float n = floor(x);
    vec3 yiq = kToYiq * sharp;
    float l = signal.x;
    float luma = (kToYiq * fetch(n - 1.0, y)).x * (l * 0.5)
         + (kToYiq * fetch(n, y)).x * (1.0 - l)
         + (kToYiq * fetch(n + 1.0, y)).x * (l * 0.5);
    vec2 chroma = yiq.yz;
    if (signal.y > 0.0) {
        vec2 sum = vec2(0.0);
        float total = 0.0;
        for (int i = -4; i <= 4; i++) {
            float d = float(i) / signal.y;
            float w = exp(-0.5 * d * d);
            sum += (kToYiq * fetch(n + float(i), y)).yz * w;
            total += w;
        }
        chroma = sum / total;
    }
    return kFromYiq * vec3(mix(yiq.x, luma, step(0.0001, l)), chroma);
}

vec3 toLinear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.4)); }
vec3 toGamma(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }

// A beam's share of its light at `d` line spacings out, width `w`: a
// Gaussian that keeps the same light whatever its width, as a beam does.
vec3 spot(float d, vec3 w) {
    vec3 t = d / w;
    return exp(-0.5 * t * t) / (w * 2.5066283);
}

// The light at x along the screen, at line position y (SNES pixels).
vec3 beamAt(float x, float y) {
    float py = y - 0.5;
    float y0 = floor(py);
    float t = py - y0;
    vec3 c0 = toLinear(lineColor(x, y0));
    if (beam.y <= 0.0) {
        // No beam: the line's color, flat, all the way down.
        return toLinear(lineColor(x, floor(y)));
    }
    vec3 c1 = toLinear(lineColor(x, y0 + 1.0));
    vec3 w0 = mix(vec3(beam.x), vec3(beam.y), sqrt(c0));
    vec3 w1 = mix(vec3(beam.x), vec3(beam.y), sqrt(c1));
    return c0 * spot(t, w0) + c1 * spot(1.0 - t, w1);
}

vec3 mask(vec2 op) {
    int type = int(dst.z + 0.5);
    float dark = dst.w;
    int x = int(op.x);
    int y = int(op.y);
    float scale = dst.y * src.w;
    if (type == 1) {
        int c = x % 3;
        return mix(vec3(dark), vec3(1.0), vec3(c == 0, c == 1, c == 2));
    }
    if (type == 2) {
        int c = x % 3;
        vec3 m = mix(vec3(dark), vec3(1.0), vec3(c == 0, c == 1, c == 2));
        // Bricks: every other triad's break halfway down a line.
        int h = max(int(scale + 0.5), 2);
        int shift = ((x / 3) % 2) * (h / 2);
        if ((y + shift) % h == h - 1) m *= dark;
        return m;
    }
    if (type == 3) {
        // Dots, each row of triads a step along from the last.
        int c = (x + (y % 2) * 2) % 3;
        return mix(vec3(dark), vec3(1.0), vec3(c == 0, c == 1, c == 2));
    }
    if (type == 4) {
        int s = max(int(scale + 0.5), 2);
        bool gap = (x % s) == s - 1 || (y % s) == s - 1;
        return vec3(gap ? dark : 1.0);
    }
    return vec3(1.0);
}

void main() {
    vec2 pos = v_uv * src.xy;
    vec3 col;
    if (signal.z != 0.0) {
        col.r = beamAt(pos.x + signal.z, pos.y).r;
        col.g = beamAt(pos.x, pos.y).g;
        col.b = beamAt(pos.x - signal.z, pos.y).b;
    } else {
        col = beamAt(pos.x, pos.y);
    }

    col *= mask(v_uv * dst.xy);
    col *= beam.z;

    vec2 d = v_uv * 2.0 - 1.0;
    col *= max(1.0 - beam.w * dot(d, d) * 0.5, 0.0);

    if (signal.w > 0.0) {
        o_color = vec4(col * signal.w, 1.0) * v_color;
    } else {
        o_color = vec4(toGamma(col), 1.0) * v_color;
    }
}
