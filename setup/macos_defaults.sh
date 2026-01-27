#!/usr/bin/env bash
# Requires bash 4+ for associative arrays (macOS default is bash 3.x)
# Homebrew installs bash 5.x: /opt/homebrew/bin/bash
# macOS defaults with drift detection
# Source this file or run directly: ./macos_defaults.sh [--apply]

# Expected macOS defaults — domain:key=type:value
# Types: bool, int, float, string
declare -A EXPECTED=(
  # Finder
  ["com.apple.finder:ShowPathbar"]="bool:true"
  ["com.apple.finder:ShowStatusBar"]="bool:true"
  ["com.apple.finder:_FXSortFoldersFirst"]="bool:true"
  ["com.apple.finder:FXDefaultSearchScope"]="string:SCcf"  # Search current folder
  ["com.apple.finder:FXEnableExtensionChangeWarning"]="bool:false"

  # Keyboard
  ["NSGlobalDomain:KeyRepeat"]="int:2"
  ["NSGlobalDomain:InitialKeyRepeat"]="int:15"

  # Dock
  ["com.apple.dock:autohide"]="bool:true"
  ["com.apple.dock:show-recents"]="bool:false"

  # Dialogs — expand save/print panels by default
  ["NSGlobalDomain:NSNavPanelExpandedStateForSaveMode"]="bool:true"
  ["NSGlobalDomain:NSNavPanelExpandedStateForSaveMode2"]="bool:true"
  ["NSGlobalDomain:PMPrintingExpandedStateForPrint"]="bool:true"
  ["NSGlobalDomain:PMPrintingExpandedStateForPrint2"]="bool:true"

  # Text — disable smart quotes and dashes (interferes with code)
  ["NSGlobalDomain:NSAutomaticQuoteSubstitutionEnabled"]="bool:false"
  ["NSGlobalDomain:NSAutomaticDashSubstitutionEnabled"]="bool:false"

  # Trackpad — tap to click
  ["com.apple.AppleMultitouchTrackpad:Clicking"]="bool:true"
  ["com.apple.driver.AppleBluetoothMultitouch.trackpad:Clicking"]="bool:true"
)

# Normalize boolean representations to "true"/"false"
normalize_bool() {
  case "$1" in
    1|true|TRUE|yes|YES) echo "true" ;;
    0|false|FALSE|no|NO) echo "false" ;;
    *) echo "$1" ;;
  esac
}

# Read a default value, normalizing booleans
read_default() {
  local domain="$1" key="$2"
  local value
  value=$(defaults read "$domain" "$key" 2>/dev/null) || { echo "UNSET"; return; }
  normalize_bool "$value"
}

# Parse expected value format "type:value"
parse_expected() {
  local spec="$1"
  local type="${spec%%:*}"
  local value="${spec#*:}"

  [[ "$type" == "bool" ]] && normalize_bool "$value" || echo "$value"
}

# Check for drift
check_defaults() {
  local drifted=()

  for key in "${!EXPECTED[@]}"; do
    local domain="${key%%:*}"
    local name="${key##*:}"
    local expected
    expected=$(parse_expected "${EXPECTED[$key]}")
    local current
    current=$(read_default "$domain" "$name")

    if [[ "$current" != "$expected" ]]; then
      drifted+=("$domain $name: $current → $expected")
    fi
  done

  if [[ ${#drifted[@]} -gt 0 ]]; then
    echo "macOS defaults drift detected:"
    printf '  %s\n' "${drifted[@]}"
    echo ""
    read -p "Apply expected values? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      apply_defaults
    fi
  else
    echo "macOS defaults: no drift"
  fi
}

# Apply all defaults
apply_defaults() {
  echo "Applying macOS defaults..."

  for key in "${!EXPECTED[@]}"; do
    local domain="${key%%:*}"
    local name="${key##*:}"
    local spec="${EXPECTED[$key]}"
    local type="${spec%%:*}"
    local value="${spec#*:}"

    case "$type" in
      bool)   defaults write "$domain" "$name" -bool "$value" ;;
      int)    defaults write "$domain" "$name" -int "$value" ;;
      float)  defaults write "$domain" "$name" -float "$value" ;;
      string) defaults write "$domain" "$name" -string "$value" ;;
    esac
  done

  # Restart affected apps
  echo "Restarting Finder and Dock..."
  killall Finder Dock 2>/dev/null || true

  echo "macOS defaults applied"
  echo "Note: Some changes may require logout/restart to take effect"
}

# Run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --apply|-a)
      apply_defaults
      ;;
    --check|-c|"")
      check_defaults
      ;;
    *)
      echo "Usage: $0 [--check|--apply]"
      echo "  --check   Check for drift (default)"
      echo "  --apply   Apply defaults without prompting"
      exit 1
      ;;
  esac
fi
