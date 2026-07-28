#!/usr/bin/env bash
# SessionStart hook. Re-copies the script tree when the plugin version differs
# from the installed copy, because ${CLAUDE_PLUGIN_ROOT} moves on every update
# while the path in settings.json must not.
#
# It deliberately does nothing when the destination does not exist: a user who
# never ran the install command should not get files created behind their back.
set -uo pipefail

# Without CLAUDE_PLUGIN_ROOT the source path would read "/scripts", which is a
# real absolute path -- on the wrong machine it could exist and be copied from.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0

DCC_SRC="$CLAUDE_PLUGIN_ROOT/scripts"
DCC_DEST="${DCC_STATUSLINE_HOME:-${DCC_FAKE_HOME:-$HOME}/.claude/dcc-statusline}"

[ -d "$DCC_SRC" ]  || exit 0
[ -d "$DCC_DEST" ] || exit 0
cmp -s "$DCC_SRC/VERSION" "$DCC_DEST/VERSION" && exit 0
cp -R "$DCC_SRC/." "$DCC_DEST/" 2>/dev/null
# Font capability can change between updates -- a new machine, a new terminal
# profile -- so it is re-probed whenever the scripts are refreshed.
bash "$DCC_DEST/detect-font.sh" "$DCC_DEST/icons.detected" >/dev/null 2>&1 || true
exit 0
