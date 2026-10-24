#!/usr/bin/env bash
# Native rules tests. One thread: tests share globals and tracking allocators (see the bok Gotchas).
set -euo pipefail
cd "$(dirname "$0")/.."
odin test src -define:ODIN_TEST_THREADS=1 "$@"
