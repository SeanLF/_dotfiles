#!/usr/bin/env bash
# Drives the DualSense through Steer's steer:// surface from Claude Code and Codex
# hook events: LEDs count waiting sessions, haptics mark approval/idle/done.
# Desktop notifications are Claude Code's own (Ghostty, gated on "away").
#
#   steer.sh <working|approval|idle|done|end>

set -uo pipefail

# Fixed path, not $TMPDIR: TMPDIR is per-bootstrap-namespace, so a login shell,
# a LaunchAgent and SSH would each get a different directory.
readonly STATE_DIR="${STEER_STATE_DIR:-${HOME}/.cache/claude-steer-sessions}"
readonly DEV_APP="/Users/sean/Developer/steer/Steer Dev.app"
EVENT="${1:-}"

mkdir -p "$STATE_DIR" 2>/dev/null
[ -w "$STATE_DIR" ] || exit 0

# running first: tab is IFS whitespace, so an empty leading field would shift the rest.
IFS=$'\t' read -r running session_id cwd <<<"$(cat 2>/dev/null | jq -r '[([.background_tasks[]? | select(.status == "running" and .type == "subagent")] | length), .session_id // "", .cwd // ""] | @tsv' 2>/dev/null)"

# session_id becomes a path component and an `rm -f` argument.
case "${session_id:-}" in
  '' | *[!A-Za-z0-9_-]*) exit 0 ;;
esac

# Stop with a subagent still running is a pause, not done (documented use of
# background_tasks). A background shell may never exit, so it does not count.
[ "$EVENT" = "done" ] && [ "${running:-0}" -gt 0 ] 2>/dev/null && EVENT=working

# The owning claude/codex pid, so a dead session's state can be pruned. Test
# membership against ppid, not comm: comm[p] auto-creates the key in awk.
claude_pid="$(
  ps -eo pid=,ppid=,comm= 2>/dev/null | awk -v start="$$" '
    { ppid[$1] = $2; comm[$1] = $3 }
    END {
      p = start
      while (p > 1 && ++hops < 64) {
        name = comm[p]; sub(/.*\//, "", name)
        if (name == "claude" || name == "codex") { print p; exit }
        if (!(p in ppid)) exit
        p = ppid[p]
      }
    }'
)"

state_file="${STATE_DIR}/${session_id}"
case "$EVENT" in
  working | approval | idle | done)
    printf '%s\t%s\t%s\t%s\n' "$EVENT" "${cwd:-$PWD}" "${claude_pid:-0}" "$(date +%s)" >"$state_file" || exit 0
    ;;
  end) rm -f "${STATE_DIR:?}/${session_id:?}" ;;
  *) exit 0 ;;
esac

# `open` can block; run detached.
{
  now="$(date +%s)"
  # A missing or non-numeric stamp reads as ancient; $((now - "abc")) would kill
  # this block under set -u.
  read_age() {
    local s
    s="$(cut -f4 "$1" 2>/dev/null | head -1)"
    case "${s:-}" in
      '' | *[!0-9]*) printf '%s' 999999 ;;
      *) printf '%s' $((now - s)) ;;
    esac
  }

  # Prune sessions whose process is gone; pid 0 would make kill -0 signal the
  # whole process group, so those fall back to age.
  for f in "$STATE_DIR"/*; do
    [ -e "$f" ] || continue
    pid="$(cut -f3 "$f" 2>/dev/null | head -1)"
    case "${pid:-}" in
      '' | 0 | *[!0-9]*) [ "$(read_age "$f")" -gt 43200 ] && rm -f "$f" ;;
      *) kill -0 "$pid" 2>/dev/null || rm -f "$f" ;;
    esac
  done

  # Working sessions don't light the gauge; waiting states age out.
  waiting=0
  approvals=0
  for f in "$STATE_DIR"/*; do
    [ -e "$f" ] || continue
    state="$(cut -f1 "$f" 2>/dev/null | head -1)"
    age="$(read_age "$f")"
    case "$state" in
      approval)
        [ "$age" -lt 1800 ] && waiting=$((waiting + 1))
        [ "$age" -lt 300 ] && approvals=$((approvals + 1))
        ;;
      done | idle) [ "$age" -lt 1800 ] && waiting=$((waiting + 1)) ;;
    esac
  done
  [ "$waiting" -gt 5 ] && waiting=5

  # Only when Steer is already running, or `open steer://` launches it.
  # -x, never -f: -f matches any argv naming the path and would launch it.
  steer_pid="$(pgrep -x Steer 2>/dev/null | head -1)"
  [ -n "$steer_pid" ] || exit 0
  steer_bin="$(ps -o comm= -p "$steer_pid" 2>/dev/null)"
  steer() {
    case "$steer_bin" in
      *"Steer Dev.app"*) open -g -a "$DEV_APP" "steer://$1" >/dev/null 2>&1 ;;
      *) open -g "steer://$1" >/dev/null 2>&1 ;;
    esac
  }

  steer "leds/${waiting}"
  if [ "$approvals" -gt 0 ]; then steer "micled/pulse"; else steer "micled/off"; fi
  case "$EVENT" in
    approval) steer "haptic/warning" ;;
    done) steer "haptic/double" ;;
    idle) steer "haptic/pulse" ;;
  esac
} >/dev/null 2>&1 </dev/null &

exit 0
