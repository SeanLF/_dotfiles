#!/bin/bash
# Run with the `bash` on PATH (brew, 5.x), not /bin/bash 3.2: under `set -e`,
# `((count++))` from zero returns non-zero and would kill the script before
# the retry loop ran, and 3.2 tolerates that silently. `ping` is shimmed.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
PASS=0 FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf '  \033[32mPASS\033[0m %s\n' "$1"
}
no() {
  FAIL=$((FAIL + 1))
  printf '  \033[31mFAIL\033[0m %s\n    got: %s\n' "$1" "$2"
}
check() { # $1 label, $2 got, $3 want
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2"; fi
}

mkdir -p "$SANDBOX/bin"
cat >"$SANDBOX/bin/ping" <<'EOF'
#!/bin/bash
echo "$$" >>"$PING_LOG"
exit "${PING_EXIT:-1}"
EOF
chmod +x "$SANDBOX/bin/ping"
# `sleep` is shimmed too so the timeout case runs in milliseconds.
printf '#!/bin/bash\nexit 0\n' >"$SANDBOX/bin/sleep"
chmod +x "$SANDBOX/bin/sleep"

online() { PATH="$SANDBOX/bin:$PATH" PING_LOG="$SANDBOX/pings" bash "$ROOT/bin/online" -q "$@"; }

: >"$SANDBOX/pings"
PING_EXIT=1 online 5
check "unreachable host times out with exit 1" "$?" 1
check "the loop kept pinging until the timeout" "$(wc -l <"$SANDBOX/pings" | tr -d ' ')" 5

: >"$SANDBOX/pings"
PING_EXIT=0 online 5
check "reachable host exits 0" "$?" 0
check "a reachable host is pinged once" "$(wc -l <"$SANDBOX/pings" | tr -d ' ')" 1

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
