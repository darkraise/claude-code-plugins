# dcc-statusline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `plugins/dcc-statusline/`, a two-line Claude Code status line driven by a JSON config, whose meters are colored by usage level and whose remaining segments are tinted by which Claude account the session is running under.

**Architecture:** A thin entry script reads the payload from stdin, makes exactly one `jq` call that parses the payload, the user config, and the account file together, then sources small libraries that each own one responsibility: color resolution, rendering primitives, git collection, and segment functions. Install copies the script tree to a stable path outside the versioned plugin cache; a `SessionStart` hook re-copies it when the plugin version changes.

**Tech Stack:** Bash 4.2+, `jq`, `git`. No Node, no network, no background process, no cache files.

**Pre-verified:** Three pieces of this plan were executed against real inputs on 2026-07-27 before it was written down, so they are known-good rather than plausible. The `jq` program in Task 2 was run against a real payload and confirmed to deep-merge user config over defaults (a user `width.ctx` overrides while `width.5h` keeps its default), floor percentages, resolve the account color by key, and fall back cleanly when passed `/dev/null`. The ramp, bar, and countdown functions in Task 3 passed all 27 boundary and clamp assertions. The porcelain v2 parser in Task 4 passed its fixtures and was additionally run against this repository. If any of those behave differently during implementation, suspect a transcription error rather than a design error.

## Global Constraints

- **Never use command substitution `$(...)` in the render path for a value bash can compute itself.** Every fork costs roughly 10–20ms under MSYS2/Git Bash. Functions return values by assigning documented global out-variables, never by printing for a caller to capture. Prefer parameter expansion over any external command: `${BASH_SOURCE[0]%/*}` not `$(dirname ...)`, `printf -v` not `$(printf ...)`. The only permitted `$(...)` in the render path is capturing the output of the budgeted external calls below — the one `jq` and the two `git` invocations — because their output cannot be obtained any other way. `$(...)` is unrestricted in tests and in `install.sh`, which are not latency-sensitive.
- Budget: **5 processes per render** — one `jq`, two `git`, and the two `timeout` wrappers around them. Anything that raises this needs justification.
- Use `printf -v var '%(%s)T' -1` for the current epoch, never `$(date +%s)`.
- Read stdin with `IFS= read -r -d '' var || true`, never `var=$(cat)`.
- Every script starts `#!/usr/bin/env bash` then `set -uo pipefail`. Never `set -e`: a failing segment must not kill the line.
- Library files define functions only. Guard any top-level execution with `if [ "${BASH_SOURCE[0]}" = "${0}" ]; then ... fi` so tests can source them, matching `plugins/telegram-notify/scripts/telegram-notify.sh:605`.
- All globals this plugin defines are prefixed `DCC_` or `P_` (payload fields).
- Plugin name is `dcc-statusline` in all three places: directory, `plugin.json` `name`, and the `marketplace.json` entry. Repository convention, `CLAUDE.md`.
- Paths written into any `settings.json` use `~` and forward slashes. Git Bash consumes unquoted backslashes.
- Language is English throughout, including comments and commit messages.
- Commit messages use `<type>(<scope>): <subject>`, imperative, 50 characters max, no trailing period.

## File Structure

| File | Responsibility |
|------|----------------|
| `.claude-plugin/plugin.json` | Manifest |
| `scripts/VERSION` | Version marker the sync hook compares |
| `scripts/lib/color.sh` | Named color to ANSI escape |
| `scripts/lib/config.sh` | The single `jq` call: payload, config, and account file into globals |
| `scripts/lib/render.sh` | Ramp lookup, bar drawing, countdown formatting, painting, joining |
| `scripts/lib/git.sh` | One `porcelain=v2` call and its parser |
| `scripts/lib/segments.sh` | One function per segment |
| `scripts/statusline.sh` | Entry point: stdin, orchestration, two lines out |
| `scripts/sync.sh` | Re-copy the tree when the plugin version changes |
| `scripts/install.sh` | Write and remove the `statusLine` entry; discover account directories |
| `hooks/hooks.json` | `SessionStart` to `sync.sh` |
| `commands/dcc-statusline.md` | The slash command |
| `tests/lib.sh` | Shared assertion helpers |
| `tests/*.test.sh` | One test file per library |
| `tests/run-all.sh` | Runs every test file, non-zero on any failure |

---

### Task 1: Scaffold and color library

**Files:**
- Create: `plugins/dcc-statusline/.claude-plugin/plugin.json`
- Create: `plugins/dcc-statusline/scripts/VERSION`
- Create: `plugins/dcc-statusline/scripts/lib/color.sh`
- Create: `plugins/dcc-statusline/tests/lib.sh`
- Test: `plugins/dcc-statusline/tests/color.test.sh`
- Create: `plugins/dcc-statusline/tests/run-all.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `dcc_color <name> [bold]` sets `DCC_C` to an ANSI escape or empty string. `dcc_paint <text> <name> [bold]` sets `DCC_PAINTED`. `dcc_reset` sets `DCC_R`. Test helpers `check <label> <got> <want>`, `finish`, and `strip_ansi` (a filter, used only in tests).

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/lib.sh`:

```bash
#!/usr/bin/env bash
# Shared assertions. Every *.test.sh sources this, then calls finish at the end.
pass=0 fail=0

check() { # check <label> <got> <want>
  if [ "$2" = "$3" ]; then
    printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else
    printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  fi
}

finish() { printf '\n%d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }

# Test-only: strips SGR sequences so assertions compare visible text.
strip_ansi() { sed -E $'s/\033\\[[0-9;]*m//g'; }
```

Create `plugins/dcc-statusline/tests/color.test.sh`:

```bash
#!/usr/bin/env bash
# lib/color.sh maps names to 256-color SGR sequences. Orange is why 256-color
# is used at all: it has no basic-8 equivalent.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/color.sh"

E=$'\033'

dcc_color green;      check "green is 256-color 10"        "$DCC_C" "$E[38;5;10m"
dcc_color orange;     check "orange is 256-color 208"      "$DCC_C" "$E[38;5;208m"
dcc_color red bold;   check "red bold sets the bold flag"  "$DCC_C" "$E[1;38;5;9m"
dcc_color 244;        check "a bare number passes through" "$DCC_C" "$E[38;5;244m"
dcc_color "";         check "empty name yields no escape"  "$DCC_C" ""
dcc_color nosuchhue;  check "unknown name yields no escape" "$DCC_C" ""

dcc_paint "hi" green
check "paint wraps text in color and reset" "$DCC_PAINTED" "$E[38;5;10mhi$E[0m"

dcc_paint "hi" ""
check "paint with no color returns text unchanged" "$DCC_PAINTED" "hi"

dcc_paint "hi" green
check "painted text survives ansi stripping" "$(printf '%s' "$DCC_PAINTED" | strip_ansi)" "hi"

finish
```

Create `plugins/dcc-statusline/tests/run-all.sh`:

```bash
#!/usr/bin/env bash
# Runs every test file. Exits non-zero if any file fails.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$HERE"/*.test.sh; do
  printf '\n=== %s ===\n' "$(basename "$t")"
  bash "$t" || rc=1
done
exit "$rc"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/color.test.sh`
Expected: FAIL — `scripts/lib/color.sh: No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `plugins/dcc-statusline/scripts/lib/color.sh`:

```bash
#!/usr/bin/env bash
# Named colors to ANSI. Every function assigns a global rather than printing:
# capturing output would require $(...), and each fork costs ~10-20ms under
# MSYS2, which the render path cannot afford.

DCC_ESC=$'\033'
DCC_C=""
DCC_R="$DCC_ESC[0m"
DCC_PAINTED=""

dcc_reset() { DCC_R="$DCC_ESC[0m"; }

dcc_color() { # dcc_color <name> [bold] -> DCC_C
  local name="${1:-}" bold="${2:-}" code=""
  case "$name" in
    black)     code=0   ;;
    red)       code=9   ;;
    green)     code=10  ;;
    yellow)    code=11  ;;
    blue)      code=12  ;;
    magenta)   code=13  ;;
    cyan)      code=14  ;;
    white)     code=15  ;;
    orange)    code=208 ;;
    gray|grey) code=245 ;;
    ''|none)   DCC_C=""; return 0 ;;
    *[!0-9]*)  DCC_C=""; return 0 ;;
    *)         code="$name" ;;
  esac
  if [ "$bold" = "bold" ]; then
    DCC_C="$DCC_ESC[1;38;5;${code}m"
  else
    DCC_C="$DCC_ESC[38;5;${code}m"
  fi
}

dcc_paint() { # dcc_paint <text> <color-name> [bold] -> DCC_PAINTED
  dcc_color "${2:-}" "${3:-}"
  if [ -z "$DCC_C" ]; then DCC_PAINTED="$1"; else DCC_PAINTED="$DCC_C$1$DCC_R"; fi
}
```

Create `plugins/dcc-statusline/scripts/VERSION` containing exactly:

```
0.1.0
```

Create `plugins/dcc-statusline/.claude-plugin/plugin.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "dcc-statusline",
  "description": "A two-line Claude Code status line: git detail, model and session state, plus context and rate-limit meters colored by usage level, with the line tinted by which Claude account the session belongs to.",
  "version": "0.1.0",
  "author": {
    "name": "Darkraise"
  },
  "homepage": "https://github.com/darkraise/claude-code-plugins/tree/main/plugins/dcc-statusline",
  "repository": "https://github.com/darkraise/claude-code-plugins",
  "license": "MIT",
  "keywords": [
    "statusline",
    "status-line",
    "multi-account",
    "rate-limits",
    "context-window"
  ]
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/color.test.sh`
Expected: PASS — the summary line ends `0 failed`, exit status 0

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline
git commit -m "feat(statusline): add scaffold and color library"
```

---

### Task 2: Payload and config parsing

The single `jq` call. It reads the payload on stdin, slurps the user config and the account's `.claude.json`, deep-merges the config over built-in defaults, and emits shell assignments quoted with `@sh`. A missing file is passed as `/dev/null`, which slurps to `[]`. If `jq` fails, the config is malformed, so it retries once with the config forced to `/dev/null` and sets `DCC_CONFIG_BAD=1`.

**Files:**
- Create: `plugins/dcc-statusline/scripts/lib/config.sh`
- Create: `plugins/dcc-statusline/tests/fixtures/full.json`
- Create: `plugins/dcc-statusline/tests/fixtures/fresh.json`
- Create: `plugins/dcc-statusline/tests/fixtures/config-valid.json`
- Create: `plugins/dcc-statusline/tests/fixtures/config-bad.json`
- Create: `plugins/dcc-statusline/tests/fixtures/claude.json`
- Test: `plugins/dcc-statusline/tests/config.test.sh`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `dcc_config_key` sets `DCC_ACCT_KEY`. `dcc_claude_json_path` sets `DCC_CLAUDE_JSON`. `dcc_parse_all <payload-json>` sets `DCC_CONFIG_BAD` plus the config globals `DCC_LINE1 DCC_LINE2 DCC_SEP DCC_W_CTX DCC_W_5H DCC_W_7D DCC_SHOW_ETA DCC_SHOW_TOKENS DCC_RAMP DCC_GLYPH_FILLED DCC_GLYPH_EMPTY DCC_GLYPH_DIRTY DCC_ACCOUNT_COLOR` and the payload globals `P_EMAIL P_CWD P_MODEL P_EFFORT P_FAST P_THINK P_AGENT P_STYLE P_CTX_PCT P_CTX_TOK P_COST P_5H_PCT P_5H_RESET P_7D_PCT P_7D_RESET`. Percentages are floored integers or empty string when absent. `DCC_RAMP` is space-separated `at:color:bold` triples sorted ascending by `at`.

- [ ] **Step 1: Write the fixtures**

`tests/fixtures/full.json`:

```json
{
  "cwd": "D:/Repositories/Personal/claude-code-plugins/plugins",
  "session_id": "abc123",
  "model": { "id": "claude-opus-5", "display_name": "Opus" },
  "workspace": { "current_dir": "D:/Repositories/Personal/claude-code-plugins/plugins" },
  "version": "2.1.211",
  "output_style": { "name": "default" },
  "cost": { "total_cost_usd": 1.2034 },
  "context_window": { "total_input_tokens": 94210, "context_window_size": 200000, "used_percentage": 47 },
  "fast_mode": true,
  "effort": { "level": "xhigh" },
  "thinking": { "enabled": true },
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1785900000 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1786400000 }
  }
}
```

`tests/fixtures/fresh.json` — a session right after `/clear`: no `rate_limits`, null percentage, no effort block:

```json
{
  "cwd": "D:/Repositories/Personal/claude-code-plugins",
  "session_id": "def456",
  "model": { "id": "claude-opus-5", "display_name": "Opus" },
  "workspace": { "current_dir": "D:/Repositories/Personal/claude-code-plugins" },
  "output_style": { "name": "default" },
  "cost": { "total_cost_usd": 0 },
  "context_window": { "total_input_tokens": 0, "context_window_size": 200000, "used_percentage": null },
  "fast_mode": false,
  "thinking": { "enabled": false }
}
```

`tests/fixtures/config-valid.json`:

```json
{
  "lines": [["dir", "model"], ["ctx", "5h"]],
  "separator": " | ",
  "meters": {
    "width": { "ctx": 4 },
    "ramp": [
      { "at": 90, "color": "red", "bold": true },
      { "at": 0, "color": "green" }
    ]
  },
  "accounts": { "~/.claude-alt": { "color": "magenta" } }
}
```

`tests/fixtures/config-bad.json`:

```
{ "lines": [["dir"  <-- not json
```

`tests/fixtures/claude.json`:

```json
{ "oauthAccount": { "emailAddress": "someone@example.com" } }
```

- [ ] **Step 2: Write the failing test**

Create `plugins/dcc-statusline/tests/config.test.sh`:

```bash
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

finish
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/config.test.sh`
Expected: FAIL — `scripts/lib/config.sh: No such file or directory`

- [ ] **Step 4: Write the implementation**

Create `plugins/dcc-statusline/scripts/lib/config.sh`:

```bash
#!/usr/bin/env bash
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/config.test.sh`
Expected: PASS — the summary line ends `0 failed`, exit status 0

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-statusline
git commit -m "feat(statusline): parse payload and config in one jq call"
```

---

### Task 3: Rendering primitives

**Files:**
- Create: `plugins/dcc-statusline/scripts/lib/render.sh`
- Test: `plugins/dcc-statusline/tests/render.test.sh`

**Interfaces:**
- Consumes: `dcc_paint` from Task 1; `DCC_RAMP`, `DCC_SEP`, `DCC_GLYPH_FILLED`, `DCC_GLYPH_EMPTY`, `DCC_ACCOUNT_COLOR` from Task 2.
- Produces: `dcc_ramp <pct>` sets `DCC_RAMP_COLOR` and `DCC_RAMP_BOLD`. `dcc_bar <pct> <width>` sets `DCC_BAR`. `dcc_eta <seconds>` sets `DCC_ETA`. `dcc_join_reset` clears the accumulator and `dcc_join_add <colorspec> <text>` appends one painted segment, skipping empty text; the finished line is left in `DCC_JOINED`. A `colorspec` is an empty string, meaning use the account tint, or `"<color>"`, or `"<color> bold"`.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/render.test.sh`:

```bash
#!/usr/bin/env bash
# Rendering primitives: the four-stop ramp, bar fill with its clamps, compact
# countdowns, and separator-aware joining.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/color.sh"
source "$HERE/../scripts/lib/render.sh"

DCC_RAMP="0:green: 50:yellow: 75:orange: 90:red:bold"
DCC_GLYPH_FILLED="#"
DCC_GLYPH_EMPTY="."
DCC_SEP=" | "
DCC_ACCOUNT_COLOR=""

# --- ramp boundaries ----------------------------------------------------------
for pair in "0 green" "49 green" "50 yellow" "74 yellow" "75 orange" "89 orange" "90 red" "100 red"; do
  set -- $pair
  dcc_ramp "$1"
  check "ramp at $1% is $2" "$DCC_RAMP_COLOR" "$2"
done
dcc_ramp 90;  check "the top ramp stop is bold" "$DCC_RAMP_BOLD" "bold"
dcc_ramp 89;  check "lower ramp stops are not bold" "$DCC_RAMP_BOLD" ""
dcc_ramp "";  check "empty percentage yields no ramp color" "$DCC_RAMP_COLOR" ""

# --- bar fill and clamps ------------------------------------------------------
dcc_bar 0 10;   check "0% is an empty bar"                 "$DCC_BAR" "[..........]"
dcc_bar 1 10;   check "1% still shows one filled cell"     "$DCC_BAR" "[#.........]"
dcc_bar 47 10;  check "47% rounds to five cells"           "$DCC_BAR" "[#####.....]"
dcc_bar 99 10;  check "99% still shows one empty cell"     "$DCC_BAR" "[#########.]"
dcc_bar 100 10; check "100% is a full bar"                 "$DCC_BAR" "[##########]"
dcc_bar 50 8;   check "width is honored"                   "$DCC_BAR" "[####....]"
dcc_bar 50 0;   check "zero width yields no bar"           "$DCC_BAR" ""
dcc_bar "" 10;  check "empty percentage yields no bar"     "$DCC_BAR" ""

# --- countdown formatting -----------------------------------------------------
dcc_eta 500400; check "multi-day countdown"      "$DCC_ETA" "5d19h"
dcc_eta 15180;  check "hours and minutes"        "$DCC_ETA" "4h13m"
dcc_eta 2700;   check "minutes only"             "$DCC_ETA" "45m"
dcc_eta 0;      check "zero reads as now"        "$DCC_ETA" "now"
dcc_eta -60;    check "elapsed reads as now"     "$DCC_ETA" "now"
dcc_eta "";     check "empty seconds yields nothing" "$DCC_ETA" ""

# --- joining ------------------------------------------------------------------
dcc_join_reset
dcc_join_add "" "one"
dcc_join_add "" "two"
check "segments are joined with the separator" "$(printf '%s' "$DCC_JOINED" | strip_ansi)" "one | two"

dcc_join_reset
dcc_join_add "" "one"
dcc_join_add "" ""
dcc_join_add "" "three"
check "an empty segment leaves no doubled separator" \
  "$(printf '%s' "$DCC_JOINED" | strip_ansi)" "one | three"

dcc_join_reset
dcc_join_add "" ""
check "an all-empty line renders as nothing" "$DCC_JOINED" ""

DCC_ACCOUNT_COLOR="magenta"
dcc_join_reset
dcc_join_add "" "tinted"
check "an empty colorspec takes the account tint" "$DCC_JOINED" $'\033[38;5;13mtinted\033[0m'

dcc_join_reset
dcc_join_add "red bold" "warn"
check "an explicit colorspec overrides the tint" "$DCC_JOINED" $'\033[1;38;5;9mwarn\033[0m'

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/render.test.sh`
Expected: FAIL — `scripts/lib/render.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

Create `plugins/dcc-statusline/scripts/lib/render.sh`:

```bash
#!/usr/bin/env bash
# Rendering primitives. Out-variables throughout, for the fork reason in color.sh.

DCC_RAMP_COLOR=""
DCC_RAMP_BOLD=""
DCC_BAR=""
DCC_ETA=""
DCC_JOINED=""
DCC_JOIN_EMPTY=1

dcc_ramp() { # dcc_ramp <pct> -> DCC_RAMP_COLOR, DCC_RAMP_BOLD
  local pct="${1:-}" stop at rest
  DCC_RAMP_COLOR=""; DCC_RAMP_BOLD=""
  [ -n "$pct" ] || return 0
  # DCC_RAMP is sorted ascending, so the last stop at or below pct wins.
  for stop in $DCC_RAMP; do
    at="${stop%%:*}"
    rest="${stop#*:}"
    [ "$pct" -ge "$at" ] 2>/dev/null || continue
    DCC_RAMP_COLOR="${rest%%:*}"
    DCC_RAMP_BOLD="${rest#*:}"
  done
}

dcc_bar() { # dcc_bar <pct> <width> -> DCC_BAR
  local pct="${1:-}" width="${2:-0}" filled i out=""
  DCC_BAR=""
  [ -n "$pct" ] || return 0
  [ "$width" -gt 0 ] 2>/dev/null || return 0
  filled=$(( (pct * width + 50) / 100 ))
  # Clamp both ends so a non-zero reading never looks empty and an incomplete
  # one never looks full.
  [ "$filled" -lt 1 ] && [ "$pct" -gt 0 ] && filled=1
  [ "$filled" -ge "$width" ] && [ "$pct" -lt 100 ] && filled=$(( width - 1 ))
  [ "$filled" -lt 0 ] && filled=0
  [ "$filled" -gt "$width" ] && filled="$width"
  for (( i = 0; i < width; i++ )); do
    if [ "$i" -lt "$filled" ]; then out="$out$DCC_GLYPH_FILLED"; else out="$out$DCC_GLYPH_EMPTY"; fi
  done
  DCC_BAR="[$out]"
}

dcc_eta() { # dcc_eta <seconds-until-reset> -> DCC_ETA
  local s="${1:-}" d h m
  DCC_ETA=""
  [ -n "$s" ] || return 0
  if [ "$s" -le 0 ] 2>/dev/null; then DCC_ETA="now"; return 0; fi
  d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf -v DCC_ETA '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf -v DCC_ETA '%dh%dm' "$h" "$m"
  else                     printf -v DCC_ETA '%dm' "$m"
  fi
}

dcc_join_reset() { DCC_JOINED=""; DCC_JOIN_EMPTY=1; }

dcc_join_add() { # dcc_join_add <colorspec> <text>
  local spec="${1:-}" text="${2:-}" color bold
  [ -n "$text" ] || return 0
  if [ -n "$spec" ]; then
    color="${spec%% *}"
    bold="${spec#* }"
    [ "$bold" = "$spec" ] && bold=""
  else
    color="$DCC_ACCOUNT_COLOR"; bold=""
  fi
  if [ "$DCC_JOIN_EMPTY" -eq 0 ]; then
    dcc_paint "$DCC_SEP" "$DCC_ACCOUNT_COLOR"
    DCC_JOINED="$DCC_JOINED$DCC_PAINTED"
  fi
  dcc_paint "$text" "$color" "$bold"
  DCC_JOINED="$DCC_JOINED$DCC_PAINTED"
  DCC_JOIN_EMPTY=0
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/render.test.sh`
Expected: PASS — the summary line ends `0 failed`, exit status 0

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline
git commit -m "feat(statusline): add ramp, bar, eta, and join primitives"
```

---

### Task 4: Git collection

**Files:**
- Create: `plugins/dcc-statusline/scripts/lib/git.sh`
- Create: `plugins/dcc-statusline/tests/fixtures/porcelain-dirty.txt`
- Create: `plugins/dcc-statusline/tests/fixtures/porcelain-clean.txt`
- Create: `plugins/dcc-statusline/tests/fixtures/porcelain-detached.txt`
- Test: `plugins/dcc-statusline/tests/git.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `dcc_git_parse <porcelain-v2-text>` sets `DCC_GIT_BRANCH DCC_GIT_AHEAD DCC_GIT_BEHIND DCC_GIT_STAGED DCC_GIT_UNSTAGED DCC_GIT_UNTRACKED DCC_GIT_DIRTY`. `dcc_git_collect <dir>` runs git and calls the parser, additionally setting `DCC_GIT_ROOT`; it returns non-zero and leaves `DCC_GIT_BRANCH` empty when the directory is not a repository or git is unavailable.

- [ ] **Step 1: Write the fixtures**

`tests/fixtures/porcelain-dirty.txt` — two staged, one unstaged, two untracked, ahead 2 behind 1:

```
# branch.oid 79da753a9b1c4e2f8a0d6c5b3e1f0a9d8c7b6a54
# branch.head feat/dcc-statusline
# branch.upstream origin/feat/dcc-statusline
# branch.ab +2 -1
1 M. N... 100644 100644 100644 aaa bbb scripts/statusline.sh
1 A. N... 000000 100644 100644 000 ccc scripts/lib/git.sh
1 .M N... 100644 100644 100644 ddd eee README.md
? notes.txt
? scratch/
```

`tests/fixtures/porcelain-clean.txt`:

```
# branch.oid 79da753a9b1c4e2f8a0d6c5b3e1f0a9d8c7b6a54
# branch.head main
# branch.upstream origin/main
# branch.ab +0 -0
```

`tests/fixtures/porcelain-detached.txt`:

```
# branch.oid 79da753a9b1c4e2f8a0d6c5b3e1f0a9d8c7b6a54
# branch.head (detached)
1 .M N... 100644 100644 100644 ddd eee README.md
```

- [ ] **Step 2: Write the failing test**

Create `plugins/dcc-statusline/tests/git.test.sh`:

```bash
#!/usr/bin/env bash
# A single `git status --porcelain=v2 --branch` carries the branch, the upstream
# ahead/behind counts, and per-file staged/unstaged/untracked state, so the
# detail counts cost no extra git invocation. The parser is tested against
# captured output rather than a live repository.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/git.sh"
F="$HERE/fixtures"

dcc_git_parse "$(cat "$F/porcelain-dirty.txt")"
check "branch name"             "$DCC_GIT_BRANCH"    "feat/dcc-statusline"
check "ahead count"             "$DCC_GIT_AHEAD"     "2"
check "behind count"            "$DCC_GIT_BEHIND"    "1"
check "staged file count"       "$DCC_GIT_STAGED"    "2"
check "unstaged file count"     "$DCC_GIT_UNSTAGED"  "1"
check "untracked entry count"   "$DCC_GIT_UNTRACKED" "2"
check "dirty flag is set"       "$DCC_GIT_DIRTY"     "1"

dcc_git_parse "$(cat "$F/porcelain-clean.txt")"
check "clean tree: branch"      "$DCC_GIT_BRANCH"    "main"
check "clean tree: no ahead"    "$DCC_GIT_AHEAD"     "0"
check "clean tree: no behind"   "$DCC_GIT_BEHIND"    "0"
check "clean tree: no staged"   "$DCC_GIT_STAGED"    "0"
check "clean tree: not dirty"   "$DCC_GIT_DIRTY"     "0"

dcc_git_parse "$(cat "$F/porcelain-detached.txt")"
check "detached HEAD is labeled"        "$DCC_GIT_BRANCH" "detached"
check "detached HEAD without upstream"  "$DCC_GIT_AHEAD"  "0"
check "detached HEAD still counts work" "$DCC_GIT_DIRTY"  "1"

dcc_git_parse ""
check "empty input yields no branch" "$DCC_GIT_BRANCH" ""

# A directory that is not a repository must fail cleanly, not error out.
tmp="$(mktemp -d)"
if dcc_git_collect "$tmp"; then rc=0; else rc=1; fi
check "collect fails outside a repository"   "$rc" "1"
check "collect leaves no stale branch"       "$DCC_GIT_BRANCH" ""
rmdir "$tmp"

finish
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/git.test.sh`
Expected: FAIL — `scripts/lib/git.sh: No such file or directory`

- [ ] **Step 4: Write the implementation**

Create `plugins/dcc-statusline/scripts/lib/git.sh`:

```bash
#!/usr/bin/env bash
# Git state from one porcelain=v2 call. In porcelain v2 a changed entry looks
# like "1 <XY> ..." where X is the staged status and Y the unstaged one, and "."
# means unchanged -- so staged and unstaged counts come from the same lines that
# carry the branch header.

DCC_GIT_BRANCH=""
DCC_GIT_AHEAD=0
DCC_GIT_BEHIND=0
DCC_GIT_STAGED=0
DCC_GIT_UNSTAGED=0
DCC_GIT_UNTRACKED=0
DCC_GIT_DIRTY=0
DCC_GIT_ROOT=""

# Resolve the timeout wrapper once. `command -v` is a builtin, so this costs no
# fork; if coreutils timeout is missing the git calls simply run unguarded.
if command -v timeout >/dev/null 2>&1; then DCC_TIMEOUT="timeout 1"; else DCC_TIMEOUT=""; fi

dcc_git_parse() { # dcc_git_parse <porcelain-v2-text>
  local line ab xy x y
  DCC_GIT_BRANCH=""; DCC_GIT_AHEAD=0; DCC_GIT_BEHIND=0
  DCC_GIT_STAGED=0; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=0; DCC_GIT_DIRTY=0
  while IFS= read -r line; do
    case "$line" in
      '# branch.head '*)
        DCC_GIT_BRANCH="${line#\# branch.head }"
        [ "$DCC_GIT_BRANCH" = "(detached)" ] && DCC_GIT_BRANCH="detached"
        ;;
      '# branch.ab '*)
        ab="${line#\# branch.ab }"
        DCC_GIT_AHEAD="${ab%% *}";  DCC_GIT_AHEAD="${DCC_GIT_AHEAD#+}"
        DCC_GIT_BEHIND="${ab##* }"; DCC_GIT_BEHIND="${DCC_GIT_BEHIND#-}"
        ;;
      '1 '*|'2 '*)
        xy="${line:2:2}"; x="${xy:0:1}"; y="${xy:1:1}"
        [ "$x" != "." ] && DCC_GIT_STAGED=$(( DCC_GIT_STAGED + 1 ))
        [ "$y" != "." ] && DCC_GIT_UNSTAGED=$(( DCC_GIT_UNSTAGED + 1 ))
        ;;
      'u '*) DCC_GIT_UNSTAGED=$(( DCC_GIT_UNSTAGED + 1 )) ;;
      '? '*) DCC_GIT_UNTRACKED=$(( DCC_GIT_UNTRACKED + 1 )) ;;
    esac
  done <<<"$1"
  [ $(( DCC_GIT_STAGED + DCC_GIT_UNSTAGED + DCC_GIT_UNTRACKED )) -gt 0 ] && DCC_GIT_DIRTY=1
  return 0
}

dcc_git_collect() { # dcc_git_collect <dir> -> parsed globals + DCC_GIT_ROOT; non-zero outside a repo
  local dir="${1:-}" out root
  DCC_GIT_BRANCH=""; DCC_GIT_ROOT=""
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  out=$($DCC_TIMEOUT git -C "$dir" status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null) || return 1
  [ -n "$out" ] || return 1
  dcc_git_parse "$out"
  [ -n "$DCC_GIT_BRANCH" ] || return 1
  root=$($DCC_TIMEOUT git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=""
  DCC_GIT_ROOT="${root//\\//}"
  return 0
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/git.test.sh`
Expected: PASS — the summary line ends `0 failed`, exit status 0

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-statusline
git commit -m "feat(statusline): collect git state in one porcelain call"
```

---

### Task 5: Segment functions

**Files:**
- Create: `plugins/dcc-statusline/scripts/lib/segments.sh`
- Test: `plugins/dcc-statusline/tests/segments.test.sh`

**Interfaces:**
- Consumes: the `P_*` and `DCC_*` globals from Task 2, `dcc_ramp`, `dcc_bar`, `dcc_eta` from Task 3, and the `DCC_GIT_*` globals from Task 4.
- Produces: `dcc_segment <name>` sets `DCC_SEG_SPEC` (a colorspec, empty meaning account tint) and `DCC_SEG_TEXT` (empty when the segment has nothing to show). Recognized names: `dir git model effort fast think agent style account ctx cost 5h 7d`. An unrecognized name yields empty text rather than an error.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/segments.test.sh`:

```bash
#!/usr/bin/env bash
# One function per segment. Every segment returns empty text rather than failing
# when its data is absent, which is what keeps a missing rate_limits block or a
# non-repository directory from taking the whole line down.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/color.sh"
source "$HERE/../scripts/lib/render.sh"
source "$HERE/../scripts/lib/git.sh"
source "$HERE/../scripts/lib/segments.sh"

DCC_RAMP="0:green: 50:yellow: 75:orange: 90:red:bold"
DCC_GLYPH_FILLED="#"; DCC_GLYPH_EMPTY="."; DCC_GLYPH_DIRTY="*"
DCC_W_CTX=10; DCC_W_5H=8; DCC_W_7D=8
DCC_SHOW_ETA=1; DCC_SHOW_TOKENS=1
DCC_NOW=1785886800   # fixed clock so countdowns are deterministic

seg() { dcc_segment "$1"; printf '%s' "$DCC_SEG_TEXT"; }

# --- dir ----------------------------------------------------------------------
P_CWD="D:/Repositories/Personal/claude-code-plugins/plugins"
DCC_GIT_ROOT="D:/Repositories/Personal/claude-code-plugins"
check "inside a repo, dir is repo-relative" "$(seg dir)" "claude-code-plugins/plugins"

DCC_GIT_ROOT="D:/Repositories/Personal/claude-code-plugins"
P_CWD="D:/Repositories/Personal/claude-code-plugins"
check "at the repo root, dir is the repo name" "$(seg dir)" "claude-code-plugins"

DCC_GIT_ROOT=""
HOME="/home/u"; P_CWD="/home/u/projects/thing"
check "outside a repo, HOME is abbreviated" "$(seg dir)" "~/projects/thing"

P_CWD="/opt/elsewhere"
check "outside HOME, the path is shown whole" "$(seg dir)" "/opt/elsewhere"

# --- git ----------------------------------------------------------------------
DCC_GIT_BRANCH="main"; DCC_GIT_DIRTY=0
DCC_GIT_AHEAD=0; DCC_GIT_BEHIND=0
DCC_GIT_STAGED=0; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=0
check "a clean branch shows only its name" "$(seg git)" "main"

DCC_GIT_DIRTY=1; DCC_GIT_AHEAD=2; DCC_GIT_BEHIND=1
DCC_GIT_STAGED=3; DCC_GIT_UNSTAGED=1; DCC_GIT_UNTRACKED=2
check "a dirty branch shows the marker and every non-zero count" \
  "$(seg git)" "main* ↑2↓1 ●3 ○1 ?2"

DCC_GIT_BRANCH=""
check "no branch means no git segment" "$(seg git)" ""

# --- session state chips ------------------------------------------------------
P_MODEL="Opus";  check "model"                    "$(seg model)"  "Opus"
P_EFFORT="xhigh"; check "effort level"            "$(seg effort)" "xhigh"
P_EFFORT="";      check "absent effort is hidden" "$(seg effort)" ""
P_FAST=1;  check "fast mode shows when on"        "$(seg fast)"   "fast"
P_FAST=0;  check "fast mode hides when off"       "$(seg fast)"   ""
P_THINK=1; check "thinking shows when on"         "$(seg think)"  "think"
P_THINK=0; check "thinking hides when off"        "$(seg think)"  ""
P_AGENT="security-reviewer"; check "agent name"   "$(seg agent)"  "security-reviewer"
P_AGENT="";                  check "no agent"     "$(seg agent)"  ""
P_STYLE="explanatory"; check "output style"       "$(seg style)"  "explanatory"
P_EMAIL="a@b.co";  check "account email"          "$(seg account)" "a@b.co"
P_EMAIL="";        check "no email means no chip" "$(seg account)" ""

# --- cost ---------------------------------------------------------------------
P_COST="1.2034"; check "cost is two decimal places" "$(seg cost)" "\$1.20"
P_COST="";       check "absent cost is hidden"      "$(seg cost)" ""

# --- meters -------------------------------------------------------------------
P_CTX_PCT=47; P_CTX_TOK=94210
check "context meter: bar, percentage, tokens" "$(seg ctx)" "ctx [#####.....] 47% (94k)"
dcc_segment ctx
check "context meter takes its ramp color, not the tint" "$DCC_SEG_SPEC" "green "

P_CTX_TOK=800
check "sub-1k token counts are shown raw" "$(seg ctx)" "ctx [#####.....] 47% (800)"

DCC_SHOW_TOKENS=0
check "tokens can be turned off" "$(seg ctx)" "ctx [#####.....] 47%"
DCC_SHOW_TOKENS=1

P_CTX_PCT=""
check "a null context percentage hides the meter" "$(seg ctx)" ""

P_5H_PCT=23; P_5H_RESET=1785900000
check "5h meter with countdown" "$(seg 5h)" "5h [##......] 23% (3h40m)"

P_5H_PCT=92
dcc_segment 5h
check "a meter above 90% turns red and bold" "$DCC_SEG_SPEC" "red bold"

DCC_SHOW_ETA=0
P_5H_PCT=23
check "the countdown can be turned off" "$(seg 5h)" "5h [##......] 23%"
DCC_SHOW_ETA=1

P_5H_PCT=""; P_5H_RESET=""
check "an absent rate limit hides the meter" "$(seg 5h)" ""

P_7D_PCT=41; P_7D_RESET=1786400000
check "7d meter with a multi-day countdown" "$(seg 7d)" "7d [###.....] 41% (5d22h)"

# --- unknown ------------------------------------------------------------------
check "an unknown segment name is ignored" "$(seg nosuchsegment)" ""

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/segments.test.sh`
Expected: FAIL — `scripts/lib/segments.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

Create `plugins/dcc-statusline/scripts/lib/segments.sh`:

```bash
#!/usr/bin/env bash
# One function per segment, dispatched by name. Each sets DCC_SEG_SPEC (a
# colorspec; empty means "use the account tint") and DCC_SEG_TEXT (empty means
# "render nothing"). Returning empty rather than failing is what makes a missing
# block degrade to a shorter line instead of a broken one.

DCC_SEG_SPEC=""
DCC_SEG_TEXT=""

_dcc_meter() { # _dcc_meter <label> <pct> <width> <reset-epoch> <tokens|"">
  local label="$1" pct="$2" width="$3" reset="$4" tokens="$5" text
  DCC_SEG_SPEC=""; DCC_SEG_TEXT=""
  [ -n "$pct" ] || return 0
  dcc_ramp "$pct"
  DCC_SEG_SPEC="$DCC_RAMP_COLOR $DCC_RAMP_BOLD"
  dcc_bar "$pct" "$width"
  text="$label $DCC_BAR ${pct}%"
  if [ "$DCC_SHOW_TOKENS" -eq 1 ] && [ -n "$tokens" ]; then
    if [ "$tokens" -ge 1000 ] 2>/dev/null; then
      text="$text ($(( tokens / 1000 ))k)"
    else
      text="$text ($tokens)"
    fi
  fi
  if [ "$DCC_SHOW_ETA" -eq 1 ] && [ -n "$reset" ]; then
    dcc_eta $(( reset - DCC_NOW ))
    [ -n "$DCC_ETA" ] && text="$text ($DCC_ETA)"
  fi
  DCC_SEG_TEXT="$text"
}

dcc_segment() { # dcc_segment <name> -> DCC_SEG_SPEC, DCC_SEG_TEXT
  local name="${1:-}" t
  DCC_SEG_SPEC=""; DCC_SEG_TEXT=""
  case "$name" in
    dir)
      if [ -n "$DCC_GIT_ROOT" ]; then
        case "$P_CWD" in
          "$DCC_GIT_ROOT") DCC_SEG_TEXT="${DCC_GIT_ROOT##*/}" ;;
          "$DCC_GIT_ROOT"/*) DCC_SEG_TEXT="${DCC_GIT_ROOT##*/}${P_CWD#"$DCC_GIT_ROOT"}" ;;
          *) DCC_SEG_TEXT="$P_CWD" ;;
        esac
      else
        case "$P_CWD" in
          "$HOME"/*) DCC_SEG_TEXT="~${P_CWD#"$HOME"}" ;;
          *)         DCC_SEG_TEXT="$P_CWD" ;;
        esac
      fi
      ;;
    git)
      [ -n "$DCC_GIT_BRANCH" ] || return 0
      t="$DCC_GIT_BRANCH"
      [ "$DCC_GIT_DIRTY" -eq 1 ] && t="$t$DCC_GLYPH_DIRTY"
      [ "$DCC_GIT_AHEAD"  -gt 0 ] && t="$t ↑$DCC_GIT_AHEAD"
      [ "$DCC_GIT_BEHIND" -gt 0 ] && t="${t}↓$DCC_GIT_BEHIND"
      [ "$DCC_GIT_STAGED"    -gt 0 ] && t="$t ●$DCC_GIT_STAGED"
      [ "$DCC_GIT_UNSTAGED"  -gt 0 ] && t="$t ○$DCC_GIT_UNSTAGED"
      [ "$DCC_GIT_UNTRACKED" -gt 0 ] && t="$t ?$DCC_GIT_UNTRACKED"
      DCC_SEG_TEXT="$t"
      ;;
    model)   DCC_SEG_TEXT="$P_MODEL" ;;
    effort)  DCC_SEG_TEXT="$P_EFFORT" ;;
    fast)    [ "$P_FAST"  -eq 1 ] && DCC_SEG_TEXT="fast" ;;
    think)   [ "$P_THINK" -eq 1 ] && DCC_SEG_TEXT="think" ;;
    agent)   DCC_SEG_TEXT="$P_AGENT" ;;
    style)   DCC_SEG_TEXT="$P_STYLE" ;;
    account) DCC_SEG_TEXT="$P_EMAIL" ;;
    cost)
      [ -n "$P_COST" ] || return 0
      printf -v DCC_SEG_TEXT '$%.2f' "$P_COST" 2>/dev/null || DCC_SEG_TEXT=""
      ;;
    ctx) _dcc_meter "ctx" "$P_CTX_PCT" "$DCC_W_CTX" "" "$P_CTX_TOK" ;;
    5h)  _dcc_meter "5h"  "$P_5H_PCT"  "$DCC_W_5H"  "$P_5H_RESET" "" ;;
    7d)  _dcc_meter "7d"  "$P_7D_PCT"  "$DCC_W_7D"  "$P_7D_RESET" "" ;;
  esac
  return 0
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/segments.test.sh`
Expected: PASS — the summary line ends `0 failed`, exit status 0

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline
git commit -m "feat(statusline): add segment functions"
```

---

### Task 6: Entry script

**Files:**
- Create: `plugins/dcc-statusline/scripts/statusline.sh`
- Test: `plugins/dcc-statusline/tests/e2e.test.sh`

**Interfaces:**
- Consumes: every library from Tasks 1 through 5.
- Produces: an executable that reads the payload on stdin and prints one or two lines. `DCC_NOW` may be preset by tests to freeze the clock. `DCC_STATUSLINE_CONFIG` overrides the config path.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/e2e.test.sh`:

```bash
#!/usr/bin/env bash
# End to end: a payload on stdin produces the finished lines. Asserts on
# ANSI-stripped text, plus one check that the tint and the ramp coexist.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../scripts/statusline.sh"
F="$HERE/fixtures"

export DCC_NOW=1785886800
export DCC_STATUSLINE_CONFIG=/dev/null
export CLAUDE_CONFIG_DIR=""

out="$(bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
line1="$(printf '%s\n' "$out" | sed -n 1p)"
line2="$(printf '%s\n' "$out" | sed -n 2p)"

check "line one carries model and state chips" \
  "$(printf '%s' "$line1" | grep -c 'Opus  ·  xhigh  ·  fast  ·  think')" "1"
check "line two carries all three meters" \
  "$(printf '%s' "$line2" | grep -c 'ctx \[.*\] 47% (94k)  ·  \$1.20  ·  5h \[.*\] 23% (3h40m)  ·  7d \[.*\] 41% (5d22h)')" "1"

# A fresh session has no rate_limits and a null percentage, so line two has
# nothing but cost -- and must not print as a bare separator.
out="$(bash "$SCRIPT" < "$F/fresh.json" | strip_ansi)"
line2="$(printf '%s\n' "$out" | sed -n 2p)"
check "a fresh session shows only cost on line two" "$line2" "\$0.00"
check "no doubled separator when meters are absent" \
  "$(printf '%s' "$line2" | grep -c '·  ·')" "0"

# Empty stdin must not produce a traceback or a stray line.
out="$(printf '' | bash "$SCRIPT" 2>&1)"
check "empty stdin renders nothing" "$out" ""

# A malformed config still renders, with a visible marker.
badcfg="$(mktemp)"; printf '{ not json' > "$badcfg"
out="$(DCC_STATUSLINE_CONFIG="$badcfg" bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
check "a malformed config renders with a marker" \
  "$(printf '%s' "$out" | grep -c 'cfg?')" "1"
rm -f "$badcfg"

# Tint and ramp coexist: the account color paints line one, the ramp paints the
# meters, and the two must both appear in the raw output.
cfg="$(mktemp)"
cat > "$cfg" <<'JSON'
{ "accounts": { "~/.claude": { "color": "magenta" } } }
JSON
raw="$(DCC_STATUSLINE_CONFIG="$cfg" bash "$SCRIPT" < "$F/full.json")"
check "the account tint is applied" "$(printf '%s' "$raw" | grep -c $'\033\\[38;5;13m')" "1"
check "the ramp color is applied to a meter" "$(printf '%s' "$raw" | grep -c $'\033\\[38;5;10m')" "1"
rm -f "$cfg"

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/e2e.test.sh`
Expected: FAIL — `statusline.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

Create `plugins/dcc-statusline/scripts/statusline.sh`:

```bash
#!/usr/bin/env bash
# Claude Code status line. Reads the session payload on stdin, prints two lines.
#
# Process budget: one jq, two git, and the timeout wrappers around them. Nothing
# in this file may use $(...) -- see the note in lib/color.sh.
set -uo pipefail

# Resolve our own directory by parameter expansion only. $(cd ... && pwd) would
# cost two forks on every render, which the process budget does not allow.
DCC_DIR="${BASH_SOURCE[0]%/*}"
[ "$DCC_DIR" = "${BASH_SOURCE[0]}" ] && DCC_DIR="."

source "$DCC_DIR/lib/color.sh"
source "$DCC_DIR/lib/config.sh"
source "$DCC_DIR/lib/render.sh"
source "$DCC_DIR/lib/git.sh"
source "$DCC_DIR/lib/segments.sh"

dcc_main() {
  local input="" name

  IFS= read -r -d '' input || true
  [ -n "$input" ] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    printf 'dcc-statusline: jq is not on PATH\n'
    return 0
  fi

  dcc_config_path
  dcc_config_key
  dcc_claude_json_path
  dcc_parse_all "$input" "$DCC_CONFIG_PATH" "$DCC_CLAUDE_JSON" || return 0

  # Tests freeze the clock; %(%s)T is a bash builtin, so this costs no fork.
  [ -n "${DCC_NOW:-}" ] || printf -v DCC_NOW '%(%s)T' -1

  # Collect git state only when a git segment is actually configured.
  case " $DCC_LINE1 $DCC_LINE2 " in
    *" git "*|*" dir "*) dcc_git_collect "$P_CWD" || true ;;
  esac

  dcc_join_reset
  for name in $DCC_LINE1; do
    dcc_segment "$name"
    dcc_join_add "$DCC_SEG_SPEC" "$DCC_SEG_TEXT"
  done
  [ "$DCC_CONFIG_BAD" -eq 1 ] && dcc_join_add "red bold" "cfg?"
  [ -n "$DCC_JOINED" ] && printf '%s\n' "$DCC_JOINED"

  dcc_join_reset
  for name in $DCC_LINE2; do
    dcc_segment "$name"
    dcc_join_add "$DCC_SEG_SPEC" "$DCC_SEG_TEXT"
  done
  [ -n "$DCC_JOINED" ] && printf '%s\n' "$DCC_JOINED"

  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  dcc_main
fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/e2e.test.sh`
Expected: PASS — the summary line ends `0 failed`, exit status 0

- [ ] **Step 5: Verify the process budget**

Run: `printf '' | strace -f -c -e trace=execve bash plugins/dcc-statusline/scripts/statusline.sh 2>/dev/null || echo "strace unavailable — count manually"`

If `strace` is unavailable, which it will be under Git Bash, instead confirm by reading: the only external commands reachable from `dcc_main` are `jq` (once in `dcc_parse_all`, twice only when the config is malformed), and `git` with its `timeout` wrapper (twice in `dcc_git_collect`). Record the finding in the commit message.

- [ ] **Step 6: Run the whole suite**

Run: `bash plugins/dcc-statusline/tests/run-all.sh`
Expected: every file reports `0 failed`, exit status 0

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-statusline
git commit -m "feat(statusline): add entry script and end-to-end tests"
```

---

### Task 7: Install, uninstall, and version sync

**Files:**
- Create: `plugins/dcc-statusline/scripts/install.sh`
- Create: `plugins/dcc-statusline/scripts/sync.sh`
- Create: `plugins/dcc-statusline/hooks/hooks.json`
- Test: `plugins/dcc-statusline/tests/install.test.sh`

**Interfaces:**
- Consumes: `scripts/VERSION` from Task 1.
- Produces: `install.sh` accepting `install`, `uninstall`, `status`, and `doctor`, each with an optional `--all`. `DCC_STATUSLINE_HOME` overrides the install destination and `DCC_FAKE_HOME` overrides the home searched for account directories, both for tests. `dcc_account_dirs` prints one qualifying directory per line. `dcc_install_one <dir>` and `dcc_uninstall_one <dir>` edit that directory's `settings.json`.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/install.test.sh`:

```bash
#!/usr/bin/env bash
# Install writes the statusLine entry into an account's settings.json and nothing
# else. Account discovery must reject directories that have a settings.json but
# no account -- ~/.claude-mem is a real example on the author's machine: it is the
# claude-mem tool's database directory, not a Claude account.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/install.sh"

fake="$(mktemp -d)"
export DCC_FAKE_HOME="$fake"
export DCC_STATUSLINE_HOME="$fake/.claude/dcc-statusline"

# Two real accounts, one lookalike tool directory, one directory with no settings.
mkdir -p "$fake/.claude" "$fake/.claude-alt" "$fake/.claude-mem" "$fake/.claude-empty"
printf '{"permissions":{"allow":[]}}\n' > "$fake/.claude/settings.json"
printf '{"permissions":{"allow":[]}}\n' > "$fake/.claude-alt/settings.json"
printf '{"observer":true}\n'            > "$fake/.claude-mem/settings.json"
printf '{"oauthAccount":{"emailAddress":"main@example.com"}}\n' > "$fake/.claude.json"
printf '{"oauthAccount":{"emailAddress":"alt@example.com"}}\n'  > "$fake/.claude-alt/.claude.json"

got="$(dcc_account_dirs | sed "s#^$fake/##" | sort | tr '\n' ' ')"
check "discovery finds both accounts and rejects the rest" "$got" ".claude .claude-alt "

# --- install ------------------------------------------------------------------
dcc_install_one "$fake/.claude-alt"
check "install writes the command" \
  "$(jq -r '.statusLine.command' "$fake/.claude-alt/settings.json")" \
  "bash ~/.claude/dcc-statusline/statusline.sh"
check "install sets a refresh interval" \
  "$(jq -r '.statusLine.refreshInterval' "$fake/.claude-alt/settings.json")" "60"
check "install preserves existing keys" \
  "$(jq -r '.permissions.allow | length' "$fake/.claude-alt/settings.json")" "0"

# --- uninstall is a clean inverse --------------------------------------------
before="$(cat "$fake/.claude/settings.json")"
dcc_install_one "$fake/.claude"
dcc_uninstall_one "$fake/.claude"
after="$(jq -S . "$fake/.claude/settings.json")"
check "uninstall removes the entry" \
  "$(jq -r 'has("statusLine")' "$fake/.claude/settings.json")" "false"
check "install then uninstall restores the content" \
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

rm -rf "$fake" "$src"
finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/install.test.sh`
Expected: FAIL — `scripts/install.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

Create `plugins/dcc-statusline/scripts/install.sh`:

```bash
#!/usr/bin/env bash
# Installs the statusLine entry into a Claude account's settings.json. A plugin
# cannot register a statusLine itself -- plugin settings.json supports only the
# agent and subagentStatusLine keys -- so the entry has to live in user settings.
#
# The command written points at a stable copy outside the versioned plugin cache,
# because ${CLAUDE_PLUGIN_ROOT} changes on every plugin update.
set -uo pipefail

DCC_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DCC_HOME_DIR="${DCC_FAKE_HOME:-$HOME}"
DCC_DEST="${DCC_STATUSLINE_HOME:-$DCC_HOME_DIR/.claude/dcc-statusline}"
DCC_COMMAND="bash ~/.claude/dcc-statusline/statusline.sh"

dcc_account_dirs() { # prints each qualifying account config dir, one per line
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
  mkdir -p "$DCC_DEST" || return 1
  cp -R "$DCC_SRC_DIR/." "$DCC_DEST/" 2>/dev/null || return 1
  # install.sh and sync.sh are plugin-side entry points; the copy only needs the
  # render path, but copying everything keeps VERSION comparison trivial.
  return 0
}

_dcc_edit_settings() { # _dcc_edit_settings <dir> <jq-program>
  local dir="$1" prog="$2" settings="$dir/settings.json" tmp
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
  if [ "${1:-}" = "--all" ]; then
    dcc_account_dirs
  else
    printf '%s\n' "${CLAUDE_CONFIG_DIR:-$DCC_HOME_DIR/.claude}"
  fi
}

dcc_doctor() {
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
```

Create `plugins/dcc-statusline/scripts/sync.sh`:

```bash
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
```

Create `plugins/dcc-statusline/hooks/hooks.json`:

```json
{
  "description": "Keeps the installed dcc-statusline scripts in sync with the plugin version.",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh\"",
            "async": true
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/install.test.sh`
Expected: PASS — the summary line ends `0 failed`, exit status 0

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline
git commit -m "feat(statusline): add install, uninstall, and sync hook"
```

---

### Task 8: Slash command, README, and registration

**Files:**
- Create: `plugins/dcc-statusline/commands/dcc-statusline.md`
- Create: `plugins/dcc-statusline/README.md`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: `install.sh` from Task 7.
- Produces: the `/dcc-statusline` command and a marketplace entry named `dcc-statusline`.

- [ ] **Step 1: Write the command**

Create `plugins/dcc-statusline/commands/dcc-statusline.md`:

```markdown
---
description: Install, remove, or diagnose the dcc-statusline status line
argument-hint: "[install|uninstall|status|doctor] [--all]"
allowed-tools: Bash, Read, Edit
---

You manage the **dcc-statusline** plugin. The engine lives at
`${CLAUDE_PLUGIN_ROOT}/scripts/`, the installed copy at `~/.claude/dcc-statusline/`,
and the shared config at `~/.claude/dcc-statusline.json`.

A plugin cannot register a status line on its own: plugin `settings.json` supports
only the `agent` and `subagentStatusLine` keys. That is why installing writes a
`statusLine` entry into the account's own `settings.json`.

Interpret `$ARGUMENTS` as the subcommand, defaulting to `status`. Pass `--all`
through when the user supplies it.

## `install`
Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" install $ARGUMENTS`.

It copies the scripts to `~/.claude/dcc-statusline/`, seeds a default config if
none exists, and writes the `statusLine` entry into the active account, or into
every account when `--all` is given. Report which directories it touched.

Then tell the user two things: the status line appears on the next session start,
and each Claude account needs its own install unless they used `--all`.

If they have more than one account, offer to add per-account tint colors to
`~/.claude/dcc-statusline.json`. Read the file, then Edit the `accounts` object,
keyed by the config directory in `~/...` form, for example
`"~/.claude-alt": { "color": "magenta" }`. Valid colors are `black`, `red`,
`green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, `orange`, `gray`, or a
256-color number.

## `uninstall`
Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" uninstall $ARGUMENTS`.
This removes only the `statusLine` key. The config and the copied scripts stay,
so a later `install` restores the previous appearance. Say so.

## `status`
Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" status` and relay which
accounts have it installed, plus the installed and plugin script versions. If
they differ, mention that a new session applies the update automatically through
the sync hook.

## `doctor`
Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" doctor` and relay the
results verbatim. If `jq` is missing, say the status line cannot run without it
and that on Windows it comes from a separate `jq` install alongside Git for
Windows. If the config fails to parse, offer to show the file and fix it.

## Preview
To show the user what their line looks like right now, pipe a payload through the
installed script:

```bash
printf '%s' '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus"},"cost":{"total_cost_usd":1.2},"context_window":{"used_percentage":47,"total_input_tokens":94210},"rate_limits":{"five_hour":{"used_percentage":23,"resets_at":'"$(( $(date +%s) + 13200 ))"'},"seven_day":{"used_percentage":41,"resets_at":'"$(( $(date +%s) + 500000 ))"'}}}' | bash ~/.claude/dcc-statusline/statusline.sh
```
```

- [ ] **Step 2: Write the README**

Create `plugins/dcc-statusline/README.md`:

```markdown
# dcc-statusline

A two-line Claude Code status line, built for machines running several Claude
accounts side by side.

```
plugins/dcc-statusline  main* ↑2↓1 ●3 ○1 ?2  ·  Opus  ·  xhigh  ·  fast  ·  you@example.com
ctx [█████░░░░░] 47% (94k)  ·  $1.20  ·  5h [██░░░░░░] 23% (4h13m)  ·  7d [████░░░░] 41% (5d19h)
```

The first line is tinted in the color you assign to that account, so a terminal's
identity is obvious at a glance. The meters on the second line ignore that tint
and take their color from the reading itself: green below 50%, yellow to 74%,
orange to 89%, then red and bold at 90% and above.

## Requirements

`bash`, `jq`, and `git`. On Windows these come from Git for Windows plus a
separate `jq` install. Claude Code runs status lines through Git Bash when it is
present.

## Install

```
/dcc-statusline install        # the account you are running now
/dcc-statusline install --all  # every account on this machine
```

Installing copies the scripts to `~/.claude/dcc-statusline/` and adds a
`statusLine` entry to that account's `settings.json`. The copy exists because
plugin directories are versioned and move on every update; a `SessionStart` hook
re-copies the tree when the version changes, so the entry never breaks.

## Configuration

`~/.claude/dcc-statusline.json`, shared by every account. Delete it to return to
defaults.

| Key | Meaning |
|-----|---------|
| `lines` | Two arrays of segment names, in render order |
| `separator` | String placed between segments |
| `meters.width` | Bar width per meter, keyed `ctx`, `5h`, `7d` |
| `meters.showEta` | Show the reset countdown |
| `meters.showTokens` | Show the token count on the context meter |
| `meters.ramp` | Color stops, each `{ "at": <pct>, "color": <name>, "bold": <bool> }` |
| `accounts` | Config directory in `~/...` form to `{ "color": <name> }` |
| `glyphs` | `filled`, `empty`, and `dirty` characters |

Segment names: `dir`, `git`, `model`, `effort`, `fast`, `think`, `agent`,
`style`, `account`, `ctx`, `cost`, `5h`, `7d`. Unknown names are ignored.

Colors: `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`,
`orange`, `gray`, or a 256-color number.

## Design notes

Everything shown comes from the payload Claude Code already sends, so there is no
network call, no credential access, and no cache. Rate limits arrive as
`rate_limits.five_hour` and `rate_limits.seven_day` and are absent until the
first API response of a session, which is why the usage meters can be missing
briefly after `/clear`.

A render costs five processes: one `jq` that parses the payload, the config, and
the account file together, and two `git` calls with their timeout wrappers. Bash
functions return values through global out-variables rather than command
substitution, because each fork costs roughly 10-20ms under MSYS2.

Any segment lacking data renders as nothing and its separators disappear with it,
so a missing block shortens the line instead of breaking it.

## Troubleshooting

Run `/dcc-statusline doctor`. It checks `jq` and `git`, whether the installed copy
matches the plugin version, whether the config parses, and which accounts have the
entry.
```

- [ ] **Step 3: Register in the marketplace**

Modify `.claude-plugin/marketplace.json`, adding this object to the end of the `plugins` array:

```json
    {
      "name": "dcc-statusline",
      "source": "./plugins/dcc-statusline",
      "description": "A two-line status line: git detail, model and session state, plus context and rate-limit meters colored by usage level, with the line tinted by which Claude account the session belongs to.",
      "category": "productivity",
      "keywords": ["statusline", "status-line", "multi-account", "rate-limits", "context-window"]
    }
```

- [ ] **Step 4: Validate the manifests**

Run: `claude plugin validate .`
Expected: passes with no errors, the same check CI runs per `CLAUDE.md`

- [ ] **Step 5: Run the whole suite**

Run: `bash plugins/dcc-statusline/tests/run-all.sh`
Expected: every file reports `0 failed`, exit status 0

- [ ] **Step 6: Install and verify against a live session**

Run: `bash plugins/dcc-statusline/scripts/install.sh install`

Then confirm the entry landed and the script renders:

```bash
jq '.statusLine' ~/.claude/settings.json
printf '%s' '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus"},"cost":{"total_cost_usd":1.2},"context_window":{"used_percentage":47,"total_input_tokens":94210}}' | bash ~/.claude/dcc-statusline/statusline.sh
```

Expected: the `statusLine` object prints, and the command prints two colored
lines. If the account tint is absent, that is expected until an `accounts` entry
exists for this config directory.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-statusline .claude-plugin/marketplace.json
git commit -m "feat(statusline): add command, docs, and registration"
```

---

## Verification checklist

Before declaring the plugin done, confirm each item and report the actual output:

- [ ] `bash plugins/dcc-statusline/tests/run-all.sh` exits 0
- [ ] `claude plugin validate .` passes
- [ ] The rendered line appears in a new Claude Code session
- [ ] `/dcc-statusline doctor` reports no FAIL lines
- [ ] A second account installed with `--all` shows its own tint color
- [ ] `~/.claude-mem` did **not** receive a `statusLine` entry
