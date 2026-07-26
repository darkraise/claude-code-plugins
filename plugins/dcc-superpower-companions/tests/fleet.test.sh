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
