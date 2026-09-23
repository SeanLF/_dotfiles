#!/bin/bash
# Shared helpers for the PreToolUse Bash guards, sourced never executed.
# Every function here must be safe to call on hostile or malformed input,
# because the callers fail open.

# Removes quoted regions from a command string, tracking quote state (not
# pairing by position: `sed "s/'[^']*'//g"` on `echo "don't" && rg -rn foo`
# would pair the apostrophe in "don't" with the next quote and delete the
# real `rg` invocation with it). Also drops heredoc bodies.
strip_quotes() {
  awk '
    # Drops heredoc BODIES only, line by line; truncating at the first "<<"
    # would hide every command after the heredoc too.
    {
      line = $0
      if (skip) {
        t = line; gsub(/^[ \t]+|[ \t]+$/, "", t)
        if (t == marker) skip = 0
        next
      }
      if (match(line, /<<-?[ \t]*[A-Za-z_"'"'"'][A-Za-z0-9_]*/)) {
        m = substr(line, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", m)
        gsub(/["'"'"']/, "", m)
        marker = m; skip = 1
        line = substr(line, 1, RSTART - 1)
      }
      out = ""; q = ""
      n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (q == "") {
          if (c == "\"" || c == "'"'"'") { q = c } else { out = out c }
        } else if (c == q) {
          q = ""
        }
      }
      printf "%s\n", out
    }
  '
}

# Matches a real `git commit` invocation, not a mention or a different
# subcommand containing the word: only dash-options and -C/-c/--git-dir/
# --work-tree arguments may sit between `git` and `commit`, and `git` may
# carry a leading path, VAR=val assignments, or a sudo/command wrapper.
is_git_commit() {
  printf '%s' "$1" | grep -qE '(^|[;&|][[:space:]]*)[[:space:]]*[({]*[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((sudo|command|nohup|time)[[:space:]]+)*([^[:space:]]*/)?git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path)([= ])[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+commit([[:space:]]|$)'
}
