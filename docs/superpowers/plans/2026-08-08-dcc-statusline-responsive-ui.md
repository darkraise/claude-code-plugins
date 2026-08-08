# dcc-statusline Responsive UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dcc-statusline status line adapt to terminal width by shrinking segments instead of dropping them, add named themes and per-segment options, and ship a preview/validate/schema surface for its config.

**Architecture:** Each segment gains a tier parameter (0 full → 3 minimal). A line is rendered at tier 0, measured, and re-rendered one tier higher until it fits the frame budget; the existing greedy segment-drop stays as the last resort. Themes and segment options are resolved inside the single existing `jq` call. Validation and preview live in files that `statusline.sh` never sources.

**Tech Stack:** Bash 4+ (Git Bash / MSYS2 on Windows), `jq`, `git`. No other runtime dependencies. Tests are plain bash scripts using `tests/lib.sh`.

## Global Constraints

- **Process budget: five processes per render** — one `jq`, two `git`, plus their `timeout` wrappers. No task may add a fork to the render path.
- **No `$(...)` anywhere in `scripts/` render-path files.** Functions return values through global out-variables. `scripts/preview.sh` and `scripts/lib/validate.sh` are exempt — they are not on the render path.
- **`scripts/statusline.sh` must never source `scripts/lib/validate.sh`.** Asserted by a test.
- **Every framed row must be exactly `DCC_FRAME_COLS` cells.** A miscount by one leaves a ragged right wall down the whole box.
- **`LC_ALL=C.UTF-8`** is set by `statusline.sh`; without it bash measures bytes, not characters. Tests that measure cells must export it themselves.
- **All glyphs in `scripts/` are written as octal UTF-8 escapes** (`printf -v v '\342\200\246'`) so source files stay pure ASCII.
- **Any text whose character count differs from its terminal cell count must pass an explicit cell count to `dcc_seg_add`.** ASCII and single-cell Unicode may omit it.
- **Tier 0 output must remain byte-for-byte identical to today's** for every existing fixture.
- **Plugin name prefix `dcc-`** must agree across `plugins/dcc-statusline/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and the directory name.
- **Run `claude plugin validate .` from the repo root before committing any manifest change.**
- **Commit format:** `<type>(<scope>): <subject>`, subject ≤50 chars, imperative, no period.
- **Run the full suite** with `bash plugins/dcc-statusline/tests/run-all.sh` before every commit.

---

## File Structure

**Created:**

| File | Responsibility |
|------|----------------|
| `plugins/dcc-statusline/scripts/lib/jq-prog.sh` | The single jq program, the default config, and the theme table |
| `plugins/dcc-statusline/scripts/lib/validate.sh` | Config diagnostics. Off the render path. Forks freely |
| `plugins/dcc-statusline/scripts/preview.sh` | Renders the real config at several widths |
| `plugins/dcc-statusline/dcc-statusline.schema.json` | JSON Schema for the config file |
| `plugins/dcc-statusline/tests/tiers.test.sh` | Per-segment tier renderings and monotonic shrink |
| `plugins/dcc-statusline/tests/theme.test.sh` | Theme table and merge order |
| `plugins/dcc-statusline/tests/validate.test.sh` | Diagnostics, plus the budget-boundary assertion |
| `plugins/dcc-statusline/tests/preview.test.sh` | Preview output shape and flags |

**Modified:**

| File | Change |
|------|--------|
| `scripts/lib/config.sh` | Loses the jq program; gains the new config globals and their defaults |
| `scripts/lib/render.sh` | Gains `dcc_line_measure`, `_dcc_trunc` |
| `scripts/lib/segments.sh` | Gains the tier parameter, tier branches, `_dcc_render_line`, `dcc_line_fit`, the `time` segment |
| `scripts/statusline.sh` | Sources `jq-prog.sh`; calls `dcc_line_fit` instead of `_dcc_emit_line` + `dcc_line_build` |
| `scripts/install.sh` | `doctor` calls `dcc_validate`; `dcc_seed_config` writes `$schema` |
| `commands/dcc-statusline.md` | `preview` and `config` subcommands |
| `README.md` | Tiers, themes, segment options, preview |
| `scripts/VERSION`, `.claude-plugin/plugin.json` | 0.4.0 → 0.5.0 |

---

# Phase 1 — Responsive tiers

### Task 1: Extract the jq program

Pure refactor. `config.sh` is 236 lines of which 50 are the jq program, and Phase 2 roughly triples that program. Moving it first keeps every later diff readable.

**Files:**
- Create: `plugins/dcc-statusline/scripts/lib/jq-prog.sh`
- Modify: `plugins/dcc-statusline/scripts/lib/config.sh:7-101` (remove `DCC_DEFAULT_CONFIG` and `DCC_JQ_PROG`)
- Modify: `plugins/dcc-statusline/scripts/statusline.sh:19-26` (add the source line)
- Modify: `plugins/dcc-statusline/scripts/install.sh:15-16` (add the source line)

**Interfaces:**
- Consumes: nothing.
- Produces: `DCC_DEFAULT_CONFIG` (JSON string) and `DCC_JQ_PROG` (jq program string), both moved verbatim from `config.sh`. `dcc_parse_all` continues to read them as globals.

- [ ] **Step 1: Run the suite to establish a green baseline**

```bash
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: every file reports `0 failed`. Record the total pass count — Step 5 must match it.

- [ ] **Step 2: Create `jq-prog.sh` with the moved content**

Create `plugins/dcc-statusline/scripts/lib/jq-prog.sh` containing this header, then the **exact** current text of `DCC_DEFAULT_CONFIG` (config.sh lines 7-37) and `DCC_JQ_PROG` (config.sh lines 49-101), including their comments, moved without a single character changed:

```bash
#!/usr/bin/env bash
set -uo pipefail
# The single jq call's program text, its default config, and the theme table.
#
# Split out of config.sh so that file holds only path resolution, the payload
# globals and the fallback chain. The program parses three things at once --
# the payload on stdin, the user config, and the account's .claude.json --
# because each extra jq process costs a fork, and the render path budgets five
# processes total.

# <DCC_DEFAULT_CONFIG moved verbatim from config.sh lines 7-37>

# <DCC_JQ_PROG moved verbatim from config.sh lines 49-101>
```

- [ ] **Step 3: Delete the moved blocks from `config.sh`**

Remove lines 7-37 (`DCC_DEFAULT_CONFIG=...`) and lines 49-101 (the comment block plus `DCC_JQ_PROG=...`). Leave everything else untouched. `config.sh` now begins with the `#!/usr/bin/env bash` / `set -uo pipefail` pair followed by the `P_EMAIL=""` defaults block.

- [ ] **Step 4: Add the source line to both entry points**

In `scripts/statusline.sh`, insert after the `lib/path.sh` line (currently line 19) so it precedes `lib/config.sh`:

```bash
source "$DCC_DIR/lib/jq-prog.sh"
```

In `scripts/install.sh`, insert between the `lib/path.sh` and `lib/config.sh` source lines (currently lines 15-16):

```bash
source "$DCC_SRC_DIR/lib/jq-prog.sh"
```

- [ ] **Step 5: Run the suite and confirm the count is unchanged**

```bash
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: identical pass count to Step 1, `0 failed`. A refactor that changes a count has changed behaviour.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-statusline/scripts/
git commit -m "refactor(statusline): split jq program into its own file"
```

---

### Task 2: Tier parameter and the `dir` tiers

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/render.sh` (add `_dcc_trunc`)
- Modify: `plugins/dcc-statusline/scripts/lib/segments.sh:51-103` (`dcc_segment` signature, `dir` branch)
- Create: `plugins/dcc-statusline/tests/tiers.test.sh`

**Interfaces:**
- Consumes: `dcc_seg_add`, `dcc_seg_reset`, `dcc_path_norm` (unchanged).
- Produces:
  - `dcc_segment <name> [tier]` — `tier` is `0`–`3`, defaulting to `0`. Every existing single-argument call site keeps working.
  - `_dcc_trunc <text> <maxlen>` → sets `DCC_TRUNC`. Returns `text` unchanged when `maxlen` is `0` or `${#text} <= maxlen`; otherwise the first `maxlen-1` characters plus `…` (U+2026, one cell). `DCC_TRUNC` is therefore never wider than `maxlen`.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/tiers.test.sh`:

```bash
#!/usr/bin/env bash
# Per-segment tier renderings. Tier 0 must reproduce today's output exactly;
# every higher tier must be no wider than the one below it, or the escalation
# loop in dcc_line_fit would never terminate.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/path.sh"
source "$HERE/../scripts/lib/color.sh"
source "$HERE/../scripts/lib/render.sh"
source "$HERE/../scripts/lib/git.sh"
source "$HERE/../scripts/lib/segments.sh"

export LC_ALL=C.UTF-8

DCC_RAMP="0:green: 50:yellow: 75:orange: 90:red:bold"
DCC_GLYPH_FILLED="#"; DCC_GLYPH_EMPTY="."; DCC_GLYPH_DIRTY="*"
DCC_W_CTX=10; DCC_W_5H=8; DCC_W_7D=8
DCC_SHOW_ETA=1; DCC_SHOW_TOKENS=1
DCC_NOW=1785886800
DCC_ICON_MODE="unicode"; DCC_ICON_W=0
DCC_I_DIR=""; DCC_I_GIT=""; DCC_I_MODEL=""; DCC_I_FAST=""
DCC_I_ACCOUNT=""; DCC_I_CTX=""; DCC_I_CLOCK=""; DCC_I_COST=""
DCC_P_DIR="blue"; DCC_P_GIT="magenta"; DCC_P_MODEL="cyan"
DCC_P_EFFORT="gray"; DCC_P_FAST="white"; DCC_P_COST="141"; DCC_P_MUTE="gray"
DCC_P_EFF_LOW="gray"; DCC_P_EFF_MEDIUM="blue"; DCC_P_EFF_HIGH="cyan"
DCC_P_EFF_XHIGH="141"; DCC_P_EFF_MAX="magenta"

segt() { # segt <name> <tier> -> the visible text at that tier
  dcc_seg_reset
  dcc_segment "$1" "$2"
  printf '%s' "$DCC_SEG_OUT" | strip_ansi
}
segtcells() { dcc_seg_reset; dcc_segment "$1" "$2"; printf '%s' "$DCC_SEG_CELLS"; }

# --- _dcc_trunc ---------------------------------------------------------------
_dcc_trunc "feature/responsive-tiers" 0
check "trunc with maxlen 0 is a no-op" "$DCC_TRUNC" "feature/responsive-tiers"
_dcc_trunc "main" 10
check "trunc leaves a short string alone" "$DCC_TRUNC" "main"
_dcc_trunc "feature/responsive-tiers" 10
check "trunc cuts and ellipsises" "$DCC_TRUNC" "feature/re…"
check "trunc keeps maxlen characters plus the ellipsis" "${#DCC_TRUNC}" "11"

# --- dir ----------------------------------------------------------------------
HOME="/home/u"
DCC_GIT_ROOT="/home/u/Repos/Personal/claude-code-plugins"
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"

check "dir tier 0 is the full path" "$(segt dir 0)" \
  "~/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"
check "dir tier 1 drops the ancestry" "$(segt dir 1)" \
  "claude-code-plugins/plugins/dcc-statusline"
check "dir tier 2 elides the middle" "$(segt dir 2)" \
  "claude-code-plugins/…/dcc-statusline"
check "dir tier 3 is the leaf alone" "$(segt dir 3)" "dcc-statusline"

# At the repo root there is no sub-path, so tier 2 has nothing to elide and
# must not emit a dangling separator.
P_CWD="/home/u/Repos/Personal/claude-code-plugins"
check "dir tier 2 at the repo root is the repo name" "$(segt dir 2)" "claude-code-plugins"
check "dir tier 3 at the repo root is the repo name" "$(segt dir 3)" "claude-code-plugins"

# One component below the root: tier 2's elision would be longer than the text
# it replaces, so tier 2 must fall back to tier 1's rendering.
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins"
check "dir tier 2 with one sub component does not elide" "$(segt dir 2)" \
  "claude-code-plugins/plugins"

# Outside a repository.
DCC_GIT_ROOT=""
P_CWD="/home/u/projects/thing"
check "non-repo dir tier 0 keeps the parent" "$(segt dir 0)" "~/projects/thing"
check "non-repo dir tier 1 is the leaf" "$(segt dir 1)" "thing"
check "non-repo dir tier 3 is the leaf" "$(segt dir 3)" "thing"

# --- monotonic shrink ---------------------------------------------------------
# The escalation loop terminates only if no tier is wider than its predecessor.
DCC_GIT_ROOT="/home/u/Repos/Personal/claude-code-plugins"
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"
prev=""
for t in 0 1 2 3; do
  now="$(segtcells dir "$t")"
  if [ -n "$prev" ]; then
    ok="no"; [ "$now" -le "$prev" ] && ok="yes"
    check "dir tier $t is no wider than tier $(( t - 1 ))" "$ok" "yes"
  fi
  prev="$now"
done

finish
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-statusline/tests/tiers.test.sh
```

Expected: FAIL. `_dcc_trunc` is undefined so `DCC_TRUNC` is unbound, and every `dir` tier returns the tier-0 string because `dcc_segment` ignores its second argument.

- [ ] **Step 3: Add `_dcc_trunc` to `render.sh`**

Append to `plugins/dcc-statusline/scripts/lib/render.sh`:

```bash
printf -v DCC_ELLIPSIS '\342\200\246'   # U+2026, one cell

_dcc_trunc() { # _dcc_trunc <text> <maxlen> -> DCC_TRUNC
  local s="${1:-}" n="${2:-0}"
  DCC_TRUNC="$s"
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  [ "$n" -gt 0 ] || return 0
  [ "${#s}" -gt "$n" ] || return 0
  DCC_TRUNC="${s:0:$n}$DCC_ELLIPSIS"
}
```

Note the result is `n+1` characters and `n+1` cells — the ellipsis is one cell under `LC_ALL=C.UTF-8`, so `dcc_seg_add`'s default `${#text}` count is correct and no explicit cell count is needed.

- [ ] **Step 4: Add the tier parameter and the `dir` tiers to `segments.sh`**

Change the `dcc_segment` signature line (currently line 52) to capture the tier and the extra locals:

```bash
dcc_segment() { # dcc_segment <name> [tier] -> DCC_SEG_OUT, DCC_SEG_CELLS
  local name="${1:-}" tier="${2:-0}"
  local cwd root home leaf parent ancestry reponame sub eff
```

Replace the `dir` branch body (currently lines 79-102, from the `if [ -n "$root" ]` through the closing `fi`) with:

```bash
      if [ -n "$root" ] && { [ "$cwd" = "$root" ] || [ "${cwd#"$root"/}" != "$cwd" ]; }; then
        # Inside a repository the path is read in three tones: what leads to the
        # repository recedes, the repository name is the anchor, and the
        # position inside it reads plainly. The anchor sits in the same place
        # whatever the depth, and every tier below preserves it -- shrinking may
        # remove context but must never move where the eye lands.
        reponame="${root##*/}"
        ancestry="${root%/*}/"
        [ "$reponame" = "$root" ] && ancestry=""
        sub="${cwd#"$root"}"
        case "$tier" in
          0) : ;;
          1) ancestry="" ;;
          2) ancestry=""
             # Elide only when there is a middle to remove. With zero or one
             # component below the root the elision is longer than the text it
             # would replace, so tier 2 renders as tier 1.
             case "${sub#/}" in
               */*) sub="/$DCC_ELLIPSIS/${sub##*/}" ;;
             esac
             ;;
          *) ancestry=""
             [ -n "$sub" ] && { reponame="${sub##*/}"; sub=""; }
             ;;
        esac
        [ -n "$ancestry" ] && dcc_seg_add "$ancestry" "$DCC_P_DIR" dim
        dcc_seg_add "$reponame" "$DCC_P_DIR" bold
        [ -n "$sub" ] && dcc_seg_add "$sub" "$DCC_P_DIR"
      else
        leaf="${cwd##*/}"
        if [ "$leaf" = "$cwd" ] || [ "$tier" -gt 0 ]; then
          [ -n "$leaf" ] || leaf="$cwd"
          dcc_seg_add "$leaf" "$DCC_P_DIR" bold
        else
          parent="${cwd%/*}/"
          dcc_seg_add "$parent" "$DCC_P_DIR" dim
          dcc_seg_add "$leaf"   "$DCC_P_DIR" bold
        fi
      fi
```

- [ ] **Step 5: Run the new test and the existing suite**

```bash
bash plugins/dcc-statusline/tests/tiers.test.sh
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: `tiers.test.sh` reports `0 failed`. `run-all.sh` reports `0 failed` — in particular `segments.test.sh`, which calls `dcc_segment` with one argument and must be unaffected.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/render.sh \
        plugins/dcc-statusline/scripts/lib/segments.sh \
        plugins/dcc-statusline/tests/tiers.test.sh
git commit -m "feat(statusline): add segment tiers and dir shrinking"
```

---

### Task 3: `git`, `model`, and meter tiers

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/segments.sh:18-49` (`_dcc_meter`), `:104-123` (`git`, `model`), `:174-176` (meter dispatch)
- Modify: `plugins/dcc-statusline/tests/tiers.test.sh` (append)

**Interfaces:**
- Consumes: `_dcc_trunc` / `DCC_TRUNC` and `dcc_segment <name> [tier]` from Task 2.
- Produces: `_dcc_meter <icon> <label> <pct> <width> <reset> <tokens> <tier>` — a seventh positional parameter, defaulting to `0`. Tier scales the bar width and suppresses the suffix.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dcc-statusline/tests/tiers.test.sh`, immediately before the `finish` line:

```bash
# --- git ----------------------------------------------------------------------
DCC_GIT_BRANCH="feature/responsive-tiers"
DCC_GIT_DIRTY=1; DCC_GIT_AHEAD=2; DCC_GIT_BEHIND=0
DCC_GIT_STAGED=3; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=2
DCC_SEG_GIT_MAXBRANCH=0

check "git tier 0 shows every counter" "$(segt git 0)" \
  "feature/responsive-tiers* ↑2 ●3 ?2"
check "git tier 1 shows every counter" "$(segt git 1)" \
  "feature/responsive-tiers* ↑2 ●3 ?2"
check "git tier 2 drops the counters" "$(segt git 2)" "feature/responsive-tiers*"
check "git tier 3 truncates the branch" "$(segt git 3)" "feature/resp…*"

DCC_GIT_BRANCH="main"
check "git tier 3 leaves a short branch alone" "$(segt git 3)" "main*"

# --- model --------------------------------------------------------------------
P_MODEL="Opus 4.8"
check "model tier 0 is the full name" "$(segt model 0)" "Opus 4.8"
check "model tier 2 is the full name" "$(segt model 2)" "Opus 4.8"
check "model tier 3 is the first word" "$(segt model 3)" "Opus"

# --- meters -------------------------------------------------------------------
# Width 10 scales to 6 at tier 1 ((10*60+50)/100) and 4 at tier 2.
P_CTX_PCT=47; P_CTX_TOK=94210
check "ctx tier 0 is a full bar with the token count" "$(segt ctx 0)" \
  "ctx #####..... 47% · 94k"
check "ctx tier 1 narrows the bar, keeping the suffix" "$(segt ctx 1)" \
  "ctx ###... 47% · 94k"
check "ctx tier 2 narrows further and drops the suffix" "$(segt ctx 2)" \
  "ctx ##.. 47%"
check "ctx tier 3 drops the bar entirely" "$(segt ctx 3)" "ctx 47%"

# A meter configured to width 2 scales to a single cell at tier 2 rather than
# rounding its bar away entirely; only tier 3 removes a bar. dcc_bar's existing
# "never look full below 100%" clamp then empties that one cell, which is
# degenerate but honest -- a one-cell bar cannot show both states, and the
# percentage beside it carries the reading regardless.
DCC_W_CTX=2
check "a width-2 meter keeps a bar cell at tier 2" "$(segt ctx 2)" "ctx . 47%"
DCC_W_CTX=10

# --- monotonic shrink, every shrinking segment --------------------------------
DCC_GIT_BRANCH="feature/responsive-tiers"
for nm in git model ctx 5h 7d; do
  prev=""
  for t in 0 1 2 3; do
    now="$(segtcells "$nm" "$t")"
    if [ -n "$prev" ]; then
      ok="no"; [ "$now" -le "$prev" ] && ok="yes"
      check "$nm tier $t is no wider than tier $(( t - 1 ))" "$ok" "yes"
    fi
    prev="$now"
  done
done
```

The `5h` and `7d` cases in that loop need their payload globals set. Add these four lines just above the loop:

```bash
P_5H_PCT=23; P_5H_RESET=1785900000
P_7D_PCT=41; P_7D_RESET=1786400000
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-statusline/tests/tiers.test.sh
```

Expected: FAIL on every `git`, `model` and meter tier assertion — all four tiers currently render identically.

- [ ] **Step 3: Implement the tier branches**

In `plugins/dcc-statusline/scripts/lib/segments.sh`, replace `_dcc_meter` (lines 18-49) with:

```bash
_dcc_meter() { # _dcc_meter <icon> <label> <pct> <width> <reset-epoch> <tokens|""> [tier]
  local icon="$1" label="$2" pct="$3" width="$4" reset="$5" tokens="$6" tier="${7:-0}"
  local suffix=""
  [ -n "$pct" ] || return 0
  # The bar is the first thing to give: it is the least precise reading on the
  # line, and the percentage beside it says the same thing exactly.
  case "$tier" in
    0) : ;;
    1) width=$(( (width * 60 + 50) / 100 )); [ "$width" -lt 1 ] && width=1 ;;
    2) width=$(( (width * 40 + 50) / 100 )); [ "$width" -lt 1 ] && width=1 ;;
    *) width=0 ;;
  esac
  dcc_ramp "$pct"
  dcc_bar "$pct" "$width"
  _dcc_icon "$icon" "$DCC_P_MUTE"
  dcc_seg_add "$label " "$DCC_P_MUTE"
  # With no bar the label's trailing space is the only gap the percentage needs;
  # emitting the bar's own trailing space as well would double it.
  if [ -n "$DCC_BAR_ON$DCC_BAR_OFF" ]; then
    dcc_seg_add "$DCC_BAR_ON"  "$DCC_RAMP_COLOR" ""    "$DCC_BAR_ON_N"
    dcc_seg_add "$DCC_BAR_OFF" "$DCC_P_MUTE"     dim   "$DCC_BAR_OFF_N"
    dcc_seg_add " " "$DCC_P_MUTE"
  fi
  # The percentage is always bold: it is the reading, and the ramp's own bold
  # stop above 90% would otherwise be the only thing that ever emphasised it.
  dcc_seg_add "${pct}%" "$DCC_RAMP_COLOR" bold
  # The suffix is context, not a reading, so it goes before the bar does.
  [ "$tier" -ge 2 ] && return 0
  if [ "$DCC_SHOW_TOKENS" -eq 1 ] && [ -n "$tokens" ]; then
    if [ "$tokens" -ge 1000 ] 2>/dev/null; then
      suffix="$(( tokens / 1000 ))k"
    else
      suffix="$tokens"
    fi
  fi
  # Anything but a run of digits is dropped rather than fed to $(( )). Bash
  # arithmetic on a float, an ISO date, or a bare word does not merely evaluate
  # to zero: it raises a syntax error that aborts the whole render.
  case "$reset" in ''|*[!0-9]*) reset="" ;; esac
  if [ "$DCC_SHOW_ETA" -eq 1 ] && [ -n "$reset" ]; then
    dcc_eta $(( reset - DCC_NOW ))
    [ -n "$DCC_ETA" ] && suffix="$DCC_ETA"
  fi
  if [ -n "$suffix" ]; then
    dcc_seg_add " $DCC_SEP_DOT $suffix" "$DCC_P_MUTE" dim $(( 3 + ${#suffix} ))
  fi
}
```

Replace the `git` branch body (lines 105-117) with:

```bash
      [ -n "$DCC_GIT_BRANCH" ] || return 0
      _dcc_icon "$DCC_I_GIT" "$DCC_P_GIT"
      # Tier 3 truncates to the configured limit, or to 12 when none is set --
      # a branch name is the one payload field with no upper bound, and at the
      # tier of last resort an unbounded field would crowd out every segment
      # beside it.
      br="$DCC_GIT_BRANCH"; lim="${DCC_SEG_GIT_MAXBRANCH:-0}"
      [ "$tier" -ge 3 ] && [ "$lim" -eq 0 ] 2>/dev/null && lim=12
      _dcc_trunc "$br" "$lim"; br="$DCC_TRUNC"
      # The dirty marker and the counts render at normal weight, not dim. Dimmed
      # against a dark background a saturated hue turns muddy and the numbers
      # stop being readable, which defeats the point of showing them. The branch
      # name still leads because it is the only bold piece here.
      dcc_seg_add "$br" "$DCC_P_GIT" bold
      [ "$DCC_GIT_DIRTY" -eq 1 ] && dcc_seg_add "$DCC_GLYPH_DIRTY" "$DCC_P_GIT"
      [ "$tier" -ge 2 ] && return 0
      [ "${DCC_SEG_GIT_COUNTERS:-1}" -eq 1 ] || return 0
      [ "$DCC_GIT_AHEAD"  -gt 0 ] && dcc_seg_add " $DCC_ARROW_UP$DCC_GIT_AHEAD" "$DCC_P_GIT" "" $(( 2 + ${#DCC_GIT_AHEAD} ))
      [ "$DCC_GIT_BEHIND" -gt 0 ] && dcc_seg_add "$DCC_ARROW_DOWN$DCC_GIT_BEHIND" "$DCC_P_GIT" "" $(( 1 + ${#DCC_GIT_BEHIND} ))
      [ "$DCC_GIT_STAGED"    -gt 0 ] && dcc_seg_add " $DCC_DOT_FILLED$DCC_GIT_STAGED" "$DCC_P_GIT" "" $(( 2 + ${#DCC_GIT_STAGED} ))
      [ "$DCC_GIT_UNSTAGED"  -gt 0 ] && dcc_seg_add " $DCC_DOT_HOLLOW$DCC_GIT_UNSTAGED" "$DCC_P_GIT" "" $(( 2 + ${#DCC_GIT_UNSTAGED} ))
      [ "$DCC_GIT_UNTRACKED" -gt 0 ] && dcc_seg_add " ?$DCC_GIT_UNTRACKED" "$DCC_P_GIT"
      ;;
```

The git branch assigns `br` and `lim` without the `local` keyword, so add both to the function's `local` declaration line from Task 2 — a bare assignment inside the branch would otherwise leak into the global namespace and persist across renders:

```bash
  local cwd root home leaf parent ancestry reponame sub eff br lim
```

Replace the `model` branch body (lines 120-122) with:

```bash
      [ -n "$P_MODEL" ] || return 0
      _dcc_icon "$DCC_I_MODEL" "$DCC_P_MODEL"
      if [ "$tier" -ge 3 ] || [ "${DCC_SEG_MODEL_SHORT:-0}" -eq 1 ]; then
        dcc_seg_add "${P_MODEL%% *}" "$DCC_P_MODEL" bold
      else
        dcc_seg_add "$P_MODEL" "$DCC_P_MODEL" bold
      fi
      ;;
```

Replace the meter dispatch lines (174-176) with:

```bash
    ctx) _dcc_meter "$DCC_I_CTX"   "${DCC_L_CTX:-ctx}" "$P_CTX_PCT" "$DCC_W_CTX" "" "$P_CTX_TOK" "$tier" ;;
    5h)  _dcc_meter "$DCC_I_CLOCK" "${DCC_L_5H:-5h}"   "$P_5H_PCT"  "$DCC_W_5H"  "$P_5H_RESET" "" "$tier" ;;
    7d)  _dcc_meter "$DCC_I_CLOCK" "${DCC_L_7D:-7d}"   "$P_7D_PCT"  "$DCC_W_7D"  "$P_7D_RESET" "" "$tier" ;;
```

- [ ] **Step 4: Run the tests**

```bash
bash plugins/dcc-statusline/tests/tiers.test.sh
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: both report `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/segments.sh \
        plugins/dcc-statusline/tests/tiers.test.sh
git commit -m "feat(statusline): shrink git, model and meters by tier"
```

---

### Task 4: The escalation loop

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/render.sh` (add `dcc_line_measure`)
- Modify: `plugins/dcc-statusline/scripts/lib/segments.sh` (add `_dcc_render_line`, `dcc_line_fit`)
- Modify: `plugins/dcc-statusline/scripts/lib/jq-prog.sh` (add `responsive.maxTier`)
- Modify: `plugins/dcc-statusline/scripts/lib/config.sh` (add `DCC_MAX_TIER` default)
- Modify: `plugins/dcc-statusline/scripts/statusline.sh:28-35,94-119`
- Modify: `plugins/dcc-statusline/tests/tiers.test.sh` (append)

**Interfaces:**
- Consumes: `dcc_segment <name> [tier]` and the tier renderings from Tasks 2-3.
- Produces:
  - `dcc_line_measure` → `DCC_LINE_TOTAL`, the cells the pushed segments would occupy including separators, without building the string.
  - `_dcc_render_line <names> <tier> <mark-bad-config>` — fills `DCC_SEGS`/`DCC_SEGW` at the given tier. `mark-bad-config` of `1` appends the red `cfg?` chip when `DCC_CONFIG_BAD` is `1`.
  - `dcc_line_fit <names> <max-cells> <mark-bad-config>` → `DCC_LINE_OUT`, `DCC_LINE_CELLS`, `DCC_LINE_DROPPED`, `DCC_LINE_TIER`. A `max-cells` of `0` means no known width: renders at tier 0 only.
  - `DCC_MAX_TIER` — from `responsive.maxTier`, default `3`, clamped to `0`–`3`.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dcc-statusline/tests/tiers.test.sh`, before `finish`:

```bash
# --- escalation ---------------------------------------------------------------
DCC_SEP="  ·  "; dcc_sep_cells 5
DCC_MAX_TIER=3
DCC_CONFIG_BAD=0
DCC_GIT_BRANCH="main"; DCC_GIT_DIRTY=0
DCC_GIT_AHEAD=0; DCC_GIT_BEHIND=0
DCC_GIT_STAGED=0; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=0
DCC_GIT_ROOT="/home/u/Repos/Personal/claude-code-plugins"
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"
P_MODEL="Opus 4.8"

dcc_line_fit "dir git model" 200 0
check "a wide budget renders at tier 0" "$DCC_LINE_TIER" "0"
check "a wide budget drops nothing" "$DCC_LINE_DROPPED" "0"

dcc_line_fit "dir git model" 60 0
ok="no"; [ "$DCC_LINE_TIER" -gt 0 ] && ok="yes"
check "a tight budget escalates past tier 0" "$ok" "yes"
ok="no"; [ "$DCC_LINE_CELLS" -le 60 ] && ok="yes"
check "the fitted line is within budget" "$ok" "yes"
check "escalation drops no segments" "$DCC_LINE_DROPPED" "0"

# A budget of zero means the width is unknown, not that nothing fits.
dcc_line_fit "dir git model" 0 0
check "an unknown width renders at tier 0" "$DCC_LINE_TIER" "0"
check "an unknown width drops nothing" "$DCC_LINE_DROPPED" "0"

# maxTier 0 pins the render and restores greedy dropping.
DCC_MAX_TIER=0
dcc_line_fit "dir git model" 40 0
check "maxTier 0 never escalates" "$DCC_LINE_TIER" "0"
ok="no"; [ "$DCC_LINE_DROPPED" -gt 0 ] && ok="yes"
check "maxTier 0 falls back to dropping" "$ok" "yes"
DCC_MAX_TIER=3

# Escalation must terminate even when tier 3 still overflows, handing off to the
# greedy drop rather than looping.
DCC_GIT_BRANCH="$(printf 'x%.0s' $(seq 1 300))"
dcc_line_fit "dir git model" 52 0
check "a pathological branch still reaches tier 3" "$DCC_LINE_TIER" "3"
ok="no"; [ "$DCC_LINE_CELLS" -le 52 ] && ok="yes"
check "a pathological branch still fits the budget" "$ok" "yes"
DCC_GIT_BRANCH="main"

# The bad-config marker survives re-rendering.
DCC_CONFIG_BAD=1
dcc_line_fit "dir" 200 1
check "the cfg marker is appended when asked" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi | grep -c 'cfg?')" "1"
dcc_line_fit "dir" 200 0
check "the cfg marker is absent when not asked" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi | grep -c 'cfg?')" "0"
DCC_CONFIG_BAD=0
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-statusline/tests/tiers.test.sh
```

Expected: FAIL with `dcc_line_fit: command not found`.

- [ ] **Step 3: Add `dcc_line_measure` to `render.sh`**

Append to `plugins/dcc-statusline/scripts/lib/render.sh`:

```bash
DCC_LINE_TOTAL=0

dcc_line_measure() { # -> DCC_LINE_TOTAL, the cells the pushed segments need
  # Measures without building, so the escalation loop can reject a tier without
  # paying for its string concatenation.
  local i n=0 c=0
  DCC_LINE_TOTAL=0
  [ "${#DCC_SEGW[@]}" -gt 0 ] || return 0
  for i in "${!DCC_SEGW[@]}"; do
    [ "$c" -gt 0 ] && n=$(( n + DCC_SEP_CELLS ))
    n=$(( n + DCC_SEGW[i] ))
    c=$(( c + 1 ))
  done
  DCC_LINE_TOTAL="$n"
}
```

- [ ] **Step 4: Add the loop to `segments.sh`**

Append to `plugins/dcc-statusline/scripts/lib/segments.sh`:

```bash
DCC_LINE_TIER=0

_dcc_render_line() { # _dcc_render_line <names> <tier> <mark-bad-config>
  local name
  dcc_line_reset
  for name in $1; do
    dcc_segment "$name" "$2"
    dcc_line_push
  done
  if [ "${3:-0}" -eq 1 ] && [ "${DCC_CONFIG_BAD:-0}" -eq 1 ]; then
    dcc_seg_add "cfg?" red bold
    dcc_line_push
  fi
}

dcc_line_fit() { # dcc_line_fit <names> <max-cells> <mark-bad-config>
  # Renders at tier 0 and escalates the whole line one tier at a time until it
  # fits. Uniform escalation is deliberate: a line where the path abbreviated
  # but the branch did not would follow no rule a reader could infer.
  #
  # A max of 0 means the width is unknown -- COLUMNS was missing or unusable,
  # which is also why the frame is off -- so there is nothing to fit against and
  # tier 0 stands.
  local names="$1" max="${2:-0}" mark="${3:-0}" tier top="${DCC_MAX_TIER:-3}"
  case "$top" in ''|*[!0-9]*) top=3 ;; esac
  [ "$top" -gt 3 ] && top=3
  for (( tier = 0; tier <= top; tier++ )); do
    _dcc_render_line "$names" "$tier" "$mark"
    DCC_LINE_TIER="$tier"
    if [ "$max" -le 0 ]; then
      dcc_line_build
      return 0
    fi
    dcc_line_measure
    if [ "$DCC_LINE_TOTAL" -le "$max" ]; then
      dcc_line_build "$max"
      return 0
    fi
  done
  # Tier `top` still overflows. Greedy segment dropping is the last resort, and
  # the only path on which data is actually lost.
  dcc_line_build "$max"
}
```

- [ ] **Step 5: Add the `responsive` config key**

In `plugins/dcc-statusline/scripts/lib/jq-prog.sh`, add to `DCC_DEFAULT_CONFIG` after the `"frameMargin": 4,` line:

```json
  "responsive": { "maxTier": 3 },
```

and add to `DCC_JQ_PROG` after the `DCC_FRAME_MARGIN` line:

```
  @sh "DCC_MAX_TIER=\(num($c.responsive.maxTier; 3))",
```

In `plugins/dcc-statusline/scripts/lib/config.sh`, add beside the other config defaults, next to `DCC_FRAME_MARGIN=4`:

```bash
DCC_MAX_TIER=3
```

- [ ] **Step 6: Wire it into `statusline.sh`**

Delete `_dcc_emit_line` (lines 28-35) — `_dcc_render_line` in `segments.sh` replaces it.

Replace the framed block (lines 94-109) with:

```bash
  if [ "$DCC_FRAME_ON" -eq 1 ]; then
    dcc_frame_top "$P_EMAIL" "$DCC_I_ACCOUNT" "$DCC_ICON_W"
    printf '%s\n' "$DCC_FRAME_OUT"
    dcc_line_fit "$names1" "$DCC_FRAME_BUDGET" 1
    dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
    printf '%s\n' "$DCC_FRAME_OUT"
    dcc_line_fit "$names2" "$DCC_FRAME_BUDGET" 0
    dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
    printf '%s\n' "$DCC_FRAME_OUT"
    dcc_frame_bottom
    printf '%s\n' "$DCC_FRAME_OUT"
    return 0
  fi
```

Replace the unframed block (lines 111-118) with:

```bash
  dcc_line_fit "$names1" 0 1
  [ -n "$DCC_LINE_OUT" ] && printf '%s\n' "$DCC_LINE_OUT"

  dcc_line_fit "$names2" 0 0
  [ -n "$DCC_LINE_OUT" ] && printf '%s\n' "$DCC_LINE_OUT"
```

- [ ] **Step 7: Run the tests**

```bash
bash plugins/dcc-statusline/tests/tiers.test.sh
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: both `0 failed`. `e2e.test.sh` in particular must still pass unchanged — it asserts tier-0 output at `COLUMNS=100`, which is wide enough not to escalate.

- [ ] **Step 8: Commit**

```bash
git add plugins/dcc-statusline/scripts/ plugins/dcc-statusline/tests/tiers.test.sh
git commit -m "feat(statusline): fit lines by escalating segment tiers"
```

---

### Task 5: Frame integrity across widths

The single highest-value test in this plan. Tier escalation changes how many cells a row occupies, and a miscount by one leaves a ragged wall down the whole box. Today only `COLUMNS=100` is covered.

**Files:**
- Modify: `plugins/dcc-statusline/tests/e2e.test.sh` (append before `rm -rf "$fakehome"`)

**Interfaces:**
- Consumes: `dcc_line_fit` from Task 4; `dcc_cells` from `tests/lib.sh`.
- Produces: nothing.

- [ ] **Step 1: Write the test**

Append to `plugins/dcc-statusline/tests/e2e.test.sh`, immediately before the `rm -rf "$fakehome"` line:

```bash
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

# maxTier 0 must reproduce today's behaviour exactly: no escalation, and the
# greedy drop doing the fitting.
cfgt="$(mktemp)"; printf '{ "responsive": { "maxTier": 0 } }' > "$cfgt"
out="$(DCC_STATUSLINE_CONFIG="$cfgt" COLUMNS=60 bash "$SCRIPT" < "$F/full.json")"
rowno=0
while IFS= read -r row; do
  rowno=$(( rowno + 1 ))
  dcc_cells "$row"
  check "maxTier 0 row $rowno still measures 56 cells" "$DCC_CELLS" "56"
done < <(printf '%s\n' "$out")
rm -f "$cfgt"
```

- [ ] **Step 2: Run it**

```bash
bash plugins/dcc-statusline/tests/e2e.test.sh
```

Expected: `0 failed`. If a row is off by one, the culprit is a `dcc_seg_add` call in a tier branch whose text is not ASCII and which did not pass an explicit cell count — check the tier-2 `dir` elision first, since `$DCC_ELLIPSIS` is the only non-ASCII character added by Phase 1.

- [ ] **Step 3: Commit**

```bash
git add plugins/dcc-statusline/tests/e2e.test.sh
git commit -m "test(statusline): assert frame width across seven widths"
```

---

# Phase 2 — Themes

### Task 6: Theme table and merge order

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/jq-prog.sh`
- Modify: `plugins/dcc-statusline/scripts/lib/config.sh:194-236` (`dcc_parse_all`, all four `jq` invocations)
- Create: `plugins/dcc-statusline/tests/theme.test.sh`

**Interfaces:**
- Consumes: `dcc_parse_all <payload> <config-path> <claude-json-path>` (unchanged signature).
- Produces: `DCC_THEMES`, a JSON object mapping theme name to a partial config. Merge order becomes `defaults * theme * userConfig`.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/theme.test.sh`:

```bash
#!/usr/bin/env bash
# Theme resolution. The merge order is defaults * theme * userConfig, so a key
# the user sets always beats the same key set by their theme.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/path.sh"
source "$HERE/../scripts/lib/jq-prog.sh"
source "$HERE/../scripts/lib/config.sh"

export LC_ALL=C.UTF-8
PAYLOAD='{"model":{"display_name":"Opus"}}'

parse_with() { # parse_with <config-json> -- sets the DCC_* globals
  local cfg; cfg="$(mktemp)"
  printf '%s' "$1" > "$cfg"
  dcc_parse_all "$PAYLOAD" "$cfg" /dev/null
  rm -f "$cfg"
}

# No theme key: the defaults stand.
parse_with '{}'
check "no theme leaves the default frame"   "$DCC_FRAME_MODE" "auto"
check "no theme leaves the default dir hue" "$DCC_P_DIR"      "blue"
check "no theme reports a clean config"     "$DCC_CONFIG_BAD" "0"

# An explicit default theme is a no-op.
parse_with '{ "theme": "default" }'
check "the default theme changes nothing" "$DCC_P_DIR" "blue"

# minimal turns the frame off and strips the meters back.
parse_with '{ "theme": "minimal" }'
check "minimal disables the frame"     "$DCC_FRAME_MODE"  "none"
check "minimal drops the ctx bar"      "$DCC_W_CTX"       "0"
check "minimal hides the token count"  "$DCC_SHOW_TOKENS" "0"

# mono removes hue; the three weights carry the hierarchy alone.
parse_with '{ "theme": "mono" }'
check "mono desaturates the path"   "$DCC_P_DIR"   "white"
check "mono desaturates the branch" "$DCC_P_GIT"   "white"
check "mono desaturates the model"  "$DCC_P_MODEL" "white"

# vivid raises contrast.
parse_with '{ "theme": "vivid" }'
check "vivid recolours the path" "$DCC_P_DIR" "cyan"

# The user's own key beats the theme's. This is the whole point of the merge
# order: picking a theme must not make a setting unreachable.
parse_with '{ "theme": "mono", "palette": { "dir": "red" } }'
check "a user key overrides the theme"        "$DCC_P_DIR" "red"
check "the theme still supplies unset keys"   "$DCC_P_GIT" "white"

# A theme the table does not define falls back to default rather than failing.
parse_with '{ "theme": "nonesuch" }'
check "an unknown theme falls back to default" "$DCC_P_DIR"      "blue"
check "an unknown theme is not a parse error"  "$DCC_CONFIG_BAD" "0"

# A theme of the wrong type must not abort the parse.
parse_with '{ "theme": 42 }'
check "a non-string theme falls back to default" "$DCC_P_DIR"      "blue"
check "a non-string theme is not a parse error"  "$DCC_CONFIG_BAD" "0"

finish
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-statusline/tests/theme.test.sh
```

Expected: FAIL on every theme assertion — `theme` is currently an unknown key that the merge ignores.

- [ ] **Step 3: Add the theme table to `jq-prog.sh`**

Append to `plugins/dcc-statusline/scripts/lib/jq-prog.sh`, after `DCC_DEFAULT_CONFIG`:

```bash
# Themes are partial configs merged between the defaults and the user's own
# file, so selecting one never makes a setting unreachable. Kept here rather
# than in separate files because the render path reads them inside the single
# jq call and cannot afford another file open.
DCC_THEMES='{
  "default": {},
  "minimal": {
    "frame": "none",
    "icons": { "mode": "unicode" },
    "lines": [["dir","git","model"],["ctx","cost"]],
    "meters": {
      "width": { "ctx": 0, "5h": 0, "7d": 0 },
      "showEta": false,
      "showTokens": false
    }
  },
  "mono": {
    "palette": {
      "dir": "white", "git": "white", "model": "white",
      "effort": "gray", "fast": "white", "cost": "white", "mute": "gray",
      "effortLevels": {
        "low": "gray", "medium": "gray", "high": "white",
        "xhigh": "white", "max": "white"
      }
    },
    "meters": {
      "ramp": [
        {"at":0,"color":"gray"},
        {"at":75,"color":"white"},
        {"at":90,"color":"white","bold":true}
      ]
    }
  },
  "vivid": {
    "palette": {
      "dir": "cyan", "git": "magenta", "model": "green",
      "effort": "yellow", "fast": "yellow", "cost": "magenta", "mute": "white",
      "effortLevels": {
        "low": "gray", "medium": "cyan", "high": "green",
        "xhigh": "yellow", "max": "magenta"
      }
    },
    "meters": {
      "ramp": [
        {"at":0,"color":"green","bold":true},
        {"at":50,"color":"yellow","bold":true},
        {"at":75,"color":"orange","bold":true},
        {"at":90,"color":"red","bold":true}
      ]
    }
  }
}'
```

- [ ] **Step 4: Change the merge line in `DCC_JQ_PROG`**

Replace the second line of `DCC_JQ_PROG`:

```
| (if ($cfg|length) > 0 then ($d * $cfg[0]) else $d end) as $c
```

with:

```
| (if ($cfg|length) > 0 then $cfg[0] else {} end) as $u
| (if ($u.theme|type) == "string" then ($themes[$u.theme] // {}) else {} end) as $t
| ($d * $t * $u) as $c
```

`jq`'s `*` merges objects recursively and replaces arrays wholesale, which is what both `lines` and `ramp` need. The `type` guard keeps a non-string `theme` from indexing `$themes` with an invalid key, which would abort the parse and cost the whole status line rather than one key.

- [ ] **Step 5: Pass `$themes` to all four `jq` calls**

In `plugins/dcc-statusline/scripts/lib/config.sh`, every `jq` invocation inside `dcc_parse_all` (four of them, at roughly lines 201, 211, 222, and 232) gains one argument. Add `--argjson themes "$DCC_THEMES"` immediately after each `--argjson d "$DCC_DEFAULT_CONFIG"`. For example the first becomes:

```bash
  if out=$(jq -r --argjson d "$DCC_DEFAULT_CONFIG" --argjson themes "$DCC_THEMES" \
                 --arg acct "${DCC_ACCT_KEY:-}" \
                 --slurpfile cfg "$cfg" --slurpfile who "$who" \
                 "$DCC_JQ_PROG" <<<"$input" 2>/dev/null); then
```

Apply the identical change to the other three. Missing one produces a `$themes is not defined` error that the fallback chain silently swallows, so the symptom is a theme that works until the config is malformed.

- [ ] **Step 6: Run the tests**

```bash
bash plugins/dcc-statusline/tests/theme.test.sh
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: both `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/jq-prog.sh \
        plugins/dcc-statusline/scripts/lib/config.sh \
        plugins/dcc-statusline/tests/theme.test.sh
git commit -m "feat(statusline): add named themes"
```

---

# Phase 3 — Segment options

### Task 7: The `segments` object

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/jq-prog.sh`
- Modify: `plugins/dcc-statusline/scripts/lib/config.sh` (defaults for the new globals)
- Modify: `plugins/dcc-statusline/scripts/lib/segments.sh` (`dir` honours `DCC_SEG_DIR_STYLE`)
- Modify: `plugins/dcc-statusline/tests/tiers.test.sh` (append)

**Interfaces:**
- Consumes: the tier branches from Tasks 2-3, which already read `DCC_SEG_GIT_COUNTERS`, `DCC_SEG_GIT_MAXBRANCH`, `DCC_SEG_MODEL_SHORT`, `DCC_L_CTX`, `DCC_L_5H`, `DCC_L_7D` with `${...:-default}` fallbacks.
- Produces: those six globals plus `DCC_SEG_DIR_STYLE`, all populated from the config.

| Global | Config key | Type | Default |
|--------|-----------|------|---------|
| `DCC_SEG_DIR_STYLE` | `segments.dir.style` | `""` \| `full` \| `repo` \| `leaf` | `""` |
| `DCC_SEG_GIT_COUNTERS` | `segments.git.counters` | `0`/`1` | `1` |
| `DCC_SEG_GIT_MAXBRANCH` | `segments.git.maxBranch` | int | `0` |
| `DCC_SEG_MODEL_SHORT` | `segments.model.short` | `0`/`1` | `0` |
| `DCC_L_CTX` | `segments.ctx.label` | string | `ctx` |
| `DCC_L_5H` | `segments.5h.label` | string | `5h` |
| `DCC_L_7D` | `segments.7d.label` | string | `7d` |

- [ ] **Step 1: Write the failing test**

Append to `plugins/dcc-statusline/tests/tiers.test.sh`, before `finish`:

```bash
# --- segment options ----------------------------------------------------------
DCC_GIT_BRANCH="feature/responsive-tiers"
DCC_GIT_DIRTY=1; DCC_GIT_AHEAD=2; DCC_GIT_BEHIND=0
DCC_GIT_STAGED=3; DCC_GIT_UNSTAGED=0; DCC_GIT_UNTRACKED=2
DCC_SEG_GIT_MAXBRANCH=0

DCC_SEG_GIT_COUNTERS=0
check "counters off hides the counts" "$(segt git 0)" "feature/responsive-tiers*"
DCC_SEG_GIT_COUNTERS=1

DCC_SEG_GIT_MAXBRANCH=8
check "maxBranch truncates at tier 0" "$(segt git 0)" "feature/…* ↑2 ●3 ?2"
DCC_SEG_GIT_MAXBRANCH=0

DCC_SEG_MODEL_SHORT=1
check "model short applies at tier 0" "$(segt model 0)" "Opus"
DCC_SEG_MODEL_SHORT=0

DCC_L_CTX="context"
check "a custom meter label is used" "$(segt ctx 0)" "context #####..... 47% · 94k"
DCC_L_CTX="ctx"

# dir.style pins the rendering below the line's tier, but never above it: a
# pin is a floor on compactness, not a veto on fitting.
DCC_GIT_ROOT="/home/u/Repos/Personal/claude-code-plugins"
P_CWD="/home/u/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"
DCC_SEG_DIR_STYLE="repo"
check "dir.style repo pins tier 0 to tier 1" "$(segt dir 0)" \
  "claude-code-plugins/plugins/dcc-statusline"
check "dir.style repo does not block tier 3" "$(segt dir 3)" "dcc-statusline"
DCC_SEG_DIR_STYLE="leaf"
check "dir.style leaf pins tier 0 to tier 3" "$(segt dir 0)" "dcc-statusline"
DCC_SEG_DIR_STYLE=""
check "no dir.style restores tier 0" "$(segt dir 0)" \
  "~/Repos/Personal/claude-code-plugins/plugins/dcc-statusline"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-statusline/tests/tiers.test.sh
```

Expected: FAIL on the `dir.style` assertions (the segment ignores the variable) and on `DCC_L_CTX` if it was never set. The `counters`, `maxBranch` and `short` assertions already pass — Tasks 2-3 read those globals — which is intended; this task's work is wiring them to the config.

- [ ] **Step 3: Honour `DCC_SEG_DIR_STYLE` in `segments.sh`**

In the `dir` branch, immediately after the `dcc_path_norm` / `$HOME` abbreviation block and before `_dcc_icon "$DCC_I_DIR"`, insert:

```bash
      # A pinned style raises the effective tier but never lowers it. Pinning is
      # a floor on how compact the path may be, not a veto on the line fitting.
      case "${DCC_SEG_DIR_STYLE:-}" in
        repo) [ "$tier" -lt 1 ] && tier=1 ;;
        leaf) [ "$tier" -lt 3 ] && tier=3 ;;
      esac
```

`tier` is already a `local` of `dcc_segment`, so reassigning it is scoped to this call.

- [ ] **Step 4: Add the config plumbing**

In `plugins/dcc-statusline/scripts/lib/jq-prog.sh`, add to `DCC_DEFAULT_CONFIG` after the `"accounts": {},` line:

```json
  "segments": {
    "dir": { "style": "" },
    "git": { "counters": true, "maxBranch": 0 },
    "model": { "short": false },
    "ctx": { "label": "ctx" },
    "5h": { "label": "5h" },
    "7d": { "label": "7d" }
  },
```

and add to `DCC_JQ_PROG` after the `DCC_MAX_TIER` line:

```
  @sh "DCC_SEG_DIR_STYLE=\(str($c.segments.dir.style))",
  @sh "DCC_SEG_GIT_COUNTERS=\(if $c.segments.git.counters == false then 0 else 1 end)",
  @sh "DCC_SEG_GIT_MAXBRANCH=\(num($c.segments.git.maxBranch; 0))",
  @sh "DCC_SEG_MODEL_SHORT=\(if $c.segments.model.short == true then 1 else 0 end)",
  @sh "DCC_L_CTX=\(if ($c.segments.ctx.label|type) == "string" and ($c.segments.ctx.label|length) > 0 then $c.segments.ctx.label else "ctx" end)",
  @sh "DCC_L_5H=\(if ($c.segments["5h"].label|type) == "string" and ($c.segments["5h"].label|length) > 0 then $c.segments["5h"].label else "5h" end)",
  @sh "DCC_L_7D=\(if ($c.segments["7d"].label|type) == "string" and ($c.segments["7d"].label|length) > 0 then $c.segments["7d"].label else "7d" end)",
```

In `plugins/dcc-statusline/scripts/lib/config.sh`, add beside `DCC_MAX_TIER=3`:

```bash
DCC_SEG_DIR_STYLE=""
DCC_SEG_GIT_COUNTERS=1
DCC_SEG_GIT_MAXBRANCH=0
DCC_SEG_MODEL_SHORT=0
DCC_L_CTX="ctx"
DCC_L_5H="5h"
DCC_L_7D="7d"
```

- [ ] **Step 5: Run the tests**

```bash
bash plugins/dcc-statusline/tests/tiers.test.sh
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: both `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-statusline/scripts/ plugins/dcc-statusline/tests/tiers.test.sh
git commit -m "feat(statusline): add per-segment options"
```

---

### Task 8: Per-line separators and the `time` segment

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/jq-prog.sh`
- Modify: `plugins/dcc-statusline/scripts/lib/config.sh`
- Modify: `plugins/dcc-statusline/scripts/lib/segments.sh` (the `time` branch)
- Modify: `plugins/dcc-statusline/scripts/statusline.sh:66` (per-line separator selection)
- Modify: `plugins/dcc-statusline/tests/tiers.test.sh`, `plugins/dcc-statusline/tests/e2e.test.sh`

**Interfaces:**
- Consumes: `dcc_line_fit` from Task 4, `dcc_sep_cells` from `render.sh`.
- Produces: `DCC_SEP1` and `DCC_SEP2`. `DCC_SEP` remains the active separator, assigned per line by `dcc_main` before each `dcc_line_fit` call. A `separator` string sets both; an array sets them positionally, reusing its last element when shorter than the line count and falling back to the default when empty.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dcc-statusline/tests/tiers.test.sh`, before `finish`:

```bash
# --- the time segment ---------------------------------------------------------
# DCC_NOW is the frozen clock the meters already use, so the rendering is
# deterministic. 1785886800 mod 86400 is 85200 seconds, which is 23:40 UTC --
# TZ is pinned because %(%H:%M)T renders in local time.
DCC_NOW=1785886800
export TZ=UTC
check "time renders hours and minutes" "$(segt time 0)" "23:40"
check "time does not shrink" "$(segt time 3)" "23:40"
```

And append to `plugins/dcc-statusline/tests/e2e.test.sh`, before the `rm -rf "$fakehome"` line:

```bash
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
bash plugins/dcc-statusline/tests/tiers.test.sh
bash plugins/dcc-statusline/tests/e2e.test.sh
```

Expected: `time` renders empty (unknown segment names fall through the `case` and produce nothing), and all three separator assertions fail because an array `separator` currently reaches `@sh` as a JSON array rendered into one quoted string.

- [ ] **Step 3: Add the `time` segment**

In `plugins/dcc-statusline/scripts/lib/segments.sh`, add a branch to the `case` in `dcc_segment`, beside `agent` and `style`:

```bash
    time)
      # %(...)T is a bash builtin, so this costs no fork -- the same mechanism
      # statusline.sh uses for DCC_NOW. Reading DCC_NOW rather than -1 keeps a
      # frozen test clock deterministic.
      printf -v tnow '%(%H:%M)T' "${DCC_NOW:--1}"
      dcc_seg_add "$tnow" "$DCC_P_MUTE"
      ;;
```

Add `tnow` to the `local` declaration line:

```bash
  local cwd root home leaf parent ancestry reponame sub eff br lim tnow
```

- [ ] **Step 4: Add per-line separators**

In `plugins/dcc-statusline/scripts/lib/jq-prog.sh`, replace the `DCC_SEP` line in `DCC_JQ_PROG`:

```
  @sh "DCC_SEP=\($c.separator)",
```

with:

```
  @sh "DCC_SEP1=\(if ($c.separator|type) == "array"
                  then ($c.separator[0] // "  ·  ")
                  else $c.separator end)",
  @sh "DCC_SEP2=\(if ($c.separator|type) == "array"
                  then ($c.separator[1] // $c.separator[0] // "  ·  ")
                  else $c.separator end)",
```

In `plugins/dcc-statusline/scripts/lib/config.sh`, replace the `printf -v DCC_SEP` default with three lines:

```bash
printf -v DCC_SEP  '  \302\267  '   # U+00B7 middle dot
printf -v DCC_SEP1 '  \302\267  '
printf -v DCC_SEP2 '  \302\267  '
```

In `plugins/dcc-statusline/scripts/statusline.sh`, delete the `dcc_sep_cells "${#DCC_SEP}"` call (line 66) — the separator is now chosen per line — and set it immediately before each `dcc_line_fit` call. In the framed block:

```bash
    DCC_SEP="$DCC_SEP1"; dcc_sep_cells "${#DCC_SEP1}"
    dcc_line_fit "$names1" "$DCC_FRAME_BUDGET" 1
    dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
    printf '%s\n' "$DCC_FRAME_OUT"
    DCC_SEP="$DCC_SEP2"; dcc_sep_cells "${#DCC_SEP2}"
    dcc_line_fit "$names2" "$DCC_FRAME_BUDGET" 0
```

and the matching pair in the unframed block:

```bash
  DCC_SEP="$DCC_SEP1"; dcc_sep_cells "${#DCC_SEP1}"
  dcc_line_fit "$names1" 0 1
  [ -n "$DCC_LINE_OUT" ] && printf '%s\n' "$DCC_LINE_OUT"

  DCC_SEP="$DCC_SEP2"; dcc_sep_cells "${#DCC_SEP2}"
  dcc_line_fit "$names2" 0 0
  [ -n "$DCC_LINE_OUT" ] && printf '%s\n' "$DCC_LINE_OUT"
```

- [ ] **Step 5: Add `time` to the documented segment list**

In `plugins/dcc-statusline/tests/segments.test.sh:180`, add `time` to the name list so the "every segment tolerates absent data" loop covers it:

```bash
for name in dir git model effort fast time agent style account ctx cost 5h 7d; do
```

- [ ] **Step 6: Run the tests**

```bash
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-statusline/scripts/ plugins/dcc-statusline/tests/
git commit -m "feat(statusline): per-line separators and time segment"
```

---

# Phase 4 — Configuration surface

### Task 9: `validate.sh` and the budget boundary

**Files:**
- Create: `plugins/dcc-statusline/scripts/lib/validate.sh`
- Create: `plugins/dcc-statusline/tests/validate.test.sh`

**Interfaces:**
- Consumes: `jq` on `PATH`. Forks freely — this file is never on the render path.
- Produces: `dcc_validate <config-path>` — prints one line per finding to stdout in the `ok   - ` / `warn - ` / `FAIL - ` format `install.sh doctor` already uses. Returns `0` when no `FAIL` line was printed, `1` otherwise. A nonexistent path is `ok` (defaults apply).

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/validate.test.sh`:

```bash
#!/usr/bin/env bash
# Config diagnostics, plus the assertion that keeps them off the render path.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/validate.sh"

export LC_ALL=C.UTF-8

vout() { # vout <config-json> -> the findings
  local cfg; cfg="$(mktemp)"
  printf '%s' "$1" > "$cfg"
  dcc_validate "$cfg"
  rm -f "$cfg"
}

check "a valid config reports no failures" \
  "$(vout '{ "theme": "mono" }' | grep -c '^FAIL')" "0"
check "a missing file is not a failure" \
  "$(dcc_validate /nonexistent/dcc.json | grep -c '^FAIL')" "0"
check "malformed JSON is a failure" \
  "$(vout '{ not json' | grep -c '^FAIL')" "1"

check "an unknown top-level key is named" \
  "$(vout '{ "colour": "blue" }' | grep -c 'colour')" "1"
check "an unknown theme is named" \
  "$(vout '{ "theme": "nonesuch" }' | grep -c 'nonesuch')" "1"
check "an unknown segment name is named" \
  "$(vout '{ "lines": [["dir","bogus"],[]] }' | grep -c 'bogus')" "1"
check "an invalid colour is named" \
  "$(vout '{ "palette": { "dir": "puce" } }' | grep -c 'puce')" "1"
check "a 256-colour number is accepted" \
  "$(vout '{ "palette": { "dir": "141" } }' | grep -c '^FAIL')" "0"
check "an out-of-range colour number is rejected" \
  "$(vout '{ "palette": { "dir": "999" } }' | grep -c '999')" "1"
check "a wrong-typed frameMargin is named" \
  "$(vout '{ "frameMargin": "wide" }' | grep -c 'frameMargin')" "1"
check "an out-of-range maxTier is named" \
  "$(vout '{ "responsive": { "maxTier": 9 } }' | grep -c 'maxTier')" "1"
check "the \$schema key is not reported as unknown" \
  "$(vout '{ "$schema": "./dcc-statusline.schema.json" }' | grep -c 'schema')" "0"

# The budget boundary. validate.sh forks freely; the render path budgets five
# processes. A source line here would blow that budget on every keystroke, and
# the cost would not show up in any rendering assertion.
check "statusline.sh does not source validate.sh" \
  "$(grep -c 'validate\.sh' "$HERE/../scripts/statusline.sh")" "0"
check "no render-path lib sources validate.sh" \
  "$(grep -l 'validate\.sh' "$HERE"/../scripts/lib/*.sh | grep -vc 'validate\.sh')" "0"

finish
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-statusline/tests/validate.test.sh
```

Expected: FAIL — `validate.sh` does not exist, so the `source` line aborts the file.

- [ ] **Step 3: Write `validate.sh`**

Create `plugins/dcc-statusline/scripts/lib/validate.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
# Config diagnostics. NEVER sourced by statusline.sh -- this file forks freely,
# and the render path budgets five processes. tests/validate.test.sh asserts the
# boundary, because a stray source line would cost forks on every keystroke
# without failing any rendering assertion.

DCC_VALID_SEGMENTS="dir git model effort fast agent style account ctx cost 5h 7d time"
DCC_VALID_COLORS="black red green yellow blue magenta cyan white orange gray"
DCC_VALID_THEMES="default minimal mono vivid"
DCC_VALID_TOPKEYS="\$schema lines separator frame frameMargin responsive icons palette meters accounts glyphs segments theme"

_dcc_v_in() { # _dcc_v_in <needle> <space-separated haystack>
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

_dcc_v_color() { # _dcc_v_color <label> <value> -> prints a FAIL line if invalid
  local label="$1" v="$2"
  [ -n "$v" ] || return 0
  if _dcc_v_in "$v" "$DCC_VALID_COLORS"; then return 0; fi
  # A bare number is a 256-colour index; anything outside 0-255 is not.
  case "$v" in
    ''|*[!0-9]*) printf 'FAIL - %s: "%s" is not a colour name or a 0-255 number\n' "$label" "$v"; return 1 ;;
  esac
  if [ "$v" -gt 255 ]; then
    printf 'FAIL - %s: "%s" is outside the 0-255 colour range\n' "$label" "$v"
    return 1
  fi
  return 0
}

dcc_validate() { # dcc_validate <config-path> -> findings on stdout, rc 1 on any FAIL
  local cfg="${1:-}" rc=0 k v n

  if [ ! -f "$cfg" ]; then
    printf 'ok   - no config file; built-in defaults apply\n'
    return 0
  fi
  if ! jq -e . "$cfg" >/dev/null 2>&1; then
    printf 'FAIL - config is not valid JSON\n'
    return 1
  fi

  while IFS= read -r k; do
    [ -n "$k" ] || continue
    _dcc_v_in "$k" "$DCC_VALID_TOPKEYS" && continue
    printf 'warn - unknown key "%s" is ignored\n' "$k"
  done < <(jq -r 'keys[]' "$cfg" 2>/dev/null)

  v="$(jq -r '.theme // empty' "$cfg" 2>/dev/null)"
  if [ -n "$v" ] && ! _dcc_v_in "$v" "$DCC_VALID_THEMES"; then
    printf 'FAIL - theme: "%s" is unknown; valid themes are %s\n' "$v" "$DCC_VALID_THEMES"
    rc=1
  fi

  while IFS= read -r v; do
    [ -n "$v" ] || continue
    _dcc_v_in "$v" "$DCC_VALID_SEGMENTS" && continue
    printf 'FAIL - lines: "%s" is not a segment name; valid names are %s\n' "$v" "$DCC_VALID_SEGMENTS"
    rc=1
  done < <(jq -r '(.lines // []) | flatten | .[]' "$cfg" 2>/dev/null)

  while IFS= read -r k; do
    [ -n "$k" ] || continue
    v="${k#*=}"; k="${k%%=*}"
    _dcc_v_color "palette.$k" "$v" || rc=1
  done < <(jq -r '(.palette // {}) | to_entries[] | select(.value|type == "string") | "\(.key)=\(.value)"' "$cfg" 2>/dev/null)

  while IFS= read -r k; do
    [ -n "$k" ] || continue
    v="${k#*=}"; k="${k%%=*}"
    _dcc_v_color "palette.effortLevels.$k" "$v" || rc=1
  done < <(jq -r '(.palette.effortLevels // {}) | to_entries[] | "\(.key)=\(.value)"' "$cfg" 2>/dev/null)

  n="$(jq -r 'if has("frameMargin") and (.frameMargin|type) != "number" then "bad" else "" end' "$cfg" 2>/dev/null)"
  if [ "$n" = "bad" ]; then
    printf 'FAIL - frameMargin: must be a number of cells, e.g. 4\n'
    rc=1
  fi

  n="$(jq -r '.responsive.maxTier // empty' "$cfg" 2>/dev/null)"
  if [ -n "$n" ]; then
    case "$n" in
      0|1|2|3) : ;;
      *) printf 'FAIL - responsive.maxTier: "%s" is outside 0-3\n' "$n"; rc=1 ;;
    esac
  fi

  [ "$rc" -eq 0 ] && printf 'ok   - config validates\n'
  return "$rc"
}
```

- [ ] **Step 4: Run the test**

```bash
bash plugins/dcc-statusline/tests/validate.test.sh
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: both `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/validate.sh \
        plugins/dcc-statusline/tests/validate.test.sh
git commit -m "feat(statusline): add config validation off render path"
```

---

### Task 10: `preview.sh`

**Files:**
- Create: `plugins/dcc-statusline/scripts/preview.sh`
- Create: `plugins/dcc-statusline/tests/preview.test.sh`

**Interfaces:**
- Consumes: `scripts/statusline.sh` invoked as a subprocess with `COLUMNS` set per block.
- Produces: an executable script accepting `--width N`, `--theme NAME`, `--config PATH`, `--help`. Exit `0` on success, `2` on an unknown flag.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/preview.test.sh`:

```bash
#!/usr/bin/env bash
# The preview renders the real config at several widths. It is not on the render
# path, so it may fork freely.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
PREVIEW="$HERE/../scripts/preview.sh"

export LC_ALL=C.UTF-8
export DCC_NOW=1785886800

out="$(bash "$PREVIEW" --config /dev/null 2>&1)"
check "the default preview shows five widths" \
  "$(printf '%s\n' "$out" | grep -c '^── COLUMNS ')" "5"
check "the preview reports the tier each line chose" \
  "$(printf '%s\n' "$out" | grep -c 'tier ')" "5"
check "the preview renders the probe model" \
  "$(printf '%s' "$out" | strip_ansi | grep -c 'Opus')" "1"

out="$(bash "$PREVIEW" --config /dev/null --width 100 2>&1)"
check "--width renders exactly one block" \
  "$(printf '%s\n' "$out" | grep -c '^── COLUMNS ')" "1"
check "--width names the width it was given" \
  "$(printf '%s\n' "$out" | grep -c '^── COLUMNS 100')" "1"

out="$(bash "$PREVIEW" --config /dev/null --theme minimal --width 100 2>&1)"
check "--theme minimal drops the frame" \
  "$(printf '%s' "$out" | grep -c '╭')" "0"

bash "$PREVIEW" --config /dev/null --nonsense >/dev/null 2>&1; rc=$?
check "an unknown flag exits 2" "$rc" "2"

bash "$PREVIEW" --help >/dev/null 2>&1; rc=$?
check "--help exits 0" "$rc" "0"

finish
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-statusline/tests/preview.test.sh
```

Expected: FAIL — `preview.sh` does not exist.

- [ ] **Step 3: Write `preview.sh`**

Create `plugins/dcc-statusline/scripts/preview.sh`:

```bash
#!/usr/bin/env bash
# Renders the real config at several widths so the responsive tiers can be seen
# before they are trusted.
#
# A separate script rather than a flag on statusline.sh: statusline.sh reads a
# payload on stdin and must stay free of argument parsing on the render path.
# This file is not on that path and forks freely.
set -uo pipefail

DCC_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DCC_WIDTHS="48 60 80 120 200"
DCC_CFG=""
DCC_THEME=""

_dcc_usage() {
  cat <<'TXT'
usage: preview.sh [--width N] [--theme NAME] [--config PATH]

  --width N      render one width only, instead of 48 60 80 120 200
  --theme NAME   render with this theme, without editing the config
  --config PATH  render this config file instead of the installed one
TXT
}

while [ $# -gt 0 ]; do
  case "$1" in
    --width)  DCC_WIDTHS="${2:-}"; shift 2 ;;
    --theme)  DCC_THEME="${2:-}";  shift 2 ;;
    --config) DCC_CFG="${2:-}";    shift 2 ;;
    --help|-h) _dcc_usage; exit 0 ;;
    *) printf 'preview.sh: unknown option %s\n' "$1" >&2; _dcc_usage >&2; exit 2 ;;
  esac
done

[ -n "$DCC_CFG" ] || DCC_CFG="${DCC_STATUSLINE_CONFIG:-$HOME/.claude/dcc-statusline.json}"
[ -f "$DCC_CFG" ] || DCC_CFG=/dev/null

# A theme override is applied by merging it over the chosen config into a temp
# file, so the user's own file is never touched.
if [ -n "$DCC_THEME" ]; then
  tmp="$(mktemp)"
  jq --arg t "$DCC_THEME" '. + {theme: $t}' "$DCC_CFG" > "$tmp" 2>/dev/null
  # Tested with -s rather than on jq's exit status: jq run against /dev/null (or
  # any empty file) reads no JSON value, writes nothing, and still exits 0, so an
  # exit-status check would leave an empty config here and silently lose the theme.
  [ -s "$tmp" ] || printf '{"theme":"%s"}' "$DCC_THEME" > "$tmp"
  DCC_CFG="$tmp"
fi

# A representative session: inside a repository, mid-context, with both rate
# limit windows populated. Frozen relative to DCC_NOW so the countdowns are
# stable across runs.
now="${DCC_NOW:-$(date +%s)}"
payload="$(cat <<JSON
{
  "workspace": { "current_dir": "$PWD" },
  "model": { "display_name": "Opus 4.8" },
  "effort": { "level": "xhigh" },
  "cost": { "total_cost_usd": 1.2 },
  "context_window": { "used_percentage": 47, "total_input_tokens": 94210 },
  "rate_limits": {
    "five_hour":  { "used_percentage": 23, "resets_at": $(( now + 13200 )) },
    "seven_day":  { "used_percentage": 41, "resets_at": $(( now + 500000 )) }
  }
}
JSON
)"

for w in $DCC_WIDTHS; do
  case "$w" in ''|*[!0-9]*) printf 'preview.sh: "%s" is not a width\n' "$w" >&2; exit 2 ;; esac
  # DCC_PREVIEW_TIERS makes statusline.sh report the tier each line settled on.
  tiers="$(printf '%s' "$payload" \
    | COLUMNS="$w" DCC_STATUSLINE_CONFIG="$DCC_CFG" DCC_NOW="$now" \
      DCC_PREVIEW_TIERS=1 bash "$DCC_SRC_DIR/statusline.sh" 2>/dev/null \
    | sed -n 's/^DCC_TIERS //p')"
  printf '\n── COLUMNS %s ── tier %s ──\n' "$w" "${tiers:-0/0}"
  printf '%s' "$payload" \
    | COLUMNS="$w" DCC_STATUSLINE_CONFIG="$DCC_CFG" DCC_NOW="$now" \
      bash "$DCC_SRC_DIR/statusline.sh" 2>/dev/null
done
printf '\n'

[ -n "$DCC_THEME" ] && rm -f "$DCC_CFG"
exit 0
```

- [ ] **Step 4: Emit the tier report from `statusline.sh`**

`preview.sh` reads a `DCC_TIERS` line that `statusline.sh` only prints when asked. In `plugins/dcc-statusline/scripts/statusline.sh`, add immediately before each of the two `return 0` points of `dcc_main` (the end of the framed block and the end of the unframed block):

```bash
  [ -n "${DCC_PREVIEW_TIERS:-}" ] && printf 'DCC_TIERS %s/%s\n' "$DCC_TIER1" "$DCC_LINE_TIER"
```

and capture line one's tier immediately after its `dcc_line_fit` call in both blocks:

```bash
    DCC_TIER1="$DCC_LINE_TIER"
```

Declare it beside the other locals at the top of `dcc_main`:

```bash
  local names1 names2 DCC_TIER1=0
```

This costs one `[ -n ... ]` test per render when the variable is unset, and no fork.

- [ ] **Step 5: Run the tests**

```bash
bash plugins/dcc-statusline/tests/preview.test.sh
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: both `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-statusline/scripts/preview.sh \
        plugins/dcc-statusline/scripts/statusline.sh \
        plugins/dcc-statusline/tests/preview.test.sh
git commit -m "feat(statusline): add multi-width preview"
```

---

### Task 11: JSON Schema and `doctor` integration

**Files:**
- Create: `plugins/dcc-statusline/dcc-statusline.schema.json`
- Modify: `plugins/dcc-statusline/scripts/install.sh:73-85` (`dcc_seed_config`), `:124-132` (`dcc_doctor`)
- Modify: `plugins/dcc-statusline/tests/install.test.sh` (append)

**Interfaces:**
- Consumes: `dcc_validate` from Task 9.
- Produces: a schema file, and a `dcc_seed_config` that writes `"$schema"` into a newly created config.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dcc-statusline/tests/install.test.sh`, immediately before its `finish` line:

```bash
# --- schema and validation ----------------------------------------------------
SCHEMA="$HERE/../dcc-statusline.schema.json"
check "the schema file exists" "$([ -f "$SCHEMA" ] && echo yes || echo no)" "yes"
check "the schema is valid JSON" \
  "$(jq -e . "$SCHEMA" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "the schema declares every top-level key" \
  "$(jq -r '.properties | keys | length' "$SCHEMA")" "13"

# A seeded config points at the schema so editors validate while typing.
seedhome="$(mktemp -d)"
mkdir -p "$seedhome/.claude"
DCC_FAKE_HOME="$seedhome" dcc_seed_config
check "a seeded config declares \$schema" \
  "$(jq -r '."$schema" // empty' "$seedhome/.claude/dcc-statusline.json" | grep -c 'dcc-statusline.schema.json')" "1"
check "a seeded config still has an accounts map" \
  "$(jq -r '.accounts | type' "$seedhome/.claude/dcc-statusline.json")" "object"
check "a seeded config validates" \
  "$(dcc_validate "$seedhome/.claude/dcc-statusline.json" | grep -c '^FAIL')" "0"
rm -rf "$seedhome"

# doctor names the offending key rather than only reporting that parsing failed.
dochome="$(mktemp -d)"
mkdir -p "$dochome/.claude"
printf '{ "theme": "nonesuch" }' > "$dochome/.claude/dcc-statusline.json"
out="$(DCC_FAKE_HOME="$dochome" dcc_doctor 2>&1)"
check "doctor names an unknown theme" "$(printf '%s' "$out" | grep -c 'nonesuch')" "1"
rm -rf "$dochome"
```

`install.test.sh` sources `install.sh`, which after this task sources `validate.sh`, so `dcc_validate` is in scope.

- [ ] **Step 2: Run it to verify it fails**

```bash
bash plugins/dcc-statusline/tests/install.test.sh
```

Expected: FAIL — the schema file does not exist and `dcc_seed_config` writes no `$schema`.

- [ ] **Step 3: Write the schema**

Create `plugins/dcc-statusline/dcc-statusline.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/darkraise/claude-code-plugins/plugins/dcc-statusline/dcc-statusline.schema.json",
  "title": "dcc-statusline configuration",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "$schema": { "type": "string" },
    "theme": {
      "description": "A named preset, merged between the defaults and this file.",
      "enum": ["default", "minimal", "mono", "vivid"]
    },
    "lines": {
      "description": "Two arrays of segment names, in render order.",
      "type": "array",
      "maxItems": 2,
      "items": {
        "type": "array",
        "items": {
          "enum": ["dir", "git", "model", "effort", "fast", "agent", "style",
                   "account", "ctx", "cost", "5h", "7d", "time"]
        }
      }
    },
    "separator": {
      "description": "A string used on both lines, or an array of one per line.",
      "oneOf": [
        { "type": "string" },
        { "type": "array", "items": { "type": "string" }, "maxItems": 2 }
      ]
    },
    "frame": { "enum": ["auto", "box", "none"] },
    "frameMargin": {
      "description": "Cells to hold the box back from the reported terminal width.",
      "type": "integer",
      "minimum": 0
    },
    "responsive": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "maxTier": {
          "description": "0 disables shrinking; 3 allows the most compact rendering.",
          "type": "integer",
          "minimum": 0,
          "maximum": 3
        }
      }
    },
    "icons": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "mode": { "enum": ["auto", "nerd", "unicode"] },
        "width": { "type": "integer", "minimum": 0, "maximum": 2 }
      }
    },
    "palette": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "dir":    { "$ref": "#/$defs/color" },
        "git":    { "$ref": "#/$defs/color" },
        "model":  { "$ref": "#/$defs/color" },
        "effort": { "$ref": "#/$defs/color" },
        "fast":   { "$ref": "#/$defs/color" },
        "cost":   { "$ref": "#/$defs/color" },
        "mute":   { "$ref": "#/$defs/color" },
        "effortLevels": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "low":    { "$ref": "#/$defs/color" },
            "medium": { "$ref": "#/$defs/color" },
            "high":   { "$ref": "#/$defs/color" },
            "xhigh":  { "$ref": "#/$defs/color" },
            "max":    { "$ref": "#/$defs/color" }
          }
        }
      }
    },
    "meters": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "width": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "ctx": { "type": "integer", "minimum": 0 },
            "5h":  { "type": "integer", "minimum": 0 },
            "7d":  { "type": "integer", "minimum": 0 }
          }
        },
        "showEta": { "type": "boolean" },
        "showTokens": { "type": "boolean" },
        "ramp": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["at", "color"],
            "properties": {
              "at": { "type": "integer", "minimum": 0, "maximum": 100 },
              "color": { "$ref": "#/$defs/color" },
              "bold": { "type": "boolean" }
            }
          }
        }
      }
    },
    "accounts": {
      "description": "Config directory in ~/... form to its frame colour.",
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "additionalProperties": false,
        "properties": { "color": { "$ref": "#/$defs/color" } }
      }
    },
    "glyphs": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "filled": { "type": "string" },
        "empty":  { "type": "string" },
        "dirty":  { "type": "string" }
      }
    },
    "segments": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "dir":   { "type": "object", "additionalProperties": false,
                   "properties": { "style": { "enum": ["", "full", "repo", "leaf"] } } },
        "git":   { "type": "object", "additionalProperties": false,
                   "properties": { "counters": { "type": "boolean" },
                                   "maxBranch": { "type": "integer", "minimum": 0 } } },
        "model": { "type": "object", "additionalProperties": false,
                   "properties": { "short": { "type": "boolean" } } },
        "ctx":   { "type": "object", "additionalProperties": false,
                   "properties": { "label": { "type": "string" } } },
        "5h":    { "type": "object", "additionalProperties": false,
                   "properties": { "label": { "type": "string" } } },
        "7d":    { "type": "object", "additionalProperties": false,
                   "properties": { "label": { "type": "string" } } }
      }
    }
  },
  "$defs": {
    "color": {
      "description": "A colour name, or a 256-colour index as a string.",
      "type": "string",
      "pattern": "^(black|red|green|yellow|blue|magenta|cyan|white|orange|gray|[0-9]{1,3})$"
    }
  }
}
```

The `properties` object has exactly 13 keys — `$schema`, `theme`, `lines`, `separator`, `frame`, `frameMargin`, `responsive`, `icons`, `palette`, `meters`, `accounts`, `glyphs`, `segments` — matching both the test and `DCC_VALID_TOPKEYS` in `validate.sh`. The two lists must stay in step; the schema is what editors read, `DCC_VALID_TOPKEYS` is what `doctor` reads.

- [ ] **Step 4: Seed `$schema` and wire `doctor`**

In `plugins/dcc-statusline/scripts/install.sh`, add the source line beside the existing two (after `lib/config.sh`):

```bash
source "$DCC_SRC_DIR/lib/validate.sh"
```

Replace the heredoc in `dcc_seed_config` with one that points at the installed schema copy:

```bash
  cat > "$cfg" <<'JSON'
{
  "$schema": "./dcc-statusline/dcc-statusline.schema.json",
  "accounts": {}
}
JSON
```

The path is relative to `~/.claude/`, where both the config and the installed script tree live.

Replace the config check in `dcc_doctor` (the `if [ -f "$cfg" ]` block, lines 124-132) with:

```bash
  if dcc_validate "$cfg"; then :; else rc=1; fi
```

`dcc_validate` prints its own `ok`/`warn`/`FAIL` lines in the format `doctor` already uses, including the no-config case, so the surrounding branch is no longer needed.

- [ ] **Step 5: Run the tests**

```bash
bash plugins/dcc-statusline/tests/install.test.sh
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: both `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-statusline/dcc-statusline.schema.json \
        plugins/dcc-statusline/scripts/install.sh \
        plugins/dcc-statusline/tests/install.test.sh
git commit -m "feat(statusline): ship config schema, wire doctor"
```

---

### Task 12: Documentation, slash commands, version bump

**Files:**
- Modify: `plugins/dcc-statusline/commands/dcc-statusline.md`
- Modify: `plugins/dcc-statusline/README.md`
- Modify: `plugins/dcc-statusline/scripts/VERSION`, `plugins/dcc-statusline/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json` (version only, if it carries one)

**Interfaces:**
- Consumes: everything from Tasks 1-11.
- Produces: no code interfaces.

- [ ] **Step 1: Add the `preview` and `config` subcommands**

In `plugins/dcc-statusline/commands/dcc-statusline.md`, change the frontmatter `argument-hint` to:

```yaml
argument-hint: "[install|uninstall|status|doctor|preview|config] [--all]"
```

Replace the whole `## Preview` section at the end of the file with:

```markdown
## `preview`
Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/preview.sh" $ARGUMENTS`.

It renders the user's real config against a sample payload at 48, 60, 80, 120 and
200 columns, labelling each block with the width and the tier each line settled
on. Relay the output verbatim inside a fenced block — reformatting it destroys
the alignment that is the entire point.

Accepts `--width N` for a single width, `--theme NAME` to try a theme without
editing the config, and `--config PATH` for a file that is not installed.

If every block reports `tier 0`, the terminal is wide enough that nothing shrinks;
say so rather than leaving the user to wonder whether the feature works.

## `config`
Guided setup. Do not run a script for this one.

1. Read `~/.claude/dcc-statusline.json`, or note that it does not exist yet.
2. Ask which theme they want: `default`, `minimal`, `mono`, or `vivid`.
3. Ask which segments belong on each of the two lines. Valid names are `dir`,
   `git`, `model`, `effort`, `fast`, `agent`, `style`, `account`, `ctx`, `cost`,
   `5h`, `7d`, `time`.
4. If they run more than one Claude account, ask for a frame colour per account
   and write it under `accounts`, keyed by config directory in `~/...` form.
5. Edit the file, keeping the `$schema` key at the top if present.
6. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/preview.sh"` and show the result.

Ask one question at a time. Never overwrite a key the user did not ask you to
change.
```

- [ ] **Step 2: Document the new behaviour in the README**

In `plugins/dcc-statusline/README.md`, insert a section after the paragraph ending "…falls back to two unframed lines rather than drawing a box it cannot close." (currently line 49):

```markdown
## Width

When a line does not fit, its segments shrink rather than disappearing. The whole
line steps down one tier at a time until it fits: the path drops its ancestry,
then elides its middle, then falls back to the leaf; the branch drops its
counters and then truncates; the model shortens to its first word; the meters
narrow their bars, drop the token count and reset countdown, and finally show the
percentage alone.

Tiers are chosen by what fits, not from a width table, so there is nothing to
tune when a branch name gets longer. Only if the most compact rendering still
overflows are whole segments dropped, which is the behaviour every width used to
get.

```json
{ "responsive": { "maxTier": 0 } }
```

`maxTier` caps the escalation. Zero disables shrinking entirely and restores
segment-dropping at every width.

Run `/dcc-statusline preview` to see your own config at five widths side by side.

## Themes

`theme` selects a preset, merged between the built-in defaults and your own file,
so any key you set yourself still wins.

| Theme | Look |
|-------|------|
| `default` | The appearance described above |
| `minimal` | No frame, no icons, percentages without bars |
| `mono` | No hue; the three weights carry the hierarchy alone |
| `vivid` | High contrast, bold throughout |
```

Add these rows to the configuration table (currently lines 91-106), keeping the existing rows:

```markdown
| `theme` | `default`, `minimal`, `mono`, or `vivid` |
| `responsive.maxTier` | Cap on shrinking, `0`–`3`; default `3` |
| `segments.dir.style` | `full`, `repo`, or `leaf`; pins how the path renders |
| `segments.git.counters` | Show the ahead/behind/staged counts; default true |
| `segments.git.maxBranch` | Truncate the branch name; `0` means no limit |
| `segments.model.short` | Always show the first word of the model name |
| `segments.ctx.label` | Label text for a meter, likewise `5h` and `7d` |
```

Update the segment-names line (currently line 108) to include `time`:

```markdown
Segment names: `dir`, `git`, `model`, `effort`, `fast`, `agent`, `style`,
`account`, `ctx`, `cost`, `5h`, `7d`, `time`. Unknown names are ignored.
```

In the Troubleshooting section, replace the first sentence with:

```markdown
Run `/dcc-statusline doctor`. It checks `jq` and `git`, whether the installed copy
matches the plugin version, whether the config parses **and validates** — naming
any key whose value is not usable — whether the account you are running now has a
matching `accounts` entry, whether a fixture payload still renders, and which
accounts have the entry.
```

- [ ] **Step 3: Bump the version in all three places**

```bash
printf '0.5.0\n' > plugins/dcc-statusline/scripts/VERSION
```

In `plugins/dcc-statusline/.claude-plugin/plugin.json`, change `"version": "0.4.0"` to `"version": "0.5.0"`.

Check whether `.claude-plugin/marketplace.json` carries a version for this plugin, and if so change it to match:

```bash
grep -n 'dcc-statusline' -A 5 .claude-plugin/marketplace.json
```

- [ ] **Step 4: Validate the manifest and run the full suite**

```bash
claude plugin validate .
bash plugins/dcc-statusline/tests/run-all.sh
```

Expected: `claude plugin validate .` reports no errors; the suite reports `0 failed` in every file.

- [ ] **Step 5: Verify the preview by eye**

```bash
bash plugins/dcc-statusline/scripts/preview.sh --config /dev/null
```

Expected: five blocks. Confirm by looking that the 48-column block has a closed box with an unbroken right wall, and that its content is visibly more compact than the 200-column block. This is the one check the test suite cannot make for you — the tests assert cell counts, not that the result reads well.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-statusline/ .claude-plugin/marketplace.json
git commit -m "docs(statusline): document tiers, themes and preview"
```

---

## Verification

After Task 12, the following must all hold. Check each before declaring the work done.

- [ ] `bash plugins/dcc-statusline/tests/run-all.sh` reports `0 failed` in all twelve test files.
- [ ] `claude plugin validate .` passes from the repo root.
- [ ] `bash plugins/dcc-statusline/scripts/preview.sh --config /dev/null` renders five closed boxes.
- [ ] `grep -c 'validate\.sh' plugins/dcc-statusline/scripts/statusline.sh` returns `0`.
- [ ] `grep -c '\$(' plugins/dcc-statusline/scripts/statusline.sh plugins/dcc-statusline/scripts/lib/*.sh` returns `0` for every file except `validate.sh`, `config.sh` (whose `dcc_parse_all` has always used `$(jq ...)`), and `install.sh`.
- [ ] A real session shows the status line unchanged at your normal terminal width — tier 0 is the default and nothing should look different until the terminal is narrowed.
