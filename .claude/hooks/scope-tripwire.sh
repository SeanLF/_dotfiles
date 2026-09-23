#!/bin/bash
# Warn when a fix has grown into a redesign: 5 files or 150 non-generated lines
# since HEAD, then again at each doubling.
#
# PostToolUse, so it cannot block, which is the point. An edit refused for being
# the sixth one blocks legitimate large work, and an unrecoverable block on valid
# input costs more than the sprawl it prevents. This reports the size and leaves
# the call to the agent. Fails silent on its own errors.
#
# Thresholds are per HEAD: a commit resets them, so the warning tracks the
# current change rather than the session.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

FILES_T="${SCOPE_TRIPWIRE_FILES:-5}"
LINES_T="${SCOPE_TRIPWIRE_LINES:-150}"

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$TOOL" in
  Edit | Write | MultiEdit | NotebookEdit | apply_patch) ;;
  *) exit 0 ;;
esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
DIR="$CWD"
[ -n "$FILE" ] && DIR=$(dirname "$FILE")
[ -n "$DIR" ] && [ -d "$DIR" ] || exit 0

cd "$DIR" 2>/dev/null || exit 0
PRIVATE_DIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
PRIVATE_DIR=$(cd "$PRIVATE_DIR" && pwd) || exit 0
# ls-files --others only lists below cwd; measure the whole repo.
cd "$(git rev-parse --show-toplevel)" 2>/dev/null || exit 0

# The empty tree stands in for HEAD in a repo with no commits, so the first
# change is measured rather than skipped.
HEAD=$(git rev-parse HEAD 2>/dev/null) || HEAD=""
BASE="${HEAD:-4b825dc642cb6eb9a060e54bf8d69288fbee4904}"

# Lockfiles, build output and vendored trees are changed by a command, not
# written by hand; counting them turns one `npm install` into a tripwire.
GENERATED='(^|/)(node_modules|vendor|dist|build|target|Pods|coverage|\.next|\.venv)/|(^|/)[^/]*\.min\.(js|css)$|\.map$|(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb|Cargo\.lock|Gemfile\.lock|composer\.lock|uv\.lock|poetry\.lock|go\.sum|Package\.resolved)$'

# Tracked edits. A binary file reports "-" for both counts: it is one file and
# no lines, which is what a tripwire about reviewable size should say.
read -r FILES LINES < <(
  git diff --numstat "$BASE" 2>/dev/null |
    awk -F'\t' -v gen="$GENERATED" '
      NF >= 3 {
        path = $3
        sub(/^.*=> /, "", path); sub(/}$/, "", path)
        if (path ~ gen) next
        f++
        if ($1 != "-") l += $1
        if ($2 != "-") l += $2
      }
      END { printf "%d %d\n", f + 0, l + 0 }
    '
) || exit 0

# Untracked files are the other half of an expanding change and `git diff`
# never sees them.
while IFS= read -r u; do
  [ -n "$u" ] || continue
  printf '%s' "$u" | grep -qE "$GENERATED" && continue
  FILES=$((FILES + 1))
  [ -f "$u" ] && LINES=$((LINES + $(wc -l <"$u" 2>/dev/null || echo 0)))
done < <(git ls-files --others --exclude-standard 2>/dev/null)

[ "$FILES" -ge "$FILES_T" ] || [ "$LINES" -ge "$LINES_T" ] || exit 0

# Report once per doubling: a change that keeps growing says so again, one that
# sits at six files does not repeat on every edit.
LEVEL=0 f="$FILES_T" l="$LINES_T"
while [ "$LEVEL" -lt 6 ] && { [ "$FILES" -ge $((f * 2)) ] || [ "$LINES" -ge $((l * 2)) ]; }; do
  f=$((f * 2))
  l=$((l * 2))
  LEVEL=$((LEVEL + 1))
done

STATE="$PRIVATE_DIR/claude-scope-tripwire"
LAST=$(sed -n "s/^${BASE} //p" "$STATE" 2>/dev/null)
[ -n "$LAST" ] && [ "$LEVEL" -le "$LAST" ] && exit 0
printf '%s %s\n' "$BASE" "$LEVEL" >"$STATE" 2>/dev/null

SHORT="${HEAD:0:7}"
[ -n "$SHORT" ] || SHORT="the empty tree"
MSG="scope-tripwire: $FILES files, $LINES lines changed since $SHORT (generated paths excluded).

This is a tripwire, not a limit. Before the next edit, answer two questions:
  1. Is there a smaller coherent change that solves the stated problem?
  2. Did this add an unplanned schema, queue, scheduler, state machine,
     protocol, recovery mechanism, or generic framework? If so, say so now
     rather than at commit time.
Genuinely broadening the mission needs the user's word first. If the size is
intentional and in scope, carry on and split it into reviewable commits."

jq -n --arg m "$MSG" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}' 2>/dev/null
exit 0
