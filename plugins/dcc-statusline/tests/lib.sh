#!/usr/bin/env bash
set -uo pipefail
# Shared assertions. Every *.test.sh sources this, then calls finish at the end.
pass=0 fail=0

check() { # check <label> <got> <want>
  if [ "$2" = "$3" ]; then
    printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else
    printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  fi
}

finish() { printf '\n%d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }

# Test-only: strips SGR sequences so assertions compare visible text.
strip_ansi() { sed -E $'s/\033\\[[0-9;]*m//g'; }

# Test-only: measures a rendered row in terminal cells. Strips SGR sequences,
# then counts private-use characters as DCC_ICON_W cells and everything else as
# one. Callers must be running under a UTF-8 locale, or bash slices bytes.
DCC_TEST_ESC=$'\033'
dcc_cells() { # dcc_cells <string> -> DCC_CELLS
  local s="${1:-}" ch cp n=0
  DCC_CELLS=0
  while [ -n "$s" ]; do
    # A case pattern cannot be used here: "$DCC_TEST_ESC[" would open a bracket
    # expression rather than match an escape introducer literally.
    if [ "${s:0:2}" = "$DCC_TEST_ESC[" ]; then
      s="${s#*m}"
    else
      ch="${s:0:1}"; s="${s:1}"
      printf -v cp '%d' "'$ch"
      if [ "$cp" -ge 57344 ] && [ "$cp" -le 63743 ]; then
        n=$(( n + ${DCC_ICON_W:-1} ))
      else
        n=$(( n + 1 ))
      fi
    fi
  done
  DCC_CELLS="$n"
}

# Test-only: a git that records every invocation and answers from fixtures, so a
# test can assert how many times the render path actually shelled out. The caller
# exports GIT_CALLS, GIT_PORCELAIN and GIT_ROOT to point it at its own files.
dcc_stub_git() { # dcc_stub_git <bin-dir>
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/git" <<'SH'
#!/usr/bin/env bash
printf 'call\n' >> "$GIT_CALLS"
case " $* " in
  *" --porcelain=v2 "*)  cat "$GIT_PORCELAIN" ;;
  *" --show-toplevel "*) printf '%s\n' "$GIT_ROOT" ;;
esac
SH
  chmod +x "$bin/git"
  PATH="$bin:$PATH"
}
