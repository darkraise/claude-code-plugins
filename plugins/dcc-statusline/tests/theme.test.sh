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

# Arrays must be replaced wholesale, not merged element-wise. Nothing else in
# this file inspects lines or the ramp, so an element-wise merge -- which would
# produce a nonsense colour progression -- would otherwise pass every assertion.
parse_with '{ "theme": "minimal" }'
check "minimal replaces the line list wholesale" "$DCC_LINE1" "dir git model"
parse_with '{ "theme": "mono" }'
check "mono replaces the ramp wholesale" "$DCC_RAMP" "0:gray: 75:white: 90:white:bold"

# --- the fallback chain ------------------------------------------------------
# dcc_parse_all has four jq invocations: a primary plus three fallbacks that
# progressively drop the config and the account file. Every one needs
# --argjson themes. A missed one fails with "$themes is not defined", and the
# chain swallows that failure silently -- so the symptom is a theme that works
# until one of those files happens to be malformed. These four cases are what
# stop a future edit from reintroducing that without breaking any test.
parse_with_who() { # parse_with_who <config-json> <who-json> -> DCC_*, PARSE_RC
  local cfg who
  cfg="$(mktemp)"; who="$(mktemp)"
  printf '%s' "$1" > "$cfg"; printf '%s' "$2" > "$who"
  dcc_parse_all "$PAYLOAD" "$cfg" "$who"; PARSE_RC=$?
  rm -f "$cfg" "$who"
}

# Branch 3: the account file is corrupt, the config is not. The theme must
# survive. Were this branch missing its themes argument it would fail through to
# branch 4, which drops the config too, and the hue would come back "blue".
parse_with_who '{ "theme": "mono" }' '{ not json'
check "a theme survives a corrupt account file" "$DCC_P_DIR"      "white"
check "a corrupt account file is not a config error" "$DCC_CONFIG_BAD" "0"

# Branch 2: the config is corrupt, the account file is not. The theme is gone
# with the config it lived in, but the account file must still come through --
# which is the whole point of retrying without the config.
parse_with_who '{ not json' '{"oauthAccount":{"emailAddress":"a@b.c"}}'
check "a corrupt config still parses"          "$DCC_CONFIG_BAD" "1"
check "and the account file still comes through" "$P_EMAIL"      "a@b.c"
check "and defaults apply with no theme"         "$DCC_P_DIR"    "blue"

# Branch 4: both corrupt. The parse must still succeed rather than returning 1
# and leaving every global unassigned.
parse_with_who '{ not json' '{ also not json'
check "both files corrupt still parses" "$PARSE_RC"       "0"
check "both files corrupt reports the config" "$DCC_CONFIG_BAD" "1"

finish
