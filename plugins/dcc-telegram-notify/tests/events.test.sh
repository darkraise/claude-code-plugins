#!/usr/bin/env bash
# Tests for the TELEGRAM_EVENTS parser, which decides what is allowed to send.
# A typo must never be fatal: unknown tokens are dropped and reported, never
# propagated as an error that could take a user's notifications down.
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

# resolve <value>  -- pass the literal string UNSET to remove the variable
resolve() {
  if [ "$1" = "UNSET" ]; then unset TELEGRAM_EVENTS; else TELEGRAM_EVENTS="$1"; fi
  parse_events
  events_list
}

check "unset yields the blocked-on-you default" \
  "$(resolve UNSET)" "input permission stop-question"
check "empty means no events, like none" \
  "$(resolve "")" ""
check "none disables everything" \
  "$(resolve "none")" ""
check "none wins wherever it appears in the list" \
  "$(resolve "all,none")" ""
check "a single token enables only itself" \
  "$(resolve "permission")" "permission"
check "stop expands to the three turn-end tokens" \
  "$(resolve "stop")" "stop-done stop-question stop-reply"
check "all enables every token" \
  "$(resolve "all")" "input permission stop-done stop-question stop-reply"
check "commas, spaces and case are all tolerated" \
  "$(resolve "Permission,  STOP-DONE  input")" "input permission stop-done"
check "duplicates collapse" \
  "$(resolve "permission,permission,all")" "input permission stop-done stop-question stop-reply"

# Unknown tokens are dropped, recorded for status output, and leave valid
# neighbors alone.
out=$(resolve "permission,bogus,input")
check "unknown tokens do not disturb valid ones" "$out" "input permission"
check "unknown tokens are recorded" "$TELEGRAM_EVENTS_UNKNOWN" "bogus"
out=$(resolve "permission")
check "the unknown list resets between parses" "$TELEGRAM_EVENTS_UNKNOWN" ""

# event_enabled is the membership test the hook branches actually call.
resolve "permission,stop-question" >/dev/null
check "event_enabled true for a member" \
  "$(event_enabled permission && echo yes || echo no)" "yes"
check "event_enabled false for a non-member" \
  "$(event_enabled stop-done && echo yes || echo no)" "no"
resolve "none" >/dev/null
check "event_enabled false for everything under none" \
  "$(event_enabled permission && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
