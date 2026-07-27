#!/usr/bin/env bash
set -uo pipefail
# Path normalization, shared by every place a filesystem path is compared or
# abbreviated. On Windows the same directory reaches this plugin in three
# namespaces: Claude Code sends "C:/Users/you", a shell may hand over
# "C:\Users\you", and Git Bash sets $HOME to the MSYS form "/c/Users/you".
# A prefix comparison between two of them fails silently and produces a raw
# absolute path where an abbreviated one was intended, so every path is folded
# into the MSYS form -- the one $HOME already uses -- before any comparison.
#
# Pure parameter expansion, deliberately: this runs several times per render and
# the render path budgets five external processes in total, so cygpath, sed, and
# command substitution are all off limits.

DCC_PATH=""

dcc_path_norm() { # dcc_path_norm <path> -> DCC_PATH
  local p="${1:-}" letter
  DCC_PATH=""
  [ -n "$p" ] || return 0
  p="${p//\\//}"
  case "$p" in
    [A-Za-z]:|[A-Za-z]:/*)
      letter="${p:0:1}"
      p="/${letter,,}${p:2}"
      ;;
  esac
  # Drop one trailing slash so "/c/users/you/" and "/c/users/you" compare equal,
  # while leaving the filesystem root itself as "/" rather than "".
  [ "$p" = "/" ] || p="${p%/}"
  DCC_PATH="$p"
}
