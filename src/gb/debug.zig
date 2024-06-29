const std = @import("std");

const instructions = @import("instructions.zig");

pub fn print_instruction(instruction: instructions.Instruction) void {
    const print = std.debug.print;

    switch (instruction) {
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

fn r8_to_string(r8: instructions.R8) [:0]const u8 {
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

fn r16_to_string(r16: instructions.R16) [:0]const u8 {
    return switch (r16) {
        .bc => "bc",
        .de => "de",
        .hl => "hl",
        .sp => "sp",
        .af => unreachable,
    };
}

fn r16mem_to_string(r16mem: instructions.R16Mem) [:0]const u8 {
    return switch (r16mem.r16) {
        .bc => "bc",
        .de => "de",
        .hl => if (r16mem.increment) "hl+" else "hl-",
        else => unreachable,
    };
}

fn r16stk_to_string(r16stk: instructions.R16) [:0]const u8 {
    return switch (r16stk) {
        .bc => "bc",
        .de => "de",
        .hl => "hl",
        .sp => unreachable,
        .af => "af",
    };
}

fn cond_to_string(cond: instructions.Cond) [:0]const u8 {
    return @tagName(cond);
}

const cart = @import("cart.zig");

pub fn mbc_type_to_string(mbc_type: cart.MBCType) [:0]const u8 {
    return @tagName(mbc_type);
}
