# History
HISTSIZE=100000
SAVEHIST=100000
HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY

# Completions
autoload -Uz compinit && compinit

# Plugins (via Homebrew)
_brew_prefix="${HOMEBREW_PREFIX:-$(brew --prefix)}"
[[ -f "$_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# fzf keybindings (Ctrl+R for history, Ctrl+T for files, Alt+C for cd)
[[ -f "$_brew_prefix/opt/fzf/shell/key-bindings.zsh" ]] && source "$_brew_prefix/opt/fzf/shell/key-bindings.zsh"
[[ -f "$_brew_prefix/opt/fzf/shell/completion.zsh" ]] && source "$_brew_prefix/opt/fzf/shell/completion.zsh"
unset _brew_prefix

# Environment
export LANG=en_CA.UTF-8
# bat and Claude Code both detect terminal background at runtime; set per-mode themes.
export BAT_THEME_DARK="Monokai Extended"
export BAT_THEME_LIGHT="Monokai Extended Light"
export EDITOR='nano'
export PLAYWRIGHT_MCP_CONFIG="$HOME/.playwright/cli.config.json"
export DEV_DIR="$HOME/Developer"
export LESS="--mouse $LESS"
export PATH="$HOME/.local/bin:$PATH"

# Aliases
[[ -f ~/.aliases.zsh ]] && source ~/.aliases.zsh

# Tool initialization.
# mise must activate BEFORE starship/zoxide because both are mise-managed
# (aqua:starship/starship, aqua:ajeetdsouza/zoxide) — until mise injects its
# shim directory into PATH, `command -v starship` silently fails and the
# prompt falls back to bare zsh until the next shell.
command -v mise &>/dev/null && eval "$(mise activate zsh)"
command -v starship &>/dev/null && eval "$(starship init zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# Environment files
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# Local overrides (not tracked in dotfiles)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
