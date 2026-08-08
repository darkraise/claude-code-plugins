# dcc-telegram-notify: rename and per-event notification config

Date: 2026-08-08
Status: approved

## Problem

The `telegram-notify` plugin has two defects.

First, it violates the marketplace's own naming rule. `CLAUDE.md` requires every
plugin name to start with `dcc-`, and uses `dcc-telegram-notify` as its worked
example, but the directory, the `plugin.json` `name`, and the `marketplace.json`
entry all say `telegram-notify`.

Second, there is no way to choose which events notify you. The three hook events
are hardcoded in `hooks/hooks.json` and the script dispatches on
`hook_event_name` with no gate, so the only off switch is clearing the bot token,
which silences everything. In practice the turn-end `✅ Done` message is the
noisiest and least useful of the set, and there is no way to drop it while
keeping the alerts that mean the session is blocked.

## Goals

1. Rename the plugin to `dcc-telegram-notify` across every surface, including the
   config home, migrating existing installs without user action.
2. Add a `TELEGRAM_EVENTS` config listing which events send a message.
3. Default to the blocked-on-you set only: tool permission prompts, input
   requests, and turns that end on a question.

## Non-goals

- No new notification categories. The token vocabulary describes exactly the
  messages the script already produces.
- No per-project or per-account event sets. One list, global.
- No change to message formatting, topic routing, or LLM summarization.

## Part 1 — Rename

### Surfaces

| Surface | Before | After |
|---|---|---|
| Directory | `plugins/telegram-notify/` | `plugins/dcc-telegram-notify/` |
| `plugin.json` `name` | `telegram-notify` | `dcc-telegram-notify` |
| `plugin.json` `version` | `1.0.0` | `1.1.0` |
| `plugin.json` `homepage` | `.../plugins/telegram-notify` | `.../plugins/dcc-telegram-notify` |
| `marketplace.json` entry | `telegram-notify`, `./plugins/telegram-notify` | `dcc-telegram-notify`, `./plugins/dcc-telegram-notify` |
| Slash command | `commands/telegram-notify.md` → `/telegram-notify` | `commands/dcc-telegram-notify.md` → `/dcc-telegram-notify` |
| Engine script | `scripts/telegram-notify.sh` | `scripts/dcc-telegram-notify.sh` |
| Config/state home | `~/.telegram-notify/` | `~/.dcc-telegram-notify/` |

All moves use `git mv` so history follows the files. `hooks/hooks.json`, the
command body, both existing test files, `README.md`, `DESIGN.md`, and
`telegram.env.example` are updated to reference the new script path and command
name. The root `README.md` and `CLAUDE.md` references are updated too.

### Environment variable names are not prefixed

`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, and the rest keep their names. They
name the Telegram domain, not the plugin, so a `DCC_` prefix would add no
clarity while invalidating every config file already on disk and forcing the
migration to rewrite file contents rather than move a directory.
`TELEGRAM_NOTIFY_HOME` and `TELEGRAM_NOTIFY_ENV` keep their names for the same
reason — only the default value of `TELEGRAM_NOTIFY_HOME` changes.

### Migration

`notify_home()` returns `$h/.dcc-telegram-notify`. Immediately after the home is
resolved and before `seed_config` runs, a `migrate_home()` step moves the old
directory into place. It fires only when all three conditions hold:

- `TELEGRAM_NOTIFY_HOME` is unset — an explicit override is the user's choice and
  must not be second-guessed.
- The new home does not exist.
- The old `$h/.telegram-notify` exists and is a directory.

The move is a single `mv old new`. Because both paths are in the same user home,
this is a `rename(2)` and therefore atomic: hooks fire asynchronously and can run
concurrently, so two processes may race here, but one wins and the other's `mv`
fails harmlessly against an already-existing target. All failures are swallowed —
a notification path must never disturb the session. If the move fails, the new
home is simply seeded fresh with an empty token and the plugin stays silent,
which is the same safe state as a first install.

Token, `topics.json`, `state/`, and `debug.log` all carry over, so an existing
install keeps working with no user action.

## Part 2 — `TELEGRAM_EVENTS`

### Vocabulary

A comma- or whitespace-separated list of tokens, case-insensitive.

| Token | Gates | Emitted by |
|---|---|---|
| `permission` | 🔐 Needs permission — a tool call awaiting approval | `Notification` / `permission_prompt`, tool is not `AskUserQuestion` |
| `input` | ❓ Needs your input and 🔔 Needs you | `Notification` / `permission_prompt` with tool `AskUserQuestion`, and `Notification` / `agent_needs_input` |
| `stop-question` | ❓ Waiting on you | `Stop`, classified kind `question` |
| `stop-done` | ✅ Done | `Stop`, classified kind `work` |
| `stop-reply` | 💬 Replied | `Stop`, classified kind `reply` |

Three aliases expand during parsing: `stop` → the three `stop-*` tokens, `all` →
every token, `none` → the empty set. `none` exists so a user can go silent
without deleting their bot token.

### Default

```
TELEGRAM_EVENTS=permission,input,stop-question
```

Every case where the session is blocked waiting on a human, and nothing else.
This is applied as a shell default (`: "${TELEGRAM_EVENTS:=...}"`) rather than
depending on the seeded config file, so installs that already have a
`telegram.env` inherit it on upgrade.

This is a deliberate behavior change for existing users: `✅ Done` and
`💬 Replied` messages stop arriving unless the user opts back in with
`stop-done` / `stop-reply` or `all`. The README documents it under a short
upgrade note.

### Parsing

One function, `event_enabled <token>`, returning 0 or 1. It normalizes
`TELEGRAM_EVENTS` once at load time into a canonical, space-delimited set held in
a script-level variable:

- lowercase, split on commas and whitespace
- expand `stop`, `all`, `none`
- drop unrecognized tokens

Unrecognized tokens are dropped rather than treated as fatal. A typo must never
be able to take a user's notifications down silently or, worse, crash the hook.
The dropped tokens are retained in a second variable so `status` can report them,
and a `dbg` line records the resolved set on every firing.

`--test` bypasses `event_enabled` entirely. It is an explicit manual send and
must work regardless of the filter, otherwise a user with `none` set has no way
to verify their token.

### Where the gate is applied

`UserPromptSubmit` is never gated. It sends nothing; it only writes the turn-start
timestamp used to compute duration.

In the `Notification` branch, the gate is evaluated after the branch has decided
which of the three statuses applies, immediately before `send_message`. This
costs one `pending_action` transcript read for a suppressed message, which is
local file work and cheap.

The `Stop` branch is gated in two places:

1. An early exit at the top of the branch when none of the three `stop-*` tokens
   is enabled. This skips the transcript read and the LLM classify call entirely,
   so a user who has turned off all turn-end messages pays nothing per turn. The
   start file is still consumed and removed so it cannot accumulate.
2. A check after classification, before `send_message`, since the kind is not
   known until then.

### Known cost

With the default set and `TELEGRAM_LLM_URL` configured, a turn that classifies as
`work` still costs one gateway call before the script decides to stay silent. The
kind is not knowable in advance. This is accepted rather than worked around. Two
things blunt it: the early exit above covers the all-stop-tokens-off case for
free, and when the LLM is disabled — the default — classification falls back to
the local `ends_with_question` heuristic, which costs nothing.

### Config file and status output

`seed_config`'s template gains a `TELEGRAM_EVENTS` block documenting the tokens,
the aliases, and the default. `telegram.env.example` mirrors it, and the README
config reference table gains a row.

The `/dcc-telegram-notify status` flow reports the resolved event set and names
any unrecognized tokens it discarded.

## Testing

A new `tests/events.test.sh` sources the script with `TELEGRAM_NOTIFY_ENV`
pointed at a nonexistent path (the isolation pattern the existing tests already
use) and exercises the parser directly:

- unset `TELEGRAM_EVENTS` yields exactly `permission`, `input`, `stop-question`
- each single token enables only itself
- `stop` expands to the three stop tokens and nothing else
- `all` enables all five; `none` enables nothing
- unknown tokens are dropped, recorded, and do not disturb valid neighbors
- comma, space, and mixed separators parse identically; case is ignored

A new `tests/migration.test.sh` covers `migrate_home()` against a temporary
`HOME`: old home present and new absent migrates and preserves file contents;
both present leaves the new one untouched; neither present is a no-op; an
explicit `TELEGRAM_NOTIFY_HOME` suppresses migration entirely.

`tests/open_editor.test.sh` and `tests/pending_action.test.sh` have their
`SCRIPT` path updated to the renamed file. A new `tests/run-all.sh` runs all
four, following the `dcc-statusline` pattern.

## Verification

- `bash tests/run-all.sh` passes.
- `claude plugin validate .` passes at the repo root.
- `rg -n 'telegram-notify'` across the repo returns only intentional references:
  the new `dcc-` names, the historical mentions inside dated spec and plan
  documents under `docs/`, and the migration shim's own reference to the old
  home.
