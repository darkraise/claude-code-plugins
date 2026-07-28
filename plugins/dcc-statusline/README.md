# dcc-statusline

A Claude Code status line with an account-colored frame, built for machines
running several Claude accounts side by side.

```
╭─  you@example.com ───────────────────────────────────────────────────────╮
│  plugins/dcc-statusline  ·   main* ↑2 ?2  ·   Opus  ·  xhigh  ·    │
│  ctx ▰▰▰▰▰▱▱▱▱▱ 47% · 94k  ·   1.20  ·   5h ▰▰▱▱▱▱▱▱ 23% · 3h40m     │
╰────────────────────────────────────────────────────────────────────────────╯
```

Colour follows two rules. The frame takes the colour you assign to the account,
so a terminal is identifiable from its border alone. Inside the frame, colour
says what kind of thing a section is — blue for the path, magenta for the
branch, cyan for the model, violet for cost — while the meters keep the usage
ramp: green below 50%, yellow to 74%, orange to 89%, then red and bold at 90%
and above.

Within every section, three weights separate what leads from what supports. The
leaf directory, branch name, model, percentage, and cost figure are bold; icons,
effort and meter labels are plain; the parent path, separators, git counters and
units are dimmed.

The frame needs to know the terminal width, which Claude Code supplies in
`COLUMNS`. When that is missing, non-numeric, or narrower than 48 columns, the
status line falls back to two unframed lines rather than drawing a box it cannot
close.

Text pulled from the payload — the directory, branch, model, and email — is
measured in characters, not terminal cells. ASCII and the plugin's own glyphs
are measured correctly, but a directory or branch name containing double-width
characters such as East Asian text or emoji will make the frame's right edge
sit short. Setting `frame` to `none` avoids it.

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
| `frame` | `auto`, `box`, or `none`; `box` currently behaves the same as `auto`, framing when `COLUMNS` allows |
| `icons.mode` | `auto`, `nerd`, or `unicode`; `auto` uses the detected value |
| `icons.width` | Cells an icon occupies, `1` or `2`; omit to use detection |
| `palette` | Section name to colour: `dir`, `git`, `model`, `effort`, `fast`, `cost`, `mute` |

Segment names: `dir`, `git`, `model`, `effort`, `fast`, `agent`, `style`,
`account`, `ctx`, `cost`, `5h`, `7d`. Unknown names are ignored.

Colors: `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`,
`orange`, `gray`, or a 256-color number.

## Icons

Nerd Font glyphs are used when a Nerd Font is available and words are used when
it is not. Detection runs at install time and again whenever the plugin updates,
never during a render — the render path budgets five processes and cannot afford
to probe fonts.

The probe reads the terminal's own configured font face first, because that
names the font actually doing the rendering. Only when that cannot be read does
it fall back to scanning installed fonts, since a Nerd Font being installed does
not mean your terminal uses it.

Icon width matters: a font named "Nerd Font" draws icons at two cells, while its
"Nerd Font Mono" variant draws them at one. Getting this wrong shifts the box's
right edge by one cell per icon. Set `icons.width` if the detected value is
wrong, and run `/dcc-statusline doctor` to see what was detected.

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
