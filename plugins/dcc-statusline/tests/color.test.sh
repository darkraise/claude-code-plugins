#!/usr/bin/env bash
# lib/color.sh maps names to 256-color SGR sequences. Orange is why 256-color
# is used at all: it has no basic-8 equivalent.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/color.sh"

E=$'\033'

dcc_color green;      check "green is 256-color 10"        "$DCC_C" "$E[38;5;10m"
dcc_color orange;     check "orange is 256-color 208"      "$DCC_C" "$E[38;5;208m"
dcc_color red bold;   check "red bold sets the bold flag"  "$DCC_C" "$E[1;38;5;9m"
dcc_color 244;        check "a bare number passes through" "$DCC_C" "$E[38;5;244m"
dcc_color "";         check "empty name yields no escape"  "$DCC_C" ""
dcc_color nosuchhue;  check "unknown name yields no escape" "$DCC_C" ""

dcc_paint "hi" green
check "paint wraps text in color and reset" "$DCC_PAINTED" "$E[38;5;10mhi$E[0m"

dcc_paint "hi" ""
check "paint with no color returns text unchanged" "$DCC_PAINTED" "hi"

dcc_paint "hi" green
check "painted text survives ansi stripping" "$(printf '%s' "$DCC_PAINTED" | strip_ansi)" "hi"

finish
