#!/bin/bash
# Harness for the git-side review gate (bin/review-gate, bin/record-review,
# git/hooks/pre-commit).
#
# Builds a throwaway repo with a stand-in lefthook that rewrites files, then
# drives the cases the old PreToolUse gate got wrong. Case 0 unplugs the gate and
# requires the assertions to fail: a harness that passes either way is measuring
# nothing, and this one has already caught two bugs in its own subject.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
PASS=0 FAIL=0 CONTROL_FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf '  \033[32mPASS\033[0m %s\n' "$1"
}
no() {
  FAIL=$((FAIL + 1))
  printf '  \033[31mFAIL\033[0m %s\n' "$1"
}
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want $3, got $2)"; fi; }

review() { printf '{"agent_type":"%s","cwd":"%s"}' "$1" "$SANDBOX/repo" | "$ROOT/bin/record-review" >/dev/null 2>&1; }
commit() {
  git commit -qm "feat: change" >/dev/null 2>&1
  echo $?
}

build() {
  rm -rf "$SANDBOX/repo"
  git init -q "$SANDBOX/repo"
  cd "$SANDBOX/repo" || exit 1
  git config user.email t@t
  git config user.name t
  git config --local hooks.lefthook true

  mkdir -p .githooks fakebin
  install -m 755 "$ROOT/git/hooks/pre-commit" .githooks/pre-commit
  install -m 755 "$ROOT/git/hooks/post-commit" .githooks/post-commit
  # The real commit-msg runs BETWEEN them, which is what made consuming the hatch
  # in pre-commit unsafe. Install it, or the harness cannot see that bug.
  install -m 755 "$ROOT/git/hooks/commit-msg" .githooks/commit-msg
  git config --local core.hooksPath .githooks

  # Stand-in lefthook: strips trailing whitespace and restages, i.e. the
  # prettier-rewrites-the-tree case, without pulling in the real tool.
  cat >fakebin/lefthook <<'EOF'
#!/bin/bash
[ "${LEFTHOOK_FAILS:-0}" = "1" ] && { echo "lefthook: lint failed" >&2; exit 1; }
[ "${LEFTHOOK_REWRITES:-0}" = "1" ] || exit 0
for f in $(git diff --cached --name-only); do
  [ -f "$f" ] || continue
  sed -i '' -e 's/[[:space:]]*$//' "$f" 2>/dev/null || true
  git add "$f"
done
EOF
  chmod +x fakebin/lefthook
  touch lefthook.yml
  export PATH="$SANDBOX/repo/fakebin:$PATH"

  echo base >file.txt
  git add -A
  env -u CLAUDECODE git commit -qm "chore: base"
  # The gate only consumes the hatch when CLAUDECODE is set, so a setup commit
  # would leave one behind and silently clear the first real case.
  rm -f "$(git rev-parse --git-dir)/claude-review-force"
}

run_cases() {
  printf '\n%s\n' "$1"

  echo "human" >>file.txt && git add -A
  check "hand-typed commit is untouched (CLAUDECODE unset)" "$(env -u CLAUDECODE bash -c 'git commit -qm "feat: change" >/dev/null 2>&1; echo $?')" 0

  export CLAUDECODE=1
  echo "claude" >>file.txt && git add -A
  check "unreviewed Claude commit is refused" "$(commit)" 1

  review pr-review-toolkit:code-reviewer
  check "reviewed Claude commit passes" "$(commit)" 0

  # A review taken BEFORE `git add`, which is the usual order: read the working
  # diff, then stage, then commit. Only the staged hash was ever exercised
  # before, which hid that diff.mnemonicPrefix made the worktree hash
  # structurally unable to match and cost a second review on every commit.
  echo "reviewed before staging" >>file.txt
  review pr-review-toolkit:code-reviewer
  git add -A
  check "a review taken before git add survives it" "$(commit)" 0

  echo "more" >>file.txt && git add -A
  review Explore
  check "a non-reviewer agent does not clear the gate" "$(commit)" 1

  # The case the PreToolUse gate got wrong: lefthook rewrites after the review.
  export LEFTHOOK_REWRITES=1
  printf 'trailing   \n' >>file.txt && git add -A
  review pr-review-toolkit:code-reviewer
  check "stale review after a formatter rewrite is refused" "$(commit)" 1
  git add -A # tree is formatted and stable now
  review pr-review-toolkit:code-reviewer
  check "re-review of the formatted tree passes" "$(commit)" 0
  unset LEFTHOOK_REWRITES

  # The re-touch flake: a failed commit used to consume the marker.
  echo "x" >>file.txt && git add -A
  review pr-review-toolkit:code-reviewer
  check "lefthook failure aborts the commit" "$(LEFTHOOK_FAILS=1 commit)" 1
  check "the review survives that failed commit" "$(commit)" 0

  # Detection is git's, not a regex over a shell string.
  echo "y" >>file.txt && git add -A
  rc=$(
    cd / && git -C "$SANDBOX/repo" commit -qm "feat: elsewhere" >/dev/null 2>&1
    echo $?
  )
  check "git -C from another cwd is still gated" "$rc" 1
  review adversarial-reviewer
  check "adversarial-reviewer clears the gate" "$(commit)" 0

  echo "z" >>file.txt && git add -A
  touch "$(git rev-parse --git-common-dir)/claude-review-force"
  check "force hatch lets a mechanical change through" "$(commit)" 0
  echo "z2" >>file.txt && git add -A
  check "force hatch is one-shot" "$(commit)" 1

  # The hatch must outlive a commit rejected AFTER pre-commit. check-commit-msg
  # runs from commit-msg, one hook later, so consuming the hatch in pre-commit
  # reproduced the exact flake this gate exists to remove.
  touch "$(git rev-parse --git-common-dir)/claude-review-force"
  git commit -qm "not conventional at all" >/dev/null 2>&1
  check "bad commit message is rejected" "$?" 1
  check "hatch survives a message rejection" "$(commit)" 0

  # No HEAD: `git diff HEAD` fatals but still hashes empty input, so every tree
  # in a fresh repo hashed alike and any review certified any initial commit.
  local fresh empty
  empty=$(printf '' | shasum -a 256 | cut -c1-16)
  fresh=$(mktemp -d)
  (
    git init -q "$fresh" && cd "$fresh" || exit 1
    echo one >a.txt && git add -A
    h1=$("$ROOT/bin/review-gate" --hash)
    echo two >>a.txt && echo three >b.txt && git add -A
    h2=$("$ROOT/bin/review-gate" --hash)
    # Distinct is not enough: both could be the degenerate empty digest, which
    # is what the bug actually produced.
    [ "$h1" != "$h2" ] && [ "$h1" != "$empty" ] && [ "$h2" != "$empty" ]
  )
  check "pre-first-commit trees hash differently and non-degenerately" "$?" 0
  rm -rf "$fresh"

  # Content staged AFTER the review, whose worktree copy is then restored so the
  # working diff reads clean. Hashing the worktree let this commit unreviewed.
  echo "reviewed content" >>file.txt && git add -A
  review pr-review-toolkit:code-reviewer
  cp file.txt "$SANDBOX/keep"
  printf 'never reviewed\n' >>file.txt && git add file.txt
  cp "$SANDBOX/keep" file.txt # worktree back to what the reviewer read
  check "content staged after the review is refused" "$(commit)" 1
  git restore --staged --worktree file.txt 2>/dev/null || git checkout -q -- file.txt

  # A review taken on a clean tree hashes empty input and would otherwise
  # certify nothing. Clear the record first, or an earlier case's record answers.
  git add -A
  touch "$(git rev-parse --git-common-dir)/claude-review-force"
  commit >/dev/null
  rm -f "$(git rev-parse --git-common-dir)/claude-review"
  review pr-review-toolkit:code-reviewer # clean tree here
  check "a review of a clean tree records nothing" \
    "$([ -f "$(git rev-parse --git-common-dir)/claude-review" ] && echo present || echo absent)" absent

  # A LINKED WORKTREE, end to end. Two rev-parse calls agreeing proves nothing:
  # git exports GIT_DIR into hooks ONLY in a linked worktree, so a variable of
  # that name in the gate repoints every later git call and no number of reviews
  # can clear the commit.
  #
  # It also exports GIT_INDEX_FILE separately, so a repointed GIT_DIR still
  # reads the right index and corrupts HEAD resolution instead. That is
  # invisible while both worktrees sit on the same commit, so main has to be
  # advanced first or this case passes with the bug present.
  git worktree add -q "$SANDBOX/wt" -b wt-branch >/dev/null 2>&1
  echo "main advances" >>file.txt && git add -A
  touch "$(git rev-parse --git-common-dir)/claude-review-force"
  commit >/dev/null
  (
    cd "$SANDBOX/wt" || exit 1
    echo "worktree change" >>file.txt && git add -A
    printf '{"agent_type":"pr-review-toolkit:code-reviewer","cwd":"%s"}' "$SANDBOX/wt" |
      "$ROOT/bin/record-review" >/dev/null 2>&1
    git commit -qm "feat: reviewed inside a worktree" >/dev/null 2>&1
  )
  check "a reviewed commit inside a linked worktree passes" "$?" 0
  git worktree remove --force "$SANDBOX/wt" >/dev/null 2>&1
  git branch -qD wt-branch >/dev/null 2>&1

  unset CLAUDECODE
}

# hook-bypass-guard.sh is the only thing standing between the gate and a model
# that would rather not be gated, and it had no assertions at all.
bypass_cases() {
  echo
  echo "=== bypass guard ==="
  local guard="$ROOT/.claude/hooks/hook-bypass-guard.sh"
  # An allowed command produces NO output, so jq gets no input and prints
  # nothing. Defaulting inside jq never fires; it has to happen out here.
  verdict() {
    local out
    out=$(printf '{"tool_input":{"command":%s},"session_id":"s"}' "$(jq -Rn --arg c "$1" '$c')" | "$guard")
    if [ -z "$out" ]; then echo allow; else
      printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'
    fi
  }
  for c in \
    'git commit --no-verify -m "x"' \
    'git commit --no-verif -m "x"' \
    'git commit --no-veri -m "x"' \
    'git commit -nm "x"' \
    'git -c core.hooksPath=/dev/null commit -m "x"' \
    'git config --local core.hooksPath /dev/null' \
    'CLAUDECODE=0 git commit -m "x"' \
    'env -u CLAUDECODE git commit -m "x"' \
    'unset CLAUDECODE; git commit -m "x"' \
    'REVIEW_GATE_BIN=/nonexistent git commit -m "x"' \
    'chmod -x ~/Developer/_dotfiles/bin/review-gate' \
    'sudo chmod -x /Users/sean/Developer/_dotfiles/bin/review-gate' \
    '/usr/bin/git commit --no-verify -m "x"' \
    '/usr/bin/git -c core.hooksPath=/dev/null commit -m "x"' \
    'ls -l && git config core.hooksPath /dev/null' \
    'git config --list && git config core.hooksPath /dev/null' \
    'CLAUDECODE=1 echo hi; CLAUDECODE=0 git commit -m x' \
    '/usr/bin/git commit -nm x' \
    'sudo git commit -nm x' \
    'FOO=bar git commit -nm x' \
    'CLAUDECODE=1 git commit -nm x' \
    '(git commit --no-verify -m x)' \
    'export CLAUDECODE=0; git commit -m x' \
    'declare -x CLAUDECODE=0; git commit -m x' \
    'git commit \
       --no-verify -m x' \
    'git \
       commit -nm x' \
    'git -c \
       core.hooksPath=/dev/null commit -m x' \
    'env CLAUDECODE=0 git commit -m x' \
    'env -i git commit -m x' \
    'env -iu CLAUDECODE git commit -m x' \
    'env -ui CLAUDECODE git commit -m x' \
    'env -iu REVIEW_GATE_BIN sh' \
    'sudo env -iu CLAUDECODE git commit -m x'; do
    check "denied: $c" "$(verdict "$c")" deny
  done
  # This hook runs on EVERY Bash call, so a false positive is machine-wide and
  # has no hatch. Every line below was denied by an earlier revision.
  for c in \
    'git commit -m "feat: an ordinary commit"' \
    'git commit -m "note: we do not pass --no-verify here"' \
    'git log --oneline' \
    'git push origin main' \
    'git config --get core.hooksPath' \
    'git config --get-regexp core.*' \
    'git config --list' \
    'CLAUDECODE=1 git commit -m "feat: diagnostics"' \
    'rg core.hooksPath ~/.gitconfig' \
    'rg -n core.hooksPath git/hooks/pre-commit' \
    'rg -u CLAUDECODE bin/' \
    'rg CLAUDECODE=0 docs/' \
    'grep -n chmod /Users/sean/Developer/_dotfiles/bin/review-gate' \
    'wget --no-verbose https://example.com/x' \
    'npm install --no-verify-store' \
    'ls -l && cat file.txt' \
    'git config core.hooksPath' \
    'git grep core.hooksPath' \
    'git commit --no-verbose -m "feat: valid git flag"' \
    'git log --oneline && rg core.hooksPath .githooks' \
    'git status; rg -n core.hooksPath git/hooks/pre-commit' \
    'git status && wget --no-verbose https://example.com/x' \
    'rg -n TODO src/ && git commit -m "feat: x"' \
    'git add -A && git commit -m "feat: x" && git log -n 1' \
    'find . -name "*.sh"; git commit -m "feat: x"' \
    'git commit -m "feat: x" | tail -n 3' \
    'rg -c core.hooksPath git' \
    'rg -c core.hooksPath git bin' \
    'bat -p git/hooks/pre-commit && rg -c core.hooksPath git' \
    'rg env -u CLAUDECODE bin/' \
    'git log -n 5 --grep commit' \
    'fd -e sh | xargs grep -n chmod' \
    'time git commit -m "feat: x"' \
    'echo declare CLAUDECODE' \
    'rg -e declare -e CLAUDECODE .claude/hooks/' \
    'diff declare.log CLAUDECODE.log' \
    'npm run typeset-build' \
    'env CLAUDECODE=1 git commit -m "feat: diagnostics"' \
    'env FOO=1 rg -i pattern src/' \
    'env LC_ALL=C sed -i "" -e s/a/b/ file' \
    'env GIT_SEQUENCE_EDITOR=cat git rebase -i HEAD~3' \
    'env printenv CLAUDECODE' \
    'env FOO=1 rg CLAUDECODE bin/'; do
    check "allowed: $c" "$(verdict "$c")" allow
  done
}

# Every agent name the gate's deny message prints must actually clear it, and
# nothing else may. A message that names an agent which cannot clear the gate
# sends you round a loop that never terminates.
roster_cases() {
  echo
  echo "=== reviewer roster ==="
  local repo named
  repo=$(mktemp -d)
  git init -q "$repo"
  (
    cd "$repo" || exit 1
    git config user.email t@t
    git config user.name t
    echo one >f.txt
    git add -A
    env -u CLAUDECODE git commit -qm "chore: base"
    echo two >>f.txt
  )
  clears() {
    rm -f "$repo/.git/claude-review"
    printf '{"agent_type":"%s","cwd":"%s"}' "$1" "$repo" | "$ROOT/bin/record-review" >/dev/null 2>&1
    [ -f "$repo/.git/claude-review" ] && echo yes || echo no
  }
  # Exactly the names the deny message lists, scraped from the message itself so
  # the two cannot drift apart.
  named=$(sed -n '/Running any ONE of these/,/^$/p' "$ROOT/bin/review-gate" |
    grep -oE '^  [a-z-]+(:[a-z-]+)?' | tr -d ' ')
  for agent in $named; do
    check "the message names $agent, and it clears" "$(clears "$agent")" yes
  done
  for agent in superpowers:code-reviewer general-purpose Explore; do
    check "$agent does not clear" "$(clears "$agent")" no
  done
  rm -rf "$repo"
}

# Wiring, not behaviour, and the harness cannot reach it any other way: an
# artifact written from PostToolUse(Task) is written at SPAWN for a backgrounded
# agent, so the gate would clear before the reviewer read anything and every case
# below would still pass.
echo "=== wiring ==="
SETTINGS="$ROOT/.claude/settings.json"
check "record-review is wired to SubagentStop" \
  "$(jq -r '[.hooks.SubagentStop[]?.hooks[]?.command] | map(select(test("record-review"))) | length' "$SETTINGS")" 1
check "record-review is NOT wired to PostToolUse" \
  "$(jq -r '[.hooks.PostToolUse[]?.hooks[]?.command] | map(select(test("record-review"))) | length' "$SETTINGS")" 0
PASS=0 FAIL=0

echo
echo "=== CASE 0: negative control, gate unplugged ==="
build
export REVIEW_GATE_BIN=/nonexistent
run_cases "assertions that depend on the gate must now FAIL"
CONTROL_FAIL=$FAIL
PASS=0 FAIL=0

echo
echo "=== CASE 1: gate installed ==="
build
export REVIEW_GATE_BIN="$ROOT/bin/review-gate"
run_cases "gate active"

printf '\n%s\n' "----------------------------------------"
if [ "$CONTROL_FAIL" -eq 0 ]; then
  printf '\033[31mHARNESS IS BLIND\033[0m: the control passed everything, so it is not measuring the gate.\n'
  exit 2
fi
GATE_PASS=$PASS GATE_FAIL=$FAIL
PASS=0 FAIL=0
bypass_cases
BYPASS_PASS=$PASS BYPASS_FAIL=$FAIL
PASS=0 FAIL=0
roster_cases

printf '\n%s\n' "----------------------------------------"
printf 'negative control: %d assertions failed, so absence is detectable\n' "$CONTROL_FAIL"
printf 'gate installed:   %d passed, %d failed\n' "$GATE_PASS" "$GATE_FAIL"
printf 'bypass guard:     %d passed, %d failed\n' "$BYPASS_PASS" "$BYPASS_FAIL"
printf 'reviewer roster:  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$GATE_FAIL" -eq 0 ] && [ "$BYPASS_FAIL" -eq 0 ] && [ "$FAIL" -eq 0 ]
