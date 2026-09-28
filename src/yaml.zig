//! YAML, as far as the editable asset files need it.
//!
//! The files were first written by PyYAML with default_flow_style=None, and
//! people have them on disk and in mods. So `emit` follows PyYAML's emitter
//! rule for rule - which collections go inline, when a string needs quotes,
//! where a long line wraps - and writes the same bytes it did. `parse` reads
//! that back, and the hand edits people make to it: block and flow
//! collections, plain and quoted scalars, comments, and flow collections
//! broken across lines.
//!
//! Values are integers, booleans, null, strings, lists and maps. Maps keep
//! their order, because the order in the files is part of what they say.
const std = @import("std");

pub const Value = union(enum) {
    null_,
    boolean: bool,
    int: i64,
    str: []const u8,
    list: []const Value,
    map: []const Pair,

    /// A map's value by key, or null.
    pub fn get(self: Value, key: []const u8) ?Value {
        if (self != .map) return null;
        for (self.map) |p| {
            if (std.mem.eql(u8, p.key, key)) return p.value;
        }
        return null;
    }

    pub fn asInt(self: Value) ?i64 {
        return switch (self) {
            .int => |i| i,
            .boolean => |b| @intFromBool(b),
            else => null,
        };
    }

    pub fn asStr(self: Value) ?[]const u8 {
        return if (self == .str) self.str else null;
    }

    pub fn asList(self: Value) ?[]const Value {
        return if (self == .list) self.list else null;
    }
};

pub const Pair = struct { key: []const u8, value: Value };

// ------------------------------------------------------------------ emitting

const kBestWidth = 80;
const kBestIndent = 2;

/// Writes `value` the way PyYAML's yaml.dump(value, default_flow_style=None,
/// sort_keys=False) does.
pub fn emit(alloc: std.mem.Allocator, value: Value) ![]u8 {
    var e = Emitter{ .alloc = alloc };
    errdefer e.out.deinit(alloc);
    try e.node(value, .{ .root = true });
    // The stream ends with a line break after the document's last line.
    try e.lineBreak();
    return e.out.toOwnedSlice(alloc);
}

const Context = struct {
    root: bool = false,
    sequence: bool = false,
    mapping: bool = false,
    simple_key: bool = false,
};

const Emitter = struct {
    alloc: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,
    column: usize = 0,
    whitespace: bool = true,
    indention: bool = true,
    indent: ?usize = null,
    indents: [64]?usize = undefined,
    depth: usize = 0,
    flow_level: usize = 0,
    ctx: Context = .{},

    fn write(self: *Emitter, s: []const u8) !void {
        try self.out.appendSlice(self.alloc, s);
    }

    fn lineBreak(self: *Emitter) !void {
        self.whitespace = true;
        self.indention = true;
        self.column = 0;
        try self.write("\n");
    }

    fn writeIndent(self: *Emitter) !void {
        const indent = self.indent orelse 0;
        if (!self.indention or self.column > indent or (self.column == indent and !self.whitespace))
            try self.lineBreak();
        if (self.column < indent) {
            self.whitespace = true;
            for (self.column..indent) |_| try self.write(" ");
            self.column = indent;
        }
    }

    fn indicator(self: *Emitter, ind: []const u8, need_whitespace: bool, whitespace: bool, indention: bool) !void {
        if (!self.whitespace and need_whitespace) {
            try self.write(" ");
            self.column += 1;
        }
        try self.write(ind);
        self.column += ind.len;
        self.whitespace = whitespace;
        self.indention = self.indention and indention;
    }

    fn pushIndent(self: *Emitter, flow: bool, indentless: bool) void {
        self.indents[self.depth] = self.indent;
        self.depth += 1;
        if (self.indent) |i| {
            if (!indentless) self.indent = i + kBestIndent;
        } else {
            self.indent = if (flow) kBestIndent else 0;
        }
    }

    fn popIndent(self: *Emitter) void {
        self.depth -= 1;
        self.indent = self.indents[self.depth];
    }

    /// PyYAML's representer puts a collection inline when everything in it
    /// is a scalar, and empty collections are always inline.
    fn allScalars(value: Value) bool {
        switch (value) {
            .list => |items| {
                for (items) |v| if (v == .list or v == .map) return false;
                return true;
            },
            .map => |pairs| {
                for (pairs) |p| if (p.value == .list or p.value == .map) return false;
                return true;
            },
            else => return true,
        }
    }

    fn node(self: *Emitter, value: Value, ctx: Context) anyerror!void {
        self.ctx = ctx;
        switch (value) {
            .list => |items| {
                if (self.flow_level > 0 or items.len == 0 or allScalars(value)) {
                    try self.flowSequence(items);
                } else {
                    try self.blockSequence(items);
                }
            },
            .map => |pairs| {
                if (self.flow_level > 0 or pairs.len == 0 or allScalars(value)) {
                    try self.flowMapping(pairs);
                } else {
                    try self.blockMapping(pairs);
                }
            },
            else => {
                self.pushIndent(true, false);
                try self.scalar(value);
                self.popIndent();
            },
        }
    }

    fn blockSequence(self: *Emitter, items: []const Value) !void {
        const indentless = self.ctx.mapping and !self.indention;
        self.pushIndent(false, indentless);
        for (items) |item| {
            try self.writeIndent();
            try self.indicator("-", true, false, true);
            try self.node(item, .{ .sequence = true });
        }
        self.popIndent();
    }

    fn blockMapping(self: *Emitter, pairs: []const Pair) !void {
        self.pushIndent(false, false);
        for (pairs) |p| {
            try self.writeIndent();
            try self.node(.{ .str = p.key }, .{ .mapping = true, .simple_key = true });
            try self.indicator(":", false, false, false);
            try self.node(p.value, .{ .mapping = true });
        }
        self.popIndent();
    }

    fn flowSequence(self: *Emitter, items: []const Value) !void {
        try self.indicator("[", true, true, false);
        self.flow_level += 1;
        self.pushIndent(true, false);
        for (items, 0..) |item, i| {
            if (i != 0) try self.indicator(",", false, false, false);
            if (self.column > kBestWidth) try self.writeIndent();
            try self.node(item, .{ .sequence = true });
        }
        self.popIndent();
        self.flow_level -= 1;
        try self.indicator("]", false, false, false);
    }

    fn flowMapping(self: *Emitter, pairs: []const Pair) !void {
        try self.indicator("{", true, true, false);
        self.flow_level += 1;
        self.pushIndent(true, false);
        for (pairs, 0..) |p, i| {
            if (i != 0) try self.indicator(",", false, false, false);
            if (self.column > kBestWidth) try self.writeIndent();
            try self.node(.{ .str = p.key }, .{ .mapping = true, .simple_key = true });
            try self.indicator(":", false, false, false);
            try self.node(p.value, .{ .mapping = true });
        }
        self.popIndent();
        self.flow_level -= 1;
        try self.indicator("}", false, false, false);
    }

    fn scalar(self: *Emitter, value: Value) !void {
        var buf: [32]u8 = undefined;
        const text: []const u8, const is_str = switch (value) {
            .null_ => .{ "null", false },
            .boolean => |b| .{ if (b) "true" else "false", false },
            .int => |i| .{ try std.fmt.bufPrint(&buf, "{d}", .{i}), false },
            .str => |s| .{ s, true },
            else => unreachable,
        };
        const split = !self.ctx.simple_key;
        if (!is_str) return self.plain(text, split);

        const a = analyze(text);
        // A string that would read back as something else (a number, a
        // boolean, null) is quoted; PyYAML calls that not being implicit.
        const implicit = !resolvesToNonString(text);
        if (implicit and !(self.ctx.simple_key and (a.empty or a.multiline)) and
            ((self.flow_level > 0 and a.allow_flow_plain) or (self.flow_level == 0 and a.allow_block_plain)))
        {
            return self.plain(text, split);
        }
        if (a.allow_single_quoted and !(self.ctx.simple_key and a.multiline)) return self.singleQuoted(text, split);
        return self.doubleQuoted(text);
    }

    fn plain(self: *Emitter, text: []const u8, split: bool) !void {
        if (text.len == 0) return;
        if (!self.whitespace) {
            try self.write(" ");
            self.column += 1;
        }
        self.whitespace = false;
        self.indention = false;
        var spaces = false;
        var start: usize = 0;
        var end: usize = 0;
        while (end <= text.len) : (end += 1) {
            const ch: ?u8 = if (end < text.len) text[end] else null;
            if (spaces) {
                if (ch != ' ') {
                    if (start + 1 == end and self.column > kBestWidth and split) {
                        try self.writeIndent();
                        self.whitespace = false;
                        self.indention = false;
                    } else {
                        try self.write(text[start..end]);
                        self.column += end - start;
                    }
                    start = end;
                }
            } else if (ch == null or ch.? == ' ' or ch.? == '\n') {
                try self.write(text[start..end]);
                self.column += end - start;
                start = end;
            }
            if (ch) |cc| spaces = cc == ' ';
        }
    }

    fn singleQuoted(self: *Emitter, text: []const u8, split: bool) !void {
        try self.indicator("'", true, false, false);
        var spaces = false;
        var start: usize = 0;
        var end: usize = 0;
        while (end <= text.len) : (end += 1) {
            const ch: ?u8 = if (end < text.len) text[end] else null;
            if (spaces) {
                if (ch == null or ch.? != ' ') {
                    if (start + 1 == end and self.column > kBestWidth and split and start != 0 and end != text.len) {
                        try self.writeIndent();
                    } else {
                        try self.write(text[start..end]);
                        self.column += end - start;
                    }
                    start = end;
                }
            } else if (ch == null or ch.? == ' ' or ch.? == '\n' or ch.? == '\'') {
                if (start < end) {
                    try self.write(text[start..end]);
                    self.column += end - start;
                    start = end;
                }
            }
            if (ch == '\'') {
                try self.write("''");
                self.column += 2;
                start = end + 1;
            }
            if (ch) |cc| spaces = cc == ' ';
        }
        try self.indicator("'", false, false, false);
    }

    /// Only reached for strings with characters single quotes can't carry,
    /// which the exported files never contain; kept simple and unwrapped.
    fn doubleQuoted(self: *Emitter, text: []const u8) !void {
        try self.indicator("\"", true, false, false);
        for (text) |ch| {
            var buf: [8]u8 = undefined;
            const s: []const u8 = switch (ch) {
                '"' => "\\\"",
                '\\' => "\\\\",
                '\n' => "\\n",
                '\t' => "\\t",
                0x20...0x21, 0x23...0x5b, 0x5d...0x7e => &[_]u8{ch},
                else => try std.fmt.bufPrint(&buf, "\\x{X:0>2}", .{ch}),
            };
            try self.write(s);
            self.column += s.len;
        }
        try self.indicator("\"", false, false, false);
    }
};

const Analysis = struct {
    empty: bool = false,
    multiline: bool = false,
    allow_flow_plain: bool = true,
    allow_block_plain: bool = true,
    allow_single_quoted: bool = true,
};

fn isWs(ch: u8) bool {
    return ch == 0 or ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

/// PyYAML's Emitter.analyze_scalar, for the ASCII text the files hold.
fn analyze(s: []const u8) Analysis {
    if (s.len == 0) return .{ .empty = true, .allow_flow_plain = false, .allow_block_plain = true };
    var block_ind = false;
    var flow_ind = false;
    var line_breaks = false;
    var special = false;
    var leading_space = false;
    var trailing_space = false;
    if (std.mem.startsWith(u8, s, "---") or std.mem.startsWith(u8, s, "...")) {
        block_ind = true;
        flow_ind = true;
    }
    var preceded_by_ws = true;
    var followed_by_ws = s.len == 1 or isWs(s[1]);
    for (s, 0..) |ch, i| {
        if (i == 0) {
            if (std.mem.indexOfScalar(u8, "#,[]{}&*!|>'\"%@`", ch) != null) {
                flow_ind = true;
                block_ind = true;
            }
            if (ch == '?' or ch == ':') {
                flow_ind = true;
                if (followed_by_ws) block_ind = true;
            }
            if (ch == '-' and followed_by_ws) {
                flow_ind = true;
                block_ind = true;
            }
        } else {
            if (std.mem.indexOfScalar(u8, ",?[]{}", ch) != null) flow_ind = true;
            if (ch == ':') {
                flow_ind = true;
                if (followed_by_ws) block_ind = true;
            }
            if (ch == '#' and preceded_by_ws) {
                flow_ind = true;
                block_ind = true;
            }
        }
        if (ch == '\n') line_breaks = true;
        if (!(ch == '\n' or (ch >= 0x20 and ch <= 0x7e))) special = true;
        if (ch == ' ') {
            if (i == 0) leading_space = true;
            if (i == s.len - 1) trailing_space = true;
        }
        preceded_by_ws = isWs(ch);
        followed_by_ws = i + 2 >= s.len or isWs(s[i + 2]);
    }
    var a = Analysis{ .multiline = line_breaks };
    if (leading_space or trailing_space) {
        a.allow_flow_plain = false;
        a.allow_block_plain = false;
    }
    if (special) {
        a.allow_flow_plain = false;
        a.allow_block_plain = false;
        a.allow_single_quoted = false;
    }
    if (line_breaks) {
        a.allow_flow_plain = false;
        a.allow_block_plain = false;
    }
    if (flow_ind) a.allow_flow_plain = false;
    if (block_ind) a.allow_block_plain = false;
    return a;
}

// --------------------------------------------------- YAML 1.1 implicit types

fn allIn(s: []const u8, set: []const u8) bool {
    for (s) |ch| if (std.mem.indexOfScalar(u8, set, ch) == null) return false;
    return true;
}

fn stripSign(s: []const u8) []const u8 {
    return if (s.len > 0 and (s[0] == '-' or s[0] == '+')) s[1..] else s;
}

fn isBool(s: []const u8) bool {
    const words = [_][]const u8{ "yes", "Yes", "YES", "no", "No", "NO", "true", "True", "TRUE", "false", "False", "FALSE", "on", "On", "ON", "off", "Off", "OFF" };
    for (words) |w| if (std.mem.eql(u8, s, w)) return true;
    return false;
}

fn isNull(s: []const u8) bool {
    return s.len == 0 or std.mem.eql(u8, s, "~") or std.mem.eql(u8, s, "null") or
        std.mem.eql(u8, s, "Null") or std.mem.eql(u8, s, "NULL");
}

/// `[1-9][0-9_]*(:[0-5]?[0-9])+`, YAML 1.1's base 60.
fn isSexagesimal(s: []const u8, allow_fraction: bool) bool {
    var parts = std.mem.splitScalar(u8, s, ':');
    const head = parts.next().?;
    if (head.len == 0 or !allIn(head, "0123456789_")) return false;
    if (!allow_fraction and head[0] == '0') return false;
    var any = false;
    while (parts.next()) |p| {
        var digits = p;
        if (allow_fraction and parts.peek() == null) {
            // The last part of a base 60 float carries the fraction.
            const dot = std.mem.indexOfScalar(u8, p, '.') orelse return false;
            digits = p[0..dot];
            if (!allIn(p[dot + 1 ..], "0123456789_")) return false;
        }
        if (digits.len == 0 or digits.len > 2 or !allIn(digits, "0123456789")) return false;
        if (digits.len == 2 and digits[0] > '5') return false;
        any = true;
    }
    return any;
}

fn isInt(s0: []const u8) bool {
    const s = stripSign(s0);
    if (s.len == 0) return false;
    if (std.mem.startsWith(u8, s, "0b")) return s.len > 2 and allIn(s[2..], "01_");
    if (std.mem.startsWith(u8, s, "0x")) return s.len > 2 and allIn(s[2..], "0123456789abcdefABCDEF_");
    if (s[0] == '0') return s.len == 1 or allIn(s[1..], "01234567_");
    if (s[0] >= '1' and s[0] <= '9' and allIn(s, "0123456789_")) return true;
    return isSexagesimal(s, false);
}

fn isFloat(s0: []const u8) bool {
    const s = stripSign(s0);
    if (std.mem.eql(u8, s0, ".nan") or std.mem.eql(u8, s0, ".NaN") or std.mem.eql(u8, s0, ".NAN")) return true;
    if (std.mem.eql(u8, s, ".inf") or std.mem.eql(u8, s, ".Inf") or std.mem.eql(u8, s, ".INF")) return true;
    if (s.len == 0) return false;
    // [0-9][0-9_]*\.[0-9_]*([eE][-+][0-9]+)? or \.[0-9][0-9_]*(...)?
    if (s[0] == '.' and s0.len == s.len) {
        return s.len > 1 and s[1] >= '0' and s[1] <= '9' and decimalRest(s[1..]);
    }
    if (s[0] >= '0' and s[0] <= '9') {
        if (std.mem.indexOfScalar(u8, s, ':') != null) return isSexagesimal(s, true);
        const dot = std.mem.indexOfScalar(u8, s, '.') orelse return false;
        if (!allIn(s[0..dot], "0123456789_")) return false;
        return decimalRest(s[dot + 1 ..]) or s.len == dot + 1;
    }
    return false;
}

/// `[0-9_]*([eE][-+][0-9]+)?`
fn decimalRest(s: []const u8) bool {
    const e = std.mem.indexOfAny(u8, s, "eE") orelse return allIn(s, "0123456789_");
    if (!allIn(s[0..e], "0123456789_")) return false;
    const exp = s[e + 1 ..];
    return exp.len >= 2 and (exp[0] == '-' or exp[0] == '+') and allIn(exp[1..], "0123456789");
}

fn isTimestamp(s: []const u8) bool {
    // Only the date form matters in practice: YYYY-MM-DD, and the longer
    // forms all start with one.
    if (s.len < 8 or !std.ascii.isDigit(s[0]) or !std.ascii.isDigit(s[1]) or
        !std.ascii.isDigit(s[2]) or !std.ascii.isDigit(s[3]) or s[4] != '-') return false;
    return std.mem.indexOfScalarPos(u8, s, 5, '-') != null and allIn(s[0..@min(s.len, 10)], "0123456789-");
}

/// Whether PyYAML's resolver would read this plain text as something other
/// than a string.
fn resolvesToNonString(s: []const u8) bool {
    return isBool(s) or isNull(s) or isInt(s) or isFloat(s) or isTimestamp(s) or
        std.mem.eql(u8, s, "<<") or std.mem.eql(u8, s, "=");
}

/// The value plain text stands for.
fn resolvePlain(s: []const u8) Value {
    if (isNull(s)) return .null_;
    if (isBool(s)) {
        return .{ .boolean = switch (s[0]) {
            'y', 'Y', 't', 'T' => true,
            'o', 'O' => s.len == 2 and (s[1] == 'n' or s[1] == 'N'),
            else => false,
        } };
    }
    if (isInt(s)) {
        if (parseInt(s)) |i| return .{ .int = i };
    }
    return .{ .str = s };
}

fn parseInt(s0: []const u8) ?i64 {
    var digits: [64]u8 = undefined;
    var n: usize = 0;
    for (s0) |ch| {
        if (ch == '_') continue;
        if (n == digits.len) return null;
        digits[n] = ch;
        n += 1;
    }
    const s = digits[0..n];
    const neg = s.len > 0 and s[0] == '-';
    const body = stripSign(s);
    const v: i64 = if (std.mem.startsWith(u8, body, "0x"))
        std.fmt.parseInt(i64, body[2..], 16) catch return null
    else if (std.mem.startsWith(u8, body, "0b"))
        std.fmt.parseInt(i64, body[2..], 2) catch return null
    else if (body.len > 1 and body[0] == '0')
        std.fmt.parseInt(i64, body[1..], 8) catch return null
    else if (std.mem.indexOfScalar(u8, body, ':') != null) blk: {
        var total: i64 = 0;
        var parts = std.mem.splitScalar(u8, body, ':');
        while (parts.next()) |p| total = total * 60 + (std.fmt.parseInt(i64, p, 10) catch return null);
        break :blk total;
    } else std.fmt.parseInt(i64, body, 10) catch return null;
    return if (neg) -v else v;
}

// ------------------------------------------------------------------ parsing

pub const ParseError = error{ Syntax, OutOfMemory };

pub const Diagnostic = struct { line: usize = 0, message: []const u8 = "" };

/// Parses a document. Strings in the result point into `text` where they
/// can, and are allocated where quotes or folding changed them; everything
/// is owned by `arena`, so free the arena, not the value.
pub fn parse(arena: std.mem.Allocator, text: []const u8, diag: ?*Diagnostic) ParseError!Value {
    var p = Parser{ .arena = arena, .src = text, .diag = diag };
    p.skipBlank();
    if (p.pos >= p.src.len) return .null_;
    const v = try p.blockNode(0);
    p.skipBlank();
    if (p.pos < p.src.len) return p.fail("unexpected content");
    return v;
}

const Parser = struct {
    arena: std.mem.Allocator,
    src: []const u8,
    pos: usize = 0,
    diag: ?*Diagnostic,

    fn fail(self: *Parser, message: []const u8) ParseError {
        if (self.diag) |d| {
            d.line = std.mem.count(u8, self.src[0..@min(self.pos, self.src.len)], "\n") + 1;
            d.message = message;
        }
        return error.Syntax;
    }

    fn peek(self: *Parser) u8 {
        return if (self.pos < self.src.len) self.src[self.pos] else 0;
    }

    fn column(self: *Parser) usize {
        const line_start = if (std.mem.lastIndexOfScalar(u8, self.src[0..self.pos], '\n')) |i| i + 1 else 0;
        return self.pos - line_start;
    }

    /// Skips spaces, comments and whole blank lines, leaving pos at the first
    /// character of the next content.
    fn skipBlank(self: *Parser) void {
        while (self.pos < self.src.len) {
            const ch = self.src[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n') {
                self.pos += 1;
            } else if (ch == '#' and (self.pos == 0 or isWs(self.src[self.pos - 1]))) {
                while (self.pos < self.src.len and self.src[self.pos] != '\n') self.pos += 1;
            } else if (self.pos == 0 and std.mem.startsWith(u8, self.src, "---")) {
                self.pos += 3;
            } else break;
        }
    }

    /// Skips spaces and a comment on the current line only.
    fn skipInline(self: *Parser) void {
        while (self.pos < self.src.len and (self.src[self.pos] == ' ' or self.src[self.pos] == '\t')) self.pos += 1;
        if (self.peek() == '#') {
            while (self.pos < self.src.len and self.src[self.pos] != '\n') self.pos += 1;
        }
    }

    fn atLineEnd(self: *Parser) bool {
        const ch = self.peek();
        return ch == 0 or ch == '\n' or ch == '\r';
    }

    fn isSeqEntry(self: *Parser) bool {
        if (self.peek() != '-') return false;
        const next: u8 = if (self.pos + 1 < self.src.len) self.src[self.pos + 1] else 0;
        return isWs(next);
    }

    /// Where a "key:" on this line ends, if the line is a mapping entry.
    fn mappingKeyEnd(self: *Parser) ?usize {
        var i = self.pos;
        const ch = self.peek();
        if (ch == '\'' or ch == '"') {
            // A quoted key: find its closing quote.
            i += 1;
            while (i < self.src.len and self.src[i] != '\n') : (i += 1) {
                if (self.src[i] == ch) {
                    if (ch == '\'' and i + 1 < self.src.len and self.src[i + 1] == '\'') {
                        i += 1;
                        continue;
                    }
                    if (ch == '"' and self.src[i - 1] == '\\') continue;
                    break;
                }
            }
            i += 1;
            while (i < self.src.len and self.src[i] == ' ') i += 1;
            return if (i < self.src.len and self.src[i] == ':' and (i + 1 >= self.src.len or isWs(self.src[i + 1]))) i else null;
        }
        if (ch == '[' or ch == '{') return null;
        while (i < self.src.len and self.src[i] != '\n') : (i += 1) {
            if (self.src[i] == ':' and (i + 1 >= self.src.len or isWs(self.src[i + 1]))) return i;
            if (self.src[i] == '#' and i > self.pos and isWs(self.src[i - 1])) return null;
        }
        return null;
    }

    fn blockNode(self: *Parser, min_indent: usize) ParseError!Value {
        self.skipBlank();
        const col = self.column();
        if (self.pos >= self.src.len) return .null_;
        if (col < min_indent) return .null_;
        if (self.isSeqEntry()) return self.blockSequence(col);
        if (self.mappingKeyEnd() != null) return self.blockMapping(col);
        return self.flowNode(col, false);
    }

    fn blockSequence(self: *Parser, indent: usize) ParseError!Value {
        var items: std.ArrayList(Value) = .empty;
        while (true) {
            self.skipBlank();
            if (self.pos >= self.src.len or self.column() != indent or !self.isSeqEntry()) break;
            self.pos += 1;
            self.skipInline();
            if (self.atLineEnd()) {
                try items.append(self.arena, try self.blockNode(indent + 1));
            } else if (self.isSeqEntry()) {
                // "- - x": a sequence starting on the same line.
                try items.append(self.arena, try self.blockSequence(self.column()));
            } else if (self.mappingKeyEnd() != null) {
                // "- key: value" starts a mapping indented to where key is.
                try items.append(self.arena, try self.blockMapping(self.column()));
            } else {
                try items.append(self.arena, try self.flowNode(indent + 1, false));
            }
        }
        return .{ .list = try items.toOwnedSlice(self.arena) };
    }

    fn blockMapping(self: *Parser, indent: usize) ParseError!Value {
        var pairs: std.ArrayList(Pair) = .empty;
        while (true) {
            self.skipBlank();
            if (self.pos >= self.src.len or self.column() != indent) break;
            const key_end = self.mappingKeyEnd() orelse break;
            const key_text = std.mem.trimEnd(u8, self.src[self.pos..key_end], " ");
            const key = switch (key_text[0]) {
                '\'', '"' => blk: {
                    var sub = Parser{ .arena = self.arena, .src = key_text, .diag = null };
                    break :blk (try sub.quoted()).str;
                },
                else => key_text,
            };
            self.pos = key_end + 1;
            self.skipInline();
            var value: Value = undefined;
            if (self.atLineEnd()) {
                self.skipBlank();
                const col = self.column();
                // Sequences may sit at the key's own indentation.
                if (self.pos < self.src.len and (col > indent or (col == indent and self.isSeqEntry()))) {
                    value = if (self.isSeqEntry()) try self.blockSequence(col) else try self.blockNode(indent + 1);
                } else value = .null_;
            } else {
                value = try self.flowNode(indent + 1, false);
            }
            try pairs.append(self.arena, .{ .key = key, .value = value });
        }
        return .{ .map = try pairs.toOwnedSlice(self.arena) };
    }

    /// A scalar or flow collection starting at pos. `in_flow` is true inside
    /// [ ] or { }, where , ] } end a plain scalar.
    fn flowNode(self: *Parser, min_indent: usize, in_flow: bool) ParseError!Value {
        if (in_flow) self.skipBlank() else self.skipInline();
        return switch (self.peek()) {
            '[' => self.flowSequence(),
            '{' => self.flowMapping(),
            '\'', '"' => self.quoted(),
            else => self.plainScalar(min_indent, in_flow),
        };
    }

    fn flowSequence(self: *Parser) ParseError!Value {
        self.pos += 1;
        var items: std.ArrayList(Value) = .empty;
        while (true) {
            self.skipBlank();
            if (self.peek() == ']') {
                self.pos += 1;
                break;
            }
            if (self.pos >= self.src.len) return self.fail("unclosed [");
            try items.append(self.arena, try self.flowNode(0, true));
            self.skipBlank();
            if (self.peek() == ',') {
                self.pos += 1;
            } else if (self.peek() != ']') return self.fail("expected , or ]");
        }
        return .{ .list = try items.toOwnedSlice(self.arena) };
    }

    fn flowMapping(self: *Parser) ParseError!Value {
        self.pos += 1;
        var pairs: std.ArrayList(Pair) = .empty;
        while (true) {
            self.skipBlank();
            if (self.peek() == '}') {
                self.pos += 1;
                break;
            }
            if (self.pos >= self.src.len) return self.fail("unclosed {");
            const key = try self.flowNode(0, true);
            self.skipBlank();
            if (self.peek() != ':') return self.fail("expected : in {}");
            self.pos += 1;
            const value = try self.flowNode(0, true);
            const key_str = switch (key) {
                .str => |s| s,
                .int => |i| try std.fmt.allocPrint(self.arena, "{d}", .{i}),
                else => return self.fail("unsupported key"),
            };
            try pairs.append(self.arena, .{ .key = key_str, .value = value });
            self.skipBlank();
            if (self.peek() == ',') {
                self.pos += 1;
            } else if (self.peek() != '}') return self.fail("expected , or }");
        }
        return .{ .map = try pairs.toOwnedSlice(self.arena) };
    }

    fn quoted(self: *Parser) ParseError!Value {
        const q = self.peek();
        self.pos += 1;
        var out: std.ArrayList(u8) = .empty;
        while (true) {
            if (self.pos >= self.src.len) return self.fail("unclosed quote");
            const ch = self.src[self.pos];
            if (ch == q) {
                if (q == '\'' and self.pos + 1 < self.src.len and self.src[self.pos + 1] == '\'') {
                    try out.append(self.arena, '\'');
                    self.pos += 2;
                    continue;
                }
                self.pos += 1;
                break;
            }
            if (ch == '\n' or ch == '\r') {
                // Line folding: a break and the indentation after it become
                // one space, and a blank line becomes a newline.
                while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') out.items.len -= 1;
                var breaks: usize = 0;
                while (self.pos < self.src.len and isWs(self.src[self.pos])) : (self.pos += 1) {
                    if (self.src[self.pos] == '\n') breaks += 1;
                }
                if (breaks > 1) {
                    for (1..breaks) |_| try out.append(self.arena, '\n');
                } else try out.append(self.arena, ' ');
                continue;
            }
            if (q == '"' and ch == '\\') {
                self.pos += 1;
                const e = self.peek();
                self.pos += 1;
                switch (e) {
                    'n' => try out.append(self.arena, '\n'),
                    't' => try out.append(self.arena, '\t'),
                    '0' => try out.append(self.arena, 0),
                    '\\', '"', '/' => try out.append(self.arena, e),
                    'x' => {
                        if (self.pos + 2 > self.src.len) return self.fail("bad \\x escape");
                        const v = std.fmt.parseInt(u8, self.src[self.pos .. self.pos + 2], 16) catch return self.fail("bad \\x escape");
                        try out.append(self.arena, v);
                        self.pos += 2;
                    },
                    else => return self.fail("unsupported escape"),
                }
                continue;
            }
            try out.append(self.arena, ch);
            self.pos += 1;
        }
        return .{ .str = try out.toOwnedSlice(self.arena) };
    }

    /// A plain scalar, which may carry on over following lines that are
    /// indented further than `min_indent` (PyYAML wraps long ones that way).
    fn plainScalar(self: *Parser, min_indent: usize, in_flow: bool) ParseError!Value {
        var out: std.ArrayList(u8) = .empty;
        while (true) {
            const start = self.pos;
            while (self.pos < self.src.len) : (self.pos += 1) {
                const ch = self.src[self.pos];
                if (ch == '\n' or ch == '\r') break;
                if (ch == ':' and (self.pos + 1 >= self.src.len or isWs(self.src[self.pos + 1]) or (in_flow and std.mem.indexOfScalar(u8, ",[]{}", self.src[self.pos + 1]) != null))) break;
                if (ch == '#' and self.pos > start and isWs(self.src[self.pos - 1])) break;
                if (in_flow and (ch == ',' or ch == ']' or ch == '}' or ch == '[' or ch == '{')) break;
            }
            const piece = std.mem.trim(u8, self.src[start..self.pos], " \t");
            if (piece.len > 0) {
                if (out.items.len > 0) try out.append(self.arena, ' ');
                try out.appendSlice(self.arena, piece);
            }
            // Continue onto the next line only if it's indented deeper and
            // the scalar didn't end on something structural.
            if (!self.atLineEnd()) break;
            const save = self.pos;
            self.skipBlank();
            if (self.pos >= self.src.len or self.column() < min_indent or (!in_flow and self.column() == 0) or
                self.isSeqEntry() or self.mappingKeyEnd() != null or
                std.mem.indexOfScalar(u8, ",]}#", self.peek()) != null)
            {
                self.pos = save;
                break;
            }
            if (!in_flow and self.column() <= min_indent -| 1) {
                self.pos = save;
                break;
            }
        }
        return resolvePlain(try out.toOwnedSlice(self.arena));
    }
};

// ------------------------------------------------------------------- tests

const testing = std.testing;

fn roundTrip(text: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diag = Diagnostic{};
    const v = parse(arena, text, &diag) catch |e| {
        std.debug.print("line {d}: {s}\n", .{ diag.line, diag.message });
        return e;
    };
    const out = try emit(arena, v);
    try testing.expectEqualStrings(text, out);
}

test "PyYAML's style survives a round trip" {
    try roundTrip(
        \\Header:
        \\  name: 'LW 000 : Lost Woods NW'
        \\  size: big
        \\  gfx: 33
        \\  sign_text: -1
        \\  music: {beginning: Forest, zelda: Forest, sword: World_map, agahnim: World_map}
        \\Travel: []
        \\Entrances:
        \\- {index: 43, x: 46, y: 37, entrance_id: 44}
        \\Exits:
        \\- index: 54
        \\  room: 225
        \\  xy: [744, 584]
        \\  special_exit: {dir: 0, spr_gfx: 12, aux_gfx: 47, pal_bg: 10, pal_spr: 1, top: 0,
        \\    bottom: 288, left: 0, right: 0, left_edge_of_map: 0, unk4: -224, unk6: -4, unk5: -224,
        \\    unk7: -4}
        \\Items:
        \\- [53, 6, 04-Random]
        \\Layer1:
        \\- {x: 12, y: 4, n: '100-Wall Outer Corner (HIGH) [NW]'}
        \\- {x: 12, y: 8, s: 2*1, n: '61-[W]Wall Vert: [U-D]'}
        \\Header2:
        \\  effect: '01'
        \\  tag0: Kill to open Ganon's door
        \\  pits_hurt_player: false
        \\  chests: [5!, 3]
        \\
    );
}

test "strings that look like other things get quoted" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const v = Value{ .list = &.{
        .{ .str = "01" },  .{ .str = "10" },    .{ .str = "yes" }, .{ .str = "None" },
        .{ .str = "" },    .{ .str = "5!" },    .{ .str = "1:30" }, .{ .str = "3.5" },
        .{ .str = "a'b" }, .{ .str = "- x" }, .{ .str = "4_bombs" },
    } };
    try testing.expectEqualStrings(
        "['01', '10', 'yes', None, '', 5!, '1:30', '3.5', a'b, '- x', 4_bombs]\n",
        try emit(arena, v),
    );
}

test "plain scalars read back as the right types" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const v = try parse(arena_state.allocator(), "[12, -4, 0x1f, 017, true, false, null, ~, hello world, '12', 1:30]", null);
    const l = v.list;
    try testing.expectEqual(@as(i64, 12), l[0].int);
    try testing.expectEqual(@as(i64, -4), l[1].int);
    try testing.expectEqual(@as(i64, 31), l[2].int);
    try testing.expectEqual(@as(i64, 15), l[3].int);
    try testing.expect(l[4].boolean and !l[5].boolean);
    try testing.expect(l[6] == .null_ and l[7] == .null_);
    try testing.expectEqualStrings("hello world", l[8].str);
    try testing.expectEqualStrings("12", l[9].str);
    try testing.expectEqual(@as(i64, 90), l[10].int);
}

test "hand edits parse: comments, reindented lists, spread-out flow" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const v = try parse(arena_state.allocator(),
        \\# a comment
        \\Sprites:
        \\  - [1, 2, lower, 6D-Rat]   # indented this time
        \\  - [
        \\      3, 4,
        \\      upper, 00-Raven
        \\    ]
        \\Secrets: []
    , null);
    const sprites = v.get("Sprites").?.list;
    try testing.expectEqual(@as(usize, 2), sprites.len);
    try testing.expectEqualStrings("00-Raven", sprites[1].list[3].str);
    try testing.expectEqual(@as(usize, 0), v.get("Secrets").?.list.len);
}
