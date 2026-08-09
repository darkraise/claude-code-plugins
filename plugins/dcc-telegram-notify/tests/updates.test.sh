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

# A holder whose lock was stolen while it slept must not delete the new
# holder's lock on release -- that would admit a third process alongside it.
lock_mkdir_acquire "$LOCKP" "token-a"
printf 'token-b' > "$LOCKP.d/owner"
lock_mkdir_release "$LOCKP" "token-a"
check "release by a stale token leaves the current holder's lock" \
  "$([ -d "$LOCKP.d" ] && echo yes || echo no)" "yes"
printf 'token-a' > "$LOCKP.d/owner"
lock_mkdir_release "$LOCKP" "token-a"
check "release by the current owner token removes the lock" \
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
  {"update_id":101,"callback_query":{"id":"cb1","data":"abc12345:0","from":{"id":222}}},
  {"update_id":102,"message":{"message_id":6,"text":"from a stranger","from":{"id":999},"chat":{"id":-100}}}
]}
JSON
updates_offset_set 0
updates_poll
check "poll returns 0 on a good response" "$?" "0"
check "allowed senders are spooled" \
  "$([ -f "$SPOOL_DIR/100.json" ] && echo yes || echo no)" "yes"
check "callback queries from allowed users are spooled" \
  "$([ -f "$SPOOL_DIR/101.json" ] && echo yes || echo no)" "yes"
check "a stranger never reaches the spool" \
  "$([ -f "$SPOOL_DIR/102.json" ] && echo yes || echo no)" "no"
# The filtered-out update is deliberately the HIGHEST id in the batch: if the
# offset were computed over spooled updates only, it would stop at 101 and the
# stranger's messages would be refetched forever.
check "the offset advances past a filtered update that is the batch's highest" \
  "$(updates_offset_get)" "102"

# A replayed identical response must not duplicate anything.
updates_poll
check "re-spooling the same update_id yields one file" \
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
