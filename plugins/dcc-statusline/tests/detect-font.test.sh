#!/usr/bin/env bash
# The font probe. A terminal's font config answers only when we can prove we
# are running inside that terminal; every unidentified host gets words.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
PROBE="$HERE/../scripts/detect-font.sh"
F="$HERE/fixtures"

out="$(mktemp)"

probe() { # probe <wt-settings|"">  -- an explicit path is the test escape hatch
  DCC_WT_SETTINGS="$1" bash "$PROBE" "$out" >/dev/null 2>&1
  cat "$out"
}

# --- an explicitly named terminal config is consulted --------------------------
check "a nerd terminal face selects nerd at two cells" "$(probe "$F/wt-nerd.json")" "nerd 2"
check "a mono nerd face selects one cell"              "$(probe "$F/wt-mono.json")" "nerd 1"
check "a plain terminal face selects unicode"          "$(probe "$F/wt-plain.json")" "unicode 1"
check "an unreadable terminal config yields unicode"   "$(probe "$F/wt-bad.json")" "unicode 1"
check "a missing terminal config yields unicode"       "$(probe "$F/nonexistent.json")" "unicode 1"

# --- the Windows Terminal config is gated on actually being in Windows Terminal
# A font config describes the terminal that owns it, not whichever terminal is
# hosting us. Reading Windows Terminal's settings while Claude Code ran under a
# different host reported icons that arrived as "?" on screen.
unset_probe() { # unset_probe -- no explicit config path, so the gate applies
  env -u DCC_WT_SETTINGS -u DCC_ICONS "$@" bash "$PROBE" "$out" >/dev/null 2>&1
  cat "$out"
}
check "without WT_SESSION the terminal config is not consulted" \
  "$(unset_probe env -u WT_SESSION)" "unicode 1"

# --- an installed Nerd Font is never itself a positive signal ------------------
# Having a Nerd Font on the machine never proved the terminal uses it, which is
# exactly the false positive that produced unreadable output.
fonts="$(mktemp)"; printf 'CaskaydiaMono NF\nJetBrainsMono Nerd Font\n' > "$fonts"
check "installed nerd fonts alone do not enable icons" \
  "$(DCC_FONT_LIST="$fonts" unset_probe env -u WT_SESSION)" "unicode 1"
rm -f "$fonts"

# --- overrides ----------------------------------------------------------------
check "the environment override wins outright" \
  "$(DCC_ICONS=unicode probe "$F/wt-nerd.json")" "unicode 1"
check "the environment override can also force icons on" \
  "$(DCC_ICONS=nerd probe "$F/wt-plain.json")" "nerd 2"

# --- the writer must never emit a zero width ----------------------------------
# icons.sh cannot defend against a cache line reading "nerd 0" (glyphs loaded,
# zero cell width): its "-n" guard passes on the string "0". The writer -- this
# script -- has to guarantee one is never produced.
zero_width=""
for wt in "$F/wt-nerd.json" "$F/wt-plain.json" "$F/wt-mono.json" "$F/wt-bad.json" "$F/nonexistent.json"; do
  line="$(probe "$wt")"
  width="${line#* }"
  [ "$width" = "0" ] && zero_width="$zero_width [$wt]"
done
check "width is never zero across every fixture" "${zero_width:-none}" "none"

# The probe must never leave a half-written file behind on failure.
check "the output file holds exactly one line" "$(wc -l < "$out" | tr -d ' ')" "1"

rm -f "$out"
finish
