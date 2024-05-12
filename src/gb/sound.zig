pub const Sound_MMIO = packed struct {
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
    WAV_PATTERN_1: u32,
    WAV_PATTERN_2: u32,
    WAV_PATTERN_3: u32,
};
