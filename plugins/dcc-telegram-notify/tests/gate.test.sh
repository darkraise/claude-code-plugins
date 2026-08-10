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

# A fake bot token makes real curl fail fast, so the timing check above passes
# whether or not the away_armed guard is even there -- both look instant. Only
# counting actual curl invocations proves the guard, not just its timing,
# blocks the branch before it can touch the network.
CURL_LOG="$(mktemp -u)"
CURL_STUB_DIR="$(mktemp -d)"
cat > "$CURL_STUB_DIR/curl" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$CURL_LOG"
echo '{"ok":true}'
STUB
chmod +x "$CURL_STUB_DIR/curl"
rm -f "$CURL_LOG"
PATH="$CURL_STUB_DIR:$PATH" run_hook "$PR" >/dev/null
check "a disarmed gate makes zero curl calls" \
  "$([ -s "$CURL_LOG" ] && echo "called" || echo "none")" "none"

# Armed but with the read side unusable (no allowed users): reply_enabled must
# stop the branch before it ever reaches Telegram, same as the disarmed path.
# Nothing above exercises this combination, so a dropped reply_enabled guard
# would otherwise ship silently.
#
# Only the curl-call count is asserted here, not "returns no decision": with
# the generic stub above, a missing guard still falls through to send_message,
# gets no message_id back from the stub's generic {"ok":true} response, and
# exits before ever reaching gate_decision -- so stdout is empty whether or
# not the guard exists. An assertion that cannot fail is worse than no
# assertion, since it reads as coverage it isn't providing.
ARMED_HOME="$(mktemp -d)"
printf '%s' "$(( $(date +%s) + 3600 ))" > "$ARMED_HOME/away"
rm -f "$CURL_LOG"
printf '%s' "$PR" | PATH="$CURL_STUB_DIR:$PATH" TELEGRAM_NOTIFY_HOME="$ARMED_HOME" \
  TELEGRAM_NOTIFY_ENV="$(mktemp -u)" TELEGRAM_BOT_TOKEN=t TELEGRAM_CHAT_ID=-100 \
  TELEGRAM_ALLOWED_USERS= bash "$SCRIPT" >/dev/null
check "an armed gate with reply disabled makes zero curl calls" \
  "$([ -s "$CURL_LOG" ] && echo "called" || echo "none")" "none"

# --- Armed round trips: a real tap, and a timeout with no tap ---------------
# Everything above only ever reaches the guards, never the tap itself. A stub
# curl plays Telegram: it captures the nonce embedded in the Allow button's
# callback_data from the sendMessage call, then (when TAP_INDEX is set) hands
# it back on the next getUpdates poll as a callback_query, exactly as a real
# button tap would. TAP_INDEX unset means "nobody ever taps" -- the timeout path.
TAP_STUB_DIR="$(mktemp -d)"
cat > "$TAP_STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *getUpdates*)
    nonce=$(cat "$TAP_NONCE_FILE" 2>/dev/null)
    if [ -n "$nonce" ] && [ -n "${TAP_INDEX:-}" ] && [ ! -f "$TAP_TAPPED_FILE" ]; then
      touch "$TAP_TAPPED_FILE"
      printf '{"ok":true,"result":[{"update_id":900,"callback_query":{"id":"cbX","from":{"id":111},"data":"%s:%s","message":{"chat":{"id":-100}}}}]}' \
        "$nonce" "$TAP_INDEX"
    else
      echo '{"ok":true,"result":[]}'
    fi
    ;;
  *sendMessage*)
    nonce=$(printf '%s' "$args" | grep -oE '[a-z0-9]{8}:0' | head -1 | cut -d: -f1)
    [ -n "$nonce" ] && printf '%s' "$nonce" > "$TAP_NONCE_FILE"
    echo '{"ok":true,"result":{"message_id":950}}'
    ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$TAP_STUB_DIR/curl"

TAP_HOME="$(mktemp -d)"
printf '%s' "$(( $(date +%s) + 3600 ))" > "$TAP_HOME/away"
export TAP_NONCE_FILE="$(mktemp -u)" TAP_TAPPED_FILE="$(mktemp -u)"

export TAP_INDEX=0
out="$(printf '%s' "$PR" | PATH="$TAP_STUB_DIR:$PATH" TELEGRAM_NOTIFY_HOME="$TAP_HOME" \
  TELEGRAM_NOTIFY_ENV="$(mktemp -u)" TELEGRAM_BOT_TOKEN=t TELEGRAM_CHAT_ID=-100 \
  TELEGRAM_ALLOWED_USERS=111 TELEGRAM_REPLY_POLL=1 bash "$SCRIPT")"
check "a tapped Allow reaches real stdout as an allow decision" \
  "$(jq -r '.hookSpecificOutput.decision.behavior' <<<"$out" 2>/dev/null)" "allow"
check "a tapped Allow leaves no pending nonce behind" \
  "$(find "$TAP_HOME/pending" -type f 2>/dev/null | wc -l | tr -d ' ')" "0"

# The security-relevant case: Deny must reach stdout as "deny", not "allow".
# This has to go through the same case dispatch in main() that Allow does --
# asserting on gate_decision directly (as the two checks near the bottom of
# this file do) would never notice button index 1 wired to the wrong behavior.
rm -f "$TAP_TAPPED_FILE"
DENY_HOME="$(mktemp -d)"
printf '%s' "$(( $(date +%s) + 3600 ))" > "$DENY_HOME/away"
export TAP_INDEX=1
out="$(printf '%s' "$PR" | PATH="$TAP_STUB_DIR:$PATH" TELEGRAM_NOTIFY_HOME="$DENY_HOME" \
  TELEGRAM_NOTIFY_ENV="$(mktemp -u)" TELEGRAM_BOT_TOKEN=t TELEGRAM_CHAT_ID=-100 \
  TELEGRAM_ALLOWED_USERS=111 TELEGRAM_REPLY_POLL=1 bash "$SCRIPT")"
check "a tapped Deny reaches real stdout as a deny decision" \
  "$(jq -r '.hookSpecificOutput.decision.behavior' <<<"$out" 2>/dev/null)" "deny"
check "a tapped Deny leaves no pending nonce behind" \
  "$(find "$DENY_HOME/pending" -type f 2>/dev/null | wc -l | tr -d ' ')" "0"

# "I'm back" must return no decision at all (the keyboard picker still handles
# it) and must disarm away mode, so the very next permission request goes
# straight to the keyboard instead of back out to Telegram.
rm -f "$TAP_TAPPED_FILE"
BACK_HOME="$(mktemp -d)"
printf '%s' "$(( $(date +%s) + 3600 ))" > "$BACK_HOME/away"
export TAP_INDEX=back
out="$(printf '%s' "$PR" | PATH="$TAP_STUB_DIR:$PATH" TELEGRAM_NOTIFY_HOME="$BACK_HOME" \
  TELEGRAM_NOTIFY_ENV="$(mktemp -u)" TELEGRAM_BOT_TOKEN=t TELEGRAM_CHAT_ID=-100 \
  TELEGRAM_ALLOWED_USERS=111 TELEGRAM_REPLY_POLL=1 bash "$SCRIPT")"
check "a tapped I'm-back returns no decision" "$out" ""
check "a tapped I'm-back disarms away mode" \
  "$([ -f "$BACK_HOME/away" ] && echo armed || echo disarmed)" "disarmed"

rm -f "$TAP_TAPPED_FILE"
unset TAP_INDEX
out="$(printf '%s' "$PR" | PATH="$TAP_STUB_DIR:$PATH" TELEGRAM_NOTIFY_HOME="$TAP_HOME" \
  TELEGRAM_NOTIFY_ENV="$(mktemp -u)" TELEGRAM_BOT_TOKEN=t TELEGRAM_CHAT_ID=-100 \
  TELEGRAM_ALLOWED_USERS=111 TELEGRAM_REPLY_POLL=1 TELEGRAM_REPLY_WINDOW_AWAY=2 bash "$SCRIPT")"
check "a timed-out gate returns no decision" "$out" ""
check "a timed-out gate leaves no pending nonce behind" \
  "$(find "$TAP_HOME/pending" -type f 2>/dev/null | wc -l | tr -d ' ')" "0"

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
