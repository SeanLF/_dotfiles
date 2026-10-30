#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Keyboard Backlight Up
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔆
# @raycast.packageName System

# Raycast, not a Shortcuts hotkey: those work again in macOS 27.2 but take
# a noticeable beat to fire, which is wrong for a key you tap repeatedly.
exec "$HOME/.local/bin/kbbl" up 1
