# dcc-statusline Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reframe the dcc-statusline output as a tinted box carrying account identity, with semantic per-section colour and a three-weight hierarchy inside it.

**Architecture:** Segments stop returning a colour plus a flat string and instead paint themselves through an accumulator that also tracks display width in cells. A new frame layer consumes those measured lines, pads them to `COLUMNS`, and draws a box. Font capability is probed once at install time and cached to a file the render path reads with a shell builtin.

**Tech Stack:** Bash 4+, one `jq` invocation, `git`. No new dependencies.

## Global Constraints

- No `$(...)` command substitution anywhere in the render path. Each fork costs 10-20ms under MSYS2 and the budget is five processes per render: one `jq`, two `git`, and their `timeout` wrappers.
- Functions return values through global out-variables, never by printing.
- `statusline.sh` must set `LC_ALL=C.UTF-8` before any width arithmetic. Without it bash measures bytes, so a three-byte box glyph counts as three cells.
- All non-ASCII characters in shell sources are written as octal UTF-8 escapes via `printf -v`. Source files stay pure ASCII.
- Any segment lacking data renders as nothing and its separators disappear with it. A missing block shortens the line; it never breaks it.
- Tests live in `plugins/dcc-statusline/tests/`, are plain bash, source `tests/lib.sh`, use `check <label> <got> <want>`, and end with `finish`.
- Run the full suite with `bash plugins/dcc-statusline/tests/run-all.sh`. This is
  a cross-cutting refactor, so Tasks 5 through 8 deliberately leave sibling test
  files red while their callers are migrated. Each of those tasks runs only its
  own test file; the full suite is green again at Task 9 and is run there.
- All work happens on branch `feat/statusline-visual-redesign`.
- Commit messages follow `<type>(<scope>): <subject>`, imperative, 50 characters max, no trailing period.

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `scripts/lib/color.sh` | Named colours to ANSI, three weights | Modify |
| `scripts/lib/icons.sh` | Glyph tables and icon mode/width resolution | Create |
| `scripts/lib/render.sh` | Bar fill, countdowns, segment accumulator with cell counts | Modify |
| `scripts/lib/frame.sh` | Box drawing, padding, overflow, `COLUMNS` fallback | Create |
| `scripts/lib/segments.sh` | One function per segment, self-painting | Modify |
| `scripts/lib/config.sh` | The single `jq` parse; new config keys and defaults | Modify |
| `scripts/statusline.sh` | Entry point; locale, frame routing | Modify |
| `scripts/detect-font.sh` | Font probe, run at install and sync only | Create |
| `scripts/install.sh` | Runs the probe; `doctor` reports its result | Modify |
| `scripts/sync.sh` | Re-runs the probe after a version change | Modify |

Test files mirror the library split: `color.test.sh`, `icons.test.sh`, `render.test.sh`, `frame.test.sh`, `segments.test.sh`, `config.test.sh`, `detect-font.test.sh`, `e2e.test.sh`.

---

### Task 1: Dim weight in the colour layer

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/color.sh:14-36`
- Test: `plugins/dcc-statusline/tests/color.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `dcc_color <name> [weight]` and `dcc_paint <text> <color> [weight]`, where `weight` is one of `""`, `bold`, `dim`. `dcc_color` sets `DCC_C`; `dcc_paint` sets `DCC_PAINTED`.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dcc-statusline/tests/color.test.sh`, before the `finish` line:

```bash
# --- dim weight ---------------------------------------------------------------
dcc_color cyan dim
check "dim emits SGR 2 before the colour" "$DCC_C" $'\033[2;38;5;14m'
dcc_color cyan bold
check "bold still emits SGR 1"            "$DCC_C" $'\033[1;38;5;14m'
dcc_color cyan
check "no weight emits neither"           "$DCC_C" $'\033[38;5;14m'
dcc_color cyan nonsense
check "an unknown weight falls back to plain" "$DCC_C" $'\033[38;5;14m'
dcc_paint "x" cyan dim
check "paint threads the weight through" "$DCC_PAINTED" $'\033[2;38;5;14mx\033[0m'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/color.test.sh`
Expected: FAIL on "dim emits SGR 2 before the colour", got `\033[38;5;14m`

- [ ] **Step 3: Write minimal implementation**

In `scripts/lib/color.sh`, replace the trailing `if` of `dcc_color`:

```bash
  case "$bold" in
    bold) DCC_C="$DCC_ESC[1;38;5;${code}m" ;;
    dim)  DCC_C="$DCC_ESC[2;38;5;${code}m" ;;
    *)    DCC_C="$DCC_ESC[38;5;${code}m"   ;;
  esac
}
```

Rename the local `bold` to `weight` in the signature comment and body so the
parameter name matches what it now carries:

```bash
dcc_color() { # dcc_color <name> [weight: ''|bold|dim] -> DCC_C
  local name="${1:-}" weight="${2:-}" code=""
```

and change the `case` subject to `"$weight"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/color.test.sh`
Expected: PASS, 0 failed

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/color.sh plugins/dcc-statusline/tests/color.test.sh
git commit -m "feat(statusline): add dim weight to colour layer"
```

---

### Task 2: Config keys and changed defaults

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/config.sh:7-26` (defaults), `:38-74` (jq program), `:108-120` (fallback globals)
- Test: `plugins/dcc-statusline/tests/config.test.sh:57`

**Interfaces:**
- Consumes: nothing.
- Produces: globals `DCC_FRAME_MODE` (`auto`/`box`/`none`), `DCC_ICON_MODE_CFG` (`auto`/`nerd`/`unicode`), `DCC_ICON_W_CFG` (integer, `0` meaning "use detection"), and palette globals `DCC_P_DIR`, `DCC_P_GIT`, `DCC_P_MODEL`, `DCC_P_EFFORT`, `DCC_P_FAST`, `DCC_P_COST`, `DCC_P_MUTE`. Default `DCC_LINE1` no longer contains `think`; `DCC_GLYPH_FILLED` and `DCC_GLYPH_EMPTY` change.

- [ ] **Step 1: Write the failing test**

In `plugins/dcc-statusline/tests/config.test.sh`, replace line 57 and append new
checks after the existing defaults block:

```bash
check "defaults: line one segment order"        "$DCC_LINE1" "dir git model effort fast agent style account"
check "defaults: frame mode"                    "$DCC_FRAME_MODE"    "auto"
check "defaults: icon mode"                     "$DCC_ICON_MODE_CFG" "auto"
check "defaults: icon width defers to detection" "$DCC_ICON_W_CFG"   "0"
check "defaults: path palette"                  "$DCC_P_DIR"    "blue"
check "defaults: branch palette"                "$DCC_P_GIT"    "magenta"
check "defaults: model palette"                 "$DCC_P_MODEL"  "cyan"
check "defaults: effort palette"                "$DCC_P_EFFORT" "gray"
check "defaults: fast palette"                  "$DCC_P_FAST"   "white"
check "defaults: cost palette"                  "$DCC_P_COST"   "141"
check "defaults: muted palette"                 "$DCC_P_MUTE"   "gray"
```

Then append a user-override block before `finish`:

```bash
cfg="$(mktemp)"
cat > "$cfg" <<'JSON'
{ "frame": "none",
  "icons": { "mode": "nerd", "width": 1 },
  "palette": { "dir": "green" } }
JSON
dcc_parse_all "$(cat "$F/full.json")" "$cfg" /dev/null
check "user frame mode overrides"   "$DCC_FRAME_MODE"    "none"
check "user icon mode overrides"    "$DCC_ICON_MODE_CFG" "nerd"
check "user icon width overrides"   "$DCC_ICON_W_CFG"    "1"
check "user palette entry overrides" "$DCC_P_DIR"        "green"
check "unset palette entries keep defaults" "$DCC_P_GIT" "magenta"
rm -f "$cfg"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/config.test.sh`
Expected: FAIL with `DCC_FRAME_MODE: unbound variable` or empty values

- [ ] **Step 3: Write minimal implementation**

In `scripts/lib/config.sh`, replace `DCC_DEFAULT_CONFIG` with:

```bash
DCC_DEFAULT_CONFIG='{
  "lines": [
    ["dir","git","model","effort","fast","agent","style","account"],
    ["ctx","cost","5h","7d"]
  ],
  "separator": "  \u00b7  ",
  "frame": "auto",
  "icons": { "mode": "auto", "width": 0 },
  "palette": {
    "dir": "blue", "git": "magenta", "model": "cyan",
    "effort": "gray", "fast": "white", "cost": "141", "mute": "gray"
  },
  "meters": {
    "width": {"ctx":10,"5h":8,"7d":8},
    "showEta": true,
    "showTokens": true,
    "ramp": [
      {"at":0,"color":"green"},
      {"at":50,"color":"yellow"},
      {"at":75,"color":"orange"},
      {"at":90,"color":"red","bold":true}
    ]
  },
  "accounts": {},
  "glyphs": {"filled":"\u25b0","empty":"\u25b1","dirty":"*"}
}'
```

Every non-ASCII character in this blob is written as a JSON `\uXXXX` escape.
`jq` decodes them itself, so `config.sh` stays pure ASCII without any
`printf -v` assembly — the Global Constraint holds here with no exception.
Note this also changes the existing `separator` default, which previously held
a literal middle dot.

Add to `DCC_JQ_PROG`, after the `DCC_SEP` line:

```
  @sh "DCC_FRAME_MODE=\($c.frame // "auto")",
  @sh "DCC_ICON_MODE_CFG=\($c.icons.mode // "auto")",
  @sh "DCC_ICON_W_CFG=\(num($c.icons.width; 0))",
  @sh "DCC_P_DIR=\($c.palette.dir // "blue")",
  @sh "DCC_P_GIT=\($c.palette.git // "magenta")",
  @sh "DCC_P_MODEL=\($c.palette.model // "cyan")",
  @sh "DCC_P_EFFORT=\($c.palette.effort // "gray")",
  @sh "DCC_P_FAST=\($c.palette.fast // "white")",
  @sh "DCC_P_COST=\($c.palette.cost // "141")",
  @sh "DCC_P_MUTE=\($c.palette.mute // "gray")",
```

Add matching fallback defaults beside the existing `DCC_SEP=` block:

```bash
DCC_FRAME_MODE="auto"
DCC_ICON_MODE_CFG="auto"
DCC_ICON_W_CFG=0
DCC_P_DIR="blue"
DCC_P_GIT="magenta"
DCC_P_MODEL="cyan"
DCC_P_EFFORT="gray"
DCC_P_FAST="white"
DCC_P_COST="141"
DCC_P_MUTE="gray"
```

Change the glyph and separator fallbacks to match the new defaults. These are
shell assignments rather than JSON, so they use octal escapes:

```bash
printf -v DCC_GLYPH_FILLED '\342\226\260'   # U+25B0
printf -v DCC_GLYPH_EMPTY  '\342\226\261'   # U+25B1
printf -v DCC_SEP          '  \302\267  '   # U+00B7 middle dot
```

Delete the literal `DCC_SEP="  ·  "` assignment these replace.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/config.test.sh`
Expected: PASS, 0 failed

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/config.sh plugins/dcc-statusline/tests/config.test.sh
git commit -m "feat(statusline): add frame, icon and palette config"
```

---

### Task 3: Icon tables and mode resolution

**Files:**
- Create: `plugins/dcc-statusline/scripts/lib/icons.sh`
- Create: `plugins/dcc-statusline/tests/icons.test.sh`

**Interfaces:**
- Consumes: `DCC_ICON_MODE_CFG`, `DCC_ICON_W_CFG` from Task 2.
- Produces: `dcc_icons_init` setting `DCC_ICON_MODE` (`nerd`/`unicode`), `DCC_ICON_W` (integer cells, `0` in unicode mode), and the glyph globals `DCC_I_DIR`, `DCC_I_GIT`, `DCC_I_MODEL`, `DCC_I_FAST`, `DCC_I_ACCOUNT`, `DCC_I_CTX`, `DCC_I_CLOCK`, `DCC_I_COST` — each an empty string in unicode mode.

- [ ] **Step 1: Write the failing test**

Create `plugins/dcc-statusline/tests/icons.test.sh`:

```bash
#!/usr/bin/env bash
# Icon mode resolution: env beats config beats cache beats default.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/icons.sh"

cache_dir="$(mktemp -d)"
export DCC_STATUSLINE_HOME="$cache_dir"

DCC_ICON_MODE_CFG="auto"; DCC_ICON_W_CFG=0

# --- default with no cache and no override ------------------------------------
unset DCC_ICONS
dcc_icons_init
check "no signal at all falls back to unicode" "$DCC_ICON_MODE" "unicode"
check "unicode mode emits no folder glyph"     "$DCC_I_DIR"     ""
check "unicode mode reports zero icon cells"   "$DCC_ICON_W"    "0"

# --- cache file ---------------------------------------------------------------
printf 'nerd 2\n' > "$cache_dir/icons.detected"
dcc_icons_init
check "the cache selects nerd mode"   "$DCC_ICON_MODE" "nerd"
check "the cache selects icon width"  "$DCC_ICON_W"    "2"
check "nerd mode populates the folder glyph" \
  "$(printf '%s' "$DCC_I_DIR" | od -An -tx1 | tr -d ' \n')" "ef81bb"
check "nerd mode populates the branch glyph" \
  "$(printf '%s' "$DCC_I_GIT" | od -An -tx1 | tr -d ' \n')" "ee82a0"

# --- config beats cache -------------------------------------------------------
DCC_ICON_MODE_CFG="unicode"
dcc_icons_init
check "config mode outranks the cache" "$DCC_ICON_MODE" "unicode"
DCC_ICON_MODE_CFG="auto"

DCC_ICON_W_CFG=1
dcc_icons_init
check "config width outranks the cache" "$DCC_ICON_W" "1"
DCC_ICON_W_CFG=0

# --- env beats config ---------------------------------------------------------
DCC_ICON_MODE_CFG="nerd"
export DCC_ICONS=unicode
dcc_icons_init
check "the environment outranks config" "$DCC_ICON_MODE" "unicode"
unset DCC_ICONS
DCC_ICON_MODE_CFG="auto"

# --- damaged cache ------------------------------------------------------------
printf 'gibberish\n' > "$cache_dir/icons.detected"
dcc_icons_init
check "an unreadable cache value falls back to unicode" "$DCC_ICON_MODE" "unicode"

printf 'nerd notanumber\n' > "$cache_dir/icons.detected"
dcc_icons_init
check "a non-numeric width falls back to two cells" "$DCC_ICON_W" "2"

: > "$cache_dir/icons.detected"
dcc_icons_init
check "an empty cache falls back to unicode" "$DCC_ICON_MODE" "unicode"

rm -rf "$cache_dir"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/icons.test.sh`
Expected: FAIL — `scripts/lib/icons.sh: No such file or directory`

- [ ] **Step 3: Write minimal implementation**

Create `plugins/dcc-statusline/scripts/lib/icons.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
# Glyph tables and icon mode resolution. Every glyph is written as an octal
# UTF-8 escape so this file stays pure ASCII: the private-use area does not
# survive every editor, pipe and terminal it might pass through.
#
# Nothing here forks. The cache file is read with the read builtin.

DCC_ICON_MODE="unicode"
DCC_ICON_W=0
DCC_I_DIR=""; DCC_I_GIT=""; DCC_I_MODEL=""; DCC_I_FAST=""
DCC_I_ACCOUNT=""; DCC_I_CTX=""; DCC_I_CLOCK=""; DCC_I_COST=""

_dcc_icons_load() {
  printf -v DCC_I_DIR     '\357\201\273'   # U+F07B folder
  printf -v DCC_I_GIT     '\356\202\240'   # U+E0A0 branch
  printf -v DCC_I_MODEL   '\357\213\233'   # U+F2DB chip
  printf -v DCC_I_FAST    '\357\203\247'   # U+F0E7 bolt
  printf -v DCC_I_ACCOUNT '\357\200\207'   # U+F007 user
  printf -v DCC_I_CTX     '\357\207\200'   # U+F1C0 database
  printf -v DCC_I_CLOCK   '\357\200\227'   # U+F017 clock
  printf -v DCC_I_COST    '\357\205\225'   # U+F155 dollar
}

_dcc_icons_clear() {
  DCC_I_DIR=""; DCC_I_GIT=""; DCC_I_MODEL=""; DCC_I_FAST=""
  DCC_I_ACCOUNT=""; DCC_I_CTX=""; DCC_I_CLOCK=""; DCC_I_COST=""
}

dcc_icons_init() { # -> DCC_ICON_MODE, DCC_ICON_W, DCC_I_*
  local mode="" width="" cm cw home

  # Cache first, so config and environment can override it below.
  home="${DCC_STATUSLINE_HOME:-${HOME:-}/.claude/dcc-statusline}"
  if [ -r "$home/icons.detected" ]; then
    read -r cm cw < "$home/icons.detected" || true
    case "${cm:-}" in nerd|unicode) mode="$cm" ;; esac
    case "${cw:-}" in ''|*[!0-9]*) cw="" ;; esac
    [ -n "${cw:-}" ] && width="$cw"
  fi

  case "${DCC_ICON_MODE_CFG:-auto}" in nerd|unicode) mode="$DCC_ICON_MODE_CFG" ;; esac
  [ "${DCC_ICON_W_CFG:-0}" -gt 0 ] 2>/dev/null && width="$DCC_ICON_W_CFG"
  case "${DCC_ICONS:-}" in nerd|unicode) mode="$DCC_ICONS" ;; esac

  [ -n "$mode" ] || mode="unicode"
  DCC_ICON_MODE="$mode"

  if [ "$mode" = "nerd" ]; then
    # Two cells is the safer default: a "Nerd Font" draws icons at natural
    # width, and only the "Mono" variant forces them to one.
    [ -n "$width" ] || width=2
    DCC_ICON_W="$width"
    _dcc_icons_load
  else
    DCC_ICON_W=0
    _dcc_icons_clear
  fi
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/icons.test.sh`
Expected: PASS, 0 failed

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/icons.sh plugins/dcc-statusline/tests/icons.test.sh
git commit -m "feat(statusline): add icon tables and mode resolution"
```

---

### Task 4: Font detection probe

**Files:**
- Create: `plugins/dcc-statusline/scripts/detect-font.sh`
- Create: `plugins/dcc-statusline/tests/detect-font.test.sh`
- Create: `plugins/dcc-statusline/tests/fixtures/wt-nerd.json`, `wt-plain.json`, `wt-mono.json`, `wt-bad.json`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `scripts/detect-font.sh`, executable as `bash detect-font.sh <output-file>`. Writes one line, `<mode> <width>`, where mode is `nerd` or `unicode` and width is `1` or `2`. Honours `DCC_WT_SETTINGS` (path to a Windows Terminal settings file) and `DCC_FONT_LIST` (path to a newline-delimited font-name list) so it is testable without touching the real machine. This file forks freely; it never runs during a render.

- [ ] **Step 1: Write the failing test**

Create the four fixtures:

`tests/fixtures/wt-nerd.json`
```json
{ "profiles": { "defaults": { "font": { "face": "CaskaydiaMono Nerd Font" } } } }
```

`tests/fixtures/wt-plain.json`
```json
{ "profiles": { "defaults": { "font": { "face": "Consolas" } } } }
```

`tests/fixtures/wt-mono.json`
```json
{ "profiles": { "defaults": { "font": { "face": "JetBrainsMono Nerd Font Mono" } } } }
```

`tests/fixtures/wt-bad.json`
```json
{ not json
```

Create `plugins/dcc-statusline/tests/detect-font.test.sh`:

```bash
#!/usr/bin/env bash
# The font probe. Terminal config is authoritative; the installed-font list is
# only consulted when that config cannot be read.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
PROBE="$HERE/../scripts/detect-font.sh"
F="$HERE/fixtures"

out="$(mktemp)"
fonts="$(mktemp)"
printf 'CaskaydiaMono NF\nSegoe UI\n' > "$fonts"
nofonts="$(mktemp)"
printf 'Consolas\nSegoe UI\n' > "$nofonts"

probe() { # probe <wt-settings|""> <font-list|"">
  DCC_WT_SETTINGS="$1" DCC_FONT_LIST="$2" bash "$PROBE" "$out" >/dev/null 2>&1
  cat "$out"
}

check "a nerd terminal face selects nerd at two cells" \
  "$(probe "$F/wt-nerd.json" "$nofonts")" "nerd 2"
check "a mono nerd face selects one cell" \
  "$(probe "$F/wt-mono.json" "$nofonts")" "nerd 1"
check "a plain terminal face selects unicode even when nerd fonts exist" \
  "$(probe "$F/wt-plain.json" "$fonts")" "unicode 1"
check "an unreadable terminal config falls back to the font list" \
  "$(probe "$F/wt-bad.json" "$fonts")" "nerd 2"
check "a missing terminal config falls back to the font list" \
  "$(probe "$F/nonexistent.json" "$fonts")" "nerd 2"
check "no signal anywhere yields unicode" \
  "$(probe "$F/nonexistent.json" "$nofonts")" "unicode 1"

DCC_ICONS=unicode
check "the environment override wins outright" \
  "$(DCC_ICONS=unicode probe "$F/wt-nerd.json" "$fonts")" "unicode 1"
unset DCC_ICONS

# The probe must never leave a half-written file behind on failure.
check "the output file holds exactly one line" "$(wc -l < "$out" | tr -d ' ')" "1"

rm -f "$out" "$fonts" "$nofonts"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/detect-font.test.sh`
Expected: FAIL — every check returns empty, because `detect-font.sh` does not exist

- [ ] **Step 3: Write minimal implementation**

Create `plugins/dcc-statusline/scripts/detect-font.sh`:

```bash
#!/usr/bin/env bash
# Decides whether this machine can render Nerd Font glyphs, and how wide they
# are. Runs at install and after a version change -- never during a render, so
# it may fork as much as it likes.
#
# Writes one line to $1: "<nerd|unicode> <1|2>".
set -uo pipefail

DCC_OUT="${1:-}"
[ -n "$DCC_OUT" ] || { printf 'usage: detect-font.sh <output-file>\n' >&2; exit 2; }

# A face name ending in the Mono variant draws icons at one cell. The match is
# on the suffix and never on a substring: family names such as
# "CaskaydiaMono Nerd Font" carry "Mono" in the family portion while being the
# double-width variant.
_dcc_width_for_face() { # _dcc_width_for_face <face>
  case "$1" in
    *"Nerd Font Mono"|*"NF Mono"|*NFM) printf '1' ;;
    *)                                 printf '2' ;;
  esac
}

_dcc_face_is_nerd() { # _dcc_face_is_nerd <face>
  case "$1" in
    *"Nerd Font"*|*"NF"|*"NFM"|*"NFP"|*Powerline*) return 0 ;;
    *) return 1 ;;
  esac
}

_dcc_wt_face() { # prints the configured Windows Terminal face, or nothing
  local f="${DCC_WT_SETTINGS:-}"
  [ -n "$f" ] || f="${LOCALAPPDATA:-}/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
  [ -r "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -r '[(.profiles.defaults.font.face? // empty)]
         + [((.profiles.list? // [])[]?.font.face? // empty)]
         | map(select(type == "string")) | .[0] // empty' "$f" 2>/dev/null
}

_dcc_font_list() { # prints installed font names, one per line
  if [ -n "${DCC_FONT_LIST:-}" ]; then
    [ -r "$DCC_FONT_LIST" ] && cat "$DCC_FONT_LIST"
    return 0
  fi
  case "$(uname -s 2>/dev/null || printf unknown)" in
    MINGW*|MSYS*|CYGWIN*)
      reg query "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts" 2>/dev/null
      reg query "HKCU\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts" 2>/dev/null
      ;;
    Darwin) ls /Library/Fonts "$HOME/Library/Fonts" 2>/dev/null ;;
    *)      fc-list : family 2>/dev/null ;;
  esac
}

dcc_detect() { # prints "<mode> <width>"
  local face list

  case "${DCC_ICONS:-}" in
    unicode) printf 'unicode 1'; return 0 ;;
    nerd)    printf 'nerd 2';    return 0 ;;
  esac

  # The terminal's own configured face is authoritative when it can be read:
  # it names the font actually rendering. A plain face here is a real negative,
  # not a reason to go looking for an installed Nerd Font that is not in use.
  if face="$(_dcc_wt_face)" && [ -n "$face" ]; then
    if _dcc_face_is_nerd "$face"; then
      printf 'nerd %s' "$(_dcc_width_for_face "$face")"
    else
      printf 'unicode 1'
    fi
    return 0
  fi

  list="$(_dcc_font_list)"
  # Windows registers Nerd Font families under the abbreviated NF, NFM and NFP
  # names -- the registry reports "CaskaydiaMono NF Bold", never the spelled-out
  # form -- so matching only "Nerd Font" would never fire on the one platform
  # this fallback exists to serve.
  if printf '%s' "$list" | grep -qi -E 'nerd ?font|nerdfont|powerline|(^|[[:space:]])NF[MP]?([[:space:]]|$)'; then
    printf 'nerd 2'
  else
    printf 'unicode 1'
  fi
}

# Written through a temporary file so a failure mid-probe cannot leave a
# half-written value that the render path would then read as authoritative.
dcc_tmp="$DCC_OUT.tmp.$$"
{ dcc_detect; printf '\n'; } > "$dcc_tmp" 2>/dev/null || { rm -f "$dcc_tmp"; exit 1; }
mv -f "$dcc_tmp" "$DCC_OUT" 2>/dev/null || { rm -f "$dcc_tmp"; exit 1; }
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/detect-font.test.sh`
Expected: PASS, 0 failed

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/detect-font.sh plugins/dcc-statusline/tests/detect-font.test.sh plugins/dcc-statusline/tests/fixtures/wt-*.json
git commit -m "feat(statusline): add font capability probe"
```

---

### Task 5: Split the meter bar into filled and empty runs

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/render.sh:26-42`
- Test: `plugins/dcc-statusline/tests/render.test.sh:27-34`

**Interfaces:**
- Consumes: `DCC_GLYPH_FILLED`, `DCC_GLYPH_EMPTY`.
- Produces: `dcc_bar <pct> <width>` setting `DCC_BAR_ON` (filled run), `DCC_BAR_OFF` (empty run), `DCC_BAR_ON_N` and `DCC_BAR_OFF_N` (their cell counts). `DCC_BAR` is removed; every caller must migrate.

- [ ] **Step 1: Write the failing test**

Replace lines 27-34 of `plugins/dcc-statusline/tests/render.test.sh` with:

```bash
bar() { dcc_bar "$1" "$2"; printf '%s|%s|%s|%s' "$DCC_BAR_ON" "$DCC_BAR_OFF" "$DCC_BAR_ON_N" "$DCC_BAR_OFF_N"; }
check "0% fills nothing"                 "$(bar 0 10)"   "|..........|0|10"
check "1% still fills one cell"          "$(bar 1 10)"   "#|.........|1|9"
check "47% rounds to five cells"         "$(bar 47 10)"  "#####|.....|5|5"
check "99% still leaves one empty cell"  "$(bar 99 10)"  "#########|.|9|1"
check "100% fills every cell"            "$(bar 100 10)" "##########||10|0"
check "width is honored"                 "$(bar 50 8)"   "####|....|4|4"
check "zero width yields no bar"         "$(bar 50 0)"   "||0|0"
check "empty percentage yields no bar"   "$(bar '' 10)"  "||0|0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/render.test.sh`
Expected: FAIL with `DCC_BAR_ON: unbound variable`

- [ ] **Step 3: Write minimal implementation**

Replace `dcc_bar` in `scripts/lib/render.sh`:

```bash
DCC_BAR_ON=""; DCC_BAR_OFF=""; DCC_BAR_ON_N=0; DCC_BAR_OFF_N=0

dcc_bar() { # dcc_bar <pct> <width> -> DCC_BAR_ON/OFF and their cell counts
  local pct="${1:-}" width="${2:-0}" filled i
  DCC_BAR_ON=""; DCC_BAR_OFF=""; DCC_BAR_ON_N=0; DCC_BAR_OFF_N=0
  [ -n "$pct" ] || return 0
  [ "$width" -gt 0 ] 2>/dev/null || return 0
  filled=$(( (pct * width + 50) / 100 ))
  # Clamp both ends so a non-zero reading never looks empty and an incomplete
  # one never looks full.
  [ "$filled" -lt 1 ] && [ "$pct" -gt 0 ] && filled=1
  [ "$filled" -ge "$width" ] && [ "$pct" -lt 100 ] && filled=$(( width - 1 ))
  [ "$filled" -lt 0 ] && filled=0
  [ "$filled" -gt "$width" ] && filled="$width"
  for (( i = 0; i < filled; i++ )); do DCC_BAR_ON="$DCC_BAR_ON$DCC_GLYPH_FILLED"; done
  for (( i = filled; i < width; i++ )); do DCC_BAR_OFF="$DCC_BAR_OFF$DCC_GLYPH_EMPTY"; done
  DCC_BAR_ON_N="$filled"
  DCC_BAR_OFF_N=$(( width - filled ))
}
```

Delete the `DCC_BAR=""` declaration at the top of the file.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/render.test.sh`
Expected: PASS, 0 failed. The joining block at lines 44-68 still exercises
`dcc_join_add`, which this task does not touch.

`segments.test.sh` goes red here, because `_dcc_meter` still reads the removed
`DCC_BAR`. Task 7 repairs it. Do not run `run-all.sh` between Tasks 5 and 9.

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/render.sh plugins/dcc-statusline/tests/render.test.sh
git commit -m "feat(statusline): split meter bar into two runs"
```

---

### Task 6: Cell-counting segment accumulator

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/render.sh:56-75` (replaces the join API)
- Test: `plugins/dcc-statusline/tests/render.test.sh:44-68`

**Interfaces:**
- Consumes: `dcc_paint` from Task 1, `DCC_SEP`.
- Produces:
  - `dcc_seg_reset` — clears `DCC_SEG_OUT` and `DCC_SEG_CELLS`.
  - `dcc_seg_add <text> <color> [weight] [cells]` — appends painted text; `cells` defaults to `${#text}` and must be passed explicitly for any non-ASCII text.
  - `dcc_line_reset` — clears the collected segment list.
  - `dcc_line_push` — moves the current segment onto the list and resets it; a segment with empty output is discarded.
  - `dcc_line_build [max-cells]` — sets `DCC_LINE_OUT`, `DCC_LINE_CELLS` and `DCC_LINE_DROPPED`. With `max-cells` empty or `0` nothing is dropped.
  - `DCC_SEP_CELLS` — cell width of the separator, set by `dcc_sep_cells <n>`.

- [ ] **Step 1: Write the failing test**

Replace lines 44-68 of `plugins/dcc-statusline/tests/render.test.sh` with:

```bash
# --- segment accumulation and line building -----------------------------------
dcc_sep_cells 3     # " | "

seg() { # seg <text> <color> [weight] [cells]
  dcc_seg_add "$1" "$2" "${3:-}" "${4:-}"; dcc_line_push
}

dcc_line_reset; seg one green; seg two green; dcc_line_build
check "segments are joined with the separator" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "one | two"
check "the built line reports its cell width" "$DCC_LINE_CELLS" "9"

dcc_line_reset; seg one green; seg "" green; seg three green; dcc_line_build
check "an empty segment leaves no doubled separator" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "one | three"

dcc_line_reset; seg "" green; dcc_line_build
check "an all-empty line renders as nothing" "$DCC_LINE_OUT" ""
check "an all-empty line measures zero"      "$DCC_LINE_CELLS" "0"

# A segment carrying multiple weights is one unit to the joiner.
dcc_line_reset
dcc_seg_add "main" magenta bold
dcc_seg_add "*"    magenta dim
dcc_line_push
dcc_line_build
check "one segment may mix weights" "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "main*"
check "mixed weights sum their cells" "$DCC_LINE_CELLS" "5"

# An explicit cell count overrides the character count, which is how a
# double-width icon is accounted for.
dcc_line_reset
dcc_seg_add "X" cyan "" 2
dcc_line_push
dcc_line_build
check "an explicit cell count wins" "$DCC_LINE_CELLS" "2"

# --- overflow -----------------------------------------------------------------
dcc_line_reset; seg aaaa green; seg bbbb green; seg cccc green
dcc_line_build 12
check "an over-long line drops the segments that do not fit" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "aaaa | bbbb"
check "the drop count is reported" "$DCC_LINE_DROPPED" "1"
check "the surviving line fits the budget" "$DCC_LINE_CELLS" "11"

dcc_line_reset; seg aaaa green; seg bbbb green
dcc_line_build 0
check "a zero budget means unlimited" \
  "$(printf '%s' "$DCC_LINE_OUT" | strip_ansi)" "aaaa | bbbb"

dcc_line_reset; seg aaaaaaaaaaaaaaaa green
dcc_line_build 4
check "a single over-long segment yields an empty line" "$DCC_LINE_OUT" ""

# --- colouring ----------------------------------------------------------------
dcc_line_reset; seg tinted magenta; dcc_line_build
check "a segment takes the colour it was given" "$DCC_LINE_OUT" $'\033[38;5;13mtinted\033[0m'

DCC_P_MUTE="gray"
dcc_line_reset; seg one green; seg two green; dcc_line_build
sepcolor="no"; printf '%s' "$DCC_LINE_OUT" | grep -q $'\033\\[2;38;5;245m' && sepcolor="yes"
check "the separator renders dim and muted" "$sepcolor" "yes"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/render.test.sh`
Expected: FAIL — `dcc_sep_cells: command not found`

- [ ] **Step 3: Write minimal implementation**

Replace the join block at the end of `scripts/lib/render.sh`:

```bash
DCC_SEG_OUT=""
DCC_SEG_CELLS=0
DCC_SEP_CELLS=5
DCC_LINE_OUT=""
DCC_LINE_CELLS=0
DCC_LINE_DROPPED=0
declare -a DCC_SEGS=() DCC_SEGW=()

dcc_sep_cells() { DCC_SEP_CELLS="${1:-0}"; }

dcc_seg_reset() { DCC_SEG_OUT=""; DCC_SEG_CELLS=0; }

dcc_seg_add() { # dcc_seg_add <text> <color> [weight] [cells]
  local text="${1:-}" color="${2:-}" weight="${3:-}" cells="${4:-}"
  [ -n "$text" ] || return 0
  # Character count is only correct for ASCII. Anything else -- an icon, a bar
  # cell, a box glyph -- must state its width, because a double-width icon
  # counts as one character and two cells.
  [ -n "$cells" ] || cells=${#text}
  dcc_paint "$text" "$color" "$weight"
  DCC_SEG_OUT="$DCC_SEG_OUT$DCC_PAINTED"
  DCC_SEG_CELLS=$(( DCC_SEG_CELLS + cells ))
}

dcc_line_reset() { DCC_SEGS=(); DCC_SEGW=(); dcc_seg_reset; }

dcc_line_push() {
  if [ -n "$DCC_SEG_OUT" ]; then
    DCC_SEGS+=("$DCC_SEG_OUT")
    DCC_SEGW+=("$DCC_SEG_CELLS")
  fi
  dcc_seg_reset
}

dcc_line_build() { # dcc_line_build [max-cells] -> DCC_LINE_OUT, _CELLS, _DROPPED
  local max="${1:-0}" i add used=0 sep
  DCC_LINE_OUT=""; DCC_LINE_CELLS=0; DCC_LINE_DROPPED=0
  [ "${#DCC_SEGS[@]}" -gt 0 ] || return 0
  dcc_paint "$DCC_SEP" "${DCC_P_MUTE:-gray}" dim
  sep="$DCC_PAINTED"
  for i in "${!DCC_SEGS[@]}"; do
    add=${DCC_SEGW[$i]}
    [ -n "$DCC_LINE_OUT" ] && add=$(( add + DCC_SEP_CELLS ))
    # Whole segments are dropped rather than any string being cut: a cut could
    # sever an escape sequence and bleed colour across the rest of the row.
    #
    # The scan is greedy, not trailing-only: a segment too wide to fit is
    # skipped and the scan continues, so a later smaller segment can survive an
    # earlier larger one. That is deliberate -- one oversized branch name should
    # not also cost the model and mode flags that would have fitted beside it.
    if [ "$max" -gt 0 ] && [ $(( used + add )) -gt "$max" ]; then
      DCC_LINE_DROPPED=$(( DCC_LINE_DROPPED + 1 ))
      continue
    fi
    [ -n "$DCC_LINE_OUT" ] && DCC_LINE_OUT="$DCC_LINE_OUT$sep"
    DCC_LINE_OUT="$DCC_LINE_OUT${DCC_SEGS[$i]}"
    used=$(( used + add ))
  done
  DCC_LINE_CELLS="$used"
}
```

Delete `dcc_join_reset` and `dcc_join_add`, and the `DCC_JOINED` and
`DCC_JOIN_EMPTY` declarations.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/render.test.sh`
Expected: PASS, 0 failed

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/render.sh plugins/dcc-statusline/tests/render.test.sh
git commit -m "feat(statusline): track cell width while joining"
```

---

### Task 7: Self-painting segments

**Files:**
- Modify: `plugins/dcc-statusline/scripts/lib/segments.sh` (whole file)
- Test: `plugins/dcc-statusline/tests/segments.test.sh` (whole file)

**Interfaces:**
- Consumes: `dcc_seg_add`, `dcc_seg_reset` from Task 6; `dcc_bar` from Task 5; `DCC_I_*` and `DCC_ICON_W` from Task 3; palette globals from Task 2.
- Produces: `dcc_segment <name>` which paints into `DCC_SEG_OUT` and `DCC_SEG_CELLS` and returns 0 always. `DCC_SEG_SPEC` and `DCC_SEG_TEXT` are removed. The `think` case is removed.

- [ ] **Step 1: Write the failing test**

Rewrite the helper and assertions in `plugins/dcc-statusline/tests/segments.test.sh`.
Replace the existing `seg()` helper with:

```bash
seg() { # seg <name> -> the visible text of that segment
  dcc_seg_reset
  dcc_segment "$1"
  printf '%s' "$DCC_SEG_OUT" | strip_ansi
}
segcells() { dcc_seg_reset; dcc_segment "$1"; printf '%s' "$DCC_SEG_CELLS"; }
```

Add near the top, after the other globals the file already sets:

```bash
DCC_ICON_MODE="unicode"; DCC_ICON_W=0
DCC_I_DIR=""; DCC_I_GIT=""; DCC_I_MODEL=""; DCC_I_FAST=""
DCC_I_ACCOUNT=""; DCC_I_CTX=""; DCC_I_CLOCK=""; DCC_I_COST=""
DCC_P_DIR="blue"; DCC_P_GIT="magenta"; DCC_P_MODEL="cyan"
DCC_P_EFFORT="gray"; DCC_P_FAST="white"; DCC_P_COST="141"; DCC_P_MUTE="gray"
```

Delete the two `think` assertions at lines 97-98 and add:

```bash
check "the think segment no longer exists" "$(seg think)" ""
```

Update the meter assertions to the bracket-free form:

```bash
check "context meter: bar, percentage, tokens" "$(seg ctx)" "ctx #####..... 47% · 94k"
check "sub-1k token counts are shown raw"      "$(seg ctx)" "ctx #####..... 47% · 800"
check "tokens can be turned off"               "$(seg ctx)" "ctx #####..... 47%"
check "5h meter with countdown"                "$(seg 5h)"  "5h ##...... 23% · 3h40m"
check "the countdown can be turned off"        "$(seg 5h)"  "5h ##...... 23%"
check "7d meter with a multi-day countdown"    "$(seg 7d)"  "7d ###..... 41% · 5d22h"
```

Replace the two `DCC_SEG_SPEC` ramp assertions with raw-output colour checks:

```bash
P_CTX_PCT=47; dcc_seg_reset; dcc_segment ctx
ramped="no"; printf '%s' "$DCC_SEG_OUT" | grep -q $'\033\\[38;5;10m' && ramped="yes"
check "a low meter paints its bar green" "$ramped" "yes"

P_5H_PCT=95; dcc_seg_reset; dcc_segment 5h
ramped="no"; printf '%s' "$DCC_SEG_OUT" | grep -q $'\033\\[1;38;5;9m' && ramped="yes"
check "a meter above 90% turns red and bold" "$ramped" "yes"
```

Add a weight and icon-accounting block before `finish`:

```bash
# --- weights ------------------------------------------------------------------
P_CWD="/repo/claude-code-plugins/plugins"; DCC_GIT_ROOT="/repo/claude-code-plugins"
dcc_seg_reset; dcc_segment dir
dimmed="no"; printf '%s' "$DCC_SEG_OUT" | grep -q $'\033\\[2;38;5;12m' && dimmed="yes"
bolded="no"; printf '%s' "$DCC_SEG_OUT" | grep -q $'\033\\[1;38;5;12m' && bolded="yes"
check "the parent path renders dim"  "$dimmed" "yes"
check "the leaf directory renders bold" "$bolded" "yes"

# --- icon cell accounting -----------------------------------------------------
check "unicode mode charges no cells for an icon" "$(segcells model)" "4"
DCC_ICON_MODE="nerd"; DCC_ICON_W=2
printf -v DCC_I_MODEL '\357\213\233'
check "a double-width icon charges three cells with its space" "$(segcells model)" "7"
DCC_ICON_W=1
check "a single-width icon charges two cells with its space" "$(segcells model)" "6"
DCC_ICON_MODE="unicode"; DCC_I_MODEL=""
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/segments.test.sh`
Expected: FAIL — `DCC_SEG_OUT: unbound variable`, and every meter assertion fails

- [ ] **Step 3: Write minimal implementation**

Replace `plugins/dcc-statusline/scripts/lib/segments.sh` entirely:

```bash
#!/usr/bin/env bash
set -uo pipefail
# One function per segment, dispatched by name. Each paints into DCC_SEG_OUT via
# dcc_seg_add and leaves DCC_SEG_CELLS holding its display width. Returning an
# empty accumulator rather than failing is what makes a missing block degrade to
# a shorter line instead of a broken one.
#
# Colour here means "what kind of thing is this". Account identity is carried by
# the frame, not by the text.

_dcc_icon() { # _dcc_icon <glyph> <color> -- emits the glyph and its trailing space
  [ "$DCC_ICON_MODE" = "nerd" ] || return 0
  [ -n "$1" ] || return 0
  dcc_seg_add "$1" "$2" "" "$DCC_ICON_W"
  dcc_seg_add " " "$2" "" 1
}

_dcc_meter() { # _dcc_meter <icon> <label> <pct> <width> <reset-epoch> <tokens|"">
  local icon="$1" label="$2" pct="$3" width="$4" reset="$5" tokens="$6" suffix=""
  [ -n "$pct" ] || return 0
  dcc_ramp "$pct"
  dcc_bar "$pct" "$width"
  _dcc_icon "$icon" "$DCC_P_MUTE"
  dcc_seg_add "$label " "$DCC_P_MUTE"
  dcc_seg_add "$DCC_BAR_ON"  "$DCC_RAMP_COLOR" ""    "$DCC_BAR_ON_N"
  dcc_seg_add "$DCC_BAR_OFF" "$DCC_P_MUTE"     dim   "$DCC_BAR_OFF_N"
  dcc_seg_add " " "$DCC_P_MUTE"
  # The percentage is always bold: it is the reading, and the ramp's own bold
  # stop above 90% would otherwise be the only thing that ever emphasised it.
  dcc_seg_add "${pct}%" "$DCC_RAMP_COLOR" bold
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

dcc_segment() { # dcc_segment <name> -> DCC_SEG_OUT, DCC_SEG_CELLS
  local name="${1:-}" cwd root home leaf parent
  case "$name" in
    dir)
      # Claude Code reports the working directory in Windows form while the git
      # root and $HOME arrive in the MSYS form, so both sides of every
      # comparison below are folded into one namespace first (see lib/path.sh).
      dcc_path_norm "$P_CWD";        cwd="$DCC_PATH"
      dcc_path_norm "$DCC_GIT_ROOT"; root="$DCC_PATH"
      dcc_path_norm "${HOME:-}";     home="$DCC_PATH"
      if [ -n "$root" ]; then
        case "$cwd" in
          "$root")   cwd="${root##*/}" ;;
          "$root"/*) cwd="${root##*/}${cwd#"$root"}" ;;
        esac
      elif [ -n "$home" ]; then
        # Guarded: an empty $home would turn the "$home"/* pattern into a bare
        # /*, which matches every absolute path.
        case "$cwd" in
          "$home")   cwd="~" ;;
          "$home"/*) cwd="~${cwd#"$home"}" ;;
        esac
      fi
      [ -n "$cwd" ] || return 0
      _dcc_icon "$DCC_I_DIR" "$DCC_P_DIR"
      leaf="${cwd##*/}"
      if [ "$leaf" = "$cwd" ]; then
        dcc_seg_add "$cwd" "$DCC_P_DIR" bold
      else
        parent="${cwd%/*}/"
        dcc_seg_add "$parent" "$DCC_P_DIR" dim
        dcc_seg_add "$leaf"   "$DCC_P_DIR" bold
      fi
      ;;
    git)
      [ -n "$DCC_GIT_BRANCH" ] || return 0
      _dcc_icon "$DCC_I_GIT" "$DCC_P_GIT"
      dcc_seg_add "$DCC_GIT_BRANCH" "$DCC_P_GIT" bold
      [ "$DCC_GIT_DIRTY" -eq 1 ] && dcc_seg_add "$DCC_GLYPH_DIRTY" "$DCC_P_GIT" dim
      [ "$DCC_GIT_AHEAD"  -gt 0 ] && dcc_seg_add " $DCC_ARROW_UP$DCC_GIT_AHEAD" "$DCC_P_GIT" dim $(( 2 + ${#DCC_GIT_AHEAD} ))
      [ "$DCC_GIT_BEHIND" -gt 0 ] && dcc_seg_add "$DCC_ARROW_DOWN$DCC_GIT_BEHIND" "$DCC_P_GIT" dim $(( 1 + ${#DCC_GIT_BEHIND} ))
      [ "$DCC_GIT_STAGED"    -gt 0 ] && dcc_seg_add " $DCC_DOT_FILLED$DCC_GIT_STAGED" "$DCC_P_GIT" dim $(( 2 + ${#DCC_GIT_STAGED} ))
      [ "$DCC_GIT_UNSTAGED"  -gt 0 ] && dcc_seg_add " $DCC_DOT_HOLLOW$DCC_GIT_UNSTAGED" "$DCC_P_GIT" dim $(( 2 + ${#DCC_GIT_UNSTAGED} ))
      [ "$DCC_GIT_UNTRACKED" -gt 0 ] && dcc_seg_add " ?$DCC_GIT_UNTRACKED" "$DCC_P_GIT" dim
      ;;
    model)
      [ -n "$P_MODEL" ] || return 0
      _dcc_icon "$DCC_I_MODEL" "$DCC_P_MODEL"
      dcc_seg_add "$P_MODEL" "$DCC_P_MODEL" bold
      ;;
    effort)  dcc_seg_add "$P_EFFORT" "$DCC_P_EFFORT" ;;
    fast)
      [ "$P_FAST" -eq 1 ] || return 0
      if [ "$DCC_ICON_MODE" = "nerd" ] && [ -n "$DCC_I_FAST" ]; then
        dcc_seg_add "$DCC_I_FAST" "$DCC_P_FAST" "" "$DCC_ICON_W"
      else
        dcc_seg_add "fast" "$DCC_P_FAST"
      fi
      ;;
    agent)   dcc_seg_add "$P_AGENT" "$DCC_P_MUTE" ;;
    style)   dcc_seg_add "$P_STYLE" "$DCC_P_MUTE" ;;
    account)
      [ -n "$P_EMAIL" ] || return 0
      _dcc_icon "$DCC_I_ACCOUNT" "$DCC_P_MUTE"
      dcc_seg_add "$P_EMAIL" "$DCC_P_MUTE" dim
      ;;
    cost)
      [ -n "$P_COST" ] || return 0
      local money
      printf -v money '%.2f' "$P_COST" 2>/dev/null || return 0
      if [ "$DCC_ICON_MODE" = "nerd" ] && [ -n "$DCC_I_COST" ]; then
        _dcc_icon "$DCC_I_COST" "$DCC_P_COST"
        dcc_seg_add "$money" "$DCC_P_COST" bold
      else
        dcc_seg_add "\$$money" "$DCC_P_COST" bold
      fi
      ;;
    ctx) _dcc_meter "$DCC_I_CTX"   "ctx" "$P_CTX_PCT" "$DCC_W_CTX" "" "$P_CTX_TOK" ;;
    5h)  _dcc_meter "$DCC_I_CLOCK" "5h"  "$P_5H_PCT"  "$DCC_W_5H"  "$P_5H_RESET" "" ;;
    7d)  _dcc_meter "$DCC_I_CLOCK" "7d"  "$P_7D_PCT"  "$DCC_W_7D"  "$P_7D_RESET" "" ;;
  esac
  return 0
}
```

Add the non-ASCII text constants near the top of `scripts/lib/render.sh`, so
both segments and the frame can use them:

```bash
printf -v DCC_SEP_DOT    '\302\267'        # U+00B7 middle dot
printf -v DCC_ARROW_UP   '\342\206\221'    # U+2191
printf -v DCC_ARROW_DOWN '\342\206\223'    # U+2193
printf -v DCC_DOT_FILLED '\342\227\217'    # U+25CF
printf -v DCC_DOT_HOLLOW '\342\227\213'    # U+25CB
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/segments.test.sh`
Expected: PASS, 0 failed

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/segments.sh plugins/dcc-statusline/scripts/lib/render.sh plugins/dcc-statusline/tests/segments.test.sh
git commit -m "feat(statusline): paint segments with semantic colour"
```

---

### Task 8: The frame

**Files:**
- Create: `plugins/dcc-statusline/scripts/lib/frame.sh`
- Create: `plugins/dcc-statusline/tests/frame.test.sh`

**Interfaces:**
- Consumes: `dcc_paint` from Task 1, `DCC_LINE_OUT`/`DCC_LINE_CELLS` from Task 6.
- Produces:
  - `dcc_frame_init` — sets `DCC_FRAME_ON` (`1`/`0`) and `DCC_FRAME_COLS` from `DCC_FRAME_MODE` and `COLUMNS`.
  - `dcc_frame_budget` — sets `DCC_FRAME_BUDGET`, the cells available to a content line.
  - `dcc_frame_top <title> <icon> <icon-cells>` — sets `DCC_FRAME_OUT`.
  - `dcc_frame_row <built-line> <cells>` — sets `DCC_FRAME_OUT`.
  - `dcc_frame_bottom` — sets `DCC_FRAME_OUT`.
  - `dcc_cells <string>` in `tests/lib.sh` — measures a rendered row in cells by stripping SGR sequences and counting private-use characters as `DCC_ICON_W`. It lives with the test helpers, not in `frame.sh`: the render path sources `frame.sh` on every render and must not carry a function only tests call.

- [ ] **Step 1: Add the measuring helper to the shared test library**

Append to `plugins/dcc-statusline/tests/lib.sh`:

```bash
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
```

- [ ] **Step 2: Write the failing test**

Create `plugins/dcc-statusline/tests/frame.test.sh`:

```bash
#!/usr/bin/env bash
# The frame. Every drawn row must measure exactly COLUMNS cells; if it does not,
# the right wall is ragged and the whole box looks broken.
set -uo pipefail
export LC_ALL=C.UTF-8
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/lib/color.sh"
source "$HERE/../scripts/lib/render.sh"
source "$HERE/../scripts/lib/frame.sh"

DCC_ACCOUNT_COLOR="cyan"
DCC_P_MUTE="gray"
DCC_SEP=" | "
dcc_sep_cells 3

# --- enablement ---------------------------------------------------------------
DCC_FRAME_MODE="auto"; COLUMNS=100; dcc_frame_init
check "auto with a usable width draws the box" "$DCC_FRAME_ON" "1"
check "auto adopts the reported width"         "$DCC_FRAME_COLS" "100"

COLUMNS=""; dcc_frame_init
check "auto without COLUMNS falls back" "$DCC_FRAME_ON" "0"

COLUMNS="wide"; dcc_frame_init
check "auto with a non-numeric COLUMNS falls back" "$DCC_FRAME_ON" "0"

COLUMNS=40; dcc_frame_init
check "auto below the minimum falls back" "$DCC_FRAME_ON" "0"

COLUMNS=48; dcc_frame_init
check "auto at the minimum draws the box" "$DCC_FRAME_ON" "1"

DCC_FRAME_MODE="none"; COLUMNS=100; dcc_frame_init
check "none never draws the box" "$DCC_FRAME_ON" "0"

DCC_FRAME_MODE="box"; COLUMNS=""; dcc_frame_init
check "box without a width still cannot draw" "$DCC_FRAME_ON" "0"

# --- row widths ---------------------------------------------------------------
DCC_FRAME_MODE="auto"

for cols in 48 60 72 90 110 150; do
  for iw in 1 2; do
    COLUMNS="$cols"; DCC_ICON_W="$iw"; dcc_frame_init; dcc_frame_budget

    printf -v icon '\357\200\207'
    dcc_frame_top "someone@example.com" "$icon" "$iw"
    dcc_cells "$DCC_FRAME_OUT"
    check "top rule is $cols cells at icon width $iw" "$DCC_CELLS" "$cols"

    dcc_line_reset
    dcc_seg_add "alpha" cyan; dcc_line_push
    dcc_seg_add "beta"  cyan; dcc_line_push
    dcc_line_build "$DCC_FRAME_BUDGET"
    dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
    dcc_cells "$DCC_FRAME_OUT"
    check "content row is $cols cells at icon width $iw" "$DCC_CELLS" "$cols"

    dcc_frame_bottom
    dcc_cells "$DCC_FRAME_OUT"
    check "bottom rule is $cols cells at icon width $iw" "$DCC_CELLS" "$cols"
  done
done

# --- a full line still fits ---------------------------------------------------
COLUMNS=60; DCC_ICON_W=2; dcc_frame_init; dcc_frame_budget
dcc_line_reset
for n in 1 2 3 4 5 6 7 8; do dcc_seg_add "seg$n" cyan; dcc_line_push; done
dcc_line_build "$DCC_FRAME_BUDGET"
dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
dcc_cells "$DCC_FRAME_OUT"
check "an overflowing line still yields a 60-cell row" "$DCC_CELLS" "60"
check "and something was dropped to achieve it" \
  "$([ "$DCC_LINE_DROPPED" -gt 0 ] && printf yes || printf no)" "yes"

# --- a title longer than the terminal -----------------------------------------
COLUMNS=48; DCC_ICON_W=0; dcc_frame_init
printf -v icon '\357\200\207'
dcc_frame_top "an-extremely-long-account-address@somewhere.example.com" "" 0
dcc_cells "$DCC_FRAME_OUT"
check "an over-long title still yields a 48-cell rule" "$DCC_CELLS" "48"

finish
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/frame.test.sh`
Expected: FAIL — `scripts/lib/frame.sh: No such file or directory`

- [ ] **Step 4: Write minimal implementation**

Create `plugins/dcc-statusline/scripts/lib/frame.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
# Box drawing. Every row this file produces must be exactly DCC_FRAME_COLS cells
# wide; a miscount by one leaves a ragged right wall down the whole box.
#
# tput cannot help here: Claude Code captures the script's output rather than
# attaching it to a terminal, so the width arrives in COLUMNS instead.

DCC_FRAME_MIN=48

printf -v DCC_BOX_TL '\342\225\255'   # U+256D
printf -v DCC_BOX_TR '\342\225\256'   # U+256E
printf -v DCC_BOX_BL '\342\225\260'   # U+2570
printf -v DCC_BOX_BR '\342\225\257'   # U+256F
printf -v DCC_BOX_H  '\342\224\200'   # U+2500
printf -v DCC_BOX_V  '\342\224\202'   # U+2502

DCC_FRAME_ON=0
DCC_FRAME_COLS=0
DCC_FRAME_BUDGET=0
DCC_FRAME_OUT=""
DCC_CELLS=0

dcc_frame_init() { # -> DCC_FRAME_ON, DCC_FRAME_COLS
  local cols="${COLUMNS:-}"
  DCC_FRAME_ON=0; DCC_FRAME_COLS=0
  [ "${DCC_FRAME_MODE:-auto}" = "none" ] && return 0
  case "$cols" in ''|*[!0-9]*) return 0 ;; esac
  [ "$cols" -ge "$DCC_FRAME_MIN" ] || return 0
  DCC_FRAME_COLS="$cols"
  DCC_FRAME_ON=1
}

dcc_frame_budget() { # -> DCC_FRAME_BUDGET, the cells a content line may use
  if [ "$DCC_FRAME_ON" -eq 1 ]; then
    DCC_FRAME_BUDGET=$(( DCC_FRAME_COLS - 4 ))
  else
    DCC_FRAME_BUDGET=0
  fi
}

_dcc_rep() { # _dcc_rep <count> <char> -> DCC_REP
  local n="${1:-0}" ch="$2" i
  DCC_REP=""
  [ "$n" -gt 0 ] 2>/dev/null || return 0
  for (( i = 0; i < n; i++ )); do DCC_REP="$DCC_REP$ch"; done
}

dcc_frame_top() { # dcc_frame_top <title> <icon> <icon-cells> -> DCC_FRAME_OUT
  local title="${1:-}" icon="${2:-}" iw="${3:-0}" used rule
  local tint="${DCC_ACCOUNT_COLOR:-}"
  DCC_FRAME_OUT=""
  # corner + rule + space + [icon + space] + title + space + rule(n) + corner
  used=$(( 5 + ${#title} ))
  [ -n "$icon" ] && used=$(( used + iw + 1 ))
  rule=$(( DCC_FRAME_COLS - used ))
  # A title wider than the terminal would make the rule negative, so it is
  # truncated rather than allowed to push the corner off the row.
  if [ "$rule" -lt 0 ]; then
    title="${title:0:$(( ${#title} + rule ))}"
    used=$(( 5 + ${#title} ))
    [ -n "$icon" ] && used=$(( used + iw + 1 ))
    rule=$(( DCC_FRAME_COLS - used ))
    [ "$rule" -lt 0 ] && rule=0
  fi
  dcc_paint "$DCC_BOX_TL$DCC_BOX_H " "$tint"
  DCC_FRAME_OUT="$DCC_PAINTED"
  if [ -n "$icon" ]; then
    dcc_paint "$icon " "$tint"
    DCC_FRAME_OUT="$DCC_FRAME_OUT$DCC_PAINTED"
  fi
  dcc_paint "$title" "$tint" bold
  DCC_FRAME_OUT="$DCC_FRAME_OUT$DCC_PAINTED"
  _dcc_rep "$rule" "$DCC_BOX_H"
  dcc_paint " $DCC_REP$DCC_BOX_TR" "$tint"
  DCC_FRAME_OUT="$DCC_FRAME_OUT$DCC_PAINTED"
}

dcc_frame_row() { # dcc_frame_row <built-line> <cells> -> DCC_FRAME_OUT
  local body="${1:-}" cells="${2:-0}" pad
  local tint="${DCC_ACCOUNT_COLOR:-}"
  pad=$(( DCC_FRAME_COLS - 4 - cells ))
  [ "$pad" -lt 0 ] && pad=0
  _dcc_rep "$pad" " "
  dcc_paint "$DCC_BOX_V " "$tint"
  DCC_FRAME_OUT="$DCC_PAINTED$body"
  dcc_paint " $DCC_BOX_V" "$tint"
  DCC_FRAME_OUT="$DCC_FRAME_OUT$DCC_REP$DCC_PAINTED"
}

dcc_frame_bottom() { # -> DCC_FRAME_OUT
  local tint="${DCC_ACCOUNT_COLOR:-}"
  _dcc_rep $(( DCC_FRAME_COLS - 2 )) "$DCC_BOX_H"
  dcc_paint "$DCC_BOX_BL$DCC_REP$DCC_BOX_BR" "$tint"
  DCC_FRAME_OUT="$DCC_PAINTED"
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/frame.test.sh`
Expected: PASS, 0 failed

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-statusline/scripts/lib/frame.sh plugins/dcc-statusline/tests/frame.test.sh plugins/dcc-statusline/tests/lib.sh
git commit -m "feat(statusline): add box frame with width accounting"
```

---

### Task 9: Wire the entry point

**Files:**
- Modify: `plugins/dcc-statusline/scripts/statusline.sh` (whole file)
- Test: `plugins/dcc-statusline/tests/e2e.test.sh:28-31` and additions

**Interfaces:**
- Consumes: every function from Tasks 1-8.
- Produces: the finished output. Framed mode prints four rows; unframed mode prints the two rows it always did.

- [ ] **Step 1: Write the failing test**

In `plugins/dcc-statusline/tests/e2e.test.sh`, add below the existing exports:

```bash
export DCC_ICONS=unicode
export COLUMNS=""
# dcc_cells slices characters, which needs a UTF-8 locale in the test shell too;
# the script sets its own, but that does not reach this process.
export LC_ALL=C.UTF-8
```

Replace the two assertions at lines 28-31 with:

```bash
check "line one carries model and state chips" \
  "$(printf '%s' "$line1" | grep -c 'Opus  ·  xhigh  ·  fast')" "1"
check "line one no longer carries a think chip" \
  "$(printf '%s' "$line1" | grep -c 'think')" "0"
check "line two carries all three meters" \
  "$(printf '%s' "$line2" | grep -c 'ctx .* 47% · 94k  ·  \$1.20  ·  5h .* 23% · 3h40m  ·  7d .* 41% · 5d22h')" "1"
```

Add a framed block before `finish`:

```bash
# --- framed mode --------------------------------------------------------------
out="$(COLUMNS=100 bash "$SCRIPT" < "$F/full.json")"
check "a framed render prints four rows" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "4"

DCC_ICON_W=0
rowno=0
while IFS= read -r row; do
  rowno=$(( rowno + 1 ))
  dcc_cells "$row"
  check "framed row $rowno measures 100 cells" "$DCC_CELLS" "100"
done < <(printf '%s\n' "$out")

check "the account address is on the top rule" \
  "$(printf '%s\n' "$out" | sed -n 1p | strip_ansi | grep -c 'someone@example.com')" "1"
check "the account address is not repeated inside" \
  "$(printf '%s\n' "$out" | sed -n 2p | strip_ansi | grep -c 'someone@example.com')" "0"

# Too narrow to frame: falls back to the plain two-line layout.
out="$(COLUMNS=30 bash "$SCRIPT" < "$F/full.json")"
check "a narrow terminal falls back to two rows" \
  "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"

# Explicitly disabled.
cfgnf="$(mktemp)"; printf '{ "frame": "none" }' > "$cfgnf"
out="$(COLUMNS=100 DCC_STATUSLINE_CONFIG="$cfgnf" bash "$SCRIPT" < "$F/full.json")"
check "frame none renders two rows" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"
rm -f "$cfgnf"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/e2e.test.sh`
Expected: FAIL — the render still emits two rows and `dcc_join_reset: command not found`

- [ ] **Step 3: Write minimal implementation**

Replace `plugins/dcc-statusline/scripts/statusline.sh`:

```bash
#!/usr/bin/env bash
# Claude Code status line. Reads the session payload on stdin, prints two lines,
# or four when the frame is enabled.
#
# Process budget: one jq, two git, and the timeout wrappers around them. Nothing
# in this file may use $(...) -- see the note in lib/color.sh.
set -uo pipefail

# Without a UTF-8 locale bash measures and slices bytes, so a three-byte box
# glyph counts as three cells and the frame's right wall lands in the wrong
# place. Every width calculation downstream depends on this line.
export LC_ALL=C.UTF-8

# Resolve our own directory by parameter expansion only. $(cd ... && pwd) would
# cost two forks on every render, which the process budget does not allow.
DCC_DIR="${BASH_SOURCE[0]%/*}"
[ "$DCC_DIR" = "${BASH_SOURCE[0]}" ] && DCC_DIR="."

source "$DCC_DIR/lib/path.sh"
source "$DCC_DIR/lib/color.sh"
source "$DCC_DIR/lib/config.sh"
source "$DCC_DIR/lib/icons.sh"
source "$DCC_DIR/lib/render.sh"
source "$DCC_DIR/lib/frame.sh"
source "$DCC_DIR/lib/git.sh"
source "$DCC_DIR/lib/segments.sh"

_dcc_emit_line() { # _dcc_emit_line <segment-names>
  local name
  dcc_line_reset
  for name in $1; do
    dcc_segment "$name"
    dcc_line_push
  done
}

dcc_main() {
  local names1 names2

  IFS= read -r -d '' input || true
  [ -n "$input" ] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    printf 'dcc-statusline: jq is not on PATH\n'
    return 0
  fi

  dcc_config_path
  dcc_config_key
  dcc_claude_json_path
  dcc_parse_all "$input" "$DCC_CONFIG_PATH" "$DCC_CLAUDE_JSON" || return 0

  dcc_icons_init
  dcc_frame_init
  dcc_frame_budget
  dcc_sep_cells "${#DCC_SEP}"

  # Tests freeze the clock; %(%s)T is a bash builtin, so this costs no fork.
  [ -n "${DCC_NOW:-}" ] || printf -v DCC_NOW '%(%s)T' -1

  names1="$DCC_LINE1"
  names2="$DCC_LINE2"

  # Framed mode moves the account onto the top rule, so it must not also render
  # inside. Unframed mode leaves the line list exactly as configured.
  if [ "$DCC_FRAME_ON" -eq 1 ]; then
    names1="${names1// account/}"
    names1="${names1//account /}"
    names1="${names1//account/}"
  fi

  # Collect git state only when a git segment is actually configured.
  case " $names1 $names2 " in
    *" git "*|*" dir "*) dcc_git_collect "$P_CWD" || true ;;
  esac

  if [ "$DCC_FRAME_ON" -eq 1 ]; then
    dcc_frame_top "$P_EMAIL" "$DCC_I_ACCOUNT" "$DCC_ICON_W"
    printf '%s\n' "$DCC_FRAME_OUT"
    _dcc_emit_line "$names1"
    [ "$DCC_CONFIG_BAD" -eq 1 ] && { dcc_seg_add "cfg?" red bold; dcc_line_push; }
    dcc_line_build "$DCC_FRAME_BUDGET"
    dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
    printf '%s\n' "$DCC_FRAME_OUT"
    _dcc_emit_line "$names2"
    dcc_line_build "$DCC_FRAME_BUDGET"
    dcc_frame_row "$DCC_LINE_OUT" "$DCC_LINE_CELLS"
    printf '%s\n' "$DCC_FRAME_OUT"
    dcc_frame_bottom
    printf '%s\n' "$DCC_FRAME_OUT"
    return 0
  fi

  _dcc_emit_line "$names1"
  [ "$DCC_CONFIG_BAD" -eq 1 ] && { dcc_seg_add "cfg?" red bold; dcc_line_push; }
  dcc_line_build
  [ -n "$DCC_LINE_OUT" ] && printf '%s\n' "$DCC_LINE_OUT"

  _dcc_emit_line "$names2"
  dcc_line_build
  [ -n "$DCC_LINE_OUT" ] && printf '%s\n' "$DCC_LINE_OUT"

  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  input=""
  dcc_main
fi
```

- [ ] **Step 4: Run the whole suite**

Run: `bash plugins/dcc-statusline/tests/run-all.sh`
Expected: every file reports `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/statusline.sh plugins/dcc-statusline/tests/e2e.test.sh
git commit -m "feat(statusline): render the framed layout"
```

---

### Task 10: Run the probe at install and sync, and report it in doctor

**Files:**
- Modify: `plugins/dcc-statusline/scripts/install.sh` (the `dcc_copy_scripts` and `dcc_doctor` functions)
- Modify: `plugins/dcc-statusline/scripts/sync.sh`
- Test: `plugins/dcc-statusline/tests/install.test.sh`

**Interfaces:**
- Consumes: `scripts/detect-font.sh` from Task 4.
- Produces: `~/.claude/dcc-statusline/icons.detected` written at install and after a version-change sync. `doctor` prints an `icons:` line.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dcc-statusline/tests/install.test.sh`, before `finish`:

```bash
# --- font detection at install ------------------------------------------------
fake="$(mktemp -d)"
export DCC_FAKE_HOME="$fake"
mkdir -p "$fake/.claude"
printf '{}' > "$fake/.claude/settings.json"

DCC_WT_SETTINGS="$HERE/fixtures/wt-nerd.json" \
  bash "$HERE/../scripts/install.sh" install >/dev/null 2>&1
check "install writes the detection cache" \
  "$(cat "$fake/.claude/dcc-statusline/icons.detected" 2>/dev/null)" "nerd 2"

DCC_WT_SETTINGS="$HERE/fixtures/wt-plain.json" \
  bash "$HERE/../scripts/install.sh" install >/dev/null 2>&1
check "re-installing refreshes the cache" \
  "$(cat "$fake/.claude/dcc-statusline/icons.detected" 2>/dev/null)" "unicode 1"

out="$(DCC_WT_SETTINGS="$HERE/fixtures/wt-plain.json" \
  bash "$HERE/../scripts/install.sh" doctor 2>&1)"
check "doctor reports the icon mode" "$(printf '%s' "$out" | grep -c '^icons:')" "1"

# --- font detection on sync ---------------------------------------------------
printf '9.9.9' > "$fake/.claude/dcc-statusline/VERSION"
DCC_WT_SETTINGS="$HERE/fixtures/wt-nerd.json" \
  CLAUDE_PLUGIN_ROOT="$HERE/.." bash "$HERE/../scripts/sync.sh" >/dev/null 2>&1
check "a version change re-runs detection" \
  "$(cat "$fake/.claude/dcc-statusline/icons.detected" 2>/dev/null)" "nerd 2"

rm -rf "$fake"
unset DCC_FAKE_HOME
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/dcc-statusline/tests/install.test.sh`
Expected: FAIL — the cache file does not exist, and doctor prints no `icons:` line

- [ ] **Step 3: Write minimal implementation**

In `scripts/install.sh`, at the end of `dcc_copy_scripts`, add:

```bash
  # The probe forks freely; it runs here rather than in the render path, which
  # budgets five processes and cannot afford to look at fonts.
  bash "$DCC_DEST/detect-font.sh" "$DCC_DEST/icons.detected" >/dev/null 2>&1 || true
```

In `dcc_doctor`, after the version comparison block, add:

```bash
  if [ -r "$DCC_DEST/icons.detected" ]; then
    read -r dcc_m dcc_w < "$DCC_DEST/icons.detected"
    printf 'icons: %s at %s cell(s)\n' "${dcc_m:-unknown}" "${dcc_w:-?}"
  else
    printf 'icons: not detected yet -- run install to probe\n'
  fi
```

Declare `dcc_m` and `dcc_w` in the function's `local` list.

In `scripts/sync.sh`, replace the final two lines:

```bash
cp -R "$DCC_SRC/." "$DCC_DEST/" 2>/dev/null
# Font capability can change between updates -- a new machine, a new terminal
# profile -- so it is re-probed whenever the scripts are refreshed.
bash "$DCC_DEST/detect-font.sh" "$DCC_DEST/icons.detected" >/dev/null 2>&1 || true
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/dcc-statusline/tests/install.test.sh`
Expected: PASS, 0 failed

- [ ] **Step 5: Commit**

```bash
git add plugins/dcc-statusline/scripts/install.sh plugins/dcc-statusline/scripts/sync.sh plugins/dcc-statusline/tests/install.test.sh
git commit -m "feat(statusline): probe fonts at install and sync"
```

---

### Task 11: Documentation and version bump

**Files:**
- Modify: `plugins/dcc-statusline/README.md`
- Modify: `plugins/dcc-statusline/commands/dcc-statusline.md`
- Modify: `plugins/dcc-statusline/scripts/VERSION`

**Interfaces:**
- Consumes: the finished behaviour from Tasks 1-10.
- Produces: no code interface.

- [ ] **Step 1: Bump the version**

The `SessionStart` hook re-copies scripts only when `VERSION` differs, so an
unchanged version means installed users never receive this redesign.

```bash
printf '0.2.0' > plugins/dcc-statusline/scripts/VERSION
```

- [ ] **Step 2: Rewrite the README preamble**

Replace the sample block and the paragraph beneath it in
`plugins/dcc-statusline/README.md` with:

```markdown
```
╭─  you@example.com ─────────────────────────────────────────────────╮
│  plugins/dcc-statusline ·  main* ↑2 ?2 ·  Opus · xhigh ·          │
│  ctx ▰▰▰▰▰▱▱▱▱▱ 47% · 94k ·  1.20 ·  5h ▰▰▱▱▱▱▱▱ 23% · 4h13m     │
╰─────────────────────────────────────────────────────────────────────╯
```

Colour follows two rules. The frame takes the colour you assign to the account,
so a terminal is identifiable from its border alone. Inside the frame, colour
says what kind of thing a section is — blue for the path, magenta for the
branch, cyan for the model, violet for cost — while the meters keep the usage
ramp: green below 50%, yellow to 74%, orange to 89%, then red and bold at 90%
and above.

Within every section, three weights separate what leads from what supports. The
leaf directory, branch name, model and percentage are bold; icons, effort and
meter labels are plain; the parent path, separators, git counters and units are
dimmed.

The frame needs to know the terminal width, which Claude Code supplies in
`COLUMNS`. When that is missing or the terminal is narrower than 48 columns, the
status line falls back to two unframed lines rather than drawing a box it cannot
close.
```

- [ ] **Step 3: Update the README configuration table**

Add these rows to the existing table:

```markdown
| `frame` | `auto`, `box`, or `none`; `auto` frames when `COLUMNS` allows |
| `icons.mode` | `auto`, `nerd`, or `unicode`; `auto` uses the detected value |
| `icons.width` | Cells an icon occupies, `1` or `2`; omit to use detection |
| `palette` | Section name to colour: `dir`, `git`, `model`, `effort`, `fast`, `cost`, `mute` |
```

Change the segment-name sentence to drop `think`:

```markdown
Segment names: `dir`, `git`, `model`, `effort`, `fast`, `agent`, `style`,
`account`, `ctx`, `cost`, `5h`, `7d`. Unknown names are ignored.
```

- [ ] **Step 4: Document icon detection**

Add this section to the README after Configuration:

```markdown
## Icons

Nerd Font glyphs are used when a Nerd Font is available and words are used when
it is not. Detection runs at install time and again whenever the plugin updates,
never during a render — the render path budgets five processes and cannot afford
to probe fonts.

The probe reads the terminal's own configured font face first, because that
names the font actually doing the rendering. Only when that cannot be read does
it fall back to scanning installed fonts, since a Nerd Font being installed does
not mean your terminal uses it.

Icon width matters: a font named "Nerd Font" draws icons at two cells, while its
"Nerd Font Mono" variant draws them at one. Getting this wrong shifts the box's
right edge by one cell per icon. Set `icons.width` if the detected value is
wrong, and run `/dcc-statusline doctor` to see what was detected.
```

- [ ] **Step 5: Update the slash command documentation**

In `plugins/dcc-statusline/commands/dcc-statusline.md`, find the sentence
describing what `doctor` checks and append this to its list:

```markdown
It also reports the detected icon mode and icon cell width, printed as
`icons: nerd at 2 cell(s)`. Read that line when glyphs render as empty boxes
(the mode should be `unicode`) or when the box's right edge looks ragged (the
width is likely wrong — set `icons.width` in the config to correct it).
```

- [ ] **Step 6: Verify the marketplace manifest still validates**

Run: `claude plugin validate .`
Expected: no errors

- [ ] **Step 7: Run the whole suite one last time**

Run: `bash plugins/dcc-statusline/tests/run-all.sh`
Expected: every file reports `0 failed`

- [ ] **Step 8: Commit**

```bash
git add plugins/dcc-statusline/README.md plugins/dcc-statusline/commands/dcc-statusline.md plugins/dcc-statusline/scripts/VERSION
git commit -m "docs(statusline): document frame, palette and icons"
```

---

## Self-Review Notes

Spec coverage was checked section by section. Two gaps were found and closed
while writing:

- The spec's `palette` table lists a colour for `account`, but in framed mode
  the account moves to the rule and is painted by the frame's tint instead.
  Task 9 removes `account` from the line list when the frame is on, and Task 2
  therefore defines no `palette.account` key. Unframed mode still renders the
  account segment, using `DCC_P_MUTE`.
- The spec does not say what happens when the account address is wider than the
  terminal. Task 8 truncates the title so the closing corner cannot be pushed
  off the row, and asserts it.

One deliberate carry-over: `P_THINK` remains parsed in `config.sh` and its two
assertions in `config.test.sh` stay. The spec removes the *segment*, not the
payload field.
