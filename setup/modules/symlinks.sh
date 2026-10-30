#!/bin/bash

setup_symlinks() {
  mkdir -p "$HOME/.config/ghostty" "$HOME/.config/mise" "$HOME/.config/zed" \
    "$HOME/.local/bin" "$HOME/.claude" "$HOME/.codex/rules" "$HOME/.gemini" \
    "$HOME/.ssh" "$HOME/.playwright" "$HOME/Developer"

  if compgen -G "$DOTFILES_DIR/bin/*" >/dev/null; then
    for script in "$DOTFILES_DIR"/bin/*; do
      symlink_with_diff "$script" "$HOME/.local/bin/$(basename "$script")"
    done
  fi

  # brew's libarchive is keg-only and names its tar bsdtar; same flags as Apple's, newer.
  symlink_with_diff "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/libarchive/bin/bsdtar" "$HOME/.local/bin/tar"
  symlink_with_diff "$DOTFILES_DIR/.zprofile" "$HOME/.zprofile"
  symlink_with_diff "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
  symlink_with_diff "$DOTFILES_DIR/aliases.zsh" "$HOME/.aliases.zsh"
  symlink_with_diff "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
  symlink_with_diff "$DOTFILES_DIR/.gitignore_global" "$HOME/.gitignore_global"
  symlink_with_diff "$DOTFILES_DIR/.config/starship.toml" "$HOME/.config/starship.toml"
  symlink_with_diff "$DOTFILES_DIR/.config/ghostty/config" "$HOME/.config/ghostty/config"
  symlink_with_diff "$DOTFILES_DIR/.config/mise/config.toml" "$HOME/.config/mise/config.toml"
  symlink_with_diff "$DOTFILES_DIR/.config/zed/settings.json" "$HOME/.config/zed/settings.json"
  symlink_with_diff "$DOTFILES_DIR/.config/ccl/models.ini" "$HOME/.config/ccl/models.ini"
  symlink_with_diff "$DOTFILES_DIR/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  symlink_with_diff "$DOTFILES_DIR/writing-style.md" "$HOME/.claude/writing-style.md"
  # AGENTS.md is the cross-CLI canonical; Antigravity reads it via the
  # hardcoded ~/.gemini/GEMINI.md path (inherited from the Gemini CLI era).
  symlink_with_diff "$DOTFILES_DIR/AGENTS.md" "$HOME/.codex/AGENTS.md"
  symlink_with_diff "$DOTFILES_DIR/.codex/rules/default.rules" "$HOME/.codex/rules/default.rules"
  symlink_with_diff "$DOTFILES_DIR/.codex/hooks.json" "$HOME/.codex/hooks.json"
  symlink_with_diff "$DOTFILES_DIR/AGENTS.md" "$HOME/.gemini/GEMINI.md"
  symlink_with_diff "$DOTFILES_DIR/.gemini/settings.json" "$HOME/.gemini/settings.json"
  symlink_with_diff "$DOTFILES_DIR/.playwright/cli.config.json" "$HOME/.playwright/cli.config.json"

  for f in config allowed_signers; do
    symlink_with_diff "$DOTFILES_DIR/.ssh/$f" "$HOME/.ssh/$f"
  done

  # Directories: can't diff contents, so replace wholesale.
  symlink_dir "$DOTFILES_DIR/.claude/commands" "$HOME/.claude/commands"
  symlink_dir "$DOTFILES_DIR/.claude/hooks" "$HOME/.claude/hooks"
  symlink_dir "$DOTFILES_DIR/.claude/agents" "$HOME/.claude/agents"
  symlink_dir "$DOTFILES_DIR/.claude/skills" "$HOME/.claude/skills"
  symlink_dir "$DOTFILES_DIR/.codex/agents" "$HOME/.codex/agents"

  info "Symlinks: done"
}
