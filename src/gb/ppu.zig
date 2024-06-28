const std = @import("std");
const cpu = @import("cpu.zig");
const assert = std.debug.assert;

const tracy = @import("../tracy.zig");

pub const PPUState = struct {
    vram: []u8, // Does not own memory
    vram_tile_data0: []u8,
    vram_tile_data1: []u8,
    vram_tile_map0: []u8,
    vram_tile_map1: []u8,
    oam_sprites: [OAMSpriteCount]Sprite = undefined,
    h_cycles: u16 = 0, // NOTE: Normally independent of the CPU cycles but on DMG they match 1:1
    internal_wy: u8 = 0,
    last_stat_interrupt_line: bool = false, // Last state of the STAT interrupt line
    has_frame_to_consume: bool = false, // Tell the frontend to consume screen_output
    active_sprite_indices: [LineMaxActiveSprites]u8 = undefined,
    active_sprite_count: u8 = 0,
};

pub fn create_ppu_state(vram: []u8) PPUState {
    return .{
        .vram = vram,
        .vram_tile_data0 = vram[0x0000..0x1000],
        .vram_tile_data1 = vram[0x0800..0x1800],
        .vram_tile_map0 = vram[0x1800..0x1C00],
        .vram_tile_map1 = vram[0x1C00..0x2000],
    };
}

pub fn reset_ppu(ppu: *PPUState, mmio: *MMIO) void {
    ppu.* = create_ppu_state(ppu.vram);

    mmio.LY = 0;
}

pub fn step_ppu(ppu: *PPUState, mmio: *MMIO, mmio_IF: *cpu.MMIO_IF, screen_output: []u8, t_cycle_count: u8) void {
    const scope = tracy.trace(@src());
    defer scope.end();

    var t_cycles_remaining = t_cycle_count;

    while (t_cycles_remaining > 0) {
        // Update PPU Mode and get current interrupt line state
        var interrupt_line = false;
        const previous_ppu_mode = mmio.STAT.ppu_mode;

        if (mmio.LY < ScreenHeight) {
            if (ppu.h_cycles < OAMDurationCycles) {
                interrupt_line = interrupt_line or mmio.STAT.enable_scan_oam_interrupt;
                mmio.STAT.ppu_mode = .ScanOAM;
            } else if (ppu.h_cycles < OAMDurationCycles + DrawMinDurationCycles) {
                // There's no interrupt line change for this mode
                if (previous_ppu_mode != .Drawing) {
                    mmio.STAT.ppu_mode = .Drawing;
                    compute_active_sprites_for_line(ppu, mmio); // Computed during OAM on a real DMG
                }
            } else {
                interrupt_line = interrupt_line or mmio.STAT.enable_hblank_interrupt;
                mmio.STAT.ppu_mode = .HBlank;
            }
        } else {
            interrupt_line = interrupt_line or mmio.STAT.enable_vblank_interrupt;

            if (previous_ppu_mode != .VBlank) {
                mmio.STAT.ppu_mode = .VBlank;
                mmio_IF.requested_interrupt.flag.vblank = true;
            }
        }

        mmio.STAT.lyc_equal_ly = mmio.LYC == mmio.LY;
        interrupt_line = interrupt_line or (mmio.STAT.enable_lyc_interrupt and mmio.STAT.lyc_equal_ly);

        // Only request an interrupt when the interrupt line goes up
        if (!ppu.last_stat_interrupt_line and interrupt_line) {
            mmio_IF.requested_interrupt.flag.lcd = true;
        }

        ppu.last_stat_interrupt_line = interrupt_line;

        // Execute current mode
        switch (mmio.STAT.ppu_mode) {
            .HBlank, .VBlank, .ScanOAM => {},
            .Drawing => {
                const x = ppu.h_cycles - OAMDurationCycles;
                const y = mmio.LY;

                if (x < ScreenWidth) { // FIXME OBJs make relationship between cycles and horizontal position variable
                    const pixel_color = draw_dot(ppu, mmio, @intCast(x), y);

                    const screen_dst_offset = @as(u16, y) * ScreenWidth + x;
                    screen_output[screen_dst_offset] = pixel_color;
                }
            },
        }

        // Update variables for the next iteration
        t_cycles_remaining -= 1; // FIXME
        ppu.h_cycles += 1;

        if (ppu.h_cycles == ScanLineDurationCycles) {
            ppu.h_cycles = 0;

            // FIXME
            if (mmio.LCDC.enable_bg_and_window and mmio.LCDC.enable_window and mmio.LY >= mmio.WY and mmio.WX <= 166) {
                ppu.internal_wy += 1;
            }

            mmio.LY += 1;

            if (mmio.LY == ScanLineCount) {
                mmio.LY = 0;
                ppu.internal_wy = 0;

                ppu.has_frame_to_consume = true;
            }
        }
    }
}

pub const MMIO_OffsetABegin = LCDC;
pub const MMIO_OffsetAEndInclusive = LYC;
pub const MMIO_OffsetBBegin = BGP;
pub const MMIO_OffsetBEndInclusive = VBK;

pub fn store_mmio_u8(ppu: *PPUState, mmio: *MMIO, mmio_bytes: []u8, offset: u8, value: u8) void {
    switch (offset) {
        DMA => unreachable, // Doesn't belong to the PPU
        LCDC => {
            const lcd_was_on = mmio.LCDC.enable_lcd_and_ppu;
            mmio_bytes[offset] = value;
            const lcd_is_on = mmio.LCDC.enable_lcd_and_ppu;

            // Only turn off during VBlank!
            if (lcd_was_on and !lcd_is_on) {
                assert(mmio.STAT.ppu_mode == .VBlank);
            } else if (!lcd_was_on and lcd_is_on) {
                reset_ppu(ppu, mmio);
            }
        },
        else => mmio_bytes[offset] = value,
    }
}

pub fn load_mmio_u8(ppu: *const PPUState, mmio: *const MMIO, mmio_bytes: []u8, offset: u8) u8 {
    // FIXME Needed later maybe
    _ = ppu;
    _ = mmio;

    switch (offset) {
        DMA => unreachable, // Doesn't belong to the PPU
        else => return mmio_bytes[offset],
    }
}

fn draw_dot(ppu: *const PPUState, mmio: *const MMIO, screen_x: u8, screen_y: u8) u2 {
    assert(screen_x < ScreenWidth);
    assert(screen_y < ScreenHeight);

    // Tile Data
    const tile_data_bg = if (mmio.LCDC.bg_and_window_tile_data_area == .ModeUnsigned8000to8FFF) ppu.vram_tile_data0 else ppu.vram_tile_data1;
    const tile_data_sprites = ppu.vram_tile_data0;

    // Tile Map
    const tile_map_bg = if (mmio.LCDC.bg_tile_map_area == .Mode9800to9BFF) ppu.vram_tile_map0 else ppu.vram_tile_map1;
    const tile_map_win = if (mmio.LCDC.window_tile_map_area == .Mode9800to9BFF) ppu.vram_tile_map0 else ppu.vram_tile_map1;

    // FIXME What's the default pixel value?
    var pixel_color: u2 = 0;

    if (mmio.LCDC.enable_bg_and_window) {
        const window_covers_bg = mmio.LCDC.enable_window and all(u8_2{ screen_x + 7, screen_y } >= u8_2{ mmio.WX, mmio.WY });

        const tile_map = if (window_covers_bg) tile_map_win else tile_map_bg;
        const position_tile_map = if (window_covers_bg) PositionInTileMap{
            .x = screen_x + 7 - mmio.WX,
            .y = ppu.internal_wy,
        } else PositionInTileMap{
            .x = screen_x +% mmio.SCX,
            .y = screen_y +% mmio.SCY,
        };

        const position_tile_local = position_tile_local_from_position_in_tile_map(position_tile_map);
        const tile_map_index_flat = tile_map_index_flat_from_tile_local_position(position_tile_local);

        var tile_data_index = tile_map[tile_map_index_flat];

        // FIXME make this more better
        if (mmio.LCDC.bg_and_window_tile_data_area == .ModeSigned8800to97FF) {
            if (tile_data_index < 128) {
                tile_data_index += 128;
            } else {
                tile_data_index -= 128;
            }
        }

        const tile_data = get_tile_data(tile_data_bg, tile_data_index);

        const color_id = read_tile_pixel(tile_data, position_tile_local.pixel_x, position_tile_local.pixel_y);
        pixel_color = eval_palette(mmio.BGP, color_id);
    }

    if (mmio.LCDC.obj_enable) {
        // NOTE: sprites position_x and screen_x start at an offset of 16 pixels
        const sprites_extent = get_sprites_extent(mmio);

        // NOTE: Sprites are assumed to be sorted in order of decreasing priority
        for (ppu.active_sprite_indices[0..ppu.active_sprite_count]) |sprite_index| {
            const sprite = ppu.oam_sprites[sprite_index];
            const pixel_coord_sprite = screen_coords_to_sprite_coords(sprite, .{ @intCast(screen_x), @intCast(screen_y) });

            const is_sprite_visible = all(pixel_coord_sprite >= u8_2{ 0, 0 }) and all(pixel_coord_sprite < sprites_extent);

            if (is_sprite_visible) {
                const sprite_tile_info = get_sprite_tile_info(sprite, sprites_extent, pixel_coord_sprite);
                const tile_data = get_tile_data(tile_data_sprites, sprite_tile_info.tile_index);

                const color_id = read_tile_pixel(tile_data, sprite_tile_info.pixel_x, sprite_tile_info.pixel_y);

                // FIXME This is completely wrong but works for very simple cases
                const palette = if (sprite.attributes.dmg_palette == 0) mmio.OBP0 else mmio.OBP1;
                const sprite_color = eval_palette(palette, color_id);

                if (sprite.attributes.priority == 0) {
                    if (color_id != 0) // Transparent for OBJs
                    {
                        pixel_color = sprite_color;
                        break;
                    }
                } else {
                    if (color_id != 0 and pixel_color == 0) // Transparent for OBJs
                    {
                        pixel_color = sprite_color;
                        break;
                    }
                }
            }
        }
    }

    return pixel_color;
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

fn read_tile_pixel(tile_data: []u8, x: u3, y: u3) u2 {
    assert(tile_data.len == 16); // FIXME use [16]u8 if possible

    const lsb: u1 = @intCast((tile_data[@as(u4, 2) * y] >> (7 - x)) & 0b1);
    const msb: u1 = @intCast((tile_data[@as(u4, 2) * y + 1] >> (7 - x)) & 0b1);

    return @as(u2, msb) << 1 | lsb;
}

fn eval_palette(palette: MMIO_Palette, color_id: u2) u2 {
    return switch (color_id) {
        0 => palette.id_0_color,
        1 => palette.id_1_color,
        2 => palette.id_2_color,
        3 => palette.id_3_color,
    };
}

fn get_tile_data(tile_data: []u8, tile_index: u12) []u8 {
    const index: u32 = tile_index;
    return tile_data[index * 16 .. index * 16 + 16];
}

const SpriteTileInfo = struct {
    pixel_x: u3,
    pixel_y: u3,
    tile_index: u8,
};

fn get_sprite_tile_info(sprite: Sprite, sprites_extent: u8_2, pixel_coord: u8_2) SpriteTileInfo {
    var pixel_x: u3 = @intCast(pixel_coord[0]);
    var pixel_y: u4 = @intCast(pixel_coord[1]);

    if (sprite.attributes.flip_x) {
        pixel_x = @intCast(sprites_extent[0] - 1 - pixel_x);
    }

    if (sprite.attributes.flip_y) {
        pixel_y = @intCast(sprites_extent[1] - 1 - pixel_y);
    }

    var tile_index = sprite.tile_index;

    // Special tile selection when we're using tall sprites
    if (sprites_extent[1] == 16) {
        if (pixel_y < 8) {
            tile_index &= 0xFE;
        } else {
            tile_index |= 0x01;
        }
    }

    return SpriteTileInfo{
        .pixel_x = pixel_x,
        .pixel_y = @truncate(pixel_y),
        .tile_index = tile_index,
    };
}

fn all(vector: anytype) bool {
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

fn compute_active_sprites_for_line(ppu: *PPUState, mmio: *const MMIO) void {
    // NOTE: sprites position_y and LY start at an offset of 16 pixels
    const line_index: u32 = mmio.LY;
    const sprites_extent = get_sprites_extent(mmio);
    const sprite_y_start = line_index + 16 - sprites_extent[1];
    const sprite_y_stop = line_index + 16;

    var current_visible_sprite_index: u8 = 0;

    for (ppu.oam_sprites, 0..) |sprite, sprite_index| {
        const is_sprite_visible = sprite.position_y > sprite_y_start and sprite.position_y <= sprite_y_stop;

        if (is_sprite_visible) {
            ppu.active_sprite_indices[current_visible_sprite_index] = @intCast(sprite_index);
            current_visible_sprite_index += 1;
        }

        if (current_visible_sprite_index == LineMaxActiveSprites) {
            break;
        }
    }

    ppu.active_sprite_count = current_visible_sprite_index;

    std.sort.pdq(u8, ppu.active_sprite_indices[0..ppu.active_sprite_count], ppu.oam_sprites, sprite_less_than);
}

// Sort order to be in decreasing priority
fn sprite_less_than(oam_sprites: [OAMSpriteCount]Sprite, a_index: u8, b_index: u8) bool {
    const a = oam_sprites[a_index];
    const b = oam_sprites[b_index];

    return a.position_x > b.position_x;
}

fn get_sprites_extent(mmio: *const MMIO) u8_2 {
    return switch (mmio.LCDC.obj_size_mode) {
        .Sprite8x8 => .{ 8, 8 },
        .Sprite8x16 => .{ 8, 16 },
    };
}

pub const ScreenWidth = 160;
pub const ScreenHeight = 144;
const PixelsPerByte = 4;
// pub const ScreenSizeBytes = (ScreenWidth * ScreenHeight) / PixelsPerByte; // FIXME
pub const ScreenSizeBytes = ScreenWidth * ScreenHeight; // FIXME

const OAMSpriteCount = 40;
const OAMMemoryByteCount = 160;
const LineMaxActiveSprites = 10;

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

pub const MMIO = packed struct {
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
    BGP: MMIO_Palette, //= 0x47, // BG Palette Data (R/W) - Non CGB Mode Only
    OBP0: MMIO_Palette, //= 0x48, // Object Palette 0 Data (R/W) - Non CGB Mode Only
    OBP1: MMIO_Palette, //= 0x49, // Object Palette 1 Data (R/W) - Non CGB Mode Only
    WY: u8, //= 0x4A, // Window Y Position (R/W)
    WX: u8, //= 0x4B, // Window X Position minus 7 (R/W)
    // Controls DMG mode and PGB mode
    KEY0: u8, //= 0x4C,
    KEY1: u8, //= 0x4D, // CGB Mode Only - Prepare Speed Switch
    _unused_4E: u8,
    VBK: u8, //= 0x4F, // CGB Mode Only - VRAM Bank
};

const MMIO_Palette = packed struct {
    id_0_color: u2,
    id_1_color: u2,
    id_2_color: u2,
    id_3_color: u2,
};

const Sprite = packed struct {
    position_y: u8,
    position_x: u8,
    tile_index: u8,
    attributes: packed struct {
        cgb_palette: u3, // CGB palette [CGB Mode Only]: Which of OBP0–7 to use
        bank: u1, // Bank [CGB Mode Only]: 0 = Fetch tile from VRAM bank 0, 1 = Fetch tile from VRAM bank 1
        dmg_palette: u1, // DMG palette [Non CGB Mode only]: 0 = OBP0, 1 = OBP1
        flip_x: bool, // X flip: 0 = Normal, 1 = Entire OBJ is horizontally mirrored
        flip_y: bool, // Y flip: 0 = Normal, 1 = Entire OBJ is vertically mirrored
        priority: u1, // Priority: 0 = No, 1 = BG and Window colors 1–3 are drawn over this OBJ
    },
};

comptime {
    assert(@sizeOf(MMIO) == 16);
    assert(@sizeOf(MMIO_Palette) == 1);
    assert(@sizeOf(Sprite) == 4);
    assert(@sizeOf(PositionTileLocal) == 2);
}

// MMIO Offsets
const LCDC = 0x40; // LCD Control (R/W)
const STAT = 0x41; // LCDC Status (R/W)
const SCY = 0x42; // Scroll Y (R/W)
const SCX = 0x43; // Scroll X (R/W)
const LY = 0x44; // LCDC Y-Coordinate (R)
const LYC = 0x45; // LY Compare (R/W)
const DMA = 0x46;
const BGP = 0x47; // BG Palette Data (R/W) - Non CGB Mode Only
const OBP0 = 0x48; // Object Palette 0 Data (R/W) - Non CGB Mode Only
const OBP1 = 0x49; // Object Palette 1 Data (R/W) - Non CGB Mode Only
const WY = 0x4A; // Window Y Position (R/W)
const WX = 0x4B; // Window X Position minus 7 (R/W)
const KEY0 = 0x4C; // Controls DMG mode and PGB mode
const KEY1 = 0x4D; // CGB Mode Only - Prepare Speed Switch
const VBK = 0x4F; // CGB Mode Only - VRAM Bank
