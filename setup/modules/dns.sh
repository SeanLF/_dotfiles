#!/bin/bash

setup_dns() {
  local ts="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  if [[ ! -x "$ts" ]]; then
    warn "Tailscale.app not installed. Run: ./setup.sh brew"
    return 1
  fi

  # The tailnet policy decides the NextDNS profile per device; the Mac only has
  # to accept Tailscale's DNS settings.
  if ! "$ts" dns status 2>/dev/null | grep -q "Tailscale DNS: enabled"; then
    drift "Tailscale DNS not accepted (system resolver is not 100.100.100.100)"
    $DRY_RUN || "$ts" set --accept-dns=true
  fi

  # Passwordless cache flush for raycast-scripts/{toggle,fix}-dns.sh.
  local sudoers="/etc/sudoers.d/raycast-dns"
  local sudoers_line="$USER ALL=(ALL) NOPASSWD: /usr/bin/dscacheutil -flushcache, /usr/bin/killall -HUP mDNSResponder"

  # Dry-runs must never prompt for a password (would deadlock in pre-push
  # hooks with no TTY), so probe with `sudo -n` first.
  write_sudoers() {
    echo "$sudoers_line" | sudo tee "$sudoers" >/dev/null
    sudo chmod 0440 "$sudoers"
  }

  if [[ ! -f "$sudoers" ]]; then
    drift "Raycast DNS sudoers not configured (passwordless cache flush)"
    $DRY_RUN || write_sudoers
  elif $DRY_RUN && ! sudo -n true 2>/dev/null; then
    info "Raycast DNS sudoers: exists (content not verified: no cached sudo)"
  elif [[ "$(sudo grep -v '^#' "$sudoers")" != "$sudoers_line" ]]; then
    drift "Raycast DNS sudoers content out of date"
    $DRY_RUN || write_sudoers
  fi

  info "DNS: done"
}
