#!/usr/bin/env bash
#
# Route Claude Code session state to a DualSense via Steer's steer:// surface.
#
#   steer-agent.sh <working|approval|idle|done|end>
#
# Hook JSON arrives on stdin. Three signals, each doing what it is actually
# good at (all measured on hardware 2026-07-19, not assumed):
#
#   player LEDs   how many sessions want you      ambient, survives layer presses
#   haptic        something changed               finds you without a screen
#   notification  which project, click to go      the only channel carrying identity
#
# The light bar is deliberately NOT used: it is driven every tick by the
# layer/gyro/battery state machine, so anything written there is wiped by the
# first L1 press. The player LEDs are untouched by that path.
#
# STALL SAFETY: this runs on UserPromptSubmit, which Claude Code executes
# synchronously before your prompt is processed. Everything that can block --
# `open` (LaunchServices), `osascript` (Apple Events, 120s default reply
# timeout), terminal-notifier -- is therefore pushed into a detached
# background block. The synchronous part is a cat, two jq calls and a printf.
# A fully wedged Ghostty or Steer must cost the session nothing.

set -uo pipefail

# Fixed path, not $TMPDIR: on macOS TMPDIR is per-bootstrap-namespace, so
# sessions started from a login shell, a LaunchAgent and over SSH would each
# get a different directory and the gauge would silently count only its own.
readonly STATE_DIR="${HOME}/.cache/claude-steer-sessions"
readonly DEV_APP="/Users/sean/Developer/steer/Steer Dev.app"
readonly EVENT="${1:-}"

mkdir -p "$STATE_DIR" 2>/dev/null
# `mkdir -p` succeeds on an existing directory even if it is unwritable, which
# would disable the feature permanently and invisibly. Check writability too.
[ -w "$STATE_DIR" ] || exit 0

# --- Session identity --------------------------------------------------------
# One jq invocation, not two: this path is synchronous on every prompt.
IFS=$'\t' read -r session_id cwd <<<"$(cat 2>/dev/null | jq -r '[.session_id // "", .cwd // ""] | @tsv' 2>/dev/null)"
[ -n "${session_id:-}" ] || exit 0

# session_id becomes a path component and an `rm -f` argument. Claude Code
# emits UUIDs, but a stray `/` would silently write into a non-existent
# subdirectory (making the session invisible to the gauge forever) and `..`
# would take the delete outside STATE_DIR. Reject anything that isn't a plain
# identifier rather than reasoning about the blast radius.
case "$session_id" in
  '' | *[!A-Za-z0-9_-]*) exit 0 ;;
esac

# Walk up to the owning `claude` process for its pid and tty. Both are needed:
# the pid to prune dead sessions, the tty to focus the right tab.
#
# The tty MUST come from the claude process, not from this hook -- Claude Code
# spawns hooks without a controlling terminal (`ps -o tty= -p $$` returns
# `??`), which silently stripped the notification's click action and made the
# banner unclickable. tty is the right correlator generally: cwd can't
# disambiguate (two sessions can share a directory, and cwd drifts as a session
# cd's around) and pids are ephemeral.
#
# One `ps` for the whole table, walked in awk. The obvious per-level loop cost
# ~15 subprocesses and dominated this hook's synchronous runtime.
# The membership test is against `ppid`, NOT `comm`, on purpose: referencing
# comm[p] auto-creates the key in awk, so testing `p in comm` would always
# succeed and turn an unresolvable pid into an infinite loop -- in the path that
# runs before every prompt. The hop cap makes that structural rather than
# incidental.
IFS=' ' read -r claude_pid tty_name <<<"$(
  ps -eo pid=,ppid=,tty=,comm= 2>/dev/null | awk -v start="$$" '
    { ppid[$1] = $2; tty[$1] = $3; comm[$1] = $4 }
    END {
      p = start
      while (p > 1 && ++hops < 64) {
        name = comm[p]; sub(/.*\//, "", name)
        if (name == "claude") { print p, tty[p]; exit }
        if (!(p in ppid)) exit
        p = ppid[p]
      }
    }'
)"

state_file="${STATE_DIR}/${session_id}"

# Log the degraded cases ONCE per session, not once per event. Sessions started
# via ClaudeCode.app rather than the terminal binary legitimately resolve a
# `claude` ancestor whose tty is `??`, so this branch is routine for them, not
# exceptional -- logging every turn would bury the failures worth seeing.
if [ -z "${claude_pid:-}" ]; then
  # Total walk failure. Worth recording: it writes pid 0, which is both
  # unclickable and unverifiable by the pruner -- the one case that can leave
  # state behind.
  tty_path=""
  [ -f "$state_file" ] || logger -t steer-agent "no claude ancestor from pid $$; session is pid-0, age-pruned only"
elif [ -z "${tty_name:-}" ] || [ "$tty_name" = "??" ]; then
  tty_path=""
  [ -f "$state_file" ] || logger -t steer-agent "no tty for claude pid ${claude_pid}; notification will not be clickable"
else
  tty_path="/dev/${tty_name}"
fi

# --- State (synchronous: cheap, and everything downstream reads it) ----------
case "$EVENT" in
  working | approval | idle | done)
    # Store the raw cwd, not a resolved project name: resolving it needs a
    # `git rev-parse` subprocess, and this path is synchronous on every prompt
    # submission. The background block resolves it only when it needs a
    # notification subtitle.
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

# --- Everything below can block. Detach it. ----------------------------------
{
  now="$(date +%s)"

  # Age of a state file in seconds, defensively.
  #
  # Two hazards, both fatal in different ways if read naively:
  #
  # 1. A MISSING stamp (a file written by an older version of this script, which
  #    persists across upgrades in ~/.cache) must read as ANCIENT, not as zero.
  #    Zero means "just happened", so such a file would count toward the gauge
  #    forever AND skip the age-based prune -- reintroducing the exact leak the
  #    timestamp was added to close.
  # 2. A NON-NUMERIC stamp is not merely wrong, it is lethal: under `set -u`,
  #    $((now - "abc")) treats abc as a variable name and EXITS THE SHELL. That
  #    happens inside this detached block before the prune loop can delete the
  #    offending file, with stderr going to /dev/null -- so the whole feature
  #    would go dark permanently and silently for every session. A cwd
  #    containing a newline is enough to produce it (cut emits one field per
  #    line, so `head -1` matters too).
  read_age() {
    local s
    s="$(cut -f5 "$1" 2>/dev/null | head -1)"
    case "${s:-}" in
      '' | *[!0-9]*) printf '%s' 999999 ;;
      *) printf '%s' $((now - s)) ;;
    esac
  }

  # Prune sessions whose owning process is gone (crash, kill -9, closed tab).
  #
  # The age sweep is scoped to files we CAN'T verify by pid (a failed ancestry
  # walk writes 0, which `kill -0` can't test -- it would signal the whole
  # process group). A blanket `find -mmin +720 -delete` was wrong: mtime only
  # advances when an event fires, and an idle session generates none by
  # definition, so it deleted live sessions that were still waiting and nothing
  # would ever re-light them.
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

  # Only states that actually want a human count toward the gauge. "working"
  # does not: a lit LED for a session that is busy and needs nothing trains you
  # to ignore the light.
  #
  # Both waiting states age out. Without that the gauge saturates: `Stop` fires
  # at the end of EVERY turn, so any session that has ever finished one sits in
  # `waiting` until SessionEnd, and five open tabs peg the bar at 5 permanently.
  # An approval also ages out separately and much sooner -- nothing signals that
  # a permission prompt was answered, so otherwise the mic LED would pulse for
  # the entire duration of whatever long-running tool it authorised.
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

  # Guard on Steer already running: `open steer://...` LAUNCHES the app when it
  # isn't, and a hook that boots an app on every prompt submission is hostile.
  # Controller-connected is deliberately NOT checked -- the only query route
  # returns via the pasteboard, and clobbering the clipboard on every hook fire
  # is worse than a no-op. With no pad the URLs no-op behind Steer's own guard.
  steer() {
    if pgrep -f "Steer Dev.app/Contents/MacOS" >/dev/null 2>&1; then
      open -g -a "$DEV_APP" "steer://$1" >/dev/null 2>&1
    elif pgrep -f "/Applications/Steer.app/Contents/MacOS" >/dev/null 2>&1; then
      open -g "steer://$1" >/dev/null 2>&1
    fi
  }

  steer "leds/${waiting}"
  if [ "$approvals" -gt 0 ]; then steer "micled/pulse"; else steer "micled/off"; fi

  # What does this event have to say? Resolved BEFORE any Apple Event, so
  # `working` and `end` -- the majority of fires -- never talk to Ghostty at
  # all. Previously both focus queries ran on every prompt submission for a
  # value that was then discarded.
  case "$EVENT" in
    approval) notify_msg="needs your approval" ;;
    done) notify_msg="finished" ;;
    idle) notify_msg="waiting on you" ;;
    *) notify_msg="" ;;
  esac
  [ -n "$notify_msg" ] || exit 0

  # Is this session's tab already in front of you?
  #
  # Only `done` is gated on this, and the distinction matters. Claude Code fires
  # `permission_prompt` ONLY after 6 seconds without keyboard interaction, and
  # `idle_prompt` when it's waiting on you -- both already mean "the human isn't
  # typing". Suppressing those on focus drops the signal in exactly the case the
  # feature exists for: you walked away and left the tab frontmost. A focused
  # tab is not a present human.
  #
  # `Stop` has no such gate -- it fires at the end of every single turn -- so
  # while you're actually watching a tab, buzzing and banner-ing each turn is
  # pure noise. That one earns the check.
  #
  # Guarded on Ghostty already running for the same reason as Steer: a bare
  # `tell application "Ghostty"` LAUNCHES it. The process comm is lowercase
  # `ghostty`, so `pgrep -x Ghostty` does not match. `with timeout` bounds the
  # Apple Event so a beachballed Ghostty can't wedge this block.
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

  # Resolve the project name here rather than in the synchronous path: from the
  # git root, so a session that `cd`s into a subdirectory doesn't rename itself
  # mid-flight (this reported "Steer" instead of "steer" after one cd).
  project="$(basename "$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${cwd:-$PWD}")")"

  case "$EVENT" in
    approval) steer "haptic/warning" ;;
    done) steer "haptic/double" ;;
    idle) steer "haptic/pulse" ;;
  esac

  # The notification is the only channel carrying identity, and clicking it
  # focuses the exact tab. `osascript display notification` cannot do this --
  # the Standard Suite has no click handler -- hence terminal-notifier.
  # -group replaces an earlier banner for the same session rather than stacking.
  # Only attach the click action when Ghostty is running AND actually owns this
  # tty. Attaching it unconditionally means a click LAUNCHES Ghostty for anyone
  # on iTerm2/Terminal.app/VS Code -- the same hostility the pgrep guards above
  # exist to prevent. Everything else (LED count, haptic, project name in the
  # banner) is terminal-agnostic and still works for them.
  can_focus=""
  if [ -n "$tty_path" ] && pgrep -f "Ghostty.app/Contents/MacOS" >/dev/null 2>&1; then
    [ "$(
      osascript <<APPLESCRIPT 2>/dev/null
with timeout of 3 seconds
  tell application "Ghostty"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with trm in terminals of t
          if (tty of trm) is "$tty_path" then return "yes"
        end repeat
      end repeat
    end repeat
  end tell
end timeout
return "no"
APPLESCRIPT
    )" = "yes" ] && can_focus=1
  fi

  if [ -n "${notify_msg:-}" ] && command -v terminal-notifier >/dev/null 2>&1; then
    if [ -n "$can_focus" ]; then
      terminal-notifier -title "Claude Code" -subtitle "$project" -message "$notify_msg" \
        -group "claude-steer-${session_id}" \
        -execute "osascript -e 'with timeout of 5 seconds' -e 'tell application \"Ghostty\" to focus (first terminal whose tty is \"${tty_path}\")' -e 'end timeout'"
    else
      terminal-notifier -title "Claude Code" -subtitle "$project" -message "$notify_msg" \
        -group "claude-steer-${session_id}"
    fi
  fi
} >/dev/null 2>&1 </dev/null &

exit 0
