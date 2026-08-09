#!/usr/bin/env bash
# The cache exists so a 2s refresh interval does not mean a `git status` every
# two seconds. Every assertion here is about that: what it serves, when it
# refuses to, and how many git invocations each case costs. Git is stubbed with
# a script earlier on PATH that appends one line per call to a counter file.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/path.sh"
source "$HERE/../scripts/lib/git.sh"
source "$HERE/../scripts/lib/cache.sh"

tmp="$(mktemp -d)"
export DCC_CACHE_HOME="$tmp/cachehome"
mkdir -p "$tmp/repo" "$tmp/plain"

dcc_stub_git "$tmp/bin"
export PATH
export GIT_CALLS="$tmp/calls"
export GIT_PORCELAIN="$HERE/fixtures/porcelain-dirty.txt"
export GIT_ROOT="$tmp/repo"

calls() { printf '%s' "$(wc -l < "$GIT_CALLS" | tr -d ' ')"; }

# --- a cold cache collects and stores -----------------------------------------
: > "$GIT_CALLS"
DCC_NOW=1000
dcc_git_cached "$tmp/repo"; rc=$?
check "a cold read succeeds inside a repository" "$rc" "0"
check "a cold read returns the branch"           "$DCC_GIT_BRANCH" "feat/dcc-statusline"
check "a cold read counts staged files"          "$DCC_GIT_STAGED" "2"
check "a cold read invokes git twice"            "$(calls)" "2"
# dcc_path_norm may fold the root, so the warm read is compared against whatever
# a fresh collect produced rather than against the raw path handed to the stub.
want_root="$DCC_GIT_ROOT"

# --- a warm cache serves without forking --------------------------------------
: > "$GIT_CALLS"
DCC_GIT_BRANCH="wiped"; DCC_GIT_STAGED=99
DCC_NOW=1005
dcc_git_cached "$tmp/repo"; rc=$?
check "a warm read succeeds"                "$rc" "0"
check "a warm read restores the branch"     "$DCC_GIT_BRANCH" "feat/dcc-statusline"
check "a warm read restores the counts"     "$DCC_GIT_STAGED" "2"
check "a warm read restores the root"       "$DCC_GIT_ROOT" "$want_root"
check "a warm read invokes git zero times"  "$(calls)" "0"

# --- an expired stamp refreshes -----------------------------------------------
: > "$GIT_CALLS"
DCC_NOW=1020
dcc_git_cached "$tmp/repo"
check "a stamp older than the TTL refreshes" "$(calls)" "2"

# --- a torn file is not trusted -----------------------------------------------
# A concurrent writer can in principle leave a file with no sentinel. Serving it
# would render counts from a half-written cache, which looks like real data.
dcc_cache_dir; dcc_cache_key "$tmp/repo"
f="$DCC_CACHE_DIR/git-$DCC_CACHE_KEY"
printf '1020\nrepo=1\nbranch=torn\nstaged=77\n' > "$f"
: > "$GIT_CALLS"
DCC_NOW=1021
dcc_git_cached "$tmp/repo"
check "a cache with no sentinel falls back to git" "$(calls)" "2"
check "a torn cache leaks no branch"               "$DCC_GIT_BRANCH" "feat/dcc-statusline"
check "a torn cache leaks no counts"               "$DCC_GIT_STAGED" "2"

# --- a non-repository caches its negative answer ------------------------------
export GIT_PORCELAIN=/dev/null
: > "$GIT_CALLS"
DCC_NOW=2000
if dcc_git_cached "$tmp/plain"; then rc=0; else rc=1; fi
check "a non-repository returns non-zero"      "$rc" "1"
check "a non-repository costs one git call"    "$(calls)" "1"

: > "$GIT_CALLS"
DCC_NOW=2001
if dcc_git_cached "$tmp/plain"; then rc=0; else rc=1; fi
check "a cached negative is still non-zero"    "$rc" "1"
check "a cached negative invokes no git"       "$(calls)" "0"
check "a cached negative reports no branch"    "$DCC_GIT_BRANCH" ""

# --- the key survives a Windows-shaped path -----------------------------------
dcc_cache_key 'D:\Repos\my repo'
case "$DCC_CACHE_KEY" in
  *[/:\\\ ]*) form="unsafe" ;;
  *)          form="safe" ;;
esac
check "a key holds no path or space characters" "$form" "safe"

rm -rf "$tmp"
finish
