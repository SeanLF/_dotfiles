#!/bin/bash

# Compiled into ~/.local/bin (real binary, not a symlink); rebuilds only
# when source is newer than the installed binary.
setup_kbbl() {
  local kbbl_src="$DOTFILES_DIR/setup/kbbl.swift" kbbl_bin="$HOME/.local/bin/kbbl"
  if [[ -f "$kbbl_src" ]]; then
    if ! command -v swiftc &>/dev/null; then
      warn "swiftc not found (Xcode CLT); skipping kbbl compile"
    elif [[ -x "$kbbl_bin" && ! "$kbbl_src" -nt "$kbbl_bin" ]]; then
      info "kbbl: up to date"
    elif $DRY_RUN; then
      info "would compile kbbl -> $kbbl_bin"
    elif swiftc -O "$kbbl_src" -o "$kbbl_bin"; then
      info "compiled kbbl -> $kbbl_bin"
    else
      warn "kbbl compile failed"
    fi
  fi
}
