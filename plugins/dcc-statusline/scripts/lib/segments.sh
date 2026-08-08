#!/usr/bin/env bash
set -uo pipefail
# One function per segment, dispatched by name. Each paints into DCC_SEG_OUT via
# dcc_seg_add and leaves DCC_SEG_CELLS holding its display width. Returning an
# empty accumulator rather than failing is what makes a missing block degrade to
# a shorter line instead of a broken one.
#
# Colour here means "what kind of thing is this". Account identity is carried by
# the frame, not by the text.

_dcc_icon() { # _dcc_icon <glyph> <color> -- emits the glyph and its trailing space
  [ "$DCC_ICON_MODE" = "nerd" ] || return 0
  [ -n "$1" ] || return 0
  dcc_seg_add "$1" "$2" "" "$DCC_ICON_W"
  dcc_seg_add " " "$2" "" 1
}

_dcc_meter() { # _dcc_meter <icon> <label> <pct> <width> <reset-epoch> <tokens|"">
  local icon="$1" label="$2" pct="$3" width="$4" reset="$5" tokens="$6" suffix=""
  [ -n "$pct" ] || return 0
  dcc_ramp "$pct"
  dcc_bar "$pct" "$width"
  _dcc_icon "$icon" "$DCC_P_MUTE"
  dcc_seg_add "$label " "$DCC_P_MUTE"
  dcc_seg_add "$DCC_BAR_ON"  "$DCC_RAMP_COLOR" ""    "$DCC_BAR_ON_N"
  dcc_seg_add "$DCC_BAR_OFF" "$DCC_P_MUTE"     dim   "$DCC_BAR_OFF_N"
  dcc_seg_add " " "$DCC_P_MUTE"
  # The percentage is always bold: it is the reading, and the ramp's own bold
  # stop above 90% would otherwise be the only thing that ever emphasised it.
  dcc_seg_add "${pct}%" "$DCC_RAMP_COLOR" bold
  if [ "$DCC_SHOW_TOKENS" -eq 1 ] && [ -n "$tokens" ]; then
    if [ "$tokens" -ge 1000 ] 2>/dev/null; then
      suffix="$(( tokens / 1000 ))k"
    else
      suffix="$tokens"
    fi
  fi
  # Anything but a run of digits is dropped rather than fed to $(( )). Bash
  # arithmetic on a float, an ISO date, or a bare word does not merely evaluate
  # to zero: it raises a syntax error that aborts the whole render.
  case "$reset" in ''|*[!0-9]*) reset="" ;; esac
  if [ "$DCC_SHOW_ETA" -eq 1 ] && [ -n "$reset" ]; then
    dcc_eta $(( reset - DCC_NOW ))
    [ -n "$DCC_ETA" ] && suffix="$DCC_ETA"
  fi
  if [ -n "$suffix" ]; then
    dcc_seg_add " $DCC_SEP_DOT $suffix" "$DCC_P_MUTE" dim $(( 3 + ${#suffix} ))
  fi
}

dcc_segment() { # dcc_segment <name> [tier] -> DCC_SEG_OUT, DCC_SEG_CELLS
  local name="${1:-}" tier="${2:-0}"
  local cwd root home leaf parent ancestry reponame sub eff
  case "$name" in
    dir)
      # Claude Code reports the working directory in Windows form while the git
      # root and $HOME arrive in the MSYS form, so both sides of every
      # comparison below are folded into one namespace first (see lib/path.sh).
      dcc_path_norm "$P_CWD";        cwd="$DCC_PATH"
      dcc_path_norm "$DCC_GIT_ROOT"; root="$DCC_PATH"
      dcc_path_norm "${HOME:-}";     home="$DCC_PATH"

      # $HOME is abbreviated before anything else so the repository and the
      # plain-directory cases below both show the same "~/..." prefix.
      # Guarded: an empty $home would turn the "$home"/* pattern into a bare
      # /*, which matches every absolute path.
      if [ -n "$home" ]; then
        case "$cwd" in
          "$home")   cwd="~" ;;
          "$home"/*) cwd="~${cwd#"$home"}" ;;
        esac
        case "$root" in
          "$home")   root="~" ;;
          "$home"/*) root="~${root#"$home"}" ;;
        esac
      fi
      [ -n "$cwd" ] || return 0
      _dcc_icon "$DCC_I_DIR" "$DCC_P_DIR"

      if [ -n "$root" ] && { [ "$cwd" = "$root" ] || [ "${cwd#"$root"/}" != "$cwd" ]; }; then
        # Inside a repository the path is read in three tones: what leads to the
        # repository recedes, the repository name is the anchor, and the
        # position inside it reads plainly. The anchor sits in the same place
        # whatever the depth, and every tier below preserves it -- shrinking may
        # remove context but must never move where the eye lands.
        reponame="${root##*/}"
        ancestry="${root%/*}/"
        [ "$reponame" = "$root" ] && ancestry=""
        sub="${cwd#"$root"}"
        case "$tier" in
          0) : ;;
          1) ancestry="" ;;
          2) ancestry=""
             # Elide only when there is a middle to remove. With zero or one
             # component below the root the elision is longer than the text it
             # would replace, so tier 2 renders as tier 1.
             case "${sub#/}" in
               */*) sub="/$DCC_ELLIPSIS/${sub##*/}" ;;
             esac
             ;;
          *) ancestry=""
             [ -n "$sub" ] && { reponame="${sub##*/}"; sub=""; }
             ;;
        esac
        [ -n "$ancestry" ] && dcc_seg_add "$ancestry" "$DCC_P_DIR" dim
        dcc_seg_add "$reponame" "$DCC_P_DIR" bold
        [ -n "$sub" ] && dcc_seg_add "$sub" "$DCC_P_DIR"
      else
        leaf="${cwd##*/}"
        if [ "$leaf" = "$cwd" ] || [ "$tier" -gt 0 ]; then
          [ -n "$leaf" ] || leaf="$cwd"
          dcc_seg_add "$leaf" "$DCC_P_DIR" bold
        else
          parent="${cwd%/*}/"
          dcc_seg_add "$parent" "$DCC_P_DIR" dim
          dcc_seg_add "$leaf"   "$DCC_P_DIR" bold
        fi
      fi
      ;;
    git)
      [ -n "$DCC_GIT_BRANCH" ] || return 0
      _dcc_icon "$DCC_I_GIT" "$DCC_P_GIT"
      # The dirty marker and the counts render at normal weight, not dim. Dimmed
      # against a dark background a saturated hue turns muddy and the numbers
      # stop being readable, which defeats the point of showing them. The branch
      # name still leads because it is the only bold piece here.
      dcc_seg_add "$DCC_GIT_BRANCH" "$DCC_P_GIT" bold
      [ "$DCC_GIT_DIRTY" -eq 1 ] && dcc_seg_add "$DCC_GLYPH_DIRTY" "$DCC_P_GIT"
      [ "$DCC_GIT_AHEAD"  -gt 0 ] && dcc_seg_add " $DCC_ARROW_UP$DCC_GIT_AHEAD" "$DCC_P_GIT" "" $(( 2 + ${#DCC_GIT_AHEAD} ))
      [ "$DCC_GIT_BEHIND" -gt 0 ] && dcc_seg_add "$DCC_ARROW_DOWN$DCC_GIT_BEHIND" "$DCC_P_GIT" "" $(( 1 + ${#DCC_GIT_BEHIND} ))
      [ "$DCC_GIT_STAGED"    -gt 0 ] && dcc_seg_add " $DCC_DOT_FILLED$DCC_GIT_STAGED" "$DCC_P_GIT" "" $(( 2 + ${#DCC_GIT_STAGED} ))
      [ "$DCC_GIT_UNSTAGED"  -gt 0 ] && dcc_seg_add " $DCC_DOT_HOLLOW$DCC_GIT_UNSTAGED" "$DCC_P_GIT" "" $(( 2 + ${#DCC_GIT_UNSTAGED} ))
      [ "$DCC_GIT_UNTRACKED" -gt 0 ] && dcc_seg_add " ?$DCC_GIT_UNTRACKED" "$DCC_P_GIT"
      ;;
    model)
      [ -n "$P_MODEL" ] || return 0
      _dcc_icon "$DCC_I_MODEL" "$DCC_P_MODEL"
      dcc_seg_add "$P_MODEL" "$DCC_P_MODEL" bold
      ;;
    effort)
      # Coloured by level, on a cool-to-vivid progression that deliberately
      # avoids the green-through-red the meters use for usage. Sharing those
      # hues would make one colour mean two things on the same line: near a
      # limit, or simply set to max. An unrecognised level falls back to the
      # plain effort colour rather than going uncoloured.
      [ -n "$P_EFFORT" ] || return 0
      case "$P_EFFORT" in
        low)    eff="$DCC_P_EFF_LOW"    ;;
        medium) eff="$DCC_P_EFF_MEDIUM" ;;
        high)   eff="$DCC_P_EFF_HIGH"   ;;
        xhigh)  eff="$DCC_P_EFF_XHIGH"  ;;
        max)    eff="$DCC_P_EFF_MAX"    ;;
        *)      eff="$DCC_P_EFFORT"     ;;
      esac
      dcc_seg_add "$P_EFFORT" "$eff"
      ;;
    fast)
      [ "$P_FAST" -eq 1 ] || return 0
      if [ "$DCC_ICON_MODE" = "nerd" ] && [ -n "$DCC_I_FAST" ]; then
        dcc_seg_add "$DCC_I_FAST" "$DCC_P_FAST" "" "$DCC_ICON_W"
      else
        dcc_seg_add "fast" "$DCC_P_FAST"
      fi
      ;;
    agent)   dcc_seg_add "$P_AGENT" "$DCC_P_MUTE" ;;
    style)   dcc_seg_add "$P_STYLE" "$DCC_P_MUTE" ;;
    account)
      [ -n "$P_EMAIL" ] || return 0
      # Reached only when the frame is off, because framed mode moves the
      # account onto the top rule and strips this segment from the line. So the
      # account tint belongs here unconditionally: without it, a terminal too
      # narrow to frame -- or a host that omits COLUMNS -- would carry no
      # at-a-glance account signal at all, which is the one thing this plugin
      # exists to provide. Dim keeps it recessive; the hue still reads.
      local acct="${DCC_ACCOUNT_COLOR:-$DCC_P_MUTE}"
      _dcc_icon "$DCC_I_ACCOUNT" "$acct"
      dcc_seg_add "$P_EMAIL" "$acct" dim
      ;;
    cost)
      [ -n "$P_COST" ] || return 0
      local money
      printf -v money '%.2f' "$P_COST" 2>/dev/null || return 0
      if [ "$DCC_ICON_MODE" = "nerd" ] && [ -n "$DCC_I_COST" ]; then
        _dcc_icon "$DCC_I_COST" "$DCC_P_COST"
        dcc_seg_add "$money" "$DCC_P_COST" bold
      else
        dcc_seg_add "\$$money" "$DCC_P_COST" bold
      fi
      ;;
    ctx) _dcc_meter "$DCC_I_CTX"   "ctx" "$P_CTX_PCT" "$DCC_W_CTX" "" "$P_CTX_TOK" ;;
    5h)  _dcc_meter "$DCC_I_CLOCK" "5h"  "$P_5H_PCT"  "$DCC_W_5H"  "$P_5H_RESET" "" ;;
    7d)  _dcc_meter "$DCC_I_CLOCK" "7d"  "$P_7D_PCT"  "$DCC_W_7D"  "$P_7D_RESET" "" ;;
  esac
  return 0
}
