#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Fix DNS
# @raycast.mode compact

# Optional parameters:
# @raycast.icon globe
# @raycast.packageName Network

# DNS stack:
#   NextDNS daemon on 127.0.0.1:53 -- always-on system resolver, local cache, ad/malware/phishing blocking
#   Tailscale MagicDNS via NextDNS forwarder + search domain (--accept-dns=false)
#   ProtonVPN: custom DNS set to 127.0.0.1 (routes through NextDNS inside tunnel)

DIR="$(dirname "$0")/.."
fixes=()

# Ensure NextDNS daemon is running
if ! dig @127.0.0.1 example.com +short +time=1 +tries=1 &>/dev/null; then
  sudo /opt/homebrew/bin/nextdns restart &>/dev/null
  fixes+=("restarted NextDNS")
fi

# Ensure 127.0.0.1 is the system resolver
if ! scutil --dns 2>/dev/null | grep -q "127.0.0.1"; then
  sudo /opt/homebrew/bin/nextdns activate &>/dev/null
  fixes+=("activated NextDNS")
fi

# Ensure Tailscale isn't overriding DNS
if /usr/local/bin/tailscale dns status 2>/dev/null | grep -q "Tailscale DNS: enabled"; then
  /usr/local/bin/tailscale set --accept-dns=false 2>/dev/null
  fixes+=("disabled Tailscale DNS override")
fi

# Ensure MagicDNS search domain is set (shared script, also runs at boot)
if ! scutil --dns 2>/dev/null | grep -q "ts.net"; then
  sudo "$DIR/bin/tailscale-search-domain" 2>/dev/null
  fixes+=("added MagicDNS search domain")
fi

# Flush cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null

# Verify MagicDNS
if /usr/local/bin/tailscale status &>/dev/null && ! dig "$(hostname -s)" +short +time=2 +tries=1 &>/dev/null; then
  fixes+=("MagicDNS not resolving")
fi

if [[ ${#fixes[@]} -eq 0 ]]; then
  echo "DNS OK (NextDNS + MagicDNS)"
else
  echo "Fixed: ${fixes[*]}"
fi
