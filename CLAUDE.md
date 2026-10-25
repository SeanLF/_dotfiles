## Tooling philosophy

- Brew: system-binary overrides (bash, curl, git, grep, sed, make, etc.) and tools with no macOS upstream
- mise: commodity CLIs (aqua backend preferred for verification)
- Avoid shadowing with coreutils (its gnubin stays off PATH); prefer purpose-built replacements (eza, bat, ripgrep, fd)
