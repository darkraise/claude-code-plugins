#!/usr/bin/env bash
# Tests for migrate_home(): the plugin rename moved the config home from
# ~/.telegram-notify to ~/.dcc-telegram-notify. An existing install must carry
# over untouched, and an explicit TELEGRAM_NOTIFY_HOME must never be overridden.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/dcc-telegram-notify.sh"

export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"   # keep load-time migration off the real home
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"
# shellcheck disable=SC1090
source "$SCRIPT"

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# Build a fake home dir and run migrate_home() against it. $1 = "explicit" to
# simulate a user-set TELEGRAM_NOTIFY_HOME, anything else for the default path.
setup_case() {
  CASE="$(mktemp -d)"
  TELEGRAM_NOTIFY_HOME="$CASE/.dcc-telegram-notify"
  TELEGRAM_NOTIFY_HOME_WAS_SET=""
  [ "${1:-}" = "explicit" ] && TELEGRAM_NOTIFY_HOME_WAS_SET="1"
}

# 1. Old home present, new absent -> migrated, contents preserved.
setup_case
mkdir -p "$CASE/.telegram-notify/state"
echo "TELEGRAM_BOT_TOKEN=secret" > "$CASE/.telegram-notify/telegram.env"
migrate_home
check "old home is moved to the new location" \
  "$([ -d "$CASE/.dcc-telegram-notify" ] && echo yes || echo no)" "yes"
check "old home no longer exists" \
  "$([ -d "$CASE/.telegram-notify" ] && echo yes || echo no)" "no"
check "config contents survive the move" \
  "$(cat "$CASE/.dcc-telegram-notify/telegram.env" 2>/dev/null)" "TELEGRAM_BOT_TOKEN=secret"
check "state subdirectory survives the move" \
  "$([ -d "$CASE/.dcc-telegram-notify/state" ] && echo yes || echo no)" "yes"

# 2. Both present -> the new home wins and is left completely alone.
setup_case
mkdir -p "$CASE/.telegram-notify" "$CASE/.dcc-telegram-notify"
echo "old" > "$CASE/.telegram-notify/telegram.env"
echo "new" > "$CASE/.dcc-telegram-notify/telegram.env"
migrate_home
check "existing new home is not overwritten" \
  "$(cat "$CASE/.dcc-telegram-notify/telegram.env")" "new"
check "old home is left in place when both exist" \
  "$([ -d "$CASE/.telegram-notify" ] && echo yes || echo no)" "yes"

# 3. Neither present -> no-op, and no directory is conjured.
setup_case
migrate_home
check "nothing is created when there is nothing to migrate" \
  "$([ -e "$CASE/.dcc-telegram-notify" ] && echo yes || echo no)" "no"

# 4. Explicit TELEGRAM_NOTIFY_HOME -> the user's choice is never second-guessed.
setup_case explicit
mkdir -p "$CASE/.telegram-notify"
echo "old" > "$CASE/.telegram-notify/telegram.env"
migrate_home
check "explicit home suppresses migration" \
  "$([ -d "$CASE/.telegram-notify" ] && echo yes || echo no)" "yes"
check "explicit home is not created by migration" \
  "$([ -e "$CASE/.dcc-telegram-notify" ] && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
