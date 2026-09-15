#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Fix DNS
# @raycast.mode compact

# Optional parameters:
# @raycast.icon globe
# @raycast.packageName Network

# DNS stack: Tailscale DNS (100.100.100.100) -> NextDNS over DoH, per-device
# profile from the tailnet policy; MagicDNS and the ts.net search domain come
# with it. Nothing else should be configuring the resolver.

TS="${TAILSCALE_BIN:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}"
[[ -x "$TS" ]] || TS=$(command -v tailscale) || {
  echo "tailscale not found"
  exit 1
}
fixes=()

if ! "$TS" dns status 2>/dev/null | grep -q "Tailscale DNS: enabled"; then
  "$TS" set --accept-dns=true && fixes+=("enabled Tailscale DNS")
fi

sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null

scutil --dns 2>/dev/null | grep -q "nameserver.*100\.100\.100\.100" || fixes+=("resolver is NOT 100.100.100.100; is Tailscale connected?")
dig +short +time=2 +tries=1 example.com >/dev/null 2>&1 || fixes+=("public names not resolving")
dig +short +time=2 +tries=1 "$(hostname -s)" >/dev/null 2>&1 || fixes+=("MagicDNS not resolving")

if [[ ${#fixes[@]} -eq 0 ]]; then
  echo "DNS OK (Tailscale -> NextDNS, MagicDNS)"
else
  echo "Fixed/found: ${fixes[*]}"
fi
