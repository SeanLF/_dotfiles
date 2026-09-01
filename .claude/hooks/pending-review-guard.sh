#!/bin/bash
# Refuse edits and further commits while HEAD is a Claude commit no reviewer
# has seen (bin/review-gate --pending). Fails OPEN on its own errors.
set -o pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

command -v jq &>/dev/null || exit 0
GATE="${REVIEW_GATE_BIN:-$HOME/Developer/_dotfiles/bin/review-gate}"
[ -x "$GATE" ] || exit 0

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
DIR="$CWD"

case "$TOOL" in
  Bash)
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    [ -n "$COMMAND" ] || exit 0
    is_git_commit "$(printf '%s' "$COMMAND" | strip_quotes)" || exit 0
    ;;
  Edit | Write | MultiEdit | NotebookEdit)
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
    [ -n "$FILE" ] && DIR=$(dirname "$FILE")
    ;;
  *) exit 0 ;;
esac

[ -n "$DIR" ] && [ -d "$DIR" ] || exit 0
REASON=$(cd "$DIR" && "$GATE" --pending 2>&1 >/dev/null) && exit 0

jq -n --arg r "$REASON" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
  2>/dev/null ||
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"pending-review-guard: HEAD is unreviewed and the reason could not be rendered"}}'
exit 0
