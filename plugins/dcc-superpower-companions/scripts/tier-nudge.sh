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
