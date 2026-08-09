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

# A non-numeric prefix must not sail through to away_arm's arithmetic: under
# `set -u` a bad token there reads as an unset variable name and kills the
# hook outright. Each of these must print NOTHING, not just fail.
check "a non-numeric prefix before a suffix is refused" "$(parse_duration abc45s)" ""
check "a leading minus is refused" "$(parse_duration -5h)" ""
check "a double suffix is refused" "$(parse_duration 2h30m)" ""
check "a decimal is refused" "$(parse_duration 1.5h)" ""
check "a bare zero is refused" "$(parse_duration 0)" ""
check "a zero with a suffix is refused" "$(parse_duration 0h)" ""
check "a 21-digit number is refused" "$(parse_duration 100000000000000000000)" ""
# Well-formed but past TELEGRAM_AWAY_MAX (7 days): none of the earlier checks
# exercise this path, since they use either invalid syntax or values already
# under the cap.
check "a duration beyond the max is refused" "$(parse_duration 1000h)" ""
# Refused alone isn't enough: without the digit-count guard, `[ -gt 0 ]` on a
# value too wide for 64-bit arithmetic errors out and happens to still return
# non-zero, so the check above passes either way. Only the guard prevents the
# shell's own overflow error from leaking to stderr.
parse_stderr="$(parse_duration 100000000000000000000 2>&1 >/dev/null)"
check "a 21-digit number produces no stderr noise" "$parse_stderr" ""

# The CLI arms are what the slash command and the Telegram /away command call.
home="$(mktemp -d)"; env="$(mktemp -u)"
TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" bash "$SCRIPT" --away 1h >/dev/null
check "--away writes the flag" "$([ -f "$home/away" ] && echo yes || echo no)" "yes"
TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" bash "$SCRIPT" --back >/dev/null
check "--back removes the flag" "$([ -f "$home/away" ] && echo yes || echo no)" "no"

# A malformed duration reaches --away from a Telegram message a stranger could
# send, so it must never crash the hook or leak a raw shell error to stderr --
# it falls back to the default and says so.
home="$(mktemp -d)"; env="$(mktemp -u)"; errfile="$(mktemp -u)"
out=$(TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" bash "$SCRIPT" --away abc45s 2>"$errfile")
status=$?
check "--away abc45s exits 0" "$status" "0"
check "--away abc45s reports the bad duration" \
  "$(printf '%s' "$out" | head -n 1)" \
  "Not a duration: abc45s. Using the default. Try 90, 45s, 30m or 2h."
check "--away abc45s produces zero bytes on stderr" "$(wc -c < "$errfile" | tr -d ' ')" "0"
exp=$(cat "$home/away" 2>/dev/null); now=$(date +%s); diff=$(( exp - now ))
check "--away abc45s arms using the default TTL" \
  "$([ "$diff" -ge $((TELEGRAM_AWAY_TTL - 5)) ] && [ "$diff" -le $((TELEGRAM_AWAY_TTL + 15)) ] && echo yes || echo no)" \
  "yes"

home="$(mktemp -d)"; env="$(mktemp -u)"; errfile="$(mktemp -u)"
TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" bash "$SCRIPT" --away -5h >/dev/null 2>"$errfile" || true
check "--away -5h produces zero bytes on stderr" "$(wc -c < "$errfile" | tr -d ' ')" "0"
exp=$(cat "$home/away" 2>/dev/null); now=$(date +%s)
check "--away -5h arms a flag with a FUTURE expiry" \
  "$([ -n "$exp" ] && [ "$exp" -gt "$now" ] && echo yes || echo no)" "yes"

# away_arm is reachable from a Telegram message, so a bad argument must be
# REFUSED outright -- arming is a side effect, and only the caller (which has
# already chosen a fallback via parse_duration) gets to decide what to do
# about a bad value. Silently substituting the default here would arm a
# duration nobody asked for.
away_disarm
away_arm "junk"; status=$?
check "away_arm with a non-numeric argument returns 1" "$status" "1"
check "away_arm with a non-numeric argument writes no file" \
  "$([ -f "$AWAY_FILE" ] && echo yes || echo no)" "no"

# --- Leading-zero octal misparse (round 2 finding) --------------------------
# Bash arithmetic reads a leading-zero numeral as octal: "017" is 15 in
# decimal, and "008"/"009" contain digits invalid in octal and abort the shell
# outright ("value too great for base"). parse_duration must normalize via
# 10# before ANY arithmetic touches the value, and the exact numbers below are
# the point -- 017h must be 17 hours (61200s), never the octal-misread 15h.
check "008s normalizes to decimal 8" "$(parse_duration 008s)" "8"
check "017h normalizes to decimal 17 hours" "$(parse_duration 017h)" "61200"
check "009m normalizes to decimal 9 minutes" "$(parse_duration 009m)" "540"
check "07h normalizes to decimal 7 hours" "$(parse_duration 07h)" "25200"
check "an all-zero value is refused" "$(parse_duration 00)" ""
check "an all-zero value with a suffix is refused" "$(parse_duration 000h)" ""

# The subprocess path must show the same base-10 normalization: a wrong-but-
# silent value (17h misread as 15h) is worse than a crash, because it looks
# like it worked. Assert a delta RANGE, not an exact expiry, so a slow test
# runner cannot flake this.
home="$(mktemp -d)"; env="$(mktemp -u)"; errfile="$(mktemp -u)"
TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" bash "$SCRIPT" --away 017h >/dev/null 2>"$errfile"
check "--away 017h produces zero bytes on stderr" "$(wc -c < "$errfile" | tr -d ' ')" "0"
exp=$(cat "$home/away" 2>/dev/null); now=$(date +%s); diff=$(( exp - now ))
check "--away 017h arms 61200s ahead, not the octal-misread 54000s" \
  "$([ "$diff" -ge $((61200 - 5)) ] && [ "$diff" -le $((61200 + 15)) ] && echo yes || echo no)" \
  "yes"

home="$(mktemp -d)"; env="$(mktemp -u)"; errfile="$(mktemp -u)"
out=$(TELEGRAM_NOTIFY_HOME="$home" TELEGRAM_NOTIFY_ENV="$env" bash "$SCRIPT" --away 008s 2>"$errfile")
status=$?
check "--away 008s exits 0" "$status" "0"
check "--away 008s produces zero bytes on stderr" "$(wc -c < "$errfile" | tr -d ' ')" "0"
exp=$(cat "$home/away" 2>/dev/null); now=$(date +%s)
check "--away 008s arms a flag with a FUTURE expiry" \
  "$([ -n "$exp" ] && [ "$exp" -gt "$now" ] && echo yes || echo no)" "yes"

# away_arm called directly with a leading-zero value must also normalize:
# "008" is 8 seconds ahead, not a crash and not octal-truncated.
away_disarm
away_arm 008
exp=$(cat "$AWAY_FILE" 2>/dev/null); now=$(date +%s); diff=$(( exp - now ))
check "away_arm 008 arms 8 seconds ahead" \
  "$([ "$diff" -ge 3 ] && [ "$diff" -le 8 ] && echo yes || echo no)" "yes"
away_disarm

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
