#!/usr/bin/env bash
# Claude Code status line. Reads the session payload on stdin, prints two lines,
# or four when the frame is enabled.
#
# Process budget: one jq, two git, and the timeout wrappers around them. Nothing
# in this file may use $(...) -- see the note in lib/color.sh.
set -uo pipefail

# Without a UTF-8 locale bash measures and slices bytes, so a three-byte box
# glyph counts as three cells and the frame's right wall lands in the wrong
# place. Every width calculation downstream depends on this line.
export LC_ALL=C.UTF-8

# Resolve our own directory by parameter expansion only. $(cd ... && pwd) would
# cost two forks on every render, which the process budget does not allow.
DCC_DIR="${BASH_SOURCE[0]%/*}"
[ "$DCC_DIR" = "${BASH_SOURCE[0]}" ] && DCC_DIR="."

source "$DCC_DIR/lib/path.sh"
source "$DCC_DIR/lib/jq-prog.sh"
source "$DCC_DIR/lib/color.sh"
source "$DCC_DIR/lib/config.sh"
source "$DCC_DIR/lib/icons.sh"
source "$DCC_DIR/lib/render.sh"
source "$DCC_DIR/lib/frame.sh"
source "$DCC_DIR/lib/git.sh"
source "$DCC_DIR/lib/segments.sh"

_dcc_strip_account() { # _dcc_strip_account <names> -> DCC_NAMES
  local name out=""
  DCC_NAMES=""
  for name in $1; do
    [ "$name" = "account" ] && continue
    out="$out $name"
  done
  DCC_NAMES="${out# }"
}

dcc_main() {
  local names1 names2 DCC_TIER1=0

  IFS= read -r -d '' input || true
  [ -n "$input" ] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    printf 'dcc-statusline: jq is not on PATH\n'
    return 0
  fi

  dcc_config_path
  dcc_config_key
  dcc_claude_json_path
  dcc_parse_all "$input" "$DCC_CONFIG_PATH" "$DCC_CLAUDE_JSON" || return 0

  dcc_icons_init
  dcc_frame_init
  dcc_frame_budget

  # Tests freeze the clock; %(%s)T is a bash builtin, so this costs no fork.
  [ -n "${DCC_NOW:-}" ] || printf -v DCC_NOW '%(%s)T' -1

  names1="$DCC_LINE1"
  names2="$DCC_LINE2"

  # Framed mode moves the account onto the top rule, so it must not also render
  # inside. Unframed mode leaves the line list exactly as configured.
  #
  # Both lines are stripped: nothing stops a user putting "account" on line two,
  # and the top rule is drawn from P_EMAIL regardless of which line it was
  # configured on, so stripping only line one renders the address twice.
  #
  # Matching is on whole words rather than by substring substitution, so a
  # future segment name that merely contains "account" cannot be silently
  # mangled.
  if [ "$DCC_FRAME_ON" -eq 1 ]; then
    _dcc_strip_account "$names1"; names1="$DCC_NAMES"
    _dcc_strip_account "$names2"; names2="$DCC_NAMES"
  fi

  # Collect git state only when a git segment is actually configured.
  case " $names1 $names2 " in
    *" git "*|*" dir "*) dcc_git_collect "$P_CWD" || true ;;
  esac

  if [ "$DCC_FRAME_ON" -eq 1 ]; then
    dcc_frame_top "$P_EMAIL" "$DCC_I_ACCOUNT" "$DCC_ICON_W"
    printf '%s\n' "$DCC_FRAME_OUT"
    DCC_SEP="$DCC_SEP1"; dcc_sep_cells "${#DCC_SEP1}"
    dcc_line_fit "$names1" "$DCC_FRAME_BUDGET" 1
    DCC_TIER1="$DCC_LINE_TIER"
    dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
    printf '%s\n' "$DCC_FRAME_OUT"
    DCC_SEP="$DCC_SEP2"; dcc_sep_cells "${#DCC_SEP2}"
    dcc_line_fit "$names2" "$DCC_FRAME_BUDGET" 0
    dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
    printf '%s\n' "$DCC_FRAME_OUT"
    dcc_frame_bottom
    printf '%s\n' "$DCC_FRAME_OUT"
    [ -n "${DCC_PREVIEW_TIERS:-}" ] && printf 'DCC_TIERS %s/%s\n' "$DCC_TIER1" "$DCC_LINE_TIER"
    return 0
  fi

  DCC_SEP="$DCC_SEP1"; dcc_sep_cells "${#DCC_SEP1}"
  dcc_line_fit "$names1" 0 1
  DCC_TIER1="$DCC_LINE_TIER"
  [ -n "$DCC_LINE_OUT" ] && printf '%s\n' "$DCC_LINE_OUT"

  DCC_SEP="$DCC_SEP2"; dcc_sep_cells "${#DCC_SEP2}"
  dcc_line_fit "$names2" 0 0
  [ -n "$DCC_LINE_OUT" ] && printf '%s\n' "$DCC_LINE_OUT"

  [ -n "${DCC_PREVIEW_TIERS:-}" ] && printf 'DCC_TIERS %s/%s\n' "$DCC_TIER1" "$DCC_LINE_TIER"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  input=""
  dcc_main
fi
