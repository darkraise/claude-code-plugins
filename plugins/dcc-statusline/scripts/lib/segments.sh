#!/usr/bin/env bash
set -uo pipefail
# One function per segment, dispatched by name. Each sets DCC_SEG_SPEC (a
# colorspec; empty means "use the account tint") and DCC_SEG_TEXT (empty means
# "render nothing"). Returning empty rather than failing is what makes a missing
# block degrade to a shorter line instead of a broken one.

DCC_SEG_SPEC=""
DCC_SEG_TEXT=""

_dcc_meter() { # _dcc_meter <label> <pct> <width> <reset-epoch> <tokens|"">
  local label="$1" pct="$2" width="$3" reset="$4" tokens="$5" text
  DCC_SEG_SPEC=""; DCC_SEG_TEXT=""
  [ -n "$pct" ] || return 0
  dcc_ramp "$pct"
  DCC_SEG_SPEC="$DCC_RAMP_COLOR $DCC_RAMP_BOLD"
  dcc_bar "$pct" "$width"
  text="$label $DCC_BAR ${pct}%"
  if [ "$DCC_SHOW_TOKENS" -eq 1 ] && [ -n "$tokens" ]; then
    if [ "$tokens" -ge 1000 ] 2>/dev/null; then
      text="$text ($(( tokens / 1000 ))k)"
    else
      text="$text ($tokens)"
    fi
  fi
  if [ "$DCC_SHOW_ETA" -eq 1 ] && [ -n "$reset" ]; then
    dcc_eta $(( reset - DCC_NOW ))
    [ -n "$DCC_ETA" ] && text="$text ($DCC_ETA)"
  fi
  DCC_SEG_TEXT="$text"
}

dcc_segment() { # dcc_segment <name> -> DCC_SEG_SPEC, DCC_SEG_TEXT
  local name="${1:-}" t
  DCC_SEG_SPEC=""; DCC_SEG_TEXT=""
  case "$name" in
    dir)
      if [ -n "$DCC_GIT_ROOT" ]; then
        case "$P_CWD" in
          "$DCC_GIT_ROOT") DCC_SEG_TEXT="${DCC_GIT_ROOT##*/}" ;;
          "$DCC_GIT_ROOT"/*) DCC_SEG_TEXT="${DCC_GIT_ROOT##*/}${P_CWD#"$DCC_GIT_ROOT"}" ;;
          *) DCC_SEG_TEXT="$P_CWD" ;;
        esac
      else
        case "$P_CWD" in
          "$HOME"/*) DCC_SEG_TEXT="~${P_CWD#"$HOME"}" ;;
          *)         DCC_SEG_TEXT="$P_CWD" ;;
        esac
      fi
      ;;
    git)
      [ -n "$DCC_GIT_BRANCH" ] || return 0
      t="$DCC_GIT_BRANCH"
      [ "$DCC_GIT_DIRTY" -eq 1 ] && t="$t$DCC_GLYPH_DIRTY"
      [ "$DCC_GIT_AHEAD"  -gt 0 ] && t="$t ↑$DCC_GIT_AHEAD"
      [ "$DCC_GIT_BEHIND" -gt 0 ] && t="${t}↓$DCC_GIT_BEHIND"
      [ "$DCC_GIT_STAGED"    -gt 0 ] && t="$t ●$DCC_GIT_STAGED"
      [ "$DCC_GIT_UNSTAGED"  -gt 0 ] && t="$t ○$DCC_GIT_UNSTAGED"
      [ "$DCC_GIT_UNTRACKED" -gt 0 ] && t="$t ?$DCC_GIT_UNTRACKED"
      DCC_SEG_TEXT="$t"
      ;;
    model)   DCC_SEG_TEXT="$P_MODEL" ;;
    effort)  DCC_SEG_TEXT="$P_EFFORT" ;;
    fast)    [ "$P_FAST"  -eq 1 ] && DCC_SEG_TEXT="fast" ;;
    think)   [ "$P_THINK" -eq 1 ] && DCC_SEG_TEXT="think" ;;
    agent)   DCC_SEG_TEXT="$P_AGENT" ;;
    style)   DCC_SEG_TEXT="$P_STYLE" ;;
    account) DCC_SEG_TEXT="$P_EMAIL" ;;
    cost)
      [ -n "$P_COST" ] || return 0
      printf -v DCC_SEG_TEXT '$%.2f' "$P_COST" 2>/dev/null || DCC_SEG_TEXT=""
      ;;
    ctx) _dcc_meter "ctx" "$P_CTX_PCT" "$DCC_W_CTX" "" "$P_CTX_TOK" ;;
    5h)  _dcc_meter "5h"  "$P_5H_PCT"  "$DCC_W_5H"  "$P_5H_RESET" "" ;;
    7d)  _dcc_meter "7d"  "$P_7D_PCT"  "$DCC_W_7D"  "$P_7D_RESET" "" ;;
  esac
  return 0
}
