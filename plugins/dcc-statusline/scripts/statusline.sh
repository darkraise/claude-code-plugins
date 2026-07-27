#!/usr/bin/env bash
# Claude Code status line. Reads the session payload on stdin, prints two lines.
#
# Process budget: one jq, two git, and the timeout wrappers around them. Nothing
# in this file may use $(...) -- see the note in lib/color.sh.
set -uo pipefail

# Resolve our own directory by parameter expansion only. $(cd ... && pwd) would
# cost two forks on every render, which the process budget does not allow.
DCC_DIR="${BASH_SOURCE[0]%/*}"
[ "$DCC_DIR" = "${BASH_SOURCE[0]}" ] && DCC_DIR="."

source "$DCC_DIR/lib/color.sh"
source "$DCC_DIR/lib/config.sh"
source "$DCC_DIR/lib/render.sh"
source "$DCC_DIR/lib/git.sh"
source "$DCC_DIR/lib/segments.sh"

dcc_main() {
  local input="" name

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

  # Tests freeze the clock; %(%s)T is a bash builtin, so this costs no fork.
  [ -n "${DCC_NOW:-}" ] || printf -v DCC_NOW '%(%s)T' -1

  # Collect git state only when a git segment is actually configured.
  case " $DCC_LINE1 $DCC_LINE2 " in
    *" git "*|*" dir "*) dcc_git_collect "$P_CWD" || true ;;
  esac

  dcc_join_reset
  for name in $DCC_LINE1; do
    dcc_segment "$name"
    dcc_join_add "$DCC_SEG_SPEC" "$DCC_SEG_TEXT"
  done
  [ "$DCC_CONFIG_BAD" -eq 1 ] && dcc_join_add "red bold" "cfg?"
  [ -n "$DCC_JOINED" ] && printf '%s\n' "$DCC_JOINED"

  dcc_join_reset
  for name in $DCC_LINE2; do
    dcc_segment "$name"
    dcc_join_add "$DCC_SEG_SPEC" "$DCC_SEG_TEXT"
  done
  [ -n "$DCC_JOINED" ] && printf '%s\n' "$DCC_JOINED"

  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  dcc_main
fi
