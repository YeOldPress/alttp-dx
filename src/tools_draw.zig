//! What the tools window and the start page are drawn with: real text in
//! Inter (and Cinzel, for the start page's titles), baked with
//! stb_truetype at the screen's own pixel density, and shapes with smooth
//! rounded corners. Everything is laid out in points; `scale` is how many of
//! the screen's pixels one point is, so a Retina or a 150% Windows screen
//! gets text that's sharp rather than blown up.
const std = @import("std");
const c = @import("sdl.zig").c;
const fonts = @import("tools_fonts");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn hex(v: u24) Color {
        return .{ .r = @truncate(v >> 16), .g = @truncate(v >> 8), .b = @truncate(v) };
    }

    pub fn alpha(self: Color, a: u8) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }

    fn f(self: Color) c.SDL_FColor {
        return .{ .r = @as(f32, @floatFromInt(self.r)) / 255, .g = @as(f32, @floatFromInt(self.g)) / 255, .b = @as(f32, @floatFromInt(self.b)) / 255, .a = @as(f32, @floatFromInt(self.a)) / 255 };
    }
};

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h;
    }

    pub fn inset(self: Rect, d: f32) Rect {
        return .{ .x = self.x + d, .y = self.y + d, .w = self.w - d * 2, .h = self.h - d * 2 };
    }
};

// ------------------------------------------------------------------- text

/// The sizes and weights the window uses.
pub const Style = enum {
    /// The log, the version, hints.
    small,
    body,
    /// Buttons, the picked page in the sidebar, field labels.
    strong,
    heading,
    brand,

    // The start page's.
    /// Its menu.
    item,
    /// The line over its title, and the anniversary's.
    eyebrow,
    /// The name under its title.
    subtitle,
    title,
    /// Play.
    button,
    /// A sub-screen's name, at its top.
    headline,
    // The front page's title, around the name.
    hero_eyebrow,
    hero_subtitle,
    hero_small,
    hero_chip,

    fn size(self: Style) f32 {
        return switch (self) {
            .small => 12.5,
            .body => 14,
            .strong => 14,
            .heading => 24,
            .brand => 16,
            .item => 16,
            .eyebrow => 12,
            .subtitle => 17,
            .title => 70,
            .button => 20,
            .headline => 28,
            .hero_eyebrow => 15.5,
            .hero_subtitle => 22,
            .hero_small => 16,
            .hero_chip => 18,
        };
    }

    fn ttf(self: Style) []const u8 {
        return switch (self) {
            .small, .body, .hero_small => fonts.regular,
            .strong, .heading, .brand, .item, .hero_chip => fonts.semibold,
            .eyebrow, .subtitle, .title, .button, .headline, .hero_eyebrow, .hero_subtitle => fonts.display,
        };
    }
};

/// What the tools window draws with.
pub const kToolStyles = std.EnumSet(Style).initMany(&.{ .small, .body, .strong, .heading, .brand });
const kStyleCount = @typeInfo(Style).@"enum".field_names.len;

/// Laid out as stbtt_packedchar.
const Glyph = extern struct { x0: u16, y0: u16, x1: u16, y1: u16, xoff: f32, yoff: f32, xadvance: f32, xoff2: f32, yoff2: f32 };

extern fn tools_font_bake(ttf: [*]const u8, px: f32, atlas: [*]u8, w: c_int, h: c_int, codepoints: [*]const c_int, count: c_int, out: [*]Glyph) c_int;
extern fn tools_font_metrics(ttf: [*]const u8, px: f32, ascent: *f32, descent: *f32, unit: *f32) void;
extern fn tools_font_kerning(ttf: [*]const u8, first: c_int, count: c_int, out: [*]i16) void;

/// Printable ASCII, Latin-1 and Latin Extended-A, for the accented letters
/// in people's file names, and a few marks the window uses.
const kSpecials = [_]u21{ 0x2013, 0x2014, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2026, 0x2190, 0x2191, 0x2192, 0x2193, 0x2713, 0x25b6, 0x25a0 };
const kAsciiCount = 0x7f - 0x20;
const kLatinCount = 0x180 - 0xa0;
const kGlyphCount = kAsciiCount + kLatinCount + kSpecials.len;
const kCodepoints: [kGlyphCount]c_int = blk: {
    var list: [kGlyphCount]c_int = undefined;
    for (0..kAsciiCount) |i| list[i] = 0x20 + i;
    for (0..kLatinCount) |i| list[kAsciiCount + i] = 0xa0 + i;
    for (kSpecials, 0..) |s, i| list[kAsciiCount + kLatinCount + i] = s;
    break :blk list;
};

fn glyphIndex(cp: u21) usize {
    if (cp >= 0x20 and cp < 0x7f) return cp - 0x20;
    if (cp >= 0xa0 and cp < 0x180) return kAsciiCount + cp - 0xa0;
    for (kSpecials, 0..) |s, i| if (s == cp) return kAsciiCount + kLatinCount + i;
    return '?' - 0x20;
}

/// Kerning, between ASCII letters only, in font units; the same at every
/// size, so worked out once a weight.
var g_kern_regular: [kAsciiCount * kAsciiCount]i16 = undefined;
var g_kern_semibold: [kAsciiCount * kAsciiCount]i16 = undefined;
var g_kern_display: [kAsciiCount * kAsciiCount]i16 = undefined;
var g_kern_ready = false;

const Face = struct {
    tex: ?*c.SDL_Texture = null,
    atlas_w: f32 = 1,
    atlas_h: f32 = 1,
    glyphs: [kGlyphCount]Glyph = undefined,
    /// In points.
    ascent: f32 = 0,
    descent: f32 = 0,
    /// Points per font unit, for the kerning.
    unit: f32 = 0,
    kern: *const [kAsciiCount * kAsciiCount]i16 = &g_kern_regular,
};

/// One text-and-shape painter per renderer.
pub const Paint = struct {
    r: *c.SDL_Renderer,
    scale: f32 = 0,
    /// The styles baked, the rest left alone: the tools window has no use
    /// for a title 54 points tall.
    styles: std.EnumSet(Style) = kToolStyles,
    faces: [kStyleCount]Face = @splat(.{}),
    /// A smooth white disc, whose quarters make every rounded corner.
    disc_tex: ?*c.SDL_Texture = null,

    pub fn init(r: *c.SDL_Renderer, scale: f32) Paint {
        return initStyles(r, scale, kToolStyles);
    }

    pub fn initStyles(r: *c.SDL_Renderer, scale: f32, styles: std.EnumSet(Style)) Paint {
        var p = Paint{ .r = r, .styles = styles };
        _ = c.SDL_SetRenderDrawBlendMode(r, c.SDL_BLENDMODE_BLEND);
        if (!g_kern_ready) {
            tools_font_kerning(fonts.regular.ptr, 0x20, kAsciiCount, &g_kern_regular);
            tools_font_kerning(fonts.semibold.ptr, 0x20, kAsciiCount, &g_kern_semibold);
            tools_font_kerning(fonts.display.ptr, 0x20, kAsciiCount, &g_kern_display);
            g_kern_ready = true;
        }
        p.disc_tex = makeDisc(r);
        p.setScale(scale);
        return p;
    }

    pub fn deinit(self: *Paint) void {
        for (&self.faces) |*face| if (face.tex) |t| c.SDL_DestroyTexture(t);
        if (self.disc_tex) |t| c.SDL_DestroyTexture(t);
    }

    /// Bakes the text again for a new pixel density, as when the window
    /// moves to another screen.
    pub fn setScale(self: *Paint, scale: f32) void {
        if (scale == self.scale) return;
        self.scale = scale;
        _ = c.SDL_SetRenderScale(self.r, scale, scale);
        for (std.enums.values(Style), &self.faces) |style, *face| {
            if (face.tex) |t| c.SDL_DestroyTexture(t);
            face.* = if (self.styles.contains(style)) bake(self.r, style, scale) else .{};
        }
    }

    pub fn lineHeight(self: *const Paint, style: Style) f32 {
        _ = self;
        return @round(style.size() * 1.45);
    }

    /// As wide as `s` drawn `tracking` points apart, letter to letter.
    pub fn textWidthTracked(self: *const Paint, style: Style, s: []const u8, tracking: f32) f32 {
        const n = std.unicode.utf8CountCodepoints(s) catch s.len;
        return self.textWidth(style, s) + tracking * @as(f32, @floatFromInt(@max(n, 1) - 1));
    }

    pub fn textWidth(self: *const Paint, style: Style, s: []const u8) f32 {
        const face = &self.faces[@backingInt(style)];
        var w: f32 = 0;
        var prev: ?usize = null;
        var it = Utf8{ .s = s };
        while (it.next()) |cp| {
            const gi = glyphIndex(cp);
            w += face.glyphs[gi].xadvance / self.scale + kernBetween(face, prev, gi);
            prev = gi;
        }
        return w;
    }

    /// Draws `s` with its line's top at `y`.
    pub fn text(self: *const Paint, style: Style, x: f32, y: f32, col: Color, s: []const u8) void {
        self.textEx(style, x, y, col, col, 0, s);
    }

    /// Where the baseline of a line whose top is at `y` falls.
    pub fn baseline(self: *const Paint, style: Style, y: f32) f32 {
        const face = &self.faces[@backingInt(style)];
        return self.snap(y + (self.lineHeight(style) - (face.ascent - face.descent)) / 2 + face.ascent);
    }

    /// How tall a capital is, about, above the baseline.
    pub fn capHeight(self: *const Paint, style: Style) f32 {
        return self.faces[@backingInt(style)].ascent * 0.72;
    }

    /// Draws `s` with its line's top at `y`, `tracking` points further apart
    /// than the font sets it, shading from `top` at the capitals' tops to
    /// `bottom` at the baseline.
    pub fn textEx(self: *const Paint, style: Style, x: f32, y: f32, top: Color, bottom: Color, tracking: f32, s: []const u8) void {
        const face = &self.faces[@backingInt(style)];
        const tex = face.tex orelse return;
        const base_y = self.baseline(style, y);
        const cap = face.ascent * 0.72;
        var pen = self.snap(x);
        const ft = top.f();
        const fb = bottom.f();
        const shade = struct {
            fn at(a: c.SDL_FColor, b: c.SDL_FColor, t0: f32) c.SDL_FColor {
                const t = std.math.clamp(t0, 0, 1);
                return .{ .r = a.r + (b.r - a.r) * t, .g = a.g + (b.g - a.g) * t, .b = a.b + (b.b - a.b) * t, .a = a.a + (b.a - a.a) * t };
            }
        }.at;

        var verts: [64 * 4]c.SDL_Vertex = undefined;
        var idx: [64 * 6]c_int = undefined;
        var n: usize = 0;
        var prev: ?usize = null;
        var it = Utf8{ .s = s };
        while (it.next()) |cp| {
            const gi = glyphIndex(cp);
            const g = face.glyphs[gi];
            pen += kernBetween(face, prev, gi);
            prev = gi;
            if (cp != ' ') {
                const x0 = pen + g.xoff / self.scale;
                const x1 = pen + g.xoff2 / self.scale;
                const y0 = base_y + g.yoff / self.scale;
                const y1 = base_y + g.yoff2 / self.scale;
                const c0 = shade(ft, fb, (y0 - (base_y - cap)) / cap);
                const c1 = shade(ft, fb, (y1 - (base_y - cap)) / cap);
                const tu0 = @as(f32, @floatFromInt(g.x0)) / face.atlas_w;
                const tu1 = @as(f32, @floatFromInt(g.x1)) / face.atlas_w;
                const tv0 = @as(f32, @floatFromInt(g.y0)) / face.atlas_h;
                const tv1 = @as(f32, @floatFromInt(g.y1)) / face.atlas_h;
                const base: c_int = @intCast(n * 4);
                verts[n * 4 + 0] = .{ .position = .{ .x = x0, .y = y0 }, .color = c0, .tex_coord = .{ .x = tu0, .y = tv0 } };
                verts[n * 4 + 1] = .{ .position = .{ .x = x1, .y = y0 }, .color = c0, .tex_coord = .{ .x = tu1, .y = tv0 } };
                verts[n * 4 + 2] = .{ .position = .{ .x = x1, .y = y1 }, .color = c1, .tex_coord = .{ .x = tu1, .y = tv1 } };
                verts[n * 4 + 3] = .{ .position = .{ .x = x0, .y = y1 }, .color = c1, .tex_coord = .{ .x = tu0, .y = tv1 } };
                for ([_]c_int{ 0, 1, 2, 0, 2, 3 }, 0..) |k, j| idx[n * 6 + j] = base + k;
                n += 1;
                if (n == 64) {
                    _ = c.SDL_RenderGeometry(self.r, tex, &verts, @intCast(n * 4), &idx, @intCast(n * 6));
                    n = 0;
                }
            }
            pen += g.xadvance / self.scale + tracking;
        }
        if (n > 0) _ = c.SDL_RenderGeometry(self.r, tex, &verts, @intCast(n * 4), &idx, @intCast(n * 6));
    }

    pub fn textCentered(self: *const Paint, style: Style, cx: f32, y: f32, col: Color, s: []const u8) void {
        self.text(style, cx - self.textWidth(style, s) / 2, y, col, s);
    }

    /// As much of `s` as fits in `w`, with an ellipsis where it was cut.
    pub fn fit(self: *const Paint, style: Style, s: []const u8, w: f32, buf: []u8) []const u8 {
        if (self.textWidth(style, s) <= w) return s;
        const dots = "\u{2026}";
        const end = self.fitting(style, s, w - self.textWidth(style, dots)).end;
        return std.fmt.bufPrint(buf, "{s}{s}", .{ s[0..end], dots }) catch s[0..end];
    }

    /// Where a line of `s` should break to fit in `w`: at the last space that
    /// fits, or mid-word when one word is too long by itself.
    pub fn breakAt(self: *const Paint, style: Style, s: []const u8, w: f32) usize {
        const f = self.fitting(style, s, w);
        if (f.end == s.len) return s.len;
        if (f.last_space) |sp| if (sp > 0) return sp;
        return @max(f.end, 1);
    }

    /// How much of `s`, from the start, fits in `w`, and the last space in
    /// that much.
    fn fitting(self: *const Paint, style: Style, s: []const u8, w: f32) struct { end: usize, last_space: ?usize } {
        const face = &self.faces[@backingInt(style)];
        var x: f32 = 0;
        var end: usize = 0;
        var last_space: ?usize = null;
        var prev: ?usize = null;
        var it = Utf8{ .s = s };
        while (true) {
            const at = it.i;
            const cp = it.next() orelse break;
            const gi = glyphIndex(cp);
            x += face.glyphs[gi].xadvance / self.scale + kernBetween(face, prev, gi);
            prev = gi;
            if (x > w) break;
            if (cp == ' ') last_space = at;
            end = it.i;
        }
        return .{ .end = end, .last_space = last_space };
    }

    fn snap(self: *const Paint, v: f32) f32 {
        return @round(v * self.scale) / self.scale;
    }

    /// A rectangle in whole pixels.
    const Px = struct { x: f32, y: f32, w: f32, h: f32 };

    fn toPx(self: *const Paint, r: Rect) Px {
        const x = @round(r.x * self.scale);
        const y = @round(r.y * self.scale);
        return .{ .x = x, .y = y, .w = @max(0, @round((r.x + r.w) * self.scale) - x), .h = @max(0, @round((r.y + r.h) * self.scale) - y) };
    }

    /// Back to points, a hair past each whole pixel: the software renderer
    /// cuts a rectangle's corner and size down to whole pixels each on its
    /// own, and 621.9999 would lose a pixel and leave a seam.
    fn fromPx(self: *const Paint, p: Px) c.SDL_FRect {
        const e = 0.01;
        return .{ .x = (p.x + e) / self.scale, .y = (p.y + e) / self.scale, .w = (p.w + e) / self.scale, .h = (p.h + e) / self.scale };
    }

    fn fillPx(self: *const Paint, p: Px, col: Color) void {
        if (p.w <= 0 or p.h <= 0) return;
        _ = c.SDL_SetRenderDrawColor(self.r, col.r, col.g, col.b, col.a);
        const fr = self.fromPx(p);
        _ = c.SDL_RenderFillRect(self.r, &fr);
    }

    // --------------------------------------------------------------- shapes

    pub fn fill(self: *const Paint, rect: Rect, col: Color) void {
        self.fillPx(self.toPx(rect), col);
    }

    /// A rectangle with rounded corners: a quarter of the disc in each, and
    /// three plain rectangles between, so nothing is drawn twice and a color
    /// that's see-through stays even. All worked out in whole pixels, so the
    /// pieces meet without a seam.
    pub fn fillRound(self: *const Paint, rect: Rect, radius: f32, col: Color) void {
        const p = self.toPx(rect);
        const rad = @min(@round(radius * self.scale), @floor(@min(p.w, p.h) / 2));
        const tex = self.disc_tex orelse return self.fillPx(p, col);
        if (rad < 1) return self.fillPx(p, col);
        _ = c.SDL_SetTextureColorMod(tex, col.r, col.g, col.b);
        _ = c.SDL_SetTextureAlphaMod(tex, col.a);
        const half: f32 = kDiscSize / 2;
        const right = p.x + p.w - rad;
        const bottom = p.y + p.h - rad;
        const corners = [_]struct { sx: f32, sy: f32, x: f32, y: f32 }{
            .{ .sx = 0, .sy = 0, .x = p.x, .y = p.y },
            .{ .sx = half, .sy = 0, .x = right, .y = p.y },
            .{ .sx = 0, .sy = half, .x = p.x, .y = bottom },
            .{ .sx = half, .sy = half, .x = right, .y = bottom },
        };
        for (corners) |k| {
            const src = c.SDL_FRect{ .x = k.sx, .y = k.sy, .w = half, .h = half };
            const dst = self.fromPx(.{ .x = k.x, .y = k.y, .w = rad, .h = rad });
            _ = c.SDL_RenderTexture(self.r, tex, &src, &dst);
        }
        self.fillPx(.{ .x = p.x + rad, .y = p.y, .w = p.w - rad * 2, .h = p.h }, col);
        self.fillPx(.{ .x = p.x, .y = p.y + rad, .w = rad, .h = p.h - rad * 2 }, col);
        self.fillPx(.{ .x = right, .y = p.y + rad, .w = rad, .h = p.h - rad * 2 }, col);
    }

    /// A rounded rectangle with a border: the border's color, then `inside`
    /// over it, `width` in.
    pub fn box(self: *const Paint, rect: Rect, radius: f32, width: f32, border: Color, inside: Color) void {
        self.fillRound(rect, radius, border);
        self.fillRound(rect.inset(width), radius - width, inside);
    }

    pub fn disc(self: *const Paint, cx: f32, cy: f32, radius: f32, col: Color) void {
        self.fillRound(.{ .x = cx - radius, .y = cy - radius, .w = radius * 2, .h = radius * 2 }, radius, col);
    }

    /// A soft shadow under a card: a few rounded layers, each a little wider
    /// and fainter.
    pub fn shadow(self: *const Paint, rect: Rect, radius: f32) void {
        var i: f32 = 1;
        while (i <= 6) : (i += 1) {
            const r = Rect{ .x = rect.x - i, .y = rect.y - i + 4, .w = rect.w + i * 2, .h = rect.h + i * 2 };
            self.fillRound(r, radius + i, Color.hex(0x000000).alpha(@intFromFloat(14 - i * 2)));
        }
    }
};

const kDiscSize = 256;

fn makeDisc(r: *c.SDL_Renderer) ?*c.SDL_Texture {
    var px: [kDiscSize * kDiscSize]u32 = undefined;
    const mid: f32 = kDiscSize / 2;
    for (0..kDiscSize) |y| {
        for (0..kDiscSize) |x| {
            const dx = @as(f32, @floatFromInt(x)) + 0.5 - mid;
            const dy = @as(f32, @floatFromInt(y)) + 0.5 - mid;
            const cover = std.math.clamp(mid - @sqrt(dx * dx + dy * dy) + 0.5, 0, 1);
            const a: u32 = @intFromFloat(@round(cover * 255));
            px[y * kDiscSize + x] = 0xffffff00 | a;
        }
    }
    const tex = c.SDL_CreateTexture(r, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STATIC, kDiscSize, kDiscSize) orelse return null;
    _ = c.SDL_UpdateTexture(tex, null, &px, kDiscSize * 4);
    _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
    _ = c.SDL_SetTextureScaleMode(tex, c.SDL_SCALEMODE_LINEAR);
    return tex;
}

fn kernBetween(face: *const Face, prev: ?usize, gi: usize) f32 {
    const p = prev orelse return 0;
    if (p >= kAsciiCount or gi >= kAsciiCount) return 0;
    return @as(f32, @floatFromInt(face.kern[p * kAsciiCount + gi])) * face.unit;
}

/// Bakes one style at `scale` pixels a point, growing the atlas until it
/// all fits.
fn bake(r: *c.SDL_Renderer, style: Style, scale: f32) Face {
    var face = Face{};
    const ttf = style.ttf();
    face.kern = if (ttf.ptr == fonts.semibold.ptr) &g_kern_semibold else if (ttf.ptr == fonts.display.ptr) &g_kern_display else &g_kern_regular;
    tools_font_metrics(ttf.ptr, style.size(), &face.ascent, &face.descent, &face.unit);
    const alloc = std.heap.c_allocator;
    var side: usize = 256;
    while (side <= 4096) : (side *= 2) {
        const atlas = alloc.alloc(u8, side * side) catch return face;
        defer alloc.free(atlas);
        if (tools_font_bake(ttf.ptr, style.size() * scale, atlas.ptr, @intCast(side), @intCast(side), &kCodepoints, kGlyphCount, &face.glyphs) == 0) continue;
        const rgba = alloc.alloc(u32, side * side) catch return face;
        defer alloc.free(rgba);
        for (atlas, rgba) |a, *p| p.* = 0xffffff00 | @as(u32, a);
        const tex = c.SDL_CreateTexture(r, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STATIC, @intCast(side), @intCast(side)) orelse return face;
        _ = c.SDL_UpdateTexture(tex, null, rgba.ptr, @intCast(side * 4));
        _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
        _ = c.SDL_SetTextureScaleMode(tex, c.SDL_SCALEMODE_LINEAR);
        face.tex = tex;
        face.atlas_w = @floatFromInt(side);
        face.atlas_h = @floatFromInt(side);
        return face;
    }
    return face;
}

/// UTF-8, forgiving: a byte that doesn't start a good sequence is a '?'.
const Utf8 = struct {
    s: []const u8,
    i: usize = 0,

    fn next(self: *Utf8) ?u21 {
        if (self.i >= self.s.len) return null;
        const n = std.unicode.utf8ByteSequenceLength(self.s[self.i]) catch {
            self.i += 1;
            return '?';
        };
        if (self.i + n > self.s.len) {
            self.i = self.s.len;
            return '?';
        }
        const cp = std.unicode.utf8Decode(self.s[self.i..][0..n]) catch '?';
        self.i += n;
        return cp;
    }
};

test "glyphs are found for ASCII, accents and the marks, and '?' stands in otherwise" {
    try std.testing.expectEqual(@as(usize, 'A' - 0x20), glyphIndex('A'));
    try std.testing.expectEqual(@as(usize, kAsciiCount + 0xe9 - 0xa0), glyphIndex(0xe9));
    try std.testing.expectEqual(@as(usize, kAsciiCount + kLatinCount + 7), glyphIndex(0x2026));
    try std.testing.expectEqual(@as(usize, '?' - 0x20), glyphIndex(0x3042));
}

test "bad UTF-8 reads as question marks rather than stopping" {
    var it = Utf8{ .s = "a\xffb\xe2\x80" };
    try std.testing.expectEqual(@as(?u21, 'a'), it.next());
    try std.testing.expectEqual(@as(?u21, '?'), it.next());
    try std.testing.expectEqual(@as(?u21, 'b'), it.next());
    try std.testing.expectEqual(@as(?u21, '?'), it.next());
    try std.testing.expectEqual(@as(?u21, null), it.next());
}
