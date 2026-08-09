# dcc-telegram-notify: reply from Telegram to drive a session

Date: 2026-08-09
Status: approved

## Problem

`dcc-telegram-notify` is one-way. It tells you a session finished a turn, ended on
a question, or is blocked on a permission prompt — and then you have to walk back
to the machine to do anything about it. Every notification names a decision you
are the only one who can make, and the plugin has no way to carry your decision
back.

The goal is two-way: reply to a notification from your phone and the session picks
your message up and keeps working; tap a button on a permission prompt and the
tool call is approved or refused.

## Goals

1. A reply to a turn-end notification becomes the session's next instruction, with
   no blocking of the local terminal.
2. While explicitly armed, a tap on a permission notification allows or denies the
   pending tool call, and a tap on a question notification answers it.
3. Nothing changes for an install that does not configure the feature.
4. No path can hang, slow, or crash a session. A failure anywhere in the read side
   leaves the session behaving exactly as it does today.

## Non-goals

- No webhook receiver, no public endpoint, no tunnel.
- No injection of keystrokes into the terminal.
- No remote *initiation* of a session — this drives sessions that already exist
  and are already waiting on you.
- No change to how notifications are classified, summarized, or routed to topics.

## Hook contracts this design depends on

Verified against the Claude Code hooks reference on 2026-08-09.

| Hook | Field used | Effect |
|---|---|---|
| `Stop` | `asyncRewake: true`, exit code 2 | Runs in the background without blocking. On exit 2 the hook's stderr is shown to Claude and the session wakes. |
| `PermissionRequest` | `hookSpecificOutput.decision.behavior` | Synchronous. `allow` or `deny` resolves the pending tool call. Fires only when a permission is actually required. |
| `PreToolUse` | `hookSpecificOutput.permissionDecision`, `permissionDecisionReason` | Synchronous. Matched to `AskUserQuestion` only. `deny` with a reason is how a chosen answer reaches Claude. |
| all `command` hooks | `timeout` | Seconds before cancellation; default 600. |

Two of these need an empirical spike before implementation begins, because a
negative result changes the design rather than just the code. See
[Spikes](#spikes-run-these-first).

## Why the two flows differ

A `Stop` hook marked `asyncRewake` runs *after* the turn has ended, so the terminal
is free the whole time it is polling. That makes a genuine race possible: your
typing and your Telegram reply compete, and whichever lands first wins.

`PermissionRequest` and `PreToolUse` are the opposite. Claude Code runs them to
completion *before* it draws the prompt in your terminal, so while such a hook is
polling Telegram the local picker is not on screen and cannot be answered. They
are a gate in front of the local UI, not a parallel channel. Any waiting there is
a straight delay to the keyboard, which is why gating is off unless armed.

## Flow A — turn end

The `Stop` hook changes from `async: true` to `asyncRewake: true` and gains a
second phase.

Phase one is unchanged: consume the turn timer, classify the turn, apply the
`TELEGRAM_EVENTS` gate, send the notification. Phase two begins only if the read
side is enabled (see [Enablement](#enablement)) and a notification was actually
sent — there is nothing to reply *to* otherwise. The same background process then
polls for a reply addressed to the message it just sent, until one of three things
happens:

| Outcome | Exit | Effect |
|---|---|---|
| A reply is claimed | 2, text on stderr | Session wakes; Claude receives the text as its next instruction. |
| The session's turn-start file changes | 0 | You typed locally. Listener stands down silently. |
| The window elapses | 0 | Nothing happens; the turn stays ended. |

The window is `TELEGRAM_REPLY_WINDOW` normally and `TELEGRAM_REPLY_WINDOW_AWAY`
while away mode is armed, read once when the listener starts.

The local-typing check reads the mtime of `state/<session>.start`, which
`UserPromptSubmit` already rewrites on every locally submitted prompt. It is
checked once per poll cycle.

The hook's `timeout` in `hooks.json` is set above `TELEGRAM_REPLY_WINDOW` so the
script always decides its own lifetime rather than being cancelled mid-poll.

### Turn duration after a remote reply

A rewake-driven continuation does not fire `UserPromptSubmit`, so the turn-start
file is not rewritten and the next turn-end message will report a duration
measured from your original prompt. The listener therefore writes a fresh
turn-start timestamp at the moment it delivers a reply, restoring the invariant
that `state/<session>.start` marks the beginning of the current turn.

## Flow B — permissions and questions

Both gates return an empty decision immediately when away mode is disarmed, so the
default install pays one short-lived process only at moments where a prompt was
already going to appear.

### Ordinary tool approvals — `PermissionRequest`

When armed, the gate sends a notification carrying an inline keyboard with Allow
and Deny, then waits. A tap returns:

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

A timeout, an unreachable API, or any error returns no decision at all, and the
terminal picker appears as it does today.

This branch reuses the existing `pending_action` transcript reader for the message
body, so a Telegram approval shows the same "▸ Bash: <command>" detail the current
notification does.

### Questions — `PreToolUse` matched to `AskUserQuestion`

`PermissionRequest` can only allow or deny; it cannot supply an answer, so it
cannot resolve a question. `PreToolUse` can, by denying the call with a reason:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
 "permissionDecisionReason":"The user answered from Telegram: Postgres"}}
```

The matcher is `AskUserQuestion` and nothing else, so this hook never runs on an
ordinary tool call and adds no per-tool-call cost.

The question's own option labels become the buttons, up to the four the tool's
schema permits. A free-text reply to the same message is accepted too and is
passed through as the answer, which covers the "Other" case.

## Shared plumbing — the update reader

`getUpdates` is exclusive per bot token: whoever calls it consumes updates for
every other caller. Several sessions polling the same bot independently would
steal each other's replies. The reader is therefore cooperative, and no session
ever discards an update that was not addressed to it.

### Spool protocol

```
~/.dcc-telegram-notify/
├── updates/
│   ├── offset              last consumed update_id
│   ├── poll.lock           flock target
│   └── spool/<update_id>.json
├── pending/<nonce>.json    armed inline keyboards awaiting a tap
├── last/<chat>.<topic>     message_id of the most recent notification there
└── away                    expiry timestamp, present only while armed
```

A waiter loops:

1. Try `flock -n` on `poll.lock`. On success, call `getUpdates` once with
   `offset` one past the stored value, `timeout=$TELEGRAM_REPLY_POLL`, and
   `allowed_updates=["message","callback_query"]`. Write each returned update to
   `spool/<update_id>.json`, advance `offset` atomically (write to a temp file,
   then rename), release the lock. On failure to acquire, skip straight to step 3
   — another waiter is already filling the spool.
2. Sweep spool entries older than `TELEGRAM_SPOOL_TTL`.
3. Scan the spool for the first entry matching this waiter's predicate. Claim it
   by renaming it out of the spool into a private path. `rename(2)` is atomic, so
   two waiters can never both claim one update.
4. If nothing matched and the deadline has not passed, sleep briefly and repeat.

Because `flock` is released by the kernel when a process dies, a stale lock is not
possible.

### Authorization

Filtering happens at file time in step 1, before anything reaches the spool. An
update whose sender is not in `TELEGRAM_ALLOWED_USERS` is discarded and recorded
via `dbg`. This is a security boundary, not an ergonomic one: a reply becomes an
instruction Claude executes, and while away mode is armed a tap approves a tool
call, so anyone able to post in the chat would otherwise have command execution on
the machine.

An empty `TELEGRAM_ALLOWED_USERS` disables the entire read side. This is what makes
the feature inert on upgrade.

### Predicates

| Waiter | Matches |
|---|---|
| Turn-end listener | A `message` whose `reply_to_message.message_id` equals the notification it sent; or a `message` in the same chat and topic carrying no `reply_to_message`, when `last/<chat>.<topic>` still names that notification. |
| Permission gate | A `callback_query` whose `data` nonce matches the one it minted. |
| Question gate | The same `callback_query` match, or a `message` replying to its notification, taken as free text. |

The `last/<chat>.<topic>` file is written at send time; a notification going to a
group's main thread rather than a forum topic uses the literal name `main` in
place of the topic id. It makes "just type an answer into the topic" work without
long-pressing to Reply, while keeping a bare message from ever being claimed by an
older session.

### Inline keyboards

`callback_data` is capped at 64 bytes, so the payload cannot carry the context.
Each gated notification mints an eight-character nonce and writes
`pending/<nonce>.json` holding chat, topic, message id, session, kind, and the
option labels. The button payload is `<nonce>:<index>`.

Every notification sent while the read side is enabled carries at least one
button, so away mode is always one tap away from wherever you are: a lone **Away**
button while disarmed, and **Back** alongside the action buttons while armed. Only
gated notifications carry Allow/Deny or option buttons.

The `pending/` entry for a gate is removed when its waiter resolves or times out,
so a nonce cannot outlive the prompt it belongs to.

On a tap the waiter calls `answerCallbackQuery` to clear the spinner on the phone,
then `editMessageText` to append how the prompt resolved — so the message records
its own outcome and cannot be tapped a second time. A tap whose nonce no longer
exists is answered with a short "this request already expired" toast.

## Away mode

A single file, `away`, holding an epoch expiry. Machine-wide: one arming covers
every project and every Claude account sharing the config home, which matches the
physical fact that you walked away from the machine rather than from a project.

| Action | Effect |
|---|---|
| `/dcc-telegram-notify away [2h]` | Arm for the given duration, or `TELEGRAM_AWAY_TTL`. |
| Tap the Away button on any notification | Same. |
| Send `/away 2h` in the chat | Same. |
| `/dcc-telegram-notify back`, a Back tap, or `/back` | Disarm. |
| Expiry | Disarm. |
| Any locally submitted prompt | Disarm. |

The last rule needs care: a turn woken by a Telegram reply must not count as "you
came back." The listener writes `state/<session>.remote` when it delivers a reply;
`UserPromptSubmit` consumes that marker and skips the disarm when it is present.

## Enablement

The read side runs only when **both** `TELEGRAM_REPLY=on` and
`TELEGRAM_ALLOWED_USERS` is non-empty. The second condition is the real switch: an
existing install that updates has no allowlist, so it gets no new behavior and no
new background processes until the user deliberately configures one.

## Configuration

New keys in `~/.dcc-telegram-notify/telegram.env`, mirrored in
`telegram.env.example` and the README reference table.

| Variable | Default | Meaning |
|---|---|---|
| `TELEGRAM_ALLOWED_USERS` | *(empty)* | Comma-separated Telegram user IDs permitted to drive a session. Empty disables all reply-back. |
| `TELEGRAM_REPLY` | `on` | Master switch for the read side. |
| `TELEGRAM_REPLY_WINDOW` | `600` | Seconds a turn-end listener stays alive while away mode is disarmed. |
| `TELEGRAM_REPLY_WINDOW_AWAY` | `3600` | Seconds any waiter stays alive while armed — the turn-end listener and both gates. |
| `TELEGRAM_REPLY_POLL` | `3` | Server-side long-poll seconds per `getUpdates` call. |
| `TELEGRAM_SPOOL_TTL` | `300` | Seconds before an unclaimed spooled update is swept. |
| `TELEGRAM_AWAY_TTL` | `7200` | Default arming duration. |

Existing variables are unchanged. Notification *selection* stays with
`TELEGRAM_EVENTS`; reply-back is a capability rather than a message category, so it
does not get a token there.

## Components

New logic lands in two new sourced libraries rather than growing the 737-line
engine, so it can be tested in isolation.

| File | Responsibility | Depends on |
|---|---|---|
| `scripts/lib/updates.sh` | Offset, lock, poll, spool, allowlist filter, atomic claim, TTL sweep. Knows nothing about hooks. | `curl`, `jq`, `flock` |
| `scripts/lib/await.sh` | The two waiting loops, predicates, nonce minting, `pending/` bookkeeping, keyboard construction, `answerCallbackQuery` / `editMessageText`. | `updates.sh`, `send` |
| `scripts/dcc-telegram-notify.sh` | Wiring only: two new event branches, `reply_markup` support in `send`, `last/` write at send time, away-mode helpers, new maintenance flags. | both |

New maintenance flags: `--away [duration]`, `--back`, and `--reply-status` (a
diagnostic dump of enablement, allowlist size, away state, spool depth, and stored
offset). `/dcc-telegram-notify status` reports the same, and `setup` gains a step
that captures the user's own Telegram ID from their first message to the bot.

`hooks/hooks.json` gains `PermissionRequest` and a `PreToolUse` entry matched to
`AskUserQuestion`, and changes the `Stop` entry from `async` to `asyncRewake` with
an explicit `timeout`.

## Error handling

The governing rule is the one the plugin already follows: a notification path must
never disturb a session.

| Condition | Behavior |
|---|---|
| Telegram unreachable or timing out | Waiter exits quietly. Turn stays ended; terminal picker appears. |
| `409 Conflict` from `getUpdates` | Another consumer or a webhook owns this bot. Log via `dbg` and stand down for this run rather than fighting for updates. |
| Lock held by another waiter | Skip the poll, scan the spool, retry next cycle. |
| Malformed or unparseable update | Dropped; the sweep removes it. |
| `pending/` nonce missing on a tap | Answered with an "expired" toast; no decision returned. |
| `jq` or `flock` absent | Read side disables itself; the send side keeps working. |
| Empty allowlist | Read side inert; `--reply-status` says so in one line. |

## Known limitations, to be documented in the README

**Bot privacy mode.** On by default in groups, it hides ordinary messages from
bots. Until it is disabled in BotFather, a bare message typed into a topic never
reaches the bot and only Telegram's Reply function works. The README already warns
about this for `--discover`; the note is extended.

**One machine per bot token.** `getUpdates` exclusivity means exactly one machine
should have the read side enabled for a given bot. A second machine needs its own
bot. The current README claim that "the same bot on many machines is fine" is
narrowed to the send side, and `--reply-status` prints the caveat.

**Reply is execution.** A reply is an instruction Claude acts on, and an armed tap
approves a tool call. The allowlist is the only boundary. Stated plainly in the
README next to `TELEGRAM_ALLOWED_USERS`.

## Spikes: run these first

Both are cheap and both would change the design if they fail.

1. **Does `asyncRewake` wake an idle session?** The docs describe it as a way to
   surface a long-running background failure and do not state that it can wake a
   session whose turn has fully ended. Test: a `Stop` hook that sleeps 20 seconds,
   then exits 2 with text on stderr, in an otherwise idle session. If Claude does
   not resume with that text, flow A falls back to a synchronous `Stop` hook with
   a short window, and the "no blocking" property is lost.
2. **Does a `PreToolUse` denial reason read as an answer?** Test: deny an
   `AskUserQuestion` call with `permissionDecisionReason` phrased as a chosen
   option and confirm Claude proceeds on that choice rather than re-asking or
   treating it as a refusal. If it does not, the question gate is dropped and
   `AskUserQuestion` stays notify-only.

## Testing

Follows the existing suite: bash scripts under `tests/`, sourced-script isolation
with `TELEGRAM_NOTIFY_ENV` pointed at a nonexistent path, `TELEGRAM_NOTIFY_HOME`
pointed at a temp dir, and fixtures under `tests/fixtures/`. A stub `curl` placed
early on `PATH` returns canned `getUpdates`, `sendMessage`, and `answerCallbackQuery`
payloads so nothing touches the network.

`tests/updates.test.sh`

- One spool file written per update; the stored offset advances past the highest
  `update_id` and a replayed response produces no duplicates.
- A sender outside `TELEGRAM_ALLOWED_USERS` never reaches the spool.
- Two concurrent claimers matching the same update: exactly one wins.
- Entries older than `TELEGRAM_SPOOL_TTL` are swept; fresh ones survive.
- Each predicate matches only what it should: reply-to id, callback nonce, and a
  bare topic message against a current versus a superseded `last/` marker.
- A `409` response disables the read side for that run without error output.

`tests/away.test.sh`

- Arm, disarm, and expiry transitions; an expired file reads as disarmed.
- Both gates return an empty decision when disarmed.
- `UserPromptSubmit` disarms normally, but not when `state/<session>.remote` is
  present, and it consumes that marker.

`tests/listen.test.sh`

- The three listener exits: claimed reply gives exit 2 with the text on stderr; a
  touched turn-start file gives exit 0 with no output; an elapsed window gives
  exit 0.
- Delivering a reply rewrites the turn-start timestamp.

Existing tests are unchanged; `tests/run-all.sh` gains the three new files.

## Verification

- `bash plugins/dcc-telegram-notify/tests/run-all.sh` passes.
- `claude plugin validate .` passes at the repo root.
- `bash -n` clean on the engine and both new libraries.
- Both spikes recorded with their observed outcome before implementation starts.
- A live end-to-end pass on Windows/Git Bash: reply to a turn-end notification and
  confirm the session continues; arm away mode, tap Allow on a permission prompt,
  and confirm the tool runs.
- With `TELEGRAM_ALLOWED_USERS` empty, confirm no listener process outlives a turn.

Version: 1.2.0.
