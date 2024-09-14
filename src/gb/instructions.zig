const std = @import("std");
const assert = std.debug.assert;
const gb_endian = std.builtin.Endian.little;

const cpu = @import("cpu.zig");
const GBState = cpu.GBState;

const execution = @import("execution.zig");

pub fn decode_inc_pc(gb: *GBState) Instruction {
    const b0 = instruction_load_u8_inc_pc(gb);

    if (b0 == 0b0000_0000) {
        return .{ .nop = undefined };
    } else if ((b0 & 0b1100_1111) == 0b0000_0001) {
        return .{ .ld_r16_imm16 = .{
            .r16 = decode_r16(read_bits_from_byte(u2, b0, 4)),
            .imm16 = instruction_load_u16_inc_pc(gb),
        } };
    } else if ((b0 & 0b1100_1111) == 0b0000_0010) {
        return .{ .ld_r16mem_a = .{
            .r16mem = decode_r16mem(read_bits_from_byte(u2, b0, 4)),
        } };
    } else if ((b0 & 0b1100_1111) == 0b0000_1010) {
        return .{ .ld_a_r16mem = .{
            .r16mem = decode_r16mem(read_bits_from_byte(u2, b0, 4)),
        } };
    } else if (b0 == 0b0000_1000) {
        return .{ .ld_imm16_sp = .{
            .imm16 = instruction_load_u16_inc_pc(gb),
        } };
    } else if ((b0 & 0b1100_1111) == 0b0000_0011) {
        return .{ .inc_r16 = .{
            .r16 = decode_r16(read_bits_from_byte(u2, b0, 4)),
        } };
    } else if ((b0 & 0b1100_1111) == 0b0000_1011) {
        return .{ .dec_r16 = .{
            .r16 = decode_r16(read_bits_from_byte(u2, b0, 4)),
        } };
    } else if ((b0 & 0b1100_1111) == 0b0000_1001) {
        return .{ .add_hl_r16 = .{
            .r16 = decode_r16(read_bits_from_byte(u2, b0, 4)),
        } };
    } else if ((b0 & 0b1100_0111) == 0b0000_0100) {
        return .{ .inc_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 3)),
        } };
    } else if ((b0 & 0b1100_0111) == 0b0000_0101) {
        return .{ .dec_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 3)),
        } };
    } else if ((b0 & 0b1100_0111) == 0b0000_0110) {
        return .{ .ld_r8_imm8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 3)),
            .imm8 = instruction_load_u8_inc_pc(gb),
        } };
    } else if (b0 == 0b0000_0111) {
        return .{ .rlca = undefined };
    } else if (b0 == 0b0000_1111) {
        return .{ .rrca = undefined };
    } else if (b0 == 0b0001_0111) {
        return .{ .rla = undefined };
    } else if (b0 == 0b0001_1111) {
        return .{ .rra = undefined };
    } else if (b0 == 0b0010_0111) {
        return .{ .daa = undefined };
    } else if (b0 == 0b0010_1111) {
        return .{ .cpl = undefined };
    } else if (b0 == 0b0011_0111) {
        return .{ .scf = undefined };
    } else if (b0 == 0b0011_1111) {
        return .{ .ccf = undefined };
    } else if (b0 == 0b0001_1000) {
        return .{ .jr_imm8 = .{
            .offset = @bitCast(instruction_load_u8_inc_pc(gb)),
        } };
    } else if ((b0 & 0b1110_0111) == 0b0010_0000) {
        return .{ .jr_cond_imm8 = .{
            .cond = decode_cond(read_bits_from_byte(u2, b0, 3)),
            .offset = @bitCast(instruction_load_u8_inc_pc(gb)),
        } };
    } else if (b0 == 0b0001_0000) {
        return .{ .stop = undefined }; // FIXME stuff about stop being 2 instructions
    } else if (b0 == 0b0111_0110) {
        return .{ .halt = undefined }; // Parse halt first or it'll be eaten by ld_r8_r8
    } else if ((b0 & 0b1100_0000) == 0b0100_0000) {
        return .{ .ld_r8_r8 = .{
            .r8_dst = decode_r8(read_bits_from_byte(u3, b0, 3)),
            .r8_src = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } };
    } else if ((b0 & 0b1111_1000) == 0b1000_0000) {
        return .{ .add_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } };
    } else if ((b0 & 0b1111_1000) == 0b1000_1000) {
        return .{ .adc_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } };
    } else if ((b0 & 0b1111_1000) == 0b1001_0000) {
        return .{ .sub_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } };
    } else if ((b0 & 0b1111_1000) == 0b1001_1000) {
        return .{ .sbc_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } };
    } else if ((b0 & 0b1111_1000) == 0b1010_0000) {
        return .{ .and_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } };
    } else if ((b0 & 0b1111_1000) == 0b1010_1000) {
        return .{ .xor_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } };
    } else if ((b0 & 0b1111_1000) == 0b1011_0000) {
        return .{ .or_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } };
    } else if ((b0 & 0b1111_1000) == 0b1011_1000) {
        return .{ .cp_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } };
    } else if (b0 == 0b1100_0110) {
        return .{ .add_a_imm8 = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if (b0 == 0b1100_1110) {
        return .{ .adc_a_imm8 = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if (b0 == 0b1101_0110) {
        return .{ .sub_a_imm8 = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if (b0 == 0b1101_1110) {
        return .{ .sbc_a_imm8 = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if (b0 == 0b1110_0110) {
        return .{ .and_a_imm8 = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if (b0 == 0b1110_1110) {
        return .{ .xor_a_imm8 = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if (b0 == 0b1111_0110) {
        return .{ .or_a_imm8 = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if (b0 == 0b1111_1110) {
        return .{ .cp_a_imm8 = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if ((b0 & 0b1110_0111) == 0b1100_0000) {
        return .{ .ret_cond = .{
            .cond = decode_cond(read_bits_from_byte(u2, b0, 3)),
        } };
    } else if (b0 == 0b1100_1001) {
        return .{ .ret = undefined };
    } else if (b0 == 0b1101_1001) {
        return .{ .reti = undefined };
    } else if ((b0 & 0b1110_0111) == 0b1100_0010) {
        return .{ .jp_cond_imm16 = .{
            .cond = decode_cond(read_bits_from_byte(u2, b0, 3)),
            .imm16 = instruction_load_u16_inc_pc(gb),
        } };
    } else if (b0 == 0b1100_0011) {
        return .{ .jp_imm16 = .{
            .imm16 = instruction_load_u16_inc_pc(gb),
        } };
    } else if (b0 == 0b1110_1001) {
        return .{ .jp_hl = undefined };
    } else if ((b0 & 0b1110_0111) == 0b1100_0100) {
        return .{ .call_cond_imm16 = .{
            .cond = decode_cond(read_bits_from_byte(u2, b0, 3)),
            .imm16 = instruction_load_u16_inc_pc(gb),
        } };
    } else if (b0 == 0b1100_1101) {
        return .{ .call_imm16 = .{
            .imm16 = instruction_load_u16_inc_pc(gb),
        } };
    } else if ((b0 & 0b1100_0111) == 0b1100_0111) {
        return .{ .rst_tgt3 = .{
            .target_addr = decode_tgt3(read_bits_from_byte(u3, b0, 3)),
        } };
    } else if ((b0 & 0b1100_1111) == 0b1100_0001) {
        return .{ .pop_r16stk = .{
            .r16stk = decode_r16stk(read_bits_from_byte(u2, b0, 4)),
        } };
    } else if ((b0 & 0b1100_1111) == 0b1100_0101) {
        return .{ .push_r16stk = .{
            .r16stk = decode_r16stk(read_bits_from_byte(u2, b0, 4)),
        } };
    } else if (b0 == 0b1100_1011) { // 0xCB prefix opcodes
        const b1 = instruction_load_u8_inc_pc(gb);
        const masked_b1_a = b1 & 0b1111_1000;
        const masked_b1_b = b1 & 0b1100_0000;

        if (masked_b1_a == 0b0000_0000) {
            return .{ .rlc_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_a == 0b0000_1000) {
            return .{ .rrc_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_a == 0b0001_0000) {
            return .{ .rl_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_a == 0b0001_1000) {
            return .{ .rr_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_a == 0b0010_0000) {
            return .{ .sla_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_a == 0b0010_1000) {
            return .{ .sra_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_a == 0b0011_0000) {
            return .{ .swap_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_a == 0b0011_1000) {
            return .{ .srl_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_b == 0b0100_0000) {
            return .{ .bit_b3_r8 = .{
                .bit_index = read_bits_from_byte(u3, b1, 3),
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_b == 0b1000_0000) {
            return .{ .res_b3_r8 = .{
                .bit_index = read_bits_from_byte(u3, b1, 3),
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        } else if (masked_b1_b == 0b1100_0000) {
            return .{ .set_b3_r8 = .{
                .bit_index = read_bits_from_byte(u3, b1, 3),
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } };
        }
    } else if (b0 == 0b1110_0010) {
        return .{ .ldh_c_a = undefined };
    } else if (b0 == 0b1110_0000) {
        return .{ .ldh_imm8_a = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if (b0 == 0b1110_1010) {
        return .{ .ld_imm16_a = .{
            .imm16 = instruction_load_u16_inc_pc(gb),
        } };
    } else if (b0 == 0b1111_0010) {
        return .{ .ldh_a_c = undefined };
    } else if (b0 == 0b1111_0000) {
        return .{ .ldh_a_imm8 = .{ .imm8 = instruction_load_u8_inc_pc(gb) } };
    } else if (b0 == 0b1111_1010) {
        return .{ .ld_a_imm16 = .{
            .imm16 = instruction_load_u16_inc_pc(gb),
        } };
    } else if (b0 == 0b1110_1000) {
        return .{ .add_sp_imm8 = .{ .offset = @bitCast(instruction_load_u8_inc_pc(gb)) } };
    } else if (b0 == 0b1111_1000) {
        return .{ .ld_hl_sp_plus_imm8 = .{ .offset = @bitCast(instruction_load_u8_inc_pc(gb)) } };
    } else if (b0 == 0b1111_1001) {
        return .{ .ld_sp_hl = undefined };
    } else if (b0 == 0b1111_0011) {
        return .{ .di = undefined };
    } else if (b0 == 0b1111_1011) {
        return .{ .ei = undefined };
    } else if (b0 == 0xD3 or b0 == 0xDB or b0 == 0xDD) {
        return .{ .invalid = undefined };
    } else if (b0 == 0xE3 or b0 == 0xE4 or b0 == 0xEB or b0 == 0xEC or b0 == 0xED) {
        return .{ .invalid = undefined };
    } else if (b0 == 0xF4 or b0 == 0xFC or b0 == 0xFD) {
        return .{ .invalid = undefined };
    }

    unreachable;
}

fn instruction_load_u8_inc_pc(gb: *GBState) u8 {
    const byte = execution.load_memory_u8(gb, gb.registers.pc);

    gb.registers.pc += 1;

    return byte;
}

fn instruction_load_u16_inc_pc(gb: *GBState) u16 {
    const value = execution.load_memory_u16(gb, gb.registers.pc);

    gb.registers.pc += 2;

    return value;
}

// Read sub-u8 type from u8 value and bit offset
fn read_bits_from_byte(comptime T: type, op_byte: u8, bit_offset: usize) T {
    const src_type_bit_size = @bitSizeOf(@TypeOf(op_byte));
    const dst_type_bit_size = @bitSizeOf(T);
    assert(bit_offset + dst_type_bit_size <= src_type_bit_size);

    return @truncate(op_byte >> @intCast(bit_offset));
}

pub const R8 = enum {
    b,
    c,
    d,
    e,
    h,
    l,
    hl_p,
    a,
};

fn decode_r8(r8: u3) R8 {
    return switch (r8) {
        0 => R8.b,
        1 => R8.c,
        2 => R8.d,
        3 => R8.e,
        4 => R8.h,
        5 => R8.l,
        6 => R8.hl_p,
        7 => R8.a,
    };
}

pub const R16 = enum {
    bc,
    de,
    hl,
    sp,
    af,
};

fn decode_r16(r16: u2) R16 {
    return switch (r16) {
        0 => R16.bc,
        1 => R16.de,
        2 => R16.hl,
        3 => R16.sp,
    };
}

fn decode_r16stk(r16stk: u2) R16 {
    return switch (r16stk) {
        0 => R16.bc,
        1 => R16.de,
        2 => R16.hl,
        3 => R16.af,
    };
}

pub const R16Mem = struct {
    r16: R16,
    increment: bool,
};

fn decode_r16mem(r16mem: u2) R16Mem {
    return switch (r16mem) {
        0 => .{ .r16 = R16.bc, .increment = undefined },
        1 => .{ .r16 = R16.de, .increment = undefined },
        2 => .{ .r16 = R16.hl, .increment = true },
        3 => .{ .r16 = R16.hl, .increment = false },
    };
}

pub const Cond = enum {
    nz,
    z,
    nc,
    c,
};

fn decode_cond(cond: u2) Cond {
    return switch (cond) {
        0 => Cond.nz,
        1 => Cond.z,
        2 => Cond.nc,
        3 => Cond.c,
    };
}

fn decode_tgt3(tgt3: u3) u8 {
    return @as(u8, tgt3) * 8;
}

pub const Instruction = union(enum) {
    nop,
    ld_r16_imm16: ld_r16_imm16,
    ld_r16mem_a: ld_r16mem_a,
    ld_a_r16mem: ld_a_r16mem,
    ld_imm16_sp: ld_imm16_sp,
    inc_r16: inc_r16,
    dec_r16: dec_r16,
    add_hl_r16: add_hl_r16,
    inc_r8: inc_r8,
    dec_r8: dec_r8,
    ld_r8_imm8: ld_r8_imm8,
    rlca,
    rrca,
    rla,
    rra,
    daa,
    cpl,
    scf,
    ccf,
    jr_imm8: jr_imm8,
    jr_cond_imm8: jr_cond_imm8,
    stop,
    ld_r8_r8: ld_r8_r8,
    halt,
    add_a_r8: add_a_r8,
    adc_a_r8: adc_a_r8,
    sub_a_r8: sub_a_r8,
    sbc_a_r8: sbc_a_r8,
    and_a_r8: and_a_r8,
    xor_a_r8: xor_a_r8,
    or_a_r8: or_a_r8,
    cp_a_r8: cp_a_r8,
    add_a_imm8: add_a_imm8,
    adc_a_imm8: adc_a_imm8,
    sub_a_imm8: sub_a_imm8,
    sbc_a_imm8: sbc_a_imm8,
    and_a_imm8: and_a_imm8,
    xor_a_imm8: xor_a_imm8,
    or_a_imm8: or_a_imm8,
    cp_a_imm8: cp_a_imm8,
    ret_cond: ret_cond,
    ret,
    reti,
    jp_cond_imm16: jp_cond_imm16,
    jp_imm16: jp_imm16,
    jp_hl,
    call_cond_imm16: call_cond_imm16,
    call_imm16: call_imm16,
    rst_tgt3: rst_tgt3,
    pop_r16stk: pop_r16stk,
    push_r16stk: push_r16stk,
    ldh_c_a,
    ldh_imm8_a: ldh_imm8_a,
    ld_imm16_a: ld_imm16_a,
    ldh_a_c,
    ldh_a_imm8: ldh_a_imm8,
    ld_a_imm16: ld_a_imm16,
    add_sp_imm8: add_sp_imm8,
    ld_hl_sp_plus_imm8: ld_hl_sp_plus_imm8,
    ld_sp_hl,
    di,
    ei,
    rlc_r8: rlc_r8,
    rrc_r8: rrc_r8,
    rl_r8: rl_r8,
    rr_r8: rr_r8,
    sla_r8: sla_r8,
    sra_r8: sra_r8,
    swap_r8: swap_r8,
    srl_r8: srl_r8,
    bit_b3_r8: bit_b3_r8,
    res_b3_r8: res_b3_r8,
    set_b3_r8: set_b3_r8,
    invalid,
};

const generic_imm_u8 = struct {
    imm8: u8,
};

const generic_imm_i8 = struct {
    offset: i8,
};

const generic_imm_u16 = struct {
    imm16: u16,
};

const generic_r8 = struct {
    r8: R8,
};

const generic_r16 = struct {
    r16: R16,
};

const generic_r16stk = struct {
    r16stk: R16,
};

const generic_r16mem = struct {
    r16mem: R16Mem,
};

const generic_b3_r8 = struct {
    bit_index: u3,
    r8: R8,
};

pub const generic_cond_imm16 = struct {
    cond: Cond,
    imm16: u16,
};

pub const ld_r16_imm16 = struct {
    r16: R16,
    imm16: u16,
};

pub const ld_r16mem_a = generic_r16mem;
pub const ld_a_r16mem = generic_r16mem;

pub const ld_imm16_sp = generic_imm_u16;

pub const inc_r16 = generic_r16;
pub const dec_r16 = generic_r16;
pub const add_hl_r16 = generic_r16;

pub const inc_r8 = generic_r8;
pub const dec_r8 = generic_r8;

pub const ld_r8_imm8 = struct {
    r8: R8,
    imm8: u8,
};

pub const jr_imm8 = generic_imm_i8;

pub const jr_cond_imm8 = struct {
    cond: Cond,
    offset: i8,
};

pub const ld_r8_r8 = struct {
    r8_dst: R8,
    r8_src: R8,
};

pub const add_a_r8 = generic_r8;
pub const adc_a_r8 = generic_r8;
pub const sub_a_r8 = generic_r8;
pub const sbc_a_r8 = generic_r8;
pub const and_a_r8 = generic_r8;
pub const xor_a_r8 = generic_r8;
pub const or_a_r8 = generic_r8;
pub const cp_a_r8 = generic_r8;

pub const add_a_imm8 = generic_imm_u8;
pub const adc_a_imm8 = generic_imm_u8;
pub const sub_a_imm8 = generic_imm_u8;
pub const sbc_a_imm8 = generic_imm_u8;
pub const and_a_imm8 = generic_imm_u8;
pub const xor_a_imm8 = generic_imm_u8;
pub const or_a_imm8 = generic_imm_u8;
pub const cp_a_imm8 = generic_imm_u8;

pub const ret_cond = struct {
    cond: Cond,
};

pub const jp_cond_imm16 = generic_cond_imm16;

pub const jp_imm16 = generic_imm_u16;

pub const call_cond_imm16 = generic_cond_imm16;

pub const call_imm16 = generic_imm_u16;

pub const rst_tgt3 = struct {
    target_addr: u8,
};

pub const pop_r16stk = generic_r16stk;
pub const push_r16stk = generic_r16stk;

pub const ldh_imm8_a = generic_imm_u8;
pub const ld_imm16_a = generic_imm_u16;
pub const ldh_a_imm8 = generic_imm_u8;
pub const ld_a_imm16 = generic_imm_u16;

pub const add_sp_imm8 = generic_imm_i8;
pub const ld_hl_sp_plus_imm8 = generic_imm_i8;

pub const rlc_r8 = generic_r8;
pub const rrc_r8 = generic_r8;
pub const rl_r8 = generic_r8;
pub const rr_r8 = generic_r8;
pub const sla_r8 = generic_r8;
pub const sra_r8 = generic_r8;
pub const swap_r8 = generic_r8;
pub const srl_r8 = generic_r8;

pub const bit_b3_r8 = generic_b3_r8;
pub const res_b3_r8 = generic_b3_r8;
pub const set_b3_r8 = generic_b3_r8;
