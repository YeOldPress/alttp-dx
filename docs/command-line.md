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
