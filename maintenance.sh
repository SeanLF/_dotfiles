#!/bin/bash
# System maintenance — run periodically to keep packages updated
set -e

info() { echo "$1"; }
warn() { echo "WARNING: $1" >&2; }

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BREWFILE="$DOTFILES_DIR/Brewfile"

# Update Homebrew and packages
info "Updating Homebrew packages..."
brew update
brew upgrade
brew upgrade --cask
brew cleanup

# Update App Store apps
info "Updating App Store apps..."
mas upgrade || warn "mas upgrade failed (may need App Store login)"

# Update tldr pages cache
info "Updating tldr pages..."
tldr --update

# Sync Brewfile with installed packages
info "Syncing Brewfile..."
if [[ -f "$BREWFILE" ]]; then
  brew bundle dump --file="$BREWFILE" --force --describe
  info "Brewfile updated"
else
  warn "Brewfile not found at $BREWFILE"
fi

# Check for macOS updates (doesn't install, just lists)
info "Checking for macOS updates..."
softwareupdate --list 2>&1 | grep -v "^Software Update Tool" || true

info "Done!"
