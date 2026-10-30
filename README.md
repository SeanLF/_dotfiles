# Dotfiles

Personal macOS dev environment config. **macOS only** — uses Homebrew, `launchctl`, `softwareupdate`, and macOS `defaults`; no Linux/WSL support.

The two pieces worth pointing at:

- **`setup.sh` with drift detection.** Idempotent, modular, dry-runnable. Detects when a file is wrong (missing symlink, wrong target, out-of-date plist, missing Brewfile package, prunable mise tool) and reports before fixing. Any file it's about to clobber gets moved to `~/.dotfiles-backup/<timestamp>/` first, so nothing is ever destroyed. Run `./setup.sh --dry-run` to audit a machine without touching it. Each module lives in `setup/modules/`.
- **`maintenance`, once a day while you're away.** Snapshots resolved tool versions (for rollback), then runs each step of `lib/maintenance/upgrades.sh` (brew, mas, Xcode betas via xcodes, Claude Code + plugins/skills, mise, gems, rustup, uv, tldr, macOS updates that need no restart, Brewfile re-dump) as soon as the steps it depends on finish, then the read-only checks in `lib/maintenance/audits.sh` and `advisory-scan` (grype and CISA's exploited-vulnerability list) on what's now installed. Inside Rex, four side panes run the steps while the main pane shows the dependency graph live; `maintenance --graph` prints it. `maintenance --check` previews without upgrading.
- **`rex-job`, for anything unattended.** Runs a command in its own Rex session that reports its state in the tab and session picker, shows when a pane waits on Touch ID, and stays open only if the command's exit code says it needs you (Enter then starts Claude on its report). launchd runs `rex-job --daily-when-idle maintenance -- maintenance` hourly; it starts once a day, after 15 idle minutes.

A few Homebrew entries (`bash`, `curl`, `less`, `perl`, `vim`) exist specifically to shadow the ancient versions Apple ships with macOS — they're not redundant with system tools, they replace them.

## What's Included

| File                                | Purpose                                                                                                                                                                                                                                                                    |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Brewfile`                          | Homebrew packages, casks, App Store apps, uv-managed Python CLIs                                                                                                                                                                                                           |
| `.config/mise/`                     | Runtime + CLI version management (ruby, python, node, most CLIs via aqua)                                                                                                                                                                                                  |
| `.zshrc`                            | Shell config (fzf history, starship prompt, zoxide)                                                                                                                                                                                                                        |
| `aliases.zsh`                       | Git aliases, docker shortcuts, utilities                                                                                                                                                                                                                                   |
| `.gitconfig`                        | Commit signing, delta diffs, sensible defaults                                                                                                                                                                                                                             |
| `.config/ghostty/`                  | Terminal config                                                                                                                                                                                                                                                            |
| `.config/starship.toml`             | Prompt theme                                                                                                                                                                                                                                                               |
| `.config/zed/`                      | Zed editor settings                                                                                                                                                                                                                                                        |
| `AGENTS.md`                         | One instruction file for every agent CLI: Claude Code, Codex, Gemini, Antigravity                                                                                                                                                                                          |
| `.claude/`                          | Claude Code config: settings, hooks, agents, skills, slash commands                                                                                                                                                                                                        |
| `.codex/`                           | Codex config: tracked `config.toml` (rendered, not symlinked), `hooks.json` mirroring the Claude guards, agent roles, rules                                                                                                                                                |
| `.ssh/config`                       | SSH host config (1Password agent)                                                                                                                                                                                                                                          |
| `bin/`                              | The agent review gate (`review-gate`, `record-review`, `check-commit-msg`), Claude Code on other backends (`ccl` local llama.cpp, `ccnim` NVIDIA NIM), session spend (`cache-meter`), `codex-config`, `online`, `nextdns-configure` (NextDNS profile settings via the API) |
| `raycast-scripts/`                  | Raycast script commands (toggle/fix Tailscale DNS) — point Raycast at this directory                                                                                                                                                                                       |
| `justfile`                          | Dev tasks: `just check`, `just lint`, `just fmt`, `just dry-run`, `just deps`                                                                                                                                                                                              |
| `lefthook.yml`                      | Git hooks: lint staged files pre-commit, run `just check` pre-push                                                                                                                                                                                                         |
| `.editorconfig`                     | Shared editor conventions (indentation, line endings, trailing whitespace)                                                                                                                                                                                                 |
| `setup.sh`, `setup/`                | Idempotent bootstrap with drift detection; backs up clobbered files. One file per module in `setup/modules/`                                                                                                                                                               |
| `src/dotfiles/`, `lib/maintenance/` | `maintenance`, `advisory-scan` and `rex-job`, a Python package `setup.sh tools` installs with `uv tool install --editable`; the shell steps `maintenance` runs                                                                                                             |

## Installation

```bash
git clone https://github.com/SeanLF/_dotfiles.git ~/Developer/_dotfiles
cd ~/Developer/_dotfiles
./setup.sh
```

Installs Xcode CLI tools, Homebrew, Brewfile packages, mise-managed tools, symlinks configs, and turns on Tailscale DNS (which forwards to NextDNS under the tailnet policy). Run `./setup.sh --dry-run` to preview drift without applying changes, or pass a subset of modules (e.g. `./setup.sh symlinks tools`) — see `./setup.sh help`.

**Note:** Some Mac App Store apps may need manual install if not authenticated. If `setup.sh` finds pre-existing files where symlinks should go, it backs them up to `~/.dotfiles-backup/<timestamp>/` before replacing them.

## Maintenance

```bash
maintenance                         # run upgrades, then print what changed
maintenance --check                 # preview outdated packages without upgrading
maintenance --graph                 # what each step waits for
rex-job maintenance -- maintenance  # run it in its own Rex session
```

Updates Homebrew packages, App Store apps (stable Xcode included; betas via xcodes), Claude Code and its plugins, mise runtimes, uv tools, tldr pages, re-dumps the Brewfile, and checks for macOS updates.
