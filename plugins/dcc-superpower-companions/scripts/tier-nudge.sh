#!/usr/bin/env bash
# PreToolUse hook on the Skill tool. Adds context when superpowers is about to
# brainstorm an approach, write a plan, or dispatch a plan's tasks, and stays
# silent otherwise.
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

# No permissionDecision: the field is optional, and this hook has no opinion on
# whether the skill may run. Setting "defer" specifically is harmful: it is a
# print-mode-only value, ignored with a warning in an interactive session, and
# in a non-interactive one (claude -p, the SDK, CI) it defers the Skill call
# itself, so the skill never executes.
jq -n --arg c "$context" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $c
  }
}'
