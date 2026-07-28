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

It also reports the detected icon mode and icon cell width, printed as
`icons: nerd at 2 cell(s)`. Read that line when glyphs render as empty boxes
(the mode should be `unicode`) or when the box's right edge looks ragged (the
width is likely wrong — set `icons.width` in the config to correct it).

## Preview
To show the user what their line looks like right now, pipe a payload through the
installed script:

```bash
printf '%s' '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus"},"cost":{"total_cost_usd":1.2},"context_window":{"used_percentage":47,"total_input_tokens":94210},"rate_limits":{"five_hour":{"used_percentage":23,"resets_at":'"$(( $(date +%s) + 13200 ))"'},"seven_day":{"used_percentage":41,"resets_at":'"$(( $(date +%s) + 500000 ))"'}}}' | bash ~/.claude/dcc-statusline/statusline.sh
```
