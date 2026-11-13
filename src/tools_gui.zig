//! The tools window, laid out like a desktop app and dressed like the start
//! menu: the same night sky and drifting motes, gold for what to press,
//! Cinzel for names. The start menu's Tools entry opens it, and closing it
//! goes back there.
//!
//! A sidebar down the left lists the things to do, with how the assets stand
//! and Play at its foot. The page on the right is the chosen one: a heading
//! saying what it's for, the files it works with, one main button, a line
//! saying what to do next, and what the last job had to say. The mouse, the
//! keys and a pad all drive it. Jobs run on a thread of their own, so the
//! window keeps drawing while a build takes its time. Paths come from the
//! system's own file dialogs, or from dropping a file on the window.
const std = @import("std");
const c = @import("sdl.zig").c;
const ops = @import("tools_ops.zig");
const kit = @import("menu_kit.zig");
const draw = @import("tools_draw.zig");
const start_page = @import("start_page.zig");
/// The start menu's night, its gold, and the pieces drawn with them.
const Night = start_page.Page;
const updater = @import("updater.zig");
const fileio = @import("fileio.zig");
const music = @import("tools_music.zig");
const pictures = @import("tools_pictures.zig");
const game = @import("tools_game.zig");
const rom_mod = @import("rom.zig");
const Language = rom_mod.Language;

const Rect = draw.Rect;
const Color = draw.Color;
const Paint = draw.Paint;

/// The window's size while it's the tools, in points, and the least it can
/// be dragged down to.
pub const kWindowW = 1080;
pub const kWindowH = 720;
pub const kMinW = 880;
pub const kMinH = 600;

const kSideW: f32 = 236;
/// Around the page, and as wide as its rows get on a big window.
const kPad: f32 = 40;
const kMaxPageW: f32 = 760;
/// Where a page's rows start, under its heading.
const kPageTop: f32 = 116;
const kFieldH: f32 = 40;
const kButtonH: f32 = 38;
const kBrowseW: f32 = 104;
const kRadius: f32 = 8;
/// A labeled field and the gap under it.
const kFieldStep: f32 = 24 + kFieldH + 20;
const kLogLineH: f32 = 19;

// The start menu's colors. Gold is for what to press and for names, teal
// for what's picked, cream for what to read.
/// About the sky's own color halfway down, for what sits right on it.
const kBg = Color.hex(0x08121a);
const kSide = Color.hex(0x060d14).alpha(200);
const kSurface = Color.hex(0x0c1820).alpha(232);
const kSurfaceHi = Color.hex(0x16262e);
const kBorder = Color.hex(0x2a3c45);
const kText = start_page.kCream;
const kTextDim = start_page.kMuted;
const kTextFaint = start_page.kDim;
const kAccent = start_page.kGold;
const kAccentHi = start_page.kGoldHi;
/// A gold button, and the brown on it.
const kButton = Color.hex(0xe2bb60);
const kButtonHi = Color.hex(0xf0cd72);
const kOnAccent = Color.hex(0x2a1a04);
const kTeal = start_page.kTeal;
const kOk = start_page.kOk;
const kWarn = start_page.kWarn;

// ------------------------------------------------------------------ the log

const LogLine = struct {
    level: ops.Log.Level,
    len: u16,
    text: [400]u8,
};

var g_log: [300]LogLine = undefined;
var g_log_count: usize = 0;
/// Lines scrolled up from the bottom, as they're wrapped on screen.
var g_log_scroll: usize = 0;
/// Jobs write from their own thread while the window draws.
var g_log_lock: ?*c.SDL_Mutex = null;

fn logWrite(ctx: *anyopaque, level: ops.Log.Level, text: []const u8) void {
    _ = ctx;
    c.SDL_LockMutex(g_log_lock);
    defer c.SDL_UnlockMutex(g_log_lock);
    if (g_log_count == g_log.len) {
        std.mem.copyForwards(LogLine, g_log[0 .. g_log.len - 1], g_log[1..]);
        g_log_count -= 1;
    }
    var line = LogLine{ .level = level, .len = @intCast(@min(text.len, 400)), .text = undefined };
    @memcpy(line.text[0..line.len], text[0..line.len]);
    g_log[g_log_count] = line;
    g_log_count += 1;
    g_log_scroll = 0;
}

fn clearLog() void {
    c.SDL_LockMutex(g_log_lock);
    defer c.SDL_UnlockMutex(g_log_lock);
    g_log_count = 0;
    g_log_scroll = 0;
}

/// Up is positive. How far it can go is found out as it's drawn.
fn scrollLog(lines: i32) void {
    c.SDL_LockMutex(g_log_lock);
    defer c.SDL_UnlockMutex(g_log_lock);
    if (lines > 0) g_log_scroll += @intCast(lines) else g_log_scroll -|= @intCast(-lines);
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

/// The pages, in the sidebar's order.
const Screen = enum {
    assets,
    modding,
    graphics,
    music,
    msu,
    languages,
    extras,

    fn label(self: Screen) []const u8 {
        return switch (self) {
            .assets => "Build Assets",
            .modding => "Mod the Game",
            .graphics => "Graphics",
            .music => "Music",
            .msu => "MSU-1 Pack",
            .languages => "Languages",
            .extras => "Extras",
        };
    }

    /// What it's for, under its heading.
    fn about(self: Screen) []const u8 {
        return switch (self) {
            .assets => "Make the game's asset file from your US ROM. Do this once, and again after an update.",
            .modding => "Export the game's text, maps and pictures to a folder, edit them, then build them back in.",
            .graphics => "Look through the pictures in your work folder, or preview a custom Link sprite.",
            .music => "Listen to the game's songs, played by its own sound driver.",
            .msu => "Check a CD-quality MSU-1 music pack for missing or broken tracks before you use it.",
            .languages => "Take the text out of a translated ROM, like German, French or Redux, and build it into the game.",
            .extras => "Small tools for digging into the game.",
        };
    }
};

const AssetState = enum { missing, standard, custom, old };

/// A question over the window, which takes the keys until it's answered.
const Modal = enum { none, leave };

/// Where the window goes when it closes: back to the start menu, into the
/// game, or out altogether.
pub const Outcome = enum { menu, play, quit };

const State = struct {
    screen: Screen = .assets,
    /// How the asset file stands, for the sidebar, looked at now and then
    /// rather than every frame.
    assets: AssetState = .missing,
    assets_age: u32 = 0,
    paths: [kFieldCount]std.ArrayList(u8) = @splat(.empty),
    sprites_from_png: bool = false,
    /// Translations ticked to build in, and which ones the folder has files
    /// for, checked now and then rather than every frame.
    picked: [kLangCount]bool = @splat(false),
    available: [kLangCount]bool = @splat(false),
    available_age: u32 = 0,
    extra_buf: [kLangCount]Language = undefined,
    modal: Modal = .none,
    /// Which of the modal's two answers is picked: 0 does it, 1 doesn't.
    choice: usize = 0,
    /// Where the focus was before a modal took it, to go back to after.
    focus_before: usize = 0,
    /// Closing, and where to: as soon as no job is halfway through.
    leave: ?Outcome = null,
    /// Told to wait for the job, then go.
    waiting: bool = false,

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

    /// Whether Play has assets the game will start with.
    fn canPlay(self: *const State) bool {
        return self.assets == .standard or self.assets == .custom;
    }

    /// Closes the window, or says it will once the job's done: a job half
    /// written is worse than one never started.
    fn close(self: *State, ui: *Ui, to: Outcome) void {
        self.leave = to;
        if (jobRunning() and self.modal == .none) self.openModal(ui, .leave, 1);
    }

    /// Changed its mind: the window stays.
    fn stay(self: *State, ui: *Ui) void {
        self.leave = null;
        self.waiting = false;
        self.closeModal(ui);
    }

    /// Opens a page with a clean log. The sidebar is drawn first, so the
    /// focus stays on whichever of its entries opened it.
    fn open(self: *State, screen: Screen) void {
        if (self.screen == screen) return;
        // A song stops when its page is left.
        if (self.screen == .music) {
            if (self.tunes.player) |p| p.stop();
        }
        self.screen = screen;
        self.assets_age = 0;
        clearLog();
    }

    /// The asset file's state, looked at again every couple of seconds.
    fn assetsNow(self: *State, alloc: std.mem.Allocator) AssetState {
        if (self.assets_age == 0 or self.assets_age > 120) {
            self.assets = assetState(alloc, self.get(.out));
            self.assets_age = 0;
        }
        self.assets_age += 1;
        return self.assets;
    }
};

/// Where a file called `name` sits in the game's folder, which is the one
/// this runs in: the start menu moved into it before opening the window.
fn inGameDir(alloc: std.mem.Allocator, name: []const u8) []const u8 {
    var buf: [4096]u8 = undefined;
    const cwd = fileio.workingDirectory(&buf) catch return name;
    const sep = if (std.mem.endsWith(u8, cwd, std.fs.path.sep_str)) "" else std.fs.path.sep_str;
    return std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ cwd, sep, name }) catch name;
}

/// Where the game looks for its asset file.
fn gameAssetPath(alloc: std.mem.Allocator) []const u8 {
    return inGameDir(alloc, "zelda3_assets.dat");
}

fn exists(alloc: std.mem.Allocator, path: []const u8) bool {
    const z = alloc.dupeSentinel(u8, path, 0) catch return false;
    defer alloc.free(z);
    return fileio.exists(z.ptr);
}

/// Closes the window into the game, and says if it won't see what was just
/// built because that was saved somewhere it doesn't look.
fn play(alloc: std.mem.Allocator, ui: *Ui, st: *State) void {
    const expected = gameAssetPath(alloc);
    if (!std.mem.eql(u8, expected, st.get(.out))) {
        g_logger.info("The game reads its assets from {s}, not from where these were saved. Save them there to play them.", .{expected});
    }
    st.close(ui, .play);
}

// ------------------------------------------------------------------- jobs

const Job = enum {
    build,
    export_files,
    build_from_files,
    extract_dialogue,
    check_msu,
    input_log,
    text_dict,

    /// What the page says while it runs.
    fn doing(self: Job) []const u8 {
        return switch (self) {
            .build => "Building the assets",
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
    if (g_log_count != 0) logWrite(&g_log_dummy, .info, "");
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
        .export_files => _ = ops.exportFiles(alloc, g_logger, a.get(.rom), a.get(.folder)),
        .build_from_files => _ = ops.buildFromFiles(alloc, g_logger, a.get(.rom), a.get(.folder), a.get(.out), .{ .sprites_from_png = a.sprites_from_png }, extra),
        .extract_dialogue => _ = ops.extractDialogue(alloc, g_logger, a.get(.lang_rom), a.get(.folder), null),
        .check_msu => _ = ops.checkMsuPack(alloc, g_logger, a.get(.msu)),
        .input_log => _ = ops.saveInputLog(alloc, g_logger, a.get(.snapshot)),
        .text_dict => _ = ops.saveTextDict(alloc, g_logger, a.get(.dialogue)),
    }
}

// -------------------------------------------------------------- immediate UI

const kMaxItems = 64;

/// Everything that can be picked registers itself as it's drawn, in order,
/// and the arrows move between them by where they sit on screen. So a page
/// is just drawn, and the keys and pads work on it without a list of its
/// own to keep in step.
const Ui = struct {
    p: *Paint,
    /// The sky, the glow and the start menu's pieces, drawn with `p`.
    night: *const Night,
    /// Seconds, for what moves.
    t: f32 = 0,
    /// The window's size, in points.
    w: f32 = kWindowW,
    h: f32 = kWindowH,
    mouse_x: f32 = -1,
    mouse_y: f32 = -1,
    /// The mouse moved this frame, so whatever it's over takes the focus.
    moved: bool = false,
    clicked: bool = false,
    /// A or Enter this frame: whatever has the focus is pressed.
    confirm: bool = false,
    /// Left or right this frame, for a chooser with the focus, which takes
    /// them itself rather than moving off.
    adjust: i32 = 0,
    /// The keys or a pad moved the focus last, rather than the mouse, so the
    /// focus is shown with a ring.
    keys: bool = false,
    /// Something that can be clicked is under the mouse, for the pointer.
    over_any: bool = false,
    /// Which item has the focus, by its place in the frame's drawing order.
    focus: usize = 0,
    /// While a modal is up, the window under it is drawn but takes nothing.
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

    const Hit = struct {
        focused: bool,
        pressed: bool,
        /// Drawn as hovered: under the mouse, or focused by the keys.
        lit: bool,
        /// Focused by the keys, so it wants a ring.
        ring: bool,
    };
    const kNoHit = Hit{ .focused = false, .pressed = false, .lit = false, .ring = false };

    fn begin(self: *Ui) void {
        self.last_rects = self.rects;
        self.last_enabled = self.enabled;
        self.last_adjustable = self.adjustable;
        self.last_count = self.count;
        self.count = 0;
        self.over_any = false;
    }

    /// Registers something that can be picked, and says whether it has the
    /// focus and whether it was pressed this frame.
    fn item(self: *Ui, rect: Rect, enabled: bool) Hit {
        return self.itemOf(rect, enabled, false);
    }

    fn itemOf(self: *Ui, rect: Rect, enabled: bool, adjustable: bool) Hit {
        if (self.blocked or self.count == kMaxItems) return kNoHit;
        const id = self.count;
        self.rects[id] = rect;
        self.enabled[id] = enabled;
        self.adjustable[id] = adjustable;
        self.count += 1;
        const over = rect.contains(self.mouse_x, self.mouse_y);
        if (enabled and over) self.over_any = true;
        if (enabled and over and (self.moved or self.clicked)) self.focus = id;
        const focused = id == self.focus;
        return .{
            .focused = focused,
            .pressed = enabled and ((over and self.clicked) or (focused and self.confirm)),
            .lit = enabled and ((over and !self.keys) or (focused and self.keys)),
            .ring = enabled and focused and self.keys,
        };
    }

    /// Whether the focus is on a chooser, which keeps left and right.
    fn focusAdjusts(self: *const Ui) bool {
        return self.focus < self.last_count and self.last_adjustable[self.focus] and self.last_enabled[self.focus];
    }

    /// Moves the focus to the nearest item in a direction: straight ahead
    /// first, then whatever's least out of line.
    fn move(self: *Ui, dx: f32, dy: f32) void {
        self.keys = true;
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
        if (best) |b| self.focus = b;
    }

    /// The focus ring, around `rect`, on `under`.
    fn ring(self: *const Ui, rect: Rect, radius: f32, under: Color) void {
        self.p.box(rect.inset(-3), radius + 3, 2, kAccentHi, under);
    }

    /// A file or folder to work with: its label, then a box with the path
    /// in it and Browse at its end. Clicking any of it browses. `tag` is a
    /// word on how it stands, at the box's right.
    fn field(self: *Ui, x: f32, y: f32, w: f32, label: []const u8, path: []const u8, placeholder: []const u8, tag: ?Tag) bool {
        self.p.text(.strong, x, y, kText, label);
        const row = Rect{ .x = x, .y = y + 24, .w = w, .h = kFieldH };
        const hit = self.item(row, true);
        if (hit.ring) self.ring(row, kRadius, kBg);
        const box = Rect{ .x = row.x, .y = row.y, .w = row.w - kBrowseW - 8, .h = row.h };
        self.p.box(box, kRadius, 1, if (hit.lit) kAccent.alpha(150) else kBorder, kSurface);

        var right = box.x + box.w - 12;
        if (tag) |t| {
            const tw = self.p.textWidth(.small, t.text);
            self.p.text(.small, right - tw, box.y + 11, t.color, t.text);
            right -= tw + 16;
        }
        self.pathText(.{ .x = box.x + 14, .y = box.y + 10, .w = right - box.x - 14, .h = 20 }, path, placeholder);

        const browse = Rect{ .x = row.x + row.w - kBrowseW, .y = row.y, .w = kBrowseW, .h = row.h };
        self.p.box(browse, browse.h / 2, 1, if (hit.lit) kAccent else kBorder, if (hit.lit) kSurfaceHi else kSurface);
        self.p.textCentered(.strong, browse.x + browse.w / 2, browse.y + 10, if (hit.lit) kAccentHi else kText, "Browse\u{2026}");
        return hit.pressed;
    }

    /// A path the way people think of one: the file's name, then which
    /// folder it's in.
    fn pathText(self: *const Ui, at: Rect, path: []const u8, placeholder: []const u8) void {
        var buf: [256]u8 = undefined;
        if (path.len == 0) return self.p.text(.body, at.x, at.y, kTextFaint, self.p.fit(.body, placeholder, at.w, &buf));
        const name = self.p.fit(.body, std.fs.path.basename(path), at.w, &buf);
        self.p.text(.body, at.x, at.y, kText, name);
        const used = self.p.textWidth(.body, name);
        const folder = std.fs.path.basename(std.fs.path.dirname(path) orelse "");
        if (folder.len == 0) return;
        var in_buf: [160]u8 = undefined;
        var fit_buf: [256]u8 = undefined;
        const after = std.fmt.bufPrint(&in_buf, "  in {s}", .{folder}) catch return;
        const room = at.w - used;
        if (room < 60) return;
        self.p.text(.body, at.x + used, at.y, kTextDim, self.p.fit(.body, after, room, &fit_buf));
    }

    /// Picks one of several things: its label, then the choice between
    /// arrows. Left and right step through them, as does a click on either
    /// half; A steps forward. Returns the step, or 0.
    fn stepper(self: *Ui, x: f32, y: f32, w: f32, label: []const u8, value: []const u8, enabled: bool) i32 {
        self.p.text(.strong, x, y, kText, label);
        const row = Rect{ .x = x, .y = y + 24, .w = w, .h = kFieldH };
        const hit = self.itemOf(row, enabled, true);
        if (hit.ring) self.ring(row, kRadius, kBg);
        self.p.box(row, kRadius, 1, if (hit.lit) kAccent.alpha(150) else kBorder, kSurface);
        const over_left = self.mouse_x < row.x + row.w / 2;
        for ([_]bool{ true, false }) |left| {
            const b = Rect{ .x = if (left) row.x + 4 else row.x + row.w - 36, .y = row.y + 4, .w = 32, .h = row.h - 8 };
            if (hit.lit and !self.keys and over_left == left) self.p.fillRound(b, 6, kSurfaceHi);
            self.p.textCentered(.strong, b.x + b.w / 2, b.y + 6, if (enabled) kAccent else kTextFaint, if (left) "\u{2190}" else "\u{2192}");
        }
        var buf: [256]u8 = undefined;
        const shown = self.p.fit(.body, value, row.w - 96, &buf);
        self.p.textCentered(.body, row.x + row.w / 2, row.y + 10, if (enabled) kText else kTextDim, shown);

        if (!hit.focused or !enabled) return 0;
        if (self.adjust != 0) return self.adjust;
        if (hit.pressed) return if (self.clicked and over_left) -1 else 1;
        return 0;
    }

    /// A box to tick, and what it means. True on the frame it's picked.
    fn check(self: *Ui, x: f32, y: f32, label: []const u8, on: bool, enabled: bool) bool {
        const w = 28 + self.p.textWidth(.body, label);
        const row = Rect{ .x = x - 6, .y = y, .w = w + 12, .h = 28 };
        const hit = self.item(row, enabled);
        if (hit.ring) self.ring(row, 6, kBg);
        if (hit.lit) self.p.fillRound(row, 6, kSurface);
        const box = Rect{ .x = x, .y = y + 5, .w = 18, .h = 18 };
        if (on and enabled) {
            self.p.fillRound(box, 5, kButton);
            self.p.textCentered(.strong, box.x + box.w / 2, box.y - 1, kOnAccent, "\u{2713}");
        } else {
            self.p.box(box, 5, 1.5, if (enabled) kTextDim else kBorder, kSurface);
        }
        self.p.text(.body, x + 28, y + 4, if (enabled) kText else kTextFaint, label);
        return hit.pressed;
    }

    /// A page's buttons, side by side from the left: the main one filled,
    /// any other an outline. Says which was pressed, if one was.
    fn buttons(self: *Ui, x0: f32, y: f32, list: []const Action) ?usize {
        var x = x0;
        var pressed: ?usize = null;
        for (list, 0..) |a, i| {
            const rect = Rect{ .x = x, .y = y, .w = self.p.textWidth(.strong, a.label) + 40, .h = kButtonH };
            x += rect.w + 12;
            const hit = self.item(rect, a.enabled);
            if (hit.ring) self.ring(rect, rect.h / 2, kBg);
            // Pills, as the start menu's answers are: gold for the one to
            // press, an outline for the rest.
            const round = rect.h / 2;
            if (!a.enabled) {
                self.p.box(rect, round, 1, kBorder.alpha(140), kSurface);
                self.p.textCentered(.strong, rect.x + rect.w / 2, rect.y + 9, kTextFaint, a.label);
            } else if (a.main) {
                if (hit.lit) self.night.glowAt(rect.x + rect.w / 2, rect.y + rect.h / 2, rect.w * 0.7, kAccent.alpha(60));
                self.p.box(rect, round, 1.5, kAccentHi, if (hit.lit) kButtonHi else kButton);
                self.p.textCentered(.strong, rect.x + rect.w / 2, rect.y + 9, kOnAccent, a.label);
            } else {
                self.p.box(rect, round, 1, if (hit.lit) kAccent else kBorder, if (hit.lit) kSurfaceHi else kSurface);
                self.p.textCentered(.strong, rect.x + rect.w / 2, rect.y + 9, if (hit.lit) kAccentHi else kText, a.label);
            }
            if (hit.pressed) pressed = i;
        }
        return pressed;
    }
};

const Action = struct { label: []const u8, enabled: bool, main: bool = true };
const Tag = struct { text: []const u8, color: Color };

/// A rectangle as the start menu's pieces take one.
fn kr(r: Rect) kit.Rect {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
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

/// What a path needs to find for things to go ahead.
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

/// "Not found" for a path that has to be there and isn't.
fn mustTag(path: []const u8, must: Must) ?Tag {
    if (path.len == 0 or must.satisfiedBy(path)) return null;
    return .{ .text = "Not found", .color = kWarn };
}

/// For the ROM: what it is, or what's wrong with it.
fn romTag(st: *State) ?Tag {
    const rom = st.get(.rom);
    if (rom.len == 0) return null;
    if (mustTag(rom, .file)) |t| return t;
    return switch (romKind(st)) {
        .us => .{ .text = "\u{2713} US ROM", .color = kOk },
        .other => .{ .text = "Not the US ROM", .color = kWarn },
        .unreadable => .{ .text = "Can't read it", .color = kWarn },
    };
}

/// A folder that'll be made when something's put in it.
fn folderTag(path: []const u8) ?Tag {
    if (path.len == 0 or Must.folder.satisfiedBy(path)) return null;
    return .{ .text = "Will be made", .color = kTextDim };
}

/// Under the buttons: the next thing to do, in a sentence, so a grayed-out
/// button is never a mystery. While a job runs, what it's doing.
fn statusLine(ui: *Ui, x: f32, y: f32, say: []const u8) void {
    if (jobRunning()) {
        // Three dots, brightening in turn.
        const t: f32 = @floatFromInt(c.SDL_GetTicks() % 900);
        for (0..3) |i| {
            const phase = @mod(t / 300 - @as(f32, @floatFromInt(i)), 3);
            const a: u8 = if (phase < 1) 255 else 90;
            ui.p.disc(x + 4 + @as(f32, @floatFromInt(i)) * 10, y + 10, 3, kAccent.alpha(a));
        }
        var buf: [64]u8 = undefined;
        ui.p.text(.body, x + 34, y, kAccentHi, std.fmt.bufPrint(&buf, "{s}\u{2026}", .{g_job.doing()}) catch "");
        return;
    }
    ui.p.text(.body, x, y, kTextDim, say);
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

/// What the ROM is missing, if anything.
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

/// Where a page draws: its left edge, its width, and how far down it can go.
const Page = struct { x: f32, w: f32, bottom: f32 };

/// Each page returns how far down it drew, for the activity under it.
fn drawAssets(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window, pg: Page) f32 {
    var y: f32 = kPageTop;
    if (ui.field(pg.x, y, pg.w, "Your ROM", st.get(.rom), "Drop a .sfc on the window, or Browse", romTag(st))) openDialog(window, .rom);
    y += kFieldStep;
    if (ui.field(pg.x, y, pg.w, "Save assets to", st.get(.out), "zelda3_assets.dat", null)) openDialog(window, .out);
    y += kFieldStep + 4;

    const ready = !jobRunning() and romStep(st) == null and st.get(.out).len != 0;
    if (ui.buttons(pg.x, y, &.{.{ .label = "Build Assets", .enabled = ready }}) != null) startJob(alloc, st, .build);
    statusLine(ui, pg.x + buttonsWidth(ui, &.{"Build Assets"}) + 20, y + 9, romStep(st) orelse if (st.get(.out).len == 0) "Pick where to save the assets." else "Ready when you are.");
    return y + kButtonH;
}

/// How wide `buttons` will draw these labels, for whatever goes beside them.
fn buttonsWidth(ui: *const Ui, labels: []const []const u8) f32 {
    var w: f32 = -12;
    for (labels) |l| w += ui.p.textWidth(.strong, l) + 40 + 12;
    return w;
}

fn drawModding(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window, pg: Page) f32 {
    var y: f32 = kPageTop;
    if (ui.field(pg.x, y, pg.w, "Your ROM", st.get(.rom), "Drop a .sfc on the window, or Browse", romTag(st))) openDialog(window, .rom);
    y += kFieldStep;
    if (ui.field(pg.x, y, pg.w, "Work folder", st.get(.folder), "Where the files go to be edited", folderTag(st.get(.folder)))) openDialog(window, .folder);
    y += kFieldStep;
    if (ui.field(pg.x, y, pg.w, "Save assets to", st.get(.out), "zelda3_assets.dat", null)) openDialog(window, .out);
    y += kFieldStep - 6;
    if (ui.check(pg.x, y, "Build sprite sheets from PNGs too", st.sprites_from_png, true)) st.sprites_from_png = !st.sprites_from_png;
    if (ui.check(pg.x + pg.w / 2, y, "Rebuild when a file is saved", st.watch, true)) setWatch(st, !st.watch);
    y += 48;

    const idle = !jobRunning();
    const rom_ok = romStep(st) == null;
    const exported = Must.folder.satisfiedBy(st.get(.folder));
    const can_export = idle and rom_ok and st.get(.folder).len != 0;
    // Exporting comes first; once there's a folder, building from it is the
    // thing to do, and exporting again is on the side.
    var width: f32 = 0;
    if (!exported) {
        if (ui.buttons(pg.x, y, &.{.{ .label = "Export Files", .enabled = can_export }}) != null) startJob(alloc, st, .export_files);
        width = buttonsWidth(ui, &.{"Export Files"});
    } else {
        if (ui.buttons(pg.x, y, &.{
            .{ .label = "Build from Files", .enabled = idle and rom_ok and st.get(.out).len != 0 },
            .{ .label = "Export Again", .enabled = can_export, .main = false },
        })) |i| startJob(alloc, st, if (i == 0) .build_from_files else .export_files);
        width = buttonsWidth(ui, &.{ "Build from Files", "Export Again" });
    }

    statusLine(ui, pg.x + width + 20, y + 9, romStep(st) orelse if (st.get(.folder).len == 0)
        "Pick a work folder for the files."
    else if (!exported)
        "Export fills the work folder."
    else if (st.watch)
        "Watching: save a file and it rebuilds."
    else
        "Edit the files, then build.");
    return y + kButtonH;
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

/// The picture takes the rest of the page, in place of the activity.
fn drawGraphics(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window, pg: Page) f32 {
    const g = &st.gfx;
    if (g.age == 0 or g.age > 120) g.refresh(alloc, st);
    g.age += 1;

    var y: f32 = kPageTop;
    const half = (pg.w - 16) / 2;
    if (ui.field(pg.x, y, half, "Link sprite", st.get(.zspr), "A .zspr file", mustTag(st.get(.zspr), .file))) openDialog(window, .zspr);
    const n = g.count(st);
    var buf: [96]u8 = undefined;
    const value = if (n == 0) "Nothing to show yet" else std.fmt.bufPrint(&buf, "{s}  ({d} of {d})", .{ std.fs.path.basename(g.path(st, g.index)), g.index + 1, n }) catch "";
    const step = ui.stepper(pg.x + half + 16, y, half, "Picture", value, n > 1);
    if (step != 0 and n > 0) g.index = @intCast(@mod(@as(i64, @intCast(g.index)) + step, @as(i64, @intCast(n))));
    y += kFieldStep;

    g.load(alloc, st, ui.p.r);
    const say = if (n == 0)
        (if (Must.folder.satisfiedBy(st.get(.folder))) "No pictures in the work folder yet." else "Export the files in Mod the Game, or pick a Link sprite.")
    else
        g.about;
    ui.p.text(.body, pg.x, y, if (g.bad) kWarn else kTextDim, say);
    y += 30;
    const box = Rect{ .x = pg.x, .y = y, .w = pg.w, .h = pg.bottom - y };
    ui.night.panel(kr(box));
    if (n != 0) {
        if (g.tex) |tex| drawPicture(ui.p.r, tex, g.w, g.h, box.inset(16));
    }
    return pg.bottom;
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

fn drawMusic(ui: *Ui, alloc: std.mem.Allocator, st: *State, pg: Page) f32 {
    const t = &st.tunes;
    t.ensure(alloc, st.get(.out));

    var y: f32 = kPageTop;
    const songs: []const music.Song = if (t.player) |p| p.songs else &.{};
    var buf: [64]u8 = undefined;
    const value = if (songs.len == 0) "No songs yet" else std.fmt.bufPrint(&buf, "Song {d}, {s}  ({d} of {d})", .{ songs[t.index].number, @tagName(songs[t.index].bank), t.index + 1, songs.len }) catch "";
    const step = ui.stepper(pg.x, y, @min(pg.w, 420), "Song", value, songs.len > 1);
    if (step != 0 and songs.len > 0) {
        t.index = @intCast(@mod(@as(i64, @intCast(t.index)) + step, @as(i64, @intCast(songs.len))));
        // Changing songs while one plays changes what's playing.
        if (t.player.?.playing != null) _ = t.player.?.play(songs[t.index]);
    }
    y += kFieldStep + 4;

    const playing = if (t.player) |p| p.playing else null;
    const label = if (playing != null) "\u{25a0}  Stop" else "\u{25b6}  Play";
    if (ui.buttons(pg.x, y, &.{.{ .label = label, .enabled = songs.len != 0 }}) != null) {
        if (playing != null) {
            t.player.?.stop();
        } else if (!t.player.?.play(songs[t.index])) {
            g_logger.err("Couldn't play anything: there's no sound device to play it on.", .{});
        }
    }

    var say_buf: [64]u8 = undefined;
    statusLine(ui, pg.x + buttonsWidth(ui, &.{label}) + 20, y + 9, if (t.problem.len != 0)
        t.problem
    else if (playing) |p|
        std.fmt.bufPrint(&say_buf, "Playing song {d}. The arrows change it.", .{p.number}) catch ""
    else
        "Pick a song, then Play.");
    return y + kButtonH;
}

fn drawMsu(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window, pg: Page) f32 {
    var y: f32 = kPageTop;
    if (ui.field(pg.x, y, pg.w, "MSU-1 pack", st.get(.msu), "A pack's folder or .zip", mustTag(st.get(.msu), .either))) openDialog(window, .msu);
    y += kFieldStep + 4;
    const pack_ok = st.get(.msu).len != 0 and Must.either.satisfiedBy(st.get(.msu));
    if (ui.buttons(pg.x, y, &.{.{ .label = "Check Pack", .enabled = !jobRunning() and pack_ok }}) != null) startJob(alloc, st, .check_msu);
    statusLine(ui, pg.x + buttonsWidth(ui, &.{"Check Pack"}) + 20, y + 9, if (pack_ok) "Ready to look it over." else "Pick a pack's folder or .zip, or drop it on the window.");
    return y + kButtonH;
}

// --------------------------------------------------------------- languages

fn languageName(lang: Language) []const u8 {
    return switch (lang) {
        .us => "English (US)",
        .de => "German",
        .fr => "French",
        .fr_c => "French (Canada)",
        .en => "English (Europe)",
        .es => "Spanish",
        .pl => "Polish",
        .pt => "Portuguese",
        .redux => "Redux",
        .nl => "Dutch",
        .sv => "Swedish",
    };
}

fn drawLanguages(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window, pg: Page) f32 {
    if (st.available_age == 0 or st.available_age > 60) st.refreshAvailable();
    st.available_age += 1;

    var y: f32 = kPageTop;
    if (ui.field(pg.x, y, pg.w, "Translated ROM", st.get(.lang_rom), "A German, French, Redux\u{2026} ROM", mustTag(st.get(.lang_rom), .file))) openDialog(window, .lang_rom);
    y += kFieldStep;
    if (ui.field(pg.x, y, pg.w, "Work folder", st.get(.folder), "Where the extracted text goes", folderTag(st.get(.folder)))) openDialog(window, .folder);
    y += kFieldStep;
    if (ui.field(pg.x, y, pg.w, "Your US ROM", st.get(.rom), "The build needs it too", romTag(st))) openDialog(window, .rom);
    y += kFieldStep - 4;

    // Only the languages the folder has text for, which are the ones there
    // are to tick; until there's one, the line beside the button says how
    // to get it.
    const cols = 4;
    const col_w: f32 = pg.w / cols;
    var n: usize = 0;
    for (std.enums.values(Language)) |lang| {
        const i = @backingInt(lang);
        if (lang == .us or !st.available[i]) continue;
        if (n == 0) {
            ui.p.text(.strong, pg.x, y, kText, "Build these in");
            y += 26;
        }
        const x = pg.x + @as(f32, @floatFromInt(n % cols)) * col_w;
        const row_y = y + @as(f32, @floatFromInt(n / cols)) * 32;
        if (ui.check(x, row_y, languageName(lang), st.picked[i], true)) st.picked[i] = !st.picked[i];
        n += 1;
    }
    y += if (n == 0) 6 else @as(f32, @floatFromInt((n + cols - 1) / cols)) * 32 + 14;

    var any_picked = false;
    for (st.available, st.picked) |a, p| any_picked = any_picked or (a and p);
    const idle = !jobRunning();
    const can_extract = idle and st.get(.lang_rom).len != 0 and Must.file.satisfiedBy(st.get(.lang_rom)) and st.get(.folder).len != 0;
    // Extracting comes first; once there's a language to tick, building it
    // in is the thing to do, and extracting another is on the side.
    var width: f32 = 0;
    if (n == 0) {
        if (ui.buttons(pg.x, y, &.{.{ .label = "Extract Dialogue", .enabled = can_extract }}) != null) startJob(alloc, st, .extract_dialogue);
        width = buttonsWidth(ui, &.{"Extract Dialogue"});
    } else {
        if (ui.buttons(pg.x, y, &.{
            .{ .label = "Build Assets", .enabled = idle and any_picked and romStep(st) == null and st.get(.out).len != 0 },
            .{ .label = "Extract Dialogue", .enabled = can_extract, .main = false },
        })) |i| startJob(alloc, st, if (i == 0) .build else .extract_dialogue);
        width = buttonsWidth(ui, &.{ "Build Assets", "Extract Dialogue" });
    }

    statusLine(ui, pg.x + width + 20, y + 9, if (n == 0 and st.get(.lang_rom).len == 0)
        "Pick a translated ROM to take its text from."
    else if (n == 0)
        "Extract its text into the work folder."
    else if (!any_picked)
        "Tick the languages to build into the game."
    else
        romStep(st) orelse "Ready to build them in.");
    return y + kButtonH;
}

// ------------------------------------------------------------------- extras

fn drawExtras(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window, pg: Page) f32 {
    const idle = !jobRunning();
    const snapshot_ok = st.get(.snapshot).len != 0 and Must.file.satisfiedBy(st.get(.snapshot));
    const dialogue_ok = st.get(.dialogue).len != 0 and Must.file.satisfiedBy(st.get(.dialogue));
    const field_w = pg.w - 180;

    var y: f32 = kPageTop;
    if (ui.field(pg.x, y, field_w, "Input log from a snapshot", st.get(.snapshot), "A .sav from the saves folder", mustTag(st.get(.snapshot), .file))) openDialog(window, .snapshot);
    if (ui.buttons(pg.x + field_w + 16, y + 25, &.{.{ .label = "Save Input Log", .enabled = idle and snapshot_ok, .main = false }}) != null) startJob(alloc, st, .input_log);
    y += kFieldStep;
    ui.p.text(.small, pg.x, y - 14, kTextDim, "Writes the buttons pressed since the snapshot as text, beside it.");
    y += 16;

    if (ui.field(pg.x, y, field_w, "Dictionary for the dialogue", st.get(.dialogue), "A dialogue.txt, as Export writes", mustTag(st.get(.dialogue), .file))) openDialog(window, .dialogue);
    if (ui.buttons(pg.x + field_w + 16, y + 25, &.{.{ .label = "Find Dictionary", .enabled = idle and dialogue_ok, .main = false }}) != null) startJob(alloc, st, .text_dict);
    y += kFieldStep;
    ui.p.text(.small, pg.x, y - 14, kTextDim, "Searches for the best text compression dictionary. Takes a few minutes.");
    y += 16;

    if (jobRunning()) statusLine(ui, pg.x, y, "");
    return y + 20;
}

// ------------------------------------------------------------- the frame

/// The update offer shows in the sidebar while there is one.

/// The updater's labels are capitals, for the start menu's font: "V1.9",
/// "NIGHTLY 1A2B3C4". Here they read "v1.9" and "Nightly 1a2b3c4".
fn softLabel(label: []const u8, buf: []u8) []const u8 {
    const s = std.ascii.lowerString(buf[0..@min(buf.len, label.len)], label[0..@min(buf.len, label.len)]);
    if (s.len > 0 and s[0] == 'n') s[0] = 'N';
    return s;
}

/// The Triforce by the window's name, as the start menu's screens have it.
fn drawBrand(ui: *Ui) void {
    ui.night.crest(36, 24, 26, ui.t);
    ui.p.textEx(.headline, 66, 16, kAccentHi, start_page.kGoldDeep, 3, "Tools");
    ui.p.textEx(.small, 68, 52, kTextFaint, kTextFaint, 1.6, "A LINK TO THE PAST DX");
}

/// Down the left: the pages, then how the assets stand, Play and the
/// version.
fn drawSidebar(ui: *Ui, alloc: std.mem.Allocator, st: *State) void {
    ui.p.fill(.{ .x = 0, .y = 0, .w = kSideW, .h = ui.h }, kSide);
    // Its edge, gold fading out at both ends.
    ui.night.fade(.{ .x = kSideW - 1, .y = 0, .w = 1, .h = ui.h / 2 }, kAccent.alpha(0), kAccent.alpha(70), false);
    ui.night.fade(.{ .x = kSideW - 1, .y = ui.h / 2, .w = 1, .h = ui.h / 2 }, kAccent.alpha(70), kAccent.alpha(0), false);
    drawBrand(ui);
    ui.night.fade(.{ .x = 20, .y = 78, .w = kSideW - 40, .h = 1 }, kAccent.alpha(90), kAccent.alpha(0), true);

    var y: f32 = 92;
    for (std.enums.values(Screen)) |screen| {
        const row = Rect{ .x = 12, .y = y, .w = kSideW - 24, .h = 36 };
        const hit = ui.item(row, true);
        const current = st.screen == screen;
        if (hit.ring) ui.ring(row, kRadius, kSide);
        // The start menu's own pick: a band of teal light, a gold edge and
        // a diamond. Under the pointer, just the light.
        if (current) {
            ui.night.band(kr(row), true, ui.t);
        } else if (hit.lit) {
            ui.night.fade(kr(row), kTeal.alpha(26), kTeal.alpha(0), true);
        }
        ui.p.text(.item, row.x + 28, row.y + (row.h - ui.p.lineHeight(.item)) / 2, if (current) kText else if (hit.lit) Color.hex(0xd9cfb6) else kTextDim, screen.label());
        if (hit.pressed) st.open(screen);
        y += 38;
    }

    // From the bottom up.
    var buf: [40]u8 = undefined;
    var soft: [40]u8 = undefined;
    const ver = if (updater.installed == .dev) "Dev build" else softLabel(updater.installedLabel(&buf), &soft);
    ui.p.text(.small, 22, ui.h - 30, kTextFaint, ver);

    // The start menu's Play, gold, or a dim outline of it with nothing to
    // play yet.
    const can_play = st.canPlay();
    const play_rect = Rect{ .x = 28, .y = ui.h - 44 - 46, .w = kSideW - 56, .h = 44 };
    const hit = ui.item(play_rect, can_play);
    if (can_play) {
        ui.night.playButton(kr(play_rect), "Play", hit.lit, ui.t);
    } else {
        ui.p.box(play_rect, play_rect.h / 2, 1, kBorder, kSurface);
        ui.p.textEx(.button, play_rect.x + play_rect.w / 2 - ui.p.textWidthTracked(.button, "PLAY", 7) / 2, play_rect.y + (play_rect.h - ui.p.lineHeight(.button)) / 2 + 1, kTextFaint, kTextFaint, 7, "PLAY");
    }
    if (hit.pressed) play(alloc, ui, st);

    const line: struct { []const u8, []const u8, Color } = switch (st.assetsNow(alloc)) {
        .standard => .{ "Assets ready", "Built from your US ROM", kOk },
        .custom => .{ "Custom assets", "From a mod or translation", kOk },
        .missing => .{ "No assets yet", "Build them from your ROM", kWarn },
        .old => .{ "Assets out of date", "Build them again", kWarn },
    };
    const status = Rect{ .x = 12, .y = play_rect.y - 60, .w = kSideW - 24, .h = 46 };
    // Clicking it when there's something to do goes and does it.
    const fixable = st.assets == .missing or st.assets == .old;
    const shit = ui.item(status, fixable);
    if (shit.ring) ui.ring(status, kRadius, kSide);
    if (shit.lit) ui.night.fade(kr(status), kTeal.alpha(26), kTeal.alpha(0), true);
    ui.p.disc(status.x + 16, status.y + 15, 4, line[2]);
    ui.p.text(.strong, status.x + 28, status.y + 5, kText, line[0]);
    ui.p.text(.small, status.x + 28, status.y + 24, kTextDim, line[1]);
    if (shit.pressed) st.open(.assets);

    // The way back to the start menu, above how the assets stand, a pill
    // like the start menu's own Back.
    const back = Rect{ .x = 28, .y = status.y - 46, .w = kSideW - 56, .h = 32 };
    const bhit = ui.item(back, true);
    if (bhit.ring) ui.ring(back, back.h / 2, kSide);
    ui.p.box(back, back.h / 2, 1, if (bhit.lit) kAccent else kBorder, if (bhit.lit) kSurfaceHi else kSurface);
    ui.p.textCentered(.strong, back.x + back.w / 2, back.y + (back.h - ui.p.lineHeight(.strong)) / 2, if (bhit.lit) kAccentHi else kText, "\u{2190}  Start Menu");
    if (bhit.pressed) st.close(ui, .menu);
}

/// What the last job said, filling the rest of the page, once there's
/// something to show.
fn drawLog(ui: *Ui, rect: Rect) void {
    if (rect.h < 80) return;
    if (g_log_count == 0 and !jobRunning()) return;
    ui.night.heading(rect.x, rect.y, rect.w, 18, "Activity");
    const panel = Rect{ .x = rect.x, .y = rect.y + 26, .w = rect.w, .h = rect.h - 26 };
    ui.night.panel(kr(panel));
    // While a job runs, a bar slides along the top of the panel.
    if (jobRunning()) {
        const track = panel.w - 32;
        const seg: f32 = 120;
        const t: f32 = @floatFromInt(c.SDL_GetTicks() % 1400);
        const at = (t / 1400) * (track + seg) - seg;
        const from = @max(0, at);
        const to = @min(track, at + seg);
        if (to > from) ui.p.fillRound(.{ .x = panel.x + 16 + from, .y = panel.y + 1, .w = to - from, .h = 2 }, 1, kTeal);
    }

    c.SDL_LockMutex(g_log_lock);
    defer c.SDL_UnlockMutex(g_log_lock);
    const inner = Rect{ .x = panel.x + 16, .y = panel.y + 12, .w = panel.w - 32, .h = panel.h - 24 };
    const rows: usize = @intFromFloat(@max(1, @floor(inner.h / kLogLineH)));

    // From the newest line back, wrapped to the panel, skipping what's
    // scrolled past, until the panel's full.
    const Seg = struct { level: ops.Log.Level, text: []const u8 };
    var segs: [64]Seg = undefined;
    var count: usize = 0;
    var skip = g_log_scroll;
    var i = g_log_count;
    outer: while (i > 0) {
        i -= 1;
        const line = &g_log[i];
        var pieces: [24][]const u8 = undefined;
        var np: usize = 0;
        var rest: []const u8 = line.text[0..line.len];
        if (rest.len == 0) {
            pieces[0] = rest;
            np = 1;
        }
        while (rest.len > 0 and np < pieces.len) {
            const n = ui.p.breakAt(.small, rest, inner.w);
            pieces[np] = rest[0..n];
            np += 1;
            rest = std.mem.trimStart(u8, rest[n..], " ");
        }
        var k = np;
        while (k > 0) {
            k -= 1;
            if (skip > 0) {
                skip -= 1;
                continue;
            }
            if (count == rows or count == segs.len) break :outer;
            segs[count] = .{ .level = line.level, .text = pieces[k] };
            count += 1;
        }
    }
    // Scrolled further up than there is: back off to the top.
    g_log_scroll -= skip;

    var y = inner.y;
    var j = count;
    while (j > 0) {
        j -= 1;
        const col = switch (segs[j].level) {
            .info => kTextDim,
            .ok => kOk,
            .err => kWarn,
        };
        ui.p.text(.small, inner.x, y, col, segs[j].text);
        y += kLogLineH;
    }
}

fn modalRect(ui: *const Ui) Rect {
    const w: f32 = 480;
    const h: f32 = 172;
    return .{ .x = @round((ui.w - w) / 2), .y = @round((ui.h - h) / 2), .w = w, .h = h };
}

/// The modal's answers at its bottom right, the one that does it last.
/// Says which was pressed, if one was.
fn drawChoices(ui: *Ui, st: *State, labels: [2][]const u8) ?usize {
    const box = modalRect(ui);
    var pressed: ?usize = null;
    var x = box.x + box.w - 24;
    // Registered in index order, drawn right to left.
    for (labels, 0..) |label, i| {
        const w = ui.p.textWidth(.strong, label) + 40;
        x -= w;
        const r = Rect{ .x = x, .y = box.y + box.h - 24 - 36, .w = w, .h = 36 };
        x -= 12;
        const hit = ui.item(r, true);
        if (hit.focused) st.choice = i;
        if (hit.ring) ui.ring(r, r.h / 2, kSurface);
        // The start menu's answers: the picked one gold.
        if (hit.focused or hit.lit) {
            ui.p.box(r, r.h / 2, 1.5, kAccentHi, kButton);
            ui.p.textCentered(.strong, r.x + r.w / 2, r.y + 9, kOnAccent, label);
        } else {
            ui.p.box(r, r.h / 2, 1, kBorder, kSurface);
            ui.p.textCentered(.strong, r.x + r.w / 2, r.y + 9, kTextDim, label);
        }
        if (hit.pressed) pressed = i;
    }
    return pressed;
}

fn drawModal(ui: *Ui, st: *State) void {
    ui.p.fill(.{ .x = 0, .y = 0, .w = ui.w, .h = ui.h }, Color.hex(0x000000).alpha(150));
    const box = modalRect(ui);
    ui.p.shadow(box, 14);
    // A dark card edged in gold, with a diamond on its top like a clasp.
    ui.p.box(box, 14, 1, kAccent.alpha(110), Color.hex(0x0c161c));
    start_page.diamond(ui.p.r, box.x + box.w / 2, box.y, 5, kAccent);
    const x = box.x + 24;
    const title_y = box.y + 22;
    const body_y = box.y + 60;
    var buf: [96]u8 = undefined;
    switch (st.modal) {
        .leave => {
            // Up only while a job runs: leaving would cut it off halfway.
            const where = switch (st.leave orelse .menu) {
                .menu => "the start menu",
                .play => "the game",
                .quit => "quitting",
            };
            if (st.waiting) {
                ui.p.textEx(.subtitle, x, title_y, kAccentHi, kAccent, 2, "Finishing the job\u{2026}");
                ui.p.text(.body, x, body_y, kTextDim, std.fmt.bufPrint(&buf, "Then it's on to {s}. Esc stays here.", .{where}) catch "");
            } else {
                ui.p.textEx(.subtitle, x, title_y, kAccentHi, kAccent, 2, "A job is still running");
                ui.p.text(.body, x, body_y, kTextDim, std.fmt.bufPrint(&buf, "Leaving now would cut it off. Wait, then go to {s}?", .{where}) catch "");
                if (drawChoices(ui, st, .{ "Wait, Then Go", "Stay" })) |i| {
                    if (i == 0) st.waiting = true else st.stay(ui);
                }
            }
        },
        .none => {},
    }
}

fn initialState(alloc: std.mem.Allocator) State {
    var st = State{};
    // Sensible starting points: a ROM in the game's folder, and the asset
    // file where the game will look for it.
    for ([_][]const u8{ inGameDir(alloc, "zelda3.sfc"), "zelda3.sfc", inGameDir(alloc, "zelda3.smc"), "zelda3.smc" }) |p| {
        if (st.get(.rom).len == 0 and exists(alloc, p)) st.set(alloc, .rom, p);
    }
    st.set(alloc, .out, gameAssetPath(alloc));
    const folder = inGameDir(alloc, "zelda3_files");
    st.set(alloc, .folder, folder);
    st.set(alloc, .dialogue, std.fmt.allocPrint(alloc, "{s}{s}dialogue.txt", .{ folder, std.fs.path.sep_str }) catch "");
    return st;
}

/// Whether the asset file at `path` is there, whether it's the one this
/// version builds from the US ROM, and if not, whether the game loads it.
fn assetState(alloc: std.mem.Allocator, path: []const u8) AssetState {
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

/// Takes a dropped file or folder for whichever field it belongs in, by
/// what it is, and opens the page that uses it.
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
        st.open(.graphics);
    } else if (is(ext, ".zip") or (is_dir and st.screen == .msu)) {
        st.set(alloc, .msu, path);
        st.open(.msu);
    } else if (is(ext, ".sav")) {
        st.set(alloc, .snapshot, path);
        st.open(.extras);
    } else if (is(ext, ".txt")) {
        st.set(alloc, .dialogue, path);
        st.open(.extras);
    } else if (is_dir) {
        st.set(alloc, .folder, path);
    } else if (st.screen == .languages) {
        st.set(alloc, .lang_rom, path);
    } else {
        st.set(alloc, .rom, path);
        // A ROM dropped on a page without a ROM goes to the one that
        // builds from it.
        if (st.screen != .modding) st.open(.assets);
    }
}

/// A dialog's answer, into its field. A track picked for an MSU-1 pack
/// means the folder it's in.
fn picked(alloc: std.mem.Allocator, st: *State, field: Field, path: []const u8) void {
    if (field == .msu and !std.ascii.endsWithIgnoreCase(path, ".zip")) {
        st.set(alloc, .msu, std.fs.path.dirname(path) orelse path);
        return;
    }
    st.set(alloc, field, path);
}

fn drawFrame(ui: *Ui, alloc: std.mem.Allocator, st: *State, window: ?*c.SDL_Window) void {
    ui.begin();
    // Under a modal the window is still drawn, but only the modal takes input.
    ui.blocked = st.modal != .none;
    ui.night.night(ui.t, ui.w, ui.h, 0.5);
    // The sidebar first, so its entries keep their places in the focus order
    // whichever page is open.
    drawSidebar(ui, alloc, st);

    const left = kSideW + kPad;
    const pg = Page{ .x = left, .w = @min(kMaxPageW, ui.w - left - kPad), .bottom = ui.h - 28 };
    // The page's name in the start menu's gold, what it's for, and the gold
    // rule under both.
    ui.p.textEx(.headline, pg.x, 18, kAccentHi, start_page.kGoldDeep, 3, st.screen.label());
    var buf: [256]u8 = undefined;
    ui.p.text(.body, pg.x, 62, kTextDim, ui.p.fit(.body, st.screen.about(), pg.w, &buf));
    ui.night.goldRule(pg.x, 94, pg.w);

    const bottom = switch (st.screen) {
        .assets => drawAssets(ui, alloc, st, window, pg),
        .modding => drawModding(ui, alloc, st, window, pg),
        .graphics => drawGraphics(ui, alloc, st, window, pg),
        .music => drawMusic(ui, alloc, st, pg),
        .msu => drawMsu(ui, alloc, st, window, pg),
        .languages => drawLanguages(ui, alloc, st, window, pg),
        .extras => drawExtras(ui, alloc, st, window, pg),
    };
    if (st.screen != .graphics) drawLog(ui, .{ .x = pg.x, .y = bottom + 32, .w = pg.w, .h = pg.bottom - bottom - 32 });
    if (st.modal != .none) {
        ui.blocked = false;
        drawModal(ui, st);
    }
}

/// Draws one frame of a page into a BMP with no window, for looking at the
/// layout while working on it: `zelda3 tools gui-screenshot out.bmp [page]`,
/// the page being assets, modding, graphics, music, msu, languages or
/// extras.
/// `log` lines are fed through the real log first, so it shows populated;
/// ones like "@rom=path" set a field instead (any of the Field names),
/// "@pick=de,fr" ticks languages, "@sprites" ticks the sprite sheets,
/// "@watch" turns on rebuilding, "@picture=N" and "@song=N" pick from those
/// lists, "@focus=N" puts the focus on the Nth thing that can have it and
/// shows it as the keys would, "@busy=build" shows a job running,
/// "@modal=leave" the question leaving mid-job asks, "@us=path" takes path to
/// be a US ROM, "@scale=2" draws it as a Retina screen would, and
/// "@size=WxH" sizes the window.
pub fn screenshot(alloc: std.mem.Allocator, path: [:0]const u8, page_name: ?[]const u8, log_lines: []const [:0]const u8) !void {
    var scale: f32 = 1;
    var w: f32 = kWindowW;
    var h: f32 = kWindowH;
    for (log_lines) |line| {
        if (std.mem.startsWith(u8, line, "@scale=")) scale = std.fmt.parseFloat(f32, line[7..]) catch 1;
        if (std.mem.startsWith(u8, line, "@size=")) {
            var it = std.mem.splitScalar(u8, line[6..], 'x');
            w = std.fmt.parseFloat(f32, it.next() orelse "") catch w;
            h = std.fmt.parseFloat(f32, it.next() orelse "") catch h;
        }
    }
    const surface = c.SDL_CreateSurface(@intFromFloat(w * scale), @intFromFloat(h * scale), c.SDL_PIXELFORMAT_XRGB8888) orelse return error.SdlSurface;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    var night = Night.initFor(renderer, scale, draw.kToolStyles);
    defer night.deinit();
    const paint = &night.paint;
    var st = initialState(alloc);
    var ui = Ui{ .p = paint, .night = &night, .w = w, .h = h, .focus = kMaxItems, .t = 4 };
    if (page_name) |name| {
        st.screen = std.meta.stringToEnum(Screen, name) orelse .assets;
    }
    var picks: ?[]const u8 = null;
    // Settings first, then the log.
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
                ui.keys = true;
            } else if (std.mem.eql(u8, key, "busy")) {
                g_job = std.meta.stringToEnum(Job, value) orelse .build;
                g_job_running.store(true, .release);
            } else if (std.mem.eql(u8, key, "modal")) {
                st.modal = std.meta.stringToEnum(Modal, value) orelse .none;
                // Its second answer has the focus, as when it opens.
                ui.focus = 1;
            } else if (std.mem.eql(u8, key, "us")) {
                // A US ROM to build from, for a machine without one.
                st.set(alloc, .rom, value);
                st.rom_seen.appendSlice(std.heap.c_allocator, value) catch {};
                st.rom_kind = .us;
            } else if (std.meta.stringToEnum(Field, key)) |f| st.set(alloc, f, value);
        }
    }
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
    drawFrame(&ui, alloc, &st, null);
    _ = c.SDL_RenderPresent(renderer);
    if (!c.SDL_SaveBMP(surface, path.ptr)) return error.SaveFailed;
}

/// How many of the screen's pixels a point is, for the window where it is
/// now: 2 on a Retina screen, 1.5 on a Windows one at 150%.
fn windowScale(window: *c.SDL_Window) f32 {
    const s = c.SDL_GetWindowDisplayScale(window);
    return if (s > 0) s else 1;
}

/// The page last open, so coming back to the tools finds it again.
var g_last_screen: Screen = .assets;

/// Runs the tools in the start menu's window until they're closed, and says
/// where to go next. The window is the menu's: it comes in sized for the
/// tools and goes back to the menu as it was, render scale aside, which
/// the menu sets again.
pub fn runIn(alloc: std.mem.Allocator, window: *c.SDL_Window, renderer: *c.SDL_Renderer) Outcome {
    // The music page plays through SDL; the menu has no sound of its own.
    const audio = c.SDL_InitSubSystem(c.SDL_INIT_AUDIO);
    defer if (audio) c.SDL_QuitSubSystem(c.SDL_INIT_AUDIO);
    // Made once and kept: a file dialog can answer after the tools close.
    if (g_dialog_lock == null) g_dialog_lock = c.SDL_CreateMutex();
    if (g_log_lock == null) g_log_lock = c.SDL_CreateMutex();

    const arrow = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_DEFAULT);
    const hand = c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_POINTER);
    defer {
        if (arrow) |a| c.SDL_DestroyCursor(a);
        if (hand) |h| c.SDL_DestroyCursor(h);
    }

    var st = initialState(alloc);
    st.screen = g_last_screen;
    defer {
        g_last_screen = st.screen;
        st.tunes.drop(alloc);
        if (st.gfx.tex) |t| c.SDL_DestroyTexture(t);
        _ = c.SDL_SetCursor(c.SDL_GetDefaultCursor());
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

    var night = Night.initFor(renderer, windowScale(window), draw.kToolStyles);
    defer night.deinit();
    const paint = &night.paint;
    var ui = Ui{ .p = paint, .night = &night };
    var was_running = false;
    var cursor_hand = false;
    while (true) {
        // Told to go, and nothing's halfway through: go.
        if (st.leave) |to| if (!jobRunning()) return to;
        const now = c.SDL_GetTicks();
        ui.moved = false;
        ui.clicked = false;
        ui.confirm = false;
        ui.adjust = 0;
        var back = false;
        // Presses arrive as events so that a tap shorter than a frame still
        // counts; the poll below only decides when a held direction repeats.
        var tap_v: i32 = 0;
        var tap_h: i32 = 0;
        // The close button means back to the menu; the system's Quit, which
        // also follows a last window closing, means out.
        var closed = false;

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            // Mouse positions in points, as everything's laid out.
            _ = c.SDL_ConvertEventToRenderCoordinates(renderer, &event);
            switch (event.type) {
                c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    closed = true;
                    st.close(&ui, .menu);
                },
                c.SDL_EVENT_QUIT => if (!closed) st.close(&ui, .quit),
                c.SDL_EVENT_GAMEPAD_ADDED => pads.open(event.gdevice.which),
                c.SDL_EVENT_GAMEPAD_REMOVED => pads.close(event.gdevice.which),
                c.SDL_EVENT_MOUSE_MOTION => {
                    ui.mouse_x = event.motion.x;
                    ui.mouse_y = event.motion.y;
                    ui.moved = true;
                    ui.keys = false;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    ui.mouse_x = event.button.x;
                    ui.mouse_y = event.button.y;
                    ui.keys = false;
                    if (event.button.button == c.SDL_BUTTON_LEFT) ui.clicked = true;
                },
                c.SDL_EVENT_MOUSE_WHEEL => scrollLog(if (event.wheel.y > 0) 3 else if (event.wheel.y < 0) -3 else 0),
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
                        c.SDLK_RETURN, c.SDLK_SPACE => {
                            ui.confirm = true;
                            ui.keys = true;
                        },
                        c.SDLK_PAGEUP => scrollLog(8),
                        c.SDLK_PAGEDOWN => scrollLog(-8),
                        else => {},
                    }
                },
                c.SDL_EVENT_KEY_UP => _ = held.set(event.key.key, false),
                c.SDL_EVENT_GAMEPAD_BUTTON_UP => _ = held.setButton(event.gbutton.button, false),
                // The d-pad goes by position; the face buttons by the
                // letter printed on them.
                c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => {
                    _ = held.setButton(event.gbutton.button, true);
                    ui.keys = true;
                    switch (event.gbutton.button) {
                        c.SDL_GAMEPAD_BUTTON_START => ui.confirm = true,
                        c.SDL_GAMEPAD_BUTTON_DPAD_UP => tap_v -= 1,
                        c.SDL_GAMEPAD_BUTTON_DPAD_DOWN => tap_v += 1,
                        c.SDL_GAMEPAD_BUTTON_DPAD_LEFT => tap_h -= 1,
                        c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT => tap_h += 1,
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
                if (move_v != 0) ui.move(0, @floatFromInt(move_v));
                // A chooser keeps left and right for itself.
                if (move_h != 0) {
                    if (ui.focusAdjusts()) {
                        ui.adjust = move_h;
                        ui.keys = true;
                    } else ui.move(@floatFromInt(move_h), 0);
                }
                if (back) st.close(&ui, .menu);
            },
            .leave => {
                if (move_h != 0) ui.move(@floatFromInt(move_h), 0);
                if (back) st.stay(&ui);
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

        // The window may have moved to a screen with other pixels, or been
        // resized.
        paint.setScale(windowScale(window));
        ui.t = @as(f32, @floatFromInt(now)) / 1000;
        var pw: c_int = 0;
        var ph: c_int = 0;
        _ = c.SDL_GetCurrentRenderOutputSize(renderer, &pw, &ph);
        ui.w = @as(f32, @floatFromInt(pw)) / paint.scale;
        ui.h = @as(f32, @floatFromInt(ph)) / paint.scale;

        drawFrame(&ui, alloc, &st, window);
        _ = c.SDL_RenderPresent(renderer);
        if (ui.over_any != cursor_hand) {
            cursor_hand = ui.over_any;
            _ = c.SDL_SetCursor(if (cursor_hand) hand else arrow);
        }
    }
}
