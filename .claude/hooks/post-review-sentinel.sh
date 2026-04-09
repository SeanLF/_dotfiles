#!/bin/bash
# PostToolUse hook: set sentinel after review/simplifier agent tasks complete.
# Only fires for Task tool calls whose subagent_type matches review patterns.
set -o pipefail

if ! command -v jq &>/dev/null; then
  echo "post-review-sentinel: jq not found, cannot create review sentinel" >&2
  exit 0
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

# Only trigger for review-type agents (empty TOOL_NAME falls through to *)
case "$TOOL_NAME" in
  feature-dev:code-reviewer | \
    pr-review-toolkit:code-reviewer | \
    pr-review-toolkit:code-simplifier | \
    superpowers:code-reviewer)
    ;;
  *) exit 0 ;;
esac

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
if [ -z "$SESSION_ID" ]; then
  echo "post-review-sentinel: no session_id, cannot create sentinel" >&2
  exit 0
fi

if ! touch "/tmp/claude-review-done-${SESSION_ID}" 2>/dev/null; then
  echo "post-review-sentinel: failed to create /tmp/claude-review-done-${SESSION_ID}" >&2
  echo "Commits will be blocked. Create manually: touch /tmp/claude-review-done-${SESSION_ID}" >&2
fi

exit 0
