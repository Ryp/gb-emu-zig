const std = @import("std");
const assert = std.debug.assert;

const gb = @import("gb/cpu.zig");
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

    if (args.len < 2) {
        std.debug.print("error: missing ROM filename\n", .{});
        return error.MissingArgument;
    }

    const rom_filename = args[1];

    // FIXME What the idiomatic way of writing this?
    var file = if (std.fs.cwd().openFile(rom_filename, .{})) |f| f else |err| {
        std.debug.print("error: couldn't open ROM file: '{s}'\n", .{rom_filename});
        return err;
    };
    defer file.close();

    var buffer: [1024 * 4]u8 = undefined; // FIXME
    const rom_bytes = try file.read(buffer[0..buffer.len]);

    var gb_state = try gb.create_state(gpa_allocator, buffer[0..rom_bytes]);
    defer gb.destroy_state(gpa_allocator, &gb_state);

    while (true) {
        std.debug.print("loop: pc = {}\n", .{gb_state.registers.pc});

        const i = try instructions.decode(gb_state.mem[gb_state.registers.pc..]);

        const i_mem = gb_state.mem[gb_state.registers.pc .. gb_state.registers.pc + i.byte_len];
        std.debug.print("[debug] op bytes = {b:8}, {x:2}\n", .{ i_mem, i_mem });

        instructions.debug_print(i);

        gb_state.registers.pc += i.byte_len;

        execution.execute_instruction(&gb_state, i);
    }
}
