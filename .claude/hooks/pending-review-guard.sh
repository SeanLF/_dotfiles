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
    STRIPPED=$(printf '%s' "$COMMAND" | strip_quotes)
    # A commit, or a write into the tree by any of the usual shell shapes.
    # Redirects into /tmp and /dev/null are scratch, not edits.
    if ! is_git_commit "$STRIPPED" &&
      ! printf '%s' "$STRIPPED" | grep -qE '(^|[[:space:]])(sed|perl|ruby)[[:space:]]+(-[a-zA-Z]*i|--in-place)|(^|[;&|][[:space:]]*)[[:space:]]*(tee|patch|install|truncate)([[:space:]]|$)|git[[:space:]]+apply' &&
      ! printf '%s' "$COMMAND" | grep -qE '>>?[[:space:]]*"?(\$|[^[:space:]"/])' &&
      ! printf '%s' "$COMMAND" | grep -qE '>>?[[:space:]]*"?/(Users|Volumes|opt|etc|usr)'; then
      exit 0
    fi
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
