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

**Ten agents in two classes.** Seven implementers - Sonnet 5 and Opus 5 at
`low`, `medium`, and `high`, plus one Haiku 4.5 agent. Three read-only role
agents - `judge-fable`, its `judge-opus` fallback, and `scout-sonnet` - whose
`tools:` frontmatter omits `Edit`, `Write`, and `Agent`, so a reviewer that
cannot modify the tree or spawn subagents is a fact about the registry rather
than a request in a prompt.

`xhigh` and `max` are retired everywhere, and Fable never implements. Above
`impl-opus-high` the answer to a hard task is to split it, not to escalate it.

**A four-axis rubric that gates the plan.** Files, spec completeness, coupling,
and risk, each scored 0 to 3. Three of those four measure how the task was
drawn, not how hard the change is, so Rule S sends a task scoring 4 or more
across them back to be split rather than to a larger model. That cap is what
makes the assignment table stop at 6, which is exactly the seven implementers.

**An escalation ladder.** Every agent has exactly one successor, changing model
before effort. Walks terminate at a SPLIT action rather than an agent. Used at
superpowers' fix rounds 4 and 5 and at its BLOCKED handler.

**Criteria-scored reviews.** `criteria/` holds narrow scored criteria adapted
from LLM-as-a-Verifier (arXiv:2607.05391): a ground-truth note the judge sees on
every evaluation, and 2 to 4 criteria that each say where to look, what scores
high, what scores low, and what to ignore. Reviews return a 1-to-20 score per
criterion alongside superpowers' own verdicts - alongside, never replacing them,
because its fix loop keys on those verdicts. Risk-3 tasks are scored three times
and averaged, and a spread above 6 points sends the diff to the controller
instead of to the mean.

**Best-of-3 approach selection.** `selecting-approaches` gates an open approach
decision to inline, one advisory pass, or three scouts ranked by a judge in a
ring pass that cancels positional bias. Five numbered skip conditions send most
decisions to inline, including bug fixes with a located root cause - where
ranking candidates generated before the root cause is known would launder
guesses into a confident pick.

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

`criteria/` holds the verifier criteria; `criteria/TEMPLATE.md` documents the
format. `tests/criteria.test.sh` validates every file in that directory.
