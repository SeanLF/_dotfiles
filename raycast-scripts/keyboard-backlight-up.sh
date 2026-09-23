#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Keyboard Backlight Up
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔆
# @raycast.packageName System

# Native hotkey dispatch (Shortcuts/Services) is broken on macOS 27 beta, so
# this rides Raycast's event tap instead.
exec "$HOME/.local/bin/kbbl" up 1
