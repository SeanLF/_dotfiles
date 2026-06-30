#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Keyboard Backlight Down
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔅
# @raycast.packageName System

# Dim the keyboard backlight via HID illumination events (see ~/.local/bin/kbbl).
exec "$HOME/.local/bin/kbbl" down 1
