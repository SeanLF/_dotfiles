#!/bin/bash
# The Codex hook manifest (.codex/hooks.json) must carry the same guards as the
# Claude Code one (.claude/settings.json), and they must actually fire on the
# payload shapes Codex sends. Parity is asserted, not assumed: a guard added to
# one manifest and not the other fails here.
#
# Payload shapes were captured from codex 0.153.2 on 2026-09-05: PreToolUse
# carries tool_name, tool_input.command and cwd; apply_patch puts the patch in
# tool_input.command; SubagentStop carries agent_type (the role name).
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CODEX="$ROOT/.codex/hooks.json"
CLAUDE="$ROOT/.claude/settings.json"
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

# The manifest names the installed paths. Resolve them into THIS checkout, so a
# worktree tests its own hooks rather than whatever ~/.claude/hooks points at.
expand() {
  local p="$1"
  p="${p/#\~\/.claude\/hooks\//$ROOT/.claude/hooks/}"
  p="${p/#\~\/Developer\/_dotfiles\//$ROOT/}"
  printf '%s' "${p/#\~/$HOME}"
}

echo "=== manifest ==="
check "hooks.json is valid JSON" "$(jq -e . "$CODEX" >/dev/null 2>&1 && echo yes || echo no)" yes

# Codex 0.150+ registers exactly these events; an unknown key is silently ignored.
known='SessionStart SessionEnd SubagentStart PreToolUse PermissionRequest PostToolUse PreCompact PostCompact UserPromptSubmit SubagentStop Stop Interrupt'
for ev in $(jq -r '.hooks | keys[]' "$CODEX"); do
  case " $known " in
    *" $ev "*) ok "event $ev is one Codex fires" ;;
    *) no "event $ev is not a Codex hook event" ;;
  esac
done

# Every handler names an executable. `~` is expanded by the shell Codex runs it in.
while IFS= read -r cmd; do
  bin=$(expand "${cmd%% *}")
  check "executable: $cmd" "$([ -x "$bin" ] && echo yes || echo no)" yes
done < <(jq -r '.. | objects | select(.type? == "command") | .command' "$CODEX")

echo
echo "=== parity with .claude/settings.json ==="
# Claude-only handlers: rtk has no Codex processor (`rtk hook --help`).
claude_bash=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$CLAUDE" | grep -v '^rtk hook claude$' | sort)
codex_bash=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "^Bash$") | .hooks[].command' "$CODEX" | sort)
check "Bash guards are the same set, in the same order, as Claude's" "$codex_bash" "$claude_bash"

claude_edit=$(jq -r '.hooks.PreToolUse[] | select(.matcher | test("Edit")) | .hooks[].command' "$CLAUDE" | sort)
codex_edit=$(jq -r '.hooks.PreToolUse[] | select(.matcher | test("apply_patch")) | .hooks[].command' "$CODEX" | sort)
check "edit guards match Claude's" "$codex_edit" "$claude_edit"
check "the edit matcher names apply_patch, Codex's edit tool" \
  "$(jq -r '[.hooks.PreToolUse[].matcher | select(test("apply_patch"))] | length' "$CODEX")" 1

check "record-review is wired to SubagentStop" \
  "$(jq -r '[.hooks.SubagentStop[]?.hooks[]?.command] | map(select(test("record-review"))) | length' "$CODEX")" 1
check "record-review is NOT wired to PostToolUse" \
  "$(jq -r '[.hooks.PostToolUse[]?.hooks[]?.command] | map(select(test("record-review"))) | length' "$CODEX")" 0

# SessionEnd handlers get 1s by default and 3s at most.
check "SessionEnd handlers fit Codex's 3s ceiling" \
  "$(jq -r '[.hooks.SessionEnd[]?.hooks[]? | select((.timeout // 1) > 3)] | length' "$CODEX")" 0

echo
echo "=== the guards fire on Codex payloads ==="
# Run every handler Codex would run for an event, in manifest order, and report
# the first deny. This is what the Codex engine does, minus the trust check.
run_event() { # $1 event, $2 tool_name, $3 payload json
  local out cmd bin
  while IFS= read -r cmd; do
    bin=$(expand "$cmd")
    out=$(printf '%s' "$3" | (cd "$SANDBOX/repo" && eval "$bin") 2>/dev/null)
    if [ -n "$out" ] && [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = deny ]; then
      echo deny
      return
    fi
  done < <(jq -r --arg ev "$1" --arg t "$2" '.hooks[$ev][] | select((.matcher // "") as $m | $m == "" or ($t | test($m))) | .hooks[].command' "$CODEX")
  echo allow
}
payload() { # $1 tool_name, $2 command text
  jq -cn --arg t "$1" --arg c "$2" --arg d "$SANDBOX/repo" --arg s codex-test \
    '{hook_event_name:"PreToolUse",session_id:$s,turn_id:"t",cwd:$d,tool_name:$t,tool_use_id:"call_x",tool_input:{command:$c}}'
}

git init -q "$SANDBOX/repo"
(
  cd "$SANDBOX/repo" || exit 1
  git config user.email t@t && git config user.name t
  mkdir -p .githooks
  install -m 755 "$ROOT/git/hooks/post-commit" .githooks/post-commit
  git config --local core.hooksPath .githooks
  echo base >file.txt && git add -A
  env -u CLAUDECODE -u CODEX_THREAD_ID git commit -qm "chore: base"
)
patch='*** Begin Patch
*** Update File: file.txt
@@
+x
*** End Patch
'

check "git commit --no-verify is denied" "$(run_event PreToolUse Bash "$(payload Bash 'git commit --no-verify -m "feat: x"')")" deny
check "clearing the Codex marker is denied" "$(run_event PreToolUse Bash "$(payload Bash 'env -u CODEX_THREAD_ID git commit -m "feat: x"')")" deny
check "rg -rn is denied (search guard reached)" "$(run_event PreToolUse Bash "$(payload Bash 'rg -rn foo')")" deny
check "git status is allowed" "$(run_event PreToolUse Bash "$(payload Bash 'git status')")" allow
check "apply_patch on a clean HEAD is allowed" "$(run_event PreToolUse apply_patch "$(payload apply_patch "$patch")")" allow

# A Codex commit: post-commit marks HEAD pending under CODEX_THREAD_ID.
(
  cd "$SANDBOX/repo" || exit 1
  echo agent >>file.txt && git add -A
  env -u CLAUDECODE CODEX_THREAD_ID=01a0-test git commit -qm "feat: agent"
)
check "post-commit marked the Codex commit pending" \
  "$([ -f "$SANDBOX/repo/.git/claude-pending-review" ] && echo yes || echo no)" yes
check "apply_patch while HEAD is pending is denied" "$(run_event PreToolUse apply_patch "$(payload apply_patch "$patch")")" deny
check "a further commit while HEAD is pending is denied" "$(run_event PreToolUse Bash "$(payload Bash 'git commit -m "feat: on top"')")" deny
# Negative control: a tool no matcher names runs no guard, so the deny above came
# from the guard and not from the harness.
check "a tool outside every matcher runs nothing (control)" "$(run_event PreToolUse Read "$(payload Read "$patch")")" allow

# Codex's SubagentStop for the reviewer role clears it, through the manifest.
stop=$(jq -cn --arg d "$SANDBOX/repo" '{hook_event_name:"SubagentStop",session_id:"s",turn_id:"t",cwd:$d,agent_id:"a1",agent_type:"reviewer",stop_hook_active:false,last_assistant_message:"ok"}')
run_event SubagentStop reviewer "$stop" >/dev/null
check "SubagentStop(reviewer) clears the pending commit" \
  "$([ -f "$SANDBOX/repo/.git/claude-pending-review" ] && echo pending || echo clear)" clear
check "apply_patch is allowed again" "$(run_event PreToolUse apply_patch "$(payload apply_patch "$patch")")" allow

# And a subagent of another role does not.
(
  cd "$SANDBOX/repo" || exit 1
  echo more >>file.txt && git add -A
  env -u CLAUDECODE CODEX_THREAD_ID=01a0-test git commit -qm "feat: more"
)
stop=$(jq -cn --arg d "$SANDBOX/repo" '{hook_event_name:"SubagentStop",session_id:"s",turn_id:"t",cwd:$d,agent_id:"a2",agent_type:"explorer",stop_hook_active:false,last_assistant_message:"ok"}')
run_event SubagentStop explorer "$stop" >/dev/null
check "SubagentStop(explorer) leaves the commit pending" \
  "$([ -f "$SANDBOX/repo/.git/claude-pending-review" ] && echo pending || echo clear)" pending

echo
echo "=== reviewer role ==="
ROLE="$ROOT/.codex/agents/reviewer.toml"
check "the role file parses as TOML" "$(python3 -c "import tomllib,sys; tomllib.load(open('$ROLE','rb'))" 2>/dev/null && echo yes || echo no)" yes
check "the role is named reviewer" "$(python3 -c "import tomllib; print(tomllib.load(open('$ROLE','rb'))['name'])")" reviewer
check "the role pins a model (AGENTS.md: never inherit)" \
  "$(python3 -c "import tomllib; print('model' in tomllib.load(open('$ROLE','rb')))")" True

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
