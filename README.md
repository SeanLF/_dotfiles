# Dotfiles

Personal macOS dev environment config. **macOS only** — uses Homebrew, `launchctl`, `softwareupdate`, and macOS `defaults`; no Linux/WSL support.

The two pieces worth pointing at:

- **`setup.sh` with drift detection.** Idempotent, modular, dry-runnable. Detects when a file is wrong (missing symlink, wrong target, out-of-date plist, missing Brewfile package, prunable mise tool) and reports before fixing. Any file it's about to clobber gets moved to `~/.dotfiles-backup/<timestamp>/` first, so nothing is ever destroyed. Run `./setup.sh --dry-run` to audit a machine without touching it.
- **`bin/maint` with Claude Haiku summaries.** Runs the full upgrade sweep (brew, mas, Claude Code, mise, uv, tldr, Brewfile re-dump, macOS updates) and pipes the output through Haiku for a human-readable summary of what actually changed. `bin/maint --check` previews without upgrading.

A few Homebrew entries (`bash`, `curl`, `less`, `perl`, `vim`) exist specifically to shadow the ancient versions Apple ships with macOS — they're not redundant with system tools, they replace them.

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
| `justfile`              | Dev tasks: `just check`, `just lint`, `just fmt`, `just dry-run`, `just deps`    |
| `lefthook.yml`          | Git hooks: lint staged files pre-commit, run `just check` pre-push               |
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
