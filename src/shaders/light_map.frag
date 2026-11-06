#version 450
// Dynamic lighting, first pass: the light falling on each SNES pixel of a
// dark room, drawn into a floating-point texture the size of the frame.
//
// It's drawn from the light mask (lighting.zig): red is the pixels the
// room's darkness covers, green the walls and anything else solid that
// light can't pass. Each light is a soft disc that eases out to nothing at
// its radius; walls between a pixel and a light shade it. The second pass
// (light_apply.frag) reads this back smoothly at the screen's size.
//
// Compiled to SPIR-V and MSL by `zig build shaders`; the results are
// committed, so building the game needs neither tool.

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;
layout(location = 0) out vec4 o_color;

layout(set = 2, binding = 0) uniform sampler2D u_mask;

const int kMaxLights = 24;

layout(set = 3, binding = 0) uniform Params {
    // The mask texture's width and height in SNES pixels, and one over each.
    vec4 tex;
    // How dark the shadows behind walls are (0 none, 1 all the way), and
    // the number of lights.
    vec4 look;
    // Each light: x, y in SNES pixels, its radius, and its glow's size;
    // then its color at full strength (past 1 is brighter than the art), and
    // how bright its glow is.
    vec4 lights[kMaxLights * 2];
};

// How much of the light from `l` reaches `p`, what's solid in between
// taking its share. Solid ground the ray starts in (the pixel's own wall, so
// a wall's face is lit wherever the light can see it) or ends in (the wall
// a torch is set in, so it still shines out) doesn't count: only solid
// ground with open floor on both sides of it, a pillar, a block, the far
// side of a wall, casts a shadow.
float ray(vec2 p, vec2 l) {
    vec2 d = l - p;
    float len = length(d);
    if (len < 4.0) return 1.0;
    int steps = int(clamp(len * 0.5, 2.0, 64.0));
    vec2 step = d / float(steps);
    float through = 1.0;
    float run = 1.0;
    bool out_in_open = false;
    for (int s = 1; s < steps; s++) {
        float solid = texture(u_mask, (p + step * float(s)) * tex.zw).g;
        if (solid > 0.25) {
            if (out_in_open) run *= 1.0 - solid * 0.6;
        } else {
            out_in_open = true;
            through *= run;
            run = 1.0;
            if (through < 0.01) break;
        }
    }
    return through;
}

// A flame isn't a point: three rays to either side of it and its middle,
// averaged, give its shadows soft edges.
float reach(vec2 p, vec2 l) {
    if (look.x <= 0.0) return 1.0;
    vec2 d = l - p;
    float len = length(d);
    if (len < 4.0) return 1.0;
    vec2 side = vec2(-d.y, d.x) / len * 3.5;
    float through = (ray(p, l - side) + ray(p, l) * 2.0 + ray(p, l + side)) * 0.25;
    return mix(1.0, through, look.x);
}

void main() {
    vec2 p = v_uv * tex.xy;
    vec3 light = vec3(0.0);
    int n = int(look.y);
    for (int i = 0; i < kMaxLights; i++) {
        if (i >= n) break;
        vec4 a = lights[i * 2];
        vec4 b = lights[i * 2 + 1];
        float t = length(p - a.xy) / a.z;
        if (t >= 1.0) continue;
        float k = 1.0 - t * t * (3.0 - 2.0 * t);
        light += b.rgb * k * reach(p, a.xy);
    }
    o_color = vec4(light, 1.0);
}
