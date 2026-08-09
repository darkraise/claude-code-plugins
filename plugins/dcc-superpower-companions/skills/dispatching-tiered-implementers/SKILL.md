---
name: dispatching-tiered-implementers
description: Use when executing a plan whose tasks carry an Implementer line - dispatches the named model and effort tiered subagent and escalates along a defined ladder
---

# Dispatching Tiered Implementers

Run superpowers:subagent-driven-development exactly as written, with one
substitution: the implementer dispatch names a fleet agent instead of
`general-purpose`.

**Announce at start:** "I'm using the dispatching-tiered-implementers skill to
dispatch each task's assigned implementer."

## What changes, and what does not

**Changes.** Exactly one thing: the implementer dispatch passes
`subagent_type: dcc-superpower-companions:impl-<model>-<effort>` and passes **no
`model` argument**.

**Does not change.** The brief and report file protocol, the review package, the
task reviewer, the scoped re-review, the five-round cap, the breaker and its
adjudication rules, the final whole-branch review, and the handoff to
superpowers:finishing-a-development-branch. Reviewer model selection stays
superpowers'. Implementers are still never dispatched in parallel.

## The one superpowers instruction this supersedes

superpowers:subagent-driven-development states in bold that you must always
specify the model explicitly when dispatching a subagent, because an omitted
model inherits the session's model.

**For implementer dispatches only, that is superseded.** The Agent tool's
`model` argument overrides the agent file's `model` frontmatter, but there is no
matching `effort` argument, so effort keeps its frontmatter value. Passing a
model therefore produces a mismatched pairing such as Sonnet running at xhigh.

The rule's intent survives intact: the agent definition pins the model, so
nothing inherits the session default. The rule remains in force for every other
dispatch, including all reviewers.

## Dispatch a task

1. Read the task's `**Implementer:**` line.
2. Dispatch with that value as `subagent_type`, using superpowers'
   `implementer-prompt.md` template unchanged for the prompt body. Where the
   template's header reads `Subagent (general-purpose):`, use the assigned
   agent instead.
3. Record the agent identity from the dispatch result, exactly as superpowers
   requires. Fix rounds 1 to 3 resume this agent.
4. Note the assignment in the ledger superpowers already owns. Resolve its
   directory the way superpowers does — run its
   `scripts/sdd-workspace PLAN_FILE` and use the path it prints — rather than
   assuming a layout. The ledger is `progress.md` inside that directory.

   ```
   Task <N>: implementer <agent> (assigned)
   ```

   Never create a competing ledger. Superpowers owns five `Task <N>:` verbs —
   `complete`, `fix round`, `minor (deferred)`, `parked`, and `BLOCKED` — and
   no line you author may start with one of them. Its crash recovery keys on
   `Task <N>: complete`, and its final whole-branch review is pointed at the
   `minor (deferred)` and `parked` lines for triage, so a line either of them
   misreads costs a re-dispatch of finished work or a bogus merge blocker.
   Extending a line superpowers itself writes is a different act and is allowed
   in exactly one place, described under Escalate.

   `Task <N>: implementer <agent> (assigned)` is the only line you add before
   the task's first review. Add it once, right after dispatch.

`sdd-workspace` prints a bare path, but `task-brief` does not — it prints
`wrote <path>: <N> lines`. Read the brief path out of that line; do not pipe
`task-brief`'s output into a dispatch prompt as if it were a filename.

## Escalate

Read the escalation table from
[`../../reference/ladder.md`](../../reference/ladder.md). Escalation applies at
exactly two points, both defined by superpowers:

- **Fix rounds 4 and 5**, where superpowers dispatches a fresh implementer on a
  more capable model.
- **The BLOCKED handler**, where superpowers re-dispatches on a more capable
  model when the task requires more reasoning. A BLOCKED report caused by
  missing context is not an escalation: supply the context and re-dispatch the
  same agent, as superpowers says.

Escalation does **not** apply to fix rounds 1 to 3. Those resume the original
agent, which preserves its model, its effort, and its context. Re-dispatching a
different tier there discards exactly what superpowers is preserving.

Record each escalation **inside** superpowers' own fix-round line, by appending
one clause to the line it already writes at the end of the round:

```
Task <N>: fix round 4/5 (1 addressed, 1 open - <one-liner>; commits <a7>..<b7>; escalated <old-agent> -> <new-agent>)
```

Do not write a separate escalation line. Superpowers' crash recovery reads a
task's *last* ledger line and treats a task whose last line is a fix round as
mid-loop, to be resumed at the next round. Any line of your own that lands after
a fix-round line hides it, and a controller resuming after compaction reads the
task as never started, then re-dispatches work that is already done. Folding the
clause in keeps a fix-round line last at every moment, so the task recovers
exactly as it would under vanilla superpowers — including a crash partway
through round 4, where the last line is still `fix round 3/5` and the loop
resumes at round 4. The escalated agent does not need its own line to survive a
crash: the ladder is deterministic, so the round number and the original
assignment re-derive it.

A BLOCKED-handler escalation has no fix-round line to extend, because it happens
outside the fix loop. Superpowers records nothing there either, so record
nothing: re-dispatch on the successor and let the next line the loop writes
carry the state.

When the ladder is exhausted at `impl-fable-max`, which has no successor, report
BLOCKED through superpowers' existing contract. Do not loop.

## Failure modes

| Situation | Response |
|-----------|----------|
| Task has no `**Implementer:**` line | Score it with the rubric in `reference/ladder.md`, dispatch, and record `Task <N>: implementer <agent> (scored at dispatch)` |
| The line names an agent with no definition file | Stop and ask your human partner. Never fall back silently |
| The model is unavailable on this account | Substitute the same effort one model down, state the substitution in the ledger and to your partner, and continue. From Sonnet there is no such rung — stop and ask instead |
| Escalation exhausted | Report BLOCKED per superpowers |

The silent-fallback rule matters more than it looks. If a bad agent name quietly
degraded to the session default, every task would run at the session's model and
effort and nothing in the output would reveal it. That is precisely the
expensive-model failure superpowers' Model Selection section exists to prevent.

The unavailable-model row exists because Fable is not on every account. Drop the
model one rung and keep the effort. State it; never substitute silently.

That substitution runs out below Sonnet. Haiku ships in one flavour with no
effort variants, so "same effort, one model down" has no target from a
`impl-sonnet-*` agent, and dropping to `impl-haiku` would silently discard the
effort level the score asked for. If Sonnet itself is unavailable, say so and
ask your partner rather than inventing a rung.
