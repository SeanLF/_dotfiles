#!/bin/bash
# Guard `git commit` invocations.
#
#   DENY (absolute, no hatch)
#     - message not Conventional Commits
#     - message contains emoji
#     There is no good reason to write either, so no escape hatch.
#
#   DENY (honours /tmp/claude-commit-force-<session_id>, one-shot)
#     - git commit --amend
#     - staging a plan / TODO / scratch file
#     Both are "unless I ask" rules, so asking is what the sentinel records.
#
# Only inspects `-m` messages; an editor-driven commit is lefthook's job.
# Fails OPEN on its own errors: a malformed message is cheaper than a wedged
# session. Contrast pre-commit-review.sh, which fails closed by design.
set -o pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Only git commit. Not `git commit-tree`, not a mention inside a quoted string.
STRIPPED=$(echo "$COMMAND" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")
echo "$STRIPPED" | grep -qE '(^|[;&|][[:space:]]*)[[:space:]]*git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)' || exit 0

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null
  exit 0
}

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
FORCE="/tmp/claude-commit-force-${SESSION_ID}"

# Conditional rules share the existing sentinel. Consumed on use, so a single
# touch buys exactly one commit, and it must be its own Bash call.
forced() { [ -n "$SESSION_ID" ] && [ -f "$FORCE" ]; }

# --- absolute: message shape -----------------------------------------------
MSG=$(echo "$COMMAND" | sed -n "s/.*-m[[:space:]]*'\([^']*\)'.*/\1/p; s/.*-m[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)

# The hook sees the command pre-expansion, so a message built from a variable
# or a substitution is opaque here. Validating the literal text would reject
# every `-m "$MSG"` commit. Skip rather than pretend; lefthook still sees it.
case "$MSG" in *'$'* | *'`'*) MSG="" ;; esac

if [ -n "$MSG" ]; then
  if printf '%s' "$MSG" | LC_ALL=C grep -qE $'\xf0\x9f|\xe2\x9c|\xe2\x9d|\xe2\x9a|\xe2\xad|\xe2\x9e'; then
    deny "Commit message contains an emoji. AGENTS.md: conventional, no emoji. Rewrite without it."
  fi
  if ! printf '%s' "$MSG" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: .+'; then
    deny "Commit message is not Conventional Commits: '${MSG}'. Expected '<type>(<scope>)?: <why>' with type one of feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert. AGENTS.md also asks for the why, not the what."
  fi
fi

# --- conditional: --amend ---------------------------------------------------
if echo "$STRIPPED" | grep -qE '(^|[[:space:]])--amend([[:space:]]|$)'; then
  forced && {
    rm -f "$FORCE"
    exit 0
  }
  deny "git commit --amend is disallowed unless asked (AGENTS.md). If I asked, run 'touch ${FORCE}' as its own Bash call first, then retry."
fi

# --- conditional: staged plans / TODOs / scratch ----------------------------
STAGED=$(git diff --cached --name-only 2>/dev/null)
if [ -n "$STAGED" ]; then
  OFFENDERS=$(printf '%s\n' "$STAGED" | grep -iE '(^|/)(scratch/|.*\bplan\b.*\.md$|TODO(\.md)?$|.*-plan\.md$)' | head -5)
  if [ -n "$OFFENDERS" ]; then
    forced && {
      rm -f "$FORCE"
      exit 0
    }
    deny "Staged files look like plans/TODOs/scratch, which AGENTS.md says not to commit unless asked: $(echo "$OFFENDERS" | tr '\n' ' '). Unstage them, or if I asked for them, run 'touch ${FORCE}' as its own Bash call first."
  fi
fi

exit 0
