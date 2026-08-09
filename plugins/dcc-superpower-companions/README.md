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
planners scoring a task identically always reach the same agent. In practice
initial assignments cluster in the 2 to 8 band, because a plan written to
superpowers' no-placeholders rule scores near zero on spec completeness by
construction; the top rungs are reached by escalation.

**An escalation ladder.** Every agent has exactly one successor, changing model
before effort. Walks terminate at `impl-fable-max`. Used at superpowers' fix
rounds 4 and 5 and at its BLOCKED handler.

## Requirements

**superpowers must be installed.** This plugin has no standalone use, and the
coupling is harder than "it extends superpowers": every agent definition
preloads `superpowers:verification-before-completion` through its `skills:`
frontmatter, and both companion skills defer to superpowers' `sdd-workspace`,
`task-brief`, and `review-package` scripts. Claude Code plugin manifests cannot
declare a dependency on another plugin, so nothing enforces this — with
superpowers absent, the fleet loads without its preloaded skill and the
dispatch instructions point at scripts that are not there.

**`bash` and `jq`** for the hook. If `jq` is missing the hook degrades to a
silent no-op; `bash` is required for it to run at all. On Windows that means
Git for Windows. The hook declares `"shell": "bash"` so it takes the Git Bash
route explicitly: without that key Claude Code falls back to PowerShell on a
machine with no Git Bash, where the command is meaningless, and with it the
user gets Claude Code's actionable "requires bash but Git Bash was not found"
message instead.

## How it fires

A `PreToolUse` hook on the `Skill` tool adds context when
`superpowers:writing-plans` or `superpowers:subagent-driven-development` is
invoked, and stays silent otherwise. The matcher is the tool name, so the
script does run — and exits without output — on every `Skill` invocation of any
kind. That is one `bash` plus one `jq` per skill call, not zero.

The hook returns `additionalContext` and no `permissionDecision`. It has no
opinion on whether the skill may run, and `defer` in particular would be
actively wrong: it is print-mode only, ignored with a warning in an interactive
session, and in a non-interactive one it defers the `Skill` call itself so the
skill never executes.

`superpowers:executing-plans` is deliberately not matched. It runs plan tasks
inline without subagents, so the `Implementer` lines are inert there, which is
correct rather than broken.

## What a plan looks like

```markdown
### Task 4: Wire the export pipeline

**Files:**
- Create: `src/export/pipeline.ts`

**Interfaces:**
- Consumes: `formatRow(row: Row): string` from Task 2
- Produces: `runExport(cfg: Config): Promise<Report>`

**Implementer:** dcc-superpower-companions:impl-opus-medium
**Evaluation:** files 2 - spec 1 - coupling 2 - risk 2 = 7
```

Edit the `**Implementer:**` line to override. The dispatching skill obeys the
line and never recomputes when it is present.

The heading keeps superpowers' `### Task N: <name>` form on purpose.
`scripts/task-brief` finds a task by matching a heading that starts with
`Task <N>`, so a heading like `### Wire the export pipeline (Task 4)` yields an
empty brief and a non-zero exit — and, because the extractor keeps copying
until the next heading it recognizes, quietly appends that task's body to the
previous task's brief.

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
