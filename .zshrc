HISTSIZE=100000
SAVEHIST=100000
HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY

fpath=("$HOME/.local/share/zsh/site-functions" $fpath) # sentry's completion (sentry cli completion zsh)
autoload -Uz compinit && compinit

# .zprofile runs `brew shellenv`, which sets HOMEBREW_PREFIX.
_hp="${HOMEBREW_PREFIX:-/opt/homebrew}"
[[ -f "$_hp/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$_hp/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# fzf keybindings (Ctrl+R for history, Ctrl+T for files, Alt+C for cd)
[[ -f "$_hp/opt/fzf/shell/key-bindings.zsh" ]] && source "$_hp/opt/fzf/shell/key-bindings.zsh"
[[ -f "$_hp/opt/fzf/shell/completion.zsh" ]] && source "$_hp/opt/fzf/shell/completion.zsh"

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
export PATH="$_hp/opt/curl/bin:$_hp/opt/file-formula/bin:$_hp/opt/grep/libexec/gnubin:$_hp/opt/findutils/libexec/gnubin:$_hp/opt/gnu-sed/libexec/gnubin:$_hp/opt/make/libexec/gnubin:$HOME/.local/bin:$PATH"

[[ -f ~/.aliases.zsh ]] && source ~/.aliases.zsh

# mise must activate before starship/zoxide (both mise-managed): until mise
# injects its shim dir into PATH, `command -v starship` fails and the prompt
# falls back to bare zsh until the next shell.
command -v mise &>/dev/null && eval "$(mise activate zsh)"
command -v starship &>/dev/null && eval "$(starship init zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# Local overrides (not tracked in dotfiles)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Must come last: its redraw hook has to run after any hook that edits the
# command line (zsh-autosuggestions, starship, local overrides).
[[ -f "$_hp/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$_hp/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
unset _hp
