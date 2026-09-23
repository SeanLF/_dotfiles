#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false

# Moves a pre-existing file/dir to ~/.dotfiles-backup/<timestamp>/ before we
# clobber it. Guards against a path escaping the backup root via a leading slash.
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

# Also what `all` runs; `macos` is opt-in only. `touchid` runs early so every
# later sudo (notably `dns`) is a fingerprint tap, not a password.
DEFAULT_MODULES=(core touchid brew symlinks codex tools ai_clis ssh dns)

# Silent success, loud failure
info() { echo "$1"; }
drift() { if $DRY_RUN; then echo "DRIFT: $1"; else echo "FIXING: $1"; fi; }
warn() { echo "WARNING: $1" >&2; }
error() {
  echo "ERROR: $1" >&2
  exit 1
}

# For directories where we can't diff contents (e.g. ~/.claude/commands).
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

# Language runtimes and most GitHub-released CLIs live in .config/mise/config.toml.
# Python-based CLIs (e.g. thefuck) are tracked in the Brewfile as `uv "..."` entries
# and installed by `brew bundle` — setup_brew handles those.
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

# Claude Code and Antigravity CLI ship as direct installers with no brew/mise
# path; they self-update at runtime, so this only handles first-time bootstrap
# (bin/maintenance owns the upgrade path). agy's install.sh self-verifies via
# sha512; Claude's installer doesn't verify upstream.
setup_ai_clis() {
  if command -v claude &>/dev/null; then
    info "claude: already installed"
  else
    drift "claude not installed"
    $DRY_RUN || curl -fsSL https://claude.ai/install.sh | bash || warn "claude install failed"
  fi

  if command -v agy &>/dev/null; then
    info "agy: already installed"
  else
    drift "agy not installed"
    $DRY_RUN || curl -fsSL https://antigravity.google/cli/install.sh | bash || warn "agy install failed"
  fi
}

setup_symlinks() {
  mkdir -p "$HOME/.config/ghostty" "$HOME/.config/mise" "$HOME/.config/zed" \
    "$HOME/.local/bin" "$HOME/.claude" "$HOME/.codex/rules" "$HOME/.gemini" \
    "$HOME/.ssh" "$HOME/.playwright" "$HOME/Developer"

  if compgen -G "$DOTFILES_DIR/bin/*" >/dev/null; then
    for script in "$DOTFILES_DIR"/bin/*; do
      symlink_with_diff "$script" "$HOME/.local/bin/$(basename "$script")"
    done
  fi

  # Compiled into ~/.local/bin (real binary, not a symlink); rebuilds only
  # when source is newer than the installed binary.
  local kbbl_src="$DOTFILES_DIR/setup/kbbl.swift" kbbl_bin="$HOME/.local/bin/kbbl"
  if [[ -f "$kbbl_src" ]]; then
    if ! command -v swiftc &>/dev/null; then
      warn "swiftc not found (Xcode CLT) — skipping kbbl compile"
    elif [[ -x "$kbbl_bin" && ! "$kbbl_src" -nt "$kbbl_bin" ]]; then
      info "kbbl: up to date"
    elif $DRY_RUN; then
      info "would compile kbbl -> $kbbl_bin"
    elif swiftc -O "$kbbl_src" -o "$kbbl_bin"; then
      info "compiled kbbl -> $kbbl_bin"
    else
      warn "kbbl compile failed"
    fi
  fi

  symlink_with_diff "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
  symlink_with_diff "$DOTFILES_DIR/aliases.zsh" "$HOME/.aliases.zsh"
  symlink_with_diff "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
  symlink_with_diff "$DOTFILES_DIR/.gitignore_global" "$HOME/.gitignore_global"
  symlink_with_diff "$DOTFILES_DIR/.config/starship.toml" "$HOME/.config/starship.toml"
  symlink_with_diff "$DOTFILES_DIR/.config/ghostty/config" "$HOME/.config/ghostty/config"
  symlink_with_diff "$DOTFILES_DIR/.config/mise/config.toml" "$HOME/.config/mise/config.toml"
  symlink_with_diff "$DOTFILES_DIR/.config/zed/settings.json" "$HOME/.config/zed/settings.json"
  symlink_with_diff "$DOTFILES_DIR/.config/ccl/models.ini" "$HOME/.config/ccl/models.ini"
  symlink_with_diff "$DOTFILES_DIR/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  symlink_with_diff "$DOTFILES_DIR/writing-style.md" "$HOME/.claude/writing-style.md"
  # AGENTS.md is the cross-CLI canonical; Antigravity reads it via the
  # hardcoded ~/.gemini/GEMINI.md path (inherited from the Gemini CLI era).
  symlink_with_diff "$DOTFILES_DIR/AGENTS.md" "$HOME/.codex/AGENTS.md"
  symlink_with_diff "$DOTFILES_DIR/.codex/rules/default.rules" "$HOME/.codex/rules/default.rules"
  symlink_with_diff "$DOTFILES_DIR/.codex/hooks.json" "$HOME/.codex/hooks.json"
  symlink_with_diff "$DOTFILES_DIR/AGENTS.md" "$HOME/.gemini/GEMINI.md"
  symlink_with_diff "$DOTFILES_DIR/.gemini/settings.json" "$HOME/.gemini/settings.json"
  symlink_with_diff "$DOTFILES_DIR/.playwright/cli.config.json" "$HOME/.playwright/cli.config.json"

  for f in config allowed_signers; do
    symlink_with_diff "$DOTFILES_DIR/.ssh/$f" "$HOME/.ssh/$f"
  done

  # Directories: can't diff contents, so replace wholesale.
  symlink_dir "$DOTFILES_DIR/.claude/commands" "$HOME/.claude/commands"
  symlink_dir "$DOTFILES_DIR/.claude/hooks" "$HOME/.claude/hooks"
  symlink_dir "$DOTFILES_DIR/.claude/agents" "$HOME/.claude/agents"
  symlink_dir "$DOTFILES_DIR/.claude/skills" "$HOME/.claude/skills"
  symlink_dir "$DOTFILES_DIR/.codex/agents" "$HOME/.codex/agents"

  info "Symlinks: done"
}

setup_codex() {
  local tool="$DOTFILES_DIR/bin/codex-config" out rc
  if out=$("$tool" --check 2>&1); then rc=0; else rc=$?; fi
  case "$rc" in
    0) info "codex config: no drift" ;;
    1)
      drift "codex config differs from .codex/config.toml:"
      printf '%s\n' "$out" | sed 's/^/  /'
      $DRY_RUN || "$tool" --apply
      ;;
    *)
      warn "codex-config failed (exit $rc): $out"
      return 1
      ;;
  esac

  if out=$("$tool" --hooks-trust 2>&1); then
    info "codex hooks: trust recorded for every handler"
  else
    echo "DRIFT: codex hooks with no recorded trust; run /hooks inside codex once:"
    printf '%s\n' "$out" | sed 's/^/  /'
  fi
}

setup_ssh() {
  local agent_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

  if [[ ! -S "$agent_sock" ]]; then
    warn "1Password SSH agent socket not found at: $agent_sock"
    warn "Ensure 1Password is installed and SSH agent is enabled in settings"
    return 1
  fi

  if SSH_AUTH_SOCK="$agent_sock" ssh-add -l &>/dev/null; then
    info "SSH: 1Password agent working"
  else
    warn "SSH: 1Password agent found but no keys available"
    warn "Check 1Password SSH settings"
  fi
}

# /etc/pam.d/sudo_local is Apple's supported include (Sonoma+); editing
# /etc/pam.d/sudo directly wouldn't survive macOS updates. The file is
# root-owned but world-readable, so we content-compare without sudo and only
# escalate to write.
setup_touchid() {
  local src="$DOTFILES_DIR/setup/sudo_local"
  local dst="/etc/pam.d/sudo_local"

  if [[ ! -f "$src" ]]; then
    warn "TouchID pam source not found: $src — skipping"
    return 0
  fi

  # BRE pattern: this runs before brew installs ugrep, so grep here is system
  # BSD grep on a fresh Mac.
  if ! grep -q 'auth.*include.*sudo_local' /etc/pam.d/sudo; then
    warn "/etc/pam.d/sudo does not include sudo_local — TouchID drop-in will be inert"
  fi

  if [[ -f "$dst" ]] && diff -q "$src" "$dst" &>/dev/null; then
    info "TouchID sudo: configured"
    return 0
  fi

  drift "TouchID sudo not enabled or drifted ($dst)"
  $DRY_RUN && return 0
  # install(1) writes atomically (temp + rename); safer than cp+chmod for an
  # auth-critical file that must never be truncated.
  sudo install -m 444 "$src" "$dst"
  info "TouchID sudo: enabled"
}

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

setup_dns() {
  local ts="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  if [[ ! -x "$ts" ]]; then
    warn "Tailscale.app not installed. Run: ./setup.sh brew"
    return 1
  fi

  # The tailnet policy decides the NextDNS profile per device; the Mac only has
  # to accept Tailscale's DNS settings.
  if ! "$ts" dns status 2>/dev/null | grep -q "Tailscale DNS: enabled"; then
    drift "Tailscale DNS not accepted (system resolver is not 100.100.100.100)"
    $DRY_RUN || "$ts" set --accept-dns=true
  fi

  # Passwordless cache flush for raycast-scripts/{toggle,fix}-dns.sh.
  local sudoers="/etc/sudoers.d/raycast-dns"
  local sudoers_line="$USER ALL=(ALL) NOPASSWD: /usr/bin/dscacheutil -flushcache, /usr/bin/killall -HUP mDNSResponder"

  # Dry-runs must never prompt for a password (would deadlock in pre-push
  # hooks with no TTY), so probe with `sudo -n` first.
  write_sudoers() {
    echo "$sudoers_line" | sudo tee "$sudoers" >/dev/null
    sudo chmod 0440 "$sudoers"
  }

  if [[ ! -f "$sudoers" ]]; then
    drift "Raycast DNS sudoers not configured (passwordless cache flush)"
    $DRY_RUN || write_sudoers
  elif $DRY_RUN && ! sudo -n true 2>/dev/null; then
    info "Raycast DNS sudoers: exists (content not verified — no cached sudo)"
  elif [[ "$(sudo grep -v '^#' "$sudoers")" != "$sudoers_line" ]]; then
    drift "Raycast DNS sudoers content out of date"
    $DRY_RUN || write_sudoers
  fi

  info "DNS: done"
}

show_help() {
  cat <<EOF
Usage: ./setup.sh [--dry-run] [module...]

Flags:
  --dry-run   Report drift without changing anything

Modules:
  core      Install Xcode CLI tools and Homebrew
  touchid   Enable TouchID for sudo (native prompt via pam_tid drop-in)
  brew      Install packages from Brewfile (with drift detection)
  tools     Install mise-managed runtimes/CLIs and uv-managed Python tools
  ai_clis   Install Claude Code and Antigravity CLI (direct installers)
  symlinks  Create dotfile symlinks (with drift detection)
  codex     Render ~/.codex/config.toml from .codex/config.toml; report untrusted hooks
  ssh       Verify 1Password SSH agent
  dns       Accept Tailscale DNS (NextDNS via tailnet policy) + Raycast sudoers
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
      core) setup_core ;;
      touchid) setup_touchid ;;
      brew) setup_brew ;;
      tools) setup_tools ;;
      ai_clis) setup_ai_clis ;;
      symlinks) setup_symlinks ;;
      codex) setup_codex ;;
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
