const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const cpu = @import("cpu.zig");
const instructions = @import("instructions.zig");
const execution = @import("execution.zig");

test {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const rom_bytes = [2]u8{ 3, 3 };

    var gb = try cpu.create_state(allocator, &rom_bytes);
    defer cpu.destroy_state(allocator, &gb);

    try expectEqual(0x00, gb.registers.b);
    try expectEqual(0x13, gb.registers.c);
    try expectEqual(0x00, gb.registers.d);
    try expectEqual(0xD8, gb.registers.e);
    try expectEqual(0x01, gb.registers.h);
    try expectEqual(0x4D, gb.registers.l);
    try expectEqual(0x01, gb.registers.a);
    try expectEqual(cpu.FlagRegister{
        ._unused = 0,
        .carry = 1,
        .half_carry = 1,
        .substract = false,
        .zero = true,
    }, gb.registers.flags);
    try expectEqual(0xFFFE, gb.registers.sp);
    try expectEqual(0x0100, gb.registers.pc);

    gb.registers.a = 25;
    execution.execute_instruction(&gb, .{ .byte_len = 1, .encoding = .{ .add_a_r8 = .{ .r8 = instructions.R8.a } } });

    try expectEqual(50, gb.registers.a);

    gb.registers.b = 1;
    execution.execute_instruction(&gb, .{ .byte_len = 1, .encoding = .{ .add_a_r8 = .{ .r8 = instructions.R8.b } } });

    try expectEqual(1, gb.registers.b);

    execution.execute_instruction(&gb, .{ .byte_len = 1, .encoding = .{ .res_b3_r8 = .{ .bit_index = 0, .r8 = instructions.R8.b } } });

    try expectEqual(0, gb.registers.b);

    try expectEqual(51, gb.registers.a);
}
