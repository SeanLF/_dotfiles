#!/bin/bash

# Create symbolic links for dotfiles
ln -sf "$(pwd)/.zshrc" "$HOME/.zshrc"
ln -sf "$(pwd)/.gitconfig" "$HOME/.gitconfig"

# Install Xcode Command Line Tools if not already installed
if ! xcode-select -p &>/dev/null; then
  echo "Installing Xcode Command Line Tools..."
  xcode-select --install
  # Wait for xcode-select to be installed
  until xcode-select -p &>/dev/null; do
    sleep 5
    echo "Waiting for Xcode Command Line Tools to complete installation..."
  done
  echo "Xcode Command Line Tools installation complete!"
else
  echo "Xcode Command Line Tools already installed."
fi

# Install Homebrew if not already installed
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  
  # Add Homebrew to PATH based on architecture (Intel or Apple Silicon)
  if [[ $(uname -m) == "arm64" ]]; then
    # For Apple Silicon Macs
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    # For Intel Macs
    echo 'eval "$(/usr/local/bin/brew shellenv)"' >> $HOME/.zprofile
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  
  echo "Homebrew installation complete!"
else
  echo "Homebrew already installed, updating..."
  brew update
fi

# Install packages and applications using Homebrew
echo "Installing Homebrew packages and applications..."

# Core brew packages - only the ones you explicitly want, not dependencies
brew_packages=(
  # Development tools
  git
  gh
  
  # Shell utilities
  starship
  ripgrep
  fzf
  jq
  bat
  eza
  fd
  zoxide
  htop
  diff-so-fancy
  thefuck
  mise
  nping
  
  # Other utilities
  mas             # Mac App Store CLI
  webtorrent-cli
)

# Brew casks (applications)
brew_casks=(
  # Dev tools
  visual-studio-code
  cursor
  orbstack        # Docker alternative
  github
  
  # Browsers and communication
  arc
  slack
  
  # Utilities
  1password
  raycast
  keybase
  
  # Media and other
  iina
  boop
  transmission
  ghostty
  protonvpn
  postico
  chatgpt
)

# Install brew packages
for package in "${brew_packages[@]}"; do
  if brew list --formula | grep -q "^$package\$"; then
    echo "$package is already installed, skipping..."
  else
    echo "Installing $package..."
    brew install "$package"
  fi
done

# Install brew casks
for cask in "${brew_casks[@]}"; do
  if brew list --cask | grep -q "^$cask\$"; then
    echo "$cask is already installed, skipping..."
  else
    echo "Installing $cask..."
    brew install --cask "$cask"
  fi
done

echo "Homebrew installations complete!"

ln -sf "$(pwd)/.gitignore_global" "$HOME/.gitignore_global"

# Create config directories if they don't exist
mkdir -p "$HOME/.config"
mkdir -p "$HOME/Library/Application Support/Code/User"

# Link config files
ln -sf "$(pwd)/.config/starship.toml" "$HOME/.config/starship.toml"
ln -sf "$(pwd)/.config/Code/User/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"
ln -sf "$(pwd)/.config/Code/User/extensions.json" "$HOME/Library/Application Support/Code/User/extensions.json"

echo "Dotfiles have been symlinked to your home directory."
