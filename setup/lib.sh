#!/bin/bash
# Helpers every setup module uses; sourced by setup.sh.

BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# Moves a pre-existing file/dir to ~/.dotfiles-backup/<timestamp>/ before we
# clobber it. Guards against a path escaping the backup root via a leading slash.
backup() {
  local path="$1"
  if [[ "$path" != "$HOME/"* ]]; then
    error "refusing to backup path outside \$HOME: $path"
  fi
  local rel="${path#"$HOME"/}"
  local dest="$BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  mv "$path" "$dest"
  info "  backed up to $dest"
}

# Silent success, loud failure
info() { echo "$1"; }
drift() { if $DRY_RUN; then echo "DRIFT: $1"; else echo "FIXING: $1"; fi; }
warn() { echo "WARNING: $1" >&2; }
error() {
  echo "ERROR: $1" >&2
  exit 1
}

# For directories where we can't diff contents (e.g. ~/.claude/commands).
symlink_dir() {
  local src="$1" dst="$2"

  if [[ -L "$dst" ]]; then
    [[ "$(readlink "$dst")" == "$src" ]] && return 0
    drift "$dst -> wrong target ($(readlink "$dst"), expected $src)"
    $DRY_RUN && return 0
    ln -sfn "$src" "$dst"
  elif [[ -e "$dst" ]]; then
    drift "$dst exists and is not a symlink"
    $DRY_RUN && return 0
    read -rp "  Back up and replace with symlink to $src? [y/N] " response
    [[ ! "$response" =~ ^[Yy]$ ]] && return 0
    backup "$dst" && ln -s "$src" "$dst"
  else
    drift "$dst missing"
    $DRY_RUN && return 0
    ln -s "$src" "$dst"
  fi
}

symlink_with_diff() {
  local src="$1" dst="$2"

  if [[ -L "$dst" ]]; then
    [[ "$(readlink "$dst")" == "$src" ]] && return 0
    drift "$dst -> wrong target ($(readlink "$dst"), expected $src)"
    $DRY_RUN && return 0
    ln -sf "$src" "$dst"
  elif [[ -e "$dst" ]]; then
    if diff -q "$src" "$dst" &>/dev/null; then
      drift "$dst exists (not a symlink, contents identical)"
      $DRY_RUN && return 0
      backup "$dst" && ln -s "$src" "$dst"
    else
      drift "$dst exists (not a symlink, contents differ)"
      $DRY_RUN && return 0
      diff "$src" "$dst" || true
      read -rp "  Back up and replace with symlink to $src? [y/N] " response
      [[ ! "$response" =~ ^[Yy]$ ]] && return 0
      backup "$dst" && ln -s "$src" "$dst"
    fi
  else
    drift "$dst missing"
    $DRY_RUN && return 0
    ln -s "$src" "$dst"
  fi
}
