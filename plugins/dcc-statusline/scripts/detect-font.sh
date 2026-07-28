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
  # A font config describes the terminal that owns it, not whichever terminal
  # happens to be hosting us. Without WT_SESSION to prove we are running inside
  # Windows Terminal, its settings say nothing about what will render -- reading
  # them from another host is what once reported icons that arrived as "?".
  if [ -z "$f" ]; then
    [ -n "${WT_SESSION:-}" ] || return 1
    f="${LOCALAPPDATA:-}/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
  fi
  [ -r "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -r '[(.profiles.defaults.font.face? // empty)]
         + [((.profiles.list? // [])[]?.font.face? // empty)]
         | map(select(type == "string")) | .[0] // empty' "$f" 2>/dev/null
}

dcc_detect() { # prints "<mode> <width>"
  local face

  case "${DCC_ICONS:-}" in
    unicode) printf 'unicode 1'; return 0 ;;
    nerd)    printf 'nerd 2';    return 0 ;;
  esac

  # Only a terminal we can prove we are running inside gets to answer this, and
  # a plain face from it is a real negative rather than a reason to keep looking.
  if face="$(_dcc_wt_face)" && [ -n "$face" ]; then
    if _dcc_face_is_nerd "$face"; then
      printf 'nerd %s' "$(_dcc_width_for_face "$face")"
    else
      printf 'unicode 1'
    fi
    return 0
  fi

  # Scanning installed fonts is deliberately not a positive signal: a Nerd Font
  # being present on the machine never proved the terminal was using it, and
  # that false positive rendered every icon as "?" on a host that was not
  # Windows Terminal. The failure modes are not symmetric -- wrongly choosing
  # icons yields unreadable output, wrongly choosing words costs only polish --
  # so an unidentified host gets words and the user opts in via icons.mode.
  printf 'unicode 1'
}

# Written through a temporary file so a failure mid-probe cannot leave a
# half-written value that the render path would then read as authoritative.
dcc_tmp="$DCC_OUT.tmp.$$"
{ dcc_detect; printf '\n'; } > "$dcc_tmp" 2>/dev/null || { rm -f "$dcc_tmp"; exit 1; }
mv -f "$dcc_tmp" "$DCC_OUT" 2>/dev/null || { rm -f "$dcc_tmp"; exit 1; }
exit 0
