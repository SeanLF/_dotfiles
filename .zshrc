# Path to your oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="robbyrussell"

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

# User configuration
export LANG=en_US.UTF-8
export EDITOR='vim'

# Development path
export DEV_DIR="$HOME/Developer"

# Aliases
alias ls="exa --icons --group-directories-first"
alias ll="exa -lah --icons --group-directories-first"
alias cat="bat"
alias find="fd"
alias grep="rg"
alias gs="git status"
alias gc="git commit"
alias gco="git checkout"
alias gp="git push"
alias gl="git pull"

# Add Visual Studio Code (code)
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# Starship prompt
eval "$(starship init zsh)"

# Zoxide (smart cd)
eval "$(zoxide init zsh)"

# thefuck (command correction)
eval "$(thefuck --alias)"

# Johnny Decimal navigation for Documents
jd() {
  local base_dir="$HOME/Documents"
  
  if [[ "$1" =~ ^[0-9]{2}$ ]]; then
    # Navigate to category by first 2 digits
    local matches=$(find "$base_dir" -maxdepth 2 -type d -name "$1*" | sort)
    if [[ -n "$matches" ]]; then
      cd "$(echo "$matches" | head -n 1)"
    else
      echo "No matching category found: $1"
    fi
  else
    echo "Usage: jd <2-digit category number>"
    echo "Available categories:"
    find "$base_dir" -maxdepth 2 -type d -name "[0-9]*" | sort
  fi
}

# Developer directory quick navigation
dev() {
  if [[ -z "$1" ]]; then
    cd "$DEV_DIR"
  else
    local matches=$(find "$DEV_DIR" -maxdepth 1 -type d -name "*$1*" | grep -v "^\." | sort)
    if [[ -n "$matches" ]]; then
      cd "$(echo "$matches" | head -n 1)"
    else
      echo "No matching directory found: $1"
    fi
  fi
}

# Local settings that shouldn't be in the dotfiles repo
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
