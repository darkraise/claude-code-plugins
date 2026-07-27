# dcc-statusline — Design

Date: 2026-07-27
Status: DRAFT — awaiting user review

## Goal

Ship a Claude Code status line as a plugin in this marketplace: a two-line,
config-driven status line that reads everything it needs from the payload Claude
Code already provides, colors its meters by usage level, and identifies which of
several Claude accounts a session is running under.

It replaces a hand-maintained `~/.claude/statusline.sh` that was removed on
2026-07-27, and it takes its feature set from `ccstatusline` without taking its
architecture.

## The gap this fills

`ccstatusline` is a mature npm package with roughly 88 widgets, a Powerline
renderer, and an Ink TUI configurator. Three things make it a poor fit here:

1. **It is not a plugin.** It installs through `npx`/`bunx` and configures itself
   through its own TUI, so it sits outside this marketplace entirely.
2. **Most of its complexity is now unnecessary.** It reads OAuth credentials and
   calls the Anthropic usage API because it wants per-model weekly buckets.
   Claude Code now feeds `rate_limits` directly into the status line payload, so
   the usage display needs no network, no credential access, no disk cache, and
   no lock files.
3. **Its account handling stops at reading an email.** With four config
   directories in daily use, the useful thing is not the address — it is being
   able to tell at a glance which account a terminal belongs to.

What is worth taking from it: the widget catalog as a menu of what is possible,
the meter idea, and `CLAUDE_CONFIG_DIR`-aware path resolution.

## Verified platform facts

Confirmed against the Claude Code documentation or observed directly on
2026-07-27. These are load-bearing; re-verify before changing anything resting on
them.

| Fact | Source |
|------|--------|
| A plugin's `settings.json` supports only the `agent` and `subagentStatusLine` keys, so a plugin **cannot** register the main `statusLine` | Plugins reference, file locations table |
| `statusLine` accepts `type`, `command`, `padding`, `refreshInterval` (minimum 1), and `hideVimModeIndicator` | Status line doc, manual configuration |
| A status line may print multiple lines | Status line doc, display multiple lines |
| The payload carries `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`, with `resets_at` as Unix epoch **seconds** | Status line doc, available data |
| `rate_limits` appears only for Pro/Max accounts and only after the first API response; each window may be independently absent | Status line doc, fields that may be absent |
| `context_window.used_percentage` may be `null` early in a session; `current_usage` is `null` before the first API call and again after `/compact` | Status line doc, fields that may be null |
| The payload also carries `effort.level`, `thinking.enabled`, `fast_mode`, `output_style.name`, and `agent.name` | Status line doc, available data |
| On Windows, Claude Code runs the status line through Git Bash when installed, and PowerShell otherwise | Status line doc, Windows configuration |
| Git Bash consumes unquoted backslashes as escapes, so the `command` string must use forward slashes or `~` | Status line doc, Windows configuration |
| `${CLAUDE_PLUGIN_ROOT}` changes on every plugin update; the previous version's directory lingers about two weeks | Plugins reference, environment variables |
| Plugin cache paths embed the version | Observed: `superpowers/6.1.1` and `6.2.0` both present on disk |
| A `SessionStart` hook comparing a file between `${CLAUDE_PLUGIN_ROOT}` and persistent storage, then re-copying, is the documented idiom for surviving updates | Plugins reference, dependency install example |
| `git status --porcelain=v2 --branch` returns branch, upstream ahead/behind, and per-file staged, unstaged, and untracked state in one invocation | Observed against this repo |
| The account email is `oauthAccount.emailAddress` in `$CLAUDE_CONFIG_DIR/.claude.json` when that variable is set, and `$HOME/.claude.json` otherwise | darkmem bugfix 2026-07-19; re-observed across all config dirs |
| Three accounts are in use: `~/.claude` (quangtc94@gmail.com), `~/.claude-alt` (12520344@gm.uit.edu.vn), `~/.claude-alt2` (senelupin15@gmail.com) | Observed |
| `~/.claude-mem` also has a `settings.json` but is the claude-mem tool's data directory, not an account: it holds a SQLite database and a worker PID file, and has no `.claude.json` | Observed |

One thing deliberately **not** verified: whether `${CLAUDE_PLUGIN_ROOT}` expands
inside a `statusLine.command` in user settings. The documentation describes it as
a substitution for plugin-owned files. The design below never relies on it, so
the answer does not matter.

## Decisions

| Question | Decision | Why |
|----------|----------|-----|
| How much of ccstatusline to port | A curated segment set driven by a JSON config | The full widget engine is a large application; a fixed catalog with toggles covers real use and can be tested exhaustively |
| Implementation language | Bash with a single `jq` parse | Matches `telegram-notify` and the Git Bash routing Claude Code uses on Windows; one `jq` call replaces the ten the old script made |
| Account identification | Full email, with the whole line tinted in that account's color | The tint is what reads at a glance; the email removes any ambiguity about which account it is |
| Warning visibility under tinting | Meters carry their own level color; everything else takes the account tint | Preserves both signals without either drowning the other |
| Meter presentation | Context, 5-hour, and 7-day all render as bar plus percentage, colored by a shared four-stop ramp | Three comparable quantities should read identically |
| Layout | Two lines: identity, then meters | Three bars with countdowns exceed 150 columns on one line and wrap on a split pane |
| Extra segments | Context bar, session state chips, git detail counts | Chosen from the ccstatusline catalog; PR and worktree segments deferred |
| Config location | One shared `~/.claude/dcc-statusline.json`; install targets one account, `--all` targets every discovered directory | One file to edit; adding an account is a two-line change |
| Internal structure | Thin entry script plus sourced libraries, one function per segment | Sourcing costs file reads rather than process spawns, and per-segment fixtures make failure isolation testable |
| Surviving plugin updates | Install copies scripts to `~/.claude/dcc-statusline/`; a `SessionStart` hook re-copies when the version marker differs | Keeps the settings path constant, costs nothing per render, and applies updates without user action |

## Architecture

```
plugins/dcc-statusline/
  .claude-plugin/plugin.json
  scripts/
    statusline.sh          entry: stdin -> single jq parse -> render
    lib/path.sh            fold Windows and MSYS path forms into one namespace
    lib/config.sh          locate, parse, validate, default
    lib/git.sh             one porcelain=v2 call -> branch, ahead/behind, counts
    lib/segments.sh        one function per segment
    lib/render.sh          ramp, tint, bar drawing, joining
    lib/color.sh           named colors -> ANSI
    sync.sh                re-copy the tree when VERSION differs
    install.sh             write/remove the statusLine entry in settings.json
    VERSION                version marker compared by the sync hook
  hooks/hooks.json         SessionStart -> scripts/sync.sh
  commands/dcc-statusline.md
  tests/
    fixtures/*.json        captured payloads incl. degenerate cases
    *.test.sh
  README.md
```

Registered in `.claude-plugin/marketplace.json` as `dcc-statusline`, matching the
repository's `dcc-` prefix convention.

## Data flow

1. Claude Code writes session JSON to the script's stdin.
2. One `jq` call emits every needed field as shell assignments quoted with `@sh`,
   which the entry script evaluates. `@sh` quoting means a directory or session
   name containing quotes cannot break the line.
3. `lib/config.sh` loads `~/.claude/dcc-statusline.json`, falling back to
   built-in defaults.
4. If any git segment is enabled and the directory is inside a repository,
   `lib/git.sh` runs `git status --porcelain=v2 --branch` and
   `git rev-parse --show-toplevel`, both under a one-second timeout.
5. Each configured segment function returns a string or nothing.
6. `lib/render.sh` applies the ramp to meters and the account tint to everything
   else, joins non-empty segments with the separator, and prints two lines.

Two git invocations total, down from three in the old script. The detail counts
cost nothing extra because `porcelain=v2 --branch` already carries them.

## Segment catalog

| Name | Source | Example |
|------|--------|---------|
| `dir` | payload | `claude-code-plugins/plugins` |
| `git` | git | `main* ↑2↓1 ●3 ○1 ?2` |
| `model` | payload | `Opus` |
| `effort` | payload | `xhigh`, omitted when the model reports no effort |
| `fast` | payload | `fast`, only when fast mode is on |
| `think` | payload | `think`, only when thinking is on |
| `agent` | payload | agent name, only under `--agent` |
| `style` | payload | output style, omitted when `default` |
| `account` | `.claude.json` | `12520344@gm.uit.edu.vn` |
| `ctx` | payload | `ctx [█████░░░░░] 47% (94k)` |
| `cost` | payload | `$1.20` |
| `5h` | payload | `5h [██░░░░░░] 23% (4h13m)` |
| `7d` | payload | `7d [████░░░░] 41% (5d19h)` |

Order comes from the config. An unknown name is ignored rather than fatal.

Default layout:

```
plugins/dcc-statusline  main* ↑2↓1 ●3 ○1 ?2  ·  Opus xhigh fast  ·  12520344@gm.uit.edu.vn
ctx [█████░░░░░] 47% (94k)  ·  $1.20  ·  5h [██░░░░░░] 23% (4h13m)  ·  7d [████░░░░] 41% (5d19h)
```

## Rendering rules

**Account tint.** Every segment except a meter renders in the color mapped to the
active config directory. Resolution is `$CLAUDE_CONFIG_DIR` when set, else
`$HOME/.claude`. A directory with no entry falls back to no tint.

**Meter ramp.** Context, 5-hour, and 7-day meters ignore the tint and take their
color from the percentage:

| Range | Color |
|-------|-------|
| below 50% | green |
| 50–74% | yellow |
| 75–89% | orange |
| 90% and above | red, bold |

Both the bar and the number take the color, so the whole meter reads as one unit.
Comparisons are integer, against the truncated percentage.

**Bars.** Drawn with `█` and `░`, defaulting to 10 cells for context and 8 for
each usage window. Fill is `round(pct * width / 100)`, clamped to the range so
1% never shows an empty bar and 99% never shows a full one.

**Countdowns.** `resets_at` minus now, formatted compactly: `5d19h`, `4h13m`,
`45m`, or `now` when non-positive.

**Empty segments.** The renderer joins only non-empty segments and drops the
separators around empty ones, so a segment that fails or has no data yet leaves
no visible gap. A line whose segments are all empty is omitted entirely rather
than printed as a bare separator or a blank row, so a fresh session with no
`rate_limits` and no context data yet shows one line, not one line and a gap.

## Configuration

`~/.claude/dcc-statusline.json`, shared by every account. Absent means defaults.

```json
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
  "accounts": {
    "~/.claude":      { "color": "green" },
    "~/.claude-alt":  { "color": "magenta" },
    "~/.claude-alt2": { "color": "cyan" }
  },
  "glyphs": { "filled": "█", "empty": "░", "dirty": "*" }
}
```

Colors are named and resolved through `lib/color.sh` to 256-color codes, because
orange has no basic-8 equivalent. Ramp stops are sorted by `at` at load time, so
an out-of-order config still behaves.

## The slash command

`/dcc-statusline <subcommand>`, delegating to `scripts/install.sh`:

| Subcommand | Behavior |
|------------|----------|
| `install` | Copy scripts to `~/.claude/dcc-statusline/`, write the `statusLine` entry into the active account's `settings.json`, and create a default config if none exists |
| `install --all` | The same for every account directory found under `$HOME`. A directory qualifies only if it contains **both** a `settings.json` and a `.claude.json` carrying an `oauthAccount.emailAddress`, which excludes tool directories such as `~/.claude-mem`. For `~/.claude` the `.claude.json` lives at `$HOME/.claude.json` instead |
| `uninstall [--all]` | Remove the `statusLine` entry; leave the config and the copied scripts alone |
| `status` | Print which directories have the entry installed and which version each holds |
| `doctor` | Check `jq` and `git` are present, the copy matches the plugin version, the config parses, the active directory has an account entry, and a render against a fixture succeeds |

The entry written is:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/dcc-statusline/statusline.sh",
    "padding": 0,
    "refreshInterval": 60
  }
}
```

`refreshInterval` is set because the countdowns are time-based and would
otherwise freeze while a session sits idle. The path uses `~` and forward slashes
for Git Bash. Edits go through `jq` into a temporary file that is then moved into
place, so an interrupted write cannot truncate `settings.json`.

## Surviving plugin updates

`hooks/hooks.json` registers a `SessionStart` hook running `scripts/sync.sh`,
which compares `${CLAUDE_PLUGIN_ROOT}/scripts/VERSION` against
`~/.claude/dcc-statusline/VERSION` and re-copies the script directory when they
differ. Identical versions cost one `cmp` per session start. The settings entry
never changes, so no account's status line breaks on update.

## Error handling

Failures degrade in layers rather than taking the line down.

| Condition | Behavior |
|-----------|----------|
| Config file absent | Built-in defaults, silently |
| Config file malformed | Defaults, plus a `cfg?` marker appended to line one |
| `rate_limits` absent | The `5h` and `7d` segments render nothing |
| `used_percentage` null | The `ctx` meter renders nothing |
| Not a git repository, or git absent | The `git` segment renders nothing |
| A git call exceeds one second | Treated as no git data |
| `.claude.json` unreadable or without an email | The `account` segment renders nothing; the tint still applies |
| Config directory has no account entry | No tint; everything else renders |
| `jq` missing | A single plain line naming the missing dependency — the one loud case |

## Testing

Shell tests following the pattern in `plugins/telegram-notify/tests/`, each
feeding a fixture on stdin and asserting exact output with ANSI codes stripped.

Fixtures cover a normal session, a session with no `rate_limits` block as happens
right after `/clear`, a null `used_percentage`, a detached HEAD, a directory
outside any repository, an unknown config directory, and a malformed config.

Dedicated assertions:

- Ramp boundaries at 49, 50, 74, 75, 89, and 90 percent produce the expected color.
- Bar fill clamps: 1 percent shows one filled cell, 99 percent shows one empty cell.
- A failing segment produces no doubled separator.
- Tint applies to non-meter segments and never to meters.
- Countdown formatting across the day, hour, minute, and elapsed cases.
- `install` followed by `uninstall` leaves `settings.json` semantically identical
  apart from the `statusLine` key. Byte equality is not offered: the edit runs
  through `jq --indent 2`, which rewrites the whole document, so a four-space
  file comes back two-space and inline arrays are expanded.

## Out of scope

Powerline separators and themes, the interactive configurator, per-model weekly
usage buckets (which would require the Anthropic API and credential access),
token throughput metrics (which would require parsing the transcript on every
render), and PR, worktree, and jj segments. The PR and worktree data sit in the
payload already, so those remain cheap to add later if wanted.
