//! Port of snes/cart.c: LoROM/HiROM address decoding.
const std = @import("std");
const snes_types = @import("snes_types.zig");

const Snes = snes_types.Snes;
const SaveLoadFunc = snes_types.SaveLoadFunc;

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn memset(dst: [*]u8, val: c_int, n: usize) [*]u8;
extern fn memcpy(dst: [*]u8, src: [*]const u8, n: usize) [*]u8;

/// Must match `struct Cart` in cart.h.
pub const Cart = extern struct {
    snes: ?*Snes,
    @"type": u8,

    rom: ?[*]u8,
    romSize: u32,
    ram: ?[*]u8,
    ramSize: u32,
};

pub export fn cart_init(snes: ?*Snes) callconv(.c) *Cart {
    const cart: *Cart = @ptrCast(@alignCast(malloc(@sizeOf(Cart)).?));
    cart.snes = snes;
    cart.@"type" = 0;
    cart.rom = null;
    cart.romSize = 0;
    cart.ramSize = 0x2000;
    cart.ram = @ptrCast(malloc(cart.ramSize));
    return cart;
}

pub export fn cart_free(cart: *Cart) callconv(.c) void {
    free(cart);
}

pub export fn cart_reset(cart: *Cart) callconv(.c) void {
    if (cart.ramSize > 0) {
        if (cart.ram) |ram| _ = memset(ram, 0, cart.ramSize); // for now
    }
}

pub export fn cart_saveload(cart: *Cart, func: *const SaveLoadFunc, ctx: ?*anyopaque) callconv(.c) void {
    func(ctx, @ptrCast(cart.ram), cart.ramSize);
}

pub export fn cart_load(cart: *Cart, kind: c_int, rom: [*]const u8, romSize: c_int, ramSize: c_int) callconv(.c) void {
    cart.@"type" = @intCast(kind);
    if (cart.rom) |old| free(old);
    const size: usize = @intCast(romSize);
    cart.rom = @ptrCast(malloc(size));
    cart.romSize = @intCast(romSize);
    std.debug.assert(ramSize == cart.ramSize);
    _ = memset(cart.ram.?, 0, @intCast(ramSize));
    cart.ramSize = @intCast(ramSize);
    _ = memcpy(cart.rom.?, rom, size);
}

pub export fn cart_read(cart: *Cart, bank: u8, adr: u16) callconv(.c) u8 {
    if (cart.@"type" == 1)
        return cart_readLorom(cart, bank, adr);

    return switch (cart.@"type") {
        0 => cart.snes.?.openBus,
        1, 2 => cart_readHirom(cart, bank, adr),
        else => cart.snes.?.openBus,
    };
}

pub export fn cart_write(cart: *Cart, bank: u8, adr: u16, val: u8) callconv(.c) void {
    switch (cart.@"type") {
        0 => {},
        1 => cart_writeLorom(cart, bank, adr, val),
        2 => cart_writeHirom(cart, bank, adr, val),
        else => {},
    }
}

fn cart_readLorom(cart: *Cart, bank: u8, adr: u16) u8 {
    if (adr >= 0x8000) {
        // adr 8000-ffff in all banks or all addresses in banks 40-7f and c0-ff
        return cart.rom.?[(@as(u32, bank) << 15 | (adr & 0x7fff)) & (cart.romSize -% 1)];
    }
    if (((bank >= 0x70 and bank < 0x7e) or bank >= 0xf0) and adr < 0x8000 and cart.ramSize > 0) {
        // banks 70-7e and f0-ff, adr 0000-7fff
        return cart.ram.?[(@as(u32, bank & 0xf) << 15 | adr) & (cart.ramSize -% 1)];
    }
    if (bank & 0x40 != 0) {
        // adr 8000-ffff in all banks or all addresses in banks 40-7f and c0-ff
        return cart.rom.?[(@as(u32, bank) << 15 | (adr & 0x7fff)) & (cart.romSize -% 1)];
    }
    return cart.snes.?.openBus;
}

fn cart_writeLorom(cart: *Cart, bank: u8, adr: u16, val: u8) void {
    if (((bank >= 0x70 and bank < 0x7e) or bank > 0xf0) and adr < 0x8000 and cart.ramSize > 0) {
        // banks 70-7e and f0-ff, adr 0000-7fff
        cart.ram.?[(@as(u32, bank & 0xf) << 15 | adr) & (cart.ramSize -% 1)] = val;
    }
}

fn cart_readHirom(cart: *Cart, bank_in: u8, adr: u16) u8 {
    const bank = bank_in & 0x7f;
    if (bank < 0x40 and adr >= 0x6000 and adr < 0x8000 and cart.ramSize > 0) {
        // banks 00-3f and 80-bf, adr 6000-7fff
        return cart.ram.?[(@as(u32, bank & 0x3f) << 13 | (adr & 0x1fff)) & (cart.ramSize -% 1)];
    }
    if (adr >= 0x8000 or bank >= 0x40) {
        // adr 8000-ffff in all banks or all addresses in banks 40-7f and c0-ff
        return cart.rom.?[(@as(u32, bank & 0x3f) << 16 | adr) & (cart.romSize -% 1)];
    }
    return cart.snes.?.openBus;
}

fn cart_writeHirom(cart: *Cart, bank_in: u8, adr: u16, val: u8) void {
    const bank = bank_in & 0x7f;
    if (bank < 0x40 and adr >= 0x6000 and adr < 0x8000 and cart.ramSize > 0) {
        // banks 00-3f and 80-bf, adr 6000-7fff
        cart.ram.?[(@as(u32, bank & 0x3f) << 13 | (adr & 0x1fff)) & (cart.ramSize -% 1)] = val;
    }
}

const testing = std.testing;

/// A cart backed by fixed buffers, so the decoding can be checked without libc.
fn testCart(kind: u8, rom: []u8, ram: []u8, snes: *Snes) Cart {
    return .{
        .snes = snes,
        .@"type" = kind,
        .rom = rom.ptr,
        .romSize = @intCast(rom.len),
        .ram = ram.ptr,
        .ramSize = @intCast(ram.len),
    };
}

test "LoROM maps bank:8000 to consecutive rom halves" {
    var rom = [_]u8{0} ** 0x10000; // two 32k banks
    var ram = [_]u8{0} ** 0x2000;
    var snes = std.mem.zeroes(Snes);
    rom[0] = 0xaa;
    rom[0x7fff] = 0xbb;
    rom[0x8000] = 0xcc;
    var cart = testCart(1, &rom, &ram, &snes);

    try testing.expectEqual(@as(u8, 0xaa), cart_read(&cart, 0x00, 0x8000));
    try testing.expectEqual(@as(u8, 0xbb), cart_read(&cart, 0x00, 0xffff));
    try testing.expectEqual(@as(u8, 0xcc), cart_read(&cart, 0x01, 0x8000));
}

test "LoROM reads below 8000 come from open bus outside the sram banks" {
    var rom = [_]u8{0} ** 0x10000;
    var ram = [_]u8{0} ** 0x2000;
    var snes = std.mem.zeroes(Snes);
    snes.openBus = 0x42;
    var cart = testCart(1, &rom, &ram, &snes);
    try testing.expectEqual(@as(u8, 0x42), cart_read(&cart, 0x00, 0x1234));
}

test "LoROM sram is readable and writable in banks 70-7d" {
    var rom = [_]u8{0} ** 0x10000;
    var ram = [_]u8{0} ** 0x2000;
    var snes = std.mem.zeroes(Snes);
    var cart = testCart(1, &rom, &ram, &snes);

    cart_write(&cart, 0x70, 0x0010, 0x99);
    try testing.expectEqual(@as(u8, 0x99), ram[0x10]);
    try testing.expectEqual(@as(u8, 0x99), cart_read(&cart, 0x70, 0x0010));
    // Bank 7e is system ram, not cart sram.
    cart_write(&cart, 0x7e, 0x0011, 0x77);
    try testing.expectEqual(@as(u8, 0), ram[0x11]);
}

test "HiROM maps banks to 64k windows and sram to 6000-7fff" {
    var rom = [_]u8{0} ** 0x20000; // two 64k banks
    var ram = [_]u8{0} ** 0x2000;
    var snes = std.mem.zeroes(Snes);
    snes.openBus = 0x42;
    rom[0x8000] = 0x11;
    rom[0x10000] = 0x22;
    var cart = testCart(2, &rom, &ram, &snes);

    try testing.expectEqual(@as(u8, 0x11), cart_read(&cart, 0x00, 0x8000));
    // Only banks 40-7f (and c0-ff) expose a full 64k window; in banks 00-3f
    // the low half is not cart space at all.
    try testing.expectEqual(@as(u8, 0x22), cart_read(&cart, 0x41, 0x0000));
    try testing.expectEqual(@as(u8, 0x42), cart_read(&cart, 0x01, 0x0000));
    cart_write(&cart, 0x00, 0x6000, 0x55);
    try testing.expectEqual(@as(u8, 0x55), ram[0]);
    try testing.expectEqual(@as(u8, 0x55), cart_read(&cart, 0x00, 0x6000));
    // Below 6000 in the low banks there is nothing mapped.
    try testing.expectEqual(@as(u8, 0x42), cart_read(&cart, 0x00, 0x1000));
}

test "an unloaded cart reads open bus" {
    var rom = [_]u8{0} ** 0x100;
    var ram = [_]u8{0} ** 0x100;
    var snes = std.mem.zeroes(Snes);
    snes.openBus = 0x42;
    var cart = testCart(0, &rom, &ram, &snes);
    try testing.expectEqual(@as(u8, 0x42), cart_read(&cart, 0x00, 0x8000));
    cart_write(&cart, 0x70, 0x0000, 0x99); // must not fault or store
    try testing.expectEqual(@as(u8, 0), ram[0]);
}

test "Cart layout matches cart.h" {
    // Offsets taken from the C compiler on this target.
    if (@sizeOf(*anyopaque) != 8) return error.SkipZigTest;
    try testing.expectEqual(48, @sizeOf(Cart));
    try testing.expectEqual(8, @offsetOf(Cart, "type"));
    try testing.expectEqual(16, @offsetOf(Cart, "rom"));
    try testing.expectEqual(24, @offsetOf(Cart, "romSize"));
    try testing.expectEqual(32, @offsetOf(Cart, "ram"));
    try testing.expectEqual(40, @offsetOf(Cart, "ramSize"));
}
