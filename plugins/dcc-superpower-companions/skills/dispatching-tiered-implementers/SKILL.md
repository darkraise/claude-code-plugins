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

**Changes.** Three things:

1. The implementer dispatch passes
   `subagent_type: dcc-superpower-companions:impl-<model>-<effort>` and passes
   **no `model` argument**.
2. The task-review seat is a judge agent - `judge-fable`, or `judge-opus` when
   Fable is unavailable - dispatched with the criteria file appended to
   superpowers' reviewer prompt. See Score the review.
3. The scoped re-review is asked for one extra line, a progress reading, which
   can pull the escalation point from round 4 to round 3. See Progress.

**Does not change.** The brief and report file protocol, the review package, the
five-round cap, the breaker and its adjudication rules, the final whole-branch
review, and the handoff to superpowers:finishing-a-development-branch.
Implementers are still never dispatched in parallel, and the final whole-branch
review keeps superpowers' own model selection.

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
2. If that value names a retired agent, map it through the `retired` table in
   [`../../reference/ladder.md`](../../reference/ladder.md) and dispatch the
   target instead. Say the substitution aloud and record it in the ledger line
   you already add:

   ```
   Task <N>: implementer impl-opus-high (assigned; mapped from retired impl-fable-max)
   ```

   A 0.1.0 plan names agents this version deletes. Mapping them is why the
   table exists; without it the next rule stops the run.
3. Dispatch with that value as `subagent_type`, using superpowers'
   `implementer-prompt.md` template unchanged for the prompt body. Where the
   template's header reads `Subagent (general-purpose):`, use the assigned
   agent instead.
4. Record the agent identity from the dispatch result, exactly as superpowers
   requires. Fix rounds 1 to 3 resume this agent.
5. Note the assignment in the ledger superpowers already owns. Resolve its
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
   in exactly three places: under Escalate, under Score the review, and under
   Progress.

   `Task <N>: implementer <agent> (assigned)` is the only line you add before
   the task's first review. Add it once, right after dispatch.

`sdd-workspace` prints a bare path, but `task-brief` does not — it prints
`wrote <path>: <N> lines`. Read the brief path out of that line; do not pipe
`task-brief`'s output into a dispatch prompt as if it were a filename.

## Escalate

Read the escalation table from
[`../../reference/ladder.md`](../../reference/ladder.md). Escalation applies at
three points - the two superpowers defines, plus one this skill adds:

- **Fix rounds 4 and 5**, where superpowers dispatches a fresh implementer on a
  more capable model.
- **The BLOCKED handler**, where superpowers re-dispatches on a more capable
  model when the task requires more reasoning. A BLOCKED report caused by
  missing context is not an escalation: supply the context and re-dispatch the
  same agent, as superpowers says.
- **Round 3, when progress has stalled** - see Progress below. This can only
  pull the escalation point earlier, never later.

Escalation does **not** apply to fix rounds 1 and 2, nor to round 3 unless
Progress says the loop has stalled. Those rounds resume the original agent,
which preserves its model, its effort, and its context. Re-dispatching a
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

The ladder's top rung is `impl-opus-high`, whose successor is `SPLIT` - an
action, not an agent. When it is exhausted, do not report BLOCKED yet: break the
task's remaining work into smaller tasks, score each against Rule S, and
dispatch them fresh. Record it as a ruling in the ledger:

```
Ruling: split Task <N> at the top rung into <N>a and <N>b - impl-opus-high exhausted after 5 rounds - if wrong, the halves review separately and merge back
```

This `Ruling:` line is exempt from the last-line rule above, because it is not a
`Task <N>:` line. Superpowers writes its own `Ruling:` lines in the same
position after the cap, so crash recovery already steps over them when it looks
for a task's last `Task <N>:` verb.

**A task may be split-escalated once.** If a split half also exhausts the
ladder, report BLOCKED through superpowers' existing contract. Do not loop.

## Score the review

superpowers dispatches a task reviewer. Dispatch `judge-fable` for that seat
instead of a general-purpose agent, and hand it the criteria file alongside the
inputs superpowers already specifies.

**If Fable is unavailable on this account, or your human partner has said not to
use it, dispatch `judge-opus` instead and say so.** Never substitute silently.

**Prompt order matters.** Put the invariant material first - the brief path, the
report path, the diff path, and superpowers' process rules - and the criteria
block last. On the K=3 path below, the three prompts then share a long identical
prefix, which is the only reason the ordering is specified.

Append to superpowers' task-reviewer prompt:

```
## Criteria

Read the criteria file at [PLUGIN_ROOT]/criteria/task-review.md and score each
criterion independently on a 1 to 20 scale, where 1 is a clear failure, 10 is
genuinely uncertain, and 20 is clearly met.

Add this block to the end of your report, after the Assessment section:

### Verification Scores
- spec: <1-20>
- verification: <1-20>
- quality: <1-20>

Score against those criteria and nothing else. Where a criterion tells you to
ignore something, ignoring it is part of scoring correctly.
```

Expand `[PLUGIN_ROOT]` to this plugin's directory before sending the prompt. A
judge handed the literal token cannot open the file. The hook uses
`${CLAUDE_PLUGIN_ROOT}` for the same value; in a dispatch prompt you write the
resolved path.

**The scores are additive.** superpowers' fix loop triggers on its spec-failure
verdict, on Critical findings, and on Important findings. Keep every one of
those; the scores ride alongside and never replace them. A judge that returns
scores but drops the verdicts has produced an unusable review - re-dispatch it.

Read the scores as bands: **1-8 fails** and joins the fix-loop trigger; **9-13**
is borderline, recorded and adjudicated by you; **14-20 passes**.

Record the scores by extending superpowers' own completion line, whether one
judge scored the task or three:

```
Task <N>: complete (commits <base7>..<head7>, review clean; scores spec 17 / verification 15 / quality 16)
```

Never author a separate scores line. Superpowers keys crash recovery off
`Task <N>: complete`, and a line landing after it hides it.

### Repeated evaluation on risk-3 tasks

When the task's `**Evaluation:**` line scored **risk 3**, dispatch three judges
independently on the same inputs and average each criterion. Risk is the one
axis Rule S cannot reduce, so it is the one place worth paying three times.

**Disagreement is the signal, not the mean.** If the three scores for any
criterion spread by more than 6 points, read the diff yourself rather than
trusting the average. A wide spread means the criterion failed to discriminate
on this diff, which is a fact about the review, not about the code.

Record the reading in the ledger line you already write:

```
Task <N>: complete (commits <base7>..<head7>, review clean; scores spec 17 / verification 15 / quality 16, K=3)
```

## Progress

Ask the re-reviewer for one extra line, and only the re-reviewer:

```
**Progress:** <1-20>
```

Answering: given everything the implementer has done so far, would the current
state already satisfy the task? Anchors match the review bands - 1 certainly
not, 10 uncertain, 20 verified complete.

**If round N's progress is less than or equal to round N-1's, escalate at the
start of the next round** rather than waiting for round 4. A fix loop whose
progress is flat or falling is not converging, and two more rounds on the same
agent buy nothing.

**Never escalate before round 3.** superpowers resumes the same implementer on
rounds 1 to 3 specifically to preserve its model, its effort, and its context.
This rule may pull the escalation point from 4 to 3; it may never pull it to 2,
and it may never delay it past 4.

Fold the reading into superpowers' own fix-round line, for the reason this skill
already gives about lines that land after a fix-round line:

```
Task <N>: fix round 3/5 (1 addressed, 1 open - stale cache; commits a7f..b21; progress 11 -> 9; escalated impl-sonnet-medium -> impl-opus-medium)
```

## Failure modes

| Situation | Response |
|-----------|----------|
| Task has no `**Implementer:**` line | Score it with the rubric in `reference/ladder.md`, dispatch, and record `Task <N>: implementer <agent> (scored at dispatch)` |
| The line names a retired agent | Map it through the `retired` table, dispatch the target, and state the substitution in the ledger |
| The line names an agent that is neither current nor retired | Stop and ask your human partner. Never fall back silently |
| Fable is unavailable or declined for a judge seat | Dispatch `judge-opus`, say so, and continue |
| An implementer's model is unavailable on this account | Substitute the same effort one model down, state the substitution in the ledger and to your partner, and continue. From Sonnet there is no such rung - stop and ask instead |
| Escalation exhausted at impl-opus-high | Split the remaining work once; if a half also exhausts, report BLOCKED per superpowers |

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
