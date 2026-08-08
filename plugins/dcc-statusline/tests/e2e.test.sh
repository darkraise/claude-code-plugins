#!/usr/bin/env bash
# End to end: a payload on stdin produces the finished lines. Asserts on
# ANSI-stripped text, plus one check that the tint and the ramp coexist.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
SCRIPT="$HERE/../scripts/statusline.sh"
F="$HERE/fixtures"

export DCC_NOW=1785886800
export DCC_STATUSLINE_CONFIG=/dev/null
export DCC_ICONS=unicode
export COLUMNS=""
# dcc_cells slices characters, which needs a UTF-8 locale in the test shell too;
# the script sets its own, but that does not reach this process.
export LC_ALL=C.UTF-8

# Hermetic account state. An empty CLAUDE_CONFIG_DIR sends the render to the real
# $HOME/.claude.json, which made the result depend on the machine and printed the
# machine owner's actual email address into the test output. A throwaway home with
# a fixture account file removes both problems, and keeps the resolved config key
# at "~/.claude" so the tint assertions still exercise the abbreviated form.
fakehome="$(mktemp -d)"
mkdir -p "$fakehome/.claude"
cp "$F/claude.json" "$fakehome/.claude/.claude.json"
export HOME="$fakehome"
export CLAUDE_CONFIG_DIR="$fakehome/.claude"

out="$(bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
line1="$(printf '%s\n' "$out" | sed -n 1p)"
line2="$(printf '%s\n' "$out" | sed -n 2p)"

check "line one carries model and state chips" \
  "$(printf '%s' "$line1" | grep -c 'Opus  ·  xhigh  ·  fast')" "1"
check "line one no longer carries a think chip" \
  "$(printf '%s' "$line1" | grep -c 'think')" "0"
check "line two carries all three meters" \
  "$(printf '%s' "$line2" | grep -c 'ctx .* 47% · 94k  ·  \$1.20  ·  5h .* 23% · 3h40m  ·  7d .* 41% · 5d22h')" "1"

# A fresh session has no rate_limits and a null percentage, so line two has
# nothing but cost -- and must not print as a bare separator.
out="$(bash "$SCRIPT" < "$F/fresh.json" | strip_ansi)"
line2="$(printf '%s\n' "$out" | sed -n 2p)"
check "a fresh session shows only cost on line two" "$line2" "\$0.00"
check "no doubled separator when meters are absent" \
  "$(printf '%s' "$line2" | grep -c '·  ·')" "0"

# Empty stdin must not produce a traceback or a stray line.
out="$(printf '' | bash "$SCRIPT" 2>&1)"; rc=$?
check "empty stdin renders nothing" "$out" ""
check "empty stdin exits 0" "$rc" "0"

# Whitespace-only stdin holds no JSON value, so jq exits 0 having eval'd
# nothing at all -- dcc_parse_all "succeeds" without ever assigning the
# config globals. The render must still degrade to nothing, not abort on
# an unbound variable.
out="$(printf '   ' | bash "$SCRIPT" 2>&1)"; rc=$?
check "whitespace-only stdin renders nothing" "$out" ""
check "whitespace-only stdin exits 0" "$rc" "0"

# A malformed config still renders, with a visible marker.
badcfg="$(mktemp)"; printf '{ not json' > "$badcfg"
out="$(DCC_STATUSLINE_CONFIG="$badcfg" bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
check "a malformed config renders with a marker" \
  "$(printf '%s' "$out" | grep -c 'cfg?')" "1"
rm -f "$badcfg"

# A glob as a segment name must stay a literal unknown name. Unquoted, the
# name loops would expand "*" against the working directory, and a file named
# after a segment would render one the user never configured. The directory
# plants exactly that trap: a file named "time".
cfgg="$(mktemp)"; printf '{ "lines": [["*"],["cost"]], "frame": "none" }' > "$cfgg"
globdir="$(mktemp -d)"; touch "$globdir/time"
out="$(cd "$globdir" && DCC_STATUSLINE_CONFIG="$cfgg" bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
check "a glob segment name renders nothing" \
  "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"
check "the remaining line is the cost chip alone" \
  "$(printf '%s\n' "$out" | sed -n 1p)" "\$1.20"
rm -f "$cfgg"; rm -rf "$globdir"

# Tint and ramp coexist: the ramp paints the meters regardless of mode, while
# which element carries the account tint depends on whether the frame is on --
# framed mode puts it on the top rule, unframed mode puts it on the account
# chip. Each is checked against the render it actually appears in below.
cfg="$(mktemp)"
cat > "$cfg" <<'JSON'
{ "accounts": { "~/.claude": { "color": "magenta" } } }
JSON
raw="$(DCC_STATUSLINE_CONFIG="$cfg" bash "$SCRIPT" < "$F/full.json")"
raw1="$(printf '%s\n' "$raw" | sed -n 1p)"
raw2="$(printf '%s\n' "$raw" | sed -n 2p)"
# The account-chip check below alone would still read yes if raw1 had captured
# line two by mistake, since line two's cost chip and separators share the
# ramp's own colors. Requiring the model chip closes the gap: it only ever
# appears on line one.
is_line1="no"; printf '%s' "$raw1" | grep -q 'Opus' && is_line1="yes"
check "the captured line is actually line one" "$is_line1" "yes"
# Counted with grep -o. grep -c counts matching *lines*, so it reads 1 no matter
# how many meters are on the line -- and reads 0 the moment a user's config moves
# one of them to the other line.
check "every meter on line two takes the ramp color" \
  "$(printf '%s' "$raw2" | grep -o $'\033\\[38;5;10m' | wc -l | tr -d ' ')" "3"

# Without a frame, the account chip itself must carry the tint -- the one
# at-a-glance account signal available when the terminal is too narrow to draw
# a border. Matched as the exact code immediately prefixing the email, not as
# a count of dim-magenta anywhere on the line: this repo's own git segment
# renders live, and its dirty/ahead/behind/untracked markers also paint dim
# with the default git palette color, which is coincidentally "magenta" too --
# a count would pass or fail with this repo's working-tree state, not with
# whether the account chip is actually tinted.
check "an unframed render tints the account chip" \
  "$(printf '%s' "$raw1" | grep -c $'\033\\[2;38;5;13msomeone@example.com')" "1"

# In framed mode the account moves onto the top rule, so the tint must appear
# there instead of on any content line. Matched by color number with any
# weight prefix: the corners and rule dashes are painted plain but the title is
# bold, and hard-coding one weight is exactly what made this check brittle
# before -- it was only ever matching the git segment's coincidentally-shared
# palette color, never the account tint at all.
framed="$(COLUMNS=100 DCC_STATUSLINE_CONFIG="$cfg" bash "$SCRIPT" < "$F/full.json")"
top="$(printf '%s\n' "$framed" | sed -n 1p)"
tint="no"; printf '%s' "$top" | grep -q $'\033\\[[0-9;]*38;5;13m' && tint="yes"
check "the account tint paints the framed top rule" "$tint" "yes"

# The same account directory spelled the way Windows hands it over must resolve to
# the same "~/.claude" key. When it does not, the tint silently never applies and
# the account file is never found -- with no error anywhere to say so. Framed, so
# the tint is checked on the top rule like the case above.
bs="$(printf '%s' "$CLAUDE_CONFIG_DIR" | tr '/' '\\')"
top="$(CLAUDE_CONFIG_DIR="$bs" DCC_STATUSLINE_CONFIG="$cfg" COLUMNS=100 bash "$SCRIPT" < "$F/full.json" | sed -n 1p)"
tint="no"; printf '%s' "$top" | grep -q $'\033\\[[0-9;]*38;5;13m' && tint="yes"
check "a backslash-spelled config dir still applies the tint" "$tint" "yes"
check "a backslash-spelled config dir still finds the account file" \
  "$(printf '%s' "$top" | strip_ansi | grep -c 'someone@example.com')" "1"
rm -f "$cfg"

# --- framed mode --------------------------------------------------------------
out="$(COLUMNS=100 bash "$SCRIPT" < "$F/full.json")"
check "a framed render prints four rows" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "4"

DCC_ICON_W=0
rowno=0
while IFS= read -r row; do
  rowno=$(( rowno + 1 ))
  dcc_cells "$row"
  check "framed row $rowno measures the inset width" "$DCC_CELLS" "96"
done < <(printf '%s\n' "$out")

# Nerd icon mode, framed: the only path that exercises detection cache ->
# dcc_icons_init -> segments charging DCC_ICON_W cells per icon -> dcc_frame_top
# receiving the icon and its width, all at once. Every other check in this file
# forces DCC_ICONS=unicode, so a mischarge anywhere on that chain would pass
# unnoticed. DCC_ICON_W=2 below matches the width dcc_icons_init defaults to
# for nerd mode when no cache or config overrides it (see lib/icons.sh).
out="$(COLUMNS=100 DCC_ICONS=nerd bash "$SCRIPT" < "$F/full.json")"
check "a framed nerd-mode render prints four rows" \
  "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "4"

DCC_ICON_W=2
rowno=0
while IFS= read -r row; do
  rowno=$(( rowno + 1 ))
  dcc_cells "$row"
  check "framed nerd-mode row $rowno measures the inset width" "$DCC_CELLS" "96"
done < <(printf '%s\n' "$out")

check "the account address is on the top rule" \
  "$(printf '%s\n' "$out" | sed -n 1p | strip_ansi | grep -c 'someone@example.com')" "1"
check "the account address is not repeated inside" \
  "$(printf '%s\n' "$out" | sed -n 2p | strip_ansi | grep -c 'someone@example.com')" "0"

# Regression: nothing stops a user putting "account" on line two, and the top
# rule is drawn from P_EMAIL regardless of which line configured it. Stripping
# only line one would render the address twice -- once on the rule, once
# inline on line two. Counted across the whole (four-row) output, not per
# line, since the bug is precisely that it appears on two different rows.
cfg2="$(mktemp)"; printf '{ "lines": [["dir","model"],["ctx","account"]] }' > "$cfg2"
out="$(COLUMNS=100 DCC_STATUSLINE_CONFIG="$cfg2" bash "$SCRIPT" < "$F/full.json")"
check "the account address appears exactly once when configured on line two" \
  "$(printf '%s\n' "$out" | strip_ansi | grep -o 'someone@example.com' | wc -l | tr -d ' ')" "1"
rm -f "$cfg2"

# Too narrow to frame: falls back to the plain two-line layout.
out="$(COLUMNS=30 bash "$SCRIPT" < "$F/full.json")"
check "a narrow terminal falls back to two rows" \
  "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"

# Explicitly disabled.
cfgnf="$(mktemp)"; printf '{ "frame": "none" }' > "$cfgnf"
out="$(COLUMNS=100 DCC_STATUSLINE_CONFIG="$cfgnf" bash "$SCRIPT" < "$F/full.json")"
check "frame none renders two rows" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"
rm -f "$cfgnf"

# --- the frame is inset from the reported terminal width ----------------------
# Drawing to the full COLUMNS put the right wall past the visible edge of the
# host's status-line region and clipped it.
cfgm="$(mktemp)"; printf '{ "frameMargin": 6 }' > "$cfgm"
top="$(DCC_STATUSLINE_CONFIG="$cfgm" COLUMNS=100 bash "$SCRIPT" < "$F/full.json" | sed -n 1p)"
DCC_ICON_W=0
dcc_cells "$top"
check "a configured margin is honoured end to end" "$DCC_CELLS" "94"

printf '{ "frameMargin": 0 }' > "$cfgm"
top="$(DCC_STATUSLINE_CONFIG="$cfgm" COLUMNS=100 bash "$SCRIPT" < "$F/full.json" | sed -n 1p)"
dcc_cells "$top"
check "a margin of zero draws the full reported width" "$DCC_CELLS" "100"
rm -f "$cfgm"

# --- frame integrity across widths --------------------------------------------
# Tier escalation changes how many cells a row occupies, so every width has to
# be checked, not just the one that happens to fit at tier 0. A row that is one
# cell wrong leaves a ragged right wall down the entire box.
DCC_ICON_W=0
for cols in 52 60 72 88 100 140 200; do
  out="$(COLUMNS=$cols bash "$SCRIPT" < "$F/full.json")"
  want=$(( cols - 4 ))   # the default frameMargin
  check "COLUMNS=$cols prints four rows" \
    "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "4"
  rowno=0
  while IFS= read -r row; do
    rowno=$(( rowno + 1 ))
    dcc_cells "$row"
    check "COLUMNS=$cols row $rowno measures $want cells" "$DCC_CELLS" "$want"
  done < <(printf '%s\n' "$out")
done

# The same sweep in nerd mode, where every icon charges two cells rather than
# one. A tier that forgets to charge for an icon it still emits shows up here
# and nowhere else.
DCC_ICON_W=2
for cols in 52 88 140; do
  out="$(COLUMNS=$cols DCC_ICONS=nerd bash "$SCRIPT" < "$F/full.json")"
  want=$(( cols - 4 ))
  rowno=0
  while IFS= read -r row; do
    rowno=$(( rowno + 1 ))
    dcc_cells "$row"
    check "nerd COLUMNS=$cols row $rowno measures $want cells" "$DCC_CELLS" "$want"
  done < <(printf '%s\n' "$out")
done
DCC_ICON_W=0

# maxTier 0 must reproduce today's behaviour: no escalation, and the greedy drop
# doing the fitting.
#
# Width alone cannot show that. dcc_frame_row pads every row to the frame width
# whichever tier produced it, so a width assertion passes identically with
# escalation on or off -- it re-tests padding, not the config. Two things
# actually distinguish the pinned render: it differs from the default at the
# same width, and tier 0 is the only tier that never elides a path or truncates
# a branch, so no ellipsis can appear in it.
cfgt="$(mktemp)"; printf '{ "responsive": { "maxTier": 0 } }' > "$cfgt"
out="$(DCC_STATUSLINE_CONFIG="$cfgt" COLUMNS=60 bash "$SCRIPT" < "$F/full.json")"
rowno=0
while IFS= read -r row; do
  rowno=$(( rowno + 1 ))
  dcc_cells "$row"
  check "maxTier 0 row $rowno still measures 56 cells" "$DCC_CELLS" "56"
done < <(printf '%s\n' "$out")

pinned="$(printf '%s' "$out" | strip_ansi)"
defaulted="$(COLUMNS=60 bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
same="no"; [ "$pinned" = "$defaulted" ] && same="yes"
check "maxTier 0 changes what renders at this width" "$same" "no"
check "maxTier 0 never elides a path or truncates a branch" \
  "$(printf '%s' "$pinned" | grep -c '…')" "0"
rm -f "$cfgt"

# --- per-line separators ------------------------------------------------------
cfgs="$(mktemp)"
printf '{ "separator": [" | ", " / "], "frame": "none" }' > "$cfgs"
out="$(DCC_STATUSLINE_CONFIG="$cfgs" bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
check "line one uses the first separator" \
  "$(printf '%s\n' "$out" | sed -n 1p | grep -c ' | ')" "1"
check "line two uses the second separator" \
  "$(printf '%s\n' "$out" | sed -n 2p | grep -c ' / ')" "1"

# A one-element array applies to both lines.
printf '{ "separator": [" | "], "frame": "none" }' > "$cfgs"
out="$(DCC_STATUSLINE_CONFIG="$cfgs" bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
check "a short array reuses its last element" \
  "$(printf '%s\n' "$out" | sed -n 2p | grep -c ' | ')" "1"

# An empty array is not a separator; the default stands.
printf '{ "separator": [], "frame": "none" }' > "$cfgs"
out="$(DCC_STATUSLINE_CONFIG="$cfgs" bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
check "an empty array falls back to the default" \
  "$(printf '%s\n' "$out" | sed -n 1p | grep -c '  ·  ')" "1"
rm -f "$cfgs"


# --- narrow terminals fit ------------------------------------------------------
# Below the framing threshold the width is still known, so the line must shrink
# to it. Before this was fixed, every width below 52 rendered tier 0 unbounded
# and the host truncated it -- the responsive feature did nothing precisely
# where it was needed most.
DCC_ICON_W=0
for cols in 40 44 48 50; do
  out="$(COLUMNS=$cols bash "$SCRIPT" < "$F/full.json")"
  check "COLUMNS=$cols renders two unframed rows" \
    "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"
  rowno=0
  while IFS= read -r row; do
    rowno=$(( rowno + 1 ))
    dcc_cells "$row"
    ok="no"; [ "$DCC_CELLS" -le $(( cols - 4 )) ] && ok="yes"
    check "COLUMNS=$cols row $rowno fits the budget" "$ok" "yes"
  done < <(printf '%s\n' "$out")
done

# An unknown width must still render tier 0 unbounded -- the one path this
# change must not touch.
out="$(env -u COLUMNS bash "$SCRIPT" < "$F/full.json" | strip_ansi)"
check "an absent COLUMNS still shows the full path" \
  "$(printf '%s\n' "$out" | sed -n 1p | grep -c 'Repositories')" "1"

rm -rf "$fakehome"
finish
