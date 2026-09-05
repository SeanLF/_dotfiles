#!/bin/bash
# Does a real Codex session honour the guards in ~/.codex/hooks.json?
#
# Opt-in, because it spends tokens: it drives a real headless Codex. Everything
# else in tests/ is free and offline, so this is not in `just test`.
#
# The invariant it defends: Codex runs user-level hooks from ~/.codex/hooks.json
# with the PreToolUse payload shape our guards parse, and a deny from a guard
# stops the tool. tests/test-codex-hooks.sh proves the guards deny the payloads
# we captured; only this proves Codex still sends them and still listens.
#
# --dangerously-bypass-hook-trust so the probe does not depend on /hooks having
# been run on this machine; the hooks it bypasses trust for are our own.
set -uo pipefail

command -v codex >/dev/null 2>&1 || {
  echo "codex CLI not found"
  exit 2
}
[ -f "$HOME/.codex/hooks.json" ] || {
  echo "$HOME/.codex/hooks.json not installed (run ./setup.sh symlinks)"
  exit 2
}

REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
git init -q -b main "$REPO"
cd "$REPO" || exit 1
git config user.email t@t
git config user.name t
echo base >file.txt
git add -A
env -u CLAUDECODE -u CODEX_THREAD_ID git commit -qm "chore: base"

out=$(codex exec --skip-git-repo-check --dangerously-bypass-hook-trust \
  --sandbox workspace-write --ephemeral -m gpt-5.5 -c model_reasoning_effort=low \
  'Do exactly this, no commentary: 1) run the shell command: echo probe >> file.txt; 2) run the shell command: git commit -a --no-verify -m "feat: probe"; 3) paste the complete tool result of step 2 verbatim, including any denial or hook message, then print PROBE-END.' \
  </dev/null 2>&1)

printf '%s\n' "$out" | tail -20
echo "----------------------------------------"
if printf '%s' "$out" | grep -q 'skips the git hooks'; then
  echo "PASS: Codex ran hook-bypass-guard and the deny reached the model"
  rc=0
else
  echo "FAIL: no deny text in the transcript; Codex did not run the guard or its payload shape changed"
  rc=1
fi
if git log --oneline | grep -q probe; then
  echo "FAIL: the --no-verify commit landed"
  rc=1
else
  echo "PASS: no --no-verify commit landed"
fi
exit "$rc"
