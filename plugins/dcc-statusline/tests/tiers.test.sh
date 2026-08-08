#!/usr/bin/env bash
# Per-segment tier renderings. Tier 0 must reproduce today's output exactly;
# every higher tier must be no wider than the one below it, or the escalation
# loop in dcc_line_fit would never terminate.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/path.sh"
source "$HERE/../scripts/lib/color.sh"
source "$HERE/../scripts/lib/render.sh"
source "$HERE/../scripts/lib/git.sh"
source "$HERE/../scripts/lib/segments.sh"

export LC_ALL=C.UTF-8

DCC_RAMP="0:green: 50:yellow: 75:orange: 90:red:bold"
DCC_GLYPH_FILLED="#"; DCC_GLYPH_EMPTY="."; DCC_GLYPH_DIRTY="*"
DCC_W_CTX=10; DCC_W_5H=8; DCC_W_7D=8
DCC_SHOW_ETA=1; DCC_SHOW_TOKENS=1
DCC_NOW=1785886800
DCC_ICON_MODE="unicode"; DCC_ICON_W=0
DCC_I_DIR=""; DCC_I_GIT=""; DCC_I_MODEL=""; DCC_I_FAST=""
DCC_I_ACCOUNT=""; DCC_I_CTX=""; DCC_I_CLOCK=""; DCC_I_COST=""
DCC_P_DIR="blue"; DCC_P_GIT="magenta"; DCC_P_MODEL="cyan"
DCC_P_EFFORT="gray"; DCC_P_FAST="white"; DCC_P_COST="141"; DCC_P_MUTE="gray"
DCC_P_EFF_LOW="gray"; DCC_P_EFF_MEDIUM="blue"; DCC_P_EFF_HIGH="cyan"
DCC_P_EFF_XHIGH="141"; DCC_P_EFF_MAX="magenta"

segt() { # segt <name> <tier> -> the visible text at that tier
  dcc_seg_reset
  dcc_segment "$1" "$2"
  printf '%s' "$DCC_SEG_OUT" | strip_ansi
}
segtcells() { dcc_seg_reset; dcc_segment "$1" "$2"; printf '%s' "$DCC_SEG_CELLS"; }

# --- _dcc_trunc ---------------------------------------------------------------
_dcc_trunc "feature/responsive-tiers" 0
check "trunc with maxlen 0 is a no-op" "$DCC_TRUNC" "feature/responsive-tiers"
_dcc_trunc "main" 10
check "trunc leaves a short string alone" "$DCC_TRUNC" "main"
_dcc_trunc "feature/responsive-tiers" 10
check "trunc cuts and ellipsises" "$DCC_TRUNC" "feature/re…"
check "trunc keeps maxlen characters plus the ellipsis" "${#DCC_TRUNC}" "11"

# --- dir ----------------------------------------------------------------------
HOME="/home/u"
DCC_GIT_ROOT="/home/u/Repos/Personal/claude-code-plugins"
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"

check "dir tier 0 is the full path" "$(segt dir 0)" \
  "~/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"
check "dir tier 1 drops the ancestry" "$(segt dir 1)" \
  "claude-code-plugins/plugins/dcc-statusline"
check "dir tier 2 elides the middle" "$(segt dir 2)" \
  "claude-code-plugins/…/dcc-statusline"
check "dir tier 3 is the leaf alone" "$(segt dir 3)" "dcc-statusline"

# At the repo root there is no sub-path, so tier 2 has nothing to elide and
# must not emit a dangling separator.
P_CWD="/home/u/Repos/Personal/claude-code-plugins"
check "dir tier 2 at the repo root is the repo name" "$(segt dir 2)" "claude-code-plugins"
check "dir tier 3 at the repo root is the repo name" "$(segt dir 3)" "claude-code-plugins"

# One component below the root: tier 2's elision would be longer than the text
# it replaces, so tier 2 must fall back to tier 1's rendering.
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins"
check "dir tier 2 with one sub component does not elide" "$(segt dir 2)" \
  "claude-code-plugins/plugins"

# Outside a repository.
DCC_GIT_ROOT=""
P_CWD="/home/u/projects/thing"
check "non-repo dir tier 0 keeps the parent" "$(segt dir 0)" "~/projects/thing"
check "non-repo dir tier 1 is the leaf" "$(segt dir 1)" "thing"
check "non-repo dir tier 3 is the leaf" "$(segt dir 3)" "thing"

# --- monotonic shrink ---------------------------------------------------------
# The escalation loop terminates only if no tier is wider than its predecessor.
DCC_GIT_ROOT="/home/u/Repos/Personal/claude-code-plugins"
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"
prev=""
for t in 0 1 2 3; do
  now="$(segtcells dir "$t")"
  if [ -n "$prev" ]; then
    ok="no"; [ "$now" -le "$prev" ] && ok="yes"
    check "dir tier $t is no wider than tier $(( t - 1 ))" "$ok" "yes"
  fi
  prev="$now"
done

finish
