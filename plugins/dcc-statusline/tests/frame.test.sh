#!/usr/bin/env bash
# The frame. Every drawn row must measure exactly COLUMNS cells; if it does not,
# the right wall is ragged and the whole box looks broken.
set -uo pipefail
export LC_ALL=C.UTF-8
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/color.sh"
source "$HERE/../scripts/lib/render.sh"
source "$HERE/../scripts/lib/frame.sh"

DCC_ACCOUNT_COLOR="cyan"
DCC_P_MUTE="gray"
DCC_SEP=" | "
dcc_sep_cells 3

# The margin is exercised in its own block at the end of this file. Everything
# before it tests the row arithmetic, which is clearer to read when the drawn
# width and the reported width are the same number.
DCC_FRAME_MARGIN=0

# --- enablement ---------------------------------------------------------------
DCC_FRAME_MODE="auto"; COLUMNS=100; dcc_frame_init
check "auto with a usable width draws the box" "$DCC_FRAME_ON" "1"
check "auto adopts the reported width"         "$DCC_FRAME_COLS" "100"

COLUMNS=""; dcc_frame_init
check "auto without COLUMNS falls back" "$DCC_FRAME_ON" "0"

COLUMNS="wide"; dcc_frame_init
check "auto with a non-numeric COLUMNS falls back" "$DCC_FRAME_ON" "0"

COLUMNS=40; dcc_frame_init
check "auto below the minimum falls back" "$DCC_FRAME_ON" "0"

COLUMNS=48; dcc_frame_init
check "auto at the minimum draws the box" "$DCC_FRAME_ON" "1"

DCC_FRAME_MODE="none"; COLUMNS=100; dcc_frame_init
check "none never draws the box" "$DCC_FRAME_ON" "0"

DCC_FRAME_MODE="box"; COLUMNS=""; dcc_frame_init
check "box without a width still cannot draw" "$DCC_FRAME_ON" "0"

# --- row widths ---------------------------------------------------------------
DCC_FRAME_MODE="auto"

for cols in 48 60 72 90 110 150; do
  for iw in 1 2; do
    COLUMNS="$cols"; DCC_ICON_W="$iw"; dcc_frame_init; dcc_frame_budget

    printf -v icon '\357\200\207'
    dcc_frame_top "someone@example.com" "$icon" "$iw"
    dcc_cells "$DCC_FRAME_OUT"
    check "top rule is $cols cells at icon width $iw" "$DCC_CELLS" "$cols"

    dcc_line_reset
    dcc_seg_add "alpha" cyan; dcc_line_push
    dcc_seg_add "beta"  cyan; dcc_line_push
    dcc_line_build "$DCC_FRAME_BUDGET"
    dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
    dcc_cells "$DCC_FRAME_OUT"
    check "content row is $cols cells at icon width $iw" "$DCC_CELLS" "$cols"

    dcc_frame_bottom
    dcc_cells "$DCC_FRAME_OUT"
    check "bottom rule is $cols cells at icon width $iw" "$DCC_CELLS" "$cols"
  done
done

# --- a full line still fits ---------------------------------------------------
COLUMNS=60; DCC_ICON_W=2; dcc_frame_init; dcc_frame_budget
dcc_line_reset
# Ten cells per segment, so eight of them plus their separators come to 101
# cells against a budget of 56 and the line genuinely overflows. Four-cell
# segments total only 53 and would fit, leaving this block asserting nothing.
for n in 1 2 3 4 5 6 7 8; do dcc_seg_add "segment-0$n" cyan; dcc_line_push; done
dcc_line_build "$DCC_FRAME_BUDGET"
dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
dcc_cells "$DCC_FRAME_OUT"
check "an overflowing line still yields a 60-cell row" "$DCC_CELLS" "60"
check "and something was dropped to achieve it" \
  "$([ "$DCC_LINE_DROPPED" -gt 0 ] && printf yes || printf no)" "yes"

# --- a title longer than the terminal -----------------------------------------
COLUMNS=48; DCC_ICON_W=0; dcc_frame_init
printf -v icon '\357\200\207'
dcc_frame_top "an-extremely-long-account-address@somewhere.example.com" "" 0
dcc_cells "$DCC_FRAME_OUT"
check "an over-long title still yields a 48-cell rule" "$DCC_CELLS" "48"

# --- the margin holds the box back from the reported width --------------------
# COLUMNS reports the terminal, but the host insets the region the status line
# is drawn into, so drawing to the full width clipped the right wall.
DCC_ICON_W=0
COLUMNS=100; DCC_FRAME_MARGIN=2;  dcc_frame_init
check "a margin of 2 draws two cells narrower" "$DCC_FRAME_COLS" "98"
COLUMNS=100; DCC_FRAME_MARGIN=0;  dcc_frame_init
check "a margin of 0 draws the full width"     "$DCC_FRAME_COLS" "100"
COLUMNS=100; DCC_FRAME_MARGIN=10; dcc_frame_init
check "a larger margin insets further"         "$DCC_FRAME_COLS" "90"

COLUMNS=100; DCC_FRAME_MARGIN="wide"; dcc_frame_init
check "a non-numeric margin falls back to 4"   "$DCC_FRAME_COLS" "96"

# The minimum applies to the drawn width, not the reported one: a terminal wide
# enough only before the inset must still fall back rather than draw a box
# narrower than the minimum.
COLUMNS=49; DCC_FRAME_MARGIN=2; dcc_frame_init
check "the minimum is applied after the margin" "$DCC_FRAME_ON" "0"
COLUMNS=50; DCC_FRAME_MARGIN=2; dcc_frame_init
check "one cell wider clears the minimum"       "$DCC_FRAME_ON" "1"
check "and draws at exactly the minimum"        "$DCC_FRAME_COLS" "48"

# A margin at or beyond the terminal width must not produce a negative width.
COLUMNS=60; DCC_FRAME_MARGIN=60; dcc_frame_init
check "a margin as wide as the terminal falls back" "$DCC_FRAME_ON" "0"

# Every row must still measure the drawn width, not the reported one.
COLUMNS=100; DCC_FRAME_MARGIN=2; dcc_frame_init; dcc_frame_budget
dcc_frame_top "someone@example.com" "" 0
dcc_cells "$DCC_FRAME_OUT"
check "a margined top rule measures the drawn width" "$DCC_CELLS" "98"
dcc_line_reset; dcc_seg_add "alpha" cyan; dcc_line_push
dcc_line_build "$DCC_FRAME_BUDGET"
dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
dcc_cells "$DCC_FRAME_OUT"
check "a margined content row measures the drawn width" "$DCC_CELLS" "98"
dcc_frame_bottom
dcc_cells "$DCC_FRAME_OUT"
check "a margined bottom rule measures the drawn width" "$DCC_CELLS" "98"

finish
