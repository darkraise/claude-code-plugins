# dcc-statusline — Responsive, Themed, Configurable UI — Design

Date: 2026-08-08
Status: DRAFT — awaiting user review

Builds on [2026-07-28-dcc-statusline-visual-redesign-design.md](2026-07-28-dcc-statusline-visual-redesign-design.md).
That document's colour semantics, three-weight hierarchy, frame, icon policy and
process budget all stand unchanged. This document adds width adaptation, themes,
per-segment options, and a configuration surface that can be inspected before it
is trusted.

## Goal

The status line is complete but rigid. It has one breakpoint — framed above 48
usable columns, two bare lines below — and when a line does not fit,
`dcc_line_build` drops whole segments. On a narrow terminal the cost figure or
the 5h meter silently vanishes rather than shrinking.

Four changes address that: segments that shrink instead of disappearing, named
themes, options on the built-in segments, and a preview-plus-validation surface
so a config can be checked without being lived with.

## What changes, in one line each

| Change | Effect |
|--------|--------|
| Segments render at four tiers, escalating until the line fits | Data shrinks rather than vanishing; nothing is lost until tier 3 still overflows |
| Tier is chosen per line, by fit | No width table to maintain; adapts to any terminal and any branch name |
| A `theme` key selects a named preset | A coherent look without hand-assembling a palette and segment list |
| Built-in segments gain options | Path style, branch truncation, git counters, meter labels, per-line separators |
| A `time` segment | Fork-free clock via bash's `%(%H:%M)T` |
| `preview.sh` renders the real config at several widths | The responsive tiers are visible before they are trusted |
| `validate.sh`, sourced only off the render path | `doctor` names the bad key instead of the line showing a red `cfg?` |
| A JSON Schema ships with the plugin | Editor autocomplete and validation for a config file that is about to grow |

## Non-goals

- **Custom segments.** Neither a command-running segment nor a static/env-var
  one. A command segment would add forks to every render; a static one is not
  worth a config surface nobody asked for.
- **A `think` segment.** Removed deliberately on 2026-07-28 because `effort`
  reports the reasoning setting that actually varies, and its absence is asserted
  by `tests/segments.test.sh:110` and `tests/e2e.test.sh:35`. `P_THINK` continues
  to be extracted for drift detection (`tests/config.test.sh:170`) and stays
  unrendered.
- **A one-line mode.** Two lines at every width. The narrow tiers make them fit.
- **A wide mode.** Extra room is already used: tier 0 simply fits.

## Constraint that governs everything

The render path budgets five processes: one `jq` parsing payload, config and
account file together, and two `git` calls with their timeout wrappers. Every
feature here is implemented either inside that single `jq` call (themes, segment
options) or in pure bash string work (tiers). Validation and preview, which
cannot be made fork-free, run **only** in `doctor` and `preview` and are never
sourced by `statusline.sh`.

## Responsive tiers

### The model

`dcc_segment` gains a tier parameter. A line is rendered at tier 0 and measured;
if the total exceeds the budget, the whole line is re-rendered one tier higher,
repeating to tier 3. The first tier that fits is emitted. If tier 3 still
overflows, the existing greedy segment-drop in `dcc_line_build` runs unchanged as
the last resort.

Escalation is uniform across a line — every segment moves to the same tier
together. Mixing tiers within one line would pack marginally tighter at the cost
of looking arbitrary: there would be no rule a reader could infer from why the
path abbreviated but the branch did not.

Escalation is independent **between** lines. Line two carries meters and line one
carries identity; they hold different content and there is no visual coupling
that a tier mismatch would break.

### Tier table

| | tier 0 — full | tier 1 — compact | tier 2 — tight | tier 3 — minimal |
|---|---|---|---|---|
| `dir` | `~/Repos/Personal/` `claude-code-plugins` `/plugins/dcc-statusline` | ancestry dropped: `claude-code-plugins/plugins/dcc-statusline` | `claude-code-plugins/…/dcc-statusline` | `dcc-statusline` |
| `git` | `main* ↑2 ↓1 ●3 ○2 ?2` | unchanged | `main*` | `main*`, branch truncated to `maxBranch`, or to 12 when `maxBranch` is 0 |
| `model` | `Opus 4.8` | unchanged | unchanged | first word: `Opus` |
| meters | `ctx ▰▰▰▰▰▱▱▱▱▱ 47% · 94k` | bar at 60% of configured width | bar at 40%, suffix dropped | no bar: `ctx 47%` |

Meter widths at tiers 1 and 2 are `(width * 60 + 50) / 100` and
`(width * 40 + 50) / 100` — integer arithmetic, rounding to nearest, matching the
existing fill calculation in `dcc_bar`. A width below two cells drops the bar
entirely, at every tier including tier 0: a one-cell bar reads as empty at any
figure under 100%, so the percentage carries the reading alone. This is a
deliberate, human-ruled exception to the tier-0 byte-identity rule — the only
one. Widths are also clamped to at most 64 cells; `dcc_bar` builds its string
by repeated append, quadratic in the width, and an unbounded configured width
would freeze the continuously-redrawing render.

Every other segment — `effort`, `fast`, `agent`, `style`, `account`, `cost`,
`time` — renders identically at all four tiers. They are already short, and a
segment with no compact form simply ignores the parameter.

The three-tone path rule from the 2026-07-28 redesign holds at every tier that
still shows more than one component: what leads to the repository is dim, the
repository name is bold, the position inside it is plain. At tier 2 the elision
`…` is dim. At tier 3 only the bold anchor remains.

### Interaction with the frame

Tier selection runs against `DCC_FRAME_BUDGET`, so it applies in framed mode. In
unframed mode there is no known width — `COLUMNS` was missing or unusable, which
is why the frame is off — so no budget exists and tier 0 always renders. This
preserves today's unframed output exactly.

### Escape hatch

```json
{ "responsive": { "maxTier": 0 } }
```

`maxTier: 0` reproduces today's behaviour precisely: one render at tier 0, then
greedy dropping. Values 1–3 cap escalation partway. The key is absent from the
default config; the default is 3.

### Cost

A line is rendered at most four times. All of it is bash string concatenation and
arithmetic with no subshells, so the process budget is untouched. Wall-clock cost
is the concern, not fork cost, and only on terminals narrow enough to escalate —
a wide terminal fits at tier 0 and renders once, as today.

## Themes

A `theme` key names a preset. The merge order is:

```
defaults * theme * userConfig
```

The user's own keys always win, so setting a theme and then overriding one colour
behaves as expected. The theme table is embedded in the jq program alongside
`DCC_DEFAULT_CONFIG` and resolved in the same call — no extra process, no extra
file read.

| Theme | Intent |
|-------|--------|
| `default` | Today's appearance. Selecting it explicitly is a no-op. |
| `minimal` | Frame off, icons off, meters show percentages without bars, short segment list. |
| `mono` | No hue. The three weights carry the whole hierarchy. For light backgrounds and low-colour terminals. |
| `vivid` | High contrast, bold-heavy, saturated ramp. |

An unrecognised theme name resolves to `default` and is reported by `doctor`
rather than failing the render.

## Segment options

A `segments` object, keyed by segment name. Every key is optional and every
absent key keeps today's behaviour.

| Key | Type | Meaning |
|-----|------|---------|
| `segments.dir.style` | `full` \| `repo` \| `leaf` | Pins the path rendering to a tier regardless of fit. Absent means follow the line's tier. |
| `segments.git.counters` | bool | Show ahead/behind/staged/unstaged/untracked. Default true. |
| `segments.git.maxBranch` | int | Truncate the branch name. Default 0, meaning no limit. |
| `segments.model.short` | bool | Always render the first word. Default false. |
| `segments.ctx.label`, `.5h.label`, `.7d.label` | string | Override the meter's label text. |
| `separator` | string \| array | An array supplies a per-line separator; a string applies to both, as today. An array shorter than the line count reuses its last element; an empty array falls back to the default. |

`segments.dir.style` and `segments.model.short` pin a segment below the line's
tier but never above it: if the line escalates past the pinned rendering, the
segment still shrinks. A pin is a floor on compactness, not a veto on fitting.

### The `time` segment

A new built-in rendering the current time. `printf -v t '%(%H:%M)T' -1` is a bash
builtin and costs no fork, the same mechanism `statusline.sh` already uses for
`DCC_NOW`. It is not in the default line list; adding it is opt-in. Colour comes
from `palette.mute`. `DCC_NOW` continues to be overridable by tests, and the
`time` segment reads it so a frozen clock produces a deterministic render.

## Configuration surface

### `scripts/preview.sh`

Renders a sample payload through the real config at 48, 60, 80, 120 and 200
columns, labelling each block with its width and the tier each line selected.

```
--width N      render one width only
--theme NAME   override the theme without editing the config
--config PATH  render a config file that is not installed
```

It sources the same libraries as `statusline.sh` and sets `COLUMNS` per block, so
what it shows is what the status line produces. It is a separate script rather
than a flag on `statusline.sh` because `statusline.sh` reads stdin and must stay
free of argument parsing on the render path.

Wired to `/dcc-statusline preview`.

### `scripts/lib/validate.sh`

Walks a parsed config reporting: unknown keys, values of the wrong type, invalid
colour names, invalid segment names, out-of-range integers, and unknown theme
names. Each finding names the key path, the value received, and what is valid.

Sourced by `install.sh` (for `doctor`) alone; `preview.sh` renders without it.
**Never** sourced by
`statusline.sh`. This is the boundary that protects the process budget, and it is
asserted by a test that greps `statusline.sh`'s source list.

The status line's own behaviour is unchanged: a bad config still degrades
silently to defaults and still shows the red `cfg?` token. Diagnosis belongs in
`doctor`, where it can be read, not in a status line that has four columns to
spare.

### `scripts/dcc-statusline.schema.json`

A JSON Schema for the config, shipped under `scripts/` so that
`dcc_copy_scripts` carries it to an installed copy — a file at the plugin root
would never reach `~/.claude/dcc-statusline/`. `install.sh` seeds
`"$schema"` into a newly created config pointing at the installed copy, so an
editor autocompletes and validates while typing. `doctor` reports whether the
config validates against it when a validator is available, falling back to
`validate.sh`'s own checks when none is.

`$schema` is accepted and ignored by the merge — it is a documented key in the
schema itself, so it does not surface as an unknown key.

### `/dcc-statusline config`

Guided setup, written as slash-command instructions in
`commands/dcc-statusline.md`. Claude reads the current config, asks which theme,
which segments, and which account colours, then edits the file. No interactive
TUI is built in bash; the conversational layer already exists.

## Structure

`DCC_JQ_PROG` roughly triples with the theme table and the segment options, and
`config.sh` is already 236 lines of which the program is 50. The program moves to
`scripts/lib/jq-prog.sh`, sourced by `config.sh`, leaving `config.sh` holding path
resolution, defaults and the fallback chain.

`segments.sh` grows with the tier branches. It stays one file: the segments share
`_dcc_icon` and `_dcc_meter` and splitting them would separate a dispatcher from
the handlers it dispatches to for no gain in comprehension.

New files:

```
scripts/lib/jq-prog.sh              the single jq program
scripts/lib/validate.sh             config diagnostics, off the render path
scripts/preview.sh                  multi-width preview
scripts/dcc-statusline.schema.json  config schema, copied with the scripts
```

## Testing

New test files: `tiers.test.sh`, `theme.test.sh`, `preview.test.sh`,
`validate.test.sh`.

The load-bearing assertions:

1. **Frame integrity across widths.** Every framed row is exactly
   `DCC_FRAME_COLS` cells at `COLUMNS` of 40, 52, 60, 80, 120 and 200. Tier
   escalation is precisely the change that produces a ragged right wall, and
   nothing currently guards width beyond a single case.
2. **Monotonic shrink.** For each segment, the cell width at tier N+1 is less
   than or equal to tier N. A tier that grows would loop escalation without ever
   fitting.
3. **Tier 0 is unchanged.** Every existing rendering assertion still passes at
   tier 0, and `responsive.maxTier: 0` reproduces the current output byte for
   byte against the existing fixtures.
4. **Unframed output is unchanged.** With `COLUMNS` unset, output matches today's
   fixtures exactly.
5. **Budget boundary.** `statusline.sh` does not source `validate.sh`.
6. **Theme merge order.** A user key overrides the same key set by a theme.
7. **Escalation terminates.** A pathological input — a 300-character branch name
   at `COLUMNS=52` — reaches tier 3, falls through to greedy dropping, and still
   emits a correctly-sized frame.

## Phasing

Each phase is independently shippable and leaves the plugin working.

1. **Tiers.** `jq-prog.sh` split, tier parameter, escalation loop, `responsive`
   key, frame-integrity and monotonic-shrink tests.
2. **Themes.** Theme table, merge order, four presets.
3. **Segment options.** The `segments` object, array separators, the `time`
   segment.
4. **Config surface.** `validate.sh`, `preview.sh`, the schema, the `preview` and
   `config` slash-command entries, `doctor` diagnostics.

## Risks

**Width miscounting.** The plugin measures characters, not terminal cells, and
already documents that double-width text in a directory or branch name pushes the
right wall short. Tier 2's elision character and any new glyph must declare their
cell width explicitly to `dcc_seg_add`, as the existing icons and bar cells do.
The frame-integrity test catches the ASCII case; the double-width case remains a
documented limitation, unchanged.

**Escalation cost on narrow terminals.** Four renders instead of one. No forks,
but measurably more bash work on exactly the machines least likely to be fast.
`responsive.maxTier` is the mitigation if it proves to matter.

**Config growth.** The surface roughly doubles. The schema and `doctor`
diagnostics exist specifically to keep that from becoming a burden, which is why
phase 4 is not optional.
