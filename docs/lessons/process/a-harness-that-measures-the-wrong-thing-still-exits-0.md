---
title: A harness that measures the wrong thing still exits 0, so negative-control the instrument before believing its number
date: 2026-07-29
category: process
problem_type: logic_error
module: tooling, measurement
severity: high
applies_when:
  - Reporting a measured number from a script you just wrote
  - Validating a guard, hook, or migration against real history
  - A measurement confirms what you expected
tags:
  [measurement, negative-control, mutation-testing, harness, false-confidence]
---

# A harness that measures the wrong thing still exits 0

## The lesson

Four times in one session the finding was the instrument, not the subject. Each
time a command ran, exited 0, and produced a number that read as evidence.

1. **A regex that could not match.** Counting `python -c` uses with
   `'python3? -c[^"]{0,400}'`. The `[^"]` terminates at the quote that always
   follows `-c`, so it measured nothing and reported zero.
2. **A live process polluting the match.** `pgrep -f "Steer Dev.app/..."`
   matched the _diagnostic shell_ whose own argv contained that path, so the
   guard passed and `open -a` launched the app the guard exists to keep shut. I
   reported the guard as broken; the guard was fine.
3. **A stale copy of the thing under test.** The replay classifier kept the old
   `-[a-zA-Z]*i` regex after the hook's had changed, and scored a correct catch
   as a false positive.
4. **A metric insensitive to a known change.** The replay returned 98% / 0 FP
   _identically_ before and after two real defects were fixed, because the
   corpus contained neither form. Only noticing that non-movement revealed it.

Also: reading an example list as a distribution. The first six hits were sorted
by path, all from `subagents/`, so the failure looked delegated. Splitting it
showed direct conversations were twice as bad.

## Guidance

- **Break the subject on purpose and confirm the verdict flips.** This is
  mutation testing, and it catches all four cases above. If the number does not
  move when you knowingly change the thing, the number is not measuring it.
- **Control both branches.** A detector whose positive branch never fires is
  indistinguishable from a broken one. Two of these harnesses reported ~2%
  compliance; only a hand-built compliant fixture proved the branch worked at
  all.
- **Keep the classifier and the thing under test in sync,** or derive one from
  the other. Two copies of a regex drift silently.
- **Never read an ordered sample as a sample.** Sort order is not distribution.
- **History-based validation is blind to what history lacks.** The replay could
  not see `sed -ri` or `gsed -i` because no one had run them. Adversarial review
  found both; the corpus never would have.

## Generalisation

Verification has two claims in it, not one: _the subject behaves this way_, and
_this command can tell_. The second is a claim like any other and gets checked
the same way. "I ran a command" satisfies the letter of every verification rule
while leaving the load-bearing half untested, and it feels like more compliance
than asserting, not less.

Related:
[[a-guard-that-matches-command-text-fires-on-mentions-not-invocations]],
[[a-default-reference-sweep-skips-hidden-and-ignored-files]].
