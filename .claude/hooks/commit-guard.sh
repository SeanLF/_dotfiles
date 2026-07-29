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

# TEST the sentinel, never consume it. pre-commit-review.sh owns the rm; if
# both hooks consumed it, one touch would satisfy one gate and the other would
# still deny, with no way to satisfy both. That was a livelock.
forced() { [ -n "$SESSION_ID" ] && [ -f "$FORCE" ]; }

# --- absolute: message shape -----------------------------------------------
# Fold newlines so a multi-line body is reachable, then take the FIRST message
# flag. A greedy match takes the LAST -m, which validates the body against the
# subject regex and rejects every standard subject+body commit.
# Truncate at the first heredoc marker: everything after `<<` is data, not
# flags. Without this, a commit body that merely mentions -m or -am is scanned
# as if it were the invocation.
FOLDED=$(printf '%s' "${COMMAND%%<<*}" | tr '\n' '\001')
REST=""
case "$FOLDED" in
  *' --message='*) REST="${FOLDED#* --message=}" ;;
  *' -m '*) REST="${FOLDED#* -m }" ;;
  *' -am '*) REST="${FOLDED#* -am }" ;;
  *' -ma '*) REST="${FOLDED#* -ma }" ;;
esac

MSG=""
case "$REST" in
  \'*)
    MSG="${REST#\'}"
    MSG="${MSG%%\'*}"
    ;;
  \"*)
    MSG="${REST#\"}"
    MSG="${MSG%%\"*}"
    ;;
  ?*) MSG="${REST%% *}" ;;
esac

# The hook sees the command pre-expansion, so a message built from a variable
# or a substitution is opaque here. Validating the literal text would reject
# every `-m "$MSG"` commit. Skip rather than pretend; lefthook still sees it.
case "$MSG" in *'$'* | *'`'*) MSG="" ;; esac

if [ -n "$MSG" ]; then
  # Emoji can appear anywhere; Conventional Commits governs the subject only.
  SUBJECT="${MSG%%$'\001'*}"
  if printf '%s' "$MSG" | grep -qP '[\x{1F000}-\x{1FAFF}\x{2190}-\x{2BFF}\x{2600}-\x{27BF}\x{FE0F}\x{1F1E6}-\x{1F1FF}]' 2>/dev/null ||
    printf '%s' "$MSG" | LC_ALL=C grep -qE $'\xf0\x9f|\xe2\x9c|\xe2\x9d|\xe2\x9a|\xe2\xad|\xe2\x9e|\xe2\x8f|\xe2\x80\xbc'; then
    deny "Commit message contains an emoji. AGENTS.md: conventional, no emoji. Rewrite without it."
  fi
  case "$SUBJECT" in
    fixup!* | squash!* | Revert\ * | Merge\ *) ;; # git's own generated forms
    *)
      if ! printf '%s' "$SUBJECT" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: .+'; then
        deny "Commit message is not Conventional Commits: '${SUBJECT}'. Expected '<type>(<scope>)?: <why>' with type one of feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert. AGENTS.md also asks for the why, not the what."
      fi
      ;;
  esac
fi

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
