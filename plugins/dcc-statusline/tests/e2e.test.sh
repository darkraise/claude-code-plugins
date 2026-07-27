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

# Hermetic account state. An empty CLAUDE_CONFIG_DIR sends the render to the real
# $HOME/.claude.json, which made the result depend on the machine and printed the
# machine owner's actual email address into the test output. A throwaway home with
# a fixture account file removes both problems, and keeps the resolved config key
# at "~/.claude" so the tint assertions still exercise the abbreviated form.
fakehome="$(mktemp -d)"
mkdir -p "$fakehome/.claude"
cp "$F/claude.json" "$fakehome/.claude/.claude.json"
export HOME="$fakehome"
export CLAUDE_CONFIG_DIR="$fakehome/.claude"

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
raw1="$(printf '%s\n' "$raw" | sed -n 1p)"
raw2="$(printf '%s\n' "$raw" | sed -n 2p)"
# Meters take their own ramp color; everything else -- including the separators
# between segments -- takes the account tint, so the tint legitimately appears on
# both lines. Scoped to line one anyway: searching the whole output still passes
# when line one renders empty, which is exactly the failure worth catching.
tint="no"; printf '%s' "$raw1" | grep -q $'\033\\[38;5;13m' && tint="yes"
check "the account tint paints line one" "$tint" "yes"
# Counted with grep -o. grep -c counts matching *lines*, so it reads 1 no matter
# how many meters are on the line -- and reads 0 the moment a user's config moves
# one of them to the other line.
check "every meter on line two takes the ramp color" \
  "$(printf '%s' "$raw2" | grep -o $'\033\\[38;5;10m' | wc -l | tr -d ' ')" "3"

# The same account directory spelled the way Windows hands it over must resolve to
# the same "~/.claude" key. When it does not, the tint silently never applies and
# the account file is never found -- with no error anywhere to say so.
bs="$(printf '%s' "$CLAUDE_CONFIG_DIR" | tr '/' '\\')"
raw1="$(CLAUDE_CONFIG_DIR="$bs" DCC_STATUSLINE_CONFIG="$cfg" bash "$SCRIPT" < "$F/full.json" | sed -n 1p)"
tint="no"; printf '%s' "$raw1" | grep -q $'\033\\[38;5;13m' && tint="yes"
check "a backslash-spelled config dir still applies the tint" "$tint" "yes"
check "a backslash-spelled config dir still finds the account file" \
  "$(printf '%s' "$raw1" | strip_ansi | grep -c 'someone@example.com')" "1"
rm -f "$cfg"

rm -rf "$fakehome"
finish
