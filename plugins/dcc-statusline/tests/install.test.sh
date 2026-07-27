#!/usr/bin/env bash
# Install writes the statusLine entry into an account's settings.json and nothing
# else. Account discovery must reject directories that have a settings.json but
# no account -- ~/.claude-mem is a real example on the author's machine: it is the
# claude-mem tool's database directory, not a Claude account.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

# Set the fake-home overrides before sourcing install.sh. The code must not
# depend on this order -- every path it derives from these is resolved at call
# time, not at source time -- but the test should not model the hazardous
# pattern (source first, override after) that exposed that bug in the first place.
fake="$(mktemp -d)"
export DCC_FAKE_HOME="$fake"
export DCC_STATUSLINE_HOME="$fake/.claude/dcc-statusline"

source "$HERE/../scripts/install.sh"

# Two real accounts, one lookalike tool directory, one directory with no settings.
mkdir -p "$fake/.claude" "$fake/.claude-alt" "$fake/.claude-mem" "$fake/.claude-empty"
printf '{"permissions":{"allow":[]}}\n' > "$fake/.claude/settings.json"
printf '{"permissions":{"allow":[]}}\n' > "$fake/.claude-alt/settings.json"
printf '{"observer":true}\n'            > "$fake/.claude-mem/settings.json"
printf '{"oauthAccount":{"emailAddress":"main@example.com"}}\n' > "$fake/.claude.json"
printf '{"oauthAccount":{"emailAddress":"alt@example.com"}}\n'  > "$fake/.claude-alt/.claude.json"

got="$(dcc_account_dirs | sed "s#^$fake/##" | sort | tr '\n' ' ')"
check "discovery finds both accounts and rejects the rest" "$got" ".claude .claude-alt "

# Regression guard for the source-time/call-time env resolution bug: every
# returned path must be inside the fake home, never the real one. (On some
# machines $fake itself sits under the real $HOME -- e.g. a Windows temp dir
# under the user profile -- so this must check "is under $fake", not merely
# "is not under $HOME".)
outside=0
while IFS= read -r d; do
  [ -z "$d" ] && continue
  case "$d" in
    "$fake"/*) ;;
    *) outside=1 ;;
  esac
done <<<"$(dcc_account_dirs)"
check "discovery never returns a path outside the fake home" "$outside" "0"

# --- install ------------------------------------------------------------------
dcc_install_one "$fake/.claude-alt"
check "install writes the command" \
  "$(jq -r '.statusLine.command' "$fake/.claude-alt/settings.json")" \
  "bash ~/.claude/dcc-statusline/statusline.sh"
check "install sets a refresh interval" \
  "$(jq -r '.statusLine.refreshInterval' "$fake/.claude-alt/settings.json")" "60"
check "install preserves existing keys" \
  "$(jq -r '.permissions.allow | length' "$fake/.claude-alt/settings.json")" "0"

# --- uninstall is a clean inverse --------------------------------------------
before="$(cat "$fake/.claude/settings.json")"
dcc_install_one "$fake/.claude"
dcc_uninstall_one "$fake/.claude"
after="$(jq -S . "$fake/.claude/settings.json")"
check "uninstall removes the entry" \
  "$(jq -r 'has("statusLine")' "$fake/.claude/settings.json")" "false"
check "install then uninstall restores the content" \
  "$after" "$(printf '%s' "$before" | jq -S .)"

# --- a missing settings.json is created ---------------------------------------
mkdir -p "$fake/.claude-new"
printf '{"oauthAccount":{"emailAddress":"new@example.com"}}\n' > "$fake/.claude-new/.claude.json"
dcc_install_one "$fake/.claude-new"
check "install creates a missing settings.json" \
  "$(jq -r '.statusLine.type' "$fake/.claude-new/settings.json")" "command"

# --- sync ---------------------------------------------------------------------
src="$(mktemp -d)"; mkdir -p "$src/scripts/lib"
printf '9.9.9\n' > "$src/scripts/VERSION"
printf 'echo new\n' > "$src/scripts/statusline.sh"

# Nothing installed yet: sync must stay out of the way entirely.
CLAUDE_PLUGIN_ROOT="$src" bash "$HERE/../scripts/sync.sh"
check "sync does nothing when not installed" "$([ -d "$DCC_STATUSLINE_HOME" ] && echo yes || echo no)" "no"

mkdir -p "$DCC_STATUSLINE_HOME"
printf '0.1.0\n' > "$DCC_STATUSLINE_HOME/VERSION"
printf 'echo old\n' > "$DCC_STATUSLINE_HOME/statusline.sh"
CLAUDE_PLUGIN_ROOT="$src" bash "$HERE/../scripts/sync.sh"
check "sync copies when the version differs" "$(cat "$DCC_STATUSLINE_HOME/VERSION")" "9.9.9"
check "sync replaces the scripts too" "$(cat "$DCC_STATUSLINE_HOME/statusline.sh")" "echo new"

printf 'echo touched\n' > "$DCC_STATUSLINE_HOME/statusline.sh"
CLAUDE_PLUGIN_ROOT="$src" bash "$HERE/../scripts/sync.sh"
check "sync is a no-op when versions match" "$(cat "$DCC_STATUSLINE_HOME/statusline.sh")" "echo touched"

rm -rf "$fake" "$src"
finish
