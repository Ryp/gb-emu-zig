const std = @import("std");
const assert = std.debug.assert;

const gb = @import("gb/cpu.zig");
// const sdl2 = @import("sdl2_frontend.zig");
const instructions = @import("gb/instructions.zig");
const execution = @import("gb/execution.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const gpa_allocator = gpa.allocator();
    // const allocator = std.heap.page_allocator;

    // Parse arguments
    const args = try std.process.argsAlloc(gpa_allocator);
    defer std.process.argsFree(gpa_allocator, args);

    // assert(args.len == 2);

    var gb_state = try gb.create_state(gpa_allocator);
    defer gb.destroy_state(gpa_allocator, &gb_state);

    // try sdl2.execute_main_loop(gpa_allocator, &gb_state);

    gb_state.mem[gb_state.registers.pc + 0] = 0b00110001;
    gb_state.mem[gb_state.registers.pc + 1] = 0b11001101;
    gb_state.mem[gb_state.registers.pc + 2] = 0b00110111;

    std.debug.print("gb emu\n", .{});

    while (gb_state.running) {
        std.debug.print("loop: pc = {}\n", .{gb_state.registers.pc});

        const i = try instructions.decode(gb_state.mem[gb_state.registers.pc..]);

        execution.execute_instruction(&gb_state, i);

        gb_state.registers.pc += i.byte_len;
    }
}
