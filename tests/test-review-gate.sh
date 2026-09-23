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
# The Stop hook's verdict. An allowed stop prints nothing, so default outside jq.
stop() { # $1 = stop_hook_active (true/false)
  local out
  out=$(printf '{"hook_event_name":"Stop","cwd":"%s","stop_hook_active":%s}' "$PWD" "${1:-false}" |
    "${REVIEW_GATE_BIN:-$ROOT/bin/review-gate}" --stop 2>/dev/null)
  if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.decision // "allow"'; fi
}
pending() {
  "${REVIEW_GATE_BIN:-$ROOT/bin/review-gate}" --pending >/dev/null 2>&1
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
  check "ending the turn is blocked while HEAD is pending" "$(stop false)" block
  check "a stop already continued once by this hook is let through" "$(stop true)" allow
  check "unreviewed push is refused" "$(push)" 1

  review pr-review-toolkit:code-reviewer # clean tree, unpushed range
  check "a review of HEAD clears the pending state" "$(pending)" 0
  check "ending the turn is allowed once reviewed" "$(stop false)" allow
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

  # The hatch at the end of a turn: consumed, stamps the commit, lets the stop through.
  echo "stop-hatch" >>file.txt && git add -A && commit >/dev/null
  hatch
  check "the hatch lets a trivial commit's turn end" "$(stop false)" allow
  check "and it was consumed" "$([ -f "$(git rev-parse --git-common-dir)/claude-review-force" ] && echo left || echo gone)" gone
  check "and the push accepts the hatched commit" "$(push)" 0

  # A human commit on top of a pending Claude commit moves HEAD; pending keys on HEAD.
  echo "claude again" >>file.txt && git add -A && commit >/dev/null
  echo "human on top" >>file.txt && git add -A
  human git commit -qm "feat: human" >/dev/null 2>&1
  check "a human commit on top ends the pending state" "$(pending)" 0
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
check "review-gate --stop is wired to Stop" \
  "$(jq -r '[.hooks.Stop[]?.hooks[]?.command] | map(select(test("review-gate --stop"))) | length' "$SETTINGS")" 1
check "nothing gates edits mid-task" \
  "$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command] | map(select(test("pending-review-guard"))) | length' "$SETTINGS")" 0
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
roster_cases
ROSTER_PASS=$PASS ROSTER_FAIL=$FAIL
PASS=0 FAIL=0
echo
mechanism_cases

printf '\n%s\n' "----------------------------------------"
printf 'negative control: %d assertions failed, so absence is detectable\n' "$CONTROL_FAIL"
printf 'gate installed:   %d passed, %d failed  (Claude Code marker)\n' "$GATE_PASS" "$GATE_FAIL"
printf 'gate installed:   %d passed, %d failed  (Codex marker)\n' "$CODEX_PASS" "$CODEX_FAIL"
printf 'reviewer roster:  %d passed, %d failed\n' "$ROSTER_PASS" "$ROSTER_FAIL"
printf 'mechanism:        %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$GATE_FAIL" -eq 0 ] && [ "$CODEX_FAIL" -eq 0 ] && [ "$ROSTER_FAIL" -eq 0 ] && [ "$FAIL" -eq 0 ]
