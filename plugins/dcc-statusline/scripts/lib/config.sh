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

dcc_config_path() { # -> DCC_CONFIG_PATH
  DCC_CONFIG_PATH="${DCC_STATUSLINE_CONFIG:-$HOME/.claude/dcc-statusline.json}"
}

dcc_config_key() { # -> DCC_ACCT_KEY, the "~/.claude-alt" form used as a config key
  local d="${CLAUDE_CONFIG_DIR:-}"
  [ -n "$d" ] || d="$HOME/.claude"
  d="${d//\\//}"
  d="${d%/}"
  case "$d" in
    "$HOME"/*) DCC_ACCT_KEY="~${d#"$HOME"}" ;;
    "$HOME")   DCC_ACCT_KEY="~" ;;
    *)         DCC_ACCT_KEY="$d" ;;
  esac
}

dcc_claude_json_path() { # -> DCC_CLAUDE_JSON, or /dev/null when absent
  # The default account keeps its state at $HOME/.claude.json; every other
  # account keeps it inside its own CLAUDE_CONFIG_DIR.
  local d="${CLAUDE_CONFIG_DIR:-}" p
  if [ -n "$d" ]; then p="${d%/}/.claude.json"; else p="$HOME/.claude.json"; fi
  if [ -f "$p" ]; then DCC_CLAUDE_JSON="$p"; else DCC_CLAUDE_JSON=/dev/null; fi
}

dcc_parse_all() { # dcc_parse_all <payload-json> <config-path> <claude-json-path>
  local input="$1" cfg="$2" who="$3" out
  DCC_CONFIG_BAD=0
  [ -f "$cfg" ] || cfg=/dev/null
  [ -f "$who" ] || who=/dev/null
  if ! out=$(jq -r --argjson d "$DCC_DEFAULT_CONFIG" --arg acct "${DCC_ACCT_KEY:-}" \
                   --slurpfile cfg "$cfg" --slurpfile who "$who" \
                   "$DCC_JQ_PROG" <<<"$input" 2>/dev/null); then
    DCC_CONFIG_BAD=1
    out=$(jq -r --argjson d "$DCC_DEFAULT_CONFIG" --arg acct "${DCC_ACCT_KEY:-}" \
                --slurpfile cfg /dev/null --slurpfile who "$who" \
                "$DCC_JQ_PROG" <<<"$input" 2>/dev/null) || return 1
  fi
  eval "$out"
}
