#!/usr/bin/env bash
# Runs every test file. Exits non-zero if any file fails.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$HERE"/*.test.sh; do
  printf '\n=== %s ===\n' "$(basename "$t")"
  bash "$t" || rc=1
done
exit "$rc"
