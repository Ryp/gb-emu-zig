const std = @import("std");
const assert = std.debug.assert;

const cpu_state = @import("cpu.zig");
const GBState = cpu_state.GBState;
const CPUState = cpu_state.CPUState;

const instructions = @import("instructions.zig");
const R16 = instructions.R16;

pub fn execute_instruction(gb: *GBState, instruction: instructions.Instruction) void {
    switch (instruction.encoding) {
        .nop => execute_nop(gb),
        .ld_r16_imm16 => |i| execute_ld_r16_imm16(gb, i),
        .ld_r16mem_a => |i| execute_ld_r16mem_a(gb, i),
        .ld_a_r16mem => |i| execute_ld_a_r16mem(gb, i),
        .ld_imm16_sp => |i| execute_ld_imm16_sp(gb, i),
        .inc_r16 => |i| execute_inc_r16(gb, i),
        .dec_r16 => |i| execute_dec_r16(gb, i),
        .add_hl_r16 => |i| execute_add_hl_r16(gb, i),
        .inc_r8 => |i| execute_inc_r8(gb, i),
        .dec_r8 => |i| execute_dec_r8(gb, i),
        .ld_r8_imm8 => |i| execute_ld_r8_imm8(gb, i),
        .rlca => execute_rlca(gb),
        .rrca => execute_rrca(gb),
        .rla => execute_rla(gb),
        .rra => execute_rra(gb),
        .daa => execute_daa(gb),
        .cpl => execute_cpl(gb),
        .scf => execute_scf(gb),
        .ccf => execute_ccf(gb),
        .jr_imm8 => |i| execute_jr_imm8(gb, i),
        .jr_cond_imm8 => |i| execute_jr_cond_imm8(gb, i),
        .stop => execute_stop(gb),
        .ld_r8_r8 => |i| execute_ld_r8_r8(gb, i),
        .halt => execute_halt(gb),
        .add_a_r8 => |i| execute_add_a_r8(gb, i),
        .adc_a_r8 => |i| execute_adc_a_r8(gb, i),
        .sub_a_r8 => |i| execute_sub_a_r8(gb, i),
        .sbc_a_r8 => |i| execute_sbc_a_r8(gb, i),
        .and_a_r8 => |i| execute_and_a_r8(gb, i),
        .xor_a_r8 => |i| execute_xor_a_r8(gb, i),
        .or_a_r8 => |i| execute_or_a_r8(gb, i),
        .cp_a_r8 => |i| execute_cp_a_r8(gb, i),
        .add_a_imm8 => |i| execute_add_a_imm8(gb, i),
        .adc_a_imm8 => |i| execute_adc_a_imm8(gb, i),
        .sub_a_imm8 => |i| execute_sub_a_imm8(gb, i),
        .sbc_a_imm8 => |i| execute_sbc_a_imm8(gb, i),
        .and_a_imm8 => |i| execute_and_a_imm8(gb, i),
        .xor_a_imm8 => |i| execute_xor_a_imm8(gb, i),
        .or_a_imm8 => |i| execute_or_a_imm8(gb, i),
        .cp_a_imm8 => |i| execute_cp_a_imm8(gb, i),
        .ret_cond => |i| execute_ret_cond(gb, i),
        .ret => execute_ret(gb),
        .reti => execute_reti(gb),
        .jp_cond_imm16 => |i| execute_jp_cond_imm16(gb, i),
        .jp_imm16 => |i| execute_jp_imm16(gb, i),
        .jp_hl => execute_jp_hl(gb),
        .call_cond_imm16 => |i| execute_call_cond_imm16(gb, i),
        .call_imm16 => |i| execute_call_imm16(gb, i),
        .rst_tgt3 => |i| execute_rst_tgt3(gb, i),
        .pop_r16stk => |i| execute_pop_r16stk(gb, i),
        .push_r16stk => |i| execute_push_r16stk(gb, i),
        .ldh_c_a => execute_ldh_c_a(gb),
        .ldh_imm8_a => |i| execute_ldh_imm8_a(gb, i),
        .ld_imm16_a => |i| execute_ld_imm16_a(gb, i),
        .ldh_a_c => execute_ldh_a_c(gb),
        .ldh_a_imm8 => |i| execute_ldh_a_imm8(gb, i),
        .ld_a_imm16 => |i| execute_ld_a_imm16(gb, i),
        .add_sp_imm8 => |i| execute_add_sp_imm8(gb, i),
        .ld_hl_sp_plus_imm8 => |i| execute_ld_hl_sp_plus_imm8(gb, i),
        .ld_sp_hl => execute_ld_sp_hl(gb),
        .di => execute_di(gb),
        .ei => execute_ei(gb),
        .rlc_r8 => |i| execute_rlc_r8(gb, i),
        .rrc_r8 => |i| execute_rrc_r8(gb, i),
        .rl_r8 => |i| execute_rl_r8(gb, i),
        .rr_r8 => |i| execute_rr_r8(gb, i),
        .sla_r8 => |i| execute_sla_r8(gb, i),
        .sra_r8 => |i| execute_sra_r8(gb, i),
        .swap_r8 => |i| execute_swap_r8(gb, i),
        .srl_r8 => |i| execute_srl_r8(gb, i),
        .bit_b3_r8 => |i| execute_bit_b3_r8(gb, i),
        .res_b3_r8 => |i| execute_res_b3_r8(gb, i),
        .set_b3_r8 => |i| execute_set_b3_r8(gb, i),
        .invalid => execute_invalid_instruction(gb),
    }
}

fn execute_nop(gb: *GBState) void {
    _ = gb; // FIXME Do nothing
}

fn execute_ld_r16_imm16(gb: *GBState, instruction: instructions.ld_r16_imm16) void {
    store_r16(&gb.cpu, instruction.r16, instruction.imm16);
}

fn execute_ld_r16mem_a(gb: *GBState, instruction: instructions.ld_r16mem_a) void {
    const r16mem = instruction.r16mem;
    const address = load_r16(gb.cpu, r16mem.r16);

    gb.mem[address] = gb.cpu.a;

    if (r16mem.r16 == R16.hl) {
        increment_hl(&gb.cpu, r16mem.increment);
    }
}

fn execute_ld_a_r16mem(gb: *GBState, instruction: instructions.ld_a_r16mem) void {
    const r16mem = instruction.r16mem;
    const address = load_r16(gb.cpu, r16mem.r16);

    gb.cpu.a = gb.mem[address];

    if (r16mem.r16 == R16.hl) {
        increment_hl(&gb.cpu, r16mem.increment);
    }
}

fn execute_ld_imm16_sp(gb: *GBState, instruction: instructions.ld_imm16_sp) void {
    const address = instruction.imm16;

    store_u16(&gb.mem[address], &gb.mem[address + 1], gb.cpu.sp);
}

fn execute_inc_r16(gb: *GBState, instruction: instructions.inc_r16) void {
    const value = load_r16(gb.cpu, instruction.r16);

    // FIXME flags?
    store_r16(&gb.cpu, instruction.r16, value +% 1);
}

fn execute_dec_r16(gb: *GBState, instruction: instructions.dec_r16) void {
    const value = load_r16(gb.cpu, instruction.r16);

    // FIXME flags?
    store_r16(&gb.cpu, instruction.r16, value -% 1);
}

fn execute_add_hl_r16(gb: *GBState, instruction: instructions.add_hl_r16) void {
    const add = load_r16(gb.cpu, instruction.r16);
    const hl = load_r16(gb.cpu, R16.hl);
    const result = hl + add;

    // FIXME flags?
    store_r16(&gb.cpu, R16.hl, result);
}

fn execute_inc_r8(gb: *GBState, instruction: instructions.inc_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_dec_r8(gb: *GBState, instruction: instructions.dec_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_ld_r8_imm8(gb: *GBState, instruction: instructions.ld_r8_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_rlca(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_rrca(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_rla(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_rra(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_daa(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_cpl(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_scf(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_ccf(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_jr_imm8(gb: *GBState, instruction: instructions.jr_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_jr_cond_imm8(gb: *GBState, instruction: instructions.jr_cond_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_stop(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_ld_r8_r8(gb: *GBState, instruction: instructions.ld_r8_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_halt(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_add_a_r8(gb: *GBState, instruction: instructions.add_a_r8) void {
    const r8_value = load_r8(gb.*, instruction.r8); // FIXME

    gb.cpu.a += r8_value;
}

fn execute_adc_a_r8(gb: *GBState, instruction: instructions.adc_a_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_sub_a_r8(gb: *GBState, instruction: instructions.sub_a_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_sbc_a_r8(gb: *GBState, instruction: instructions.sbc_a_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_and_a_r8(gb: *GBState, instruction: instructions.and_a_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_xor_a_r8(gb: *GBState, instruction: instructions.xor_a_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_or_a_r8(gb: *GBState, instruction: instructions.or_a_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_cp_a_r8(gb: *GBState, instruction: instructions.cp_a_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_add_a_imm8(gb: *GBState, instruction: instructions.add_a_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_adc_a_imm8(gb: *GBState, instruction: instructions.adc_a_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_sub_a_imm8(gb: *GBState, instruction: instructions.sub_a_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_sbc_a_imm8(gb: *GBState, instruction: instructions.sbc_a_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_and_a_imm8(gb: *GBState, instruction: instructions.and_a_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_xor_a_imm8(gb: *GBState, instruction: instructions.xor_a_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_or_a_imm8(gb: *GBState, instruction: instructions.or_a_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_cp_a_imm8(gb: *GBState, instruction: instructions.cp_a_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_ret_cond(gb: *GBState, instruction: instructions.ret_cond) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_ret(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_reti(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_jp_cond_imm16(gb: *GBState, instruction: instructions.jp_cond_imm16) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_jp_imm16(gb: *GBState, instruction: instructions.jp_imm16) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_jp_hl(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_call_cond_imm16(gb: *GBState, instruction: instructions.call_cond_imm16) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_call_imm16(gb: *GBState, instruction: instructions.call_imm16) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_rst_tgt3(gb: *GBState, instruction: instructions.rst_tgt3) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_pop_r16stk(gb: *GBState, instruction: instructions.pop_r16stk) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_push_r16stk(gb: *GBState, instruction: instructions.push_r16stk) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_ldh_c_a(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_ldh_imm8_a(gb: *GBState, instruction: instructions.ldh_imm8_a) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_ld_imm16_a(gb: *GBState, instruction: instructions.ld_imm16_a) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_ldh_a_c(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_ldh_a_imm8(gb: *GBState, instruction: instructions.ldh_a_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_ld_a_imm16(gb: *GBState, instruction: instructions.ld_a_imm16) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_add_sp_imm8(gb: *GBState, instruction: instructions.add_sp_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_ld_hl_sp_plus_imm8(gb: *GBState, instruction: instructions.ld_hl_sp_plus_imm8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_ld_sp_hl(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_di(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_ei(gb: *GBState) void {
    _ = gb; // FIXME
}

fn execute_rlc_r8(gb: *GBState, instruction: instructions.rlc_r8) void {
    const r8_value = load_r8(gb.*, instruction.r8);
    const highest_bit_set = (r8_value & 0x80) != 0;

    const result = std.math.rotl(u8, r8_value, 1);

    store_r8(gb, instruction.r8, result);

    reset_flags(&gb.cpu);
    set_carry_flag(&gb.cpu, highest_bit_set);
    set_zero_flag(&gb.cpu, result == 0);
}

fn execute_rrc_r8(gb: *GBState, instruction: instructions.rrc_r8) void {
    const r8_value = load_r8(gb.*, instruction.r8);
    const lowest_bit_set = (r8_value & 0x01) != 0;

    const result = std.math.rotr(u8, r8_value, 1);

    store_r8(gb, instruction.r8, result);

    reset_flags(&gb.cpu);
    set_carry_flag(&gb.cpu, lowest_bit_set);
    set_zero_flag(&gb.cpu, result == 0);
}

fn execute_rl_r8(gb: *GBState, instruction: instructions.rl_r8) void {
    const r8_value = load_r8(gb.*, instruction.r8);
    const highest_bit_set = (r8_value & 0x80) != 0;

    const result = r8_value << 1 | gb.cpu.flags.carry;

    store_r8(gb, instruction.r8, result);

    reset_flags(&gb.cpu);
    set_carry_flag(&gb.cpu, highest_bit_set);
    set_zero_flag(&gb.cpu, result == 0);
}

fn execute_rr_r8(gb: *GBState, instruction: instructions.rr_r8) void {
    const r8_value = load_r8(gb.*, instruction.r8);
    const lowest_bit_set = (r8_value & 0x01) != 0;

    const result = r8_value >> 1 | @as(u8, gb.cpu.flags.carry) << 7;

    store_r8(gb, instruction.r8, result);

    reset_flags(&gb.cpu);
    set_carry_flag(&gb.cpu, lowest_bit_set);
    set_zero_flag(&gb.cpu, result == 0);
}

fn execute_sla_r8(gb: *GBState, instruction: instructions.sla_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_sra_r8(gb: *GBState, instruction: instructions.sra_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_swap_r8(gb: *GBState, instruction: instructions.swap_r8) void {
    const r8_value = load_r8(gb.*, instruction.r8);
    const result = (r8_value & 0x0F << 4) | r8_value >> 4;

    store_r8(gb, instruction.r8, result);
}

fn execute_srl_r8(gb: *GBState, instruction: instructions.srl_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_bit_b3_r8(gb: *GBState, instruction: instructions.bit_b3_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_res_b3_r8(gb: *GBState, instruction: instructions.res_b3_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_set_b3_r8(gb: *GBState, instruction: instructions.set_b3_r8) void {
    _ = gb; // FIXME
    _ = instruction;
}

fn execute_invalid_instruction(gb: *GBState) void {
    assert(gb.running);
    assert(false);

    gb.running = false;
}

fn load_r8(gb: GBState, r8: instructions.R8) u8 {
    return switch (r8) {
        .b => gb.cpu.b,
        .c => gb.cpu.c,
        .d => gb.cpu.d,
        .e => gb.cpu.e,
        .h => gb.cpu.h,
        .l => gb.cpu.l,
        .hl_p => gb.mem[load_r16(gb.cpu, R16.hl)],
        .a => gb.cpu.l,
    };
}

fn store_r8(gb: *GBState, r8: instructions.R8, value: u8) void {
    switch (r8) {
        .b => {
            gb.cpu.b = value;
        },
        .c => {
            gb.cpu.c = value;
        },
        .d => {
            gb.cpu.d = value;
        },
        .e => {
            gb.cpu.e = value;
        },
        .h => {
            gb.cpu.h = value;
        },
        .l => {
            gb.cpu.l = value;
        },
        .hl_p => {
            gb.mem[load_r16(gb.cpu, R16.hl)] = value;
        },
        .a => {
            gb.cpu.l = value;
        },
    }
}

fn load_r16(cpu: CPUState, r16: R16) u16 {
    return switch (r16) {
        .bc => (@as(u16, @intCast(cpu.b)) << 8 | cpu.c),
        .de => (@as(u16, @intCast(cpu.d)) << 8 | cpu.e),
        .hl => (@as(u16, @intCast(cpu.h)) << 8 | cpu.l),
        .af => (@as(u16, @intCast(cpu.a)) << 8 | @as(u8, @bitCast(cpu.flags))),
        .sp => cpu.sp,
        .pc => cpu.pc,
    };
}

fn store_u16(hi: *u8, lo: *u8, value: u16) void {
    hi.* = @intCast(value >> 8);
    lo.* = @intCast(value & 0xff);
}

fn store_r16(cpu: *CPUState, r16: R16, value: u16) void {
    switch (r16) {
        .bc => {
            store_u16(&cpu.b, &cpu.c, value);
        },
        .de => {
            store_u16(&cpu.d, &cpu.e, value);
        },
        .hl => {
            store_u16(&cpu.h, &cpu.l, value);
        },
        .af => {
            var r8_f: u8 = undefined;
            store_u16(&cpu.a, &r8_f, value);
            cpu.flags = @bitCast(r8_f);
        },
        .sp => {
            cpu.sp = value;
        },
        .pc => {
            cpu.pc = value;
        },
    }
}

fn increment_hl(cpu: *CPUState, increment: bool) void {
    var hl_value = load_r16(cpu.*, R16.hl);

    // FIXME What happens to carry flags when this wraps around?
    // Let zig catch an exception since it doesn't look like this is supposed to happen anyway.
    if (increment) {
        hl_value += 1;
    } else {
        hl_value -= 1;
    }

    store_r16(cpu, R16.hl, hl_value);
}

fn reset_flags(cpu: *CPUState) void {
    cpu.flags = .{
        ._unused = 0,
        .carry = 0,
        .half_carry = 0,
        .substract = 0,
        .zero = 0,
    };
}

fn set_carry_flag(cpu: *CPUState, carry: bool) void {
    cpu.flags.carry = if (carry) 1 else 0;
}

fn set_half_carry_flag(cpu: *CPUState, half_carry: bool) void {
    cpu.flags.half_carry = if (half_carry) 1 else 0;
}

fn set_substract_flag(cpu: *CPUState, substract: bool) void {
    cpu.flags.substract = if (substract) 1 else 0;
}

fn set_zero_flag(cpu: *CPUState, zero: bool) void {
    cpu.flags.zero = if (zero) 1 else 0;
}
