#!/usr/bin/env bash
# End-to-end proof that a Telegram reply actually rewakes a finished turn, and
# that the away-mode invariant around it holds. Nothing else in the suite
# drives the full Stop -> send -> await_reply -> rewake chain as one real
# subprocess, so gutting the delivery block to a bare `exit 0` (start-file
# rewrite, .remote marker, reply on fd 7, exit 2) previously left every other
# check green.
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

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# --- Stop -> rewake, driven as a real subprocess ----------------------------
# A stub curl plays Telegram: sendMessage hands back a message id, and every
# getUpdates answers with a reply addressed to that same id, exactly as a
# phone reply typed under the notification would arrive.
STUB_DIR="$(mktemp -d)"
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
args="$*"
if [[ "$args" == *getUpdates* ]]; then
  cat <<'J'
{"ok":true,"result":[{"update_id":9001,"message":{"message_id":77,"chat":{"id":-100},"text":"do the next thing","from":{"id":111},"reply_to_message":{"message_id":555}}}]}
J
elif [[ "$args" == *sendMessage* ]]; then
  cat >/dev/null
  printf '{"ok":true,"result":{"message_id":555}}'
else
  cat >/dev/null
  printf '{"ok":true,"result":{}}'
fi
STUB
chmod +x "$STUB_DIR/curl"

HOME_DIR="$(mktemp -d)"
payload='{"hook_event_name":"Stop","session_id":"e2e","cwd":".","transcript_path":"/nonexistent","last_assistant_message":"I finished the refactor."}'

errfile="$(mktemp -u)"
out=$(printf '%s' "$payload" | PATH="$STUB_DIR:$PATH" \
  TELEGRAM_NOTIFY_HOME="$HOME_DIR" TELEGRAM_NOTIFY_ENV="$(mktemp -u)" \
  TELEGRAM_BOT_TOKEN=tok TELEGRAM_CHAT_ID=-100 \
  TELEGRAM_ALLOWED_USERS=111 TELEGRAM_REPLY=on \
  TELEGRAM_EVENTS=all TELEGRAM_REPLY_POLL=1 TELEGRAM_REPLY_WINDOW=25 \
  bash "$SCRIPT" 2>"$errfile")
rc=$?

check "a Telegram reply rewakes the turn with exit code 2" "$rc" "2"
check "the reply text reaches real stderr" \
  "$(grep -qF 'do the next thing' "$errfile" && echo yes || echo no)" "yes"
check "stdout stays empty (a rewake is not a hook decision)" "$out" ""
check "a .remote marker is written for the rewoken session" \
  "$([ -f "$HOME_DIR/state/e2e.remote" ] && echo yes || echo no)" "yes"
check "the turn-start file is rewritten for the new turn" \
  "$([ -f "$HOME_DIR/state/e2e.start" ] && echo yes || echo no)" "yes"

# --- UserPromptSubmit: the other half of the away-mode invariant -----------
# Nothing else drives the engine with this hook event at all. A rewoken turn
# fires its own UserPromptSubmit once Claude acts on the reply, and that must
# NOT read as "the user came back to the keyboard" -- only an ordinary local
# prompt, with no fresh .remote marker, may disarm away mode.
run_hook() { # run_hook <home> <payload>
  printf '%s' "$2" | TELEGRAM_NOTIFY_HOME="$1" TELEGRAM_NOTIFY_ENV="$(mktemp -u)" \
    TELEGRAM_BOT_TOKEN=t TELEGRAM_CHAT_ID=-100 TELEGRAM_ALLOWED_USERS=111 \
    bash "$SCRIPT" >/dev/null 2>&1
}

# A fresh .remote marker present: away mode SURVIVES the rewoken turn's own
# prompt, and the marker is consumed so it cannot eat the NEXT genuine local
# prompt's disarm.
UPS_HOME="$(mktemp -d)"
mkdir -p "$UPS_HOME/state"
printf '%s' "$(( $(date +%s) + 3600 ))" > "$UPS_HOME/away"
touch "$UPS_HOME/state/ups1.remote"
run_hook "$UPS_HOME" '{"hook_event_name":"UserPromptSubmit","session_id":"ups1","cwd":"."}'
check "a rewoken turn's own prompt leaves away mode armed" \
  "$([ -f "$UPS_HOME/away" ] && echo armed || echo disarmed)" "armed"
check "the remote marker is consumed" \
  "$([ -f "$UPS_HOME/state/ups1.remote" ] && echo yes || echo no)" "no"

# No marker: an ordinary local prompt disarms away mode as usual.
UPS_HOME2="$(mktemp -d)"
mkdir -p "$UPS_HOME2/state"
printf '%s' "$(( $(date +%s) + 3600 ))" > "$UPS_HOME2/away"
run_hook "$UPS_HOME2" '{"hook_event_name":"UserPromptSubmit","session_id":"ups2","cwd":"."}'
check "an ordinary local prompt disarms away mode" \
  "$([ -f "$UPS_HOME2/away" ] && echo armed || echo disarmed)" "disarmed"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
