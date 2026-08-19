# dcc-superpower-companions 0.2.0 Verifier Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. When executing with
> superpowers:subagent-driven-development, REQUIRED SUB-SKILL:
> dcc-superpower-companions:dispatching-tiered-implementers. Under
> superpowers:executing-plans these lines are inert; ignore them.

**Goal:** Turn the task-scoring rubric into a decomposition gate, cut the fleet from 16 agents to 10, and add a criteria-based scored verification layer adapted from LLM-as-a-Verifier.

**Architecture:** Three reducible rubric axes become a split trigger (Rule S) whose arithmetic caps the assignment table at 6, which is exactly the seven surviving implementers. Fable leaves execution and becomes a read-only judge alongside an Opus fallback and a Sonnet scout. A `criteria/` directory supplies narrow scored criteria to reviews and to a new pairwise approach-selection skill.

**Tech Stack:** Markdown agent definitions and skills, `bash` + `jq` test suites, JSON plugin manifests. No model calls in tests.

**Spec:** `docs/superpowers/specs/2026-08-19-companions-verifier-redesign-design.md`

## Global Constraints

- Plugin name stays `dcc-superpower-companions`; the `dcc-` prefix and the three
  name locations (directory, `plugin.json`, `marketplace.json`) must agree.
- `claude plugin validate .` must pass before any commit that touches a manifest.
- Version becomes `0.2.0` in `plugins/dcc-superpower-companions/.claude-plugin/plugin.json`.
- All plugin file content is ASCII only — `fleet.test.sh` asserts this and the
  existing suites will fail on a smart quote or an em dash.
- English only, in code, comments, docs, commits, and tests.
- Commits follow `<type>(<scope>): <subject>`, subject 50 characters or fewer,
  imperative, no trailing period. Scope is `companions`.
- Tests must not make model calls. `bash` and `jq` only.
- **Bootstrap constraint:** no task in this plan may be dispatched to an agent
  this plan deletes. Every `**Implementer:**` line below names one of the seven
  agents that survive Task 1, and all seven already exist in 0.1.0, so the plan
  is executable at every point during its own execution.
- Run the full suite from the repository root:
  `for t in plugins/dcc-superpower-companions/tests/*.test.sh; do bash "$t"; done`

---

### Task 1: Retire nine agents and re-describe the survivors

**Files:**
- Delete: `plugins/dcc-superpower-companions/agents/impl-fable-low.md`
- Delete: `plugins/dcc-superpower-companions/agents/impl-fable-medium.md`
- Delete: `plugins/dcc-superpower-companions/agents/impl-fable-high.md`
- Delete: `plugins/dcc-superpower-companions/agents/impl-fable-xhigh.md`
- Delete: `plugins/dcc-superpower-companions/agents/impl-fable-max.md`
- Delete: `plugins/dcc-superpower-companions/agents/impl-sonnet-xhigh.md`
- Delete: `plugins/dcc-superpower-companions/agents/impl-sonnet-max.md`
- Delete: `plugins/dcc-superpower-companions/agents/impl-opus-xhigh.md`
- Delete: `plugins/dcc-superpower-companions/agents/impl-opus-max.md`
- Modify: `plugins/dcc-superpower-companions/agents/impl-opus-low.md`
- Modify: `plugins/dcc-superpower-companions/agents/impl-opus-medium.md`
- Modify: `plugins/dcc-superpower-companions/agents/impl-opus-high.md`

**Interfaces:**
- Consumes: nothing
- Produces: the seven-agent implementer fleet `impl-haiku`,
  `impl-sonnet-low`, `impl-sonnet-medium`, `impl-sonnet-high`, `impl-opus-low`,
  `impl-opus-medium`, `impl-opus-high`. Tasks 3 and 4 assert on this exact set.

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1
**Approach:** inline — skip 2: deletions and description edits follow the file shape already established in 0.1.0

The four Sonnet and Haiku descriptions already state scores 0 to 3, which the
new assignment table keeps unchanged. Only the three Opus descriptions move.

- [ ] **Step 1: Delete the nine retired agent definitions**

```bash
cd plugins/dcc-superpower-companions/agents
git rm impl-fable-low.md impl-fable-medium.md impl-fable-high.md \
       impl-fable-xhigh.md impl-fable-max.md \
       impl-sonnet-xhigh.md impl-sonnet-max.md \
       impl-opus-xhigh.md impl-opus-max.md
```

- [ ] **Step 2: Verify exactly seven agent files remain**

Run: `ls plugins/dcc-superpower-companions/agents/*.md | wc -l`
Expected: `7`

- [ ] **Step 3: Re-describe impl-opus-low**

In `plugins/dcc-superpower-companions/agents/impl-opus-low.md`, replace the
`description:` line with:

```yaml
description: "Task implementer running Opus 5 at low effort. Dispatched by dcc-superpower-companions for score 4: work whose reducible axes are exhausted and whose risk is real."
```

- [ ] **Step 4: Re-describe impl-opus-medium**

In `plugins/dcc-superpower-companions/agents/impl-opus-medium.md`, replace the
`description:` line with:

```yaml
description: "Task implementer running Opus 5 at medium effort. Dispatched by dcc-superpower-companions for score 5: coupled work carrying a shared-path or data-shape risk."
```

- [ ] **Step 5: Re-describe impl-opus-high and note the terminal rung**

In `plugins/dcc-superpower-companions/agents/impl-opus-high.md`, replace the
`description:` line with:

```yaml
description: "Task implementer running Opus 5 at high effort. Dispatched by dcc-superpower-companions for score 6: the top execution rung, above which a task is split rather than escalated."
```

Then replace the final paragraph of the body:

```markdown
If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. You are the
top rung of the execution ladder: there is no more capable implementer
above you, so the controller responds by splitting the remaining work
into smaller tasks and dispatching them fresh.
```

- [ ] **Step 6: Verify no retired effort or model survives**

Run:
```bash
grep -l 'effort: xhigh\|effort: max\|model: fable' plugins/dcc-superpower-companions/agents/*.md
```
Expected: no output, exit status 1.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-superpower-companions/agents
git commit -m "refactor(companions): retire xhigh, max, and fable tiers"
```

---

### Task 2: Add the three read-only role agents

**Files:**
- Create: `plugins/dcc-superpower-companions/agents/judge-fable.md`
- Create: `plugins/dcc-superpower-companions/agents/judge-opus.md`
- Create: `plugins/dcc-superpower-companions/agents/scout-sonnet.md`

**Interfaces:**
- Consumes: nothing
- Produces: agent names `judge-fable`, `judge-opus`, `scout-sonnet`, each with
  the exact toolset `Read, Grep, Glob, WebFetch`. Task 4 asserts the toolset
  string verbatim; Tasks 8 and 9 dispatch these names.

**Implementer:** dcc-superpower-companions:impl-haiku
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
**Approach:** inline — skip 5: one file shape, complete content supplied, no second candidate exists

These three carry no `skills:` preload. `verification-before-completion` is an
implementer's discipline about claiming completion; a judge produces a verdict,
not a completion claim.

- [ ] **Step 1: Create judge-fable.md**

```markdown
---
name: judge-fable
description: "Read-only verifier and approach ranker running Fable 5 at high effort. Dispatched by dcc-superpower-companions to score a task review against criteria, or to rank candidate approaches pairwise."
model: fable
effort: high
tools: Read, Grep, Glob, WebFetch
color: yellow
---

You are a judge. Your dispatch prompt carries every input you need: the
paths to read, the criteria to apply, and the exact output format. It is
your complete instruction set; follow it exactly.

You run on Fable 5 at high effort.

You cannot modify files and you cannot dispatch subagents. Both are
deliberate. Your verdict is the whole of your output.

Score against the criteria you were given and nothing else. When a
criterion tells you to ignore something, ignoring it is part of scoring
correctly. If an input you were told to read is missing or unreadable,
say so plainly and score what you can; never infer the contents of a
file you could not open.
```

- [ ] **Step 2: Create judge-opus.md**

```markdown
---
name: judge-opus
description: "Read-only verifier and approach ranker running Opus 5 at high effort. Dispatched by dcc-superpower-companions in place of judge-fable when Fable is unavailable or declined."
model: opus
effort: high
tools: Read, Grep, Glob, WebFetch
color: yellow
---

You are a judge. Your dispatch prompt carries every input you need: the
paths to read, the criteria to apply, and the exact output format. It is
your complete instruction set; follow it exactly.

You run on Opus 5 at high effort.

You cannot modify files and you cannot dispatch subagents. Both are
deliberate. Your verdict is the whole of your output.

Score against the criteria you were given and nothing else. When a
criterion tells you to ignore something, ignoring it is part of scoring
correctly. If an input you were told to read is missing or unreadable,
say so plainly and score what you can; never infer the contents of a
file you could not open.
```

- [ ] **Step 3: Create scout-sonnet.md**

```markdown
---
name: scout-sonnet
description: "Read-only approach drafter running Sonnet 5 at medium effort. Dispatched by dcc-superpower-companions to draft one candidate approach for pairwise ranking."
model: sonnet
effort: medium
tools: Read, Grep, Glob, WebFetch
color: green
---

You are an approach scout. Your dispatch prompt names one decision and
asks you for one candidate approach to it. It is your complete
instruction set; follow it exactly.

You run on Sonnet 5 at medium effort.

You cannot modify files and you cannot dispatch subagents. You produce a
proposal, never an implementation.

Draft one approach and commit to it. Do not hedge across several
options, do not rank yourself against approaches you imagine others are
drafting, and do not water the proposal down to whatever seems safest.
A judge compares your proposal against the others; a proposal that
tries to be all of them gives it nothing to compare.

State the approach, the files it would touch, what it makes easy, what
it makes hard, and the one thing most likely to go wrong with it.
```

- [ ] **Step 4: Verify the fleet is now ten agents with correct frontmatter**

Run:
```bash
ls plugins/dcc-superpower-companions/agents/*.md | wc -l
grep -c '^tools: Read, Grep, Glob, WebFetch$' plugins/dcc-superpower-companions/agents/*.md | grep -v ':0'
```
Expected: `10`, then exactly three files each reporting `:1` —
`judge-fable.md`, `judge-opus.md`, `scout-sonnet.md`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-superpower-companions/agents
git commit -m "feat(companions): add read-only judge and scout agents"
```

---

### Task 3: Rewrite the ladder reference and its test suite

**Files:**
- Modify: `plugins/dcc-superpower-companions/tests/ladder.test.sh`
- Modify: `plugins/dcc-superpower-companions/reference/ladder.md`

**Interfaces:**
- Consumes: the ten agent files from Tasks 1 and 2
- Produces: three machine-readable fenced blocks in `reference/ladder.md` —
  ` ```assignment ` (7 rows, scores 0 to 6), ` ```escalation ` (7 rows,
  terminal `SPLIT`), and ` ```retired ` (9 rows). Tasks 7, 8, and 9 read these
  tables at runtime rather than restating them.

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4
**Approach:** advisor — load-bearing (three downstream consumers read these tables), one plausible shape given 0.1.0's existing fenced-block format

Test first: the suite is rewritten before the data it checks, so the new
expectations are seen failing against the old tables.

- [ ] **Step 1: Rewrite ladder.test.sh for the new tables**

Replace the whole file with:

```bash
#!/usr/bin/env bash
# The ladder tables are data the skills read at runtime, so their integrity is
# checkable without a model. The escalation graph must terminate: every agent
# ranks strictly below its successor, so walking successors can never cycle and
# must end at the SPLIT action, which is not an agent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
AGENTS="$HERE/../agents"

IMPLEMENTERS="impl-haiku impl-opus-high impl-opus-low impl-opus-medium impl-sonnet-high impl-sonnet-low impl-sonnet-medium"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# block <tag> - print the body of the fenced block opened by ```<tag>
block() {
  awk -v tag="$1" '
    $0 == "```" tag { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER"
}

agent_exists() { [ -f "$AGENTS/$1.md" ]; }

check "ladder.md exists" "$([ -f "$LADDER" ] && echo yes || echo no)" "yes"

# --- assignment table -------------------------------------------------------
assignment=$(block assignment)
check "assignment table has 7 rows" "$(printf '%s\n' "$assignment" | grep -c .)" "7"

seen_scores=""
bad_score=NONE
bad_agent=NONE
while read -r score agent; do
  [ -n "$score" ] || continue
  case " $seen_scores " in *" $score "*) bad_score="duplicate:$score" ;; esac
  seen_scores="$seen_scores $score"
  agent_exists "$agent" || bad_agent="$agent"
done <<< "$assignment"

check "assignment scores are unique" "$bad_score" "NONE"
check "every assigned agent has a definition file" "$bad_agent" "NONE"

missing=NONE
for s in 0 1 2 3 4 5 6; do
  case " $seen_scores " in *" $s "*) ;; *) missing="$s" ;; esac
done
check "assignment covers every score 0 through 6" "$missing" "NONE"

# Rule S caps a compliant total at 6. A row above it would mean the split gate
# is bypassable by scoring, which is the defect the gate exists to remove.
above=$(printf '%s\n' "$assignment" | awk 'NF && $1 > 6 {print $1}' | tr '\n' ' ' | sed 's/ $//')
check "assignment has no row above score 6" "${above:-NONE}" "NONE"

# --- escalation table -------------------------------------------------------
escalation=$(block escalation)
check "escalation table has 7 rows" "$(printf '%s\n' "$escalation" | grep -c .)" "7"

bad_from=NONE
bad_to=NONE
terminals=""
while read -r from to; do
  [ -n "$from" ] || continue
  agent_exists "$from" || bad_from="$from"
  if [ "$to" = "SPLIT" ]; then
    terminals="$terminals $from"
  else
    agent_exists "$to" || bad_to="$to"
  fi
done <<< "$escalation"

check "every escalation source has a definition file" "$bad_from" "NONE"
check "every escalation target has a definition file" "$bad_to" "NONE"
check "exactly one terminal rung, and it is impl-opus-high" \
  "$(echo $terminals)" "impl-opus-high"

sources=$(printf '%s\n' "$escalation" | awk 'NF {print $1}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "every implementer appears exactly once as an escalation source" "$sources" "$IMPLEMENTERS"

# Judges and scouts are not on the ladder; they are never escalation targets.
offladder=$(printf '%s\n' "$escalation" | awk 'NF {print $1; print $2}' | grep -E '^(judge|scout)-' | tr '\n' ' ' | sed 's/ $//')
check "no judge or scout appears in the escalation table" "${offladder:-NONE}" "NONE"

# --- rank monotonicity ------------------------------------------------------
rank() { # rank <agent> - model_rank * 10 + effort_rank
  case "$1" in
    impl-haiku) echo 0; return ;;
    impl-sonnet-*) m=10 ;;
    impl-opus-*) m=20 ;;
    *) echo -1; return ;;
  esac
  case "${1##*-}" in
    low) e=0 ;; medium) e=1 ;; high) e=2 ;; *) echo -1; return ;;
  esac
  echo $((m + e))
}

bad_rank=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  [ "$to" = "SPLIT" ] && continue
  rf=$(rank "$from"); rt=$(rank "$to")
  if [ "$rf" -lt 0 ] || [ "$rt" -lt 0 ]; then bad_rank="unrankable:$from->$to"; break; fi
  if [ "$rt" -le "$rf" ]; then bad_rank="not-increasing:$from($rf)->$to($rt)"; break; fi
done <<< "$escalation"
check "every escalation strictly increases rank" "$bad_rank" "NONE"

# --- termination ------------------------------------------------------------
successor() { printf '%s\n' "$escalation" | awk -v a="$1" 'NF && $1 == a {print $2; exit}'; }

bad_walk=NONE
for start in $IMPLEMENTERS; do
  cur="$start"; steps=0; visited=""
  while [ "$cur" != "SPLIT" ]; do
    case " $visited " in *" $cur "*) bad_walk="cycle-at:$cur"; break ;; esac
    visited="$visited $cur"
    steps=$((steps + 1))
    if [ "$steps" -gt 20 ]; then bad_walk="runaway-from:$start"; break; fi
    cur=$(successor "$cur")
    [ -n "$cur" ] || { bad_walk="dead-end-from:$start"; break; }
  done
  [ "$bad_walk" = NONE ] || break
done
check "escalation from every implementer reaches SPLIT without cycling" "$bad_walk" "NONE"

# --- retired-agent map ------------------------------------------------------
retired=$(block retired)
check "retired map has 9 rows" "$(printf '%s\n' "$retired" | grep -c .)" "9"

RETIRED_NAMES="impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-opus-max impl-opus-xhigh impl-sonnet-max impl-sonnet-xhigh"

retired_sources=$(printf '%s\n' "$retired" | awk 'NF {print $1}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "retired map covers exactly the nine deleted agents" "$retired_sources" "$RETIRED_NAMES"

bad_target=NONE
still_present=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  agent_exists "$from" && still_present="$from"
  agent_exists "$to" || bad_target="$to"
done <<< "$retired"
check "every retired target has a definition file" "$bad_target" "NONE"
check "no retired name still has a definition file" "$still_present" "NONE"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the suite to verify it fails against the old tables**

Run: `bash plugins/dcc-superpower-companions/tests/ladder.test.sh`
Expected: FAIL, including `assignment table has 7 rows` (got 13) and
`retired map has 9 rows` (got 0).

- [ ] **Step 3: Rewrite reference/ladder.md**

Replace the whole file with:

````markdown
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
````

- [ ] **Step 4: Run the suite to verify it passes**

Run: `bash plugins/dcc-superpower-companions/tests/ladder.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-superpower-companions/reference/ladder.md \
        plugins/dcc-superpower-companions/tests/ladder.test.sh
git commit -m "feat(companions): add split gate and retired-agent map"
```

---

### Task 4: Update the fleet test for ten agents and two agent classes

**Files:**
- Modify: `plugins/dcc-superpower-companions/tests/fleet.test.sh`

**Interfaces:**
- Consumes: the ten agent files from Tasks 1 and 2
- Produces: nothing other tasks read

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
**Approach:** inline — skip 2: extends the existing suite's `check`/`fm` idiom

The existing suite asserts every agent sets no `tools:` and that `effort` matches
the filename suffix. Both are now false for the role agents, so the per-file loop
gains a class branch.

- [ ] **Step 1: Replace the expected-fleet constant and add the role list**

Replace the `EXPECTED=` line and the check below it with:

```bash
EXPECTED="impl-haiku impl-opus-high impl-opus-low impl-opus-medium impl-sonnet-high impl-sonnet-low impl-sonnet-medium judge-fable judge-opus scout-sonnet"
ROLE_TOOLS="Read, Grep, Glob, WebFetch"

actual=$(cd "$AGENTS" 2>/dev/null && ls *.md 2>/dev/null | sed 's/\.md$//' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "fleet contains exactly the 10 expected agents" "$actual" "$EXPECTED"
```

- [ ] **Step 2: Replace the per-file loop body**

Replace everything from `for f in "$AGENTS"/*.md; do` to its closing `done`
with:

```bash
for f in "$AGENTS"/*.md; do
  [ -e "$f" ] || continue
  base=$(basename "$f" .md)

  check "$base: frontmatter name matches filename" "$(fm "$f" name)" "$base"

  model=$(fm "$f" model)
  case "$model" in
    haiku|sonnet|opus|fable) got_model=ok ;;
    *) got_model="invalid:$model" ;;
  esac
  check "$base: model is a valid alias" "$got_model" "ok"

  effort=$(fm "$f" effort)
  case "$effort" in
    ''|low|medium|high) got_effort=ok ;;
    *) got_effort="retired-or-invalid:$effort" ;;
  esac
  check "$base: effort is an allowed level" "$got_effort" "ok"

  case "$base" in
    impl-*)
      # Implementers pin model and effort from their own name, carry the full
      # toolset, and preload the completion-discipline skill.
      check "$base: implementer does not run on fable" \
        "$([ "$model" = fable ] && echo yes || echo no)" "no"
      if [ "$model" = "haiku" ]; then
        check "$base: haiku carries no effort field" "${effort:-ABSENT}" "ABSENT"
      else
        check "$base: effort matches the name suffix" "$effort" "${base##*-}"
      fi
      check "$base: does not set tools" "$(grep -c '^tools:' "$f")" "0"
      check "$base: preloads verification-before-completion" \
        "$(grep -c '^  - superpowers:verification-before-completion$' "$f")" "1"
      ;;
    judge-*|scout-*)
      # Role agents are read-only by registry, not by prose. The absent tools
      # are the point: no Edit, no Write, no Agent.
      check "$base: carries the read-only toolset" "$(fm "$f" tools)" "$ROLE_TOOLS"
      check "$base: effort is high or medium" \
        "$(case "$effort" in high|medium) echo ok ;; *) echo "invalid:$effort" ;; esac)" "ok"
      check "$base: preloads no skills" "$(grep -c '^skills:' "$f")" "0"
      ;;
    *)
      check "$base: name matches a known agent class" "unknown-class" "impl|judge|scout"
      ;;
  esac

  check "$base: does not set isolation" \
    "$(grep -c '^isolation:' "$f")" "0"
  check "$base: does not preload test-driven-development" \
    "$(grep -c 'test-driven-development' "$f")" "0"
  # grep -P is unavailable here; awk with an octal byte range is portable.
  check "$base: content is ASCII only" \
    "$(LC_ALL=C awk '/[\200-\377]/{n++} END{print n+0}' "$f")" "0"
done
```

- [ ] **Step 3: Update the file's header comment**

Replace the comment block at the top of the file with:

```bash
# The fleet is ten agents in two classes. Seven implementers pin one
# model/effort pairing each and carry the full toolset. Three role agents -
# two judges and one scout - are read-only by registry: their tools list omits
# Edit, Write, NotebookEdit, and Agent, so "reviewers do not mutate the tree"
# and "reviewers do not spawn subagents" are enforced rather than requested.
#
# Haiku 4.5 does not support reasoning effort at all, so impl-haiku must NOT
# carry an effort field. The xhigh and max levels are retired everywhere, and
# no implementer runs on Fable.
```

- [ ] **Step 4: Run the suite**

Run: `bash plugins/dcc-superpower-companions/tests/fleet.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-superpower-companions/tests/fleet.test.sh
git commit -m "test(companions): cover ten agents in two classes"
```

---

### Task 5: Add the criteria format, the task-review criteria, and their test

**Files:**
- Create: `plugins/dcc-superpower-companions/criteria/TEMPLATE.md`
- Create: `plugins/dcc-superpower-companions/criteria/task-review.md`
- Create: `plugins/dcc-superpower-companions/tests/criteria.test.sh`

**Interfaces:**
- Consumes: nothing
- Produces: the criteria file format — a `## Ground Truth Note` section and a
  `## Criteria` section of 2 to 4 `### Name {#id}` headings — and the three
  task-review criterion ids `spec`, `verification`, `quality`. Task 6 follows
  the format; Task 8 reads these ids.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2
**Approach:** best-of-3 — file-per-criteria-set vs a single registry file vs criteria inlined in each skill; the choice constrains Tasks 6, 8, and 9, and reversing it later means rewriting all three

The winning approach is file-per-criteria-set, adopted from LLM-as-a-Verifier's
own layout: a criteria file is data a skill points a judge at, so it must be
readable by a subagent that has no other context.

- [ ] **Step 1: Write criteria.test.sh first**

```bash
#!/usr/bin/env bash
# Criteria files are data that skills hand to a judge subagent, so their shape
# is checkable without a model. Two things matter and both are structural: the
# ground-truth note the judge sees on every evaluation, and criterion ids that
# stay stable when a heading is reworded.
#
# The 2-to-4 bound is not style. One broad criterion is what fine-grained
# scoring replaces; five narrow ones start measuring the same thing twice.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRITERIA="$HERE/../criteria"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

check "criteria directory exists" \
  "$([ -d "$CRITERIA" ] && echo yes || echo no)" "yes"
check "TEMPLATE.md exists" \
  "$([ -f "$CRITERIA/TEMPLATE.md" ] && echo yes || echo no)" "yes"

for f in "$CRITERIA"/*.md; do
  [ -e "$f" ] || continue
  base=$(basename "$f" .md)

  check "$base: has a ground truth note" \
    "$(grep -c '^## Ground Truth Note$' "$f")" "1"
  check "$base: has a criteria section" \
    "$(grep -c '^## Criteria$' "$f")" "1"

  headings=$(grep -c '^### ' "$f")
  in_range=$([ "$headings" -ge 2 ] && [ "$headings" -le 4 ] && echo ok || echo "count:$headings")
  check "$base: has 2 to 4 criteria" "$in_range" "ok"

  # Every criterion pins an id in braces so rewording the heading never changes
  # the id a skill or a report refers to.
  pinned=$(grep -c '^### .*{#[a-z0-9_]\{1,\}}$' "$f")
  check "$base: every criterion pins a slug-safe id" "$pinned" "$headings"

  ids=$(grep -o '{#[a-z0-9_]\{1,\}}' "$f" | LC_ALL=C sort)
  uniq_ids=$(printf '%s\n' "$ids" | LC_ALL=C sort -u)
  check "$base: criterion ids are unique" \
    "$(printf '%s\n' "$ids" | grep -c .)" "$(printf '%s\n' "$uniq_ids" | grep -c .)"

  # grep -P is unavailable here; awk with an octal byte range is portable.
  check "$base: content is ASCII only" \
    "$(LC_ALL=C awk '/[\200-\377]/{n++} END{print n+0}' "$f")" "0"
done

# task-review.md is named by the dispatching skill, so its ids are a contract.
TR="$CRITERIA/task-review.md"
if [ -f "$TR" ]; then
  got=$(grep -o '{#[a-z0-9_]\{1,\}}' "$TR" | tr -d '{#}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
  check "task-review exposes the three contracted ids" "$got" "quality spec verification"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash plugins/dcc-superpower-companions/tests/criteria.test.sh`
Expected: FAIL with `criteria directory exists` want `yes` got `no`.

- [ ] **Step 3: Create criteria/TEMPLATE.md**

```markdown
# <Your Evaluation> - Verifier Criteria

Copy this file, replace the content, and keep the heading structure. A skill
hands a judge subagent the path to a file like this one; the judge has no other
context, so everything it needs to score must be in here.

Adapted from the criteria format in LLM-as-a-Verifier (arXiv:2607.05391).

## Ground Truth Note

One paragraph the judge sees on every evaluation. Use it to say which evidence
to trust, not what to conclude.

Do NOT trust the agent's self-assessment or its claims of success. Trust the
command output observed in the record over any narration of that output.

## Criteria

One third-level heading per criterion, 2 to 4 of them. Everything until the next
heading is that criterion's instruction. The judge scores each criterion
independently, which is why two narrow criteria beat one broad one.

Every heading pins an id in braces, as the two examples below do. The id is what
reports and skills refer to, so it must survive a reworded heading. Keep it
lowercase, with letters, digits, and underscores only.

Write each instruction so a stranger could score with it, in this order:

- say exactly WHERE to look - which files, commands, fields, or output
- say what should score HIGH
- say what should score LOW
- say what to IGNORE, so one criterion does not leak into another

The ignore clause is the one most often skipped and the one that does the most
work. Without it two criteria drift onto the same evidence and the score stops
carrying two independent readings.

### First Example Criterion {#first_example}

Look at <exact location>. Score HIGH when <observable property>. Score LOW when
<observable failure>, when the evidence is asserted rather than shown, or when
<the specific confusion this criterion exists to catch>. Ignore <what the
neighbouring criterion owns>.

### Second Example Criterion {#second_example}

Two criteria are the minimum, and this file carries two so that it satisfies the
format it documents. Replace both. Look at <a different location from the one
above>. Score HIGH when <observable property>. Score LOW when <observable
failure>. Ignore <what the first criterion owns> - naming it here is what keeps
the two scores independent.
```

- [ ] **Step 4: Create criteria/task-review.md**

```markdown
# Task Review - Verifier Criteria

Applied by dcc-superpower-companions:dispatching-tiered-implementers when a task
reviewer scores one task's implementation.

## Ground Truth Note

Do NOT trust the implementer's report. It is a set of unverified claims about
the code, and implementers routinely declare success on work that is incomplete,
untested, or subtly wrong. Trust the diff and the command output quoted in the
report over any narration of them. A stated rationale - "left it per YAGNI",
"kept it simple deliberately" - is the implementer grading its own work and
never raises a score.

Evidence you cannot see is not evidence that does not exist. If the report looks
truncated, re-read it at its stated path before treating it as missing.

## Criteria

### Spec Compliance {#spec}

Compare the diff against the task brief, requirement by requirement. Score HIGH
when every requirement in the brief has a corresponding change in the diff and
nothing beyond the brief was built. Score LOW when a requirement is missing,
when a requirement was claimed in the report but has no hunk in the diff, when
the right feature was built the wrong way, or when unrequested work appears -
extra abstraction, speculative options, nice-to-haves. If the brief lists
several files each with its own change, a listed file the diff never touches is
a LOW signal no matter how clean the rest of the batch is. Ignore code quality,
test design, and whether the tests were actually run; other criteria own those.

### Empirical Verification {#verification}

Look at the commands the report says were run and the output it quotes, not at
what the report concludes from them. Score HIGH when the implementer ran tests
covering exactly the code it changed, quoted the output, and the quoted output
supports the claim - and, where the brief required TDD, when a failing run is
shown before the implementation and a passing run after it. Score LOW when
success is declared with no command shown, when the quoted output does not
actually say what the report claims it says, when a traceback or a warning in
the quoted output is passed over, or when the code was edited again after the
last successful run so the final state is untested. Test output that is not
pristine is a LOW signal. Ignore whether the tests are well designed; that
belongs to Code Quality.

### Code Quality {#quality}

Review the diff as an experienced reviewer would. Score HIGH when the change is
correct, each file has one clear responsibility, error paths are handled, and
the tests assert real behavior rather than mocks. Score LOW for semantic errors
the tests would not catch, swallowed errors, verbatim duplication of a logic
block, tests that assert nothing, silent regressions in code paths the brief did
not mention, or a new file that is already unwieldy. Judge the diff on its
technical merits, not on its length or apparent effort. Ignore requirements
coverage, which Spec Compliance owns, and ignore pre-existing problems in code
this diff does not touch.
```

- [ ] **Step 5: Run the suite**

Run: `bash plugins/dcc-superpower-companions/tests/criteria.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-superpower-companions/criteria \
        plugins/dcc-superpower-companions/tests/criteria.test.sh
git commit -m "feat(companions): add scored task-review criteria"
```

---

### Task 6: Add the approach-selection criteria

**Files:**
- Create: `plugins/dcc-superpower-companions/criteria/approach-selection.md`

**Interfaces:**
- Consumes: the criteria file format from Task 5
- Produces: criterion ids `fit`, `reversibility`, `simplicity`, read by Task 9

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
**Approach:** inline — skip 2: follows the file format Task 5 establishes

These criteria are written for **pairwise** use. Each instruction compares two
candidates rather than scoring one in isolation, because a weaker judge ranks
two options far more reliably than it scores one.

- [ ] **Step 1: Create criteria/approach-selection.md**

```markdown
# Approach Selection - Verifier Criteria

Applied by dcc-superpower-companions:selecting-approaches when a judge ranks
candidate approaches pairwise.

## Ground Truth Note

You are comparing two proposals, not grading essays. Judge what each approach
would actually do to this repository, using the files you can read. A proposal
that is well written but wrong for this codebase loses to a plainly stated one
that fits.

Do NOT reward a proposal for hedging. A candidate that lists several options
instead of committing to one has not answered the question, and its apparent
safety is an artifact of saying less.

Neither candidate is a default. If they are genuinely equivalent on a criterion,
score them equally rather than inventing a difference.

## Criteria

### Fit to This Codebase {#fit}

Read the files each approach names. Score an approach HIGH when it follows a
pattern this repository already uses, reuses what exists, and its named files
and interfaces actually match what is there. Score it LOW when it introduces a
second way to do something the repo already does one way, when it assumes files,
interfaces, or conventions that do not exist here, or when it would leave two
subsystems disagreeing about the same concept. Ignore how much work each
approach is; effort belongs to Simplicity.

### Cost of Being Wrong {#reversibility}

Consider what happens if this approach turns out to be the wrong choice six
tasks later. Score HIGH when backing out is a revert - the approach is additive,
its blast radius is one place, and nothing downstream is built to depend on its
shape. Score LOW when it commits early to a data shape, a public interface, a
stored format, or a dependency that later work would have to be rewritten
around, and lower still when the commitment is invisible from the call sites it
constrains. Ignore whether the approach is likely to be wrong; only how
expensive it is if it is.

### Simplicity {#simplicity}

Score HIGH for the approach that a reader meeting this code for the first time
would understand fastest, and that solves exactly the stated problem. Score LOW
for machinery built for requirements nobody has stated, configuration with one
caller, indirection that adds a hop without adding a boundary, or a general
mechanism where a specific one was asked for. Fewer moving parts wins ties.
Ignore fit and reversibility, which the other criteria own, and do not reward
brevity that works by leaving a stated requirement unaddressed.
```

- [ ] **Step 2: Run the criteria suite**

Run: `bash plugins/dcc-superpower-companions/tests/criteria.test.sh`
Expected: PASS, `0 failed`, and the per-file checks now report on
`approach-selection` as well.

- [ ] **Step 3: Commit**

```bash
git add plugins/dcc-superpower-companions/criteria/approach-selection.md
git commit -m "feat(companions): add approach-selection criteria"
```

---

### Task 7: Rewrite assigning-implementers for the split gate

**Files:**
- Modify: `plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md`

**Interfaces:**
- Consumes: `reference/ladder.md` from Task 3
- Produces: the `**Approach:**` plan line format, read by Task 8

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2
**Approach:** inline — skip 3: the spec fixes the gate, the line format, and the check list

Three sections change. Everything else in the file — the announce line, the
plan-header amendment, the task-heading warning, and the overriding section —
stays exactly as written.

- [ ] **Step 1: Replace the "Score every task" section**

Replace the whole `## Score every task` section with:

```markdown
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
```

- [ ] **Step 2: Replace the "Write the assignment" opening**

Replace the first paragraph and code block of `## Write the assignment` with:

````markdown
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
````

- [ ] **Step 3: Add two items to the "Check your work" list**

Insert these two bullets after the existing `**Evaluation:**` arithmetic bullet:

```markdown
- Every task clears Rule S. Compute `files + spec + coupling` for each and
  confirm none reaches 4, and that no task scores 3 on spec completeness. A
  total above 6 anywhere means the gate was skipped, since Rule S caps a
  compliant total at 6.
- Every `**Approach:**` line names `inline`, `advisor`, or `best-of-3`, and
  every `inline` cites a skip condition by number.
```

- [ ] **Step 4: Verify the skill still points only at the ladder for its tables**

Run:
```bash
grep -n 'impl-sonnet\|impl-opus\|impl-haiku' \
  plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md
```
Expected: matches only inside the example plan lines, never a restated table.
No `impl-fable`, `xhigh`, or `max` appears anywhere in the output.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md
git commit -m "feat(companions): gate assignment behind Rule S"
```

---

### Task 8: Rewrite dispatching-tiered-implementers for the new ladder and scored review

**Files:**
- Modify: `plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md`

**Interfaces:**
- Consumes: `reference/ladder.md` (Task 3), `criteria/task-review.md` (Task 5),
  the `judge-fable` and `judge-opus` agents (Task 2)
- Produces: nothing other tasks read

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 0 - spec 0 - coupling 2 - risk 2 = 4
**Approach:** advisor — load-bearing (this file is the seam onto superpowers' fix loop), one plausible shape given the existing skill's structure

This is the plan's most coupled task. It touches superpowers' fix loop, its
ledger conventions, and its crash recovery, and every one of those is a place
where an additive change is safe and a replacing change breaks silently.

- [ ] **Step 1: Add the retired-agent step to "Dispatch a task"**

Insert a new step between the existing steps 1 and 2, renumbering the rest:

````markdown
2. If that value names a retired agent, map it through the `retired` table in
   [`../../reference/ladder.md`](../../reference/ladder.md) and dispatch the
   target instead. Say the substitution aloud and record it in the ledger line
   you already add:

   ```
   Task <N>: implementer impl-opus-high (assigned; mapped from retired impl-fable-max)
   ```

   A 0.1.0 plan names agents this version deletes. Mapping them is why the
   table exists; without it the next rule stops the run.
````

- [ ] **Step 2: Replace the Escalate section's opening**

Replace the first paragraph of `## Escalate` with:

```markdown
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
```

- [ ] **Step 3: Replace the ladder-exhausted paragraph**

Replace the paragraph beginning `When the ladder is exhausted` with:

````markdown
The ladder's top rung is `impl-opus-high`, whose successor is `SPLIT` - an
action, not an agent. When it is exhausted, do not report BLOCKED yet: break the
task's remaining work into smaller tasks, score each against Rule S, and
dispatch them fresh. Record it as a ruling in the ledger:

```
Ruling: split Task <N> at the top rung into <N>a and <N>b - impl-opus-high exhausted after 5 rounds - if wrong, the halves review separately and merge back
```

**A task may be split-escalated once.** If a split half also exhausts the
ladder, report BLOCKED through superpowers' existing contract. Do not loop.
````

- [ ] **Step 4: Add the scored-review section**

Insert this section immediately before `## Failure modes`:

````markdown
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

**The scores are additive.** superpowers' fix loop triggers on its spec-failure
verdict, on Critical findings, and on Important findings. Keep every one of
those; the scores ride alongside and never replace them. A judge that returns
scores but drops the verdicts has produced an unusable review - re-dispatch it.

Read the scores as bands: **1-8 fails** and joins the fix-loop trigger; **9-13**
is borderline, recorded and adjudicated by you; **14-20 passes**.

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
Task <N>: complete (scores spec 17 / verification 15 / quality 16, K=3)
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
````

- [ ] **Step 5: Update the Failure modes table**

Replace the `Escalation exhausted` row and the `model is unavailable` row with:

```markdown
| The line names a retired agent | Map it through the `retired` table, dispatch the target, and state the substitution in the ledger |
| The line names an agent that is neither current nor retired | Stop and ask your human partner. Never fall back silently |
| Fable is unavailable or declined for a judge seat | Dispatch `judge-opus`, say so, and continue |
| An implementer's model is unavailable on this account | Substitute the same effort one model down, state the substitution in the ledger and to your partner, and continue. From Sonnet there is no such rung - stop and ask instead |
| Escalation exhausted at impl-opus-high | Split the remaining work once; if a half also exhausts, report BLOCKED per superpowers |
```

- [ ] **Step 6: Verify no retired agent name survives outside the migration text**

Run:
```bash
grep -n 'xhigh\|fable-max\|opus-max\|sonnet-max' \
  plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md
```
Expected: matches only inside the retired-agent example ledger line in Step 1.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md
git commit -m "feat(companions): add scored review and progress escalation"
```

---

### Task 9: Add the selecting-approaches skill

**Files:**
- Create: `plugins/dcc-superpower-companions/skills/selecting-approaches/SKILL.md`

**Interfaces:**
- Consumes: `criteria/approach-selection.md` (Task 6), the `scout-sonnet`,
  `judge-fable`, and `judge-opus` agents (Task 2), the `**Approach:**` line
  format (Task 7)
- Produces: nothing other tasks read

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2
**Approach:** inline — skip 3: the spec fixes the gate conditions, the ring pass, and the output format

- [ ] **Step 1: Create the skill file**

````markdown
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
````

- [ ] **Step 2: Verify the skill is registered by the plugin loader**

Run: `claude plugin validate .`
Expected: no errors reported for `dcc-superpower-companions`.

- [ ] **Step 3: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/selecting-approaches
git commit -m "feat(companions): add best-of-3 approach selection"
```

---

### Task 10: Extend the hook to brainstorming

**Files:**
- Modify: `plugins/dcc-superpower-companions/scripts/tier-nudge.sh`
- Modify: `plugins/dcc-superpower-companions/tests/hook.test.sh`

**Interfaces:**
- Consumes: the skill names from Tasks 7 and 9
- Produces: nothing other tasks read

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2
**Approach:** inline — skip 2: adds one case arm to the existing matcher

The hook keeps its shape: a `case` on the skill name, `additionalContext` out,
silent on everything else. One arm is added and two texts are updated.

- [ ] **Step 1: Add the brainstorming arm and update both existing texts**

Replace the whole `case "$skill" in ... esac` block with:

```bash
case "$skill" in
  superpowers:writing-plans)
    context="Plans in this repository record an implementer assignment for each task: an \`**Implementer:**\` line naming a dcc-superpower-companions agent, an \`**Evaluation:**\` line showing the four-axis scores behind it, and an \`**Approach:**\` line when the task involved an approach decision. The dcc-superpower-companions:assigning-implementers skill holds the scoring rubric, the assignment table, and Rule S, which sends an over-scoring task back to be split rather than to a larger model."
    ;;
  superpowers:subagent-driven-development)
    context="Tasks in this repository's plans carry an \`**Implementer:**\` line naming the subagent that runs them. The dcc-superpower-companions:dispatching-tiered-implementers skill holds the dispatch rules, the escalation ladder, the retired-agent map for plans written against version 0.1.0, and the criteria-scored review it adds to the task-review seat."
    ;;
  superpowers:brainstorming)
    context="Approach decisions in this repository are settled through the dcc-superpower-companions:selecting-approaches skill, which gates each decision to inline, one advisory pass, or a best-of-3 pairwise ranking. It holds five numbered conditions for skipping straight to inline, including bug fixes with a located root cause."
    ;;
  *)
    exit 0
    ;;
esac
```

- [ ] **Step 2: Move brainstorming from the silent list to the firing list**

`tests/hook.test.sh` currently asserts that `superpowers:brainstorming` emits
nothing. That assertion is now wrong and the suite will fail until it moves.
This is the whole reason this step exists - appending a new check without
removing the old one leaves the suite contradicting itself.

Replace the firing loop's `for` line:

```bash
for skill in superpowers:writing-plans superpowers:subagent-driven-development superpowers:brainstorming; do
```

Replace the silent loop's `for` line, dropping brainstorming from it:

```bash
for skill in superpowers:executing-plans other:thing ""; do
```

Then add one context assertion beside the two that already exist, immediately
after the `subagent-driven-development context names the dispatching skill`
check:

```bash
check "brainstorming context names the selecting skill" \
  "$(run superpowers:brainstorming | jq -r '.hookSpecificOutput.additionalContext' | grep -c 'selecting-approaches')" "1"
```

- [ ] **Step 3: Update the suite's header comment**

Replace the first comment block with:

```bash
# The hook must fire for exactly three superpowers skills and stay silent for
# everything else.
#
# superpowers:executing-plans is deliberately NOT matched: it runs plan tasks
# inline in the current session without subagents, so nudging it toward tiered
# dispatch would push it to do the one thing it is designed not to do.
#
# superpowers:brainstorming IS matched, because that is where an approach
# decision is open and selecting-approaches has something to say about it.
```

- [ ] **Step 4: Run the hook suite**

Run: `bash plugins/dcc-superpower-companions/tests/hook.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-superpower-companions/scripts/tier-nudge.sh \
        plugins/dcc-superpower-companions/tests/hook.test.sh
git commit -m "feat(companions): nudge approach selection at brainstorming"
```

---

### Task 11: Update the README and both manifests to 0.2.0

**Files:**
- Modify: `plugins/dcc-superpower-companions/README.md`
- Modify: `plugins/dcc-superpower-companions/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: everything above
- Produces: nothing

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2
**Approach:** inline — skip 3: the spec fixes the version, the counts, and the descriptions

- [ ] **Step 1: Bump the plugin manifest**

In `plugins/dcc-superpower-companions/.claude-plugin/plugin.json`, set:

```json
  "version": "0.2.0",
  "description": "Extends superpowers with 10 tiered subagents: seven implementers, two read-only judges, and a scout. Scores every plan task on a four-axis rubric that sends over-scoring tasks back to be split, dispatches with a defined escalation ladder, and scores task reviews against named criteria.",
```

And replace the `keywords` array with:

```json
  "keywords": [
    "superpowers",
    "subagents",
    "planning",
    "effort",
    "model-selection",
    "verification",
    "code-review"
  ]
```

- [ ] **Step 2: Update the marketplace entry**

In `.claude-plugin/marketplace.json`, in the `dcc-superpower-companions` object,
set `description` to the same string as Step 1 and replace `keywords` with the
same seven-item array. The `name`, `source`, and `category` fields do not change.

- [ ] **Step 3: Validate both manifests**

Run: `claude plugin validate .`
Expected: validation passes with no errors.

- [ ] **Step 4: Update the README**

Make these edits, leaving the rest of the file intact:

- In `## What you get`, replace the "16 implementer agents" paragraph with:

```markdown
**Ten agents in two classes.** Seven implementers - Sonnet 5 and Opus 5 at
`low`, `medium`, and `high`, plus one Haiku 4.5 agent. Three read-only role
agents - `judge-fable`, its `judge-opus` fallback, and `scout-sonnet` - whose
`tools:` frontmatter omits `Edit`, `Write`, and `Agent`, so a reviewer that
cannot modify the tree or spawn subagents is a fact about the registry rather
than a request in a prompt.

`xhigh` and `max` are retired everywhere, and Fable never implements. Above
`impl-opus-high` the answer to a hard task is to split it, not to escalate it.
```

- Replace the "A four-axis rubric" paragraph with:

```markdown
**A four-axis rubric that gates the plan.** Files, spec completeness, coupling,
and risk, each scored 0 to 3. Three of those four measure how the task was
drawn, not how hard the change is, so Rule S sends a task scoring 4 or more
across them back to be split rather than to a larger model. That cap is what
makes the assignment table stop at 6, which is exactly the seven implementers.
```

- Add a new paragraph after the escalation-ladder paragraph:

```markdown
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
```

- In `## Reference`, add after the existing sentence:

```markdown
`criteria/` holds the verifier criteria; `criteria/TEMPLATE.md` documents the
format. `tests/criteria.test.sh` validates every file in that directory.
```

- [ ] **Step 5: Run the full suite**

Run:
```bash
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do bash "$t"; done
```
Expected: four suites, every one ending `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-superpower-companions/README.md \
        plugins/dcc-superpower-companions/.claude-plugin/plugin.json \
        .claude-plugin/marketplace.json
git commit -m "docs(companions): release 0.2.0"
```

---

## Verification

After Task 11, confirm from the repository root:

```bash
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do bash "$t"; done
claude plugin validate .
ls plugins/dcc-superpower-companions/agents/*.md | wc -l
grep -rl 'xhigh\|impl-fable' plugins/dcc-superpower-companions/agents/
```

Expected: four suites at `0 failed`; validation clean; `10` agent files; and no
agent file matching the retired names.
