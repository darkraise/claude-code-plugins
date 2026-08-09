#!/usr/bin/env bash
# Helpers shared by the engine and the read-side libraries. Kept separate so both
# can source it without depending on which one loaded first.

# Config values are text a user edited by hand, so one must never reach an
# arithmetic context unchecked: under `set -u` a non-numeric token aborts the
# process, and a leading zero is read as octal. Validating once at the boundary
# is what lets every consumer downstream treat these as plain decimal integers.
sanitize_seconds() {
  local v="${1:-}" fb="$2"
  [[ "$v" =~ ^[0-9]+$ ]] && [ "${#v}" -le 9 ] || { printf '%s' "$fb"; return 0; }
  v=$(( 10#$v ))
  [ "$v" -gt 0 ] || { printf '%s' "$fb"; return 0; }
  printf '%s' "$v"
}
