#!/usr/bin/env bash
# Telegram read side. Sourced by dcc-telegram-notify.sh; knows nothing about
# hooks, so it can be tested against a stub curl with no session in play.
#
# getUpdates is EXCLUSIVE per bot token: whoever calls it consumes updates for
# every other caller. Several sessions polling independently would steal each
# other's replies, so a poller files EVERY update it receives into a shared
# spool and each waiter then claims only what is addressed to it.

: "${TELEGRAM_ALLOWED_USERS:=}"
: "${TELEGRAM_REPLY:=on}"
: "${TELEGRAM_REPLY_WINDOW:=600}"
: "${TELEGRAM_REPLY_WINDOW_AWAY:=3600}"
: "${TELEGRAM_REPLY_POLL:=3}"
: "${TELEGRAM_SPOOL_TTL:=300}"

UPDATES_DIR="$TELEGRAM_NOTIFY_HOME/updates"
SPOOL_DIR="$UPDATES_DIR/spool"
OFFSET_FILE="$UPDATES_DIR/offset"
POLL_LOCK="$UPDATES_DIR/poll.lock"

# The read side needs more than the send side does. Any missing piece disables
# reading only -- notifications must keep working wherever the send side does.
reply_enabled() {
  [ "${TELEGRAM_REPLY:-on}" = "on" ] || return 1
  [ -n "${TELEGRAM_ALLOWED_USERS:-}" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  command -v curl >/dev/null 2>&1 || return 1
}

# A reply is an instruction Claude executes and an armed tap approves a tool
# call, so this is a security boundary, not an ergonomic one. Padding both sides
# keeps "11" from matching inside "111".
user_allowed() {
  local id="${1:-}" list
  [ -n "$id" ] || return 1
  [[ "$id" =~ ^[0-9]+$ ]] || return 1
  list=" $(printf '%s' "$TELEGRAM_ALLOWED_USERS" | tr ',' ' ') "
  case "$list" in *" $id "*) return 0 ;; *) return 1 ;; esac
}

# GNU stat and BSD stat disagree on flags and neither is present everywhere.
file_mtime() {
  [ -e "$1" ] || return 1
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# flock is absent from Git Bash for Windows, a first-class target, so locking
# falls back to an atomic mkdir. Unlike flock the kernel cannot release a mkdir
# lock when its holder dies, hence the stale steal below.
: "${TELEGRAM_LOCK_STALE:=60}"

# with_lock <lockpath> <command...> -- runs the command while holding the lock
# and propagates its exit code; returns 1 without running it if the lock is
# held. Both branches run the command in a subshell so the two paths behave
# identically.
with_lock() {
  local lock="$1"; shift
  if [ -z "${TELEGRAM_LOCK_FORCE_MKDIR:-}" ] && command -v flock >/dev/null 2>&1; then
    ( flock -n 9 || exit 1; "$@" ) 9>>"$lock.f"
    return $?
  fi
  lock_mkdir_acquire "$lock" || return 1
  ( "$@" ); local rc=$?
  rmdir "$lock.d" 2>/dev/null
  return $rc
}

lock_mkdir_acquire() {
  local lock="$1" mt
  mkdir "$lock.d" 2>/dev/null && return 0
  # A holder that was killed leaves the directory behind forever, so a lock that
  # has outlived any possible hold is assumed abandoned and taken.
  mt=$(file_mtime "$lock.d") || return 1
  [ $(( $(date +%s) - mt )) -gt "$TELEGRAM_LOCK_STALE" ] || return 1
  rmdir "$lock.d" 2>/dev/null || return 1
  mkdir "$lock.d" 2>/dev/null
}

updates_offset_get() {
  local off
  off=$(cat "$OFFSET_FILE" 2>/dev/null)
  [[ "$off" =~ ^[0-9]+$ ]] || off=0
  printf '%s' "$off"
}

updates_offset_set() {
  mkdir -p "$UPDATES_DIR" 2>/dev/null || return 0
  local tmp="$OFFSET_FILE.tmp.$$"
  printf '%s' "$1" > "$tmp" 2>/dev/null && mv "$tmp" "$OFFSET_FILE" 2>/dev/null
  return 0
}

updates_spool_put() {
  local u="$1" uid
  uid=$(jq -r '.update_id // empty' <<<"$u" 2>/dev/null) || return 0
  [ -n "$uid" ] || return 0
  mkdir -p "$SPOOL_DIR" 2>/dev/null || return 0
  local tmp="$SPOOL_DIR/.$uid.tmp.$$"
  printf '%s' "$u" > "$tmp" 2>/dev/null && mv "$tmp" "$SPOOL_DIR/$uid.json" 2>/dev/null
  return 0
}

# A reply sent to a session that has already died must not haunt a later one.
updates_sweep() {
  local f now mt
  now=$(date +%s)
  for f in "$SPOOL_DIR"/*.json; do
    [ -e "$f" ] || continue
    mt=$(file_mtime "$f") || continue
    [ $((now - mt)) -gt "$TELEGRAM_SPOOL_TTL" ] && rm -f "$f" 2>/dev/null
  done
  return 0
}

# Claim the first spooled update satisfying <predicate_fn>, which is called with
# the spool file path. The claim is a rename(2), which is atomic: two waiters
# racing for one update cannot both win, because the loser's mv hits an
# already-vanished source.
updates_claim() {
  local pred="$1" f claim
  for f in "$SPOOL_DIR"/*.json; do
    [ -e "$f" ] || continue
    "$pred" "$f" 2>/dev/null || continue
    claim="$UPDATES_DIR/claimed.$(basename "$f" .json).$$.json"
    mv "$f" "$claim" 2>/dev/null || continue
    cat "$claim" 2>/dev/null
    rm -f "$claim" 2>/dev/null
    return 0
  done
  return 1
}
