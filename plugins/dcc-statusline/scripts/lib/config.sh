#!/usr/bin/env bash
set -uo pipefail
# The single jq call. It parses three things at once -- the payload on stdin, the
# user config, and the account's .claude.json -- because each extra jq process
# costs a fork, and the render path budgets five processes total.

DCC_DEFAULT_CONFIG='{
  "lines": [
    ["dir","git","model","effort","fast","think","agent","style","account"],
    ["ctx","cost","5h","7d"]
  ],
  "separator": "  ·  ",
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
  "glyphs": {"filled":"█","empty":"░","dirty":"*"}
}'

# jq emits shell assignments. @sh quotes every interpolation, so a directory or
# email containing quotes cannot escape into the eval.
DCC_JQ_PROG='
. as $p
| (if ($cfg|length) > 0 then ($d * $cfg[0]) else $d end) as $c
| def pct($v): if $v == null then "" else ($v|floor) end;
  @sh "DCC_LINE1=\($c.lines[0] // [] | join(" "))",
  @sh "DCC_LINE2=\($c.lines[1] // [] | join(" "))",
  @sh "DCC_SEP=\($c.separator)",
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
  @sh "P_EMAIL=\(if ($who|length) > 0 then ($who[0].oauthAccount.emailAddress // "") else "" end)",
  @sh "P_CWD=\($p.workspace.current_dir // $p.cwd // "")",
  @sh "P_MODEL=\($p.model.display_name // "")",
  @sh "P_EFFORT=\($p.effort.level // "")",
  @sh "P_FAST=\(if $p.fast_mode then 1 else 0 end)",
  @sh "P_THINK=\(if $p.thinking.enabled then 1 else 0 end)",
  @sh "P_AGENT=\($p.agent.name // "")",
  @sh "P_STYLE=\(if ($p.output_style.name // "default") == "default" then "" else ($p.output_style.name) end)",
  @sh "P_CTX_PCT=\(pct($p.context_window.used_percentage))",
  @sh "P_CTX_TOK=\($p.context_window.total_input_tokens // 0)",
  @sh "P_COST=\($p.cost.total_cost_usd // "")",
  @sh "P_5H_PCT=\(pct($p.rate_limits.five_hour.used_percentage))",
  @sh "P_5H_RESET=\($p.rate_limits.five_hour.resets_at // "")",
  @sh "P_7D_PCT=\(pct($p.rate_limits.seven_day.used_percentage))",
  @sh "P_7D_RESET=\($p.rate_limits.seven_day.resets_at // "")"
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
