const std = @import("std");
const cpu = @import("cpu.zig");
const assert = std.debug.assert;

const tracy = @import("../tracy.zig");

pub const ScreenWidth = 160;
pub const ScreenHeight = 144;
// FIXME Pixel is the same as a dot or not?
pub const PixelsPerByte = 4;
// pub const ScreenSizeBytes = (ScreenWidth * ScreenHeight) / PixelsPerByte; // FIXME
pub const ScreenSizeBytes = ScreenWidth * ScreenHeight; // FIXME

pub const OAMSpriteCount = 40;
pub const OAMMemoryByteCount = 160;
pub const LineMaxActiveSprites = 10;

pub const VRAMBeginOffset = 0x8000;
pub const VRAMEndOffset = 0xA000;
pub const VRAMBytes = VRAMEndOffset - VRAMBeginOffset;

const OAMDurationCycles = 80; // FIXME add PPU name
const DrawMinDurationCycles = 172;
const HBlankMaxDurationCycles = 204;
const ScanLineDurationCycles = OAMDurationCycles + DrawMinDurationCycles + HBlankMaxDurationCycles;
const ScanLineCount = ScreenHeight + 10;

const u8_2 = @Vector(2, u8);

comptime {
    assert(ScanLineDurationCycles == 456);
    assert(ScanLineCount == 154);
    assert(@sizeOf(Sprite) * OAMSpriteCount == OAMMemoryByteCount);
}

pub const LCD_MMIO = packed struct {
    LCDC: packed struct { //= 0x40, // LCD Control (R/W)
        enable_bg_and_window: bool, // BG & Window enable / priority [Different meaning in CGB Mode]: 0 = Off; 1 = On
        obj_enable: bool, // OBJ enable: 0 = Off; 1 = On
        obj_size_mode: enum(u1) { // OBJ size: 0 = 8×8; 1 = 8×16
            Sprite8x8,
            Sprite8x16,
        },
        bg_tile_map_area: enum(u1) { // BG tile map area
            Mode9800to9BFF,
            Mode9C00to9FFF,
        },
        bg_and_window_tile_data_area: enum(u1) { // BG & Window tile data area
            ModeSigned8800to97FF,
            ModeUnsigned8000to8FFF,
        },
        enable_window: bool, // Window enable: 0 = Off; 1 = On
        window_tile_map_area: enum(u1) { // Window tile map area
            Mode9800to9BFF,
            Mode9C00to9FFF,
        },
        enable_lcd_and_ppu: bool, // LCD & PPU enable: 0 = Off; 1 = On
    },
    STAT: packed struct { //= 0x41, // LCDC Status (R/W)
        ppu_mode: enum(u2) { // PPU mode (Read-only): Indicates the PPU’s current status.
            HBlank, // mode 0
            VBlank, // mode 1
            ScanOAM, // mode 2
            Drawing, // mode 3
        },
        lyc_equal_ly: bool, // LYC == LY (Read-only): Set when LY contains the same value as LYC; it is constantly updated.
        enable_hblank_interrupt: bool, // Mode 0 int select (Read/Write): If set, selects the Mode 0 condition for the STAT interrupt.
        enable_vblank_interrupt: bool, // Mode 1 int select (Read/Write): If set, selects the Mode 1 condition for the STAT interrupt.
        enable_scan_oam_interrupt: bool, // Mode 2 int select (Read/Write): If set, selects the Mode 2 condition for the STAT interrupt.
        enable_lyc_interrupt: bool, // LYC int select (Read/Write): If set, selects the LYC == LY condition for the STAT interrupt.
        _unused: u1,
    },
    SCY: u8, //= 0x42, // Scroll Y (R/W)
    SCX: u8, //= 0x43, // Scroll X (R/W)
    LY: u8, //= 0x44, // LCDC Y-Coordinate (R)
    LYC: u8, //= 0x45, // LY Compare (R/W)
    DMA: u8, //= 0x46, // DMA Transfer and Start Address (W)
    BGP: Palette, //= 0x47, // BG Palette Data (R/W) - Non CGB Mode Only
    OBP0: Palette, //= 0x48, // Object Palette 0 Data (R/W) - Non CGB Mode Only
    OBP1: Palette, //= 0x49, // Object Palette 1 Data (R/W) - Non CGB Mode Only
    WY: u8, //= 0x4A, // Window Y Position (R/W)
    WX: u8, //= 0x4B, // Window X Position minus 7 (R/W)
    // Controls DMG mode and PGB mode
    KEY0: u8, //= 0x4C,
    KEY1: u8, //= 0x4D, // CGB Mode Only - Prepare Speed Switch
    _unused_4E: u8,
    VBK: u8, //= 0x4F, // CGB Mode Only - VRAM Bank
};

const Palette = packed struct {
    id_0_color: u2,
    id_1_color: u2,
    id_2_color: u2,
    id_3_color: u2,
};

pub const Sprite = packed struct {
    position_y: u8,
    position_x: u8,
    tile_index: u8,
    attributes: packed struct {
        cgb_palette: u3, // CGB palette [CGB Mode Only]: Which of OBP0–7 to use
        bank: u1, // Bank [CGB Mode Only]: 0 = Fetch tile from VRAM bank 0, 1 = Fetch tile from VRAM bank 1
        dmg_palette: u1, // DMG palette [Non CGB Mode only]: 0 = OBP0, 1 = OBP1
        flip_x: u1, // X flip: 0 = Normal, 1 = Entire OBJ is horizontally mirrored
        flip_y: u1, // Y flip: 0 = Normal, 1 = Entire OBJ is vertically mirrored
        priority: u1, // Priority: 0 = No, 1 = BG and Window colors 1–3 are drawn over this OBJ
    },
};

comptime {
    assert(@sizeOf(LCD_MMIO) == 16);
    assert(@sizeOf(Palette) == 1);
    assert(@sizeOf(Sprite) == 4);
    assert(@sizeOf(PositionTileLocal) == 2);
}

fn get_current_src_dot_offset(io_lcd: LCD_MMIO) u16 {
    return io_lcd.WY; // FIXME
}

// NOTE: Lets us do index math without messing with bit ops directly
const PositionInTileMap = packed struct {
    x: u8,
    y: u8,
};

const PositionTileLocal = packed struct {
    pixel_x: u3,
    tile_x: u5,
    pixel_y: u3,
    tile_y: u5,
};

fn read_tile_pixel(tile_data: []u8, x: u3, y: u3) u2 {
    assert(tile_data.len == 16); // FIXME use [16]u8 if possible

    const lsb: u1 = @intCast((tile_data[@as(u4, 2) * y] >> (7 - x)) & 0b1);
    const msb: u1 = @intCast((tile_data[@as(u4, 2) * y + 1] >> (7 - x)) & 0b1);

    return @as(u2, msb) << 1 | lsb;
}

fn eval_palette(palette: Palette, color_id: u2) u2 {
    return switch (color_id) {
        0 => palette.id_0_color,
        1 => palette.id_1_color,
        2 => palette.id_2_color,
        3 => palette.id_3_color,
    };
}

// FIXME Maybe this generates better code?
fn eval_palette_raw(palette: u8, color_id: u2) u2 {
    return @intCast((palette >> (color_id * 2)) & 0b11);
}

pub fn step_ppu(gb: *cpu.GBState, cycle_count: u8) void {
    const scope = tracy.trace(@src());
    defer scope.end();

    const io_lcd = &gb.mmio.lcd;
    var cycles_remaining = cycle_count;

    while (cycles_remaining > 0) {
        // Update PPU Mode and get current interrupt line state
        var interrupt_line = false;
        const previous_ppu_mode = io_lcd.STAT.ppu_mode;

        if (io_lcd.LY < ScreenHeight) {
            if (gb.ppu_h_cycles < OAMDurationCycles) {
                interrupt_line = interrupt_line or io_lcd.STAT.enable_scan_oam_interrupt;
                io_lcd.STAT.ppu_mode = .ScanOAM;
            } else if (gb.ppu_h_cycles < OAMDurationCycles + DrawMinDurationCycles) {
                // There's no interrupt line change for this mode
                if (previous_ppu_mode != .Drawing) {
                    io_lcd.STAT.ppu_mode = .Drawing;
                    compute_active_sprites_for_line(gb, io_lcd.LY); // Computed during OAM on a real DMG
                }
            } else {
                interrupt_line = interrupt_line or io_lcd.STAT.enable_hblank_interrupt;
                io_lcd.STAT.ppu_mode = .HBlank;
            }
        } else {
            interrupt_line = interrupt_line or io_lcd.STAT.enable_vblank_interrupt;

            if (previous_ppu_mode != .VBlank) {
                io_lcd.STAT.ppu_mode = .VBlank;
                gb.mmio.IF.requested_interrupts_mask |= cpu.InterruptMaskVBlank;
            }
        }

        io_lcd.STAT.lyc_equal_ly = io_lcd.LYC == io_lcd.LY;
        interrupt_line = interrupt_line or (io_lcd.STAT.enable_lyc_interrupt and io_lcd.STAT.lyc_equal_ly);

        // Only request an interrupt when the interrupt line goes up
        if (!gb.last_stat_interrupt_line and interrupt_line) {
            gb.mmio.IF.requested_interrupts_mask |= cpu.InterruptMaskLCD;
        }

        gb.last_stat_interrupt_line = interrupt_line;

        // Execute current mode
        switch (io_lcd.STAT.ppu_mode) {
            .HBlank, .VBlank, .ScanOAM => {},
            .Drawing => {
                const x = gb.ppu_h_cycles - OAMDurationCycles;
                const y = io_lcd.LY;

                if (x < ScreenWidth) { // FIXME OBJs make relationship between cycles and horizontal position variable
                    draw_dot(gb, @intCast(x), y);
                }
            },
        }

        // Update variables for the next iteration
        cycles_remaining -= 1; // FIXME
        gb.ppu_h_cycles += 1;

        if (gb.ppu_h_cycles == ScanLineDurationCycles) {
            gb.ppu_h_cycles = 0;

            io_lcd.LY += 1;

            if (io_lcd.LY == ScanLineCount) {
                io_lcd.LY = 0;

                gb.has_frame_to_consume = true;
            }
        }
    }
}

pub fn reset_ppu(gb: *cpu.GBState) void {
    // FIXME not sure this is strictly needed
    gb.mmio.lcd.LY = 0;
    gb.ppu_h_cycles = 0;
}

fn position_tile_local_from_position_in_tile_map(pixel_offset: PositionInTileMap) PositionTileLocal {
    return @bitCast(pixel_offset);
}

fn tile_map_index_flat_from_tile_local_position(position_tile_local: PositionTileLocal) u10 {
    // Avoid manually writing bit manipulations or index math!
    const FlatIndexAdapater = packed struct {
        tile_x: u5,
        tile_y: u5,
    };

    return @bitCast(FlatIndexAdapater{
        .tile_x = position_tile_local.tile_x,
        .tile_y = position_tile_local.tile_y,
    });
}

fn draw_dot(gb: *cpu.GBState, screen_x: u8, screen_y: u8) void {
    assert(screen_x < ScreenWidth);
    assert(screen_y < ScreenHeight);

    const io_lcd = &gb.mmio.lcd;

    // Tile Data
    const vram_tile_data0 = gb.vram[0x0000..0x1000];
    const vram_tile_data1 = gb.vram[0x0800..0x1800];
    const tile_data_bg = if (io_lcd.LCDC.bg_and_window_tile_data_area == .ModeUnsigned8000to8FFF) vram_tile_data0 else vram_tile_data1;
    const tile_data_sprites = vram_tile_data0;

    // Tile Map
    const vram_tile_map0 = gb.vram[0x1800..0x1C00];
    const vram_tile_map1 = gb.vram[0x1C00..0x2000];
    const tile_map_bg = if (io_lcd.LCDC.bg_tile_map_area == .Mode9800to9BFF) vram_tile_map0 else vram_tile_map1;
    const tile_map_win = if (io_lcd.LCDC.window_tile_map_area == .Mode9800to9BFF) vram_tile_map0 else vram_tile_map1;

    _ = tile_map_win;

    // FIXME What's the default pixel value?
    var pixel_color: u2 = 0;

    if (io_lcd.LCDC.enable_bg_and_window) {
        const position_in_tile_map = PositionInTileMap{
            .x = screen_x +% io_lcd.SCX,
            .y = screen_y +% io_lcd.SCY,
        };

        const position_tile_local = position_tile_local_from_position_in_tile_map(position_in_tile_map);
        const tile_map_index_flat = tile_map_index_flat_from_tile_local_position(position_tile_local);

        var bg_tile_data_index = tile_map_bg[tile_map_index_flat];

        // FIXME make this more better
        if (io_lcd.LCDC.bg_and_window_tile_data_area == .ModeSigned8800to97FF) {
            if (bg_tile_data_index < 128) {
                bg_tile_data_index += 128;
            } else {
                bg_tile_data_index -= 128;
            }
        }

        const bg_tile_data = get_tile_data(tile_data_bg, bg_tile_data_index);

        const bg_color_id = read_tile_pixel(bg_tile_data, position_tile_local.pixel_x, position_tile_local.pixel_y);
        pixel_color = eval_palette(io_lcd.BGP, bg_color_id);

        if (io_lcd.LCDC.enable_window) {} // FIXME
    }

    if (io_lcd.LCDC.obj_enable) {
        // NOTE: sprites position_x and screen_x start at an offset of 16 pixels
        const sprites_extent = get_sprites_extent(gb);

        for (gb.active_sprite_indices[0..gb.active_sprite_count]) |sprite_index| {
            const sprite = gb.oam_sprites[sprite_index];
            const pixel_coord_sprite = screen_coords_to_sprite_coords(sprite, .{ @intCast(screen_x), @intCast(screen_y) });

            const is_sprite_visible = all(pixel_coord_sprite >= u8_2{ 0, 0 }) and all(pixel_coord_sprite < sprites_extent);

            if (is_sprite_visible) {
                const tile_data = get_tile_data(tile_data_sprites, sprite.tile_index);

                // FIXME This is completely wrong but works for very simple cases
                const color_id = read_tile_pixel(tile_data, @intCast(pixel_coord_sprite[0]), @intCast(pixel_coord_sprite[1] % 8));
                pixel_color = eval_palette(io_lcd.BGP, color_id);
            }
        }
    }

    const screen_dst_offset = @as(u16, screen_y) * ScreenWidth + screen_x;
    gb.screen_output[screen_dst_offset] = pixel_color;
}

fn get_tile_data(tile_data: []u8, tile_index: u12) []u8 {
    return tile_data[tile_index * 16 .. tile_index * 16 + 16];
}

// FIMXE
pub fn all(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.Vector.child == bool);
    assert(type_info.Vector.len > 1);

    return @reduce(.And, vector);
}

fn screen_coords_to_sprite_coords(sprite: Sprite, screen_coord: u8_2) u8_2 {
    // NOTE: wrapping is not a problem here since we only care about the case when a pixel is inside a sprite.
    return .{
        screen_coord[0] + 8 -% sprite.position_x,
        screen_coord[1] + 16 -% sprite.position_y,
    };
}

fn compute_active_sprites_for_line(gb: *cpu.GBState, line_index: u32) void {
    // NOTE: sprites position_y and LY start at an offset of 16 pixels
    const sprites_extent = get_sprites_extent(gb);
    const sprite_y_start = line_index + 16 - sprites_extent[1];
    const sprite_y_stop = line_index + 16;

    var current_visible_sprite_index: u8 = 0;

    for (gb.oam_sprites, 0..) |sprite, sprite_index| {
        const is_sprite_visible = sprite.position_y > sprite_y_start and sprite.position_y <= sprite_y_stop;

        if (is_sprite_visible) {
            gb.active_sprite_indices[current_visible_sprite_index] = @intCast(sprite_index);
            current_visible_sprite_index += 1;
        }

        if (current_visible_sprite_index == LineMaxActiveSprites) {
            break;
        }
    }

    gb.active_sprite_count = current_visible_sprite_index;

    std.sort.pdq(u8, gb.active_sprite_indices[0..gb.active_sprite_count], gb.oam_sprites, sprite_less_than);
}

// FIXME
fn sprite_less_than(oam_sprites: [OAMSpriteCount]Sprite, a_index: u8, b_index: u8) bool {
    const a = oam_sprites[a_index];
    const b = oam_sprites[b_index];

    return a.position_x < b.position_x;
}

fn get_sprites_extent(gb: *cpu.GBState) u8_2 {
    return switch (gb.mmio.lcd.LCDC.obj_size_mode) {
        .Sprite8x8 => .{ 8, 8 },
        .Sprite8x16 => .{ 8, 16 },
    };
}
