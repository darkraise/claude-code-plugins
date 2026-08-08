#!/usr/bin/env bash
set -uo pipefail
# Box drawing. Every row this file produces must be exactly DCC_FRAME_COLS cells
# wide; a miscount by one leaves a ragged right wall down the whole box.
#
# tput cannot help here: Claude Code captures the script's output rather than
# attaching it to a terminal, so the width arrives in COLUMNS instead.

DCC_FRAME_MIN=48

printf -v DCC_BOX_TL '\342\225\255'   # U+256D
printf -v DCC_BOX_TR '\342\225\256'   # U+256E
printf -v DCC_BOX_BL '\342\225\260'   # U+2570
printf -v DCC_BOX_BR '\342\225\257'   # U+256F
printf -v DCC_BOX_H  '\342\224\200'   # U+2500
printf -v DCC_BOX_V  '\342\224\202'   # U+2502

DCC_FRAME_ON=0
DCC_FRAME_COLS=0
DCC_FRAME_BUDGET=0
DCC_FRAME_OUT=""
DCC_WIDTH_COLS=0

dcc_frame_init() { # -> DCC_FRAME_ON, DCC_FRAME_COLS, DCC_WIDTH_COLS
  local cols="${COLUMNS:-}" margin="${DCC_FRAME_MARGIN:-4}"
  DCC_FRAME_ON=0; DCC_FRAME_COLS=0; DCC_WIDTH_COLS=0
  case "$cols" in ''|*[!0-9]*) return 0 ;; esac
  # COLUMNS reports the terminal, but the status line is drawn inside a region
  # narrower than that, so drawing to the full width gets the right end cut off.
  #
  # Measured by rendering a column ruler through the real status line at
  # COLUMNS=280: the host indents the row by 2 columns and then truncates the
  # tail with an ellipsis, leaving 276 usable columns. Hence a default margin of
  # 4 rather than 2 -- two for the indent, two so the last cell is never written.
  case "$margin" in ""|*[!0-9]*) margin=4 ;; esac
  [ "$cols" -gt "$margin" ] || return 0
  cols=$(( cols - margin ))
  # The usable width is known now, whatever is decided about the box below.
  # Fitting a line depends on knowing the width; drawing a frame depends on
  # having room for one. Conflating the two cost every terminal under 52
  # columns the whole responsive feature -- it knew its width and threw it away.
  DCC_WIDTH_COLS="$cols"
  [ "${DCC_FRAME_MODE:-auto}" = "none" ] && return 0
  [ "$cols" -ge "$DCC_FRAME_MIN" ] || return 0
  DCC_FRAME_COLS="$cols"
  DCC_FRAME_ON=1
}

dcc_frame_budget() { # -> DCC_FRAME_BUDGET, the cells a content line may use
  if [ "$DCC_FRAME_ON" -eq 1 ]; then
    DCC_FRAME_BUDGET=$(( DCC_FRAME_COLS - 4 ))
  else
    DCC_FRAME_BUDGET="$DCC_WIDTH_COLS"
  fi
}

_dcc_rep() { # _dcc_rep <count> <char> -> DCC_REP
  local n="${1:-0}" ch="$2" i
  DCC_REP=""
  [ "$n" -gt 0 ] 2>/dev/null || return 0
  for (( i = 0; i < n; i++ )); do DCC_REP="$DCC_REP$ch"; done
}

dcc_frame_top() { # dcc_frame_top <title> <icon> <icon-cells> -> DCC_FRAME_OUT
  local title="${1:-}" icon="${2:-}" iw="${3:-0}" used rule
  local tint="${DCC_ACCOUNT_COLOR:-}"
  DCC_FRAME_OUT=""
  # corner + rule + space + [icon + space] + title + space + rule(n) + corner
  used=$(( 5 + ${#title} ))
  [ -n "$icon" ] && used=$(( used + iw + 1 ))
  rule=$(( DCC_FRAME_COLS - used ))
  # A title wider than the terminal would make the rule negative, so it is
  # truncated rather than allowed to push the corner off the row.
  if [ "$rule" -lt 0 ]; then
    title="${title:0:$(( ${#title} + rule ))}"
    used=$(( 5 + ${#title} ))
    [ -n "$icon" ] && used=$(( used + iw + 1 ))
    rule=$(( DCC_FRAME_COLS - used ))
    [ "$rule" -lt 0 ] && rule=0
  fi
  dcc_paint "$DCC_BOX_TL$DCC_BOX_H " "$tint"
  DCC_FRAME_OUT="$DCC_PAINTED"
  if [ -n "$icon" ]; then
    dcc_paint "$icon " "$tint"
    DCC_FRAME_OUT="$DCC_FRAME_OUT$DCC_PAINTED"
  fi
  dcc_paint "$title" "$tint" bold
  DCC_FRAME_OUT="$DCC_FRAME_OUT$DCC_PAINTED"
  _dcc_rep "$rule" "$DCC_BOX_H"
  dcc_paint " $DCC_REP$DCC_BOX_TR" "$tint"
  DCC_FRAME_OUT="$DCC_FRAME_OUT$DCC_PAINTED"
}

dcc_frame_row() { # dcc_frame_row <built-line> <cells> -> DCC_FRAME_OUT
  local body="${1:-}" cells="${2:-0}" pad
  local tint="${DCC_ACCOUNT_COLOR:-}"
  pad=$(( DCC_FRAME_COLS - 4 - cells ))
  [ "$pad" -lt 0 ] && pad=0
  _dcc_rep "$pad" " "
  dcc_paint "$DCC_BOX_V " "$tint"
  DCC_FRAME_OUT="$DCC_PAINTED$body"
  dcc_paint " $DCC_BOX_V" "$tint"
  DCC_FRAME_OUT="$DCC_FRAME_OUT$DCC_REP$DCC_PAINTED"
}

dcc_frame_bottom() { # -> DCC_FRAME_OUT
  local tint="${DCC_ACCOUNT_COLOR:-}"
  _dcc_rep $(( DCC_FRAME_COLS - 2 )) "$DCC_BOX_H"
  dcc_paint "$DCC_BOX_BL$DCC_REP$DCC_BOX_BR" "$tint"
  DCC_FRAME_OUT="$DCC_PAINTED"
}
