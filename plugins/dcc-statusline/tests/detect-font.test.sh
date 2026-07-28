#!/usr/bin/env bash
# The font probe. Terminal config is authoritative; the installed-font list is
# only consulted when that config cannot be read.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
PROBE="$HERE/../scripts/detect-font.sh"
F="$HERE/fixtures"

out="$(mktemp)"
fonts="$(mktemp)"
printf 'CaskaydiaMono NF\nSegoe UI\n' > "$fonts"
nofonts="$(mktemp)"
printf 'Consolas\nSegoe UI\n' > "$nofonts"

probe() { # probe <wt-settings|""> <font-list|"">
  DCC_WT_SETTINGS="$1" DCC_FONT_LIST="$2" bash "$PROBE" "$out" >/dev/null 2>&1
  cat "$out"
}

check "a nerd terminal face selects nerd at two cells" \
  "$(probe "$F/wt-nerd.json" "$nofonts")" "nerd 2"
check "a mono nerd face selects one cell" \
  "$(probe "$F/wt-mono.json" "$nofonts")" "nerd 1"
check "a plain terminal face selects unicode even when nerd fonts exist" \
  "$(probe "$F/wt-plain.json" "$fonts")" "unicode 1"
check "an unreadable terminal config falls back to the font list" \
  "$(probe "$F/wt-bad.json" "$fonts")" "nerd 2"
check "a missing terminal config falls back to the font list" \
  "$(probe "$F/nonexistent.json" "$fonts")" "nerd 2"
check "no signal anywhere yields unicode" \
  "$(probe "$F/nonexistent.json" "$nofonts")" "unicode 1"

DCC_ICONS=unicode
check "the environment override wins outright" \
  "$(DCC_ICONS=unicode probe "$F/wt-nerd.json" "$fonts")" "unicode 1"
unset DCC_ICONS

# Task 3's review found that icons.sh cannot defend against a cache line
# reading "nerd 0" (glyphs loaded, zero cell width): its "-n" guard passes on
# the string "0". The writer -- this script -- must guarantee it never emits
# one. Sweep every terminal-config x font-list pairing from the fixtures
# above and confirm the width field is never "0".
zero_width=""
for wt in "$F/wt-nerd.json" "$F/wt-plain.json" "$F/wt-mono.json" "$F/wt-bad.json" "$F/nonexistent.json"; do
  for fl in "$fonts" "$nofonts"; do
    line="$(probe "$wt" "$fl")"
    width="${line#* }"
    [ "$width" = "0" ] && zero_width="$zero_width [$wt + $fl]"
  done
done
check "width is never zero across every fixture pairing" "${zero_width:-none}" "none"

# The probe must never leave a half-written file behind on failure.
check "the output file holds exactly one line" "$(wc -l < "$out" | tr -d ' ')" "1"

rm -f "$out" "$fonts" "$nofonts"
finish
