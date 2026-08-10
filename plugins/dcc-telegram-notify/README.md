# dcc-telegram-notify — a Claude Code plugin

Push a Telegram message when a Claude Code session **finishes a turn**, **ends on a
question**, or **needs your attention** (a permission prompt or an agent asking for
input). Works on **Windows, Linux, and macOS**, is **multi-account aware**, and can
optionally summarize each turn with an OpenAI-compatible LLM.

```
📁 my-api · 💻 host · 👤 alt      📁 my-api · 💻 host        📁 my-api · 💻 host
✅ Done · 2m 14s                   ❓ Waiting on you           🔐 Needs permission

<turn summary / lead text>         <the question + options>    ▸ Bash: <command>
```

The header's first line is `📁 project · 💻 machine · 👤 account`, so a notification
tells you at a glance which project, on which host, under which account needs you.
(The account segment is hidden for your default account.)

## Requirements

The hook runs through **bash**, and the script uses `curl` and `jq`. All three must be
on `PATH`:

- **Linux/macOS:** `curl` and `jq` from your package manager (`apt install jq`,
  `brew install jq`, …). bash is already present.
- **Windows:** install **Git for Windows** (provides Git Bash + `curl`) and **jq**
  (`winget install jqlang.jq`). The plugin invokes `bash …`, which resolves to Git
  Bash's `bash.exe` as long as it's on `PATH`.

## Install

This plugin is published in the **darkraise** marketplace. On any machine:

```
/plugin marketplace add darkraise/claude-code-plugins
/plugin install dcc-telegram-notify@darkraise
```

Then configure and test:

```
/dcc-telegram-notify setup
```

That seeds `~/.dcc-telegram-notify/telegram.env`, walks you through pasting your bot token,
helps you find your chat id, and sends a test message. To change settings later, run
`/dcc-telegram-notify edit` to open that config file in your default editor. You can also
re-run `/dcc-telegram-notify test`, `/dcc-telegram-notify discover`, or `/dcc-telegram-notify
status` any time.

### Manual configuration (alternative to `/dcc-telegram-notify setup`)

The first hook firing creates `~/.dcc-telegram-notify/telegram.env` with an empty token
(so notifications stay silent until configured). Open it in your default editor with
`/dcc-telegram-notify edit` (or `bash scripts/dcc-telegram-notify.sh --edit`) and set at least:

```
TELEGRAM_BOT_TOKEN=123456789:AAE...      # from @BotFather
TELEGRAM_CHAT_ID=-1001234567890          # from: bash scripts/dcc-telegram-notify.sh --discover
```

Send a test:

```
bash scripts/dcc-telegram-notify.sh --test
```

## Where things live

Everything the plugin *writes* lives outside the plugin directory, in one per-user
home that all accounts share and that survives plugin updates:

```
~/.dcc-telegram-notify/
├── telegram.env      your token + settings (chmod 600)
├── topics.json       per-project topic map (per-project mode)
├── state/            per-session turn-start timestamps
└── debug.log         only when TELEGRAM_DEBUG=1
```

Override the whole location with `TELEGRAM_NOTIFY_HOME`, or point at a specific config
file with `TELEGRAM_NOTIFY_ENV`.

## Multiple Claude accounts

Each account (each `CLAUDE_CONFIG_DIR`) enables the plugin independently — run the
`/plugin install` line above once per account. Because a plugin registers its own hooks,
you never hand-edit `settings.json`, so there's no shared-file breakage between accounts.

All accounts share the single `~/.dcc-telegram-notify/telegram.env` (one token, one
destination). Messages are told apart by the **account label**, auto-derived from
`CLAUDE_CONFIG_DIR`:

- the **default** account (`~/.claude`, or no `CLAUDE_CONFIG_DIR`) shows **no label**
- `~/.claude-alt` shows `👤 alt`

To customize labels for accounts that share the one config file, set a map:

```
TELEGRAM_ACCOUNT_LABELS={".claude":"main",".claude-alt":"alt"}
```

`TELEGRAM_ACCOUNT_LABEL=<name>` forces one label everywhere (set it empty to hide the
segment). Don't put that in the shared file if you want per-account labels — use the map.

## Which events notify you

`TELEGRAM_EVENTS` is a comma-separated list of the notifications you want. The
default, `permission,input,stop-question`, sends only when the session is
actually blocked waiting on you.

| Token | Fires when | Message |
|-------|-----------|---------|
| `permission` | A tool call is waiting for your approval | 🔐 Needs permission |
| `input` | A question is waiting, or an agent asked for input | ❓ / 🔔 |
| `stop-question` | The turn ended on a question | ❓ Waiting on you |
| `stop-done` | A work turn finished | ✅ Done |
| `stop-reply` | A conversational turn finished | 💬 Replied |

Three aliases expand for you: `stop` is all three `stop-*` tokens, `all` is
everything, and `none` silences the plugin without deleting your bot token.
Unknown tokens are ignored rather than treated as errors, so a typo can't take
your notifications down — `/dcc-telegram-notify status` reports any it dropped.
Setting `TELEGRAM_EVENTS=` to an empty string silences everything too, the same
as `none` — the default above only applies when the variable is left entirely
unset or commented out.

`UserPromptSubmit` is not in the list. It sends nothing; it only starts the
timer that gives turn-end messages their duration.

> **Upgrading from `telegram-notify` 1.0.x?** Two things change. Your config and
> state move from `~/.telegram-notify` to `~/.dcc-telegram-notify` automatically
> on the first hook firing — nothing to do. And `✅ Done` / `💬 Replied` turn-end
> messages stop arriving, because the new default omits them. Set
> `TELEGRAM_EVENTS=all` to get the old behavior back. If notifications go quiet
> after updating, the automatic move can fail silently (a file lock, antivirus,
> or a synced home directory) — check by copying `telegram.env` (and
> `topics.json`, if present) from `~/.telegram-notify/` to
> `~/.dcc-telegram-notify/` yourself.

## Replying from Telegram

Reply to a turn-end notification and the session picks your message up and keeps
working — no need to be at the keyboard. This is off until you list your Telegram
user id: run `/dcc-telegram-notify whoami`, send your bot a message when prompted,
and put the id it prints into `TELEGRAM_ALLOWED_USERS`. Nothing on the read side
does anything until that list is non-empty, and the allowlist is the only thing
standing between "anyone who can post in this chat" and "commands run on this
machine" — a reply is an instruction Claude executes.

> **Read this before you rely on it for unattended work.** A reply arrives through
> the hook channel, and Claude Code marks that channel as *not* user input.
> Continuing, reading, analysing, and answering all work normally, but an
> irreversible action — an edit, a commit, a deploy — may draw a request to
> confirm at the keyboard instead of just running. This does **not** affect
> permission taps below: those return a decision (allow/deny) that the CLI
> honours directly, not text Claude has to decide whether to trust. If you were
> hoping to text "commit and push" from a train and have it happen unattended,
> it may not — plan on confirming irreversible steps yourself.
>
> `AskUserQuestion` cannot be answered from Telegram. Its notification looks like
> any other prompt, but a reply to it is not delivered as a selection — the
> question stays open until you answer at the keyboard.

**At turn end:** when a turn finishes, the notification keeps listening for a
reply for `TELEGRAM_REPLY_WINDOW` seconds. Nothing is blocked during that
window — the turn has already ended, and your terminal is free the whole time.
If you type locally and reply from Telegram both land, whichever arrives first
wins the race; the other is ignored.

**Away mode** gates permission prompts — a tool call waiting for your approval —
behind a Telegram tap instead of sending them straight to the terminal picker.
It does not gate `AskUserQuestion`; see the caveat above. Arm it with
`/dcc-telegram-notify away [duration]` (e.g. `away 2h`; defaults to
`TELEGRAM_AWAY_TTL` with no argument) and disarm it with `/dcc-telegram-notify
back`, or by typing anything locally, which disarms it automatically. It is
**machine-wide** — one flag covers every project and every Claude account
sharing this config home — and it expires on its own after the armed duration,
so a forgotten arming cannot gate sessions indefinitely.

A few gotchas:

- **Bot privacy mode hides bare group messages.** By default a Telegram bot in a
  group only sees messages that start with `/` or are sent as an explicit Reply
  to one of its messages. To have plain replies picked up, either disable
  privacy mode for your bot in @BotFather or always use Telegram's Reply
  function on the notification you're answering.
- **`getUpdates` is exclusive per bot token.** Only one machine may have
  `TELEGRAM_REPLY=on` for a given bot at a time; a second machine polling the
  same token steals updates from the first. Give each machine its own bot if
  you want the read side enabled on more than one.
- **A reply is an instruction Claude executes.** There is no second factor
  beyond the chat itself — `TELEGRAM_ALLOWED_USERS` is the only boundary
  between a message in this chat and a command run on this machine, so keep
  that list tight and keep the bot token private.

## Optional LLM turn summaries

Off by default. Set `TELEGRAM_LLM_URL` to an OpenAI-compatible base URL (and
`TELEGRAM_LLM_API_KEY` if it needs one) to have turn-end messages summarized into 1–2
sentences. If the gateway is unreachable, the notification still sends using the
message's own opening lines — nothing is lost, just less polished.

## Config reference (`~/.dcc-telegram-notify/telegram.env`)

| Variable | Default | Meaning |
|----------|---------|---------|
| `TELEGRAM_BOT_TOKEN` | — | Bot token from @BotFather (required). |
| `TELEGRAM_CHAT_ID` | — | Target chat id (negative for supergroups). |
| `TELEGRAM_TOPIC_ID` | *(empty)* | Forum topic id; empty posts to the main thread. |
| `TELEGRAM_TOPIC_MODE` | `shared` | `shared` or `per-project`. |
| `TELEGRAM_EVENTS` | `permission,input,stop-question` | Which notifications send; see above. |
| `TELEGRAM_ALLOWED_USERS` | *(empty)* | Comma-separated Telegram user ids allowed to reply/tap. Empty = read side off. |
| `TELEGRAM_REPLY` | `on` | Master switch for the read side; `off` = notifications only. |
| `TELEGRAM_REPLY_WINDOW` | `600` | Seconds a finished turn keeps listening for a reply. Same practical ceiling **3700** as `TELEGRAM_REPLY_WINDOW_AWAY` below — see that row. |
| `TELEGRAM_REPLY_WINDOW_AWAY` | `3600` | Same, while away mode is armed; also how long a permission prompt waits for a tap. Practical ceiling **3700** — the `Stop`/`PermissionRequest` hooks in `hooks.json` have a static 3700s timeout, so a higher value lets Claude Code kill the hook first. That fails safe (no reply, same as a timeout), but it never actually waits longer than 3700s. |
| `TELEGRAM_REPLY_POLL` | `3` | Seconds per `getUpdates` long-poll. |
| `TELEGRAM_SPOOL_TTL` | `300` | How long an unclaimed spooled update is kept. |
| `TELEGRAM_AWAY_TTL` | `7200` | Default duration for `/dcc-telegram-notify away` with no argument. |
| `TELEGRAM_LLM_URL` | *(empty = off)* | OpenAI-compatible gateway base URL for summaries. |
| `TELEGRAM_LLM_MODEL` | `auto/best-fast` | Model used for summaries. |
| `TELEGRAM_LLM_API_KEY` | *(empty)* | Sent as `Authorization: Bearer` only if set. |
| `TELEGRAM_LLM_TIMEOUT` | `12` | Seconds before falling back to lead text. |
| `TELEGRAM_LLM_MAX_TOKENS` | `512` | Summary length ceiling. |
| `TELEGRAM_MAX_CHARS` | `3500` | Final-message safety clip, under Telegram's 4096. |
| `TELEGRAM_MACHINE_NAME` | *(hostname)* | `💻` label in the header. |
| `TELEGRAM_ACCOUNT_LABEL` | *(auto)* | `👤` label; forces a value everywhere, empty hides it. |
| `TELEGRAM_ACCOUNT_LABELS` | *(none)* | JSON map of config-dir basename → label. |
| `TELEGRAM_NOTIFY_HOME` | `~/.dcc-telegram-notify` | Where config/state live. |
| `TELEGRAM_NOTIFY_ENV` | *(unset)* | Explicit path to the config file. |
| `TELEGRAM_DEBUG` | `0` | `1` traces each hook firing to `debug.log`. |

## Notes and gotchas

- **UTF-8 on Windows.** The script sends the message body over stdin, not on the curl
  command line, because Git Bash re-encodes argv to the legacy code page and mangles
  emoji / `·`. If you hand-edit the send path, keep UTF-8 text off the curl argv.
- **Per-project mode** needs the bot to be a group admin with Manage Topics; otherwise
  it falls back to the shared topic. Non-git folders always use the shared topic.
- **Per-project topics are tracked by id, not name — so fresh installs can duplicate a
  topic.** Telegram's Bot API cannot list a group's topics or look one up by name (there
  is no `getForumTopics`; a topic's name only reaches a bot in the `forum_topic_created`
  / `forum_topic_edited` update at creation/rename time). So the plugin can only remember
  the id `createForumTopic` returned, in `topics.json` — keyed by the repo's git remote,
  or its folder name when there's no remote. That map is **per-machine**: a fresh install
  (or a second machine) with an empty map can't discover a topic you already have and
  creates a new one with the **same name** (Telegram allows duplicate names). To reuse an
  existing topic, pin its id — e.g. `{ "github.com/you/repo": 42 }` in
  `~/.dcc-telegram-notify/topics.json`, getting the id from `--discover` — or share that file
  (or point `TELEGRAM_TOPIC_MAP` at a synced path) across machines.
- **Same bot on many machines is fine for sending only** — notifications have no
  polling conflict. The read side does: `--discover` and reply-back both call
  `getUpdates`, which is exclusive per bot token, so at most one machine may have
  `TELEGRAM_REPLY=on` for a given bot at a time.
- **`--edit` on a headless box.** With no GUI and no `$VISUAL`/`$EDITOR`, `--edit`
  will not launch a blocking terminal editor (nano/vi) when there's no interactive
  terminal — it prints the config path instead. Set `$EDITOR`/`$VISUAL`, or just edit
  `~/.dcc-telegram-notify/telegram.env` directly.
