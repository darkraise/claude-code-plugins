#!/usr/bin/env bash
set -uo pipefail
# The single jq call's program text, its default config, and the theme table.
#
# Split out of config.sh so that file holds only path resolution, the payload
# globals and the fallback chain. The program parses three things at once --
# the payload on stdin, the user config, and the account's .claude.json --
# because each extra jq process costs a fork, and the render path budgets five
# processes total.

DCC_DEFAULT_CONFIG='{
  "lines": [
    ["dir","git","model","effort","fast","agent","style","account"],
    ["ctx","cost","5h","7d"]
  ],
  "separator": "  \u00b7  ",
  "frame": "auto",
  "frameMargin": 4,
  "icons": { "mode": "auto", "width": 0 },
  "palette": {
    "dir": "blue", "git": "magenta", "model": "cyan",
    "effort": "gray", "fast": "white", "cost": "141", "mute": "gray",
    "effortLevels": {
      "low": "gray", "medium": "blue", "high": "cyan",
      "xhigh": "141", "max": "magenta"
    }
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
  @sh "DCC_FRAME_MARGIN=\(num($c.frameMargin; 4))",
  @sh "DCC_ICON_MODE_CFG=\($c.icons.mode // "auto")",
  @sh "DCC_ICON_W_CFG=\(num($c.icons.width; 0))",
  @sh "DCC_P_DIR=\($c.palette.dir // "blue")",
  @sh "DCC_P_GIT=\($c.palette.git // "magenta")",
  @sh "DCC_P_MODEL=\($c.palette.model // "cyan")",
  @sh "DCC_P_EFFORT=\($c.palette.effort // "gray")",
  @sh "DCC_P_EFF_LOW=\($c.palette.effortLevels.low // "gray")",
  @sh "DCC_P_EFF_MEDIUM=\($c.palette.effortLevels.medium // "blue")",
  @sh "DCC_P_EFF_HIGH=\($c.palette.effortLevels.high // "cyan")",
  @sh "DCC_P_EFF_XHIGH=\($c.palette.effortLevels.xhigh // "141")",
  @sh "DCC_P_EFF_MAX=\($c.palette.effortLevels.max // "magenta")",
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
