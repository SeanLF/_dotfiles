#!/bin/bash

setup_core() {
  if ! xcode-select -p &>/dev/null; then
    drift "Xcode CLI tools not installed"
    if ! $DRY_RUN; then
      xcode-select --install
      until xcode-select -p &>/dev/null; do sleep 5; done
    fi
  fi

  # Compile with the Command Line Tools, so an App Store Xcode update can't
  # swap the compiler mid-build. Projects that need full Xcode set DEVELOPER_DIR.
  local clt="/Library/Developer/CommandLineTools"
  if [[ -d "$clt" && "$(xcode-select -p 2>/dev/null)" != "$clt" ]]; then
    drift "active developer directory is $(xcode-select -p), not $clt"
    $DRY_RUN || sudo xcode-select -s "$clt"
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
