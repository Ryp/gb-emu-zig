const std = @import("std");
const assert = std.debug.assert;

const cpu = @import("gb/cpu.zig");
const lcd = @import("gb/lcd.zig");
const instructions = @import("gb/instructions.zig");
const execution = @import("gb/execution.zig");

const sdl2_frontend = @import("sdl2_frontend.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    // const allocator = std.heap.page_allocator;

    // Parse arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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

    var gb = try cpu.create_state(allocator, buffer[0..rom_bytes]);
    defer cpu.destroy_state(allocator, &gb);

    try sdl2_frontend.execute_main_loop(allocator, &gb);
}
