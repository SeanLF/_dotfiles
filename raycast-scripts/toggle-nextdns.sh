#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle NextDNS
# @raycast.mode compact

# Optional parameters:
# @raycast.icon shield
# @raycast.packageName Network

# Toggle NextDNS as system resolver.
# NextDNS has a forwarder for the tailnet -> Tailscale MagicDNS,
# so Tailscale names resolve in both states.

nextdns_active=false
scutil --dns 2>/dev/null | grep -q "nameserver.*127\.0\.0\.1" && nextdns_active=true

if $nextdns_active; then
  sudo /opt/homebrew/bin/nextdns deactivate
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder
  echo "NextDNS deactivated -- using DHCP DNS"
else
  sudo /opt/homebrew/bin/nextdns activate
  echo "NextDNS activated"
fi
