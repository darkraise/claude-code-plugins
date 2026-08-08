#!/usr/bin/env bash
set -uo pipefail
# Config diagnostics. NEVER sourced by statusline.sh -- this file forks freely,
# and the render path budgets five processes. tests/validate.test.sh asserts the
# boundary, because a stray source line would cost forks on every keystroke
# without failing any rendering assertion.

# The schema is the single source of truth for which keys, segments and themes
# exist. A second copy of those lists in bash would drift, and the only symptom
# would be doctor accepting a key the schema rejects, or the reverse.
#
# It sits under scripts/ rather than the plugin root because dcc_copy_scripts
# copies the contents of scripts/ to ~/.claude/dcc-statusline/; a file at the
# plugin root would never reach an installed copy.
DCC_SCHEMA_PATH="${BASH_SOURCE[0]%/*}/../dcc-statusline.schema.json"

# Colours are not in the schema as a list -- it constrains them with a regex, so
# there is nothing to read back. This stays a bash constant by necessity.
DCC_VALID_COLORS="black red green yellow blue magenta cyan white orange gray"

DCC_VALID_TOPKEYS=""
DCC_VALID_SEGMENTS=""
DCC_VALID_THEMES=""

_dcc_v_load_schema() { # -> DCC_VALID_TOPKEYS, _SEGMENTS, _THEMES; rc 1 if unreadable
  local out
  DCC_VALID_TOPKEYS=""; DCC_VALID_SEGMENTS=""; DCC_VALID_THEMES=""
  [ -r "$DCC_SCHEMA_PATH" ] || return 1
  out="$(jq -r '
    (.properties | keys | join(" ")),
    ((.properties.lines.items.items.enum // []) | join(" ")),
    ((.properties.theme.enum // []) | join(" "))
  ' "$DCC_SCHEMA_PATH" 2>/dev/null)" || return 1
  # Native Windows jq emits CRLF. Command substitution strips the trailing
  # newlines but not the CR ahead of each one, so without this every list ends
  # in a stray CR and _dcc_v_in stops matching its LAST entry -- doctor would
  # then call the `theme` key unknown and reject a valid `time` segment or
  # `vivid` theme. Stripping here rather than relying on sed to normalise:
  # MSYS2's sed happens to, but that is not a property to depend on.
  out="${out//$'\r'/}"
  DCC_VALID_TOPKEYS="$(printf '%s\n' "$out" | sed -n 1p)"
  DCC_VALID_SEGMENTS="$(printf '%s\n' "$out" | sed -n 2p)"
  DCC_VALID_THEMES="$(printf '%s\n' "$out" | sed -n 3p)"
  [ -n "$DCC_VALID_TOPKEYS" ]
}

_dcc_v_in() { # _dcc_v_in <needle> <space-separated haystack>
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

_dcc_v_color() { # _dcc_v_color <label> <value> -> prints a FAIL line if invalid
  local label="$1" v="$2"
  [ -n "$v" ] || return 0
  if _dcc_v_in "$v" "$DCC_VALID_COLORS"; then return 0; fi
  # A bare number is a 256-colour index; anything outside 0-255 is not.
  case "$v" in
    ''|*[!0-9]*) printf 'FAIL - %s: "%s" is not a colour name or a 0-255 number\n' "$label" "$v"; return 1 ;;
  esac
  if [ "$v" -gt 255 ]; then
    printf 'FAIL - %s: "%s" is outside the 0-255 colour range\n' "$label" "$v"
    return 1
  fi
  return 0
}

dcc_validate() { # dcc_validate <config-path> -> findings on stdout, rc 1 on any FAIL
  local cfg="${1:-}" rc=0 k v n

  if [ ! -f "$cfg" ]; then
    printf 'ok   - no config file; built-in defaults apply\n'
    return 0
  fi
  if ! jq -e . "$cfg" >/dev/null 2>&1; then
    printf 'FAIL - config is not valid JSON\n'
    return 1
  fi

  # Without a readable schema the name checks are skipped, not guessed. A
  # warning says so; downgrading to a stale hardcoded list would report
  # confident nonsense about which keys are valid.
  if _dcc_v_load_schema; then
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      _dcc_v_in "$k" "$DCC_VALID_TOPKEYS" && continue
      printf 'warn - unknown key "%s" is ignored\n' "$k"
    done < <(jq -r 'keys[]' "$cfg" 2>/dev/null | tr -d '\r')

    v="$(jq -r '.theme // empty' "$cfg" 2>/dev/null)"
    if [ -n "$v" ] && ! _dcc_v_in "$v" "$DCC_VALID_THEMES"; then
      printf 'FAIL - theme: "%s" is unknown; valid themes are %s\n' "$v" "$DCC_VALID_THEMES"
      rc=1
    fi

    while IFS= read -r v; do
      [ -n "$v" ] || continue
      _dcc_v_in "$v" "$DCC_VALID_SEGMENTS" && continue
      printf 'FAIL - lines: "%s" is not a segment name; valid names are %s\n' "$v" "$DCC_VALID_SEGMENTS"
      rc=1
    done < <(jq -r '(.lines // []) | flatten | .[]' "$cfg" 2>/dev/null | tr -d '\r')
  else
    printf 'warn - schema unreadable at %s; key, segment and theme names unchecked\n' "$DCC_SCHEMA_PATH"
  fi

  while IFS= read -r k; do
    [ -n "$k" ] || continue
    v="${k#*=}"; k="${k%%=*}"
    _dcc_v_color "palette.$k" "$v" || rc=1
  done < <(jq -r '(.palette // {}) | to_entries[] | select(.value|type == "string") | "\(.key)=\(.value)"' "$cfg" 2>/dev/null | tr -d '\r')

  while IFS= read -r k; do
    [ -n "$k" ] || continue
    v="${k#*=}"; k="${k%%=*}"
    _dcc_v_color "palette.effortLevels.$k" "$v" || rc=1
  done < <(jq -r '(.palette.effortLevels // {}) | to_entries[] | "\(.key)=\(.value)"' "$cfg" 2>/dev/null | tr -d '\r')

  n="$(jq -r 'if has("frameMargin") and (.frameMargin|type) != "number" then "bad" else "" end' "$cfg" 2>/dev/null)"
  if [ "$n" = "bad" ]; then
    printf 'FAIL - frameMargin: must be a number of cells, e.g. 4\n'
    rc=1
  fi

  n="$(jq -r '.responsive.maxTier // empty' "$cfg" 2>/dev/null)"
  if [ -n "$n" ]; then
    case "$n" in
      0|1|2|3) : ;;
      *) printf 'FAIL - responsive.maxTier: "%s" is outside 0-3\n' "$n"; rc=1 ;;
    esac
  fi

  [ "$rc" -eq 0 ] && printf 'ok   - config validates\n'
  return "$rc"
}
