const std = @import("std");
const assert = std.debug.assert;

const tracy = @import("../tracy.zig");

pub const APUState = struct {
    ch1: CH1State = .{},
    ch2: CH2State = .{},
    ch3: CH3State = .{},
    ch4: CH4State = .{},
};

const CH1State = struct {
    enabled: bool = false,
    period: PeriodState = .{},
    envelope: EnvelopeState = .{},
    period_sweep_counter: u3 = 0,
};

const CH2State = struct {
    enabled: bool = false,
    period: PeriodState = .{},
    envelope: EnvelopeState = .{},
};

const CH3State = struct {
    enabled: bool = false,
    period_counter: u11 = 0,
    sample_index: u5 = 0,
};

const CH4State = struct {
    enabled: bool = false,
    envelope: EnvelopeState = .{},
    lfsr: LFSR = .{ .mask = 0 },
    clock_counter: u3 = 0,
};

pub fn create_apu_state() APUState {
    return .{};
}

fn reset_apu(apu: *APUState) void {
    apu.* = create_apu_state();
}

// This function assumes that all ticks are only going to happen once per call.
// If you call this function after too many cycles passed, you will miss tick events
// and the APU will most likely output the wrong sound.
// NOTE: The calling order between tick update functions is important here since there's some data dependencies.
pub fn step_apu(apu: *APUState, mmio: *MMIO, clock_falling_edge_mask: u64, m_cycles_count: u8) void {
    const scope = tracy.trace(@src());
    defer scope.end();

    const tick_64hz: u1 = @truncate(clock_falling_edge_mask >> 15);
    const tick_128hz: u1 = @truncate(clock_falling_edge_mask >> 14);
    const tick_256hz: u1 = @truncate(clock_falling_edge_mask >> 13);
    const tick_lfsr_rate: u1 = @truncate(clock_falling_edge_mask >> (6 + mmio.NR43.clock_shift));

    if (tick_64hz == 1) {
        tick_envelope_sweep(apu.ch1.enabled, &apu.ch1.envelope, mmio.NR12.envelope);
        tick_envelope_sweep(apu.ch2.enabled, &apu.ch2.envelope, mmio.NR22.envelope);
        tick_envelope_sweep(apu.ch4.enabled, &apu.ch4.envelope, mmio.NR42.envelope);
    }

    if (tick_128hz == 1) {
        tick_period_sweep(&apu.ch1, mmio);
    }

    if (tick_256hz == 1) {
        tick_length_timers(apu, mmio);
    }

    if (tick_lfsr_rate == 1) {
        tick_lfsr(apu.ch4.enabled, &apu.ch4.lfsr, mmio);
    }

    // The tick rate is too high so we count M-cycles manually
    tick_period_counter(apu.ch1.enabled, &apu.ch1.period, mmio.NR13_NR14, m_cycles_count);
    tick_period_counter(apu.ch2.enabled, &apu.ch2.period, mmio.NR23_NR24, m_cycles_count);
    tick_period_counter_ch3(&apu.ch3, mmio.NR33_NR34, m_cycles_count);
}

pub const MMIO_OffsetBegin = NR10;
pub const MMIO_OffsetEndInclusive = WAV_END;

pub fn store_mmio_u8(apu: *APUState, mmio: *MMIO, mmio_bytes: []u8, offset: u8, value: u8) void {
    switch (offset) {
        NR12 => {
            mmio_bytes[offset] = value;
            update_channel1_dac(&apu.ch1, mmio);
        },
        NR22 => {
            mmio_bytes[offset] = value;
            update_channel2_dac(&apu.ch2, mmio);
        },
        NR30 => {
            mmio_bytes[offset] = value;
            update_channel3_dac(&apu.ch3, mmio);
        },
        NR42 => {
            mmio_bytes[offset] = value;
            update_channel4_dac(&apu.ch4, mmio);
        },
        NR14 => {
            mmio_bytes[offset] = value;
            trigger_channel1(&apu.ch1, mmio);
        },
        NR24 => {
            mmio_bytes[offset] = value;
            trigger_channel2(&apu.ch2, mmio);
        },
        NR34 => {
            mmio_bytes[offset] = value;
            trigger_channel3(&apu.ch3, mmio);
        },
        NR44 => {
            mmio_bytes[offset] = value;
            trigger_channel4(&apu.ch4, mmio);
        },
        NR52 => {
            // FIXME We should mask off the channel bits since they're read-only
            const apu_was_on = mmio.NR52.enable_apu;
            mmio_bytes[offset] = value;
            const apu_is_on = mmio.NR52.enable_apu;

            if (!apu_was_on and apu_is_on) {
                reset_apu(apu);
            }
        },
        else => mmio_bytes[offset] = value,
    }
}

pub fn load_mmio_u8(apu: *const APUState, mmio: *const MMIO, mmio_bytes: []u8, offset: u8) u8 {
    // FIXME Needed later for reading NR52 properly
    _ = apu;
    _ = mmio;

    switch (offset) {
        NR12, NR22, NR30, NR42 => return mmio_bytes[offset],
        NR14, NR24, NR34, NR44 => return mmio_bytes[offset],
        NR52 => return mmio_bytes[offset],
        else => return mmio_bytes[offset],
    }
}

pub fn sample_channels(apu: *APUState, mmio: *const MMIO) StereoSample {
    var channel_samples: [4]u4 = undefined;
    var channel_dac_enabled: [4]bool = undefined;

    channel_dac_enabled[0] = mmio.NR12.enable_dac.mask != 0;
    channel_dac_enabled[1] = mmio.NR22.enable_dac.mask != 0;
    channel_dac_enabled[2] = mmio.NR30.enable_dac;
    channel_dac_enabled[3] = mmio.NR42.enable_dac.mask != 0;

    channel_samples[0] = generate_channel1_sample(apu.ch1, mmio);
    channel_samples[1] = generate_channel2_sample(apu.ch2, mmio);
    channel_samples[2] = generate_channel3_sample(apu.ch3, mmio);
    channel_samples[3] = generate_channel4_sample(apu.ch4, mmio);

    var channel_samples_f32: [4]f32 = undefined;

    // DAC block
    // FIXME DAC can be disabled, how to handle this?
    for (&channel_samples_f32, channel_samples, channel_dac_enabled) |*sample_float, sample, dac_enabled| {
        sample_float.* = convert_generated_sample_to_float(sample, dac_enabled);
    }

    // Mixer block
    const mixed_sample = mix_channel_samples(mmio, channel_samples_f32);

    const normalized_sample = mixed_sample / @as(StereoSample, @splat(4.0));

    // FIXME Missing high-pass filter

    return normalized_sample;
}

// NOTE: This is called AFTER the new MMIO value was written
fn trigger_channel1(ch1: *CH1State, mmio: *MMIO) void {
    if (mmio.NR13_NR14.trigger) {
        ch1.enabled = true;

        ch1.period.counter = 0;

        ch1.envelope.volume = mmio.NR12.envelope.initial_volume;

        if (mmio.NR12.envelope.sweep_pace > 0) {
            ch1.envelope.counter = mmio.NR12.envelope.sweep_pace - 1;
        }

        if (mmio.NR10.sweep_pace > 0) {
            ch1.period_sweep_counter = mmio.NR10.sweep_pace - 1;
        }
    }
}

fn trigger_channel2(ch2: *CH2State, mmio: *MMIO) void {
    if (mmio.NR23_NR24.trigger) {
        ch2.enabled = true;

        ch2.period.counter = 0;

        ch2.envelope.volume = mmio.NR22.envelope.initial_volume;

        if (mmio.NR22.envelope.sweep_pace > 0) {
            ch2.envelope.counter = mmio.NR22.envelope.sweep_pace - 1;
        }
    }
}

fn trigger_channel3(ch3: *CH3State, mmio: *MMIO) void {
    if (mmio.NR33_NR34.trigger) {
        ch3.enabled = true;

        ch3.period_counter = 0;

        ch3.sample_index = 1;
    }
}

fn trigger_channel4(ch4: *CH4State, mmio: *MMIO) void {
    if (mmio.NR44.trigger) {
        ch4.enabled = true;

        ch4.envelope.volume = mmio.NR42.envelope.initial_volume;

        if (mmio.NR42.envelope.sweep_pace > 0) {
            ch4.envelope.counter = mmio.NR42.envelope.sweep_pace - 1;
        }
    }
}

// Turn off channels if the related DAC is off as well
fn update_channel1_dac(ch1: *CH1State, mmio: *MMIO) void {
    ch1.enabled = ch1.enabled and mmio.NR12.enable_dac.mask != 0;
}

fn update_channel2_dac(ch2: *CH2State, mmio: *MMIO) void {
    ch2.enabled = ch2.enabled and mmio.NR22.enable_dac.mask != 0;
}

fn update_channel3_dac(ch3: *CH3State, mmio: *MMIO) void {
    ch3.enabled = ch3.enabled and mmio.NR30.enable_dac;
}

fn update_channel4_dac(ch4: *CH4State, mmio: *MMIO) void {
    ch4.enabled = ch4.enabled and mmio.NR42.enable_dac.mask != 0;
}

fn tick_length_timers(apu: *APUState, mmio: *MMIO) void {
    if (apu.ch1.enabled and mmio.NR13_NR14.enable_length_timer) {
        mmio.NR11.length_timer, const overflow = @addWithOverflow(mmio.NR11.length_timer, 1);

        if (overflow == 1) {
            apu.ch1.enabled = false;
        }
    }

    if (apu.ch2.enabled and mmio.NR23_NR24.enable_length_timer) {
        mmio.NR21.length_timer, const overflow = @addWithOverflow(mmio.NR21.length_timer, 1);

        if (overflow == 1) {
            apu.ch2.enabled = false;
        }
    }

    if (apu.ch3.enabled and mmio.NR33_NR34.enable_length_timer) {
        // FIXME would overflow at 256 instead of 64 of the docs
        mmio.NR31.length_timer, const overflow = @addWithOverflow(mmio.NR31.length_timer, 1);

        if (overflow == 1) {
            apu.ch3.enabled = false;
        }
    }

    if (apu.ch4.enabled and mmio.NR44.enable_length_timer) {
        mmio.NR41.length_timer, const overflow = @addWithOverflow(mmio.NR41.length_timer, 1);

        if (overflow == 1) {
            apu.ch4.enabled = false;
        }
    }
}

const PeriodState = struct {
    counter: u11 = 0,
    duty_index: u3 = 0,
};

// NOTE: should be updated after period sweep
fn tick_period_counter(channel_enabled: bool, state: *PeriodState, mmio_frequency: MMIO_ChannelControlAndFrequency, m_cycles_count: u8) void {
    for (0..m_cycles_count) |_| {
        if (channel_enabled) {
            state.counter, const overflow = @addWithOverflow(state.counter, 1);

            if (overflow == 1) {
                state.counter = mmio_frequency.period;
                state.duty_index +%= 1;
            }
        }
    }
}

fn tick_period_counter_ch3(ch3: *CH3State, mmio_frequency: MMIO_ChannelControlAndFrequency, m_cycles_count: u8) void {
    for (0..m_cycles_count) |_| {
        if (ch3.enabled) {
            ch3.period_counter, const overflow = @addWithOverflow(ch3.period_counter, 2);

            if (overflow == 1) {
                ch3.period_counter = mmio_frequency.period;
                ch3.sample_index +%= 1;
            }
        }
    }
}

const EnvelopeState = struct {
    counter: u3 = 0,
    volume: u4 = 0,
};

fn tick_envelope_sweep(channel_enabled: bool, state: *EnvelopeState, mmio_envelope: MMIO_EnvelopeProperties) void {
    if (channel_enabled and mmio_envelope.sweep_pace != 0) // Envelope is enabled
    {
        state.counter, const overflow = @subWithOverflow(state.counter, 1);

        if (overflow == 1) {
            switch (mmio_envelope.envelope_direction) {
                // FIXME
                .DecreaseVolume => {
                    state.volume -|= 1;
                },
                .IncreaseVolume => {
                    state.volume +|= 1;
                },
            }
            state.counter = mmio_envelope.sweep_pace - 1;
        }
    }
}

// _, const period_would_overflow = @addWithOverflow(mmio.NR13_NR14.period, period_delta);
// Weird quirk
// https://gbdev.io/pandocs/Audio_Registers.html#ff10--nr10-channel-1-sweep
// if (mmio.NR10.direction == .Add and period_would_overflow == 1) {
//     ch1.enabled = false; // FIXME this is broken!
//     return;
// }
fn tick_period_sweep(ch1: *CH1State, mmio: *MMIO) void {
    if (ch1.enabled) {
        const period_delta = mmio.NR13_NR14.period >> mmio.NR10.step;

        if (mmio.NR10.sweep_pace != 0) // Frequency sweep is enabled
        {
            ch1.period_sweep_counter, const overflow_sweep_count = @subWithOverflow(ch1.period_sweep_counter, 1);

            if (overflow_sweep_count == 1) {
                switch (mmio.NR10.direction) {
                    .Add => {
                        _, const overflow_period = @addWithOverflow(mmio.NR13_NR14.period, period_delta);
                        if (overflow_period == 1) {
                            ch1.enabled = false;
                        } else {
                            mmio.NR13_NR14.period += period_delta;
                        }
                    },
                    .Sub => {
                        mmio.NR13_NR14.period -= period_delta;
                    },
                }

                ch1.period_sweep_counter = mmio.NR10.sweep_pace - 1;
            }
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

fn tick_lfsr(channel_enabled: bool, lfsr: *LFSR, mmio: *const MMIO) void {
    if (channel_enabled) {
        const new_bit = ~(lfsr.bits.bit0 ^ lfsr.bits.bit1);

        lfsr.bits.bit15 = new_bit;

        if (mmio.NR43.lfsr_width == .Short) {
            lfsr.bits.bit7 = new_bit;
        }

        lfsr.mask >>= 1;
    }
}

fn generate_channel1_sample(ch1: CH1State, mmio: *const MMIO) u4 {
    const channel_active = ch1.enabled and (!mmio.NR13_NR14.enable_length_timer or mmio.NR11.length_timer > 0);

    if (!channel_active) {
        return ChannelOffSample;
    }

    return DutyCycles[mmio.NR11.wave_duty][ch1.period.duty_index] * ch1.envelope.volume;
}

fn generate_channel2_sample(ch2: CH2State, mmio: *const MMIO) u4 {
    const channel_active = ch2.enabled and (!mmio.NR23_NR24.enable_length_timer or mmio.NR21.length_timer > 0);

    if (!channel_active) {
        return ChannelOffSample;
    }

    return DutyCycles[mmio.NR21.wave_duty][ch2.period.duty_index] * ch2.envelope.volume;
}

const DutyCycles: [4][8]u1 = .{
    .{ 1, 1, 1, 1, 1, 1, 1, 0 }, // 12.5%
    .{ 0, 1, 1, 1, 1, 1, 1, 0 }, // 25%
    .{ 0, 1, 1, 1, 1, 0, 0, 0 }, // 50%
    .{ 1, 0, 0, 0, 0, 0, 0, 1 }, // 75%
};

fn generate_channel3_sample(ch3: CH3State, mmio: *const MMIO) u4 {
    const channel_active = ch3.enabled and (!mmio.NR33_NR34.enable_length_timer or mmio.NR31.length_timer > 0);

    if (!channel_active) {
        return ChannelOffSample;
    }

    const wave_mmio_bytes = std.mem.asBytes(mmio)[WAV_START - MMIO_OffsetBegin .. WAV_END + 1 - MMIO_OffsetBegin];

    const wave_sample_byte = wave_mmio_bytes[ch3.sample_index / 2];
    const wave_sample_nibble: u4 = if (ch3.sample_index % 2 == 0) @truncate(wave_sample_byte >> 4) else @truncate(wave_sample_byte);

    const sample = switch (mmio.NR32.output_level) {
        .Mute => 0,
        .Volume100pcts => wave_sample_nibble,
        .Volume50pcts => wave_sample_nibble >> 1,
        .Volume25pcts => wave_sample_nibble >> 2,
    };

    return sample;
}

fn generate_channel4_sample(ch4: CH4State, mmio: *const MMIO) u4 {
    const channel_active = ch4.enabled and (!mmio.NR44.enable_length_timer or mmio.NR41.length_timer > 0);

    if (!channel_active) {
        return ChannelOffSample;
    }

    return ch4.lfsr.bits.bit0 * ch4.envelope.volume;
}

fn convert_generated_sample_to_float(sample: u4, dac_enabled: bool) f32 {
    if (dac_enabled) {
        return (@as(f32, @floatFromInt(sample)) / 15.0) * -2.0 + 1.0;
    } else {
        return 0.0; // FIXME Needs to be smoothed out over time
    }
}

// Returns a stereo signal in [-4.0:4.0]
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

fn convert_per_channel_bool_to_vec(s: MMIO_PerChannelBool) @Vector(4, bool) {
    return .{ s.channel1, s.channel2, s.channel3, s.channel4 };
}

fn convert_channel_volume_to_float(volume: u3) f32 {
    return (@as(f32, @floatFromInt(volume)) + 1.0) / 8.0;
}

const ChannelOffSample = 0;

// 0 = R
// 1 = L
pub const StereoSample = f32_2;

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
    NR11: MMIO_PulseLengthAndDuty, // 0x11 Channel 1 Sound length/Wave pattern duty (R/W)
    NR12: MMIO_ChannelEnvelope, // 0x12 Channel 1 Volume Envelope (R/W)
    NR13_NR14: MMIO_ChannelControlAndFrequency, // 0x13 0x14 Channel 1
    // Channel 2
    NR20: u8, // Unused
    NR21: MMIO_PulseLengthAndDuty, // 0x16 Channel 2 Sound Length/Wave Pattern Duty (R/W)
    NR22: MMIO_ChannelEnvelope, // 0x17 Channel 2 Volume Envelope (R/W)
    NR23_NR24: MMIO_ChannelControlAndFrequency, // 0x18 0x19 Channel 2
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
    NR33_NR34: MMIO_ChannelControlAndFrequency, // 0x1E 0x1D Channel 3
    // Channel 4
    NR40: u8, // Unused
    NR41: packed struct { // 0x20 Channel 4 Sound Length (R/W)
        length_timer: u6,
        _unused: u2,
    },
    NR42: MMIO_ChannelEnvelope, // 0x21 Channel 4 Volume Envelope (R/W)
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
        enable_r: MMIO_PerChannelBool,
        enable_l: MMIO_PerChannelBool,
    },
    NR52: packed struct { // 0x26 Audio master control
        enabled: MMIO_PerChannelBool, // FIXME Read-only
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

const MMIO_PulseLengthAndDuty = packed struct {
    length_timer: u6,
    wave_duty: u2,
};

const MMIO_ChannelControlAndFrequency = packed struct {
    period: u11,
    _unused: u3,
    enable_length_timer: bool,
    trigger: bool,
};

const MMIO_ChannelEnvelope = packed union {
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

const MMIO_PerChannelBool = packed struct {
    channel1: bool,
    channel2: bool,
    channel3: bool,
    channel4: bool,
};

comptime {
    assert(@sizeOf(MMIO) == 0x30);
}

// MMIO Offsets
const NR10 = 0x10; // Channel 1 Sweep register (R/W)
// NR11       = 0x11, // Channel 1 Sound length/Wave pattern duty (R/W)
const NR12 = 0x12; // Channel 1 Volume Envelope (R/W)
// NR13       = 0x13, // Channel 1 Frequency lo (Write Only)
const NR14 = 0x14; // Channel 1 Frequency hi (R/W)
// NR21      = 0x16, // Channel 2 Sound Length/Wave Pattern Duty (R/W)
const NR22 = 0x17; // Channel 2 Volume Envelope (R/W)
// NR23      = 0x18, // Channel 2 Frequency lo data (W)
const NR24 = 0x19; // Channel 2 Frequency hi data (R/W)
const NR30 = 0x1A; // Channel 3 Sound on/off (R/W)
// NR31      = 0x1B, // Channel 3 Sound Length
// NR32      = 0x1C, // Channel 3 Select output level (R/W)
// NR33      = 0x1D, // Channel 3 Frequency's lower data (W)
const NR34 = 0x1E; // Channel 3 Frequency's higher data (R/W)
// NR41      = 0x20, // Channel 4 Sound Length (R/W)
const NR42 = 0x21; // Channel 4 Volume Envelope (R/W)
// NR43      = 0x22, // Channel 4 Polynomial Counter (R/W)
const NR44 = 0x23; // Channel 4 Counter/consecutive, Inital (R/W)
// NR50      = 0x24, // Channel control / ON-OFF / Volume (R/W)
// NR51      = 0x25, // Selection of Sound output terminal (R/W)
const NR52 = 0x26; // Audio master control
const WAV_START = 0x30; // Wave pattern start
const WAV_END = 0x3F; // Wave pattern end
