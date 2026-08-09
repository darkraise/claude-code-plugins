#!/usr/bin/env bash
# The five-process render budget, measured rather than grepped for. Every
# external binary is replaced by a logging shim that forwards to the real one,
# PATH is restricted to the shim directory alone, and the counts are asserted
# exactly: one jq, two git, two timeout wrappers. A stray $(date +%s) added to
# the render path would pass every rendering assertion and cost 10-20ms per
# keystroke; it fails here and nowhere else.
#
# This measures the cold-cache path: one collect, one cache write. The cache
# directory is pointed at a temp dir this file owns and pre-creates, because
# mkdir is not among the shims below: with the directory absent, dcc_cache_dir's
# own mkdir would fail silently on the restricted PATH, DCC_CACHE_DIR would come
# back empty, and the render would fall straight through to an uncached collect
# -- the same counts as the cache-engaged path this file means to measure, so
# nothing would fail, but the run would silently stop proving the cache write
# itself costs no process. Pre-creating it makes this the cache-engaged cold
# path instead. Pointing it elsewhere -- or leaving it to default to the real
# machine's $TMPDIR/dcc-statusline-$UID/ -- would let a warm entry left by
# another test (or a previous run of this file, since the clock below is frozen
# and a frozen stamp never ages out) silently turn this into a cache-hit render
# that reports zero git calls instead of failing loudly.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../scripts/statusline.sh"
F="$HERE/fixtures"

export DCC_NOW=1785886800
export DCC_STATUSLINE_CONFIG=/dev/null
export DCC_ICONS=unicode
export COLUMNS=100
export LC_ALL=C.UTF-8

# Hermetic account state, as in e2e.test.sh: without it the render reads the
# machine owner's real ~/.claude.json.
fakehome="$(mktemp -d)"
mkdir -p "$fakehome/.claude"
cp "$F/claude.json" "$fakehome/.claude/.claude.json"
export HOME="$fakehome"
export CLAUDE_CONFIG_DIR="$fakehome/.claude"

# Real paths captured BEFORE PATH is restricted; the shims must forward to
# them or the render fails silently and a passing count proves nothing.
REAL_BASH="$(command -v bash)"
REAL_JQ="$(command -v jq)"
REAL_GIT="$(command -v git)"
REAL_TIMEOUT="$(command -v timeout)"
check "the real jq exists" "$([ -n "$REAL_JQ" ] && echo yes)" "yes"
check "the real git exists" "$([ -n "$REAL_GIT" ] && echo yes)" "yes"
check "the real timeout exists" "$([ -n "$REAL_TIMEOUT" ] && echo yes)" "yes"

shims="$(mktemp -d)"
log="$shims/calls.log"
: > "$log"

# Created now, with the real mkdir, before PATH is restricted to the shims
# below -- dcc_cache_dir's own mkdir would otherwise be unreachable and the
# cache would disengage instead of being measured.
export DCC_CACHE_HOME="$shims/cachehome"
mkdir -p "$DCC_CACHE_HOME/dcc-statusline-$UID"

make_shim() { # make_shim <name> <real-path>
  # The shebang is the real bash by absolute path: /usr/bin/env would search
  # the restricted PATH and find nothing.
  printf '#!%s\nprintf "%%s\\n" "%s" >> "%s"\nexec "%s" "$@"\n' \
    "$REAL_BASH" "$1" "$log" "$2" > "$shims/$1"
  chmod +x "$shims/$1"
}
make_shim jq "$REAL_JQ"
make_shim git "$REAL_GIT"
make_shim timeout "$REAL_TIMEOUT"

# One run, stdout and stderr captured separately. The stderr assertion is
# load-bearing: a call to a binary that is neither shimmed nor on the
# restricted PATH leaves every count intact -- its only trace is bash's
# "command not found" on stderr.
err="$(PATH="$shims" "$REAL_BASH" "$SCRIPT" < "$F/full.json" 2>&1 >"$shims/out.raw")"
out="$(strip_ansi < "$shims/out.raw")"
check "the restricted render writes nothing to stderr" "$err" ""

# The render must actually have produced the full framed output: a count of
# zero calls is exactly what a render that died on the spot would log too.
check "the restricted render prints four rows" \
  "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "4"
check "the restricted render carries the model chip" \
  "$(printf '%s' "$out" | grep -c 'Opus')" "1"
check "the restricted render carries the meters" \
  "$(printf '%s' "$out" | grep -c 'ctx .* 47%')" "1"

check "a render costs exactly one jq" \
  "$(grep -c '^jq$' "$log")" "1"
check "a render costs exactly two git" \
  "$(grep -c '^git$' "$log")" "2"
check "a render costs exactly two timeout wrappers" \
  "$(grep -c '^timeout$' "$log")" "2"
check "a render costs five processes in total" \
  "$(wc -l < "$log" | tr -d ' ')" "5"

rm -rf "$shims" "$fakehome"
finish
