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
check "trunc cuts and ellipsises" "$DCC_TRUNC" "feature/r…"
check "trunc never exceeds maxlen" "${#DCC_TRUNC}" "10"
_dcc_trunc "feature/responsive-tiers" 1
check "trunc at maxlen 1 is the ellipsis alone" "$DCC_TRUNC" "…"
check "trunc at maxlen 1 still honours the bound" "${#DCC_TRUNC}" "1"

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

# --- git ----------------------------------------------------------------------
DCC_GIT_BRANCH="feature/responsive-tiers"
DCC_GIT_DIRTY=1; DCC_GIT_AHEAD=2; DCC_GIT_BEHIND=0
DCC_GIT_STAGED=3; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=2
DCC_SEG_GIT_MAXBRANCH=0

check "git tier 0 shows every counter" "$(segt git 0)" \
  "feature/responsive-tiers* ↑2 ●3 ?2"
check "git tier 1 shows every counter" "$(segt git 1)" \
  "feature/responsive-tiers* ↑2 ●3 ?2"
check "git tier 2 drops the counters" "$(segt git 2)" "feature/responsive-tiers*"
check "git tier 3 truncates the branch" "$(segt git 3)" "feature/res…*"

DCC_GIT_BRANCH="main"
check "git tier 3 leaves a short branch alone" "$(segt git 3)" "main*"

# --- model --------------------------------------------------------------------
P_MODEL="Opus 4.8"
check "model tier 0 is the full name" "$(segt model 0)" "Opus 4.8"
check "model tier 2 is the full name" "$(segt model 2)" "Opus 4.8"
check "model tier 3 is the first word" "$(segt model 3)" "Opus"

# --- meters -------------------------------------------------------------------
# Width 10 scales to 6 at tier 1 ((10*60+50)/100) and 4 at tier 2.
P_CTX_PCT=47; P_CTX_TOK=94210
check "ctx tier 0 is a full bar with the token count" "$(segt ctx 0)" \
  "ctx #####..... 47% · 94k"
check "ctx tier 1 narrows the bar, keeping the suffix" "$(segt ctx 1)" \
  "ctx ###... 47% · 94k"
check "ctx tier 2 narrows further and drops the suffix" "$(segt ctx 2)" \
  "ctx ##.. 47%"
check "ctx tier 3 drops the bar entirely" "$(segt ctx 3)" "ctx 47%"

# A meter configured to width 2 scales below two cells at tier 2. A one-cell bar
# cannot show both states -- dcc_bar's "never look full below 100%" clamp empties
# it, so it would read as 0% at 47% -- so the bar is dropped instead of shown
# misleadingly, and the percentage carries the reading alone.
DCC_W_CTX=2
check "a width-2 meter drops its bar at tier 2" "$(segt ctx 2)" "ctx 47%"
check "a width-2 meter keeps its bar at tier 0" "$(segt ctx 0)" "ctx #. 47% · 94k"
DCC_W_CTX=10

# A meter narrower than two cells drops its bar at every tier, tier 0 included.
# This is a deliberate exception to the tier-0 byte-identity rule: width 1 used
# to render one empty cell, which dcc_bar's "never look full below 100%" clamp
# leaves empty at any reading under 100 -- so it read as 0% at 47%. Width 0 used
# to render a doubled space. The minimal theme sets width 0 on purpose. The
# token suffix is governed only by tier, not by the bar-width clamp, and
# P_CTX_TOK is still set from above, so it still renders here -- its presence
# confirms there is exactly one space before the percentage, not two.
DCC_W_CTX=1
check "a width-1 meter drops its bar at tier 0" "$(segt ctx 0)" "ctx 47% · 94k"
DCC_W_CTX=0
check "a width-0 meter has no doubled space at tier 0" "$(segt ctx 0)" "ctx 47% · 94k"
DCC_W_CTX=10
check "the default width is unaffected at tier 0" "$(segt ctx 0)" "ctx #####..... 47% · 94k"

# An absurd configured width is clamped to 64: dcc_bar builds its string by
# repeated append, quadratic in the width, so an unbounded value would freeze
# the continuously-redrawing status line. 47% of 64 fills 30 cells.
DCC_W_CTX=200000
check "an oversized meter width clamps to 64 cells" "$(segt ctx 0)" \
  "ctx ##############################.................................. 47% · 94k"
err="$( { dcc_seg_reset; dcc_segment ctx 0; } 2>&1 >/dev/null )"
check "an oversized meter width writes nothing to stderr" "$err" ""
# Past 64-bit range the numeric tests cannot evaluate; both width comparisons
# are guarded so the failure is silent, not a per-render stderr line.
DCC_W_CTX=99999999999999999999999
err="$( { dcc_seg_reset; dcc_segment ctx 0; } 2>&1 >/dev/null )"
check "a past-64-bit meter width writes nothing to stderr" "$err" ""
DCC_W_CTX=10

# --- monotonic shrink, every shrinking segment --------------------------------
DCC_GIT_BRANCH="feature/responsive-tiers"
P_5H_PCT=23; P_5H_RESET=1785900000
P_7D_PCT=41; P_7D_RESET=1786400000
for nm in git model ctx 5h 7d; do
  prev=""
  for t in 0 1 2 3; do
    now="$(segtcells "$nm" "$t")"
    if [ -n "$prev" ]; then
      ok="no"; [ "$now" -le "$prev" ] && ok="yes"
      check "$nm tier $t is no wider than tier $(( t - 1 ))" "$ok" "yes"
    fi
    prev="$now"
  done
done

# --- escalation ---------------------------------------------------------------
DCC_SEP="  ·  "; dcc_sep_cells 5
DCC_MAX_TIER=3
DCC_CONFIG_BAD=0
DCC_GIT_BRANCH="main"; DCC_GIT_DIRTY=0
DCC_GIT_AHEAD=0; DCC_GIT_BEHIND=0
DCC_GIT_STAGED=0; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=0
DCC_GIT_ROOT="/home/u/Repos/Personal/claude-code-plugins"
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"
P_MODEL="Opus 4.8"

dcc_line_fit "dir git model" 200 0
check "a wide budget renders at tier 0" "$DCC_LINE_TIER" "0"
check "a wide budget drops nothing" "$DCC_LINE_DROPPED" "0"

dcc_line_fit "dir git model" 60 0
ok="no"; [ "$DCC_LINE_TIER" -gt 0 ] && ok="yes"
check "a tight budget escalates past tier 0" "$ok" "yes"
ok="no"; [ "$DCC_LINE_CELLS" -le 60 ] && ok="yes"
check "the fitted line is within budget" "$ok" "yes"
check "escalation drops no segments" "$DCC_LINE_DROPPED" "0"

# A budget of zero means the width is unknown, not that nothing fits.
dcc_line_fit "dir git model" 0 0
check "an unknown width renders at tier 0" "$DCC_LINE_TIER" "0"
check "an unknown width drops nothing" "$DCC_LINE_DROPPED" "0"

# maxTier 0 pins the render and restores greedy dropping.
DCC_MAX_TIER=0
dcc_line_fit "dir git model" 40 0
check "maxTier 0 never escalates" "$DCC_LINE_TIER" "0"
ok="no"; [ "$DCC_LINE_DROPPED" -gt 0 ] && ok="yes"
check "maxTier 0 falls back to dropping" "$ok" "yes"
DCC_MAX_TIER=3

# Escalation must terminate even when tier 3 still overflows, handing off to the
# greedy drop rather than looping. The budget is 30, not 52: at 52 a truncated
# 300-character branch actually fits at tier 3, so the assertions would pass
# from an in-loop return and never exercise the fall-through they name.
DCC_GIT_BRANCH="$(printf 'x%.0s' $(seq 1 300))"
dcc_line_fit "dir git model" 30 0
check "a pathological branch still reaches tier 3" "$DCC_LINE_TIER" "3"
ok="no"; [ "$DCC_LINE_DROPPED" -gt 0 ] && ok="yes"
check "tier 3 overflow hands off to the greedy drop" "$ok" "yes"
DCC_GIT_BRANCH="main"

# An oversized maxTier must not reach the C-style loop, where it would wrap.
DCC_MAX_TIER=9223372036854776000
dcc_line_fit "model" 200 0
check "an oversized maxTier falls back to 3" "$DCC_LINE_TIER" "0"
check "an oversized maxTier still renders this call" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "Opus 4.8"

# The wide budget above fits at tier 0 whichever way the fallback goes, so only
# a budget too tight for tier 0 can tell falling back to 3 from falling back to
# 0 -- which would pin the render and quietly restore greedy dropping.
DCC_GIT_BRANCH="$(printf 'x%.0s' $(seq 1 300))"
dcc_line_fit "dir git model" 30 0
check "an oversized maxTier still escalates to tier 3" "$DCC_LINE_TIER" "3"
DCC_GIT_BRANCH="main"
DCC_MAX_TIER=3

# The bad-config marker survives re-rendering.
DCC_CONFIG_BAD=1
dcc_line_fit "dir" 200 1
check "the cfg marker is appended when asked" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi | grep -c 'cfg?')" "1"
dcc_line_fit "dir" 200 0
check "the cfg marker is absent when not asked" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi | grep -c 'cfg?')" "0"
DCC_CONFIG_BAD=0

# --- segment options ----------------------------------------------------------
DCC_GIT_BRANCH="feature/responsive-tiers"
DCC_GIT_DIRTY=1; DCC_GIT_AHEAD=2; DCC_GIT_BEHIND=0
DCC_GIT_STAGED=3; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=2
DCC_SEG_GIT_MAXBRANCH=0

DCC_SEG_GIT_COUNTERS=0
check "counters off hides the counts" "$(segt git 0)" "feature/responsive-tiers*"
DCC_SEG_GIT_COUNTERS=1

DCC_SEG_GIT_MAXBRANCH=8
check "maxBranch truncates at tier 0" "$(segt git 0)" "feature…* ↑2 ●3 ?2"
DCC_SEG_GIT_MAXBRANCH=0

DCC_SEG_MODEL_SHORT=1
check "model short applies at tier 0" "$(segt model 0)" "Opus"
DCC_SEG_MODEL_SHORT=0

DCC_L_CTX="context"
check "a custom meter label is used" "$(segt ctx 0)" "context #####..... 47% · 94k"
DCC_L_CTX="ctx"

# dir.style pins the rendering below the line's tier, but never above it: a
# pin is a floor on compactness, not a veto on fitting.
DCC_GIT_ROOT="/home/u/Repos/Personal/claude-code-plugins"
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"
DCC_SEG_DIR_STYLE="repo"
check "dir.style repo pins tier 0 to tier 1" "$(segt dir 0)" \
  "claude-code-plugins/plugins/dcc-statusline"
check "dir.style repo does not block tier 3" "$(segt dir 3)" "dcc-statusline"
DCC_SEG_DIR_STYLE="leaf"
check "dir.style leaf pins tier 0 to tier 3" "$(segt dir 0)" "dcc-statusline"
DCC_SEG_DIR_STYLE=""
check "no dir.style restores tier 0" "$(segt dir 0)" \
  "~/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"

# --- the time segment ---------------------------------------------------------
# DCC_NOW is the frozen clock the meters already use, so the rendering is
# deterministic. 1785886800 mod 86400 is 85200 seconds, which is 23:40 UTC --
# TZ is pinned because %(%H:%M)T renders in local time.
DCC_NOW=1785886800
export TZ=UTC
check "time renders hours and minutes" "$(segt time 0)" "23:40"
check "time does not shrink" "$(segt time 3)" "23:40"

finish
