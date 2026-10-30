#!/bin/bash

setup_brew() {
  if ! command -v brew &>/dev/null; then
    error "Homebrew not installed. Run: ./setup.sh core"
  fi

  if brew bundle check --file="$DOTFILES_DIR/Brewfile" &>/dev/null; then
    info "Brewfile: no drift"
  else
    drift "Brewfile has missing packages:"
    brew bundle check --file="$DOTFILES_DIR/Brewfile" --verbose 2>&1 | grep -v "^Homebrew Bundle"
    if ! $DRY_RUN; then
      echo ""
      read -rp "Install missing packages? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        brew bundle --file="$DOTFILES_DIR/Brewfile" || warn "Some packages failed (mas apps may need manual install)"
      fi
    fi
  fi

}
