# Gameboy Emulator

There's a simple Gameboy emulator written in zig using SDL2. It can run games like Tetris, Zelda or Kirby decently, and doesn't pretend to do much more. Most basic features are implemented, like graphics, sound and controls, but there was no effort to support any complex hardware behavior or bugs.

Tetris             |  Zelda
:-------------------------:|:-------------------------:
![image](https://github.com/Ryp/gb-emu-zig/assets/1625198/3d174690-ba52-46fd-9e9e-02e6101c8041) | ![image](https://github.com/Ryp/gb-emu-zig/assets/1625198/05800d09-e7e2-45f6-a41f-503ba853bbdf)

ROM-only and MBC1 cartridge are supported, whereas MBC2 has limited support. On the other hand the codebase should be very simple to get into and hopefully very readable.
Sound will accumulate lag over time under normal use, this is a known bug.

## How to run

This should get you going after cloning the repo:
```bash
zig build run -- <rom_file>
```

## Controls

| Keyboard key          | Gameboy            |
|-----------------------|--------------------|
| Esc                   | Exit               |
| WASD                  | DPad               |
| O                     | A                  |
| K                     | B                  |
| Enter                 | Start              |
| B                     | Select             |
