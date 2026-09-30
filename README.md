# alttp-zig

A Link to the Past, reimplemented from scratch and ported to Zig.

This is a fork of [snesrev/zelda3](https://github.com/snesrev/zelda3), the C
reimplementation of the whole game. I ported it to Zig and added a start menu,
a settings screen inside the game, controller rumble, `zelda3-tools` (an asset
toolbox with a window and a command line), and a way to play
[alttpr.com](https://alttpr.com) randomizer seeds with a built-in item
tracker.

You bring your own US ROM. No game data ships here, and once the assets are
built the ROM isn't needed again.

Upstream's Discord: https://discord.gg/AJJbJAzNNJ

## Downloads

[Releases](https://github.com/YeOldPress/alttp-zig/releases) have two
downloads for each platform, both with SDL3 inside:

| | Game | Tools |
| --- | --- | --- |
| macOS 11+, Apple Silicon | `alttp-zig-*-macos-arm64.zip` | `zelda3-tools-*-macos-arm64.zip` |
| Linux x86_64, glibc 2.35+ | `alttp-zig-*-x86_64.AppImage` | `zelda3-tools-*-x86_64.AppImage` |
| Windows x86_64 | `alttp-zig-*-windows-x86_64.zip` | `zelda3-tools-*-windows-x86_64.zip` |

The game is all you need to play: start it, give it your ROM, press Play. The
tools are for modding and extra languages.

The Mac app and the AppImage keep `zelda3.ini`, `zelda3_assets.dat` and your
saves in `~/Library/Application Support/alttp-zig` or
`~/.local/share/alttp-zig`, and the tools default to the same place. On
Windows everything stays in the game's folder.

## Building

You need [Zig 0.16.0](https://ziglang.org/download/) and SDL3.

```sh
sudo apt install libsdl3-dev   # Ubuntu 25.10 or newer
sudo dnf install SDL3-devel    # Fedora
sudo pacman -S sdl3            # Arch
brew install sdl3              # macOS

git clone https://github.com/YeOldPress/alttp-zig
cd alttp-zig
zig build run
```

Put your ROM at `zelda3.sfc` in the repository root, or drag it onto the window
when asked. Both `zelda3` and `zelda3-tools` land in `zig-out/bin`.

```sh
zig build run                      # build and start the game
zig build tools                    # build and open zelda3-tools
zig build assets                   # build zelda3_assets.dat, no window
zig build test                     # the tests
zig build -Doptimize=ReleaseSafe   # a faster build
```

On Windows, take `SDL3-devel-<version>-mingw.zip` from
[SDL's releases](https://github.com/libsdl-org/SDL/releases) and point the
build at it, then copy `SDL3.dll` next to the binaries:

```
zig build -Dsdl-include=<sdl>\x86_64-w64-mingw32\include ^
          -Dsdl-lib=<sdl>\x86_64-w64-mingw32\bin
```

`-Dsdl-lib` points at `bin` on purpose: zig links `SDL3.dll` directly.
The same flags with `-Dtarget=x86_64-windows` cross-compile from Linux or macOS.

## The start menu

`zelda3` opens on a menu for settings, features, controls and building the
asset file.
Press Play and the game starts in the same window. It also shows whether the
asset file is verified, different or missing, and won't start the game on
assets it can't verify.

Turn it off with `StartMenu = 0` in `[General]`, from the menu itself, or from
the settings inside the game. Arrows or the pad to move, Enter or A to pick,
S or X to save, Esc or B to go back.

**Controls** maps the SNES pad's buttons before the game even starts, the
same way the Controls tab does inside the game (below): a big drawing of the
pad, each button's key and controller button, A on a row and then any key or
pad button to change it, and **Reset all to defaults**.

## Settings inside the game

Press Start, then Select, and choose **Settings**. It's also on the player
select screen. Same settings as the start menu, drawn with the game's own
graphics.

<table>
  <tr>
    <td><img src="docs/screenshots/select-menu.png" alt="The Select menu with Continue Game, Save and Quit, and Settings" width="384"></td>
    <td><img src="docs/screenshots/file-select.png" alt="The player select screen, with Settings beside Quit Game on the bottom row" width="384"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/settings-general.png" alt="The General tab, with Rumble selected and its meter full" width="384"></td>
    <td><img src="docs/screenshots/settings-graphics.png" alt="The Graphics tab, with Output Method selected" width="384"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/settings-info.png" alt="The info box for Rumble, explaining what it does" width="384"></td>
    <td></td>
  </tr>
</table>

L/R changes tab, Up/Down picks, Left/Right or A changes, Y explains, B or
Start saves and goes back. Most settings apply right away; the ones that can't
say "Applies next start".

The last tab, **Controls** (the Power Glove), maps the SNES pad's buttons, with
a drawing of the pad that lights up the one you're on. Each row shows its key
and its controller button. Press A on one, then press any key or pad button
to give it that: whichever you press, keyboard or controller, is the one that
changes. Taking one another button already has swaps the two, so nothing is
left without; keys that already do something else (fullscreen, snapshots,
cheats) are refused. Esc, or five seconds, backs out, and **Reset all to
defaults** puts both back. Changes work straight away and are saved to
`Controls` in `[KeyMap]` and `[GamepadMap]`.

## Rumble

The SNES had no rumble, so the port watches the game and shakes the pad to
match: Link getting hurt, explosions, screen shakes, bosses dying, heavy things
moving, arrows landing, doors opening, the hammer and the hookshot. It only
reads game state, so the port still matches the original frame for frame.
`Rumble` in `[General]` sets the strength; `zelda3 --pad-info` says whether
your pad has a motor.

## Playing

| Button | Key | | Key | Action |
| --- | --- | --- | --- | --- |
| D-pad | Arrows | | Tab | Turbo |
| Start | Enter | | P | Pause |
| Select | Right Shift | | Alt+Enter | Fullscreen |
| A | X | | Ctrl+Up/Down | Window size |
| B | Z | | Shift+= / Shift+- | Volume |
| X | S | | F1-F10 | Load snapshot (Shift saves, Ctrl replays) |
| Y | A | | W | Fill health and magic |
| L | C | | Ctrl+E | Walk through walls |
| R | V | | Ctrl+R | Reset |

Keys and the gamepad are rebindable in `zelda3.ini`, which lists the rest of
the debug keys.

- `zelda3 <rom>` runs the original machine code alongside the port and compares
  RAM every frame. This is how the port is verified.
- `zelda3 --config <path>` uses another ini.
- `zelda3 --build-assets` builds the asset file and exits.
- `zelda3 --data-dir` prints where the ini, assets and saves live.
- `zelda3 --render <chapter> <script> <out.bmp>` plays a button script from a
  snapshot in `saves/ref` with no window and saves the last frame. `s<n>` in
  place of the chapter starts from your own quick-save slot n instead.
- `zelda3 seed.sfc` opens a randomizer seed on its page in the start menu.
- `zelda3 --seed-info seed.sfc` prints what a seed says about itself,
  spoilers included, without starting anything.
- `zelda3 --emu-render <seed> <script> <out.bmp>` plays a script in the
  emulator and saves the last frame with the tracker. `TRACKER=overlay` (or
  `window`, `off`), `WIDE=96` and `TRACKER_OPTS="Size=compact;Maps=current"`
  change what's drawn.
- `zelda3 --menu-shot <main|hub|alttpr|details> <out.bmp> [seed]` draws a
  start menu screen with no window.

## MSU audio

Point `MSUPath` at a pack and set `EnableMSU`:

| Value | Files | Tracks |
| --- | --- | --- |
| `true` | `<MSUPath><n>.pcm` | plain |
| `deluxe` | `<MSUPath><n>.pcm` | deluxe |
| `opuz` | `<MSUPath><n>.opuz` | plain |
| `deluxe-opuz` | `<MSUPath><n>.opuz` | deluxe |

Deluxe packs have a track per place rather than per song; only use it with a
deluxe pack. MSU needs `AudioChannels = 2`, and it sets the audio rate itself.
Randomizer seeds play the same pack; see [MSU-1 for seeds](#msu-1-for-seeds).

## Randomizer

Play seeds from [alttpr.com](https://alttpr.com), the A Link to the Past
randomizer, with an item tracker that follows along by itself.

### Getting a seed going

1. On alttpr.com, generate a seed from the **Japanese 1.0 ROM** (MD5
   `03a63945398191337e896e5771f77173`), the one the randomizer is built on,
   and save the `.sfc` it gives you.
2. Start `zelda3`, press **Randomizer** (under Play), then **ALTTPR.COM
   Randomizer**. **Built-In Randomizer** beside it is greyed out: that one is
   coming soon.
3. Drag the seed onto the window. Or skip steps 2 and 3 with `zelda3 seed.sfc`,
   which opens straight on the seed.
4. Press **Play This Seed**, or Start.

The main menu's drag-and-drop is only for the US ROM that builds the port's
assets. A seed dropped there gets pointed at the Randomizer page instead.

### The ALTTPR.COM page

The top of the page is the seed: its name and alttpr.com link, the five hash
icons (the same ones alttpr.com shows, to check you've got the right seed),
logic, mode, goal, how many crystals Ganon's Tower and Ganon want, and how many
item locations there are. Under it are the options for the run.

**Seed Details** lists everything the ROM says about itself: file, size,
whether it has a save yet, which MSU pack will play, the hash, logic, game
type, mode, goal, crystal requirements, item count, swords, map and compass,
small key and big key shuffles, tournament flag, quickswap, pseudo boots,
silver arrows, menu speed, heart beep, heart color, the clock, and starting
items. At the bottom are the spoilers, hidden until you press A: which
medallion Misery Mire and Turtle Rock want, and every dungeon's pendant or
crystal.

### How a seed plays

A seed rewrites too much of the game's code for the port to play it, so it
runs in a SNES emulator instead: the one the port is verified against
(LakeSnes, by way of upstream), put back together as a whole console. It plays
the ROM exactly as the randomizer built it, and the page says so up front.

- **Saves** go next to the seed as `seed.srm`, written as the game saves.
- **Off for seeds:** snapshots, cheats and Turbo. It's a race.
- **Still there:** fullscreen, pause, window size, volume, and Ctrl+R to
  reset. T moves the tracker between its places.

A few of the port's extras come along, because they only watch the game:

- **Rumble**, on by default, the same as in the port.
- **Widescreen**, off by default and marked experimental. Rooms and areas show
  as far as they go, but outdoors the edges can briefly show stale tiles while
  scrolling, and enemies still vanish at the original screen edge.
- **MSU-1 audio**, below.

### MSU-1 for seeds

Seeds play the same MSU pack as the normal game: whatever `MSUPath` in
`[Sound]` points at, `.pcm` or `.opuz`. There's nothing to copy or rename.
Turn it on or off with **MSU-1 Audio** on the page.

The randomizer has MSU-1 support built into every seed, so the seed's own
code picks the tracks, just like on a real SNES. It uses the normal game's
numbering, 1 to 34, plus extras a normal pack doesn't have:

| Tracks | What they are | Without them |
| --- | --- | --- |
| 35 to 46 | One per dungeon | the normal dungeon music |
| 47 to 58 | One per boss | the normal boss music |
| 59 | Ganon's Tower upstairs | the normal music |
| 60 | Light World after the Master Sword | the normal Light World |
| 61 | Dark World with all seven crystals | the normal Dark World |

Normal game packs often have their own track 35 and up, meaning something
else, and a seed would take those for its extras: Eastern Palace plays the
wrong song. So only tracks 1 to 34 are offered, and the seed falls back to the
normal music for everything past that.

### The tracker

It reads the game's save data every frame, so there's nothing to click, and it
draws its icons and maps from the seed, so it looks like the game. It goes
beside the game (either side), over it, in a window of its own, or nowhere.
T switches between those while playing, and closing the tracker's window puts
it back beside the game.

The **large** layout, the default:

- **Counter:** items found out of the seed's total, hearts, and crystals
  against what Ganon's Tower and Ganon need (green once you have enough).
- **Items:** everything in the inventory, dim until found, with counts for
  bottles, pendants and crystals, and half or quarter magic.
- **Dungeons**, one row each, with a stripe for how it stands: red while its
  boss is alive, green once beaten with checks left, grey when there's nothing
  left. Then checks left, small keys found, big key, map, compass, the boss,
  and the prize once you know it.
- **Both world maps**, with a marker on every check: cyan for not yet looked
  at, gold for partly done, grey for done, and bigger ones for dungeons in
  their stripe's colors. The map you're in has a gold frame, and a legend
  underneath says what the colors mean.

The **compact** layout fits the same into less room: the dungeons three
across, with the name in the prize's color once it's known, and the maps side
by side.

### Tracker options

All on the page, and kept in `[Randomizer]` in `zelda3.ini`, apart from the
normal game's settings.

| Option | Key | Values (first is the default) |
| --- | --- | --- |
| Widescreen | `Widescreen` | `4:3` (off), `16:9`, `16:10`, `18:9` |
| Rumble | `Rumble` | `100%`, down to `0%` |
| MSU-1 Audio | `MSUGamePath` | `1`, `0` |
| Placement | `Tracker` | `panel`, `overlay`, `window`, `off` |
| Layout | `TrackerSize` | `large`, `compact` |
| Panel Side | `TrackerSide` | `right`, `left` |
| Show Items | `TrackerItems` | `1`, `0` |
| Show Dungeons | `TrackerDungeons` | `1`, `0` |
| Show Maps | `TrackerMaps` | `both`, `current`, `off` |
| Dungeon Names | `TrackerNames` | `full`, `short` |
| Small Keys | `TrackerKeys` | `1`, `0` |
| Big Key/Map/Compass | `TrackerDungeonItems` | `1`, `0` |
| Bosses | `TrackerBosses` | `1`, `0` |
| Dungeon Prizes | `TrackerPrizes` | `map` (once you have its map), `always` (a spoiler), `off` |
| MM/TR Medallions | `TrackerMedallions` | `0`, `1` (a spoiler) |
| Item Counter | `TrackerCounter` | `1`, `0` |
| Missing Items | `TrackerMissing` | `dim`, `hide` |
| Cleared Checks | `TrackerCleared` | `grey`, `hide` |
| Map Markers | `TrackerMarkers` | `large`, `small` |
| Background | `TrackerBackground` | `dark`, `black`, `green`, `magenta` (the last two key out on a stream) |
| Overlay Opacity | `TrackerOpacity` | `80%`, `10%` to `100%` |
| Overlay Corner | `TrackerCorner` | `bottom-right`, `bottom-left`, `top-right`, `top-left` |
| Overlay Size | `TrackerOverlaySize` | `small`, `large` |
| Map Legend | `TrackerLegend` | `1`, `0` |

## zelda3-tools

Everything to do with the assets besides playing: building them, exporting
them to edit, building them back, and adding languages. Run it with no
arguments for the window, or with a command.

<table>
  <tr>
    <td><img src="docs/screenshots/tools-modding.png" alt="The Modding page, with the ROM, the files folder and the output path filled in, and the log showing a build from edited files" width="480"></td>
    <td><img src="docs/screenshots/tools-languages.png" alt="The Languages page, with German and French ticked and the log showing a build that added them" width="480"></td>
  </tr>
</table>

- **Assets** builds and checks `zelda3_assets.dat`, and identifies ROMs.
- **Modding** exports the overworld and dungeons as YAML, the dialogue as text,
  Link, the font and the sprite sheets as PNG, and the music to look at. Edit
  them and build the asset file from the folder.
- **Languages** extracts the text and font from a translated ROM and builds it
  in beside the English. Set `Language = de` (or whichever) in `zelda3.ini`
  to play in it.

```sh
zelda3-tools build --rom zelda3.sfc --out zelda3_assets.dat
zelda3-tools export --rom zelda3.sfc --out my_mod
zelda3-tools build --from my_mod [--sprites-from-png]
zelda3-tools extract-dialogue --rom german.sfc --out langs
zelda3-tools build --languages de,fr --lang-dir langs
zelda3-tools help
```

Unedited files build exactly the standard asset file, and mistakes are
reported by file and line. Known ROMs: the US, German, French, French Canadian
and European releases, and the Spanish, Polish, Portuguese, Dutch, Swedish and
English Redux fan translations. Only the US ROM builds the asset file. Its
SHA-256 is `66871d66be19ad2c34c927d6b14cd8eb6fc3181965b6e517cb361f7316009cfb`.

## Checking the port

```sh
zig run other/check_ancilla_parity.zig
```

Builds the original C from commit `fbbb3f9` beside the port and compares them.

## What's different from the original

From upstream: widescreen, a sharper world map, pixel shaders, MSU audio, item
switching with L and R and a second item on X, and optional gameplay tweaks
and bug fixes under `[Features]` in `zelda3.ini`.

The second item on X is its own setting here, **Second Item On X** in
Features (`ItemOnX`), apart from L and R switching. Hold X on an item in the
item menu to put it there and press X to use it; while X has one, L and R
pressed together open the map (and close it again), and Select is left to the
save menu. A second box in the HUD shows it: under the item box, or
beside it when the HUD is spread out for widescreen.

Added here: the start menu, the in-game settings, rumble, a widescreen HUD
that moves out to the screen's edges (`WidescreenHud` in `[General]`), a
widescreen camera that keeps the whole wide picture inside the area you're in
instead of stopping where a 4:3 screen would and showing black past its edge,
scroll transitions, Zora's Domain and wide dungeon rooms included, with the
door circle drawn out to the full width (`WidescreenCamera` in `[General]`;
both do nothing at 4:3, where the game plays exactly as the original), a quit
option on the player select screen, `zelda3-tools`, and randomizer seeds, played in the
emulator the port is checked against, with the item tracker.

## Questions nobody asked

**Why Zig?**

Because I love programming in it.

**Why not Rust?**

No.

## Credits

- **snesrev**, who reverse engineered the game and wrote the C
  reimplementation this is ported from, and the upstream contributors:
  FitzRoyX, Keaton Greve, xander-haj, Patrick Mollohan, DaBanana64, Jason
  Shearer, KiritoDev, Nutzzz, UltraHDR, DPS2004, David Girón, Goodlyay, Jarrod
  Makin, Rémy F, Stefan Sperling, Thomas, Timár Csaba, VictorXPDE, hgdagon,
  liffy, makolyte and vanfanel.
- **spannerism**, for the Zelda 3 JP disassembly, and the authors of the other
  disassemblies that named the game's functions and variables.
- **elzo_d**, for [LakeSnes](https://github.com/elzo-d/LakeSnes): the PPU and
  DSP upstream optimized, and the rest of the console that plays randomizer
  seeds.
- The [ALttP Randomizer](https://alttpr.com) team: **sporchia** and the
  [generator](https://github.com/sporchia/alttp_vt_randomizer), whose code says
  where a seed keeps its settings, and **KatDevsGames** and the
  [z3randomizer](https://github.com/KatDevsGames/z3randomizer) contributors,
  whose code says where it keeps what you've found and how its MSU-1 tracks
  work.
- **kattothepast** and the [alttptracker](https://github.com/kattothepast/alttptracker)
  contributors, for which save data flag is which check and where each one
  sits on the map.
- The fan translators behind the
  [Spanish](https://www.romhacking.net/translations/2195/),
  [Polish](https://www.romhacking.net/translations/5760/),
  [Portuguese](https://www.romhacking.net/translations/6530/),
  [Dutch](https://www.romhacking.net/translations/1124/),
  [Swedish](https://www.romhacking.net/translations/982/) and English Redux
  ([1](https://www.romhacking.net/translations/6657/),
  [2](https://www.romhacking.net/hacks/2594/)) versions the tools can read.
- [SDL](https://libsdl.org), [Opus](https://opus-codec.org) by the Xiph.Org
  Foundation, and [stb_image](https://github.com/nothings/stb) by Sean Barrett.
- Nintendo, for the game.

## License

MIT, see `LICENSE.txt`, which keeps the original notices: Copyright (c) 2022
snesrev and Copyright (c) 2021 elzo_d.

Vendored in `third_party/`: Opus 1.3.1 (3-clause BSD, `COPYING` there and in
`LICENSE.txt`), stb_image 2.27 (MIT or public domain), and a generated OpenGL
loader. SDL3 and OpenGL are system dependencies.

No game assets are distributed here.
