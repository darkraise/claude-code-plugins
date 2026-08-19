# Assignment, escalation, and retirement tables

Single source of truth for both companion skills and the test suite. The fenced
blocks below are parsed by `tests/ladder.test.sh`; keep them machine-readable.

## Scoring rubric

Score each task on four axes, 0 to 3 each, and sum them to a total.

| Axis | 0 | 1 | 2 | 3 |
|------|---|---|---|---|
| Files | one file | two or three | four to six | seven or more, or not enumerable |
| Spec completeness | complete code given verbatim | code given with small gaps | prose plus exact signatures | prose only, approach undecided |
| Coupling | self-contained, consumes nothing | consumes one interface from an earlier task | crosses a layer, or produces interfaces others depend on | changes a shared interface |
| Risk | additive, trivially revertible | localized behavior change | shared code path or data shape | security, data loss, migration, or concurrency |

**Count file shapes, not file instances.** Sixteen files generated from one
template are one shape and score 0 on Files. The axis measures how many distinct
decisions the task carries, and repeating one decision sixteen times is still
one decision. A task that creates one config file and one test file carries two
shapes.

## Three axes are reducible, one is not

| Reducible - fix by splitting | Irreducible |
|------------------------------|-------------|
| Files, Spec completeness, Coupling | Risk |

Files, spec completeness, and coupling are facts about how the plan was drawn.
Risk is a fact about the change itself. Answering a reducible axis with a more
capable model pays to keep a decomposition defect.

## Rule S - the split gate

Let `reducible = files + spec + coupling`.

**If `reducible >= 4`, or if `spec = 3`, the task must be split or re-designed.
Do not assign a larger model.**

`spec = 3` means prose only with the approach undecided. That is not a
model-selection problem; it is a design decision nobody made. Route it to
dcc-superpower-companions:selecting-approaches, settle the approach, rewrite the
task with the decision in it, and re-score. The task will then score 0, 1, or 2
on that axis like every other compliant task.

Rule S caps a compliant total: `reducible <= 3` and `spec <= 2`, so
`total <= 3 + risk(3) = 6`. **The assignment table's ceiling is a consequence of
Rule S, not a separate choice.** A computed total of 7 or more means the gate was
skipped, not that a higher tier is needed.

### The one legacy floor

0.1.0 assigned a `spec = 3` task no lower than `impl-opus-low`. That floor now
applies only when a human overrides Rule S and keeps an undecided-approach task
as written. It raises; it never lowers.

## Assignment table

The total indexes this table directly. Two planners scoring a task identically
always reach the same agent.

```assignment
0 impl-haiku
1 impl-sonnet-low
2 impl-sonnet-medium
3 impl-sonnet-high
4 impl-opus-low
5 impl-opus-medium
6 impl-opus-high
```

## Escalation table

Escalation changes model before it changes effort, because an implementer that
is stuck usually needs more capability rather than marginally more thinking.

```escalation
impl-haiku impl-sonnet-medium
impl-sonnet-low impl-opus-low
impl-sonnet-medium impl-opus-medium
impl-sonnet-high impl-opus-high
impl-opus-low impl-opus-medium
impl-opus-medium impl-opus-high
impl-opus-high SPLIT
```

### The terminal rung is an action

`SPLIT` is not an agent. A task that exhausts `impl-opus-high` has its remaining
work broken into smaller tasks, each scored fresh against Rule S and dispatched
on its own. This is the ladder's answer to a task that is genuinely too large,
and it is the same answer Rule S gives at planning time.

**A task may be split-escalated once.** A second exhaustion is reported BLOCKED
through superpowers' existing contract. Without that guard, a task that resists
both splitting and capability would loop.

### Why this terminates

Rank each agent as `model_rank * 10 + effort_rank`, where Haiku ranks 0, Sonnet
1, and Opus 2, and effort ranks 0 through 2 from `low` to `high`. That puts Haiku
at 0, Sonnet at 10 to 12, and Opus at 20 to 22. Every successor has a strictly
higher rank, so the graph is acyclic and every walk reaches `SPLIT`.
`tests/ladder.test.sh` asserts both the ranking and the walk rather than trusting
this argument.

Judges and scouts are not on the ladder. They are not implementers, so they are
never an escalation source or target.

## Retired-agent map

0.1.0 plans name agents 0.2.0 deletes. Map them on read. The rule is **clamp each
dimension to its allowed maximum**: a retired effort clamps to `high`, and a
retired model clamps to the top execution rung.

```retired
impl-sonnet-xhigh impl-sonnet-high
impl-sonnet-max impl-sonnet-high
impl-opus-xhigh impl-opus-high
impl-opus-max impl-opus-high
impl-fable-low impl-opus-high
impl-fable-medium impl-opus-high
impl-fable-high impl-opus-high
impl-fable-xhigh impl-opus-high
impl-fable-max impl-opus-high
```

Effort clamps keep their model, because the ban is on the effort level. Fable
clamps to `impl-opus-high` regardless of its effort, because the ban is on the
model and the top execution rung is where a Fable implementer's work belongs.

State the substitution in the ledger. Never substitute silently: a plan that
quietly runs on a different tier than it records is the audit failure this
plugin exists to prevent.

## What the range actually reaches

A plan written to superpowers:writing-plans bans placeholders and requires the
real code in every code step, so a compliant task scores 0 or 1 on spec
completeness almost by construction. Combined with Rule S, initial assignments
cluster in the 0 to 3 band - Haiku and Sonnet. Scores of 4 to 6 are reached
almost entirely through the Risk axis, which is the one axis splitting cannot
reduce.

That is the intended outcome. Do not inflate an axis to land on a tier that feels
right; if a task feels harder than its score, the plan text is probably hiding
something, and the fix is a better task description or a smaller task.
