#!/usr/bin/env bash
set -uo pipefail
# Rendering primitives. Out-variables throughout, for the fork reason in color.sh.

DCC_RAMP_COLOR=""
DCC_RAMP_BOLD=""
DCC_BAR=""
DCC_ETA=""
DCC_JOINED=""
DCC_JOIN_EMPTY=1

dcc_ramp() { # dcc_ramp <pct> -> DCC_RAMP_COLOR, DCC_RAMP_BOLD
  local pct="${1:-}" stop at rest
  DCC_RAMP_COLOR=""; DCC_RAMP_BOLD=""
  [ -n "$pct" ] || return 0
  # DCC_RAMP is sorted ascending, so the last stop at or below pct wins.
  for stop in $DCC_RAMP; do
    at="${stop%%:*}"
    rest="${stop#*:}"
    [ "$pct" -ge "$at" ] 2>/dev/null || continue
    DCC_RAMP_COLOR="${rest%%:*}"
    DCC_RAMP_BOLD="${rest#*:}"
  done
}

dcc_bar() { # dcc_bar <pct> <width> -> DCC_BAR
  local pct="${1:-}" width="${2:-0}" filled i out=""
  DCC_BAR=""
  [ -n "$pct" ] || return 0
  [ "$width" -gt 0 ] 2>/dev/null || return 0
  filled=$(( (pct * width + 50) / 100 ))
  # Clamp both ends so a non-zero reading never looks empty and an incomplete
  # one never looks full.
  [ "$filled" -lt 1 ] && [ "$pct" -gt 0 ] && filled=1
  [ "$filled" -ge "$width" ] && [ "$pct" -lt 100 ] && filled=$(( width - 1 ))
  [ "$filled" -lt 0 ] && filled=0
  [ "$filled" -gt "$width" ] && filled="$width"
  for (( i = 0; i < width; i++ )); do
    if [ "$i" -lt "$filled" ]; then out="$out$DCC_GLYPH_FILLED"; else out="$out$DCC_GLYPH_EMPTY"; fi
  done
  DCC_BAR="[$out]"
}

dcc_eta() { # dcc_eta <seconds-until-reset> -> DCC_ETA
  local s="${1:-}" d h m
  DCC_ETA=""
  [ -n "$s" ] || return 0
  if [ "$s" -le 0 ] 2>/dev/null; then DCC_ETA="now"; return 0; fi
  d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf -v DCC_ETA '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf -v DCC_ETA '%dh%dm' "$h" "$m"
  else                     printf -v DCC_ETA '%dm' "$m"
  fi
}

dcc_join_reset() { DCC_JOINED=""; DCC_JOIN_EMPTY=1; }

dcc_join_add() { # dcc_join_add <colorspec> <text>
  local spec="${1:-}" text="${2:-}" color bold
  [ -n "$text" ] || return 0
  if [ -n "$spec" ]; then
    color="${spec%% *}"
    bold="${spec#* }"
    [ "$bold" = "$spec" ] && bold=""
  else
    color="$DCC_ACCOUNT_COLOR"; bold=""
  fi
  if [ "$DCC_JOIN_EMPTY" -eq 0 ]; then
    dcc_paint "$DCC_SEP" "$DCC_ACCOUNT_COLOR"
    DCC_JOINED="$DCC_JOINED$DCC_PAINTED"
  fi
  dcc_paint "$text" "$color" "$bold"
  DCC_JOINED="$DCC_JOINED$DCC_PAINTED"
  DCC_JOIN_EMPTY=0
}
