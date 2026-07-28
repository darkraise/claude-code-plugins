#!/usr/bin/env bash
set -uo pipefail
# Named colors to ANSI. Every function assigns a global rather than printing:
# capturing output would require $(...), and each fork costs ~10-20ms under
# MSYS2, which the render path cannot afford.

DCC_ESC=$'\033'
DCC_C=""
DCC_R="$DCC_ESC[0m"
DCC_PAINTED=""

dcc_reset() { DCC_R="$DCC_ESC[0m"; }

dcc_color() { # dcc_color <name> [weight: ''|bold|dim] -> DCC_C
  local name="${1:-}" weight="${2:-}" code=""
  case "$name" in
    black)     code=0   ;;
    red)       code=9   ;;
    green)     code=10  ;;
    yellow)    code=11  ;;
    blue)      code=12  ;;
    magenta)   code=13  ;;
    cyan)      code=14  ;;
    white)     code=15  ;;
    orange)    code=208 ;;
    gray|grey) code=245 ;;
    ''|none)   DCC_C=""; return 0 ;;
    *[!0-9]*)  DCC_C=""; return 0 ;;
    *)         code="$name" ;;
  esac
  case "$weight" in
    bold) DCC_C="$DCC_ESC[1;38;5;${code}m" ;;
    dim)  DCC_C="$DCC_ESC[2;38;5;${code}m" ;;
    *)    DCC_C="$DCC_ESC[38;5;${code}m"   ;;
  esac
}

dcc_paint() { # dcc_paint <text> <color-name> [weight: ''|bold|dim] -> DCC_PAINTED
  dcc_color "${2:-}" "${3:-}"
  if [ -z "$DCC_C" ]; then DCC_PAINTED="$1"; else DCC_PAINTED="$DCC_C$1$DCC_R"; fi
}
