const std = @import("std");
const assert = std.debug.assert;

const cpu = @import("gb/cpu.zig");
const lcd = @import("gb/lcd.zig");
const instructions = @import("gb/instructions.zig");
const execution = @import("gb/execution.zig");

const enable_debug = false;

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

    var gb = try cpu.create_state(gpa_allocator, buffer[0..rom_bytes]);
    defer cpu.destroy_state(gpa_allocator, &gb);

    while (true) {
        try step(&gb);
    }
}

fn step(gb: *cpu.GBState) !void {
    const interrupt_mask_to_service = gb.mmio.IF.requested_interrupts_mask & gb.mmio.IE.enable_interrupts_mask;

    var current_instruction: instructions.Instruction = undefined;

    // Service interrupts
    if (gb.enable_interrupts_master and interrupt_mask_to_service != 0) {
        const interrupt_bit_index = @ctz(interrupt_mask_to_service); // First set bit gets priority
        const interrupt_bit_mask: u5 = @intCast(@as(u16, 1) << interrupt_bit_index);
        const interrupt_jump_address: u8 = 0x40 + @as(u8, interrupt_bit_index) * 0x08;

        gb.mmio.IF.requested_interrupts_mask &= ~interrupt_bit_mask; // Mark current interrupt as serviced
        gb.enable_interrupts_master = false; // Disable interrupts while we service them

        // FIXME check how 'byte_len' intereferes with clock timing
        // FIXME also we're using byte_len to reset PC to the location BEFORE executing
        current_instruction = instructions.Instruction{ .byte_len = 3, .encoding = .{ .call_imm16 = .{
            .imm16 = interrupt_jump_address,
        } } };
    } else {
        current_instruction = try instructions.decode(gb.memory[gb.registers.pc..]);
    }

    if (enable_debug) {
        print_register_debug(gb.registers);

        const i_mem = gb.memory[gb.registers.pc .. gb.registers.pc + current_instruction.byte_len];
        std.debug.print("[debug] op bytes = {b:0>8}, {x:0>2}\n", .{ i_mem, i_mem });

        instructions.debug_print(current_instruction);
    }

    // Normally this would take some cycles to complete, but we take this into account
    // a tiny bit later.
    gb.registers.pc += current_instruction.byte_len;

    execution.execute_instruction(gb, current_instruction);

    // We're decoding all instructions fully before executing them.
    // Each byte read actually makes the CPU spin another 4 cycles, so we can just
    // add them here after the fact
    gb.pending_cycles += @as(u8, current_instruction.byte_len) * 4;

    consume_pending_cycles(gb);
}

fn consume_pending_cycles(gb: *cpu.GBState) void {
    gb.total_cycles += gb.pending_cycles;

    if (gb.pending_cycles > 0) {
        lcd.step_pixel_processing_unit(gb, gb.pending_cycles);
    }

    if (enable_debug) {
        std.debug.print("cycles consumed: {}\n", .{gb.pending_cycles});
        std.debug.print("total cycles = {:0>12}\n", .{gb.total_cycles});
    }

    gb.pending_cycles = 0; // FIXME
}

fn print_register_debug(registers: cpu.Registers) void {
    std.debug.print("===================================\n", .{});
    std.debug.print("====| PC = {x:0>4}, SP = {x:0>4}\n", .{ registers.pc, registers.sp });
    std.debug.print("====| A = {x:0>2}, Flags: {s} {s} {s} {s}\n", .{
        registers.a,
        if (registers.flags.zero == 1) "Z" else "_",
        if (registers.flags.substract == 1) "N" else "_",
        if (registers.flags.half_carry == 1) "H" else "_",
        if (registers.flags.carry == 1) "C" else "_",
    });
    std.debug.print("====| B = {x:0>2}, C = {x:0>2}\n", .{ registers.b, registers.c });
    std.debug.print("====| D = {x:0>2}, E = {x:0>2}\n", .{ registers.d, registers.e });
    std.debug.print("====| H = {x:0>2}, L = {x:0>2}\n", .{ registers.h, registers.l });
    std.debug.print("===================================\n", .{});
}
