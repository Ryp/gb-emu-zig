const std = @import("std");
const cpu = @import("cpu.zig");

pub const Keys = packed struct {
    dpad: packed union {
        pressed: packed struct {
            right: bool,
            left: bool,
            up: bool,
            down: bool,
        },
        pressed_mask: u4,
    },
    buttons: packed union {
        pressed: packed struct {
            a: bool,
            b: bool,
            select: bool,
            start: bool,
        },
        pressed_mask: u4,
    },
};

// FIXME enable interrupt handling
// FIXME don't allow pressing opposite directions at the same time (games break)
pub fn update_state(gb: *cpu.GBState) void {
    gb.mmio.JOYP.released_state = switch (gb.mmio.JOYP.input_selector) {
        .both => ~(gb.keys.buttons.pressed_mask | gb.keys.dpad.pressed_mask),
        .buttons => ~gb.keys.buttons.pressed_mask,
        .dpad => ~gb.keys.dpad.pressed_mask,
        .none => 0xf,
    };
}
