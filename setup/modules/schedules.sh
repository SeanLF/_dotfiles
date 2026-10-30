#!/bin/bash

# Hourly attempts; each job decides for itself whether a run is due today, so
# an offline or busy hour just waits for the next one.
hourly_agent() { # name program [args...]
  local name="$1" args="" arg
  shift
  for arg in "$@"; do args+="<string>$arg</string>"; done
  local label="dev.seanfloyd.$name"
  local plist="$HOME/Library/LaunchAgents/$label.plist" want
  want=$(
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>$args</array>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$HOME/.local/share/mise/shims:$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartInterval</key><integer>3600</integer>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/$name.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/$name.log</string>
</dict>
</plist>
EOF
  )
  [[ -f "$plist" && "$(cat "$plist")" == "$want" ]] && return 0
  drift "$plist missing or out of date"
  $DRY_RUN && return 0
  mkdir -p "$(dirname "$plist")"
  printf '%s\n' "$want" >"$plist"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist" || warn "could not load $plist"
}

setup_schedules() {
  hourly_agent maintenance "$HOME/.local/bin/rex-job" --daily-when-idle maintenance -- "$HOME/.local/bin/maintenance"
  info "Schedules: done"
}
