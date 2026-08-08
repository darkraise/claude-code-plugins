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

_dcc_meter() { # _dcc_meter <icon> <label> <pct> <width> <reset-epoch> <tokens|""> [tier]
  local icon="$1" label="$2" pct="$3" width="$4" reset="$5" tokens="$6" tier="${7:-0}"
  local suffix=""
  [ -n "$pct" ] || return 0
  # The bar is the first thing to give: it is the least precise reading on the
  # line, and the percentage beside it says the same thing exactly.
  case "$tier" in
    0) : ;;
    1) width=$(( (width * 60 + 50) / 100 )) ;;
    2) width=$(( (width * 40 + 50) / 100 )) ;;
    *) width=0 ;;
  esac
  # The frame is never more than a few hundred cells wide, and dcc_bar builds
  # its string by repeated append -- quadratic in the width. Without an upper
  # bound a config of meters.width 200000 takes over a minute per render, and
  # the status line redraws continuously.
  [ "$width" -gt 64 ] 2>/dev/null && width=64
  # A one-cell bar carries no information: dcc_bar's existing "never look full
  # below 100%" clamp empties it, so it would read as 0% at every reading under
  # 100. Below two cells the bar is dropped rather than shown misleadingly.
  [ "$width" -lt 2 ] 2>/dev/null && width=0
  dcc_ramp "$pct"
  dcc_bar "$pct" "$width"
  _dcc_icon "$icon" "$DCC_P_MUTE"
  dcc_seg_add "$label " "$DCC_P_MUTE"
  # With no bar the label's trailing space is the only gap the percentage needs;
  # emitting the bar's own trailing space as well would double it.
  if [ -n "$DCC_BAR_ON$DCC_BAR_OFF" ]; then
    dcc_seg_add "$DCC_BAR_ON"  "$DCC_RAMP_COLOR" ""    "$DCC_BAR_ON_N"
    dcc_seg_add "$DCC_BAR_OFF" "$DCC_P_MUTE"     dim   "$DCC_BAR_OFF_N"
    dcc_seg_add " " "$DCC_P_MUTE"
  fi
  # The percentage is always bold: it is the reading, and the ramp's own bold
  # stop above 90% would otherwise be the only thing that ever emphasised it.
  dcc_seg_add "${pct}%" "$DCC_RAMP_COLOR" bold
  # The suffix is context, not a reading, so it goes before the bar does.
  [ "$tier" -ge 2 ] && return 0
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
  local cwd root home leaf parent ancestry reponame sub eff br lim tnow
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

      # A pinned style raises the effective tier but never lowers it. Pinning is
      # a floor on how compact the path may be, not a veto on the line fitting.
      case "${DCC_SEG_DIR_STYLE:-}" in
        repo) [ "$tier" -lt 1 ] && tier=1 ;;
        leaf) [ "$tier" -lt 3 ] && tier=3 ;;
      esac

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
      # Tier 3 truncates to the configured limit, or to 12 when none is set --
      # a branch name is the one payload field with no upper bound, and at the
      # tier of last resort an unbounded field would crowd out every segment
      # beside it.
      br="$DCC_GIT_BRANCH"; lim="${DCC_SEG_GIT_MAXBRANCH:-0}"
      [ "$tier" -ge 3 ] && [ "$lim" -eq 0 ] 2>/dev/null && lim=12
      _dcc_trunc "$br" "$lim"; br="$DCC_TRUNC"
      # The dirty marker and the counts render at normal weight, not dim. Dimmed
      # against a dark background a saturated hue turns muddy and the numbers
      # stop being readable, which defeats the point of showing them. The branch
      # name still leads because it is the only bold piece here.
      dcc_seg_add "$br" "$DCC_P_GIT" bold
      [ "$DCC_GIT_DIRTY" -eq 1 ] && dcc_seg_add "$DCC_GLYPH_DIRTY" "$DCC_P_GIT"
      [ "$tier" -ge 2 ] && return 0
      [ "${DCC_SEG_GIT_COUNTERS:-1}" -eq 1 ] || return 0
      [ "$DCC_GIT_AHEAD"  -gt 0 ] && dcc_seg_add " $DCC_ARROW_UP$DCC_GIT_AHEAD" "$DCC_P_GIT" "" $(( 2 + ${#DCC_GIT_AHEAD} ))
      [ "$DCC_GIT_BEHIND" -gt 0 ] && dcc_seg_add "$DCC_ARROW_DOWN$DCC_GIT_BEHIND" "$DCC_P_GIT" "" $(( 1 + ${#DCC_GIT_BEHIND} ))
      [ "$DCC_GIT_STAGED"    -gt 0 ] && dcc_seg_add " $DCC_DOT_FILLED$DCC_GIT_STAGED" "$DCC_P_GIT" "" $(( 2 + ${#DCC_GIT_STAGED} ))
      [ "$DCC_GIT_UNSTAGED"  -gt 0 ] && dcc_seg_add " $DCC_DOT_HOLLOW$DCC_GIT_UNSTAGED" "$DCC_P_GIT" "" $(( 2 + ${#DCC_GIT_UNSTAGED} ))
      [ "$DCC_GIT_UNTRACKED" -gt 0 ] && dcc_seg_add " ?$DCC_GIT_UNTRACKED" "$DCC_P_GIT"
      ;;
    model)
      [ -n "$P_MODEL" ] || return 0
      _dcc_icon "$DCC_I_MODEL" "$DCC_P_MODEL"
      if [ "$tier" -ge 3 ] || [ "${DCC_SEG_MODEL_SHORT:-0}" -eq 1 ]; then
        dcc_seg_add "${P_MODEL%% *}" "$DCC_P_MODEL" bold
      else
        dcc_seg_add "$P_MODEL" "$DCC_P_MODEL" bold
      fi
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
    time)
      # %(...)T is a bash builtin, so this costs no fork -- the same mechanism
      # statusline.sh uses for DCC_NOW. Reading DCC_NOW rather than -1 keeps a
      # frozen test clock deterministic.
      printf -v tnow '%(%H:%M)T' "${DCC_NOW:--1}"
      dcc_seg_add "$tnow" "$DCC_P_MUTE"
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
    ctx) _dcc_meter "$DCC_I_CTX"   "${DCC_L_CTX:-ctx}" "$P_CTX_PCT" "$DCC_W_CTX" "" "$P_CTX_TOK" "$tier" ;;
    5h)  _dcc_meter "$DCC_I_CLOCK" "${DCC_L_5H:-5h}"   "$P_5H_PCT"  "$DCC_W_5H"  "$P_5H_RESET" "" "$tier" ;;
    7d)  _dcc_meter "$DCC_I_CLOCK" "${DCC_L_7D:-7d}"   "$P_7D_PCT"  "$DCC_W_7D"  "$P_7D_RESET" "" "$tier" ;;
  esac
  return 0
}

DCC_LINE_TIER=0

_dcc_render_line() { # _dcc_render_line <names> <tier> <mark-bad-config>
  local name
  dcc_line_reset
  for name in $1; do
    dcc_segment "$name" "$2"
    dcc_line_push
  done
  if [ "${3:-0}" -eq 1 ] && [ "${DCC_CONFIG_BAD:-0}" -eq 1 ]; then
    dcc_seg_add "cfg?" red bold
    dcc_line_push
  fi
}

dcc_line_fit() { # dcc_line_fit <names> <max-cells> <mark-bad-config>
  # Renders at tier 0 and escalates the whole line one tier at a time until it
  # fits. Uniform escalation is deliberate: a line where the path abbreviated
  # but the branch did not would follow no rule a reader could infer.
  #
  # A max of 0 means the width is unknown -- COLUMNS was missing or unusable,
  # which is also why the frame is off -- so there is nothing to fit against and
  # tier 0 stands.
  local names="$1" max="${2:-0}" mark="${3:-0}" tier top="${DCC_MAX_TIER:-3}"
  # Whitelist the four legal values rather than range-checking. A digit guard
  # followed by [ "$top" -gt 3 ] fails open on a value past 64-bit range: the
  # test does not evaluate false, it errors, the clamp is skipped, and the
  # C-style loop below wraps the value -- either spinning without bound or
  # never executing at all, which would leave DCC_LINE_OUT holding the
  # previous line's segments.
  case "$top" in 0|1|2|3) : ;; *) top=3 ;; esac
  for (( tier = 0; tier <= top; tier++ )); do
    _dcc_render_line "$names" "$tier" "$mark"
    DCC_LINE_TIER="$tier"
    if [ "$max" -le 0 ]; then
      dcc_line_build
      return 0
    fi
    dcc_line_measure
    if [ "$DCC_LINE_TOTAL" -le "$max" ]; then
      dcc_line_build "$max"
      return 0
    fi
  done
  # Tier `top` still overflows. Greedy segment dropping is the last resort, and
  # the only path on which data is actually lost.
  dcc_line_build "$max"
}
