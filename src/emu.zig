//! A whole SNES, running a ROM as it is: for randomizer seeds, which change
//! the game's own code, so only the ROM itself can play them exactly.
//!
//! The port never runs through here. This is the emulator the port is checked
//! against (LakeSnes, by way of upstream), put back together as a complete
//! console: the cpu, ppu, dma and sound chips stepped together a master cycle
//! at a time by snes_runFrame.
const std = @import("std");
const snes_pkg = @import("snes");
const snes_mod = snes_pkg.snes;
const ppu_mod = snes_pkg.ppu;
const dsp_mod = snes_pkg.dsp;
const fileio = @import("fileio.zig");

const Snes = snes_pkg.snes_types.Snes;
const Ppu = snes_pkg.ppu_types.Ppu;
const Apu = snes_pkg.apu.Apu;
const Cart = snes_pkg.cart.Cart;
const Input = snes_pkg.input.Input;

pub const kWidth = 256;
pub const kHeight = 224;

pub const Console = struct {
    snes: *Snes,
    ram: *[0x20000]u8,
    /// Where the battery-backed save lives, beside the ROM as .srm.
    save_path: [:0]u8,
    /// The save ram as last written to disk, to only write when it changes.
    saved: []u8,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *Console) void {
        self.flushSave();
        snes_mod.snes_free(self.snes);
        self.alloc.destroy(self.ram);
        self.alloc.free(self.save_path);
        self.alloc.free(self.saved);
        self.* = undefined;
    }

    /// Loads a ROM file and powers the console on, with its save if there
    /// is one.
    pub fn open(alloc: std.mem.Allocator, rom_path: [:0]const u8) !Console {
        const rom = try fileio.readWholeFile(alloc, rom_path.ptr);
        defer alloc.free(rom);
        const ram = try alloc.create([0x20000]u8);
        errdefer alloc.destroy(ram);
        @memset(ram, 0);
        const s = snes_mod.snes_init(ram);
        errdefer snes_mod.snes_free(s);
        snes_mod.g_accurate_timing = true;
        snes_pkg.cpu.g_real_brk = true;
        snes_pkg.ppu.g_lenient = true;
        if (!snes_pkg.snes_other.snes_loadRom(s, rom.ptr, @intCast(rom.len))) return error.NotARom;

        const ext = std.fs.path.extension(rom_path);
        const save_path = try std.fmt.allocPrintSentinel(alloc, "{s}.srm", .{rom_path[0 .. rom_path.len - ext.len]}, 0);
        errdefer alloc.free(save_path);
        var self = Console{ .snes = s, .ram = ram, .save_path = save_path, .saved = &.{}, .alloc = alloc };
        const sram = self.saveRam();
        if (fileio.readWholeFile(alloc, save_path.ptr)) |data| {
            defer alloc.free(data);
            const n = @min(data.len, sram.len);
            @memcpy(sram[0..n], data[0..n]);
        } else |_| {}
        self.saved = try alloc.dupe(u8, sram);
        return self;
    }

    fn cart(self: *Console) *Cart {
        return @ptrCast(@alignCast(self.snes.cart.?));
    }

    fn ppu(self: *Console) *Ppu {
        return @ptrCast(@alignCast(self.snes.ppu.?));
    }

    /// The cartridge's battery-backed ram.
    pub fn saveRam(self: *Console) []u8 {
        const c = self.cart();
        const ram = c.ram orelse return &.{};
        return ram[0..c.ramSize];
    }

    /// The console's work ram ($7e0000-$7fffff), for the item tracker.
    pub fn workRam(self: *Console) *const [0x20000]u8 {
        return self.ram;
    }

    /// Runs one frame with `buttons` held (the port's joypad bit order, which
    /// is the controller's own), drawing it into `pixels`: kWidth x kHeight,
    /// 0x00RRGGBB, `pitch` bytes a row.
    pub fn runFrame(self: *Console, buttons: u16, pixels: [*]u8, pitch: usize) void {
        const in1: *Input = @ptrCast(@alignCast(self.snes.input1.?));
        in1.currentState = buttons;
        const p = self.ppu();
        // No widescreen margins: this draws exactly what the console does.
        p.extraLeftRight = 0;
        ppu_mod.PpuSetExtraSideSpace(p, 0, 0, 0);
        ppu_mod.PpuBeginDrawing(p, pixels, pitch, snes_pkg.ppu_types.kPpuRenderFlags_NewRenderer);
        snes_mod.snes_runFrame(self.snes);
    }

    /// The frame's sound, resampled to `samples` per frame.
    pub fn audio(self: *Console, out: [*]i16, samples: c_int, channels: c_int) void {
        const apu: *Apu = @ptrCast(@alignCast(self.snes.apu.?));
        dsp_mod.dsp_getSamples(@ptrCast(@alignCast(apu.dsp.?)), out, samples, channels);
    }

    pub fn reset(self: *Console) void {
        snes_mod.snes_reset(self.snes, false);
    }

    /// Writes the save ram to disk if the game has changed it.
    pub fn flushSave(self: *Console) void {
        const sram = self.saveRam();
        if (sram.len == 0 or std.mem.eql(u8, sram, self.saved)) return;
        fileio.writeWholeFile(self.save_path.ptr, sram) catch |e| {
            std.debug.print("Could not save {s}: {s}\n", .{ self.save_path, @errorName(e) });
            return;
        };
        @memcpy(self.saved, sram);
    }
};

/// What a ROM is, going by its header: a randomizer seed, the Japanese 1.0
/// the randomizer starts from, or something else.
pub const RomKind = enum { randomizer, japanese, other };

pub fn romKind(rom: []const u8) RomKind {
    const off: usize = if (rom.len & 0x3ff == 0x200) 0x200 else 0;
    if (rom.len < off + 0x8000) return .other;
    const title = rom[off + 0x7fc0 ..][0..21];
    // The randomizer names every seed "VT <hash>".
    if (std.mem.startsWith(u8, title, "VT ")) return .randomizer;
    if (std.mem.startsWith(u8, title, "ZELDANODENSETSU")) return .japanese;
    return .other;
}

test "seeds are told apart by their header" {
    var rom = [_]u8{0} ** 0x8000;
    @memcpy(rom[0x7fc0..][0..13], "VT mykaDL4lMQ");
    try std.testing.expectEqual(RomKind.randomizer, romKind(&rom));
    @memcpy(rom[0x7fc0..][0..15], "ZELDANODENSETSU");
    try std.testing.expectEqual(RomKind.japanese, romKind(&rom));
    try std.testing.expectEqual(RomKind.other, romKind(rom[0..100]));
}
