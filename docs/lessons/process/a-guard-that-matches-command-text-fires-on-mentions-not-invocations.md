---
title: A guard that matches command text fires on mentions, not just invocations, so writing about the rule trips the rule
date: 2026-07-28
category: process
problem_type: logic_error
module: hooks, tooling
severity: medium
applies_when:
  - Writing a PreToolUse hook or any pattern-matching command guard
  - Validating a command string before it executes
  - A guard blocks a command that only quotes or describes the thing it guards
tags: [hooks, guards, false-positive, quoting, shell, pretooluse]
---

# A guard that matches command text fires on mentions, not invocations

## The lesson

A guard that greps the raw command string cannot distinguish _running_ a
command from _talking about_ one. Every guard I wrote in one session had this
bug, in three separate forms, and each one blocked legitimate work:

1. **Quoted mention.** `echo "this rg -rn should be denied"` was denied. The
   guard saw `rg` and `-rn` and never asked whether they were inside a string.
2. **Multi-line quoted mention.** After stripping quotes with `sed`, a commit
   message describing the rule still tripped it, because `sed` is line-oriented
   and `[^"]*` does not span newlines. The fix is to fold newlines into a
   sentinel byte, strip, then unfold.
3. **Pre-expansion opacity.** A commit guard read `git commit -m "$MSG"` and
   validated the literal five characters `$MSG` against a Conventional Commits
   regex. Every variable-built message would have been permanently rejected.

The through-line: the hook receives the command as _text the model proposed_,
not as an executed process. Quoting, interpolation, and heredocs are all still
unresolved at that point.

## Guidance

- **Strip quoted regions before matching**, and do it newline-aware. `tr '\n'
'\001'` before `sed`, `tr` back after.
- **Anchor to command position.** Split on `;`, `|`, `&&`, `||` and require the
  tool name at the start of a segment, not anywhere in the string.
- **Skip what you cannot see.** If the argument contains `$` or a backtick, the
  real value is unknowable pre-expansion. Skip the check rather than validate a
  placeholder. A guard that pretends to validate is worse than one that admits
  it cannot.
- **Trial it against its own documentation.** The single best test case is a
  commit message describing the rule. If the guard survives being written
  about, it will survive most real usage.

## Generalisation

The failure is treating a _proposal_ as an _execution_. Anything inspecting an
instruction before it runs is reading source text, so every quoting and
expansion rule of the target language still applies and none of it has been
resolved yet. Write the guard expecting its own documentation to be the first
thing that trips it.

Related: [[validators-only-catch-the-corruption-they-were-told-about]],
[[a-default-reference-sweep-skips-hidden-and-ignored-files]].
