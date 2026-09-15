#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle DNS
# @raycast.mode compact

# Optional parameters:
# @raycast.icon shield
# @raycast.packageName Network

# Tailscale DNS on: system resolver is 100.100.100.100, which answers MagicDNS
# itself and forwards everything else to NextDNS over DoH.
# Tailscale DNS off: the network's own DNS. Captive portals need this state to
# show their login page; turn it back on afterwards.

TS="${TAILSCALE_BIN:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}"
[[ -x "$TS" ]] || TS=$(command -v tailscale) || {
  echo "tailscale not found"
  exit 1
}

if "$TS" dns status 2>/dev/null | grep -q "Tailscale DNS: enabled"; then
  "$TS" set --accept-dns=false
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder 2>/dev/null
  echo "DNS: network resolver (captive-portal mode); MagicDNS off"
else
  "$TS" set --accept-dns=true
  echo "DNS: Tailscale -> NextDNS; MagicDNS on"
fi
