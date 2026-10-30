#!/bin/bash
# The upgrades maintenance runs, one function per step; this file decides
# how to upgrade, maintenance decides when and in what order.
#   upgrades.sh [--check] step_name...      --check previews, changes nothing
set -e

CHECK_ONLY=false
if [[ "${1:-}" == --check ]]; then
  CHECK_ONLY=true
  shift
fi
# shellcheck source=/dev/null
source "$(dirname "$(readlink -f "$0")")/common.sh"

DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
BREWFILE="$DOTFILES_DIR/Brewfile"
RUBY_GEMS="$DOTFILES_DIR/ruby-global-gems"

# claude's TUI clears the screen when it sees a terminal, wiping the steps above it.
no_tty() {
  "$@" 2>&1 | cat
  return "${PIPESTATUS[0]}"
}

# brew's recorded version of a self-updating cask is stale once the app updates
# itself, so compare the bundle's own version; prints casks whose updater stalled.
lagging_casks() {
  local token want app have
  while IFS=$'\t' read -r token want app; do
    have=$(defaults read "/Applications/$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null) || continue
    want=${want%%[,-]*} have=${have%%-*}
    # Skips builds whose version isn't dotted numbers (nightlies, tip builds).
    [[ $want =~ ^[0-9]+(\.[0-9]+)*$ && $have =~ ^[0-9]+(\.[0-9]+)*$ && $want != "$have" ]] || continue
    [[ $(printf '%s\n%s\n' "$have" "$want" | sort -V | head -1) == "$have" ]] && echo "$token"
  done < <(brew info --cask --installed --json=v2 2>/dev/null |
    jq -r '.casks[] | select(.auto_updates) | [.token, .version, ([.artifacts[] | .app? // empty | .[] | strings][0] // empty)] | select(length == 3) | @tsv')
}

# token|app bundle|whether the cask runs a .pkg installer (needs sudo). Not
# tabs: they're IFS whitespace, so an empty app field would collapse away.
cask_apps() {
  brew info --cask --installed --json=v2 2>/dev/null |
    jq -r '.casks[] | [.token, ([.artifacts[] | .app? // empty | .[] | strings][0] // ""), ([.artifacts[] | keys[]] | any(. == "pkg" or . == "installer"))] | map(tostring) | join("|")'
}

# Brew redoing a self-updating cask reinstalls what the app already moved past.
export HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1
# Open shells load zsh modules from their own Cellar path on demand; deleting
# it breaks completion in every long-lived pane until it restarts.
export HOMEBREW_NO_CLEANUP_FORMULAE=zsh
# step_brew_update runs once; the formula and cask steps then run side by side.
export HOMEBREW_NO_AUTO_UPDATE=1

step_brew_update() {
  step "Homebrew update"
  try brew update
}

# Formulae first in the mise chain: brew upgrades mise itself.
step_brew_formulae() {
  step "Homebrew formulae"
  if $CHECK_ONLY; then
    brew outdated --formula || true
    return 0
  fi
  # --no-ask: brew upgrade defaults to prompting when a TTY is attached, which hangs unattended runs.
  try brew upgrade --formula --no-ask
}

# Casks to upgrade: brew's outdated list plus self-updating apps whose updater
# stalled. An app that's open is left for the next run, since brew would quit it.
step_brew_casks() {
  step "Homebrew casks"
  local token app pkg outdated plain=() pkgs=() running=()
  outdated=" $(brew outdated --cask --quiet 2>/dev/null | tr '\n' ' ') $(lagging_casks | tr '\n' ' ') "
  while IFS='|' read -r token app pkg; do
    [[ "$outdated" == *" $token "* ]] || continue
    if [[ -n "$app" ]] && pgrep -qf "/Applications/$app/Contents/MacOS/"; then
      running+=("$token")
    elif [[ "$pkg" == true ]]; then
      pkgs+=("$token")
    else
      plain+=("$token")
    fi
  done < <(cask_apps)

  if $CHECK_ONLY; then
    if ((${#plain[@]} + ${#pkgs[@]})); then info "casks to upgrade: ${plain[*]} ${pkgs[*]}"; fi
    if ((${#running[@]})); then info "open, would skip: ${running[*]}"; fi
    return 0
  fi
  if ((${#plain[@]})); then try brew upgrade --cask --greedy --no-ask "${plain[@]}"; fi
  if ((${#pkgs[@]})); then try brew upgrade --cask --greedy --no-ask "${pkgs[@]}"; fi
  if ((${#running[@]})); then info "skipped while open: ${running[*]}"; fi
}

# After every brew step: cleanup could delete what a running upgrade is using.
step_brew_tidy() {
  step "Homebrew cleanup"
  if $CHECK_ONLY; then
    info "(skipped in --check mode)"
    return 0
  fi
  try brew autoremove
  try brew cleanup
}

step_appstore() {
  step "App Store"
  if $CHECK_ONLY; then
    mas outdated || true
  else
    try mas upgrade
  fi
}

# Xcode prereleases only; stable Xcode is step_appstore's, so the two run apart. `--latest-prerelease`
# installs RCs too, so prerelease_re must also match "release candidate" or an
# installed RC would look like a fresh one is available.
step_xcodes() {
  step "Xcode (xcodes)"
  command -v xcodes &>/dev/null || {
    info "xcodes not installed, skipping"
    return
  }
  # Silenced: `xcodes update` prints all ~285 versions; re-read via `xcodes list` below.
  xcodes update >/dev/null 2>&1 || warn "xcodes update failed"

  # Anchor on a leading version number to skip blanks and the list's footer line.
  local list prerelease_re latest_pre
  prerelease_re="beta|release candidate"
  list=$(xcodes list 2>/dev/null)
  latest_pre=$(echo "$list" | grep -iE "^[0-9].*($prerelease_re)" | tail -1)

  # Multi-GB download; guard the empty-parse case so a format drift in `xcodes
  # list` can't blank the "already newest" check and trigger a needless re-download.
  if [[ -z "$latest_pre" ]]; then
    warn "xcodes: could not parse a prerelease from 'xcodes list' (format change?)"
  elif xcodes installed 2>/dev/null | grep -qiE "$prerelease_re"; then
    if echo "$latest_pre" | grep -qi "installed"; then
      info "on latest prerelease: $latest_pre"
    elif $CHECK_ONLY; then
      info "newer prerelease available; would install: $latest_pre"
    elif [[ -z "${MAINT_UNATTENDED:-}" && -t 0 ]]; then
      info "upgrading to latest prerelease: $latest_pre"
      report_status blocked "Xcode prerelease needs Apple ID 2FA" auth
      try xcodes install --latest-prerelease
      report_status working
    else
      # xcodes needs interactive Apple ID 2FA; a headless run can't answer it,
      # so report instead of failing on every unattended sweep.
      info "newer prerelease available (run maintenance yourself; it needs Apple ID 2FA): $latest_pre"
    fi
  fi
}

# `claude update` re-downloads the full ~200MB binary even when already current;
# compare versions first to skip it.
step_claude_code() {
  step "Claude Code"
  local local_ver dist_url remote_ver
  local_ver="$(claude --version 2>/dev/null | awk '{print $1}' || true)"
  dist_url="$(curl -sI https://claude.ai/install.sh 2>/dev/null |
    grep -i '^location:' | tr -d '\r' |
    sed 's/^[Ll]ocation: //; s|/bootstrap\.sh$||')"
  remote_ver="$(curl -sf "$dist_url/latest" 2>/dev/null || true)"

  if [[ -z "$remote_ver" ]]; then
    warn "could not check latest Claude Code version, skipping"
  elif [[ "$local_ver" == "$remote_ver" ]]; then
    ok "Claude Code is already up to date ($local_ver)"
  else
    info "Claude Code $local_ver -> $remote_ver"
    $CHECK_ONLY || try no_tty claude update
  fi
}

# No `claude plugin update --all`; refresh marketplaces then loop each enabled plugin id.
step_claude_plugins() {
  step "Claude plugins/skills"
  command -v claude &>/dev/null || {
    info "claude not found, skipping"
    return
  }
  try no_tty claude plugin marketplace update
  if $CHECK_ONLY; then
    info "(check mode: marketplace refreshed; plugin updates skipped)"
    return
  fi
  command -v jq &>/dev/null || {
    warn "jq not found; skipping per-plugin updates"
    return
  }
  # Distinguish "list failed" from "genuinely zero enabled plugins", or a broken
  # CLI silently reads as nothing-to-do.
  local raw ids id
  if ! raw=$(claude plugin list --json 2>/dev/null); then
    warn "claude plugin list failed"
    return
  fi
  # Full "name@marketplace" id, not the bare name; `claude plugin update` needs it.
  # A plugin enabled at both user and project scope is listed twice, so dedupe.
  ids=$(jq -r '[.[] | select(.enabled) | .id] | unique[]' <<<"$raw" 2>/dev/null) || {
    warn "could not parse plugin list (format change?)"
    return
  }
  if [[ -z "$ids" ]]; then
    info "no enabled plugins to update"
    return
  fi
  while IFS= read -r id; do
    [[ -n "$id" ]] && try no_tty claude plugin update "$id"
  done <<<"$ids"
}

# agy self-updates in the background already, and re-fetches its full ~42MB
# tarball even when current; no step needed here.

step_mise() {
  step "mise"
  # Scoped to this step only: without GITHUB_TOKEN, mise's "latest" resolution
  # hits unauthenticated rate limits.
  local gh_token=""
  if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    gh_token="$(gh auth token)"
  fi
  if $CHECK_ONLY; then
    GITHUB_TOKEN="$gh_token" mise outdated || true
    return
  fi
  # mise exits 0 and reports "all up to date" even when a tool's latest version
  # couldn't be resolved; capture stderr to surface that silent skip.
  local log
  log=$(mktemp)
  GITHUB_TOKEN="$gh_token" mise upgrade 2>"$log" || warn "mise upgrade failed"
  cat "$log" >&2
  if grep -qE "Error getting latest version|Remote versions cannot be fetched" "$log"; then
    warn "mise: could not resolve the latest version of some tools; they were not upgraded"
  fi
  rm -f "$log"
  try mise prune --yes
}

step_uv() {
  step "uv tools"
  if $CHECK_ONLY; then
    uv tool list --outdated 2>/dev/null || uv tool list || true
  else
    # Release cooldown: poisoned uploads are usually yanked within days. uv
    # records the span in each tool's receipt, so it sticks to later upgrades.
    UV_EXCLUDE_NEWER="3 days" try uv tool upgrade --all
  fi
}

# mise's Ruby has no pkg-config metadata for its vendored openssl, so a gem
# with native extensions fails to build against it without the env vars set
# below. --with-openssl-dir after `--` forwards to every gem's extconf.rb;
# gems that don't need it ignore the unknown flag.
step_gems() {
  step "Ruby gems"
  command -v gem &>/dev/null || {
    info "gem not found, skipping"
    return
  }

  # Tool gems that must live in the Ruby gemset (see ruby-global-gems); mise
  # gives each Ruby its own empty gemset, so a new Ruby needs these reinstalled.
  # Project gems come from each repo's bundle, not here.
  local wanted=() line
  if [[ -f "$RUBY_GEMS" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="${line//[[:space:]]/}"
      [[ -n "$line" ]] && wanted+=("$line")
    done <"$RUBY_GEMS"
  fi

  if $CHECK_ONLY; then
    if ((${#wanted[@]})); then
      local installed missing=() g
      installed="$(gem list --no-versions || true)"
      for g in "${wanted[@]}"; do
        grep -qxF "$g" <<<"$installed" || missing+=("$g")
      done
      ((${#missing[@]})) && info "would install (missing host gems): ${missing[*]}"
    fi
    gem outdated || true
    return
  fi

  # `local -x`: scopes these exports to gem's child processes only, restored on return.
  local openssl_prefix="" ssl_args=()
  if command -v brew &>/dev/null; then
    openssl_prefix="$(brew --prefix openssl@3 2>/dev/null || true)"
  fi
  if [[ -n "$openssl_prefix" ]]; then
    local -x PKG_CONFIG_PATH="$openssl_prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    ssl_args=(-- --with-openssl-dir="$openssl_prefix")
  fi

  ((${#wanted[@]})) && try gem install --no-document --conservative "${wanted[@]}" "${ssl_args[@]}"
  try gem update "${ssl_args[@]}"
  try gem cleanup
}

# mise's `rust` plugin delegates to rustup for the stable toolchain, but rustup
# itself, other toolchains, and stale components only refresh via `rustup
# self update` / `rustup update`, which step_mise doesn't cover.
step_rustup() {
  step "rustup"
  command -v rustup &>/dev/null || {
    info "rustup not installed, skipping"
    return
  }
  if $CHECK_ONLY; then
    rustup check || true
  else
    try rustup self update
    try rustup update
  fi
}

step_tldr() {
  step "tldr"
  $CHECK_ONLY || try tldr --update
}

step_brewfile() {
  step "Brewfile"
  if $CHECK_ONLY; then
    info "(skipped in --check mode)"
  elif [[ -f "$BREWFILE" ]]; then
    try brew bundle dump --file="$BREWFILE" --force
    # This repo's own package, installed from the checkout by setup.sh tools; in
    # the Brewfile, brew bundle would try to install it from PyPI.
    grep -vx 'uv "seanfloyd-dotfiles"' "$BREWFILE" >"$BREWFILE.tmp" && mv "$BREWFILE.tmp" "$BREWFILE"
    ok "Brewfile updated"
  else
    warn "Brewfile not found at $BREWFILE"
  fi
}

# macOS installs its own updates (automatic install is on) and restarting is
# the user's call; this installs what needs no restart, like Command Line Tools.
step_macos() {
  step "macOS updates"
  local list label labels=()
  list=$(softwareupdate --list 2>&1)
  grep -E '^\* Label|Title:' <<<"$list" || info "no updates"
  while IFS= read -r label; do labels+=("$label"); done < <(awk '
    /^\* Label: / { if (l != "" && !r) print l; l = substr($0, 10); r = 0; next }
    /Action: restart/ { r = 1 }
    END { if (l != "" && !r) print l }' <<<"$list")
  ((${#labels[@]})) || return 0
  if $CHECK_ONLY; then
    info "would install: ${labels[*]}"
    return 0
  fi
  try sudo softwareupdate --install "${labels[@]}"
}

run_listed "$@"
