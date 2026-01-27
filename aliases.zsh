# File listing
if command -v eza &> /dev/null; then
  alias ls="eza --icons --group-directories-first"
  alias ll="eza -lah --icons --group-directories-first"
else
  alias ls="ls -G"
  alias ll="ls -lha"
fi

# Docker
alias dc='docker compose'
alias dcr='docker compose run --rm'

# Editor
alias code='zed'

# Git
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gco='git checkout'
alias gd='git diff'
alias gl='git pull'
alias gp='git push'
alias gst='git status'
alias gsw='git switch'

# Johnny Decimal navigation for Documents
jd() {
  local base_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents"
  local match

  if [[ "$1" =~ ^[0-9]{2}$ ]]; then
    match=$(fd -d 2 -t d "^${1}" "$base_dir" | sort | head -n 1)
    if [[ -n "$match" ]]; then
      cd "$match"
    else
      echo "No matching category found: $1"
    fi
  else
    echo "Usage: jd <2-digit category number>"
    echo "Available categories:"
    fd -d 2 -t d "^[0-9]" "$base_dir" | sort
  fi
}
