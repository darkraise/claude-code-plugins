#!/usr/bin/env bash
# SessionStart hook. Re-copies the script tree when the plugin version differs
# from the installed copy, because ${CLAUDE_PLUGIN_ROOT} moves on every update
# while the path in settings.json must not.
#
# It deliberately does nothing when the destination does not exist: a user who
# never ran the install command should not get files created behind their back.
set -uo pipefail

SRC="${CLAUDE_PLUGIN_ROOT:-}/scripts"
DEST="${DCC_STATUSLINE_HOME:-${DCC_FAKE_HOME:-$HOME}/.claude/dcc-statusline}"

[ -d "$SRC" ]  || exit 0
[ -d "$DEST" ] || exit 0
cmp -s "$SRC/VERSION" "$DEST/VERSION" && exit 0
cp -R "$SRC/." "$DEST/" 2>/dev/null
exit 0
