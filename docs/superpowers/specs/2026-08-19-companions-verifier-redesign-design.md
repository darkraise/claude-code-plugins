# dcc-superpower-companions 0.2.0 — Verifier Redesign

Date: 2026-08-19
Status: APPROVED — ready for implementation planning
Supersedes: parts of `2026-07-27-dcc-superpower-companions-design.md` (fleet
composition, assignment table, escalation ladder). Everything that design says
about the hook, the plan-line mechanism, and the superpowers seams still holds.

## Goal

Make the plugin push plans toward decompositions that cheap models can execute,
instead of buying a larger model whenever a plan task is badly drawn. Add a
verification layer adapted from LLM-as-a-Verifier, and retire the top of the
model grid.

## Why 0.1.0 needs this

The 0.1.0 rubric scores four axes and maps the total to an agent. Three of those
four axes — Files, Spec completeness, Coupling — are **properties of the plan's
decomposition**, not of the change itself. Only Risk is intrinsic.

That makes the rubric purely reactive. A task drawn too large scores high and is
answered with a more capable model, when the correct answer was almost always to
draw the task smaller. The plugin measures a decomposition defect and then pays
to work around it.

Three further consequences fall out of the same root:

1. **The grid is over-parameterised.** Thirteen assignment buckets imply a
   resolution the four-axis score does not have. Sixteen agent files exist to
   serve distinctions the rubric cannot reliably make.
2. **Reviews are unstructured.** Review quality is left entirely to superpowers'
   single broad reviewer prompt. The plugin has opinions about who implements
   and none about how the work is verified.
3. **Approach selection is invisible.** A task scoring `spec = 3` — prose only,
   approach undecided — is a design decision that was never made. 0.1.0 answers
   it with a floor rule that buys Opus. Buying capability is not the same as
   making the decision.

## What we took from LLM-as-a-Verifier

Source: `D:\Repositories\Community\llm-as-a-verifier` (read 2026-08-19),
paper arXiv:2607.05391.

| Idea | How it lands here |
|------|-------------------|
| Criteria decomposition — 2-4 narrow criteria, each stating where to look, what scores high, what scores low, what to ignore | `criteria/*.md`, modelled on their `criteria/TEMPLATE.md` |
| Ground-truth note: trust observed output, NOT the agent's narration | The ground-truth note on every criteria file |
| Fine-grained scoring (1-20) instead of a binary verdict | Per-criterion score in the task review, with a banded gate |
| Repeated evaluation, averaged | K=3 on risk-3 tasks only; K=1 otherwise |
| Pairwise comparison beats absolute scoring for a weaker judge | Approach selection ranks candidates pairwise, never scores them alone |
| Ring pass — every candidate appears once in slot A and once in slot B, cancelling positional bias | The N=3 ring: A vs B, B vs C, C vs A |
| Progress tracking on a partial trajectory, to abandon a hopeless rollout early | `**Progress:**` score in the re-review, driving early escalation |
| Prefix-cache ordering — invariant bulk first, varying criterion last | Dispatch prompt ordering for the K=3 path |

### What we did not take, and why

**The logprob expectation.** Their fine-grained reward takes an expectation over
the full logprob distribution of score tokens, which is where most of their
reported gain comes from. The Agent tool returns text, not token distributions,
so this is unreachable from a Claude Code plugin. Repeated integer sampling is a
coarse approximation of it, not an equivalent. **Do not cite their benchmark
numbers as expected outcomes of this design.**

**The pivot tournament.** `O(Nk)` beats `O(N^2)` only once N exceeds about 4. At
N=3 the ring pass alone yields a full ranking in 3 comparisons. Building a pivot
tournament for N=3 is machinery with no payer.

**Multi-modality, token accounting, the score cache.** No use case here.

## Verified platform facts

Confirmed on 2026-08-19 unless carried forward. Load-bearing; re-verify before
changing anything that rests on them.

| Fact | Source |
|------|--------|
| Subagent frontmatter accepts `tools:` as a comma-separated allowlist | `feature-dev/agents/code-reviewer.md` in the plugin cache |
| A restricted toolset is enforced by the registry, not by prompt | The session agent list renders each agent's real toolset |
| An agent with no `Edit`/`Write`/`NotebookEdit` cannot modify files | Follows from the above |
| An agent with no `Agent` tool cannot dispatch subagents | Follows from the above; `Explore` ships this way |
| `effort` is settable in frontmatter as low, medium, high, xhigh, or max | Carried forward from the 0.1.0 design |
| The Agent tool has `model` but no `effort` parameter | Carried forward |
| Haiku 4.5 does not support effort | Carried forward |
| Plugin subagents are namespaced `<plugin>:<agent>` | Carried forward |
| `scripts/task-brief` copies a task block verbatim from its heading to the next recognised heading | Carried forward |
| superpowers' fix loop keys on the spec-fail marker and on Critical/Important findings | Read from `subagent-driven-development/SKILL.md` |
| superpowers resumes the same implementer on fix rounds 1-3 and escalates only on 4-5 | Same source |

## Decisions

| Question | Decision | Why |
|----------|----------|-----|
| What the rubric is for | A size budget on the plan first, a dispatch key second | The reducible axes measure decomposition. Answering them with capability pays to keep a defect |
| Effort ceiling | `xhigh` and `max` retired everywhere, implementers and judges alike | User ruling. The design makes it coherent: above `impl-opus-high` the answer is to split, not to think harder |
| Fable's role | Judge and advisor only, never an implementer | User ruling |
| Fable unavailable | Fall back to `judge-opus`, stated aloud | Fable is not on every account, and the user may decline it |
| Judge toolset | `Read, Grep, Glob, WebFetch` — no Bash | Makes read-only structural. superpowers already tells reviewers not to re-run the implementer's tests and provides a "name the test you would run" path |
| Scoring format | Added alongside superpowers' verdicts, never replacing them | Its fix loop keys on the spec-fail marker and Critical/Important. Replacing those breaks the loop silently |
| K repeats | K=1; K=3 when the task scored risk 3 | Cost tracks stakes. Risk is the one axis the split gate cannot reduce |
| N for approach selection | 3, with a ring pass | Smallest N where a ring pass both ranks fully and cancels positional bias exactly |
| When to run best-of-N | Behind a five-condition skip gate | Cost control, and a correctness boundary for bugs |
| Progress escalation floor | Never earlier than round 3 | superpowers' rounds 1-3 preserve the implementer's context deliberately |

---

## Part 1 — The rubric becomes a split gate

The four axes stay, with one clarification and one reclassification.

**Clarification to the Files axis.** Count distinct file *shapes*, not instances.
Sixteen files generated from one template are one shape and score 0. Under 0.1.0
that task scores 3 on Files and buys Opus for what is transcription.

**Reclassification.**

| Reducible — fix by splitting | Irreducible |
|------------------------------|-------------|
| Files, Spec completeness, Coupling | Risk |

### Rule S — the split gate

> Let `reducible = files + spec + coupling`.
>
> **If `reducible >= 4`, or if `spec = 3`, the task must be split or
> re-designed. Do not assign a larger model.**

`spec = 3` means prose only with the approach undecided. That is not a
model-selection problem: it is a design decision nobody made. It routes to
Part 4, not to Opus. The 0.1.0 spec-3 floor survives only as the fallback when a
human overrides the gate.

### The assignment table follows from Rule S

After Rule S, `reducible <= 3` and `spec <= 2`, so `total <= 3 + risk(3) = 6`.
The table's ceiling is a consequence of the rule rather than a hand-picked cut.

```
0  impl-haiku          4  impl-opus-low
1  impl-sonnet-low     5  impl-opus-medium
2  impl-sonnet-medium  6  impl-opus-high
3  impl-sonnet-high
```

A total of 7 or more is unreachable in a compliant plan. If one is computed, the
gate was skipped.

---

## Part 2 — The fleet: 16 agents to 10

### Seven implementers

`impl-haiku`, `impl-sonnet-low`, `impl-sonnet-medium`, `impl-sonnet-high`,
`impl-opus-low`, `impl-opus-medium`, `impl-opus-high`.

Body and frontmatter keep the 0.1.0 shape: thin role statement, `skills:` preload
of `superpowers:verification-before-completion`, full toolset.

### Three read-only role agents

| Agent | Model | Effort | Role |
|-------|-------|--------|------|
| `judge-fable` | Fable 5 | high | Task verifier and approach ranker |
| `judge-opus` | Opus 5 | high | The same, when Fable is unavailable or declined |
| `scout-sonnet` | Sonnet 5 | medium | Drafts one candidate approach |

All three carry `tools: Read, Grep, Glob, WebFetch`.

One agent serves both judge roles because the roles differ only in their dispatch
prompt; the agent file exists to pin model, effort, and toolset. Splitting them
would duplicate a file to hold no additional fact.

Excluding `Edit`, `Write`, and `NotebookEdit` makes "reviewers do not mutate the
tree" a property of the registry. Excluding `Agent` does the same for "reviewers
do not spawn subagents". superpowers spends two prose sections asking for both
today, and prose is not enforcement.

### Escalation ladder

```
impl-haiku         -> impl-sonnet-medium
impl-sonnet-low    -> impl-opus-low
impl-sonnet-medium -> impl-opus-medium
impl-sonnet-high   -> impl-opus-high
impl-opus-low      -> impl-opus-medium
impl-opus-medium   -> impl-opus-high
impl-opus-high     -> SPLIT
```

**The terminal rung is an action, not an agent.** A task that exhausts
`impl-opus-high` has its remaining work split into sub-tasks, each scored and
dispatched fresh. A task may be split-escalated **once**; a second exhaustion is
reported BLOCKED through superpowers' existing contract.

Termination still holds by rank. With Haiku 0, Sonnet 1, Opus 2 and effort 0-2
from `low` to `high`, rank is `model_rank * 10 + effort_rank`: Haiku 0, Sonnet
10-12, Opus 20-22. Every successor has strictly greater rank, and SPLIT is
reachable at most once per task.

### Retired-agent map

Existing plans name agents this release deletes. The rule is **clamp each
dimension to its allowed maximum**: effort clamps to `high`, and a retired model
clamps to the top execution rung.

```
impl-sonnet-xhigh  -> impl-sonnet-high
impl-sonnet-max    -> impl-sonnet-high
impl-opus-xhigh    -> impl-opus-high
impl-opus-max      -> impl-opus-high
impl-fable-low     -> impl-opus-high
impl-fable-medium  -> impl-opus-high
impl-fable-high    -> impl-opus-high
impl-fable-xhigh   -> impl-opus-high
impl-fable-max     -> impl-opus-high
```

The dispatching skill applies the map and states the substitution in the ledger.
Without it, every 0.1.0 plan trips the "agent name with no definition file — stop
and ask" rule.

---

## Part 3 — Criteria-based scored review

### The criteria directory

`criteria/` holds `TEMPLATE.md`, `task-review.md`, and `approach-selection.md`.
Each file carries a `## Ground Truth Note` the judge sees on every evaluation,
and a `## Criteria` section of 2-4 criterion headings. Each heading pins an id in
braces so rewording the heading never changes the id.

Each criterion instruction must state, in this order: where to look, what scores
HIGH, what scores LOW, and what to IGNORE. The last clause is what stops two
criteria from measuring the same thing.

`task-review.md` carries three criteria, with ids `spec`, `verification`, and
`quality`.

### The score block

The judge appends one block to superpowers' existing report format:

```
### Verification Scores
- spec: <1-20>
- verification: <1-20>
- quality: <1-20>
```

Bands: **1-8 fails** and enters the fix loop; **9-13 borderline**, findings
recorded and the controller adjudicates; **14-20 passes**.

**This is additive.** superpowers' fix loop triggers on its spec-fail marker, on
Critical, or on Important. The scores ride alongside those verdicts and never
replace them.

### Repeated evaluation

K=1 by default. When the task scored **risk 3**, dispatch K=3 independent judges
and average each criterion.

**Disagreement is the signal, not the mean.** If the three judges spread more
than 6 points on any criterion, the controller reads the diff itself rather than
trusting the average. A wide spread means the criterion did not discriminate,
which is a fact about the review, not about the code.

### Prompt ordering

The dispatch prompt places the invariant material first — brief path, report
path, diff path, process rules — and the criteria block last. On the K=3 path the
three prompts then share a long identical prefix. This is the only place the
ordering pays, and it is the only place it is required.

---

## Part 4 — Approach selection

### The gate decides who decides

Every `spec = 3` task gets its approach settled before dispatch. The gate chooses
**who settles it**, at one of three costs:

| Outcome | Cost | Meaning |
|---------|------|---------|
| `inline` | 0 calls | The controller decides and records why |
| `advisor` | 1 call | One judge reviews the controller's chosen approach |
| `best-of-3` | 4 calls | Three scouts draft, one judge ranks |

The middle rung exists because a load-bearing decision with only one plausible
approach poses a verification question — "is this one wrong" — not a selection
question. That is `compare`, not `select`.

### Skip conditions

Any one sends the decision to `inline`. **Cite the condition by number.** An
uncited skip is not a skip.

1. **Bug fix with a located root cause.** Fixing it correctly is one approach.
2. **The repo already answers it.** An established pattern covers this exact
   change. Consistency dominates and a creative alternative is a defect.
3. **The spec or the user already chose.** Ranking ruled-out options is theatre.
4. **Trivially reversible and single-file.** Being wrong costs a revert.
5. **You cannot name two structurally distinct candidates.** State each in one
   sentence before dispatching scouts. Differing in naming or step order is not
   structural difference.

### Why bugs are excluded on correctness grounds

Generating N candidate approaches before a root cause is located produces N
guesses, and a ranking pass returns a winner whether or not any candidate is
correct — laundering speculation into a confident pick. Bugs route to
`superpowers:systematic-debugging`. This is a correctness boundary, not a cost
control.

### When best-of-3 runs

All three must hold: at least two nameable structurally distinct candidates; the
decision constrains later tasks or is expensive to reverse (an interface others
consume, a data shape, a migration, a public API, a dependency choice); and
neither the repo nor the spec already answers it.

Everything not skipped and not qualifying lands on `advisor`.

### The ring pass

Three `scout-sonnet` agents draft in parallel, one approach each. One judge then
runs three comparisons — **A vs B, B vs C, C vs A** — scoring both candidates
per criterion each time. At N=3 every candidate occupies slot A exactly once and
slot B exactly once, so positional bias cancels exactly and no second pass is
needed.

Comparisons aggregate into win mass; the highest normalised win rate wins. The
output names the winner **and the grafts**: ideas from the losing candidates
worth folding in.

### The plan line

```markdown
**Approach:** inline — skip 2: follows the existing hook-script pattern
**Approach:** advisor — load-bearing (produces the criteria file format)
**Approach:** best-of-3 — file-per-criterion vs single-registry vs inline-in-skill
```

---

## Part 5 — Progress-based early escalation

The re-reviewer emits one extra line:

```
**Progress:** <1-20>
```

Answering: given everything done so far, would the current state already satisfy
the task? Anchors match the review bands — 1 certainly not, 10 uncertain, 20
verified complete.

**Rule:** if round N's progress is less than or equal to round N-1's, escalate at
the start of the next round rather than waiting for superpowers' round 4.

**Floor: never escalate before round 3.** superpowers resumes the same
implementer on rounds 1-3 to preserve its model, effort, and context. Escalating
into round 2 discards exactly what that rule protects. The rule may only pull the
escalation point from 4 to 3; it may never delay it.

The progress reading folds into the fix-round line superpowers already writes,
for the reason 0.1.0 established — a line landing after a fix-round line hides it
from crash recovery:

```
Task 4: fix round 3/5 (1 addressed, 1 open - stale cache; commits a7f..b21; progress 11 -> 9; escalated impl-sonnet-medium -> impl-opus-medium)
```

---

## Testing strategy

No model calls, as in 0.1.0. Extended `bash` and `jq` suites.

| Suite | Asserts |
|-------|---------|
| `fleet.test.sh` | Exactly 10 agent files; no xhigh or max effort anywhere; no Fable on any implementer; the three role agents carry the exact read-only toolset; every implementer preloads the verification skill |
| `ladder.test.sh` | Assignment table covers 0-6 with no gaps; every named agent has a file; escalation is total over the seven implementers and strictly rank-increasing; SPLIT is the only terminal; the retired map is total over all nine retired names and every target exists |
| `criteria.test.sh` | Every criteria file has a Ground Truth Note and 2-4 criteria; every criterion carries a pinned id; ids are unique per file and slug-safe |
| `hook.test.sh` | Existing coverage, plus the brainstorming matcher |

## Migration

0.1.0 plans stay executable. The retired map covers every deleted name, and the
`**Implementer:**` and `**Evaluation:**` line formats are unchanged.
`**Approach:**` is optional; an absent line means "not assessed", not "skip".

## Out of scope

- The pivot tournament, and any N above 3.
- Multi-modal inputs, token accounting, score caching.
- Changing superpowers' reviewer model selection, its five-round cap, its
  breaker, or the final whole-branch review.
- Any attempt to recover logprob-weighted scoring.

## Risks

| Risk | Mitigation |
|------|------------|
| The controller talks itself into `inline` to dodge cost | The skip condition must be cited by number; an uncited skip is invalid |
| Rule S encourages splitting into tasks too small to carry a test cycle | superpowers' Task Right-Sizing still binds: a task is the smallest unit worth a fresh reviewer's gate |
| The score block confuses superpowers' fix loop | Scores are additive; the loop keys only on the verdicts it already owns |
| K=3 judges disagree and the mean hides it | Spread above 6 points routes to the controller instead |
| Splitting at the top rung loops forever | Split-escalation allowed once per task, then BLOCKED |
| Fable absent on the account | `judge-opus` fallback, stated aloud, never silent |
