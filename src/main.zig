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

    // FIXME I don't support ROMs with swappable address space
    var buffer: [256 * 128]u8 = undefined; // FIXME
    const rom_bytes = try file.read(buffer[0..buffer.len]);

    var gb_state = try gb.create_state(gpa_allocator, buffer[0..rom_bytes]);
    defer gb.destroy_state(gpa_allocator, &gb_state);

    while (true) {
        std.debug.print("===================================\n", .{});
        std.debug.print("====| PC = {x:4}, SP = {x:4}\n", .{ gb_state.registers.pc, gb_state.registers.sp });
        std.debug.print("====| A = {x:2}, Flags: {s} {s} {s} {s}\n", .{
            gb_state.registers.a,
            if (gb_state.registers.flags.zero == 1) "Z" else "_",
            if (gb_state.registers.flags.substract == 1) "N" else "_",
            if (gb_state.registers.flags.half_carry == 1) "H" else "_",
            if (gb_state.registers.flags.carry == 1) "C" else "_",
        });
        std.debug.print("====| B = {x:2}, C = {x:2}\n", .{ gb_state.registers.b, gb_state.registers.c });
        std.debug.print("====| D = {x:2}, E = {x:2}\n", .{ gb_state.registers.d, gb_state.registers.e });
        std.debug.print("====| H = {x:2}, L = {x:2}\n", .{ gb_state.registers.h, gb_state.registers.l });
        std.debug.print("===================================\n", .{});

        const i = try instructions.decode(gb_state.memory[gb_state.registers.pc..]);

        const i_mem = gb_state.memory[gb_state.registers.pc .. gb_state.registers.pc + i.byte_len];
        std.debug.print("[debug] op bytes = {b:8}, {x:2}\n", .{ i_mem, i_mem });

        instructions.debug_print(i);

        gb_state.registers.pc += i.byte_len;

        execution.execute_instruction(&gb_state, i);
    }
}
