#!/usr/bin/env bash
# Writes assets/screenshots/*.png with headless Chrome through the page's QA parameters
# (?level=N&screen=title|act|play|end&keys=<moves>; see web/index.html). Run tools/build.sh first.
# The move strings are prefixes of the solver's winning strings (tools/test.sh logs them).
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-8117}"
python3 -m http.server -d build/web "$PORT" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1
mkdir -p assets/screenshots
shot() { # name, query
  google-chrome --headless=new --no-sandbox --disable-gpu --hide-scrollbars --window-size=800,600 \
    --virtual-time-budget=6000 --screenshot="assets/screenshots/$1.png" "http://localhost:$PORT/?$2" >/dev/null 2>&1
  echo "assets/screenshots/$1.png"
}
shot 01-title "screen=title"
shot 02-act "level=1&screen=act"
shot 03-coin "level=2&keys=DDRRRrDRD"
shot 04-hat "level=5&keys=DDDDRRRRDRRR"
shot 05-finale "level=10&keys=uRRUUUUpRRRURR>DRRDDDRUUURRRUUUUDDDDDDDDD"
shot 06-end "screen=end"
