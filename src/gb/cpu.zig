const std = @import("std");

pub const GBState = struct {
    registers: Registers,
    memory: []u8,
};

const native_endian = @import("builtin").target.cpu.arch.endian();

// Register layout varies depending on the host, since we want to make use of
// bit-casting r8 registers into r16 to save manual conversions.
pub const Registers = switch (native_endian) {
    .little => Registers_LittleEndian,
    .big => Registers_BigEndian,
};

const Registers_LittleEndian = packed struct {
    c: u8,
    b: u8,
    e: u8,
    d: u8,
    l: u8,
    h: u8,
    flags: FlagRegister,
    a: u8,
    sp: u16, // Stack Pointer
    pc: u16, // Program Counter
};

const Registers_BigEndian = packed struct {
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    a: u8,
    flags: FlagRegister,
    sp: u16, // Stack Pointer
    pc: u16, // Program Counter
};

// Anytime we need the u16 view on register, we can safely bitcast since the backing has the proper memory layout
pub const Registers_R16 = packed struct {
    bc: u16,
    de: u16,
    hl: u16,
    af: u16,
    sp: u16, // Stack Pointer
    pc: u16, // Program Counter
};

pub const FlagRegister = packed struct {
    _unused: u4,
    carry: u1,
    half_carry: u1,
    substract: u1,
    zero: u1,
};

comptime {
    std.debug.assert(@sizeOf(FlagRegister) == 1);
    std.debug.assert(@offsetOf(Registers_LittleEndian, "sp") == 8);
    std.debug.assert(@offsetOf(Registers_BigEndian, "sp") == 8);
    std.debug.assert(@offsetOf(Registers_R16, "sp") == 8);
}

pub fn create_state(allocator: std.mem.Allocator, cart_rom_bytes: []const u8) !GBState {
    const memory = try allocator.alloc(u8, 256 * 256); // FIXME
    errdefer allocator.free(memory);

    // FIXME
    std.mem.copyForwards(u8, memory, cart_rom_bytes);

    // See http://www.codeslinger.co.uk/pages/projects/gameboy/hardware.html
    memory[0xFF05] = 0x00;
    memory[0xFF06] = 0x00;
    memory[0xFF07] = 0x00;
    memory[0xFF10] = 0x80;
    memory[0xFF11] = 0xBF;
    memory[0xFF12] = 0xF3;
    memory[0xFF14] = 0xBF;
    memory[0xFF16] = 0x3F;
    memory[0xFF17] = 0x00;
    memory[0xFF19] = 0xBF;
    memory[0xFF1A] = 0x7F;
    memory[0xFF1B] = 0xFF;
    memory[0xFF1C] = 0x9F;
    memory[0xFF1E] = 0xBF;
    memory[0xFF20] = 0xFF;
    memory[0xFF21] = 0x00;
    memory[0xFF22] = 0x00;
    memory[0xFF23] = 0xBF;
    memory[0xFF24] = 0x77;
    memory[0xFF25] = 0xF3;
    memory[0xFF26] = 0xF1;
    memory[0xFF40] = 0x91;
    memory[0xFF42] = 0x00;
    memory[0xFF43] = 0x00;
    memory[0xFF45] = 0x00;
    memory[0xFF47] = 0xFC;
    memory[0xFF48] = 0xFF;
    memory[0xFF49] = 0xFF;
    memory[0xFF4A] = 0x00;
    memory[0xFF4B] = 0x00;
    memory[0xFFFF] = 0x00;

    return GBState{
        .registers = @bitCast(Registers_R16{
            .bc = 0x0013,
            .de = 0x00D8,
            .hl = 0x014D,
            .af = 0x01B0,
            .sp = 0xFFFE,
            .pc = 0x0100,
        }),
        .memory = memory,
    };
}

pub fn destroy_state(allocator: std.mem.Allocator, gb: *GBState) void {
    allocator.free(gb.memory);
}
