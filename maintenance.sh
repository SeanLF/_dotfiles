#!/bin/bash
# System maintenance — run periodically to keep packages updated
set -e

info() { echo "$1"; }
warn() { echo "WARNING: $1" >&2; failures+=("$1"); }

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BREWFILE="$DOTFILES_DIR/Brewfile"
failures=()

# Bail early if offline
if ! online -q 5; then
  echo "No network connectivity — skipping maintenance"
  exit 1
fi

# Update Homebrew and packages
info "Updating Homebrew packages..."
brew update || warn "brew update failed"
brew upgrade || warn "brew upgrade failed"
brew upgrade --cask || warn "brew upgrade --cask failed"
brew cleanup || warn "brew cleanup failed"

# Update App Store apps
info "Updating App Store apps..."
mas upgrade || warn "mas upgrade failed (may need App Store login)"

# Update Claude Code
# Workaround: claude update downloads the full binary (~200MB) even when
# already up-to-date. Check versions first to skip the download.
# https://github.com/anthropics/claude-code/issues/20808
info "Updating Claude Code..."
local_ver="$(claude --version 2>/dev/null | awk '{print $1}' || true)"
dist_url="$(curl -sI https://claude.ai/install.sh 2>/dev/null \
  | grep -i '^location:' | tr -d '\r' \
  | sed 's/^[Ll]ocation: //; s|/bootstrap\.sh$||')"
remote_ver="$(curl -sf "$dist_url/latest" 2>/dev/null || true)"
if [[ -z "$remote_ver" ]]; then
  warn "could not check latest Claude Code version, running claude update"
  claude update || warn "claude update failed"
elif [[ "$local_ver" == "$remote_ver" ]]; then
  info "Claude Code is already up to date ($local_ver)"
else
  info "Claude Code $local_ver -> $remote_ver"
  claude update || warn "claude update failed"
fi
unset local_ver dist_url remote_ver

# Update mise tools
info "Updating mise tools..."
mise upgrade || warn "mise upgrade failed"

# Update tldr pages cache
info "Updating tldr pages..."
tldr --update || warn "tldr --update failed"

# Sync Brewfile with installed packages
info "Syncing Brewfile..."
if [[ -f "$BREWFILE" ]]; then
  brew bundle dump --file="$BREWFILE" --force --describe || warn "brew bundle dump failed"
  info "Brewfile updated"
else
  warn "Brewfile not found at $BREWFILE"
fi

# Check for macOS updates (doesn't install, just lists)
info "Checking for macOS updates..."
softwareupdate --list 2>&1 | grep -v "^Software Update Tool" || true

# Recap
if [[ ${#failures[@]} -gt 0 ]]; then
  echo ""
  echo "Finished with ${#failures[@]} warning(s):"
  for f in "${failures[@]}"; do echo "  - $f"; done
  exit 1
else
  info "Done — all clear!"
fi
