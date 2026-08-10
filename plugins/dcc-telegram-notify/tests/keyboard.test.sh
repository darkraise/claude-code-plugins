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

# Regression: record_last must resolve the SAME effective topic send() posts
# to. In shared mode with a configured TELEGRAM_TOPIC_ID, SEND_TOPIC is never
# set (no per-project routing runs), so a call site that read "${SEND_TOPIC:-}"
# directly instead of going through effective_topic() would record the marker
# under "main" while the message actually landed in topic 99 -- silently
# breaking every bare (non-long-pressed) reply typed there. Run in a fresh
# subprocess so the TELEGRAM_TOPIC_ID/TELEGRAM_TOPIC_MODE env is picked up at
# source time, the same way the real hook process starts up.
topic_home="$(mktemp -d)"
result="$(TELEGRAM_NOTIFY_HOME="$topic_home" TELEGRAM_NOTIFY_ENV="$(mktemp -u)" \
  TELEGRAM_CHAT_ID=-100 TELEGRAM_TOPIC_MODE=shared TELEGRAM_TOPIC_ID=99 bash -c '
    # shellcheck disable=SC1090
    source "'"$SCRIPT"'"
    record_last 555
    [ -f "$(last_marker_path -100 99)" ] && echo yes || echo no
  ')"
check "record_last falls back to TELEGRAM_TOPIC_ID, not main, when SEND_TOPIC is unset" \
  "$result" "yes"
check "record_last does NOT write the marker under main in that case" \
  "$([ -f "$topic_home/last/-100.main" ] && echo yes || echo no)" "no"

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

# answer_callback and edit_message are listed interfaces the brief did not
# exercise; covered here so a perturbation of either is actually caught.
answer_callback "cb123" "Approved"
check "answer_callback posts to answerCallbackQuery" \
  "$(grep -c 'answerCallbackQuery' "$CURL_STUB_ARGS" || true)" "1"
check "answer_callback includes the callback id" \
  "$(grep -c 'callback_query_id=cb123' "$CURL_STUB_ARGS" || true)" "1"

edit_message 55 "<b>done</b>"
check "edit_message posts to editMessageText" \
  "$(grep -c 'editMessageText' "$CURL_STUB_ARGS" || true)" "1"
check "edit_message includes the message id" \
  "$(grep -c 'message_id=55' "$CURL_STUB_ARGS" || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
