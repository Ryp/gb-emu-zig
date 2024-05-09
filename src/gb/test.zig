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

    var gb_state = try cpu.create_state(allocator, &rom_bytes);
    defer cpu.destroy_state(allocator, &gb_state);

    try expectEqual(0x00, gb_state.registers.b);
    try expectEqual(0x13, gb_state.registers.c);
    try expectEqual(0x00, gb_state.registers.d);
    try expectEqual(0xD8, gb_state.registers.e);
    try expectEqual(0x01, gb_state.registers.h);
    try expectEqual(0x4D, gb_state.registers.l);
    try expectEqual(0x01, gb_state.registers.a);
    try expectEqual(cpu.FlagRegister{
        ._unused = 0,
        .carry = 1,
        .half_carry = 1,
        .substract = 0,
        .zero = 1,
    }, gb_state.registers.flags);
    try expectEqual(0xFFFE, gb_state.registers.sp);
    try expectEqual(0x0100, gb_state.registers.pc);
}
