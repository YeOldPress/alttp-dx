#version 450
// Dynamic lighting, second pass: the frame drawn at the screen's size with
// the light laid over it.
//
// Pixels the room's darkness covers (red in the mask) are darkened the way
// the SNES does it, a fixed amount taken off each channel (in a room that
// isn't dark, just dimmed a little), and then lit
// again from the light map (light_map.frag), read with smooth filtering so
// the light's edges are soft however big the pixels are. Close to a flame,
// where the light is more than the art's own, surfaces brighten a little
// past it. Every light glows, a soft halo over whatever's near it, except
// the HUD (0 in the mask). A touch of noise keeps the gradients from
// banding.
//
// HD Water: where the mask's blue says there's water (and not a sprite over
// it), the water's drawn afresh at the screen's own resolution (hdWater).
//
// And the air bends: shimmering in the desert's heat and over lava, and in
// rings rushing out from blasts. The picture's read from a little way off
// where it does, never pulling the HUD into the scene.
//
// Compiled to SPIR-V and MSL by `zig build shaders`; the results are
// committed, so building the game needs neither tool.

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;
layout(location = 0) out vec4 o_color;

layout(set = 2, binding = 0) uniform sampler2D u_frame;
layout(set = 2, binding = 1) uniform sampler2D u_mask;
layout(set = 2, binding = 2) uniform sampler2D u_light;

const int kMaxLights = 48;

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
    // the glows are, the frame number for the noise, and how much of the
    // room's light is left once the darkness is taken off (1 in a dark room,
    // less in one that's only dimmed).
    vec4 look;
    // The weather: how far a lightning flash washes the scene toward white.
    vec4 weather;
    // HD Water: 1 when there's water in the mask to work on, the game's
    // frame count for it to move by, and where the frame's left edge and
    // top are in the world.
    vec4 water;
    // The desert's heat haze: 1 when it's shimmering, then as water's.
    vec4 heat;
    // 1 when the air over lava shimmers (how hot, 255 less the mask's
    // alpha, its lowest bit aside), how many shockwaves there are, and how
    // many things are reflected in the water.
    vec4 fx;
    // Each blast's shockwave: where it went off in the world, how far its
    // ring has spread, and how many SNES pixels it pushes the picture.
    vec4 shocks[6];
    // What the water reflects: each one's left and right edges on the
    // frame, the line under its feet, and its top.
    vec4 mirrors[8];
    // As in light_map.frag.
    vec4 lights[kMaxLights * 2];
};

float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233)) + look.z * 0.618) * 43758.5453);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(41.37, 289.13))) * 15731.743);
}

// p (in SNES pixels) kept on the frame: the textures can be bigger than it,
// and what's past its edges isn't the picture.
vec2 onFrame(vec2 p) {
    return clamp(p, vec2(0.5), map.xy - 0.5);
}

// The water in the mask at p (in SNES pixels), read smoothly between its
// pixels, for an edge as fine as the screen's.
float waterNear(vec2 p) {
    vec2 q = clamp(p, vec2(1.0), map.xy - 1.0) - 0.5;
    vec2 i = floor(q);
    vec2 f = q - i;
    float a = step(0.004, texture(u_mask, (i + vec2(0.5, 0.5)) * tex.zw).b);
    float b = step(0.004, texture(u_mask, (i + vec2(1.5, 0.5)) * tex.zw).b);
    float c = step(0.004, texture(u_mask, (i + vec2(0.5, 1.5)) * tex.zw).b);
    float d = step(0.004, texture(u_mask, (i + vec2(1.5, 1.5)) * tex.zw).b);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// The water's own clock, in game frames, and where the frame sits in the
// world, so what's drawn on the water stays put as the camera moves.
float waterTime() { return water.y; }
vec2 worldAt(vec2 p) { return p + water.zw; }

float vhash(vec2 i) {
    return fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(vhash(i), vhash(i + vec2(1.0, 0.0)), u.x),
               mix(vhash(i + vec2(0.0, 1.0)), vhash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 x) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(x);
        x = x * 2.03 + vec2(17.1, 9.3);
        a *= 0.5;
    }
    return v;
}

// Whether the mask says the water at uv is drawn in the water's own colors
// (odd), not some speck on it (even), and so fit to blend into its color.
bool cleanWater(vec2 uv) {
    int b = int(texture(u_mask, uv).b * 255.0 + 0.5);
    return b > 2 && (b & 1) == 1;
}

// Whether the mask says the water at uv is see-through (200 or 201): BG1
// blended in over a dungeon's floor, as Swamp Palace's is.
bool seeThrough(vec2 uv) {
    float b = texture(u_mask, uv).b * 255.0;
    return b > 198.5 && b < 201.5;
}

// The water drawn afresh at p: the art's own water colors blended smooth,
// big soft clouds of light and dark drifting over it with a little sky in
// the light, fine wisps of light winding through, a sparkle now and then,
// and white foam breaking along the shore.
vec3 hdWater(vec2 p, vec3 art, bool clear) {
    // The art's color, blended over a few pixels around: its pixels gone,
    // deep and shallow still told apart.
    vec3 sum = vec3(0.0);
    float n = 0.0;
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 2.39996;
        float r = 1.5 + 4.5 * sqrt((float(i) + 0.5) / 12.0);
        vec2 uv = onFrame(p + vec2(cos(a), sin(a)) * r) * tex.zw;
        if (cleanWater(uv)) {
            sum += texture(u_frame, uv).rgb;
            n += 1.0;
        }
    }
    vec3 base = n > 0.0 ? sum / n : art;
    // See-through water: what's under it (the floor, a switch, the steps
    // going in) shows through, softened, and the light plays over it more
    // gently.
    if (clear) base = mix(base, art, 0.7);

    float t = waterTime();
    vec2 wp = worldAt(p);
    vec3 sky = vec3(0.86, 0.93, 1.0);

    // The clouds: light and dark stretches, slowly drifting and turning.
    vec2 q = wp / 56.0 + vec2(t * 0.0006, t * 0.0004);
    float cloud = fbm(q + fbm(q * 0.7 - vec2(t * 0.0003, 0.0)) * 1.6);
    vec3 col = base * (clear ? 0.88 + 0.25 * cloud : 0.72 + 0.6 * cloud);
    col = mix(col, sky, smoothstep(0.55, 0.85, cloud) * (clear ? 0.12 : 0.3));

    // The wisps: thin lines where a slowly warping pattern crosses its
    // middle, as fine as the screen.
    vec2 v = wp / 24.0;
    float warp = fbm(v * 0.8 + vec2(t * 0.0011, -t * 0.0008));
    float r = fbm(v + warp * 1.3 + vec2(-t * 0.0007, t * 0.0009));
    // Kept a screen pixel and a half wide at least, and soft-edged, so a
    // line doesn't flicker on and off as it moves between pixels.
    float wisp = 1.0 - smoothstep(0.0, max(0.022, fwidth(r) * 1.5), abs(r - 0.5));
    col += sky * wisp * (0.08 + 0.14 * cloud) * (clear ? 0.7 : 1.0);

    // Now and then a sparkle, a sharp point of light that winks out.
    vec2 cell = floor(wp / 5.0);
    float h = hash(cell);
    if (h > 0.88) {
        vec2 at = (cell + 0.25 + 0.5 * vec2(hash(cell + 7.0), hash(cell + 13.0))) * 5.0;
        float flash = pow(max(0.0, sin(h * 97.0 + t * (0.03 + 0.05 * h))), 40.0);
        col += sky * flash * smoothstep(0.9, 0.0, length(wp - at)) * 0.7;
    }

    // The foam: white along the shore, broken up and moving. How much water
    // there is all around, averaged, rounds off the shore's stair steps.
    // Soft and faint, a haze fading out from the shore rather than a line
    // drawn along it.
    float around = 0.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7853982 + 0.3927;
        around += waterNear(p + vec2(cos(a), sin(a)) * 3.5);
    }
    around /= 8.0;
    float broken = 0.5 + 0.5 * smoothstep(0.35, 0.65, fbm(wp / 6.0 + vec2(t * 0.002, -t * 0.0015)));
    float foam = smoothstep(1.0, 0.55, around) * broken;
    col = mix(col, vec3(0.95, 0.98, 1.0), foam * 0.18);

    // Deep and shallow alike: the art's own colors, blended above, already
    // tell them apart, where the tiles' say might not match what's drawn.
    return col;
}

// The mask's alpha as a byte: 255 less the heat over lava, its lowest bit
// clear for a sprite's pixel.
int maskAlpha(vec2 uv) {
    return int(texture(u_mask, uv).a * 255.0 + 0.5);
}

// The water at p, with whatever stands in it or at its edge reflected:
// each one mirrored about the line under its feet, wavering with the
// water, fading the deeper it goes and tinted by the water.
vec3 reflections(vec2 p, vec3 col) {
    float t = waterTime();
    for (int i = 0; i < 8; i++) {
        if (float(i) >= fx.z) break;
        vec4 m = mirrors[i];
        float depth = p.y - m.z;
        float height = m.z - m.w;
        if (p.x < m.x - 2.0 || p.x > m.y + 2.0 || depth < 0.0 || depth > height) continue;
        float wave = sin(p.y * 0.9 + t * 0.12) * 0.6 * (0.3 + depth / height);
        vec2 q = vec2(p.x + wave, m.z - depth - 1.0);
        vec2 uv = onFrame(q) * tex.zw;
        if ((maskAlpha(uv) & 1) != 0) continue;
        vec3 seen = texture(u_frame, uv).rgb;
        float fade = 0.42 * (1.0 - depth / height);
        col = mix(col, seen * mix(vec3(1.0), col * 1.6, 0.45), fade);
    }
    return col;
}

void main() {
    vec2 p = v_uv * tex.xy;
    vec4 here = texture(u_mask, v_uv);
    vec2 uv = v_uv;
    // Where the picture's read from, once the air's bent it.
    vec2 from = p;
    vec2 wp = worldAt(p);
    float t = waterTime();
    vec2 bend = vec2(0.0);
    float front = 0.0;
    if (here.r * 255.0 > 0.5) {
        // The desert's heat: the picture wavers, row by row, side to side,
        // in ripples that rise up the screen, stronger in some stretches
        // than others as they drift.
        if (heat.x > 0.0) {
            float stretch = smoothstep(0.3, 0.75, fbm(wp / 70.0 + vec2(t * 0.0015, -t * 0.0025)));
            float a = sin(wp.y * 0.55 + t * 0.09 + sin(wp.x * 0.045 + t * 0.013) * 1.5);
            float b = sin(wp.y * 1.4 + t * 0.16 + wp.x * 0.03);
            bend.x += (a * 0.65 + b * 0.35) * 1.1 * (0.35 + 0.65 * stretch);
            bend.y += sin(wp.x * 0.09 + wp.y * 0.2 + t * 0.05) * 0.25 * stretch;
        }
        // Over lava, the same but quicker and tighter, as hot as the air
        // is there.
        float hot = fx.x > 0.0 ? float(255 - (maskAlpha(v_uv) | 1)) / 255.0 : 0.0;
        if (hot > 0.004) {
            float flick = 0.6 + 0.4 * fbm(wp / 20.0 + vec2(0.0, t * 0.02));
            float a = sin(wp.y * 0.8 + t * 0.15 + sin(wp.x * 0.07 + t * 0.02) * 1.5);
            float b = sin(wp.y * 1.9 + t * 0.24 + wp.x * 0.05);
            bend.x += (a * 0.6 + b * 0.4) * 1.2 * hot * flick;
            bend.y += sin(wp.x * 0.13 + wp.y * 0.3 + t * 0.08) * 0.3 * hot;
        }
        // The shockwaves: each ring a bulge in the air, the picture pushed
        // outward ahead of it and drawn back in behind.
        for (int i = 0; i < 6; i++) {
            if (float(i) >= fx.y) break;
            vec4 s = shocks[i];
            vec2 d = wp - s.xy;
            float dist = length(d);
            float width = 5.0 + s.z * 0.1;
            float x = (dist - s.z) / width;
            float ring = exp(-x * x);
            // x e^(-x^2) peaks at 0.43; this makes s.w the push at its peak.
            bend -= d / max(dist, 0.001) * (x * ring * 2.33) * s.w;
            front += ring * s.w;
        }
        if (bend != vec2(0.0)) {
            vec2 moved = onFrame(p + bend) * tex.zw;
            if (texture(u_mask, moved).r * 255.0 > 0.5) {
                uv = moved;
                from = onFrame(p + bend);
            }
        }
    }
    // 2 in the mask is something over the water, a sprite or the HUD: not
    // drawn as water, though the shore's foam isn't drawn around it.
    float w = water.x > 0.0 && texture(u_mask, uv).b * 255.0 > 2.5 ? 1.0 : 0.0;
    vec3 c = texture(u_frame, uv).rgb;
    float m = here.r * 255.0;
    if (w > 0.0) c = reflections(from, hdWater(from, c, seeThrough(uv)));

    if (m > 0.5 && m < 1.5) {
        // The light map's texels sit on SNES pixel centers.
        vec3 light = texture(u_light, p * map.zw).rgb;
        vec3 base = max(c - dark.rgb, vec3(0.0)) * look.w;
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

    // A shockwave's front catches the light a little.
    if (front > 0.0) c *= 1.0 + min(front, 5.0) * 0.03;

    // And a touch warmer in the heat.
    if (heat.x > 0.0 && m > 0.5) c *= vec3(1.03, 1.0, 0.96);

    // A lightning flash: the scene, not the HUD, washed toward a cold white.
    if (m > 0.5 && weather.x > 0.0)
        c = mix(c, max(c, vec3(0.85, 0.9, 1.0)), weather.x);

    c += (noise(floor(gl_FragCoord.xy)) - 0.5) / 255.0;
    o_color = vec4(clamp(c, 0.0, 1.0), 1.0);
}
