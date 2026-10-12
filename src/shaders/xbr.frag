#version 450
// Pixel art drawn bigger with its diagonals smoothed, after the xBR idea.
//
// Each screen pixel falls in one SNES pixel, E, nearer one of its corners.
// Turned so that corner's the bottom right, the pixels round about are:
//
//        A1 B1 C1
//     A0 A  B  C  C4
//     D0 D  E  F  F4
//     G0 G  H  I  I4
//        G5 H5 I5
//
// Where the colors change less along the F to H diagonal than across it, an
// edge runs that way, and E's corner beyond the line from F to H is drawn
// in whichever of F and H is the nearer color, with a soft screen pixel at
// the line. Flat areas and straight edges stay as they were; staircases
// become slopes, and curves round.
//
// Compiled to SPIR-V and MSL by `zig build shaders`.

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;
layout(location = 0) out vec4 o_color;

layout(set = 2, binding = 0) uniform sampler2D u_texture;

layout(set = 3, binding = 0) uniform Params {
    // The frame: width and height in SNES pixels, and one over each.
    vec4 src;
    // Screen pixels to a SNES pixel; unused three times.
    vec4 out_scale;
};

vec3 at(vec2 p) {
    return texture(u_texture, (p + 0.5) * src.zw).rgb;
}

// How different two colors look: in brightness most, as xBR weighs it.
float dist(vec3 a, vec3 b) {
    const mat3 kToYuv = mat3(
        0.299, -0.169, 0.499,
        0.587, -0.331, -0.418,
        0.114, 0.499, -0.0813);
    vec3 d = abs(kToYuv * (a - b));
    return dot(d, vec3(48.0, 7.0, 6.0));
}

void main() {
    vec2 pos = v_uv * src.xy;
    vec2 e = floor(pos);
    vec2 f = pos - e - 0.5;
    // The corner this screen pixel's nearer, as a direction, and where it
    // sits within that quarter, 0 at E's middle to 0.5 at its corner.
    vec2 dir = vec2(f.x < 0.0 ? -1.0 : 1.0, f.y < 0.0 ? -1.0 : 1.0);
    vec2 u = f * dir;

    vec2 dx = vec2(dir.x, 0.0);
    vec2 dy = vec2(0.0, dir.y);
    vec3 E = at(e);
    vec3 F = at(e + dx);
    vec3 H = at(e + dy);
    vec3 I = at(e + dx + dy);
    vec3 B = at(e - dy);
    vec3 C = at(e + dx - dy);
    vec3 D = at(e - dx);
    vec3 G = at(e - dx + dy);
    vec3 F4 = at(e + 2.0 * dx);
    vec3 I4 = at(e + 2.0 * dx + dy);
    vec3 H5 = at(e + 2.0 * dy);
    vec3 I5 = at(e + dx + 2.0 * dy);

    // Along the F to H diagonal against across it.
    float along = dist(E, C) + dist(E, G) + dist(I, F4) + dist(I, H5) + 4.0 * dist(H, F);
    float across = dist(H, I5) + dist(H, D) + dist(F, I4) + dist(F, B) + 4.0 * dist(E, I);
    bool edge = along < across && dist(E, F) > 0.0 && dist(E, H) > 0.0;

    vec3 col = E;
    if (edge) {
        vec3 fill = dist(E, F) <= dist(E, H) ? F : H;
        // Beyond the line from F's side to H's, softly, over a screen pixel.
        float soft = 0.5 / max(out_scale.x, 1.0);
        float k = smoothstep(0.5 - soft, 0.5 + soft, u.x + u.y);
        col = mix(E, fill, k);
    }
    o_color = vec4(col, 1.0) * v_color;
}
