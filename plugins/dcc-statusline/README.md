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
repository name, branch name, model, percentage, and cost figure are bold;
icons, effort, meter labels, the path inside the repository and the git counters
are plain; the path leading to the repository, separators and units are dimmed.
The counters stay at plain weight on purpose — dimmed against a dark background
a saturated hue turns muddy and the numbers stop being readable, which defeats
the point of showing them.

The path reads in those three tones so your eye lands in the same place at any
depth. What leads to the repository recedes, the repository name is the anchor,
and where you are inside it reads plainly:

```
/d/Repositories/Personal/claude-code-plugins/plugins/dcc-statusline
└──────── dim ──────────┘└────── bold ─────┘└───────── plain ─────┘
```

Outside a repository the same rule applies with the containing directory dimmed
and the current one bold.

The reasoning effort is coloured by level — grey, blue, cyan, violet, magenta as
it rises — on a progression that deliberately avoids the green-through-red the
meters use. Sharing those hues would let one colour mean two things on the same
line: near a limit, or simply set to `max`. Override any of them under
`palette.effortLevels`.

The frame needs to know the terminal width, which Claude Code supplies in
`COLUMNS`. When that is missing, non-numeric, or narrower than 48 columns, the
status line falls back to two unframed lines rather than drawing a box it cannot
close.

## Width

When a line does not fit, its segments shrink rather than disappearing. The whole
line steps down one tier at a time until it fits: the path drops its ancestry,
then elides its middle, then falls back to the leaf; the branch drops its
counters and then truncates; the model shortens to its first word; the meters
narrow their bars, drop the token count and reset countdown, and finally show the
percentage alone.

Tiers are chosen by what fits, not from a width table, so there is nothing to
tune when a branch name gets longer. Only if the most compact rendering still
overflows are whole segments dropped, which is the behaviour every width used to
get.

```json
{ "responsive": { "maxTier": 0 } }
```

`maxTier` caps the escalation, and accepts only `0`, `1`, `2`, or `3`; any other
value — including a negative number or one above `3` — falls back to `3`. Zero
disables shrinking entirely and restores segment-dropping at every width.

A meter narrower than two cells shows no bar at all, at every width including
the widest. One cell cannot show both a filled and an empty state — the bar
would read as empty at any figure below 100% — so the percentage carries the
reading alone. This is the one place where the widest rendering is not simply
the fullest one.

Run `/dcc-statusline preview` to see your own config at five widths side by
side. A block too narrow to frame is labelled `unframed` rather than given a
tier: with no frame there is no width budget, and nothing shrinks.

## Themes

`theme` selects a preset, merged between the built-in defaults and your own file,
so any key you set yourself still wins.

| Theme | Look |
|-------|------|
| `default` | The appearance described above |
| `minimal` | No frame, no icons, percentages without bars |
| `mono` | No hue; the three weights carry the hierarchy alone |
| `vivid` | High contrast, bold throughout |

`COLUMNS` reports the terminal, but the region the host draws the status line
into can be slightly narrower, and a box drawn to the full width has its right
wall clipped. So the frame is held back by `frameMargin` cells, four by default:
two for a left indent the host adds, two so the final cell is never written.
Raise it if the right edge still clips, or set it to `0` to use the full width.

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
| `separator` | String placed between segments, or a two-element array giving each line its own; a shorter array reuses its last element for the missing line, and an empty array falls back to the default |
| `theme` | `default`, `minimal`, `mono`, or `vivid` |
| `responsive.maxTier` | Cap on shrinking, `0`–`3`; default `3`; any other value falls back to `3` |
| `meters.width` | Bar width per meter, keyed `ctx`, `5h`, `7d`; values under `2` drop the bar entirely |
| `meters.showEta` | Show the reset countdown |
| `meters.showTokens` | Show the token count on the context meter |
| `meters.ramp` | Color stops, each `{ "at": <pct>, "color": <name>, "bold": <bool> }` |
| `accounts` | Config directory in `~/...` form to `{ "color": <name> }` |
| `glyphs` | `filled`, `empty`, and `dirty` characters |
| `frame` | `auto`, `box`, or `none`; `box` currently behaves the same as `auto`, framing when `COLUMNS` allows |
| `frameMargin` | Cells to hold the box back from the reported terminal width; default `4` |
| `icons.mode` | `auto`, `nerd`, or `unicode`; `auto` uses the detected value |
| `icons.width` | Cells an icon occupies, `1` or `2`; omit to use detection |
| `palette` | Section name to colour: `dir`, `git`, `model`, `effort`, `fast`, `cost`, `mute` |
| `palette.effortLevels` | Colour per reasoning effort: `low`, `medium`, `high`, `xhigh`, `max` |
| `segments.dir.style` | `full`, `repo`, or `leaf`; pins how the path renders |
| `segments.git.counters` | Show the ahead/behind/staged counts; default true |
| `segments.git.maxBranch` | Truncate the branch name; `0` means no limit |
| `segments.model.short` | Always show the first word of the model name |
| `segments.ctx.label` | Label text for a meter, likewise `5h` and `7d` |

Segment names: `dir`, `git`, `model`, `effort`, `fast`, `agent`, `style`,
`account`, `ctx`, `cost`, `5h`, `7d`, `time`. Unknown names are ignored.

Colors: `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`,
`orange`, `gray`, or a 256-color number.

## Icons

Nerd Font glyphs are used when a Nerd Font is available and words are used when
it is not. Detection runs at install time and again whenever the plugin updates,
never during a render — the render path budgets five processes and cannot afford
to probe fonts.

Detection is deliberately conservative: icons are enabled only when the probe
can identify the terminal it is running in and read that terminal's configured
font. On Windows that means Windows Terminal, confirmed by `WT_SESSION`. Any
host it cannot identify gets words.

Scanning the machine's installed fonts is not treated as evidence. Having a Nerd
Font installed never proved the terminal was using it, and trusting that turned
every icon into a `?` on a host that was not Windows Terminal. The two mistakes
are not equally cheap — guessing icons wrong makes the line unreadable, guessing
words wrong only costs some polish — so an unrecognised host gets words and you
turn icons on yourself:

```json
{ "icons": { "mode": "nerd" } }
```

Icon width matters when you do: a font named "Nerd Font" draws icons at two
cells, while its "Nerd Font Mono" variant draws them at one. Getting this wrong
shifts the box's right edge by one cell per icon. Set `icons.width` if the
detected value is wrong, and run `/dcc-statusline doctor` to see what was
detected.

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
matches the plugin version, whether the config parses **and validates** — naming
unknown keys, unrecognised names and enum values, invalid colours, and
out-of-range numbers; a value of the wrong JSON type inside a valid key can
still slip past, which a schema-aware editor catches — whether the account
you are running now has a
matching `accounts` entry, whether a fixture payload still renders, and which
accounts have the entry.

The `accounts` check is the one to read when a tint does not appear: it prints the
key the plugin resolved for the current `CLAUDE_CONFIG_DIR`, which is what your
`accounts` map has to be keyed on. Windows spellings (`C:\Users\you\.claude-alt`,
`C:/Users/you/.claude-alt`) and the Git Bash spelling (`/c/Users/you/.claude-alt`)
all resolve to the same `~/.claude-alt` key, so write the `~` form.
