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

finish
