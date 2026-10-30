#!/bin/bash
# Checks maintenance runs after upgrading. They only report, never change
# anything, so a warning here is something to act on by hand.
#   audits.sh audit_name...
set -e

# shellcheck source=/dev/null
source "$(dirname "$(readlink -f "$0")")/common.sh"

# `mise prune` only removes orphaned versions tracked via configs; a tool
# installed with no config source lingers silently. `mise ls` renders the
# source config as the 3rd column, so a row with fewer than 3 columns is an
# undeclared install, cross-checked below against every config mise has seen
# (its state dir), not just the ones active in this cwd.
audit_mise_drift() {
  step "mise drift"
  local tracked drift="" name ver
  tracked=$(cat "$HOME/.local/state/mise/tracked-configs"/* 2>/dev/null) || true
  while read -r name ver _; do
    [[ -n "$name" ]] || continue
    grep -qF "$name" <<<"$tracked" || drift+="  - $name $ver"$'\n'
  done < <(mise ls 2>/dev/null | awk 'NF>0 && NF<3')
  if [[ -z "$drift" ]]; then
    ok "all mise installs declared"
  else
    warn "untracked mise installs (declare in config or uninstall):"
    printf '%s' "$drift" >&2
  fi
}

# A runtime pinned by an old project survives `mise prune` but stops getting security fixes.
audit_eol() {
  step "End-of-life runtimes"
  local tool product releases ver cycle eol found=false
  for tool in node python ruby go; do
    case $tool in node) product=nodejs ;; *) product=$tool ;; esac
    releases=$(curl -sf "https://endoflife.date/api/v1/products/$product/") || {
      warn "eol: could not fetch $product release data"
      continue
    }
    while read -r ver; do
      [[ -n "$ver" ]] || continue
      if [[ $tool == node ]]; then cycle=${ver%%.*}; else cycle=$(cut -d. -f1-2 <<<"$ver"); fi
      eol=$(jq -r --arg c "$cycle" '.result.releases[] | select(.name == $c and .isEol) | .eolFrom' <<<"$releases")
      [[ -n "$eol" ]] || continue
      found=true
      warn "$tool $ver is end-of-life since $eol: mise uninstall $tool@$ver, and bump the project that pins it"
    done < <(mise ls --installed --json "$tool" 2>/dev/null | jq -r '.[].version')
  done
  $found || ok "no end-of-life runtimes installed"
}

# Binaries no package manager owns are never upgraded; move them under mise or delete them.
audit_strays() {
  step "Unmanaged binaries"
  local f strays=""
  for f in "$HOME"/go/bin/* "$HOME"/.cargo/bin/* "$HOME"/.local/bin/*; do
    [[ -e "$f" || -L "$f" ]] || continue
    case $f in
      # agy updates itself; setup.sh compiles kbbl.
      "$HOME"/.cargo/bin/rustup | "$HOME"/.local/bin/agy* | "$HOME"/.local/bin/kbbl) continue ;;
    esac
    if [[ -L "$f" ]]; then
      [[ -e "$f" ]] || strays+="  - $f (dangling link)"$'\n'
    else
      strays+="  - $f"$'\n'
    fi
  done
  if [[ -z "$strays" ]]; then
    ok "every binary has an owner"
  else
    warn "unmanaged binaries (add to mise config or delete):"
    printf '%s' "$strays" >&2
  fi
}

run_listed "$@"
