#!/usr/bin/env bash
# A single `git status --porcelain=v2 --branch` carries the branch, the upstream
# ahead/behind counts, and per-file staged/unstaged/untracked state, so the
# detail counts cost no extra git invocation. The parser is tested against
# captured output rather than a live repository.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/path.sh"
source "$HERE/../scripts/lib/git.sh"
F="$HERE/fixtures"

dcc_git_parse "$(cat "$F/porcelain-dirty.txt")"
check "branch name"             "$DCC_GIT_BRANCH"    "feat/dcc-statusline"
check "ahead count"             "$DCC_GIT_AHEAD"     "2"
check "behind count"            "$DCC_GIT_BEHIND"    "1"
check "staged file count"       "$DCC_GIT_STAGED"    "2"
check "unstaged file count"     "$DCC_GIT_UNSTAGED"  "1"
check "untracked entry count"   "$DCC_GIT_UNTRACKED" "2"
check "dirty flag is set"       "$DCC_GIT_DIRTY"     "1"

dcc_git_parse "$(cat "$F/porcelain-clean.txt")"
check "clean tree: branch"      "$DCC_GIT_BRANCH"    "main"
check "clean tree: no ahead"    "$DCC_GIT_AHEAD"     "0"
check "clean tree: no behind"   "$DCC_GIT_BEHIND"    "0"
check "clean tree: no staged"   "$DCC_GIT_STAGED"    "0"
check "clean tree: not dirty"   "$DCC_GIT_DIRTY"     "0"

dcc_git_parse "$(cat "$F/porcelain-detached.txt")"
check "detached HEAD is labeled"        "$DCC_GIT_BRANCH" "detached"
check "detached HEAD without upstream"  "$DCC_GIT_AHEAD"  "0"
check "detached HEAD still counts work" "$DCC_GIT_DIRTY"  "1"

dcc_git_parse ""
check "empty input yields no branch" "$DCC_GIT_BRANCH" ""

# A directory that is not a repository must fail cleanly, not error out.
tmp="$(mktemp -d)"
if dcc_git_collect "$tmp"; then rc=0; else rc=1; fi
check "collect fails outside a repository"   "$rc" "1"
check "collect leaves no stale branch"       "$DCC_GIT_BRANCH" ""
rmdir "$tmp"

# `git rev-parse --show-toplevel` answers in the drive-letter namespace on Windows
# ("D:/repo") while the dir segment compares against $HOME in the MSYS one, so the
# root has to come back already folded. Skipped where there is no repository.
if dcc_git_collect "$HERE"; then
  case "$DCC_GIT_ROOT" in
    ?:*|*\\*) form="windows" ;;
    /*)       form="msys" ;;
    *)        form="$DCC_GIT_ROOT" ;;
  esac
  check "the git root comes back in one namespace" "$form" "msys"
fi

finish
