#!/bin/bash

# /etc/pam.d/sudo_local is Apple's supported include (Sonoma+); editing
# /etc/pam.d/sudo directly wouldn't survive macOS updates. The file is
# root-owned but world-readable, so we content-compare without sudo and only
# escalate to write.
setup_touchid() {
  local src="$DOTFILES_DIR/setup/sudo_local"
  local dst="/etc/pam.d/sudo_local"

  if [[ ! -f "$src" ]]; then
    warn "TouchID pam source not found: $src; skipping"
    return 0
  fi

  # BRE pattern: this runs before brew installs ugrep, so grep here is system
  # BSD grep on a fresh Mac.
  if ! grep -q 'auth.*include.*sudo_local' /etc/pam.d/sudo; then
    warn "/etc/pam.d/sudo does not include sudo_local, so the TouchID drop-in will be inert"
  fi

  if [[ -f "$dst" ]] && diff -q "$src" "$dst" &>/dev/null; then
    info "TouchID sudo: configured"
    return 0
  fi

  drift "TouchID sudo not enabled or drifted ($dst)"
  $DRY_RUN && return 0
  # install(1) writes atomically (temp + rename); safer than cp+chmod for an
  # auth-critical file that must never be truncated.
  sudo install -m 444 "$src" "$dst"
  info "TouchID sudo: enabled"
}
