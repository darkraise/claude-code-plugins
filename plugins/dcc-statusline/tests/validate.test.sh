#!/usr/bin/env bash
# Config diagnostics, plus the assertion that keeps them off the render path.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/validate.sh"

export LC_ALL=C.UTF-8

vout() { # vout <config-json> -> the findings
  local cfg; cfg="$(mktemp)"
  printf '%s' "$1" > "$cfg"
  dcc_validate "$cfg"
  rm -f "$cfg"
}

check "a valid config reports no failures" \
  "$(vout '{ "theme": "mono" }' | grep -c '^FAIL')" "0"
check "a missing file is not a failure" \
  "$(dcc_validate /nonexistent/dcc.json | grep -c '^FAIL')" "0"
check "malformed JSON is a failure" \
  "$(vout '{ not json' | grep -c '^FAIL')" "1"

check "an unknown top-level key is named" \
  "$(vout '{ "colour": "blue" }' | grep -c 'colour')" "1"
check "an unknown theme is named" \
  "$(vout '{ "theme": "nonesuch" }' | grep -c 'nonesuch')" "1"
check "an unknown segment name is named" \
  "$(vout '{ "lines": [["dir","bogus"],[]] }' | grep -c 'bogus')" "1"
check "an invalid colour is named" \
  "$(vout '{ "palette": { "dir": "puce" } }' | grep -c 'puce')" "1"
check "a 256-colour number is accepted" \
  "$(vout '{ "palette": { "dir": "141" } }' | grep -c '^FAIL')" "0"
check "an out-of-range colour number is rejected" \
  "$(vout '{ "palette": { "dir": "999" } }' | grep -c '999')" "1"
check "a wrong-typed frameMargin is named" \
  "$(vout '{ "frameMargin": "wide" }' | grep -c 'frameMargin')" "1"
check "an out-of-range maxTier is named" \
  "$(vout '{ "responsive": { "maxTier": 9 } }' | grep -c 'maxTier')" "1"
check "the \$schema key is not reported as unknown" \
  "$(vout '{ "$schema": "./dcc-statusline.schema.json" }' | grep -c 'schema')" "0"

# Value checks beyond names: enums and ranges, each read from the schema like
# the name lists above, never from a second copy in bash.
check "an unknown frame value is named" \
  "$(vout '{ "frame": "bogus" }' | grep -c 'bogus')" "1"
check "an unknown dir style is named" \
  "$(vout '{ "segments": { "dir": { "style": "nonsense" } } }' | grep -c 'nonsense')" "1"
check "a valid dir style is not a failure" \
  "$(vout '{ "segments": { "dir": { "style": "leaf" } } }' | grep -c '^FAIL')" "0"
check "an unknown icons mode is named" \
  "$(vout '{ "icons": { "mode": "emoji" } }' | grep -c 'emoji')" "1"
check "an out-of-range icons width is a failure" \
  "$(vout '{ "icons": { "width": 99 } }' | grep -c '^FAIL')" "1"
check "a negative meter width is a failure" \
  "$(vout '{ "meters": { "width": { "ctx": -4 } } }' | grep -c '^FAIL')" "1"
check "a meter width past the render clamp is a failure" \
  "$(vout '{ "meters": { "width": { "ctx": 200000 } } }' | grep -c '^FAIL')" "1"
check "a valid meter width is not a failure" \
  "$(vout '{ "meters": { "width": { "ctx": 12 } } }' | grep -c '^FAIL')" "0"
check "an unknown segments sub-key is named" \
  "$(vout '{ "segments": { "typo": { "x": 1 } } }' | grep -c 'typo')" "1"
check "an unknown responsive sub-key is named" \
  "$(vout '{ "responsive": { "maxTier": 1, "extra": 2 } }' | grep -c 'extra')" "1"
check "a numeric separator is a failure" \
  "$(vout '{ "separator": 42 }' | grep -c '^FAIL')" "1"
check "an array separator is not a failure" \
  "$(vout '{ "separator": [" | "] }' | grep -c '^FAIL')" "0"

# The valid-name lists come from the schema, not from a second copy in bash.
# These assert the wiring, so a schema edit that widens or narrows a list is
# picked up by doctor without anyone remembering to update a parallel constant.
_dcc_v_load_schema
check "top-level keys are read from the schema" \
  "$(printf '%s' "$DCC_VALID_TOPKEYS" | wc -w | tr -d ' ')" "13"
check "segment names are read from the schema" \
  "$(printf '%s' "$DCC_VALID_SEGMENTS" | wc -w | tr -d ' ')" "13"
check "theme names are read from the schema" \
  "$(printf '%s' "$DCC_VALID_THEMES" | wc -w | tr -d ' ')" "4"
check "the schema list includes the time segment" \
  "$(printf '%s' "$DCC_VALID_SEGMENTS" | grep -c 'time')" "1"
check "the meter width ceiling is read from the schema" "$DCC_METER_W_MAX" "64"
check "the icon width ceiling is read from the schema" "$DCC_ICON_W_MAX" "2"

# Membership, not counting, and deliberately on the LAST entry of each list.
# A stray CR from a CRLF jq lands on exactly that entry, and every count-based
# assertion above stays green with it: wc -w counts "theme\r" as one word and
# grep -c 'time' matches "time\r". Only the glob _dcc_v_in actually performs
# can tell the difference, so these use it directly.
r=no; _dcc_v_in "theme" "$DCC_VALID_TOPKEYS"  && r=yes
check "the last top-level key matches exactly" "$r" "yes"
r=no; _dcc_v_in "time"  "$DCC_VALID_SEGMENTS" && r=yes
check "the last segment name matches exactly"  "$r" "yes"
r=no; _dcc_v_in "vivid" "$DCC_VALID_THEMES"   && r=yes
check "the last theme name matches exactly"    "$r" "yes"

# An unreadable schema must degrade to a warning, not take doctor down with it.
DCC_SCHEMA_PATH=/nonexistent/schema.json
check "a missing schema warns rather than failing" \
  "$(vout '{ "theme": "mono" }' | grep -c '^warn')" "1"
check "a missing schema is not a FAIL" \
  "$(vout '{ "theme": "mono" }' | grep -c '^FAIL')" "0"
DCC_SCHEMA_PATH="$HERE/../scripts/dcc-statusline.schema.json"

# The budget boundary. validate.sh forks freely; the render path budgets five
# processes. A source line here would blow that budget on every keystroke, and
# the cost would not show up in any rendering assertion.
check "statusline.sh does not source validate.sh" \
  "$(grep -c 'validate\.sh' "$HERE/../scripts/statusline.sh")" "0"
check "no render-path lib sources validate.sh" \
  "$(grep -l 'validate\.sh' "$HERE"/../scripts/lib/*.sh | grep -vc 'validate\.sh')" "0"

# The two greps above search for a literal filename, so a future refactor that
# sourced lib/*.sh in a loop would pull validate.sh onto the render path with
# the string "validate.sh" appearing nowhere, and both would still pass. Ask
# the loaded script itself instead. Sourcing is safe: statusline.sh guards its
# entry point on BASH_SOURCE[0] = $0, which does not hold when sourced.
have="$(DCC_T="$HERE/../scripts/statusline.sh" bash -c \
  'source "$DCC_T" >/dev/null 2>&1; declare -F dcc_validate >/dev/null && echo yes || echo no')"
check "loading statusline.sh does not define dcc_validate" "$have" "no"

finish
