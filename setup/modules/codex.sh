#!/bin/bash

setup_codex() {
  local tool="$DOTFILES_DIR/bin/codex-config" out rc
  if out=$("$tool" --check 2>&1); then rc=0; else rc=$?; fi
  case "$rc" in
    0) info "codex config: no drift" ;;
    1)
      drift "codex config differs from .codex/config.toml:"
      printf '%s\n' "$out" | sed 's/^/  /'
      $DRY_RUN || "$tool" --apply
      ;;
    *)
      warn "codex-config failed (exit $rc): $out"
      return 1
      ;;
  esac

  if out=$("$tool" --hooks-trust 2>&1); then
    info "codex hooks: trust recorded for every handler"
  else
    echo "DRIFT: codex hooks with no recorded trust; run /hooks inside codex once:"
    printf '%s\n' "$out" | sed 's/^/  /'
  fi
}
