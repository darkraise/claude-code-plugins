# dcc-statusline — Resize Responsiveness — Design

Date: 2026-08-09
Status: DRAFT — awaiting user review

Builds on [2026-08-08-dcc-statusline-responsive-ui-design.md](2026-08-08-dcc-statusline-responsive-ui-design.md).
That document's width adaptation is correct and unchanged here. This document
fixes the reason it is rarely seen: the width is only ever re-read on a timer
that ticks once a minute.

## Problem

Resizing the terminal reflows every part of the Claude Code UI except the status
line. The frame keeps its old right wall and the segment tiers keep the choices
they made for the old width, until something unrelated happens.

The cause is not in the width math. `dcc_frame_init` reads `COLUMNS`, and
Claude Code sets `COLUMNS` to the current terminal size immediately before every
run. The problem is *when* runs happen. Claude Code re-executes the status line
command on session start, on a new assistant message, when `/compact` finishes,
on a permission-mode change, on a vim-mode toggle, and on the `refreshInterval`
timer. Terminal resize is not on that list.

Claude Code's own components are React/Ink nodes that re-render on `SIGWINCH`.
The status line is not a component — it is the string captured from the last run
of the script. On resize that captured string is re-laid-out (padded or
truncated) but not regenerated, so the layout decisions frozen inside it survive.
Anthropic's omission is defensible: dragging a window edge emits dozens of
`SIGWINCH` events per second, each of which would spawn and then cancel an
arbitrary user shell command.

A plugin has no hook into resize. The only lever is `refreshInterval`, and
`install.sh` currently writes `60`.

## Goal

A resized terminal is redrawn at the correct width within about two seconds,
without the status line costing more processes per minute than it does today.

## What changes, in one line each

| Change | Effect |
|--------|--------|
| `install.sh` writes `refreshInterval: 2` | Width is re-read every two seconds, so a resize is picked up within one tick |
| `doctor` checks the installed interval | Accounts still carrying `60` are named instead of silently lagging |
| Git state is cached in a temp file with a 10s TTL | Most of the 30× extra runs cost zero `git` forks |
| Cache reads and writes use only bash builtins | A cache hit adds no process to the render path |
| A per-session payload fingerprint forces a git refresh | Event-driven runs stay exact; only idle timer ticks serve cached git state |

## Non-goals

- **Detecting resize directly.** No mechanism exists. Polling is the whole design.
- **A configurable interval.** One shipped value, changed by editing `install.sh`.
  A knob would mean schema, validation, doctor reconciliation and tests for a
  number nobody has yet wanted to vary.
- **Caching anything other than git.** The remaining per-run work is one `jq`,
  which is needed for the payload regardless.

## Interval

`dcc_install_one` in `scripts/install.sh` writes the `.statusLine` object
wholesale, so lowering the literal is the entire migration path — re-running
`/dcc-statusline install --all` updates every account. `padding: 0` and the
command string are untouched.

Two seconds rather than one: at one-second ticks the resize gain is imperceptible
against two, while the tick rate doubles. Two seconds is also comfortably clear
of Claude Code's 300ms debounce and of the script's own runtime, so a tick never
arrives while the previous run is still going (Claude Code cancels an in-flight
script when a new trigger fires).

`doctor` reads `.statusLine.refreshInterval` from each account's `settings.json`
and, when it is not `2`, prints:

```
warn - <account> has refreshInterval <n>; resize will lag. Run: /dcc-statusline install
```

This follows the existing stale-copy warning next to it: a `warn` line, not a
`FAIL`, and no effect on the exit status.

## Git cache

`dcc_git_collect` runs `git status --porcelain=v2` and `git rev-parse
--show-toplevel` on every render. At a 2s interval that is 60 git invocations a
minute, which on Git Bash is the dominant cost of the whole feature.

**Location.** `${TMPDIR:-/tmp}/dcc-statusline/`. One file per working directory,
named from the normalized path with `/`, `\` and `:` substituted by `_` through
parameter expansion. Hashing would need a fork and the render path has no budget
for one.

**Format.** Line 1 is the epoch second the cache was written. Lines 2..n are the
collected fields (`branch`, `ahead`, `behind`, `staged`, `unstaged`, `untracked`,
`dirty`, `root`), one `name=value` per line. The final line is the literal
sentinel `END`.

**Reading.** A `while read` loop over a redirect, compared against
`printf -v now '%(%s)T' -1`. Both are builtins, so a cache hit costs no process.
Absent sentinel means a torn or partial file and is treated as a miss, so a
concurrent writer can never produce a rendered line built from half a cache.

**Writing.** A single `printf` redirect, not a temp-file-plus-`mv`, because `mv`
is a fork. The payload is a few hundred bytes and is emitted in one `write`,
which is atomic in practice on both a local Linux filesystem and NTFS. The
sentinel check makes the residual risk self-healing rather than visible.

**TTL.** 10 seconds. It must be several multiples of the tick interval or the
cache never hits: at 10s roughly four of every five idle ticks skip git entirely.
The cache decouples git cost from the tick rate — at most one collect per ten
seconds, so 6 collects a minute instead of the 30 a bare 2s interval would cause.
This is still above today's 60s baseline of roughly 1 collect a minute; the point
is that it stays bounded and does not scale with how fast the line refreshes.

**Sharing.** The cache is keyed by directory, not by session or account, so
concurrent sessions in the same repository share it. They would compute identical
values, so sharing is free.

## Freshness on event-driven runs

A 10s TTL applied blindly would make the git segment lag by up to ten seconds
after Claude finishes editing files — precisely when the segment is being read.

The fix distinguishes an event-driven run from an idle timer tick. An
event-driven run has a payload that differs from the previous run's: token counts
and cost advance with every assistant message. A per-session file in the same
cache directory holds the previous run's fingerprint, `P_CTX_TOK|P_COST`. When
the current fingerprint differs, git is collected fresh regardless of TTL, and
the new fingerprint is written. When it matches, the run is an idle tick and the
TTL governs.

This requires `session_id` from the payload, which the jq program does not
currently extract; it gains one field, `P_SESSION`. Keying per session rather
than per directory matters because two sessions sharing a repository would
otherwise invalidate each other's fingerprint on every tick and the TTL would
never apply.

Fingerprint files are small and accumulate one per session in the system temp
directory, which is cleaned by the OS. Pruning them from the render path would
cost a fork and is not worth it.

## Process budget

The header of `statusline.sh` declares the budget; it is amended to state the
two cases.

| Case | Processes |
|------|-----------|
| Idle tick, cache hit | 1 (`jq`) |
| Cache miss or event-driven run | 1 `jq` + 2 `git` + `timeout` wrappers |

The miss case equals today's unconditional cost, so no render is slower than it
is now, and the common case is cheaper.

## Structure

Cache logic lives in a new `scripts/lib/cache.sh` rather than inside `git.sh`.
`git.sh` stays a pure collector — run git, parse porcelain — and remains testable
without touching the filesystem. `cache.sh` owns the temp directory, the stamp,
the sentinel and the fingerprint, and calls into `dcc_git_collect` on a miss.
`statusline.sh` calls `dcc_git_cached` where it currently calls
`dcc_git_collect`.

## Testing

`tests/install.test.sh:90` asserts `60` and becomes `2`.

New cases, in the existing `tests/` style with a fake `TMPDIR`:

- A cache hit returns the same globals a fresh collect would, and runs no git.
- A stamp older than the TTL forces a refresh and rewrites the file.
- A file missing its `END` sentinel is treated as a miss.
- A changed fingerprint forces a refresh inside the TTL.
- An unchanged fingerprint inside the TTL serves the cache.
- A directory outside a repository caches nothing and keeps returning non-zero.
- `doctor` warns when an account's `refreshInterval` is not 2, and is silent at 2.

Git invocation counting is done with a stub `git` earlier on `PATH` that appends
to a counter file, which is how the existing git tests already isolate.

## Documentation

The README's install section states the interval and why it is two seconds, and
names the cache directory so a stale git segment has an obvious thing to delete.
The troubleshooting list gains an entry for a status line that does not follow a
resize: the account's `refreshInterval` has drifted, run install.
