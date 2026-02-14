#!/bin/bash
# Gate: remind Claude to run review + simplifier agents before committing.
# Returns deny on git commit if there are staged changes, so Claude
# evaluates whether agents have already been run this session.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only trigger on git commit commands
if ! echo "$COMMAND" | grep -q 'git commit'; then
  exit 0
fi

# Check if there are staged changes worth reviewing
STAGED=$(git diff --cached --stat 2>/dev/null | tail -1)
if [ -z "$STAGED" ]; then
  exit 0
fi

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "CLAUDE.md requires running review + simplifier agents before committing. If already done this session, retry the commit."
  }
}'
