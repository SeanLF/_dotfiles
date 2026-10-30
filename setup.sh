#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=false

# Also what `all` runs; `macos` is opt-in only. `touchid` runs early so every
# later sudo (notably `dns`) is a fingerprint tap, not a password.
DEFAULT_MODULES=(core touchid brew shell symlinks kbbl codex tools ai_clis ssh dns schedules)

# Each sourced file is linted on its own.
# shellcheck source=/dev/null
source "$DOTFILES_DIR/setup/lib.sh"
for module in "$DOTFILES_DIR"/setup/modules/*.sh; do
  # shellcheck source=/dev/null
  source "$module"
done

show_help() {
  cat <<EOF
Usage: ./setup.sh [--dry-run] [module...]

Flags:
  --dry-run   Report drift without changing anything

Modules:
  core      Install Xcode CLI tools and Homebrew
  touchid   Enable TouchID for sudo (native prompt via pam_tid drop-in)
  brew      Install packages from Brewfile (with drift detection)
  shell     Make brew's zsh the login shell
  tools     mise tools, npm's release cooldown, and this repo's commands (uv)
  ai_clis   Install Claude Code and Antigravity CLI (direct installers)
  symlinks  Create dotfile symlinks (with drift detection)
  kbbl      Compile kbbl into ~/.local/bin
  codex     Render ~/.codex/config.toml from .codex/config.toml; report untrusted hooks
  ssh       Verify 1Password SSH agent
  dns       Accept Tailscale DNS (NextDNS via tailnet policy) + Raycast sudoers
  schedules  Daily maintenance via rex-job, when idle (launchd)
  macos     Apply macOS defaults (Finder, Dock, keyboard)
  all       Run all modules (default)

Examples:
  ./setup.sh              # Run all modules
  ./setup.sh core brew    # Just install tools and packages
  ./setup.sh symlinks     # Just update symlinks
  ./setup.sh macos        # Just apply macOS defaults
EOF
}

main() {
  local modules=()

  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=true ;;
      *) modules+=("$arg") ;;
    esac
  done

  $DRY_RUN && info "=== DRY RUN (no changes) ==="

  if [[ ${#modules[@]} -eq 0 ]] || [[ " ${modules[*]} " == *" all "* ]]; then
    modules=("${DEFAULT_MODULES[@]}")
  fi

  for module in "${modules[@]}"; do
    case "$module" in
      help | -h | --help)
        show_help
        exit 0
        ;;
      *)
        declare -F "setup_$module" >/dev/null || error "Unknown module: $module. Run './setup.sh help' for usage."
        "setup_$module"
        ;;
    esac
  done

  info "Done!"
}

main "$@"
