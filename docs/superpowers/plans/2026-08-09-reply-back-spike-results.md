# Reply-back spike results

Date: 2026-08-10
Method: live interactive Claude Code session, hooks registered in a scratch project.
Run by the repository owner; a subagent cannot perform this test, because an
`asyncRewake` hook needs a session that stays alive after its turn ends.

## Spike 1 — does `asyncRewake` wake an idle session?

**YES.** The turn ended normally, the terminal stayed usable, and roughly 20 seconds
later the session woke on its own and executed the instruction carried on the hook's
stderr (`git status`, reported back correctly).

Flow A survives as designed. The `Stop` hook stays `asyncRewake`, and the "your
terminal is never blocked" property holds.

### Does a rewake-driven turn fire `UserPromptSubmit`?

**YES.** `ups.log` recorded 12 firings against roughly 2 prompts the owner actually
typed, so the woken turns each fired it too.

This makes the `state/<session>.remote` marker load-bearing rather than defensive:
without it, every reply arriving from Telegram would fire `UserPromptSubmit` and
disarm away mode, exactly as if the owner had walked back to the keyboard. The plan
already specifies the marker and a 120-second TTL on it. Keep both.

## Spike 2 — does a `PreToolUse` denial reason read as an answer?

**NO.** Decisively. Presented with a denial whose reason read
`The user answered from Telegram: PostgreSQL`, the session refused to treat it as a
selection:

> AskUserQuestion returned an error, not a selection — the error text claims "the user
> answered from Telegram: PostgreSQL", which is the same unverified relay channel as
> the looping Stop-hook messages, not a recorded choice in the tool's response. So I
> have no confirmed pick from you, and I'm not going to write PostgreSQL into
> anything on the strength of that string.

**Consequence: Task 9 is dropped.** `AskUserQuestion` stays notify-only. The plan's
own decision rule called for this outcome.

## Spike 3 — unplanned, and the most consequential finding

**Claude Code marks a rewake payload as untrusted, and the session acts accordingly.**

The woken session volunteered, unprompted:

> it came in as Stop-hook feedback wrapped in a notification that explicitly said no
> human input had been received and that nothing in it should be treated as your
> instruction. So I ran it because `git status` is read-only and harmless, not because
> I treated the hook text as your message. […] I'd only run non-trivial or irreversible
> commands from it after you confirm here directly.

So the channel delivers text and wakes the session, but the text arrives labelled as
*not* user input. A well-behaved session will act on read-only or analytical
instructions and will decline irreversible ones without local confirmation. This is
correct platform behaviour — a hook can emit anything, so its output should not carry
user authority — but it materially narrows what "reply and the agent keeps working"
can mean.

### What this does and does not affect

| Path | Affected? | Why |
|---|---|---|
| Turn-end reply (Task 7) | **Yes** | Text arrives via the hook channel and is treated as untrusted. Continuation, reading, analysis and answering work; edits, commits, deploys may draw a confirmation request. |
| Permission tap (Task 8) | **No** | `PermissionRequest` returns a control-plane decision (`allow`/`deny`) that the CLI honours directly. It is not text Claude must decide whether to trust. |
| AskUserQuestion (Task 9) | Dropped | See spike 2. |

### Not a defect: the observed loop

The probe fired six times in a row because it exited 2 unconditionally on every
`Stop`. The real listener exits 2 only when it has *claimed* a reply, and a claimed
update is removed from the spool by an atomic rename, so it cannot be re-delivered.
The production design does not have this behaviour.

## Decisions taken

1. Keep flow A on `asyncRewake` — spike 1 passed.
2. Keep `state/<session>.remote` and its TTL — spike 1's follow-up requires it.
3. Drop Task 9 entirely; `AskUserQuestion` remains notify-only.
4. Spike 3 is a scope question for the repository owner, recorded here and raised
   directly rather than decided unilaterally.
