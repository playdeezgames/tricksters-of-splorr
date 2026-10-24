# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

Planning phase. The game is a turn-based stealth puzzle ("Con Artist": distract guards, lift the prize, reach the exit); the design, level plan, architecture and schedule are in `docs/DESIGN.md`, which is the source of truth. There is no source, build script or test yet. Update this file as the structure is decided and created. Do not invent commands: the ones below come from the bok recipe and have not been run in this repo.

## The jam

[All Tools Allowed #3](https://itch.io/jam/all-tools-allowed-3) (Critics Arcade AI game jam). Theme: **TRICK** (magic, prank, trick-or-treat, stunt; free interpretation).

- Submissions close **Mon, October 26, 2026, 5PM GMT** (72 hour window that opened October 23). Community and judge rating runs to November 2; winners November 4.
- Judged 1 to 5 on **Immersion, Player Experience, Cohesion & Craft, Theme**. Only participants and invited judges vote.
- Any tool is allowed, including generative AI, but the **itch page must disclose the tools used** (say "none" if none) or the entry is not accepted. Put the disclosure in `ITCH_DESCRIPTION.md` (see Release layout).
- A browser build is encouraged, so ship HTML5. No trademarked or infringing content. Zero-effort, single-prompt entries may be removed, so aim for a polished, complete experience.

## Stack

Odin compiled to `js_wasm32` with Odin's own runtime (`odin.js`, no emscripten), drawing to a plain **2D canvas through a JS shim, not WebGL** (WebGL fails on the user's Chrome and in the in-app browser pane). Toolchain: `odin` (nightly `dev-2026-07`) is on PATH at `~/.local/bin/odin`; `wasm-ld` is installed; `python3` is available; `emcc` and `node` are not on PATH.

Commands (the wasm must be served over http, not `file://`):

```bash
tools/build.sh              # builds build/web (game.wasm, odin.js, index.html, assets); pass -o:size to ship
tools/serve.sh 8123         # serves build/web
```

Layout so far: `src/game.odin` (pure rules, `take_turn`), `src/levels.odin` (ASCII maps), `src/web.odin` (`#+build js`: canvas imports, input, `step`), `web/index.html` (canvas shim, sheet loading; its `SHEETS` order must match the `Sheet` enum in `web.odin`). The canvas is 400x300 logical pixels, scaled by a whole number; sprites are 10 px cells drawn at 20 px, white ink tinted by the page.

Native tests (once they exist): `odin test src -define:ODIN_TEST_THREADS=1`. Run one test with `-define:ODIN_TEST_NAMES=pkg.test_name`.

## The bok (shared knowledge base)

`/home/yermom/git/bok-of-splorr` (an Obsidian vault, added as a working directory; read-only reference, and its own `CLAUDE.md` governs edits there). Read before writing code:

- `splorr/Tech/Odin wasm recipe.md`: the frame loop, input, canvas shim, and several architecture variants (pure core plus platform layer, shared framebuffer, DOM-driven, Web Audio/images from the page). Fortune Hunter and Murder Hobo are the closest templates for a framebuffer game.
- `splorr/Gotchas.md`: Odin and wasm traps (no `core:os` on wasm, imports not allowed inside `when`, constant arrays cannot take runtime indexes, `where`/`cast` are keywords, an unbounded loop freezes the whole tab so cap every retry loop, read `e.key` before `e.code`, seed the RNG in `main`).
- `splorr/Tech/Release standard.md` and `Shipping to itch.io.md`.
- `splorr/Assets/` and `Tech/*font*.md`, `Tech/*tileset*.md`: reusable fonts and tilesets with licence notes. `Assets/1bit-kingdom/*` may only live in a private repo; check visibility before using or pushing it.

## Architecture conventions to follow (from the recipe)

- Keep all rules in a package with **no browser imports** so it compiles and tests natively. Put everything with `foreign import` and `core:sys/wasm/js` in files marked `#+build js`, and test files `#+build !js` (`core:testing` pulls in `core:os`, which panics on wasm).
- Pass clock and randomness into the logic as arguments so tests can force outcomes.
- The module name in `foreign import canvas "canvas"` must match the key given to `odin.runWasm("game.wasm", log, { canvas: {...} }, memory)`. Pass your own `WasmMemoryInterface` as the fourth argument when the shim must read wasm memory or call exports.
- Keep an exported `step` even for event-driven games, or `odin.js` ends the program right after `main`.
- Event callbacks and exports need `context = ...` set before using anything that needs a context.

## Standing rules (from the bok)

- **Never `git push`, run `shippit.sh --push`, or `butler push` unless the user explicitly says so.** If "push" is ambiguous, ask whether it means git or itch.
- Follow the Release standard layout in this repo: `ITCH_DESCRIPTION.md` (page URL, jam, "pasted in by hand", short description, body, AI-use disclosure), `assets/cover.png` (630x500), `assets/screenshots/01-title.png` etc., `devlog/YYYYMMDD/devlog.md`, `tools/build.sh`, `tools/test.sh`, `tools/ship.sh` (tests, build, zip `build/web` with `index.html` at the root, push only with `--push`, never `git add`/commit), and a one-line `shippit.sh` wrapper (`exec "$(dirname "$0")/tools/ship.sh" "$@"`). Copy `~/git/FortuneHunter/tools/ship.sh` as the template if that repo exists on this machine; it was not present at planning time. New itch channel name is `html`.
- If a session meets the ROM `Font8x8.png`, ask the user before replacing it (offer DINOBYTE, then Public Pixel).
- Steam is out of scope for this game.
- Do not describe or "fix" deliberate design as a problem.

## Tooling notes

- Port 8765 is often taken by another project's static server; pick another port and check the first response.
- Use `fuser -k PORT/tcp` to stop a server; `pkill -f "http.server PORT"` inside a tool call kills the tool's own shell.
- In-app browser pane screenshots can lag one step; take a second one before concluding a key press did nothing. Headless Chrome screenshots of a 2D-canvas game work: `google-chrome --headless=new --no-sandbox --disable-gpu --window-size=800,800 --virtual-time-budget=4000 --screenshot=out.png URL`.
