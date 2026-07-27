# dcc-statusline

A two-line Claude Code status line, built for machines running several Claude
accounts side by side.

```
plugins/dcc-statusline  main* ↑2↓1 ●3 ○1 ?2  ·  Opus  ·  xhigh  ·  fast  ·  you@example.com
ctx [█████░░░░░] 47% (94k)  ·  $1.20  ·  5h [██░░░░░░] 23% (4h13m)  ·  7d [████░░░░] 41% (5d19h)
```

Color follows one rule: the meters take the usage ramp, and everything else takes
the color you assign to the account. So the ramp paints `ctx`, `5h`, and `7d` by
the reading itself — green below 50%, yellow to 74%, orange to 89%, then red and
bold at 90% and above — while every other chip and every separator on both lines
carries the account tint, making a terminal's identity obvious at a glance.

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

The edit goes through `jq`, which rewrites the whole file, so `settings.json`
comes back formatted with two-space indentation. Its contents are preserved;
only the layout is normalized. Uninstalling removes the `statusLine` key and
leaves everything else as it was.

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
matches the plugin version, whether the config parses, whether the account you are
running now has a matching `accounts` entry, whether a fixture payload still
renders, and which accounts have the entry.

The `accounts` check is the one to read when a tint does not appear: it prints the
key the plugin resolved for the current `CLAUDE_CONFIG_DIR`, which is what your
`accounts` map has to be keyed on. Windows spellings (`C:\Users\you\.claude-alt`,
`C:/Users/you/.claude-alt`) and the Git Bash spelling (`/c/Users/you/.claude-alt`)
all resolve to the same `~/.claude-alt` key, so write the `~` form.
