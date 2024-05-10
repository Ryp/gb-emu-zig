const std = @import("std");

pub const GBState = struct {
    registers: Registers,
    memory: []u8,
    io_registers: *IORegisters,
    enable_interrupts_master: bool,
    pending_cycles: u8,
    total_cycles: u64,
};

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
    _unused: u4,
    carry: u1,
    half_carry: u1,
    substract: u1,
    zero: u1,
};

comptime {
    std.debug.assert(@sizeOf(FlagRegister) == 1);
    std.debug.assert(@offsetOf(Registers_LittleEndian, "sp") == 8);
    std.debug.assert(@offsetOf(Registers_BigEndian, "sp") == 8);
    std.debug.assert(@offsetOf(Registers_R16, "sp") == 8);
}

pub const IORegisters = packed struct {
    JOYP: u8, //= 0x00, // Joypad (R/W)
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
    IF: u8, //= 0x0F, // Interrupt Flag (R/W)
    // Sound
    NR10: u8, //= 0x10, // Channel 1 Sweep register (R/W)
    NR11: u8, //= 0x11, // Channel 1 Sound length/Wave pattern duty (R/W)
    NR12: u8, //= 0x12, // Channel 1 Volume Envelope (R/W)
    NR13: u8, //= 0x13, // Channel 1 Frequency lo (Write Only)
    NR14: u8, //= 0x14, // Channel 1 Frequency hi (R/W)
    _unused_15: u8,
    NR21: u8, //= 0x16, // Channel 2 Sound Length/Wave Pattern Duty (R/W)
    NR22: u8, //= 0x17, // Channel 2 Volume Envelope (R/W)
    NR23: u8, //= 0x18, // Channel 2 Frequency lo data (W)
    NR24: u8, //= 0x19, // Channel 2 Frequency hi data (R/W)
    NR30: u8, //= 0x1A, // Channel 3 Sound on/off (R/W)
    NR31: u8, //= 0x1B, // Channel 3 Sound Length
    NR32: u8, //= 0x1C, // Channel 3 Select output level (R/W)
    NR33: u8, //= 0x1D, // Channel 3 Frequency's lower data (W)
    NR34: u8, //= 0x1E, // Channel 3 Frequency's higher data (R/W)
    _unused_1F: u8,
    NR41: u8, //= 0x20, // Channel 4 Sound Length (R/W)
    NR42: u8, //= 0x21, // Channel 4 Volume Envelope (R/W)
    NR43: u8, //= 0x22, // Channel 4 Polynomial Counter (R/W)
    NR44: u8, //= 0x23, // Channel 4 Counter/consecutive, Inital (R/W)
    NR50: u8, //= 0x24, // Channel control / ON-OFF / Volume (R/W)
    NR51: u8, //= 0x25, // Selection of Sound output terminal (R/W)
    NR52: u8, //= 0x26, // Sound on/off
    _unused_27: u8,
    _unused_28: u8,
    _unused_29: u8,
    _unused_2A: u8,
    _unused_2B: u8,
    _unused_2C: u8,
    _unused_2D: u8,
    _unused_2E: u8,
    _unused_2F: u8,
    WAV_PATTERN_0: u32, //= 0x30, // Wave pattern
    WAV_PATTERN_1: u32, //= 0x30, // Wave pattern
    WAV_PATTERN_2: u32, //= 0x30, // Wave pattern
    WAV_PATTERN_3: u32, //= 0x30, // Wave pattern
    LCDC: u8, //= 0x40, // LCD Control (R/W)
    STAT: u8, //= 0x41, // LCDC Status (R/W)
    SCY: u8, //= 0x42, // Scroll Y (R/W)
    SCX: u8, //= 0x43, // Scroll X (R/W)
    LY: u8, //= 0x44, // LCDC Y-Coordinate (R)
    LYC: u8, //= 0x45, // LY Compare (R/W)
    DMA: u8, //= 0x46, // DMA Transfer and Start Address (W)
    BGP: u8, //= 0x47, // BG Palette Data (R/W) - Non CGB Mode Only
    OBP0: u8, //= 0x48, // Object Palette 0 Data (R/W) - Non CGB Mode Only
    OBP1: u8, //= 0x49, // Object Palette 1 Data (R/W) - Non CGB Mode Only
    WY: u8, //= 0x4A, // Window Y Position (R/W)
    WX: u8, //= 0x4B, // Window X Position minus 7 (R/W)
    // Controls DMG mode and PGB mode
    KEY0: u8, //= 0x4C,
    KEY1: u8, //= 0x4D, // CGB Mode Only - Prepare Speed Switch
    _unused_4E: u8,
    VBK: u8, //= 0x4F, // CGB Mode Only - VRAM Bank
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
    _unused_80_4: u32,
    _unused_84_4: u32,
    _unused_88_4: u32,
    _unused_8C_4: u32,
    _unused_90_4: u32,
    _unused_94_4: u32,
    _unused_98_4: u32,
    _unused_9C_4: u32,
    _unused_A0_4: u32,
    _unused_A4_4: u32,
    _unused_A8_4: u32,
    _unused_AC_4: u32,
    _unused_B0_4: u32,
    _unused_B4_4: u32,
    _unused_B8_4: u32,
    _unused_BC_4: u32,
    _unused_C0_4: u32,
    _unused_C4_4: u32,
    _unused_C8_4: u32,
    _unused_CC_4: u32,
    _unused_D0_4: u32,
    _unused_D4_4: u32,
    _unused_D8_4: u32,
    _unused_DC_4: u32,
    _unused_E0_4: u32,
    _unused_E4_4: u32,
    _unused_E8_4: u32,
    _unused_EC_4: u32,
    _unused_F0_4: u32,
    _unused_F4_4: u32,
    _unused_F8_4: u32,
    _unused_FC: u8,
    _unused_FD: u8,
    _unused_FE: u8,
    IE: u8,
};

comptime {
    std.debug.assert(@offsetOf(IORegisters, "WAV_PATTERN_0") == 0x30);
    std.debug.assert(@offsetOf(IORegisters, "PCM34") == 0x77);
    std.debug.assert(@sizeOf(IORegisters) == 256);
}

pub fn create_state(allocator: std.mem.Allocator, cart_rom_bytes: []const u8) !GBState {
    const memory = try allocator.alloc(u8, 256 * 256); // FIXME
    errdefer allocator.free(memory);

    // FIXME
    std.mem.copyForwards(u8, memory, cart_rom_bytes);

    const io_register_memory = memory[0xFF00..];
    const io_registers: *IORegisters = @ptrCast(@alignCast(io_register_memory)); // FIXME remove alignCast!

    // See this page for the initial state of the io registers:
    // http://www.codeslinger.co.uk/pages/projects/gameboy/hardware.html
    io_register_memory[0x05] = 0x00;
    io_register_memory[0x06] = 0x00;
    io_register_memory[0x07] = 0x00;
    io_register_memory[0x10] = 0x80;
    io_register_memory[0x11] = 0xBF;
    io_register_memory[0x12] = 0xF3;
    io_register_memory[0x14] = 0xBF;
    io_register_memory[0x16] = 0x3F;
    io_register_memory[0x17] = 0x00;
    io_register_memory[0x19] = 0xBF;
    io_register_memory[0x1A] = 0x7F;
    io_register_memory[0x1B] = 0xFF;
    io_register_memory[0x1C] = 0x9F;
    io_register_memory[0x1E] = 0xBF;
    io_register_memory[0x20] = 0xFF;
    io_register_memory[0x21] = 0x00;
    io_register_memory[0x22] = 0x00;
    io_register_memory[0x23] = 0xBF;
    io_register_memory[0x24] = 0x77;
    io_register_memory[0x25] = 0xF3;
    io_register_memory[0x26] = 0xF1;
    io_register_memory[0x40] = 0x91;
    io_register_memory[0x42] = 0x00;
    io_register_memory[0x43] = 0x00;
    io_register_memory[0x45] = 0x00;
    io_register_memory[0x47] = 0xFC;
    io_register_memory[0x48] = 0xFF;
    io_register_memory[0x49] = 0xFF;
    io_register_memory[0x4A] = 0x00;
    io_register_memory[0x4B] = 0x00;
    io_register_memory[0xFF] = 0x00;

    return GBState{
        .registers = @bitCast(Registers_R16{
            .bc = 0x0013,
            .de = 0x00D8,
            .hl = 0x014D,
            .af = 0x01B0,
            .sp = 0xFFFE,
            .pc = 0x0100,
        }),
        .memory = memory,
        .io_registers = io_registers,
        .enable_interrupts_master = false,
        .pending_cycles = 0, // In T-states
        .total_cycles = 0, // In T-states
    };
}

pub fn destroy_state(allocator: std.mem.Allocator, gb: *GBState) void {
    allocator.free(gb.memory);
}
