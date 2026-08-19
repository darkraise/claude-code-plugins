---
name: selecting-approaches
description: Use when an approach decision is open - during brainstorming, or when a plan task scores 3 on spec completeness - gates the decision to inline, advisor, or a best-of-3 pairwise ranking
---

# Selecting Approaches

Settle an open approach decision at a cost that matches what the decision is
worth. Most decisions are settled inline; a few earn one advisory pass; a small
number earn a ranked competition.

**Announce at start:** "I'm using the selecting-approaches skill to settle this
approach decision."

## When this applies

Two entry points:

- **superpowers:brainstorming**, at the architectural path's "propose 2-3
  approaches" step.
- **A plan task scoring 3 on spec completeness**, which Rule S in
  [`../../reference/ladder.md`](../../reference/ladder.md) routes here rather
  than to a larger model. Prose only with the approach undecided is a design
  decision nobody made, and buying capability is not the same as making it.

## The gate decides who decides, not whether

Every decision that reaches this skill gets settled before implementation. The
gate chooses which of three seats settles it:

| Outcome | Cost | Who settles it |
|---------|------|----------------|
| `inline` | 0 subagent calls | You do, and record why |
| `advisor` | 1 call | You choose; one judge checks the choice |
| `best-of-3` | 4 calls | Three scouts draft; one judge ranks |

The middle rung exists because a load-bearing decision with only one plausible
approach asks a verification question - "is this one wrong" - not a selection
question. Ranking one candidate against nothing is not a ranking.

## Skip to inline

Any one of these sends the decision to `inline`. **Cite it by number in the
`**Approach:**` line.** An uncited skip is not a skip - it is you deciding the
cost is inconvenient, which is exactly what the gate is here to stop.

1. **A bug fix whose root cause is located.** Fixing it correctly is one
   approach; the alternatives are wording.
2. **The repository already answers it.** An established pattern covers this
   exact change - a fourth adapter beside three, a new flag beside eight.
   Consistency dominates, and a creative alternative is a defect.
3. **The spec or your human partner already chose.** Ranking ruled-out options
   is theatre.
4. **Trivially reversible and confined to one file.** Being wrong costs a
   revert.
5. **You cannot name two structurally distinct candidates.** Write each in one
   sentence before dispatching anything. Differing in naming, ordering, or
   wording is not structural difference.

### Bugs are excluded on correctness grounds, not cost

Generating candidate approaches before a root cause is located produces N
guesses, and a ranking pass returns a winner whether or not any candidate is
right - laundering speculation into a confident pick. An unlocated root cause is
a debugging problem: use superpowers:systematic-debugging. Come back here only
if, with the cause in hand, more than one structurally distinct fix exists.

## When best-of-3 runs

All three must hold:

- At least two structurally distinct candidates you can state in one sentence
  each.
- The decision is load-bearing: it constrains later tasks, or it is expensive to
  reverse - an interface others consume, a data shape, a stored format, a
  migration, a public API, a dependency choice.
- Neither the repository nor the spec already answers it.

Everything not skipped and not qualifying lands on `advisor`.

## Run best-of-3

**Draft.** Dispatch three `dcc-superpower-companions:scout-sonnet` agents in
parallel, one per candidate, per superpowers:dispatching-parallel-agents. Give
each the same decision statement and the same constraints, and name its
candidate's angle so the three do not converge. Each returns one committed
approach, not a survey.

**Rank.** Dispatch one `dcc-superpower-companions:judge-fable` to run the ring
pass: three comparisons, **A vs B, B vs C, C vs A**, scoring both candidates
against every criterion in
[`../../criteria/approach-selection.md`](../../criteria/approach-selection.md)
each time.

The ring is the whole reason for three comparisons rather than one. Every
candidate sits in slot A exactly once and slot B exactly once, so a judge's
preference for whichever candidate it read first cancels out exactly. Do not
reorder the ring, and do not drop a comparison to save a pass - two comparisons
leave one candidate unbalanced and the bias comes back.

**If Fable is unavailable or your human partner has declined it, dispatch
`judge-opus` instead and say so.** Never substitute silently.

**Select.** Aggregate the three comparisons into a win count per candidate. The
highest wins. Report the winner, the ranking, and the **grafts** - the ideas
from the losing candidates worth folding into the winner. A ring pass that
returns only a winner has thrown away two thirds of what it paid for.

If the ring produces a three-way tie, the candidates are equivalent on these
criteria. Say so and choose the simplest; do not run a second ring to break a
tie the criteria could not see.

## Run advisor

State your chosen approach in a paragraph, then dispatch one judge to score it
against the same criteria file and answer one question: is this approach wrong
for this repository, and if so, what specifically would fail?

A judge that finds nothing is not a rubber stamp - it is the cheap outcome you
were paying for. A judge that finds something is why the seat exists; treat its
answer as a finding to address, not a veto to argue with.

## Record the decision

Write one line into the plan task or the design document:

```markdown
**Approach:** inline - skip 2: follows the existing hook-script pattern
**Approach:** advisor - load-bearing (produces the criteria file format)
**Approach:** best-of-3 - file-per-criterion vs single-registry vs inline-in-skill
```

For `best-of-3`, also record the grafts wherever the decision itself is written
down. The losing candidates are the most expensive thing this skill produces
that is not the winner, and they are gone the moment the session ends.
