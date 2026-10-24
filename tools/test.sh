#!/usr/bin/env bash
# Native rules tests. One thread: tests share globals and tracking allocators (see the bok Gotchas).
set -euo pipefail
cd "$(dirname "$0")/.."
# -o:speed: a debug build makes the larger solver searches take minutes.
odin test src -o:speed -define:ODIN_TEST_THREADS=1 "$@"
