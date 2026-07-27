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
