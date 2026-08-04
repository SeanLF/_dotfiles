#!/bin/bash
# Does the review record still get written at subagent COMPLETION, not at spawn?
#
# Opt-in, because it spends tokens: it drives a real headless agent. Everything
# else in tests/ is free and offline, so this is not in `just test`.
#
# The invariant it defends: the Agent tool backgrounds subagents by default, and
# for a backgrounded call the tool result is the launch confirmation, so
# PostToolUse(Task) fires at SPAWN. A gate keyed on it clears before the reviewer
# has read anything and reports green while enforcing nothing. SubagentStop is
# the completion signal. That is a fact about Claude Code, not about this repo,
# so it can change under us and the failure is silent. tests/test-review-gate.sh
# asserts the WIRING; only this asserts the TIMING.
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
# Something for the agent to have reviewed, so the recorded hash is not the
# degenerate empty digest that record-review declines to write.
printf 'four\nfive\n' >>f.txt

ARTIFACT="$REPO/.git/claude-review"
rm -f "$ARTIFACT"

# Must be a real PARENT spawning a real SUBAGENT. `claude --agent X` makes X the
# main session, which fires Stop rather than SubagentStop, so it cannot see the
# thing being tested.
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
if [ -f "$ARTIFACT" ]; then
  echo "after completion: present, $(sed -n 's/^event=//p' "$ARTIFACT")  (want SubagentStop)"
else
  echo "after completion: ABSENT  (want present)"
fi

[ "$EARLY" = absent ] && [ -f "$ARTIFACT" ] &&
  [ "$(sed -n 's/^event=//p' "$ARTIFACT")" = "SubagentStop" ]
rc=$?
[ $rc -eq 0 ] && echo "PASS: still written at completion" ||
  echo "FAIL: the timing invariant has changed; re-read bin/record-review"
exit $rc
