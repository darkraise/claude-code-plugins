#!/usr/bin/env bash
# Tests for the Telegram read side: the spool, the offset, the allowlist filter,
# and the atomic claim that stops two sessions consuming one reply.
set -uo pipefail

# Every mktemp call below is host scratch space this file never removes on
# its own; across repeated runs that leaves thousands of orphaned tmp.*
# entries in the host's /tmp (both -d directories, and -u paths that a later
# redirect such as `2>"$errfile"` turns into a real file). Wrapping mktemp
# records each path it hands out to a FILE, not a variable: most calls here
# happen inside a $(...) command substitution, which forks its own subshell,
# and a variable set there is lost the moment that subshell exits -- a file
# survives it. The EXIT trap then sweeps every path this file made that
# actually exists on disk, not just the first.
_TEST_TMP_LIST="${TMPDIR:-/tmp}/dcc-telegram-test-tmp.$$"
mktemp() {
  local d
  d="$(command mktemp "$@")"
  printf '%s\n' "$d" >> "$_TEST_TMP_LIST"
  printf '%s' "$d"
}
trap '
  if [ -f "$_TEST_TMP_LIST" ]; then
    while IFS= read -r _d; do [ -e "$_d" ] && rm -rf "$_d"; done < "$_TEST_TMP_LIST"
    rm -f "$_TEST_TMP_LIST"
  fi
' EXIT

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

# A claimer hard-killed between its mv (claim) and rm (release) leaves a
# claimed.*.json file in UPDATES_DIR itself, outside SPOOL_DIR -- the sweep
# must reclaim those too, on the same TTL, or they pile up forever.
: > "$UPDATES_DIR/claimed.30.111.222.json"
touch -d "@$(( $(date +%s) - 600 ))" "$UPDATES_DIR/claimed.30.111.222.json" 2>/dev/null \
  || touch -t "$(date -r $(( $(date +%s) - 600 )) +%Y%m%d%H%M.%S)" "$UPDATES_DIR/claimed.30.111.222.json"
: > "$UPDATES_DIR/claimed.31.111.223.json"
updates_sweep
check "a stale abandoned claim file is swept" \
  "$([ -f "$UPDATES_DIR/claimed.30.111.222.json" ] && echo yes || echo no)" "no"
check "a fresh abandoned claim file survives the sweep" \
  "$([ -f "$UPDATES_DIR/claimed.31.111.223.json" ] && echo yes || echo no)" "yes"

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

# --- matchers ----------------------------------------------------------------
mk() { printf '%s' "$2" > "$SPOOL_DIR/$1.json"; printf '%s' "$SPOOL_DIR/$1.json"; }

MATCH_REPLY_TO=42 MATCH_CHAT=-100 MATCH_TOPIC=7 MATCH_NONCE=abc12345

f=$(mk 200 '{"update_id":200,"message":{"message_id":50,"chat":{"id":-100},"message_thread_id":7,"text":"go on","reply_to_message":{"message_id":42}}}')
check "a reply to our notification matches" "$(match_reply_to "$f" && echo yes || echo no)" "yes"

f=$(mk 201 '{"update_id":201,"message":{"message_id":51,"chat":{"id":-100},"message_thread_id":7,"text":"other","reply_to_message":{"message_id":41}}}')
check "a reply to someone else's notification does not match" \
  "$(match_reply_to "$f" && echo yes || echo no)" "no"

# message_id is only unique within a chat, so a matching id from a different
# chat (a DM alongside the group, say) must not be claimed.
f=$(mk 201b '{"update_id":2011,"message":{"message_id":63,"chat":{"id":-200},"message_thread_id":7,"text":"cross chat","reply_to_message":{"message_id":42}}}')
check "a reply with a matching id in a different chat does not match" \
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

# An explicit reply is match_reply_to's business even when its chat, topic, and
# reply_to_message.message_id all line up with the newest marker; claiming it
# here too would let a single update satisfy two matchers at once.
f=$(mk 203b '{"update_id":2031,"message":{"message_id":58,"chat":{"id":-100},"message_thread_id":7,"text":"explicit","reply_to_message":{"message_id":42}}}')
check "a reply carrying reply_to_message is not claimed as bare" \
  "$(match_bare_topic "$f" && echo yes || echo no)" "no"

# Telegram auto-fills reply_to_message with the topic's own root message even
# when the user typed a plain answer, so that case must still be claimed bare.
f=$(mk 203c '{"update_id":2032,"message":{"message_id":59,"chat":{"id":-100},"message_thread_id":7,"text":"topic root reply","reply_to_message":{"message_id":7}}}')
check "a topic-root auto-reply still matches bare" \
  "$(match_bare_topic "$f" && echo yes || echo no)" "yes"
f=$(mk 203d '{"update_id":2033,"message":{"message_id":60,"chat":{"id":-100},"message_thread_id":7,"text":"explicit elsewhere","reply_to_message":{"message_id":5000}}}')
check "a reply pointing elsewhere still does not match bare" \
  "$(match_bare_topic "$f" && echo yes || echo no)" "no"

check "the main thread renders as the literal name main" \
  "$(basename "$(last_marker_path -100 "")")" "-100.main"
check "a real topic id is preserved in the marker path" \
  "$(basename "$(last_marker_path -100 7)")" "-100.7"

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
f=$(mk 208 '{"update_id":208,"message":{"message_id":56,"chat":{"id":-999},"text":"/away 2h"}}')
check "an away command in another chat does not match" \
  "$(match_command "$f" && echo yes || echo no)" "no"
f=$(mk 209 '{"update_id":209,"message":{"message_id":57,"chat":{"id":-100},"text":"/back"}}')
check "a back command matches anywhere in our chat" \
  "$(match_command "$f" && echo yes || echo no)" "yes"
f=$(mk 210 '{"update_id":210,"message":{"message_id":61,"chat":{"id":-100},"text":"/backend deploy failed"}}')
check "a message merely starting with /back is not a command" \
  "$(match_command "$f" && echo yes || echo no)" "no"
rm -f "$SPOOL_DIR"/*.json

# --- config sanitization boundary (Task 5 additional work) -------------------
# TELEGRAM_REPLY_POLL, TELEGRAM_SPOOL_TTL and TELEGRAM_LOCK_STALE are config
# text a user can hand-edit, and each reaches this library's own arithmetic or
# `[ -gt ]` compares. Each variable is fixed at source time, so every case here
# sources a fresh copy of the library in its own subprocess with the value
# under test already in its environment. Sinks are exercised directly (not
# just sanitize_seconds itself) so a broken call site, not just a broken
# helper, is what these prove.
touch_ago() { # touch_ago <seconds-ago> <path>
  touch -d "@$(( $(date +%s) - $1 ))" "$2" 2>/dev/null \
    || touch -t "$(date -r $(( $(date +%s) - $1 )) +%Y%m%d%H%M.%S)" "$2"
}

# TELEGRAM_REPLY_POLL feeds `curl --max-time "$((TELEGRAM_REPLY_POLL + 10))"`
# in _updates_poll_locked. A stub curl records the --max-time value it was
# handed instead of calling Telegram.
STUB2_DIR="$(mktemp -d)"
cat > "$STUB2_DIR/curl" <<'STUB'
#!/usr/bin/env bash
prev=""
for a in "$@"; do
  [ "$prev" = "--max-time" ] && printf '%s' "$a" > "$CURL_MAXTIME_FILE"
  prev="$a"
done
cat >/dev/null 2>/dev/null
printf '{"ok":true,"result":[]}'
STUB
chmod +x "$STUB2_DIR/curl"

poll_maxtime() { # poll_maxtime <TELEGRAM_REPLY_POLL value> <errfile>
  local home maxfile
  home="$(mktemp -d)"; maxfile="$(mktemp -u)"
  PATH="$STUB2_DIR:$PATH" TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_REPLY_POLL="$1" \
    CURL_MAXTIME_FILE="$maxfile" bash -c '
      set -uo pipefail
      API="https://example.invalid/botTEST"; dbg() { :; }
      # shellcheck disable=SC1090
      source "'"$LIB"'"
      updates_poll
    ' >/dev/null 2>"$2"
  cat "$maxfile" 2>/dev/null
}
errfile="$(mktemp -u)"
check "TELEGRAM_REPLY_POLL=banana falls back to the default poll timeout (3+10)" \
  "$(poll_maxtime banana "$errfile")" "13"
check "TELEGRAM_REPLY_POLL=banana produces zero bytes on stderr" \
  "$(wc -c < "$errfile" | tr -d ' ')" "0"
errfile="$(mktemp -u)"
check "TELEGRAM_REPLY_POLL=007 normalizes to decimal 7, not a fallback or octal misread" \
  "$(poll_maxtime 007 "$errfile")" "17"
check "TELEGRAM_REPLY_POLL=007 produces zero bytes on stderr" \
  "$(wc -c < "$errfile" | tr -d ' ')" "0"

# TELEGRAM_SPOOL_TTL feeds `[ $((now - mt)) -gt "$TELEGRAM_SPOOL_TTL" ]` in
# updates_sweep. Chosen ages straddle the fallback default (300s) so a
# non-numeric value that silently fell back to 0 (swept always) or stayed
# unsanitized (a fatal `[` error) would both be caught here.
sweep_survives() { # sweep_survives <TELEGRAM_SPOOL_TTL value> <age-seconds> <errfile>
  local home
  home="$(mktemp -d)"
  TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_SPOOL_TTL="$1" bash -c '
    set -uo pipefail
    API="x"; dbg() { :; }
    # shellcheck disable=SC1090
    source "'"$LIB"'"
    mkdir -p "$SPOOL_DIR"
    printf "{}" > "$SPOOL_DIR/1.json"
    '"$(declare -f touch_ago)"'
    touch_ago '"$2"' "$SPOOL_DIR/1.json"
    updates_sweep
    [ -f "$SPOOL_DIR/1.json" ] && echo survived || echo swept
  ' 2>"$3"
}
errfile="$(mktemp -u)"
check "TELEGRAM_SPOOL_TTL=banana falls back to the default 300s (400s-old entry swept)" \
  "$(sweep_survives banana 400 "$errfile")" "swept"
check "TELEGRAM_SPOOL_TTL=banana produces zero bytes on stderr" \
  "$(wc -c < "$errfile" | tr -d ' ')" "0"
errfile="$(mktemp -u)"
check "TELEGRAM_SPOOL_TTL=0005 normalizes to decimal 5, not the 300s default (10s-old entry swept)" \
  "$(sweep_survives 0005 10 "$errfile")" "swept"
check "TELEGRAM_SPOOL_TTL=0005 produces zero bytes on stderr" \
  "$(wc -c < "$errfile" | tr -d ' ')" "0"

# TELEGRAM_LOCK_STALE feeds the mkdir-fallback lock steal in
# lock_mkdir_acquire. A lock dir older than the effective threshold must be
# stolen (with_lock's probe runs); one younger must not.
lock_stolen() { # lock_stolen <TELEGRAM_LOCK_STALE value> <age-seconds> <errfile>
  local home
  home="$(mktemp -d)"
  TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_LOCK_STALE="$1" TELEGRAM_LOCK_FORCE_MKDIR=1 bash -c '
    set -uo pipefail
    API="x"; dbg() { :; }
    # shellcheck disable=SC1090
    source "'"$LIB"'"
    LOCKP="$TELEGRAM_NOTIFY_HOME/t.lock"
    mkdir "$LOCKP.d"
    '"$(declare -f touch_ago)"'
    touch_ago '"$2"' "$LOCKP.d"
    probe() { printf ran; }
    with_lock "$LOCKP" probe
  ' 2>"$3"
}
errfile="$(mktemp -u)"
check "TELEGRAM_LOCK_STALE=banana falls back to the default 60s (70s-old lock stolen)" \
  "$(lock_stolen banana 70 "$errfile")" "ran"
check "TELEGRAM_LOCK_STALE=banana produces zero bytes on stderr" \
  "$(wc -c < "$errfile" | tr -d ' ')" "0"
errfile="$(mktemp -u)"
check "TELEGRAM_LOCK_STALE=005 normalizes to decimal 5, not the 60s default (6s-old lock stolen)" \
  "$(lock_stolen 005 6 "$errfile")" "ran"
check "TELEGRAM_LOCK_STALE=005 produces zero bytes on stderr" \
  "$(wc -c < "$errfile" | tr -d ' ')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
