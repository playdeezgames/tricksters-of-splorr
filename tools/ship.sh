#!/usr/bin/env bash
# Prepares the itch.io build: tests, an optimized web build, a zip. Pushes ONLY with --push. Never commits, never deletes
# anything but the old zip. Usage: tools/ship.sh [--push]
set -euo pipefail
cd "$(dirname "$0")/.."
# The page: https://thegrumpygamedev.itch.io/tricksters-of-splorr (the slug is a guess until the page exists: check it).
TARGET="thegrumpygamedev/tricksters-of-splorr:html"
ZIP="build/tricksters-of-splorr-html5.zip"

tools/test.sh
tools/build.sh -o:size
rm -f "$ZIP"
(cd build/web && zip -q -9 -r "../tricksters-of-splorr-html5.zip" .)
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1)); wasm $(du -h build/web/game.wasm | cut -f1)"
unzip -l "$ZIP" | tail -5

if [ "${1:-}" = "--push" ]; then
	if [ -n "$(git status --porcelain)" ]; then echo "note: the working tree has uncommitted changes; what is pushed is the working tree, not a commit"; fi
	butler push "$ZIP" "$TARGET"
	echo "pushed to $TARGET. It goes live after itch.io processes it; check: butler status $TARGET"
else
	echo "not pushed (run tools/ship.sh --push when you want it live; the target is $TARGET)"
fi
