#!/bin/bash
# Guard `git commit` invocations.
#
#   DENY (honours /tmp/claude-commit-force-<session_id>, one-shot)
#     - git commit --amend
#     - staging a plan / TODO / scratch file
#
# Both are "unless I ask" rules, which is why they live here rather than in a git
# hook: git can see the commit, but only this side knows whether I asked for it.
# Everything git can judge for itself has moved to git. Message shape is in
# bin/check-commit-msg via commit-msg, the review gate is in bin/review-gate via
# pre-commit.
#
# Fails OPEN on its own errors: a missed amend is cheaper than a wedged session.
set -o pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Only git commit. Not `git commit-tree`, not a mention inside a quoted string.
STRIPPED=$(printf '%s' "$COMMAND" | strip_quotes)
is_git_commit "$STRIPPED" || exit 0

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null ||
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"commit-guard: could not render the reason; denying rather than silently allowing"}}'
  exit 0
}

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
FORCE="/tmp/claude-commit-force-${SESSION_ID}"

# TEST the sentinel, never consume it: this guard can deny twice in one commit
# (amend and a staged plan), and consuming on the first would leave the second
# unsatisfiable. Nothing else reads this file. The review gate's hatch is a
# separate marker in $GIT_DIR, cleared by git/hooks/post-commit.
forced() { [ -n "$SESSION_ID" ] && [ -f "$FORCE" ]; }

# Message shape is not checked here. bin/check-commit-msg enforces conventional
# and no-emoji from the global commit-msg hook, for every commit rather than only
# the ones the agent makes, and it sees the final message rather than guessing at
# it from an unexpanded shell string.

# --- conditional: --amend ---------------------------------------------------
if echo "$STRIPPED" | grep -qE '(^|[[:space:]])--amend([[:space:]]|$)'; then
  forced && exit 0
  deny "git commit --amend is disallowed unless asked (AGENTS.md). If I asked, run 'touch ${FORCE}' as its own Bash call first, then retry."
fi

# --- conditional: staged plans / TODOs / scratch ----------------------------
# -a/-am stage at commit time, after this hook runs, so the index looks
# empty and the scan would pass a commit that sweeps in exactly these files.
STAGED=$(git diff --cached --name-only 2>/dev/null)
if printf '%s' "$STRIPPED" | grep -qE '(^|[[:space:]])-[a-zA-Z]*a[a-zA-Z]*([[:space:]]|$)|--all([[:space:]]|$)'; then
  STAGED="${STAGED}
$(git diff --name-only 2>/dev/null)"
fi
if [ -n "$STAGED" ]; then
  OFFENDERS=$(printf '%s\n' "$STAGED" | grep -iE '(^|/)(scratch/|plans?/|plan\.md$|.*[-_]plan\.md$|TODO(\.md)?$)' | head -5)
  if [ -n "$OFFENDERS" ]; then
    forced && exit 0
    deny "Staged files look like plans/TODOs/scratch, which AGENTS.md says not to commit unless asked: $(echo "$OFFENDERS" | tr '\n' ' '). Unstage them, or if I asked for them, run 'touch ${FORCE}' as its own Bash call first."
  fi
fi

exit 0
