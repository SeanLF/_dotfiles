#!/bin/bash

# Claude Code and Antigravity CLI ship as direct installers with no brew/mise
# path; they self-update at runtime, so this only handles first-time bootstrap
# (maintenance owns the upgrade path). agy's install.sh self-verifies via
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
