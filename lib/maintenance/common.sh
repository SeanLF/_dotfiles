#!/bin/bash
# Helpers upgrades.sh and audits.sh share; sourced, not run.

# mise's shims pick the tool version at each call. `mise env` isn't enough: in
# a pane Rex starts, it appends tool paths after /usr/bin, so Apple's gem won.
export PATH="$HOME/.local/share/mise/shims:$PATH"

if [[ -t 1 ]]; then
  bold='\033[1m' dim='\033[2m'
  green='\033[32m' yellow='\033[33m'
  reset='\033[0m'
else
  bold='' dim='' green='' yellow='' reset=''
fi

failures=()

step_started=""
step_done() {
  [[ -n "$step_started" ]] || return 0
  info "($((SECONDS - step_started))s)"
}
step() {
  step_done
  step_started=$SECONDS
  echo -e "${bold}$1${reset}"
}
info() { echo -e "${dim}$1${reset}"; }
ok() { echo -e "${green}$1${reset}"; }
warn() {
  echo -e "${yellow}$1${reset}" >&2
  failures+=("$1")
}

try() { "$@" || warn "$* failed"; }

# A pane maintenance opened shows its state in Rex's tab (OSC 7501). In
# the main pane rex-job reports instead, so this stays quiet there.
report_status() { # state [message] [kind]
  [[ -n "${MAINT_PANE:-}" && -n "${REX_BLOCK:-}" && -t 1 ]] || return 0
  local pairs="state=$1:app=maintenance"
  [[ -n "${2:-}" ]] && pairs+=":msg=$(printf '%s' "$2" | base64 | tr -d '\n')"
  [[ -n "${3:-}" ]] && pairs+=":kind=$3"
  printf '\033]7501;%s\a' "$pairs"
}

# Runs the named functions, then reports: warnings go to $MAINT_WARNINGS, one
# per line, and the exit status is 1 if there were any.
run_listed() {
  report_status working "${*//step_/}"
  local fn
  for fn in "$@"; do "$fn"; done
  step_done
  if ((${#failures[@]})); then
    if [[ -n "${MAINT_WARNINGS:-}" ]]; then printf '%s\n' "${failures[@]}" >>"$MAINT_WARNINGS"; fi
    report_status error "${#failures[@]} warning(s)"
    exit 1
  fi
  report_status "done"
}
