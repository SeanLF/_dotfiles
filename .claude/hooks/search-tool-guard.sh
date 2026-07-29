#!/bin/bash
# Guard bash-tool search commands.
#
#   DENY  rg short-flag clusters containing `r` (e.g. -rn, -nr, -riw).
#         `-r` is --replace, so it eats the next token and exits 0 with
#         rewritten text that reads like a real finding. Root cause: `grep -rn`
#         muscle memory. rg already recurses by default, so the `r` is redundant.
#         No legitimate use -> hard deny, no escape hatch.
#
#   WARN  bare `grep` / `find`, which Claude Code shadows with `ugrep -G
#         --ignore-files` and `bfs`. Non-blocking: real uses exist mid-pipeline.
#
# Fails OPEN: a search guard that blocks work on its own bugs is worse than the
# bug it guards. Contrast pre-commit-review.sh, which fails closed by design.
set -o pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null
  exit 0
}

# Records the warning; does NOT exit. Exiting here let a leading grep/find
# segment short-circuit the loop before a later `rg` segment was ever tested,
# downgrading the no-hatch deny to an advisory.
WARNING=""
warn() { WARNING="$1"; }

emit_warning() {
  [ -z "$WARNING" ] && return 0
  jq -n --arg c "$WARNING" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' \
    2>/dev/null
  echo "$WARNING" >&2
}

# Strip quoted strings, then split on command separators. Without this, merely
# *mentioning* a pattern (echo, commit message, writing these very docs) trips
# the guard. Over-splitting is safe here; it only ever costs a missed warning.
# sed is line-oriented, so fold newlines into a sentinel byte first. Without
# this a multi-line quoted string (a commit message describing these very
# rules) survives stripping and trips the guard.
SEGMENTS=$(printf '%s' "$COMMAND" |
  tr '\n' '\001' |
  sed "s/'[^']*'//g; s/\"[^\"]*\"//g" |
  tr '\001' '\n' |
  sed 's/&&/\n/g; s/||/\n/g; s/[;|]/\n/g')

while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}" # ltrim
  [ -z "$seg" ] && continue

  # --- DENY: rg short-flag cluster containing r (-rn, -nr, -riw) ----------
  # Bare `-r` with a separate replacement argument is legitimate and unmatched.
  case "$seg" in
    rg\ * | *[[:space:]]rg\ *)
      if echo "$seg" | grep -qE '(^|[[:space:]])-([a-zA-Z]+r|r[a-zA-Z]+)([[:space:]]|$)'; then
        deny "rg: -r is --replace, not --recursive. It swallows the next token and exits 0 with rewritten text that reads like a real finding. rg already recurses by default, so drop the r: use 'rg -n' (or 'rg -l', 'rg -i'). If you genuinely want --replace, pass it unbundled: rg -r 'text' pattern."
      fi
      ;;
  esac

  # --- WARN: shadowed grep / find ----------------------------------------
  case "$seg" in
    grep\ * | find\ *)
      warn "Note: bash-tool grep/find are shadowed by Claude Code (grep -> 'ugrep -G --ignore-files', find -> bfs). BRE makes + ? | { } literal, and gitignored/hidden files are skipped, so no-match does not mean absent. Prefer rg/fd; use 'rg -uu' before mutating anything, or 'command grep'/'ggrep' for real GNU behaviour."
      ;;
  esac
done <<<"$SEGMENTS"

# Deny always wins; warnings are emitted only if nothing denied.
emit_warning
exit 0
