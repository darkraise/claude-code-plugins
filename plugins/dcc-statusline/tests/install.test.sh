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
# doctor's fixture-probe render goes through the real cache path; without this
# it would write fp-nosession into the real machine's cache directory.
export DCC_CACHE_HOME="$fake/cache"

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

# The two checks above pass even if DCC_HOME_DIR/DCC_DEST were cached at source
# time, because this test file happens to export the fake-home vars before
# sourcing install.sh. That ordering can't distinguish call-time resolution
# from source-time caching, so it proves nothing about which one the code
# actually does. This one forces the distinction: source with the fake-home
# vars still unset, THEN set them, THEN call. Source-time caching would have
# already captured the (unset) fallback to the real $HOME before the export
# ever runs; only call-time resolution can still pick up the export. Runs in
# a command-substitution subshell so an internal failure (or a stray "unbound
# variable" abort under set -u) is captured as a mismatched string rather than
# taking down the rest of this test file.
got_calltime="$(
  unset DCC_FAKE_HOME DCC_STATUSLINE_HOME
  source "$HERE/../scripts/install.sh"
  export DCC_FAKE_HOME="$fake"
  export DCC_STATUSLINE_HOME="$fake/.claude/dcc-statusline"
  dcc_account_dirs | sed "s#^$fake/##" | sort | tr '\n' ' '
)"
check "discovery resolves the fake home at call time, not source time" \
  "$got_calltime" ".claude .claude-alt "

# Regression guard: once DCC_FAKE_HOME is set, an ambient CLAUDE_CONFIG_DIR
# (routine on a machine with more than one account -- and this machine's own
# shell may have one set right now) must not be able to redirect the
# single-account install target outside the fake home. The decoy path is a
# throwaway scratch dir, deliberately never a real account directory, so this
# assertion cannot touch real configuration even if the code under test were
# still broken. Scoped to a subshell for the same reason as the check above:
# an internal failure is a mismatched string, not a crashed test file.
decoy="$(mktemp -d)"
got_target="$(
  export CLAUDE_CONFIG_DIR="$decoy"
  dcc_targets
)"
rm -rf "$decoy"
check "the install target ignores CLAUDE_CONFIG_DIR once DCC_FAKE_HOME is set" \
  "$got_target" "$fake/.claude"

# --- install ------------------------------------------------------------------
dcc_install_one "$fake/.claude-alt"
check "install writes the command" \
  "$(jq -r '.statusLine.command' "$fake/.claude-alt/settings.json")" \
  "bash ~/.claude/dcc-statusline/statusline.sh"
check "install sets a refresh interval" \
  "$(jq -r '.statusLine.refreshInterval' "$fake/.claude-alt/settings.json")" "2"
check "install preserves existing keys" \
  "$(jq -r '.permissions.allow | length' "$fake/.claude-alt/settings.json")" "0"

# --- uninstall is a clean inverse --------------------------------------------
before="$(cat "$fake/.claude/settings.json")"
dcc_install_one "$fake/.claude"
dcc_uninstall_one "$fake/.claude"
after="$(jq -S . "$fake/.claude/settings.json")"
check "uninstall removes the entry" \
  "$(jq -r 'has("statusLine")' "$fake/.claude/settings.json")" "false"
# Semantic equality, not byte equality: jq --indent 2 rewrites the whole file, so
# a 4-space original comes back 2-space and inline arrays are expanded. Comparing
# through jq -S is therefore the strongest claim this can honestly make.
check "install then uninstall restores the content semantically" \
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

# An unset CLAUDE_PLUGIN_ROOT would leave the source path as the bare "/scripts",
# a real absolute path that could exist and be copied from.
check "sync exits quietly without CLAUDE_PLUGIN_ROOT" \
  "$(unset CLAUDE_PLUGIN_ROOT; bash "$HERE/../scripts/sync.sh" 2>&1; printf 'rc=%d' "$?")" \
  "rc=0"

# --- a home directory containing a space --------------------------------------
# Windows home directories routinely contain one. Unquoted, the path list would
# word-split into fragments naming no directory at all.
spacey="$fake/home with space"
mkdir -p "$spacey/.claude"
printf '{"permissions":{"allow":[]}}\n' > "$spacey/.claude/settings.json"
got_spacey="$(
  unset CLAUDE_CONFIG_DIR
  export DCC_FAKE_HOME="$spacey"
  export DCC_STATUSLINE_HOME="$spacey/.claude/dcc-statusline"
  bash "$HERE/../scripts/install.sh" install 2>&1
)"
check "install handles a home directory containing a space" \
  "$got_spacey" "installed: $spacey/.claude"
check "install wrote the entry into the spaced directory" \
  "$(jq -r '.statusLine.type' "$spacey/.claude/settings.json")" "command"

got_spacey="$(
  unset CLAUDE_CONFIG_DIR
  export DCC_FAKE_HOME="$spacey"
  export DCC_STATUSLINE_HOME="$spacey/.claude/dcc-statusline"
  bash "$HERE/../scripts/install.sh" uninstall 2>&1
)"
check "uninstall handles a home directory containing a space" \
  "$got_spacey" "uninstalled: $spacey/.claude"

# --- doctor -------------------------------------------------------------------
# Every other doctor check can pass while the tint never applies and the render
# is broken, which is how a config key nobody could match survived to release.
printf '{"accounts":{"~/.claude":{"color":"magenta"}}}\n' > "$fake/.claude/dcc-statusline.json"
doctor_run() { # doctor_run <config-dir-or-empty>
  local ccd="$1"
  (
    unset CLAUDE_CONFIG_DIR
    [ -n "$ccd" ] && export CLAUDE_CONFIG_DIR="$ccd"
    export HOME="$fake"
    export DCC_FAKE_HOME="$fake"
    export DCC_STATUSLINE_HOME="$fake/.claude/dcc-statusline"
    bash "$HERE/../scripts/install.sh" doctor 2>&1
  )
}

doc="$(doctor_run "")"
check "doctor confirms the active account has a tint entry" \
  "$(printf '%s\n' "$doc" | grep -c 'ok   - ~/.claude has an accounts entry')" "1"
check "doctor renders a fixture payload" \
  "$(printf '%s\n' "$doc" | grep -c 'ok   - a fixture render succeeds')" "1"

doc="$(doctor_run "$fake/.claude-alt")"
check "doctor names an account that has no tint entry" \
  "$(printf '%s\n' "$doc" | grep -c 'warn - ~/.claude-alt has no accounts entry')" "1"

# --- doctor: refresh interval drift ------------------------------------------
# A stale refreshInterval is invisible: everything renders correctly, just
# seconds after the terminal was resized. Only doctor can surface it.
printf '{"statusLine":{"type":"command","command":"x","refreshInterval":60}}\n' \
  > "$fake/.claude-alt/settings.json"
doc="$(doctor_run "")"
check "doctor names an account with a stale refresh interval" \
  "$(printf '%s\n' "$doc" | grep -c "warn - $fake/.claude-alt has refreshInterval 60")" "1"

printf '{"statusLine":{"type":"command","command":"x","refreshInterval":2}}\n' \
  > "$fake/.claude-alt/settings.json"
doc="$(doctor_run "")"
check "doctor is silent when the refresh interval is current" \
  "$(printf '%s\n' "$doc" | grep -c 'has refreshInterval')" "0"

# An entry with no refreshInterval at all predates the key and must be caught.
printf '{"statusLine":{"type":"command","command":"x"}}\n' \
  > "$fake/.claude-alt/settings.json"
doc="$(doctor_run "")"
check "doctor names an account with no refresh interval" \
  "$(printf '%s\n' "$doc" | grep -c "warn - $fake/.claude-alt has refreshInterval unset")" "1"

# --- version agreement --------------------------------------------------------
# The SessionStart sync hook fires on a difference between the plugin's VERSION
# and the installed copy's. If VERSION drifts from the manifest the plugin gets
# a new release that the hook never notices, which is the failure it exists to
# prevent.
check "scripts/VERSION matches the plugin manifest version" \
  "$(cat "$HERE/../scripts/VERSION")" \
  "$(jq -r '.version' "$HERE/../.claude-plugin/plugin.json")"

rm -rf "$fake" "$src"
# DCC_STATUSLINE_HOME is still exported from line 16, pointing at the fake home
# just removed above. Left set, it would override the fresh DCC_FAKE_HOME below
# and silently redirect the next block's writes into that stale, deleted path.
unset DCC_STATUSLINE_HOME

# --- font detection at install ------------------------------------------------
fake="$(mktemp -d)"
export DCC_FAKE_HOME="$fake"
# Re-pointed at the new $fake: the first one (and its cache subdir) was
# already removed above, and the doctor call further down still renders.
export DCC_CACHE_HOME="$fake/cache"
mkdir -p "$fake/.claude"
printf '{}' > "$fake/.claude/settings.json"

DCC_WT_SETTINGS="$HERE/fixtures/wt-nerd.json" \
  bash "$HERE/../scripts/install.sh" install >/dev/null 2>&1
check "install writes the detection cache" \
  "$(cat "$fake/.claude/dcc-statusline/icons.detected" 2>/dev/null)" "nerd 2"

DCC_WT_SETTINGS="$HERE/fixtures/wt-plain.json" \
  bash "$HERE/../scripts/install.sh" install >/dev/null 2>&1
check "re-installing refreshes the cache" \
  "$(cat "$fake/.claude/dcc-statusline/icons.detected" 2>/dev/null)" "unicode 1"

out="$(DCC_WT_SETTINGS="$HERE/fixtures/wt-plain.json" \
  bash "$HERE/../scripts/install.sh" doctor 2>&1)"
check "doctor reports the icon mode" "$(printf '%s' "$out" | grep -c '^icons:')" "1"

# --- font detection on sync ---------------------------------------------------
printf '9.9.9' > "$fake/.claude/dcc-statusline/VERSION"
DCC_WT_SETTINGS="$HERE/fixtures/wt-nerd.json" \
  CLAUDE_PLUGIN_ROOT="$HERE/.." bash "$HERE/../scripts/sync.sh" >/dev/null 2>&1
check "a version change re-runs detection" \
  "$(cat "$fake/.claude/dcc-statusline/icons.detected" 2>/dev/null)" "nerd 2"

rm -rf "$fake"
unset DCC_FAKE_HOME

# --- schema and validation ----------------------------------------------------
# The schema sits under scripts/ so dcc_copy_scripts carries it to an installed
# copy; a file at the plugin root would never be copied, and the installed
# validate.sh would find no schema to read its name lists from.
SCHEMA="$HERE/../scripts/dcc-statusline.schema.json"
check "the schema file exists" "$([ -f "$SCHEMA" ] && echo yes || echo no)" "yes"
check "the schema is valid JSON" \
  "$(jq -e . "$SCHEMA" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "the schema declares every top-level key" \
  "$(jq -r '.properties | keys | length' "$SCHEMA")" "13"

# An install must carry the schema across, or the installed validate.sh silently
# stops checking key, segment and theme names.
cphome="$(mktemp -d)"
DCC_FAKE_HOME="$cphome" DCC_STATUSLINE_HOME="$cphome/dest" dcc_copy_scripts
check "install copies the schema to the destination" \
  "$([ -f "$cphome/dest/dcc-statusline.schema.json" ] && echo yes || echo no)" "yes"
rm -rf "$cphome"

# A seeded config points at the schema so editors validate while typing.
seedhome="$(mktemp -d)"
mkdir -p "$seedhome/.claude"
DCC_FAKE_HOME="$seedhome" dcc_seed_config
check "a seeded config declares \$schema" \
  "$(jq -r '."$schema" // empty' "$seedhome/.claude/dcc-statusline.json" | grep -c 'dcc-statusline.schema.json')" "1"
check "a seeded config still has an accounts map" \
  "$(jq -r '.accounts | type' "$seedhome/.claude/dcc-statusline.json")" "object"
check "a seeded config validates" \
  "$(dcc_validate "$seedhome/.claude/dcc-statusline.json" | grep -c '^FAIL')" "0"
rm -rf "$seedhome"

# doctor names the offending key rather than only reporting that parsing failed.
dochome="$(mktemp -d)"
mkdir -p "$dochome/.claude"
printf '{ "theme": "nonesuch" }' > "$dochome/.claude/dcc-statusline.json"
out="$(DCC_FAKE_HOME="$dochome" dcc_doctor 2>&1)"
check "doctor names an unknown theme" "$(printf '%s' "$out" | grep -c 'nonesuch')" "1"
rm -rf "$dochome"

finish
