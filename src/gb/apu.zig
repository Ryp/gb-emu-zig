const std = @import("std");
const assert = std.debug.assert;

const cpu = @import("cpu.zig");

pub const APUState = struct {
    ch1: CH1State = .{},
    ch2: CH2State = .{},
    ch3: CH3State = .{},
    ch4: CH4State = .{},
};

const CH1State = struct {
    envelope: EnvelopeState = .{},
    period_sweep_counter: u3 = 0,
};

const CH2State = struct {
    envelope: EnvelopeState = .{},
};

const CH3State = struct {};

const CH4State = struct {
    sample: u4 = 0,
    envelope: EnvelopeState = .{},
    lfsr: LFSR = .{ .mask = 0 },
    clock_counter: u3 = 0,
};

pub fn create_apu_state() APUState {
    return .{};
}

pub fn reset_apu(gb: *cpu.GBState) void {
    gb.apu_state = create_apu_state();
}

pub fn step_apu(gb: *cpu.GBState, t_cycle_count: u8, clock_falling_edge_mask: u64) void {
    const mmio = &gb.mmio.apu;

    const tick_64hz: u1 = @truncate(clock_falling_edge_mask >> 15);
    const tick_128hz: u1 = @truncate(clock_falling_edge_mask >> 14);
    const tick_256hz: u1 = @truncate(clock_falling_edge_mask >> 13);
    const tick_lfsr_rate: u1 = @truncate(clock_falling_edge_mask >> (5 + mmio.NR43.clock_shift)); // FIXME

    // FIXME Ticks happen when channel aren't triggered?

    if (tick_64hz == 1) {
        tick_envelope_sweep(&gb.apu_state.ch1.envelope, mmio.NR12.envelope);
        tick_envelope_sweep(&gb.apu_state.ch2.envelope, mmio.NR22.envelope);
        tick_envelope_sweep(&gb.apu_state.ch4.envelope, mmio.NR42.envelope);
    }

    if (tick_128hz == 1) {
        tick_period_sweep(&gb.apu_state.ch1, mmio);
    }

    if (tick_256hz == 1) {
        tick_length_timers(mmio);
    }

    if (tick_lfsr_rate == 1) {
        tick_lfsr(&gb.apu_state.ch4.lfsr, mmio);
    }

    // FIXME compute sample values
    gb.apu_state.ch4.sample = if (gb.apu_state.ch4.lfsr.bits.bit0 == 1) gb.apu_state.ch4.envelope.volume else 0;

    for (0..t_cycle_count) |_| // FIXME 4MHz audio!
    {
        var channel_samples: [4]u4 = undefined;
        var channel_dac_enabled: [4]bool = undefined;

        channel_dac_enabled[0] = mmio.NR12.enable_dac.mask != 0;
        channel_dac_enabled[1] = mmio.NR22.enable_dac.mask != 0;
        channel_dac_enabled[2] = mmio.NR30.enable_dac;
        channel_dac_enabled[3] = mmio.NR42.enable_dac.mask != 0;

        channel_samples[0] = generate_channel1_sample(mmio, channel_dac_enabled[0]);
        // FIXME
        channel_samples[1] = 0;
        channel_samples[2] = 0;
        channel_samples[3] = 0;

        var channel_samples_f32: [4]f32 = undefined;

        // DAC block
        // FIXME DAC can be disabled, how to handle this?
        for (&channel_samples_f32, channel_samples, channel_dac_enabled) |*sample_float, sample, dac_enabled| {
            sample_float.* = convert_generated_sample_to_float(sample, dac_enabled);
        }

        // Mixer block
        const mixed_sample = mix_channel_samples(mmio, channel_samples_f32);

        // FIXME Missing high-pass filter

        _ = mixed_sample;
    }
}

// NOTE: This is called AFTER the new MMIO value was written
pub fn trigger_channel1(gb: *cpu.GBState, ch1: *CH1State) void {
    const mmio = &gb.mmio.apu;

    if (mmio.NR13_NR14.trigger) {
        ch1.period_sweep_counter = mmio.NR10.sweep_pace - 1;

        ch1.envelope.counter = mmio.NR12.envelope.sweep_pace - 1;
        ch1.envelope.volume = mmio.NR12.envelope.initial_volume;
    }
}

pub fn trigger_channel2(gb: *cpu.GBState) void {
    _ = gb;
    unreachable;
}

pub fn trigger_channel3(gb: *cpu.GBState) void {
    _ = gb;
    unreachable;
}

pub fn trigger_channel4(gb: *cpu.GBState) void {
    _ = gb;
    unreachable;
}

fn tick_length_timers(mmio: *MMIO) void {
    if (mmio.NR13_NR14.enable_length_timer) {
        mmio.NR11.length_timer, const ch1_length_overflow = @addWithOverflow(mmio.NR11.length_timer, 1);

        if (ch1_length_overflow == 1) {
            mmio.NR13_NR14.trigger = false;
        }
    }

    if (mmio.NR23_NR24.enable_length_timer) {
        mmio.NR21.length_timer, const ch2_length_overflow = @addWithOverflow(mmio.NR21.length_timer, 1);

        if (ch2_length_overflow == 1) {
            mmio.NR23_NR24.trigger = false;
        }
    }

    if (mmio.NR33_NR34.enable_length_timer) {
        // FIXME would overflow at 256 instead of 64 of the docs
        mmio.NR31.length_timer, const ch3_length_overflow = @addWithOverflow(mmio.NR31.length_timer, 1);

        if (ch3_length_overflow == 1) {
            mmio.NR33_NR34.trigger = false;
        }
    }

    if (mmio.NR44.enable_length_timer) {
        mmio.NR41.length_timer, const ch4_length_overflow = @addWithOverflow(mmio.NR41.length_timer, 1);

        if (ch4_length_overflow == 1) {
            mmio.NR44.trigger = false;
        }
    }
}

const EnvelopeState = struct {
    counter: u3 = 0,
    volume: u4 = 0,
};

fn tick_envelope_sweep(state: *EnvelopeState, envelope: MMIO_EnvelopeProperties) void {
    if (envelope.sweep_pace != 0) // Envelope is enabled
    {
        state.counter, const overflow = @subWithOverflow(state.counter, 1);

        if (overflow == 1) {
            switch (envelope.envelope_direction) {
                // FIXME
                .DecreaseVolume => {
                    state.volume -|= 1;
                },
                .IncreaseVolume => {
                    state.volume +|= 1;
                },
            }
            state.counter = envelope.sweep_pace - 1;
        }
    }
}

fn tick_period_sweep(ch1: *CH1State, mmio: *MMIO) void {
    const period_delta = mmio.NR13_NR14.period >> mmio.NR10.step;
    _, const period_would_overflow = @addWithOverflow(mmio.NR13_NR14.period, period_delta);

    // Weird quirk
    // https://gbdev.io/pandocs/Audio_Registers.html#ff10--nr10-channel-1-sweep
    if (period_would_overflow == 1) {
        mmio.NR13_NR14.trigger = false;
        return;
    }

    if (mmio.NR10.sweep_pace != 0) // Frequency sweep is enabled
    {
        ch1.period_sweep_counter, const overflow_sweep_count = @subWithOverflow(ch1.period_sweep_counter, 1);

        if (overflow_sweep_count == 1) {
            switch (mmio.NR10.direction) {
                .Add => {
                    mmio.NR13_NR14.period += period_delta;
                },
                .Sub => {
                    mmio.NR13_NR14.period -= period_delta;
                },
            }

            ch1.period_sweep_counter = mmio.NR10.sweep_pace - 1;
        }
    }
}

const LFSR = packed union {
    mask: u16,
    bits: packed struct {
        bit0: u1,
        bit1: u1,
        _unused_bit2_6: u5,
        bit7: u1,
        _unused_bit8_14: u7,
        bit15: u1,
    },
};

fn tick_lfsr(lfsr: *LFSR, mmio: *const MMIO) void {
    const new_bit = ~(lfsr.bits.bit0 ^ lfsr.bits.bit1);

    lfsr.bits.bit15 = new_bit;

    if (mmio.NR43.lfsr_width == .Short) {
        lfsr.bits.bit7 = new_bit;
    }

    lfsr.mask >>= 1;
}

fn generate_channel1_sample(mmio: *const MMIO, dac_enabled: bool) u4 {
    const channel_enabled = dac_enabled and mmio.NR52.enable.channel1;
    const channel_active = channel_enabled and mmio.NR13_NR14.trigger and (!mmio.NR13_NR14.enable_length_timer or mmio.NR11.length_timer > 0);

    if (!channel_active) {
        return ChannelOffSample;
    }

    const sample: u4 = 0; // FIXME

    return sample;
}

fn convert_generated_sample_to_float(sample: u4, dac_enabled: bool) f32 {
    if (dac_enabled) {
        return (@as(f32, @floatFromInt(sample)) / 15.0) * -2.0 + 1.0;
    } else {
        return 0.0; // FIXME Needs to be smoothed out over time
    }
}

// Retuns a stereo signal in [-4.0:4.0]
fn mix_channel_samples(mmio: *const MMIO, channel_samples_vec: f32_4) StereoSample {
    const zero_vec: f32_4 = @splat(0.0);

    const enable_r_vec = convert_per_channel_bool_to_vec(mmio.NR51.enable_r);
    const enable_l_vec = convert_per_channel_bool_to_vec(mmio.NR51.enable_l);

    // For each R/L side, choose between each channel sample or silence, then sum over all channels.
    var mix_r = @reduce(.Add, @select(f32, enable_r_vec, channel_samples_vec, zero_vec));
    var mix_l = @reduce(.Add, @select(f32, enable_l_vec, channel_samples_vec, zero_vec));

    // Apply per-channel volume
    // No muting is possible at this stage
    mix_r *= convert_channel_volume_to_float(mmio.NR50.volume_r);
    mix_l *= convert_channel_volume_to_float(mmio.NR50.volume_l);

    return .{ mix_r, mix_l };
}

fn convert_per_channel_bool_to_vec(s: PerChannelBool) @Vector(4, bool) {
    return .{ s.channel1, s.channel2, s.channel3, s.channel4 };
}

fn convert_channel_volume_to_float(volume: u3) f32 {
    return (@as(f32, @floatFromInt(volume)) + 1.0) / 8.0;
}

const ChannelOffSample = 0;

// 0 = R
// 1 = L
const StereoSample = f32_2;

const f32_2 = @Vector(2, f32);
const f32_4 = @Vector(4, f32);

pub const MMIO = packed struct {
    // Channel 1
    NR10: packed struct { // 0x10 Channel 1 Sweep register (R/W)
        step: u3,
        direction: enum(u1) {
            Add = 0,
            Sub = 1,
        },
        sweep_pace: u3,
        _unused: u1,
    },
    NR11: PulseLengthAndDuty, // 0x11 Channel 1 Sound length/Wave pattern duty (R/W)
    NR12: ChannelEnvelope, // 0x12 Channel 1 Volume Envelope (R/W)
    NR13_NR14: ChannelControlAndFrequency, // 0x13 0x14 Channel 1
    // Channel 2
    NR20: u8, // Unused
    NR21: PulseLengthAndDuty, // 0x16 Channel 2 Sound Length/Wave Pattern Duty (R/W)
    NR22: ChannelEnvelope, // 0x17 Channel 2 Volume Envelope (R/W)
    NR23_NR24: ChannelControlAndFrequency, // 0x18 0x19 Channel 2
    // Channel 3
    NR30: packed struct { // 0x1A Channel 3 Sound on/off (R/W)
        _unused: u7,
        enable_dac: bool,
    },
    NR31: packed struct { // 0x1B Channel 3 Sound Length
        length_timer: u8,
    },
    NR32: packed struct { // 0x1C Channel 3 Select output level (R/W)
        _unused0: u5,
        output_level: enum(u2) {
            Mute = 0,
            Volume100pcts = 1,
            Volume50pcts = 2,
            Volume25pcts = 3,
        },
        _unused1: u1,
    },
    NR33_NR34: ChannelControlAndFrequency, // 0x1E 0x1D Channel 3
    // Channel 4
    NR40: u8, // Unused
    NR41: packed struct { // 0x20 Channel 4 Sound Length (R/W)
        length_timer: u6,
        _unused: u2,
    },
    NR42: ChannelEnvelope, // 0x21 Channel 4 Volume Envelope (R/W)
    NR43: packed struct { // 0x22 Channel 4 Polynomial Counter (R/W)
        clock_divider: u3,
        lfsr_width: enum(u1) {
            Long = 0,
            Short = 1,
        },
        clock_shift: u4,
    },
    NR44: packed struct { // 0x23 Channel 4 Counter/consecutive, Inital (R/W)
        _unused: u6,
        enable_length_timer: bool,
        trigger: bool,
    },
    // Misc
    NR50: packed struct { // 0x24 Channel control / ON-OFF / Volume (R/W)
        volume_r: u3,
        enable_vin_r: bool,
        volume_l: u3,
        enable_vin_l: bool,
    },
    NR51: packed struct { // 0x25 Selection of Sound output terminal (R/W)
        enable_r: PerChannelBool,
        enable_l: PerChannelBool,
    },
    NR52: packed struct { // 0x26 Audio master control
        enable: PerChannelBool,
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
    // Channel 3
    WAV_PATTERN_0: u32, // 0x30 Wave pattern
    WAV_PATTERN_1: u32,
    WAV_PATTERN_2: u32,
    WAV_PATTERN_3: u32,
};

const PulseLengthAndDuty = packed struct {
    length_timer: u6,
    wave_duty: u2,
};

const ChannelControlAndFrequency = packed struct {
    period: u11,
    _unused: u3,
    enable_length_timer: bool,
    trigger: bool,
};

const ChannelEnvelope = packed union {
    envelope: MMIO_EnvelopeProperties,
    enable_dac: packed struct {
        _unused: u3,
        mask: u5,
    },
};

const MMIO_EnvelopeProperties = packed struct {
    sweep_pace: u3,
    envelope_direction: enum(u1) {
        DecreaseVolume = 0,
        IncreaseVolume = 1,
    },
    initial_volume: u4,
};

const PerChannelBool = packed struct {
    channel1: bool,
    channel2: bool,
    channel3: bool,
    channel4: bool,
};

comptime {
    assert(@sizeOf(MMIO) == 0x30);
}
