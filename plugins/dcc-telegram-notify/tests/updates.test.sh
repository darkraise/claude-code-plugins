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
updates_claim match_race | jq -r '.message.text // ""' > "$TELEGRAM_NOTIFY_HOME/race_a.txt" &
updates_claim match_race | jq -r '.message.text // ""' > "$TELEGRAM_NOTIFY_HOME/race_b.txt" &
wait
a=$(cat "$TELEGRAM_NOTIFY_HOME/race_a.txt" 2>/dev/null)
b=$(cat "$TELEGRAM_NOTIFY_HOME/race_b.txt" 2>/dev/null)
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

# --- with_lock ---------------------------------------------------------------
LOCKP="$TELEGRAM_NOTIFY_HOME/t.lock"
lock_probe() { printf 'ran'; }
check "with_lock runs its command" "$(with_lock "$LOCKP" lock_probe)" "ran"
lock_fail() { return 7; }
with_lock "$LOCKP" lock_fail
check "with_lock propagates the command's exit code" "$?" "7"
check "with_lock leaves no lock behind" \
  "$([ -d "$LOCKP.d" ] && echo yes || echo no)" "no"

# The mkdir fallback is the path Windows takes, so force it everywhere.
export TELEGRAM_LOCK_FORCE_MKDIR=1
check "the mkdir fallback runs its command" "$(with_lock "$LOCKP" lock_probe)" "ran"
check "the mkdir fallback releases the lock" \
  "$([ -d "$LOCKP.d" ] && echo yes || echo no)" "no"

# A held lock must be refused, not queued -- another waiter is already polling.
mkdir "$LOCKP.d"
with_lock "$LOCKP" lock_probe >/dev/null
check "a held lock is refused" "$?" "1"

# A lock left by a killed holder must not wedge the feature forever.
touch -d "@$(( $(date +%s) - 300 ))" "$LOCKP.d" 2>/dev/null \
  || touch -t "$(date -r $(( $(date +%s) - 300 )) +%Y%m%d%H%M.%S)" "$LOCKP.d"
check "a stale lock is stolen" "$(with_lock "$LOCKP" lock_probe)" "ran"
unset TELEGRAM_LOCK_FORCE_MKDIR
rm -rf "$LOCKP.d" "$LOCKP.f"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
