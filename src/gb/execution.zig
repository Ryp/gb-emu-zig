const std = @import("std");
const assert = std.debug.assert;

const cpu = @import("cpu.zig");
const GBState = cpu.GBState;
const Registers = cpu.Registers;

const instructions = @import("instructions.zig");
const R8 = instructions.R8;
const R16 = instructions.R16;

const lcd = @import("lcd.zig");
const joypad = @import("joypad.zig");

const enable_debug = false;

pub fn step(gb: *GBState) !void {
    joypad.update_state(gb);

    // Service interrupts
    const interrupt_mask_to_service = gb.mmio.IF.requested_interrupts_mask & gb.mmio.IE.enable_interrupts_mask;

    if (gb.enable_interrupts_master and interrupt_mask_to_service != 0) {
        const interrupt_bit_index = @ctz(interrupt_mask_to_service); // First set bit gets priority
        const interrupt_bit_mask: u5 = @intCast(@as(u16, 1) << interrupt_bit_index);
        const interrupt_jump_address: u8 = 0x40 + @as(u8, interrupt_bit_index) * 0x08;

        gb.mmio.IF.requested_interrupts_mask &= ~interrupt_bit_mask; // Mark current interrupt as serviced
        gb.enable_interrupts_master = false; // Disable interrupts while we service them

        if (enable_debug) {
            std.debug.print("==== INTERRUPT ==== INTERRUPT ==== INTERRUPT ==== INTERRUPT ==== INTERRUPT ==== INTERRUPT ==== INTERRUPT ==== INTERRUPT ==== INTERRUPT ==== INTERRUPT ====\n", .{});
        }

        execute_interrupt(gb, interrupt_jump_address);
    }

    // Execute instructions
    const current_instruction = try instructions.decode(gb.memory[gb.registers.pc..]);

    if (enable_debug) {
        print_register_debug(gb.registers);
        std.debug.print(" | KEYS {b:0>8} JOYP {b:0>8}", .{ @as(u8, @bitCast(gb.keys)), @as(u8, @bitCast(gb.mmio.JOYP)) });
        std.debug.print(" | IME {b} IE {b:0>5} IF {b:0>5} STAT {b:0>8}", .{ @as(u1, if (gb.enable_interrupts_master) 1 else 0), gb.mmio.IE.enable_interrupts_mask, gb.mmio.IF.requested_interrupts_mask, @as(u8, @bitCast(gb.mmio.lcd.STAT)) });

        const i_mem = gb.memory[gb.registers.pc .. gb.registers.pc + current_instruction.byte_len];
        std.debug.print(" | {b:0>8} {x:0>2}", .{ i_mem, i_mem });

        instructions.debug_print(current_instruction);
    }

    // Normally this would take some cycles to complete, but we take this into account
    // a tiny bit later.
    gb.registers.pc += current_instruction.byte_len;

    execute_instruction(gb, current_instruction);

    assert(gb.registers.pc < 0x8000 or gb.registers.pc > 0xff80);
    assert(gb.registers.sp >= 0x8000);

    // We're decoding all instructions fully before executing them.
    // Each byte read actually makes the CPU spin another 4 cycles, so we can just
    // add them here after the fact
    gb.pending_cycles += @as(u8, current_instruction.byte_len) * 4;

    consume_pending_cycles(gb);
}

fn consume_pending_cycles(gb: *GBState) void {
    gb.total_cycles += gb.pending_cycles;

    if (gb.pending_cycles > 0) {
        lcd.step_pixel_processing_unit(gb, gb.pending_cycles);
    }

    gb.pending_cycles = 0; // FIXME
}

fn print_register_debug(registers: Registers) void {
    std.debug.print("PC {x:0>4} SP {x:0>4}", .{ registers.pc, registers.sp });
    std.debug.print(" A {x:0>2} Flags {s} {s} {s} {s}", .{
        registers.a,
        if (registers.flags.zero) "Z" else "_",
        if (registers.flags.substract) "N" else "_",
        if (registers.flags.half_carry == 1) "H" else "_",
        if (registers.flags.carry == 1) "C" else "_",
    });
    std.debug.print(" B {x:0>2} C {x:0>2}", .{ registers.b, registers.c });
    std.debug.print(" D {x:0>2} E {x:0>2}", .{ registers.d, registers.e });
    std.debug.print(" H {x:0>2} L {x:0>2}", .{ registers.h, registers.l });
}

fn execute_instruction(gb: *GBState, instruction: instructions.Instruction) void {
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

pub fn execute_interrupt(gb: *GBState, jump_address: u16) void {
    // FIXME timing
    gb.registers.sp -= 2;

    store_memory_u16(gb, gb.registers.sp, gb.registers.pc);

    store_pc(gb, jump_address);
}

fn execute_nop(gb: *GBState) void {
    _ = gb; // do nothing
}

fn execute_ld_r16_imm16(gb: *GBState, instruction: instructions.ld_r16_imm16) void {
    store_r16(&gb.registers, instruction.r16, instruction.imm16);
}

fn execute_ld_r16mem_a(gb: *GBState, instruction: instructions.ld_r16mem_a) void {
    const r16mem = instruction.r16mem;
    const address = load_r16(gb.registers, r16mem.r16);

    store_memory_u8(gb, address, gb.registers.a);

    if (r16mem.r16 == R16.hl) {
        increment_hl(&gb.registers, r16mem.increment);
    }
}

fn execute_ld_a_r16mem(gb: *GBState, instruction: instructions.ld_a_r16mem) void {
    const r16mem = instruction.r16mem;
    const address = load_r16(gb.registers, r16mem.r16);

    gb.registers.a = load_memory_u8(gb, address);

    if (r16mem.r16 == R16.hl) {
        increment_hl(&gb.registers, r16mem.increment);
    }
}

fn execute_ld_imm16_sp(gb: *GBState, instruction: instructions.ld_imm16_sp) void {
    store_memory_u16(gb, instruction.imm16, gb.registers.sp);
}

fn execute_inc_r16(gb: *GBState, instruction: instructions.inc_r16) void {
    const value = load_r16(gb.registers, instruction.r16);

    store_r16(&gb.registers, instruction.r16, value +% 1);
}

fn execute_dec_r16(gb: *GBState, instruction: instructions.dec_r16) void {
    const value = load_r16(gb.registers, instruction.r16);

    store_r16(&gb.registers, instruction.r16, value -% 1);
}

fn execute_add_hl_r16(gb: *GBState, instruction: instructions.add_hl_r16) void {
    spend_cycles(gb, 4);

    const registers_r16: *cpu.Registers_R16 = @ptrCast(&gb.registers);
    const r16_value = load_r16(gb.registers, instruction.r16);

    const result, const carry = @addWithOverflow(registers_r16.hl, r16_value);
    _, const half_carry = @addWithOverflow(@as(u8, @intCast(registers_r16.hl & 0xff)), @as(u8, @intCast(r16_value & 0xff)));

    registers_r16.hl = result;

    gb.registers.flags.carry = carry;
    gb.registers.flags.half_carry = half_carry;
    gb.registers.flags.substract = false;
}

fn execute_inc_r8(gb: *GBState, instruction: instructions.inc_r8) void {
    const r8_value = load_r8(gb, instruction.r8);

    const op_result = r8_value +% 1;
    _, const half_carry = @addWithOverflow(@as(u4, @intCast(r8_value & 0xf)), 1);

    store_r8(gb, instruction.r8, op_result);

    gb.registers.flags.half_carry = half_carry;
    gb.registers.flags.substract = false;
    gb.registers.flags.zero = op_result == 0;
}

fn execute_dec_r8(gb: *GBState, instruction: instructions.dec_r8) void {
    const r8_value = load_r8(gb, instruction.r8);

    const op_result = r8_value -% 1;
    _, const half_carry = @subWithOverflow(@as(u4, @intCast(r8_value & 0xf)), 1);

    store_r8(gb, instruction.r8, op_result);

    gb.registers.flags.half_carry = half_carry;
    gb.registers.flags.substract = true;
    gb.registers.flags.zero = op_result == 0;
}

fn execute_ld_r8_imm8(gb: *GBState, instruction: instructions.ld_r8_imm8) void {
    store_r8(gb, instruction.r8, instruction.imm8);
}

fn execute_rlca(gb: *GBState) void {
    const msb_set = (gb.registers.a & 0x80) != 0;

    gb.registers.a = std.math.rotl(u8, gb.registers.a, 1);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, msb_set);
}

fn execute_rrca(gb: *GBState) void {
    const lsb_set = (gb.registers.a & 0x01) != 0;

    gb.registers.a = std.math.rotr(u8, gb.registers.a, 1);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, lsb_set);
}

fn execute_rla(gb: *GBState) void {
    const msb_set = (gb.registers.a & 0x80) != 0;

    gb.registers.a = gb.registers.a << 1 | gb.registers.flags.carry;

    reset_flags(&gb.registers);
    set_carry(&gb.registers, msb_set);
}

fn execute_rra(gb: *GBState) void {
    const lsb_set = (gb.registers.a & 0x01) != 0;

    gb.registers.a = gb.registers.a >> 1 | (@as(u8, gb.registers.flags.carry) << 7);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, lsb_set);
}

fn execute_daa(gb: *GBState) void {
    _ = gb;
    unreachable;
}

fn execute_cpl(gb: *GBState) void {
    gb.registers.a ^= 0b1111_1111;

    gb.registers.flags.half_carry = 1;
    gb.registers.flags.substract = true;
}

fn execute_scf(gb: *GBState) void {
    gb.registers.flags.carry = 1;

    gb.registers.flags.half_carry = 0;
    gb.registers.flags.substract = false;
}

fn execute_ccf(gb: *GBState) void {
    gb.registers.flags.carry ^= 1;

    gb.registers.flags.half_carry = 0;
    gb.registers.flags.substract = false;
}

fn execute_jr_imm8(gb: *GBState, instruction: instructions.jr_imm8) void {
    // FIXME Zig is weird about mixing unsigned and signed values, so the ugly ternary is what it is.
    if (instruction.offset < 0) {
        store_pc(gb, gb.registers.pc - @as(u16, @intCast(-instruction.offset)));
    } else {
        store_pc(gb, gb.registers.pc + @as(u16, @intCast(instruction.offset)));
    }
}

fn execute_jr_cond_imm8(gb: *GBState, instruction: instructions.jr_cond_imm8) void {
    if (eval_cond(gb.registers, instruction.cond)) {
        execute_jr_imm8(gb, .{ .offset = instruction.offset });
    }
}

fn execute_stop(gb: *GBState) void {
    _ = gb;
    unreachable;
}

fn execute_ld_r8_r8(gb: *GBState, instruction: instructions.ld_r8_r8) void {
    const value = load_r8(gb, instruction.r8_src);

    store_r8(gb, instruction.r8_dst, value);
}

fn execute_halt(gb: *GBState) void {
    _ = gb;
    unreachable;
}

fn execute_add_a(gb: *GBState, value: u8) void {
    const result, const carry = @addWithOverflow(gb.registers.a, value);
    _, const half_carry = @addWithOverflow(@as(u4, @intCast(gb.registers.a & 0xf)), value);

    gb.registers.a = result;

    gb.registers.flags.carry = carry;
    gb.registers.flags.half_carry = half_carry;
    gb.registers.flags.substract = false;
    gb.registers.flags.zero = gb.registers.a == 0;
}

fn execute_adc_a(gb: *GBState, value: u8) void {
    const result_with_carry, const carry_a = @addWithOverflow(gb.registers.a, gb.registers.flags.carry);
    const result, const carry_b = @addWithOverflow(result_with_carry, value);

    const result_with_half_carry, const half_carry_a = @addWithOverflow(@as(u4, @intCast(gb.registers.a & 0xf)), gb.registers.flags.carry);
    _, const half_carry_b = @addWithOverflow(result_with_half_carry, @as(u4, @intCast(value & 0xf)));

    gb.registers.a = result;

    gb.registers.flags.carry = carry_a | carry_b;
    gb.registers.flags.half_carry = half_carry_a | half_carry_b;
    gb.registers.flags.substract = false;
    gb.registers.flags.zero = gb.registers.a == 0;
}

fn execute_sub_a(gb: *GBState, value: u8) void {
    const result, const carry = @subWithOverflow(gb.registers.a, value);
    _, const half_carry = @subWithOverflow(@as(u4, @intCast(gb.registers.a & 0xf)), value);

    gb.registers.a = result;

    gb.registers.flags.carry = carry;
    gb.registers.flags.half_carry = half_carry;
    gb.registers.flags.substract = true;
    gb.registers.flags.zero = gb.registers.a == 0;
}

fn execute_sbc_a(gb: *GBState, value: u8) void {
    const result_with_carry, const carry_a = @subWithOverflow(gb.registers.a, gb.registers.flags.carry);
    const result, const carry_b = @subWithOverflow(result_with_carry, value);

    const result_with_half_carry, const half_carry_a = @subWithOverflow(@as(u4, @intCast(gb.registers.a & 0xf)), gb.registers.flags.carry);
    _, const half_carry_b = @subWithOverflow(result_with_half_carry, @as(u4, @intCast(value & 0xf)));

    gb.registers.a = result;

    gb.registers.flags.carry = carry_a | carry_b;
    gb.registers.flags.half_carry = half_carry_a | half_carry_b;
    gb.registers.flags.substract = true;
    gb.registers.flags.zero = gb.registers.a == 0;
}

fn execute_and_a(gb: *GBState, value: u8) void {
    gb.registers.a &= value;

    reset_flags(&gb.registers);
    gb.registers.flags.half_carry = 1;
    gb.registers.flags.zero = gb.registers.a == 0;
}

fn execute_xor_a(gb: *GBState, value: u8) void {
    gb.registers.a ^= value;

    reset_flags(&gb.registers);
    gb.registers.flags.zero = gb.registers.a == 0;
}

fn execute_or_a(gb: *GBState, value: u8) void {
    gb.registers.a |= value;

    reset_flags(&gb.registers);
    gb.registers.flags.zero = gb.registers.a == 0;
}

fn execute_cp_a(gb: *GBState, value: u8) void {
    set_carry(&gb.registers, gb.registers.a < value);
    set_half_carry(&gb.registers, (gb.registers.a & 0xf) < (value & 0xf));
    gb.registers.flags.substract = true;
    gb.registers.flags.zero = gb.registers.a == value;
}

fn execute_add_a_r8(gb: *GBState, instruction: instructions.add_a_r8) void {
    execute_add_a(gb, load_r8(gb, instruction.r8));
}

fn execute_add_a_imm8(gb: *GBState, instruction: instructions.add_a_imm8) void {
    execute_add_a(gb, instruction.imm8);
}

fn execute_adc_a_r8(gb: *GBState, instruction: instructions.adc_a_r8) void {
    execute_adc_a(gb, load_r8(gb, instruction.r8));
}

fn execute_adc_a_imm8(gb: *GBState, instruction: instructions.adc_a_imm8) void {
    execute_adc_a(gb, instruction.imm8);
}

fn execute_sub_a_r8(gb: *GBState, instruction: instructions.sub_a_r8) void {
    execute_sub_a(gb, load_r8(gb, instruction.r8));
}

fn execute_sub_a_imm8(gb: *GBState, instruction: instructions.sub_a_imm8) void {
    execute_sub_a(gb, instruction.imm8);
}

fn execute_sbc_a_r8(gb: *GBState, instruction: instructions.sbc_a_r8) void {
    execute_sbc_a(gb, load_r8(gb, instruction.r8));
}

fn execute_sbc_a_imm8(gb: *GBState, instruction: instructions.sbc_a_imm8) void {
    execute_sbc_a(gb, instruction.imm8);
}

fn execute_and_a_r8(gb: *GBState, instruction: instructions.and_a_r8) void {
    execute_and_a(gb, load_r8(gb, instruction.r8));
}

fn execute_and_a_imm8(gb: *GBState, instruction: instructions.and_a_imm8) void {
    execute_and_a(gb, instruction.imm8);
}

fn execute_xor_a_r8(gb: *GBState, instruction: instructions.xor_a_r8) void {
    execute_xor_a(gb, load_r8(gb, instruction.r8));
}

fn execute_xor_a_imm8(gb: *GBState, instruction: instructions.xor_a_imm8) void {
    execute_xor_a(gb, instruction.imm8);
}

fn execute_or_a_r8(gb: *GBState, instruction: instructions.or_a_r8) void {
    execute_or_a(gb, load_r8(gb, instruction.r8));
}

fn execute_or_a_imm8(gb: *GBState, instruction: instructions.or_a_imm8) void {
    execute_or_a(gb, instruction.imm8);
}

fn execute_cp_a_r8(gb: *GBState, instruction: instructions.cp_a_r8) void {
    execute_cp_a(gb, load_r8(gb, instruction.r8));
}

fn execute_cp_a_imm8(gb: *GBState, instruction: instructions.cp_a_imm8) void {
    execute_cp_a(gb, instruction.imm8);
}

fn execute_ret_cond(gb: *GBState, instruction: instructions.ret_cond) void {
    spend_cycles(gb, 4); // FIXME there's probably a better explanation for this

    if (eval_cond(gb.registers, instruction.cond)) {
        execute_ret(gb);
    }
}

fn execute_ret(gb: *GBState) void {
    const previous_pc = load_memory_u16(gb, gb.registers.sp);

    store_pc(gb, previous_pc);

    gb.registers.sp += 2;
}

fn execute_reti(gb: *GBState) void {
    execute_ret(gb);

    gb.enable_interrupts_master = true;
}

fn execute_jp_cond_imm16(gb: *GBState, instruction: instructions.jp_cond_imm16) void {
    if (eval_cond(gb.registers, instruction.cond)) {
        execute_jp_imm16(gb, .{ .imm16 = instruction.imm16 });
    }
}

fn execute_jp_imm16(gb: *GBState, instruction: instructions.jp_imm16) void {
    store_pc(gb, instruction.imm16);
}

fn execute_jp_hl(gb: *GBState) void {
    const registers_r16: cpu.Registers_R16 = @bitCast(gb.registers);

    // FIXME here storing PC doesn't cost anything for some reason
    // While other times it does.
    gb.registers.pc = registers_r16.hl;
}

fn execute_call_cond_imm16(gb: *GBState, instruction: instructions.call_cond_imm16) void {
    if (eval_cond(gb.registers, instruction.cond)) {
        execute_call_imm16(gb, .{ .imm16 = instruction.imm16 });
    }
}

fn execute_call_imm16(gb: *GBState, instruction: instructions.call_imm16) void {
    gb.registers.sp -= 2;

    store_memory_u16(gb, gb.registers.sp, gb.registers.pc);

    store_pc(gb, instruction.imm16);
}

// Like a call but 2 bytes cheapers
fn execute_rst_tgt3(gb: *GBState, instruction: instructions.rst_tgt3) void {
    gb.registers.sp -= 2;

    store_memory_u16(gb, gb.registers.sp, gb.registers.pc);

    store_pc(gb, instruction.target_addr);
}

fn execute_pop_r16stk(gb: *GBState, instruction: instructions.pop_r16stk) void {
    const value = load_memory_u16(gb, gb.registers.sp);

    store_r16(&gb.registers, instruction.r16stk, value);

    gb.registers.sp += 2;
}

fn execute_push_r16stk(gb: *GBState, instruction: instructions.push_r16stk) void {
    spend_cycles(gb, 4); // FIXME there's probably a better explanation for this

    gb.registers.sp -= 2;

    store_memory_u16(gb, gb.registers.sp, load_r16(gb.registers, instruction.r16stk));
}

const LDH_OFFSET: u16 = 0xff00;

fn execute_ldh_c_a(gb: *GBState) void {
    store_memory_u8(gb, LDH_OFFSET + gb.registers.c, gb.registers.a);
}

fn execute_ldh_imm8_a(gb: *GBState, instruction: instructions.ldh_imm8_a) void {
    store_memory_u8(gb, LDH_OFFSET + instruction.imm8, gb.registers.a);
}

fn execute_ld_imm16_a(gb: *GBState, instruction: instructions.ld_imm16_a) void {
    store_memory_u8(gb, instruction.imm16, gb.registers.a);
}

fn execute_ldh_a_c(gb: *GBState) void {
    gb.registers.a = load_memory_u8(gb, LDH_OFFSET + gb.registers.c);
}

fn execute_ldh_a_imm8(gb: *GBState, instruction: instructions.ldh_a_imm8) void {
    gb.registers.a = load_memory_u8(gb, LDH_OFFSET + instruction.imm8);
}

fn execute_ld_a_imm16(gb: *GBState, instruction: instructions.ld_a_imm16) void {
    gb.registers.a = load_memory_u8(gb, instruction.imm16);
}

fn execute_add_sp_imm8(gb: *GBState, instruction: instructions.add_sp_imm8) void {
    spend_cycles(gb, 8);

    const result, const carry = if (instruction.offset < 0)
        @subWithOverflow(gb.registers.sp, @as(u16, @intCast(-instruction.offset)))
    else
        @addWithOverflow(gb.registers.sp, @as(u16, @intCast(instruction.offset)));

    // NOTE: Super weird carry behavior, note the bitCast.
    _, const half_carry = @addWithOverflow(@as(u4, @intCast(gb.registers.sp & 0xf)), @as(u4, @intCast(instruction.offset & 0xf)));

    assert(carry == 0);

    gb.registers.sp = result;

    gb.registers.flags.carry = carry; // FIXME might not be correct
    gb.registers.flags.half_carry = half_carry;
    gb.registers.flags.substract = false;
    gb.registers.flags.zero = false;
}

fn execute_ld_hl_sp_plus_imm8(gb: *GBState, instruction: instructions.ld_hl_sp_plus_imm8) void {
    _ = gb;
    _ = instruction;
    unreachable;
}

fn execute_ld_sp_hl(gb: *GBState) void {
    _ = gb;
    unreachable;
}

fn execute_di(gb: *GBState) void {
    gb.enable_interrupts_master = false;
}

fn execute_ei(gb: *GBState) void {
    // FIXME apparently we have to wait 1 op before actually turning this on
    gb.enable_interrupts_master = true;
}

fn execute_rlc_r8(gb: *GBState, instruction: instructions.rlc_r8) void {
    const r8_value = load_r8(gb, instruction.r8);
    const r8_msb_set = (r8_value & 0x80) != 0;

    const op_result = std.math.rotl(u8, r8_value, 1);

    store_r8(gb, instruction.r8, op_result);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, r8_msb_set);
    gb.registers.flags.zero = op_result == 0;
}

fn execute_rrc_r8(gb: *GBState, instruction: instructions.rrc_r8) void {
    const r8_value = load_r8(gb, instruction.r8);
    const r8_lsb_set = (r8_value & 0x01) != 0;

    const op_result = std.math.rotr(u8, r8_value, 1);

    store_r8(gb, instruction.r8, op_result);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, r8_lsb_set);
    gb.registers.flags.zero = op_result == 0;
}

fn execute_rl_r8(gb: *GBState, instruction: instructions.rl_r8) void {
    const r8_value = load_r8(gb, instruction.r8);
    const r8_msb_set = (r8_value & 0x80) != 0;

    const op_result = r8_value << 1 | gb.registers.flags.carry;

    store_r8(gb, instruction.r8, op_result);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, r8_msb_set);
    gb.registers.flags.zero = op_result == 0;
}

fn execute_rr_r8(gb: *GBState, instruction: instructions.rr_r8) void {
    const r8_value = load_r8(gb, instruction.r8);
    const r8_lsb_set = (r8_value & 0x01) != 0;

    const op_result = r8_value >> 1 | @as(u8, gb.registers.flags.carry) << 7;

    store_r8(gb, instruction.r8, op_result);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, r8_lsb_set);
    gb.registers.flags.zero = op_result == 0;
}

fn execute_sla_r8(gb: *GBState, instruction: instructions.sla_r8) void {
    const r8_value = load_r8(gb, instruction.r8);
    const r8_msb_set = (r8_value & 0x80) != 0;
    const r8_rest_unset = (r8_value & 0x7F) == 0;

    const op_result = r8_value << 1;

    store_r8(gb, instruction.r8, op_result);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, r8_msb_set);
    gb.registers.flags.zero = r8_rest_unset;
}

fn execute_sra_r8(gb: *GBState, instruction: instructions.sra_r8) void {
    const r8_value = load_r8(gb, instruction.r8);
    const r8_msb = r8_value & 0x80;
    const r8_lsb_set = (r8_value & 0x01) != 0;

    const op_result = r8_value >> 1 | r8_msb;

    store_r8(gb, instruction.r8, op_result);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, r8_lsb_set);
    gb.registers.flags.zero = op_result == 0;
}

fn execute_swap_r8(gb: *GBState, instruction: instructions.swap_r8) void {
    const r8_value = load_r8(gb, instruction.r8);

    const op_result = (r8_value << 4) | (r8_value >> 4);

    store_r8(gb, instruction.r8, op_result);

    reset_flags(&gb.registers);
    gb.registers.flags.zero = r8_value == 0;
}

fn execute_srl_r8(gb: *GBState, instruction: instructions.srl_r8) void {
    const r8_value = load_r8(gb, instruction.r8);
    const r8_lsb_set = (r8_value & 0x01) != 0;

    const op_result = r8_value >> 1;

    store_r8(gb, instruction.r8, op_result);

    reset_flags(&gb.registers);
    set_carry(&gb.registers, r8_lsb_set);
    gb.registers.flags.zero = op_result == 0;
}

fn execute_bit_b3_r8(gb: *GBState, instruction: instructions.bit_b3_r8) void {
    const r8_value = load_r8(gb, instruction.r8);

    const bit = @as(u8, 1) << instruction.bit_index;
    const op_result = r8_value & bit;

    gb.registers.flags = .{
        ._unused = 0,
        .carry = gb.registers.flags.carry,
        .half_carry = 1,
        .substract = false,
        .zero = op_result == 0,
    };
}

fn execute_res_b3_r8(gb: *GBState, instruction: instructions.res_b3_r8) void {
    const r8_value = load_r8(gb, instruction.r8);

    const bit = @as(u8, 1) << instruction.bit_index;
    const op_result = r8_value & ~bit;

    store_r8(gb, instruction.r8, op_result);
}

fn execute_set_b3_r8(gb: *GBState, instruction: instructions.set_b3_r8) void {
    const r8_value = load_r8(gb, instruction.r8);

    const bit = @as(u8, 1) << instruction.bit_index;
    const op_result = r8_value | bit;

    store_r8(gb, instruction.r8, op_result);
}

fn execute_invalid_instruction(gb: *GBState) void {
    _ = gb;
    unreachable;
}

fn load_memory_u8(gb: *GBState, address: u16) u8 {
    spend_cycles(gb, 4);

    switch (address) {
        0x0000...0x7fff => return gb.memory[address], // FIXME Is reading the ROM legal?
        0x8000...0x9fff => { // VRAM
            // is only readable when the PPU is not drawing
            const is_ppu_drawing = gb.mmio.lcd.STAT.ppu_mode == .Drawing;
            assert(!is_ppu_drawing);
            if (is_ppu_drawing) {
                return 0xff;
            } else {
                return gb.vram[address - 0x8000];
            }
        },
        0xa000...0xbfff => return gb.memory[address], // External RAM
        0xc000...0xcfff => return gb.memory[address], // RAM
        0xd000...0xdfff => return gb.memory[address], // RAM (Banked on CGB)
        0xe000...0xfdff => unreachable, // Echo RAMBANK
        0xfe00...0xfe9f => return gb.memory[address], // OAMRAM
        0xfea0...0xfeff => unreachable, // Nothing?
        0xff00...0xff7f, 0xffff => { // MMIO
            const offset: u8 = @intCast(address & 0xff);
            const typed_offset: cpu.MMIO_Offset = @enumFromInt(offset);
            const mmio_bytes = @as([*]u8, @ptrCast(gb.mmio));

            switch (typed_offset) {
                .JOYP => return mmio_bytes[offset] & 0x0F,
                _ => return mmio_bytes[offset],
            }
        },
        0xff80...0xfffe => return gb.memory[address], // HRAM
    }
}

fn store_memory_u8(gb: *GBState, address: u16, value: u8) void {
    spend_cycles(gb, 4);

    switch (address) {
        0x0000...0x7fff => { // ROM
            // Avoid writing here
            // Unfortunately it's common for official games to do, so avoid asserting for now.
            // https://www.reddit.com/r/EmuDev/comments/5ht388/gb_why_does_tetris_write_to_the_rom/
            // assert(address == 0x2000);
        }, // We can't write into the ROM
        0x8000...0x9fff => { // VRAM
            // is only writable when the PPU is not drawing
            // FIXME assert(gb.mmio.lcd.STAT.ppu_mode != .Drawing);
            gb.vram[address - 0x8000] = value;
        },
        0xa000...0xbfff => gb.memory[address] = value, // External RAM
        0xc000...0xcfff => gb.memory[address] = value, // RAM
        0xd000...0xdfff => gb.memory[address] = value, // RAM (Banked on CGB)
        0xe000...0xfdff => {}, // FIXME Echo RAMBANK
        0xfe00...0xfe9f => gb.memory[address] = value, // OAMRAM
        0xfea0...0xfeff => {}, // FIXME Nothing?
        0xff00...0xff7f, 0xffff => { // MMIO
            const offset: u8 = @intCast(address & 0xff);
            const typed_offset: cpu.MMIO_Offset = @enumFromInt(offset);
            const mmio_bytes = @as([*]u8, @ptrCast(gb.mmio));

            switch (typed_offset) {
                // We could probably just write the full byte and not worry
                .JOYP => gb.mmio.JOYP.input_selector = @enumFromInt((value >> 4) & 0b11),
                _ => mmio_bytes[offset] = value,
            }
        },
        0xff80...0xfffe => gb.memory[address] = value, // HRAM
    }
}

fn load_memory_u16(gb: *GBState, address: u16) u16 {
    const l = load_memory_u8(gb, address);
    const h = load_memory_u8(gb, address + 1);

    return @as(u16, l) | (@as(u16, @intCast(h)) << 8);
}

fn store_memory_u16(gb: *GBState, address: u16, value: u16) void {
    store_memory_u8(gb, address, @intCast(value & 0xff));
    store_memory_u8(gb, address + 1, @intCast(value >> 8));
}

// FIXME check if this actually takes cycles
fn store_pc(gb: *GBState, value: u16) void {
    spend_cycles(gb, 4);

    gb.registers.pc = value;
}

fn spend_cycles(gb: *GBState, cycles: u8) void {
    gb.pending_cycles += cycles;
}

fn load_r8(gb: *GBState, r8: R8) u8 {
    return switch (r8) {
        .b => gb.registers.b,
        .c => gb.registers.c,
        .d => gb.registers.d,
        .e => gb.registers.e,
        .h => gb.registers.h,
        .l => gb.registers.l,
        .hl_p => load_memory_u8(gb, load_r16(gb.registers, R16.hl)),
        .a => gb.registers.a,
    };
}

fn store_r8(gb: *GBState, r8: R8, value: u8) void {
    switch (r8) {
        .b => gb.registers.b = value,
        .c => gb.registers.c = value,
        .d => gb.registers.d = value,
        .e => gb.registers.e = value,
        .h => gb.registers.h = value,
        .l => gb.registers.l = value,
        .hl_p => store_memory_u8(gb, load_r16(gb.registers, R16.hl), value),
        .a => gb.registers.a = value,
    }
}

fn load_r16(registers: Registers, r16: R16) u16 {
    const registers_r16: cpu.Registers_R16 = @bitCast(registers);

    return switch (r16) {
        .bc => registers_r16.bc,
        .de => registers_r16.de,
        .hl => registers_r16.hl,
        .af => registers_r16.af,
        .sp => registers_r16.sp,
    };
}

fn store_r16(registers: *Registers, r16: R16, value: u16) void {
    var registers_r16: *cpu.Registers_R16 = @ptrCast(registers);

    switch (r16) {
        .bc => registers_r16.bc = value,
        .de => registers_r16.de = value,
        .hl => registers_r16.hl = value,
        .af => registers_r16.af = value,
        .sp => registers_r16.sp = value,
    }
}

fn eval_cond(registers: Registers, cond: instructions.Cond) bool {
    return switch (cond) {
        .nz => !registers.flags.zero,
        .z => registers.flags.zero,
        .nc => registers.flags.carry == 0,
        .c => registers.flags.carry == 1,
    };
}

fn increment_hl(registers: *Registers, increment: bool) void {
    var hl_value = load_r16(registers.*, R16.hl);

    // Let zig catch an exception on wraparound since it doesn't look like this is supposed to happen anyway.
    if (increment) {
        hl_value += 1;
    } else {
        hl_value -= 1;
    }

    store_r16(registers, R16.hl, hl_value);
}

fn reset_flags(registers: *Registers) void {
    registers.flags = @bitCast(@as(u8, 0));
}

fn set_carry(registers: *Registers, carry: bool) void {
    registers.flags.carry = if (carry) 1 else 0;
}

fn set_half_carry(registers: *Registers, half_carry: bool) void {
    registers.flags.half_carry = if (half_carry) 1 else 0;
}
