# Randomizer

ALTTP-DX plays seeds from [alttpr.com](https://alttpr.com), the A Link to the
Past randomizer, with an item tracker that follows along by itself.

## Getting a seed going

1. On alttpr.com, generate a seed from the **Japanese 1.0 ROM** (MD5
   `03a63945398191337e896e5771f77173`), the one the randomizer is built on,
   and save the `.sfc` it gives you.
2. Start the game, press **Randomizer** (under Play), then **ALTTPR.COM
   Randomizer**. **Built-In Randomizer** beside it is greyed out: that one is
   coming soon.
3. Drag the seed onto the window. Or skip steps 2 and 3 with `zelda3 seed.sfc`,
   which opens straight on the seed.
4. Press **Play This Seed**, or Start.

The main menu's drag-and-drop is only for the US ROM that builds the game's
assets. A seed dropped there gets pointed at the Randomizer page instead.

## The ALTTPR.COM page

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

## How a seed plays

A seed rewrites too much of the game's code for ALTTP-DX's own engine to play
it, so it runs in a SNES emulator instead: the one the engine is verified
against (LakeSnes, by way of upstream), put back together as a whole console.
It plays the ROM exactly as the randomizer built it, and the page says so up
front.

- **Saves** go next to the seed as `seed.srm`, written as the game saves.
- **Off for seeds:** snapshots, cheats and Turbo. It's a race.
- **Still there:** fullscreen, pause, window size, volume, and Ctrl+R to
  reset. T moves the tracker between its places.

A few of the extras come along, because they only watch the game:

- **Rumble**, on by default.
- **Widescreen**, off by default and marked experimental. Rooms and areas show
  as far as they go, but outdoors the edges can briefly show stale tiles while
  scrolling, and enemies still vanish at the original screen edge.
- **MSU-1 audio**, below.

## MSU-1 for seeds

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

## The tracker

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

## Options

All on the ALTTPR.COM page, and kept in `[Randomizer]` in `zelda3.ini`, apart
from the normal game's settings.

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
