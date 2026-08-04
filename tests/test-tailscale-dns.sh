#!/bin/bash
# Executable form of the claims bin/tailscale-search-domain relies on.
#
# Every assertion here was a comment first. They are facts about scutil and about
# tailscale's JSON, both of which belong to someone else and can change under us;
# a comment saying "scutil writes errors to stdout" goes stale silently, this
# does not.
#
# Read-only with respect to the real DNS config. The one key it writes is under
# State:/Network/Service/ClaudeProbe/DNS with NO ServerAddresses, so configd
# builds no resolver from it, and it is removed again immediately.
set -uo pipefail

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

PROBE="State:/Network/Service/ClaudeProbe/DNS"

echo "=== scutil behaviour the script depends on ==="

# The whole reason remove_key parses stdout instead of checking $?.
out=$(
  scutil <<EOF
open
remove $PROBE
EOF
)
rc=$?
check "scutil exits 0 even when it refuses" "$rc" 0
check "scutil writes its error to STDOUT, not stderr" \
  "$(case "$out" in *"Permission denied"* | *"No such key"*) echo stdout ;; *) echo elsewhere ;; esac)" stdout

err=$(
  scutil 2>&1 >/dev/null <<EOF
open
remove $PROBE
EOF
)
check "stderr is empty, so 2>/dev/null would have hidden nothing useful" "${err:-empty}" empty

# Why the set path has no `open` and has never needed one.
if [ "$(id -u)" -eq 0 ]; then
  scutil >/dev/null <<EOF
d.init
d.add SearchDomains * probe.invalid
set $PROBE
EOF
  check "set works without an open (no ServerAddresses, so no resolver is built)" \
    "$(
      scutil <<EOF 2>&1 | rg -c 'probe.invalid' || echo 0
open
show $PROBE
EOF
    )" 1
  scutil >/dev/null 2>&1 <<EOF
open
remove $PROBE
EOF
  check "probe key removed again" \
    "$(
      scutil <<EOF 2>&1 | rg -c 'No such key' || echo 0
open
show $PROBE
EOF
    )" 1
else
  echo "  SKIP set-path assertions (need root: sudo $0)"
fi

echo
echo "=== tailscale JSON shape the script parses ==="
if [ -x /usr/local/bin/tailscale ]; then
  json=$(/usr/local/bin/tailscale status --json 2>/dev/null)
  check "BackendState is present" \
    "$(printf '%s' "$json" | /usr/bin/python3 -c 'import sys,json; print("yes" if "BackendState" in json.load(sys.stdin) else "no")' 2>/dev/null)" yes
  # The reason BackendState gates the script rather than MagicDNSSuffix: the
  # suffix reflects tailnet membership and outlives the tunnel.
  state=$(printf '%s' "$json" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("BackendState",""))' 2>/dev/null)
  suffix=$(printf '%s' "$json" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("CurrentTailnet",{}).get("MagicDNSSuffix",""))' 2>/dev/null)
  if [ "$state" != "Running" ] && [ -n "$suffix" ]; then
    ok "suffix outlives the tunnel (state=$state, suffix set), which is why BackendState gates and not the suffix"
    PASS=$((PASS))
  else
    echo "  INFO state=$state suffix=${suffix:-none}; the outlives-the-tunnel case needs a stopped tunnel to observe"
  fi
  # Malformed input must fall through to teardown, never to "leave the key".
  check "empty JSON yields an empty state, which the script treats as not-Running" \
    "$(printf '' | /usr/bin/python3 -c 'import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print("")
  raise SystemExit
print(d.get("BackendState",""))' 2>/dev/null | tr -d '\n')" ""
else
  echo "  SKIP tailscale assertions (binary not at /usr/local/bin/tailscale)"
fi

echo
printf 'tailscale-dns: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
