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

    var gb_state = try cpu.create_state(allocator);
    defer cpu.destroy_state(allocator, &gb_state);

    try expectEqual(0x00, gb_state.cpu.b);
    try expectEqual(0x13, gb_state.cpu.c);
    try expectEqual(0x00, gb_state.cpu.d);
    try expectEqual(0xD8, gb_state.cpu.e);
    try expectEqual(0x01, gb_state.cpu.h);
    try expectEqual(0x4D, gb_state.cpu.l);
    try expectEqual(0x01, gb_state.cpu.a);
    try expectEqual(cpu.FlagRegister{
        ._unused = 0,
        .carry = 1,
        .half_carry = 1,
        .substract = 0,
        .zero = 1,
    }, gb_state.cpu.flags);
    try expectEqual(0xFFFE, gb_state.cpu.sp);
    try expectEqual(0x0100, gb_state.cpu.pc);

    gb_state.mem[0] = 0b00110001;
    gb_state.mem[1] = 0b11001101;
    gb_state.mem[2] = 0b00110111;

    const i = try instructions.decode(gb_state.mem);

    execution.execute_instruction(&gb_state, i);
}
