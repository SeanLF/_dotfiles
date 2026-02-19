# Dotfiles

Personal macOS dev environment config. One-command setup for a new machine.

## What's Included

| File | Purpose |
|------|---------|
| `Brewfile` | Declarative packages, casks, App Store apps |
| `.zshrc` | Shell config (fzf history, starship prompt, zoxide) |
| `aliases.zsh` | Git aliases, docker shortcuts, utilities |
| `.gitconfig` | Commit signing, delta diffs, sensible defaults |
| `.config/ghostty/` | Terminal config |
| `.config/mise/` | Runtime version management (ruby, python, node, terraform) |
| `.config/starship.toml` | Prompt theme |
| `.config/zed/` | Zed editor settings |
| `.claude/` | Claude Code config: CLAUDE.md preferences, hooks, slash commands, writing style |
| `.ssh/config` | SSH host config |
| `bin/online` | Wait for network connectivity script |
| `maintenance.sh` | Update everything: Homebrew, App Store, Claude Code, mise, tldr, Brewfile sync |

## Installation

```bash
git clone https://github.com/SeanLF/_dotfiles.git ~/Developer/_dotfiles
cd ~/Developer/_dotfiles
./setup.sh
```

Installs Homebrew (if needed), packages from Brewfile, and symlinks configs.

**Note:** Some Mac App Store apps may need manual install if not authenticated.

## Maintenance

```bash
./maintenance.sh
```

Updates Homebrew packages, App Store apps, Claude Code, mise runtimes, tldr pages, re-dumps the Brewfile, and checks for macOS updates.
