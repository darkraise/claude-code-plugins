# Telegram Reply-Back Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Telegram reply drive a Claude Code session — reply to a turn-end notification and the session wakes up and keeps working; tap a button on a permission prompt and the tool call is approved or refused.

**Architecture:** The `Stop` hook becomes `asyncRewake`, so it keeps polling Telegram in the background after the turn has ended and exits with code 2 to hand your reply to Claude — the terminal is never blocked. `PermissionRequest` and a narrowly-matched `PreToolUse` gate tool approvals and questions, but only while "away" mode is armed. All waiters share one cooperative reader that holds a portable lock, calls `getUpdates` once, and files every update into a spool, so concurrent sessions never steal each other's replies.

**Tech Stack:** Bash (POSIX-ish, must run on Git Bash for Windows as well as Linux/macOS), `curl`, `jq`. Tests are plain bash scripts under `plugins/dcc-telegram-notify/tests/`.

**Spec:** `docs/superpowers/specs/2026-08-09-dcc-telegram-notify-reply-back-design.md`

## Global Constraints

- Plugin directory is `plugins/dcc-telegram-notify/`. All paths below are relative to the repository root.
- Plugin name stays `dcc-telegram-notify` in all three places that must agree: directory, `plugin.json` `name`, `marketplace.json` entry.
- Bump `plugins/dcc-telegram-notify/.claude-plugin/plugin.json` `version` to `1.2.0` (Task 10, not before).
- Run `claude plugin validate .` at the repo root before committing any manifest change.
- **A notification path must never disturb a session.** Every new code path swallows its own failures and falls back to today's behavior.
- **Never break the send side.** If `jq` or `curl` is missing, or the allowlist is empty, the read side disables itself and notifications keep working.
- **`flock` does not exist on Git Bash for Windows** — verified on the target machine on 2026-08-09. It is NOT a dependency. All locking goes through `with_lock`, which uses `flock` when present and an atomic `mkdir` with a stale-lock steal when not. Never call `flock` directly in new code.
- English only in code, comments, commits, and docs.
- Commit format: `<type>(<scope>): <subject>`, subject ≤50 chars, imperative, no period. Scope is `telegram-notify`.
- Comments explain WHY, never WHAT. Match the existing script's comment density — it comments non-obvious constraints heavily and obvious code not at all.
- Config variable names are unprefixed (`TELEGRAM_*`), matching the existing convention.
- New config defaults, copied verbatim from the spec: `TELEGRAM_ALLOWED_USERS` empty, `TELEGRAM_REPLY=on`, `TELEGRAM_REPLY_WINDOW=600`, `TELEGRAM_REPLY_WINDOW_AWAY=3600`, `TELEGRAM_REPLY_POLL=3`, `TELEGRAM_SPOOL_TTL=300`, `TELEGRAM_AWAY_TTL=7200`.

## Orientation for someone new to this codebase

`scripts/dcc-telegram-notify.sh` is a single 737-line bash script that is both the hook engine and the CLI. Read it before starting. Three things about it drive this plan:

1. **It is sourced by its own tests.** The last block is `if [ "${BASH_SOURCE[0]}" = "${0}" ]; then … fi`, so sourcing the file defines every function without running anything. Every test file uses this.
2. **`main()` redirects both stdout and stderr to `/dev/null`** (line ~507) so a broken notification can never print into the user's session. The new hooks must *write to stdout* (a JSON decision) and *stderr* (the rewake text), so Task 7 saves those file descriptors before the redirect. This is the single easiest thing to get wrong.
3. **Config and state live in `$TELEGRAM_NOTIFY_HOME`** (default `~/.dcc-telegram-notify`), never beside the script. Tests isolate by exporting `TELEGRAM_NOTIFY_HOME` to a temp dir and `TELEGRAM_NOTIFY_ENV` to a path that does not exist.

Tests follow one idiom, from `tests/events.test.sh`:

```bash
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }
# … checks …
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

`check <name> <got> <want>` — note the argument order.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `scripts/lib/updates.sh` | Create (Tasks 1–3) | Telegram read side: allowlist, offset, lock, poll, spool, sweep, atomic claim, matchers. Knows nothing about hooks. |
| `scripts/lib/await.sh` | Create (Task 6) | The waiting loops: turn-end listener and gate waiter. Consumes `updates.sh`. |
| `scripts/dcc-telegram-notify.sh` | Modify (Tasks 4,5,7,8,9,10) | Wiring: away helpers, keyboard support in `send`, three new hook branches, new CLI flags. |
| `hooks/hooks.json` | Modify (Tasks 7,8,9) | `Stop` becomes `asyncRewake`; add `PermissionRequest` and `PreToolUse`. |
| `tests/updates.test.sh` | Create (Tasks 1–3) | Spool, offset, allowlist, claim, sweep, matchers. |
| `tests/away.test.sh` | Create (Task 4) | Arm, disarm, expiry, duration parsing, gate-when-disarmed. |
| `tests/keyboard.test.sh` | Create (Task 5) | Keyboard JSON, nonce/pending bookkeeping, `last/` write. |
| `tests/listen.test.sh` | Create (Tasks 6,7) | The listener's three exits. |
| `tests/run-all.sh` | Modify (Task 1) | No change needed — it globs `*.test.sh`. Verify only. |
| `telegram.env.example`, `README.md`, `DESIGN.md`, `commands/dcc-telegram-notify.md` | Modify (Task 10) | Documentation and setup UX. |

---

## Task 0: Spikes — verify the two hook contracts

**Do this first and do not skip it.** Both flows in this plan rest on hook behavior the documentation does not fully promise. A negative result changes the design, not just the code. This task writes no product code.

**Files:**
- Create: `docs/superpowers/plans/2026-08-09-reply-back-spike-results.md`

- [ ] **Step 1: Build the asyncRewake probe**

Create a throwaway hook script at `/tmp/rewake-probe.sh` (use the scratchpad directory on Windows):

```bash
#!/usr/bin/env bash
sleep 20
printf 'SPIKE: the user replied from Telegram: please run `git status` and tell me the branch.\n' >&2
exit 2
```

- [ ] **Step 2: Register it and observe**

In a scratch project, add to `.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash /tmp/rewake-probe.sh", "asyncRewake": true, "timeout": 120 } ] }
    ]
  }
}
```

Start an interactive session, send any trivial prompt (e.g. "say hi"), let the turn end, then **do not touch the keyboard for 40 seconds**.

Record answers to all four questions:

1. Does the turn end immediately, leaving the prompt box usable? (Expected: yes.)
2. After ~20s, does the session wake on its own and act on the stderr text? (This is the load-bearing one.)
3. Does that woken turn fire `UserPromptSubmit`? Determine this by adding a second hook on `UserPromptSubmit` that appends a line to a log file, then checking whether the file grew.
4. If you *do* type a prompt during the 20s, does the hook's later exit 2 still inject text, or is it discarded?

- [ ] **Step 3: Build the AskUserQuestion probe**

Create `/tmp/askq-probe.sh`:

```bash
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The user answered from Telegram: PostgreSQL"}}'
exit 0
```

Register it:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "AskUserQuestion",
        "hooks": [ { "type": "command", "command": "bash /tmp/askq-probe.sh" } ] }
    ]
  }
}
```

Ask the session something that makes it call `AskUserQuestion` (e.g. "ask me which database to use, using the AskUserQuestion tool"). Record: does Claude proceed as though PostgreSQL was chosen, or does it treat the denial as a refusal and re-ask?

- [ ] **Step 4: Write up the results and decide**

Record each observation verbatim in the spike results file, then apply the decision rules:

| Result | Consequence for this plan |
|---|---|
| Spike 1 Q2 is **no** | Flow A loses its no-blocking property. Change `Stop` back to a synchronous hook with `TELEGRAM_REPLY_WINDOW` defaulted down to `30`, and emit `{"decision":"block","reason":"<text>"}` on stdout instead of exit 2. Tasks 6 and 7 change; Tasks 1–5 and 8–10 are unaffected. Stop and report to the user before continuing. |
| Spike 1 Q3 is **yes** | Task 7's `.remote` marker is load-bearing exactly as written. Keep it. |
| Spike 1 Q3 is **no** | The marker is belt-and-braces. Keep it anyway — it costs one file and makes the disarm rule correct under both behaviors. |
| Spike 2 shows a re-ask | Drop Task 9 entirely. `AskUserQuestion` stays notify-only. Report to the user. |

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-08-09-reply-back-spike-results.md
git commit -m "docs(telegram-notify): record hook contract spike results"
```

---

## Task 1: `updates.sh` — allowlist, offset, spool, claim, sweep

**Files:**
- Create: `plugins/dcc-telegram-notify/scripts/lib/updates.sh`
- Create: `plugins/dcc-telegram-notify/tests/updates.test.sh`

**Interfaces:**
- Consumes: `$TELEGRAM_NOTIFY_HOME` and `dbg()` from the engine script. When `updates.sh` is sourced standalone in tests, both are provided by the test.
- Produces:
  - `reply_enabled()` → 0 when the read side may run
  - `user_allowed <id>` → 0 when that Telegram user id may drive a session
  - `file_mtime <path>` → epoch seconds on stdout, empty if absent
  - `updates_offset_get` / `updates_offset_set <id>`
  - `updates_spool_put <update_json>` → writes one file, keyed by `update_id`
  - `updates_sweep` → removes spool entries older than `TELEGRAM_SPOOL_TTL`
  - `updates_claim <predicate_fn>` → prints the claimed update JSON, returns 0; returns 1 if nothing matched
  - Path globals: `UPDATES_DIR`, `SPOOL_DIR`, `OFFSET_FILE`, `POLL_LOCK`

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-telegram-notify/tests/updates.test.sh`:

```bash
#!/usr/bin/env bash
# Tests for the Telegram read side: the spool, the offset, the allowlist filter,
# and the atomic claim that stops two sessions consuming one reply.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../scripts/lib/updates.sh"

export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"
TELEGRAM_ALLOWED_USERS="111,222"
TELEGRAM_SPOOL_TTL=300
API="https://example.invalid/botTEST"
dbg() { :; }
# shellcheck disable=SC1090
source "$LIB"

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# --- allowlist ---------------------------------------------------------------
check "an allowlisted id is allowed" \
  "$(user_allowed 111 && echo yes || echo no)" "yes"
check "an id not on the list is refused" \
  "$(user_allowed 999 && echo yes || echo no)" "no"
check "a prefix of an allowlisted id is not a match" \
  "$(user_allowed 11 && echo yes || echo no)" "no"
check "an empty id is refused" \
  "$(user_allowed "" && echo yes || echo no)" "no"

# reply_enabled needs a non-empty allowlist; empty is the upgrade-safe default.
check "the read side is enabled with an allowlist" \
  "$(TELEGRAM_REPLY=on reply_enabled && echo yes || echo no)" "yes"
check "an empty allowlist disables the read side" \
  "$(TELEGRAM_ALLOWED_USERS= reply_enabled && echo yes || echo no)" "no"
check "TELEGRAM_REPLY=off disables the read side" \
  "$(TELEGRAM_REPLY=off reply_enabled && echo yes || echo no)" "no"

# --- offset ------------------------------------------------------------------
check "a missing offset file reads as 0" "$(updates_offset_get)" "0"
updates_offset_set 4711
check "the offset round-trips" "$(updates_offset_get)" "4711"
printf 'garbage' > "$OFFSET_FILE"
check "a corrupt offset file reads as 0" "$(updates_offset_get)" "0"
updates_offset_set 4711

# --- spool + claim -----------------------------------------------------------
updates_spool_put '{"update_id":10,"message":{"message_id":1,"text":"alpha"}}'
updates_spool_put '{"update_id":11,"message":{"message_id":2,"text":"beta"}}'
check "one file lands per update" "$(ls "$SPOOL_DIR" | wc -l | tr -d ' ')" "2"
check "the file is named for its update_id" \
  "$([ -f "$SPOOL_DIR/10.json" ] && echo yes || echo no)" "yes"

match_beta() { [ "$(jq -r '.message.text' "$1")" = "beta" ]; }
check "a claim returns the matching update" \
  "$(updates_claim match_beta | jq -r '.message.text')" "beta"
check "a claimed update leaves the spool" \
  "$([ -f "$SPOOL_DIR/11.json" ] && echo yes || echo no)" "no"
check "a second claim of the same update finds nothing" \
  "$(updates_claim match_beta >/dev/null && echo yes || echo no)" "no"
check "an unmatched update stays in the spool" \
  "$([ -f "$SPOOL_DIR/10.json" ] && echo yes || echo no)" "yes"

# Two claimers racing for one update: exactly one may win, or the whole
# feature silently duplicates work across sessions.
updates_spool_put '{"update_id":12,"message":{"message_id":3,"text":"race"}}'
match_race() { [ "$(jq -r '.message.text' "$1")" = "race" ]; }
a="$(updates_claim match_race | jq -r '.message.text // ""')" &
b="$(updates_claim match_race | jq -r '.message.text // ""')" &
wait
winners=0
[ -n "${a:-}" ] && winners=$((winners + 1))
[ -n "${b:-}" ] && winners=$((winners + 1))
check "exactly one claimer wins a contested update" "$winners" "1"

# --- sweep -------------------------------------------------------------------
updates_spool_put '{"update_id":20,"message":{"message_id":9,"text":"fresh"}}'
updates_spool_put '{"update_id":21,"message":{"message_id":9,"text":"stale"}}'
touch -d "@$(( $(date +%s) - 600 ))" "$SPOOL_DIR/21.json" 2>/dev/null \
  || touch -t "$(date -r $(( $(date +%s) - 600 )) +%Y%m%d%H%M.%S)" "$SPOOL_DIR/21.json"
updates_sweep
check "a stale spool entry is swept" \
  "$([ -f "$SPOOL_DIR/21.json" ] && echo yes || echo no)" "no"
check "a fresh spool entry survives the sweep" \
  "$([ -f "$SPOOL_DIR/20.json" ] && echo yes || echo no)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-telegram-notify/tests/updates.test.sh
```

Expected: fails immediately — `source: .../scripts/lib/updates.sh: No such file or directory`.

- [ ] **Step 3: Write the implementation**

Create `plugins/dcc-telegram-notify/scripts/lib/updates.sh`:

```bash
#!/usr/bin/env bash
# Telegram read side. Sourced by dcc-telegram-notify.sh; knows nothing about
# hooks, so it can be tested against a stub curl with no session in play.
#
# getUpdates is EXCLUSIVE per bot token: whoever calls it consumes updates for
# every other caller. Several sessions polling independently would steal each
# other's replies, so a poller files EVERY update it receives into a shared
# spool and each waiter then claims only what is addressed to it.

: "${TELEGRAM_ALLOWED_USERS:=}"
: "${TELEGRAM_REPLY:=on}"
: "${TELEGRAM_REPLY_WINDOW:=600}"
: "${TELEGRAM_REPLY_WINDOW_AWAY:=3600}"
: "${TELEGRAM_REPLY_POLL:=3}"
: "${TELEGRAM_SPOOL_TTL:=300}"

UPDATES_DIR="$TELEGRAM_NOTIFY_HOME/updates"
SPOOL_DIR="$UPDATES_DIR/spool"
OFFSET_FILE="$UPDATES_DIR/offset"
POLL_LOCK="$UPDATES_DIR/poll.lock"

# The read side needs more than the send side does. Any missing piece disables
# reading only -- notifications must keep working wherever the send side does.
reply_enabled() {
  [ "${TELEGRAM_REPLY:-on}" = "on" ] || return 1
  [ -n "${TELEGRAM_ALLOWED_USERS:-}" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  command -v curl >/dev/null 2>&1 || return 1
}

# A reply is an instruction Claude executes and an armed tap approves a tool
# call, so this is a security boundary, not an ergonomic one. Padding both sides
# keeps "11" from matching inside "111".
user_allowed() {
  local id="${1:-}" list
  [ -n "$id" ] || return 1
  list=" $(printf '%s' "$TELEGRAM_ALLOWED_USERS" | tr ',' ' ') "
  case "$list" in *" $id "*) return 0 ;; *) return 1 ;; esac
}

# GNU stat and BSD stat disagree on flags and neither is present everywhere.
file_mtime() {
  [ -e "$1" ] || return 1
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

updates_offset_get() {
  local off
  off=$(cat "$OFFSET_FILE" 2>/dev/null)
  [[ "$off" =~ ^[0-9]+$ ]] || off=0
  printf '%s' "$off"
}

updates_offset_set() {
  mkdir -p "$UPDATES_DIR" 2>/dev/null || return 0
  local tmp="$OFFSET_FILE.tmp.$$"
  printf '%s' "$1" > "$tmp" 2>/dev/null && mv "$tmp" "$OFFSET_FILE" 2>/dev/null
  return 0
}

updates_spool_put() {
  local u="$1" uid
  uid=$(jq -r '.update_id // empty' <<<"$u" 2>/dev/null) || return 0
  [ -n "$uid" ] || return 0
  mkdir -p "$SPOOL_DIR" 2>/dev/null || return 0
  local tmp="$SPOOL_DIR/.$uid.tmp.$$"
  printf '%s' "$u" > "$tmp" 2>/dev/null && mv "$tmp" "$SPOOL_DIR/$uid.json" 2>/dev/null
  return 0
}

# A reply sent to a session that has already died must not haunt a later one.
updates_sweep() {
  local f now mt
  now=$(date +%s)
  for f in "$SPOOL_DIR"/*.json; do
    [ -e "$f" ] || continue
    mt=$(file_mtime "$f") || continue
    [ $((now - mt)) -gt "$TELEGRAM_SPOOL_TTL" ] && rm -f "$f" 2>/dev/null
  done
  return 0
}

# Claim the first spooled update satisfying <predicate_fn>, which is called with
# the spool file path. The claim is a rename(2), which is atomic: two waiters
# racing for one update cannot both win, because the loser's mv hits an
# already-vanished source.
updates_claim() {
  local pred="$1" f claim
  for f in "$SPOOL_DIR"/*.json; do
    [ -e "$f" ] || continue
    "$pred" "$f" 2>/dev/null || continue
    claim="$UPDATES_DIR/claimed.$$.${RANDOM}.json"
    mv "$f" "$claim" 2>/dev/null || continue
    cat "$claim" 2>/dev/null
    rm -f "$claim" 2>/dev/null
    return 0
  done
  return 1
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash plugins/dcc-telegram-notify/tests/updates.test.sh
```

Expected: `18 passed, 0 failed`, exit 0.

If the sweep checks fail on a BSD `touch`, the fallback branch in the test's `touch` line is the culprit — confirm `date -r` exists on that host. On Git Bash the GNU `touch -d @epoch` form is used and the fallback never runs.

- [ ] **Step 5: Confirm the runner picks the file up**

```bash
bash plugins/dcc-telegram-notify/tests/run-all.sh
```

Expected: the new file appears in the output and everything passes. `run-all.sh` globs `*.test.sh`, so no edit is needed.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/lib/updates.sh plugins/dcc-telegram-notify/tests/updates.test.sh
git commit -m "feat(telegram-notify): add update spool and claim"
```

---

## Task 2: `updates_poll` — the locked, filtered fetch

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/lib/updates.sh` (append)
- Modify: `plugins/dcc-telegram-notify/tests/updates.test.sh` (append before the tally)

**Interfaces:**
- Consumes: `updates_offset_get`, `updates_offset_set`, `updates_spool_put`, `user_allowed` (Task 1); `$API` from the engine script.
- Produces: `updates_poll` → returns 0 when the poll ran, 1 when the lock was held or the call failed, **2 on a `409 Conflict`** meaning another consumer owns this bot and the caller must stop looping.

- [ ] **Step 1: Write the failing test**

Append to `tests/updates.test.sh`, immediately before the `printf '\n%d passed` tally line:

```bash
# --- updates_poll ------------------------------------------------------------
# A stub curl earlier on PATH than the real one returns canned getUpdates
# payloads, so nothing here touches the network.
STUB_DIR="$(mktemp -d)"
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
cat "$CURL_STUB_RESPONSE"
STUB
chmod +x "$STUB_DIR/curl"
PATH="$STUB_DIR:$PATH"

rm -f "$SPOOL_DIR"/*.json
export CURL_STUB_RESPONSE="$STUB_DIR/resp.json"
cat > "$CURL_STUB_RESPONSE" <<'JSON'
{"ok":true,"result":[
  {"update_id":100,"message":{"message_id":5,"text":"from an allowed user","from":{"id":111},"chat":{"id":-100}}},
  {"update_id":101,"message":{"message_id":6,"text":"from a stranger","from":{"id":999},"chat":{"id":-100}}},
  {"update_id":102,"callback_query":{"id":"cb1","data":"abc12345:0","from":{"id":222}}}
]}
JSON
updates_offset_set 0
updates_poll
check "poll returns 0 on a good response" "$?" "0"
check "allowed senders are spooled" \
  "$([ -f "$SPOOL_DIR/100.json" ] && echo yes || echo no)" "yes"
check "a stranger never reaches the spool" \
  "$([ -f "$SPOOL_DIR/101.json" ] && echo yes || echo no)" "no"
check "callback queries from allowed users are spooled" \
  "$([ -f "$SPOOL_DIR/102.json" ] && echo yes || echo no)" "yes"
# The offset must pass the FILTERED-OUT update too, or it is refetched forever.
check "the offset advances past every update, filtered or not" \
  "$(updates_offset_get)" "102"

# A replayed identical response must not duplicate anything.
updates_poll
check "a replay adds no duplicate spool entries" \
  "$(ls "$SPOOL_DIR" | wc -l | tr -d ' ')" "2"

cat > "$CURL_STUB_RESPONSE" <<'JSON'
{"ok":false,"error_code":409,"description":"Conflict: terminated by other getUpdates request"}
JSON
updates_poll
check "a 409 tells the caller to stand down" "$?" "2"

cat > "$CURL_STUB_RESPONSE" <<'JSON'
not json at all
JSON
updates_poll
check "an unparseable response is a plain failure" "$?" "1"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-telegram-notify/tests/updates.test.sh
```

Expected: FAIL lines for the new checks — `updates_poll: command not found`.

- [ ] **Step 3: Write the implementation**

Append to `scripts/lib/updates.sh`:

```bash
# One locked fetch. The lock is non-blocking on purpose: if another waiter is
# already filling the spool there is nothing to gain by queueing, so we return
# and let the caller re-scan what that waiter files.
#
# Returns 0 on a completed poll, 1 on lock contention or any failure, and 2 on a
# 409, which means another consumer (or a webhook) owns this bot token. There is
# no winning that fight, so the caller stops rather than thrashing.
updates_poll() {
  mkdir -p "$SPOOL_DIR" 2>/dev/null || return 1
  with_lock "$POLL_LOCK" _updates_poll_locked
}

_updates_poll_locked() {
    local off resp ok max u uid from
    off=$(updates_offset_get)
    resp=$(curl -sS --max-time "$((TELEGRAM_REPLY_POLL + 10))" \
      --data-urlencode "offset=$((off + 1))" \
      --data-urlencode "timeout=${TELEGRAM_REPLY_POLL}" \
      --data-urlencode 'allowed_updates=["message","callback_query"]' \
      "${API}/getUpdates" 2>/dev/null) || exit 1

    ok=$(jq -r '.ok // false' <<<"$resp" 2>/dev/null)
    if [ "$ok" != "true" ]; then
      [ "$(jq -r '.error_code // 0' <<<"$resp" 2>/dev/null)" = "409" ] && exit 2
      exit 1
    fi

    # Advance past every update returned, including ones the allowlist drops.
    # Leaving a filtered update below the offset would refetch it forever.
    max=$(jq -r '[.result[].update_id] | max // empty' <<<"$resp" 2>/dev/null)

    while IFS= read -r u; do
      [ -n "$u" ] || continue
      from=$(jq -r '(.message.from.id // .callback_query.from.id // empty)' <<<"$u" 2>/dev/null)
      if ! user_allowed "$from"; then
        uid=$(jq -r '.update_id // "?"' <<<"$u" 2>/dev/null)
        dbg "   updates: dropped update $uid from unlisted user ${from:-none}"
        continue
      fi
      updates_spool_put "$u"
    done < <(jq -c '.result[]' <<<"$resp" 2>/dev/null)

    [ -n "$max" ] && updates_offset_set "$max"
    exit 0
}
```

`with_lock` runs its command in a subshell on both branches, so `exit 0` / `exit 1`
/ `exit 2` inside `_updates_poll_locked` set the return code exactly as the
original inline subshell did.

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash plugins/dcc-telegram-notify/tests/updates.test.sh
```

Expected: `26 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/lib/updates.sh plugins/dcc-telegram-notify/tests/updates.test.sh
git commit -m "feat(telegram-notify): add locked getUpdates poll"
```

---

## Task 3: Matchers — routing an update to the right waiter

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/lib/updates.sh` (append)
- Modify: `plugins/dcc-telegram-notify/tests/updates.test.sh` (append before the tally)

**Interfaces:**
- Consumes: nothing new.
- Produces, all taking a spool file path and reading these globals: `MATCH_REPLY_TO`, `MATCH_CHAT`, `MATCH_TOPIC`, `MATCH_NONCE`.
  - `match_reply_to <file>` — an explicit Telegram reply to our notification
  - `match_bare_topic <file>` — a plain message in our chat+topic, only while `last/<chat>.<topic>` still names our notification
  - `match_callback <file>` — a button tap carrying our nonce
  - `match_command <file>` — a message whose text starts with `/away` or `/back`, in our chat
  - `update_text <json>` — the user-visible text of a claimed message
  - `update_callback_index <json>` — the button index from a claimed tap
  - `last_marker_path <chat> <topic>` — path of the `last/` marker, with an empty topic rendered as `main`

- [ ] **Step 1: Write the failing test**

Append to `tests/updates.test.sh` before the tally:

```bash
# --- matchers ----------------------------------------------------------------
mk() { printf '%s' "$2" > "$SPOOL_DIR/$1.json"; printf '%s' "$SPOOL_DIR/$1.json"; }

MATCH_REPLY_TO=42 MATCH_CHAT=-100 MATCH_TOPIC=7 MATCH_NONCE=abc12345

f=$(mk 200 '{"update_id":200,"message":{"message_id":50,"chat":{"id":-100},"message_thread_id":7,"text":"go on","reply_to_message":{"message_id":42}}}')
check "a reply to our notification matches" "$(match_reply_to "$f" && echo yes || echo no)" "yes"

f=$(mk 201 '{"update_id":201,"message":{"message_id":51,"chat":{"id":-100},"message_thread_id":7,"text":"other","reply_to_message":{"message_id":41}}}')
check "a reply to someone else's notification does not match" \
  "$(match_reply_to "$f" && echo yes || echo no)" "no"

# A bare topic message routes to whichever notification is currently newest
# there, so "just type an answer" works without long-pressing to Reply.
mkdir -p "$TELEGRAM_NOTIFY_HOME/last"
printf '42' > "$(last_marker_path -100 7)"
f=$(mk 202 '{"update_id":202,"message":{"message_id":52,"chat":{"id":-100},"message_thread_id":7,"text":"bare"}}')
check "a bare topic message matches while we are the newest there" \
  "$(match_bare_topic "$f" && echo yes || echo no)" "yes"
printf '99' > "$(last_marker_path -100 7)"
check "a bare topic message stops matching once superseded" \
  "$(match_bare_topic "$f" && echo yes || echo no)" "no"
printf '42' > "$(last_marker_path -100 7)"
f=$(mk 203 '{"update_id":203,"message":{"message_id":53,"chat":{"id":-100},"message_thread_id":9,"text":"elsewhere"}}')
check "a bare message in another topic does not match" \
  "$(match_bare_topic "$f" && echo yes || echo no)" "no"

check "the main thread renders as the literal name main" \
  "$(basename "$(last_marker_path -100 "")")" "-100.main"

f=$(mk 204 '{"update_id":204,"callback_query":{"id":"c","data":"abc12345:1","from":{"id":111}}}')
check "a tap carrying our nonce matches" "$(match_callback "$f" && echo yes || echo no)" "yes"
check "the button index is extracted" \
  "$(update_callback_index "$(cat "$f")")" "1"
f=$(mk 205 '{"update_id":205,"callback_query":{"id":"c","data":"zzz99999:0","from":{"id":111}}}')
check "a tap carrying another prompt's nonce does not match" \
  "$(match_callback "$f" && echo yes || echo no)" "no"

f=$(mk 206 '{"update_id":206,"message":{"message_id":54,"chat":{"id":-100},"text":"/away 2h"}}')
check "an away command matches anywhere in our chat" \
  "$(match_command "$f" && echo yes || echo no)" "yes"
check "the text of a claimed message is extracted" \
  "$(update_text "$(cat "$f")")" "/away 2h"
f=$(mk 207 '{"update_id":207,"message":{"message_id":55,"chat":{"id":-100},"text":"not a command"}}')
check "an ordinary message is not a command" \
  "$(match_command "$f" && echo yes || echo no)" "no"
rm -f "$SPOOL_DIR"/*.json
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-telegram-notify/tests/updates.test.sh
```

Expected: FAIL lines — `last_marker_path: command not found` and friends.

- [ ] **Step 3: Write the implementation**

Append to `scripts/lib/updates.sh`:

```bash
# --- Matchers ----------------------------------------------------------------
# Each takes a spool file path and reads the MATCH_* globals the waiter set, so
# they satisfy the single-argument contract updates_claim calls them with.

# A notification going to a group's main thread rather than a forum topic has no
# thread id; "main" keeps the filename well-formed.
last_marker_path() {
  local chat="$1" topic="${2:-}"
  [ -n "$topic" ] || topic=main
  printf '%s/last/%s.%s' "$TELEGRAM_NOTIFY_HOME" "$chat" "$topic"
}

match_reply_to() {
  local rid
  rid=$(jq -r '.message.reply_to_message.message_id // empty' "$1" 2>/dev/null)
  [ -n "$rid" ] && [ "$rid" = "${MATCH_REPLY_TO:-}" ]
}

match_bare_topic() {
  local chat topic
  jq -e '.message' "$1" >/dev/null 2>&1 || return 1
  jq -e '.message.reply_to_message' "$1" >/dev/null 2>&1 && return 1
  chat=$(jq -r '.message.chat.id // empty' "$1" 2>/dev/null)
  topic=$(jq -r '.message.message_thread_id // empty' "$1" 2>/dev/null)
  [ "$chat" = "${MATCH_CHAT:-}" ] || return 1
  [ "${topic:-}" = "${MATCH_TOPIC:-}" ] || return 1
  # Only the newest notification in this topic may absorb an unaddressed reply,
  # so an older session cannot swallow an answer meant for a newer prompt.
  [ "$(cat "$(last_marker_path "$MATCH_CHAT" "$MATCH_TOPIC")" 2>/dev/null)" = "${MATCH_REPLY_TO:-}" ]
}

match_callback() {
  local d
  d=$(jq -r '.callback_query.data // empty' "$1" 2>/dev/null)
  [ -n "$d" ] && [ "${d%%:*}" = "${MATCH_NONCE:-}" ]
}

# Claimed before the reply matchers so arming or disarming from the chat is
# never mistaken for an instruction to Claude.
match_command() {
  local chat text
  chat=$(jq -r '.message.chat.id // empty' "$1" 2>/dev/null)
  [ "$chat" = "${MATCH_CHAT:-}" ] || return 1
  text=$(jq -r '.message.text // empty' "$1" 2>/dev/null)
  case "$text" in /away*|/back*) return 0 ;; *) return 1 ;; esac
}

update_text() { jq -r '.message.text // ""' <<<"$1" 2>/dev/null; }
update_callback_index() { jq -r '(.callback_query.data // "") | split(":")[1] // ""' <<<"$1" 2>/dev/null; }
update_callback_id() { jq -r '.callback_query.id // ""' <<<"$1" 2>/dev/null; }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash plugins/dcc-telegram-notify/tests/updates.test.sh
```

Expected: `40 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/lib/updates.sh plugins/dcc-telegram-notify/tests/updates.test.sh
git commit -m "feat(telegram-notify): add update routing matchers"
```

---

## Task 4: Away mode

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` — add helpers after `resolve_account_label` (~line 189) and new CLI arms in the dispatch block at the end
- Create: `plugins/dcc-telegram-notify/tests/away.test.sh`

**Interfaces:**
- Consumes: `$TELEGRAM_NOTIFY_HOME`.
- Produces:
  - `away_armed()` → 0 while armed; deletes an expired file as a side effect
  - `away_arm <seconds>` — seconds defaults to `$TELEGRAM_AWAY_TTL`
  - `away_disarm`
  - `parse_duration <spec>` → seconds on stdout; accepts `90`, `45s`, `30m`, `2h`; prints nothing and returns 1 on anything else
  - `$AWAY_FILE`
  - CLI: `--away [duration]`, `--back`

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-telegram-notify/tests/away.test.sh`:

```bash
#!/usr/bin/env bash
# Away mode is the arming that turns the blocking gates on. It is machine-wide:
# one flag covers every project and every Claude account sharing this home.
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

check "a fresh home is disarmed" "$(away_armed && echo yes || echo no)" "no"
away_arm 3600
check "arming makes it armed" "$(away_armed && echo yes || echo no)" "yes"
away_disarm
check "disarming makes it disarmed" "$(away_armed && echo yes || echo no)" "no"

# An expiry in the past must read as disarmed AND clean itself up, so a stale
# flag can never silently gate a session forever.
printf '%s' "$(( $(date +%s) - 1 ))" > "$AWAY_FILE"
check "an expired arming reads as disarmed" "$(away_armed && echo yes || echo no)" "no"
check "an expired arming removes its own file" \
  "$([ -f "$AWAY_FILE" ] && echo yes || echo no)" "no"

printf 'garbage' > "$AWAY_FILE"
check "a corrupt away file reads as disarmed" "$(away_armed && echo yes || echo no)" "no"
away_disarm

check "a bare number is seconds" "$(parse_duration 90)" "90"
check "an s suffix is seconds" "$(parse_duration 45s)" "45"
check "an m suffix is minutes" "$(parse_duration 30m)" "1800"
check "an h suffix is hours" "$(parse_duration 2h)" "7200"
check "nonsense is refused" "$(parse_duration wat || echo refused)" "refused"
check "an empty duration is refused" "$(parse_duration "" || echo refused)" "refused"

# The CLI arms are what the slash command and the Telegram /away command call.
home="$(mktemp -d)"; env="$(mktemp -u)"
TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" bash "$SCRIPT" --away 1h >/dev/null
check "--away writes the flag" "$([ -f "$home/away" ] && echo yes || echo no)" "yes"
TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" bash "$SCRIPT" --back >/dev/null
check "--back removes the flag" "$([ -f "$home/away" ] && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-telegram-notify/tests/away.test.sh
```

Expected: FAIL lines — `away_armed: command not found`.

- [ ] **Step 3: Write the implementation**

In `scripts/dcc-telegram-notify.sh`, add the default alongside the others near line 118 (`: "${TELEGRAM_TOPIC_MODE:=shared}"`):

```bash
: "${TELEGRAM_AWAY_TTL:=7200}"
```

Then insert this block immediately after the `TELEGRAM_ACCOUNT_LABEL_RESOLVED` assignment (~line 189):

```bash
# --- Away mode ---------------------------------------------------------------
# The arming that turns the blocking gates on. Machine-wide by design: you walk
# away from the machine, not from one project, so one flag covers every project
# and every Claude account sharing this home.
AWAY_FILE="$TELEGRAM_NOTIFY_HOME/away"

away_armed() {
  local exp
  exp=$(cat "$AWAY_FILE" 2>/dev/null)
  [[ "$exp" =~ ^[0-9]+$ ]] || { rm -f "$AWAY_FILE" 2>/dev/null; return 1; }
  # An expired flag deletes itself here rather than waiting for a disarm, so a
  # forgotten arming cannot gate sessions indefinitely.
  [ "$(date +%s)" -lt "$exp" ] || { rm -f "$AWAY_FILE" 2>/dev/null; return 1; }
}

away_arm() {
  local secs="${1:-$TELEGRAM_AWAY_TTL}"
  mkdir -p "$TELEGRAM_NOTIFY_HOME" 2>/dev/null || return 0
  printf '%s' "$(( $(date +%s) + secs ))" > "$AWAY_FILE" 2>/dev/null
  return 0
}

away_disarm() { rm -f "$AWAY_FILE" 2>/dev/null; return 0; }

parse_duration() {
  local d="${1:-}"
  case "$d" in
    "")            return 1 ;;
    *[0-9]h)       printf '%s' $(( ${d%h} * 3600 )) ;;
    *[0-9]m)       printf '%s' $(( ${d%m} * 60 )) ;;
    *[0-9]s)       printf '%s' "${d%s}" ;;
    *[!0-9]*)      return 1 ;;
    *)             printf '%s' "$d" ;;
  esac
}
```

Then add two arms to the dispatch `case` at the end of the file, before the `"") main ;;` line:

```bash
    --away)
      secs=$(parse_duration "${2:-}") || secs="$TELEGRAM_AWAY_TTL"
      away_arm "$secs"
      printf 'Away mode armed for %s. Permission prompts and questions will wait for a Telegram tap.\n' \
        "$(format_duration "$secs")"
      ;;
    --back)
      away_disarm
      echo "Away mode disarmed. Prompts go straight to your terminal again."
      ;;
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash plugins/dcc-telegram-notify/tests/away.test.sh
```

Expected: `16 passed, 0 failed`.

- [ ] **Step 5: Run the whole suite to check for regressions**

```bash
bash plugins/dcc-telegram-notify/tests/run-all.sh
```

Expected: every file passes. The new `case` arms must not have disturbed the existing `--events` dispatch tests.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh plugins/dcc-telegram-notify/tests/away.test.sh
git commit -m "feat(telegram-notify): add machine-wide away mode"
```

---

## Task 5: Inline keyboards, nonces, and the `last/` marker

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` — `send()` (~line 292) and `send_message()` (~line 314)
- Create: `plugins/dcc-telegram-notify/tests/keyboard.test.sh`

**Interfaces:**
- Consumes: `send`, `send_message`, `$SEND_TOPIC`, `$TELEGRAM_CHAT_ID`.
- Produces:
  - `$SEND_KEYBOARD` — a global read by `send()`; when non-empty it is posted as `reply_markup`
  - `kb_row <label|data> …` → one JSON row
  - `kb <row> …` → the full `reply_markup` object
  - `mint_nonce` → eight lowercase alphanumeric characters
  - `pending_put <nonce> <json>` / `pending_get <nonce>` / `pending_rm <nonce>`
  - `record_last <message_id>` — writes the `last/` marker for the current destination
  - `answer_callback <callback_id> <text>` / `edit_message <message_id> <html>`

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-telegram-notify/tests/keyboard.test.sh`:

```bash
#!/usr/bin/env bash
# Inline keyboards and the bookkeeping behind them. callback_data is capped at
# 64 bytes by Telegram, so the button carries only a nonce and an index and the
# real context lives in pending/<nonce>.json on disk.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/dcc-telegram-notify.sh"

export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"
export TELEGRAM_CHAT_ID="-100"
# shellcheck disable=SC1090
source "$SCRIPT"

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

row="$(kb_row 'Allow|n1:0' 'Deny|n1:1')"
check "a row is a JSON array of buttons" "$(jq -c 'length' <<<"$row")" "2"
check "a button carries its label" "$(jq -r '.[0].text' <<<"$row")" "Allow"
check "a button carries its callback data" "$(jq -r '.[1].callback_data' <<<"$row")" "n1:1"
markup="$(kb "$row" "$(kb_row 'Back|n1:back')")"
check "the markup nests rows under inline_keyboard" \
  "$(jq -c '.inline_keyboard | length' <<<"$markup")" "2"
check "a label containing quotes survives encoding" \
  "$(jq -r '.[0].text' <<<"$(kb_row 'say "hi"|n1:0')")" 'say "hi"'

n="$(mint_nonce)"
check "a nonce is eight characters" "${#n}" "8"
check "a nonce is lowercase alphanumeric" \
  "$(printf '%s' "$n" | tr -d 'a-z0-9' | wc -c | tr -d ' ')" "0"
check "two nonces differ" "$([ "$n" != "$(mint_nonce)" ] && echo yes || echo no)" "yes"

pending_put "$n" '{"kind":"permission","message_id":7,"options":["Allow","Deny"]}'
check "a pending entry round-trips" "$(pending_get "$n" | jq -r '.kind')" "permission"
check "a missing pending entry is empty" "$(pending_get nosuchxx)" ""
pending_rm "$n"
check "a removed pending entry is gone" "$(pending_get "$n")" ""

SEND_TOPIC=7
record_last 4242
check "the last marker records the message id" \
  "$(cat "$(last_marker_path -100 7)")" "4242"
SEND_TOPIC=""
record_last 4343
check "a main-thread send records under main" \
  "$(cat "$(last_marker_path -100 "")")" "4343"

# send() must post reply_markup only when a keyboard is set. A stub curl records
# what it was handed instead of calling Telegram.
STUB_DIR="$(mktemp -d)"; PATH="$STUB_DIR:$PATH"
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CURL_STUB_ARGS"
cat > /dev/null
printf '{"ok":true,"result":{"message_id":1}}'
STUB
chmod +x "$STUB_DIR/curl"
export CURL_STUB_ARGS="$STUB_DIR/args"

SEND_KEYBOARD=""
send "plain" >/dev/null
check "no reply_markup is sent without a keyboard" \
  "$(grep -c 'reply_markup' "$CURL_STUB_ARGS" || true)" "0"
SEND_KEYBOARD="$markup"
send "with buttons" >/dev/null
check "reply_markup is sent when a keyboard is set" \
  "$(grep -c 'reply_markup' "$CURL_STUB_ARGS" || true)" "1"
SEND_KEYBOARD=""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-telegram-notify/tests/keyboard.test.sh
```

Expected: FAIL lines — `kb_row: command not found`.

- [ ] **Step 3: Write the implementation**

The test sources `dcc-telegram-notify.sh`, which must now source the library. Add this immediately after the `API=` assignment (~line 191):

```bash
# The read side lives in its own libraries so it can be tested without a session
# in play. Sourced after API/config so it inherits both.
TELEGRAM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck disable=SC1090
[ -r "$TELEGRAM_LIB_DIR/updates.sh" ] && . "$TELEGRAM_LIB_DIR/updates.sh"
```

Add `SEND_KEYBOARD` to the routing-state line (~line 194):

```bash
REPO_KEY=""; REPO_NAME=""; SEND_TOPIC=""; SEND_KEYBOARD=""
```

In `send()`, add the keyboard to the argument array immediately after the `message_thread_id` line:

```bash
  [ -n "$SEND_KEYBOARD" ] && args+=(--data-urlencode "reply_markup=${SEND_KEYBOARD}")
```

Add this block after `send_message()` (~line 326):

```bash
# --- Inline keyboards --------------------------------------------------------
# Telegram caps callback_data at 64 bytes, so a button carries only a nonce and
# a button index; the chat, topic, message id, session and option labels live in
# pending/<nonce>.json beside the rest of the state.

kb_row() {
  local a parts=()
  for a in "$@"; do
    parts+=("$(jq -nc --arg t "${a%%|*}" --arg d "${a#*|}" '{text:$t,callback_data:$d}')")
  done
  local IFS=,
  printf '[%s]' "${parts[*]}"
}

kb() { local IFS=,; printf '{"inline_keyboard":[%s]}' "$*"; }

mint_nonce() {
  local n
  n=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c 8)
  [ ${#n} -eq 8 ] || n=$(printf '%08x' $(( (RANDOM << 15 | RANDOM) & 0xffffffff )))
  printf '%s' "$n"
}

PENDING_DIR="$TELEGRAM_NOTIFY_HOME/pending"

pending_put() {
  mkdir -p "$PENDING_DIR" 2>/dev/null || return 0
  printf '%s' "$2" > "$PENDING_DIR/$1.json" 2>/dev/null
  return 0
}
pending_get() { cat "$PENDING_DIR/$1.json" 2>/dev/null; return 0; }
pending_rm()  { rm -f "$PENDING_DIR/$1.json" 2>/dev/null; return 0; }

# Written at send time so a bare message typed into a topic can be routed to the
# newest notification there without the user long-pressing to Reply.
record_last() {
  local p
  p=$(last_marker_path "$TELEGRAM_CHAT_ID" "${SEND_TOPIC:-}")
  mkdir -p "$(dirname "$p")" 2>/dev/null || return 0
  printf '%s' "$1" > "$p" 2>/dev/null
  return 0
}

# Clears the spinner on the phone. Telegram shows the text as a brief toast.
answer_callback() {
  curl -sS --max-time 10 \
    --data-urlencode "callback_query_id=$1" \
    --data-urlencode "text=${2:-}" \
    "${API}/answerCallbackQuery" >/dev/null 2>&1
  return 0
}

# Rewrites a resolved prompt so the message records its own outcome and its
# buttons cannot be tapped a second time.
edit_message() {
  local mid="$1" html="$2"
  printf '%s' "$html" | curl -sS --max-time 10 \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "message_id=${mid}" \
    --data-urlencode "text@-" \
    --data-urlencode "parse_mode=HTML" \
    "${API}/editMessageText" >/dev/null 2>&1
  return 0
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash plugins/dcc-telegram-notify/tests/keyboard.test.sh
```

Expected: `19 passed, 0 failed`.

- [ ] **Step 5: Run the whole suite**

```bash
bash plugins/dcc-telegram-notify/tests/run-all.sh
```

Expected: everything passes. Sourcing `updates.sh` from the engine must not disturb the existing tests — if `updates.test.sh` now fails on a redefined function, the library is being sourced twice; that is harmless but confirm the failure is not real.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh plugins/dcc-telegram-notify/tests/keyboard.test.sh
git commit -m "feat(telegram-notify): add inline keyboard plumbing"
```

---

## Task 6: `await.sh` — the waiting loops

**Files:**
- Create: `plugins/dcc-telegram-notify/scripts/lib/await.sh`
- Create: `plugins/dcc-telegram-notify/tests/listen.test.sh`

**Interfaces:**
- Consumes: `updates_poll`, `updates_claim`, `updates_sweep`, the matchers and `MATCH_*` globals (Tasks 1–3); `away_armed`, `away_arm`, `away_disarm`, `parse_duration`, `answer_callback`, `pending_get`, `pending_rm` (Tasks 4–5); `file_mtime`.
- Produces:
  - `await_reply <start_file> <message_id> <chat> <topic> <deadline>` → prints the reply text and returns 0; returns 1 on local typing, timeout, or conflict
  - `await_tap <nonce> <chat> <deadline>` → prints `<button_index>` and returns 0; returns 1 on timeout or conflict
  - `handle_control <update_json>` → returns 0 if the update was an `/away` or `/back` command it consumed

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-telegram-notify/tests/listen.test.sh`:

```bash
#!/usr/bin/env bash
# The turn-end listener's three exits. It runs AFTER the turn has ended, so the
# terminal is free the whole time -- your typing and your Telegram reply race,
# and whichever lands first wins.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/dcc-telegram-notify.sh"

export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"
export TELEGRAM_CHAT_ID="-100"
export TELEGRAM_ALLOWED_USERS="111"
export TELEGRAM_REPLY_POLL=1
# shellcheck disable=SC1090
source "$SCRIPT"
# shellcheck disable=SC1090
source "$HERE/../scripts/lib/await.sh"

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# A stub curl returning an empty update list, so the loops spin without network.
STUB_DIR="$(mktemp -d)"; PATH="$STUB_DIR:$PATH"
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
printf '{"ok":true,"result":[]}'
STUB
chmod +x "$STUB_DIR/curl"

mkdir -p "$STATE_DIR" "$SPOOL_DIR" "$TELEGRAM_NOTIFY_HOME/last"
start="$STATE_DIR/sess.start"
date +%s > "$start"
printf '42' > "$(last_marker_path -100 7)"

# 1. A reply already in the spool is claimed and returned as the turn's next
#    instruction.
printf '%s' '{"update_id":300,"message":{"message_id":9,"chat":{"id":-100},"message_thread_id":7,"text":"keep going","reply_to_message":{"message_id":42}}}' > "$SPOOL_DIR/300.json"
out="$(await_reply "$start" 42 -100 7 "$(( $(date +%s) + 10 ))")"; rc=$?
check "a claimed reply returns 0" "$rc" "0"
check "a claimed reply prints its text" "$out" "keep going"

# 2. A touched turn-start file means the user typed locally, so the listener
#    stands down without consuming anything.
rm -f "$SPOOL_DIR"/*.json
( sleep 1; date +%s > "$start"; touch "$start" ) &
out="$(await_reply "$start" 42 -100 7 "$(( $(date +%s) + 8 ))")"; rc=$?
wait
check "local typing makes the listener stand down" "$rc" "1"
check "standing down prints nothing" "$out" ""

# 3. An elapsed window is a quiet exit.
date +%s > "$start"
out="$(await_reply "$start" 42 -100 7 "$(( $(date +%s) + 2 ))")"; rc=$?
check "an elapsed window returns 1" "$rc" "1"
check "an elapsed window prints nothing" "$out" ""

# 4. A 409 means another consumer owns this bot; standing down beats thrashing.
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
printf '{"ok":false,"error_code":409,"description":"Conflict"}'
STUB
chmod +x "$STUB_DIR/curl"
date +%s > "$start"
start_s=$(date +%s)
await_reply "$start" 42 -100 7 "$(( start_s + 30 ))" >/dev/null; rc=$?
check "a 409 aborts the listener" "$rc" "1"
check "a 409 aborts promptly rather than waiting out the window" \
  "$([ $(( $(date +%s) - start_s )) -lt 10 ] && echo yes || echo no)" "yes"

# 5. A control command arms away mode and is never treated as an instruction.
away_disarm
handle_control '{"update_id":1,"message":{"chat":{"id":-100},"text":"/away 1h"}}'
check "an away command arms away mode" "$(away_armed && echo yes || echo no)" "yes"
handle_control '{"update_id":2,"message":{"chat":{"id":-100},"text":"/back"}}'
check "a back command disarms away mode" "$(away_armed && echo yes || echo no)" "no"
check "an ordinary message is not a control command" \
  "$(handle_control '{"update_id":3,"message":{"chat":{"id":-100},"text":"hello"}}' && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-telegram-notify/tests/listen.test.sh
```

Expected: fails at `source .../lib/await.sh: No such file or directory`.

- [ ] **Step 3: Write the implementation**

Create `plugins/dcc-telegram-notify/scripts/lib/await.sh`:

```bash
#!/usr/bin/env bash
# The two waiting loops. Sourced by dcc-telegram-notify.sh after updates.sh.
#
# await_reply runs AFTER a turn has ended (an asyncRewake Stop hook), so nothing
# is blocked while it waits. await_tap runs INSIDE a synchronous permission gate
# and does block, which is why it only ever runs while away mode is armed.

# Arming and disarming from the chat must never be mistaken for an instruction
# to Claude, so control commands are consumed before the reply matchers run.
# Returns 0 when the update was a command this consumed.
handle_control() {
  local u="$1" text
  text=$(update_text "$u")
  case "$text" in
    /away*)
      local spec secs
      spec=$(printf '%s' "$text" | awk '{print $2}')
      secs=$(parse_duration "$spec") || secs="$TELEGRAM_AWAY_TTL"
      away_arm "$secs"
      dbg "   away: armed for ${secs}s from Telegram"
      return 0 ;;
    /back*)
      away_disarm
      dbg "   away: disarmed from Telegram"
      return 0 ;;
    *) return 1 ;;
  esac
}

# Drain any control commands sitting in the spool. Called once per poll cycle by
# both loops so /away and /back work no matter which waiter is running.
drain_control() {
  local u
  while u=$(updates_claim match_command); do
    [ -n "$u" ] || break
    handle_control "$u"
  done
  return 0
}

# Wait for a reply addressed to the notification we just sent. Prints the reply
# text and returns 0; returns 1 for every other outcome, all of which mean "do
# nothing and let the session be".
await_reply() {
  local start_file="$1" msg_id="$2" chat="$3" topic="$4" deadline="$5"
  local baseline u rc
  baseline=$(file_mtime "$start_file" 2>/dev/null) || baseline=0

  MATCH_REPLY_TO="$msg_id"; MATCH_CHAT="$chat"; MATCH_TOPIC="$topic"

  while [ "$(date +%s)" -lt "$deadline" ]; do
    # UserPromptSubmit rewrites this file on every locally submitted prompt, so
    # a changed mtime means the user came back to the keyboard and won the race.
    local now_mt
    now_mt=$(file_mtime "$start_file" 2>/dev/null) || now_mt=0
    if [ "$now_mt" != "$baseline" ]; then
      dbg "   await_reply: local prompt detected, standing down"
      return 1
    fi

    updates_poll; rc=$?
    if [ "$rc" = "2" ]; then
      dbg "   await_reply: 409 conflict, another consumer owns this bot"
      return 1
    fi
    updates_sweep
    drain_control

    if u=$(updates_claim match_reply_to); then
      update_text "$u"; return 0
    fi
    if u=$(updates_claim match_bare_topic); then
      update_text "$u"; return 0
    fi
    sleep 1
  done
  dbg "   await_reply: window elapsed"
  return 1
}

# Wait for a button tap carrying our nonce. Prints the button index and returns
# 0; returns 1 on timeout or conflict, which the gate turns into "no decision"
# so the terminal picker appears exactly as it does today.
await_tap() {
  local nonce="$1" chat="$2" deadline="$3" u rc
  MATCH_NONCE="$nonce"; MATCH_CHAT="$chat"

  while [ "$(date +%s)" -lt "$deadline" ]; do
    updates_poll; rc=$?
    if [ "$rc" = "2" ]; then
      dbg "   await_tap: 409 conflict, standing down"
      return 1
    fi
    updates_sweep
    drain_control

    if u=$(updates_claim match_callback); then
      answer_callback "$(update_callback_id "$u")" "Got it"
      update_callback_index "$u"
      return 0
    fi
    sleep 1
  done
  dbg "   await_tap: window elapsed"
  return 1
}
```

Source it from the engine, right after the `updates.sh` line added in Task 5:

```bash
# shellcheck disable=SC1090
[ -r "$TELEGRAM_LIB_DIR/await.sh" ] && . "$TELEGRAM_LIB_DIR/await.sh"
```

Because `listen.test.sh` sources `await.sh` explicitly as well, the double source is harmless — bash simply redefines the functions.

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash plugins/dcc-telegram-notify/tests/listen.test.sh
```

Expected: `12 passed, 0 failed`. This file takes ~15 seconds because several checks wait out real timers.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/lib/await.sh plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh plugins/dcc-telegram-notify/tests/listen.test.sh
git commit -m "feat(telegram-notify): add reply and tap wait loops"
```

---

## Task 7: Wire the `Stop` listener and the `UserPromptSubmit` disarm

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` — `main()` (~lines 502–657)
- Modify: `plugins/dcc-telegram-notify/hooks/hooks.json`
- Modify: `plugins/dcc-telegram-notify/tests/listen.test.sh` (append before the tally)

**Interfaces:**
- Consumes: `await_reply` (Task 6), `away_armed`/`away_disarm` (Task 4), `record_last` (Task 5).
- Produces: the `Stop` branch exits 2 with the reply on saved-stderr; `state/<session>.remote` marks a remotely-driven turn.

- [ ] **Step 1: Write the failing test**

Append to `tests/listen.test.sh` before the tally:

```bash
# --- the remote marker -------------------------------------------------------
# A turn woken by a Telegram reply must not count as "the user came back", or
# replying from the phone would silently disarm away mode every time.
sess=marker-test
touch "$STATE_DIR/${sess}.remote"
check "a fresh remote marker is honoured" \
  "$(remote_marker_fresh "$sess" && echo yes || echo no)" "yes"
# Stale markers must expire: if a rewake never fires UserPromptSubmit the marker
# would otherwise linger and eat the NEXT genuine local prompt's disarm.
touch -d "@$(( $(date +%s) - 600 ))" "$STATE_DIR/${sess}.remote" 2>/dev/null \
  || touch -t "$(date -r $(( $(date +%s) - 600 )) +%Y%m%d%H%M.%S)" "$STATE_DIR/${sess}.remote"
check "a stale remote marker is ignored" \
  "$(remote_marker_fresh "$sess" && echo yes || echo no)" "no"
rm -f "$STATE_DIR/${sess}.remote"
check "a missing remote marker is not fresh" \
  "$(remote_marker_fresh "$sess" && echo yes || echo no)" "no"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-telegram-notify/tests/listen.test.sh
```

Expected: FAIL lines — `remote_marker_fresh: command not found`.

- [ ] **Step 3: Save the output file descriptors**

This is the step that is easiest to get wrong. `main()` currently silences both streams at line ~507:

```bash
  # Never let a notification failure disturb the session.
  exec 1>/dev/null 2>&1
```

Replace it with:

```bash
  # Never let a notification failure disturb the session. FDs 6 and 7 keep the
  # real stdout and stderr, because the decision hooks must print JSON on stdout
  # and the rewake listener must print the reply on stderr -- everything else
  # stays silenced.
  exec 6>&1 7>&2 1>/dev/null 2>&1
```

- [ ] **Step 4: Add the marker helper**

Add next to the away helpers added in Task 4:

```bash
# A turn woken by a Telegram reply must not disarm away mode the way a locally
# typed prompt does. The listener drops this marker when it delivers a reply.
# It expires because a rewake-driven turn may never fire UserPromptSubmit at
# all, and a lingering marker would eat the next genuine local prompt's disarm.
: "${TELEGRAM_REMOTE_MARKER_TTL:=120}"
remote_marker_fresh() {
  local f="$STATE_DIR/${1}.remote" mt
  mt=$(file_mtime "$f" 2>/dev/null) || return 1
  [ $(( $(date +%s) - mt )) -le "$TELEGRAM_REMOTE_MARKER_TTL" ]
}
```

`STATE_DIR` is defined at the top of the script, so this works when sourced.

- [ ] **Step 5: Rewrite the `UserPromptSubmit` branch**

Replace the existing branch (~line 544):

```bash
    UserPromptSubmit)
      date +%s > "$start_file"
      # Typing locally means you are back at the keyboard, so away mode ends --
      # unless this turn was itself driven by a Telegram reply.
      if remote_marker_fresh "$session"; then
        rm -f "$STATE_DIR/${session}.remote"
      else
        rm -f "$STATE_DIR/${session}.remote"
        away_disarm
      fi
      ;;
```

- [ ] **Step 6: Record the message id after every send, and add phase two**

In the `Stop` branch, replace the final `send_message "$header" "$status" "$body"` line (~line 654) with:

```bash
      local resp mid reply window deadline
      resp=$(send_message "$header" "$status" "$body")
      mid=$(jq -r '(.result.message_id // empty)' <<<"$resp" 2>/dev/null)
      [ -n "$mid" ] && record_last "$mid"

      # Phase two: keep polling for a reply to the message just sent. The turn
      # has already ended, so the terminal is free the whole time -- typing
      # locally and replying from Telegram race, and either one ends this.
      reply_enabled || exit 0
      [ -n "$mid" ] || exit 0
      if away_armed; then window="$TELEGRAM_REPLY_WINDOW_AWAY"; else window="$TELEGRAM_REPLY_WINDOW"; fi
      deadline=$(( $(date +%s) + window ))
      rm -f "$STATE_DIR/${session}.remote"
      dbg "   listen: waiting ${window}s for a reply to message $mid"
      reply=$(await_reply "$start_file" "$mid" "$TELEGRAM_CHAT_ID" "${SEND_TOPIC:-}" "$deadline") || exit 0
      [ -n "$reply" ] || exit 0

      # A rewake does not fire UserPromptSubmit, so restore the invariant that
      # the start file marks the beginning of the CURRENT turn ourselves.
      date +%s > "$start_file"
      : > "$STATE_DIR/${session}.remote"
      dbg "   listen: delivering a reply of ${#reply} chars via rewake"
      printf '%s\n' "$reply" >&7
      exit 2
      ;;
```

Also add `record_last` to the `Notification` branch's send, replacing its `send_message "$header" "$status" "$body"` line (~line 581):

```bash
      local nresp nmid
      nresp=$(send_message "$header" "$status" "$body")
      nmid=$(jq -r '(.result.message_id // empty)' <<<"$nresp" 2>/dev/null)
      [ -n "$nmid" ] && record_last "$nmid"
```

- [ ] **Step 7: Update `hooks.json`**

Change only the `Stop` entry:

```json
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/dcc-telegram-notify.sh\"",
            "asyncRewake": true,
            "timeout": 3700
          }
        ]
      }
    ]
```

The timeout sits above `TELEGRAM_REPLY_WINDOW_AWAY` (3600) so the script always decides its own lifetime rather than being cancelled mid-poll.

- [ ] **Step 8: Run the tests**

```bash
bash plugins/dcc-telegram-notify/tests/listen.test.sh
bash plugins/dcc-telegram-notify/tests/run-all.sh
```

Expected: `15 passed, 0 failed` in `listen.test.sh`; the whole suite green.

- [ ] **Step 9: Verify the JSON and the syntax**

```bash
jq . plugins/dcc-telegram-notify/hooks/hooks.json > /dev/null && echo "hooks.json ok"
bash -n plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh && echo "script ok"
claude plugin validate .
```

Expected: all three succeed.

- [ ] **Step 10: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh plugins/dcc-telegram-notify/hooks/hooks.json plugins/dcc-telegram-notify/tests/listen.test.sh
git commit -m "feat(telegram-notify): wake session on a Telegram reply"
```

---

## Task 8: The `PermissionRequest` gate

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` — new branch in `main()`'s `case`
- Modify: `plugins/dcc-telegram-notify/hooks/hooks.json`
- Create: `plugins/dcc-telegram-notify/tests/gate.test.sh`

**Interfaces:**
- Consumes: `away_armed`, `reply_enabled`, `pending_action`, `mint_nonce`, `pending_put`, `kb`, `kb_row`, `await_tap`, `edit_message`, `record_last`.
- Produces: a `PermissionRequest` branch printing a decision on FD 6, and `gate_decision <behavior>` which renders that JSON.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-telegram-notify/tests/gate.test.sh`:

```bash
#!/usr/bin/env bash
# The permission gate. It is a synchronous hook that Claude Code runs to
# completion BEFORE it draws the terminal picker, so it must return instantly
# whenever away mode is disarmed -- otherwise every approval at the keyboard
# would sit behind a Telegram poll.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/dcc-telegram-notify.sh"

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# run_hook <payload> -- one isolated run of the engine against a hook payload
HOME_DIR="$(mktemp -d)"
run_hook() {
  printf '%s' "$1" | TELEGRAM_NOTIFY_HOME="$HOME_DIR" TELEGRAM_NOTIFY_ENV="$(mktemp -u)" \
    TELEGRAM_BOT_TOKEN=t TELEGRAM_CHAT_ID=-100 TELEGRAM_ALLOWED_USERS=111 \
    bash "$SCRIPT" 2>/dev/null
}

PR='{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":".","tool_name":"Bash","tool_input":{"command":"ls"},"transcript_path":"/nonexistent"}'

rm -f "$HOME_DIR/away"
out="$(run_hook "$PR")"
check "a disarmed gate returns no decision" "$out" ""
check "a disarmed gate exits 0" "$?" "0"

# Timing is the whole point of the disarmed path: it must not poll Telegram.
s=$(date +%s); run_hook "$PR" >/dev/null; e=$(date +%s)
check "a disarmed gate returns in under 3 seconds" \
  "$([ $((e - s)) -lt 3 ] && echo yes || echo no)" "yes"

# The decision renderer is the contract with Claude Code; a typo here silently
# turns every remote approval into a no-op.
export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"
# shellcheck disable=SC1090
source "$SCRIPT"
check "an allow decision names the hook event" \
  "$(gate_decision allow | jq -r '.hookSpecificOutput.hookEventName')" "PermissionRequest"
check "an allow decision carries the behavior" \
  "$(gate_decision allow | jq -r '.hookSpecificOutput.decision.behavior')" "allow"
check "a deny decision carries the behavior" \
  "$(gate_decision deny | jq -r '.hookSpecificOutput.decision.behavior')" "deny"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-telegram-notify/tests/gate.test.sh
```

Expected: the `gate_decision` checks FAIL with `command not found`. The disarmed-gate checks may already pass, because an unrecognized `hook_event_name` currently falls through `main()`'s `case` and exits 0 — that is the correct behavior, and these checks lock it in.

- [ ] **Step 3: Write the implementation**

Add near the keyboard helpers:

```bash
# The decision contract with Claude Code. Printing nothing at all means "no
# decision", which leaves the terminal picker to handle it exactly as today.
gate_decision() {
  jq -nc --arg b "$1" \
    '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:$b}}}'
}
```

Add this branch to `main()`'s `case`, after the `Notification)` branch:

```bash
    PermissionRequest)
      # Synchronous: Claude Code runs this to completion BEFORE drawing the
      # terminal picker, so anything slow here is a delay at the keyboard.
      # Disarmed is therefore the instant path, and it is the default.
      away_armed || exit 0
      reply_enabled || exit 0

      local ptool ptarget paction pnonce pmarkup presp pmid pidx pdeadline
      ptool=$(jq -r '.tool_name // ""' <<<"$payload" 2>/dev/null)
      if [ -z "$ptool" ]; then
        paction=$(pending_action "$(jq -r '.transcript_path // ""' <<<"$payload" 2>/dev/null)")
        ptool=$(jq -r '.tool // ""' <<<"$paction" 2>/dev/null)
        ptarget=$(jq -r '.target // ""' <<<"$paction" 2>/dev/null)
      else
        ptarget=$(jq -r '
          (.tool_input // {}) |
          (.command // .url // .file_path // .notebook_path // .pattern // "")
          | gsub("\\s+"; " ")' <<<"$payload" 2>/dev/null)
        [ "${#ptarget}" -gt 150 ] && ptarget="${ptarget:0:150}…"
      fi
      [ -n "$ptool" ] || exit 0

      pnonce=$(mint_nonce)
      pmarkup=$(kb "$(kb_row "✅ Allow|${pnonce}:0" "⛔ Deny|${pnonce}:1")" \
                   "$(kb_row "🏠 I'm back|${pnonce}:back")")
      SEND_KEYBOARD="$pmarkup"
      body="▸ $ptool"
      [ -n "$ptarget" ] && body="▸ $ptool: $ptarget"
      presp=$(send_message "$header" "🔐 Needs permission" "$body")
      SEND_KEYBOARD=""
      pmid=$(jq -r '(.result.message_id // empty)' <<<"$presp" 2>/dev/null)
      [ -n "$pmid" ] || exit 0
      record_last "$pmid"
      pending_put "$pnonce" "$(jq -nc --arg m "$pmid" --arg t "$ptool" \
        '{kind:"permission",message_id:$m,tool:$t}')"

      pdeadline=$(( $(date +%s) + TELEGRAM_REPLY_WINDOW_AWAY ))
      pidx=$(await_tap "$pnonce" "$TELEGRAM_CHAT_ID" "$pdeadline")
      pending_rm "$pnonce"
      case "$pidx" in
        0) edit_message "$pmid" "$header
✅ Allowed from Telegram

$(printf '%s' "$body" | html_escape)"
           gate_decision allow >&6 ;;
        1) edit_message "$pmid" "$header
⛔ Denied from Telegram

$(printf '%s' "$body" | html_escape)"
           gate_decision deny >&6 ;;
        back)
           away_disarm
           edit_message "$pmid" "$header
🏠 Away mode off — answer at the keyboard

$(printf '%s' "$body" | html_escape)" ;;
        # A timeout returns no decision at all, so the terminal picker appears
        # exactly as it does today.
        *) edit_message "$pmid" "$header
⌛ No answer — waiting at the keyboard

$(printf '%s' "$body" | html_escape)" ;;
      esac
      exit 0
      ;;
```

- [ ] **Step 4: Register the hook**

Add to `hooks/hooks.json`, as a sibling of the other events:

```json
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/dcc-telegram-notify.sh\"",
            "timeout": 3700
          }
        ]
      }
    ]
```

No `async` — this hook must block to have a decision honoured.

- [ ] **Step 5: Run the tests**

```bash
bash plugins/dcc-telegram-notify/tests/gate.test.sh
bash plugins/dcc-telegram-notify/tests/run-all.sh
jq . plugins/dcc-telegram-notify/hooks/hooks.json > /dev/null && echo "hooks.json ok"
```

Expected: `7 passed, 0 failed` in `gate.test.sh`; the whole suite green; valid JSON.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh plugins/dcc-telegram-notify/hooks/hooks.json plugins/dcc-telegram-notify/tests/gate.test.sh
git commit -m "feat(telegram-notify): approve tools from Telegram"
```

---

## Task 9: The `AskUserQuestion` gate

**Skip this task entirely if spike 2 in Task 0 showed Claude re-asking rather than accepting the denial reason as an answer.**

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` — new branch in `main()`'s `case`
- Modify: `plugins/dcc-telegram-notify/hooks/hooks.json`
- Modify: `plugins/dcc-telegram-notify/tests/gate.test.sh` (append before the tally)

**Interfaces:**
- Consumes: everything Task 8 consumes, plus `await_reply` for the free-text path.
- Produces: a `PreToolUse` branch, and `question_decision <answer>` rendering the denial that carries the answer.

- [ ] **Step 1: Write the failing test**

Append to `tests/gate.test.sh` before the tally:

```bash
# --- the question gate -------------------------------------------------------
# PermissionRequest can only allow or deny, so it cannot supply an ANSWER. A
# PreToolUse denial whose reason names the chosen option is how the choice
# reaches Claude.
check "a question decision names the hook event" \
  "$(question_decision "Postgres" | jq -r '.hookSpecificOutput.hookEventName')" "PreToolUse"
check "a question decision denies the tool call" \
  "$(question_decision "Postgres" | jq -r '.hookSpecificOutput.permissionDecision')" "deny"
check "a question decision carries the answer in its reason" \
  "$(question_decision "Postgres" | jq -r '.hookSpecificOutput.permissionDecisionReason')" \
  "The user answered from Telegram: Postgres"

PTU='{"hook_event_name":"PreToolUse","session_id":"s2","cwd":".","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which database?","options":[{"label":"Postgres"},{"label":"SQLite"}]}]},"transcript_path":"/nonexistent"}'
rm -f "$HOME_DIR/away"
out="$(run_hook "$PTU")"
check "a disarmed question gate returns no decision" "$out" ""
s=$(date +%s); run_hook "$PTU" >/dev/null; e=$(date +%s)
check "a disarmed question gate returns in under 3 seconds" \
  "$([ $((e - s)) -lt 3 ] && echo yes || echo no)" "yes"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-telegram-notify/tests/gate.test.sh
```

Expected: FAIL — `question_decision: command not found`.

- [ ] **Step 3: Write the implementation**

Add next to `gate_decision`:

```bash
# PermissionRequest can allow or deny but cannot supply an answer, so a question
# is resolved by denying the tool call with a reason that names the choice.
question_decision() {
  jq -nc --arg r "The user answered from Telegram: $1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",
      permissionDecisionReason:$r}}'
}
```

Add this branch to `main()`'s `case`:

```bash
    PreToolUse)
      # Matched to AskUserQuestion only, so this never runs on an ordinary tool
      # call and costs nothing the rest of the time.
      away_armed || exit 0
      reply_enabled || exit 0

      local qtext qopts qnonce qrow qmarkup qresp qmid qidx qdeadline qanswer i
      qtext=$(jq -r '.tool_input.questions[0].question // ""' <<<"$payload" 2>/dev/null)
      [ -n "$qtext" ] || exit 0
      mapfile -t qopts < <(jq -r '[.tool_input.questions[0].options[]?.label] | .[]' <<<"$payload" 2>/dev/null)
      [ "${#qopts[@]}" -gt 0 ] || exit 0

      qnonce=$(mint_nonce)
      qrow=()
      for i in "${!qopts[@]}"; do qrow+=("${qopts[$i]}|${qnonce}:${i}"); done
      qmarkup=$(kb "$(kb_row "${qrow[@]}")" "$(kb_row "🏠 I'm back|${qnonce}:back")")
      SEND_KEYBOARD="$qmarkup"
      body="$qtext"
      qresp=$(send_message "$header" "❓ Needs your input" "$body")
      SEND_KEYBOARD=""
      qmid=$(jq -r '(.result.message_id // empty)' <<<"$qresp" 2>/dev/null)
      [ -n "$qmid" ] || exit 0
      record_last "$qmid"
      pending_put "$qnonce" "$(jq -nc --arg m "$qmid" '{kind:"question",message_id:$m}')"

      qdeadline=$(( $(date +%s) + TELEGRAM_REPLY_WINDOW_AWAY ))
      qidx=$(await_tap "$qnonce" "$TELEGRAM_CHAT_ID" "$qdeadline")
      pending_rm "$qnonce"
      case "$qidx" in
        back)
          away_disarm
          edit_message "$qmid" "$header
🏠 Away mode off — answer at the keyboard

$(printf '%s' "$body" | html_escape)" ;;
        ''|*[!0-9]*)
          edit_message "$qmid" "$header
⌛ No answer — waiting at the keyboard

$(printf '%s' "$body" | html_escape)" ;;
        *)
          qanswer="${qopts[$qidx]}"
          edit_message "$qmid" "$header
✅ Answered from Telegram: $(printf '%s' "$qanswer" | html_escape)

$(printf '%s' "$body" | html_escape)"
          question_decision "$qanswer" >&6 ;;
      esac
      exit 0
      ;;
```

- [ ] **Step 4: Register the hook**

Add to `hooks/hooks.json`:

```json
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/dcc-telegram-notify.sh\"",
            "timeout": 3700
          }
        ]
      }
    ]
```

The matcher is `AskUserQuestion` and nothing else — a broader matcher would spawn a bash process on every single tool call.

- [ ] **Step 5: Run the tests**

```bash
bash plugins/dcc-telegram-notify/tests/gate.test.sh
bash plugins/dcc-telegram-notify/tests/run-all.sh
jq . plugins/dcc-telegram-notify/hooks/hooks.json > /dev/null && echo "hooks.json ok"
```

Expected: `12 passed, 0 failed` in `gate.test.sh`; the whole suite green.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh plugins/dcc-telegram-notify/hooks/hooks.json plugins/dcc-telegram-notify/tests/gate.test.sh
git commit -m "feat(telegram-notify): answer questions from Telegram"
```

---

## Task 10: Configuration, status, documentation, and the version bump

**Files:**
- Modify: `plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh` — `seed_config()` template and the dispatch `case`
- Modify: `plugins/dcc-telegram-notify/telegram.env.example`
- Modify: `plugins/dcc-telegram-notify/README.md`
- Modify: `plugins/dcc-telegram-notify/DESIGN.md`
- Modify: `plugins/dcc-telegram-notify/commands/dcc-telegram-notify.md`
- Modify: `plugins/dcc-telegram-notify/.claude-plugin/plugin.json`

**Interfaces:**
- Produces: `--reply-status` CLI arm; `/dcc-telegram-notify away|back|whoami` subcommands.

- [ ] **Step 1: Extend the seeded config template**

In `seed_config()`, insert before the `# --- Optional LLM turn summaries` block:

```
# --- Replying from Telegram --------------------------------------------------
# Reply to a notification and the session picks your message up and keeps
# working. THIS IS OFF until you list at least one Telegram user id below: a
# reply is an instruction Claude executes, and while away mode is armed a tap
# approves a tool call, so anyone able to post in the chat would otherwise have
# command execution on this machine.
# Find your id with: /dcc-telegram-notify whoami
TELEGRAM_ALLOWED_USERS=

# Master switch for the read side. off = notifications only, as before.
TELEGRAM_REPLY=on

# How long a finished turn keeps listening for a reply, in seconds. Nothing is
# blocked during this window -- the turn has already ended.
TELEGRAM_REPLY_WINDOW=600

# The same window while away mode is armed, which also governs how long a
# permission prompt waits for your tap before falling back to the terminal.
TELEGRAM_REPLY_WINDOW_AWAY=3600

# Seconds per getUpdates long-poll, and how long an unclaimed update is kept.
TELEGRAM_REPLY_POLL=3
TELEGRAM_SPOOL_TTL=300

# Default duration for /dcc-telegram-notify away when you don't name one.
TELEGRAM_AWAY_TTL=7200
```

Mirror the same block into `telegram.env.example`.

- [ ] **Step 2: Add `--reply-status` and `--whoami`**

Add to the dispatch `case`:

```bash
    --reply-status)
      printf 'read side:      %s\n' "$(reply_enabled && echo enabled || echo disabled)"
      printf 'allowlist:      %s\n' \
        "$([ -n "$TELEGRAM_ALLOWED_USERS" ] && printf '%s id(s)' "$(printf '%s' "$TELEGRAM_ALLOWED_USERS" | tr ',' ' ' | wc -w | tr -d ' ')" || echo 'EMPTY — reply-back is off')"
      printf 'away mode:      %s\n' "$(away_armed && echo armed || echo disarmed)"
      printf 'spool depth:    %s\n' "$(ls "$SPOOL_DIR" 2>/dev/null | wc -l | tr -d ' ')"
      printf 'update offset:  %s\n' "$(updates_offset_get)"
      echo
      echo "Note: getUpdates is exclusive per bot token. Exactly one machine may"
      echo "have TELEGRAM_REPLY=on for a given bot; a second machine needs its own."
      ;;
    --whoami)
      [ -n "$TELEGRAM_BOT_TOKEN" ] || die "Set TELEGRAM_BOT_TOKEN first"
      echo "Send any message to your bot now, then press Enter."
      read -r _ || true
      curl -sS --max-time 15 "${API}/getUpdates" | jq -r '
        [ .result[] | (.message // .callback_query // empty) | .from
          | select(. != null) | "  \(.id)   \(.first_name // "")\(if .username then " (@" + .username + ")" else "" end)" ]
        | unique | if length == 0 then "  (nothing seen — post a message to the bot and retry)" else .[] end'
      echo
      echo "Put the id in TELEGRAM_ALLOWED_USERS in your telegram.env."
      ;;
```

Update the `die` line in the final `*)` arm to list the new flags:

```bash
    *) die "unknown option: $1 (use --discover, --test, --edit, --events, --away, --back, --reply-status, --whoami, or pipe hook JSON on stdin)" ;;
```

- [ ] **Step 3: Document in the README**

Add a `## Replying from Telegram` section after `## Which events notify you`, covering:

- What a reply does at turn end (wakes the session, nothing is blocked, your typing wins the race if it lands first).
- Away mode: what it gates, how to arm and disarm, that it is machine-wide, and that it expires.
- The setup step: run `/dcc-telegram-notify whoami`, put the id in `TELEGRAM_ALLOWED_USERS`, and note that reply-back does nothing until you do.
- The three gotchas, each as its own short paragraph, worded from the spec's "Known limitations" section: bot privacy mode hides bare group messages so you must either disable it in BotFather or use Telegram's Reply function; `getUpdates` is exclusive so exactly one machine per bot token may enable the read side; and a reply is an instruction Claude executes, with the allowlist as the only boundary.

Add the seven new variables to the config reference table with the defaults from Global Constraints.

Amend the existing bullet under **Notes and gotchas** that reads "**Same bot on many machines is fine** — sending has no polling conflict" to say that this holds for the send side only, and that the read side must be enabled on exactly one machine.

- [ ] **Step 4: Document in DESIGN.md**

Add a `## Two-way replies` section recording the four decisions that are not obvious from the code: why turn end and permissions use different mechanisms (asyncRewake runs after the turn ends so nothing blocks; the gates run before the terminal picker is drawn so they cannot race it), why the spool exists (`getUpdates` exclusivity), why the claim is a rename (atomicity across concurrent waiters), and why an empty allowlist disables everything (upgrade safety plus the security boundary). Link to the spec by path.

- [ ] **Step 5: Extend the slash command**

In `commands/dcc-telegram-notify.md`, change the front-matter `argument-hint` to:

```
argument-hint: "[setup|edit|test|discover|status|away|back|whoami]"
```

Add three subcommand sections mirroring the existing style: `away` runs `--away $2`, `back` runs `--back`, and `whoami` runs `--whoami` and tells the user to paste the id into `TELEGRAM_ALLOWED_USERS`. Extend the `setup` flow with a step between the chat-id step and the test step that runs the `whoami` flow and writes the id into the config with an Edit. Extend `status` to also run `--reply-status` and report it.

- [ ] **Step 6: Bump the version**

In `.claude-plugin/plugin.json`, change `"version": "1.1.0"` to `"version": "1.2.0"`.

- [ ] **Step 7: Verify everything**

```bash
bash plugins/dcc-telegram-notify/tests/run-all.sh
bash -n plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh
bash -n plugins/dcc-telegram-notify/scripts/lib/updates.sh
bash -n plugins/dcc-telegram-notify/scripts/lib/await.sh
jq . plugins/dcc-telegram-notify/hooks/hooks.json > /dev/null && echo "hooks.json ok"
claude plugin validate .
printf '' | TELEGRAM_NOTIFY_HOME="$(mktemp -d)" bash plugins/dcc-telegram-notify/scripts/dcc-telegram-notify.sh --reply-status
```

Expected: suite green, all syntax checks clean, validate passes, and `--reply-status` reports the read side disabled with an empty allowlist.

- [ ] **Step 8: Live end-to-end check**

With a real token and your own id in `TELEGRAM_ALLOWED_USERS`, on Windows/Git Bash:

1. Finish a turn, reply to the notification from your phone, and confirm the session resumes and acts on the text.
2. Finish a turn, then type locally within the window, and confirm nothing from Telegram is injected afterwards.
3. Run `/dcc-telegram-notify away 10m`, trigger a permission prompt, tap Allow, and confirm the tool runs and the Telegram message rewrites itself to "Allowed from Telegram".
4. Run `/dcc-telegram-notify back`, trigger a permission prompt, and confirm the terminal picker appears immediately with no delay.
5. Clear `TELEGRAM_ALLOWED_USERS`, finish a turn, and confirm with `ps` that no listener process outlives it.

- [ ] **Step 9: Commit**

```bash
git add plugins/dcc-telegram-notify docs
git commit -m "feat(telegram-notify): document and ship reply-back 1.2.0"
```

---

## Self-review notes

Checked against the spec on 2026-08-09.

**Spec coverage.** Every spec section maps to a task: flow A → Tasks 6–7; flow B → Tasks 8–9; spool protocol → Tasks 1–2; authorization → Task 1; predicates → Task 3; inline keyboards → Task 5; away mode → Task 4; enablement → Task 1 (`reply_enabled`); configuration → Tasks 1, 4, 10; components → the File Structure table; error handling → the 409 path in Task 2, the guard in `reply_enabled`, and the no-decision fallbacks in Tasks 8–9; known limitations → Task 10 steps 3–4; spikes → Task 0; testing → the four test files.

**One deliberate deviation from the spec.** The spec says the `pending/` entry is removed when its waiter resolves or times out; the plan also removes it on the `back` and timeout paths, which the spec left implicit. No `TELEGRAM_SPOOL_TTL`-style sweep exists for `pending/` because every code path that creates an entry also removes it.

**Interface consistency.** `last_marker_path`, `update_text`, `update_callback_index`, and `update_callback_id` are defined in Task 3 and used in Tasks 5–9 under those exact names. `file_mtime` is defined in Task 1 and used in Tasks 6–7. `MATCH_REPLY_TO`/`MATCH_CHAT`/`MATCH_TOPIC`/`MATCH_NONCE` are set only in `await_reply` and `await_tap`. FD 6 is stdout for decisions, FD 7 is stderr for the rewake text; both are established in Task 7 step 3 and used in Tasks 7–9.

**Ordering constraint.** Task 5 adds the `source` line for `updates.sh`, so Tasks 1–3 must land before any test sources the engine script expecting the library's functions. Task 7 depends on Task 5's `record_last` and Task 6's `await_reply`. Task 9 depends on Task 8's `run_hook` helper in the shared test file.
