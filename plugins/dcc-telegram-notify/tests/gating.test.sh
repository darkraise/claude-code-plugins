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
