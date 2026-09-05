#!/bin/bash
# Harness for bin/codex-config: the tracked file owns its keys in the live file
# and nothing else; everything Codex writes there survives an --apply.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CC="$ROOT/bin/codex-config"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
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

LIVE="$T/config.toml"
TRACKED="$T/tracked.toml"
HOOKS="$T/hooks.json"
run() { "$CC" "$@" --live "$LIVE" --tracked "$TRACKED" --hooks "$HOOKS" --backup-dir "$T/bak"; }
py() { python3 -c "import tomllib; d = tomllib.load(open('$LIVE', 'rb')); print($1)"; }

cat >"$LIVE" <<'EOF'
model = "old-model"
approvals_reviewer = "user"
notify = ["/some/app/path"]

[projects."/Users/x/Documents/some area"]
trust_level = "trusted"

[hooks.state."/Users/x/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "abc123"

[notice]
hide_full_access_warning = true

[notice.model_migrations]
"gpt-5.3-codex" = "gpt-5.4"

[tui.model_availability_nux]
"gpt-5.5" = 4

[mcp_servers.node_repl]
command = "/Applications/App.app/node"

[mcp_servers.node_repl.env]
APP_VERSION = "26.901"

[mcp_servers.xcode]
command = "xcrun"
args = ["mcpbridge"]

[mcp_servers.xcode.tools.OldTool]
approval_mode = "approve"

[plugins."bundled@openai-bundled"]
enabled = true

[plugins."superpowers@openai-curated"]
enabled = false
EOF

cat >"$TRACKED" <<'EOF'
model = "new-model"
approvals_reviewer = "user"

[notice]
hide_full_access_warning = true

[mcp_servers.xcode]
command = "xcrun"
args = ["mcpbridge"]

[mcp_servers.xcode.tools.NewTool]
approval_mode = "approve"

[plugins."superpowers@openai-curated"]
enabled = true
EOF

echo "=== drift ==="
out=$(run --check)
rc=$?
check "--check exits 1 when an owned key differs" "$rc" 1
check "names the changed scalar" "$(printf '%s\n' "$out" | grep -c '^model: tracked="new-model" live="old-model"$')" 1
check "names the owned table's stale subkey (deletion is drift too)" "$(printf '%s\n' "$out" | grep -c 'OldTool')" 1
check "names the owned table's missing subkey" "$(printf '%s\n' "$out" | grep -c 'NewTool')" 1
check "names the plugin flag" "$(printf '%s\n' "$out" | grep -c 'superpowers')" 1
check "does not report keys only the live file has" "$(printf '%s\n' "$out" | grep -c -e projects -e node_repl -e notify -e bundled)" 0

echo
echo "=== apply ==="
run --apply >/dev/null
check "--check exits 0 after --apply" "$(
  run --check >/dev/null
  echo $?
)" 0
check "owned scalar updated" "$(py "d['model']")" new-model
check "owned table replaced whole: stale subkey gone" "$(py "'OldTool' in d['mcp_servers']['xcode']['tools']")" False
check "owned table replaced whole: new subkey present" "$(py "d['mcp_servers']['xcode']['tools']['NewTool']['approval_mode']")" approve
check "owned plugin flag updated" "$(py "d['plugins']['superpowers@openai-curated']['enabled']")" True
check "project trust preserved (path with spaces and quotes)" "$(py "d['projects']['/Users/x/Documents/some area']['trust_level']")" trusted
check "hook trust hash preserved" "$(py "d['hooks']['state']['/Users/x/.codex/hooks.json:pre_tool_use:0:0']['trusted_hash']")" abc123
check "app-written MCP server preserved" "$(py "d['mcp_servers']['node_repl']['env']['APP_VERSION']")" 26.901
check "app-written plugin preserved" "$(py "d['plugins']['bundled@openai-bundled']['enabled']")" True
check "Codex-written notice subtable preserved" "$(py "d['notice']['model_migrations']['gpt-5.3-codex']")" gpt-5.4
check "TUI state preserved" "$(py "d['tui']['model_availability_nux']['gpt-5.5']")" 4
check "top-level key only live has preserved" "$(py "d['notify'][0]")" /some/app/path
check "a backup was written first" "$(find "$T/bak" -name config.toml | wc -l | tr -d ' ')" 1

before=$(shasum -a 256 <"$LIVE")
run --apply >/dev/null
check "a second --apply is a byte-identical no-op" "$(shasum -a 256 <"$LIVE")" "$before"
check "and writes no second backup" "$(find "$T/bak" -name config.toml | wc -l | tr -d ' ')" 1
check "--render agrees with the file on disk" "$(run --render | shasum -a 256)" "$before"

echo
echo "=== refusals ==="
printf 'model = "x"\n\n[projects."/p"]\ntrust_level = "trusted"\n' >"$T/leak.toml"
check "a tracked file carrying [projects] is refused (exit 2)" \
  "$(
    "$CC" --check --live "$LIVE" --tracked "$T/leak.toml" >/dev/null 2>&1
    echo $?
  )" 2
printf 'model = "x"\n\n[hooks.state."k"]\ntrusted_hash = "h"\n' >"$T/leak2.toml"
check "a tracked file carrying [hooks.state] is refused (exit 2)" \
  "$(
    "$CC" --check --live "$LIVE" --tracked "$T/leak2.toml" >/dev/null 2>&1
    echo $?
  )" 2
check "the real tracked file carries neither" \
  "$(
    "$CC" --check --live "$LIVE" --tracked "$ROOT/.codex/config.toml" >/dev/null 2>&1
    echo $?
  )" 1

echo
echo "=== hook trust ==="
cat >"$HOOKS" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "^Bash$", "hooks": [{ "type": "command", "command": "a.sh" }, { "type": "command", "command": "b.sh" }] }
    ],
    "SubagentStop": [{ "hooks": [{ "type": "command", "command": "c.sh" }] }]
  }
}
EOF
out=$(run --hooks-trust)
rc=$?
check "--hooks-trust exits 1 with three untrusted handlers" "$rc" 1
check "lists all three" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 3
cat >>"$LIVE" <<EOF

[hooks.state."$HOOKS:pre_tool_use:0:0"]
trusted_hash = "h1"

[hooks.state."$HOOKS:pre_tool_use:0:1"]
trusted_hash = "h2"
EOF
out=$(run --hooks-trust)
check "trust keys are <path>:<event label>:<group>:<handler>" "$(printf '%s\n' "$out")" "SubagentStop[0][0] c.sh"
cat >>"$LIVE" <<EOF

[hooks.state."$HOOKS:subagent_stop:0:0"]
trusted_hash = "h3"
EOF
check "--hooks-trust exits 0 once every handler is trusted" "$(
  run --hooks-trust >/dev/null
  echo $?
)" 0

echo
echo "=== emitter round-trip ==="
# The render-then-parse-back guard, on the real live config when there is one.
REAL="${CODEX_HOME:-$HOME/.codex}/config.toml"
[ -f "$REAL" ] || REAL="$LIVE"
python3 - "$CC" "$REAL" <<'EOF'
import importlib.machinery, importlib.util, sys, tomllib
sys.dont_write_bytecode = True  # or bin/__pycache__ appears and setup.sh symlinks it
loader = importlib.machinery.SourceFileLoader("cc", sys.argv[1])
spec = importlib.util.spec_from_loader("cc", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
with open(sys.argv[2], "rb") as fh:
    d = tomllib.load(fh)
assert tomllib.loads(m.render(d)) == d, "round-trip changed the data"
mutated = m._deepcopy(d)
mutated["model"] = "zz-negative-control"
assert tomllib.loads(m.render(mutated)) != d, "control: a changed dict must render differently"
try:
    m.render({"bad": object()})
except TypeError:
    pass
else:
    raise AssertionError("an unrepresentable value must be refused, not written")
EOF
check "render round-trips the live config, and the control detects a change" "$?" 0

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
