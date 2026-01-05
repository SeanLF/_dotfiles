# Path to your oh-my-zsh installation
if [ -d "$HOME/.oh-my-zsh" ]; then
  export ZSH="$HOME/.oh-my-zsh"

  # Theme disabled - starship handles prompt
  # ZSH_THEME="robbyrussell"

  # Plugins
  plugins=(
    git
    macos
    brew
    vscode
    docker
    docker-compose
    zsh-autosuggestions
    zsh-syntax-highlighting
  )

  source $ZSH/oh-my-zsh.sh
else
  echo "Oh-My-Zsh is not installed. Please install it from https://ohmyz.sh/"
fi


# User configuration
export LANG=en_US.UTF-8
export EDITOR='nano'

# Development path
export DEV_DIR="$HOME/Developer"

# Aliases
if command -v eza &> /dev/null; then
  alias ls="eza --icons --group-directories-first"
  alias ll="eza -lah --icons --group-directories-first"
else
  alias ls="ls -G"
  alias ll="ls -lha"
fi

alias dc='docker compose'
alias dcr='docker compose run --rm'
alias code='cursor'
online() {
  local timeout=${1:-60}
  local count=0
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  printf "Waiting for connection  "
  while ! curl -s --connect-timeout 2 1.1.1.1 >/dev/null 2>&1; do
    ((count++))
    if ((count >= timeout)); then
      printf "\r\033[K✗ Timed out after ${timeout}s\n"
      return 1
    fi
    printf "\b${spin:$((count%10)):1}"
    sleep 1
  done
  printf "\r\033[K✓ Online after ${count}s\n"
  osascript -e 'display notification "Internet accessible" with title "Network Status"'
}

# Starship prompt
if command -v starship &> /dev/null; then
  eval "$(starship init zsh)"
else
  echo "Starship is not installed. Please install it from https://starship.rs/"
fi

# Zoxide (smart cd)
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
else
  echo "Zoxide is not installed. Please install it from https://github.com/ajeetdsouza/zoxide"
fi

# thefuck (command correction)
if command -v thefuck &> /dev/null; then
  eval "$(thefuck --alias)"
else
  echo "Thefuck is not installed. Please install it from https://github.com/nvbn/thefuck"
fi

# atuin (command history)
if [ -d "$HOME/.atuin/bin" ]; then
  . "$HOME/.atuin/bin/env"
  eval "$(atuin init zsh)"
else
  echo "Atuin is not installed. Please install it from https://github.com/ellie/atuin"
fi

# mise (programming tool manager)
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh)"
else
  echo "Mise is not installed. Please install it from https://github.com/mise-app/mise"
fi

# Johnny Decimal navigation for Documents
jd() {
  local base_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents"

  if [[ "$1" =~ ^[0-9]{2}$ ]]; then
    # Navigate to category by first 2 digits
    local matches=$(fd -d 2 -t d "^${1}" "$base_dir" | sort)
    if [[ -n "$matches" ]]; then
      cd "$(echo "$matches" | head -n 1)"
    else
      echo "No matching category found: $1"
    fi
  else
    echo "Usage: jd <2-digit category number>"
    echo "Available categories:"
    fd -d 2 -t d "^[0-9]" "$base_dir" | sort
  fi
}

# Environment files
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"
[[ -f "$HOME/.langflow/uv/env" ]] && . "$HOME/.langflow/uv/env"

# Misc settings
export LESS="--mouse $LESS"

# Local settings that shouldn't be in the dotfiles repo
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local