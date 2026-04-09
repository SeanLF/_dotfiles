#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false

# Move a pre-existing file/dir out of the way before we clobber it, so the
# previous contents are always recoverable from ~/.dotfiles-backup/<timestamp>/.
# All current call sites pass paths under $HOME; guard against anything else
# escaping the backup root via a leading slash.
backup() {
  local path="$1"
  if [[ "$path" != "$HOME/"* ]]; then
    error "refusing to backup path outside \$HOME: $path"
  fi
  local rel="${path#"$HOME"/}"
  local dest="$BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  mv "$path" "$dest"
  info "  backed up to $dest"
}

# Default module order — also what `all` runs. `macos` is opt-in only.
DEFAULT_MODULES=(core brew symlinks tools ssh dns)

# Silent success, loud failure
info() { echo "$1"; }
drift() { if $DRY_RUN; then echo "DRIFT: $1"; else echo "FIXING: $1"; fi; }
warn() { echo "WARNING: $1" >&2; }
error() {
  echo "ERROR: $1" >&2
  exit 1
}

# Symlink a directory, replacing any pre-existing non-symlink after confirmation.
# Used for directories where we can't diff contents (e.g. ~/.claude/commands).
symlink_dir() {
  local src="$1" dst="$2"

  if [[ -L "$dst" ]]; then
    [[ "$(readlink "$dst")" == "$src" ]] && return 0
    drift "$dst -> wrong target ($(readlink "$dst"), expected $src)"
    $DRY_RUN && return 0
    ln -sfn "$src" "$dst"
  elif [[ -e "$dst" ]]; then
    drift "$dst exists and is not a symlink"
    $DRY_RUN && return 0
    read -rp "  Back up and replace with symlink to $src? [y/N] " response
    [[ ! "$response" =~ ^[Yy]$ ]] && return 0
    backup "$dst" && ln -s "$src" "$dst"
  else
    drift "$dst missing"
    $DRY_RUN && return 0
    ln -s "$src" "$dst"
  fi
}

# Symlink with drift detection
symlink_with_diff() {
  local src="$1" dst="$2"

  if [[ -L "$dst" ]]; then
    [[ "$(readlink "$dst")" == "$src" ]] && return 0
    drift "$dst -> wrong target ($(readlink "$dst"), expected $src)"
    $DRY_RUN && return 0
    ln -sf "$src" "$dst"
  elif [[ -e "$dst" ]]; then
    if diff -q "$src" "$dst" &>/dev/null; then
      drift "$dst exists (not a symlink, contents identical)"
      $DRY_RUN && return 0
      backup "$dst" && ln -s "$src" "$dst"
    else
      drift "$dst exists (not a symlink, contents differ)"
      $DRY_RUN && return 0
      diff "$src" "$dst" || true
      read -rp "  Back up and replace with symlink to $src? [y/N] " response
      [[ ! "$response" =~ ^[Yy]$ ]] && return 0
      backup "$dst" && ln -s "$src" "$dst"
    fi
  else
    drift "$dst missing"
    $DRY_RUN && return 0
    ln -s "$src" "$dst"
  fi
}

# Module: Core (Xcode CLI tools + Homebrew)
setup_core() {
  if ! xcode-select -p &>/dev/null; then
    drift "Xcode CLI tools not installed"
    if ! $DRY_RUN; then
      xcode-select --install
      until xcode-select -p &>/dev/null; do sleep 5; done
    fi
  fi

  if ! command -v brew &>/dev/null; then
    drift "Homebrew not installed"
    if ! $DRY_RUN; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if [[ $(uname -m) == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      else
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    fi
  fi
}

# Module: Brew (install packages with drift detection)
setup_brew() {
  if ! command -v brew &>/dev/null; then
    error "Homebrew not installed. Run: ./setup.sh core"
  fi

  if brew bundle check --file="$DOTFILES_DIR/Brewfile" &>/dev/null; then
    info "Brewfile: no drift"
  else
    drift "Brewfile has missing packages:"
    brew bundle check --file="$DOTFILES_DIR/Brewfile" --verbose 2>&1 | grep -v "^Homebrew Bundle"
    if ! $DRY_RUN; then
      echo ""
      read -rp "Install missing packages? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        brew bundle --file="$DOTFILES_DIR/Brewfile" || warn "Some packages failed (mas apps may need manual install)"
      fi
    fi
  fi
}

# Module: mise-managed runtimes and CLIs
# Language runtimes and most GitHub-released CLIs live in .config/mise/config.toml.
# Python-based CLIs (e.g. thefuck) are tracked in the Brewfile as `uv "..."` entries
# and installed by `brew bundle` — so setup_brew handles those.
setup_tools() {
  if ! command -v mise &>/dev/null; then
    error "mise not installed. Run: ./setup.sh brew"
  fi

  local missing prunable
  missing=$(mise ls --missing) || error "mise ls --missing failed — check mise status"
  prunable=$(mise ls --prunable) || error "mise ls --prunable failed — check mise status"

  if [[ -z "$missing" && -z "$prunable" ]]; then
    info "mise: no drift"
  fi

  if [[ -n "$missing" ]]; then
    drift "mise has missing tools:"
    echo "$missing"
    if ! $DRY_RUN; then
      echo ""
      read -rp "Install missing tools? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        mise install || warn "mise install failed"
      fi
    fi
  fi

  if [[ -n "$prunable" ]]; then
    drift "mise has tools not in config (prunable):"
    echo "$prunable"
    if ! $DRY_RUN; then
      echo ""
      read -rp "Prune these? [y/N] " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        mise prune --yes || warn "mise prune failed"
      fi
    fi
  fi
}

# Module: Symlinks
setup_symlinks() {
  # Create config directories
  mkdir -p "$HOME/.config/ghostty" "$HOME/.config/mise" "$HOME/.config/zed" \
    "$HOME/.local/bin" "$HOME/.claude" "$HOME/.ssh" "$HOME/.playwright" "$HOME/Developer"

  # Symlink scripts from bin/
  if compgen -G "$DOTFILES_DIR/bin/*" >/dev/null; then
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
  symlink_with_diff "$DOTFILES_DIR/.playwright/cli.config.json" "$HOME/.playwright/cli.config.json"

  # SSH config (1Password agent) and allowed signers (ssh-based commit signing)
  for f in config allowed_signers; do
    symlink_with_diff "$DOTFILES_DIR/.ssh/$f" "$HOME/.ssh/$f"
  done

  # Claude commands and hooks directories (can't diff contents, so replace wholesale)
  symlink_dir "$DOTFILES_DIR/.claude/commands" "$HOME/.claude/commands"
  symlink_dir "$DOTFILES_DIR/.claude/hooks" "$HOME/.claude/hooks"

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
  local bash_path path
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

# Module: DNS (NextDNS daemon + Tailscale MagicDNS search domain)
setup_dns() {
  if ! command -v nextdns &>/dev/null; then
    warn "NextDNS not installed. Run: ./setup.sh brew"
    return 1
  fi

  # NextDNS config (profile + Tailscale forwarder)
  local current_profile
  current_profile=$(nextdns config 2>/dev/null | grep "^profile " | awk '{print $2}')
  if [[ -z "$current_profile" ]]; then
    drift "NextDNS profile not configured"
    if ! $DRY_RUN; then
      echo "  Find your profile ID at https://my.nextdns.io (the alphanumeric ID in the URL)"
      read -rp "  NextDNS profile ID: " profile_id
      [[ -z "$profile_id" ]] && error "Profile ID required"
      sudo nextdns config set -profile "$profile_id"
    fi
  fi

  # Tailscale MagicDNS forwarder
  local ts_domain
  ts_domain=$(/usr/local/bin/tailscale status --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['CurrentTailnet']['MagicDNSSuffix'])" 2>/dev/null || echo "")
  if [[ -n "$ts_domain" ]] && ! nextdns config 2>/dev/null | grep -q "forwarder.*$ts_domain"; then
    drift "NextDNS missing Tailscale forwarder for $ts_domain"
    $DRY_RUN || sudo nextdns config set -forwarder "${ts_domain}.=100.100.100.100"
  fi

  # Cache size
  if ! nextdns config 2>/dev/null | grep -q "cache-size 10MB"; then
    drift "NextDNS cache size not set to 10MB"
    $DRY_RUN || sudo nextdns config set -cache-size 10MB
  fi

  # Install and activate
  if ! $DRY_RUN; then
    sudo nextdns install 2>/dev/null || true
    sudo nextdns activate 2>/dev/null || true
  fi

  # NextDNS sudoers (passwordless for Raycast script)
  local sudoers="/etc/sudoers.d/nextdns"
  local sudoers_line="$USER ALL=(ALL) NOPASSWD: /opt/homebrew/bin/nextdns activate, /opt/homebrew/bin/nextdns deactivate, /opt/homebrew/bin/nextdns restart, /opt/homebrew/bin/nextdns status, $DOTFILES_DIR/bin/tailscale-search-domain, /usr/bin/dscacheutil -flushcache, /usr/bin/killall -HUP mDNSResponder"

  # Sudoers file is root-owned 0440, so reading it for content comparison needs
  # sudo. Dry-runs must never prompt for a password (would deadlock in pre-push
  # hooks with no TTY), so probe with `sudo -n` first: if creds are cached we
  # still catch content drift, otherwise we fall back to a soft report.
  write_sudoers() {
    echo "$sudoers_line" | sudo tee "$sudoers" >/dev/null
    sudo chmod 0440 "$sudoers"
  }

  if [[ ! -f "$sudoers" ]]; then
    drift "NextDNS sudoers not configured (passwordless commands)"
    $DRY_RUN || write_sudoers
  elif $DRY_RUN && ! sudo -n true 2>/dev/null; then
    info "NextDNS sudoers: exists (content not verified — no cached sudo)"
  elif [[ "$(sudo cat "$sudoers")" != "$sudoers_line" ]]; then
    drift "NextDNS sudoers content out of date"
    $DRY_RUN || write_sudoers
  fi

  # Tailscale search domain launchd plist (copy, not symlink -- launchd requirement)
  local plist="com.tailscale.searchdomain.plist"
  local src="$DOTFILES_DIR/$plist"
  local dst="/Library/LaunchDaemons/$plist"

  local rendered
  rendered=$(sed "s|__DOTFILES_DIR__|$DOTFILES_DIR|g" "$src")

  if ! echo "$rendered" | diff -q - "$dst" &>/dev/null 2>&1; then
    drift "Tailscale search domain plist out of date"
    if ! $DRY_RUN; then
      echo "$rendered" | sudo tee "$dst" >/dev/null
      sudo launchctl bootout system "$dst" 2>/dev/null || true
      sudo launchctl bootstrap system "$dst"
    fi
  fi

  info "DNS: done"
}

# Help
show_help() {
  cat <<EOF
Usage: ./setup.sh [--dry-run] [module...]

Flags:
  --dry-run   Report drift without changing anything

Modules:
  core      Install Xcode CLI tools and Homebrew
  brew      Install packages from Brewfile (with drift detection)
  tools     Install mise-managed runtimes/CLIs and uv-managed Python tools
  symlinks  Create dotfile symlinks (with drift detection)
  ssh       Verify 1Password SSH agent
  dns       NextDNS sudoers + Tailscale search domain plist
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
  local modules=()

  # Parse flags
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=true ;;
      *) modules+=("$arg") ;;
    esac
  done

  $DRY_RUN && info "=== DRY RUN (no changes) ==="

  # No args or `all` → run the canonical default list
  if [[ ${#modules[@]} -eq 0 ]] || [[ " ${modules[*]} " == *" all "* ]]; then
    modules=("${DEFAULT_MODULES[@]}")
  fi

  for module in "${modules[@]}"; do
    case "$module" in
      core) setup_core ;;
      brew) setup_brew ;;
      tools) setup_tools ;;
      symlinks) setup_symlinks ;;
      ssh) setup_ssh ;;
      dns) setup_dns ;;
      macos) setup_macos ;;
      help | -h | --help)
        show_help
        exit 0
        ;;
      *) error "Unknown module: $module. Run './setup.sh help' for usage." ;;
    esac
  done

  info "Done!"
}

main "$@"
