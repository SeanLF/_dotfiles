# Dotfiles

Personal macOS dev environment config. One-command setup for a new machine. **macOS only** — uses Homebrew, `launchctl`, `softwareupdate`, and macOS `defaults`; no Linux/WSL support.

## What's Included

| File                    | Purpose                                                                          |
| ----------------------- | -------------------------------------------------------------------------------- |
| `Brewfile`              | Homebrew packages, casks, App Store apps, uv-managed Python CLIs                 |
| `.config/mise/`         | Runtime + CLI version management (ruby, python, node, most CLIs via aqua)        |
| `.zshrc`                | Shell config (fzf history, starship prompt, zoxide)                              |
| `aliases.zsh`           | Git aliases, docker shortcuts, utilities                                         |
| `.gitconfig`            | Commit signing, delta diffs, sensible defaults                                   |
| `.config/ghostty/`      | Terminal config                                                                  |
| `.config/starship.toml` | Prompt theme                                                                     |
| `.config/zed/`          | Zed editor settings                                                              |
| `.claude/`              | Claude Code config: CLAUDE.md preferences, hooks, slash commands, writing style  |
| `.ssh/config`           | SSH host config (1Password agent)                                                |
| `bin/`                  | Small scripts: `maint`, `online`, `nextdns-configure`, `tailscale-search-domain` |
| `raycast-scripts/`      | Raycast script commands (toggle/fix NextDNS) — point Raycast at this directory   |
| `lefthook.yml`          | Pre-commit hooks: shellcheck, ruff, taplo, prettier                              |
| `.editorconfig`         | Shared editor conventions (indentation, line endings, trailing whitespace)       |
| `setup.sh`              | Idempotent bootstrap with drift detection; backs up clobbered files              |

## Installation

```bash
git clone https://github.com/SeanLF/_dotfiles.git ~/Developer/_dotfiles
cd ~/Developer/_dotfiles
./setup.sh
```

Installs Xcode CLI tools, Homebrew, Brewfile packages, mise-managed tools, symlinks configs, and configures DNS. Run `./setup.sh --dry-run` to preview drift without applying changes, or pass a subset of modules (e.g. `./setup.sh symlinks tools`) — see `./setup.sh help`.

**Note:** Some Mac App Store apps may need manual install if not authenticated. If `setup.sh` finds pre-existing files where symlinks should go, it backs them up to `~/.dotfiles-backup/<timestamp>/` before replacing them.

## Maintenance

```bash
bin/maint           # run upgrades, then summarize with Claude Haiku
bin/maint --check   # preview outdated packages without upgrading
```

Updates Homebrew packages, App Store apps, Claude Code, mise runtimes, uv tools, tldr pages, re-dumps the Brewfile, and checks for macOS updates.
