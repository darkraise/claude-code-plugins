#!/usr/bin/env bash
# One function per segment. Every segment returns empty text rather than failing
# when its data is absent, which is what keeps a missing rate_limits block or a
# non-repository directory from taking the whole line down.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/color.sh"
source "$HERE/../scripts/lib/render.sh"
source "$HERE/../scripts/lib/git.sh"
source "$HERE/../scripts/lib/segments.sh"

DCC_RAMP="0:green: 50:yellow: 75:orange: 90:red:bold"
DCC_GLYPH_FILLED="#"; DCC_GLYPH_EMPTY="."; DCC_GLYPH_DIRTY="*"
DCC_W_CTX=10; DCC_W_5H=8; DCC_W_7D=8
DCC_SHOW_ETA=1; DCC_SHOW_TOKENS=1
DCC_NOW=1785886800   # fixed clock so countdowns are deterministic

seg() { dcc_segment "$1"; printf '%s' "$DCC_SEG_TEXT"; }

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
P_THINK=1; check "thinking shows when on"         "$(seg think)"  "think"
P_THINK=0; check "thinking hides when off"        "$(seg think)"  ""
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
check "context meter: bar, percentage, tokens" "$(seg ctx)" "ctx [#####.....] 47% (94k)"
dcc_segment ctx
check "context meter takes its ramp color, not the tint" "$DCC_SEG_SPEC" "green "

P_CTX_TOK=800
check "sub-1k token counts are shown raw" "$(seg ctx)" "ctx [#####.....] 47% (800)"

DCC_SHOW_TOKENS=0
check "tokens can be turned off" "$(seg ctx)" "ctx [#####.....] 47%"
DCC_SHOW_TOKENS=1

P_CTX_PCT=""
check "a null context percentage hides the meter" "$(seg ctx)" ""

P_5H_PCT=23; P_5H_RESET=1785900000
check "5h meter with countdown" "$(seg 5h)" "5h [##......] 23% (3h40m)"

P_5H_PCT=92
dcc_segment 5h
check "a meter above 90% turns red and bold" "$DCC_SEG_SPEC" "red bold"

DCC_SHOW_ETA=0
P_5H_PCT=23
check "the countdown can be turned off" "$(seg 5h)" "5h [##......] 23%"
DCC_SHOW_ETA=1

P_5H_PCT=""; P_5H_RESET=""
check "an absent rate limit hides the meter" "$(seg 5h)" ""

P_7D_PCT=41; P_7D_RESET=1786400000
check "7d meter with a multi-day countdown" "$(seg 7d)" "7d [###.....] 41% (5d22h)"

# --- unknown ------------------------------------------------------------------
check "an unknown segment name is ignored" "$(seg nosuchsegment)" ""

finish
