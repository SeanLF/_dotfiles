#!/bin/bash
# .claude/hooks/scope-tripwire.sh warns once a change crosses 5 files or 150
# non-generated lines since HEAD, stays quiet below that, and never blocks.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$ROOT/.claude/hooks/scope-tripwire.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
PASS=0 FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf '  \033[32mPASS\033[0m %s\n' "$1"
}
no() {
  FAIL=$((FAIL + 1))
  printf '  \033[31mFAIL\033[0m %s\n' "$1"
}
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want $3, got $2)"; fi; }

payload() { # $1 repo dir, $2 edited file
  jq -cn --arg d "$1" --arg f "$2" \
    '{hook_event_name:"PostToolUse",session_id:"s",cwd:$d,tool_name:"Edit",tool_input:{file_path:$f}}'
}

# Returns the additionalContext the hook emitted, or "" for silence. $1 is the
# binary under test so the negative control can swap it out.
fire() { # $1 binary, $2 repo, $3 file
  payload "$2" "$3" | (cd "$2" && "$1") 2>/dev/null |
    jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}
fired() { [ -n "$(fire "$@")" ] && echo yes || echo no; }

# The sandbox inherits this machine's git hooks. Conventional subjects keep
# check-commit-msg from rejecting the fixture (a rejected base commit leaves no
# HEAD, and the hook then measures against the empty tree), and clearing the
# harness markers keeps the review gate from gating a throwaway repo.
sandbox_commit() { env -u CLAUDECODE -u CODEX_THREAD_ID git commit -q -m "$1"; }

new_repo() { # $1 name
  local d="$SANDBOX/$1"
  git init -q "$d"
  (
    cd "$d" || exit 1
    git config user.email t@t
    git config user.name t
    echo base >seed.txt
    git add -A
    sandbox_commit "chore: seed the sandbox"
  ) >/dev/null 2>&1
  printf '%s' "$d"
}
edit_files() { # $1 repo, $2 count, $3 lines each
  local i
  for ((i = 1; i <= $2; i++)); do
    seq 1 "$3" >"$1/f$i.txt"
  done
  (cd "$1" && git add -A)
}

echo "=== negative control ==="
# Prove the harness can fail before trusting a PASS. A hook that only ever exits
# 0 is indistinguishable from a working one unless `fired` can return "no" for a
# case that should fire.
R=$(new_repo control)
edit_files "$R" 8 5
check "a silent binary is reported as not firing" "$(fired /usr/bin/true "$R" "$R/f1.txt")" no
check "the real hook fires on the same tree" "$(fired "$HOOK" "$R" "$R/f1.txt")" yes

echo
echo "=== thresholds ==="
R=$(new_repo small)
edit_files "$R" 2 10
check "2 files, 20 lines: silent" "$(fired "$HOOK" "$R" "$R/f1.txt")" no

R=$(new_repo manyfiles)
edit_files "$R" 5 1
check "5 files: fires on the file count alone" "$(fired "$HOOK" "$R" "$R/f1.txt")" yes

R=$(new_repo manylines)
edit_files "$R" 1 200
check "1 file, 200 lines: fires on the line count alone" "$(fired "$HOOK" "$R" "$R/f1.txt")" yes

R=$(new_repo counts)
edit_files "$R" 6 30
OUT=$(fire "$HOOK" "$R" "$R/f1.txt")
check "the message names the file count" "$(printf '%s' "$OUT" | grep -c '6 files')" 1
check "the message calls itself a tripwire, not a limit" \
  "$(printf '%s' "$OUT" | grep -c 'not a limit')" 1

echo
echo "=== what does not count ==="
R=$(new_repo generated)
mkdir -p "$R/node_modules/x" "$R/dist"
for f in package-lock.json yarn.lock Cargo.lock go.sum dist/app.min.js dist/app.js.map node_modules/x/a.js; do
  seq 1 100 >"$R/$f"
done
(cd "$R" && git add -Af)
check "lockfiles, dist and node_modules do not trip it" "$(fired "$HOOK" "$R" "$R/package-lock.json")" no

R=$(new_repo untracked)
edit_files "$R" 6 30
(cd "$R" && git reset -q)
check "untracked files count too" "$(fired "$HOOK" "$R" "$R/f1.txt")" yes
R=$(new_repo untracked-elsewhere)
edit_files "$R" 6 30
(cd "$R" && git reset -q)
mkdir -p "$R/sub" && echo x >"$R/sub/g.txt"
check "untracked files outside the edited file's directory count" "$(fired "$HOOK" "$R" "$R/sub/g.txt")" yes

echo
echo "=== it reports once, and again on doubling ==="
R=$(new_repo repeat)
edit_files "$R" 6 10
check "first crossing reports" "$(fired "$HOOK" "$R" "$R/f1.txt")" yes
check "second edit at the same size is silent" "$(fired "$HOOK" "$R" "$R/f1.txt")" no
edit_files "$R" 11 10
check "doubling reports again" "$(fired "$HOOK" "$R" "$R/f1.txt")" yes
edit_files "$R" 12 10
check "past a reported doubling, silent again" "$(fired "$HOOK" "$R" "$R/f1.txt")" no

R=$(new_repo committed)
edit_files "$R" 6 10
check "fires before the commit" "$(fired "$HOOK" "$R" "$R/f1.txt")" yes
(cd "$R" && git add -A && sandbox_commit "chore: land the work") >/dev/null 2>&1
edit_files "$R" 1 5
check "a commit resets the count" "$(fired "$HOOK" "$R" "$R/f1.txt")" no

echo
echo "=== it never blocks and never crashes ==="
R=$(new_repo shape)
edit_files "$R" 8 40
OUT=$(payload "$R" "$R/f1.txt" | (cd "$R" && "$HOOK") 2>/dev/null)
check "output is valid JSON" "$(printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && echo yes || echo no)" yes
check "output carries no permissionDecision" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"')" none
check "hookEventName is PostToolUse" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName')" PostToolUse
payload "$R" "$R/f1.txt" | (cd "$R" && "$HOOK") >/dev/null 2>&1
check "exit status is 0 when it fires" "$?" 0

OUT=$(
  jq -cn '{hook_event_name:"PostToolUse",cwd:"/nonexistent",tool_name:"Edit",tool_input:{file_path:"/nonexistent/a.txt"}}' | "$HOOK" 2>/dev/null
  echo "rc=$?"
)
check "a path outside any repo is silent and exits 0" "$OUT" "rc=0"
OUT=$(
  printf 'not json' | "$HOOK" 2>/dev/null
  echo "rc=$?"
)
check "malformed input is silent and exits 0" "$OUT" "rc=0"

R=$(new_repo othertool)
edit_files "$R" 9 40
check "a Bash call is not an edit, so it is ignored" \
  "$(jq -cn --arg d "$R" '{hook_event_name:"PostToolUse",cwd:$d,tool_name:"Bash",tool_input:{command:"ls"}}' |
    (cd "$R" && "$HOOK") 2>/dev/null | wc -c | tr -d ' ')" 0

echo
echo "=== wiring ==="
check "wired to PostToolUse on the edit tools in .claude/settings.json" \
  "$(jq -r '[.hooks.PostToolUse[]? | select((.matcher // "") | test("Edit")) | .hooks[].command] |
     map(select(test("scope-tripwire"))) | length' "$ROOT/.claude/settings.json")" 1
check "NOT wired to PreToolUse, where it could block" \
  "$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command] | map(select(test("scope-tripwire"))) | length' "$ROOT/.claude/settings.json")" 0
# Codex sends the same PostToolUse payload, but whether it surfaces
# additionalContext to the model is unverified, and adding a handler drops that
# handler's recorded trust until `/hooks` runs again. Mirror it and delete this
# check once a probe shows the text reaches the model.
check "not mirrored into .codex/hooks.json yet (see comment)" \
  "$(jq -r '[.. | objects | select(.type? == "command") | .command] | map(select(test("scope-tripwire"))) | length' "$ROOT/.codex/hooks.json")" 0

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
