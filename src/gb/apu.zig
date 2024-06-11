const std = @import("std");
const assert = std.debug.assert;

const cpu = @import("cpu.zig");

pub fn step_apu(gb: *cpu.GBState, t_cycle_count: u8) void {
    _ = gb; // FIXME
    _ = t_cycle_count;
}

pub fn reset_apu(gb: *cpu.GBState) void {
    _ = gb; // FIXME
}

pub const MMIO = packed struct {
    NR10: packed struct { // 0x10 Channel 1 Sweep register (R/W)
        step: u3,
        direction: enum(u1) {
            Add = 0,
            Sub = 1,
        },
        pace: u3,
        _unused: u1,
    },
    NR11: packed struct { // 0x11 Channel 1 Sound length/Wave pattern duty (R/W)
        length_timer: u6,
        wave_duty: u2,
    },
    NR12: packed struct { // 0x12 Channel 1 Volume Envelope (R/W)
        sweep_pace: u3,
        envelope_direction: enum(u1) {
            DecreaseVolume = 0,
            IncreaseVolume = 1,
        },
        initial_volume: u4,
    },
    NR13: u8, // 0x13 Channel 1 Frequency lo (Write Only)
    NR14: packed struct { // 0x14 Channel 1 Frequency hi (R/W)
        period: u3,
        _unused: u3,
        length_enable: bool,
        trigger: bool,
    },
    _unused_15: u8,
    NR21: u8, // 0x16 Channel 2 Sound Length/Wave Pattern Duty (R/W)
    NR22: u8, // 0x17 Channel 2 Volume Envelope (R/W)
    NR23: u8, // 0x18 Channel 2 Frequency lo data (W)
    NR24: u8, // 0x19 Channel 2 Frequency hi data (R/W)
    NR30: u8, // 0x1A Channel 3 Sound on/off (R/W)
    NR31: u8, // 0x1B Channel 3 Sound Length
    NR32: u8, // 0x1C Channel 3 Select output level (R/W)
    NR33: u8, // 0x1D Channel 3 Frequency's lower data (W)
    NR34: u8, // 0x1E Channel 3 Frequency's higher data (R/W)
    _unused_1F: u8,
    NR41: u8, // 0x20 Channel 4 Sound Length (R/W)
    NR42: u8, // 0x21 Channel 4 Volume Envelope (R/W)
    NR43: u8, // 0x22 Channel 4 Polynomial Counter (R/W)
    NR44: u8, // 0x23 Channel 4 Counter/consecutive, Inital (R/W)
    NR50: packed struct { // 0x24 Channel control / ON-OFF / Volume (R/W)
        volume_r: u3,
        enable_vin_r: bool,
        volume_l: u3,
        enable_vin_l: bool,
    },
    NR51: packed struct { // 0x25 Selection of Sound output terminal (R/W)
        enable_channel1_r: bool,
        enable_channel2_r: bool,
        enable_channel3_r: bool,
        enable_channel4_r: bool,
        enable_channel1_l: bool,
        enable_channel2_l: bool,
        enable_channel3_l: bool,
        enable_channel4_l: bool,
    },
    NR52: packed struct { // 0x26 Audio master control
        enable_channel1: bool,
        enable_channel2: bool,
        enable_channel3: bool,
        enable_channel4: bool,
        _unused: u3,
        enable_apu: bool,
    },
    _unused_27: u8,
    _unused_28: u8,
    _unused_29: u8,
    _unused_2A: u8,
    _unused_2B: u8,
    _unused_2C: u8,
    _unused_2D: u8,
    _unused_2E: u8,
    _unused_2F: u8,
    WAV_PATTERN_0: u32, // 0x30 Wave pattern
    WAV_PATTERN_1: u32,
    WAV_PATTERN_2: u32,
    WAV_PATTERN_3: u32,
};

comptime {
    assert(@sizeOf(MMIO) == 0x30);
}
