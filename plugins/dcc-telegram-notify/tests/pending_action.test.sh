#!/usr/bin/env bash
# Tests for pending_action(): it must describe the tool the user is ACTUALLY
# being asked to approve/answer, never a stale, already-resolved tool_use left in
# the transcript by an earlier step.
#
# Regression: a permission notification once showed an old "git add && git commit"
# Bash command while the screen was actually on an AskUserQuestion, because the
# AskUserQuestion tool_use had not yet flushed to the transcript and the function
# returned the most recent *already-resolved* tool instead.
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
FIXTURES="$HERE/fixtures"

# Never touch the real config home: Task 2 adds a load-time migration that would
# otherwise move this machine's actual ~/.dcc-telegram-notify during a test run.
export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"
# Isolate from the real config/token, and keep the flush-wait poll short.
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"
export TELEGRAM_PENDING_TRIES=2
# shellcheck disable=SC1090
source "$SCRIPT"

pass=0 fail=0
field() { # field <json-or-empty> <jq-expr>
  local o="$1"
  [ -n "$o" ] || { printf 'EMPTY'; return; }
  jq -r "$2" <<<"$o" 2>/dev/null || printf 'EMPTY'
}
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# 1. Only a resolved Bash (+ trailing text) exists → nothing is pending.
out=$(pending_action "$FIXTURES/stale_resolved_bash.jsonl")
check "resolved-only transcript yields NO pending action" \
  "$(field "$out" '.tool // "EMPTY"')" "EMPTY"

# 2. A resolved Bash precedes an unresolved AskUserQuestion → report the question.
out=$(pending_action "$FIXTURES/pending_askquestion.jsonl")
check "unresolved AskUserQuestion wins over the older resolved Bash (tool)" \
  "$(field "$out" '.tool // "EMPTY"')" "AskUserQuestion"
check "unresolved AskUserQuestion reports its question text" \
  "$(field "$out" '.question // "EMPTY"')" "Which execution approach do you want?"

# 3. A single unresolved Bash → normal permission prompt still works.
out=$(pending_action "$FIXTURES/pending_bash.jsonl")
check "unresolved Bash is reported as pending (tool)" \
  "$(field "$out" '.tool // "EMPTY"')" "Bash"
check "unresolved Bash reports its command target" \
  "$(field "$out" '.target // "EMPTY"')" "rm -rf /tmp/scratch"

# 4. A user message whose content is a bare string (e.g. slash-command output)
#    must not break the resolved-id scan; the unresolved AskUserQuestion still wins.
out=$(pending_action "$FIXTURES/pending_with_string_user_content.jsonl")
check "string-content user message does not break iteration (tool)" \
  "$(field "$out" '.tool // "EMPTY"')" "AskUserQuestion"

# 5. TELEGRAM_PENDING_TRIES sanitization (Task 5 additional work). tries feeds
# `for ((i = 0; i < tries; i++))`, a fatal arithmetic context under `set -u`:
# a bad value must fall back rather than kill the hook. Exercised against a
# fixture with nothing pending, so the loop runs to completion either way.
errfile=$(mktemp -u)
out=$(TELEGRAM_PENDING_TRIES=banana pending_action "$FIXTURES/stale_resolved_bash.jsonl" 2>"$errfile")
check "TELEGRAM_PENDING_TRIES=banana still yields no pending action (falls back, no crash)" \
  "$(field "$out" '.tool // "EMPTY"')" "EMPTY"
check "TELEGRAM_PENDING_TRIES=banana produces zero bytes on stderr" \
  "$(wc -c < "$errfile" | tr -d ' ')" "0"

errfile=$(mktemp -u)
out=$(TELEGRAM_PENDING_TRIES=003 pending_action "$FIXTURES/stale_resolved_bash.jsonl" 2>"$errfile")
check "TELEGRAM_PENDING_TRIES=003 still yields no pending action (normalizes, no crash)" \
  "$(field "$out" '.tool // "EMPTY"')" "EMPTY"
check "TELEGRAM_PENDING_TRIES=003 produces zero bytes on stderr" \
  "$(wc -c < "$errfile" | tr -d ' ')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
