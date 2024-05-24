const std = @import("std");
const assert = std.debug.assert;
const gb_endian = std.builtin.Endian.little;

pub fn decode(mem: []const u8) !Instruction {
    const b0 = mem[0];

    if (b0 == 0b0000_0000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .nop = undefined } };
    } else if ((b0 & 0b1100_1111) == 0b0000_0001) {
        return Instruction{ .byte_len = 3, .encoding = .{ .ld_r16_imm16 = .{
            .r16 = decode_r16(read_bits_from_byte(u2, b0, 4)),
            .imm16 = std.mem.readVarInt(u16, mem[1..3], gb_endian),
        } } };
    } else if ((b0 & 0b1100_1111) == 0b0000_0010) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ld_r16mem_a = .{
            .r16mem = decode_r16mem(read_bits_from_byte(u2, b0, 4)),
        } } };
    } else if ((b0 & 0b1100_1111) == 0b0000_1010) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ld_a_r16mem = .{
            .r16mem = decode_r16mem(read_bits_from_byte(u2, b0, 4)),
        } } };
    } else if (b0 == 0b0000_1000) {
        return Instruction{ .byte_len = 3, .encoding = .{ .ld_imm16_sp = .{
            .imm16 = std.mem.readVarInt(u16, mem[1..3], gb_endian),
        } } };
    } else if ((b0 & 0b1100_1111) == 0b0000_0011) {
        return Instruction{ .byte_len = 1, .encoding = .{ .inc_r16 = .{
            .r16 = decode_r16(read_bits_from_byte(u2, b0, 4)),
        } } };
    } else if ((b0 & 0b1100_1111) == 0b0000_1011) {
        return Instruction{ .byte_len = 1, .encoding = .{ .dec_r16 = .{
            .r16 = decode_r16(read_bits_from_byte(u2, b0, 4)),
        } } };
    } else if ((b0 & 0b1100_1111) == 0b0000_1001) {
        return Instruction{ .byte_len = 1, .encoding = .{ .add_hl_r16 = .{
            .r16 = decode_r16(read_bits_from_byte(u2, b0, 4)),
        } } };
    } else if ((b0 & 0b1100_0111) == 0b0000_0100) {
        return Instruction{ .byte_len = 1, .encoding = .{ .inc_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 3)),
        } } };
    } else if ((b0 & 0b1100_0111) == 0b0000_0101) {
        return Instruction{ .byte_len = 1, .encoding = .{ .dec_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 3)),
        } } };
    } else if ((b0 & 0b1100_0111) == 0b0000_0110) {
        return Instruction{ .byte_len = 2, .encoding = .{ .ld_r8_imm8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 3)),
            .imm8 = mem[1],
        } } };
    } else if (b0 == 0b0000_0111) {
        return Instruction{ .byte_len = 1, .encoding = .{ .rlca = undefined } };
    } else if (b0 == 0b0000_1111) {
        return Instruction{ .byte_len = 1, .encoding = .{ .rrca = undefined } };
    } else if (b0 == 0b0001_0111) {
        return Instruction{ .byte_len = 1, .encoding = .{ .rla = undefined } };
    } else if (b0 == 0b0001_1111) {
        return Instruction{ .byte_len = 1, .encoding = .{ .rra = undefined } };
    } else if (b0 == 0b0010_0111) {
        return Instruction{ .byte_len = 1, .encoding = .{ .daa = undefined } };
    } else if (b0 == 0b0010_1111) {
        return Instruction{ .byte_len = 1, .encoding = .{ .cpl = undefined } };
    } else if (b0 == 0b0011_0111) {
        return Instruction{ .byte_len = 1, .encoding = .{ .scf = undefined } };
    } else if (b0 == 0b0011_1111) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ccf = undefined } };
    } else if (b0 == 0b0001_1000) {
        return Instruction{ .byte_len = 2, .encoding = .{ .jr_imm8 = .{
            .offset = @bitCast(mem[1]),
        } } };
    } else if ((b0 & 0b1110_0111) == 0b0010_0000) {
        return Instruction{ .byte_len = 2, .encoding = .{ .jr_cond_imm8 = .{
            .cond = decode_cond(read_bits_from_byte(u2, b0, 3)),
            .offset = @bitCast(mem[1]),
        } } };
    } else if (b0 == 0b0001_0000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .stop = undefined } }; // FIXME stuff about stop being 2 instructions
    } else if (b0 == 0b0111_0110) {
        return Instruction{ .byte_len = 1, .encoding = .{ .halt = undefined } }; // Parse halt first or it'll be eaten by ld_r8_r8
    } else if ((b0 & 0b1100_0000) == 0b0100_0000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ld_r8_r8 = .{
            .r8_dst = decode_r8(read_bits_from_byte(u3, b0, 3)),
            .r8_src = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } } };
    } else if ((b0 & 0b1111_1000) == 0b1000_0000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .add_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } } };
    } else if ((b0 & 0b1111_1000) == 0b1000_1000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .adc_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } } };
    } else if ((b0 & 0b1111_1000) == 0b1001_0000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .sub_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } } };
    } else if ((b0 & 0b1111_1000) == 0b1001_1000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .sbc_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } } };
    } else if ((b0 & 0b1111_1000) == 0b1010_0000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .and_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } } };
    } else if ((b0 & 0b1111_1000) == 0b1010_1000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .xor_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } } };
    } else if ((b0 & 0b1111_1000) == 0b1011_0000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .or_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } } };
    } else if ((b0 & 0b1111_1000) == 0b1011_1000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .cp_a_r8 = .{
            .r8 = decode_r8(read_bits_from_byte(u3, b0, 0)),
        } } };
    } else if (b0 == 0b1100_0110) {
        return Instruction{ .byte_len = 2, .encoding = .{ .add_a_imm8 = .{ .imm8 = mem[1] } } };
    } else if (b0 == 0b1100_1110) {
        return Instruction{ .byte_len = 2, .encoding = .{ .adc_a_imm8 = .{ .imm8 = mem[1] } } };
    } else if (b0 == 0b1101_0110) {
        return Instruction{ .byte_len = 2, .encoding = .{ .sub_a_imm8 = .{ .imm8 = mem[1] } } };
    } else if (b0 == 0b1101_1110) {
        return Instruction{ .byte_len = 2, .encoding = .{ .sbc_a_imm8 = .{ .imm8 = mem[1] } } };
    } else if (b0 == 0b1110_0110) {
        return Instruction{ .byte_len = 2, .encoding = .{ .and_a_imm8 = .{ .imm8 = mem[1] } } };
    } else if (b0 == 0b1110_1110) {
        return Instruction{ .byte_len = 2, .encoding = .{ .xor_a_imm8 = .{ .imm8 = mem[1] } } };
    } else if (b0 == 0b1111_0110) {
        return Instruction{ .byte_len = 2, .encoding = .{ .or_a_imm8 = .{ .imm8 = mem[1] } } };
    } else if (b0 == 0b1111_1110) {
        return Instruction{ .byte_len = 2, .encoding = .{ .cp_a_imm8 = .{ .imm8 = mem[1] } } };
    } else if ((b0 & 0b1110_0111) == 0b1100_0000) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ret_cond = .{
            .cond = decode_cond(read_bits_from_byte(u2, b0, 3)),
        } } };
    } else if (b0 == 0b1100_1001) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ret = undefined } };
    } else if (b0 == 0b1101_1001) {
        return Instruction{ .byte_len = 1, .encoding = .{ .reti = undefined } };
    } else if ((b0 & 0b1110_0111) == 0b1100_0010) {
        return Instruction{ .byte_len = 3, .encoding = .{ .jp_cond_imm16 = .{
            .cond = decode_cond(read_bits_from_byte(u2, b0, 3)),
            .imm16 = std.mem.readVarInt(u16, mem[1..3], gb_endian),
        } } };
    } else if (b0 == 0b1100_0011) {
        return Instruction{ .byte_len = 3, .encoding = .{ .jp_imm16 = .{
            .imm16 = std.mem.readVarInt(u16, mem[1..3], gb_endian),
        } } };
    } else if (b0 == 0b1110_1001) {
        return Instruction{ .byte_len = 1, .encoding = .{ .jp_hl = undefined } };
    } else if ((b0 & 0b1110_0111) == 0b1100_0100) {
        return Instruction{ .byte_len = 3, .encoding = .{ .call_cond_imm16 = .{
            .cond = decode_cond(read_bits_from_byte(u2, b0, 3)),
            .imm16 = std.mem.readVarInt(u16, mem[1..3], gb_endian),
        } } };
    } else if (b0 == 0b1100_1101) {
        return Instruction{ .byte_len = 3, .encoding = .{ .call_imm16 = .{
            .imm16 = std.mem.readVarInt(u16, mem[1..3], gb_endian),
        } } };
    } else if ((b0 & 0b1100_0111) == 0b1100_0111) {
        return Instruction{ .byte_len = 1, .encoding = .{ .rst_tgt3 = .{
            .target_addr = decode_tgt3(read_bits_from_byte(u3, b0, 3)),
        } } };
    } else if ((b0 & 0b1100_1111) == 0b1100_0001) {
        return Instruction{ .byte_len = 1, .encoding = .{ .pop_r16stk = .{
            .r16stk = decode_r16stk(read_bits_from_byte(u2, b0, 4)),
        } } };
    } else if ((b0 & 0b1100_1111) == 0b1100_0101) {
        return Instruction{ .byte_len = 1, .encoding = .{ .push_r16stk = .{
            .r16stk = decode_r16stk(read_bits_from_byte(u2, b0, 4)),
        } } };
    } else if (b0 == 0b1100_1011) { // 0xCB prefix opcodes
        const b1 = mem[1];
        const masked_b1_a = b1 & 0b1111_1000;
        const masked_b1_b = b1 & 0b1100_0000;

        if (masked_b1_a == 0b0000_0000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .rlc_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_a == 0b0000_1000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .rrc_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_a == 0b0001_0000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .rl_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_a == 0b0001_1000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .rr_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_a == 0b0010_0000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .sla_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_a == 0b0010_1000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .sra_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_a == 0b0011_0000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .swap_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_a == 0b0011_1000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .srl_r8 = .{
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_b == 0b0100_0000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .bit_b3_r8 = .{
                .bit_index = read_bits_from_byte(u3, b1, 3),
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_b == 0b1000_0000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .res_b3_r8 = .{
                .bit_index = read_bits_from_byte(u3, b1, 3),
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        } else if (masked_b1_b == 0b1100_0000) {
            return Instruction{ .byte_len = 2, .encoding = .{ .set_b3_r8 = .{
                .bit_index = read_bits_from_byte(u3, b1, 3),
                .r8 = decode_r8(read_bits_from_byte(u3, b1, 0)),
            } } };
        }
    } else if (b0 == 0b1110_0010) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ldh_c_a = undefined } };
    } else if (b0 == 0b1110_0000) {
        return Instruction{ .byte_len = 2, .encoding = .{ .ldh_imm8_a = .{ .imm8 = mem[1] } } };
    } else if (b0 == 0b1110_1010) {
        return Instruction{ .byte_len = 3, .encoding = .{ .ld_imm16_a = .{
            .imm16 = std.mem.readVarInt(u16, mem[1..3], gb_endian),
        } } };
    } else if (b0 == 0b1111_0010) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ldh_a_c = undefined } };
    } else if (b0 == 0b1111_0000) {
        return Instruction{ .byte_len = 2, .encoding = .{ .ldh_a_imm8 = .{ .imm8 = mem[1] } } };
    } else if (b0 == 0b1111_1010) {
        return Instruction{ .byte_len = 3, .encoding = .{ .ld_a_imm16 = .{
            .imm16 = std.mem.readVarInt(u16, mem[1..3], gb_endian),
        } } };
    } else if (b0 == 0b1110_1000) {
        return Instruction{ .byte_len = 2, .encoding = .{ .add_sp_imm8 = .{ .offset = @bitCast(mem[1]) } } };
    } else if (b0 == 0b1111_1000) {
        return Instruction{ .byte_len = 2, .encoding = .{ .ld_hl_sp_plus_imm8 = .{ .offset = @bitCast(mem[1]) } } };
    } else if (b0 == 0b1111_1001) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ld_sp_hl = undefined } };
    } else if (b0 == 0b1111_0011) {
        return Instruction{ .byte_len = 1, .encoding = .{ .di = undefined } };
    } else if (b0 == 0b1111_1011) {
        return Instruction{ .byte_len = 1, .encoding = .{ .ei = undefined } };
    } else if (b0 == 0xD3 or b0 == 0xDB or b0 == 0xDD) {
        return Instruction{ .byte_len = 1, .encoding = .{ .invalid = undefined } };
    } else if (b0 == 0xE3 or b0 == 0xE4 or b0 == 0xEB or b0 == 0xEC or b0 == 0xED) {
        return Instruction{ .byte_len = 1, .encoding = .{ .invalid = undefined } };
    } else if (b0 == 0xF4 or b0 == 0xFC or b0 == 0xFD) {
        return Instruction{ .byte_len = 1, .encoding = .{ .invalid = undefined } };
    }

    return error.UnknownInstruction;
}

// Read sub-u8 type from u8 value and bit offset
fn read_bits_from_byte(comptime T: type, op_byte: u8, bit_offset: usize) T {
    const src_type_bit_size = @bitSizeOf(@TypeOf(op_byte));
    const dst_type_bit_size = @bitSizeOf(T);
    assert(bit_offset + dst_type_bit_size <= src_type_bit_size);

    return @truncate(op_byte >> @intCast(bit_offset));
}

const OpCode = enum {
    nop,
    ld_r16_imm16,
    ld_r16mem_a,
    ld_a_r16mem,
    ld_imm16_sp,
    inc_r16,
    dec_r16,
    add_hl_r16,
    inc_r8,
    dec_r8,
    ld_r8_imm8,
    rlca,
    rrca,
    rla,
    rra,
    daa,
    cpl,
    scf,
    ccf,
    jr_imm8,
    jr_cond_imm8,
    stop,
    ld_r8_r8,
    halt,
    add_a_r8,
    adc_a_r8,
    sub_a_r8,
    sbc_a_r8,
    and_a_r8,
    xor_a_r8,
    or_a_r8,
    cp_a_r8,
    add_a_imm8,
    adc_a_imm8,
    sub_a_imm8,
    sbc_a_imm8,
    and_a_imm8,
    xor_a_imm8,
    or_a_imm8,
    cp_a_imm8,
    ret_cond,
    ret,
    reti,
    jp_cond_imm16,
    jp_imm16,
    jp_hl,
    call_cond_imm16,
    call_imm16,
    rst_tgt3,
    pop_r16stk,
    push_r16stk,
    ldh_c_a,
    ldh_imm8_a,
    ld_imm16_a,
    ldh_a_c,
    ldh_a_imm8,
    ld_a_imm16,
    add_sp_imm8,
    ld_hl_sp_plus_imm8,
    ld_sp_hl,
    di,
    ei,
    rlc_r8,
    rrc_r8,
    rl_r8,
    rr_r8,
    sla_r8,
    sra_r8,
    swap_r8,
    srl_r8,
    bit_b3_r8,
    res_b3_r8,
    set_b3_r8,
    invalid,
};

pub const Instruction = struct {
    byte_len: u2,
    encoding: union(OpCode) {
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
    },
};

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

pub const jp_cond_imm16 = struct {
    cond: Cond,
    imm16: u16,
};

pub const jp_imm16 = generic_imm_u16;

pub const call_cond_imm16 = struct {
    cond: Cond,
    imm16: u16,
};

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

fn r8_to_string(r8: R8) [:0]const u8 {
    return switch (r8) {
        .b => "b",
        .c => "c",
        .d => "d",
        .e => "e",
        .h => "h",
        .l => "l",
        .hl_p => "[hl]",
        .a => "a",
    };
}

fn r16_to_string(r16: R16) [:0]const u8 {
    return switch (r16) {
        .bc => "bc",
        .de => "de",
        .hl => "hl",
        .sp => "sp",
        .af => unreachable,
    };
}

fn r16mem_to_string(r16mem: R16Mem) [:0]const u8 {
    return switch (r16mem.r16) {
        .bc => "bc",
        .de => "de",
        .hl => if (r16mem.increment) "hl+" else "hl-",
        else => unreachable,
    };
}

fn r16stk_to_string(r16stk: R16) [:0]const u8 {
    return switch (r16stk) {
        .bc => "bc",
        .de => "de",
        .hl => "hl",
        .sp => unreachable,
        .af => "af",
    };
}

fn cond_to_string(cond: Cond) [:0]const u8 {
    return switch (cond) {
        .nz => "nz",
        .z => "z",
        .nc => "nc",
        .c => "c",
    };
}

pub fn debug_print(instruction: Instruction) void {
    const print = std.debug.print;

    switch (instruction.encoding) {
        .nop => print("nop\n", .{}),
        .ld_r16_imm16 => |i| print("ld {s}, {x:0>4}\n", .{ r16_to_string(i.r16), i.imm16 }),
        .ld_r16mem_a => |i| print("ld [{s}], a\n", .{r16mem_to_string(i.r16mem)}),
        .ld_a_r16mem => |i| print("ld a, [{s}]\n", .{r16mem_to_string(i.r16mem)}),
        .ld_imm16_sp => |i| print("ld [{x:0>4}], sp\n", .{i.imm16}),
        .inc_r16 => |i| print("inc {s}\n", .{r16_to_string(i.r16)}),
        .dec_r16 => |i| print("dec {s}\n", .{r16_to_string(i.r16)}),
        .add_hl_r16 => |i| print("add hl, {s}\n", .{r16_to_string(i.r16)}),
        .inc_r8 => |i| print("inc {s}\n", .{r8_to_string(i.r8)}),
        .dec_r8 => |i| print("dec {s}\n", .{r8_to_string(i.r8)}),
        .ld_r8_imm8 => |i| print("ld {s}, {x:0>2}\n", .{ r8_to_string(i.r8), i.imm8 }),
        .rlca => print("rlca\n", .{}),
        .rrca => print("rrca\n", .{}),
        .rla => print("rla\n", .{}),
        .rra => print("rra\n", .{}),
        .daa => print("daa\n", .{}),
        .cpl => print("cpl\n", .{}),
        .scf => print("scf\n", .{}),
        .ccf => print("ccf\n", .{}),
        .jr_imm8 => |i| print("jr {} (dec)\n", .{i.offset}),
        .jr_cond_imm8 => |i| print("jr {s}, {} (dec)\n", .{ cond_to_string(i.cond), i.offset }),
        .stop => print("stop\n", .{}),
        .ld_r8_r8 => |i| print("ld {s}, {s}\n", .{ r8_to_string(i.r8_dst), r8_to_string(i.r8_src) }),
        .halt => print("halt\n", .{}),
        .add_a_r8 => |i| print("add a, {s}\n", .{r8_to_string(i.r8)}),
        .adc_a_r8 => |i| print("adc a, {s}\n", .{r8_to_string(i.r8)}),
        .sub_a_r8 => |i| print("sub a, {s}\n", .{r8_to_string(i.r8)}),
        .sbc_a_r8 => |i| print("sbc a, {s}\n", .{r8_to_string(i.r8)}),
        .and_a_r8 => |i| print("and a, {s}\n", .{r8_to_string(i.r8)}),
        .xor_a_r8 => |i| print("xor a, {s}\n", .{r8_to_string(i.r8)}),
        .or_a_r8 => |i| print("or a, {s}\n", .{r8_to_string(i.r8)}),
        .cp_a_r8 => |i| print("cp a, {s}\n", .{r8_to_string(i.r8)}),
        .add_a_imm8 => |i| print("add a, {x:0>2}\n", .{i.imm8}),
        .adc_a_imm8 => |i| print("adc a, {x:0>2}\n", .{i.imm8}),
        .sub_a_imm8 => |i| print("sub a, {x:0>2}\n", .{i.imm8}),
        .sbc_a_imm8 => |i| print("sbc a, {x:0>2}\n", .{i.imm8}),
        .and_a_imm8 => |i| print("and a, {x:0>2}\n", .{i.imm8}),
        .xor_a_imm8 => |i| print("xor a, {x:0>2}\n", .{i.imm8}),
        .or_a_imm8 => |i| print("or a, {x:0>2}\n", .{i.imm8}),
        .cp_a_imm8 => |i| print("cp a, {x:0>2}\n", .{i.imm8}),
        .ret_cond => |i| print("ret {s}\n", .{cond_to_string(i.cond)}),
        .ret => print("ret\n", .{}),
        .reti => print("reti\n", .{}),
        .jp_cond_imm16 => |i| print("jp {s}, {x:0>4}\n", .{ cond_to_string(i.cond), i.imm16 }),
        .jp_imm16 => |i| print("jp {x:0>4}\n", .{i.imm16}),
        .jp_hl => print("jp hl\n", .{}),
        .call_cond_imm16 => |i| print("call {s}, {x:0>4}\n", .{ cond_to_string(i.cond), i.imm16 }),
        .call_imm16 => |i| print("call {x:0>4}\n", .{i.imm16}),
        .rst_tgt3 => |i| print("rst {x:0>2}\n", .{i.target_addr}),
        .pop_r16stk => |i| print("pop {s}\n", .{r16stk_to_string(i.r16stk)}),
        .push_r16stk => |i| print("push {s}\n", .{r16stk_to_string(i.r16stk)}),
        .ldh_c_a => print("ld [c], a\n", .{}),
        .ldh_imm8_a => |i| print("ldh [{x:0>2}], a\n", .{i.imm8}),
        .ld_imm16_a => |i| print("ldh [{x:0>4}], a\n", .{i.imm16}),
        .ldh_a_c => print("ld a, [c]\n", .{}),
        .ldh_a_imm8 => |i| print("ldh a, [{x:0>2}]\n", .{i.imm8}),
        .ld_a_imm16 => |i| print("ldh a, [{x:0>4}]\n", .{i.imm16}),
        .add_sp_imm8 => |i| print("add sp, {} (dec)\n", .{i.offset}),
        .ld_hl_sp_plus_imm8 => |i| print("ld hl, sp + {} (dec)\n", .{i.offset}),
        .ld_sp_hl => print("ld sp, hl\n", .{}),
        .di => print("di\n", .{}),
        .ei => print("ei\n", .{}),
        .rlc_r8 => |i| print("rlc {s}\n", .{r8_to_string(i.r8)}),
        .rrc_r8 => |i| print("rrc {s}\n", .{r8_to_string(i.r8)}),
        .rl_r8 => |i| print("rl {s}\n", .{r8_to_string(i.r8)}),
        .rr_r8 => |i| print("rr {s}\n", .{r8_to_string(i.r8)}),
        .sla_r8 => |i| print("sla {s}\n", .{r8_to_string(i.r8)}),
        .sra_r8 => |i| print("sra {s}\n", .{r8_to_string(i.r8)}),
        .swap_r8 => |i| print("swap {s}\n", .{r8_to_string(i.r8)}),
        .srl_r8 => |i| print("srl {s}\n", .{r8_to_string(i.r8)}),
        .bit_b3_r8 => |i| print("bit {}, {s}\n", .{ i.bit_index, r8_to_string(i.r8) }),
        .res_b3_r8 => |i| print("res {}, {s}\n", .{ i.bit_index, r8_to_string(i.r8) }),
        .set_b3_r8 => |i| print("set {}, {s}\n", .{ i.bit_index, r8_to_string(i.r8) }),
        .invalid => print("invalid\n", .{}),
    }
}
