# dcc-telegram-notify Rename and Event Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the `telegram-notify` plugin to `dcc-telegram-notify` (migrating its config home) and add a `TELEGRAM_EVENTS` setting that selects which notifications send, defaulting to the blocked-on-you set only.

**Architecture:** The plugin is a single bash script driven by three Claude Code hooks. The rename is mechanical file and manifest edits plus a one-time `mv` of the config home performed at script load. The event filter is two new functions near the top of the script — `parse_events` (normalizes the config into a canonical set once at load) and `event_enabled` (a set-membership test) — consulted immediately before each `send_message` call in `main()`, plus one early exit in the `Stop` branch that avoids a wasted LLM call.

**Tech Stack:** bash, `jq`, `curl`, Claude Code plugin manifests (JSON). Tests are plain bash scripts that `source` the engine script and assert on function output; one test drives the script end to end with a `curl` stub on `PATH`.

Spec: `docs/superpowers/specs/2026-08-08-dcc-telegram-notify-events-design.md`

## Global Constraints

- Plugin name is `dcc-telegram-notify` in all three places that must agree: directory name, `plugins/dcc-telegram-notify/.claude-plugin/plugin.json` `name`, and the `.claude-plugin/marketplace.json` entry.
- `claude plugin validate .` must pass at the repo root before any manifest change is committed. CI runs the same command.
- Environment variable names keep their `TELEGRAM_` prefix. Do **not** rename `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `TELEGRAM_NOTIFY_HOME`, `TELEGRAM_NOTIFY_ENV`, or any other existing variable. Only the *default value* of `TELEGRAM_NOTIFY_HOME` changes.
- The notification path must never disturb a Claude session: every new failure mode is swallowed (`|| true`, `2>/dev/null`) rather than propagated.
- The canonical token set is exactly: `permission`, `input`, `stop-question`, `stop-done`, `stop-reply`. Aliases: `stop`, `all`, `none`.
- The default event set is exactly `permission,input,stop-question`.
- Commit messages follow `<type>(<scope>): <subject>`, subject ≤50 chars, imperative, no trailing period. Scope is `telegram-notify` for task 1 and `dcc-telegram-notify` afterwards.
- English only in code, comments, docs, and commits.
- All work happens on the existing branch `feat/dcc-telegram-notify-events`.

## File Structure

Paths below are relative to the repo root `D:/Repositories/Personal/claude-code-plugins`.

**Renamed (via `git mv`, so history follows):**

| From | To |
|---|---|
| `plugins/telegram-notify/` | `plugins/dcc-telegram-notify/` |
| `plugins/dcc-telegram-notify/scripts/telegram-notify.sh` | `.../scripts/dcc-telegram-notify.sh` |
| `plugins/dcc-telegram-notify/commands/telegram-notify.md` | `.../commands/dcc-telegram-notify.md` |

**Modified:**

- `.claude-plugin/marketplace.json` — plugin `name` and `source`.
- `plugins/dcc-telegram-notify/.claude-plugin/plugin.json` — `name`, `version`, `homepage`.
- `plugins/dcc-telegram-notify/hooks/hooks.json` — the three `command` strings.
- `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` — the whole feature lives here: home resolution and migration, the event parser, the gates in `main()`, and the seeded config template.
- `plugins/dcc-telegram-notify/tests/open_editor.test.sh`, `tests/pending_action.test.sh` — script path and a hermetic `TELEGRAM_NOTIFY_HOME`.
- `plugins/dcc-telegram-notify/README.md`, `DESIGN.md`, `telegram.env.example`, `.gitignore` — prose and paths.
- `README.md` (repo root) — plugin table entry.

**Created:**

- `plugins/dcc-telegram-notify/tests/run-all.sh` — runs every `*.test.sh`.
- `plugins/dcc-telegram-notify/tests/migration.test.sh` — config home migration.
- `plugins/dcc-telegram-notify/tests/events.test.sh` — token parser.
- `plugins/dcc-telegram-notify/tests/gating.test.sh` — end-to-end send/no-send.

**Responsibility boundary:** the engine script stays one file. It is ~640 lines of tightly coupled hook handling and the existing codebase pattern is one script per plugin behavior; splitting it is out of scope for this work.

---

### Task 1: Rename the plugin to dcc-telegram-notify

Purely mechanical. No behavior changes — the config home stays `~/.telegram-notify` until Task 2. Documentation is updated here too so the rename lands complete in one reviewable change.

**Files:**
- Rename: `plugins/telegram-notify/` → `plugins/dcc-telegram-notify/`
- Rename: `plugins/dcc-telegram-notify/scripts/telegram-notify.sh` → `scripts/dcc-telegram-notify.sh`
- Rename: `plugins/dcc-telegram-notify/commands/telegram-notify.md` → `commands/dcc-telegram-notify.md`
- Modify: `.claude-plugin/marketplace.json`, `plugins/dcc-telegram-notify/.claude-plugin/plugin.json`, `plugins/dcc-telegram-notify/hooks/hooks.json`, `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh`, `plugins/dcc-telegram-notify/README.md`, `plugins/dcc-telegram-notify/DESIGN.md`, `plugins/dcc-telegram-notify/telegram.env.example`, `plugins/dcc-telegram-notify/.gitignore`, `README.md`
- Test: `plugins/dcc-telegram-notify/tests/open_editor.test.sh`, `tests/pending_action.test.sh`
- Create: `plugins/dcc-telegram-notify/tests/run-all.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the script path `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh`, which every later task edits; `tests/run-all.sh` as the single verification entry point used by every later task.

- [ ] **Step 1: Move the directory and the two renamed files**

```bash
cd /d/Repositories/Personal/claude-code-plugins
git mv plugins/telegram-notify plugins/dcc-telegram-notify
git mv plugins/dcc-telegram-notify/scripts/telegram-notify.sh \
       plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh
git mv plugins/dcc-telegram-notify/commands/telegram-notify.md \
       plugins/dcc-telegram-notify/commands/dcc-telegram-notify.md
```

- [ ] **Step 2: Update the plugin manifest**

In `plugins/dcc-telegram-notify/.claude-plugin/plugin.json`, change exactly three values:

```json
  "name": "dcc-telegram-notify",
  "version": "1.1.0",
  "homepage": "https://github.com/darkraise/claude-code-plugins/tree/main/plugins/dcc-telegram-notify",
```

- [ ] **Step 3: Update the marketplace entry**

In `.claude-plugin/marketplace.json`, in the object whose `name` is `telegram-notify`:

```json
      "name": "dcc-telegram-notify",
      "source": "./plugins/dcc-telegram-notify",
```

Leave `description`, `category`, and `keywords` unchanged.

- [ ] **Step 4: Update the hook command paths**

In `plugins/dcc-telegram-notify/hooks/hooks.json`, all three `command` strings become:

```json
"command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/dcc-telegram-notify.sh\"",
```

- [ ] **Step 5: Run the validator**

```bash
cd /d/Repositories/Personal/claude-code-plugins && claude plugin validate .
```
Expected: passes with no errors. If it reports the old name anywhere, a manifest edit was missed.

- [ ] **Step 6: Update the script's self-references**

In `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` change only these:

The `die` prefix (around line 130):
```bash
die() { echo "dcc-telegram-notify: $*" >&2; exit 1; }
```

Inside `seed_config`'s heredoc, the first comment line and the `TELEGRAM_CHAT_ID` hint:
```
# Telegram notification config for the Claude Code dcc-telegram-notify plugin.
```
```
# Find it with the /dcc-telegram-notify command, or:  dcc-telegram-notify.sh --discover
```

The unknown-option message at the bottom needs no change (it names flags, not the script).

- [ ] **Step 7: Make the two existing tests hermetic and point them at the new script**

In **both** `tests/open_editor.test.sh` and `tests/pending_action.test.sh`, change the `SCRIPT` line and add a home override immediately above the existing `TELEGRAM_NOTIFY_ENV` export.

`tests/open_editor.test.sh`:
```bash
SCRIPT="$HERE/../scripts/dcc-telegram-notify.sh"

# Never touch the real config home: Task 2 adds a load-time migration that would
# otherwise move this machine's actual ~/.telegram-notify during a test run.
export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"   # isolate from the real config/token
```

`tests/pending_action.test.sh`:
```bash
SCRIPT="$HERE/../scripts/dcc-telegram-notify.sh"
FIXTURES="$HERE/fixtures"

# Never touch the real config home: Task 2 adds a load-time migration that would
# otherwise move this machine's actual ~/.telegram-notify during a test run.
export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"
# Isolate from the real config/token, and keep the flush-wait poll short.
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"
export TELEGRAM_PENDING_TRIES=2
```

- [ ] **Step 8: Create the test runner**

Create `plugins/dcc-telegram-notify/tests/run-all.sh`:

```bash
#!/usr/bin/env bash
# Runs every test file. Exits non-zero if any file fails.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$HERE"/*.test.sh; do
  printf '\n=== %s ===\n' "$(basename "$t")"
  bash "$t" || rc=1
done
exit "$rc"
```

Then mark it executable:
```bash
git update-index --add --chmod=+x plugins/dcc-telegram-notify/tests/run-all.sh
```

- [ ] **Step 9: Run the tests**

```bash
bash plugins/dcc-telegram-notify/tests/run-all.sh
```
Expected: both existing files report `0 failed` and the runner exits 0.

- [ ] **Step 10: Update documentation prose**

Replace every user-facing occurrence of the old names. In `plugins/dcc-telegram-notify/README.md`:
- Title line: `# dcc-telegram-notify — a Claude Code plugin`
- Install command: `/plugin install dcc-telegram-notify@darkraise`
- Every `/telegram-notify <sub>` becomes `/dcc-telegram-notify <sub>`
- Every `scripts/telegram-notify.sh` becomes `scripts/dcc-telegram-notify.sh`

In `plugins/dcc-telegram-notify/commands/dcc-telegram-notify.md`:
- Body opening: ``You manage the **dcc-telegram-notify** plugin's configuration.``
- Every `${CLAUDE_PLUGIN_ROOT}/scripts/telegram-notify.sh` becomes `${CLAUDE_PLUGIN_ROOT}/scripts/dcc-telegram-notify.sh` (7 occurrences)

In `plugins/dcc-telegram-notify/telegram.env.example`, the `TELEGRAM_CHAT_ID` hint line:
```
# Find it with the /dcc-telegram-notify command, or:  dcc-telegram-notify.sh --discover
```

In `plugins/dcc-telegram-notify/.gitignore`, `DESIGN.md`, and the repo-root `README.md`, update every `telegram-notify` that names the plugin, its command, or its script. Do **not** touch dated documents under `docs/` — they are historical records.

- [ ] **Step 11: Verify no stale references remain**

```bash
cd /d/Repositories/Personal/claude-code-plugins
rg -n --hidden -g '!.git' -g '!docs/**' 'telegram-notify' | rg -v 'dcc-telegram-notify'
```
Expected: only lines where `telegram-notify` is part of a path that is legitimately still old — at this point that is `~/.telegram-notify` (the config home, renamed in Task 2) and the `telegram.env` filename. Anything naming the *plugin*, *command*, or *script* must already read `dcc-`.

- [ ] **Step 12: Commit**

```bash
git add -A plugins/dcc-telegram-notify .claude-plugin/marketplace.json README.md
git commit -m "refactor(telegram-notify): rename plugin to dcc-telegram-notify" -m "The marketplace requires every plugin name to start with dcc-. Renames the
directory, manifest name, marketplace entry, slash command, and engine script,
and adds a test runner. The config home is unchanged for now."
```

---

### Task 2: Migrate the config home to ~/.dcc-telegram-notify

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh:13-23` (the home resolution block)
- Test: `plugins/dcc-telegram-notify/tests/migration.test.sh` (create)

**Interfaces:**
- Consumes: the renamed script from Task 1.
- Produces: `migrate_home()` — takes no arguments, reads the globals `TELEGRAM_NOTIFY_HOME` (already resolved to the new default) and `TELEGRAM_NOTIFY_HOME_WAS_SET`, returns 0 always. Later tasks do not call it.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-telegram-notify/tests/migration.test.sh`:

```bash
#!/usr/bin/env bash
# Tests for migrate_home(): the plugin rename moved the config home from
# ~/.telegram-notify to ~/.dcc-telegram-notify. An existing install must carry
# over untouched, and an explicit TELEGRAM_NOTIFY_HOME must never be overridden.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/dcc-telegram-notify.sh"

export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"   # keep load-time migration off the real home
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"
# shellcheck disable=SC1090
source "$SCRIPT"

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# Build a fake home dir and run migrate_home() against it. $1 = "explicit" to
# simulate a user-set TELEGRAM_NOTIFY_HOME, anything else for the default path.
setup_case() {
  CASE="$(mktemp -d)"
  TELEGRAM_NOTIFY_HOME="$CASE/.dcc-telegram-notify"
  TELEGRAM_NOTIFY_HOME_WAS_SET=""
  [ "${1:-}" = "explicit" ] && TELEGRAM_NOTIFY_HOME_WAS_SET="1"
}

# 1. Old home present, new absent -> migrated, contents preserved.
setup_case
mkdir -p "$CASE/.telegram-notify/state"
echo "TELEGRAM_BOT_TOKEN=secret" > "$CASE/.telegram-notify/telegram.env"
migrate_home
check "old home is moved to the new location" \
  "$([ -d "$CASE/.dcc-telegram-notify" ] && echo yes || echo no)" "yes"
check "old home no longer exists" \
  "$([ -d "$CASE/.telegram-notify" ] && echo yes || echo no)" "no"
check "config contents survive the move" \
  "$(cat "$CASE/.dcc-telegram-notify/telegram.env" 2>/dev/null)" "TELEGRAM_BOT_TOKEN=secret"
check "state subdirectory survives the move" \
  "$([ -d "$CASE/.dcc-telegram-notify/state" ] && echo yes || echo no)" "yes"

# 2. Both present -> the new home wins and is left completely alone.
setup_case
mkdir -p "$CASE/.telegram-notify" "$CASE/.dcc-telegram-notify"
echo "old" > "$CASE/.telegram-notify/telegram.env"
echo "new" > "$CASE/.dcc-telegram-notify/telegram.env"
migrate_home
check "existing new home is not overwritten" \
  "$(cat "$CASE/.dcc-telegram-notify/telegram.env")" "new"
check "old home is left in place when both exist" \
  "$([ -d "$CASE/.telegram-notify" ] && echo yes || echo no)" "yes"

# 3. Neither present -> no-op, and no directory is conjured.
setup_case
migrate_home
check "nothing is created when there is nothing to migrate" \
  "$([ -e "$CASE/.dcc-telegram-notify" ] && echo yes || echo no)" "no"

# 4. Explicit TELEGRAM_NOTIFY_HOME -> the user's choice is never second-guessed.
setup_case explicit
mkdir -p "$CASE/.telegram-notify"
echo "old" > "$CASE/.telegram-notify/telegram.env"
migrate_home
check "explicit home suppresses migration" \
  "$([ -d "$CASE/.telegram-notify" ] && echo yes || echo no)" "yes"
check "explicit home is not created by migration" \
  "$([ -e "$CASE/.dcc-telegram-notify" ] && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash plugins/dcc-telegram-notify/tests/migration.test.sh
```
Expected: FAIL — `migrate_home: command not found` on every case, so all nine checks fail.

- [ ] **Step 3: Implement the migration**

In `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh`, replace the home resolution block (currently lines 10–23, from the `# Config and mutable state live in...` comment through the `STATE_DIR=` line) with:

```bash
# Config and mutable state live in a stable per-user home, NOT beside the script:
# installed as a plugin the script directory is replaced on every update and is
# shared read-only across accounts. Resolve a home that works on Linux, macOS,
# and Windows Git Bash; override the whole location with TELEGRAM_NOTIFY_HOME.
# Recorded before notify_home() overwrites the variable, so migrate_home() can
# tell an explicit override from the default.
TELEGRAM_NOTIFY_HOME_WAS_SET="${TELEGRAM_NOTIFY_HOME:+1}"
notify_home() {
  if [ -n "${TELEGRAM_NOTIFY_HOME:-}" ]; then printf '%s' "$TELEGRAM_NOTIFY_HOME"; return; fi
  local h="${HOME:-}"
  if [ -z "$h" ] && [ -n "${USERPROFILE:-}" ]; then
    h=$(cygpath -u "$USERPROFILE" 2>/dev/null || printf '%s' "$USERPROFILE")
  fi
  printf '%s/.dcc-telegram-notify' "$h"
}
TELEGRAM_NOTIFY_HOME="$(notify_home)"

# The plugin rename moved this home from ~/.telegram-notify. Carry an existing
# install over so the token, topic map and state survive an update. Within one
# user home this is a rename(2) and therefore atomic, so the async hooks racing
# here are safe: one wins, the loser's mv fails against a target that now exists.
# Every failure is swallowed -- the worst case is a freshly seeded, silent config.
migrate_home() {
  [ -n "$TELEGRAM_NOTIFY_HOME_WAS_SET" ] && return 0
  [ -e "$TELEGRAM_NOTIFY_HOME" ] && return 0
  local old="${TELEGRAM_NOTIFY_HOME%/.dcc-telegram-notify}/.telegram-notify"
  [ -d "$old" ] || return 0
  mv "$old" "$TELEGRAM_NOTIFY_HOME" 2>/dev/null || true
  return 0
}
migrate_home

CONFIG_FILE="${TELEGRAM_NOTIFY_ENV:-$TELEGRAM_NOTIFY_HOME/telegram.env}"
STATE_DIR="$TELEGRAM_NOTIFY_HOME/state"
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bash plugins/dcc-telegram-notify/tests/run-all.sh
```
Expected: `migration.test.sh` reports `9 passed, 0 failed`; the other two files still report `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh \
        plugins/dcc-telegram-notify/tests/migration.test.sh
git commit -m "feat(dcc-telegram-notify): move config home, migrate old one" -m "Config and state now live in ~/.dcc-telegram-notify. An existing
~/.telegram-notify is renamed into place at load time, which is atomic within
one user home, so concurrent async hooks cannot corrupt it. An explicit
TELEGRAM_NOTIFY_HOME suppresses the migration entirely."
```

---

### Task 3: Add the TELEGRAM_EVENTS token parser

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` (insert after the `TELEGRAM_TOPIC_MAP` default, before the `TELEGRAM_MACHINE_NAME` block)
- Test: `plugins/dcc-telegram-notify/tests/events.test.sh` (create)

**Interfaces:**
- Consumes: the renamed script from Task 1.
- Produces, all used by Task 4 and Task 5:
  - `parse_events()` — no arguments, reads `TELEGRAM_EVENTS`, sets `TELEGRAM_EVENTS_RESOLVED` and `TELEGRAM_EVENTS_UNKNOWN`. Called once at load; tests re-call it after changing `TELEGRAM_EVENTS`.
  - `event_enabled <token>` — returns 0 if the token is in the resolved set, 1 otherwise.
  - `events_list` — prints the resolved set as a space-separated, alphabetically sorted string, or the empty string.
  - `TELEGRAM_EVENTS_UNKNOWN` — space-separated tokens that matched nothing, empty when all were valid.

**Decision not stated in the spec:** `TELEGRAM_EVENTS` set to the empty string means *no events*, identical to `none`. Only an entirely unset variable gets the default. A user who blanks the line intends silence; a user who comments it out intends the default.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-telegram-notify/tests/events.test.sh`:

```bash
#!/usr/bin/env bash
# Tests for the TELEGRAM_EVENTS parser, which decides what is allowed to send.
# A typo must never be fatal: unknown tokens are dropped and reported, never
# propagated as an error that could take a user's notifications down.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/dcc-telegram-notify.sh"

export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"
# shellcheck disable=SC1090
source "$SCRIPT"

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# resolve <value>  -- pass the literal string UNSET to remove the variable
resolve() {
  if [ "$1" = "UNSET" ]; then unset TELEGRAM_EVENTS; else TELEGRAM_EVENTS="$1"; fi
  parse_events
  events_list
}

check "unset yields the blocked-on-you default" \
  "$(resolve UNSET)" "input permission stop-question"
check "empty means no events, like none" \
  "$(resolve "")" ""
check "none disables everything" \
  "$(resolve "none")" ""
check "none wins wherever it appears in the list" \
  "$(resolve "all,none")" ""
check "a single token enables only itself" \
  "$(resolve "permission")" "permission"
check "stop expands to the three turn-end tokens" \
  "$(resolve "stop")" "stop-done stop-question stop-reply"
check "all enables every token" \
  "$(resolve "all")" "input permission stop-done stop-question stop-reply"
check "commas, spaces and case are all tolerated" \
  "$(resolve "Permission,  STOP-DONE  input")" "input permission stop-done"
check "duplicates collapse" \
  "$(resolve "permission,permission,all")" "input permission stop-done stop-question stop-reply"

# Unknown tokens are dropped, recorded for status output, and leave valid
# neighbors alone.
out=$(resolve "permission,bogus,input")
check "unknown tokens do not disturb valid ones" "$out" "input permission"
check "unknown tokens are recorded" "$TELEGRAM_EVENTS_UNKNOWN" "bogus"
out=$(resolve "permission")
check "the unknown list resets between parses" "$TELEGRAM_EVENTS_UNKNOWN" ""

# event_enabled is the membership test the hook branches actually call.
resolve "permission,stop-question" >/dev/null
check "event_enabled true for a member" \
  "$(event_enabled permission && echo yes || echo no)" "yes"
check "event_enabled false for a non-member" \
  "$(event_enabled stop-done && echo yes || echo no)" "no"
resolve "none" >/dev/null
check "event_enabled false for everything under none" \
  "$(event_enabled permission && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash plugins/dcc-telegram-notify/tests/events.test.sh
```
Expected: FAIL — `parse_events: command not found` and `events_list: command not found`, all 15 checks failing.

- [ ] **Step 3: Implement the parser**

In `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh`, insert immediately after the `: "${TELEGRAM_TOPIC_MAP:=$TELEGRAM_NOTIFY_HOME/topics.json}"` line:

```bash
# Which notifications are allowed to send. Comma- or space-separated tokens:
#   permission    a tool call is waiting for approval
#   input         a question is waiting, or an agent asked for input
#   stop-question the turn ended on a question
#   stop-done     a work turn finished
#   stop-reply    a conversational turn finished
# Aliases: stop = the three stop-* tokens, all = everything, none = nothing.
# Unset gets the default below; set-but-empty means nothing, same as none.
TELEGRAM_EVENTS_RESOLVED=" "
TELEGRAM_EVENTS_UNKNOWN=""
parse_events() {
  local raw tok out="" unknown=""
  if [ "${TELEGRAM_EVENTS+set}" = "set" ]; then raw="$TELEGRAM_EVENTS"
  else raw="permission,input,stop-question"; fi
  raw=$(printf '%s' "$raw" | tr 'A-Z,' 'a-z ')
  for tok in $raw; do
    case "$tok" in
      permission|input|stop-question|stop-done|stop-reply) out="$out$tok " ;;
      stop) out="${out}stop-question stop-done stop-reply " ;;
      all)  out="${out}permission input stop-question stop-done stop-reply " ;;
      none) out=""; break ;;
      # A typo must never break notifications, so it is dropped and reported
      # rather than raised. `status` surfaces whatever landed here.
      *)    unknown="$unknown$tok " ;;
    esac
  done
  # shellcheck disable=SC2086 -- deliberate word splitting to dedupe the set
  [ -n "$out" ] && out=$(printf '%s\n' $out | LC_ALL=C sort -u | tr '\n' ' ')
  TELEGRAM_EVENTS_RESOLVED=" $out"
  TELEGRAM_EVENTS_UNKNOWN="${unknown% }"
}
parse_events

event_enabled() {
  case "$TELEGRAM_EVENTS_RESOLVED" in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

events_list() { local l="${TELEGRAM_EVENTS_RESOLVED# }"; printf '%s' "${l% }"; }
```

Note on `none`: it clears the set and stops parsing, so it wins no matter where it appears. That is why `all,none` resolves to nothing.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bash plugins/dcc-telegram-notify/tests/run-all.sh
```
Expected: `events.test.sh` reports `15 passed, 0 failed`; every other file still reports `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh \
        plugins/dcc-telegram-notify/tests/events.test.sh
git commit -m "feat(dcc-telegram-notify): add TELEGRAM_EVENTS parser" -m "Normalizes the configured token list once at load into a canonical set, with
stop/all/none aliases. Unknown tokens are dropped and recorded rather than
raised, so a typo can never silence notifications by crashing the hook.
Nothing consults the set yet."
```

---

### Task 4: Gate the notification branches on the event set

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` — the `Notification` and `Stop` arms of `main()`'s `case`
- Test: `plugins/dcc-telegram-notify/tests/gating.test.sh` (create)

**Interfaces:**
- Consumes: `event_enabled <token>` from Task 3.
- Produces: no new functions. `main()` now exits 0 without sending when the matching token is disabled.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-telegram-notify/tests/gating.test.sh`:

```bash
#!/usr/bin/env bash
# End-to-end: does a hook firing actually reach Telegram? Drives the script the
# way Claude Code does -- payload on stdin -- with a curl stub on PATH standing
# in for the Bot API, and counts sends.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/dcc-telegram-notify.sh"
FIXTURES="$HERE/fixtures"

TMP="$(mktemp -d)"
BIN="$TMP/bin"; mkdir -p "$BIN"
export CURL_CALLS="$TMP/curl.calls"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
# Stand-in for curl: record the send and answer like the Telegram Bot API.
echo call >> "$CURL_CALLS"
cat >/dev/null
printf '{"ok":true,"result":{"message_id":1}}'
STUB
chmod +x "$BIN/curl"
export PATH="$BIN:$PATH"

CFG="$TMP/telegram.env"
cat > "$CFG" <<'EOF'
TELEGRAM_BOT_TOKEN=123456789:TESTTOKEN
TELEGRAM_CHAT_ID=-1001234567890
TELEGRAM_LLM_URL=
TELEGRAM_TOPIC_MODE=shared
EOF
export TELEGRAM_NOTIFY_ENV="$CFG"
export TELEGRAM_NOTIFY_HOME="$TMP/home"
export TELEGRAM_PENDING_TRIES=2

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# sends <events-value|UNSET> <payload-json>  -> how many messages were sent
sends() {
  : > "$CURL_CALLS"
  if [ "$1" = "UNSET" ]; then
    printf '%s' "$2" | env -u TELEGRAM_EVENTS bash "$SCRIPT" >/dev/null 2>&1
  else
    printf '%s' "$2" | TELEGRAM_EVENTS="$1" bash "$SCRIPT" >/dev/null 2>&1
  fi
  # grep -c prints 0 and exits 1 on no match, so swallow the status, not the count.
  grep -c call "$CURL_CALLS" 2>/dev/null || true
}

STOP_Q='{"hook_event_name":"Stop","session_id":"s1","cwd":"'"$TMP"'","last_assistant_message":"Which of these should I do first?"}'
STOP_W='{"hook_event_name":"Stop","session_id":"s1","cwd":"'"$TMP"'","last_assistant_message":"Fixed the parser and all 42 tests pass."}'
PERM='{"hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"s1","cwd":"'"$TMP"'","transcript_path":"'"$FIXTURES/pending_bash.jsonl"'"}'
ASK='{"hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"s1","cwd":"'"$TMP"'","transcript_path":"'"$FIXTURES/pending_askquestion.jsonl"'"}'
AGENT='{"hook_event_name":"Notification","notification_type":"agent_needs_input","session_id":"s1","cwd":"'"$TMP"'","message":"An agent needs your input."}'

# permission gates tool approvals only.
check "permission sends a tool approval"        "$(sends permission "$PERM")"  "1"
check "input does not send a tool approval"     "$(sends input "$PERM")"       "0"

# input gates both flavors of "a human has to answer something".
check "input sends an AskUserQuestion prompt"   "$(sends input "$ASK")"        "1"
check "permission does not send AskUserQuestion" "$(sends permission "$ASK")"  "0"
check "input sends an agent input request"      "$(sends input "$AGENT")"      "1"
check "permission does not send agent input"    "$(sends permission "$AGENT")" "0"

# The three turn-end kinds are gated separately.
check "stop-question sends a question turn"     "$(sends stop-question "$STOP_Q")" "1"
check "stop-question mutes a work turn"         "$(sends stop-question "$STOP_W")" "0"
check "stop-done sends a work turn"             "$(sends stop-done "$STOP_W")"     "1"
check "stop-done mutes a question turn"         "$(sends stop-done "$STOP_Q")"     "0"

# The shipped default: everything that blocks you, nothing that does not.
check "default sends a question turn"           "$(sends UNSET "$STOP_Q")" "1"
check "default mutes a finished work turn"      "$(sends UNSET "$STOP_W")" "0"
check "default sends a tool approval"           "$(sends UNSET "$PERM")"   "1"

# none is a complete off switch that leaves the token in place.
check "none mutes turn ends"                    "$(sends none "$STOP_Q")" "0"
check "none mutes permission prompts"           "$(sends none "$PERM")"   "0"

# A muted Stop must still consume the turn timer, or start files pile up forever.
mkdir -p "$TELEGRAM_NOTIFY_HOME/state"
date +%s > "$TELEGRAM_NOTIFY_HOME/state/s1.start"
sends none "$STOP_W" >/dev/null
check "a muted Stop still clears its start file" \
  "$([ -e "$TELEGRAM_NOTIFY_HOME/state/s1.start" ] && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
bash plugins/dcc-telegram-notify/tests/gating.test.sh
```
Expected: FAIL on every "does not send" / "mutes" check — they report `1` where `0` is wanted, because nothing consults the event set yet. The positive checks already pass.

- [ ] **Step 3: Gate the Notification branch**

In `main()`'s `Notification)` arm, add `gate` to the `local` declaration and set it alongside each `status`. The arm becomes:

```bash
    Notification)
      local ntype transcript status body action tool sidechain q opts n target gate
      ntype=$(jq -r '.notification_type // ""' <<<"$payload" 2>/dev/null)
      transcript=$(jq -r '.transcript_path // ""' <<<"$payload" 2>/dev/null)
      if [ "$ntype" = "permission_prompt" ]; then
        action=$(pending_action "$transcript")
        tool=$(jq -r '.tool // ""' <<<"$action" 2>/dev/null)
        sidechain=$(jq -r '.sidechain // false' <<<"$action" 2>/dev/null)
        if [ "$tool" = "AskUserQuestion" ]; then
          # A question is waiting, not a tool to approve — present it as one.
          status="❓ Needs your input"; gate=input
          q=$(jq -r '.question // ""' <<<"$action" 2>/dev/null)
          opts=$(jq -r '(.options // []) | join(" / ")' <<<"$action" 2>/dev/null)
          body="$q"
          [ -n "$opts" ] && body="$q"$'\n\n'"Options: $opts"
        elif [ -n "$tool" ]; then
          status="🔐 Needs permission"; gate=permission
          n=$(jq -r '.n // 1' <<<"$action" 2>/dev/null)
          target=$(jq -r '.target // ""' <<<"$action" 2>/dev/null)
          body="▸ $tool"
          [ -n "$target" ] && body="▸ $tool: $target"
          [ "${n:-1}" -gt 1 ] 2>/dev/null && body="$body (+$((n - 1)) more)"
        else
          status="🔐 Needs permission"; gate=permission
          body=$(jq -r '.message // "Claude is waiting for your approval."' <<<"$payload" 2>/dev/null)
        fi
        # Mark subagent-issued prompts so they are distinct from the main session.
        [ "$sidechain" = "true" ] && header="$header ⤷ <i>subagent</i>"
      else
        status="🔔 Needs you"; gate=input
        body=$(jq -r '.message // "Claude is waiting for you."' <<<"$payload" 2>/dev/null)
      fi
      event_enabled "$gate" || { dbg "   muted: $gate not in TELEGRAM_EVENTS [$(events_list)]"; exit 0; }
      send_message "$header" "$status" "$body"
      ;;
```

- [ ] **Step 4: Gate the Stop branch**

Replace the top of the `Stop)` arm — the `local` line through the `if [ -r "$start_file" ]` block — with:

```bash
    Stop)
      local transcript full kind status body duration="" turn_start="" now gate
      # Consume the turn timer before any early exit, or muted sessions leave
      # start files behind forever.
      if [ -r "$start_file" ]; then
        turn_start=$(cat "$start_file")
        [[ "$turn_start" =~ ^[0-9]+$ ]] || turn_start=""
        rm -f "$start_file"
      fi

      # With every turn-end token off there is nothing this branch can produce,
      # so skip before the transcript read and the LLM classify call.
      if ! event_enabled stop-question && ! event_enabled stop-done \
         && ! event_enabled stop-reply; then
        dbg "   muted: no stop-* token in TELEGRAM_EVENTS [$(events_list)]"
        exit 0
      fi

      transcript=$(jq -r '.transcript_path // ""' <<<"$payload" 2>/dev/null)
```

Then extend the kind-to-status mapping further down to carry the gate, and check it:

```bash
      case "$kind" in
        question) status="❓ Waiting on you"; gate=stop-question ;;
        reply)    status="💬 Replied";        gate=stop-reply ;;
        *)        status="✅ Done";           gate=stop-done ;;
      esac
      event_enabled "$gate" || { dbg "   muted: $gate not in TELEGRAM_EVENTS [$(events_list)]"; exit 0; }
```

- [ ] **Step 5: Log the resolved set on every firing**

Immediately after the existing `dbg "── EVENT=$event ..."` line in `main()`, add:

```bash
  dbg "   events=[$(events_list)]${TELEGRAM_EVENTS_UNKNOWN:+ unknown=[$TELEGRAM_EVENTS_UNKNOWN]}"
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
bash plugins/dcc-telegram-notify/tests/run-all.sh
```
Expected: `gating.test.sh` reports `16 passed, 0 failed`; all four files pass and the runner exits 0.

- [ ] **Step 7: Confirm --test still bypasses the filter**

`--test` calls `send_message` directly from the option dispatch, never through `main()`, so it is unaffected by construction. Verify by inspection:

```bash
rg -n 'event_enabled' plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh
```
Expected: every hit is inside `main()`. If one appears in the `--test` arm, remove it — a user with `none` set must still be able to verify their token.

- [ ] **Step 8: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh \
        plugins/dcc-telegram-notify/tests/gating.test.sh
git commit -m "feat(dcc-telegram-notify): honor TELEGRAM_EVENTS when sending" -m "Each notification now checks its token before sending. The Stop branch exits
early when every turn-end token is off, skipping the transcript read and the
LLM classify call, but still consumes the turn timer so start files cannot
accumulate. --test deliberately bypasses the filter."
```

---

### Task 5: Document the event config

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` (the `seed_config` heredoc)
- Modify: `plugins/dcc-telegram-notify/telegram.env.example`
- Modify: `plugins/dcc-telegram-notify/README.md`
- Modify: `plugins/dcc-telegram-notify/commands/dcc-telegram-notify.md`

**Interfaces:**
- Consumes: `events_list` and `TELEGRAM_EVENTS_UNKNOWN` from Task 3, for the `status` subcommand.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Add the block to the seeded config template**

In `seed_config`'s heredoc, insert after the `TELEGRAM_TOPIC_MODE=shared` line:

```
# --- Which events notify you -------------------------------------------------
# Comma-separated list. Tokens:
#   permission     a tool call is waiting for your approval
#   input          a question is waiting, or an agent asked for input
#   stop-question  the turn ended on a question
#   stop-done      a work turn finished
#   stop-reply     a conversational turn finished
# Aliases: stop (all three stop-*), all, none. Unknown tokens are ignored.
# The default is everything that leaves the session blocked on you.
TELEGRAM_EVENTS=permission,input,stop-question
```

- [ ] **Step 2: Mirror it in the example file**

Add the identical block to `plugins/dcc-telegram-notify/telegram.env.example`, in the same position (after `TELEGRAM_TOPIC_MODE=shared`).

- [ ] **Step 3: Update the README**

Replace the "The three hook events" table with one that names the gating token, and add the upgrade note. The section becomes:

```markdown
## Which events notify you

`TELEGRAM_EVENTS` is a comma-separated list of the notifications you want. The
default, `permission,input,stop-question`, sends only when the session is
actually blocked waiting on you.

| Token | Fires when | Message |
|-------|-----------|---------|
| `permission` | A tool call is waiting for your approval | 🔐 Needs permission |
| `input` | A question is waiting, or an agent asked for input | ❓ / 🔔 |
| `stop-question` | The turn ended on a question | ❓ Waiting on you |
| `stop-done` | A work turn finished | ✅ Done |
| `stop-reply` | A conversational turn finished | 💬 Replied |

Three aliases expand for you: `stop` is all three `stop-*` tokens, `all` is
everything, and `none` silences the plugin without deleting your bot token.
Unknown tokens are ignored rather than treated as errors, so a typo can't take
your notifications down — `/dcc-telegram-notify status` reports any it dropped.

`UserPromptSubmit` is not in the list. It sends nothing; it only starts the
timer that gives turn-end messages their duration.

> **Upgrading from `telegram-notify` 1.0.x?** Two things change. Your config and
> state move from `~/.telegram-notify` to `~/.dcc-telegram-notify` automatically
> on the first hook firing — nothing to do. And `✅ Done` / `💬 Replied` turn-end
> messages stop arriving, because the new default omits them. Set
> `TELEGRAM_EVENTS=all` to get the old behavior back.
```

Then add a row to the config reference table, directly under `TELEGRAM_TOPIC_MODE`:

```markdown
| `TELEGRAM_EVENTS` | `permission,input,stop-question` | Which notifications send; see above. |
```

And update the "Where things live" block to read `~/.dcc-telegram-notify/`.

- [ ] **Step 4: Extend the status subcommand**

In `plugins/dcc-telegram-notify/commands/dcc-telegram-notify.md`, add a bullet to the `status` list, after the destination bullet:

```markdown
- the active event set — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/dcc-telegram-notify.sh" --events` and report the resolved tokens, plus any it flags as unknown
```

Then add the `--events` option to the script's dispatch `case`, immediately before the `"") main ;;` arm:

```bash
    --events)
      printf 'enabled: %s\n' "$(events_list)"
      [ -n "$TELEGRAM_EVENTS_UNKNOWN" ] && \
        printf 'ignored (not valid tokens): %s\n' "$TELEGRAM_EVENTS_UNKNOWN"
      ;;
```

Also update the script's header comment block to list it:

```bash
#   --events:   prints which notifications are enabled, and any unknown tokens
```

- [ ] **Step 5: Verify the new option works**

```bash
cd /d/Repositories/Personal/claude-code-plugins/plugins/dcc-telegram-notify
TELEGRAM_NOTIFY_HOME="$(mktemp -d)" TELEGRAM_NOTIFY_ENV="$(mktemp -u)" \
  TELEGRAM_EVENTS="all,bogus" bash scripts/dcc-telegram-notify.sh --events
```
Expected output, exactly two lines:
```
enabled: input permission stop-done stop-question stop-reply
ignored (not valid tokens): bogus
```

- [ ] **Step 6: Run everything**

```bash
cd /d/Repositories/Personal/claude-code-plugins
bash plugins/dcc-telegram-notify/tests/run-all.sh && claude plugin validate .
```
Expected: all four test files report `0 failed`, and the validator passes.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-telegram-notify
git commit -m "docs(dcc-telegram-notify): document TELEGRAM_EVENTS" -m "Adds the token reference to the seeded config, the example file, and the
README, plus an upgrade note covering the moved config home and the turn-end
messages the new default omits. Adds --events so the status subcommand can
report the resolved set."
```

---

## Final Verification

- [ ] `bash plugins/dcc-telegram-notify/tests/run-all.sh` — four files, all `0 failed`, runner exits 0.
- [ ] `claude plugin validate .` at the repo root — passes.
- [ ] `rg -n --hidden -g '!.git' -g '!docs/**' 'telegram-notify' | rg -v 'dcc-telegram-notify'` — the only surviving hits are the migration shim's reference to the old `~/.telegram-notify` home, the README upgrade note that names the old plugin, and the `telegram.env` / `TELEGRAM_*` names that were deliberately left alone.
- [ ] A real end-to-end check on this machine: reinstall the plugin under its new name, submit a prompt that ends in a plain statement (expect no Telegram message) and one that ends in a question (expect `❓ Waiting on you`), and confirm `~/.dcc-telegram-notify/telegram.env` now holds the token that used to live in `~/.telegram-notify/`.
