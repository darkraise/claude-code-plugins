#!/usr/bin/env bash
set -uo pipefail
# The single jq call. It parses three things at once -- the payload on stdin, the
# user config, and the account's .claude.json -- because each extra jq process
# costs a fork, and the render path budgets five processes total.

DCC_DEFAULT_CONFIG='{
  "lines": [
    ["dir","git","model","effort","fast","agent","style","account"],
    ["ctx","cost","5h","7d"]
  ],
  "separator": "  \u00b7  ",
  "frame": "auto",
  "icons": { "mode": "auto", "width": 0 },
  "palette": {
    "dir": "blue", "git": "magenta", "model": "cyan",
    "effort": "gray", "fast": "white", "cost": "141", "mute": "gray"
  },
  "meters": {
    "width": {"ctx":10,"5h":8,"7d":8},
    "showEta": true,
    "showTokens": true,
    "ramp": [
      {"at":0,"color":"green"},
      {"at":50,"color":"yellow"},
      {"at":75,"color":"orange"},
      {"at":90,"color":"red","bold":true}
    ]
  },
  "accounts": {},
  "glyphs": {"filled":"\u25b0","empty":"\u25b1","dirty":"*"}
}'

# jq emits shell assignments. @sh quotes every interpolation, so a directory or
# email containing quotes cannot escape into the eval.
#
# Every payload extraction reads `((path)? // null)` and goes through a
# type-checking helper. The payload is the one input nobody validates: a field of
# an unexpected type would otherwise abort jq, and since the fallback chain below
# only ever retries without the *config* and the *account file*, an aborted parse
# costs the entire status line rather than the one segment whose data was wrong.
# The parentheses matter -- a bare `.a.b.c?` guards only the final index, so
# `.rate_limits.five_hour` against an array still aborts.
DCC_JQ_PROG='
. as $p
| (if ($cfg|length) > 0 then ($d * $cfg[0]) else $d end) as $c
| def num($v; $dflt): if ($v|type) == "number" then ($v|floor) else $dflt end;
  def flt($v): if ($v|type) == "number" then $v else "" end;
  def str($v): if ($v|type) == "string" then $v else "" end;
  @sh "DCC_LINE1=\($c.lines[0] // [] | join(" "))",
  @sh "DCC_LINE2=\($c.lines[1] // [] | join(" "))",
  @sh "DCC_SEP=\($c.separator)",
  @sh "DCC_FRAME_MODE=\($c.frame // "auto")",
  @sh "DCC_ICON_MODE_CFG=\($c.icons.mode // "auto")",
  @sh "DCC_ICON_W_CFG=\(num($c.icons.width; 0))",
  @sh "DCC_P_DIR=\($c.palette.dir // "blue")",
  @sh "DCC_P_GIT=\($c.palette.git // "magenta")",
  @sh "DCC_P_MODEL=\($c.palette.model // "cyan")",
  @sh "DCC_P_EFFORT=\($c.palette.effort // "gray")",
  @sh "DCC_P_FAST=\($c.palette.fast // "white")",
  @sh "DCC_P_COST=\($c.palette.cost // "141")",
  @sh "DCC_P_MUTE=\($c.palette.mute // "gray")",
  @sh "DCC_W_CTX=\($c.meters.width.ctx // 10)",
  @sh "DCC_W_5H=\($c.meters.width["5h"] // 8)",
  @sh "DCC_W_7D=\($c.meters.width["7d"] // 8)",
  @sh "DCC_SHOW_ETA=\(if $c.meters.showEta == false then 0 else 1 end)",
  @sh "DCC_SHOW_TOKENS=\(if $c.meters.showTokens == false then 0 else 1 end)",
  @sh "DCC_RAMP=\($c.meters.ramp | sort_by(.at)
                  | map("\(.at):\(.color):\(if .bold then "bold" else "" end)")
                  | join(" "))",
  @sh "DCC_GLYPH_FILLED=\($c.glyphs.filled)",
  @sh "DCC_GLYPH_EMPTY=\($c.glyphs.empty)",
  @sh "DCC_GLYPH_DIRTY=\($c.glyphs.dirty)",
  @sh "DCC_ACCOUNT_COLOR=\($c.accounts[$acct].color // "")",
  @sh "P_EMAIL=\(str(($who[0].oauthAccount.emailAddress)? // null))",
  @sh "P_CWD=\(str((($p.workspace.current_dir)? // ($p.cwd)?) // null))",
  @sh "P_MODEL=\(str(($p.model.display_name)? // null))",
  @sh "P_EFFORT=\(str(($p.effort.level)? // null))",
  @sh "P_FAST=\(if (($p.fast_mode)? // false) then 1 else 0 end)",
  @sh "P_THINK=\(if (($p.thinking.enabled)? // false) then 1 else 0 end)",
  @sh "P_AGENT=\(str(($p.agent.name)? // null))",
  @sh "P_STYLE=\(str(($p.output_style.name)? // null) | if . == "default" then "" else . end)",
  @sh "P_CTX_PCT=\(num(($p.context_window.used_percentage)? // null; ""))",
  @sh "P_CTX_TOK=\(num(($p.context_window.total_input_tokens)? // null; 0))",
  @sh "P_COST=\(flt(($p.cost.total_cost_usd)? // null))",
  @sh "P_5H_PCT=\(num(($p.rate_limits.five_hour.used_percentage)? // null; ""))",
  @sh "P_5H_RESET=\(num(($p.rate_limits.five_hour.resets_at)? // null; ""))",
  @sh "P_7D_PCT=\(num(($p.rate_limits.seven_day.used_percentage)? // null; ""))",
  @sh "P_7D_RESET=\(num(($p.rate_limits.seven_day.resets_at)? // null; ""))"
'

# Defaults for every payload global dcc_parse_all can produce. Under `set -u`,
# a segment reading e.g. $P_MODEL before dcc_parse_all ever runs -- or after
# it legitimately fails and returns 1 without assigning anything -- would
# abort the whole non-interactive shell instead of just rendering an empty
# segment. Declaring them here, the way git.sh pre-declares DCC_GIT_*, closes
# that gap regardless of whether the parse ever succeeds.
P_EMAIL=""
P_CWD=""
P_MODEL=""
P_EFFORT=""
P_FAST=0
P_THINK=0
P_AGENT=""
P_STYLE=""
P_CTX_PCT=""
P_CTX_TOK=""
P_COST=""
P_5H_PCT=""
P_5H_RESET=""
P_7D_PCT=""
P_7D_RESET=""

# Same gap, and the same fix, for the config-side globals: whitespace-only
# stdin holds no JSON value, so jq exits 0 having eval'd nothing at all, and
# dcc_parse_all returns success without assigning a single DCC_* here either.
#
# DCC_LINE1 and DCC_LINE2 default to empty rather than to the segment names
# in DCC_DEFAULT_CONFIG above. Looping over those names would depend on every
# segment handler happening to treat empty P_* data as "render nothing" --
# true today, but an accident of the segment implementations, not a
# guarantee. An empty line list makes the degenerate case render nothing by
# construction: no segment loop runs, so no segment's behavior matters.
DCC_LINE1=""
DCC_LINE2=""
printf -v DCC_SEP '  \302\267  '   # U+00B7 middle dot
DCC_FRAME_MODE="auto"
DCC_ICON_MODE_CFG="auto"
DCC_ICON_W_CFG=0
DCC_P_DIR="blue"
DCC_P_GIT="magenta"
DCC_P_MODEL="cyan"
DCC_P_EFFORT="gray"
DCC_P_FAST="white"
DCC_P_COST="141"
DCC_P_MUTE="gray"
DCC_W_CTX=10
DCC_W_5H=8
DCC_W_7D=8
DCC_SHOW_ETA=1
DCC_SHOW_TOKENS=1
DCC_RAMP="0:green: 50:yellow: 75:orange: 90:red:bold"
printf -v DCC_GLYPH_FILLED '\342\226\260'   # U+25B0
printf -v DCC_GLYPH_EMPTY  '\342\226\261'   # U+25B1
DCC_GLYPH_DIRTY="*"
DCC_ACCOUNT_COLOR=""

dcc_config_path() { # -> DCC_CONFIG_PATH
  DCC_CONFIG_PATH="${DCC_STATUSLINE_CONFIG:-$HOME/.claude/dcc-statusline.json}"
}

dcc_config_key() { # dcc_config_key [home-dir] -> DCC_ACCT_KEY, the "~/.claude-alt" config key
  # Both operands are folded into one namespace first (see lib/path.sh): the
  # config directory arrives in Windows form while $HOME is the MSYS form, and
  # comparing them raw yields a raw absolute path that matches no accounts entry.
  local d h
  dcc_path_norm "${1:-${HOME:-}}"; h="$DCC_PATH"
  dcc_path_norm "${CLAUDE_CONFIG_DIR:-}"; d="$DCC_PATH"
  [ -n "$d" ] || d="$h/.claude"
  case "$d" in
    "$h"/*) DCC_ACCT_KEY="~${d#"$h"}" ;;
    "$h")   DCC_ACCT_KEY="~" ;;
    *)      DCC_ACCT_KEY="$d" ;;
  esac
}

dcc_claude_json_path() { # -> DCC_CLAUDE_JSON, or /dev/null when absent
  # The default account keeps its state at $HOME/.claude.json; every other
  # account keeps it inside its own CLAUDE_CONFIG_DIR.
  local d p
  dcc_path_norm "${CLAUDE_CONFIG_DIR:-}"; d="$DCC_PATH"
  [ -n "$d" ] || { dcc_path_norm "${HOME:-}"; d="$DCC_PATH"; }
  p="$d/.claude.json"
  if [ -f "$p" ]; then DCC_CLAUDE_JSON="$p"; else DCC_CLAUDE_JSON=/dev/null; fi
}

dcc_parse_all() { # dcc_parse_all <payload-json> <config-path> <claude-json-path>
  local input="$1" cfg="$2" who="$3" out cfg_existed=0
  DCC_CONFIG_BAD=0
  [ -f "$cfg" ] && cfg_existed=1
  [ -f "$cfg" ] || cfg=/dev/null
  [ -f "$who" ] || who=/dev/null

  if out=$(jq -r --argjson d "$DCC_DEFAULT_CONFIG" --arg acct "${DCC_ACCT_KEY:-}" \
                 --slurpfile cfg "$cfg" --slurpfile who "$who" \
                 "$DCC_JQ_PROG" <<<"$input" 2>/dev/null); then
    eval "$out"; return 0
  fi

  # The config might be the corrupt one; retry without it so a good account
  # file (and its email) still comes through. A nonexistent config can't be
  # the cause of a failure, so there is nothing to gain by retrying without one.
  if [ "$cfg_existed" -eq 1 ] && \
     out=$(jq -r --argjson d "$DCC_DEFAULT_CONFIG" --arg acct "${DCC_ACCT_KEY:-}" \
                 --slurpfile cfg /dev/null --slurpfile who "$who" \
                 "$DCC_JQ_PROG" <<<"$input" 2>/dev/null); then
    DCC_CONFIG_BAD=1
    eval "$out"; return 0
  fi

  # The config survived that retry (or never existed), so the account's
  # .claude.json must be the corrupt one. Dropping only that keeps the config
  # -- and any account tint it defines -- intact.
  if [ "$cfg_existed" -eq 1 ] && \
     out=$(jq -r --argjson d "$DCC_DEFAULT_CONFIG" --arg acct "${DCC_ACCT_KEY:-}" \
                 --slurpfile cfg "$cfg" --slurpfile who /dev/null \
                 "$DCC_JQ_PROG" <<<"$input" 2>/dev/null); then
    eval "$out"; return 0
  fi

  # Both files are corrupt (or the account file is, and there was no config
  # to begin with). Reaching here with cfg_existed=1 proves the config itself
  # doesn't parse either -- the previous attempt just tried it alone and failed.
  DCC_CONFIG_BAD=$cfg_existed
  out=$(jq -r --argjson d "$DCC_DEFAULT_CONFIG" --arg acct "${DCC_ACCT_KEY:-}" \
             --slurpfile cfg /dev/null --slurpfile who /dev/null \
             "$DCC_JQ_PROG" <<<"$input" 2>/dev/null) || return 1
  eval "$out"
}
