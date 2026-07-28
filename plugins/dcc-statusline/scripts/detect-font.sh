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
