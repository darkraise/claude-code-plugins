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

## Score every task, then check whether it should exist as written

Read the rubric, Rule S, and the assignment table from
[`../../reference/ladder.md`](../../reference/ladder.md). Do not restate the
tables here or work from memory: that file is the single source of truth and it
is what the test suite validates.

Score the task as the plan describes it, not as you imagine it might grow.
"Spec completeness" in particular is a fact about the plan text: if the task's
steps contain the complete code to write, that axis is 0 no matter how clever
the code is. Count file shapes rather than file instances - the rubric says why.

**Then apply Rule S before you look at the assignment table.** If
`files + spec + coupling >= 4`, or if `spec = 3`, this task is not a
model-selection problem. It is a task drawn too large or a design decision
nobody made, and the answer is to change the plan:

- **`reducible >= 4`:** split the task. Draw the boundary where a reviewer could
  meaningfully reject one half while approving the other, per superpowers'
  Task Right-Sizing. Fold setup and scaffolding into the half that needs them.
  Re-score both halves; each should now clear the gate.
- **`spec = 3`:** the approach is undecided. Run
  dcc-superpower-companions:selecting-approaches, settle it, rewrite the task
  with the decision in its steps, and re-score. The axis will then be 0, 1, or
  2 like every other compliant task.

Only after Rule S passes does the total index the assignment table.

**Resist the urge to reach for a bigger model instead.** Three of the four axes
measure how you drew the task, not how hard the change is. Buying capability to
cover a decomposition defect keeps the defect and pays for it, and it is the
specific failure this version of the rubric exists to remove. If a task keeps
failing Rule S no matter how you split it, that is a real finding about the
work - say so in the plan rather than scoring around it.

## Write the assignment

Add two or three lines to each task block, directly below its `**Interfaces:**`
block:

```markdown
**Implementer:** dcc-superpower-companions:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5
**Approach:** inline - skip 2: follows the existing exporter pattern
```

The `**Approach:**` line is required whenever the task involved an approach
decision, and omitted otherwise. Its value is `inline`, `advisor`, or
`best-of-3`, followed by a dash and a one-line reason.
dcc-superpower-companions:selecting-approaches owns the gate that produces it.
An `inline` reason must cite a skip condition by number - an uncited skip is not
a skip.

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
- Every task clears Rule S. Compute `files + spec + coupling` for each and
  confirm none reaches 4, and that no task scores 3 on spec completeness. A
  total above 6 anywhere means the gate was skipped, since Rule S caps a
  compliant total at 6.
- Every `**Approach:**` line names `inline`, `advisor`, or `best-of-3`, and
  every `inline` cites a skip condition by number.
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
