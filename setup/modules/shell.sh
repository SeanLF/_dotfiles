#!/bin/bash

# Login shell: brew's zsh, current where Apple's /bin/zsh lags a macOS behind.
# /bin/zsh stays as the fallback, and #!/bin/zsh scripts keep using it.
setup_shell() {
  local zsh="${HOMEBREW_PREFIX:-/opt/homebrew}/bin/zsh"
  if [[ ! -x "$zsh" ]]; then
    warn "brew zsh not installed. Run: ./setup.sh brew"
    return 0
  fi
  if ! grep -qxF "$zsh" /etc/shells; then
    drift "$zsh not in /etc/shells"
    $DRY_RUN || echo "$zsh" | sudo tee -a /etc/shells >/dev/null
  fi
  if [[ "$(dscl . -read "$HOME" UserShell | awk '{print $2}')" != "$zsh" ]]; then
    drift "login shell is not $zsh"
    $DRY_RUN || sudo chsh -s "$zsh" "$USER"
  fi
  info "Shell: done"
}
