#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install Xcode Command Line Tools if needed
if ! xcode-select -p &>/dev/null; then
  echo "Installing Xcode Command Line Tools..."
  xcode-select --install
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
fi

# Install Homebrew if needed
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ $(uname -m) == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# Install everything from Brewfile (mas apps may need manual install if not authenticated)
echo "Installing from Brewfile..."
brew bundle --file="$DOTFILES_DIR/Brewfile" || echo "Some packages failed to install (mas apps may need manual install)"

# Create config directories
mkdir -p "$HOME/.config/ghostty"
mkdir -p "$HOME/.config/mise"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.claude"

# Symlink scripts (if bin/ exists and has files)
if compgen -G "$DOTFILES_DIR/bin/*" > /dev/null; then
  for script in "$DOTFILES_DIR"/bin/*; do
    ln -sf "$script" "$HOME/.local/bin/$(basename "$script")"
  done
fi

# Symlink dotfiles
ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
ln -sf "$DOTFILES_DIR/aliases.zsh" "$HOME/.aliases.zsh"
ln -sf "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
ln -sf "$DOTFILES_DIR/.gitignore_global" "$HOME/.gitignore_global"
ln -sf "$DOTFILES_DIR/.config/starship.toml" "$HOME/.config/starship.toml"
ln -sf "$DOTFILES_DIR/.config/ghostty/config" "$HOME/.config/ghostty/config"
ln -sf "$DOTFILES_DIR/.config/mise/config.toml" "$HOME/.config/mise/config.toml"
ln -sf "$DOTFILES_DIR/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
rm -rf "$HOME/.claude/commands" 2>/dev/null
ln -sf "$DOTFILES_DIR/.claude/commands" "$HOME/.claude/commands"

echo "Done! Restarting shell..."
exec zsh -l
