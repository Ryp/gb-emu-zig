const std = @import("std");

const ppu = @import("ppu.zig");
const sound = @import("sound.zig");
const joypad = @import("joypad.zig");
const cart = @import("cart.zig");

pub const GBState = struct {
    registers: Registers,
    rom: []const u8, // Borrowed from create_state
    cart_properties: cart.CardridgeProperties, // Should get const?
    cart_current_rom_bank: u8 = 1,
    cart_current_ram_bank: u8 = 0,
    memory: []u8,
    mmio: *MMIO,
    enable_interrupts_master: bool, // IME
    vram: []u8,
    oam_sprites: [ppu.OAMSpriteCount]ppu.Sprite,

    // PPU internal state
    screen_output: []u8,
    ppu_h_cycles: u16, // NOTE: Normally independent of the CPU cycles but on DMG they match 1:1
    last_stat_interrupt_line: bool, // Last state of the STAT interrupt line
    has_frame_to_consume: bool, // Tell the frontend to consume screen_output
    active_sprite_indices: [ppu.LineMaxActiveSprites]u8,
    active_sprite_count: u8,

    dma_active: bool = false,
    dma_current_offset: u8 = 0,

    keys: joypad.Keys,

    is_halted: bool = false, // FIXME
    pending_t_cycles: u8, // How much the CPU is in advance over other components
    total_t_cycles: u64,
};

pub fn create_state(allocator: std.mem.Allocator, cart_rom_bytes: []const u8) !GBState {
    const cart_header = cart.extract_header_from_rom(cart_rom_bytes);
    const cart_properties = cart.get_cart_properties(cart_header.cart_type);

    std.debug.assert(cart_properties.has_battery == false);
    std.debug.assert(cart_properties.has_ram == false);
    std.debug.assert(cart_properties.mbc_type == .None or cart_properties.mbc_type == .MBC1);

    if (cart_properties.mbc_type == .None) {
        std.debug.assert(cart_rom_bytes.len == 32 * 1024);
    } else if (cart_properties.mbc_type == .MBC1) {
        std.debug.assert(cart_rom_bytes.len == (@as(u32, 1) << @as(u5, @intCast(cart_header.rom_size))) * 32 * 1024);
    }

    const memory = try allocator.alloc(u8, 256 * 256); // FIXME
    errdefer allocator.free(memory);

    const screen_output = try allocator.alloc(u8, ppu.ScreenSizeBytes);
    errdefer allocator.free(screen_output);

    const mmio_memory = memory[0xFF00..];
    const mmio: *MMIO = @ptrCast(@alignCast(mmio_memory)); // FIXME remove alignCast!
    const vram = memory[ppu.VRAMBeginOffset..ppu.VRAMEndOffset];

    // See this page for the initial state of the io registers:
    // http://www.codeslinger.co.uk/pages/projects/gameboy/hardware.html
    mmio_memory[0x05] = 0x00;
    mmio_memory[0x06] = 0x00;
    mmio_memory[0x07] = 0x00;
    mmio_memory[0x10] = 0x80;
    mmio_memory[0x11] = 0xBF;
    mmio_memory[0x12] = 0xF3;
    mmio_memory[0x14] = 0xBF;
    mmio_memory[0x16] = 0x3F;
    mmio_memory[0x17] = 0x00;
    mmio_memory[0x19] = 0xBF;
    mmio_memory[0x1A] = 0x7F;
    mmio_memory[0x1B] = 0xFF;
    mmio_memory[0x1C] = 0x9F;
    mmio_memory[0x1E] = 0xBF;
    mmio_memory[0x20] = 0xFF;
    mmio_memory[0x21] = 0x00;
    mmio_memory[0x22] = 0x00;
    mmio_memory[0x23] = 0xBF;
    mmio_memory[0x24] = 0x77;
    mmio_memory[0x25] = 0xF3;
    mmio_memory[0x26] = 0xF1;
    mmio_memory[0x40] = 0x91;
    mmio_memory[0x42] = 0x00;
    mmio_memory[0x43] = 0x00;
    mmio_memory[0x45] = 0x00;
    mmio_memory[0x47] = 0xFC;
    mmio_memory[0x48] = 0xFF;
    mmio_memory[0x49] = 0xFF;
    mmio_memory[0x4A] = 0x00;
    mmio_memory[0x4B] = 0x00;
    mmio_memory[0xFF] = 0x00;

    // FIXME
    mmio.ppu.LY = 0;
    mmio.JOYP.input_selector = .both;
    mmio.JOYP._unused = 0b11;

    return GBState{
        .registers = @bitCast(Registers_R16{
            .bc = 0x0013,
            .de = 0x00D8,
            .hl = 0x014D,
            .af = 0x01B0, // NOTE: The lowest nibble HAS to be set to zero.
            .sp = 0xFFFE,
            .pc = 0x0100,
        }),
        .rom = cart_rom_bytes,
        .cart_properties = cart_properties,
        .memory = memory,
        .mmio = mmio,
        .enable_interrupts_master = false,
        .vram = vram,
        .oam_sprites = undefined,
        .screen_output = screen_output,
        .ppu_h_cycles = 0,
        .last_stat_interrupt_line = false,
        .has_frame_to_consume = false,
        .active_sprite_indices = undefined,
        .active_sprite_count = 0,
        .keys = .{ .dpad = .{ .pressed_mask = 0 }, .buttons = .{ .pressed_mask = 0 } },
        .pending_t_cycles = 0,
        .total_t_cycles = 0,
    };
}

pub fn destroy_state(allocator: std.mem.Allocator, gb: *GBState) void {
    allocator.free(gb.memory);
    allocator.free(gb.screen_output);
}

const native_endian = @import("builtin").target.cpu.arch.endian();

// Register layout varies depending on the host, since we want to make use of
// bit-casting r8 registers into r16 to save manual conversions.
pub const Registers = switch (native_endian) {
    .little => Registers_LittleEndian,
    .big => Registers_BigEndian,
};

const Registers_LittleEndian = packed struct {
    c: u8,
    b: u8,
    e: u8,
    d: u8,
    l: u8,
    h: u8,
    flags: FlagRegister,
    a: u8,
    sp: u16, // Stack Pointer
    pc: u16, // Program Counter
};

const Registers_BigEndian = packed struct {
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    a: u8,
    flags: FlagRegister,
    sp: u16, // Stack Pointer
    pc: u16, // Program Counter
};

// Anytime we need the u16 view on register, we can safely bitcast since the backing has the proper memory layout
pub const Registers_R16 = packed struct {
    bc: u16,
    de: u16,
    hl: u16,
    af: u16,
    sp: u16, // Stack Pointer
    pc: u16, // Program Counter
};

pub const FlagRegister = packed struct {
    _unused: u4, // NOTE: This has to stay zero otherwise pop/push could break
    carry: u1,
    half_carry: u1,
    substract: bool,
    zero: bool,
};

comptime {
    std.debug.assert(@sizeOf(FlagRegister) == 1);
    std.debug.assert(@offsetOf(Registers_LittleEndian, "sp") == 8);
    std.debug.assert(@offsetOf(Registers_BigEndian, "sp") == 8);
    std.debug.assert(@offsetOf(Registers_R16, "sp") == 8);
}

pub const MMIO = packed struct {
    JOYP: packed struct { //= 0x00, // Joypad (R/W)
        released_state: u4,
        input_selector: enum(u2) {
            both,
            buttons,
            dpad,
            none,
        },
        _unused: u2,
    },
    SB: u8, //= 0x01, // Serial transfer data (R/W)
    SC: u8, //= 0x02, // Serial Transfer Control (R/W)
    _unused_03: u8,
    DIV: u8, //= 0x04, // Divider Register (R/W)
    TIMA: u8, //= 0x05, // Timer counter (R/W)
    TMA: u8, //= 0x06, // Timer Modulo (R/W)
    TAC: u8, // = 0x07, // Timer Control (R/W)
    _unused_08: u8,
    _unused_09: u8,
    _unused_0A: u8,
    _unused_0B: u8,
    _unused_0C: u8,
    _unused_0D: u8,
    _unused_0E: u8,
    IF: packed struct { //= 0x0F, // Interrupt Flag (R/W)
        requested_interrupts_mask: u5,
        _unused: u3,
    },
    sound: sound.Sound_MMIO,
    ppu: ppu.MMIO,
    BANK: u8, //= 0x50, // Write to disable the boot ROM mapping
    HDMA1: u8, //= 0x51, // CGB Mode Only - New DMA Source, High
    HDMA2: u8, //= 0x52, // CGB Mode Only - New DMA Source, Low
    HDMA3: u8, //= 0x53, // CGB Mode Only - New DMA Destination, High
    HDMA4: u8, //= 0x54, // CGB Mode Only - New DMA Destination, Low
    HDMA5: u8, //= 0x55, // CGB Mode Only - New DMA Length/Mode/Start
    RP: u8, //= 0x56, // CGB Mode Only - Infrared Communications Port
    _unused_57: u8,
    _unused_58: u8,
    _unused_59: u8,
    _unused_5A: u8,
    _unused_5B: u8,
    _unused_5C: u8,
    _unused_5D: u8,
    _unused_5E: u8,
    _unused_5F: u8,
    _unused_60: u8,
    _unused_61: u8,
    _unused_62: u8,
    _unused_63: u8,
    _unused_64: u8,
    _unused_65: u8,
    _unused_66: u8,
    _unused_67: u8,
    BGPI: u8, // = 0x68, // CGB Mode Only - Background Palette Index
    BGPD: u8, // = 0x69, // CGB Mode Only - Background Palette Data
    OBPI: u8, // = 0x6A, // CGB Mode Only - Object Palette Index
    OBPD: u8, // = 0x6B, // CGB Mode Only - Object Palette Data
    OPRI: u8, // = 0x6C, // Affects object priority (X based or index based)
    _unused_6D: u8,
    _unused_6E: u8,
    _unused_6F: u8,
    SVBK: u8, // = 0x70, // CGB Mode Only - WRAM Bank
    PSM: u8, // = 0x71, // Palette Selection Mode, controls the PSW and key combo
    PSWX: u8, // = 0x72, // X position of the palette switching window
    PSWY: u8, // = 0x73, // Y position of the palette switching window
    PSW: u8, // = 0x74, // Key combo to trigger the palette switching window
    UNKNOWN5: u8, // = 0x75, // (8Fh) - Bit 4-6 (Read/Write)
    PCM12: u8, // = 0x76, // Channels 1 and 2 amplitudes
    PCM34: u8, // = 0x77, // Channels 3 and 4 amplitudes
    _unused_78: u8,
    _unused_79: u8,
    _unused_7A: u8,
    _unused_7B: u8,
    _unused_7C: u8,
    _unused_7D: u8,
    _unused_7E: u8,
    _unused_7F: u8,
    hram_80_4: u32,
    hram_84_4: u32,
    hram_88_4: u32,
    hram_8C_4: u32,
    hram_90_4: u32,
    hram_94_4: u32,
    hram_98_4: u32,
    hram_9C_4: u32,
    hram_A0_4: u32,
    hram_A4_4: u32,
    hram_A8_4: u32,
    hram_AC_4: u32,
    hram_B0_4: u32,
    hram_B4_4: u32,
    hram_B8_4: u32,
    hram_BC_4: u32,
    hram_C0_4: u32,
    hram_C4_4: u32,
    hram_C8_4: u32,
    hram_CC_4: u32,
    hram_D0_4: u32,
    hram_D4_4: u32,
    hram_D8_4: u32,
    hram_DC_4: u32,
    hram_E0_4: u32,
    hram_E4_4: u32,
    hram_E8_4: u32,
    hram_EC_4: u32,
    hram_F0_4: u32,
    hram_F4_4: u32,
    hram_F8_4: u32,
    hram_FC: u8,
    hram_FD: u8,
    hram_FE: u8,
    IE: packed struct { //= 0xFF, // Interrupt Enable
        enable_interrupts_mask: u5,
        _unused: u3,
    },
};

// For instruction execution it's useful to also be able to index mmio memory with offsets
pub const MMIO_Offset = enum(u8) {
    JOYP = 0x00, // Joypad (R/W)
    // SB         = 0x01, // Serial transfer data (R/W)
    // SC         = 0x02, // Serial Transfer Control (R/W)
    // DIV        = 0x04, // Divider Register (R/W)
    // TIMA       = 0x05, // Timer counter (R/W)
    // TMA        = 0x06, // Timer Modulo (R/W)
    // TAC        = 0x07, // Timer Control (R/W)
    // IF         = 0x0F, // Interrupt Flag (R/W)
    // NR10       = 0x10, // Channel 1 Sweep register (R/W)
    // NR11       = 0x11, // Channel 1 Sound length/Wave pattern duty (R/W)
    // NR12       = 0x12, // Channel 1 Volume Envelope (R/W)
    // NR13       = 0x13, // Channel 1 Frequency lo (Write Only)
    // NR14       = 0x14, // Channel 1 Frequency hi (R/W)
    // NR21       = 0x16, // Channel 2 Sound Length/Wave Pattern Duty (R/W)
    // NR22       = 0x17, // Channel 2 Volume Envelope (R/W)
    // NR23       = 0x18, // Channel 2 Frequency lo data (W)
    // NR24       = 0x19, // Channel 2 Frequency hi data (R/W)
    // NR30       = 0x1A, // Channel 3 Sound on/off (R/W)
    // NR31       = 0x1B, // Channel 3 Sound Length
    // NR32       = 0x1C, // Channel 3 Select output level (R/W)
    // NR33       = 0x1D, // Channel 3 Frequency's lower data (W)
    // NR34       = 0x1E, // Channel 3 Frequency's higher data (R/W)
    // NR41       = 0x20, // Channel 4 Sound Length (R/W)
    // NR42       = 0x21, // Channel 4 Volume Envelope (R/W)
    // NR43       = 0x22, // Channel 4 Polynomial Counter (R/W)
    // NR44       = 0x23, // Channel 4 Counter/consecutive, Inital (R/W)
    // NR50       = 0x24, // Channel control / ON-OFF / Volume (R/W)
    // NR51       = 0x25, // Selection of Sound output terminal (R/W)
    // NR52       = 0x26, // Sound on/off
    // WAV_START  = 0x30, // Wave pattern start
    // WAV_END    = 0x3F, // Wave pattern end
    LCDC = 0x40, // LCD Control (R/W)
    // STAT       = 0x41, // LCDC Status (R/W)
    // SCY        = 0x42, // Scroll Y (R/W)
    // SCX        = 0x43, // Scroll X (R/W)
    // LY         = 0x44, // LCDC Y-Coordinate (R)
    // LYC        = 0x45, // LY Compare (R/W)
    DMA = 0x46, // DMA Transfer and Start Address (W)
    // BGP        = 0x47, // BG Palette Data (R/W) - Non CGB Mode Only
    // OBP0       = 0x48, // Object Palette 0 Data (R/W) - Non CGB Mode Only
    // OBP1       = 0x49, // Object Palette 1 Data (R/W) - Non CGB Mode Only
    // WY         = 0x4A, // Window Y Position (R/W)
    // WX         = 0x4B, // Window X Position minus 7 (R/W)
    // KEY0       = 0x4C, // Controls DMG mode and PGB mode
    // KEY1       = 0x4D, // CGB Mode Only - Prepare Speed Switch
    // VBK        = 0x4F, // CGB Mode Only - VRAM Bank
    // BANK       = 0x50, // Write to disable the boot ROM mapping
    // HDMA1      = 0x51, // CGB Mode Only - New DMA Source, High
    // HDMA2      = 0x52, // CGB Mode Only - New DMA Source, Low
    // HDMA3      = 0x53, // CGB Mode Only - New DMA Destination, High
    // HDMA4      = 0x54, // CGB Mode Only - New DMA Destination, Low
    // HDMA5      = 0x55, // CGB Mode Only - New DMA Length/Mode/Start
    // RP         = 0x56, // CGB Mode Only - Infrared Communications Port
    // BGPI       = 0x68, // CGB Mode Only - Background Palette Index
    // BGPD       = 0x69, // CGB Mode Only - Background Palette Data
    // OBPI       = 0x6A, // CGB Mode Only - Object Palette Index
    // OBPD       = 0x6B, // CGB Mode Only - Object Palette Data
    // OPRI       = 0x6C, // Affects object priority (X based or index based)
    // SVBK       = 0x70, // CGB Mode Only - WRAM Bank
    // PSM        = 0x71, // Palette Selection Mode, controls the PSW and key combo
    // PSWX       = 0x72, // X position of the palette switching window
    // PSWY       = 0x73, // Y position of the palette switching window
    // PSW        = 0x74, // Key combo to trigger the palette switching window
    // UNKNOWN5   = 0x75, // (8Fh) - Bit 4-6 (Read/Write)
    // PCM12     = 0x76, // Channels 1 and 2 amplitudes
    // PCM34     = 0x77, // Channels 3 and 4 amplitudes
    // IE        = 0xFF, // IE - Interrupt Enable
    _, // There's plenty of unused addressing
};

comptime {
    std.debug.assert(@offsetOf(MMIO, "sound") == 0x10);
    std.debug.assert(@offsetOf(MMIO, "ppu") == 0x40);
    std.debug.assert(@offsetOf(MMIO, "PCM34") == 0x77);
    std.debug.assert(@sizeOf(MMIO) == 256);
}

pub const TClockPeriod = 4 * 1024 * 1024;
pub const DIVClockPeriod = 16 * 1024;

pub const InterruptMaskVBlank = 0b00001;
pub const InterruptMaskLCD = 0b00010;
pub const InterruptMaskTimer = 0b00100;
pub const InterruptMaskSerial = 0b01000;
pub const InterruptMaskJoypad = 0b10000;

pub const DMACopyByteCount = 160;
