#!/usr/bin/env bash
# Routes Claude Code session state to a DualSense via Steer's steer:// surface.
#
#   steer-agent.sh <working|approval|idle|done|end>
#
# Runs on UserPromptSubmit, synchronously. Anything that can block (`open`,
# `osascript`) is pushed into the detached background block below.

set -uo pipefail

# Fixed path, not $TMPDIR: TMPDIR is per-bootstrap-namespace, so a login shell,
# a LaunchAgent and SSH would each get a different directory.
readonly STATE_DIR="${STEER_AGENT_STATE_DIR:-${HOME}/.cache/claude-steer-sessions}"
readonly DEV_APP="/Users/sean/Developer/steer/Steer Dev.app"
EVENT="${1:-}"

mkdir -p "$STATE_DIR" 2>/dev/null
# mkdir -p succeeds on an existing unwritable directory, so check separately.
[ -w "$STATE_DIR" ] || exit 0

# running first: tab is IFS whitespace, so an empty leading field would shift the rest.
IFS=$'\t' read -r running session_id cwd <<<"$(cat 2>/dev/null | jq -r '[([.background_tasks[]? | select(.status == "running")] | length), .session_id // "", .cwd // ""] | @tsv' 2>/dev/null)"
[ -n "${session_id:-}" ] || exit 0

# The turn ended but background work will wake Claude again: not done, not waiting.
case "$EVENT" in
  done | idle) [ "${running:-0}" -gt 0 ] 2>/dev/null && EVENT=working ;;
esac

# session_id becomes a path component and an `rm -f` argument; reject anything
# that isn't a plain identifier.
case "$session_id" in
  '' | *[!A-Za-z0-9_-]*) exit 0 ;;
esac

# Walk up to the owning `claude` process for its pid and tty. The tty MUST
# come from the claude process, not from this hook: hooks are spawned without
# a controlling terminal, so `ps -o tty= -p $$` here would return `??`.
#
# The membership test below is against `ppid`, NOT `comm`: referencing comm[p]
# auto-creates the key in awk, so `p in comm` would always succeed and turn an
# unresolvable pid into an infinite loop. The hop cap is a second line of
# defence, not the fix.
IFS=' ' read -r claude_pid tty_name <<<"$(
  ps -eo pid=,ppid=,tty=,comm= 2>/dev/null | awk -v start="$$" '
    { ppid[$1] = $2; tty[$1] = $3; comm[$1] = $4 }
    END {
      p = start
      while (p > 1 && ++hops < 64) {
        name = comm[p]; sub(/.*\//, "", name)
        if (name == "claude" || name == "codex") { print p, tty[p]; exit }
        if (!(p in ppid)) exit
        p = ppid[p]
      }
    }'
)"

state_file="${STATE_DIR}/${session_id}"

# Log the degraded cases once per session, not once per event, or a routine
# ClaudeCode.app session (tty is legitimately `??`) buries real failures.
if [ -z "${claude_pid:-}" ]; then
  tty_path=""
  [ -f "$state_file" ] || logger -t steer-agent "no claude ancestor from pid $$; session is pid-0, age-pruned only"
elif [ -z "${tty_name:-}" ] || [ "$tty_name" = "??" ]; then
  tty_path=""
  [ -f "$state_file" ] || logger -t steer-agent "no tty for claude pid ${claude_pid}; notification will not be clickable"
else
  tty_path="/dev/${tty_name}"
fi

# Test seam.
[ -n "${STEER_AGENT_TTY:-}" ] && tty_path="$STEER_AGENT_TTY"

case "$EVENT" in
  working | approval | idle | done)
    # Store the raw cwd, not a resolved project name: this path is
    # synchronous, and resolving needs a git subprocess (done below instead).
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$EVENT" "$tty_path" "${cwd:-$PWD}" "${claude_pid:-0}" "$(date +%s)" >"$state_file" ||
      {
        logger -t steer-agent "failed to write ${state_file}"
        exit 0
      }
    ;;
  end)
    rm -f "${STATE_DIR:?}/${session_id:?}"
    ;;
  *)
    exit 0
    ;;
esac

# Everything below can block; run it detached.
{
  now="$(date +%s)"

  # A MISSING stamp must read as ANCIENT, not zero, or such a file counts
  # toward the gauge forever and skips the age-based prune. A NON-NUMERIC
  # stamp is worse: under `set -u`, $((now - "abc")) exits the whole shell,
  # silently killing this detached block for every session. Guard both.
  read_age() {
    local s
    s="$(cut -f5 "$1" 2>/dev/null | head -1)"
    case "${s:-}" in
      '' | *[!0-9]*) printf '%s' 999999 ;;
      *) printf '%s' $((now - s)) ;;
    esac
  }

  # Prune sessions whose owning process is gone. The age fallback below is only
  # for files we can't verify by pid (pid 0 would make `kill -0` signal the
  # whole process group); pid-verified files are never pruned by mtime, since
  # an idle session generates none.
  for f in "$STATE_DIR"/*; do
    [ -e "$f" ] || continue
    pid="$(cut -f4 "$f" 2>/dev/null | head -1)"
    case "${pid:-}" in
      '' | 0 | *[!0-9]*)
        # Unverifiable owner: fall back to age so it can't linger forever.
        [ "$(read_age "$f")" -gt 43200 ] && rm -f "$f"
        ;;
      *)
        kill -0 "$pid" 2>/dev/null || rm -f "$f"
        ;;
    esac
  done

  # "working" doesn't count toward the gauge: a lit LED for a busy session
  # trains you to ignore the light. Both waiting states age out (1800s) so a
  # session doesn't peg the gauge forever after Stop; approval ages out
  # separately and sooner (300s) since nothing signals a prompt was answered.
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
      done | idle)
        [ "$age" -lt 1800 ] && waiting=$((waiting + 1))
        ;;
    esac
  done
  [ "$waiting" -gt 5 ] && waiting=5

  # Guard on Steer already running, or `open steer://...` launches the app.
  # -x, never -f: -f matches any argv merely naming the path, and would launch it.
  steer_bin=""
  steer_pid="$(pgrep -x Steer 2>/dev/null | head -1)"
  if [ -n "$steer_pid" ]; then
    steer_bin="$(ps -o comm= -p "$steer_pid" 2>/dev/null)"
    [ -z "$steer_bin" ] &&
      logger -t steer-agent "Steer pid ${steer_pid} resolved no path; URL routing degraded"
  fi

  steer() {
    case "$steer_bin" in
      '') return 0 ;;
      *"Steer Dev.app"*) open -g -a "$DEV_APP" "steer://$1" >/dev/null 2>&1 ;;
      *) open -g "steer://$1" >/dev/null 2>&1 ;;
    esac
  }

  steer "leds/${waiting}"
  if [ "$approvals" -gt 0 ]; then steer "micled/pulse"; else steer "micled/off"; fi

  # Resolved before any Apple Event, so `working` and `end` never talk to
  # Ghostty at all.
  case "$EVENT" in
    approval) notify_msg="needs your approval" ;;
    done) notify_msg="finished" ;;
    idle) notify_msg="waiting on you" ;;
    *) notify_msg="" ;;
  esac
  [ -n "$notify_msg" ] || exit 0

  # Only `done` (Stop, which fires every turn) is gated on tab focus; approval
  # and idle already imply the human isn't typing, so a focused tab there
  # isn't a present human and must not suppress the signal.
  #
  # Guarded on Ghostty already running, or a bare `tell application` launches
  # it. Its comm is lowercase `ghostty`, so `pgrep -x Ghostty` misses it here
  # on purpose. `with timeout` bounds the Apple Event.
  tab_is_focused() {
    [ -n "$tty_path" ] || return 1
    pgrep -f "Ghostty.app/Contents/MacOS" >/dev/null 2>&1 || return 1
    [ "$(
      osascript <<APPLESCRIPT 2>/dev/null
with timeout of 3 seconds
  tell application "Ghostty"
    if not frontmost then return "no"
    try
      if (tty of (focused terminal of (selected tab of front window))) is "$tty_path" then return "yes"
    end try
  end tell
end timeout
return "no"
APPLESCRIPT
    )" = "yes" ]
  }

  if [ "$EVENT" = "done" ] && tab_is_focused; then
    exit 0
  fi

  # Resolved from the git root, so a session that `cd`s into a subdirectory
  # doesn't rename itself mid-flight.
  project="$(basename "$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${cwd:-$PWD}")")"

  case "$EVENT" in
    approval) steer "haptic/warning" ;;
    done) steer "haptic/double" ;;
    idle) steer "haptic/pulse" ;;
  esac

  if [ -n "$tty_path" ] && [ -w "$tty_path" ]; then
    # Any C0 or `;` would break out of the OSC sequence; `project` is a dirname.
    printf '\033]777;notify;%s;%s\007' \
      "$(printf '%s' "$project" | tr -d '\000-\037;')" \
      "$(printf '%s' "$notify_msg" | tr -d '\000-\037;')" \
      >"$tty_path" 2>/dev/null ||
      logger -t steer-agent "OSC write to ${tty_path} failed; ${EVENT} notification lost"
  else
    # Every logger call in this file lands at DEBUG; `log show` needs --debug.
    logger -t steer-agent "no tty for session; ${EVENT} notification suppressed"
  fi
} >/dev/null 2>&1 </dev/null &

exit 0
