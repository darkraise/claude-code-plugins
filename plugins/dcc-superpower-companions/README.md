# dcc-superpower-companions

Extends [superpowers](https://github.com/obra/superpowers) so that every task in
an implementation plan records which implementer subagent runs it, chosen from a
grid of model and reasoning-effort pairings.

## Why

Superpowers already advises picking cheap, standard, or capable models per task.
Two things were missing.

`writing-plans` has no field for the choice, so the decision is invisible in the
plan and re-derived from memory at dispatch. And reasoning effort is unreachable
at dispatch time: the Agent tool exposes a `model` parameter but no `effort`
parameter, so effort can only be set in a subagent definition's frontmatter.
Superpowers dispatches the built-in `general-purpose` agent, so every implementer
runs at the session's effort level regardless of task difficulty.

This plugin ships pre-baked agent definitions, which makes effort reachable, and
two skills that write the choice into the plan and read it back.

## What you get

**16 implementer agents.** Sonnet 5, Opus 5, and Fable 5 at each of `low`,
`medium`, `high`, `xhigh`, and `max`, plus one Haiku 4.5 agent. Haiku carries no
effort field because Haiku does not support reasoning effort.

**A four-axis rubric.** Files touched, spec completeness, coupling, and risk,
each scored 0 to 3. The total from 0 to 12 indexes an assignment table, so two
planners scoring a task identically always reach the same agent.

**An escalation ladder.** Every agent has exactly one successor, changing model
before effort. Walks terminate at `impl-fable-max`. Used at superpowers' fix
rounds 4 and 5 and at its BLOCKED handler.

## How it fires

A `PreToolUse` hook on the `Skill` tool adds context when
`superpowers:writing-plans` or `superpowers:subagent-driven-development` is
invoked, and stays silent otherwise. It costs nothing in sessions that never
invoke those skills.

`superpowers:executing-plans` is deliberately not matched. It runs plan tasks
inline without subagents, so the `Implementer` lines are inert there, which is
correct rather than broken.

## What a plan looks like

```markdown
### Wire the export pipeline (Task 4)

**Files:**
- Create: `src/export/pipeline.ts`

**Interfaces:**
- Consumes: `formatRow(row: Row): string` from Task 2
- Produces: `runExport(cfg: Config): Promise<Report>`

**Implementer:** dcc-superpower-companions:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 2 - risk 2 = 8
```

Edit the `**Implementer:**` line to override. The dispatching skill obeys the
line and never recomputes when it is present.

## Compatibility

The plugin extends one seam: the implementer dispatch names a fleet agent
instead of `general-purpose` and passes no `model` argument. Everything else in
the superpowers loop is untouched, including the review stages, the five-round
cap, the breaker, and reviewer model selection.

It supersedes exactly one superpowers instruction, and only for implementer
dispatches: "always specify the model explicitly". Passing `model` would
override the agent file while `effort` kept its frontmatter value, producing
mismatched pairings. The intent survives, since the agent definition pins the
model.

## Tests

```bash
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do bash "$t"; done
```

Requires `jq`. No model calls.

## Reference

`reference/ladder.md` holds the rubric, the assignment table, and the escalation
table. Both skills and the test suite read that one copy.
