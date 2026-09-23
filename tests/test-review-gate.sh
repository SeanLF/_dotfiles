#!/bin/bash
# Harness for the git-side review gate (bin/review-gate, bin/record-review,
# git/hooks/pre-commit advisory, git/hooks/pre-push refusing).
#
# Builds a throwaway repo with a stand-in lefthook that rewrites files, then
# drives the cases the old PreToolUse gate got wrong. Case 0 unplugs the gate and
# requires the assertions to fail: a harness that passes either way is measuring
# nothing, and this one has already caught two bugs in its own subject.
#
# The flow cases run once per harness marker: CLAUDECODE=1 (Claude Code) and
# CODEX_THREAD_ID (Codex). A commit or push with neither set is a human's.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
PASS=0 FAIL=0 CONTROL_FAIL=0
AGENT_MARKER=claude

agent_on() {
  case "$AGENT_MARKER" in
    codex)
      unset CLAUDECODE
      export CODEX_THREAD_ID=01a0-test-thread
      ;;
    *)
      unset CODEX_THREAD_ID
      export CLAUDECODE=1
      ;;
  esac
}
agent_off() { unset CLAUDECODE CODEX_THREAD_ID; }
human() { env -u CLAUDECODE -u CODEX_THREAD_ID "$@"; }

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
push() {
  git push -q origin HEAD >/dev/null 2>&1
  echo $?
}
hatch() { touch "$(git rev-parse --git-common-dir)/claude-review-force"; }
pending() {
  "${REVIEW_GATE_BIN:-$ROOT/bin/review-gate}" --pending >/dev/null 2>&1
  echo $?
}
# The PreToolUse guard, fed the JSON the harnesses send it (apply_patch carries
# the patch in tool_input.command). "allow" is no output.
guard() { # $1 tool, $2 file_path or command
  local out
  if [ "$1" = Bash ] || [ "$1" = apply_patch ]; then
    out=$(jq -cn --arg t "$1" --arg c "$2" --arg d "$SANDBOX/repo" '{tool_name:$t,cwd:$d,tool_input:{command:$c}}' | "$ROOT/.claude/hooks/pending-review-guard.sh")
  else
    out=$(jq -cn --arg t "$1" --arg f "$2" --arg d "$SANDBOX/repo" '{tool_name:$t,cwd:$d,tool_input:{file_path:$f}}' | "$ROOT/.claude/hooks/pending-review-guard.sh")
  fi
  if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'; fi
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
  install -m 755 "$ROOT/git/hooks/pre-push" .githooks/pre-push
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
  human git commit -qm "chore: base"
  rm -rf "$SANDBOX/remote.git"
  git init -q --bare "$SANDBOX/remote.git"
  git remote add origin "$SANDBOX/remote.git"
  human git push -qu origin HEAD >/dev/null 2>&1
  rm -f "$(git rev-parse --git-dir)/claude-review-force" "$(git rev-parse --git-dir)/claude-review"
}

run_cases() {
  printf '\n%s\n' "$1"

  echo "human" >>file.txt && git add -A
  human git commit -qm "feat: change" >/dev/null 2>&1
  check "hand-typed push is untouched (no agent marker)" "$(human bash -c 'git push -q origin HEAD >/dev/null 2>&1; echo $?')" 0

  agent_on
  echo "agent" >>file.txt && git add -A
  check "unreviewed agent commit is allowed (advisory)" "$(commit)" 0
  check "that commit is now pending review" "$(pending)" 1
  check "the guard refuses an Edit while HEAD is pending" "$(guard Edit "$SANDBOX/repo/file.txt")" deny
  check "the guard refuses an apply_patch while HEAD is pending" "$(guard apply_patch '*** Begin Patch
*** Update File: file.txt
@@
+x
*** End Patch')" deny
  check "the guard refuses another commit while HEAD is pending" "$(guard Bash 'git commit -m "feat: on top"')" deny
  check "the guard leaves an edit outside the repo alone" "$(guard Edit "$SANDBOX/elsewhere.txt")" allow
  check "the guard leaves a non-commit Bash call alone" "$(guard Bash 'git status')" allow
  check "unreviewed push is refused" "$(push)" 1

  review pr-review-toolkit:code-reviewer # clean tree, unpushed range
  check "a review of HEAD clears the pending state" "$(pending)" 0
  check "edits are allowed again" "$(guard Edit "$SANDBOX/repo/file.txt")" allow
  check "apply_patch is allowed again" "$(guard apply_patch '*** Begin Patch
*** Update File: file.txt
@@
+x
*** End Patch')" allow
  check "push after a review of the committed range passes" "$(push)" 0

  # The Codex reviewer role clears the gate the way the Claude reviewers do.
  echo "codex-reviewed" >>file.txt && git add -A && commit >/dev/null
  check "a commit is pending before the Codex reviewer runs" "$(pending)" 1
  printf '{"hook_event_name":"SubagentStop","agent_type":"reviewer","agent_id":"a1","cwd":"%s"}' "$SANDBOX/repo" |
    "$ROOT/bin/record-review" >/dev/null 2>&1
  check "a Codex SubagentStop for the reviewer role clears pending" "$(pending)" 0
  check "and the push passes" "$(push)" 0

  # The in-flow cycle: commit, review that commit, commit, review, push. No
  # whole-range review ever runs; the per-commit stamps carry the push.
  echo "c1" >>file.txt && git add -A && commit >/dev/null
  review feature-dev:code-reviewer
  echo "c2" >>file.txt && git add -A && commit >/dev/null
  review feature-dev:code-reviewer
  rm -f "$(git rev-parse --git-common-dir)/claude-review"
  check "two commits each reviewed in turn push without a range review" "$(push)" 0

  # A review taken before the commit (the old flow) must not leave HEAD pending.
  echo "pre" >>file.txt
  review pr-review-toolkit:code-reviewer
  git add -A && commit >/dev/null
  check "a commit whose staged content was already reviewed is not pending" "$(pending)" 0
  push >/dev/null

  # The hatch touched before a trivial commit: no pending, and the push still has its hatch.
  hatch
  echo "trivial" >>file.txt && git add -A && commit >/dev/null
  check "a hatched commit is not pending" "$(pending)" 0
  echo "trivial-next" >>file.txt && git add -A && commit >/dev/null
  check "the hatch was consumed by that commit, so the next one is pending" "$(pending)" 1
  review pr-review-toolkit:code-reviewer
  check "the push accepts the stamped commits" "$(push)" 0

  # The hatch touched AFTER an unreviewed commit clears pending and stamps it.
  echo "trivial2" >>file.txt && git add -A && commit >/dev/null
  check "an unhatched commit is pending" "$(pending)" 1
  hatch
  check "touching the hatch afterwards clears pending" "$(pending)" 0
  check "and the push accepts the stamped commit" "$(push)" 0

  # Bash writes are edits too; scratch writes are not.
  echo "bashwrite" >>file.txt && git add -A && commit >/dev/null
  check "the guard refuses sed -i while HEAD is pending" "$(guard Bash 'sed -i "" -e s/a/b/ file.txt')" deny
  check "the guard refuses a redirect into the tree while pending" "$(guard Bash 'echo x > file.txt')" deny
  check "the guard refuses a heredoc into the tree while pending" "$(guard Bash 'cat > file.txt <<EOF2
x
EOF2')" deny
  check "the guard allows a redirect into /tmp while pending" "$(guard Bash 'echo x > /tmp/scratch.txt')" allow
  check "the guard allows a redirect to a file descriptor while pending" "$(guard Bash 'make check 2>&1 | tail -n 20; echo done >&2')" allow
  check "the guard refuses a >&file redirect into the tree while pending" "$(guard Bash 'echo x >&file.txt')" deny
  check "the guard refuses >&word when the word only starts with a digit" "$(guard Bash 'echo x >&1backup.log')" deny
  check "the guard allows closing a descriptor with >&-" "$(guard Bash 'exec 3>&-; cmd >&- ; echo ok')" allow
  check "the guard allows a read while pending" "$(guard Bash 'rg -n foo file.txt')" allow
  review pr-review-toolkit:code-reviewer
  push >/dev/null

  # A human commit on top of a pending Claude commit moves HEAD; the guard keys on HEAD.
  echo "claude again" >>file.txt && git add -A && commit >/dev/null
  echo "human on top" >>file.txt && git add -A
  human git commit -qm "feat: human" >/dev/null 2>&1
  check "a human commit on top unblocks editing" "$(pending)" 0
  review pr-review-toolkit:code-reviewer
  push >/dev/null

  # The usual order: read the working diff, then stage, commit, push.
  echo "reviewed before staging" >>file.txt
  review pr-review-toolkit:code-reviewer
  git add -A
  commit >/dev/null
  check "a review taken before git add survives commit and push" "$(push)" 0

  echo "more" >>file.txt && git add -A && commit >/dev/null
  review Explore
  check "a non-reviewer agent does not clear the gate" "$(push)" 1
  review pr-review-toolkit:code-reviewer
  push >/dev/null

  # lefthook rewrites after the review: the pushed content is not what was read.
  export LEFTHOOK_REWRITES=1
  printf 'trailing   \n' >>file.txt && git add -A
  review pr-review-toolkit:code-reviewer
  check "commit stays advisory when the formatter rewrites the tree" "$(commit)" 0
  check "stale review after a formatter rewrite is refused at push" "$(push)" 1
  review pr-review-toolkit:code-reviewer
  check "re-review of the formatted tree passes" "$(push)" 0
  unset LEFTHOOK_REWRITES

  echo "x" >>file.txt && git add -A
  review pr-review-toolkit:code-reviewer
  check "lefthook failure aborts the commit" "$(LEFTHOOK_FAILS=1 commit)" 1
  commit >/dev/null
  check "the review survives that failed commit" "$(push)" 0

  # Detection is git's, not a regex over a shell string.
  echo "y" >>file.txt && git add -A && commit >/dev/null
  rc=$(
    cd / && git -C "$SANDBOX/repo" push -q origin HEAD >/dev/null 2>&1
    echo $?
  )
  check "git -C from another cwd is still gated" "$rc" 1
  review adversarial-reviewer
  check "adversarial-reviewer clears the gate" "$(push)" 0

  echo "z" >>file.txt && git add -A && commit >/dev/null
  hatch
  check "force hatch lets a mechanical change through" "$(push)" 0
  echo "z2" >>file.txt && git add -A && commit >/dev/null
  check "force hatch is one-shot" "$(push)" 1
  hatch
  echo "z3" >>file.txt && git add -A && commit >/dev/null
  check "a hatch covers the commit it met, not the earlier unreviewed one" "$(push)" 1
  review pr-review-toolkit:code-reviewer
  check "reviewing the range then passes" "$(push)" 0

  # A review covers what was there when it ran, not what came after.
  echo "p1" >>file.txt && git add -A && commit >/dev/null
  review pr-review-toolkit:code-reviewer
  echo "p2" >>file.txt && git add -A && commit >/dev/null
  check "a commit made after the review is refused at push" "$(push)" 1
  review pr-review-toolkit:code-reviewer
  check "a review of the full range passes" "$(push)" 0

  # Two unpushed commits reviewed together, as the pushed range, not per commit.
  echo "q1" >>file.txt && git add -A && commit >/dev/null
  echo "q2" >>file.txt && git add -A && commit >/dev/null
  review pr-review-toolkit:code-reviewer
  check "one review covers several unpushed commits" "$(push)" 0

  # A follow-up after a range review changes the range hash; the commits the
  # review saw must still count.
  echo "r1" >>file.txt && git add -A && commit >/dev/null
  echo "r2" >>file.txt && git add -A && commit >/dev/null
  review pr-review-toolkit:code-reviewer
  hatch
  echo "r3" >>file.txt && git add -A && commit >/dev/null
  check "a hatched follow-up keeps the range review before it" "$(push)" 0

  # No HEAD: `git diff HEAD` fatals but still hashes empty input, so every tree
  # in a fresh repo would hash alike.
  local fresh empty
  empty=$(printf '' | shasum -a 256 | cut -c1-16)
  fresh=$(mktemp -d)
  (
    git init -q "$fresh" && cd "$fresh" || exit 1
    echo one >a.txt && git add -A
    h1=$("$ROOT/bin/review-gate" --hash)
    echo two >>a.txt && echo three >b.txt && git add -A
    h2=$("$ROOT/bin/review-gate" --hash)
    [ "$h1" != "$h2" ] && [ "$h1" != "$empty" ] && [ "$h2" != "$empty" ]
  )
  check "pre-first-commit trees hash differently and non-degenerately" "$?" 0
  rm -rf "$fresh"

  # Content staged AFTER the review, whose worktree copy is then restored so the
  # working diff reads clean.
  echo "reviewed content" >>file.txt && git add -A
  review pr-review-toolkit:code-reviewer
  cp file.txt "$SANDBOX/keep"
  printf 'never reviewed\n' >>file.txt && git add file.txt
  cp "$SANDBOX/keep" file.txt
  commit >/dev/null
  git checkout -q -- file.txt
  check "content staged after the review is refused at push" "$(push)" 1
  review pr-review-toolkit:code-reviewer
  push >/dev/null

  # A review of a clean, pushed tree hashes empty everywhere and must not
  # overwrite the record with a certificate for nothing.
  rm -f "$(git rev-parse --git-common-dir)/claude-review"
  review pr-review-toolkit:code-reviewer
  check "a review of a clean pushed tree records nothing" \
    "$([ -f "$(git rev-parse --git-common-dir)/claude-review" ] && echo present || echo absent)" absent

  # Pending is per worktree: a commit in one must not clear the other's.
  git worktree add -q "$SANDBOX/wt2" -b wt2-branch >/dev/null 2>&1
  echo "main pending" >>file.txt && git add -A && commit >/dev/null
  (
    cd "$SANDBOX/wt2" || exit 1
    echo "wt2 change" >>file.txt && git add -A
    git commit -qm "feat: in wt2" >/dev/null 2>&1
  )
  check "a commit in another worktree leaves this one pending" "$(pending)" 1
  review pr-review-toolkit:code-reviewer
  push >/dev/null
  git worktree remove --force "$SANDBOX/wt2" >/dev/null 2>&1
  git branch -qD wt2-branch >/dev/null 2>&1

  # The first push of a repo with no remote-tracking refs carries everything.
  local first
  first=$(mktemp -d)
  (
    git init -q -b main "$first" && cd "$first" || exit 1
    git config user.email t@t && git config user.name t
    echo one >a.txt && git add -A && git commit -qm "chore: base"
    echo two >>a.txt && git add -A && git commit -qm "feat: more"
    "$ROOT/bin/review-gate" --push "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000 >/dev/null 2>&1
  )
  check "the first push of main with no remote refs is gated" "$?" 1
  rm -rf "$first"

  # A LINKED WORKTREE, end to end: git exports GIT_DIR into hooks only there.
  git worktree add -q "$SANDBOX/wt" -b wt-branch >/dev/null 2>&1
  echo "main advances" >>file.txt && git add -A && commit >/dev/null
  hatch
  push >/dev/null
  (
    cd "$SANDBOX/wt" || exit 1
    echo "worktree change" >>file.txt && git add -A
    git commit -qm "feat: inside a worktree" >/dev/null 2>&1
    printf '{"agent_type":"pr-review-toolkit:code-reviewer","cwd":"%s"}' "$SANDBOX/wt" |
      "$ROOT/bin/record-review" >/dev/null 2>&1
    pending >"$SANDBOX/wt-pending"
    git push -qu origin wt-branch >/dev/null 2>&1
  )
  check "a reviewed push from a linked worktree passes" "$?" 0
  check "a review in a linked worktree clears its pending commit" "$(cat "$SANDBOX/wt-pending")" 0
  git worktree remove --force "$SANDBOX/wt" >/dev/null 2>&1
  git branch -qD wt-branch >/dev/null 2>&1

  agent_off
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
  # shellcheck disable=SC2016
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
    'sudo env -iu CLAUDECODE git commit -m x' \
    'CODEX_THREAD_ID= git commit -m x' \
    'CODEX_THREAD_ID=other git commit -m x' \
    'env -u CODEX_THREAD_ID git commit -m x' \
    'unset CODEX_THREAD_ID; git commit -m x' \
    'export CODEX_THREAD_ID=; git commit -m x' \
    'env CODEX_THREAD_ID= git commit -m x' \
    'git push --no-verify origin main' \
    'git push origin main --no-verify' \
    'rm .git/claude-pending-review' \
    'rm -f "$(git rev-parse --git-common-dir)/claude-pending-review"' \
    'git rev-parse HEAD >> .git/claude-reviewed-commits' \
    'echo abc > .git/claude-review' \
    'chmod -x ~/.claude/hooks/pending-review-guard.sh'; do
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
    'rg CODEX_THREAD_ID bin/ .claude/hooks/' \
    'printenv CODEX_THREAD_ID' \
    'env printenv CODEX_THREAD_ID' \
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
    'env FOO=1 rg CLAUDECODE bin/' \
    'git push -n origin main' \
    'git push --dry-run origin main' \
    'cat .git/claude-pending-review' \
    'rg claude-pending-review bin/' \
    'touch .git/claude-review-force' \
    'rm -rf build && rg -n claude-pending-review bin/' \
    'cp a.txt b.txt && cat .git/claude-review' \
    'mv old.log new.log; rg claude-reviewed-commits docs/'; do
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
    human git commit -qm "chore: base"
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

# Mechanism claims that were previously only asserted in comments. Each one is a
# fact about git or the shell that the gate depends on; if it stops being true the
# gate breaks in a way the flow tests would not localize.
mechanism_cases() {
  echo "=== mechanism ==="
  local repo h_w h_s
  repo=$(mktemp -d)
  git init -q "$repo"
  (
    cd "$repo" || exit 1
    git config user.email t@t
    git config user.name t
    git config diff.mnemonicPrefix true # what this machine sets
    echo one >f.txt
    git add -A
    human git commit -qm "chore: base"
    echo two >>f.txt
    git add -A
  )
  # Without --no-prefix, mnemonicPrefix labels the two diffs w/ and i/, so
  # identical content hashes differently and the worktree branch is dead code.
  h_w=$(cd "$repo" && git diff HEAD | shasum -a 256 | cut -c1-16)
  h_s=$(cd "$repo" && git diff --cached HEAD | shasum -a 256 | cut -c1-16)
  check "mnemonicPrefix DOES split the hashes (why --no-prefix is needed)" \
    "$([ "$h_w" != "$h_s" ] && echo split || echo same)" split
  h_w=$(cd "$repo" && git diff --no-prefix HEAD | shasum -a 256 | cut -c1-16)
  h_s=$(cd "$repo" && git diff --no-prefix --cached HEAD | shasum -a 256 | cut -c1-16)
  check "--no-prefix makes them equal for identical content" "$h_w" "$h_s"
  # And that the gate's own helper inherits the fix.
  check "review-gate --hash agrees with itself across staging" \
    "$(cd "$repo" && "$ROOT/bin/review-gate" --hash | sed -n 's/^worktree=//p')" \
    "$(cd "$repo" && "$ROOT/bin/review-gate" --hash | sed -n 's/^staged=//p')"
  rm -rf "$repo"

  # Why the flag pattern is --no-veri and not --no-v: git rejects --no-v as
  # ambiguous, and --no-verbose is a real flag that must not be denied.
  #
  # In a scratch repo with an empty index, never the caller's. `git commit
  # --no-verbose -m x` parses fine, so in a repo with anything staged this
  # assertion would COMMIT it.
  local probe out
  probe=$(mktemp -d)
  git init -q "$probe"
  out=$(cd "$probe" && git commit --no-v -m x 2>&1)
  check "git rejects --no-v as ambiguous (so the pattern must be --no-veri)" \
    "$(case "$out" in *ambiguous*) echo yes ;; *) echo no ;; esac)" yes
  out=$(cd "$probe" && git commit --no-verbose -m x 2>&1)
  check "--no-verbose parses, so denying --no-v* was a false positive" \
    "$(case "$out" in *ambiguous* | *"unknown option"*) echo rejected ;; *) echo parsed ;; esac)" parsed
  rm -rf "$probe"
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
check "pending-review-guard is wired to Bash" \
  "$(jq -r '[.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command] | map(select(test("pending-review-guard"))) | length' "$SETTINGS")" 1
check "pending-review-guard is wired to Edit/Write" \
  "$(jq -r '[.hooks.PreToolUse[] | select(.matcher|test("Edit")) | .hooks[].command] | map(select(test("pending-review-guard"))) | length' "$SETTINGS")" 1
PASS=0 FAIL=0

echo
echo "=== CASE 0: negative control, gate unplugged ==="
build
export REVIEW_GATE_BIN=/nonexistent
run_cases "assertions that depend on the gate must now FAIL"
CONTROL_FAIL=$FAIL
PASS=0 FAIL=0

echo
echo "=== CASE 1: gate installed, Claude Code marker ==="
build
export REVIEW_GATE_BIN="$ROOT/bin/review-gate"
run_cases "gate active (CLAUDECODE=1)"

printf '\n%s\n' "----------------------------------------"
if [ "$CONTROL_FAIL" -eq 0 ]; then
  printf '\033[31mHARNESS IS BLIND\033[0m: the control passed everything, so it is not measuring the gate.\n'
  exit 2
fi
GATE_PASS=$PASS GATE_FAIL=$FAIL
PASS=0 FAIL=0

echo
echo "=== CASE 2: gate installed, Codex marker ==="
AGENT_MARKER=codex
build
run_cases "gate active (CODEX_THREAD_ID set, CLAUDECODE unset)"
CODEX_PASS=$PASS CODEX_FAIL=$FAIL
AGENT_MARKER=claude
PASS=0 FAIL=0
bypass_cases
BYPASS_PASS=$PASS BYPASS_FAIL=$FAIL
PASS=0 FAIL=0
roster_cases
ROSTER_PASS=$PASS ROSTER_FAIL=$FAIL
PASS=0 FAIL=0
echo
mechanism_cases

printf '\n%s\n' "----------------------------------------"
printf 'negative control: %d assertions failed, so absence is detectable\n' "$CONTROL_FAIL"
printf 'gate installed:   %d passed, %d failed  (Claude Code marker)\n' "$GATE_PASS" "$GATE_FAIL"
printf 'gate installed:   %d passed, %d failed  (Codex marker)\n' "$CODEX_PASS" "$CODEX_FAIL"
printf 'bypass guard:     %d passed, %d failed\n' "$BYPASS_PASS" "$BYPASS_FAIL"
printf 'reviewer roster:  %d passed, %d failed\n' "$ROSTER_PASS" "$ROSTER_FAIL"
printf 'mechanism:        %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$GATE_FAIL" -eq 0 ] && [ "$CODEX_FAIL" -eq 0 ] && [ "$BYPASS_FAIL" -eq 0 ] && [ "$ROSTER_FAIL" -eq 0 ] && [ "$FAIL" -eq 0 ]
