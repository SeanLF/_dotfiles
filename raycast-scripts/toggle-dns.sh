#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle DNS
# @raycast.mode compact

# Optional parameters:
# @raycast.icon shield
# @raycast.packageName Network

# Off switches to the network's own DNS; captive portals need that to show
# their login page, so turn it back on afterwards.

TS="${TAILSCALE_BIN:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}"
[[ -x "$TS" ]] || TS=$(command -v tailscale) || {
  echo "tailscale not found"
  exit 1
}

if "$TS" dns status 2>/dev/null | grep -q "Tailscale DNS: enabled"; then
  "$TS" set --accept-dns=false
  msg="DNS: network resolver (captive-portal mode); MagicDNS off"
else
  "$TS" set --accept-dns=true
  msg="DNS: Tailscale -> NextDNS; MagicDNS on"
fi

# Flush both ways: answers cached from a captive portal's hijacking resolver
# must not outlive the switch back.
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null
echo "$msg"
