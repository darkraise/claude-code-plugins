# dcc-statusline Resize Responsiveness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the status line redraw at the correct width within ~2 seconds of a terminal resize, without increasing its per-minute process cost more than necessary.

**Architecture:** Claude Code never re-runs the status line command on `SIGWINCH`, so the only lever is `refreshInterval`, which drops from 60 to 2. To keep 30 runs a minute affordable, git state moves behind a temp-file cache read entirely with bash builtins, refreshed at most once per 10 seconds — except on event-driven runs, which are detected by a per-session payload fingerprint and always collect fresh.

**Tech Stack:** Bash 4+ (Git Bash on Windows), `jq`, `git`, the plugin's own test harness in `plugins/dcc-statusline/tests/`.

**Spec:** [docs/superpowers/specs/2026-08-09-dcc-statusline-resize-refresh-design.md](../specs/2026-08-09-dcc-statusline-resize-refresh-design.md)

## Global Constraints

- Every path in this plan is relative to the repo root `D:/Repositories/Personal/claude-code-plugins`. Plugin files live under `plugins/dcc-statusline/`.
- **The render path may not add forks.** `scripts/statusline.sh` declares a process budget in its header: one `jq`, two `git`, plus `timeout` wrappers. A cache hit must add zero processes. That rules out `$(...)`, `stat`, `date`, `mv`, `touch`, `md5sum`, and `mkdir` on the hot path. Use parameter expansion, `read`, `printf -v`, and `printf '%(%s)T'`.
- `mkdir -p` on the cache directory is permitted because it is guarded by `[ -d ... ] ||`, so it forks once per machine boot rather than once per render.
- Scripts start with `#!/usr/bin/env bash` and `set -uo pipefail`. Under `set -u`, every global a function might read must be pre-declared at file scope.
- Comments follow the repo style: explain *why* a non-obvious constraint exists, never *what* the line does.
- Commit messages: `<type>(<scope>): <subject>`, imperative, subject ≤50 chars. Scope is `statusline`.
- Run `bash plugins/dcc-statusline/tests/run-all.sh` before each commit. `run-all.sh` globs `*.test.sh`, so a new test file needs no registration.
- English only in code, comments, docs, and commits.

---

### Task 1: Lower the refresh interval and have doctor police it

**Files:**
- Modify: `plugins/dcc-statusline/scripts/install.sh:11` (add `DCC_REFRESH`), `:66-69` (`dcc_install_one`), `:155-162` (the doctor account loop)
- Test: `plugins/dcc-statusline/tests/install.test.sh:89-90` and a new block before `# --- version agreement`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `DCC_REFRESH`, a shell variable in `install.sh` holding the string `2`. Both the writer and the checker read it so they cannot drift.

- [ ] **Step 1: Update the existing interval assertion to fail**

In `plugins/dcc-statusline/tests/install.test.sh`, change the assertion at line 89-90 from `"60"` to `"2"`:

```bash
check "install sets a refresh interval" \
  "$(jq -r '.statusLine.refreshInterval' "$fake/.claude-alt/settings.json")" "2"
```

- [ ] **Step 2: Add the failing doctor assertions**

In the same file, insert this block immediately before the `# --- version agreement` comment (currently line 192). It reuses the `doctor_run` helper defined at line 170 and the `$fake` accounts created at the top of the file.

```bash
# --- doctor: refresh interval drift ------------------------------------------
# A stale refreshInterval is invisible: everything renders correctly, just
# seconds after the terminal was resized. Only doctor can surface it.
printf '{"statusLine":{"type":"command","command":"x","refreshInterval":60}}\n' \
  > "$fake/.claude-alt/settings.json"
doc="$(doctor_run "")"
check "doctor names an account with a stale refresh interval" \
  "$(printf '%s\n' "$doc" | grep -c "warn - $fake/.claude-alt has refreshInterval 60")" "1"

printf '{"statusLine":{"type":"command","command":"x","refreshInterval":2}}\n' \
  > "$fake/.claude-alt/settings.json"
doc="$(doctor_run "")"
check "doctor is silent when the refresh interval is current" \
  "$(printf '%s\n' "$doc" | grep -c 'has refreshInterval')" "0"

# An entry with no refreshInterval at all predates the key and must be caught.
printf '{"statusLine":{"type":"command","command":"x"}}\n' \
  > "$fake/.claude-alt/settings.json"
doc="$(doctor_run "")"
check "doctor names an account with no refresh interval" \
  "$(printf '%s\n' "$doc" | grep -c "warn - $fake/.claude-alt has refreshInterval unset")" "1"
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/install.test.sh`
Expected: FAIL on `install sets a refresh interval` (want `2`, got `60`) and on all three new doctor checks (want `1`/`0`, got `0`/`1` respectively).

- [ ] **Step 4: Add the shared constant**

In `plugins/dcc-statusline/scripts/install.sh`, immediately after line 11 (`DCC_COMMAND=...`), add:

```bash
# Terminal resize is not one of Claude Code's status line update triggers, so a
# resized terminal keeps its old layout until the next run. The refresh timer is
# the only thing that bounds that lag. Doctor compares against this same value,
# so the writer and the checker cannot drift apart.
DCC_REFRESH=2
```

- [ ] **Step 5: Write the interval through the constant**

Replace the body of `dcc_install_one` (lines 66-69):

```bash
dcc_install_one() { # dcc_install_one <config-dir>
  _dcc_edit_settings "$1" \
    '.statusLine = {type:"command",command:"'"$DCC_COMMAND"'",padding:0,refreshInterval:'"$DCC_REFRESH"'}'
}
```

- [ ] **Step 6: Add the doctor check**

In `dcc_doctor`, replace the account loop (lines 155-162) with:

```bash
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if jq -e '.statusLine' "$d/settings.json" >/dev/null 2>&1; then
      printf 'ok   - installed in %s\n' "$d"
      iv="$(jq -r '.statusLine.refreshInterval // "unset"' "$d/settings.json" 2>/dev/null)"
      if [ "$iv" != "$DCC_REFRESH" ]; then
        printf 'warn - %s has refreshInterval %s; a resize will lag. Run: /dcc-statusline install\n' \
          "$d" "$iv"
      fi
    else
      printf 'warn - not installed in %s\n' "$d"
    fi
  done < <(dcc_account_dirs)
```

Add `iv` to the `local` declaration on line 107 so `set -u` and the function's existing style are both satisfied:

```bash
  local rc=0 d cfg key probe rendered dcc_m dcc_w iv
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash plugins/dcc-statusline/tests/install.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 8: Run the whole suite**

Run: `bash plugins/dcc-statusline/tests/run-all.sh`
Expected: every file reports `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add plugins/dcc-statusline/scripts/install.sh plugins/dcc-statusline/tests/install.test.sh
git commit -m "feat(statusline): refresh every 2s so resizes land"
```

---

### Task 2: Cache git state in a temp file

**Files:**
- Create: `plugins/dcc-statusline/scripts/lib/cache.sh`
- Create: `plugins/dcc-statusline/tests/cache.test.sh`
- Modify: `plugins/dcc-statusline/tests/lib.sh` (add the shared git stub helper)

**Interfaces:**
- Consumes: `dcc_git_collect <dir>` from `scripts/lib/git.sh` — returns 0 inside a repository and sets `DCC_GIT_BRANCH`, `DCC_GIT_AHEAD`, `DCC_GIT_BEHIND`, `DCC_GIT_STAGED`, `DCC_GIT_UNSTAGED`, `DCC_GIT_UNTRACKED`, `DCC_GIT_DIRTY`, `DCC_GIT_ROOT`; returns non-zero outside one. Also `DCC_NOW`, the epoch second `statusline.sh` computes before any git work.
- Produces:
  - `dcc_git_cached <dir>` — same globals and same return contract as `dcc_git_collect`, served from cache when possible.
  - `dcc_cache_dir` → sets `DCC_CACHE_DIR` (empty when unusable).
  - `dcc_cache_key <string>` → sets `DCC_CACHE_KEY`.
  - `DCC_CACHE_TTL` (default 10) and `DCC_CACHE_FORCE` (0/1; Task 3 sets it).
  - `DCC_CACHE_HOME`, a test-only override for the temp root.
  - `dcc_stub_git <bindir>` in `tests/lib.sh` — writes a counting git stub and prepends `<bindir>` to `PATH`. Task 4's end-to-end test uses the same helper.

- [ ] **Step 1: Add the shared git stub helper**

Append to `plugins/dcc-statusline/tests/lib.sh`:

```bash
# Test-only: a git that records every invocation and answers from fixtures, so a
# test can assert how many times the render path actually shelled out. The caller
# exports GIT_CALLS, GIT_PORCELAIN and GIT_ROOT to point it at its own files.
dcc_stub_git() { # dcc_stub_git <bin-dir>
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/git" <<'SH'
#!/usr/bin/env bash
printf 'call\n' >> "$GIT_CALLS"
case " $* " in
  *" --porcelain=v2 "*)  cat "$GIT_PORCELAIN" ;;
  *" --show-toplevel "*) printf '%s\n' "$GIT_ROOT" ;;
esac
SH
  chmod +x "$bin/git"
  PATH="$bin:$PATH"
}
```

- [ ] **Step 2: Write the failing test**

Create `plugins/dcc-statusline/tests/cache.test.sh`:

```bash
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/cache.test.sh`
Expected: FAIL immediately — `scripts/lib/cache.sh: No such file or directory`.

- [ ] **Step 4: Write the implementation**

Create `plugins/dcc-statusline/scripts/lib/cache.sh`:

```bash
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
# Set by dcc_cache_event, added below in Task 3. Declared here so a render that
# never calls it still has a defined value under set -u.
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/cache.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 6: Run the whole suite**

Run: `bash plugins/dcc-statusline/tests/run-all.sh`
Expected: every file reports `0 failed`. Nothing sources `cache.sh` yet, so no other file changes behavior.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/cache.sh plugins/dcc-statusline/tests/cache.test.sh \
        plugins/dcc-statusline/tests/lib.sh
git commit -m "feat(statusline): cache git state between renders"
```

---

### Task 3: Force a fresh collect on event-driven runs

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/cache.sh` (append `dcc_cache_event`)
- Modify: `plugins/dcc-statusline/scripts/lib/jq-prog.sh:174` area (add `P_SESSION`)
- Modify: `plugins/dcc-statusline/scripts/lib/config.sh:10-24` (declare `P_SESSION`)
- Test: `plugins/dcc-statusline/tests/cache.test.sh` (append), `plugins/dcc-statusline/tests/config.test.sh` (append)

**Interfaces:**
- Consumes: `dcc_cache_dir`/`dcc_cache_key` and the `DCC_CACHE_FORCE` global from Task 2. `P_CTX_TOK` and `P_COST`, already produced by `dcc_parse_all`.
- Produces: `dcc_cache_event` — sets `DCC_CACHE_FORCE` to 1 when this run's payload differs from the previous run's for the same session, 0 otherwise. `P_SESSION`, the payload's `session_id`.

Why this exists: with a 10-second TTL, the git segment could show ten-second-old counts immediately after Claude finished editing files. An event-driven run is distinguishable from an idle timer tick because its payload has advanced — token count and cost move with every assistant message. The fingerprint is stored per session, because two sessions open on the same repository would otherwise invalidate each other's fingerprint on every tick and the TTL would never apply.

- [ ] **Step 1: Write the failing tests**

Append to `plugins/dcc-statusline/tests/cache.test.sh`, immediately before the `rm -rf "$tmp"` line:

```bash
# --- event-driven runs bypass the TTL -----------------------------------------
export GIT_PORCELAIN="$HERE/fixtures/porcelain-dirty.txt"
P_SESSION="sess-1"; P_CTX_TOK="1000"; P_COST="0.50"

dcc_cache_event
check "a session seen for the first time forces a refresh" "$DCC_CACHE_FORCE" "1"

: > "$GIT_CALLS"
DCC_NOW=3000
dcc_git_cached "$tmp/repo"
check "a forced run invokes git despite an empty cache" "$(calls)" "2"

dcc_cache_event
check "an unchanged payload does not force a refresh" "$DCC_CACHE_FORCE" "0"
: > "$GIT_CALLS"
DCC_NOW=3001
dcc_git_cached "$tmp/repo"
check "an idle tick serves the cache" "$(calls)" "0"

P_CTX_TOK="2000"
dcc_cache_event
check "an advanced token count forces a refresh" "$DCC_CACHE_FORCE" "1"
: > "$GIT_CALLS"
DCC_NOW=3002
dcc_git_cached "$tmp/repo"
check "a forced run refreshes inside the TTL" "$(calls)" "2"

# A second session must keep its own fingerprint, or two sessions on one
# repository force each other to refresh on every single tick.
P_SESSION="sess-2"
dcc_cache_event
check "a second session starts with its own fingerprint" "$DCC_CACHE_FORCE" "1"
dcc_cache_event
check "the second session then settles" "$DCC_CACHE_FORCE" "0"
P_SESSION="sess-1"
dcc_cache_event
check "the first session is undisturbed by the second" "$DCC_CACHE_FORCE" "0"
```

Append to `plugins/dcc-statusline/tests/config.test.sh`, at the end of the file before its `finish` call:

```bash
# session_id keys the per-session cache fingerprint, so the parse has to carry it.
dcc_parse_all "$(cat "$HERE/fixtures/full.json")" /dev/null /dev/null
check "the parse carries the session id" "$P_SESSION" "abc123"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash plugins/dcc-statusline/tests/cache.test.sh`
Expected: FAIL with `dcc_cache_event: command not found` on the first new check.

Run: `bash plugins/dcc-statusline/tests/config.test.sh`
Expected: FAIL — `P_SESSION` is empty, want `abc123`. If it aborts with `P_SESSION: unbound variable` instead, that is the same failure and Step 4 fixes it.

- [ ] **Step 3: Add the fingerprint function**

Append to `plugins/dcc-statusline/scripts/lib/cache.sh`:

```bash
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
```

- [ ] **Step 4: Declare and parse the session id**

In `plugins/dcc-statusline/scripts/lib/config.sh`, add after line 10 (`P_EMAIL=""`):

```bash
P_SESSION=""
```

In `plugins/dcc-statusline/scripts/lib/jq-prog.sh`, add a line after the `P_EMAIL` entry (line 167):

```
  @sh "P_SESSION=\(str(($p.session_id)? // null))",
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash plugins/dcc-statusline/tests/cache.test.sh`
Expected: PASS, `0 failed`.

Run: `bash plugins/dcc-statusline/tests/config.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 6: Run the whole suite**

Run: `bash plugins/dcc-statusline/tests/run-all.sh`
Expected: every file reports `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/cache.sh plugins/dcc-statusline/scripts/lib/jq-prog.sh \
        plugins/dcc-statusline/scripts/lib/config.sh plugins/dcc-statusline/tests/cache.test.sh \
        plugins/dcc-statusline/tests/config.test.sh
git commit -m "feat(statusline): refresh git on event-driven runs"
```

---

### Task 4: Wire the cache into the render path, document, release

**Files:**
- Modify: `plugins/dcc-statusline/scripts/statusline.sh:4-6` (budget comment), `:19-27` (sources), `:85-87` (git call)
- Modify: `plugins/dcc-statusline/scripts/VERSION`, `plugins/dcc-statusline/.claude-plugin/plugin.json`
- Modify: `plugins/dcc-statusline/README.md`
- Test: `plugins/dcc-statusline/tests/e2e.test.sh` (append)

**Interfaces:**
- Consumes: `dcc_git_cached <dir>` and `dcc_cache_event` from Tasks 2 and 3.
- Produces: nothing further.

- [ ] **Step 1: Write the failing end-to-end test**

Append to `plugins/dcc-statusline/tests/e2e.test.sh`, before its `finish` call. That file already defines `HERE`, `SCRIPT` and `F="$HERE/fixtures"` at the top, and exports a frozen `DCC_NOW=1785886800`, which the subshell inherits — so both renders below share one clock and land inside the TTL.

```bash
# --- the render path goes through the cache -----------------------------------
# Proving it end to end rather than by unit test: the wiring is the whole point,
# and a render that quietly still calls dcc_git_collect would pass every test in
# cache.test.sh while costing two git calls every two seconds in the field.
cachetmp="$(mktemp -d)"

render_twice() { # -> the git call count across two identical renders
  (
    dcc_stub_git "$cachetmp/bin"
    export PATH
    export DCC_CACHE_HOME="$cachetmp/cache"
    export GIT_CALLS="$cachetmp/calls"
    export GIT_PORCELAIN="$HERE/fixtures/porcelain-dirty.txt"
    export GIT_ROOT="$cachetmp"
    : > "$GIT_CALLS"
    # The fixture's cwd is a path on the author's machine. Repointing it at the
    # temp dir keeps the assertion about caching rather than about which
    # directories happen to exist. The default segment list includes "dir" and
    # "git", so the render does reach the git path.
    payload="$(jq -c --arg d "$cachetmp" '.workspace.current_dir = $d | .cwd = $d' "$F/full.json")"
    for _ in 1 2; do
      printf '%s' "$payload" \
        | DCC_STATUSLINE_CONFIG=/dev/null bash "$SCRIPT" >/dev/null 2>&1
    done
    wc -l < "$GIT_CALLS" | tr -d ' '
  )
}

check "two identical renders share one git collect" "$(render_twice)" "2"
rm -rf "$cachetmp"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/e2e.test.sh`
Expected: FAIL — want `2`, got `4`, because each render still collects independently.

- [ ] **Step 3: Source the cache and call through it**

In `plugins/dcc-statusline/scripts/statusline.sh`, add after line 26 (`source "$DCC_DIR/lib/git.sh"`):

```bash
source "$DCC_DIR/lib/cache.sh"
```

Replace the git collection block (lines 85-87):

```bash
  # Collect git state only when a git segment is actually configured.
  case " $names1 $names2 " in
    *" git "*|*" dir "*) dcc_cache_event; dcc_git_cached "$P_CWD" || true ;;
  esac
```

- [ ] **Step 4: Update the process budget comment**

Replace lines 5-6 of `plugins/dcc-statusline/scripts/statusline.sh`:

```bash
# Process budget: one jq on a cache hit, plus two git and the timeout wrappers
# when the git cache misses or the payload shows an event-driven run. Nothing in
# this file may use $(...) -- see the note in lib/color.sh.
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/e2e.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 6: Bump the version**

`plugins/dcc-statusline/scripts/VERSION` becomes:

```
0.6.0
```

`plugins/dcc-statusline/.claude-plugin/plugin.json` — set `"version": "0.6.0"`. `install.test.sh` asserts these two agree; the SessionStart sync hook fires on the difference between the plugin's VERSION and the installed copy's, so this bump is what pushes the new scripts onto each account.

- [ ] **Step 7: Document the behavior**

In `plugins/dcc-statusline/README.md`, in the section that describes what install writes to `settings.json` (around line 130), add:

```markdown
The entry sets `refreshInterval: 2`. Claude Code does not re-run a status line
command when the terminal is resized -- resize is not one of its update triggers
-- so the refresh timer is what bounds how long a resized terminal keeps its old
layout. Two seconds is the trade: any longer is visible, any shorter buys
nothing.

To keep that rate affordable, git state is cached under
`$TMPDIR/dcc-statusline/` for ten seconds, and refreshed immediately whenever
the session payload shows a new assistant message rather than an idle timer
tick. Deleting that directory is safe and forces a fresh collect.
```

Add to the README's troubleshooting list:

```markdown
- **The status line does not follow a terminal resize.** The account's
  `refreshInterval` has drifted from 2. Run `/dcc-statusline doctor` to confirm,
  then `/dcc-statusline install --all`.
```

- [ ] **Step 8: Run the whole suite and validate the manifest**

Run: `bash plugins/dcc-statusline/tests/run-all.sh`
Expected: every file reports `0 failed`.

Run: `claude plugin validate .` from the repo root.
Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add plugins/dcc-statusline/scripts/statusline.sh plugins/dcc-statusline/scripts/VERSION \
        plugins/dcc-statusline/.claude-plugin/plugin.json plugins/dcc-statusline/README.md \
        plugins/dcc-statusline/tests/e2e.test.sh
git commit -m "feat(statusline): render through the git cache"
```

- [ ] **Step 10: Install to every account and verify in the field**

```bash
bash plugins/dcc-statusline/scripts/install.sh install --all
bash plugins/dcc-statusline/scripts/install.sh doctor
```

Expected: `installed:` for each of `~/.claude`, `~/.claude-alt`, `~/.claude-alt2`; doctor reports no `refreshInterval` warning and no `FAIL` line.

Then resize the terminal and confirm the frame's right wall follows within roughly two seconds.
