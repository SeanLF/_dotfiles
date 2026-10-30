#!/bin/bash
# A side pane maintenance hands steps to, one at a time (src/dotfiles/lanes.py).
#   lane.sh FOLDER
# FOLDER/job holds the pane's title on its first line, then the command, one
# argument per line; "stop" alone ends the lane. The exit code goes to
# FOLDER/result. Bash rather than Python so Rex shows a shell in the pane.
dir=$1
title() { printf '\033]2;%s\a' "$1"; }

title idle
while :; do
  if [[ ! -f "$dir/job" ]]; then
    sleep 0.1
    continue
  fi
  name=$(head -1 "$dir/job")
  [[ "$name" == stop ]] && exit 0
  args=()
  while IFS= read -r arg; do args+=("$arg"); done < <(tail -n +2 "$dir/job")
  rm "$dir/job"
  # One step per screen: its full output stays in the step's log.
  printf '\033[H\033[2J\033[3J'
  title "$name"
  "${args[@]}"
  code=$?
  echo
  title idle
  echo "$code" >"$dir/result.tmp" && mv "$dir/result.tmp" "$dir/result"
done
