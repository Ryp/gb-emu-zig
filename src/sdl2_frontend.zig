const std = @import("std");
const assert = std.debug.assert;

const cpu = @import("gb/cpu.zig");
const execution = @import("gb/execution.zig");
const lcd = @import("gb/lcd.zig");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const BgColor = c.SDL_Color{ .r = 0, .g = 0, .b = 128, .a = 255 };

const SdlContext = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
};

fn create_sdl_context(allocator: std.mem.Allocator) !SdlContext {
    _ = allocator; // FIXME

    if (c.SDL_Init(c.SDL_INIT_EVERYTHING) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    errdefer c.SDL_Quit();

    const window_width = lcd.ScreenWidth;
    const window_height = lcd.ScreenHeight;

    const window = c.SDL_CreateWindow("Gameboy Emu", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @intCast(window_width), @intCast(window_height), c.SDL_WINDOW_SHOWN) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    errdefer c.SDL_DestroyWindow(window);

    if (c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1") == c.SDL_FALSE) {
        c.SDL_Log("Unable to set hint: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    errdefer c.SDL_DestroyRenderer(renderer);

    if (c.TTF_Init() != 0) {
        c.SDL_Log("Unable to initialize TTF: %s", c.TTF_GetError());
        return error.SDLInitializationFailed;
    }
    errdefer c.TTF_Quit();

    return .{
        .window = window,
        .renderer = renderer,
    };
}

fn destroy_sdl_context(allocator: std.mem.Allocator, sdl_context: SdlContext) void {
    _ = allocator; // FIXME

    c.TTF_Quit();

    c.SDL_DestroyRenderer(sdl_context.renderer);
    c.SDL_DestroyWindow(sdl_context.window);
    c.SDL_Quit();
}

pub fn execute_main_loop(allocator: std.mem.Allocator, gb: *cpu.GBState) !void {
    const sdl_context = try create_sdl_context(allocator);
    defer destroy_sdl_context(allocator, sdl_context);

    const title_string = try allocator.alloc(u8, 1024);
    defer allocator.free(title_string);

    const backbuffer = try allocator.alloc(u32, lcd.ScreenWidth * lcd.ScreenHeight);
    defer allocator.free(backbuffer);

    var frame_index: u32 = 0;

    main_loop: while (true) {
        // Poll events
        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent) > 0) {
            switch (sdlEvent.type) {
                c.SDL_QUIT => {
                    break :main_loop;
                },
                c.SDL_MOUSEBUTTONUP => {}, // FIXME
                c.SDL_KEYDOWN => {
                    const key_sym = sdlEvent.key.keysym.sym;
                    switch (key_sym) {
                        // c.SDLK_LEFT => ,
                        // c.SDLK_RIGHT => ,
                        // c.SDLK_UP => ,
                        // c.SDLK_DOWN => ,
                        // c.SDLK_h => ,
                        c.SDLK_ESCAPE => {
                            break :main_loop;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        while (!gb.has_frame_to_consume) {
            try execution.step(gb);
        }

        gb.has_frame_to_consume = false;

        // Set window title
        _ = std.fmt.bufPrintZ(title_string, "Emu frame {}", .{frame_index}) catch unreachable;
        c.SDL_SetWindowTitle(sdl_context.window, title_string.ptr);

        // Clear backbuffer (not necessary, just for debug)
        _ = c.SDL_SetRenderDrawColor(sdl_context.renderer, BgColor.r, BgColor.g, BgColor.b, BgColor.a);
        _ = c.SDL_RenderClear(sdl_context.renderer);

        // Fill backbuffer pixels with emu data
        // FIXME the current format is kinda stupid but works
        for (backbuffer, gb.screen_output) |*out, in| {
            out.* = in;
            out.* = switch (in) {
                0 => 0xFF909090,
                1 => 0xFF606060,
                2 => 0xFF404040,
                3 => 0xFF101010,
                else => 0xFFFF0000,
            };
        }

        const texture = c.SDL_CreateTexture(sdl_context.renderer, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STATIC, lcd.ScreenWidth, lcd.ScreenHeight);
        defer c.SDL_DestroyTexture(texture);

        _ = c.SDL_UpdateTexture(texture, null, @ptrCast(backbuffer.ptr), lcd.ScreenWidth * 4);
        _ = c.SDL_RenderCopy(sdl_context.renderer, texture, null, null);

        c.SDL_RenderPresent(sdl_context.renderer);

        frame_index += 1;
    }
}