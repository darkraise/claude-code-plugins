#!/usr/bin/env bash
# The fleet is ten agents in two classes. Seven implementers pin one
# model/effort pairing each and carry the full toolset. Three role agents -
# two judges and one scout - are read-only by registry: their tools list omits
# Edit, Write, NotebookEdit, and Agent, so "reviewers do not mutate the tree"
# and "reviewers do not spawn subagents" are enforced rather than requested.
#
# Haiku 4.5 does not support reasoning effort at all, so impl-haiku must NOT
# carry an effort field. The xhigh and max levels are retired everywhere, and
# no implementer runs on Fable.
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

EXPECTED="impl-haiku impl-opus-high impl-opus-low impl-opus-medium impl-sonnet-high impl-sonnet-low impl-sonnet-medium judge-fable judge-opus scout-sonnet"
ROLE_TOOLS="Read, Grep, Glob, WebFetch"

actual=$(cd "$AGENTS" 2>/dev/null && ls *.md 2>/dev/null | sed 's/\.md$//' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "fleet contains exactly the 10 expected agents" "$actual" "$EXPECTED"

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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
