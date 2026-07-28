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

# --- joining ------------------------------------------------------------------
dcc_join_reset
dcc_join_add "" "one"
dcc_join_add "" "two"
check "segments are joined with the separator" "$(printf '%s' "$DCC_JOINED" | strip_ansi)" "one | two"

dcc_join_reset
dcc_join_add "" "one"
dcc_join_add "" ""
dcc_join_add "" "three"
check "an empty segment leaves no doubled separator" \
  "$(printf '%s' "$DCC_JOINED" | strip_ansi)" "one | three"

dcc_join_reset
dcc_join_add "" ""
check "an all-empty line renders as nothing" "$DCC_JOINED" ""

DCC_ACCOUNT_COLOR="magenta"
dcc_join_reset
dcc_join_add "" "tinted"
check "an empty colorspec takes the account tint" "$DCC_JOINED" $'\033[38;5;13mtinted\033[0m'

dcc_join_reset
dcc_join_add "red bold" "warn"
check "an explicit colorspec overrides the tint" "$DCC_JOINED" $'\033[1;38;5;9mwarn\033[0m'

finish
