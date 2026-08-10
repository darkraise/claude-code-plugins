#!/usr/bin/env bash
# Tests for the TELEGRAM_EVENTS parser, which decides what is allowed to send.
# A typo must never be fatal: unknown tokens are dropped and reported, never
# propagated as an error that could take a user's notifications down.
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
# shellcheck disable=SC1090
source "$SCRIPT"

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# resolve <value>  -- pass the literal string UNSET to remove the variable
# Sets TELEGRAM_EVENTS then parses, in THIS shell -- $( ) would fork a subshell
# and the globals parse_events sets would die with it.
RESOLVED=""
resolve() {
  if [ "$1" = "UNSET" ]; then unset TELEGRAM_EVENTS; else TELEGRAM_EVENTS="$1"; fi
  parse_events
  RESOLVED="$(events_list)"
}

resolve UNSET
check "unset yields the blocked-on-you default" "$RESOLVED" "input permission stop-question"
resolve ""
check "empty means no events, like none" "$RESOLVED" ""
resolve "none"
check "none disables everything" "$RESOLVED" ""
resolve "all,none"
check "none wins wherever it appears in the list" "$RESOLVED" ""
resolve "permission"
check "a single token enables only itself" "$RESOLVED" "permission"
resolve "stop"
check "stop expands to the three turn-end tokens" "$RESOLVED" "stop-done stop-question stop-reply"
resolve "all"
check "all enables every token" "$RESOLVED" "input permission stop-done stop-question stop-reply"
resolve "Permission,  STOP-DONE  input"
check "commas, spaces and case are all tolerated" "$RESOLVED" "input permission stop-done"
resolve "permission,permission,all"
check "duplicates collapse" "$RESOLVED" "input permission stop-done stop-question stop-reply"

# Unknown tokens are dropped, recorded for status output, and leave valid
# neighbors alone.
resolve "permission,bogus,input"
check "unknown tokens do not disturb valid ones" "$RESOLVED" "input permission"
check "unknown tokens are recorded" "$TELEGRAM_EVENTS_UNKNOWN" "bogus"
resolve "permission"
check "the unknown list resets between parses" "$TELEGRAM_EVENTS_UNKNOWN" ""

# event_enabled is the membership test the hook branches actually call.
# It only reads TELEGRAM_EVENTS_RESOLVED, so calling it inside $( ) is fine.
resolve "permission,stop-question"
check "event_enabled true for a member" \
  "$(event_enabled permission && echo yes || echo no)" "yes"
check "event_enabled false for a non-member" \
  "$(event_enabled stop-done && echo yes || echo no)" "no"
resolve "none"
check "event_enabled false for everything under none" \
  "$(event_enabled permission && echo yes || echo no)" "no"

# --- --events CLI dispatch -----------------------------------------------
# Exercises the actual subprocess arm, not the sourced parser: the exit-code
# bug this covers only showed up through the dispatch arm's own exit status,
# which the checks above (calling functions in-process) can never observe.
# Each run gets its own home/env so it cannot touch the real config.
run_events() {
  local home env
  home="$(mktemp -d)"
  env="$(mktemp -u)"
  if [ "$1" = "UNSET" ]; then
    TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" \
      env -u TELEGRAM_EVENTS bash "$SCRIPT" --events
  else
    TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" \
      TELEGRAM_EVENTS="$1" bash "$SCRIPT" --events
  fi
}

out="$(run_events UNSET)"; status=$?
check "--events exits 0 on a clean default config" "$status" "0"
check "--events prints the default enabled set" "$out" \
  "enabled: input permission stop-question"

out="$(run_events "all,bogus")"; status=$?
check "--events exits 0 even with unknown tokens" "$status" "0"
check "--events prints the full set and the ignored-tokens line" "$out" \
"enabled: input permission stop-done stop-question stop-reply
ignored (not valid tokens): bogus"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
