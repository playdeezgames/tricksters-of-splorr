# Tricksters of SPLORR!! — design plan

Concept 1 from planning: **Con Artist**, a turn-based grid puzzle. Written October 24, 2026. Jam deadline: **Monday, October 26, 2026, 5PM GMT**. Aim to have a shippable build by Sunday night and submit Monday morning at the latest.

## Pitch

You are a street trickster working a small town. Every level is a stage: a marked item to lift, guards and shopkeepers who watch, and a handful of tricks you may use. Nobody gets hurt and nothing fights. You win by **setup, misdirection, payoff**: draw the eyes one way, take the prize the other way, walk out the front door.

The theme (TRICK) is the mechanic, not the skin: every puzzle is "whose attention is where, and for how many turns".

## Core rules

- Grid of tiles, one screen per level (target 16 by 12 tiles of 10 px, scaled up). Walls, doors, the **prize**, the **exit**.
- **Turns.** You act once (move one tile, wait, or use a trick), then every mark acts. All mark behaviour is deterministic and readable.
- **Marks** have a position, a facing and a **sight cone** (the tiles in a straight line ahead, up to 3, stopped by walls and closed doors). The cone is drawn on the floor. Marks follow a fixed patrol (drawn as small arrows) until distracted.
- **Caught** = you end a turn inside a cone while not disguised for that mark. No death, no animation fuss: a one-line reaction and the level rewinds a step. **Undo (Z) and restart (R) are always free**; the design assumes the player experiments.
- **Win** = hold the prize and step on the exit.
- **No randomness anywhere.** That keeps levels solvable by search and the puzzles fair.

## The tricks (taught one or two per few levels)

| Trick | Effect | Cost |
|---|---|---|
| **Coin toss** | Throw a coin to a tile within 4; marks within 5 tiles walk to it and stare at it for 2 turns | limited uses per level |
| **Look over there!** | A mark in line with you (distance up to 3) is forced to turn to face a direction you pick for 1 turn | limited uses |
| **Pickpocket** | From directly behind an adjacent mark (outside its cone) take its key; opens the matching door | free, but needs the position |
| **Disguise** | A hat for N turns: marks of the matching colour ignore you; others still see you | one hat per level, found on the map |

Levels combine them: for example, toss a coin to pull the guard off the corridor, point the second guard at the first, pickpocket the key in the gap.

## Level plan (target 10, cut from the bottom if short on time)

1. Walk to the prize and the exit past one patrolling guard (teaches cones and timing).
2. Wait for the gap; first use of the coin toss.
3–4. Coin toss with two guards; doors.
5–6. Pickpocket the key.
7. Look over there!
8. Disguise.
9. Everything at once on a small screen.
10. **The twist.** The "marks" turn out to be the audience of a stage show and the level is your finale: the exit is the curtain call. Short end screen with the trickster's patter.

## Presentation (this is where Immersion and Cohesion & Craft are won)

- **Stage framing.** Curtains and footlights around the grid, "ACT I" to "ACT III" chapter cards, a narrator line under the grid that reacts to each turn ("Nothing up my sleeve."). Short, written in the trickster's voice.
- **Readable states.** Marks show `?` when investigating and `!` when they spot you; cones tint when you are disguised. Small screen shake on being caught; a flourish when the prize is lifted.
- **Sound.** Synthesised blips via Web Audio in the JS shim (no asset pipeline): coin clink, caught, success, footstep, trick cue. One looping tune only if time allows; otherwise silence plus effects is fine.
- **Art.** Bit Bonanza (CC0, 10 by 10, 1-bit, stated no generative AI) from `bok-of-splorr/splorr/Assets/bit-bonanza/`. Chosen over 1-Bit Kingdom because it is CC0 and the repo can stay public. Needs sheets: People, Creatures, Tools, Clothing, UI, Food, Jewelry. Copy only the sheets used into `assets/`, and copy the licence record. Credit: Bit Bonanza by VEXED, https://v3x3d.itch.io/bit-bonanza.
- **Text.** Public Pixel (see `Tech/Public Pixel Font.md` in the bok) drawn by the JS shim with canvas `fillText`, so Odin never lays out glyphs.

## Architecture

Follows the **Roomba Rights split** from the bok recipe (pure logic, native tests, thin web layer):

```
src/
  game.odin        rules: state, take_turn, tricks, sight, undo stack. No imports from the browser.
  levels.odin      level data (ASCII maps plus mark and patrol tables)
  game_test.odin   #+build !js  — rules tests and the solver
  web.odin         #+build js   — foreign imports, input, step, drawing, sound calls
web/
  index.html       canvas, odin.runWasm with a canvas import object, Web Audio, font loading
tools/  build.sh test.sh ship.sh   (plus shippit.sh wrapper)
assets/ sheets, cover.png (630x500), screenshots/
```

- `press(action)` queues an action and `tick(dt)` animates mark movement (as in Roomba Rights); `take_turn` runs a whole turn at once so tests and the solver skip animation. `dt` is in seconds.
- **State is a small plain struct** (no pointers, no maps), so **undo is just a stack of copies** and the solver can hash states.
- **Solver as a test.** Breadth-first search over (player, marks, items, doors, trick counts, disguise timer) calls the real `take_turn`. Every level must be solvable, and the test records the minimum turns as the **par** shown on the level-select screen. This is the main correctness guarantee while we hand-design under time pressure.
- Input: keyboard first (arrows or WASD move, space waits, 1–4 pick a trick, Z undo, R restart), reading `e.key` before `e.code`. Mouse/touch only if time remains.
- Seed nothing: the game has no randomness.

## Schedule (hours are rough; today is Saturday, October 24)

| When | Goal |
|---|---|
| Sat, first 2 h | Repo skeleton, `tools/build.sh`, canvas shim, a tile map drawn in the browser, player moves |
| Sat evening | `game.odin` rules: marks, cones, patrol, caught, undo; tests; levels 1–3 playable |
| Sun morning | Tricks (coin, pickpocket), doors, solver test, levels 4–6 |
| Sun afternoon | Look over there!, disguise, levels 7–10, narrator text, title and end screens |
| Sun evening | Sound, juice, cover and screenshots, `ITCH_DESCRIPTION.md` with the AI disclosure, `tools/ship.sh` dry run |
| Mon morning | Playtest, fixes, user posts the build by hand; **hard stop for features is Sunday evening** |

## Scope cuts, in order

1. Level 10 twist becomes a plain ending card.
2. Disguise and Look over there! drop out; levels shrink to 8.
3. Music (already optional), then touch input.
4. Never cut: undo, the solver test, the stage framing and narrator, and sound effects. They carry the score more than extra levels do.

## Open decisions for the user

- Title: working name "Tricksters of SPLORR!!" (matches the repo and the SPLORR!! brand).
- Touch support: planned as stretch only.
- Whether the user wants the final twist (level 10) as written.

## Submission checklist

- `ITCH_DESCRIPTION.md` discloses the tools: Claude Code (Claude Sonnet 5.5) wrote the code; Odin; Bit Bonanza assets (CC0, VEXED); Public Pixel font. The user handles the itch page, sets "played in the browser", and uploads by hand. **Nothing is pushed to git or itch unless the user says so.**
