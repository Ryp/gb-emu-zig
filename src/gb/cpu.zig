const std = @import("std");

pub const GBState = struct {
    cpu: CPUState,
    mem: []u8,
    running: bool,
};

pub const CPUState = struct {
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    a: u8,
    f: FlagRegister,
    sp: u16, // Stack Pointer
    pc: u16, // Program Counter
};

pub const FlagRegister = packed struct {
    _unused0: u1,
    _unused1: u1,
    _unused2: u1,
    _unused3: u1,
    carry: u1,
    half_carry: u1,
    n_add_sub: u1,
    zero: u1,
};

pub fn create_state(allocator: std.mem.Allocator) !GBState {
    const mem = try allocator.alloc(u8, 256 * 256);
    errdefer allocator.free(mem);

    return GBState{
        .cpu = CPUState{
            .b = 0x00,
            .c = 0x13,
            .d = 0x00,
            .e = 0xD8,
            .h = 0x01,
            .l = 0x4D,
            .a = 0x01,
            .f = .{
                ._unused0 = 0,
                ._unused1 = 0,
                ._unused2 = 0,
                ._unused3 = 0,
                .carry = 1,
                .half_carry = 1,
                .n_add_sub = 0,
                .zero = 1,
            },
            .sp = 0xFFFE,
            .pc = 0x0100,
        },
        .mem = mem,
        .running = true,
    };
}

pub fn destroy_state(allocator: std.mem.Allocator, gb: *GBState) void {
    allocator.free(gb.mem);
}
