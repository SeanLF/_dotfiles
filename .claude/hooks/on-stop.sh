#!/bin/bash
# Stop: the review gate decides first, and only a turn that really ends notifies.
# Two parallel Stop hooks sent "finished" while the gate sent Claude back to work.
set -uo pipefail

input=$(cat)
out=$(printf '%s' "$input" | "${REVIEW_GATE_BIN:-$HOME/Developer/_dotfiles/bin/review-gate}" --stop 2>/dev/null)
if [ -n "$out" ]; then
  printf '%s\n' "$out"
  exit 0
fi
printf '%s' "$input" | "${NOTIFY_BIN:-$(dirname "$0")/notify.sh}" 'done'
exit 0
