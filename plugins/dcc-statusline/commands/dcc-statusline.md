---
description: Install, remove, or diagnose the dcc-statusline status line
argument-hint: "[install|uninstall|status|doctor|preview|config] [--all]"
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

## `preview`
Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/preview.sh" $ARGUMENTS`.

It renders the user's real config against a sample payload at 48, 60, 80, 120 and
200 columns, labelling each block with the width and the tier each line settled
on. Relay the output verbatim inside a fenced block — reformatting it destroys
the alignment that is the entire point.

Accepts `--width N` for a single width, `--theme NAME` to try a theme without
editing the config, and `--config PATH` for a file that is not installed.

If every block reports `tier 0`, the terminal is wide enough that nothing shrinks;
say so rather than leaving the user to wonder whether the feature works.

## `config`
Guided setup. Do not run a script for this one.

1. Read `~/.claude/dcc-statusline.json`, or note that it does not exist yet.
2. Ask which theme they want: `default`, `minimal`, `mono`, or `vivid`.
3. Ask which segments belong on each of the two lines. Valid names are `dir`,
   `git`, `model`, `effort`, `fast`, `agent`, `style`, `account`, `ctx`, `cost`,
   `5h`, `7d`, `time`.
4. If they run more than one Claude account, ask for a frame colour per account
   and write it under `accounts`, keyed by config directory in `~/...` form.
5. Edit the file, keeping the `$schema` key at the top if present.
6. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/preview.sh"` and show the result.

Ask one question at a time. Never overwrite a key the user did not ask you to
change.
