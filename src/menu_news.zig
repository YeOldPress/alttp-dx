//! The start menu's What's New: this release's notes, shown once after an
//! update to it, and again whenever the version in the corner is clicked.
//!
//! The notes are the release's own .github/release-notes/<tag>.md, built
//! into the game (build.zig), so they're there however the update came: by
//! the Update button or by hand. They're Markdown, read here only as far as
//! they use it: the title, the section headings, paragraphs and bullets,
//! with the bold, code and links taken out.
const std = @import("std");
const start_page = @import("start_page.zig");
const P = start_page;
const kit = @import("menu_kit.zig");
const Rect = kit.Rect;
const draw_mod = @import("tools_draw.zig");

pub const kPanel = Rect{ .x = 40, .y = P.kBodyTop, .w = P.kW - 80, .h = P.kBodyBottom - P.kBodyTop };
const kPad: f32 = 26;

const Kind = enum { title, heading, body, bullet, gap };

/// A line as it's drawn: wrapped to the panel already.
const Row = struct { kind: Kind, text: []const u8, indent: bool = false };

var g_arena: ?std.heap.ArenaAllocator = null;
var g_text: []const u8 = "";
var g_rows: std.ArrayList(Row) = .empty;
var g_laid = false;
/// The first row showing.
var g_top: usize = 0;

pub const Action = enum { none, leave };

pub const Input = struct {
    move: i32 = 0,
    adjust: i32 = 0,
    confirm: bool = false,
    back: bool = false,
    wheel: i32 = 0,
};

/// Opening it on `notes`, at the top.
pub fn open(alloc: std.mem.Allocator, notes: []const u8) void {
    close();
    g_arena = std.heap.ArenaAllocator.init(alloc);
    g_text = g_arena.?.allocator().dupe(u8, notes) catch "";
    g_top = 0;
    g_laid = false;
}

pub fn close() void {
    if (g_arena) |*a| a.deinit();
    g_arena = null;
    g_rows = .empty;
    g_text = "";
    g_laid = false;
}

fn rowHeight(k: Kind) f32 {
    return switch (k) {
        .title => 40,
        .heading => 36,
        .body, .bullet => 22,
        .gap => 10,
    };
}

fn styleOf(k: Kind) draw_mod.Style {
    return switch (k) {
        .title => .subtitle,
        .heading => .eyebrow,
        else => .body,
    };
}

/// How many rows fit from row `top` down.
fn visibleFrom(top: usize) usize {
    var h: f32 = 0;
    var n: usize = 0;
    const room = kPanel.h - 2 * 18;
    for (g_rows.items[@min(top, g_rows.items.len)..]) |r| {
        h += rowHeight(r.kind);
        if (h > room) break;
        n += 1;
    }
    // A heading at the very bottom goes over with what it heads.
    const rows = g_rows.items[@min(top, g_rows.items.len)..];
    while (n > 1 and n < rows.len and (rows[n - 1].kind == .heading or rows[n - 1].kind == .gap)) n -= 1;
    return n;
}

/// The furthest down the top row can go, with the last row at the bottom.
fn maxTop() usize {
    var top = g_rows.items.len;
    var h: f32 = 0;
    const room = kPanel.h - 2 * 18;
    while (top > 0) {
        h += rowHeight(g_rows.items[top - 1].kind);
        if (h > room) break;
        top -= 1;
    }
    return top;
}

pub fn input(in: Input) Action {
    if (in.back or in.confirm) return .leave;
    var step: i32 = in.move - in.wheel * 3;
    // Left and right turn a page.
    if (in.adjust != 0) step = in.adjust * @as(i32, @intCast(@max(visibleFrom(g_top), 2) - 1));
    if (step != 0) {
        const at = @as(i64, @intCast(g_top)) + step;
        g_top = @intCast(std.math.clamp(at, 0, @as(i64, @intCast(maxTop()))));
    }
    return .none;
}

/// Turns the notes into rows, wrapped to the panel, the first time it's
/// drawn (which is when there's type to measure them with).
fn layout(p: *const draw_mod.Paint) void {
    g_laid = true;
    const a = (g_arena orelse return).allocator();
    const w = kPanel.w - 2 * kPad;
    var it = std.mem.splitScalar(u8, g_text, '\n');
    var last: Kind = .gap;
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        var kind: Kind = .body;
        var rest = line;
        if (std.mem.startsWith(u8, line, "### ")) {
            kind = .heading;
            rest = line[4..];
        } else if (std.mem.startsWith(u8, line, "## ") or std.mem.startsWith(u8, line, "# ")) {
            kind = .title;
            rest = line[std.mem.indexOfScalar(u8, line, ' ').? + 1 ..];
        } else if (std.mem.startsWith(u8, line, "- ") or std.mem.startsWith(u8, line, "* ")) {
            kind = .bullet;
            rest = line[2..];
        }
        const clean = plain(a, rest) catch continue;
        // A little air before a heading or a paragraph, none between
        // bullets.
        if (g_rows.items.len != 0 and !(kind == .bullet and last == .bullet)) g_rows.append(a, .{ .kind = .gap, .text = "" }) catch return;
        if (kind == .heading) {
            g_rows.append(a, .{ .kind = .heading, .text = std.ascii.allocUpperString(a, clean) catch clean }) catch return;
        } else if (kind == .title) {
            g_rows.append(a, .{ .kind = .title, .text = clean }) catch return;
        } else {
            const style = styleOf(kind);
            const indent: f32 = if (kind == .bullet) 18 else 0;
            var left = clean;
            var first = true;
            while (left.len != 0) {
                const cut = P.padBreakAt(p, style, left, w - indent);
                g_rows.append(a, .{
                    .kind = if (kind == .bullet and first) .bullet else .body,
                    .text = std.mem.trimEnd(u8, left[0..cut], " "),
                    .indent = kind == .bullet,
                }) catch return;
                left = std.mem.trimStart(u8, left[cut..], " ");
                first = false;
            }
        }
        last = kind;
    }
}

/// A line of Markdown as plain words: no **bold**, `code` or [links](…),
/// and the PlayStation shapes as start_page draws them.
fn plain(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        const ch = s[i];
        if (ch == '*' or ch == '`') {
            i += 1;
            continue;
        }
        if (ch == '\\' and i + 1 < s.len) {
            try out.append(a, s[i + 1]);
            i += 2;
            continue;
        }
        // [text](url): the text.
        if (ch == '[') if (std.mem.indexOfScalarPos(u8, s, i, ']')) |close_at| {
            if (close_at + 1 < s.len and s[close_at + 1] == '(') if (std.mem.indexOfScalarPos(u8, s, close_at, ')')) |end| {
                try out.appendSlice(a, s[i + 1 .. close_at]);
                i = end + 1;
                continue;
            };
        };
        const shapes = [_]struct { utf8: []const u8, byte: u8 }{
            .{ .utf8 = "\u{2715}", .byte = 1 }, .{ .utf8 = "\u{25cb}", .byte = 2 },
            .{ .utf8 = "\u{25a1}", .byte = 3 }, .{ .utf8 = "\u{25b3}", .byte = 4 },
        };
        var matched = false;
        for (shapes) |sh| {
            if (std.mem.startsWith(u8, s[i..], sh.utf8)) {
                try out.append(a, sh.byte);
                i += sh.utf8.len;
                matched = true;
                break;
            }
        }
        if (matched) continue;
        try out.append(a, ch);
        i += 1;
    }
    return out.items;
}

pub fn draw(page: *const P.Page) void {
    const p = &page.paint;
    if (!g_laid) layout(p);
    page.panel(kPanel);
    const x = kPanel.x + kPad;
    var y = kPanel.y + 18;
    const n = visibleFrom(g_top);
    for (g_rows.items[g_top..][0..n]) |r| {
        const h = rowHeight(r.kind);
        switch (r.kind) {
            .gap => {},
            .title => p.text(.subtitle, x, y + (h - p.lineHeight(.subtitle)) / 2, P.kGoldHi, r.text),
            .heading => page.heading(x, y + 6, kPanel.w - 2 * kPad, h - 8, r.text),
            .bullet, .body => {
                const ix: f32 = if (r.indent) x + 18 else x;
                if (r.kind == .bullet) start_page.diamond(p.r, x + 6, y + h / 2, 3, P.kGold);
                P.padText(p, .body, ix, y + (h - p.lineHeight(.body)) / 2, P.kCream.alpha(225), r.text);
            },
        }
        y += h;
    }
    const total = g_rows.items.len;
    if (total > n) {
        const nf: f32 = @floatFromInt(total);
        page.scrollbar(kPanel.x + kPanel.w - 10, kPanel.y + 14, kPanel.h - 28, @as(f32, @floatFromInt(g_top)) / nf, @as(f32, @floatFromInt(n)) / nf);
    }
}

pub fn hints(out: *[5]P.Hint) []const P.Hint {
    const list: []const P.Hint = &.{
        .{ .key = "\xe2\x86\x91 \xe2\x86\x93", .action = "Scroll" },
        .{ .key = "\xe2\x86\x90 \xe2\x86\x92", .action = "Page" },
        .{ .key = "A / Enter", .action = "Done" },
    };
    @memcpy(out[0..list.len], list);
    return out[0..list.len];
}

/// For the screenshots: scrolled down `rows`.
pub fn scrollForShot(rows: usize) void {
    g_top = rows;
}

test "markdown comes out as plain words" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("Press F11 for fullscreen, in zelda3.ini", try plain(a, "Press **F11** for fullscreen, in `zelda3.ini`"));
    try std.testing.expectEqualStrings("see the guide here", try plain(a, "see [the guide](docs/randomizer.md) here"));
    try std.testing.expectEqualStrings("\x01 and \x04", try plain(a, "\u{2715} and \u{25b3}"));
}
