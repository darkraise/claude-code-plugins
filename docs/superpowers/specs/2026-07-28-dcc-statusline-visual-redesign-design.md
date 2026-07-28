# dcc-statusline — Visual Redesign — Design

Date: 2026-07-28
Status: DRAFT — awaiting user review

Supersedes the rendering rules of
[2026-07-27-dcc-statusline-design.md](2026-07-27-dcc-statusline-design.md). That
document's architecture, data flow, install mechanism, and process budget all
stand unchanged; only presentation and the width arithmetic it now requires are
revised here.

## Goal

Make the status line legible at a glance rather than merely complete. Today every
chip on the first line renders in one flat account tint, so the path, branch,
model, mode flags and email all read at identical weight and nothing leads.

Three changes address that: a tinted frame drawn around both lines, semantic
color inside the frame, and a three-weight hierarchy within every segment.

## What changes, in one line each

| Change | Effect |
|--------|--------|
| A box in the account tint encloses both lines | The frame becomes the account signal, and the terminal is identifiable from its border |
| The account email moves onto the top rule | Frees a slot inside and stops a long address dominating the first line |
| Color inside the frame becomes semantic | Hue says what kind of thing a section is, not which account it belongs to |
| Three weights — bold, normal, dim | The leaf directory, branch name, model and percentage lead; parents, counters, separators and units recede |
| Nerd Font icons when a Nerd Font is present | Shorter line, each section identifiable without reading it |
| Meters lose their brackets and change glyph | Reads as a gauge rather than an ASCII progress bar |
| The `think` segment is removed | `effort` sits beside it and reports the reasoning setting that actually varies |

## Verified platform facts

Confirmed against the Claude Code documentation or observed directly on this
machine on 2026-07-28. These are load-bearing; the frame does not work if any of
them is wrong.

| Fact | Source |
|------|--------|
| `tput cols` cannot read the terminal size from a status line script, because Claude Code captures output rather than attaching it to a terminal | Status line doc, sizing output to the terminal |
| Claude Code sets `COLUMNS` and `LINES` to the current terminal dimensions before running the script, from v2.1.153 | Status line doc, sizing output to the terminal |
| Reading an environment variable costs no process, so width is available inside the five-process budget | Follows from the above |
| With no locale set, bash measures and slices **bytes**: `${#s}` on a three-byte box glyph returns 3 | Observed; `locale` reports unset in the Git Bash environment |
| `LC_ALL=C.UTF-8` is available on this Git Bash and makes `${#s}` return characters | Observed; `locale -a` lists `C.utf8`, and `LC_ALL=C.UTF-8` resolves to it |
| A status line may print any number of lines; each `printf` is one row | Status line doc, display multiple lines |
| Multi-line output carrying escape codes is more prone to rendering glitches than plain single-line text | Status line doc, display glitches with escape sequences |
| `thinking.enabled` remains a documented live boolean; the docs do not state it is permanently true | Status line doc, available data |
| Windows Terminal's configured font face is readable at `%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` under `profiles.defaults.font.face` | Observed; reports `CaskaydiaMono Nerd Font` |
| Installed fonts are enumerable from `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts` | Observed; matches `CaskaydiaMono NF*` |
| Bash `printf` renders arbitrary UTF-8 from octal byte escapes, e.g. `printf -v v '\357\201\273'` yields U+F07B | Observed |
| SGR 2 (faint) is the third weight; terminals that ignore it render normal text | Standard ANSI; degrades safely |

One fact deliberately **not** established: whether a font named "Nerd Font"
always draws icons at two cells and "Nerd Font Mono" always at one. The naming
convention says so, but it is a convention, not a guarantee, which is why icon
width is a configurable number rather than an inference.

## Decisions

| Question | Decision | Why |
|----------|----------|-----|
| Frame or no frame | A full box, four rows, tinted by account | Chosen over a left rail and over top-and-bottom rules only; the enclosure is what makes the block read as one object |
| What carries account identity | The frame | Frees every hue inside the box to carry meaning instead |
| Where the account email goes | Onto the top rule | The frame is already the identity; the address belongs on it, not competing inside it |
| Color inside the frame | One hue per section kind | Deliberately reverses the earlier "everything takes the account tint" rule, which the frame now makes redundant |
| Cost color | Violet, outside the ramp | Green through red belong to the usage ramp; cost in green would read as a usage level |
| Icon policy when no Nerd Font | Drop icons entirely, restore words | Emoji substitutes are double-width and would break the right wall |
| When to detect the font | Once, at install and on the version-change sync hook | The render path budgets five processes and must not fork to probe fonts |
| How the render learns the result | Reads a one-word cache file with the `read` builtin | Costs no process |
| Which font signal wins | The terminal's configured face, when readable; installed fonts only as fallback | An installed Nerd Font does not prove the terminal uses it |
| Overflow policy | Drop whole sections, greedily: keep every section that still fits, skip the ones that do not | Cutting a string mid-way risks severing an escape sequence and bleeding color across the row. Greedy rather than trailing-only because one oversized branch name should not also cost the model, effort and mode flags that would have fit |
| When `COLUMNS` is absent or tiny | Fall back to the unframed two-line layout | Better than drawing a box that cannot close |
| Source encoding of glyphs | Octal UTF-8 byte escapes | Keeps every script pure ASCII and immune to editors, pipes and terminals that mangle the private-use area |
| `think` segment | Removed from defaults and from the segment dispatcher | Redundant beside `effort`; unknown segment names are already ignored, so an existing config listing it degrades to nothing |

## The three weights

All three are the same color. Weight, not hue, separates them.

| Weight | SGR | Carries |
|--------|-----|---------|
| Bold | `1` | Leaf directory, branch name, model, meter percentage |
| Normal | none | Icons, effort, mode flags, meter labels |
| Dim | `2` | Parent path, separators, git counters, dirty mark, token counts, countdowns |

## Palette

Section hues, all outside the ramp's green-to-red range so no section can be
mistaken for a usage reading.

| Section | Color | 256 code |
|---------|-------|----------|
| `dir` | blue | 12 |
| `git` | magenta | 13 |
| `model` | cyan | 14 |
| `effort` | grey | 245 |
| `fast` | white | 15 |
| `cost` | violet | 141 |
| `ctx`, `5h`, `7d` | usage ramp, unchanged | 10 / 11 / 208 / 9 |
| frame | account tint | per `accounts` config |
| `account` chip | account tint, but only when unframed | per `accounts` config |

The account chip is a special case. In framed mode it does not render at all —
the address moves onto the top rule and the frame carries the identity. It
therefore only appears when the frame is off, and in that mode it takes the
account tint rather than the muted grey. Without that, a terminal too narrow to
frame, or a host that does not set `COLUMNS`, would carry no at-a-glance account
signal whatsoever, which is the single thing this plugin exists to provide.

The ramp keeps its existing four stops: green below 50, yellow to 74, orange to
89, then red and bold from 90.

## Icons

Nine glyphs, all from the Font Awesome block present in every Nerd Font release.
Each is written in source as an octal UTF-8 escape.

| Segment | Glyph | Codepoint | Octal |
|---------|-------|-----------|-------|
| `dir` | folder | U+F07B | `\357\201\273` |
| `git` | branch | U+E0A0 | `\356\202\240` |
| `model` | chip | U+F2DB | `\357\213\233` |
| `fast` | bolt | U+F0E7 | `\357\203\247` |
| `account` | user | U+F007 | `\357\200\207` |
| `ctx` | database | U+F1C0 | `\357\207\200` |
| `5h`, `7d` | clock | U+F017 | `\357\200\227` |
| `cost` | dollar | U+F155 | `\357\205\225` |
| meter filled / empty | — | U+25B0 / U+25B1 | `\342\226\260` / `\342\226\261` |

Box drawing uses U+256D, U+256E, U+2570, U+256F, U+2500 and U+2502.

## Font detection

Runs at install and from the existing `SessionStart` sync hook, never during a
render. Writes one word — `nerd` or `unicode` — plus an icon cell width to
`~/.claude/dcc-statusline/icons.detected`.

Probe order, first match wins:

1. `DCC_ICONS` environment variable. Read by the probe **and** by the render
   path, where it outranks the cache file — that is what makes tests hermetic,
   since a test process cannot rely on whatever the installer happened to detect.
2. Windows Terminal's configured font face. Authoritative when readable, because
   it names the font actually rendering. A face matching `Nerd Font`, `NF`, `NFM`
   or `Powerline` selects `nerd`; anything else selects `unicode`.
3. Installed fonts — the Windows font registry, `fc-list` on Linux, the font
   directories on macOS. Fallback only, used when step 2 cannot be read.
4. Otherwise `unicode`.

Icon cell width derives from the same face name, matched on the **suffix** and
never on a substring: a face ending in `Nerd Font Mono`, `NF Mono` or `NFM`
implies one cell; anything else implies two. The suffix rule matters because
family names such as `CaskaydiaMono Nerd Font` contain "Mono" in the family
portion while being the double-width variant. The `icons.width` config key
overrides the result.

`doctor` reports which signal fired, the resolved mode, and the resolved width.

## Width arithmetic

The frame's correctness rests entirely on counting cells, not characters and not
bytes.

`statusline.sh` sets `LC_ALL=C.UTF-8` before any width arithmetic. Without it
bash counts bytes and every box glyph counts as three.

Segments are assembled as `(painted, cells)` pairs rather than one string. Every
non-ASCII piece passes its cell count explicitly; icons pass the configured icon
width. Composition, for a terminal of `C` columns and icon width `I`:

Each row below must total exactly `C` cells. Corner, edge and rule stand for the
box glyphs listed above; every term is a cell count, not a literal string.

```
top      corner(1) + rule(1) + space(1) + icon(I) + space(1)
       + title(len) + space(1) + rule(n) + corner(1)      where n = C - 6 - I - len

content  edge(1) + space(1) + body(used) + pad(C - 4 - used) + space(1) + edge(1)

bottom   corner(1) + rule(C - 2) + corner(1)
```

When icons are off, the icon and its trailing space are omitted and
`n = C - 5 - len`.

Rendering must be verified, not assumed: a test strips escape sequences, measures
each row in cells, and asserts it equals `COLUMNS`. The prototype passes this at
110, 90, 72, 60 and 48 columns, at both icon widths.

## Overflow

When a content line exceeds `C - 4` cells, whole segments are dropped until it
fits. The scan is greedy rather than trailing-only: segments are considered in
render order, each is kept if it still fits within the remaining budget, and
skipped if it does not. A later, smaller segment may therefore survive an
earlier, larger one that was skipped, so the surviving set is not always a
prefix of the configured order.

That is the intended behaviour, not an accident of the loop. A single oversized
branch name should cost you the branch, not also the model, effort and mode
flags that would have fitted beside it. Each segment carries its own hue and
icon, so a gap in the order is unambiguous to read.

Segments are never cut mid-string, because a cut could sever an escape sequence
and bleed color across the remainder of the row. Each line is padded to the
right wall so both content rows align.

## Configuration

New keys, merged over defaults exactly as the existing ones are. Anyone who has
already set `glyphs` or `separator` keeps their values.

| Key | Values | Default | Meaning |
|-----|--------|---------|---------|
| `frame` | `auto`, `box`, `none` | `auto` | `auto` draws the box when `COLUMNS` is known and at least 48, otherwise falls back to two unframed lines |
| `icons.mode` | `auto`, `nerd`, `unicode` | `auto` | `auto` reads the detection cache |
| `icons.width` | `1`, `2` | from detection | Cells an icon occupies |
| `palette` | section name to color | table above | Section hues |

`icons` is an object, not a scalar, so that mode and width can live under one
key — matching the existing `meters.width.ctx` nesting:

```json
"icons": { "mode": "auto", "width": 2 }
```

Changed defaults: `glyphs.filled` becomes `▰`, `glyphs.empty` becomes `▱`, the
meter suffix separator becomes ` · ` rather than parentheses, and `lines[0]`
loses `think`.

## Internal changes

| Unit | Change |
|------|--------|
| `lib/color.sh` | `dcc_color` gains a `dim` weight emitting SGR 2 |
| `lib/render.sh` | `dcc_bar` returns filled and empty runs separately so each takes its own color; the joiner concatenates pre-painted segments and tracks cell width |
| `lib/segments.sh` | Segments paint themselves through a `dcc_seg_add <text> [weight] [color] [cells]` helper instead of returning one color and one flat string; `think` handler removed |
| `lib/frame.sh` | New. Box drawing, padding, overflow, and the `COLUMNS` fallback |
| `lib/icons.sh` | New. The two glyph tables and mode resolution |
| `scripts/detect-font.sh` | New. The probe, run at install and sync only |
| `statusline.sh` | Sets `LC_ALL=C.UTF-8`; routes through the frame when enabled |

The existing constraint holds throughout: no `$(...)` anywhere in the render
path.

## Testing

| Area | Coverage |
|------|----------|
| Frame width | Strip escapes, measure cells, assert every row equals `COLUMNS`, at 48 / 60 / 72 / 90 / 110 columns and both icon widths |
| Overflow | Assert whole sections are dropped and no escape sequence is ever split, including the non-monotonic case where an oversized middle section is skipped while a later, smaller one is kept |
| Fallback | `COLUMNS` unset, empty, non-numeric, and below the minimum all produce the unframed two-line layout |
| Locale | Width assertions run with the locale unset, proving the script sets its own |
| Detection | Fixture Windows Terminal settings with a Nerd face, a non-Nerd face, a missing file, and a corrupt file; fixture font lists; precedence between signals |
| Icon mode | `nerd` and `unicode` render paths, and `DCC_ICONS` override precedence |
| Weights | `dcc_color` emits SGR 1, SGR 2, and neither, correctly |
| Meters | Split bar coloring, ramp boundaries at 49/50, 74/75, 89/90, and the clamps at 0 and 100 |
| End to end | Golden output for both icon modes, with `DCC_ICONS` and `COLUMNS` forced so the goldens are hermetic |

Existing golden files change throughout. That is expected: this is a visual
redesign.

## Out of scope

Powerline chevrons and background-filled segments; truecolor or gradient ramps;
any change to which data the payload provides or which segments exist beyond
removing `think`; per-account palettes; and changing the two-line content split.
