const std = @import("std");

const lcd = @import("lcd.zig");
const sound = @import("sound.zig");

pub const GBState = struct {
    registers: Registers,
    memory: []u8,
    mmio: *MMIO,
    enable_interrupts_master: bool,
    screen_x: u8,
    screen_output: []u8,
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

pub const MMIO = packed struct {
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
    IF: packed struct { //= 0x0F, // Interrupt Flag (R/W)
        vblank_interrupt_requested: bool,
        lcd_interrupt_requested: bool,
        timer_interrupt_requested: bool,
        serial_interrupt_requested: bool,
        joypad_interrupt_requested: bool,
        _unused: u3,
    },
    sound: sound.Sound_MMIO,
    lcd: lcd.LCD_MMIO,
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
    IE: packed struct { //= 0xFF, // Interrupt enable
        enable_vblank_interrupt: bool, // VBlank (Read/Write): Controls whether the VBlank interrupt handler may be called
        enable_lcd_interrupt: bool, // LCD (Read/Write): Controls whether the LCD interrupt handler may be called
        enable_timer_interrupt: bool, // Timer (Read/Write): Controls whether the Timer interrupt handler may be called
        enable_serial_interrupt: bool, // Serial (Read/Write): Controls whether the Serial interrupt handler may be called
        enable_joypad_interrupt: bool, // Joypad (Read/Write): Controls whether the Joypad interrupt handler may be called
        _unused: u3,
    },
};

comptime {
    std.debug.assert(@offsetOf(MMIO, "sound") == 0x10);
    std.debug.assert(@offsetOf(MMIO, "lcd") == 0x40);
    std.debug.assert(@offsetOf(MMIO, "PCM34") == 0x77);
    std.debug.assert(@sizeOf(MMIO) == 256);
}

pub fn create_state(allocator: std.mem.Allocator, cart_rom_bytes: []const u8) !GBState {
    const memory = try allocator.alloc(u8, 256 * 256); // FIXME
    errdefer allocator.free(memory);

    const screen_output = try allocator.alloc(u8, lcd.ScreenSizeBytes);
    errdefer allocator.free(screen_output);

    // FIXME This only works with the smallest ROMs
    std.mem.copyForwards(u8, memory, cart_rom_bytes);

    const mmio_memory = memory[0xFF00..];
    const mmio: *MMIO = @ptrCast(@alignCast(mmio_memory)); // FIXME remove alignCast!

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
        .mmio = mmio,
        .enable_interrupts_master = false,
        .screen_x = 0,
        .screen_output = screen_output,
        .pending_cycles = 0, // In T-states, is how much the CPU is in advance over other components
        .total_cycles = 0, // In T-states
    };
}

pub fn destroy_state(allocator: std.mem.Allocator, gb: *GBState) void {
    allocator.free(gb.memory);
    allocator.free(gb.screen_output);
}
