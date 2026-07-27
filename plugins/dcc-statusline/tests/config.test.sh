#!/usr/bin/env bash
# One jq call parses payload + config + account file. Absent files are passed as
# /dev/null and slurp to []; a malformed config falls back to defaults and raises
# DCC_CONFIG_BAD instead of failing the render.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/config.sh"
F="$HERE/fixtures"

# --- config directory key -----------------------------------------------------
HOME=/home/u CLAUDE_CONFIG_DIR="" dcc_config_key
check "no CLAUDE_CONFIG_DIR resolves to ~/.claude" "$DCC_ACCT_KEY" "~/.claude"

HOME=/home/u CLAUDE_CONFIG_DIR=/home/u/.claude-alt dcc_config_key
check "CLAUDE_CONFIG_DIR is abbreviated to a ~ key" "$DCC_ACCT_KEY" "~/.claude-alt"

HOME=/home/u CLAUDE_CONFIG_DIR='C:\Users\q\.claude-alt2' dcc_config_key
check "windows backslashes are normalized" "$DCC_ACCT_KEY" "C:/Users/q/.claude-alt2"

# --- defaults when no config file exists --------------------------------------
DCC_ACCT_KEY="~/.claude"
dcc_parse_all "$(cat "$F/full.json")" /dev/null /dev/null
check "defaults: config is not flagged bad"     "$DCC_CONFIG_BAD" "0"
check "defaults: line one segment order"        "$DCC_LINE1" "dir git model effort fast think agent style account"
check "defaults: line two segment order"        "$DCC_LINE2" "ctx cost 5h 7d"
check "defaults: context meter width"           "$DCC_W_CTX" "10"
check "defaults: usage meter width"             "$DCC_W_5H"  "8"
check "defaults: ramp is sorted ascending"      "$DCC_RAMP"  "0:green: 50:yellow: 75:orange: 90:red:bold"
check "defaults: no account entry means no tint" "$DCC_ACCOUNT_COLOR" ""

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
check "user separator replaces default"    "$DCC_SEP"   " | "
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

finish
