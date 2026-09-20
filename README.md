# alttp-zig

A Zig port of [snesrev/zelda3](https://github.com/snesrev/zelda3), a
reimplementation of Zelda 3.

This is a fork. The original project is written in C by snesrev and
contributors; this repository ports that code to Zig. Upstream remains the
source of the game logic, the asset pipeline and the reverse-engineering work
behind both — see the [About](#about) section for its credits. The MIT licence
and the original copyright notices are retained unchanged in `LICENSE.txt`.

Upstream's discord server is: https://discord.gg/AJJbJAzNNJ

## Zig port (this checkout)

Build with Zig 0.16.0 and SDL3. All game code is handwritten Zig; third-party
OpenGL loading, stb_image, and Opus remain C dependencies.

```sh
zig build                          # game and launcher into zig-out/bin
zig build test
zig build -Doptimize=ReleaseSafe
zig build launcher                 # settings, asset building, and play
zig build assets                   # just build zelda3_assets.dat, no window
zig build run                      # run the game directly
```

Put your own US ROM at `zelda3.sfc` in the repository root, then run `zig build
launcher`. The launcher builds `zelda3_assets.dat` from it - press B, or just
press enter to play and it builds them first - edits everything in
`zelda3.ini`, and starts the game. No Python, Pillow or PyYAML is needed; the
asset importer is Zig and produces a file identical to the one the old
`assets/restool.py` produced.

The binaries are `zig-out/bin/zelda3` and `zig-out/bin/zelda3-launcher`. The
game reads `zelda3.ini` and `zelda3_assets.dat` from the working directory, so
run it from `zig-out/bin` (the launcher moves there for you).
SDL3 must be installed and discoverable through `pkg-config --cflags/--libs
sdl3` or the system library search paths. (SDL3 ships no `sdl3-config`.)

The conversion is **complete**. Every game routine in `src/` and `snes/` is Zig,
and no project C source or header remains: the only C still compiled is
third-party (`gl_core`, `stb_image`, Opus), alongside the usual SDL3, libc and
OpenGL linkage.

Optional differential checks compare the port's results and complete RAM state
with the original C from commit `fbbb3f967a51fafe642e6140d0753979e73b4090`:

```sh
python3 other/check_ancilla_parity.py
python3 other/check_ancilla_parity.py -Doptimize=ReleaseSafe
```

These checks require Git history containing that commit. The script creates a
temporary, symbol-renamed C reference — together with the headers it needs, also
taken from that commit — so it stays self-contained now that the tree carries no
headers of its own. It does not generate Zig implementations or add the
reference to the game build.

## About

This is a reverse engineered clone of Zelda 3 - A Link to the Past.

It's around 70-80kLOC of C code, and reimplements all parts of the original game. The game is playable from start to end.

You need a copy of the ROM to extract game resources (levels, images). Then once that's done, the ROM is no longer needed.

It uses the PPU and DSP implementation from [LakeSnes](https://github.com/elzo-d/LakeSnes), but with lots of speed optimizations.
Additionally, it can be configured to also run the original machine code side by side. Then the RAM state is compared after each frame, to verify that the C implementation is correct.

I got much assistance from spannerism's Zelda 3 JP disassembly and the other ones that documented loads of function names and variables.

## Additional features

A bunch of features have been added that are not supported by the original game. Some of them are:

Support for pixel shaders.

Support for enhanced aspect ratios of 16:9 or 16:10.

Higher quality world map.

Support for MSU audio tracks.

Secondary item slot on button X (Hold X in inventory to select).

Switching current item with L/R keys.

## How to Play:

Option 1: Launcher by RadzPrower (windows only) https://github.com/ajohns6/Zelda-3-Launcher

Option 2: Building it yourself

Visit Wiki for more info on building the project: https://github.com/snesrev/zelda3/wiki

## Installing Python & libraries on Windows (required for asset extraction steps)
1. Download [Python](https://www.python.org/ftp/python/3.11.1/python-3.11.1-amd64.exe) installer and install with "Add to PATH" checkbox checked
2. Open the command prompt
3. Type `python -m pip install --upgrade pip pillow pyyaml` and hit enter
4. Close the command prompt

## Compiling on Windows
1. Download the project by clicking "Code > Download ZIP" on the github page
2. Extract the ZIP to your hard drive
3. Place the USA rom named `zelda3.sfc` in the root directory.
4. Double-click `extract_assets.bat` in the main dir to create `zelda3_assets.dat` in that same dir
5. Build with `zig build` as described at the top of this file
6. Configure with `zelda3.ini` in the main dir

The TCC and Visual Studio routes (`run_with_tcc.bat`, `Zelda3.sln`,
`zelda3.vcxproj`) compiled `src/*.c` and were removed once the last C sources
were ported; MSBuild cannot build a Zig project. Both remain available in
upstream: https://github.com/snesrev/zelda3

## Installing libraries on Linux/MacOS
1. Open a terminal
2. Install pip if not already installed
```sh
python3 -m ensurepip
```
3. Clone the repo and `cd` into it
```sh
git clone https://github.com/snesrev/zelda3
cd zelda3
```
4. Install requirements using pip
```sh
python3 -m pip install -r requirements.txt
```
5. Install SDL3
* Ubuntu/Debian `sudo apt install libsdl3-dev` (Ubuntu 25.10 or newer; older
  releases have no SDL3 package and need a source build)
* Fedora Linux `sudo dnf install SDL3-devel`
* Arch Linux `sudo pacman -S sdl3`
* macOS: `brew install sdl3` (you can get homebrew [here](https://brew.sh/))

## Compiling on Linux/MacOS
1. Place your US ROM file named `zelda3.sfc` in `zelda3`
2. Extract the assets
```sh
python3 assets/restool.py --extract-from-rom
```
3. Build and run
```sh
zig build
zig build run
```

The `Makefile` was removed along with the last C sources — `zig build` replaces
it. A Nintendo Switch target still exists under `src/platform/switch/`, but its
Makefile builds the old C sources and no longer works here; upstream
(https://github.com/snesrev/zelda3) still has a working one.

## More Compilation Help

Look at the wiki at https://github.com/snesrev/zelda3/wiki for more help.

The ROM needs to be named `zelda3.sfc` and has to be from the US region with this exact SHA256 hash
`66871d66be19ad2c34c927d6b14cd8eb6fc3181965b6e517cb361f7316009cfb`

In case you're planning to move the executable to a different location, please include the file `zelda3_assets.dat`.

## Usage and controls

The game supports snapshots. The joypad input history is also saved in the snapshot. It's thus possible to replay a playthrough in turbo mode to verify that the game behaves correctly.

The game is run with `./zelda3` and takes an optional path to the ROM-file, which will verify for each frame that the C code matches the original behavior.

| Button | Key         |
| ------ | ----------- |
| Up     | Up arrow    |
| Down   | Down arrow  |
| Left   | Left arrow  |
| Right  | Right arrow |
| Start  | Enter       |
| Select | Right shift |
| A      | X           |
| B      | Z           |
| X      | S           |
| Y      | A           |
| L      | C           |
| R      | V           |

The keys can be reconfigured in zelda3.ini

Additionally, the following commands are available:

| Key | Action                |
| --- | --------------------- |
| Tab | Turbo mode |
| W   | Fill health/magic     |
| Shift+W   | Fill rupees/bombs/arrows     |
| Ctrl+E | Reset            |
| P   | Pause (with dim)                |
| Shift+P   | Pause (without dim)                |
| Ctrl+Up   | Increase window size                |
| Ctrl+Down   | Decrease window size                |
| T   | Toggle replay turbo mode  |
| O   | Set dungeon key to 1  |
| K   | Clear all input history from the joypad log  |
| L   | Stop replaying a shapshot  |
| R   | Toggle between fast and slow renderer |
| F   | Display renderer performance |
| F1-F10 | Load snapshot      |
| Alt+Enter | Toggle Fullscreen     |
| Shift+F1-F10 | Save snapshot |
| Ctrl+F1-F10 | Replay the snapshot |
| 1-9 | Load a dungeons playthrough snapshot |
| Ctrl+1-9 | Run a dungeons playthrough in turbo mode |


## License

This project is licensed under the MIT license. See `LICENSE.txt` for details.

It is a fork of [snesrev/zelda3](https://github.com/snesrev/zelda3) and inherits
that licence. `LICENSE.txt` retains the original copyright notices — Copyright
(c) 2022 snesrev and Copyright (c) 2021 elzo_d — as the MIT licence requires.
The SNES PPU and DSP implementation originates in
[LakeSnes](https://github.com/elzo-d/LakeSnes) by elzo_d.

No game assets are distributed. Running the game requires a ROM you already
own, from which the assets are extracted locally.

### Third-party components

Vendored under `third_party/`, each under its own licence:

| Component | Licence | Full text |
| --- | --- | --- |
| Opus 1.3.1 (stripped) | 3-clause BSD, © Xiph.Org Foundation and others | `third_party/opus-1.3.1-stripped/COPYING`, also appended to `LICENSE.txt` |
| stb_image v2.27 | Dual: MIT or public domain (Unlicense), © Sean Barrett | end of `third_party/stb/stb_image.h` |
| gl_core 3.1 | Generated OpenGL loader (glLoadGen); no licence text is present in the file | — |

SDL3, libc and OpenGL are linked as external system dependencies and are not
included in this repository.
