#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Keyboard Backlight Down
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔅
# @raycast.packageName System

exec "$HOME/.local/bin/kbbl" down 1
