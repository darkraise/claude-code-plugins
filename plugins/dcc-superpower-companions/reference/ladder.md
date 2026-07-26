# Assignment and escalation tables

Single source of truth for both companion skills and the test suite. The fenced
blocks below are parsed by `tests/ladder.test.sh`; keep them machine-readable.

## Scoring rubric

Score each task on four axes, 0 to 3 each, and sum them to a total from 0 to 12.

| Axis | 0 | 1 | 2 | 3 |
|------|---|---|---|---|
| Files | one file | two or three | four to six | seven or more, or not enumerable |
| Spec completeness | complete code given verbatim | code given with small gaps | prose plus exact signatures | prose only, approach undecided |
| Coupling | self-contained, consumes nothing | consumes one interface from an earlier task | crosses a layer, or produces interfaces others depend on | changes a shared interface |
| Risk | additive, trivially revertible | localized behavior change | shared code path or data shape | security, data loss, migration, or concurrency |

## Assignment table

The total indexes this table directly. Two planners scoring a task identically
always reach the same agent.

```assignment
0 impl-haiku
1 impl-sonnet-low
2 impl-sonnet-medium
3 impl-sonnet-high
4 impl-sonnet-xhigh
5 impl-sonnet-max
6 impl-opus-low
7 impl-opus-medium
8 impl-opus-high
9 impl-opus-xhigh
10 impl-opus-max
11 impl-fable-xhigh
12 impl-fable-max
```

## Escalation table

Escalation changes model before it changes effort, because an implementer that
is stuck usually needs more capability rather than marginally more thinking.
`impl-fable-max` has no successor; a task that exhausts the ladder is reported
BLOCKED.

```escalation
impl-haiku impl-sonnet-high
impl-sonnet-low impl-opus-low
impl-sonnet-medium impl-opus-medium
impl-sonnet-high impl-opus-high
impl-sonnet-xhigh impl-opus-xhigh
impl-sonnet-max impl-opus-max
impl-opus-low impl-fable-low
impl-opus-medium impl-fable-medium
impl-opus-high impl-fable-high
impl-opus-xhigh impl-fable-xhigh
impl-opus-max impl-fable-max
impl-fable-low impl-fable-medium
impl-fable-medium impl-fable-high
impl-fable-high impl-fable-xhigh
impl-fable-xhigh impl-fable-max
impl-fable-max -
```

### Why this terminates

Rank each agent as `model_rank * 10 + effort_rank`, where Haiku ranks 0, Sonnet
1, Opus 2, and Fable 3, and effort ranks 0 through 4 from `low` to `max`. That
puts Haiku at 0, Sonnet at 10 to 14, Opus at 20 to 24, and Fable at 30 to 34.
Every successor has a strictly higher rank, so the graph is acyclic and every
walk ends at `impl-fable-max`. `tests/ladder.test.sh` asserts this by walking
the table rather than trusting the argument.

The three low-effort Fable agents are never assigned initially, since no score
reaches them, but they are reachable by escalation from their Opus
counterparts. All 16 agents are used.
