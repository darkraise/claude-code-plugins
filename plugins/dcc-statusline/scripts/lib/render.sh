#!/usr/bin/env bash
set -uo pipefail
# Rendering primitives. Out-variables throughout, for the fork reason in color.sh.

printf -v DCC_SEP_DOT    '\302\267'        # U+00B7 middle dot
printf -v DCC_ARROW_UP   '\342\206\221'    # U+2191
printf -v DCC_ARROW_DOWN '\342\206\223'    # U+2193
printf -v DCC_DOT_FILLED '\342\227\217'    # U+25CF
printf -v DCC_DOT_HOLLOW '\342\227\213'    # U+25CB

DCC_RAMP_COLOR=""
DCC_RAMP_BOLD=""
DCC_BAR_ON=""; DCC_BAR_OFF=""; DCC_BAR_ON_N=0; DCC_BAR_OFF_N=0
DCC_ETA=""

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

dcc_bar() { # dcc_bar <pct> <width> -> DCC_BAR_ON/OFF and their cell counts
  local pct="${1:-}" width="${2:-0}" filled i
  DCC_BAR_ON=""; DCC_BAR_OFF=""; DCC_BAR_ON_N=0; DCC_BAR_OFF_N=0
  [ -n "$pct" ] || return 0
  [ "$width" -gt 0 ] 2>/dev/null || return 0
  filled=$(( (pct * width + 50) / 100 ))
  # Clamp both ends so a non-zero reading never looks empty and an incomplete
  # one never looks full.
  [ "$filled" -lt 1 ] && [ "$pct" -gt 0 ] && filled=1
  [ "$filled" -ge "$width" ] && [ "$pct" -lt 100 ] && filled=$(( width - 1 ))
  [ "$filled" -lt 0 ] && filled=0
  [ "$filled" -gt "$width" ] && filled="$width"
  for (( i = 0; i < filled; i++ )); do DCC_BAR_ON="$DCC_BAR_ON$DCC_GLYPH_FILLED"; done
  for (( i = filled; i < width; i++ )); do DCC_BAR_OFF="$DCC_BAR_OFF$DCC_GLYPH_EMPTY"; done
  DCC_BAR_ON_N="$filled"
  DCC_BAR_OFF_N=$(( width - filled ))
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

DCC_SEG_OUT=""
DCC_SEG_CELLS=0
DCC_SEP_CELLS=5
DCC_LINE_OUT=""
DCC_LINE_CELLS=0
DCC_LINE_DROPPED=0
declare -a DCC_SEGS=() DCC_SEGW=()

dcc_sep_cells() { DCC_SEP_CELLS="${1:-0}"; }

dcc_seg_reset() { DCC_SEG_OUT=""; DCC_SEG_CELLS=0; }

dcc_seg_add() { # dcc_seg_add <text> <color> [weight] [cells]
  local text="${1:-}" color="${2:-}" weight="${3:-}" cells="${4:-}"
  [ -n "$text" ] || return 0
  # Character count is only correct for ASCII. Anything else -- an icon, a bar
  # cell, a box glyph -- must state its width, because a double-width icon
  # counts as one character and two cells.
  [ -n "$cells" ] || cells=${#text}
  dcc_paint "$text" "$color" "$weight"
  DCC_SEG_OUT="$DCC_SEG_OUT$DCC_PAINTED"
  DCC_SEG_CELLS=$(( DCC_SEG_CELLS + cells ))
}

dcc_line_reset() { DCC_SEGS=(); DCC_SEGW=(); dcc_seg_reset; }

dcc_line_push() {
  if [ -n "$DCC_SEG_OUT" ]; then
    DCC_SEGS+=("$DCC_SEG_OUT")
    DCC_SEGW+=("$DCC_SEG_CELLS")
  fi
  dcc_seg_reset
}

dcc_line_build() { # dcc_line_build [max-cells] -> DCC_LINE_OUT, _CELLS, _DROPPED
  local max="${1:-0}" i add used=0 sep
  DCC_LINE_OUT=""; DCC_LINE_CELLS=0; DCC_LINE_DROPPED=0
  [ "${#DCC_SEGS[@]}" -gt 0 ] || return 0
  dcc_paint "$DCC_SEP" "${DCC_P_MUTE:-gray}" dim
  sep="$DCC_PAINTED"
  for i in "${!DCC_SEGS[@]}"; do
    add=${DCC_SEGW[$i]}
    [ -n "$DCC_LINE_OUT" ] && add=$(( add + DCC_SEP_CELLS ))
    # Whole segments are dropped rather than any string being cut: a cut could
    # sever an escape sequence and bleed colour across the rest of the row.
    #
    # The scan is greedy, not trailing-only: a segment too wide to fit is
    # skipped and the scan continues, so a later smaller segment can survive an
    # earlier larger one. That is deliberate -- one oversized branch name should
    # not also cost the model and mode flags that would have fitted beside it.
    if [ "$max" -gt 0 ] && [ $(( used + add )) -gt "$max" ]; then
      DCC_LINE_DROPPED=$(( DCC_LINE_DROPPED + 1 ))
      continue
    fi
    [ -n "$DCC_LINE_OUT" ] && DCC_LINE_OUT="$DCC_LINE_OUT$sep"
    DCC_LINE_OUT="$DCC_LINE_OUT${DCC_SEGS[$i]}"
    used=$(( used + add ))
  done
  DCC_LINE_CELLS="$used"
}

printf -v DCC_ELLIPSIS '\342\200\246'   # U+2026, one cell

_dcc_trunc() { # _dcc_trunc <text> <maxlen> -> DCC_TRUNC
  local s="${1:-}" n="${2:-0}"
  DCC_TRUNC="$s"
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  [ "$n" -gt 0 ] || return 0
  [ "${#s}" -gt "$n" ] || return 0
  DCC_TRUNC="${s:0:$n}$DCC_ELLIPSIS"
}
