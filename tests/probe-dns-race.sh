#!/bin/bash
# Side-by-side resolver latency: the nextdns CLI at 127.0.0.1 against Tailscale
# at 100.100.100.100, one fresh name each every 2 s, with the en0 address so a
# network switch and each path's recovery line up in one log.
#
# Usage: tests/probe-dns-race.sh [logfile] [samples]   (default: stdout, 1800)
# Opt-in, costs upstream queries; not part of `just test`.
set -uo pipefail

LOG="${1:-/dev/stdout}"
MAX="${2:-1800}"

t() {
  local q
  q=$(dig +time=3 +tries=1 "@$1" "p$RANDOM$RANDOM.seanfloyd.dev" A +noall +stats 2>&1 |
    rg -o "Query time: [0-9]+" | rg -o "[0-9]+")
  echo "${q:-FAIL}"
}

for ((i = 0; i < MAX; i++)); do
  ip=$(ipconfig getifaddr en0 2>/dev/null || echo none)
  printf '%s en0=%s cli=%s ts=%s\n' "$(date '+%H:%M:%S')" "$ip" "$(t 127.0.0.1)" "$(t 100.100.100.100)" >>"$LOG"
  sleep 2
done
