#!/usr/bin/env bash
# Theme resolution. The merge order is defaults * theme * userConfig, so a key
# the user sets always beats the same key set by their theme.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/path.sh"
source "$HERE/../scripts/lib/jq-prog.sh"
source "$HERE/../scripts/lib/config.sh"

export LC_ALL=C.UTF-8
PAYLOAD='{"model":{"display_name":"Opus"}}'

parse_with() { # parse_with <config-json> -- sets the DCC_* globals
  local cfg; cfg="$(mktemp)"
  printf '%s' "$1" > "$cfg"
  dcc_parse_all "$PAYLOAD" "$cfg" /dev/null
  rm -f "$cfg"
}

# No theme key: the defaults stand.
parse_with '{}'
check "no theme leaves the default frame"   "$DCC_FRAME_MODE" "auto"
check "no theme leaves the default dir hue" "$DCC_P_DIR"      "blue"
check "no theme reports a clean config"     "$DCC_CONFIG_BAD" "0"

# An explicit default theme is a no-op.
parse_with '{ "theme": "default" }'
check "the default theme changes nothing" "$DCC_P_DIR" "blue"

# minimal turns the frame off and strips the meters back.
parse_with '{ "theme": "minimal" }'
check "minimal disables the frame"     "$DCC_FRAME_MODE"  "none"
check "minimal drops the ctx bar"      "$DCC_W_CTX"       "0"
check "minimal hides the token count"  "$DCC_SHOW_TOKENS" "0"

# mono removes hue; the three weights carry the hierarchy alone.
parse_with '{ "theme": "mono" }'
check "mono desaturates the path"   "$DCC_P_DIR"   "white"
check "mono desaturates the branch" "$DCC_P_GIT"   "white"
check "mono desaturates the model"  "$DCC_P_MODEL" "white"

# vivid raises contrast.
parse_with '{ "theme": "vivid" }'
check "vivid recolours the path" "$DCC_P_DIR" "cyan"

# The user's own key beats the theme's. This is the whole point of the merge
# order: picking a theme must not make a setting unreachable.
parse_with '{ "theme": "mono", "palette": { "dir": "red" } }'
check "a user key overrides the theme"        "$DCC_P_DIR" "red"
check "the theme still supplies unset keys"   "$DCC_P_GIT" "white"

# A theme the table does not define falls back to default rather than failing.
parse_with '{ "theme": "nonesuch" }'
check "an unknown theme falls back to default" "$DCC_P_DIR"      "blue"
check "an unknown theme is not a parse error"  "$DCC_CONFIG_BAD" "0"

# A theme of the wrong type must not abort the parse.
parse_with '{ "theme": 42 }'
check "a non-string theme falls back to default" "$DCC_P_DIR"      "blue"
check "a non-string theme is not a parse error"  "$DCC_CONFIG_BAD" "0"

finish
