#!/usr/bin/env bash
set -uo pipefail
# Git state cached to a temp file. The status line refreshes every two seconds so
# that a terminal resize is picked up promptly, which would otherwise mean a
# `git status` every two seconds in every open session.
#
# Nothing on the read path may fork: the render path's process budget is one jq
# and two git calls, and a cache hit has to fit inside it with room to spare.
# That rules out stat, date and mv -- the stamp is stored in the file and
# compared against bash's own %(%s)T, and the write is a single printf redirect.

DCC_CACHE_TTL="${DCC_CACHE_TTL:-10}"
DCC_CACHE_DIR=""
DCC_CACHE_KEY=""
DCC_CACHE_REPO=0
# Forces a refresh past a warm cache. Pre-declared because a render that never
# sets it would otherwise abort under set -u.
DCC_CACHE_FORCE=0

dcc_cache_dir() { # -> DCC_CACHE_DIR, empty when the directory cannot be used
  local root="${DCC_CACHE_HOME:-${TMPDIR:-/tmp}}"
  root="${root%/}"
  DCC_CACHE_DIR="$root/dcc-statusline"
  # Guarded so the fork happens once per machine, not once per render.
  [ -d "$DCC_CACHE_DIR" ] || mkdir -p "$DCC_CACHE_DIR" 2>/dev/null || DCC_CACHE_DIR=""
}

dcc_cache_key() { # dcc_cache_key <string> -> DCC_CACHE_KEY
  local s="${1:-}"
  s="${s//\\/_}"
  s="${s//\//_}"
  s="${s//:/_}"
  s="${s// /_}"
  # Windows still enforces a path limit that a deep repository path can breach.
  # The tail is kept rather than the head: sibling directories differ at the end.
  [ "${#s}" -gt 120 ] && s="${s: -120}"
  DCC_CACHE_KEY="${s:-_}"
}

_dcc_cache_read() { # _dcc_cache_read <file> -> 0 when a complete, fresh entry loaded
  local file="$1" line k v stamp="" sealed=0 age
  [ -r "$file" ] || return 1
  while IFS= read -r line; do
    if [ -z "$stamp" ]; then stamp="$line"; continue; fi
    if [ "$line" = "END" ]; then sealed=1; break; fi
    k="${line%%=*}"; v="${line#*=}"
    case "$k" in
      repo)      DCC_CACHE_REPO="$v" ;;
      branch)    DCC_GIT_BRANCH="$v" ;;
      ahead)     DCC_GIT_AHEAD="$v" ;;
      behind)    DCC_GIT_BEHIND="$v" ;;
      staged)    DCC_GIT_STAGED="$v" ;;
      unstaged)  DCC_GIT_UNSTAGED="$v" ;;
      untracked) DCC_GIT_UNTRACKED="$v" ;;
      dirty)     DCC_GIT_DIRTY="$v" ;;
      root)      DCC_GIT_ROOT="$v" ;;
    esac
  done < "$file"
  # No sentinel means the file was truncated or caught mid-write. Whatever was
  # loaded above is discarded by the caller, which resets before collecting.
  [ "$sealed" -eq 1 ] || return 1
  case "$stamp" in ''|*[!0-9]*) return 1 ;; esac
  age=$(( 10#${DCC_NOW:-0} - 10#$stamp ))
  [ "$age" -ge 0 ] && [ "$age" -lt "$DCC_CACHE_TTL" ]
}

_dcc_cache_write() { # _dcc_cache_write <file> <repo-flag>
  local file="$1" repo="$2" out
  printf -v out '%s\nrepo=%s\nbranch=%s\nahead=%s\nbehind=%s\nstaged=%s\nunstaged=%s\nuntracked=%s\ndirty=%s\nroot=%s\nEND\n' \
    "${DCC_NOW:-0}" "$repo" "$DCC_GIT_BRANCH" "$DCC_GIT_AHEAD" "$DCC_GIT_BEHIND" \
    "$DCC_GIT_STAGED" "$DCC_GIT_UNSTAGED" "$DCC_GIT_UNTRACKED" "$DCC_GIT_DIRTY" \
    "$DCC_GIT_ROOT"
  # One redirect rather than write-then-mv: mv is a fork. A few hundred bytes go
  # out in a single write, and the sentinel above makes any interleaving that
  # does slip through self-healing rather than visible.
  printf '%s' "$out" > "$file" 2>/dev/null || true
}

dcc_git_cached() { # dcc_git_cached <dir> -> git globals; non-zero outside a repository
  local dir="${1:-}" file
  [ -n "$dir" ] || return 1
  dcc_cache_dir
  [ -n "$DCC_CACHE_DIR" ] || { dcc_git_collect "$dir"; return $?; }
  dcc_cache_key "$dir"
  file="$DCC_CACHE_DIR/git-$DCC_CACHE_KEY"
  DCC_CACHE_REPO=0
  if [ "$DCC_CACHE_FORCE" -eq 0 ] && _dcc_cache_read "$file"; then
    [ "$DCC_CACHE_REPO" = "1" ] && return 0
    return 1
  fi
  # A partial read may have assigned some of these, and dcc_git_collect only
  # clears branch and root before it can bail out. Reset everything so a
  # rejected cache cannot survive as counts next to a freshly read branch.
  DCC_GIT_BRANCH=""; DCC_GIT_ROOT=""
  DCC_GIT_AHEAD=0; DCC_GIT_BEHIND=0; DCC_GIT_STAGED=0
  DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=0; DCC_GIT_DIRTY=0
  if dcc_git_collect "$dir"; then
    _dcc_cache_write "$file" 1
    return 0
  fi
  _dcc_cache_write "$file" 0
  return 1
}

dcc_cache_event() { # -> DCC_CACHE_FORCE=1 when the payload advanced since the last run
  local file fp prev=""
  DCC_CACHE_FORCE=0
  dcc_cache_dir
  # With nowhere to remember the previous payload, every run is treated as an
  # event: correct, just not cheap.
  [ -n "$DCC_CACHE_DIR" ] || { DCC_CACHE_FORCE=1; return 0; }
  dcc_cache_key "${P_SESSION:-nosession}"
  file="$DCC_CACHE_DIR/fp-$DCC_CACHE_KEY"
  fp="${P_CTX_TOK:-}|${P_COST:-}"
  [ -r "$file" ] && read -r prev < "$file"
  [ "$fp" = "$prev" ] && return 0
  DCC_CACHE_FORCE=1
  printf '%s\n' "$fp" > "$file" 2>/dev/null || true
  return 0
}
