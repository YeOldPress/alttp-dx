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
    // HD Water: when there's water in the mask to work on, 1 indoors and 2
    // out in the world; the game's frame count for it to move by, and where
    // the frame's left edge and top are in the world.
    vec4 water;
    // The desert's heat haze: 1 when it's shimmering, then as water's.
    vec4 heat;
    // 1 when the air over lava shimmers (how hot, 255 less the mask's
    // alpha, its lowest bit aside), how many shockwaves there are, how
    // many things are reflected in the water, and how many points of
    // Link's wake there are.
    vec4 fx;
    // Each blast's shockwave: where it went off in the world, how far its
    // ring has spread, and how many SNES pixels it pushes the picture.
    vec4 shocks[6];
    // What the water reflects: each one's left and right edges on the
    // frame, the line under its feet, and its top.
    vec4 mirrors[8];
    // 1 when there's lava to redraw (61 in the mask's blue), 1 when there's light from a window (the mask's alpha says
    // where), how strong the bloom is, and how many bright things bloom.
    vec4 air;
    // Each one that blooms: where it is on the frame, how far round it,
    // and how strongly.
    vec4 blooms[8];
    // Link's wake: each point he's left behind him swimming, where it is in
    // the world, how many frames ago, and how strong.
    vec4 wake[48];
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
    return b > 2 && (b & 1) == 1 && b != 61;
}

// Whether the mask says uv is lava (61), to be drawn afresh.
bool isLava(vec2 uv) {
    float b = texture(u_mask, uv).b * 255.0;
    return b > 60.5 && b < 61.5;
}

// Whether the mask says the water at uv is see-through (200 or 201): BG1
// blended in over a dungeon's floor, as Swamp Palace's is.
bool seeThrough(vec2 uv) {
    float b = texture(u_mask, uv).b * 255.0;
    return b > 198.5 && b < 201.5;
}

// How much of the water round p is deep (254 or 255 in the mask), over a
// few pixels, so the change from shallow to deep is a soft one rather
// than a tile's square edge.
float deepAround(vec2 p) {
    float d = texture(u_mask, onFrame(p) * tex.zw).b * 255.0 > 229.5 ? 1.0 : 0.0;
    for (int i = 0; i < 16; i++) {
        float a = float(i) * 0.392699 + (i < 8 ? 0.0 : 0.196);
        float r = i < 8 ? 4.5 : 10.0;
        d += texture(u_mask, onFrame(p + vec2(cos(a), sin(a)) * r) * tex.zw).b * 255.0 > 229.5 ? 1.0 : 0.0;
    }
    return d / 17.0;
}

// The water's surface out in the world, its height at wp (in the world)
// at time t: six trains of waves crossing, long to short, and fine
// ripples over them.
float waveHeight(vec2 wp, float t) {
    // Six trains of waves at uneven angles and lengths, each bent its own
    // way by slow noise so they never line up into a pattern; crests a
    // little sharper than troughs, as real ones are. Fine ripples over.
    float h = 0.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float ang = 0.3 + fi * 0.97;
        float freq = 0.2 * pow(1.33, fi);
        float amp = 0.32 * pow(0.78, fi);
        vec2 dir = vec2(cos(ang), sin(ang));
        float warp = vnoise(wp / (36.0 - fi * 3.0) + vec2(fi * 7.3, fi * 3.1) + t * 0.0015) * 4.0;
        float w = 0.5 + 0.5 * sin(dot(wp, dir) * freq - t * (0.03 + fi * 0.009) + warp);
        h += w * w * amp;
    }
    h += (vnoise(wp / 3.0 + vec2(t * 0.012, -t * 0.009)) - 0.5) * 0.12;
    return h;
}

// Link's wake at wp, as a boat leaves one: a short train of waves
// spreading out from each point he's swum through, slower than he swims,
// so they pile up into the V behind him (and follow him round a turn);
// wider and lower as they spread, settling as they age. Gives the slope
// they add to the surface, and how much white water's churned up right
// behind him.
vec2 wakeSlope(vec2 wp, out float churn) {
    vec2 grad = vec2(0.0);
    churn = 0.0;
    for (int i = 0; i < 48; i++) {
        if (float(i) >= fx.w) break;
        vec4 k = wake[i];
        vec2 off = wp - k.xy;
        float d = length(off);
        float age = k.z / 96.0;
        // Fresh, the churned white water along his path.
        if (d < 8.0) churn += k.w * exp(-d * d / 5.0) * max(1.0 - age * 3.0, 0.0) * 0.67;
        float r = 2.0 + k.z * 0.32;
        float x = d - r;
        if (abs(x) > 6.0 || d < 0.01) continue;
        float s = 1.0 - age;
        float amp = k.w * s * sqrt(s) * 0.36 * inversesqrt(1.0 + r * 0.15);
        // Uneven from ring to ring, so the waves inside the V don't line
        // up like the teeth of a comb.
        amp *= 0.6 + 0.8 * hash(k.xy);
        float e = exp(-x * x / 4.0);
        // A crest or two, leading the ring, the steepest at its front.
        float slope = (1.5 * cos(x * 1.5) - x / 2.0 * sin(x * 1.5)) * e;
        grad += amp * slope * off / d;
    }
    return grad;
}

// The water drawn afresh at p: the art's own water colors blended smooth,
// big soft clouds of light and dark drifting over it with a little sky in
// the light, fine wisps of light winding through, a sparkle now and then,
// and white foam breaking along the shore.
vec3 hdWater(vec2 p, vec3 art, bool clear) {
    bool outdoors = water.x > 1.5;
    // Out in the world, the waves: the surface's slope here, which lights
    // it and bends what's seen through it.
    vec3 normal = vec3(0.0, 0.0, 1.0);
    float churn = 0.0;
    if (outdoors) {
        vec2 wq = worldAt(p);
        float tw = waterTime();
        float e = 0.75;
        float dx = waveHeight(wq + vec2(e, 0.0), tw) - waveHeight(wq - vec2(e, 0.0), tw);
        float dy = waveHeight(wq + vec2(0.0, e), tw) - waveHeight(wq - vec2(0.0, e), tw);
        vec2 slope = vec2(dx, dy) * 0.6 + wakeSlope(wq, churn);
        normal = normalize(vec3(-slope * 1.0, 1.0));
    }
    vec2 seen = p + normal.xy * 2.0;
    // The art's color, blended over a few pixels around: its pixels gone,
    // deep and shallow still told apart.
    vec3 sum = vec3(0.0);
    float n = 0.0;
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 2.39996;
        float r = 1.5 + 4.5 * sqrt((float(i) + 0.5) / 12.0);
        vec2 uv = onFrame(seen + vec2(cos(a), sin(a)) * r) * tex.zw;
        if (cleanWater(uv)) {
            sum += texture(u_frame, uv).rgb;
            n += 1.0;
        }
    }
    vec3 base = n > 0.0 ? sum / n : art;
    // The water's colors further round, to set its darker patches (where
    // the art draws it deeper) further apart from the rest.
    vec3 wide = vec3(0.0);
    float wn = 0.0;
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 2.39996 + 1.1;
        float r = 6.0 + 10.0 * sqrt((float(i) + 0.5) / 12.0);
        vec2 uv = onFrame(p + vec2(cos(a), sin(a)) * r) * tex.zw;
        if (cleanWater(uv)) {
            wide += texture(u_frame, uv).rgb;
            wn += 1.0;
        }
    }
    if (outdoors && wn > 0.0) base = clamp(wide / wn + (base - wide / wn) * 1.4, 0.0, 1.0);
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
    // Gentle enough not to hide which water's deep.
    // Out in the world, gentle enough not to hide which water's deep.
    vec3 col = base * (clear ? 0.88 + 0.25 * cloud : outdoors ? 0.84 + 0.32 * cloud : 0.72 + 0.6 * cloud);
    col = mix(col, sky, smoothstep(0.55, 0.85, cloud) * (clear ? 0.12 : outdoors ? 0.2 : 0.3));
    // Out in the world, deep water (where Link swims) darker and richer,
    // shallow (where he wades) lighter, as the game's tiles have them.
    if (outdoors) {
        float deep = deepAround(p);
        col *= mix(1.07, 0.8, smoothstep(0.0, 1.0, deep));
        // The waves lit by the sun, high to the top left: faces turned to
        // it brighter, the backs of them darker, and glints off the crests.
        vec3 sun = normalize(vec3(-0.45, -0.6, 0.66));
        float facing = dot(normal, sun) - sun.z;
        col *= 1.0 + facing * 0.75;
        vec3 bounce = reflect(-sun, normal);
        float glint = pow(max(bounce.z, 0.0), 40.0);
        col += vec3(1.0, 0.98, 0.92) * glint * 0.45;
    }

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
    // And white water churned up behind Link as he swims, broken up.
    col = mix(col, vec3(0.95, 0.98, 1.0), clamp(churn * 0.15, 0.0, 0.2) * broken);

    // Deep and shallow alike: the art's own colors, blended above, already
    // tell them apart, where the tiles' say might not match what's drawn.
    return col;
}

// How much of what's round p (in SNES pixels) is lava, read smoothly
// between pixels.
float lavaNear(vec2 p) {
    vec2 q = clamp(p, vec2(1.0), map.xy - 1.0) - 0.5;
    vec2 i = floor(q);
    vec2 f = q - i;
    float a = isLava((i + vec2(0.5, 0.5)) * tex.zw) ? 1.0 : 0.0;
    float b = isLava((i + vec2(1.5, 0.5)) * tex.zw) ? 1.0 : 0.0;
    float c = isLava((i + vec2(0.5, 1.5)) * tex.zw) ? 1.0 : 0.0;
    float d = isLava((i + vec2(1.5, 1.5)) * tex.zw) ? 1.0 : 0.0;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// The lava drawn afresh at p: its own colors blended smooth, churning
// slowly, a dark crust cooling over it in drifting plates with glowing
// cracks between, hot spots throbbing, the odd bubble swelling and
// bursting, and the crust thicker along its banks.
vec3 hdLava(vec2 p, vec3 art) {
    vec2 wp = worldAt(p);
    // Lava's thick: everything on it moves at half the water's pace.
    float t = waterTime() * 0.5;
    // The art's three colors, its dark red, red and orange, each found
    // among the pixels around and blended in the same measure everywhere,
    // as much of each as shows over time. (The game animates its lava,
    // much more of the dark red showing on some frames than others:
    // blended as they come, the whole of it would pulse in time.)
    vec3 dark = vec3(0.0);
    vec3 red = vec3(0.0);
    vec3 orange = vec3(0.0);
    vec3 n3 = vec3(0.0);
    for (int i = 0; i < 17; i++) {
        vec2 uv = onFrame(p) * tex.zw;
        if (i > 0) {
            float a = float(i) * 2.39996;
            float r = 1.5 + 8.0 * sqrt((float(i) - 0.5) / 16.0);
            uv = onFrame(p + vec2(cos(a), sin(a)) * r) * tex.zw;
        }
        if (!isLava(uv)) continue;
        vec3 c = texture(u_frame, uv).rgb;
        if (c.g > 0.3) { orange += c; n3.z += 1.0; }
        else if (c.r < 0.75) { dark += c; n3.x += 1.0; }
        else { red += c; n3.y += 1.0; }
    }
    // One missing is made from the others, as Turtle Rock's are.
    if (n3.y > 0.0) red /= n3.y;
    else if (n3.z > 0.0) red = orange / n3.z * vec3(0.906, 0.27, 1.0);
    else if (n3.x > 0.0) red = dark / n3.x * vec3(1.56, 1.37, 1.4);
    else red = art;
    dark = n3.x > 0.0 ? dark / n3.x : red * vec3(0.64, 0.73, 0.71);
    orange = n3.z > 0.0 ? orange / n3.z : red * vec3(1.1, 3.7, 1.0);
    vec3 base = dark * 0.28 + red * 0.52 + orange * 0.2;

    // The slow churn: the pattern drifting and folding over on itself.
    vec2 q = wp / 30.0;
    vec2 flow = vec2(fbm(q + vec2(0.0, t * 0.0016)), fbm(q + vec2(5.2, 1.3) - vec2(t * 0.0013, 0.0)));
    float heat = fbm(q * 1.4 + flow * 2.4 + vec2(t * 0.0009, -t * 0.0012));
    // Molten where it's hot, crusted over darker where it's cooled.
    float molten = smoothstep(0.22, 0.55, heat);
    vec3 crust = base * vec3(0.66, 0.42, 0.38);
    vec3 col = mix(crust, base * vec3(1.12, 1.18, 1.0), molten);
    // The cracks in the crust glowing yellow, thin lines where a second,
    // quicker pattern crosses its middle, kept soft as fine as the screen.
    vec2 v = wp / 24.0 + flow * 1.2;
    float r = fbm(v + vec2(t * 0.0018, t * 0.0014));
    float crack = 1.0 - smoothstep(0.0, max(0.05, fwidth(r) * 2.0), abs(r - 0.5));
    col = mix(col, vec3(1.0, 0.62, 0.2), crack * (1.0 - molten) * 0.6);
    // The hottest spots brighten toward yellow white, and throb.
    float throb = 0.5 + 0.5 * sin(t * 0.015 + heat * 4.0);
    col = mix(col, vec3(1.0, 0.86, 0.45), smoothstep(0.68, 0.85, heat) * (0.35 + 0.25 * throb));

    // Now and then a bubble swells up, glowing, and bursts.
    vec2 cell = floor(wp / 14.0);
    float h = hash(cell + 3.7);
    if (h > 0.55) {
        // Slower still than the rest, as thick as it is: swelling for a
        // second or two, bursting, and settling.
        float tb = t * 0.35;
        float period = 90.0 + 120.0 * hash(cell + 9.1);
        float phase = fract(tb / period + h * 7.0);
        vec2 at = (cell + 0.3 + 0.4 * vec2(hash(cell + 1.3), hash(cell + 5.9))) * 14.0;
        float d = length(wp - at);
        float size = 1.0 + 3.0 * smoothstep(0.0, 0.12, phase);
        // Swelling, a bright dome with a darker rim.
        float dome = (1.0 - smoothstep(size - 0.8, size, d)) * step(phase, 0.12);
        col = mix(col, vec3(1.0, 0.8, 0.4), dome * (0.25 + 0.5 * (1.0 - d / size)));
        // Burst, a ring spreading out and fading.
        float since = (phase - 0.12) * period;
        float ring = exp(-pow(d - (size + since * 0.25), 2.0) / 0.8) * step(0.12, phase) * exp(-since / 10.0);
        col = mix(col, vec3(1.0, 0.85, 0.5), ring * 0.6);
    }

    // Cooler and crusted along its banks.
    float around = 0.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7853982 + 0.3927;
        around += lavaNear(p + vec2(cos(a), sin(a)) * 3.0);
    }
    around /= 8.0;
    col = mix(crust, col, 0.35 + 0.65 * smoothstep(0.45, 0.95, around));
    return col;
}

// The mask's alpha as a byte: 255 less the heat over lava, its lowest bit
// clear for a sprite's pixel and the next for light from a window.
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

// Whether the mask says there's light from a window at uv.
float beamAt(vec2 uv) {
    return (maskAlpha(uv) & 2) == 0 ? 1.0 : 0.0;
}

// Light from a window, as the game draws it: hard-edged bands of it. Its
// edges softened into the room, and a slow shimmer through it.
vec3 windowLight(vec2 p, vec2 wp, vec3 c) {
    float cover = beamAt(onFrame(p) * tex.zw);
    vec3 around = c;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7853982 + 0.3927;
        vec2 uv = onFrame(p + vec2(cos(a), sin(a)) * 2.5) * tex.zw;
        cover += beamAt(uv);
        around += texture(u_frame, uv).rgb;
    }
    cover /= 9.0;
    if (cover <= 0.0) return c;
    around /= 9.0;
    float edge = 1.0 - abs(cover * 2.0 - 1.0);
    c = mix(c, around, edge * 0.6);
    float t = waterTime();
    return c + vec3(1.0, 0.95, 0.8) * cover * (0.05 + 0.03 * sin(t * 0.025 + wp.y * 0.04 - wp.x * 0.02));
}

// Bloom: bright sprites (magic, a crystal, the Master Sword held up)
// bleeding their own colors softly out round them.
vec3 bloom(vec2 p, vec3 c, float near) {
    vec3 sum = vec3(0.0);
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 2.39996;
        float r = 1.0 + 4.5 * sqrt((float(i) + 0.5) / 12.0);
        vec2 uv = onFrame(p + vec2(cos(a), sin(a)) * r) * tex.zw;
        if ((maskAlpha(uv) & 1) != 0) continue;
        vec3 s = texture(u_frame, uv).rgb;
        sum += s * smoothstep(0.55, 1.0, max(s.r, max(s.g, s.b)));
    }
    sum /= 12.0;
    return c + sum * (1.0 - c) * min(near, 1.0) * 2.0 * air.z;
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
        float hot = fx.x > 0.0 ? float(255 - (maskAlpha(v_uv) | 3)) / 255.0 : 0.0;
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
    if (w > 0.0 && !isLava(uv)) c = reflections(from, hdWater(from, c, seeThrough(uv)));
    if (air.x > 0.0 && isLava(uv)) c = hdLava(from, c);
    if (air.y > 0.0 && here.r * 255.0 > 0.5) c = windowLight(from, wp, c);

    if (m > 0.5 && m < 1.5) {
        // The light map's texels sit on SNES pixel centers.
        vec3 light = texture(u_light, p * map.zw).rgb;
        vec3 base = max(c - dark.rgb, vec3(0.0)) * look.w;
        vec3 lit = base + c * min(light, vec3(1.0));
        vec3 over = c * max(light - vec3(1.0), vec3(0.0)) * look.x;
        c = min(lit, c) + over;
    }

    if (m > 0.5 && air.z > 0.0 && air.w > 0.0) {
        float near = 0.0;
        for (int i = 0; i < 8; i++) {
            if (float(i) >= air.w) break;
            vec2 d = p - blooms[i].xy;
            near += blooms[i].w * exp(-dot(d, d) / (2.0 * blooms[i].z * blooms[i].z));
        }
        if (near > 0.03) c = bloom(p, c, near);
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
