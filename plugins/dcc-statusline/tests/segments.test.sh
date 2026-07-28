#!/usr/bin/env bash
# One function per segment. Every segment returns empty text rather than failing
# when its data is absent, which is what keeps a missing rate_limits block or a
# non-repository directory from taking the whole line down.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/path.sh"
source "$HERE/../scripts/lib/color.sh"
source "$HERE/../scripts/lib/render.sh"
source "$HERE/../scripts/lib/git.sh"
source "$HERE/../scripts/lib/segments.sh"

DCC_RAMP="0:green: 50:yellow: 75:orange: 90:red:bold"
DCC_GLYPH_FILLED="#"; DCC_GLYPH_EMPTY="."; DCC_GLYPH_DIRTY="*"
DCC_W_CTX=10; DCC_W_5H=8; DCC_W_7D=8
DCC_SHOW_ETA=1; DCC_SHOW_TOKENS=1
DCC_NOW=1785886800   # fixed clock so countdowns are deterministic

DCC_ICON_MODE="unicode"; DCC_ICON_W=0
DCC_I_DIR=""; DCC_I_GIT=""; DCC_I_MODEL=""; DCC_I_FAST=""
DCC_I_ACCOUNT=""; DCC_I_CTX=""; DCC_I_CLOCK=""; DCC_I_COST=""
DCC_P_DIR="blue"; DCC_P_GIT="magenta"; DCC_P_MODEL="cyan"
DCC_P_EFFORT="gray"; DCC_P_FAST="white"; DCC_P_COST="141"; DCC_P_MUTE="gray"

seg() { # seg <name> -> the visible text of that segment
  dcc_seg_reset
  dcc_segment "$1"
  printf '%s' "$DCC_SEG_OUT" | strip_ansi
}
segcells() { dcc_seg_reset; dcc_segment "$1"; printf '%s' "$DCC_SEG_CELLS"; }

# --- dir ----------------------------------------------------------------------
P_CWD="D:/Repositories/Personal/claude-code-plugins/plugins"
DCC_GIT_ROOT="D:/Repositories/Personal/claude-code-plugins"
check "inside a repo, dir is repo-relative" "$(seg dir)" "claude-code-plugins/plugins"

DCC_GIT_ROOT="D:/Repositories/Personal/claude-code-plugins"
P_CWD="D:/Repositories/Personal/claude-code-plugins"
check "at the repo root, dir is the repo name" "$(seg dir)" "claude-code-plugins"

DCC_GIT_ROOT=""
HOME="/home/u"; P_CWD="/home/u/projects/thing"
check "outside a repo, HOME is abbreviated" "$(seg dir)" "~/projects/thing"

P_CWD="/opt/elsewhere"
check "outside HOME, the path is shown whole" "$(seg dir)" "/opt/elsewhere"

# Claude Code reports the working directory in the Windows drive-letter namespace
# ("C:\Users\you"), git reports its root in the mixed one ("D:/repo"), and $HOME
# is the MSYS one ("/c/Users/you"). Comparing any two of those raw fails, so every
# spelling of a directory has to resolve to the same label.
DCC_GIT_ROOT="/d/Repositories/Personal/claude-code-plugins"
for spelling in "D:/Repositories/Personal/claude-code-plugins/plugins" \
                'D:\Repositories\Personal\claude-code-plugins\plugins' \
                "/d/Repositories/Personal/claude-code-plugins/plugins"; do
  P_CWD="$spelling"
  check "inside a repo, [$spelling] is repo-relative" "$(seg dir)" "claude-code-plugins/plugins"
done

for spelling in "D:/Repositories/Personal/claude-code-plugins" \
                'D:\Repositories\Personal\claude-code-plugins' \
                "/d/Repositories/Personal/claude-code-plugins"; do
  P_CWD="$spelling"
  check "at the repo root, [$spelling] is the repo name" "$(seg dir)" "claude-code-plugins"
done

DCC_GIT_ROOT=""
HOME="/c/Users/quang"
for spelling in "C:/Users/quang" 'C:\Users\quang' "/c/Users/quang"; do
  P_CWD="$spelling"
  check "HOME itself abbreviates to ~ for [$spelling]" "$(seg dir)" "~"
done

for spelling in "C:/Users/quang/projects/thing" \
                'C:\Users\quang\projects\thing' \
                "/c/Users/quang/projects/thing"; do
  P_CWD="$spelling"
  check "under HOME, [$spelling] abbreviates" "$(seg dir)" "~/projects/thing"
done

P_CWD='D:\Elsewhere\thing'
check "outside HOME, a Windows path is shown whole in one namespace" \
  "$(seg dir)" "/d/Elsewhere/thing"

HOME="/home/u"

# --- git ----------------------------------------------------------------------
DCC_GIT_BRANCH="main"; DCC_GIT_DIRTY=0
DCC_GIT_AHEAD=0; DCC_GIT_BEHIND=0
DCC_GIT_STAGED=0; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=0
check "a clean branch shows only its name" "$(seg git)" "main"

DCC_GIT_DIRTY=1; DCC_GIT_AHEAD=2; DCC_GIT_BEHIND=1
DCC_GIT_STAGED=3; DCC_GIT_UNSTAGED=1; DCC_GIT_UNTRACKED=2
check "a dirty branch shows the marker and every non-zero count" \
  "$(seg git)" "main* ↑2↓1 ●3 ○1 ?2"

DCC_GIT_BRANCH=""
check "no branch means no git segment" "$(seg git)" ""

# --- session state chips ------------------------------------------------------
P_MODEL="Opus";  check "model"                    "$(seg model)"  "Opus"
P_EFFORT="xhigh"; check "effort level"            "$(seg effort)" "xhigh"
P_EFFORT="";      check "absent effort is hidden" "$(seg effort)" ""
P_FAST=1;  check "fast mode shows when on"        "$(seg fast)"   "fast"
P_FAST=0;  check "fast mode hides when off"       "$(seg fast)"   ""
check "the think segment no longer exists" "$(seg think)" ""
P_AGENT="security-reviewer"; check "agent name"   "$(seg agent)"  "security-reviewer"
P_AGENT="";                  check "no agent"     "$(seg agent)"  ""
P_STYLE="explanatory"; check "output style"       "$(seg style)"  "explanatory"
P_EMAIL="a@b.co";  check "account email"          "$(seg account)" "a@b.co"
P_EMAIL="";        check "no email means no chip" "$(seg account)" ""

# --- cost ---------------------------------------------------------------------
P_COST="1.2034"; check "cost is two decimal places" "$(seg cost)" "\$1.20"
P_COST="";       check "absent cost is hidden"      "$(seg cost)" ""

# --- meters -------------------------------------------------------------------
P_CTX_PCT=47; P_CTX_TOK=94210
check "context meter: bar, percentage, tokens" "$(seg ctx)" "ctx #####..... 47% · 94k"

P_CTX_PCT=47; dcc_seg_reset; dcc_segment ctx
ramped="no"; printf '%s' "$DCC_SEG_OUT" | grep -q $'\033\\[38;5;10m' && ramped="yes"
check "a low meter paints its bar green" "$ramped" "yes"

P_CTX_TOK=800
check "sub-1k token counts are shown raw" "$(seg ctx)" "ctx #####..... 47% · 800"

DCC_SHOW_TOKENS=0
check "tokens can be turned off" "$(seg ctx)" "ctx #####..... 47%"
DCC_SHOW_TOKENS=1

P_CTX_PCT=""
check "a null context percentage hides the meter" "$(seg ctx)" ""

P_5H_PCT=23; P_5H_RESET=1785900000
check "5h meter with countdown" "$(seg 5h)" "5h ##...... 23% · 3h40m"

P_5H_PCT=95; dcc_seg_reset; dcc_segment 5h
ramped="no"; printf '%s' "$DCC_SEG_OUT" | grep -q $'\033\\[1;38;5;9m' && ramped="yes"
check "a meter above 90% turns red and bold" "$ramped" "yes"

DCC_SHOW_ETA=0
P_5H_PCT=23
check "the countdown can be turned off" "$(seg 5h)" "5h ##...... 23%"
DCC_SHOW_ETA=1

P_5H_PCT=""; P_5H_RESET=""
check "an absent rate limit hides the meter" "$(seg 5h)" ""

P_7D_PCT=41; P_7D_RESET=1786400000
check "7d meter with a multi-day countdown" "$(seg 7d)" "7d ###..... 41% · 5d22h"

# Belt and braces for the reset value. jq coerces this field, but anything that
# reached bash arithmetic uncoerced -- a float, an ISO date, a bare word -- raises
# a syntax error (or, under set -u, an unbound-variable abort) that kills the
# whole meter line instead of one countdown. stderr is folded into the captured
# text so such an abort shows up as a failed assertion rather than passing quietly.
P_5H_PCT=23
for bad in "1785900000.0" "2026-07-28T10:00:00Z" "soon" "-5"; do
  P_5H_RESET="$bad"
  check "a non-numeric reset [$bad] costs only the countdown" \
    "$( { seg 5h; } 2>&1 )" "5h ##...... 23%"
done
P_5H_PCT=""; P_5H_RESET=""

# --- unknown ------------------------------------------------------------------
check "an unknown segment name is ignored" "$(seg nosuchsegment)" ""

# --- regression: P_* entirely unset must not abort the dispatcher -------------
# config.sh, not segments.sh, owns the P_* defaults (see its module-level
# assignments): dcc_parse_all can legitimately fail without ever setting them,
# so sourcing config.sh -- not a successful parse -- is what has to stand
# between that failure and an "unbound variable" abort of the whole status
# line. Each name runs in its own subshell so a real regression fails that
# one assertion instead of taking this whole file down with it.
for name in dir git model effort fast think agent style account ctx cost 5h 7d; do
  result=$(
    {
      unset P_EMAIL P_CWD P_MODEL P_EFFORT P_FAST P_THINK P_AGENT P_STYLE \
            P_CTX_PCT P_CTX_TOK P_COST P_5H_PCT P_5H_RESET P_7D_PCT P_7D_RESET
      source "$HERE/../scripts/lib/config.sh"
      dcc_seg_reset
      dcc_segment "$name"
      printf 'rc=%d text=[%s]' "$?" "$DCC_SEG_OUT"
    } 2>&1
  )
  check "unset P_* leaves the '$name' segment empty, not aborted" "$result" "rc=0 text=[]"
done

# --- weights ------------------------------------------------------------------
# Each check pins the weight to the specific text it must wrap, not merely to
# the output containing that weight's escape sequence somewhere -- a check that
# only confirmed presence would still pass if the two weights were swapped.
esc=$'\033'
P_CWD="/repo/claude-code-plugins/plugins"; DCC_GIT_ROOT="/repo/claude-code-plugins"
dcc_seg_reset; dcc_segment dir
dimparent="no"
printf '%s' "$DCC_SEG_OUT" | grep -qF "${esc}[2;38;5;12mclaude-code-plugins/" && dimparent="yes"
boldleaf="no"
printf '%s' "$DCC_SEG_OUT" | grep -qF "${esc}[1;38;5;12mplugins" && boldleaf="yes"
check "the dim weight wraps the parent path"     "$dimparent" "yes"
check "the bold weight wraps the leaf directory" "$boldleaf"  "yes"

# --- icon cell accounting -----------------------------------------------------
check "unicode mode charges no cells for an icon" "$(segcells model)" "4"
DCC_ICON_MODE="nerd"; DCC_ICON_W=2
printf -v DCC_I_MODEL '\357\213\233'
check "a double-width icon charges three cells with its space" "$(segcells model)" "7"
DCC_ICON_W=1
check "a single-width icon charges two cells with its space" "$(segcells model)" "6"
DCC_ICON_MODE="unicode"; DCC_I_MODEL=""

finish
