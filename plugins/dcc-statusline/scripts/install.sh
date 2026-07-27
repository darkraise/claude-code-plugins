#!/usr/bin/env bash
# Installs the statusLine entry into a Claude account's settings.json. A plugin
# cannot register a statusLine itself -- plugin settings.json supports only the
# agent and subagentStatusLine keys -- so the entry has to live in user settings.
#
# The command written points at a stable copy outside the versioned plugin cache,
# because ${CLAUDE_PLUGIN_ROOT} changes on every plugin update.
set -uo pipefail

DCC_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DCC_COMMAND="bash ~/.claude/dcc-statusline/statusline.sh"

_dcc_paths() { # -> DCC_HOME_DIR, DCC_DEST -- resolved fresh on every call, never
               # cached at source time, because a caller (tests, in particular)
               # may set DCC_FAKE_HOME / DCC_STATUSLINE_HOME after sourcing this
               # file rather than before it
  DCC_HOME_DIR="${DCC_FAKE_HOME:-$HOME}"
  DCC_DEST="${DCC_STATUSLINE_HOME:-$DCC_HOME_DIR/.claude/dcc-statusline}"
}

dcc_account_dirs() { # prints each qualifying account config dir, one per line
  _dcc_paths
  local d j
  for d in "$DCC_HOME_DIR"/.claude "$DCC_HOME_DIR"/.claude-*; do
    [ -d "$d" ] || continue
    [ -f "$d/settings.json" ] || continue
    if [ "$d" = "$DCC_HOME_DIR/.claude" ]; then j="$DCC_HOME_DIR/.claude.json"; else j="$d/.claude.json"; fi
    [ -f "$j" ] || continue
    jq -e '.oauthAccount.emailAddress // empty' "$j" >/dev/null 2>&1 || continue
    printf '%s\n' "$d"
  done
}

dcc_copy_scripts() {
  _dcc_paths
  mkdir -p "$DCC_DEST" || return 1
  cp -R "$DCC_SRC_DIR/." "$DCC_DEST/" 2>/dev/null || return 1
  # install.sh and sync.sh are plugin-side entry points; the copy only needs the
  # render path, but copying everything keeps VERSION comparison trivial.
  return 0
}

_dcc_edit_settings() { # _dcc_edit_settings <dir> <jq-program>
  local dir="$1" prog="$2" tmp
  local settings="$dir/settings.json"
  [ -f "$settings" ] || printf '{}\n' > "$settings"
  tmp="$settings.dcc-tmp.$$"
  if jq --indent 2 "$prog" "$settings" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$settings"
  else
    rm -f "$tmp"
    return 1
  fi
}

dcc_install_one() { # dcc_install_one <config-dir>
  _dcc_edit_settings "$1" \
    '.statusLine = {type:"command",command:"'"$DCC_COMMAND"'",padding:0,refreshInterval:60}'
}

dcc_uninstall_one() { # dcc_uninstall_one <config-dir>
  _dcc_edit_settings "$1" 'del(.statusLine)'
}

dcc_seed_config() {
  _dcc_paths
  local cfg="$DCC_HOME_DIR/.claude/dcc-statusline.json"
  [ -f "$cfg" ] && return 0
  mkdir -p "$DCC_HOME_DIR/.claude" || return 0
  cat > "$cfg" <<'JSON'
{
  "lines": [
    ["dir", "git", "model", "effort", "fast", "think", "agent", "style", "account"],
    ["ctx", "cost", "5h", "7d"]
  ],
  "separator": "  ·  ",
  "meters": {
    "width": { "ctx": 10, "5h": 8, "7d": 8 },
    "showEta": true,
    "showTokens": true,
    "ramp": [
      { "at": 0,  "color": "green" },
      { "at": 50, "color": "yellow" },
      { "at": 75, "color": "orange" },
      { "at": 90, "color": "red", "bold": true }
    ]
  },
  "accounts": {},
  "glyphs": { "filled": "█", "empty": "░", "dirty": "*" }
}
JSON
}

dcc_targets() { # dcc_targets <--all|"">
  _dcc_paths
  if [ "${1:-}" = "--all" ]; then
    dcc_account_dirs
  else
    printf '%s\n' "${CLAUDE_CONFIG_DIR:-$DCC_HOME_DIR/.claude}"
  fi
}

dcc_doctor() {
  _dcc_paths
  local rc=0 d
  command -v jq  >/dev/null 2>&1 && printf 'ok   - jq is on PATH\n'  || { printf 'FAIL - jq is not on PATH\n';  rc=1; }
  command -v git >/dev/null 2>&1 && printf 'ok   - git is on PATH\n' || { printf 'warn - git is not on PATH; the git segment will be hidden\n'; }
  if [ -f "$DCC_DEST/statusline.sh" ]; then
    printf 'ok   - scripts are installed at %s\n' "$DCC_DEST"
    if cmp -s "$DCC_SRC_DIR/VERSION" "$DCC_DEST/VERSION"; then
      printf 'ok   - installed copy matches the plugin version\n'
    else
      printf 'warn - installed copy is stale; run: /dcc-statusline install\n'
    fi
  else
    printf 'FAIL - scripts are not installed; run: /dcc-statusline install\n'; rc=1
  fi
  if [ -f "$DCC_HOME_DIR/.claude/dcc-statusline.json" ]; then
    if jq -e . "$DCC_HOME_DIR/.claude/dcc-statusline.json" >/dev/null 2>&1; then
      printf 'ok   - config parses\n'
    else
      printf 'FAIL - config is not valid JSON\n'; rc=1
    fi
  else
    printf 'ok   - no config file; built-in defaults apply\n'
  fi
  for d in $(dcc_account_dirs); do
    if jq -e '.statusLine' "$d/settings.json" >/dev/null 2>&1; then
      printf 'ok   - installed in %s\n' "$d"
    else
      printf 'warn - not installed in %s\n' "$d"
    fi
  done
  return "$rc"
}

dcc_status() {
  _dcc_paths
  local d
  for d in $(dcc_account_dirs); do
    if jq -e '.statusLine' "$d/settings.json" >/dev/null 2>&1; then
      printf '%s: installed\n' "$d"
    else
      printf '%s: not installed\n' "$d"
    fi
  done
  [ -f "$DCC_DEST/VERSION" ] && printf 'installed script version: %s\n' "$(cat "$DCC_DEST/VERSION")"
  printf 'plugin script version: %s\n' "$(cat "$DCC_SRC_DIR/VERSION")"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _dcc_paths
  case "${1:-status}" in
    install)
      dcc_copy_scripts || { printf 'dcc-statusline: could not copy scripts to %s\n' "$DCC_DEST"; exit 1; }
      dcc_seed_config
      for d in $(dcc_targets "${2:-}"); do
        dcc_install_one "$d" && printf 'installed: %s\n' "$d" || printf 'failed: %s\n' "$d"
      done
      ;;
    uninstall)
      for d in $(dcc_targets "${2:-}"); do
        dcc_uninstall_one "$d" && printf 'uninstalled: %s\n' "$d" || printf 'failed: %s\n' "$d"
      done
      ;;
    status) dcc_status ;;
    doctor) dcc_doctor ;;
    *) printf 'usage: install.sh {install|uninstall|status|doctor} [--all]\n'; exit 2 ;;
  esac
fi
