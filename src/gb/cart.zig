const std = @import("std");
const assert = std.debug.assert;

pub const MaxROMByteSize = 8 * 1024 * 1024;
pub const ROMBankSizeBytes = 16 * 1024;
pub const RAMBankSizeBytes = 8 * 1024;

pub const CartState = struct {
    rom: []const u8, // Borrowed from create_cart_state
    rom_bank_count: u10,
    ram_bank_count: u5,
    mbc_state: MBC_State,
};

pub fn create_cart_state(allocator: std.mem.Allocator, cart_rom_bytes: []const u8) !CartState {
    const cart_header = extract_header_from_rom(cart_rom_bytes);

    const rom_bank_count = get_rom_bank_count_from_header(cart_header);
    const rom_size_bytes = @as(usize, rom_bank_count) * ROMBankSizeBytes;
    assert(cart_rom_bytes.len == rom_size_bytes);

    const ram_bank_count = get_ram_bank_count_from_header(cart_header);
    const ram_size_bytes = @as(usize, ram_bank_count) * RAMBankSizeBytes;

    const properties = get_cart_properties(cart_header.cart_type);
    assert(properties.has_ram == (ram_bank_count != 0));

    return CartState{
        .rom = cart_rom_bytes,
        .rom_bank_count = rom_bank_count,
        .ram_bank_count = ram_bank_count,
        .mbc_state = try create_mbc_state(allocator, properties, ram_size_bytes, rom_size_bytes),
    };
}

pub fn destroy_cart_state(allocator: std.mem.Allocator, cart: *CartState) void {
    destroy_mbc_state(allocator, cart.mbc_state);
}

const MBCType = enum {
    ROMOnly,
    MBC1,
    MBC2,
};

const MBC_State = union(MBCType) {
    ROMOnly,
    MBC1: MBC1_State,
    MBC2: MBC2_State,
};

// Max 2 MiB ROM = 128 banks + optional Max 32 KiB external banked RAM
const MBC1_State = struct {
    current_rom_bank: u5 = 1,
    current_ram_bank: u2 = 0,
    rom_address_mask: u21,
    ram: []u8,
    ram_enable: bool = false,
    banking_mode: enum(u1) {
        Simple = 0,
        Advanced = 1,
    } = .Simple,
};

// Max 256 kiB ROM = 16 banks + 512x4 bits internal RAM
const MBC2_State = struct {
    current_rom_bank: u8 = 1,
    ram_enable: bool = false,
    nibble_ram: []u4,
};

fn create_mbc_state(allocator: std.mem.Allocator, properties: CartridgeProperties, ram_size_bytes: usize, rom_size_bytes: usize) !MBC_State {
    switch (properties.mbc_type) {
        .ROMOnly => {
            return .{ .ROMOnly = undefined };
        },
        .MBC1 => {
            const ram = try allocator.alloc(u8, ram_size_bytes);
            errdefer allocator.free(ram);

            return .{ .MBC1 = MBC1_State{
                .rom_address_mask = @intCast(rom_size_bytes - 1),
                .ram = ram,
            } };
        },
        .MBC2 => {
            const nibble_ram = try allocator.alloc(u4, 512);
            errdefer allocator.free(nibble_ram);

            return .{ .MBC2 = MBC2_State{
                .nibble_ram = nibble_ram,
            } };
        },
    }
}

fn destroy_mbc_state(allocator: std.mem.Allocator, mbc_state: MBC_State) void {
    switch (mbc_state) {
        .ROMOnly => {},
        .MBC1 => |mbc1| {
            allocator.free(mbc1.ram);
        },
        .MBC2 => |mbc2| {
            allocator.free(mbc2.nibble_ram);
        },
    }
}

pub fn load_rom_u8_bank0(cart: *const CartState, address: u14) u8 {
    switch (cart.mbc_state) {
        .ROMOnly, .MBC2 => {
            return cart.rom[address];
        },
        .MBC1 => |mbc1| {
            const rom_address = get_mbc1_rom_address(address, mbc1, 0);
            return cart.rom[rom_address];
        },
    }
}

// NOTE: address starts at zero
pub fn load_rom_u8_bankX(cart: *const CartState, address: u14) u8 {
    switch (cart.mbc_state) {
        .ROMOnly => {
            return cart.rom[@as(u15, address) + ROMBankSizeBytes];
        },
        .MBC1 => |mbc1| {
            const rom_address = get_mbc1_rom_address(address, mbc1, mbc1.current_rom_bank);
            return cart.rom[rom_address];
        },
        .MBC2 => |mbc2| {
            const banked_address = @as(u21, address) + @as(u21, mbc2.current_rom_bank) * ROMBankSizeBytes; // FIXME
            return cart.rom[banked_address];
        },
    }
}

pub fn store_rom_u8(cart: *CartState, address: u15, value: u8) void {
    switch (cart.mbc_state) {
        .ROMOnly => {
            // Avoid writing here
            // Unfortunately it's common for official games to do, so avoid asserting for now.
            // https://www.reddit.com/r/EmuDev/comments/5ht388/gb_why_does_tetris_write_to_the_rom/
            assert(address == 0x2000);
        },
        .MBC1 => |*mbc1| switch (address) {
            0x0000...0x1fff => { // RAM Enable
                mbc1.ram_enable = @as(u4, @truncate(value)) == 0xa;
            },
            0x2000...0x3fff => { // ROM Bank number
                const bank_number: u5 = @truncate(@max(value, 1));
                mbc1.current_rom_bank = bank_number;
            },
            0x4000...0x5fff => { // RAM Bank number
                const bank_number: u2 = @truncate(value);
                mbc1.current_ram_bank = bank_number;
            },
            0x6000...0x7fff => { // Banking mode
                const mode: u1 = @truncate(value);
                mbc1.banking_mode = @enumFromInt(mode);
            },
        },
        .MBC2 => |*mbc2| switch (address) {
            0x0000...0x3fff => {
                const rom_control = (address & 0x10) != 0;

                if (rom_control) {
                    // Write ROM Bank number
                    const bank_number: u4 = @truncate(@max(value % cart.rom_bank_count, 1)); // FIXME Modulo
                    mbc2.current_rom_bank = bank_number;
                } else {
                    mbc2.ram_enable = value == 0x0a;
                }
            },
            0x4000...0x7fff => {},
        },
    }
}

pub fn load_external_ram_u8(cart: *const CartState, address: u13) u8 {
    switch (cart.mbc_state) {
        .ROMOnly => unreachable,
        .MBC1 => |mbc1| {
            if (mbc1.ram_enable) {
                assert(cart.ram_bank_count != 0);

                const ram_address = get_mbc1_ram_address(address, mbc1);
                return mbc1.ram[ram_address];
            } else {
                return 0xff;
            }
        },
        .MBC2 => |mbc2| {
            assert(mbc2.ram_enable);
            return mbc2.nibble_ram[address];
        },
    }
}

pub fn store_external_ram_u8(cart: *CartState, address: u13, value: u8) void {
    switch (cart.mbc_state) {
        .ROMOnly => unreachable,
        .MBC1 => |mbc1| {
            if (mbc1.ram_enable) {
                assert(cart.ram_bank_count != 0);

                const ram_address = get_mbc1_ram_address(address, mbc1);
                mbc1.ram[ram_address] = value;
            }
        },
        .MBC2 => |mbc2| {
            assert(mbc2.ram_enable);
            mbc2.nibble_ram[address] = @truncate(value); // FIXME Bounds
        },
    }
}

fn get_mbc1_rom_address(address: u14, mbc1: MBC1_State, bank_index: u5) u21 {
    // https://gbdev.io/pandocs/MBC1.html#addressing-diagrams
    const MBC1ROMAddressHelper = packed struct {
        base_addr: u14,
        bank_index: u5,
        extended: u2,
    };

    const rom_address_helper = MBC1ROMAddressHelper{
        .base_addr = address,
        .bank_index = bank_index,
        .extended = if (mbc1.banking_mode == .Advanced) mbc1.current_ram_bank else 0,
    };

    const rom_address: u21 = @bitCast(rom_address_helper);
    return rom_address & mbc1.rom_address_mask;
}

fn get_mbc1_ram_address(address: u13, mbc1: MBC1_State) u15 {
    // https://gbdev.io/pandocs/MBC1.html#addressing-diagrams
    const MBC1RAMAddressHelper = packed struct {
        base_addr: u13,
        bank_index: u2,
    };

    const ram_address_helper = MBC1RAMAddressHelper{
        .base_addr = address,
        .bank_index = mbc1.current_ram_bank,
    };

    const ram_address: u15 = @bitCast(ram_address_helper);
    return ram_address; // FIXME wrap?
}

pub const CartridgeProperties = struct {
    mbc_type: MBCType,
    has_ram: bool = false,
    has_battery: bool = false,
    has_timer: bool = false,
    has_rumble: bool = false,
};

fn get_cart_properties(cart_type: CardridgeType) CartridgeProperties {
    return switch (cart_type) {
        .ROM_ONLY => .{ .mbc_type = .ROMOnly },
        .MBC1 => .{ .mbc_type = .MBC1 },
        .MBC1_RAM => .{ .mbc_type = .MBC1, .has_ram = true },
        .MBC1_RAM_BATTERY => .{ .mbc_type = .MBC1, .has_ram = true, .has_battery = true },
        .MBC2 => .{ .mbc_type = .MBC2 },
        .MBC2_BATTERY => .{ .mbc_type = .MBC2, .has_battery = true },
        //.ROM_RAM = 0x08,
        //.ROM_RAM_BATTERY = 0x09,
        //.MMM01 = 0x0B,
        //.MMM01_RAM = 0x0C,
        //.MMM01_RAM_BATTERY = 0x0D,
        //.MBC3_TIMER_BATTERY => .{ .mbc_type = .MBC3, .has_battery = true, .has_timer = true },
        //.MBC3_TIMER_RAM_BATTERY => .{ .mbc_type = .MBC3, .has_ram = true, .has_battery = true, .has_timer = true },
        //.MBC3 => .{ .mbc_type = .MBC3 },
        //.MBC3_RAM => .{ .mbc_type = .MBC3, .has_ram = true },
        //.MBC3_RAM_BATTERY => .{ .mbc_type = .MBC3, .has_ram = true, .has_battery = true },
        //.MBC5 => .{ .mbc_type = .MBC5 },
        //.MBC5_RAM => .{ .mbc_type = .MBC5, .has_ram = true },
        //.MBC5_RAM_BATTERY => .{ .mbc_type = .MBC5, .has_ram = true, .has_battery = true },
        //.MBC5_RUMBLE => .{ .mbc_type = .MBC5, .has_rumble = true },
        //.MBC5_RUMBLE_RAM => .{ .mbc_type = .MBC5, .has_rumble = true, .has_ram = true },
        //.MBC5_RUMBLE_RAM_BATTERY => .{ .mbc_type = .MBC5, .has_rumble = true, .has_ram = true, .has_battery = true },
        //.MBC6 = 0x20,
        //.MBC7_SENSOR_RUMBLE_RAM_BATTERY = 0x22,
        //.POCKET_CAMERA = 0xFC,
        //.BANDAI_TAMA5 = 0xFD,
        //.HuC3 = 0xFE,
        //.HuC1_RAM_BATTERY = 0xFF,
        else => unreachable,
    };
}

const CardridgeType = enum(u8) {
    ROM_ONLY = 0x00,
    MBC1 = 0x01,
    MBC1_RAM = 0x02,
    MBC1_RAM_BATTERY = 0x03,
    MBC2 = 0x05,
    MBC2_BATTERY = 0x06,
    ROM_RAM = 0x08,
    ROM_RAM_BATTERY = 0x09,
    MMM01 = 0x0B,
    MMM01_RAM = 0x0C,
    MMM01_RAM_BATTERY = 0x0D,
    MBC3_TIMER_BATTERY = 0x0F,
    MBC3_TIMER_RAM_BATTERY = 0x10,
    MBC3 = 0x11,
    MBC3_RAM = 0x12,
    MBC3_RAM_BATTERY = 0x13,
    MBC5 = 0x19,
    MBC5_RAM = 0x1A,
    MBC5_RAM_BATTERY = 0x1B,
    MBC5_RUMBLE = 0x1C,
    MBC5_RUMBLE_RAM = 0x1D,
    MBC5_RUMBLE_RAM_BATTERY = 0x1E,
    MBC6 = 0x20,
    MBC7_SENSOR_RUMBLE_RAM_BATTERY = 0x22,
    POCKET_CAMERA = 0xFC,
    BANDAI_TAMA5 = 0xFD,
    HuC3 = 0xFE,
    HuC1_RAM_BATTERY = 0xFF,
};

const LogoSizeBytes = 48;
const CartHeaderOffsetBytes = 0x100;
const CartHeaderSizeBytes = 0x50;

const CartHeader = packed struct {
    _unused0: u32, // 0x00
    //logo: [LogoSizeBytes]u8, // 0x04
    _logo0: u32,
    _logo1: u32,
    _logo2: u32,
    _logo3: u32,
    _logo10: u32,
    _logo11: u32,
    _logo12: u32,
    _logo13: u32,
    _logo20: u32,
    _logo21: u32,
    _logo22: u32,
    _logo23: u32,
    //title: [16]u8, // 0x34
    _title0: u32,
    _title1: u32,
    _title2: u32,
    _title3: u32,
    new_licensee_code_a: u8, // 0x44
    new_licensee_code_b: u8, // 0x45
    sgb_flag: u8, // 0x46
    cart_type: CardridgeType, // 0x47
    rom_size: u8, // 0x48
    ram_size: u8, // 0x49
    destination_code: u8, // 0x4a
    old_licensee_code: u8,
    mask_rom_version: u8,
    header_checksum: u8,
    global_checksum: u16,
};

fn extract_header_from_rom(cart_rom_bytes: []const u8) CartHeader {
    assert(cart_rom_bytes.len >= CartHeaderOffsetBytes + CartHeaderSizeBytes);

    var header: CartHeader = undefined;
    const header_bytes = std.mem.asBytes(&header);

    std.mem.copyForwards(u8, header_bytes, cart_rom_bytes[CartHeaderOffsetBytes .. CartHeaderOffsetBytes + CartHeaderSizeBytes]);

    return header;
}

// https://gbdev.io/pandocs/The_Cartridge_Header.html#0148--rom-size
fn get_rom_bank_count_from_header(cart_header: CartHeader) u10 {
    return switch (cart_header.rom_size) {
        0...8 => |value| @as(u10, 1) << @intCast(value + 1),
        else => unreachable,
    };
}

// https://gbdev.io/pandocs/The_Cartridge_Header.html#0149--ram-size
fn get_ram_bank_count_from_header(cart_header: CartHeader) u5 {
    return switch (cart_header.ram_size) {
        0 => 0,
        2 => 1,
        3 => 4,
        4 => 16,
        5 => 8,
        else => unreachable,
    };
}

comptime {
    assert(@offsetOf(CartHeader, "_logo0") == 0x04);
    assert(@offsetOf(CartHeader, "_title0") == 0x34);
    assert(@offsetOf(CartHeader, "new_licensee_code_a") == 0x44);
    assert(@offsetOf(CartHeader, "sgb_flag") == 0x46);
    assert(@offsetOf(CartHeader, "cart_type") == 0x47);
    assert(@sizeOf(CartHeader) == CartHeaderSizeBytes);
}

const NintendoLogoBitmap = [LogoSizeBytes]u8{
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
};
