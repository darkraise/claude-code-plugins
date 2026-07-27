#!/usr/bin/env bash
set -uo pipefail
# Shared assertions. Every *.test.sh sources this, then calls finish at the end.
pass=0 fail=0

check() { # check <label> <got> <want>
  if [ "$2" = "$3" ]; then
    printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else
    printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  fi
}

finish() { printf '\n%d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }

# Test-only: strips SGR sequences so assertions compare visible text.
strip_ansi() { sed -E $'s/\033\\[[0-9;]*m//g'; }
