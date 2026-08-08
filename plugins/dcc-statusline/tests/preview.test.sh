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

finish
