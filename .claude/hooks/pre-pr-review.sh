#!/bin/bash
# Gate: enforce the pre-PR/publish self-review before `git push` or `gh pr create`.
# Surfaces the AGENTS.md self-review checks at the publish moment and blocks until
# they've been run. Fails closed: any unexpected state denies.
#
# Escape hatch (one-shot, consumed on use):
#   /tmp/claude-pr-review-done-<session_id> -- touch AFTER running the self-review
#
# Does NOT gate plain `git commit` (that has its own pre-commit-review.sh gate).
set -o pipefail

DENY_FALLBACK='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"pre-pr-review: hook error, denying as safety measure"}}'

deny() {
  local reason="${1:-pre-PR self-review not yet run}"
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

# Only trigger on `git push` or `gh pr create` (start of command or after a ; & | separator).
if ! echo "$COMMAND" | grep -qE '(^|[;&|])[[:space:]]*(git[[:space:]]+([^[:space:]]+[[:space:]]+)*push|gh[[:space:]]+pr[[:space:]]+create)([[:space:]]|$)'; then
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || deny "failed to parse session_id"
if [ -z "$SESSION_ID" ]; then
  deny "no session_id in hook input; cannot verify review status"
fi

MARKER="/tmp/claude-pr-review-done-${SESSION_ID}"
if [ -f "$MARKER" ]; then
  rm "$MARKER" 2>/dev/null || deny "marker exists but cannot be removed; check permissions on $MARKER"
  exit 0
fi

deny "Pre-PR self-review not run (AGENTS.md). Before this push/PR, confirm: (1) re-ran it the way a user invokes it and every claim in docs/output is true — no version/compat/consumer asserted from memory; (2) no best-effort/cosmetic path can crash or corrupt the primary job; (3) for any heuristic, checked the authoritative tool/spec before hand-rolling. Then, in a SEPARATE Bash call first (PreToolUse fires before the command runs): touch ${MARKER} — and re-issue. [session: ${SESSION_ID}]"
