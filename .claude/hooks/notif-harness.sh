#!/usr/bin/env bash
#
# Hermetic before/after harness for the Claude notification stack.
#
#   .claude/hooks/notif-harness.sh
#
# Runs steer-agent.sh for every event with a shimmed PATH and an isolated state
# dir, so nothing reaches the real Notification Centre, Steer, or Ghostty. What
# it reports is what the delegation is supposed to change:
#
#   spawns   external processes the hook starts per event (the glue)
#   sync ms  what actually blocks your prompt on UserPromptSubmit
#   registry where session state lives, and how much of it is stale
#
# Shims stand in for the things that would otherwise have side effects. pgrep
# answers "yes, running" so the full path is exercised rather than short-
# circuited; osascript distinguishes the two AppleScript queries by their text
# so `done` is not silently suppressed by a fake focus hit.

set -uo pipefail

# Beside this file, not under $HOME, so a fresh checkout measures the hook in
# the repo rather than whatever version happens to be installed.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOOK="${HOOK:-$_here/steer-agent.sh}"
# 'done' is quoted: unquoted it parses as the loop keyword, not an array element.
readonly EVENTS=(working approval idle 'done' end)
readonly RUNS="${RUNS:-5}"

work="$(mktemp -d)"
# Without this, a failed mktemp leaves work empty and every "$work/bin/$tool"
# below resolves to /bin/$tool, i.e. the shim loop tries to overwrite /bin/open.
# SIP happens to block that on a stock Mac; this script must not rely on it.
[ -d "$work" ] || {
  echo "mktemp -d failed" >&2
  exit 1
}
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/state"
readonly LOG="$work/spawns.log"
readonly OSC="$work/osc.out"
: >"$LOG"
: >"$OSC"

for tool in osascript terminal-notifier open pgrep logger; do
  cat >"$work/bin/$tool" <<SHIM
#!/usr/bin/env bash
printf '%s\t%s\n' "$tool" "\$*" >>"$LOG"
case "$tool" in
  # Emit a pid that still EXISTS when the hook reads it: the hook now resolves
  # the executable path off the pid, and \$\$ here is the shim, already reaped by
  # then -- which silently measured the Steer-is-down path instead. pid 1 is
  # always alive and resolves to launchd, exercising the release-app branch.
  pgrep) echo 1; exit 0 ;;
  osascript)
    # One AppleScript call survives in the hook, the focus probe. Answer "no" so
    # a fake focus hit cannot suppress \`done\`. The old two-branch shim named a
    # tty-walk query that no longer exists.
    echo no
    ;;
esac
exit 0
SHIM
  chmod +x "$work/bin/$tool"
done

payload() { printf '{"session_id":"harness-%s","cwd":"%s"}' "$1" "$PWD"; }

run_hook() {
  PATH="$work/bin:$PATH" \
    STEER_AGENT_STATE_DIR="$work/state" \
    STEER_AGENT_TTY="$OSC" \
    "$HOOK" "$1" <<<"$(payload "$1")" >/dev/null 2>&1
}

echo "=== static ==="
printf 'hook LOC          %s\n' "$(grep -c '' "$HOOK")"
printf 'osascript blocks  %s\n' "$(sed 's/#.*//' "$HOOK" | grep -c 'osascript')"
# Strip comments first: after the OSC swap the word "terminal-notifier" survives
# in a comment explaining why it left, and counting that as a dependency would
# report a removal that did happen as one that didn't.
printf 'external deps     %s\n' \
  "$(sed 's/#.*//' "$HOOK" | grep -oE 'terminal-notifier|osascript|open -g|pgrep' | sort -u | paste -sd, -)"

echo
echo "=== per-event spawns (shimmed, no side effects) ==="
for ev in "${EVENTS[@]}"; do
  : >"$LOG"
  run_hook "$ev"
  # The hook detaches its slow half, so the shims land after it exits.
  for _ in $(seq 40); do
    before="$(grep -c '' "$LOG")"
    sleep 0.1
    [ "$(grep -c '' "$LOG")" = "$before" ] && break
  done
  printf '%-9s %s spawn(s)  %s\n' "$ev" "$(grep -c '' "$LOG")" \
    "$(cut -f1 "$LOG" | sort | uniq -c | sort -rn | awk '{printf "%s×%s ", $1, $2}')"
done

echo
echo "=== synchronous cost (what blocks your prompt), best of $RUNS ==="
best=99999
for _ in $(seq "$RUNS"); do
  start="$(python3 -c 'import time; print(int(time.time()*1000))')"
  run_hook working
  end="$(python3 -c 'import time; print(int(time.time()*1000))')"
  ms=$((end - start))
  [ "$ms" -lt "$best" ] && best="$ms"
done
printf 'UserPromptSubmit  %s ms\n' "$best"

echo
echo "=== notification bytes written to the session target ==="
if [ -s "$OSC" ]; then
  od -c "$OSC" | head -4
else
  echo "(none: display went through a subprocess, not the terminal)"
fi

echo
echo "=== live registry ==="
real="$HOME/.cache/claude-steer-sessions"
if [ -d "$real" ]; then
  total=0
  stale=0
  for f in "$real"/*; do
    [ -e "$f" ] && total=$((total + 1))
  done
  for f in "$real"/*; do
    [ -e "$f" ] || continue
    pid="$(cut -f4 "$f" 2>/dev/null | head -1)"
    case "${pid:-}" in
      '' | 0 | *[!0-9]*) stale=$((stale + 1)) ;;
      *) kill -0 "$pid" 2>/dev/null || stale=$((stale + 1)) ;;
    esac
  done
  printf 'backend           %s (TSV files)\n' "$real"
  printf 'rows              %s (%s with a dead or unverifiable owner)\n' "$total" "$stale"
else
  printf 'backend           %s\n' "no state dir"
fi
if command -v ccpool >/dev/null 2>&1 && ccpool session list >/dev/null 2>&1; then
  printf 'ccpool sessions   %s\n' "$(ccpool session list 2>/dev/null | grep -c '')"
else
  printf 'ccpool sessions   (no session verb)\n'
fi
