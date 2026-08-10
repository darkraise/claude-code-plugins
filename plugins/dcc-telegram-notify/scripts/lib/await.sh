#!/usr/bin/env bash
# The two waiting loops. Sourced by dcc-telegram-notify.sh after updates.sh.
#
# await_reply runs AFTER a turn has ended (an asyncRewake Stop hook), so nothing
# is blocked while it waits. await_tap runs INSIDE a synchronous permission gate
# and does block, which is why it only ever runs while away mode is armed.

# Arming and disarming from the chat must never be mistaken for an instruction
# to Claude, so control commands are consumed before the reply matchers run.
# Returns 0 when the update was a command this consumed.
handle_control() {
  local u="$1" text
  text=$(update_text "$u")
  case "$text" in
    /away*)
      local spec secs
      spec=$(printf '%s' "$text" | awk '{print $2}')
      secs=$(parse_duration "$spec") || secs="$TELEGRAM_AWAY_TTL"
      away_arm "$secs"
      dbg "   away: armed for ${secs}s from Telegram"
      return 0 ;;
    /back*)
      away_disarm
      dbg "   away: disarmed from Telegram"
      return 0 ;;
    *) return 1 ;;
  esac
}

# Drain any control commands sitting in the spool. Called once per poll cycle by
# both loops so /away and /back work no matter which waiter is running.
drain_control() {
  local u
  while u=$(updates_claim match_command); do
    [ -n "$u" ] || break
    handle_control "$u"
  done
  return 0
}

# Wait for a reply addressed to the notification we just sent. Prints the reply
# text and returns 0; returns 1 for every other outcome, all of which mean "do
# nothing and let the session be".
await_reply() {
  local start_file="$1" msg_id="$2" chat="$3" topic="$4" deadline="$5"
  local baseline u rc
  baseline=$(file_mtime "$start_file" 2>/dev/null) || baseline=0

  MATCH_REPLY_TO="$msg_id"; MATCH_CHAT="$chat"; MATCH_TOPIC="$topic"

  while [ "$(date +%s)" -lt "$deadline" ]; do
    # UserPromptSubmit rewrites this file on every locally submitted prompt, so
    # a changed mtime means the user came back to the keyboard and won the race.
    local now_mt
    now_mt=$(file_mtime "$start_file" 2>/dev/null) || now_mt=0
    if [ "$now_mt" != "$baseline" ]; then
      dbg "   await_reply: local prompt detected, standing down"
      return 1
    fi

    updates_poll; rc=$?
    if [ "$rc" = "2" ]; then
      dbg "   await_reply: 409 conflict, another consumer owns this bot"
      return 1
    fi
    updates_sweep
    drain_control

    if u=$(updates_claim match_reply_to); then
      update_text "$u"; return 0
    fi
    if u=$(updates_claim match_bare_topic); then
      update_text "$u"; return 0
    fi
    sleep 1
  done
  dbg "   await_reply: window elapsed"
  return 1
}

# Wait for a button tap carrying our nonce. Prints the button index and returns
# 0; returns 1 on timeout or conflict, which the gate turns into "no decision"
# so the terminal picker appears exactly as it does today.
await_tap() {
  local nonce="$1" chat="$2" deadline="$3" u rc
  MATCH_NONCE="$nonce"; MATCH_CHAT="$chat"

  while [ "$(date +%s)" -lt "$deadline" ]; do
    updates_poll; rc=$?
    if [ "$rc" = "2" ]; then
      dbg "   await_tap: 409 conflict, standing down"
      return 1
    fi
    updates_sweep
    drain_control

    if u=$(updates_claim match_callback); then
      answer_callback "$(update_callback_id "$u")" "Got it"
      update_callback_index "$u"
      return 0
    fi
    sleep 1
  done
  dbg "   await_tap: window elapsed"
  return 1
}
