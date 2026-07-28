#!/usr/bin/env bash
set -uo pipefail
# Glyph tables and icon mode resolution. Every glyph is written as an octal
# UTF-8 escape so this file stays pure ASCII: the private-use area does not
# survive every editor, pipe and terminal it might pass through.
#
# Nothing here forks. The cache file is read with the read builtin.

DCC_ICON_MODE="unicode"
DCC_ICON_W=0
DCC_I_DIR=""; DCC_I_GIT=""; DCC_I_MODEL=""; DCC_I_FAST=""
DCC_I_ACCOUNT=""; DCC_I_CTX=""; DCC_I_CLOCK=""; DCC_I_COST=""

_dcc_icons_load() {
  printf -v DCC_I_DIR     '\357\201\273'   # U+F07B folder
  printf -v DCC_I_GIT     '\356\202\240'   # U+E0A0 branch
  printf -v DCC_I_MODEL   '\357\213\233'   # U+F2DB chip
  printf -v DCC_I_FAST    '\357\203\247'   # U+F0E7 bolt
  printf -v DCC_I_ACCOUNT '\357\200\207'   # U+F007 user
  printf -v DCC_I_CTX     '\357\207\200'   # U+F1C0 database
  printf -v DCC_I_CLOCK   '\357\200\227'   # U+F017 clock
  printf -v DCC_I_COST    '\357\205\225'   # U+F155 dollar
}

_dcc_icons_clear() {
  DCC_I_DIR=""; DCC_I_GIT=""; DCC_I_MODEL=""; DCC_I_FAST=""
  DCC_I_ACCOUNT=""; DCC_I_CTX=""; DCC_I_CLOCK=""; DCC_I_COST=""
}

dcc_icons_init() { # -> DCC_ICON_MODE, DCC_ICON_W, DCC_I_*
  local mode="" width="" cm cw home

  # Cache first, so config and environment can override it below.
  home="${DCC_STATUSLINE_HOME:-${HOME:-}/.claude/dcc-statusline}"
  if [ -r "$home/icons.detected" ]; then
    read -r cm cw < "$home/icons.detected" || true
    case "${cm:-}" in nerd|unicode) mode="$cm" ;; esac
    case "${cw:-}" in ''|*[!0-9]*) cw="" ;; esac
    [ -n "${cw:-}" ] && width="$cw"
  fi

  case "${DCC_ICON_MODE_CFG:-auto}" in nerd|unicode) mode="$DCC_ICON_MODE_CFG" ;; esac
  [ "${DCC_ICON_W_CFG:-0}" -gt 0 ] 2>/dev/null && width="$DCC_ICON_W_CFG"
  case "${DCC_ICONS:-}" in nerd|unicode) mode="$DCC_ICONS" ;; esac

  [ -n "$mode" ] || mode="unicode"
  DCC_ICON_MODE="$mode"

  if [ "$mode" = "nerd" ]; then
    # Two cells is the safer default: a "Nerd Font" draws icons at natural
    # width, and only the "Mono" variant forces them to one.
    [ -n "$width" ] || width=2
    DCC_ICON_W="$width"
    _dcc_icons_load
  else
    DCC_ICON_W=0
    _dcc_icons_clear
  fi
  return 0
}
