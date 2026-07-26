# dcc-superpower-companions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Claude Code plugin that gives superpowers plans a per-task implementer assignment drawn from a 16-agent grid of model and reasoning-effort pairings.

**Architecture:** A fleet of 16 subagent definitions makes reasoning effort reachable (it is settable only in subagent frontmatter, never at dispatch time). Two companion skills write the assignment into a plan and read it back at dispatch, and a targeted `PreToolUse` hook on the `Skill` tool makes those skills fire deterministically. The plan document is the only state passed between planning and execution.

**Tech Stack:** Markdown (skills, agents, reference tables), JSON (plugin manifest, hook config), Bash with `jq` (hook script and test suite).

**Spec:** `docs/superpowers/specs/2026-07-27-dcc-superpower-companions-design.md`

## Global Constraints

- The plugin name is `dcc-superpower-companions`. The directory name, the `name` in `.claude-plugin/plugin.json`, and the `name` in the marketplace entry must all be exactly that string. `CLAUDE.md` requires every plugin name to start with `dcc-`.
- English only in all code, comments, docs, examples, commits, configs, errors, and tests.
- Agent frontmatter must **never** set `isolation`. It would branch from the default branch rather than the session HEAD, putting implementers on stale code.
- Agent frontmatter must **omit** `tools`, so implementers inherit every tool available to subagents, matching the `general-purpose` agent superpowers dispatches today.
- Agent frontmatter preloads exactly one skill: `superpowers:verification-before-completion`. Do not add `superpowers:test-driven-development`.
- The hook must respond to `superpowers:writing-plans` and `superpowers:subagent-driven-development` only. It must **never** respond to `superpowers:executing-plans`, which runs tasks inline without subagents.
- Hook `additionalContext` text must be phrased as factual statements about the project, never as imperative instructions, or it can trip prompt-injection defenses and be surfaced to the user instead of acted on.
- Agent names written into plans are fully qualified: `dcc-superpower-companions:impl-opus-high`.
- Ledger lines this plugin writes must never contain the reserved verbs `complete`, `fix round`, `parked`, or `BLOCKED`, because superpowers' crash recovery keys on `Task <N>: complete`.
- Commits use Conventional Commits: `<type>(<scope>): <subject>`, imperative, 50 chars max, no period.
- `claude plugin validate .` must pass from the repository root after every task.
- Write files with LF line endings. `.gitattributes` normalizes them; do not fight it.
- Generated file content must be ASCII only. No em dashes or typographic quotes in generated agent files.
- Agent `description` values must be **double-quoted** in the frontmatter. The descriptions contain `": "`, which is illegal in a YAML plain scalar and makes the frontmatter unparseable. This was confirmed empirically: unquoted, 13 of the 16 files fail to parse.
- Test scripts must use `LC_ALL=C sort` for any comparison against a hardcoded sorted list, and must not use `grep -P`, which is unavailable in this environment (`grep: -P supports only unibyte and UTF-8 locales`). Use `LC_ALL=C awk '/[\200-\377]/'` for non-ASCII detection.

## File Structure

```
plugins/dcc-superpower-companions/
  .claude-plugin/plugin.json          Plugin manifest
  agents/impl-*.md                    16 subagent definitions (model + effort pairings)
  reference/ladder.md                 Assignment and escalation tables; single source of truth
  skills/assigning-implementers/SKILL.md          Scores tasks, writes the assignment
  skills/dispatching-tiered-implementers/SKILL.md Reads it, dispatches, escalates
  hooks/hooks.json                    PreToolUse hook matching the Skill tool
  scripts/tier-nudge.sh               Emits context for two skill names only
  tests/fleet.test.sh                 Fleet completeness and frontmatter validity
  tests/ladder.test.sh                Table integrity, name resolution, termination proof
  tests/hook.test.sh                  Hook script behavior
  README.md                           Plugin documentation
```

Repository-level files modified: `.claude-plugin/marketplace.json` (register the plugin) and `README.md` (add a row to the plugin table).

`reference/ladder.md` holds both tables in parseable fenced blocks so the two skills and the test suite read one copy. A second copy would drift.

---

### Task 1: Plugin scaffold and marketplace registration

**Files:**
- Create: `plugins/dcc-superpower-companions/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the plugin directory `plugins/dcc-superpower-companions/` and a validated manifest. Every later task adds files beneath it.

- [ ] **Step 1: Create the plugin manifest**

```bash
mkdir -p plugins/dcc-superpower-companions/.claude-plugin
```

Write `plugins/dcc-superpower-companions/.claude-plugin/plugin.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "dcc-superpower-companions",
  "description": "Extends superpowers with 16 model and effort tiered implementer subagents. Scores every plan task on a four-axis rubric, records the assigned implementer in the plan, and dispatches that agent with a defined escalation ladder.",
  "version": "0.1.0",
  "author": {
    "name": "Darkraise"
  },
  "homepage": "https://github.com/darkraise/claude-code-plugins/tree/main/plugins/dcc-superpower-companions",
  "repository": "https://github.com/darkraise/claude-code-plugins",
  "license": "MIT",
  "keywords": [
    "superpowers",
    "subagents",
    "planning",
    "effort",
    "model-selection"
  ]
}
```

- [ ] **Step 2: Register in the marketplace manifest**

In `.claude-plugin/marketplace.json`, append this object to the `plugins` array (after the `telegram-notify` entry):

```json
    {
      "name": "dcc-superpower-companions",
      "source": "./plugins/dcc-superpower-companions",
      "description": "Extends superpowers with 16 model and effort tiered implementer subagents, a four-axis task scoring rubric, and a defined escalation ladder.",
      "category": "workflow",
      "keywords": ["superpowers", "subagents", "planning", "effort", "model-selection"]
    }
```

Remember the comma after the preceding `telegram-notify` object.

- [ ] **Step 3: Validate the manifests**

Run: `claude plugin validate .`
Expected: PASS with no errors. If it reports a JSON syntax error, the most likely cause is a missing or trailing comma in the `plugins` array.

- [ ] **Step 4: Add the README row**

In `README.md`, add this row to the "Available plugins" table, immediately after the `telegram-notify` row:

```markdown
| `dcc-superpower-companions` | Extends superpowers with 16 model and effort tiered implementer subagents. Scores every plan task, records the assigned implementer in the plan, and dispatches it with a defined escalation ladder. |
```

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-superpower-companions/.claude-plugin/plugin.json .claude-plugin/marketplace.json README.md
git commit -m "feat(companions): scaffold dcc-superpower-companions plugin"
```

---

### Task 2: The 16-agent fleet

**Files:**
- Create: `plugins/dcc-superpower-companions/tests/fleet.test.sh`
- Create: `plugins/dcc-superpower-companions/agents/impl-haiku.md` and 15 siblings

**Interfaces:**
- Consumes: the plugin directory from Task 1.
- Produces: 16 agent definition files whose basenames are exactly `impl-haiku`, `impl-sonnet-{low,medium,high,xhigh,max}`, `impl-opus-{low,medium,high,xhigh,max}`, and `impl-fable-{low,medium,high,xhigh,max}`. Task 3's ladder tables reference these names; Task 6's dispatch skill resolves them as `dcc-superpower-companions:<name>`.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-superpower-companions/tests/fleet.test.sh`:

```bash
#!/usr/bin/env bash
# The fleet must be exactly the 16 valid model/effort pairings, and every
# definition must carry frontmatter the Claude Code agent loader accepts.
#
# Haiku 4.5 does not support reasoning effort at all, so impl-haiku must NOT
# carry an effort field; the other three models support all five levels.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS="$HERE/../agents"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# fm <file> <key> - read one scalar key out of the YAML frontmatter block
fm() {
  awk -v k="$2" '
    NR == 1 && $0 == "---" { inb = 1; next }
    inb && $0 == "---" { exit }
    inb && index($0, k ":") == 1 { sub("^" k ":[ \t]*", ""); print; exit }
  ' "$1"
}

EXPECTED="impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-haiku impl-opus-high impl-opus-low impl-opus-max impl-opus-medium impl-opus-xhigh impl-sonnet-high impl-sonnet-low impl-sonnet-max impl-sonnet-medium impl-sonnet-xhigh"

actual=$(cd "$AGENTS" 2>/dev/null && ls *.md 2>/dev/null | sed 's/\.md$//' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "fleet contains exactly the 16 expected agents" "$actual" "$EXPECTED"

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
  if [ "$model" = "haiku" ]; then
    check "$base: haiku carries no effort field" "${effort:-ABSENT}" "ABSENT"
  else
    check "$base: effort matches the name suffix" "$effort" "${base##*-}"
    case "$effort" in
      low|medium|high|xhigh|max) got_effort=ok ;;
      *) got_effort="invalid:$effort" ;;
    esac
    check "$base: effort is a valid level" "$got_effort" "ok"
  fi

  check "$base: does not set isolation" \
    "$(grep -c '^isolation:' "$f")" "0"
  check "$base: does not set tools" \
    "$(grep -c '^tools:' "$f")" "0"
  check "$base: preloads verification-before-completion" \
    "$(grep -c '^  - superpowers:verification-before-completion$' "$f")" "1"
  check "$base: does not preload test-driven-development" \
    "$(grep -c 'test-driven-development' "$f")" "0"
  # grep -P is unavailable here; awk with an octal byte range is portable.
  check "$base: content is ASCII only" \
    "$(LC_ALL=C awk '/[\200-\377]/{n++} END{print n+0}' "$f")" "0"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

```bash
chmod +x plugins/dcc-superpower-companions/tests/fleet.test.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dcc-superpower-companions/tests/fleet.test.sh`
Expected: FAIL on "fleet contains exactly the 16 expected agents", because `agents/` does not exist yet and the actual list is empty.

- [ ] **Step 3: Generate the 16 agent files**

Run this exactly. It is the complete generator; the data rows below it are the only per-agent differences.

```bash
mkdir -p plugins/dcc-superpower-companions/agents
cd plugins/dcc-superpower-companions/agents

while IFS='|' read -r name model effort color note; do
  [ -n "$name" ] || continue
  case "$model" in
    haiku)  display="Haiku 4.5" ;;
    sonnet) display="Sonnet 5" ;;
    opus)   display="Opus 5" ;;
    fable)  display="Fable 5" ;;
  esac

  if [ -n "$effort" ]; then
    desc="Task implementer running $display at $effort effort. Dispatched by dcc-superpower-companions for $note."
    runs="You run on $display at $effort effort."
  else
    desc="Task implementer running $display. Dispatched by dcc-superpower-companions for $note."
    runs="You run on $display."
  fi

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    # Quoted: the description contains ": ", illegal in a YAML plain scalar.
    printf 'description: "%s"\n' "$desc"
    printf 'model: %s\n' "$model"
    if [ -n "$effort" ]; then printf 'effort: %s\n' "$effort"; fi
    printf 'skills:\n'
    printf '  - superpowers:verification-before-completion\n'
    printf 'color: %s\n' "$color"
    printf -- '---\n'
    printf '\n'
    printf 'You are a task implementer. Your dispatch prompt carries the task brief\n'
    printf 'path, the report file path, and the report contract. It is your complete\n'
    printf 'instruction set; follow it exactly.\n'
    printf '\n'
    printf '%s\n' "$runs"
    printf 'The brief governs test strategy; apply TDD when the brief steps call for\n'
    printf 'it, not by default.\n'
    printf '\n'
    printf 'If the task turns out to need more capability than you have, stop and\n'
    printf 'report BLOCKED rather than producing work you are unsure of. The\n'
    printf 'controller has a defined escalation ladder and will re-dispatch.\n'
  } > "$name.md"
done <<'ROWS'
impl-haiku|haiku||cyan|score 0: single-file transcription where the plan supplies the complete code
impl-sonnet-low|sonnet|low|green|score 1: two or three files with near-complete code supplied
impl-sonnet-medium|sonnet|medium|green|score 2: small well-specified changes with light coupling
impl-sonnet-high|sonnet|high|green|score 3: ordinary multi-file work with exact signatures supplied
impl-sonnet-xhigh|sonnet|xhigh|green|score 4: multi-file work with some of the approach left open
impl-sonnet-max|sonnet|max|green|score 5: intricate work at the top of the Sonnet range
impl-opus-low|opus|low|purple|score 6: broad but well-specified work needing wide context
impl-opus-medium|opus|medium|purple|score 7: multi-file integration with real coupling
impl-opus-high|opus|high|purple|score 8: multi-file integration needing design judgment
impl-opus-xhigh|opus|xhigh|purple|score 9: cross-layer work with meaningful blast radius
impl-opus-max|opus|max|purple|score 10: high-risk cross-layer work at the top of the Opus range
impl-fable-low|fable|low|red|escalation only, reached from impl-opus-low
impl-fable-medium|fable|medium|red|escalation only, reached from impl-opus-medium
impl-fable-high|fable|high|red|escalation only, reached from impl-opus-high
impl-fable-xhigh|fable|xhigh|red|score 11: shared-interface or migration work
impl-fable-max|fable|max|red|score 12: the hardest tasks, including security, data loss, and concurrency
ROWS

cd ../../..
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dcc-superpower-companions/tests/fleet.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Spot-check one generated file**

Run: `cat plugins/dcc-superpower-companions/agents/impl-opus-high.md`
Expected: frontmatter with `name: impl-opus-high`, `model: opus`, `effort: high`, a **double-quoted** `description:` value, a `skills:` list containing only `superpowers:verification-before-completion`, `color: purple`, and no `tools:` or `isolation:` key.

- [ ] **Step 6: Confirm every frontmatter block is parseable YAML**

The agent loader parses this frontmatter, and `fleet.test.sh` reads it with awk, which would not notice malformed YAML. Check it with a real parser:

```bash
uvx --quiet --from pyyaml python -c "
import yaml, glob, os
os.chdir('plugins/dcc-superpower-companions/agents')
bad = 0
for f in sorted(glob.glob('*.md')):
    front = open(f, encoding='utf-8').read().split('---')[1]
    try:
        d = yaml.safe_load(front)
        assert isinstance(d, dict) and d['name'] == f[:-3]
    except Exception as e:
        print('FAIL', f, type(e).__name__); bad += 1
print('parsed OK:', len(glob.glob('*.md')) - bad, '| bad:', bad)
"
```

Expected: `parsed OK: 16 | bad: 0`. If any file fails with `ScannerError: mapping values are not allowed here`, the `description` lost its quotes — the value contains `": "`, which YAML reads as a nested mapping.

- [ ] **Step 7: Validate and commit**

```bash
claude plugin validate .
git add plugins/dcc-superpower-companions/agents plugins/dcc-superpower-companions/tests/fleet.test.sh
git commit -m "feat(companions): add 16 tiered implementer agents"
```

---

### Task 3: The ladder reference and its integrity tests

**Files:**
- Create: `plugins/dcc-superpower-companions/tests/ladder.test.sh`
- Create: `plugins/dcc-superpower-companions/reference/ladder.md`

**Interfaces:**
- Consumes: the 16 agent filenames from Task 2.
- Produces: `reference/ladder.md` containing two parseable fenced blocks. The block tagged `assignment` has 13 lines of `<score> <agent-name>`. The block tagged `escalation` has 16 lines of `<from-agent> <to-agent>`, where the successor of `impl-fable-max` is the literal `-`. Tasks 5 and 6 cite this file as the single source of truth for both tables.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-superpower-companions/tests/ladder.test.sh`:

```bash
#!/usr/bin/env bash
# The ladder tables are data the skills read at runtime, so their integrity is
# checkable without a model. The escalation graph must terminate: every agent
# ranks strictly below its successor, so walking successors can never cycle and
# must end at impl-fable-max.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
AGENTS="$HERE/../agents"

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
check "assignment table has 13 rows" "$(printf '%s\n' "$assignment" | grep -c .)" "13"

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
for s in 0 1 2 3 4 5 6 7 8 9 10 11 12; do
  case " $seen_scores " in *" $s "*) ;; *) missing="$s" ;; esac
done
check "assignment covers every score 0 through 12" "$missing" "NONE"

# --- escalation table -------------------------------------------------------
escalation=$(block escalation)
check "escalation table has 16 rows" "$(printf '%s\n' "$escalation" | grep -c .)" "16"

bad_from=NONE
bad_to=NONE
terminals=""
while read -r from to; do
  [ -n "$from" ] || continue
  agent_exists "$from" || bad_from="$from"
  if [ "$to" = "-" ]; then
    terminals="$terminals $from"
  else
    agent_exists "$to" || bad_to="$to"
  fi
done <<< "$escalation"

check "every escalation source has a definition file" "$bad_from" "NONE"
check "every escalation target has a definition file" "$bad_to" "NONE"
check "exactly one terminal agent, and it is impl-fable-max" \
  "$(echo $terminals)" "impl-fable-max"

sources=$(printf '%s\n' "$escalation" | awk 'NF {print $1}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
all=$(cd "$AGENTS" && ls *.md | sed 's/\.md$//' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "every agent appears exactly once as an escalation source" "$sources" "$all"

# --- termination ------------------------------------------------------------
successor() { printf '%s\n' "$escalation" | awk -v a="$1" 'NF && $1 == a {print $2; exit}'; }

bad_walk=NONE
for start in $all; do
  cur="$start"; steps=0; visited=""
  while [ "$cur" != "-" ]; do
    case " $visited " in *" $cur "*) bad_walk="cycle-at:$cur"; break ;; esac
    visited="$visited $cur"
    steps=$((steps + 1))
    if [ "$steps" -gt 20 ]; then bad_walk="runaway-from:$start"; break; fi
    cur=$(successor "$cur")
    [ -n "$cur" ] || { bad_walk="dead-end-from:$start"; break; }
  done
  [ "$bad_walk" = NONE ] || break
  case " $visited " in *" impl-fable-max "*) ;; *) bad_walk="never-terminates:$start" ;; esac
  [ "$bad_walk" = NONE ] || break
done
check "escalation from every agent terminates at impl-fable-max without cycling" "$bad_walk" "NONE"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

```bash
chmod +x plugins/dcc-superpower-companions/tests/ladder.test.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dcc-superpower-companions/tests/ladder.test.sh`
Expected: FAIL on "ladder.md exists" (got `no`), plus cascading failures on the table checks.

- [ ] **Step 3: Write the ladder reference**

```bash
mkdir -p plugins/dcc-superpower-companions/reference
```

Write `plugins/dcc-superpower-companions/reference/ladder.md`:

````markdown
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
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dcc-superpower-companions/tests/ladder.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-superpower-companions/reference plugins/dcc-superpower-companions/tests/ladder.test.sh
git commit -m "feat(companions): add assignment and escalation tables"
```

---

### Task 4: The trigger hook

**Files:**
- Create: `plugins/dcc-superpower-companions/tests/hook.test.sh`
- Create: `plugins/dcc-superpower-companions/scripts/tier-nudge.sh`
- Create: `plugins/dcc-superpower-companions/hooks/hooks.json`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a `PreToolUse` hook registered on the `Skill` tool. `scripts/tier-nudge.sh` reads the hook payload on stdin, inspects `.tool_input.skill`, and prints a JSON object with `hookSpecificOutput.hookEventName = "PreToolUse"`, `permissionDecision = "defer"`, and a non-empty `additionalContext` for exactly two skill names. For every other input it prints nothing and exits 0.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-superpower-companions/tests/hook.test.sh`:

```bash
#!/usr/bin/env bash
# The hook must fire for exactly two superpowers skills and stay silent for
# everything else.
#
# superpowers:executing-plans is deliberately NOT matched: it runs plan tasks
# inline in the current session without subagents, so nudging it toward tiered
# dispatch would push it to do the one thing it is designed not to do.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/tier-nudge.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

run() { # run <skill-name> - feed a synthetic PreToolUse payload, print stdout
  jq -n --arg s "$1" '{hook_event_name:"PreToolUse",tool_name:"Skill",tool_input:{skill:$s,args:""}}' \
    | bash "$SCRIPT" 2>/dev/null
}

for skill in superpowers:writing-plans superpowers:subagent-driven-development; do
  out=$(run "$skill")
  check "$skill: emits valid JSON" \
    "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
  check "$skill: event name is PreToolUse" \
    "$(jq -r '.hookSpecificOutput.hookEventName // "MISSING"' <<<"$out" 2>/dev/null)" "PreToolUse"
  check "$skill: decision is defer" \
    "$(jq -r '.hookSpecificOutput.permissionDecision // "MISSING"' <<<"$out" 2>/dev/null)" "defer"
  check "$skill: additionalContext is non-empty" \
    "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"
done

check "writing-plans context names the assigning skill" \
  "$(run superpowers:writing-plans | jq -r '.hookSpecificOutput.additionalContext' | grep -c 'assigning-implementers')" "1"
check "subagent-driven-development context names the dispatching skill" \
  "$(run superpowers:subagent-driven-development | jq -r '.hookSpecificOutput.additionalContext' | grep -c 'dispatching-tiered-implementers')" "1"

for skill in superpowers:executing-plans superpowers:brainstorming other:thing ""; do
  label="${skill:-<empty>}"
  check "$label: emits nothing" "$(run "$skill" | wc -c | tr -d ' ')" "0"
done

check "malformed stdin exits 0 and emits nothing" \
  "$(printf 'not json' | bash "$SCRIPT" 2>/dev/null | wc -c | tr -d ' ')" "0"

# hooks.json wiring
HOOKS="$HERE/../hooks/hooks.json"
check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "hooks.json registers a PreToolUse matcher on Skill" \
  "$(jq -r '.hooks.PreToolUse[0].matcher // "MISSING"' "$HOOKS" 2>/dev/null)" "Skill"
check "hooks.json is synchronous (async must not be true)" \
  "$(jq -r '.hooks.PreToolUse[0].hooks[0].async // false' "$HOOKS" 2>/dev/null)" "false"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

```bash
chmod +x plugins/dcc-superpower-companions/tests/hook.test.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/dcc-superpower-companions/tests/hook.test.sh`
Expected: FAIL on the first `emits valid JSON` check, because `scripts/tier-nudge.sh` does not exist.

- [ ] **Step 3: Write the hook script**

```bash
mkdir -p plugins/dcc-superpower-companions/scripts
```

Write `plugins/dcc-superpower-companions/scripts/tier-nudge.sh`:

```bash
#!/usr/bin/env bash
# PreToolUse hook on the Skill tool. Adds context when superpowers is about to
# write or execute a plan, and stays silent otherwise.
#
# The context is phrased as factual project information rather than as an
# instruction: text framed as an out-of-band system command can trip Claude's
# prompt-injection defenses, which surfaces it to the user instead of acting on it.
set -uo pipefail

payload=$(cat)
skill=$(jq -r '.tool_input.skill // empty' <<<"$payload" 2>/dev/null) || exit 0
[ -n "$skill" ] || exit 0

case "$skill" in
  superpowers:writing-plans)
    context="Plans in this repository record an implementer assignment for each task: an \`**Implementer:**\` line naming a dcc-superpower-companions agent, and an \`**Evaluation:**\` line showing the four-axis scores behind it. The dcc-superpower-companions:assigning-implementers skill holds the scoring rubric and the assignment table."
    ;;
  superpowers:subagent-driven-development)
    context="Tasks in this repository's plans carry an \`**Implementer:**\` line naming the subagent that runs them. The dcc-superpower-companions:dispatching-tiered-implementers skill holds the dispatch rules and the escalation ladder, including why implementer dispatches pass no model argument."
    ;;
  *)
    exit 0
    ;;
esac

jq -n --arg c "$context" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "defer",
    additionalContext: $c
  }
}'
```

- [ ] **Step 4: Write the hook registration**

```bash
mkdir -p plugins/dcc-superpower-companions/hooks
```

Write `plugins/dcc-superpower-companions/hooks/hooks.json`:

```json
{
  "description": "Adds implementer-assignment context when superpowers writes or executes a plan.",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/tier-nudge.sh\"",
            "async": false
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash plugins/dcc-superpower-companions/tests/hook.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 6: Validate and commit**

```bash
claude plugin validate .
git add plugins/dcc-superpower-companions/scripts plugins/dcc-superpower-companions/hooks plugins/dcc-superpower-companions/tests/hook.test.sh
git commit -m "feat(companions): add PreToolUse trigger hook"
```

---

### Task 5: The assigning skill

**Files:**
- Create: `plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md`

**Interfaces:**
- Consumes: `reference/ladder.md` from Task 3 (relative path `../../reference/ladder.md`).
- Produces: the plan-document contract that Task 6 reads back. Each task block gains an `**Implementer:**` line holding a fully qualified agent name and an `**Evaluation:**` line holding the four axis scores and their total. The plan header gains one appended blockquote line naming the dispatching skill.

- [ ] **Step 1: Create the skill**

```bash
mkdir -p plugins/dcc-superpower-companions/skills/assigning-implementers
```

Write `plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md`:

````markdown
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

## Score every task

Read the rubric and the assignment table from
[`../../reference/ladder.md`](../../reference/ladder.md). Do not restate the
tables here or work from memory: that file is the single source of truth and it
is what the test suite validates.

Score the task as the plan describes it, not as you imagine it might grow.
"Spec completeness" in particular is a fact about the plan text: if the task's
steps contain the complete code to write, that axis is 0 no matter how clever
the code is.

Sum the four axes and read the agent off the assignment table.

## Write the assignment

Add two lines to each task block, directly below its `**Interfaces:**` block:

```markdown
**Implementer:** dcc-superpower-companions:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 2 - risk 2 = 8
```

The agent name is fully qualified. Plugin subagents are namespaced
`<plugin>:<agent>`, and an unqualified name may not resolve.

Both lines land in the brief the implementer reads, because
superpowers' `scripts/task-brief` copies a task block verbatim. That is
intended: an implementer knowing its task's blast radius is useful context.

## Amend the plan header

Append one blockquote line to the plan header. **Append it; never replace the
existing `REQUIRED SUB-SKILL` line** — that line is what hands off to
superpowers:subagent-driven-development, and replacing it breaks the handoff.

```markdown
> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. REQUIRED SUB-SKILL:
> dcc-superpower-companions:dispatching-tiered-implementers
```

This is what makes the plan carry its own execution instruction, so a session
that opens the plan cold still dispatches correctly.

## Check your work

Before saving the plan:

- Every task has both lines. A task without them gets scored at dispatch time
  instead, which works but loses the audit trail.
- Every agent name is fully qualified and appears in
  `reference/ladder.md`'s assignment table.
- Every `**Evaluation:**` line's four scores actually sum to the stated total,
  and that total maps to the named agent. A total that disagrees with the agent
  is the one error that makes the record actively misleading.

## Overriding

A human can edit any `**Implementer:**` line by hand. The dispatching skill
obeys the line and never recomputes when it is present, so a human ruling
always wins over the rubric. When you override, leave the `**Evaluation:**`
line in place: the gap between the score and the choice is the interesting part.
````

- [ ] **Step 2: Verify the skill loads**

Run: `claude plugin validate .`
Expected: PASS. A malformed skill frontmatter block is the most likely failure; `name` and `description` are both required.

- [ ] **Step 3: Verify the referenced path resolves**

Run: `ls plugins/dcc-superpower-companions/skills/assigning-implementers/../../reference/ladder.md`
Expected: the path prints, confirming the relative link in the skill body resolves to the file Task 3 created.

- [ ] **Step 4: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/assigning-implementers
git commit -m "feat(companions): add assigning-implementers skill"
```

---

### Task 6: The dispatching skill

**Files:**
- Create: `plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md`

**Interfaces:**
- Consumes: `reference/ladder.md` from Task 3, and the `**Implementer:**` line contract from Task 5.
- Produces: the dispatch and escalation rules. Nothing later consumes this; it is the last behavioral component.

- [ ] **Step 1: Create the skill**

```bash
mkdir -p plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers
```

Write `plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md`:

````markdown
---
name: dispatching-tiered-implementers
description: Use when executing a plan whose tasks carry an Implementer line - dispatches the named model and effort tiered subagent and escalates along a defined ladder
---

# Dispatching Tiered Implementers

Run superpowers:subagent-driven-development exactly as written, with one
substitution: the implementer dispatch names a fleet agent instead of
`general-purpose`.

**Announce at start:** "I'm using the dispatching-tiered-implementers skill to
dispatch each task's assigned implementer."

## What changes, and what does not

**Changes.** Exactly one thing: the implementer dispatch passes
`subagent_type: dcc-superpower-companions:impl-<model>-<effort>` and passes **no
`model` argument**.

**Does not change.** The brief and report file protocol, the review package, the
task reviewer, the scoped re-review, the five-round cap, the breaker and its
adjudication rules, the final whole-branch review, and the handoff to
superpowers:finishing-a-development-branch. Reviewer model selection stays
superpowers'. Implementers are still never dispatched in parallel.

## The one superpowers instruction this supersedes

superpowers:subagent-driven-development states in bold that you must always
specify the model explicitly when dispatching a subagent, because an omitted
model inherits the session's model.

**For implementer dispatches only, that is superseded.** The Agent tool's
`model` argument overrides the agent file's `model` frontmatter, but there is no
matching `effort` argument, so effort keeps its frontmatter value. Passing a
model therefore produces a mismatched pairing such as Sonnet running at xhigh.

The rule's intent survives intact: the agent definition pins the model, so
nothing inherits the session default. The rule remains in force for every other
dispatch, including all reviewers.

## Dispatch a task

1. Read the task's `**Implementer:**` line.
2. Dispatch with that value as `subagent_type`, using superpowers'
   `implementer-prompt.md` template unchanged for the prompt body. Where the
   template's header reads `Subagent (general-purpose):`, use the assigned
   agent instead.
3. Record the agent identity from the dispatch result, exactly as superpowers
   requires. Fix rounds 1 to 3 resume this agent.
4. Note the assignment in the ledger superpowers already owns at
   `.superpowers/sdd/<plan-basename>/progress.md`:

   ```
   Task <N>: implementer <agent> (assigned)
   ```

   Never create a competing ledger. Never use the reserved verbs `complete`,
   `fix round`, `parked`, or `BLOCKED` in lines you add: superpowers' crash
   recovery keys on `Task <N>: complete`, and a line it misreads costs a
   re-dispatch of finished work.

## Escalate

Read the escalation table from
[`../../reference/ladder.md`](../../reference/ladder.md). Escalation applies at
exactly two points, both defined by superpowers:

- **Fix rounds 4 and 5**, where superpowers dispatches a fresh implementer on a
  more capable model.
- **The BLOCKED handler**, where superpowers re-dispatches on a more capable
  model when the task requires more reasoning. A BLOCKED report caused by
  missing context is not an escalation: supply the context and re-dispatch the
  same agent, as superpowers says.

Escalation does **not** apply to fix rounds 1 to 3. Those resume the original
agent, which preserves its model, its effort, and its context. Re-dispatching a
different tier there discards exactly what superpowers is preserving.

Record each escalation in the ledger:

```
Task <N>: implementer <new-agent> (escalated from <old-agent>, round <R>)
```

When the ladder is exhausted at `impl-fable-max`, which has no successor, report
BLOCKED through superpowers' existing contract. Do not loop.

## Failure modes

| Situation | Response |
|-----------|----------|
| Task has no `**Implementer:**` line | Score it with the rubric in `reference/ladder.md`, dispatch, and record `Task <N>: implementer <agent> (scored at dispatch)` |
| The line names an agent with no definition file | Stop and ask your human partner. Never fall back silently |
| The model is unavailable on this account | Substitute the same effort one model down, state the substitution in the ledger and to your partner, and continue |
| Escalation exhausted | Report BLOCKED per superpowers |

The silent-fallback rule matters more than it looks. If a bad agent name quietly
degraded to the session default, every task would run at the session's model and
effort and nothing in the output would reveal it. That is precisely the
expensive-model failure superpowers' Model Selection section exists to prevent.

The unavailable-model row exists because Fable is not on every account. Drop the
model one rung and keep the effort. State it; never substitute silently.
````

- [ ] **Step 2: Verify the skill loads**

Run: `claude plugin validate .`
Expected: PASS.

- [ ] **Step 3: Confirm both skills are discoverable**

Run: `ls plugins/dcc-superpower-companions/skills/*/SKILL.md`
Expected: two paths, `assigning-implementers/SKILL.md` and `dispatching-tiered-implementers/SKILL.md`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers
git commit -m "feat(companions): add dispatching-tiered-implementers skill"
```

---

### Task 7: Plugin documentation and full verification

**Files:**
- Create: `plugins/dcc-superpower-companions/README.md`

**Interfaces:**
- Consumes: every component built in Tasks 1 through 6.
- Produces: nothing consumed downstream. This task closes the plan.

- [ ] **Step 1: Write the plugin README**

Write `plugins/dcc-superpower-companions/README.md`:

````markdown
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
````

- [ ] **Step 2: Run the full test suite**

Run:

```bash
for t in plugins/dcc-superpower-companions/tests/*.test.sh; do
  printf '\n=== %s ===\n' "$(basename "$t")"
  bash "$t" || echo "SUITE FAILED: $t"
done
```

Expected: three suites, each ending `0 failed`, and no `SUITE FAILED` line.

- [ ] **Step 3: Validate the marketplace**

Run: `claude plugin validate .`
Expected: PASS.

- [ ] **Step 4: Confirm the manifest, directory, and marketplace names agree**

Run:

```bash
jq -r '.name' plugins/dcc-superpower-companions/.claude-plugin/plugin.json
jq -r '.plugins[] | select(.name | startswith("dcc-")) | "\(.name) \(.source)"' .claude-plugin/marketplace.json
```

Expected: `dcc-superpower-companions`, then `dcc-superpower-companions ./plugins/dcc-superpower-companions`. All three must agree, per the `dcc-` prefix rule in `CLAUDE.md`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-superpower-companions/README.md
git commit -m "docs(companions): add plugin README"
```

---

## Verification

The plan is complete when all of the following hold:

1. `for t in plugins/dcc-superpower-companions/tests/*.test.sh; do bash "$t"; done` reports `0 failed` for all three suites.
2. `claude plugin validate .` passes.
3. `ls plugins/dcc-superpower-companions/agents/*.md | wc -l` prints `16`.
4. The plugin name is identical in the directory name, `plugin.json`, and `marketplace.json`.
