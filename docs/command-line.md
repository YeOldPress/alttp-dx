# Command line, debug keys and checking

For working on ALTTP-DX rather than playing it.

## Options

- `zelda3 --config <path>` uses another ini.
- `zelda3 --build-assets` builds the asset file and exits.
- `zelda3 --data-dir` prints where the ini, assets and saves live.
- `zelda3 --pad-info` says what each connected controller is, what its face
  buttons are labeled and do, and whether it has a rumble motor.
- `zelda3 <rom>` runs the original machine code alongside the game and
  compares RAM every frame. This is how the game is verified.
- `zelda3 --render <chapter> <script> <out.bmp>` plays a button script from a
  snapshot in `saves/ref` with no window and saves the last frame. `s<n>` in
  place of the chapter starts from your own quick-save slot n instead. A script
  is steps of frames and the buttons held for them: `60,1:start,20,1:select,30`.
  `CRT=arcade` (or any look) draws that frame through the real CRT shaders,
  with the look's own curve and bezel, in a window that never shows, and
  `SCALE=n` makes it n pixels to a SNES pixel (3 unless said). It needs SDL's
  GPU renderer. This is how the README's CRT pictures are made.
  `ENTRANCE=n` goes in through dungeon entrance n before the script starts
  and prints the room it lands in, as a way into any room. `POKE=addr:value`
  (comma-separated, `0x` for hex) writes bytes of the game's RAM after that,
  to set something up: `POKE=0x202:6` puts the fire rod in Link's hands.
  With `-` for the chapter, `ROOM=n` boots from power-on straight into
  dungeon entrance n on a made-up file, no snapshot needed (4 is Hyrule
  Castle's torchlit hall). `ROOMID=n` with it moves over to room n of that
  dungeon (`ROOM=53 DARK=1 ROOMID=0x14` is Turtle Rock's lava pipe room;
  `DARK=1` makes it a Dark World file). `BIRD=k` boots onto the overworld
  where the flute's bird drops Link instead (0 to 7; 7 is Lake Hylia), and
  `OUTSIDE=n` where dungeon room n's exit comes out, or `SPOT=lake` out in
  Lake Hylia by the island. `NEWFILE=1` makes the made-up file a brand-new
  one instead, as naming a file makes it; with `RANDO=n` it's set up for the
  randomizer's Open mode, so on its own it stops at the menu of places to
  start (`NEWFILE=1|RANDO=5` with `200,5:a,150,120:down,150` picks Link's
  House and walks out the door), and with `ROOM`, `BIRD` or `OUTSIDE` it
  starts there on that new file. `RECEIVE=item@frame` hands Link an item
  that many frames into the script, as an NPC would, or as a chest would
  with `item@frame:chest`: an item receipt number (`0x50`) or a randomizer
  item's name (`progressive_sword`, worked out from what Link has then), up
  to eight separated by `;`. It's a way to see what a receipt shows and does
  (`ROOM=4|RANDO=5|RECEIVE=0x4e@100:chest` with `215` is half magic and
  its HUD). And
  `SET="Graphics.Particles=0;General.ExtendedAspectRatio=16:9"` overrides
  settings from the ini for that picture.
- `zelda3 --preview "<options>" <script> <out.bmp>` is the same from
  power-on with the options in one argument instead of the environment,
  `ROOM=4|CRT=off|SCALE=2|SET=Graphics.DynamicLighting=0`. It's how the start
  menu takes its pictures of the graphics settings, into `previews/` beside
  the ini.
- `zelda3 --menu-shot <screen> <out.bmp> [seed]` draws a start menu screen
  (`main`, `settings`, `features`, `controls`, `achievements`, `hub`,
  `alttpr`, `details`) with no window. `LIST_ROW=n` picks a row on the lists, `INFO=1` opens the
  info box, `CTL_ROW=n` and `CAPTURE=1` set up the Controls screen.
- `zelda3 seed.sfc` opens a randomizer seed on its page in the start menu.
- `zelda3 --seed-info seed.sfc` prints what a seed says about itself,
  spoilers included, without starting anything.
- `zelda3 --emu-render <seed> <script> <out.bmp>` plays a script in the
  emulator and saves the last frame with the tracker. `TRACKER=overlay` (or
  `window`, `off`), `WIDE=96` and `TRACKER_OPTS="Size=compact;Maps=current"`
  change what's drawn.

## Debug keys

| Key | Action |
| --- | --- |
| Tab | Turbo |
| F1-F10 | Load snapshot (Shift saves, Ctrl replays) |
| W | Fill health and magic |
| Ctrl+E | Walk through walls |
| Ctrl+R | Reset |

`zelda3.ini` lists the rest, and every key and gamepad button can be rebound
there.

## Checking against the original

```sh
zig build test
zig run other/check_ancilla_parity.zig
```

The second builds the original C from commit `fbbb3f9` beside ALTTP-DX and
compares them.
