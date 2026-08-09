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
# The disarmed verdict alone isn't enough: without the ^[0-9]+$ guard, bash's
# own "[ -lt ]" happens to reject "garbage" too, so the yes/no check above
# passes either way. What only the guard prevents is that non-numeric compare
# erroring onto stderr -- a notification path must swallow its own failures,
# never spray shell errors.
printf 'garbage' > "$AWAY_FILE"
away_stderr="$(away_armed 2>&1 >/dev/null)"
check "a corrupt away file produces no stderr noise" "$away_stderr" ""
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
