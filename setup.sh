#!/bin/bash

# Create symbolic links for dotfiles
ln -sf "$(pwd)/.zshrc" "$HOME/.zshrc"
ln -sf "$(pwd)/.gitconfig" "$HOME/.gitconfig"
ln -sf "$(pwd)/.gitignore_global" "$HOME/.gitignore_global"

# Create config directories if they don't exist
mkdir -p "$HOME/.config"
mkdir -p "$HOME/Library/Application Support/Code/User"

# Link config files
ln -sf "$(pwd)/.config/starship.toml" "$HOME/.config/starship.toml"
ln -sf "$(pwd)/.config/Code/User/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"
ln -sf "$(pwd)/.config/Code/User/extensions.json" "$HOME/Library/Application Support/Code/User/extensions.json"

echo "Dotfiles have been symlinked to your home directory."
