#!/bin/bash

# Language runtimes and most GitHub-released CLIs live in .config/mise/config.toml.
# Python-based CLIs (e.g. thefuck) are tracked in the Brewfile as `uv "..."` entries
# and installed by `brew bundle`; setup_brew handles those.
setup_tools() {
  if ! command -v mise &>/dev/null; then
    error "mise not installed. Run: ./setup.sh brew"
  fi

  local missing prunable
  missing=$(mise ls --missing) || error "mise ls --missing failed; check mise status"
  prunable=$(mise ls --prunable) || error "mise ls --prunable failed; check mise status"

  if [[ -z "$missing" && -z "$prunable" ]]; then
    info "mise: no drift"
  fi

  if [[ -n "$missing" ]]; then
    drift "mise has missing tools:"
    echo "$missing"
    if ! $DRY_RUN; then
      echo ""
      read -rp "Install missing tools? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        mise install || warn "mise install failed"
      fi
    fi
  fi

  if [[ -n "$prunable" ]]; then
    drift "mise has tools not in config (prunable):"
    echo "$prunable"
    if ! $DRY_RUN; then
      echo ""
      read -rp "Prune these? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        mise prune --yes || warn "mise prune failed"
      fi
    fi
  fi

  # npm login writes its token into ~/.npmrc, so it stays a local file rather
  # than a symlink into this repo; only the release cooldown is ensured here.
  if [[ -L "$HOME/.npmrc" ]] || ! grep -qx 'min-release-age=3' "$HOME/.npmrc" 2>/dev/null; then
    drift "$HOME/.npmrc is a symlink or lacks min-release-age=3"
    if ! $DRY_RUN; then
      [[ -L "$HOME/.npmrc" ]] && rm "$HOME/.npmrc"
      echo 'min-release-age=3' >>"$HOME/.npmrc"
      chmod 600 "$HOME/.npmrc"
    fi
  fi

  # maintenance, advisory-scan and rex-job: this repo's Python package, editable
  # so a pull is the upgrade.
  if ! uv tool list 2>/dev/null | grep -q '^seanfloyd-dotfiles '; then
    drift "dotfiles commands (maintenance, advisory-scan, rex-job) not installed"
    $DRY_RUN || uv tool install --force --editable "$DOTFILES_DIR"
  fi
}
