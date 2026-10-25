#!/bin/bash
# Guards bash-tool search commands: denies `rg -r*` clusters (--replace
# masquerading as --recursive) and warns on in-place sed/perl/ruby -i.
# Fails OPEN: contrast pre-commit-review.sh, which fails closed by design.
set -o pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

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

# Records the warning without exiting, so a later `rg` segment is still
# tested.
WARNING=""
warn() { WARNING=$1; }

emit_warning() {
  [ -z "$WARNING" ] && return 0
  jq -n --arg c "$WARNING" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' \
    2>/dev/null
  echo "$WARNING" >&2
}

# Strip quoted strings first, or merely *mentioning* a pattern trips the guard.
SEGMENTS=$(printf '%s' "$COMMAND" | strip_quotes |
  sed 's/&&/\n/g; s/||/\n/g; s/[;|]/\n/g')

while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}" # ltrim
  [ -z "$seg" ] && continue

  # Bare `-r` with a separate replacement argument is legitimate and unmatched.
  case "$seg" in
    rg\ * | *[[:space:]]rg\ *)
      CLUSTER=$(printf '%s' "$seg" | grep -oE '(^|[[:space:]])-[a-zA-Z]*r[a-zA-Z]*([[:space:]]|$)' | head -1 | tr -d '[:space:]')
      # A trailing `r` that follows a value-taking flag is that flag's argument,
      # not --replace. `rg -tr` is `--type r` (R sources) and is a valid command.
      BEFORE="${CLUSTER%%r*}"
      LASTCH="${BEFORE#"${BEFORE%?}"}"
      if [ -n "$CLUSTER" ] && [ "$CLUSTER" != "-r" ] &&
        ! printf '%s' "$LASTCH" | grep -qE '[AaBCefgmMtT]'; then
        deny "rg: -r is --replace, not --recursive. It swallows the next token and exits 0 with rewritten text that reads like a real finding. rg already recurses by default, so drop the r: use 'rg -n' (or 'rg -l', 'rg -i'). If you genuinely want --replace, pass it unbundled: rg -r 'text' pattern."
      fi
      ;;
  esac

  # Every cluster holding an `i` is examined, not just the first: `perl -Ilib
  # -pi -e` has a decoy cluster before the real one. Allows a path or `g`
  # prefix too, or `gsed`/`/usr/bin/sed` would be missed.
  TOOL=$(printf '%s' "$seg" |
    grep -oE '(^|[[:space:]])([^[:space:]]*/)?g?(sed|perl|ruby)([[:space:]]|$)' |
    head -1 | grep -oE 'sed|perl|ruby')
  if [ -n "$TOOL" ]; then
    # Value-taking flags are per-tool: `r` takes a value for ruby (-rnokogiri)
    # but is a bare toggle for sed.
    case "$TOOL" in
      sed) VALFLAGS='ef' ;;
      perl) VALFLAGS='eEIMmFxCSD' ;;
      *) VALFLAGS='eIrCEFKSxT' ;;
    esac
    INPLACE=""
    CLUSTERS=$(printf '%s' "$seg" |
      grep -oE '(^|[[:space:]])-[a-zA-Z0-9.]*i[a-zA-Z0-9.]*' | tr -d ' \t')
    while IFS= read -r cl; do
      [ -z "$cl" ] && continue
      # A value-taking flag before the `i` means the `i` is inside that flag's
      # value, not a toggle.
      printf '%s' "${cl%%i*}" | grep -q "[$VALFLAGS]" && continue
      INPLACE=1
      break
    done <<<"$CLUSTERS"
    if [ -n "$INPLACE" ] ||
      printf '%s' "$seg" | grep -qE '(^|[[:space:]])--in-?place([[:space:]=]|$)'; then
      warn "Note: sed/perl/ruby -i rewrite in place and exit 0 even when the pattern matched nothing, so an edit that never applied looks identical to one that did. Prefer the Edit tool, which errors on no match. If you need the in-place form (bulk or multi-file), verify it landed -- re-read or diff the file -- rather than assuming."
    fi
  fi

done <<<"$SEGMENTS"

# Deny always wins; warnings are emitted only if nothing denied.
emit_warning
exit 0
