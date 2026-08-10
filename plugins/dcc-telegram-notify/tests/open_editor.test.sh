#!/usr/bin/env bash
# Tests for open_editor(): on a headless / non-interactive host (no GUI opener, no
# controlling TTY, and no $VISUAL/$EDITOR) it must NOT launch a blocking terminal
# editor (nano/vi) -- those need a terminal and would hang when `--edit` is run
# without a TTY (e.g. from the slash command). Instead it prints the config path
# and returns non-zero. An explicitly set $EDITOR is always honored.
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

# Never touch the real config home: Task 2 adds a load-time migration that would
# otherwise move this machine's actual ~/.dcc-telegram-notify during a test run.
export TELEGRAM_NOTIFY_HOME="$(mktemp -d)"
export TELEGRAM_NOTIFY_ENV="$(mktemp -u)"   # isolate from the real config/token
# shellcheck disable=SC1090
source "$SCRIPT"

TMP="$(mktemp -d)"
CFG="$TMP/telegram.env"; : > "$CFG"

pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi; }

# Force the Linux/other branch regardless of the host OS.
uname() { echo Linux; }

# 1. Headless: no display, no editor env, non-interactive stdin/stdout, and both
#    nano and vi "available" as stubs -- neither may be launched.
NANO_MARK="$TMP/nano.called"; VI_MARK="$TMP/vi.called"
nano() { echo called > "$NANO_MARK"; }
vi()   { echo called > "$VI_MARK"; }
unset VISUAL EDITOR DISPLAY WAYLAND_DISPLAY 2>/dev/null || true

out=$(open_editor "$CFG" </dev/null); rc=$?
check "headless: returns non-zero (launched no editor)" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
check "headless: did NOT run nano" "$([ -e "$NANO_MARK" ] && echo ran || echo skipped)" "skipped"
check "headless: did NOT run vi"   "$([ -e "$VI_MARK" ] && echo ran || echo skipped)" "skipped"
check "headless: printed the config path" "$(printf '%s' "$out" | grep -qF "$CFG" && echo yes || echo no)" "yes"

# 2. An explicit $EDITOR is honored (even non-interactively).
ED_MARK="$TMP/editor.arg"
cat > "$TMP/fake-editor.sh" <<EOF
#!/usr/bin/env bash
printf '%s' "\$1" > "$ED_MARK"
EOF
chmod +x "$TMP/fake-editor.sh"
export EDITOR="$TMP/fake-editor.sh"
open_editor "$CFG" </dev/null; rc=$?
check "explicit \$EDITOR is invoked with the file" "$(cat "$ED_MARK" 2>/dev/null)" "$CFG"
check "explicit \$EDITOR path returns success" "$rc" "0"
unset EDITOR

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
