# Itch.io page text

The page: https://thegrumpygamedev.itch.io/tricksters-of-splorr (live; slug confirmed October 27, 2026)
Made for All Tools Allowed #3 (https://itch.io/jam/all-tools-allowed-3), theme TRICK.
This file is pasted in by hand; nothing here is published by the repo.

## Short description

A small stage show of sleight and nerve: toss a coin, lift a key, turn a guard's head, borrow a hat. Ten puzzles, no fighting.

## Paste this as the page description

Welcome to the show. You are a trickster, and every level is a stage with a prize on it, an exit across it, and guards who would very much like to see you.

**Nobody gets hurt. Nobody even gets close.** Guards watch the three tiles in front of them, and you win by working out where their eyes are going to be. Every turn you act once, then every guard acts once, and what they do is never random: you can see their route, watch their cone, and plan.

**Four tricks, each taught by a level that cannot be won without it:**

- **Coin toss (T, then a direction).** A guard who hears the coin walks over to look at it, stares for two turns, then walks back to his post.
- **Pickpocket (P).** Lift a key from a guard who is not looking at you, and open the locked door it belongs to.
- **Look over there! (L, then a direction).** Point past a guard and he turns his head that way for three turns.
- **Disguise.** A hat fools guards of its own colour, and only that colour, for six turns.

Ten levels in five acts, and each one is a puzzle with a shortest possible solution. The game shows you its "par" (the fewest turns that wins), and you will want to beat your own score. **Undo (Z) is free and unlimited, and so is restarting (R)**, so try things. A level that looks impossible is probably waiting for the right trick.

**Controls:** arrow keys (or WASD) move, Space waits, T coin, L look, P pickpocket, Z undo, R restart, M mute. Keyboard needed; there is no touch control yet.

There is a small surprise in the last act. Take a bow when it comes.

**Credits and how it was made.** This game was made for a jam that allows any tool, and it used one heavily: the code (Odin compiled to WebAssembly, no engine), the levels, the text and the tests were written with Claude Code (Claude Sonnet 5.5) from my design decisions and playtesting. A solver written for the tests checks that every level can be won and that the par shown on screen is the true minimum. The sprites are from Bit Bonanza and Bountiful Bits by VEXED (CC0, https://v3x3d.itch.io/bit-bonanza and https://v3x3d.itch.io/bountiful-bits). The font is Public Pixel by GGBotNet (CC0). The sound effects are synthesized in the browser as you play, with no recorded samples, and there is no music. The stage dressing (curtains, valance, footlights, the title and end screens) was drawn in code by Claude, and the cover and screenshots were produced by scripts from the game's own art. No image or music generators were used.

## Notes (not for the page)

- The page exists and is published. `tools/ship.sh` pushes to `thegrumpygamedev/tricksters-of-splorr:html`, and only with `--push`; the live channel is `html` (version 3 at last check), so do not rename it.
- On the page's Edit game screen: set "Kind of project" to HTML, tick "This file will be played in the browser" on the html upload, and use the full-screen embed (the canvas scales to fill the window). Submit the page to the jam from the jam page after the upload is processed.
- The cover is `assets/cover.png` (630 by 500, drawn by `tools/make_cover.py`); screenshots are in `assets/screenshots/` (made by `tools/make_screenshots.sh`, which drives the page's QA parameters; the end-screen shot shows a perfect run).
- The AI-use paragraph is a draft in the user's voice. Confirm the wording, in particular "from my design decisions and playtesting", and fill in the jam's AI-tools disclosure on the submission to match. The jam requires a disclosure, or the entry is not accepted.
- The page's art credits come from the vault notes on each pack (both CC0, both say no generative AI was used); there is no licence file in the packs themselves.
- The finale twist is deliberately not in the short description or the screenshots' captions.
- QA parameters (not mentioned on the page): `?level=N`, `&screen=title|act|play|end`, `&keys=<moves>` in the solver's notation (see `web/index.html`).
