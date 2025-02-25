const std = @import("std");
const assert = std.debug.assert;

const cpu = @import("gb/cpu.zig");
const cart = @import("gb/cart.zig");
const instructions = @import("gb/instructions.zig");
const execution = @import("gb/execution.zig");
const debug = @import("gb/debug.zig");

const sdl_frontend = @import("sdl.zig");

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

    var rom_buffer: [cart.MaxROMByteSize]u8 = undefined;
    const rom_bytes_read = try file.read(&rom_buffer);

    var cart_state = try cart.create_cart_state(allocator, rom_buffer[0..rom_bytes_read]);
    defer cart.destroy_cart_state(allocator, &cart_state);

    std.debug.print("debug: Cart Type = '{s}'\n", .{debug.mbc_type_to_string(cart_state.mbc_state)});

    var gb = try cpu.create_gb_state(allocator, &cart_state);
    defer cpu.destroy_gb_state(allocator, &gb);

    try sdl_frontend.execute_main_loop(allocator, &gb);
}
