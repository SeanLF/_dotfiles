#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Keyboard Backlight Up
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔆
# @raycast.packageName System

# Brighten the keyboard backlight via HID illumination events (see ~/.local/bin/kbbl).
# Native hotkey dispatch (Shortcuts/Services) is broken on macOS 27 beta, so this
# rides Raycast's reliable event tap instead.
exec "$HOME/.local/bin/kbbl" up 1
