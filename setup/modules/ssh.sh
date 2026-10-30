#!/bin/bash

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
