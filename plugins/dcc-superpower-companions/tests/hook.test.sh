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

run_status() { # run_status <skill-name> - feed a synthetic PreToolUse payload, return the script's exit status
  jq -n --arg s "$1" '{hook_event_name:"PreToolUse",tool_name:"Skill",tool_input:{skill:$s,args:""}}' \
    | bash "$SCRIPT" >/dev/null 2>&1
}

for skill in superpowers:writing-plans superpowers:subagent-driven-development; do
  out=$(run "$skill")
  check "$skill: emits valid JSON" \
    "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
  check "$skill: event name is PreToolUse" \
    "$(jq -r '.hookSpecificOutput.hookEventName // "MISSING"' <<<"$out" 2>/dev/null)" "PreToolUse"
  # permissionDecision must stay absent. "defer" in particular is print-mode
  # only: interactive sessions ignore it with a warning, and non-interactive
  # ones defer the Skill call itself so the skill never runs.
  check "$skill: emits no permissionDecision" \
    "$(jq -r '.hookSpecificOutput.permissionDecision // "ABSENT"' <<<"$out" 2>/dev/null)" "ABSENT"
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
  run_status "$skill"
  check "$label: exits 0" "$?" "0"
done

check "malformed stdin exits 0 and emits nothing" \
  "$(printf 'not json' | bash "$SCRIPT" 2>/dev/null | wc -c | tr -d ' ')" "0"

printf 'not json' | bash "$SCRIPT" >/dev/null 2>&1
check "malformed stdin: exits 0" "$?" "0"

# hooks.json wiring
HOOKS="$HERE/../hooks/hooks.json"
check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "hooks.json registers a PreToolUse matcher on Skill" \
  "$(jq -r '.hooks.PreToolUse[0].matcher // "MISSING"' "$HOOKS" 2>/dev/null)" "Skill"
check "hooks.json is synchronous (async must not be true)" \
  "$(jq -r '.hooks.PreToolUse[0].hooks[0].async // false' "$HOOKS" 2>/dev/null)" "false"
# Hook commands default to PowerShell on Windows when Git Bash is absent, where
# "bash" is not a command and ${CLAUDE_PLUGIN_ROOT} is not a variable. This key
# forces the bash route, so such a machine gets Claude Code's actionable
# "requires bash but Git Bash was not found" message instead.
check "hooks.json forces the bash interpreter" \
  "$(jq -r '.hooks.PreToolUse[0].hooks[0].shell // "MISSING"' "$HOOKS" 2>/dev/null)" "bash"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
