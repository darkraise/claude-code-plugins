#!/usr/bin/env bash
# Renders the real config at several widths so the responsive tiers can be seen
# before they are trusted.
#
# A separate script rather than a flag on statusline.sh: statusline.sh reads a
# payload on stdin and must stay free of argument parsing on the render path.
# This file is not on that path and forks freely.
set -uo pipefail

DCC_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DCC_WIDTHS="48 60 80 120 200"
DCC_CFG=""
DCC_THEME=""

# Every glyph under scripts/ is an octal UTF-8 escape rather than a literal
# byte in the source, the same convention lib/frame.sh uses for its box
# corners -- so this file stays readable as plain ASCII regardless of the
# editor or terminal encoding it is opened in.
printf -v DCC_BOX_H '\342\224\200'   # U+2500
DCC_RULE="$DCC_BOX_H$DCC_BOX_H"

_dcc_usage() {
  cat <<'TXT'
usage: preview.sh [--width N] [--theme NAME] [--config PATH]

  --width N      render one width only, instead of 48 60 80 120 200
  --theme NAME   render with this theme, without editing the config
  --config PATH  render this config file instead of the installed one
TXT
}

DCC_CFG_GIVEN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --width|--theme|--config)
      # `shift 2` with a single argument remaining returns 1 and shifts
      # nothing, so $# never decreases and this loop spins at full CPU with no
      # output. A trailing flag is an ordinary typo; it must not lock the
      # user's terminal.
      [ $# -ge 2 ] || { printf 'preview.sh: %s needs a value\n' "$1" >&2; exit 2; }
      case "$1" in
        --width)  DCC_WIDTHS="$2" ;;
        --theme)  DCC_THEME="$2"  ;;
        --config) DCC_CFG="$2"; DCC_CFG_GIVEN=1 ;;
      esac
      shift 2
      ;;
    --help|-h) _dcc_usage; exit 0 ;;
    *) printf 'preview.sh: unknown option %s\n' "$1" >&2; _dcc_usage >&2; exit 2 ;;
  esac
done

if [ "$DCC_CFG_GIVEN" -eq 1 ]; then
  # A path the user typed is not the same as a path that merely defaults.
  # Tested with -e rather than -f so an explicit /dev/null stays legitimate.
  [ -e "$DCC_CFG" ] || { printf 'preview.sh: no such config: %s\n' "$DCC_CFG" >&2; exit 2; }
else
  DCC_CFG="${DCC_STATUSLINE_CONFIG:-$HOME/.claude/dcc-statusline.json}"
  [ -f "$DCC_CFG" ] || DCC_CFG=/dev/null
fi

# A config that exists but does not parse would otherwise render as built-in
# defaults with nothing said about it -- the same silent-success failure as a
# mistyped path, reached a different way. This is a diagnostic tool; say so.
if [ "$DCC_CFG" != /dev/null ] && ! jq -e . "$DCC_CFG" >/dev/null 2>&1; then
  printf 'preview.sh: %s is not valid JSON; previewing built-in defaults\n' "$DCC_CFG" >&2
  DCC_CFG=/dev/null
fi

# A theme override is applied by merging it over the chosen config into a temp
# file, so the user's own file is never touched.
if [ -n "$DCC_THEME" ]; then
  tmp="$(mktemp)"
  # A trap rather than a cleanup line at the end of the script: the invalid
  # --width guard inside the render loop below exits 2 without ever reaching
  # the tail of the script, which would otherwise leak this file.
  trap 'rm -f "$tmp"' EXIT
  jq --arg t "$DCC_THEME" '. + {theme: $t}' "$DCC_CFG" > "$tmp" 2>/dev/null
  # Tested with -s rather than on jq's exit status: jq run against /dev/null (or
  # any empty file) reads no JSON value, writes nothing, and still exits 0, so an
  # exit-status check would leave an empty config here and silently lose the theme.
  [ -s "$tmp" ] || jq -n --arg t "$DCC_THEME" '{theme: $t}' > "$tmp"
  DCC_CFG="$tmp"
fi

# A representative session: inside a repository, mid-context, with both rate
# limit windows populated. Frozen relative to DCC_NOW so the countdowns are
# stable across runs.
now="${DCC_NOW:-$(date +%s)}"
payload="$(cat <<JSON
{
  "workspace": { "current_dir": "$PWD" },
  "model": { "display_name": "Opus 4.8" },
  "effort": { "level": "xhigh" },
  "cost": { "total_cost_usd": 1.2 },
  "context_window": { "used_percentage": 47, "total_input_tokens": 94210 },
  "rate_limits": {
    "five_hour":  { "used_percentage": 23, "resets_at": $(( now + 13200 )) },
    "seven_day":  { "used_percentage": 41, "resets_at": $(( now + 500000 )) }
  }
}
JSON
)"

for w in $DCC_WIDTHS; do
  case "$w" in ''|*[!0-9]*) printf 'preview.sh: "%s" is not a width\n' "$w" >&2; exit 2 ;; esac
  # One render per width, not two. DCC_PREVIEW_TIERS appends a machine-readable
  # DCC_TIERS line; it is split off here rather than earned with a second
  # subprocess render of the same thing.
  out="$(printf '%s' "$payload" \
    | COLUMNS="$w" DCC_STATUSLINE_CONFIG="$DCC_CFG" DCC_NOW="$now" \
      DCC_PREVIEW_TIERS=1 bash "$DCC_SRC_DIR/statusline.sh" 2>/dev/null)"
  tiers="$(printf '%s\n' "$out" | sed -n 's/^DCC_TIERS //p')"
  body="$(printf '%s\n' "$out" | sed '/^DCC_TIERS /d')"

  # Below DCC_FRAME_MIN + frameMargin the frame is off, but the width can still
  # be known and dcc_line_fit still escalates against it -- only the box itself
  # is missing. Printing "tier 0/0" there next to a genuine "tier 3/2" at a
  # wider setting would read as though the narrow terminal were the roomier
  # one, when really no box was drawn at all. Say unframed instead: that is the
  # honest reason for the different label, not the tier. Framed output is
  # always exactly 4 lines (top rule, two content rows, bottom rule); unframed
  # is at most 2, so counting lines tells the two apart without inspecting
  # DCC_FRAME_ON.
  if [ "$(printf '%s\n' "$body" | grep -c '')" -ge 4 ]; then
    printf '\n%s COLUMNS %s %s tier %s %s\n' "$DCC_RULE" "$w" "$DCC_RULE" "${tiers:-0/0}" "$DCC_RULE"
  else
    printf '\n%s COLUMNS %s %s unframed %s\n' "$DCC_RULE" "$w" "$DCC_RULE" "$DCC_RULE"
  fi
  printf '%s\n' "$body"
done
printf '\n'

exit 0
