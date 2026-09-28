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
        const n = @min(rest.len, cols);
        pushLine(level, rest[0..n]);
        rest = rest[n..];
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
const Field = enum { rom, out, verify };

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
        .rom => c.SDL_ShowOpenFileDialog(dialogCallback, userdata, window, &kRomFilters, kRomFilters.len, null, false),
        .verify => c.SDL_ShowOpenFileDialog(dialogCallback, userdata, window, &kDatFilters, kDatFilters.len, null, false),
        .out => c.SDL_ShowSaveFileDialog(dialogCallback, userdata, window, &kDatFilters, kDatFilters.len, null),
    }
}

// ----------------------------------------------------------------- the state

const Page = enum {
    assets,

    fn title(self: Page) []const u8 {
        return switch (self) {
            .assets => "Assets",
        };
    }
};

const State = struct {
    page: Page = .assets,
    rom: std.ArrayList(u8) = .empty,
    out: std.ArrayList(u8) = .empty,
    verify: std.ArrayList(u8) = .empty,

    fn set(self: *State, alloc: std.mem.Allocator, field: Field, path: []const u8) void {
        const list = switch (field) {
            .rom => &self.rom,
            .out => &self.out,
            .verify => &self.verify,
        };
        list.clearRetainingCapacity();
        list.appendSlice(alloc, path) catch {};
    }

    fn get(self: *State, field: Field) []const u8 {
        return switch (field) {
            .rom => self.rom.items,
            .out => self.out.items,
            .verify => self.verify.items,
        };
    }
};

/// Where a file called `name` would sit next to this program.
fn besideExe(alloc: std.mem.Allocator, name: []const u8) []const u8 {
    const base = c.SDL_GetBasePath() orelse return name;
    return std.fmt.allocPrint(alloc, "{s}{s}", .{ std.mem.span(base), name }) catch name;
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

const Job = enum { build, rom_info, verify };

fn runJob(alloc: std.mem.Allocator, st: *State, job: Job) void {
    const rom = alloc.dupeZ(u8, st.get(.rom)) catch return;
    defer alloc.free(rom);
    const out = alloc.dupeZ(u8, st.get(.out)) catch return;
    defer alloc.free(out);
    pushLine(.info, "");
    switch (job) {
        .build => _ = ops.buildAssets(alloc, g_logger, rom, out),
        .rom_info => _ = ops.romInfo(alloc, g_logger, rom),
        .verify => _ = ops.verifyAssets(alloc, g_logger, out),
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
    // Sensible starting points: a ROM beside the program or in the current
    // folder, and the asset file beside the program, where the game looks.
    for ([_][]const u8{ besideExe(alloc, "zelda3.sfc"), "zelda3.sfc", besideExe(alloc, "zelda3.smc"), "zelda3.smc" }) |p| {
        if (st.rom.items.len == 0 and exists(alloc, p)) st.set(alloc, .rom, p);
    }
    st.set(alloc, .out, besideExe(alloc, "zelda3_assets.dat"));
    pushLine(.info, "Ready. Pick a section on the left.");
    return st;
}

fn drawFrame(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    ui.fill(.{ .x = 0, .y = 0, .w = kWindowW, .h = kWindowH }, kBg);
    drawSidebar(ui, st);
    switch (st.page) {
        .assets => drawAssets(ui, alloc, st, window),
    }
    drawLog(ui);
}

/// Draws one frame of a page into a BMP with no window, for looking at the
/// layout while working on it: `zelda3-tools gui-screenshot out.bmp [page]`.
/// `log` lines are fed through the real log first, so it shows populated.
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
    for (log_lines) |line| logWrite(&g_log_dummy, if (std.mem.startsWith(u8, line, "!")) .err else .info, line);
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
                    if (std.mem.endsWith(u8, lower, ".dat")) st.set(alloc, .out, path) else st.set(alloc, .rom, path);
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
