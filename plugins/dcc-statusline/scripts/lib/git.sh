#!/usr/bin/env bash
set -uo pipefail
# Git state from one porcelain=v2 call. In porcelain v2 a changed entry looks
# like "1 <XY> ..." where X is the staged status and Y the unstaged one, and "."
# means unchanged -- so staged and unstaged counts come from the same lines that
# carry the branch header.

DCC_GIT_BRANCH=""
DCC_GIT_AHEAD=0
DCC_GIT_BEHIND=0
DCC_GIT_STAGED=0
DCC_GIT_UNSTAGED=0
DCC_GIT_UNTRACKED=0
DCC_GIT_DIRTY=0
DCC_GIT_ROOT=""

dcc_git_parse() { # dcc_git_parse <porcelain-v2-text>
  local line ab xy x y
  DCC_GIT_BRANCH=""; DCC_GIT_AHEAD=0; DCC_GIT_BEHIND=0
  DCC_GIT_STAGED=0; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=0; DCC_GIT_DIRTY=0
  while IFS= read -r line; do
    case "$line" in
      '# branch.head '*)
        DCC_GIT_BRANCH="${line#\# branch.head }"
        [ "$DCC_GIT_BRANCH" = "(detached)" ] && DCC_GIT_BRANCH="detached"
        ;;
      '# branch.ab '*)
        ab="${line#\# branch.ab }"
        DCC_GIT_AHEAD="${ab%% *}";  DCC_GIT_AHEAD="${DCC_GIT_AHEAD#+}"
        DCC_GIT_BEHIND="${ab##* }"; DCC_GIT_BEHIND="${DCC_GIT_BEHIND#-}"
        ;;
      '1 '*|'2 '*)
        xy="${line:2:2}"; x="${xy:0:1}"; y="${xy:1:1}"
        [ "$x" != "." ] && DCC_GIT_STAGED=$(( DCC_GIT_STAGED + 1 ))
        [ "$y" != "." ] && DCC_GIT_UNSTAGED=$(( DCC_GIT_UNSTAGED + 1 ))
        ;;
      'u '*) DCC_GIT_UNSTAGED=$(( DCC_GIT_UNSTAGED + 1 )) ;;
      '? '*) DCC_GIT_UNTRACKED=$(( DCC_GIT_UNTRACKED + 1 )) ;;
    esac
  done <<<"$1"
  [ $(( DCC_GIT_STAGED + DCC_GIT_UNSTAGED + DCC_GIT_UNTRACKED )) -gt 0 ] && DCC_GIT_DIRTY=1
  return 0
}

dcc_git_collect() { # dcc_git_collect <dir> -> parsed globals + DCC_GIT_ROOT; non-zero outside a repo
  local dir="${1:-}" out root to
  DCC_GIT_BRANCH=""; DCC_GIT_ROOT=""
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  # `command -v` is a builtin, so probing per call costs no fork; if coreutils
  # timeout is missing the git calls below simply run unguarded.
  if command -v timeout >/dev/null 2>&1; then to="timeout 1"; else to=""; fi
  out=$($to git -C "$dir" status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null) || return 1
  [ -n "$out" ] || return 1
  dcc_git_parse "$out"
  [ -n "$DCC_GIT_BRANCH" ] || return 1
  root=$($to git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=""
  dcc_path_norm "$root"
  DCC_GIT_ROOT="$DCC_PATH"
  return 0
}
