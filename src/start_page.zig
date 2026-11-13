//! The start menu's front page in its modern dress, for the series' 40th
//! anniversary: night falling over the title, gold motes drifting up through
//! it, the Triforce glowing over the name, and the menu down the right in
//! real type. The old page, all 8x8 debug font, is still there as the retro
//! one (StartMenuStyle in the ini); this only draws, and says where things
//! are so a click lands where they're drawn. What the entries do is
//! menu.zig's, the same either way.
const std = @import("std");
const c = @import("sdl.zig").c;
const ui = @import("tools_draw.zig");
const kit = @import("menu_kit.zig");

const Color = ui.Color;
const Paint = ui.Paint;

/// Widescreen, where the retro page is 4:3.
pub const kW: f32 = 960;
pub const kH: f32 = 540;

/// What an entry is, which is how it's drawn.
pub const Role = enum { entry, play, randomizer, update };

pub const Item = struct {
    label: []const u8,
    role: Role = .entry,
    /// A hidden entry takes no room and catches no clicks.
    shown: bool = true,
};

/// A button and what it does, along the bottom.
pub const Hint = struct { key: []const u8, action: []const u8 };

pub const State = struct {
    items: []const Item,
    cursor: usize,
    /// Whether the game can start, said under Play.
    assets_line: []const u8,
    assets_ok: bool,
    /// A second line under it, for what to do about it.
    assets_note: []const u8 = "",
    /// What just happened, or that there are edits to save.
    status: []const u8 = "",
    status_warn: bool = false,
    version: []const u8,
    hints: []const Hint,
    /// Seconds, for what moves.
    time: f32,
    /// A question is up over the page: it steps back behind it.
    dimmed: bool = false,
    /// Nintendo's anniversary banner, when StartBanner asks for it and it's
    /// been fetched: hung small in the bottom left corner.
    logo: ?*c.SDL_Texture = null,
    /// Its width over its height.
    logo_aspect: f32 = 1,
};

pub const Line = struct {
    text: []const u8,
    tone: enum { plain, dim, warn, accent } = .dim,
};

pub const Dialog = struct {
    box: kit.Rect,
    title: []const u8,
    lines: []const Line = &.{},
    choices: []const []const u8 = &.{},
    choice_rects: []const kit.Rect = &.{},
    picked: usize = 0,
    /// A bar, 0 to 1, for a download.
    progress: ?f32 = null,
};

// ------------------------------------------------------------------ colors

const kSkyTop = Color.hex(0x050912);
const kSkyBottom = Color.hex(0x0b1b24);
pub const kGoldHi = Color.hex(0xfff1c1);
pub const kGold = Color.hex(0xe6bf62);
pub const kGoldDeep = Color.hex(0xb07f2a);
pub const kCream = Color.hex(0xf4ecd8);
pub const kMuted = Color.hex(0x93a6ae);
pub const kDim = Color.hex(0x5f7279);
pub const kTeal = Color.hex(0x5fd0cc);
pub const kViolet = Color.hex(0x9a88ff);
pub const kOk = Color.hex(0x7fe0aa);
pub const kWarn = Color.hex(0xf5b45b);
pub const kChip = Color.hex(0x0f1c23);
pub const kChipLine = Color.hex(0x34464f);

// ------------------------------------------------------------------ layout

/// The title's column on the left, and the menu's on the right.
const kTitleX: f32 = 300;
/// The middle of the rings round the title, and how big the whole of it is
/// next to how it was first drawn.
const kTitleY: f32 = 252;
const kTitleScale: f32 = 1.3;
/// The outer ring's radius.
const kRingR: f32 = 162 * kTitleScale;
const kMenuX: f32 = 620;
const kMenuW: f32 = 250;
const kRowH: f32 = 30;
const kPlayH: f32 = 50;
/// From Play's top to Randomizer's: Play, and the two lines under it.
const kPlayToRando: f32 = kPlayH + 56;
const kRandoH: f32 = 36;
/// The space the menu is centered in, between the Update button and the
/// footer's rule.
const kMenuTop: f32 = 64;
const kMenuBottom: f32 = 488;
pub const kFooterY: f32 = 500;

/// A sub-screen's header: its name, and the rule under it. What it shows
/// goes between that and the footer.
pub const kHeaderRule: f32 = 86;
pub const kBodyTop: f32 = 104;
pub const kBodyBottom: f32 = 488;

/// The way back, at the top right of a sub-screen.
pub fn backRect() kit.Rect {
    return .{ .x = kW - 40 - 96, .y = 30, .w = 96, .h = 28 };
}

fn shownEntries(items: []const Item) usize {
    var n: usize = 0;
    for (items) |it| n += @intFromBool(it.shown and it.role == .entry);
    return n;
}

/// Where the menu's first row goes: the whole of it, rows, Play and
/// Randomizer, centered top to bottom.
fn menuTop(items: []const Item) f32 {
    const rows: f32 = @floatFromInt(shownEntries(items));
    const total = rows * kRowH + 18 + kPlayToRando + kRandoH;
    return @round(kMenuTop + (kMenuBottom - kMenuTop - total) / 2);
}

fn playRect(items: []const Item) kit.Rect {
    const rows: f32 = @floatFromInt(shownEntries(items));
    return .{ .x = kMenuX, .y = menuTop(items) + rows * kRowH + 18, .w = kMenuW, .h = kPlayH };
}

fn randoRect(items: []const Item) kit.Rect {
    const p = playRect(items);
    return .{ .x = kMenuX + 20, .y = p.y + kPlayToRando, .w = kMenuW - 40, .h = kRandoH };
}

fn updateRect(p: *const Paint, label: []const u8) kit.Rect {
    const w = p.textWidth(.strong, label) + 44;
    return .{ .x = kW - 24 - w, .y = 18, .w = w, .h = 28 };
}

/// Where entry `i` is, drawn and clicked. Rows are wider than their words,
/// so aiming at a short one still lands.
pub fn entryRect(p: *const Paint, items: []const Item, i: usize) kit.Rect {
    const it = items[i];
    if (!it.shown) return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    return switch (it.role) {
        .play => playRect(items),
        .randomizer => randoRect(items),
        .update => updateRect(p, it.label),
        .entry => blk: {
            var slot: f32 = 0;
            for (items[0..i]) |o| slot += @floatFromInt(@intFromBool(o.shown and o.role == .entry));
            break :blk .{ .x = kMenuX, .y = menuTop(items) + slot * kRowH, .w = kMenuW, .h = kRowH - 2 };
        },
    };
}

// ------------------------------------------------------------------- page

pub const Page = struct {
    paint: Paint,
    /// A soft round glow, white, tinted as it's drawn.
    glow: ?*c.SDL_Texture,

    pub fn init(r: *c.SDL_Renderer) Page {
        return initScaled(r, 1);
    }

    /// At a window's pixel density: 2 on a Retina screen, so the type is
    /// baked sharp rather than stretched.
    pub fn initScaled(r: *c.SDL_Renderer, scale: f32) Page {
        return .{
            .paint = Paint.initStyles(r, scale, std.EnumSet(ui.Style).initMany(&.{ .small, .body, .strong, .item, .eyebrow, .subtitle, .title, .button, .headline, .hero_eyebrow, .hero_subtitle, .hero_small, .hero_chip })),
            .glow = makeGlow(r),
        };
    }

    /// The same night for another window, the tools': at its pixel density,
    /// with its own text styles baked as well as the sub-screens'.
    pub fn initFor(r: *c.SDL_Renderer, scale: f32, styles: std.EnumSet(ui.Style)) Page {
        var all = styles;
        all.setUnion(std.EnumSet(ui.Style).initMany(&.{ .small, .body, .strong, .item, .eyebrow, .subtitle, .button, .headline }));
        return .{ .paint = Paint.initStyles(r, scale, all), .glow = makeGlow(r) };
    }

    pub fn deinit(self: *Page) void {
        self.paint.deinit();
        if (self.glow) |t| c.SDL_DestroyTexture(t);
    }

    pub fn draw(self: *const Page, s: State) void {
        const r = self.paint.r;
        _ = c.SDL_SetRenderDrawBlendMode(r, c.SDL_BLENDMODE_BLEND);
        self.sky(s.time);
        self.motes(s.time, 1);
        self.title(s.time);
        if (s.logo) |tex| self.banner(tex, s.logo_aspect, s.time);
        self.menu(s);
        self.footerBar(s.hints, s.version, kDim);
        // What just happened, under the title.
        if (s.status.len != 0) {
            const col = if (s.status_warn) kGold else kTeal;
            const p = &self.paint;
            p.textEx(.small, kTitleX - p.textWidthTracked(.small, s.status, 1.5) / 2, kTitleY + kRingR + 12, col, col, 1.5, s.status);
        }
        if (s.dimmed) self.dim();
    }

    /// Everything steps back behind a question.
    pub fn dim(self: *const Page) void {
        self.paint.fill(.{ .x = 0, .y = 0, .w = kW, .h = kH }, Color.hex(0x000000).alpha(150));
    }

    // ---------------------------------------------------------- the sky

    fn sky(self: *const Page, t: f32) void {
        const p = &self.paint;
        gradient(p.r, .{ .x = 0, .y = 0, .w = kW, .h = kH }, kSkyTop, kSkyBottom, .vertical);
        // A cool light behind the title, and a warmer one low on the right
        // where the menu is, like a sky going from night to dawn.
        self.glowAt(kTitleX, kTitleY + 4, 300 * kTitleScale, Color.hex(0x2a7c86).alpha(52));
        self.glowAt(kW - 80, kH + 40, 380, Color.hex(0x7a5a2a).alpha(34));
        // Two thin rings round the title, the outer turning slowly, with
        // ticks: a dial, or an old seal.
        self.seal(t);
        // The edge between the title and the menu, fading out at both ends.
        const line = Color.hex(0x9fb6bd);
        gradient(p.r, .{ .x = 560, .y = 80, .w = 1, .h = 196 }, line.alpha(0), line.alpha(40), .vertical);
        gradient(p.r, .{ .x = 560, .y = 276, .w = 1, .h = 196 }, line.alpha(40), line.alpha(0), .vertical);
    }

    fn seal(self: *const Page, t: f32) void {
        const p = &self.paint;
        const cx = kTitleX;
        const cy = kTitleY;
        const k_s = kTitleScale;
        // A royal seal: two gold rings, and between them a band of little
        // Triforces pointing outward with a diamond between each pair,
        // turning slowly. Strokes with some width rather than hairlines,
        // which all but vanish on a dark sky.
        const r_in = 150 * k_s;
        const r_mid = (r_in + kRingR) / 2;
        ring(p.r, cx, cy, r_in, 1.6, 200, kGold.alpha(100));
        ring(p.r, cx, cy, kRingR, 1.6, 200, kGold.alpha(100));
        // A faint third ring outside, which the clasps sit on.
        ring(p.r, cx, cy, kRingR + 9 * k_s, 1, 200, kGold.alpha(34));
        const turn = t * 0.025;
        const kSlots = 36;
        var k: usize = 0;
        while (k < kSlots) : (k += 1) {
            const a = turn + @as(f32, @floatFromInt(k)) * std.math.tau / kSlots;
            if (k % 3 == 0) {
                triforceTurned(p.r, cx + @cos(a) * r_mid, cy + @sin(a) * r_mid, 10 * k_s, a, kGoldHi.alpha(170), kGoldDeep.alpha(170));
            } else {
                diamond(p.r, cx + @cos(a) * r_mid, cy + @sin(a) * r_mid, 1.8 * k_s, kGold.alpha(110));
            }
        }
        // Clasps at the four points, still while the band turns: a diamond
        // with a smaller one inside, and a little one each side along the
        // ring.
        const r_clasp = kRingR + 9 * k_s;
        for ([_]f32{ -std.math.pi / 2.0, 0, std.math.pi / 2.0, std.math.pi }) |a| {
            const x = cx + @cos(a) * r_clasp;
            const y = cy + @sin(a) * r_clasp;
            self.glowAt(x, y, 16 * k_s, kGold.alpha(50));
            diamond(p.r, x, y, 6 * k_s, kGold);
            diamond(p.r, x, y, 2.5 * k_s, kGoldHi);
            for ([_]f32{ -1, 1 }) |side| {
                const b = a + side * 0.07;
                diamond(p.r, cx + @cos(b) * r_clasp, cy + @sin(b) * r_clasp, 2 * k_s, kGold.alpha(160));
            }
        }
    }

    /// Specks of gold, and the odd one of teal, rising slowly and swaying,
    /// each twinkling in its own time. Worked out from the time alone, so
    /// there's nothing to keep.
    fn motes(self: *const Page, t: f32, strength: f32) void {
        self.motesIn(t, strength, kW, kH);
    }

    fn motesIn(self: *const Page, t: f32, strength: f32, w: f32, h: f32) void {
        const span = h + 40;
        var i: u32 = 0;
        while (i < 64) : (i += 1) {
            const hs = hash(i);
            const rx = unit(hs, 0);
            const ry = unit(hs, 1);
            const speed = 6 + unit(hs, 2) * 12;
            const sway = 4 + unit(hs, 3) * 12;
            const freq = 0.15 + unit(hs, 4) * 0.35;
            const phase = unit(hs, 5) * std.math.tau;
            const size = 0.7 + unit(hs, 6) * 1.6;
            const teal = unit(hs, 7) < 0.22;
            const y = h + 20 - @mod(t * speed + ry * span, span);
            const x = rx * w + @sin(t * freq + phase) * sway;
            const tw = 0.5 + 0.5 * @sin(t * (0.8 + unit(hs, 2)) + phase * 3);
            // Fading in off the bottom and out toward the top.
            const edge = smooth(h + 20, h - 40, y) * smooth(-10, 90, y);
            const a = tw * edge * strength;
            if (a <= 0.01) continue;
            const col = if (teal) kTeal else Color.hex(0xffd98a);
            self.glowAt(x, y, size * 6, col.alpha(@intFromFloat(55 * a)));
            self.paint.disc(x, y, size * 0.75, Color.hex(0xfff6dc).alpha(@intFromFloat(230 * a)));
        }
    }

    // -------------------------------------------------------- the title

    fn title(self: *const Page, t: f32) void {
        const p = &self.paint;
        const cx = kTitleX;
        const k = kTitleScale;
        // Laid out from the rings' middle, so it all grows together.
        const at = struct {
            fn y(off: f32) f32 {
                return @round(kTitleY + off * kTitleScale);
            }
        }.y;

        // The Triforce, breathing a little light.
        const breath = 0.75 + 0.25 * @sin(t * 1.3);
        self.glowAt(cx, at(-88), 100 * k, kGold.alpha(@intFromFloat(50 * breath)));
        triforce(p.r, cx, at(-120), 58 * k, 1.6 * k);

        const legend = "THE LEGEND OF";
        p.textEx(.hero_eyebrow, cx - p.textWidthTracked(.hero_eyebrow, legend, 5 * k) / 2, at(-52), kGoldHi, kGold, 5 * k, legend);
        // The name, in gold that darkens toward its foot, over a faint
        // shadow to lift it off the sky.
        const name = "ZELDA";
        const nw = p.textWidthTracked(.title, name, 7 * k);
        const shade = Color.hex(0x000000).alpha(110);
        p.textEx(.title, cx - nw / 2 + 1, at(-39) + 3, shade, shade, 7 * k, name);
        p.textEx(.title, cx - nw / 2, at(-39), kGoldHi, kGoldDeep, 7 * k, name);

        // A LINK TO THE PAST, and this port's DX in a chip after it.
        const sub = "A LINK TO THE PAST";
        const sw = p.textWidthTracked(.hero_subtitle, sub, 2.5 * k);
        const chip_w: f32 = @round(32 * k);
        const chip_gap = 10 * k;
        const left = cx - (sw + chip_gap + chip_w) / 2;
        p.textEx(.hero_subtitle, left, at(34), kCream, Color.hex(0xd5c9ad), 2.5 * k, sub);
        const chip = ui.Rect{ .x = left + sw + chip_gap, .y = at(40), .w = chip_w, .h = @round(18 * k) };
        p.fillRound(chip, 4 * k, kTeal);
        p.textCentered(.hero_chip, chip.x + chip.w / 2, chip.y + (chip.h - p.lineHeight(.hero_chip)) / 2, Color.hex(0x05211f), "DX");

        // The anniversary: a rule with a diamond each side of the words.
        const words = "40TH ANNIVERSARY";
        const ww = p.textWidthTracked(.hero_eyebrow, words, 4 * k);
        const wy = at(80);
        const mid_y = wy + p.lineHeight(.hero_eyebrow) / 2;
        p.textEx(.hero_eyebrow, cx - ww / 2, wy, kGoldHi, kGold, 4 * k, words);
        const gap = 14 * k;
        const rule_w = 62 * k;
        diamond(p.r, cx - ww / 2 - gap, mid_y, 3.5 * k, kGold);
        diamond(p.r, cx + ww / 2 + gap, mid_y, 3.5 * k, kGold);
        gradient(p.r, .{ .x = cx - ww / 2 - gap - 8 - rule_w, .y = mid_y, .w = rule_w, .h = 1 }, kGold.alpha(0), kGold.alpha(150), .horizontal);
        gradient(p.r, .{ .x = cx + ww / 2 + gap + 8, .y = mid_y, .w = rule_w, .h = 1 }, kGold.alpha(150), kGold.alpha(0), .horizontal);
        const years = "1986  \xc2\xb7  2026";
        p.textEx(.hero_small, cx - p.textWidthTracked(.hero_small, years, 3 * k) / 2, at(102), kMuted, kMuted, 3 * k, years);
    }

    /// Nintendo's banner, small in the bottom left corner under the seal,
    /// hanging in a little warm light and drifting a breath up and down.
    fn banner(self: *const Page, tex: *c.SDL_Texture, aspect: f32, t: f32) void {
        const p = &self.paint;
        const h: f32 = 112;
        const w = h * aspect;
        const x: f32 = 24;
        const top = kFooterY - 10 - h + 1.5 * @sin(t * 0.9);
        self.glowAt(x + w / 2, top + h * 0.42, h * 0.7, kGold.alpha(34));
        // A soft shadow on the sky behind it.
        _ = c.SDL_SetTextureColorMod(tex, 0, 0, 0);
        _ = c.SDL_SetTextureAlphaMod(tex, 90);
        _ = c.SDL_RenderTexture(p.r, tex, null, &.{ .x = x + 2, .y = top + 3, .w = w, .h = h });
        _ = c.SDL_SetTextureColorMod(tex, 255, 255, 255);
        _ = c.SDL_SetTextureAlphaMod(tex, 255);
        _ = c.SDL_RenderTexture(p.r, tex, null, &.{ .x = x, .y = top, .w = w, .h = h });
    }

    // --------------------------------------------------------- the menu

    fn menu(self: *const Page, s: State) void {
        const p = &self.paint;
        for (s.items, 0..) |it, i| {
            if (!it.shown) continue;
            const box = entryRect(p, s.items, i);
            const picked = i == s.cursor;
            switch (it.role) {
                .entry => self.row(box, it.label, picked, s.time),
                .play => self.play(box, it.label, picked, s.time),
                .randomizer => self.randomizer(box, it.label, picked, s.time),
                .update => self.update(box, it.label, picked),
            }
        }

        // Whether the game can start, under Play.
        const pr = playRect(s.items);
        const col = if (s.assets_ok) kOk else kWarn;
        p.textEx(.small, pr.x + pr.w / 2 - p.textWidthTracked(.small, s.assets_line, 1.5) / 2, pr.y + pr.h + 8, col, col, 1.5, s.assets_line);
        if (s.assets_note.len != 0)
            p.textCentered(.small, pr.x + pr.w / 2, pr.y + pr.h + 26, kMuted, s.assets_note);
    }

    /// A row of the menu: picked, a band of light fading out to the right,
    /// a gold edge and a diamond before the word.
    fn row(self: *const Page, box: kit.Rect, label: []const u8, picked: bool, t: f32) void {
        const p = &self.paint;
        const text_x = box.x + 26;
        if (picked) {
            gradient(p.r, .{ .x = box.x, .y = box.y, .w = box.w, .h = box.h }, kTeal.alpha(58), kTeal.alpha(0), .horizontal);
            p.fill(.{ .x = box.x, .y = box.y, .w = 2, .h = box.h }, kGold);
            const pulse = 0.8 + 0.2 * @sin(t * 4);
            diamond(p.r, box.x + 13, box.y + box.h / 2, 4 * pulse + 0.5, kGoldHi);
        }
        p.text(.item, text_x, box.y + (box.h - p.lineHeight(.item)) / 2, if (picked) kCream else kMuted, label);
    }

    /// Play: the one thing the page is for, in gold.
    fn play(self: *const Page, box: kit.Rect, label: []const u8, picked: bool, t: f32) void {
        const p = &self.paint;
        const rect = ui.Rect{ .x = box.x, .y = box.y, .w = box.w, .h = box.h };
        if (picked) {
            const pulse = 0.7 + 0.3 * @sin(t * 2.4);
            self.glowAt(rect.x + rect.w / 2, rect.y + rect.h / 2, rect.w * 0.7, kGold.alpha(@intFromFloat(90 * pulse)));
            sideDiamonds(p.r, rect, kGoldHi);
        }
        p.box(rect, rect.h / 2, 1.5, if (picked) kGoldHi else Color.hex(0xe6c56f), if (picked) Color.hex(0xf0cd72) else Color.hex(0xd2aa52));
        // A sheen across its top half.
        p.fillRound(.{ .x = rect.x + 6, .y = rect.y + 4, .w = rect.w - 12, .h = rect.h / 2 - 4 }, (rect.h / 2 - 4) / 2, Color.hex(0xffffff).alpha(if (picked) 46 else 30));
        const up = upper(label);
        const tw = p.textWidthTracked(.button, up.slice(), 7);
        p.textEx(.button, rect.x + rect.w / 2 - tw / 2, rect.y + (rect.h - p.lineHeight(.button)) / 2 + 1, Color.hex(0x3b2606), Color.hex(0x1c1102), 7, up.slice());
    }

    /// Randomizer: smaller, in a color of its own, since it plays something
    /// other than the port.
    fn randomizer(self: *const Page, box: kit.Rect, label: []const u8, picked: bool, t: f32) void {
        const p = &self.paint;
        const rect = ui.Rect{ .x = box.x, .y = box.y, .w = box.w, .h = box.h };
        if (picked) {
            const pulse = 0.7 + 0.3 * @sin(t * 2.4);
            self.glowAt(rect.x + rect.w / 2, rect.y + rect.h / 2, rect.w * 0.6, kViolet.alpha(@intFromFloat(60 * pulse)));
            sideDiamonds(p.r, rect, kViolet);
        }
        const inside = if (picked) Color.hex(0x2a2550) else Color.hex(0x141a2c);
        p.box(rect, rect.h / 2, 1.5, if (picked) Color.hex(0xc7bcff) else kViolet.alpha(200), inside);
        p.textCentered(.item, rect.x + rect.w / 2, rect.y + (rect.h - p.lineHeight(.item)) / 2, if (picked) kCream else Color.hex(0xc9c0ff), label);
    }

    /// A newer version, offered in the top corner.
    fn update(self: *const Page, box: kit.Rect, label: []const u8, picked: bool) void {
        const p = &self.paint;
        const rect = ui.Rect{ .x = box.x, .y = box.y, .w = box.w, .h = box.h };
        p.box(rect, rect.h / 2, if (picked) 2 else 1, if (picked) kGoldHi else kOk, if (picked) Color.hex(0x1c3328) else Color.hex(0x0f2019));
        p.disc(rect.x + 15, rect.y + rect.h / 2, 3.5, if (picked) kGoldHi else kOk);
        p.text(.strong, rect.x + 26, rect.y + (rect.h - p.lineHeight(.strong)) / 2, if (picked) kGoldHi else kOk, label);
    }

    // ------------------------------------------------------- the footer

    /// The rule along the bottom, what the buttons do, a key in a chip and
    /// then what it does, and a few words at the right.
    pub fn footerBar(self: *const Page, hints: []const Hint, right: []const u8, right_col: Color) void {
        const p = &self.paint;
        const rule = Color.hex(0x9fb6bd);
        gradient(p.r, .{ .x = 24, .y = kFooterY, .w = kW / 2 - 24, .h = 1 }, rule.alpha(0), rule.alpha(46), .horizontal);
        gradient(p.r, .{ .x = kW / 2, .y = kFooterY, .w = kW / 2 - 24, .h = 1 }, rule.alpha(46), rule.alpha(0), .horizontal);

        var x: f32 = 28;
        const y: f32 = kFooterY + 12;
        for (hints) |h| {
            const kw = @max(p.textWidth(.small, h.key) + 12, 20);
            p.box(.{ .x = x, .y = y, .w = kw, .h = 18 }, 5, 1, kChipLine, kChip);
            p.textCentered(.small, x + kw / 2, y, kCream, h.key);
            x += kw + 6;
            p.text(.small, x, y, kMuted, h.action);
            x += p.textWidth(.small, h.action) + 18;
        }
        if (right.len != 0) {
            const tw = p.textWidthTracked(.small, right, 1.2);
            p.textEx(.small, kW - 28 - tw, y, right_col, right_col, 1.2, right);
        }
    }

    // ---------------------------------------------------- sub-screens

    /// A sub-screen's sky and header: the same night as the front page with
    /// fewer motes, a small Triforce by the screen's name, and the way back.
    pub fn backdrop(self: *const Page, t: f32, name: []const u8, back_picked: bool) void {
        const p = &self.paint;
        _ = c.SDL_SetRenderDrawBlendMode(p.r, c.SDL_BLENDMODE_BLEND);
        gradient(p.r, .{ .x = 0, .y = 0, .w = kW, .h = kH }, kSkyTop, kSkyBottom, .vertical);
        self.glowAt(150, 40, 340, Color.hex(0x2a7c86).alpha(40));
        self.glowAt(kW - 80, kH + 40, 380, Color.hex(0x7a5a2a).alpha(30));
        self.motes(t, 0.55);

        const breath = 0.75 + 0.25 * @sin(t * 1.3);
        self.glowAt(56, 42, 34, kGold.alpha(@intFromFloat(46 * breath)));
        triforce(p.r, 56, 28, 26, 1);
        p.textEx(.headline, 86, 22, kGoldHi, kGoldDeep, 3, name);
        const crumb = "A LINK TO THE PAST DX";
        p.textEx(.small, 88, 58, kDim, kDim, 2, crumb);

        const b = backRect();
        const br = ui.Rect{ .x = b.x, .y = b.y, .w = b.w, .h = b.h };
        p.box(br, br.h / 2, 1, if (back_picked) kGold else kChipLine, if (back_picked) Color.hex(0x1d2a2f) else kChip);
        const label = "\xe2\x86\x90  Back";
        p.textCentered(.strong, br.x + br.w / 2, br.y + (br.h - p.lineHeight(.strong)) / 2, if (back_picked) kGoldHi else kCream, label);

        const rule = kGold;
        gradient(p.r, .{ .x = 40, .y = kHeaderRule, .w = (kW - 80) / 2, .h = 1 }, rule.alpha(10), rule.alpha(90), .horizontal);
        gradient(p.r, .{ .x = kW / 2, .y = kHeaderRule, .w = (kW - 80) / 2, .h = 1 }, rule.alpha(90), rule.alpha(10), .horizontal);
        diamond(p.r, kW / 2, kHeaderRule + 0.5, 3.5, kGold);
    }

    /// The sub-screens' night, for a window of any size: the sky, its two
    /// lights, and motes at `strength`.
    pub fn night(self: *const Page, t: f32, w: f32, h: f32, strength: f32) void {
        const p = &self.paint;
        _ = c.SDL_SetRenderDrawBlendMode(p.r, c.SDL_BLENDMODE_BLEND);
        gradient(p.r, .{ .x = 0, .y = 0, .w = w, .h = h }, kSkyTop, kSkyBottom, .vertical);
        self.glowAt(150, 40, 340, Color.hex(0x2a7c86).alpha(40));
        self.glowAt(w - 80, h + 40, 380, Color.hex(0x7a5a2a).alpha(30));
        self.motesIn(t, strength, w, h);
    }

    /// The Triforce `h` tall with its top at (cx, top), breathing light.
    pub fn crest(self: *const Page, cx: f32, top: f32, h: f32, t: f32) void {
        const breath = 0.75 + 0.25 * @sin(t * 1.3);
        self.glowAt(cx, top + h / 2 + 1, h * 1.3, kGold.alpha(@intFromFloat(46 * breath)));
        triforce(self.paint.r, cx, top, h, h / 26);
    }

    /// The gold rule under a header, brightest in the middle where a
    /// diamond sits on it.
    pub fn goldRule(self: *const Page, x: f32, y: f32, w: f32) void {
        const r = self.paint.r;
        gradient(r, .{ .x = x, .y = y, .w = w / 2, .h = 1 }, kGold.alpha(10), kGold.alpha(90), .horizontal);
        gradient(r, .{ .x = x + w / 2, .y = y, .w = w / 2, .h = 1 }, kGold.alpha(90), kGold.alpha(10), .horizontal);
        diamond(r, x + w / 2, y + 0.5, 3.5, kGold);
    }

    /// A line fading from `a` to `b`, along or down.
    pub fn fade(self: *const Page, rect: kit.Rect, a: Color, b: Color, across: bool) void {
        gradient(self.paint.r, .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h }, a, b, if (across) .horizontal else .vertical);
    }

    /// The front page's Play, anywhere.
    pub fn playButton(self: *const Page, box: kit.Rect, label: []const u8, picked: bool, t: f32) void {
        self.play(box, label, picked, t);
    }

    /// The band of light under a picked row, with its gold edge and diamond,
    /// as the front page's menu has it.
    pub fn band(self: *const Page, box: kit.Rect, picked: bool, t: f32) void {
        if (!picked) return;
        const p = &self.paint;
        gradient(p.r, .{ .x = box.x, .y = box.y, .w = box.w, .h = box.h }, kTeal.alpha(58), kTeal.alpha(0), .horizontal);
        p.fill(.{ .x = box.x, .y = box.y, .w = 2, .h = box.h }, kGold);
        const pulse = 0.8 + 0.2 * @sin(t * 4);
        diamond(p.r, box.x + 13, box.y + box.h / 2, 4 * pulse + 0.5, kGoldHi);
    }

    /// A heading in a list: gold capitals, and a rule fading out after them.
    pub fn heading(self: *const Page, x: f32, y: f32, w: f32, h: f32, label: []const u8) void {
        const p = &self.paint;
        var up_buf = upper(label);
        const text = up_buf.slice();
        const ty = y + (h - p.lineHeight(.eyebrow)) / 2 + 1;
        p.textEx(.eyebrow, x, ty, kGoldHi, kGold, 3, text);
        const end = x + p.textWidthTracked(.eyebrow, text, 3) + 12;
        if (end < x + w) gradient(p.r, .{ .x = end, .y = y + h / 2, .w = x + w - end, .h = 1 }, kGold.alpha(90), kGold.alpha(0), .horizontal);
    }

    /// A dark card to put things on.
    pub fn panel(self: *const Page, rect: kit.Rect) void {
        const p = &self.paint;
        const r = ui.Rect{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
        p.box(r, 12, 1, Color.hex(0x22323a), Color.hex(0x0a141a).alpha(236));
        gradient(p.r, .{ .x = r.x + 16, .y = r.y, .w = r.w / 2 - 16, .h = 1 }, kGold.alpha(0), kGold.alpha(70), .horizontal);
        gradient(p.r, .{ .x = r.x + r.w / 2, .y = r.y, .w = r.w / 2 - 16, .h = 1 }, kGold.alpha(70), kGold.alpha(0), .horizontal);
    }

    /// A thin bar beside a list that runs past what shows: `top` and `len`
    /// are how far down the part showing starts and how much of it there is,
    /// each 0 to 1.
    pub fn scrollbar(self: *const Page, x: f32, y: f32, h: f32, top: f32, len: f32) void {
        const p = &self.paint;
        p.fillRound(.{ .x = x, .y = y, .w = 3, .h = h }, 1.5, kChipLine.alpha(150));
        p.fillRound(.{ .x = x, .y = y + h * top, .w = 3, .h = @max(h * len, 12) }, 1.5, kGold.alpha(200));
    }

    /// Small arrows either side of a value that left and right change.
    pub fn chevrons(self: *const Page, left: f32, right: f32, cy: f32, col: Color) void {
        const r = self.paint.r;
        const s: f32 = 4;
        triangle(r, .{ left, cy }, .{ left + s, cy - s }, .{ left + s, cy + s }, col);
        triangle(r, .{ right, cy }, .{ right - s, cy - s }, .{ right - s, cy + s }, col);
    }

    /// A mark for something done, or the outline of one not yet.
    pub fn mark(self: *const Page, cx: f32, cy: f32, on: bool) void {
        const r = self.paint.r;
        if (on) {
            self.glowAt(cx, cy, 14, kGold.alpha(70));
            diamond(r, cx, cy, 6, kGold);
            diamond(r, cx, cy - 1, 2.5, kGoldHi);
        } else {
            diamond(r, cx, cy, 6, kChipLine);
            diamond(r, cx, cy, 4.5, Color.hex(0x0a141a));
        }
    }

    /// Text wrapped to `w`, a line every `line_h`, at most `max_lines` of
    /// them. Returns where the next line would go.
    pub fn wrap(self: *const Page, style: ui.Style, x: f32, y: f32, w: f32, line_h: f32, col: Color, text: []const u8, max_lines: usize) f32 {
        const p = &self.paint;
        var rest = std.mem.trim(u8, text, " ");
        var yy = y;
        var n: usize = 0;
        while (rest.len != 0 and n < max_lines) : (n += 1) {
            const cut = p.breakAt(style, rest, w);
            p.text(style, x, yy, col, std.mem.trimEnd(u8, rest[0..cut], " "));
            rest = std.mem.trimStart(u8, rest[cut..], " ");
            yy += line_h;
        }
        return yy;
    }

    /// One of the big choices, the randomizer page's: a card with a name in
    /// the title's type and a line under it, lit when picked.
    pub fn card(self: *const Page, rect: kit.Rect, name: []const u8, sub: []const u8, picked: bool, soon: bool, t: f32) void {
        const p = &self.paint;
        const r = ui.Rect{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
        const accent = if (soon) kDim else kViolet;
        if (picked) {
            const pulse = 0.7 + 0.3 * @sin(t * 2.4);
            self.glowAt(r.x + r.w / 2, r.y + r.h / 2, r.w * 0.62, accent.alpha(@intFromFloat(46 * pulse)));
        }
        p.shadow(r, 16);
        p.box(r, 16, if (picked) 1.5 else 1, if (picked) kGoldHi else accent.alpha(150), if (picked) Color.hex(0x18183a) else Color.hex(0x0d1424));
        const cx = r.x + r.w / 2;
        // A Triforce for the one made here; three diamonds, a seed's
        // shuffle, for the one from alttpr.com.
        if (soon) {
            triforce(p.r, cx, r.y + 34, 40, 1.2);
            p.fill(.{ .x = r.x + 1, .y = r.y + 30, .w = r.w - 2, .h = 50 }, Color.hex(0x0d1424).alpha(150));
        } else {
            const col = if (picked) kGoldHi else Color.hex(0xc7bcff);
            diamond(p.r, cx - 22, r.y + 60, 9, col.alpha(200));
            diamond(p.r, cx, r.y + 48, 11, col);
            diamond(p.r, cx + 22, r.y + 60, 9, col.alpha(200));
        }
        var up = upper(name);
        const nw = p.textWidthTracked(.subtitle, up.slice(), 2.5);
        p.textEx(.subtitle, cx - nw / 2, r.y + 104, if (picked) kGoldHi else kCream, if (picked) kGold else Color.hex(0xd5c9ad), 2.5, up.slice());
        if (soon) {
            const pw = p.textWidth(.strong, sub) + 28;
            const pill = ui.Rect{ .x = cx - pw / 2, .y = r.y + 146, .w = pw, .h = 24 };
            p.box(pill, 12, 1, kWarn.alpha(160), Color.hex(0x2a1d0c));
            p.textCentered(.strong, cx, pill.y + (pill.h - p.lineHeight(.strong)) / 2, kWarn, sub);
        } else {
            p.textCentered(.body, cx, r.y + 150, if (picked) kCream else kMuted, sub);
        }
    }

    // ------------------------------------------------------ questions

    /// A question over the page: a dark card edged in gold, its title in
    /// the title's type, and its answers as pills. Where it and its answers
    /// sit is menu.zig's, the same rectangles the retro page's clicks use.
    pub fn dialog(self: *const Page, d: Dialog) void {
        const p = &self.paint;
        const box = ui.Rect{ .x = d.box.x, .y = d.box.y, .w = d.box.w, .h = d.box.h };
        const cx = box.x + box.w / 2;
        p.shadow(box, 14);
        p.box(box, 14, 1, kGold.alpha(110), Color.hex(0x0c161c));
        // A diamond on the top edge, like a clasp.
        diamond(p.r, cx, box.y, 5, kGold);

        p.textEx(.subtitle, cx - p.textWidthTracked(.subtitle, d.title, 2) / 2, box.y + 22, kGoldHi, kGold, 2, d.title);
        var y = box.y + 56;
        for (d.lines) |line| {
            const col = switch (line.tone) {
                .plain => kCream,
                .dim => kMuted,
                .warn => kWarn,
                .accent => kTeal,
            };
            p.textCentered(.body, cx, y, col, line.text);
            y += 21;
        }

        if (d.progress) |frac| {
            const bar = ui.Rect{ .x = box.x + 50, .y = box.y + 92, .w = box.w - 100, .h = 10 };
            p.fillRound(bar, 5, Color.hex(0x1a2a32));
            if (frac > 0) p.fillRound(.{ .x = bar.x, .y = bar.y, .w = @max(bar.w * frac, 10), .h = bar.h }, 5, kTeal);
        }

        for (d.choices, d.choice_rects, 0..) |label, cr, i| {
            const rect = ui.Rect{ .x = cr.x, .y = cr.y, .w = cr.w, .h = cr.h };
            const picked = i == d.picked;
            if (picked) {
                p.box(rect, rect.h / 2, 1.5, kGoldHi, Color.hex(0xe9c46c));
                p.textCentered(.item, rect.x + rect.w / 2, rect.y + (rect.h - p.lineHeight(.item)) / 2, Color.hex(0x2a1a04), label);
            } else {
                p.box(rect, rect.h / 2, 1, kChipLine, kChip);
                p.textCentered(.item, rect.x + rect.w / 2, rect.y + (rect.h - p.lineHeight(.item)) / 2, kMuted, label);
            }
        }
    }

    pub fn glowAt(self: *const Page, x: f32, y: f32, radius: f32, col: Color) void {
        const tex = self.glow orelse return;
        _ = c.SDL_SetTextureColorMod(tex, col.r, col.g, col.b);
        _ = c.SDL_SetTextureAlphaMod(tex, col.a);
        const dst = c.SDL_FRect{ .x = x - radius, .y = y - radius, .w = radius * 2, .h = radius * 2 };
        _ = c.SDL_RenderTexture(self.paint.r, tex, null, &dst);
    }
};

// ----------------------------------------------------------------- shapes

const Dir = enum { vertical, horizontal };

/// A rectangle shading from `a` to `b`, top to bottom or left to right.
fn gradient(r: *c.SDL_Renderer, rect: ui.Rect, a: Color, b: Color, dir: Dir) void {
    const fa = fcolor(a);
    const fb = fcolor(b);
    const tl = fa;
    const tr = if (dir == .horizontal) fb else fa;
    const bl = if (dir == .horizontal) fa else fb;
    const br = fb;
    const v = [_]c.SDL_Vertex{
        .{ .position = .{ .x = rect.x, .y = rect.y }, .color = tl, .tex_coord = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = rect.x + rect.w, .y = rect.y }, .color = tr, .tex_coord = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = rect.x + rect.w, .y = rect.y + rect.h }, .color = br, .tex_coord = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = rect.x, .y = rect.y + rect.h }, .color = bl, .tex_coord = .{ .x = 0, .y = 0 } },
    };
    const idx = [_]c_int{ 0, 1, 2, 0, 2, 3 };
    _ = c.SDL_RenderGeometry(r, null, &v, v.len, &idx, idx.len);
}

/// The Triforce, `h` tall with its top at (cx, top): three triangles a hair
/// apart, gold, lighter at the top of each.
fn triforce(r: *c.SDL_Renderer, cx: f32, top: f32, h: f32, gap: f32) void {
    const w = h * 2 / @sqrt(3.0);
    const mid = top + h / 2;
    const bottom = top + h;
    const tris = [_][3][2]f32{
        .{ .{ cx, top }, .{ cx + w / 4, mid }, .{ cx - w / 4, mid } },
        .{ .{ cx - w / 4, mid }, .{ cx, bottom }, .{ cx - w / 2, bottom } },
        .{ .{ cx + w / 4, mid }, .{ cx + w / 2, bottom }, .{ cx, bottom } },
    };
    var v: [9]c.SDL_Vertex = undefined;
    for (tris, 0..) |tri, i| {
        const gx = (tri[0][0] + tri[1][0] + tri[2][0]) / 3;
        const gy = (tri[0][1] + tri[1][1] + tri[2][1]) / 3;
        for (tri, 0..) |pt, j| {
            // Each pulled in toward its middle, which opens the gaps.
            const dx = pt[0] - gx;
            const dy = pt[1] - gy;
            const len = @sqrt(dx * dx + dy * dy);
            const k = (len - gap) / len;
            const col = if (j == 0) kGoldHi else kGoldDeep;
            v[i * 3 + j] = .{ .position = .{ .x = gx + dx * k, .y = gy + dy * k }, .color = fcolor(col), .tex_coord = .{ .x = 0, .y = 0 } };
        }
    }
    _ = c.SDL_RenderGeometry(r, null, &v, v.len, null, 0);
}

/// A small Triforce `h` tall centered on (x, y), its point toward angle
/// `a`, shading from `top` at each point to `bottom` at each base.
fn triforceTurned(r: *c.SDL_Renderer, x: f32, y: f32, h: f32, a: f32, top: Color, bottom: Color) void {
    const w = h * 2 / @sqrt(3.0);
    // Laid out pointing up around its middle, then turned: "up" becomes
    // outward along `a`.
    const ux = @cos(a);
    const uy = @sin(a);
    const at = struct {
        fn p(cx: f32, cy: f32, ox: f32, oy: f32, lx: f32, ly: f32) c.SDL_FPoint {
            // ly up is outward, lx across is along the ring.
            return .{ .x = cx + ox * ly - oy * lx, .y = cy + oy * ly + ox * lx };
        }
    }.p;
    const tris = [_][3][2]f32{
        .{ .{ 0, h / 2 }, .{ w / 4, 0 }, .{ -w / 4, 0 } },
        .{ .{ -w / 4, 0 }, .{ 0, -h / 2 }, .{ -w / 2, -h / 2 } },
        .{ .{ w / 4, 0 }, .{ w / 2, -h / 2 }, .{ 0, -h / 2 } },
    };
    var v: [9]c.SDL_Vertex = undefined;
    for (tris, 0..) |tri, i| {
        for (tri, 0..) |pt, j| {
            v[i * 3 + j] = .{ .position = at(x, y, ux, uy, pt[0], pt[1]), .color = fcolor(if (j == 0) top else bottom), .tex_coord = .{ .x = 0, .y = 0 } };
        }
    }
    _ = c.SDL_RenderGeometry(r, null, &v, v.len, null, 0);
}

fn triangle(r: *c.SDL_Renderer, a: [2]f32, b: [2]f32, d: [2]f32, col: Color) void {
    const fc = fcolor(col);
    const v = [_]c.SDL_Vertex{
        .{ .position = .{ .x = a[0], .y = a[1] }, .color = fc, .tex_coord = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = b[0], .y = b[1] }, .color = fc, .tex_coord = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = d[0], .y = d[1] }, .color = fc, .tex_coord = .{ .x = 0, .y = 0 } },
    };
    _ = c.SDL_RenderGeometry(r, null, &v, v.len, null, 0);
}

/// A small square turned on its point.
pub fn diamond(r: *c.SDL_Renderer, x: f32, y: f32, size: f32, col: Color) void {
    const fc = fcolor(col);
    const v = [_]c.SDL_Vertex{
        .{ .position = .{ .x = x, .y = y - size }, .color = fc, .tex_coord = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = x + size, .y = y }, .color = fc, .tex_coord = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = x, .y = y + size }, .color = fc, .tex_coord = .{ .x = 0, .y = 0 } },
        .{ .position = .{ .x = x - size, .y = y }, .color = fc, .tex_coord = .{ .x = 0, .y = 0 } },
    };
    const idx = [_]c_int{ 0, 1, 2, 0, 2, 3 };
    _ = c.SDL_RenderGeometry(r, null, &v, v.len, &idx, idx.len);
}

/// A diamond off each end of a picked button.
fn sideDiamonds(r: *c.SDL_Renderer, rect: ui.Rect, col: Color) void {
    diamond(r, rect.x - 12, rect.y + rect.h / 2, 4, col);
    diamond(r, rect.x + rect.w + 12, rect.y + rect.h / 2, 4, col);
}

/// A circle `width` points thick, as `segments` short quads round it.
fn ring(r: *c.SDL_Renderer, cx: f32, cy: f32, radius: f32, width: f32, segments: usize, col: Color) void {
    const fc = fcolor(col);
    var v: [2 * 257]c.SDL_Vertex = undefined;
    var idx: [6 * 256]c_int = undefined;
    const n: usize = @min(segments, 256);
    const r_in = radius - width / 2;
    const r_out = radius + width / 2;
    for (0..n + 1) |i| {
        const a = @as(f32, @floatFromInt(i)) * std.math.tau / @as(f32, @floatFromInt(n));
        v[i * 2] = .{ .position = .{ .x = cx + @cos(a) * r_in, .y = cy + @sin(a) * r_in }, .color = fc, .tex_coord = .{ .x = 0, .y = 0 } };
        v[i * 2 + 1] = .{ .position = .{ .x = cx + @cos(a) * r_out, .y = cy + @sin(a) * r_out }, .color = fc, .tex_coord = .{ .x = 0, .y = 0 } };
    }
    for (0..n) |i| {
        const b: c_int = @intCast(i * 2);
        for ([_]c_int{ 0, 1, 3, 0, 3, 2 }, 0..) |k, j| idx[i * 6 + j] = b + k;
    }
    _ = c.SDL_RenderGeometry(r, null, &v, @intCast((n + 1) * 2), &idx, @intCast(n * 6));
}

const kGlowSize = 128;

/// A soft round glow, brightest in the middle and gone by the edge.
fn makeGlow(r: *c.SDL_Renderer) ?*c.SDL_Texture {
    var px: [kGlowSize * kGlowSize]u32 = undefined;
    const mid: f32 = kGlowSize / 2;
    for (0..kGlowSize) |y| {
        for (0..kGlowSize) |x| {
            const dx = (@as(f32, @floatFromInt(x)) + 0.5 - mid) / mid;
            const dy = (@as(f32, @floatFromInt(y)) + 0.5 - mid) / mid;
            const d = @min(1, @sqrt(dx * dx + dy * dy));
            const k = 1 - d;
            const a: u32 = @intFromFloat(@round(k * k * (0.6 + 0.4 * k) * 255));
            px[y * kGlowSize + x] = 0xffffff00 | a;
        }
    }
    const tex = c.SDL_CreateTexture(r, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STATIC, kGlowSize, kGlowSize) orelse return null;
    _ = c.SDL_UpdateTexture(tex, null, &px, kGlowSize * 4);
    _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
    _ = c.SDL_SetTextureScaleMode(tex, c.SDL_SCALEMODE_LINEAR);
    return tex;
}

// ------------------------------------------------------------------ bits

fn fcolor(col: Color) c.SDL_FColor {
    return .{ .r = @as(f32, @floatFromInt(col.r)) / 255, .g = @as(f32, @floatFromInt(col.g)) / 255, .b = @as(f32, @floatFromInt(col.b)) / 255, .a = @as(f32, @floatFromInt(col.a)) / 255 };
}

fn hash(i: u32) u64 {
    var x: u64 = @as(u64, i) *% 0x9e3779b97f4a7c15 +% 0x632be59bd9b4e019;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

/// The `k`th of eight numbers from 0 to 1 in a hash.
fn unit(h: u64, k: u6) f32 {
    const b: u8 = @truncate(h >> (k * 8));
    return @as(f32, @floatFromInt(b)) / 255;
}

/// 0 at `a`, 1 at `b`, smoothly between.
fn smooth(a: f32, b: f32, x: f32) f32 {
    const t = std.math.clamp((x - a) / (b - a), 0, 1);
    return t * t * (3 - 2 * t);
}

const Upper = struct {
    buf: [48]u8 = undefined,
    len: usize = 0,
    fn slice(self: *const Upper) []const u8 {
        return self.buf[0..self.len];
    }
};

fn upper(s: []const u8) Upper {
    var u = Upper{};
    u.len = @min(s.len, u.buf.len);
    for (s[0..u.len], 0..) |ch, i| u.buf[i] = std.ascii.toUpper(ch);
    return u;
}

test "the title's rings fit between the window's top, the footer and the menu" {
    try std.testing.expect(kTitleY - kRingR >= 24);
    try std.testing.expect(kTitleY + kRingR + 12 + 16 <= kFooterY);
    try std.testing.expect(kTitleX + kRingR < 560 and kTitleX - kRingR > 24);
}

test "the menu fits between the update button and the footer" {
    const items_7 = [_]Item{ .{ .label = "a" }, .{ .label = "b" }, .{ .label = "c" }, .{ .label = "d" }, .{ .label = "e" }, .{ .label = "f" }, .{ .label = "g" }, .{ .label = "Play", .role = .play }, .{ .label = "Randomizer", .role = .randomizer } };
    const r = randoRect(&items_7);
    try std.testing.expect(menuTop(&items_7) >= kMenuTop);
    try std.testing.expect(r.y + r.h <= kMenuBottom);
    // The selected Play's diamonds stay inside the window.
    try std.testing.expect(kMenuX + kMenuW + 12 + 4 < kW);
}
