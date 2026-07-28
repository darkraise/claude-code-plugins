#!/usr/bin/env bash
# Rendering primitives: the four-stop ramp, bar fill with its clamps, compact
# countdowns, and separator-aware joining.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/color.sh"
source "$HERE/../scripts/lib/render.sh"

DCC_RAMP="0:green: 50:yellow: 75:orange: 90:red:bold"
DCC_GLYPH_FILLED="#"
DCC_GLYPH_EMPTY="."
DCC_SEP=" | "
DCC_ACCOUNT_COLOR=""

# --- ramp boundaries ----------------------------------------------------------
for pair in "0 green" "49 green" "50 yellow" "74 yellow" "75 orange" "89 orange" "90 red" "100 red"; do
  set -- $pair
  dcc_ramp "$1"
  check "ramp at $1% is $2" "$DCC_RAMP_COLOR" "$2"
done
dcc_ramp 90;  check "the top ramp stop is bold" "$DCC_RAMP_BOLD" "bold"
dcc_ramp 89;  check "lower ramp stops are not bold" "$DCC_RAMP_BOLD" ""
dcc_ramp "";  check "empty percentage yields no ramp color" "$DCC_RAMP_COLOR" ""

# --- bar fill and clamps ------------------------------------------------------
bar() { dcc_bar "$1" "$2"; printf '%s|%s|%s|%s' "$DCC_BAR_ON" "$DCC_BAR_OFF" "$DCC_BAR_ON_N" "$DCC_BAR_OFF_N"; }
check "0% fills nothing"                 "$(bar 0 10)"   "|..........|0|10"
check "1% still fills one cell"          "$(bar 1 10)"   "#|.........|1|9"
check "47% rounds to five cells"         "$(bar 47 10)"  "#####|.....|5|5"
check "99% still leaves one empty cell"  "$(bar 99 10)"  "#########|.|9|1"
check "100% fills every cell"            "$(bar 100 10)" "##########||10|0"
check "width is honored"                 "$(bar 50 8)"   "####|....|4|4"
check "zero width yields no bar"         "$(bar 50 0)"   "||0|0"
check "empty percentage yields no bar"   "$(bar '' 10)"  "||0|0"

# --- countdown formatting -----------------------------------------------------
dcc_eta 500400; check "multi-day countdown"      "$DCC_ETA" "5d19h"
dcc_eta 15180;  check "hours and minutes"        "$DCC_ETA" "4h13m"
dcc_eta 2700;   check "minutes only"             "$DCC_ETA" "45m"
dcc_eta 0;      check "zero reads as now"        "$DCC_ETA" "now"
dcc_eta -60;    check "elapsed reads as now"     "$DCC_ETA" "now"
dcc_eta "";     check "empty seconds yields nothing" "$DCC_ETA" ""

# --- segment accumulation and line building -----------------------------------
dcc_sep_cells 3     # " | "

seg() { # seg <text> <color> [weight] [cells]
  dcc_seg_add "$1" "$2" "${3:-}" "${4:-}"; dcc_line_push
}

dcc_line_reset; seg one green; seg two green; dcc_line_build
check "segments are joined with the separator" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "one | two"
check "the built line reports its cell width" "$DCC_LINE_CELLS" "9"

dcc_line_reset; seg one green; seg "" green; seg three green; dcc_line_build
check "an empty segment leaves no doubled separator" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "one | three"

dcc_line_reset; seg "" green; dcc_line_build
check "an all-empty line renders as nothing" "$DCC_LINE_OUT" ""
check "an all-empty line measures zero"      "$DCC_LINE_CELLS" "0"

# A segment carrying multiple weights is one unit to the joiner.
dcc_line_reset
dcc_seg_add "main" magenta bold
dcc_seg_add "*"    magenta dim
dcc_line_push
dcc_line_build
check "one segment may mix weights" "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "main*"
check "mixed weights sum their cells" "$DCC_LINE_CELLS" "5"

# An explicit cell count overrides the character count, which is how a
# double-width icon is accounted for.
dcc_line_reset
dcc_seg_add "X" cyan "" 2
dcc_line_push
dcc_line_build
check "an explicit cell count wins" "$DCC_LINE_CELLS" "2"

# --- overflow -----------------------------------------------------------------
dcc_line_reset; seg aaaa green; seg bbbb green; seg cccc green
dcc_line_build 12
check "an over-long line drops trailing segments" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "aaaa | bbbb"
check "the drop count is reported" "$DCC_LINE_DROPPED" "1"
check "the surviving line fits the budget" "$DCC_LINE_CELLS" "11"

dcc_line_reset; seg aaaa green; seg bbbb green
dcc_line_build 0
check "a zero budget means unlimited" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "aaaa | bbbb"

dcc_line_reset; seg aaaaaaaaaaaaaaaa green
dcc_line_build 4
check "a single over-long segment yields an empty line" "$DCC_LINE_OUT" ""

# --- colouring ----------------------------------------------------------------
dcc_line_reset; seg tinted magenta; dcc_line_build
check "a segment takes the colour it was given" "$DCC_LINE_OUT" $'\033[38;5;13mtinted\033[0m'

DCC_P_MUTE="gray"
dcc_line_reset; seg one green; seg two green; dcc_line_build
sepcolor="no"; printf '%s' "$DCC_LINE_OUT" | grep -q $'\033\\[2;38;5;245m' && sepcolor="yes"
check "the separator renders dim and muted" "$sepcolor" "yes"

finish
