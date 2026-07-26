# dcc-superpower-companions — Design

Date: 2026-07-27
Status: APPROVED — ready for implementation planning

## Goal

Let a superpowers plan record, per task, which implementer subagent will run it —
chosen from a grid of model and reasoning-effort pairings — so that model and
effort selection becomes an auditable property of the plan document rather than a
judgment call made from memory at dispatch time.

## The gap this fills

Superpowers already selects models. `subagent-driven-development` has a Model
Selection section advising cheap, standard, and capable tiers, and its fix loop
escalates on rounds 4 and 5. But two things are missing:

1. **`writing-plans` has no field for the choice.** The task template defines
   `Files`, `Interfaces`, and steps. Nothing records which agent runs the task, so
   the decision is invisible in the plan and re-derived from memory at dispatch.
2. **Effort is unreachable at dispatch time.** The Agent tool exposes a `model`
   parameter but no `effort` parameter. Reasoning effort can only be set in a
   subagent definition's frontmatter. Superpowers dispatches the built-in
   `general-purpose` agent, so every implementer runs at the session's effort
   level regardless of task difficulty.

This plugin closes both: a fleet of pre-baked agent definitions makes effort
reachable, and two companion skills write the choice into the plan and read it
back at dispatch.

## Verified platform facts

Each was confirmed against the Claude Code documentation or observed directly on
2026-07-27. They are load-bearing; re-verify before changing anything that rests
on them.

| Fact | Source |
|------|--------|
| Subagent frontmatter supports `effort: low\|medium\|high\|xhigh\|max` | Subagents doc, supported frontmatter fields |
| The Agent tool has `model` but no `effort` parameter | Agent tool schema |
| A dispatch-time `model` argument overrides the agent file's `model` frontmatter | Agent tool schema |
| Fable 5, Opus 5, and Sonnet 5 support all five effort levels | Model config doc, effort table |
| Haiku 4.5 is absent from that table, and models not listed do not support effort | Model config doc |
| Plugin subagents are namespaced `<plugin>:<agent>` for `subagent_type` | Observed in the session agent registry |
| Plugin subagents ignore `hooks`, `mcpServers`, and `permissionMode` frontmatter | Subagents doc |
| `PreToolUse` supports `hookSpecificOutput.additionalContext` | Hooks doc, PreToolUse decision control |
| The Skill tool passes the qualified skill name as `tool_input.skill` | Observed in a session transcript |
| Injected context must read as factual statements, not imperative commands, or it can trip prompt-injection defenses | Hooks doc, "Add context for Claude" |
| `isolation: worktree` branches from the default branch, not the session's HEAD | Worktrees doc |
| `scripts/task-brief` copies a task block verbatim from its heading to the next | Read from the superpowers source |

## Decisions

| Question | Decision | Why |
|----------|----------|-----|
| How the plugin reaches superpowers | Companion skills, triggered by a targeted `PreToolUse` hook | Superpowers ships read-only in the plugin cache and cannot be edited. Skills alone fire on model judgment; the hook makes it deterministic while costing nothing in sessions that never invoke those skills |
| Fleet size | Full grid: 16 agents | Three effort-capable models at five levels each, plus one effort-less Haiku |
| Role scope | Implementers only, plus an explicit escalation ordering | Reviewers keep superpowers' own model selection. The ordering turns "one tier above" from a judgment call into a lookup |
| Agent body | Thin role statement, one preloaded skill | Superpowers stays the single source of process truth, so nothing drifts when it updates |
| Assignment method | Four scored axes summing to a table index, with the scores recorded in the plan | Deterministic and auditable: the same task scored the same way always yields the same agent, and a reader can argue with the reasoning |

## Architecture

The plan document is the only state. Superpowers brainstorms and plans as it
always does; the assigning skill adds two lines per task; the plan is committed
and becomes the carrier. Later — same session or not — the dispatching skill
reads those lines back and turns each into a `subagent_type`. Nothing is held in
memory between planning and execution, so a plan written today still dispatches
correctly next month, and a plan written without the plugin still works because
the dispatch skill scores any task missing an assignment.

```
plugins/dcc-superpower-companions/
  .claude-plugin/plugin.json
  agents/impl-*.md                              16 definitions
  skills/assigning-implementers/SKILL.md        scores tasks, writes the assignment
  skills/dispatching-tiered-implementers/SKILL.md   reads it, dispatches, escalates
  reference/ladder.md                           scoring + escalation tables, one copy
  hooks/hooks.json                              PreToolUse matching the Skill tool
  scripts/tier-nudge.sh                         emits context for two skill names only
  tests/*.test.sh
  README.md
```

`reference/ladder.md` holds both tables so the two skills and the test suite read
one copy. A second copy would drift.

## The fleet

Sixteen agents in total: fifteen named `impl-<model>-<effort>`, plus `impl-haiku`,
which carries no effort field because Haiku does not support one.

|          | low | medium | high | xhigh | max |
|----------|-----|--------|------|-------|-----|
| `sonnet` | ● | ● | ● | ● | ● |
| `opus`   | ● | ● | ● | ● | ● |
| `fable`  | ● | ● | ● | ● | ● |
| `haiku`  | — effort not supported — |

Every file follows one template, differing only in `name`, `model`, `effort`,
`color`, and the sentence naming its intended task class:

```markdown
---
name: impl-opus-high
description: Task implementer running Opus 5 at high effort. Dispatched by
  dcc-superpower-companions for plan tasks scoring 8 on the assignment rubric.
model: opus
effort: high
skills:
  - superpowers:verification-before-completion
color: purple
---

You are a task implementer. Your dispatch prompt carries the task brief path,
the report file path, and the report contract. It is your complete instruction
set; follow it exactly.

You run on Opus 5 at high effort. The brief governs test strategy — apply TDD
when the brief's steps call for it, not by default.
```

Three frontmatter choices are deliberate:

- **`tools` is omitted**, so implementers inherit every tool available to
  subagents. This matches the `general-purpose` agent superpowers dispatches today.
- **`isolation` is never set.** It would branch from the default branch rather
  than the session's HEAD, putting implementers on stale code. Superpowers already
  creates the worktree at the controller level.
- **Only `verification-before-completion` is preloaded.** Preloading the TDD skill
  into all sixteen would push TDD onto tasks whose briefs do not ask for it,
  contradicting the dispatch prompt's "implement exactly what the task specifies".
  TDD already lives in the plan's own steps.

## The assignment rubric

Four axes, each scored 0 to 3, summed to a total from 0 to 12.

| Axis | 0 | 1 | 2 | 3 |
|------|---|---|---|---|
| **Files** | one file | two or three | four to six | seven or more, or not enumerable |
| **Spec completeness** | complete code given verbatim | code given with small gaps | prose plus exact signatures | prose only, approach undecided |
| **Coupling** | self-contained, consumes nothing | consumes one interface from an earlier task | crosses a layer, or produces interfaces others depend on | changes a shared interface |
| **Risk** | additive, trivially revertible | localized behavior change | shared code path or data shape | security, data loss, migration, or concurrency |

The total indexes the assignment table directly. Every score maps to exactly one
agent, so two planners scoring a task identically always reach the same agent.

| Score | Agent | Score | Agent |
|-------|-------|-------|-------|
| 0 | `impl-haiku` | 7 | `impl-opus-medium` |
| 1 | `impl-sonnet-low` | 8 | `impl-opus-high` |
| 2 | `impl-sonnet-medium` | 9 | `impl-opus-xhigh` |
| 3 | `impl-sonnet-high` | 10 | `impl-opus-max` |
| 4 | `impl-sonnet-xhigh` | 11 | `impl-fable-xhigh` |
| 5 | `impl-sonnet-max` | 12 | `impl-fable-max` |
| 6 | `impl-opus-low` | | |

## The escalation ladder

Escalation changes model before it changes effort, because an implementer that is
stuck usually needs more capability rather than marginally more thinking.

| From | To | From | To |
|------|----|------|----|
| `impl-haiku` | `impl-sonnet-high` | `impl-opus-low` | `impl-fable-low` |
| `impl-sonnet-low` | `impl-opus-low` | `impl-opus-medium` | `impl-fable-medium` |
| `impl-sonnet-medium` | `impl-opus-medium` | `impl-opus-high` | `impl-fable-high` |
| `impl-sonnet-high` | `impl-opus-high` | `impl-opus-xhigh` | `impl-fable-xhigh` |
| `impl-sonnet-xhigh` | `impl-opus-xhigh` | `impl-opus-max` | `impl-fable-max` |
| `impl-sonnet-max` | `impl-opus-max` | `impl-fable-low` | `impl-fable-medium` |
| `impl-fable-medium` | `impl-fable-high` | `impl-fable-high` | `impl-fable-xhigh` |
| `impl-fable-xhigh` | `impl-fable-max` | `impl-fable-max` | none — report BLOCKED |

Rank each agent as `model_rank × 10 + effort_rank`, where Haiku ranks 0, Sonnet 1,
Opus 2, and Fable 3, and effort ranks 0 through 4 from `low` to `max`. That puts
Haiku at 0, Sonnet at 10 to 14, Opus at 20 to 24, and Fable at 30 to 34. Every
successor has a strictly higher rank, which makes the graph acyclic and guarantees
termination at `impl-fable-max`. The test suite asserts this rather than trusting
it.

The three low-effort Fable agents are never assigned initially — no score reaches
them — but they are reachable by escalation from their Opus counterparts. All
sixteen agents are used.

Escalation applies at exactly two points, both defined by superpowers:

- **Fix rounds 4 and 5**, where superpowers calls for a fresh implementer on a
  more capable model.
- **The BLOCKED handler**, where superpowers says to re-dispatch on a more capable
  model when the task requires more reasoning.

It does **not** apply to fix rounds 1 to 3, which resume the original agent.
Resuming preserves its model, its effort, and its context; re-dispatching a
different tier there would discard exactly what superpowers is preserving.

## Plan document changes

Each task block gains two lines below the `Interfaces` block:

```markdown
**Implementer:** dcc-superpower-companions:impl-opus-high
**Evaluation:** files 2 · spec 2 · coupling 2 · risk 2 = 8
```

The agent name is fully qualified because plugin subagents are namespaced, and an
unqualified name may not resolve.

The plan header gains one appended line. It is appended, never substituted — the
existing `REQUIRED SUB-SKILL` line is what hands off to
`subagent-driven-development`, and replacing it would break the handoff:

```markdown
> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. REQUIRED SUB-SKILL:
> dcc-superpower-companions:dispatching-tiered-implementers
```

**Overriding** is editing the `Implementer` line by hand. The dispatch skill obeys
that line and never recomputes when it is present, so a human ruling always wins
over the rubric.

`scripts/task-brief` copies a task block verbatim, so both lines appear in the
brief the implementer reads. This is accepted, not worked around: an implementer
knowing its task's blast radius is useful context, and moving the assignment out
of the task block would let it desync when tasks are renumbered.

## Trigger mechanism

`hooks/hooks.json` registers one `PreToolUse` hook matching the `Skill` tool.
`scripts/tier-nudge.sh` reads the hook payload, inspects `tool_input.skill`, and
responds to exactly two values:

| Invoked skill | Response |
|---------------|----------|
| `superpowers:writing-plans` | `defer` plus context naming the assigning skill |
| `superpowers:subagent-driven-development` | `defer` plus context naming the dispatching skill |
| anything else | exit 0, no output, no effect |

`permissionDecision` is always `defer`, so the invoked skill runs normally and the
hook only adds context. The context text is phrased as factual project
information — "Plans in this project record an implementer assignment for each
task" — rather than as an instruction, because command-framed injected text can
trip prompt-injection defenses and be surfaced to the user instead of acted on.

`superpowers:executing-plans` is deliberately **not** matched. It executes tasks
inline in the current session without subagents, so nudging it toward tiered
dispatch would push it to do the one thing it is designed not to do. Under that
skill the `Implementer` lines are inert, which is correct rather than broken.

## Superpowers compatibility contract

The plugin extends one seam and leaves the rest of the loop untouched. This
section is the checklist that keeps it that way.

**What changes.** Exactly one thing: the implementer dispatch names a fleet agent
as `subagent_type` instead of `general-purpose`, and passes no `model` argument.

**What does not change.** The brief and report file protocol, the review package,
the task reviewer, the scoped re-review, the five-round cap, the breaker and its
adjudication rules, the final whole-branch review, and the handoff to
`finishing-a-development-branch`. Reviewer model selection stays superpowers'.

**The one instruction this plugin supersedes.** Superpowers states in bold that
you must always specify the model explicitly when dispatching a subagent, because
an omitted model inherits the session's model. For implementer dispatches only,
that is superseded: passing `model` overrides the agent file's model while `effort`
keeps its frontmatter value, producing a mismatched pairing such as Sonnet running
at xhigh. The rule's intent survives — the agent definition pins the model, so
nothing inherits the session default. It remains in force for every other
dispatch.

**Ledger discipline.** Superpowers owns
`.superpowers/sdd/<plan-basename>/progress.md` and its crash-recovery logic keys
on lines matching `Task <N>: complete`. Assignment and escalation notes append to
that same ledger — never a competing one — and never use the reserved verbs
`complete`, `fix round`, `parked`, or `BLOCKED` in their own lines. The permitted
form is `Task <N>: implementer <agent> (<reason>)`.

**Parallelism.** Unchanged. Superpowers forbids dispatching implementers in
parallel because they conflict, and nothing here relaxes that.

## Failure modes

| Situation | Response |
|-----------|----------|
| Task has no `Implementer` line | Score it inline with the same rubric, dispatch, and record that it was scored on the fly |
| Line names an agent that does not exist | Stop and ask. Never fall back silently |
| Escalation exhausted at `impl-fable-max` | Report BLOCKED, per superpowers' existing contract |
| Model unavailable on the account | Substitute the same effort one model down, state the substitution in the report, continue |
| Dispatch about to pass `model` | Forbidden for implementers. `subagent_type` only |
| Agent frontmatter tempted toward `isolation` | Never set it |

The silent-fallback rule matters more than it appears. If a bad agent name quietly
degraded to the session default, every task would run at the session's model and
effort and nothing in the output would reveal it — precisely the expensive-model
failure superpowers warns about.

The unavailable-model row exists because Fable is not on every account. The
substitution drops the model one rung and keeps the effort, and must be stated
rather than applied silently.

## Testing

A bash suite in the style of `plugins/telegram-notify/tests/`. All of it runs
without invoking a model.

1. **Fleet completeness** — exactly sixteen agent files exist and their name set
   equals the expected grid.
2. **Frontmatter validity** — each file's `name` matches its filename; `model` is
   in the allowlist; `effort` is present and valid for Sonnet, Opus, and Fable,
   and absent for Haiku.
3. **Assignment table** — scores 0 through 12 are all present and each names an
   agent that exists.
4. **Escalation table** — every agent except `impl-fable-max` has exactly one
   successor; every successor exists; following successors from any starting
   agent terminates at `impl-fable-max` without revisiting an agent.
5. **Hook script** — given synthetic stdin for `superpowers:writing-plans`, it
   emits valid JSON with `permissionDecision: "defer"` and non-empty
   `additionalContext`; given `superpowers:executing-plans` or an unrelated skill,
   it emits nothing and exits 0.
6. **Manifest** — `claude plugin validate .` passes.

## Out of scope

Reviewer and final-review tiering; a budget mode that shifts the whole ladder;
tiering for `executing-plans`; and any modification to superpowers itself.

## Repository integration

- Directory `plugins/dcc-superpower-companions/`, satisfying the `dcc-` prefix
  rule in `CLAUDE.md`.
- An entry in `.claude-plugin/marketplace.json` whose `name` matches the manifest
  and the directory.
- A row in the README's plugin table.

Note: the three existing plugins (`telegram-notify`, `example-plugin`,
`darkmem-resume`) predate the `dcc-` rule and do not carry the prefix. Renaming
`telegram-notify` would break existing installs, so they are left as-is; migrating
them is a separate decision.
