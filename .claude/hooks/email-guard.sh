#!/bin/bash
# Asks before a network call carries a personal @seanfloyd.dev address.
# APIs that want a contact (SEC EDGAR, Wikimedia, crates.io, ecosyste.ms
# mailto) get bots@seanfloyd.dev instead. Fails OPEN.
set -o pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
TEXT=$(echo "$INPUT" | jq -r '.tool_input.command // .tool_input.url // empty' 2>/dev/null) || exit 0
[ -z "$TEXT" ] && exit 0

DOMAIN="${EMAIL_GUARD_DOMAIN:-seanfloyd.dev}"
BOT="bots@$DOMAIN"
PERSONAL="[A-Za-z0-9._%+-]+@${DOMAIN//./\\.}"

personal_in() { printf '%s' "$1" | grep -oiE "$PERSONAL" | grep -viqx "$BOT"; }

personal_in "$TEXT" || exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [ "$TOOL" != "WebFetch" ]; then
  # Quotes are kept: the address usually sits inside one. A git segment
  # setting the author is the address going where it belongs.
  HIT=""
  while IFS= read -r seg; do
    personal_in "$seg" || continue
    is_git_commit "$seg" && continue
    HIT=1
    break
  done <<<"$(printf '%s' "$TEXT" | sed 's/&&/\n/g; s/||/\n/g; s/[;|]/\n/g')"
  [ -z "$HIT" ] && exit 0
  # A UA assigned in one segment and sent from another is still a send.
  printf '%s' "$TEXT" | grep -qiE 'curl|wget|https?://|requests\.|urllib|httpx|fetch\(|Net::HTTP|gh api' || exit 0
fi

jq -n --arg r "This sends Sean's personal address to a network service. For a User-Agent or mailto contact, use $BOT instead. Only send the personal address if Sean asked for it in this session." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}' \
  2>/dev/null
exit 0
