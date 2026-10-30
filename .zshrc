HISTSIZE=100000
SAVEHIST=100000
HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY

fpath=("/Users/sean/.local/share/zsh/site-functions" $fpath) # sentry-cli completion
autoload -Uz compinit && compinit

_brew_prefix="${HOMEBREW_PREFIX:-$(brew --prefix)}"
[[ -f "$_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# fzf keybindings (Ctrl+R for history, Ctrl+T for files, Alt+C for cd)
[[ -f "$_brew_prefix/opt/fzf/shell/key-bindings.zsh" ]] && source "$_brew_prefix/opt/fzf/shell/key-bindings.zsh"
[[ -f "$_brew_prefix/opt/fzf/shell/completion.zsh" ]] && source "$_brew_prefix/opt/fzf/shell/completion.zsh"
unset _brew_prefix

export LANG=en_CA.UTF-8
# bat and Claude Code both detect terminal background at runtime; set per-mode themes.
export BAT_THEME_DARK="Monokai Extended"
export BAT_THEME_LIGHT="Monokai Extended Light"
export EDITOR='nano'
export PLAYWRIGHT_MCP_CONFIG="$HOME/.playwright/cli.config.json"
export DEV_DIR="$HOME/Developer"
export LESS="--mouse $LESS"
# Keep the `=`: BUN_OPTIONS reaches every bun, and `--preload <path>` breaks `bun install`.
export BUN_OPTIONS="${BUN_OPTIONS:+$BUN_OPTIONS }--preload=$HOME/.claude/hooks/no-agent-summary.js"
# Override ancient macOS system tools with current GNU/Homebrew versions
_hp="${HOMEBREW_PREFIX:-/opt/homebrew}"
export PATH="$_hp/opt/curl/bin:$_hp/opt/grep/libexec/gnubin:$_hp/opt/findutils/libexec/gnubin:$_hp/opt/gnu-sed/libexec/gnubin:$_hp/opt/make/libexec/gnubin:$HOME/.local/bin:$PATH"
unset _hp

[[ -f ~/.aliases.zsh ]] && source ~/.aliases.zsh

# mise must activate before starship/zoxide (both mise-managed): until mise
# injects its shim dir into PATH, `command -v starship` fails and the prompt
# falls back to bare zsh until the next shell.
command -v mise &>/dev/null && eval "$(mise activate zsh)"
command -v starship &>/dev/null && eval "$(starship init zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# Local overrides (not tracked in dotfiles)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
