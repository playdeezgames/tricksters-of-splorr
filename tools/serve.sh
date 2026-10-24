#!/usr/bin/env bash
# Serves build/web over http. Port defaults to 8123 (8765 is often taken by another project).
cd "$(dirname "$0")/.."
exec python3 -m http.server -d build/web "${1:-8123}"
