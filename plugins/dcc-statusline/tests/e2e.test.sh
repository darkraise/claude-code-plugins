#!/usr/bin/env bash
# End to end: a payload on stdin produces the finished lines. Asserts on
# ANSI-stripped text, plus one check that the tint and the ramp coexist.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../scripts/statusline.sh"
F="$HERE/fixtures"

export DCC_NOW=1785886800
export DCC_STATUSLINE_CONFIG=/dev/null
export CLAUDE_CONFIG_DIR=""

out="$(bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
line1="$(printf '%s\n' "$out" | sed -n 1p)"
line2="$(printf '%s\n' "$out" | sed -n 2p)"

check "line one carries model and state chips" \
  "$(printf '%s' "$line1" | grep -c 'Opus  ·  xhigh  ·  fast  ·  think')" "1"
check "line two carries all three meters" \
  "$(printf '%s' "$line2" | grep -c 'ctx \[.*\] 47% (94k)  ·  \$1.20  ·  5h \[.*\] 23% (3h40m)  ·  7d \[.*\] 41% (5d22h)')" "1"

# A fresh session has no rate_limits and a null percentage, so line two has
# nothing but cost -- and must not print as a bare separator.
out="$(bash "$SCRIPT" < "$F/fresh.json" | strip_ansi)"
line2="$(printf '%s\n' "$out" | sed -n 2p)"
check "a fresh session shows only cost on line two" "$line2" "\$0.00"
check "no doubled separator when meters are absent" \
  "$(printf '%s' "$line2" | grep -c '·  ·')" "0"

# Empty stdin must not produce a traceback or a stray line.
out="$(printf '' | bash "$SCRIPT" 2>&1)"
check "empty stdin renders nothing" "$out" ""

# A malformed config still renders, with a visible marker.
badcfg="$(mktemp)"; printf '{ not json' > "$badcfg"
out="$(DCC_STATUSLINE_CONFIG="$badcfg" bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
check "a malformed config renders with a marker" \
  "$(printf '%s' "$out" | grep -c 'cfg?')" "1"
rm -f "$badcfg"

# Tint and ramp coexist: the account color paints line one, the ramp paints the
# meters, and the two must both appear in the raw output.
cfg="$(mktemp)"
cat > "$cfg" <<'JSON'
{ "accounts": { "~/.claude": { "color": "magenta" } } }
JSON
raw="$(DCC_STATUSLINE_CONFIG="$cfg" bash "$SCRIPT" < "$F/full.json")"
# Meters take their own ramp color; everything else -- including the
# separators between segments -- takes the account tint. Line two mixes both
# (meters plus the non-meter "cost" chip and its separators), so the tint
# legitimately appears on both lines, not just line one; this checks for its
# presence rather than counting matching lines, which is why a plain
# grep -c/"1" comparison doesn't express the real invariant.
tint="no"; printf '%s' "$raw" | grep -q $'\033\\[38;5;13m' && tint="yes"
check "the account tint is applied" "$tint" "yes"
check "the ramp color is applied to a meter" "$(printf '%s' "$raw" | grep -c $'\033\\[38;5;10m')" "1"
rm -f "$cfg"

finish
