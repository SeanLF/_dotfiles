# Dotfiles

Personal macOS dev environment config. One-command setup for a new machine.

## What's Included

| File | Purpose |
|------|---------|
| `Brewfile` | Declarative packages, casks, App Store apps, Cursor extensions |
| `.zshrc` | Shell config (fzf history, starship prompt, zoxide) |
| `aliases.zsh` | Git aliases, docker shortcuts, utilities |
| `.gitconfig` | Commit signing, diff-so-fancy, sensible defaults |
| `.config/ghostty/` | Terminal config |
| `.config/mise/` | Runtime version management (ruby, python, node, terraform) |
| `.config/starship.toml` | Prompt theme |
| `.claude/CLAUDE.md` | Claude Code preferences |
| `bin/online` | Wait for network connectivity script |

## Installation

```bash
git clone https://github.com/SeanLF/_dotfiles.git ~/Developer/_dotfiles
cd ~/Developer/_dotfiles
./setup.sh
```

Installs Homebrew (if needed), packages from Brewfile, and symlinks configs.

**Note:** Some Mac App Store apps may need manual install if not authenticated.

## Updating Packages

```bash
brew update && brew upgrade && brew upgrade --cask
mas upgrade
mise upgrade
```
