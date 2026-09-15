#!/bin/bash
# The two Raycast DNS commands must drive Tailscale DNS, never the retired
# nextdns CLI. `tailscale`, `sudo`, `scutil` and `dig` are shimmed; the shim
# keeps Tailscale DNS state in a file so a toggle can be observed.
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
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2"; fi; }

mkdir -p "$SANDBOX/bin"
cat >"$SANDBOX/bin/tailscale" <<'EOF'
#!/bin/bash
echo "$*" >>"$TS_LOG"
case "$1 $2" in
  "dns status") if [[ "$(cat "$TS_STATE")" == on ]]; then echo "Tailscale DNS: enabled."; else echo "Tailscale DNS: disabled."; fi ;;
  "set --accept-dns=true") echo on >"$TS_STATE" ;;
  "set --accept-dns=false") echo off >"$TS_STATE" ;;
esac
exit 0
EOF
cat >"$SANDBOX/bin/scutil" <<'EOF'
#!/bin/bash
if [[ "$(cat "$TS_STATE")" == on ]]; then echo "  nameserver[0] : 100.100.100.100"; else echo "  nameserver[0] : 192.168.8.1"; fi
EOF
printf '#!/bin/bash\n"$@"\n' >"$SANDBOX/bin/sudo"
printf '#!/bin/bash\necho 93.184.216.34\n' >"$SANDBOX/bin/dig"
printf '#!/bin/bash\nexit 0\n' >"$SANDBOX/bin/dscacheutil"
printf '#!/bin/bash\nexit 0\n' >"$SANDBOX/bin/killall"
chmod +x "$SANDBOX"/bin/*

run() { # $1=script $2=initial state
  echo "$2" >"$SANDBOX/state"
  : >"$SANDBOX/ts.log"
  PATH="$SANDBOX/bin:$PATH" TS_STATE="$SANDBOX/state" TS_LOG="$SANDBOX/ts.log" TAILSCALE_BIN="$SANDBOX/bin/tailscale" \
    bash "$ROOT/raycast-scripts/$1" 2>&1
}
state() { cat "$SANDBOX/state"; }
sets() { rg -c "^set --accept-dns" "$SANDBOX/ts.log" || echo 0; }
mentions_nextdns_cli() { rg -c -i "nextdns.*(activate|deactivate|restart)" "$SANDBOX/ts.log" "$ROOT/raycast-scripts/$1" 2>/dev/null | rg -v ":0$" | wc -l | tr -d ' '; }

echo "=== toggle-dns ==="
out=$(run toggle-dns.sh on)
check "on -> off: Tailscale DNS disabled" "$(state)" off
check "on -> off: says network DNS is in use" "$(echo "$out" | rg -c -i 'network')" 1
out=$(run toggle-dns.sh off)
check "off -> on: Tailscale DNS enabled" "$(state)" on
check "off -> on: says Tailscale/NextDNS is in use" "$(echo "$out" | rg -c -i 'nextdns')" 1
check "toggle never touches the nextdns CLI" "$(mentions_nextdns_cli toggle-dns.sh)" 0

echo "=== fix-dns ==="
out=$(run fix-dns.sh off)
check "disabled -> enables Tailscale DNS" "$(state)" on
check "reports the fix" "$(echo "$out" | rg -c -i 'enabled Tailscale DNS')" 1
out=$(run fix-dns.sh on)
check "already enabled -> no set call" "$(sets)" 0
check "already enabled -> reports OK" "$(echo "$out" | rg -c 'DNS OK')" 1
check "fix never touches the nextdns CLI" "$(mentions_nextdns_cli fix-dns.sh)" 0

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
