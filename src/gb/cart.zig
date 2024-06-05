const std = @import("std");

pub const LogoSizeBytes = 48;
pub const CartHeaderOffsetBytes = 0x100;
pub const CartHeaderSizeBytes = 0x50;

pub const MaxROMByteSize = 8 * 1024 * 1024;

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
    std.debug.assert(cart_rom_bytes.len >= CartHeaderOffsetBytes + CartHeaderSizeBytes);

    var header: CartHeader = undefined;
    const header_bytes: *[CartHeaderSizeBytes]u8 = @ptrCast(&header);

    std.mem.copyForwards(u8, header_bytes, cart_rom_bytes[CartHeaderOffsetBytes .. CartHeaderOffsetBytes + CartHeaderSizeBytes]);

    return header;
}

pub const CartState = struct {
    rom: []const u8, // Borrowed from create_state
    properties: CardridgeProperties, // Should get const?
    current_rom_bank: u8 = 1,
    ram_enable: bool = false,
    current_ram_bank: u8 = 0,
};

pub fn create_cart_state(cart_rom_bytes: []const u8) CartState {
    const cart_header = extract_header_from_rom(cart_rom_bytes);
    const cart_properties = get_cart_properties(cart_header.cart_type);

    // std.debug.assert(cart_properties.has_battery == false);
    std.debug.assert(cart_properties.has_ram == false);

    if (cart_properties.mbc_type == .None) {
        std.debug.assert(cart_rom_bytes.len == 32 * 1024);
    } else if (cart_properties.mbc_type == .MBC1) {
        std.debug.assert(cart_rom_bytes.len == (@as(u32, 1) << @as(u5, @intCast(cart_header.rom_size))) * 32 * 1024);
    }

    return CartState{
        .rom = cart_rom_bytes,
        .properties = cart_properties,
    };
}

pub fn destroy_cart_state(cart: CartState) void {
    switch (cart.properties.mbc_type) {
        .None => {},
        .MBC1 => {},
        .MBC2 => {},
        .MBC3 => {},
        .MBC5 => {},
    }
}

pub const MBCType = enum {
    None, // 32 kiB ROM
    MBC1, // Max 2 MiB ROM = 128 banks + optional Max 32 KiB external banked RAM
    MBC2, // Max 256 kiB ROM = 16 banks + 512x4 bits internal RAM
    MBC3, // FIXME
    MBC5, // FIXME
};

pub const CardridgeProperties = struct {
    mbc_type: MBCType,
    has_ram: bool = false,
    has_battery: bool = false,
    has_timer: bool = false,
    has_rumble: bool = false,
};

fn get_cart_properties(cart_type: CardridgeType) CardridgeProperties {
    return switch (cart_type) {
        .ROM_ONLY => .{ .mbc_type = .None },
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
        .MBC3_TIMER_BATTERY => .{ .mbc_type = .MBC3, .has_battery = true, .has_timer = true },
        .MBC3_TIMER_RAM_BATTERY => .{ .mbc_type = .MBC3, .has_ram = true, .has_battery = true, .has_timer = true },
        .MBC3 => .{ .mbc_type = .MBC3 },
        .MBC3_RAM => .{ .mbc_type = .MBC3, .has_ram = true },
        .MBC3_RAM_BATTERY => .{ .mbc_type = .MBC3, .has_ram = true, .has_battery = true },
        .MBC5 => .{ .mbc_type = .MBC5 },
        .MBC5_RAM => .{ .mbc_type = .MBC5, .has_ram = true },
        .MBC5_RAM_BATTERY => .{ .mbc_type = .MBC5, .has_ram = true, .has_battery = true },
        .MBC5_RUMBLE => .{ .mbc_type = .MBC5, .has_rumble = true },
        .MBC5_RUMBLE_RAM => .{ .mbc_type = .MBC5, .has_rumble = true, .has_ram = true },
        .MBC5_RUMBLE_RAM_BATTERY => .{ .mbc_type = .MBC5, .has_rumble = true, .has_ram = true, .has_battery = true },
        //.MBC6 = 0x20,
        //.MBC7_SENSOR_RUMBLE_RAM_BATTERY = 0x22,
        //.POCKET_CAMERA = 0xFC,
        //.BANDAI_TAMA5 = 0xFD,
        //.HuC3 = 0xFE,
        //.HuC1_RAM_BATTERY = 0xFF,
        else => unreachable,
    };
}

const NintendoLogoBitmap = [LogoSizeBytes]u8{
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
};

comptime {
    std.debug.assert(@offsetOf(CartHeader, "_logo0") == 0x04);
    std.debug.assert(@offsetOf(CartHeader, "_title0") == 0x34);
    std.debug.assert(@offsetOf(CartHeader, "new_licensee_code_a") == 0x44);
    std.debug.assert(@offsetOf(CartHeader, "sgb_flag") == 0x46);
    std.debug.assert(@offsetOf(CartHeader, "cart_type") == 0x47);
    std.debug.assert(@sizeOf(CartHeader) == CartHeaderSizeBytes);
}

// pub const NewLicenseeCode = enum(u8) {
//     None                                                  0x00
//     Nintendo_Research_Development_1                       0x01
//     Capcom                                                0x08
//     Electronic_Arts                                       0x13
//     Hudson_Soft                                           0x18
//     B_AI                                                  0x19
//     KSS                                                   0x20
//     Planning_Office_WADA                                  0x22
//     PCM_Complete                                          0x24
//     San_X                                                 0x25
//     Kemco                                                 0x28
//     SETA Corporation                                      0x29
//     Viacom                                                0x30
//     Nintendo                                              0x31
//     Bandai                                                0x32
//     Ocean_Software_Acclaim_Entertainment                  0x33
//     Konami                                                0x34
//     HectorSoft                                            0x35
//     Taito                                                 0x37
//     Hudson_Soft                                           0x38
//     Banpresto                                             0x39
//     Ubi_Soft1                                             0x41
//     Atlus                                                 0x42
//     Malibu_Interactive                                    0x44
//     Angel                                                 0x46
//     Bullet_Proof_Software2                                0x47
//     Irem                                                  0x49
//     Absolute                                              0x50
//     Acclaim_Entertainment                                 0x51
//     Activision                                            0x52
//     Sammy_USA_Corporation                                 0x53
//     Konami                                                0x54
//     Hi_Tech_Expressions                                   0x55
//     LJN                                                   0x56
//     Matchbox                                              0x57
//     Mattel                                                0x58
//     Milton_Bradley_Company                                0x59
//     Titus_Interactive                                     0x60
//     Virgin_Games_Ltd_3                                    0x61
//     Lucasfilm_ Games4                                     0x64
//     Ocean_Software                                        0x67
//     Electronic_Arts                                       0x69
//     Infogrames5                                           0x70
//     Interplay_Entertainment                               0x71
//     Broderbund                                            0x72
//     Sculptured_Software6                                  0x73
//     The_Sales_Curve_Limited7                              0x75
//     THQ                                                   0x78
//     Accolade                                              0x79
//     Misawa_Entertainment                                  0x80
//     lozc                                                  0x83
//     Tokuma_Shoten                                         0x86
//     Tsukuda_Original                                      0x87
//     Chunsoft_Co_8                                         0x91
//     Video_System                                          0x92
//     Ocean_Software_Acclaim_Entertainment                  0x93
//     Varie                                                 0x95
//     Yonezawa_s_pal                                        0x96
//     Kaneko                                                0x97
//     Pack_In_Video                                         0x99
//     Bottom_Up                                             0x9H
//     Konami_Yu_Gi_Oh                                       0xA4
//     MTO                                                   0xBL
//     Kodansha                                              0xDK
// };

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

pub fn load_rom_u8(cart: *const CartState, address: u15) u8 {
    switch (address) {
        0x0000...0x3fff => { // ROM bank 0
            // FIXME handle boot ROM here
            return cart.rom[address];
        },
        0x4000...0x7fff => { // ROM bank X
            switch (cart.properties.mbc_type) {
                .None => {
                    return cart.rom[address];
                },
                .MBC1 => {
                    const banked_address = @as(u32, address) + @as(u32, cart.current_rom_bank - 1) * 0x4000;
                    return cart.rom[banked_address];
                },
                .MBC2 => {
                    const banked_address = @as(u32, address) + @as(u32, cart.current_rom_bank - 1) * 0x4000; // FIXME
                    return cart.rom[banked_address];
                },
                .MBC3 => unreachable,
                .MBC5 => unreachable,
            }
        },
    }
}

pub fn store_rom_u8(cart: *CartState, address: u15, value: u8) void {
    // Avoid writing here
    // Unfortunately it's common for official games to do, so avoid asserting for now.
    // https://www.reddit.com/r/EmuDev/comments/5ht388/gb_why_does_tetris_write_to_the_rom/
    // assert(address == 0x2000 or address == 0x00c3);
    switch (cart.properties.mbc_type) {
        .None => {},
        .MBC1 => switch (address) {
            0x0000...0x1fff => {
                cart.ram_enable = @as(u4, @truncate(value)) == 0xa;
            },
            0x2000...0x3fff => { // Write ROM Bank number
                const bank_number: u5 = @truncate(@max(value, 1));
                cart.current_rom_bank = bank_number;
            },
            0x4000...0x7fff => {},
        },
        .MBC2 => switch (address) {
            0x0000...0x3fff => {
                const rom_control = (address & 0x10) != 0;

                if (rom_control) {
                    // Write ROM Bank number
                    const bank_number: u4 = @truncate(@max(value, 1));
                    cart.current_rom_bank = bank_number;
                } else {
                    cart.ram_enable = value == 0x0a;
                }
            },
            0x4000...0x7fff => {},
        },
        .MBC3 => unreachable,
        .MBC5 => unreachable,
    }
}

pub fn load_external_ram_u8(cart: *const CartState, address: u14) u8 {
    _ = cart;
    _ = address;
    unreachable;
    // return gb.memory[address];
}

pub fn store_external_ram_u8(cart: *CartState, address: u14, value: u8) void {
    _ = cart;
    _ = address;
    _ = value;
    unreachable;
    // gb.memory[address] = value;
}
