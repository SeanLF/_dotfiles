---
title: The dangerous flag collisions are the ones that succeed, because a wrong flag that errors costs a second and a wrong flag that works costs a wrong conclusion
date: 2026-07-28
category: best-practices
module: tooling
problem_type: silent_regression
severity: high
applies_when:
  - Carrying muscle memory for short flags between similar tools
  - A command exits 0 with output that looks plausible but reads oddly
  - Deciding which tool misuse deserves a guardrail
tags: [ripgrep, grep, flags, silent-failure, exit-code, guardrails]
---

# The dangerous flag collisions are the ones that succeed

## The lesson

`rg` and `grep` assign different meanings to the same short flags. Two
collisions, both hit in a single session, with completely different costs:

| flag | `grep`          | `rg`        | failure mode                         |
| ---- | --------------- | ----------- | ------------------------------------ |
| `-h` | `--no-filename` | `--help`    | prints the manual. Obviously wrong.  |
| `-r` | `--recursive`   | `--replace` | prints rewritten text at **exit 0**. |

`rg -h '^#{2,3} '` returned ripgrep's help text instead of headings. Wrong,
noticed in one second, corrected, zero cost.

`rg -rn 'pattern' file` is the same class of mistake and is genuinely
dangerous. `-r` consumes `n` as the replacement string, so the output is the
matched lines _rewritten_, at exit 0, with no warning. A wrong identifier comes
back looking exactly like a real finding and feeds straight into the next edit.

Note the root cause is not an exotic environment. `rg` is stock ripgrep, and
`grep -rn pattern .` is one of the most common invocations in existence. The
collision is ordinary; only the consequence is not.

## Guidance

Rank misuse by **what happens when you get it wrong**, not by how likely it is:

- **Fails loudly**: no guardrail needed. The error is the guardrail.
- **Succeeds wrongly**: this is where a hard block earns its cost, because
  nothing downstream will ever tell you.

For `rg` specifically: recursion is already the default, so the `r` carried over
from `grep -rn` is not merely wrong, it is _redundant_. Drop it and use `rg -n`.

## Generalisation

When adopting a replacement tool, the short flags are the highest-risk surface,
because they are the part you type from memory rather than look up. Audit them
for the ones that will silently succeed, and guard only those. Guarding the
loud failures adds friction and buys nothing.

Related: [[a-default-reference-sweep-skips-hidden-and-ignored-files]],
[[a-tool-that-exits-zero-may-have-written-nothing]].
