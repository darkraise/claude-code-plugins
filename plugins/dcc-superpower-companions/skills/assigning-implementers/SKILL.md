---
name: assigning-implementers
description: Use when writing an implementation plan with superpowers:writing-plans - scores each task on a four-axis rubric and records which model and effort tiered implementer subagent will run it
---

# Assigning Implementers

Record, for every task in an implementation plan, which implementer subagent
will run it. The choice becomes a property of the plan document instead of a
judgment made from memory at dispatch time.

**Announce at start:** "I'm using the assigning-implementers skill to assign an
implementer to each task."

## When this applies

Use alongside superpowers:writing-plans, after the tasks are drafted and before
the plan is saved. Retrofitting an existing plan is the same process: read it,
score each task, add the two lines.

The assignment is only acted on by superpowers:subagent-driven-development.
Under superpowers:executing-plans, which runs tasks inline in the current
session without subagents, the lines are inert. That is correct, not broken;
leave them in place so the plan stays portable between both execution paths.

## Score every task

Read the rubric and the assignment table from
[`../../reference/ladder.md`](../../reference/ladder.md). Do not restate the
tables here or work from memory: that file is the single source of truth and it
is what the test suite validates.

Score the task as the plan describes it, not as you imagine it might grow.
"Spec completeness" in particular is a fact about the plan text: if the task's
steps contain the complete code to write, that axis is 0 no matter how clever
the code is.

Sum the four axes and read the agent off the assignment table. Totals cluster
low, because superpowers:writing-plans bans placeholders and requires real code
in code steps — see the reachable-range note in `reference/ladder.md`. Resist
inflating an axis to reach a tier that feels right; the escalation ladder exists
for tasks that turn out harder than the plan text showed.

## Write the assignment

Add two lines to each task block, directly below its `**Interfaces:**` block:

```markdown
**Implementer:** dcc-superpower-companions:impl-opus-medium
**Evaluation:** files 2 - spec 1 - coupling 2 - risk 2 = 7
```

The agent name is fully qualified. Plugin subagents are namespaced
`<plugin>:<agent>`, and an unqualified name may not resolve.

Both lines land in the brief the implementer reads, because
superpowers' `scripts/task-brief` copies a task block verbatim. That is
intended: an implementer knowing its task's blast radius is useful context.

**Keep superpowers' task heading form.** `scripts/task-brief` finds a task by
matching a heading that begins with `Task <N>`, so the heading must read
`### Task 4: Wire the export pipeline`, exactly as superpowers:writing-plans
specifies. A heading that buries the number, such as
`### Wire the export pipeline (Task 4)`, does not match: `task-brief` exits
non-zero leaving an empty brief file, and the task cannot be dispatched.

The damage is not confined to that task. `task-brief` only stops copying when
it meets the *next* heading it recognizes, so a malformed heading silently
appends its whole task body to the **previous** task's brief. One bad heading
therefore breaks one task and corrupts its neighbor, and the neighbor's brief
still exits 0 and looks fine.

## Amend the plan header

Append one blockquote line to the plan header. **Append it; never replace the
existing `REQUIRED SUB-SKILL` line** — that line is what hands off to
superpowers:subagent-driven-development, and replacing it breaks the handoff.

```markdown
> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. When executing with
> superpowers:subagent-driven-development, REQUIRED SUB-SKILL:
> dcc-superpower-companions:dispatching-tiered-implementers. Under
> superpowers:executing-plans these lines are inert; ignore them.
```

This is what makes the plan carry its own execution instruction, so a session
that opens the plan cold still dispatches correctly. The condition matters:
superpowers' own header offers both execution paths, and an unconditional
second `REQUIRED SUB-SKILL` would demand a subagent-dispatch skill from the
inline path that never dispatches subagents.

## Check your work

Before saving the plan:

- Every task has both lines. A task without them gets scored at dispatch time
  instead, which works but loses the audit trail.
- Every agent name is fully qualified and appears in
  `reference/ladder.md`'s assignment table.
- Every `**Evaluation:**` line's four scores actually sum to the stated total,
  and that total maps to the named agent — allowing for the spec-3 floor in
  `reference/ladder.md`, which is the one case where the agent legitimately
  outranks the total. A total that disagrees with the agent for any other
  reason is the one error that makes the record actively misleading.
- Every task heading begins with `Task <N>`. Check them as a set, not one by
  one: `grep -cE '^#+[[:space:]]+Task[[:space:]]+[0-9]' PLAN_FILE` must equal
  the number of tasks. That pattern is superpowers' own matcher.
  A single `task-brief` run proves nothing about the rest of the plan — it only
  inspects the heading of the task you asked for, and a task whose own heading
  is fine still exits 0 while carrying a malformed neighbor's body inside it.

## Overriding

A human can edit any `**Implementer:**` line by hand. The dispatching skill
obeys the line and never recomputes when it is present, so a human ruling
always wins over the rubric. When you override, leave the `**Evaluation:**`
line in place: the gap between the score and the choice is the interesting part.
