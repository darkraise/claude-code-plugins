#!/usr/bin/env bash
# The turn-end listener's three exits. It runs AFTER the turn has ended, so the
# terminal is free the whole time -- your typing and your Telegram reply race,
# and whichever lands first wins.
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
#    stands down without consuming anything. The window is 8s and the touch
#    lands at 1s: a plain timeout would ALSO return 1 with no output, so
#    promptness is what actually distinguishes "stood down" from "timed out"
#    and is what catches a dropped local-typing check.
rm -f "$SPOOL_DIR"/*.json
start2_s=$(date +%s)
( sleep 1; date +%s > "$start"; touch "$start" ) &
out="$(await_reply "$start" 42 -100 7 "$(( $(date +%s) + 8 ))")"; rc=$?
wait
check "local typing makes the listener stand down" "$rc" "1"
check "standing down prints nothing" "$out" ""
check "standing down for local typing happens promptly, not by timing out" \
  "$([ $(( $(date +%s) - start2_s )) -lt 6 ] && echo yes || echo no)" "yes"

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

# The 409 stub from check 4 must not leak into what follows: any check below
# that reaches updates_poll (via await_reply) would otherwise abort on a
# conflict it never actually hit, silently skipping whatever it meant to prove.
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
printf '{"ok":true,"result":[]}'
STUB
chmod +x "$STUB_DIR/curl"

# 5. A control command arms away mode and is never treated as an instruction.
away_disarm
handle_control '{"update_id":1,"message":{"chat":{"id":-100},"text":"/away 1h"}}'
check "an away command arms away mode" "$(away_armed && echo yes || echo no)" "yes"
handle_control '{"update_id":2,"message":{"chat":{"id":-100},"text":"/back"}}'
check "a back command disarms away mode" "$(away_armed && echo yes || echo no)" "no"
check "an ordinary message is not a control command" \
  "$(handle_control '{"update_id":3,"message":{"chat":{"id":-100},"text":"hello"}}' && echo yes || echo no)" "no"

# 5b. handle_control's patterns must agree with match_command's in updates.sh
#     (see the WHY comment above handle_control): a word merely starting with
#     /away or /back is not a command, in either function. The state is
#     asserted explicitly before AND after each call -- the return code alone
#     would pass even if the function armed/disarmed and then returned 1.
away_disarm
check "away is disarmed before the /awayfoo probe" "$(away_armed && echo yes || echo no)" "no"
check "/awayfoo is not a control command" \
  "$(handle_control '{"update_id":4,"message":{"chat":{"id":-100},"text":"/awayfoo"}}' && echo yes || echo no)" "no"
check "/awayfoo does not arm away mode" "$(away_armed && echo yes || echo no)" "no"

away_arm 999
check "away is armed before the /backup probe" "$(away_armed && echo yes || echo no)" "yes"
check "/backup is not a control command" \
  "$(handle_control '{"update_id":5,"message":{"chat":{"id":-100},"text":"/backup"}}' && echo yes || echo no)" "no"
check "/backup does not disarm away mode" "$(away_armed && echo yes || echo no)" "yes"
away_disarm

check "bare /away still arms away mode" \
  "$(handle_control '{"update_id":6,"message":{"chat":{"id":-100},"text":"/away"}}' >/dev/null; away_armed && echo yes || echo no)" "yes"
away_disarm
check "/away with an argument still arms away mode" \
  "$(handle_control '{"update_id":7,"message":{"chat":{"id":-100},"text":"/away 2h"}}' >/dev/null; away_armed && echo yes || echo no)" "yes"
check "bare /back still disarms away mode" \
  "$(handle_control '{"update_id":8,"message":{"chat":{"id":-100},"text":"/back"}}' >/dev/null; away_armed && echo yes || echo no)" "no"

# 6. Every matcher fails CLOSED when its MATCH_* global is unset (Task 3's
#    carried finding): a real chat id never equals the empty string, so a
#    waiter that forgot to set one gets silence, not an error. Prove that
#    await_reply's own claim setup can't accidentally rely on a stale global
#    from a previous call by unsetting MATCH_CHAT and confirming a reply that
#    would otherwise match is left unclaimed.
unset MATCH_CHAT MATCH_REPLY_TO MATCH_TOPIC
printf '%s' '{"update_id":301,"message":{"message_id":10,"chat":{"id":-100},"message_thread_id":7,"text":"unset chat","reply_to_message":{"message_id":42}}}' > "$SPOOL_DIR/301.json"
check "a claim with MATCH_CHAT unset fails closed rather than matching" \
  "$(MATCH_REPLY_TO=42 MATCH_TOPIC=7 updates_claim match_reply_to >/dev/null && echo yes || echo no)" "no"
check "the update is left unclaimed in the spool" \
  "$([ -f "$SPOOL_DIR/301.json" ] && echo yes || echo no)" "yes"
rm -f "$SPOOL_DIR"/*.json

# 7. handle_control is tried before the reply matchers on every cycle of
#    await_reply's own loop (not just when called standalone), so a user typing
#    /away while a listener happens to be running is armed rather than left
#    sitting unconsumed in the spool waiting for a reply that never comes.
away_disarm
printf '%s' '{"update_id":310,"message":{"chat":{"id":-100},"text":"/away 1h"}}' > "$SPOOL_DIR/310.json"
date +%s > "$start"
await_reply "$start" 42 -100 7 "$(( $(date +%s) + 2 ))" >/dev/null; rc=$?
check "await_reply drains a control command from its own loop" \
  "$(away_armed && echo yes || echo no)" "yes"
check "the drained control command is consumed, not treated as a reply" "$rc" "1"
away_disarm
rm -f "$SPOOL_DIR"/*.json

# --- await_tap ----------------------------------------------------------------
# await_tap is the synchronous counterpart to await_reply: it blocks inside a
# permission gate waiting for a button tap carrying its nonce. It gets none of
# the coverage above, so it is exercised the same way here: a successful claim,
# a timeout, and a promptly-aborting 409.

# 8. A tap carrying our nonce is claimed, the phone's spinner is cleared, and
#    the button index is printed.
printf '%s' '{"update_id":400,"callback_query":{"id":"cb1","data":"abc12345:1","from":{"id":111}}}' > "$SPOOL_DIR/400.json"
out="$(await_tap abc12345 -100 "$(( $(date +%s) + 10 ))")"; rc=$?
check "a claimed tap returns 0" "$rc" "0"
check "a claimed tap prints its button index" "$out" "1"

# 9. An elapsed window is a quiet exit, same as await_reply's.
out="$(await_tap abc12345 -100 "$(( $(date +%s) + 2 ))")"; rc=$?
check "an elapsed tap window returns 1" "$rc" "1"
check "an elapsed tap window prints nothing" "$out" ""

# 10. A 409 aborts await_tap promptly too.
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
printf '{"ok":false,"error_code":409,"description":"Conflict"}'
STUB
chmod +x "$STUB_DIR/curl"
start_s=$(date +%s)
await_tap abc12345 -100 "$(( start_s + 30 ))" >/dev/null; rc=$?
check "a 409 aborts await_tap" "$rc" "1"
check "a 409 aborts await_tap promptly rather than waiting out the window" \
  "$([ $(( $(date +%s) - start_s )) -lt 10 ] && echo yes || echo no)" "yes"
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
printf '{"ok":true,"result":[]}'
STUB
chmod +x "$STUB_DIR/curl"

# 11. Same fail-closed trap as check 6, but for the matcher await_tap relies on:
#     an unset MATCH_NONCE must never accidentally match a real tap.
unset MATCH_NONCE
printf '%s' '{"update_id":401,"callback_query":{"id":"cb2","data":"abc12345:0","from":{"id":111}}}' > "$SPOOL_DIR/401.json"
check "a claim with MATCH_NONCE unset fails closed rather than matching" \
  "$(updates_claim match_callback >/dev/null && echo yes || echo no)" "no"
rm -f "$SPOOL_DIR"/*.json

# 12. handle_control is tried before the tap matcher on every cycle of
#     await_tap's own loop too, same as check 7 for await_reply.
away_disarm
printf '%s' '{"update_id":410,"message":{"chat":{"id":-100},"text":"/away 1h"}}' > "$SPOOL_DIR/410.json"
await_tap abc12345 -100 "$(( $(date +%s) + 2 ))" >/dev/null; rc=$?
check "await_tap drains a control command from its own loop" \
  "$(away_armed && echo yes || echo no)" "yes"
check "the drained control command is consumed, not treated as a tap" "$rc" "1"
away_disarm
rm -f "$SPOOL_DIR"/*.json

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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
