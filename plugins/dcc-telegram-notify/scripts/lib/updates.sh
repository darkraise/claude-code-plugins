#!/usr/bin/env bash
# Telegram read side. Sourced by dcc-telegram-notify.sh; knows nothing about
# hooks, so it can be tested against a stub curl with no session in play.
#
# getUpdates is EXCLUSIVE per bot token: whoever calls it consumes updates for
# every other caller. Several sessions polling independently would steal each
# other's replies, so a poller files EVERY update it receives into a shared
# spool and each waiter then claims only what is addressed to it.

# sanitize_seconds is shared with the engine; resolved relative to this file so
# a standalone test source (which never loads the engine) still finds it.
UPDATES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[ -r "$UPDATES_LIB_DIR/common.sh" ] && . "$UPDATES_LIB_DIR/common.sh"

: "${TELEGRAM_ALLOWED_USERS:=}"
: "${TELEGRAM_REPLY:=on}"
: "${TELEGRAM_REPLY_WINDOW:=600}"
: "${TELEGRAM_REPLY_WINDOW_AWAY:=3600}"
: "${TELEGRAM_REPLY_POLL:=3}"
TELEGRAM_REPLY_POLL=$(sanitize_seconds "$TELEGRAM_REPLY_POLL" 3)
: "${TELEGRAM_SPOOL_TTL:=300}"
TELEGRAM_SPOOL_TTL=$(sanitize_seconds "$TELEGRAM_SPOOL_TTL" 300)

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
TELEGRAM_LOCK_STALE=$(sanitize_seconds "$TELEGRAM_LOCK_STALE" 60)

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
  local token="$$-$BASHPID-$RANDOM-$(date +%s)"
  lock_mkdir_acquire "$lock" "$token" || return 1
  ( "$@" ); local rc=$?
  lock_mkdir_release "$lock" "$token"
  return $rc
}

lock_mkdir_acquire() {
  local lock="$1" token="$2" mt
  if mkdir "$lock.d" 2>/dev/null; then
    printf '%s' "$token" > "$lock.d/owner" 2>/dev/null
    return 0
  fi
  # A holder that was killed leaves the directory behind forever, so a lock that
  # has outlived any possible hold is assumed abandoned and taken.
  mt=$(file_mtime "$lock.d") || return 1
  [ $(( $(date +%s) - mt )) -gt "$TELEGRAM_LOCK_STALE" ] || return 1
  rm -f "$lock.d/owner" 2>/dev/null
  rmdir "$lock.d" 2>/dev/null || return 1
  mkdir "$lock.d" 2>/dev/null || return 1
  printf '%s' "$token" > "$lock.d/owner" 2>/dev/null
  return 0
}

# Only the current owner may release. A holder that was stolen from would
# otherwise delete the new holder's lock and admit a third process alongside it.
lock_mkdir_release() {
  local lock="$1" token="$2"
  [ "$(cat "$lock.d/owner" 2>/dev/null)" = "$token" ] || return 0
  rm -f "$lock.d/owner" 2>/dev/null
  rmdir "$lock.d" 2>/dev/null
  return 0
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
# already-vanished source. That guarantee only holds if the two waiters target
# different destinations, though -- $$ is the invoking shell's PID and is
# shared by every subshell it forks, so two claimers running as sibling
# subshells of the same shell would both build the identical destination name
# and both successfully mv+cat the same file. $BASHPID is set per subshell, so
# it is what actually distinguishes them; $RANDOM guards the remaining case of
# two genuinely separate processes racing in the same PID slot.
updates_claim() {
  local pred="$1" f claim
  for f in "$SPOOL_DIR"/*.json; do
    [ -e "$f" ] || continue
    "$pred" "$f" 2>/dev/null || continue
    claim="$UPDATES_DIR/claimed.$(basename "$f" .json).${BASHPID:-$$}.$RANDOM.json"
    mv "$f" "$claim" 2>/dev/null || continue
    cat "$claim" 2>/dev/null
    rm -f "$claim" 2>/dev/null
    return 0
  done
  return 1
}

# One locked fetch. The lock is non-blocking on purpose: if another waiter is
# already filling the spool there is nothing to gain by queueing, so we return
# and let the caller re-scan what that waiter files.
#
# Returns 0 on a completed poll, 1 on lock contention or any failure, and 2 on a
# 409, which means another consumer (or a webhook) owns this bot token. There is
# no winning that fight, so the caller stops rather than thrashing.
updates_poll() {
  mkdir -p "$SPOOL_DIR" 2>/dev/null || return 1
  with_lock "$POLL_LOCK" _updates_poll_locked
}

_updates_poll_locked() {
    local off resp ok max u uid from
    off=$(updates_offset_get)
    resp=$(curl -sS --max-time "$((TELEGRAM_REPLY_POLL + 10))" \
      --data-urlencode "offset=$((off + 1))" \
      --data-urlencode "timeout=${TELEGRAM_REPLY_POLL}" \
      --data-urlencode 'allowed_updates=["message","callback_query"]' \
      "${API}/getUpdates" 2>/dev/null) || exit 1

    ok=$(jq -r '.ok // false' <<<"$resp" 2>/dev/null)
    if [ "$ok" != "true" ]; then
      [ "$(jq -r '.error_code // 0' <<<"$resp" 2>/dev/null)" = "409" ] && exit 2
      exit 1
    fi

    # Advance past every update returned, including ones the allowlist drops.
    # Leaving a filtered update below the offset would refetch it forever.
    max=$(jq -r '[.result[].update_id] | max // empty' <<<"$resp" 2>/dev/null)

    while IFS= read -r u; do
      [ -n "$u" ] || continue
      from=$(jq -r '(.message.from.id // .callback_query.from.id // empty)' <<<"$u" 2>/dev/null)
      if ! user_allowed "$from"; then
        uid=$(jq -r '.update_id // "?"' <<<"$u" 2>/dev/null)
        dbg "   updates: dropped update $uid from unlisted user ${from:-none}"
        continue
      fi
      updates_spool_put "$u"
    done < <(jq -c '.result[]' <<<"$resp" 2>/dev/null)

    [ -n "$max" ] && updates_offset_set "$max"
    exit 0
}

# --- Matchers ----------------------------------------------------------------
# Each takes a spool file path and reads the MATCH_* globals the waiter set, so
# they satisfy the single-argument contract updates_claim calls them with.

# A notification going to a group's main thread rather than a forum topic has no
# thread id; "main" keeps the filename well-formed.
last_marker_path() {
  local chat="$1" topic="${2:-}"
  [ -n "$topic" ] || topic=main
  printf '%s/last/%s.%s' "$TELEGRAM_NOTIFY_HOME" "$chat" "$topic"
}

match_reply_to() {
  local rid chat
  # message_id is only unique within a chat, and updates_poll spools updates
  # from every chat the bot is in, so an unscoped id could pick up a reply
  # aimed at a waiter in a different chat entirely.
  chat=$(jq -r '.message.chat.id // empty' "$1" 2>/dev/null)
  [ "$chat" = "${MATCH_CHAT:-}" ] || return 1
  rid=$(jq -r '.message.reply_to_message.message_id // empty' "$1" 2>/dev/null)
  [ -n "$rid" ] && [ "$rid" = "${MATCH_REPLY_TO:-}" ]
}

match_bare_topic() {
  local chat topic rid
  jq -e '.message' "$1" >/dev/null 2>&1 || return 1
  chat=$(jq -r '.message.chat.id // empty' "$1" 2>/dev/null)
  topic=$(jq -r '.message.message_thread_id // empty' "$1" 2>/dev/null)
  [ "$chat" = "${MATCH_CHAT:-}" ] || return 1
  [ "${topic:-}" = "${MATCH_TOPIC:-}" ] || return 1
  # Telegram auto-fills reply_to_message with a topic's ROOT message even when
  # the user never pressed Reply, so only a reply pointing somewhere else counts
  # as an explicit one -- otherwise a plain answer typed into a topic would be
  # rejected here and picked up by nothing.
  rid=$(jq -r '.message.reply_to_message.message_id // empty' "$1" 2>/dev/null)
  [ -n "$rid" ] && [ "$rid" != "${topic:-}" ] && return 1
  # Only the newest notification in this topic may absorb an unaddressed reply,
  # so an older session cannot swallow an answer meant for a newer prompt.
  [ "$(cat "$(last_marker_path "$MATCH_CHAT" "$MATCH_TOPIC")" 2>/dev/null)" = "${MATCH_REPLY_TO:-}" ]
}

match_callback() {
  local d
  d=$(jq -r '.callback_query.data // empty' "$1" 2>/dev/null)
  [ -n "$d" ] && [ "${d%%:*}" = "${MATCH_NONCE:-}" ]
}

# Claimed before the reply matchers so arming or disarming from the chat is
# never mistaken for an instruction to Claude.
match_command() {
  local chat text
  chat=$(jq -r '.message.chat.id // empty' "$1" 2>/dev/null)
  [ "$chat" = "${MATCH_CHAT:-}" ] || return 1
  text=$(jq -r '.message.text // empty' "$1" 2>/dev/null)
  case "$text" in
    /away|/away\ *|/back|/back\ *) return 0 ;;
    *) return 1 ;;
  esac
}

update_text() { jq -r '.message.text // ""' <<<"$1" 2>/dev/null; }
update_callback_index() { jq -r '(.callback_query.data // "") | split(":")[1] // ""' <<<"$1" 2>/dev/null; }
update_callback_id() { jq -r '.callback_query.id // ""' <<<"$1" 2>/dev/null; }
