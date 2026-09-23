#!/bin/bash
# Is the review stamp still written at subagent COMPLETION, not spawn?
# Opt-in (spends tokens), unlike the rest of tests/. The Agent tool backgrounds
# subagents by default, so PostToolUse(Task) fires at spawn, not completion;
# a gate keyed on it would clear before the reviewer read anything.
# tests/test-review-gate.sh asserts the WIRING; only this asserts the TIMING.
set -uo pipefail

command -v claude >/dev/null 2>&1 || {
  echo "claude CLI not found"
  exit 2
}

REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
git init -q "$REPO"
cd "$REPO" || exit 1
git config user.email t@t
git config user.name t
printf 'one\ntwo\nthree\n' >f.txt
git add -A
env -u CLAUDECODE git commit -qm "chore: base"

ARTIFACT="$REPO/.git/claude-reviewed-commits"
rm -f "$ARTIFACT"

# Must be a real parent spawning a subagent: `claude --agent X` makes X the
# main session, firing Stop rather than SubagentStop.
claude -p "Use the Task tool to launch one subagent with subagent_type \
'code-simplifier:code-simplifier' and the prompt 'Read f.txt and report its line \
count. Do not edit anything.' Wait for it, then report what it said." \
  --permission-mode acceptEdits >/dev/null 2>&1 &
AGENT=$!

EARLY=absent
for _ in 1 2 3; do
  sleep 2
  [ -f "$ARTIFACT" ] && {
    EARLY=present
    break
  }
done
wait $AGENT 2>/dev/null

echo "artifact while the agent was still running: $EARLY  (want absent)"
LATE=absent
grep -qx "$(git rev-parse HEAD)" "$ARTIFACT" 2>/dev/null && LATE=present
echo "HEAD stamped after completion: $LATE  (want present)"

[ "$EARLY" = absent ] && [ "$LATE" = present ]
rc=$?
[ $rc -eq 0 ] && echo "PASS: still written at completion" ||
  echo "FAIL: the timing invariant has changed; re-read bin/record-review"
exit $rc
