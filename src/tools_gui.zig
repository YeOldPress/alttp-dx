//! The zelda3-tools window.
//!
//! A sidebar of sections on the left, the chosen section on the right, and a
//! log along the bottom that every operation reports into. Drawn immediate
//! mode with SDL's renderer and its built-in font, so there's no toolkit to
//! ship. Paths come from the system's own file dialogs, or from dropping a
//! file on the window.
const std = @import("std");
const builtin = @import("builtin");
const c = @import("sdl.zig").c;
const ops = @import("tools_ops.zig");
const Language = @import("rom.zig").Language;

const kWindowW = 1024;
const kWindowH = 680;
const kSidebarW = 200;
const kLogH = 190;
/// SDL's debug font is 8x8; everything is drawn at twice that.
const kScale = 2;
const kCharW = 8 * kScale;
const kLineH = 8 * kScale + 6;

const Rgb = u32;
const kBg: Rgb = 0x1c2230;
const kSidebar: Rgb = 0x141923;
const kPanel: Rgb = 0x242b3a;
const kPanelHover: Rgb = 0x2f3950;
const kAccent: Rgb = 0xd8b048;
const kText: Rgb = 0xe8e8ec;
const kDim: Rgb = 0x8c94a6;
const kOk: Rgb = 0x6cc86c;
const kErr: Rgb = 0xe86464;
const kLogBg: Rgb = 0x10141c;
const kButton: Rgb = 0x3a4a6a;
const kButtonHover: Rgb = 0x4d6290;
const kButtonText: Rgb = 0xffffff;
const kDisabled: Rgb = 0x2a3140;

const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h;
    }
};

// ------------------------------------------------------------------ the log

const LogLine = struct {
    level: ops.Log.Level,
    len: u8,
    text: [200]u8,
};

var g_log: [300]LogLine = undefined;
var g_log_count: usize = 0;
/// Lines scrolled up from the bottom.
var g_log_scroll: usize = 0;

fn logWrite(ctx: *anyopaque, level: ops.Log.Level, text: []const u8) void {
    _ = ctx;
    // Long lines are wrapped to the log's width here, once, rather than at
    // every draw.
    const cols: usize = (kWindowW - kSidebarW - 32) / kCharW;
    var rest = text;
    while (true) {
        var n: usize = @min(rest.len, cols);
        // Break at a space where there is one, so words stay whole.
        if (n < rest.len) {
            if (std.mem.lastIndexOfScalar(u8, rest[0 .. n + 1], ' ')) |sp| {
                if (sp > 0) n = sp;
            }
        }
        pushLine(level, rest[0..n]);
        rest = std.mem.trimStart(u8, rest[n..], " ");
        if (rest.len == 0) break;
    }
    g_log_scroll = 0;
}

fn pushLine(level: ops.Log.Level, text: []const u8) void {
    if (g_log_count == g_log.len) {
        std.mem.copyForwards(LogLine, g_log[0 .. g_log.len - 1], g_log[1..]);
        g_log_count -= 1;
    }
    var line = LogLine{ .level = level, .len = @intCast(@min(text.len, 200)), .text = undefined };
    @memcpy(line.text[0..line.len], text[0..line.len]);
    g_log[g_log_count] = line;
    g_log_count += 1;
}

var g_log_dummy: u8 = 0;
const g_logger = ops.Log{ .ctx = &g_log_dummy, .writeFn = logWrite };

// ------------------------------------------------------------ file dialogs

/// Which field a dialog's answer belongs to. The answer can arrive on another
/// thread, so it lands here under a lock and the main loop picks it up.
const Field = enum { rom, out, verify, folder, lang_rom };

var g_dialog_lock: ?*c.SDL_Mutex = null;
var g_dialog_field: Field = .rom;
var g_dialog_result: ?[:0]u8 = null;

fn dialogCallback(userdata: ?*anyopaque, filelist: [*c]const [*c]const u8, filter: c_int) callconv(.c) void {
    _ = filter;
    const field: Field = @enumFromInt(@intFromPtr(userdata) - 1);
    if (filelist == null or filelist[0] == null) return; // failed, or cancelled
    const path = std.mem.span(filelist[0]);
    const copy = std.heap.c_allocator.dupeZ(u8, path) catch return;
    c.SDL_LockMutex(g_dialog_lock);
    defer c.SDL_UnlockMutex(g_dialog_lock);
    if (g_dialog_result) |old| std.heap.c_allocator.free(old);
    g_dialog_result = copy;
    g_dialog_field = field;
}

const kRomFilters = [_]c.SDL_DialogFileFilter{.{ .name = "SNES ROM", .pattern = "sfc;smc" }};
const kDatFilters = [_]c.SDL_DialogFileFilter{.{ .name = "Asset file", .pattern = "dat" }};

fn openDialog(window_opt: ?*c.SDL_Window, field: Field) void {
    const window = window_opt orelse return;
    const userdata: ?*anyopaque = @ptrFromInt(@intFromEnum(field) + 1);
    switch (field) {
        .rom, .lang_rom => c.SDL_ShowOpenFileDialog(dialogCallback, userdata, window, &kRomFilters, kRomFilters.len, null, false),
        .verify => c.SDL_ShowOpenFileDialog(dialogCallback, userdata, window, &kDatFilters, kDatFilters.len, null, false),
        .out => c.SDL_ShowSaveFileDialog(dialogCallback, userdata, window, &kDatFilters, kDatFilters.len, null),
        .folder => c.SDL_ShowOpenFolderDialog(dialogCallback, userdata, window, null, false),
    }
}

// ----------------------------------------------------------------- the state

const Page = enum {
    assets,
    modding,
    languages,

    fn title(self: Page) []const u8 {
        return switch (self) {
            .assets => "Assets",
            .modding => "Modding",
            .languages => "Languages",
        };
    }
};

const State = struct {
    page: Page = .assets,
    rom: std.ArrayList(u8) = .empty,
    out: std.ArrayList(u8) = .empty,
    verify: std.ArrayList(u8) = .empty,
    folder: std.ArrayList(u8) = .empty,
    lang_rom: std.ArrayList(u8) = .empty,
    sprites_from_png: bool = false,
    /// Translations ticked to build in, and which ones the folder has files
    /// for, checked now and then rather than every frame.
    picked: [kLangCount]bool = @splat(false),
    available: [kLangCount]bool = @splat(false),
    available_age: u32 = 0,
    extra_buf: [kLangCount]Language = undefined,

    /// The ticked translations the folder has files for.
    fn extra(self: *State) ops.Extra {
        var n: usize = 0;
        for (0..kLangCount) |i| {
            if (!self.picked[i] or !self.available[i]) continue;
            self.extra_buf[n] = @enumFromInt(i);
            n += 1;
        }
        return .{ .languages = self.extra_buf[0..n], .dir = self.folder.items };
    }

    fn refreshAvailable(self: *State) void {
        var buf: [kLangCount]Language = undefined;
        self.available = @splat(false);
        for (ops.availableLanguages(self.folder.items, &buf)) |l| self.available[@intFromEnum(l)] = true;
        self.available_age = 0;
    }

    fn set(self: *State, alloc: std.mem.Allocator, field: Field, path: []const u8) void {
        const list = switch (field) {
            .rom => &self.rom,
            .out => &self.out,
            .verify => &self.verify,
            .folder => &self.folder,
            .lang_rom => &self.lang_rom,
        };
        list.clearRetainingCapacity();
        list.appendSlice(alloc, path) catch {};
    }

    fn get(self: *State, field: Field) []const u8 {
        return switch (field) {
            .rom => self.rom.items,
            .out => self.out.items,
            .verify => self.verify.items,
            .folder => self.folder.items,
            .lang_rom => self.lang_rom.items,
        };
    }
};

/// Where a file called `name` would sit in the game's folder: beside this
/// program for a plain install, or in the game's data directory when this
/// runs from an app bundle or AppImage, which are read-only.
fn inGameDir(alloc: std.mem.Allocator, name: []const u8) []const u8 {
    const base_z = c.SDL_GetBasePath() orelse return name;
    const base = std.mem.span(base_z);
    if (@import("menu.zig").isPackaged(base)) {
        const pref = c.SDL_GetPrefPath("", "alttp-zig") orelse return name;
        defer c.SDL_free(pref);
        return std.fmt.allocPrint(alloc, "{s}{s}", .{ std.mem.span(pref), name }) catch name;
    }
    return std.fmt.allocPrint(alloc, "{s}{s}", .{ base, name }) catch name;
}

fn exists(alloc: std.mem.Allocator, path: []const u8) bool {
    const z = alloc.dupeZ(u8, path) catch return false;
    defer alloc.free(z);
    return @import("fileio.zig").exists(z.ptr);
}

// -------------------------------------------------------------- immediate UI

const Ui = struct {
    r: *c.SDL_Renderer,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    clicked: bool = false,

    fn color(self: Ui, rgb: Rgb) void {
        _ = c.SDL_SetRenderDrawColor(self.r, @truncate(rgb >> 16), @truncate(rgb >> 8), @truncate(rgb), 255);
    }

    fn fill(self: Ui, rect: Rect, rgb: Rgb) void {
        self.color(rgb);
        const f = c.SDL_FRect{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
        _ = c.SDL_RenderFillRect(self.r, &f);
    }

    fn text(self: Ui, x: f32, y: f32, rgb: Rgb, s: []const u8) void {
        var buf: [256]u8 = undefined;
        const n = @min(s.len, buf.len - 1);
        @memcpy(buf[0..n], s[0..n]);
        buf[n] = 0;
        self.color(rgb);
        _ = c.SDL_SetRenderScale(self.r, kScale, kScale);
        _ = c.SDL_RenderDebugText(self.r, x / kScale, y / kScale, @ptrCast(&buf));
        _ = c.SDL_SetRenderScale(self.r, 1, 1);
    }

    fn hovered(self: Ui, rect: Rect) bool {
        return rect.contains(self.mouse_x, self.mouse_y);
    }

    /// A button; true on the frame it's clicked.
    fn button(self: Ui, rect: Rect, label: []const u8, enabled: bool) bool {
        const hot = enabled and self.hovered(rect);
        self.fill(rect, if (!enabled) kDisabled else if (hot) kButtonHover else kButton);
        const tw: f32 = @floatFromInt(label.len * kCharW);
        self.text(rect.x + (rect.w - tw) / 2, rect.y + (rect.h - 8 * kScale) / 2, if (enabled) kButtonText else kDim, label);
        return hot and self.clicked;
    }

    /// A button sized to its label, placed at x; advances x past it.
    fn buttonAt(self: Ui, x: *f32, y: f32, label: []const u8, enabled: bool) bool {
        const w: f32 = @floatFromInt(label.len * kCharW + 40);
        defer x.* += w + 16;
        return self.button(.{ .x = x.*, .y = y, .w = w, .h = 40 }, label, enabled);
    }

    /// A checkbox and its label; true on the frame it's clicked.
    fn checkbox(self: Ui, x: f32, y: f32, label: []const u8, on: bool) bool {
        return self.checkboxEx(x, y, label, on, true);
    }

    fn checkboxEx(self: Ui, x: f32, y: f32, label: []const u8, on: bool, enabled: bool) bool {
        const box = Rect{ .x = x, .y = y, .w = 20, .h = 20 };
        const hit = Rect{ .x = x, .y = y, .w = 28 + @as(f32, @floatFromInt(label.len * kCharW)), .h = 20 };
        const hot = enabled and self.hovered(hit);
        self.fill(box, if (!enabled) kDisabled else if (hot) kButtonHover else kButton);
        if (on and enabled) self.fill(.{ .x = x + 5, .y = y + 5, .w = 10, .h = 10 }, kAccent);
        self.text(x + 30, y + 2, if (enabled) kText else kDim, label);
        return hot and self.clicked;
    }

    /// A labelled path with a Browse button. True when Browse is clicked.
    fn pathField(self: Ui, x: f32, y: f32, w: f32, label: []const u8, path: []const u8, placeholder: []const u8) bool {
        self.text(x, y, kDim, label);
        const box = Rect{ .x = x, .y = y + kLineH, .w = w - 140, .h = 32 };
        self.fill(box, kPanel);
        const cols: usize = @intFromFloat((box.w - 16) / kCharW);
        if (path.len == 0) {
            self.text(box.x + 8, box.y + 8, kDim, placeholder);
        } else if (path.len <= cols) {
            self.text(box.x + 8, box.y + 8, kText, path);
        } else {
            // Long paths keep their end, which is the part that matters.
            var buf: [256]u8 = undefined;
            const shown = std.fmt.bufPrint(&buf, "...{s}", .{path[path.len - (cols - 3) ..]}) catch path;
            self.text(box.x + 8, box.y + 8, kText, shown);
        }
        return self.button(.{ .x = box.x + box.w + 12, .y = box.y, .w = 128, .h = 32 }, "Browse", true);
    }

    /// Wrapped paragraph text; returns the height it took.
    fn paragraph(self: Ui, x: f32, y: f32, w: f32, rgb: Rgb, s: []const u8) f32 {
        const cols: usize = @intFromFloat(w / kCharW);
        var line_y = y;
        var rest = s;
        while (rest.len > 0) {
            var n = @min(rest.len, cols);
            if (n < rest.len) {
                if (std.mem.lastIndexOfScalar(u8, rest[0..n], ' ')) |sp| n = sp;
            }
            self.text(x, line_y, rgb, rest[0..n]);
            rest = std.mem.trimStart(u8, rest[n..], " ");
            line_y += kLineH;
        }
        return line_y - y;
    }
};

// ------------------------------------------------------------------- pages

const kLangCount = @typeInfo(Language).@"enum".fields.len;

const kContentX = kSidebarW + 32;
const kContentW = kWindowW - kSidebarW - 64;

fn drawAssets(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    var y: f32 = 32;
    ui.text(kContentX, y, kAccent, "Build the game's assets");
    y += kLineH + 8;
    y += ui.paragraph(kContentX, y, kContentW, kDim, "zelda3_assets.dat holds everything the game takes from the ROM. Build it once from the US release and the ROM isn't needed again.");
    y += 16;

    if (ui.pathField(kContentX, y, kContentW, "US ROM", st.get(.rom), "Drop a .sfc or .smc here, or Browse")) openDialog(window, .rom);
    y += kLineH + 48;
    if (ui.pathField(kContentX, y, kContentW, "Write to", st.get(.out), "zelda3_assets.dat")) openDialog(window, .out);
    y += kLineH + 56;

    const can_build = st.get(.rom).len != 0 and st.get(.out).len != 0;
    var x: f32 = kContentX;
    if (ui.buttonAt(&x, y, "Build Assets", can_build)) runJob(alloc, st, .build);
    if (ui.buttonAt(&x, y, "Check ROM", st.get(.rom).len != 0)) runJob(alloc, st, .rom_info);
    if (ui.buttonAt(&x, y, "Verify Assets", st.get(.out).len != 0)) runJob(alloc, st, .verify);
}

fn drawModding(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    var y: f32 = 32;
    ui.text(kContentX, y, kAccent, "Edit the game's data");
    y += kLineH + 8;
    y += ui.paragraph(kContentX, y, kContentW, kDim, "Export writes the world, the dialogue, the graphics and the music out as YAML, text and PNG. Change them, then build the asset file from the folder.");
    y += 16;

    if (ui.pathField(kContentX, y, kContentW, "US ROM", st.get(.rom), "Drop a .sfc or .smc here, or Browse")) openDialog(window, .rom);
    y += kLineH + 48;
    if (ui.pathField(kContentX, y, kContentW, "Folder", st.get(.folder), "Where the files go, and come back from")) openDialog(window, .folder);
    y += kLineH + 48;
    if (ui.pathField(kContentX, y, kContentW, "Write to", st.get(.out), "zelda3_assets.dat")) openDialog(window, .out);
    y += kLineH + 56;

    if (ui.checkbox(kContentX, y, "Build the sprite sheets from sprites/ too", st.sprites_from_png)) st.sprites_from_png = !st.sprites_from_png;
    y += kLineH + 12;

    const ready = st.get(.rom).len != 0 and st.get(.folder).len != 0;
    var x: f32 = kContentX;
    if (ui.buttonAt(&x, y, "Export Files", ready)) runJob(alloc, st, .export_files);
    if (ui.buttonAt(&x, y, "Build From Files", ready and st.get(.out).len != 0)) runJob(alloc, st, .build_from_files);
}

/// Short names, so three fit across.
fn shortName(lang: Language) []const u8 {
    return switch (lang) {
        .us => "English (US)",
        .de => "German",
        .fr => "French",
        .fr_c => "French (CA)",
        .en => "English (EU)",
        .es => "Spanish",
        .pl => "Polish",
        .pt => "Portuguese",
        .redux => "Redux",
        .nl => "Dutch",
        .sv => "Swedish",
    };
}

fn drawLanguages(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    if (st.available_age == 0 or st.available_age > 60) st.refreshAvailable();
    st.available_age += 1;

    var y: f32 = 32;
    ui.text(kContentX, y, kAccent, "Play in another language");
    y += kLineH + 8;
    y += ui.paragraph(kContentX, y, kContentW, kDim, "Extract the text from a translated ROM into the folder, tick it, and build. Ticked languages go into every build.");
    y += 12;

    if (ui.pathField(kContentX, y, kContentW, "Translated ROM", st.get(.lang_rom), "A German, French, Spanish... ROM")) openDialog(window, .lang_rom);
    y += kLineH + 44;
    if (ui.pathField(kContentX, y, kContentW, "Folder", st.get(.folder), "Where the extracted text goes")) openDialog(window, .folder);
    y += kLineH + 50;

    const col_w: f32 = kContentW / 3;
    var n: usize = 0;
    for (std.enums.values(Language)) |lang| {
        if (lang == .us) continue;
        const i = @intFromEnum(lang);
        const x = kContentX + @as(f32, @floatFromInt(n % 3)) * col_w;
        const row_y = y + @as(f32, @floatFromInt(n / 3)) * 28;
        if (ui.checkboxEx(x, row_y, shortName(lang), st.picked[i], st.available[i])) st.picked[i] = !st.picked[i];
        n += 1;
    }
    y += @as(f32, @floatFromInt((n + 2) / 3)) * 28 + 12;

    var x: f32 = kContentX;
    if (ui.buttonAt(&x, y, "Extract Dialogue", st.get(.lang_rom).len != 0 and st.get(.folder).len != 0)) runJob(alloc, st, .extract_dialogue);
    if (ui.buttonAt(&x, y, "Build Assets", st.get(.rom).len != 0 and st.get(.out).len != 0)) runJob(alloc, st, .build);
}

const Job = enum { build, rom_info, verify, export_files, build_from_files, extract_dialogue };

fn runJob(alloc: std.mem.Allocator, st: *State, job: Job) void {
    const rom = alloc.dupeZ(u8, st.get(.rom)) catch return;
    defer alloc.free(rom);
    const out = alloc.dupeZ(u8, st.get(.out)) catch return;
    defer alloc.free(out);
    const folder = alloc.dupeZ(u8, st.get(.folder)) catch return;
    defer alloc.free(folder);
    const lang_rom = alloc.dupeZ(u8, st.get(.lang_rom)) catch return;
    defer alloc.free(lang_rom);
    defer st.refreshAvailable();
    pushLine(.info, "");
    switch (job) {
        .build => _ = ops.buildAssets(alloc, g_logger, rom, out, st.extra()),
        .rom_info => _ = ops.romInfo(alloc, g_logger, rom),
        .verify => _ = ops.verifyAssets(alloc, g_logger, out),
        .export_files => _ = ops.exportFiles(alloc, g_logger, rom, folder),
        .build_from_files => _ = ops.buildFromFiles(alloc, g_logger, rom, folder, out, .{ .sprites_from_png = st.sprites_from_png }, st.extra()),
        .extract_dialogue => _ = ops.extractDialogue(alloc, g_logger, lang_rom, folder, null),
    }
}

fn drawSidebar(ui: *Ui, st: *State) void {
    ui.fill(.{ .x = 0, .y = 0, .w = kSidebarW, .h = kWindowH }, kSidebar);
    ui.text(20, 24, kAccent, "zelda3");
    ui.text(20, 24 + kLineH, kAccent, "tools");
    var y: f32 = 110;
    inline for (std.meta.fields(Page)) |f| {
        const page: Page = @enumFromInt(f.value);
        const rect = Rect{ .x = 0, .y = y, .w = kSidebarW, .h = 40 };
        const selected = st.page == page;
        if (selected) ui.fill(rect, kPanel) else if (ui.hovered(rect)) ui.fill(rect, kPanelHover);
        if (selected) ui.fill(.{ .x = 0, .y = y, .w = 4, .h = 40 }, kAccent);
        ui.text(24, y + 12, if (selected) kText else kDim, page.title());
        if (ui.hovered(rect) and ui.clicked) st.page = page;
        y += 44;
    }
}

fn drawLog(ui: *Ui) void {
    const top: f32 = kWindowH - kLogH;
    ui.fill(.{ .x = kSidebarW, .y = top, .w = kWindowW - kSidebarW, .h = kLogH }, kLogBg);
    const rows: usize = @intFromFloat((kLogH - 16) / kLineH);
    const end = g_log_count - @min(g_log_scroll, g_log_count);
    const start = end -| rows;
    var y: f32 = top + 10;
    for (g_log[start..end]) |line| {
        const rgb: Rgb = switch (line.level) {
            .info => kText,
            .ok => kOk,
            .err => kErr,
        };
        ui.text(kSidebarW + 16, y, rgb, line.text[0..line.len]);
        y += kLineH;
    }
}

// ------------------------------------------------------------------- main

fn initialState(alloc: std.mem.Allocator) State {
    var st = State{};
    // Sensible starting points: a ROM in the game's folder or the current
    // one, and the asset file in the game's folder, where the game looks.
    for ([_][]const u8{ inGameDir(alloc, "zelda3.sfc"), "zelda3.sfc", inGameDir(alloc, "zelda3.smc"), "zelda3.smc" }) |p| {
        if (st.rom.items.len == 0 and exists(alloc, p)) st.set(alloc, .rom, p);
    }
    st.set(alloc, .out, inGameDir(alloc, "zelda3_assets.dat"));
    st.set(alloc, .folder, inGameDir(alloc, "zelda3_files"));
    pushLine(.info, "Ready. Pick a section on the left.");
    return st;
}

fn drawFrame(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    ui.fill(.{ .x = 0, .y = 0, .w = kWindowW, .h = kWindowH }, kBg);
    drawSidebar(ui, st);
    switch (st.page) {
        .assets => drawAssets(ui, alloc, st, window),
        .modding => drawModding(ui, alloc, st, window),
        .languages => drawLanguages(ui, alloc, st, window),
    }
    drawLog(ui);
}

/// Draws one frame of a page into a BMP with no window, for looking at the
/// layout while working on it: `zelda3-tools gui-screenshot out.bmp [page]`.
/// `log` lines are fed through the real log first, so it shows populated;
/// ones like "@rom=path" set a field instead (rom, out, folder, lang_rom),
/// "@pick=de,fr" ticks languages and "@sprites" ticks the sprite sheets.
pub fn screenshot(alloc: std.mem.Allocator, path: [:0]const u8, page_name: ?[]const u8, log_lines: []const [:0]const u8) !void {
    const surface = c.SDL_CreateSurface(kWindowW, kWindowH, c.SDL_PIXELFORMAT_XRGB8888) orelse return error.SdlSurface;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    var st = initialState(alloc);
    if (page_name) |name| {
        inline for (std.meta.fields(Page)) |f| {
            if (std.ascii.eqlIgnoreCase(f.name, name)) st.page = @enumFromInt(f.value);
        }
    }
    var picks: ?[]const u8 = null;
    for (log_lines) |line| {
        if (std.mem.startsWith(u8, line, "@")) {
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse line.len;
            const key = line[1..eq];
            const value = if (eq < line.len) line[eq + 1 ..] else "";
            if (std.mem.eql(u8, key, "pick")) {
                picks = value;
            } else if (std.mem.eql(u8, key, "sprites")) {
                st.sprites_from_png = true;
            } else if (std.meta.stringToEnum(Field, key)) |f| st.set(alloc, f, value);
            continue;
        }
        const level: ops.Log.Level = if (std.mem.startsWith(u8, line, "!")) .err else if (std.mem.startsWith(u8, line, "+")) .ok else .info;
        logWrite(&g_log_dummy, level, if (level == .info) line else line[1..]);
    }
    st.refreshAvailable();
    if (picks) |p| {
        var it = std.mem.tokenizeScalar(u8, p, ',');
        while (it.next()) |code| {
            if (@import("asset_languages.zig").fromCode(code)) |l| st.picked[@intFromEnum(l)] = true;
        }
    }
    var ui = Ui{ .r = renderer, .mouse_x = -1, .mouse_y = -1 };
    drawFrame(&ui, alloc, &st, null);
    _ = c.SDL_RenderPresent(renderer);
    if (!c.SDL_SaveBMP(surface, path.ptr)) return error.SaveFailed;
}

pub fn run(alloc: std.mem.Allocator) !void {
    if (builtin.os.tag == .macos) _ = c.SDL_SetHint(c.SDL_HINT_JOYSTICK_MFI, "0");
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("Could not start SDL: {s}\n", .{c.SDL_GetError()});
        return error.SdlInit;
    }
    defer c.SDL_Quit();
    const window = c.SDL_CreateWindow("zelda3 tools", kWindowW, kWindowH, 0) orelse return error.SdlWindow;
    defer c.SDL_DestroyWindow(window);
    const renderer = c.SDL_CreateRenderer(window, null) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    _ = c.SDL_SetRenderVSync(renderer, 1);
    g_dialog_lock = c.SDL_CreateMutex();
    defer c.SDL_DestroyMutex(g_dialog_lock);

    var st = initialState(alloc);

    var ui = Ui{ .r = renderer };
    var running = true;
    while (running) {
        ui.clicked = false;
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_MOUSE_MOTION => {
                    ui.mouse_x = event.motion.x;
                    ui.mouse_y = event.motion.y;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    ui.mouse_x = event.button.x;
                    ui.mouse_y = event.button.y;
                    if (event.button.button == c.SDL_BUTTON_LEFT) ui.clicked = true;
                },
                c.SDL_EVENT_MOUSE_WHEEL => {
                    if (ui.mouse_y >= kWindowH - kLogH) {
                        if (event.wheel.y > 0) g_log_scroll = @min(g_log_scroll + 1, g_log_count) else g_log_scroll -|= 1;
                    }
                },
                // A dropped ROM fills in the ROM; a dropped asset file is
                // taken as the one to write or check.
                c.SDL_EVENT_DROP_FILE => if (event.drop.data) |p| {
                    const path = std.mem.span(p);
                    const lower = std.ascii.allocLowerString(alloc, path) catch path;
                    if (std.mem.endsWith(u8, lower, ".dat")) {
                        st.set(alloc, .out, path);
                    } else st.set(alloc, if (st.page == .languages) .lang_rom else .rom, path);
                },
                else => {},
            }
        }

        c.SDL_LockMutex(g_dialog_lock);
        if (g_dialog_result) |path| {
            st.set(alloc, if (g_dialog_field == .verify) .out else g_dialog_field, path);
            alloc.free(path);
            g_dialog_result = null;
        }
        c.SDL_UnlockMutex(g_dialog_lock);

        drawFrame(&ui, alloc, &st, window);
        _ = c.SDL_RenderPresent(renderer);
    }
}
