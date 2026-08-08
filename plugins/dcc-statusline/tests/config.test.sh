#!/usr/bin/env bash
# One jq call parses payload + config + account file. Absent files are passed as
# /dev/null and slurp to []; a malformed config falls back to defaults and raises
# DCC_CONFIG_BAD instead of failing the render.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/path.sh"
source "$HERE/../scripts/lib/jq-prog.sh"
source "$HERE/../scripts/lib/config.sh"
F="$HERE/fixtures"

# --- config directory key -----------------------------------------------------
HOME=/home/u CLAUDE_CONFIG_DIR="" dcc_config_key
check "no CLAUDE_CONFIG_DIR resolves to ~/.claude" "$DCC_ACCT_KEY" "~/.claude"

HOME=/home/u CLAUDE_CONFIG_DIR=/home/u/.claude-alt dcc_config_key
check "CLAUDE_CONFIG_DIR is abbreviated to a ~ key" "$DCC_ACCT_KEY" "~/.claude-alt"

# Windows hands the config directory over in the drive-letter namespace while Git
# Bash sets $HOME to the MSYS one. Every spelling of the same directory has to
# collapse to the one key users are told to write, or the account tint -- the
# reason this plugin exists -- silently never applies to a non-default account.
HOME=/c/Users/q CLAUDE_CONFIG_DIR='C:/Users/q/.claude-alt2' dcc_config_key
check "a drive-letter config dir inside HOME yields a ~ key"  "$DCC_ACCT_KEY" "~/.claude-alt2"

HOME=/c/Users/q CLAUDE_CONFIG_DIR='C:\Users\q\.claude-alt2' dcc_config_key
check "a backslash config dir inside HOME yields a ~ key"     "$DCC_ACCT_KEY" "~/.claude-alt2"

HOME=/c/Users/q CLAUDE_CONFIG_DIR='/c/Users/q/.claude-alt2' dcc_config_key
check "an MSYS config dir inside HOME yields a ~ key"         "$DCC_ACCT_KEY" "~/.claude-alt2"

HOME=/c/Users/q CLAUDE_CONFIG_DIR='c:/Users/q/.claude-alt2/' dcc_config_key
check "a lowercase drive and a trailing slash yield the same key" "$DCC_ACCT_KEY" "~/.claude-alt2"

HOME='C:\Users\q' CLAUDE_CONFIG_DIR='C:/Users/q/.claude-alt2' dcc_config_key
check "a Windows-form HOME is folded as well"                 "$DCC_ACCT_KEY" "~/.claude-alt2"

HOME=/c/Users/q CLAUDE_CONFIG_DIR='C:\Users\q' dcc_config_key
check "a config dir equal to HOME yields a bare ~"            "$DCC_ACCT_KEY" "~"

HOME=/c/Users/q CLAUDE_CONFIG_DIR='D:\Configs\claude' dcc_config_key
check "a config dir genuinely outside HOME stays absolute"    "$DCC_ACCT_KEY" "/d/Configs/claude"

# The key is worth nothing unless it selects an account entry. config-valid.json
# tints "~/.claude-alt" -- the form the README, the seeded config and the slash
# command all tell users to write -- so this is the assertion that fails when the
# key comes out as a raw absolute path instead.
HOME=/c/Users/q CLAUDE_CONFIG_DIR='C:\Users\q\.claude-alt' dcc_config_key
dcc_parse_all "$(cat "$F/full.json")" "$F/config-valid.json" /dev/null
check "a Windows-form config dir still resolves the account tint" "$DCC_ACCOUNT_COLOR" "magenta"
unset CLAUDE_CONFIG_DIR

# --- defaults when no config file exists --------------------------------------
DCC_ACCT_KEY="~/.claude"
dcc_parse_all "$(cat "$F/full.json")" /dev/null /dev/null
check "defaults: config is not flagged bad"     "$DCC_CONFIG_BAD" "0"
check "defaults: line one segment order"        "$DCC_LINE1" "dir git model effort fast agent style account"
check "defaults: line two segment order"        "$DCC_LINE2" "ctx cost 5h 7d"
check "defaults: context meter width"           "$DCC_W_CTX" "10"
check "defaults: usage meter width"             "$DCC_W_5H"  "8"
check "defaults: ramp is sorted ascending"      "$DCC_RAMP"  "0:green: 50:yellow: 75:orange: 90:red:bold"
check "defaults: no account entry means no tint" "$DCC_ACCOUNT_COLOR" ""
check "defaults: frame mode"                    "$DCC_FRAME_MODE"    "auto"
check "defaults: frame margin"                  "$DCC_FRAME_MARGIN"  "4"
check "defaults: icon mode"                     "$DCC_ICON_MODE_CFG" "auto"
check "defaults: icon width defers to detection" "$DCC_ICON_W_CFG"   "0"
check "defaults: path palette"                  "$DCC_P_DIR"    "blue"
check "defaults: branch palette"                "$DCC_P_GIT"    "magenta"
check "defaults: model palette"                 "$DCC_P_MODEL"  "cyan"
check "defaults: effort palette"                "$DCC_P_EFFORT" "gray"
check "defaults: low effort colour"     "$DCC_P_EFF_LOW"    "gray"
check "defaults: medium effort colour"  "$DCC_P_EFF_MEDIUM" "blue"
check "defaults: high effort colour"    "$DCC_P_EFF_HIGH"   "cyan"
check "defaults: xhigh effort colour"   "$DCC_P_EFF_XHIGH"  "141"
check "defaults: max effort colour"     "$DCC_P_EFF_MAX"    "magenta"
check "defaults: fast palette"                  "$DCC_P_FAST"   "white"
check "defaults: cost palette"                  "$DCC_P_COST"   "141"
check "defaults: muted palette"                 "$DCC_P_MUTE"   "gray"

# --- payload extraction -------------------------------------------------------
check "model display name"          "$P_MODEL"     "Opus"
check "effort level"                "$P_EFFORT"    "xhigh"
check "fast mode is a 1/0 flag"     "$P_FAST"      "1"
check "thinking is a 1/0 flag"      "$P_THINK"     "1"
check "default output style is dropped" "$P_STYLE" ""
check "context percentage is floored" "$P_CTX_PCT" "47"
check "context tokens"              "$P_CTX_TOK"   "94210"
check "5h percentage is floored"    "$P_5H_PCT"    "23"
check "5h reset epoch"              "$P_5H_RESET"  "1785900000"
check "7d percentage is floored"    "$P_7D_PCT"    "41"

# --- absent blocks ------------------------------------------------------------
dcc_parse_all "$(cat "$F/fresh.json")" /dev/null /dev/null
check "absent rate_limits yields empty 5h" "$P_5H_PCT"  ""
check "absent rate_limits yields empty 7d" "$P_7D_PCT"  ""
check "null used_percentage yields empty"  "$P_CTX_PCT" ""
check "absent effort yields empty"         "$P_EFFORT"  ""
check "absent email yields empty"          "$P_EMAIL"   ""

# --- user config merges over defaults -----------------------------------------
DCC_ACCT_KEY="~/.claude-alt"
dcc_parse_all "$(cat "$F/full.json")" "$F/config-valid.json" "$F/claude.json"
check "user lines replace defaults"        "$DCC_LINE1" "dir model"
check "user separator replaces default"    "$DCC_SEP1"  " | "
check "user meter width replaces default"  "$DCC_W_CTX" "4"
check "unset meter width keeps default"    "$DCC_W_5H"  "8"
check "out-of-order ramp is sorted"        "$DCC_RAMP"  "0:green: 90:red:bold"
check "matching account resolves a color"  "$DCC_ACCOUNT_COLOR" "magenta"
check "email is read from the account file" "$P_EMAIL"  "someone@example.com"
check "valid config is not flagged bad"    "$DCC_CONFIG_BAD" "0"

# --- malformed config ---------------------------------------------------------
dcc_parse_all "$(cat "$F/full.json")" "$F/config-bad.json" /dev/null
check "malformed config is flagged"        "$DCC_CONFIG_BAD" "1"
check "malformed config falls back to defaults" "$DCC_LINE2" "ctx cost 5h 7d"
check "malformed config still parses payload"   "$P_MODEL"   "Opus"

# --- malformed account file alone -----------------------------------------------
DCC_ACCT_KEY="~/.claude-alt"
dcc_parse_all "$(cat "$F/full.json")" "$F/config-valid.json" "$F/claude-bad.json"
check "malformed account file still parses payload"      "$P_MODEL" "Opus"
check "malformed account file yields empty email"        "$P_EMAIL" ""
check "malformed account file is not a config problem"   "$DCC_CONFIG_BAD" "0"
check "malformed account file still applies user config" "$DCC_LINE1" "dir model"
check "malformed account file still resolves account tint" "$DCC_ACCOUNT_COLOR" "magenta"

# --- both config and account file malformed -------------------------------------
dcc_parse_all "$(cat "$F/full.json")" "$F/config-bad.json" "$F/claude-bad.json"
check "double-malformed still parses payload"         "$P_MODEL"   "Opus"
check "double-malformed falls back to default line two" "$DCC_LINE2" "ctx cost 5h 7d"
check "double-malformed yields empty email"           "$P_EMAIL"   ""
check "double-malformed is flagged as config bad"     "$DCC_CONFIG_BAD" "1"

# --- non-numeric resets_at ------------------------------------------------------
# jq preserves a JSON float verbatim and many serializers emit epoch seconds that
# way, so an uncoerced resets_at reaches bash arithmetic as "1785900000.0" -- a
# syntax error that takes the whole meter line down rather than one segment.
DCC_ACCT_KEY="~/.claude"
dcc_parse_all '{"rate_limits":{"five_hour":{"used_percentage":23,"resets_at":1785900000.0}}}' /dev/null /dev/null
check "a float resets_at is floored to an integer" "$P_5H_RESET" "1785900000"

dcc_parse_all '{"rate_limits":{"seven_day":{"used_percentage":41,"resets_at":1.7864e9}}}' /dev/null /dev/null
check "an exponent-notation resets_at is floored"  "$P_7D_RESET" "1786400000"

dcc_parse_all '{"rate_limits":{"five_hour":{"used_percentage":23,"resets_at":"2026-07-28T10:00:00Z"}}}' /dev/null /dev/null
check "a date-string resets_at yields empty"       "$P_5H_RESET" ""
check "a date-string resets_at keeps its meter"    "$P_5H_PCT"   "23"

dcc_parse_all '{"rate_limits":{"seven_day":{"used_percentage":41,"resets_at":"soon"}}}' /dev/null /dev/null
check "a non-numeric resets_at yields empty"       "$P_7D_RESET" ""

# --- payload type drift ----------------------------------------------------------
# The fallback chain retries without the config and without the account file, but
# never without the payload, so one wrong-typed field used to abort jq and blank
# both lines. A bad field must now cost only its own segment.
dcc_parse_all '{
  "model": "Opus",
  "workspace": "/tmp",
  "cwd": "/tmp/here",
  "context_window": "none",
  "rate_limits": [],
  "output_style": "verbose",
  "cost": 5,
  "effort": { "level": "xhigh" },
  "thinking": { "enabled": true },
  "fast_mode": true
}' /dev/null /dev/null
check "drift: a string model yields an empty model"      "$P_MODEL"   ""
check "drift: a good sibling field still renders"        "$P_EFFORT"  "xhigh"
check "drift: thinking still renders"                    "$P_THINK"   "1"
check "drift: fast mode still renders"                   "$P_FAST"    "1"
check "drift: a string workspace falls back to cwd"      "$P_CWD"     "/tmp/here"
check "drift: a string context_window yields empty pct"  "$P_CTX_PCT" ""
check "drift: an array rate_limits yields empty"         "$P_5H_PCT"  ""
check "drift: a string output_style yields empty"        "$P_STYLE"   ""
check "drift: a numeric cost yields empty"               "$P_COST"    ""
check "drift: the config still loads"                    "$DCC_LINE2" "ctx cost 5h 7d"

dcc_parse_all '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":"47"}}' /dev/null /dev/null
check "drift: a string percentage yields empty"          "$P_CTX_PCT" ""
check "drift: the model survives a string percentage"    "$P_MODEL"   "Opus"

# --- user overrides for frame, icon and palette config -------------------------
cfg="$(mktemp)"
cat > "$cfg" <<'JSON'
{ "frame": "none",
  "frameMargin": 5,
  "icons": { "mode": "nerd", "width": 1 },
  "palette": { "dir": "green" } }
JSON
dcc_parse_all "$(cat "$F/full.json")" "$cfg" /dev/null
check "user frame mode overrides"   "$DCC_FRAME_MODE"    "none"
check "user frame margin overrides" "$DCC_FRAME_MARGIN"  "5"
check "user icon mode overrides"    "$DCC_ICON_MODE_CFG" "nerd"
check "user icon width overrides"   "$DCC_ICON_W_CFG"    "1"
check "user palette entry overrides" "$DCC_P_DIR"        "green"
check "unset palette entries keep defaults" "$DCC_P_GIT" "magenta"
rm -f "$cfg"

# --- segment options -----------------------------------------------------------
cfg="$(mktemp)"
cat > "$cfg" <<'JSON'
{ "segments": {
    "dir":   { "style": "leaf" },
    "git":   { "counters": false, "maxBranch": 14 },
    "model": { "short": true },
    "ctx":   { "label": "context" },
    "5h":    { "label": "session" },
    "7d":    { "label": "week" } } }
JSON
dcc_parse_all "$(cat "$F/full.json")" "$cfg" /dev/null
check "dir style comes through"     "$DCC_SEG_DIR_STYLE"     "leaf"
check "counters false becomes 0"    "$DCC_SEG_GIT_COUNTERS"  "0"
check "maxBranch comes through"     "$DCC_SEG_GIT_MAXBRANCH" "14"
check "model short true becomes 1"  "$DCC_SEG_MODEL_SHORT"   "1"
check "the ctx label comes through" "$DCC_L_CTX"             "context"
check "the 5h label comes through"  "$DCC_L_5H"              "session"
check "the 7d label comes through"  "$DCC_L_7D"              "week"
rm -f "$cfg"

# The whole object is optional: absent, every prior default stands.
dcc_parse_all "$(cat "$F/full.json")" /dev/null /dev/null
check "no segments object leaves the dir style empty" "$DCC_SEG_DIR_STYLE"     ""
check "no segments object keeps counters on"          "$DCC_SEG_GIT_COUNTERS"  "1"
check "no segments object keeps maxBranch at 0"       "$DCC_SEG_GIT_MAXBRANCH" "0"
check "no segments object keeps the model long"       "$DCC_SEG_MODEL_SHORT"   "0"
check "no segments object keeps the ctx label"        "$DCC_L_CTX"             "ctx"
check "no segments object keeps the 7d label"         "$DCC_L_7D"              "7d"

# An empty or non-string label falls back rather than rendering a bare leading
# space where "ctx " used to be, which would read as a rendering bug.
cfg="$(mktemp)"
printf '{ "segments": { "ctx": { "label": "" }, "5h": { "label": 42 } } }' > "$cfg"
dcc_parse_all "$(cat "$F/full.json")" "$cfg" /dev/null
check "an empty label falls back"         "$DCC_L_CTX"      "ctx"
check "a non-string label falls back"     "$DCC_L_5H"       "5h"
check "a bad label is not a config error" "$DCC_CONFIG_BAD" "0"
rm -f "$cfg"

finish
