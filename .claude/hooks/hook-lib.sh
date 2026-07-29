#!/bin/bash
# Shared helpers for the PreToolUse Bash guards.
#
# Sourced, never executed. Every function here must be safe to call when the
# input is hostile or malformed, because the callers fail open.

# Remove quoted regions from a command string, tracking quote state properly.
#
# The obvious `sed "s/'[^']*'//g; s/\"[^\"]*\"//g"` is wrong: it pairs quotes by
# position, not by state. Given `echo "don't" && rg -rn foo` it pairs the
# apostrophe inside the double-quoted word with the next single quote in the
# line and deletes everything between, taking the real `rg` invocation with it.
# The guard then silently sees nothing to guard. Contractions are routine, so
# this fires often, and the failure mode is silence.
#
# Also drops heredoc bodies: everything from `<<` onward is data, not flags.
strip_quotes() {
  awk '
    # Drop heredoc BODIES only, line by line. Truncating at the first "<<"
    # instead would hide every command after the heredoc, so a `git commit`
    # following one would never be seen.
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

# Drop heredoc bodies but KEEP quotes. Detection wants quotes gone; message
# extraction needs them intact, since the quotes delimit the message itself.
strip_heredocs() {
  awk '
    {
      line = $0
      if (skip) {
        t = line; gsub(/^[ \t]+|[ \t]+$/, "", t)
        if (t == marker) skip = 0
        next
      }
      if (match(line, /<<-?[ \t]*[A-Za-z_"\x27][A-Za-z0-9_]*/)) {
        m = substr(line, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", m)
        gsub(/["\x27]/, "", m)
        marker = m; skip = 1
        line = substr(line, 1, RSTART - 1)
      }
      printf "%s\n", line
    }
  '
}

# A `git commit` invocation, as opposed to a mention of one or a different git
# subcommand that happens to contain the word. Only dash-options and the
# argument of -C/-c/--git-dir/--work-tree may sit between `git` and `commit`,
# so `git log --grep commit` does not match while `git -C /path commit` does.
is_git_commit() {
  printf '%s' "$1" | grep -qE '(^|[;&|][[:space:]]*)[[:space:]]*git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path)([= ])[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+commit([[:space:]]|$)'
}
