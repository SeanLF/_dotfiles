#!/bin/bash

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
    warn "Homebrew bash not found; run './setup.sh brew' first"
    warn "macOS defaults requires bash 4+ for associative arrays"
    return 1
  fi

  "$bash_path" "$macos_script"
}
