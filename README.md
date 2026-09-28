# alttp-zig

A Link to the Past, reimplemented from scratch and ported to Zig.

This is a fork of [snesrev/zelda3](https://github.com/snesrev/zelda3). The
reimplementation is theirs: years of reverse engineering by snesrev and a long
list of contributors, written in C, covering every part of the game from the
title screen to the credits. I ported all of it to Zig and then kept going. It
has a start menu built in now, a settings screen inside the game itself, and
controller rumble, which the SNES never had. It builds its own asset file
straight out of a ROM, so Python isn't part of the picture anymore.

You bring your own US ROM. No game data ships here, and once the assets are
built the ROM isn't needed again.

Upstream's Discord, which is where the interesting conversations happen:
https://discord.gg/AJJbJAzNNJ

## Downloads

[Releases](https://github.com/YeOldPress/alttp-zig/releases) have a macOS app
(Apple Silicon, macOS 11 or newer), a Linux AppImage (x86_64, glibc 2.35 or
newer, so Ubuntu 22.04 and anything after it) and a Windows zip. SDL3 is inside
all three. Start it, give it your ROM, press Play.

The app and the AppImage can't write inside themselves, so they keep
`zelda3.ini`, `zelda3_assets.dat` and your saves in a data directory instead:
`~/Library/Application Support/alttp-zig` on macOS, `~/.local/share/alttp-zig`
on Linux. That's also where to put an MSU pack or edit the ini by hand. The
Windows zip keeps everything in its own folder, same as a build from source.

## Getting it running

You need [Zig 0.16.0](https://ziglang.org/download/) and SDL3.

```sh
sudo apt install libsdl3-dev   # Ubuntu 25.10 or newer
sudo dnf install SDL3-devel    # Fedora
sudo pacman -S sdl3            # Arch
brew install sdl3              # macOS
```

Older Ubuntu releases have no SDL3 package and need a source build. SDL3 ships
no `sdl3-config`, so the build finds it through `pkg-config`, falling back to a
plain `-lSDL3` if pkg-config doesn't know about it.

Then:

```sh
git clone https://github.com/YeOldPress/alttp-zig
cd alttp-zig
zig build run
```

Drop your ROM at `zelda3.sfc` in the repository root before you start it, or
just drag it onto the window when it asks. Press Play: it builds the assets if
they're missing and starts the game.

The game lands in `zig-out/bin` as `zelda3`. That's the whole thing: one
executable, with the menu, the asset builder and the game all inside it.

### On Windows

Nothing on Windows knows what pkg-config is, so fetch SDL3 yourself and point
the build at it. Take `SDL3-devel-<version>-mingw.zip` from
[SDL's releases](https://github.com/libsdl-org/SDL/releases), unzip it
somewhere, and:

```
zig build -Dsdl-include=<sdl>\x86_64-w64-mingw32\include ^
          -Dsdl-lib=<sdl>\x86_64-w64-mingw32\bin
```

`-Dsdl-lib` points at `bin` rather than `lib` on purpose. That package's import
library is called `libSDL3.dll.a`, which zig doesn't go looking for, so it
links against `SDL3.dll` itself instead. If you'd rather use the Visual Studio
package, point it at `lib\x64`, which has a `SDL3.lib` zig does recognise.

Copy `SDL3.dll` in next to the binaries when you're done, or put it on PATH.
Nothing starts without it.

You can also build the Windows binaries from Linux or macOS, which is how this
gets checked:

```sh
zig build -Dtarget=x86_64-windows -Dsdl-include=... -Dsdl-lib=...
```

### The other build steps

```sh
zig build test                     # the port's own tests
zig build run                      # build and start the game
zig build assets                   # build zelda3_assets.dat, no window
zig build -Doptimize=ReleaseSafe   # if the debug build is too slow for you
```

## The start menu

`zelda3` opens on it. It edits `zelda3.ini` and builds the asset file, and when
you press Play it closes and the game opens in its place, in the same process.
It draws with SDL's built-in 8x8 font, so there's no toolkit and no font file
to ship, just the SDL the game already links.

Set `StartMenu = 0` in `[General]`, or turn off Start Menu in this menu or in
the [settings inside the game](#settings-inside-the-game), to go straight into
the game. The menu shows up anyway if the asset file is
missing or doesn't match, because the game won't start on assets it can't
vouch for.

| Menu entry | What it does |
| --- | --- |
| Settings | General, graphics and sound |
| Features | The extras listed under [What's different](#whats-different-from-the-original) |
| Save Settings | Writes `zelda3.ini` |
| Build Assets | Asks for a ROM, then builds `zelda3_assets.dat` |
| Play | Saves the ini and starts the game |

| | Keyboard | Gamepad | Mouse |
| --- | --- | --- | --- |
| Move | Arrows | D-pad or stick | Hover, or wheel |
| Select, or cycle a value | Enter | A | Left click |
| Previous/next value | Left/Right | Left/Right | - |
| Save | S | X | - |
| Back, or quit | Esc | B | Right click |

Pad faces are read by the label printed on them rather than by position, so on
a Nintendo pad the button its case calls A is the one that selects. This sounds
like a detail and cost me an evening, because getting it wrong meant pressing A
on the main menu closed the whole thing.

Under the Play button it tells you what state the asset file is in:

- **ASSETS VERIFIED**, it matches the digest the importer produces
- **ASSETS PRESENT - CHECKSUM DIFFERS**, something else is there, usually an
  older file
- **ASSETS MISSING**, there's nothing to load

That check exists because presence isn't enough. A stale `.dat` loads perfectly
happily and then the game misbehaves in ways that look like game bugs rather
than like a bad file, which is a miserable thing to debug.

When it asks for a ROM you can drop any `.sfc` or `.smc` on the window (the
name doesn't matter, it checks the contents) or press A or Enter to use the
`zelda3.sfc` sitting beside the game.

Settings that are free text, `WindowSize`, `Shader` and `MSUPath`, plus the key
bindings, are shown but not editable here. Edit `zelda3.ini` for those. The ini
gets rewritten a line at a time, so its comments and layout survive the trip.
A setting your ini is too old to mention shows its built-in default, and if
you change it, it's added to the end of its section along with the comment
that explains it.

## Settings inside the game

The same settings, without leaving the game. Press Start, then Select, and the
old Continue / Save and Quit question has a third answer, **Settings**. The
file select screen has it too, on the bottom row next to QUIT GAME.

It's drawn with the game's own graphics: the inventory's framed boxes, item
icons for tabs (the Book of Mudora for General, the Magic Mirror for Graphics,
the Flute for Sound, the Pegasus Boots for Features), hearts for on and off, a
magic-meter bar for numbers, and the dialogue font for every word.

| Button | Does |
| --- | --- |
| L / R | Change tab |
| Up / Down | Pick a setting |
| Left / Right, or A | Change it |
| Y | Explain what it does |
| B or Start | Save `zelda3.ini` and go back |

Anything that can change under a running game does so straight away: every
feature toggle, rumble, fullscreen, the renderer switches, filtering, FPS in the
title, frame delay, autosave and the MSU resume and cue options. The rest, the
output method, the audio device settings and the aspect ratio among them, say
"Applies next start" beside the tab's name, because they're read once when the
game starts up.

Under the hood it paints over the finished frame rather than building a screen
in VRAM, and the game waits in its own save menu underneath the whole time, so
leaving needs nothing putting back. The Settings choice isn't offered when
comparing against the original ROM (`zelda3 <rom>`) or with non-US dialogue
loaded, since the new line on the Select menu is written in the US text
encoding.

## Rumble

The SNES pad had no motor, so the game never asks for rumble. This port
watches what the game does and shakes the controller to match:

- Link getting hurt, harder for bigger hits. Falling into a pit counts.
- Explosions: bombs, and every blast of Bombos.
- The screen shaking: dashing into a wall with the Pegasus Boots, the Quake
  medallion, dungeon entrances opening, bosses emerging.
- A boss dying, which builds to full strength over the explosions and ends on
  one big thump when it disappears.
- Heavy things moving: push blocks, statues, gravestones, Somaria blocks, pull
  switches, the Swamp Palace levers and the Sanctuary's sliding shelf.
- Link's arrows landing, a little firmer in an enemy than in a wall. Enemy
  arrows don't count.
- Doors sliding open, the ones floor switches work included.
- The hammer landing, and the hookshot bouncing off a wall, catching, and
  reeling Link in.

It only ever reads game state, so the port still matches the original frame
for frame with it on. It stays quiet during replays and when you load a
snapshot. `Rumble` in `[General]` sets the strength, 0% turns it off, and
`zelda3 --pad-info` or the console output when a pad connects says whether
your pad has a motor at all. Plenty of SNES-style pads don't.

## Playing

`zelda3` moves into the directory holding `zelda3.ini` and `zelda3_assets.dat`
before it reads anything, so it doesn't matter where you start it from. That's
its own directory (`zig-out/bin` for a build from source), or the data
directory above for the app and the AppImage. `zelda3 --data-dir` prints which.
If there's no `zelda3.ini` there, it writes out the default one it was built
with.

| Button | Key |
| ------ | ----------- |
| Up | Up arrow |
| Down | Down arrow |
| Left | Left arrow |
| Right | Right arrow |
| Start | Enter |
| Select | Right shift |
| A | X |
| B | Z |
| X | S |
| Y | A |
| L | C |
| R | V |

Rebindable in `zelda3.ini`, along with the gamepad.

| Key | Action |
| --- | --- |
| Tab | Turbo |
| P / Shift+P | Pause, with and without the dimming |
| Alt+Enter | Fullscreen |
| Ctrl+Up / Ctrl+Down | Window bigger / smaller |
| Shift+= / Shift+- | Volume up / down |
| F1-F10 | Load snapshot |
| Shift+F1-F10 | Save snapshot |
| Ctrl+F1-F10 | Replay snapshot |
| T | Toggle replay turbo |
| L | Stop replaying a snapshot |
| K | Clear the joypad input log |
| W | Fill health and magic |
| Shift+W | Fill rupees, bombs and arrows |
| O | Set the dungeon key count to 1 |
| Ctrl+E | Walk through walls |
| Ctrl+R | Reset |
| R | Toggle the fast and slow renderers |
| F | Show renderer performance |

`LoadRef` and `ReplayRef` put the dungeon playthrough snapshots on 1-9. They
ship commented out in `zelda3.ini`.

Arguments worth knowing:

- `zelda3 <rom>` runs the original machine code alongside the port and compares
  the whole RAM state every frame. This is how the port gets verified, and it's
  how most of the bugs in it were found. It skips the start menu.
- `zelda3 --config <path>` reads a different ini, from the directory you're in,
  and skips the start menu. Without it the game moves to its own directory
  first.
- `zelda3 --build-assets` builds `zelda3_assets.dat` and exits.
- `zelda3 --data-dir` prints where the ini, assets and saves live.
- `zelda3 --pad-info` lists the connected pads and what SDL makes of their
  buttons.
- `zelda3 --render <chapter> <script> <out.bmp>` plays a script of button
  presses from one of the chapter snapshots in `saves/ref` (0 to 12, or `-` to
  start from power-on) with no window, then writes the last frame as a BMP.
  `60,1:start,20,1:select,30` waits a second, taps Start, waits, taps Select
  and waits again. It's for looking at screens while working on them without
  playing your way there every time.

Snapshots save the joypad input history too, so you can replay a whole
playthrough in turbo mode and check the game still does exactly what it did.

## MSU audio

If you have an MSU music pack, point `MSUPath` at it and set `EnableMSU`. The
value looks like five options but it's really two choices stuck together, which
track set and which file format:

| Value | Files | Track set |
| --- | --- | --- |
| `false` | none, you get the SPC music | - |
| `true` | `<MSUPath><n>.pcm` | plain |
| `deluxe` | `<MSUPath><n>.pcm` | deluxe |
| `opuz` | `<MSUPath><n>.opuz` | plain |
| `deluxe-opuz` | `<MSUPath><n>.opuz` | deluxe |

Plain packs give you one track per song. Deluxe packs give you one track per
*place*: the game's music id gets remapped by which overworld area or which
entrance you're standing in, so Death Mountain, Kakariko and the lost woods
each get their own music instead of sharing the overworld theme. That's 73
extra tracks, numbered 37 to 114. OPUZ is the same music Opus-compressed, about
a tenth of the size.

Deluxe is a property of the pack you downloaded, not a quality setting. Set it
with a plain pack installed and the game will go looking for tracks that aren't
there and quietly fall back to chip music in most rooms.

Two gotchas worth putting in writing, because both cost me time. MSU only mixes
in stereo, so `AudioChannels = 1` silently gives you no MSU audio at all. And
`AudioFreq` gets overridden while MSU is on, to 44100 for PCM and 48000 for
OPUZ, because the mixer has to run at whatever rate the decoder produces.

## Assets

`zelda3_assets.dat` holds everything the game needs that came out of the ROM:
levels, graphics, music, text. Building it is a one-off.

```sh
zig build assets    # no window
```

or let the start menu do it. The importer is Zig, it takes about a tenth of a
second, and the file it writes is byte-for-byte the one `assets/restool.py`
used to produce. There's a test pinning that digest, because "close enough" on
an asset file means bugs that look like game bugs.

ROMs are recognised by SHA-1. The US, German and French releases are known, but
only the US ROM can build the asset file; the other two are for pulling
dialogue out in their language. A headered `.smc` is fine, the copier header
gets stripped on the way in. The US ROM's SHA256 is
`66871d66be19ad2c34c927d6b14cd8eb6fc3181965b6e517cb361f7316009cfb`.

The Python tool is still in `assets/` and still works, and it's still the route
to the extra languages:

```sh
python3 -m pip install -r requirements.txt
python3 assets/restool.py --extract-dialogue -r german.sfc
python3 assets/restool.py --languages=de
```

If you move the game somewhere else, take `zelda3_assets.dat` with it.

## Checking the port against the original C

The port is meant to behave identically to the C it came from, and that gets
checked rather than assumed:

```sh
python3 other/check_ancilla_parity.py
python3 other/check_ancilla_parity.py -Doptimize=ReleaseSafe
```

This compiles the original C from commit `fbbb3f9`, runs it against the port
and diffs the complete RAM state. It needs git history containing that commit.
The script builds a temporary, symbol-renamed reference and pulls the headers
it needs from that commit too, so it stays self-contained now that the tree
carries no headers of its own.

Between this and replaying recorded input frame by frame, several bugs turned
up that had been sitting in the port unnoticed, including one that dragged Link
most of a screen the wrong way whenever a Debirando pit pulled at him.

## What's different from the original

All of this is inherited from upstream. The presentation options live in
`[General]`, `[Graphics]` and `[Sound]` in `zelda3.ini`; the gameplay toggles
are in `[Features]`, which is the start menu's Features screen.

- Widescreen, 16:9, 16:10 or 18:9, and a higher resolution world map
- Pixel shaders
- MSU audio
- Switching items with L and R, which also puts a second item slot on X (hold
  X, L or R in the item screen to assign)
- Turning while dashing, using the mirror to reach the Dark World, collecting
  items and breaking pots with the sword, carrying 9999 rupees, four active
  bombs instead of two, skipping the intro, cancelling bird travel, showing
  maxed-out counts in yellow
- An assortment of bug fixes, both the cosmetic kind and the kind that changes
  how the game plays

Most of those ship off. The low health beep is the exception: `zelda3.ini`
turns it off out of the box, and you can have it back if you miss it.

Added here:

- [Settings inside the game](#settings-inside-the-game), behind Select and on
  the player select screen
- [Rumble](#rumble)
- A start menu for settings, the ROM and the asset file, built into the game
  rather than a separate program
- A quit option on the player select screen, so you don't have to close the
  window with a controller in your hands

## Questions nobody asked

**Why Zig?**

Because I love programming in it. That's the whole answer. It reads like C,
but a debug build trips over most of C's undefined behaviour out loud instead
of letting it quietly corrupt something, the build system is the language
instead of a second language bolted on the side, it cross-compiles for Windows
from a Mac without complaint, and it talks to C as if it had always been
there, which matters a great deal when the thing you're porting is a lot of C.

**Why not Rust?**

Rust is a perfectly good language. It's the Rust community that makes me
nervous.

Nobody tells you about Rust. It finds you. Mention a C port anywhere in public
and within the hour a stranger will be explaining memory safety to you,
unprompted, with the quiet warmth of someone handing you a pamphlet at the
door. "Rewrite It In Rust" isn't a suggestion over there, it's a greeting. You
don't adopt Rust so much as get converted to it: there's a crab mascot, a
sacred text, a ritual where you spend a week fighting the borrow checker and
come out the other side unable to stop talking about lifetimes, and a firm
belief that everyone else is simply further back on the path.

This is a SNES game. It has 128K of RAM and a fixed set of things it does
with it, and the port is checked frame by frame against the original. I'm not
sure what I'd be being saved from.

If you've read this far and are already drafting an issue titled "Have you
considered Rust?": yes. That's why.

## Credits

snesrev and the zelda3 contributors did the reverse engineering and wrote the
reimplementation this is a port of. snesrev credits spannerism's Zelda 3 JP
disassembly and the other disassemblies that documented function names and
variables.

The SNES PPU and DSP come from [LakeSnes](https://github.com/elzo-d/LakeSnes)
by elzo_d, by way of upstream, which optimised them heavily.

## Licence

MIT, see `LICENSE.txt`.

This is a fork and it inherits that licence. `LICENSE.txt` is unchanged and
keeps the original copyright notices, Copyright (c) 2022 snesrev and Copyright
(c) 2021 elzo_d, as the MIT licence requires.

No game assets are distributed here. Playing requires a ROM you already own,
which the assets get extracted from locally.

Vendored under `third_party/`, each under its own licence:

| Component | Licence | Full text |
| --- | --- | --- |
| Opus 1.3.1 (stripped) | 3-clause BSD, (c) Xiph.Org Foundation and others | `third_party/opus-1.3.1-stripped/COPYING`, also appended to `LICENSE.txt` |
| stb_image v2.27 | MIT or public domain (Unlicense), (c) Sean Barrett | end of `third_party/stb/stb_image.h` |
| gl_core 3.1 | Generated OpenGL loader (glLoadGen), carries no licence text | none |

SDL3, libc and OpenGL are linked as system dependencies and aren't included
here.

## Things that no longer exist

The `Makefile`, `Zelda3.sln`, `zelda3.vcxproj` and `run_with_tcc.bat` all built
the C sources and were removed once there weren't any. `zig build` replaces
them, and MSBuild can't build a Zig project anyway. Upstream still has working
versions of all of it.

There was a Nintendo Switch target, and upstream still has a working one. Its
Makefile built the C sources that no longer exist here, so it went with them.

The same goes for the Windows system volume mixer, which upstream drives from
`volume_control.c`. This build had it compiled out from the moment the C went,
so that file was doing nothing but sitting there. Volume changes adjust the
game's own mix instead.

`extract_assets.bat` still calls the Python tool and still works if you have
Python with Pillow and PyYAML. `zig build assets` replaces it and needs
neither.
