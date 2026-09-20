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
zig build test                     # the port's own tests
zig build -Doptimize=ReleaseSafe
zig build launcher                 # settings, asset building, and play
zig build assets                   # just build zelda3_assets.dat, no window
zig build run                      # run the game directly
```

SDL3 must be installed and discoverable through `pkg-config --cflags/--libs
sdl3` or the system library search paths. (SDL3 ships no `sdl3-config`.)

The binaries are `zig-out/bin/zelda3` and `zig-out/bin/zelda3-launcher`. The
game reads `zelda3.ini` and `zelda3_assets.dat` from the working directory, so
run it from `zig-out/bin` — the launcher moves there for you.

The conversion is **complete**. Every game routine in `src/` and `snes/` is Zig,
and no project C source or header remains: the only C still compiled is
third-party (`gl_core`, `stb_image`, Opus), alongside the usual SDL3, libc and
OpenGL linkage.

## Assets

You need a copy of the ROM to extract the game's resources — levels, graphics,
music, text. Once `zelda3_assets.dat` exists the ROM is no longer needed.

Put your own US ROM at `zelda3.sfc` in the repository root, then either:

```sh
zig build launcher    # choose Build Assets, or just press Launch
zig build assets      # no window; writes zig-out/bin/zelda3_assets.dat
```

The importer is Zig. No Python, Pillow or PyYAML is needed, and the file it
writes is byte-for-byte the one the old `assets/restool.py` produced — a test
checks it against that digest. A headered `.smc` is fine; the copier header is
stripped when the ROM is read.

ROMs are recognised by SHA-1, and the US, German and French releases are known.
Only the US ROM can build the asset file; the other two matter for extracting
dialogue in their language. The US ROM has this SHA256 hash:
`66871d66be19ad2c34c927d6b14cd8eb6fc3181965b6e517cb361f7316009cfb`

The Python tool under `assets/` still works and still builds the same file. It
remains the route for the extra languages, and it needs its libraries:

```sh
python3 -m pip install -r requirements.txt
python3 assets/restool.py --extract-from-rom
python3 assets/restool.py --languages=de
```

If you move the game somewhere else, take `zelda3_assets.dat` with it.

## The launcher

`zig build launcher`, or `zig-out/bin/zelda3-launcher`, opens a small window
that edits `zelda3.ini`, builds the asset file and starts the game. It draws
with SDL's built-in 8x8 font, so it needs no toolkit and no font file — just
the SDL the game already links.

| Menu entry | What it does |
| --- | --- |
| Settings | General, graphics and sound options |
| Features | The extras listed under [Additional features](#additional-features) |
| Save Settings | Writes `zelda3.ini` |
| Build Assets | Asks for a ROM, then builds `zelda3_assets.dat` |
| Launch | Saves the ini and starts the game |

Under the Launch button the launcher says which state the asset file is in:
**ASSETS VERIFIED** when it matches the digest the importer produces, **ASSETS
PRESENT - CHECKSUM DIFFERS** when something else is there, usually an older
file, and **ASSETS MISSING** when there is none. Presence alone is not enough:
a stale `.dat` loads and then misbehaves in ways that look like game bugs.

Build Assets — and Launch, when there are no assets yet — asks for a ROM. Drop
any `.sfc` or `.smc` on the window, the name does not matter because the
contents are checked, or press A/Enter to use the `zelda3.sfc` already sitting
beside the game.

| | Keyboard | Gamepad | Mouse |
| --- | --- | --- | --- |
| Move | Arrows | D-pad or stick | Hover, or wheel |
| Select, or cycle a value | Enter | A | Left click |
| Previous/next value | Left/Right | Left/Right | — |
| Save | S | X | — |
| Back, or quit | Esc | B | Right click |

Gamepad faces are read by their printed label rather than their position, so on
a Nintendo pad the button its case labels A is the one that confirms. Held
directions repeat. Leaving asks first — B sits next to A, and the window is one
press from gone — and says so when there are unsaved changes.

Settings that are free text (`WindowSize`, `Shader`, `MSUPath`) and the key
bindings are shown but not editable here; edit `zelda3.ini` for those. The ini
is rewritten a line at a time, so its comments, ordering and spacing survive.

## Running the game

Run `zelda3` from the directory holding `zelda3.ini` and `zelda3_assets.dat`.

- `zelda3 <rom>` also runs the original machine code side by side and compares
  the whole RAM state after each frame, verifying the port against the original.
- `zelda3 --config <path>` reads a different ini. Without it the game moves to
  its own directory first.

The game supports snapshots. The joypad input history is saved in the snapshot
as well, so a playthrough can be replayed in turbo mode to check that the game
still behaves the same.

## Compiling on Windows

1. Install [Zig 0.16.0](https://ziglang.org/download/) and SDL3
2. Download the project by clicking "Code > Download ZIP" on the github page
3. Extract the ZIP to your hard drive
4. Place the USA rom named `zelda3.sfc` in the root directory
5. Build with `zig build`
6. Run `zig build launcher` to build the assets and configure the game

`extract_assets.bat` still calls the Python tool and still works if you have
Python with Pillow and PyYAML installed; `zig build assets` replaces it and
needs neither.

The TCC and Visual Studio routes (`run_with_tcc.bat`, `Zelda3.sln`,
`zelda3.vcxproj`) compiled `src/*.c` and were removed once the last C sources
were ported; MSBuild cannot build a Zig project. Both remain available in
upstream: https://github.com/snesrev/zelda3

## Compiling on Linux/MacOS

1. Install SDL3
* Ubuntu/Debian `sudo apt install libsdl3-dev` (Ubuntu 25.10 or newer; older
  releases have no SDL3 package and need a source build)
* Fedora Linux `sudo dnf install SDL3-devel`
* Arch Linux `sudo pacman -S sdl3`
* macOS: `brew install sdl3` (you can get homebrew [here](https://brew.sh/))

2. Install [Zig 0.16.0](https://ziglang.org/download/)

3. Clone the repo and `cd` into it
```sh
git clone https://github.com/YeOldPress/alttp-zig
cd alttp-zig
```

4. Place your US ROM file named `zelda3.sfc` in the root directory

5. Build and play
```sh
zig build
zig build launcher
```

Python is needed only for the optional differential checks below and for
building the extra languages. The game and its assets need neither.

The `Makefile` was removed along with the last C sources — `zig build` replaces
it. A Nintendo Switch target still exists under `src/platform/switch/`, but its
Makefile builds the old C sources and no longer works here; upstream
(https://github.com/snesrev/zelda3) still has a working one.

## Checking the port against the C

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

It's around 70-80kLOC reimplementing all parts of the original game — C
upstream, Zig here — and the game is playable from start to end.

You need a copy of the ROM to extract game resources (levels, images). Then once that's done, the ROM is no longer needed.

It uses the PPU and DSP implementation from [LakeSnes](https://github.com/elzo-d/LakeSnes), but with lots of speed optimizations.
Additionally, it can be configured to also run the original machine code side by side. Then the RAM state is compared after each frame, to verify that the implementation is correct.

I got much assistance from spannerism's Zelda 3 JP disassembly and the other ones that documented loads of function names and variables.

## Additional features

A bunch of features have been added that are not supported by the original
game. They live under `[Features]` in `zelda3.ini` and in the launcher's
Features screen. Some of them are:

Support for pixel shaders.

Support for enhanced aspect ratios of 16:9 or 16:10.

Higher quality world map.

Support for MSU audio tracks.

Secondary item slot on button X (Hold X in inventory to select).

Switching current item with L/R keys.

## Usage and controls

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

The keys can be reconfigured in `zelda3.ini`, along with the gamepad's.

Additionally, the following commands are available:

| Key | Action                |
| --- | --------------------- |
| Tab | Turbo mode |
| W   | Fill health/magic     |
| Shift+W   | Fill rupees/bombs/arrows     |
| O   | Set dungeon key to 1  |
| Ctrl+E | Walk through walls |
| Ctrl+R | Reset            |
| P   | Pause (with dim)                |
| Shift+P   | Pause (without dim)                |
| Ctrl+Up   | Increase window size                |
| Ctrl+Down   | Decrease window size                |
| Shift+= | Volume up |
| Shift+- | Volume down |
| T   | Toggle replay turbo mode  |
| K   | Clear all input history from the joypad log  |
| L   | Stop replaying a snapshot  |
| R   | Toggle between fast and slow renderer |
| F   | Display renderer performance |
| F1-F10 | Load snapshot      |
| Alt+Enter | Toggle Fullscreen     |
| Shift+F1-F10 | Save snapshot |
| Ctrl+F1-F10 | Replay the snapshot |

`LoadRef` and `ReplayRef` bind the dungeon playthrough snapshots to 1-9. Both
are commented out in `zelda3.ini`; uncomment them to use those.

## More Compilation Help

Look at the wiki at https://github.com/snesrev/zelda3/wiki for more help.

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
