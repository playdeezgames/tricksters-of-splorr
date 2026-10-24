#!/usr/bin/env bash
# Builds the browser game into build/web. Extra args replace the default -o:speed (use -o:size for shipping).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web/assets
odin build src -target:js_wasm32 -out:build/web/game.wasm "${@:--o:speed}"
cp "$(odin root)/core/sys/wasm/js/odin.js" build/web/
cp web/index.html build/web/
cp -r assets/bit-bonanza assets/bountiful-bits assets/fonts build/web/assets/
echo "built build/web ($(stat -c %s build/web/game.wasm) bytes of wasm)"
