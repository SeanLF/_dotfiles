#!/bin/bash
# Gate: remind Claude to run review + simplifier agents before committing.
# Fails closed: any unexpected state (missing jq, malformed input) denies.
#
# Sentinels (one-shot, consumed on use):
#   /tmp/claude-review-done-<session_id>  -- created by post-review-sentinel.sh
#   /tmp/claude-commit-force-<session_id> -- manual escape hatch for squash/rebase
set -o pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

DENY_FALLBACK='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"pre-commit-review: hook error, denying as safety measure"}}'

deny() {
  local reason="${1:-review agents not yet run}"
  jq -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null || echo "$DENY_FALLBACK"
  exit 0
}

if ! command -v jq &>/dev/null; then
  echo "$DENY_FALLBACK"
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty') || deny "failed to parse hook input"

# Only trigger on git commit commands
if ! is_git_commit "$(printf '%s' "$COMMAND" | strip_quotes)"; then
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || deny "failed to parse session_id"
if [ -z "$SESSION_ID" ]; then
  deny "no session_id in hook input; cannot verify review status"
fi

SENTINEL="/tmp/claude-review-done-${SESSION_ID}"
FORCE="/tmp/claude-commit-force-${SESSION_ID}"

# Review sentinel: created by post-review hook, one commit per review cycle
if [ -f "$SENTINEL" ]; then
  rm "$SENTINEL" 2>/dev/null || deny "sentinel exists but cannot be removed; check permissions on $SENTINEL"
  exit 0
fi

# Force sentinel: escape hatch for squash/rebase where review already happened.
# Create with: touch /tmp/claude-commit-force-<session_id>
if [ -f "$FORCE" ]; then
  rm "$FORCE" 2>/dev/null || deny "force sentinel exists but cannot be removed; check permissions on $FORCE"
  exit 0
fi

STAGED_N=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
SCOPE="${STAGED_N} file(s) staged."
if [ "${STAGED_N:-0}" -gt 3 ]; then
  SCOPE="${STAGED_N} files staged, which is over the 3-file threshold: run the review, no exceptions."
fi

deny "Review gate. ${SCOPE}

Running any ONE of these clears the gate (exact subagent_type, the prefix matters):
  pr-review-toolkit:code-reviewer
  pr-review-toolkit:code-simplifier
  pr-review-toolkit:silent-failure-hunter   <- if error handling changed
  code-simplifier:code-simplifier
  feature-dev:code-reviewer
Any other name, including superpowers:code-reviewer, does not exist or does not clear it.   adversarial-reviewer                      <- refutes rather than confirms; worth running last

To skip for a trivial or purely mechanical change, run EXACTLY this as its own Bash call, then retry the commit:

  touch ${FORCE}

It must be a separate call: this hook fires before your command runs, so 'touch ... && git commit' always denies. The marker is consumed on use, so re-touch after any pre-commit failure (prettier rewrite, lefthook)."
