const std = @import("std");
const cpu = @import("cpu.zig");

pub const ScreenWidth = 160;
pub const ScreenHeight = 144;
// FIXME Pixel is the same as a dot or not?
pub const PixelsPerByte = 4;
// pub const ScreenSizeBytes = (ScreenWidth * ScreenHeight) / PixelsPerByte; // FIXME
pub const ScreenSizeBytes = ScreenWidth * ScreenHeight; // FIXME

pub const TileMapExtent = 256;

pub const VRAMBeginOffset = 0x8000;
pub const VRAMEndOffset = 0xA000;
pub const VRAMBytes = VRAMEndOffset - VRAMBeginOffset;

const OAMDurationCycles = 20; // FIXME add PPU name
const DrawMinDurationCycles = 43;
const HBlankMaxDurationCycles = 51;
const ScanLineDurationCycles = OAMDurationCycles + DrawMinDurationCycles + HBlankMaxDurationCycles;
const ScanLineCount = ScreenHeight + 10;

comptime {
    std.debug.assert(ScanLineDurationCycles == 114);
    std.debug.assert(ScanLineCount == 154);
}

pub const LCD_MMIO = packed struct {
    LCDC: packed struct { //= 0x40, // LCD Control (R/W)
        enable_bg_and_window: bool, // BG & Window enable / priority [Different meaning in CGB Mode]: 0 = Off; 1 = On
        obj_enable: bool, // OBJ enable: 0 = Off; 1 = On
        obj_size_mode: enum(u1) { // OBJ size: 0 = 8×8; 1 = 8×16
            Sprite8x8,
            Sprite8x16,
        },
        bg_tile_map_area: u1, // BG tile map area: 0 = 9800–9BFF; 1 = 9C00–9FFF
        bg_and_window_tile_data_area: u1, // BG & Window tile data area: 0 = 8800–97FF; 1 = 8000–8FFF
        enable_window: bool, // Window enable: 0 = Off; 1 = On
        window_tile_map_area: u1, // Window tile map area: 0 = 9800–9BFF; 1 = 9C00–9FFF
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

const Sprite = packed struct {
    position_x: u8,
    position_y: u8,
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
    std.debug.assert(@sizeOf(LCD_MMIO) == 16);
    std.debug.assert(@sizeOf(Palette) == 1);
    std.debug.assert(@sizeOf(Sprite) == 4);
    std.debug.assert(@sizeOf(TileMapPixelOffset) == 2);
}

fn get_current_src_dot_offset(io_lcd: LCD_MMIO) u16 {
    return io_lcd.WY; // FIXME
}

// NOTE: Lets us do index math without messing with bit ops directly
const TileMapPixelOffset = packed struct {
    tile_pixel_x: u3,
    tile_x: u5,
    tile_pixel_y: u3,
    tile_y: u5,
};

fn read_tile_pixel(tile_data: []u8, x: u3, y: u3) u2 {
    std.debug.assert(tile_data.len == 16); // FIXME use [16]u8 if possible

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

pub fn step_pixel_processing_unit(gb: *cpu.GBState, cycle_count: u8) void {
    const io_lcd = &gb.mmio.lcd;
    var cycles_remaining = cycle_count;

    // FIXME Handle io_lcd.LCDC.enable_lcd_and_ppu correctly

    while (cycles_remaining > 0) {
        // Update PPU Mode and get current interrupt line state
        var interrupt_line = false;

        if (io_lcd.LY < ScreenHeight) {
            if (gb.ppu_h_cycles < OAMDurationCycles) {
                interrupt_line = interrupt_line or io_lcd.STAT.enable_scan_oam_interrupt;
                io_lcd.STAT.ppu_mode = .ScanOAM;
            } else if (gb.ppu_h_cycles < OAMDurationCycles + DrawMinDurationCycles) {
                // There's no interrupt for this mode
                io_lcd.STAT.ppu_mode = .Drawing;
            } else {
                interrupt_line = interrupt_line or io_lcd.STAT.enable_hblank_interrupt;
                io_lcd.STAT.ppu_mode = .HBlank;
            }
        } else {
            interrupt_line = interrupt_line or io_lcd.STAT.enable_vblank_interrupt;
            io_lcd.STAT.ppu_mode = .VBlank;
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
                const x: u16 = gb.ppu_h_cycles - OAMDurationCycles;
                const y: u16 = io_lcd.LY;

                // FIXME properly clock this
                pixel_processing_unit_draw(gb, x * 4 + 0, y);
                pixel_processing_unit_draw(gb, x * 4 + 1, y);
                pixel_processing_unit_draw(gb, x * 4 + 2, y);
                pixel_processing_unit_draw(gb, x * 4 + 3, y);
            },
        }

        // Update variables for the next iteration
        cycles_remaining -= 4; // FIXME
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

fn pixel_processing_unit_draw(gb: *cpu.GBState, screen_x: u16, screen_y: u16) void {
    if (screen_x >= 160) { // FIXME properly clock this
        return;
    }
    const io_lcd = &gb.mmio.lcd;

    // Tile Data
    const vram_tile_data0 = gb.vram[0x0000..0x1000];
    const vram_tile_data1 = gb.vram[0x0800..0x1800];
    const tile_data_sprites = vram_tile_data0;
    const tile_data_bg = if (io_lcd.LCDC.bg_and_window_tile_data_area == 1) vram_tile_data1 else vram_tile_data0;

    _ = tile_data_sprites;

    // Tile Map
    const vram_tile_map0 = gb.vram[0x1800..0x1C00];
    const vram_tile_map1 = gb.vram[0x1C00..0x2000];
    const tile_map_bg = if (io_lcd.LCDC.bg_tile_map_area == 1) vram_tile_map1 else vram_tile_map0;
    const tile_map_win = if (io_lcd.LCDC.window_tile_map_area == 1) vram_tile_map1 else vram_tile_map0;

    _ = tile_map_win;

    std.debug.assert(screen_x < ScreenWidth);
    std.debug.assert(screen_y < ScreenHeight);

    if (io_lcd.LCDC.enable_bg_and_window) {
        const tile_map_x = (screen_x + io_lcd.SCX) % TileMapExtent;
        const tile_map_y = (screen_y + io_lcd.SCY) % TileMapExtent;

        const pixel_offset: TileMapPixelOffset = @bitCast(tile_map_y * TileMapExtent + tile_map_x);

        if (io_lcd.LCDC.enable_window) {}

        const bg_tile_map_entry: u16 = tile_map_bg[@as(u16, pixel_offset.tile_y) * 32 + pixel_offset.tile_x];

        // FIXME find out why we have trash in the tile map
        if (bg_tile_map_entry < 128) {
            std.debug.assert(bg_tile_map_entry < 128); // FIXME

            const bg_tile = tile_data_bg[bg_tile_map_entry * 16 .. bg_tile_map_entry * 16 + 16];

            const bg_color_id = read_tile_pixel(bg_tile, pixel_offset.tile_pixel_x, pixel_offset.tile_pixel_y);
            const pixel_color = eval_palette(io_lcd.BGP, bg_color_id);

            const screen_dst_offset = screen_y * ScreenWidth + screen_x;
            gb.screen_output[screen_dst_offset] = pixel_color;
        }
    }

    if (io_lcd.LCDC.obj_enable) {}
}
