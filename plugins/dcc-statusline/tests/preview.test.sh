#!/usr/bin/env bash
# The preview renders the real config at several widths. It is not on the render
# path, so it may fork freely.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
PREVIEW="$HERE/../scripts/preview.sh"

export LC_ALL=C.UTF-8
export DCC_NOW=1785886800

out="$(bash "$PREVIEW" --config /dev/null 2>&1)"
check "the default preview shows five widths" \
  "$(printf '%s\n' "$out" | grep -c '^── COLUMNS ')" "5"
# Four report a tier; COLUMNS=48 is below the framing threshold, so it reports
# unframed instead -- there is no width budget there and the tier is always 0.
check "the preview reports the tier where a frame exists" \
  "$(printf '%s\n' "$out" | grep -c 'tier ')" "4"
check "the preview names the unframed width" \
  "$(printf '%s\n' "$out" | grep -c 'unframed')" "1"
# grep -c counts matching LINES, and the model appears on one line of every
# block, so this is five and not one.
check "the preview renders the probe model at every width" \
  "$(printf '%s' "$out" | strip_ansi | grep -c 'Opus')" "5"

out="$(bash "$PREVIEW" --config /dev/null --width 100 2>&1)"
check "--width renders exactly one block" \
  "$(printf '%s\n' "$out" | grep -c '^── COLUMNS ')" "1"
check "--width names the width it was given" \
  "$(printf '%s\n' "$out" | grep -c '^── COLUMNS 100')" "1"

out="$(bash "$PREVIEW" --config /dev/null --theme minimal --width 100 2>&1)"
check "--theme minimal drops the frame" \
  "$(printf '%s' "$out" | grep -c '╭')" "0"

bash "$PREVIEW" --config /dev/null --nonsense >/dev/null 2>&1; rc=$?
check "an unknown flag exits 2" "$rc" "2"

bash "$PREVIEW" --help >/dev/null 2>&1; rc=$?
check "--help exits 0" "$rc" "0"

# A trailing flag must error rather than spin: `shift 2` with one argument left
# returns 1 and shifts nothing, so the parse loop would never terminate. Run
# under timeout so a regression fails the suite instead of hanging it.
timeout 5 bash "$PREVIEW" --config /dev/null --width >/dev/null 2>&1; rc=$?
check "a trailing --width exits 2 rather than hanging" "$rc" "2"
timeout 5 bash "$PREVIEW" --theme >/dev/null 2>&1; rc=$?
check "a trailing --theme exits 2 rather than hanging" "$rc" "2"

# A path the user typed must fail loudly; a preview of built-in defaults would
# look like a successful preview of a config that was never read.
bash "$PREVIEW" --config /no/such/file.json >/dev/null 2>&1; rc=$?
check "a missing explicit config exits 2" "$rc" "2"

# But an explicit /dev/null is legitimate -- it is how the tests ask for the
# built-in defaults, and -e accepts it where -f would not.
bash "$PREVIEW" --config /dev/null --width 100 >/dev/null 2>&1; rc=$?
check "an explicit /dev/null config is accepted" "$rc" "0"

# A config that exists but does not parse warns on stderr and still renders.
badcfg="$(mktemp)"; printf '{ not json' > "$badcfg"
out2="$(bash "$PREVIEW" --config "$badcfg" --width 100 2>&1)"; rc=$?
check "a malformed config still exits 0" "$rc" "0"
check "a malformed config says so" \
  "$(printf '%s' "$out2" | grep -c 'not valid JSON')" "1"
rm -f "$badcfg"

finish
