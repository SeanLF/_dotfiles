## Tooling philosophy

- Brew: system-binary overrides (bash, curl, git, grep, sed, make, etc.) and tools with no macOS upstream
- mise: commodity CLIs (aqua backend preferred for verification)
- Prefer purpose-built replacements (eza, bat, ripgrep, fd) over coreutils; its gnubin stays off PATH
