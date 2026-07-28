#!/usr/bin/env bash
# Icon mode resolution: env beats config beats cache beats default.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/icons.sh"

cache_dir="$(mktemp -d)"
export DCC_STATUSLINE_HOME="$cache_dir"

DCC_ICON_MODE_CFG="auto"; DCC_ICON_W_CFG=0

# --- default with no cache and no override ------------------------------------
unset DCC_ICONS
dcc_icons_init
check "no signal at all falls back to unicode" "$DCC_ICON_MODE" "unicode"
check "unicode mode emits no folder glyph"     "$DCC_I_DIR"     ""
check "unicode mode reports zero icon cells"   "$DCC_ICON_W"    "0"

# --- cache file ---------------------------------------------------------------
printf 'nerd 2\n' > "$cache_dir/icons.detected"
dcc_icons_init
check "the cache selects nerd mode"   "$DCC_ICON_MODE" "nerd"
check "the cache selects icon width"  "$DCC_ICON_W"    "2"
check "nerd mode populates the folder glyph" \
  "$(printf '%s' "$DCC_I_DIR" | od -An -tx1 | tr -d ' \n')" "ef81bb"
check "nerd mode populates the branch glyph" \
  "$(printf '%s' "$DCC_I_GIT" | od -An -tx1 | tr -d ' \n')" "ee82a0"

# --- config beats cache -------------------------------------------------------
DCC_ICON_MODE_CFG="unicode"
dcc_icons_init
check "config mode outranks the cache" "$DCC_ICON_MODE" "unicode"
check "switching back to unicode clears the folder glyph" "$DCC_I_DIR" ""
check "switching back to unicode clears the branch glyph" "$DCC_I_GIT" ""
DCC_ICON_MODE_CFG="auto"

DCC_ICON_W_CFG=1
dcc_icons_init
check "config width outranks the cache" "$DCC_ICON_W" "1"
DCC_ICON_W_CFG=0

# --- env beats config ---------------------------------------------------------
DCC_ICON_MODE_CFG="nerd"
export DCC_ICONS=unicode
dcc_icons_init
check "the environment outranks config" "$DCC_ICON_MODE" "unicode"
unset DCC_ICONS
DCC_ICON_MODE_CFG="auto"

# --- damaged cache ------------------------------------------------------------
printf 'gibberish\n' > "$cache_dir/icons.detected"
dcc_icons_init
check "an unreadable cache value falls back to unicode" "$DCC_ICON_MODE" "unicode"

printf 'nerd notanumber\n' > "$cache_dir/icons.detected"
dcc_icons_init
check "a non-numeric width falls back to two cells" "$DCC_ICON_W" "2"

: > "$cache_dir/icons.detected"
dcc_icons_init
check "an empty cache falls back to unicode" "$DCC_ICON_MODE" "unicode"

rm -rf "$cache_dir"
finish
