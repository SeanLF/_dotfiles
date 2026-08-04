#!/bin/bash
# Deny any attempt to skip git's own hooks.
#
# The review gate lives in the git pre-commit hook now, which is what makes its
# detection exact, but it also puts it behind flags and env vars the model can
# set. This is the one part that has to stay at the tool boundary. Upstream has
# no fix: anthropics/claude-code#40117 landed six commits past a hook this way
# and was closed as a duplicate.
#
# Everything here is a switch that turns a git hook off, which is why they are
# all denied absolutely with no hatch. The gate prints its own hatch, and that
# hatch survives a failed commit, so there is never a reason to reach for these.
#
# Deliberately narrow: "does this command carry a hook-disabling switch" is a far
# more robust question than "is this a commit", and a miss only skips a review
# where a false positive would wedge the session. So it fails OPEN.
set -o pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0
STRIPPED=$(printf '%s' "$COMMAND" | strip_quotes)

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null ||
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"hook-bypass-guard: could not render the reason; denying rather than silently allowing"}}'
  exit 0
}

HATCH="The review gate prints a one-line hatch of its own if the change is genuinely trivial. Use that instead."

# This hook runs on EVERY Bash call, not just git ones. It has to: the form most
# worth catching, `CLAUDECODE=0 git commit`, does not match a `Bash(git *)`
# filter, so the filter had to come off.
#
# Every rule below therefore runs PER SEGMENT, not over the whole command. A
# whole-string test is wrong in both directions and we shipped both: a stray
# `ls -l` anywhere disarmed an exemption, and a stray `git status` anywhere
# re-armed a git rule over the unrelated half, so `git log && rg core.hooksPath`
# was denied. Splitting first makes each rule judge only the command it is about.
# A trailing backslash is a line CONTINUATION, not a separator. Splitting
# without folding first put `git` in one segment and `--no-verify` in the next,
# so every git-scoped rule missed a command the old whole-string version caught.
# A model formatting a long git invocation writes these routinely.
SEGMENTS=$(printf '%s' "$STRIPPED" |
  awk '{ if (sub(/\\$/, "")) printf "%s", $0; else print }' |
  sed -E 's/(\|\||&&|[;&|])/\
/g')

# NAME as the COMMAND WORD of a segment: past a leading `(` or `{`, any VAR=val
# assignments, and the usual wrappers, with a leading path stripped.
#
# Command position, not "appears anywhere". `grep -n chmod file` is not a chmod,
# and `rg -c core.hooksPath git` is a search of the git/ directory, not a git
# invocation. Both were denied when this only asked whether the word was present.
#
# Known gap: wrapper OPTIONS and ARGUMENTS are not skipped, so `sudo -u me git`
# reads as sudo, and `timeout 30 git` reads as timeout. `time` is listed because
# it takes no argument; `timeout` is not, because every real spelling of it
# carries a duration and would slip anyway. Accepted: this file is a speed bump,
# and erring toward allow is the documented direction.
# $2 MUST stay parenthesized. ERE alternation binds loosest, so an unwrapped
# `export|declare|typeset` split the whole pattern into four top-level branches
# and only the first kept the `^` anchor: the rest became unanchored substring
# matches, and `rg -e declare -e CLAUDECODE .claude/hooks/` was denied.
seg_command_is() {
  printf '%s' "$1" | grep -qE "^[[:space:]]*[({]*[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((sudo|command|xargs|nohup|time)[[:space:]]+)*([^[:space:]]*/)?($2)([[:space:]]|$)"
}

while IFS= read -r seg; do
  [ -z "$seg" ] && continue

  # git's parse-options takes any unambiguous prefix. `--no-v` is NOT one of
  # them (git: "ambiguous option: no-v (could be --no-verbose or --no-verify)"),
  # so the shortest that means verify is --no-veri. Matching --no-v* denied the
  # perfectly ordinary `git commit --no-verbose`.
  if seg_command_is "$seg" git && printf '%s' "$seg" | grep -qE '(^|[[:space:]])--no-veri[a-z]*([[:space:]]|$)'; then
    deny "--no-verify skips the git hooks, which is where the review gate, lefthook and check-commit-msg all live. ${HATCH}"
  fi

  # core.hooksPath is the whole hooks directory, so pointing it anywhere else
  # disables every hook at once. Needs `git config` or `git -c` to be a write:
  # `rg core.hooksPath` is how you read these hooks, and `git grep core.hooksPath`
  # searches for them.
  if seg_command_is "$seg" git && printf '%s' "$seg" | grep -q 'core\.hooksPath' &&
    printf '%s' "$seg" | grep -qE '(^|[[:space:]])(config|-c)([[:space:]]|$)|-c[[:space:]]*core\.hooksPath' &&
    ! printf '%s' "$seg" | grep -qE '(^|[[:space:]])--(get|get-all|get-regexp|get-urlmatch|list)([[:space:]]|$)' &&
    ! printf '%s' "$seg" | grep -qE 'core\.hooksPath[[:space:]]*$'; then
    deny "Writing core.hooksPath disables every git hook at once, including the review gate and check-commit-msg. ${HATCH}"
  fi

  # The gate's own knobs, as a command PREFIX rather than anywhere on the line,
  # so `rg CLAUDECODE=0 docs/` stays a search. CLAUDECODE=1 is the value it
  # already has, so it turns nothing off and stays available for diagnostics.
  # `export CLAUDECODE=0` and `declare -x CLAUDECODE=0` put the assignment past
  # the command word, so the prefix anchor alone missed the most obvious spelling
  # of the very thing this rule is named for.
  if { printf '%s' "$seg" | grep -qE '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*CLAUDECODE[[:space:]]*=' ||
    { seg_command_is "$seg" 'export|declare|typeset|setenv|env' && printf '%s' "$seg" | grep -qE 'CLAUDECODE[[:space:]]*='; }; } &&
    ! printf '%s' "$seg" | grep -qE '(^|[[:space:]])CLAUDECODE=1([[:space:]]|$)'; then
    deny "Setting CLAUDECODE to anything but 1 turns the review gate off. ${HATCH}"
  fi

  # `-u` alone is far too common to match bare: it is ripgrep's --unrestricted,
  # so `rg -u CLAUDECODE` (searching for the variable) was denied. Require the
  # clearing idioms themselves.
  #
  # The `env -...i...` arm is pinned to env's OWN option slot, immediately after
  # the command word, or it catches every `-i` on whatever env wraps: `env FOO=1
  # rg -i pattern` and `env LC_ALL=C sed -i` were both denied. And `i` may sit
  # anywhere in the bundle, not last: `-[a-zA-Z]*i` caught `env -ui` but let
  # `env -iu CLAUDECODE` through, which clears the environment just the same.
  if printf '%s' "$seg" | grep -qE '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*REVIEW_GATE_BIN[[:space:]]*=' ||
    (seg_command_is "$seg" env && printf '%s' "$seg" | grep -qE "(-u[[:space:]]+(CLAUDECODE|REVIEW_GATE_BIN)|(^|[[:space:]])env[[:space:]]+-[a-zA-Z]*i[a-zA-Z]*([[:space:]]|\$))") ||
    (seg_command_is "$seg" unset && printf '%s' "$seg" | grep -qE '(CLAUDECODE|REVIEW_GATE_BIN)'); then
    deny "CLAUDECODE and REVIEW_GATE_BIN are what the review gate keys on, so setting or clearing either turns the gate off. ${HATCH}"
  fi

  # Making the gate non-executable makes pre-commit take its not-installed
  # branch and fail open in silence.
  if seg_command_is "$seg" chmod && printf '%s' "$seg" | grep -qE 'review-gate|record-review'; then
    deny "Changing the mode on review-gate or record-review disables the gate silently. ${HATCH}"
  fi

  # -n means --no-verify on commit, but --dry-run on push, so this is
  # commit-only. Matches bundled short flags too: `git commit -nm "msg"`.
  # Per-segment matters most here: `rg -n TODO && git commit -m x` was denied,
  # and -n is on rg, head, tail, sort and git log.
  if is_git_commit "$seg" &&
    printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
    deny "git commit -n is --no-verify and skips the git hooks. ${HATCH}"
  fi
done <<EOF
$SEGMENTS
EOF

exit 0
