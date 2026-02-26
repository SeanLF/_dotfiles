#!/bin/bash
# System maintenance — run periodically to keep packages updated
set -e

if [[ -t 1 ]]; then
  bold='\033[1m' dim='\033[2m'
  red='\033[31m' green='\033[32m' yellow='\033[33m' blue='\033[34m'
  reset='\033[0m'
else
  bold='' dim='' red='' green='' yellow='' blue='' reset=''
fi

step() { echo -e "${bold}${blue}==> $1${reset}"; }
info() { echo -e "${dim}$1${reset}"; }
ok()   { echo -e "${green}$1${reset}"; }
warn() { echo -e "${yellow}$1${reset}" >&2; failures+=("$1"); }

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BREWFILE="$DOTFILES_DIR/Brewfile"
failures=()

# Bail early if offline
if ! online -q 5; then
  echo -e "${red}No network connectivity — skipping maintenance${reset}"
  exit 1
fi

step "Homebrew"
brew update || warn "brew update failed"
brew upgrade || warn "brew upgrade failed"
brew upgrade --cask || warn "brew upgrade --cask failed"
brew cleanup || warn "brew cleanup failed"

step "App Store"
mas upgrade || warn "mas upgrade failed (may need App Store login)"

# Workaround: claude update downloads the full binary (~200MB) even when
# already up-to-date. Check versions first to skip the download.
# https://github.com/anthropics/claude-code/issues/20808
step "Claude Code"
local_ver="$(claude --version 2>/dev/null | awk '{print $1}' || true)"
dist_url="$(curl -sI https://claude.ai/install.sh 2>/dev/null \
  | grep -i '^location:' | tr -d '\r' \
  | sed 's/^[Ll]ocation: //; s|/bootstrap\.sh$||')"
remote_ver="$(curl -sf "$dist_url/latest" 2>/dev/null || true)"
if [[ -z "$remote_ver" ]]; then
  warn "could not check latest Claude Code version, running claude update"
  claude update || warn "claude update failed"
elif [[ "$local_ver" == "$remote_ver" ]]; then
  ok "Claude Code is already up to date ($local_ver)"
else
  info "Claude Code $local_ver -> $remote_ver"
  claude update || warn "claude update failed"
fi
unset local_ver dist_url remote_ver

step "NextDNS CLI"
if ndns_out="$(nextdns upgrade 2>&1)"; then
  if echo "$ndns_out" | grep -q "Already on the latest"; then
    ok "NextDNS is already up to date ($(nextdns version | awk '{print $NF}'))"
  else
    echo "$ndns_out"
  fi
else
  echo "$ndns_out"
  warn "nextdns upgrade failed"
fi
unset ndns_out

step "mise"
mise upgrade || warn "mise upgrade failed"

step "tldr"
tldr --update || warn "tldr --update failed"

step "Brewfile"
if [[ -f "$BREWFILE" ]]; then
  brew bundle dump --file="$BREWFILE" --force --describe || warn "brew bundle dump failed"
  ok "Brewfile updated"
else
  warn "Brewfile not found at $BREWFILE"
fi

step "macOS updates"
softwareupdate --list 2>&1 | grep -v "^Software Update Tool" || true

echo ""
if [[ ${#failures[@]} -gt 0 ]]; then
  echo -e "${red}Finished with ${#failures[@]} warning(s):${reset}"
  for f in "${failures[@]}"; do echo -e "  ${yellow}- $f${reset}"; done
  exit 1
else
  ok "Done -- all clear!"
fi
