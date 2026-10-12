#version 450
// A composite video signal, made and taken apart again the way a TV did.
//
// The SNES sends color on a 3.58 MHz wave mixed into the brightness: one
// wave every 1.5 of its pixels, its phase turned half round every line and
// every frame. A TV gets brightness back by averaging over about one wave,
// and color by multiplying by the wave and averaging much wider. Neither
// comes out clean: fine detail in the brightness, a dither, looks like color
// to the TV, the rainbow; color it can't quite average out of the brightness
// shows as dots that crawl as the phase turns; and the color, averaged so
// wide, bleeds well past its edges. On top of that a TV sharpened what it
// had, leaving halos beside hard edges; the cable echoed, leaving a faint
// ghost to the right; and the signal carried a little noise.
//
// Drawn into a texture four samples to a SNES pixel across, the frame's
// height down, which the CRT shader (crt.frag) then reads as its picture.
//
// Compiled to SPIR-V and MSL by `zig build shaders`.

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;
layout(location = 0) out vec4 o_color;

layout(set = 2, binding = 0) uniform sampler2D u_texture;

layout(set = 3, binding = 0) uniform Params {
    // The frame: width and height in SNES pixels, and one over each.
    vec4 src;
    // The frame's parity, for the phase that turns each frame; how strongly
    // the decoding shows at all, 0 to 1; how far the color spreads, in SNES
    // pixels; how wide the brightness is averaged, in SNES pixels (1.5, one
    // wave, leaves no dots on a flat color; less lets them through).
    vec4 signal;
    // How much the TV sharpens, leaving halos; the ghost's strength; the
    // noise's; and the frame number, for the noise.
    vec4 extra;
};

const float kPi = 3.14159265;
// SNES pixels to one wave of the color carrier.
const float kWave = 1.5;

const mat3 kToYiq = mat3(
    0.299, 0.596, 0.211,
    0.587, -0.274, -0.523,
    0.114, -0.322, 0.312);
const mat3 kFromYiq = mat3(
    1.0, 1.0, 1.0,
    0.956, -0.272, -1.106,
    0.621, -0.647, 1.703);

vec3 yiqAt(float x, float y) {
    vec2 uv = (vec2(floor(x), y) + 0.5) * src.zw;
    return kToYiq * texture(u_texture, uv).rgb;
}

float phaseAt(float x, float turn) {
    return 2.0 * kPi * x / kWave + turn;
}

// The composite signal at x on this line.
float signalAt(float x, float y, float turn) {
    vec3 yiq = yiqAt(x, y);
    float p = phaseAt(x, turn);
    return yiq.x + yiq.y * cos(p) + yiq.z * sin(p);
}

// The brightness a TV gets back at x: the signal averaged over `width`.
float lumaAt(float x, float y, float turn, float width) {
    float sum = 0.0;
    float n = 0.0;
    for (int k = -8; k <= 8; k++) {
        float off = float(k) * 0.25;
        if (abs(off) > width * 0.5) continue;
        sum += signalAt(x + off, y, turn);
        n += 1.0;
    }
    return sum / max(n, 1.0);
}

float hash(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

void main() {
    float x = v_uv.x * src.x;
    float line = floor(v_uv.y * src.y);
    // Half a turn more each line and each frame.
    float turn = kPi * (line + signal.x);

    // Brightness, and the TV's sharpening: the difference from a wider
    // average, added back, which overshoots at edges.
    float luma = lumaAt(x, line, turn, signal.w);
    if (extra.x > 0.0) {
        float wide = lumaAt(x, line, turn, 4.0);
        luma += (luma - wide) * extra.x;
    }

    // Color: the signal times the wave, averaged wide, four samples a wave.
    vec2 chroma = vec2(0.0);
    float total = 0.0;
    float sigma = max(signal.z, 0.5);
    for (int k = -24; k <= 24; k++) {
        float off = float(k) * 0.375;
        float d = off / sigma;
        if (abs(d) > 3.0) continue;
        float w = exp(-0.5 * d * d);
        float s = signalAt(x + off, line, turn);
        float p = phaseAt(x + off, turn);
        chroma += 2.0 * s * vec2(cos(p), sin(p)) * w;
        total += w;
    }
    chroma /= max(total, 0.0001);

    // The cable's echo, a little to the right of what made it.
    if (extra.y > 0.0) luma = mix(luma, lumaAt(x - 3.0, line, turn, 1.5), extra.y);

    // The signal's noise, a fresh grain every frame.
    if (extra.z > 0.0) luma += (hash(vec3(x * 4.0, line, extra.w)) - 0.5) * extra.z;

    // As strong as asked: the decoded signal over the picture as it was.
    vec3 yiq = mix(yiqAt(x, line), vec3(luma, chroma), signal.y);
    o_color = vec4(clamp(kFromYiq * yiq, 0.0, 1.0), 1.0) * v_color;
}
