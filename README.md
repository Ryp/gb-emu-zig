# Gameboy Emulator

Here's a simple Gameboy emulator written in Zig using SDL3. It can run games like Tetris, Zelda or Kirby decently, and doesn't pretend to do much more. Most basic features are implemented, like graphics, sound and controls, but there was no effort to support any complex hardware behavior or bugs. On the other hand the codebase should be very simple to get into and hopefully very readable.

Tetris             |  Zelda
:-------------------------:|:-------------------------:
![image](https://github.com/Ryp/gb-emu-zig/assets/1625198/3d174690-ba52-46fd-9e9e-02e6101c8041) | ![image](https://github.com/Ryp/gb-emu-zig/assets/1625198/05800d09-e7e2-45f6-a41f-503ba853bbdf)

## How to run

This should get you going after cloning the repo:
```bash
zig build -Doptimize=ReleaseFast run -- <rom_file>
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

## Rough edges

- ROM-only and MBC1 cartridge are supported, whereas MBC2 has limited support. Everything else is unsupported.
- It's assumed your refresh rate is 60Hz. Failing that, the gameplay speed will be wrong and the audio will get wildly out of sync.
- Sound will slowly accumulate lag over time anyway because 60Hz is not 59.94Hz.
