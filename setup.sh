#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Silent success, loud failure
info() { echo "$1"; }
warn() { echo "WARNING: $1" >&2; }
error() { echo "ERROR: $1" >&2; exit 1; }

# Symlink with drift detection
symlink_with_diff() {
  local src="$1" dst="$2"

  if [[ -L "$dst" ]]; then
    # Already a symlink — check if pointing to correct target
    [[ "$(readlink "$dst")" == "$src" ]] && return 0
    info "Updating symlink: $dst"
    ln -sf "$src" "$dst"
  elif [[ -e "$dst" ]]; then
    # File exists but not a symlink — show diff
    echo "File exists at $dst (not a symlink)"
    if diff -q "$src" "$dst" &>/dev/null; then
      echo "  Contents identical, replacing with symlink"
    else
      echo "  Contents differ:"
      diff "$src" "$dst" || true
      read -p "  Replace with symlink to $src? [y/N] " response
      [[ ! "$response" =~ ^[Yy]$ ]] && return 0
    fi
    rm "$dst" && ln -s "$src" "$dst"
  else
    # Target doesn't exist — create symlink
    ln -s "$src" "$dst"
  fi
}

# Module: Core (Xcode CLI tools + Homebrew)
setup_core() {
  # Xcode Command Line Tools
  if ! xcode-select -p &>/dev/null; then
    info "Installing Xcode Command Line Tools..."
    xcode-select --install
    until xcode-select -p &>/dev/null; do
      sleep 5
    done
  fi

  # Homebrew
  if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ $(uname -m) == "arm64" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
}

# Module: Brew (install packages with drift detection)
setup_brew() {
  if ! command -v brew &>/dev/null; then
    error "Homebrew not installed. Run: ./setup.sh core"
  fi

  # Check for drift
  if brew bundle check --file="$DOTFILES_DIR/Brewfile" &>/dev/null; then
    info "Brewfile: no missing packages"
  else
    info "Brewfile drift detected:"
    brew bundle check --file="$DOTFILES_DIR/Brewfile" --verbose 2>&1 | grep -v "^Homebrew Bundle"
    echo ""
    read -p "Install missing packages? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      brew bundle --file="$DOTFILES_DIR/Brewfile" || warn "Some packages failed (mas apps may need manual install)"
    fi
  fi
}

# Module: Symlinks
setup_symlinks() {
  # Create config directories
  mkdir -p "$HOME/.config/ghostty" "$HOME/.config/mise" "$HOME/.config/zed" \
           "$HOME/.local/bin" "$HOME/.claude" "$HOME/.ssh" "$HOME/Developer"

  # Symlink scripts from bin/
  if compgen -G "$DOTFILES_DIR/bin/*" > /dev/null; then
    for script in "$DOTFILES_DIR"/bin/*; do
      symlink_with_diff "$script" "$HOME/.local/bin/$(basename "$script")"
    done
  fi

  # Symlink dotfiles
  symlink_with_diff "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
  symlink_with_diff "$DOTFILES_DIR/aliases.zsh" "$HOME/.aliases.zsh"
  symlink_with_diff "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
  symlink_with_diff "$DOTFILES_DIR/.gitignore_global" "$HOME/.gitignore_global"
  symlink_with_diff "$DOTFILES_DIR/.config/starship.toml" "$HOME/.config/starship.toml"
  symlink_with_diff "$DOTFILES_DIR/.config/ghostty/config" "$HOME/.config/ghostty/config"
  symlink_with_diff "$DOTFILES_DIR/.config/mise/config.toml" "$HOME/.config/mise/config.toml"
  symlink_with_diff "$DOTFILES_DIR/.config/zed/settings.json" "$HOME/.config/zed/settings.json"
  symlink_with_diff "$DOTFILES_DIR/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

  # SSH config (1Password agent)
  if [[ -f "$DOTFILES_DIR/.ssh/config" ]]; then
    symlink_with_diff "$DOTFILES_DIR/.ssh/config" "$HOME/.ssh/config"
  fi

  # Claude commands directory (remove existing, then symlink)
  if [[ -e "$HOME/.claude/commands" && ! -L "$HOME/.claude/commands" ]]; then
    warn "~/.claude/commands exists and is not a symlink"
    read -p "Remove and replace with symlink? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      rm -rf "$HOME/.claude/commands"
      ln -s "$DOTFILES_DIR/.claude/commands" "$HOME/.claude/commands"
    fi
  elif [[ ! -e "$HOME/.claude/commands" ]]; then
    ln -s "$DOTFILES_DIR/.claude/commands" "$HOME/.claude/commands"
  fi

  info "Symlinks: done"
}

# Module: SSH (verify 1Password agent)
setup_ssh() {
  local agent_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

  if [[ ! -S "$agent_sock" ]]; then
    warn "1Password SSH agent socket not found at: $agent_sock"
    warn "Ensure 1Password is installed and SSH agent is enabled in settings"
    return 1
  fi

  # Test agent
  if SSH_AUTH_SOCK="$agent_sock" ssh-add -l &>/dev/null; then
    info "SSH: 1Password agent working"
  else
    warn "SSH: 1Password agent found but no keys available"
    warn "Check 1Password SSH settings"
  fi
}

# Module: macOS defaults
setup_macos() {
  local macos_script="$DOTFILES_DIR/setup/macos_defaults.sh"
  if [[ ! -f "$macos_script" ]]; then
    warn "macOS defaults script not found: $macos_script"
    return 1
  fi

  # Requires bash 4+ for associative arrays
  local bash_path
  for path in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$path" ]] && bash_path="$path" && break
  done

  if [[ -z "$bash_path" ]]; then
    warn "Homebrew bash not found — run './setup.sh brew' first"
    warn "macOS defaults requires bash 4+ for associative arrays"
    return 1
  fi

  "$bash_path" "$macos_script"
}

# Help
show_help() {
  cat <<EOF
Usage: ./setup.sh [module...]

Modules:
  core      Install Xcode CLI tools and Homebrew
  brew      Install packages from Brewfile (with drift detection)
  symlinks  Create dotfile symlinks (with drift detection)
  ssh       Verify 1Password SSH agent
  macos     Apply macOS defaults (Finder, Dock, keyboard)
  all       Run all modules (default)

Examples:
  ./setup.sh              # Run all modules
  ./setup.sh core brew    # Just install tools and packages
  ./setup.sh symlinks     # Just update symlinks
  ./setup.sh macos        # Just apply macOS defaults
EOF
}

# Main
main() {
  local modules=("$@")

  # Default to all if no args
  if [[ ${#modules[@]} -eq 0 ]]; then
    modules=(core brew symlinks ssh)
  fi

  for module in "${modules[@]}"; do
    case "$module" in
      core)     setup_core ;;
      brew)     setup_brew ;;
      symlinks) setup_symlinks ;;
      ssh)      setup_ssh ;;
      macos)    setup_macos ;;
      all)      setup_core; setup_brew; setup_symlinks; setup_ssh ;;
      help|-h|--help) show_help; exit 0 ;;
      *)        error "Unknown module: $module. Run './setup.sh help' for usage." ;;
    esac
  done

  info "Done!"
}

main "$@"
