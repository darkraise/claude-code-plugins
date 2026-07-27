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
  # Anything but a run of digits is dropped rather than fed to $(( )). Bash
  # arithmetic on a float, an ISO date, or a bare word does not merely evaluate
  # to zero: it raises a syntax error that aborts the whole render, taking the
  # entire meter line with it. jq already coerces this field, so reaching the
  # non-numeric branch means the coercion was bypassed.
  case "$reset" in ''|*[!0-9]*) reset="" ;; esac
  if [ "$DCC_SHOW_ETA" -eq 1 ] && [ -n "$reset" ]; then
    dcc_eta $(( reset - DCC_NOW ))
    [ -n "$DCC_ETA" ] && text="$text ($DCC_ETA)"
  fi
  DCC_SEG_TEXT="$text"
}

dcc_segment() { # dcc_segment <name> -> DCC_SEG_SPEC, DCC_SEG_TEXT
  local name="${1:-}" t cwd root home
  DCC_SEG_SPEC=""; DCC_SEG_TEXT=""
  case "$name" in
    dir)
      # Claude Code reports the working directory in Windows form while the git
      # root and $HOME arrive in the MSYS form, so both sides of every
      # comparison below are folded into one namespace first (see lib/path.sh).
      dcc_path_norm "$P_CWD";        cwd="$DCC_PATH"
      dcc_path_norm "$DCC_GIT_ROOT"; root="$DCC_PATH"
      dcc_path_norm "${HOME:-}";     home="$DCC_PATH"
      if [ -n "$root" ]; then
        case "$cwd" in
          "$root")   DCC_SEG_TEXT="${root##*/}" ;;
          "$root"/*) DCC_SEG_TEXT="${root##*/}${cwd#"$root"}" ;;
          *)         DCC_SEG_TEXT="$cwd" ;;
        esac
      elif [ -n "$home" ]; then
        # Guarded: an empty $home would turn the "$home"/* pattern into a bare
        # /*, which matches every absolute path.
        case "$cwd" in
          "$home")   DCC_SEG_TEXT="~" ;;
          "$home"/*) DCC_SEG_TEXT="~${cwd#"$home"}" ;;
          *)         DCC_SEG_TEXT="$cwd" ;;
        esac
      else
        DCC_SEG_TEXT="$cwd"
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
