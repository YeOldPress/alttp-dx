//! The zelda3-tools window, dressed like the game's start menu.
//!
//! The same card on the same dark ground, the game's title over it, and the
//! sections as tabs under that. Each section is a short stack of rows and
//! buttons that the mouse, the keys and a pad all drive, with a log along the
//! bottom that every job reports into. Jobs run on a thread of their own, so
//! the window keeps drawing while a build takes its time. Paths come from the
//! system's own file dialogs, or from dropping a file on the window.
const std = @import("std");
const builtin = @import("builtin");
const c = @import("sdl.zig").c;
const ops = @import("tools_ops.zig");
const kit = @import("menu_kit.zig");
const menu = @import("menu.zig");
const updater = @import("updater.zig");
const fileio = @import("fileio.zig");
const music = @import("tools_music.zig");
const pictures = @import("tools_pictures.zig");
const game = @import("tools_game.zig");
const rom_mod = @import("rom.zig");
const Language = rom_mod.Language;

const Rect = kit.Rect;
const Rgb = kit.Rgb;
const kScale = kit.kScale;
const kCell = kit.kCell;
const kRowH = kit.kRowH;

const kWindowW = 1024;
const kWindowH = 680;
/// Inside the card: where everything lines up on the left, and how far it
/// can reach.
const kMarginX: f32 = 48;
const kContentW: f32 = kWindowW - kMarginX * 2;
const kTabsY: f32 = 118;
const kContentY: f32 = 164;
const kLogY: f32 = 494;
const kLogH: f32 = 122;
const kFooterY: f32 = kWindowH - 32 - kRowH;
const kLogLineH: f32 = kRowH + 2;
/// The labels in front of the path boxes, and the Browse chip after them.
const kLabelW: f32 = 256;
const kBrowseW: f32 = 128;
const kButtonH: f32 = 8 * kScale + 18;
/// From one row of a page to the next.
const kRowStep: f32 = 38;

/// For the buttons that aren't a page's main job, which are green.
const kColorButton = Rgb{ .r = 0x33, .g = 0x45, .b = 0x6c };
const kColorLogBg = Rgb{ .r = 0x0b, .g = 0x0f, .b = 0x18 };

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
/// Jobs write from their own thread while the window draws.
var g_log_lock: ?*c.SDL_Mutex = null;

const kLogCols: usize = @intFromFloat((kContentW - 32) / kCell);
const kLogRows: usize = @intFromFloat((kLogH - 12) / kLogLineH);

fn logWrite(ctx: *anyopaque, level: ops.Log.Level, text: []const u8) void {
    _ = ctx;
    c.SDL_LockMutex(g_log_lock);
    defer c.SDL_UnlockMutex(g_log_lock);
    // Long lines are wrapped to the log's width here, once, rather than at
    // every draw.
    var rest = text;
    while (true) {
        var n: usize = @min(rest.len, kLogCols);
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

fn scrollLog(lines: i32) void {
    c.SDL_LockMutex(g_log_lock);
    defer c.SDL_UnlockMutex(g_log_lock);
    const most = g_log_count -| kLogRows;
    if (lines > 0) g_log_scroll = @min(g_log_scroll + @as(usize, @intCast(lines)), most) else g_log_scroll -|= @as(usize, @intCast(-lines));
}

var g_log_dummy: u8 = 0;
const g_logger = ops.Log{ .ctx = &g_log_dummy, .writeFn = logWrite };

// ------------------------------------------------------------ file dialogs

/// Every path the window keeps. A dialog's answer can arrive on another
/// thread, so it lands here under a lock and the main loop picks it up.
const Field = enum { rom, out, folder, lang_rom, zspr, msu, snapshot, dialogue };
const kFieldCount = @typeInfo(Field).@"enum".field_names.len;

var g_dialog_lock: ?*c.SDL_Mutex = null;
var g_dialog_field: Field = .rom;
var g_dialog_result: ?[:0]u8 = null;

fn dialogCallback(userdata: ?*anyopaque, filelist: [*c]const [*c]const u8, filter: c_int) callconv(.c) void {
    _ = filter;
    const field: Field = @fromBackingInt(@intCast(@intFromPtr(userdata) - 1));
    if (filelist == null or filelist[0] == null) return; // failed, or cancelled
    const path = std.mem.span(filelist[0]);
    const copy = std.heap.c_allocator.dupeSentinel(u8, path, 0) catch return;
    c.SDL_LockMutex(g_dialog_lock);
    defer c.SDL_UnlockMutex(g_dialog_lock);
    if (g_dialog_result) |old| std.heap.c_allocator.free(old);
    g_dialog_result = copy;
    g_dialog_field = field;
}

const kRomFilters = [_]c.SDL_DialogFileFilter{.{ .name = "SNES ROM", .pattern = "sfc;smc" }};
const kDatFilters = [_]c.SDL_DialogFileFilter{.{ .name = "Asset file", .pattern = "dat" }};
const kZsprFilters = [_]c.SDL_DialogFileFilter{.{ .name = "Link sprite", .pattern = "zspr" }};
/// A pack is a folder or a zip; picking any track in a folder means the
/// folder.
const kMsuFilters = [_]c.SDL_DialogFileFilter{.{ .name = "MSU-1 pack, or a track in one", .pattern = "zip;msu;pcm;opuz" }};
const kSavFilters = [_]c.SDL_DialogFileFilter{.{ .name = "Snapshot", .pattern = "sav" }};
const kTxtFilters = [_]c.SDL_DialogFileFilter{.{ .name = "Dialogue", .pattern = "txt" }};

fn openDialog(window_opt: ?*c.SDL_Window, field: Field) void {
    const window = window_opt orelse return;
    const userdata: ?*anyopaque = @ptrFromInt(@backingInt(field) + 1);
    const filters: []const c.SDL_DialogFileFilter = switch (field) {
        .rom, .lang_rom => &kRomFilters,
        .out => return c.SDL_ShowSaveFileDialog(dialogCallback, userdata, window, &kDatFilters, kDatFilters.len, null),
        .folder => return c.SDL_ShowOpenFolderDialog(dialogCallback, userdata, window, null, false),
        .zspr => &kZsprFilters,
        .msu => &kMsuFilters,
        .snapshot => &kSavFilters,
        .dialogue => &kTxtFilters,
    };
    c.SDL_ShowOpenFileDialog(dialogCallback, userdata, window, filters.ptr, @intCast(filters.len), null, false);
}

// ----------------------------------------------------------------- the state

const Page = enum {
    assets,
    modding,
    graphics,
    music,
    languages,
    extras,

    fn title(self: Page) []const u8 {
        return switch (self) {
            .assets => "ASSETS",
            .modding => "MODDING",
            .graphics => "GRAPHICS",
            .music => "MUSIC",
            .languages => "LANGUAGES",
            .extras => "EXTRAS",
        };
    }

    /// The next page along, or the one before, going round.
    fn step(self: Page, dir: i32) Page {
        const n: i32 = @intCast(kPageCount);
        return @fromBackingInt(@intCast(@mod(@as(i32, @backingInt(self)) + dir, n)));
    }
};
const kPageCount = @typeInfo(Page).@"enum".field_names.len;

/// A question over the page, which takes the keys until it's answered.
const Modal = enum { none, quit, update };
const kQuitChoices = [_][]const u8{ "QUIT", "STAY" };
const kUpdateChoices = [_][]const u8{ "UPDATE", "NOT NOW" };
const kUpdateFailedChoices = [_][]const u8{ "OPEN PAGE", "CLOSE" };

const State = struct {
    page: Page = .assets,
    paths: [kFieldCount]std.ArrayList(u8) = @splat(.empty),
    sprites_from_png: bool = false,
    /// Translations ticked to build in, and which ones the folder has files
    /// for, checked now and then rather than every frame.
    picked: [kLangCount]bool = @splat(false),
    available: [kLangCount]bool = @splat(false),
    available_age: u32 = 0,
    extra_buf: [kLangCount]Language = undefined,
    modal: Modal = .none,
    /// Which of the modal's two answers is picked.
    choice: usize = 0,
    /// Where the focus was before a modal took it, to go back to after.
    focus_before: usize = 0,
    quit: bool = false,

    /// The game, to start with Play, when it's somewhere the tools can see.
    game_buf: [4096]u8 = undefined,
    game: ?[:0]const u8 = null,

    /// Rebuilding when the work folder changes: on or off, the folder's
    /// stamp as of the last build or look, and when it was last looked at.
    watch: bool = false,
    watch_built: u64 = 0,
    watch_seen: u64 = 0,
    watch_at: u64 = 0,

    gfx: Gallery = .{},
    tunes: Tunes = .{},

    /// The ROM last looked at, and what it turned out to be, so the pages
    /// can say every frame without reading it every frame.
    rom_seen: std.ArrayList(u8) = .empty,
    rom_kind: RomKind = .unreadable,

    /// The ticked translations the folder has files for.
    fn extra(self: *State) ops.Extra {
        var n: usize = 0;
        for (0..kLangCount) |i| {
            if (!self.picked[i] or !self.available[i]) continue;
            self.extra_buf[n] = @fromBackingInt(@intCast(i));
            n += 1;
        }
        return .{ .languages = self.extra_buf[0..n], .dir = self.get(.folder) };
    }

    fn refreshAvailable(self: *State) void {
        var buf: [kLangCount]Language = undefined;
        self.available = @splat(false);
        for (ops.availableLanguages(self.get(.folder), &buf)) |l| self.available[@backingInt(l)] = true;
        self.available_age = 0;
    }

    fn set(self: *State, alloc: std.mem.Allocator, field: Field, path: []const u8) void {
        const list = &self.paths[@backingInt(field)];
        list.clearRetainingCapacity();
        list.appendSlice(alloc, path) catch {};
    }

    fn get(self: *const State, field: Field) []const u8 {
        return self.paths[@backingInt(field)].items;
    }

    /// Puts a question up, with the focus on `choice`. Its answers are all
    /// it lets register, so they're items 0 and 1 while it's up.
    fn openModal(self: *State, ui: *Ui, modal: Modal, choice: usize) void {
        if (self.modal == .none) self.focus_before = ui.focus;
        self.modal = modal;
        self.choice = choice;
        ui.focus = choice;
    }

    fn closeModal(self: *State, ui: *Ui) void {
        self.modal = .none;
        ui.focus = self.focus_before;
    }

    /// Whether Play has a game to start. A packaged Mac can always ask
    /// Launch Services, which knows where the game was put.
    fn canPlay(self: *const State) bool {
        if (self.game != null) return true;
        const base = std.mem.span(c.SDL_GetBasePath() orelse return false);
        return builtin.os.tag == .macos and menu.isPackaged(base);
    }
};

/// Where a file called `name` would sit in the game's folder: beside this
/// program for a plain install, or in the game's data directory when this
/// runs from an app bundle or AppImage, which are read-only.
fn inGameDir(alloc: std.mem.Allocator, name: []const u8) []const u8 {
    const base_z = c.SDL_GetBasePath() orelse return name;
    const base = std.mem.span(base_z);
    if (menu.isPackaged(base)) {
        const pref = menu.dataDirectory() orelse return name;
        defer c.SDL_free(pref);
        return std.fmt.allocPrint(alloc, "{s}{s}", .{ std.mem.span(pref), name }) catch name;
    }
    return std.fmt.allocPrint(alloc, "{s}{s}", .{ base, name }) catch name;
}

/// Where the game will look for its asset file: its data directory when the
/// tools are packaged (and so is it), or the folder it runs from.
fn gameAssetPath(alloc: std.mem.Allocator, st: *const State) []const u8 {
    if (st.game) |g| {
        if (game.folderOf(g)) |dir| return std.fmt.allocPrint(alloc, "{s}{s}zelda3_assets.dat", .{ dir, std.fs.path.sep_str }) catch "zelda3_assets.dat";
    }
    return inGameDir(alloc, "zelda3_assets.dat");
}

fn exists(alloc: std.mem.Allocator, path: []const u8) bool {
    const z = alloc.dupeSentinel(u8, path, 0) catch return false;
    defer alloc.free(z);
    return fileio.exists(z.ptr);
}

/// Starts the game, and says so, and says if it won't see what was just
/// built because that was saved somewhere it doesn't look.
fn play(alloc: std.mem.Allocator, st: *State) void {
    if (!game.start(st.game)) {
        g_logger.err("Couldn't start the game. Keep the tools beside it, where the downloads put them.", .{});
        return;
    }
    g_logger.ok("Starting the game.", .{});
    const expected = gameAssetPath(alloc, st);
    if (!std.mem.eql(u8, expected, st.get(.out)))
        g_logger.info("It reads its assets from {s}, not from where these were saved.", .{expected});
}

// ------------------------------------------------------------------- jobs

const Job = enum {
    build,
    rom_info,
    verify,
    export_files,
    build_from_files,
    extract_dialogue,
    check_msu,
    input_log,
    text_dict,

    /// What the footer says while it runs.
    fn doing(self: Job) []const u8 {
        return switch (self) {
            .build => "Building the assets",
            .rom_info => "Checking the ROM",
            .verify => "Checking the assets",
            .export_files => "Exporting the files",
            .build_from_files => "Building from your files",
            .extract_dialogue => "Extracting the dialogue",
            .check_msu => "Checking the pack",
            .input_log => "Reading the input log",
            .text_dict => "Searching for a dictionary",
        };
    }

    /// Whether it writes into the work folder, which isn't an edit to
    /// rebuild for.
    fn writesFolder(self: Job) bool {
        return self == .export_files or self == .extract_dialogue;
    }
};

/// What a job works from, copied out of the window's state so the window
/// can go on changing while it runs.
const JobArgs = struct {
    job: Job,
    paths: [kFieldCount][:0]u8,
    languages: [kLangCount]Language = undefined,
    language_count: usize = 0,
    sprites_from_png: bool,

    fn get(self: *const JobArgs, field: Field) [:0]u8 {
        return self.paths[@backingInt(field)];
    }

    fn free(self: *JobArgs, alloc: std.mem.Allocator) void {
        for (self.paths) |p| alloc.free(p);
        alloc.destroy(self);
    }
};

var g_job_running = std.atomic.Value(bool).init(false);
/// The job running, or the last one to.
var g_job: Job = .build;

fn jobRunning() bool {
    return g_job_running.load(.acquire);
}

fn startJob(alloc: std.mem.Allocator, st: *State, job: Job) void {
    if (jobRunning()) return;
    const args = makeJobArgs(alloc, st, job) catch {
        g_logger.err("Out of memory.", .{});
        return;
    };
    logWrite(&g_log_dummy, .info, "");
    g_job = job;
    g_job_running.store(true, .release);
    const t = std.Thread.spawn(.{}, jobThread, .{ alloc, args }) catch {
        g_job_running.store(false, .release);
        args.free(alloc);
        g_logger.err("Could not start the job.", .{});
        return;
    };
    t.detach();
}

fn makeJobArgs(alloc: std.mem.Allocator, st: *State, job: Job) !*JobArgs {
    const args = try alloc.create(JobArgs);
    errdefer alloc.destroy(args);
    args.* = .{ .job = job, .paths = undefined, .sprites_from_png = st.sprites_from_png };
    var made: usize = 0;
    errdefer for (args.paths[0..made]) |p| alloc.free(p);
    for (&args.paths, 0..) |*p, i| {
        p.* = try alloc.dupeSentinel(u8, st.paths[i].items, 0);
        made += 1;
    }
    const langs = st.extra().languages;
    @memcpy(args.languages[0..langs.len], langs);
    args.language_count = langs.len;
    return args;
}

fn jobThread(alloc: std.mem.Allocator, a: *JobArgs) void {
    defer {
        a.free(alloc);
        g_job_running.store(false, .release);
    }
    const extra = ops.Extra{ .languages = a.languages[0..a.language_count], .dir = a.get(.folder) };
    switch (a.job) {
        .build => _ = ops.buildAssets(alloc, g_logger, a.get(.rom), a.get(.out), extra),
        .rom_info => _ = ops.romInfo(alloc, g_logger, a.get(.rom)),
        .verify => _ = ops.verifyAssets(alloc, g_logger, a.get(.out)),
        .export_files => _ = ops.exportFiles(alloc, g_logger, a.get(.rom), a.get(.folder)),
        .build_from_files => _ = ops.buildFromFiles(alloc, g_logger, a.get(.rom), a.get(.folder), a.get(.out), .{ .sprites_from_png = a.sprites_from_png }, extra),
        .extract_dialogue => _ = ops.extractDialogue(alloc, g_logger, a.get(.lang_rom), a.get(.folder), null),
        .check_msu => _ = ops.checkMsuPack(alloc, g_logger, a.get(.msu)),
        .input_log => _ = ops.saveInputLog(alloc, g_logger, a.get(.snapshot)),
        .text_dict => _ = ops.saveTextDict(alloc, g_logger, a.get(.dialogue)),
    }
}

// -------------------------------------------------------------- immediate UI

const kMaxItems = 48;

/// Everything that can be picked registers itself as it's drawn, in order,
/// and the arrows move between them by where they sit on screen. So a page
/// is just drawn, and the keys and pads work on it without a list of its
/// own to keep in step.
const Ui = struct {
    r: *c.SDL_Renderer,
    mouse_x: f32 = -1,
    mouse_y: f32 = -1,
    /// The mouse moved this frame, so whatever it's over takes the focus.
    moved: bool = false,
    clicked: bool = false,
    /// A or Enter this frame: whatever has the focus is pressed.
    confirm: bool = false,
    /// Left or right moved the focus this frame. A tab takes its page when
    /// the keys land on it that way, but not when the mouse passes over it.
    stepped: bool = false,
    /// Left or right this frame, for a chooser with the focus, which takes
    /// them itself rather than moving off.
    adjust: i32 = 0,
    /// Which item has the focus, by its place in the frame's drawing order.
    focus: usize = 0,
    /// While a modal is up, the page under it is drawn but takes nothing.
    blocked: bool = false,
    rects: [kMaxItems]Rect = undefined,
    enabled: [kMaxItems]bool = undefined,
    adjustable: [kMaxItems]bool = undefined,
    count: usize = 0,
    /// Last frame's items, which are what the arrows move among.
    last_rects: [kMaxItems]Rect = undefined,
    last_enabled: [kMaxItems]bool = undefined,
    last_adjustable: [kMaxItems]bool = undefined,
    last_count: usize = 0,

    const Hit = struct { focused: bool, pressed: bool };

    fn begin(self: *Ui) void {
        self.last_rects = self.rects;
        self.last_enabled = self.enabled;
        self.last_adjustable = self.adjustable;
        self.last_count = self.count;
        self.count = 0;
    }

    /// Registers something that can be picked, and says whether it has the
    /// focus and whether it was pressed this frame.
    fn item(self: *Ui, rect: Rect, enabled: bool) Hit {
        return self.itemOf(rect, enabled, false);
    }

    fn itemOf(self: *Ui, rect: Rect, enabled: bool, adjustable: bool) Hit {
        if (self.blocked or self.count == kMaxItems) return .{ .focused = false, .pressed = false };
        const id = self.count;
        self.rects[id] = rect;
        self.enabled[id] = enabled;
        self.adjustable[id] = adjustable;
        self.count += 1;
        const over = rect.contains(self.mouse_x, self.mouse_y);
        if (enabled and over and (self.moved or self.clicked)) self.focus = id;
        const focused = id == self.focus;
        return .{ .focused = focused, .pressed = enabled and ((over and self.clicked) or (focused and self.confirm)) };
    }

    /// Whether the focus is on a chooser, which keeps left and right.
    fn focusAdjusts(self: *const Ui) bool {
        return self.focus < self.last_count and self.last_adjustable[self.focus] and self.last_enabled[self.focus];
    }

    /// Moves the focus to the nearest item in a direction: straight ahead
    /// first, then whatever's least out of line.
    fn move(self: *Ui, dx: f32, dy: f32) void {
        const n = self.last_count;
        if (n == 0) return;
        if (self.focus >= n) self.focus = 0;
        const from = self.last_rects[self.focus];
        var best: ?usize = null;
        var best_score: f32 = std.math.inf(f32);
        for (0..n) |i| {
            if (i == self.focus or !self.last_enabled[i]) continue;
            const to = self.last_rects[i];
            const ddx = centerX(to) - centerX(from);
            const ddy = centerY(to) - centerY(from);
            const along = if (dx != 0) ddx * dx else ddy * dy;
            if (along <= 1) continue;
            const gap = if (dx != 0) rangeGap(from.y, from.h, to.y, to.h) else rangeGap(from.x, from.w, to.x, to.w);
            const off = @abs(if (dx != 0) ddy else ddx);
            const score = along + gap * 4 + off * 0.01;
            if (score < best_score) {
                best_score = score;
                best = i;
            }
        }
        if (best) |b| {
            self.focus = b;
            self.stepped = dx != 0;
        }
    }

    fn text(self: *const Ui, x: f32, y: f32, col: Rgb, s: []const u8) void {
        kit.drawText(self.r, x, y, col, s);
    }

    /// Wrapped paragraph text; returns the height it took.
    fn paragraph(self: *const Ui, x: f32, y: f32, w: f32, col: Rgb, s: []const u8) f32 {
        const cols: usize = @intFromFloat(w / kCell);
        var line_y = y;
        var rest = s;
        while (rest.len > 0) {
            var n = @min(rest.len, cols);
            if (n < rest.len) {
                if (std.mem.lastIndexOfScalar(u8, rest[0..n], ' ')) |sp| n = sp;
            }
            self.text(x, line_y, col, rest[0..n]);
            rest = std.mem.trimStart(u8, rest[n..], " ");
            line_y += kRowH + 2;
        }
        return line_y - y;
    }

    /// A row naming a file or folder: its label, the path in a box, and a
    /// Browse chip. Picking any of it browses. `must` says what has to be
    /// there already, which is flagged when it isn't.
    fn pathRow(self: *Ui, y: f32, label: []const u8, path: []const u8, placeholder: []const u8, must: Must) bool {
        const row = Rect{ .x = kMarginX, .y = y, .w = kContentW, .h = 32 };
        const hit = self.item(row, true);
        if (hit.focused) kit.drawRowHighlight(self.r, row.x, row.y, row.w, row.h);
        self.text(row.x + 20, y + 8, if (hit.focused) kit.kColorSelect else kit.kColorText, label);

        const box = rowBox(y);
        kit.fillRound(self.r, box.x, box.y, box.w, box.h, 6, kit.kColorBgTop);
        self.pathText(box, path, placeholder, must);

        // Browse shows on the row with the focus, which the mouse gives to
        // whatever it's over, rather than on every row at once.
        if (hit.focused) {
            const chip = Rect{ .x = box.x + box.w + 12, .y = box.y, .w = kBrowseW - 4, .h = box.h };
            kit.fillRound(self.r, chip.x, chip.y, chip.w, chip.h, 8, kColorButton);
            kit.outlineRound(self.r, chip.x, chip.y, chip.w, chip.h, 8, 2, kit.kColorSelect);
            kit.drawTextCentered(self.r, chip.x + chip.w / 2, chip.y + 5, kit.kColorSelect, "Browse", kScale);
        }
        return hit.pressed;
    }

    /// A path the way people think of one: the file's name, then which
    /// folder it's in, or that it isn't there.
    fn pathText(self: *const Ui, box: Rect, path: []const u8, placeholder: []const u8, must: Must) void {
        const x = box.x + 10;
        const y = box.y + 5;
        const cols: usize = @intFromFloat((box.w - 20) / kCell);
        if (path.len == 0) return self.text(x, y, kit.kColorTextDim, placeholder);

        const name = std.fs.path.basename(path);
        const shown = name[0..@min(name.len, cols)];
        const missing = !must.satisfiedBy(path);
        self.text(x, y, if (missing) kit.kColorWarn else kit.kColorValue, shown);

        var buf: [128]u8 = undefined;
        const folder = std.fs.path.basename(std.fs.path.dirname(path) orelse "");
        const after = if (missing)
            "  isn't there"
        else if (folder.len != 0)
            std.fmt.bufPrint(&buf, "  in {s}", .{folder}) catch ""
        else
            "";
        const room = cols - shown.len;
        if (room > 4) self.text(x + @as(f32, @floatFromInt(shown.len)) * kCell, y, kit.kColorTextDim, after[0..@min(after.len, room)]);
    }

    /// A row that picks one of several things: its label, and the choice
    /// between arrows. Left and right step through them, as does a click
    /// on either half; A steps forward. Returns the step, or 0.
    fn chooser(self: *Ui, y: f32, label: []const u8, value: []const u8, enabled: bool) i32 {
        const row = Rect{ .x = kMarginX, .y = y, .w = kContentW, .h = 32 };
        const hit = self.itemOf(row, enabled, true);
        if (hit.focused and enabled) kit.drawRowHighlight(self.r, row.x, row.y, row.w, row.h);
        const label_col = if (!enabled) kit.kColorTextDim else if (hit.focused) kit.kColorSelect else kit.kColorText;
        self.text(row.x + 20, y + 8, label_col, label);

        const box = Rect{ .x = kMarginX + kLabelW, .y = y + 3, .w = kContentW - kLabelW - 4, .h = 26 };
        kit.fillRound(self.r, box.x, box.y, box.w, box.h, 6, kit.kColorBgTop);
        const arrow_col = if (!enabled) kit.kColorLine else if (hit.focused) kit.kColorSelect else kit.kColorTextDim;
        self.text(box.x + 10, box.y + 5, arrow_col, "<");
        self.text(box.x + box.w - 10 - kCell, box.y + 5, arrow_col, ">");
        kit.drawTextCentered(self.r, box.x + box.w / 2, box.y + 5, if (enabled) kit.kColorValue else kit.kColorTextDim, value, kScale);

        if (!hit.focused or !enabled) return 0;
        if (self.adjust != 0) return self.adjust;
        if (hit.pressed) return if (self.clicked and self.mouse_x < box.x + box.w / 2) -1 else 1;
        return 0;
    }

    /// A box to tick, and what it means. True on the frame it's picked.
    fn checkRow(self: *Ui, x: f32, y: f32, w: f32, label: []const u8, on: bool, enabled: bool) bool {
        const row = Rect{ .x = x, .y = y, .w = w, .h = 26 };
        const hit = self.item(row, enabled);
        if (hit.focused and enabled) kit.drawRowHighlight(self.r, row.x, row.y, row.w, row.h);
        const box = Rect{ .x = x + 18, .y = y + 4, .w = 18, .h = 18 };
        kit.fillRound(self.r, box.x, box.y, box.w, box.h, 4, kit.kColorBgTop);
        kit.outlineRound(self.r, box.x, box.y, box.w, box.h, 4, 1, if (enabled) kit.kColorTextDim else kit.kColorLine);
        if (on and enabled) kit.fillRound(self.r, box.x + 4, box.y + 4, box.w - 8, box.h - 8, 2, kit.kColorOk);
        const col = if (!enabled) kit.kColorLine else if (hit.focused) kit.kColorSelect else kit.kColorText;
        self.text(x + 46, y + 5, col, label);
        return hit.pressed;
    }

    /// A button sized to its label, placed at x; advances x past it.
    fn button(self: *Ui, x: *f32, y: f32, label: []const u8, enabled: bool, kind: ButtonKind) bool {
        const rect = Rect{ .x = x.*, .y = y, .w = kit.textWidth(label, kScale) + 40, .h = kButtonH };
        x.* += rect.w + 28;
        const hit = self.item(rect, enabled);
        if (kind == .main) {
            kit.drawButton(self.r, rect, if (enabled) kit.kColorLaunchBg else kit.kColorDisabledBg, hit.focused);
            kit.drawTextCentered(self.r, rect.x + rect.w / 2, rect.y + 9, if (enabled) kit.kColorLaunchText else kit.kColorTextDim, label, kScale);
            return hit.pressed;
        }
        // The rest are outlines, so the main one is the thing to look at.
        kit.fillRound(self.r, rect.x, rect.y, rect.w, rect.h, 10, if (hit.focused) kit.kColorRowHi else kit.kColorPanel);
        const edge = if (hit.focused) kit.kColorSelect else if (!enabled) kit.kColorRowHi else kit.kColorLine;
        kit.outlineRound(self.r, rect.x, rect.y, rect.w, rect.h, 10, if (hit.focused) 2 else 1, edge);
        const text_col = if (!enabled) kit.kColorLine else if (hit.focused) kit.kColorSelect else if (kind == .play) kit.kColorValue else kit.kColorText;
        kit.drawTextCentered(self.r, rect.x + rect.w / 2, rect.y + 9, text_col, label, kScale);
        return hit.pressed;
    }
};

/// The page's main job is a filled green button, like Play on the start
/// menu; the rest are outlines, with starting the game picked out in blue.
const ButtonKind = enum { main, play, other };

/// The box a path row or a chooser shows its value in.
fn rowBox(y: f32) Rect {
    return .{ .x = kMarginX + kLabelW, .y = y + 3, .w = kContentW - kLabelW - kBrowseW - 12, .h = 26 };
}

fn centerX(r: Rect) f32 {
    return r.x + r.w / 2;
}

fn centerY(r: Rect) f32 {
    return r.y + r.h / 2;
}

/// How far apart two spans are along one axis; 0 when they overlap.
fn rangeGap(a: f32, a_len: f32, b: f32, b_len: f32) f32 {
    return @max(0, @max(a, b) - @min(a + a_len, b + b_len));
}

// ------------------------------------------------------------------- pages

/// What a path row needs to find at its path for things to go ahead.
const Must = enum {
    /// Nothing: it's somewhere to write.
    nothing,
    file,
    folder,
    /// A file or a folder: an MSU-1 pack is either.
    either,

    fn satisfiedBy(self: Must, path: []const u8) bool {
        if (self == .nothing) return true;
        var buf: [4096]u8 = undefined;
        const z = std.fmt.bufPrintSentinel(&buf, "{s}", .{path}, 0) catch return false;
        return switch (self) {
            .folder => fileio.isDir(z.ptr),
            .file => fileio.exists(z.ptr),
            else => fileio.isDir(z.ptr) or fileio.exists(z.ptr),
        };
    }
};

/// Under the buttons: the next thing to do, in a sentence, so a grayed-out
/// button is never a mystery.
fn nextStep(ui: *Ui, y: f32, say: []const u8) void {
    ui.text(kMarginX + 20, y, kit.kColorSection, if (jobRunning()) "Hang on, this takes a moment." else say);
}

const RomKind = enum { us, other, unreadable };

/// What the picked ROM is, read when it changes.
fn romKind(st: *State) RomKind {
    const rom = st.get(.rom);
    if (std.mem.eql(u8, rom, st.rom_seen.items)) return st.rom_kind;
    const alloc = std.heap.c_allocator;
    st.rom_seen.clearRetainingCapacity();
    st.rom_seen.appendSlice(alloc, rom) catch return .unreadable;
    st.rom_kind = .unreadable;
    const z = alloc.dupeSentinel(u8, rom, 0) catch return .unreadable;
    defer alloc.free(z);
    var r = rom_mod.Rom.load(alloc, z.ptr) catch return .unreadable;
    defer r.deinit();
    st.rom_kind = if (r.language == .us) .us else .other;
    return st.rom_kind;
}

/// What the ROM row is missing, if anything.
fn romStep(st: *State) ?[]const u8 {
    if (st.get(.rom).len == 0) return "Pick your US ROM, or drop it on the window.";
    if (!Must.file.satisfiedBy(st.get(.rom))) return "That ROM isn't there anymore. Pick it again.";
    return switch (romKind(st)) {
        .us => null,
        .other => "That isn't the US ROM, which the build needs.",
        .unreadable => "That ROM couldn't be read. Pick it again.",
    };
}

const kLangCount = @typeInfo(Language).@"enum".field_names.len;

/// What the page is for, in one quiet line under the tabs; the tab itself
/// says which page it is. Returns where the page's rows start.
fn pageHeading(ui: *Ui, about: []const u8) f32 {
    ui.text(kMarginX + 20, kContentY, kit.kColorTextDim, about);
    return kContentY + kRowH + 22;
}

fn drawAssets(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    var y = pageHeading(ui, "Make the game's graphics, music and text from your ROM.");
    if (ui.pathRow(y, "Your ROM", st.get(.rom), "Drop a .sfc here, or Browse", .file)) openDialog(window, .rom);
    y += kRowStep;
    if (ui.pathRow(y, "Save to", st.get(.out), "zelda3_assets.dat", .nothing)) openDialog(window, .out);
    y += 56;

    const idle = !jobRunning();
    const rom_ok = romStep(st) == null;
    const built = Must.file.satisfiedBy(st.get(.out));
    var x: f32 = kMarginX + 20;
    if (ui.button(&x, y, "BUILD ASSETS", idle and rom_ok and st.get(.out).len != 0, .main)) startJob(alloc, st, .build);
    // Any ROM can be checked; that's how to find out what one is.
    if (ui.button(&x, y, "CHECK ROM", idle and Must.file.satisfiedBy(st.get(.rom)) and st.get(.rom).len != 0, .other)) startJob(alloc, st, .rom_info);
    if (ui.button(&x, y, "VERIFY ASSETS", idle and built, .other)) startJob(alloc, st, .verify);
    if (ui.button(&x, y, "PLAY", st.canPlay(), .play)) play(alloc, st);

    nextStep(ui, y + kButtonH + 18, romStep(st) orelse if (st.get(.out).len == 0) "Pick where to save the assets." else if (built) "Built. Press Play to try it, or build again." else "All set. Press Build Assets.");
}

fn drawModding(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    var y = pageHeading(ui, "Export the game to files, edit them, and build it back.");
    if (ui.pathRow(y, "Your ROM", st.get(.rom), "Drop a .sfc here, or Browse", .file)) openDialog(window, .rom);
    y += kRowStep;
    if (ui.pathRow(y, "Work folder", st.get(.folder), "Where the files go to be edited", .nothing)) openDialog(window, .folder);
    y += kRowStep;
    if (ui.pathRow(y, "Save to", st.get(.out), "zelda3_assets.dat", .nothing)) openDialog(window, .out);
    y += 42;
    const half = kContentW / 2;
    if (ui.checkRow(kMarginX, y, half - 6, "Build sprite sheets too", st.sprites_from_png, true)) st.sprites_from_png = !st.sprites_from_png;
    if (ui.checkRow(kMarginX + half, y, half, "Rebuild when files change", st.watch, true)) setWatch(st, !st.watch);
    y += 40;

    const idle = !jobRunning();
    const rom_ok = romStep(st) == null;
    const exported = Must.folder.satisfiedBy(st.get(.folder));
    var x: f32 = kMarginX + 20;
    if (ui.button(&x, y, "BUILD FROM FILES", idle and rom_ok and exported and st.get(.out).len != 0, .main)) startJob(alloc, st, .build_from_files);
    if (ui.button(&x, y, "EXPORT FILES", idle and rom_ok and st.get(.folder).len != 0, .other)) startJob(alloc, st, .export_files);
    if (ui.button(&x, y, "PLAY", st.canPlay(), .play)) play(alloc, st);

    nextStep(ui, y + kButtonH + 18, romStep(st) orelse if (st.get(.folder).len == 0)
        "Pick a work folder for the files."
    else if (!exported)
        "Press Export Files to fill the work folder."
    else if (st.watch)
        "Watching: save a file and it rebuilds by itself."
    else
        "Edit the files, Build From Files, then Play.");
}

/// Turns rebuilding on save on or off, taking the folder as it is now as the
/// starting point.
fn setWatch(st: *State, on: bool) void {
    st.watch = on;
    if (!on) return;
    st.watch_built = folderStamp(st);
    st.watch_seen = st.watch_built;
    g_logger.info("Watching the work folder. Save a change and it rebuilds.", .{});
}

fn folderStamp(st: *const State) u64 {
    var buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintSentinel(&buf, "{s}", .{st.get(.folder)}, 0) catch return 0;
    return game.stamp(z);
}

/// Once a second: if the work folder has changed since the last build and
/// has stayed the same for that second, so a save is finished, build.
fn watchFolder(alloc: std.mem.Allocator, st: *State, now: u64) void {
    if (!st.watch or now < st.watch_at + 1000) return;
    st.watch_at = now;
    if (jobRunning()) return;
    const s = folderStamp(st);
    defer st.watch_seen = s;
    if (s == st.watch_built or s != st.watch_seen) return;
    st.watch_built = s;
    if (romStep(st) != null or st.get(.out).len == 0) return;
    g_logger.info("A file in the work folder changed. Rebuilding.", .{});
    startJob(alloc, st, .build_from_files);
}

// ----------------------------------------------------------------- graphics

/// The Graphics page's pictures: the exported ones in the work folder, and
/// a Link sprite first when one's been picked, with the one showing loaded
/// into a texture.
const Gallery = struct {
    list: [][:0]u8 = &.{},
    index: usize = 0,
    age: u32 = 0,
    tex: ?*c.SDL_Texture = null,
    w: f32 = 0,
    h: f32 = 0,
    /// The path the texture is of, to know when it needs loading again.
    shown: std.ArrayList(u8) = .empty,
    about_buf: [128]u8 = undefined,
    about: []const u8 = "",
    bad: bool = false,

    fn count(self: *const Gallery, st: *const State) usize {
        return self.list.len + @intFromBool(st.get(.zspr).len != 0);
    }

    /// The path of picture `i`.
    fn path(self: *const Gallery, st: *const State, i: usize) []const u8 {
        if (st.get(.zspr).len != 0) {
            if (i == 0) return st.get(.zspr);
            return self.list[i - 1];
        }
        return self.list[i];
    }

    fn refresh(self: *Gallery, alloc: std.mem.Allocator, st: *const State) void {
        const fresh = pictures.listPictures(alloc, st.get(.folder)) catch return;
        pictures.freeList(alloc, self.list);
        self.list = fresh;
        self.age = 0;
        const n = self.count(st);
        if (self.index >= n) self.index = n -| 1;
    }

    /// Makes sure the texture is of picture `self.index`.
    fn load(self: *Gallery, alloc: std.mem.Allocator, st: *const State, r: *c.SDL_Renderer) void {
        const want: []const u8 = if (self.count(st) == 0) "" else self.path(st, self.index);
        if (std.mem.eql(u8, want, self.shown.items)) return;
        self.shown.clearRetainingCapacity();
        self.shown.appendSlice(alloc, want) catch return;
        if (self.tex) |t| c.SDL_DestroyTexture(t);
        self.tex = null;
        self.about = "";
        self.bad = false;
        if (want.len == 0) return;

        const z = alloc.dupeSentinel(u8, want, 0) catch return;
        defer alloc.free(z);
        const is_zspr = std.ascii.endsWithIgnoreCase(want, ".zspr");
        var pic = (if (is_zspr) pictures.loadZspr(alloc, z) else pictures.loadPng(alloc, z)) catch |e| {
            self.bad = true;
            self.about = std.fmt.bufPrint(&self.about_buf, "{s} {s}", .{ std.fs.path.basename(want), if (is_zspr) pictures.zsprProblem(e) else "couldn't be read as a picture." }) catch "";
            return;
        };
        defer pic.deinit(alloc);
        self.about = std.fmt.bufPrint(&self.about_buf, "{s}", .{pic.about()}) catch "";
        const tex = c.SDL_CreateTexture(r, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_STATIC, @intCast(pic.width), @intCast(pic.height)) orelse return;
        _ = c.SDL_UpdateTexture(tex, null, pic.rgba.ptr, @intCast(pic.width * 4));
        _ = c.SDL_SetTextureScaleMode(tex, c.SDL_SCALEMODE_NEAREST);
        _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
        self.tex = tex;
        self.w = @floatFromInt(pic.width);
        self.h = @floatFromInt(pic.height);
    }
};

/// The Graphics page uses the log's room for the picture.
const kPictureBottom: f32 = kLogY + kLogH;

fn drawGraphics(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    const g = &st.gfx;
    if (g.age == 0 or g.age > 120) g.refresh(alloc, st);
    g.age += 1;

    var y = pageHeading(ui, "Look at exported pictures, or check a Link sprite.");
    if (ui.pathRow(y, "Link sprite", st.get(.zspr), "A .zspr, or drop one here", .file)) openDialog(window, .zspr);
    y += kRowStep;

    const n = g.count(st);
    var buf: [96]u8 = undefined;
    const value = if (n == 0) "nothing to show yet" else std.fmt.bufPrint(&buf, "{s}  ({d} of {d})", .{ std.fs.path.basename(g.path(st, g.index)), g.index + 1, n }) catch "";
    const step = ui.chooser(y, "Picture", value, n > 1);
    if (step != 0 and n > 0) g.index = @intCast(@mod(@as(i64, @intCast(g.index)) + step, @as(i64, @intCast(n))));
    y += kRowStep + 4;

    g.load(alloc, st, ui.r);
    const box = Rect{ .x = kMarginX, .y = y + 26, .w = kContentW, .h = kPictureBottom - y - 26 };
    kit.fillRound(ui.r, box.x, box.y, box.w, box.h, 10, kColorLogBg);
    if (n == 0) {
        const say = if (Must.folder.satisfiedBy(st.get(.folder))) "No pictures in the work folder. Export the files on Modding." else "Export the files on Modding, or pick a Link sprite.";
        ui.text(kMarginX + 20, y, kit.kColorSection, say);
        return;
    }
    ui.text(kMarginX + 20, y, if (g.bad) kit.kColorWarn else kit.kColorSection, g.about);
    if (g.tex) |tex| drawPicture(ui.r, tex, g.w, g.h, .{ .x = box.x + 12, .y = box.y + 12, .w = box.w - 24, .h = box.h - 24 });
}

/// Draws a picture as big as fits, in whole steps of size from 2x up, which
/// keeps pixel art sharp. A tall narrow one, like Link's sheet, is cut into
/// columns side by side, which lets it be bigger.
fn drawPicture(r: *c.SDL_Renderer, tex: *c.SDL_Texture, w: f32, h: f32, box: Rect) void {
    const gap: f32 = 12;
    var best_k: f32 = 1;
    var best_s: f32 = 0;
    var best_chunk: f32 = h;
    var k: f32 = 1;
    // Only a sheet at least twice as tall as it's wide gets cut.
    const most: f32 = if (h >= w * 2) 8 else 1;
    while (k <= most) : (k += 1) {
        // Columns are cut every 16 rows, the height of a sprite, so none is
        // split between two of them.
        const chunk = @ceil(h / k / 16) * 16;
        if (k > 1 and chunk * (k - 1) >= h) break;
        const fit = @min(box.w / (k * w + (k - 1) * gap), box.h / chunk);
        const s = if (fit >= 2) @floor(fit) else fit;
        if (s > best_s + 0.001) {
            best_s = s;
            best_k = k;
            best_chunk = chunk;
        }
    }
    const total_w = (best_k * w + (best_k - 1) * gap) * best_s;
    const x0 = box.x + (box.w - total_w) / 2;
    const y0 = box.y + (box.h - @min(best_chunk, h) * best_s) / 2;
    var i: f32 = 0;
    while (i < best_k) : (i += 1) {
        const top = i * best_chunk;
        const rows = @min(best_chunk, h - top);
        if (rows <= 0) break;
        const src = c.SDL_FRect{ .x = 0, .y = top, .w = w, .h = rows };
        const dst = c.SDL_FRect{ .x = @round(x0 + i * (w + gap) * best_s), .y = @round(y0), .w = w * best_s, .h = rows * best_s };
        _ = c.SDL_RenderTexture(r, tex, &src, &dst);
    }
}

// -------------------------------------------------------------------- music

/// The Music page's player, made from the asset file the first time the
/// page wants it, and again if that file changes.
const Tunes = struct {
    player: ?*music.Player = null,
    /// The asset file it was made from, and that file's stamp then.
    from: std.ArrayList(u8) = .empty,
    from_size: u64 = 0,
    index: usize = 0,
    /// Why there isn't a player, when there should be.
    problem: []const u8 = "",
    age: u32 = 0,

    fn ensure(self: *Tunes, alloc: std.mem.Allocator, out: []const u8) void {
        if (self.age != 0 and self.age < 60) {
            self.age += 1;
            return;
        }
        self.age = 1;
        var buf: [4096]u8 = undefined;
        const z = std.fmt.bufPrintSentinel(&buf, "{s}", .{out}, 0) catch return;
        var info: c.SDL_PathInfo = undefined;
        const size: u64 = if (c.SDL_GetPathInfo(z.ptr, &info)) info.size ^ @as(u64, @bitCast(info.modify_time)) else 0;
        if (std.mem.eql(u8, out, self.from.items) and size == self.from_size) return;
        self.drop(alloc);
        self.from.appendSlice(alloc, out) catch return;
        self.from_size = size;
        if (size == 0) {
            self.problem = "Build the assets first: the music comes out of them.";
            return;
        }
        self.player = music.Player.init(alloc, z) catch {
            self.problem = "The asset file has no music in it that these tools can read.";
            return;
        };
        self.problem = "";
        if (self.index >= self.player.?.songs.len) self.index = 0;
    }

    fn drop(self: *Tunes, alloc: std.mem.Allocator) void {
        if (self.player) |p| p.deinit();
        self.player = null;
        self.from.clearRetainingCapacity();
        _ = alloc;
    }
};

fn drawMusic(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    const t = &st.tunes;
    t.ensure(alloc, st.get(.out));

    var y = pageHeading(ui, "Play the game's songs, or check an MSU-1 pack.");
    const songs: []const music.Song = if (t.player) |p| p.songs else &.{};
    var buf: [64]u8 = undefined;
    const value = if (songs.len == 0) "no songs yet" else std.fmt.bufPrint(&buf, "Song {d}, {s}  ({d} of {d})", .{ songs[t.index].number, @tagName(songs[t.index].bank), t.index + 1, songs.len }) catch "";
    const step = ui.chooser(y, "Song", value, songs.len > 1);
    if (step != 0 and songs.len > 0) {
        t.index = @intCast(@mod(@as(i64, @intCast(t.index)) + step, @as(i64, @intCast(songs.len))));
        // Changing songs while one plays changes what's playing.
        if (t.player.?.playing != null) _ = t.player.?.play(songs[t.index]);
    }
    y += kRowStep + 2;

    const playing = if (t.player) |p| p.playing else null;
    var x: f32 = kMarginX + 20;
    if (ui.button(&x, y, "PLAY SONG", songs.len != 0, .main)) {
        if (!t.player.?.play(songs[t.index])) g_logger.err("Couldn't play anything: there's no sound device to play it on.", .{});
    }
    if (ui.button(&x, y, "STOP", playing != null, .other)) t.player.?.stop();
    y += kButtonH + 22;

    if (ui.pathRow(y, "MSU-1 pack", st.get(.msu), "A pack's folder or .zip", .either)) openDialog(window, .msu);
    y += 44;
    x = kMarginX + 20;
    const pack_ok = st.get(.msu).len != 0 and Must.either.satisfiedBy(st.get(.msu));
    if (ui.button(&x, y, "CHECK PACK", !jobRunning() and pack_ok, .other)) startJob(alloc, st, .check_msu);

    var say_buf: [96]u8 = undefined;
    const say = if (t.problem.len != 0)
        t.problem
    else if (playing) |p|
        std.fmt.bufPrint(&say_buf, "Playing song {d}. Left and right change it.", .{p.number}) catch ""
    else if (!pack_ok)
        "Pick a song and Play, or pick a pack to check."
    else
        "Press Check Pack to look it over.";
    nextStep(ui, y + kButtonH + 18, say);
}

// --------------------------------------------------------------- languages

/// Short names, so four fit across.
fn shortName(lang: Language) []const u8 {
    return switch (lang) {
        .us => "English US",
        .de => "German",
        .fr => "French",
        .fr_c => "French CA",
        .en => "English EU",
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

    var y = pageHeading(ui, "Add the text from translated ROMs to the game.");
    if (ui.pathRow(y, "Translated ROM", st.get(.lang_rom), "A German, French, Spanish... ROM", .file)) openDialog(window, .lang_rom);
    y += kRowStep;
    if (ui.pathRow(y, "Work folder", st.get(.folder), "Where the extracted text goes", .nothing)) openDialog(window, .folder);
    y += 40;

    // Only the languages the folder has text for, which are the ones there
    // are to tick; until there's one, the line below says how to get it.
    const cols = 4;
    const col_w: f32 = kContentW / cols;
    var n: usize = 0;
    for (std.enums.values(Language)) |lang| {
        const i = @backingInt(lang);
        if (lang == .us or !st.available[i]) continue;
        const x = kMarginX + @as(f32, @floatFromInt(n % cols)) * col_w;
        const row_y = y + @as(f32, @floatFromInt(n / cols)) * 26;
        if (ui.checkRow(x, row_y, col_w - 6, shortName(lang), st.picked[i], st.available[i])) st.picked[i] = !st.picked[i];
        n += 1;
    }
    if (n != 0) y += @as(f32, @floatFromInt((n + cols - 1) / cols)) * 26 + 12;

    const idle = !jobRunning();
    const lang_rom_ok = Must.file.satisfiedBy(st.get(.lang_rom)) and st.get(.lang_rom).len != 0;
    var x: f32 = kMarginX + 20;
    if (ui.button(&x, y, "BUILD ASSETS", idle and romStep(st) == null and st.get(.out).len != 0, .main)) startJob(alloc, st, .build);
    if (ui.button(&x, y, "EXTRACT DIALOGUE", idle and lang_rom_ok and st.get(.folder).len != 0, .other)) startJob(alloc, st, .extract_dialogue);

    var any_available = false;
    var any_picked = false;
    for (st.available, st.picked) |a, p| {
        any_available = any_available or a;
        any_picked = any_picked or (a and p);
    }
    nextStep(ui, y + kButtonH + 14, if (!any_available and st.get(.lang_rom).len == 0)
        "Pick a translated ROM to take its text from."
    else if (!any_available)
        "Press Extract Dialogue, then tick its language."
    else if (!any_picked)
        "Tick the languages to build into the game."
    else if (romStep(st) != null)
        "Building needs your US ROM too: pick it on Assets."
    else
        "Press Build Assets to put them in the game.");
}

// ------------------------------------------------------------------- extras

fn drawExtras(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    var y = pageHeading(ui, "Helpers for working on the game itself.");
    if (ui.pathRow(y, "Snapshot", st.get(.snapshot), "A .sav from the saves folder", .file)) openDialog(window, .snapshot);
    y += 40;
    const idle = !jobRunning();
    const snapshot_ok = st.get(.snapshot).len != 0 and Must.file.satisfiedBy(st.get(.snapshot));
    var x: f32 = kMarginX + 20;
    if (ui.button(&x, y, "SAVE INPUT LOG", idle and snapshot_ok, .other)) startJob(alloc, st, .input_log);
    y += kButtonH + 22;

    if (ui.pathRow(y, "Dialogue", st.get(.dialogue), "A dialogue.txt, as Export writes", .file)) openDialog(window, .dialogue);
    y += 40;
    const dialogue_ok = st.get(.dialogue).len != 0 and Must.file.satisfiedBy(st.get(.dialogue));
    x = kMarginX + 20;
    if (ui.button(&x, y, "FIND DICTIONARY", idle and dialogue_ok, .other)) startJob(alloc, st, .text_dict);

    nextStep(ui, y + kButtonH + 18, if (!snapshot_ok and !dialogue_ok)
        "Both write a text file beside the one you pick."
    else if (dialogue_ok)
        "The dictionary search takes a few minutes."
    else
        "Saves the input log as text beside the snapshot.");
}

// ------------------------------------------------------------- the frame

/// The update offer takes the line under the title while there is one, as
/// on the start menu.
fn updateShown() bool {
    return switch (updater.phase()) {
        .available, .downloading, .installing, .ready, .failed => true,
        else => false,
    };
}

fn updateButtonLabel(buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "UPDATE TO {s}", .{updater.offerLabel()}) catch "UPDATE";
}

/// The game's title, then what this is, or the offer of something newer.
fn drawHeader(ui: *Ui, st: *State) void {
    const cx: f32 = kWindowW / 2;
    kit.drawTextCentered(ui.r, cx, 36, kit.kColorSelect, "THE LEGEND OF ZELDA", kScale);
    kit.drawTextCentered(ui.r, cx, 36 + kRowH, kit.kColorSelect, "A LINK TO THE PAST DX", kScale);
    if (updateShown()) {
        var buf: [64]u8 = undefined;
        const label = updateButtonLabel(&buf);
        const w = kit.textWidth(label, kScale) + 40;
        const u = Rect{ .x = cx - w / 2, .y = 36 + kRowH * 2 - 2, .w = w, .h = kRowH + 2 };
        const hit = ui.item(u, true);
        kit.fillRound(ui.r, u.x, u.y, u.w, u.h, 8, if (hit.focused) kit.kColorRowHi else kit.kColorPanel);
        kit.outlineRound(ui.r, u.x, u.y, u.w, u.h, 8, if (hit.focused) 2 else 1, if (hit.focused) kit.kColorSelect else kit.kColorOk);
        kit.drawTextCentered(ui.r, cx, u.y + 3, if (hit.focused) kit.kColorSelect else kit.kColorOk, label, kScale);
        if (hit.pressed) st.openModal(ui, .update, 0);
    } else {
        kit.drawTextCentered(ui.r, cx, 36 + kRowH * 2, kit.kColorTextDim, "TOOLS", kScale);
    }
    kit.fillRect(ui.r, 60, 36 + kRowH * 3 + 7, kWindowW - 120, 1, kit.kColorLine);
}

/// The sections, side by side under the title. They're the first things
/// registered, so tab N is always item N.
fn drawTabs(ui: *Ui, st: *State) void {
    const gap: f32 = 10;
    const pad: f32 = 32;
    var total: f32 = -gap;
    inline for (@typeInfo(Page).@"enum".field_values) |value| {
        const page: Page = @fromBackingInt(@intCast(value));
        total += kit.textWidth(page.title(), kScale) + pad + gap;
    }
    var x: f32 = (kWindowW - total) / 2;
    inline for (@typeInfo(Page).@"enum".field_values) |value| {
        const page: Page = @fromBackingInt(@intCast(value));
        const rect = Rect{ .x = x, .y = kTabsY, .w = kit.textWidth(page.title(), kScale) + pad, .h = kRowH + 10 };
        x += rect.w + gap;
        const hit = ui.item(rect, true);
        const current = st.page == page;
        if (current) kit.fillRound(ui.r, rect.x, rect.y, rect.w, rect.h, 8, kit.kColorRowHi);
        if (hit.focused) kit.outlineRound(ui.r, rect.x, rect.y, rect.w, rect.h, 8, 2, kit.kColorSelect);
        const col = if (hit.focused) kit.kColorSelect else if (current) kit.kColorText else kit.kColorTextDim;
        kit.drawTextCentered(ui.r, rect.x + rect.w / 2, rect.y + 7, col, page.title(), kScale);
        if (hit.pressed or (hit.focused and ui.stepped)) st.page = page;
    }
}

fn drawLog(ui: *Ui) void {
    kit.fillRound(ui.r, kMarginX, kLogY, kContentW, kLogH, 10, kColorLogBg);
    // While a job runs, a gold bar slides along the top of the log.
    if (jobRunning()) {
        const track = kContentW - 40;
        const seg: f32 = 140;
        const t: f32 = @floatFromInt(c.SDL_GetTicks() % 1400);
        const at = (t / 1400) * (track + seg) - seg;
        const from = @max(0, at);
        const to = @min(track, at + seg);
        if (to > from) kit.fillRound(ui.r, kMarginX + 20 + from, kLogY + 4, to - from, 3, 1.5, kit.kColorSelect);
    }
    c.SDL_LockMutex(g_log_lock);
    defer c.SDL_UnlockMutex(g_log_lock);
    const end = g_log_count - @min(g_log_scroll, g_log_count);
    const start = end -| kLogRows;
    var y: f32 = kLogY + 12;
    for (g_log[start..end]) |line| {
        const col = switch (line.level) {
            .info => kit.kColorTextDim,
            .ok => kit.kColorOk,
            .err => kit.kColorWarn,
        };
        ui.text(kMarginX + 16, y, col, line.text[0..line.len]);
        y += kLogLineH;
    }
}

fn drawFooter(ui: *Ui, st: *State) void {
    if (st.modal != .none) {
        const hint = switch (st.modal) {
            .update => switch (updater.phase()) {
                .downloading => "B/Esc: cancel",
                .installing, .ready => "",
                else => "Left/Right: choose   A/Enter: confirm   B/Esc: cancel",
            },
            else => "Left/Right: choose   A/Enter: confirm   B/Esc: cancel",
        };
        ui.text(kMarginX, kFooterY, kit.kColorTextDim, hint);
        return;
    }
    if (jobRunning()) {
        var buf: [64]u8 = undefined;
        ui.text(kMarginX, kFooterY, kit.kColorSelect, std.fmt.bufPrint(&buf, "{s}...", .{g_job.doing()}) catch "WORKING...");
    } else {
        ui.text(kMarginX, kFooterY, kit.kColorTextDim, "A/Enter: pick  Tab/L/R: page  B/Esc: quit");
    }
    // Which version this is, out of the way in the corner.
    var buf: [40]u8 = undefined;
    const ver = if (updater.installed == .dev) "DEV BUILD" else updater.installedLabel(&buf);
    ui.text(kWindowW - kMarginX - kit.textWidth(ver, kScale), kFooterY, kit.kColorTextDim, ver);
}

/// Lines of a modal, spaced so they read as separate sentences.
const kModalLineH: f32 = kRowH + 8;

fn modalRect() Rect {
    const w: f32 = 700;
    const h: f32 = 200;
    return .{ .x = (kWindowW - w) / 2, .y = (kWindowH - h) / 2 - 20, .w = w, .h = h };
}

/// The modal's two answers, side by side. Says which was pressed, if one was.
fn drawChoices(ui: *Ui, st: *State, labels: []const []const u8) ?usize {
    const box = modalRect();
    const w: f32 = 180;
    const gap: f32 = 30;
    var pressed: ?usize = null;
    for (labels, 0..) |label, i| {
        const x = box.x + (box.w - (w * 2 + gap)) / 2 + (w + gap) * @as(f32, @floatFromInt(i));
        const r = Rect{ .x = x, .y = box.y + box.h - 62, .w = w, .h = kRowH + 16 };
        const hit = ui.item(r, true);
        if (hit.focused) st.choice = i;
        const selected = i == st.choice;
        kit.fillRound(ui.r, r.x, r.y, r.w, r.h, 8, if (selected) kit.kColorRowHi else kit.kColorPanel);
        kit.outlineRound(ui.r, r.x, r.y, r.w, r.h, 8, if (selected) 2 else 1, if (selected) kit.kColorSelect else kit.kColorLine);
        kit.drawTextCentered(ui.r, r.x + r.w / 2, r.y + 8, if (selected) kit.kColorSelect else kit.kColorText, label, kScale);
        if (hit.pressed) pressed = i;
    }
    return pressed;
}

fn drawModal(ui: *Ui, st: *State) void {
    const box = modalRect();
    const cx = box.x + box.w / 2;
    // A frame paints its own interior, which is what blanks the page behind.
    kit.drawFrame(ui.r, box.x, box.y, box.w, box.h);
    var buf: [64]u8 = undefined;
    switch (st.modal) {
        .quit => {
            kit.drawTextCentered(ui.r, cx, box.y + 34, kit.kColorSelect, "QUIT THE TOOLS?", kScale);
            if (jobRunning()) kit.drawTextCentered(ui.r, cx, box.y + 34 + kModalLineH, kit.kColorWarn, "A job is still running. Quitting stops it.", kScale);
            if (drawChoices(ui, st, &kQuitChoices)) |i| {
                if (i == 0) st.quit = true else st.closeModal(ui);
            }
        },
        .update => switch (updater.phase()) {
            .downloading, .installing, .ready => |p| {
                const title = switch (p) {
                    .downloading => std.fmt.bufPrint(&buf, "DOWNLOADING {s}", .{updater.offerLabel()}) catch "DOWNLOADING",
                    .installing => "INSTALLING...",
                    else => if (jobRunning()) "RESTARTING WHEN THE JOB'S DONE..." else "RESTARTING...",
                };
                kit.drawTextCentered(ui.r, cx, box.y + 34, kit.kColorSelect, title, kScale);

                const pr = updater.progress();
                const frac: f32 = if (p != .downloading) 1 else if (pr.total == 0) 0 else @min(1, @as(f32, @floatFromInt(pr.done)) / @as(f32, @floatFromInt(pr.total)));
                const bar = Rect{ .x = box.x + 60, .y = box.y + 84, .w = box.w - 120, .h = 14 };
                kit.fillRound(ui.r, bar.x, bar.y, bar.w, bar.h, 6, kit.kColorRowHi);
                if (frac > 0) kit.fillRound(ui.r, bar.x, bar.y, @max(bar.w * frac, 12), bar.h, 6, kit.kColorOk);

                const mb = 1024.0 * 1024.0;
                const size = std.fmt.bufPrint(&buf, "{d:.1} OF {d:.1} MB", .{ @as(f32, @floatFromInt(pr.done)) / mb, @as(f32, @floatFromInt(pr.total)) / mb }) catch "";
                if (p == .downloading) kit.drawTextCentered(ui.r, cx, bar.y + 30, kit.kColorTextDim, size, kScale);
            },
            .failed => {
                kit.drawTextCentered(ui.r, cx, box.y + 26, kit.kColorWarn, "COULD NOT UPDATE", kScale);
                kit.drawTextCentered(ui.r, cx, box.y + 26 + kModalLineH, kit.kColorText, updater.message(), kScale);
                kit.drawTextCentered(ui.r, cx, box.y + 26 + kModalLineH * 2, kit.kColorTextDim, "Or get it by hand from the release page.", kScale);
                if (drawChoices(ui, st, &kUpdateFailedChoices)) |i| {
                    if (i == 0) _ = c.SDL_OpenURL(updater.pageUrl().ptr);
                    updater.dismiss();
                    st.closeModal(ui);
                }
            },
            else => {
                kit.drawTextCentered(ui.r, cx, box.y + 26, kit.kColorSelect, std.fmt.bufPrint(&buf, "UPDATE THE TOOLS TO {s}?", .{updater.offerLabel()}) catch "UPDATE?", kScale);
                var mine: [40]u8 = undefined;
                kit.drawTextCentered(ui.r, cx, box.y + 26 + kModalLineH, kit.kColorText, std.fmt.bufPrint(&buf, "You have {s} now.", .{updater.installedLabel(&mine)}) catch "", kScale);
                kit.drawTextCentered(ui.r, cx, box.y + 26 + kModalLineH * 2, kit.kColorTextDim, "Downloads from GitHub, then restarts.", kScale);
                if (drawChoices(ui, st, &kUpdateChoices)) |i| {
                    if (i == 0) updater.install() else st.closeModal(ui);
                }
            },
        },
        .none => {},
    }
}

fn initialState(alloc: std.mem.Allocator) State {
    var st = State{};
    st.game = game.find(&st.game_buf);
    // Sensible starting points: a ROM in the game's folder or the current
    // one, and the asset file where the game will look for it.
    for ([_][]const u8{ inGameDir(alloc, "zelda3.sfc"), "zelda3.sfc", inGameDir(alloc, "zelda3.smc"), "zelda3.smc" }) |p| {
        if (st.get(.rom).len == 0 and exists(alloc, p)) st.set(alloc, .rom, p);
    }
    st.set(alloc, .out, gameAssetPath(alloc, &st));
    const folder = inGameDir(alloc, "zelda3_files");
    st.set(alloc, .folder, folder);
    st.set(alloc, .dialogue, std.fmt.allocPrint(alloc, "{s}{s}dialogue.txt", .{ folder, std.fs.path.sep_str }) catch "");
    return st;
}

/// The first thing in the log: what's ready and what isn't, a line each, so
/// the next step is plain before anything's been pressed.
fn reportReadiness(alloc: std.mem.Allocator, st: *State) void {
    if (st.get(.rom).len == 0) {
        g_logger.info("No ROM picked yet.", .{});
    } else if (!Must.file.satisfiedBy(st.get(.rom))) {
        g_logger.info("Your ROM isn't where it was. Pick it again.", .{});
    } else switch (romKind(st)) {
        .us => g_logger.ok("Your ROM is the US release: ready to build.", .{}),
        .other => g_logger.info("Your ROM isn't the US release the build needs.", .{}),
        .unreadable => g_logger.info("Your ROM couldn't be read. Pick it again.", .{}),
    }

    switch (assetState(alloc, st.get(.out))) {
        .missing => g_logger.info("The assets aren't built yet.", .{}),
        .standard => g_logger.ok("The assets are built and match this version.", .{}),
        .custom => g_logger.ok("The assets are custom: a mod, or extra languages.", .{}),
        .old => g_logger.info("The assets are from another version. Build again.", .{}),
    }

    if (st.game != null) {
        g_logger.ok("The game is beside the tools: Play starts it.", .{});
    } else if (!st.canPlay()) {
        g_logger.info("The game isn't beside the tools, so Play is off.", .{});
    }
}

/// Whether the asset file at `path` is there, whether it's the one this
/// version builds from the US ROM, and if not, whether the game loads it.
fn assetState(alloc: std.mem.Allocator, path: []const u8) enum { missing, standard, custom, old } {
    const z = alloc.dupeSentinel(u8, path, 0) catch return .missing;
    defer alloc.free(z);
    const data = fileio.readWholeFile(alloc, z.ptr) catch return .missing;
    defer alloc.free(data);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    if (std.mem.eql(u8, &hex, @import("asset_all.zig").kReferenceDigest)) return .standard;
    return if (@import("asset_pack.zig").loadsInGame(data)) .custom else .old;
}

/// Takes a dropped file or folder for whichever row it belongs in, by what
/// it is, and goes to that page.
fn dropped(alloc: std.mem.Allocator, st: *State, path: []const u8) void {
    var buf: [4096]u8 = undefined;
    const z = std.fmt.bufPrintSentinel(&buf, "{s}", .{path}, 0) catch return;
    const is_dir = fileio.isDir(z.ptr);
    const ext = std.fs.path.extension(path);
    const is = struct {
        fn f(e: []const u8, want: []const u8) bool {
            return std.ascii.eqlIgnoreCase(e, want);
        }
    }.f;
    if (is(ext, ".dat")) {
        st.set(alloc, .out, path);
    } else if (is(ext, ".zspr")) {
        st.set(alloc, .zspr, path);
        st.gfx.index = 0;
        st.page = .graphics;
    } else if (is(ext, ".zip") or (is_dir and st.page == .music)) {
        st.set(alloc, .msu, path);
        st.page = .music;
    } else if (is(ext, ".sav")) {
        st.set(alloc, .snapshot, path);
        st.page = .extras;
    } else if (is(ext, ".txt")) {
        st.set(alloc, .dialogue, path);
        st.page = .extras;
    } else if (is_dir) {
        st.set(alloc, .folder, path);
    } else {
        st.set(alloc, if (st.page == .languages) .lang_rom else .rom, path);
    }
}

/// A dialog's answer, into its row. A track picked for an MSU-1 pack means
/// the folder it's in.
fn picked(alloc: std.mem.Allocator, st: *State, field: Field, path: []const u8) void {
    if (field == .msu and !std.ascii.endsWithIgnoreCase(path, ".zip")) {
        st.set(alloc, .msu, std.fs.path.dirname(path) orelse path);
        return;
    }
    st.set(alloc, field, path);
}

fn drawFrame(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    ui.begin();
    // Under a modal the page is still drawn, but only the modal takes input.
    ui.blocked = st.modal != .none;
    kit.fillBackground(ui.r, kWindowW, kWindowH);
    kit.drawFrame(ui.r, 16, 16, kWindowW - 32, kWindowH - 32);
    drawTabs(ui, st);
    switch (st.page) {
        .assets => drawAssets(ui, alloc, st, window),
        .modding => drawModding(ui, alloc, st, window),
        .graphics => drawGraphics(ui, alloc, st, window),
        .music => drawMusic(ui, alloc, st, window),
        .languages => drawLanguages(ui, alloc, st, window),
        .extras => drawExtras(ui, alloc, st, window),
    }
    // After the page, so an update turning up doesn't shift what the focus
    // is on.
    drawHeader(ui, st);
    if (st.page != .graphics) drawLog(ui);
    drawFooter(ui, st);
    if (st.modal != .none) {
        ui.blocked = false;
        drawModal(ui, st);
    }
}

/// Draws one frame of a page into a BMP with no window, for looking at the
/// layout while working on it: `zelda3-tools gui-screenshot out.bmp [page]`.
/// `log` lines are fed through the real log first, so it shows populated;
/// ones like "@rom=path" set a field instead (any of the Field names),
/// "@pick=de,fr" ticks languages, "@sprites" ticks the sprite sheets,
/// "@watch" turns on rebuilding, "@picture=N" and "@song=N" pick from those
/// lists, "@focus=N" puts the focus on the Nth thing that can have it,
/// "@busy=build" shows a job running, "@update=available" (or downloading,
/// failed...) an update on offer, "@modal=quit" or "@modal=update" a
/// question up, and "@us=path" takes path to be a US ROM.
pub fn screenshot(alloc: std.mem.Allocator, path: [:0]const u8, page_name: ?[]const u8, log_lines: []const [:0]const u8) !void {
    const surface = c.SDL_CreateSurface(kWindowW, kWindowH, c.SDL_PIXELFORMAT_XRGB8888) orelse return error.SdlSurface;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    var st = initialState(alloc);
    var ui = Ui{ .r = renderer };
    if (page_name) |name| {
        const info = @typeInfo(Page).@"enum";
        inline for (info.field_names, info.field_values) |field_name, value| {
            if (std.ascii.eqlIgnoreCase(field_name, name)) st.page = @fromBackingInt(@intCast(value));
        }
    }
    var picks: ?[]const u8 = null;
    // Settings first, so the opening report is about them, then the log.
    for (log_lines) |line| {
        if (std.mem.startsWith(u8, line, "@")) {
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse line.len;
            const key = line[1..eq];
            const value = if (eq < line.len) line[eq + 1 ..] else "";
            const number = std.fmt.parseInt(usize, value, 10) catch 0;
            if (std.mem.eql(u8, key, "pick")) {
                picks = value;
            } else if (std.mem.eql(u8, key, "sprites")) {
                st.sprites_from_png = true;
            } else if (std.mem.eql(u8, key, "watch")) {
                st.watch = true;
            } else if (std.mem.eql(u8, key, "picture")) {
                st.gfx.index = number;
            } else if (std.mem.eql(u8, key, "song")) {
                st.tunes.index = number;
            } else if (std.mem.eql(u8, key, "focus")) {
                ui.focus = number;
            } else if (std.mem.eql(u8, key, "busy")) {
                g_job = std.meta.stringToEnum(Job, value) orelse .build;
                g_job_running.store(true, .release);
            } else if (std.mem.eql(u8, key, "update")) {
                updater.pretend(std.meta.stringToEnum(updater.Phase, value) orelse .available, "V1.9");
            } else if (std.mem.eql(u8, key, "modal")) {
                st.modal = std.meta.stringToEnum(Modal, value) orelse .none;
            } else if (std.mem.eql(u8, key, "us")) {
                // A US ROM to build from, for a machine without one.
                st.set(alloc, .rom, value);
                st.rom_seen.appendSlice(std.heap.c_allocator, value) catch {};
                st.rom_kind = .us;
            } else if (std.meta.stringToEnum(Field, key)) |f| st.set(alloc, f, value);
        }
    }
    reportReadiness(alloc, &st);
    for (log_lines) |line| {
        if (std.mem.startsWith(u8, line, "@")) continue;
        const level: ops.Log.Level = if (std.mem.startsWith(u8, line, "!")) .err else if (std.mem.startsWith(u8, line, "+")) .ok else .info;
        logWrite(&g_log_dummy, level, if (level == .info) line else line[1..]);
    }
    st.refreshAvailable();
    if (picks) |p| {
        var it = std.mem.tokenizeScalar(u8, p, ',');
        while (it.next()) |code| {
            if (@import("asset_languages.zig").fromCode(code)) |l| st.picked[@backingInt(l)] = true;
        }
    }
    // The pictures list on the first frame, and the picked one loads on it.
    drawFrame(&ui, alloc, &st, null);
    if (st.page == .graphics) drawFrame(&ui, alloc, &st, null);
    _ = c.SDL_RenderPresent(renderer);
    if (!c.SDL_SaveBMP(surface, path.ptr)) return error.SaveFailed;
}

/// Asks GitHub about a newer version of the tools, on the channel the game's
/// settings pick, unless they've turned checking off. The tools have no
/// settings of their own; next to the game they share its zelda3.ini, and on
/// their own the defaults stand: check, for releases.
fn checkForUpdates(alloc: std.mem.Allocator) void {
    const path = inGameDir(alloc, "zelda3.ini");
    const z = alloc.dupeSentinel(u8, path, 0) catch return;
    defer alloc.free(z);
    var ini = menu.Ini.load(alloc, z.ptr) catch {
        updater.check(.releases);
        return;
    };
    defer ini.deinit();
    if (menu.updatesOnIn(&ini)) updater.check(menu.updateChannelIn(&ini));
}

pub fn run(alloc: std.mem.Allocator) !void {
    kit.configureJoysticks();
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD | c.SDL_INIT_AUDIO)) {
        std.debug.print("Could not start SDL: {s}\n", .{c.SDL_GetError()});
        return error.SdlInit;
    }
    defer c.SDL_Quit();
    const window = c.SDL_CreateWindow("ALTTP-DX Tools", kWindowW, kWindowH, 0) orelse return error.SdlWindow;
    defer c.SDL_DestroyWindow(window);
    const renderer = c.SDL_CreateRenderer(window, null) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    _ = c.SDL_SetRenderVSync(renderer, 1);
    g_dialog_lock = c.SDL_CreateMutex();
    defer c.SDL_DestroyMutex(g_dialog_lock);
    g_log_lock = c.SDL_CreateMutex();

    // On Windows the updater names the tools' files from their own folder,
    // as the game does from its.
    if (builtin.os.tag == .windows) {
        if (c.SDL_GetBasePath()) |base| fileio.setWorkingDirectory(base) catch {};
    }
    updater.cleanUp();
    checkForUpdates(alloc);

    var st = initialState(alloc);
    reportReadiness(alloc, &st);
    defer {
        st.tunes.drop(alloc);
        if (st.gfx.tex) |t| c.SDL_DestroyTexture(t);
    }

    // Any pad can drive the window, and one plugged in later works too.
    var pads = kit.Pads{};
    defer pads.closeAll();
    var pad_count: c_int = 0;
    if (c.SDL_GetGamepads(&pad_count)) |ids| {
        for (ids[0..@intCast(pad_count)]) |id| pads.open(id);
        c.SDL_free(ids);
    }
    var held = kit.Held{};
    var vrepeat = kit.Repeat{};
    var hrepeat = kit.Repeat{};

    var ui = Ui{ .r = renderer };
    var was_running = false;
    while (!st.quit) {
        const now = c.SDL_GetTicks();
        ui.moved = false;
        ui.clicked = false;
        ui.confirm = false;
        ui.stepped = false;
        ui.adjust = 0;
        var back = false;
        var page_step: i32 = 0;
        // Presses arrive as events so that a tap shorter than a frame still
        // counts; the poll below only decides when a held direction repeats.
        var tap_v: i32 = 0;
        var tap_h: i32 = 0;

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => st.quit = true,
                c.SDL_EVENT_GAMEPAD_ADDED => pads.open(event.gdevice.which),
                c.SDL_EVENT_GAMEPAD_REMOVED => pads.close(event.gdevice.which),
                c.SDL_EVENT_MOUSE_MOTION => {
                    ui.mouse_x = event.motion.x;
                    ui.mouse_y = event.motion.y;
                    ui.moved = true;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    ui.mouse_x = event.button.x;
                    ui.mouse_y = event.button.y;
                    if (event.button.button == c.SDL_BUTTON_LEFT) ui.clicked = true;
                    if (event.button.button == c.SDL_BUTTON_RIGHT) back = true;
                },
                c.SDL_EVENT_MOUSE_WHEEL => {
                    if (ui.mouse_y >= kLogY and ui.mouse_y < kLogY + kLogH and st.page != .graphics) {
                        scrollLog(if (event.wheel.y > 0) 1 else if (event.wheel.y < 0) -1 else 0);
                    }
                },
                // Anything that stops the window seeing releases has to
                // clear what it thinks is held, or a direction sticks on.
                c.SDL_EVENT_WINDOW_FOCUS_LOST => held = .{},
                c.SDL_EVENT_KEY_DOWN => {
                    if (held.set(event.key.key, true)) {
                        switch (event.key.key) {
                            c.SDLK_UP => tap_v -= 1,
                            c.SDLK_DOWN => tap_v += 1,
                            c.SDLK_LEFT => tap_h -= 1,
                            c.SDLK_RIGHT => tap_h += 1,
                            else => {},
                        }
                    } else switch (event.key.key) {
                        c.SDLK_ESCAPE => back = true,
                        c.SDLK_RETURN, c.SDLK_SPACE => ui.confirm = true,
                        c.SDLK_TAB => page_step = if (event.key.mod & c.SDL_KMOD_SHIFT != 0) -1 else 1,
                        c.SDLK_PAGEUP => scrollLog(@intCast(kLogRows - 1)),
                        c.SDLK_PAGEDOWN => scrollLog(-@as(i32, @intCast(kLogRows - 1))),
                        else => {},
                    }
                },
                c.SDL_EVENT_KEY_UP => _ = held.set(event.key.key, false),
                c.SDL_EVENT_GAMEPAD_BUTTON_UP => _ = held.setButton(event.gbutton.button, false),
                // The d-pad and shoulders go by position; the face buttons
                // by the letter printed on them.
                c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => {
                    _ = held.setButton(event.gbutton.button, true);
                    switch (event.gbutton.button) {
                        c.SDL_GAMEPAD_BUTTON_START => ui.confirm = true,
                        c.SDL_GAMEPAD_BUTTON_DPAD_UP => tap_v -= 1,
                        c.SDL_GAMEPAD_BUTTON_DPAD_DOWN => tap_v += 1,
                        c.SDL_GAMEPAD_BUTTON_DPAD_LEFT => tap_h -= 1,
                        c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT => tap_h += 1,
                        c.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER => page_step = -1,
                        c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER => page_step = 1,
                        else => switch (kit.faceAction(event.gbutton.which, event.gbutton.button)) {
                            .confirm => ui.confirm = true,
                            .back => back = true,
                            else => {},
                        },
                    }
                },
                c.SDL_EVENT_DROP_FILE => if (event.drop.data) |p| dropped(alloc, &st, std.mem.span(p)),
                else => {},
            }
        }

        // Directions come from every input's current state rather than from
        // key events, so the keyboard and the pads behave alike and a held
        // direction repeats.
        const vdir = std.math.sign(held.vertical() + pads.stickDirection(.vertical));
        const hdir = std.math.sign(held.horizontal() + pads.stickDirection(.horizontal));
        var move_v: i32 = 0;
        var move_h: i32 = 0;
        if (tap_v != 0) {
            move_v = std.math.sign(tap_v);
            vrepeat.arm(move_v, now);
        } else move_v = vrepeat.step(vdir, now);
        if (tap_h != 0) {
            move_h = std.math.sign(tap_h);
            hrepeat.arm(move_h, now);
        } else move_h = hrepeat.step(hdir, now);

        switch (st.modal) {
            .none => {
                if (move_v != 0) {
                    ui.move(0, @floatFromInt(move_v));
                    // Up into the tabs lands on this page's, not whichever
                    // is nearest, which would change the page.
                    if (ui.focus < kPageCount) ui.focus = @backingInt(st.page);
                }
                // A chooser keeps left and right for itself.
                if (move_h != 0) {
                    if (ui.focusAdjusts()) ui.adjust = move_h else ui.move(@floatFromInt(move_h), 0);
                }
                if (page_step != 0) {
                    st.page = st.page.step(page_step);
                    // The focus goes to the page's own tab, so the arrows
                    // carry on from the top of it.
                    ui.focus = @backingInt(st.page);
                }
                if (back) st.openModal(&ui, .quit, 1);
            },
            .quit => {
                if (move_h != 0) ui.move(@floatFromInt(move_h), 0);
                if (back) st.closeModal(&ui);
            },
            .update => switch (updater.phase()) {
                .downloading => if (back) updater.cancel(),
                .installing, .ready => {},
                else => {
                    if (move_h != 0) ui.move(@floatFromInt(move_h), 0);
                    if (back) {
                        updater.dismiss();
                        st.closeModal(&ui);
                    }
                },
            },
        }
        c.SDL_LockMutex(g_dialog_lock);
        if (g_dialog_result) |path| {
            picked(alloc, &st, g_dialog_field, path);
            alloc.free(path);
            g_dialog_result = null;
        }
        c.SDL_UnlockMutex(g_dialog_lock);

        // A job just finished: it may have made the folder's languages, or
        // written the folder, which isn't an edit to rebuild for.
        const running = jobRunning();
        if (was_running and !running) {
            st.refreshAvailable();
            if (g_job.writesFolder() and st.watch) {
                st.watch_built = folderStamp(&st);
                st.watch_seen = st.watch_built;
            }
        }
        was_running = running;
        watchFolder(alloc, &st, now);

        drawFrame(&ui, alloc, &st, window);
        _ = c.SDL_RenderPresent(renderer);

        // Installed: start the new tools, once no job is halfway through.
        if (updater.phase() == .ready and !running) {
            _ = updater.restart();
            st.quit = true;
        }
    }
}
